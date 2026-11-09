import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/stocks/catalogue_produits_screen.dart';
import 'package:agrierp/features/stocks/produits_repository.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tickets ST-1 / ST-2 — ARCHIVER UN PRODUIT ET CONFIGURER UN SEUIL AU POSTE (`CatalogueProduits::archive`,
/// `SeuilsAlerte::saveThreshold`).
///
/// Les deux écrivent `products` par `ProduitsRepository` : la fiche repasse `pending` et part ENTIÈRE (le serveur la valide
/// comme toute modification de produit) ; l'archivage y ajoute `is_active: false`, jamais l'inverse.
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
  late ProduitsRepository depot;

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
    depot = ProduitsRepository(database: db);
    await db.into(db.productCategories).insert(ProductCategoriesCompanion.insert(id: uuid('cat1'), label: 'Aliments'));
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: uuid('p1'), sku: 'ALI-001', name: 'Aliment ponte 25kg', categoryId: Value(uuid('cat1')), unit: 'sac', pricingMode: 'fourchette',
        priceMin: const Value(5000), priceMax: const Value(6000), stockQty: const Value(4), alertThreshold: const Value(10),
      ),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(id: uuid('p2'), sku: 'ALI-002', name: 'Maïs', categoryId: Value(uuid('cat1')), unit: 'sac', pricingMode: 'fourchette', priceMin: const Value(1), priceMax: const Value(2), stockQty: const Value(50), alertThreshold: const Value(5)),
    );
  });
  tearDown(() async => db.close());

  Future<Product> p1() => depot.produit(uuid('p1')).then((p) => p!);

  group('dépôt', () {
    test('⚠️ archiver marque inactif, repasse pending, ne supprime rien et ne touche ni stock ni prix', () async {
      await depot.archiver(uuid('p1'));

      final p = await p1();
      expect(p.isActive, isFalse);
      expect(p.syncStatus, SyncStatus.pending);
      expect((p.stockQty, p.priceMin, p.priceMax, p.alertThreshold), (4.0, 5000.0, 6000.0, 10.0));
      expect((await db.select(db.products).get()).length, 2, reason: 'archiver n\'efface rien');
      expect((await StocksRepository(database: db, deviceId: 'poste-test').charger()).lignes.map((l) => l.produit.id), [uuid('p2')], reason: 'le catalogue ne propose plus le produit archivé');
    });

    test('archiver un produit inconnu ou déjà archivé ne fait rien', () async {
      await depot.archiver(uuid('inconnu'));
      await depot.archiver(uuid('p1'));
      await (db.update(db.products)..where((t) => t.id.equals(uuid('p1')))).write(const ProductsCompanion(syncStatus: Value(SyncStatus.synced)));

      await depot.archiver(uuid('p1'));

      expect((await p1()).syncStatus, SyncStatus.synced, reason: 'déjà archivé : pas de nouvel envoi');
    });

    test('⚠️ le seuil suit la règle du web : entier, 0 ou plus, obligatoire', () async {
      expect(ProduitsRepository.validerSeuil(''), "Le champ seuil d'alerte est obligatoire.");
      expect(ProduitsRepository.validerSeuil('abc'), contains('nombre entier'));
      expect(ProduitsRepository.validerSeuil('1,5'), contains('nombre entier'));
      expect(ProduitsRepository.validerSeuil('-1'), contains('au moins 0'));
      expect(ProduitsRepository.validerSeuil('0'), isNull);
      expect(ProduitsRepository.validerSeuil(' 25 '), isNull);

      await expectLater(depot.definirSeuil(uuid('p1'), '-3'), throwsArgumentError);
      expect((await p1()).alertThreshold, 10);
    });

    test('définir un seuil écrit alert_threshold, repasse pending, sans toucher au reste de la fiche', () async {
      await depot.definirSeuil(uuid('p1'), '25');

      final p = await p1();
      expect(p.alertThreshold, 25);
      expect(p.syncStatus, SyncStatus.pending);
      expect((p.name, p.stockQty, p.priceMin, p.isActive), ('Aliment ponte 25kg', 4.0, 5000.0, true));
    });
  });

  group('moteur', () {
    test('⚠️⚠️ l\'archivage part avec is_active:false et la fiche entière ; une modification de seuil part is_active:true', () async {
      await depot.archiver(uuid('p1'));
      await depot.definirSeuil(uuid('p2'), '8');

      await moteur.synchroniser();

      final envoyes = <Object?, Map<dynamic, dynamic>>{for (final e in (serveur.envois.single['products'] as List)) (e as Map)['id']: e};
      expect(envoyes[uuid('p1')]!['is_active'], isFalse);
      expect(envoyes[uuid('p1')]!['name'], 'Aliment ponte 25kg');
      expect(envoyes[uuid('p1')]!['alert_threshold'], 10.0);
      expect(envoyes[uuid('p2')]!['is_active'], isTrue);
      expect(envoyes[uuid('p2')]!['alert_threshold'], 8.0);
      expect((await db.select(db.products).get()).every((p) => p.syncStatus == SyncStatus.synced), isTrue);
    });

    test('un refus du serveur sur le seuil devient conflict avec son motif', () async {
      await depot.definirSeuil(uuid('p2'), '8');
      serveur.refus['products'] = {uuid('p2'): 'Le champ seuil est refusé.'};

      await moteur.synchroniser();

      expect((await depot.produit(uuid('p2')))!.syncStatus, SyncStatus.conflict);
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      await tester.pumpWidget(
        MaterialApp(home: CatalogueProduitsScreen(depot: StocksRepository(database: db, deviceId: 'poste-test'), produits: depot)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️⚠️ la liste archive après la confirmation du Blade : le produit disparaît, sa fiche est pending', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('vue-liste')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('archiver-produit-0')), findsOneWidget);

      await tester.tap(find.byKey(const Key('archiver-produit-0')));
      await tester.pumpAndSettle();
      expect(find.text("Confirmer l'archivage"), findsOneWidget);
      expect(find.textContaining('sera marqué(e) comme archivé(e) (statut inactif)'), findsOneWidget);
      expect(find.textContaining("Aucune suppression définitive n'est effectuée."), findsOneWidget);
      expect((await p1()).isActive, isTrue, reason: 'rien tant que l\'on n\'a pas confirmé');

      await tester.tap(find.byKey(const Key('archiver-produit-confirmer')));
      await tester.pumpAndSettle();
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));

      final archives = (await db.select(db.products).get()).where((p) => !p.isActive);
      expect(archives, hasLength(1));
      expect(archives.single.syncStatus, SyncStatus.pending);
      expect(find.textContaining('archivé avec succès'), findsNothing, reason: 'le toast est déjà retiré');
    });

    testWidgets('⚠️ « Annuler » n\'archive rien', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('carte-archiver-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect((await db.select(db.products).get()).every((p) => p.isActive), isTrue);
    });

    testWidgets('⚠️⚠️ le crayon des seuils ouvre « Configurer un Seuil » : refus sous le champ, puis le seuil est écrit', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key("onglet-catalogue-Seuils d'Alerte")));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('modifier-seuil-0')));
      await tester.pumpAndSettle();
      expect(find.text('Configurer un Seuil'), findsOneWidget);
      expect(find.byKey(const Key('seuil-produit')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('seuil-champ')), '');
      await tester.tap(find.byKey(const Key('seuil-enregistrer')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('seuil-erreur'))).data, "Le champ seuil d'alerte est obligatoire.");

      final nom = tester.widget<Text>(find.byKey(const Key('seuil-produit'))).data!;
      await tester.enterText(find.byKey(const Key('seuil-champ')), '40');
      await tester.tap(find.byKey(const Key('seuil-enregistrer')));
      await tester.pumpAndSettle();
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));

      final p = (await db.select(db.products).get()).firstWhere((p) => p.name == nom);
      expect(p.alertThreshold, 40);
      expect(p.syncStatus, SyncStatus.pending);
    });

    testWidgets('sans dépôt d\'écriture, les boutons restent inertes (consultation)', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: CatalogueProduitsScreen(depot: StocksRepository(database: db, deviceId: 'poste-test'))));
      await tester.pumpAndSettle();

      final carte = tester.widget<InkWell>(find.byKey(const Key('carte-archiver-0')));
      expect(carte.onTap, isNull);
    });
  });
}
