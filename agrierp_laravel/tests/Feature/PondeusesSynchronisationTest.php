<?php

namespace Tests\Feature;

use App\Actions\TransferBetweenLotsAction;
use App\Livewire\Stocks\AjouterProduit;
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Sale;
use App\Models\TreasuryAccount;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket VOL-2 — SYNCHRONISATION des volailles pondeuses : colonnes du quatrième emplacement (`*_4`) et des passages, départ
 * obligatoire par stade, produit rangé dans un stade, motifs de refus français. Date figée au 14/10/2026 ; bande de 100,
 * départ Poussin ponte 10 / Poussin en croissance 20 / Poulette 30 / Pondeuse 40. Valeurs attendues calculées à la main.
 */
class PondeusesSynchronisationTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    private LivestockSpecies $espece;

    private LivestockLot $bande;

    private int $n = 0;

    /** @var array<string, Product> */
    private array $produits = [];

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-14 12:00:00');

        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);
        $this->utilisateur = User::create([
            'name' => 'Directeur', 'username' => 'dg', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->utilisateur->assignRole('admin');

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        foreach ([['411', 'Clients', 4], ['531', 'Caisse', 5], ['701', 'Ventes de marchandises', 7], ['443', 'TVA collectée', 4]] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        $this->espece = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Aviculture', 'is_enabled' => true]);
        $this->bande = $this->bande('AVI-PON-01');

        $categorie = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
        foreach (['pp' => ["Poussin d'un jour (ponte)", 'poussin_ponte'], 'pl' => ['Poulette (sujet vif)', 'poulette'], 'po' => ['Poule de réforme', 'pondeuse'], 'sans' => ['Poulet braisé', null]] as $cle => [$nom, $cat]) {
            $this->produits[$cle] = Product::create([
                'sku' => 'AVI-'.strtoupper($cle), 'name' => $nom, 'category_id' => $categorie->id, 'unit' => 'u', 'pricing_mode' => 'fourchette',
                'price_min' => 1000, 'price_max' => 5000, 'stock_qty' => 500, 'species_id' => $this->espece->id, 'is_active' => true, 'categorie_effectif' => $cat,
            ]);
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function bande(string $code, int $effectif = 100): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $this->espece->id, 'stage' => 'ponte',
            'initial_quantity' => $effectif, 'current_quantity' => $effectif, 'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function uuid(): string
    {
        return sprintf('%08d-0000-4000-8000-000000000000', ++$this->n);
    }

    private function fiche(string $jour, array $en_plus = []): array
    {
        return array_merge([
            'id' => $this->uuid(), 'lot_id' => $this->bande->id, 'entry_date' => $jour,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0, 'mort_4' => 0,
            'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0, 'don_4' => 0,
            'vente_repro' => 0, 'vente_sevre' => 0, 'vente_jeune' => 0, 'vente_4' => 0,
            'passage_4_sevre' => 0, 'passage_sevre_jeune' => 0, 'passage_jeune_repro' => 0,
        ], $en_plus);
    }

    private function depart(string $jour = '2026-10-10'): array
    {
        return $this->fiche($jour, ['cat_depart_repro' => 40, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30, 'cat_depart_4' => 10]);
    }

    private function pousser(array $corps)
    {
        return $this->actingAs($this->utilisateur, 'sanctum')->postJson('/api/sync/push', $corps);
    }

    private function motif($reponse, string $table = 'livestock_daily_entries'): string
    {
        return (string) $reponse->json("{$table}.rejected.0.reason");
    }

    private function enBase(string $id): LivestockDailyEntry
    {
        return LivestockDailyEntry::findOrFail($id);
    }

    /** @return array{int, int, int, int} cat_eff Poussin ponte, Poussin en croissance, Poulette, Pondeuse STOCKÉS. */
    private function stades(LivestockDailyEntry $f): array
    {
        return [(int) $f->cat_eff_4, (int) $f->cat_eff_sevre, (int) $f->cat_eff_jeune, (int) $f->cat_eff_repro];
    }

    private function vente(string $produit, int $qte, string $jour = '2026-10-12'): array
    {
        return [
            'id' => $this->uuid(), 'payment_mode' => 'especes', 'status' => 'validee', 'subtotal' => 1000 * $qte, 'discount' => 0,
            'total' => 1000 * $qte, 'sold_at' => $jour.' 10:00:00',
            'lines' => [['product_id' => $this->produits[$produit]->id, 'lot_id' => $this->bande->id, 'qty' => $qte, 'unit_price' => 1000, 'manual_total_amount' => 1000 * $qte]],
        ];
    }

    // ===================================================================== fiches : départ obligatoire

    public function test_une_fiche_sans_depart_sur_une_bande_de_pondeuses_est_refusee_avec_un_motif_clair(): void
    {
        $r = $this->pousser(['livestock_daily_entries' => [$this->fiche('2026-10-10')]])->assertOk();

        $this->assertSame([], $r->json('livestock_daily_entries.accepted'));
        $this->assertSame("Fiche refusée : l'effectif de départ par stade (Poussin ponte, Poussin en croissance, Poulette, Pondeuse) de la bande AVI-PON-01 n'est pas saisi. Saisissez-le d'abord sur la fiche Pondeuses, puis renvoyez la fiche.", $this->motif($r));
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_un_depart_accepte_calcule_les_stades_et_la_bande(): void
    {
        $f = $this->depart();
        $f2 = $this->fiche('2026-10-11', [
            'ne' => 6, 'achat' => 2, 'mort' => 3, 'mort_4' => 1, 'mort_jeune' => 2,
            'passage_4_sevre' => 4, 'passage_sevre_jeune' => 5, 'passage_jeune_repro' => 6,
        ]);
        $r = $this->pousser(['livestock_daily_entries' => [$f, $f2]])->assertOk();

        $this->assertSame([$f['id'], $f2['id']], $r->json('livestock_daily_entries.accepted'));
        // PP 10+6−1−4 = 11 · PC 20+4−5 = 19 · PL 30+2+5−2−6 = 29 · PO 40+6 = 46 : total 105 = 100 + 8 − 3.
        $fiche2 = $this->enBase($f2['id']);
        $this->assertSame([11, 19, 29, 46], $this->stades($fiche2));
        $this->assertSame(105, (int) $fiche2->effectif_final);
        $this->assertSame(105, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_cat_eff_4_envoye_par_un_poste_n_est_pas_ecrit_il_est_derive(): void
    {
        $f = $this->depart();
        $f['cat_eff_4'] = 77;
        $this->pousser(['livestock_daily_entries' => [$f]])->assertOk();

        $this->assertSame(10, (int) $this->enBase($f['id'])->cat_eff_4);
    }

    public function test_un_jour_anterieur_au_depart_est_refuse(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart('2026-10-10')]])->assertOk();

        $r = $this->pousser(['livestock_daily_entries' => [$this->fiche('2026-10-08')]])->assertOk();

        $this->assertSame("Fiche refusée : cette journée précède l'effectif de départ de la bande (fixé le 10/10/2026). Les jours antérieurs au départ ne sont pas saisissables.", $this->motif($r));
    }

    public function test_un_depart_different_de_l_effectif_total_est_refuse(): void
    {
        $f = $this->fiche('2026-10-10', ['cat_depart_repro' => 40, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30, 'cat_depart_4' => 9]);

        $r = $this->pousser(['livestock_daily_entries' => [$f]])->assertOk();

        $this->assertSame("La somme des stades de départ (99) ne correspond pas à l'effectif total au début du jour de départ (100).", $this->motif($r));
    }

    public function test_un_depart_a_trois_colonnes_est_refuse_comme_incomplet(): void
    {
        $f = $this->fiche('2026-10-10', ['cat_depart_repro' => 40, 'cat_depart_sevre' => 30, 'cat_depart_jeune' => 30]);

        $r = $this->pousser(['livestock_daily_entries' => [$f]])->assertOk();

        $this->assertSame('Effectif de départ incomplet : les quatre stades doivent être renseignés (0 si le stade est vide).', $this->motif($r));
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_les_ventes_ventilees_sont_acceptees_et_leur_somme_doit_egaler_la_vente(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();

        $bonne = $this->fiche('2026-10-11', ['vente' => 7, 'vente_4' => 1, 'vente_sevre' => 2, 'vente_jeune' => 3, 'vente_repro' => 1]);
        $this->pousser(['livestock_daily_entries' => [$bonne]])->assertOk()->assertJsonPath('livestock_daily_entries.accepted.0', $bonne['id']);
        // PP 9 · PC 18 · PL 27 · PO 39 ; total 93.
        $f = $this->enBase($bonne['id']);
        $this->assertSame([9, 18, 27, 39, 93], [...$this->stades($f), (int) $f->effectif_final]);

        $fausse = $this->fiche('2026-10-12', ['vente' => 7, 'vente_4' => 1, 'vente_sevre' => 2, 'vente_jeune' => 3, 'vente_repro' => 0]);
        $r = $this->pousser(['livestock_daily_entries' => [$fausse]])->assertOk();
        $this->assertSame('Ventilation incohérente : les ventes de la fiche (7) ne correspondent pas à la somme des quatre stades (6).', $this->motif($r));
    }

    public function test_une_ventilation_a_trois_colonnes_est_refusee_en_francais(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();
        $f = $this->fiche('2026-10-11', ['mort' => 3]);
        unset($f['mort_4']);

        $r = $this->pousser(['livestock_daily_entries' => [$f]])->assertOk();

        $this->assertSame('Ventilation incomplète : les quatre stades des morts (Poussin ponte, Poussin en croissance, Poulette, Pondeuse) doivent être renseignés ensemble (0 si le stade est vide).', $this->motif($r));
    }

    public function test_un_passage_superieur_a_son_stade_source_est_refuse(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();

        $r = $this->pousser(['livestock_daily_entries' => [$this->fiche('2026-10-11', ['passage_jeune_repro' => 31])]])->assertOk();

        $this->assertSame("Passage de stade refusé (Poulette (4 à 5.5 mois) vers Pondeuse (6 à 18 mois)) : 31 sujet(s) à faire passer, mais le stade source n'en compte que 30.", $this->motif($r));
    }

    // ===================================================================== ventes : produit → stade

    public function test_une_vente_du_poste_est_rangee_dans_le_stade_du_produit_et_recalcule_la_chaine(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();
        $vente = $this->vente('po', 5, '2026-10-12');

        $r = $this->pousser(['sales' => [$vente]])->assertOk();

        $this->assertSame([$vente['id']], $r->json('sales.accepted'));
        $f = LivestockDailyEntry::where('entry_date', '2026-10-12')->sole();
        $this->assertSame([5, 5, 0, 0, 0], [(int) $f->vente, (int) $f->vente_repro, (int) $f->vente_sevre, (int) $f->vente_jeune, (int) $f->vente_4]);
        // Pondeuse 40 − 5 = 35 ; total 95.
        $this->assertSame([10, 20, 30, 35, 95], [...$this->stades($f), (int) $f->effectif_final]);
    }

    public function test_une_vente_de_poussin_ponte_sort_du_quatrieme_emplacement(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();

        $this->pousser(['sales' => [$this->vente('pp', 4, '2026-10-12')]])->assertOk();

        $f = LivestockDailyEntry::where('entry_date', '2026-10-12')->sole();
        $this->assertSame([4, 4], [(int) $f->vente, (int) $f->vente_4]);
        $this->assertSame([6, 20, 30, 40], $this->stades($f));
    }

    public function test_une_vente_antidatee_recalcule_les_fiches_suivantes(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart('2026-10-10'), $this->fiche('2026-10-13')]])->assertOk();

        $this->pousser(['sales' => [$this->vente('pl', 4, '2026-10-11')]])->assertOk();

        // 11/10 : Poulette 26, total 96 ; 13/10 reprend 96 et 26.
        $f13 = LivestockDailyEntry::where('entry_date', '2026-10-13')->sole();
        $this->assertSame([10, 20, 26, 40, 96], [...$this->stades($f13), (int) $f13->effectif_final]);
        $this->assertSame(96, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_une_vente_d_un_produit_sans_stade_est_refusee_et_rien_n_est_ecrit(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();

        $r = $this->pousser(['sales' => [$this->vente('sans', 2, '2026-10-12')]])->assertOk();

        $this->assertSame([], $r->json('sales.accepted'));
        $this->assertSame("Vente refusée : le produit « Poulet braisé » n'a pas de stade d'effectif de pondeuses (Poussin ponte, Poussin en croissance, Poulette ou Pondeuse). Renseignez-le dans « Modifier un produit » avant de le vendre sur une bande de pondeuses.", $this->motif($r, 'sales'));
        $this->assertSame(0, Sale::count());
        $this->assertSame(1, LivestockDailyEntry::count());
        $this->assertSame('500.00', (string) $this->produits['sans']->fresh()->stock_qty);
    }

    public function test_une_vente_sans_depart_est_refusee(): void
    {
        $r = $this->pousser(['sales' => [$this->vente('po', 2, '2026-10-12')]])->assertOk();

        $this->assertSame("Vente refusée : l'effectif de départ par stade de la bande AVI-PON-01 n'est pas saisi. Ouvrez la fiche Pondeuses et saisissez-le avant toute vente de cette bande.", $this->motif($r, 'sales'));
    }

    public function test_la_fiche_du_jour_portant_une_vente_refusee_est_retiree_de_son_stade(): void
    {
        $fiche = $this->fiche('2026-10-12', ['vente' => 2, 'vente_4' => 2]);
        $this->pousser(['livestock_daily_entries' => [$this->depart('2026-10-10')]])->assertOk();
        $vente = $this->vente('pp', 2, '2026-10-12');
        $vente['total'] = 1;

        $this->pousser(['livestock_daily_entries' => [$fiche], 'sales' => [$vente]])->assertOk();

        $f = LivestockDailyEntry::where('entry_date', '2026-10-12')->sole();
        $this->assertSame([0, 0], [(int) $f->vente, (int) $f->vente_4]);
        $this->assertSame([10, 20, 30, 40, 100], [...$this->stades($f), (int) $f->effectif_final]);
        $this->assertSame(0, Sale::count());
    }

    // ===================================================================== transferts entre bandes

    public function test_un_transfert_de_pondeuses_exige_le_stade_et_accepte_le_quatrieme_emplacement(): void
    {
        $cible = $this->bande('AVI-PON-02', 0);
        $this->pousser(['livestock_daily_entries' => [$this->depart('2026-10-10')]])->assertOk();

        try {
            app(TransferBetweenLotsAction::class)->execute([
                'source_lot_id' => $this->bande->id, 'target_lot_id' => $cible->id, 'transfer_date' => '2026-10-12', 'quantity' => 3,
            ]);
            $this->fail('le stade est obligatoire');
        } catch (ValidationException $e) {
            $this->assertStringContainsString('précisez la catégorie (le stade, pour les pondeuses)', $e->errors()['transfert'][0]);
        }

        app(TransferBetweenLotsAction::class)->execute([
            'source_lot_id' => $this->bande->id, 'target_lot_id' => $cible->id, 'transfer_date' => '2026-10-12', 'quantity' => 3, 'categorie' => 'quatre',
        ]);

        $f = LivestockDailyEntry::where('lot_id', $this->bande->id)->whereDate('entry_date', '2026-10-12')->sole();
        $this->assertSame([3, 97], [(int) $f->transfert_sortie_4, (int) $f->effectif_final]);
        $this->assertSame([7, 20, 30, 40], $this->stades($f));
    }

    // ===================================================================== produits

    public function test_le_formulaire_produit_propose_les_quatre_stades_aux_libelles_du_bareme(): void
    {
        $this->actingAs($this->utilisateur);

        $c = Livewire::test(AjouterProduit::class, ['product' => $this->produits['sans']->id]);
        $c->assertSee('Poussin ponte (0 à 2 mois)')->assertSee('Poussin en croissance (2 à 4 mois)')->assertSee('Poulette (4 à 5.5 mois)')->assertSee('Pondeuse (6 à 18 mois)');

        $c->set('categorie_effectif', 'poulette')->call('save')->assertHasNoErrors();
        $this->assertSame('poulette', $this->produits['sans']->fresh()->categorie_effectif);
    }

    public function test_un_produit_cree_au_poste_garde_son_stade_de_pondeuse(): void
    {
        $categorie = ProductCategory::first();
        $base = ['category_id' => $categorie->id, 'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 1000, 'price_max' => 2000,
            'tva_rate' => 0, 'alert_threshold' => 1, 'stock_qty' => 0, 'species_id' => $this->espece->id];
        $pl = $base + ['id' => $this->uuid(), 'name' => 'Poulette', 'categorie_effectif' => 'poulette'];

        $r = $this->pousser(['products' => [$pl]])->assertOk();

        $this->assertSame([$pl['id']], $r->json('products.accepted'));
        $this->assertSame('poulette', Product::find($pl['id'])->categorie_effectif);
    }

    public function test_le_tirage_sert_le_stade_des_produits_et_les_colonnes_des_fiches(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();
        $r = $this->actingAs($this->utilisateur, 'sanctum')->getJson('/api/sync/pull')->assertOk();

        $parNom = collect($r->json('products'))->pluck('categorie_effectif', 'name');
        $this->assertSame('pondeuse', $parNom['Poule de réforme']);
        $fiche = $r->json('livestock_daily_entries.0');
        foreach (['mort_4', 'don_4', 'vente_4', 'cat_depart_4', 'cat_eff_4', 'passage_4_sevre', 'passage_jeune_repro', 'transfert_entree_4', 'transfert_sortie_4'] as $cle) {
            $this->assertArrayHasKey($cle, $fiche, "la colonne {$cle} est servie au poste");
        }
        $this->assertSame(10, $fiche['cat_depart_4']);
    }
}
