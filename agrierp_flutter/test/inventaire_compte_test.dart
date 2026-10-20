import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/stocks/journal_stocks.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket S-T10 — L'INVENTAIRE DU POSTE PART EN QUANTITÉ COMPTÉE DATÉE ; L'ÉCART EST CALCULÉ PAR LE SERVEUR.
///
/// Le poste envoyait l'écart contre SON stock local : une vente faite au web et pas encore descendue rendait ce stock
/// trop haut, et le serveur décomptait la vente une seconde fois. Désormais la ligne `stock_adjustments` garde la
/// QUANTITÉ COMPTÉE et l'INSTANT du comptage, qui partent avec l'écart local (affichage, serveur ancien) ; le serveur
/// calcule l'écart sur son grand livre (`agrierp_laravel/tests/Feature/SyncInventaireCompteTest.php`). Le poste se
/// recale au tirage de confirmation : stock du produit et mouvement du serveur.
///
/// Attendus calculés à la main : le serveur avait 100 sacs, le web en vend 3 (serveur : 97), le poste — resté à
/// 100 — en compte 95 à 10 h 30 (heure du Bénin) : écart local −5, écart du serveur 95 − 97 = −2.
class _Connexion implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

const _provende = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';

Map<String, dynamic> _produitServi(double stock) => {
  'id': _provende,
  'sku': 'ALI-001',
  'name': 'Aliment ponte 25kg',
  'unit': 'sac',
  'pricing_mode': 'fixe',
  'stock_qty': stock,
  'is_active': true,
  'updated_at': '2026-10-19T10:00:00.000000Z',
};

