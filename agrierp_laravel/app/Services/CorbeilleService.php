<?php

namespace App\Services;

use App\Actions\SaisieBandeAction;
use App\Models\AdministrativeDocument;
use App\Models\ArchivedDocument;
use App\Models\AttendanceRecord;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\CorbeilleOperation;
use App\Models\Correspondence;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\Employee;
use App\Models\Expense;
use App\Models\FeedRationStandard;
use App\Models\FeedType;
use App\Models\InternshipAbsence;
use App\Models\LivestockLot;
use App\Models\LivestockTransfer;
use App\Models\Product;
use App\Models\ProphylaxisScheduleStandard;
use App\Models\Quote;
use App\Models\Sale;
use App\Models\Supplier;
use App\Models\User;
use App\Models\VeterinaryRecord;
use App\Support\CleUnicite;
use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Tickets 14.55 puis ARC1 / ARC2 (PRD `docs/prd/archives.md`) — LA CORBEILLE : voir, RESTAURER, SUPPRIMER DÉFINITIVEMENT.
 *
 * Le projet impose depuis toujours l'archivage logique (`is_active = false`) plutôt que la suppression. Ce service est
 * le point de passage UNIQUE de la page web (`Livewire\Parametres\Corbeille`) ET de l'envoi du poste
 * (`SyncController::pushCorbeilleDemandes`) : une seule règle, jamais deux implémentations qui divergent.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  CE QUI N'ENTRE PAS DANS LA CORBEILLE (décisions 14.55, conservées)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * ⚠️⚠️ **LES ÉCRITURES COMPTABLES** : une écriture ne se supprime pas, elle se contre-passe. La faire réapparaître
 * modifierait un grand livre — possiblement d'un exercice clos — sans écriture de contrepartie : le Bilan cesserait
 * d'être équilibré.
 *
 * ⚠️ **LES COMPTES UTILISATEURS** : leur réactivation existe sur Gestion des Utilisateurs, avec son contrôle de rôle.
 * L'exposer ici créerait une seconde porte d'entrée.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  CE QUI EST VISIBLE MAIS NON RESTAURABLE (ARC1) — et DIT à l'écran
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 🔴→✅ **LES DÉPENSES.** Avant ARC1, « Restaurer » remettait `is_active = true` — or l'archivage d'une dépense
 * (`SaisieDepenseAction::archiver`) a CONTRE-PASSÉ son écriture ET réintégré son montant en trésorerie. Restaurée telle
 * quelle, la dépense réapparaissait sans sa charge au grand livre et sans son décaissement : la caisse était fausse du
 * montant. La restauration ne rejoue pas, et ne doit pas effacer la contre-passation : elle est INTERDITE (question
 * ARC-Q1 pour une restauration avec re-comptabilisation).
 *
 * **LES VENTES ANNULÉES** (stock réintégré) et **LES TRANSFERTS ANNULÉS** (sujets rendus aux deux bandes) : mêmes motifs.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  SUPPRESSION DÉFINITIVE — IRRÉVERSIBLE, donc prudente
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Conditions cumulatives : l'élément est ARCHIVÉ ; son type est ADMIS ; AUCUNE référence (clé étrangère, ou colonne
 * `<entité>_id` d'une autre table) ne le vise ; droit administrateur ; mot `SUPPRIMER`. Jamais une pièce ou un fait
 * comptable, zootechnique ou numéroté (dépense, vente, devis, avance, courrier, pointage, bande, soin, compte,
 * transfert). Chaque suppression est journalisée (`AuditLog corbeille.deleted` + `corbeille_operations`, qui garde le
 * TITRE de ce qui a été effacé).
 *
 * ⚠️ **LE TYPE EST VÉRIFIÉ CONTRE LE REGISTRE**, jamais interprété comme un nom de classe : accepter une classe fournie
 * par l'appelant permettrait de réactiver ou d'effacer n'importe quel modèle du projet, y compris les exclus.
 */
class CorbeilleService
{
    public const MOT_CONFIRMATION = 'SUPPRIMER';

    /** Espace de noms des identifiants (UUID v5) de l'instantané servi au poste : `uuid5(ESPACE, "type:id")`. */
    public const ESPACE_CORBEILLE = '3b6f0a52-9c1e-4d6a-8e47-5a2f9d7c1b84';

    public const MESSAGE_RESTAUREE = 'Élément restauré — il réapparaît dans son module.';

