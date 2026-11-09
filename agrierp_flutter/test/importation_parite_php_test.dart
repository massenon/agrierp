import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/importation/importation_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket IMPORT-1 — PARITÉ EXÉCUTÉE de l'importation en masse : le VRAI `ImportMasseService` du serveur.
///
/// ⚠️⚠️ Rien n'est recopié. Le PHP (SQLite en mémoire, migrations réelles) fabrique les fichiers xlsx avec le VRAI modèle
/// (PhpSpreadsheet) et un jeu de lignes (valides, doublons, déjà présentes, erreurs de chaque règle), les ANALYSE
/// (`analyser`) et rend état et motif de chaque ligne. Le poste lit LES MÊMES FICHIERS avec le paquet `excel`, sur une base
/// semée des mêmes fiches, et le test compare ligne par ligne : numéro, état, motif (mot pour mot), doublon, identifiant
/// déterministe. Les colonnes, la version et l'empreinte du modèle, et les normalisations de cellule, sont comparées de même.
void main() {
  final saut = sautSansPhp();

  const script = r'''<?php
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
use App\Models\{ProductCategory, LivestockSpecies, ModuleConfig, Product, Customer, Supplier, FiscalYear, User, Permission, Role, Employee, ChartOfAccount, FeedRationStandard};
use App\Services\Import\{ImportMasseService, ModeleXlsxService, ModuleImport};
use PhpOffice\PhpSpreadsheet\Cell\DataType;
use PhpOffice\PhpSpreadsheet\IOFactory;

FiscalYear::create(['year' => (int) now()->year, 'start_date' => now()->startOfYear()->format('Y-m-d'), 'end_date' => now()->endOfYear()->format('Y-m-d'), 'status' => 'ouvert']);
$cat = ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
ProductCategory::create(['label' => 'Équipements', 'is_active' => true]);
$esp = LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Aviculture', 'is_enabled' => true]);
ModuleConfig::create(['species_code' => 'aviculture', 'is_enabled' => true]);
Product::create(['sku' => 'AVI-001', 'name' => 'Poulet fermier', 'category_id' => $cat->id, 'species_id' => $esp->id, 'unit' => 'U', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 2, 'stock_qty' => 7, 'is_active' => true]);
Customer::create(['name' => 'Boulangerie Le Bon Pain', 'phone' => '+229 0197123456', 'is_active' => true]);
Supplier::create(['name' => 'Quincaillerie Centrale', 'category' => 'Matériel', 'phone' => '+22997112233', 'is_active' => true]);
Employee::create(['first_name' => 'Marie', 'last_name' => 'Adjovi', 'position' => 'Comptable', 'hire_date' => '2023-05-10', 'status' => 'actif', 'is_active' => true]);
Employee::create(['first_name' => 'Luc', 'last_name' => 'Zinsou', 'position' => 'Ancien', 'hire_date' => '2020-01-01', 'status' => 'actif', 'is_active' => false]);
ChartOfAccount::create(['code' => '6061', 'label' => 'Fournitures', 'class' => 6, 'is_active' => true]);
ChartOfAccount::create(['code' => '6062', 'label' => 'Archivé', 'class' => 6, 'is_active' => false]);
FeedRationStandard::create(['species_code' => 'aviculture', 'stage_label' => 'Pondeuse (adulte)', 'ration_g_per_day' => 120, 'is_active' => true]);
FeedRationStandard::create(['species_code' => 'aviculture', 'stage_label' => 'Stade archivé', 'ration_g_per_day' => 10, 'is_active' => false]);
$perms = ['manage-stocks', 'manage-ventes', 'manage-achats', 'manage-rh', 'manage-comptabilite', 'manage-elevage'];
foreach ($perms as $p) { Permission::findOrCreate($p, 'web'); }
$role = Role::findOrCreate('importeur', 'web'); $role->syncPermissions($perms);
$user = User::create(['name' => 'Importeur', 'username' => 'imp', 'email' => 'imp@x.test', 'password' => bcrypt('x'), 'is_active' => true]);
$user->assignRole($role);

$sortie = ['graines' => [
    'cat' => $cat->id, 'esp' => $esp->id, 'produit' => Product::first()->id, 'produit_sku' => 'AVI-001',
    'employes' => Employee::all()->map(fn ($e) => ['id' => $e->id, 'prenom' => $e->first_name, 'nom' => $e->last_name, 'poste' => (string) $e->position, 'embauche' => $e->hire_date?->format('Y-m-d'), 'actif' => (bool) $e->is_active])->all(),
    'comptes' => ChartOfAccount::all()->map(fn ($c) => ['id' => $c->id, 'code' => $c->code, 'label' => $c->label, 'classe' => (int) $c->class, 'actif' => (bool) $c->is_active])->all(),
    'rations' => FeedRationStandard::all()->map(fn ($r) => ['id' => $r->id, 'espece' => $r->species_code, 'stade' => $r->stage_label, 'grammes' => (int) $r->ration_g_per_day, 'actif' => (bool) $r->is_active])->all(),
], 'modules' => []];
foreach ($in['modules'] as $cle => $lignes) {
    $module = ImportMasseService::module($cle);
    $classeur = app(ModeleXlsxService::class)->construire($module);
    $donnees = $classeur->getSheetByName('Données');
    $pos = []; foreach ($module->colonnes() as $i => $c) { $pos[$c->cle] = $i + 1; }
    foreach ($lignes as $r => $ligne) {
        foreach ($ligne as $k => $v) {
            if (is_int($v) || is_float($v)) { $donnees->setCellValue([$pos[$k], $r + 2], $v); }
            else { $donnees->setCellValueExplicit([$pos[$k], $r + 2], (string) $v, DataType::TYPE_STRING); }
        }
    }
    $chemin = sys_get_temp_dir().'/parite_import_'.$cle.'_'.getmypid().'.xlsx';
    IOFactory::createWriter($classeur, 'Xlsx')->save($chemin);
    $lot = app(ImportMasseService::class)->analyser($cle, $chemin, 'import.xlsx', $user);
    $res = [];
    foreach ($lot->lignes as $l) {
        $id = null;
        if ($l['statut'] === 'valide') { $id = $module->idLigne($module->valider($l['brut'])['valeurs']); }
        $res[] = ['ligne' => $l['ligne'], 'statut' => $l['statut'], 'motif' => $l['motif'], 'doublon' => $l['doublon'], 'id' => $id];
    }
    $sortie['modules'][$cle] = [
        'fichier' => $chemin, 'lignes' => $res, 'bloquant' => $lot->rapport['bloquant'],
        'version' => $module->version(), 'empreinte' => $module->empreinte(), 'permission' => $module->permission(),
        'entetes' => array_map(fn ($c) => $c->entete(), $module->colonnes()),
        'cles' => array_map(fn ($c) => $c->cle, $module->colonnes()),
        'libelle' => $module->libelle(),
        'liste_categories' => $module->listes()['categories'] ?? [],
        'listes' => $module->listes(),
        'sensibles' => $module->colonnesSensibles(),
        'designations' => array_map(fn ($l) => $l['designation'], $lot->lignes),
    ];
}
$f = app(App\Services\FusionReferentielsService::class);
$sortie['normalisations'] = [];
foreach ($in['textes'] as $t) {
    $sortie['normalisations'][] = [
        'cle' => App\Services\Import\LectureValeurs::cle($t),
        'tel' => $f->normaliserTelephone($t),
        'entier' => App\Services\Import\LectureValeurs::entier($t),
        'decimal' => App\Services\Import\LectureValeurs::decimal($t),
    ];
}
echo json_encode($sortie);
''';

  String l(int n, [String c = 'x']) => List.filled(n, c).join();

  final stocks = <Map<String, Object>>[
    {'nom': 'Poulet de chair', 'categorie': 'Aviculture', 'unite': 'u', 'filiere': 'Aviculture', 'mode_prix': 'Fourchette', 'prix_min': 3000, 'prix_max': 4000, 'tva': 0, 'seuil': 5, 'stock_initial': 12}, // 2 valide
    {'nom': 'Aliment ponte', 'categorie': 'aviculture', 'unite': 'sac', 'filiere': '', 'mode_prix': 'Sur devis', 'prix_min': '', 'prix_max': '', 'tva': 18, 'seuil': 10, 'stock_initial': '8,5'}, // 3 valide
    {'nom': 'Prix décimal', 'categorie': 'Aviculture', 'unite': 'u', 'mode_prix': 'Fourchette', 'prix_min': '3000,50', 'prix_max': 4000, 'tva': 0, 'seuil': 1, 'stock_initial': 1}, // 4
    {'nom': 'TVA folle', 'categorie': 'Aviculture', 'unite': 'u', 'mode_prix': 'Fourchette', 'prix_min': 1, 'prix_max': 2, 'tva': 120, 'seuil': 1, 'stock_initial': 1}, // 5
    {'nom': 'Max sous min', 'categorie': 'Aviculture', 'unite': 'u', 'mode_prix': 'Fourchette', 'prix_min': 5000, 'prix_max': 4000, 'tva': 0, 'seuil': 1, 'stock_initial': 1}, // 6
    {'nom': 'Catégorie inconnue', 'categorie': 'Jardinage', 'unite': 'u', 'mode_prix': 'Fourchette', 'prix_min': 1, 'prix_max': 2, 'tva': 0, 'seuil': 1, 'stock_initial': 1}, // 7
    {'nom': '', 'categorie': 'Aviculture', 'unite': 'u', 'mode_prix': 'Fourchette', 'prix_min': 1, 'prix_max': 2, 'tva': 0, 'seuil': 1, 'stock_initial': ''}, // 8
    {'nom': 'Stock négatif', 'categorie': 'Aviculture', 'unite': 'u', 'mode_prix': 'Fourchette', 'prix_min': 1, 'prix_max': 2, 'tva': 0, 'seuil': 1, 'stock_initial': -3}, // 9
    {'nom': 'Mode inconnu', 'categorie': 'Aviculture', 'unite': 'u', 'mode_prix': 'Gratuit', 'tva': 0, 'seuil': 1, 'stock_initial': 1}, // 10
    {'nom': 'Sans prix', 'categorie': 'Aviculture', 'unite': 'u', 'mode_prix': 'Fourchette', 'tva': 0, 'seuil': 1, 'stock_initial': 1}, // 11
    {'nom': '  ALIMENT   ponte ', 'categorie': 'Aviculture', 'unite': 'SAC', 'mode_prix': 'Sur devis', 'tva': 0, 'seuil': 1, 'stock_initial': 1}, // 12 doublon de 3
    {'nom': 'Poulet fermier', 'categorie': 'Aviculture', 'unite': 'u', 'filiere': 'Aviculture', 'mode_prix': 'Fourchette', 'prix_min': 1, 'prix_max': 2, 'tva': 0, 'seuil': 1, 'stock_initial': 100}, // 13 déjà au catalogue
    {'nom': 'Min vide', 'categorie': 'Aviculture', 'unite': 'u', 'mode_prix': 'Fourchette', 'prix_max': 4000, 'tva': 0, 'seuil': 1, 'stock_initial': 1}, // 14
    {'nom': 'Effectif faux', 'categorie': 'Aviculture', 'unite': 'u', 'filiere': 'Aviculture', 'mode_prix': 'Sur devis', 'tva': 0, 'seuil': 1, 'stock_initial': 1, 'categorie_effectif': 'Cochon'}, // 15
    {'nom': 'Reproducteur vif', 'categorie': 'Aviculture', 'unite': 'u', 'filiere': 'Aviculture', 'mode_prix': 'Sur devis', 'tva': 0, 'seuil': 1, 'stock_initial': 3, 'categorie_effectif': 'Reproducteur'}, // 16
    {'nom': l(151), 'categorie': 'Aviculture', 'unite': 'u', 'mode_prix': 'Sur devis', 'tva': 0, 'seuil': 1, 'stock_initial': 1}, // 17
    {'nom': 'Unité trop longue', 'categorie': 'Aviculture', 'unite': l(21), 'mode_prix': 'Sur devis', 'tva': 0, 'seuil': 1, 'stock_initial': 1}, // 18
    {'nom': 'Filière inconnue', 'categorie': 'Aviculture', 'unite': 'u', 'filiere': 'Aquaculture', 'mode_prix': 'Sur devis', 'tva': 0, 'seuil': 1, 'stock_initial': 1}, // 19
    {'nom': 'Tva texte', 'categorie': 'Aviculture', 'unite': 'u', 'mode_prix': 'Sur devis', 'tva': 'dix', 'seuil': -1, 'stock_initial': 1}, // 20
    {'nom': 'Nombres à espaces', 'categorie': 'Équipements', 'unite': 'u', 'mode_prix': 'Fourchette', 'prix_min': '1 500', 'prix_max': '2 500', 'tva': '5,5', 'seuil': '2', 'stock_initial': '1 000'}, // 21 valide
  ];

  final clients = <Map<String, Object>>[
    {'nom': 'Boulangerie Du Plateau', 'telephone': '0197123456', 'email': 'a@bonpain.example', 'ville': 'Pobè', 'ifu': '3201234567890'}, // 2 valide
    {'nom': 'Mme Adjovi', 'telephone': '', 'email': '', 'ville': 'Ikpinlè', 'ifu': ''}, // 3 valide sans téléphone
    {'nom': 'IFU court', 'telephone': '0197000001', 'ifu': '320123456789'}, // 4
    {'nom': 'Mail faux', 'telephone': '0197000002', 'email': 'pas-un-mail'}, // 5
    {'nom': l(151), 'telephone': '0197000003'}, // 6
    {'nom': '', 'telephone': '0197000004'}, // 7
    {'nom': 'BOULANGERIE du plateau', 'telephone': '+229 01 97 12 34 56'}, // 8 doublon de 2
    {'nom': 'Boulangerie Le Bon Pain', 'telephone': '0197123456', 'ville': 'Cotonou'}, // 9 déjà en base
    {'nom': 'mme  ADJOVI', 'telephone': ''}, // 10 doublon de 3 (sans téléphone)
    {'nom': 'Téléphone numérique', 'telephone': 97123457}, // 11 valide
    {'nom': 'Téléphone long', 'telephone': '9' * 31}, // 12
    {'nom': 'Société Évolution', 'telephone': '0196111111'}, // 13 valide
    {'nom': 'societe evolution', 'telephone': '0196111111'}, // 14 doublon de 13 (accents)
    {'nom': 'Ville longue', 'telephone': '0196111112', 'ville': l(101)}, // 15
  ];

  final fournisseurs = <Map<String, Object>>[
    {'nom': 'Provenderie du Plateau', 'categorie': 'Aliments', 'telephone': '0197654321', 'adresse': 'Route de Kétou'}, // 2 valide
    {'nom': 'Sans téléphone', 'categorie': 'Aliments', 'telephone': ''}, // 3
    {'nom': 'Catégorie inconnue', 'categorie': 'Jardinage', 'telephone': '0197000002'}, // 4
    {'nom': 'Sans catégorie', 'categorie': '', 'telephone': '0197000003'}, // 5
    {'nom': 'Téléphone long', 'categorie': 'Autre', 'telephone': '9' * 31}, // 6
    {'nom': 'PROVENDERIE du plateau', 'categorie': 'Aliments', 'telephone': '01 97 65 43 21'}, // 7 doublon de 2
    {'nom': 'quincaillerie centrale', 'categorie': 'Autre', 'telephone': '97112233'}, // 8 déjà en base
    {'nom': 'Adresse longue', 'categorie': 'Matériel', 'telephone': '0197000009', 'adresse': l(256)}, // 9
    {'nom': 'Produits vétérinaires', 'categorie': 'produits VÉTÉRINAIRES', 'telephone': '0196112233'}, // 10 valide
    {'nom': 'Court tel', 'categorie': 'Autre', 'telephone': '123'}, // 11 valide (téléphone court : pas de fusion)
  ];

  final employes = <Map<String, Object>>[
    {'nom': 'AGBOTON', 'prenom': 'Pascal', 'poste': 'Gardien', 'date_embauche': '2024-03-01', 'salaire': '45000', 'statut': 'Actif'}, // 2 valide
    {'nom': 'DOSSOU', 'prenom': 'Clarisse', 'poste': 'Aide', 'date_embauche': '2025-09-15', 'salaire': '', 'statut': 'congé'}, // 3 valide
    {'nom': '', 'prenom': 'Sans nom', 'poste': 'X', 'date_embauche': '2024-01-01'}, // 4
    {'nom': 'Sans prénom', 'prenom': '', 'poste': 'X', 'date_embauche': '2024-01-01'}, // 5
    {'nom': 'Sans poste', 'prenom': 'P', 'poste': '', 'date_embauche': '2024-01-01'}, // 6
    {'nom': 'Date française', 'prenom': 'P', 'poste': 'X', 'date_embauche': '01/03/2024'}, // 7
    {'nom': 'Date impossible', 'prenom': 'P', 'poste': 'X', 'date_embauche': '2024-02-31'}, // 8
    {'nom': 'Sans date', 'prenom': 'P', 'poste': 'X', 'date_embauche': ''}, // 9
    {'nom': 'Statut inconnu', 'prenom': 'P', 'poste': 'X', 'date_embauche': '2024-01-01', 'statut': 'Retraité'}, // 10
    {'nom': 'Salaire décimal', 'prenom': 'P', 'poste': 'X', 'date_embauche': '2024-01-01', 'salaire': '45000,5'}, // 11
    {'nom': 'N' * 101, 'prenom': 'P', 'poste': 'X', 'date_embauche': '2024-01-01'}, // 12
    {'nom': 'agbotôn', 'prenom': 'PÀSCAL', 'poste': 'Autre', 'date_embauche': '2024-03-01'}, // 13 doublon de 2
    {'nom': 'ADJOVI', 'prenom': 'marie', 'poste': 'Autre', 'date_embauche': '2023-05-10'}, // 14 déjà en base
    {'nom': 'Zinsou', 'prenom': 'Luc', 'poste': 'Nouveau', 'date_embauche': '2020-01-01'}, // 15 archivé en base : valide
    {'nom': 'Statut vide', 'prenom': 'P', 'poste': 'X', 'date_embauche': '2024-06-01', 'statut': ''}, // 16 valide
    {'nom': 'Date numérique', 'prenom': 'P', 'poste': 'X', 'date_embauche': 45000}, // 17
    {'nom': 'Salaire négatif', 'prenom': 'P', 'poste': 'X', 'date_embauche': '2024-01-01', 'salaire': '-5'}, // 18
    {'nom': 'Poste long', 'prenom': 'P', 'poste': 'P' * 101, 'date_embauche': '2024-01-01'}, // 19
    {'nom': 'Salaire espaces', 'prenom': 'P', 'poste': 'X', 'date_embauche': '2024-01-02', 'salaire': '45 000', 'statut': 'suspendu'}, // 20 valide
  ];

  final planComptable = <Map<String, Object>>[
    {'numero': '60511', 'libelle': 'Achats de provende', 'classe': '6 - Charges'}, // 2 valide
    {'numero': '70131', 'libelle': 'Ventes de lapins', 'classe': '7'}, // 3 valide
    {'numero': '', 'libelle': 'Sans numéro', 'classe': '6'}, // 4
    {'numero': '1' * 21, 'libelle': 'Numéro long', 'classe': '6'}, // 5
    {'numero': '6053', 'libelle': '', 'classe': '6'}, // 6
    {'numero': '6054', 'libelle': 'Sans classe', 'classe': ''}, // 7
    {'numero': '6055', 'libelle': 'Classe 10', 'classe': '10'}, // 8
    {'numero': '6056', 'libelle': 'Classe texte', 'classe': 'abc'}, // 9
    {'numero': '6057', 'libelle': 'Classe zéro', 'classe': '0'}, // 10
    {'numero': '60 511', 'libelle': 'Doublon avec espace', 'classe': '6'}, // 11 doublon de 2
    {'numero': '6061', 'libelle': 'Déjà au plan', 'classe': '7'}, // 12 déjà en base
    {'numero': '6062', 'libelle': 'Archivé au plan', 'classe': '6'}, // 13 déjà en base (archivé)
    {'numero': 6052, 'libelle': 'Achats de vaccins', 'classe': '6 - CHARGES'}, // 14 valide
    {'numero': '6058', 'libelle': 'Classe avec zéro', 'classe': '07'}, // 15
    {'numero': '6059', 'libelle': 'L' * 256, 'classe': '6'}, // 16
    {'numero': '6060', 'libelle': 'Classe à espaces', 'classe': ' 8 '}, // 17 valide
  ];

  final rations = <Map<String, Object>>[
    {'espece': 'Aviculture (Volailles)', 'stade': 'Poulette test (3 à 5 mois)', 'grammes': '85'}, // 2 valide
    {'espece': 'cuniculture', 'stade': 'Lapine test', 'grammes': 250}, // 3 valide
    {'espece': 'PORCICULTURE (porcs)', 'stade': 'Truie test', 'grammes': '2 500'}, // 4 valide
    {'espece': '', 'stade': 'Sans espèce', 'grammes': '10'}, // 5
    {'espece': 'Apiculture', 'stade': 'Espèce inconnue', 'grammes': '10'}, // 6
    {'espece': 'cuniculture', 'stade': '', 'grammes': '10'}, // 7
    {'espece': 'cuniculture', 'stade': 'S' * 101, 'grammes': '10'}, // 8
    {'espece': 'cuniculture', 'stade': 'Sans grammes', 'grammes': ''}, // 9
    {'espece': 'cuniculture', 'stade': 'Grammes décimaux', 'grammes': '30,5'}, // 10
    {'espece': 'cuniculture', 'stade': 'Grammes zéro', 'grammes': '0'}, // 11
    {'espece': 'cuniculture', 'stade': 'Grammes négatifs', 'grammes': '-4'}, // 12
    {'espece': 'Aviculture (Volailles)', 'stade': 'POULETTE test  (3 à 5 mois)', 'grammes': '99'}, // 13 doublon de 2
    {'espece': 'aviculture', 'stade': 'pondeuse (adulte)', 'grammes': '999'}, // 14 déjà au barème
    {'espece': 'cuniculture', 'stade': 'Pondeuse (adulte)', 'grammes': '50'}, // 15 autre espèce : valide
    {'espece': 'aviculture', 'stade': 'Stade archivé', 'grammes': '20'}, // 16 archivé au barème : valide
    {'espece': 'aviculture', 'stade': 'Zéro initial', 'grammes': '007'}, // 17
  ];

  const textes = [
    'Société Évolution', '  Œufs de TABLE (plateau) ', 'Ça va', 'Zoë – œuvre', '+229 97 12 34 56', '00229 0197123456', '0197123456', '12 34', '97 12 34 56',
    '1500', '1 500', '1500,50', '-3', '8,5', '1e3', ' 12 ', '', '123456789012345', '1234567890123456',
  ];

  Map<String, dynamic>? php;

  setUpAll(() {
    if (saut != null) return;
    php = executerPhp(script, {
      'modules': {'stocks': stocks, 'clients': clients, 'fournisseurs': fournisseurs, 'employes': employes, 'plan_comptable': planComptable, 'rations': rations},
      'textes': textes,
    }, application: true) as Map<String, dynamic>;
  });

  tearDownAll(() {
    for (final m in (php?['modules'] as Map<String, dynamic>? ?? {}).values) {
      final f = File(m['fichier'] as String);
      if (f.existsSync()) f.deleteSync();
    }
  });

  Future<AppDatabase> baseSemee() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final g = php!['graines'] as Map<String, dynamic>;
    await db.into(db.productCategories).insert(ProductCategoriesCompanion.insert(id: g['cat'] as String, label: 'Aviculture'));
    await db.into(db.productCategories).insert(ProductCategoriesCompanion.insert(id: '11111111-1111-4111-8111-111111111111', label: 'Équipements'));
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: g['esp'] as String, code: 'aviculture', label: 'Aviculture'));
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: g['produit'] as String, sku: 'AVI-001', name: 'Poulet fermier', unit: 'U', pricingMode: 'fourchette',
      categoryId: Value(g['cat'] as String), speciesId: Value(g['esp'] as String),
    ));
    await db.into(db.customers).insert(CustomersCompanion.insert(id: '22222222-2222-4222-8222-222222222222', name: 'Boulangerie Le Bon Pain', phone: const Value('+229 0197123456')));
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: '33333333-3333-4333-8333-333333333333', name: 'Quincaillerie Centrale', category: const Value('Matériel'), phone: const Value('+22997112233')));
    // Les fiches que le serveur a déjà (graines du PHP) : employés, comptes, rations.
    for (final e in (g['employes'] as List).cast<Map<String, dynamic>>()) {
      await db.into(db.employees).insert(EmployeesCompanion.insert(
        id: e['id'] as String, deviceId: 'serveur', updatedAt: DateTime(2026, 11, 9), firstName: e['prenom'] as String, lastName: e['nom'] as String,
        position: Value(e['poste'] as String), hireDate: Value(e['embauche'] == null ? null : DateTime.parse(e['embauche'] as String)),
        isActive: Value(e['actif'] as bool),
      ));
    }
    for (final c in (g['comptes'] as List).cast<Map<String, dynamic>>()) {
      await db.into(db.chartOfAccounts).insert(ChartOfAccountsCompanion.insert(
        id: c['id'] as String, code: c['code'] as String, label: c['label'] as String, accountClass: Value(c['classe'] as int), isActive: Value(c['actif'] as bool),
      ));
    }
    for (final r in (g['rations'] as List).cast<Map<String, dynamic>>()) {
      await db.into(db.feedRationStandards).insert(FeedRationStandardsCompanion.insert(
        id: r['id'] as String, speciesCode: r['espece'] as String, stageLabel: r['stade'] as String, rationGPerDay: (r['grammes'] as int).toDouble(), isActive: Value(r['actif'] as bool),
      ));
    }
    return db;
  }

  for (final cle in ['stocks', 'clients', 'fournisseurs', 'employes', 'plan_comptable', 'rations']) {
    test('$cle : le poste lit le fichier du serveur et rend, ligne par ligne, le même état et le même motif', () async {
      final p = (php!['modules'] as Map<String, dynamic>)[cle] as Map<String, dynamic>;
      final m = ImportationRepository.module(cle)!;

      // Le modèle : mêmes colonnes, même version, même droit.
      expect([for (final c in m.colonnes) c.entete], (p['entetes'] as List).cast<String>());
      expect([for (final c in m.colonnes) c.cle], (p['cles'] as List).cast<String>());
      expect(m.version, p['version']);
      expect(m.libelle, p['libelle']);
      expect(m.permission, p['permission']);
      expect(m.colonnesSensibles, (p['sensibles'] as List).cast<String>());
      expect(m.nomDeFichier, 'Modele_${m.cle[0].toUpperCase()}${m.cle.substring(1)}_v${m.version}.xlsx');

      final db = await baseSemee();
      addTearDown(db.close);
      final depot = ImportationRepository(database: db);

      // Les listes déroulantes qui ne dépendent pas de la base : mêmes valeurs, même ordre.
      if (cle != 'stocks' && cle != 'clients') {
        final attendues = (p['listes'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as List).cast<String>()));
        expect(await depot.listes(m), attendues);
      }
      final octets = Uint8List.fromList(File(p['fichier'] as String).readAsBytesSync());
      final apercu = await depot.analyser(m, octets, 'import.xlsx');

      final attendu = (p['lignes'] as List).cast<Map<String, dynamic>>();
      expect(apercu.lignes.length, attendu.length);
      final ecarts = <String>[];
      for (var i = 0; i < attendu.length; i++) {
        final a = attendu[i];
        final b = apercu.lignes[i];
        if (b.ligne != a['ligne']) ecarts.add('ligne ${a['ligne']} : numéro ${b.ligne}');
        if (b.statut != a['statut']) ecarts.add('ligne ${a['ligne']} : état ${b.statut} / serveur ${a['statut']}');
        if ((b.motif ?? '') != (a['motif'] ?? '')) ecarts.add('ligne ${a['ligne']} : motif\n  poste   « ${b.motif} »\n  serveur « ${a['motif']} »');
        if (b.designation != (p['designations'] as List)[i]) ecarts.add('ligne ${a['ligne']} : désignation « ${b.designation} » / « ${(p['designations'] as List)[i]} »');
        if (b.doublon != a['doublon']) ecarts.add('ligne ${a['ligne']} : doublon ${b.doublon} / ${a['doublon']}');
        if (a['id'] != null) {
          final r = depot.validerLigne(m, b.brut!, await ContexteImportation.charger(db, cle));
          expect(depot.idLigne(m, r.valeurs), a['id'], reason: 'UUID v5 de la ligne ${a['ligne']}');
        }
      }
      expect(ecarts, isEmpty, reason: ecarts.join('\n'));
      expect(apercu.bloquant, p['bloquant']);
    }, skip: saut);
  }

  test('les normalisations de cellule et de clé sont celles du serveur', () {
    final n = (php!['normalisations'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < textes.length; i++) {
      final t = textes[i];
      expect(ImportationRepository.cle(t), n[i]['cle'], reason: 'cle(« $t »)');
      expect(ImportationRepository.normaliserTelephone(t), n[i]['tel'], reason: 'téléphone(« $t »)');
      expect(ImportationRepository.entier(t), n[i]['entier'], reason: 'entier(« $t »)');
      final d = ImportationRepository.decimal(t);
      expect(d, n[i]['decimal'] == null ? isNull : closeTo((n[i]['decimal'] as num).toDouble(), 1e-9), reason: 'décimal(« $t »)');
    }
  }, skip: saut);

  test('la constante d espace UUID et les catégories de fournisseur sont celles du serveur', () {
    final src = File('$dossierLaravel/app/Services/Import/ModuleImport.php').readAsStringSync();
    expect(src, contains("'${ImportationRepository.espaceUuid}'"));
    final cats = (php!['modules']['fournisseurs']['liste_categories'] as List).cast<String>();
    expect(ImportationRepository.categoriesFournisseur, cats);
  }, skip: saut);
}