/// Serveur feint : avant l'envoi il sert l'état d'après la vente du web (97) ; il acquitte l'inventaire ; au tirage
/// de confirmation il sert le stock recalculé (95) et le mouvement qu'il a créé (écart −2, `reference_id` = la ligne
/// du poste, daté de l'instant du comptage).
class _Serveur extends Interceptor {
  final envois = <Map<String, dynamic>>[];
  var tirages = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      return handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [for (final e in value) if (e is Map && e['id'] is String) e['id']],
                  'rejected': [],
                },
          },
        ),
      );
    }
    tirages++;
    final ajustement = envois.isEmpty
        ? null
        : ((envois.last['stock_adjustments'] as List?) ?? const []).cast<Map>().firstOrNull;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'server_time': '2026-10-19T11:00:0${tirages}Z',
          'products': [_produitServi(ajustement == null ? 97 : 95)],
          if (ajustement != null)
            'stock_movements': [
              {
                'id': 'm0000000-0000-4000-8000-000000000001',
                'product_id': _provende,
                'type': 'sortie',
                'quantity': 2,
                'reference_type': 'inventaire',
                'reference_id': ajustement['id'],
                'reason': ajustement['reason'],
                'movement_date': '2026-10-19 10:30:00',
              },
            ],
        },
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late StocksRepository depot;

  /// 10 h 30 au Bénin : l'instant du comptage (heure murale, S-T11).
  final comptage = DateTime(2026, 10, 19, 10, 30);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = StocksRepository(database: db, deviceId: 'poste-bureau', horloge: () => comptage);
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: _provende,
        sku: 'ALI-001',
        name: 'Aliment ponte 25kg',
        unit: 'sac',
        pricingMode: 'fixe',
        // Le dernier tirage du poste : 100 sacs. La vente du web (3 sacs) n'est pas descendue.
        stockQty: const Value(100),
        syncStatus: const Value(SyncStatus.synced),
      ),
    );
  });

  tearDown(() async => db.close());

  test('⚠️⚠️ la ligne garde la QUANTITÉ COMPTÉE et l\'INSTANT du comptage ; le stock local suit le comptage', () async {
    final a = await depot.enregistrerEcart(productId: _provende, stockPhysique: 95, motif: StocksRepository.motifs[1]);

    expect(a.countedQuantity, 95);
    expect(a.movementDate, comptage);
    // L'écart LOCAL, gardé pour l'affichage et un serveur ancien.
    expect(a.type, 'sortie');
    expect(a.quantity, 5);
    expect(a.referenceType, 'inventaire');
    expect(a.syncStatus, SyncStatus.pending);
    expect(a.updatedAt.toUtc(), DateTime.utc(2026, 10, 19, 9, 30), reason: 'instant de la saisie (10 h 30 au Bénin)');
    expect((await db.select(db.products).getSingle()).stockQty, 95);
  });

  test('⚠️⚠️ l\'envoi porte counted_quantity et counted_at (instant UTC), EN PLUS de l\'écart local', () async {
    final serveur = _Serveur();
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur);
    final moteur = SyncEngine(database: db, client: client, deviceId: 'poste-bureau', connectivity: _Connexion());

    final a = await depot.enregistrerEcart(productId: _provende, stockPhysique: 95, motif: StocksRepository.motifs[1]);
    final ajout = await depot.ajouterStock(date: DateTime(2026, 10, 19), productId: _provende, quantite: '4');
    await moteur.synchroniser();

    final lignes = (serveur.envois.single['stock_adjustments'] as List).cast<Map<String, dynamic>>();
    final inventaire = lignes.singleWhere((l) => l['id'] == a.id);
    expect(inventaire['counted_quantity'], 95);
    expect(inventaire['counted_at'], '2026-10-19T09:30:00.000Z', reason: '10 h 30 au Bénin = 09 h 30 UTC');
    expect(inventaire['type'], 'sortie');
    expect(inventaire['quantity'], 5);
    expect(inventaire['reference_type'], 'inventaire');
    expect(inventaire['client_ref'], a.id);

    // Un « Ajout Manuel » n'est pas un comptage : aucune des deux clés.
    final ajoutEnvoye = lignes.singleWhere((l) => l['id'] == ajout.id);
    expect(ajoutEnvoye.containsKey('counted_quantity'), isFalse);
    expect(ajoutEnvoye.containsKey('counted_at'), isFalse);
  });

  test('un inventaire d\'avant S-T10 (sans quantité comptée) part comme avant, sans les deux clés', () async {
    final serveur = _Serveur();
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur);
    final moteur = SyncEngine(database: db, client: client, deviceId: 'poste-bureau', connectivity: _Connexion());
    await db.into(db.stockAdjustments).insert(
      StockAdjustmentsCompanion.insert(
        id: 'b0000000-0000-4000-8000-000000000001',
        deviceId: 'poste-bureau',
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: DateTime.utc(2026, 10, 18, 9),
        productId: _provende,
        type: 'sortie',
        quantity: 1,
        referenceType: 'inventaire',
        movementDate: DateTime(2026, 10, 18, 10),
      ),
    );
    await moteur.synchroniser();

    final ligne = ((serveur.envois.single['stock_adjustments'] as List).single as Map);
    expect(ligne.containsKey('counted_quantity'), isFalse);
    expect(ligne.containsKey('counted_at'), isFalse);
  });

  test('⚠️ un inventaire REFUSÉ (refus rendu sous `client_ref`, serveur d\'avant S-T10) passe en conflit avec son motif', () async {
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: o,
              statusCode: 200,
              data: o.path.contains('push')
                  ? {
                      'stock_adjustments': {
                        'accepted': [],
                        'rejected': [
                          for (final l in ((o.data as Map)['stock_adjustments'] as List).cast<Map>())
                            {'client_ref': l['client_ref'], 'reason': 'Le champ quantité comptée est invalide.'},
                        ],
                      },
                    }
                  : {'server_time': '2026-10-19T11:00:00Z'},
            ),
          ),
        ),
      );
    final moteur = SyncEngine(database: db, client: client, deviceId: 'poste-bureau', connectivity: _Connexion());

    final a = await depot.enregistrerEcart(productId: _provende, stockPhysique: 95, motif: StocksRepository.motifs[1]);
    await moteur.synchroniser();

    final relu = await (db.select(db.stockAdjustments)..where((t) => t.id.equals(a.id))).getSingle();
    expect(relu.syncStatus, SyncStatus.conflict, reason: 'jamais renvoyé en silence à chaque synchronisation');
    expect((await moteur.conflits()).single.reason, 'Le champ quantité comptée est invalide.');
  });

  test('en attente, l\'inventaire compté est projeté à l\'instant du comptage (comme le serveur le datera)', () async {
    await depot.enregistrerEcart(productId: _provende, stockPhysique: 95, motif: StocksRepository.motifs[1]);

    final journal = await JournalStocks.charger(db, maintenant: DateTime(2026, 10, 19, 18));
    final projete = journal.mouvements.single;
    expect(projete.enAttente, isTrue);
    expect(projete.date, comptage, reason: 'pas l\'instant de lecture (18 h)');
  });

  test('⚠️⚠️ à l\'acquittement, le poste se recale au tirage : stock et écart du SERVEUR, jamais l\'écart local', () async {
    final serveur = _Serveur();
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur);
    final moteur = SyncEngine(database: db, client: client, deviceId: 'poste-bureau', connectivity: _Connexion());

    final a = await depot.enregistrerEcart(productId: _provende, stockPhysique: 95, motif: StocksRepository.motifs[1]);
    await moteur.synchroniser();

    expect(serveur.tirages, 2, reason: 'tirage, envoi, puis tirage de CONFIRMATION (un ajustement acquitté)');
    final relu = await (db.select(db.stockAdjustments)..where((t) => t.id.equals(a.id))).getSingle();
    expect(relu.syncStatus, SyncStatus.synced);
    expect((await db.select(db.products).getSingle()).stockQty, 95, reason: 'le stock du serveur, recalculé');

    final journal = await JournalStocks.charger(db, maintenant: DateTime(2026, 10, 19, 18));
    final ecarts = [
      for (final m in journal.mouvements)
        if (JournalStocks.typesEcartInventaire.contains(m.referenceType)) m.quantiteSignee,
    ];
    expect(ecarts, [-2], reason: 'l\'écart du serveur (95 − 97), une seule fois — jamais le −5 local');
    expect(HeureBenin.cleJour(journal.mouvements.single.date), '2026-10-19');
  });
}
