import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_porcs_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.15 — FICHE PORCS (`fiche-porcs.html`).
///
/// ⚠️⚠️ Le point le plus délicat de cette fiche est **l'unité** : c'est la
/// SEULE à peser en kilos, alors que la colonne de stockage
/// `weight_sample_avg_g` porte le poids moyen par sujet **en grammes**. Une
/// conversion manquante ou faite une fois de trop se solde par un facteur
/// mille, invisible jusqu'au suivi de croissance. Le serveur s'y était trompé
/// dans le sens du rechargement (corrigé au ticket 14.60).
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

  Future<void> bande({
    String? stade = 'engraissement',
    String? codeEspece = 'porciculture',
    int effectif = 100,
  }) async {
    await db
        .into(db.livestockLots)
        .insertOnConflictUpdate(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'POR-2026-01',
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

    // Référentiel de rations porcines, tel que le serveur le sert.
    const stades = {
      'Porcelet': 300.0,
      'Jeune porc': 600.0,
      'Porc reproducteur': 2000.0,
    };
    var i = 0;
    for (final entree in stades.entries) {
      await db
          .into(db.feedRationStandards)
          .insert(
            FeedRationStandardsCompanion.insert(
              id: 'ffffffff-1111-4111-8111-00000000000$i',
              speciesCode: 'porciculture',
              stageLabel: entree.key,
              rationGPerDay: entree.value,
            ),
          );
      i++;
    }
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FichePorcsScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String texte) =>
      tester.getTopLeft(find.text(texte)).dy;

  // ── Conformité à la maquette ───────────────────────────────────────────

  testWidgets(
    'les quatre cartes KPI sont celles de la maquette, dans son ordre',
    (tester) async {
      await afficher(tester);

      final libelles = [
        'EFFECTIF PORCINS VIVANTS',
        'TRUIES GESTANTES / VERRATS',
        'PORCELETS SOUS MÈRE',
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
      y(tester, 'MORTS PAR CATÉGORIE'),
      y(tester, 'DONS PAR CATÉGORIE'),
      y(tester, 'EFFECTIF FINAL DU JOUR (CALCULÉ DYNAMIQUE)'),
      y(tester, 'RATIONNEMENT & PROVENDE SERVIE PAR STADE PORCIN (EN GRAMMES G/J)'),
      y(tester, 'POIDS MOYEN CONSTATÉ'),
      y(tester, 'Traitements & Soins Porcins Automatiques Prévus pour ce Jour'),
      y(
        tester,
        'Attribution Logettes & Porcheries Traitées (Cochées par défaut)',
      ),
    ];

    expect(
      positions,
      equals([...positions]..sort()),
      reason:
          'ordre maquette : Morts, Dons, Effectif, Rationnement, Pesée, '
          'Soins, Attribution',
    );
  });

  // 🔁 F0.99 — libellés du WEB : les morts disent « Reproducteur (Truie/Verrat) » et « Porc marchand /
  // Engraiss. », les dons « Reproducteur » et « Porc marchand » (`fiche-porcs.blade.php`).
  testWidgets('les catégories des morts et des dons sont celles du web', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('REPRODUCTEUR (TRUIE/VERRAT)'), findsOneWidget);
    expect(find.text('PORC MARCHAND / ENGRAISS.'), findsOneWidget);
    expect(find.text('REPRODUCTEUR'), findsNWidgets(2), reason: 'bloc Dons + effectif de départ (15.57)');
    expect(find.text('PORC MARCHAND'), findsNWidgets(2), reason: 'bloc Dons + effectif de départ (15.57)');
    expect(find.text('PORCELET'), findsNWidgets(3), reason: 'Morts, Dons et effectif de départ (15.57)');
  });

  testWidgets('les libellés propres aux porcs sont repris tels quels', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('ACHATS DU JOUR'), findsOneWidget);
    expect(find.text('NÉS (MISE BAS PORCELETS)'), findsOneWidget);
    // ⚠️ EN KILOS — seule fiche à cette échelle.
    expect(find.text('POIDS GÉNÉRAL PESÉ (KG)'), findsOneWidget);
    expect(find.text('Enregistrer ce Jour'), findsOneWidget);
    expect(find.text('Réinitialiser'), findsOneWidget);
  });

  // ── L'unité, le point qui fait mal ─────────────────────────────────────

  testWidgets('⚠️⚠️ 850 Kg pesés sur 100 porcs donnent 8,5 Kg de moyenne', (
    tester,
  ) async {
    await afficher(tester);

    await tester.enterText(find.byKey(const Key('champ-pesee-0')), '850');
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('poids-moyen'))).data,
      '8.5 Kg',
      reason: 'une conversion de trop afficherait 0,0085 ou 8500',
    );
  });

  testWidgets(
    "⚠️⚠️ le poids traverse l'aller-retour : 850 Kg saisis, 850 Kg rechargés",
    (tester) async {
      await afficher(tester);

      await tester.enterText(find.byKey(const Key('champ-pesee-0')), '850');
      await tester.pumpAndSettle();

      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();

      // La moyenne stockée est bien en GRAMMES : 850 000 g ÷ 100 = 8 500 g.
      final fiche = await depot.chargerJour(bandeId, DateTime.now());
      expect(
        fiche?.weightSampleAvgG,
        8500,
        reason: 'y déposer des kilos serait une erreur d un facteur mille',
      );

      // Et le champ du total réaffiche bien un TOTAL, pas la moyenne.
      expect(find.byKey(const Key('champ-pesee-850')), findsOneWidget);
    },
  );

  testWidgets('sans pesée, le poids moyen affiche un tiret', (tester) async {
    await afficher(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('poids-moyen'))).data,
      '—',
      reason: '0 Kg se lirait « des porcs sans poids »',
    );
  });

  // ── Calculs et rationnement ────────────────────────────────────────────

  testWidgets('un mort saisi réduit aussitôt l effectif final', (tester) async {
    await afficher(tester);

    final avant = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    await tester.ensureVisible(find.byKey(const Key('pas-mort-Porcelet-1')));
    await tester.tap(find.byKey(const Key('pas-mort-Porcelet-1')));
    await tester.pumpAndSettle();

    final apres = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    expect(int.parse(apres!), int.parse(avant!) - 1);
  });

  testWidgets(
    '⚠️ la ration au-dessus du kilo double son unité, comme la maquette',
    (tester) async {
      await afficher(tester);

      // 🔁 F0.99 — `number_format($r, 0, ',', ' ')` du web : « 2 000 g/j (2.0 Kg) » sur la seule ligne
      // Reproducteur ; « 300 g/j » seul pour le Porcelet.
      expect(find.text('2 000 g/j (2.0 Kg)'), findsOneWidget);
      expect(find.text('300 g/j'), findsOneWidget);
    },
  );

  testWidgets("⚠️ la section Attribution dit que son référentiel manque", (
    tester,
  ) async {
    await afficher(tester);

    expect(
      find.textContaining('Aucun référentiel de logettes'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Logette L1'),
      findsNothing,
      reason: 'recopier les logettes de la maquette inventerait une donnée',
    );
  });

  testWidgets('sans bande porcine, l écran le dit au lieu de rester vide', (
    tester,
  ) async {
    await bande(codeEspece: 'cuniculture');

    await afficher(tester);

    expect(find.textContaining('Aucune bande porcine active'), findsOneWidget);
  });

  // ── 🔁 F0.99 — rationnement par catégorie, comme le web (15.42) ─────────────────
  // Barème du setUp : Porcelet 300, Jeune porc 600 (= Porc Marchand, D15), Porc reproducteur 2 000.
  // Bande sans chaîne : tout l'effectif dans la catégorie de son stade (`departDepuisStade`).

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  testWidgets('engraissement : 100 Porcs Marchands × 600 = 60 000 g, les autres lignes à 0', (
    tester,
  ) async {
    await afficher(tester);

    expect(texte(tester, 'ration-libelle-marchand'), 'Porc Marchand');
    expect(texte(tester, 'ration-effectif-marchand'), '100');
    expect(texte(tester, 'ration-grammes-marchand'), '${100 * 600} g');
    expect(texte(tester, 'ration-effectif-porcelet'), '0');
    expect(texte(tester, 'ration-effectif-reproducteur'), '0');
    expect(texte(tester, 'total-provende'), '60000 g (60 Kg)');
  });

  testWidgets('🔴 croissance : la ligne Porcelet est nourrie (le poste nourrissait « Jeune porc »)', (
    tester,
  ) async {
    await bande(stade: 'croissance');
    await afficher(tester);

    expect(texte(tester, 'ration-effectif-porcelet'), '100');
    expect(texte(tester, 'ration-effectif-marchand'), '0');
    expect(texte(tester, 'total-provende'), '${100 * 300} g (30 Kg)');
  });

  testWidgets('un mort Porc Marchand saisi réduit aussitôt sa ligne', (tester) async {
    await afficher(tester);

    await tester.ensureVisible(find.byKey(const Key('pas-mort-Porc Marchand-1')));
    await tester.tap(find.byKey(const Key('pas-mort-Porc Marchand-1')));
    await tester.pumpAndSettle();

    expect(texte(tester, 'ration-effectif-marchand'), '99');
    expect(texte(tester, 'total-provende'), '${99 * 600} g (59.4 Kg)');
  });

  testWidgets('bande sans stade : effectifs et total « — », jamais 0', (tester) async {
    await bande(stade: null);
    await afficher(tester);

    for (final c in ['porcelet', 'marchand', 'reproducteur']) {
      expect(texte(tester, 'ration-effectif-$c'), '—', reason: c);
      expect(texte(tester, 'ration-grammes-$c'), '—', reason: c);
    }
    expect(texte(tester, 'total-provende'), '—');
  });

  testWidgets('la ration vient du barème (650 g), pas du secours (600 g)', (tester) async {
    await (db.update(db.feedRationStandards)..where((t) => t.stageLabel.equals('Jeune porc')))
        .write(const FeedRationStandardsCompanion(rationGPerDay: Value(650)));
    await afficher(tester);

    expect(texte(tester, 'ration-g-marchand'), '650 g/j');
    expect(texte(tester, 'total-provende'), '${100 * 650} g (65 Kg)');
  });

  testWidgets('barème sans la catégorie : ration de secours du serveur (600 g)', (tester) async {
    await (db.delete(db.feedRationStandards)..where((t) => t.stageLabel.equals('Jeune porc'))).go();
    await afficher(tester);

    expect(texte(tester, 'ration-g-marchand'), '600 g/j');
    expect(texte(tester, 'total-provende'), '60000 g (60 Kg)');
  });
}
