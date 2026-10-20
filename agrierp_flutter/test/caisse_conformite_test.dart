import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/caisse_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chemins_depot.dart';

/// Ticket F0.21 — CONFORMITÉ DE LA CAISSE À `pos-interface.html`.
///
/// ⚠️⚠️ Cet écran a été construit **avant** la règle « la maquette est la
/// référence de mise en page ». La fiche Lapins, auditée sous cette règle,
/// portait trois écarts réels ; la caisse n'avait jamais été relue.
///
/// Ces tests verrouillent ce que l'audit a remis en place.
void main() {
  late AppDatabase db;
  late CaisseRepository depot;

  const catAvi = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const catProvende = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = CaisseRepository(database: db, deviceId: 'poste-test');

    for (final (id, libelle) in [
      (catAvi, 'Aviculture'),
      (catProvende, 'Provendes'),
    ]) {
      await db
          .into(db.productCategories)
          .insert(ProductCategoriesCompanion.insert(id: id, label: libelle));
    }

    // Un produit par catégorie : c'est ce qui rend le filtre observable.
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'pppppppp-1111-4111-8111-pppppppppppp',
            sku: 'OEUF-PLT',
            name: 'Œufs de table (plateau)',
            categoryId: const Value(catAvi),
            unit: 'plateau',
            pricingMode: 'fixe',
            stockQty: const Value(40),
          ),
        );

    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'qqqqqqqq-1111-4111-8111-qqqqqqqqqqqq',
            sku: 'ALI-001',
            name: 'Provende ponte',
            categoryId: const Value(catProvende),
            unit: 'sac',
            pricingMode: 'fixe',
            stockQty: const Value(12),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: CaisseScreen(depot: depot)));
    await tester.pumpAndSettle();
  }

  // ── Les filtres de catégorie ───────────────────────────────────────────

  testWidgets(
    "⚠️⚠️ les filtres de catégorie existent — ils étaient annoncés, jamais construits",
    (tester) async {
      await afficher(tester);

      expect(
        find.text('Tous'),
        findsOneWidget,
        reason: 'le premier filtre de la maquette',
      );
      expect(find.text('Aviculture'), findsOneWidget);
      expect(find.text('Provendes'), findsOneWidget);
    },
  );

  testWidgets('choisir une catégorie restreint réellement la grille', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Œufs de table (plateau)'), findsOneWidget);
    expect(find.text('Provende ponte'), findsOneWidget);

    await tester.tap(find.byKey(const Key('categorie-$catAvi')));
    await tester.pumpAndSettle();

    expect(find.text('Œufs de table (plateau)'), findsOneWidget);
    expect(
      find.text('Provende ponte'),
      findsNothing,
      reason: 'un filtre qui ne filtre pas est pire que pas de filtre',
    );
  });

  testWidgets('« Tous » rétablit le catalogue entier', (tester) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('categorie-$catAvi')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('categorie-tous')));
    await tester.pumpAndSettle();

    expect(find.text('Provende ponte'), findsOneWidget);
  });

  testWidgets('⚠️ recherche et catégorie se cumulent, comme dans la maquette', (
    tester,
  ) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('categorie-$catProvende')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('recherche-produit')), 'Œufs');
    await tester.pumpAndSettle();

    // « Œufs » existe, mais pas dans la catégorie Provendes.
    expect(find.text('Œufs de table (plateau)'), findsNothing);
  });

  testWidgets(
    "⚠️ les catégories viennent du serveur : aucune n'est codée en dur",
    (tester) async {
      await db.delete(db.productCategories).go();

      await afficher(tester);

      // Sans référentiel, aucune puce — surtout pas les sept intitulés que la
      // maquette porte en dur dans son HTML.
      expect(find.text('Aviculture'), findsNothing);
      expect(find.text('Héliciculture'), findsNothing);
      expect(find.text('Tous'), findsNothing);
    },
  );

  // ── Les libellés de la maquette ────────────────────────────────────────

  testWidgets("⚠️ le bloc d'ajout porte les libellés de la maquette", (
    tester,
  ) async {
    await afficher(tester);

    // Une provende n'exige pas de bande : le dialogue s'ouvre directement.
    await tester.tap(find.text('Provende ponte'));
    await tester.pumpAndSettle();

    expect(find.text('Vente à la Pièce'), findsOneWidget);
    expect(find.text('Nombre de sujets / Quantité'), findsOneWidget);
    expect(find.text('Montant Global de la Vente (FCFA)'), findsOneWidget);
    expect(find.text('Ajouter au panier'), findsOneWidget);
  });

  // ── F0.89 : le champ « Date de la vente », écart ASSUMÉ ─────────────────

  test(
    "⚠️ F0.89 — la maquette n'a AUCUN champ de date : le champ du poste est un écart assumé",
    () {
      final maquette = File(
        '$dossierPrototype/pos-interface.html',
      );
      if (!maquette.existsSync()) {
        markTestSkipped('SAUT : maquette absente de ce poste.');
        return;
      }
      final html = maquette.readAsStringSync();

      // Si la maquette gagne un jour un champ de date, cet écart n'en est plus un : il faudra
      // alors porter SON libellé et SA place, et retirer la mention « écart assumé ».
      expect(html.contains('type="date"'), isFalse);
      expect(html.toLowerCase().contains('date de la vente'), isFalse);

      // L'écart est DOCUMENTÉ dans l'écran (docblock, écart n° 4), avec sa décision.
      final source = File(
        'lib/features/ventes/caisse_screen.dart',
      ).readAsStringSync();
      expect(source, contains('Champ « Date de la vente » AJOUTÉ au panier'));
      expect(source, contains('Décision CLIENT du 14/10/2026'));
    },
  );

  testWidgets(
    '⚠️ F0.89 — un SEUL champ de date, au panier, jamais dans « Vente à la Pièce »',
    (tester) async {
      await afficher(tester);

      expect(find.text('DATE DE LA VENTE'), findsOneWidget);
      expect(find.byKey(const Key('date-vente')), findsOneWidget);

      await tester.tap(find.text('Provende ponte'));
      await tester.pumpAndSettle();

      expect(find.text('Vente à la Pièce'), findsOneWidget);
      // Le champ du panier est derrière la modale ; la modale elle-même n'en porte aucun.
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byKey(const Key('date-vente')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(DatePickerDialog),
        ),
        findsNothing,
      );
    },
  );

  // ── La confirmation de vente ───────────────────────────────────────────

  testWidgets(
    '⚠️⚠️ une vente validée ouvre la modale « Vente Enregistrée » avec sa référence',
    (tester) async {
      await afficher(tester);

      await tester.tap(find.text('Provende ponte'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre de sujets / Quantité'),
        '2',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Montant Global de la Vente (FCFA)'),
        '36000',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ajouter au panier'));
      await tester.pumpAndSettle();

      final valider = find.text('Valider la Vente');
      await tester.ensureVisible(valider);
      await tester.tap(valider);
      await tester.pumpAndSettle();

      // ⚠️ Une modale, pas un bandeau de trois secondes : le caissier qui se
      // retourne vers son client doit encore pouvoir lire la référence.
      expect(find.byKey(const Key('modale-vente-enregistree')), findsOneWidget);
      expect(find.text('Vente Enregistrée'), findsOneWidget);
      expect(find.byKey(const Key('reference-vente')), findsOneWidget);
      expect(find.text('Nouvelle Vente'), findsOneWidget);

      // ⚠️ Et la facture PDF est dite absente plutôt qu'offerte en trompe-l'œil.
      expect(find.textContaining('produite par le serveur'), findsOneWidget);
      expect(find.text('Télécharger la Facture'), findsNothing);

      final ventes = await db.select(db.sales).get();
      expect(ventes, hasLength(1));
    },
  );
}
