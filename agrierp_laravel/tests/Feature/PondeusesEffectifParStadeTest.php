<?php

namespace Tests\Feature;

use App\Actions\RecordSaleOnFicheElevageAction;
use App\Livewire\Elevage\FichePondeuses;
use App\Livewire\Elevage\FicheReproducteurs;
use App\Livewire\Ventes\PosInterface;
use App\Models\FeedRationStandard;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\User;
use App\Services\EffectifParCategorieService;
use App\Support\CategorieVolaille;
use App\Support\StadePondeuse;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Livewire\Features\SupportTesting\Testable;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket VOL-2 (décision client du 05/11/2026) — EFFECTIF PAR STADE CALCULÉ POUR LA FICHE « PONDEUSES ».
 *
 * Quatre stades (libellés EXACTS du barème) : Poussin ponte (PP, emplacement `quatre`), Poussin en croissance (PC, `sevre`),
 * Poulette (PL, `jeune`), Pondeuse (PO, `repro`). Formules (p1, p2, p3 = passages PP → PC, PC → PL, PL → PO) :
 *   PP = max(0, PPv + éclosions − vente − mort − don − p1)        PC = max(0, PCv − vente − mort − don + p1 − p2)
 *   PL = max(0, PLv + achat − vente − mort − don + p2 − p3)       PO = max(0, POv − vente − mort − don + p3)
 *
 * ⚠️ Les valeurs attendues sont des LITTÉRAUX calculés à la main, jamais produits par le service. Date figée au 14/10/2026.
 * Bande de 100 : départ PP 10 / PC 20 / PL 30 / PO 40 ; rations du barème 30 / 60 / 80 / 110 g/j.
 *
 *   J1 (05/10) achat 2 (→ PL), éclosions 6 (→ PP), morts PP1 PC2 PL3 PO4, passages p1 4, p2 5, p3 6
 *              PP 10+6−1−4 = 11 · PC 20+4−2−5 = 17 · PL 30+2+5−3−6 = 28 · PO 40+6−4 = 42        total 98   provende 8 210 g
 *   J2 (06/10) ventes PP1 PL2 PO3 (caisse), don PC2, mort PO1, passage p1 3
 *              PP 11−1−3 = 7 · PC 17+3−2 = 18 · PL 28−2 = 26 · PO 42−3−1 = 38                    total 89   provende 7 550 g
 *   J3 (07/10) vente de 30 poulettes (caisse) : PL = max(0, 26−30) = 0 ; total max(0, 89−30) = 59 ; somme 63 ≠ 59
 */
class PondeusesEffectifParStadeTest extends TestCase
{
    use RefreshDatabase;

    private const J1 = '2026-10-05';

    private const J2 = '2026-10-06';

    private const J3 = '2026-10-07';

    private LivestockSpecies $espece;

    private LivestockLot $lot;

