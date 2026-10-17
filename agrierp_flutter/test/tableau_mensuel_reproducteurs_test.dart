import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/tableau_mensuel.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_reproducteurs_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.29 — TABLEAU MENSUEL DE LA FICHE REPRODUCTEURS.
///
/// ⚠️ **« LOT / SOUCHE » EST PLACÉ AVANT LES GROUPES**, exactement comme dans
/// `fiche-volailles-reproducteurs.html`. C'est la seule des cinq fiches à
/// intercaler une colonne entre la date et le premier groupe.
///
/// ⚠️⚠️ **REPRO / POULET / POUSSIN AFFICHENT UN TIRET.** La ventilation des
/// morts n'existe qu'à la saisie : la table n'a qu'une colonne `mort`. La
/// mortalité reste lisible dans « Taux Mort % », colonne de la maquette — rien
/// n'a été ajouté pour compenser.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'dddddddd-1111-4111-8111-dddddddddddd';

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

  Future<void> journee(
    int jour, {
    int couves = 0,
    int nes = 0,
    int mort = 0,
    int effectif = 200,
    double? moyenneG,
  }) async {
    final maintenant = DateTime.now();
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

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FicheReproducteursScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ les groupes de la maquette sont présents', (tester) async {
    await journee(3, couves: 120, nes: 96);
    await afficher(tester);

    // 🔁 F0.99 — groupes du WEB (`fiche-reproducteurs.blade.php`) : Couvoir, Morts (total).
    for (final g in ['COUVOIR', 'MORTS (TOTAL)']) {
      expect(
        find.descendant(of: tableau, matching: find.text(g)),
        findsOneWidget,
        reason: g,
      );
    }
  });

  testWidgets('toutes les colonnes du web sont là (sous-colonnes en casse mixte, 15.57)', (tester) async {
    await journee(3, couves: 120, nes: 96);
    await afficher(tester);

    for (final c in [
      'DATE',
      'Couvés',
      'Nés',
      'Repro+Poulet+Poussin',
      'EFFECTIF FINAL',
      'TAUX MORT %',
      'POIDS GÉNÉRAL (G)',
    ]) {
      expect(
        find.descendant(of: tableau, matching: find.text(c)),
        findsOneWidget,
        reason: c,
      );
    }
  });

  /// ⚠️ `ponte_total` = œufs COUVÉS, `ne` = poussins NÉS, comme le serveur.
  testWidgets('la ligne porte le couvoir du jour', (tester) async {
    await journee(3, couves: 120, nes: 96);
    await afficher(tester);

    expect(find.text('120'), findsWidgets);
    expect(find.text('96'), findsWidgets);
  });

  // 🔁 F0.99 — ni « Lot / Souche » ni « Traitements & Prophylaxie » : le web n'a pas ces colonnes.
  testWidgets('les colonnes absentes du web ne sont pas affichées', (tester) async {
    await journee(3, couves: 120);
    await afficher(tester);

    for (final c in ['LOT / SOUCHE', 'TRAITEMENTS & PROPHYLAXIE']) {
      expect(find.descendant(of: tableau, matching: find.text(c)), findsNothing, reason: c);
    }
  });

  /// ⚠️ 200 g de moyenne × 200 sujets = 40 000 g pesés, pas 200.
  testWidgets('la pesée se reconstitue en grammes', (tester) async {
    await journee(3, effectif: 200, moyenneG: 200);
    await afficher(tester);

    expect(find.text('40000'), findsOneWidget);
  });

  // 🔁 F0.99 — le web affiche le TOTAL des morts (seule valeur stockée), plus des tirets par catégorie.
  testWidgets('⚠️⚠️ la colonne des morts porte le total enregistré', (
    tester,
  ) async {
    await journee(3, couves: 120, mort: 4, effectif: 200, moyenneG: 200);
    await afficher(tester);

    final ligne = find.byKey(const Key('ligne-mois-0'));
    expect(find.descendant(of: ligne, matching: find.text('4')), findsOneWidget);
    expect(find.descendant(of: ligne, matching: find.text('—')), findsNothing);
  });

  /// 200 fin + 4 morts = 204 au départ → 4/204 = 2,0 %.
  testWidgets('le taux de mortalité est lisible', (
    tester,
  ) async {
    await journee(3, mort: 4, effectif: 200);
    await afficher(tester);

    expect(find.text('2.0'), findsWidgets);
  });

  testWidgets('toucher une ligne charge cette journée', (tester) async {
    await journee(3);
    await journee(8);

    await afficher(tester);

    final ligne = find.byKey(const Key('ligne-mois-0'));
    await tester.ensureVisible(ligne);
    await tester.tap(ligne);
    await tester.pumpAndSettle();

    expect(find.textContaining('Jour 3 ('), findsWidgets);
  });

  testWidgets('sans journée saisie, le tableau le dit', (tester) async {
    await afficher(tester);

    expect(find.text('— Aucune journée saisie ce mois-ci —'), findsOneWidget);
  });
}
