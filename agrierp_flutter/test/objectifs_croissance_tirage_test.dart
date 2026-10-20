import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket U2 (décision client D-U2 du 19/10/2026) — LES OBJECTIFS DE GMQ DESCENDENT DU SERVEUR.
///
/// `growth_standards` est servie COMPLÈTE à chaque tirage (`SyncController::pull`) ; le poste en remplace
/// l'ensemble (référentiel en lecture seule) par un absorbeur STRICT : une ligne incohérente refuse le lot, le
/// barème précédent reste et le curseur n'avance pas.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-19T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      envois.add(options.data as Map<String, dynamic>);
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {}));
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;

  String uuid(int n) => '22222222-0000-4000-8000-${n.toString().padLeft(12, '0')}';

  Map<String, Object?> ligne(int n, String espece, Object? stade, Object? min, Object? max) => {
    'id': uuid(n),
    'species_code': espece,
    'stage_label': stade,
    'gmq_min_g_per_day': min,
    'gmq_max_g_per_day': max,
  };

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
    );
  });

  tearDown(() async => db.close());

  Future<List<(String, String, int, int)>> bareme() async => [
    for (final b in await (db.select(db.growthStandards)
          ..orderBy([(t) => OrderingTerm(expression: t.speciesCode), (t) => OrderingTerm(expression: t.stageLabel)]))
        .get())
      (b.speciesCode, b.stageLabel, b.gmqMinGPerDay, b.gmqMaxGPerDay),
  ];

  test('le barème servi remplace l ensemble à chaque tirage', () async {
    serveur.tirage = {
      'server_time': '2026-10-19T12:00:00Z',
      'growth_standards': [
        ligne(1, 'cuniculture', 'engraissement', 15, 20),
        ligne(2, 'porciculture', 'engraissement', 500, 650),
      ],
    };
    await moteur.synchroniser();
    expect(await bareme(), [('cuniculture', 'engraissement', 15, 20), ('porciculture', 'engraissement', 500, 650)]);

    // Le web a corrigé un objectif et retiré une ligne : le poste suit, rien ne reste d'avant.
    serveur.tirage = {
      'server_time': '2026-10-19T13:00:00Z',
      'growth_standards': [ligne(1, 'cuniculture', 'engraissement', 16, 22)],
    };
    await moteur.synchroniser();
    expect(await bareme(), [('cuniculture', 'engraissement', 16, 22)]);

    // Un référentiel ne repart jamais.
    expect(serveur.envois.where((e) => e.containsKey('growth_standards')), isEmpty);
    expect(await db.pendingCount(), 0);
  });

  test('une réponse sans la clé (serveur antérieur à U2) ne touche à rien ; une liste vide vide le barème', () async {
    serveur.tirage = {
      'server_time': '2026-10-19T12:00:00Z',
      'growth_standards': [ligne(1, 'cuniculture', 'engraissement', 15, 20)],
    };
    await moteur.synchroniser();

    serveur.tirage = {'server_time': '2026-10-19T13:00:00Z'};
    await moteur.synchroniser();
    expect(await bareme(), hasLength(1));

    serveur.tirage = {'server_time': '2026-10-19T14:00:00Z', 'growth_standards': <Object>[]};
    await moteur.synchroniser();
    expect(await bareme(), isEmpty);
  });

  test('⚠️⚠️ STRICT : une ligne illisible refuse le lot et le barème précédent reste', () async {
    serveur.tirage = {
      'server_time': '2026-10-19T12:00:00Z',
      'growth_standards': [ligne(1, 'cuniculture', 'engraissement', 15, 20)],
    };
    await moteur.synchroniser();

    for (final fautive in [
      ligne(2, 'porciculture', 'engraissement', 'cinq cents', 650),
      ligne(2, 'porciculture', 'engraissement', 500.5, 650),
      ligne(2, 'porciculture', 'engraissement', -1, 650),
      ligne(2, 'porciculture', 'engraissement', 500, null),
      ligne(2, 'porciculture', null, 500, 650),
      {...ligne(2, 'porciculture', 'engraissement', 500, 650), 'id': 'court'},
      // Même identifiant servi deux fois.
      ligne(1, 'porciculture', 'engraissement', 500, 650),
    ]) {
      serveur.tirage = {
        'server_time': '2026-10-19T13:00:00Z',
        'growth_standards': [ligne(1, 'cuniculture', 'engraissement', 99, 99), fautive],
      };
      await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()), reason: '$fautive');
      expect(await bareme(), [('cuniculture', 'engraissement', 15, 20)], reason: 'rien n est écrit : $fautive');
    }
  });

  test('un objectif servi en texte entier (pilote MySQL) est lu', () async {
    serveur.tirage = {
      'server_time': '2026-10-19T12:00:00Z',
      'growth_standards': [ligne(1, 'aviculture', 'croissance', '20', '30')],
    };
    await moteur.synchroniser();
    expect(await bareme(), [('aviculture', 'croissance', 20, 30)]);
  });
}
