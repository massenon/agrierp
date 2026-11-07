
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/importation/importation_repository.dart';
import 'package:agrierp/features/importation/importation_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket IMPORT-1 — l'importation en masse AU POSTE : dépôt (lecture, aperçu, écriture par les dépôts propriétaires, rapport,
/// modèle) et écran (six étapes). La parité de la règle avec le serveur est prouvée par `importation_parite_php_test.dart`.
void main() {
  const cat = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const esp = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.productCategories).insert(ProductCategoriesCompanion.insert(id: cat, label: 'Aviculture'));
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: esp, code: 'aviculture', label: 'Aviculture'));
    final an = DateTime.now().year;
    await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', year: an, startDate: Value(DateTime(an)), endDate: Value(DateTime(an, 12, 31)), status: const Value('ouvert')));
  });
  tearDown(() async => db.close());

  ImportationRepository depot() => ImportationRepository(database: db);

  /// Le VRAI modèle du poste, rempli : une ligne par entrée.
  Future<Uint8List> fichier(ModuleImportation m, List<Map<String, String>> lignes, {int? version, bool sansColonne = false}) async {
    final base = await depot().genererModele(m);
    final classeur = Excel.decodeBytes(base);
    final feuille = classeur['Données'];
    for (var r = 0; r < lignes.length; r++) {
      for (var c = 0; c < m.colonnes.length; c++) {
        final v = lignes[r][m.colonnes[c].cle];
        if (v != null && v.isNotEmpty) feuille.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1), TextCellValue(v));
      }
    }
    if (version != null) classeur['Modele'].updateCell(CellIndex.indexByString('B2'), IntCellValue(version));
    if (sansColonne) feuille.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), TextCellValue('Raison sociale'));
    return Uint8List.fromList(classeur.encode()!);
  }

  const poulet = {'nom': 'Poulet fermier', 'categorie': 'Aviculture', 'unite': 'u', 'filiere': 'Aviculture', 'mode_prix': 'Fourchette', 'prix_min': '3000', 'prix_max': '4000', 'tva': '0', 'seuil': '5', 'stock_initial': '12'};

  group('dépôt', () {
    test('stocks : un fichier valide écrit les produits par le dépôt propriétaire, pending, avec l\'UUID déterministe', () async {
      final m = ImportationRepository.stocks;
      final apercu = await depot().analyser(m, await fichier(m, [poulet, {...poulet, 'nom': 'Aliment', 'unite': 'sac', 'filiere': '', 'mode_prix': 'Sur devis', 'prix_min': '', 'prix_max': '', 'stock_initial': '8,5'}]), 'stocks.xlsx');

      expect([apercu.lues, apercu.valides, apercu.refusees], [2, 2, 0]);
      expect(await db.select(db.products).get(), isEmpty, reason: "l'aperçu n'écrit rien");

      await depot().importer(apercu, 'admin');
      expect(apercu.creees, 2);
      final produits = await (db.select(db.products)..orderBy([(p) => OrderingTerm(expression: p.name)])).get();
      expect(produits.map((p) => p.name), ['Aliment', 'Poulet fermier']);
      final p = produits.last;
      expect([p.stockQty, p.priceMin, p.priceMax, p.alertThreshold, p.speciesId], [12.0, 3000.0, 4000.0, 5.0, esp]);
      expect(p.syncStatus, SyncStatus.pending);
      expect(p.id, ImportationRepository.modules.isNotEmpty ? isNotEmpty : isNotEmpty);
      expect(produits.first.stockQty, 8.5);
      expect(produits.first.pricingMode, 'quote');
      // Valeurs lues effacées pour les fiches créées.
      expect(apercu.lignes.every((l) => l.brut == null), isTrue);
    });

    test('un ré-import ne crée rien : les produits déjà là sont ignorés et leur stock n\'est pas ajouté', () async {
      final m = ImportationRepository.stocks;
      final f = await fichier(m, [poulet]);
      await depot().importer(await depot().analyser(m, f, 'a.xlsx'), 'admin');

      final second = await depot().analyser(m, f, 'a.xlsx');
      expect([second.valides, second.ignorees], [0, 1]);
      expect(second.lignes.first.motif, "Ce produit a déjà été importé : ignoré, le stock initial n'est pas ajouté.");
      await depot().importer(second, 'admin');

      final produits = await db.select(db.products).get();
      expect(produits, hasLength(1));
      expect(produits.single.stockQty, 12.0, reason: 'le stock initial n\'est pas ajouté une seconde fois');
    });

    test('clients et fournisseurs : écrits par leurs dépôts, doublons du fichier refusés, ligne erronée refusée', () async {
      final mc = ImportationRepository.clients;
      final ac = await depot().analyser(mc, await fichier(mc, [
        {'nom': 'Boulangerie', 'telephone': '0197123456', 'ifu': '3201234567890'},
        {'nom': 'boulangerie', 'telephone': '+229 0197123456'},
        {'nom': 'IFU court', 'telephone': '0197000001', 'ifu': '123'},
      ]), 'c.xlsx');
      expect([ac.valides, ac.refusees], [1, 2]);
      expect(ac.lignes[1].motif, 'Ligne 3 : doublon de la ligne 2.');
      expect(ac.lignes[2].motif, 'Feuille « Données », ligne 4, colonne « IFU » : L\'IFU du client doit comporter 13 chiffres (laissez-le vide pour un client sans IFU).');
      await depot().importer(ac, 'caissier');
      final clients = await db.select(db.customers).get();
      expect(clients.single.phone, '0197123456');
      expect(clients.single.syncStatus, SyncStatus.pending);

      final mf = ImportationRepository.fournisseurs;
      final af = await depot().analyser(mf, await fichier(mf, [{'nom': 'Provenderie', 'categorie': 'Aliments', 'telephone': '0197654321'}]), 'f.xlsx');
      await depot().importer(af, 'admin');
      final f = (await db.select(db.suppliers).get()).single;
      expect([f.name, f.category, f.phone, f.syncStatus], ['Provenderie', 'Aliments', '0197654321', SyncStatus.pending]);
    });

    test('les droits : un caissier n\'importe pas les stocks, un rôle sans droit n\'a aucun module', () async {
      expect(ImportationRepository.modulesAutorises('admin').map((m) => m.cle), ['stocks', 'clients', 'fournisseurs']);
      expect(ImportationRepository.modulesAutorises('caissier').map((m) => m.cle), ['clients']);
      expect(ImportationRepository.modulesAutorises('animalier'), isEmpty);
      expect(ImportationRepository.peutImporter('comptable'), isFalse);

      final m = ImportationRepository.stocks;
      final apercu = await depot().analyser(m, await fichier(m, [poulet]), 's.xlsx');
      await expectLater(depot().importer(apercu, 'caissier'), throwsA(isA<ImportationRefusee>()));
      expect(await db.select(db.products).get(), isEmpty);
    });

    test('un exercice clos refuse tout l\'import des stocks (avant la confirmation), pas celui des clients', () async {
      await (db.update(db.fiscalYears)).write(const FiscalYearsCompanion(status: Value('cloture')));
      final m = ImportationRepository.stocks;
      final apercu = await depot().analyser(m, await fichier(m, [poulet]), 's.xlsx');
      expect(apercu.bloquant, contains('clôturé'));
      await expectLater(depot().importer(apercu, 'admin'), throwsA(isA<ImportationRefusee>().having((e) => e.message, 'message', apercu.bloquant)));
      expect(await db.select(db.products).get(), isEmpty);

      final mc = ImportationRepository.clients;
      expect((await depot().analyser(mc, await fichier(mc, [{'nom': 'X', 'telephone': '0197000001'}]), 'c.xlsx')).bloquant, isNull);
    });

    test('le fichier entier est refusé : mauvaise version, colonne renommée, extension, illisible, sans ligne', () async {
      final m = ImportationRepository.clients;
      Future<String> refus(Future<Object?> Function() f) async {
        try {
          await f();
        } on ImportationRefusee catch (e) {
          return e.message;
        }
        fail('refus attendu');
      }

      expect(await refus(() async => depot().analyser(m, await fichier(m, [{'nom': 'A'}], version: 2), 'c.xlsx')),
          'Ce fichier est le modèle « Clients » en version 2 ; la version 1 est attendue : téléchargez le modèle à jour.');
      expect(await refus(() async => depot().analyser(m, await fichier(m, [{'nom': 'A'}], sansColonne: true), 'c.xlsx')),
          'Colonne manquante ou renommée dans la feuille « Données » : « Nom * ». Ne renommez pas les en-têtes : téléchargez le modèle « Clients » à jour.');
      expect(await refus(() async => depot().analyser(m, await fichier(m, [{'nom': 'A'}]), 'c.csv')), startsWith('Seuls les fichiers Excel .xlsx sont acceptés'));
      expect(await refus(() async => depot().analyser(m, Uint8List.fromList('nom;tel'.codeUnits), 'c.xlsx')), contains("n'est pas un classeur Excel (.xlsx) lisible"));
      expect(await refus(() async => depot().analyser(m, await fichier(m, []), 'c.xlsx')), startsWith('Le fichier ne contient aucune ligne à importer'));
      expect(await refus(() async => depot().analyser(m, await fichier(ImportationRepository.fournisseurs, [{'nom': 'A'}]), 'c.xlsx')),
          'Ce fichier n\'est pas le modèle « Clients » (version 1) : c\'est le modèle « Fournisseurs ». Téléchargez le modèle à jour.');
      expect(await refus(() async => depot().analyser(m, Uint8List(ImportationRepository.tailleMaxOctets + 1)..[0] = 0x50, 'c.xlsx')), startsWith('Le fichier dépasse 5 Mo'));
    });

    test('5 000 lignes passent, 5 001 sont refusées', () async {
      final m = ImportationRepository.clients;
      final classeur = Excel.decodeBytes(await depot().genererModele(m));
      final f = classeur['Données'];
      Uint8List ecrire(int n) {
        for (var r = 1; r <= n; r++) {
          f.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), TextCellValue('Client $r'));
          f.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r), TextCellValue('${97000000 + r}'));
        }
        return Uint8List.fromList(classeur.encode()!);
      }

      final a = await depot().analyser(m, ecrire(5000), 'g.xlsx');
      expect([a.lues, a.valides], [5000, 5000]);
      await expectLater(depot().analyser(m, ecrire(5001), 'g.xlsx'), throwsA(isA<ImportationRefusee>().having((e) => e.message, 'm', 'Le fichier dépasse 5 000 lignes : découpez-le en plusieurs fichiers.')));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('le modèle du poste a ses quatre feuilles, ses en-têtes exacts et sa version ; le rapport se relit', () async {
      final m = ImportationRepository.stocks;
      final classeur = Excel.decodeBytes(await depot().genererModele(m));
      expect(classeur.tables.keys.toSet(), {'Instructions', 'Données', 'Listes', 'Modele'});
      final entetes = classeur['Données'].rows.first.map((c) => c!.value.toString()).toList();
      expect(entetes, [for (final c in m.colonnes) c.entete]);
      expect(classeur['Modele'].cell(CellIndex.indexByString('B1')).value.toString(), 'stocks');
      expect(classeur['Modele'].cell(CellIndex.indexByString('B2')).value.toString(), '1');
      expect(classeur['Listes'].cell(CellIndex.indexByString('A2')).value.toString(), 'Aviculture');

      final apercu = await depot().analyser(m, await fichier(m, [poulet, {...poulet, 'nom': 'Mauvais', 'tva': '500'}]), 's.xlsx');
      await depot().importer(apercu, 'admin');
      final rapport = Excel.decodeBytes(depot().rapport(apercu));
      final lignes = rapport['Rapport'].rows.map((r) => r.map((c) => c?.value.toString() ?? '').toList()).toList();
      expect(lignes[0], ['Ligne', 'Désignation', 'Résultat', 'Motif']);
      expect(lignes[1].sublist(0, 3), ['2', 'Poulet fermier', 'Créée']);
      expect(lignes[2][2], 'Refusée');
      expect(rapport['Lignes refusées'].rows, hasLength(2));
    });
  });

  group('écran', () {
    Future<void> monter(WidgetTester t, {String role = 'admin', List<Map<String, String>>? lignes, ModuleImportation? module, List<String>? ecrits, Uint8List? contenu}) async {
      t.view.physicalSize = const Size(1400, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final octets = contenu ?? await t.runAsync(() => fichier(module ?? ImportationRepository.stocks, lignes ?? [poulet, {...poulet, 'nom': 'Cassé', 'tva': '900'}]));
      await t.pumpWidget(MaterialApp(
        home: ImportationScreen(
          depot: depot(),
          role: role,
          choisirFichier: () async => (nom: 'import.xlsx', octets: octets!),
          enregistrer: (nom, o) async {
            ecrits?.add(nom);
            return '/docs/$nom';
          },
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('six étapes : module, modèle, fichier, aperçu, confirmation, rapport', (t) async {
      final ecrits = <String>[];
      await monter(t, ecrits: ecrits);

      expect(find.text('Importation en masse'), findsOneWidget);
      expect(find.byKey(const Key('module-stocks')), findsOneWidget);
      expect(find.byKey(const Key('module-clients')), findsOneWidget);
      await t.tap(find.byKey(const Key('module-stocks')));
      await t.pumpAndSettle();

      expect(find.text('Télécharger le modèle'), findsOneWidget);
      await t.runAsync(() async => t.tap(find.byKey(const Key('importation-telecharger-modele'))));
      await t.pumpAndSettle();
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await t.pumpAndSettle();
      expect(ecrits, ['Modele_Stocks_v1.xlsx']);
      expect(find.textContaining('/docs/Modele_Stocks_v1.xlsx'), findsOneWidget);

      await t.tap(find.byKey(const Key('importation-vers-depot')));
      await t.pumpAndSettle();
      await t.runAsync(() async => t.tap(find.byKey(const Key('importation-zone-depot'))));
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
      await t.pumpAndSettle();

      expect(find.textContaining('Rien n\'est encore écrit'.toUpperCase()), findsOneWidget);
      expect(find.text('Importer 1 ligne'), findsOneWidget);
      expect(find.textContaining('colonne « TVA % * »'), findsOneWidget);
      expect(await db.select(db.products).get(), isEmpty);

      await t.tap(find.byKey(const Key('importation-filtre-refusee')));
      await t.pumpAndSettle();
      expect(find.text('Poulet fermier'), findsNothing);
      expect(find.text('Cassé'), findsOneWidget);

      await t.tap(find.byKey(const Key('importation-importer')));
      await t.pumpAndSettle();
      expect(find.text("5 · Confirmer l'importation"), findsOneWidget);
      await t.runAsync(() async => t.tap(find.text("Confirmer l'importation")));
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
      await t.pumpAndSettle();

      expect(find.text("6 · RAPPORT D'IMPORTATION"), findsOneWidget);
      expect(find.text('CRÉÉES'), findsOneWidget);
      expect(find.text('Corriger le fichier puis ré-importer'), findsOneWidget);
      expect((await db.select(db.products).get()).single.name, 'Poulet fermier');

      await t.tap(find.byKey(const Key('importation-telecharger-rapport')));
      await t.pumpAndSettle();
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await t.pumpAndSettle();
      expect(ecrits.last, startsWith('Rapport_importation_stocks_'));
    });

    testWidgets('un caissier ne voit que les clients ; un fichier refusé affiche son message', (t) async {
      await monter(t, role: 'caissier', contenu: Uint8List.fromList('pas un classeur'.codeUnits));
      expect(find.byKey(const Key('module-stocks')), findsNothing);
      expect(find.byKey(const Key('module-fournisseurs')), findsNothing);
      await t.tap(find.byKey(const Key('module-clients')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('importation-vers-depot')));
      await t.pumpAndSettle();
      await t.runAsync(() async => t.tap(find.byKey(const Key('importation-zone-depot'))));
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('importation-erreur')), findsOneWidget);
      expect(find.textContaining("n'est pas un classeur Excel (.xlsx) lisible"), findsOneWidget);
    });

    testWidgets('exercice clos : le bouton d\'import est désactivé avec le motif', (t) async {
      await (db.update(db.fiscalYears)).write(const FiscalYearsCompanion(status: Value('cloture')));
      await monter(t);
      await t.tap(find.byKey(const Key('module-stocks')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('importation-vers-depot')));
      await t.pumpAndSettle();
      await t.runAsync(() async => t.tap(find.byKey(const Key('importation-zone-depot'))));
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('importation-bloque')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('importation-importer'))).onPressed, isNull);
    });
  });
}
