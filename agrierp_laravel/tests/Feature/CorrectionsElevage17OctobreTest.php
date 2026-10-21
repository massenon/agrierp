<?php

namespace Tests\Feature;

use App\Actions\RecordSaleOnFicheElevageAction;
use App\Livewire\Elevage\EnregistrerSujets;
use App\Livewire\Elevage\FicheEscargots;
use App\Livewire\Elevage\FicheLapins;
use App\Livewire\Elevage\FichePondeuses;
use App\Livewire\Elevage\FichePorcs;
use App\Livewire\Elevage\FicheReproducteurs;
use App\Livewire\Elevage\GestionBandes;
use App\Livewire\Elevage\GestionElevage;
use App\Livewire\Elevage\TransformationForm;
use App\Models\FeedRationStandard;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\User;
use App\Models\VeterinaryRecord;
use App\Models\VeterinaryWithdrawalPeriod;
use Carbon\Carbon;
use Database\Seeders\DemoUsersSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Corrections demandées par le client le 17/10/2026 (fiches journalières, archivage, tiroir des bandes, paramètres).
 *
 * ⚠️ Valeurs attendues = LITTÉRAUX calculés à la main. Date figée au 14/10/2026.
 */
class CorrectionsElevage17OctobreTest extends TestCase
{
    use RefreshDatabase;

