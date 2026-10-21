<?php

namespace Tests\Feature;

use App\Livewire\Elevage\SuiviReproduction;
use App\Models\Animal;
use App\Models\LivestockLot;
use App\Models\LivestockReproductionEvent;
use App\Models\LivestockSpecies;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use App\Models\Permission;
use App\Models\Role;
use Tests\TestCase;

/**
 * Ticket H11 (décision D-H-maquette du 19/10/2026) — LES AJOUTS DU POSTE AU SUIVI REPRODUCTION EXISTENT AU WEB.
 *
 * Référence : `agrierp_flutter/lib/features/elevage/suivi_reproduction_screen.dart` (colonnes après les neuf du Blade,
 * jalon « Boîte à nid J+28 », bandeaux de cycle Volailles / Escargots, « Bandes suivies », champ « Cages Occupées » et
 * aperçu des échéances de la modale lapin, lien vers la fiche d'un sujet enregistré).
 */
class SuiviReproductionAjoutsPosteTest extends TestCase
{
    use RefreshDatabase;

    private array $especes = [];

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-19 10:00:00');

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('animalier', 'web');
        $role->givePermissionTo(['view-elevage', 'manage-elevage']);
        $u = User::create(['name' => 'Animalier', 'email' => 'repro.h11@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026')]);
        $u->assignRole($role);
        $this->actingAs($u);

        foreach (['cuniculture' => 'Lapins', 'aviculture' => 'Volailles', 'porciculture' => 'Porcs', 'helico' => 'Escargots'] as $code => $libelle) {
            $this->especes[$code] = LivestockSpecies::create(['code' => $code, 'label' => $libelle, 'is_enabled' => true]);
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function bande(string $code, string $espece, bool $active = true): LivestockLot
    {
        return LivestockLot::create([
            'code' => $code, 'species_id' => $this->especes[$espece]->id, 'stage' => 'reproduction',
            'initial_quantity' => 20, 'current_quantity' => 20, 'created_date' => '2026-08-01',
            'status' => $active ? 'actif' : 'cloture', 'is_active' => $active,
        ]);
    }

    /**
     * Lapins : rappel du cycle, ligne annexe, puis les quatre colonnes du poste APRÈS « Action ».
     * R1 : mise bas avec 2 nés morts → « Morts S/Mère » = 2 ; R2 sans mise bas → « — ». Sevrés, Poids Moyen et Cages : « — ».
     * R1 est un sujet enregistré → lien vers sa fiche ; R2 n'en est pas un → texte.
     */
    public function test_lapins_colonnes_jalon_et_lien_sujet(): void
    {
        $lot = $this->bande('LAP-R', 'cuniculture');
        LivestockReproductionEvent::create(['lot_id' => $lot->id, 'mother_ref' => 'R1', 'sire_ref' => 'M2', 'saillie_date' => '2026-09-01',
            'palpation_date' => '2026-09-15', 'mise_bas_date_actual' => '2026-10-01', 'nes_vivants' => 7, 'nes_morts' => 2, 'status' => 'en_cours']);
        LivestockReproductionEvent::create(['lot_id' => $lot->id, 'mother_ref' => 'R2', 'saillie_date' => '2026-10-10', 'status' => 'en_cours']);
        $r1 = Animal::create(['identifier' => 'R1', 'species_id' => $this->especes['cuniculture']->id, 'lot_id' => $lot->id, 'sex' => 'F', 'entry_date' => '2026-03-01']);

        $page = Livewire::test(SuiviReproduction::class);

        $page->assertSeeHtmlInOrder(['Rappel du cycle :', 'Saillie J0', 'Palpation J+14', 'Mise bas J+30', 'Sevrage J+60',
            'Jalon intermédiaire : Boîte à nid J+28 (informatif, sans action de suivi).'])
            ->assertSeeHtmlInOrder(['>Statut</th>', '>Action</th>', '>Sevrés (M/F)</th>', '>Morts S/Mère</th>', '>Poids Moyen (g)</th>', '>Cages</th>'])
            ->assertSee('href="'.route('elevage.animal-details', $r1).'"', false);

        $lignes = $page->instance()->colonnesPoste;
        $this->assertSame(['—', '2', '—', '—'], $lignes[$this->evenement('R1')]);
        $this->assertSame(['—', '—', '—', '—'], $lignes[$this->evenement('R2')]);
        $this->assertSame(['R1' => $r1->id], $page->instance()->sujetsConnus);
    }

    /**
     * Porcs : « Sevrage (J+42) » après « Action » — date stockée (30/11/2026), sinon mise bas réelle + 42 j
     * (01/10/2026 + 42 = 12/11/2026), sinon « — ». Ni ligne annexe ni colonnes lapin.
     */
    public function test_porcs_colonne_sevrage(): void
    {
        $lot = $this->bande('POR-R', 'porciculture');
        LivestockReproductionEvent::create(['lot_id' => $lot->id, 'mother_ref' => 'T1', 'saillie_date' => '2026-06-01', 'sevrage_date_expected' => '2026-11-30', 'status' => 'en_cours']);
        LivestockReproductionEvent::create(['lot_id' => $lot->id, 'mother_ref' => 'T2', 'saillie_date' => '2026-06-10', 'palpation_date' => '2026-07-01',
            'mise_bas_date_actual' => '2026-10-01', 'nes_vivants' => 10, 'nes_morts' => 1, 'status' => 'en_cours']);
        LivestockReproductionEvent::create(['lot_id' => $lot->id, 'mother_ref' => 'T3', 'saillie_date' => '2026-10-05', 'status' => 'en_cours']);

        $page = Livewire::test(SuiviReproduction::class)->set('tab', 'porcs');

        $page->assertSeeHtmlInOrder(['>Statut</th>', '>Action</th>', '>Sevrage (J+42)</th>'])
            ->assertDontSee('Jalon intermédiaire')
            ->assertDontSee('Sevrés (M/F)');

        $lignes = $page->instance()->colonnesPoste;
        $this->assertSame(['30/11/2026'], $lignes[$this->evenement('T1')]);
        $this->assertSame(['12/11/2026'], $lignes[$this->evenement('T2')]);
        $this->assertSame(['—'], $lignes[$this->evenement('T3')]);
    }

    /** Volailles : carte « Bandes suivies » = bandes NON ARCHIVÉES de l'espèce (2 sur 3), puis le bandeau d'incubation. */
    public function test_volailles_bandes_suivies_et_bandeau(): void
    {
        $this->bande('AVI-R1', 'aviculture');
        $this->bande('AVI-R2', 'aviculture');
        $this->bande('AVI-R3', 'aviculture', false);
        $this->bande('ESC-R1', 'helico');

        $page = Livewire::test(SuiviReproduction::class)->set('tab', 'volailles');
        $this->assertSame(2, $page->instance()->incubationSummary['lots']);
        $page->assertSeeHtmlInOrder(["Taux d&#039;Éclosion", 'Bandes suivies', '2', 'Saisir le Couvoir du Jour →',
            'Rappel du cycle :', 'Mise en Incubation J0', 'Éclosion Attendue J+21']);

        $page->set('tab', 'escargots');
        $this->assertSame(1, $page->instance()->incubationSummary['lots']);
        $page->assertSeeHtmlInOrder(['Bandes suivies', 'Saisir le Couvoir du Jour →', 'Rappel du cycle :', 'Placement Bac de Ponte J0',
            'Éclosion Naissains Attendue J+25']);
    }

    /**
     * Modale lapin : « Cages Occupées » désactivé, puis l'aperçu des échéances depuis la date de saillie choisie.
     * 01/10/2026 : palpation +14 = 15/10, boîte à nid +28 = 29/10, mise bas +30 = 31/10, sevrage +60 = 30/11.
     * Modale porc : ni l'un ni l'autre (le poste ne les montre qu'aux lapins).
     */
    public function test_modale_saillie_cages_et_apercu(): void
    {
        $page = Livewire::test(SuiviReproduction::class)->set('saillieDate', '2026-10-01');

        $page->assertSeeHtmlInOrder(['Date de Saillie *', 'Cages Occupées', 'Référentiel des cages absent du schéma',
            'Ligne du temps automatique calculée :',
            'Palpation (J+14) :', '15/10/2026', 'Boîte à nid (J+28) :', '29/10/2026',
            'Mise bas (J+30) :', '31/10/2026', 'Sevrage (J+60) :', '30/11/2026', 'Enregistrer la Saillie'])
            ->assertSee('disabled', false);

        Livewire::test(SuiviReproduction::class)->set('tab', 'porcs')
            ->assertDontSee('Cages Occupées')
            ->assertDontSee('Ligne du temps automatique calculée :');
    }

    private function evenement(string $mere): string
    {
        return LivestockReproductionEvent::where('mother_ref', $mere)->value('id');
    }
}
