import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/stocks/gestion_stocks_screen.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.38 — GESTION STOCKS (`prototype_html/gestion-stocks.html`).
///
/// ⚠️⚠️ **AUCUN ÉCRAN NE CRÉAIT D'AJUSTEMENT.** `stock_adjustments` est poussée
/// par le moteur depuis le ticket F0.3, et le serveur la rejoue par son action
/// d'ajustement — mais **rien au poste ne l'alimentait**. Le canal d'envoi
/// existait sans producteur : un inventaire physique constaté au magasin
/// n'avait aucun moyen d'être saisi hors ligne.
///
/// Ticket U8 — la valorisation (PMP, valeurs, écarts en FCFA) est désormais celle
/// du web, sur les lignes d'achat descendues depuis U4 : voir
/// `valorisation_stocks_test.dart` (jeu fait à la main et parité exécutée PHP).
void main() {
  late AppDatabase db;
  late StocksRepository depot;

  const provende = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
  const oeufs = 'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb';
  const categorieAliments = 'cccccccc-0000-4000-8000-cccccccccccc';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = StocksRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.productCategories)
        .insert(
          ProductCategoriesCompanion.insert(
            id: categorieAliments,
            label: 'Aliments',
          ),
        );

    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: provende,
            sku: 'ALI-001',
            name: 'Aliment ponte 25kg',
            categoryId: const Value(categorieAliments),
            unit: 'sac',
            pricingMode: 'fixe',
            stockQty: const Value(45),
            alertThreshold: const Value(15),
          ),
        );

    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: oeufs,
            sku: 'AVI-002',
            name: 'Œufs de table (plateau)',
            unit: 'plateau',
            pricingMode: 'fixe',
            stockQty: const Value(8),
            alertThreshold: const Value(30),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(home: GestionStocksScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-stocks-$onglet')));
    await tester.pumpAndSettle();
  }

  group('dépôt', () {
    /// ⚠️⚠️ LE CŒUR DU TICKET : le poste sait enfin saisir un écart.
    test('⚠️⚠️ un manquant produit une SORTIE en file d envoi', () async {
      // 45 théoriques, 40 comptés → 5 manquants.
      final ecart = await depot.enregistrerEcart(
        productId: provende,
        stockPhysique: 40,
        motif: 'Vol / Disparition',
      );

      expect(ecart.type, 'sortie');
      // ⚠️ LE SIGNE EST PORTÉ PAR `type`, JAMAIS PAR LA QUANTITÉ : le serveur
      // refuse une quantité négative ou nulle.
      expect(ecart.quantity, 5);
      expect(ecart.referenceType, 'inventaire');
      expect(ecart.reason, 'Vol / Disparition');
      expect(ecart.syncStatus, SyncStatus.pending);
    });

    test('un excédent produit une ENTRÉE', () async {
      final ecart = await depot.enregistrerEcart(
        productId: provende,
        stockPhysique: 52,
        motif: 'Surplus de livraison',
      );

      expect(ecart.type, 'entree');
      expect(ecart.quantity, 7);
    });

    /// ⚠️ Tout l'objet d'un inventaire : le comptage physique devient la
    /// vérité locale. Le serveur, lui, recalcule depuis son propre état.
    test('⚠️ le stock local suit immédiatement le comptage', () async {
      await depot.enregistrerEcart(
        productId: provende,
        stockPhysique: 40,
        motif: 'Vol / Disparition',
      );

      final produit = await (db.select(
        db.products,
      )..where((t) => t.id.equals(provende))).getSingle();

      expect(produit.stockQty, 40);
    });

    /// ⚠️ Un écart nul n'est pas un mouvement : le serveur le rejetterait
    /// (`quantity` strictement positive) et la ligne ne dirait rien.
    test('⚠️ un écart nul est refusé', () async {
      expect(
        () => depot.enregistrerEcart(
          productId: provende,
          stockPhysique: 45,
          motif: 'Erreur d inventaire antérieur',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('le motif est obligatoire', () async {
      expect(
        () => depot.enregistrerEcart(
          productId: provende,
          stockPhysique: 40,
          motif: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    /// 🔴→✅ Le badge « en attente » compte l'ajustement : la table figure
    /// dans `pendingCount()` depuis l'origine, contrairement aux dépenses
    /// (corrigé au ticket F0.35).
    test('l ajustement compte dans le badge en attente', () async {
      expect(await db.pendingCount(), 0);

      await depot.enregistrerEcart(
        productId: provende,
        stockPhysique: 40,
        motif: 'Vol / Disparition',
      );

      expect(await db.pendingCount(), 1);
    });
  });

  group('écran', () {
    testWidgets('⚠️ les trois onglets de la maquette sont là, dans son ordre', (
      tester,
    ) async {
      await afficher(tester);

      for (final onglet in [
        'Tableau & Valorisation',
        'Journal des Mouvements',
        'Ajustement / Correction',
      ]) {
        expect(find.text(onglet), findsOneWidget, reason: onglet);
      }
    });

    testWidgets('les quatre KPI portent les libellés de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      for (final libelle in [
        'VALORISATION STOCKS',
        'ALERTES DE SEUIL',
        'ROTATION DU STOCK',
        "ÉCARTS D'INVENTAIRE",
      ]) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }
    });

    /// ⚠️⚠️ Sans prix de revient, aucune valorisation possible — ni au poste
    /// ni au serveur pour ce qui n'a jamais été acheté.
    /// ⚠️⚠️ **LE NOMBRE DE CARTES, PAS SEULEMENT LEURS LIBELLÉS** (ticket
    /// F0.54). Le contrôle voisin vérifie que les quatre libellés attendus sont
    /// présents ; il ne dirait rien d'une CINQUIÈME carte ajoutée, ni d'une
    /// carte de la maquette rendue deux fois. `cartesMaquette` est relevé sur
    /// la maquette elle-même (`border-l-4`) : c'est lui qui fait foi.
    testWidgets('⚠️⚠️ l écran rend le nombre de cartes de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      expect(
        find.byType(CarteKpi),
        findsNWidgets(cartesAttendues('gestion-stocks.html')),
      );
    });

    /// Ticket U8 — la valorisation est celle du web (voir `valorisation_stocks_test`) : sans aucune
    /// ligne d'achat, aucun produit n'a de PMP, et le web affiche « 0 FCFA » (un produit sans PMP est
    /// exclu de la somme), PMP et valeur « — » sur chaque ligne.
    testWidgets('⚠️⚠️ sans achat, la valorisation vaut 0 FCFA et chaque PMP est un tiret', (
      tester,
    ) async {
      await afficher(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-Valorisation Stocks')),
          matching: find.text('0 FCFA'),
        ),
        findsOneWidget,
      );
      expect(find.text('Basée sur le PMP réel (achats)'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        expect(tester.widget<Text>(find.byKey(Key('pmp-$i'))).data, '—');
        expect(tester.widget<Text>(find.byKey(Key('valeur-$i'))).data, '—');
      }
    });

    testWidgets('les alertes de seuil comptent les produits sous leur seuil', (
      tester,
    ) async {
      await afficher(tester);

      // Œufs : 8 pour un seuil de 30. La provende, elle, est à 45 pour 15.
      // Ticket U9 — `$kpis['alertes'].' réf.'` du Blade.
      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-Alertes de Seuil')),
          matching: find.text('1 réf.'),
        ),
        findsOneWidget,
      );
    });

    /// 🔴→✅ Ticket U9 — `urgence = alert_threshold > 0 && stock <= alert_threshold` : un seuil NUL ne déclenche
    /// rien au web. Le poste comptait « Sous seuil » un produit à 0 dont le seuil valait 0.
    testWidgets('U9 — un seuil nul n est jamais une alerte, comme au web', (
      tester,
    ) async {
      await (db.update(db.products)..where((t) => t.id.equals(oeufs))).write(
        const ProductsCompanion(stockQty: Value(0), alertThreshold: Value(0)),
      );
      await afficher(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-Alertes de Seuil')),
          matching: find.text('0 réf.'),
        ),
        findsOneWidget,
      );
      expect(find.text('Critique'), findsNothing);
      expect(find.text('Normal'), findsNWidgets(2));
    });

    /// 🔴→✅ Ticket U9 — `Product::where('is_active', true)->orderBy('name')` : le poste triait par CODE.
    testWidgets('U9 — le tableau est trié par NOM, comme au web (pas par code)', (
      tester,
    ) async {
      // Code « AAA-000 » (premier par code), nom « Zinc… » (dernier par nom) ; « Bâche » s'intercale par sa
      // collation (accent ignoré), pas après « Œufs ».
      for (final (id, sku, nom) in [
        ('dddddddd-0000-4000-8000-dddddddddddd', 'AAA-000', 'Zinc oxyde 1kg'),
        ('eeeeeeee-0000-4000-8000-eeeeeeeeeeee', 'ZZZ-999', 'bâche agricole'),
      ]) {
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: id,
                sku: sku,
                name: nom,
                unit: 'u',
                pricingMode: 'fixe',
              ),
            );
      }
      await afficher(tester);

      String texte(String cle) =>
          tester.widget<Text>(find.byKey(Key(cle))).data!;
      expect([for (var i = 0; i < 4; i++) texte('designation-$i')], [
        'Aliment ponte 25kg',
        'bâche agricole',
        'Œufs de table (plateau)',
        'Zinc oxyde 1kg',
      ]);
      expect(texte('code-0'), 'ALI-001');
    });

    /// Ticket U9 — `rtrim(rtrim(number_format($stock, 2, '.', ''), '0'), '.')` : « 12.5 », jamais « 12.50 ».
    testWidgets('U9 — la quantité en stock suit le format du Blade', (
      tester,
    ) async {
      await (db.update(db.products)..where((t) => t.id.equals(provende)))
          .write(const ProductsCompanion(stockQty: Value(12.5)));
      await afficher(tester);

      expect(tester.widget<Text>(find.byKey(const Key('stock-0'))).data,
          '12.5 sac');
      expect(tester.widget<Text>(find.byKey(const Key('stock-1'))).data,
          '8 plateau');
    });

    /// Ticket U9 — le filtre « Catégorie » du web porte sur les catégories ACTIVES, par identifiant.
    testWidgets('U9 — le filtre de catégorie ne propose que les catégories actives', (
      tester,
    ) async {
      await db
          .into(db.productCategories)
          .insert(
            ProductCategoriesCompanion.insert(
              id: 'ffffffff-0000-4000-8000-ffffffffffff',
              label: 'Archivée',
              isActive: const Value(false),
            ),
          );
      await afficher(tester);

      await tester.tap(find.byKey(const Key('stock-categorie')));
      await tester.pumpAndSettle();
      expect(find.text('Archivée'), findsNothing);
      await tester.tap(find.text('Aliments').last);
      await tester.pumpAndSettle();

      expect(find.text('Aliment ponte 25kg'), findsOneWidget);
      expect(find.text('Œufs de table (plateau)'), findsNothing);
    });

    testWidgets('le tableau porte les huit colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      // ⚠️⚠️ SANS ACCENT — c'est ce qu'écrit `gestion-stocks.html` dans ses
      // `<th>`, alors que ses propres modales accentuent. Incohérence du
      // prototype, reproduite et signalée, jamais harmonisée en silence.
      for (final colonne in [
        'CODE',
        'DESIGNATION',
        'CATEGORIE',
        'STOCK',
        'PMP UNIT.',
        'VALEUR',
        'URGENCE',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    /// 🔴→✅ Ticket U9 — les deux pastilles du Blade : « Critique » et « Normal » (ni « Sous seuil » ni « Négatif »).
    testWidgets("l'urgence signale le produit sous seuil", (tester) async {
      await afficher(tester);

      expect(find.text('Critique'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Sous seuil'), findsNothing);
      // Les œufs (8 pour un seuil de 30) sont la deuxième ligne (tri par nom).
      expect(
        find.descendant(
          of: find.byKey(const Key('urgence-1')),
          matching: find.text('Critique'),
        ),
        findsOneWidget,
      );
    });

    /// ⚠️ Un stock négatif n'est pas une fraude : c'est une ENTRÉE NON SAISIE,
    /// régularisable par un ajustement. Le serveur pose la même lecture.
    testWidgets('⚠️ un stock négatif est signalé, pas masqué', (tester) async {
      await (db.update(db.products)..where((t) => t.id.equals(oeufs))).write(
        const ProductsCompanion(stockQty: Value(-3)),
      );

      await afficher(tester);

      // Ticket U9 — comme le Blade : la cellule Stock en rouge gras et la mention « Entrée non saisie », jamais une
      // pastille « Négatif » (l'urgence reste celle du seuil).
      expect(find.text('Négatif'), findsNothing);
      expect(find.byKey(const Key('entree-non-saisie-1')), findsOneWidget);
      expect(find.text('ENTRÉE NON SAISIE'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('stock-1'))).data,
        '-3 plateau',
      );
    });

    testWidgets('la recherche filtre par nom et par code', (tester) async {
      await afficher(tester);

      await tester.enterText(
        find.byKey(const Key('stock-recherche')),
        'ALI-001',
      );
      await tester.pumpAndSettle();

      expect(find.text('Aliment ponte 25kg'), findsOneWidget);
      expect(find.text('Œufs de table (plateau)'), findsNothing);
    });

    // ── Onglet Ajustement ───────────────────────────────────────────────────

    testWidgets('⚠️ le stock théorique accompagne le produit choisi', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Ajustement / Correction');

      // ⚠️ Le libellé porte le théorique, comme dans la maquette : l'opérateur
      // compare sans changer d'écran.
      expect(find.textContaining('Théorique : 45'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const Key('adj-theorique')),
          matching: find.text('45'),
        ),
        findsOneWidget,
      );
    });

    testWidgets("l'écart se calcule à la saisie", (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'Ajustement / Correction');

      await tester.enterText(find.byKey(const Key('adj-physique')), '40');
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('adj-ecart'))).data,
        '-5',
      );
    });

    testWidgets("un excédent s'affiche avec son signe", (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'Ajustement / Correction');

      await tester.enterText(find.byKey(const Key('adj-physique')), '52');
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('adj-ecart'))).data,
        '+7',
      );
    });

    testWidgets('les huit motifs de la maquette sont proposés', (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'Ajustement / Correction');

      await tester.tap(find.byKey(const Key('adj-motif')));
      await tester.pumpAndSettle();

      for (final motif in StocksRepository.motifs) {
        expect(find.text(motif), findsWidgets, reason: motif);
      }
    });

    testWidgets("sans motif, l'ajustement est refusé avec sa raison", (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Ajustement / Correction');

      await tester.enterText(find.byKey(const Key('adj-physique')), '40');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adj-valider')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adj-erreur')), findsOneWidget);
      expect(await db.select(db.stockAdjustments).get(), isEmpty);
    });

    testWidgets("l'ajustement validé apparaît au journal", (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'Ajustement / Correction');

      await tester.enterText(find.byKey(const Key('adj-physique')), '40');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adj-motif')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vol / Disparition').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adj-valider')));
      await tester.pumpAndSettle();

      await ouvrir(tester, 'Journal des Mouvements');

      expect(find.byKey(const Key('mouvement-0')), findsOneWidget);
      expect(find.text('Sortie'), findsOneWidget);
      // Ticket U9 — motif du Blade : `referenceLabel('inventaire')` (« Inventaire ») — motif ; quantité signée.
      expect(find.text('Inventaire — Vol / Disparition'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('quantite-mouvement-0'))).data,
        '-5',
      );
    });

    // ── Onglet Journal ──────────────────────────────────────────────────────

    /// 🔴→✅ Ticket U9 — le journal est celui de la FERME : les mouvements descendus du serveur (ventes, achats,
    /// production, ajustements du web), plus les ajustements de ce poste en attente d'envoi.
    testWidgets('U9 — le journal montre le grand livre de la ferme et les saisies en attente', (
      tester,
    ) async {
      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: '11111111-0000-4000-8000-111111111111',
              productId: oeufs,
              type: 'sortie',
              quantity: 2.5,
              referenceType: 'sale',
              referenceId: const Value('abcdef12-3456-4789-8abc-def123456789'),
              movementDate: DateTime(2026, 10, 3, 9, 15),
            ),
          );
      await depot.enregistrerEcart(
        productId: provende,
        stockPhysique: 40,
        motif: 'Casse de matériel',
      );
      await afficher(tester);
      await ouvrir(tester, 'Journal des Mouvements');

      String texte(String cle) =>
          tester.widget<Text>(find.byKey(Key(cle))).data!;
      // Le plus récent d'abord : l'ajustement en attente (daté de maintenant), puis la vente du 3.
      expect(texte('motif-mouvement-0'), 'Inventaire — Casse de matériel');
      expect(texte('quantite-mouvement-0'), '-5');
      expect(texte('motif-mouvement-1'), 'Vente');
      expect(texte('quantite-mouvement-1'), '-2.5');
      expect(texte('reference-mouvement-1'), 'ABCDEF12');
      expect(find.text('03/10/2026 09:15'), findsOneWidget);
      expect(find.byKey(const Key('mouvement-2')), findsNothing);
    });

    testWidgets('le journal porte les sept colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Journal des Mouvements');

      for (final colonne in [
        'DATE / HEURE',
        'REFERENCE',
        'PRODUIT',
        'TYPE',
        'MOTIF',
        'QUANTITE',
        'VALEUR',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('sans ajustement, le journal le dit', (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'Journal des Mouvements');

      expect(
        find.text('Aucun mouvement enregistré pour le moment.'),
        findsOneWidget,
      );
    });
  });
}
