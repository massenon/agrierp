import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket CP-1 — LE PLAN COMPTABLE S'ÉCRIT AU POSTE (`Comptabilite\PlanComptable` : newAccount, saveAccount, archiveAccount).
///
/// Un compte créé, modifié ou archivé est `pending` jusqu'à l'acquittement ; le serveur (`PlanComptableService`) applique les
/// règles du web — numéro unique, classe 1 à 9, archivage refusé si une écriture cite le compte — et peut refuser avec son motif.
class _Serveur extends Interceptor {
  final List<Map<String, dynamic>> envois = [];
  final refus = <String, String>{};
  Map<String, dynamic> tirage = {'server_time': '2026-10-28T12:00:00Z'};

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
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
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
  late ComptabiliteRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 28, 14),
    );
    depot = ComptabiliteRepository(database: db, deviceId: 'poste-test');
    await db.into(db.chartOfAccounts).insert(ChartOfAccountsCompanion.insert(id: uuid('c411'), code: '411', label: 'Clients', accountClass: const Value(4)));
    await db.into(db.chartOfAccounts).insert(ChartOfAccountsCompanion.insert(id: uuid('c601'), code: '601', label: 'Achats', accountClass: const Value(6)));
  });
  tearDown(() async => db.close());

  Future<ChartOfAccount> compte(String id) => (db.select(db.chartOfAccounts)..where((c) => c.id.equals(id))).getSingle();

  group('dépôt', () {
    test('⚠️ un compte créé est pending, d\'origine ce poste, actif, et le plan du serveur reste synced', () async {
      final c = await depot.creerCompte(code: ' 6181 ', libelle: 'Frais de déplacement', classe: '6');

      expect(c.syncStatus, SyncStatus.pending);
      expect(c.deviceId, 'poste-test');
      expect(c.isActive, isTrue);
      expect((c.code, c.label, c.accountClass), ('6181', 'Frais de déplacement', 6));
      expect((await compte(uuid('c411'))).syncStatus, SyncStatus.synced);
    });

    test('⚠️⚠️ les refus du web sont reproduits AVANT d\'écrire : numéro unique, intitulé, classe 1 à 9', () async {
      Future<Map<String, String>> refus(Future<void> Function() geste) async {
        try {
          await geste();
        } on SaisieCompteRefusee catch (e) {
          return e.erreurs;
        }
        fail('accepté');
      }

      var e = await refus(() => depot.creerCompte(code: '411', libelle: 'Doublon', classe: '4'));
      expect(e['code'], 'La valeur du champ numéro de compte existe déjà.');
      e = await refus(() => depot.creerCompte(code: '', libelle: '', classe: ''));
      expect(e.keys, containsAll(['code', 'label', 'class']));
      expect(e['code'], 'Le champ numéro de compte est obligatoire.');
      e = await refus(() => depot.creerCompte(code: '9999', libelle: 'x', classe: '10'));
      expect(e['class'], 'Le champ classe doit être compris entre 1 et 9.');
      e = await refus(() => depot.creerCompte(code: 'A' * 21, libelle: 'x', classe: '4'));
      expect(e['code'], contains('20 caractères'));

      expect((await db.select(db.chartOfAccounts).get()).length, 2);
    });

    test('modifier garde le droit de conserver son propre numéro et repasse pending', () async {
      final c = await depot.modifierCompte(uuid('c411'), code: '411', libelle: 'Clients et comptes rattachés', classe: '4');

      expect(c.label, 'Clients et comptes rattachés');
      expect(c.syncStatus, SyncStatus.pending);
      await expectLater(depot.modifierCompte(uuid('c411'), code: '601', libelle: 'x', classe: '4'), throwsA(isA<SaisieCompteRefusee>()));
    });

    test('⚠️ archiver est refusé si une écriture cite le compte (motif du web), sinon inactif et pending', () async {
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(id: uuid('ex1'), year: 2026));
      await db.into(db.accountingEntries).insert(AccountingEntriesCompanion.insert(id: uuid('e1'), fiscalYearId: Value(uuid('ex1')), entryDate: DateTime(2026, 5, 1)));
      await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: uuid('l1'), entryId: uuid('e1'), accountId: uuid('c411'), debit: const Value(1000)));

      await expectLater(
        depot.archiverCompte(uuid('c411')),
        throwsA(isA<SaisieCompteRefusee>().having((e) => e.erreurs['formulaire'], 'motif', ComptabiliteRepository.motifCompteUtilise)),
      );
      expect((await compte(uuid('c411'))).isActive, isTrue);

      await depot.archiverCompte(uuid('c601'));
      final c = await compte(uuid('c601'));
      expect((c.isActive, c.syncStatus), (false, SyncStatus.pending));
      expect((await depot.charger()).comptes.map((x) => x.code), ['411'], reason: 'le plan ne montre plus le compte archivé');
    });
  });

  group('moteur', () {
    test('⚠️⚠️ l\'envoi porte numéro, intitulé, classe et is_active ; un compte archivé part is_active:false', () async {
      final c = await depot.creerCompte(code: '6181', libelle: 'Déplacements', classe: '6');
      await depot.archiverCompte(uuid('c601'));

      await moteur.synchroniser();

      final envoyes = <Object?, Map<dynamic, dynamic>>{for (final e in (serveur.envois.single['chart_of_accounts'] as List)) (e as Map)['id']: e};
      expect(envoyes[c.id], {'id': c.id, 'code': '6181', 'label': 'Déplacements', 'class': 6, 'is_active': true});
      expect(envoyes[uuid('c601')]!['is_active'], isFalse);
      expect((await db.select(db.chartOfAccounts).get()).every((x) => x.syncStatus == SyncStatus.synced), isTrue);
    });

    test('un refus du serveur devient conflict avec son motif et se relance', () async {
      final c = await depot.creerCompte(code: '6181', libelle: 'Déplacements', classe: '6');
      serveur.refus[c.id] = 'La valeur du champ numéro de compte existe déjà.';

      await moteur.synchroniser();

      expect((await compte(c.id)).syncStatus, SyncStatus.conflict);
      final conflit = (await db.select(db.syncConflicts).get()).firstWhere((x) => x.sourceTable == 'chart_of_accounts');
      expect(conflit.reason, contains('existe déjà'));
      await moteur.relancer(conflit);
      expect((await compte(c.id)).syncStatus, SyncStatus.pending);
    });

    test('⚠️ le tirage ne touche pas un compte local non acquitté, remplace les acquittés et retire ceux que le serveur ne sert plus', () async {
      final local = await depot.creerCompte(code: '6181', libelle: 'Déplacements', classe: '6');
      await (db.update(db.chartOfAccounts)..where((x) => x.id.equals(local.id))).write(const ChartOfAccountsCompanion(syncStatus: Value(SyncStatus.conflict)));
      serveur.tirage = {
        'server_time': '2026-10-28T13:00:00Z',
        'chart_of_accounts': [
          {'id': uuid('c411'), 'code': '411', 'label': 'Clients (serveur)', 'class': 4},
        ],
      };

      await moteur.synchroniser();

      final plan = {for (final x in await db.select(db.chartOfAccounts).get()) x.id: x};
      expect(plan[local.id]!.syncStatus, SyncStatus.conflict, reason: 'jamais retiré par le tirage');
      expect(plan[uuid('c411')]!.label, 'Clients (serveur)');
      expect(plan.containsKey(uuid('c601')), isFalse, reason: 'archivé ailleurs : le serveur ne le sert plus');
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      await tester.pumpWidget(MaterialApp(home: ComptabiliteScreen(depot: depot, maintenant: () => DateTime(2026, 10, 28, 10))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('carte-planComptable')));
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️⚠️ « Nouveau Compte » : refus sous les champs, puis le compte est écrit et affiché', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('plan-nouveau-compte')));
      await tester.pumpAndSettle();
      expect(find.text('Nouveau Compte'), findsWidgets);
      await tester.tap(find.byKey(const Key('compte-enregistrer')));
      await tester.pumpAndSettle();
      expect(find.text('Le champ numéro de compte est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ intitulé est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ classe est obligatoire.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('compte-code')), '6181');
      await tester.enterText(find.byKey(const Key('compte-libelle')), 'Frais de déplacement');
      await tester.tap(find.byKey(const Key('compte-classe')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6 - Charges').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('compte-enregistrer')));
      await tester.pumpAndSettle();

      final c = (await db.select(db.chartOfAccounts).get()).firstWhere((x) => x.code == '6181');
      expect((c.syncStatus, c.accountClass), (SyncStatus.pending, 6));
      expect(find.text('Frais de déplacement'), findsOneWidget);
      expect(find.text('6 - Charges'), findsWidgets, reason: 'la classe s\'affiche avec son libellé, comme au Blade');
    });

    testWidgets('« Archiver » : confirmation du Blade ; un compte utilisé affiche le motif et reste actif', (tester) async {
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(id: uuid('ex1'), year: 2026));
      await db.into(db.accountingEntries).insert(AccountingEntriesCompanion.insert(id: uuid('e1'), fiscalYearId: Value(uuid('ex1')), entryDate: DateTime(2026, 5, 1)));
      await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: uuid('l1'), entryId: uuid('e1'), accountId: uuid('c411'), debit: const Value(1000)));
      await afficher(tester);

      await tester.tap(find.byKey(const Key('plan-archiver-0')));
      await tester.pumpAndSettle();
      expect(find.text("Confirmer l'archivage"), findsOneWidget);
      await tester.tap(find.byKey(const Key('compte-archiver-confirmer')));
      await tester.pumpAndSettle();
      expect(find.textContaining('déjà utilisé dans au moins une écriture comptable'), findsOneWidget);
      expect((await compte(uuid('c411'))).isActive, isTrue);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan-archiver-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('compte-archiver-confirmer')));
      await tester.pumpAndSettle();
      expect((await compte(uuid('c601'))).isActive, isFalse);
    });
  });
}
