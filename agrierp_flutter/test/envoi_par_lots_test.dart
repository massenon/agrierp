import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket H13b (décision D-SYNC-2) — ENVOI PAR LOTS DE 50.
///
/// ⚠️⚠️ Ce que ces tests verrouillent ne lève aucune erreur côté serveur : une fiche partie dans un lot
/// ANTÉRIEUR à la vente du même jour fait compter la vente deux fois (15.30, 2N), et un lot en échec après
/// d'autres ferait renvoyer ce que le serveur a déjà écrit.
void main() {
  Map<String, dynamic> fiche(String id, String jour) => {'id': id, 'lot_id': 'L', 'entry_date': jour};
  Map<String, dynamic> vente(String id, String jour) => {'id': id, 'sold_at': '$jour 10:15:00'};
  Map<String, dynamic> transfert(String id, String jour) => {'id': id, 'transfer_date': jour};
  Map<String, dynamic> ligne(String id) => {'id': id};

  int lignes(Map<String, dynamic> lot) => lot.values.whereType<List>().fold(0, (n, l) => n + l.length);

  group('H13b — découpage', () {
    test('50 lignes ou moins : l envoi part TEL QUEL, en une requête', () {
      final envoi = {
        'device_id': 'poste',
        'sales': [for (var i = 0; i < 30; i++) vente('v$i', '2026-10-01')],
        'expenses': [for (var i = 0; i < 20; i++) ligne('d$i')],
        'products': <Object?>[],
      };
      final lots = SyncEngine.decouperEnLots(envoi);
      expect(lots, hasLength(1));
      expect(identical(lots.single, envoi), isTrue);
    });

    test('au-delà : lots de 50 au plus, rien de perdu, en-tête dans chaque lot', () {
      final envoi = {
        'device_id': 'poste',
        'data_reset_at': '2026-10-17T10:00:00Z',
        'expenses': [for (var i = 0; i < 70; i++) ligne('d$i')],
        'products': [for (var i = 0; i < 45; i++) ligne('p$i')],
        'customers': <Object?>[],
      };
      final lots = SyncEngine.decouperEnLots(envoi);

      expect(lots.map(lignes), [50, 50, 15]);
      for (final lot in lots) {
        expect(lot['device_id'], 'poste');
        expect(lot['data_reset_at'], '2026-10-17T10:00:00Z');
        expect(lot.containsKey('customers'), isFalse, reason: 'une table vide ne part pas');
      }
      expect([for (final l in lots) ...?(l['expenses'] as List?)], envoi['expenses']);
      expect([for (final l in lots) ...?(l['products'] as List?)], envoi['products']);
    });

    test('les lots suivent l ordre de traitement du serveur : un produit avant la dépense, un achat avant son retour',
        () {
      final envoi = {
        'device_id': 'poste',
        'purchase_returns': [for (var i = 0; i < 30; i++) ligne('r$i')],
        'purchases': [for (var i = 0; i < 30; i++) ligne('a$i')],
        'products': [for (var i = 0; i < 30; i++) ligne('p$i')],
      };
      final ordre = [
        for (final lot in SyncEngine.decouperEnLots(envoi))
          for (final t in ['products', 'purchases', 'purchase_returns'])
            for (final _ in (lot[t] as List?) ?? const []) t,
      ];
      expect(ordre, [...List.filled(30, 'products'), ...List.filled(30, 'purchases'), ...List.filled(30, 'purchase_returns')]);
    });

    test('🔴 une vente et les fiches de son jour partent TOUJOURS dans le même lot (15.30)', () {
      final jours = [for (var j = 1; j <= 9; j++) '2026-10-0$j'];
      final envoi = {
        'device_id': 'poste',
        // Fiches dans l'ordre des jours (F0.89), ventes dans le désordre de leur saisie.
        'livestock_daily_entries': [
          for (final j in jours)
            for (var b = 0; b < 4; b++) fiche('f$j-$b', j),
        ],
        'livestock_transfers': [for (final j in jours) transfert('t$j', j)],
        'sales': [
          for (final j in jours.reversed)
            for (var v = 0; v < 3; v++) vente('v$j-$v', j),
        ],
        'expenses': [for (var i = 0; i < 20; i++) ligne('d$i')],
      };
      final lots = SyncEngine.decouperEnLots(envoi);
      expect(lots.length, greaterThan(1));

      for (final j in jours) {
        final porteurs = [
          for (var i = 0; i < lots.length; i++)
            if ([
              ...?(lots[i]['livestock_daily_entries'] as List?),
              ...?(lots[i]['livestock_transfers'] as List?),
              ...?(lots[i]['sales'] as List?),
            ].any((l) => (l['entry_date'] ?? l['transfer_date'] ?? l['sold_at'] as String).startsWith(j)))
              i,
        ];
        expect(porteurs, hasLength(1), reason: 'journée $j coupée entre les lots $porteurs');
      }

      // Les journées partent dans l'ordre des jours : la veille est écrite avant le lendemain.
      final fichesDansLOrdre = [for (final l in lots) ...?(l['livestock_daily_entries'] as List?)];
      expect(fichesDansLOrdre, envoi['livestock_daily_entries']);
      for (final lot in lots) {
        expect(lignes(lot), lessThanOrEqualTo(SyncEngine.tailleLot));
      }
    });

    test('une journée de plus de 50 lignes part seule, entière', () {
      final envoi = {
        'device_id': 'poste',
        'livestock_daily_entries': [for (var b = 0; b < 40; b++) fiche('f$b', '2026-10-05')],
        'sales': [for (var v = 0; v < 25; v++) vente('v$v', '2026-10-05')],
        'products': [for (var i = 0; i < 10; i++) ligne('p$i')],
      };
      final lots = SyncEngine.decouperEnLots(envoi);
      expect(lots.map(lignes), [10, 65]);
      expect((lots.last['sales'] as List), hasLength(25));
    });

    test('chaque table envoyée par le poste a son rang dans l ordre du serveur', () {
      // Les clés de `_pousser` ; une table oubliée partirait en dernier, après ce qui peut dépendre d'elle.
      final source = RegExp(r"^\s+(?:if \([a-z]+\.isNotEmpty\)\s+)?'([a-z_]+)': ", multiLine: true);
      final moteur = _sourceDuMoteur();
      final debut = moteur.indexOf('_envoyerParLots({');
      final fin = moteur.indexOf('});', debut);
      final cles = source.allMatches(moteur.substring(debut, fin)).map((m) => m.group(1)!).toSet()
        ..removeAll({'device_id', 'data_reset_at'});
      expect(cles.length, greaterThan(20));
      expect(cles.difference(SyncEngine.ordreDuServeur.toSet()), isEmpty);
    });
  });

  group('H13b — fusion des réponses', () {
    test('acceptés et refusés mis bout à bout, compteurs additionnés', () {
      final fusion = <String, dynamic>{};
      SyncEngine.fusionnerReponse(fusion, {
        'expenses': {'accepted': ['a'], 'rejected': []},
        'referentiels_ignored': 2,
        'cles_invalides': ['x'],
      });
      SyncEngine.fusionnerReponse(fusion, {
        'expenses': {
          'accepted': ['b'],
          'rejected': [
            {'id': 'c', 'reason': 'motif'},
          ],
        },
        'sales': {'accepted': ['v'], 'rejected': []},
        'referentiels_ignored': 1,
        'cles_invalides': ['y'],
      });
      expect(fusion['expenses'], {
        'accepted': ['a', 'b'],
        'rejected': [
          {'id': 'c', 'reason': 'motif'},
        ],
      });
      expect(fusion['sales'], {'accepted': ['v'], 'rejected': []});
      expect(fusion['referentiels_ignored'], 3);
      expect(fusion['cles_invalides'], ['x', 'y']);
    });
  });

  group('H13b — moteur', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> depenses(int n) async {
      for (var i = 0; i < n; i++) {
        await db.into(db.expenses).insert(
              ExpensesCompanion.insert(
                id: '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
                deviceId: 'poste-test',
                updatedAt: DateTime(2026, 10, 6),
                expenseDate: DateTime(2026, 10, 6),
                label: 'Dépense $i',
                category: 'Carburant',
                amount: 1000,
                treasuryAccountId: Value('caisse'),
              ),
            );
      }
    }

    Future<int> enAttente() async =>
        (await (db.select(db.expenses)..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get()).length;

    test('120 dépenses en attente : trois requêtes, toutes acquittées', () async {
      await depenses(120);
      final serveur = _Serveur();
      final r = await _moteur(db, serveur).synchroniser();

      expect(serveur.envois.map((e) => (e['expenses'] as List).length), [50, 50, 20]);
      expect(r.accepte, 120);
      expect(await enAttente(), 0);
    });

    test('🔴 un lot en échec réseau : les lots accusés sont acquittés, le reste attend, l échec remonte', () async {
      await depenses(120);
      final serveur = _Serveur(echecAuLot: 2);

      await expectLater(
        _moteur(db, serveur).synchroniser(),
        throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.connectionError)),
      );
      expect(serveur.envois, hasLength(2));
      expect(await enAttente(), 70, reason: 'les 50 du premier lot sont écrits au serveur : ils ne repartent pas');
    });
  });
}

String _sourceDuMoteur() => File('lib/core/sync/sync_engine.dart').readAsStringSync();

SyncEngine _moteur(AppDatabase db, _Serveur serveur) {
  final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur);
  return SyncEngine(database: db, client: client, deviceId: 'poste-test', connectivity: _EnLigne());
}

/// Serveur feint : accepte toute dépense reçue ; échoue (liaison coupée) au lot [echecAuLot] (1 = premier).
class _Serveur extends Interceptor {
  _Serveur({this.echecAuLot});

  final int? echecAuLot;
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.path.contains('push')) {
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: <String, dynamic>{}));
      return;
    }
    final corps = options.data as Map<String, dynamic>;
    envois.add(corps);
    if (envois.length == echecAuLot) {
      handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError));
      return;
    }
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{
          'expenses': {
            'accepted': [for (final d in (corps['expenses'] as List?) ?? const []) d['id']],
            'rejected': [],
          },
        },
      ),
    );
  }
}

class _EnLigne implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}
