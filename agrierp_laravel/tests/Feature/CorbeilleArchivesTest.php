<?php

namespace Tests\Feature;

use App\Actions\SaisieDepenseAction;
use App\Livewire\Parametres\Corbeille;
use App\Models\AdministrativeDocument;
use App\Models\ArchivedDocument;
use App\Models\AttendanceRecord;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\Correspondence;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\Employee;
use App\Models\Expense;
use App\Models\FeedRationStandard;
use App\Models\FeedType;
use App\Models\FiscalYear;
use App\Models\Internship;
use App\Models\InternshipAbsence;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\LivestockTransfer;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\ProphylaxisScheduleStandard;
use App\Models\Quote;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Models\User;
use App\Models\VeterinaryRecord;
use App\Services\CorbeilleService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Tickets ARC1 / ARC2 (PRD `docs/prd/archives.md`) — LA CORBEILLE : voir, restaurer, supprimer définitivement.
 *
 * Demande du client : « une page pour afficher les enregistrements archivés et permettre de les RESTAURER et/ou de les
 * SUPPRIMER DÉFINITIVEMENT ». Chaque règle de § 5 du PRD a son test ; les valeurs attendues sont calculées à la main
 * (§ 5.3 : 4 archivés, 3 restaurables, 1 supprimable).
 *
 * ⚠️ Toute date est FIGÉE (20/06/2026) : aucun test ne dépend du jour où la suite tourne.
 */
class CorbeilleArchivesTest extends TestCase
{
    use DecorDepenses;
    use RefreshDatabase;

    private LivestockSpecies $espece;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerDecorDepenses();

