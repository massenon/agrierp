<?php

namespace Tests\Feature;

use App\Livewire\Stocks\ImportationMasse;
use App\Services\Import\ImportMasseService;
use App\Services\Import\ImportRefuse;
use App\Services\Import\LecteurXlsx;
use App\Services\Import\ModeleXlsxService;
use Livewire\Livewire;
use PhpOffice\PhpSpreadsheet\Cell\DataValidation;
use PhpOffice\PhpSpreadsheet\IOFactory;
use PhpOffice\PhpSpreadsheet\Spreadsheet;

/**
 * Ticket IMPORT-1 — les MODÈLES xlsx téléchargeables et le contrôle du FICHIER avant toute ligne (version, colonnes, limites).
 */
class ImportMasseModelesTest extends ImportMasseBase
{
    /** @return array<string, array{0: string}> */
    public static function modules(): array
    {
        return [
            'stocks' => ['stocks'], 'clients' => ['clients'], 'fournisseurs' => ['fournisseurs'],
            'employes' => ['employes'], 'plan_comptable' => ['plan_comptable'], 'rations' => ['rations'],
        ];
    }

    /** @dataProvider modules */
    public function test_le_modele_a_ses_quatre_feuilles_ses_en_tetes_exacts_et_sa_version(string $cle): void
    {
        $module = ImportMasseService::module($cle);
        $chemin = app(ModeleXlsxService::class)->fichier($module);
        $classeur = IOFactory::load($chemin);
        @unlink($chemin);

        $this->assertSame(['Instructions', 'Données', 'Listes', 'Modele'], $classeur->getSheetNames());
        $this->assertSame('hidden', $classeur->getSheetByName('Modele')->getSheetState(), 'La feuille technique est masquée.');

        $entetes = $classeur->getSheetByName('Données')->rangeToArray('A1:'.chr(64 + count($module->colonnes())).'1')[0];
        $this->assertSame(array_map(fn ($c) => $c->entete(), $module->colonnes()), $entetes);
        foreach ($module->colonnes() as $colonne) {
            $this->assertSame($colonne->obligatoire, str_ends_with($colonne->entete(), ' *'), 'Les colonnes obligatoires portent « * ».');
        }
        $this->assertNull($classeur->getSheetByName('Données')->getCell('A2')->getValue(), 'La feuille « Données » est VIDE : aucune ligne d\'exemple importée par erreur.');

        // Version et nom du modèle dans une cellule lisible, et dans la feuille « Instructions ».
        $meta = $classeur->getSheetByName('Modele');
        $this->assertSame($cle, $meta->getCell('B1')->getValue());
        $this->assertSame(1, $meta->getCell('B2')->getValue());
        $this->assertSame($module->empreinte(), $meta->getCell('B3')->getValue());
        $instructions = $classeur->getSheetByName('Instructions');
        $this->assertSame('Modèle « '.$module->libelle().' » — version 1', $instructions->getCell('A1')->getValue());
        $this->assertStringContainsString("NE RENOMMEZ PAS", implode(' ', array_column($instructions->toArray(), 1)));
        $this->assertStringContainsString('AAAA-MM-JJ', implode(' ', array_column($instructions->toArray(), 1)));
        $this->assertStringContainsString('ENTIERS', implode(' ', array_column($instructions->toArray(), 1)));
    }

    /** @dataProvider modules */
    public function test_l_empreinte_des_en_tetes_est_celle_de_la_version_courante(string $cle): void
    {
        $module = ImportMasseService::module($cle);

        // Changer une colonne SANS augmenter la version fait rougir ce test : un fichier d'une ancienne version serait lu avec de nouvelles colonnes.
        $this->assertSame($module->empreinteAttendue(), $module->empreinte());
        $this->assertSame(1, $module->version());
    }