    public const MESSAGE_RESTAURATION_INTROUVABLE = 'Restauration impossible : élément introuvable ou déjà restauré.';

    public const MESSAGE_SUPPRIMEE = 'Élément supprimé définitivement.';

    public const MESSAGE_SUPPRESSION_INTROUVABLE = 'Suppression impossible : élément introuvable ou non archivé.';

    public const MESSAGE_CONFIRMATION = 'Pour confirmer, saisissez le mot SUPPRIMER.';

    public const MESSAGE_DROIT = 'Votre rôle ne permet pas cette action.';

    public const REFUS_DEPENSE = 'Cette dépense a été contre-passée au grand livre et son montant réintégré en trésorerie : la restaurer ne rejouerait ni l\'un ni l\'autre. Saisissez une nouvelle dépense.';

    public const REFUS_VENTE = 'Une vente annulée a réintégré son stock : elle ne se restaure pas. Saisissez une nouvelle vente.';

    public const REFUS_TRANSFERT = 'Un transfert annulé a rendu leurs sujets aux deux bandes : le restaurer ne rejouerait pas le mouvement. Saisissez un nouveau transfert.';

    /**
     * Pourquoi un type ne se supprime JAMAIS définitivement (PRD § 5.2). Le poste en garde la copie pour les éléments
     * qu'il vient d'archiver et que le serveur n'a pas encore jugés : `corbeille_blade_test.dart` la compare, mot pour mot.
     *
     * @var array<string, string>
     */
    public const MOTIFS_SUPPRESSION = [
        'depenses' => 'Une dépense est un fait comptable : son écriture a été contre-passée, elle reste archivée.',
        'bandes' => 'Une bande porte ses fiches, ses ventes et ses transferts : un fait zootechnique ne s\'efface pas, elle reste archivée.',
        'soins' => 'Un soin est un fait zootechnique : il ne s\'efface pas, il reste archivé.',
        'courriers' => 'Un courrier porte une référence numérotée (CR-AAAA-NNN) : l\'effacer ouvrirait un trou dans le registre, il reste archivé.',
        'comptes' => 'Un compte du plan comptable ne s\'efface pas : il reste archivé.',
        'devis' => 'Un devis porte un numéro (DEV-AAAA-NNN) : l\'effacer ouvrirait un trou dans la numérotation, il reste archivé.',
        'avances' => 'Une avance est un encaissement comptabilisé : elle ne s\'efface pas, elle reste archivée.',
        'pointages' => 'Un pointage alimente la paie : il ne s\'efface pas, il reste archivé.',
        'ventes' => 'Une vente annulée est un fait comptable : elle ne s\'efface pas, elle reste archivée.',
        'transferts' => 'Un transfert est un fait zootechnique : il ne s\'efface pas, il reste archivé.',
    ];

    /** Les libellés des tables qui référencent un élément (« 3 vente(s) »). Une table absente d'ici s'affiche « ligne(s) de <table> ». */
    private const LIBELLES_TABLES = [
        'sales' => 'vente(s)',
        'sale_lines' => 'ligne(s) de vente',
        'stock_movements' => 'mouvement(s) de stock',
        'expenses' => 'dépense(s)',
        'purchases' => 'achat(s)',
        'purchase_lines' => 'ligne(s) d\'achat',
        'purchase_orders' => 'bon(s) de commande',
        'purchase_returns' => 'retour(s) d\'achat',
        'payables' => 'dette(s) fournisseur',
        'supplier_payments' => 'règlement(s) fournisseur',
        'supplier_refunds' => 'remboursement(s) fournisseur',
        'supplier_credits' => 'créance(s) fournisseur',
        'receivables' => 'créance(s) client',
        'customer_advances' => 'avance(s) client',
        'customer_reminders' => 'relance(s) client',
        'quotes' => 'devis',
        'credit_notes' => 'avoir(s)',
        'attendance_records' => 'pointage(s)',
        'payslips' => 'bulletin(s) de paie',
        'lot_revenues' => 'revenu(s) de bande',
    ];

    /** @var array<string, list<array{0: string, 1: string}>> */
    private array $pointsDeReference = [];

