import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_pondeuses_screen.dart';
import 'package:agrierp/features/elevage/production_oeufs_service.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.14 — FICHE PONDEUSES (`fiche-volailles-pondeuses.html`).
///
/// ⚠️⚠️ Deux choses sont protégées ici. D'abord **la conformité à la maquette**
/// — ordre des sections et libellés au mot près, la maquette étant la référence
/// de mise en page. Ensuite **l'entrée réelle des plateaux au stock local** :
/// sans elle, la caisse du poste refuserait de vendre des œufs qu'il vient de
/// récolter, tant qu'aucune synchronisation n'a eu lieu.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;
  late ProductionOeufsService production;

  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const produitOeufsId = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';

  Future<void> bande({
    String? stade = 'ponte',
    String? codeEspece = 'aviculture',
    int effectif = 480,
  }) async {
    await db
        .into(db.livestockLots)
        .insertOnConflictUpdate(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'AVI-PON-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            speciesCode: Value(codeEspece),
            stage: Value(stade),
            createdDate: Value(HeureBenin.maintenant()),
            initialQuantity: Value(effectif),
            currentQuantity: Value(effectif),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
    production = ProductionOeufsService(database: db);

    await bande();

    // ⚠️ LIGATURE EN MAJUSCULE, comme au catalogue réel.
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: produitOeufsId,
            sku: 'OEUF-PLT',
            name: 'Œufs de table (plateau)',
            unit: 'plateau',
            pricingMode: 'fourchette',
            stockQty: const Value(48),
          ),
        );

    // Référentiel de rations aviculture, tel que le serveur le sert.
    const stades = {
      'Poussin ponte (0 à 2 mois)': 30.0,
      'Poussin en croissance (2 à 4 mois)': 60.0,
      'Poulette (4 à 5.5 mois)': 80.0,
      'Pondeuse (6 à 18 mois)': 110.0,
    };
    var i = 0;
    for (final entree in stades.entries) {
      await db
          .into(db.feedRationStandards)
          .insert(
            FeedRationStandardsCompanion.insert(
              id: 'ffffffff-1111-4111-8111-00000000000$i',
              speciesCode: 'aviculture',
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
        home: FichePondeusesScreen(
          depot: depot,
          soins: soins,
          production: production,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String texte) =>
      tester.getTopLeft(find.text(texte)).dy;

  // ── Calculs purs, repris de `computePonteAndPlateaux()` ─────────────────

  test(
    '435 récoltés − 15 cassés = 420 commercialisables = 14 plateaux + 0 vrac',
    () {
      final comm = ProductionOeufsService.commercialisables(
        recoltes: 435,
        casses: 15,
      );
      expect(comm, 420);

      final nets = ProductionOeufsService.enPlateaux(comm);
      expect(nets.plateaux, 14);
      expect(nets.vrac, 0);
    },
  );

  test('le reliquat sous le plateau est annoncé en vrac, pas arrondi', () {
    final nets = ProductionOeufsService.enPlateaux(435);
    expect(nets.plateaux, 14);
    expect(
      nets.vrac,
      15,
      reason: 'la maquette affiche « 14 Plateaux (15 vrac) »',
    );
  });

  test('plus de cassés que de récoltés ne donne jamais un négatif', () {
    expect(
      ProductionOeufsService.commercialisables(recoltes: 10, casses: 40),
      0,
    );
  });

  test('⚠️ le taux de ponte est nul, pas zéro, sans effectif', () {
    expect(
      ProductionOeufsService.tauxDePonte(recoltes: 440, effectif: 0),
      isNull,
      reason: '0 % se lirait « les poules n ont pas pondu »',
    );
    // ⚠️ 440 / 480 = 91,67 %. Le « 91.6 % » de la maquette est du texte de
    // demonstration statique, pas le resultat de son propre calcul.
    expect(
      ProductionOeufsService.tauxDePonte(recoltes: 440, effectif: 480),
      closeTo(91.67, 0.01),
    );
  });

  // ── Garde-fou du stock ─────────────────────────────────────────────────

  test(
    '⚠️⚠️ une bande qui n est pas de l aviculture n alimente pas le stock',
    () async {
      await bande(codeEspece: 'helico');
      final lot = await (db.select(
        db.livestockLots,
      )..where((t) => t.id.equals(bandeId))).getSingle();

      final plateaux = await production.entrerAuStock(
        bande: lot,
        recoltes: 900,
        casses: 0,
        creation: true,
      );

      expect(
        plateaux,
        0,
        reason: 'une ponte d escargots n est pas un oeuf de table',
      );
    },
  );

  test("⚠️ une correction du même jour ne recompte pas les œufs", () async {
    final lot = await (db.select(
      db.livestockLots,
    )..where((t) => t.id.equals(bandeId))).getSingle();

    expect(
      await production.entrerAuStock(
        bande: lot,
        recoltes: 435,
        casses: 15,
        creation: false,
      ),
      0,
    );
  });

  // ── Conformité à la maquette ───────────────────────────────────────────

  testWidgets(
    'les quatre cartes KPI sont celles de la maquette, dans son ordre',
    (tester) async {
      await afficher(tester);

      final libelles = [
        'EFFECTIF PONDEUSES VIVANTES',
        'TAUX DE PONTE MOYEN',
        'STOCK PLATEAUX (30 ŒUFS)',
        'TAUX DE MORTALITÉ',
      ];
      for (final l in libelles) {
        expect(find.text(l), findsOneWidget, reason: l);
      }

      final positions = libelles.map((l) => y(tester, l)).toList();
      final trie = [...positions]..sort();
      expect(positions, equals(trie));
    },
  );

  testWidgets("⚠️ l'ordre des sections suit la maquette", (tester) async {
    await afficher(tester);

    final positions = [
      y(
        tester,
        "WORKFLOW RÉCOLTE & STOCK D'ŒUFS (COMBINE LES FICHES OFFICIELLES DE LA FERME)",
      ),
      y(tester, 'MORTS PAR CATÉGORIE'),
      y(tester, 'DONS PAR CATÉGORIE'),
      y(tester, 'EFFECTIF FINAL DU JOUR (CALCULÉ DYNAMIQUE)'),
      y(tester, 'RATIONNEMENT & PROVENDE SERVIE PAR STADE (EN GRAMMES G/J)'),
      y(tester, 'POIDS MOYEN CONSTATÉ'),
      y(
        tester,
        'Traitements & Prophylaxie Avicole Automatiques Prévus pour ce Jour',
      ),
      y(
        tester,
        'Attribution Bâtiments & Parcs Volailles Traités (Cochés par défaut)',
      ),
    ];

    final trie = [...positions]..sort();
    expect(
      positions,
      equals(trie),
      reason:
          'ordre : Œufs, Morts, Dons, Effectif, Rationnement, '
          'Pesée, Prophylaxie, Attribution',
    );
  });

  // 🔁 F0.99 — catégories des morts du WEB (`fiche-pondeuses.blade.php`), Dons sur les mêmes catégories (15.56).
  testWidgets('les trois catégories du web portent les morts ET les dons', (
    tester,
  ) async {
    await afficher(tester);

    for (final stade in ['PONDEUSE / REPRO', 'POULETTE', 'POUSSIN']) {
      expect(find.text(stade), findsNWidgets(2), reason: '$stade : Morts et Dons');
    }
    expect(find.text('DONS PAR CATÉGORIE'), findsOneWidget);
    expect(find.text('POUSSIN PONTE'), findsNothing);
  });

  testWidgets('le bloc œufs recalcule à la saisie', (tester) async {
    await afficher(tester);

    await tester.enterText(
      find.byKey(const Key('champ-oeufs-pondus-0')),
      '435',
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('champ-oeufs-casses-0')), '15');
    await tester.pumpAndSettle();

    // Les deux encarts melent libelle normal et valeur en gras dans un meme
    // paragraphe, comme la maquette : le finder doit lire le texte enrichi.
    expect(
      find.textContaining('14 Plateaux (0 œufs vrac)', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('+14 Plateaux au Stock Produits', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('un mort saisi réduit aussitôt l effectif final', (tester) async {
    await afficher(tester);

    final avant = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    await tester.ensureVisible(find.byKey(const Key('pas-mort-Pondeuse / Repro-1')));
    await tester.tap(find.byKey(const Key('pas-mort-Pondeuse / Repro-1')));
    await tester.pumpAndSettle();

    final apres = tester
        .widget<Text>(find.byKey(const Key('effectif-final')))
        .data;

    expect(int.parse(apres!), int.parse(avant!) - 1);
  });

  testWidgets(
    '⚠️⚠️ enregistrer fait entrer les plateaux au stock LOCAL, tout de suite',
    (tester) async {
      await afficher(tester);

      await tester.enterText(
        find.byKey(const Key('champ-oeufs-pondus-0')),
        '435',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('champ-oeufs-casses-0')),
        '15',
      );
      await tester.pumpAndSettle();

      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();

      final produit = await (db.select(
        db.products,
      )..where((t) => t.id.equals(produitOeufsId))).getSingle();

      // 48 plateaux au départ + 14 récoltés.
      expect(
        produit.stockQty,
        62,
        reason: 'sans cela la caisse du poste refuserait de vendre ces œufs',
      );

      final fiche = await depot.chargerJour(bandeId, HeureBenin.maintenant());
      expect(fiche?.ponteTotal, 435);
      expect(fiche?.ponteCasses, 15);
    },
  );

  testWidgets('les libellés des boutons sont ceux de la maquette', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Enregistrer ce Jour'), findsOneWidget);
    expect(find.text('Réinitialiser'), findsOneWidget);
  });

  testWidgets(
    "⚠️ la section Attribution est là et dit que son référentiel manque",
    (tester) async {
      await afficher(tester);

      expect(
        find.textContaining('Aucun référentiel de bâtiments'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Bâtiment P1'),
        findsNothing,
        reason: 'recopier les bâtiments de la maquette inventerait une donnée',
      );
    },
  );

  testWidgets('sans bande de ponte, l écran le dit au lieu de rester vide', (
    tester,
  ) async {
    await (db.update(db.livestockLots)..where((t) => t.id.equals(bandeId)))
        .write(const LivestockLotsCompanion(stage: Value('croissance')));

    await afficher(tester);

    expect(
      find.textContaining('Aucune bande active au stade Ponte'),
      findsOneWidget,
    );
  });

  // 🔁 15.56 — un don fait quitter le sujet : l'effectif final baisse aussitôt, comme sur le web.
  testWidgets('un don saisi réduit aussitôt l effectif final', (tester) async {
    await afficher(tester);

    final avant = tester.widget<Text>(find.byKey(const Key('effectif-final'))).data;
    await tester.ensureVisible(find.byKey(const Key('pas-don-Poulette-1')));
    await tester.tap(find.byKey(const Key('pas-don-Poulette-1')));
    await tester.pumpAndSettle();
    final apres = tester.widget<Text>(find.byKey(const Key('effectif-final'))).data;

    expect(int.parse(apres!), int.parse(avant!) - 1);
  });
}