    public function test_les_listes_deroulantes_du_modele_stocks_sont_alimentees_par_la_base(): void
    {
        $module = ImportMasseService::module('stocks');
        $classeur = app(ModeleXlsxService::class)->construire($module);

        $listes = $classeur->getSheetByName('Listes');
        $this->assertSame('categories', $listes->getCell('A1')->getValue());
        $nombre = \App\Models\ProductCategory::where('is_active', true)->count();
        $categories = array_column($listes->rangeToArray('A2:A'.($nombre + 1)), 0);
        $this->assertEqualsCanonicalizing(\App\Models\ProductCategory::where('is_active', true)->pluck('label')->all(), $categories);
        $this->assertContains('Équipements', $categories);
        $this->assertNull($listes->getCell('A'.($nombre + 2))->getValue());
        $this->assertSame('Fourchette', $listes->getCell('D2')->getValue());
        $this->assertSame('Sur devis', $listes->getCell('D3')->getValue());
        $this->assertContains('Aviculture', array_column($listes->rangeToArray('C2:C6'), 0), 'Filières : les espèces actives.');

        // Listes déroulantes : lues dans le XML du fichier ENREGISTRÉ (une validation par colonne-liste, sur toute la limite de lignes).
        $zip = new \ZipArchive();
        $zip->open($this->ecrire($classeur));
        $xml = $zip->getFromName('xl/worksheets/sheet2.xml');
        $zip->close();

        $limite = LecteurXlsx::LIGNES_MAX + 1;
        preg_match_all('/<dataValidation ([^>]*)>\s*<formula1>([^<]*)<\/formula1>/', $xml, $validations, PREG_SET_ORDER);
        $this->assertCount(5, $validations, 'Cinq colonnes à liste : catégorie, unité, filière, mode de prix, catégorie d\'effectif.');

        $parPlage = [];
        foreach ($validations as [, $attributs, $formule]) {
            preg_match('/sqref="([^"]+)"/', $attributs, $plage);
            $parPlage[$plage[1]] = [$attributs, html_entity_decode($formule)];
        }
        $this->assertSame("'Listes'!\$A\$2:\$A\$".($nombre + 1), $parPlage['B2:B'.$limite][1]);
        $this->assertStringContainsString('type="list"', $parPlage['B2:B'.$limite][0]);
        $this->assertStringContainsString('errorStyle="stop"', $parPlage['B2:B'.$limite][0], 'Catégorie : refus strict.');
        $this->assertStringContainsString('showDropDown="0"', $parPlage['B2:B'.$limite][0], 'La flèche de la liste déroulante est affichée.');
        $this->assertStringContainsString('errorStyle="warning"', $parPlage['C2:C'.$limite][0], 'Les unités sont une proposition : un avertissement, jamais un blocage.');
        $this->assertSame("'Listes'!\$D\$2:\$D\$3", $parPlage['E2:E'.$limite][1], 'Mode de prix : Fourchette / Sur devis.');
    }

    public function test_les_telephones_et_l_ifu_sont_au_format_texte_et_les_montants_entiers(): void
    {
        $clients = app(ModeleXlsxService::class)->construire(ImportMasseService::module('clients'))->getSheetByName('Données');
        $this->assertSame('@', $clients->getStyle('B2')->getNumberFormat()->getFormatCode());
        $this->assertSame('@', $clients->getStyle('E2')->getNumberFormat()->getFormatCode());

        $stocks = app(ModeleXlsxService::class)->construire(ImportMasseService::module('stocks'))->getSheetByName('Données');
        $this->assertSame('0', $stocks->getStyle('F2')->getNumberFormat()->getFormatCode());
        $this->assertSame('0', $stocks->getStyle('G2')->getNumberFormat()->getFormatCode());
    }

    public function test_le_nom_du_fichier_modele_porte_le_module_et_la_version(): void
    {
        $service = app(ModeleXlsxService::class);
        $this->assertSame('Modele_Stocks_v1.xlsx', $service->nomDeFichier(ImportMasseService::module('stocks')));
        $this->assertSame('Modele_Clients_v1.xlsx', $service->nomDeFichier(ImportMasseService::module('clients')));
    }

    public function test_l_ecran_telecharge_le_modele_du_module_autorise_seulement(): void
    {
        $admin = $this->utilisateur(['manage-stocks', 'manage-ventes', 'manage-achats']);
        Livewire::actingAs($admin)->test(ImportationMasse::class)
            ->call('choisirModule', 'clients')
            ->call('telechargerModele')
            ->assertFileDownloaded('Modele_Clients_v1.xlsx');

        Livewire::actingAs($this->utilisateur(['manage-ventes']))->test(ImportationMasse::class)
            ->set('module', 'stocks')
            ->call('telechargerModele')
            ->assertForbidden();
    }

    // ── Contrôle du FICHIER ────────────────────────────────────────────────────────────────────

    private function refus(callable $faire): string
    {
        try {
            $faire();
        } catch (ImportRefuse $e) {
            return $e->getMessage();
        }
        $this->fail('Le fichier aurait dû être refusé.');
    }

    public function test_une_autre_version_du_modele_est_refusee(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $message = $this->refus(fn () => $this->analyser('clients', [['nom' => 'A']], $user, ['version' => 2]));

        $this->assertSame('Ce fichier est le modèle « Clients » en version 2 ; la version 1 est attendue : téléchargez le modèle à jour.', $message);
    }

    public function test_un_autre_modele_est_refuse_en_le_nommant(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $message = $this->refus(fn () => $this->analyser('clients', [['nom' => 'A']], $user, ['modele' => 'fournisseurs']));

        $this->assertSame('Ce fichier n\'est pas le modèle « Clients » (version 1) : c\'est le modèle « Fournisseurs ». Téléchargez le modèle à jour.', $message);
    }