    /**
     * Registre des types de la Corbeille.
     *
     * ⚠️ LISTE EXPLICITE, JAMAIS UNE DÉCOUVERTE AUTOMATIQUE des modèles portant `is_active` : un balayage automatique
     * embarquerait la première table sensible ajoutée au schéma, sans que personne ne l'ait décidé.
     *
     * Clés d'une définition :
     *  - `modele`, `libelle`, `module` ; `titre` : colonne OU fonction rendant le titre lisible ;
     *  - `detail` : fonction rendant la précision affichée sous le titre (facultative) ;
     *  - `archive` : `is_active` (défaut) ou `annulee` (vente : `status = 'annulee'`) ;
     *  - `restauration` : `libre` · `interdite` (avec `refus`) ;
     *  - `date` : fonction rendant le jour de l'élément — un exercice clos le rend non restaurable (R4) ;
     *  - `code` : colonne dont la valeur doit rester unique parmi les actifs ;
     *  - `suppression` : `sans_reference` (aucune table ne peut le viser) · `si_non_reference` (contrôle des
     *    dépendances ; `cle` = colonne `<entité>_id` des tables qui le visent sans clé étrangère) · `interdite`
     *    (avec `motif`).
     *
     * @return array<string, array<string, mixed>>
     */
    public static function registre(): array
    {
        $interdite = fn (string $type) => ['suppression' => 'interdite', 'motif' => self::MOTIFS_SUPPRESSION[$type]];

        return [
            'produits' => ['modele' => Product::class, 'libelle' => 'Produit', 'titre' => 'name', 'module' => 'stocks',
                'detail' => fn (Product $l) => (string) $l->sku, 'code' => 'sku', 'code_phrase' => 'un produit actif',
                'suppression' => 'si_non_reference', 'cle' => 'product_id'],
            'fournisseurs' => ['modele' => Supplier::class, 'libelle' => 'Fournisseur', 'titre' => 'name', 'module' => 'achats',
                'detail' => fn (Supplier $l) => (string) ($l->category ?? ''), 'suppression' => 'si_non_reference', 'cle' => 'supplier_id'],
            'clients' => ['modele' => Customer::class, 'libelle' => 'Client', 'titre' => 'name', 'module' => 'ventes',
                'detail' => fn (Customer $l) => (string) ($l->phone ?? ''), 'suppression' => 'si_non_reference', 'cle' => 'customer_id'],
            'depenses' => ['modele' => Expense::class, 'libelle' => 'Dépense', 'titre' => 'label', 'module' => 'achats',
                'detail' => fn (Expense $l) => self::fcfa($l->amount), 'restauration' => 'interdite', 'refus' => self::REFUS_DEPENSE]
                + $interdite('depenses'),
            'bandes' => ['modele' => LivestockLot::class, 'libelle' => 'Bande', 'titre' => 'code', 'module' => 'elevage',
                'detail' => fn (LivestockLot $l) => (string) ($l->stage ?? '')]
                + $interdite('bandes'),
            'soins' => ['modele' => VeterinaryRecord::class, 'libelle' => 'Soin vétérinaire', 'titre' => 'action_type', 'module' => 'elevage',
                'detail' => fn (VeterinaryRecord $l) => (string) ($l->product_used ?? ''), 'date' => fn (VeterinaryRecord $l) => self::jour($l->record_date)]
                + $interdite('soins'),
            'rations' => ['modele' => FeedRationStandard::class, 'libelle' => 'Ration normative', 'titre' => 'stage_label', 'module' => 'elevage',
                'detail' => fn (FeedRationStandard $l) => (string) $l->species_code, 'suppression' => 'sans_reference'],
            'provendes' => ['modele' => FeedType::class, 'libelle' => 'Type de provende', 'titre' => 'name', 'module' => 'elevage',
                'suppression' => 'sans_reference'],
            'prophylaxie' => ['modele' => ProphylaxisScheduleStandard::class, 'libelle' => 'Protocole prophylactique', 'titre' => 'treatment', 'module' => 'elevage',
                'detail' => fn (ProphylaxisScheduleStandard $l) => trim($l->species_code.' — '.$l->period_label, ' —'), 'suppression' => 'sans_reference'],
            'absences' => ['modele' => InternshipAbsence::class, 'libelle' => 'Absence de stagiaire', 'module' => 'rh',
                'titre' => fn (InternshipAbsence $l) => trim((string) $l->reason) !== '' ? (string) $l->reason : 'Absence du '.self::jourFr($l->absence_date),
                'detail' => fn (InternshipAbsence $l) => self::jourFr($l->absence_date), 'suppression' => 'sans_reference'],
            'documents' => ['modele' => AdministrativeDocument::class, 'libelle' => 'Document administratif', 'titre' => 'title', 'module' => 'administration',
                'detail' => fn (AdministrativeDocument $l) => (string) ($l->type ?? ''), 'suppression' => 'sans_reference'],
            'pieces' => ['modele' => ArchivedDocument::class, 'libelle' => 'Pièce archivée', 'titre' => 'title', 'module' => 'administration',
                'detail' => fn (ArchivedDocument $l) => (string) ($l->category ?? ''), 'suppression' => 'sans_reference'],
            'courriers' => ['modele' => Correspondence::class, 'libelle' => 'Courrier', 'titre' => 'subject', 'module' => 'administration',
                'detail' => fn (Correspondence $l) => (string) ($l->reference ?? '')]
                + $interdite('courriers'),
            'comptes' => ['modele' => ChartOfAccount::class, 'libelle' => 'Compte du plan', 'titre' => 'label', 'module' => 'comptabilite',
                'detail' => fn (ChartOfAccount $l) => (string) $l->code, 'code' => 'code', 'code_phrase' => 'un compte actif']
                + $interdite('comptes'),
            'devis' => ['modele' => Quote::class, 'libelle' => 'Devis', 'module' => 'ventes',
                'titre' => fn (Quote $l) => trim((string) $l->quote_number) !== '' ? (string) $l->quote_number : 'Devis sans numéro',
                'detail' => fn (Quote $l) => trim(Str::limit((string) $l->articles_description, 60).' — '.self::fcfa($l->amount), ' —'),
                'date' => fn (Quote $l) => self::jour($l->quote_date)]
                + $interdite('devis'),
            'avances' => ['modele' => CustomerAdvance::class, 'libelle' => 'Avance client', 'module' => 'ventes',
                'titre' => fn (CustomerAdvance $l) => 'Avance de '.self::fcfa($l->amount),
                'detail' => fn (CustomerAdvance $l) => (string) ($l->customer?->name ?? ''),
                'date' => fn (CustomerAdvance $l) => self::jour($l->advance_date)]
                + $interdite('avances'),
            'employes' => ['modele' => Employee::class, 'libelle' => 'Employé', 'module' => 'rh',
                'titre' => fn (Employee $l) => trim($l->first_name.' '.$l->last_name),
                'detail' => fn (Employee $l) => (string) ($l->position ?? ''), 'suppression' => 'si_non_reference', 'cle' => 'employee_id'],
            'pointages' => ['modele' => AttendanceRecord::class, 'libelle' => 'Pointage', 'module' => 'rh',
                'titre' => fn (AttendanceRecord $l) => trim(($l->employee?->first_name ?? '').' '.($l->employee?->last_name ?? '')).' — '.self::jourFr($l->attendance_date),
                'detail' => fn (AttendanceRecord $l) => (string) ($l->status ?? ''),
                'date' => fn (AttendanceRecord $l) => self::jour($l->attendance_date)]
                + $interdite('pointages'),
            'ventes' => ['modele' => Sale::class, 'libelle' => 'Vente annulée', 'module' => 'ventes', 'archive' => 'annulee',
                'titre' => fn (Sale $l) => 'Vente du '.self::jourFr($l->date_effective),
                'detail' => fn (Sale $l) => self::fcfa($l->total), 'restauration' => 'interdite', 'refus' => self::REFUS_VENTE]
                + $interdite('ventes'),
            'transferts' => ['modele' => LivestockTransfer::class, 'libelle' => 'Transfert annulé', 'module' => 'elevage',
                'titre' => fn (LivestockTransfer $l) => 'Transfert du '.self::jourFr($l->transfer_date),
                'detail' => fn (LivestockTransfer $l) => (int) $l->quantity.' sujet(s)', 'restauration' => 'interdite', 'refus' => self::REFUS_TRANSFERT]
                + $interdite('transferts'),
        ];
    }

