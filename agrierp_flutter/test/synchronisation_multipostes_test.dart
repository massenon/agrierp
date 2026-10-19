import 'dart:async';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/fusion_referentiels.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket S-T9 — DÉFAUTS TROUVÉS PAR L'ESSAI À PLUSIEURS POSTES, verrouillés côté poste sans serveur.
///
/// L'essai lui-même (`essai_multipostes_test.dart`, tag `integration`) ne tourne qu'avec le vrai serveur ; ces tests
/// reproduisent chaque défaut avec un serveur feint, pour qu'il ne puisse pas revenir en silence.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Serveur feint : acquitte tout ce qui part ; [pendantLEnvoi] s'exécute APRÈS réception de l'envoi et AVANT la
/// réponse (le geste de l'utilisateur pendant que l'envoi est en route).
class _Serveur extends Interceptor {
  _Serveur({this.pendantLEnvoi, this.fusions = const {}});

  final Future<void> Function()? pendantLEnvoi;
  final Map<String, String> fusions;
  final envois = <Map<String, dynamic>>[];
  int tirages = 0;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      await pendantLEnvoi?.call();
      final reponse = <String, dynamic>{};
      corps.forEach((table, lignes) {
        if (lignes is! List) return;
        reponse[table] = {
          'accepted': [for (final l in lignes) (l as Map)['id']],
          'rejected': <Object?>[],
          if (table == 'livestock_daily_entries')
            'merged': [
              for (final l in lignes)
                if (fusions.containsKey((l as Map)['id'])) {'id': l['id'], 'id_serveur': fusions[l['id']]},
            ],
        };
      });
      return handler.resolve(Response(requestOptions: options, statusCode: 200, data: reponse));
    }
    tirages++;
    handler.resolve(Response(requestOptions: options, statusCode: 200, data: <String, dynamic>{}));
  }
}

const _lot = '11111111-1111-4111-8111-111111111111';
const _fiche = '22222222-2222-4222-8222-222222222222';
const _ficheServeur = '33333333-3333-4333-8333-333333333333';

