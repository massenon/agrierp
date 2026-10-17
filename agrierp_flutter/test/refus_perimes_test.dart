import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/administration/administration_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serveur feint minimal : répond [reponsePush] à l'envoi, un tirage vide sinon.
class _Serveur extends Interceptor {
  _Serveur(this.reponsePush);

  final Map<String, dynamic> reponsePush;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final push = options.path.contains('push');
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: push
            ? reponsePush
            : {
                'server_time': '2026-10-09T12:01:00.000Z',
                'product_categories': <dynamic>[],
                'products': <dynamic>[],
                'livestock_lots': <dynamic>[],
              },
      ),
    );
  }
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Ticket F0.79-bis — LES MOTIFS DE REFUS PÉRIMÉS.
///
/// ⚠️⚠️ Un refus corrigé, accepté ou rendu sans objet (la ligne est retirée) ne doit pas
/// survivre dans `sync_conflicts` : l'écran Synchronisation l'afficherait avec « Relancer »
/// pour une ligne qui n'est plus refusée. Mais le refus d'un AUTRE enregistrement, lui,
/// reste.
void main() {
  late AppDatabase db;
  late AdministrationRepository depot;

  String uuid(String g) => g.padRight(36, '0').substring(0, 36);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = AdministrationRepository(database: db);
  });

  tearDown(() async => db.close());

  SyncEngine moteur(Map<String, dynamic> push) => SyncEngine(
    database: db,
    client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
      ..interceptors.add(_Serveur(push)),
    deviceId: 'poste-test',
    connectivity: _Connectivite(),
  );

  Future<void> refus(String table, String id, [String raison = 'Refus.']) => db
      .into(db.syncConflicts)
      .insert(
        SyncConflictsCompanion.insert(
          id: '$table:$id',
          sourceTable: table,
          recordId: id,
          reason: raison,
          detectedAt: DateTime(2026, 10, 9),
        ),
      );

  Future<List<String>> refusOuverts() async => [
    for (final c in await db.select(db.syncConflicts).get()) c.id,
  ];

  Future<void> courrier(
    String cle, {
    SyncStatus statut = SyncStatus.synced,
    bool connu = true,
  }) => db
      .into(db.mails)
      .insert(
        MailsCompanion.insert(
          id: uuid(cle),
          type: 'entrant',
          subject: 'Objet',
          party: const Value('Partie'),
          mailDate: Value(DateTime(2026, 7, 14)),
          syncStatus: Value(statut),
          knownByServer: Value(connu),
        ),
      );

  Future<void> document(
    String cle, {
    SyncStatus statut = SyncStatus.synced,
    bool connu = true,
  }) => db
      .into(db.archivedDocuments)
      .insert(
        ArchivedDocumentsCompanion.insert(
          id: uuid(cle),
          title: 'Titre',
          category: const Value('Fiscal'),
          archivedDate: Value(DateTime(2026, 1, 2)),
          syncStatus: Value(statut),
          knownByServer: Value(connu),
        ),
      );

  final saisieCourrier = FormulaireCourrier(
    type: 'entrant',
    objet: 'Objet corrigé',
    partie: 'Partie',
    date: DateTime(2026, 7, 14),
  );
  final saisieArchive = FormulaireArchive(
    titre: 'Titre corrigé',
    categorie: 'Fiscal',
    dateArchivage: DateTime(2026, 1, 2),
  );

  group('refusé → corrigé', () {
    test('⚠️ un courrier corrigé n’a plus de refus ouvert', () async {
      await courrier('c1', statut: SyncStatus.conflict);
      await refus('mails', uuid('c1'));

      await depot.modifierCourrier(uuid('c1'), saisieCourrier);

      expect(await refusOuverts(), isEmpty);
    });

    test('⚠️ un document archivé corrigé n’a plus de refus ouvert', () async {
      await document('d1', statut: SyncStatus.conflict);
      await refus('archived_documents', uuid('d1'));

      await depot.modifierArchive(uuid('d1'), saisieArchive);

      expect(await refusOuverts(), isEmpty);
    });
  });

  group('refusé → corrigé → accepté', () {
    test('⚠️ courrier : synced ET plus aucun refus', () async {
      await courrier('c1', statut: SyncStatus.pending);
      await refus(
        'mails',
        uuid('c1'),
      ); // refus périmé resté d'avant la correction

      await moteur({
        'mails': {
          'accepted': [uuid('c1')],
          'rejected': [],
        },
      }).synchroniser();

      expect(
        (await db.select(db.mails).getSingle()).syncStatus,
        SyncStatus.synced,
      );
      expect(await refusOuverts(), isEmpty);
    });

    test('⚠️ document archivé : synced ET plus aucun refus', () async {
      await document('d1', statut: SyncStatus.pending);
      await refus('archived_documents', uuid('d1'));

      await moteur({
        'archived_documents': {
          'accepted': [uuid('d1')],
          'rejected': [],
        },
      }).synchroniser();

      expect(await refusOuverts(), isEmpty);
    });

    test('⚠️ toute table passant par _acquitter (client) est purgée', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: uuid('k1'),
              name: 'Client',
              syncStatus: const Value(SyncStatus.pending),
            ),
          );
      await refus('customers', uuid('k1'));

      await moteur({
        'customers': {
          'accepted': [uuid('k1')],
          'rejected': [],
        },
      }).synchroniser();

      expect(await refusOuverts(), isEmpty);
    });

    test('⚠️ un REJET du même envoi garde son refus tout neuf', () async {
      await courrier('c1', statut: SyncStatus.pending);
      await refus('mails', uuid('c1'), 'Ancien refus.');

      await moteur({
        'mails': {
          'accepted': [],
          'rejected': [
            {'id': uuid('c1'), 'reason': 'Nouveau refus.'},
          ],
        },
      }).synchroniser();

      final c = await db.select(db.syncConflicts).getSingle();
      expect(c.reason, 'Nouveau refus.');
    });
  });

  group('conflit → retrait', () {
    test(
      '⚠️ document connu en conflit, retiré : plus de refus orphelin',
      () async {
        await document('d1', statut: SyncStatus.conflict);
        await refus('archived_documents', uuid('d1'));

        expect(await depot.retirerArchive(uuid('d1')), isTrue);

        final d = await db.select(db.archivedDocuments).getSingle();
        expect(d.isActive, isFalse);
        expect(d.syncStatus, SyncStatus.pending);
        expect(await refusOuverts(), isEmpty);
      },
    );

    test(
      '⚠️ courrier connu en conflit, archivé : plus de refus orphelin',
      () async {
        await courrier('c1', statut: SyncStatus.conflict);
        await refus('mails', uuid('c1'));

        expect(await depot.archiverCourrier(uuid('c1')), isTrue);

        final c = await db.select(db.mails).getSingle();
        expect(c.isActive, isFalse);
        expect(c.syncStatus, SyncStatus.pending);
        expect(await refusOuverts(), isEmpty);
      },
    );
  });

  group('le refus d’un AUTRE enregistrement n’est jamais purgé', () {
    test(
      '⚠️ corriger, retirer ou faire accepter l’un garde le refus de l’autre',
      () async {
        await courrier('c1', statut: SyncStatus.pending);
        await courrier('c2', statut: SyncStatus.conflict);
        await document('d1', statut: SyncStatus.pending);
        await document('d2', statut: SyncStatus.conflict);
        await refus('mails', uuid('c1'));
        await refus('mails', uuid('c2'));
        await refus('archived_documents', uuid('d1'));
        await refus('archived_documents', uuid('d2'));

        await depot.modifierCourrier(uuid('c1'), saisieCourrier);
        await depot.modifierArchive(uuid('d1'), saisieArchive);
        await depot.archiverCourrier(uuid('c1'));
        await depot.retirerArchive(uuid('d1'));

        expect(
          await refusOuverts(),
          unorderedEquals([
            'mails:${uuid('c2')}',
            'archived_documents:${uuid('d2')}',
          ]),
        );
      },
    );

    test(
      '⚠️ l’acceptation de l’un garde le refus de l’autre, même table, même id sur une autre table',
      () async {
        await courrier('c1', statut: SyncStatus.pending);
        await courrier('c2', statut: SyncStatus.conflict);
        await document(
          'c1',
          statut: SyncStatus.conflict,
        ); // même id, autre table
        await refus('mails', uuid('c1'));
        await refus('mails', uuid('c2'));
        await refus('archived_documents', uuid('c1'));

        await moteur({
          'mails': {
            'accepted': [uuid('c1')],
            'rejected': [],
          },
        }).synchroniser();

        expect(
          await refusOuverts(),
          unorderedEquals([
            'mails:${uuid('c2')}',
            'archived_documents:${uuid('c1')}',
          ]),
        );
      },
    );
  });
}
