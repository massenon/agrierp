<?php

namespace Tests\Feature;

use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Services\AutonomieAlimentaireService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * 🔴→✅ Ticket U14 — LE PRODUIT DE PROVENDE D'UNE FILIÈRE ET LE POIDS DU SAC NE DÉPENDENT PLUS DE L'ORDRE DE LA BASE.
 *
 * `produitProvende()` faisait `first()` et `stockEnKg()` `value()` SANS `orderBy` : avec deux candidats, MySQL rendait
 * celui de son plan d'exécution. Le premier PAR IDENTIFIANT, désormais — la règle que le poste suit (parité exécutée :
 * `agrierp_flutter/test/provende_autonomie_parite_test.dart`). Les lignes sont insérées dans l'ordre INVERSE des
 * identifiants : sans `orderBy`, SQLite rend l'ordre d'insertion et le test rougit.
 */
class AutonomieProduitProvendeTest extends TestCase
{
    use RefreshDatabase;

    public function test_le_premier_candidat_par_identifiant_et_le_premier_type_de_provende_par_identifiant(): void
    {
        $lapins = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $t = now();

        foreach ([['ffffffff-0000-4000-8000-000000000001', 'Provende lapin'], ['11111111-0000-4000-8000-000000000001', 'ALIMENT lapin']] as [$id, $nom]) {
            DB::table('products')->insert([
                'id' => $id, 'sku' => $id, 'name' => $nom, 'category_id' => $categorie->id, 'species_id' => $lapins->id,
                'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'tva_rate' => 0,
                'stock_qty' => 3, 'is_active' => true, 'created_at' => $t, 'updated_at' => $t,
            ]);
        }
        foreach ([['ffffffff-0000-4000-8000-0000000000aa', 50], ['11111111-0000-4000-8000-0000000000aa', 40]] as [$id, $sac]) {
            DB::table('feed_types')->insert([
                'id' => $id, 'name' => 'Type '.$sac, 'standard_bag_weight_kg' => $sac, 'price_per_kg' => 100,
                'is_active' => true, 'created_at' => $t, 'updated_at' => $t,
            ]);
        }

        $produit = app(AutonomieAlimentaireService::class)->produitProvende('cuniculture');

        $this->assertSame('ALIMENT lapin', $produit?->name);
        $this->assertSame(120.0, $produit->stockEnKg(), '3 sacs du premier type (40 Kg)');
        $this->assertInstanceOf(Product::class, $produit);
    }
}
