import 'dart:convert';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/rh/attestations_repository.dart';
import 'package:agrierp/features/rh/attestations_vue.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.64 — ATTESTATIONS (`rh-attestations.html`).
///
/// ⚠️⚠️ **LE PDF EST PRODUIT ET COMPTÉ PAR LE SERVEUR.** L'aperçu est calculé au
/// poste avec les mêmes règles ; le document officiel, lui, vient du serveur, qui
/// en garde la trace d'audit. Hors ligne, rien n'est produit en cachette.
const _modeleEmploye =
    'Nous soussigné, Ferme École OLOUWACHEGOUN, attestons que [NOM], est '
    'employé(e) au sein de notre structure en qualité de [POSTE] sous contrat '
    '[CONTRAT] du [DATE_DEBUT] au [DATE_FIN].';

const _modeleStagiaire =
    'Nous soussigné, Ferme École OLOUWACHEGOUN, attestons que [NOM] a suivi '
    'avec assiduité et succès une formation pratique dans la spécialité '
    '[SPECIALITE] du [DATE_DEBUT] au [DATE_FIN].';

/// Faux serveur : retient les requêtes et rend la réponse voulue.
class _ServeurFeint extends Interceptor {
  _ServeurFeint({this.code = 200, this.corps, this.horsLigne = false});

  final int code;
  final Object? corps;
  final bool horsLigne;

  final requetes = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requetes.add(options);

    if (horsLigne) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
    } else if (code >= 400) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: code,
            // ⚠️ `ResponseType.bytes` : l'erreur arrive en OCTETS.
            data: corps is Map ? utf8.encode(jsonEncode(corps)) : corps,
          ),
        ),
      );
    } else {
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: corps ?? utf8.encode('%PDF-1.4 faux document'),
          headers: Headers.fromMap({
            'content-disposition': [
              'attachment; filename="attestation-agossou-jean.pdf"',
            ],
          }),
        ),
      );
    }
  }
}

class _ConnectiviteFeinte implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

