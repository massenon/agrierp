import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/parametres/corbeille_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket ARC3 — LA CORBEILLE DANS LA SYNCHRONISATION DU POSTE.
///
/// ⚠️⚠️ L'ENVOI : le poste n'envoie que la DEMANDE (`corbeille_demandes` : type, élément, action, mot saisi) — jamais
/// `is_active`, jamais une suppression ; le serveur répond table par table, l'accusé acquitte, le refus passe en `conflict`
/// AVEC son motif et se relance. LE TIRAGE : `corbeille` est un INSTANTANÉ remplacé en entier ; l'absorbeur est STRICT
/// (rien n'est écrit si une ligne est illisible) ; les demandes acquittées s'effacent avec l'ancien instantané.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-21T09:00:00Z'};
  final Map<String, String> refus = {};
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [for (final e in value) if (e is Map && e['id'] is String && !refus.containsKey(e['id'])) e['id']],
                  'rejected': [for (final e in value) if (e is Map && refus.containsKey(e['id'])) {'id': e['id'], 'reason': refus[e['id']]}],
                },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late CorbeilleRepository depot;

  const client = 'cccccccc-0000-4000-8000-000000000001';

  String uuid(String graine) => graine.padRight(36, '_').substring(0, 36);

  Map<String, dynamic> ligne(String id, {Object? restaurable = true, Object? motif, Object? titre = 'Kossi Adjovi', Object? archiveLe = '2026-06-20 09:00:00'}) => {
    'id': id,
    'type': 'clients',
    'element_id': client,
    'titre': titre,
    'detail': '+22997000001',
    'module': 'ventes',
    'archive_le': archiveLe,
    'restaurable': restaurable,
    'motif_restauration': motif,
    'supprimable': true,
    'motif_suppression': null,
  };

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime.utc(2026, 10, 21, 9, 30, 5),
    );
    depot = CorbeilleRepository(database: db, identifiantPoste: 'poste-test', horloge: () => DateTime(2026, 10, 21, 10));
    await db.into(db.customers).insert(
      CustomersCompanion.insert(id: client, name: 'Kossi Adjovi', isActive: const Value(false), syncStatus: const Value(SyncStatus.synced)),
    );
  });

  tearDown(() async => db.close());

  Future<void> instantane(String id) => db.into(db.corbeilleElements).insert(
    CorbeilleElementsCompanion.insert(
      id: id, type: 'clients', elementId: client, titre: 'Kossi Adjovi', module: 'ventes', restaurable: true, supprimable: true,
    ),
  );

  group('ENVOI', () {
    test('⚠️⚠️ la demande part avec ses champs — jamais is_active, jamais de suppression — et l\'accusé l\'acquitte', () async {
      await instantane(uuid('i1'));
      await depot.demanderSuppression((await depot.lignes()).single, 'SUPPRIMER');

      await moteur.synchroniser();

      final corps = serveur.envois.single;
      final d = (corps['corbeille_demandes'] as List).single as Map;
      expect(d.keys.toSet(), {'id', 'type', 'element_id', 'action', 'confirmation', 'device_id'});
      expect(d['type'], 'clients');
      expect(d['element_id'], client);
      expect(d['action'], 'supprimer');
      expect(d['confirmation'], 'SUPPRIMER');
      expect(d['device_id'], 'poste-test');
      expect(corps['customers'], isEmpty, reason: 'le client n\'est pas renvoyé : le serveur fait l\'effet');
      expect((await db.select(db.corbeilleDemandes).get()).single.syncStatus, SyncStatus.synced);
      expect((await db.select(db.customers).get()), hasLength(1), reason: 'le poste n\'efface rien lui-même');
    });

    test('sans demande, la clé n\'est pas envoyée', () async {
      await moteur.synchroniser();

      expect(serveur.envois.every((e) => !e.containsKey('corbeille_demandes')), isTrue);
    });

    test('⚠️⚠️ le refus passe la demande en conflict AVEC son motif ; « Relancer » la remet en file', () async {
      await instantane(uuid('i1'));
      await depot.demanderRestauration((await depot.lignes()).single);
      final id = (await db.select(db.corbeilleDemandes).get()).single.id;
      const motif = 'Restauration impossible : élément introuvable ou déjà restauré.';
      serveur.refus[id] = motif;

      await moteur.synchroniser();

      expect((await db.select(db.corbeilleDemandes).get()).single.syncStatus, SyncStatus.conflict);
      final conflit = (await db.select(db.syncConflicts).get()).single;
      expect(conflit.id, 'corbeille_demandes:$id');
      expect(conflit.reason, contains(motif));
      expect((await depot.lignes()).single.refus, contains(motif));

      await moteur.relancer(conflit);
      expect((await db.select(db.corbeilleDemandes).get()).single.syncStatus, SyncStatus.pending);
      serveur.refus.clear();
      await moteur.synchroniser();
      expect((await db.select(db.corbeilleDemandes).get()).single.syncStatus, SyncStatus.synced);
    });

    test('la demande est le DERNIER lot de l\'envoi (après l\'archivage du même paquet)', () {
      expect(SyncEngine.ordreDuServeur.last, 'corbeille_demandes');
    });
  });

  group('TIRAGE : absorbeur de `corbeille`', () {
    test('l\'instantané est absorbé tel quel ; la date est l\'heure murale du serveur', () async {
      serveur.tirage = {'server_time': '2026-10-21T09:00:00Z', 'corbeille': [ligne(uuid('a1')), ligne(uuid('a2'), restaurable: false, motif: 'Parce que.')]};
      // deux lignes d'un même élément seraient refusées : on varie l'élément
      (serveur.tirage['corbeille'] as List)[1]['element_id'] = 'dddddddd-0000-4000-8000-000000000002';

      await moteur.synchroniser();

      final l = await db.select(db.corbeilleElements).get();
      expect(l, hasLength(2));
      final a = l.firstWhere((e) => e.id == uuid('a1'));
      expect(a.archiveLe, DateTime(2026, 6, 20, 9));
      expect(a.restaurable, isTrue);
      final b = l.firstWhere((e) => e.id == uuid('a2'));
      expect((b.restaurable, b.motifRestauration), (false, 'Parce que.'));
    });

    test('⚠️ remplacé EN ENTIER : une liste vide efface, une clé absente ne touche à rien', () async {
      await instantane(uuid('i1'));

      await moteur.synchroniser();
      expect(await db.select(db.corbeilleElements).get(), hasLength(1), reason: 'clé absente (compte sans le droit) : intact');

      serveur.tirage = {'server_time': '2026-10-21T09:05:00Z', 'corbeille': <Object>[]};
      await moteur.synchroniser();
      expect(await db.select(db.corbeilleElements).get(), isEmpty);
    });

    test('les demandes ACQUITTÉES s\'effacent avec l\'ancien instantané ; pending et conflict restent', () async {
      for (final (id, statut) in [('d1', SyncStatus.synced), ('d2', SyncStatus.pending), ('d3', SyncStatus.conflict)]) {
        await db.into(db.corbeilleDemandes).insert(
          CorbeilleDemandesCompanion.insert(
            id: uuid(id), deviceId: 'poste-test', syncStatus: Value(statut), updatedAt: DateTime.utc(2026, 10, 21), type: 'clients', elementId: uuid('e$id'), action: 'restaurer',
          ),
        );
      }
      serveur.tirage = {'server_time': '2026-10-21T09:05:00Z', 'corbeille': <Object>[]};

      await moteur.synchroniser();

      // la demande `pending` est envoyée puis acquittée à son tour : on vérifie seulement la `conflict` et l'effacement de la `synced`
      final restantes = (await db.select(db.corbeilleDemandes).get()).map((d) => d.id).toSet();
      expect(restantes, isNot(contains(uuid('d1'))));
      expect(restantes, contains(uuid('d3')));
    });

    test('⚠️⚠️ STRICT : une ligne illisible refuse le lot, RIEN n\'est écrit (l\'ancien instantané reste)', () async {
      await instantane(uuid('i1'));
      final mauvaises = <String, Map<String, dynamic>>{
        'identifiant invalide': ligne('trop-court'),
        'titre absent': ligne(uuid('a1'), titre: null),
        'drapeau illisible': ligne(uuid('a1'), restaurable: 'oui'),
        'refus sans motif': ligne(uuid('a1'), restaurable: false),
        'date illisible': ligne(uuid('a1'), archiveLe: 'hier'),
      };
      for (final MapEntry(:key, :value) in mauvaises.entries) {
        serveur.tirage = {'server_time': '2026-10-21T09:00:00Z', 'corbeille': [value]};

        await expectLater(moteur.synchroniser(), throwsA(anything), reason: key);

        final l = await db.select(db.corbeilleElements).get();
        expect(l.map((e) => e.id), [uuid('i1')], reason: key);
      }
    });

    test('un élément servi deux fois est refusé', () async {
      serveur.tirage = {'server_time': '2026-10-21T09:00:00Z', 'corbeille': [ligne(uuid('a1')), ligne(uuid('a2'))]};

      await expectLater(moteur.synchroniser(), throwsA(anything));
      expect(await db.select(db.corbeilleElements).get(), isEmpty);
    });
  });
}
