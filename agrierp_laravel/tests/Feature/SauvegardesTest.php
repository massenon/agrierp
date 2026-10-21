<?php

namespace Tests\Feature;

use App\Livewire\Parametres\Sauvegardes;
use App\Models\AuditLog;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\User;
use App\Services\SauvegardeService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ticket 14.57 (Sprint 14) — SAUVEGARDES DE LA BASE.
 *
 * 🔴 Le test qui compte le plus est celui de la TRAVERSÉE DE RÉPERTOIRE : le
 * téléchargement recevait un chemin depuis le navigateur et le servait tel
 * quel. Une méthode Livewire est appelable avec n'importe quel argument —
 * `../../.env` aurait livré les identifiants de la base.
 */
class SauvegardesTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('local');

        foreach (['view-parametres', 'manage-parametres'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-parametres', 'manage-parametres']);
        Role::findOrCreate('caissier', 'web');

        $this->admin = User::create([
            'name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $this->admin->assignRole('admin');
        $this->actingAs($this->admin);

        $categorie = ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
        Product::create([
            'sku' => 'ALI-001', 'name' => "Poulet d'un jour", 'category_id' => $categorie->id,
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 40, 'is_active' => true,
        ]);
    }

    /** Un export de module produit un fichier réel, nommé par sa portée. */
    public function test_a_module_export_produces_a_named_file(): void
    {
        $fichier = app(SauvegardeService::class)->genererModule('stocks');

        $this->assertNotNull($fichier);
        $this->assertStringEndsWith('_stocks.sql', $fichier);
        Storage::disk('local')->assertExists(SauvegardeService::DOSSIER.'/'.$fichier);
    }

    /** Le contenu exporté est réellement celui du module. */
    public function test_the_export_contains_the_module_data(): void
    {
        $fichier = app(SauvegardeService::class)->genererModule('stocks');
        $contenu = Storage::disk('local')->get(SauvegardeService::DOSSIER.'/'.$fichier);

        $this->assertStringContainsString('INSERT INTO `products`', $contenu);
        $this->assertStringContainsString('ALI-001', $contenu);
    }

    /**
     * ⚠️ Les valeurs passent par `PDO::quote` : un libellé contenant une
     * apostrophe — « Poulet d'un jour » — produirait sinon un fichier SQL
     * invalide, et on ne s'en apercevrait qu'au moment de restaurer.
     */
    public function test_apostrophes_are_escaped(): void
    {
        $fichier = app(SauvegardeService::class)->genererModule('stocks');
        $contenu = Storage::disk('local')->get(SauvegardeService::DOSSIER.'/'.$fichier);

        // ⚠️ L'ECHAPPEMENT SUIT LE DIALECTE DE LA CONNEXION : SQLite double
        // l'apostrophe, MySQL la precede d'une barre. C'est exactement ce
        // qu'il faut, le fichier etant genere sur la meme base que celle ou
        // il sera relu. L'assertion porte donc sur la PROPRIETE : l'apostrophe
        // n'est jamais laissee nue au milieu d'une chaine SQL.
        $doublee = str_contains($contenu, "Poulet d" . "''" . "un jour");
        $barree = str_contains($contenu, "Poulet d" . chr(92) . "'" . "un jour");

        $this->assertTrue($doublee || $barree, "l'apostrophe doit etre echappee");
    }

    /** Un module inconnu ne produit rien. */
    public function test_an_unknown_module_produces_nothing(): void
    {
        $this->assertNull(app(SauvegardeService::class)->genererModule('inexistant'));
    }

    /** La portée est lisible dans le listing — c'est la colonne « Table ». */
    public function test_the_listing_exposes_the_scope(): void
    {
        app(SauvegardeService::class)->genererModule('elevage');

        $liste = app(SauvegardeService::class)->lister();

        $this->assertCount(1, $liste);
        $this->assertEquals('Élevage', $liste[0]['portee']);
    }

    /**
     * ⚠️ Les sauvegardes du ticket 11.1 n'ont aucun suffixe : elles doivent
     * s'afficher comme complètes, pas comme inconnues.
     */
    public function test_legacy_backups_are_shown_as_complete(): void
    {
        Storage::disk('local')->put(
            SauvegardeService::DOSSIER.'/backup_2026-08-01_0200.sql',
            '-- ancien format',
        );

        $liste = app(SauvegardeService::class)->lister();

        $this->assertEquals('Base complète', $liste[0]['portee']);
    }

    /**
     * ⚠️ Un export de données seules le DIT dans sa portée : ce fichier ne
     * restaure rien sur une base vierge.
     */
    public function test_a_data_only_export_says_so(): void
    {
        Storage::disk('local')->put(
            SauvegardeService::DOSSIER.'/backup_2026-08-18_1400_donnees.sql',
            '-- donnees seules',
        );

        $this->assertEquals(
            'Toutes les données (sans schéma)',
            app(SauvegardeService::class)->lister()[0]['portee'],
        );
    }

    /**
     * ⚠️⚠️ LE TEST LE PLUS IMPORTANT — TRAVERSÉE DE RÉPERTOIRE. Une méthode
     * Livewire est appelable avec n'importe quel argument : sans vérification,
     * `../../.env` aurait servi les identifiants de la base.
     */
    public function test_a_traversal_attempt_serves_nothing(): void
    {
        $service = app(SauvegardeService::class);

        $this->assertNull($service->chemin('../../.env'));
        $this->assertNull($service->chemin('../.env'));
        $this->assertNull($service->chemin('.env'));
        $this->assertNull($service->chemin('inexistant.sql'));
    }

    /** Un fichier réellement présent dans le dossier, lui, est servi. */
    public function test_a_real_backup_is_served(): void
    {
        $fichier = app(SauvegardeService::class)->genererModule('stocks');

        $this->assertNotNull(app(SauvegardeService::class)->chemin($fichier));
    }

    /** Le téléchargement se journalise : c'est le fichier le plus sensible. */
    public function test_downloading_is_journalled(): void
    {
        $fichier = app(SauvegardeService::class)->genererModule('stocks');

        Livewire::test(Sauvegardes::class)->call('telecharger', $fichier);

        $this->assertEquals(1, AuditLog::where('action', 'database.backup_downloaded')->count());
    }

    /** Un nom hostile passé à l'écran ne sert rien et ne journalise rien. */
    public function test_a_hostile_name_downloads_nothing(): void
    {
        Livewire::test(Sauvegardes::class)
            ->call('telecharger', '../../.env')
            ->assertDispatched('toast');

        $this->assertEquals(0, AuditLog::where('action', 'database.backup_downloaded')->count());
    }

    /** Un module doit être choisi avant l'export. */
    public function test_a_module_must_be_chosen(): void
    {
        Livewire::test(Sauvegardes::class)
            ->call('genererModule')
            ->assertHasErrors('moduleAExporter');
    }

    /**
     * ⚠️ Une sauvegarde contient l'INTÉGRALITÉ de la base — salaires compris.
     * Un non-administrateur n'y touche pas.
     */
    public function test_a_non_admin_cannot_download(): void
    {
        $fichier = app(SauvegardeService::class)->genererModule('stocks');

        $caissier = User::create([
            'name' => 'Caissière', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $caissier->assignRole('caissier');
        $this->actingAs($caissier);

        $refuse = false;

        try {
            Livewire::test(Sauvegardes::class)->call('telecharger', $fichier);
        } catch (\Throwable $e) {
            $refuse = true;
        }

        $this->assertTrue($refuse);
        $this->assertEquals(0, AuditLog::where('action', 'database.backup_downloaded')->count());
    }

    /** Les modules exportables et leurs tables sont déclarés explicitement. */
    public function test_every_module_declares_real_tables(): void
    {
        foreach (SauvegardeService::modules() as $cle => $definition) {
            $this->assertNotEmpty($definition['tables'], "le module {$cle} declare des tables");
            $this->assertNotEmpty($definition['libelle']);
        }
    }
}
