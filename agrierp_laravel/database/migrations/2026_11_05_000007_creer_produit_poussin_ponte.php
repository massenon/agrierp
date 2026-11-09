<?php

use App\Support\StadePondeuse;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Ticket VOL-2 (05/11/2026), décision du client : créer le produit « Poussin d'un jour (ponte) », rangé au stade « Poussin ponte ».
 * Le « Poussin d'un jour » existant reste une catégorie des reproducteurs. Idempotent (SKU AVI-007 ou nom déjà présents : rien),
 * copie l'unité, la catégorie, l'espèce et la fourchette de prix du « Poussin d'un jour », stock à 0 (aucun stock inventé).
 */
return new class extends Migration
{
    private const NOM = "Poussin d'un jour (ponte)";

    public function up(): void
    {
        if (! DB::getSchemaBuilder()->hasTable('products')) {
            return;
        }
        if (DB::table('products')->where('name', self::NOM)->orWhere('sku', 'AVI-007')->exists()) {
            return;
        }

        $modele = DB::table('products')->where('name', "Poussin d'un jour")->first();
        $aviculture = DB::table('livestock_species')->where('code', 'aviculture')->value('id');
        $categorie = $modele->category_id ?? DB::table('product_categories')->where('label', 'Aviculture')->value('id');
        if ($categorie === null) {
            return; // base sans catalogue : rien à copier, le semoir créera le produit.
        }

        DB::table('products')->insert([
            'id' => (string) Str::uuid(),
            'sku' => 'AVI-007',
            'name' => self::NOM,
            'category_id' => $categorie,
            'unit' => $modele->unit ?? 'u',
            'pricing_mode' => $modele->pricing_mode ?? 'fourchette',
            'price_min' => $modele->price_min ?? 500,
            'price_max' => $modele->price_max ?? 700,
            'tva_rate' => $modele->tva_rate ?? 0,
            'stock_qty' => 0,
            'alert_threshold' => 0,
            'species_id' => $modele->species_id ?? $aviculture,
            'categorie_effectif' => StadePondeuse::devinerDepuisLeNom(self::NOM) ?? 'poussin_ponte',
            'is_active' => true,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        DB::table('products')->where('sku', 'AVI-007')->where('name', self::NOM)->where('stock_qty', 0)->delete();
    }
};
