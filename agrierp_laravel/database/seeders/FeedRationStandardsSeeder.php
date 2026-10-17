<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * ⚠️ CORRECTION D'UNE ERREUR PRÉCÉDENTE (ticket 2.7 → révisée au ticket 2.8) :
 * ce fichier avait été réécrit au ticket 2.7 en s'appuyant sur
 * `Fiche_de_rationneent_des_aniamaux.md`, qui semblait indiquer 300 g/j
 * pour "Lapin sevré" et 120 g/j pour "Pondeuse", contre 30 g/j et 110 g/j
 * dans `SEEDER_TEST.md`. En lisant `parametres-elevage.html` au ticket 2.8
 * (`RATIONS_STORE`, le prototype lui-même — hiérarchie des sources n°1,
 * "comportemental" inclus), les valeurs affichées sont bien **30 g/j** et
 * **110 g/j** — identiques à `SEEDER_TEST.md`, PAS à ma correction
 * précédente. `Fiche_de_rationneent_des_aniamaux.md` a une notation
 * décimale incohérente dans sa colonne "Kg" (0,03 / 0,3 / 0,120 mélangés
 * sans convention claire) et décrit un schéma à deux lignées avicoles
 * distinctes que le prototype n'implémente pas réellement (aviculture n'a
 * que 4 stades dans `RATIONS_STORE`, pas 6). Le prototype, comportemental
 * et structurel, l'emporte sur un document de référence à la notation
 * ambiguë (Document 00 §1, hiérarchie des sources). Les valeurs
 * "corrigées" du ticket 2.7 étaient donc elles-mêmes une erreur — revenues
 * ici aux valeurs originales de `SEEDER_TEST.md`, désormais confirmées de
 * façon indépendante par `parametres-elevage.html`. Toutes mes excuses
 * pour cet aller-retour ; le barème ci-dessous est maintenant corroboré
 * par DEUX sources indépendantes concordantes.
 */
/**
 * Ticket 15.36 — glossaire de la fiche lapins (décision client du 14/10/2026) :
 * « Lapin Sevré » devient « Jeune » et « Jeune Lapin (engraissement) » devient
 * « Lapin de Chair ». Les rations (30 / 60 g) ne changent pas. La migration
 * 2026_10_14_000001 fait le même renommage sur une base déjà peuplée ; la fiche
 * retrouve les rations par la clé stable de CategorieRationLapin, ancien OU
 * nouveau libellé.
 */
class FeedRationStandardsSeeder extends Seeder
{
    public function run(): void
    {
        $rations = [
            ['species_code' => 'aviculture', 'stage_label' => 'Poussin ponte (0 à 2 mois)', 'ration_g_per_day' => 30],
            ['species_code' => 'aviculture', 'stage_label' => 'Poussin en croissance (2 à 4 mois)', 'ration_g_per_day' => 60],
            ['species_code' => 'aviculture', 'stage_label' => 'Poulette (4 à 5.5 mois)', 'ration_g_per_day' => 80],
            ['species_code' => 'aviculture', 'stage_label' => 'Pondeuse (6 à 18 mois)', 'ration_g_per_day' => 110],
            ['species_code' => 'cuniculture', 'stage_label' => 'Lapine Mère / Reproducteur', 'ration_g_per_day' => 120],
            ['species_code' => 'cuniculture', 'stage_label' => 'Jeune', 'ration_g_per_day' => 30],
            ['species_code' => 'cuniculture', 'stage_label' => 'Lapin de Chair', 'ration_g_per_day' => 60],
            ['species_code' => 'porciculture', 'stage_label' => 'Porcelet', 'ration_g_per_day' => 300],
            ['species_code' => 'porciculture', 'stage_label' => 'Jeune porc', 'ration_g_per_day' => 600],
            ['species_code' => 'porciculture', 'stage_label' => 'Porc reproducteur', 'ration_g_per_day' => 2000],
        ];

        foreach ($rations as $r) {
            DB::table('feed_ration_standards')->insert([
                'id' => (string) Str::uuid(),
                'species_code' => $r['species_code'],
                'stage_label' => $r['stage_label'],
                'ration_g_per_day' => $r['ration_g_per_day'],
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }
}
