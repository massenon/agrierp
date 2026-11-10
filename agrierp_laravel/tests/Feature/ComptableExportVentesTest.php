<?php

namespace Tests\Feature;

use App\Livewire\Ventes\Devis;
use App\Livewire\Ventes\HistoriqueAvances;
use App\Livewire\Ventes\ListeClients;
use App\Livewire\Ventes\SuiviDettes;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Spatie\Permission\PermissionRegistrar;
use Tests\TestCase;

/**
 * COMPTA-1 (DV-34, décision du client du 09/11/2026) : le rôle `comptable` reçoit `export-ventes` (PDF de clients, créances, avances, devis, tickets). Il ne
 * reçoit PAS `manage-ventes` (caisse). Caissier et animalier sont inchangés. Seeder ET migration (bases existantes) le portent.
 */
class ComptableExportVentesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
    }

    private function compte(string $role): User
    {
        $u = User::create(['name' => $role, 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com', 'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true]);
        $u->assignRole($role);

        return $u;
    }

    private function droits(string $role): array
    {
        return Role::findByName($role, 'web')->permissions->pluck('name')->sort()->values()->all();
    }

    public function test_le_seeder_donne_export_ventes_au_comptable_et_rien_de_plus_aux_autres_roles(): void
    {
        $this->assertContains('export-ventes', $this->droits('comptable'));
        $this->assertNotContains('manage-ventes', $this->droits('comptable'), 'jamais la caisse');
        $this->assertSame(['export-ventes', 'manage-ventes', 'view-facturation', 'view-ventes'], $this->droits('caissier'));
        $this->assertSame(['archive-elevage', 'export-elevage', 'manage-elevage', 'view-elevage'], $this->droits('animalier'));
    }

    public function test_le_comptable_exporte_les_pdf_de_ventes_le_caissier_aussi_l_animalier_non(): void
    {
        foreach ([['exportClientsPdf', ListeClients::class], ['exportCreancesPdf', SuiviDettes::class], ['exportAvancesPdf', HistoriqueAvances::class], ['exportDevisPdf', Devis::class]] as [$methode, $composant]) {
            foreach (['comptable', 'caissier'] as $role) {
                Livewire::actingAs($this->compte($role))->test($composant)->call($methode)->assertOk();
                User::query()->delete();
            }
            try {
                Livewire::actingAs($this->compte('animalier'))->test($composant)->call($methode)->assertForbidden();
            } catch (\Illuminate\Auth\Access\AuthorizationException|\Symfony\Component\HttpKernel\Exception\HttpException) {
                $this->addToAssertionCount(1);   // refusé dès l'ouverture de l'écran
            }
            User::query()->delete();
        }
        // L'export est refusé à l'animalier même s'il atteignait la méthode : le droit, pas l'écran.
        $this->assertFalse($this->compte('animalier')->can('export-ventes'));
    }

    public function test_la_migration_est_idempotente_ne_touche_que_le_comptable_et_se_defait(): void
    {
        $role = Role::findByName('comptable', 'web');
        $role->revokePermissionTo('export-ventes');
        app()[PermissionRegistrar::class]->forgetCachedPermissions();
        $avant = ['caissier' => $this->droits('caissier'), 'animalier' => $this->droits('animalier'), 'admin' => $this->droits('admin')];
        $this->assertNotContains('export-ventes', $this->droits('comptable'));

        $migration = require database_path('migrations/2026_11_10_000001_accorder_export_ventes_comptable_compta1.php');
        $migration->up();
        $migration->up(); // idempotente
        $this->assertContains('export-ventes', $this->droits('comptable'));
        $this->assertSame(1, DB::table('role_has_permissions')->where('role_id', $role->id)->where('permission_id', Permission::where('name', 'export-ventes')->value('id'))->count());
        $this->assertSame($avant, ['caissier' => $this->droits('caissier'), 'animalier' => $this->droits('animalier'), 'admin' => $this->droits('admin')]);
        $this->assertNotContains('manage-ventes', $this->droits('comptable'));

        $migration->down();
        $this->assertNotContains('export-ventes', $this->droits('comptable'));
        $this->assertContains('export-ventes', $this->droits('caissier'), 'le retrait ne touche que le comptable');
    }

    public function test_la_migration_ignore_un_role_comptable_absent(): void
    {
        Role::findByName('comptable', 'web')->delete();
        $migration = require database_path('migrations/2026_11_10_000001_accorder_export_ventes_comptable_compta1.php');
        $migration->up();
        $this->assertNull(Role::where('name', 'comptable')->first());
    }
}
