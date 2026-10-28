<?php

namespace App\Services;

use App\Exceptions\ClosedFiscalYearException;
use App\Exceptions\NoOpenFiscalYearException;
use App\Exceptions\UnbalancedAccountingEntryException;
use App\Models\AccountingEntry;
use App\Models\AccountingEntryLine;
use App\Exceptions\EcritureVerrouilleeException;
use App\Models\FiscalYear;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Ticket 10.2 (Sprint 10) — POINT DE PASSAGE UNIQUE pour toute écriture
 * comptable (Document 02 §Services, Document 03 §Contraintes
 * applicatives). Aucun module (POS, Achats, Paie, Journal manuel...) ne
 * doit jamais créer directement une `AccountingEntry`/`AccountingEntryLine`
 * — toujours via ce service, jamais par un `Model::create()` isolé
 * ailleurs qui pourrait un jour oublier la contrainte d'équilibre.
 *
 * ⚠️ CONTRAINTE CRITIQUE, VÉRIFIÉE AVANT TOUT `save()` : la somme des
 * débits DOIT être rigoureusement égale à la somme des crédits. Toute
 * tentative de créer une écriture déséquilibrée est refusée avant
 * d'atteindre la base — `UnbalancedAccountingEntryException` levée,
 * aucune ligne partielle jamais persistée (comparaison avec arrondi au
 * centime pour absorber les imprécisions flottantes légitimes, jamais un
 * seuil plus large qui masquerait un vrai déséquilibre).
 *
 * Ce service NE COUVRE PAS la contrainte additionnelle "compte débité ≠
 * compte crédité" (Document 01 §6.3) — cette règle est spécifique à la
 * SAISIE MANUELLE au Journal Comptable (ticket 10.4, formulaire à 2
 * lignes explicites), pas à toute écriture générée automatiquement
 * (une écriture de vente multi-lignes peut légitimement toucher
 * plusieurs comptes de produits différents crédités face à un seul
 * compte de trésorerie débité — la contrainte "comptes distincts" n'a de
 * sens que pour une saisie manuelle à 2 lignes). Le composant du ticket
 * 10.4 devra appliquer cette vérification supplémentaire lui-même, en
 * plus de (jamais à la place de) l'équilibre vérifié ici.
 *
 * RETROCÂBLAGE DES MODULES EXISTANTS (POS, Achats, Paie, Dépenses...)
 * DÉLIBÉRÉMENT HORS PÉRIMÈTRE DE CE TICKET : chaque intégration
 * nécessite une décision de mapping SYSCOHADA propre à son type de
 * transaction (ex. vente → 531/701, achat → 601/401...) — ce travail
 * arrive progressivement à mesure que les écrans comptables eux-mêmes
 * sont construits (tickets 10.3 à 10.8), pas en un seul geste ici.
 * Documenté explicitement pour ne jamais être oublié en aval.
 */
class AccountingEntryService
{
    /**
     * Ticket 15.30 — L'exercice OUVERT qui couvre `$entryDate`, ou une exception.
     *
     * Extrait de `record()` pour que la règle « exercice absent ou clos = refus »
     * ait UN SEUL texte : `record()` l'applique à chaque écriture, et
     * `VerifySaleDateAction` l'interroge AVANT d'engager une vente datée (le
     * refus vient alors avant tout effet de bord, y compris pour un mode de
     * règlement qui ne produit aucune écriture).
     *
     * 🔴→✅ Ticket EX3 (R2) — LE FILET : aucun exercice ne couvre la date, mais c'est la première saisie de l'année qui
     * suit l'exercice ouvert le plus récent, et la tâche du 1er janvier n'a pas tourné → l'exercice est ouvert ICI, avant
     * tout refus (`OuvertureExerciceService::filet`). Sans lui, un cron absent bloquait la caisse jusqu'à la clôture.
     *
     * 🔴→✅ Ticket EX5 (R4) — messages réécrits, date au format JJ/MM/AAAA, mêmes au web et à l'envoi d'un poste.
     *
     * @throws NoOpenFiscalYearException  aucun exercice ne couvre la date
     * @throws ClosedFiscalYearException  l'exercice qui la couvre est clos
     */
    public function exerciceOuvertPour(string $entryDate): FiscalYear
    {
        $fiscalYear = $this->exerciceQuiCouvre($entryDate)
            ?? app(OuvertureExerciceService::class)->filet($entryDate);

        if (! $fiscalYear) {
            throw NoOpenFiscalYearException::pourDate($entryDate);
        }

        if ($fiscalYear->status !== 'ouvert') {
            throw ClosedFiscalYearException::forDate($entryDate, (int) $fiscalYear->year);
        }

        return $fiscalYear;
    }

