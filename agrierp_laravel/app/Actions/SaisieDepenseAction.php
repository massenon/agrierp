<?php

namespace App\Actions;

use App\Exceptions\DepenseNonModifiableException;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\Expense;
use App\Models\ExpenseLine;
use App\Models\TreasuryAccount;
use App\Services\AccountingEntryService;
use App\Services\ConversionDepensesEnLignes;
use App\Support\MotifsRefusPush;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Ticket U14 — POINT DE PASSAGE UNIQUE d'une dépense : création, modification, archivage.
 *
 * Ticket DEP1 (PRD `docs/prd/depenses-multilignes.md`) — UNE DÉPENSE, PLUSIEURS LIGNES. Le document reçu est :
 *   `expense_date`, `treasury_account_id`, `payment_mode?`, `cost_center_id?`, `supplier_id?`, `beneficiary?`,
 *   `lines` = [`id?`, `label`, `charge_account_id`, `amount`] (au moins une), `amount?` (le total annoncé : contrôlé).
 * Le total est la SOMME des lignes, jamais saisi : `expenses.amount` est écrit ICI, `expenses.label` est le résumé.
 *
 * ⚠️ COMPATIBILITÉ DES POSTES NON MIGRÉS (EF10) : le serveur est déployé AVANT les postes. Un document PLAT (`label`,
 * `category`, `amount`, sans `lines`) est accepté et converti en UNE ligne (compte de charge déduit de la catégorie,
 * identifiant de ligne = UUID v5 de la dépense : un renvoi retombe sur la même ligne).
 *
 * Règles :
 *  - création : `payee`, décaissée tout de suite (trésorerie − total) ; en-tête, lignes, écriture (un débit par compte,
 *    un crédit de trésorerie) et décaissement dans UNE transaction — une pièce refusée (exercice clos ou absent,
 *    déséquilibre, trésorerie sans compte du plan) annule TOUT, il ne reste ni dépense ni ligne ;
 *  - modification : réservée aux dépenses SANS pièce (reprise de l'ancien). Une dépense COMPTABILISÉE est IMMUABLE
 *    ([MESSAGE_DEJA_COMPTABILISEE]) : on la corrige par archivage (contre-passation) puis nouvelle saisie ;
 *  - EX5 : exercice clos (date d'origine ou nouvelle) → motif R4, avant toute écriture ;
 *  - archivage : contre-passation de l'écriture d'origine, datée du jour, trésorerie réintégrée, `is_active = false`.
 *
 * ⚠️ VERROUS : la dépense est relue SOUS VERROU (`lockForUpdate`) avant toute écriture, puis la trésorerie est touchée
 * — même ordre partout.
 */
class SaisieDepenseAction
{
    /**
     * 🔴→✅ Ticket U14 — le COMPTE DE TRÉSORERIE rejoint le montant et le compte de charge. Ticket DEP1 — une dépense
     * comptabilisée ne se modifie PLUS DU TOUT (le libellé non plus) : correction par contre-passation.
     */
    public const MESSAGE_DEJA_COMPTABILISEE = 'Cette dépense est déjà comptabilisée : elle ne peut plus être modifiée. Archivez-la (la charge est extournée et la trésorerie réintégrée), puis saisissez-la à nouveau.';

    public const MESSAGE_ARCHIVEE = 'Cette dépense est archivée : elle ne peut plus être modifiée.';

    public const ARCHIVEE = 'archivee';

    public const ARCHIVEE_SANS_ANNULATION = 'archivee_sans_annulation';

    public const DEJA_ARCHIVEE = 'deja_archivee';

    /** Libellés français des champs du document (messages de validation du web et de l'envoi des postes). */
    public static function attributs(): array
    {
        return [
            'expense_date' => 'date de la dépense', 'treasury_account_id' => 'compte de trésorerie',
            'payment_mode' => 'mode de paiement', 'cost_center_id' => 'centre de coût', 'supplier_id' => 'fournisseur',
            'beneficiary' => 'bénéficiaire', 'amount' => 'total', 'category' => 'catégorie', 'label' => 'libellé',
            'lines' => 'lignes', 'lines.*.id' => 'identifiant de la ligne', 'lines.*.label' => 'libellé de la ligne',
            'lines.*.charge_account_id' => 'compte de charge de la ligne', 'lines.*.amount' => 'montant de la ligne',
        ];
    }

    /** @return array<string, string> */
    public static function messages(): array
    {
        return [
            'lines.required' => 'Ajoutez au moins une ligne à la dépense.',
            'lines.min' => 'Ajoutez au moins une ligne à la dépense.',
            'lines.array' => 'Ajoutez au moins une ligne à la dépense.',
            'lines.*.charge_account_id.exists' => 'Le compte de charge de la ligne n\'existe pas au plan comptable (classe 6).',
            'lines.*.id.distinct' => 'Deux lignes de la dépense portent le même identifiant.',
        ];
    }

    /**
     * Met le document sous sa forme à lignes : un document PLAT d'un poste non migré devient UNE ligne ; le mode de
     * paiement manquant se déduit du type du compte de trésorerie. Ne valide rien.
     *
     * @param  array<string, mixed>  $donnees
     * @return array<string, mixed>
     */
    public function preparer(array $donnees, ?string $idDepense = null): array
    {
        if (! isset($donnees['lines']) || ! is_array($donnees['lines'])) {
            if (array_key_exists('label', $donnees) || array_key_exists('category', $donnees) || array_key_exists('amount', $donnees)) {
                $categorie = (string) ($donnees['category'] ?? '');
                $compte = $categorie !== '' && in_array($categorie, Expense::CATEGORIES, true)
                    ? ConversionDepensesEnLignes::compteDeLaCategorie($categorie)
                    : null;

                if ($compte === null) {
                    throw ValidationException::withMessages([
                        'category' => $categorie === '' ? 'Le champ catégorie est obligatoire.' : 'La valeur du champ catégorie n\'est pas autorisée.',
                    ]);
                }

                $donnees['lines'] = [[
                    'id' => $idDepense !== null ? ExpenseLine::idDeConversion($idDepense) : null,
                    'label' => $donnees['label'] ?? null,
                    'charge_account_id' => $compte->id,
                    'amount' => $donnees['amount'] ?? null,
                ]];
                $donnees['__plat'] = true;
                unset($donnees['amount']);
            }
        }

        if (empty($donnees['payment_mode']) && ! empty($donnees['treasury_account_id'])) {
            $donnees['payment_mode'] = TreasuryAccount::whereKey($donnees['treasury_account_id'])->value('type');
        }

        return $donnees;
    }

    /** Le document est-il celui, PLAT, d'un poste non migré (ni `lines`, mais `label` / `category` / `amount`) ? */
    private function estPlat(array $donnees): bool
    {
        return (! isset($donnees['lines']) || ! is_array($donnees['lines']))
            && (array_key_exists('label', $donnees) || array_key_exists('category', $donnees) || array_key_exists('amount', $donnees));
    }

    /**
     * Valide le document (mêmes règles pour le web, l'envoi d'un poste et le poste lui-même) et le rend normalisé.
     * [$pourLEnvoi] : les motifs sont ceux de l'envoi d'un poste (`MotifsRefusPush`), sinon ceux du web (`lang/fr`).
     *
     * @param  array<string, mixed>  $donnees
     * @return array<string, mixed>
     *
     * @throws ValidationException
     */
    public function valider(array $donnees, ?string $idDepense = null, bool $pourLEnvoi = false): array
    {
        $messages = ($pourLEnvoi ? MotifsRefusPush::messages() : []) + self::messages();
        $attributs = ($pourLEnvoi ? MotifsRefusPush::attributs() : []) + self::attributs();
        $commun = [
            'expense_date' => ['required', 'date'],
            'treasury_account_id' => ['required', 'exists:treasury_accounts,id'],
            'payment_mode' => ['nullable', Rule::in(array_keys(Expense::MODES_DE_PAIEMENT))],
            'cost_center_id' => ['nullable', 'exists:cost_centers,id'],
            'supplier_id' => ['nullable', 'exists:suppliers,id'],
            'beneficiary' => ['nullable', 'string', 'max:150'],
        ];

        // Un document PLAT d'un poste non migré : TOUTES ses erreurs d'abord (un seul motif complet), puis sa conversion.
        if ($this->estPlat($donnees)) {
            Validator::make($donnees, $commun + [
                'label' => ['required', 'string', 'max:255'],
                'category' => ['required', 'string', Rule::in(Expense::CATEGORIES)],
                'amount' => ['required', 'numeric', 'min:1'],
            ], $messages, $attributs)->validate();
        }

        $donnees = $this->preparer($donnees, $idDepense);
        $plat = ! empty($donnees['__plat']);

        $validateur = Validator::make($donnees, $commun + [
            'amount' => ['nullable', 'numeric'],
            'lines' => ['required', 'array', 'min:1'],
            'lines.*.id' => ['nullable', 'uuid', 'distinct'],
            'lines.*.label' => ['required', 'string', 'max:255'],
            'lines.*.charge_account_id' => ['required', Rule::exists('chart_of_accounts', 'id')->where(fn ($q) => $q->where('class', 6)->where('is_active', true))],
            // Montants ENTIERS (FCFA) ; seul un document plat d'un poste non migré garde l'ancienne tolérance (numérique).
            'lines.*.amount' => $plat ? ['required', 'numeric', 'min:1'] : ['required', 'integer', 'min:1'],
        ], $messages, $attributs);

        $validateur->after(function ($v) use ($donnees) {
            if ($v->errors()->isNotEmpty()) {
                return;
            }

            $compte = TreasuryAccount::find($donnees['treasury_account_id']);
            if ($compte && ! empty($donnees['payment_mode']) && $compte->type !== $donnees['payment_mode']) {
                $v->errors()->add('payment_mode', 'Le mode de paiement ne correspond pas au type du compte de trésorerie choisi.');
            }

            $somme = $this->total($donnees['lines']);
            if (isset($donnees['amount']) && $donnees['amount'] !== '' && abs((float) $donnees['amount'] - $somme) >= 0.01) {
                $v->errors()->add('amount', 'Le total de la dépense ('.number_format((float) $donnees['amount'], 0, ',', ' ').' FCFA) ne correspond pas à la somme de ses lignes ('.number_format($somme, 0, ',', ' ').' FCFA).');
            }
        });

        $validateur->validate();

        return $donnees;
    }

    /** @param  array<int, array<string, mixed>>  $lignes */
    private function total(array $lignes): float
    {
        return round(array_sum(array_map(fn ($l) => (float) $l['amount'], $lignes)), 2);
    }

    /** @param  array<int, array<string, mixed>>  $lignes */
    private function resume(array $lignes): string
    {
        return Str::limit(Expense::resume(array_map(fn ($l) => trim((string) $l['label']), $lignes)), 255, '');
    }

    /**
     * La « catégorie » conservée pour les postes anciens : le compte de la PREMIÈRE ligne, au libellé de l'ancienne
     * liste quand il y figure (« 601 - Aliments »), sinon « code - intitulé du plan ».
     *
     * @param  array<int, array<string, mixed>>  $lignes
     */
    private function categorieDeCompatibilite(array $lignes): ?string
    {
        $compte = ChartOfAccount::find($lignes[0]['charge_account_id'] ?? null);
        if ($compte === null) {
            return null;
        }

        foreach (Expense::CATEGORIES as $categorie) {
            if (str_starts_with($categorie, $compte->code.' - ')) {
                return $categorie;
            }
        }

        return Str::limit($compte->code.' - '.$compte->label, 100, '');
    }

    /** @param  array<int, array<string, mixed>>  $lignes */
    private function ecrireLesLignes(Expense $depense, array $lignes): void
    {
        foreach (array_values($lignes) as $i => $donneesLigne) {
            $ligne = new ExpenseLine();
            // ⚠️ `id` n'est pas remplissable : `create(['id' => …])` l'ignorerait en silence (piège 14.78).
            $ligne->id = ! empty($donneesLigne['id']) ? $donneesLigne['id'] : (string) Str::uuid();
            $ligne->fill([
                'expense_id' => $depense->id,
                'position' => $i,
                'label' => trim((string) $donneesLigne['label']),
                'charge_account_id' => $donneesLigne['charge_account_id'],
                'amount' => $donneesLigne['amount'],
            ]);
            $ligne->save();
        }
    }

    /**
     * @param  array<string, mixed>  $donnees  voir le docblock de la classe
     *
     * @throws ValidationException
     * @throws \App\Exceptions\DepenseNonComptabilisableException
     */
    public function creer(array $donnees, ?string $id = null, ?string $justificatif = null): Expense
    {
        $donnees = $this->valider($donnees, $id);

        // 🔴→✅ Ticket EX5 (EF5, EF6, R4) — un exercice CLOS est jugé AVANT tout effet. Un exercice ABSENT est jugé par
        // l'écriture (`record()`, filet R2 compris), DANS la transaction : rien n'est écrit.
        app(AccountingEntryService::class)->refuserSiExerciceClos($donnees['expense_date']);

        return DB::transaction(function () use ($donnees, $id, $justificatif) {
            $depense = new Expense();
            if ($id !== null) {
                $depense->id = $id;
            }
            $depense->fill([
                'expense_date' => $donnees['expense_date'],
                'label' => $this->resume($donnees['lines']),
                'category' => $this->categorieDeCompatibilite($donnees['lines']),
                'amount' => $this->total($donnees['lines']),
                'treasury_account_id' => $donnees['treasury_account_id'],
                'payment_mode' => $donnees['payment_mode'] ?? null,
                'cost_center_id' => $donnees['cost_center_id'] ?? null,
                'supplier_id' => $donnees['supplier_id'] ?? null,
                'beneficiary' => ($donnees['beneficiary'] ?? null) !== null && trim($donnees['beneficiary']) !== '' ? trim($donnees['beneficiary']) : null,
                'created_by' => auth()->id() ?? auth('sanctum')->id(),
                'receipt_path' => $justificatif,
                // Une dépense saisie est immédiatement décaissée : le compte débité est obligatoire.
                'status' => 'payee',
                'is_active' => true,
            ]);
            $depense->save();
            $this->ecrireLesLignes($depense, $donnees['lines']);
            AuditLog::record('expense.created', 'achats');

            // Débit Classe 6 (un par compte) / Crédit Classe 5 (CDC §1.4 [M2]). Refus ⇒ exception ⇒ tout est annulé.
            app(RecordExpenseAccountingEntryAction::class)->execute($depense);

            TreasuryAccount::where('id', $donnees['treasury_account_id'])->decrement('balance', $depense->amount);

            return $depense->fresh(['lines']);
        });
    }

    /**
     * Modifie une dépense SANS pièce (reprise de l'ancien) : les lignes sont remplacées, la trésorerie réajustée.
     *
     * @param  array<string, mixed>  $donnees
     *
     * @throws DepenseNonModifiableException
     * @throws ValidationException
     */
    public function modifier(string $id, array $donnees, ?string $justificatif = null): Expense
    {
        $donnees = $this->valider($donnees, $id);

        return DB::transaction(function () use ($id, $donnees, $justificatif) {
            $depense = Expense::query()->whereKey($id)->lockForUpdate()->firstOrFail();

            if (! $depense->is_active) {
                throw new DepenseNonModifiableException(self::MESSAGE_ARCHIVEE);
            }

            // 🔴→✅ Ticket EX5 (EF5) — une dépense d'un exercice CLOS ne se modifie plus (motif R4 de sa date), et ne passe
            // pas non plus dans un exercice clos.
            $ancienneDate = $depense->expense_date->format('Y-m-d');
            $nouvelleDate = Carbon::parse($donnees['expense_date'])->format('Y-m-d');
            app(AccountingEntryService::class)->refuserSiExerciceClos($ancienneDate);
            app(AccountingEntryService::class)->refuserSiExerciceClos($nouvelleDate);

            // ⚠️ UNE DÉPENSE COMPTABILISÉE EST IMMUABLE (14.33, DEP1) : la correction passe par l'archivage
            // (contre-passation) puis une nouvelle saisie.
            if ($depense->accounting_entry_id) {
                throw new DepenseNonModifiableException(self::MESSAGE_DEJA_COMPTABILISEE);
            }

            // Réajuste la trésorerie : annule l'ancien total, applique le nouveau.
            TreasuryAccount::where('id', $depense->treasury_account_id)->increment('balance', $depense->amount);
            $depense->lines()->delete();
            $depense->update([
                'expense_date' => $donnees['expense_date'],
                'label' => $this->resume($donnees['lines']),
                'category' => $this->categorieDeCompatibilite($donnees['lines']),
                'amount' => $this->total($donnees['lines']),
                'treasury_account_id' => $donnees['treasury_account_id'],
                'payment_mode' => $donnees['payment_mode'] ?? null,
                'cost_center_id' => $donnees['cost_center_id'] ?? null,
                'supplier_id' => $donnees['supplier_id'] ?? null,
                'beneficiary' => ($donnees['beneficiary'] ?? null) !== null && trim($donnees['beneficiary']) !== '' ? trim($donnees['beneficiary']) : null,
                'receipt_path' => $justificatif ?: $depense->receipt_path,
            ]);
            $this->ecrireLesLignes($depense, $donnees['lines']);
            AuditLog::record('expense.updated', 'achats');
            TreasuryAccount::where('id', $donnees['treasury_account_id'])->decrement('balance', $this->total($donnees['lines']));

            return $depense->fresh(['lines']);
        });
    }

    /**
     * @return string  [ARCHIVEE], [ARCHIVEE_SANS_ANNULATION] (écriture d'annulation non générée : à dire) ou
     *                 [DEJA_ARCHIVEE] (rien n'est refait : un second archivage ne réintègre pas une seconde fois)
     */
    public function archiver(string $id): string
    {
        return DB::transaction(function () use ($id) {
            $depense = Expense::query()->whereKey($id)->lockForUpdate()->firstOrFail();

            // 🔴→✅ Ticket U14 — un second archivage (double clic, page restée ouverte, renvoi d'un poste) réintégrait
            // une seconde fois le montant et contre-passait deux fois la charge.
            if (! $depense->is_active) {
                return self::DEJA_ARCHIVEE;
            }

            // 🔴→✅ Ticket EX5 (EF5) — une dépense d'un exercice CLOS ne s'archive plus. Motif R4 de sa date.
            app(AccountingEntryService::class)->refuserSiExerciceClos($depense->expense_date->format('Y-m-d'));

            // TICKET 14.33 — CONTRE-PASSATION, jamais suppression de l'originale : le grand livre est immuable.
            $annulation = app(RecordExpenseAccountingEntryAction::class)->reverse($depense);

            TreasuryAccount::where('id', $depense->treasury_account_id)->increment('balance', $depense->amount);
            $depense->update(['is_active' => false]);
            AuditLog::record('expense.archived', 'achats');

            return $depense->accounting_entry_id && ! $annulation ? self::ARCHIVEE_SANS_ANNULATION : self::ARCHIVEE;
        });
    }

    /**
     * Vrai si [$donnees] décrit exactement [$depense] (même jour, trésorerie, mode, centre de coût, fournisseur,
     * bénéficiaire, mêmes lignes — identifiant, libellé, compte, montant) : un renvoi par un poste d'une saisie déjà
     * reçue, à acquitter sans rien rejouer (IDEMPOTENCE).
     *
     * @param  array<string, mixed>  $donnees
     */
    public function identique(Expense $depense, array $donnees): bool
    {
        $donnees = $this->preparer($donnees, $depense->id);

        $vide = fn ($v) => ($v === null || $v === '') ? null : $v;
        $lignesRecues = collect($donnees['lines'] ?? [])->map(fn ($l) => [
            'id' => $l['id'] ?? null, 'label' => trim((string) $l['label']), 'compte' => $l['charge_account_id'],
            'montant' => round((float) $l['amount'], 2),
        ])->sortBy('id')->values()->all();
        $lignesConnues = $depense->lines()->get()->map(fn ($l) => [
            'id' => $l->id, 'label' => $l->label, 'compte' => $l->charge_account_id, 'montant' => round((float) $l->amount, 2),
        ])->sortBy('id')->values()->all();

        return $depense->expense_date?->format('Y-m-d') === Carbon::parse($donnees['expense_date'])->format('Y-m-d')
            && $depense->treasury_account_id === $donnees['treasury_account_id']
            && $vide($depense->payment_mode) === $vide($donnees['payment_mode'] ?? null)
            && $vide($depense->cost_center_id) === $vide($donnees['cost_center_id'] ?? null)
            && $vide($depense->supplier_id) === $vide($donnees['supplier_id'] ?? null)
            && $vide($depense->beneficiary) === $vide(isset($donnees['beneficiary']) ? trim((string) $donnees['beneficiary']) : null)
            && $lignesRecues === $lignesConnues;
    }
}
