import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/caisse_screen.dart';
// Drift exporte `isNull` / `isNotNull` (expressions SQL) : masques ici pour
// laisser accessibles les matchers homonymes de `flutter_test`.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 0 Flutter — écran de caisse.
///
/// Le comportement vérifié ici est celui qui ne peut se perdre qu'à l'écran :
/// la bande DOIT être demandée avant d'ajouter un sujet vivant au panier, et
/// annuler cette désignation doit annuler l'ajout — sans quoi une ligne
/// partirait sans bande, échappant au contrôle sanitaire.
void main() {
  late AppDatabase db;
  late CaisseRepository depot;

  const bande = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const espece = 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = CaisseRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bande,
            code: 'AVI-2026-01',
            speciesId: espece,
            initialQuantity: const Value(50),
            currentQuantity: const Value(50),
          ),
        );

    // Un produit lié à une espèce (sujet vivant) et un produit qui ne l'est
    // pas (provende) : seul le premier exige une bande.
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'pppppppp-1111-4111-8111-pppppppppppp',
            sku: 'AVI-001',
            name: 'Poulet goliath',
            speciesId: const Value(espece),
            unit: 'u',
            pricingMode: 'fourchette',
            priceMin: const Value(3000),
            priceMax: const Value(4000),
            stockQty: const Value(50),
          ),
        );

    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'qqqqqqqq-1111-4111-8111-qqqqqqqqqqqq',
            sku: 'ALI-001',
            name: 'Aliment ponte 25kg',
            unit: 'sac',
            pricingMode: 'fixe',
            priceMin: const Value(6500),
            stockQty: const Value(20),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: CaisseScreen(depot: depot)));
    await tester.pumpAndSettle();
  }

  testWidgets('le catalogue local est affiche', (tester) async {
    await afficher(tester);

    expect(find.byKey(const Key('produit-AVI-001')), findsOneWidget);
    expect(find.byKey(const Key('produit-ALI-001')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('compteur-panier'))).data,
      '0',
    );
  });

  testWidgets('la recherche filtre la grille', (tester) async {
    await afficher(tester);

    await tester.enterText(find.byKey(const Key('recherche-produit')), 'ponte');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('produit-ALI-001')), findsOneWidget);
    expect(find.byKey(const Key('produit-AVI-001')), findsNothing);
  });

  /// ⚠️ LE COMPORTEMENT CENTRAL : un sujet vivant exige sa bande.
  testWidgets('un sujet vivant demande sa bande avant tout ajout', (
    tester,
  ) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('produit-AVI-001')));
    await tester.pumpAndSettle();

    expect(find.text('Bande source'), findsOneWidget);
    expect(find.byKey(const Key('bande-AVI-2026-01')), findsOneWidget);
  });

  /// ⚠️ ANNULER LA DÉSIGNATION ANNULE L'AJOUT : jamais de ligne sans bande
  /// pour un produit qui en exige une — elle échapperait au contrôle
  /// sanitaire et au rattachement du revenu.
  testWidgets('annuler la bande annule l ajout', (tester) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('produit-AVI-001')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('compteur-panier'))).data,
      '0',
    );
    expect(
      find.byKey(const Key('saisie-quantite')),
      findsNothing,
      reason: 'la saisie de quantite ne doit meme pas s ouvrir',
    );
  });

  /// Une provende n'est liée à aucune espèce : pas de bande demandée.
  testWidgets('une provende n exige aucune bande', (tester) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('produit-ALI-001')));
    await tester.pumpAndSettle();

    expect(find.text('Bande source'), findsNothing);
    expect(find.byKey(const Key('saisie-quantite')), findsOneWidget);
  });

  /// Parcours complet : bande, quantité, montant, panier, validation.
  testWidgets('une vente complete part en file de synchronisation', (
    tester,
  ) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('produit-AVI-001')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bande-AVI-2026-01')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('saisie-quantite')), '6');
    await tester.enterText(find.byKey(const Key('saisie-montant')), '21000');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmer-ligne')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('compteur-panier'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('total-a-payer'))).data,
      '21 000 FCFA',
    );

    await tester.tap(find.byKey(const Key('valider-vente')));
    await tester.pumpAndSettle();

    expect(await db.pendingCount(), greaterThanOrEqualTo(1));

    final vente = await db.select(db.sales).getSingle();
    expect(vente.total, 21000);

    final ligne = await db.select(db.saleLines).getSingle();
    expect(ligne.lotId, bande, reason: 'la bande designee est conservee');

    // Le panier est vidé : sans cela, un double appui revendrait le tout.
    expect(
      tester.widget<Text>(find.byKey(const Key('compteur-panier'))).data,
      '0',
    );
  });

  /// ⚠️⚠️ LE REFUS SANITAIRE EST MONTRÉ TEL QUEL, avec le code de la bande :
  /// le caissier doit pouvoir citer le motif à son responsable.
  testWidgets('une bande sous remanence est refusee a l ecran', (tester) async {
    await db
        .into(db.veterinaryWithdrawalPeriods)
        .insert(
          VeterinaryWithdrawalPeriodsCompanion.insert(
            id: 'rrrrrrrr-1111-4111-8111-rrrrrrrrrrrr',
            lotId: bande,
            productUsed: const Value('Antibiotique polyvalent'),
            endDate: DateTime.now().add(const Duration(days: 5)),
          ),
        );

    await afficher(tester);

    await tester.tap(find.byKey(const Key('produit-AVI-001')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bande-AVI-2026-01')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('saisie-quantite')), '2');
    await tester.enterText(find.byKey(const Key('saisie-montant')), '7000');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmer-ligne')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('valider-vente')));
    await tester.pumpAndSettle();

    expect(find.textContaining('rémanence'), findsOneWidget);
    expect(find.textContaining('AVI-2026-01'), findsWidgets);
    expect(await db.select(db.sales).get(), isEmpty);
  });

  /// La remise se répercute sur le total à payer.
  testWidgets('la remise diminue le total', (tester) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('produit-ALI-001')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('saisie-quantite')), '2');
    await tester.enterText(find.byKey(const Key('saisie-montant')), '13000');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmer-ligne')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('remise')), '1000');
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('total-a-payer'))).data,
      '12 000 FCFA',
    );
  });

  /// Ticket #47 (suite) — le panier tient en DEUX rangées de deux colonnes, comme le web :
  /// Sous-total + Remise sur une rangée, Total à Payer + Mode de Règlement sur la suivante ;
  /// et « Client » et « Date de la vente » ne se touchent pas.
  testWidgets('⚠️ le panier range Sous-total / Remise puis Total / Mode de règlement', (tester) async {
    await afficher(tester);

    // Le haut, pas le centre : la police des tests (Ahem) fait passer « Remise (FCFA) » sur deux lignes.
    double haut(Finder f) => tester.getRect(f).top;
    final sousTotal = find.text('Sous-total');
    final remise = find.text('Remise (FCFA)');
    final total = find.text('Total à Payer');
    final mode = find.byKey(const Key('mode-reglement'));

    expect((haut(sousTotal) - haut(remise)).abs(), lessThan(2), reason: 'Sous-total et Remise sur une même rangée');
    expect((tester.getRect(total).top - tester.getRect(mode).top).abs(), lessThan(30),
        reason: 'Total à Payer et Mode de Règlement sur une même rangée');
    expect(haut(total), greaterThan(haut(sousTotal)), reason: 'la rangée du total vient après celle du sous-total');
    expect(tester.getRect(sousTotal).right, lessThan(tester.getRect(remise).left));
    expect(tester.getRect(total).right, lessThan(tester.getRect(mode).left));

    final client = tester.getRect(find.byKey(const Key('client-vente')));
    final date = tester.getRect(find.byKey(const Key('date-vente')));
    expect(date.left - client.right, greaterThanOrEqualTo(8), reason: 'écart franc entre Client et Date');
  });

  /// Le bouton reste inerte tant que le panier est vide.
  testWidgets('on ne valide pas un panier vide', (tester) async {
    await afficher(tester);

    // La cle porte sur le bouton lui-meme : `FilledButton.icon` construit
    // bien un `FilledButton`, inutile de chercher un descendant.
    final bouton = tester.widget<FilledButton>(
      find.byKey(const Key('valider-vente')),
    );

    expect(bouton.onPressed, isNull);
  });
}
