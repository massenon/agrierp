import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/sync/synchronisation_automatique.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket S-T1 (méthode TATACORA, `docs/COMPARAISON_METHODE_TATACORA.md` §4) — RÉACTION AUX RÉPONSES DU SERVEUR.
///
/// 🔴 Avant : une 422 ou une 413 sur un LOT ENTIER refusait les 49 lignes saines avec la fautive, à chaque
/// tentative, sans jamais dire laquelle ; une 5xx n'était pas réessayée. Désormais le lot est coupé en deux jusqu'à
/// isoler la ligne fautive (en `conflict`, motif français), et une 5xx est réessayée comme un échec réseau.
///
/// ⚠️⚠️ La coupe ne passe JAMAIS au milieu d'une journée couplée (fiches, transferts et ventes d'un même jour,
/// H13b) : une vente séparée de sa fiche est comptée deux fois par le serveur (15.30), sans aucune erreur.
void main() {
  group('S-T1 — 422 / 413 : le lot est coupé en deux', () {
    Map<String, dynamic> fiche(String id, String jour) => {'id': id, 'lot_id': 'L', 'entry_date': jour};
    Map<String, dynamic> vente(String id, String jour) => {'id': id, 'sold_at': '$jour 10:15:00'};
    Map<String, dynamic> transfert(String id, String jour) => {'id': id, 'transfer_date': jour};

    String? jourDe(Object? l) {
      if (l is! Map) return null;
      final d = (l['entry_date'] ?? l['transfer_date'] ?? l['sold_at'])?.toString();
      return d?.substring(0, 10);
    }

    const couplees = ['livestock_daily_entries', 'livestock_transfers', 'sales'];

    test('🔴 une journée couplée n est JAMAIS coupée ; seule la journée fautive passe en refus, entière', () async {
      final jours = [for (var j = 1; j <= 6; j++) '2026-10-0$j'];
      final envoi = <String, dynamic>{
        'device_id': 'poste',
        'livestock_daily_entries': [
          for (final j in jours)
            for (var b = 0; b < 3; b++) fiche('f$j-$b', j),
        ],
        'livestock_transfers': [for (final j in jours) transfert('t$j', j)],
        'sales': [
          for (final j in jours.reversed)
            for (var v = 0; v < 2; v++) vente('v$j-$v', j),
        ],
        'expenses': [for (var i = 0; i < 8; i++) {'id': 'd$i'}],
      };
      final parJour = <String, Set<String>>{};
      for (final t in couplees) {
        for (final l in envoi[t] as List) {
          parJour.putIfAbsent(jourDe(l)!, () => {}).add(l['id'] as String);
        }
      }

      final envois = <Map<String, dynamic>>[];
      final reponses = <Map<String, dynamic>>[];
      await SyncEngine.envoyerEnIsolant(
        envoi,
        (lot) async {
          envois.add(lot);
          // Le serveur refuse le lot ENTIER dès qu'il contient la vente fautive du 3.
          if ((lot['sales'] as List? ?? const []).any((v) => v['id'] == 'v2026-10-03-1')) {
            throw _reponse(422, {'message': 'Le champ mode de paiement est invalide.'}, lot);
          }
          return _accepterTout(lot);
        },
        reponses.add,
      );

      expect(envois.length, greaterThan(2), reason: 'le lot a bien été coupé');
      for (final lot in envois) {
        final presents = <String, Set<String>>{};
        for (final t in couplees) {
          for (final l in (lot[t] as List?) ?? const []) {
            presents.putIfAbsent(jourDe(l)!, () => {}).add(l['id'] as String);
          }
        }
        for (final MapEntry(key: jour, value: ids) in presents.entries) {
          expect(ids, parJour[jour], reason: 'journée $jour coupée dans un lot envoyé');
        }
        expect(lot['device_id'], 'poste', reason: 'l en-tête accompagne chaque moitié');
      }

      final fusion = <String, dynamic>{};
      for (final r in reponses) {
        SyncEngine.fusionnerReponse(fusion, r);
      }
      final refuses = {
        for (final t in fusion.keys)
          for (final r in (fusion[t]['rejected'] as List)) r['id'] as String,
      };
      final acceptes = {
        for (final t in fusion.keys) ...(fusion[t]['accepted'] as List).cast<String>(),
      };
      expect(refuses, parJour['2026-10-03'], reason: 'la journée fautive, entière, et rien d autre');
      final tout = {
        for (final t in [...couplees, 'expenses'])
          for (final l in envoi[t] as List) l['id'] as String,
      };
      expect(acceptes, tout.difference(parJour['2026-10-03']!));
      for (final t in couplees) {
        for (final r in (fusion[t]['rejected'] as List)) {
          expect(
            r['reason'],
            'Refusée par le serveur : requête invalide (422) — Le champ mode de paiement est invalide.',
          );
        }
      }
    });

    test('413 : des lots plus petits, jusqu à passer ; une ligne seule encore trop grosse est refusée', () async {
      final envoi = <String, dynamic>{
        'device_id': 'poste',
        'expenses': [
          for (var i = 0; i < 50; i++) {'id': 'd$i', 'label': i == 30 ? 'x' * 5000 : 'Dépense $i'},
        ],
      };
      final passes = <int>[];
      final reponses = <Map<String, dynamic>>[];
      await SyncEngine.envoyerEnIsolant(
        envoi,
        (lot) async {
          final lignes = lot['expenses'] as List;
          final taille = lignes.fold<int>(0, (n, l) => n + (l['label'] as String).length);
          if (lignes.length > 12 || taille > 4000) throw _reponse(413, '<html>Request Entity Too Large</html>', lot);
          passes.add(lignes.length);
          return _accepterTout(lot);
        },
        reponses.add,
      );

      expect(passes.every((n) => n <= 12), isTrue);
      final fusion = <String, dynamic>{};
      for (final r in reponses) {
        SyncEngine.fusionnerReponse(fusion, r);
      }
      expect((fusion['expenses']['accepted'] as List), hasLength(49));
      expect(fusion['expenses']['rejected'], [
        {'id': 'd30', 'reason': 'Refusée par le serveur : envoi trop volumineux (413).'},
      ]);
    });

    test('toute autre erreur pendant la coupe remonte telle quelle (réseau, 5xx, 401…)', () async {
      final envoi = <String, dynamic>{
        'expenses': [for (var i = 0; i < 4; i++) {'id': 'd$i'}],
      };
      var appels = 0;
      await expectLater(
        SyncEngine.envoyerEnIsolant(envoi, (lot) async {
          appels++;
          if (appels == 1) throw _reponse(422, null, lot);
          throw _reponse(500, null, lot);
        }, (_) {}),
        throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statut', 500)),
      );
    });

    test('refus fabriqué : motif sans message du serveur, chaque ligne sous sa table', () {
      expect(
        SyncEngine.refusDUnite(
          [('livestock_daily_entries', {'id': 'f1'}), ('sales', {'id': 'v1'})],
          422,
          {'message': '  '},
        ),
        {
          'livestock_daily_entries': {
            'accepted': <Object?>[],
            'rejected': [
              {'id': 'f1', 'reason': 'Refusée par le serveur : requête invalide (422).'},
            ],
          },
          'sales': {
            'accepted': <Object?>[],
            'rejected': [
              {'id': 'v1', 'reason': 'Refusée par le serveur : requête invalide (422).'},
            ],
          },
        },
      );
    });
  });

  group('S-T1 — moteur', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> depenses(int n, {int? fautive}) async {
      for (var i = 0; i < n; i++) {
        await db.into(db.expenses).insert(
              ExpensesCompanion.insert(
                id: '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
                deviceId: 'poste-test',
                updatedAt: DateTime(2026, 10, 6),
                expenseDate: DateTime(2026, 10, 6),
                label: i == fautive ? 'FAUTIVE' : 'Dépense $i',
                category: 'Carburant',
                amount: 1000,
                treasuryAccountId: 'caisse',
              ),
            );
      }
    }

    Future<List<Expense>> parStatut(SyncStatus s) =>
        (db.select(db.expenses)..where((t) => t.syncStatus.equalsValue(s))).get();

    test('🔴 422 sur un lot de 50 dont une ligne fautive : 49 acceptées, 1 en conflit avec son motif', () async {
      await depenses(50, fautive: 17);
      final serveur = _Serveur((lot) {
        final lignes = (lot['expenses'] as List?) ?? const [];
        if (lignes.any((d) => d['label'] == 'FAUTIVE')) {
          return (422, {'message': 'Le champ libellé contient un caractère interdit.', 'errors': {}});
        }
        return null;
      });

      final r = await _moteur(db, serveur).synchroniser();

      expect(r.accepte, 49);
      expect(r.rejete, 1);
      expect(await parStatut(SyncStatus.synced), hasLength(49));
      final conflit = await parStatut(SyncStatus.conflict);
      expect(conflit.single.label, 'FAUTIVE');
      final motif = (await db.select(db.syncConflicts).getSingle()).reason;
      expect(motif, 'Refusée par le serveur : requête invalide (422) — Le champ libellé contient un caractère interdit.');
      expect(r.motifs, [motif]);
      // 1 lot entier, puis deux moitiés par niveau jusqu'à la ligne seule : log2(50) ≈ 6 niveaux.
      expect(serveur.envois.length, lessThanOrEqualTo(1 + 2 * 6));
    });

    test('413 sur 120 dépenses : des lots plus petits, toutes acquittées, rien en conflit', () async {
      await depenses(120);
      final serveur = _Serveur((lot) => ((lot['expenses'] as List?) ?? const []).length > 20 ? (413, null) : null);

      final r = await _moteur(db, serveur).synchroniser();

      expect(r.accepte, 120);
      expect(r.rejete, 0);
      expect(await parStatut(SyncStatus.synced), hasLength(120));
      expect(serveur.acceptes.every((n) => n <= 20), isTrue, reason: '${serveur.acceptes}');
    });

    test('5xx : l erreur remonte, réessayable ; rien n est perdu ni marqué', () async {
      await depenses(3);
      final serveur = _Serveur((_) => (500, {'message': 'Server Error'}));

      Object? erreur;
      try {
        await _moteur(db, serveur).synchroniser();
      } catch (e) {
        erreur = e;
      }
      expect(erreur, isA<DioException>());
      expect(SynchronisationAutomatique.estReessayable(erreur!), isTrue);
      expect(SynchronisationAutomatique.estEchecReseau(erreur), isFalse);
      expect(await parStatut(SyncStatus.pending), hasLength(3));
    });

    for (final statut in [401, 403]) {
      test('$statut : refus nommé (EchecSynchronisation), session refusée, saisies gardées', () async {
        await depenses(2);
        final serveur = _Serveur((_) => (statut, null), auTirage: true);

        await expectLater(
          _moteur(db, serveur).synchroniser(),
          throwsA(
            isA<EchecSynchronisation>()
                .having((e) => e.statut, 'statut', statut)
                .having((e) => e.estSessionRefusee, 'session refusée', isTrue)
                .having((e) => SynchronisationAutomatique.estReessayable(e), 'réessayable', isFalse),
          ),
        );
        expect(await parStatut(SyncStatus.pending), hasLength(2));
      });
    }
  });
}