    /**
     * Tout ce qui est archivé, du plus récemment archivé au plus ancien, avec ce que chaque ligne permet.
     *
     * @return array<int, array{type: string, libelle_type: string, module: string, id: string, titre: string, detail: string, archive_le: ?CarbonInterface, archive_par: ?string, restaurable: bool, motif_restauration: ?string, supprimable: bool, motif_suppression: ?string}>
     */
    public function elements(?string $typeFiltre = null, ?string $recherche = null, ?string $du = null, ?string $au = null): array
    {
        $elements = [];

        foreach (static::registre() as $type => $definition) {
            if ($typeFiltre && $typeFiltre !== $type) {
                continue;
            }

            $lignes = $this->archives($definition)->orderByDesc('updated_at')->get();
            $motifsSuppression = $this->motifsDeSuppression($type, $definition, $lignes);
            $auteurs = $this->auteursDArchivage($definition, $lignes);

            foreach ($lignes as $ligne) {
                $motifRestauration = $this->motifDeRestauration($type, $definition, $ligne);
                $motifSuppression = $motifsSuppression[$ligne->getKey()] ?? null;

                $elements[] = [
                    'type' => $type,
                    'libelle_type' => $definition['libelle'],
                    'module' => $definition['module'],
                    'id' => (string) $ligne->getKey(),
                    // Un identifiant UUID seul ne permet pas de décider si l'on veut restaurer.
                    'titre' => $this->titre($definition, $ligne),
                    'detail' => isset($definition['detail']) ? (string) $definition['detail']($ligne) : '',
                    'archive_le' => $ligne->updated_at,
                    // Ticket ARC-Q2 — QUI a archivé ; `null` quand on ne le sait pas (archivage d'avant l'audit de l'entité).
                    'archive_par' => $auteurs[(string) $ligne->getKey()] ?? null,
                    'restaurable' => $motifRestauration === null,
                    'motif_restauration' => $motifRestauration,
                    'supprimable' => $motifSuppression === null,
                    'motif_suppression' => $motifSuppression,
                ];
            }
        }

        usort($elements, fn ($a, $b) => ($b['archive_le']?->timestamp ?? 0) <=> ($a['archive_le']?->timestamp ?? 0));

        return self::filtrer($elements, null, $recherche, $du, $au);
    }

