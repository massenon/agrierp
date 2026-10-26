<?php

namespace Tests\Feature;

use App\Actions\AnnulerVenteAction;
use App\Actions\SaisieBandeAction;
use App\Actions\SaisieDepenseAction;
use App\Actions\SaisieDevisAction;
use App\Actions\TransferBetweenLotsAction;
use App\Livewire\Comptabilite\PlanComptable;
use App\Livewire\Elevage\ParametresElevage;
use App\Livewire\Elevage\SoinsVaccinsHub;
use App\Livewire\Parametres\Corbeille;
use App\Livewire\RH\FeuillePointage;
use App\Livewire\RH\RegistreEmployes;
use App\Livewire\RH\RegistreStagiaires;
use App\Livewire\Stocks\CatalogueProduits;
use App\Models\AdministrativeDocument;
use App\Models\ArchivedDocument;
use App\Models\AttendanceRecord;
use App\Models\AuditLog;
use App\Models\ChartOfAccount;
use App\Models\Correspondence;
use App\Models\Customer;
use App\Models\CustomerAdvance;
use App\Models\Employee;
use App\Models\FeedRationStandard;
use App\Models\FeedType;
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
use App\Models\Supplier;
use App\Models\User;
use App\Models\VeterinaryRecord;
use App\Services\ArchiveDocumentService;
use App\Services\CorbeilleService;
use App\Services\CourrierService;
use App\Services\CustomerAdvanceService;
use App\Services\CustomerCatalogService;
use App\Services\DocumentAdministratifService;
use App\Services\SupplierCatalogService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket ARC-Q2 (PRD `docs/prd/archives.md`) — « ARCHIVÉ PAR » : la Corbeille dit QUI a archivé.
 *
 * Décision du client : OUI, on veut savoir qui a archivé. `audit_logs` retient désormais l'enregistrement visé
 * (`entity_type` / `entity_id`) ; la Corbeille lit le DERNIER audit d'archivage de chaque élément.
 *
 * ⚠️ Ce que ces tests protègent :
 *  - CHAQUE chemin d'archivage (web ET poste) renseigne l'entité visée : un test par type de la Corbeille, l'auteur
 *    étant un AUTRE compte que l'administrateur (un test qui archive avec le même compte ne prouverait rien) ;
 *  - un archivage antérieur à la migration (aucune entité en audit) s'affiche « — » : jamais « 0 », jamais un nom inventé ;
 *  - au poste, l'auteur est l'utilisateur du JETON, et un renvoi (accusé perdu) ne change pas l'auteur.
 *
 * ⚠️ Toute date est FIGÉE (20/06/2026).
 */
class CorbeilleArchiveParTest extends TestCase
{
    use DecorDepenses;
    use RefreshDatabase;

    private User $marie;

    private LivestockSpecies $espece;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerDecorDepenses();

