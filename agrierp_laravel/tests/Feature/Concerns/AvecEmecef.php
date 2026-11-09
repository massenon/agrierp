<?php

namespace Tests\Feature\Concerns;

use App\Models\ChartOfAccount;
use App\Models\CompanySetting;
use App\Models\Customer;
use App\Models\FiscalYear;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\Sale;
use App\Models\SaleLine;
use App\Models\User;
use Illuminate\Support\Facades\Http;

/**
 * MECEF-1 — décor commun des tests de la passerelle e-MECeF : réglage en mode `emecef`, produits à 18 % et exonéré, ventes
 * « à facturer ». AUCUN appel réel : tout passe par `Http::fake`.
 */
trait AvecEmecef
{
    public const JETON = 'JWT-SECRET-NE-JAMAIS-AFFICHER';

    public const URL = 'https://emcf.test/api';

    protected Product $taxable;

    protected Product $exonere;

    protected function reglerEmecef(string $mode = 'emecef', ?string $jeton = self::JETON, string $ifu = '3202601234567'): CompanySetting
    {
        $r = CompanySetting::current();
        $r->update([
            'company_name' => 'Ferme École', 'ifu' => $ifu, 'mecef_mode' => $mode, 'mecef_api_url' => self::URL,
            'mecef_jeton_encrypted' => $jeton, 'mecef_operateur_id' => '7', 'mecef_operateur_nom' => 'Caissière Test',
        ]);

        return $r->fresh();
    }

    protected function decorVentes(): void
    {
        foreach (['view-ventes', 'manage-ventes', 'view-facturation', 'manage-facturation', 'manage-parametres', 'view-parametres'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('administrateur-test', 'web');
        $role->givePermissionTo(Permission::all());
        $u = User::create(['name' => 'Admin', 'username' => 'admin-e', 'email' => 'adm@x.bj', 'password' => bcrypt('x'), 'is_active' => true]);
        $u->assignRole($role);
        $this->actingAs($u);

        FiscalYear::create([
            'year' => now()->year, 'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'), 'status' => 'ouvert',
        ]);
        foreach ([['531', 'Caisse', 5], ['411', 'Clients', 4], ['443', 'TVA facturée', 4], ['701', 'Ventes de produits', 7]] as [$c, $l, $k]) {
            ChartOfAccount::create(['code' => $c, 'label' => $l, 'class' => $k, 'is_active' => true]);
        }

        $cat = ProductCategory::create(['label' => 'Œufs', 'is_active' => true]);
        $this->taxable = Product::create(['sku' => 'OEUF', 'name' => 'Plaquette d\'œufs', 'category_id' => $cat->id, 'unit' => 'plaquette',
            'pricing_mode' => 'fourchette', 'price_min' => 2000, 'price_max' => 6000, 'tva_rate' => 18, 'stock_qty' => 100, 'is_active' => true]);
        $this->exonere = Product::create(['sku' => 'MAIS', 'name' => 'Maïs brut', 'category_id' => $cat->id, 'unit' => 'kg',
            'pricing_mode' => 'fourchette', 'price_min' => 100, 'price_max' => 600, 'tva_rate' => 0, 'stock_qty' => 100, 'is_active' => true]);
    }

    /** @param array<int, array{0: Product, 1: float, 2: int}> $lignes produit, quantité, montant de la ligne */
    protected function venteAFacturer(array $lignes = [], int $remise = 0, string $mode = 'especes', array $choix = ['facture_type' => 'normalisee', 'client_nom_facture' => 'AMOUSSOU Régis', 'aib_taux' => 'N/A']): Sale
    {
        $lignes = $lignes ?: [[$this->taxable, 2, 11800]];
        $client = Customer::firstOrCreate(['name' => 'AMOUSSOU Régis'], ['is_active' => true]);
        $sousTotal = array_sum(array_column($lignes, 2));

        $vente = Sale::create(['customer_id' => $client->id, 'payment_mode' => $mode, 'subtotal' => $sousTotal, 'discount' => $remise,
            'total' => $sousTotal - $remise, 'delivery_fee' => 0, 'status' => 'validee'] + $choix);

        foreach ($lignes as [$produit, $qte, $montant]) {
            SaleLine::create(['sale_id' => $vente->id, 'product_id' => $produit->id, 'qty' => $qte,
                'unit_price' => $montant / $qte, 'manual_total_amount' => $montant, 'is_manual_price' => true]);
        }

        return $vente->fresh('lines');
    }

    /** Réponses e-MECeF de succès : création puis confirmation. */
    protected function fauxEmecefSucces(string $uid = 'uid-dgi-001'): void
    {
        Http::fake([
            self::URL.'/invoice' => Http::response(['uid' => $uid, 'total' => 11800, 'ts' => 1800], 200),
            self::URL.'/invoice/*/confirm' => Http::response([
                'qrCode' => 'F;ED01000001;TEST-AAAA-BBBB-CCCC;3202601234567;20261107101500',
                'codeMECeFDGI' => 'TEST-AAAA-BBBB-CCCC', 'counters' => '12/34 FV', 'nim' => 'ED01000001',
                'dateTime' => '2026-11-07T10:15:00',
            ], 200),
        ]);
    }
}