    /**
     * Recherche (titre, détail et type : casse, accents et espaces ignorés), type, période d'archivage (bornes incluses).
     *
     * @param  array<int, array<string, mixed>>  $elements
     * @return array<int, array<string, mixed>>
     */
    public static function filtrer(array $elements, ?string $type, ?string $recherche, ?string $du, ?string $au): array
    {
        $cle = $recherche !== null && trim($recherche) !== '' ? CleUnicite::cle($recherche) : null;

        return array_values(array_filter($elements, function (array $e) use ($type, $cle, $du, $au) {
            if ($type && $e['type'] !== $type) {
                return false;
            }
            if ($cle !== null && ! str_contains(CleUnicite::cle($e['titre'].' '.$e['detail'].' '.$e['libelle_type']), $cle)) {
                return false;
            }
            $jour = $e['archive_le']?->format('Y-m-d');
            if ($du && ($jour === null || $jour < $du)) {
                return false;
            }
            if ($au && ($jour === null || $jour > $au)) {
                return false;
            }

            return true;
        }));
    }

    public function compte(): int
    {
        return count($this->elements());
    }

    /**
     * Les trois cartes de la page (PRD EF1).
     *
     * @param  array<int, array<string, mixed>>  $elements
     * @return array{archives: int, restaurables: int, supprimables: int}
     */
    public function cartes(array $elements): array
    {
        return [
            'archives' => count($elements),
            'restaurables' => count(array_filter($elements, fn ($e) => $e['restaurable'])),
            'supprimables' => count(array_filter($elements, fn ($e) => $e['supprimable'])),
        ];
    }

    /** Ancien contrat (ticket 14.55) : `true` si restauré. Préférer [tenterRestauration], qui dit POURQUOI. */
    public function restaurer(string $type, string $id): bool
    {
        return $this->tenterRestauration($type, $id)['ok'];
    }

