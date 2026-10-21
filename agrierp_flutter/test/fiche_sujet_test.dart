import 'dart:convert';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/pdf_recu.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/elevage/fiche_sujet_screen.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_repository.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_screen.dart';
import 'package:agrierp/features/elevage/sujets_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull, Table;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'cartes_attendues.dart';

/// Ticket F0.65 — FICHE SUJET (`animal-details.html`).
///
/// ⚠️⚠️ **RIEN N'EST FABRIQUÉ.** Un mouvement, une saillie, un soin figurent à
/// l'écran parce qu'ils ont été SAISIS. Les trois onglets sans source affichent
/// leur motif. Le PDF est produit par le serveur, qui n'est jamais contourné.
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
              'attachment; filename="sujet-LAP-2026-0143.pdf"',
            ],
          }),
        ),
      );
    }
  }
}

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

  final lot = uuid('lot-cuni');
  final sujetId = uuid('sujet-143');
  final maintenant = DateTime(2026, 7, 28);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  SujetsRepository depot([_ServeurFeint? serveur]) {
    if (serveur == null) return SujetsRepository(database: db);
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
      ..interceptors.add(serveur);
    return SujetsRepository(database: db, client: ClientSujets(client));
  }

  Future<void> sujet({
    String? id,
    String identifiant = 'LAP-2026-0143',
    String? lotId,
    String statut = 'actif',
    DateTime? naissance,
    DateTime? sortie,
    String? motifSortie,
    bool actif = true,
    String sexe = 'F',
    String? cage = 'C5',
  }) => db
      .into(db.animals)
      .insert(
        AnimalsCompanion.insert(
          id: id ?? sujetId,
          identifier: identifiant,
          speciesLabel: const Value('Lapins'),
          lotId: Value(lotId),
          lotCode: Value(lotId == null ? null : 'LOT-CUNI-2026-011'),
          sex: Value(sexe),
          breed: const Value('Néo-Zélandais Blanc'),
          birthDate: Value(naissance ?? DateTime(2026, 2, 12)),
          entryDate: Value(DateTime(2026, 2, 15)),
          origin: const Value('Naissance interne (Lot LOT-CUNI-2026-002)'),
          cage: Value(cage),
          status: Value(statut),
          exitDate: Value(sortie),
          exitReason: Value(motifSortie),
          isActive: Value(actif),
        ),
      );

  Future<void> saillie(
    String cle, {
    required String mere,
    String? pere,
    DateTime? date,
    DateTime? miseBas,
    int? vivants,
    int? morts,
    String statut = 'en_cours',
  }) => db
      .into(db.livestockReproductionEvents)
      .insert(
        LivestockReproductionEventsCompanion.insert(
          id: uuid('rep-$cle'),
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          lotId: lot,
          motherRef: mere,
          sireRef: Value(pere),
          saillieDate: Value(date),
          miseBasDateActual: Value(miseBas),
          nesVivants: Value(vivants),
          nesMorts: Value(morts),
          status: Value(statut),
          updatedAt: DateTime(2026, 7, 1),
        ),
      );

  Future<void> soin(
    String cle,
    String lotId,
    DateTime date,
    String action, {
    String? produit,
    String? dose,
  }) => db
      .into(db.veterinaryRecords)
      .insert(
        VeterinaryRecordsCompanion.insert(
          id: uuid('soin-$cle'),
          deviceId: 'serveur',
          updatedAt: date,
          lotId: lotId,
          actionType: action,
          recordDate: date,
          productUsed: Value(produit),
          dose: Value(dose),
        ),
      );

  group('âge', () {
    test('mois ENTIERS écoulés, comme Carbon::diffInMonths', () {
      final n = DateTime(2026, 2, 12);

      expect(SujetsRepository.moisEntre(n, DateTime(2026, 7, 12)), 5);
      expect(SujetsRepository.moisEntre(n, DateTime(2026, 7, 11)), 4);
      expect(SujetsRepository.moisEntre(n, DateTime(2026, 2, 12)), 0);
      expect(SujetsRepository.moisEntre(n, DateTime(2027, 2, 12)), 12);
      // Une date de naissance dans le futur ne donne pas un âge négatif.
      expect(SujetsRepository.moisEntre(DateTime(2027, 1, 1), n), 0);
    });
  });

  group('lecture', () {
    test(
      '⚠️⚠️ la reproduction se retrouve par mère OU géniteur, jamais ailleurs',
      () async {
        await sujet();
        await saillie(
          'a',
          mere: 'LAP-2026-0143',
          pere: 'LAP-2026-0098',
          date: DateTime(2026, 7, 1),
        );
        await saillie(
          'b',
          mere: 'LAP-2026-0001',
          pere: 'LAP-2026-0143',
          date: DateTime(2026, 5, 1),
          miseBas: DateTime(2026, 6, 1),
          vivants: 7,
          morts: 1,
          statut: 'termine',
        );
        // Une saillie qui ne le concerne pas.
        await saillie(
          'c',
          mere: 'LAP-2026-0500',
          pere: 'LAP-2026-0501',
          date: DateTime(2026, 6, 1),
        );

        final f = (await depot().charger(sujetId, maintenant: maintenant))!;

        expect(f.reproduction.map((e) => e.role), ['Mère', 'Géniteur']);
        // La plus récente d'abord.
        expect(f.reproduction.first.saillie, DateTime(2026, 7, 1));
        expect(f.reproduction.last.vivants, 7);
        expect(f.reproduction.last.morts, 1);
        expect(f.reproduction.first.statut, 'En cours');
        expect(f.reproduction.last.statut, 'Termine');
      },
    );

    test(
      '⚠️ les soins sont ceux de la BANDE du sujet, pas d\'une autre',
      () async {
        await sujet(lotId: lot);
        await soin(
          '1',
          lot,
          DateTime(2026, 6, 1),
          'Vaccination',
          produit: 'Myxomatose',
          dose: '1 dose',
        );
        await soin('2', lot, DateTime(2026, 7, 1), 'Déparasitage');
        await soin('x', uuid('autre-lot'), DateTime(2026, 7, 2), 'Vaccination');

        final f = (await depot().charger(sujetId, maintenant: maintenant))!;

        expect(f.soins.map((s) => s.action), ['Déparasitage', 'Vaccination']);
        expect(f.soins.last.produit, 'Myxomatose');
      },
    );

    test(
      'un sujet sans bande n\'a aucun soin, et n\'en emprunte pas',
      () async {
        await sujet();
        await soin('1', lot, DateTime(2026, 6, 1), 'Vaccination');

        final f = (await depot().charger(sujetId, maintenant: maintenant))!;

        expect(f.soins, isEmpty);
      },
    );

    test(
      '⚠️⚠️ mouvements : l\'entrée seule, et la sortie QUAND elle a eu lieu',
      () async {
        await sujet();
        var f = (await depot().charger(sujetId, maintenant: maintenant))!;
        expect(f.mouvements, hasLength(1));
        expect(f.mouvements.single.libelle, 'Entrée en élevage');
        expect(
          f.mouvements.single.detail,
          'Naissance interne (Lot LOT-CUNI-2026-002)',
        );

        await db.delete(db.animals).go();
        await sujet(
          statut: 'vendu',
          sortie: DateTime(2026, 6, 1),
          motifSortie: 'Vente à un éleveur',
          actif: false,
        );
        f = (await depot().charger(sujetId, maintenant: maintenant))!;

        expect(f.mouvements, hasLength(2));
        expect(f.mouvements.last.libelle, 'Sortie — Vendu', reason: 'BS-Q11 : le libellé du statut, plus la valeur technique');
        expect(f.mouvements.last.detail, 'Vente à un éleveur');
      },
    );

    test('une sortie sans motif le dit, au lieu d\'en inventer un', () async {
      await sujet(statut: 'mort', sortie: DateTime(2026, 6, 1), actif: false);

      final f = (await depot().charger(sujetId, maintenant: maintenant))!;

      expect(f.mouvements.last.detail, 'Motif non précisé');
    });

    test('l\'historique mêle tout, du plus récent au plus ancien', () async {
      await sujet(lotId: lot);
      await saillie('a', mere: 'LAP-2026-0143', date: DateTime(2026, 7, 1));
      await soin(
        '1',
        lot,
        DateTime(2026, 6, 1),
        'Vaccination',
        produit: 'Myxo',
      );

      final h = (await depot().charger(
        sujetId,
        maintenant: maintenant,
      ))!.historique;

      expect(h.map((l) => l.type), [
        'Reproduction',
        'Soin (bande)',
        'Mouvement',
      ]);
      expect(h.first.libelle, 'Saillie (en cours)');
      expect(h[1].libelle, 'Vaccination — Myxo');
    });

    test('âge, badge, sexe', () async {
      await sujet();
      final f = (await depot().charger(sujetId, maintenant: maintenant))!;

      expect(f.ageEnMois, 5);
      expect(f.badge, 'Actif — Reproducteur');
      expect(f.sexe, 'Femelle');
    });

    test('un sujet sorti porte son statut, pas « Actif »', () async {
      await sujet(statut: 'vendu', actif: false, sexe: 'M');
      final f = (await depot().charger(sujetId, maintenant: maintenant))!;

      expect(f.badge, 'Vendu');
      expect(f.sexe, 'Mâle');
    });

    test('⚠️ BS-Q11 — un sujet réformé s écrit « Réformé » (badge et mouvement), jamais « Reforme »', () async {
      await sujet(
        statut: 'reforme',
        sortie: DateTime(2026, 6, 1),
        motifSortie: 'Réforme pour âge',
        actif: false,
      );
      final f = (await depot().charger(sujetId, maintenant: maintenant))!;

      expect(f.badge, 'Réformé');
      expect(f.mouvements.last.libelle, 'Sortie — Réformé');
      expect(f.historique.map((l) => l.libelle).join('|'), isNot(contains('Reforme')));
    });

    test('un sujet inconnu rend null', () async {
      expect(await depot().charger(uuid('inconnu')), isNull);
    });

    test(
      'les identifiants connus servent à rendre une référence cliquable',
      () async {
        await sujet();

        expect(await depot().identifiants(), {'LAP-2026-0143': sujetId});
      },
    );
  });

  group('export PDF', () {
    test(
      'GET /api/animals/{id}/pdf, en octets, avec le nom du serveur',
      () async {
        final s = _ServeurFeint();

        final pdf = await depot(s).exporterPdf(sujetId);

        expect(s.requetes.single.path, '/api/animals/$sujetId/pdf');
        expect(s.requetes.single.method, 'GET');
        expect(s.requetes.single.responseType, ResponseType.bytes);
        expect(String.fromCharCodes(pdf.octets), startsWith('%PDF'));
        expect(pdf.fichier, 'sujet-LAP-2026-0143.pdf');
      },
    );

    test(
      '⚠️ un refus 403 rend la phrase du serveur, décodée des octets',
      () async {
        await expectLater(
          depot(
            _ServeurFeint(code: 403, corps: {'message': 'Pas pour vous.'}),
          ).exporterPdf(sujetId),
          throwsA(
            isA<EchecSujet>().having(
              (e) => e.message,
              'message',
              'Pas pour vous.',
            ),
          ),
        );
      },
    );

    test(
      '404, 401, 429 et réseau absent disent chacun la bonne chose',
      () async {
        Future<String> message(_ServeurFeint s) async {
          try {
            await depot(s).exporterPdf(sujetId);
          } on EchecSujet catch (e) {
            return e.message;
          }
          return '';
        }

        expect(
          await message(_ServeurFeint(code: 404)),
          contains("n'existe plus"),
        );
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
      },
    );

    test('un document vide n\'est jamais présenté comme une fiche', () async {
      await expectLater(
        depot(_ServeurFeint(corps: <int>[])).exporterPdf(sujetId),
        throwsA(isA<EchecSujet>()),
      );
    });

    test('sans session, rien n\'est tenté', () async {
      await expectLater(
        depot().exporterPdf(sujetId),
        throwsA(
          isA<EchecSujet>().having(
            (e) => e.message,
            'message',
            contains('Aucune session'),
          ),
        ),
      );
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

    Map<String, dynamic> tirage(Object? sujets) => {
      'server_time': '2026-08-17T12:00:00.000Z',
      'product_categories': <dynamic>[],
      'products': <dynamic>[],
      'livestock_lots': <dynamic>[],
      'animals': ?sujets,
    };

    Map<String, dynamic> ligne(
      String id,
      String identifiant, {
      bool actif = true,
    }) => {
      'id': id,
      'identifier': identifiant,
      'species_label': 'Lapins',
      'lot_id': null,
      'lot_code': null,
      'category': 'reproducteur',
      'sex': 'F',
      'breed': 'Néo-Zélandais',
      'birth_date': '2026-02-12',
      'entry_date': '2026-02-15',
      'origin': 'Naissance interne',
      'cage': 'C5',
      'status': actif ? 'actif' : 'vendu',
      'exit_date': actif ? null : '2026-06-01',
      'exit_reason': actif ? null : 'Vente',
      'is_active': actif,
    };

    test('sujets remplacés, sortis compris, bloc absent sans effet', () async {
      final a = uuid('a');
      final b = uuid('b');

      await moteur(
        tirage([ligne(a, 'LAP-1'), ligne(b, 'LAP-2', actif: false)]),
      ).synchroniser();

      final lignes = await db.select(db.animals).get();
      expect(lignes, hasLength(2));
      expect(lignes.firstWhere((l) => l.id == b).status, 'vendu');
      expect(lignes.firstWhere((l) => l.id == b).isActive, isFalse);
      expect(lignes.firstWhere((l) => l.id == a).birthDate, isNotNull);

      // Serveur plus ancien (pas de bloc) : rien n'est effacé.
      await moteur(tirage(null)).synchroniser();
      expect(await db.select(db.animals).get(), hasLength(2));

      // Un sujet retiré côté serveur disparaît d'ici.
      await moteur(tirage([ligne(a, 'LAP-1')])).synchroniser();
      expect((await db.select(db.animals).get()).map((l) => l.id), [a]);
    });
  });

  group('écran', () {
    final livrees = <PdfRecu>[];
    final imprimees = <PdfRecu>[];

    setUp(() {
      livrees.clear();
      imprimees.clear();
    });

    Future<void> afficher(
      WidgetTester tester, {
      String? id,
      _ServeurFeint? serveur,
      VoidCallback? onRetour,
      VoidCallback? onReproduction,
      Size taille = const Size(1600, 2400),
    }) async {
      tester.view.physicalSize = taille;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: FicheSujetScreen(
            depot: depot(serveur ?? _ServeurFeint()),
            sujetId: id ?? sujetId,
            maintenant: maintenant,
            onRetour: onRetour,
            onOuvrirReproduction: onReproduction,
            enregistrer: (pdf) async {
              livrees.add(pdf);
              return r'C:\Documents\AgriERP\sujet.pdf';
            },
            imprimer: (pdf) async => imprimees.add(pdf),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> onglet(WidgetTester tester, String titre) async {
      await tester.tap(find.byKey(Key('onglet-sujet-$titre')));
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️ l\'en-tête : identifiant, statut, ligne descriptive', (
      tester,
    ) async {
      await sujet(lotId: lot);
      await afficher(tester);

      expect(find.text('Sujet #LAP-2026-0143'), findsOneWidget);
      expect(find.text('Actif — Reproducteur'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('sujet-ligne'))).data,
        'Lapins · Race Néo-Zélandais Blanc · Femelle · Lot LOT-CUNI-2026-011 · '
        'Cage C5',
      );
    });

    testWidgets('huit onglets, dans l\'ordre de la maquette', (tester) async {
      await sujet();
      await afficher(tester);

      final x = [
        for (final t in [
          'Général',
          'Historique',
          'Alimentation',
          'Vaccins',
          'Reproduction',
          'Production',
          'Mouvements',
          'Documents',
        ])
          tester.getTopLeft(find.byKey(Key('onglet-sujet-$t'))).dx,
      ];

      expect(x, orderedEquals([...x]..sort()));
      expect(x.toSet(), hasLength(8));
    });

    testWidgets('⚠️⚠️ Général : les dix champs d\'identification et l\'âge', (
      tester,
    ) async {
      await sujet(lotId: lot);
      await afficher(tester);

      String champ(String l) =>
          tester.widget<Text>(find.byKey(Key('sujet-champ-$l'))).data!;

      expect(champ('N° Identification'), 'LAP-2026-0143');
      expect(champ('Espèce'), 'Lapins');
      expect(champ('Catégorie'), 'Reproducteur');
      expect(champ('Race'), 'Néo-Zélandais Blanc');
      expect(champ('Sexe'), 'Femelle');
      expect(champ('Date de Naissance'), '12/02/2026 (5 mois)');
      expect(champ("Date d'Entrée"), '15/02/2026');
      expect(champ('Origine'), 'Naissance interne (Lot LOT-CUNI-2026-002)');
      expect(champ('Cage'), 'C5');
      expect(champ('Lot'), 'LOT-CUNI-2026-011');
    });

    testWidgets('un champ absent s\'écrit « — », jamais vide', (tester) async {
      await sujet(cage: null);
      await afficher(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('sujet-champ-Cage'))).data,
        '—',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('sujet-champ-Lot'))).data,
        '—',
      );
    });

    testWidgets('⚠️⚠️ le QR code ENCODE L\'IDENTIFIANT du sujet', (
      tester,
    ) async {
      await sujet();
      await afficher(tester);

      final lignes = await db.select(db.animals).get();
      expect(FicheSujetScreen.donneesQr(lignes.single), 'LAP-2026-0143');

      final qr = tester.widget<QrImageView>(
        find.byKey(const Key('sujet-qr-image')),
      );
      expect(qr.semanticsLabel, 'QR code du sujet LAP-2026-0143');
      expect(find.textContaining('Scan terrain'), findsOneWidget);
    });

    testWidgets('Historique : les lignes réelles, ou le message de Laravel', (
      tester,
    ) async {
      await sujet();
      await afficher(tester);
      await onglet(tester, 'Historique');

      expect(find.byKey(const Key('sujet-historique-ligne-0')), findsOneWidget);
      expect(
        find.textContaining('Entrée en élevage — Naissance interne'),
        findsOneWidget,
      );
    });

    testWidgets(
      '⚠️ Vaccins : le bandeau dit que ce sont les soins de la BANDE',
      (tester) async {
        await sujet(lotId: lot);
        await soin(
          '1',
          lot,
          DateTime(2026, 6, 1),
          'Vaccination',
          produit: 'Myxomatose',
          dose: '1 dose',
        );
        await afficher(tester);
        await onglet(tester, 'Vaccins');

        expect(find.byKey(const Key('sujet-soins-bande')), findsOneWidget);
        expect(find.textContaining('bande LOT-CUNI-2026-011'), findsOneWidget);
        expect(
          find.textContaining('ne sont pas des traitements individuels'),
          findsOneWidget,
        );
        expect(find.text('Myxomatose'), findsOneWidget);
        expect(find.text('01/06/2026'), findsOneWidget);
      },
    );

    testWidgets('Vaccins sans soin : le message de Laravel', (tester) async {
      await sujet(lotId: lot);
      await afficher(tester);
      await onglet(tester, 'Vaccins');

      expect(
        find.text('Aucun soin enregistré pour la bande de ce sujet.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Reproduction : rôle, mise bas, nés, statut, et lien vers le suivi',
      (tester) async {
        await sujet();
        await saillie(
          'a',
          mere: 'LAP-2026-0143',
          date: DateTime(2026, 5, 1),
          miseBas: DateTime(2026, 6, 1),
          vivants: 7,
          morts: 1,
          statut: 'termine',
        );
        var ouvert = 0;
        await afficher(tester, onReproduction: () => ouvert++);
        await onglet(tester, 'Reproduction');

        expect(find.text('Mère'), findsOneWidget);
        expect(find.text('01/05/2026'), findsOneWidget);
        expect(find.text('01/06/2026'), findsOneWidget);
        expect(find.text('Termine'), findsOneWidget);

        await tester.tap(find.byKey(const Key('sujet-lien-reproduction')));
        await tester.pumpAndSettle();
        expect(ouvert, 1);
      },
    );

    testWidgets('Reproduction vide : le message de Laravel', (tester) async {
      await sujet();
      await afficher(tester);
      await onglet(tester, 'Reproduction');

      expect(
        find.text('Aucun événement de reproduction pour ce sujet.'),
        findsOneWidget,
      );
    });

    testWidgets('⚠️ Mouvements : seuls les saisis, et la note le dit', (
      tester,
    ) async {
      await sujet();
      await afficher(tester);
      await onglet(tester, 'Mouvements');

      expect(find.byKey(const Key('sujet-mouvements-ligne-0')), findsOneWidget);
      expect(find.byKey(const Key('sujet-mouvements-ligne-1')), findsNothing);
      expect(
        find.textContaining("Aucun historique de déplacement entre cages"),
        findsOneWidget,
      );
    });

    for (final t in ['Alimentation', 'Production', 'Documents']) {
      testWidgets('⚠️⚠️ $t : aucun contenu plausible, le MOTIF à la place', (
        tester,
      ) async {
        await sujet();
        await afficher(tester);
        await onglet(tester, t);

        expect(
          find.byKey(Key('sujet-attente-${t.toLowerCase()}')),
          findsOneWidget,
        );
        expect(
          find.text('Aucune donnée réelle pour cet onglet'),
          findsOneWidget,
        );
        expect(find.textContaining('plus trompeur qu\'utile'), findsOneWidget);
        // Ni tableau ni chiffre : rien de fabriqué.
        expect(find.byType(Table), findsNothing);
      });
    }

    testWidgets('Alimentation dit que la ration se calcule PAR BANDE', (
      tester,
    ) async {
      await sujet();
      await afficher(tester);
      await onglet(tester, 'Alimentation');

      expect(find.textContaining('PAR BANDE'), findsOneWidget);
    });

    testWidgets('aucune carte d\'indicateur au niveau de la fiche', (
      tester,
    ) async {
      await sujet();
      await afficher(tester);

      // Les trois cartes de la maquette vivent dans l'onglet Alimentation, sans
      // source : elles ne sont donc pas rendues (voir l'exemption « Coût »).
      expect(cartesAttendues('animal-details.html'), 3);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets(
      '⚠️⚠️ l\'export écrit le PDF du serveur et propose l\'impression',
      (tester) async {
        await sujet();
        final s = _ServeurFeint();
        await afficher(tester, serveur: s);

        await tester.tap(find.byKey(const Key('sujet-exporter')));
        await tester.pumpAndSettle();

        expect(s.requetes, hasLength(1));
        expect(livrees.single.fichier, 'sujet-LAP-2026-0143.pdf');
        expect(find.byKey(const Key('sujet-reussi')), findsOneWidget);

        await tester.tap(find.byKey(const Key('sujet-imprimer')));
        await tester.pumpAndSettle();
        expect(imprimees, hasLength(1));
      },
    );

    testWidgets(
      '⚠️⚠️ hors ligne : échec visible, aucun fichier, aucun succès',
      (tester) async {
        await sujet();
        await afficher(tester, serveur: _ServeurFeint(horsLigne: true));

        await tester.tap(find.byKey(const Key('sujet-exporter')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('sujet-echec')), findsOneWidget);
        expect(find.byKey(const Key('sujet-reussi')), findsNothing);
        expect(find.textContaining('nécessite le réseau'), findsOneWidget);
        expect(livrees, isEmpty);
      },
    );

    testWidgets('un refus de rôle affiche la phrase du serveur', (
      tester,
    ) async {
      await sujet();
      await afficher(
        tester,
        serveur: _ServeurFeint(code: 403, corps: {'message': 'Pas pour vous.'}),
      );

      await tester.tap(find.byKey(const Key('sujet-exporter')));
      await tester.pumpAndSettle();

      expect(find.text('Pas pour vous.'), findsOneWidget);
    });

    testWidgets('un sujet introuvable le dit et laisse revenir', (
      tester,
    ) async {
      var retour = 0;
      await afficher(tester, id: uuid('inconnu'), onRetour: () => retour++);

      expect(find.byKey(const Key('sujet-introuvable')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sujet-retour')));
      await tester.pumpAndSettle();
      expect(retour, 1);
    });

    testWidgets('lg: deux colonnes 2/3 + 1/3 ; sous lg: elles s\'empilent', (
      tester,
    ) async {
      await sujet();

      await afficher(tester, taille: const Size(1600, 2400));
      final i = tester.getRect(find.byKey(const Key('sujet-identification')));
      final q = tester.getRect(find.byKey(const Key('sujet-qr')));
      expect(i.top, q.top);
      expect(i.width / q.width, closeTo(2, 0.05));

      await afficher(tester, taille: const Size(800, 3200));
      final i2 = tester.getRect(find.byKey(const Key('sujet-identification')));
      final q2 = tester.getRect(find.byKey(const Key('sujet-qr')));
      expect(q2.top, greaterThan(i2.bottom));
    });
  });

  group('lien depuis le Suivi Reproduction', () {
    Future<void> afficherSuivi(
      WidgetTester tester, {
      void Function(String)? onSujet,
    }) async {
      tester.view.physicalSize = const Size(1600, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await db
          .into(db.livestockLots)
          .insert(
            LivestockLotsCompanion.insert(
              id: lot,
              code: 'LOT-LAP-2026-06',
              speciesId: 'esp-cuniculture',
              speciesCode: const Value('cuniculture'),
              currentQuantity: const Value(50),
            ),
          );

      await tester.pumpWidget(
        MaterialApp(
          home: SuiviReproductionScreen(
            depot: SuiviReproductionRepository(database: db),
            onOuvrirSujet: onSujet,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      '⚠️ une référence qui nomme un sujet est un lien, une autre reste du texte',
      (tester) async {
        await sujet();
        await saillie(
          'a',
          mere: 'LAP-2026-0143',
          pere: 'MALE-INCONNU',
          date: DateTime.now().subtract(const Duration(days: 20)),
        );
        String? ouvert;
        await afficherSuivi(tester, onSujet: (id) => ouvert = id);

        expect(
          find.byKey(const Key('lien-sujet-LAP-2026-0143')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('lien-sujet-MALE-INCONNU')), findsNothing);
        expect(find.text('MALE-INCONNU'), findsOneWidget);

        await tester.tap(find.byKey(const Key('lien-sujet-LAP-2026-0143')));
        await tester.pumpAndSettle();
        expect(ouvert, sujetId);
      },
    );

    testWidgets('sans rappel, aucune référence n\'est cliquable', (
      tester,
    ) async {
      await sujet();
      await saillie(
        'a',
        mere: 'LAP-2026-0143',
        date: DateTime.now().subtract(const Duration(days: 20)),
      );
      await afficherSuivi(tester);

      expect(find.byKey(const Key('lien-sujet-LAP-2026-0143')), findsNothing);
    });
  });
}
