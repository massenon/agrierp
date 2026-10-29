<?php

namespace Tests\Feature;

use App\Livewire\Parametres\AssistantDemarrage;
use App\Models\ChartOfAccount;
use App\Models\CompanySetting;
use App\Models\FiscalYear;
use App\Models\ModuleConfig;
use App\Models\TreasuryAccount;
use App\Models\User;
use App\Services\DemarrageService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.51 — ASSISTANT DE DÉMARRAGE SUR BASE VIDE.
 *
 * Les étapes sont CONSTATÉES dans la base ; l'assistant ne bloque rien ; la seule écriture qu'il fait lui-même
 * est l'ouverture du premier exercice, qu'aucun écran ne permettait.
 */
class AssistantDemarrageTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->admin = $this->compte('admin');
        $this->travelTo(now()->setDate(2026, 10, 17));
        // Module éteint par défaut : les tests de l'assistant l'allument d'abord.
        ModuleConfig::definir(ModuleConfig::ASSISTANT_DEMARRAGE, true, null);
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function etat(): array
    {
        return collect(app(DemarrageService::class)->etapes())->pluck('fait', 'cle')->all();
    }

    private function toutEnPlace(): void
    {
        CompanySetting::create(['company_name' => 'Ferme École', 'address' => 'Ikpinlè', 'phone' => '+22901000000']);
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '571', 'balance' => 0, 'is_active' => true]);
        ModuleConfig::updateOrCreate(['species_code' => 'cuniculture'], ['is_enabled' => true]);
    }

    public function test_sur_base_vide_les_etapes_manquantes_sont_constatees(): void
    {
        ChartOfAccount::query()->delete();
        ModuleConfig::query()->where('species_code', '!=', ModuleConfig::ASSISTANT_DEMARRAGE)->update(['is_enabled' => false]);

        $this->assertSame(
            ['entreprise' => false, 'plan' => false, 'exercice' => false, 'tresorerie' => false, 'modules' => false, 'utilisateurs' => false],
            $this->etat(),
        );
    }

    public function test_un_exercice_cloture_ou_qui_ne_couvre_pas_aujourd_hui_ne_compte_pas(): void
    {
        FiscalYear::create(['year' => 2025, 'start_date' => '2025-01-01', 'end_date' => '2025-12-31', 'status' => 'ouvert']);
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'cloture']);

        $this->assertFalse($this->etat()['exercice']);
    }

    public function test_l_assistant_s_ouvre_pour_l_administrateur_seulement_et_se_reporte(): void
    {
        $this->actingAs($this->admin);
        Livewire::test(AssistantDemarrage::class)->assertSet('afficher', true)->assertSee('Bienvenue dans AgriERP')
            ->call('reporter')->assertSet('afficher', false);
        Livewire::test(AssistantDemarrage::class)->assertSet('afficher', false);

        $this->actingAs($this->compte('caissier'));
        Livewire::test(AssistantDemarrage::class)->assertSet('afficher', false);
    }

    public function test_une_ferme_deja_en_place_ne_voit_pas_l_assistant(): void
    {
        $this->toutEnPlace();
        $this->actingAs($this->admin);

        Livewire::test(AssistantDemarrage::class)->assertSet('afficher', false);
    }

    public function test_ouvrir_le_premier_exercice_annee_civile_une_seule_fois(): void
    {
        $this->actingAs($this->admin);

        Livewire::test(AssistantDemarrage::class)->call('ouvrirExercice');
        Livewire::test(AssistantDemarrage::class)->call('ouvrirExercice')->assertDispatched('toast', type: 'error');

        $exercice = FiscalYear::sole();
        $this->assertSame(['2026-01-01', '2026-12-31', 'ouvert'],
            [$exercice->start_date->toDateString(), $exercice->end_date->toDateString(), $exercice->status]);
        $this->assertTrue($this->etat()['exercice']);
    }

    public function test_un_exercice_cloture_n_est_jamais_rouvert(): void
    {
        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'cloture']);
        $this->actingAs($this->admin);

        Livewire::test(AssistantDemarrage::class)->call('ouvrirExercice')->assertDispatched('toast', type: 'error');

        $this->assertSame('cloture', FiscalYear::sole()->status);
    }

    public function test_terminer_exige_les_etapes_obligatoires(): void
    {
        $this->actingAs($this->admin);
        CompanySetting::create(['company_name' => 'Ferme École']);

        Livewire::test(AssistantDemarrage::class)->call('terminer')->assertDispatched('toast', type: 'error');
        $this->assertNull(CompanySetting::first()->onboarding_completed_at);

        CompanySetting::query()->delete();
        $this->toutEnPlace();
        Livewire::test(AssistantDemarrage::class)->call('terminer');
        $this->assertNotNull(CompanySetting::first()->onboarding_completed_at);
    }

    public function test_un_non_administrateur_ne_peut_ni_ouvrir_d_exercice_ni_terminer(): void
    {
        $this->actingAs($this->compte('animalier'));

        Livewire::test(AssistantDemarrage::class)->call('ouvrirExercice')->assertForbidden();
        Livewire::test(AssistantDemarrage::class)->call('terminer')->assertForbidden();
        $this->assertSame(0, FiscalYear::count());
    }

    public function test_le_tableau_de_bord_monte_l_assistant(): void
    {
        $this->actingAs($this->admin)->get('/dashboard')->assertOk()->assertSeeLivewire(AssistantDemarrage::class);
    }

    public function test_le_module_est_eteint_par_defaut_et_se_bascule_depuis_modules_actifs(): void
    {
        ModuleConfig::query()->delete();
        $this->assertFalse(ModuleConfig::isEnabled(ModuleConfig::ASSISTANT_DEMARRAGE));

        $this->actingAs($this->admin);
        \Livewire\Livewire::test(\App\Livewire\Parametres\AssistantDemarrage::class)->assertSet('afficher', false);

        \Livewire\Livewire::test(\App\Livewire\Parametres\ModulesActifs::class)->call('toggleAssistant');
        $this->assertTrue(ModuleConfig::isEnabled(ModuleConfig::ASSISTANT_DEMARRAGE));
        \Livewire\Livewire::test(\App\Livewire\Parametres\AssistantDemarrage::class)->assertSet('afficher', true);

        \Livewire\Livewire::test(\App\Livewire\Parametres\ModulesActifs::class)->call('toggleAssistant');
        $this->assertFalse(ModuleConfig::isEnabled(ModuleConfig::ASSISTANT_DEMARRAGE));
    }

    public function test_le_poste_peut_envoyer_le_module_assistant(): void
    {
        $r = app(\App\Actions\RecordModulesConfigFromDeviceAction::class)->execute(
            [['id' => 'assistant_demarrage', 'species_code' => 'assistant_demarrage', 'is_enabled' => true]],
            $this->admin,
        );

        $this->assertSame(['assistant_demarrage'], $r['accepted']);
        $this->assertTrue(ModuleConfig::isEnabled(ModuleConfig::ASSISTANT_DEMARRAGE));
    }
}
