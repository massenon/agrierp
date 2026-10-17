<?php

namespace Tests\Feature;

use App\Models\Expense;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\TreasuryAccount;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.69 (Sprint 14) — CE QUE LE PUSH DES FICHES ACCEPTAIT.
 *
 * ⚠️⚠️ Le validateur ne contrôlait que **trois champs** — `id`, `lot_id`,
 * `entry_date` — et tout le reste passait par `fill()` sans le moindre examen.
 * Trois défauts en découlaient :
 *
 * 1. des quantités **négatives** entraient en base et gonflaient l'effectif ;
 * 2. `effectif_final` était **repris du client** : calculé avec l'effectif de la
 *    veille tel que le poste l'avait tiré, il devenait faux dès qu'une journée
 *    précédente était corrigée sur le web — et il faisait pourtant autorité ;
 * 3. deux postes saisissant la même bande le même jour provoquaient une
 *    violation de contrainte **non rattrapée**, donc un 500 pour la requête
 *    ENTIÈRE — emportant les ventes et les dépenses du même envoi.
 */
class SyncFichesElevageValidationTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $bande;

    private User $utilisateur;

    protected function setUp(): void
    {
        parent::setUp();

        $this->utilisateur = User::create([
            'name' => 'Animalier', 'username' => 'elevage',
            'email' => 'elevage@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);

        $espece = LivestockSpecies::firstOrCreate(
            ['code' => 'cuniculture'],
            ['label' => 'Cuniculture', 'is_active' => true],
        );

        $this->bande = LivestockLot::create([
            'code' => 'CUN-2026-01',
            'species_id' => $espece->id,
            'stage' => 'engraissement',
            'initial_quantity' => 40,
            'current_quantity' => 40,
            'created_date' => now()->subDays(60)->toDateString(),
            'status' => 'actif',
            'is_active' => true,
        ]);
    }

    private function pousser(array $remplacements = []): \Illuminate\Testing\TestResponse
    {
        $fiche = array_merge([
            'id' => '99999999-9999-4999-8999-999999999999',
            'lot_id' => $this->bande->id,
            'entry_date' => now()->toDateString(),
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'effectif_final' => 40,
        ], $remplacements);

        return $this->actingAs($this->utilisateur, 'sanctum')
            ->postJson('/api/sync/push', ['livestock_daily_entries' => [$fiche]]);
    }

    /** ⚠️ Un achat négatif gonflerait l'effectif au lieu de l'augmenter. */
    public function test_a_negative_quantity_is_refused(): void
    {
        $reponse = $this->pousser(['achat' => -50]);

        $reponse->assertOk();
        $reponse->assertJsonPath('livestock_daily_entries.accepted', []);
        $this->assertEquals(0, LivestockDailyEntry::count());
    }

    /**
     * ⚠️ PAS DE FICHE DANS LE FUTUR : son effectif final servirait de point de
     * départ à une journée qui n'a pas eu lieu.
     */
    public function test_a_future_dated_sheet_is_refused(): void
    {
        $reponse = $this->pousser(['entry_date' => now()->addDays(3)->toDateString()]);

        $reponse->assertOk();
        $this->assertEquals(0, LivestockDailyEntry::count());
    }

    /**
     * ⚠️⚠️ L'EFFECTIF EST RECALCULÉ PAR LE SERVEUR, jamais repris du client.
     * Le poste envoie ici un chiffre absurde : c'est le calcul du serveur qui
     * doit être stocké.
     */
    public function test_the_headcount_is_recomputed_never_trusted(): void
    {
        $this->pousser([
            'mort' => 5,
            // Le poste pretend 999 : perime, faux, ou simplement d'un autre
            // etat du monde.
            'effectif_final' => 999,
        ])->assertOk();

        // 40 de depart − 5 morts = 35.
        $this->assertEquals(35, LivestockDailyEntry::firstOrFail()->effectif_final);
    }

    /**
     * ⚠️ ET LA BORNE À ZÉRO (ticket 14.63) TIENT SUR CE CHEMIN. Reprendre le
     * nombre du client la contournait entièrement.
     */
    public function test_the_zero_floor_holds_on_the_sync_path(): void
    {
        $this->pousser(['mort' => 500, 'effectif_final' => -460])->assertOk();

        $this->assertEquals(0, LivestockDailyEntry::firstOrFail()->effectif_final);
    }

    /**
     * ⚠️⚠️ LE DÉFAUT LE PLUS COÛTEUX : deux postes, la même bande, le même jour.
     * La contrainte `unique(lot_id, entry_date)` levait une exception non
     * rattrapée — 500 pour la requête ENTIÈRE, ventes et dépenses du même envoi
     * perdues avec elle.
     */
    public function test_a_duplicate_day_rejects_only_that_sheet(): void
    {
        // Un premier poste a deja transmis la journee.
        LivestockDailyEntry::create([
            'lot_id' => $this->bande->id,
            'entry_date' => now()->toDateString(),
            'effectif_final' => 40,
        ]);

        $caisse = TreasuryAccount::create([
            'label' => 'Caisse Physique', 'account_code' => '531',
            'type' => 'caisse', 'balance' => 500000, 'is_active' => true,
        ]);

        // Second poste : sa fiche entre en conflit, mais son envoi porte AUSSI
        // une depense qui, elle, n'a rien a se reprocher.
        $reponse = $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'livestock_daily_entries' => [[
                'id' => '11111111-1111-4111-8111-111111111111',
                'lot_id' => $this->bande->id,
                'entry_date' => now()->toDateString(),
                'achat' => 0, 'ne' => 0, 'mort' => 2, 'vente' => 0, 'don' => 0,
                'effectif_final' => 38,
            ]],
            'expenses' => [[
                'id' => '22222222-2222-4222-8222-222222222222',
                'expense_date' => now()->toDateString(),
                'label' => 'Gasoil groupe',
                'category' => '605 - Énergie',
                'amount' => 12000,
                'treasury_account_id' => $caisse->id,
            ]],
        ]);

        // ⚠️ 200, pas 500 : un conflit sur une table n'emporte pas les autres.
        $reponse->assertOk();
        $reponse->assertJsonPath('livestock_daily_entries.accepted', []);
        $this->assertStringContainsString(
            'existe deja',
            $reponse->json('livestock_daily_entries.rejected.0.reason'),
            'le motif doit etre lisible au poste',
        );

        // ⚠️ La depense du meme envoi est passee : c'est tout l'enjeu.
        $this->assertEquals(1, Expense::count(),
            'un conflit d elevage ne doit pas faire perdre une depense');
    }

    /** Le flux nominal reste accepté. */
    public function test_a_valid_sheet_is_still_accepted(): void
    {
        $this->pousser(['mort' => 2])->assertOk();

        $this->assertEquals(38, LivestockDailyEntry::firstOrFail()->effectif_final);
    }
}
