<?php

namespace Tests\Feature;

use App\Livewire\Elevage\DashboardElevage;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Models\ProphylaxisScheduleStandard;
use App\Models\User;
use App\Models\VeterinaryRecord;
use App\Models\VeterinaryWithdrawalPeriod;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use App\Models\Permission;
use App\Models\Role;
use Tests\TestCase;

/**
 * Ticket H11 (décision D-H-maquette du 19/10/2026) — LES AJOUTS DU POSTE AU DASHBOARD ÉLEVAGE EXISTENT AU WEB.
 *
 * Référence : `agrierp_flutter/lib/features/elevage/dashboard_elevage_repository.dart` et `_screen.dart`.
 * Jour fixé au lundi 19/10/2026. Jeu (pesées en g) :
 *   LAP-01 (cuniculture, mise en lot 01/10) : 28/09 600, 08/10 800, 18/10 1 000  → GMQ cumulé (1000−600)/20 = 20,0
 *   LAP-02 (cuniculture, mise en lot 02/10) : 01/10 400, 11/10 550               → GMQ cumulé 150/10       = 15,0
 *   POR-01 (porciculture)                     : 01/10 20 000, 06/10 22 000, 11/10 25 000 → 5 000/10 = 500,0
 *   POR-02 (porciculture)                     : 28/09 10 000, 05/10 10 700 (pesées POSÉES SUR DEUX BORNES hebdomadaires)
 *                                               → 700/7 = 100,0
 *   AVI-01 (aviculture, stade ponte), AVI-02 (aviculture, stade chair) : aucune pesée.
 */
class DashboardElevageAjoutsPosteTest extends TestCase
{
    use RefreshDatabase;

    private array $especes = [];

    private array $bandes = [];

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-19 10:00:00');

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('animalier', 'web');
        $role->givePermissionTo(['view-elevage', 'manage-elevage']);
        $u = User::create(['name' => 'Animalier', 'email' => 'elevage.h11@olouwachegoun.bj', 'password' => bcrypt('AgriERP@2026')]);
        $u->assignRole($role);
        $this->actingAs($u);

        foreach (['cuniculture' => 'Cuniculture', 'aviculture' => 'Aviculture', 'porciculture' => 'Porciculture', 'helico' => 'Héliciculture'] as $code => $libelle) {
            $this->especes[$code] = LivestockSpecies::create(['code' => $code, 'label' => $libelle, 'is_enabled' => true]);
            ModuleConfig::create(['species_code' => $code, 'is_enabled' => true]);
        }

        $this->bandes['LAP-01'] = $this->bande('LAP-01', 'cuniculture', 'engraissement', '2026-10-01');
        $this->bandes['LAP-02'] = $this->bande('LAP-02', 'cuniculture', 'engraissement', '2026-10-02');
        $this->bandes['POR-01'] = $this->bande('POR-01', 'porciculture', 'engraissement', '2026-09-01');
        $this->bandes['POR-02'] = $this->bande('POR-02', 'porciculture', 'engraissement', '2026-09-01');
        $this->bandes['AVI-01'] = $this->bande('AVI-01', 'aviculture', 'ponte', '2026-08-01');
        $this->bandes['AVI-02'] = $this->bande('AVI-02', 'aviculture', 'chair', '2026-09-15');

