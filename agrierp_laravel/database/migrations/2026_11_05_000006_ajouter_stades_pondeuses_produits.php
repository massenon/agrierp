<?php

use App\Support\CategorieVolaille;
use App\Support\StadePondeuse;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Ticket VOL-2 (05/11/2026) — STADE D'EFFECTIF DES PRODUITS DE LA FICHE PONDEUSES.
 *
 * (1) `products.categorie_effectif` admet désormais les QUATRE stades (`poussin_ponte`, `poussin_croissance`, `poulette`,
 *     `pondeuse`) en plus des trois catégories des reproducteurs. Valeur PAR DÉFAUT d'après le nom (voir
 *     [StadePondeuse::devinerDepuisLeNom]) : poulette → poulette ; pondeuse / poule de réforme → pondeuse ; poussin en
 *     croissance ; poussin « ponte ». ⚠️ Un produit dont le nom est SANS ambiguïté pondeuse écrase la valeur que la règle de
 *     VOL-1 avait posée d'après le nom (« Poule pondeuse » y devenait « reproducteur ») ; une valeur choisie par un humain
 *     ailleurs (un produit déjà rangé sans rapport avec le nom) n'est jamais touchée : seuls les produits sans catégorie ou
 *     rangés par la règle de VOL-1 sont concernés. Un produit sans règle sûre reste SANS stade (jamais rangé au hasard).
 * (2) Les quatre lignes du barème de l'aviculture (libellés EXACTS du semoir, `FeedRationStandardsSeeder`) existent déjà sur toute
 *     base semée et ne sont PAS touchées ici : si l'une manque, `StadePondeuse::ration()` retombe sur la valeur d'origine
 *     (30 / 60 / 80 / 110 g/j) sans jamais afficher « — ».
 */
return new class extends Migration
{
    public function up(): void
    {
        $aviculture = DB::table('livestock_species')->where('code', 'aviculture')->value('id');

        if ($aviculture !== null) {
            DB::table('products')->where('species_id', $aviculture)->get(['id', 'name', 'categorie_effectif'])
                ->each(function ($produit) {
                    $stade = StadePondeuse::devinerDepuisLeNom($produit->name);
                    if ($stade === null) {
                        return;
                    }
                    $actuelle = $produit->categorie_effectif;
                    $parVol1 = $actuelle !== null && $actuelle === CategorieVolaille::devinerDepuisLeNom($produit->name);
                    if ($actuelle === null || $parVol1) {
                        DB::table('products')->where('id', $produit->id)->update(['categorie_effectif' => $stade]);
                    }
                });
        }
    }

    public function down(): void
    {
        // Les stades posés par défaut ne se retirent pas à l'aveugle (ils peuvent avoir été corrigés à la main) : rien à défaire.
    }
};
