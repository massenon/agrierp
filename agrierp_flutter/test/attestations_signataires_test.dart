import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/rh/attestations_repository.dart';
import 'package:agrierp/features/rh/attestations_vue.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket ATT-2 (27/10/2026) — SIGNATAIRES SELON LA DURÉE, PARAMÉTRABLES, ET APERÇU FIDÈLE AU MODÈLE OFFICIEL.
///
/// Règle du client : d'un mois à un an, SEUL le promoteur (Directeur Général) signe ; au-delà d'un an, TROIS personnes
/// signent (Examinateur, Président du Jury, Directeur Général). Le seuil et le palier de chaque signataire sont ceux du
/// modèle, servis par le serveur et modifiables au poste. Le PDF est fabriqué au poste (ATT-3) ; ici : la règle, le formulaire, l'aperçu.
const _corpsOfficiel =
    'Je soussigné **OLOUKOUNLE O. Hassimiyou**, Directeur Général de la **FERME ECOLE OLOUWACHEGOUN,** atteste que le '
    'nommé[ACCORD_E] **[NOM],** né[ACCORD_E] le [DATE_NAISSANCE_LONGUE] à [LIEU_NAISSANCE], a suivi une formation '
    'pratique[DE_DUREE] sur ladite ferme, du **[DATE_DEBUT_LONGUE] au [DATE_FIN_LONGUE]** dans les domaines ci-après :';

class _Serveur extends Interceptor {
  _Serveur({this.code = 200, this.corps});

  final int code;
  final Map<String, dynamic>? corps;
  final requetes = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requetes.add(options);

    if (code >= 400) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: code,
            data: utf8.encode(jsonEncode(corps ?? {})),
          ),
        ),
      );
      return;
    }

    handler.resolve(
      Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: options.method == 'PUT'
            ? <String, dynamic>{'message': 'ok'}
            : <String, dynamic>{'numero': 'N°01/2026/FEO/DG', 'deja_enregistree': false},
        headers: Headers.fromMap({
          'content-disposition': ['attachment; filename="attestation.pdf"'],
        }),
      ),
    );
  }
}

class _Tirage extends Interceptor {
  _Tirage(this.corps);

  final Map<String, dynamic> corps;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) => handler.resolve(
    Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 200,
      data: options.path.contains('push') ? <String, dynamic>{} : corps,
    ),
  );
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

