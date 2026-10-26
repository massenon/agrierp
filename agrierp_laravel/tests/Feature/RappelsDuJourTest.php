<?php

namespace Tests\Feature;

use App\Livewire\Shared\RappelsDuJour;
use App\Models\CompanySetting;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Models\Permission;
use App\Models\ProphylaxisScheduleStandard;
use App\Models\Role;
use App\Models\User;
use App\Models\VeterinaryCalendarEvent;
use App\Models\VeterinaryRecord;
use App\Models\VeterinaryWithdrawalPeriod;
use App\Services\RappelsDuJourService;
use Illuminate\Auth\Events\Login;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Tickets POP1 — LA FENÊTRE « RAPPELS DU JOUR » À L'OUVERTURE (PRD `docs/prd/popup-rappels.md`, règle R-RAPPELS-01).
 *
 * Jour fixé au mercredi 14/10/2026, N = 3 (défaut). Jeu d'exemple calculé à la main (PRD § 5) :
 *   LAP-A (cuniculture, mise en lot 10/10 : le 14/10 est J5)
 *     soin « Vaccin Newcastle » le 12/10 → En retard, 2 jours ; soin « Déparasitage » le 14/10 → Aujourd'hui ;
 *     soin « Vitamines » le 17/10 → À venir, dans 3 jours ; soin « Trop tard » le 18/10 → absent (4 jours > N).
 * Ordre attendu : Vaccin Newcastle, Déparasitage, Vitamines.
 */
class RappelsDuJourTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $bande;

    private LivestockSpecies $cuniculture;

    private LivestockSpecies $aviculture;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-14 10:00:00');

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('animalier', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);
        Role::findOrCreate('caissier', 'web');

        $this->cuniculture = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
        $this->aviculture = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true]);
        ModuleConfig::create(['species_code' => 'cuniculture', 'is_enabled' => true]);
        ModuleConfig::create(['species_code' => 'aviculture', 'is_enabled' => true]);

        $this->bande = $this->bande('LAP-A', $this->cuniculture, '2026-10-10');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function bande(string $code, LivestockSpecies $espece, string $miseEnLot, string $statut = 'actif'): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => 100, 'current_quantity' => 100, 'created_date' => $miseEnLot,
            'status' => $statut, 'is_active' => true,
        ]);
    }

    private function soin(string $tache, string $date, ?LivestockLot $bande = null, string $statut = 'planned'): VeterinaryCalendarEvent
    {
        return VeterinaryCalendarEvent::create([
            'lot_id' => ($bande ?? $this->bande)->id, 'task_type' => $tache, 'scheduled_date' => $date, 'status' => $statut,
        ]);
    }

    private function utilisateur(string $role): User
    {
        $u = User::create(['name' => ucfirst($role), 'email' => $role.'.pop@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026')]);
        $u->assignRole($role);

        return $u;
    }

    private function jeuDExemple(): void
    {
        $this->soin('Trop tard', '2026-10-18');
        $this->soin('Vitamines', '2026-10-17');
        $this->soin('Déparasitage', '2026-10-14');
        $this->soin('Vaccin Newcastle', '2026-10-12');
    }

    private function libelles(?array $lignes = null): array
    {
        return array_map(fn ($l) => $l['libelle'], $lignes ?? app(RappelsDuJourService::class)->calculer());
    }

    // ── Règle R-RAPPELS-01 ─────────────────────────────────────────────────────

    public function test_jeu_d_exemple_du_prd_urgences_echeances_et_ordre(): void
    {
        $this->jeuDExemple();

        $lignes = app(RappelsDuJourService::class)->calculer();

        $this->assertSame(['Vaccin Newcastle', 'Déparasitage', 'Vitamines'], $this->libelles($lignes), 'le soin à 4 jours (> N) est absent ; le tri est retard, aujourd\'hui, à venir');
        $this->assertSame(['retard', 'aujourdhui', 'avenir'], array_column($lignes, 'urgence'));
        $this->assertSame([-2, 0, 3], array_column($lignes, 'jours'));
        $this->assertSame(['En retard de 2 jours', "Aujourd'hui", 'Dans 3 jours'], array_column($lignes, 'echeance'));
        $this->assertSame(['LAP-A', 'LAP-A', 'LAP-A'], array_column($lignes, 'bande'));
        $this->assertSame('Lapins', $lignes[0]['espece']);
        $this->assertSame('2026-10-12', $lignes[0]['date']);
        $this->assertSame('12/10/2026', $lignes[0]['date_texte']);
        $this->assertSame('soin', $lignes[0]['type']);
    }

    public function test_le_delai_est_celui_du_reglage_rappel_soins_jours(): void
    {
        $this->jeuDExemple();

        CompanySetting::current()->update(['rappel_soins_jours' => 0]);
        $this->assertSame(['Vaccin Newcastle', 'Déparasitage'], $this->libelles(), 'N = 0 : le jour même seulement (et le retard)');

        CompanySetting::current()->update(['rappel_soins_jours' => 4]);
        $this->assertSame(['Vaccin Newcastle', 'Déparasitage', 'Vitamines', 'Trop tard'], $this->libelles());
    }

    public function test_un_soin_realise_ou_en_cours_et_une_bande_cloturee_ne_rappellent_rien(): void
    {
        $this->soin('Réalisé', '2026-10-14', null, 'done');
        $this->soin('En cours', '2026-10-14', null, 'inprogress');
        $close = $this->bande('LAP-X', $this->cuniculture, '2026-09-01', 'cloture');
        $this->soin('Bande close', '2026-10-14', $close);

        $this->assertSame([], app(RappelsDuJourService::class)->calculer());
    }

    public function test_une_espece_desactivee_ne_genere_aucun_rappel(): void
    {
        $volailles = $this->bande('AVI-A', $this->aviculture, '2026-10-01');
        $this->soin('Soin lapins', '2026-10-14');
        $this->soin('Soin volailles', '2026-10-14', $volailles);
        ModuleConfig::where('species_code', 'aviculture')->update(['is_enabled' => false]);

        $this->assertSame(['Soin lapins'], $this->libelles());

        ModuleConfig::where('species_code', 'cuniculture')->update(['is_enabled' => false]);
        $this->assertSame([], $this->libelles());
    }

    public function test_traitement_du_bareme_du_jour_et_a_venir_sauf_deja_administre(): void
    {
        // LAP-A mise en lot le 10/10 : le 14/10 = J5, le 15/10 = J6, le 17/10 = J8 (N = 3), le 18/10 = J9 (hors horizon).
        ProphylaxisScheduleStandard::create(['species_code' => 'cuniculture', 'period_label' => 'J5', 'cycle_day_start' => 5, 'cycle_day_end' => 5,
            'treatment' => 'Vermifuge', 'product_recommended' => 'Ivomec', 'dosage' => '1 ml', 'withdrawal_days' => 0, 'is_active' => true]);
        ProphylaxisScheduleStandard::create(['species_code' => 'cuniculture', 'period_label' => 'J6', 'cycle_day_start' => 6, 'cycle_day_end' => 6,
            'treatment' => 'Vaccin VHD', 'product_recommended' => 'Filavac', 'dosage' => '1 dose', 'withdrawal_days' => 0, 'is_active' => true]);
        ProphylaxisScheduleStandard::create(['species_code' => 'cuniculture', 'period_label' => 'J9', 'cycle_day_start' => 9, 'cycle_day_end' => 9,
            'treatment' => 'Hors horizon', 'product_recommended' => 'X', 'dosage' => '-', 'withdrawal_days' => 0, 'is_active' => true]);
        ProphylaxisScheduleStandard::create(['species_code' => 'cuniculture', 'period_label' => 'J7', 'cycle_day_start' => 7, 'cycle_day_end' => 7,
            'treatment' => 'Archivé', 'product_recommended' => 'Y', 'dosage' => '-', 'withdrawal_days' => 0, 'is_active' => false]);

        $lignes = app(RappelsDuJourService::class)->calculer();
        $this->assertSame(['Vermifuge', 'Vaccin VHD'], $this->libelles($lignes));
        $this->assertSame(['aujourdhui', 'avenir'], array_column($lignes, 'urgence'));
        $this->assertSame(['prophylaxie', 'prophylaxie'], array_column($lignes, 'type'));
        $this->assertSame(['Ivomec', 'Filavac'], array_column($lignes, 'produit'));
        $this->assertSame(['Dans 1 jour', "Aujourd'hui"][1], $lignes[0]['echeance']);
        $this->assertSame('Dans 1 jour', $lignes[1]['echeance']);

        // Déjà administré aujourd'hui : plus un rappel (l'afficher ferait redoser la bande).
        VeterinaryRecord::create(['lot_id' => $this->bande->id, 'action_type' => 'Vermifuge', 'record_date' => '2026-10-14', 'is_active' => true]);
        $this->assertSame(['Vaccin VHD'], $this->libelles());
    }

    public function test_fin_de_delai_d_attente_dans_l_horizon(): void
    {
        VeterinaryWithdrawalPeriod::create(['lot_id' => $this->bande->id, 'product_used' => 'Ivermectine', 'start_date' => '2026-10-01',
            'withdrawal_days' => 13, 'end_date' => '2026-10-14']);
        VeterinaryWithdrawalPeriod::create(['lot_id' => $this->bande->id, 'product_used' => 'Oxytétracycline', 'start_date' => '2026-10-10',
            'withdrawal_days' => 7, 'end_date' => '2026-10-17']);
        VeterinaryWithdrawalPeriod::create(['lot_id' => $this->bande->id, 'product_used' => 'Trop loin', 'start_date' => '2026-10-10',
            'withdrawal_days' => 14, 'end_date' => '2026-10-24']);
        VeterinaryWithdrawalPeriod::create(['lot_id' => $this->bande->id, 'product_used' => 'Terminée', 'start_date' => '2026-09-01',
            'withdrawal_days' => 7, 'end_date' => '2026-09-08']);

        $lignes = app(RappelsDuJourService::class)->calculer();
        $this->assertSame(['remanence', 'remanence'], array_column($lignes, 'type'));
        $this->assertSame(['Ivermectine', 'Oxytétracycline'], array_column($lignes, 'produit'));
        $this->assertSame(['aujourdhui', 'avenir'], array_column($lignes, 'urgence'));
        $this->assertSame(["Fin du délai d'attente", "Fin du délai d'attente"], array_column($lignes, 'libelle'));
    }

    public function test_tri_par_urgence_puis_date_puis_bande(): void
    {
        $autre = $this->bande('AVI-A', $this->aviculture, '2026-10-01');
        $this->soin('À venir B', '2026-10-16');
        $this->soin('Retard récent', '2026-10-13');
        $this->soin('Aujourd\'hui B', '2026-10-14', $autre);
        $this->soin('Retard ancien', '2026-10-10', $autre);
        $this->soin('Aujourd\'hui A', '2026-10-14');
        $this->soin('À venir A', '2026-10-15', $autre);

        $this->assertSame(
            ['Retard ancien', 'Retard récent', 'Aujourd\'hui B', 'Aujourd\'hui A', 'À venir A', 'À venir B'],
            $this->libelles(),
            'urgence, puis date croissante, puis code de bande (même jour : AVI-A avant LAP-A)',
        );
    }

    // ── Droits ─────────────────────────────────────────────────────────────────

    public function test_le_service_ne_rend_rien_a_qui_ne_voit_pas_soins_et_vaccins(): void
    {
        $this->jeuDExemple();

        $this->assertCount(3, app(RappelsDuJourService::class)->pourUtilisateur($this->utilisateur('animalier')));
        $this->assertSame([], app(RappelsDuJourService::class)->pourUtilisateur($this->utilisateur('caissier')));
        $this->assertSame([], app(RappelsDuJourService::class)->pourUtilisateur(null));
    }

    public function test_le_caissier_ne_recoit_pas_la_fenetre_et_ne_la_monte_meme_pas(): void
    {
        $this->jeuDExemple();
        $caissier = $this->utilisateur('caissier');

        Livewire::actingAs($caissier)->test(RappelsDuJour::class)
            ->call('ouvrir', false, null)
            ->assertSet('visible', false)
            ->assertSet('rappels', []);

        $this->actingAs($caissier)->get('/dashboard')->assertOk()->assertDontSee('Rappels du jour');
    }

    // ── Ouverture : une fois par session, fenêtre vide, masquage du jour, connexion ──

    public function test_l_animalier_voit_la_fenetre_a_l_ouverture(): void
    {
        $this->jeuDExemple();

        Livewire::actingAs($this->utilisateur('animalier'))->test(RappelsDuJour::class)
            ->call('ouvrir', false, null)
            ->assertSet('visible', true)
            ->assertCount('rappels', 3)
            ->assertSee('Rappels du jour')
            ->assertSee('En retard')
            ->assertSee('Vaccin Newcastle')
            ->assertSee('LAP-A (Lapins)')
            ->assertSee('Ouvrir Soins et vaccins')
            ->assertSee('Plus tard')
            ->assertSee("Ne plus afficher aujourd'hui", false);
    }

    public function test_jamais_de_fenetre_vide(): void
    {
        Livewire::actingAs($this->utilisateur('animalier'))->test(RappelsDuJour::class)
            ->call('ouvrir', false, null)
            ->assertSet('visible', false)
            ->assertSet('rappels', [])
            ->assertDontSee('Rappels du jour');
    }

    public function test_une_seule_fois_par_session_du_navigateur(): void
    {
        $this->jeuDExemple();

        Livewire::actingAs($this->utilisateur('animalier'))->test(RappelsDuJour::class)
            ->call('ouvrir', true, null)
            ->assertSet('visible', false);
    }

    public function test_ne_plus_afficher_aujourd_hui_vaut_pour_la_date_du_jour_seulement(): void
    {
        $this->jeuDExemple();
        $animalier = $this->utilisateur('animalier');

        Livewire::actingAs($animalier)->test(RappelsDuJour::class)
            ->call('ouvrir', false, '2026-10-14')
            ->assertSet('visible', false);

        // Masqué hier : la fenêtre revient aujourd'hui.
        Livewire::actingAs($animalier)->test(RappelsDuJour::class)
            ->call('ouvrir', false, '2026-10-13')
            ->assertSet('visible', true);
    }

    public function test_la_connexion_rouvre_la_fenetre_meme_dans_une_session_deja_vue_mais_pas_le_masquage_du_jour(): void
    {
        $this->jeuDExemple();
        $animalier = $this->utilisateur('animalier');

        event(new Login('web', $animalier, false));
        $this->assertTrue(session('rappels_forcer'));

        Livewire::actingAs($animalier)->test(RappelsDuJour::class)
            ->call('ouvrir', true, null)
            ->assertSet('visible', true);
        $this->assertNull(session('rappels_forcer'), 'le drapeau de connexion est consommé : une seule ouverture');

        event(new Login('web', $animalier, false));
        Livewire::actingAs($animalier)->test(RappelsDuJour::class)
            ->call('ouvrir', true, '2026-10-14')
            ->assertSet('visible', false);
    }

    public function test_une_erreur_de_calcul_est_silencieuse(): void
    {
        $this->jeuDExemple();
        $this->mock(RappelsDuJourService::class, function ($m) {
            $m->shouldReceive('pourUtilisateur')->andThrow(new \RuntimeException('base illisible'));
        });

        Livewire::actingAs($this->utilisateur('animalier'))->test(RappelsDuJour::class)
            ->call('ouvrir', false, null)
            ->assertSet('visible', false)
            ->assertHasNoErrors();
    }

    // ── Mise en page ───────────────────────────────────────────────────────────

    public function test_la_mise_en_page_monte_le_composant_pour_qui_voit_l_elevage_et_garde_le_stockage_local(): void
    {
        $this->jeuDExemple();

        $this->actingAs($this->utilisateur('animalier'))->get('/dashboard')
            ->assertOk()
            ->assertSee('sessionStorage', false)
            ->assertSee('localStorage', false)
            ->assertSee('agrierp_rappels_masques', false)
            ->assertSee('agrierp_rappels_session', false);
    }
}
