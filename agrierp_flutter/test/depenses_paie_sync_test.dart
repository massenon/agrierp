import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket U13 — `expenses` ET `payslips` DESCENDENT AU POSTE.
///
/// Verrouillé ici : l'absorbeur STRICT des dépenses (tout ou rien, curseur immobile sur refus), qui n'écrase JAMAIS une
/// dépense locale `pending` ou `conflict`, applique l'archivage du web et garde l'origine (`device_id`) d'une dépense
/// acquittée ; l'absorbeur STRICT de la paie (lecture seule, jamais envoyée) ; la clé absente (serveur antérieur, table
/// non servie au compte) ; la resynchronisation unique `depenses_resync_u13` ; la réinitialisation (15.50) qui purge
/// les deux tables ; le Tableau de bord qui ne liste plus une dépense archivée au web.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Serveur feint : sert [tirage], acquitte tout envoi et garde chaque corps.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-19T12:00:00Z'};

  final List<Object?> demandes = [];
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
                  'accepted': [
                    for (final e in value)
                      if (e is Map && e['id'] is String) e['id'],
                  ],
                  'rejected': [],
                },
          },
        ),
      );
      return;
    }
    demandes.add(options.queryParameters['since']);
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;

  const caisse = 'cccccccc-0000-4000-8000-000000000531';
  String uuid(String graine) => graine.padRight(36, '0');

  Map<String, dynamic> depenseJson(
    String id, {
    Object? date = '2026-10-12',
    Object? libelle = 'Électricité SBEE',
    Object? categorie = '605 - Énergie',
    Object? montant = 42000,
    Object? compte = caisse,
    Object? actif = true,
  }) => {
    'id': id,
    'expense_date': date,
    'label': libelle,
    'category': categorie,
    'amount': montant,
    'treasury_account_id': compte,
    'is_active': actif,
    'updated_at': '2026-10-12T10:00:00+01:00',
  };

  Map<String, dynamic> bulletinJson(
    String id, {
    Object? nom = 'HOUNKPÈ Codjo',
    Object? net = 138650.5,
    Object? quand = '2026-10-18 23:30:00',
  }) => {'id': id, 'employee_name': nom, 'net_salary': net, 'created_at': quand};

  Future<void> depenseLocale(String id, SyncStatus statut, {double montant = 9000, String poste = 'poste-test'}) => db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          id: id,
          deviceId: poste,
          syncStatus: Value(statut),
          updatedAt: DateTime(2026, 10, 12),
          expenseDate: DateTime(2026, 10, 12),
          label: 'Saisie locale',
          category: '601 - Aliments',
          amount: montant,
          treasuryAccountId: caisse,
        ),
      );

  Future<Expense?> depense(String id) => (db.select(db.expenses)..where((t) => t.id.equals(id))).getSingleOrNull();

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 19, 14),
    );
  });

  tearDown(() async => db.close());

  group('dépenses (table mixte)', () {
    test('une dépense du web descend, jour métier tel quel, acquittée', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'expenses': [depenseJson(uuid('w1'))],
      };

      await moteur.synchroniser();

      final d = (await depense(uuid('w1')))!;
      expect(d.expenseDate, DateTime(2026, 10, 12));
      expect(d.label, 'Électricité SBEE');
      expect(d.category, '605 - Énergie');
      expect(d.amount, 42000);
      expect(d.treasuryAccountId, caisse);
      expect(d.isActive, isTrue);
      expect(d.syncStatus, SyncStatus.synced);
      expect(d.deviceId, 'serveur');
      expect(serveur.envois.where((e) => e.containsKey('expenses')), isEmpty, reason: 'jamais renvoyée');
    });

    test('⚠️ une dépense de CE poste archivée au web devient inactive ici, et garde son origine', () async {
      await depenseLocale(uuid('p1'), SyncStatus.synced);
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'expenses': [depenseJson(uuid('p1'), montant: 9000, actif: false)],
      };

      await moteur.synchroniser();

      final d = (await depense(uuid('p1')))!;
      expect(d.isActive, isFalse);
      expect(d.deviceId, 'poste-test', reason: 'l origine de la saisie ne change pas');
      expect(d.label, 'Électricité SBEE', reason: 'la dernière version du serveur (modifiée au web)');
    });

    for (final statut in [SyncStatus.pending, SyncStatus.conflict]) {
      test('⚠️⚠️ une dépense locale ${statut.name} n est JAMAIS écrasée par le tirage', () async {
        await depenseLocale(uuid('l1'), statut, montant: 9000);
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'expenses': [depenseJson(uuid('l1'), montant: 1, actif: false)],
        };

        await moteur.synchroniser();

        final d = (await depense(uuid('l1')))!;
        expect(d.amount, 9000);
        expect(d.isActive, isTrue);
        expect(d.label, 'Saisie locale');
        if (statut == SyncStatus.pending) {
          // Partie à l'envoi (après le tirage), acquittée : elle devient `synced`.
          expect(serveur.envois.single['expenses'], hasLength(1));
        } else {
          expect(d.syncStatus, SyncStatus.conflict);
        }
      });
    }

    test('clé absente (serveur antérieur, ou table non servie) : rien n est touché', () async {
      await depenseLocale(uuid('p1'), SyncStatus.synced);

      await moteur.synchroniser();

      expect((await depense(uuid('p1')))!.isActive, isTrue);
      expect(await db.select(db.expenses).get(), hasLength(1));
    });

    for (final (cas, fautif) in <(String, Map<String, dynamic>)>[
      ('identifiant invalide', depenseJson('court')),
      ('servie deux fois', depenseJson(uuid('w1'))),
      ('date illisible', depenseJson(uuid('w2'), date: 'hier')),
      ('date absente', depenseJson(uuid('w2'), date: null)),
      ('libellé absent', depenseJson(uuid('w2'), libelle: null)),
      ('compte de charge qui n est pas un texte', depenseJson(uuid('w2'), categorie: 605)),
      ('montant absent', depenseJson(uuid('w2'), montant: null)),
      ('montant illisible', depenseJson(uuid('w2'), montant: 'cent')),
      ('montant négatif', depenseJson(uuid('w2'), montant: -5)),
      ('compte de trésorerie absent', depenseJson(uuid('w2'), compte: null)),
      ('compte de trésorerie vide', depenseJson(uuid('w2'), compte: '')),
      ('archivage illisible', depenseJson(uuid('w2'), actif: 'peut-être')),
    ]) {
      test('⚠️⚠️ STRICT — $cas : toute la page est refusée, rien n est écrit, le curseur ne bouge pas', () async {
        await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
        final curseur = (await db.etatDeSynchronisation())?.lastPulledAt;
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'expenses': [depenseJson(uuid('w1')), fautif],
        };

        await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));

        expect(await db.select(db.expenses).get(), isEmpty);
        expect((await db.etatDeSynchronisation())?.lastPulledAt, curseur);
      });
    }
  });

  group('paie (lecture seule)', () {
    test('un bulletin descend : nom, net, instant en heure MURALE du serveur ; jamais envoyé', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'payslips': [bulletinJson(uuid('b1')), bulletinJson(uuid('b2'), nom: null)],
      };
      await depenseLocale(uuid('l1'), SyncStatus.pending);

      await moteur.synchroniser();
      await moteur.synchroniser();

      final b = await (db.select(db.payslips)..orderBy([(t) => OrderingTerm(expression: t.id)])).get();
      expect(b, hasLength(2), reason: 'resservi, remplacé par identifiant');
      expect(b[0].employeeName, 'HOUNKPÈ Codjo');
      expect(b[0].netSalary, 138650.5);
      // 23 h 30 le 18 reste le 18 : jamais converti d'un fuseau à l'autre.
      expect(b[0].createdAt, DateTime(2026, 10, 18, 23, 30));
      expect(b[1].employeeName, isNull);
      for (final corps in serveur.envois) {
        expect(corps.containsKey('payslips'), isFalse);
      }
      expect(AppDatabase.tablesEnvoyees, isNot(contains('payslips')));
    });

    for (final (cas, fautif) in <(String, Map<String, dynamic>)>[
      ('identifiant invalide', bulletinJson('court')),
      ('servi deux fois', bulletinJson(uuid('b1'))),
      ('net absent', bulletinJson(uuid('b2'), net: null)),
      ('net négatif', bulletinJson(uuid('b2'), net: -1)),
      ('net illisible', bulletinJson(uuid('b2'), net: 'beaucoup')),
      ('instant illisible', bulletinJson(uuid('b2'), quand: 'hier soir')),
      ('nom qui n est pas un texte', bulletinJson(uuid('b2'), nom: 12)),
    ]) {
      test('⚠️⚠️ STRICT — $cas : rien n est écrit', () async {
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'payslips': [bulletinJson(uuid('b1')), fautif],
        };

        await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));

        expect(await db.select(db.payslips).get(), isEmpty);
      });
    }
  });

  group('réinitialisation, resynchronisation, écrans', () {
    test('la réinitialisation du serveur (15.50) purge dépenses et paie : tables d activité', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'expenses': [depenseJson(uuid('w1'))],
        'payslips': [bulletinJson(uuid('b1'))],
      };
      await moteur.synchroniser();

      await db.purgerDonneesDActivite();

      expect(await db.select(db.expenses).get(), isEmpty);
      expect(await db.select(db.payslips).get(), isEmpty);
      expect(AppDatabase.tablesDActivite, containsAll(['expenses', 'payslips']));
    });

    Future<void> posteEnService() async {
      await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
      for (final cle in [
        SyncEngine.cleJournalResync,
        SyncEngine.cleJournalResyncCreation,
        SyncEngine.cleFichesResync,
        SyncEngine.cleFichesResyncCategories,
        SyncEngine.cleFichesResyncU10,
        SyncEngine.cleLignesResync,
        SyncEngine.cleRetoursResync,
        SyncEngine.cleMouvementsResync,
      ]) {
        await db.into(db.appSettings).insert(AppSettingsCompanion.insert(key: cle, value: '1'));
      }
    }

    test(
      '⚠️⚠️ un poste déjà en service redemande TOUT une fois (dépenses et paie antérieures à son curseur), puis l incrémental',
      () async {
        await posteEnService();
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'products': [],
          'expenses': [depenseJson(uuid('w1'))],
        };

        await moteur.synchroniser();
        await moteur.synchroniser();

        expect(serveur.demandes.first, isNull, reason: 'sans since, une fois');
        expect(serveur.demandes.last, isNotNull, reason: 'puis incrémental');
      },
    );

    test('⚠️ serveur antérieur à U13 (produits servis sans les dépenses) : la resynchronisation N EST PAS marquée faite', () async {
      await posteEnService();
      serveur.tirage = {'server_time': '2026-10-19T12:00:00Z', 'products': []};

      await moteur.synchroniser();
      await moteur.synchroniser();

      expect(serveur.demandes, [null, null]);
    });

    test('Tableau de bord : une dépense archivée au web n est plus listée (`where(is_active, true)`)', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'expenses': [
          depenseJson(uuid('w1'), libelle: 'Active'),
          depenseJson(uuid('w2'), libelle: 'Archivée', actif: false, date: '2026-10-15'),
        ],
      };
      await moteur.synchroniser();

      final d = await TableauDeBordRepository(database: db, horloge: () => DateTime(2026, 10, 19, 14)).charger();

      expect([for (final l in d.depensesRecentes) l.libelle], ['Active']);
      expect(await DepensesRepository(database: db, deviceId: 'poste-test').mesDepenses(), hasLength(1));
    });
  });
}
