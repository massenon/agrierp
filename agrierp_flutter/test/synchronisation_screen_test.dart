import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/sync/synchronisation_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
// Drift exporte `isNull` / `isNotNull` (expressions SQL) : masques ici pour
// laisser accessibles les matchers homonymes de `flutter_test`.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sprint 0 Flutter — écran de synchronisation.
///
/// Avant lui, un refus du serveur n'existait que dans un bandeau de huit
/// secondes : le caissier qui s'absentait ne le voyait jamais, et personne ne
/// pouvait dire pourquoi la saisie était restée sur le poste.
class _HorsLigne implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.none,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

void main() {
  late AppDatabase db;
  late SyncEngine engine;

  const bande = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    engine = SyncEngine(
      database: db,
      client: Dio(BaseOptions(baseUrl: 'http://serveur-feint')),
      deviceId: 'poste-test',
      connectivity: _HorsLigne(),
    );

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bande,
            code: 'AVI-2026-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            initialQuantity: const Value(50),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SynchronisationScreen(database: db, engine: engine),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ficheEnAttente(String id) async {
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: id,
            deviceId: 'poste-test',
            updatedAt: DateTime(2026, 8, 18),
            lotId: bande,
            entryDate: DateTime(2026, 8, 18),
          ),
        );
  }

  testWidgets('un poste vierge annonce n avoir jamais synchronise', (
    tester,
  ) async {
    await afficher(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('compteur-attente'))).data,
      '0',
    );
    expect(find.text('Jamais'), findsNWidgets(2));
    expect(find.text('Aucun refus du serveur.'), findsOneWidget);
  });

  testWidgets('les saisies en attente sont comptees', (tester) async {
    await ficheEnAttente('11111111-1111-4111-8111-111111111111');

    await afficher(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('compteur-attente'))).data,
      '1',
    );
    expect(find.textContaining('n\'existent que sur ce poste'), findsOneWidget);
  });

  /// ⚠️ LE MOTIF DU SERVEUR EST AFFICHÉ MOT POUR MOT : le responsable doit
  /// pouvoir le citer pour faire corriger la cause.
  testWidgets('un refus est affiche avec son motif', (tester) async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ficheEnAttente(id);

    await db
        .into(db.syncConflicts)
        .insert(
          SyncConflictsCompanion.insert(
            id: 'livestock_daily_entries:$id',
            sourceTable: 'livestock_daily_entries',
            recordId: id,
            reason: 'lot_id inconnu du serveur',
            detectedAt: DateTime(2026, 8, 18, 9, 30),
          ),
        );

    await afficher(tester);

    expect(find.text('REFUSÉS PAR LE SERVEUR (1)'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(Key('motif-$id'))).data,
      'lot_id inconnu du serveur',
    );
    expect(find.text('Fiche journalière d\'élevage'), findsOneWidget);
  });

  /// ⚠️ UN REFUS COMPTE TOUJOURS COMME « EN ATTENTE » : il n'est pas arrivé au
  /// serveur non plus. Afficher 0 ferait éteindre le poste en croyant le
  /// travail à l'abri.
  testWidgets('un refus reste compte en attente', (tester) async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ficheEnAttente(id);

    await (db.update(
      db.livestockDailyEntries,
    )..where((t) => t.id.equals(id))).write(
      const LivestockDailyEntriesCompanion(
        syncStatus: Value(SyncStatus.conflict),
      ),
    );

    await afficher(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('compteur-attente'))).data,
      '1',
    );
  });

  /// La relance referme le conflit et remet la saisie en file.
  testWidgets('remettre en file referme le refus', (tester) async {
    const id = '11111111-1111-4111-8111-111111111111';
    await ficheEnAttente(id);

    await (db.update(
      db.livestockDailyEntries,
    )..where((t) => t.id.equals(id))).write(
      const LivestockDailyEntriesCompanion(
        syncStatus: Value(SyncStatus.conflict),
      ),
    );

    await db
        .into(db.syncConflicts)
        .insert(
          SyncConflictsCompanion.insert(
            id: 'livestock_daily_entries:$id',
            sourceTable: 'livestock_daily_entries',
            recordId: id,
            reason: 'lot_id inconnu du serveur',
            detectedAt: DateTime(2026, 8, 18, 9, 30),
          ),
        );

    await afficher(tester);

    await tester.tap(find.byKey(Key('relancer-$id')));
    await tester.pumpAndSettle();

    expect(find.text('Aucun refus du serveur.'), findsOneWidget);

    final fiche = await (db.select(
      db.livestockDailyEntries,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(fiche.syncStatus, SyncStatus.pending);
  });

  /// ⚠️ Hors ligne, l'écran le dit sans dramatiser : c'est le mode normal.
  testWidgets('hors ligne, la tentative est annoncee sans erreur', (
    tester,
  ) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('bouton-synchroniser')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hors ligne'), findsOneWidget);
  });
}
