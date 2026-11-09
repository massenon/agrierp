import 'dart:async';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/systeme/verrou_onglets.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// PWA-2b — PLUSIEURS ONGLETS : une seule synchronisation à la fois, tous onglets confondus (verrou simple). Deux « onglets » =
/// deux moteurs sur deux bases (comme deux onglets, chacun sa mémoire) qui partagent UN verrou factice (`navigator.locks`).
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  int enCours = 0;
  int maximum = 0;
  int tirages = 0;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.path.contains('pull')) {
      tirages++;
      enCours++;
      if (enCours > maximum) maximum = enCours;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      enCours--;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path.contains('push') ? <String, dynamic>{} : {'server_time': '2026-11-09T12:00:00+00:00'},
      ),
    );
  }
}

void main() {
  tearDown(() => SyncEngine.verrouEntreOnglets = sousVerrouEntreOnglets<SyncOutcome>);

  SyncEngine moteur(_Serveur serveur) => SyncEngine(
    database: AppDatabase.forTesting(NativeDatabase.memory()),
    client: Dio()..interceptors.add(serveur),
    deviceId: 'poste-web',
    connectivity: _Connectivite(),
  );

  test('natif : le verrou n\'ajoute rien (l\'action s\'exécute telle quelle)', () async {
    expect(await sousVerrouEntreOnglets<int>(() async => 42), 42);
    await expectLater(sousVerrouEntreOnglets<int>(() async => throw StateError('x')), throwsStateError);
  });

  test('deux onglets qui synchronisent en même temps : jamais deux tirages simultanés', () async {
    // Verrou factice : file d'attente exclusive partagée par les deux moteurs.
    Future<void> file = Future<void>.value();
    SyncEngine.verrouEntreOnglets = (action) {
      final suite = file.then((_) => action());
      file = suite.then((_) {}, onError: (_) {});
      return suite;
    };
    final serveur = _Serveur();
    final a = moteur(serveur);
    final b = moteur(serveur);
    await Future.wait([a.synchroniser(), b.synchroniser()]);
    expect(serveur.tirages, 2, reason: 'chaque onglet a bien synchronisé…');
    expect(serveur.maximum, 1, reason: '…mais l\'un après l\'autre');
  });

  test('sans verrou (témoin), les deux tirages se chevauchent', () async {
    final serveur = _Serveur();
    await Future.wait([moteur(serveur).synchroniser(), moteur(serveur).synchroniser()]);
    expect(serveur.maximum, 2);
  });
}
