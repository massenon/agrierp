import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_escargots_screen.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_porcs_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket 15.57 — LES SECTIONS DU WEB EXISTENT AU POSTE (décision client du 17/10/2026 : « les sections
/// doivent exister des deux côtés »).
///
///  - Porcs : « Effectif de départ par catégorie » (pré-rempli depuis le stade, corrigeable, contrôlé
///    comme au web par `verifierDepart`, verrouillé ensuite) et saisie Verrats / Truies Gestantes /
///    Porcelets / Engraissement ;
///  - Escargots : saisie Naissains / Engraissement / Bordés ;
///  - tableaux mensuels : ces effectifs, synchronisés, s'affichent au lieu de « — ».
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'aaaaaaaa-1557-4557-8557-aaaaaaaaaaaa';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
  });

  tearDown(() async => db.close());

  Future<void> bande(String espece, String stade) => db.into(db.livestockLots).insert(
    LivestockLotsCompanion.insert(
      id: bandeId,
      code: 'BANDE-1557',
      speciesId: 'eeeeeeee-1557-4557-8557-eeeeeeeeeeee',
      speciesCode: Value(espece),
      stage: Value(stade),
      createdDate: Value(DateTime.now().subtract(const Duration(days: 3))),
      initialQuantity: const Value(100),
      currentQuantity: const Value(100),
    ),
  );

  Future<void> afficher(WidgetTester tester, Widget ecran) async {
    tester.view.physicalSize = const Size(1600, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ecran));
    await tester.pumpAndSettle();
  }

  Future<void> saisir(WidgetTester tester, String prefixeCle, String valeur) async {
    final champ = find.byWidgetPredicate(
      (w) => w is TextFormField && w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('champ-$prefixeCle-'),
    );
    await tester.ensureVisible(champ);
    await tester.enterText(champ, valeur);
    await tester.pumpAndSettle();
  }

  Future<void> enregistrer(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Enregistrer ce Jour'));
    await tester.tap(find.text('Enregistrer ce Jour'));
    await tester.pumpAndSettle();
  }

  group('Porcs — effectif de départ par catégorie', () {
    testWidgets('pré-rempli depuis le stade (engraissement : 100 Porcs Marchands), puis verrouillé', (
      tester,
    ) async {
      await bande('porciculture', 'engraissement');
      await afficher(tester, FichePorcsScreen(depot: depot, soins: soins));

      expect(find.byKey(const Key('porcs-depart-modifiable')), findsOneWidget);
      expect(find.byKey(const Key('porcs-depart-motif')), findsNothing);

      await enregistrer(tester);

      final f = await db.select(db.livestockDailyEntries).getSingle();
      expect([f.catDepartRepro, f.catDepartSevre, f.catDepartJeune], [0, 0, 100]);
      await tester.pumpWidget(const SizedBox());
      await afficher(tester, FichePorcsScreen(depot: depot, soins: soins));
      expect(find.byKey(const Key('porcs-depart-verrouille')), findsOneWidget);
    });

    testWidgets('bande mixte : départ corrigé 10 / 0 / 90, écrit tel quel', (tester) async {
      await bande('porciculture', 'engraissement');
      await afficher(tester, FichePorcsScreen(depot: depot, soins: soins));

      await saisir(tester, 'depart-repro', '10');
      await saisir(tester, 'depart-jeune', '90');
      await enregistrer(tester);

      final f = await db.select(db.livestockDailyEntries).getSingle();
      expect([f.catDepartRepro, f.catDepartSevre, f.catDepartJeune], [10, 0, 90]);
    });

    testWidgets('🔴 somme fausse : motif du web affiché, RIEN n est écrit', (tester) async {
      await bande('porciculture', 'engraissement');
      await afficher(tester, FichePorcsScreen(depot: depot, soins: soins));

      await saisir(tester, 'depart-repro', '10');
      final motif =
          "La somme des catégories de départ (110) ne correspond pas à l'effectif total au début du jour de départ (100).";
      expect(find.text(motif), findsOneWidget);

      await enregistrer(tester);
      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
    });
  });

  testWidgets('Porcs — Verrats / Truies / Porcelets / Engraissement saisis, puis au tableau mensuel', (
    tester,
  ) async {
    await bande('porciculture', 'engraissement');
    await afficher(tester, FichePorcsScreen(depot: depot, soins: soins));

    await saisir(tester, 'effectif-verrats', '3');
    await saisir(tester, 'effectif-truies', '12');
    await saisir(tester, 'effectif-porcelets', '40');
    await saisir(tester, 'effectif-engraissement', '45');
    await enregistrer(tester);

    final f = await db.select(db.livestockDailyEntries).getSingle();
    expect([f.effectifM, f.effectifF, f.effectifSevres, f.effectifSmeres], [3, 12, 40, 45]);
    final ligne = find.byKey(const Key('ligne-mois-0'));
    for (final v in ['3', '12', '40', '45']) {
      expect(find.descendant(of: ligne, matching: find.text(v)), findsOneWidget, reason: v);
    }
  });

  testWidgets('Escargots — Naissains / Engraissement / Bordés saisis, puis au tableau mensuel', (
    tester,
  ) async {
    await bande('helico', 'engraissement');
    await afficher(tester, FicheEscargotsScreen(depot: depot, soins: soins));

    expect(find.byKey(const Key('escargots-effectifs-saisis')), findsOneWidget);
    await saisir(tester, 'effectif-naissains', '700');
    await saisir(tester, 'effectif-engraissement', '250');
    await saisir(tester, 'effectif-bordes', '50');
    await enregistrer(tester);

    final f = await db.select(db.livestockDailyEntries).getSingle();
    expect([f.effectifM, f.effectifF, f.effectifSevres, f.effectifSmeres], [700, 250, 50, null]);
    final ligne = find.byKey(const Key('ligne-mois-0'));
    for (final v in ['700', '250', '50']) {
      expect(find.descendant(of: ligne, matching: find.text(v)), findsOneWidget, reason: v);
    }
  });
}
