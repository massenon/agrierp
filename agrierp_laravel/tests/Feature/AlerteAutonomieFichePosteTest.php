<?php

namespace Tests\Feature;

use App\Livewire\Elevage\FicheLapins;
use App\Livewire\Elevage\FichePorcs;
use App\Models\FeedRationStandard;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Notification;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket U13 — L'ALERTE D'AUTONOMIE ALIMENTAIRE (cloche) EST LEVÉE AUSSI POUR UNE FICHE REÇUE D'UN POSTE.
 *
 * Au web, `saveDay()` des fiches Lapins et Porcs lève `RaiseFeedAutonomyAlertAction` ; une fiche envoyée par un poste
 * (`/api/sync/push`) ne la levait pas. Verrouillé ici :
 *  - **parité** : la MÊME journée, enregistrée au web (vrai composant Livewire) sur une bande et envoyée par un poste
 *    sur une bande jumelle, produit la MÊME notification (type, gravité, titre, message, lien, rôle) — et le message
 *    attendu est un LITTÉRAL calculé à la main ;
 *  - **dédoublonnage** : une fiche RENVOYÉE (accusé perdu) ne crée pas une deuxième alerte ; une alerte déjà levée au web
 *    le même jour non plus ;
 *  - **mêmes exclusions qu'au web** : provende inconnue (bande sans départ : catégories inconnues), fiche née d'une
 *    vente (le comptoir du web ne lève rien), compte sans `manage-elevage` (la fiche n'est qu'une vente), autre espèce.
 *
 * Lapins : départ Reproducteur 10 / Sous-mères 20 / Jeune 30 (60), rations 120 / 30 / 60 g. Journée : 2 achetés et
 * 5 nés (Sous-mères, D11 : 27), 1 mort Jeune (29) → provende 10×120 + 27×30 + 29×60 = 3 750 g = 3,75 kg/j. Stock de
 * provende 10 kg → autonomie round(10 ÷ 3,75, 1) = 2,7 jours (≤ 3 : alerte « moyen », « 3,8 kg » affichés).
 */
class AlerteAutonomieFichePosteTest extends TestCase
{
    use RefreshDatabase;

    private const JOUR = '2026-10-13';

    private const MESSAGE_LAPINS = 'Autonomie restante : 2,7 jours — 10 kg en stock pour 3,8 kg consommés par jour. '
        .'Réapprovisionnez avant rupture.';

    private User $animalier;

    private LivestockSpecies $lapins;

    private Product $provende;