    private const JOUR = '2026-10-10';

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-14 12:00:00');

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);
        $admin = User::create(['name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
        $admin->assignRole('admin');
        $this->actingAs($admin);

        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Reproducteur', 'ration_g_per_day' => 120]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Sous-mères', 'ration_g_per_day' => 30]);
        FeedRationStandard::create(['species_code' => 'cuniculture', 'stage_label' => 'Jeune', 'ration_g_per_day' => 60]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function espece(string $code, string $label): LivestockSpecies
    {
        return LivestockSpecies::firstOrCreate(['code' => $code], ['label' => $label, 'is_enabled' => true, 'is_active' => true]);
    }

    private function bande(string $code, string $espece, string $stade, int $effectif, array $plus = []): LivestockLot
    {
        return LivestockLot::create(array_merge([
            'code' => $code, 'species_id' => $this->espece($espece, ucfirst($espece))->id, 'stage' => $stade,
            'initial_quantity' => $effectif, 'current_quantity' => $effectif,
            'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true,
        ], $plus));
    }

    private function provende(string $espece, float $stock, string $nom = 'Provende lapins'): Product
    {
        $categorie = ProductCategory::firstOrCreate(['label' => 'Aliments'], ['is_active' => true]);

        return Product::create([
            'sku' => 'ALI-'.strtoupper(substr($espece, 0, 3)), 'name' => $nom, 'category_id' => $categorie->id,
            'species_id' => $this->espece($espece, ucfirst($espece))->id, 'unit' => 'kg', 'pricing_mode' => 'fourchette',
            'price_min' => 300, 'price_max' => 400, 'tva_rate' => 0, 'stock_qty' => $stock, 'is_active' => true,
        ]);
    }

    private function texte($c): string
    {
        return preg_replace('/\s+/u', ' ', html_entity_decode(strip_tags($c->html()), ENT_QUOTES | ENT_HTML5));
    }

    // ============================================================ autonomie alimentaire

    /** Stock à 0 : message ROUGE de rupture, et la fiche s'enregistre quand même. */
    public function test_une_rupture_de_stock_s_affiche_en_rouge_sans_empecher_l_enregistrement(): void
    {
        $lot = $this->bande('LOT-LAP-1', 'cuniculture', 'engraissement', 50);
        $this->provende('cuniculture', 0);

        $c = Livewire::test(FicheLapins::class)->call('loadDay', self::JOUR);

        $this->assertTrue($c->instance()->feedAutonomy['rupture']);
        $this->assertTrue($c->instance()->feedAutonomy['critique']);
        $this->assertStringContainsString('Autonomie alimentaire : rupture de stock', $this->texte($c));
        $this->assertStringContainsString('approvisionnez-vous', $this->texte($c));
        $this->assertMatchesRegularExpression('/bg-error-bg[^"]*"[^>]*role="alert"/', $c->html());

        $c->set('ne', 0)->call('saveDay');
        $this->assertSame(1, LivestockDailyEntry::where('lot_id', $lot->id)->count(), 'la rupture ne bloque jamais la fiche');
    }

    /** Aucun produit de provende en catalogue : rouge aussi (« aucun stock suivi »), jamais un sablier gris. */
    public function test_sans_produit_de_provende_l_autonomie_est_signalee_en_rouge(): void
    {
        $this->bande('LOT-POR-1', 'porciculture', 'engraissement', 10);

        $c = Livewire::test(FichePorcs::class)->call('loadDay', self::JOUR);

        $this->assertStringContainsString('Autonomie alimentaire : aucun stock de provende suivi', $this->texte($c));
        $this->assertStringNotContainsString("Le suivi d'autonomie alimentaire sera alimenté", $this->texte($c));
    }

    /** Bande de 50 Jeunes : 50 × 60 g = 3 kg/j ; stock 9 kg → 3 jours = critique (rouge), stock 30 kg → 10 jours. */
    public function test_l_autonomie_est_critique_sous_trois_jours(): void
    {
        $this->bande('LOT-LAP-1', 'cuniculture', 'engraissement', 50);
        $produit = $this->provende('cuniculture', 9);

        $a = Livewire::test(FicheLapins::class)->call('loadDay', self::JOUR)->instance()->feedAutonomy;
        $this->assertSame(3.0, $a['autonomie_jours']);
        $this->assertTrue($a['critique']);
        $this->assertFalse($a['rupture']);

        $produit->update(['stock_qty' => 30]);
        $a = Livewire::test(FicheLapins::class)->call('loadDay', self::JOUR)->instance()->feedAutonomy;
        $this->assertSame(10.0, $a['autonomie_jours']);
        $this->assertFalse($a['critique']);
    }

    // ============================================================ poids et traitements

    /** Moyenne stockée 1 250 g × effectif final 40 = « Poids Général » 50 000 g dans le tableau mensuel. */
    public function test_le_poids_general_du_tableau_mensuel_est_le_total_pese_et_non_la_moyenne(): void
    {
        $lot = $this->bande('LOT-LAP-1', 'cuniculture', 'engraissement', 40);
        $fiche = LivestockDailyEntry::create(['lot_id' => $lot->id, 'entry_date' => self::JOUR, 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0,
            'effectif_final' => 40, 'weight_sample_avg_g' => 1250]);

        $this->assertSame(50000, $fiche->poids_general_g);
        $this->assertNull((new LivestockDailyEntry(['effectif_final' => 40]))->poids_general_g, 'sans pesée : inconnu, jamais 0');

        foreach ([FicheLapins::class, FicheEscargots::class, FicheReproducteurs::class] as $ecran) {
            $this->assertStringContainsString('poids_general_g', file_get_contents((new \ReflectionClass($ecran))->getFileName()).file_get_contents(resource_path('views/livewire/elevage/'.Str::kebab(class_basename($ecran)).'.blade.php')), class_basename($ecran));
        }
    }

    /** Poids pesé 3 500 g pour un effectif final de 40 : 87,5 → 88 g (arrondi, comme la valeur enregistrée). */
    public function test_le_poids_moyen_constate_est_calcule_automatiquement_et_arrondi(): void
    {
        $this->bande('LOT-LAP-1', 'cuniculture', 'engraissement', 40);
        $c = Livewire::test(FicheLapins::class)->call('loadDay', self::JOUR)->set('peseeTotal', 3500);
        $this->assertStringContainsString('88 g', $this->texte($c));

        $this->bande('AVI-REP-1', 'aviculture', 'reproduction', 40);
        $c = Livewire::test(FicheReproducteurs::class)->call('loadDay', self::JOUR)->set('peseeTotal', 3500);
        $this->assertStringContainsString('Poids Moyen Constaté', $this->texte($c));
        $this->assertStringContainsString('88 g', $this->texte($c));
    }

    /** Un traitement validé au registre apparaît dans la colonne « Traitements & Prophylaxie » ; un soin archivé, non. */
    public function test_les_traitements_valides_apparaissent_dans_le_tableau_mensuel(): void
    {
        $lot = $this->bande('LOT-LAP-1', 'cuniculture', 'engraissement', 40);
        VeterinaryRecord::create(['lot_id' => $lot->id, 'action_type' => 'Vaccination VHD', 'product_used' => 'Dercunimix', 'record_date' => self::JOUR, 'is_active' => true]);
        VeterinaryRecord::create(['lot_id' => $lot->id, 'action_type' => 'Déparasitage', 'record_date' => self::JOUR, 'is_active' => false]);

        $c = Livewire::test(FicheLapins::class)->call('loadDay', self::JOUR);

        $this->assertSame('Vaccination VHD (Dercunimix)', $c->instance()->traitementsDuJour(self::JOUR, null));
        $this->assertSame('—', $c->instance()->traitementsDuJour('2026-10-11', null));
        $this->assertStringContainsString('Vaccination VHD (Dercunimix)', $this->texte($c));
        $this->assertStringNotContainsString('Déparasitage', $this->texte($c));
    }

    /** Pondeuses et Reproducteurs sont raccordées au protocole du jour (plus de « à planifier »). */
    public function test_pondeuses_et_reproducteurs_affichent_la_prophylaxie_du_jour(): void
    {
        $this->bande('AVI-PON-1', 'aviculture', 'ponte', 100);
        $this->bande('AVI-REP-1', 'aviculture', 'reproduction', 40);

        $this->assertNotNull(Livewire::test(FichePondeuses::class)->instance()->protocoleDuJour);
        $this->assertNotNull(Livewire::test(FicheReproducteurs::class)->instance()->protocoleDuJour);
    }

    // ============================================================ transformation = vente

    /**
     * Bande de 40 ; fiche du 12 : 2 morts → 38. Transformation de 5 sujets le 10 : vente du 10 = 5 → 35 ; le 12
     * recalculé = 33 ; bande = 33. Puis l'animalier réenregistre le 12 : la transformation N'EST PAS effacée.
     */
    public function test_une_transformation_est_une_vente_de_la_fiche_et_survit_a_la_sauvegarde_suivante(): void
    {
        $lot = $this->bande('AVI-ENG-1', 'aviculture', 'engraissement', 40);
        LivestockDailyEntry::create(['lot_id' => $lot->id, 'entry_date' => '2026-10-12', 'achat' => 0, 'ne' => 0, 'mort' => 2, 'vente' => 0, 'don' => 0, 'effectif_final' => 38]);
        $lot->update(['current_quantity' => 38]);
        $produit = Product::create(['sku' => 'AVI-005', 'name' => 'Poulet fumé', 'category_id' => ProductCategory::create(['label' => 'Transformés', 'is_active' => true])->id,
            'unit' => 'pièce', 'pricing_mode' => 'fourchette', 'price_min' => 5000, 'price_max' => 6000, 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true]);

        Livewire::test(TransformationForm::class)
            ->set('lotId', $lot->id)->set('qtyAnimals', 5)->set('productId', $produit->id)->set('qtyProduced', 5)->set('transformationDate', self::JOUR)
            ->call('validateTransformation')->assertHasNoErrors();

        $jour = LivestockDailyEntry::where('lot_id', $lot->id)->whereDate('entry_date', self::JOUR)->first();
        $this->assertSame(5, (int) $jour->vente);
        $this->assertSame(35, (int) $jour->effectif_final);
        $this->assertSame(33, (int) LivestockDailyEntry::where('lot_id', $lot->id)->whereDate('entry_date', '2026-10-12')->value('effectif_final'));
        $this->assertSame(33, (int) $lot->fresh()->current_quantity);
        $this->assertSame(5.0, (float) $produit->fresh()->stock_qty);

        app(RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($lot->id, '2026-10-12');
        $this->assertSame(33, (int) $lot->fresh()->current_quantity, 'la transformation n\'est plus effacée');
    }

    // ============================================================ don

    /**
     * Décision client du 17/10/2026 : le « Don » est une SORTIE (animal donné), soustrait comme dans la formule
     * Effectif Final = J-1 + Achats + Nés − (Morts + Ventes + Dons). Bande de 30, don de 4 : 26.
     */
    public function test_un_don_enregistre_est_une_sortie_soustraite_de_l_effectif(): void
    {
        $lot = $this->bande('AVI-ENG-1', 'aviculture', 'engraissement', 30);

        Livewire::test(EnregistrerSujets::class)
            ->set('species_id', $lot->species_id)->set('lot_id', $lot->id)->set('origine', 'Don')->set('quantite', 4)->set('entry_date', self::JOUR)
            ->call('saveEntry')->assertHasNoErrors();

        $fiche = LivestockDailyEntry::where('lot_id', $lot->id)->first();
        $this->assertSame(4, (int) $fiche->don);
        $this->assertSame(26, (int) $fiche->effectif_final);
        $this->assertSame(26, (int) $lot->fresh()->current_quantity);
    }

    // ============================================================ archivage

    /** Bandes de 60 et 40 ; archiver celle de 40 la retire immédiatement de tous les indicateurs « actuels ». */
    public function test_une_bande_archivee_ne_compte_plus_dans_les_statistiques(): void
    {
        $this->bande('LOT-LAP-1', 'cuniculture', 'engraissement', 60);
        $archivee = $this->bande('LOT-LAP-2', 'cuniculture', 'reproduction', 40);
        VeterinaryWithdrawalPeriod::create(['lot_id' => $archivee->id, 'product_used' => 'Oxytétracycline', 'start_date' => '2026-10-12', 'withdrawal_days' => 7, 'end_date' => '2026-10-19']);

        $this->assertSame(100, Livewire::test(GestionElevage::class)->instance()->effectifTotal);
        $kpis = Livewire::test(GestionBandes::class)->instance()->kpis;
        $this->assertSame([2, 1, 100, 1], [$kpis['bandes_actives'], $kpis['en_reproduction'], $kpis['effectif_total'], $kpis['alertes_sanitaires']]);

        Livewire::test(GestionBandes::class)->call('archiveLot', $archivee->id);

        $this->assertSame(60, Livewire::test(GestionElevage::class)->instance()->effectifTotal);
        $this->assertSame(1, Livewire::test(GestionElevage::class)->instance()->bandesActives);
        $kpis = Livewire::test(GestionBandes::class)->instance()->kpis;
        $this->assertSame([1, 0, 60, 0], [$kpis['bandes_actives'], $kpis['en_reproduction'], $kpis['effectif_total'], $kpis['alertes_sanitaires']]);
        $this->assertSame(60, (int) LivestockLot::vivantes()->sum('current_quantity'));
    }

    // ============================================================ tiroir de Gestion des Bandes

    public function test_le_tiroir_des_bandes_affiche_l_autonomie_et_le_suivi_sanitaire_reels(): void
    {
        $lot = $this->bande('LOT-LAP-1', 'cuniculture', 'engraissement', 50);
        $this->provende('cuniculture', 30);
        LivestockDailyEntry::create(['lot_id' => $lot->id, 'entry_date' => '2026-10-13', 'achat' => 0, 'ne' => 0, 'mort' => 2, 'vente' => 0, 'don' => 0,
            'effectif_final' => 48, 'feed_qty_kg' => 2.88]);
        VeterinaryWithdrawalPeriod::create(['lot_id' => $lot->id, 'product_used' => 'Oxytétracycline', 'start_date' => '2026-10-12', 'withdrawal_days' => 7, 'end_date' => '2026-10-19']);
        VeterinaryRecord::create(['lot_id' => $lot->id, 'action_type' => 'Traitement antibiotique', 'product_used' => 'Oxytétracycline', 'record_date' => '2026-10-12', 'is_active' => true]);

        $c = Livewire::test(GestionBandes::class)->call('view', $lot->id);
        $texte = $this->texte($c);

        // 30 kg ÷ 2,88 kg/j = 10,4 jours ; 2 morts sur 50 au début de la période = 4 %.
        $this->assertStringContainsString('Autonomie alimentaire : 10.4 jours', $texte);
        $this->assertStringContainsString('2,88 Kg/j', $texte);
        $this->assertStringContainsString("Délai d'attente en cours", $texte);
        $this->assertStringContainsString('19/10/2026', $texte);
        $this->assertStringContainsString('2 mort(s) — 4,0 %', $texte);
        $this->assertStringContainsString('12/10/2026 — Traitement antibiotique (Oxytétracycline)', $texte);
        $this->assertStringNotContainsString('sera alimenté en données réelles', $texte);
    }

    // ============================================================ stades de bande et paramètres

    /** Lapins : Stade Initial = Reproducteur / Jeune / Sous-mères (valeurs stockées inchangées), jamais « Ponte ». */
    public function test_le_stade_initial_des_lapins_propose_les_trois_categories_du_glossaire(): void
    {
        $lapins = $this->espece('cuniculture', 'Lapins');
        $volailles = $this->espece('aviculture', 'Volailles');

        $c = Livewire::test(GestionBandes::class)->call('newLot')->set('species_id', $lapins->id);
        $this->assertSame(['reproduction' => 'Reproducteur', 'engraissement' => 'Jeune', 'croissance' => 'Sous-mères'], $c->instance()->stades);

        $c->set('stage', 'croissance')->set('code', 'LOT-LAP-9')->set('quantity', 30)->call('saveLot')->assertHasNoErrors();
        $lot = LivestockLot::where('code', 'LOT-LAP-9')->first();
        $this->assertSame('croissance', $lot->stage);
        $this->assertSame('Sous-mères', $lot->libelleStade());

        $c->call('newLot')->set('species_id', $lapins->id)->set('stage', 'ponte')->set('code', 'LOT-LAP-10')->set('quantity', 5)->call('saveLot')->assertHasErrors('stage');

        $c->call('newLot')->set('species_id', $volailles->id);
        $this->assertArrayHasKey('ponte', $c->instance()->stades);
    }

    public function test_les_parametres_portent_le_nom_et_le_contact_du_client(): void
    {
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(DemoUsersSeeder::class);

        // L'administrateur du setUp (dg@fermeolouwachegoun.com) existe déjà : il est retrouvé par son identifiant et mis à jour,
        // jamais dupliqué.
        $this->assertSame(1, User::where('username', 'admin')->count());
        $admin = User::where('username', 'admin')->first();
        $this->assertSame('M. Olouchègoun', $admin->name);
        $this->assertSame('contact@fermeolouwachegoun.com', $admin->email);

        foreach (['database/seeders', 'resources/views', 'app'] as $dossier) {
            foreach (new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator(base_path($dossier))) as $fichier) {
                if ($fichier->isFile()) {
                    $this->assertStringNotContainsString('OLOUKOUNLE', file_get_contents($fichier->getPathname()), $fichier->getPathname());
                }
            }
        }
    }
}