    public function test_un_classeur_sans_metadonnees_n_est_pas_un_modele(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $message = $this->refus(fn () => $this->analyser('clients', [['nom' => 'A']], $user, ['sans_meta' => true]));

        $this->assertStringStartsWith('Ce fichier n\'est pas un modèle LogiAgriERP', $message);
    }

    public function test_une_colonne_manquante_ou_renommee_est_nommee(): void
    {
        $user = $this->utilisateur(['manage-achats']);

        $manquante = $this->refus(fn () => $this->analyser('fournisseurs', [['nom' => 'A']], $user, ['retirer' => ['telephone']]));
        $this->assertSame('Colonne manquante ou renommée dans la feuille « Données » : « Téléphone * ». Ne renommez pas les en-têtes : téléchargez le modèle « Fournisseurs » à jour.', $manquante);

        $renommee = $this->refus(fn () => $this->analyser('fournisseurs', [['nom' => 'A']], $user, ['renommer' => ['nom' => 'Raison sociale', 'categorie' => 'Type']]));
        $this->assertStringContainsString('Colonnes manquantes ou renommées', $renommee);
        $this->assertStringContainsString('« Nom * », « Catégorie * »', $renommee);
    }

    public function test_une_extension_autre_que_xlsx_ou_csv_est_refusee(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $chemin = $this->fichier(ImportMasseService::module('clients'), [['nom' => 'A']]);

        $message = $this->refus(fn () => $this->service()->analyser('clients', $chemin, 'clients.txt', $user));
        $this->assertStringStartsWith('Seuls les fichiers Excel .xlsx (ou CSV .csv en repli) sont acceptés', $message);
    }

    public function test_un_fichier_illisible_ou_vide_est_refuse(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $dossier = sys_get_temp_dir().'/agrierp_import_'.uniqid();
        mkdir($dossier);

        file_put_contents($dossier.'/texte.xlsx', "nom;telephone\nA;0197000000\n");
        $message = $this->refus(fn () => $this->service()->analyser('clients', $dossier.'/texte.xlsx', 'texte.xlsx', $user));
        $this->assertStringContainsString('n\'est pas un classeur Excel (.xlsx) lisible', $message);

        file_put_contents($dossier.'/zip.xlsx', "PK\x03\x04 pas un vrai classeur");
        $message = $this->refus(fn () => $this->service()->analyser('clients', $dossier.'/zip.xlsx', 'zip.xlsx', $user));
        $this->assertStringContainsString('n\'est pas un classeur Excel (.xlsx) lisible', $message);

        file_put_contents($dossier.'/vide.xlsx', '');
        $this->assertStringContainsString('n\'est pas un classeur Excel', $this->refus(fn () => $this->service()->analyser('clients', $dossier.'/vide.xlsx', 'vide.xlsx', $user)));

        @unlink($dossier.'/texte.xlsx');
        @unlink($dossier.'/zip.xlsx');
        @unlink($dossier.'/vide.xlsx');
        @rmdir($dossier);
    }

    public function test_un_fichier_sans_ligne_est_refuse(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $message = $this->refus(fn () => $this->analyser('clients', [], $user));

        $this->assertSame('Le fichier ne contient aucune ligne à importer : remplissez la feuille « Données » sous les en-têtes.', $message);
    }

    public function test_un_fichier_trop_gros_est_refuse_avant_toute_lecture(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $dossier = sys_get_temp_dir().'/agrierp_import_'.uniqid();
        mkdir($dossier);
        $chemin = $dossier.'/gros.xlsx';
        file_put_contents($chemin, 'PK'.str_repeat('0', LecteurXlsx::TAILLE_MAX_OCTETS));

        $message = $this->refus(fn () => $this->service()->analyser('clients', $chemin, 'gros.xlsx', $user));
        $this->assertStringStartsWith('Le fichier dépasse 5 Mo', $message);
        @unlink($chemin);
        @rmdir($dossier);
    }

    public function test_cinq_mille_lignes_passent_et_cinq_mille_une_sont_refusees(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $lignes = [];
        for ($i = 1; $i <= LecteurXlsx::LIGNES_MAX; $i++) {
            $lignes[] = ['nom' => 'Client '.$i, 'telephone' => (string) (97000000 + $i)];
        }

        $lot = $this->analyser('clients', $lignes, $user);
        $this->assertSame(5000, $lot->lues);
        $this->assertSame(5000, $lot->valides);
        $this->assertSame(0, \App\Models\Customer::count(), 'Aperçu : aucune écriture.');

        $lignes[] = ['nom' => 'Client 5001', 'telephone' => '97005001'];
        $message = $this->refus(fn () => $this->analyser('clients', $lignes, $user));
        $this->assertSame('Le fichier dépasse 5 000 lignes : découpez-le en plusieurs fichiers.', $message);
    }

