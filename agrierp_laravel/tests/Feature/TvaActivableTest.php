<?php

namespace Tests\Feature;

use App\Actions\RecordSaleAccountingEntryAction;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\CompanySetting;
use App\Models\FiscalYear;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Services\TvaSettingService;
use App\Services\VatDeclarationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.38 (Sprint 14) — TVA ACTIVABLE OU NON.
 *
 * Le point qui compte : le réglage pilote L'AFFICHAGE **et** LES ÉCRITURES.
 * Ne piloter que l'affichage aurait été le piège — les écrans auraient montré
 * du HT pendant que le grand livre continuait de ventiler une taxe, et la
 * Déclaration TVA aurait présenté un montant à reverser sur une entreprise non
 * assujettie.
 */
class TvaActivableTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();

        TvaSettingService::oublier();

        FiscalYear::create([
            'year' => now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        foreach ([
            ['531', 'Caisse', 5],
            ['443', 'TVA facturée', 4],
            ['701', 'Ventes de produits', 7],
        ] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }

        $categorie = ProductCategory::create(['label' => 'Transformation', 'is_active' => true]);

        $this->produit = Product::create([
            'sku' => 'TRA-002', 'name' => 'Poulet fumé', 'category_id' => $categorie->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 4_500, 'price_max' => 5_500,
            'tva_rate' => 18, 'stock_qty' => 50, 'is_active' => true,
        ]);
    }

    private function reglerTva(bool $active): void
    {
        CompanySetting::create([
            'company_name' => 'FERME ÉCOLE OLOUWACHEGOUN',
            'tva_enabled' => $active,
        ]);

        TvaSettingService::oublier();
    }

    private function vendre(float $montant = 11_800): Sale
    {
        $vente = Sale::create([
            'payment_mode' => 'especes', 'subtotal' => $montant, 'discount' => 0,
            'total' => $montant, 'delivery_fee' => 0, 'status' => 'validee',
            'mecef_status' => 'transmise',
        ]);

        SaleLine::create([
            'sale_id' => $vente->id, 'product_id' => $this->produit->id,
            'qty' => 2, 'unit_price' => $montant / 2, 'manual_total_amount' => $montant,
        ]);

        app(RecordSaleAccountingEntryAction::class)->execute($vente->fresh('lines'));

        return $vente->fresh();
    }

    private function ligne(Sale $vente, string $code): ?\App\Models\AccountingEntryLine
    {
        return AccountingEntry::with('lines.account')
            ->findOrFail($vente->accounting_entry_id)
            ->lines
            ->first(fn ($l) => $l->account->code === $code);
    }

    // ------------------------------------------------------- TVA ACTIVE

    /** TVA active : le montant est TTC et la taxe est ventilée. */
    public function test_with_vat_enabled_the_amount_is_split_between_ht_and_tax(): void
    {
        $this->reglerTva(true);

        $vente = $this->vendre(11_800);

        $this->assertEquals(10_000, (float) $this->ligne($vente, '701')->credit, 'Produit au HT.');
        $this->assertEquals(1_800, (float) $this->ligne($vente, '443')->credit, 'TVA collectee.');
        $this->assertEquals(11_800, (float) $this->ligne($vente, '531')->debit, 'Encaissement TTC.');
    }

    public function test_with_vat_enabled_the_label_is_ttc(): void
    {
        $this->reglerTva(true);

        $this->assertTrue(app(TvaSettingService::class)->active());
        $this->assertEquals('TTC', app(TvaSettingService::class)->libelleMontant());
        $this->assertEquals(18.0, app(TvaSettingService::class)->tauxPour(18));
    }

    // ----------------------------------------------------- TVA INACTIVE

    /**
     * LE POINT CENTRAL : TVA désactivée, AUCUNE ligne de taxe n'est produite.
     * La totalité du montant va au compte de produit.
     */
    public function test_with_vat_disabled_no_tax_line_is_ever_posted(): void
    {
        $this->reglerTva(false);

        $vente = $this->vendre(11_800);

        $this->assertEquals(11_800, (float) $this->ligne($vente, '701')->credit,
            'La totalite va au produit : aucun HT/TVA a ventiler.');
        $this->assertNull($this->ligne($vente, '443'), 'Aucune ligne de TVA collectee.');
        $this->assertEquals(11_800, (float) $this->ligne($vente, '531')->debit);
    }

    /** Le montant devient un montant HT, et le libellé le dit. */
    public function test_with_vat_disabled_the_label_is_ht(): void
    {
        $this->reglerTva(false);

        $service = app(TvaSettingService::class);

        $this->assertFalse($service->active());
        $this->assertTrue($service->inactive());
        $this->assertEquals('HT', $service->libelleMontant());
    }

    /**
     * ⚠️ LE TAUX DU CATALOGUE RESTE INCHANGÉ EN BASE. Le jour où
     * l'exploitation devient assujettie, rien n'est à ressaisir.
     */
    public function test_the_product_rate_is_neutralised_not_erased(): void
    {
        $this->reglerTva(false);

        $this->assertEquals(0.0, app(TvaSettingService::class)->tauxPour(18), 'Taux neutralise a la lecture.');
        $this->assertEquals(18, (float) $this->produit->fresh()->tva_rate, 'Mais conserve au catalogue.');
    }

    /** La déclaration ne présente rien à reverser sur une non-assujettie. */
    public function test_a_non_liable_business_has_nothing_to_declare(): void
    {
        $this->reglerTva(false);

        $this->vendre(11_800);

        $service = app(VatDeclarationService::class);

        $this->assertFalse($service->assujettie());

        $collectee = $service->tvaCollectee(
            now()->startOfMonth()->format('Y-m-d'), now()->endOfMonth()->format('Y-m-d')
        );

        $this->assertEquals(0, $collectee['total_tva'], 'Aucune TVA a reverser.');
        $this->assertEquals(11_800, $collectee['total_ht'], "Le montant reste celui de l'operation.");
    }

    /** Sans paramétrage, l'exploitation est réputée assujettie. */
    public function test_the_default_is_liable_when_nothing_is_configured(): void
    {
        TvaSettingService::oublier();

        $this->assertTrue(app(TvaSettingService::class)->active(),
            "Cesser silencieusement de collecter la TVA serait bien plus grave que l'inverse.");
    }
}
