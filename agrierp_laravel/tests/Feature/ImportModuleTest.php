<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Permission;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\User;
use App\Services\ImportModuleService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Ticket 14.58 (Sprint 14) — IMPORT D'UN MODULE.
 *
 * ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. Exécuter un fichier SQL téléversé
 * reviendrait à accepter des instructions arbitraires sur la base : `DROP
 * TABLE`, `UPDATE users SET password = …`, `DELETE FROM accounting_entries`.
 * Rien n'est jamais exécuté tel quel — le fichier est analysé, et seules les
 * insertions vers les tables du module choisi sont retenues.
 *
 * Les quatre tests d'attaque sont les plus importants du fichier.
 */
class ImportModuleTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['view-parametres', 'manage-parametres'] as $nom) {
            Permission::findOrCreate($nom, 'web');
        }
        Role::findOrCreate('admin', 'web')->givePermissionTo(['view-parametres', 'manage-parametres']);

        $admin = User::create([
            'name' => 'Directeur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
            'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
        ]);
        $admin->assignRole('admin');
        $this->actingAs($admin);

        // ⚠️ `id` N'EST PAS ASSIGNABLE EN MASSE (protection contre l'ecrasement
        // d'UUID) : le passer a `create()` le laisse simplement generer le sien,
        // et la reference du test pointerait alors dans le vide.
        $categorie = new ProductCategory();
        $categorie->id = '11111111-1111-4111-8111-111111111111';
        $categorie->label = 'Aliments';
        $categorie->is_active = true;
        $categorie->save();
    }

    /**
     * Un VRAI export du module « Stocks » contient aussi ses catégories : les
     * omettre ferait échouer la référence, et le test ne refléterait pas ce que
     * l'application produit réellement.
     */
    private function insertionProduit(string $sku = 'ALI-001', string $nom = 'Aliment ponte'): string
    {
        return "INSERT INTO `product_categories` (`id`, `label`, `is_active`) VALUES "
            ."('11111111-1111-4111-8111-111111111111', 'Aliments', 1);
"
            ."INSERT INTO `products` (`id`, `sku`, `name`, `category_id`, `unit`, `pricing_mode`, "
            ."`tva_rate`, `stock_qty`, `is_active`) VALUES "
            ."('22222222-2222-4222-8222-222222222222', '{$sku}', '{$nom}', "
            ."'11111111-1111-4111-8111-111111111111', 'sac', 'fourchette', 0, 40, 1);";
    }

    /** Le flux nominal : les insertions du module sont appliquées. */
    public function test_a_module_export_is_imported(): void
    {
        $resultat = app(ImportModuleService::class)
            ->importer($this->insertionProduit(), 'stocks');

        $this->assertEquals(2, $resultat['inserees'], 'la categorie et le produit');
        $this->assertEquals(0, $resultat['rejetees']);
        $this->assertEquals('Aliment ponte', Product::first()->name);
    }

    /** L'import est journalisé : c'est une opération destructrice. */
    public function test_the_import_is_journalled(): void
    {
        app(ImportModuleService::class)->importer($this->insertionProduit(), 'stocks');

        $this->assertEquals(1, AuditLog::where('action', 'module.imported')->count());
    }

    /**
     * ⚠️⚠️ ATTAQUE 1 — `DROP TABLE`. Un fichier exécuté tel quel détruirait le
     * schéma. L'instruction doit être refusée ET signalée.
     */
    public function test_a_drop_statement_is_refused_and_reported(): void
    {
        $sql = "DROP TABLE products;\n".$this->insertionProduit();

        $resultat = app(ImportModuleService::class)->importer($sql, 'stocks');

        $this->assertEquals(2, $resultat['inserees']);
        $this->assertEquals(1, $resultat['rejetees']);
        $this->assertStringContainsString('DROP', implode(' ', $resultat['motifs']));
        // La table existe toujours : la preuve que rien n'a été exécuté.
        $this->assertEquals(1, Product::count());
    }

    /**
     * ⚠️⚠️ ATTAQUE 2 — ÉLÉVATION DE PRIVILÈGE. Un export « Stocks » contenant
     * un `INSERT INTO users` créerait un compte administrateur.
     */
    public function test_an_insert_outside_the_module_is_refused(): void
    {
        $sql = "INSERT INTO `users` (`id`, `name`, `username`, `email`, `password`, `is_active`) "
            ."VALUES ('33333333-3333-4333-8333-333333333333', 'Intrus', 'intrus', "
            ."'intrus@example.com', 'x', 1);";

        $resultat = app(ImportModuleService::class)->importer($sql, 'stocks');

        $this->assertEquals(0, $resultat['inserees']);
        $this->assertEquals(1, $resultat['rejetees']);
        $this->assertStringContainsString('users', implode(' ', $resultat['motifs']));
        $this->assertEquals(1, User::count(), "aucun compte n'a ete cree");
    }

    /**
     * ⚠️⚠️ ATTAQUE 3 — `UPDATE` sur les mots de passe. Refusé au même titre :
     * seules les insertions passent.
     */
    public function test_an_update_statement_is_refused(): void
    {
        $motDePasseAvant = User::first()->password;

        $resultat = app(ImportModuleService::class)
            ->importer("UPDATE users SET password = 'compromis';", 'stocks');

        $this->assertEquals(0, $resultat['inserees']);
        $this->assertEquals(1, $resultat['rejetees']);
        $this->assertEquals($motDePasseAvant, User::first()->password);
    }

    /**
     * ⚠️⚠️ ATTAQUE 4 — `DELETE` sur la comptabilité. Refusé.
     */
    public function test_a_delete_statement_is_refused(): void
    {
        $resultat = app(ImportModuleService::class)
            ->importer("DELETE FROM accounting_entries;", 'comptabilite');

        $this->assertEquals(0, $resultat['inserees']);
        $this->assertEquals(1, $resultat['rejetees']);
    }

    /**
     * ⚠️ L'IMPORT REMPLACE, IL NE FUSIONNE PAS : une fusion produirait des
     * doublons sur des clés déjà connues.
     */
    public function test_the_import_replaces_rather_than_merges(): void
    {
        Product::create([
            'sku' => 'ANCIEN', 'name' => 'Ancien produit',
            'category_id' => '11111111-1111-4111-8111-111111111111',
            'unit' => 'u', 'pricing_mode' => 'fourchette', 'tva_rate' => 0,
            'stock_qty' => 5, 'is_active' => true,
        ]);

        app(ImportModuleService::class)->importer($this->insertionProduit(), 'stocks');

        $this->assertEquals(1, Product::count());
        $this->assertEquals('ALI-001', Product::first()->sku);
    }

    /** Les valeurs contenant une apostrophe traversent l'aller-retour. */
    public function test_apostrophes_survive_the_round_trip(): void
    {
        $sql = str_replace('Aliment ponte', "Poulet d''un jour", $this->insertionProduit());

        app(ImportModuleService::class)->importer($sql, 'stocks');

        $this->assertEquals("Poulet d'un jour", Product::first()->name);
    }

    /**
     * ⚠️ Un point-virgule DANS une valeur ne doit pas couper l'instruction :
     * le libellé serait tronqué et la ligne rejetée.
     */
    public function test_a_semicolon_inside_a_value_does_not_split_the_statement(): void
    {
        $sql = str_replace('Aliment ponte', 'Aliment ponte; croissance', $this->insertionProduit());

        $resultat = app(ImportModuleService::class)->importer($sql, 'stocks');

        $this->assertEquals(2, $resultat['inserees']);
        $this->assertEquals('Aliment ponte; croissance', Product::first()->name);
    }

    /** Les commentaires du fichier n'entrent pas dans le décompte des rejets. */
    public function test_comments_are_not_counted_as_refusals(): void
    {
        $sql = "-- Sauvegarde AgriERP\n-- Table : products\n".$this->insertionProduit();

        $resultat = app(ImportModuleService::class)->importer($sql, 'stocks');

        $this->assertEquals(2, $resultat['inserees']);
        $this->assertEquals(0, $resultat['rejetees']);
    }

    /** Un module inconnu ne touche à rien. */
    public function test_an_unknown_module_touches_nothing(): void
    {
        $resultat = app(ImportModuleService::class)
            ->importer($this->insertionProduit(), 'inexistant');

        $this->assertEquals(0, $resultat['inserees']);
        $this->assertEquals(0, Product::count());
    }

    /** Une valeur NULL est restituée comme telle, pas comme la chaîne « NULL ». */
    public function test_null_values_stay_null(): void
    {
        // La categorie accompagne le produit, comme dans un export reel : le
        // remplacement vide d'abord les tables du module.
        $sql = "INSERT INTO `product_categories` (`id`, `label`, `is_active`) VALUES "
            ."('11111111-1111-4111-8111-111111111111', 'Aliments', 1);"
            ."INSERT INTO `products` (`id`, `sku`, `name`, `category_id`, `unit`, "
            ."`pricing_mode`, `tva_rate`, `stock_qty`, `is_active`, `description`) VALUES "
            ."('44444444-4444-4444-8444-444444444444', 'X-1', 'Sans description', "
            ."'11111111-1111-4111-8111-111111111111', 'u', 'fourchette', 0, 0, 1, NULL);";

        app(ImportModuleService::class)->importer($sql, 'stocks');

        $this->assertNull(Product::first()->description);
    }
}
