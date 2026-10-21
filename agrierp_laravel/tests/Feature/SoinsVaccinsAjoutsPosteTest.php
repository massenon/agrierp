<?php

namespace Tests\Feature;

use App\Livewire\Elevage\SoinsVaccinsHub;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\User;
use App\Models\VeterinaryRecord;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Livewire\Livewire;
use App\Models\Permission;
use App\Models\Role;
use Tests\TestCase;

/**
 * Ticket H11 (décision D-H-maquette du 19/10/2026) — LES AJOUTS DU POSTE AU REGISTRE DES SOINS EXISTENT AU WEB.
 *
 * Référence : `agrierp_flutter/lib/features/elevage/soins_vaccins_screen.dart` (`_filtres`, `_lignesFiltrees`,
 * colonne « Statut »). Recherche sur le code de la bande, le type d'action, le produit et les symptômes, sans casse ;
 * catégorie = type d'action exact ; espèce = Lapins / Volailles / Porcs. Filtrage FAIT PAR LA REQUÊTE (serveur).
 * Jeu : 3 soins actifs + 1 archivé.
 *   S1 LAP-01 (cuniculture) Vaccination, Pasteurellose
 *   S2 AVI-01 (aviculture)  Vermifuge, Pipérazine, symptômes « Diarrhée blanche »
 *   S3 POR-01 (porciculture) Traitement curatif, Oxytétracycline
 *   S4 LAP-01 Vermifuge ARCHIVÉ — jamais affiché.
 */
class SoinsVaccinsAjoutsPosteTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-19 10:00:00');

        foreach (['view-elevage', 'manage-elevage'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        $role = Role::findOrCreate('animalier', 'web');
        $role->givePermissionTo(['view-elevage', 'manage-elevage']);
        $u = User::create(['name' => 'Animalier', 'email' => 'soins.h11@fermeolouwachegoun.com', 'password' => bcrypt('AgriERP@2026')]);
        $u->assignRole($role);
        $this->actingAs($u);

        $bandes = [];
        foreach (['LAP-01' => 'cuniculture', 'AVI-01' => 'aviculture', 'POR-01' => 'porciculture'] as $code => $espece) {
            $s = LivestockSpecies::create(['code' => $espece, 'label' => ucfirst($espece), 'is_enabled' => true]);
            $bandes[$code] = LivestockLot::create(['code' => $code, 'species_id' => $s->id, 'stage' => 'engraissement', 'initial_quantity' => 10,
                'current_quantity' => 10, 'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => true]);
        }

        VeterinaryRecord::create(['lot_id' => $bandes['LAP-01']->id, 'action_type' => 'Vaccination', 'product_used' => 'Pasteurellose', 'record_date' => '2026-10-10', 'is_active' => true]);
        VeterinaryRecord::create(['lot_id' => $bandes['AVI-01']->id, 'action_type' => 'Vermifuge', 'product_used' => 'Pipérazine', 'symptomes' => 'Diarrhée blanche', 'record_date' => '2026-10-11', 'is_active' => true]);
        VeterinaryRecord::create(['lot_id' => $bandes['POR-01']->id, 'action_type' => 'Traitement curatif', 'product_used' => 'Oxytétracycline', 'record_date' => '2026-10-12', 'is_active' => true]);
        VeterinaryRecord::create(['lot_id' => $bandes['LAP-01']->id, 'action_type' => 'Vermifuge', 'product_used' => 'Archivé', 'record_date' => '2026-10-13', 'is_active' => false]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function produits($page): array
    {
        return $page->instance()->veterinaryRecords->pluck('product_used')->sort()->values()->all();
    }

    public function test_barre_de_filtres_et_colonne_statut(): void
    {
        $page = Livewire::test(SoinsVaccinsHub::class);

        $page->assertSee('placeholder="Rechercher un diagnostic, un lot..."', false)
            ->assertSeeHtmlInOrder(['Toutes catégories', 'Vaccination', 'Traitement curatif', 'Vermifuge', 'Vitamines'])
            ->assertSeeHtmlInOrder(['Toutes espèces', 'Lapins', 'Volailles', 'Porcs'])
            // Colonne ajoutée APRÈS les six du Blade ; un soin du registre est un soin ADMINISTRÉ : « Effectué ».
            ->assertSeeHtmlInOrder(['>Date</th>', '>Lot / Espèce</th>', '>Type d&#039;action</th>', '>Produit</th>', '>Dose</th>', '>Actions</th>', '>Statut</th>', '>Effectué</span>'])
            // Importer / Exporter PDF sont inertes au poste : non portés.
            ->assertDontSee('Importer')
            ->assertDontSee('Exporter PDF');

        $this->assertSame(['Oxytétracycline', 'Pasteurellose', 'Pipérazine'], $this->produits($page));
        $this->assertSame(3, substr_count($page->html(), '>Effectué</span>'));
    }

    /** Recherche : « diarrhée » ne trouve S2 que par ses SYMPTÔMES ; « por-01 » trouve S3 par le code de bande, sans casse. */
    public function test_recherche_serveur(): void
    {
        $page = Livewire::test(SoinsVaccinsHub::class)->set('recherche', 'diarrhée');
        $this->assertSame(['Pipérazine'], $this->produits($page));

        $page->set('recherche', 'por-01');
        $this->assertSame(['Oxytétracycline'], $this->produits($page));

        $page->set('recherche', 'introuvable');
        $this->assertSame([], $this->produits($page));
        $page->assertSee('— Aucun soin au registre pour ces critères —');
    }

    /** Catégorie « Vermifuge » : S2 seul (S4 est archivé). Espèce « Lapins » : S1 seul. Les deux filtres se cumulent. */
    public function test_filtres_categorie_et_espece(): void
    {
        $page = Livewire::test(SoinsVaccinsHub::class)->set('categorie', 'Vermifuge');
        $this->assertSame(['Pipérazine'], $this->produits($page));

        $page->set('categorie', '')->set('espece', 'Lapins');
        $this->assertSame(['Pasteurellose'], $this->produits($page));

        $page->set('categorie', 'Vermifuge');
        $this->assertSame([], $this->produits($page));
    }
}