    /**
     * Ticket EX5 (EF5, R4) — « exercice clos = rien ne s'y écrit », pour une saisie qui ne produit pas forcément
     * d'écriture : mouvement de stock (`AdjustStockAction`), fiche d'élevage (Q3), modification ou archivage d'une
     * dépense. Le motif R4 si un exercice CLOS couvre [$date], `null` sinon — une date qu'aucun exercice ne couvre n'est
     * pas refusée ici (une fiche ou un ajout de stock n'a pas besoin d'exercice ; l'écriture, s'il y en a une, passe par
     * `record()`, qui la refusera).
     */
    public function refusExerciceClos(string $date): ?string
    {
        $exercice = $this->exerciceQuiCouvre($date);

        return $exercice !== null && $exercice->status !== 'ouvert'
            ? ClosedFiscalYearException::message((int) $exercice->year, Carbon::parse($date)->format('d/m/Y'))
            : null;
    }

    /**
     * @throws ClosedFiscalYearException  un exercice clos couvre [$date]
     */
    public function refuserSiExerciceClos(string $date): void
    {
        $refus = $this->refusExerciceClos($date);

        if ($refus !== null) {
            throw new ClosedFiscalYearException($refus);
        }
    }

    /**
     * Ticket EX6 (EF7) — BORNE BASSE du calendrier d'une saisie qui passe une écriture (dépense, règlement,
     * remboursement, avance, vente datée) : le début du plus ancien exercice OUVERT, `null` s'il n'y en a aucun.
     * Indicative : [exerciceOuvertPour] reste le juge. Le poste en garde la copie (`ExerciceDeSaisie::premierJour`,
     * règle `ecriture`).
     */
    public function premierJourSaisissable(): ?string
    {
        $debut = FiscalYear::where('status', 'ouvert')->min('start_date');

        return $debut ? substr((string) $debut, 0, 10) : null;
    }

    /**
     * Ticket EX6 (EF7) — BORNE BASSE du calendrier d'une saisie jugée par [refusExerciceClos] seulement (ajout de
     * stock) : le lendemain du plus récent exercice CLOS, `null` s'il n'y en a aucun — un jour qu'aucun exercice ne
     * couvre reste admis. Copie au poste : `ExerciceDeSaisie::premierJour`, règle `closSeulement`.
     */
    public function premierJourHorsExerciceClos(): ?string
    {
        $fin = FiscalYear::where('status', '!=', 'ouvert')->max('end_date');

        return $fin ? Carbon::parse(substr((string) $fin, 0, 10))->addDay()->format('Y-m-d') : null;
    }

    private function exerciceQuiCouvre(string $date): ?FiscalYear
    {
        $jour = Carbon::parse($date)->format('Y-m-d');

        return FiscalYear::whereDate('start_date', '<=', $jour)
            ->whereDate('end_date', '>=', $jour)
            ->first();
    }