void main() {
  late AppDatabase db;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final aujourdhui = DateTime(2026, 10, 24);
  const defaut = ReglageSignature.defaut;

  List<int> positions(ReglageSignature r, DateTime? debut, DateTime? fin, [Map<int, Map<String, String>> surcharges = const {}]) => [
    for (final s in r.requis(debut: debut, fin: fin, aujourdhui: aujourdhui, surcharges: surcharges)) s.position,
  ];

  group('règle de signature (pure)', () {
    test('⚠️⚠️ jusqu\'à un an INCLUS le promoteur seul signe ; au-delà, trois, dans l\'ordre du modèle', () {
      expect(positions(defaut, DateTime(2026, 9, 24), DateTime(2026, 10, 24)), [1], reason: 'un mois');
      expect(positions(defaut, DateTime(2026, 10, 20), DateTime(2026, 10, 24)), [1], reason: 'moins d\'un mois');
      expect(positions(defaut, DateTime(2025, 10, 15), DateTime(2026, 10, 15)), [1], reason: 'un an exactement : court');
      expect(positions(defaut, DateTime(2025, 10, 15), DateTime(2026, 10, 16)), [2, 3, 1], reason: 'un an et un jour');
      expect(positions(defaut, DateTime(2024, 1, 1), DateTime(2026, 10, 24)), [2, 3, 1]);
    });

    test('sans date de fin la durée court jusqu\'à aujourd\'hui ; sans début, le promoteur', () {
      expect(positions(defaut, DateTime(2024, 3, 1), null), [2, 3, 1]);
      expect(positions(defaut, DateTime(2026, 6, 1), null), [1]);
      expect(positions(defaut, null, null), [1]);
    });

    test('⚠️ le 31 janvier + 1 mois = le dernier jour de février (comme Carbon addMonthsNoOverflow)', () {
      expect(ReglageSignature.ajouterMois(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(ReglageSignature.ajouterMois(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
      expect(ReglageSignature.ajouterMois(DateTime(2025, 10, 15), 12), DateTime(2026, 10, 15));
      expect(ReglageSignature.ajouterMois(DateTime(2025, 11, 30), 3), DateTime(2026, 2, 28));
    });

    test('le seuil et le palier de chaque signataire se paramètrent', () {
      final six = defaut.avec(seuilMois: 6);
      expect(positions(six, DateTime(2026, 4, 24), DateTime(2026, 10, 24)), [1], reason: 'six mois pile');
      expect(positions(six, DateTime(2026, 4, 23), DateTime(2026, 10, 24)), [2, 3, 1]);

      final autre = defaut.avec(
        signataires: {
          ...defaut.signataires,
          2: defaut.signataires[2]!.avec(court: true),
          1: defaut.signataires[1]!.avec(long: false),
        },
      );
      expect(positions(autre, DateTime(2026, 9, 24), DateTime(2026, 10, 24)), [2, 1]);
      expect(positions(autre, DateTime(2024, 1, 1), DateTime(2026, 10, 24)), [2, 3]);
    });

    test('les modifications de l\'émetteur remplacent le modèle ; un signataire vide n\'est pas imprimé', () {
      final liste = defaut.requis(
        debut: DateTime(2024, 1, 1),
        fin: DateTime(2026, 10, 24),
        aujourdhui: aujourdhui,
        surcharges: {2: {'nom': ' KPOHAZOUNDE Jean ', 'fonction': 'Chef ATDA Pôle 5'}},
      );

      final examinateur = liste.firstWhere((s) => s.position == 2);
      expect(examinateur.nom, 'KPOHAZOUNDE Jean');
      expect(examinateur.fonction, 'Chef ATDA Pôle 5');
      expect(examinateur.titre, 'Examinateur', reason: 'l\'intitulé non modifié reste celui du modèle');
      // Un signataire que la règle n'appelle pas ne s'imprime pas parce qu'on l'a renseigné.
      expect(positions(defaut, DateTime(2026, 9, 24), DateTime(2026, 10, 24), {2: {'nom': 'X'}}), [1]);

      final vide = defaut.avec(signataires: {...defaut.signataires, 2: const SignataireModele(position: 2, long: true)});
      expect(positions(vide, DateTime(2024, 1, 1), DateTime(2026, 10, 24)), [3, 1]);
    });

    test('les valeurs par défaut sont celles du modèle fourni (et du serveur)', () {
      expect(defaut.seuilMois, 12);
      expect(defaut.signataires[1]!.nom, 'Hassimiyou O. OLOUKOUNLE');
      expect(defaut.signataires[1]!.titre, '');
      expect(defaut.signataires[2]!.titre, 'Examinateur');
      expect(defaut.signataires[3]!.titre, 'Président du Jury');
      expect([for (final n in [1, 2, 3]) defaut.signataires[n]!.court], [true, false, false]);
      expect([for (final n in [1, 2, 3]) defaut.signataires[n]!.long], [true, true, true]);
    });

    test('le corps envoyé au serveur porte tous les champs de la règle, sous les clés du serveur', () {
      final corps = defaut.avec(seuilMois: 9, appreciationImprimee: false).versServeur();

      expect(corps['seuil_signature_mois'], 9);
      expect(corps['appreciation_imprimee'], false);
      expect(corps['appreciation_text'], isNull);
      expect(corps['sig2_nom'], 'SOGNIGBE Gbédjinou Serge Bruno');
      expect(corps['sig3_fonction'], contains('FN-CCPB'));
      expect(corps['sig2_court'], false);
      expect(corps['sig2_long'], true);
      expect(corps.keys.where((k) => k.startsWith('sig')), hasLength(15));
    });
  });

  group('texte du modèle officiel', () {
    const fagbohoun = PersonneAttestation(
      id: 'x', nom: 'FAGBOHOUN', prenom: 'Sébastien Ichola Alaro', poste: null, etablissement: 'Agronomie', debut: null, fin: null,
    );

    test('⚠️⚠️ le texte d\'une attestation de formation, mot pour mot (même qu\'au serveur)', () {
      final t = AttestationsRepository.apercu(
        modele: _corpsOfficiel,
        type: 'stagiaire',
        personne: fagbohoun,
        contrat: '',
        debut: DateTime(2025, 10, 15),
        fin: DateTime(2026, 10, 15),
        birthDate: DateTime(2008, 1, 21),
        birthPlace: 'Kétou',
      );

      expect(
        t,
        'Je soussigné OLOUKOUNLE O. Hassimiyou, Directeur Général de la FERME ECOLE OLOUWACHEGOUN, atteste que le nommé '
        'FAGBOHOUN Sébastien Ichola Alaro, né le 21 janvier 2008 à Kétou, a suivi une formation pratique d\'un (01) an '
        'sur ladite ferme, du 15 octobre 2025 au 15 octobre 2026 dans les domaines ci-après :',
      );
    });

    test('au féminin : accords « nommée », « née », « Madame »', () {
      final t = AttestationsRepository.apercu(
        modele: _corpsOfficiel,
        type: 'stagiaire',
        personne: fagbohoun,
        contrat: '',
        debut: DateTime(2025, 10, 15),
        fin: DateTime(2026, 10, 15),
        birthDate: DateTime(2008, 1, 21),
        civilite: 'Mme',
      );
      expect(t, contains('le nommée FAGBOHOUN'));
      expect(t, contains('née le 21 janvier 2008'));
    });

    test('durée en toutes lettres : « an » au singulier, élision devant « un » seulement', () {
      String d(DateTime a, DateTime b) => AttestationsRepository.deDuree(a, b);

      expect(d(DateTime(2025, 10, 15), DateTime(2026, 10, 15)), " d'un (01) an");
      expect(d(DateTime(2025, 7, 15), DateTime(2026, 10, 15)), " d'un (01) an et trois (03) mois");
      expect(d(DateTime(2026, 4, 15), DateTime(2026, 10, 15)), ' de six (06) mois');
      expect(d(DateTime(2024, 10, 15), DateTime(2026, 10, 15)), ' de deux (02) ans');
      expect(d(DateTime(2026, 10, 20), DateTime(2026, 10, 24)), '', reason: 'moins d\'un mois : pas de durée');
      expect(AttestationsRepository.dateLongue(DateTime(2026, 2, 1)), '1 février 2026');
    });

    test('l\'appréciation : la saisie, sinon la phrase standard, sinon rien (modèle qui la supprime, employé)', () {
      String? a(String saisie, {ReglageSignature? r, String type = 'stagiaire'}) => AttestationsRepository.appreciation(
        type: type, personne: fagbohoun, saisie: saisie, reglage: r ?? defaut,
      );

      expect(
        a(''),
        'Au cours de sa formation, Monsieur FAGBOHOUN Sébastien Ichola Alaro s’est distingué par sa ponctualité, '
        'son esprit d’initiative, sa capacité d’adaptation et sa motivation à apprendre.',
      );
      expect(a('  Très assidu.  '), 'Très assidu.');
      expect(a('', r: defaut.avec(appreciationImprimee: false)), isNull);
      expect(a('Très assidu.', r: defaut.avec(appreciationImprimee: false)), 'Très assidu.');
      expect(a('', type: 'employe'), isNull);
    });
  });

  group('absorption du tirage', () {
    SyncEngine moteur(Map<String, dynamic> pull) => SyncEngine(
      database: db,
      client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(_Tirage(pull)),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
    );

    Map<String, dynamic> tirage(List<Map<String, dynamic>> modeles) => {
      'server_time': '2026-10-27T12:00:00.000Z',
      'product_categories': <dynamic>[],
      'products': <dynamic>[],
      'livestock_lots': <dynamic>[],
      'attestation_templates': modeles,
    };

    test('⚠️ la règle de signature et les signataires du serveur arrivent au poste', () async {
      await moteur(
        tirage([
          {
            'id': uuid('m1'), 'type': 'stagiaire', 'body_text': 'B [NOM]',
            'seuil_signature_mois': 6,
            'appreciation_text': 'Phrase du modèle', 'appreciation_imprimee': false,
            'sig1_titre': '', 'sig1_nom': 'Le Directeur', 'sig1_fonction': 'Directeur',
            'sig2_titre': 'Examinateur', 'sig2_nom': 'Marie', 'sig2_fonction': 'ATDA',
            'sig3_titre': 'Président du Jury', 'sig3_nom': 'Paul', 'sig3_fonction': 'FN-CCPB',
            'sig1_court': true, 'sig2_court': true, 'sig3_court': false,
            'sig1_long': true, 'sig2_long': false, 'sig3_long': true,
          },
        ]),
      ).synchroniser();

      final r = (await AttestationsRepository(database: db).reglage('stagiaire'))!;
      expect(r.seuilMois, 6);
      expect(r.appreciationText, 'Phrase du modèle');
      expect(r.appreciationImprimee, isFalse);
      expect(r.signataires[2]!.nom, 'Marie');
      expect(r.signataires[3]!.fonction, 'FN-CCPB');
      expect([for (final n in [1, 2, 3]) r.signataires[n]!.court], [true, true, false]);
      expect([for (final n in [1, 2, 3]) r.signataires[n]!.long], [true, false, true]);
    });

    test('un serveur plus ancien (sans ces champs) laisse les défauts de la table : 12 mois, le promoteur seul au court', () async {
      await moteur(
        tirage([
          {'id': uuid('m1'), 'type': 'employe', 'body_text': 'A [NOM]'},
        ]),
      ).synchroniser();

      final r = (await AttestationsRepository(database: db).reglage('employe'))!;
      expect(r.seuilMois, 12);
      expect([for (final n in [1, 2, 3]) r.signataires[n]!.court], [true, false, false]);
      expect([for (final n in [1, 2, 3]) r.signataires[n]!.long], [true, true, true]);
    });

    test('aucune règle tant que le modèle n\'est pas reçu', () async {
      expect(await AttestationsRepository(database: db).reglage('employe'), isNull);
    });
  });

  group('écran', () {
    late _Serveur serveur;
    final livrees = <PdfAttestation>[];
    setUp(livrees.clear);

    Future<void> modeles() async {
      for (final (cle, type, texte) in [('m-e', 'employe', 'Attestation de [NOM].'), ('m-s', 'stagiaire', _corpsOfficiel)]) {
        await db.into(db.attestationTemplates).insert(
          AttestationTemplatesCompanion.insert(
            id: uuid(cle),
            type: type,
            bodyText: texte,
            sig1Nom: Value(defaut.signataires[1]!.nom),
            sig1Fonction: Value(defaut.signataires[1]!.fonction),
            sig2Titre: const Value('Examinateur'),
            sig2Nom: Value(defaut.signataires[2]!.nom),
            sig2Fonction: Value(defaut.signataires[2]!.fonction),
            sig3Titre: const Value('Président du Jury'),
            sig3Nom: Value(defaut.signataires[3]!.nom),
            sig3Fonction: Value(defaut.signataires[3]!.fonction),
          ),
        );
      }
    }

    Future<void> stagiaire(String cle, String nom, DateTime debut, DateTime? fin) => db.into(db.internships).insert(
      InternshipsCompanion.insert(
        id: uuid(cle),
        deviceId: 'serveur',
        updatedAt: DateTime(2026, 1, 1),
        syncStatus: const Value(SyncStatus.synced),
        firstName: 'Félicité',
        lastName: nom,
        school: const Value('Agronomie'),
        startDate: Value(debut),
        endDate: Value(fin),
      ),
    );

    Future<void> afficher(WidgetTester t, {_Serveur? faux}) async {
      serveur = faux ?? _Serveur();
      t.view.physicalSize = const Size(1600, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await modeles();

      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AttestationsVue(
                depot: AttestationsRepository(
                  database: db,
                  client: ClientAttestations(Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur)),
                ),
                maintenant: aujourdhui,
                enregistrer: (pdf) async {
                  livrees.add(pdf);
                  return 'C:/attestation.pdf';
                },
                imprimer: (pdf) async {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    Future<void> choisirStagiaire(WidgetTester t, String libelle) async {
      await t.tap(find.byKey(const Key('att-type-stagiaire')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('att-personne')));
      await t.pumpAndSettle();
      await t.tap(find.text(libelle).last);
      await t.pumpAndSettle();
    }

    testWidgets('⚠️⚠️ un stage de plus d\'un an : TROIS signataires, au formulaire et à l\'aperçu', (t) async {
      await stagiaire('s1', 'LONG', DateTime(2025, 1, 5), DateTime(2026, 10, 15));
      await afficher(t);
      await choisirStagiaire(t, 'LONG Félicité');

      expect(find.byKey(const Key('att-apercu-sig-2')), findsOneWidget);
      expect(find.byKey(const Key('att-apercu-sig-3')), findsOneWidget);
      expect(find.byKey(const Key('att-apercu-sig-1')), findsOneWidget);
      expect(find.text('Examinateur'), findsWidgets);
      expect(find.text('Président du Jury'), findsWidgets);
      expect(
        t.widget<Text>(find.byKey(const Key('att-signataires-titre'))).data,
        'SIGNATAIRES — TROIS SIGNATAIRES (ATTESTATION DE PLUS DE 12 MOIS)',
      );
      // De gauche à droite : Examinateur, Président du Jury, Directeur Général.
      final x = [for (final n in [2, 3, 1]) t.getTopLeft(find.byKey(Key('att-apercu-sig-$n'))).dx];
      expect(x[0], lessThan(x[1]));
      expect(x[1], lessThan(x[2]));
    });

    testWidgets('⚠️⚠️ un stage de moins d\'un an : le promoteur seul', (t) async {
      await stagiaire('s1', 'COURT', DateTime(2026, 2, 1), DateTime(2026, 5, 31));
      await afficher(t);
      await choisirStagiaire(t, 'COURT Félicité');

      expect(find.byKey(const Key('att-apercu-sig-1')), findsOneWidget);
      expect(find.byKey(const Key('att-apercu-sig-2')), findsNothing);
      expect(find.byKey(const Key('att-apercu-sig-3')), findsNothing);
      expect(
        t.widget<Text>(find.byKey(const Key('att-signataires-titre'))).data,
        "SIGNATAIRES — LE PROMOTEUR SEUL (JUSQU'À 12 MOIS)",
      );
    });

    testWidgets('changer la date de fin change qui signe, en direct', (t) async {
      await stagiaire('s1', 'BASCULE', DateTime(2025, 10, 15), DateTime(2026, 10, 15));
      await afficher(t);
      await choisirStagiaire(t, 'BASCULE Félicité');
      expect(find.byKey(const Key('att-apercu-sig-2')), findsNothing, reason: 'un an exactement : court');

      await t.enterText(find.byKey(const Key('att-fin')), '16/10/2026');
      await t.pumpAndSettle();

      expect(find.byKey(const Key('att-apercu-sig-2')), findsOneWidget, reason: 'un an et un jour : long');
    });

    testWidgets('⚠️ une modification du signataire s\'affiche à l\'aperçu ET s\'imprime dans le PDF du poste ; un champ vide reprend le modèle', (t) async {
      await stagiaire('s1', 'LONG', DateTime(2025, 1, 5), DateTime(2026, 10, 15));
      await afficher(t);
      await choisirStagiaire(t, 'LONG Félicité');

      // Le formulaire est replié : on l'ouvre.
      await t.tap(find.byKey(const Key('att-signataires')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('att-sig2-nom')), 'KPOHAZOUNDE Jean');
      await t.pumpAndSettle();

      // ⚠️ À l'APERÇU seulement : l'indication grisée du champ (le nom du modèle) reste dans l'arbre, invisible.
      Finder dansApercu(int n, String texte) =>
          find.descendant(of: find.byKey(Key('att-apercu-sig-$n')), matching: find.text(texte));
      expect(dansApercu(2, 'KPOHAZOUNDE Jean'), findsOneWidget);
      expect(dansApercu(2, 'SOGNIGBE Gbédjinou Serge Bruno'), findsNothing, reason: 'remplacé pour cette attestation');
      expect(dansApercu(3, 'Elisée Kocou HOUNKPONOU'), findsOneWidget, reason: 'les autres reprennent le modèle');

      await t.tap(find.byKey(const Key('att-generer')));
      // ⚠️ Le PDF se fabrique au poste (polices et images du bundle, disque réel) : hors du temps simulé.
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
      await t.pumpAndSettle();

      // Le serveur ne reçoit que la DÉCLARATION d'émission : ni nom de signataire, ni texte.
      final corps = serveur.requetes.single.data as Map;
      expect(serveur.requetes.single.path, '/api/attestations/emissions');
      expect(corps.keys.toSet(), {'id', 'type', 'issued_at'});

      // Le document, lui, porte le nom modifié (relu par pdftotext quand il existe).
      expect(livrees, hasLength(1));
      await t.runAsync(() async {
        if ((await Process.run('which', ['pdftotext'])).exitCode != 0) return;
        final f = File('${Directory.systemTemp.path}/att_sig_test.pdf')..writeAsBytesSync(livrees.single.octets);
        final texte = (await Process.run('pdftotext', ['-layout', f.path, '-'])).stdout as String;
        f.deleteSync();
        expect(texte, contains('KPOHAZOUNDE Jean'));
        expect(texte, isNot(contains('SOGNIGBE')), reason: 'remplacé pour cette attestation');
        expect(texte, contains('Elisée Kocou HOUNKPONOU'), reason: 'les autres reprennent le modèle');
      });
    });

    testWidgets('l\'aperçu imprime la phrase d\'appréciation standard, et les puces ➢ dans l\'ordre du modèle', (t) async {
      await stagiaire('s1', 'LONG', DateTime(2025, 1, 5), DateTime(2026, 10, 15));
      await afficher(t);
      await choisirStagiaire(t, 'LONG Félicité');
      await t.tap(find.byKey(const Key('att-domaine-gestion')));
      await t.tap(find.byKey(const Key('att-domaine-maraichage')));
      await t.pumpAndSettle();

      expect(
        t.widget<Text>(find.byKey(const Key('att-apercu-appreciation'))).data,
        startsWith('Au cours de sa formation, Monsieur LONG Félicité s’est distingué'),
      );
      expect(find.byKey(const Key('att-apercu-cloture')), findsOneWidget);
      final y = [for (final c in ['maraichage', 'gestion']) t.getTopLeft(find.byKey(Key('att-apercu-domaine-$c'))).dy];
      expect(y[0], lessThan(y[1]), reason: 'l\'ordre du modèle, pas celui du clic');
      expect(
        t.widget<Text>(find.byKey(const Key('att-apercu-domaine-gestion'))).data,
        '➢ Notion de gestion des entreprises agricoles.',
      );
    });

    // ── Personnaliser les modèles : la règle de signature ──

    Future<void> ouvrirModeles(WidgetTester t) async {
      await t.tap(find.byKey(const Key('onglet-attestations-Personnaliser les Modèles')));
      await t.pumpAndSettle();
    }

    testWidgets('⚠️ l\'onglet Modèles porte la règle de chaque modèle, préremplie par le serveur', (t) async {
      await afficher(t);
      await ouvrirModeles(t);

      for (final type in ['employe', 'stagiaire']) {
        expect(find.byKey(Key('att-reglage-$type')), findsOneWidget);
        expect(t.widget<TextField>(find.byKey(Key('att-seuil-$type'))).controller!.text, '12');
        expect(t.widget<TextField>(find.byKey(Key('att-$type-sig2-nom'))).controller!.text, 'SOGNIGBE Gbédjinou Serge Bruno');
        expect(t.widget<TextField>(find.byKey(Key('att-$type-sig1-fonction'))).controller!.text, 'Directeur de la Ferme ÉCOLE OLOUWACHEGOUN');
      }
    });

    testWidgets('⚠️⚠️ enregistrer la règle : le serveur d\'abord (PUT, clés du serveur), la base locale ensuite', (t) async {
      await afficher(t);
      await ouvrirModeles(t);

      await t.enterText(find.byKey(const Key('att-seuil-stagiaire')), '6');
      await t.enterText(find.byKey(const Key('att-stagiaire-sig2-nom')), 'KPOHAZOUNDE Jean');
      await t.ensureVisible(find.byKey(const Key('att-stagiaire-sig2-court')));
      await t.tap(find.byKey(const Key('att-stagiaire-sig2-court')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('att-enregistrer-reglage-stagiaire')));
      await t.tap(find.byKey(const Key('att-enregistrer-reglage-stagiaire')));
      await t.pumpAndSettle();

      final r = serveur.requetes.single;
      expect(r.method, 'PUT');
      expect(r.path, '/api/attestation-templates/stagiaire');
      final corps = r.data as Map;
      expect(corps['seuil_signature_mois'], 6);
      expect(corps['sig2_nom'], 'KPOHAZOUNDE Jean');
      expect(corps['sig2_court'], true);
      expect(corps['sig1_court'], true);
      expect(corps.containsKey('body_text'), isFalse, reason: 'le texte du modèle a son propre bouton');
      expect(find.text('Règle de signature enregistrée.'), findsOneWidget);

      final local = (await AttestationsRepository(database: db).reglage('stagiaire'))!;
      expect(local.seuilMois, 6);
      expect(local.signataires[2]!.nom, 'KPOHAZOUNDE Jean');
      expect(local.signataires[2]!.court, isTrue);
      expect((await AttestationsRepository(database: db).reglage('employe'))!.seuilMois, 12, reason: 'l\'autre modèle n\'est pas touché');
    });

    testWidgets('un seuil invalide est refusé AVANT l\'envoi, avec les mots du serveur', (t) async {
      await afficher(t);
      await ouvrirModeles(t);

      for (final (saisie, message) in [
        ('', 'Indiquez la durée en mois.'),
        ('abc', 'La durée est un nombre entier de mois.'),
        ('0', "La durée doit être d'au moins 1 mois."),
        ('121', 'La durée ne peut pas dépasser 120 mois.'),
      ]) {
        await t.enterText(find.byKey(const Key('att-seuil-stagiaire')), saisie);
        await t.ensureVisible(find.byKey(const Key('att-enregistrer-reglage-stagiaire')));
        await t.tap(find.byKey(const Key('att-enregistrer-reglage-stagiaire')));
        await t.pumpAndSettle();
        expect(t.widget<Text>(find.byKey(const Key('erreur-reglage-stagiaire'))).data, message);
      }

      expect(serveur.requetes, isEmpty);
    });

    testWidgets('⚠️⚠️ une règle refusée par le serveur n\'est PAS présentée comme enregistrée, et la base locale ne bouge pas', (t) async {
      await afficher(t, faux: _Serveur(code: 403, corps: {'message': 'Votre rôle ne permet pas de modifier les modèles.'}));
      await ouvrirModeles(t);

      await t.enterText(find.byKey(const Key('att-seuil-stagiaire')), '3');
      await t.ensureVisible(find.byKey(const Key('att-enregistrer-reglage-stagiaire')));
      await t.tap(find.byKey(const Key('att-enregistrer-reglage-stagiaire')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('att-echec')), findsOneWidget);
      expect(find.text('Règle de signature enregistrée.'), findsNothing);
      expect((await AttestationsRepository(database: db).reglage('stagiaire'))!.seuilMois, 12);
    });
  });
}