void main() {
  late AppDatabase db;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  AttestationsRepository depot([_ServeurFeint? serveur]) {
    if (serveur == null) return AttestationsRepository(database: db);
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
      ..interceptors.add(serveur);
    return AttestationsRepository(
      database: db,
      client: ClientAttestations(client),
    );
  }

  Future<void> employe(
    String cle,
    String prenom,
    String nom, {
    String? poste,
    DateTime? embauche,
  }) => db
      .into(db.employees)
      .insert(
        EmployeesCompanion.insert(
          id: uuid(cle),
          firstName: prenom,
          lastName: nom,
          position: Value(poste),
          hireDate: Value(embauche),
        ),
      );

  Future<void> stagiaire(
    String cle,
    String prenom,
    String nom, {
    String? ecole,
    DateTime? debut,
    DateTime? fin,
  }) => db
      .into(db.internships)
      .insert(
        InternshipsCompanion.insert(
          id: uuid(cle),
          firstName: prenom,
          lastName: nom,
          school: Value(ecole),
          startDate: Value(debut),
          endDate: Value(fin),
        ),
      );

  Future<void> modeles({bool stagiaires = true}) async {
    await db
        .into(db.attestationTemplates)
        .insert(
          AttestationTemplatesCompanion.insert(
            id: uuid('m-employe'),
            type: 'employe',
            bodyText: _modeleEmploye,
          ),
        );
    if (stagiaires) {
      await db
          .into(db.attestationTemplates)
          .insert(
            AttestationTemplatesCompanion.insert(
              id: uuid('m-stagiaire'),
              type: 'stagiaire',
              bodyText: _modeleStagiaire,
            ),
          );
    }
  }

  const agossou = PersonneAttestation(
    id: 'x',
    nom: 'AGOSSOU',
    prenom: 'Jean',
    poste: 'Animalier',
    etablissement: null,
    debut: null,
    fin: null,
  );

  group('aperçu', () {
    test(
      '⚠️⚠️ texte exact d\'une attestation de travail (même qu\'au serveur)',
      () {
        final t = AttestationsRepository.apercu(
          modele: _modeleEmploye,
          type: 'employe',
          personne: agossou,
          contrat: 'CDD',
          debut: DateTime(2024, 3, 1),
          fin: DateTime(2025, 2, 28),
        );

        expect(
          t,
          'Nous soussigné, Ferme École OLOUWACHEGOUN, attestons que AGOSSOU '
          'Jean, est employé(e) au sein de notre structure en qualité de '
          'Animalier sous contrat CDD du 01/03/2024 au 28/02/2025.',
        );
      },
    );

    test('⚠️ sans date de fin : « ce jour », jamais une phrase brisée', () {
      final t = AttestationsRepository.apercu(
        modele: _modeleEmploye,
        type: 'employe',
        personne: agossou,
        contrat: 'CDI',
        debut: DateTime(2024, 3, 1),
      );

      expect(t, endsWith('du 01/03/2024 au ce jour.'));
    });

    test('stagiaire : spécialité et établissement viennent de l\'école', () {
      const adjovi = PersonneAttestation(
        id: 'y',
        nom: 'ADJOVI',
        prenom: 'Félicité',
        poste: null,
        etablissement: 'Agronomie',
        debut: null,
        fin: null,
      );

      final t = AttestationsRepository.apercu(
        modele:
            '[NOM] — [SPECIALITE] / [ETABLISSEMENT] : [DATE_DEBUT] → [DATE_FIN]',
        type: 'stagiaire',
        personne: adjovi,
        contrat: 'CDI',
        debut: DateTime(2026, 2, 1),
        fin: DateTime(2026, 5, 31),
      );

      expect(
        t,
        'ADJOVI Félicité — Agronomie / Agronomie : 01/02/2026 → 31/05/2026',
      );
    });

    test(
      'une balise inconnue reste telle quelle, un champ absent s\'efface',
      () {
        const sansPoste = PersonneAttestation(
          id: 'z',
          nom: 'X',
          prenom: 'Y',
          poste: null,
          etablissement: null,
          debut: null,
          fin: null,
        );

        final t = AttestationsRepository.apercu(
          modele: '[INCONNUE] / [POSTE] / [DATE_DEBUT]',
          type: 'employe',
          personne: sansPoste,
          contrat: 'CDI',
        );

        expect(t, '[INCONNUE] /  / ');
      },
    );

    test('le contrat n\'a pas de sens pour un stagiaire', () {
      final t = AttestationsRepository.apercu(
        modele: '[CONTRAT]',
        type: 'stagiaire',
        personne: agossou,
        contrat: 'CDI',
      );

      expect(t, '[CONTRAT]');
    });
  });

  group('lectures', () {
    test(
      'les employés sont triés par nom, avec leur date d\'embauche',
      () async {
        await employe('e1', 'Zoé', 'TOKPO', poste: 'Caissière');
        await employe(
          'e2',
          'Jean',
          'AGOSSOU',
          poste: 'Animalier',
          embauche: DateTime(2024, 3, 1),
        );

        final l = await depot().personnes('employe');

        expect(l.map((p) => p.libelle), ['AGOSSOU Jean', 'TOKPO Zoé']);
        expect(l.first.poste, 'Animalier');
        expect(l.first.debut, DateTime(2024, 3, 1));
        expect(
          l.first.fin,
          isNull,
          reason: 'un contrat en cours n\'a pas de fin',
        );
      },
    );

    test('les stagiaires portent école, début et fin de stage', () async {
      await stagiaire(
        's1',
        'Félicité',
        'ADJOVI',
        ecole: 'Agronomie',
        debut: DateTime(2026, 2, 1),
        fin: DateTime(2026, 5, 31),
      );

      final p = (await depot().personnes('stagiaire')).single;

      expect(p.etablissement, 'Agronomie');
      expect(p.poste, isNull);
      expect(p.debut, DateTime(2026, 2, 1));
      expect(p.fin, DateTime(2026, 5, 31));
    });

    test('⚠️ modèle jamais reçu : null, pas une chaîne vide', () async {
      expect(await depot().modele('employe'), isNull);

      await modeles();

      expect(await depot().modele('employe'), _modeleEmploye);
    });

    test(
      '⚠️⚠️ « émises » : inconnu avant le tirage, un vrai zéro après',
      () async {
        expect(await depot().emises('stagiaire'), isNull);

        await db
            .into(db.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                key: SyncEngine.cleAttestationsEmises('stagiaire'),
                value: '0',
              ),
            );

        expect(await depot().emises('stagiaire'), 0);
      },
    );
  });

  group('client HTTP', () {
    test(
      'une génération part vers /api/attestations avec les clés du serveur',
      () async {
        final s = _ServeurFeint();

        final pdf = await depot(s).generer(
          type: 'employe',
          personne: agossou,
          contrat: 'CDD',
          debut: DateTime(2024, 3, 1),
          note: 'Sérieux',
        );

        final r = s.requetes.single;
        expect(r.path, '/api/attestations');
        expect(r.method, 'POST');
        expect(r.responseType, ResponseType.bytes);
        expect(r.data, {
          'type': 'employe',
          'person_id': 'x',
          'contract_type': 'CDD',
          // ⚠️ `Y-m-d` : un ISO complet décalerait d'un jour selon le fuseau.
          'start_date': '2024-03-01',
          'note': 'Sérieux',
        });
        expect(String.fromCharCodes(pdf.octets), startsWith('%PDF'));
        expect(pdf.fichier, 'attestation-agossou-jean.pdf');
      },
    );

    test(
      'un stagiaire n\'envoie pas de type de contrat, ni de note vide',
      () async {
        final s = _ServeurFeint();

        await depot(s).generer(
          type: 'stagiaire',
          personne: agossou,
          contrat: 'CDI',
          debut: DateTime(2026, 2, 1),
          fin: DateTime(2026, 5, 31),
          note: '   ',
        );

        expect(s.requetes.single.data, {
          'type': 'stagiaire',
          'person_id': 'x',
          'start_date': '2026-02-01',
          'end_date': '2026-05-31',
        });
      },
    );

    test(
      '⚠️ un refus 403 rend le message du serveur, décodé des octets',
      () async {
        final r = depot(
          _ServeurFeint(
            code: 403,
            corps: {
              'message': "Votre rôle ne permet pas d'éditer des attestations.",
            },
          ),
        );

        await expectLater(
          r.generer(type: 'employe', personne: agossou, contrat: 'CDI'),
          throwsA(
            isA<EchecAttestation>().having(
              (e) => e.message,
              'message',
              "Votre rôle ne permet pas d'éditer des attestations.",
            ),
          ),
        );
      },
    );

    test('un 422 est rendu PAR CHAMP', () async {
      final r = depot(
        _ServeurFeint(
          code: 422,
          corps: {
            'errors': {
              'person_id': ["Cette personne n'existe plus."],
            },
          },
        ),
      );

      await expectLater(
        r.generer(type: 'employe', personne: agossou, contrat: 'CDI'),
        throwsA(
          isA<EchecAttestation>().having((e) => e.champs, 'champs', {
            'personne': "Cette personne n'existe plus.",
          }),
        ),
      );
    });

    test('401, 429 et réseau absent disent chacun la bonne chose', () async {
      Future<String> message(_ServeurFeint s) async {
        try {
          await depot(
            s,
          ).generer(type: 'employe', personne: agossou, contrat: 'CDI');
        } on EchecAttestation catch (e) {
          return e.message;
        }
        return '';
      }

      expect(
        await message(_ServeurFeint(code: 401)),
        contains('Session expirée'),
      );
      expect(
        await message(_ServeurFeint(code: 429)),
        contains('Trop de demandes'),
      );
      expect(
        await message(_ServeurFeint(horsLigne: true)),
        contains('nécessite le réseau'),
      );
    });

    test(
      '⚠️ un document vide n\'est jamais présenté comme une attestation',
      () async {
        await expectLater(
          depot(
            _ServeurFeint(corps: Uint8List(0)),
          ).generer(type: 'employe', personne: agossou, contrat: 'CDI'),
          throwsA(isA<EchecAttestation>()),
        );
      },
    );

    test('sans session, rien n\'est tenté', () async {
      await expectLater(
        depot().generer(type: 'employe', personne: agossou, contrat: 'CDI'),
        throwsA(
          isA<EchecAttestation>().having(
            (e) => e.message,
            'message',
            contains('Aucune session'),
          ),
        ),
      );
    });
  });

  group('modèles', () {
    test('⚠️ le serveur d\'abord, la base locale ensuite', () async {
      await modeles();
      final s = _ServeurFeint(corps: <String, dynamic>{});

      await depot(s).enregistrerModele('employe', 'Texte neuf pour [NOM].');

      final r = s.requetes.single;
      expect(r.method, 'PUT');
      expect(r.path, '/api/attestation-templates/employe');
      expect(r.data, {'body_text': 'Texte neuf pour [NOM].'});
      expect(await depot().modele('employe'), 'Texte neuf pour [NOM].');
      expect(await depot().modele('stagiaire'), _modeleStagiaire);
    });

    test('⚠️⚠️ refusé : le modèle local N\'EST PAS modifié', () async {
      await modeles();

      await expectLater(
        depot(
          _ServeurFeint(code: 403, corps: {'message': 'Interdit.'}),
        ).enregistrerModele('employe', 'Texte détourné'),
        throwsA(isA<EchecAttestation>()),
      );

      expect(await depot().modele('employe'), _modeleEmploye);
    });
  });

  group('absorption du tirage', () {
    SyncEngine moteur(Map<String, dynamic> pull) {
      final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
        ..interceptors.add(_Tirage(pull));
      return SyncEngine(
        database: db,
        client: client,
        deviceId: 'poste-test',
        connectivity: _ConnectiviteFeinte(),
      );
    }

    Map<String, dynamic> tirage({Object? modeles, Object? compteurs}) => {
      'server_time': '2026-08-17T12:00:00.000Z',
      'product_categories': <dynamic>[],
      'products': <dynamic>[],
      'livestock_lots': <dynamic>[],
      'attestation_templates': ?modeles,
      'attestation_counts': ?compteurs,
    };

    test(
      'modèles remplacés, compteurs gardés, bloc absent sans effet',
      () async {
        Map<String, dynamic> m(String id, String type, String texte) => {
          'id': id,
          'type': type,
          'body_text': texte,
        };

        await moteur(
          tirage(
            modeles: [
              m(uuid('m1'), 'employe', 'A [NOM]'),
              m(uuid('m2'), 'stagiaire', 'B [NOM]'),
            ],
            compteurs: {'employe': 3, 'stagiaire': 150},
          ),
        ).synchroniser();

        expect(await depot().modele('employe'), 'A [NOM]');
        expect(await depot().modele('stagiaire'), 'B [NOM]');
        expect(await depot().emises('stagiaire'), 150);
        expect(await depot().emises('employe'), 3);

        // Un tirage SANS ces blocs (serveur plus ancien) n'efface rien.
        await moteur(tirage()).synchroniser();
        expect(await db.select(db.attestationTemplates).get(), hasLength(2));
        expect(await depot().emises('stagiaire'), 150);

        // Un modèle modifié ailleurs REMPLACE l'ancien.
        await moteur(
          tirage(
            modeles: [
              m(uuid('m1'), 'employe', 'A modifié [NOM]'),
              m(uuid('m2'), 'stagiaire', 'B [NOM]'),
            ],
            compteurs: {'employe': 4, 'stagiaire': 151},
          ),
        ).synchroniser();
        expect(await depot().modele('employe'), 'A modifié [NOM]');
        expect(await depot().emises('stagiaire'), 151);
      },
    );
  });

  group('écran', () {
    late _ServeurFeint serveur;
    final jour = DateTime(2026, 7, 28);

    final livrees = <PdfAttestation>[];
    final imprimees = <PdfAttestation>[];

    setUp(() {
      livrees.clear();
      imprimees.clear();
    });

    Future<void> afficher(
      WidgetTester tester, {
      _ServeurFeint? faux,
      Size taille = const Size(1600, 2600),
      Future<String> Function(PdfAttestation)? enregistrer,
    }) async {
      serveur = faux ?? _ServeurFeint();
      tester.view.physicalSize = taille;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AttestationsVue(
                depot: depot(serveur),
                maintenant: jour,
                enregistrer:
                    enregistrer ??
                    (pdf) async {
                      livrees.add(pdf);
                      return r'C:\Documents\AgriERP\attestation.pdf';
                    },
                imprimer: (pdf) async => imprimees.add(pdf),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choisirPersonne(WidgetTester tester, String libelle) async {
      await tester.tap(find.byKey(const Key('att-personne')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(libelle).last);
      await tester.pumpAndSettle();
    }

    Future<void> donnees() async {
      await employe(
        'e1',
        'Jean',
        'AGOSSOU',
        poste: 'Animalier',
        embauche: DateTime(2024, 3, 1),
      );
      await stagiaire(
        's1',
        'Félicité',
        'ADJOVI',
        ecole: 'Agronomie',
        debut: DateTime(2026, 2, 1),
        fin: DateTime(2026, 5, 31),
      );
      await modeles();
    }

    String contenu(WidgetTester tester, String cle) =>
        tester.widget<TextField>(find.byKey(Key(cle))).controller!.text;

    testWidgets('titre, sous-titre, deux onglets dans l\'ordre, pas de carte', (
      tester,
    ) async {
      await donnees();
      await afficher(tester);

      expect(find.text('Attestations de Travail & de Stage'), findsOneWidget);
      expect(
        find.textContaining('Personnalisez les modèles officiels'),
        findsOneWidget,
      );
      final x1 = tester.getTopLeft(
        find.byKey(const Key('onglet-attestations-Générer une Attestation')),
      );
      final x2 = tester.getTopLeft(
        find.byKey(const Key('onglet-attestations-Personnaliser les Modèles')),
      );
      expect(x2.dx, greaterThan(x1.dx));
      expect(
        find.byType(CarteKpi),
        findsNWidgets(cartesAttendues('rh-attestations.html')),
      );
    });

    testWidgets('choisir une personne préremplit poste, dates et aperçu', (
      tester,
    ) async {
      await donnees();
      await afficher(tester);

      expect(find.byKey(const Key('att-apercu-vide')), findsOneWidget);

      await choisirPersonne(tester, 'AGOSSOU Jean');

      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('att-role')),
                matching: find.byType(Text),
              ),
            )
            .data,
        'Animalier',
      );
      expect(contenu(tester, 'att-debut'), '01/03/2024');
      expect(contenu(tester, 'att-fin'), '');
      expect(
        tester.widget<Text>(find.byKey(const Key('att-apercu-corps'))).data,
        'Nous soussigné, Ferme École OLOUWACHEGOUN, attestons que AGOSSOU '
        'Jean, est employé(e) au sein de notre structure en qualité de '
        'Animalier sous contrat CDI du 01/03/2024 au ce jour.',
      );
    });

    testWidgets('le contrat et la note modifient l\'aperçu en direct', (
      tester,
    ) async {
      await donnees();
      await afficher(tester);
      await choisirPersonne(tester, 'AGOSSOU Jean');

      await tester.tap(find.byKey(const Key('att-contrat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CDD').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('att-note')), 'Très assidu');
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('att-apercu-corps'))).data,
        contains('sous contrat CDD'),
      );
      expect(find.byKey(const Key('att-apercu-note')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('att-apercu-note'))).data,
        'Très assidu',
      );
    });

    testWidgets(
      'stagiaire : « Établissement », pas de contrat, dates du stage',
      (tester) async {
        await donnees();
        await afficher(tester);

        await tester.tap(find.byKey(const Key('att-type-stagiaire')));
        await tester.pumpAndSettle();
        await choisirPersonne(tester, 'ADJOVI Félicité');

        expect(find.text('ÉTABLISSEMENT'), findsOneWidget);
        expect(find.byKey(const Key('att-contrat')), findsNothing);
        expect(contenu(tester, 'att-debut'), '01/02/2026');
        expect(contenu(tester, 'att-fin'), '31/05/2026');
        expect(
          tester.widget<Text>(find.byKey(const Key('att-apercu-titre'))).data,
          'ATTESTATION DE STAGE',
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('att-apercu-corps'))).data,
          contains('dans la spécialité Agronomie'),
        );
      },
    );

    testWidgets('⚠️ l\'en-tête du certificat est celui de la page web', (
      tester,
    ) async {
      await donnees();
      await afficher(tester);

      expect(find.text('FERME ÉCOLE OLOUWACHEGOUN'), findsOneWidget);
      expect(find.text('RCCM : RB/PNO/22 A 33870'), findsOneWidget);
      expect(find.text('OLOUKOUNLE Olouchegoun Hassimiyou'), findsOneWidget);
      expect(find.text('Fait à Ikpinlè, le 28/07/2026.'), findsOneWidget);
      // L'IFU de démonstration du prototype n'est PAS repris.
      expect(find.textContaining('3202601234567'), findsNothing);
    });

    testWidgets('⚠️ modèle pas encore reçu : l\'aperçu le dit', (tester) async {
      await employe('e1', 'Jean', 'AGOSSOU', poste: 'Animalier');
      await afficher(tester);
      await choisirPersonne(tester, 'AGOSSOU Jean');

      expect(find.textContaining('pas encore reçu du serveur'), findsOneWidget);
      expect(find.byKey(const Key('att-apercu-corps')), findsNothing);
    });

    testWidgets('générer sans personne : « obligatoire », rien n\'est envoyé', (
      tester,
    ) async {
      await donnees();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('att-generer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('erreur-personne')), findsOneWidget);
      expect(serveur.requetes, isEmpty);
    });

    testWidgets('une date invalide est refusée avant l\'envoi', (tester) async {
      await donnees();
      await afficher(tester);
      await choisirPersonne(tester, 'AGOSSOU Jean');

      await tester.enterText(find.byKey(const Key('att-fin')), '31/02/2026');
      await tester.tap(find.byKey(const Key('att-generer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('erreur-fin')), findsOneWidget);
      expect(serveur.requetes, isEmpty);
    });

    testWidgets(
      '⚠️⚠️ une génération réussie écrit le PDF et propose l\'impression',
      (tester) async {
        await donnees();
        await afficher(tester);
        await choisirPersonne(tester, 'AGOSSOU Jean');

        await tester.tap(find.byKey(const Key('att-generer')));
        await tester.pumpAndSettle();

        expect(serveur.requetes, hasLength(1));
        expect(livrees, hasLength(1));
        expect(livrees.single.fichier, 'attestation-agossou-jean.pdf');
        expect(find.byKey(const Key('att-reussi')), findsOneWidget);
        expect(
          find.textContaining(r'C:\Documents\AgriERP\attestation.pdf'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('att-imprimer')));
        await tester.pumpAndSettle();
        expect(imprimees, hasLength(1));
      },
    );

    testWidgets(
      '⚠️⚠️ hors ligne : échec visible, aucun fichier, aucun succès',
      (tester) async {
        await donnees();
        await afficher(tester, faux: _ServeurFeint(horsLigne: true));
        await choisirPersonne(tester, 'AGOSSOU Jean');

        await tester.tap(find.byKey(const Key('att-generer')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('att-echec')), findsOneWidget);
        expect(find.byKey(const Key('att-reussi')), findsNothing);
        expect(find.textContaining('nécessite le réseau'), findsOneWidget);
        expect(livrees, isEmpty);
        expect(find.byKey(const Key('att-imprimer')), findsNothing);
      },
    );

    testWidgets('un refus de rôle affiche le message du serveur', (
      tester,
    ) async {
      await donnees();
      await afficher(
        tester,
        faux: _ServeurFeint(
          code: 403,
          corps: {
            'message': "Votre rôle ne permet pas d'éditer des attestations.",
          },
        ),
      );
      await choisirPersonne(tester, 'AGOSSOU Jean');

      await tester.tap(find.byKey(const Key('att-generer')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Votre rôle ne permet pas'), findsOneWidget);
      expect(livrees, isEmpty);
    });

    testWidgets('une écriture de fichier qui échoue est dite, pas avalée', (
      tester,
    ) async {
      await donnees();
      await afficher(
        tester,
        enregistrer: (_) async => throw const FileSystemExceptionFeinte(),
      );
      await choisirPersonne(tester, 'AGOSSOU Jean');

      await tester.tap(find.byKey(const Key('att-generer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('att-echec')), findsOneWidget);
      expect(
        find.textContaining("Impossible d'écrire le fichier"),
        findsOneWidget,
      );
    });

    testWidgets('onglet Modèles : deux textes préremplis et leurs balises', (
      tester,
    ) async {
      await donnees();
      await afficher(tester);

      await tester.tap(
        find.byKey(const Key('onglet-attestations-Personnaliser les Modèles')),
      );
      await tester.pumpAndSettle();

      expect(contenu(tester, 'att-texte-employe'), _modeleEmploye);
      expect(contenu(tester, 'att-texte-stagiaire'), _modeleStagiaire);
      expect(
        find.text(
          'Balises disponibles : [NOM], [POSTE], [CONTRAT], [DATE_DEBUT], [DATE_FIN]',
        ),
        findsOneWidget,
      );
      expect(find.text('ENREGISTRER CE MODÈLE'), findsNothing);
      expect(find.text('Enregistrer ce Modèle'), findsNWidgets(2));
    });

    testWidgets('⚠️ un modèle enregistré est envoyé puis relu par l\'aperçu', (
      tester,
    ) async {
      await donnees();
      await afficher(tester, faux: _ServeurFeint(corps: <String, dynamic>{}));

      await tester.tap(
        find.byKey(const Key('onglet-attestations-Personnaliser les Modèles')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('att-texte-employe')),
        'Texte neuf pour [NOM].',
      );
      await tester.tap(find.byKey(const Key('att-enregistrer-employe')));
      await tester.pumpAndSettle();

      expect(serveur.requetes.single.data, {
        'body_text': 'Texte neuf pour [NOM].',
      });
      expect(find.text('Modèle enregistré avec succès.'), findsOneWidget);
      expect(await depot().modele('employe'), 'Texte neuf pour [NOM].');
    });

    testWidgets('un modèle vide est refusé avant l\'envoi', (tester) async {
      await donnees();
      await afficher(tester);

      await tester.tap(
        find.byKey(const Key('onglet-attestations-Personnaliser les Modèles')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('att-texte-employe')), '  ');
      await tester.tap(find.byKey(const Key('att-enregistrer-employe')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('erreur-modele-employe')), findsOneWidget);
      expect(serveur.requetes, isEmpty);
    });

    testWidgets(
      '⚠️⚠️ un modèle refusé par le serveur n\'est pas présenté comme enregistré',
      (tester) async {
        await donnees();
        await afficher(
          tester,
          faux: _ServeurFeint(
            code: 403,
            corps: {
              'message': 'Votre rôle ne permet pas de modifier les modèles.',
            },
          ),
        );

        await tester.tap(
          find.byKey(
            const Key('onglet-attestations-Personnaliser les Modèles'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('att-texte-employe')),
          'Détourné',
        );
        await tester.tap(find.byKey(const Key('att-enregistrer-employe')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('att-echec')), findsOneWidget);
        expect(find.byKey(const Key('att-reussi')), findsNothing);
        expect(
          find.textContaining('ne permet pas de modifier'),
          findsOneWidget,
        );
        expect(await depot().modele('employe'), _modeleEmploye);
      },
    );

    testWidgets('lg: deux colonnes 45 / 55 ; sous lg: elles s\'empilent', (
      tester,
    ) async {
      await donnees();

      await afficher(tester, taille: const Size(1600, 2600));
      final f = tester.getRect(find.byKey(const Key('att-formulaire')));
      final a = tester.getRect(find.byKey(const Key('att-apercu')));
      expect(f.top, a.top);
      expect(f.width / a.width, closeTo(45 / 55, 0.02));

      await afficher(tester, taille: const Size(800, 3600));
      final f2 = tester.getRect(find.byKey(const Key('att-formulaire')));
      final a2 = tester.getRect(find.byKey(const Key('att-apercu')));
      expect(a2.top, greaterThan(f2.bottom));
    });
  });
}

/// Intercepteur de tirage : rend toujours le même corps de tirage.
class _Tirage extends Interceptor {
  _Tirage(this.corps);

  final Map<String, dynamic> corps;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path.contains('push') ? <String, dynamic>{} : corps,
      ),
    );
  }
}

/// Erreur de disque simulée (le test n'écrit jamais sur un vrai disque).
class FileSystemExceptionFeinte implements Exception {
  const FileSystemExceptionFeinte();

  @override
  String toString() => 'disque plein';
}
