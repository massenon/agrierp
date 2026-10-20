import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket 15.50 — LA RÉINITIALISATION DU SERVEUR ATTEINT LE POSTE.
///
/// 🔴 Avant : un poste gardait toutes les données effacées sur le serveur (bandes, ventes, écritures)
/// et renvoyait ses saisies en attente à la synchronisation suivante — la réinitialisation était
/// défaite par le premier poste qui se reconnectait.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  String? marque;
  final List<Map<String, dynamic>> envois = [];
  final List<Map<String, dynamic>> tirages = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      envois.add(options.data as Map<String, dynamic>);
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: <String, dynamic>{}));
      return;
    }
    tirages.add(options.queryParameters);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {'server_time': '2026-10-17T12:00:00Z', 'data_reset_at': marque},
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;

  const lot = 'bbbbbbbb-1500-4000-8000-000000000001';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 17, 16),
    );
  });

  tearDown(() async => db.close());

  Future<void> activite({bool enAttente = true}) async {
    await db.into(db.livestockLots).insert(
      LivestockLotsCompanion.insert(
        id: lot,
        code: 'LAP-A',
        speciesId: 'esp',
        initialQuantity: const Value(20),
        currentQuantity: const Value(20),
      ),
    );
    await db.into(db.livestockDailyEntries).insert(
      LivestockDailyEntriesCompanion.insert(
        id: 'dddddddd-1500-4000-8000-000000000001',
        deviceId: 'poste-test',
        updatedAt: DateTime(2026, 10, 16),
        lotId: lot,
        entryDate: DateTime(2026, 10, 16),
        mort: const Value(1),
        syncStatus: Value(enAttente ? SyncStatus.pending : SyncStatus.synced),
      ),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: 'pppppppp-1500-4000-8000-000000000001',
        sku: 'ALI-1',
        name: 'Provende',
        categoryId: const Value('cat'),
        unit: 'sac',
        pricingMode: 'fixe',
        stockQty: const Value(40),
      ),
    );
  }

  test('chaque table du poste est classée UNE fois : effacée ou conservée', () {
    final classees = [...AppDatabase.tablesDActivite, ...AppDatabase.tablesConservees];
    final schema = db.allTables.map((t) => t.actualTableName).toSet();

    expect(classees.toSet().length, classees.length, reason: 'une table classée deux fois');
    expect(classees.toSet(), schema);
  });

  test(
    '🔴 marque inconnue : activité effacée AVANT l\'envoi, soldes à zéro, perte annoncée',
    () async {
      await activite();
      await db.noterEtatDeSynchronisation(tire: DateTime(2026, 10, 15));
      serveur.marque = '2026-10-17T09:30:00+00:00';

      final resultat = await moteur.synchroniser();

      expect(await db.select(db.livestockLots).get(), isEmpty);
      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
      expect((await db.select(db.products).getSingle()).stockQty, 0);
      expect(resultat.avertissements.join(' '), contains('réinitialisées le 17/10/2026'));
      expect(resultat.avertissements.join(' '), contains('dont 1 saisie(s)'));
      // La fiche en attente n'est PAS partie, et l'envoi porte la marque appliquée.
      for (final envoi in serveur.envois) {
        expect(envoi['livestock_daily_entries'], isEmpty);
        expect(envoi['data_reset_at'], serveur.marque);
      }
      // Le curseur avait passé : tout est redemandé une fois, sans `since`.
      expect(serveur.tirages.last.containsKey('since'), isFalse);
    },
  );

  test('marque déjà appliquée : rien n\'est effacé une seconde fois', () async {
    serveur.marque = '2026-10-17T09:30:00+00:00';
    await moteur.synchroniser();
    await activite(enAttente: false);

    final resultat = await moteur.synchroniser();

    expect(await db.select(db.livestockLots).get(), hasLength(1));
    expect(resultat.avertissements, isEmpty);
  });

  test('poste neuf : la marque est notée sans avertissement', () async {
    serveur.marque = '2026-10-17T09:30:00+00:00';

    final resultat = await moteur.synchroniser();

    expect(resultat.avertissements, isEmpty);
    expect(serveur.envois.every((e) => e['data_reset_at'] == serveur.marque), isTrue);
  });

  test('serveur jamais réinitialisé : rien n\'est effacé, aucune marque envoyée', () async {
    await activite(enAttente: false);

    await moteur.synchroniser();

    expect(await db.select(db.livestockLots).get(), hasLength(1));
    expect(serveur.envois.every((e) => !e.containsKey('data_reset_at')), isTrue);
  });

  test('envoi refusé (409) : le motif du serveur est repris', () {
    expect(
      EchecSynchronisation.motifHttp(409, {'message': 'Envoi refusé : réinitialisées le 17/10/2026'}),
      'Envoi refusé : réinitialisées le 17/10/2026',
    );
    expect(EchecSynchronisation.motifHttp(409, null), contains('réinitialisées'));
  });
}
