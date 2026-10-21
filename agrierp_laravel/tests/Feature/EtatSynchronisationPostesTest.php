<?php

namespace Tests\Feature;

use App\Livewire\Shared\EtatSynchronisationPostes;
use App\Models\JournalSynchronisation;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\User;
use App\Services\JournalSynchronisationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket H3 — BOUTON « SYNCHRONISER » ET ÉTAT DES POSTES AU WEB (PRD `synchronisation-barre-superieure`, §10).
 *
 * 🔴 Avant : un envoi laissait `api.sync_push` sans poste ni compteur, un tirage ne laissait rien ; aucun écran ne
 * disait quel poste n'avait rien envoyé depuis des jours. Jeu P1 / P2 / P3 du PRD §5, calculé à la main.
 */
class EtatSynchronisationPostesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
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

    public function test_le_bouton_est_reserve_a_l_administrateur(): void
    {
        $this->actingAs($this->compte('admin'))->get('/dashboard')->assertOk()->assertSee('modal-etat-synchronisation');

        foreach (['comptable', 'caissier', 'animalier'] as $role) {
            $this->actingAs($this->compte($role))->get('/dashboard')->assertOk()->assertDontSee('modal-etat-synchronisation');
        }

        $this->actingAs(User::where('username', 'caissier')->sole());
        Livewire::test(EtatSynchronisationPostes::class)->assertForbidden();
    }

    public function test_les_trois_pastilles_du_prd(): void
    {
        $admin = $this->compte('admin');
        $caissier = $this->compte('caissier');
        $animalier = $this->compte('animalier');
        $maintenant = now();

        $jeton = function (User $u, string $poste, $dernierContact) {
            $t = $u->createToken($poste, ['*'], now()->addDays(90))->accessToken;
            $t->forceFill(['last_used_at' => $dernierContact])->save();
        };
        $jeton($caissier, 'P1', $maintenant->copy()->subHour());
        $jeton($animalier, 'P2', $maintenant->copy()->subDays(5));
        $jeton($admin, 'P3', $maintenant->copy()->subHours(2));
        // Jeton expiré : jamais listé.
        $expire = $admin->createToken('P-EXPIRE', ['*'], now()->subDay())->accessToken;

        JournalSynchronisation::create(['poste' => 'P1', 'sens' => 'envoi', 'nb_acceptes' => 12, 'nb_refuses' => 0]);
        JournalSynchronisation::create(['poste' => 'P3', 'sens' => 'envoi', 'nb_acceptes' => 3, 'nb_refuses' => 1]);

        $etat = app(JournalSynchronisationService::class)->etatDesPostes($maintenant)->keyBy('poste');

        $this->assertSame(['P1', 'P2', 'P3'], $etat->keys()->sort()->values()->all());
        $this->assertSame('À jour', $etat['P1']['libelle_etat']);
        $this->assertSame('Inactif depuis 5 jours', $etat['P2']['libelle_etat']);
        // Le refus l'emporte sur la date (P3 vu il y a 2 h).
        $this->assertSame('Refus à corriger', $etat['P3']['libelle_etat']);
        $this->assertSame([12, 0], [$etat['P1']['acceptes'], $etat['P1']['refuses']]);
        $this->assertNull($etat['P2']['acceptes']);
        $this->assertSame('Animalier', $etat['P2']['utilisateur']);

        $this->actingAs($admin);
        Livewire::test(EtatSynchronisationPostes::class)
            ->assertSee('Postes de la ferme')
            ->assertSee('Inactif depuis 5 jours')
            ->assertSee('Refus à corriger')
            ->assertSee('12 / 0')
            ->assertDontSee('P-EXPIRE')
            ->call('actualiser')
            ->assertOk();
    }

    public function test_tirage_et_envoi_sont_journalises_par_poste_avec_leurs_compteurs(): void
    {
        $animalier = $this->compte('animalier');
        $jeton = $animalier->createToken('POSTE-ELEVAGE-01', ['*'], now()->addDays(90))->plainTextToken;
        $esp = LivestockSpecies::firstOrCreate(['code' => 'cuniculture'], ['label' => 'Cuniculture', 'is_enabled' => true]);
        $lot = LivestockLot::create([
            'code' => 'LOT-H3', 'species_id' => $esp->id, 'stage' => 'engraissement', 'initial_quantity' => 20,
            'current_quantity' => 20, 'created_date' => now()->subDays(5)->toDateString(), 'status' => 'actif', 'is_active' => true,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$jeton)->getJson('/api/sync/pull')->assertOk();

        $tirage = JournalSynchronisation::where('sens', 'tirage')->sole();
        $this->assertSame(['POSTE-ELEVAGE-01', $animalier->id], [$tirage->poste, $tirage->user_id]);
        $this->assertGreaterThanOrEqual(1, $tirage->nb_recus, 'la bande au moins');

        // Une fiche acceptée, une refusée (bande inconnue) : 1 / 1.
        $this->withHeader('Authorization', 'Bearer '.$jeton)->postJson('/api/sync/push', [
            'livestock_daily_entries' => [
                ['id' => '11111111-1111-4111-8111-111111111111', 'lot_id' => $lot->id, 'entry_date' => now()->toDateString(),
                    'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0],
                ['id' => '22222222-2222-4222-8222-222222222222', 'lot_id' => '99999999-9999-4999-8999-999999999999',
                    'entry_date' => now()->toDateString(), 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0],
            ],
        ])->assertOk()
            ->assertJsonPath('livestock_daily_entries.accepted.0', '11111111-1111-4111-8111-111111111111')
            ->assertJsonPath('livestock_daily_entries.rejected.0.id', '22222222-2222-4222-8222-222222222222');

        $envoi = JournalSynchronisation::where('sens', 'envoi')->sole();
        $this->assertSame(['POSTE-ELEVAGE-01', 1, 1], [$envoi->poste, $envoi->nb_acceptes, $envoi->nb_refuses]);
    }

    public function test_un_journal_en_echec_ne_fait_pas_echouer_la_synchronisation(): void
    {
        $caissier = $this->compte('caissier');
        $jeton = $caissier->createToken('POSTE-CAISSE', ['*'], now()->addDays(90))->plainTextToken;
        DB::statement('ALTER TABLE journal_synchronisation RENAME TO journal_synchronisation_hs');

        $this->withHeader('Authorization', 'Bearer '.$jeton)->getJson('/api/sync/pull')->assertOk();
        $this->withHeader('Authorization', 'Bearer '.$jeton)->postJson('/api/sync/push', [])->assertOk();
    }
}
