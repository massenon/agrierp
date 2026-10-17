import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_escargots_screen.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.17 — FICHE ESCARGOTS (`fiche-escargots.html`).
///
/// ⚠️⚠️ Deux singularités de cette fiche.
///
/// 1. **Aucun barème de ration n'existe pour l'héliciculture** : la section
///    reste un bandeau d'attente, jamais un tableau à zéro — qui se lirait
///    « aucune provende à servir ».
/// 2. **La maquette porte deux champs « Naissains Nés »** dont un seul alimente
///    l'effectif : une saisie dans l'autre se perdait en silence.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

  Future<void> bande({
    String? codeEspece = 'helico',
    int effectif = 2000,
  }) async {
    await db
        .into(db.livestockLots)
        .insertOnConflictUpdate(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'HEL-2026-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            speciesCode: Value(codeEspece),
            stage: const Value('engraissement'),
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
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FicheEscargotsScreen(depot: depot, soins: soins),
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
        'EFFECTIF ESCARGOTS TOTAL',
        'NAISSAINS NÉS (MOIS)',
        "TAUX D'ÉCLOSION NAISSAINS",
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
      y(tester, 'ACHATS DU JOUR'),
      y(tester, 'ŒUFS RÉCOLTÉS (PONDOIRS TERRE)'),
      y(tester, 'MORTS PAR CATÉGORIE'),
      y(tester, 'EFFECTIF FINAL DU JOUR (CALCULÉ DYNAMIQUE)'),
      y(tester, 'POIDS MOYEN CONSTATÉ'),
      y(
        tester,
        'Soins, Hygrométrie & Entretien du Substrat Prévus pour ce Jour',
      ),
      y(
        tester,
        'Attribution Parcs & Fosses en Terre Traités (Cochés par défaut)',
      ),
    ];

    expect(
      positions,
      equals([...positions]..sort()),
      reason:
          'ordre : Entrées, Pondoirs, Morts, Effectif, '
          'Pesée, Soins, Attribution',
    );
  });

  // 🔁 F0.99 — catégories des morts du WEB (`fiche-escargots.blade.php`), et aucun bloc Dons (le web n'en a pas).
  testWidgets('les trois catégories de morts sont celles du web, sans bloc Dons', (
    tester,
  ) async {
    await afficher(tester);

    for (final categorie in ['REPRODUCTEUR (BORDÉ)', 'ENGRAISSEMENT', 'NAISSAIN']) {
      expect(find.text(categorie), findsOneWidget, reason: categorie);
    }
    expect(find.text('DONS PAR CATÉGORIE'), findsNothing);
  });

  // ── Le barème manquant ─────────────────────────────────────────────────

  testWidgets(
    "⚠️⚠️ sans barème hélicicole, un bandeau d'attente et non un tableau à zéro",
    (tester) async {
      await afficher(tester);

      expect(find.textContaining('barème non fourni'), findsOneWidget);
      // Un tableau à zéro se lirait « aucune provende à servir ».
      expect(find.text('PROVENDE SERVIE (G)'), findsNothing);
    },
  );

  testWidgets('si un barème est un jour fourni, le tableau apparaît', (
    tester,
  ) async {
    await db
        .into(db.feedRationStandards)
        .insert(
          FeedRationStandardsCompanion.insert(
            id: 'ffffffff-1111-4111-8111-ffffffffffff',
            speciesCode: 'helico',
            stageLabel: 'Engraissement',
            rationGPerDay: 2,
          ),
        );

    await afficher(tester);

    expect(find.textContaining('barème non fourni'), findsNothing);
    expect(find.text('PROVENDE SERVIE (G)'), findsOneWidget);
    // 2000 escargots × 2 g = 4000 g.
    expect(find.text('4000 g'), findsOneWidget);
  });

  // ── Les deux champs « Naissains Nés » ──────────────────────────────────

  testWidgets(
    "⚠️⚠️ les deux champs « Naissains Nés » de la maquette restent cohérents",
    (tester) async {
      await afficher(tester);

      // La maquette en porte deux, dont un seul alimentait l'effectif : saisir
      // dans l'un doit se refléter dans l'autre, sinon une saisie se perd.
      await tester.enterText(
        find.byKey(const Key('champ-naissains-entree-0')),
        '150',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('champ-naissains-nes-150')), findsOneWidget);
    },
  );

  testWidgets("⚠️ les naissains nés augmentent l'effectif final", (
    tester,
  ) async {
    await afficher(tester);

    final avant = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    await tester.enterText(
      find.byKey(const Key('champ-naissains-nes-0')),
      '150',
    );
    await tester.pumpAndSettle();

    final apres = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    expect(int.parse(apres!), int.parse(avant!) + 150);
  });

  // ── Le taux d'éclosion ─────────────────────────────────────────────────

  testWidgets("⚠️ sans œuf récolté, le taux d'éclosion affiche un tiret", (
    tester,
  ) async {
    await afficher(tester);

    expect(lecture(tester, 'taux-eclosion'), '—');
  });

  testWidgets('150 naissains de 200 œufs récoltés font 75,0 %', (tester) async {
    await afficher(tester);

    await tester.enterText(find.byKey(const Key('champ-oeufs-terre-0')), '200');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('champ-naissains-nes-0')),
      '150',
    );
    await tester.pumpAndSettle();

    expect(lecture(tester, 'taux-eclosion'), '75.0 %');
  });

  // ── Correspondance des colonnes ────────────────────────────────────────

  testWidgets(
    '⚠️⚠️ les œufs récoltés vont dans ponteTotal, les naissains dans ne',
    (tester) async {
      await afficher(tester);

      await tester.enterText(
        find.byKey(const Key('champ-oeufs-terre-0')),
        '200',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('champ-naissains-nes-0')),
        '150',
      );
      await tester.pumpAndSettle();

      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();

      final fiche = await depot.chargerJour(bandeId, DateTime.now());
      expect(fiche?.ponteTotal, 200, reason: 'les œufs récoltés aux pondoirs');
      expect(fiche?.ne, 150, reason: 'les naissains nés');
    },
  );

  testWidgets('un mort saisi réduit aussitôt l effectif final', (tester) async {
    await afficher(tester);

    final avant = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    await tester.ensureVisible(find.byKey(const Key('pas-mort-Naissain-1')));
    await tester.tap(find.byKey(const Key('pas-mort-Naissain-1')));
    await tester.pumpAndSettle();

    final apres = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    expect(int.parse(apres!), int.parse(avant!) - 1);
  });

  // ── Écarts assumés ─────────────────────────────────────────────────────

  testWidgets("la section Attribution dit que son référentiel manque", (
    tester,
  ) async {
    await afficher(tester);

    expect(
      find.textContaining('Aucun référentiel de parcs et fosses'),
      findsOneWidget,
    );
    expect(find.textContaining('Fosse F1'), findsNothing);
  });

  testWidgets(
    "sans bande hélicicole, l'écran rappelle que le module est désactivé par défaut",
    (tester) async {
      await bande(codeEspece: 'cuniculture');

      await afficher(tester);

      expect(
        find.textContaining('Aucune bande hélicicole active'),
        findsOneWidget,
      );
      expect(
        find.textContaining('module désactivé par défaut'),
        findsOneWidget,
      );
    },
  );
}
