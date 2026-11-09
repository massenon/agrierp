<?php

namespace Tests\Feature;

use App\Actions\RecordSaleOnFicheElevageAction;
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
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Livewire\Features\SupportTesting\Testable;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket VOL-1 (décision client du 04/11/2026) — EFFECTIF PAR CATÉGORIE CALCULÉ POUR LA FICHE « VOLAILLES REPRODUCTEURS ».
 *
 * Trois catégories : Reproducteur (`repro`), Jeune (`jeune`, ex-« Poulet »), Poussin (`sevre`). Formules :
 *   R = max(0, Rv − vente_R − mort_R − don_R)
 *   J = max(0, Jv + achat − vente_J − mort_J − don_J + p)
 *   P = max(0, Pv + éclosions − vente_P − mort_P − don_P − p)
 *
 * ⚠️ Les valeurs attendues sont des LITTÉRAUX calculés à la main, jamais produits par le service. Date figée au 14/10/2026.
 * Bande : 100 sujets, départ Reproducteur 20 / Jeune 30 / Poussin 50, rations 130 / 80 / 30 g/j.
 *
 *   J1 (05/10) achat 2, éclosions 10, morts R1 + J2 + P3                       → R19  J30  P57   total 106   provende 6 580 g
 *   J2 (06/10) ventes R1 + J2 + P4 (caisse), mort J1, don P2, passage 5         → R18  J32  P46   total 96    provende 6 280 g
 *   J3 (07/10) vente P50 (caisse)                                              → R18  J32  P0    total 46    somme 50 ≠ 46
 */
