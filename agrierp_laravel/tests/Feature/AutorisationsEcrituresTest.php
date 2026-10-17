<?php

namespace Tests\Feature;

use App\Models\Permission;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.64 (Sprint 14) — LIRE NE DONNE PAS LE DROIT D'ÉCRIRE.
 *
 * ⚠️⚠️ CE QUE CE BALAYAGE A TROUVÉ. Le ticket 14.62 avait corrigé **un** écran
 * (`SaisieDepenses`) où trois méthodes mutantes ne portaient aucune
 * autorisation. Le défaut n'était pas isolé : **24 composants Livewire sur 96
 * écrivaient en base sans le moindre `authorize()`**, plusieurs gardés par une
 * simple permission de LECTURE (`can:view-stocks` sur un écran qui archive des
 * produits, `can:view-facturation` sur un écran qui écrit).
 *
 * 42 méthodes ont été protégées sur 20 composants. Quatre composants sont
 * volontairement exclus : ils agissent sur les données de l'utilisateur
 * lui-même (`MonProfil`, notifications) ou s'exécutent avant authentification
 * (`ResetPassword`).
 *
 * ⚠️ CES TESTS VÉRIFIENT LA GARANTIE, PAS SEULEMENT L'EXCEPTION : après le
 * refus, rien ne doit avoir changé en base.
 */
class AutorisationsEcrituresTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        foreach ([
            'view-stocks', 'manage-stocks',
            'view-elevage', 'manage-elevage',
            'view-parametres', 'manage-parametres',
            'view-rh', 'manage-rh',
        ] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }

        // Un rôle qui ne peut que CONSULTER.
        Role::findOrCreate('lecteur', 'web')->givePermissionTo([
            'view-stocks', 'view-elevage', 'view-parametres', 'view-rh',
        ]);
    }

    private function lecteur(): User
    {
        $u = User::create([
            'name' => 'Lecteur', 'username' => 'lecteur',
            'email' => 'lecteur@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $u->assignRole('lecteur');

        return $u;
    }

    /**
     * ⚠️ Un droit de lecture sur les stocks ne doit pas permettre d'archiver un
     * produit — l'écran était pourtant gardé par `can:view-stocks`.
     */
    public function test_a_reader_cannot_archive_a_product(): void
    {
        $categorie = new \App\Models\ProductCategory();
        $categorie->id = '11111111-1111-4111-8111-111111111111';
        $categorie->label = 'Aliments';
        $categorie->is_active = true;
        $categorie->save();

        $produit = \App\Models\Product::create([
            'sku' => 'ALI-001', 'name' => 'Provende ponte',
            'category_id' => $categorie->id, 'unit' => 'sac',
            'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 12, 'is_active' => true,
        ]);

        Livewire::actingAs($this->lecteur())
            ->test(\App\Livewire\Stocks\CatalogueProduits::class)
            ->call('archive', $produit->id)
            ->assertForbidden();

        $this->assertTrue((bool) $produit->fresh()->is_active,
            'le produit doit rester actif');
    }

    /**
     * ⚠️ Le référentiel des rations pilote la provende servie à tout le
     * cheptel : le modifier n'est pas une lecture.
     */
    public function test_a_reader_cannot_change_the_ration_referential(): void
    {
        Livewire::actingAs($this->lecteur())
            ->test(\App\Livewire\Elevage\ParametresElevage::class)
            ->set('ration_species_code', 'cuniculture')
            ->set('ration_stage_label', 'Lapin de chair')
            ->set('ration_grammes', 999)
            ->call('saveRation')
            ->assertForbidden();

        $this->assertEquals(0, \App\Models\FeedRationStandard::count());
    }

    /** ⚠️ Les données de l'entreprise figurent sur toutes les pièces émises. */
    public function test_a_reader_cannot_change_the_company_data(): void
    {
        // L'ecran lit les reglages au montage : sans eux il ne se monte pas.
        \App\Models\CompanySetting::firstOrCreate([], [
            'company_name' => 'Ferme École OLOUWACHEGOUN',
        ]);

        Livewire::actingAs($this->lecteur())
            ->test(\App\Livewire\Parametres\DonneesEntreprise::class)
            ->call('save')
            ->assertForbidden();
    }

    /** ⚠️ Un stagiaire enregistré engage l'exploitation. */
    public function test_a_reader_cannot_register_an_internship(): void
    {
        Livewire::actingAs($this->lecteur())
            ->test(\App\Livewire\RH\RegistreStagiaires::class)
            ->call('saveInternship')
            ->assertForbidden();

        $this->assertEquals(0, \App\Models\Internship::count());
    }

    /**
     * ⚠️⚠️ LES PERMISSIONS `manage-parametres` ET `manage-facturation`
     * EXISTENT ENFIN. Elles étaient appelées dans le code — neuf fois pour la
     * première — sans figurer dans le seeder : aucun rôle ne les portait, et le
     * projet n'a aucun contournement admin. Les écrans Restauration,
     * Réinitialisation et Sauvegardes étaient donc inaccessibles à TOUT LE
     * MONDE en base réelle, administrateur compris.
     */
    public function test_the_two_missing_permissions_now_exist_and_reach_the_admin(): void
    {
        // Le seeder est la source de vérité des rôles et permissions.
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $admin = User::create([
            'name' => 'Directeur', 'username' => 'admin',
            'email' => 'dg@olouwachegoun.bj',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $admin->assignRole('admin');

        $this->assertTrue($admin->can('manage-parametres'),
            'les onglets Restauration / Reinitialisation / Sauvegardes en dependent');
        $this->assertTrue($admin->can('manage-facturation'),
            'le module n avait qu une permission de lecture');
    }
}
