import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/clients/clients_creances_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serveur de synchronisation feint : sert, tirage après tirage, les blocs [tirages]
/// (le dernier se répète), répond [reponsePush] à l'envoi et note ce qui est envoyé.
class _ServeurSync extends Interceptor {
  _ServeurSync({this.reponsePush = const {}, this.tirages = const [{}]});

  final Map<String, dynamic> reponsePush;
  final List<Map<String, dynamic>> tirages;
  final List<Map<String, dynamic>> envois = [];
  var _tirage = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final push = options.path.contains('push');
    if (push) envois.add(Map<String, dynamic>.from(options.data as Map));

    Map<String, dynamic> corps;
    if (push) {
      corps = reponsePush;
    } else {
      final bloc =
          tirages[_tirage < tirages.length ? _tirage : tirages.length - 1];
      _tirage++;
      corps = {
        'server_time': '2026-10-08T12:0$_tirage:00.000Z',
        'product_categories': <dynamic>[],
        'products': <dynamic>[],
        'livestock_lots': <dynamic>[],
        ...bloc,
      };
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: corps,
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

/// Ticket F0.72 — FICHE CLIENT CRÉÉE, MODIFIÉE, ARCHIVÉE AU POSTE (`liste-clients.html`).
///
/// ⚠️⚠️ **LOCAL D'ABORD, SYNCHRONISÉ ENSUITE**, comme les produits et les fournisseurs :
/// la fiche est écrite `pending`, le serveur la valide à l'envoi. Un refus la passe en
/// `conflict`, jamais « envoyée » en silence.
///
/// ⚠️⚠️ **ET LE TIRAGE FUSIONNE** : l'ancien absorbeur effaçait toute la table avant de
/// réinsérer, alors que le serveur ne renvoie que les clients modifiés depuis `since` —
/// dès le deuxième tirage, le poste n'aurait plus gardé que le delta.
void main() {
  late AppDatabase db;
  late ClientsCreancesRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ClientsCreancesRepository(database: db, deviceId: 'poste-test');
  });

  tearDown(() async => db.close());

  SyncEngine moteur(_ServeurSync serveur) => SyncEngine(
    database: db,
    client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
      ..interceptors.add(serveur),
    deviceId: 'poste-test',
    connectivity: _ConnectiviteFeinte(),
  );

