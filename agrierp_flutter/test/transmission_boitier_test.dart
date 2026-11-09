import 'dart:async';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/mecef/marque_boitier.dart';
import 'package:agrierp/core/mecef/passerelle_boitier.dart';
import 'package:agrierp/core/mecef/passerelle_boitier_native.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/transmission_boitier.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'boitier_faux_pilote.dart';

/// MECEF-2 — LA TRANSMISSION PAR LE POSTE, contre un FAUX PILOTE (⚠️ NON VÉRIFIÉ AVEC UN VRAI BOÎTIER).
/// États, idempotence (jamais deux transmissions d'une vente), reprise au retour du boîtier, jamais un jeton, résultat envoyé au serveur.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-11-09T09:00:00Z'};
  final List<Map<String, dynamic>> envois = [];

  /// Appelé PENDANT un envoi (le boîtier répond entre la lecture des ventes et l'accusé du serveur).
  Future<void> Function()? pendantEnvoi;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      final pendant = pendantEnvoi;
      pendantEnvoi = null;
      if (pendant != null) await pendant();
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List) key: {'accepted': [for (final e in value) if (e is Map && e['id'] is String) e['id']], 'rejected': <Object>[]},
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
  late FauxPilote pilote;
  late CaisseRepository caisse;
  late TransmissionBoitier service;
  late _Serveur serveur;
  late SyncEngine moteur;

  const vente = 'dddddddd-1111-4000-8000-000000000001';
  const produit = 'pppppppp-1111-4111-8111-pppppppppppp';

  Future<void> reglage(String cle, String valeur) => db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: cle, value: valeur));

  Future<void> poserVente({String id = vente, String type = 'normalisee', bool lignes = true, SyncStatus sync = SyncStatus.synced}) async {
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: id, deviceId: 'poste-test', syncStatus: Value(sync), updatedAt: DateTime(2026, 11, 9, 9),
        paymentMode: 'especes', subtotal: const Value(11800), total: 11800, soldAt: DateTime(2026, 11, 9, 9),
        factureType: Value(type), clientNomFacture: const Value('AMOUSSOU Régis'), aibTaux: const Value('N/A'),
      ),
    );
    if (lignes) {
      await db.into(db.saleLines).insert(
        SaleLinesCompanion.insert(id: id.replaceRange(0, 4, 'llll'), saleId: id, productId: produit, qty: 2, unitPrice: 5900, manualTotalAmount: 11800),
      );
    }
  }

  Future<Sale> lire([String id = vente]) => (db.select(db.sales)..where((s) => s.id.equals(id))).getSingle();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    pilote = await FauxPilote.demarrer();
    caisse = CaisseRepository(database: db, deviceId: 'poste-test', maintenant: () => DateTime(2026, 11, 9, 10));
    service = TransmissionBoitier(
      caisse: caisse,
      database: db,
      passerelle: PasserelleBoitierHttp(
        adresse: pilote.adresse,
        delais: const DelaisBoitier(connexion: Duration(milliseconds: 500), verification: Duration(milliseconds: 500), informations: Duration(milliseconds: 500), facture: Duration(milliseconds: 700)),
      ),
    );
    serveur = _Serveur();
    moteur = SyncEngine(database: db, client: Dio()..interceptors.add(serveur), deviceId: 'poste-test', connectivity: _Connectivite(), maintenant: () => DateTime.utc(2026, 11, 9, 9));

    await db.into(db.products).insert(ProductsCompanion.insert(id: produit, sku: 'OEUF', name: "Plaquette d'œufs", unit: 'plaquette', pricingMode: 'fourchette', tvaRate: const Value(18)));
    await db.into(db.companySettings).insert(CompanySettingsCompanion.insert(ifu: const Value('3202601234567'), tvaEnabled: const Value(true)));
    await reglage('mecef.mode', 'boitier');
    await reglage('mecef.actif', '1');
    await reglage('mecef.operateur_id', '7');
    await reglage('mecef.operateur_nom', 'Caissière Test');
  });
  tearDown(() async {
    await pilote.arreter();
    await db.close();
  });

  test('succès : la vente devient « Normalisée » avec ce que le boîtier rend, et repart au serveur', () async {
    await poserVente();

    final r = await service.transmettre(vente);

    expect(r.issue, IssueTransmission.transmise);
    final v = await lire();
    expect(v.mecefStatus, 'transmise');
    expect(v.mecefQrRef, startsWith('F;ED04000623;'));
    expect(v.mecefCode, 'NW34NID6ZHANFNMZ2IU7LL3H');
    expect(v.mecefNim, 'ED04000623');
    expect(v.mecefNormaliseLe, DateTime(2020, 5, 3, 13, 50, 2));
    expect(v.mecefMessage, isNull);
    expect(v.syncStatus, SyncStatus.pending, reason: 'elle repart au serveur');
    expect(pilote.appelsBill, 1);
  });

  test('la charge envoyée est celle du serveur (FactureMecef) : opérateur, produit, taxe B, paiement espèces, aucun jeton', () async {
    await poserVente();
    await service.transmettre(vente);

    final c = pilote.chargesRecues.single;
    expect(c['vt'], 'FV');
    expect(c['seller_id'], '7');
    expect(c['seller_name'], 'Caissière Test');
    expect(c['buyer_name'], 'AMOUSSOU Régis');
    expect(c['aib'], 'N/A');
    expect(c['payments'], [{'mode': 'E', 'amount': 11800}]);
    final p = (c['products'] as List).single as Map;
    expect(p['tax'], 'B');
    expect(p['price'], 5900);
    expect(p['items'], 2);
    expect(pilote.enTetesAuthorization.single, isNull);
    expect('$c'.toLowerCase(), isNot(contains('token')));
    expect('$c'.toLowerCase(), isNot(contains('jeton')));
  });

  test('IDEMPOTENCE : une vente normalisée n est JAMAIS retransmise (second appel, reprise, vente simple, autre mode)', () async {
    await poserVente();
    await service.transmettre(vente);
    final deuxieme = await service.transmettre(vente);
    final reprise = await service.reprendre();

    expect(deuxieme.issue, IssueTransmission.nonConcernee);
    expect(reprise, 0);
    expect(pilote.appelsBill, 1);
  });

  test('IDEMPOTENCE : deux demandes simultanées, une seule transmission', () async {
    await poserVente();
    pilote.delai = const Duration(milliseconds: 150);

    final r = await Future.wait([service.transmettre(vente), service.transmettre(vente)]);

    expect(r.where((x) => x.issue == IssueTransmission.transmise).length, 1);
    expect(pilote.appelsBill, 1);
  });

  test('une facture simple, une vente annulée, un autre mode : rien n est appelé', () async {
    await poserVente(type: 'simple');
    expect((await service.transmettre(vente)).issue, IssueTransmission.nonConcernee);

    await poserVente(id: 'dddddddd-1111-4000-8000-000000000002');
    await (db.update(db.sales)..where((s) => s.id.equals('dddddddd-1111-4000-8000-000000000002'))).write(const SalesCompanion(status: Value('annulee')));
    expect((await service.transmettre('dddddddd-1111-4000-8000-000000000002')).issue, IssueTransmission.nonConcernee);

    await poserVente(id: 'dddddddd-1111-4000-8000-000000000003');
    await reglage('mecef.mode', 'emecef');
    expect((await service.transmettre('dddddddd-1111-4000-8000-000000000003')).issue, IssueTransmission.nonConcernee);
    expect(await service.reprendre(), 0);
    expect(pilote.appelsBill, 0);
  });

  test('boîtier injoignable (503) : « En attente », pas d erreur, repris AU RETOUR du boîtier, une seule fois', () async {
    await poserVente();
    pilote.scenario = ScenarioPilote.indisponible503;

    final r = await service.transmettre(vente);
    expect(r.issue, IssueTransmission.enAttente);
    expect(r.message, 'Boîtier injoignable : la facture sera transmise dès son retour.');
    var v = await lire();
    expect(v.mecefStatus, 'en_attente');
    expect(v.mecefMessage, messageBoitierInjoignable);
    expect(v.syncStatus, SyncStatus.synced, reason: 'rien à envoyer au serveur : aucun résultat');
    expect(await service.reprendre(), 0, reason: 'le boîtier est toujours absent');

    pilote.scenario = ScenarioPilote.succes;
    expect(await service.reprendre(), 1);
    v = await lire();
    expect(v.mecefStatus, 'transmise');
    expect(await service.reprendre(), 0);
    expect(pilote.appelsBill, 2, reason: 'un essai refusé en 503, un essai réussi');
  });

  test('boîtier absent (connexion refusée) : la reprise ne fait rien et ne lève pas', () async {
    await poserVente();
    await pilote.arreter();
    expect((await service.transmettre(vente)).issue, IssueTransmission.enAttente);
    expect(await service.reprendre(), 0);
    expect((await service.verifier()).message, 'Boîtier injoignable');
  });

  test('refus 400 : « Refusée » avec son motif français ; JAMAIS repris seul ; relance manuelle possible', () async {
    await poserVente();
    pilote.scenario = ScenarioPilote.refus400;

    final r = await service.transmettre(vente);
    expect(r.issue, IssueTransmission.refusee);
    var v = await lire();
    expect(v.mecefStatus, 'erreur');
    expect(v.mecefMessage, contains('refusé'));
    expect(v.syncStatus, SyncStatus.pending);

    pilote.scenario = ScenarioPilote.succes;
    expect(await service.reprendre(), 0, reason: 'un refus ne boucle pas');
    expect(pilote.appelsBill, 1);

    expect((await service.transmettre(vente)).issue, IssueTransmission.transmise, reason: 'relance manuelle');
    v = await lire();
    expect(v.mecefStatus, 'transmise');
  });

  test('200 avec qr_code VIDE : refus, jamais « Normalisée »', () async {
    await poserVente();
    pilote.scenario = ScenarioPilote.qrVide;

    final r = await service.transmettre(vente);

    expect(r.issue, IssueTransmission.refusee);
    final v = await lire();
    expect(v.mecefStatus, 'erreur');
    expect(v.mecefQrRef, isNull);
  });

  test('réponse perdue (délai après envoi) : INCERTAINE, marquée, JAMAIS retransmise seule ; relance après vérification', () async {
    await poserVente();
    pilote.scenario = ScenarioPilote.delai;
    pilote.delai = const Duration(seconds: 2);

    final r = await service.transmettre(vente);
    expect(r.issue, IssueTransmission.incertaine);
    var v = await lire();
    expect(v.mecefStatus, 'en_attente');
    expect(v.mecefMessage, marqueTransmissionBoitier);

    pilote.delai = Duration.zero;
    expect(await service.reprendre(), 0);
    expect((await service.transmettre(vente)).issue, IssueTransmission.nonConcernee, reason: 'jamais seul');
    expect(pilote.appelsBill, 1);
    expect((await service.compteurs()).aVerifier, 1);

    expect((await service.transmettre(vente, apresVerification: true)).issue, IssueTransmission.transmise);
    v = await lire();
    expect(v.mecefStatus, 'transmise');
    expect(pilote.appelsBill, 2);
  });

  test('un arrêt de l application pendant l appel laisse la marque : la reprise ne retransmet pas', () async {
    await poserVente();
    // La marque est posée AVANT l'appel : on simule l'arrêt juste après la réservation.
    expect(await caisse.reserverTransmissionBoitier(vente), isNotNull);

    expect(await service.reprendre(), 0);
    expect((await service.transmettre(vente)).issue, IssueTransmission.nonConcernee);
    expect(pilote.appelsBill, 0);
  });

  test('le tirage n efface JAMAIS une transmission incertaine, ni une normalisation en attente d envoi', () async {
    await poserVente();
    await caisse.reserverTransmissionBoitier(vente);
    serveur.tirage = {
      'server_time': '2026-11-09T09:05:00Z',
      'sales': [
        {'id': vente, 'payment_mode': 'especes', 'total': 11800, 'status': 'validee', 'sold_at': '2026-11-09 09:00:00', 'mecef_status': 'en_attente', 'mecef_message': 'Mode boîtier : en attente', 'facture_type': 'normalisee'},
      ],
    };
    await moteur.synchroniser();
    var v = await lire();
    expect(v.mecefMessage, marqueTransmissionBoitier, reason: 'la marque survit au tirage');

    // Une normalisation du poste pas encore envoyée (pending) : l'absorbeur strict ne la touche pas non plus.
    await service.transmettre(vente, apresVerification: true);
    await (db.update(db.sales)..where((s) => s.id.equals(vente))).write(SalesCompanion(syncStatus: const Value(SyncStatus.pending), updatedAt: Value(DateTime(2026, 11, 9, 11))));
    await moteur.synchroniser();
    v = await lire();
    expect(v.mecefStatus, 'transmise');
  });

  test('le serveur normalisé REMPLACE la marque (sa normalisation fait foi)', () async {
    await poserVente();
    await caisse.reserverTransmissionBoitier(vente);
    serveur.tirage = {
      'server_time': '2026-11-09T09:05:00Z',
      'sales': [
        {'id': vente, 'payment_mode': 'especes', 'total': 11800, 'status': 'validee', 'sold_at': '2026-11-09 09:00:00', 'mecef_status': 'transmise', 'mecef_qr_ref': 'F;X;Y;1;20261109090000', 'facture_type': 'normalisee'},
      ],
    };
    await moteur.synchroniser();
    final v = await lire();
    expect(v.mecefStatus, 'transmise');
    expect(v.mecefMessage, isNull);
  });

  test('lignes de la vente pas encore reçues : en attente, rien n est appelé', () async {
    await poserVente(lignes: false);
    final r = await service.transmettre(vente);
    expect(r.issue, IssueTransmission.enAttente);
    expect(pilote.appelsBill, 0);
  });

  test('opérateur non réglé : rien n est appelé, le message dit où le régler', () async {
    await poserVente();
    await reglage('mecef.operateur_id', '');
    final r = await service.transmettre(vente);
    expect(r.issue, IssueTransmission.nonConcernee);
    expect(r.message, contains('opérateur'));
    expect(pilote.appelsBill, 0);
  });

  test('une charge refusée par le constructeur (total incohérent) est « Refusée » sans toucher le boîtier', () async {
    await poserVente();
    await (db.update(db.sales)..where((s) => s.id.equals(vente))).write(const SalesCompanion(total: Value(99999)));
    final r = await service.transmettre(vente);
    expect(r.issue, IssueTransmission.refusee);
    expect(r.message, contains('Total de la vente'));
    expect(pilote.appelsBill, 0);
  });

  group('envoi au serveur', () {
    test('la vente normalisée par le boîtier part avec le bloc `mecef` (mode boîtier), rien d autre', () async {
      await poserVente();
      await service.transmettre(vente);

      await moteur.synchroniser();

      final vendue = (serveur.envois.last['sales'] as List).single as Map;
      final m = vendue['mecef'] as Map;
      expect(m['status'], 'transmise');
      expect((m['qr_ref'] as String), startsWith('F;ED04000623;'));
      expect(m['code'], 'NW34NID6ZHANFNMZ2IU7LL3H');
      expect(m['nim'], 'ED04000623');
      expect(m.keys.toSet(), {'status', 'qr_ref', 'code', 'nim', 'normalise_le', 'message'});
      expect(vendue.keys.where((k) => k.startsWith('mecef_')), isEmpty);
      expect('$vendue'.toLowerCase(), isNot(contains('token')));
      expect((await lire()).syncStatus, SyncStatus.synced, reason: 'acquittée');
    });

    test('un refus du boîtier part avec son motif et sans QR', () async {
      await poserVente();
      pilote.scenario = ScenarioPilote.refus400;
      await service.transmettre(vente);

      await moteur.synchroniser();

      final m = ((serveur.envois.last['sales'] as List).single as Map)['mecef'] as Map;
      expect(m['status'], 'erreur');
      expect(m['qr_ref'], isNull);
      expect(m['message'], contains('refusé'));
    });

    test('⚠️ la facture normalisée PENDANT l envoi reste en attente d envoi, puis part avec son résultat (jamais retransmise)', () async {
      await poserVente(sync: SyncStatus.pending);
      serveur.pendantEnvoi = () => service.transmettre(vente);

      await moteur.synchroniser();

      // Le premier envoi est parti sans résultat ; le serveur l'a acquitté, mais la vente porte la normalisation du boîtier.
      expect(((serveur.envois.first['sales'] as List).single as Map).containsKey('mecef'), isFalse);
      var v = await lire();
      expect(v.mecefStatus, 'transmise');
      expect(v.syncStatus, SyncStatus.pending, reason: 'pas acquittée : son résultat n\'est pas encore parti');

      // Un tirage entre-temps ne l'efface pas (vente en attente), puis l'envoi suivant porte le résultat.
      await moteur.synchroniser();
      final dernier = (serveur.envois.last['sales'] as List).single as Map;
      expect((dernier['mecef'] as Map)['status'], 'transmise');
      v = await lire();
      expect(v.mecefStatus, 'transmise');
      expect(v.syncStatus, SyncStatus.synced);
      expect(pilote.appelsBill, 1);
    });

    test('hors mode boîtier : AUCUN bloc `mecef` ne part', () async {
      await poserVente();
      await service.transmettre(vente);
      await reglage('mecef.mode', 'emecef');

      await moteur.synchroniser();

      expect(((serveur.envois.last['sales'] as List).single as Map).containsKey('mecef'), isFalse);
    });

    test('une transmission incertaine ne part pas (la vente part, sans bloc)', () async {
      await poserVente(sync: SyncStatus.pending);
      await caisse.reserverTransmissionBoitier(vente);

      await moteur.synchroniser();

      final vendue = (serveur.envois.last['sales'] as List).single as Map;
      expect(vendue.containsKey('mecef'), isFalse);
    });
  });

  test('la passerelle du poste ne sait joindre que cette machine ; pas de jeton ni de Dio de session dans le client', () {
    final src = File('lib/core/mecef/passerelle_boitier_native.dart').readAsStringSync();
    expect(src, isNot(contains('Authorization:')));
    expect(src, contains('hotesBoitierAutorises'));
  });
}
