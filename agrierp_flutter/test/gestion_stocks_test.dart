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
/// ⚠️⚠️ **TOUTE LA VALORISATION EST HORS DE PORTÉE.** Le PMP se calcule côté
/// serveur par moyenne pondérée des lignes d'achat ; `purchase_lines` ne
/// descend pas et `products` ne porte aucune colonne de coût. L'estimer depuis
/// le prix de VENTE gonflerait l'actif.
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

    testWidgets('⚠️⚠️ la valorisation dit pourquoi elle est absente', (
      tester,
    ) async {
      await afficher(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-Valorisation Stocks')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      expect(find.text('Prix de revient absent du catalogue'), findsOneWidget);
    });

    testWidgets('les alertes de seuil comptent les produits sous leur seuil', (
      tester,
    ) async {
      await afficher(tester);

      // Œufs : 8 pour un seuil de 30. La provende, elle, est à 45 pour 15.
      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-Alertes de Seuil')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
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

    testWidgets("l'urgence signale le produit sous seuil", (tester) async {
      await afficher(tester);

      expect(find.text('Sous seuil'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
    });

    /// ⚠️ Un stock négatif n'est pas une fraude : c'est une ENTRÉE NON SAISIE,
    /// régularisable par un ajustement. Le serveur pose la même lecture.
    testWidgets('⚠️ un stock négatif est signalé, pas masqué', (tester) async {
      await (db.update(db.products)..where((t) => t.id.equals(oeufs))).write(
        const ProductsCompanion(stockQty: Value(-3)),
      );

      await afficher(tester);

      expect(find.text('Négatif'), findsOneWidget);
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
        find.descendant(
          of: find.byKey(const Key('adj-ecart')),
          matching: find.text('-5'),
        ),
        findsOneWidget,
      );
    });

    testWidgets("un excédent s'affiche avec son signe", (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'Ajustement / Correction');

      await tester.enterText(find.byKey(const Key('adj-physique')), '52');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('adj-ecart')),
          matching: find.text('+7'),
        ),
        findsOneWidget,
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
      expect(find.text('Vol / Disparition'), findsOneWidget);
    });

    // ── Onglet Journal ──────────────────────────────────────────────────────

    /// ⚠️⚠️ Présenter ces seules lignes comme « le journal » ferait croire à
    /// un magasin sans mouvement.
    testWidgets('⚠️⚠️ le journal dit qu il ne voit que ce poste', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Journal des Mouvements');

      expect(
        find.textContaining("Ajustements d'inventaire saisis sur ce poste"),
        findsOneWidget,
      );
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
        find.text('— Aucun ajustement saisi sur ce poste —'),
        findsOneWidget,
      );
    });
  });
}
