<?php

namespace Tests\Feature;

use App\Models\FiscalYear;
use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Models\Permission;
use App\Models\ProductCategory;
use App\Models\Role;
use App\Models\User;
use App\Services\Import\ImportMasseService;
use App\Services\Import\ModeleXlsxService;
use App\Services\Import\ModuleImport;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PhpOffice\PhpSpreadsheet\Cell\DataType;
use PhpOffice\PhpSpreadsheet\IOFactory;
use Tests\TestCase;

/**
 * Ticket IMPORT-1 — socle commun des tests de l'importation en masse : un exercice OUVERT, des catégories, une filière, des
 * comptes de droits distincts, et un FABRICANT DE FICHIERS xlsx (PhpSpreadsheet) qui part du VRAI modèle téléchargeable.
 */
abstract class ImportMasseBase extends TestCase
{
    use RefreshDatabase;

    /** @var array<int, string> */
    private array $aSupprimer = [];

    protected ProductCategory $categorie;

    protected LivestockSpecies $espece;

    protected function setUp(): void
    {
        parent::setUp();

        foreach (['manage-stocks', 'manage-ventes', 'manage-achats', 'view-stocks'] as $permission) {
            Permission::findOrCreate($permission, 'web');
        }

        FiscalYear::create([
            'year' => (int) now()->year,
            'start_date' => now()->startOfYear()->format('Y-m-d'),
            'end_date' => now()->endOfYear()->format('Y-m-d'),
            'status' => 'ouvert',
        ]);

        $this->categorie = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
        ProductCategory::create(['label' => 'Équipements', 'is_active' => true]);
        $this->espece = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Aviculture', 'is_enabled' => true]);
        ModuleConfig::create(['species_code' => 'aviculture', 'is_enabled' => true]);
    }

    protected function tearDown(): void
    {
        foreach ($this->aSupprimer as $fichier) {
            @unlink($fichier);
        }
        parent::tearDown();
    }

    /** @param array<int, string> $permissions */
    protected function utilisateur(array $permissions, string $nom = 'Importateur'): User
    {
        $role = Role::findOrCreate('role-'.md5(implode(',', $permissions).$nom), 'web');
        $role->syncPermissions($permissions);

        $user = User::create([
            'name' => $nom, 'username' => strtolower($nom).uniqid(), 'email' => strtolower($nom).uniqid().'@fermeolouwachegoun.com',
            'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true,
        ]);
        $user->assignRole($role);

        return $user;
    }

    protected function service(): ImportMasseService
    {
        return app(ImportMasseService::class);
    }

    /**
     * Fabrique un fichier d'importation à partir du VRAI modèle du module.
     *
     * @param  array<int, array<string, mixed>>  $lignes  clé de colonne → valeur (texte ou nombre)
     * @param  array{version?: int, modele?: string, sans_meta?: bool, renommer?: array<string, string>, retirer?: array<int, string>}  $options
     */
    protected function fichier(ModuleImport $module, array $lignes, array $options = [], string $nom = 'import.xlsx'): string
    {
        $classeur = app(ModeleXlsxService::class)->construire($module);
        $donnees = $classeur->getSheetByName('Données');

        $colonnes = [];
        foreach ($module->colonnes() as $i => $colonne) {
            $colonnes[$colonne->cle] = $i + 1;
        }

        foreach ($lignes as $r => $ligne) {
            foreach ($ligne as $cle => $valeur) {
                if (is_int($valeur) || is_float($valeur)) {
                    $donnees->setCellValue([$colonnes[$cle], $r + 2], $valeur);
                } else {
                    $donnees->setCellValueExplicit([$colonnes[$cle], $r + 2], (string) $valeur, DataType::TYPE_STRING);
                }
            }
        }

        foreach ($options['renommer'] ?? [] as $cle => $nouveau) {
            $donnees->setCellValueExplicit([$colonnes[$cle], 1], $nouveau, DataType::TYPE_STRING);
        }
        foreach ($options['retirer'] ?? [] as $cle) {
            $donnees->setCellValue([$colonnes[$cle], 1], null);
        }

        $meta = $classeur->getSheetByName('Modele');
        if (! empty($options['sans_meta'])) {
            $classeur->removeSheetByIndex($classeur->getIndex($meta));
        } else {
            if (isset($options['version'])) {
                $meta->setCellValue('B2', $options['version']);
            }
            if (isset($options['modele'])) {
                $meta->setCellValueExplicit('B1', $options['modele'], DataType::TYPE_STRING);
            }
        }

        return $this->ecrire($classeur, $nom);
    }

    protected function ecrire(\PhpOffice\PhpSpreadsheet\Spreadsheet $classeur, string $nom = 'import.xlsx'): string
    {
        $dossier = sys_get_temp_dir().'/agrierp_import_'.uniqid();
        mkdir($dossier);
        $chemin = $dossier.'/'.$nom;
        IOFactory::createWriter($classeur, 'Xlsx')->save($chemin);
        $this->aSupprimer[] = $chemin;

        return $chemin;
    }

    /** @param array<int, array<string, mixed>> $lignes */
    protected function analyser(string $module, array $lignes, User $user, array $options = [], string $nom = 'import.xlsx')
    {
        $chemin = $this->fichier(ImportMasseService::module($module), $lignes, $options, $nom);

        return $this->service()->analyser($module, $chemin, $nom, $user);
    }
}
