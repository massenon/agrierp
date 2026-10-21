<?php

namespace Tests\Feature;

use App\Livewire\Parametres\ModulesActifs;
use App\Models\AuditLog;
use App\Models\CompanySetting;
use App\Models\ModuleConfig;
use App\Models\User;
use Database\Seeders\LivestockSpeciesSeeder;
use Database\Seeders\ModulesConfigSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket MOD1 — LES MODULES ACTIFS SE BASCULENT AU POSTE COMME AU WEB (« En poste, je n'arrive pas à ACTIVER /
 * DÉSACTIVER les Modules Actifs », signalé par le client).
 *
 * 🔴 Avant : `modules_config` n'était qu'un référentiel descendant. Un envoi du poste était compté dans
 * `referentiels_ignored` et perdu, et l'écran du poste n'avait aucun interrupteur. Mêmes règles que
 * `Livewire\Parametres\ModulesActifs::toggleModule()` : droit `manage-modules` (administrateur), un seul réglage
 * (`modules_config.is_enabled`), `updated_by` tracé, journal `module.toggled`, jamais la comptabilité.
 */
class SyncModulesActifsPosteTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(LivestockSpeciesSeeder::class);
        $this->seed(ModulesConfigSeeder::class);
        CompanySetting::current();
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);
        Sanctum::actingAs($u);

        return $u;
    }

    private function ligne(string $code, bool $actif): array
    {
        return ['id' => $code, 'species_code' => $code, 'is_enabled' => $actif];
    }

    public function test_l_administrateur_eteint_puis_rallume_un_module_depuis_le_poste(): void
    {
        $admin = $this->compte('admin');

        $this->postJson('/api/sync/push', ['modules_config' => [$this->ligne('porciculture', false)]])->assertOk()
            ->assertJsonPath('modules_config.accepted.0', 'porciculture')
            ->assertJsonPath('referentiels_ignored', 0);
        $this->assertFalse(ModuleConfig::isEnabled('porciculture'));
        $this->assertTrue(ModuleConfig::isEnabled('cuniculture'), 'les autres modules ne bougent pas');
        $this->assertSame($admin->id, ModuleConfig::where('species_code', 'porciculture')->value('updated_by'));
        $this->assertTrue(AuditLog::where('action', 'module.toggled')->where('module', 'parametres')->exists());

        // Valeur EXPLICITE, jamais une bascule : rejouer l'envoi ne rallume pas le module.
        $this->postJson('/api/sync/push', ['modules_config' => [$this->ligne('porciculture', false)]])->assertOk();
        $this->assertFalse(ModuleConfig::isEnabled('porciculture'));

        $this->postJson('/api/sync/push', ['modules_config' => [$this->ligne('porciculture', true)]])->assertOk();
        $this->assertTrue(ModuleConfig::isEnabled('porciculture'));
    }

    public function test_la_valeur_choisie_au_poste_descend_aux_autres_postes_au_tirage(): void
    {
        $this->compte('admin');
        $this->postJson('/api/sync/push', ['modules_config' => [$this->ligne('helico', true), $this->ligne('aviculture', false)]])->assertOk();

        $tirage = collect($this->getJson('/api/sync/pull')->assertOk()->json('modules_config'))->keyBy('species_code');
        $this->assertTrue((bool) $tirage['helico']['is_enabled']);
        $this->assertFalse((bool) $tirage['aviculture']['is_enabled']);
    }

    public function test_un_compte_sans_manage_modules_est_refuse_avec_son_motif(): void
    {
        foreach (['animalier', 'caissier', 'comptable'] as $role) {
            $this->compte($role);
            $this->postJson('/api/sync/push', ['modules_config' => [$this->ligne('cuniculture', false)]])->assertOk()
                ->assertJsonCount(1, 'modules_config.rejected')
                ->assertJsonPath('modules_config.rejected.0.id', 'cuniculture');
            $this->assertTrue(ModuleConfig::isEnabled('cuniculture'), "refusé pour $role");
        }
    }

    public function test_une_espece_inconnue_ou_une_valeur_illisible_est_refusee_ligne_par_ligne(): void
    {
        $this->compte('admin');
        $r = $this->postJson('/api/sync/push', ['modules_config' => [
            $this->ligne('licornes', true),
            ['id' => 'aviculture', 'species_code' => 'aviculture', 'is_enabled' => 'peut-être'],
            $this->ligne('porciculture', false),
        ]])->assertOk();

        $this->assertSame(['porciculture'], $r->json('modules_config.accepted'));
        $this->assertCount(2, $r->json('modules_config.rejected'));
        $this->assertTrue(ModuleConfig::isEnabled('aviculture'));
        $this->assertFalse(ModuleConfig::isEnabled('porciculture'));
    }

    public function test_une_espece_sans_ligne_de_configuration_est_creee_comme_le_fait_le_web(): void
    {
        $this->compte('admin');
        ModuleConfig::where('species_code', 'helico')->delete();

        $this->postJson('/api/sync/push', ['modules_config' => [$this->ligne('helico', true)]])->assertOk()
            ->assertJsonPath('modules_config.accepted.0', 'helico');
        $this->assertTrue(ModuleConfig::isEnabled('helico'));
        $this->assertSame(1, ModuleConfig::where('species_code', 'helico')->count());
    }

    public function test_la_comptabilite_n_est_jamais_touchee(): void
    {
        $this->compte('admin');
        $avant = [\DB::table('accounting_entries')->count(), \DB::table('chart_of_accounts')->count(), \DB::table('treasury_accounts')->count()];

        foreach ([false, true] as $actif) {
            foreach (['cuniculture', 'aviculture', 'porciculture', 'helico'] as $code) {
                $this->postJson('/api/sync/push', ['modules_config' => [$this->ligne($code, $actif)]])->assertOk();
            }
        }

        $this->assertSame($avant, [\DB::table('accounting_entries')->count(), \DB::table('chart_of_accounts')->count(), \DB::table('treasury_accounts')->count()]);
    }

    /** Le web et le poste écrivent au MÊME endroit : la bascule web se voit au tirage, et inversement. */
    public function test_la_bascule_du_web_et_celle_du_poste_se_rejoignent(): void
    {
        $admin = $this->compte('admin');

        Livewire::actingAs($admin)->test(ModulesActifs::class)->call('toggleModule', 'aviculture')
            ->assertDispatched('toast', message: 'Modification appliquée avec succès.', type: 'success');
        $tirage = collect($this->getJson('/api/sync/pull')->json('modules_config'))->keyBy('species_code');
        $this->assertFalse((bool) $tirage['aviculture']['is_enabled'], 'éteint au web, éteint au tirage du poste');

        $this->postJson('/api/sync/push', ['modules_config' => [$this->ligne('aviculture', true)]])->assertOk();
        $this->assertTrue(ModuleConfig::isEnabled('aviculture'), 'rallumé au poste, rallumé au web');
    }
}
