import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/achats/achats_commandes_screen.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:agrierp/features/stocks/produits_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket AC-2 — LES BOUTONS « + » DE L'ACHAT (`EnregistrerAchat::saveNewSupplier` / `saveNewProduct`).
///
/// Le fournisseur (raison sociale, téléphone) et le produit (nom, catégorie, unité) se créent sans quitter l'achat, EN LOCAL
/// (`pending`), par les dépôts propriétaires — puis la fiche créée est sélectionnée.
void main() {
  late AppDatabase db;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.productCategories).insert(ProductCategoriesCompanion.insert(id: uuid('cat1'), label: 'Aliments'));
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: uuid('f0'), name: 'Fournisseur existant', category: const Value('Aliments')));
  });
  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester, {bool avecProduits = true}) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(ToastAgri.toutRetirer);
    await tester.pumpWidget(
      MaterialApp(
        home: AchatsCommandesScreen(
          depot: AchatsRepository(database: db, identifiantPoste: 'poste-test'),
          depotFournisseurs: FournisseursRepository(database: db),
          depotProduits: avecProduits ? ProduitsRepository(database: db) : null,
          maintenant: () => DateTime(2026, 10, 28, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ « + » fournisseur : les deux champs du web sont obligatoires, la fiche est écrite pending avec « Autre » et sélectionnée', (tester) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('ajouter-fournisseur')));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau Fournisseur'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rapide-fournisseur-enregistrer')));
    await tester.pumpAndSettle();
    expect(find.text('Le champ raison sociale est obligatoire.'), findsOneWidget);
    expect(find.text('Le champ téléphone est obligatoire.'), findsOneWidget);
    expect((await db.select(db.suppliers).get()).length, 1, reason: 'rien d\'écrit');

    await tester.enterText(find.byKey(const Key('rapide-fournisseur-nom')), 'Provenderie du Plateau');
    await tester.enterText(find.byKey(const Key('rapide-fournisseur-telephone')), '+229 97 00 00 00');
    await tester.tap(find.byKey(const Key('rapide-fournisseur-enregistrer')));
    await tester.pumpAndSettle();
    await tester.pump(ToastAgri.duree + const Duration(seconds: 1));

    final cree = (await db.select(db.suppliers).get()).firstWhere((f) => f.name == 'Provenderie du Plateau');
    expect(cree.syncStatus, SyncStatus.pending);
    expect(cree.category, 'Autre');
    expect(cree.phone, '+229 97 00 00 00');
    expect(find.text('Provenderie du Plateau'), findsWidgets, reason: 'la fiche créée est sélectionnée dans la liste');
  });

  testWidgets('⚠️ « + » produit : nom, catégorie et unité (« u » par défaut) ; fourchette à zéro, pending, sélectionné avec un P.U. de 0', (tester) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('ajouter-produit')));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau Produit'), findsOneWidget);
    expect(find.text('La tarification (Fourchette/Sur devis) se complète ensuite depuis le Catalogue Produits.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('rapide-produit-unite'))).controller!.text, 'u');

    await tester.tap(find.byKey(const Key('rapide-produit-enregistrer')));
    await tester.pumpAndSettle();
    expect(find.text('Le champ nom du produit est obligatoire.'), findsOneWidget);
    expect(find.text('Le champ catégorie est obligatoire.'), findsOneWidget);
    expect(await db.select(db.products).get(), isEmpty);

    await tester.enterText(find.byKey(const Key('rapide-produit-nom')), 'Maïs concassé');
    await tester.tap(find.byKey(const Key('rapide-produit-categorie')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aliments').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rapide-produit-unite')), 'sac');
    await tester.tap(find.byKey(const Key('rapide-produit-enregistrer')));
    await tester.pumpAndSettle();
    await tester.pump(ToastAgri.duree + const Duration(seconds: 1));

    final p = (await db.select(db.products).get()).single;
    expect(p.name, 'Maïs concassé');
    expect(p.unit, 'sac');
    expect(p.categoryId, uuid('cat1'));
    expect(p.pricingMode, 'fourchette');
    expect((p.priceMin, p.priceMax, p.tvaRate, p.stockQty, p.alertThreshold), (0.0, 0.0, 0.0, 0.0, 0.0));
    expect(p.syncStatus, SyncStatus.pending);
    expect(tester.widget<TextField>(find.byKey(const Key('champ-prix-unitaire'))).controller!.text, '0');
    expect(find.text('Maïs concassé'), findsWidgets);
  });

  testWidgets('sans dépôt des produits, le bouton « + » du produit n\'est pas offert (le fournisseur l\'est)', (tester) async {
    await afficher(tester, avecProduits: false);

    expect(find.byKey(const Key('ajouter-produit')), findsNothing);
    expect(find.byKey(const Key('ajouter-fournisseur')), findsOneWidget);
  });
}