    /**
     * @param  array<int, array{account_id: string, cost_center_id?: ?string, debit?: float, credit?: float}>  $lines
     */
    public function record(
        array $lines,
        string $entryDate,
        ?string $reference = null,
        ?string $sourceType = null,
        ?string $sourceId = null,
    ): AccountingEntry {
        $totalDebit = round(array_sum(array_column($lines, 'debit')), 2);
        $totalCredit = round(array_sum(array_column($lines, 'credit')), 2);

        // Comparaison au centime près — absorbe les imprécisions flottantes
        // légitimes, jamais un seuil plus large qui masquerait un vrai écart.
        if (abs($totalDebit - $totalCredit) >= 0.01) {
            throw UnbalancedAccountingEntryException::forTotals($totalDebit, $totalCredit);
        }

        // ⚠️ Ticket 10.6 : résout l'exercice qui COUVRE RÉELLEMENT la date de
        // l'écriture (pas "le dernier exercice ouvert" appliqué aveuglément) —
        // sans cette correction, une écriture antidatée dans un exercice
        // désormais clos aurait pu être rattachée à tort au nouvel exercice
        // ouvert. Document 01 §6.6 point 4 : blocage serveur systématique.
        $fiscalYear = $this->exerciceOuvertPour($entryDate);

        return DB::transaction(function () use ($lines, $entryDate, $reference, $sourceType, $sourceId, $fiscalYear) {
            // Ticket 15.20a : le numéro est attribué ICI, dans la transaction et sous verrou, jamais
            // avant. Une référence saisie à la main (sans gabarit) est conservée telle quelle.
            if ($reference !== null && str_contains($reference, AccountingEntry::GABARIT_NUMERO)) {
                $reference = mb_substr(
                    preg_replace('/'.preg_quote(AccountingEntry::GABARIT_NUMERO, '/').'/', AccountingEntry::attribuerNumero($fiscalYear), $reference, 1),
                    0,
                    100,
                );
            }

            $entry = AccountingEntry::create([
                'fiscal_year_id' => $fiscalYear->id,
                'entry_date' => $entryDate,
                'reference' => $reference,
                'source_type' => $sourceType,
                'source_id' => $sourceId,
                'is_locked' => false,
                'is_active' => true,
            ]);

            foreach ($lines as $line) {
                AccountingEntryLine::create([
                    'entry_id' => $entry->id,
                    'account_id' => $line['account_id'],
                    'cost_center_id' => $line['cost_center_id'] ?? null,
                    'debit' => $line['debit'] ?? 0,
                    'credit' => $line['credit'] ?? 0,
                ]);
            }

            return $entry;
        });
    }

    /**
     * Saisie manuelle à 2 lignes (Journal Comptable, ticket 10.4) — ajoute
     * la contrainte "compte débité ≠ compte crédité" (Document 01 §6.3)
     * PAR-DESSUS l'équilibre déjà vérifié par `record()`, jamais à sa place.
     */
    public function recordManual(
        string $debitAccountId,
        string $creditAccountId,
        float $amount,
        string $entryDate,
        ?string $reference = null,
        ?string $costCenterId = null,
        // Ticket CP-2 — UUID de la demande du poste : posé en `source_id`, il rend la création idempotente.
        ?string $sourceId = null,
    ): AccountingEntry {
        if ($debitAccountId === $creditAccountId) {
            throw new \InvalidArgumentException('Le compte débité doit être différent du compte crédité.');
        }

        return $this->record(
            lines: [
                ['account_id' => $debitAccountId, 'cost_center_id' => $costCenterId, 'debit' => $amount, 'credit' => 0],
                ['account_id' => $creditAccountId, 'cost_center_id' => $costCenterId, 'debit' => 0, 'credit' => $amount],
            ],
            entryDate: $entryDate,
            reference: $reference,
            sourceType: 'manual',
            sourceId: $sourceId,
        );
    }