    /**
     * Restaure un élément archivé, sous les règles du PRD (§ 5.1).
     *
     * @return array{ok: bool, message: string}
     */
    public function tenterRestauration(string $type, string $id, ?string $deviceId = null, ?User $acteur = null, ?string $idDemande = null): array
    {
        $acteur ??= auth()->user();
        if (! $acteur || ! $acteur->can('manage-parametres')) {
            return $this->refus(self::MESSAGE_DROIT);
        }

        $definition = static::registre()[$type] ?? null;
        if ($definition === null) {
            return $this->refus(self::MESSAGE_RESTAURATION_INTROUVABLE);
        }

        return DB::transaction(function () use ($type, $id, $definition, $acteur, $deviceId, $idDemande) {
            $ligne = $this->archives($definition)->whereKey($id)->lockForUpdate()->first();
            if ($ligne === null) {
                return $this->refus(self::MESSAGE_RESTAURATION_INTROUVABLE);
            }

            $motif = $this->motifDeRestauration($type, $definition, $ligne);
            if ($motif !== null) {
                return $this->refus($motif);
            }

            $titre = $this->titre($definition, $ligne);
            if ($type === 'bandes') {
                // Point de passage de l'écran Bandes & Sujets (BS-Q7) : code déjà porté par une bande en cours = refus.
                try {
                    app(SaisieBandeAction::class)->restaurer($ligne->getKey());
                } catch (ValidationException $e) {
                    return $this->refus((string) collect($e->errors())->flatten()->first());
                }
            } else {
                $ligne->update(['is_active' => true]);
            }

            // La restauration est un acte administratif : elle se journalise, comme l'archivage.
            AuditLog::record('corbeille.restored', $definition['module'], $acteur->id);
            $this->journaliser('restaurer', $type, (string) $ligne->getKey(), $titre, 'accepte', null, $acteur, $deviceId, $idDemande);

            return ['ok' => true, 'message' => self::MESSAGE_RESTAUREE];
        });
    }

    /**
     * Supprime DÉFINITIVEMENT un élément archivé, sous les règles du PRD (§ 5.2). Irréversible.
     *
     * @return array{ok: bool, message: string}
     */
    public function supprimerDefinitivement(string $type, string $id, string $confirmation, ?string $deviceId = null, ?User $acteur = null, ?string $idDemande = null): array
    {
        $acteur ??= auth()->user();
        if (! $acteur || ! $acteur->can('manage-parametres')) {
            return $this->refus(self::MESSAGE_DROIT);
        }

        $definition = static::registre()[$type] ?? null;
        if ($definition === null) {
            return $this->refus(self::MESSAGE_SUPPRESSION_INTROUVABLE);
        }

        try {
            return DB::transaction(function () use ($type, $id, $confirmation, $definition, $acteur, $deviceId, $idDemande) {
                $ligne = $this->archives($definition)->whereKey($id)->lockForUpdate()->first();
                if ($ligne === null) {
                    return $this->refus(self::MESSAGE_SUPPRESSION_INTROUVABLE);
                }

                $motif = $this->motifsDeSuppression($type, $definition, new Collection([$ligne]))[$ligne->getKey()] ?? null;
                if ($motif !== null) {
                    return $this->refus($motif);
                }

                // Le mot est EXACT (casse et espaces compris) : « supprimer » ou « SUPPRIMER » suivi d'un espace ne suffisent pas.
                if ($confirmation !== self::MOT_CONFIRMATION) {
                    return $this->refus(self::MESSAGE_CONFIRMATION);
                }

                // Le titre est copié AVANT l'effacement : la ligne supprimée ne dira plus ce qu'elle était.
                $titre = $this->titre($definition, $ligne);
                $ligne->delete();

                AuditLog::record('corbeille.deleted', $definition['module'], $acteur->id);
                $this->journaliser('supprimer', $type, (string) $id, $titre, 'accepte', null, $acteur, $deviceId, $idDemande);

                return ['ok' => true, 'message' => self::MESSAGE_SUPPRIMEE];
            });
        } catch (QueryException) {
            // Filet : une contrainte étrangère que le contrôle des dépendances n'a pas vue retient la ligne.
            return $this->refus('Suppression impossible : cet élément est encore référencé ailleurs, il reste archivé.');
        }
    }

    /**
     * Écrit une ligne du journal de la Corbeille. `$idDemande` : l'UUID d'une demande née sur un poste (idempotence).
     */
    public function journaliser(string $action, string $type, string $elementId, ?string $titre, string $issue, ?string $motif, ?User $acteur, ?string $deviceId, ?string $idDemande = null): CorbeilleOperation
    {
        $operation = new CorbeilleOperation([
            'user_id' => $acteur?->id, 'action' => $action, 'type' => $type, 'element_id' => $elementId,
            'titre' => $titre !== null ? mb_substr($titre, 0, 255) : null, 'issue' => $issue, 'motif' => $motif, 'device_id' => $deviceId,
        ]);
        if ($idDemande !== null) {
            $operation->id = $idDemande;
        }
        $operation->save();

        return $operation;
    }

