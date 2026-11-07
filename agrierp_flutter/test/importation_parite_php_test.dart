import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
use App\Models\{ProductCategory, LivestockSpecies, ModuleConfig, Product, Customer, Supplier, FiscalYear, User, Permission, Role};
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
foreach (['manage-stocks', 'manage-ventes', 'manage-achats'] as $p) { Permission::findOrCreate($p, 'web'); }
$role = Role::findOrCreate('importeur', 'web'); $role->syncPermissions(['manage-stocks', 'manage-ventes', 'manage-achats']);
$user = User::create(['name' => 'Importeur', 'username' => 'imp', 'email' => 'imp@x.test', 'password' => bcrypt('x'), 'is_active' => true]);
$user->assignRole($role);

$sortie = ['graines' => ['cat' => $cat->id, 'esp' => $esp->id, 'produit' => Product::first()->id, 'produit_sku' => 'AVI-001'], 'modules' => []];
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

  const textes = [
    'Société Évolution', '  Œufs de TABLE (plateau) ', 'Ça va', 'Zoë – œuvre', '+229 97 12 34 56', '00229 0197123456', '0197123456', '12 34', '97 12 34 56',
    '1500', '1 500', '1500,50', '-3', '8,5', '1e3', ' 12 ', '', '123456789012345', '1234567890123456',
  ];

  Map<String, dynamic>? php;

  setUpAll(() {
    if (saut != null) return;
    php = executerPhp(script, {
      'modules': {'stocks': stocks, 'clients': clients, 'fournisseurs': fournisseurs},
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
    return db;
  }

  for (final cle in ['stocks', 'clients', 'fournisseurs']) {
    test('$cle : le poste lit le fichier du serveur et rend, ligne par ligne, le même état et le même motif', () async {
      final p = (php!['modules'] as Map<String, dynamic>)[cle] as Map<String, dynamic>;
      final m = ImportationRepository.module(cle)!;

      // Le modèle : mêmes colonnes, même version, même droit.
      expect([for (final c in m.colonnes) c.entete], (p['entetes'] as List).cast<String>());
      expect([for (final c in m.colonnes) c.cle], (p['cles'] as List).cast<String>());
      expect(m.version, p['version']);
      expect(m.libelle, p['libelle']);
      expect(m.permission, p['permission']);
      expect(m.nomDeFichier, 'Modele_${m.cle[0].toUpperCase()}${m.cle.substring(1)}_v${m.version}.xlsx');

      final db = await baseSemee();
      addTearDown(db.close);
      final depot = ImportationRepository(database: db);
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