class VolaillesEffectifParCategorieTest extends TestCase
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
            'code' => 'AVI-REP-01', 'species_id' => $this->espece->id, 'stage' => 'reproduction',
            'initial_quantity' => 100, 'current_quantity' => 100,
            'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);

        // Les trois lignes du barème (130 / 80 / 30 g/j) sont semées par la migration VOL-1, comme sur une base existante.

        $categorie = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
        foreach ([
            'poussin' => ["Poussin d'un jour", CategorieVolaille::POUSSIN],
            'jeune' => ['Poulet goliath (sujet vif)', CategorieVolaille::JEUNE],
            'repro' => ['Coq reproducteur', CategorieVolaille::REPRODUCTEUR],
            'sans' => ['Poulet braisé', null],
        ] as $cle => [$nom, $categorieEffectif]) {
            $this->produits[$cle] = Product::create([
                'sku' => 'AVI-'.strtoupper($cle), 'name' => $nom, 'category_id' => $categorie->id, 'unit' => 'u',
                'pricing_mode' => 'fourchette', 'price_min' => 1000, 'price_max' => 5000, 'stock_qty' => 500,
                'species_id' => $this->espece->id, 'is_active' => true, 'categorie_effectif' => $categorieEffectif,
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
        return Livewire::test(FicheReproducteurs::class)->set('selectedDate', $jour);
    }

    private function departer(Testable $c, int $r = 20, int $j = 30, int $p = 50): Testable
    {
        return $c->set('departRepro', $r)->set('departJeune', $j)->set('departSevre', $p);
    }

    private function entree(string $jour): LivestockDailyEntry
    {
        return LivestockDailyEntry::where('lot_id', $this->lot->id)->whereDate('entry_date', $jour)->firstOrFail();
    }

    /** @return array{int, int, int} cat_eff Reproducteur, Jeune, Poussin STOCKÉS. */
    private function stocke(string $jour): array
    {
        $f = $this->entree($jour);

        return [(int) $f->cat_eff_repro, (int) $f->cat_eff_jeune, (int) $f->cat_eff_sevre];
    }

    private function affiche(Testable $c, string $id): string
    {
        $this->assertSame(1, preg_match('/<input\b[^>]*\bid="'.preg_quote($id, '/').'"[^>]*>/', $c->html(), $m), "champ #{$id} introuvable");
        $this->assertSame(1, preg_match('/\bvalue="([^"]*)"/', $m[0], $v));

        return $v[1];
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
            ->set('achat', 2)->set('poussinsNes', 10)
            ->set('mortRepro', 1)->set('mortPoulet', 2)->set('mortPoussin', 3)
            ->call('saveDay');

        $this->vendre('repro', 1, self::J2);
        $this->vendre('jeune', 2, self::J2);
        $this->vendre('poussin', 4, self::J2);
        $this->ouvrir(self::J2)->set('mortPoulet', 1)->set('donPoussin', 2)->set('passage', 5)->call('saveDay');

        $this->vendre('poussin', 50, self::J3);
        $this->ouvrir(self::J3)->call('saveDay');
    }

    // ===================================================================== (1) service pur, calculs à la main

    public function test_service_la_vente_reproducteur_sort_des_reproducteurs_seulement(): void
    {
        $r = EffectifParCategorieService::calculerJour('volailles_repro', ['repro' => 5, 'sevre' => 7, 'jeune' => 9], ['vente_repro' => 2]);

        $this->assertSame([3, 7, 9], [$r->repro, $r->sevre, $r->jeune]);
    }

    public function test_service_l_achat_entre_dans_les_jeunes(): void
    {
        $r = EffectifParCategorieService::calculerJour('volailles_repro', ['repro' => 0, 'sevre' => 0, 'jeune' => 10], ['achat' => 4]);

        $this->assertSame([0, 0, 14], [$r->repro, $r->sevre, $r->jeune]);
    }

    public function test_service_l_eclosion_entre_dans_les_poussins(): void
    {
        $r = EffectifParCategorieService::calculerJour('volailles_repro', ['repro' => 0, 'sevre' => 10, 'jeune' => 0], ['ne' => 6]);

        $this->assertSame([0, 16, 0], [$r->repro, $r->sevre, $r->jeune]);
    }

    public function test_service_le_passage_transfere_des_poussins_aux_jeunes_total_inchange(): void
    {
        $r = EffectifParCategorieService::calculerJour('volailles_repro', ['repro' => 3, 'sevre' => 10, 'jeune' => 2], ['passage' => 4]);

        $this->assertSame([3, 6, 6], [$r->repro, $r->sevre, $r->jeune]);
        $this->assertSame(15, $r->somme());
        $this->assertNull($r->refus);
    }

    public function test_service_chaque_categorie_est_bornee_a_zero(): void
    {
        $r = EffectifParCategorieService::calculerJour('volailles_repro', ['repro' => 2, 'sevre' => 2, 'jeune' => 2], [
            'mort_repro' => 5, 'vente_sevre' => 9, 'don_jeune' => 7,
        ]);

        $this->assertSame([0, 0, 0], [$r->repro, $r->sevre, $r->jeune]);
    }

    public function test_service_un_passage_superieur_a_la_source_est_refuse_et_ramene_a_la_source(): void
    {
        // Source = 3 poussins − 1 mort = 2 ; passage demandé 3.
        $r = EffectifParCategorieService::calculerJour('volailles_repro', ['repro' => 0, 'sevre' => 3, 'jeune' => 0], ['mort_sevre' => 1, 'passage' => 3]);

        $this->assertSame("Passage de stade refusé : 3 sujet(s) à faire passer, mais la catégorie source n'en compte que 2.", $r->refus);
        $this->assertSame(2, $r->passageApplique);
        $this->assertSame([0, 0, 2], [$r->repro, $r->sevre, $r->jeune]);
    }

    public function test_service_jamais_de_null_meme_sans_mouvement_ni_veille(): void
    {
        $r = EffectifParCategorieService::calculerJour('volailles_repro', ['repro' => null, 'sevre' => null, 'jeune' => null], []);

        $this->assertSame([0, 0, 0], [$r->repro, $r->sevre, $r->jeune]);
        $this->assertTrue($r->estComplet());
    }

    public function test_service_un_depart_different_de_la_somme_est_refuse(): void
    {
        $this->assertSame(
            "La somme des catégories de départ (99) ne correspond pas à l'effectif total au début du jour de départ (100).",
            EffectifParCategorieService::verifierDepart(['repro' => 20, 'sevre' => 50, 'jeune' => 29], 100),
        );
        $this->assertNull(EffectifParCategorieService::verifierDepart(['repro' => 20, 'sevre' => 50, 'jeune' => 30], 100));
    }

    public function test_les_bandes_ponte_et_les_autres_filieres_ne_sont_pas_des_volailles(): void
    {
        $this->assertSame('volailles_repro', EffectifParCategorieService::especeDuLot($this->lot->load('species')));
        // VOL-2 : le stade « ponte » est l'AUTRE famille de volailles (pondeuses, quatre stades), distincte des reproducteurs.
        $this->lot->update(['stage' => 'ponte']);
        $this->assertSame('volailles_ponte', EffectifParCategorieService::especeDuLot($this->lot->fresh()->load('species')));
    }

    // ===================================================================== (2) fiche Livewire

    public function test_la_fiche_demande_le_depart_au_lieu_de_l_effectif_et_refuse_d_enregistrer(): void
    {
        $c = $this->ouvrir(self::J1);

        $this->assertStringContainsString('Effectif de départ par catégorie (obligatoire)', $this->texte($c));
        $this->assertStringContainsString("Saisissez l'effectif de départ de la bande pour calculer", $this->texte($c));
        $this->assertStringNotContainsString('id="cat-eff-reproducteur"', $c->html());

        $c->set('achat', 3)->call('saveDay');

        $this->assertSame(0, LivestockDailyEntry::count(), 'rien ne s\'enregistre sans départ');
        $this->assertStringContainsString('id="ration-depart-requis"', $c->html());
        $this->assertStringNotContainsString('id="cat-eff-', $c->html(), 'jamais d\'effectif de catégorie inconnu (« — ») affiché sur cette fiche');
    }

    public function test_un_depart_incoherent_est_refuse(): void
    {
        $c = $this->departer($this->ouvrir(self::J1), 20, 30, 49);

        $this->assertStringContainsString('La somme des catégories de départ (99)', $this->texte($c));
        $c->call('saveDay');
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_la_proposition_du_stade_est_reprise_sur_demande_seulement(): void
    {
        $c = $this->ouvrir(self::J1);
        $c->assertSet('departRepro', null);

        $c->call('appliquerPropositionDepart')->assertSet('departRepro', 100)->assertSet('departSevre', 0)->assertSet('departJeune', 0);
    }

    public function test_les_champs_d_effectif_sont_calcules_en_direct_et_disabled(): void
    {
        $c = $this->departer($this->ouvrir(self::J1))->set('achat', 3);

        foreach (['cat-eff-reproducteur', 'cat-eff-jeune', 'cat-eff-poussin'] as $id) {
            $this->assertSame(1, preg_match('/<input\b[^>]*\bid="'.$id.'"[^>]*>/', $c->html(), $m));
            $this->assertMatchesRegularExpression('/\bdisabled\b/', $m[0]);
        }
        // Départ 20/30/50 + achat 3 (→ Jeune).
        $this->assertSame(['20', '33', '50'], [$this->affiche($c, 'cat-eff-reproducteur'), $this->affiche($c, 'cat-eff-jeune'), $this->affiche($c, 'cat-eff-poussin')]);
    }

    public function test_le_libelle_est_jeune_jamais_poulet_ni_jeune_a_maturite(): void
    {
        $texte = $this->texte($this->departer($this->ouvrir(self::J1)));

        $this->assertStringNotContainsString('Poulet', $texte);
        $this->assertStringNotContainsString('à maturité', $texte);
        $this->assertStringContainsString('Jeune', $texte);
        $this->assertSame(['Reproducteur', 'Poussin', 'Jeune', 'Ponte'], array_values(LivestockLot::stadesPourEspece('aviculture')));
    }

    public function test_enregistrement_ecrit_depart_mouvements_ventiles_et_categories_calculees(): void
    {
        $this->departer($this->ouvrir(self::J1))
            ->set('achat', 2)->set('poussinsNes', 10)
            ->set('mortRepro', 1)->set('mortPoulet', 2)->set('mortPoussin', 3)
            ->call('saveDay');

        $f = $this->entree(self::J1);
        $this->assertSame([20, 30, 50], [(int) $f->cat_depart_repro, (int) $f->cat_depart_jeune, (int) $f->cat_depart_sevre]);
        $this->assertSame([1, 2, 3, 6], [(int) $f->mort_repro, (int) $f->mort_jeune, (int) $f->mort_sevre, (int) $f->mort]);
        $this->assertSame(106, (int) $f->effectif_final);
        $this->assertSame([19, 30, 57], $this->stocke(self::J1));
        $this->assertSame(106, (int) $this->lot->fresh()->current_quantity);
    }

    public function test_jours_suivants_vente_passage_bornes_et_avertissement(): void
    {
        $this->scenarioComplet();

        $this->assertSame([18, 32, 46], $this->stocke(self::J2));
        $this->assertSame(96, (int) $this->entree(self::J2)->effectif_final);
        $j2 = $this->entree(self::J2);
        $this->assertSame([1, 2, 4, 7], [(int) $j2->vente_repro, (int) $j2->vente_jeune, (int) $j2->vente_sevre, (int) $j2->vente]);

        $this->assertSame([18, 32, 0], $this->stocke(self::J3));
        $this->assertSame(46, (int) $this->entree(self::J3)->effectif_final);

        $c = $this->ouvrir(self::J3);
        $this->assertStringContainsString("la somme des catégories (50) diffère de l'effectif total (46)", $this->texte($c));
    }

    public function test_provende_du_jour_est_la_somme_des_trois_categories(): void
    {
        $this->scenarioComplet();

        $c = $this->ouvrir(self::J2);
        // R18 × 130 = 2 340 ; J32 × 80 = 2 560 ; P46 × 30 = 1 380.
        $this->assertSame('2340 g', $this->cellule($c, 'cat-prov-reproducteur-g'));
        $this->assertSame('2560 g', $this->cellule($c, 'cat-prov-jeune-g'));
        $this->assertSame('1380 g', $this->cellule($c, 'cat-prov-poussin-g'));
        $this->assertSame('6280 g (6.28 Kg)', $this->cellule($c, 'day-total-provende-g'));
        $this->assertSame(6.28, $c->instance()->rationnement['total_kg']);
    }

    public function test_un_passage_superieur_a_la_source_est_refuse_a_l_enregistrement(): void
    {
        // Poussins 50 + éclosions 10 − morts 3 = 57 : un passage de 100 est refusé.
        $c = $this->departer($this->ouvrir(self::J1))->set('poussinsNes', 10)->set('mortPoussin', 3)->set('passage', 100);

        $this->assertStringContainsString("la catégorie source n'en compte que 57", $this->texte($c));
        $c->call('saveDay');
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_un_jour_anterieur_au_depart_n_est_pas_saisissable_et_n_affiche_aucun_inconnu(): void
    {
        $this->departer($this->ouvrir(self::J2))->call('saveDay');
        $c = $this->ouvrir(self::J1);

        $this->assertStringContainsString("Jour antérieur à l'effectif de départ", $this->texte($c));
        $c->set('achat', 1)->call('saveDay');
        $this->assertSame(1, LivestockDailyEntry::count(), 'le jour antérieur au départ ne s\'enregistre pas');
    }

    public function test_le_depart_est_verrouille_apres_le_premier_enregistrement(): void
    {
        $this->departer($this->ouvrir(self::J1))->call('saveDay');

        $c = $this->ouvrir(self::J2);
        $this->assertStringContainsString('Effectif de départ par catégorie (verrouillé)', $this->texte($c));
        $this->assertStringNotContainsString('Effectif de départ par catégorie (obligatoire)', $this->texte($c));
    }

    public function test_corriger_un_jour_passe_recalcule_les_jours_suivants(): void
    {
        $this->scenarioComplet();

        // J1 corrigé : 4 morts de Reproducteur au lieu de 1 (R16 au lieu de 19, total 103 au lieu de 106).
        $this->ouvrir(self::J1)->set('mortRepro', 4)->call('saveDay');

        $this->assertSame([16, 30, 57], $this->stocke(self::J1));
        $this->assertSame([15, 32, 46], $this->stocke(self::J2));     // R 16 − vente 1 = 15
        $this->assertSame(93, (int) $this->entree(self::J2)->effectif_final);
        $this->assertSame([15, 32, 0], $this->stocke(self::J3));
    }

    public function test_une_fiche_d_avant_le_ticket_non_ventilee_doit_etre_ventilee(): void
    {
        // Fiche d'avant VOL-1 : total des morts sans ventilation, sur un jour sans chaîne.
        LivestockDailyEntry::create([
            'lot_id' => $this->lot->id, 'entry_date' => self::J1, 'achat' => 0, 'ne' => 0, 'mort' => 4, 'vente' => 0, 'don' => 0, 'effectif_final' => 96,
        ]);

        $c = $this->departer($this->ouvrir(self::J1))->assertSet('mortEnregistre', 4);
        $c->call('saveDay');
        $this->assertNull($this->entree(self::J1)->cat_depart_repro, 'refusé tant que les morts ne sont pas ventilés');

        $c->set('mortRepro', 1)->set('mortPoulet', 1)->set('mortPoussin', 2)->call('saveDay');
        $this->assertSame([20, 30, 50], [(int) $this->entree(self::J1)->cat_depart_repro, (int) $this->entree(self::J1)->cat_depart_jeune, (int) $this->entree(self::J1)->cat_depart_sevre]);
    }

    // ===================================================================== (3) caisse : produit → catégorie

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

    public function test_caisse_la_vente_est_rangee_dans_la_categorie_du_produit(): void
    {
        $this->departEnBase();

        $this->vendreALaCaisse('poussin', 3, self::J2);
        $this->vendreALaCaisse('repro', 1, self::J2);

        $f = $this->entree(self::J2);
        $this->assertSame([4, 3, 0, 1], [(int) $f->vente, (int) $f->vente_sevre, (int) $f->vente_jeune, (int) $f->vente_repro]);
        // Poussins 50 − 3 = 47 ; Reproducteurs 20 − 1 = 19 ; Jeunes 30 ; départ J1 = 100 → 96.
        $this->assertSame([19, 30, 47], $this->stocke(self::J2));
        $this->assertSame(96, (int) $f->effectif_final);
    }

    public function test_caisse_un_produit_sans_categorie_est_refuse_avec_un_motif_clair_et_rien_n_est_ecrit(): void
    {
        $this->departEnBase();
        $avant = LivestockDailyEntry::count();

        $c = $this->vendreALaCaisse('sans', 2, self::J2);

        $c->assertDispatched('toast', message: "Vente refusée : le produit « Poulet braisé » n'a pas de catégorie d'effectif (Reproducteur, Jeune ou Poussin). Renseignez-la dans « Modifier un produit » avant de le vendre sur une bande de volailles reproductrices.", type: 'error');
        $this->assertSame($avant, LivestockDailyEntry::count());
        $this->assertSame(0, \App\Models\Sale::count());
        $this->assertSame('500.00', (string) $this->produits['sans']->fresh()->stock_qty);
    }

    public function test_caisse_une_bande_sans_depart_refuse_la_vente(): void
    {
        $c = $this->vendreALaCaisse('jeune', 2, self::J2);

        $c->assertDispatched('toast', message: "Vente refusée : l'effectif de départ par catégorie de la bande AVI-REP-01 n'est pas saisi. Ouvrez la fiche Volailles Reproducteurs et saisissez-le avant toute vente de cette bande.", type: 'error');
        $this->assertSame(0, \App\Models\Sale::count());
    }

    public function test_vente_antidatee_avant_le_depart_refusee_et_apres_recalcule_la_chaine(): void
    {
        $this->departer($this->ouvrir(self::J2))->call('saveDay');
        $this->ouvrir(self::J3)->call('saveDay');

        try {
            $this->vendre('jeune', 1, self::J1);
            $this->fail('une vente avant le départ doit être refusée');
        } catch (ValidationException $e) {
            $this->assertStringContainsString('précède l\'effectif de départ', $e->errors()['lines'][0]);
        }

        // Vente antidatée du jour J2 (2 jeunes) : J2 et J3 se recalculent. Départ 20/30/50 + J2 → J28 ; J3 = J28.
        $this->vendre('jeune', 2, self::J2);
        $this->assertSame([20, 28, 50], $this->stocke(self::J2));
        $this->assertSame([20, 28, 50], $this->stocke(self::J3));
        $this->assertSame(98, (int) $this->entree(self::J3)->effectif_final);
        $this->assertSame(98, (int) $this->lot->fresh()->current_quantity);
    }

    public function test_un_produit_de_categorie_inconnue_est_refuse_par_l_action(): void
    {
        $this->departEnBase();
        $this->produits['jeune']->update(['categorie_effectif' => null]);

        $refus = app(RecordSaleOnFicheElevageAction::class)->refusDesLignes(
            [['lot_id' => $this->lot->id, 'qty' => 1, 'product_id' => $this->produits['jeune']->id]], self::J2,
        );

        $this->assertStringContainsString('n\'a pas de catégorie d\'effectif', (string) $refus);
    }

    // ===================================================================== (4) rationnement : barème

    public function test_le_bareme_semé_porte_les_trois_lignes_provisoires_sans_toucher_aux_pondeuses(): void
    {
        FeedRationStandard::query()->delete();
        $this->seed(\Database\Seeders\FeedRationStandardsSeeder::class);

        $lignes = FeedRationStandard::where('species_code', 'aviculture')->pluck('ration_g_per_day', 'stage_label')->all();
        $this->assertSame(130, (int) $lignes['Reproducteur']);
        $this->assertSame(80, (int) $lignes['Jeune']);
        $this->assertSame(30, (int) $lignes['Poussin']);
        $this->assertSame(110, (int) $lignes['Pondeuse (6 à 18 mois)']);
        $this->assertSame(30, (int) $lignes['Poussin ponte (0 à 2 mois)']);
        $this->assertCount(7, $lignes);
    }

    public function test_les_cles_de_ration_sont_exactes_jamais_par_sous_chaine(): void
    {
        $this->assertSame(CategorieVolaille::POUSSIN, CategorieVolaille::cleDuLibelle('Poussin'));
        $this->assertSame(CategorieVolaille::JEUNE, CategorieVolaille::cleDuLibelle(' jeune '));
        $this->assertNull(CategorieVolaille::cleDuLibelle('Poussin ponte (0 à 2 mois)'));
        $this->assertNull(CategorieVolaille::cleDuLibelle('Pondeuse (6 à 18 mois)'));
        $this->assertNull(CategorieVolaille::cleDuLibelle('Jeune porc'));
    }

    public function test_une_ration_modifiee_dans_le_bareme_est_prise_en_compte(): void
    {
        FeedRationStandard::where('stage_label', 'Jeune')->update(['ration_g_per_day' => 100]);

        $t = CategorieVolaille::tableauReproducteurs(FeedRationStandard::where('species_code', 'aviculture')->get(), ['repro' => 1, 'sevre' => 2, 'jeune' => 3]);

        // 1 × 130 + 3 × 100 + 2 × 30 = 490.
        $this->assertSame(490, $t['total_g']);
        $this->assertSame(0.49, $t['total_kg']);
    }

    public function test_produits_par_defaut_d_apres_le_nom(): void
    {
        $this->assertSame('poussin', CategorieVolaille::devinerDepuisLeNom("Poussin d'un jour"));
        $this->assertSame('jeune', CategorieVolaille::devinerDepuisLeNom('Poulet goliath (sujet vif)'));
        $this->assertSame('jeune', CategorieVolaille::devinerDepuisLeNom('Poulet abattu frais'));
        $this->assertSame('reproducteur', CategorieVolaille::devinerDepuisLeNom('Coq reproducteur'));
        $this->assertSame('reproducteur', CategorieVolaille::devinerDepuisLeNom('Poule pondeuse réformée'));
        $this->assertNull(CategorieVolaille::devinerDepuisLeNom('Œufs de table (plateau)'));
        $this->assertNull(CategorieVolaille::devinerDepuisLeNom('Aliment démarrage (poussin) 25kg'));
        $this->assertNull(CategorieVolaille::devinerDepuisLeNom('Lapin vif'));
    }

    public function test_parametres_elevage_montre_et_enregistre_les_trois_rations(): void
    {
        $ecran = Livewire::test(\App\Livewire\Elevage\ParametresElevage::class);

        $lignes = $ecran->instance()->rations->where('species_code', 'aviculture')->pluck('ration_g_per_day', 'stage_label');
        $this->assertSame(['Jeune' => 80, 'Poussin' => 30, 'Reproducteur' => 130], $lignes->map(fn ($v) => (int) $v)->sortKeys()->all());

        $jeune = FeedRationStandard::where('species_code', 'aviculture')->where('stage_label', 'Jeune')->sole();
        $ecran->call('editRation', $jeune->id)->set('ration_grammes', 90)->call('saveRation')->assertHasNoErrors();

        $this->assertSame(90, (int) $jeune->fresh()->ration_g_per_day);
        // … et la fiche l'utilise : Jeunes 30 × 90 = 2 700 g (départ 20 / 30 / 50 : 20 × 130 + 30 × 90 + 50 × 30 = 6 800).
        $t = $this->departer($this->ouvrir(self::J1))->instance()->rationnement;
        $this->assertSame(6800, $t['total_g']);
    }
}
