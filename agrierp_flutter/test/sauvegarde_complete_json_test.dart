import 'dart:convert';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/systeme/plateforme_poste.dart';
import 'package:agrierp/features/parametres/administration_locale.dart';
import 'package:agrierp/features/parametres/sauvegarde_complete_json.dart';
import 'package:drift/native.dart';
import 'coffre_memoire.dart';
import 'package:flutter_test/flutter_test.dart';

/// PWA-2b — SAUVEGARDE COMPLÈTE au navigateur : toutes les tables en JSON, téléchargées ; ALLER-RETOUR prouvé (export puis
/// import dans une base VIDE : même contenu, table par table, blobs compris). La restauration depuis l'écran reste refusée.
void main() {
  Future<Map<String, List<Map<String, Object?>>>> contenu(AppDatabase db) async => {
    for (final t in await SauvegardeCompleteJson.tables(db))
      t: [for (final r in await db.customSelect('SELECT * FROM "$t" ORDER BY 1').get()) r.data],
  };

  Future<AppDatabase> peuplee() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    for (var i = 0; i < 40; i++) {
      await db.into(db.productCategories).insert(
        ProductCategoriesCompanion.insert(id: 'c0c0c0c0-0000-4000-8000-${i.toString().padLeft(12, '0')}', label: 'Catégorie « $i » \'été\''),
      );
    }
    await db.into(db.chartOfAccounts).insert(ChartOfAccountsCompanion.insert(id: 'a0a0a0a0-0000-4000-8000-000000000001', code: '601000', label: 'Achats é à ü 日本'));
    return db;
  }

  test('aller-retour : export puis import dans une base vide donnent le même contenu', () async {
    final source = await peuplee();
    addTearDown(source.close);
    final octets = await SauvegardeCompleteJson.exporter(source, maintenant: DateTime(2026, 11, 9, 10));

    final cible = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(cible.close);
    expect((await contenu(cible))['product_categories'], isEmpty);
    final repris = await SauvegardeCompleteJson.importer(cible, octets);

    expect(repris, greaterThanOrEqualTo(41));
    expect(await contenu(cible), await contenu(source));
  });

  test('les octets (BLOB) font l\'aller-retour', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    await source.customStatement('CREATE TABLE zz_blob (id INTEGER PRIMARY KEY, donnees BLOB, note TEXT, n REAL)');
    await source.customStatement('INSERT INTO zz_blob VALUES (1, ?, NULL, 1.5)', [[0, 1, 2, 255]]);
    final octets = await SauvegardeCompleteJson.exporter(source, maintenant: DateTime(2026, 11, 9));
    final cible = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(cible.close);
    await cible.customStatement('CREATE TABLE zz_blob (id INTEGER PRIMARY KEY, donnees BLOB, note TEXT, n REAL)');
    await SauvegardeCompleteJson.importer(cible, octets);
    final r = (await cible.customSelect('SELECT * FROM zz_blob').get()).single.data;
    expect(r['donnees'], [0, 1, 2, 255]);
    expect(r['note'], isNull);
    expect(r['n'], 1.5);
  });

  test('un fichier étranger ou d\'un autre schéma est refusé, sans rien modifier', () async {
    final db = await peuplee();
    addTearDown(db.close);
    await expectLater(SauvegardeCompleteJson.importer(db, utf8.encode('pas du json')), throwsFormatException);
    await expectLater(SauvegardeCompleteJson.importer(db, utf8.encode('{"a":1}')), throwsFormatException);
    final autre = utf8.encode(jsonEncode({'format': 1, 'schema_version': 1, 'tables': {'product_categories': []}}));
    await expectLater(SauvegardeCompleteJson.importer(db, autre), throwsFormatException);
    expect((await contenu(db))['product_categories'], hasLength(40));
  });

  group('au navigateur (repli simulé)', () {
    final livraisons = <({String nom, List<int> octets})>[];
    late Future<String> Function(String, List<int>) ancien;
    setUp(() {
      livraisons.clear();
      PlateformePoste.forcerNavigateur(true);
      ancien = PlateformePoste.livreurNavigateur;
      PlateformePoste.livreurNavigateur = (nom, octets) async {
        livraisons.add((nom: nom, octets: octets));
        return nom;
      };
    });
    tearDown(() {
      PlateformePoste.forcerNavigateur(null);
      PlateformePoste.livreurNavigateur = ancien;
    });

    test('« Sauvegarde complète » TÉLÉCHARGE un fichier _complete.json qui se réimporte', () async {
      final db = await peuplee();
      addTearDown(db.close);
      final admin = AdministrationLocale(database: db, role: () => 'admin', idUtilisateur: () => 'u', coffre: CoffreMemoire());
      final message = await admin.generer();
      expect(message, startsWith('Sauvegarde complète téléchargée : '));
      expect(livraisons.single.nom, endsWith('_complete.json'));
      final vide = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(vide.close);
      await SauvegardeCompleteJson.importer(vide, livraisons.single.octets);
      expect(await contenu(vide), await contenu(db));
    });

    test('la restauration reste refusée avec un motif français', () async {
      final db = await peuplee();
      addTearDown(db.close);
      final admin = AdministrationLocale(database: db, role: () => 'admin', idUtilisateur: () => 'u', coffre: CoffreMemoire());
      await expectLater(
        admin.programmerRestauration('x_complete.sqlite'),
        throwsA(isA<RefusAdministration>().having((e) => e.message, 'motif', contains('restauration'))),
      );
    });
  });
}
