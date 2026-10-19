import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket U9 — LE GRAND LIVRE DES STOCKS (`stock_movements`) DESCEND AU POSTE.
///
/// Verrouillé ici : l'absorbeur STRICT (tout ou rien, curseur immobile sur refus), le remplacement par identifiant
/// (le serveur resert deux minutes sous le curseur), la clé absente (serveur antérieur), la resynchronisation unique
/// `mouvements_resync_u9`, le journal JAMAIS envoyé (référentiel en lecture seule), le tirage de confirmation qui
/// rapporte le mouvement d'un ajustement acquitté — et, de bout en bout, qu'un écart d'inventaire saisi ici est
/// compté UNE fois avant l'envoi, après l'acquittement et après la redescente de son mouvement.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Serveur feint : sert [tirage] (ou [apresEnvoi] une fois un envoi reçu), acquitte tout envoi et garde chaque corps.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-19T12:00:00Z'};
  Map<String, dynamic>? apresEnvoi;

  final List<Object?> demandes = [];
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      if (apresEnvoi != null) tirage = apresEnvoi!;
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
                      if (e is Map && e['id'] is String) e['id'],
                  ],
                  'rejected': [],
                },
          },
        ),
      );
      return;
    }
    demandes.add(options.queryParameters['since']);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: tirage,
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;

  const provende = 'd1d2d3d4-0000-4000-8000-00000000000b';
  String uuid(String graine) => graine.padRight(36, '0');

  Map<String, dynamic> mouvementJson(
    String id, {
    String produit = provende,
    Object? type = 'sortie',
    Object? quantite = 3,
    Object? reference = 'sale',
    Object? referenceId,
    Object? motif,
    Object? date = '2026-10-12 23:30:00',
  }) => {
    'id': id,
    'product_id': produit,
    'type': type,
    'quantity': quantite,
    'reference_type': reference,
    'reference_id': referenceId,
    'reason': motif,
    'movement_date': date,
  };

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 19, 14),
    );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: provende,
            sku: 'ALI-PONTE',
            name: 'Provende ponte',
            unit: 'sac',
            pricingMode: 'fixe',
            stockQty: const Value(40),
            syncStatus: const Value(SyncStatus.synced),
          ),
        );
  });

  tearDown(() async => db.close());

  group('absorbeur', () {
    test('le journal servi est absorbé tel quel, date en heure MURALE du serveur', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'stock_movements': [
          mouvementJson(uuid('m1'), motif: 'Vol / Disparition', reference: 'adjustment'),
          mouvementJson(
            uuid('m2'),
            type: 'entree',
            quantite: 2.5,
            reference: 'purchase',
            referenceId: uuid('achat'),
            date: '2026-10-13 09:00:00',
          ),
        ],
      };

      await moteur.synchroniser();

      final lignes = await (db.select(
        db.stockMovements,
      )..orderBy([(t) => OrderingTerm(expression: t.movementDate)])).get();
      expect(lignes, hasLength(2));
      expect(lignes[0].type, 'sortie');
      expect(lignes[0].quantity, 3);
      expect(lignes[0].referenceType, 'adjustment');
      expect(lignes[0].referenceId, isNull);
      expect(lignes[0].reason, 'Vol / Disparition');
      // 23 h 30 le 12 reste le 12 : jamais converti d'un fuseau à l'autre.
      expect(lignes[0].movementDate, DateTime(2026, 10, 12, 23, 30));
      expect(lignes[1].quantity, 2.5);
      expect(lignes[1].referenceId, uuid('achat'));
    });

    test('un mouvement resservi (recouvrement de deux minutes) est remplacé, jamais dupliqué', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'stock_movements': [mouvementJson(uuid('m1'))],
      };
      await moteur.synchroniser();
      await moteur.synchroniser();

      expect(await db.select(db.stockMovements).get(), hasLength(1));
    });

    test('clé absente (serveur antérieur à U9) : rien n est touché', () async {
      await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: uuid('m0'),
              productId: provende,
              type: 'entree',
              quantity: 1,
              referenceType: 'purchase',
              movementDate: DateTime(2026, 10, 1),
            ),
          );

      await moteur.synchroniser();

      expect(await db.select(db.stockMovements).get(), hasLength(1));
    });

    for (final (cas, fautif) in <(String, Map<String, dynamic>)>[
      ('produit inconnu du poste', mouvementJson(uuid('mx'), produit: uuid('inconnu'))),
      ('type hors enum', mouvementJson(uuid('mx'), type: 'perte')),
      ('quantité négative', mouvementJson(uuid('mx'), quantite: -2)),
      ('quantité absente', mouvementJson(uuid('mx'), quantite: null)),
      ('quantité illisible', mouvementJson(uuid('mx'), quantite: 'trois')),
      ('type de référence absent', mouvementJson(uuid('mx'), reference: null)),
      ('référence qui n est pas un texte', mouvementJson(uuid('mx'), referenceId: 12)),
      ('date illisible', mouvementJson(uuid('mx'), date: 'hier')),
      ('identifiant invalide', mouvementJson('court')),
      ('servi deux fois', mouvementJson(uuid('m1'))),
    ]) {
      test('⚠️⚠️ STRICT — $cas : tout le lot est refusé, le curseur ne bouge pas', () async {
        await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
        final curseur = (await db.etatDeSynchronisation())?.lastPulledAt;
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'stock_movements': [mouvementJson(uuid('m1')), fautif],
        };

        await expectLater(
          moteur.synchroniser(),
          throwsA(isA<FormatException>()),
        );

        expect(await db.select(db.stockMovements).get(), isEmpty);
        expect((await db.etatDeSynchronisation())?.lastPulledAt, curseur);
      });
    }
  });

  group('lecture seule', () {
    test('⚠️⚠️ le journal n est JAMAIS envoyé, même avec un ajustement en attente', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'stock_movements': [mouvementJson(uuid('m1'))],
      };
      await StocksRepository(
        database: db,
        deviceId: 'poste-test',
      ).enregistrerEcart(productId: provende, stockPhysique: 38, motif: 'Casse de matériel');

      await moteur.synchroniser();

      expect(serveur.envois, isNotEmpty);
      for (final corps in serveur.envois) {
        expect(corps.containsKey('stock_movements'), isFalse);
      }
      expect(AppDatabase.tablesEnvoyees, isNot(contains('stock_movements')));
    });

    test('la réinitialisation du serveur (15.50) efface le journal : c est une table d activité', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'stock_movements': [mouvementJson(uuid('m1'))],
      };
      await moteur.synchroniser();

      await db.purgerDonneesDActivite();

      expect(await db.select(db.stockMovements).get(), isEmpty);
      expect(AppDatabase.tablesDActivite, contains('stock_movements'));
    });
  });

  group('resynchronisation unique `mouvements_resync_u9`', () {
    Future<void> posteEnService() async {
      await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
      for (final cle in [
        SyncEngine.cleJournalResync,
        SyncEngine.cleJournalResyncCreation,
        SyncEngine.cleFichesResync,
        SyncEngine.cleFichesResyncCategories,
        SyncEngine.cleLignesResync,
        SyncEngine.cleRetoursResync,
      ]) {
        await db
            .into(db.appSettings)
            .insert(AppSettingsCompanion.insert(key: cle, value: '1'));
      }
    }

    test(
      '⚠️⚠️ un poste déjà en service redemande TOUT une fois (le journal est antérieur à son curseur), puis l incrémental',
      () async {
        await posteEnService();
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'stock_movements': [mouvementJson(uuid('m1'))],
        };

        await moteur.synchroniser();
        await moteur.synchroniser();

        expect(serveur.demandes.first, isNull, reason: 'sans since, une fois');
        expect(serveur.demandes.last, isNotNull, reason: 'puis incrémental');
        expect(await db.select(db.stockMovements).get(), hasLength(1));
      },
    );

    test(
      '⚠️ serveur antérieur à U9 (produits servis sans leur grand livre) : la resynchronisation N EST PAS marquée faite',
      () async {
        await posteEnService();
        serveur.tirage = {'server_time': '2026-10-19T12:00:00Z', 'products': []};

        await moteur.synchroniser();
        await moteur.synchroniser();

        expect(serveur.demandes, [null, null]);
      },
    );
  });

  /// ⚠️⚠️ **DE BOUT EN BOUT : UN ÉCART SAISI ICI COMPTE UNE FOIS, À CHAQUE ÉTAPE.** Avant l'envoi il est projeté
  /// (`pending`) ; l'envoi l'acquitte et le TIRAGE DE CONFIRMATION rapporte son mouvement (même `reference_id`) ;
  /// la projection cesse. Jamais zéro fois (acquitté mais pas encore redescendu), jamais deux fois.
  test('⚠️⚠️ U9 — l écart saisi ici compte UNE fois avant l envoi, et après la redescente de son mouvement', () async {
    await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            id: uuid('achat'),
            deviceId: 'serveur',
            updatedAt: DateTime(2026, 10, 1),
            syncStatus: const Value(SyncStatus.synced),
            supplierId: uuid('fournisseur'),
            paymentMode: 'especes',
            total: 0,
            purchaseDate: DateTime(2026, 10, 1),
          ),
        );
    await db
        .into(db.purchaseLines)
        .insert(
          PurchaseLinesCompanion.insert(
            id: uuid('ligne'),
            purchaseId: uuid('achat'),
            productId: provende,
            qty: 10,
            unitPrice: 8000,
          ),
        );
    final depot = StocksRepository(
      database: db,
      deviceId: 'poste-test',
      horloge: () => DateTime(2026, 10, 19, 14),
    );
    final ecart = await depot.enregistrerEcart(
      productId: provende,
      stockPhysique: 37,
      motif: 'Casse de matériel',
    );

    // Avant l'envoi : −3 × 8 000.
    expect((await depot.charger()).ecartsDuMois, -24000);

    // L'envoi acquitte ; le serveur rejoue et sert le mouvement au tirage de confirmation.
    serveur.apresEnvoi = {
      'server_time': '2026-10-19T12:05:00Z',
      'stock_movements': [
        mouvementJson(
          uuid('m-serveur'),
          reference: 'inventaire',
          referenceId: ecart.id,
          motif: 'Casse de matériel',
          date: '2026-10-19 12:04:00',
        ),
      ],
    };
    await moteur.synchroniser();

    expect(serveur.demandes, hasLength(2), reason: 'tirage de confirmation');
    final apres = await depot.charger();
    expect(apres.ecartsDuMois, -24000, reason: 'ni zéro, ni deux fois');
    expect(apres.journal.where((l) => l.mouvement.referenceType == 'inventaire'), hasLength(1));
    expect(apres.journal.single.mouvement.enAttente, isFalse);
  });
}
