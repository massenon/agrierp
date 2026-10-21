<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FicheLapins;
use App\Models\FeedRationStandard;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Support\CategorieRationLapin;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 15.36 (Sprint 15) — GLOSSAIRE DE LA FICHE LAPINS (web).
 *
 * Décision client VALIDÉE le 14/10/2026 : tableau de rationnement
 * « Catégorie » = Reproducteur 120 g / Jeune 30 g (ex-« Sevré ») / Lapin de
 * Chair 60 g (ex-« Jeune (engraissement) ») ; « Sevrés » devient « Jeunes »
 * (tableau mensuel ET champ de l'Effectif Final du Jour).
 *
 * LE PIÈGE QUE CE FICHIER VERROUILLE : le rapprochement des rations se faisait
 * par SOUS-CHAÎNE du libellé (`str_contains(..., 'Sevré')`) avec des valeurs
 * de secours en dur (30 / 60 / 120). Renommer le libellé aurait fait retomber
 * EN SILENCE sur ces constantes — aucun message d'erreur, un chiffre juste
 * tant que le barème n'est pas modifié, faux ensuite. Les tests utilisent donc
 * des rations qui DIFFÈRENT des valeurs de secours (150 / 40 / 70) : si la
 * ration affichée est 120/30/60, le barème a été ignoré.
 *
 * 🔁 DÉCISION CLIENT DU 17/10/2026 — glossaire Reproducteur / Jeune / Sous-mères : « Jeune » (30 g) devient
 * « Sous-mères » (clé `sous_meres`) et « Lapin de Chair » (60 g) devient « Jeune » (clé `chair`). Migration
 * 2026_10_17_000001, testée en fin de fichier.
 *
 * 🔁 TICKET 15.41 — RÉÉCRIT là où il verrouillait la saisie MANUELLE des effectifs Jeune / Lapin de Chair
 * (`catEffSevre` / `catEffJeune`) : ces effectifs sont désormais CALCULÉS depuis l'effectif de départ. La
 * couverture est inchangée (rations 150 / 40 / 70, total 4 400 g, clé stable, anciens et nouveaux libellés,
 * secours, colonnes de synchronisation) ; seule la façon de fournir les effectifs 10 / 20 / 30 a changé.
 */
class GlossaireFicheLapinsTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $lot;

    protected function setUp(): void
    {
        parent::setUp();

        // Ticket S2 : l'enregistrement exige désormais `authorize()` ; l'écran est utilisé par un compte animalier.
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $compte = \App\Models\User::create([
            'name' => 'Animalier', 'username' => 'animalier-test',
            'email' => 'animalier-test@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $compte->assignRole('animalier');
        $this->actingAs($compte);

        $species = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);

        $this->lot = LivestockLot::create([
            'code' => 'LOT-LAP-GLOSS', 'species_id' => $species->id, 'stage' => 'engraissement',
            'initial_quantity' => 60, 'current_quantity' => 60, 'created_date' => '2026-06-01',
            'status' => 'actif', 'is_active' => true,
        ]);
    }

    /** Barème de la cuniculture ; valeurs VOLONTAIREMENT différentes des secours par défaut. */
    private function bareme(string $repro, string $jeune, string $chair, array $valeurs = [150, 40, 70]): void
    {
        DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->delete();
        foreach ([[$repro, $valeurs[0]], [$jeune, $valeurs[1]], [$chair, $valeurs[2]]] as [$libelle, $g]) {
            FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => $libelle, 'ration_g_per_day' => $g]);
        }
    }

    private function calcul(): array
    {
        // Ticket 15.41 : les effectifs ne sont plus saisis, ils sont CALCULÉS depuis l'effectif de départ
        // (effectif au début du jour, somme = 60 = effectif de la bande).
        $c = Livewire::test(FicheLapins::class)
            ->set('selectedDate', '2026-07-10')
            ->set('departRepro', 10)
            ->set('departSevre', 20)    // emplacement de synchro : = « Sous-mères » (17/10/2026)
            ->set('departJeune', 30);   // emplacement de synchro : = « Jeune » (17/10/2026)

        return $c->instance()->provendeCalculation;
    }

    // ----------------------------------------------------------- affichage

    /** 🔁 Décision client du 17/10/2026 : Reproducteur / Jeune / Sous-mères. */
    public function test_le_tableau_de_rationnement_porte_les_trois_categories_du_glossaire(): void
    {
        $this->bareme('Reproducteur', 'Sous-mères', 'Jeune', [120, 30, 60]);

        Livewire::test(FicheLapins::class)
            ->assertSeeHtml('<th class="px-md py-xs text-left">Catégorie</th>')
            ->assertSeeHtml('font-bold text-brand-forest">Reproducteur</td>')
            ->assertSeeHtml('font-bold text-brand-forest">Jeune</td>')
            ->assertSeeHtml('font-bold text-brand-forest">Sous-mères</td>')
            ->assertDontSeeHtml('font-bold text-brand-forest">Lapin de Chair</td>')
            ->assertSee('120 g/j')
            ->assertSee('30 g/j')
            ->assertSee('60 g/j');
    }

    public function test_les_anciens_libelles_ne_sont_plus_affiches_sur_la_fiche(): void
    {
        $html = Livewire::test(FicheLapins::class)->html();

        $this->assertStringNotContainsString('Sevré', $html);
        $this->assertStringNotContainsString('Jeune (engraissement)', $html);
    }

    public function test_le_champ_de_l_effectif_final_et_le_tableau_mensuel_disent_jeunes(): void
    {
        $html = Livewire::test(FicheLapins::class)->html();

        // Champ saisi de l'Effectif Final du Jour.
        $this->assertStringContainsString('uppercase mb-xs">Jeunes</label>', $html);
        // En-tête du tableau mensuel — reste distinct de « S/Mères ».
        $this->assertStringContainsString('text-outline font-bold">Jeunes</th>', $html);
        $this->assertStringContainsString('text-outline font-bold">S/Mères</th>', $html);
        $this->assertStringContainsString('uppercase mb-xs">S/Mères</label>', $html);
    }

    public function test_les_autres_especes_restent_inchangees(): void
    {
        $porcs = file_get_contents(base_path('resources/views/livewire/elevage/fiche-porcs.blade.php'));
        $classePorcs = file_get_contents(app_path('Livewire/Elevage/FichePorcs.php'));

        // 🔁 TICKET 15.42 : la fiche porcs a ses libellés de la maquette (« Porcelet » / « Porc Marchand » / « Reproducteur ») et
        // sa PROPRE clé stable ; le glossaire des lapins n'y entre toujours pas.
        $this->assertStringContainsString('Porc Marchand', $porcs);
        $this->assertStringNotContainsString('Lapin de Chair', $porcs);
        $this->assertStringContainsString('CategorieRationPorc', $classePorcs);
        $this->assertStringNotContainsString('str_contains($r->stage_label', $classePorcs, 'plus de rapprochement par fragment de libellé');
        $this->assertStringNotContainsString('CategorieRationLapin', $classePorcs);
    }

    public function test_le_rapport_transversal_multi_especes_garde_son_libelle_generique(): void
    {
        // Décision signalée au rapport 15.36 : la synthèse mêle les espèces
        // (porcs, volailles) ; « Jeunes » y serait faux. L'en-tête CSV ne change donc pas.
        $source = file_get_contents(app_path('Livewire/Rapports/ElevageSynth.php'));
        $this->assertStringContainsString('Sous Mères,Sevrés,Morts', $source);
        $this->assertStringContainsString('Sevrés', file_get_contents(base_path('resources/views/exports/elevage-synth.blade.php')));
    }

    public function test_le_motif_de_la_fiche_sujet_utilise_le_glossaire(): void
    {
        $vue = file_get_contents(base_path('resources/views/livewire/elevage/animal-details.blade.php'));

        $this->assertStringNotContainsString('Reproducteur / Sevré / Jeune', $vue);
        $this->assertStringNotContainsString('Lapin de Chair', $vue);
        $this->assertStringContainsString('Reproducteur / Jeune / Sous-mères', $vue);
    }

    // ------------------------------ le piège : renommer ne change pas la ration

    public function test_les_rations_sont_identiques_quel_que_soit_le_jeu_de_libelles(): void
    {
        // Jeux complets d'un barème (petite catégorie, puis catégorie d'engraissement). Le jeu du 14/10/2026
        // (« Jeune » = 30 g, « Lapin de Chair » = 60 g) n'existe plus en base : la migration 2026_10_17_000001
        // le convertit (testée plus bas).
        $jeux = [
            'anciens (seeder d\'avant)' => ['Lapine Mère / Reproducteur', 'Lapin Sevré', 'Jeune Lapin (engraissement)'],
            'intermédiaires (tests 14.11)' => ['Reproducteur', 'Sevré', 'Jeune (engraissement)'],
            'glossaire du 17/10/2026' => ['Reproducteur', 'Sous-mères', 'Jeune'],
            'glossaire en casse libre' => ['REPRODUCTEUR', 'sous-mères', 'jeune'],
        ];

        foreach ($jeux as $nom => [$r, $sm, $j]) {
            $this->bareme($r, $sm, $j);
            $calcul = $this->calcul();

            $this->assertSame(150, $calcul['repro']['ration'], "Reproducteur — jeu $nom");
            $this->assertSame(40, $calcul['sous_meres']['ration'], "Sous-mères — jeu $nom (30 = barème ignoré)");
            $this->assertSame(70, $calcul['chair']['ration'], "Jeune — jeu $nom (60 = barème ignoré)");
            // Mesure indépendante : 10×150 + 20×40 + 30×70.
            $this->assertSame(10 * 150 + 20 * 40 + 30 * 70, $calcul['total_g'], "Total — jeu $nom");
        }
    }

    public function test_renommer_le_libelle_en_base_ne_change_pas_la_ration_affichee(): void
    {
        $this->bareme('Lapine Mère / Reproducteur', 'Lapin Sevré', 'Jeune Lapin (engraissement)');
        $avant = $this->calcul();

        FeedRationStandard::where('stage_label', 'Lapin Sevré')->update(['stage_label' => 'Sous-mères']);
        FeedRationStandard::where('stage_label', 'Jeune Lapin (engraissement)')->update(['stage_label' => 'Jeune']);
        $apres = $this->calcul();

        $this->assertSame($avant, $apres);
        $this->assertSame(40, $apres['sous_meres']['ration']);
        $this->assertSame(70, $apres['chair']['ration']);
    }

    public function test_les_valeurs_de_secours_restent_quand_le_bareme_est_vide(): void
    {
        DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->delete();
        $calcul = $this->calcul();

        $this->assertSame(120, $calcul['repro']['ration']);
        $this->assertSame(30, $calcul['sous_meres']['ration']);
        $this->assertSame(60, $calcul['chair']['ration']);
    }

    public function test_une_categorie_absente_du_bareme_retombe_sur_son_secours_sans_affecter_les_autres(): void
    {
        DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->delete();
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Sous-mères', 'ration_g_per_day' => 45]);
        $calcul = $this->calcul();

        $this->assertSame(45, $calcul['sous_meres']['ration']);
        $this->assertSame(120, $calcul['repro']['ration']);
        $this->assertSame(60, $calcul['chair']['ration']);
    }

    public function test_la_cle_stable_classe_anciens_et_nouveaux_libelles_sans_confondre_chair_et_jeune(): void
    {
        $attendu = [
            'Reproducteur' => 'reproducteur',
            'Lapine Mère / Reproducteur' => 'reproducteur',
            'Sous-mères' => 'sous_meres',
            'Sous mères' => 'sous_meres',
            'Sevré' => 'sous_meres',
            'Lapin Sevré' => 'sous_meres',
            'Lapin Sevre' => 'sous_meres',
            'Jeune' => 'chair',                          // 17/10/2026 : « Jeune » est la catégorie à 60 g/j
            ' jeune ' => 'chair',
            'Lapin de Chair' => 'chair',
            'Jeune Lapin (engraissement)' => 'chair',
            'Jeune (engraissement)' => 'chair',
            'Porcelet' => null,
            '' => null,
        ];

        foreach ($attendu as $libelle => $cle) {
            $this->assertSame($cle, CategorieRationLapin::cle((string) $libelle), "« $libelle »");
        }
    }

    // ------------------------------------------- contrat de synchronisation

    public function test_les_colonnes_de_synchronisation_sont_intactes(): void
    {
        foreach (['cat_eff_sevre', 'cat_eff_jeune', 'cat_eff_repro', 'effectif_sevres', 'effectif_smeres', 'effectif_m', 'effectif_f'] as $colonne) {
            $this->assertTrue(Schema::hasColumn('livestock_daily_entries', $colonne), $colonne);
        }
        $this->assertFalse(Schema::hasColumn('livestock_daily_entries', 'effectif_jeunes'));
        $this->assertFalse(Schema::hasColumn('feed_ration_standards', 'category_key'));
    }

    public function test_la_saisie_persiste_toujours_dans_les_colonnes_historiques(): void
    {
        $this->bareme('Reproducteur', 'Jeune', 'Lapin de Chair');

        Livewire::test(FicheLapins::class)
            ->set('selectedDate', '2026-07-10')
            ->set('effectifSevres', 17)
            ->set('departRepro', 10)
            ->set('departSevre', 20)
            ->set('departJeune', 30)
            ->call('saveDay');

        $e = LivestockDailyEntry::first();
        $this->assertNotNull($e);
        $this->assertSame(17, (int) $e->effectif_sevres);
        // Ticket 15.41 : `cat_eff_*` sont dérivés du départ par la chaîne, dans les MÊMES colonnes historiques.
        $this->assertSame(10, (int) $e->cat_eff_repro);
        $this->assertSame(20, (int) $e->cat_eff_sevre);
        $this->assertSame(30, (int) $e->cat_eff_jeune);
    }

    // ------------------------------------------ migration de données + seeder

    private function migration(): object
    {
        return require database_path('migrations/2026_10_14_000001_renomme_libelles_bareme_lapins.php');
    }

    public function test_la_migration_renomme_les_anciens_libelles_et_garde_les_valeurs(): void
    {
        $this->bareme('Lapine Mère / Reproducteur', 'Lapin Sevré', 'Jeune Lapin (engraissement)');
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Jeune porc', 'ration_g_per_day' => 600]);

        $this->migration()->up();

        $lib = DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->orderBy('stage_label')->pluck('ration_g_per_day', 'stage_label')->all();
        $this->assertEquals(['Jeune' => 40, 'Lapin de Chair' => 70, 'Lapine Mère / Reproducteur' => 150], $lib);
        $this->assertSame(600, (int) DB::table('feed_ration_standards')->where('stage_label', 'Jeune porc')->value('ration_g_per_day'));
    }

    public function test_la_migration_est_idempotente_et_ne_cree_pas_de_doublon(): void
    {
        $this->bareme('Lapine Mère / Reproducteur', 'Lapin Sevré', 'Jeune Lapin (engraissement)');
        $m = $this->migration();

        $m->up();
        $apres1 = DB::table('feed_ration_standards')->orderBy('stage_label')->get(['stage_label', 'ration_g_per_day'])->toArray();
        $m->up();
        $apres2 = DB::table('feed_ration_standards')->orderBy('stage_label')->get(['stage_label', 'ration_g_per_day'])->toArray();

        $this->assertEquals($apres1, $apres2);
        $this->assertSame(3, DB::table('feed_ration_standards')->count());
    }

    public function test_la_migration_ne_renomme_pas_si_le_nouveau_libelle_existe_deja(): void
    {
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Lapin Sevré', 'ration_g_per_day' => 31]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Jeune', 'ration_g_per_day' => 32]);

        $this->migration()->up();

        $this->assertSame(2, DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->count());
        $this->assertSame(31, (int) DB::table('feed_ration_standards')->where('stage_label', 'Lapin Sevré')->value('ration_g_per_day'));
    }

    public function test_la_migration_ne_touche_que_la_cuniculture(): void
    {
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Lapin Sevré', 'ration_g_per_day' => 5]);

        $this->migration()->up();

        $this->assertSame(1, DB::table('feed_ration_standards')->where('species_code', 'porciculture')->where('stage_label', 'Lapin Sevré')->count());
    }

    public function test_le_seeder_pose_les_nouveaux_libelles(): void
    {
        $this->seed(\Database\Seeders\FeedRationStandardsSeeder::class);

        $cuni = DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->pluck('ration_g_per_day', 'stage_label')->all();

        $this->assertEquals(30, $cuni['Sous-mères']);
        $this->assertEquals(60, $cuni['Jeune']);
        $this->assertArrayNotHasKey('Lapin de Chair', $cuni);
        $this->assertArrayNotHasKey('Lapin Sevré', $cuni);
        $this->assertArrayNotHasKey('Jeune Lapin (engraissement)', $cuni);
        $this->assertSame(1, DB::table('feed_ration_standards')->where('species_code', 'porciculture')->where('stage_label', 'Jeune porc')->count());
    }

    // ------------------------------------------------ Ticket 15.37 — réserves de l'audit indépendant

    /**
     * L06 — « jeune » est une égalité STRICTE (après minuscules et suppression des accents), jamais une
     * sous-chaîne : « Jeunes » (pluriel du tableau mensuel), « Jeune porc » (autre espèce) ne relèvent d'aucune
     * catégorie. 🔁 17/10/2026 : « Jeune » désigne la catégorie à 60 g/j (clé `chair`).
     */
    public function test_jeune_est_une_egalite_stricte_jamais_une_sous_chaine(): void
    {
        $this->assertSame('chair', CategorieRationLapin::cle('Jeune Lapin (engraissement)'));
        $this->assertSame('chair', CategorieRationLapin::cle('Jeune (engraissement)'));
        $this->assertNull(CategorieRationLapin::cle('Jeunes'));
        $this->assertNull(CategorieRationLapin::cle('Jeune porc'));
        $this->assertNull(CategorieRationLapin::cle('Jeune.'));
        $this->assertNull(CategorieRationLapin::cle('Jeune lapin'));

        foreach (['Jeune', 'jeune', 'JEUNE', ' Jeune ', 'Jéune', 'JÉUNE'] as $libelle) {
            $this->assertSame('chair', CategorieRationLapin::cle($libelle), "« $libelle »");
        }
    }

    /** L06 — une ligne « Jeunes » ou « Jeune porc » du barème ne vole pas la ration Jeune. */
    public function test_une_ligne_jeunes_ou_jeune_porc_du_bareme_ne_vole_pas_la_ration_jeune(): void
    {
        DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->delete();
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Jeunes', 'ration_g_per_day' => 999]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Jeune porc', 'ration_g_per_day' => 888]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Jeune', 'ration_g_per_day' => 45]);

        $this->assertSame(45, $this->calcul()['chair']['ration']);

        FeedRationStandard::where('stage_label', 'Jeune')->delete();
        $this->assertSame(60, $this->calcul()['chair']['ration'], 'sans ligne « Jeune » : le secours, pas « Jeunes »');
    }

    /**
     * Parité Unicode (ticket 15.37, côté Laravel : on DOCUMENTE seulement). `trim()` PHP ne retire que les
     * espaces ASCII : un libellé entouré d'une espace Unicode n'a donc aucune clé ici (ration de secours).
     */
    public function test_comportement_actuel_une_espace_unicode_autour_de_jeune_ne_donne_aucune_cle(): void
    {
        $this->assertNull(CategorieRationLapin::cle("\u{00A0}Jeune"), 'espace insécable avant');
        $this->assertNull(CategorieRationLapin::cle("Jeune\u{00A0}"), 'espace insécable après');
        $this->assertNull(CategorieRationLapin::cle("\u{2003}Jeune"), 'cadratin avant');
        $this->assertNull(CategorieRationLapin::cle("Jeune\u{2003}"), 'cadratin après');
        // Témoin : l'espace ASCII, elle, est retirée.
        $this->assertSame('chair', CategorieRationLapin::cle(" \tJeune\n"));
    }

    /** L08 — `down()` rétablit exactement les anciens libellés, rations intactes. */
    public function test_la_migration_down_retablit_les_anciens_libelles_et_garde_les_valeurs(): void
    {
        $this->bareme('Reproducteur', 'Jeune', 'Lapin de Chair');
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Jeune', 'ration_g_per_day' => 600]);

        $this->migration()->down();

        $lib = DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->orderBy('stage_label')->pluck('ration_g_per_day', 'stage_label')->all();
        $this->assertEquals(['Jeune Lapin (engraissement)' => 70, 'Lapin Sevré' => 40, 'Reproducteur' => 150], $lib);
        // Autre espèce : jamais touchée, même si elle porte un libellé identique.
        $this->assertSame(1, DB::table('feed_ration_standards')->where('species_code', 'porciculture')->where('stage_label', 'Jeune')->count());
    }

    /** L08 — aller-retour : up() puis down() puis up() ne perd ni ne duplique aucune ligne. */
    public function test_la_migration_aller_retour_est_sans_perte(): void
    {
        $this->bareme('Reproducteur', 'Lapin Sevré', 'Jeune Lapin (engraissement)');
        $m = $this->migration();
        $avant = DB::table('feed_ration_standards')->orderBy('stage_label')->pluck('ration_g_per_day', 'stage_label')->all();

        $m->up();
        $m->down();

        $this->assertEquals($avant, DB::table('feed_ration_standards')->orderBy('stage_label')->pluck('ration_g_per_day', 'stage_label')->all());
    }

    /** L08 — `down()` ne renomme pas si l'ancien libellé existe déjà (même garde que `up()`). */
    public function test_la_migration_down_ne_renomme_pas_si_l_ancien_libelle_existe_deja(): void
    {
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Jeune', 'ration_g_per_day' => 31]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Lapin Sevré', 'ration_g_per_day' => 32]);

        $this->migration()->down();

        $this->assertSame(31, (int) DB::table('feed_ration_standards')->where('stage_label', 'Jeune')->value('ration_g_per_day'));
        $this->assertSame(2, DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->count());
    }

    /**
     * L09 — `updated_at` AVANCE sur les lignes renommées SEULEMENT : le poste tire le référentiel
     * complet, mais toute logique « modifié depuis » doit voir les seules lignes touchées. Les lignes non
     * renommées (Reproducteur, autre espèce) gardent leur horodatage.
     */
    public function test_la_migration_avance_updated_at_des_seules_lignes_renommees(): void
    {
        $this->bareme('Reproducteur', 'Lapin Sevré', 'Jeune Lapin (engraissement)');
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Lapin Sevré', 'ration_g_per_day' => 5]);
        DB::table('feed_ration_standards')->update(['updated_at' => '2026-01-01 08:00:00']);

        \Carbon\Carbon::setTestNow('2026-10-14 12:00:00');
        try {
            $this->migration()->up();
        } finally {
            \Carbon\Carbon::setTestNow();
        }

        $horodatage = fn (string $espece, string $libelle) => (string) DB::table('feed_ration_standards')
            ->where('species_code', $espece)->where('stage_label', $libelle)->value('updated_at');

        $this->assertSame('2026-10-14 12:00:00', $horodatage('cuniculture', 'Jeune'));
        $this->assertSame('2026-10-14 12:00:00', $horodatage('cuniculture', 'Lapin de Chair'));
        $this->assertSame('2026-01-01 08:00:00', $horodatage('cuniculture', 'Reproducteur'), 'ligne non renommée : horodatage intact');
        $this->assertSame('2026-01-01 08:00:00', $horodatage('porciculture', 'Lapin Sevré'), 'autre espèce : horodatage intact');
    }

    /** L09 — même chose pour `down()`. */
    public function test_la_migration_down_avance_aussi_updated_at_des_seules_lignes_renommees(): void
    {
        $this->bareme('Reproducteur', 'Jeune', 'Lapin de Chair');
        DB::table('feed_ration_standards')->update(['updated_at' => '2026-01-01 08:00:00']);

        \Carbon\Carbon::setTestNow('2026-10-14 12:00:00');
        try {
            $this->migration()->down();
        } finally {
            \Carbon\Carbon::setTestNow();
        }

        $horodatage = fn (string $libelle) => (string) DB::table('feed_ration_standards')
            ->where('species_code', 'cuniculture')->where('stage_label', $libelle)->value('updated_at');

        $this->assertSame('2026-10-14 12:00:00', $horodatage('Lapin Sevré'));
        $this->assertSame('2026-10-14 12:00:00', $horodatage('Jeune Lapin (engraissement)'));
        $this->assertSame('2026-01-01 08:00:00', $horodatage('Reproducteur'));
    }

    // ------------------------------------------- migration du 17/10/2026 (Reproducteur / Jeune / Sous-mères)

    private function migration17(): object
    {
        return require database_path('migrations/2026_10_17_000001_glossaire_lapins_sous_meres.php');
    }

    /** L'ORDRE compte : « Jeune » (30 g) devient « Sous-mères » AVANT que « Lapin de Chair » (60 g) devienne « Jeune ». */
    public function test_la_migration_du_17_10_renomme_dans_le_bon_ordre_et_garde_les_rations(): void
    {
        $this->bareme('Reproducteur', 'Jeune', 'Lapin de Chair', [120, 30, 60]);

        $this->migration17()->up();

        $cuni = DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->pluck('ration_g_per_day', 'stage_label')->all();
        $this->assertEquals(['Reproducteur' => 120, 'Sous-mères' => 30, 'Jeune' => 60], $cuni);
        $this->assertSame(30, $this->calcul()['sous_meres']['ration']);
        $this->assertSame(60, $this->calcul()['chair']['ration']);
    }

    public function test_la_migration_du_17_10_est_idempotente_et_reversible(): void
    {
        $this->bareme('Reproducteur', 'Jeune', 'Lapin de Chair', [120, 30, 60]);

        $this->migration17()->up();
        $this->migration17()->up();
        $this->assertSame(3, DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->count());
        $this->assertSame(30, (int) DB::table('feed_ration_standards')->where('stage_label', 'Sous-mères')->value('ration_g_per_day'));

        $this->migration17()->down();
        $cuni = DB::table('feed_ration_standards')->where('species_code', 'cuniculture')->pluck('ration_g_per_day', 'stage_label')->all();
        $this->assertEquals(['Reproducteur' => 120, 'Jeune' => 30, 'Lapin de Chair' => 60], $cuni);
    }
}
