<?php

namespace Tests\Feature;

use App\Livewire\Comptabilite\DeclarationTva;
use App\Models\Customer;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Purchase;
use App\Models\PurchaseLine;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\Supplier;
use App\Services\VatDeclarationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.7 (Sprint 14) — Déclaration TVA (module M14, exigence impérative).
 *
 * La règle la plus lourde de conséquences est le filtre MeCeF : déclarer une
 * facture qui n'a jamais été transmise à la DGI fausserait une déclaration
 * fiscale. Elle est verrouillée par un test dédié.
 */
class DeclarationTvaTest extends TestCase
{
    use RefreshDatabase;

    private function product(string $sku, float $tvaRate): Product
    {
        $category = ProductCategory::firstOrCreate(['label' => 'Test'], ['is_active' => true]);

        return Product::create([
            'sku' => $sku,
            'name' => 'Produit '.$sku,
            'category_id' => $category->id,
            'unit' => 'pièce',
            'pricing_mode' => 'fourchette',
            'price_min' => 100,
            'price_max' => 200,
            'tva_rate' => $tvaRate,
            'stock_qty' => 100,
            'is_active' => true,
        ]);
    }

    private function sale(string $mecefStatus, array $lines): Sale
    {
        $customer = Customer::firstOrCreate(['name' => 'GBAGUIDI Solange'], ['phone' => '+22997000000', 'is_active' => true]);

        $sale = Sale::create([
            'customer_id' => $customer->id,
            'payment_mode' => 'especes',
            'subtotal' => array_sum(array_column($lines, 'ttc')),
            'discount' => 0,
            'total' => array_sum(array_column($lines, 'ttc')),
            'delivery_fee' => 0,
            'status' => 'validee',
            'mecef_status' => $mecefStatus,
        ]);

        foreach ($lines as $line) {
            SaleLine::create([
                'sale_id' => $sale->id,
                'product_id' => $line['product']->id,
                'qty' => 1,
                'unit_price' => $line['ttc'],
                'manual_total_amount' => $line['ttc'],
                'is_manual_price' => true,
            ]);
        }

        return $sale;
    }

    /** HT = arrondi(TTC / 1,18) puis TVA = TTC − HT — formule exacte du prototype. */
    public function test_ht_and_vat_are_derived_from_the_ttc_amount(): void
    {
        $service = app(VatDeclarationService::class);

        $this->assertEquals(38_136.0, $service->ht(45_000, 0.18));   // 45 000 / 1,18
        $this->assertEquals(6_864.0, $service->tva(45_000, 0.18));   // 45 000 − 38 136

        // Produit brut exonéré : HT = TTC, TVA nulle.
        $this->assertEquals(12_500.0, $service->ht(12_500, 0.0));
        $this->assertEquals(0.0, $service->tva(12_500, 0.0));
    }

    /**
     * LA RÈGLE CRITIQUE : une facture en erreur MeCeF n'a jamais été transmise
     * à la DGI — la déclarer fausserait une déclaration fiscale.
     */
    public function test_only_invoices_actually_transmitted_to_mecef_are_declared(): void
    {
        $taxable = $this->product('TVA-18', 18);

        $this->sale('transmise', [['product' => $taxable, 'ttc' => 45_000]]);
        $this->sale('erreur', [['product' => $taxable, 'ttc' => 500_000]]);      // ne doit PAS être déclarée
        $this->sale('en_attente', [['product' => $taxable, 'ttc' => 300_000]]);  // ni celle-ci

        $collectee = app(VatDeclarationService::class)
            ->tvaCollectee(now()->startOfMonth()->format('Y-m-d'), now()->endOfMonth()->format('Y-m-d'));

        $this->assertCount(1, $collectee['rows'], 'Seule la facture transmise doit figurer dans la déclaration.');
        $this->assertEquals(6_864.0, $collectee['total_tva']);
    }

    public function test_exempt_products_produce_no_vat(): void
    {
        $brut = $this->product('TVA-00', 0);
        $this->sale('transmise', [['product' => $brut, 'ttc' => 12_500]]);

        $collectee = app(VatDeclarationService::class)
            ->tvaCollectee(now()->startOfMonth()->format('Y-m-d'), now()->endOfMonth()->format('Y-m-d'));

        $this->assertEquals(0.0, $collectee['total_tva']);
        $this->assertEquals(12_500.0, $collectee['total_ht']);
        $this->assertEquals('0% (exonéré)', $collectee['rows'][0]['rate_label']);
    }

    /** Une facture mêlant 0% et 18% est signalée « mixte », jamais réduite au 1er taux. */
    public function test_a_mixed_rate_invoice_is_labelled_as_such(): void
    {
        $this->sale('transmise', [
            ['product' => $this->product('TVA-18', 18), 'ttc' => 45_000],
            ['product' => $this->product('TVA-00', 0), 'ttc' => 12_500],
        ]);

        $collectee = app(VatDeclarationService::class)
            ->tvaCollectee(now()->startOfMonth()->format('Y-m-d'), now()->endOfMonth()->format('Y-m-d'));

        $this->assertEquals('mixte', $collectee['rows'][0]['rate_label']);
        $this->assertEquals(6_864.0, $collectee['total_tva']);      // seule la ligne à 18% porte la TVA
        $this->assertEquals(57_500.0, $collectee['total_ttc']);
    }

    public function test_net_vat_becomes_a_reportable_credit_when_negative(): void
    {
        $taxable = $this->product('TVA-18', 18);
        $this->sale('transmise', [['product' => $taxable, 'ttc' => 45_000]]);   // TVA collectée 6 864

        $supplier = Supplier::create(['name' => 'Provenderie du Plateau', 'phone' => '+22997111111', 'is_active' => true]);
        $purchase = Purchase::create([
            'supplier_id' => $supplier->id,
            'payment_mode' => 'especes',
            'total' => 185_000,
            'purchase_date' => now()->format('Y-m-d'),
        ]);
        PurchaseLine::create([
            'purchase_id' => $purchase->id,
            'product_id' => $taxable->id,
            'qty' => 1,
            'unit_price' => 185_000,
        ]);

        $declaration = app(VatDeclarationService::class)
            ->declaration(now()->startOfMonth()->format('Y-m-d'), now()->endOfMonth()->format('Y-m-d'));

        $this->assertEquals(28_220.0, $declaration['deductible']['total_tva']);   // 185 000 − arrondi(185 000/1,18)
        $this->assertEquals(-21_356.0, $declaration['tva_nette']);               // 6 864 − 28 220
        $this->assertTrue($declaration['is_credit'], 'Une TVA nette négative est un crédit reportable, pas un montant à payer.');
        $this->assertEquals(21_356.0, $declaration['montant_affiche']);
    }

    public function test_component_renders_and_computes_the_deadline(): void
    {
        $this->sale('transmise', [['product' => $this->product('TVA-18', 18), 'ttc' => 45_000]]);

        Livewire::test(DeclarationTva::class)
            ->assertOk()
            ->assertSee('Déclaration TVA')
            ->assertSee('TVA Collectée (4431)')
            ->assertSet('periode', now()->format('Y-m'))
            // Échéance DGI : le 15 du mois suivant.
            ->assertSee(now()->startOfMonth()->addMonthNoOverflow()->day(15)->format('d/m/Y'));
    }
}