    private int $n = 0;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-14 12:00:00');
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $this->animalier = $this->compte('animalier');
        $this->lapins = LivestockSpecies::create(['code' => 'cuniculture', 'label' => 'Lapins', 'is_enabled' => true]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Reproducteur', 'ration_g_per_day' => 120]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Sous-mères', 'ration_g_per_day' => 30]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Jeune', 'ration_g_per_day' => 60]);

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        $this->provende = Product::create([
            'sku' => 'ALI-LAP', 'name' => 'Provende lapins', 'category_id' => $categorie->id, 'unit' => 'kg',
            'pricing_mode' => 'fourchette', 'price_min' => 300, 'price_max' => 350, 'stock_qty' => 10,
            'is_active' => true, 'species_id' => $this->lapins->id,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function compte(string $role): User
    {
        $u = User::create([
            'name' => 'Compte '.$role, 'username' => $role.'-u13', 'email' => $role.'-u13@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole($role);

        return $u;
    }

    private function bande(LivestockSpecies $espece, string $code): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $espece->id, 'stage' => 'croissance', 'initial_quantity' => 60,
            'current_quantity' => 60, 'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ]);
    }

    /** La journée de référence au web (vrai composant), départ compris. */
    private function enregistrerAuWeb(LivestockLot $bande): void
    {
        $this->actingAs($this->animalier);
        Livewire::test(FicheLapins::class)
            ->set('bandeId', $bande->id)
            ->set('selectedDate', self::JOUR)
            ->set('departRepro', 10)->set('departSevre', 20)->set('departJeune', 30)
            ->set('achat', 2)->set('ne', 5)->set('mortChair', 1)
            ->call('saveDay')
            ->assertHasNoErrors();
    }

    /** La même journée, telle que le poste l'envoie (fiche Lapins du poste, tête de chaîne). */
    private function ficheDuPoste(LivestockLot $bande, array $enPlus = []): array
    {
        return array_merge([
            'id' => sprintf('%08d-0000-4000-8000-0000000000aa', ++$this->n), 'lot_id' => $bande->id, 'entry_date' => self::JOUR,
            'achat' => 2, 'ne' => 5, 'mort' => 1, 'vente' => 0, 'don' => 0,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 1, 'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0,
            'passage_sevre_jeune' => 0, 'cat_depart_repro' => 10, 'cat_depart_sevre' => 20, 'cat_depart_jeune' => 30,
            'feed_qty_kg' => 3.75,
        ], $enPlus);
    }

    private function pousser(array $fiches, ?User $compte = null)
    {
        return $this->actingAs($compte ?? $this->animalier, 'sanctum')
            ->postJson('/api/sync/push', ['livestock_daily_entries' => $fiches])
            ->assertOk();
    }

    /** @return array<string, mixed> ce que la cloche affiche d'une alerte */
    private function alerte(Notification $n): array
    {
        return $n->only(['type', 'severity', 'title', 'message', 'link_url', 'target_role', 'is_read']);
    }

    public function test_la_meme_journee_au_web_et_au_poste_leve_la_meme_alerte(): void
    {
        $this->enregistrerAuWeb($this->bande($this->lapins, 'LAP-WEB'));
        $web = Notification::where('type', 'stock_low')->sole();
        $this->assertSame(self::MESSAGE_LAPINS, $web->message, 'littéral calculé à la main');
        $this->assertSame('moyen', $web->severity);
        $this->assertSame('Stock Provende lapins bas', $web->title);

        // Le dédoublonnage du jour est celui du web : on repart d'une cloche vide pour comparer.
        Notification::query()->delete();

        $reponse = $this->pousser([$this->ficheDuPoste($this->bande($this->lapins, 'LAP-POSTE'))]);
        $this->assertCount(1, $reponse->json('livestock_daily_entries.accepted'));
        $poste = Notification::where('type', 'stock_low')->sole();

        $this->assertSame($this->alerte($web), $this->alerte($poste));
    }

    public function test_une_fiche_renvoyee_ne_cree_pas_une_seconde_alerte(): void
    {
        $fiche = $this->ficheDuPoste($this->bande($this->lapins, 'LAP-A'));
        $this->pousser([$fiche]);
        $this->assertSame(1, Notification::where('type', 'stock_low')->count());

        // Accusé perdu : le poste renvoie la même fiche, puis une correction de la même journée.
        $this->pousser([$fiche]);
        $this->pousser([array_merge($fiche, ['feed_qty_kg' => 3.76])]);
        $this->assertSame(1, Notification::where('type', 'stock_low')->count());
    }

    public function test_une_alerte_deja_levee_au_web_le_meme_jour_n_est_pas_dupliquee(): void
    {
        $this->enregistrerAuWeb($this->bande($this->lapins, 'LAP-WEB'));
        $this->pousser([$this->ficheDuPoste($this->bande($this->lapins, 'LAP-POSTE'))]);

        $this->assertSame(1, Notification::where('type', 'stock_low')->count());
    }

    public function test_stock_suffisant_l_alerte_ouverte_se_resorbe_comme_au_web(): void
    {
        $this->pousser([$this->ficheDuPoste($this->bande($this->lapins, 'LAP-A'))]);
        $this->assertFalse(Notification::where('type', 'stock_low')->sole()->is_read);

        // Réapprovisionné : 100 kg pour 3,75 kg/j = 26,7 jours. La fiche suivante résorbe l'alerte ouverte.
        $this->provende->update(['stock_qty' => 100]);
        $this->pousser([$this->ficheDuPoste($this->bande($this->lapins, 'LAP-B'))]);

        $this->assertTrue(Notification::where('type', 'stock_low')->sole()->is_read);
    }

    public function test_provende_inconnue_bande_sans_depart_aucune_alerte_ni_au_web_ni_au_poste(): void
    {
        $this->actingAs($this->animalier);
        Livewire::test(FicheLapins::class)
            ->set('bandeId', $this->bande($this->lapins, 'LAP-WEB')->id)
            ->set('selectedDate', self::JOUR)
            ->set('achat', 2)->set('ne', 5)->set('mortChair', 1)
            ->call('saveDay');
        $this->assertSame(0, Notification::where('type', 'stock_low')->count(), 'web');

        $sansDepart = $this->ficheDuPoste($this->bande($this->lapins, 'LAP-POSTE'), ['feed_qty_kg' => null]);
        unset($sansDepart['cat_depart_repro'], $sansDepart['cat_depart_sevre'], $sansDepart['cat_depart_jeune']);
        $this->pousser([$sansDepart]);
        $this->assertSame(0, Notification::where('type', 'stock_low')->count(), 'poste');
    }

    /**
     * D6 — une bande SANS chaîne garde ses anciens effectifs de catégorie saisis à la main (`cat_eff_*`) : ce ne sont
     * pas des effectifs calculés, la fiche web les ignore (catégories inconnues → aucune alerte). Le serveur ne doit
     * pas s'en servir non plus.
     */
    public function test_bande_sans_chaine_les_anciennes_categories_manuelles_ne_levent_rien(): void
    {
        $bande = $this->bande($this->lapins, 'LAP-D6');
        $ancienne = new \App\Models\LivestockDailyEntry([
            'lot_id' => $bande->id, 'entry_date' => self::JOUR, 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0,
            'don' => 0, 'cat_eff_repro' => 10, 'cat_eff_sevre' => 27, 'cat_eff_jeune' => 29,
        ]);
        $ancienne->id = '00000066-0000-4000-8000-0000000000aa';
        $ancienne->effectif_final = 66;
        $ancienne->save();

        $fiche = $this->ficheDuPoste($bande, ['id' => $ancienne->id]);
        unset($fiche['cat_depart_repro'], $fiche['cat_depart_sevre'], $fiche['cat_depart_jeune']);
        $this->pousser([$fiche]);

        $this->assertNotNull($ancienne->fresh()->cat_eff_repro, 'témoin : les catégories manuelles sont toujours là');
        $this->assertSame(0, Notification::where('type', 'stock_low')->count());
    }

    public function test_une_fiche_nee_d_une_vente_ou_d_un_compte_de_vente_ne_leve_rien(): void
    {
        $bande = $this->bande($this->lapins, 'LAP-A');
        // La chaîne existe (départ en base, comme après une saisie de l'éleveur) : seule la nature de la fiche joue.
        $this->pousser([$this->ficheDuPoste($bande, ['entry_date' => '2026-10-12'])]);
        Notification::query()->delete();

        // Fiche née d'une vente au comptoir (compte administrateur : seule la vente, aucune provende).
        $this->pousser([[
            'id' => '00000077-0000-4000-8000-0000000000aa', 'lot_id' => $bande->id, 'entry_date' => self::JOUR,
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 2, 'don' => 0,
        ]], $this->compte('admin'));
        $this->assertSame(0, Notification::where('type', 'stock_low')->count(), 'fiche née d\'une vente');

        // Compte de vente (sans manage-elevage) : la fiche n'est qu'une vente.
        $this->pousser([[
            'id' => '00000078-0000-4000-8000-0000000000aa', 'lot_id' => $bande->id, 'entry_date' => '2026-10-14',
            'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 1, 'don' => 0,
        ]], $this->compte('caissier'));
        $this->assertSame(0, Notification::where('type', 'stock_low')->count(), 'compte de vente');
    }

    public function test_porcs_la_meme_journee_au_web_et_au_poste_leve_la_meme_alerte(): void
    {
        $porcs = LivestockSpecies::create(['code' => 'porciculture', 'label' => 'Porcs', 'is_enabled' => true]);
        $categorie = ProductCategory::create(['label' => 'Aliments porcs', 'is_active' => true]);
        Product::create([
            'sku' => 'ALI-POR', 'name' => 'Aliment porcs', 'category_id' => $categorie->id, 'unit' => 'kg',
            'pricing_mode' => 'fourchette', 'price_min' => 300, 'price_max' => 350, 'stock_qty' => 50,
            'is_active' => true, 'species_id' => $porcs->id,
        ]);

        // Rations de secours (aucun barème porcs) : Reproducteur 2 000, Porcelet 300, Marchand 600 g. Départ 4 / 36 / 20
        // (60), 4 porcelets nés (40) → 4×2000 + 40×300 + 20×600 = 32 000 g = 32 kg/j ; 50 kg → 1,6 jour (« jour » au
        // singulier sous 2, gravité « moyen » au-dessus d'un jour).
        $this->actingAs($this->animalier);
        Livewire::test(FichePorcs::class)
            ->set('bandeId', $this->bande($porcs, 'POR-WEB')->id)
            ->set('selectedDate', self::JOUR)
            ->set('departRepro', 4)->set('departSevre', 36)->set('departJeune', 20)
            ->set('ne', 4)
            ->call('saveDay')
            ->assertHasNoErrors();
        $web = Notification::where('type', 'stock_low')->sole();
        $this->assertSame('Autonomie restante : 1,6 jour — 50 kg en stock pour 32,0 kg consommés par jour. '
            .'Réapprovisionnez avant rupture.', $web->message);
        Notification::query()->delete();

        $this->pousser([[
            'id' => '00000090-0000-4000-8000-0000000000aa', 'lot_id' => $this->bande($porcs, 'POR-POSTE')->id,
            'entry_date' => self::JOUR, 'achat' => 0, 'ne' => 4, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0, 'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0,
            'passage_sevre_jeune' => 0, 'cat_depart_repro' => 4, 'cat_depart_sevre' => 36, 'cat_depart_jeune' => 20,
            'feed_qty_kg' => 32.0,
        ]]);

        $this->assertSame($this->alerte($web), $this->alerte(Notification::where('type', 'stock_low')->sole()));
    }
}
