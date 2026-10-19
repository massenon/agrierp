import 'dart:async';
import 'dart:io';

import 'package:agrierp/core/config/parametres_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/sync/synchronisation_automatique.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket H13 (décisions D-SYNC-3 et B2) — synchronisation automatique du poste.
///
/// ⚠️ Les minuteries sont celles de `testWidgets` (temps simulé) : 5 minutes ou une heure s'y écoulent en
/// une ligne, et une minuterie oubliée en fin de test fait échouer le test — ce qui vérifie aussi [arreter].
void main() {
  const aboutie = SyncOutcome(tire: 1, accepte: 0, rejete: 0);
  final reseauCoupe = DioException(
    requestOptions: RequestOptions(path: '/api/sync/pull'),
    type: DioExceptionType.connectionError,
  );

  late StreamController<List<ConnectivityResult>> reseau;
  late List<Duration> appels;
  late Duration ecoule;

  setUp(() {
    reseau = StreamController<List<ConnectivityResult>>.broadcast();
    appels = [];
    ecoule = Duration.zero;
  });
  tearDown(() => reseau.close());

  /// Avance le temps simulé par pas d'une seconde, pour dater chaque tentative.
  Future<void> avancer(WidgetTester t, Duration duree) async {
    final fin = ecoule + duree;
    while (ecoule < fin) {
      ecoule += const Duration(seconds: 1);
      await t.pump(const Duration(seconds: 1));
    }
  }

  SynchronisationAutomatique automatique(
    Future<SyncOutcome> Function() reponse, {
    void Function()? onTermine,
  }) => SynchronisationAutomatique(
    synchroniser: () {
      appels.add(ecoule);
      return reponse();
    },
    changementsReseau: reseau.stream,
    onTermine: onTermine,
  );

  group('H13 — déclencheurs', () {
    testWidgets('le retour du réseau déclenche une synchronisation, une liaison qui reste ne la relance pas', (t) async {
      final a = automatique(() async => aboutie)..demarrer();

      reseau.add([ConnectivityResult.wifi]); // état initial : pas un retour
      await t.pump();
      expect(appels, isEmpty);

      reseau.add([ConnectivityResult.none]);
      await t.pump();
      reseau.add([ConnectivityResult.ethernet]);
      await t.pump();
      expect(appels, hasLength(1));

      reseau.add([ConnectivityResult.wifi]);
      await t.pump();
      expect(appels, hasLength(1), reason: 'une liaison qui change de nature n\'est pas un retour');
      a.arreter();
    });

    testWidgets('toutes les 5 minutes par défaut (S-T3, note TATACORA)', (t) async {
      final a = automatique(() async => aboutie)..demarrer();
      expect(a.intervalle, const Duration(minutes: 5));

      await avancer(t, const Duration(minutes: 11));
      expect(appels, [const Duration(minutes: 5), const Duration(minutes: 10)]);
      a.arreter();
    });

    testWidgets('chaque tentative aboutie relit la barre (onTermine)', (t) async {
      var relectures = 0;
      final a = automatique(() async => aboutie, onTermine: () => relectures++)..demarrer();
      await avancer(t, const Duration(minutes: 5));
      expect(relectures, 1);
      a.arreter();
    });

    testWidgets('arrêtée, plus rien ne part', (t) async {
      final a = automatique(() async => aboutie)..demarrer();
      a.arreter();
      reseau.add([ConnectivityResult.none]);
      reseau.add([ConnectivityResult.wifi]);
      await avancer(t, const Duration(minutes: 20));
      expect(appels, isEmpty);
    });
  });

  group('H13 — réessais', () {
    testWidgets('🔴 échec réseau : réessais à 30 s, 2 min, 5 min, 15 min, puis toutes les heures', (t) async {
      final a = automatique(() async => throw reseauCoupe)..demarrer();

      reseau.add([ConnectivityResult.none]);
      reseau.add([ConnectivityResult.wifi]);
      await t.pump();
      expect(appels, [Duration.zero]);
      expect(a.reessaiProgramme, const Duration(seconds: 30));

      await avancer(t, const Duration(hours: 3));
      // Dates cumulées : 0 → +30 s → +2 min → +5 min → +15 min → +1 h → +1 h. L'intervalle de 5 min ne
      // court-circuite jamais un réessai programmé.
      expect(appels, [
        Duration.zero,
        const Duration(seconds: 30),
        const Duration(minutes: 2, seconds: 30),
        const Duration(minutes: 7, seconds: 30),
        const Duration(minutes: 22, seconds: 30),
        const Duration(hours: 1, minutes: 22, seconds: 30),
        const Duration(hours: 2, minutes: 22, seconds: 30),
      ]);
      expect(a.echecsConsecutifs, 7);
      a.arreter();
    });

    testWidgets('une tentative aboutie remet les réessais à zéro', (t) async {
      var echouer = true;
      final a = automatique(() async => echouer ? throw reseauCoupe : aboutie)..demarrer();
      reseau.add([ConnectivityResult.none]);
      reseau.add([ConnectivityResult.wifi]);
      await avancer(t, const Duration(seconds: 31));
      expect(a.echecsConsecutifs, 2);

      echouer = false;
      await avancer(t, const Duration(minutes: 2));
      expect(a.echecsConsecutifs, 0);
      expect(a.reessaiProgramme, isNull);
      a.arreter();
    });

    testWidgets('⚠️ un REFUS du serveur (4xx) n\'est pas réessayé : seul l\'intervalle relance', (t) async {
      final a = automatique(
        () async => throw const EchecSynchronisation('Trop de synchronisations rapprochées.', statut: 429),
      )..demarrer();
      reseau.add([ConnectivityResult.none]);
      reseau.add([ConnectivityResult.wifi]);
      await t.pump();
      expect(a.reessaiProgramme, isNull);
      expect(a.suspendue, isFalse, reason: 'seuls 401 et 403 arrêtent la synchronisation automatique');

      await avancer(t, const Duration(minutes: 4));
      expect(appels, hasLength(1), reason: 'aucun réessai à 30 s');
      await avancer(t, const Duration(minutes: 1));
      expect(appels, hasLength(2), reason: 'l\'intervalle relance');
      a.arreter();
    });

    testWidgets('⚠️ hors ligne n\'est pas un échec : aucun réessai, le retour du réseau relancera', (t) async {
      final a = automatique(() async => const SyncOutcome.horsLigne())..demarrer();
      reseau.add([ConnectivityResult.none]);
      reseau.add([ConnectivityResult.wifi]);
      await t.pump();
      expect(a.reessaiProgramme, isNull);
      expect(a.echecsConsecutifs, 0);
      a.arreter();
    });

    test('échec réseau ou refus : la distinction', () {
      DioException dio(DioExceptionType type, [Object? erreur]) =>
          DioException(requestOptions: RequestOptions(path: '/'), type: type, error: erreur);

      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        expect(SynchronisationAutomatique.estEchecReseau(dio(type)), isTrue, reason: '$type');
      }
      expect(SynchronisationAutomatique.estEchecReseau(dio(DioExceptionType.unknown, const SocketException('x'))), isTrue);
      expect(SynchronisationAutomatique.estEchecReseau(const SocketException('x')), isTrue);
      expect(SynchronisationAutomatique.estEchecReseau(TimeoutException('x')), isTrue);

      expect(SynchronisationAutomatique.estEchecReseau(dio(DioExceptionType.badResponse)), isFalse);
      expect(SynchronisationAutomatique.estEchecReseau(dio(DioExceptionType.cancel)), isFalse);
      expect(SynchronisationAutomatique.estEchecReseau(dio(DioExceptionType.unknown, StateError('x'))), isFalse);
      expect(SynchronisationAutomatique.estEchecReseau(const EchecSynchronisation('refus')), isFalse);
      expect(SynchronisationAutomatique.estEchecReseau(StateError('bogue')), isFalse);
    });
  });

  group('H13 — fermeture', () {
    test('la synchronisation de fermeture est bornée : un serveur muet ne retient pas l\'utilisateur', () async {
      final a = SynchronisationAutomatique(
        synchroniser: () => Completer<SyncOutcome>().future,
        changementsReseau: const Stream.empty(),
      );
      expect(await a.avantFermeture(delai: const Duration(milliseconds: 20)), isFalse);
    });

    test('aboutie : vrai ; hors ligne ou en échec : faux, sans lever', () async {
      SynchronisationAutomatique avec(Future<SyncOutcome> Function() f) =>
          SynchronisationAutomatique(synchroniser: f, changementsReseau: const Stream.empty());
      expect(await avec(() async => aboutie).avantFermeture(), isTrue);
      expect(await avec(() async => const SyncOutcome.horsLigne()).avantFermeture(), isFalse);
      expect(await avec(() async => throw reseauCoupe).avantFermeture(), isFalse);
    });

    Future<void> barre(WidgetTester t, {required int enAttente, required Future<int> Function() avant}) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarreSuperieure(
              groupe: '',
              ecran: 'Tableau de bord',
              enAttente: enAttente,
              onBasculerMenu: () {},
              avantFermeture: avant,
            ),
          ),
        ),
      );
    }

    testWidgets('fermer envoie d\'abord ce qui attend ; tout parti, aucune confirmation', (t) async {
      final envoi = Completer<int>();
      var envois = 0;
      await barre(t, enAttente: 3, avant: () {
        envois++;
        return envoi.future;
      });

      await t.tap(find.byKey(const Key('fenetre-fermer')));
      await t.pump();
      expect(envois, 1);
      expect(find.text('Synchronisation avant fermeture'), findsOneWidget);
      expect(find.text('Envoi des enregistrements en attente…'), findsOneWidget);

      envoi.complete(0);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('modale-envoi-fermeture')), findsNothing);
      expect(find.byKey(const Key('modale-fermeture')), findsNothing);
    });

    testWidgets('ce qui n\'est pas parti est compté dans la confirmation', (t) async {
      await barre(t, enAttente: 3, avant: () async => 2);

      await t.tap(find.byKey(const Key('fenetre-fermer')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('modale-fermeture')), findsOneWidget);
      expect(find.textContaining('2 enregistrement(s) attendent encore'), findsOneWidget);
    });

    testWidgets('rien en attente : aucune tentative d\'envoi', (t) async {
      var envois = 0;
      await barre(t, enAttente: 0, avant: () async => envois++);
      await t.tap(find.byKey(const Key('fenetre-fermer')));
      await t.pumpAndSettle();
      expect(envois, 0);
    });
  });

  group('H13 — moteur et réglage', () {
    test('⚠️ deux appels simultanés reçoivent la MÊME tentative ; la suivante en ouvre une nouvelle', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final moteur = SyncEngine(
        database: db,
        client: Dio(),
        deviceId: 'poste-test',
        connectivity: _HorsLigne(),
      );

      final premiere = moteur.synchroniser();
      final seconde = moteur.synchroniser();
      expect(identical(premiere, seconde), isTrue);
      expect((await premiere).horsLigne, isTrue);

      expect(identical(moteur.synchroniser(), premiere), isFalse);
    });

    test('intervalle : 5 min par défaut (S-T3), valeur proposée retenue, valeur hors choix ignorée', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final parametres = ParametresPoste(database: db);

      expect(ParametresPoste.intervallesProposes, [5, 15, 30, 60]);
      expect(await parametres.intervalleSynchronisation(), const Duration(minutes: 5));
      expect(
        Duration(minutes: ParametresPoste.intervalleParDefaut),
        SynchronisationAutomatique.intervalleParDefaut,
        reason: 'un seul défaut, au réglage comme au moteur',
      );
      await parametres.definirIntervalleSynchronisation(30);
      expect(await parametres.intervalleSynchronisation(), const Duration(minutes: 30));
      await parametres.definirIntervalleSynchronisation(0);
      expect(await parametres.intervalleSynchronisation(), const Duration(minutes: 30));

      // Une valeur illisible écrite ailleurs retombe sur le défaut, jamais sur une boucle.
      await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: ParametresPoste.cleIntervalleSynchronisation, value: '0'),
      );
      expect(await parametres.intervalleSynchronisation(), const Duration(minutes: 5));
    });
  });
}

class _HorsLigne implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}
