<?php

namespace Tests\Feature;

use App\Livewire\Elevage\SuiviReproduction;
use App\Models\AuditLog;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 3.F7 (décision client A, 11/11/2026) — saveMiseBas écrit `ne` dans la fiche journalière.
 *
 * Avant ce correctif, enregistrer une mise bas mettait à jour `livestock_reproduction_events`
 * mais ne touchait pas `livestock_daily_entries` : l'effectif de la bande restait inchangé,
 * forçant une double saisie. Désormais, les nés vivants alimentent automatiquement la fiche
 * du jour de la mise bas (colonne `ne`).
 */
class SuiviReproductionMiseBasFicheTest extends TestCase
{
    use RefreshDatabase;

    private User $animalier;

    private LivestockLot $bande;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-11-11 08:00:00');

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('animalier', 'web');
        $role->givePermissionTo(['view-elevage', 'manage-elevage']);

        $this->animalier = User::create([
            'name' => 'Animalier',
            'email' => 'animalier.3f7@fermeolouwachegoun.com',
            'password' => bcrypt('LogiAgriERP@2026'),
        ]);
        $this->animalier->assignRole($role);

        $espece = LivestockSpecies::create([
            'code' => 'cuniculture',
            'label' => 'Lapins',
            'is_enabled' => true,
        ]);