    /** Le titre lisible d'une ligne ; « — » si elle n'en porte pas. */
    public function titre(array $definition, Model $ligne): string
    {
        $titre = is_callable($definition['titre'])
            ? $definition['titre']($ligne)
            : $ligne->{$definition['titre']};

        return trim((string) $titre) !== '' ? trim((string) $titre) : '—';
    }

    // ─────────────────────────────────── règles ───────────────────────────────────

    /** Pourquoi cette ligne ne peut PAS être restaurée (`null` : elle le peut). */
    private function motifDeRestauration(string $type, array $definition, Model $ligne): ?string
    {
        if (($definition['restauration'] ?? 'libre') === 'interdite') {
            return $definition['refus'];
        }

        // Exercice clos : lecture seule (motif R4 de la date de l'élément).
        if (isset($definition['date'])) {
            $jour = $definition['date']($ligne);
            if ($jour !== null && ($refus = app(AccountingEntryService::class)->refusExerciceClos($jour)) !== null) {
                return $refus;
            }
        }

        // Code déjà porté par un élément ACTIF (clé normalisée : casse, accents, espaces).
        if (isset($definition['code'])) {
            $valeur = (string) $ligne->{$definition['code']};
            $pris = $ligne->newQuery()->where('is_active', true)->where($ligne->getKeyName(), '!=', $ligne->getKey())
                ->pluck($definition['code'])->contains(fn ($autre) => CleUnicite::cle((string) $autre) === CleUnicite::cle($valeur));
            if ($pris) {
                return 'Le code « '.trim($valeur).' » est déjà porté par '.$definition['code_phrase'].' : ce'
                    .($definition['modele'] === Product::class ? ' produit' : ' compte').' ne peut pas être restauré.';
            }
        }

        // Une bande : même règle que l'écran Bandes & Sujets (BS-Q7), code comparé aux bandes EN COURS seulement.
        if ($ligne instanceof LivestockLot) {
            $pris = LivestockLot::where('is_active', true)->where('id', '!=', $ligne->id)
                ->whereRaw('lower(code) = ?', [mb_strtolower($ligne->code)])->exists();
            if ($pris) {
                return LivestockLot::messageCodePris($ligne->code);
            }
        }

        return null;
    }

    /**
     * Pour chaque ligne, pourquoi elle ne peut PAS être supprimée définitivement (absente : elle le peut).
     *
     * @param  Collection<int, Model>  $lignes
     * @return array<string, string>
     */
    private function motifsDeSuppression(string $type, array $definition, Collection $lignes): array
    {
        if ($lignes->isEmpty()) {
            return [];
        }

        $mode = $definition['suppression'] ?? 'interdite';
        if ($mode === 'interdite') {
            $motif = $definition['motif'] ?? 'Cet élément ne peut pas être supprimé définitivement : il reste archivé.';

            return $lignes->mapWithKeys(fn ($l) => [$l->getKey() => $motif])->all();
        }
        // `sans_reference` : aucune clé étrangère ne vise aujourd'hui ces tables ; le contrôle générique ne coûte rien
        // et garde la porte fermée à un futur schéma : il est appliqué aussi.

        $table = $lignes->first()?->getTable();
        $ids = $lignes->map(fn ($l) => $l->getKey())->all();
        $comptes = [];
        foreach ($this->pointsDeReference($table, $definition['cle'] ?? null) as [$tableLiee, $colonne]) {
            foreach (array_chunk($ids, 500) as $paquet) {
                $lignesLiees = DB::table($tableLiee)->whereIn($colonne, $paquet)->select($colonne, DB::raw('count(*) as n'))->groupBy($colonne)->get();
                foreach ($lignesLiees as $l) {
                    $comptes[$l->{$colonne}][$tableLiee] = ($comptes[$l->{$colonne}][$tableLiee] ?? 0) + (int) $l->n;
                }
            }
        }

        $motifs = [];
        foreach ($lignes as $ligne) {
            $liees = $comptes[$ligne->getKey()] ?? [];
            if ($liees === []) {
                continue;
            }
            $morceaux = [];
            foreach ($liees as $tableLiee => $n) {
                $morceaux[] = $n.' '.(self::LIBELLES_TABLES[$tableLiee] ?? 'ligne(s) de '.$tableLiee);
            }
            $liste = count($morceaux) > 1 ? implode(', ', array_slice($morceaux, 0, -1)).' et '.end($morceaux) : $morceaux[0];
            $motifs[$ligne->getKey()] = $this->titre($definition, $ligne).' est référencé par '.$liste.' : il ne peut pas être supprimé, il reste archivé.';
        }

        return $motifs;
    }

