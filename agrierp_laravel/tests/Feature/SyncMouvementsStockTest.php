<?php

namespace Tests\Feature;

use App\Actions\AdjustStockAction;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\StockMovement;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Ticket U9 — LE GRAND LIVRE DES STOCKS (`stock_movements`) DESCEND AU POSTE.
 *
 * « Rotation du Stock », « Écarts d'Inventaire » (Gestion des Stocks) et le Tableau 3 de la ponte (Rapports) lisent
 * ce journal au web ; le poste ne le recevait pas et affichait « — », ou des chiffres limités à ses propres saisies.
 * Ce que ces tests verrouillent :
 *  - le tirage complet sert TOUT le journal, avec les seules colonnes du calcul et de l'affichage (aucun horodatage
 *    technique), la date en heure murale du serveur ;
 *  - au curseur, avec un recouvrement de deux minutes (un mouvement écrit pendant un tirage n'est jamais perdu) ;
 *  - c'est un journal écrit par le serveur SEUL : un envoi de `stock_movements` est ignoré et compté, rien n'est créé ;
 *  - l'ajustement envoyé par le poste redescend comme mouvement portant l'identifiant de la ligne du poste — c'est
 *    ce qui permet au poste de ne jamais le compter deux fois.
 */
class SyncMouvementsStockTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private Product $provende;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->utilisateur = User::create([
            'name' => 'Administrateur', 'username' => 'admin',
            'email' => 'dg@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->utilisateur->assignRole('admin');

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $this->provende = Product::create([
            'sku' => 'ALI-PONTE', 'name' => 'Provende ponte', 'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'price_min' => 8000, 'price_max' => 8000,
            'stock_qty' => 10, 'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function tirer(?string $depuis = null)
    {
        return $this->actingAs($this->utilisateur, 'sanctum')
            ->getJson('/api/sync/pull'.($depuis ? '?since='.urlencode($depuis) : ''))
            ->assertOk();
    }

    public function test_le_tirage_complet_sert_tout_le_journal_avec_les_seules_colonnes_utiles(): void
    {
        Carbon::setTestNow('2026-10-12 23:30:00');
        app(AdjustStockAction::class)->execute($this->provende, -3, 'adjustment', null, now(), 'Vol / Disparition');
        Carbon::setTestNow('2026-10-13 09:00:00');
        app(AdjustStockAction::class)->execute($this->provende, 2.5, 'purchase', (string) Str::uuid());

        $mouvements = collect($this->tirer()->json('stock_movements'));

        $this->assertCount(2, $mouvements);
        $this->assertSame(StockMovement::count(), $mouvements->count());
        $vol = $mouvements->firstWhere('reference_type', 'adjustment');
        // Exactement ces clés : ni `created_at`, ni `updated_at`.
        $this->assertEqualsCanonicalizing(
            ['id', 'product_id', 'type', 'quantity', 'reference_type', 'reference_id', 'reason', 'movement_date'],
            array_keys($vol),
        );
        $this->assertSame('sortie', $vol['type']);
        $this->assertSame(3.0, (float) $vol['quantity']);
        $this->assertSame('Vol / Disparition', $vol['reason']);
        $this->assertNull($vol['reference_id']);
        $this->assertSame($this->provende->id, $vol['product_id']);
        // Heure MURALE du serveur : le 12 à 23 h 30 reste le 12, quel que soit le fuseau du poste.
        $this->assertSame('2026-10-12 23:30:00', $vol['movement_date']);
        $this->assertSame(2.5, (float) $mouvements->firstWhere('reference_type', 'purchase')['quantity']);
        // Ordre chronologique.
        $this->assertSame(['adjustment', 'purchase'], $mouvements->pluck('reference_type')->all());
    }

    public function test_au_curseur_avec_un_recouvrement_de_deux_minutes(): void
    {
        Carbon::setTestNow('2026-10-19 08:00:00');
        app(AdjustStockAction::class)->execute($this->provende, -1, 'sale', (string) Str::uuid());
        // Écrit 90 secondes AVANT le curseur, pendant le tirage précédent : il n'avait pas été lu.
        Carbon::setTestNow('2026-10-19 09:58:30');
        app(AdjustStockAction::class)->execute($this->provende, -2, 'sale', (string) Str::uuid());
        Carbon::setTestNow('2026-10-19 10:30:00');
        app(AdjustStockAction::class)->execute($this->provende, 4, 'purchase', (string) Str::uuid());

        $depuis = Carbon::parse('2026-10-19 10:00:00')->toIso8601String();
        $quantites = collect($this->tirer($depuis)->json('stock_movements'))->pluck('quantity')->map(fn ($q) => (float) $q);

        $this->assertEquals([2.0, 4.0], $quantites->all(), 'le mouvement de 8 h est déjà au poste ; celui de 9 h 58 est resservi');
    }

    public function test_sans_rien_de_nouveau_aucun_mouvement_ne_descend(): void
    {
        Carbon::setTestNow('2026-10-19 08:00:00');
        app(AdjustStockAction::class)->execute($this->provende, -1, 'sale', (string) Str::uuid());

        $this->assertSame([], $this->tirer(Carbon::parse('2026-10-19 09:00:00')->toIso8601String())->json('stock_movements'));
    }

    public function test_un_envoi_de_mouvements_est_ignore_et_compte_rien_n_est_cree(): void
    {
        $reponse = $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'stock_movements' => [[
                'id' => (string) Str::uuid(), 'product_id' => $this->provende->id, 'type' => 'entree',
                'quantity' => 99, 'reference_type' => 'adjustment', 'movement_date' => '2026-10-19 08:00:00',
            ]],
        ])->assertOk();

        $this->assertSame(1, $reponse->json('referentiels_ignored'));
        $this->assertSame(0, StockMovement::count());
        $this->assertEquals(10, (float) $this->provende->fresh()->stock_qty);
    }

    public function test_l_ajustement_du_poste_redescend_avec_l_identifiant_de_sa_ligne(): void
    {
        $ligneDuPoste = (string) Str::uuid();

        $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', [
            'stock_adjustments' => [[
                'client_ref' => $ligneDuPoste, 'product_id' => $this->provende->id, 'type' => 'sortie',
                'quantity' => 4, 'reference_type' => 'inventaire', 'reason' => 'Casse de matériel',
            ]],
        ])->assertOk()->assertJsonPath('stock_adjustments.accepted', [$ligneDuPoste]);

        $mouvement = collect($this->tirer()->json('stock_movements'))->sole();

        $this->assertSame($ligneDuPoste, $mouvement['reference_id']);
        $this->assertSame('inventaire', $mouvement['reference_type']);
        $this->assertSame('sortie', $mouvement['type']);
        $this->assertSame(4.0, (float) $mouvement['quantity']);
    }
}
