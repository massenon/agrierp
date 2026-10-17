<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Catalogue COMPLET (18 produits, 6 catégories) — repris exactement du
 * tableau `CATALOG` de `catalogue-view.html` (source de vérité n°1),
 * qui est la liste exhaustive réconciliée catalogue↔POS déjà mentionnée
 * dans `SEEDER_TEST.md` §7 comme référence à atteindre. L'extrait de 4
 * produits livré au ticket 2.2 est ici remplacé par ce jeu complet, requis
 * pour démontrer réellement le catalogue au ticket 2.3 (pastilles de
 * catégorie, recherche, grille/liste) sans donnée éparse.
 */
class ProductsSeeder extends Seeder
{
    public function run(): void
    {
        $speciesIds = DB::table('livestock_species')->pluck('id', 'code');

        // 🔴→✅ TICKET 14.36 — CATÉGORIES « Aliments » et « Médicaments ».
        //
        // Le catalogue ne contenait QUE des produits vendables : ni provende ni
        // produit vétérinaire. Or `livestock_daily_entries.feed_product_id`
        // pointe vers `products`, le tableau de bord du prototype alerte sur
        // « Stock aliment lapins bas », et l'autonomie alimentaire se calcule
        // sur un stock d'aliment. Une exploitation ne pouvait donc ni acheter
        // sa provende, ni la voir baisser, ni être alertée d'une rupture.
        //
        // Les deux noms de catégorie sont ceux du filtre de `gestion-stocks.html`
        // (Aliments, Animaux, Matériel, Médicaments, Produits transformés) —
        // jamais inventés.
        $categoryLabels = ['Cuniculture', 'Aviculture', 'Porciculture', 'Maraîchage', 'Transformation', 'Équipements', 'Aliments', 'Médicaments'];
        $categoryIds = [];
        foreach ($categoryLabels as $label) {
            $id = (string) Str::uuid();
            DB::table('product_categories')->insert([
                'id' => $id,
                'label' => $label,
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            $categoryIds[$label] = $id;
        }

        // species_id renseigné uniquement pour les 3 filières d'élevage —
        // Maraîchage/Transformation/Équipements n'ont pas de filière animale.
        $categorySpecies = [
            'Cuniculture' => 'cuniculture',
            'Aviculture' => 'aviculture',
            'Porciculture' => 'porciculture',
        ];

        // ⚠️ L'espèce d'un intrant se déduit du PRODUIT, pas de sa catégorie :
        // « Aliments » couvre les trois filières. Sans ce rattachement, aucune
        // analyse de coût par filière ne serait possible sur l'aliment, qui en
        // est pourtant le premier poste.
        $produitEspece = [
            'ALI-001' => 'aviculture',
            'ALI-002' => 'aviculture',
            'ALI-003' => 'aviculture',
            'ALI-004' => 'cuniculture',
            'ALI-005' => 'porciculture',
        ];

        $products = [
            ['sku' => 'CUN-001', 'name' => 'Lapin vivant', 'cat' => 'Cuniculture', 'stock' => 56, 'threshold' => 15, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 6000, 'max' => 11000],
            ['sku' => 'CUN-002', 'name' => 'Lapereau sevré', 'cat' => 'Cuniculture', 'stock' => 8, 'threshold' => 10, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 1200, 'max' => 1800],
            ['sku' => 'AVI-001', 'name' => 'Poulet goliath (sujet vif)', 'cat' => 'Aviculture', 'stock' => 64, 'threshold' => 15, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 4000, 'max' => 8000],
            ['sku' => 'AVI-002', 'name' => 'Œufs de table (plateau)', 'cat' => 'Aviculture', 'stock' => 118, 'threshold' => 30, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 2000, 'max' => 2500],
            ['sku' => 'AVI-003', 'name' => "Poussin d'un jour", 'cat' => 'Aviculture', 'stock' => 210, 'threshold' => 50, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 500, 'max' => 700],
            ['sku' => 'AVI-004', 'name' => 'Poulet abattu frais', 'cat' => 'Aviculture', 'stock' => 30, 'threshold' => 10, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 4000, 'max' => 6000],
            ['sku' => 'AVI-005', 'name' => 'Poulet fumé', 'cat' => 'Aviculture', 'stock' => 15, 'threshold' => 5, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 4500, 'max' => 5500],
            ['sku' => 'AVI-006', 'name' => 'Poulet braisé', 'cat' => 'Aviculture', 'stock' => 12, 'threshold' => 5, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 4000, 'max' => 6000],
            ['sku' => 'POR-001', 'name' => 'Porc vivant', 'cat' => 'Porciculture', 'stock' => 20, 'threshold' => 5, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 60000, 'max' => 180000],
            ['sku' => 'POR-002', 'name' => 'Porcelet sevré', 'cat' => 'Porciculture', 'stock' => 4, 'threshold' => 5, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 12000, 'max' => 18000],
            ['sku' => 'MAR-001', 'name' => 'Légumes frais (maraîchage)', 'cat' => 'Maraîchage', 'stock' => 45, 'threshold' => 10, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 2500, 'max' => 5000],
            ['sku' => 'MAR-002', 'name' => 'Tomates (panier)', 'cat' => 'Maraîchage', 'stock' => 22, 'threshold' => 5, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 1200, 'max' => 1800],
            ['sku' => 'MAR-003', 'name' => 'Régime de noix de palme', 'cat' => 'Maraîchage', 'stock' => 3, 'threshold' => 1, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 15000, 'max' => 35000],
            ['sku' => 'MAR-004', 'name' => 'Piment frais (sac 1kg)', 'cat' => 'Maraîchage', 'stock' => 32, 'threshold' => 10, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 1000, 'max' => 1400],
            ['sku' => 'TRA-001', 'name' => 'Fumier composté (sac)', 'cat' => 'Transformation', 'stock' => 40, 'threshold' => 10, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 800, 'max' => 1200],
            ['sku' => 'EQP-001', 'name' => 'Cage galvanisée 4 compartiments', 'cat' => 'Équipements', 'stock' => 6, 'threshold' => 2, 'unit' => 'u', 'pricing' => 'quote', 'min' => null, 'max' => null],
            ['sku' => 'EQP-002', 'name' => 'Cage galvanisée 6 compartiments', 'cat' => 'Équipements', 'stock' => 4, 'threshold' => 2, 'unit' => 'u', 'pricing' => 'quote', 'min' => null, 'max' => null],
            ['sku' => 'EQP-003', 'name' => 'Cage galvanisée 8 compartiments', 'cat' => 'Équipements', 'stock' => 2, 'threshold' => 1, 'unit' => 'u', 'pricing' => 'quote', 'min' => null, 'max' => null],

            // --- INTRANTS (ticket 14.36) -------------------------------------
            //
            // ⚠️ COMPTÉS EN SACS DE 25 KG, jamais en kilos. C'est l'unité du
            // prototype : `gestion-stocks.html` liste « ALI-001 — Aliment ponte
            // 25kg » avec un stock théorique de 45 (sacs) et un mouvement
            // d'achat de +20. C'est aussi l'unité d'achat réelle, et celle que
            // porte `feed_types.standard_bag_weight_kg`.
            //
            // Prix du sac = `feed_types.price_per_kg` × 25, plutôt qu'un montant
            // recopié du HTML : le référentiel de rationnement reste le point de
            // vérité du coût de l'aliment.
            ['sku' => 'ALI-001', 'name' => 'Aliment ponte 25kg', 'cat' => 'Aliments', 'stock' => 45, 'threshold' => 15, 'unit' => 'sac', 'pricing' => 'fourchette', 'min' => 6500, 'max' => 7500],
            ['sku' => 'ALI-002', 'name' => 'Aliment croissance (poulette) 25kg', 'cat' => 'Aliments', 'stock' => 20, 'threshold' => 10, 'unit' => 'sac', 'pricing' => 'fourchette', 'min' => 7000, 'max' => 8000],
            ['sku' => 'ALI-003', 'name' => 'Aliment démarrage (poussin) 25kg', 'cat' => 'Aliments', 'stock' => 12, 'threshold' => 6, 'unit' => 'sac', 'pricing' => 'fourchette', 'min' => 7500, 'max' => 8500],
            ['sku' => 'ALI-004', 'name' => 'Aliment lapins reproducteur 25kg', 'cat' => 'Aliments', 'stock' => 18, 'threshold' => 8, 'unit' => 'sac', 'pricing' => 'fourchette', 'min' => 7250, 'max' => 8250],
            ['sku' => 'ALI-005', 'name' => 'Aliment porcelet / démarrage 25kg', 'cat' => 'Aliments', 'stock' => 14, 'threshold' => 6, 'unit' => 'sac', 'pricing' => 'fourchette', 'min' => 8000, 'max' => 9000],

            // « Anti-coccidien » est le produit vétérinaire nommé par le
            // prototype (MED-001). Les trois autres couvrent les traitements
            // réellement cités par les fiches d'élevage.
            ['sku' => 'MED-001', 'name' => 'Anti-coccidien (flacon)', 'cat' => 'Médicaments', 'stock' => 4, 'threshold' => 4, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 4500, 'max' => 6000],
            ['sku' => 'MED-002', 'name' => 'Antibiotique polyvalent (flacon)', 'cat' => 'Médicaments', 'stock' => 6, 'threshold' => 4, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 5000, 'max' => 7000],
            ['sku' => 'MED-003', 'name' => 'Vitamines AD3E (sachet)', 'cat' => 'Médicaments', 'stock' => 10, 'threshold' => 5, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 1500, 'max' => 2500],
            ['sku' => 'MED-004', 'name' => 'Déparasitant (Ivermectine)', 'cat' => 'Médicaments', 'stock' => 5, 'threshold' => 3, 'unit' => 'u', 'pricing' => 'fourchette', 'min' => 3500, 'max' => 5000],
        ];

        foreach ($products as $p) {
            DB::table('products')->insert([
                'id' => (string) Str::uuid(),
                'sku' => $p['sku'],
                'name' => $p['name'],
                'category_id' => $categoryIds[$p['cat']],
                'unit' => $p['unit'],
                'pricing_mode' => $p['pricing'],
                'price_min' => $p['min'],
                'price_max' => $p['max'],
                'tva_rate' => 0,
                'stock_qty' => $p['stock'],
                'alert_threshold' => $p['threshold'],
                'species_id' => isset($produitEspece[$p['sku']])
                    ? ($speciesIds[$produitEspece[$p['sku']]] ?? null)
                    : (isset($categorySpecies[$p['cat']]) ? ($speciesIds[$categorySpecies[$p['cat']]] ?? null) : null),
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }
}
