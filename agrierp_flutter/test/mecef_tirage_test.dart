import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/ventes/facturation_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Ticket VC-5 — le tirage dit au poste si le module MeCeF est activé ; sans réponse, le poste garde son défaut (désactivé).
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  SyncEngine moteurServant(Map<String, dynamic> entreprise) => SyncEngine(
    database: db,
    deviceId: 'poste-test',
    connectivity: _Connectivite(),
    coffre: CoffreMemoire(),
    maintenant: () => DateTime(2026, 10, 28, 14),
    client: Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: o,
              statusCode: 200,
              data: o.path.contains('pull') ? {'server_time': '2026-10-28T12:00:00Z', 'company_settings': entreprise} : {},
            ),
          ),
        ),
      ),
  );

  test('⚠️ le serveur active puis désactive le module : la facturation du poste suit', () async {
    final depot = FacturationRepository(database: db, mecefParDefaut: false);
    expect(await depot.mecefActif(), isFalse);

    await moteurServant({'company_name': 'Ferme', 'mecef_actif': true}).synchroniser();
    expect(await depot.mecefActif(), isTrue);

    await moteurServant({'company_name': 'Ferme', 'mecef_actif': false}).synchroniser();
    expect(await depot.mecefActif(), isFalse);
  });

  test('un serveur antérieur (clé absente) ne change pas le choix du poste', () async {
    final depot = FacturationRepository(database: db, mecefParDefaut: false);
    await depot.definirMecefActif(true);

    await moteurServant({'company_name': 'Ferme'}).synchroniser();

    expect(await depot.mecefActif(), isTrue);
  });
}