    /**
     * Toutes les colonnes d'autres tables qui visent [$table] : clés étrangères déclarées, plus les colonnes nommées
     * [$cle] (`product_id`…) même sans contrainte (la base n'en pose pas partout).
     *
     * @return list<array{0: string, 1: string}>
     */
    private function pointsDeReference(string $table, ?string $cle): array
    {
        $memo = $table.'|'.$cle;
        if (isset($this->pointsDeReference[$memo])) {
            return $this->pointsDeReference[$memo];
        }

        $points = [];
        foreach (Schema::getTables() as $t) {
            $nom = $t['name'];
            if ($nom === 'corbeille_operations') {
                continue;
            }
            foreach (Schema::getForeignKeys($nom) as $fk) {
                if ($fk['foreign_table'] === $table && count($fk['columns']) === 1 && $nom !== $table) {
                    $points[$nom.'.'.$fk['columns'][0]] = [$nom, $fk['columns'][0]];
                }
            }
            if ($cle !== null && $nom !== $table && Schema::hasColumn($nom, $cle)) {
                $points[$nom.'.'.$cle] = [$nom, $cle];
            }
        }

        return $this->pointsDeReference[$memo] = array_values($points);
    }

    /**
     * Ticket ARC-Q2 — « Archivé par » : le nom de l'utilisateur du DERNIER audit d'archivage de chaque ligne
     * (`audit_logs.entity_type` / `entity_id`, famille `AuditLog::ACTIONS_ARCHIVAGE`). Une ligne sans audit d'entité
     * (archivée avant cette migration), ou dont l'auteur n'existe plus, est ABSENTE du résultat : l'écran affiche
     * « — », jamais un nom deviné.
     *
     * @param  Collection<int, Model>  $lignes
     * @return array<string, string>  id de l'élément => nom de l'auteur
     */
    private function auteursDArchivage(array $definition, Collection $lignes): array
    {
        if ($lignes->isEmpty()) {
            return [];
        }

        $type = $lignes->first()->getMorphClass();
        $ids = $lignes->map(fn ($l) => (string) $l->getKey())->all();
        $auteurs = [];

        foreach (array_chunk($ids, 500) as $paquet) {
            $audits = AuditLog::query()
                ->where('entity_type', $type)
                ->whereIn('entity_id', $paquet)
                ->whereIn('action', AuditLog::ACTIONS_ARCHIVAGE)
                ->with('user:id,name')
                ->orderByDesc('created_at')
                ->get();

            foreach ($audits as $audit) {
                // Le premier audit rencontré est le plus récent : on ne le remplace pas (même s'il n'a plus d'auteur).
                if (! array_key_exists($audit->entity_id, $auteurs)) {
                    $auteurs[$audit->entity_id] = $audit->user?->name;
                }
            }
        }

        return array_filter($auteurs, fn ($nom) => $nom !== null && trim($nom) !== '');
    }

    /** La requête des lignes ARCHIVÉES d'un type. */
    private function archives(array $definition)
    {
        /** @var class-string<Model> $modele */
        $modele = $definition['modele'];

        return ($definition['archive'] ?? 'is_active') === 'annulee'
            ? $modele::query()->where('status', 'annulee')
            : $modele::query()->where('is_active', false);
    }

    /** @return array{ok: false, message: string} */
    private function refus(string $message): array
    {
        return ['ok' => false, 'message' => $message];
    }

    private static function fcfa($montant): string
    {
        return number_format((float) $montant, 0, ',', ' ').' FCFA';
    }

    private static function jour($date): ?string
    {
        return $date instanceof CarbonInterface ? $date->format('Y-m-d') : ($date ? substr((string) $date, 0, 10) : null);
    }

    private static function jourFr($date): string
    {
        return $date instanceof CarbonInterface ? $date->format('d/m/Y') : '—';
    }
}