DioException _reponse(int statut, Object? corps, Map<String, dynamic> lot) {
  final options = RequestOptions(path: '/api/sync/push', data: lot);
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: statut, data: corps),
  );
}

Map<String, dynamic> _accepterTout(Map<String, dynamic> lot) => {
  for (final MapEntry(:key, :value) in lot.entries)
    if (value is List) key: {'accepted': [for (final l in value) l['id']], 'rejected': <Object?>[]},
};

SyncEngine _moteur(AppDatabase db, _Serveur serveur) {
  final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur);
  return SyncEngine(database: db, client: client, deviceId: 'poste-test', connectivity: _EnLigne());
}

/// Serveur feint : [refuser] rend (statut, corps) pour refuser le lot ENTIER, `null` pour tout accepter.
/// [auTirage] : la même réponse dès le tirage.
class _Serveur extends Interceptor {
  _Serveur(this.refuser, {this.auTirage = false});

  final (int, Object?)? Function(Map<String, dynamic> lot) refuser;
  final bool auTirage;
  final List<Map<String, dynamic>> envois = [];

  /// Nombre de lignes de chaque envoi accepté.
  final List<int> acceptes = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.path.contains('push')) {
      final refus = auTirage ? refuser(const {}) : null;
      if (refus != null) {
        handler.reject(_rejet(options, refus));
        return;
      }
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: <String, dynamic>{}));
      return;
    }
    final corps = options.data as Map<String, dynamic>;
    envois.add(corps);
    final refus = refuser(corps);
    if (refus != null) {
      handler.reject(_rejet(options, refus));
      return;
    }
    acceptes.add(((corps['expenses'] as List?) ?? const []).length);
    handler.resolve(Response(requestOptions: options, statusCode: 200, data: _accepterTout(corps)));
  }

  DioException _rejet(RequestOptions options, (int, Object?) refus) => DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: refus.$1, data: refus.$2),
  );
}

class _EnLigne implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}
