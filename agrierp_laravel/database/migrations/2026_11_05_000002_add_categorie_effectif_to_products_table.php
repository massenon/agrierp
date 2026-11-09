<?php

use App\Support\CategorieVolaille;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Ticket VOL-1 (04/11/2026) — CATÉGORIE D'EFFECTIF D'UN PRODUIT de l'aviculture-reproducteurs.
 *
 * La caisse (web et poste) range chaque vente de sujets vivants dans la catégorie du PRODUIT vendu :
 * `reproducteur`, `jeune` ou `poussin` (NULL pour tous les autres produits). Les produits de l'aviculture existants
 * reçoivent une valeur PAR DÉFAUT d'après leur nom (voir [CategorieVolaille::devinerDepuisLeNom]) :
 * poussin d'un jour → poussin ; poulet / jeune en maturité → jeune ; coq / poule reproductrice → reproducteur.
 * Un produit dont le nom ne se range pas reste SANS catégorie (jamais rangé au hasard) : sa vente sur une bande à chaîne
 * est refusée avec un motif clair, et la valeur se pose dans « Modifier un produit ».
 *
 * Idempotente : ne touche jamais une valeur déjà posée.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('products', 'categorie_effectif')) {
            Schema::table('products', function (Blueprint $table) {
                $table->string('categorie_effectif', 20)->nullable();
            });
        }

        $aviculture = DB::table('livestock_species')->where('code', 'aviculture')->value('id');
        if ($aviculture === null) {
            return;
        }

        DB::table('products')
            ->where('species_id', $aviculture)
            ->whereNull('categorie_effectif')
            ->get(['id', 'name'])
            ->each(function ($produit) {
                $categorie = CategorieVolaille::devinerDepuisLeNom($produit->name);
                if ($categorie !== null) {
                    DB::table('products')->where('id', $produit->id)->update(['categorie_effectif' => $categorie]);
                }
            });
    }

    public function down(): void
    {
        if (Schema::hasColumn('products', 'categorie_effectif')) {
            Schema::table('products', function (Blueprint $table) {
                $table->dropColumn('categorie_effectif');
            });
        }
    }
};
