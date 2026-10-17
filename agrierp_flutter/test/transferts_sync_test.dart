import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/elevage/transferts_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket 15.46 — LES TRANSFERTS ENTRE BANDES VOYAGENT DANS LES DEUX SENS.
///
///  - Envoi : un transfert créé (ou annulé) hors ligne part avec la fiche créée pour lui, puis passe
///    `synced` à l'accusé, ou `conflict` avec le motif du serveur.
///  - Tirage : les transferts du web descendent, et les colonnes `transfert_*` des fiches aussi.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-14T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];
  String? refusTransfert;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      List<String> ids(String cle) => [
        for (final e in corps[cle] as List? ?? const []) (e as Map)['id'] as String,
      ];
      final transferts = ids('livestock_transfers');
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'livestock_daily_entries': {'accepted': ids('livestock_daily_entries'), 'rejected': []},
            'livestock_transfers': refusTransfert == null
                ? {'accepted': transferts, 'rejected': []}
                : {
                    'accepted': [],
                    'rejected': [
                      for (final id in transferts) {'id': id, 'reason': refusTransfert},
                    ],
                  },
          },
        ),
      );
      return;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage),
    );
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late TransfertsRepository depot;

  const especeLapins = 'esp-lapins-0000-0000-000000000001';
  const a = 'bbbbbbbb-0000-4000-8000-000000000001';
  const b = 'bbbbbbbb-0000-4000-8000-000000000002';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    final client = Dio()..interceptors.add(serveur);
    moteur = SyncEngine(
      database: db,
      client: client,
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 14, 16),
    );
    depot = TransfertsRepository(database: db, deviceId: 'poste-test');
    for (final (id, code, n) in [(a, 'LAP-A', 20), (b, 'LAP-B', 5)]) {
      await db
          .into(db.livestockLots)
          .insert(
            LivestockLotsCompanion.insert(
              id: id,
              code: code,
              speciesId: especeLapins,
              speciesCode: const Value('cuniculture'),
              stage: const Value('croissance'),
              initialQuantity: Value(n),
              currentQuantity: Value(n),
              createdDate: Value(DateTime(2026, 9, 1)),
            ),
          );
    }
  });

  tearDown(() async => db.close());

  test('un transfert du poste part avec ses fiches, sans colonne de transfert, puis est acquitté', () async {
    final t = await depot.creer(
      sourceLotId: a,
      targetLotId: b,
      jour: DateTime(2026, 9, 5),
      quantite: 6,
      categorie: 'sevre',
    );
    expect(await db.pendingCount(), 3, reason: 'le transfert et les deux fiches créées pour lui');

    await moteur.synchroniser();

    final envoi = serveur.envois.single;
    final transferts = envoi['livestock_transfers'] as List;
    expect(transferts.single, containsPair('id', t.id));
    expect(transferts.single, containsPair('transfer_date', '2026-09-05'));
    expect(transferts.single, containsPair('categorie', 'sevre'));
    expect((envoi['livestock_daily_entries'] as List).length, 2);
    for (final f in envoi['livestock_daily_entries'] as List) {
      expect((f as Map).keys.where((k) => k.toString().startsWith('transfert')), isEmpty,
          reason: 'colonnes dérivées : le serveur les recalcule, le poste ne les envoie jamais');
    }
    final apres = await (db.select(db.livestockTransfers)..where((x) => x.id.equals(t.id))).getSingle();
    expect(apres.syncStatus, SyncStatus.synced);
    expect(await db.pendingCount(), 0);
  });

  test('un transfert refusé par le serveur passe en conflit avec son motif', () async {
    serveur.refusTransfert = 'Transfert refusé : la bande source LAP-A ne compte que 3 sujet(s) le 05/09/2026.';
    await depot.creer(sourceLotId: a, targetLotId: b, jour: DateTime(2026, 9, 5), quantite: 6, categorie: 'sevre');

    final resultat = await moteur.synchroniser();

    expect(resultat.motifs.join(' '), contains('ne compte que 3 sujet(s)'));
    final t = await db.select(db.livestockTransfers).getSingle();
    expect(t.syncStatus, SyncStatus.conflict);
  });

  test('le tirage absorbe les transferts du web et les colonnes de transfert des fiches', () async {
    serveur.tirage = {
      'server_time': '2026-10-14T12:00:00Z',
      'livestock_lots': [
        {
          'id': b, 'code': 'LAP-B', 'species_id': especeLapins, 'species_code': 'cuniculture',
          'stage': 'croissance', 'initial_quantity': 5, 'current_quantity': 11,
          'created_date': '2026-09-01', 'status': 'actif', 'is_active': true, 'lot_source_id': a,
        },
      ],
      'livestock_daily_entries': [
        {
          'id': 'dddddddd-0000-4000-8000-000000000001', 'lot_id': b, 'entry_date': '2026-09-05',
          'achat': 0, 'ne': 0, 'mort': 0, 'vente': 0, 'don': 0, 'effectif_final': 11,
          'transfert_entree': 6, 'transfert_sortie': 0, 'transfert_entree_sevre': 6,
          'updated_at': '2026-10-14T11:00:00Z',
        },
      ],
      'livestock_transfers': [
        {
          'id': 'eeeeeeee-0000-4000-8000-000000000001', 'source_lot_id': a, 'target_lot_id': b,
          'transfer_date': '2026-09-05', 'quantity': 6, 'categorie': 'sevre', 'constitution': false,
          'motif': 'Sevrage', 'is_active': true, 'updated_at': '2026-10-14T11:00:00Z',
        },
      ],
    };

    await moteur.synchroniser();

    final t = await db.select(db.livestockTransfers).getSingle();
    expect([t.quantity, t.categorie, t.isActive, t.syncStatus], [6, 'sevre', true, SyncStatus.synced]);
    final f = await db.select(db.livestockDailyEntries).getSingle();
    expect([f.transfertEntree, f.transfertEntreeSevre, f.effectifFinal], [6, 6, 11]);
    final lot = await (db.select(db.livestockLots)..where((x) => x.id.equals(b))).getSingle();
    expect(lot.lotSourceId, a);
  });
}
