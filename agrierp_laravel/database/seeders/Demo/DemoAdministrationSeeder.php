<?php

namespace Database\Seeders\Demo;

use App\Models\AdministrativeDocument;
use App\Models\ArchivedDocument;
use App\Models\CompanySetting;
use App\Models\Expense;
use App\Models\Correspondence;
use App\Models\TreasuryAccount;
use Illuminate\Database\Seeder;

/**
 * Ticket 14.31 (Sprint 14) — ADMINISTRATION et DÉPENSES de démonstration.
 *
 * ⚠️ LES DÉPENSES DÉCRÉMENTENT RÉELLEMENT LA TRÉSORERIE, comme le fait
 * `SaisieDepenses`. Sans cela le solde affiché serait supérieur à la réalité
 * de la simulation, et le rapprochement bancaire n'aurait plus rien à
 * rapprocher.
 *
 * ⚠️ LIMITE ASSUMÉE, HÉRITÉE DE L'APPLICATION : une dépense ne génère
 * AUCUNE écriture comptable — `SaisieDepenses` n'appelle aucune Action
 * comptable, contrairement aux ventes, achats, paie, avoirs et amortissements
 * (tickets 14.23 à 14.27). Les dépenses de la simulation sortent donc de la
 * trésorerie sans apparaître au Compte de Résultat. C'est un manque RÉEL de
 * l'application, signalé au ticket 14.31 — pas un raccourci du seeder, qui se
 * contente ici de reproduire fidèlement le comportement existant.
 */
class DemoAdministrationSeeder extends Seeder
{
    public function __construct(private DemoContexte $ctx) {}

    public function run(): void
    {
        $this->renseignerEntreprise();
        $depenses = $this->creerDepenses();
        $this->creerDocuments();
        $this->creerCourriers();
        $this->creerArchives();

        $this->command?->info('  Administration : '.$depenses.' dépenses, '
            .AdministrativeDocument::count().' documents, '.Correspondence::count().' courriers, '
            .ArchivedDocument::count().' pièces archivées.');
    }

    /** Identité réelle de l'exploitation — en-têtes de PDF et mentions légales. */
    private function renseignerEntreprise(): void
    {
        CompanySetting::firstOrCreate([], [
            'company_name' => 'FERME ÉCOLE OLOUWACHEGOUN',
            'promoter_name' => 'Cabinet FAGUEZ SARL',
            'address' => 'Ikpinlè, Commune d\'Adja-Ouèrè, Département du Plateau, Bénin',
            'phone' => '+2290197840285',
            'email' => 'contact@fermeolouwachegoun.com',
            'ifu' => '3202512345678',
            'rccm' => 'RB/PTN/26 B 1234',
        ]);
    }

    private function creerDepenses(): int
    {
        $caisse = TreasuryAccount::where('account_code', '531')->first();

        if (! $caisse) {
            return 0;
        }

        // ⚠️ CATÉGORIES = COMPTES SYSCOHADA, au format exact de l'écran
        // (« 605 - Énergie »). Ticket 14.33 : c'est de ce libellé que
        // `RecordExpenseAccountingEntryAction` extrait le compte de charge.
        // Des libellés libres auraient produit des dépenses sans écriture.
        $modeles = [
            ['Carburant groupe électrogène', '605 - Énergie', 18_000, 42_000],
            ['Électricité SBEE', '605 - Énergie', 25_000, 60_000],
            ['Eau SONEB', '605 - Énergie', 8_000, 18_000],
            ['Transport et livraison', '614 - Transports', 5_000, 25_000],
            ['Petit outillage et réparations', '606 - Entretien', 6_000, 35_000],
            ['Frais de communication', '628 - Autres charges', 5_000, 15_000],
            ['Désinfection et litière', '602 - Produits vétérinaires', 10_000, 30_000],
        ];

        $compte = 0;

        for ($jour = $this->ctx->debut; $jour->lte($this->ctx->fin); $jour = $jour->addDays($this->ctx->entre(3, 7))) {
            // Ticket DEP1 — UNE DÉPENSE, PLUSIEURS LIGNES : une dépense sur trois porte un second achat (autre compte de
            // charge). Le total est la somme des lignes ; le libellé de l'en-tête leur résumé.
            $achats = [$this->ctx->parmi($modeles)];
            if ($this->ctx->entre(0, 2) === 0) {
                $achats[] = $this->ctx->parmi($modeles);
            }
            $lignes = [];
            foreach ($achats as [$libelle, $categorie, $min, $max]) {
                $compteDeCharge = \App\Services\ConversionDepensesEnLignes::compteDeLaCategorie($categorie);
                if ($compteDeCharge !== null) {
                    $lignes[] = ['label' => $libelle, 'account' => $compteDeCharge, 'category' => $categorie, 'amount' => $this->ctx->entre($min, $max)];
                }
            }
            if ($lignes === []) {
                continue;
            }
            $montant = array_sum(array_column($lignes, 'amount'));

            // Compte payeur choisi selon le solde disponible : l'écran laisse ce
            // choix à l'opérateur, et une caisse systématiquement ponctionnée
            // pendant que les autres comptes dorment n'a rien de réaliste.
            $payeur = $this->ctx->compteSolvable($montant) ?? $caisse;

            $depense = Expense::create([
                'expense_date' => $jour->format('Y-m-d'),
                'label' => Expense::resume(array_column($lignes, 'label')),
                'category' => $lignes[0]['category'],
                'amount' => $montant,
                'treasury_account_id' => $payeur->id,
                'payment_mode' => $payeur->type,
                'status' => 'payee',
                'is_active' => true,
                'created_at' => $jour, 'updated_at' => $jour,
            ]);
            foreach ($lignes as $rang => $ligne) {
                \App\Models\ExpenseLine::create([
                    'expense_id' => $depense->id, 'position' => $rang, 'label' => $ligne['label'],
                    'charge_account_id' => $ligne['account']->id, 'amount' => $ligne['amount'],
                ]);
            }

            // Même séquence que `SaisieDepenses` : écriture comptable PUIS
            // décrément de trésorerie. Ticket 14.33 — avant lui, les dépenses
            // de la simulation sortaient de la caisse sans jamais apparaître au
            // Compte de Résultat, qui les surestimait donc de leur total.
            app(\App\Actions\RecordExpenseAccountingEntryAction::class)->execute($depense);

            $payeur->decrement('balance', $montant);

            $compte++;
        }

        return $compte;
    }

