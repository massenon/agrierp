import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/stocks/catalogue_produits_screen.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.39 — CATALOGUE PRODUITS (`catalogue-produits.html`).
///
/// ⚠️⚠️ **LE CATALOGUE EST EN LECTURE SEULE, ET CE N'EST PAS UN MANQUE.**
/// `products` et `product_categories` sont des **référentiels** : le point
/// d'entrée de synchronisation les compte dans `referentiels_ignored` et
/// **ignore tout envoi** les concernant. Un produit créé au poste serait jeté
/// sans un mot, puis effacé par le tirage suivant.
///
/// ⚠️⚠️ **LES PASTILLES DE CATÉGORIE VIENNENT DES DONNÉES REÇUES.** La maquette
/// en code six en dur et **oublie « Aliments » et « Médicaments »** — neuf
/// produits réels, dont toute la provende, seraient restés hors de tout
/// filtre. Recopier la liste aurait reproduit l'oubli.
void main() {
  late AppDatabase db;
  late StocksRepository depot;

  const catAliments = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
  const catAviculture = 'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = StocksRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.productCategories)
        .insert(
          ProductCategoriesCompanion.insert(id: catAliments, label: 'Aliments'),
        );
    await db
        .into(db.productCategories)
        .insert(
          ProductCategoriesCompanion.insert(
            id: catAviculture,
            label: 'Aviculture',
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> produit(
    String id,
    String sku,
    String nom, {
    String? categorie,
    double stock = 10,
    double? seuil,
    String mode = 'fixe',
    double? prixMin,
    double? prixMax,
  }) => db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: id.padRight(36, '0').substring(0, 36),
          sku: sku,
          name: nom,
          categoryId: Value(categorie),
          unit: 'u',
          pricingMode: mode,
          priceMin: Value(prixMin),
          priceMax: Value(prixMax),
          stockQty: Value(stock),
          alertThreshold: Value(seuil),
        ),
      );

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(home: CatalogueProduitsScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-catalogue-$onglet')));
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ les deux onglets du hub sont là, dans son ordre', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Voir le Catalogue'), findsOneWidget);
    expect(find.text("Seuils d'Alerte"), findsOneWidget);
  });

  /// ⚠️⚠️ Le cœur du ticket : offrir la création donnerait une saisie effacée
  /// au tirage suivant.
  /// ⚠️⚠️ **LE NOMBRE DE CARTES, ONGLET PAR ONGLET** (ticket F0.54). Les deux
  /// onglets du hub sont deux pages distinctes de la maquette : le contrôle se
  /// fait donc page par page, sans arbitrage sur la répartition.
  testWidgets('⚠️⚠️ chaque onglet rend le nombre de cartes de sa page', (
    tester,
  ) async {
    await afficher(tester);

    expect(
      find.byType(CarteKpi),
      findsNWidgets(cartesAttendues('catalogue-view.html')),
      reason: 'Voir le Catalogue',
    );

    await ouvrir(tester, "Seuils d'Alerte");
    expect(
      find.byType(CarteKpi),
      findsNWidgets(cartesAttendues('seuils-alerte.html')),
      reason: "Seuils d'Alerte",
    );
  });

  testWidgets('⚠️⚠️ le catalogue annonce qu il est en consultation', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.byKey(const Key('catalogue-lecture-seule')), findsOneWidget);
    expect(
      find.textContaining('référentiel tenu par le serveur'),
      findsOneWidget,
    );

    final bouton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Nouveau Produit'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(bouton.onPressed, isNull);
  });

  /// ⚠️⚠️ La maquette code six pastilles en dur et oublie « Aliments ».
  testWidgets('⚠️⚠️ les pastilles suivent les catégories réellement reçues', (
    tester,
  ) async {
    await produit(
      'p1',
      'ALI-001',
      'Aliment ponte 25kg',
      categorie: catAliments,
    );
    await produit('p2', 'AVI-002', 'Œufs de table', categorie: catAviculture);

    await afficher(tester);

    expect(find.byKey(const Key('pastille-Tous')), findsOneWidget);
    expect(find.byKey(const Key('pastille-Aliments')), findsOneWidget);
    expect(find.byKey(const Key('pastille-Aviculture')), findsOneWidget);
  });

  testWidgets('une pastille restreint le catalogue', (tester) async {
    await produit(
      'p1',
      'ALI-001',
      'Aliment ponte 25kg',
      categorie: catAliments,
    );
    await produit('p2', 'AVI-002', 'Œufs de table', categorie: catAviculture);

    await afficher(tester);
    await tester.tap(find.byKey(const Key('pastille-Aliments')));
    await tester.pumpAndSettle();

    expect(find.text('Aliment ponte 25kg'), findsOneWidget);
    expect(find.text('Œufs de table'), findsNothing);
  });

  testWidgets('la recherche porte sur le nom et le SKU', (tester) async {
    await produit(
      'p1',
      'ALI-001',
      'Aliment ponte 25kg',
      categorie: catAliments,
    );
    await produit('p2', 'AVI-002', 'Œufs de table', categorie: catAviculture);

    await afficher(tester);
    await tester.enterText(
      find.byKey(const Key('catalogue-recherche')),
      'AVI-002',
    );
    await tester.pumpAndSettle();

    expect(find.text('Œufs de table'), findsOneWidget);
    expect(find.text('Aliment ponte 25kg'), findsNothing);
  });

  testWidgets('la bascule liste affiche les six colonnes de la maquette', (
    tester,
  ) async {
    await produit(
      'p1',
      'ALI-001',
      'Aliment ponte 25kg',
      categorie: catAliments,
    );

    await afficher(tester);
    await tester.tap(find.byKey(const Key('vue-liste')));
    await tester.pumpAndSettle();

    for (final colonne in [
      'SKU',
      'DÉSIGNATION',
      'CATÉGORIE',
      'STOCK',
      'TARIF',
      'ACTIONS',
    ]) {
      expect(find.text(colonne), findsOneWidget, reason: colonne);
    }
  });

  /// ⚠️⚠️ TROIS MODES DE TARIFICATION, PAS DEUX. Un produit **sur devis** n'a
  /// pas de prix : afficher « 0 F » le ferait vendre pour rien à la caisse.
  testWidgets('⚠️⚠️ un produit sur devis n affiche jamais un prix nul', (
    tester,
  ) async {
    await produit(
      'p1',
      'PRE-001',
      'Prestation labour',
      categorie: catAliments,
      mode: 'devis',
    );
    await produit(
      'p2',
      'CUN-001',
      'Lapin vivant',
      categorie: catAviculture,
      mode: 'fourchette',
      prixMin: 3000,
      prixMax: 4500,
    );

    await afficher(tester);

    expect(find.text('Sur devis'), findsOneWidget);
    expect(find.text('3000 – 4500 F'), findsOneWidget);
    expect(find.text('0 F'), findsNothing);
  });

  // ── Onglet Seuils d'Alerte ────────────────────────────────────────────────

  testWidgets('les deux KPI portent les libellés de la maquette', (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, "Seuils d'Alerte");

    expect(find.text('PRODUITS SOUS SEUIL'), findsOneWidget);
    expect(find.text('SEUILS CONFIGURÉS'), findsOneWidget);
  });

  testWidgets('le tableau des seuils porte les cinq colonnes de la maquette', (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, "Seuils d'Alerte");

    for (final colonne in [
      'PRODUIT',
      'STOCK ACTUEL',
      'SEUIL CONFIGURÉ',
      'STATUT',
      'ACTIONS',
    ]) {
      expect(find.text(colonne), findsOneWidget, reason: colonne);
    }
  });

  /// ⚠️⚠️ UN PRODUIT SANS SEUIL N'EST NI NORMAL NI CRITIQUE : il n'est pas
  /// surveillé. Le compter comme « normal » ferait croire à une veille qui
  /// n'existe pas.
  testWidgets(
    '⚠️⚠️ un produit sans seuil est hors surveillance, et c est dit',
    (tester) async {
      await produit(
        'p1',
        'ALI-001',
        'Aliment ponte 25kg',
        categorie: catAliments,
        stock: 5,
        seuil: 12,
      );
      await produit(
        'p2',
        'AVI-002',
        'Œufs de table',
        categorie: catAviculture,
        stock: 40,
      );

      await afficher(tester);
      await ouvrir(tester, "Seuils d'Alerte");

      // Un seul seuil configuré, un seul produit sous ce seuil.
      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-Seuils configurés')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('1 produit(s) sans seuil configuré'),
        findsOneWidget,
      );
      // Le produit non surveillé ne figure pas au tableau.
      expect(find.text('Œufs de table'), findsNothing);
    },
  );

  testWidgets('le statut distingue critique et normal', (tester) async {
    await produit(
      'p1',
      'ALI-001',
      'Aliment ponte 25kg',
      categorie: catAliments,
      stock: 5,
      seuil: 12,
    );
    await produit(
      'p2',
      'AVI-002',
      'Œufs de table',
      categorie: catAviculture,
      stock: 40,
      seuil: 30,
    );

    await afficher(tester);
    await ouvrir(tester, "Seuils d'Alerte");

    expect(find.text('Critique'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
  });

  testWidgets('le filtre de statut restreint le tableau', (tester) async {
    await produit(
      'p1',
      'ALI-001',
      'Aliment ponte 25kg',
      categorie: catAliments,
      stock: 5,
      seuil: 12,
    );
    await produit(
      'p2',
      'AVI-002',
      'Œufs de table',
      categorie: catAviculture,
      stock: 40,
      seuil: 30,
    );

    await afficher(tester);
    await ouvrir(tester, "Seuils d'Alerte");

    await tester.tap(find.byKey(const Key('filtre-statut-seuil')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Critique').last);
    await tester.pumpAndSettle();

    expect(find.text('Aliment ponte 25kg'), findsOneWidget);
    expect(find.text('Œufs de table'), findsNothing);
  });

  testWidgets('sans produit surveillé, le tableau le dit', (tester) async {
    await afficher(tester);
    await ouvrir(tester, "Seuils d'Alerte");

    expect(
      find.text('— Aucun produit surveillé pour ce statut —'),
      findsOneWidget,
    );
  });
}
