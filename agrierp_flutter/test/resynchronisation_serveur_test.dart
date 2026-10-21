import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/modale_synchronisation.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket SW-1 (correction du client du 21/10/2026) — LE WEB FAIT AUSSI REVENIR LES DONNÉES VERS LES POSTES, côté poste.
///
/// « Renvoyer vers ce poste » (web) lève un drapeau serveur `resynchronisation_demandee_le`. Le poste le lit au ping
/// de 30 s (`GET /api/sync/demande`) et au tirage ; il repart alors d'un tirage COMPLET (sans `since`), puis
/// ACQUITTE (`POST /api/sync/resynchronisation/acquittement`) : le drapeau tombe. Aucune migration Drift : le
/// drapeau vit au serveur, l'état « en cours » vit en mémoire.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  /// Instant du drapeau levé au serveur ; `null` : aucun. Tombe quand l'acquittement le désigne.
  String? drapeau;

  /// Réponse de l'acquittement : le serveur refuse-t-il (drapeau plus récent) ?
  bool acquittementRefuse = false;

  /// Panne réseau sur l'acquittement.
  bool acquittementEnPanne = false;

  final List<Map<String, dynamic>> tirages = [];
  final List<Map<String, dynamic>> acquittements = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    Response<Map<String, dynamic>> ok(Map<String, dynamic> corps) =>
        Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: corps);

    if (options.path.contains('resynchronisation/acquittement')) {
      acquittements.add(Map<String, dynamic>.from(options.data as Map));
      if (acquittementEnPanne) {
        handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError));
        return;
      }
      final acquittee = !acquittementRefuse && drapeau != null;
      if (acquittee) drapeau = null;
      handler.resolve(ok({'acquittee': acquittee}));
      return;
    }
    if (options.path.contains('sync/demande')) {
      handler.resolve(ok({
        'demande': false,
        'resynchronisation': drapeau != null,
        'resynchronisation_demandee_le': drapeau,
      }));
      return;
    }
    if (options.path.contains('push')) {
      handler.resolve(ok(<String, dynamic>{}));
      return;
    }
    tirages.add(Map<String, dynamic>.from(options.queryParameters));
    handler.resolve(ok({
      'page': 1,
      'server_time': '2026-10-21T12:00:00+00:00',
      'resynchronisation_demandee_le': ?drapeau,
      'page_suivante': null,
    }));
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur),
      deviceId: 'POSTE-BUREAU',
      connectivity: _Connectivite(),
    );
  });
  tearDown(() => db.close());

  /// Un poste « à jour » : deux synchronisations sans drapeau ont rendu les reglages uniques et fixé le curseur.
  Future<void> posteAJour() async {
    await moteur.synchroniser();
    serveur.tirages.clear();
    await moteur.synchroniser();
    expect(serveur.tirages.single['since'], isNotNull, reason: 'poste à jour : tirage incrémental');
    serveur.tirages.clear();
  }

  test('🔴 un drapeau levé au serveur fait repartir le poste d un tirage COMPLET, puis il acquitte', () async {
    await posteAJour();
    serveur.drapeau = '2026-10-21T09:00:00+00:00';

    await moteur.synchroniser();

    expect(serveur.tirages, hasLength(2), reason: 'la page 1 incrémentale porte le drapeau, puis le tirage repart');
    expect(serveur.tirages.first['since'], isNotNull);
    expect(serveur.tirages.last.containsKey('since'), isFalse, reason: 'tirage complet : aucun curseur envoyé');
    expect(serveur.acquittements, [
      {'demandee_le': '2026-10-21T09:00:00+00:00'},
    ], reason: 'acquitté avec l instant de la demande honorée, une seule fois');
    expect(serveur.drapeau, isNull, reason: 'le drapeau est tombé');
    expect(moteur.resynchronisationServeur.value, isFalse);

    // Le tirage suivant est de nouveau incrémental, et n acquitte plus.
    serveur.tirages.clear();
    await moteur.synchroniser();
    expect(serveur.tirages.single['since'], isNotNull);
    expect(serveur.acquittements, hasLength(1));
  });

  test('sans drapeau : aucun tirage complet de plus, aucun acquittement', () async {
    await posteAJour();
    await moteur.synchroniser();

    expect(serveur.tirages.single['since'], isNotNull);
    expect(serveur.acquittements, isEmpty);
  });

  test('le ping de 30 s lit le drapeau : demande de synchronisation et état « demandée par le serveur »', () async {
    expect(await moteur.demandeDuServeur(), isFalse);
    expect(moteur.resynchronisationServeur.value, isFalse);

    serveur.drapeau = '2026-10-21T09:00:00+00:00';
    expect(await moteur.demandeDuServeur(), isTrue, reason: 'le ping déclenche la synchronisation');
    expect(moteur.resynchronisationServeur.value, isTrue);
  });

  test('un acquittement refusé (drapeau plus récent) ou perdu laisse l état « demandée » : le suivant recommencera', () async {
    await posteAJour();
    serveur.drapeau = '2026-10-21T09:00:00+00:00';
    serveur.acquittementRefuse = true;
    await moteur.synchroniser();
    expect(moteur.resynchronisationServeur.value, isTrue);
    expect(serveur.drapeau, isNotNull);

    serveur.acquittementRefuse = false;
    serveur.acquittementEnPanne = true;
    await moteur.synchroniser();
    expect(moteur.resynchronisationServeur.value, isTrue, reason: 'panne à l acquittement : jamais une erreur, jamais « terminé »');

    serveur.acquittementEnPanne = false;
    await moteur.synchroniser();
    expect(serveur.drapeau, isNull);
    expect(moteur.resynchronisationServeur.value, isFalse);
  });

  testWidgets('la modale dit « Resynchronisation demandée par le serveur » tant que le drapeau n est pas acquitté', (t) async {
    await t.runAsync(() async {
      serveur.drapeau = '2026-10-21T09:00:00+00:00';
      await moteur.demandeDuServeur();
    });

    await t.pumpWidget(MaterialApp(home: Scaffold(body: ModaleSynchronisation(engine: moteur, database: db))));
    await t.pump();
    expect(find.text('Resynchronisation demandée par le serveur'), findsOneWidget);

    await t.runAsync(() async => moteur.synchroniser());
    await t.pump();
    expect(find.text('Resynchronisation demandée par le serveur'), findsNothing);
  });

  test('PARITÉ : les libellés communs de la modale web (Blade) sont ceux de la modale du poste', () {
    final blade = File(
      '$dossierLaravel/resources/views/livewire/shared/etat-synchronisation-postes.blade.php',
    );
    if (!blade.existsSync()) {
      markTestSkipped('Blade introuvable (AGRIERP_LARAVEL) : parité non vérifiable.');
      return;
    }
    final web = blade.readAsStringSync();
    final poste = File('lib/core/sync/modale_synchronisation.dart').readAsStringSync();

    // Parties COMMUNES : titre, état « à jour », dernier envoi, resynchronisation demandée.
    for (final libelle in ['Synchronisation', 'Dernier envoi']) {
      expect(web, contains(libelle), reason: 'libellé commun absent du Blade : $libelle');
      expect(poste, contains(libelle), reason: 'libellé commun absent du poste : $libelle');
    }
    expect(web, contains('Resynchronisation demandée'));
    expect(poste, contains('Resynchronisation demandée par le serveur'));
    // Le geste est propre au web (« Renvoyer vers ce poste ») : il n'existe pas au poste, qui n'a qu'un seul poste.
    expect(web, contains('Renvoyer vers ce poste'));
    expect(web, contains('Renvoyer vers tous les postes'));
    expect(poste, isNot(contains("libelle: 'Renvoyer")));
  });
}
