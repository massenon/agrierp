import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/emissions_attestation.dart';
import 'package:agrierp/features/rh/attestations_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ATT-3 — LE POSTE FABRIQUE LUI-MÊME L'ATTESTATION (demande du client : « le poste doit produire aussi »).
///
/// Ce que le serveur garde : le numéro (jamais inventé au poste) et la trace d'audit, par `POST /api/attestations/emissions`.
/// Ce fichier prouve : le PDF produit au poste est un vrai document (une page A4 paysage, polices et images embarquées,
/// texte lisible), la file d'émissions survit au redémarrage, ne perd rien avant l'accord du serveur, et se vide sans
/// requête superflue.

/// Faux serveur d'émissions : rend un numéro par émission, ou coupe le réseau.
class _Emissions extends Interceptor {
  _Emissions({this.horsLigne = false, this.refus});

  bool horsLigne;
  final int? refus;
  final requetes = <RequestOptions>[];
  final _numeros = <String, String>{};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requetes.add(options);

    if (horsLigne) {
      handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError));
    } else if (refus != null) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: refus,
            data: utf8.encode(jsonEncode({'message': 'Refusé.'})),
          ),
        ),
      );
    } else {
      final id = (options.data as Map)['id'] as String;
      final deja = _numeros.containsKey(id);
      final numero = _numeros.putIfAbsent(id, () => 'N°${(_numeros.length + 1).toString().padLeft(2, '0')}/2026/FEO/DG');
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: {'numero': numero, 'deja_enregistree': deja},
        ),
      );
    }
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  const personne = PersonneAttestation(
    id: 'p1',
    nom: 'ADJOVI',
    prenom: 'Félicité',
    poste: null,
    etablissement: 'Agronomie',
    debut: null,
    fin: null,
  );

  AttestationsRepository depot([_Emissions? serveur]) => AttestationsRepository(
    database: db,
    client: serveur == null
        ? null
        : ClientAttestations(Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur)),
  );

  Future<AttestationProduite> produire(
    AttestationsRepository r, {
    DateTime? debut,
    DateTime? fin,
    List<String> domaines = const ['maraichage', 'gestion'],
  }) => r.produire(
    type: 'stagiaire',
    personne: personne,
    contrat: '',
    debut: debut ?? DateTime(2026, 2, 1),
    fin: fin ?? DateTime(2026, 5, 31),
    domaines: domaines,
    birthDate: DateTime(2001, 3, 14),
    birthPlace: 'Pobè',
    civilite: 'Mme',
    aujourdhui: DateTime(2026, 10, 27),
  );

  group('le PDF fabriqué au poste', () {
    testWidgets('est un vrai document : une page A4 paysage, polices et images embarquées', (tester) async {
      await tester.runAsync(() async {
        final r = await produire(depot(_Emissions()));
        final octets = r.pdf.octets;

        expect(latin1.decode(octets.take(5).toList()), '%PDF-');
        // Polices (Caladea, Carlito, Bevan) et images (décor, filigrane, logo) EMBARQUÉES : bien plus que quelques ko.
        expect(octets.length, greaterThan(150 * 1024));
        expect(r.pdf.fichier, 'attestation-adjovi-felicite.pdf');

        final binaire = await Process.run('which', ['pdfinfo']);
        if (binaire.exitCode != 0) {
          markTestSkipped('pdfinfo absent : la géométrie du PDF ne peut pas être relue ici.');
          return;
        }
        final fichier = File('${Directory.systemTemp.path}/att_poste_info.pdf')..writeAsBytesSync(octets);
        addTearDown(() => fichier.existsSync() ? fichier.deleteSync() : null);

        final info = (await Process.run('pdfinfo', [fichier.path])).stdout as String;
        expect(info, contains(RegExp(r'Pages:\s+1\b')));
        expect(info, contains(RegExp(r'Page size:\s+84[12](\.\d+)? x 595(\.\d+)? pts')));
      });
    });

    testWidgets('⚠️ le numéro du serveur est imprimé ; sans serveur, il reste VIDE (jamais inventé)', (tester) async {
      await tester.runAsync(() async {
        final avec = await produire(depot(_Emissions()));
        expect(avec.numero, 'N°01/2026/FEO/DG');
        expect(avec.horsLigne, isFalse);

        final sans = await produire(depot(_Emissions(horsLigne: true)));
        expect(sans.numero, isNull);
        expect(sans.horsLigne, isTrue);
        expect(AttestationsRepository.numeroVide(2026), 'N°—/2026/FEO/DG');
      });
    });

    testWidgets('texte lisible : pdftotext relit le nom, le numéro, la date et les signataires (sauté sans pdftotext)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final binaire = await Process.run('which', ['pdftotext']);
        if (binaire.exitCode != 0) {
          markTestSkipped('pdftotext absent : le texte du PDF ne peut pas être relu ici.');
          return;
        }

        // Plus d'un an : les trois signataires.
        final r = await produire(depot(_Emissions()), debut: DateTime(2025, 1, 6), fin: DateTime(2026, 5, 31));
        final fichier = File('${Directory.systemTemp.path}/att_poste_test.pdf')..writeAsBytesSync(r.pdf.octets);
        addTearDown(() => fichier.existsSync() ? fichier.deleteSync() : null);

        final texte = (await Process.run('pdftotext', ['-layout', fichier.path, '-'])).stdout as String;

        expect(texte, contains('ATTESTATION DE FORMATION'));
        expect(texte, contains('N°01/2026/FEO/DG'));
        expect(texte, contains('27 octobre 2026'));
        expect(texte, contains('ADJOVI Félicité'));
        expect(texte, contains('née'));
        expect(texte, contains('Conduite de cultures maraîchères'));
        expect(texte, contains('Notion de gestion des entreprises agricoles.'));
        expect(texte, contains('Examinateur'));
        expect(texte, contains('Président du Jury'));
        expect(texte, contains('Hassimiyou O. OLOUKOUNLE'));
      });
    });

    testWidgets('⚠️ jusqu\'à un an, le promoteur SEUL signe ; au-delà, trois signataires', (tester) async {
      await tester.runAsync(() async {
        final regle = ReglageSignature.defaut;
        final court = regle.requis(debut: DateTime(2026, 2, 1), fin: DateTime(2026, 5, 31), aujourdhui: DateTime(2026, 10, 27));
        final long = regle.requis(debut: DateTime(2025, 1, 6), fin: DateTime(2026, 5, 31), aujourdhui: DateTime(2026, 10, 27));

        expect(court.map((s) => s.position), [1]);
        expect(long.map((s) => s.position), [2, 3, 1]);
      });
    });
  });

  group('la file des émissions', () {
    test('une émission hors ligne attend ; la file survit (relue depuis la base)', () async {
      final instant = DateTime.utc(2026, 10, 27, 9, 30);
      await FileEmissionsAttestation(db).ajouter(EmissionEnAttente(id: 'e1', type: 'stagiaire', instant: instant));

      final relue = await FileEmissionsAttestation(db).lire();

      expect(relue, hasLength(1));
      expect(relue.single.id, 'e1');
      expect(relue.single.instant, instant, reason: 'l\'instant de l\'ÉMISSION, jamais celui de l\'envoi');
    });

    test('la même émission n\'est pas mise deux fois en file', () async {
      final f = FileEmissionsAttestation(db);
      final e = EmissionEnAttente(id: 'e1', type: 'employe', instant: DateTime.utc(2026, 10, 27));

      await f.ajouter(e);
      await f.ajouter(e);

      expect(await f.lire(), hasLength(1));
    });

    test('⚠️ file vide : AUCUNE requête au serveur', () async {
      final s = _Emissions();

      final n = await AttestationsRepository.viderLaFile(db, ClientAttestations(Dio()..interceptors.add(s)));

      expect(n, 0);
      expect(s.requetes, isEmpty);
    });

    test('⚠️ hors ligne : rien n\'est retiré ; le réseau revenu, tout est déclaré dans l\'ordre, une fois', () async {
      final s = _Emissions(horsLigne: true);
      final client = ClientAttestations(Dio(BaseOptions(baseUrl: 'http://x'))..interceptors.add(s));
      final f = FileEmissionsAttestation(db);
      await f.ajouter(EmissionEnAttente(id: 'e1', type: 'stagiaire', instant: DateTime.utc(2026, 10, 26)));
      await f.ajouter(EmissionEnAttente(id: 'e2', type: 'employe', instant: DateTime.utc(2026, 10, 27)));

      expect(await AttestationsRepository.viderLaFile(db, client), 0);
      expect(await f.lire(), hasLength(2), reason: 'une émission perdue en route n\'existerait nulle part');
      expect(s.requetes, hasLength(1), reason: 'la file s\'arrête au premier échec');

      s.horsLigne = false;
      s.requetes.clear();

      expect(await AttestationsRepository.viderLaFile(db, client), 2);
      expect(await f.lire(), isEmpty);
      expect([for (final r in s.requetes) (r.data as Map)['id']], ['e1', 'e2']);
      expect((s.requetes.first.data as Map)['issued_at'], '2026-10-26T00:00:00.000Z');
    });

    test('un refus définitif (422) retire l\'émission : elle bloquerait la file sinon', () async {
      final s = _Emissions(refus: 422);
      final client = ClientAttestations(Dio(BaseOptions(baseUrl: 'http://x'))..interceptors.add(s));
      final f = FileEmissionsAttestation(db);
      await f.ajouter(EmissionEnAttente(id: 'e1', type: 'stagiaire', instant: DateTime.utc(2026, 10, 26)));

      expect(await AttestationsRepository.viderLaFile(db, client), 1);
      expect(await f.lire(), isEmpty);
    });

    test('une panne du serveur (500) ou une session expirée (401) garde l\'émission', () async {
      for (final code in [500, 401]) {
        final s = _Emissions(refus: code);
        final client = ClientAttestations(Dio(BaseOptions(baseUrl: 'http://x'))..interceptors.add(s));
        final f = FileEmissionsAttestation(db);
        await f.ajouter(EmissionEnAttente(id: 'e$code', type: 'stagiaire', instant: DateTime.utc(2026, 10, 26)));

        expect(await AttestationsRepository.viderLaFile(db, client), 0, reason: '$code');
        expect(await f.lire(), isNotEmpty, reason: '$code');
      }
    });
  });

  group('produire', () {
    testWidgets('hors ligne : produite, émission en file avec l\'instant du Bénin converti en UTC', (tester) async {
      await tester.runAsync(() async {
        final r = await produire(depot(_Emissions(horsLigne: true)));

        expect(r.horsLigne, isTrue);
        final file = await FileEmissionsAttestation(db).lire();
        expect(file, hasLength(1));
        expect(file.single.type, 'stagiaire');
        // 27/10/2026 00:00 heure du Bénin (UTC+1) = 26/10/2026 23:00 UTC.
        expect(file.single.instant, DateTime.utc(2026, 10, 26, 23));
      });
    });

    testWidgets('⚠️ un refus (403) ne produit rien et ne met rien en file', (tester) async {
      await tester.runAsync(() async {
        await expectLater(produire(depot(_Emissions(refus: 403))), throwsA(isA<EchecAttestation>()));
        expect(await FileEmissionsAttestation(db).lire(), isEmpty);
      });
    });

    test('les puces suivent l\'ordre du modèle, quel que soit l\'ordre des cases cochées', () {
      expect(AttestationsRepository.domainesPuces.keys, ['maraichage', 'elevage', 'rations', 'gestion']);
    });
  });
}