        $this->marie = User::create(['name' => 'Marie Gestionnaire', 'username' => 'marie', 'email' => 'marie@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $this->marie->assignRole('admin');

        $this->espece = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'ALI-001', 'name' => 'Maïs concassé', 'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true,
        ]);
    }

    private function element(string $type, string $id): array
    {
        foreach (app(CorbeilleService::class)->elements() as $e) {
            if ($e['type'] === $type && $e['id'] === $id) {
                return $e;
            }
        }
        $this->fail("« $type » $id absent de la Corbeille");
    }

    private function bande(string $code, bool $active = true): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $this->espece->id, 'stage' => 'ponte', 'initial_quantity' => 0, 'current_quantity' => 0,
            'created_date' => '2026-05-01', 'status' => 'actif', 'is_active' => $active,
        ]);
    }

    // ═════════════════════════════════ LE CONTRAT : audit_logs ═════════════════════════════════

    public function test_audit_logs_porte_l_enregistrement_vise_en_colonnes_facultatives(): void
    {
        $this->assertTrue(Schema::hasColumns('audit_logs', ['entity_type', 'entity_id']));
        $this->assertTrue(Schema::hasIndex('audit_logs', 'audit_logs_entite_visee_index'));

        // Les appels existants (sans entité) fonctionnent toujours et laissent les colonnes vides.
        $ancien = AuditLog::record('login', 'auth');
        $this->assertNull($ancien->fresh()->entity_type);
        $this->assertNull($ancien->fresh()->entity_id);

        $client = Customer::create(['name' => 'Kossi', 'is_active' => true]);
        $neuf = AuditLog::record('customer.archived', 'ventes', null, $client);
        $this->assertSame(Customer::class, $neuf->fresh()->entity_type);
        $this->assertSame($client->id, $neuf->fresh()->entity_id);
    }

    /** Migration SÛRE et REJOUABLE : la rejouer ne casse rien et ne perd aucune donnée. */
    public function test_la_migration_se_rejoue_sans_perdre_de_donnees(): void
    {
        $client = Customer::create(['name' => 'Kossi', 'is_active' => true]);
        $log = AuditLog::record('customer.archived', 'ventes', null, $client);

        $migration = require database_path('migrations/2026_10_26_000001_audit_logs_entite_visee.php');
        $migration->up();
        $migration->up();

        $this->assertSame($client->id, $log->fresh()->entity_id);

        $migration->down();
        $this->assertFalse(Schema::hasColumn('audit_logs', 'entity_type'));
        $migration->down();
        $migration->up();
        $this->assertTrue(Schema::hasColumns('audit_logs', ['entity_type', 'entity_id']));
    }

    // ═════════════════════════ UN TEST PAR TYPE : l'auteur est lu en Corbeille ═════════════════════════

    /**
     * Chaque entrée archive un enregistrement par SON chemin réel (service, action ou écran) et rend [type, id].
     *
     * @return array<string, array{0: \Closure}>
     */
    public static function chemins(): array
    {
        return [
            'clients' => [fn (self $t) => $t->archiverClient()],
            'fournisseurs' => [fn (self $t) => $t->archiverFournisseur()],
            'produits' => [fn (self $t) => $t->archiverProduit()],
            'depenses' => [fn (self $t) => $t->archiverDepense()],
            'bandes' => [fn (self $t) => $t->archiverBande()],
            'soins' => [fn (self $t) => $t->archiverSoin()],
            'rations' => [fn (self $t) => $t->archiverRation()],
            'provendes' => [fn (self $t) => $t->archiverProvende()],
            'prophylaxie' => [fn (self $t) => $t->archiverProphylaxie()],
            'absences' => [fn (self $t) => $t->archiverAbsence()],
            'documents' => [fn (self $t) => $t->archiverDocument()],
            'pieces' => [fn (self $t) => $t->archiverPiece()],
            'courriers' => [fn (self $t) => $t->archiverCourrier()],
            'comptes' => [fn (self $t) => $t->archiverCompte()],
            'devis' => [fn (self $t) => $t->archiverDevis()],
            'avances' => [fn (self $t) => $t->archiverAvance()],
            'employes' => [fn (self $t) => $t->archiverEmploye()],
            'pointages' => [fn (self $t) => $t->archiverPointage()],
            'ventes' => [fn (self $t) => $t->annulerVente()],
            'transferts' => [fn (self $t) => $t->annulerTransfert()],
        ];
    }

    /** @dataProvider chemins */
    #[\PHPUnit\Framework\Attributes\DataProvider('chemins')]
    public function test_l_auteur_de_l_archivage_est_affiche_pour_chaque_type(\Closure $archiver): void
    {
        $this->actingAs($this->marie);
        [$type, $id] = $archiver($this);

        $this->assertSame('Marie Gestionnaire', $this->element($type, $id)['archive_par'], "auteur de l'archivage : $type");
        $this->assertDatabaseHas('audit_logs', ['entity_id' => $id, 'user_id' => $this->marie->id]);
    }

    public function archiverClient(): array
    {
        $c = Customer::create(['name' => 'Kossi Adjovi', 'is_active' => true]);
        app(CustomerCatalogService::class)->archiver($c);

        return ['clients', $c->id];
    }

    public function archiverFournisseur(): array
    {
        $f = Supplier::create(['name' => 'Provenderie du Plateau', 'is_active' => true]);
        app(SupplierCatalogService::class)->archiver($f);

        return ['fournisseurs', $f->id];
    }

    public function archiverProduit(): array
    {
        $p = Product::create(['sku' => 'ALI-002', 'name' => 'Son de blé', 'category_id' => $this->produit->category_id, 'unit' => 'sac', 'pricing_mode' => 'fourchette', 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true]);
        Livewire::test(CatalogueProduits::class)->call('archive', $p->id);

        return ['produits', $p->id];
    }

    public function archiverDepense(): array
    {
        $d = app(SaisieDepenseAction::class)->creer($this->document());
        app(SaisieDepenseAction::class)->archiver($d->id);

        return ['depenses', $d->id];
    }

    public function archiverBande(): array
    {
        $b = $this->bande('LAP-2026-01');
        app(SaisieBandeAction::class)->archiver($b->id);

        return ['bandes', $b->id];
    }

    public function archiverSoin(): array
    {
        $s = VeterinaryRecord::create(['lot_id' => $this->bande('LAP-2026-01')->id, 'action_type' => 'Vaccination', 'product_used' => 'Pasteurellose', 'record_date' => '2026-06-01', 'is_active' => true]);
        Livewire::test(SoinsVaccinsHub::class)->call('archiveSoin', $s->id);

        return ['soins', $s->id];
    }

    public function archiverRation(): array
    {
        $r = FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Lapin Sevré', 'ration_g_per_day' => 30, 'is_active' => true]);
        Livewire::test(ParametresElevage::class)->call('deleteRation', $r->id);

        return ['rations', $r->id];
    }

    public function archiverProvende(): array
    {
        $p = FeedType::create(['name' => 'Provende croissance', 'species_id' => $this->espece->id, 'standard_bag_weight_kg' => 25, 'price_per_kg' => 400, 'is_active' => true]);
        Livewire::test(ParametresElevage::class)->call('deleteProvende', $p->id);

        return ['provendes', $p->id];
    }

    public function archiverProphylaxie(): array
    {
        $p = ProphylaxisScheduleStandard::create(['species_code' => 'cuniculture', 'period_label' => 'Sevrage', 'cycle_day_start' => 28, 'cycle_day_end' => 35, 'treatment' => 'Vermifuge', 'product_recommended' => 'Pipérazine', 'dosage' => '1 ml', 'is_active' => true]);
        Livewire::test(ParametresElevage::class)->call('deleteProphy', $p->id);

        return ['prophylaxie', $p->id];
    }

    public function archiverAbsence(): array
    {
        $stagiaire = Internship::create(['first_name' => 'Ruth', 'last_name' => 'DOSSOU', 'start_date' => '2026-05-01', 'end_date' => '2026-08-01']);
        $a = InternshipAbsence::create(['internship_id' => $stagiaire->id, 'absence_date' => '2026-06-02', 'reason' => 'Maladie', 'is_active' => true]);
        Livewire::test(RegistreStagiaires::class)->call('deleteAbsence', $a->id);

        return ['absences', $a->id];
    }

    public function archiverDocument(): array
    {
        $d = AdministrativeDocument::create(['title' => 'Attestation de stage', 'type' => 'attestation', 'beneficiary' => 'Ruth DOSSOU', 'doc_date' => '2026-06-03', 'status' => 'signe', 'is_active' => true]);
        app(DocumentAdministratifService::class)->archiver($d);

        return ['documents', $d->id];
    }

    public function archiverPiece(): array
    {
        $p = ArchivedDocument::create(['title' => 'Bail du terrain', 'category' => 'Juridique', 'archived_date' => '2026-06-03', 'is_active' => true]);
        app(ArchiveDocumentService::class)->archiver($p);

        return ['pieces', $p->id];
    }

    public function archiverCourrier(): array
    {
        $c = Correspondence::create(['reference' => 'CR-2026-001', 'type' => 'entrant', 'subject' => 'Demande de visite', 'party' => 'Mairie', 'mail_date' => '2026-06-03', 'is_active' => true]);
        app(CourrierService::class)->archiver($c);

        return ['courriers', $c->id];
    }

    public function archiverCompte(): array
    {
        $c = ChartOfAccount::create(['code' => '6288', 'label' => 'Charges inutilisées', 'class' => 6, 'is_active' => true]);
        Livewire::test(PlanComptable::class)->call('archiveAccount', $c->id);

        return ['comptes', $c->id];
    }

    public function archiverDevis(): array
    {
        $acheteur = Customer::create(['name' => 'Acheteur Actif', 'is_active' => true]);
        $d = Quote::create(['quote_number' => 'DEV-2026-001', 'customer_id' => $acheteur->id, 'articles_description' => '2 cages', 'amount' => 150000, 'tva_rate' => 18, 'validity_days' => 15, 'quote_date' => '2026-06-05', 'status' => 'brouillon', 'is_active' => true]);
        app(SaisieDevisAction::class)->archiver($d->id);

        return ['devis', $d->id];
    }

    public function archiverAvance(): array
    {
        $acheteur = Customer::create(['name' => 'Acheteur Actif', 'is_active' => true]);
        $a = CustomerAdvance::create(['customer_id' => $acheteur->id, 'amount' => 20000, 'amount_used' => 20000, 'advance_date' => '2026-06-05', 'is_active' => true]);
        app(CustomerAdvanceService::class)->archiver($a);

        return ['avances', $a->id];
    }

    public function archiverEmploye(): array
    {
        $e = Employee::create(['first_name' => 'Ange', 'last_name' => 'TOSSOU', 'position' => 'Ouvrier', 'base_salary' => 50000, 'hire_date' => '2025-01-01', 'status' => 'actif', 'is_active' => true]);
        Livewire::test(RegistreEmployes::class)->call('archiveEmployee', $e->id);

        return ['employes', $e->id];
    }

    public function archiverPointage(): array
    {
        $e = Employee::create(['first_name' => 'Ange', 'last_name' => 'TOSSOU', 'position' => 'Ouvrier', 'base_salary' => 50000, 'hire_date' => '2025-01-01', 'status' => 'actif', 'is_active' => true]);
        $p = AttendanceRecord::create(['employee_id' => $e->id, 'attendance_date' => '2026-06-04', 'status' => 'present', 'is_active' => true]);
        Livewire::test(FeuillePointage::class)->call('archiveRecord', $p->id);

        return ['pointages', $p->id];
    }

    public function annulerVente(): array
    {
        $acheteur = Customer::create(['name' => 'Acheteur Actif', 'is_active' => true]);
        $v = Sale::create(['customer_id' => $acheteur->id, 'payment_mode' => 'especes', 'subtotal' => 5000, 'discount' => 0, 'total' => 5000, 'status' => 'validee', 'sold_at' => '2026-06-10 10:00:00']);
        SaleLine::create(['sale_id' => $v->id, 'product_id' => $this->produit->id, 'qty' => 1, 'unit_price' => 5000, 'manual_total_amount' => 5000]);
        app(AnnulerVenteAction::class)->execute($v);

        return ['ventes', $v->id];
    }

    public function annulerTransfert(): array
    {
        $t = LivestockTransfer::create(['source_lot_id' => $this->bande('LAP-2026-01')->id, 'target_lot_id' => $this->bande('LAP-2026-02')->id, 'transfer_date' => '2026-06-06', 'quantity' => 3, 'constitution' => true, 'is_active' => true]);
        app(TransferBetweenLotsAction::class)->annuler($t);

        return ['transferts', $t->id];
    }

    // ═════════════════════════════ ANCIENS ARCHIVAGES, DERNIER AUTEUR, MASSE ═════════════════════════════

    /** Un archivage antérieur à la migration n'a aucune entité en audit : l'auteur est INCONNU, jamais inventé. */
    public function test_un_ancien_archivage_n_a_pas_d_auteur(): void
    {
        $client = Customer::create(['name' => 'Kossi Adjovi', 'phone' => '+22997000001', 'is_active' => false]);
        // Un audit d'archivage d'avant la migration : même action, même module, mais SANS entité.
        AuditLog::record('customer.archived', 'ventes', $this->marie->id);

        $this->assertNull($this->element('clients', $client->id)['archive_par']);

        $html = Livewire::test(Corbeille::class)->html();
        $this->assertStringContainsString('Archivé par', $html);
        $this->assertStringNotContainsString('Marie Gestionnaire', $html, 'aucun nom inventé');
        $this->assertMatchesRegularExpression('#data-label="Archivé par"[^>]*>\s*—\s*<#', $html);
        $this->assertDoesNotMatchRegularExpression('#data-label="Archivé par"[^>]*>\s*0\s*<#', $html);
    }

    public function test_la_colonne_archive_par_affiche_le_nom_de_l_auteur(): void
    {
        $this->actingAs($this->marie);
        [, $id] = $this->archiverClient();
        $this->actingAs($this->admin);

        $html = Livewire::test(Corbeille::class)->html();

        $this->assertMatchesRegularExpression('#data-label="Archivé par"[^>]*>\s*Marie Gestionnaire\s*<#', $html);
        $this->assertStringContainsString('Archivé le', $html);
        $this->assertNotNull($this->element('clients', $id)['archive_le']);
    }

    /** Restauré puis archivé une seconde fois par un autre compte : le DERNIER archivage fait foi. */
    public function test_le_dernier_archivage_fait_foi(): void
    {
        $this->actingAs($this->marie);
        [, $id] = $this->archiverClient();
        $this->assertSame('Marie Gestionnaire', $this->element('clients', $id)['archive_par']);

        $this->actingAs($this->admin);
        $this->assertTrue(app(CorbeilleService::class)->restaurer('clients', $id));
        $this->assertCount(0, array_filter(app(CorbeilleService::class)->elements(), fn ($e) => $e['id'] === $id));

        \Illuminate\Support\Carbon::setTestNow(\Illuminate\Support\Carbon::parse('2026-06-21 09:00', 'Africa/Porto-Novo'));
        app(CustomerCatalogService::class)->archiver(Customer::findOrFail($id));

        $this->assertSame('Direction', $this->element('clients', $id)['archive_par']);
    }

    /** Un utilisateur supprimé ou un audit sans utilisateur : « — », jamais une erreur. */
    public function test_un_audit_sans_utilisateur_donne_un_auteur_inconnu(): void
    {
        $client = Customer::create(['name' => 'Kossi Adjovi', 'is_active' => true]);
        $client->update(['is_active' => false]);
        AuditLog::create(['user_id' => null, 'action' => 'customer.archived', 'module' => 'ventes', 'entity_type' => Customer::class, 'entity_id' => $client->id]);

        $this->assertNull($this->element('clients', $client->id)['archive_par']);
    }

    /** L'archivage en masse des clients renseigne l'auteur de CHAQUE client archivé. */
    public function test_l_archivage_en_masse_renseigne_chaque_client(): void
    {
        $this->actingAs($this->marie);
        $a = Customer::create(['name' => 'Client A', 'is_active' => true]);
        $b = Customer::create(['name' => 'Client B', 'is_active' => true]);
        $deja = Customer::create(['name' => 'Client C', 'is_active' => false]);

        $this->assertSame(2, app(CustomerCatalogService::class)->archiverPlusieurs([$a->id, $b->id, $deja->id]));

        $this->assertSame('Marie Gestionnaire', $this->element('clients', $a->id)['archive_par']);
        $this->assertSame('Marie Gestionnaire', $this->element('clients', $b->id)['archive_par']);
        $this->assertNull($this->element('clients', $deja->id)['archive_par'], 'déjà archivé avant : pas de nom inventé');
    }

    // ═════════════════════════════════════ LE POSTE ═════════════════════════════════════

    private function posteur(): User
    {
        $u = User::create(['name' => 'Posteur Aimé', 'username' => 'aime', 'email' => 'aime@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $u->assignRole('admin');

        return $u;
    }

    private function pousser(User $u, array $corps): void
    {
        $this->actingAs($u, 'sanctum')->postJson('/api/sync/push', ['device_id' => 'poste-test'] + $corps)->assertOk();
    }

    /** @return array<string, array<string, mixed>> les lignes de la Corbeille servies au poste, par type */
    private function tirer(User $u): array
    {
        $corps = $this->actingAs($u, 'sanctum')->getJson('/api/sync/pull?page=1')->assertOk()->json();

        return collect($corps['corbeille'])->keyBy('type')->all();
    }

    public function test_le_tirage_sert_l_auteur_et_null_pour_un_ancien_archivage(): void
    {
        $this->actingAs($this->marie);
        [, $clientId] = $this->archiverClient();
        $this->actingAs($this->admin);
        $ancien = Supplier::create(['name' => 'Ancien fournisseur', 'is_active' => false]);

        $lignes = $this->tirer($this->admin);

        $this->assertArrayHasKey('archive_par', $lignes['clients']);
        $this->assertSame('Marie Gestionnaire', $lignes['clients']['archive_par']);
        $this->assertArrayHasKey('archive_par', $lignes['fournisseurs']);
        $this->assertNull($lignes['fournisseurs']['archive_par'], "archivage d'avant la migration : null, jamais 0 ni un nom");
        $this->assertSame($ancien->id, $lignes['fournisseurs']['element_id']);
    }

    public function test_un_client_archive_au_poste_porte_le_nom_de_l_utilisateur_du_jeton(): void
    {
        $posteur = $this->posteur();
        $fiche = ['id' => (string) Str::uuid(), 'name' => 'Restaurant Chez Mama', 'phone' => '+22997121212', 'is_active' => true];
        $this->pousser($posteur, ['customers' => [$fiche]]);
        $this->pousser($posteur, ['customers' => [array_merge($fiche, ['is_active' => false])]]);

        $this->assertSame('Posteur Aimé', $this->tirer($this->admin)['clients']['archive_par']);
    }

    public function test_une_ration_archivee_au_poste_porte_le_jeton_et_un_renvoi_ne_change_pas_l_auteur(): void
    {
        $posteur = $this->posteur();
        $id = '77777777-7777-4777-8777-777777777777';
        $ration = ['id' => $id, 'species_code' => 'cuniculture', 'stage_label' => 'Jeune', 'ration_g_per_day' => 60];
        $this->pousser($posteur, ['feed_ration_standards' => [$ration]]);
        $this->pousser($posteur, ['feed_ration_standards' => [['is_active' => false] + $ration]]);

        $this->assertSame('Posteur Aimé', $this->element('rations', $id)['archive_par']);

        // Accusé perdu : le même poste renvoie, puis un AUTRE compte renvoie — l'auteur d'origine reste.
        $this->pousser($posteur, ['feed_ration_standards' => [['is_active' => false] + $ration]]);
        $this->pousser($this->marie, ['feed_ration_standards' => [['is_active' => false] + $ration]]);

        $this->assertSame('Posteur Aimé', $this->element('rations', $id)['archive_par']);
        $this->assertSame(1, AuditLog::where('action', 'feed_ration_standard.archived')->where('entity_id', $id)->count());
    }

    public function test_un_soin_archive_au_poste_porte_le_jeton(): void
    {
        $posteur = $this->posteur();
        $id = '88888888-8888-4888-8888-888888888888';
        $soin = ['id' => $id, 'lot_id' => $this->bande('LAP-2026-09')->id, 'action_type' => 'Traitement curatif', 'product_used' => 'Oxytétracycline', 'record_date' => '2026-06-19', 'withdrawal_days' => 7, 'cost' => 2500];
        $this->pousser($posteur, ['veterinary_records' => [$soin]]);
        $this->pousser($posteur, ['veterinary_records' => [['id' => $id, 'is_active' => false]]]);

        $this->assertSame('Posteur Aimé', $this->element('soins', $id)['archive_par']);
    }

    public function test_un_transfert_annule_au_poste_porte_le_jeton(): void
    {
        $posteur = $this->posteur();
        $t = LivestockTransfer::create(['source_lot_id' => $this->bande('LAP-2026-01')->id, 'target_lot_id' => $this->bande('LAP-2026-02')->id, 'transfer_date' => '2026-06-06', 'quantity' => 3, 'constitution' => true, 'is_active' => true]);

        $this->pousser($posteur, ['livestock_transfers' => [[
            'id' => $t->id, 'source_lot_id' => $t->source_lot_id, 'target_lot_id' => $t->target_lot_id,
            'transfer_date' => '2026-06-06', 'quantity' => 3, 'constitution' => true, 'is_active' => false,
        ]]]);

        $this->assertFalse($t->fresh()->is_active);
        $this->assertSame('Posteur Aimé', $this->element('transferts', $t->id)['archive_par']);
    }

    public function test_une_depense_archivee_au_poste_porte_le_jeton(): void
    {
        $posteur = $this->posteur();
        $depense = app(SaisieDepenseAction::class)->creer($this->document());
        $donnees = ['id' => $depense->id, 'is_active' => false] + $this->document();
        $this->pousser($posteur, ['expenses' => [$donnees]]);

        $this->assertFalse($depense->fresh()->is_active);
        $this->assertSame('Posteur Aimé', $this->element('depenses', $depense->id)['archive_par']);
    }
}
