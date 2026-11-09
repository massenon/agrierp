import 'dart:convert';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/systeme/plateforme_poste.dart';
import 'package:agrierp/features/parametres/administration_locale.dart';
import 'package:agrierp/features/parametres/sauvegarde_complete_json.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

/// PWA-2c — RESTAURATION de la sauvegarde complète JSON au navigateur : seulement dans un état sûr (aucune ligne
/// `pending` / `conflict`), après contrôle STRICT du fichier, tout ou rien dans UNE transaction ; chaque refus est testé.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  String id(int i) => 'c0c0c0c0-0000-4000-8000-${i.toString().padLeft(12, '0')}';

  Future<Map<String, List<Map<String, Object?>>>> contenu(AppDatabase db, {bool sansReglages = false}) async => {
    for (final t in await SauvegardeCompleteJson.tables(db))
      if (!(sansReglages && t == 'app_settings'))
        t: [for (final r in await db.customSelect('SELECT * FROM "$t" ORDER BY 1').get()) r.data],
  };

  Future<AppDatabase> source() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    for (var i = 0; i < 30; i++) {
      await db.into(db.productCategories).insert(ProductCategoriesCompanion.insert(id: id(i), label: 'Catégorie « $i » été'));
    }
    await db.into(db.chartOfAccounts).insert(
      ChartOfAccountsCompanion.insert(id: 'a0a0a0a0-0000-4000-8000-000000000001', code: '601000', label: 'Achats é à ü 日本'),
    );
    return db;
  }

  /// Une base DIFFÉRENTE, au repos (rien en attente), avec l'identité de CE poste.
  Future<AppDatabase> cible() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.productCategories).insert(ProductCategoriesCompanion.insert(id: id(900), label: 'Autre catégorie'));
    await db.into(db.appSettings).insert(AppSettingsCompanion.insert(key: 'poste.identifiant', value: 'poste-web-cible'));
    return db;
  }

  Future<List<int>> sauvegardeDeLaSource() async {
    final s = await source();
    addTearDown(s.close);
    return SauvegardeCompleteJson.exporter(s, maintenant: DateTime(2026, 11, 9, 10));
  }

  Future<void> poserEnAttente(AppDatabase db, SyncStatus statut) => db.into(db.chartOfAccounts).insert(
    ChartOfAccountsCompanion.insert(
      id: 'a0a0a0a0-0000-4000-8000-0000000000ff',
      code: 'LOCAL',
      label: 'Saisi au poste',
      syncStatus: Value(statut),
    ),
  );

  Matcher refus([String? contient]) =>
      throwsA(isA<RestaurationRefusee>().having((e) => e.message, 'motif', contient == null ? isNotEmpty : contains(contient)));

  test('aller-retour : export → base différente → restauration → contenu identique (identité du poste gardée)', () async {
    final octets = await sauvegardeDeLaSource();
    final s = await source();
    addTearDown(s.close);
    final db = await cible();
    addTearDown(db.close);
    expect((await contenu(db))['product_categories'], hasLength(1));

    final repris = await RestaurationSauvegarde.restaurer(db, octets);

    expect(repris, greaterThanOrEqualTo(31));
    expect(await contenu(db, sansReglages: true), await contenu(s, sansReglages: true));
    final reglages = {for (final r in await db.select(db.appSettings).get()) r.key: r.value};
    expect(reglages['poste.identifiant'], 'poste-web-cible', reason: 'l\'identité de CE poste n\'est jamais reprise d\'un autre');
  });

  test('REFUS : une saisie `pending` attend d\'être envoyée → motif français, base inchangée', () async {
    final octets = await sauvegardeDeLaSource();
    final db = await cible();
    addTearDown(db.close);
    await poserEnAttente(db, SyncStatus.pending);
    final avant = await contenu(db);
    await expectLater(RestaurationSauvegarde.restaurer(db, octets), refus('Des saisies ne sont pas encore envoyées'));
    expect(RestaurationSauvegarde.motifEtatNonSur, contains('Synchronisez d\'abord'));
    expect(await contenu(db), avant);
  });

  test('REFUS : une saisie `conflict` (refusée par le serveur) bloque aussi', () async {
    final octets = await sauvegardeDeLaSource();
    final db = await cible();
    addTearDown(db.close);
    await poserEnAttente(db, SyncStatus.conflict);
    final avant = await contenu(db);
    await expectLater(RestaurationSauvegarde.restaurer(db, octets), refus('Des saisies ne sont pas encore envoyées'));
    expect(await contenu(db), avant);
  });

  test('le contrôle seul (`ecrire: false`) refuse comme la restauration et n\'écrit rien', () async {
    final octets = await sauvegardeDeLaSource();
    final db = await cible();
    addTearDown(db.close);
    final avant = await contenu(db);
    expect(await RestaurationSauvegarde.restaurer(db, octets, ecrire: false), 0);
    expect(await contenu(db), avant, reason: 'contrôler n\'écrit pas');
    await poserEnAttente(db, SyncStatus.pending);
    await expectLater(RestaurationSauvegarde.restaurer(db, octets, ecrire: false), refus('Des saisies ne sont pas encore envoyées'));
  });

  group('contrôle strict du fichier : refus TOTAL, base inchangée', () {
    late AppDatabase db;
    late Map<String, List<Map<String, Object?>>> avant;
    setUp(() async {
      db = await cible();
      avant = await contenu(db);
    });
    tearDown(() async {
      expect(await contenu(db), avant, reason: 'un refus ne modifie RIEN');
      await db.close();
    });

    List<int> doc(Map<String, Object?> m) => utf8.encode(jsonEncode(m));
    Map<String, Object?> valide({Object? version, Map<String, Object?>? tables}) => {
      'format': 1,
      'schema_version': version ?? db.schemaVersion,
      'tables': tables ?? {'product_categories': []},
    };

    test('pas du JSON', () => expectLater(RestaurationSauvegarde.restaurer(db, utf8.encode('pas du json')), refus('illisible')));
    test('JSON étranger', () => expectLater(RestaurationSauvegarde.restaurer(db, doc({'a': 1})), refus('pas une sauvegarde complète')));
    test('format inconnu', () => expectLater(RestaurationSauvegarde.restaurer(db, doc({...valide(), 'format': 2})), refus('pas une sauvegarde complète')));
    test('schéma absent', () => expectLater(RestaurationSauvegarde.restaurer(db, doc({...valide(), 'schema_version': null})), refus('version du schéma')));
    test('schéma en texte', () => expectLater(RestaurationSauvegarde.restaurer(db, doc(valide(version: '86'))), refus('version du schéma')));

    test('schéma PLUS RÉCENT que l\'application', () async {
      await expectLater(
        RestaurationSauvegarde.restaurer(db, doc(valide(version: db.schemaVersion + 1))),
        refus('version plus récente de l\'application'),
      );
    });

    test('table inconnue : refus total, même si les autres tables sont valides', () async {
      final tables = {
        'product_categories': [
          {'id': id(1), 'label': 'x'},
        ],
        'table_fantome': [
          {'a': 1},
        ],
      };
      await expectLater(RestaurationSauvegarde.restaurer(db, doc(valide(tables: tables))), refus('table « table_fantome » est inconnue'));
    });

    test('colonne inconnue', () async {
      final tables = {
        'product_categories': [
          {'id': id(1), 'label': 'x', 'colonne_fantome': 3},
        ],
      };
      await expectLater(RestaurationSauvegarde.restaurer(db, doc(valide(tables: tables))), refus('colonne « colonne_fantome »'));
    });

    test('ligne qui n\'est pas un objet / table qui n\'est pas une liste', () async {
      await expectLater(RestaurationSauvegarde.restaurer(db, doc(valide(tables: {'product_categories': [42]}))), refus('n\'est pas un objet'));
      await expectLater(RestaurationSauvegarde.restaurer(db, doc(valide(tables: {'product_categories': 'x'}))), refus('n\'est pas une liste'));
    });

    test('TOUT OU RIEN : une ligne qui viole une contrainte en cours d\'écriture annule TOUT', () async {
      final tables = {
        'product_categories': [
          {'id': id(1), 'label': 'bonne ligne'},
          {'id': id(2)}, // `label` obligatoire : échoue après la première insertion
        ],
      };
      await expectLater(RestaurationSauvegarde.restaurer(db, doc(valide(tables: tables))), refus('Rien n\'a été modifié'));
    });
  });

  group('depuis l\'écran d\'administration (navigateur simulé)', () {
    var recharges = 0;
    late Future<void> Function() ancien;
    setUp(() {
      recharges = 0;
      PlateformePoste.forcerNavigateur(true);
      ancien = PlateformePoste.rechargeur;
      PlateformePoste.rechargeur = () async => recharges++;
    });
    tearDown(() {
      PlateformePoste.forcerNavigateur(null);
      PlateformePoste.rechargeur = ancien;
    });

    AdministrationLocale admin(AppDatabase db) =>
        AdministrationLocale(database: db, role: () => 'admin', idUtilisateur: () => 'u', coffre: CoffreMemoire());

    test('restaure, puis redémarre (rechargement) ; le contrôle seul ne recharge pas', () async {
      final octets = await sauvegardeDeLaSource();
      final db = await cible();
      addTearDown(db.close);
      await admin(db).controlerRestaurationNavigateur(octets);
      expect(recharges, 0);
      final message = await admin(db).restaurerDepuisFichierNavigateur(octets);
      expect(message, contains('le poste redémarre'));
      expect(recharges, 1);
      expect((await contenu(db))['product_categories'], hasLength(30));
    });

    test('un refus devient un RefusAdministration avec le motif ; pas de rechargement', () async {
      final octets = await sauvegardeDeLaSource();
      final db = await cible();
      addTearDown(db.close);
      await poserEnAttente(db, SyncStatus.pending);
      await expectLater(
        admin(db).restaurerDepuisFichierNavigateur(octets),
        throwsA(isA<RefusAdministration>().having((e) => e.message, 'motif', contains('Des saisies ne sont pas encore envoyées'))),
      );
      expect(recharges, 0);
    });

    test('natif : le geste n\'existe pas (la restauration native garde son mécanisme)', () async {
      PlateformePoste.forcerNavigateur(false);
      final db = await cible();
      addTearDown(db.close);
      await expectLater(admin(db).restaurerDepuisFichierNavigateur(const [1]), throwsA(isA<RefusAdministration>()));
    });
  });

  testWidgets('la modale de confirmation exige le mot RESTAURER', (tester) async {
    String? rendu;
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => rendu = await showDialog<String>(context: c, builder: (_) => const ModaleRestauration()),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('restauration-confirmation')), 'restaurer?');
    await tester.tap(find.byKey(const Key('restauration-confirmer')));
    await tester.pumpAndSettle();
    expect(find.text('Saisissez RESTAURER pour confirmer.'), findsOneWidget);
    expect(rendu, isNull);
    await tester.enterText(find.byKey(const Key('restauration-confirmation')), 'RESTAURER');
    await tester.tap(find.byKey(const Key('restauration-confirmer')));
    await tester.pumpAndSettle();
    expect(rendu, 'RESTAURER');
  });
}