        $this->bande = LivestockLot::create([
            'code' => 'L-001',
            'species_id' => $espece->id,
            'stage' => 'reproduction',
            'initial_quantity' => 10,
            'current_quantity' => 10,
            'created_date' => '2026-08-01',
            'status' => 'actif',
            'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function creerCycle(): LivestockReproductionEvent
    {
        return LivestockReproductionEvent::create([
            'lot_id' => $this->bande->id,
            'mother_ref' => 'R1',
            'sire_ref' => 'M1',
            'saillie_date' => '2026-10-12',
            'status' => 'en_cours',
        ]);
    }

    // ─── Comportement nominal ────────────────────────────────────────────────

    /** Une mise bas avec 6 nés vivants crée une fiche journalière avec ne=6. */
    public function test_mise_bas_cree_fiche_ne_si_absente(): void
    {
        $event = $this->creerCycle();

        $this->assertDatabaseMissing('livestock_daily_entries', [
            'lot_id' => $this->bande->id,
        ]);

        $this->actingAs($this->animalier);

        Livewire::test(SuiviReproduction::class)
            ->set('miseBasEventId', $event->id)
            ->set('nesVivants', 6)
            ->set('nesMorts', 1)
            ->call('saveMiseBas');

        $this->assertDatabaseHas('livestock_daily_entries', [
            'lot_id' => $this->bande->id,
            'entry_date' => '2026-11-11',
            'ne' => 6,
        ]);
    }

    /** Une mise bas avec 4 nés vivants sur une fiche existante (ne=2) donne ne=6. */
    public function test_mise_bas_ajoute_ne_sur_fiche_existante(): void
    {
        $event = $this->creerCycle();

        LivestockDailyEntry::create([
            'lot_id' => $this->bande->id,
            'entry_date' => '2026-11-11',
            'ne' => 2,
            'mort' => 0,
            'effectif_final' => 12,
        ]);

        $this->actingAs($this->animalier);

        Livewire::test(SuiviReproduction::class)
            ->set('miseBasEventId', $event->id)
            ->set('nesVivants', 4)
            ->set('nesMorts', 0)
            ->call('saveMiseBas');

        $this->assertDatabaseHas('livestock_daily_entries', [
            'lot_id' => $this->bande->id,
            'entry_date' => '2026-11-11',
            'ne' => 6,
        ]);

        // Une seule fiche, pas de doublon
        $this->assertSame(1, LivestockDailyEntry::where('lot_id', $this->bande->id)->count());
    }

    /** L'événement de reproduction est mis à jour correctement. */
    public function test_mise_bas_met_a_jour_evenement_reproduction(): void
    {
        $event = $this->creerCycle();

        $this->actingAs($this->animalier);

        Livewire::test(SuiviReproduction::class)
            ->set('miseBasEventId', $event->id)
            ->set('nesVivants', 5)
            ->set('nesMorts', 2)
            ->call('saveMiseBas');

        $event->refresh();

        $this->assertEquals('2026-11-11', $event->mise_bas_date_actual->format('Y-m-d'));
        $this->assertSame(5, (int) $event->nes_vivants);
        $this->assertSame(2, (int) $event->nes_morts);
    }

    // ─── Zéro nés vivants ───────────────────────────────────────────────────

    /** Zéro nés vivants : l'événement est mis à jour mais aucune fiche n'est créée. */
    public function test_zero_nes_vivants_ne_cree_pas_de_fiche(): void
    {
        $event = $this->creerCycle();

        $this->actingAs($this->animalier);

        Livewire::test(SuiviReproduction::class)
            ->set('miseBasEventId', $event->id)
            ->set('nesVivants', 0)
            ->set('nesMorts', 3)
            ->call('saveMiseBas');

        $this->assertDatabaseMissing('livestock_daily_entries', [
            'lot_id' => $this->bande->id,
        ]);

        $event->refresh();
        $this->assertSame(0, (int) $event->nes_vivants);
    }

    /** Zéro nés vivants sur une fiche déjà existante : la fiche n'est pas touchée. */
    public function test_zero_nes_vivants_ne_modifie_pas_fiche_existante(): void
    {
        $event = $this->creerCycle();

        LivestockDailyEntry::create([
            'lot_id' => $this->bande->id,
            'entry_date' => '2026-11-11',
            'ne' => 3,
            'mort' => 1,
            'effectif_final' => 12,
        ]);

        $this->actingAs($this->animalier);

        Livewire::test(SuiviReproduction::class)
            ->set('miseBasEventId', $event->id)
            ->set('nesVivants', 0)
            ->set('nesMorts', 0)
            ->call('saveMiseBas');

        $this->assertDatabaseHas('livestock_daily_entries', [
            'lot_id' => $this->bande->id,
            'entry_date' => '2026-11-11',
            'ne' => 3,
        ]);
    }

    // ─── Audit et retours UI ────────────────────────────────────────────────

    /** Une entrée d'audit est créée après une mise bas réussie. */
    public function test_audit_enregistre_apres_mise_bas(): void
    {
        $event = $this->creerCycle();

        $this->actingAs($this->animalier);

        Livewire::test(SuiviReproduction::class)
            ->set('miseBasEventId', $event->id)
            ->set('nesVivants', 3)
            ->set('nesMorts', 0)
            ->call('saveMiseBas');

        $this->assertDatabaseHas('audit_logs', [
            'action' => 'reproduction_event.misebas_recorded',
            'module' => 'elevage',
        ]);
    }

    /** La modale est fermée et un toast de succès est dispatché. */
    public function test_toast_succes_et_fermeture_modale(): void
    {
        $event = $this->creerCycle();

        $this->actingAs($this->animalier);

        Livewire::test(SuiviReproduction::class)
            ->set('miseBasEventId', $event->id)
            ->set('nesVivants', 4)
            ->set('nesMorts', 1)
            ->call('saveMiseBas')
            ->assertDispatched('close-modal', name: 'modal-misebas')
            ->assertDispatched('toast', type: 'success');
    }

    // ─── Autorisation ───────────────────────────────────────────────────────

    /** Un utilisateur sans permission `manage-elevage` ne peut pas enregistrer une mise bas. */
    public function test_sans_permission_manage_elevage_acces_refuse(): void
    {
        $event = $this->creerCycle();

        $roleVue = Role::findOrCreate('visiteur', 'web');
        $roleVue->givePermissionTo(['view-elevage']);

        $visiteur = User::create([
            'name' => 'Visiteur',
            'email' => 'visiteur.3f7@fermeolouwachegoun.com',
            'password' => bcrypt('LogiAgriERP@2026'),
        ]);
        $visiteur->assignRole($roleVue);

        $this->actingAs($visiteur);

        Livewire::test(SuiviReproduction::class)
            ->set('miseBasEventId', $event->id)
            ->set('nesVivants', 3)
            ->set('nesMorts', 0)
            ->call('saveMiseBas')
            ->assertForbidden();

        $this->assertDatabaseMissing('livestock_daily_entries', [
            'lot_id' => $this->bande->id,
        ]);
    }

    // ─── Validation ─────────────────────────────────────────────────────────

    /** `nesVivants` négatif est refusé avec une erreur de validation. */
    public function test_nes_vivants_negatif_est_invalide(): void
    {
        $event = $this->creerCycle();

        $this->actingAs($this->animalier);

        Livewire::test(SuiviReproduction::class)
            ->set('miseBasEventId', $event->id)
            ->set('nesVivants', -1)
            ->set('nesMorts', 0)
            ->call('saveMiseBas')
            ->assertHasErrors(['nesVivants']);
    }
}
