<?php

namespace Tests\Feature;

use App\Models\InfirmaryRecord;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\User;
use App\Models\VeterinaryCalendarEvent;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Ticket H8b (décision D-H8 du 19/10/2026) — L'INFIRMERIE ET LE CALENDRIER VÉTÉRINAIRE SE SAISISSENT AU POSTE.
 *
 * 🔴 Avant : ni tirées ni poussées. L'onglet « Suivi Sanitaire » du poste était vide, et une intervention planifiée
 * au web n'apparaissait jamais au calendrier du poste. Mêmes règles que `SoinsVaccinsHub` (création en `en_cours` /
 * `planned`, réintégration, décès, confirmation `done`).
 */
class SyncInfirmerieCalendrierTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $bande;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $esp = LivestockSpecies::firstOrCreate(['code' => 'cuniculture'], ['label' => 'Cuniculture', 'is_enabled' => true]);
        $this->bande = LivestockLot::create([
            'code' => 'LOT-H8B', 'species_id' => $esp->id, 'stage' => 'engraissement', 'initial_quantity' => 30,
            'current_quantity' => 30, 'created_date' => now()->subDays(20)->toDateString(), 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => ucfirst($role), 'username' => $role, 'email' => $role.'@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);
        Sanctum::actingAs($u);

        return $u;
    }

    public function test_le_tirage_sert_l_infirmerie_et_le_calendrier(): void
    {
        $this->compte('animalier');
        InfirmaryRecord::create(['lot_id' => $this->bande->id, 'motif' => 'Diarrhée', 'isolation_level' => 'Infirmerie', 'entry_date' => now()->toDateString(), 'status' => 'en_cours']);
        VeterinaryCalendarEvent::create(['lot_id' => $this->bande->id, 'task_type' => 'Rappel Myxomatose', 'scheduled_date' => now()->addDays(2)->toDateString(), 'status' => 'planned']);

        $this->getJson('/api/sync/pull')->assertOk()
            ->assertJsonPath('infirmary_records.0.motif', 'Diarrhée')
            ->assertJsonPath('veterinary_calendar_events.0.task_type', 'Rappel Myxomatose');
    }

    public function test_une_entree_d_infirmerie_du_poste_est_creee_puis_reintegree(): void
    {
        $this->compte('animalier');
        $id = '33333333-3333-4333-8333-333333333333';
        $entree = ['id' => $id, 'lot_id' => $this->bande->id, 'sujet_ref' => 'R4', 'motif' => 'Boiterie',
            'isolation_level' => 'Quarantaine stricte', 'entry_date' => now()->toDateString()];

        $this->postJson('/api/sync/push', ['infirmary_records' => [$entree]])->assertOk()
            ->assertJsonPath('infirmary_records.accepted.0', $id);
        $this->assertSame('en_cours', InfirmaryRecord::findOrFail($id)->status);

        // Renvoi identique : acquitté, rien ne double.
        $this->postJson('/api/sync/push', ['infirmary_records' => [$entree + ['status' => 'en_cours']]])->assertOk();
        $this->assertSame(1, InfirmaryRecord::count());

        $this->postJson('/api/sync/push', ['infirmary_records' => [['id' => $id, 'status' => 'reintegre']]])->assertOk();
        $this->assertSame('reintegre', InfirmaryRecord::findOrFail($id)->status);
    }

    /**
     * 🔴→✅ Ticket U6 (décision client D-U6 du 19/10/2026) — LE WEB ACCEPTE UNE DATE D'ENTRÉE FUTURE
     * (`saveInfirmaryEntry()` : `required|date`) ; l'envoi la refusait (`before_or_equal:today`). Mêmes règles partout.
     */
    public function test_une_entree_d_infirmerie_datee_dans_le_futur_est_acceptee_comme_au_web(): void
    {
        $u = $this->compte('animalier');
        $id = '99999999-9999-4999-8999-999999999990';
        $demain = now()->addDays(3)->toDateString();

        $this->postJson('/api/sync/push', ['infirmary_records' => [[
            'id' => $id, 'lot_id' => $this->bande->id, 'motif' => 'Isolement préventif',
            'isolation_level' => 'Simple surveillance', 'entry_date' => $demain,
        ]]])->assertOk()->assertJsonPath('infirmary_records.accepted.0', $id)
            ->assertJsonCount(0, 'infirmary_records.rejected');
        $this->assertSame($demain, InfirmaryRecord::findOrFail($id)->entry_date->toDateString());

        // Le web, maître : la même date future passe la validation de la modale.
        $this->actingAs($u);
        \Livewire\Livewire::test(\App\Livewire\Elevage\SoinsVaccinsHub::class)
            ->set('infLotId', $this->bande->id)->set('infMotif', 'Isolement préventif')
            ->set('infIsolation', 'Simple surveillance')->set('infDate', $demain)
            ->call('saveInfirmaryEntry')->assertHasNoErrors();
        $this->assertSame(2, InfirmaryRecord::whereDate('entry_date', $demain)->count());
    }

    /** Ticket U6 — les autres règles du web restent : date obligatoire et lisible. */
    public function test_une_entree_sans_date_lisible_reste_refusee(): void
    {
        $this->compte('animalier');
        $this->postJson('/api/sync/push', ['infirmary_records' => [[
            'id' => '99999999-9999-4999-8999-999999999991', 'lot_id' => $this->bande->id, 'motif' => 'Toux',
            'isolation_level' => 'Infirmerie', 'entry_date' => 'demain',
        ]]])->assertOk()->assertJsonCount(1, 'infirmary_records.rejected');
        $this->assertSame(0, InfirmaryRecord::count());
    }

    public function test_un_niveau_d_isolement_inconnu_est_refuse(): void
    {
        $this->compte('animalier');
        $this->postJson('/api/sync/push', ['infirmary_records' => [[
            'id' => '44444444-4444-4444-8444-444444444444', 'lot_id' => $this->bande->id, 'motif' => 'Toux',
            'isolation_level' => 'Cage dorée', 'entry_date' => now()->toDateString(),
        ]]])->assertOk()->assertJsonCount(1, 'infirmary_records.rejected');
        $this->assertSame(0, InfirmaryRecord::count());
    }

    public function test_une_intervention_planifiee_au_poste_puis_confirmee(): void
    {
        $this->compte('animalier');
        $id = '55555555-5555-4555-8555-555555555555';

        $this->postJson('/api/sync/push', ['veterinary_calendar_events' => [[
            'id' => $id, 'lot_id' => $this->bande->id, 'task_type' => 'Vermifuge', 'scheduled_date' => now()->addDay()->toDateString(),
        ]]])->assertOk()->assertJsonPath('veterinary_calendar_events.accepted.0', $id);
        $this->assertSame('planned', VeterinaryCalendarEvent::findOrFail($id)->status);

        $this->postJson('/api/sync/push', ['veterinary_calendar_events' => [['id' => $id, 'status' => 'done']]])->assertOk();
        $this->assertSame('done', VeterinaryCalendarEvent::findOrFail($id)->status);

        // « En retard » est un affichage, jamais une valeur stockée.
        $this->postJson('/api/sync/push', ['veterinary_calendar_events' => [['id' => $id, 'status' => 'late']]])->assertOk()
            ->assertJsonCount(1, 'veterinary_calendar_events.rejected');
    }

    public function test_un_caissier_ne_peut_rien_ecrire_au_sanitaire(): void
    {
        $this->compte('caissier');
        $this->postJson('/api/sync/push', ['veterinary_calendar_events' => [[
            'id' => '66666666-6666-4666-8666-666666666666', 'lot_id' => $this->bande->id, 'task_type' => 'Vermifuge',
            'scheduled_date' => now()->toDateString(),
        ]]])->assertOk()->assertJsonCount(1, 'veterinary_calendar_events.rejected');
        $this->assertSame(0, VeterinaryCalendarEvent::count());
    }
}
