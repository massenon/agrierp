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

import 'package:agrierp/core/widgets/toast_agri.dart';

/// Ticket F0.14 — FICHE PONDEUSES ; 🔁 ticket U11 : le BLADE (`fiche-pondeuses.blade.php`) est la référence de mise
/// en page, plus la maquette (`fiche_pondeuses_blade_test.dart` lit la vue et exécute le PHP).
///
/// ⚠️⚠️ Deux choses sont protégées ici. D'abord **la conformité au Blade**
/// — ordre des sections et libellés au mot près. Ensuite **l'entrée réelle des plateaux au stock local** :
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

  // 🔁 Ticket U11 — l'ordre des sections du Blade (la maquette avait « Attribution Bâtiments » et un bloc de
  // prophylaxie à elle).
  testWidgets("⚠️ U11 — l'ordre des sections suit le Blade", (tester) async {
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await afficher(tester);

    final libelles = [
      'Saisie Journalière Ponte & Cheptel',
      'ACHATS / ENTRÉES DU JOUR',
      "WORKFLOW RÉCOLTE & STOCK D'ŒUFS",
      'MORTS PAR CATÉGORIE',
      'DONS PAR CATÉGORIE',
      'EFFECTIF FINAL DU JOUR',
      'RATIONNEMENT & PROVENDE SERVIE PAR STADE (EN GRAMMES G/J)',
      'POIDS GÉNÉRAL PESÉ (G)',
      'STOCK ŒUFS & PLATEAUX (30) — JOUR SÉLECTIONNÉ',
      'TRAITEMENTS & RAPPELS',
      'OBSERVATIONS',
      'Enregistrer ce Jour',
      'CHEPTEL DU JOUR',
    ];
    final positions = [
      for (final l in libelles) tester.getTopLeft(find.text(l).first).dy,
    ];
    final trie = [...positions]..sort();
    expect(positions, equals(trie), reason: libelles.join(' → '));
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
    // Ticket U11 — le nom du produit œufs, comme le Blade (`{{ $this->eggProduct->name }}`).
    expect(
      find.textContaining(
        '+14 Plateaux (Œufs de table (plateau))',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  /// 🔴→✅ Ticket U11 — `getTauxPonteCalcProperty()` / `getMortalityRateCalcProperty()` du web : divisés par l'effectif
  /// de la VEILLE (480, effectif initial, aucune fiche antérieure), « 0,0 % » sans saisie — le poste divisait la
  /// ponte par l'effectif FINAL et affichait « — ». Calcul à la main : 435 ÷ 480 × 100 = 90,625 → « 90,6 % » ;
  /// 1 mort ÷ 480 × 100 = 0,208… → « 0,2 % ».
  testWidgets('⚠️ U11 — taux du jour : ceux du web, sur l effectif de la veille', (tester) async {
    await afficher(tester);

    String valeur(String cle) => tester.widget<Text>(find.byKey(Key(cle))).data!;
    expect(valeur('champ-taux-ponte'), '0,0 %');
    expect(valeur('taux-mortalite-jour'), '0,0 %');

    await tester.enterText(find.byKey(const Key('champ-oeufs-pondus-0')), '435');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('pas-mort-Poulette-1')));
    await tester.tap(find.byKey(const Key('pas-mort-Poulette-1')));
    await tester.pumpAndSettle();

    expect(valeur('champ-taux-ponte'), '90,6 %');
    expect(valeur('taux-mortalite-jour'), '0,2 %');
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
      // Ticket U11 — le toast du web.
      expect(find.text('Jour enregistré avec succès.'), findsOneWidget);
      await tester.pump(ToastAgri.duree);

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

  // 🔁 Ticket U11 — le Blade n'a ni « Réinitialiser » ni « Attribution Bâtiments & Parcs Volailles Traités » ; il a
  // « Exporter PDF » dans l'en-tête.
  testWidgets('⚠️ U11 — boutons et sections du Blade, plus ceux de la maquette', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Enregistrer ce Jour'), findsOneWidget);
    expect(find.text('Exporter PDF'), findsOneWidget);
    expect(find.text('Réinitialiser'), findsNothing);
    expect(find.textContaining('Attribution Bâtiments'), findsNothing);
    expect(find.textContaining('COMBINE LES FICHES'), findsNothing);
    expect(find.text('(Pré-rempli de J-1)'), findsNothing);
  });

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