    private function creerDocuments(): void
    {
        foreach ([
            ['Attestation de travail — ADJOVI Kossi', 'Attestation', 'ADJOVI Kossi', 12, 'signe'],
            ['Certificat de stage — TOSSOU Ange', 'Certificat', 'TOSSOU Ange', 30, 'signe'],
            ['Attestation de présence — HOUNSOU Bernadette', 'Attestation', 'HOUNSOU Bernadette', 45, 'signe'],
            ['Demande de subvention PAEB — campagne 2026', 'Demande', 'Ferme École Olouwachegoun', 60, 'en_attente'],
            ['Certificat sanitaire du cheptel avicole', 'Certificat', 'Ferme École Olouwachegoun', 20, 'signe'],
            ['Attestation de stage — AKPOVI Nadège', 'Attestation', 'AKPOVI Nadège', 8, 'en_attente'],
        ] as [$titre, $type, $beneficiaire, $joursAvant, $statut]) {
            $date = $this->ctx->fin->subDays($joursAvant);

            AdministrativeDocument::create([
                'title' => $titre,
                'type' => $type,
                'beneficiary' => $beneficiaire,
                'doc_date' => $date->format('Y-m-d'),
                'status' => $statut,
                'is_active' => true,
                'created_at' => $date, 'updated_at' => $date,
            ]);
        }
    }

    private function creerCourriers(): void
    {
        foreach ([
            ['entrant', 'Convocation réunion des éleveurs du Plateau', 'Direction Départementale de l\'Agriculture', 55],
            ['entrant', 'Notification de contrôle sanitaire', 'Direction de l\'Élevage', 40],
            ['sortant', 'Demande d\'agrément couvoir', 'Ministère de l\'Agriculture', 33],
            ['entrant', 'Relance facture provende du mois', 'Provenderie du Plateau', 25],
            ['sortant', 'Réponse à la relance — échéancier proposé', 'Provenderie du Plateau', 21],
            ['sortant', 'Offre de partenariat — approvisionnement en œufs', 'Supermarché EREVAN Cotonou', 14],
            ['entrant', 'Accusé de réception du dossier de subvention', 'PAEB', 7],
        ] as $i => [$type, $sujet, $partie, $joursAvant]) {
            $date = $this->ctx->fin->subDays($joursAvant);

            Correspondence::create([
                'reference' => ($type === 'entrant' ? 'CA' : 'CD').'-2026-'.str_pad((string) ($i + 1), 3, '0', STR_PAD_LEFT),
                'type' => $type,
                'subject' => $sujet,
                'party' => $partie,
                'mail_date' => $date->format('Y-m-d'),
                'is_active' => true,
                'created_at' => $date, 'updated_at' => $date,
            ]);
        }
    }

    private function creerArchives(): void
    {
        foreach ([
            ['Statuts de la société', 'Juridique', 400, null],
            ['Registre du commerce (RCCM)', 'Juridique', 395, null],
            ['Attestation fiscale IFU', 'Fiscal', 120, 245],
            ['Police d\'assurance du cheptel', 'Assurance', 200, 165],
            ['Convention de partenariat PAEB', 'Partenariat', 300, 430],
            ['Agrément sanitaire d\'exploitation', 'Réglementaire', 260, 105],
        ] as [$titre, $categorie, $joursAvant, $joursValidite]) {
            $date = $this->ctx->fin->subDays($joursAvant);

            ArchivedDocument::create([
                'title' => $titre,
                'category' => $categorie,
                'archived_date' => $date->format('Y-m-d'),
                // Échéances volontairement réparties de part et d'autre
                // d'aujourd'hui : l'écran doit montrer des pièces valides ET
                // des pièces à renouveler, sinon son alerte ne se voit pas.
                'expiry_date' => $joursValidite ? $date->addDays($joursValidite)->format('Y-m-d') : null,
                'is_active' => true,
                'created_at' => $date, 'updated_at' => $date,
            ]);
        }
    }
}
