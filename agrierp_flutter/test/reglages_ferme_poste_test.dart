import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrierp/core/config/fichiers_entreprise.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:agrierp/features/parametres/reglages_ferme_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

/// Tickets PA-2, PA-3, PA-4, PA-7, PA-8 — LES RÉGLAGES DE LA FERME S'ÉCRIVENT AU POSTE, EN DEMANDES (`settings_requests`).
///
/// Le poste reproduit les refus du web AVANT d'écrire ; le serveur (services du web) reste le juge et applique les verrous
/// administrateur. Un secret SMS n'est jamais en base : il attend au coffre et part une fois.
class _Serveur extends Interceptor {
  final List<Map<String, dynamic>> envois = [];
  final refus = <String, String>{};

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
                  'accepted': [for (final e in value) if (e is Map && !refus.containsKey(e['id'])) e['id']],
                  'rejected': [for (final e in value) if (e is Map && refus.containsKey(e['id'])) {'id': e['id'], 'reason': refus[e['id']]}],
                },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {'server_time': '2026-10-28T12:00:00Z'}));
  }
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late ReglagesFermeRepository depot;
  late CoffreMemoire coffre;

  String uuid(String g) => g.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    coffre = CoffreMemoire();
    moteur = SyncEngine(
      database: db, client: Dio()..interceptors.add(serveur), deviceId: 'poste-test', connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 28, 14), coffre: coffre,
    );
    depot = ReglagesFermeRepository(database: db, deviceId: 'poste-test', coffre: coffre, horloge: () => DateTime(2026, 10, 28, 10));
  });
  tearDown(() async => db.close());

  Future<Map<String, String>> refus(Future<void> Function() geste) async {
    try {
      await geste();
    } on ReglageRefuse catch (e) {
      return e.erreurs;
    }
    fail('accepté');
  }

  Future<List<SettingsRequest>> demandes() => db.select(db.settingsRequests).get();

  Future<void> entrepriseVerrouillee() => db.into(db.companySettings).insert(
    CompanySettingsCompanion.insert(
      id: const Value('unique'), companyName: const Value('Ferme'), vpsRate: const Value(4), cnssEmployeeRate: const Value(3.6),
      cnssEmployerPensionRate: const Value(6.4), cnssEmployerFamilyRate: const Value(9), cnssEmployerRiskRate: const Value(2),
      payrollLocked: const Value(true), payrollEditedAt: const Value('27/10/2026 à 09:15'),
    ),
  );

  group('PA-3 · entreprise', () {
    Future<void> enregistrer({String vps = '4', bool admin = false, String ifu = '3201700000000'}) => depot.enregistrerEntreprise(
      raisonSociale: 'Ferme École', promoteur: 'Dr M', adresse: 'Ikpinlè', telephone: '0197', email: 'a@b.bj', ifu: ifu, rccm: 'RB/1',
      tva: true, vps: vps, cnssSalarie: '3.6', cnssPension: '6.4', cnssFamille: '9', cnssRisque: '2', estAdmin: admin,
    );

    test('⚠️ une demande pending est écrite avec le contenu du Blade, rien d\'autre', () async {
      await enregistrer();

      final d = (await demandes()).single;
      expect((d.kind, d.syncStatus, d.deviceId), ('entreprise', SyncStatus.pending, 'poste-test'));
      final p = jsonDecode(d.payload) as Map<String, dynamic>;
      expect((p['companyName'], p['ifu'], p['vpsRate'], p['tvaEnabled']), ('Ferme École', '3201700000000', 4.0, true));
    });

    test('⚠️⚠️ les refus du web sont reproduits avant d\'écrire (messages de lang/fr)', () async {
      var e = await refus(() => enregistrer(ifu: '12AB'));
      expect(e['ifu'], "L'IFU doit contenir uniquement des chiffres.");
      e = await refus(() => depot.enregistrerEntreprise(
        raisonSociale: '', promoteur: '', adresse: '', telephone: '', email: 'pas-un-mail', ifu: '', rccm: '', tva: false,
        vps: '11', cnssSalarie: 'abc', cnssPension: '', cnssFamille: '21', cnssRisque: '0', estAdmin: true,
      ));
      expect(e['companyName'], 'Le champ raison sociale est obligatoire.');
      expect(e['email'], 'Le champ adresse e-mail doit être une adresse e-mail valide.');
      expect(e['vpsRate'], 'Le champ taux du VPS ne doit pas dépasser 10.');
      expect(e['cnssEmployeeRate'], 'Le champ taux CNSS salarié doit être un nombre.');
      expect(e['cnssEmployerFamilyRate'], 'Le champ taux CNSS employeur (prestations familiales) ne doit pas dépasser 20.');
      expect(e['cnssEmployerRiskRate'], 'Le champ taux CNSS employeur (risques professionnels) doit être au moins égal à 1.');
      expect(await demandes(), isEmpty);
    });

    test('⚠️ taux arrêtés : un non-administrateur est refusé avec la date du web, l\'identité reste modifiable', () async {
      await entrepriseVerrouillee();

      final e = await refus(() => enregistrer(vps: '2'));
      expect(e['vpsRate'], 'Les taux de charges sociales ont été arrêtés le 27/10/2026 à 09:15. Seul un administrateur peut les modifier.');

      await enregistrer(); // mêmes taux : seule l'identité change
      await enregistrer(vps: '2', admin: true);
      expect((await demandes()).length, 2);
    });
  });

  group('PA-7 · barème ITS', () {
    const bon = [TrancheSaisie(de: 0, a: 60000, taux: 0), TrancheSaisie(de: 60000, a: 150000, taux: 10), TrancheSaisie(de: 150000, a: null, taux: 15)];

    test('cohérence du web : départ à 0, pas de trou, dernière tranche ouverte, taux 0 à 100', () {
      expect(ReglagesFermeRepository.verifierCoherence(bon), isNull);
      expect(ReglagesFermeRepository.verifierCoherence(const []), 'Le barème doit comporter au moins une tranche.');
      expect(ReglagesFermeRepository.verifierCoherence(const [TrancheSaisie(de: 10, a: null, taux: 0)]), contains('doit partir de 0'));
      expect(
        ReglagesFermeRepository.verifierCoherence(const [TrancheSaisie(de: 0, a: 60000, taux: 0), TrancheSaisie(de: 70000, a: null, taux: 10)]),
        'Les tranches doivent se suivre sans trou ni chevauchement : la tranche suivante doit commencer exactement à 60 000 FCFA.',
      );
      expect(ReglagesFermeRepository.verifierCoherence(const [TrancheSaisie(de: 0, a: 5, taux: 0)]), contains('dernière tranche doit être ouverte'));
      expect(ReglagesFermeRepository.verifierCoherence(const [TrancheSaisie(de: 0, a: null, taux: 101)]), 'Un taux doit être compris entre 0 et 100 %.');
    });

    test('⚠️ barème arrêté : seul l\'administrateur l\'écrit ; sinon la demande part avec ses tranches', () async {
      await entrepriseVerrouillee();
      final e = await refus(() => depot.enregistrerBareme(bon, estAdmin: false));
      expect(e['tranches'], 'Le barème a déjà été arrêté le 27/10/2026 à 09:15. Seul un administrateur peut le modifier.');

      await depot.enregistrerBareme(bon, estAdmin: true);
      final p = jsonDecode((await demandes()).single.payload) as Map<String, dynamic>;
      expect((p['tranches'] as List).last, {'from': 150000.0, 'to': null, 'rate': 15.0});
    });
  });

  group('PA-4 · modes de paiement', () {
    test('banque et Mobile Money : refus du web, puis demande pending', () async {
      var e = await refus(() => depot.creerBanque(banque: '', titulaire: '', rib: '', iban: ''));
      expect(e.keys, containsAll(['bankName', 'rib', 'iban']));
      e = await refus(() => depot.creerMomo(operateur: 'MTN', telephone: ''));
      expect(e['phoneNumber'], 'Le champ numéro de téléphone est obligatoire.');

      await depot.creerBanque(banque: 'Ecobank', titulaire: 'Ferme', rib: 'BJ01', iban: 'BJ66', compte: '5211');
      await depot.creerMomo(operateur: 'MTN', telephone: '0197');
      expect((await demandes()).map((d) => d.kind), ['mode_paiement', 'mode_paiement']);
    });

    test('⚠️ virement : comptes différents, montant, solde du poste ; la demande porte l\'UUID qui rend le rejeu inoffensif', () async {
      await db.into(db.treasuryAccounts).insert(TreasuryAccountsCompanion.insert(id: uuid('t1'), label: 'Caisse', balance: const Value(100000)));
      await db.into(db.treasuryAccounts).insert(TreasuryAccountsCompanion.insert(id: uuid('t2'), label: 'Banque'));

      var e = await refus(() => depot.virer(sourceId: uuid('t1'), destinationId: uuid('t1'), montant: '10'));
      expect(e['transferToId'], 'Le compte destinataire doit être différent du compte source.');
      e = await refus(() => depot.virer(sourceId: uuid('t1'), destinationId: uuid('t2'), montant: '500000'));
      expect(e['transferAmount'], 'Solde insuffisant sur Caisse : 100 000 FCFA disponibles.');

      await depot.virer(sourceId: uuid('t1'), destinationId: uuid('t2'), montant: '40000', motif: 'Dépôt');
      expect(jsonDecode((await demandes()).single.payload), containsPair('transferAmount', 40000.0));
    });
  });

  group('PA-2 · rôles', () {
    test('⚠️ réservé à l\'administrateur ; nom en minuscules ; unicité ; fondamentaux jamais supprimés ; rôle porté refusé', () async {
      await db.into(db.rolesApplicatifs).insert(RolesApplicatifsCompanion.insert(id: '1', name: 'comptable'));
      await db.into(db.rolesApplicatifs).insert(RolesApplicatifsCompanion.insert(id: '2', name: 'stagiaire-test'));
      await db.into(db.utilisateurs).insert(UtilisateursCompanion.insert(id: uuid('u1'), deviceId: 'serveur', updatedAt: DateTime(2026), name: 'X', role: const Value('stagiaire-test')));

      expect((await refus(() => depot.enregistrerRole(nom: 'x', permissions: {}, estAdmin: false)))['formulaire'], isNotNull);
      expect((await refus(() => depot.enregistrerRole(nom: 'Mauvais Nom', permissions: {}, estAdmin: true)))['roleName'], contains('lettres minuscules'));
      expect((await refus(() => depot.enregistrerRole(nom: 'comptable', permissions: {}, estAdmin: true)))['roleName'], 'La valeur du champ nom du rôle est déjà utilisée.');

      await depot.enregistrerRole(nom: 'responsable-achats', permissions: {'view-achats', 'manage-achats'}, estAdmin: true);
      final p = jsonDecode((await demandes()).single.payload) as Map<String, dynamic>;
      expect(p['roleName'], 'responsable-achats');
      expect(p['permissions'], ['manage-achats', 'view-achats']);

      expect(await depot.supprimerRole('comptable', estAdmin: true), contains('4 rôles fondamentaux'));
      expect(await depot.supprimerRole('stagiaire-test', estAdmin: true), 'Impossible de supprimer « stagiaire-test » : 1 utilisateur(s) porte(nt) encore ce rôle.');
      expect((await demandes()).length, 1, reason: 'aucun refus n\'a écrit de demande');
    });
  });

  group('PA-8 · SMS et moteur', () {
    test('⚠️⚠️ le jeton n\'est JAMAIS en base : au coffre, il part avec la demande puis est effacé à l\'acquittement', () async {
      await depot.enregistrerSms(fournisseur: 'twilio', twilioSid: 'AC1', twilioDe: '+229', twilioJeton: 'JETON-SECRET');
      final d = (await demandes()).single;

      expect(d.payload, isNot(contains('JETON-SECRET')));
      expect(coffre.contenu[ReglagesFermeRepository.cleSecretSms(d.id)], contains('JETON-SECRET'));

      await moteur.synchroniser();

      final envoyee = (serveur.envois.single['settings_requests'] as List).single as Map;
      expect(envoyee['payload'], containsPair('twilioToken', 'JETON-SECRET'));
      expect(coffre.contenu.containsKey(ReglagesFermeRepository.cleSecretSms(d.id)), isFalse);
      expect((await demandes()).single.syncStatus, SyncStatus.synced);
    });

    test('un refus du serveur devient conflict avec son motif, le secret reste pour la relance', () async {
      await depot.enregistrerSms(fournisseur: 'vonage', vonageCle: 'K', vonageSecret: 'S');
      final d = (await demandes()).single;
      serveur.refus[d.id] = 'Votre rôle ne permet pas ce réglage.';

      await moteur.synchroniser();

      expect((await demandes()).single.syncStatus, SyncStatus.conflict);
      expect(coffre.contenu.containsKey(ReglagesFermeRepository.cleSecretSms(d.id)), isTrue);
      final conflit = (await db.select(db.syncConflicts).get()).firstWhere((x) => x.sourceTable == 'settings_requests');
      expect(conflit.reason, contains('ne permet pas'));
      await moteur.relancer(conflit);
      expect((await demandes()).single.syncStatus, SyncStatus.pending);
    });

    test('un fournisseur inconnu est refusé avant d\'écrire', () async {
      expect((await refus(() => depot.enregistrerSms(fournisseur: 'autre')))['smsProvider'], isNotNull);
      expect(await demandes(), isEmpty);
    });
  });

  group('AUT-2 · logo et favicon', () {
    late Directory dossier;
    final png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));

    setUp(() async {
      dossier = await Directory.systemTemp.createTemp('entreprise_test');
      FichiersEntreprise.courant = FichiersEntreprise(dossier: () async => dossier);
      depot = ReglagesFermeRepository(database: db, deviceId: 'poste-test', coffre: coffre, horloge: () => DateTime(2026, 10, 28, 10));
    });
    tearDown(() async {
      FichiersEntreprise.courant = FichiersEntreprise();
      await dossier.delete(recursive: true);
    });

    Future<void> enregistrer({FichierChoisi? logo, FichierChoisi? favicon}) => depot.enregistrerEntreprise(
      raisonSociale: 'Ferme École', promoteur: 'Dr M', adresse: 'Ikpinlè', telephone: '0197', email: 'a@b.bj', ifu: '3201700000000', rccm: 'RB/1',
      tva: true, vps: '4', cnssSalarie: '3.6', cnssPension: '6.4', cnssFamille: '9', cnssRisque: '2', estAdmin: true, logo: logo, favicon: favicon,
    );

    test('⚠️ le fichier est gardé tout de suite sur le poste ; la demande n\'emporte que son nom, les octets partent à l\'envoi', () async {
      await enregistrer(logo: (nom: 'ferme.png', octets: png), favicon: (nom: 'f.png', octets: png));

      expect(await FichiersEntreprise.courant.lire('logo'), png);
      expect(await FichiersEntreprise.courant.logoPourPdf(), png);
      final d = (await demandes()).single;
      expect(d.payload, isNot(contains(base64Encode(png))));

      await moteur.synchroniser();

      final envoye = ((serveur.envois.single['settings_requests'] as List).single as Map)['payload'] as Map;
      expect(envoye['logoB64'], base64Encode(png));
      expect(envoye['faviconB64'], base64Encode(png));
    });

    test('⚠️ refus avant d\'écrire : format inconnu, favicon au-delà de 500 Ko ; rien n\'est gardé', () async {
      final r = await refus(() => enregistrer(logo: (nom: 'x.pdf', octets: png), favicon: (nom: 'f.png', octets: Uint8List(600 * 1024))));

      expect(r['logoFile'], 'Le logo doit être une image (png, jpg, gif, bmp ou webp).');
      expect(r['faviconFile'], 'Le favicon ne doit pas dépasser 500 Ko.');
      expect(await FichiersEntreprise.courant.fichier('logo'), isNull);
      expect(await demandes(), isEmpty);
    });

    test('un logo GIF reste affiché mais les PDF gardent celui de l\'installation (le moteur PDF ne lit que PNG et JPEG)', () async {
      await FichiersEntreprise.courant.enregistrer('logo', png, 'ferme.gif');

      expect(await FichiersEntreprise.courant.fichier('logo'), isNotNull);
      expect(await FichiersEntreprise.courant.logoPourPdf(), isNull);
    });

    test('un nouveau chemin servi par le web fait télécharger le fichier ; le même chemin ne le retélécharge pas', () async {
      var telechargements = 0;
      final client = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          if (o.path.contains('company-file')) {
            telechargements++;
            h.resolve(Response<List<int>>(requestOptions: o, statusCode: 200, data: png));
          } else if (o.path.contains('pull')) {
            h.resolve(Response<Map<String, dynamic>>(requestOptions: o, statusCode: 200, data: {
              'server_time': '2026-10-28T12:00:00Z',
              'company_settings': {'company_name': 'Ferme', 'logo_path': 'company/abc.png'},
            }));
          } else {
            h.resolve(Response<Map<String, dynamic>>(requestOptions: o, statusCode: 200, data: {}));
          }
        }));
      final m = SyncEngine(database: db, client: client, deviceId: 'poste-test', connectivity: _Connectivite(), maintenant: () => DateTime(2026, 10, 28, 14), coffre: coffre);

      await m.synchroniser();
      await m.synchroniser();

      expect(telechargements, 1);
      expect(await FichiersEntreprise.courant.lire('logo'), png);
      expect(await FichiersEntreprise.courant.sourceServeur('logo'), 'company/abc.png');
    });
  });

  group('écran', () {
    testWidgets('⚠️ « Données de l\'Entreprise » : modifier écrit la demande ; le barème et les SMS s\'ouvrent en sous-pages', (tester) async {
      tester.view.physicalSize = const Size(1700, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await entrepriseVerrouillee();
      await tester.pumpWidget(MaterialApp(home: ParametresGenerauxScreen(
        depot: ParametresGenerauxRepository(database: db), reglages: depot, estAdmin: true, ongletInitial: "Données de l'Entreprise",
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('entreprise-bareme')));
      await tester.pumpAndSettle();
      expect(find.text('Barème IR-PTS / ITS'), findsOneWidget);
      expect(find.byKey(const Key('bareme-de-0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('bareme-retour')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('entreprise-sms')));
      await tester.pumpAndSettle();
      expect(find.text('Intégrations & Notifications'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sms-retour')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('entreprise-modifier')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('entreprise-ifu')), '3201700000000');
      await tester.tap(find.byKey(const Key('entreprise-enregistrer')));
      await tester.pumpAndSettle();
      expect((await demandes()).single.kind, 'entreprise');
      expect(find.byKey(const Key('reglage-message')), findsOneWidget);
    });
  });
}
