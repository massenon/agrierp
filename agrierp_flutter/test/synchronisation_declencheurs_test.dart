import 'dart:async';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/gestes_importants.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/sync/synchronisation_automatique.dart';
import 'package:agrierp/core/theme/agri_theme.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coque_poste.dart';

/// Tickets S-T1 et S-T3 (méthode TATACORA, `docs/COMPARAISON_METHODE_TATACORA.md` §4) — QUAND LE POSTE
/// SYNCHRONISE SEUL, ET QUAND IL S'ARRÊTE.
///
/// S-T1 : une 5xx est réessayée comme un échec réseau ; un 401 / 403 arrête la synchronisation automatique
/// jusqu'à la reconnexion (rien n'est perdu, « Synchroniser maintenant » reste possible).
/// S-T3 : à l'ouverture de la session, après un geste important (vente, fiche, soin — agrégés quelques secondes),
/// et toutes les 5 minutes.
///
/// ⚠️ Temps simulé de `testWidgets` : une minuterie oubliée fait échouer le test, ce qui vérifie aussi `arreter`.
void main() {
  const aboutie = SyncOutcome(tire: 1, accepte: 0, rejete: 0);
  const sessionExpiree = EchecSynchronisation(
    'Session expirée : reconnectez-vous. Vos saisies en attente sont conservées sur ce poste.',
    statut: 401,
  );
  DioException http(int statut) {
    final options = RequestOptions(path: '/api/sync/pull');
    return DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: options, statusCode: statut),
    );
  }

  late StreamController<List<ConnectivityResult>> reseau;
  late GestesImportants gestes;
  late List<Duration> appels;
  late Duration ecoule;

  setUp(() {
    reseau = StreamController<List<ConnectivityResult>>.broadcast();
    gestes = GestesImportants();
    appels = [];
    ecoule = Duration.zero;
  });
  tearDown(() {
    reseau.close();
    gestes.dispose();
  });

  Future<void> avancer(WidgetTester t, Duration duree) async {
    final fin = ecoule + duree;
    while (ecoule < fin) {
      ecoule += const Duration(seconds: 1);
      await t.pump(const Duration(seconds: 1));
    }
  }

  SynchronisationAutomatique automatique(Future<SyncOutcome> Function() reponse) => SynchronisationAutomatique(
    synchroniser: () {
      appels.add(ecoule);
      return reponse();
    },
    changementsReseau: reseau.stream,
    gestes: gestes,
  );

  group('S-T1 — 5xx réessayée, 401 / 403 : arrêt', () {
    testWidgets('🔴 une 5xx programme le réessai de 30 s, comme un échec réseau', (t) async {
      final a = automatique(() async => throw http(503))..demarrer(aussitot: true);
      await t.pump();
      expect(appels, [Duration.zero]);
      expect(a.reessaiProgramme, const Duration(seconds: 30));

      await avancer(t, const Duration(minutes: 3));
      expect(appels, [Duration.zero, const Duration(seconds: 30), const Duration(minutes: 2, seconds: 30)]);
      a.arreter();
    });

    testWidgets('une 4xx (422, 429) n est pas réessayée', (t) async {
      for (final statut in [422, 429]) {
        appels.clear();
        final a = automatique(() async => throw http(statut))..demarrer(aussitot: true);
        await t.pump();
        expect(a.reessaiProgramme, isNull, reason: '$statut');
        expect(a.suspendue, isFalse, reason: '$statut');
        a.arreter();
      }
    });

    for (final statut in [401, 403]) {
      testWidgets('🔴 $statut : plus AUCUNE tentative automatique (intervalle, réseau, geste), réessai annulé', (
        t,
      ) async {
        Future<SyncOutcome> Function() reponse = () async => throw http(500);
        final a = automatique(() => reponse())..demarrer(aussitot: true);
        await t.pump();
        expect(a.reessaiProgramme, const Duration(seconds: 30));

        reponse = () async => throw EchecSynchronisation('Refus', statut: statut);
        await avancer(t, const Duration(seconds: 30));
        expect(appels, hasLength(2));
        expect(a.suspendue, isTrue);
        expect(a.reessaiProgramme, isNull, reason: 'le réessai de la 5xx précédente est annulé');

        reponse = () async => aboutie;
        reseau.add([ConnectivityResult.none]);
        reseau.add([ConnectivityResult.wifi]);
        gestes.signaler();
        await avancer(t, const Duration(minutes: 31));
        await a.declencher();
        expect(appels, hasLength(2), reason: 'suspendue jusqu\'à la reconnexion');
        a.arreter();
      });
    }

    testWidgets('reconnexion : la session suivante (instance neuve) synchronise aussitôt et reprend', (t) async {
      final perimee = automatique(() async => throw sessionExpiree)..demarrer(aussitot: true);
      await t.pump();
      expect(perimee.suspendue, isTrue);
      perimee.arreter(); // déconnexion : le socle est démonté

      final reprise = automatique(() async => aboutie)..demarrer(aussitot: true);
      await t.pump();
      expect(appels, hasLength(2));
      expect(reprise.suspendue, isFalse);
      await avancer(t, const Duration(minutes: 5));
      expect(appels, hasLength(3), reason: 'l\'intervalle reprend');
      reprise.arreter();
    });

    test('réessayable : réseau et 5xx ; ni 4xx, ni refus nommé 401 / 403, ni bogue local', () {
      expect(SynchronisationAutomatique.estReessayable(http(500)), isTrue);
      expect(SynchronisationAutomatique.estReessayable(http(502)), isTrue);
      expect(SynchronisationAutomatique.estReessayable(http(599)), isTrue);
      expect(SynchronisationAutomatique.estReessayable(const EchecSynchronisation('x', statut: 503)), isTrue);
      expect(
        SynchronisationAutomatique.estReessayable(
          DioException(requestOptions: RequestOptions(path: '/'), type: DioExceptionType.connectionError),
        ),
        isTrue,
      );

      for (final statut in [400, 404, 409, 413, 422, 429]) {
        expect(SynchronisationAutomatique.estReessayable(http(statut)), isFalse, reason: '$statut');
      }
      expect(SynchronisationAutomatique.estReessayable(sessionExpiree), isFalse);
      expect(SynchronisationAutomatique.estReessayable(const EchecSynchronisation('x')), isFalse);
      expect(SynchronisationAutomatique.estReessayable(StateError('bogue')), isFalse);

      expect(const EchecSynchronisation('x', statut: 401).estSessionRefusee, isTrue);
      expect(const EchecSynchronisation('x', statut: 403).estSessionRefusee, isTrue);
      expect(const EchecSynchronisation('x', statut: 429).estSessionRefusee, isFalse);
      expect(const EchecSynchronisation('x').estSessionRefusee, isFalse);
    });
  });

  group('S-T3 — déclencheurs', () {
    testWidgets('ouverture de la session : une tentative aussitôt ; sans `aussitot`, aucune', (t) async {
      final sans = automatique(() async => aboutie)..demarrer();
      await t.pump();
      expect(appels, isEmpty);
      sans.arreter();

      final avec = automatique(() async => aboutie)..demarrer(aussitot: true);
      await t.pump();
      expect(appels, [Duration.zero]);
      avec.arreter();
    });

    testWidgets('🔴 trois gestes en deux secondes : UNE synchronisation, 5 s après le premier', (t) async {
      final a = automatique(() async => aboutie)..demarrer();
      gestes.signaler();
      await avancer(t, const Duration(seconds: 1));
      gestes.signaler();
      await avancer(t, const Duration(seconds: 1));
      gestes.signaler();
      await avancer(t, const Duration(seconds: 10));
      expect(appels, [const Duration(seconds: 5)]);

      gestes.signaler();
      await avancer(t, const Duration(seconds: 6));
      expect(appels, [const Duration(seconds: 5), const Duration(seconds: 17)], reason: 'un geste plus tard : une autre');
      a.arreter();
    });

    testWidgets('un geste pendant une synchronisation en relance une à sa fin', (t) async {
      final enCours = Completer<SyncOutcome>();
      var premiere = true;
      final a = automatique(() {
        if (premiere) {
          premiere = false;
          return enCours.future;
        }
        return Future.value(aboutie);
      })..demarrer(aussitot: true);
      await t.pump();

      gestes.signaler();
      await avancer(t, const Duration(seconds: 6));
      expect(appels, hasLength(1), reason: 'jamais deux synchronisations simultanées');

      enCours.complete(aboutie);
      await avancer(t, const Duration(seconds: 6));
      expect(appels, hasLength(2), reason: 'la saisie faite pendant la première part dans la suivante');
      a.arreter();
    });

    testWidgets('un geste ne court-circuite pas un réessai programmé', (t) async {
      final a = automatique(() async => throw http(500))..demarrer(aussitot: true);
      await t.pump();
      gestes.signaler();
      await avancer(t, const Duration(seconds: 20));
      expect(appels, [Duration.zero]);
      await avancer(t, const Duration(seconds: 10));
      expect(appels, [Duration.zero, const Duration(seconds: 30)]);
      a.arreter();
    });

    testWidgets('arrêtée, un geste ne déclenche plus rien', (t) async {
      automatique(() async => aboutie)
        ..demarrer()
        ..arreter();
      gestes.signaler();
      await avancer(t, const Duration(seconds: 10));
      expect(appels, isEmpty);
    });
  });

  group('S-T3 — les dépôts signalent leurs gestes', () {
    late AppDatabase db;
    late int signaux;
    const bande = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      signaux = 0;
      gestes.addListener(() => signaux++);
      await db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: bande,
          code: 'AVI-2026-01',
          speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
          initialQuantity: const Value(50),
          currentQuantity: const Value(50),
        ),
      );
    });
    tearDown(() => db.close());

    test('vente enregistrée à la caisse : un signal', () async {
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'pppppppp-1111-4111-8111-pppppppppppp',
          sku: 'AVI-001',
          name: 'Poulet goliath',
          unit: 'u',
          pricingMode: 'fourchette',
          stockQty: const Value(50),
        ),
      );
      final produit = await db.select(db.products).getSingle();

      await CaisseRepository(database: db, deviceId: 'poste-test', gestes: gestes).enregistrerVente(
        panier: [LignePanier(produit: produit, quantite: 1, montant: 3500)],
        modePaiement: 'especes',
      );
      expect(signaux, 1);
    });

    test('vente refusée (panier vide) : aucun signal', () async {
      await expectLater(
        CaisseRepository(database: db, deviceId: 'poste-test', gestes: gestes).enregistrerVente(
          panier: const [],
          modePaiement: 'especes',
        ),
        throwsA(isA<VenteRefusee>()),
      );
      expect(signaux, 0);
    });

    test('fiche journalière enregistrée : un signal', () async {
      await FicheJournaliereRepository(database: db, deviceId: 'poste-test', gestes: gestes).enregistrer(
        lotId: bande,
        jour: DateTime(2026, 10, 18),
        achat: 0,
        ne: 2,
        mort: 0,
        don: 0,
      );
      expect(signaux, 1);
    });

    test('soin enregistré : un signal', () async {
      await SoinsRepository(database: db, deviceId: 'poste-test', gestes: gestes).enregistrer(
        lotId: bande,
        typeAction: 'Vaccination',
        produit: 'Vaccin',
      );
      expect(signaux, 1);
    });

    test('sans point de gestes (tests, dépôts internes) : rien ne casse', () async {
      await SoinsRepository(database: db, deviceId: 'poste-test').enregistrer(lotId: bande, typeAction: 'Vitamines');
      expect(signaux, 0);
    });
  });

  group('S-T1 / S-T3 — l accueil du poste (SocleAccueil)', () {
    late AppDatabase db;
    late _Serveur serveur;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      serveur = _Serveur();
    });
    tearDown(() => db.close());

    SyncEngine moteur() => SyncEngine(
      database: db,
      client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur),
      deviceId: 'poste-audit',
      connectivity: _EnLigne(),
    );

    Future<void> ouvrir(WidgetTester t, {bool synchroniserALOuverture = true, Key? cle}) async {
      t.view.physicalSize = const Size(1600, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: AgriTheme.light,
          home: coqueDeTest(
            db,
            key: cle,
            engine: moteur(),
            changementsReseau: reseau.stream,
            gestes: gestes,
            synchroniserALOuverture: synchroniserALOuverture,
          ),
        ),
      );
      // Lecture de l'intervalle, puis tentative d'ouverture (base locale, client HTTP feint).
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets(
      '🔴 ouverture : synchronise ; 401 : plus rien d automatique ; reconnexion : reprend ; geste : synchronise',
      (t) async {
        serveur.statut = 401;
        await ouvrir(t, cle: const ValueKey('session-1'));
        expect(serveur.tirages, 1, reason: 'synchronisation à l\'ouverture de la session');

        await avancer(t, const Duration(minutes: 11));
        gestes.signaler();
        await avancer(t, const Duration(seconds: 10));
        expect(serveur.tirages, 1, reason: '401 : la synchronisation automatique est arrêtée');

        // Déconnexion puis reconnexion : `AgriErpApp` démonte l'accueil, puis en monte un neuf.
        await t.pumpWidget(const MaterialApp(home: SizedBox()));
        serveur.statut = 200;
        await ouvrir(t, cle: const ValueKey('session-2'));
        expect(serveur.tirages, 2, reason: 'la reconnexion relance la synchronisation');

        gestes.signaler();
        await avancer(t, const Duration(seconds: 6));
        expect(serveur.tirages, 3, reason: 'un geste important déclenche une synchronisation');

        await avancer(t, const Duration(minutes: 5));
        expect(serveur.tirages, 4, reason: 'puis toutes les 5 minutes');
        await t.pumpWidget(const MaterialApp(home: SizedBox()));
      },
    );

    testWidgets('juste après l écran de premier démarrage : pas de synchronisation à l ouverture', (t) async {
      await ouvrir(t, synchroniserALOuverture: false);
      expect(serveur.tirages, 0);
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
    });
  });
}

/// Serveur feint : répond [statut] au tirage (200 : corps vide) et accepte tout envoi.
class _Serveur extends Interceptor {
  int statut = 200;
  int tirages = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('pull')) tirages++;
    if (statut != 200) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: statut),
        ),
      );
      return;
    }
    handler.resolve(Response(requestOptions: options, statusCode: 200, data: <String, dynamic>{}));
  }
}

class _EnLigne implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}