        $this->pesee('LAP-01', '2026-09-28', 600);
        $this->pesee('LAP-01', '2026-10-08', 800);
        $this->pesee('LAP-01', '2026-10-18', 1000);
        $this->pesee('LAP-02', '2026-10-01', 400);
        $this->pesee('LAP-02', '2026-10-11', 550);
        $this->pesee('POR-01', '2026-10-01', 20000);
        $this->pesee('POR-01', '2026-10-06', 22000);
        $this->pesee('POR-01', '2026-10-11', 25000);
        $this->pesee('POR-02', '2026-09-28', 10000);
        $this->pesee('POR-02', '2026-10-05', 10700);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function bande(string $code, string $espece, string $stade, string $miseEnLot): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $this->especes[$espece]->id, 'stage' => $stade,
            'initial_quantity' => 100, 'current_quantity' => 100, 'created_date' => $miseEnLot,
            'status' => 'actif', 'is_active' => true,
        ]);
    }

    private function pesee(string $code, string $date, int $poids): void
    {
        LivestockDailyEntry::create(['lot_id' => $this->bandes[$code]->id, 'entry_date' => $date, 'effectif_final' => 100, 'weight_sample_avg_g' => $poids]);
    }

    private function ponte(string $code, string $date, ?int $oeufs, int $effectif): void
    {
        LivestockDailyEntry::create(['lot_id' => $this->bandes[$code]->id, 'entry_date' => $date, 'effectif_final' => $effectif, 'ponte_total' => $oeufs]);
    }

    /**
     * Courbe « Croissance (GMQ) par Espèce » : cinq bornes hebdomadaires 21/09, 28/09, 05/10, 12/10, 19/10.
     * Cuniculture : au 12/10, LAP-01 a 2 pesées (800−600)/10 = 20,0 et LAP-02 150/10 = 15,0 → moyenne 17,5 ; idem au 19/10.
     * Avant, aucune bande n'a deux pesées → null (aucun point). Aviculture : rien.
     * Porciculture : au 05/10, seule POR-02 a 2 pesées (la seconde EST la borne : `entry_date <= borne`) → 100,0 ;
     * au 12/10 et au 19/10, (POR-01 500 + POR-02 100) ÷ 2 = 300,0.
     */
    public function test_courbe_gmq_par_espece_de_la_synthese(): void
    {
        $page = Livewire::test(DashboardElevage::class);

        $series = $page->instance()->gmqParEspeceParSemaine;
        $this->assertSame([null, null, null, 17.5, 17.5], $series['cuniculture']);
        $this->assertSame([null, null, 100.0, 300.0, 300.0], $series['porciculture']);
        $this->assertSame([null, null, null, null, null], $series['aviculture']);

        $page->assertSee('Croissance (GMQ) par Espèce - 4 dernières semaines')
            ->assertSeeHtmlInOrder(['S1', 'S2', 'S3', 'S4', 'S5'])
            ->assertSeeHtmlInOrder(['Cuniculture', 'Aviculture', 'Porciculture'])
            ->assertSee('<circle', false);
    }

    /**
     * 4ᵉ ligne de chaque carte de filière (formules du dépôt Dart) : Mères / Géniteurs « — », Truies reproductrices « — »,
     * Taux d'éclosion « — » ; Taux de ponte = moyenne des (œufs ÷ effectif × 100) des fiches DU MOIS des bandes EN PONTE,
     * œufs absents comptés 0 : (80 + 90 + 0) ÷ 3 = 56,666… → « 56.7% ». La fiche de septembre et la bande de chair sont hors calcul.
     */
    public function test_quatrieme_ligne_des_cartes_de_filiere(): void
    {
        $this->ponte('AVI-01', '2026-10-02', 80, 100);
        $this->ponte('AVI-01', '2026-10-03', 90, 100);
        $this->ponte('AVI-01', '2026-10-04', null, 100);
        $this->ponte('AVI-01', '2026-09-30', 50, 100);
        $this->ponte('AVI-02', '2026-10-02', 10, 100);

        Livewire::test(DashboardElevage::class)
            ->assertSeeHtmlInOrder(['Cuniculture', 'Autonomie aliment', 'Mères / Géniteurs', '—'])
            ->assertSeeHtmlInOrder(['Aviculture', 'Autonomie aliment', 'Taux de ponte', '56.7%'])
            ->assertSeeHtmlInOrder(['Porciculture', 'Autonomie aliment', 'Truies reproductrices', '—'])
            ->assertSeeHtmlInOrder(['Héliciculture', 'Autonomie aliment', "Taux d&#039;éclosion", '—']);
    }

    /**
     * Rappels VMS calculés (moteur `ProtocoleDuJourService`, 7 jours) : barème lapin « Vitamines » J19 et
     * « Vermifuge lapereaux » J20. LAP-01 (J1 = 01/10) est à J19 aujourd'hui (Vitamines DÉJÀ administrées → pas de rappel),
     * J20 demain → « Dans 1 jour ». LAP-02 (J1 = 02/10) : J19 demain, J20 après-demain. Rémanence POR-01 jusqu'au 24/10
     * → « Fin dans 5 jours » ; celle échue le 18/10 n'apparaît pas.
     */
    public function test_rappels_vms_calcules(): void
    {
        ProphylaxisScheduleStandard::create(['species_code' => 'cuniculture', 'period_label' => 'J19', 'cycle_day_start' => 19, 'cycle_day_end' => 19,
            'treatment' => 'Vitamines', 'product_recommended' => 'Amin Total', 'dosage' => '1 g/l', 'withdrawal_days' => 0, 'is_active' => true]);
        ProphylaxisScheduleStandard::create(['species_code' => 'cuniculture', 'period_label' => 'J20', 'cycle_day_start' => 20, 'cycle_day_end' => 20,
            'treatment' => 'Vermifuge lapereaux', 'product_recommended' => 'Ivomec', 'dosage' => '0,2 ml', 'withdrawal_days' => 0, 'is_active' => true]);
        VeterinaryRecord::create(['lot_id' => $this->bandes['LAP-01']->id, 'action_type' => 'Vitamines', 'record_date' => '2026-10-19', 'is_active' => true]);
        VeterinaryWithdrawalPeriod::create(['lot_id' => $this->bandes['POR-01']->id, 'product_used' => 'Oxytétracycline', 'start_date' => '2026-10-17',
            'withdrawal_days' => 7, 'end_date' => '2026-10-24']);
        VeterinaryWithdrawalPeriod::create(['lot_id' => $this->bandes['POR-01']->id, 'product_used' => 'Ivermectine', 'start_date' => '2026-10-01',
            'withdrawal_days' => 17, 'end_date' => '2026-10-18']);

        $page = Livewire::test(DashboardElevage::class);

        $this->assertSame([
            ['libelle' => 'Vermifuge lapereaux — LAP-01', 'echeance' => 'Dans 1 jour', 'jours' => 1],
            ['libelle' => 'Vitamines — LAP-02', 'echeance' => 'Dans 1 jour', 'jours' => 1],
            ['libelle' => 'Vermifuge lapereaux — LAP-02', 'echeance' => 'Dans 2 jours', 'jours' => 2],
            ['libelle' => 'Rémanence en cours — Oxytétracycline', 'echeance' => 'Fin dans 5 jours', 'jours' => 5],
        ], $page->instance()->rappelsVms);

        $page->assertSeeHtmlInOrder(['Rappels VMS à venir', 'Vermifuge lapereaux — LAP-01', 'Dans 1 jour', 'Rémanence en cours — Oxytétracycline',
            'Fin dans 5 jours', 'Le calendrier complet (réel) est disponible dans Soins et Vaccins.', 'Voir le calendrier complet →'])
            ->assertDontSee('Ivermectine')
            ->assertDontSee('— Aucun rappel dans les 7 prochains jours —');
    }

    public function test_sans_rappel_le_bloc_le_dit(): void
    {
        Livewire::test(DashboardElevage::class)->assertSee('— Aucun rappel dans les 7 prochains jours —');
    }

    /**
     * Onglet GMQ : cartes par espèce = moyenne NON arrondie des GMQ cumulés, écrite sans décimale.
     * Lapins (20 + 15) ÷ 2 = 17,5 → « 18 g/j » ; Volailles « — » ; Porcs (500 + 100) ÷ 2 = 300 → « 300 g/j » ;
     * Lots suivis = 4 (LAP-01, LAP-02, POR-01, POR-02).
     * Bande suivie = la dernière pesée la plus récente (LAP-01, 18/10) ; ses 8 bornes du 31/08 au 19/10 : 20,0 aux deux dernières.
     */
    public function test_onglet_gmq_cartes_filtre_et_courbe(): void
    {
        // Ticket U2 — objectifs lus dans `growth_standards` (barème du stade des bandes moyennées) : les stades
        // « croissance » et « reproduction » n'ont aucune bande et ne comptent pas.
        $this->bareme('cuniculture', 'engraissement', 15, 20);
        $this->bareme('cuniculture', 'croissance', 10, 30);
        $this->bareme('porciculture', 'engraissement', 500, 650);
        $this->bareme('porciculture', 'reproduction', 40, 80);

        $page = Livewire::test(DashboardElevage::class)->set('tab', 'gmq');

        $page->assertSeeHtmlInOrder(['GMQ Moyen Lapins', '18 g/j', 'Objectif : 15-20 g/j',
            'GMQ Moyen Volailles Chair', '—', 'Moins de 2 pesées enregistrées',
            'GMQ Moyen Porcs', '300 g/j', 'Objectif : 500-650 g/j',
            'Lots Suivis (Pesées ≥ 2)', '4'])
            ->assertSee('Évolution du GMQ — LAP-01 (8 dernières semaines)')
            ->assertSeeHtmlInOrder(['Toutes les Espèces', 'Cuniculture (Lapins)', 'Aviculture (Volailles)', 'Porciculture (Porcs)']);

        $this->assertSame([null, null, null, null, null, null, 20.0, 20.0], $page->instance()->evolutionGmq);
        $this->assertSame(['AVI-01', 'AVI-02', 'LAP-01', 'LAP-02', 'POR-01', 'POR-02'], $page->instance()->gmqTableFiltree->map(fn ($r) => $r['lot']->code)->sort()->values()->all());

        $page->set('espece', 'porciculture');
        $this->assertSame(['POR-01', 'POR-02'], $page->instance()->gmqTableFiltree->map(fn ($r) => $r['lot']->code)->sort()->values()->all());
        // Les cartes ne suivent pas le filtre (poste : seul le tableau est filtré).
        $page->assertSee('18 g/j');
    }

    private function bareme(string $espece, string $stade, int $min, int $max): void
    {
        \App\Models\GrowthStandard::create(['species_code' => $espece, 'stage_label' => $stade,
            'gmq_min_g_per_day' => $min, 'gmq_max_g_per_day' => $max]);
    }

    /**
     * 🔴→✅ Ticket U2 (D-U2) — les objectifs des cartes GMQ étaient des CONSTANTES (15-20, 20-55, 400-650) recopiées du
     * poste. Sans aucun barème : « Objectif : — », jamais un objectif inventé ni 0.
     */
    public function test_sans_bareme_l_objectif_est_un_tiret(): void
    {
        $page = Livewire::test(DashboardElevage::class)->set('tab', 'gmq');

        $page->assertSeeHtmlInOrder(['GMQ Moyen Lapins', '18 g/j', 'Objectif : —', 'GMQ Moyen Porcs', '300 g/j', 'Objectif : —'])
            ->assertDontSee('Objectif : 15-20 g/j')
            ->assertDontSee('Objectif : 400-650 g/j');
        $this->assertSame(['cuniculture' => null, 'aviculture' => null, 'porciculture' => null], $page->instance()->gmqCartes['objectifs']);
    }

    /**
     * Ticket U2 — deux stades moyennés dans une carte : ENVELOPPE de leurs barèmes. POR-02 passe en croissance :
     * engraissement 500-650 et croissance 300-550 → « Objectif : 300-650 g/j ». Le barème « reproduction » (aucune
     * bande à ce stade) n'entre pas, et un barème modifié se lit au chargement suivant.
     */
    public function test_l_objectif_est_l_enveloppe_des_baremes_des_stades_moyennes(): void
    {
        $this->bandes['POR-02']->update(['stage' => 'croissance']);
        $this->bareme('porciculture', 'engraissement', 500, 650);
        $this->bareme('porciculture', 'croissance', 300, 550);
        $this->bareme('porciculture', 'reproduction', 40, 80);

        $page = Livewire::test(DashboardElevage::class)->set('tab', 'gmq');
        $page->assertSeeHtmlInOrder(['GMQ Moyen Porcs', '300 g/j', 'Objectif : 300-650 g/j']);
        $this->assertSame([300, 650], $page->instance()->gmqCartes['objectifs']['porciculture']);

        \App\Models\GrowthStandard::where('stage_label', 'croissance')->update(['gmq_min_g_per_day' => 450]);
        $this->assertSame([450, 650], Livewire::test(DashboardElevage::class)->instance()->gmqCartes['objectifs']['porciculture']);
    }

    /**
     * Onglet Prévision : bandes projetables (≥ 3 pesées), triées par code : LAP-01 puis POR-01.
     * LAP-01 : x = 0, 10, 20 ; y = 600, 800, 1 000 → pente 20, ordonnée 600 ; à 14 j : 600 + 20 × (20 + 14) = 1 280 g.
     * POR-01 : x = 0, 5, 10 ; y = 20 000, 22 000, 25 000 → n = 3, Σx = 15, Σy = 67 000, Σxy = 360 000, Σx² = 125,
     *   dénominateur 3 × 125 − 225 = 150, pente (1 080 000 − 1 005 000) ÷ 150 = 500, ordonnée (67 000 − 7 500) ÷ 3 = 19 833,33…
     *   projection(h) = round(19 833,33 + 500 × (10 + h)) : 7 j 28 333 ; 14 j 31 833 ; 30 j 39 833 ; 60 j 54 833.
     */
    public function test_onglet_prevision_selecteur_horizons_et_cartes(): void
    {
        $page = Livewire::test(DashboardElevage::class)->set('tab', 'prevision');

        $page->assertSee('Calcul du poste : droite de régression sur toutes les pesées de la bande (trois au minimum), comme le serveur.')
            ->assertSeeHtmlInOrder(['Paramètres de la projection', 'Bande', 'LAP-01 (Cuniculture)', 'POR-01 (Porciculture)',
                'Poids Actuel Constaté (g)', 'GMQ Observé (g/jour)', 'Horizon de Projection', '7 jours', '14 jours', '30 jours', '60 jours'])
            ->assertSeeHtmlInOrder(['Poids Projeté', '1 280 g', 'À 14 jours, 3 pesées retenues',
                'Poids Cible de Commercialisation', '—', 'Aucun poids cible n&#039;est paramétré',
                'Date Estimée d&#039;Atteinte de la Cible', '—', 'Dépend du poids cible']);

        $page->set('bandePrevision', $this->bandes['POR-01']->id)->set('horizon', 30)
            ->assertSee('value="25000"', false)
            ->assertSee('value="500.0"', false)
            ->assertSeeHtmlInOrder(['Poids Projeté', '39 833 g', 'À 30 jours, 3 pesées retenues'])
            ->assertSeeHtmlInOrder(['Courbe de Croissance — Historique et Projection', 'Échéance', 'Poids (g)',
                'Aujourd&#039;hui', '25 000', '+ 7 jours', '28 333', '+ 14 jours', '31 833', '+ 30 jours', '39 833', '+ 60 jours', '54 833']);
    }

    public function test_prevision_sans_bande_projetable_cartes_a_tiret(): void
    {
        LivestockDailyEntry::query()->delete();

        Livewire::test(DashboardElevage::class)->set('tab', 'prevision')
            ->assertSee('— Trois pesées au minimum sont nécessaires pour projeter —')
            ->assertSeeHtmlInOrder(['Poids Projeté', '—', 'Trois pesées au minimum'])
            ->assertDontSee('Courbe de Croissance — Historique et Projection');
    }
}
