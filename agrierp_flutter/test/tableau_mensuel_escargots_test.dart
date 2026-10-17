import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/tableau_mensuel.dart';
import 'package:agrierp/features/elevage/fiche_escargots_screen.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.30 — TABLEAU MENSUEL DE LA FICHE ESCARGOTS.
///
/// ⚠️ **« NAISSAIN NÉ » AU SINGULIER EN ENTRÉE, « NAISSAINS » AU PLURIEL EN
/// EFFECTIF** : deux libellés distincts dans `fiche-escargots.html`, recopiés
/// tels quels. C'est l'un des arbitrages client encore ouverts — les
/// harmoniser ici serait trancher à la place du client.
///
/// ⚠️⚠️ **NAISSAINS / ENGRAISS. / BORDÉS AFFICHENT UN TIRET** : la ventilation
/// par stade n'existe qu'à la saisie ; la table ne porte que l'effectif total.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'HEL-ENG-01',
            speciesId: '11111111-1111-4111-8111-111111111111',
            speciesCode: const Value('helico'),
            stage: const Value('engraissement'),
            createdDate: Value(DateTime.now()),
            initialQuantity: const Value(1500),
            currentQuantity: const Value(1500),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> journee(
    int jour, {
    int achat = 0,
    int ne = 0,
    int mort = 0,
    int vente = 0,
    int don = 0,
    int effectif = 1500,
    double? moyenneG,
  }) async {
    final maintenant = DateTime.now();
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: 'fiche-esc-$jour'.padRight(36, '-'),
            deviceId: 'poste-test',
            updatedAt: maintenant,
            lotId: bandeId,
            entryDate: DateTime(maintenant.year, maintenant.month, jour),
            achat: Value(achat),
            ne: Value(ne),
            mort: Value(mort),
            vente: Value(vente),
            don: Value(don),
            effectifFinal: Value(effectif),
            weightSampleAvgG: Value(moyenneG),
          ),
        );
  }

  final tableau = find.byType(TableauMensuel);

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FicheEscargotsScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ les groupes de la maquette sont présents', (tester) async {
    await journee(5, ne: 40);
    await afficher(tester);

    for (final g in ['ENTRÉES', 'SORTIES', 'EFFECTIF FINAL DU JOUR']) {
      expect(
        find.descendant(of: tableau, matching: find.text(g)),
        findsOneWidget,
        reason: g,
      );
    }
  });

  testWidgets('toutes les colonnes de la maquette sont là', (tester) async {
    await journee(5, ne: 40);
    await afficher(tester);

    for (final c in [
      'DATE',
      'ACHAT',
      'NAISSAIN NÉ',
      'MORT',
      'VENTE',
      'DON',
      'NAISSAINS',
      'ENGRAISS.',
      'BORDÉS',
      'TOTAL',
      'TAUX MORT %',
      'POIDS GÉNÉRAL (G)',
      'TRAITEMENTS & PROPHYLAXIE',
    ]) {
      expect(
        find.descendant(of: tableau, matching: find.text(c)),
        findsOneWidget,
        reason: c,
      );
    }
  });

  /// ⚠️ 12 g de moyenne × 1 500 sujets = 18 000 g pesés, pas 12.
  testWidgets('la pesée se reconstitue en grammes', (tester) async {
    await journee(5, effectif: 1500, moyenneG: 12);
    await afficher(tester);

    expect(
      find.descendant(of: tableau, matching: find.text('18000')),
      findsOneWidget,
    );
  });

  testWidgets('⚠️⚠️ les trois stades non synchronisés affichent un tiret', (
    tester,
  ) async {
    await journee(5, effectif: 1500, moyenneG: 12);
    await afficher(tester);

    // Naissains, Engraiss., Bordés + Entretien & Hygrométrie.
    final ligne = find.byKey(const Key('ligne-mois-0'));
    expect(
      find.descendant(of: ligne, matching: find.text('—')),
      findsNWidgets(4),
    );
  });

  /// 1 500 fin + 30 morts = 1 530 au départ → 30/1530 = 2,0 %.
  testWidgets(
    'le taux de mortalité du jour se calcule sur l effectif de début',
    (tester) async {
      await journee(5, mort: 30, effectif: 1500);
      await afficher(tester);

      expect(
        find.descendant(of: tableau, matching: find.text('2.0')),
        findsOneWidget,
      );
    },
  );

  testWidgets('toucher une ligne charge cette journée', (tester) async {
    await journee(5);
    await journee(12);

    await afficher(tester);

    final ligne = find.byKey(const Key('ligne-mois-0'));
    await tester.ensureVisible(ligne);
    await tester.tap(ligne);
    await tester.pumpAndSettle();

    expect(find.textContaining('Jour 5 ('), findsWidgets);
  });

  testWidgets('sans journée saisie, le tableau le dit', (tester) async {
    await afficher(tester);

    expect(find.text('— Aucune journée saisie ce mois-ci —'), findsOneWidget);
  });
}