    /**
     * Modification d'une écriture manuelle existante (ticket 10.4) — MÊME
     * contrainte "compte débité ≠ compte crédité" que `recordManual()`,
     * jamais une seconde règle de validation qui pourrait diverger.
     * Remplace intégralement les 2 lignes existantes plutôt que de les
     * patcher en place — élimine tout risque de ligne orpheline si la
     * modification change le nombre ou l'ordre des comptes.
     */
    public function updateManual(
        AccountingEntry $entry,
        string $debitAccountId,
        string $creditAccountId,
        float $amount,
        string $entryDate,
        ?string $reference = null,
    ): AccountingEntry {
        if ($debitAccountId === $creditAccountId) {
            throw new \InvalidArgumentException('Le compte débité doit être différent du compte crédité.');
        }

        $this->verifierModifiable($entry);

        // 🔴→✅ TICKET EX5 (EF5) — LE DÉPLACEMENT D'UNE ÉCRITURE. Changer la date ne recalculait pas `fiscal_year_id` :
        // une écriture de 2027 déplacée au 15/12/2026 restait rattachée à 2027 (et à sa numérotation), y compris quand
        // 2026 était CLOS. La nouvelle date passe la règle de `record()` (exercice ouvert qui la couvre, motif R4), puis
        // une écriture ne change jamais d'exercice : la numérotation est par exercice (15.20a), et les états d'un
        // exercice se lisent par `fiscal_year_id`.
        $nouvelExercice = $this->exerciceOuvertPour($entryDate);
        if ($nouvelExercice->id !== $entry->fiscal_year_id) {
            $ancien = FiscalYear::find($entry->fiscal_year_id);
            throw new EcritureVerrouilleeException(
                "Une écriture ne change pas d'exercice : celle-ci appartient à l'exercice {$ancien?->year}. "
                ."Archivez-la, puis saisissez-la à nouveau dans l'exercice {$nouvelExercice->year}."
            );
        }

        DB::transaction(function () use ($entry, $debitAccountId, $creditAccountId, $amount, $entryDate, $reference) {
            $entry->lines()->delete();

            AccountingEntryLine::create(['entry_id' => $entry->id, 'account_id' => $debitAccountId, 'debit' => $amount, 'credit' => 0]);
            AccountingEntryLine::create(['entry_id' => $entry->id, 'account_id' => $creditAccountId, 'debit' => 0, 'credit' => $amount]);

            $entry->update(['entry_date' => $entryDate, 'reference' => $reference]);

            // Ticket 15.28 — LES LIGNES ONT ÉTÉ RECRÉÉES (nouveaux identifiants) : l'écriture a
            // changé, même si ni sa date ni sa référence n'ont bougé. Sans ce `touch()`, l'en-tête
            // n'est pas « sale », `updated_at` reste ancien et le tirage `since` du poste ne la
            // sert jamais : le poste garde les anciennes lignes, sans aucune erreur.
            $entry->touch();
        });

        return $entry->fresh('lines');
    }

    /**
     * Ticket EX4 / EX5 — ARCHIVAGE d'une écriture au Journal (`JournalComptable::archiveEntry`), avec les mêmes refus
     * que la modification : écriture verrouillée par la clôture, à-nouveau ou sa contre-passation, exercice clos.
     *
     * @throws EcritureVerrouilleeException|ClosedFiscalYearException
     */
    public function archiver(AccountingEntry $entry): void
    {
        $this->verifierModifiable($entry, 'archivée');

        $entry->update(['is_active' => false]);
    }

    /**
     * Ce qui interdit de toucher une écriture existante, quelle que soit la nouvelle saisie.
     *
     * 🔴→✅ TICKET EX4 (EF4, défaut É3) — L'À-NOUVEAU DE N+1 SE MODIFIAIT ET S'ARCHIVAIT AU JOURNAL. Il appartient à
     * N+1, exercice ouvert : la clôture de N ne le verrouille pas (`is_locked` ne vise que les écritures de N). Le
     * modifier ou l'archiver faisait diverger l'ouverture de N+1 de la clôture de N, sans aucune erreur. Il ne se
     * corrige que par la réouverture de N (15.53), qui le contre-passe — et la contre-passation est protégée de même.
     */
    public function verifierModifiable(AccountingEntry $entry, string $geste = 'modifiée'): void
    {
        if (in_array($entry->source_type, ['ran', 'ran_reversal'], true)) {
            $exercice = FiscalYear::find($entry->fiscal_year_id);
            $annee = (int) ($exercice?->year ?? $entry->entry_date->format('Y'));

            throw new EcritureVerrouilleeException(
                "L'écriture d'à-nouveau de l'exercice {$annee} est verrouillée : elle ne se modifie ni ne s'archive. "
                .'Pour la corriger, rouvrez l\'exercice '.($annee - 1).'.'
            );
        }

        if ($entry->is_locked) {
            throw new EcritureVerrouilleeException("Cette écriture est verrouillée (exercice clôturé) et ne peut plus être {$geste}.");
        }

        // Une écriture d'un exercice clos qui ne serait pas verrouillée (base antérieure à la clôture verrouillante).
        $this->refuserSiExerciceClos($entry->entry_date->format('Y-m-d'));
    }
}
