import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/parametres/reglages_ferme_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/facturation_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// MECEF-1 — le POSTE : le mode (jamais le jeton) descend au tirage, les colonnes de la facture normalisée sont tirées et
/// JAMAIS écrites par le poste, la facture normalisée est en lecture seule (même refus, même message que le web), le PDF porte
/// le QR et les mentions de la DGI et rien d'inventé sans normalisation.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-11-07T09:00:00Z'};
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
                  'accepted': [for (final e in value) if (e is Map && e['id'] is String) e['id']],
                  'rejected': <Object>[],
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

  const vente = 'bbbbbbbb-1111-4000-8000-000000000001';
  const secret = 'eyJhbGciOiJIUzI1NiJ9.SECRET-JETON-DGI.signature';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime.utc(2026, 11, 7, 9),
    );
  });
  tearDown(() async => db.close());

  Map<String, dynamic> venteJson({String? statut = 'transmise', String? message}) => {
    'id': vente, 'customer_id': null, 'customer_name': null, 'payment_mode': 'especes',
    'subtotal': 11800, 'discount': 0, 'total': 11800, 'status': 'validee',
    'mecef_status': statut,
    'mecef_qr_ref': statut == 'transmise' ? 'F;ED01000001;TEST-AAAA;3202601234567;20261107101500' : null,
    'mecef_code': statut == 'transmise' ? 'TEST-AAAA' : null,
    'mecef_nim': statut == 'transmise' ? 'ED01000001' : null,
    'mecef_compteurs': statut == 'transmise' ? '12/34 FV' : null,
    'mecef_normalise_le': statut == 'transmise' ? '2026-11-07T10:15:00+01:00' : null,
    'mecef_message': message,
    'sold_at': '2026-11-07T09:30:00+01:00',
  };

  group('le tirage', () {
    test('⚠️ le mode, l adresse, l opérateur et UN BOOLÉEN descendent ; jamais le jeton', () async {
      serveur.tirage = {
        'server_time': '2026-11-07T09:00:00Z',
        'company_settings': {
          'company_name': 'Ferme', 'mecef_actif': true, 'mecef_mode': 'emecef', 'mecef_jeton_configure': true,
          'mecef_api_url': 'https://emcf.test/api', 'mecef_operateur_id': '7', 'mecef_operateur_nom': 'Awa',
          // Même si un serveur fautif l'envoyait, le poste n'a nulle part où le ranger.
          'mecef_jeton': secret,
        },
      };

      await moteur.synchroniser();

      final r = await ReglagesFermeRepository(database: db).reglageMecef();
      expect(r.mode, 'emecef');
      expect(r.jetonConfigure, isTrue);
      expect(r.apiUrl, 'https://emcf.test/api');
      expect(r.operateurId, '7');
      expect(r.operateurNom, 'Awa');
      expect(await FacturationRepository(database: db).mecefActif(), isTrue);

      final stockage = [
        for (final l in await db.select(db.appSettings).get()) '${l.key}=${l.value}',
      ].join('\n');
      expect(stockage, isNot(contains('SECRET-JETON')), reason: 'le jeton n\'est écrit nulle part au poste');
    });

    test('mode inconnu ou serveur antérieur : le poste lit « désactivé » et propose l\'adresse par défaut', () async {
      final r = await ReglagesFermeRepository(database: db).reglageMecef();
      expect(r.mode, 'desactive');
      expect(r.jetonConfigure, isFalse);
      expect(r.apiUrl, 'https://developper.impots.bj/sygmef-emcf/api');
    });

    test('la vente normalisée est tirée avec le code, le NIM, les compteurs, l instant et le motif', () async {
      serveur.tirage = {'server_time': '2026-11-07T09:00:00Z', 'sales': [venteJson()]};
      await moteur.synchroniser();

      final v = await (db.select(db.sales)..where((s) => s.id.equals(vente))).getSingle();
      expect(v.mecefStatus, 'transmise');
      expect(v.mecefCode, 'TEST-AAAA');
      expect(v.mecefNim, 'ED01000001');
      expect(v.mecefCompteurs, '12/34 FV');
      expect(v.mecefNormaliseLe, isNotNull);
      expect(v.mecefNormaliseLe!.minute, 15);
      expect(v.mecefMessage, isNull);
      expect(StatutMecef.depuis(v.mecefStatus).libelle, 'Normalisée');
    });

    test('une vente refusée porte son motif français ; une expirée a son libellé', () async {
      serveur.tirage = {'server_time': '2026-11-07T09:00:00Z', 'sales': [venteJson(statut: 'erreur', message: 'Création refusée par e-MECeF (422) : IFU inconnu.')]};
      await moteur.synchroniser();
      var v = await (db.select(db.sales)..where((s) => s.id.equals(vente))).getSingle();
      expect(StatutMecef.depuis(v.mecefStatus).libelle, 'Refusée');
      expect(v.mecefMessage, contains('IFU inconnu'));

      serveur.tirage = {'server_time': '2026-11-07T09:05:00Z', 'sales': [venteJson(statut: 'expiree', message: 'Facture expirée chez la DGI.')]};
      await moteur.synchroniser();
      v = await (db.select(db.sales)..where((s) => s.id.equals(vente))).getSingle();
      expect(StatutMecef.depuis(v.mecefStatus).libelle, 'Expirée');
    });

    test('⚠️ le poste n écrit JAMAIS les colonnes MeCeF : ni la vente, ni l avoir envoyés ne les portent', () {
      final source = File('lib/core/sync/sync_engine.dart').readAsStringSync();
      final vente = source.split('Map<String, dynamic> _venteEnJson(Sale v, List<SaleLine> lignes) => {')[1].split('\n  };')[0];
      expect(vente, contains("'total': v.total"), reason: 'le garde lit bien la fonction d\'envoi des ventes');
      expect(vente, isNot(contains('mecef')), reason: 'la normalisation appartient au serveur');

      final avoir = source.split('Map<String, dynamic> _avoirEnJson(AvoirClient a) => {')[1].split('};')[0];
      expect(avoir, contains("'amount'"));
      expect(avoir, isNot(contains('mecef')), reason: 'la facture d\'avoir appartient au serveur');
    });
  });

  group('lecture seule', () {
    Future<void> poser(String? statut) => db.into(db.sales).insert(
      SalesCompanion.insert(
        id: vente, deviceId: 'serveur', syncStatus: const Value(SyncStatus.synced), updatedAt: DateTime(2026, 11, 7),
        paymentMode: 'especes', total: 11800, soldAt: DateTime(2026, 11, 7, 9),
        mecefStatus: Value(statut),
      ),
    );

    test('⚠️ annuler une facture normalisée est refusé avec le message EXACT du web, et rien ne bouge', () async {
      await poser('transmise');
      final caisse = CaisseRepository(database: db, deviceId: 'poste-test');

      await expectLater(
        caisse.annulerVente(vente),
        throwsA(isA<FactureNormaliseeRefusee>().having((e) => e.toString(), 'message', messageFactureNormalisee)),
      );

      final v = await (db.select(db.sales)..where((s) => s.id.equals(vente))).getSingle();
      expect(v.status, 'validee');
      expect(v.syncStatus, SyncStatus.synced, reason: 'aucune demande d\'annulation n\'est écrite');
    });

    test('le message du poste est celui que le serveur dit : lu dans le code PHP', () {
      final php = File('$dossierLaravel/app/Exceptions/FactureNormaliseeException.php');
      if (!php.existsSync()) {
        markTestSkipped('SAUT : dépôt Laravel absent ($dossierLaravel)');
        return;
      }
      expect(php.readAsStringSync(), contains("'$messageFactureNormalisee'"));
    });

    for (final statut in [null, 'en_attente', 'erreur', 'expiree']) {
      test('une facture ${statut ?? 'jamais transmise'} reste annulable (comme avant)', () async {
        await poser(statut);
        final annulee = await CaisseRepository(database: db, deviceId: 'poste-test').annulerVente(vente);
        expect(annulee, isTrue);
      });
    }
  });

  group('la facture PDF', () {
    Future<Sale> lire() => (db.select(db.sales)..where((s) => s.id.equals(vente))).getSingle();

    Future<void> poser({String? statut, String? qr, String? code}) => db.into(db.sales).insert(
      SalesCompanion.insert(
        id: vente, deviceId: 'serveur', syncStatus: const Value(SyncStatus.synced), updatedAt: DateTime(2026, 11, 7),
        paymentMode: 'especes', total: 11800, soldAt: DateTime(2026, 11, 7, 9),
        mecefStatus: Value(statut), mecefQrRef: Value(qr), mecefCode: Value(code),
        mecefNim: Value(code == null ? null : 'ED01000001'), mecefCompteurs: Value(code == null ? null : '12/34 FV'),
        mecefNormaliseLe: Value(code == null ? null : DateTime(2026, 11, 7, 10, 15, 0)),
      ),
    );

    test('normalisée : le QR de la DGI et les mentions (code, NIM, compteurs, date et heure)', () async {
      await poser(statut: 'transmise', qr: 'F;ED01000001;TEST-AAAA;3202601234567;20261107101500', code: 'TEST-AAAA');
      final doc = DocumentsFacturation.facture(LigneFacture(vente: await lire(), envoyee: true), const []);

      expect(doc.noteDePied, 'Facture normalisée MeCeF');
      expect(doc.mentions, [
        'Code MeCeF/DGI : TEST-AAAA',
        'NIM : ED01000001',
        'Compteurs : 12/34 FV',
        'Normalisée le 07/11/2026 à 10:15:00',
      ]);
      expect(doc.codeQr, 'F;ED01000001;TEST-AAAA;3202601234567;20261107101500');
    });

    test('⚠️ sans normalisation (en attente, refusée, jamais transmise) : aucune mention, aucun QR inventé', () async {
      for (final statut in ['en_attente', 'erreur', 'expiree', null]) {
        await db.delete(db.sales).go();
        await poser(statut: statut, qr: statut == null ? null : 'REF-NON-CERTIFIEE');
        final doc = DocumentsFacturation.facture(LigneFacture(vente: await lire(), envoyee: true), const []);
        expect(doc.noteDePied, 'Facture émise sans certification MeCeF.', reason: '$statut');
        expect(doc.mentions, isEmpty, reason: '$statut');
        expect(doc.codeQr, isNull, reason: '$statut');
      }
    });

    test('ancienne facture normalisée sans code (simulation) : la référence, comme le web', () async {
      await poser(statut: 'transmise', qr: 'REF-123');
      final doc = DocumentsFacturation.facture(LigneFacture(vente: await lire(), envoyee: true), const []);
      expect(doc.noteDePied, 'Facture normalisée MeCeF — référence : REF-123');
      expect(doc.codeQr, 'REF-123');
    });
  });

  group('le réglage écrit une DEMANDE', () {
    Future<Map<String, dynamic>> derniereDemande() async {
      final r = (await db.select(db.settingsRequests).get()).single;
      expect(r.kind, 'entreprise');
      return jsonDecode(r.payload) as Map<String, dynamic>;
    }

    Future<void> enregistrer(ReglagesFermeRepository depot, {String ifu = '3202601234567', String? mode, String url = ''}) => depot.enregistrerEntreprise(
      raisonSociale: 'Ferme', promoteur: '', adresse: '', telephone: '', email: '', ifu: ifu, rccm: '', tva: true,
      vps: '4', cnssSalarie: '3.6', cnssPension: '6.4', cnssFamille: '9', cnssRisque: '2', estAdmin: true,
      mecefMode: mode, mecefApiUrl: url, mecefOperateurId: ' 7 ', mecefOperateurNom: 'Awa',
    );

    test('le mode, l adresse et l opérateur partent ; JAMAIS un jeton', () async {
      final depot = ReglagesFermeRepository(database: db);
      await enregistrer(depot, mode: 'emecef', url: 'https://emcf.test/api');

      final p = await derniereDemande();
      expect(p['mecefMode'], 'emecef');
      expect(p['mecefApiUrl'], 'https://emcf.test/api');
      expect(p['mecefOperateurId'], '7');
      expect(p['mecefOperateurNom'], 'Awa');
      expect(p.keys.where((k) => k.toLowerCase().contains('jeton') || k.toLowerCase().contains('token')), isEmpty);
    });

    test('un écran qui ne parle pas de MeCeF n envoie aucune clé MeCeF (le serveur garde son réglage)', () async {
      await enregistrer(ReglagesFermeRepository(database: db));
      expect((await derniereDemande()).keys.where((k) => k.startsWith('mecef')), isEmpty);
    });

    test('⚠️ les refus sont ceux du web, mot pour mot', () async {
      final depot = ReglagesFermeRepository(database: db);

      await expectLater(
        enregistrer(depot, ifu: '12345', mode: 'emecef'),
        throwsA(isA<ReglageRefuse>().having((e) => e.erreurs['ifu'], 'ifu', "L'IFU doit comporter 13 chiffres pour la facturation e-MECeF.")),
      );
      await expectLater(
        enregistrer(depot, mode: 'emecef', url: 'pas une adresse'),
        throwsA(isA<ReglageRefuse>().having((e) => e.erreurs['mecefApiUrl'], 'url', "L'adresse de l'API e-MECeF doit être une adresse web complète (https://…).")),
      );
      await expectLater(
        enregistrer(depot, mode: 'nimporte'),
        throwsA(isA<ReglageRefuse>().having((e) => e.erreurs['mecefMode'], 'mode', 'Le mode de facturation normalisée doit être : désactivé, e-MECeF ou boîtier.')),
      );
      expect(await db.select(db.settingsRequests).get(), isEmpty, reason: 'un refus n\'écrit rien');

      // Les mêmes phrases sont celles du serveur (lues dans le code PHP).
      final php = File('$dossierLaravel/app/Services/EntrepriseService.php');
      if (php.existsSync()) {
        final source = php.readAsStringSync();
        expect(source, contains("L'IFU doit comporter 13 chiffres pour la facturation e-MECeF."));
        expect(source, contains("L'adresse de l'API e-MECeF doit être une adresse web complète (https://…)."));
        expect(source, contains('Le mode de facturation normalisée doit être : désactivé, e-MECeF ou boîtier.'));
      }
    });

    test('les libellés des modes sont ceux du web (`MecefMode::LIBELLES`)', () {
      final php = File('$dossierLaravel/app/Support/MecefMode.php');
      if (!php.existsSync()) {
        markTestSkipped('SAUT : dépôt Laravel absent ($dossierLaravel)');
        return;
      }
      final source = php.readAsStringSync();
      for (final libelle in ReglagesFermeRepository.libellesModesMecef.values) {
        expect(source, contains("'$libelle'"));
      }
      expect(source, contains("URL_PAR_DEFAUT = '${ReglagesFermeRepository.urlEmecefParDefaut}'"));
    });
  });
}