    public function test_les_lignes_vides_ne_comptent_pas_meme_nombreuses(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $module = ImportMasseService::module('clients');
        $classeur = app(ModeleXlsxService::class)->construire($module);
        $donnees = $classeur->getSheetByName('Données');
        $donnees->setCellValue('A2', 'Seule ligne');
        // 8 000 lignes « utilisées » (cellules vides mises en forme) sous la seule ligne remplie.
        $donnees->getStyle('D3:D8000')->getFont()->setBold(true);
        $chemin = $this->ecrire($classeur);

        $lot = $this->service()->analyser('clients', $chemin, 'vides.xlsx', $user);
        $this->assertSame(1, $lot->lues);
    }

    public function test_une_formule_n_est_jamais_evaluee(): void
    {
        $user = $this->utilisateur(['manage-ventes']);
        $module = ImportMasseService::module('clients');
        $classeur = app(ModeleXlsxService::class)->construire($module);
        $classeur->getSheetByName('Données')->setCellValue('A2', '=1+1');
        $chemin = $this->ecrire($classeur);

        $lot = $this->service()->analyser('clients', $chemin, 'formule.xlsx', $user);
        $this->assertSame('=1+1', $lot->lignes[0]['brut']['nom'], 'Le texte de la formule est lu, jamais son résultat.');
    }

    public function test_aucun_module_n_ecrit_hors_de_son_point_de_passage_unique(): void
    {
        // Garde de lecture de sources : l'importation n'écrit QUE par les fabriques de l'écran et de la synchronisation.
        foreach (glob(app_path('Services/Import/*.php')) as $fichier) {
            $source = file_get_contents($fichier);
            $this->assertDoesNotMatchRegularExpression('/DB::table|::insert\(|->insert\(|->stock_qty\s*=|StockMovement::create|->increment\(|->decrement\(|DB::(statement|unprepared)/', $source, basename($fichier).' écrit hors de son point de passage unique.');
            $this->assertDoesNotMatchRegularExpression('/(Product|Customer|Supplier)::(create|forceCreate|insert)\(/', $source, basename($fichier));
        }

        $stocks = file_get_contents(app_path('Services/Import/ImportStocksService.php'));
        $this->assertStringContainsString('ProductCatalogService::class)->creer(', $stocks);
        $this->assertStringContainsString('CustomerCatalogService::class)->creer(', file_get_contents(app_path('Services/Import/ImportClientsService.php')));
        $this->assertStringContainsString('SupplierCatalogService::class)->creer(', file_get_contents(app_path('Services/Import/ImportFournisseursService.php')));
        $this->assertStringContainsString('SaisieEmployeAction::class)->creer(', file_get_contents(app_path('Services/Import/ImportEmployesService.php')));
        $this->assertStringContainsString('PlanComptableService::class)->creer(', file_get_contents(app_path('Services/Import/ImportPlanComptableService.php')));
        $this->assertStringContainsString('RationStandardService::class)->creer(', file_get_contents(app_path('Services/Import/ImportRationsService.php')));
    }

    public function test_le_lien_du_menu_est_dans_le_groupe_administration_pour_qui_peut_importer(): void
    {
        $this->withoutVite();
        $this->seed(\Database\Seeders\RolesAndPermissionsSeeder::class);

        $lien = fn ($role) => (function () use ($role) {
            $user = \App\Models\User::create(['name' => 'U '.$role, 'username' => $role.uniqid(), 'email' => $role.uniqid().'@x.test', 'password' => bcrypt('x'), 'is_active' => true]);
            $user->assignRole($role);

            return $this->actingAs($user)->get('/dashboard')->getContent();
        })();

        foreach (['admin', 'caissier', 'animalier', 'comptable'] as $role) {
            $html = $lien($role);
            $this->assertMatchesRegularExpression('#ADMINISTRATION</p>\s*<div[^>]*>.*?href="/importation-masse".*?Importation en masse#s', $html, $role);
        }
        $this->assertStringContainsString('Administration &amp; Document', $lien('admin'));
        // IMPORT-2 à 4 : l'animalier (barème) et le comptable (plan comptable) voient désormais le lien ; un rôle sans aucun des six droits non.
        \App\Models\Role::findOrCreate('sans-droit-import', 'web')->syncPermissions(['view-stocks']);
        $this->assertStringNotContainsString('href="/importation-masse"', $lien('sans-droit-import'));
    }
}