void main() {
  late AppDatabase db;
  final jour = DateTime(2026, 10, 17);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.livestockLots).insert(
      LivestockLotsCompanion.insert(id: _lot, code: 'ESSAI-A', speciesId: 'aviculture', initialQuantity: const Value(300)),
    );
  });
  tearDown(() async => db.close());

  Future<void> fiche({required SyncStatus statut, int mort = 0, int vente = 0, String id = _fiche}) =>
      db.into(db.livestockDailyEntries).insert(
        LivestockDailyEntriesCompanion.insert(
          id: id,
          deviceId: 'poste-elevage',
          syncStatus: Value(statut),
          updatedAt: DateTime(2026, 10, 17, 9),
          lotId: _lot,
          entryDate: jour,
          mort: Value(mort),
          vente: Value(vente),
          effectifFinal: Value(300 - mort - vente),
        ),
      );

  Future<LivestockDailyEntry?> lire([String id = _fiche]) =>
      (db.select(db.livestockDailyEntries)..where((t) => t.id.equals(id))).getSingleOrNull();

  SyncEngine moteur(_Serveur serveur) {
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur);
    return SyncEngine(database: db, client: client, deviceId: 'poste-elevage', connectivity: _Connectivite());
  }

  group('S-T9 — l\'accusé n\'acquitte que la version partie', () {
    test('🔴 un mort ajouté PENDANT l\'envoi reste en attente et repart (il était perdu)', () async {
      await fiche(statut: SyncStatus.pending, mort: 0);
      final serveur = _Serveur(
        pendantLEnvoi: () async {
          // L'animalier corrige sa fiche pendant que la version précédente est en route.
          await (db.update(db.livestockDailyEntries)..where((t) => t.id.equals(_fiche))).write(
            LivestockDailyEntriesCompanion(mort: const Value(1), updatedAt: Value(DateTime(2026, 10, 17, 9, 0, 0, 400))),
          );
        },
      );

      await moteur(serveur).synchroniser();

      final f = await lire();
      expect(f!.mort, 1);
      expect(f.syncStatus, SyncStatus.pending, reason: 'la correction doit repartir : le serveur a reçu 0 mort');

      // L'envoi suivant porte la correction.
      final suivant = _Serveur();
      await moteur(suivant).synchroniser();
      expect((suivant.envois.single['livestock_daily_entries'] as List).single['mort'], 1);
      expect((await lire())!.syncStatus, SyncStatus.synced);
    });

    test('une vente répercutée pendant l\'envoi ne fait pas repartir la fiche (le serveur ne reprend plus sa vente)',
        () async {
      await fiche(statut: SyncStatus.pending, mort: 2);
      final serveur = _Serveur(
        pendantLEnvoi: () async {
          await (db.update(db.livestockDailyEntries)..where((t) => t.id.equals(_fiche))).write(
            LivestockDailyEntriesCompanion(vente: const Value(3), updatedAt: Value(DateTime(2026, 10, 17, 10))),
          );
        },
      );

      await moteur(serveur).synchroniser();

      expect((await lire())!.syncStatus, SyncStatus.synced);
    });
  });

  group('S-T9 — la vente au comptoir ne renvoie pas une fiche déjà synchronisée', () {
    test('🔴 fiche synchronisée : la vente s\'y affiche, la fiche reste synced (morts tirés jamais renvoyés)', () async {
      await fiche(statut: SyncStatus.synced, mort: 4);
      final repo = FicheJournaliereRepository(database: db, deviceId: 'poste-caisse-1');

      await repo.repercuterVente(_lot, 2, jour, DateTime(2026, 10, 17, 11));

      final f = await lire();
      expect(f!.vente, 2, reason: 'le comptoir voit sa vente tout de suite');
      expect(f.syncStatus, SyncStatus.synced, reason: 'renvoyée, elle porterait les morts tels que le comptoir les avait tirés');
      expect(f.updatedAt, DateTime(2026, 10, 17, 9));
    });

    test('fiche en attente, ou créée par la vente : elle part, comme avant', () async {
      final repo = FicheJournaliereRepository(database: db, deviceId: 'poste-caisse-1');
      await repo.repercuterVente(_lot, 1, jour, DateTime(2026, 10, 17, 11));
      expect((await (db.select(db.livestockDailyEntries)).getSingle()).syncStatus, SyncStatus.pending);

      await (db.delete(db.livestockDailyEntries)).go();
      await fiche(statut: SyncStatus.pending, mort: 1);
      await repo.repercuterVente(_lot, 1, jour, DateTime(2026, 10, 17, 12));
      expect((await lire())!.syncStatus, SyncStatus.pending);
    });
  });

  group('S-T9 — fiche fusionnée par le serveur (même bande, même jour)', () {
    test('la fiche locale prend l\'identifiant du serveur, sur place, et son refus éventuel disparaît', () async {
      await fiche(statut: SyncStatus.pending, mort: 1);
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'livestock_daily_entries:$_fiche',
          sourceTable: 'livestock_daily_entries',
          recordId: _fiche,
          reason: 'ancien refus',
          detectedAt: DateTime(2026, 10, 17),
        ),
      );

      await moteur(_Serveur(fusions: {_fiche: _ficheServeur})).synchroniser();

      expect(await lire(), isNull);
      final f = await lire(_ficheServeur);
      expect(f, isNotNull);
      expect(f!.mort, 1);
      expect(f.syncStatus, SyncStatus.synced);
      expect(await db.select(db.syncConflicts).get(), isEmpty);
    });

    test('idempotent : la fiche du serveur déjà présente, la copie du poste est retirée', () async {
      await fiche(statut: SyncStatus.synced, mort: 1, id: _ficheServeur);
      await db.customStatement(
        "INSERT INTO livestock_daily_entries (id, device_id, sync_status, updated_at, lot_id, entry_date, achat, ne, mort, vente, effectif_final) "
        "SELECT '$_fiche', device_id, 'synced', updated_at, lot_id, entry_date + 86400, achat, ne, mort, vente, effectif_final "
        "FROM livestock_daily_entries WHERE id = '$_ficheServeur'",
      );

      await FusionReferentiels(db).appliquerFiche(_fiche, _ficheServeur);
      await FusionReferentiels(db).appliquerFiche(_fiche, _ficheServeur);

      expect(await lire(), isNull);
      expect(await lire(_ficheServeur), isNotNull);
    });
  });

  test('S-T9 — une vente de bétail acquittée déclenche le tirage de confirmation (la fiche du serveur redescend)',
      () async {
    await fiche(statut: SyncStatus.synced, vente: 0);
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: '44444444-4444-4444-8444-444444444444',
        deviceId: 'poste-caisse-1',
        updatedAt: DateTime(2026, 10, 17, 11),
        paymentMode: 'especes',
        total: 7000,
        soldAt: DateTime(2026, 10, 17, 11),
      ),
    );
    await db.into(db.saleLines).insert(
      SaleLinesCompanion.insert(
        id: '55555555-5555-4555-8555-555555555555',
        saleId: '44444444-4444-4444-8444-444444444444',
        productId: '66666666-6666-4666-8666-666666666666',
        lotId: const Value(_lot),
        qty: 2,
        unitPrice: 3500,
        manualTotalAmount: 7000,
      ),
    );
    final serveur = _Serveur();

    await moteur(serveur).synchroniser();

    expect(serveur.tirages, 2, reason: 'tirage avant l\'envoi, puis tirage de confirmation');
  });
}
