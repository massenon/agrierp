import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/parametres/administration_locale.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

/// Tickets AUT-4 (PA-1, PA-5, PA-6) — L'ADMINISTRATION DU POSTE SE FAIT SANS LE SERVEUR : sauvegarde (copie SQLite), export de
/// module, restauration au prochain lancement, import d'un module, déconnexion des autres comptes, état de ce poste.
void main() {
  late AppDatabase db;
  late Directory dossier;
  late Directory copie;
  late CoffreMemoire coffre;
  late AdministrationLocale admin;
  var maintenant = DateTime(2026, 10, 28, 10, 30);
  var role = 'admin';

  Future<void> client(String id, String nom, {SyncStatus statut = SyncStatus.synced}) => db.into(db.customers).insert(
    CustomersCompanion.insert(id: id.padRight(36, '0').substring(0, 36), name: nom, syncStatus: Value(statut)),
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dossier = await Directory.systemTemp.createTemp('sauvegardes_test');
    copie = await Directory.systemTemp.createTemp('copie_test');
    coffre = CoffreMemoire();
    maintenant = DateTime(2026, 10, 28, 10, 30);
    role = 'admin';
    admin = AdministrationLocale(
      database: db, role: () => role, idUtilisateur: () => 'u-courant', coffre: coffre,
      dossierSauvegardes: () async => Directory('${dossier.path}/sauvegardes'), dossierCopie: () async => copie, maintenant: () => maintenant,
    );
  });
  tearDown(() async {
    await db.close();
    await dossier.delete(recursive: true);
    await copie.delete(recursive: true);
  });

  test('⚠️ réservé à l\'administrateur : les droits sont ceux du rôle de la session', () {
    expect(admin.peut('manage-parametres'), isTrue);
    role = 'caissier';
    expect(admin.peut('manage-parametres'), isFalse);
  });

  group('PA-1 · sessions', () {
    test('⚠️ les autres comptes perdent code PIN et réglages ; le compte courant garde les siens', () async {
      coffre.contenu.addAll({
        'agrierp.verrou.u-courant': 'a', 'agrierp.verrou.u-2': 'b', 'agrierp.verrou.u-3': 'c',
        'agrierp.inactivite.u-2': '5', 'agrierp.inactivite.u-courant': '15', 'agrierp.rappels.masque.u-3': '2026-10-28',
        'agrierp.token': 'jeton', 'smtp.motdepasse': 'x',
      });

      final m = await admin.viderSessions();

      expect(m, '2 compte(s) déconnecté(s) de ce poste. Votre session est conservée.');
      expect(coffre.contenu.keys.toSet(), {'agrierp.verrou.u-courant', 'agrierp.inactivite.u-courant', 'agrierp.token', 'smtp.motdepasse'});
    });
  });

  group('PA-6 · sauvegardes', () {
    test('⚠️ la sauvegarde complète est une VRAIE base : on y relit ce qui était saisi, sans réseau', () async {
      await client('c1', 'AMOUSSOU Régis');

      final message = await admin.generer();

      expect(message, startsWith('Sauvegarde complète générée : backup_2026-10-28_1030_complete.sqlite'));
      final f = (await admin.sauvegardes()).single;
      expect((f.complete, f.portee), (true, 'Sauvegarde complète'));
      expect(f.taille, greaterThan(0));
      await db.customStatement("ATTACH DATABASE '${dossier.path}/sauvegardes/${f.fichier}' AS s");
      expect((await db.customSelect('SELECT name FROM s.customers').getSingle()).read<String>('name'), 'AMOUSSOU Régis');
    });

    test('deux sauvegardes dans la même minute ne s\'écrasent pas', () async {
      await admin.generer();
      await admin.generer();

      expect((await admin.sauvegardes()).length, 2);
    });

    test('un export de module est un JSON de ses seules tables, et ne se restaure pas', () async {
      await client('c1', 'AMOUSSOU Régis');

      final message = await admin.generer(module: 'ventes');

      expect(message, contains('Ventes & Clients'));
      final f = (await admin.sauvegardes()).single;
      expect((f.complete, f.portee), (false, 'Ventes & Clients (export, sans schéma)'));
      final json = jsonDecode(await File('${dossier.path}/sauvegardes/${f.fichier}').readAsString()) as Map<String, dynamic>;
      expect((json['tables'] as Map).keys, containsAll(['customers', 'sales']));
      expect(((json['tables'] as Map)['customers'] as List).single['name'], 'AMOUSSOU Régis');
      expect(json['tables'] as Map, isNot(contains('products')));
      await expectLater(admin.generer(module: 'inconnu'), throwsA(isA<RefusAdministration>()));
      await expectLater(admin.programmerRestauration(f.fichier), throwsA(isA<RefusAdministration>()));
    });

    test('⚠️ rétention de 30 jours comme le web : une sauvegarde plus ancienne disparaît à la lecture', () async {
      await admin.generer();
      final f = File('${dossier.path}/sauvegardes/backup_2026-10-28_1030_complete.sqlite');
      await f.setLastModified(DateTime(2026, 9, 1));

      expect(await admin.sauvegardes(), isEmpty);
      expect(await f.exists(), isFalse);
    });

    test('« Copier » pose le fichier dans le dossier de copie ; un fichier inconnu est refusé', () async {
      await admin.generer();

      final chemin = await admin.copier('backup_2026-10-28_1030_complete.sqlite');

      expect(await File(chemin).exists(), isTrue);
      await expectLater(admin.copier('absent.sqlite'), throwsA(isA<RefusAdministration>()));
    });

    test('⚠️ l\'import d\'un module remplace SES tables par la sauvegarde, repart pending, et laisse les autres modules', () async {
      await client('c1', 'AMOUSSOU Régis');
      await db.into(db.productCategories).insert(ProductCategoriesCompanion.insert(id: 'cat'.padRight(36, '0'), label: 'Aliments'));
      await admin.generer();
      await db.customStatement('DELETE FROM customers');
      await client('c2', 'GBAGUIDI Solange');

      final m = await admin.importerModule(fichier: 'backup_2026-10-28_1030_complete.sqlite', module: 'ventes');

      expect(m, startsWith('Module « Ventes & Clients » remplacé'));
      final noms = (await db.customSelect('SELECT name, sync_status FROM customers').get()).map((r) => (r.read<String>('name'), r.read<String>('sync_status'))).toList();
      expect(noms, [('AMOUSSOU Régis', 'pending')]);
      expect((await db.select(db.productCategories).get()).length, 1);
      // La base est détachée : un second import fonctionne.
      await admin.importerModule(fichier: 'backup_2026-10-28_1030_complete.sqlite', module: 'ventes');
    });

    test('l\'import refuse un export JSON et un module inconnu', () async {
      await admin.generer(module: 'rh');
      final json = (await admin.sauvegardes()).single.fichier;

      await expectLater(admin.importerModule(fichier: json, module: 'rh'), throwsA(isA<RefusAdministration>()));
      await expectLater(admin.importerModule(fichier: json, module: 'x'), throwsA(isA<RefusAdministration>()));
    });

    test('⚠️⚠️ la restauration est programmée, puis installée AVANT l\'ouverture de la base, l\'ancienne étant gardée', () async {
      await admin.generer();
      final donnees = Directory('${dossier.path}/sauvegardes').parent;
      await File('${donnees.path}/agrierp.sqlite').writeAsString('BASE ACTUELLE');
      await File('${donnees.path}/agrierp.sqlite-wal').writeAsString('journal');

      final m = await admin.programmerRestauration('backup_2026-10-28_1030_complete.sqlite');

      expect(m, contains('fermez puis rouvrez AgriERP'));
      expect(await File('${donnees.path}/agrierp.restauration').exists(), isTrue);
      expect(await File('${donnees.path}/agrierp.sqlite').readAsString(), 'BASE ACTUELLE', reason: 'rien ne change à chaud');

      await AdministrationLocale.appliquerRestaurationEnAttente(dossierDonnees: donnees);

      expect(await File('${donnees.path}/agrierp.avant-restauration.sqlite').readAsString(), 'BASE ACTUELLE');
      expect(await File('${donnees.path}/agrierp.sqlite-wal').exists(), isFalse);
      expect(await File('${donnees.path}/agrierp.restauration').exists(), isFalse);
      expect((await File('${donnees.path}/agrierp.sqlite').readAsBytes()).take(15), utf8.encode('SQLite format 3'));
      // Sans restauration en attente, rien ne bouge.
      await AdministrationLocale.appliquerRestaurationEnAttente(dossierDonnees: donnees);
    });
  });

  group('PA-5 · ce poste', () {
    test('compte les saisies en attente et les refus du serveur, sans réseau', () async {
      await client('c1', 'A', statut: SyncStatus.pending);
      await client('c2', 'B', statut: SyncStatus.conflict);
      await client('c3', 'C');

      final e = await admin.etatDuPoste();

      expect((e.enAttente, e.conflits, e.derniere), (1, 1, null));
    });
  });

  group('écran', () {
    testWidgets('⚠️ générer une sauvegarde, puis la restaurer avec confirmation', (tester) async {
      tester.view.physicalSize = const Size(1700, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Les fichiers et la base sont réels : leurs futures ne se terminent que hors du temps simulé.
      Future<void> attendre() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump();
        }
      }

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: OngletSauvegardes(admin: admin)))));
      await attendre();
      expect(find.byKey(const Key('sauvegarde-vide')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sauvegarde-generer')));
      await attendre();
      expect(find.byKey(const Key('sauvegarde-message')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sauvegarde-restaurer-backup_2026-10-28_1030_complete.sqlite')));
      await tester.pump();
      expect(find.byKey(const Key('sauvegarde-confirmation-restauration')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sauvegarde-confirmer-restauration')));
      await attendre();
      expect(find.textContaining('Restauration programmée'), findsOneWidget);
    });

    test('⚠️ aucune trace du serveur dans l\'administration du poste', () {
      final source = File('lib/features/parametres/administration_locale.dart').readAsStringSync();
      expect(source, isNot(contains('Dio')));
      expect(source, isNot(contains('/api/')));
      expect(source, isNot(contains('estEnLigne')));
    });
  });
}
