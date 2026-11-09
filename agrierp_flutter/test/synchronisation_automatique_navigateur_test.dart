import 'dart:async';

import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/sync/synchronisation_automatique.dart';
import 'package:agrierp/core/systeme/evenements_navigateur.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// PWA-2b — déclencheurs de synchronisation propres au NAVIGATEUR, joués avec un faux déclencheur (flux d'événements) :
/// retour en ligne, retour de focus de l'onglet (anti-rebond de 30 s), jamais pendant une synchronisation en cours.
/// Natif : un flux vide (ou absent) ne change rien.
void main() {
  late StreamController<EvenementNavigateur> evenements;
  late StreamController<List<ConnectivityResult>> reseau;
  late DateTime horloge;
  late int appels;
  Completer<void>? bloquer;
  late SynchronisationAutomatique auto;

  SynchronisationAutomatique creer({
    Stream<EvenementNavigateur>? flux,
    Future<bool> Function()? sondeur,
  }) =>
      SynchronisationAutomatique(
        synchroniser: () async {
          appels++;
          if (bloquer != null) await bloquer!.future;
          return const SyncOutcome(tire: 0, accepte: 0, rejete: 0);
        },
        changementsReseau: reseau.stream,
        intervalle: const Duration(hours: 1),
        evenementsNavigateur: flux,
        maintenant: () => horloge,
        sondeur: sondeur,
      );

  setUp(() {
    evenements = StreamController<EvenementNavigateur>.broadcast();
    reseau = StreamController<List<ConnectivityResult>>.broadcast();
    horloge = DateTime(2026, 11, 9, 9);
    appels = 0;
    bloquer = null;
  });

  tearDown(() async {
    auto.arreter();
    await evenements.close();
    await reseau.close();
  });

  Future<void> laisserPasser() => Future<void>.delayed(Duration.zero);

  test('retour en ligne : une synchronisation, même juste après une autre', () async {
    auto = creer(flux: evenements.stream)..demarrer(aussitot: true);
    await laisserPasser();
    expect(appels, 1, reason: 'ouverture de l\'application');
    evenements.add(EvenementNavigateur.retourEnLigne);
    await laisserPasser();
    expect(appels, 2, reason: 'le retour du réseau n\'est jamais retenu par l\'anti-rebond');
  });

  test('retour de focus : anti-rebond de 30 s', () async {
    auto = creer(flux: evenements.stream)..demarrer(aussitot: true);
    await laisserPasser();
    expect(appels, 1);

    horloge = horloge.add(const Duration(seconds: 10));
    evenements.add(EvenementNavigateur.ongletVisible);
    await laisserPasser();
    expect(appels, 1, reason: 'moins de 30 s depuis la dernière tentative');

    horloge = horloge.add(const Duration(seconds: 25));
    evenements.add(EvenementNavigateur.ongletVisible);
    await laisserPasser();
    expect(appels, 2, reason: '35 s : le focus relance');

    horloge = horloge.add(const Duration(seconds: 5));
    evenements.add(EvenementNavigateur.ongletVisible);
    await laisserPasser();
    expect(appels, 2, reason: 'l\'anti-rebond repart de la dernière tentative');
  });

  test('jamais pendant une synchronisation en cours', () async {
    bloquer = Completer<void>();
    auto = creer(flux: evenements.stream)..demarrer(aussitot: true);
    await laisserPasser();
    expect(appels, 1);
    horloge = horloge.add(const Duration(minutes: 5));
    evenements
      ..add(EvenementNavigateur.ongletVisible)
      ..add(EvenementNavigateur.retourEnLigne);
    await laisserPasser();
    expect(appels, 1, reason: 'une synchronisation tourne déjà : aucune seconde');
    bloquer!.complete();
    await laisserPasser();
  });

  test('natif : aucun flux, ou flux vide, ne déclenche rien', () async {
    auto = creer()..demarrer();
    await laisserPasser();
    expect(appels, 0);
    auto.arreter();
    auto = creer(flux: const Stream<EvenementNavigateur>.empty())..demarrer();
    await laisserPasser();
    expect(appels, 0);
    expect(await evenementsDuNavigateur().isEmpty, isTrue, reason: 'VM = natif : flux vide');
  });

  test('après arrêt, les événements ne déclenchent plus', () async {
    auto = creer(flux: evenements.stream)..demarrer();
    auto.arreter();
    evenements.add(EvenementNavigateur.retourEnLigne);
    await laisserPasser();
    expect(appels, 0);
  });

  // PWA-2c — sondage léger avant de synchroniser (faux sondeur).
  group('sondage léger au retour en ligne', () {
    test('serveur injoignable : on reste hors ligne, rien n\'est tiré, aucune erreur', () async {
      var sondages = 0;
      auto = creer(
        flux: evenements.stream,
        sondeur: () async {
          sondages++;
          return false;
        },
      )..demarrer();
      evenements.add(EvenementNavigateur.retourEnLigne);
      await laisserPasser();
      await laisserPasser();
      expect(sondages, 1);
      expect(appels, 0, reason: 'sondage en échec : aucune synchronisation, donc aucune erreur rouge');
      expect(auto.echecsConsecutifs, 0);
      expect(auto.reessaiProgramme, isNull, reason: 'hors ligne n\'est pas une erreur : pas de réessai bruyant');
    });

    test('serveur joignable : le sondage précède la synchronisation', () async {
      final ordre = <String>[];
      auto = SynchronisationAutomatique(
        synchroniser: () async {
          ordre.add('synchro');
          return const SyncOutcome(tire: 0, accepte: 0, rejete: 0);
        },
        changementsReseau: reseau.stream,
        intervalle: const Duration(hours: 1),
        evenementsNavigateur: evenements.stream,
        maintenant: () => horloge,
        sondeur: () async {
          ordre.add('sonde');
          return true;
        },
      )..demarrer();
      evenements.add(EvenementNavigateur.retourEnLigne);
      await laisserPasser();
      await laisserPasser();
      expect(ordre, ['sonde', 'synchro']);
    });

    test('un sondeur qui lève vaut « hors ligne » ; le focus après 30 s sonde de nouveau', () async {
      var joignable = false;
      var sondages = 0;
      auto = creer(
        flux: evenements.stream,
        sondeur: () async {
          sondages++;
          if (!joignable) throw TimeoutException('3 s');
          return true;
        },
      )..demarrer();
      evenements.add(EvenementNavigateur.ongletVisible);
      await laisserPasser();
      await laisserPasser();
      expect((sondages, appels), (1, 0));
      joignable = true;
      evenements.add(EvenementNavigateur.ongletVisible);
      await laisserPasser();
      await laisserPasser();
      expect((sondages, appels), (2, 1), reason: 'aucune tentative n\'a eu lieu : pas d\'anti-rebond');
    });

    test('jamais deux sondages à la fois', () async {
      final fin = Completer<bool>();
      var sondages = 0;
      auto = creer(
        flux: evenements.stream,
        sondeur: () {
          sondages++;
          return fin.future;
        },
      )..demarrer();
      evenements
        ..add(EvenementNavigateur.retourEnLigne)
        ..add(EvenementNavigateur.retourEnLigne);
      await laisserPasser();
      expect(sondages, 1);
      fin.complete(false);
      await laisserPasser();
    });
  });
}
