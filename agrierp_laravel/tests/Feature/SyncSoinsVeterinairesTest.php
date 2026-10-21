<?php

namespace Tests\Feature;

use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\ProphylaxisScheduleStandard;
use App\Models\Role;
use App\Models\User;
use App\Models\VeterinaryRecord;
use App\Models\VeterinaryWithdrawalPeriod;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.54 (Sprint 14) — SOINS VÉTÉRINAIRES SYNCHRONISÉS.
 *
 * 🔴 LE DÉFAUT QUE CE TICKET EMPÊCHE. La règle « un délai d'attente > 0 bloque
 * la bande à la vente » vivait dans l'écran web, donc inatteignable depuis la
 * synchronisation. Un soin administré HORS LIGNE puis remonté aurait créé le
 * registre vétérinaire **sans sa période de rémanence** : la bande serait
 * restée vendable, et la ferme aurait pu écouler une viande porteuse de résidus
 * d'antibiotiques sans que rien ne le signale.
 */
class SyncSoinsVeterinairesTest extends TestCase
{
    use RefreshDatabase;

    private const MDP = 'AgriERP@2026';

    private LivestockLot $bande;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('animalier', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);

        $user = User::create([
            'name' => 'Chef d\'Élevage', 'username' => 'elevage',
            'email' => 'elevage@fermeolouwachegoun.com',
            'password' => bcrypt(self::MDP), 'is_active' => true,
        ]);
        $user->assignRole('animalier');

        $espece = LivestockSpecies::create(['label' => 'Cuniculture', 'code' => 'CUN', 'is_active' => true]);

        $this->bande = LivestockLot::create([
            'code' => 'CUN-2026-01', 'species_id' => $espece->id, 'stage' => 'croissance',
            'initial_quantity' => 40, 'current_quantity' => 40,
            'created_date' => now()->subMonths(2)->format('Y-m-d'),
            'status' => 'actif', 'is_active' => true,
        ]);

        $this->token = $this->postJson('/api/auth/login', [
            'identifiant' => 'elevage', 'password' => self::MDP, 'device_name' => 'poste-ferme-01',
        ])->json('token');
    }

    private function pousserSoin(array $remplacements = [])
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->postJson('/api/sync/push', [
                'veterinary_records' => [array_merge([
                    'id' => '11111111-1111-4111-8111-111111111111',
                    'lot_id' => $this->bande->id,
                    'action_type' => 'Vaccination',
                    'product_used' => 'Antibiotique polyvalent',
                    'dose' => '2 ml',
                    'record_date' => now()->format('Y-m-d'),
                    'withdrawal_days' => 7,
                ], $remplacements)],
            ]);
    }

    /** Le soin arrive avec son UUID client préservé. */
    public function test_the_offline_care_reaches_the_server(): void
    {
        $this->pousserSoin()->assertOk();

        $soin = VeterinaryRecord::findOrFail('11111111-1111-4111-8111-111111111111');

        $this->assertEquals('Vaccination', $soin->action_type);
        $this->assertEquals($this->bande->id, $soin->lot_id);
    }

    /**
     * 🔴→✅ L'EFFET QUI COMPTE : la rémanence est créée, donc la bande est
     * bloquée à la vente. Sans lui, la viande partait au comptoir.
     */
    public function test_the_withdrawal_period_is_created(): void
    {
        $this->pousserSoin();

        $remanence = VeterinaryWithdrawalPeriod::where('lot_id', $this->bande->id)->firstOrFail();

        $this->assertEquals(7, $remanence->withdrawal_days);
        $this->assertTrue(VeterinaryWithdrawalPeriod::isLotBlocked($this->bande->id));
    }

    /** Un soin sans délai d'attente ne bloque rien. */
    public function test_a_care_without_delay_blocks_nothing(): void
    {
        $this->pousserSoin(['withdrawal_days' => 0]);

        $this->assertEquals(0, VeterinaryWithdrawalPeriod::count());
        $this->assertFalse(VeterinaryWithdrawalPeriod::isLotBlocked($this->bande->id));
    }

    /**
     * ⚠️ La rémanence n'est créée que si un PRODUIT est nommé : un délai sans
     * produit ne dit pas de quoi la viande doit se purger.
     */
    public function test_a_delay_without_a_product_creates_nothing(): void
    {
        $this->pousserSoin(['product_used' => null]);

        $this->assertEquals(1, VeterinaryRecord::count(), 'le soin est enregistre');
        $this->assertEquals(0, VeterinaryWithdrawalPeriod::count());
    }

    /**
     * ⚠️ UN RENVOI APRÈS COUPURE N'EMPILE PAS LES RÉMANENCES : la bande serait
     * bloquée deux fois plus longtemps qu'elle ne doit l'être.
     */
    public function test_a_repeated_push_stacks_nothing(): void
    {
        $this->pousserSoin()->assertOk();
        $this->pousserSoin()->assertOk();

        $this->assertEquals(1, VeterinaryRecord::count());
        $this->assertEquals(1, VeterinaryWithdrawalPeriod::count());
    }

    /** Une bande inconnue est refusée avec son motif, jamais avalée. */
    public function test_an_unknown_lot_is_rejected_with_its_reason(): void
    {
        $reponse = $this->pousserSoin(['lot_id' => '99999999-9999-4999-8999-999999999999']);

        $reponse->assertOk();
        $this->assertCount(1, $reponse->json('veterinary_records.rejected'));
        $this->assertEquals(0, VeterinaryRecord::count());
    }

    /** Le calendrier prophylactique descend au poste. */
    public function test_the_prophylaxis_schedule_reaches_the_client(): void
    {
        ProphylaxisScheduleStandard::create([
            'species_code' => 'cuniculture',
            'period_label' => 'Semaine 4',
            'treatment' => 'Vaccination myxomatose',
            'product_recommended' => 'Vaccin myxo',
            'dosage' => '1 ml',
            'withdrawal_days' => 0,
            'is_active' => true,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->getJson('/api/sync/pull')
            ->assertOk()
            ->assertJsonPath('prophylaxis_schedule_standards.0.treatment', 'Vaccination myxomatose');
    }

    /** Le registre des soins déjà administrés descend aussi. */
    public function test_the_care_history_reaches_the_client(): void
    {
        $this->pousserSoin();

        $this->withHeader('Authorization', 'Bearer '.$this->token)
            ->getJson('/api/sync/pull')
            ->assertOk()
            ->assertJsonPath('veterinary_records.0.action_type', 'Vaccination');
    }
}
