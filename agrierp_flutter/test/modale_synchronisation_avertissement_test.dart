import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/modale_synchronisation.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.84-bis — l'écran DIT ce que le tirage du journal a constaté sans le refuser. Depuis le ticket H2,
/// c'est la modale « Synchronisation » de la barre supérieure qui le dit (le bouton du pied de barre est retiré).
///
/// Un serveur qui annonce « aucune écriture active » alors que le poste en contient ne vide pas le
/// journal au premier tirage : l'utilisateur doit le lire, pas croire à un « Déjà à jour ».
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class _ServeurJournalVide extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{
          'server_time': '2026-10-10T12:00:00+00:00',
          'accounting_entry_ids': <String>[],
          'accounting_entries': <Map<String, dynamic>>[],
          'accounting_entry_lines': <Map<String, dynamic>>[],
        },
      ),
    );
  }
}

void main() {
  testWidgets(
    '⚠️ un journal annoncé vide est signalé à l écran, jamais « Déjà à jour »',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() => db.close());
      await tester.runAsync(
        () => db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: '00000000-0000-4000-8000-000000000001',
                entryDate: DateTime(2026, 10, 1),
              ),
            ),
      );
      final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
        ..interceptors.add(_ServeurJournalVide());
      final moteur = SyncEngine(
        database: db,
        client: client,
        deviceId: 'poste-test',
        connectivity: _Connectivite(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModaleSynchronisation(engine: moteur, database: db),
          ),
        ),
      );

      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('sync-maintenant')));
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.descendant(
          of: find.byKey(const Key('sync-derniere-tentative')),
          matching: find.textContaining('journal comptable vide'),
        ),
        findsOneWidget,
      );
      // Le toast est un avertissement, jamais un succès muet.
      expect(find.byKey(const Key('toast-avertissement')), findsOneWidget);
      expect(find.byKey(const Key('toast-succes')), findsNothing);
      ToastAgri.toutRetirer();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