        $this->espece = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Maïs concassé', 'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true,
        ]);
    }

    private function service(): CorbeilleService
    {
        return app(CorbeilleService::class);
    }

    // ───────────────────────── fabriques : UN enregistrement archivé de chaque type ─────────────────────────

    private function bande(string $code, bool $active = false): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $this->espece->id, 'stage' => 'ponte', 'initial_quantity' => 0, 'current_quantity' => 0,
            'created_date' => '2026-05-01', 'status' => 'actif', 'is_active' => $active,
        ]);
    }

    private function client(string $nom = 'Kossi Adjovi', bool $active = false): Customer
    {
        return Customer::create(['name' => $nom, 'phone' => '+22997000001', 'is_active' => $active]);
    }

    private function vente(Customer $client, string $statut = 'validee'): Sale
    {
        $vente = Sale::create([
            'customer_id' => $client->id, 'payment_mode' => 'especes', 'subtotal' => 5000, 'discount' => 0, 'total' => 5000,
            'status' => $statut, 'sold_at' => '2026-06-10 10:00:00',
        ]);
        SaleLine::create(['sale_id' => $vente->id, 'product_id' => $this->produit->id, 'qty' => 1, 'unit_price' => 5000, 'manual_total_amount' => 5000]);

        return $vente;
    }

    private function depenseArchivee(): Expense
    {
        $depense = app(SaisieDepenseAction::class)->creer($this->document());
        app(SaisieDepenseAction::class)->archiver($depense->id);

        return $depense->fresh();
    }

    private function employe(bool $active = false): Employee
    {
        return Employee::create(['first_name' => 'Ange', 'last_name' => 'TOSSOU', 'position' => 'Ouvrier', 'base_salary' => 50000, 'hire_date' => '2025-01-01', 'status' => 'actif', 'is_active' => $active]);
    }

    /**
     * Un archivé de CHAQUE type de la Corbeille.
     *
     * @return array<string, \Illuminate\Database\Eloquent\Model>
     */
    private function toutArchiver(): array
    {
        $client = $this->client('Kossi Adjovi');
        $acheteur = $this->client('Acheteur Actif', true);
        $bande = $this->bande('LAP-2026-01');
        $stagiaire = Internship::create(['first_name' => 'Ruth', 'last_name' => 'DOSSOU', 'start_date' => '2026-05-01', 'end_date' => '2026-08-01']);
        $employe = $this->employe();

        return [
            'produits' => Product::create(['sku' => 'ALI-002', 'name' => 'Son de blé', 'category_id' => $this->produit->category_id, 'unit' => 'sac', 'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => false]),
            'fournisseurs' => Supplier::create(['name' => 'Provenderie du Plateau', 'is_active' => false]),
            'clients' => $client,
            'depenses' => $this->depenseArchivee(),
            'bandes' => $bande,
            'soins' => VeterinaryRecord::create(['lot_id' => $bande->id, 'action_type' => 'Vaccination', 'product_used' => 'Pasteurellose', 'record_date' => '2026-06-01', 'is_active' => false]),
            'rations' => FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Lapin Sevré', 'ration_g_per_day' => 30, 'is_active' => false]),
            'provendes' => FeedType::create(['name' => 'Provende croissance', 'species_id' => $this->espece->id, 'standard_bag_weight_kg' => 25, 'price_per_kg' => 400, 'is_active' => false]),
            'prophylaxie' => ProphylaxisScheduleStandard::create(['species_code' => 'cuniculture', 'period_label' => 'Sevrage', 'cycle_day_start' => 28, 'cycle_day_end' => 35, 'treatment' => 'Vermifuge', 'product_recommended' => 'Pipérazine', 'dosage' => '1 ml', 'is_active' => false]),
            'absences' => InternshipAbsence::create(['internship_id' => $stagiaire->id, 'absence_date' => '2026-06-02', 'reason' => 'Maladie', 'is_active' => false]),
            'documents' => AdministrativeDocument::create(['title' => 'Attestation de stage', 'type' => 'attestation', 'beneficiary' => 'Ruth DOSSOU', 'doc_date' => '2026-06-03', 'status' => 'signe', 'is_active' => false]),
            'pieces' => ArchivedDocument::create(['title' => 'Bail du terrain', 'category' => 'Juridique', 'archived_date' => '2026-06-03', 'is_active' => false]),
            'courriers' => Correspondence::create(['reference' => 'CR-2026-001', 'type' => 'entrant', 'subject' => 'Demande de visite', 'party' => 'Mairie', 'mail_date' => '2026-06-03', 'is_active' => false]),
            'comptes' => ChartOfAccount::create(['code' => '6288', 'label' => 'Charges inutilisées', 'class' => 6, 'is_active' => false]),
            'devis' => Quote::create(['quote_number' => 'DEV-2026-001', 'customer_id' => $acheteur->id, 'articles_description' => '2 cages', 'amount' => 150000, 'tva_rate' => 18, 'validity_days' => 15, 'quote_date' => '2026-06-05', 'status' => 'brouillon', 'is_active' => false]),
            'avances' => CustomerAdvance::create(['customer_id' => $acheteur->id, 'amount' => 20000, 'amount_used' => 20000, 'advance_date' => '2026-06-05', 'is_active' => false]),
            'employes' => $employe,
            'pointages' => AttendanceRecord::create(['employee_id' => $this->employe(true)->id, 'attendance_date' => '2026-06-04', 'status' => 'present', 'is_active' => false]),
            'ventes' => $this->vente($acheteur, 'annulee'),
            'transferts' => LivestockTransfer::create(['source_lot_id' => $bande->id, 'target_lot_id' => $this->bande('LAP-2026-02', true)->id, 'transfer_date' => '2026-06-06', 'quantity' => 3, 'is_active' => false]),
        ];
    }

    private function types(array $elements): array
    {
        return array_values(array_unique(array_column($elements, 'type')));
    }

    private function element(string $type, string $id): ?array
    {
        foreach ($this->service()->elements() as $e) {
            if ($e['type'] === $type && $e['id'] === $id) {
                return $e;
            }
        }

        return null;
    }

    // ═════════════════════════════════════ LISTE ═════════════════════════════════════

    /** EF1 — TOUS les types archivables sont listés, avec un titre lisible (provendes et absences lisaient « — »). */
    public function test_chaque_type_archivable_apparait_avec_un_titre_lisible(): void
    {
        $this->toutArchiver();

        $elements = $this->service()->elements();

        $attendus = ['produits', 'fournisseurs', 'clients', 'depenses', 'bandes', 'soins', 'rations', 'provendes', 'prophylaxie',
            'absences', 'documents', 'pieces', 'courriers', 'comptes', 'devis', 'avances', 'employes', 'pointages', 'ventes', 'transferts'];
        $this->assertEqualsCanonicalizing($attendus, $this->types($elements));
        $this->assertEqualsCanonicalizing($attendus, array_keys(CorbeilleService::registre()));

        foreach ($elements as $e) {
            $this->assertNotSame('', trim($e['titre']), "titre vide : {$e['type']}");
            $this->assertNotSame('—', $e['titre'], "le titre de « {$e['type']} » lit une colonne absente");
            $this->assertNotNull($e['archive_le'], "date d'archivage : {$e['type']}");
        }
        $this->assertSame('Provende croissance', collect($elements)->firstWhere('type', 'provendes')['titre']);
        $this->assertSame('Maladie', collect($elements)->firstWhere('type', 'absences')['titre']);
    }

    /** Hors Corbeille : écritures comptables et comptes utilisateurs, même archivés (décisions 14.55 conservées). */
    public function test_ecritures_et_utilisateurs_restent_hors_de_la_corbeille(): void
    {
        $this->depenseArchivee();
        DB::table('accounting_entries')->update(['is_active' => false]);
        User::whereKey($this->admin->id)->update(['is_active' => false]);

        $types = $this->types($this->service()->elements());

        $this->assertNotContains('ecritures', $types);
        $this->assertNotContains('utilisateurs', $types);
        $this->assertArrayNotHasKey('ecritures', CorbeilleService::registre());
        $this->assertArrayNotHasKey('utilisateurs', CorbeilleService::registre());
    }

    /** Un enregistrement actif n'est pas dans la corbeille ; une vente VALIDÉE non plus. */
    public function test_les_actifs_et_les_ventes_validees_n_y_sont_pas(): void
    {
        $this->client('Actif', true);
        $this->vente($this->client('Autre actif', true), 'validee');

        $this->assertSame(0, $this->service()->compte());
    }

    public function test_recherche_filtre_de_type_et_periode(): void
    {
        $this->client('Kossi Adjovi');
        $this->produit->update(['is_active' => false]);
        Supplier::create(['name' => 'Provenderie du Plateau', 'is_active' => false]);
        // dates d'archivage figées : le 05, le 10 et le 15 juin
        Customer::query()->update(['updated_at' => '2026-06-05 08:00:00']);
        Product::query()->update(['updated_at' => '2026-06-10 08:00:00']);
        Supplier::query()->update(['updated_at' => '2026-06-15 23:59:59']);

        $this->assertCount(3, $this->service()->elements());
        $this->assertCount(1, $this->service()->elements('produits'));
        // recherche : casse, accents et espaces ignorés (« mais » trouve « Maïs concassé »)
        $this->assertSame(['produits'], $this->types($this->service()->elements(null, 'MAIS')));
        $this->assertSame(['clients'], $this->types($this->service()->elements(null, 'kossi  adjovi')));
        // la recherche porte aussi sur le TYPE affiché
        $this->assertSame(['fournisseurs'], $this->types($this->service()->elements(null, 'fournisseur')));
        // période : bornes INCLUSIVES, le 15 à 23:59:59 est dans « au 15 »
        $this->assertCount(3, $this->service()->elements(null, null, '2026-06-05', '2026-06-15'));
        $this->assertSame(['produits'], $this->types($this->service()->elements(null, null, '2026-06-06', '2026-06-14')));
        $this->assertCount(1, $this->service()->elements(null, null, '2026-06-15', null));
        $this->assertCount(2, $this->service()->elements(null, null, null, '2026-06-10'));
        // tri : le plus récemment archivé d'abord
        $this->assertSame(['fournisseurs', 'produits', 'clients'], array_column($this->service()->elements(), 'type'));
    }

    /** PRD § 5.3 — l'exemple calculé à la main : 4 archivés, 3 restaurables, 1 supprimable. */
    public function test_cartes_exemple_du_prd(): void
    {
        $this->client('Kossi Adjovi');                                   // 0 vente        → supprimable
        $sogea = $this->client('SOGEA');                                 // 3 ventes       → restaurable seulement
        foreach (range(1, 3) as $_) {
            $this->vente($sogea);
        }
        $this->depenseArchivee();                                        // 45 000 + 10 000 + 5 000 → ni l'un ni l'autre
        $this->produit->update(['is_active' => false]);
        $this->vente($this->client('Acheteur', true));                   // fait référencer le produit… par une seconde vente
        // le produit est donc référencé par 4 lignes de vente (3 de SOGEA + 1)

        $cartes = $this->service()->cartes($this->service()->elements());

        $this->assertSame(['archives' => 4, 'restaurables' => 3, 'supprimables' => 1], $cartes);
    }

    // ═════════════════════════════════════ RESTAURATION ═════════════════════════════════════

    /** Les types sans effet comptable ni de stock se restaurent librement ; trace d'audit et journal. */
    public function test_restauration_libre_des_types_simples(): void
    {
        $archives = $this->toutArchiver();

        foreach (['produits', 'fournisseurs', 'clients', 'soins', 'rations', 'provendes', 'prophylaxie', 'absences',
            'documents', 'pieces', 'courriers', 'comptes', 'employes', 'bandes', 'devis', 'avances', 'pointages'] as $type) {
            $resultat = $this->service()->tenterRestauration($type, $archives[$type]->getKey());
            $this->assertTrue($resultat['ok'], "{$type} : ".$resultat['message']);
            $this->assertTrue((bool) $archives[$type]->fresh()->is_active, "{$type} reste archivé");
        }

        $this->assertSame(17, AuditLog::where('action', 'corbeille.restored')->count());
        $this->assertSame(17, DB::table('corbeille_operations')->where('action', 'restaurer')->where('issue', 'accepte')->count());
    }

    /** ⚠️ Une dépense archivée ne se restaure PAS : contre-passée et réintégrée, la rejouer n'est pas dans la restauration. */
    public function test_une_depense_archivee_ne_se_restaure_pas(): void
    {
        $depense = $this->depenseArchivee();
        $ecritures = DB::table('accounting_entries')->count();
        $soldeCaisse = (float) $this->caisse->fresh()->balance;

        $resultat = $this->service()->tenterRestauration('depenses', $depense->id);

        $this->assertFalse($resultat['ok']);
        $this->assertSame('Cette dépense a été contre-passée au grand livre et son montant réintégré en trésorerie : la restaurer ne rejouerait ni l\'un ni l\'autre. Saisissez une nouvelle dépense.', $resultat['message']);
        $this->assertFalse((bool) $depense->fresh()->is_active, 'la dépense reste archivée');
        $this->assertSame($ecritures, DB::table('accounting_entries')->count(), 'aucune écriture touchée');
        $this->assertSame($soldeCaisse, (float) $this->caisse->fresh()->balance, 'trésorerie intacte (500 000 : 60 000 sortis puis réintégrés)');
        $this->assertSame(500_000.0, $soldeCaisse);
        $this->assertSame(0, AuditLog::where('action', 'corbeille.restored')->count());
        // même refus pour une dépense ANTÉRIEURE à la comptabilisation (sans pièce)
        $ancienne = Expense::create(['expense_date' => '2026-06-01', 'label' => 'Reprise', 'category' => 'divers', 'amount' => 1000, 'treasury_account_id' => $this->caisse->id, 'is_active' => false]);
        $this->assertFalse($this->service()->tenterRestauration('depenses', $ancienne->id)['ok']);
        $this->assertFalse((bool) $ancienne->fresh()->is_active);
    }

    public function test_une_vente_annulee_et_un_transfert_annule_ne_se_restaurent_pas(): void
    {
        $archives = $this->toutArchiver();

        $vente = $this->service()->tenterRestauration('ventes', $archives['ventes']->id);
        $transfert = $this->service()->tenterRestauration('transferts', $archives['transferts']->id);

        $this->assertFalse($vente['ok']);
        $this->assertSame('Une vente annulée a réintégré son stock : elle ne se restaure pas. Saisissez une nouvelle vente.', $vente['message']);
        $this->assertSame('annulee', $archives['ventes']->fresh()->status);
        $this->assertFalse($transfert['ok']);
        $this->assertSame('Un transfert annulé a rendu leurs sujets aux deux bandes : le restaurer ne rejouerait pas le mouvement. Saisissez un nouveau transfert.', $transfert['message']);
        $this->assertFalse((bool) $archives['transferts']->fresh()->is_active);
    }

    /** Code déjà pris : la bande (règle BS-Q7 de `SaisieBandeAction`), le produit et le compte (clé normalisée). */
    public function test_restaurer_un_code_deja_pris_est_refuse_avec_son_message(): void
    {
        $archivee = $this->bande('PON-2026-01');
        $archivee->update(['is_active' => false]);
        $this->bande('pon-2026-01', true);
        $resultat = $this->service()->tenterRestauration('bandes', $archivee->id);
        $this->assertFalse($resultat['ok']);
        $this->assertSame(LivestockLot::messageCodePris('PON-2026-01'), $resultat['message']);
        $this->assertFalse((bool) $archivee->fresh()->is_active);

        $archive = Product::create(['sku' => 'VAC-001', 'name' => 'Vaccin', 'category_id' => $this->produit->category_id, 'unit' => 'dose', 'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => false]);
        Product::create(['sku' => 'vac-001', 'name' => 'Vaccin bis', 'category_id' => $this->produit->category_id, 'unit' => 'dose', 'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true]);
        $produit = $this->service()->tenterRestauration('produits', $archive->id);
        $this->assertFalse($produit['ok']);
        $this->assertSame('Le code « VAC-001 » est déjà porté par un produit actif : ce produit ne peut pas être restauré.', $produit['message']);

        $compte = ChartOfAccount::create(['code' => '6281', 'label' => 'Ancien', 'class' => 6, 'is_active' => false]);
        ChartOfAccount::create(['code' => '6281 ', 'label' => 'Nouveau', 'class' => 6, 'is_active' => true]);
        $this->assertFalse($this->service()->tenterRestauration('comptes', $compte->id)['ok']);
    }

    /** Exercice clos : lecture seule. Devis, avance, soin et pointage datés dans un exercice clos ne se restaurent pas. */
    public function test_un_exercice_clos_interdit_la_restauration_des_elements_dates(): void
    {
        $archives = $this->toutArchiver();
        FiscalYear::query()->update(['status' => 'cloture']);

        foreach (['devis', 'avances', 'soins', 'pointages'] as $type) {
            $resultat = $this->service()->tenterRestauration($type, $archives[$type]->getKey());
            $this->assertFalse($resultat['ok'], "{$type} restauré dans un exercice clos");
            $this->assertStringContainsString('2026', $resultat['message'], $type);
            $this->assertFalse((bool) $archives[$type]->fresh()->is_active, $type);
        }
        // un élément NON daté d'un exercice (client, produit) se restaure toujours
        $this->assertTrue($this->service()->tenterRestauration('clients', $archives['clients']->id)['ok']);
        // et l'élément refusé le dit sur la ligne
        $this->assertFalse($this->element('devis', $archives['devis']->id)['restaurable']);
        $this->assertStringContainsString('2026', $this->element('devis', $archives['devis']->id)['motif_restauration']);
    }

    public function test_type_inconnu_element_introuvable_ou_deja_actif(): void
    {
        $actif = $this->client('Actif', true);

        $this->assertFalse($this->service()->tenterRestauration('App\\Models\\User', $this->admin->id)['ok']);
        $this->assertFalse($this->service()->tenterRestauration('utilisateurs', $this->admin->id)['ok']);
        $this->assertFalse($this->service()->tenterRestauration('ecritures', $actif->id)['ok']);
        $this->assertSame('Restauration impossible : élément introuvable ou déjà restauré.', $this->service()->tenterRestauration('clients', $actif->id)['message']);
        $this->assertSame('Restauration impossible : élément introuvable ou déjà restauré.', $this->service()->tenterRestauration('clients', '00000000-0000-4000-8000-000000000000')['message']);
        $this->assertFalse($this->service()->restaurer('clients', $actif->id), "l'ancien contrat booléen est conservé");
    }

    // ═════════════════════════════════════ SUPPRESSION DÉFINITIVE ═════════════════════════════════════

    public function test_suppression_exige_le_mot_supprimer_exactement(): void
    {
        $client = $this->client('Kossi Adjovi');

        foreach (['', 'supprimer', 'SUPPRIMER ', 'OUI', 'Supprimer'] as $mauvais) {
            $resultat = $this->service()->supprimerDefinitivement('clients', $client->id, $mauvais);
            $this->assertFalse($resultat['ok'], "« {$mauvais} » accepté");
            $this->assertSame('Pour confirmer, saisissez le mot SUPPRIMER.', $resultat['message']);
        }
        $this->assertDatabaseHas('customers', ['id' => $client->id]);
        $this->assertSame(0, AuditLog::where('action', 'corbeille.deleted')->count());

        $resultat = $this->service()->supprimerDefinitivement('clients', $client->id, 'SUPPRIMER');

        $this->assertTrue($resultat['ok']);
        $this->assertSame('Élément supprimé définitivement.', $resultat['message']);
        $this->assertDatabaseMissing('customers', ['id' => $client->id]);
        $this->assertSame(1, AuditLog::where('action', 'corbeille.deleted')->count());
        $journal = DB::table('corbeille_operations')->where('action', 'supprimer')->first();
        $this->assertSame('clients', $journal->type);
        $this->assertSame($client->id, $journal->element_id);
        $this->assertSame('Kossi Adjovi', $journal->titre, 'le titre survit à la ligne supprimée');
        $this->assertSame($this->admin->id, $journal->user_id);
    }

    /** PRD § 5.3 — SOGEA (3 ventes) : refus nominatif, rien n'est supprimé. */
    public function test_un_client_reference_par_des_ventes_ne_se_supprime_pas(): void
    {
        $sogea = $this->client('SOGEA');
        foreach (range(1, 3) as $_) {
            $this->vente($sogea);
        }

        $resultat = $this->service()->supprimerDefinitivement('clients', $sogea->id, 'SUPPRIMER');

        $this->assertFalse($resultat['ok']);
        $this->assertStringContainsString('SOGEA est référencé par', $resultat['message']);
        $this->assertStringContainsString('3 vente(s)', $resultat['message']);
        $this->assertStringContainsString('il reste archivé', $resultat['message']);
        $this->assertDatabaseHas('customers', ['id' => $sogea->id]);
        $this->assertSame(0, AuditLog::where('action', 'corbeille.deleted')->count());
        $this->assertFalse($this->element('clients', $sogea->id)['supprimable']);
        $this->assertSame($resultat['message'], $this->element('clients', $sogea->id)['motif_suppression']);
    }

    public function test_produit_fournisseur_et_employe_references_ne_se_suppriment_pas(): void
    {
        // produit : une ligne de vente et un mouvement de stock
        $this->vente($this->client('Acheteur', true));
        StockMovement::create(['product_id' => $this->produit->id, 'type' => 'entree', 'quantity' => 5, 'reference_type' => 'initial', 'reason' => 'Stock initial', 'movement_date' => '2026-06-01']);
        $this->produit->update(['is_active' => false]);
        $r = $this->service()->supprimerDefinitivement('produits', $this->produit->id, 'SUPPRIMER');
        $this->assertFalse($r['ok']);
        $this->assertStringContainsString('1 ligne(s) de vente', $r['message']);
        $this->assertStringContainsString('1 mouvement(s) de stock', $r['message']);
        $this->assertDatabaseHas('products', ['id' => $this->produit->id]);

        // fournisseur : une dépense l'a pour fournisseur (colonne sans contrainte étrangère)
        $this->fournisseur->update(['is_active' => false]);
        app(SaisieDepenseAction::class)->creer($this->document(['supplier_id' => $this->fournisseur->id]));
        $r = $this->service()->supprimerDefinitivement('fournisseurs', $this->fournisseur->id, 'SUPPRIMER');
        $this->assertFalse($r['ok']);
        $this->assertStringContainsString('dépense(s)', $r['message']);
        $this->assertDatabaseHas('suppliers', ['id' => $this->fournisseur->id]);

        // employé : un pointage (même archivé) le référence
        $employe = $this->employe();
        AttendanceRecord::create(['employee_id' => $employe->id, 'attendance_date' => '2026-06-04', 'status' => 'present', 'is_active' => false]);
        $r = $this->service()->supprimerDefinitivement('employes', $employe->id, 'SUPPRIMER');
        $this->assertFalse($r['ok']);
        $this->assertStringContainsString('pointage(s)', $r['message']);
        $this->assertDatabaseHas('employees', ['id' => $employe->id]);
    }

    /** Sans la moindre référence, produit, fournisseur et employé se suppriment. */
    public function test_produit_fournisseur_et_employe_non_references_se_suppriment(): void
    {
        $produit = Product::create(['sku' => 'TMP-001', 'name' => 'Erreur de saisie', 'category_id' => $this->produit->category_id, 'unit' => 'sac', 'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => false]);
        $fournisseur = Supplier::create(['name' => 'Doublon', 'is_active' => false]);
        $employe = $this->employe();

        foreach ([['produits', $produit], ['fournisseurs', $fournisseur], ['employes', $employe]] as [$type, $ligne]) {
            $this->assertTrue($this->element($type, $ligne->id)['supprimable'], $type);
            $r = $this->service()->supprimerDefinitivement($type, $ligne->id, 'SUPPRIMER');
            $this->assertTrue($r['ok'], $type.' : '.$r['message']);
            $this->assertNull($ligne::find($ligne->id), $type);
        }
        $this->assertSame(3, AuditLog::where('action', 'corbeille.deleted')->count());
    }

    /** Les barèmes, absences, documents et pièces se suppriment (aucune conséquence, aucune référence). */
    public function test_types_sans_consequence_se_suppriment(): void
    {
        $archives = $this->toutArchiver();

        foreach (['rations', 'provendes', 'prophylaxie', 'absences', 'documents', 'pieces'] as $type) {
            $ligne = $archives[$type];
            $this->assertTrue($this->element($type, $ligne->getKey())['supprimable'], $type);
            $r = $this->service()->supprimerDefinitivement($type, $ligne->getKey(), 'SUPPRIMER');
            $this->assertTrue($r['ok'], $type.' : '.$r['message']);
            $this->assertNull($ligne::find($ligne->getKey()), "{$type} encore en base");
        }
    }

    /** Jamais une pièce ou un fait comptable, zootechnique ou numéroté : dépense, vente, devis, avance, courrier, pointage, bande, soin, compte, transfert. */
    public function test_les_types_interdits_ne_se_suppriment_jamais(): void
    {
        $archives = $this->toutArchiver();
        $comptesAvant = DB::table('accounting_entries')->count();

        foreach (['depenses', 'ventes', 'devis', 'avances', 'courriers', 'pointages', 'bandes', 'soins', 'comptes', 'transferts'] as $type) {
            $ligne = $archives[$type];
            $e = $this->element($type, $ligne->getKey());
            $this->assertFalse($e['supprimable'], "{$type} annoncé supprimable");
            $this->assertNotEmpty($e['motif_suppression'], "{$type} : motif");

            $r = $this->service()->supprimerDefinitivement($type, $ligne->getKey(), 'SUPPRIMER');
            $this->assertFalse($r['ok'], "{$type} supprimé !");
            $this->assertSame($e['motif_suppression'], $r['message']);
            $this->assertNotNull($ligne::find($ligne->getKey()), "{$type} a disparu de la base");
        }
        $this->assertSame($comptesAvant, DB::table('accounting_entries')->count());
        $this->assertSame(0, AuditLog::where('action', 'corbeille.deleted')->count());
    }

    public function test_un_element_actif_ou_inconnu_ne_se_supprime_pas(): void
    {
        $actif = $this->client('Actif', true);

        $r = $this->service()->supprimerDefinitivement('clients', $actif->id, 'SUPPRIMER');
        $this->assertFalse($r['ok']);
        $this->assertSame('Suppression impossible : élément introuvable ou non archivé.', $r['message']);
        $this->assertDatabaseHas('customers', ['id' => $actif->id]);
        $this->assertFalse($this->service()->supprimerDefinitivement('App\\Models\\User', $this->admin->id, 'SUPPRIMER')['ok']);
        $this->assertDatabaseHas('users', ['id' => $this->admin->id]);
        $this->assertFalse($this->service()->supprimerDefinitivement('utilisateurs', $this->admin->id, 'SUPPRIMER')['ok']);
    }

    // ═════════════════════════════════════ ÉCRAN LIVEWIRE ═════════════════════════════════════

    public function test_l_ecran_liste_les_actions_et_dit_pourquoi_une_action_est_interdite(): void
    {
        $archives = $this->toutArchiver();

        Livewire::test(Corbeille::class)
            ->assertSee('Corbeille')
            ->assertSee('Éléments archivés')
            ->assertSee('Restaurables')
            ->assertSee('Suppression définitive possible')
            ->assertSee('Kossi Adjovi')
            ->assertSee('Restaurer')
            ->assertSee('Supprimer définitivement')
            // refus DIT à l'écran, sous forme de phrase (pas de bouton mort)
            ->assertSee('ne rejouerait ni l\'un ni l\'autre')
            ->assertSee('Une vente annulée a réintégré son stock');
        $this->assertNotNull($archives['depenses']);
    }

    public function test_restaurer_depuis_l_ecran_et_refus_dit_par_un_toast(): void
    {
        $archives = $this->toutArchiver();

        Livewire::test(Corbeille::class)
            ->call('restaurer', 'clients', $archives['clients']->id)
            ->assertDispatched('toast', message: 'Élément restauré — il réapparaît dans son module.', type: 'success')
            ->call('restaurer', 'depenses', $archives['depenses']->id)
            ->assertDispatched('toast', message: 'Cette dépense a été contre-passée au grand livre et son montant réintégré en trésorerie : la restaurer ne rejouerait ni l\'un ni l\'autre. Saisissez une nouvelle dépense.', type: 'error');

        $this->assertTrue((bool) $archives['clients']->fresh()->is_active);
        $this->assertFalse((bool) $archives['depenses']->fresh()->is_active);
    }

    public function test_suppression_en_deux_temps_depuis_l_ecran(): void
    {
        $client = $this->client('Kossi Adjovi');

        $composant = Livewire::test(Corbeille::class)
            ->call('demanderSuppression', 'clients', $client->id)
            ->assertSet('suppressionType', 'clients')
            ->assertSet('suppressionId', $client->id)
            ->assertDispatched('open-modal', name: 'modal-confirm-suppression-definitive')
            ->set('confirmation', 'oui')
            ->call('supprimerDefinitivement')
            ->assertDispatched('toast', message: 'Pour confirmer, saisissez le mot SUPPRIMER.', type: 'error');
        $this->assertDatabaseHas('customers', ['id' => $client->id]);

        $composant->set('confirmation', 'SUPPRIMER')
            ->call('supprimerDefinitivement')
            ->assertDispatched('toast', message: 'Élément supprimé définitivement.', type: 'success')
            ->assertSet('suppressionId', null)
            ->assertSet('confirmation', '');
        $this->assertDatabaseMissing('customers', ['id' => $client->id]);
    }

    /** Ouvrir la modale d'un type interdit ou référencé est refusé AVANT la saisie du mot (rien n'est ouvert). */
    public function test_la_modale_ne_s_ouvre_pas_pour_un_element_non_supprimable(): void
    {
        $archives = $this->toutArchiver();

        Livewire::test(Corbeille::class)
            ->call('demanderSuppression', 'depenses', $archives['depenses']->id)
            ->assertNotDispatched('open-modal')
            ->assertDispatched('toast', type: 'error')
            ->assertSet('suppressionId', null);
    }

    public function test_un_non_administrateur_ne_peut_ni_voir_ni_restaurer_ni_supprimer(): void
    {
        $client = $this->client('Kossi Adjovi');
        $caissier = User::create(['name' => 'Caissière', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $caissier->assignRole('caissier');
        $this->actingAs($caissier);

        foreach (['restaurer' => ['clients', $client->id], 'demanderSuppression' => ['clients', $client->id], 'supprimerDefinitivement' => []] as $methode => $arguments) {
            $refuse = false;
            try {
                Livewire::test(Corbeille::class)->call($methode, ...$arguments);
            } catch (\Throwable) {
                $refuse = true;
            }
            $this->assertTrue($refuse, "{$methode} accepté pour un caissier");
        }
        $this->assertDatabaseHas('customers', ['id' => $client->id, 'is_active' => false]);
        $this->assertSame(0, AuditLog::whereIn('action', ['corbeille.restored', 'corbeille.deleted'])->count());
        // et le service, appelé directement avec ce compte, ne fait pas confiance à l'écran
        $this->assertFalse($this->service()->tenterRestauration('clients', $client->id, null, $caissier)['ok']);
        $this->assertFalse($this->service()->supprimerDefinitivement('clients', $client->id, 'SUPPRIMER', null, $caissier)['ok']);
        $this->assertDatabaseHas('customers', ['id' => $client->id, 'is_active' => false]);
    }

    public function test_filtres_de_l_ecran_et_reinitialisation(): void
    {
        $this->client('Kossi Adjovi');
        Supplier::create(['name' => 'Provenderie du Plateau', 'is_active' => false]);

        Livewire::test(Corbeille::class)
            ->set('typeFiltre', 'fournisseurs')
            ->assertSee('Provenderie du Plateau')
            ->assertDontSee('Kossi Adjovi')
            ->set('typeFiltre', '')
            ->set('recherche', 'kossi')
            ->assertSee('Kossi Adjovi')
            ->assertDontSee('Provenderie du Plateau')
            ->set('du', '2030-01-01')
            ->assertSee('Aucun élément archivé ne correspond')
            ->call('reinitialiserFiltres')
            ->assertSet('recherche', '')
            ->assertSet('typeFiltre', '')
            ->assertSet('du', '')
            ->assertSee('Provenderie du Plateau');
    }

    public function test_corbeille_vide_et_pagination(): void
    {
        Livewire::test(Corbeille::class)->assertSee('La corbeille est vide — aucun élément archivé.');

        foreach (range(1, 27) as $i) {
            Customer::create(['name' => sprintf('Client %02d', $i), 'is_active' => false]);
        }
        Customer::query()->update(['updated_at' => '2026-06-01 08:00:00']);

        $page1 = Livewire::test(Corbeille::class);
        $this->assertSame(25, count($page1->viewData('page')->items()));
        $page1->assertSee('27');
        $this->assertSame(2, $page1->viewData('page')->lastPage());
    }

    /** L'onglet du hub Paramètres s'appelle « Corbeille » ; l'ancienne clé `restauration` y mène encore. */
    public function test_l_onglet_du_hub_s_appelle_corbeille(): void
    {
        $this->get('/parametres-hub?tab=corbeille')->assertOk()->assertSee('Corbeille')->assertDontSee('>Restauration<', false);
        $this->get('/parametres-hub?tab=restauration')->assertOk()->assertSee('Éléments archivés');
    }
}
