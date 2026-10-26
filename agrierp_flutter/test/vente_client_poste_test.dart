import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/caisse_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket VTE-1 — « Je n'arrive pas à enregistrer de ventes » : le client à la caisse du poste.
///
/// La règle (web = maître, `PosInterface::validateSale`) :
///  1. une vente au COMPTANT s'enregistre TOUJOURS, sans client (« Client Anonyme ») ;
///  2. avec un client, créé au poste (pas encore au serveur) ou pas encore tiré : la vente s'enregistre avec son
///     `customer_id`, et part APRÈS le client dans le même envoi ;
///  3. une vente à CRÉDIT exige un client connu de ce poste : refus MOTIVÉ, panier conservé, client créable à la volée.
///  4. Aucun échec silencieux : une erreur inattendue s'affiche aussi.
class _Casse extends CaisseRepository {
  _Casse({required super.database, required super.deviceId});

  @override
  Future<Sale> enregistrerVente({
    required List<LignePanier> panier,
    required String modePaiement,
    String? clientId,
    double remise = 0,
    double? especesRecues,
    DateTime? dateVente,
  }) async => throw StateError('Le disque du poste est plein : écriture impossible.');
}

void main() {
  late AppDatabase db;
  late CaisseRepository depot;

  const client = 'cccccccc-1111-4111-8111-cccccccccccc';
  late Product oeufs;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = CaisseRepository(database: db, deviceId: 'poste-test', maintenant: () => DateTime(2026, 10, 26, 10));
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb',
        sku: 'OEU-001',
        name: 'Oeufs',
        unit: 'u',
        pricingMode: 'fourchette',
        priceMin: const Value(1000),
        priceMax: const Value(8000),
        stockQty: const Value(50),
      ),
    );
    oeufs = await db.select(db.products).getSingle();
  });

  tearDown(() async => db.close());

  Future<void> poserClient({SyncStatus statut = SyncStatus.synced, String nom = 'GBAGUIDI Solange'}) => db
      .into(db.customers)
      .insert(CustomersCompanion.insert(id: client, name: nom, syncStatus: Value(statut)));

  List<LignePanier> panier() => [LignePanier(produit: oeufs, quantite: 2, montant: 6000)];

  group('dépôt', () {
    test('une vente au comptant s\'enregistre sans client', () async {
      final vente = await depot.enregistrerVente(panier: panier(), modePaiement: 'especes');

      expect(vente.customerId, isNull);
      expect(vente.syncStatus, SyncStatus.pending);
    });

    test('⚠️ une vente au comptant avec un client PAS ENCORE SYNCHRONISÉ (créé au poste) s\'enregistre avec son client', () async {
      await poserClient(statut: SyncStatus.pending);

      final vente = await depot.enregistrerVente(panier: panier(), modePaiement: 'mobile_money', clientId: client);

      expect(vente.customerId, client);
      expect(vente.customerName, 'GBAGUIDI Solange', reason: 'la vente reste nommée dans l\'historique, même avant le premier envoi');
      expect(vente.syncStatus, SyncStatus.pending);
    });

    test('un client inconnu de ce poste n\'empêche pas une vente au comptant (le serveur jugera)', () async {
      final vente = await depot.enregistrerVente(panier: panier(), modePaiement: 'especes', clientId: client);

      expect(vente.customerId, client);
      expect(vente.customerName, isNull);
    });

    test('⚠️ une vente à crédit SANS client est refusée avec son motif, et ne laisse aucune trace', () async {
      await expectLater(
        depot.enregistrerVente(panier: panier(), modePaiement: 'credit'),
        throwsA(
          isA<VenteRefusee>().having(
            (e) => e.message,
            'message',
            'Une vente à crédit exige un client : choisissez-le dans la liste ou créez-le avec le bouton « + ».',
          ),
        ),
      );

      expect(await db.select(db.sales).get(), isEmpty);
      expect(await db.select(db.saleLines).get(), isEmpty);
      expect((await db.select(db.products).getSingle()).stockQty, 50, reason: 'le stock n\'a pas bougé');
    });

    test('une vente à crédit avec un client inconnu de ce poste est refusée', () async {
      await expectLater(
        depot.enregistrerVente(panier: panier(), modePaiement: 'credit', clientId: client),
        throwsA(
          isA<VenteRefusee>().having(
            (e) => e.message,
            'message',
            'Une vente à crédit exige un client connu de ce poste : le client choisi est introuvable. Lancez une synchronisation ou créez-le avec le bouton « + ».',
          ),
        ),
      );
      expect(await db.select(db.sales).get(), isEmpty);
    });

    test('une vente à crédit avec un client connu (même créé au poste) s\'enregistre', () async {
      await poserClient(statut: SyncStatus.pending);

      final vente = await depot.enregistrerVente(panier: panier(), modePaiement: 'credit', clientId: client);

      expect([vente.paymentMode, vente.customerId, vente.total], ['credit', client, 6000]);
    });

    test('clients() ne propose que les clients actifs, par nom', () async {
      await poserClient(nom: 'ZANNOU');
      await db.into(db.customers).insert(CustomersCompanion.insert(id: 'cccccccc-2222-4222-8222-cccccccccccc', name: 'AMOUSSOU'));
      await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'cccccccc-3333-4333-8333-cccccccccccc', name: 'ARCHIVÉ', isActive: const Value(false)),
      );

      expect((await depot.clients()).map((c) => c.name), ['AMOUSSOU', 'ZANNOU']);
    });

    test('creerClient crée la fiche EN ATTENTE d\'envoi (le serveur la valide à la synchronisation)', () async {
      final c = await depot.creerClient(nom: ' Restaurant LA TERRASSE ', telephone: '97 20 20 20');

      expect([c.name, c.phone, c.syncStatus], ['Restaurant LA TERRASSE', '97 20 20 20', SyncStatus.pending]);
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester, {CaisseRepository? avec}) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: CaisseScreen(depot: avec ?? depot)));
      await tester.pumpAndSettle();
    }

    Future<void> mettreAuPanier(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('produit-OEU-001')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('saisie-quantite')), '2');
      await tester.enterText(find.byKey(const Key('saisie-montant')), '6000');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmer-ligne')));
      await tester.pumpAndSettle();
    }

    Future<void> choisirMode(WidgetTester tester, String libelle) async {
      await tester.ensureVisible(find.byKey(const Key('mode-reglement')));
      await tester.tap(find.byKey(const Key('mode-reglement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(libelle).last);
      await tester.pumpAndSettle();
    }

    Future<void> valider(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('valider-vente')));
      await tester.tap(find.byKey(const Key('valider-vente')));
      await tester.pumpAndSettle();
    }

    testWidgets('le champ client est ACTIF et propose « Client Anonyme » puis les clients de ce poste', (tester) async {
      await poserClient();
      await afficher(tester);

      final champ = tester.widget<DropdownButton<String?>>(find.byKey(const Key('client-vente')));
      expect(champ.onChanged, isNotNull, reason: 'le champ n\'est plus désactivé');
      expect(find.text('Client Anonyme'), findsOneWidget);
      expect(find.textContaining('Fichier client non synchronisé'), findsNothing);

      await tester.tap(find.byKey(const Key('client-vente')));
      await tester.pumpAndSettle();
      expect(find.text('GBAGUIDI Solange'), findsOneWidget);
    });

    testWidgets('une vente au comptant sans client s\'enregistre', (tester) async {
      await afficher(tester);
      await mettreAuPanier(tester);
      await valider(tester);

      expect(find.byKey(const Key('modale-vente-enregistree')), findsOneWidget);
      expect((await db.select(db.sales).getSingle()).customerId, isNull);
    });

    testWidgets('⚠️ une vente avec un client créé au poste (pas encore au serveur) s\'enregistre avec lui', (tester) async {
      await poserClient(statut: SyncStatus.pending);
      await afficher(tester);
      await tester.tap(find.byKey(const Key('client-vente')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GBAGUIDI Solange').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('client-vente-note')), findsOneWidget, reason: 'le caissier est prévenu : ce client partira avec la vente');

      await mettreAuPanier(tester);
      await valider(tester);

      expect((await db.select(db.sales).getSingle()).customerId, client);
    });

    testWidgets('⚠️ une vente à crédit sans client : message clair sous le champ ET en bandeau, panier conservé', (tester) async {
      await afficher(tester);
      await mettreAuPanier(tester);
      await choisirMode(tester, 'Crédit / À terme');
      await valider(tester);

      const motif = 'Une vente à crédit exige un client : choisissez-le dans la liste ou créez-le avec le bouton « + ».';
      expect(find.byKey(const Key('client-vente-erreur')), findsOneWidget);
      expect(find.text(motif), findsNWidgets(2), reason: 'sous le champ client et dans le bandeau');
      expect(await db.select(db.sales).get(), isEmpty);
      expect(tester.widget<Text>(find.byKey(const Key('compteur-panier'))).data, '1', reason: 'le panier est conservé');
    });

    testWidgets('⚠️ le client se crée À LA VOLÉE depuis la caisse, puis la vente à crédit passe', (tester) async {
      await afficher(tester);
      await mettreAuPanier(tester);
      await choisirMode(tester, 'Crédit / À terme');

      await tester.ensureVisible(find.byKey(const Key('ajouter-client')));
      await tester.tap(find.byKey(const Key('ajouter-client')));
      await tester.pumpAndSettle();
      expect(find.text('Nouveau Client'), findsOneWidget);

      // Nom obligatoire : le formulaire dit pourquoi il ne passe pas.
      await tester.tap(find.byKey(const Key('enregistrer-client')));
      await tester.pumpAndSettle();
      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('client-nom')), 'Restaurant LA TERRASSE');
      await tester.enterText(find.byKey(const Key('client-telephone')), '97202020');
      await tester.tap(find.byKey(const Key('enregistrer-client')));
      await tester.pumpAndSettle();

      final nouveau = await (db.select(db.customers)..where((c) => c.name.equals('Restaurant LA TERRASSE'))).getSingle();
      expect(nouveau.syncStatus, SyncStatus.pending);

      await valider(tester);

      final vente = await db.select(db.sales).getSingle();
      expect([vente.paymentMode, vente.customerId, vente.customerName], ['credit', nouveau.id, 'Restaurant LA TERRASSE']);
    });

    testWidgets('⚠️ aucun blocage silencieux : une erreur inattendue est dite au caissier', (tester) async {
      await afficher(tester, avec: _Casse(database: db, deviceId: 'poste-test'));
      await mettreAuPanier(tester);
      await valider(tester);

      expect(find.textContaining('Vente NON enregistrée'), findsOneWidget);
      expect(find.textContaining('Le disque du poste est plein'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('compteur-panier'))).data, '1', reason: 'le panier est conservé');
      expect(tester.widget<FilledButton>(find.byKey(const Key('valider-vente'))).onPressed, isNotNull, reason: 'le bouton se libère');
    });
  });
}
