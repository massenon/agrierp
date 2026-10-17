<?php

namespace Tests\Feature;

use App\Models\Permission;
use App\Models\Role;
use App\Models\Supplier;
use App\Models\SupplierPayment;
use App\Models\SupplierRefund;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\ImportModuleService;
use App\Services\ReinitialisationDonneesService;
use App\Services\SauvegardeService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket 15.20 — réinitialisation et sauvegarde des tables d'achats fournisseurs.
 *
 * Défaut constaté : `supplier_payments` (ticket 15.16) n'avait été ajouté ni à `ReinitialisationDonneesService` ni au
 * module « achats » de `SauvegardeService` - la réinitialisation le laissait orphelin (règlements sans fournisseur) et
 * une sauvegarde par module ne l'exportait pas. Même oubli évité ici pour `supplier_refunds`.
 */
class SauvegardeAchatsFournisseursTest extends TestCase
{
    use RefreshDatabase;

    private Supplier $fournisseur;

    private TreasuryAccount $caisse;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('local');

        // RefreshDatabase enveloppe le test dans une transaction : SQLite y ignore la suspension des clés étrangères de
        // l'import. On les DIFFÈRE ici (même remarque que SauvegardeCompteurEcrituresTest).
        DB::statement('PRAGMA defer_foreign_keys = ON');

        foreach (['view-parametres', 'manage-parametres'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-parametres', 'manage-parametres']);
        $admin = User::create([
            'name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $admin->assignRole('admin');
        $this->actingAs($admin);

        $this->fournisseur = Supplier::create(['name' => 'Provenderie du Plateau', 'is_active' => true]);
        $this->caisse = TreasuryAccount::create([
            'label' => 'Caisse', 'account_code' => '531', 'type' => 'caisse', 'balance' => 0, 'is_active' => true,
        ]);
    }

    private function reglement(): SupplierPayment
    {
        $p = new SupplierPayment();
        $p->id = (string) Str::uuid();
        $p->fill([
            'supplier_id' => $this->fournisseur->id, 'treasury_account_id' => $this->caisse->id,
            'amount' => 30000, 'applied_amount' => 30000, 'payment_date' => '2026-10-01', 'device_id' => 'poste-1',
        ])->save();

        return $p;
    }

    private function remboursement(): SupplierRefund
    {
        $r = new SupplierRefund();
        $r->id = (string) Str::uuid();
        $r->fill([
            'supplier_id' => $this->fournisseur->id, 'treasury_account_id' => $this->caisse->id,
            'amount' => 20000, 'applied_amount' => 20000, 'refund_date' => '2026-10-02', 'device_id' => 'poste-1',
        ])->save();

        return $r;
    }

    public function test_le_module_achats_contient_reglements_et_remboursements_avant_les_fournisseurs(): void
    {
        $tables = SauvegardeService::modules()['achats']['tables'];

        foreach (['supplier_payments', 'supplier_refunds'] as $table) {
            $this->assertContains($table, $tables);
            $this->assertLessThan(
                array_search('suppliers', $tables, true),
                array_search($table, $tables, true),
                "Enfant d'abord : {$table} référence suppliers.",
            );
        }
    }

    public function test_aller_retour_export_import_du_module_achats_restaure_reglements_et_remboursements(): void
    {
        $p = $this->reglement();
        $r = $this->remboursement();

        $fichier = app(SauvegardeService::class)->genererModule('achats');
        $sql = Storage::disk('local')->get(SauvegardeService::DOSSIER.'/'.$fichier);
        $this->assertStringContainsString('INSERT INTO `supplier_payments`', $sql);
        $this->assertStringContainsString('INSERT INTO `supplier_refunds`', $sql);

        // Les lignes disparaissent (autre état de la base), puis la restauration les ramène.
        DB::table('supplier_payments')->delete();
        DB::table('supplier_refunds')->delete();
        $this->assertSame(0, SupplierPayment::count() + SupplierRefund::count());

        app(ImportModuleService::class)->importer($sql, 'achats');

        $this->assertNotNull(SupplierPayment::find($p->id));
        $this->assertNotNull(SupplierRefund::find($r->id));
        $this->assertEquals(20000, SupplierRefund::find($r->id)->applied_amount);
        $this->assertNotNull(Supplier::find($this->fournisseur->id));
    }

    public function test_un_remplacement_du_module_efface_aussi_les_reglements_et_remboursements_qui_ne_sont_pas_dans_la_sauvegarde(): void
    {
        $fichier = app(SauvegardeService::class)->genererModule('achats');
        $sql = Storage::disk('local')->get(SauvegardeService::DOSSIER.'/'.$fichier);

        $this->reglement();
        $this->remboursement();

        app(ImportModuleService::class)->importer($sql, 'achats');

        // La sauvegarde ne contenait aucun règlement ni remboursement : aucun orphelin ne survit au remplacement.
        $this->assertSame(0, SupplierPayment::count());
        $this->assertSame(0, SupplierRefund::count());
    }

    public function test_la_reinitialisation_vide_reglements_et_remboursements(): void
    {
        $this->reglement();
        $this->remboursement();

        app(ReinitialisationDonneesService::class)->executer();

        $this->assertSame(0, SupplierPayment::count());
        $this->assertSame(0, SupplierRefund::count());
        $this->assertSame(0, Supplier::count());
    }

    /**
     * GARDE-FOU : toute table qui référence une table d'achats (fournisseurs, achats, comptes de trésorerie parmi les
     * tables d'activité...) doit être VIDÉE par la réinitialisation ET rangée dans un module de sauvegarde. L'oubli de
     * `supplier_payments` ne levait aucune erreur : seule une table restée pleine au mauvais endroit le trahissait.
     */
    public function test_toute_table_enfant_des_achats_est_reinitialisee_et_sauvegardee(): void
    {
        $parents = ['suppliers', 'purchases', 'purchase_orders', 'payables'];
        $enModule = collect(SauvegardeService::modules())->flatMap(fn ($m) => $m['tables'])->all();
        $oublis = [];

        foreach (Schema::getTableListing(schemaQualified: false) as $table) {
            foreach (Schema::getForeignKeys($table) as $cle) {
                if (! in_array($cle['foreign_table'], $parents, true)) {
                    continue;
                }

                if (! in_array($table, ReinitialisationDonneesService::tablesTransactionnelles(), true)) {
                    $oublis[] = "{$table} (référence {$cle['foreign_table']}) absente de la réinitialisation";
                }

                if (! in_array($table, $enModule, true)) {
                    $oublis[] = "{$table} (référence {$cle['foreign_table']}) absente des modules de sauvegarde";
                }
            }
        }

        $this->assertSame([], array_values(array_unique($oublis)));
    }
}
