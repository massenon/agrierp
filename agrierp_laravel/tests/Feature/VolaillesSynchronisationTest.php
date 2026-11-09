<?php

namespace Tests\Feature;

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
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket VOL-1 — SYNCHRONISATION des volailles reproductrices : colonnes `vente_*`, départ obligatoire, produit rangé
 * dans une catégorie d'effectif, motifs de refus français. Date figée au 14/10/2026 ; bande de 100, départ
 * Reproducteur 20 / Jeune 30 / Poussin 50. Valeurs attendues calculées à la main.
 */
class VolaillesSynchronisationTest extends TestCase
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
            'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true,
        ]);
        $this->utilisateur->assignRole('admin');

        FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
        foreach ([['411', 'Clients', 4], ['531', 'Caisse', 5], ['701', 'Ventes de marchandises', 7], ['443', 'TVA collectée', 4]] as [$code, $label, $classe]) {
            ChartOfAccount::create(['code' => $code, 'label' => $label, 'class' => $classe, 'is_active' => true]);
        }
        TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse Principale', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);

        $this->espece = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Aviculture', 'is_enabled' => true]);
        $this->bande = LivestockLot::create([
            'code' => 'AVI-REP-01', 'species_id' => $this->espece->id, 'stage' => 'reproduction',
            'initial_quantity' => 100, 'current_quantity' => 100, 'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);

        $categorie = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
        foreach (['poussin' => ["Poussin d'un jour", 'poussin'], 'jeune' => ['Poulet goliath (sujet vif)', 'jeune'], 'sans' => ['Poulet braisé', null]] as $cle => [$nom, $cat]) {
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

    private function uuid(): string
    {
        return sprintf('%08d-0000-4000-8000-000000000000', ++$this->n);
    }

    private function fiche(string $jour, array $en_plus = []): array
    {
        return array_merge([
            'id' => $this->uuid(), 'lot_id' => $this->bande->id, 'entry_date' => $jour,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0, 'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0,
            'vente_repro' => 0, 'vente_sevre' => 0, 'vente_jeune' => 0, 'passage_sevre_jeune' => 0,
        ], $en_plus);
    }

    private function depart(string $jour = '2026-10-10'): array
    {
        return $this->fiche($jour, ['cat_depart_repro' => 20, 'cat_depart_sevre' => 50, 'cat_depart_jeune' => 30]);
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

    private function vente(string $produit, int $qte, string $jour = '2026-10-12', ?string $id = null): array
    {
        return [
            'id' => $id ?? $this->uuid(), 'payment_mode' => 'especes', 'status' => 'validee', 'subtotal' => 1000 * $qte, 'discount' => 0,
            'total' => 1000 * $qte, 'sold_at' => $jour.' 10:00:00',
            'lines' => [['product_id' => $this->produits[$produit]->id, 'lot_id' => $this->bande->id, 'qty' => $qte, 'unit_price' => 1000, 'manual_total_amount' => 1000 * $qte]],
        ];
    }

    // ===================================================================== fiches : départ obligatoire

    public function test_une_fiche_sans_depart_sur_une_bande_de_volailles_est_refusee_avec_un_motif_clair(): void
    {
        $r = $this->pousser(['livestock_daily_entries' => [$this->fiche('2026-10-10')]])->assertOk();

        $this->assertSame([], $r->json('livestock_daily_entries.accepted'));
        $this->assertSame("Fiche refusée : l'effectif de départ par catégorie (Reproducteur, Jeune, Poussin) de la bande AVI-REP-01 n'est pas saisi. Saisissez-le d'abord sur la fiche Volailles Reproducteurs, puis renvoyez la fiche.", $this->motif($r));
        $this->assertSame(0, LivestockDailyEntry::count());
    }

    public function test_un_depart_accepte_calcule_les_categories_et_la_bande(): void
    {
        $f = $this->depart();
        $f2 = $this->fiche('2026-10-11', ['ne' => 10, 'achat' => 2, 'mort' => 3, 'mort_sevre' => 3]);
        $r = $this->pousser(['livestock_daily_entries' => [$f, $f2]])->assertOk();

        $this->assertSame([$f['id'], $f2['id']], $r->json('livestock_daily_entries.accepted'));
        // Départ 20/30/50 ; J2 : poussins 50 + 10 − 3 = 57 ; jeunes 30 + 2 = 32 ; total 100 + 12 − 3 = 109.
        $fiche2 = $this->enBase($f2['id']);
        $this->assertSame([20, 32, 57], [(int) $fiche2->cat_eff_repro, (int) $fiche2->cat_eff_jeune, (int) $fiche2->cat_eff_sevre]);
        $this->assertSame(109, (int) $fiche2->effectif_final);
        $this->assertSame(109, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_un_jour_anterieur_au_depart_est_refuse(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart('2026-10-10')]])->assertOk();

        $r = $this->pousser(['livestock_daily_entries' => [$this->fiche('2026-10-08')]])->assertOk();

        $this->assertSame("Fiche refusée : cette journée précède l'effectif de départ de la bande (fixé le 10/10/2026). Les jours antérieurs au départ ne sont pas saisissables.", $this->motif($r));
    }

    public function test_un_depart_different_de_l_effectif_total_est_refuse(): void
    {
        $f = $this->fiche('2026-10-10', ['cat_depart_repro' => 20, 'cat_depart_sevre' => 50, 'cat_depart_jeune' => 29]);

        $r = $this->pousser(['livestock_daily_entries' => [$f]])->assertOk();

        $this->assertSame("La somme des catégories de départ (99) ne correspond pas à l'effectif total au début du jour de départ (100).", $this->motif($r));
    }

    public function test_les_ventes_ventilees_sont_acceptees_et_leur_somme_doit_egaler_la_vente(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();

        $bonne = $this->fiche('2026-10-11', ['vente' => 7, 'vente_repro' => 1, 'vente_jeune' => 2, 'vente_sevre' => 4]);
        $this->pousser(['livestock_daily_entries' => [$bonne]])->assertOk()->assertJsonPath('livestock_daily_entries.accepted.0', $bonne['id']);
        // Reproducteurs 19, Jeunes 28, Poussins 46 ; total 93.
        $f = $this->enBase($bonne['id']);
        $this->assertSame([19, 28, 46, 93], [(int) $f->cat_eff_repro, (int) $f->cat_eff_jeune, (int) $f->cat_eff_sevre, (int) $f->effectif_final]);

        $fausse = $this->fiche('2026-10-12', ['vente' => 7, 'vente_repro' => 1, 'vente_jeune' => 2, 'vente_sevre' => 3]);
        $r = $this->pousser(['livestock_daily_entries' => [$fausse]])->assertOk();
        $this->assertSame('Ventilation incohérente : les ventes de la fiche (7) ne correspondent pas à la somme des trois catégories (6).', $this->motif($r));
    }

    public function test_une_ventilation_des_ventes_incomplete_est_refusee_en_francais(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();
        $f = $this->fiche('2026-10-11', ['vente' => 3]);
        unset($f['vente_jeune'], $f['vente_sevre']);

        $r = $this->pousser(['livestock_daily_entries' => [$f]])->assertOk();

        $this->assertSame('Ventilation incomplète : les trois catégories des ventes (Reproducteur, Jeune, Poussin) doivent être renseignées ensemble (0 si la catégorie est vide).', $this->motif($r));
    }

    public function test_un_ancien_poste_qui_envoie_une_vente_non_ventilee_est_refuse(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();
        $f = $this->fiche('2026-10-11', ['vente' => 3]);
        unset($f['vente_repro'], $f['vente_jeune'], $f['vente_sevre']);

        $r = $this->pousser(['livestock_daily_entries' => [$f]])->assertOk();

        $this->assertStringContainsString('les ventes de la fiche ne sont pas ventilés par catégorie', $this->motif($r));
    }

    // ===================================================================== ventes : produit → catégorie

    public function test_une_vente_du_poste_est_rangee_dans_la_categorie_du_produit_et_recalcule_la_chaine(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();
        $vente = $this->vente('poussin', 5, '2026-10-12');

        $r = $this->pousser(['sales' => [$vente]])->assertOk();

        $this->assertSame([$vente['id']], $r->json('sales.accepted'));
        $f = LivestockDailyEntry::where('entry_date', '2026-10-12')->sole();
        $this->assertSame([5, 5, 0, 0], [(int) $f->vente, (int) $f->vente_sevre, (int) $f->vente_jeune, (int) $f->vente_repro]);
        // Poussins 50 − 5 = 45 ; total 95.
        $this->assertSame([20, 30, 45, 95], [(int) $f->cat_eff_repro, (int) $f->cat_eff_jeune, (int) $f->cat_eff_sevre, (int) $f->effectif_final]);
    }

    public function test_une_vente_antidatee_recalcule_les_fiches_suivantes(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart('2026-10-10'), $this->fiche('2026-10-13')]])->assertOk();

        $this->pousser(['sales' => [$this->vente('jeune', 4, '2026-10-11')]])->assertOk();

        // 11/10 : jeunes 26, total 96 ; 13/10 reprend 96 et 26.
        $f13 = LivestockDailyEntry::where('entry_date', '2026-10-13')->sole();
        $this->assertSame([20, 26, 50, 96], [(int) $f13->cat_eff_repro, (int) $f13->cat_eff_jeune, (int) $f13->cat_eff_sevre, (int) $f13->effectif_final]);
        $this->assertSame(96, (int) $this->bande->fresh()->current_quantity);
    }

    public function test_une_vente_d_un_produit_sans_categorie_est_refusee_et_rien_n_est_ecrit(): void
    {
        $this->pousser(['livestock_daily_entries' => [$this->depart()]])->assertOk();
        $vente = $this->vente('sans', 2, '2026-10-12');

        $r = $this->pousser(['sales' => [$vente]])->assertOk();

        $this->assertSame([], $r->json('sales.accepted'));
        $this->assertSame("Vente refusée : le produit « Poulet braisé » n'a pas de catégorie d'effectif (Reproducteur, Jeune ou Poussin). Renseignez-la dans « Modifier un produit » avant de le vendre sur une bande de volailles reproductrices.", $this->motif($r, 'sales'));
        $this->assertSame(0, Sale::count());
        $this->assertSame(1, LivestockDailyEntry::count());
        $this->assertSame('500.00', (string) $this->produits['sans']->fresh()->stock_qty);
    }

    public function test_la_fiche_du_jour_portant_une_vente_refusee_est_retiree_de_ses_sujets_par_categorie(): void
    {
        // Le poste envoie la fiche du jour (qui porte déjà la vente de 2 jeunes) ET la vente, refusée (total incohérent) :
        // la fiche est rectifiée, ventilation comprise.
        $fiche = $this->fiche('2026-10-12', ['vente' => 2, 'vente_jeune' => 2]);
        $this->pousser(['livestock_daily_entries' => [$this->depart('2026-10-10')]])->assertOk();
        $vente = $this->vente('jeune', 2, '2026-10-12');
        $vente['total'] = 1;

        $this->pousser(['livestock_daily_entries' => [$fiche], 'sales' => [$vente]])->assertOk();

        $f = LivestockDailyEntry::where('entry_date', '2026-10-12')->sole();
        $this->assertSame([0, 0, 0, 0], [(int) $f->vente, (int) $f->vente_jeune, (int) $f->vente_sevre, (int) $f->vente_repro]);
        $this->assertSame([20, 30, 50, 100], [(int) $f->cat_eff_repro, (int) $f->cat_eff_jeune, (int) $f->cat_eff_sevre, (int) $f->effectif_final]);
        $this->assertSame(0, Sale::count());
    }

    public function test_la_categorie_introuvable_ne_fait_rien_deviner_a_la_rectification_de_la_fiche(): void
    {
        $fiche = $this->fiche('2026-10-12', ['vente' => 2, 'vente_jeune' => 2]);
        $this->pousser(['livestock_daily_entries' => [$this->depart('2026-10-10')]])->assertOk();

        $this->pousser(['livestock_daily_entries' => [$fiche], 'sales' => [$this->vente('sans', 2, '2026-10-12')]])->assertOk();

        $f = LivestockDailyEntry::where('entry_date', '2026-10-12')->sole();
        $this->assertSame([2, 2], [(int) $f->vente, (int) $f->vente_jeune], 'la somme reste cohérente, rien n\'est rangé au hasard');
        $this->assertSame(0, Sale::count());
    }

    // ===================================================================== produits

    public function test_le_tirage_sert_la_categorie_d_effectif_des_produits(): void
    {
        $r = $this->actingAs($this->utilisateur, 'sanctum')->getJson('/api/sync/pull')->assertOk();

        $parNom = collect($r->json('products'))->pluck('categorie_effectif', 'name');
        $this->assertSame('poussin', $parNom["Poussin d'un jour"]);
        $this->assertSame('jeune', $parNom['Poulet goliath (sujet vif)']);
        $this->assertNull($parNom['Poulet braisé']);
    }

    public function test_un_produit_cree_au_poste_garde_sa_categorie_d_effectif_seulement_en_aviculture(): void
    {
        $categorie = ProductCategory::first();
        $base = ['category_id' => $categorie->id, 'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 1000, 'price_max' => 2000,
            'tva_rate' => 0, 'alert_threshold' => 1, 'stock_qty' => 0];
        $coq = $base + ['id' => $this->uuid(), 'name' => 'Coq reproducteur', 'species_id' => $this->espece->id, 'categorie_effectif' => 'reproducteur'];
        $lapin = $base + ['id' => $this->uuid(), 'name' => 'Lapin vif', 'species_id' => null, 'categorie_effectif' => 'jeune'];
        $faux = $base + ['id' => $this->uuid(), 'name' => 'Poulet inconnu', 'species_id' => $this->espece->id, 'categorie_effectif' => 'canard'];

        $r = $this->pousser(['products' => [$coq, $lapin, $faux]])->assertOk();

        $this->assertSame([$coq['id'], $lapin['id']], $r->json('products.accepted'));
        $this->assertSame('reproducteur', Product::find($coq['id'])->categorie_effectif);
        $this->assertNull(Product::find($lapin['id'])->categorie_effectif, 'hors aviculture : toujours vide');
        $this->assertSame("La catégorie d'effectif doit être Reproducteur, Jeune ou Poussin (reproducteurs), ou l'un des quatre stades des pondeuses (Poussin ponte, Poussin en croissance, Poulette, Pondeuse).", $r->json('products.rejected.0.reason'));
    }

    public function test_un_poste_ancien_sans_la_cle_ne_touche_pas_la_categorie_du_produit(): void
    {
        $p = $this->produits['poussin'];
        $envoi = ['id' => $p->id, 'name' => $p->name, 'category_id' => $p->category_id, 'species_id' => $this->espece->id, 'unit' => 'u',
            'pricing_mode' => 'fourchette', 'price_min' => 600, 'price_max' => 900, 'tva_rate' => 0, 'alert_threshold' => 5];

        $this->pousser(['products' => [$envoi]])->assertOk()->assertJsonPath('products.accepted.0', $p->id);

        $this->assertSame('poussin', $p->fresh()->categorie_effectif);
    }

    public function test_le_formulaire_produit_propose_la_categorie_seulement_pour_l_aviculture(): void
    {
        $this->actingAs($this->utilisateur);

        $c = Livewire::test(AjouterProduit::class, ['product' => $this->produits['sans']->id]);
        $c->assertSee("Catégorie d'effectif", false)->assertSee('Reproducteur')->assertSee('Poussin');

        $c->set('categorie_effectif', 'jeune')->call('save')->assertHasNoErrors()->assertOk();
        $this->assertSame('jeune', $this->produits['sans']->fresh()->categorie_effectif);

        $c = Livewire::test(AjouterProduit::class, ['product' => $this->produits['sans']->id])->set('species_id', '');
        $c->assertDontSee("Catégorie d'effectif", false);
    }

    public function test_la_migration_pose_la_categorie_par_defaut_d_apres_le_nom(): void
    {
        $this->produits['sans']->update(['name' => "Poussin chair d'un jour", 'categorie_effectif' => null]);
        $this->produits['jeune']->update(['categorie_effectif' => null]);
        $this->produits['poussin']->update(['categorie_effectif' => 'reproducteur']);   // déjà posée : jamais réécrite

        $migration = require base_path('database/migrations/2026_11_05_000002_add_categorie_effectif_to_products_table.php');
        $migration->up();

        $this->assertSame('poussin', $this->produits['sans']->fresh()->categorie_effectif);
        $this->assertSame('jeune', $this->produits['jeune']->fresh()->categorie_effectif);
        $this->assertSame('reproducteur', $this->produits['poussin']->fresh()->categorie_effectif);
    }

    public function test_la_migration_du_bareme_n_ecrase_pas_une_ration_deja_ajustee_et_ne_touche_pas_aux_pondeuses(): void
    {
        \App\Models\FeedRationStandard::where('species_code', 'aviculture')->delete();
        \App\Models\FeedRationStandard::create(['species_code' => 'aviculture', 'stage_label' => 'Jeune', 'ration_g_per_day' => 95]);
        \App\Models\FeedRationStandard::create(['species_code' => 'aviculture', 'stage_label' => 'Pondeuse (6 à 18 mois)', 'ration_g_per_day' => 110]);

        $migration = require base_path('database/migrations/2026_11_05_000003_ajouter_rations_reproducteurs_volaille.php');
        $migration->up();
        $migration->up();

        $lignes = \App\Models\FeedRationStandard::where('species_code', 'aviculture')->pluck('ration_g_per_day', 'stage_label')->all();
        ksort($lignes);
        $this->assertSame(['Jeune' => 95, 'Pondeuse (6 à 18 mois)' => 110, 'Poussin' => 30, 'Reproducteur' => 130], array_map('intval', $lignes));
    }
}
