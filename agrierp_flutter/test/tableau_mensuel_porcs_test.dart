import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_porcs_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.28 — TABLEAU MENSUEL DE LA FICHE PORCS, 🔁 ticket U12a : celui du Blade (TOUS les jours du mois, taux de
/// mortalité `mortality_rate` sur l'effectif de début `previousEffectif()`).
///
/// ⚠️⚠️ **LA COLONNE DE POIDS EST EN KILOS, seule fiche à cette échelle.** La base stocke la MOYENNE par sujet en
/// grammes (`weight_sample_avg_g`) ; le Blade affiche le TOTAL pesé en kilos, `round(moyenne × effectif ÷ 1000, 1)`
/// tel que PHP l'écrit (« 540 », « 85.5 »). Recopier la moyenne afficherait 45 là où 540 Kg ont été pesés (14.60).
///
/// ⚠️ Truies Gest. / Verrats / Porcelets / Engraiss. (`effectif_f`, `effectif_m`, `effectif_sevres`,
/// `effectif_smeres`, saisis, synchronisés depuis 15.57) : « — » quand ils sont inconnus.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'cccccccc-1111-4111-8111-cccccccccccc';
  final maintenant = HeureBenin.maintenant();
  final joursDuMois = DateTime(maintenant.year, maintenant.month + 1, 0).day;
  String deux(int n) => n.toString().padLeft(2, '0');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'POR-ENG-01',
            speciesId: 'ffffffff-1111-4111-8111-ffffffffffff',
            speciesCode: const Value('porciculture'),
            stage: const Value('engraissement'),
            createdDate: Value(DateTime.now()),
            initialQuantity: const Value(12),
            currentQuantity: const Value(12),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> journee(int jour, {int mort = 0, int effectif = 12, double? moyenneG}) async {
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: 'fiche-porc-$jour'.padRight(36, '-'),
            deviceId: 'poste-test',
            updatedAt: maintenant,
            lotId: bandeId,
            entryDate: DateTime(maintenant.year, maintenant.month, jour),
            mort: Value(mort),
            effectifFinal: Value(effectif),
            weightSampleAvgG: Value(moyenneG),
          ),
        );
  }

  /// `hidden lg:block` : le tableau n'existe qu'à partir de 1 024 px, comme au web.
  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: FichePorcsScreen(depot: depot, soins: soins)));
    await tester.pumpAndSettle();
  }

  Finder ligne(int index) => find.byKey(Key('ligne-mois-$index'));

  testWidgets('⚠️ les groupes du Blade sont présents', (tester) async {
    await journee(6);
    await afficher(tester);

    for (final g in ['ENTRÉES', 'SORTIES', 'EFFECTIF FINAL DU JOUR']) {
      expect(find.text(g), findsOneWidget, reason: g);
    }
  });

  testWidgets('toutes les colonnes du web sont là, dans le libellé du Blade', (tester) async {
    await journee(6);
    await afficher(tester);

    for (final c in [
      'DATE',
      'Achat',
      'Né',
      'Mort',
      'Vente',
      'Don',
      'Truies Gest.',
      'Verrats',
      'Porcelets',
      'Engraiss.',
      'Total',
      'TAUX MORT %',
      'POIDS GÉNÉRAL (KG)',
      'TRAITEMENTS & PROPHYLAXIE',
    ]) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
  });

  /// ⚠️⚠️ 45 000 g de moyenne × 12 sujets = 540 Kg (PHP écrit « 540 », sans décimale nulle).
  testWidgets('la pesée se reconstitue en kilos, pas en moyenne', (tester) async {
    await journee(6, effectif: 12, moyenneG: 45000);
    await afficher(tester);

    expect(find.descendant(of: ligne(5), matching: find.text('540')), findsOneWidget);
    expect(find.text('45.0'), findsNothing);
    expect(find.text('45'), findsNothing);
  });

  /// ⚠️ SANS PESÉE, LA CELLULE PORTE UN TIRET, jamais « 0 » : six tirets — les quatre effectifs saisis inconnus, le
  /// poids, les traitements.
  testWidgets('sans pesée, la colonne poids porte un tiret', (tester) async {
    await journee(6, effectif: 12);
    await afficher(tester);

    expect(find.descendant(of: ligne(5), matching: find.text('—')), findsNWidgets(6));
  });

  testWidgets('⚠️⚠️ les quatre effectifs saisis inconnus affichent un tiret', (tester) async {
    await journee(6, effectif: 12, moyenneG: 45000);
    await afficher(tester);

    // Truies Gest., Verrats, Porcelets, Engraiss. + Traitements — la colonne poids, elle, est renseignée.
    expect(find.descendant(of: ligne(5), matching: find.text('—')), findsNWidgets(5));
  });

  /// 🔁 U12a — `mortality_rate` du web : morts ÷ `previousEffectif()` (fiche précédente, sinon effectif INITIAL de la
  /// bande : 12), et non plus un effectif de début reconstitué (12 + 1 = 13, soit 7,7 %) : 1 ÷ 12 = 8,33 → « 8.3 ».
  testWidgets('le taux de mortalité se calcule sur l effectif de début du web', (tester) async {
    await journee(6, mort: 1, effectif: 11);
    await afficher(tester);

    expect(find.descendant(of: ligne(5), matching: find.text('8.3')), findsOneWidget);
  });

  testWidgets('toucher une ligne charge cette journée', (tester) async {
    await journee(6);
    await journee(11);

    await afficher(tester);

    await tester.ensureVisible(ligne(5));
    await tester.tap(ligne(5));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('date-choisie'))).data,
      '06/${deux(maintenant.month)}/${maintenant.year}',
    );
  });

  testWidgets('🔁 U12a — sans journée saisie, tous les jours du mois sont listés', (tester) async {
    await afficher(tester);

    expect(ligne(joursDuMois - 1), findsOneWidget);
    expect(find.text('— Aucune journée saisie ce mois-ci —'), findsNothing);
  });
}
