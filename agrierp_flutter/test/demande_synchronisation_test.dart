import 'dart:async';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/sync/synchronisation_automatique.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket S-T6 (méthode TATACORA) — « Demander la synchronisation des postes » : le web dépose une demande, la
/// session ouverte du poste l'interroge toutes les 30 s (`GET /api/sync/demande`) et synchronise si elle l'y trouve.
///
/// ⚠️ Horloge simulée de `testWidgets` : 30 s s'écoulent en une ligne, et une minuterie oubliée en fin de test fait
/// échouer le test — ce qui vérifie aussi `arreter()`.
class _Serveur extends Interceptor {
  _Serveur(this.reponse);

  /// `null` : liaison coupée ; un entier : statut d'erreur HTTP ; une table : corps de la réponse 200.
  Object? Function() reponse;
  final chemins = <String>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    chemins.add(options.path);
    final r = reponse();
    if (r == null) {
      handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError));
    } else if (r is int) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: r, data: {'message': 'Non authentifié.'}),
        ),
      );
    } else {
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: r));
    }
  }
}

class _EnLigne implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

void main() {
  const aboutie = SyncOutcome(tire: 1, accepte: 0, rejete: 0);

  late StreamController<List<ConnectivityResult>> reseau;
  late int synchronisations;
  late int questions;

  setUp(() {
    reseau = StreamController<List<ConnectivityResult>>.broadcast();
    synchronisations = 0;
    questions = 0;
  });
  tearDown(() => reseau.close());

  SynchronisationAutomatique automatique(Future<bool> Function() demande) => SynchronisationAutomatique(
    synchroniser: () async {
      synchronisations++;
      return aboutie;
    },
    changementsReseau: reseau.stream,
    // L'intervalle ordinaire est repoussé loin : seul le déclencheur S-T6 est éprouvé ici.
    intervalle: const Duration(hours: 6),
    demandeDuServeur: () {
      questions++;
      return demande();
    },
  );

  group('S-T6 — la session interroge le serveur toutes les 30 s', () {
    testWidgets('🔴 session refusée (401 / 403, S-T1) : plus aucune question au serveur', (t) async {
      final a = SynchronisationAutomatique(
        synchroniser: () async {
          synchronisations++;
          throw const EchecSynchronisation('Session expirée : reconnectez-vous.', statut: 401);
        },
        changementsReseau: reseau.stream,
        intervalle: const Duration(hours: 6),
        demandeDuServeur: () async {
          questions++;
          return true;
        },
      )..demarrer();

      await t.pump(const Duration(seconds: 30));
      expect((questions, synchronisations), (1, 1));
      expect(a.suspendue, isTrue);

      await t.pump(const Duration(minutes: 5));
      expect(questions, 1, reason: 'suspendue : la question serait refusée elle aussi');
      a.arreter();
    });

    testWidgets('demande trouvée : une synchronisation ; pas de demande : aucune', (t) async {
      var demandes = [false, true, false];
      final a = automatique(() async => demandes.removeAt(0))..demarrer();

      await t.pump(const Duration(seconds: 29));
      expect(questions, 0, reason: 'la première question part à 30 s');

      await t.pump(const Duration(seconds: 1));
      expect((questions, synchronisations), (1, 0));

      await t.pump(const Duration(seconds: 30));
      expect((questions, synchronisations), (2, 1), reason: 'le serveur a demandé : synchronisation');

      await t.pump(const Duration(seconds: 30));
      expect((questions, synchronisations), (3, 1), reason: 'demande déjà servie : rien de plus');
      demandes = [];
      a.arreter();
    });

    testWidgets('hors ligne : la question n\'est pas posée ; au retour, elle reprend', (t) async {
      final a = automatique(() async => true)..demarrer();
      reseau.add([ConnectivityResult.none]);
      await t.pump();

      await t.pump(const Duration(seconds: 90));
      expect(questions, 0, reason: 'hors ligne, aucune question au serveur');

      reseau.add([ConnectivityResult.wifi]);
      await t.pump();
      expect(synchronisations, 1, reason: 'le retour du réseau synchronise (H13)');

      await t.pump(const Duration(seconds: 30));
      expect((questions, synchronisations), (1, 2));
      a.arreter();
    });

    testWidgets('⚠️ une question en échec est silencieuse : ni synchronisation, ni réessai programmé', (t) async {
      final a = automatique(() async => throw StateError('serveur muet'))..demarrer();

      await t.pump(const Duration(seconds: 30));
      expect((questions, synchronisations), (1, 0));
      expect(a.reessaiProgramme, isNull);
      expect(a.echecsConsecutifs, 0);

      await t.pump(const Duration(seconds: 30));
      expect(questions, 2, reason: 'la question revient d\'elle-même');
      a.arreter();
    });

    testWidgets('arrêtée (déconnexion), plus aucune question', (t) async {
      final a = automatique(() async => true)..demarrer();
      a.arreter();

      await t.pump(const Duration(minutes: 5));
      expect(questions, 0);
    });

    testWidgets('sans fonction de demande (tests du châssis) : aucune minuterie de plus', (t) async {
      final a = SynchronisationAutomatique(
        synchroniser: () async => aboutie,
        changementsReseau: reseau.stream,
        intervalle: const Duration(hours: 6),
      )..demarrer();
      await t.pump(const Duration(minutes: 2));
      expect(questions, 0);
      a.arreter();
    });

    test('l\'intervalle de la question est de 30 s', () {
      expect(SynchronisationAutomatique.intervalleDemande, const Duration(seconds: 30));
    });
  });

  group('S-T6 — SyncEngine.demandeDuServeur', () {
    late AppDatabase db;
    late _Serveur serveur;
    late SyncEngine engine;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      serveur = _Serveur(() => {'demande': false});
      engine = SyncEngine(
        database: db,
        client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur),
        deviceId: 'poste-test',
        connectivity: _EnLigne(),
      );
    });
    tearDown(() => db.close());

    test('lit GET /api/sync/demande', () async {
      serveur.reponse = () => {'demande': true, 'demandee_le': '2026-10-19T10:00:00+01:00', 'demandee_par': 'Admin'};
      expect(await engine.demandeDuServeur(), isTrue);
      expect(serveur.chemins, ['/api/sync/demande']);

      serveur.reponse = () => {'demande': false};
      expect(await engine.demandeDuServeur(), isFalse);
    });

    test('⚠️ liaison coupée, session expirée, erreur serveur, réponse inattendue : « pas de demande », sans lever', () async {
      for (final r in <Object? Function()>[() => null, () => 401, () => 500, () => <String, dynamic>{}, () => {'demande': 'oui'}]) {
        serveur.reponse = r;
        expect(await engine.demandeDuServeur(), isFalse);
      }
    });
  });
}
