import 'dart:convert';
import 'dart:io';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _C implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _S extends Interceptor {
  List<dynamic> full = [], inc = [];
  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    if (o.path.contains('push')) {
      h.resolve(Response<Map<String, dynamic>>(requestOptions: o, statusCode: 200, data: <String, dynamic>{}));
      return;
    }
    final pages = o.queryParameters['since'] == null ? full : inc;
    final j = o.queryParameters['curseur_page'];
    final i = j == null ? 0 : pages.indexWhere((p) => p['page_suivante'] == j) + 1;
    h.resolve(Response<Map<String, dynamic>>(requestOptions: o, statusCode: 200, data: Map<String, dynamic>.from(pages[i] as Map)));
  }
}

void main() {
  test('bench', () async {
    final s = _S()
      ..full = jsonDecode(File('/tmp/bench/full.json').readAsStringSync())
      ..inc = jsonDecode(File('/tmp/bench/inc.json').readAsStringSync());
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final m = SyncEngine(database: db, client: Dio()..interceptors.add(s), deviceId: 'poste-bench', connectivity: _C());
    void rapport(String t) {
      final l = SyncEngine.mesuresUs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      print('--- $t');
      for (final e in l.take(10)) print('${e.key} ${e.value ~/ 1000} ms (${SyncEngine.mesuresN[e.key]} lignes)');
      SyncEngine.mesuresUs.clear(); SyncEngine.mesuresN.clear();
    }
    var sw = Stopwatch()..start();
    await m.synchroniser();
    print('INITIAL ${sw.elapsedMilliseconds} ms'); rapport('initial');
    sw = Stopwatch()..start();
    await m.synchroniser();
    print('INCREMENTAL ${sw.elapsedMilliseconds} ms'); rapport('incremental');
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
