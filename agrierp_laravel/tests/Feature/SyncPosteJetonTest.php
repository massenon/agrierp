<?php

namespace Tests\Feature;

use App\Models\JournalSynchronisation;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Ticket S-T2 (méthode TATACORA, `docs/COMPARAISON_METHODE_TATACORA.md` §3) — UN POSTE NE SIGNE PAS AU NOM D'UN AUTRE.
 *
 * 🔴 Avant : le jeton Sanctum est nommé d'après le poste à la connexion, mais le `device_id` envoyé n'était comparé à
 * rien. Un poste pouvait se présenter comme un autre ; les avances, règlements, retours, remboursements, imputations
 * et transferts portaient alors le poste annoncé. Désormais : refus 403, motif français, rien d'écrit.
 */
class SyncPosteJetonTest extends TestCase
{
    use RefreshDatabase;

    private const FICHE = '11111111-1111-4111-8111-111111111111';

    private User $animalier;

    private LivestockLot $lot;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->animalier = User::create([
            'name' => 'Animalier', 'username' => 'animalier', 'email' => 'animalier@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->animalier->assignRole('animalier');

        $esp = LivestockSpecies::firstOrCreate(['code' => 'cuniculture'], ['label' => 'Cuniculture', 'is_enabled' => true]);
        $this->lot = LivestockLot::create([
            'code' => 'LOT-ST2', 'species_id' => $esp->id, 'stage' => 'engraissement', 'initial_quantity' => 20,
            'current_quantity' => 20, 'created_date' => now()->subDays(5)->toDateString(), 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function jeton(string $poste): string
    {
        return $this->postJson('/api/auth/login', [
            'identifiant' => 'animalier', 'password' => 'AgriERP@2026', 'device_name' => $poste,
        ])->assertOk()->json('token');
    }

    /** @return array<string, mixed> */
    private function envoi(?string $deviceId): array
    {
        return array_filter([
            'device_id' => $deviceId,
            'livestock_daily_entries' => [[
                'id' => self::FICHE, 'lot_id' => $this->lot->id, 'entry_date' => now()->toDateString(),
                'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            ]],
        ], fn ($v) => $v !== null);
    }

    public function test_un_envoi_au_nom_d_un_autre_poste_est_refuse_en_403_sans_rien_ecrire(): void
    {
        $jeton = $this->jeton('POSTE-ELEVAGE-01');

        $reponse = $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->postJson('/api/sync/push', $this->envoi('POSTE-CAISSE'))
            ->assertStatus(403);

        $message = $reponse->json('message');
        $this->assertStringContainsString('« POSTE-ELEVAGE-01 »', $message);
        $this->assertStringContainsString('« POSTE-CAISSE »', $message);
        $this->assertStringContainsString('Un poste ne peut pas synchroniser au nom d\'un autre', $message);
        $this->assertNull(LivestockDailyEntry::find(self::FICHE), 'rien n\'est écrit');
        $this->assertSame(0, JournalSynchronisation::where('sens', 'envoi')->count(), 'un refus n\'est pas un envoi');
    }

    public function test_le_poste_du_jeton_envoie_normalement_et_le_journal_porte_le_nom_du_jeton(): void
    {
        $jeton = $this->jeton('POSTE-ELEVAGE-01');

        $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->postJson('/api/sync/push', $this->envoi('POSTE-ELEVAGE-01'))
            ->assertOk()
            ->assertJsonPath('livestock_daily_entries.accepted', [self::FICHE]);

        $this->assertSame('POSTE-ELEVAGE-01', JournalSynchronisation::where('sens', 'envoi')->sole()->poste);
    }

    public function test_sans_device_id_rien_n_est_compare_et_le_journal_porte_le_nom_du_jeton(): void
    {
        $jeton = $this->jeton('POSTE-ELEVAGE-01');

        $this->withHeader('Authorization', 'Bearer '.$jeton)
            ->postJson('/api/sync/push', $this->envoi(null))
            ->assertOk();

        $this->assertSame('POSTE-ELEVAGE-01', JournalSynchronisation::where('sens', 'envoi')->sole()->poste);
    }

    public function test_le_tirage_compare_aussi_le_poste_quand_il_est_envoye(): void
    {
        $jeton = $this->jeton('POSTE-ELEVAGE-01');
        $requete = fn () => $this->withHeader('Authorization', 'Bearer '.$jeton);

        $requete()->getJson('/api/sync/pull?device_id=POSTE-CAISSE')
            ->assertStatus(403)
            ->assertJsonPath('message', fn (string $m) => str_contains($m, '« POSTE-CAISSE »'));
        $this->assertSame(0, JournalSynchronisation::where('sens', 'tirage')->count());

        $requete()->getJson('/api/sync/pull?device_id=POSTE-ELEVAGE-01')->assertOk();
        // Le poste n'envoie pas son identifiant au tirage aujourd'hui : rien à comparer.
        $requete()->getJson('/api/sync/pull')->assertOk();
        $this->assertSame(['POSTE-ELEVAGE-01'], JournalSynchronisation::where('sens', 'tirage')->pluck('poste')->unique()->values()->all());
    }

    public function test_un_jeton_transitoire_sans_nom_de_poste_n_est_pas_compare(): void
    {
        // `Sanctum::actingAs` (tests) et la session web ne délivrent aucun jeton de poste : rien à comparer.
        Sanctum::actingAs($this->animalier, ['*']);
        $this->postJson('/api/sync/push', $this->envoi('poste-test'))->assertOk();

        $this->actingAs($this->animalier, 'sanctum');
        $this->getJson('/api/sync/pull?device_id=poste-test')->assertOk();
    }
}
