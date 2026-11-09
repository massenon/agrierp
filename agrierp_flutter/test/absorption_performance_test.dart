import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// PWA-2b — GARDE DE PERFORMANCE DE L'ABSORPTION (priorité 1 : synchronisation incrémentale lente au navigateur).
///
/// CAUSE MESURÉE dans Chromium : le plan comptable (1 337 lignes, servi EN ENTIER à chaque tirage, incrémental compris)
/// était écrit par un `await insert` PAR LIGNE. Sur le web chaque instruction attendue est un aller-retour vers le worker
/// SQLite (≈ 55 ms) : 73 s pour cette seule table (95 s la page 1). Sur le poste Windows (isolat natif) le même code ne
/// coûtait que ≈ 0,1 s : le défaut est invisible en VM par la DURÉE, d'où une garde sur le NOMBRE D'INSTRUCTIONS émises
/// (ce qui fait le coût au navigateur), plus une durée à marge très large.
///
/// Sémantique inchangée et verrouillée ici : une ligne `pending` n'est jamais écrasée par le tirage.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class _Serveur extends Interceptor {
  _Serveur(this.comptes);
  final List<Map<String, dynamic>> comptes;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path.contains('push')
            ? <String, dynamic>{}
            : {
                'chart_of_accounts': comptes,
                'server_time': '2026-11-09T12:00:00+00:00',
              },
      ),
    );
  }
}

/// Compte les instructions qui atteignent le moteur SQLite (chaque appel = un aller-retour au navigateur).
class _Compteur extends QueryInterceptor {
  int instructions = 0;

  @override
  Future<void> runBatched(QueryExecutor e, BatchedStatements s) {
    instructions++;
    return super.runBatched(e, s);
  }

  @override
  Future<void> runCustom(QueryExecutor e, String s, List<Object?> a) {
    instructions++;
    return super.runCustom(e, s, a);
  }

  @override
  Future<int> runInsert(QueryExecutor e, String s, List<Object?> a) {
    instructions++;
    return super.runInsert(e, s, a);
  }

  @override
  Future<int> runUpdate(QueryExecutor e, String s, List<Object?> a) {
    instructions++;
    return super.runUpdate(e, s, a);
  }

  @override
  Future<int> runDelete(QueryExecutor e, String s, List<Object?> a) {
    instructions++;
    return super.runDelete(e, s, a);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor e,
    String s,
    List<Object?> a,
  ) {
    instructions++;
    return super.runSelect(e, s, a);
  }
}

void main() {
  const n = 3000;
  String id(int i) =>
      'c0c0c0c0-0000-4000-8000-${i.toString().padLeft(12, '0')}';

  test(
    'absorber $n comptes déjà connus : peu d\'instructions, jamais d\'écrasement d\'une ligne en attente',
    () async {
      final comptes = [
        for (var i = 0; i < n; i++)
          {'id': id(i), 'code': '${100000 + i}', 'label': 'Compte $i', 'class': 6},
      ];
      final compteur = _Compteur();
      final db = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(compteur),
      );
      addTearDown(db.close);
      final moteur = SyncEngine(
        database: db,
        client: Dio()..interceptors.add(_Serveur(comptes)),
        deviceId: 'poste-perf',
        connectivity: _Connectivite(),
      );

      // Un compte saisi au poste, en attente : le tirage ne doit pas le toucher.
      await db
          .into(db.chartOfAccounts)
          .insert(
            ChartOfAccountsCompanion.insert(
              id: id(7),
              code: 'LOCAL',
              label: 'Saisi au poste',
              syncStatus: const Value(SyncStatus.pending),
            ),
          );

      await moteur.synchroniser(); // tirage 1 : insère les comptes
      expect(await db.select(db.chartOfAccounts).get(), hasLength(n));

      compteur.instructions = 0;
      final chrono = Stopwatch()..start();
      await moteur.synchroniser(); // tirage 2 : les 3 000 sont DÉJÀ connus
      chrono.stop();

      // Avant : ≥ 3 000 instructions (une par ligne) ; après : une poignée (+ réglages, envoi, curseur).
      expect(
        compteur.instructions,
        lessThan(150),
        reason: 'une instruction par ligne coûterait ≈ 55 ms chacune au navigateur',
      );
      expect(
        chrono.elapsed,
        lessThan(const Duration(seconds: 60)),
        reason: 'marge très large : la VM mesure ≈ 0,3 s',
      );
      final protege = await (db.select(db.chartOfAccounts)
            ..where((t) => t.id.equals(id(7))))
          .getSingle();
      expect(protege.code, 'LOCAL', reason: 'la ligne en attente survit');
    },
  );
}