    /** @var array<string, Product> */
    private array $produits = [];

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->seed(\Database\Seeders\FeedRationStandardsSeeder::class);
        $compte = User::create([
            'name' => 'Directeur', 'username' => 'dg-test', 'email' => 'dg-test@fermeolouwachegoun.com',
            'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true,
        ]);
        $compte->assignRole('admin');
        $this->actingAs($compte);
        Carbon::setTestNow('2026-10-14 12:00:00');

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);

        $this->espece = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Aviculture', 'is_enabled' => true]);
        $this->lot = LivestockLot::create([
            'code' => 'AVI-PON-01', 'species_id' => $this->espece->id, 'stage' => 'ponte',
            'initial_quantity' => 100, 'current_quantity' => 100,
            'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);

        $categorie = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
        foreach ([
            'pp' => ["Poussin d'un jour (ponte)", StadePondeuse::POUSSIN_PONTE],
            'pc' => ['Poussin en croissance', StadePondeuse::POUSSIN_CROISSANCE],
            'pl' => ['Poulette (sujet vif)', StadePondeuse::POULETTE],
            'po' => ['Poule de réforme', StadePondeuse::PONDEUSE],
            'sans' => ['Poulet braisé', null],
            'repro' => ['Coq reproducteur', CategorieVolaille::REPRODUCTEUR],
        ] as $cle => [$nom, $stade]) {
            $this->produits[$cle] = Product::create([
                'sku' => 'AVI-'.strtoupper($cle), 'name' => $nom, 'category_id' => $categorie->id, 'unit' => 'u',
                'pricing_mode' => 'fourchette', 'price_min' => 1000, 'price_max' => 5000, 'stock_qty' => 500,
                'species_id' => $this->espece->id, 'is_active' => true, 'categorie_effectif' => $stade,
            ]);
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    // ===================================================================== outils

    private function ouvrir(string $jour): Testable
    {
        return Livewire::test(FichePondeuses::class)->set('selectedDate', $jour);
    }

    private function departer(Testable $c, int $pp = 10, int $pc = 20, int $pl = 30, int $po = 40): Testable
    {
        return $c->set('departPoussinPonte', $pp)->set('departPoussinCroissance', $pc)->set('departPoulette', $pl)->set('departPondeuse', $po);
    }

    private function entree(string $jour): LivestockDailyEntry
    {
        return LivestockDailyEntry::where('lot_id', $this->lot->id)->whereDate('entry_date', $jour)->firstOrFail();
    }

    /** @return array{int, int, int, int} cat_eff Poussin ponte, Poussin en croissance, Poulette, Pondeuse STOCKÉS. */
    private function stocke(string $jour): array
    {
        $f = $this->entree($jour);

        return [(int) $f->cat_eff_4, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune, (int) $f->cat_eff_repro];
    }

    private function cellule(Testable $c, string $id): string
    {
        $this->assertSame(1, preg_match('/<td\b[^>]*\bid="'.preg_quote($id, '/').'"[^>]*>\s*([^<]*?)\s*<\/td>/', $c->html(), $m), "cellule #{$id} introuvable");

        return html_entity_decode($m[1]);
    }

    private function texte(Testable $c): string
    {
        return preg_replace('/\s+/u', ' ', html_entity_decode(strip_tags($c->html()), ENT_QUOTES | ENT_HTML5));
    }

    private function vendre(string $produit, int $qte, string $jour): void
    {
        app(RecordSaleOnFicheElevageAction::class)->execute(
            [['lot_id' => $this->lot->id, 'qty' => $qte, 'product_id' => $this->produits[$produit]->id]],
            $jour,
        );
    }

    private function scenarioComplet(): void
    {
        $this->departer($this->ouvrir(self::J1))
            ->set('achat', 2)->set('ne', 6)
            ->set('mortPoussinPonte', 1)->set('mortPoussinCroissance', 2)->set('mortPoulette', 3)->set('mortPondeuse', 4)
            ->set('passage1', 4)->set('passage2', 5)->set('passage3', 6)
            ->call('saveDay');

        $this->vendre('pp', 1, self::J2);
        $this->vendre('pl', 2, self::J2);
        $this->vendre('po', 3, self::J2);
        $this->ouvrir(self::J2)->set('donPoussinCroissance', 2)->set('mortPondeuse', 1)->set('passage1', 3)->call('saveDay');

        $this->vendre('pl', 30, self::J3);
        $this->ouvrir(self::J3)->call('saveDay');
    }

    // ===================================================================== (1) service pur, calculs à la main

    public function test_service_l_achat_entre_dans_poulette(): void
    {
        $r = EffectifParCategorieService::calculerJour('volailles_ponte', ['repro' => 0, 'sevre' => 0, 'jeune' => 10, 'quatre' => 0], ['achat' => 4]);

        $this->assertSame([0, 0, 14, 0], [$r->repro, $r->sevre, $r->jeune, $r->quatre]);
    }

    public function test_service_l_eclosion_entre_dans_poussin_ponte(): void
    {
        $r = EffectifParCategorieService::calculerJour('volailles_ponte', ['repro' => 1, 'sevre' => 2, 'jeune' => 3, 'quatre' => 10], ['ne' => 6]);

        $this->assertSame([1, 2, 3, 16], [$r->repro, $r->sevre, $r->jeune, $r->quatre]);
    }

    public function test_service_trois_passages_enchainent_les_stades_total_inchange(): void
    {
        $r = EffectifParCategorieService::calculerJour(
            'volailles_ponte',
            ['repro' => 0, 'sevre' => 0, 'jeune' => 0, 'quatre' => 10],
            ['passage_4_sevre' => 4, 'passage' => 3, 'passage_jeune_repro' => 2],
        );

        // PP 10−4 = 6 · PC 0+4−3 = 1 · PL 0+3−2 = 1 · PO 0+2 = 2 : total 10.
        $this->assertSame([2, 1, 1, 6], [$r->repro, $r->sevre, $r->jeune, $r->quatre]);
        $this->assertSame(10, $r->somme());
        $this->assertNull($r->refus);
        $this->assertSame(['passage_4_sevre' => 4, 'passage_sevre_jeune' => 3, 'passage_jeune_repro' => 2], $r->passagesAppliques);
    }

    public function test_service_chaque_stade_est_borne_a_zero(): void
    {
        $r = EffectifParCategorieService::calculerJour(
            'volailles_ponte',
            ['repro' => 3, 'sevre' => 2, 'jeune' => 1, 'quatre' => 0],
            ['vente_repro' => 5, 'mort_sevre' => 9, 'don_jeune' => 4, 'mort_4' => 7],
        );

        $this->assertSame([0, 0, 0, 0], [$r->repro, $r->sevre, $r->jeune, $r->quatre]);
    }

    public function test_service_un_passage_superieur_a_la_source_est_refuse_et_ramene_a_la_source(): void
    {
        // PP 10 : un passage de 11 est refusé, ramené à 10.
        $r = EffectifParCategorieService::calculerJour('volailles_ponte', ['repro' => 0, 'sevre' => 0, 'jeune' => 0, 'quatre' => 10], ['passage_4_sevre' => 11]);

        $this->assertSame("Passage de stade refusé (Poussin ponte (0 à 2 mois) vers Poussin en croissance (2 à 4 mois)) : 11 sujet(s) à faire passer, mais le stade source n'en compte que 10.", $r->refus);
        $this->assertSame([0, 10, 0, 0], [$r->repro, $r->sevre, $r->jeune, $r->quatre]);

        // Le passage entrant compte dans la source suivante : p1 5 puis p2 5 passent, p2 6 est refusé (PC n'a que 5).
        $ok = EffectifParCategorieService::calculerJour('volailles_ponte', ['repro' => 0, 'sevre' => 0, 'jeune' => 0, 'quatre' => 5], ['passage_4_sevre' => 5, 'passage' => 5]);
        $this->assertNull($ok->refus);
        $this->assertSame([0, 0, 5, 0], [$ok->repro, $ok->sevre, $ok->jeune, $ok->quatre]);
        $ko = EffectifParCategorieService::calculerJour('volailles_ponte', ['repro' => 0, 'sevre' => 0, 'jeune' => 0, 'quatre' => 5], ['passage_4_sevre' => 5, 'passage' => 6]);
        $this->assertStringContainsString("(Poussin en croissance (2 à 4 mois) vers Poulette (4 à 5.5 mois)) : 6 sujet(s) à faire passer, mais le stade source n'en compte que 5.", (string) $ko->refus);
    }

    public function test_service_jamais_de_null_meme_sans_mouvement_ni_veille(): void
    {
        $r = EffectifParCategorieService::calculerJour('volailles_ponte', ['repro' => null, 'sevre' => null, 'jeune' => null, 'quatre' => null], []);

        $this->assertSame([0, 0, 0, 0], [$r->repro, $r->sevre, $r->jeune, $r->quatre]);
        $this->assertSame(['cat_eff_repro' => 0, 'cat_eff_sevre' => 0, 'cat_eff_jeune' => 0, 'cat_eff_4' => 0], $r->versColonnes());
    }

    public function test_service_un_depart_different_de_la_somme_est_refuse(): void
    {
        $this->assertSame(
            "La somme des stades de départ (99) ne correspond pas à l'effectif total au début du jour de départ (100).",
            EffectifParCategorieService::verifierDepart(['repro' => 40, 'sevre' => 20, 'jeune' => 30, 'quatre' => 9], 100),
        );
        $this->assertSame(
            'Effectif de départ incomplet : les quatre stades doivent être renseignés (0 si le stade est vide).',
            EffectifParCategorieService::verifierDepart(['repro' => 40, 'sevre' => 20, 'jeune' => 30, 'quatre' => null], 100),
        );
        $this->assertNull(EffectifParCategorieService::verifierDepart(['repro' => 40, 'sevre' => 20, 'jeune' => 30, 'quatre' => 10], 100));
    }

    public function test_les_deux_familles_de_volailles_sont_distinctes(): void
    {
        $this->assertSame('volailles_ponte', EffectifParCategorieService::especeDuLot($this->lot->load('species')));
        $this->lot->update(['stage' => 'reproduction']);
        $this->assertSame('volailles_repro', EffectifParCategorieService::especeDuLot($this->lot->fresh()->load('species')));
        $this->assertSame(['repro', 'sevre', 'jeune', 'quatre'], EffectifParCategorieService::emplacementsDe('volailles_ponte'));
        $this->assertSame(['repro', 'sevre', 'jeune'], EffectifParCategorieService::emplacementsDe('volailles_repro'));
    }

    // ===================================================================== (2) fiche Livewire

    public function test_la_fiche_demande_le_depart_au_lieu_de_l_effectif_et_refuse_d_enregistrer(): void
    {
        $c = $this->ouvrir(self::J1);

        $this->assertStringContainsString('Effectif de départ par stade (obligatoire)', $this->texte($c));
        $this->assertStringContainsString("Saisissez l'effectif de départ de la bande pour calculer", $this->texte($c));

        $c->set('achat', 3)->call('saveDay');

        $this->assertSame(0, LivestockDailyEntry::count(), 'rien ne s\'enregistre sans départ');
        $this->assertStringContainsString('id="ration-depart-requis"', $c->html());
        $this->assertStringNotContainsString('id="cat-eff-', $c->html(), 'jamais d\'effectif de stade inconnu (« — »)');
    }

    public function test_les_libelles_affiches_sont_les_quatre_du_bareme_partout(): void
    {
        $texte = $this->texte($this->departer($this->ouvrir(self::J1)));

        foreach (StadePondeuse::LIBELLES as $libelle) {
            $this->assertGreaterThanOrEqual(6, substr_count($texte, $libelle), "« {$libelle} » : morts, dons, départ, ration, ventes, passages");
        }
        // Les lignes des reproducteurs n'apparaissent jamais sur la fiche Pondeuses.
        $this->assertStringNotContainsString('Reproducteur', $texte);
        $this->assertStringNotContainsString('id="cat-eff-reproducteur"', $this->ouvrir(self::J1)->html());
    }

    public function test_un_depart_incoherent_est_refuse(): void
    {
        $c = $this->departer($this->ouvrir(self::J1), 10, 20, 30, 39);

        $this->assertStringContainsString('La somme des stades de départ (99)', $this->texte($c));
        $c->call('saveDay');
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_la_proposition_du_stade_est_reprise_sur_demande_seulement(): void
    {
        $c = $this->ouvrir(self::J1);
        $c->assertSet('departPondeuse', null);

        $c->call('appliquerPropositionDepart')
            ->assertSet('departPondeuse', 100)->assertSet('departPoulette', 0)->assertSet('departPoussinCroissance', 0)->assertSet('departPoussinPonte', 0);
    }

    public function test_les_champs_d_effectif_sont_calcules_en_direct_et_disabled(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('achat', 3);

        foreach (['poussin_ponte', 'poussin_croissance', 'poulette', 'pondeuse'] as $cle) {
            $this->assertSame(1, preg_match('/<input\b[^>]*\bid="cat-eff-'.$cle.'"[^>]*>/', $c->html(), $m));
            $this->assertMatchesRegularExpression('/\bdisabled\b/', $m[0]);
        }
        // Départ 10/20/30/40 + achat 3 (→ Poulette).
        $t = $c->instance()->rationnement['lignes'];
        $this->assertSame([10, 20, 33, 40], array_column($t, 'effectif'));
    }

    public function test_enregistrement_ecrit_depart_mouvements_ventiles_passages_et_stades_calcules(): void
    {
        $this->departer($this->ouvrir(self::J1))
            ->set('achat', 2)->set('ne', 6)
            ->set('mortPoussinPonte', 1)->set('mortPoussinCroissance', 2)->set('mortPoulette', 3)->set('mortPondeuse', 4)
            ->set('passage1', 4)->set('passage2', 5)->set('passage3', 6)
            ->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame([40, 20, 30, 10], [(int) $f->cat_depart_repro, (int) $f->cat_depart_sevre, (int) $f->cat_depart_jeune, (int) $f->cat_depart_4]);
        $this->assertSame([4, 2, 3, 1, 10], [(int) $f->mort_repro, (int) $f->mort_sevre, (int) $f->mort_jeune, (int) $f->mort_4, (int) $f->mort]);
        $this->assertSame([4, 5, 6], [(int) $f->passage_4_sevre, (int) $f->passage_sevre_jeune, (int) $f->passage_jeune_repro]);
        $this->assertSame(98, (int) $f->effectif_final);
        $this->assertSame([11, 17, 28, 42], $this->stocke(self::J1));
        $this->assertSame(98, (int) $this->lot->fresh()->current_quantity);
    }

    public function test_jours_suivants_ventes_par_stade_bornes_et_avertissement(): void
    {
        $this->scenarioComplet();

        $this->assertSame([7, 18, 26, 38], $this->stocke(self::J2));
        $j2 = $this->entree(self::J2);
        $this->assertSame(89, (int) $j2->effectif_final);
        $this->assertSame([1, 2, 3, 6], [(int) $j2->vente_4, (int) $j2->vente_jeune, (int) $j2->vente_repro, (int) $j2->vente]);
        $this->assertSame(0, (int) $j2->vente_sevre);

        $this->assertSame([7, 18, 0, 38], $this->stocke(self::J3));
        $this->assertSame(59, (int) $this->entree(self::J3)->effectif_final);

        $this->assertStringContainsString("la somme des stades (63) diffère de l'effectif total (59)", $this->texte($this->ouvrir(self::J3)));
    }

    public function test_provende_du_jour_est_la_somme_des_quatre_stades_arrondie_comme_php(): void
    {
        $this->scenarioComplet();

        $c = $this->ouvrir(self::J1);
        // 11 × 30 = 330 ; 17 × 60 = 1 020 ; 28 × 80 = 2 240 ; 42 × 110 = 4 620.
        $this->assertSame('330 g', $this->cellule($c, 'cat-prov-poussin_ponte-g'));
        $this->assertSame('1020 g', $this->cellule($c, 'cat-prov-poussin_croissance-g'));
        $this->assertSame('2240 g', $this->cellule($c, 'cat-prov-poulette-g'));
        $this->assertSame('4620 g', $this->cellule($c, 'cat-prov-pondeuse-g'));
        $this->assertSame('8210 g (8.21 Kg)', $this->cellule($c, 'day-total-provende-g'));

        $c2 = $this->ouvrir(self::J2);
        // 7 × 30 + 18 × 60 + 26 × 80 + 38 × 110 = 210 + 1 080 + 2 080 + 4 180 = 7 550.
        $this->assertSame('7550 g (7.55 Kg)', $this->cellule($c2, 'day-total-provende-g'));
        $this->assertSame(7.55, $c2->instance()->rationnement['total_kg']);
    }

    public function test_un_passage_superieur_a_la_source_est_refuse_a_l_enregistrement(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('passage1', 11);

        $this->assertStringContainsString("le stade source n'en compte que 10", $this->texte($c));
        $c->call('saveDay');
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_un_jour_anterieur_au_depart_n_est_pas_saisissable(): void
    {
        $this->departer($this->ouvrir(self::J2))->call('saveDay');
        $c = $this->ouvrir(self::J1);

        $this->assertStringContainsString("Jour antérieur à l'effectif de départ", $this->texte($c));
        $c->set('achat', 1)->call('saveDay');
        $this->assertSame(1, LivestockDailyEntry::count());
    }

    public function test_le_depart_est_verrouille_apres_le_premier_enregistrement(): void
    {
        $this->departer($this->ouvrir(self::J1))->call('saveDay');

        $c = $this->ouvrir(self::J2);
        $this->assertStringContainsString('Effectif de départ par stade (verrouillé)', $this->texte($c));
        $this->assertStringNotContainsString('Effectif de départ par stade (obligatoire)', $this->texte($c));
    }

    public function test_corriger_un_jour_passe_recalcule_les_jours_suivants(): void
    {
        $this->scenarioComplet();

        // J1 corrigé : 8 morts de Pondeuse au lieu de 4 (PO 38 au lieu de 42, total 94).
        $this->ouvrir(self::J1)->set('mortPondeuse', 8)->call('saveDay');

        $this->assertSame([11, 17, 28, 38], $this->stocke(self::J1));
        $this->assertSame([7, 18, 26, 34], $this->stocke(self::J2));     // PO 38 − vente 3 − mort 1
        $this->assertSame(85, (int) $this->entree(self::J2)->effectif_final);
    }

    public function test_une_fiche_d_avant_le_ticket_non_ventilee_doit_etre_ventilee(): void
    {
        LivestockDailyEntry::create([
            'lot_id' => $this->lot->id, 'entry_date' => self::J1, 'achat' => 0, 'ne' => 0, 'mort' => 4, 'vente' => 0, 'don' => 0, 'effectif_final' => 96,
            'ponte_total' => 150,
        ]);

        $c = $this->departer($this->ouvrir(self::J1))->assertSet('mortEnregistre', 4);
        $c->call('saveDay');
        $this->assertNull($this->entree(self::J1)->cat_depart_repro, 'refusé tant que les morts ne sont pas ventilés');

        $c->set('mortPondeuse', 1)->set('mortPoulette', 1)->set('mortPoussinCroissance', 1)->set('mortPoussinPonte', 1)->call('saveDay');
        $this->assertSame(10, (int) $this->entree(self::J1)->cat_depart_4);
        $this->assertSame(150, (int) $this->entree(self::J1)->ponte_total, 'la ponte (œufs) n\'est pas touchée');
    }

    public function test_les_oeufs_et_le_stock_d_oeufs_ne_changent_pas(): void
    {
        $this->departer($this->ouvrir(self::J1))->set('oeufsRecoltes', 90)->set('oeufsCasses', 10)->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame([90, 10], [(int) $f->ponte_total, (int) $f->ponte_casses]);
        $this->assertSame(80, $this->ouvrir(self::J1)->instance()->commercialisables);
    }

    // ===================================================================== (3) caisse : produit → stade

    private function departEnBase(): void
    {
        $this->departer($this->ouvrir(self::J1))->call('saveDay');
    }

    private function vendreALaCaisse(string $produit, int $qte, ?string $jour = null): Testable
    {
        $p = $this->produits[$produit];

        return Livewire::test(PosInterface::class)
            ->set('cart', [[
                'product_id' => $p->id, 'name' => $p->name, 'unit' => 'u', 'lot_id' => $this->lot->id, 'lot_code' => $this->lot->code,
                'qty' => $qte, 'montant' => 1000 * $qte,
            ]])
            ->set('paymentMode', 'especes')->set('cashReceived', 1000 * $qte)
            ->set('dateVente', $jour ?? now()->toDateString())
            ->call('validateSale');
    }

    public function test_caisse_la_vente_est_rangee_dans_le_stade_du_produit(): void
    {
        $this->departEnBase();

        $this->vendreALaCaisse('pc', 3, self::J2);
        $this->vendreALaCaisse('pp', 1, self::J2);

        $f = $this->entree(self::J2);
        $this->assertSame([4, 3, 1, 0, 0], [(int) $f->vente, (int) $f->vente_sevre, (int) $f->vente_4, (int) $f->vente_jeune, (int) $f->vente_repro]);
        // PC 20 − 3 = 17 ; PP 10 − 1 = 9 ; PL 30 ; PO 40 ; total 100 − 4 = 96.
        $this->assertSame([9, 17, 30, 40], $this->stocke(self::J2));
        $this->assertSame(96, (int) $f->effectif_final);
    }

    public function test_caisse_un_produit_sans_stade_est_refuse_avec_un_motif_clair_et_rien_n_est_ecrit(): void
    {
        $this->departEnBase();
        $avant = LivestockDailyEntry::count();

        $c = $this->vendreALaCaisse('sans', 2, self::J2);

        $c->assertDispatched('toast', message: "Vente refusée : le produit « Poulet braisé » n'a pas de stade d'effectif de pondeuses (Poussin ponte, Poussin en croissance, Poulette ou Pondeuse). Renseignez-le dans « Modifier un produit » avant de le vendre sur une bande de pondeuses.", type: 'error');
        $this->assertSame($avant, LivestockDailyEntry::count());
        $this->assertSame(0, \App\Models\Sale::count());
        $this->assertSame('500.00', (string) $this->produits['sans']->fresh()->stock_qty);
    }

    public function test_caisse_une_categorie_de_reproducteurs_ne_se_vend_pas_sur_une_bande_de_pondeuses(): void
    {
        $this->departEnBase();

        $refus = app(RecordSaleOnFicheElevageAction::class)->refusDesLignes(
            [['lot_id' => $this->lot->id, 'qty' => 1, 'product_id' => $this->produits['repro']->id]], self::J2,
        );

        $this->assertStringContainsString('n\'a pas de stade d\'effectif de pondeuses', (string) $refus);
    }

    public function test_caisse_une_bande_sans_depart_refuse_la_vente(): void
    {
        $c = $this->vendreALaCaisse('pl', 2, self::J2);

        $c->assertDispatched('toast', message: "Vente refusée : l'effectif de départ par stade de la bande AVI-PON-01 n'est pas saisi. Ouvrez la fiche Pondeuses et saisissez-le avant toute vente de cette bande.", type: 'error');
        $this->assertSame(0, \App\Models\Sale::count());
    }

    public function test_vente_antidatee_avant_le_depart_refusee_et_apres_recalcule_la_chaine(): void
    {
        $this->departer($this->ouvrir(self::J2))->call('saveDay');
        $this->ouvrir(self::J3)->call('saveDay');

        try {
            $this->vendre('pl', 1, self::J1);
            $this->fail('une vente avant le départ doit être refusée');
        } catch (ValidationException $e) {
            $this->assertStringContainsString('précède l\'effectif de départ', $e->errors()['lines'][0]);
        }

        $this->vendre('pl', 2, self::J2);
        $this->assertSame([10, 20, 28, 40], $this->stocke(self::J2));
        $this->assertSame([10, 20, 28, 40], $this->stocke(self::J3));
        $this->assertSame(98, (int) $this->entree(self::J3)->effectif_final);
        $this->assertSame(98, (int) $this->lot->fresh()->current_quantity);
    }

    public function test_la_transformation_range_ses_sujets_dans_pondeuse(): void
    {
        $this->departEnBase();

        app(RecordSaleOnFicheElevageAction::class)->execute(
            [['lot_id' => $this->lot->id, 'qty' => 5, 'categorie_effectif' => StadePondeuse::PONDEUSE]], self::J2,
        );

        $this->assertSame([10, 20, 30, 35], $this->stocke(self::J2));
    }

    // ===================================================================== (4) rationnement : barème, produits, familles

    public function test_les_cles_de_ration_sont_exactes_jamais_par_sous_chaine(): void
    {
        $this->assertSame(StadePondeuse::POUSSIN_PONTE, StadePondeuse::cleDuLibelle('Poussin ponte (0 à 2 mois)'));
        $this->assertSame(StadePondeuse::POUSSIN_CROISSANCE, StadePondeuse::cleDuLibelle('poussin en croissance'));
        $this->assertSame(StadePondeuse::POULETTE, StadePondeuse::cleDuLibelle(' Poulette (4 à 5.5 mois) '));
        $this->assertSame(StadePondeuse::PONDEUSE, StadePondeuse::cleDuLibelle('Pondeuse (6 à 18 mois)'));
        $this->assertNull(StadePondeuse::cleDuLibelle('Poussin'));
        $this->assertNull(StadePondeuse::cleDuLibelle('Jeune'));
        $this->assertNull(StadePondeuse::cleDuLibelle('Reproducteur'));
        $this->assertNull(StadePondeuse::cleDuLibelle('Pondeuse réformée'));
        // … et réciproquement, les lignes des pondeuses ne sont jamais des catégories de reproducteurs.
        $this->assertNull(CategorieVolaille::cleDuLibelle('Poussin ponte (0 à 2 mois)'));
    }

    public function test_le_tableau_a_quatre_lignes_dans_l_ordre_de_la_chaine_et_le_total_est_arrondi_comme_php(): void
    {
        FeedRationStandard::where('stage_label', 'Pondeuse (6 à 18 mois)')->update(['ration_g_per_day' => 105]);

        $t = StadePondeuse::tableau(FeedRationStandard::where('species_code', 'aviculture')->get(), ['quatre' => 1, 'sevre' => 2, 'jeune' => 3, 'repro' => 7]);

        // 1 × 30 + 2 × 60 + 3 × 80 + 7 × 105 = 30 + 120 + 240 + 735 = 1 125 g.
        $this->assertSame(
            ['Poussin ponte (0 à 2 mois)', 'Poussin en croissance (2 à 4 mois)', 'Poulette (4 à 5.5 mois)', 'Pondeuse (6 à 18 mois)'],
            array_column($t['lignes'], 'libelle'),
        );
        $this->assertSame([30, 120, 240, 735], array_column($t['lignes'], 'total_g'));
        $this->assertSame(1125, $t['total_g']);
        $this->assertSame(1.13, $t['total_kg']);      // 1,125 arrondi à 2 décimales comme `round()` de PHP
    }

    public function test_un_stade_indisponible_rend_le_total_inconnu_jamais_0(): void
    {
        $t = StadePondeuse::tableau(FeedRationStandard::where('species_code', 'aviculture')->get(), ['quatre' => null, 'sevre' => 2, 'jeune' => 3, 'repro' => 7]);

        $this->assertNull($t['total_g']);
        $this->assertNull($t['total_kg']);
    }

    public function test_une_ligne_du_bareme_absente_retombe_sur_la_valeur_d_origine(): void
    {
        FeedRationStandard::where('stage_label', 'Poulette (4 à 5.5 mois)')->delete();

        $t = StadePondeuse::tableau(FeedRationStandard::where('species_code', 'aviculture')->get(), ['quatre' => 0, 'sevre' => 0, 'jeune' => 1, 'repro' => 0]);

        $this->assertSame(80, $t['total_g']);
    }

    public function test_produits_par_defaut_d_apres_le_nom(): void
    {
        $this->assertSame('poulette', StadePondeuse::devinerDepuisLeNom('Poulette (sujet vif)'));
        $this->assertSame('pondeuse', StadePondeuse::devinerDepuisLeNom('Poule pondeuse'));
        $this->assertSame('pondeuse', StadePondeuse::devinerDepuisLeNom('Poule de réforme'));
        $this->assertSame('poussin_croissance', StadePondeuse::devinerDepuisLeNom('Poussin en croissance'));
        $this->assertSame('poussin_ponte', StadePondeuse::devinerDepuisLeNom("Poussin d'un jour ponte"));
        $this->assertNull(StadePondeuse::devinerDepuisLeNom("Poussin d'un jour"));
        $this->assertNull(StadePondeuse::devinerDepuisLeNom('Œufs de table (plateau)'));
        $this->assertNull(StadePondeuse::devinerDepuisLeNom('Aliment croissance (poulette) 25kg'));
    }

    public function test_la_fiche_reproducteurs_n_affiche_jamais_les_stades_de_ponte(): void
    {
        $this->lot->update(['stage' => 'reproduction']);

        $html = Livewire::test(FicheReproducteurs::class)->html();

        $this->assertStringNotContainsString('Poussin ponte', $html);
        $this->assertStringNotContainsString('Pondeuse (6 à 18 mois)', $html);
    }

    public function test_la_migration_pose_le_stade_des_produits_d_apres_le_nom_sans_ecraser_un_choix_humain(): void
    {
        // « Poule de réforme » rangée par la règle de VOL-1 (reproducteur) → pondeuse ; un choix humain reste.
        $this->produits['po']->update(['categorie_effectif' => CategorieVolaille::REPRODUCTEUR]);
        $humain = Product::create([
            'sku' => 'AVI-H', 'name' => 'Poulette (sujet vif) choisie', 'category_id' => $this->produits['po']->category_id, 'unit' => 'u',
            'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => 1, 'species_id' => $this->espece->id,
            'is_active' => true, 'categorie_effectif' => CategorieVolaille::REPRODUCTEUR,   // ≠ de la règle de VOL-1 (jeune) : choix humain
        ]);
        $this->produits['pl']->update(['categorie_effectif' => null]);

        (include database_path('migrations/2026_11_05_000006_ajouter_stades_pondeuses_produits.php'))->up();

        $this->assertNotNull($this->produits['pl']->fresh()->categorie_effectif);
        $this->assertSame('poulette', $this->produits['pl']->fresh()->categorie_effectif);
        $this->assertSame('reproducteur', $humain->fresh()->categorie_effectif);
    }
}
