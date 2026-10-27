import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/achats/achats_commandes_screen.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket AC-1 — LES BONS DE COMMANDE SE SAISISSENT ET SE RÉCEPTIONNENT AU POSTE (`bons-commande.blade.php`).
///
/// ⚠️⚠️ **LE POSTE N'ÉCRIT QUE LE FAIT.** « Générer le Bon » écrit le bon et ses lignes (`pending`). « Valider la réception »
/// n'écrit PAS le statut du bon : elle écrit un ACHAT relié au bon (`purchase_order_id`) ; le serveur
/// (`ReceptionBonCommandeService`) reçoit le bon avec SES lignes, passe la facture, le stock, la dette entière et l'écriture.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-28T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];
  final refus = <String, Map<String, String>>{};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [
                    for (final e in value)
                      if (e is Map && e['id'] is String && !(refus[key]?.containsKey(e['id']) ?? false)) e['id'],
                  ],
                  'rejected': [
                    for (final e in value)
                      if (e is Map && e['id'] is String && (refus[key]?.containsKey(e['id']) ?? false))
                        {'id': e['id'], 'reason': refus[key]![e['id']]},
                  ],
                },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late AchatsRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 28, 14),
    );
    depot = AchatsRepository(database: db, identifiantPoste: 'poste-test');
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: uuid('f1'), name: 'Provenderie du Plateau', category: const Value('Aliments')));
    await db.into(db.products).insert(
      ProductsCompanion.insert(id: uuid('p1'), sku: 'ALI-25', name: 'Aliment ponte 25kg', unit: 'sac', pricingMode: 'fourchette', priceMin: const Value(5900)),
    );
  });
  tearDown(() async => db.close());

  Future<Product> aliment() => (db.select(db.products)..where((p) => p.id.equals(uuid('p1')))).getSingle();

  Future<String> bonSaisi({int qte = 10, double prix = 6000}) async => depot.creerBon(
    fournisseurId: uuid('f1'),
    livraisonAttendue: DateTime(2026, 11, 5),
    lignes: [LigneSaisieBon(produit: await aliment(), quantite: qte, prixEstime: prix)],
  );

  group('dépôt', () {
    test('⚠️ « Générer le Bon » écrit le bon envoyé et ses lignes en pending, sans toucher au stock', () async {
      final stockAvant = (await aliment()).stockQty;

      final id = await bonSaisi();

      final bon = (await db.select(db.purchaseOrders).get()).single;
      expect(bon.id, id);
      expect(bon.syncStatus, SyncStatus.pending);
      expect(bon.deviceId, 'poste-test');
      expect(bon.status, 'envoye');
      expect(bon.supplierName, 'Provenderie du Plateau');
      expect(bon.estimatedTotal, 60000);
      final ligne = (await db.select(db.purchaseOrderLines).get()).single;
      expect(ligne.purchaseOrderId, id);
      expect(ligne.qty, 10);
      expect(ligne.estimatedUnitPrice, 6000);
      expect((await aliment()).stockQty, stockAvant);
      expect(await db.select(db.purchases).get(), isEmpty);
    });

    test('les refus du web sont reproduits AVANT d\'écrire, mêmes messages', () async {
      Future<String> refuse(Future<void> Function() geste) async {
        try {
          await geste();
        } on SaisieAchatRefusee catch (e) {
          return e.motif;
        }
        fail('accepté');
      }

      expect(await refuse(() => depot.creerBon(fournisseurId: uuid('f1'), lignes: [])), 'Ajoutez au moins un article au bon de commande.');
      expect(
        await refuse(() async => depot.creerBon(fournisseurId: uuid('inconnu'), lignes: [LigneSaisieBon(produit: await aliment(), quantite: 1, prixEstime: 1)])),
        'Le champ fournisseur est obligatoire.',
      );
      expect(await db.select(db.purchaseOrders).get(), isEmpty);
    });

    test('⚠️⚠️ la réception écrit un ACHAT relié au bon (crédit, sans règlement), jamais le statut du bon', () async {
      final id = await bonSaisi();

      final achatId = await depot.recevoirBon(id);

      final achat = (await db.select(db.purchases).get()).single;
      expect(achat.id, achatId);
      expect(achat.purchaseOrderId, id);
      expect(achat.syncStatus, SyncStatus.pending);
      expect(achat.paymentMode, 'credit');
      expect(achat.amountPaid, 0);
      expect(achat.treasuryAccountId, isNull, reason: 'la réception ne règle rien');
      expect(achat.total, 60000);
      final ligne = (await db.select(db.purchaseLines).get()).single;
      expect((ligne.qty, ligne.unitPrice), (10.0, 6000.0), reason: 'les lignes du bon, prix estimé devenu prix réel');
      expect((await db.select(db.purchaseOrders).get()).single.status, 'envoye', reason: 'le serveur seul pose « reçu »');
      expect((await aliment()).stockQty, 0, reason: 'le stock est entré par le serveur');

      final d = await depot.charger();
      expect(d.bonsCommande.single.statut, 'recu', reason: 'affiché reçu dès la réception saisie');
      expect(d.bonsCommande.single.receptionPossible, isFalse);
    });

    test('un bon ne se reçoit qu\'une fois, et pas s\'il est déjà reçu, refusé ou inconnu', () async {
      Future<String> refuse(Future<void> Function() geste) async {
        try {
          await geste();
        } on SaisieAchatRefusee catch (e) {
          return e.motif;
        }
        fail('accepté');
      }

      final id = await bonSaisi();
      await depot.recevoirBon(id);
      expect(await refuse(() => depot.recevoirBon(id)), contains('déjà reçu'));
      expect(await refuse(() => depot.recevoirBon(uuid('inconnu'))), contains('inconnu'));

      await db.into(db.purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(id: uuid('b-recu'), deviceId: 'serveur', updatedAt: DateTime.now(), syncStatus: const Value(SyncStatus.synced), supplierId: Value(uuid('f1')), status: const Value('recu')),
      );
      expect(await refuse(() => depot.recevoirBon(uuid('b-recu'))), contains('déjà reçu'));

      final refusee = await bonSaisi();
      await (db.update(db.purchaseOrders)..where((t) => t.id.equals(refusee))).write(const PurchaseOrdersCompanion(syncStatus: Value(SyncStatus.conflict)));
      expect(await refuse(() => depot.recevoirBon(refusee)), contains('refusé par le serveur'));
      expect((await db.select(db.purchases).get()).length, 1);
    });
  });

  group('moteur', () {
    test('⚠️⚠️ l\'envoi porte le bon et ses lignes (sans statut ni total), puis la réception porte purchase_order_id', () async {
      final id = await bonSaisi();
      final achatId = await depot.recevoirBon(id);

      await moteur.synchroniser();

      final bon = (serveur.envois.single['purchase_orders'] as List).single as Map;
      expect(bon['id'], id);
      expect(bon['supplier_id'], uuid('f1'));
      expect(bon['expected_delivery_date'], '2026-11-05');
      expect(bon.containsKey('status'), isFalse);
      expect(bon.containsKey('estimated_total'), isFalse);
      final ligne = (bon['lines'] as List).single as Map;
      expect(ligne['product_id'], uuid('p1'));
      expect(ligne['qty'], 10.0);
      expect(ligne['estimated_unit_price'], 6000.0);
      final achat = (serveur.envois.single['purchases'] as List).single as Map;
      expect(achat['id'], achatId);
      expect(achat['purchase_order_id'], id);
      expect((await db.select(db.purchaseOrders).get()).single.syncStatus, SyncStatus.synced);
      expect((await db.select(db.purchases).get()).single.syncStatus, SyncStatus.synced);
    });

    test('un achat sans bon n\'envoie pas purchase_order_id', () async {
      await depot.enregistrer(
        fournisseurId: uuid('f1'),
        lignes: [LigneSaisieAchat(produit: await aliment(), quantite: 2, prixUnitaire: 5900)],
        modePaiement: 'especes',
        compteId: uuid('t1'),
        montantPaye: 11800,
      );

      await moteur.synchroniser();

      expect(((serveur.envois.single['purchases'] as List).single as Map).containsKey('purchase_order_id'), isFalse);
    });

    test('un refus du serveur sur la réception rend la main : le bon redevient recevable et la relance est possible', () async {
      final id = await bonSaisi();
      final achatId = await depot.recevoirBon(id);
      serveur.refus['purchases'] = {achatId: 'Ce bon de commande est déjà reçu : une seule réception est possible.'};

      await moteur.synchroniser();

      expect((await db.select(db.purchases).get()).single.syncStatus, SyncStatus.conflict);
      final d = await depot.charger();
      expect(d.bonsCommande.single.statut, 'envoye', reason: 'une réception refusée n\'a rien reçu');
      expect(d.bonsCommande.single.motifRefusReception, contains('déjà reçu'));
    });

    test('⚠️ le tirage ne touche pas un bon local non acquitté, remplace les lignes d\'un bon acquitté et retire ceux que le serveur ne sert plus', () async {
      // Un bon refusé (`conflict`) n'est pas renvoyé et ne doit pas être écrasé non plus : même protection que `pending`.
      final local = await bonSaisi();
      await (db.update(db.purchaseOrders)..where((t) => t.id.equals(local))).write(const PurchaseOrdersCompanion(syncStatus: Value(SyncStatus.conflict)));
      await db.into(db.purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(id: uuid('b-vieux'), deviceId: 'serveur', updatedAt: DateTime.now(), syncStatus: const Value(SyncStatus.synced), supplierId: Value(uuid('f1'))),
      );
      await db.into(db.purchaseOrderLines).insert(
        PurchaseOrderLinesCompanion.insert(id: uuid('l-vieille'), purchaseOrderId: uuid('b-vieux'), productId: uuid('p1'), qty: 1, estimatedUnitPrice: 1),
      );
      await db.into(db.purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(id: uuid('b-garde'), deviceId: 'serveur', updatedAt: DateTime.now(), syncStatus: const Value(SyncStatus.synced), supplierId: Value(uuid('f1')), status: const Value('envoye')),
      );
      serveur.tirage = {
        'server_time': '2026-10-28T13:00:00Z',
        'purchase_orders': [
          {
            'id': uuid('b-garde'), 'supplier_id': uuid('f1'), 'supplier_name': 'Provenderie du Plateau', 'expected_delivery_date': '2026-11-10',
            'status': 'recu', 'created_at': '2026-10-20T08:00:00Z', 'estimated_total': 12000.0,
            'lines': [{'id': uuid('l-neuve'), 'product_id': uuid('p1'), 'qty': 2.0, 'estimated_unit_price': 6000.0}],
          },
        ],
      };

      await moteur.synchroniser();

      final bons = {for (final b in await db.select(db.purchaseOrders).get()) b.id: b};
      expect(bons[local]!.syncStatus, SyncStatus.conflict, reason: 'jamais écrasé par le tirage');
      expect(bons.containsKey(uuid('b-vieux')), isFalse, reason: 'le serveur ne le sert plus');
      expect(bons[uuid('b-garde')]!.status, 'recu');
      expect(bons[uuid('b-garde')]!.estimatedTotal, 12000);
      final lignes = await db.select(db.purchaseOrderLines).get();
      expect(lignes.where((l) => l.purchaseOrderId == uuid('b-garde')).single.id, uuid('l-neuve'));
      expect(lignes.where((l) => l.purchaseOrderId == uuid('b-vieux')), isEmpty);
      expect(lignes.where((l) => l.purchaseOrderId == local), isNotEmpty, reason: 'les lignes du bon local restent');
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      await tester.pumpWidget(
        MaterialApp(home: AchatsCommandesScreen(depot: depot, maintenant: () => DateTime(2026, 10, 28, 10))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onglet-achats-Bons de Commande')));
      await tester.pumpAndSettle();
    }

    String texteDe(WidgetTester tester, String cle) => tester.widget<Text>(find.byKey(Key(cle))).data!;

    /// Une pastille porte sa clé sur son conteneur : on lit le texte qu'il contient.
    String pastille(WidgetTester tester, String cle) => tester.widget<Text>(find.descendant(of: find.byKey(Key(cle)), matching: find.byType(Text))).data!;

    Future<void> choisir(WidgetTester tester, String cle, String libelle) async {
      await tester.tap(find.byKey(Key(cle)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(libelle).last);
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️⚠️ le formulaire du Blade génère un bon : prix proposé, total estimé, bon pending dans le tableau', (tester) async {
      await afficher(tester);
      expect(find.text('Planification des approvisionnements de la ferme.'), findsOneWidget);
      expect(find.byKey(const Key('bon-panier-vide')), findsOneWidget);

      // Sans article : le refus du web, rien d'écrit.
      await tester.tap(find.byKey(const Key('bon-generer')));
      await tester.pumpAndSettle();
      expect(find.text('Ajoutez au moins un article au bon de commande.'), findsOneWidget);
      expect(await db.select(db.purchaseOrders).get(), isEmpty);

      await choisir(tester, 'liste-bon-fournisseur', 'Provenderie du Plateau');
      await choisir(tester, 'liste-bon-produit', 'Aliment ponte 25kg');
      expect(tester.widget<TextField>(find.byKey(const Key('champ-bon-prix'))).controller!.text, '5900', reason: 'le prix minimal du produit est proposé');
      await tester.enterText(find.byKey(const Key('champ-bon-quantite')), '4');
      await tester.enterText(find.byKey(const Key('champ-bon-prix')), '6000');
      await tester.tap(find.byKey(const Key('bon-ajouter')));
      await tester.pumpAndSettle();
      expect(texteDe(tester, 'bon-ligne-total-0'), '24 000');
      expect(texteDe(tester, 'bon-total'), '24 000 FCFA');

      await tester.tap(find.byKey(const Key('bon-generer')));
      await tester.pumpAndSettle();
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));

      final bon = (await db.select(db.purchaseOrders).get()).single;
      expect(bon.syncStatus, SyncStatus.pending);
      expect(bon.estimatedTotal, 24000);
      expect(find.byKey(const Key('bon-panier-vide')), findsOneWidget, reason: 'le panier est vidé');
      expect(pastille(tester, 'bon-statut-0'), 'ENVOYÉ / EN COURS');
      expect(find.byKey(const Key('bon-attente-0')), findsOneWidget);
    });

    testWidgets('⚠️ « Valider la réception » écrit l\'achat relié et le bon s\'affiche reçu, sans bouton de réception', (tester) async {
      final id = await bonSaisi();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('bon-recevoir-0')));
      await tester.pumpAndSettle();
      expect(find.text('Valider la réception'), findsWidgets);
      expect(find.text('Confirmer la Réception'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reception-confirmer')));
      await tester.pumpAndSettle();
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));

      expect((await db.select(db.purchases).get()).single.purchaseOrderId, id);
      expect(pastille(tester, 'bon-statut-0'), 'REÇU / VALIDÉ');
      expect(find.byKey(const Key('bon-recevoir-0')), findsNothing);
      expect(find.byKey(const Key('bon-imprimer-0')), findsOneWidget);
    });
  });
}