  Future<void> client(
    String cle,
    String nom, {
    String? ville,
    bool actif = true,
    SyncStatus statut = SyncStatus.synced,
  }) => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: uuid(cle),
          name: nom,
          city: Value(ville),
          isActive: Value(actif),
          syncStatus: Value(statut),
        ),
      );

  const fiche = FormulaireClient(
    nom: 'AMOUSSOU Régis',
    telephone: '+229 97 12 34 56',
    ville: 'Adja-Ouèrè',
    email: 'regis@ferme.bj',
  );

  group('règles et dépôt', () {
    test(
      'règles : seul le nom est obligatoire, e-mail et longueurs bornés',
      () {
        expect(ClientsCreancesRepository.validerFiche(fiche), isEmpty);
        expect(
          ClientsCreancesRepository.validerFiche(
            const FormulaireClient(nom: 'X'),
          ),
          isEmpty,
          reason: 'ni téléphone ni ville ni e-mail requis (règle du web)',
        );
        expect(
          ClientsCreancesRepository.validerFiche(
            FormulaireClient(
              nom: ' ',
              telephone: 'x' * 31,
              ville: 'v' * 101,
              email: 'pas-un-email',
            ),
          ).keys,
          containsAll(['nom', 'telephone', 'ville', 'email']),
        );
      },
    );

    test(
      '⚠️ créée en attente avec un UUID du poste, vides rangés en NULL',
      () async {
        final c = await depot.creerClient(
          const FormulaireClient(nom: '  Hôtel Plateau  '),
        );

        expect(c.id, hasLength(36));
        expect(c.name, 'Hôtel Plateau');
        expect(c.phone, isNull);
        expect(c.city, isNull);
        expect(c.email, isNull);
        expect(c.syncStatus, SyncStatus.pending);
        expect(c.isActive, isTrue);
        expect(c.creditLimit, 0);
      },
    );

    test(
      '⚠️ modifier repasse en attente et laisse le plafond de crédit',
      () async {
        await client('c1', 'Ancien nom');
        await (db.update(db.customers)..where((c) => c.id.equals(uuid('c1'))))
            .write(const CustomersCompanion(creditLimit: Value(50000)));

        final m = await depot.modifierClient(uuid('c1'), fiche);

        expect(m.name, 'AMOUSSOU Régis');
        expect(m.email, 'regis@ferme.bj');
        expect(m.creditLimit, 50000);
        expect(m.syncStatus, SyncStatus.pending);
      },
    );

    test(
      '⚠️ archiver ne supprime rien et compte seulement les actifs',
      () async {
        await client('c1', 'A');
        await client('c2', 'B');
        await client('c3', 'C', actif: false);

        final n = await depot.archiverClients([
          uuid('c1'),
          uuid('c2'),
          uuid('c3'),
        ]);

        expect(n, 2, reason: 'une fiche déjà archivée n’est pas comptée');
        final tous = await db.select(db.customers).get();
        expect(tous, hasLength(3));
        expect(tous.every((c) => !c.isActive), isTrue);
        expect(
          tous
              .where((c) => c.id != uuid('c3'))
              .every((c) => c.syncStatus == SyncStatus.pending),
          isTrue,
        );
      },
    );

    test(
      'la liste ne montre que les actifs ; les créances gardent le nom d’un archivé',
      () async {
        await client('c1', 'Actif');
        await client('c2', 'Archivé', actif: false);
        await db
            .into(db.receivables)
            .insert(
              ReceivablesCompanion.insert(
                id: uuid('r1'),
                customerId: uuid('c2'),
                amount: 5000,
              ),
            );

        final d = await depot.charger();

        expect(d.clients.map((l) => l.client.name), ['Actif']);
        expect(d.clientsActifs, 1);
        expect(d.creances.single.nomClient, 'Archivé');
      },
    );

    test(
      'statut dérivé comme le web : créance en retard dès qu’un solde reste dû',
      () async {
        await client('c1', 'Doit');
        await client('c2', 'À jour');
        await db
            .into(db.receivables)
            .insert(
              ReceivablesCompanion.insert(
                id: uuid('r1'),
                customerId: uuid('c1'),
                amount: 5000,
                amountPaid: const Value(1000),
              ),
            );

        final d = await depot.charger();
        final parNom = {for (final l in d.clients) l.client.name: l.statut};

        expect(parNom, {'Doit': 'Créance en retard', 'À jour': 'Actif'});
      },
    );
  });

  group('synchronisation', () {
    test('⚠️ envoyée sans plafond de crédit, acquittée sur réponse', () async {
      final c = await depot.creerClient(fiche);
      final serveur = _ServeurSync(
        reponsePush: {
          'customers': {
            'accepted': [c.id],
            'rejected': [],
          },
        },
      );

      await moteur(serveur).synchroniser();

      final envoye = (serveur.envois.single['customers'] as List).single as Map;
      expect(envoye, {
        'id': c.id,
        'name': 'AMOUSSOU Régis',
        'phone': '+229 97 12 34 56',
        'email': 'regis@ferme.bj',
        'city': 'Adja-Ouèrè',
        'is_active': true,
      });
      expect(
        (await db.select(db.customers).getSingle()).syncStatus,
        SyncStatus.synced,
      );
    });

    test(
      '⚠️ refusée par le serveur : conflit avec motif, jamais réputée envoyée',
      () async {
        final c = await depot.creerClient(fiche);
        final serveur = _ServeurSync(
          reponsePush: {
            'customers': {
              'accepted': [],
              'rejected': [
                {'id': c.id, 'reason': 'Votre rôle ne permet pas.'},
              ],
            },
          },
        );

        final sortie = await moteur(serveur).synchroniser();

        expect(
          (await db.select(db.customers).getSingle()).syncStatus,
          SyncStatus.conflict,
        );
        expect(sortie.rejete, 1);
        expect(sortie.motifs.join(' '), contains('Votre rôle ne permet pas.'));
      },
    );

    test('⚠️ un conflit se relance : la fiche repasse en attente', () async {
      final c = await depot.creerClient(fiche);
      final serveur = _ServeurSync(
        reponsePush: {
          'customers': {
            'accepted': [],
            'rejected': [
              {'id': c.id, 'reason': 'Refus.'},
            ],
          },
        },
      );
      final m = moteur(serveur);
      await m.synchroniser();

      final conflit = (await m.conflits()).single;
      await m.relancer(conflit);

      expect(
        (await db.select(db.customers).getSingle()).syncStatus,
        SyncStatus.pending,
      );
      expect(await m.conflits(), isEmpty);
    });

    test(
      '⚠️⚠️ le tirage INCRÉMENTAL fusionne : les clients non modifiés restent',
      () async {
        final serveur = _ServeurSync(
          tirages: [
            {
              'customers': [
                {'id': uuid('c1'), 'name': 'Premier', 'is_active': true},
                {'id': uuid('c2'), 'name': 'Second', 'is_active': true},
              ],
            },
            {
              // Le serveur ne renvoie que ce qui a changé depuis `since`.
              'customers': [
                {
                  'id': uuid('c2'),
                  'name': 'Second',
                  'email': 'second@ferme.bj',
                  'is_active': false,
                },
              ],
            },
          ],
        );
        final m = moteur(serveur);

        await m.synchroniser();
        await m.synchroniser();

        final tous = {
          for (final c in await db.select(db.customers).get()) c.name: c,
        };
        expect(tous.keys, containsAll(['Premier', 'Second']));
        expect(tous['Premier']!.isActive, isTrue);
        expect(
          tous['Second']!.isActive,
          isFalse,
          reason: 'archivé sur le serveur',
        );
        expect(tous['Second']!.email, 'second@ferme.bj');
      },
    );

    test('⚠️ le tirage n’efface NI n’écrase une fiche en attente', () async {
      await client('c9', 'Saisie au poste', statut: SyncStatus.pending);
      final serveur = _ServeurSync(
        tirages: [
          {
            'customers': [
              {
                'id': uuid('c9'),
                'name': 'Version du serveur',
                'is_active': true,
              },
              {'id': uuid('c8'), 'name': 'Autre', 'is_active': true},
            ],
          },
        ],
      );

      await moteur(serveur).synchroniser();

      final noms = (await db.select(db.customers).get()).map((c) => c.name);
      expect(noms, containsAll(['Saisie au poste', 'Autre']));
      expect(noms, isNot(contains('Version du serveur')));
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(home: ClientsCreancesScreen(depot: depot)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      '⚠️ « Nouveau Client » écrit une fiche en attente, nom seul exigé',
      (tester) async {
        await afficher(tester);

        await tester.tap(find.byKey(const Key('nouveau-client')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('client-enregistrer')));
        await tester.pumpAndSettle();
        expect(await db.select(db.customers).get(), isEmpty);
        expect(find.text('Ce champ est obligatoire.'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('client-nom')),
          'GBAGUIDI Solange',
        );
        await tester.enterText(find.byKey(const Key('client-ville')), 'Pobè');
        await tester.tap(find.byKey(const Key('client-enregistrer')));
        await tester.pumpAndSettle();

        final c = await db.select(db.customers).getSingle();
        expect(c.name, 'GBAGUIDI Solange');
        expect(c.city, 'Pobè');
        expect(c.phone, isNull);
        expect(c.syncStatus, SyncStatus.pending);
        expect(find.byKey(Key('client-en-attente-${c.id}')), findsOneWidget);
        expect(find.text('GBAGUIDI Solange'), findsOneWidget);
      },
    );

    testWidgets('modifier une fiche la réécrit et la repasse en attente', (
      tester,
    ) async {
      await client('c1', 'TOSSOU Marcel', ville: 'Kétou');
      await afficher(tester);

      await tester.tap(find.byKey(Key('modifier-client-${uuid('c1')}')));
      await tester.pumpAndSettle();
      expect(find.text('Modifier le Client'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('client-ville')), 'Sakété');
      await tester.tap(find.byKey(const Key('client-enregistrer')));
      await tester.pumpAndSettle();

      final c = await db.select(db.customers).getSingle();
      expect(c.city, 'Sakété');
      expect(c.syncStatus, SyncStatus.pending);
    });

    testWidgets(
      '⚠️ archiver nomme la fiche, ne supprime rien et la retire de la liste',
      (tester) async {
        await client('c1', 'TOSSOU Marcel');
        await client('c2', 'Hôtel Plateau');
        await afficher(tester);

        await tester.tap(find.byKey(Key('archiver-client-${uuid('c1')}')));
        await tester.pumpAndSettle();
        expect(find.text("Confirmer l'archivage"), findsOneWidget);
        expect(
          find.textContaining('TOSSOU Marcel sera marqué(e)'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('archivage-clients-confirmer')));
        await tester.pumpAndSettle();

        expect(await db.select(db.customers).get(), hasLength(2));
        expect(
          (await (db.select(
            db.customers,
          )..where((c) => c.id.equals(uuid('c1')))).getSingle()).isActive,
          isFalse,
        );
        expect(find.text('TOSSOU Marcel'), findsNothing);
        expect(find.text('Hôtel Plateau'), findsOneWidget);
      },
    );

    testWidgets(
      '⚠️ la sélection compte, « Supprimer la sélection » archive en masse',
      (tester) async {
        await client('c1', 'A');
        await client('c2', 'B');
        await client('c3', 'C');
        await afficher(tester);

        expect(find.byKey(const Key('barre-selection-clients')), findsNothing);

        await tester.tap(find.byKey(Key('client-case-${uuid('c1')}')));
        await tester.tap(find.byKey(Key('client-case-${uuid('c2')}')));
        await tester.pumpAndSettle();
        expect(find.text('2 client(s) sélectionné(s)'), findsOneWidget);

        await tester.tap(find.byKey(const Key('supprimer-selection-clients')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('2 client(s) sélectionné(s) sera marqué(e)'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('archivage-clients-confirmer')));
        await tester.pumpAndSettle();

        final actifs = await (db.select(
          db.customers,
        )..where((c) => c.isActive.equals(true))).get();
        expect(actifs.map((c) => c.name), ['C']);
        expect(find.byKey(const Key('barre-selection-clients')), findsNothing);
      },
    );

    testWidgets('« tout sélectionner » ne prend que les lignes filtrées', (
      tester,
    ) async {
      await client('c1', 'A', ville: 'Pobè');
      await client('c2', 'B', ville: 'Kétou');
      await afficher(tester);

      await tester.tap(find.byKey(const Key('filtre-ville-client')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pobè').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clients-tout-selectionner')));
      await tester.pumpAndSettle();

      expect(find.text('1 client(s) sélectionné(s)'), findsOneWidget);
    });

    testWidgets('le filtre de statut isole les clients en retard', (
      tester,
    ) async {
      await client('c1', 'Doit');
      await client('c2', 'À jour');
      await db
          .into(db.receivables)
          .insert(
            ReceivablesCompanion.insert(
              id: uuid('r1'),
              customerId: uuid('c1'),
              amount: 5000,
            ),
          );
      await afficher(tester);

      await tester.tap(find.byKey(const Key('filtre-statut-client')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créance en retard').last);
      await tester.pumpAndSettle();

      expect(find.text('Doit'), findsOneWidget);
      expect(find.text('À jour'), findsNothing);
    });
  });
}
