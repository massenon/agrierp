<?php

namespace Tests\Feature;

use App\Livewire\Shared\EtatSynchronisationPostes;
use App\Models\AuditLog;
use App\Models\ControleCoherence;
use App\Models\DemandeSynchronisation;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use App\Services\CoherenceSynchronisationService;
use App\Services\DemandeSynchronisationService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Tickets S-T6 et S-T7 (méthode TATACORA, `docs/COMPARAISON_METHODE_TATACORA.md`) :
 *  - « Demander la synchronisation des postes » au web, lue par les postes (`GET /api/sync/demande`) ;
 *  - comptes du serveur pour le contrôle de cohérence (`GET /api/sync/coherence`), jeu calculé à la main ;
 *  - la matrice des droits date le rôle (table de liaison `role_has_permissions`).
 */
class SupervisionSynchronisationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    /** Jeton Sanctum nommé comme le poste (`AuthController` le crée sous `device_name`). */
    private function jeton(User $u, string $poste): string
    {
        return $u->createToken($poste, ['*'], now()->addDays(90))->plainTextToken;
    }

    private function demande(string $jeton): array
    {
        // ⚠️ Le garde Sanctum garde l'utilisateur de la requête précédente d'un même test : sans cet oubli, le jeton
        // du second poste serait lu comme celui du premier.
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', 'Bearer '.$jeton)->getJson('/api/sync/demande')->assertOk()->json();
    }

    // ── S-T6 : demande de synchronisation ─────────────────────────────────────────────────────────────────────

    public function test_le_bouton_de_demande_est_dans_la_modale_de_l_administrateur_seul(): void
    {
        $this->actingAs($this->compte('admin'))->get('/dashboard')->assertOk()
            ->assertSee('Demander la synchronisation des postes');

        $caissier = $this->compte('caissier');
        $this->actingAs($caissier)->get('/dashboard')->assertOk()
            ->assertDontSee('Demander la synchronisation des postes');
        Livewire::test(EtatSynchronisationPostes::class)->assertForbidden();
    }

    public function test_demander_pour_tous_puis_pour_un_poste_ecrit_la_demande_et_l_audite(): void
    {
        $admin = $this->compte('admin');
        $caissier = $this->compte('caissier');
        $this->jeton($caissier, 'POSTE-CAISSE');
        $this->actingAs($admin);

        Livewire::test(EtatSynchronisationPostes::class)
            ->call('demander')
            ->assertDispatched('toast', message: 'Demande envoyée : les postes connectés synchroniseront dans les 30 secondes.', type: 'success')
            ->call('demander', 'POSTE-CAISSE')
            ->assertDispatched('toast', type: 'success')
            ->call('demander', 'POSTE-INCONNU')
            ->assertDispatched('toast', message: 'Poste inconnu du serveur : demande non envoyée.', type: 'error');

        $this->assertSame(2, DemandeSynchronisation::count(), 'le poste inconnu ne laisse pas de demande');
        $this->assertSame(1, DemandeSynchronisation::whereNull('poste')->count());
        $this->assertSame($admin->id, DemandeSynchronisation::where('poste', 'POSTE-CAISSE')->sole()->demandee_par);
        $this->assertSame(1, AuditLog::where('action', 'sync.demande_tous')->count());
        $this->assertSame(1, AuditLog::where('action', 'sync.demande_poste')->count());
    }

    public function test_une_demande_pour_tous_est_servie_une_fois_a_chaque_poste(): void
    {
        $admin = $this->compte('admin');
        $a = $this->jeton($this->compte('caissier'), 'POSTE-A');
        $b = $this->jeton($this->compte('animalier'), 'POSTE-B');

        $this->assertSame(['demande' => false], $this->demande($a), 'aucune demande déposée');

        Carbon::setTestNow('2026-10-19 10:00:00');
        app(DemandeSynchronisationService::class)->demander(null, $admin);

        Carbon::setTestNow('2026-10-19 10:00:20');
        $reponse = $this->demande($a);
        $this->assertTrue($reponse['demande']);
        $this->assertSame('Admin', $reponse['demandee_par']);
        $this->assertSame(['demande' => false], $this->demande($a), 'déjà servie à ce poste : une seule synchronisation');

        // L'autre poste ne l'a pas encore lue : elle lui est due.
        $this->assertTrue($this->demande($b)['demande']);
        $this->assertSame(['demande' => false], $this->demande($b));
        $this->assertSame(2, DB::table('demandes_synchronisation_servies')->count());
    }

    public function test_une_demande_pour_un_poste_ne_reveille_que_lui_et_expire_apres_une_heure(): void
    {
        $admin = $this->compte('admin');
        $a = $this->jeton($this->compte('caissier'), 'POSTE-A');
        $b = $this->jeton($this->compte('animalier'), 'POSTE-B');

        Carbon::setTestNow('2026-10-19 10:00:00');
        app(DemandeSynchronisationService::class)->demander('POSTE-A', $admin);
        $this->assertSame(['demande' => false], $this->demande($b), 'demande adressée à un autre poste');

        // Expirée : 60 minutes et une seconde plus tard, plus personne ne la lit.
        Carbon::setTestNow('2026-10-19 11:00:01');
        $this->assertSame(['demande' => false], $this->demande($a));

        Carbon::setTestNow('2026-10-19 11:00:00');
        $this->assertTrue($this->demande($a)['demande'], 'encore valide à 60 minutes pile');
    }

    public function test_la_demande_exige_un_jeton(): void
    {
        $this->getJson('/api/sync/demande')->assertUnauthorized();
        $this->getJson('/api/sync/coherence?depuis=2026-10-01')->assertUnauthorized();
    }

    // ── S-T6 : contrôle de cohérence ──────────────────────────────────────────────────────────────────────────

    private function inserer(string $table, array $colonnes): void
    {
        DB::table($table)->insert(['id' => (string) Str::uuid(), ...$colonnes]);
    }

    /**
     * Jeu calculé à la main, du 18 au 19/10/2026 (contrôle depuis le 18 ; tout ce qui précède est exclu).
     */
    private function jeuDeCoherence(): void
    {
        // Les bandes, clients, fournisseurs et produits visés n'existent pas : seuls les comptes sont mis à l'épreuve.
        // ⚠️ `PRAGMA foreign_keys` est sans effet dans la transaction de `RefreshDatabase` ; les contraintes sont donc
        // DIFFÉRÉES au COMMIT, qui n'a jamais lieu (le test se termine par un retour arrière).
        DB::statement('PRAGMA defer_foreign_keys = ON');
        $u = fn () => (string) Str::uuid();

        $vente = fn ($sold, $created, $total, $statut = 'validee') => $this->inserer('sales', [
            'payment_mode' => 'especes', 'subtotal' => $total, 'total' => $total, 'status' => $statut,
            'sold_at' => $sold, 'created_at' => $created, 'updated_at' => $created,
        ]);
        $vente('2026-10-18 09:00:00', '2026-10-18 09:00:00', 1000);
        $vente('2026-10-18 17:30:00', '2026-10-19 08:00:00', 2500.5);   // date effective = sold_at : le 18
        $vente(null, '2026-10-19 11:00:00', 700);                        // sans sold_at : created_at, le 19
        $vente('2026-10-19 12:00:00', '2026-10-19 12:00:00', 9999, 'annulee'); // annulée : exclue
        $vente('2026-10-17 23:59:59', '2026-10-17 23:59:59', 5000);      // avant `depuis` : exclue

        $this->inserer('purchases', ['supplier_id' => $u(), 'payment_mode' => 'especes', 'total' => 15000, 'purchase_date' => '2026-10-18', 'created_at' => now(), 'updated_at' => now()]);
        $this->inserer('purchases', ['supplier_id' => $u(), 'payment_mode' => 'credit', 'total' => 4000.25, 'purchase_date' => '2026-10-18', 'created_at' => now(), 'updated_at' => now()]);

        $lot = $u();
        $this->inserer('livestock_daily_entries', ['lot_id' => $lot, 'entry_date' => '2026-10-18', 'mort' => 2, 'effectif_final' => 10, 'created_at' => now(), 'updated_at' => now()]);
        $this->inserer('livestock_daily_entries', ['lot_id' => $lot, 'entry_date' => '2026-10-19', 'mort' => 0, 'effectif_final' => 10, 'created_at' => now(), 'updated_at' => now()]);
        $this->inserer('livestock_daily_entries', ['lot_id' => $u(), 'entry_date' => '2026-10-19', 'mort' => 3, 'effectif_final' => 10, 'created_at' => now(), 'updated_at' => now()]);

        $this->inserer('veterinary_records', ['lot_id' => $lot, 'action_type' => 'vaccin', 'cost' => 1200, 'record_date' => '2026-10-19', 'is_active' => true, 'created_at' => now(), 'updated_at' => now()]);
        $this->inserer('veterinary_records', ['lot_id' => $lot, 'action_type' => 'vaccin', 'cost' => 800, 'record_date' => '2026-10-19', 'is_active' => false, 'created_at' => now(), 'updated_at' => now()]);

        $this->inserer('customer_advances', ['customer_id' => $u(), 'amount' => 5000, 'advance_date' => '2026-10-19', 'is_active' => true, 'created_at' => now(), 'updated_at' => now()]);

        $this->inserer('livestock_transfers', ['source_lot_id' => $lot, 'target_lot_id' => $u(), 'transfer_date' => '2026-10-18', 'quantity' => 12, 'is_active' => true, 'created_at' => now(), 'updated_at' => now()]);

        $this->inserer('stock_movements', ['product_id' => $u(), 'type' => 'sortie', 'quantity' => 3, 'reference_type' => 'vente', 'movement_date' => '2026-10-19 08:15:00', 'created_at' => now(), 'updated_at' => now()]);
        $this->inserer('stock_movements', ['product_id' => $u(), 'type' => 'entree', 'quantity' => 1.5, 'reference_type' => 'inventaire', 'movement_date' => '2026-10-19 18:00:00', 'created_at' => now(), 'updated_at' => now()]);
    }

    public function test_les_comptes_du_serveur_par_table_et_par_jour(): void
    {
        $this->jeuDeCoherence();
        $jeton = $this->jeton($this->compte('caissier'), 'POSTE-CAISSE');

        $tables = $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->getJson('/api/sync/coherence?depuis=2026-10-18')
            ->assertOk()
            ->assertJsonPath('depuis', '2026-10-18')
            ->json('tables');

        $this->assertSame(array_keys(CoherenceSynchronisationService::AGREGATS), array_keys($tables));
        $this->assertEquals([
            '2026-10-18' => ['nombre' => 2, 'total' => 3500.5],
            '2026-10-19' => ['nombre' => 1, 'total' => 700],
        ], $tables['sales']['jours']);
        $this->assertSame('Ventes', $tables['sales']['libelle']);
        $this->assertEquals(['2026-10-18' => ['nombre' => 2, 'total' => 19000.25]], $tables['purchases']['jours']);
        $this->assertEquals([
            '2026-10-18' => ['nombre' => 1, 'total' => 2],
            '2026-10-19' => ['nombre' => 2, 'total' => 3],
        ], $tables['livestock_daily_entries']['jours']);
        $this->assertEquals(['2026-10-19' => ['nombre' => 1, 'total' => 1200]], $tables['veterinary_records']['jours'], 'soin archivé exclu');
        $this->assertEquals(['2026-10-19' => ['nombre' => 1, 'total' => 5000]], $tables['customer_advances']['jours']);
        $this->assertEquals(['2026-10-18' => ['nombre' => 1, 'total' => 12]], $tables['livestock_transfers']['jours']);
        $this->assertEquals(['2026-10-19' => ['nombre' => 2, 'total' => 4.5]], $tables['stock_movements']['jours']);

        // Le contrôle est noté pour la modale du web.
        $this->assertSame('POSTE-CAISSE', ControleCoherence::sole()->poste);
    }

    public function test_la_date_de_depart_est_obligatoire_et_bornee(): void
    {
        $jeton = $this->jeton($this->compte('caissier'), 'POSTE-CAISSE');
        $api = $this->withHeader('Authorization', 'Bearer '.$jeton);

        $api->getJson('/api/sync/coherence')->assertUnprocessable();
        $api->getJson('/api/sync/coherence?depuis=18/10/2026')->assertUnprocessable();
        $api->getJson('/api/sync/coherence?depuis='.now()->subDays(400)->toDateString())->assertUnprocessable();
        $this->assertSame(0, ControleCoherence::count());
    }

    public function test_la_modale_montre_le_dernier_controle_de_chaque_poste(): void
    {
        $admin = $this->compte('admin');
        $jeton = $this->jeton($this->compte('caissier'), 'POSTE-CAISSE');

        Carbon::setTestNow('2026-10-19 09:41:00');
        $this->withHeader('Authorization', 'Bearer '.$jeton)->getJson('/api/sync/coherence?depuis=2026-10-01')->assertOk();

        $this->actingAs($admin);
        Livewire::test(EtatSynchronisationPostes::class)
            ->assertSee('Dernier contrôle')
            ->assertSee('19/10/2026 09:41');
    }

    // ── S-T7 : la matrice des droits date le rôle ─────────────────────────────────────────────────────────────

    public function test_modifier_les_droits_d_un_role_le_date_et_le_tirage_incremental_le_resert(): void
    {
        $admin = $this->compte('admin');
        $jeton = $this->jeton($admin, 'POSTE-ADMIN');
        $api = $this->withHeader('Authorization', 'Bearer '.$jeton);

        Carbon::setTestNow('2026-10-19 08:00:00');
        $caissier = Role::findByName('caissier', 'web');
        $caissier->forceFill(['updated_at' => now()])->saveQuietly();
        $curseur = $api->getJson('/api/sync/pull')->assertOk()->json('server_time');
        $this->assertNotContains('manage-stocks', Role::findByName('caissier', 'web')->permissions->pluck('name')->all());

        // Écran web « Rôles et permissions » : la matrice change, `roles` n'est pas écrite par Spatie.
        Carbon::setTestNow('2026-10-19 09:00:00');
        $caissier->givePermissionTo('manage-stocks');
        $this->assertSame('2026-10-19 09:00:00', Role::findByName('caissier', 'web')->updated_at->format('Y-m-d H:i:s'),
            'un droit gagné doit dater le rôle, sinon un tirage au curseur ne le voit pas');

        Carbon::setTestNow('2026-10-19 09:05:00');
        $roles = collect($api->getJson('/api/sync/pull?since='.urlencode($curseur))->assertOk()->json('roles'))->keyBy('name');
        $this->assertContains('manage-stocks', $roles['caissier']['permissions']);

        Carbon::setTestNow('2026-10-19 10:00:00');
        $caissier->revokePermissionTo('manage-stocks');
        $this->assertSame('2026-10-19 10:00:00', Role::findByName('caissier', 'web')->updated_at->format('Y-m-d H:i:s'));

        Carbon::setTestNow('2026-10-19 11:00:00');
        $caissier->syncPermissions(['view-ventes']);
        $this->assertSame('2026-10-19 11:00:00', Role::findByName('caissier', 'web')->updated_at->format('Y-m-d H:i:s'));
    }

    public function test_la_matrice_ecrite_depuis_la_permission_date_aussi_les_roles(): void
    {
        Carbon::setTestNow('2026-10-19 08:00:00');
        $animalier = Role::findByName('animalier', 'web');
        $animalier->forceFill(['updated_at' => now()])->saveQuietly();

        Carbon::setTestNow('2026-10-19 09:30:00');
        Permission::findByName('manage-stocks', 'web')->assignRole('animalier');

        $this->assertSame('2026-10-19 09:30:00', Role::findByName('animalier', 'web')->updated_at->format('Y-m-d H:i:s'));

        Carbon::setTestNow('2026-10-19 09:45:00');
        Permission::findByName('manage-stocks', 'web')->removeRole('animalier');
        $this->assertSame('2026-10-19 09:45:00', Role::findByName('animalier', 'web')->updated_at->format('Y-m-d H:i:s'));
    }

    public function test_l_ecran_roles_et_permissions_date_le_role_modifie(): void
    {
        $this->actingAs($this->compte('admin'));

        Carbon::setTestNow('2026-10-19 08:00:00');
        Role::findByName('comptable', 'web')->forceFill(['updated_at' => now()])->saveQuietly();

        Carbon::setTestNow('2026-10-19 12:00:00');
        $droits = Role::findByName('comptable', 'web')->permissions->pluck('name')->all();
        $composant = Livewire::test(\App\Livewire\Parametres\RolesPermissions::class)->call('editRole', 'comptable');
        $matrice = $composant->get('editingPermissions');
        $matrice['manage-elevage'] = ! in_array('manage-elevage', $droits, true);
        $composant->set('editingPermissions', $matrice)->call('saveRole')->assertHasNoErrors();

        $this->assertSame('2026-10-19 12:00:00', Role::findByName('comptable', 'web')->updated_at->format('Y-m-d H:i:s'));
    }
}
