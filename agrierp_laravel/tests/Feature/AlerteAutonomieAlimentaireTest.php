<?php

namespace Tests\Feature;

use App\Actions\RaiseFeedAutonomyAlertAction;
use App\Models\Notification;
use App\Models\Product;
use App\Models\ProductCategory;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.40 (Sprint 14) — ALERTE D'AUTONOMIE ALIMENTAIRE.
 *
 * Gap documenté depuis le ticket 13.1 : le calcul existait, mais **uniquement
 * affiché dans la fiche consultée**. L'alerte n'était visible que si l'on
 * ouvrait précisément la bonne fiche — c'est-à-dire jamais au moment où elle
 * est utile.
 *
 * Et une régression introduite au ticket 14.36, corrigée ici : l'aliment étant
 * compté en SACS de 25 kg, lire `stock_qty` comme des kilos donnait une
 * autonomie **25 fois trop faible**, donc une alerte permanente.
 */
class AlerteAutonomieAlimentaireTest extends TestCase
{
    use RefreshDatabase;

    private Product $aliment;

    protected function setUp(): void
    {
        parent::setUp();

        \DB::table('feed_types')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Aliment lapins', 'standard_bag_weight_kg' => 25,
            'price_per_kg' => 290, 'is_active' => true,
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);

        $this->aliment = Product::create([
            'sku' => 'ALI-004', 'name' => 'Aliment lapins reproducteur 25kg',
            'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'price_min' => 7_250, 'price_max' => 8_250,
            'tva_rate' => 0, 'stock_qty' => 4, 'alert_threshold' => 8, 'is_active' => true,
        ]);
    }

    // ------------------------------------------------- la conversion d'unité

    /**
     * LA RÉGRESSION CORRIGÉE : 4 sacs, c'est 100 kg, pas 4 kg.
     */
    public function test_feed_stock_is_converted_from_bags_to_kilos(): void
    {
        $this->assertEquals(100.0, $this->aliment->stockEnKg(), '4 sacs de 25 kg.');
    }

    /** Un produit compté à l'unité n'est pas converti. */
    public function test_a_unit_counted_product_is_not_converted(): void
    {
        $autre = Product::create([
            'sku' => 'MED-001', 'name' => 'Anti-coccidien', 'category_id' => $this->aliment->category_id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 4_500, 'price_max' => 6_000,
            'tva_rate' => 18, 'stock_qty' => 4, 'is_active' => true,
        ]);

        $this->assertEquals(4.0, $autre->stockEnKg());
    }

    // ------------------------------------------------------------ l'alerte

    /** Sous le seuil de 3 jours, l'alerte remonte à la cloche. */
    public function test_an_autonomy_below_three_days_raises_an_alert(): void
    {
        // 100 kg pour 40 kg/jour = 2,5 jours
        $alerte = app(RaiseFeedAutonomyAlertAction::class)->execute($this->aliment, 40);

        $this->assertNotNull($alerte);
        $this->assertEquals('stock_low', $alerte->type);
        $this->assertEquals('animalier', $alerte->target_role, "Destinee au ROLE, pas a l'auteur de la saisie.");
        $this->assertStringContainsString('2,5 jours', $alerte->message);
        $this->assertFalse((bool) $alerte->is_read);
    }

    /** Au-dessus du seuil, rien n'est signalé. */
    public function test_a_comfortable_autonomy_raises_nothing(): void
    {
        // 100 kg pour 10 kg/jour = 10 jours
        $this->assertNull(app(RaiseFeedAutonomyAlertAction::class)->execute($this->aliment, 10));
        $this->assertEquals(0, Notification::count());
    }

    /** Moins d'un jour d'autonomie : la sévérité passe à critique. */
    public function test_less_than_a_day_is_critical(): void
    {
        $alerte = app(RaiseFeedAutonomyAlertAction::class)->execute($this->aliment, 150);

        $this->assertEquals('critique', $alerte->severity);
    }

    /**
     * ⚠️ LE PIÈGE ÉVITÉ : une consommation nulle donne une autonomie INFINIE,
     * pas nulle. Diviser par zéro produirait l'alerte la plus grave sur le lot
     * le plus vide.
     */
    public function test_no_consumption_means_infinite_autonomy_not_zero(): void
    {
        $this->assertNull(app(RaiseFeedAutonomyAlertAction::class)->execute($this->aliment, 0));
        $this->assertEquals(0, Notification::count());
    }

    // ------------------------------------------------------- déduplication

    /**
     * Une fiche se sauvegarde plusieurs fois : sans déduplication, la cloche
     * deviendrait illisible en une matinée.
     */
    public function test_saving_repeatedly_does_not_stack_identical_alerts(): void
    {
        $action = app(RaiseFeedAutonomyAlertAction::class);

        $action->execute($this->aliment, 40);
        $action->execute($this->aliment, 40);
        $action->execute($this->aliment, 40);

        $this->assertEquals(1, Notification::where('type', 'stock_low')->count());
    }

    /**
     * ⚠️ L'ALERTE SE RÉSORBE au réapprovisionnement. Une alerte de rupture qui
     * survit à la livraison apprend à l'utilisateur à ignorer la cloche — et le
     * jour d'une vraie rupture, il l'ignorera aussi.
     */
    public function test_restocking_clears_the_open_alert(): void
    {
        $action = app(RaiseFeedAutonomyAlertAction::class);

        $action->execute($this->aliment, 40);
        $this->assertEquals(1, Notification::where('is_read', false)->count());

        // Livraison : 40 sacs, soit 1 000 kg.
        $this->aliment->update(['stock_qty' => 40]);

        $action->execute($this->aliment->fresh(), 40);

        $this->assertEquals(0, Notification::where('is_read', false)->count(),
            "L'alerte n'a plus lieu d'etre une fois le stock reconstitue.");
        $this->assertEquals(1, Notification::count(), "Mais elle reste tracee, jamais supprimee.");
    }

    /** Le message porte les chiffres qui permettent de décider. */
    public function test_the_message_carries_the_numbers_needed_to_act(): void
    {
        $alerte = app(RaiseFeedAutonomyAlertAction::class)->execute($this->aliment, 40);

        $this->assertStringContainsString('100 kg en stock', $alerte->message);
        $this->assertStringContainsString('40,0 kg consommés par jour', $alerte->message);
        $this->assertStringContainsString('ALI-004', $alerte->link_url);
    }
}
