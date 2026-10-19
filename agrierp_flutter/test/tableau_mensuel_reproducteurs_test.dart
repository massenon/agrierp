import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/tableau_mensuel.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_reproducteurs_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.29 — TABLEAU MENSUEL DE LA FICHE REPRODUCTEURS, 🔁 F0.99 / U12a : celui du Blade
/// (`fiche-reproducteurs.blade.php`) — Date | Couvoir (Couvés, Nés) | Morts (total) (Repro+Poulet+Poussin) | Effectif
/// Final | Taux Mort % | Poids Général (g), TOUS les jours du mois, et la note du Blade sous le tableau.
///
/// ⚠️⚠️ La ventilation Repro / Poulet / Poussin des morts n'est pas conservée : la colonne porte le TOTAL enregistré.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'dddddddd-1111-4111-8111-dddddddddddd';
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
            code: 'AVI-REP-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            speciesCode: const Value('aviculture'),
            stage: const Value('reproduction'),
            createdDate: Value(DateTime.now()),
            initialQuantity: const Value(200),
            currentQuantity: const Value(200),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> journee(int jour, {int couves = 0, int nes = 0, int mort = 0, int effectif = 200, double? moyenneG}) async {
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: 'fiche-repro-$jour'.padRight(36, '-'),
            deviceId: 'poste-test',
            updatedAt: maintenant,
            lotId: bandeId,
            entryDate: DateTime(maintenant.year, maintenant.month, jour),
            ne: Value(nes),
            mort: Value(mort),
            effectifFinal: Value(effectif),
            ponteTotal: Value(couves),
            weightSampleAvgG: Value(moyenneG),
          ),
        );
  }

  final tableau = find.byType(TableauMensuel);

  /// `hidden lg:block` : le tableau n'existe qu'à partir de 1 024 px, comme au web.
  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: FicheReproducteursScreen(depot: depot, soins: soins)));
    await tester.pumpAndSettle();
  }

  Finder ligne(int index) => find.byKey(Key('ligne-mois-$index'));

  testWidgets('⚠️ les groupes du Blade sont présents', (tester) async {
    await journee(3, couves: 120, nes: 96);
    await afficher(tester);

    for (final g in ['COUVOIR', 'MORTS (TOTAL)']) {
      expect(find.descendant(of: tableau, matching: find.text(g)), findsOneWidget, reason: g);
    }
  });

  testWidgets('toutes les colonnes du web sont là, dans le libellé du Blade', (tester) async {
    await journee(3, couves: 120, nes: 96);
    await afficher(tester);

    for (final c in ['DATE', 'Couvés', 'Nés', 'Repro+Poulet+Poussin', 'EFFECTIF FINAL', 'TAUX MORT %', 'POIDS GÉNÉRAL (G)']) {
      expect(find.descendant(of: tableau, matching: find.text(c)), findsOneWidget, reason: c);
    }
  });

  /// ⚠️ `ponte_total` = œufs COUVÉS, `ne` = poussins NÉS, comme le serveur.
  testWidgets('la ligne porte le couvoir du jour', (tester) async {
    await journee(3, couves: 120, nes: 96);
    await afficher(tester);

    expect(find.descendant(of: ligne(2), matching: find.text('120')), findsOneWidget);
    expect(find.descendant(of: ligne(2), matching: find.text('96')), findsOneWidget);
  });

  // 🔁 F0.99 — ni « Lot / Souche » ni « Traitements & Prophylaxie » : le web n'a pas ces colonnes.
  testWidgets('les colonnes absentes du web ne sont pas affichées, la note du Blade l est', (tester) async {
    await journee(3, couves: 120);
    await afficher(tester);

    for (final c in ['LOT / SOUCHE', 'TRAITEMENTS & PROPHYLAXIE']) {
      expect(find.descendant(of: tableau, matching: find.text(c)), findsNothing, reason: c);
    }
    expect(find.byKey(const Key('note-ventilation-morts')), findsOneWidget);
  });

  /// ⚠️ 200 g de moyenne × 200 sujets = 40 000 g pesés, pas 200.
  testWidgets('la pesée se reconstitue en grammes', (tester) async {
    await journee(3, effectif: 200, moyenneG: 200);
    await afficher(tester);

    expect(find.descendant(of: ligne(2), matching: find.text('40000')), findsOneWidget);
  });

  testWidgets('⚠️⚠️ la colonne des morts porte le total enregistré', (tester) async {
    await journee(3, couves: 120, mort: 4, effectif: 200, moyenneG: 200);
    await afficher(tester);

    expect(find.descendant(of: ligne(2), matching: find.text('4')), findsOneWidget);
    expect(find.descendant(of: ligne(2), matching: find.text('—')), findsNothing);
  });

  /// 4 morts ÷ 200 (effectif initial, `previousEffectif()`) = 2,0 %.
  testWidgets('le taux de mortalité est lisible', (tester) async {
    await journee(3, mort: 4, effectif: 196);
    await afficher(tester);

    expect(find.descendant(of: ligne(2), matching: find.text('2.0')), findsOneWidget);
  });

  testWidgets('toucher une ligne charge cette journée', (tester) async {
    await journee(3);
    await journee(8);

    await afficher(tester);

    await tester.ensureVisible(ligne(2));
    await tester.tap(ligne(2));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('date-choisie'))).data,
      '03/${deux(maintenant.month)}/${maintenant.year}',
    );
  });

  testWidgets('🔁 U12a — sans journée saisie, tous les jours du mois sont listés', (tester) async {
    await afficher(tester);

    expect(ligne(joursDuMois - 1), findsOneWidget);
    expect(find.text('— Aucune journée saisie ce mois-ci —'), findsNothing);
  });
}
