import 'dart:async';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// PWA-2c — sondage léger du serveur (`SyncEngine.serveurJoignable`) et libellés de l'indicateur de liaison.
class _Reseau implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Reponse extends Interceptor {
  _Reponse(this.quoi);
  final Future<Response<Object?>> Function(RequestOptions) quoi;
  final vues = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    vues.add(options);
    quoi(options).then(handler.resolve, onError: (Object e) {
      handler.reject(
        e is DioException ? e : DioException(requestOptions: options, error: e, type: DioExceptionType.connectionError),
      );
    });
  }
}

void main() {
  SyncEngine moteur(_Reponse serveur) {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return SyncEngine(
      database: db,
      client: Dio(BaseOptions(baseUrl: 'http://serveur.test'))..interceptors.add(serveur),
      deviceId: 'poste-sonde',
      connectivity: _Reseau(),
    );
  }

  Response<Object?> http(RequestOptions o, int code) =>
      Response<Object?>(requestOptions: o, statusCode: code, data: '');

  test('serveur qui répond : joignable, route /up, jamais en cache, aucune donnée', () async {
    final serveur = _Reponse((o) async => http(o, 200));
    final m = moteur(serveur);
    expect(m.liaisonServeur.value, isNull);
    expect(await m.serveurJoignable(), isTrue);
    expect(m.liaisonServeur.value, isTrue);
    final r = serveur.vues.single;
    expect(r.path, '/up', reason: 'route de santé EXISTANTE, aucune route ajoutée');
    expect(r.method, 'GET');
    expect(r.headers['Cache-Control'], 'no-store');
    expect(r.receiveTimeout, const Duration(seconds: 3));
    expect(r.queryParameters.keys, ['_'], reason: 'aucun paramètre métier');
  });

  test('un 401 ou 404 prouve que le serveur répond ; un 502 / 503 non', () async {
    for (final (code, attendu) in [(401, true), (404, true), (502, false), (503, false)]) {
      final m = moteur(_Reponse((o) async => http(o, code)));
      expect(await m.serveurJoignable(), attendu, reason: '$code');
    }
  });

  test('réseau coupé ou délai dépassé : hors ligne, sans lever', () async {
    final coupe = moteur(_Reponse((o) => Future.error(DioException(requestOptions: o, type: DioExceptionType.connectionError))));
    expect(await coupe.serveurJoignable(), isFalse);
    expect(coupe.liaisonServeur.value, isFalse);

    final lent = moteur(_Reponse((o) => Completer<Response<Object?>>().future));
    expect(await lent.serveurJoignable(delai: const Duration(milliseconds: 50)), isFalse);
    expect(lent.liaisonServeur.value, isFalse);
  });

  test('indicateur : mêmes mots que la modale (Hors ligne / En attente (N) / Synchronisé)', () {
    expect(BarreSuperieure.libelleLiaison(liaison: false, enAttente: 3), 'Hors ligne');
    expect(BarreSuperieure.libelleLiaison(liaison: true, enAttente: 3), 'En attente (3)');
    expect(BarreSuperieure.libelleLiaison(liaison: true, enAttente: 0), 'Synchronisé');
    expect(BarreSuperieure.libelleLiaison(liaison: null, enAttente: 0), 'Synchronisé');
  });
}
