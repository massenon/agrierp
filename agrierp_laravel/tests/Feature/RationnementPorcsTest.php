<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FichePorcs;
use App\Models\FeedRationStandard;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Support\CategorieRationPorc;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Features\SupportTesting\Testable;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * Ticket 14.12 (Sprint 14), RÉÉCRIT au ticket 15.42 — Rationnement Porcs relié aux Morts/Dons.
 *
 * Même défaut et même correction que `FicheLapins` (ticket 14.11), avec une nomenclature de catégories différente
 * (Porcelet / Porc Marchand / Reproducteur). Les tests sont volontairement écrits sur les valeurs PROPRES aux porcs
 * plutôt que recopiés : une correction appliquée par analogie sans vérification est exactement ce que ce projet
 * a déjà payé cher.
 *
 * 🔁 TICKET 15.42 — les effectifs de catégorie ne sont plus des SAISIES (`catEffRepro` / `catEffPorcelet` /
 * `catEffJeune` n'existent plus) : ils sont CALCULÉS depuis un effectif de départ (D4) et les mouvements par
 * catégorie. Chaque test de 14.12 est réécrit pour la même garantie, sans en perdre une :
 *   persistés + rechargés · continuité d'un jour à l'autre (avant : « reprise du dernier jour », désormais la chaîne) ·
 *   seules les pertes Reproducteur diminuent la ligne Reproducteur · la ration prend l'effectif calculé ·
 *   sans historique (avant : saisie manuelle, désormais « — » et départ à saisir) · jamais négatif ·
 *   l'enregistrement persiste la valeur calculée.
 * Et le piège de rapprochement par FRAGMENT de libellé (rations de secours en dur) est verrouillé, comme pour les
 * lapins (`GlossaireFicheLapinsTest`) : clé stable `CategorieRationPorc`.
 *
 * Départ R8 / P24 / M28 (total 60), rations 2 000 / 300 / 600 g/j.
 */
class RationnementPorcsTest extends TestCase
{
    use RefreshDatabase;

    private LivestockLot $lot;

    protected function setUp(): void
    {
        parent::setUp();

        $species = LivestockSpecies::create(['code' => 'porciculture', 'label' => 'Porcs', 'is_enabled' => true]);

        $this->lot = LivestockLot::create([
            'code' => 'BANDE-POR-CROISS-P1',
            'species_id' => $species->id,
            'stage' => 'croissance',
            'initial_quantity' => 60,
            'current_quantity' => 60,
            'created_date' => '2026-06-01',
            'status' => 'actif',
            'is_active' => true,
        ]);

        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Porcelet', 'ration_g_per_day' => 300]);
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Jeune marchand', 'ration_g_per_day' => 600]);
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Porc reproducteur', 'ration_g_per_day' => 2000]);
    }

    private function jour(string $date, array $attributs = []): LivestockDailyEntry
    {
        return LivestockDailyEntry::create(array_merge([
            'lot_id' => $this->lot->id,
            'entry_date' => $date,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'effectif_final' => 60,
        ], $attributs));
    }

    /** Enregistre le départ R8 / P24 / M28 au jour donné. */
    private function departer(string $date, array $mouvements = []): Testable
    {
        $c = Livewire::test(FichePorcs::class)
            ->set('selectedDate', $date)
            ->set('departRepro', 8)->set('departSevre', 24)->set('departJeune', 28);
        foreach ($mouvements as $champ => $valeur) {
            $c->set($champ, $valeur);
        }

        return $c->call('saveDay');
    }

    private function affiche(Testable $c, string $id): string
    {
        $this->assertSame(1, preg_match('/<input\b[^>]*\bid="'.preg_quote($id, '/').'"[^>]*>/', $c->html(), $m), "champ #{$id} introuvable");
        $this->assertSame(1, preg_match('/\bvalue="([^"]*)"/', $m[0], $v), "champ #{$id} sans value");

        return $v[1];
    }

    /** @return array{string, string, string} Reproducteur / Porcelet / Porc Marchand tels qu'affichés */
    private function ecran(Testable $c): array
    {
        return [$this->affiche($c, 'cat-eff-repro'), $this->affiche($c, 'cat-eff-porcelet'), $this->affiche($c, 'cat-eff-jeune')];
    }

    public function test_category_headcounts_and_movements_are_persisted_and_reloaded(): void
    {
        $this->departer('2026-07-10', ['mortRepro' => 1, 'mortPorcelet' => 2, 'donMarchand' => 3, 'ne' => 4]);

        $entry = LivestockDailyEntry::where('entry_date', '2026-07-10')->firstOrFail();

        $this->assertEquals(7, $entry->cat_eff_repro);     // 8 − 1
        $this->assertEquals(26, $entry->cat_eff_sevre);    // emplacement générique <- Porcelet : 24 + 4 − 2
        $this->assertEquals(25, $entry->cat_eff_jeune);    // 28 − 3
        $this->assertEquals([8, 24, 28], [$entry->cat_depart_repro, $entry->cat_depart_sevre, $entry->cat_depart_jeune]);

        // Rechargement par une NOUVELLE session : mouvements ET effectifs relus de la base.
        $component = Livewire::test(FichePorcs::class)
            ->call('loadDay', '2026-07-10')
            ->assertSet('mortRepro', 1)
            ->assertSet('mortPorcelet', 2)
            ->assertSet('donMarchand', 3)
            ->assertSet('ne', 4);

        $this->assertSame(['7', '26', '25'], $this->ecran($component));
    }

    /** Remplace « un jour non saisi reprend les effectifs du dernier jour connu » : la chaîne les porte. */
    public function test_an_unsaved_day_carries_over_the_previous_values(): void
    {
        $this->departer('2026-07-10');

        $component = Livewire::test(FichePorcs::class)->call('loadDay', '2026-07-11');

        $this->assertSame(['8', '24', '28'], $this->ecran($component));
        $component->assertSet('mortRepro', 0)->assertSet('donMarchand', 0);
    }

    /** Les morts Marchand et Porcelet ne doivent pas toucher la ligne Reproducteur. */
    public function test_only_breeder_losses_reduce_the_breeder_line(): void
    {
        $this->departer('2026-07-10');

        $component = Livewire::test(FichePorcs::class)
            ->call('loadDay', '2026-07-11')
            ->set('mortRepro', 1)
            ->set('mortMarchand', 4)      // autre catégorie
            ->set('mortPorcelet', 3)      // autre catégorie
            ->set('donRepro', 1);

        // Reproducteur : 8 − 1 mort − 1 don = 6 ; chaque autre catégorie ne perd que ses propres morts.
        $this->assertSame(['6', '21', '24'], $this->ecran($component));
        $this->assertEquals(6, $component->instance()->categoriesJour['repro']);
    }

    public function test_the_ration_uses_the_computed_breeder_headcount(): void
    {
        $this->departer('2026-07-10');

        $component = Livewire::test(FichePorcs::class)
            ->call('loadDay', '2026-07-11')
            ->set('mortRepro', 2);

        // 6 reproducteurs × 2 000 g = 12 000 g
        $this->assertEquals(6, $component->instance()->categoriesJour['repro']);
        $this->assertEquals(12_000, $component->instance()->provendeCalculation['repro']['total_g']);
        // 24 × 300 + 28 × 600 + 12 000 = 7 200 + 16 800 + 12 000
        $this->assertEquals(36_000, $component->instance()->provendeCalculation['total_g']);
    }

    /** Remplace « sans historique la ligne reste manuelle » : sans départ, « — » (jamais 0) et départ à saisir. */
    public function test_without_history_the_lines_are_unknown_and_the_start_is_asked(): void
    {
        $component = Livewire::test(FichePorcs::class)->set('selectedDate', '2026-07-10');

        $this->assertNull($component->instance()->categoriesJour['repro']);
        $this->assertSame(['—', '—', '—'], $this->ecran($component));
        $this->assertTrue($component->instance()->categoriesJour['depart_requis']);
        $this->assertNull($component->instance()->provendeCalculation['total_g']);
    }

    public function test_the_breeder_headcount_never_goes_negative(): void
    {
        $this->departer('2026-07-10');

        $component = Livewire::test(FichePorcs::class)
            ->call('loadDay', '2026-07-11')
            ->set('mortRepro', 9);

        $this->assertEquals(0, $component->instance()->categoriesJour['repro']);
        $this->assertSame('0', $this->affiche($component, 'cat-eff-repro'));
    }

    public function test_saving_persists_the_computed_value(): void
    {
        $this->departer('2026-07-10');

        Livewire::test(FichePorcs::class)
            ->call('loadDay', '2026-07-11')
            ->set('mortRepro', 3)
            ->call('saveDay');

        $this->assertEquals(
            5,
            LivestockDailyEntry::where('entry_date', '2026-07-11')->value('cat_eff_repro')
        );
    }

    // ===================================================================== clé stable des rations (15.42)

    /** @return array<string, array{list<array{string, int}>}> barèmes de libellés, rations ≠ valeurs de secours */
    public static function baremesDeLibelles(): array
    {
        return [
            'libellés actuels du barème' => [[['Porcelet', 350], ['Jeune porc', 700], ['Porc reproducteur', 2500]]],
            'libellés de la maquette' => [[['Porcelet', 350], ['Porc Marchand', 700], ['Reproducteur', 2500]]],
            'capitalisation différente' => [[['PORCELET', 350], ['porc marchand', 700], ['Porc Reproducteur (Truie / Verrat)', 2500]]],
            'libellés détaillés' => [[['Porcelet (Démarrage / Sevrage)', 350], ['Jeune porc (Engraissement)', 700], ['Porc Reproducteur (Truie / Verrat)', 2500]]],
            'jeune marchand' => [[['Porcelet', 350], ['Jeune marchand', 700], ['Reproducteur', 2500]]],
        ];
    }

    /**
     * ⚠️ LE PIÈGE : le web retrouvait les rations par `str_contains` SENSIBLE À LA CASSE (« reproducteur », « Jeune »,
     * « Porcelet ») avec des valeurs de secours en dur (2 000 / 300 / 600). « Reproducteur » (maquette) ou
     * « Porc Marchand » retombaient donc EN SILENCE sur les constantes. Rations ≠ secours : si 2 000 / 300 / 600
     * s'affiche, le barème a été ignoré.
     *
     * @param  list<array{string, int}>  $bareme
     */
    #[DataProvider('baremesDeLibelles')]
    public function test_les_rations_viennent_du_bareme_quel_que_soit_le_libelle(array $bareme): void
    {
        FeedRationStandard::query()->delete();
        foreach ($bareme as [$libelle, $ration]) {
            FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => $libelle, 'ration_g_per_day' => $ration]);
        }

        $this->departer('2026-07-10');
        $calcul = Livewire::test(FichePorcs::class)->call('loadDay', '2026-07-10')->instance()->provendeCalculation;

        $this->assertSame(2500, $calcul['repro']['ration']);
        $this->assertSame(350, $calcul['porcelet']['ration']);
        $this->assertSame(700, $calcul['jeune']['ration']);
        // R8 × 2 500 + P24 × 350 + M28 × 700 = 20 000 + 8 400 + 19 600
        $this->assertSame(48_000, $calcul['total_g']);
    }

    public function test_un_bareme_vide_retombe_sur_les_rations_de_secours_documentees(): void
    {
        FeedRationStandard::query()->delete();

        $this->departer('2026-07-10');
        $calcul = Livewire::test(FichePorcs::class)->call('loadDay', '2026-07-10')->instance()->provendeCalculation;

        $this->assertSame([2000, 300, 600], [$calcul['repro']['ration'], $calcul['porcelet']['ration'], $calcul['jeune']['ration']]);
        $this->assertSame(CategorieRationPorc::RATIONS_DE_SECOURS, [
            CategorieRationPorc::REPRODUCTEUR => 2000, CategorieRationPorc::PORCELET => 300, CategorieRationPorc::MARCHAND => 600,
        ]);
    }

    /** Une ligne d'une AUTRE espèce ou sans rapport (« Lapin Sevré », « Truie ») ne vole aucune ration porcine. */
    public function test_une_ligne_sans_rapport_ne_vole_aucune_ration(): void
    {
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Lapin Sevré', 'ration_g_per_day' => 999]);
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Jeunes', 'ration_g_per_day' => 888]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Reproducteur', 'ration_g_per_day' => 777]);

        $this->departer('2026-07-10');
        $calcul = Livewire::test(FichePorcs::class)->call('loadDay', '2026-07-10')->instance()->provendeCalculation;

        $this->assertSame([2000, 300, 600], [$calcul['repro']['ration'], $calcul['porcelet']['ration'], $calcul['jeune']['ration']]);
    }

    /** @return array<string, array{?string, ?string}> */
    public static function libellesEtCles(): array
    {
        return [
            'reproducteur' => ['Reproducteur', CategorieRationPorc::REPRODUCTEUR],
            'porc reproducteur' => ['Porc reproducteur', CategorieRationPorc::REPRODUCTEUR],
            'majuscules' => ['  PORC REPRODUCTEUR  ', CategorieRationPorc::REPRODUCTEUR],
            'truie / verrat' => ['Porc Reproducteur (Truie / Verrat)', CategorieRationPorc::REPRODUCTEUR],
            'porcelet' => ['Porcelet', CategorieRationPorc::PORCELET],
            'porcelet détaillé' => ['Porcelet (Démarrage / Sevrage)', CategorieRationPorc::PORCELET],
            'porcelets' => ['Porcelets', CategorieRationPorc::PORCELET],
            'porc marchand' => ['Porc Marchand', CategorieRationPorc::MARCHAND],
            'jeune porc' => ['Jeune porc', CategorieRationPorc::MARCHAND],
            'jeune porc engraissement' => ['Jeune porc (Engraissement)', CategorieRationPorc::MARCHAND],
            'jeune marchand' => ['Jeune marchand', CategorieRationPorc::MARCHAND],
            'jeune (marchand)' => ['Jeune (marchand)', CategorieRationPorc::MARCHAND],
            'engraissement' => ['Engraissement', CategorieRationPorc::MARCHAND],
            'jeune seul' => ['Jeune', CategorieRationPorc::MARCHAND],
            'accents tolérés' => ['Porc Marchând', CategorieRationPorc::MARCHAND],
            'pluriel jeunes' => ['Jeunes', null],
            'lapin sevré' => ['Lapin Sevré', null],
            'sans rapport' => ['Truie gestante', null],
            'vide' => ['', null],
            'null' => [null, null],
        ];
    }

    #[DataProvider('libellesEtCles')]
    public function test_la_cle_stable_d_un_libelle(?string $libelle, ?string $attendue): void
    {
        $this->assertSame($attendue, CategorieRationPorc::cle($libelle));
    }

    public function test_les_libelles_affiches_sont_ceux_de_la_maquette_et_les_cles_sont_stables(): void
    {
        $this->assertSame([
            'reproducteur' => 'Reproducteur', 'porcelet' => 'Porcelet', 'marchand' => 'Porc Marchand',
        ], CategorieRationPorc::LIBELLES);
    }

    public function test_une_categorie_en_double_dans_le_bareme_prend_la_premiere_ligne_sans_erreur(): void
    {
        FeedRationStandard::query()->delete();
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Porcelet', 'ration_g_per_day' => 350]);
        FeedRationStandard::create(['species_code' => 'porciculture', 'stage_label' => 'Porcelets', 'ration_g_per_day' => 450]);

        $ration = CategorieRationPorc::ration(FeedRationStandard::all(), CategorieRationPorc::PORCELET);

        $this->assertContains($ration, [350, 450]);
    }
}
