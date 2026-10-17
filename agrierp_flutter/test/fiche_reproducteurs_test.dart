import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_reproducteurs_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.16 — FICHE REPRODUCTEURS (`fiche-volailles-reproducteurs.html`).
///
/// ⚠️⚠️ Deux pièges propres à cette fiche.
///
/// 1. **La correspondance des colonnes** : `ponte_total` porte les œufs
///    **couvés**, `ne` les poussins **nés**. Les inverser ferait passer une
///    couvée pour des naissances — et gonflerait l'effectif.
/// 2. **Le taux d'éclosion** : rien de couvé n'est PAS un taux de 0 %, encore
///    moins de 85 % (la valeur de démonstration que le serveur affichait, cf.
///    ticket 14.61). Une couvée entièrement perdue, elle, vaut bien 0 %.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

  Future<void> bande({
    String? stade = 'reproduction',
    String? codeEspece = 'aviculture',
    int effectif = 60,
  }) async {
    await db
        .into(db.livestockLots)
        .insertOnConflictUpdate(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'AVI-REP-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            speciesCode: Value(codeEspece),
            stage: Value(stade),
            createdDate: Value(DateTime.now()),
            initialQuantity: Value(effectif),
            currentQuantity: Value(effectif),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');

    await bande();

    await db
        .into(db.feedRationStandards)
        .insert(
          FeedRationStandardsCompanion.insert(
            id: 'ffffffff-1111-4111-8111-ffffffffffff',
            speciesCode: 'aviculture',
            stageLabel: 'Reproducteur',
            rationGPerDay: 130,
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FicheReproducteursScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String texte) =>
      tester.getTopLeft(find.text(texte)).dy;

  String? lecture(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key('lecture-$cle'))).data;

  // ── Conformité à la maquette ───────────────────────────────────────────

  testWidgets(
    'les quatre cartes KPI sont celles de la maquette, dans son ordre',
    (tester) async {
      await afficher(tester);

      final libelles = [
        'EFFECTIF TOTAL VIVANT',
        "TAUX D'ÉCLOSION COUVOIR",
        'POUSSINS NÉS (ÉCLOSION)',
        'TAUX DE MORTALITÉ',
      ];
      for (final l in libelles) {
        expect(find.text(l), findsOneWidget, reason: l);
      }

      final positions = libelles.map((l) => y(tester, l)).toList();
      expect(positions, equals([...positions]..sort()));
    },
  );

  testWidgets("⚠️ l'ordre des sections suit la maquette", (tester) async {
    await afficher(tester);

    final positions = [
      y(tester, 'BANDE / LOT CONCERNÉ'),
      y(tester, 'ŒUFS COUVÉS (MIS EN INCUBATION)'),
      y(tester, 'MORTS PAR CATÉGORIE'),
      y(tester, 'EFFECTIF FINAL DU JOUR (CALCULÉ DYNAMIQUE)'),
      y(tester, 'RATIONNEMENT & PROVENDE SERVIE PAR STADE (EN GRAMMES G/J)'),
      y(tester, 'POIDS MOYEN CONSTATÉ'),
      y(tester, 'Traitements & Vaccins Avicoles Automatiques Prévus'),
      y(
        tester,
        'Attribution Bâtiments & Parcs Volailles Traités (Cochés par défaut)',
      ),
    ];

    expect(
      positions,
      equals([...positions]..sort()),
      reason:
          'ordre : Bande, Couvoir, Morts, Effectif, '
          'Rationnement, Pesée, Vaccins, Attribution',
    );
  });

  // 🔁 F0.99 — catégories des morts du WEB (`fiche-reproducteurs.blade.php`), et aucun bloc Dons (le web n'en a pas).
  testWidgets('les trois catégories de morts sont celles du web, sans bloc Dons', (
    tester,
  ) async {
    await afficher(tester);

    for (final categorie in ['REPRO', 'POULET', 'POUSSIN']) {
      expect(find.text(categorie), findsOneWidget, reason: categorie);
    }
    expect(find.text('DONS PAR CATÉGORIE'), findsNothing);
  });

  // ── Le taux d'éclosion ─────────────────────────────────────────────────

  testWidgets("⚠️⚠️ sans œuf couvé, le taux d'éclosion affiche un tiret", (
    tester,
  ) async {
    await afficher(tester);

    expect(
      lecture(tester, 'taux-eclosion'),
      '—',
      reason: 'ni 0 %, ni surtout les 85 % de démonstration du serveur',
    );
  });

  testWidgets('34 poussins nés de 40 œufs couvés font 85,0 %', (tester) async {
    await afficher(tester);

    await tester.enterText(find.byKey(const Key('champ-oeufs-couves-0')), '40');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('champ-poussins-nes-0')), '34');
    await tester.pumpAndSettle();

    expect(lecture(tester, 'taux-eclosion'), '85.0 %');
  });

  testWidgets(
    "⚠️ une couvée entièrement perdue vaut 0 %, et se distingue de « rien de couvé »",
    (tester) async {
      await afficher(tester);

      await tester.enterText(
        find.byKey(const Key('champ-oeufs-couves-0')),
        '40',
      );
      await tester.pumpAndSettle();

      expect(
        lecture(tester, 'taux-eclosion'),
        '0.0 %',
        reason:
            'un fait clinique, tout différent d une absence de mise en '
            'incubation',
      );
    },
  );

  // ── La correspondance des colonnes ─────────────────────────────────────

  testWidgets(
    '⚠️⚠️ les œufs couvés vont dans ponteTotal, les poussins nés dans ne',
    (tester) async {
      await afficher(tester);

      await tester.enterText(
        find.byKey(const Key('champ-oeufs-couves-0')),
        '40',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('champ-poussins-nes-0')),
        '34',
      );
      await tester.pumpAndSettle();

      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();

      final fiche = await depot.chargerJour(bandeId, DateTime.now());
      expect(fiche?.ponteTotal, 40, reason: 'les œufs mis en incubation');
      expect(fiche?.ne, 34, reason: 'les naissances du jour');
    },
  );

  testWidgets("⚠️ les poussins nés augmentent l'effectif final", (
    tester,
  ) async {
    await afficher(tester);

    final avant = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    await tester.enterText(find.byKey(const Key('champ-poussins-nes-0')), '10');
    await tester.pumpAndSettle();

    final apres = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    expect(int.parse(apres!), int.parse(avant!) + 10);
  });

  testWidgets('un mort saisi réduit aussitôt l effectif final', (tester) async {
    await afficher(tester);

    final avant = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    await tester.ensureVisible(
      find.byKey(const Key('pas-mort-Repro-1')),
    );
    await tester.tap(find.byKey(const Key('pas-mort-Repro-1')));
    await tester.pumpAndSettle();

    final apres = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    expect(int.parse(apres!), int.parse(avant!) - 1);
  });

  // ── Écarts assumés ─────────────────────────────────────────────────────

  testWidgets(
    "⚠️ une bande en reproduction voit son protocole déclaré indéterminable",
    (tester) async {
      // Le cycle se compte depuis la dernière saillie ; AUCUNE saillie n'est
      // enregistrée pour cette bande : c'est SUR CETTE FICHE que le cas se
      // produit le plus (F0.91 : avec une saillie, le jour est calculé).
      await db
          .into(db.prophylaxisScheduleStandards)
          .insert(
            ProphylaxisScheduleStandardsCompanion.insert(
              id: '11111111-1111-4111-8111-111111111111',
              speciesCode: 'aviculture',
              periodLabel: 'J1',
              cycleDayStart: const Value(1),
              cycleDayEnd: const Value(60),
              treatment: 'Vaccin Newcastle',
            ),
          );

      await afficher(tester);

      expect(find.text('Indéterminé'), findsOneWidget);
      expect(find.textContaining('saillie'), findsOneWidget);
    },
  );

  testWidgets("la section Attribution dit que son référentiel manque", (
    tester,
  ) async {
    await afficher(tester);

    expect(
      find.textContaining('Aucun référentiel de bâtiments'),
      findsOneWidget,
    );
    expect(find.textContaining('Parc R1'), findsNothing);
  });

  testWidgets('sans bande avicole hors ponte, l écran le dit', (tester) async {
    await bande(stade: 'ponte');

    await afficher(tester);

    expect(
      find.textContaining('Aucune bande avicole hors ponte'),
      findsOneWidget,
    );
  });

  testWidgets(
    "⚠️⚠️ une bande de CHAIR en engraissement est pilotée par cette fiche",
    (tester) async {
      // Le titre de la maquette le dit — « Reproducteurs & Goliath » — et le
      // serveur applique `stage != 'ponte'`. Filtrer sur la seule reproduction
      // rendait les bandes de chair INVISIBLES au poste, alors que le web les
      // gere : leur saisie journaliere devenait impossible sur le terrain.
      await bande(stade: 'engraissement');

      await afficher(tester);

      expect(
        find.textContaining('Aucune bande avicole hors ponte'),
        findsNothing,
      );
      expect(find.byKey(const Key('effectif-final')), findsOneWidget);
    },
  );
}
