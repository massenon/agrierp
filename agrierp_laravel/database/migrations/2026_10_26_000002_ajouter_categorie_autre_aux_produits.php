<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Ajoute la catégorie « Autre » aux catégories de produits si elle n'existe pas.
 *
 * Le seeder crée les 8 catégories nominatives (Cuniculture, Aviculture, …) ;
 * pour les achats d'articles hors filière (pièces, petits outillages, divers),
 * le client demande une catégorie générique « Autre » accessible dans le modal
 * « Nouveau Produit » de l'écran Achats (ticket #39, 26/10/2026).
 *
 * Idempotente : si le label existe déjà (base reconstruite depuis le seeder
 * après que « Autre » y a été ajouté), la migration ne fait rien.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (DB::table('product_categories')->where('label', 'Autre')->doesntExist()) {
            DB::table('product_categories')->insert([
                'id'         => (string) Str::uuid(),
                'label'      => 'Autre',
                'is_active'  => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        // Ne supprime que si aucun produit ne l'utilise (suppression logique impossible
        // sans clé secondaire connue — on ne touche pas les données existantes).
        $cat = DB::table('product_categories')->where('label', 'Autre')->first();
        if ($cat && DB::table('products')->where('category_id', $cat->id)->doesntExist()) {
            DB::table('product_categories')->where('id', $cat->id)->delete();
        }
    }
};
