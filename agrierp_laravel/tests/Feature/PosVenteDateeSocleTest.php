<?php

namespace Tests\Feature;

use App\Livewire\Ventes\PosInterface;
use App\Models\AccountingEntry;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\PeriodicClosure;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\StockMovement;
use App\Models\TreasuryAccount;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.30 — le POS web est sûr pour une date passée, SANS que le champ
 * existe encore à l'écran. `$dateVente` vide = comportement inchangé (la vente
 * du jour n'est jamais bloquée par ce ticket, même mois clôturé).
 */
class PosVenteDateeSocleTest extends TestCase
{
    use RefreshDatabase;

    private Product $produit;

    protected function setUp(): void
    {
        parent::setUp();

        Carbon::setTestNow('2026-10-14 12:00:00');

        foreach (['view-ventes', 'manage-ventes'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('caissier', 'web');
        $role->givePermissionTo(['view-ventes', 'manage-ventes']);

        $user = User::create(['name' => 'Caissière', 'email' => 'posdate@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026')]);
        $user->assignRole($role);
        $this->actingAs($user);

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);

        foreach ([['531', 'Caisse', 5], ['411', 'Clients', 4], ['701', 'Ventes', 7]] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        $categorie = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
        $this->produit = Product::create([
            'sku' => 'AVI-001', 'name' => 'Poulet', 'category_id' => $categorie->id, 'unit' => 'u',
            'pricing_mode' => 'fourchette', 'price_min' => 4_000, 'price_max' => 8_000,
            'tva_rate' => 0, 'stock_qty' => 50, 'is_active' => true,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function vendre(?string $date)
    {
        $composant = Livewire::test(PosInterface::class)
            ->set('paymentMode', 'especes')
            ->set('cart', [[
                'product_id' => $this->produit->id, 'name' => 'Poulet', 'unit' => 'u',
                'qty' => 2, 'montant' => 12_000, 'lot_id' => null, 'lot_code' => null,
            ]]);

        if ($date !== null) {
            $composant->set('dateVente', $date);
        }

        return $composant->call('validateSale');
    }

    public function test_une_vente_sans_date_reste_celle_du_jour(): void
    {
        $this->vendre(null)->assertHasNoErrors();

        $this->assertSame('2026-10-14 12:00', Sale::firstOrFail()->sold_at->format('Y-m-d H:i'));
    }

    public function test_une_vente_passee_est_enregistree_et_datee_partout(): void
    {
        $this->vendre('2026-09-20')->assertHasNoErrors();

        $vente = Sale::firstOrFail();
        $this->assertSame('2026-09-20', $vente->sold_at->format('Y-m-d'));
        $this->assertSame('2026-09-20', AccountingEntry::firstOrFail()->entry_date->format('Y-m-d'));
        $this->assertSame('2026-09-20', StockMovement::where('reference_id', $vente->id)->firstOrFail()->movement_date->format('Y-m-d'));
    }

    public function test_une_date_dans_un_mois_cloture_est_refusee(): void
    {
        PeriodicClosure::create(['period' => '2026-07', 'closed_at' => now()]);

        $this->vendre('2026-07-28')->assertHasErrors(['dateVente']);

        $this->assertSame(0, Sale::count());
        $this->assertEquals(50, $this->produit->fresh()->stock_qty);
    }

    public function test_une_date_sans_exercice_ouvert_est_refusee(): void
    {
        $this->vendre('2024-03-10')->assertHasErrors(['dateVente']);

        $this->assertSame(0, Sale::count());
    }

    public function test_une_date_future_ou_invalide_est_refusee(): void
    {
        $this->vendre('2026-10-15')->assertHasErrors(['dateVente']);
        $this->vendre('pas-une-date')->assertHasErrors(['dateVente']);
        $this->vendre('2026-02-31')->assertHasErrors(['dateVente']);

        $this->assertSame(0, Sale::count());
    }

    /** Le panier du jour n'est PAS bloqué par une clôture du mois courant : seules les ventes datées le sont. */
    public function test_la_vente_du_jour_n_est_pas_soumise_au_garde_de_date(): void
    {
        PeriodicClosure::create(['period' => '2026-10', 'closed_at' => now()]);

        $this->vendre(null)->assertHasNoErrors();

        $this->assertSame(1, Sale::count());
    }
}
