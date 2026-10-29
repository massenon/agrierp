import 'dart:convert';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/comptabilite/cloture_exercice_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket CP-4 — LA CLÔTURE D'EXERCICE SE DEMANDE AU POSTE (décision du client : « oui, le poste doit le faire »).
///
/// Le poste n'écrit QUE la DEMANDE (`fiscal_closure_requests`) ; le serveur la rejoue par `ClotureExerciceService` (le point de
/// passage du web). Il refuse avant d'écrire, avec les messages du web, ce qu'il sait juger : étapes, soldes, échéance, balance.
class _Serveur extends Interceptor {
  final List<Map<String, dynamic>> envois = [];
  final refus = <String, String>{};
  int tirages = 0;
  Map<String, dynamic> tirage = {'server_time': '2027-02-15T12:00:00Z'};

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
    tirages++;
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
  late ClotureExerciceRepository depot;
  var maintenant = DateTime(2027, 2, 15, 10);

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  Future<void> plan(String code, String libelle, int classe) => db.into(db.chartOfAccounts).insert(
    ChartOfAccountsCompanion.insert(id: uuid('c$code'), code: code, label: libelle, accountClass: Value(classe)),
  );

  Future<void> ecriture(String id, DateTime jour, String debit, String credit, double montant, {String exercice = 'ex26'}) async {
    await db.into(db.accountingEntries).insert(AccountingEntriesCompanion.insert(id: uuid(id), fiscalYearId: Value(uuid(exercice)), entryDate: jour));
    await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: uuid('${id}d'), entryId: uuid(id), accountId: uuid('c$debit'), debit: Value(montant)));
    await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: uuid('${id}c'), entryId: uuid(id), accountId: uuid('c$credit'), credit: Value(montant)));
  }

  Future<List<FiscalClosureRequest>> demandes() => (db.select(db.fiscalClosureRequests)..orderBy([(d) => OrderingTerm.asc(d.updatedAt)])).get();

  Future<String> refus(Future<void> Function() geste) async {
    try {
      await geste();
    } on RefusCloture catch (e) {
      return e.motif;
    }
    fail('le geste aurait dû être refusé');
  }

  setUp(() async {
    maintenant = DateTime(2027, 2, 15, 10);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2027, 2, 15, 14),
    );
    var tic = 0;
    depot = ClotureExerciceRepository(database: db, deviceId: 'poste-test', horloge: () => maintenant);
    // Les instants d'écriture doivent se distinguer pour l'ordre d'envoi.
    tic++;
    await db.into(db.fiscalYears).insert(
      FiscalYearsCompanion.insert(id: uuid('ex26'), year: 2026, startDate: Value(DateTime(2026, 1, 1)), endDate: Value(DateTime(2026, 12, 31)), status: const Value('ouvert')),
    );
    await plan('101', 'Capital', 1);
    await plan('131', 'Résultat - Bénéfice', 1);
    await plan('139', 'Résultat - Perte', 1);
    await plan('531', 'Caisse', 5);
    await plan('701', 'Ventes de marchandises', 7);
    await plan('601', 'Achats', 6);
    await ecriture('e1', DateTime(2026, 3, 1), '531', '101', 1000000);
    await ecriture('e2', DateTime(2026, 6, 10), '531', '701', 300000);
    expect(tic, 1);
  });
  tearDown(() async => db.close());

  group('dépôt', () {
    test('⚠️⚠️ la clôture se refuse dans l\'ordre du web : étape 1, puis étape 2, puis elle est admise — et seules des DEMANDES sont écrites', () async {
      expect(await refus(() => depot.cloturerExercice(2026)), contains('Étape 1 non confirmée'));

      await depot.confirmerEtape1(2026);
      expect(await refus(() => depot.cloturerExercice(2026)), contains('Étape 2 non faite : 1 compte(s) de charges ou de produits de 2026 restent à solder.'));

      await depot.solderComptesGestion(2026);
      await depot.cloturerExercice(2026);

      final d = await demandes();
      expect([for (final x in d) x.kind], ['confirmer_etape1', 'solder_comptes_gestion', 'cloturer_exercice']);
      expect(d.every((x) => x.syncStatus == SyncStatus.pending), isTrue);
      expect(jsonDecode(d.last.payload), {'year': 2026});
      final exercice = (await db.select(db.fiscalYears).get()).single;
      expect((exercice.status, exercice.step1ConfirmedAt), ('ouvert', null), reason: 'le poste n\'écrit JAMAIS fiscal_years');
    });

    test('une demande identique déjà en attente n\'est pas doublée ; une clôture demandée grise la suivante', () async {
      await depot.confirmerEtape1(2026);
      expect(await refus(() => depot.confirmerEtape1(2026)), contains('déjà en attente'));
      await depot.solderComptesGestion(2026);
      await depot.cloturerExercice(2026);
      expect(await refus(() => depot.cloturerExercice(2026)), contains('est déjà en attente d\'envoi'));
      expect((await demandes()).length, 3);
    });

    test('avant l\'échéance du 31/12 : refusé avec le motif du web', () async {
      maintenant = DateTime(2026, 11, 15, 10);
      await depot.confirmerEtape1(2026);
      expect(await refus(() => depot.cloturerExercice(2026)), "L'exercice 2026 ne peut être clôturé qu'après son échéance du 31/12/2026, à partir du 01/01/2027.");
    });

    test('un exercice précédent encore ouvert, un exercice clos ou inconnu : refusés', () async {
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(id: uuid('ex27'), year: 2027, startDate: Value(DateTime(2027, 1, 1)), endDate: Value(DateTime(2027, 12, 31)), status: const Value('ouvert')));
      maintenant = DateTime(2028, 2, 1);
      expect(await refus(() => depot.cloturerExercice(2027)), "L'exercice 2026 est encore ouvert : clôturez-le avant l'exercice 2027.");
      expect(await refus(() => depot.cloturerExercice(2019)), 'Cet exercice ne peut pas être clôturé (déjà clos ou introuvable).');
      expect(await refus(() => depot.rouvrirExercice(2026)), "L'exercice 2026 n'est pas clôturé.");
    });

    test('un à-nouveau déséquilibré est refusé avec les montants (compte de classe 8)', () async {
      await plan('811', 'Cessions', 8);
      await ecriture('e3', DateTime(2026, 4, 1), '811', '101', 50000);
      await depot.confirmerEtape1(2026);
      await depot.solderComptesGestion(2026);
      // L'étape 2 est demandée : l'à-nouveau n'est pas jugé ici (le solde n'est pas encore au journal) ; le serveur jugera.
      await depot.cloturerExercice(2026);
      expect((await demandes()).length, 3);
    });

    test('« solder » : rien à solder et plan sans 131/139 sont refusés avec le motif du web', () async {
      await db.delete(db.accountingEntryLines).go();
      expect(await refus(() => depot.solderComptesGestion(2026)), 'Aucun compte de charges/produits à solder pour cet exercice.');
    });

    test('clôture de mois : lisibilité, déjà clôturé, balance équilibrée, doublon', () async {
      expect(await refus(() => depot.cloturerPeriode('mars')), contains('illisible'));
      await depot.cloturerPeriode('2026-03');
      expect(await refus(() => depot.cloturerPeriode('2026-03')), contains('déjà en attente'));

      await db.into(db.periodicClosures).insert(PeriodicClosuresCompanion.insert(id: uuid('p1'), period: '2026-04', closedAt: Value(DateTime(2026, 5, 1))));
      expect(await refus(() => depot.cloturerPeriode('2026-04')), 'Ce mois est déjà clôturé.');

      // Une écriture déséquilibrée = tirage INCOMPLET : le poste ne bloque pas sur un journal qu'il sait partiel, le serveur juge.
      await (db.delete(db.fiscalClosureRequests)).go();
      await (db.update(db.accountingEntryLines)..where((l) => l.id.equals(uuid('e1d')))).write(const AccountingEntryLinesCompanion(debit: Value(1000500)));
      await depot.cloturerPeriode('2026-03');
      expect((await demandes()).single.kind, 'cloturer_periode');
    });

    test('déclôture : seul un mois clôturé non encore rouvert, une fois', () async {
      expect(await refus(() => depot.decloturerPeriode(uuid('inconnu'))), "Ce mois n'est pas clôturé.");
      await db.into(db.periodicClosures).insert(PeriodicClosuresCompanion.insert(id: uuid('p1'), period: '2026-04', closedAt: Value(DateTime(2026, 5, 1))));
      await depot.decloturerPeriode(uuid('p1'));
      expect(await refus(() => depot.decloturerPeriode(uuid('p1'))), contains('déjà en attente'));
      expect(jsonDecode((await demandes()).single.payload), {'closure_id': uuid('p1'), 'period': '2026-04'});
    });

    test('réouverture : refusée si N+1 est clos ; admise sinon', () async {
      await (db.update(db.fiscalYears)).write(FiscalYearsCompanion(status: const Value('cloture'), closedAt: Value(DateTime(2027, 2, 1))));
      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(id: uuid('ex27'), year: 2027, status: const Value('cloture')));
      expect(await refus(() => depot.rouvrirExercice(2026)), "L'exercice 2027 est clôturé : rouvrez-le d'abord, son report à nouveau dépend de 2026.");
      await (db.update(db.fiscalYears)..where((e) => e.year.equals(2027))).write(const FiscalYearsCompanion(status: Value('ouvert')));
      await depot.rouvrirExercice(2026);
      expect((await demandes()).single.kind, 'rouvrir_exercice');
    });

    test('ouverture de N+1 : pas avant le 1er décembre, jamais deux fois ; premier exercice : l\'année en cours', () async {
      maintenant = DateTime(2026, 11, 20);
      expect(await refus(() => depot.ouvrirExerciceSuivant(2027)), "L'exercice 2027 ne peut s'ouvrir qu'à partir du 01/12/2026.");
      maintenant = DateTime(2026, 12, 3);
      await depot.ouvrirExerciceSuivant(2027);
      expect(await refus(() => depot.ouvrirExerciceSuivant(2027)), contains('déjà en attente'));
      expect(await refus(() => depot.ouvrirExerciceSuivant(2026)), "L'exercice 2026 existe déjà.");
      expect(await refus(() => depot.ouvrirExerciceSuivant(2029)), "L'exercice 2029 ne peut s'ouvrir qu'à la suite de l'exercice 2028, qui n'existe pas.");
    });

    test('abandonner une demande refusée la retire avec son conflit', () async {
      await depot.confirmerEtape1(2026);
      final id = (await demandes()).single.id;
      await db.into(db.syncConflicts).insert(SyncConflictsCompanion.insert(id: 'fiscal_closure_requests:$id', sourceTable: 'fiscal_closure_requests', recordId: id, reason: 'x', detectedAt: DateTime(2027)));
      await depot.abandonner(id);
      expect(await demandes(), isEmpty);
      expect(await db.select(db.syncConflicts).get(), isEmpty);
    });
  });

  group('moteur', () {
    test('⚠️⚠️ l\'envoi porte {id, kind, payload} dans l\'ordre demandé ; acquitté, un tirage de confirmation suit', () async {
      await depot.confirmerEtape1(2026);
      await depot.cloturerPeriode('2026-03');

      serveur.tirage = {
        'server_time': '2027-02-15T12:00:00Z',
        'fiscal_years': [
          {'id': uuid('ex26'), 'year': 2026, 'start_date': '2026-01-01', 'end_date': '2026-12-31', 'status': 'ouvert', 'step1_confirmed_at': '2027-02-15 11:00:00', 'closed_at': null},
        ],
        'periodic_closures': [
          {'id': uuid('p1'), 'period': '2026-03', 'closed_at': '2027-02-15 11:00:05', 'reopened_at': null},
        ],
      };
      await moteur.synchroniser();

      final envoi = serveur.envois.single['fiscal_closure_requests'] as List;
      final d = await demandes();
      expect(envoi, [
        {'id': d[0].id, 'kind': 'confirmer_etape1', 'payload': {'year': 2026}},
        {'id': d[1].id, 'kind': 'cloturer_periode', 'payload': {'period': '2026-03'}},
      ]);
      expect(d.every((x) => x.syncStatus == SyncStatus.synced), isTrue);
      expect(serveur.tirages, greaterThanOrEqualTo(2), reason: 'une demande acquittée déclenche le tirage de confirmation');

      final exercice = (await db.select(db.fiscalYears).get()).single;
      expect(exercice.step1ConfirmedAt, DateTime(2027, 2, 15, 11));
      final mois = (await db.select(db.periodicClosures).get()).single;
      expect((mois.period, mois.closedAt, mois.reopenedAt), ('2026-03', DateTime(2027, 2, 15, 11, 0, 5), null));
    });

    test('un refus devient conflict avec son motif, visible à l\'écran de la demande, et se relance', () async {
      await depot.cloturerPeriode('2026-03');
      final id = (await demandes()).single.id;
      serveur.refus[id] = 'Balance déséquilibrée (écart de 12 FCFA) — corrigez l\'écart avant de clôturer ce mois.';

      await moteur.synchroniser();

      expect((await demandes()).single.syncStatus, SyncStatus.conflict);
      final liste = (await depot.charger()).demandes.single;
      expect(liste.refusee, isTrue);
      expect(liste.motifRefus, contains('écart de 12 FCFA'));

      serveur.refus.clear();
      final conflit = (await db.select(db.syncConflicts).get()).firstWhere((x) => x.sourceTable == 'fiscal_closure_requests');
      await moteur.relancer(conflit);
      await moteur.synchroniser();
      expect((await demandes()).single.syncStatus, SyncStatus.synced);
    });

    test('rien en attente : aucune clé fiscal_closure_requests n\'est envoyée', () async {
      await moteur.synchroniser();
      expect(serveur.envois, isEmpty);
    });
  });

  group('écran', () {
    // Le toast arme un minuteur de 3,5 s : retiré avant la fin du test (sinon « Timer still pending »).
    void ecranTest(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (tester) async {
      await corps(tester);
      ToastAgri.toutRetirer();
    });

    Future<void> afficher(WidgetTester tester, {bool admin = true, bool cloturer = true}) async {
      tester.view.physicalSize = const Size(1800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      await tester.pumpWidget(
        MaterialApp(
          home: ComptabiliteScreen(
            depot: ComptabiliteRepository(database: db, deviceId: 'poste-test'),
            depotCloture: depot,
            peutAdministrer: admin,
            peutCloturer: cloturer,
            maintenant: () => maintenant,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('carte-cloture')));
      await tester.pumpAndSettle();
    }

    ecranTest('⚠️ la page rend les libellés du Blade : en-tête, onglets, sélecteur de mois, historique', (tester) async {
      await db.into(db.periodicClosures).insert(PeriodicClosuresCompanion.insert(id: uuid('p1'), period: '2026-04', closedAt: Value(DateTime(2026, 5, 2))));
      await afficher(tester);

      for (final t in ["Bascule & Clôture d'Exercice Comptable", "Sélection de l'exercice fiscal actif et assistant de clôture annuelle (N vers N+1).", 'Clôture Périodique', 'Clôture Annuelle', 'Clôturer le Mois Sélectionné', 'Historique des Clôtures Périodiques', 'Avril 2026', 'Clôturé', 'Déclôturer (exceptionnel)']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.text('Balance Équilibrée — Clôture Autorisée'), findsOneWidget);
    });

    ecranTest('⚠️⚠️ « Clôturer le Mois » : modale de confirmation, puis la DEMANDE est écrite, pas la clôture', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('cloture-mois-bouton')));
      await tester.pumpAndSettle();
      expect(find.text('Clôturer ce Mois ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloture-mois-confirmer')));
      await tester.pumpAndSettle();

      final d = (await demandes()).single;
      expect((d.kind, d.syncStatus), ('cloturer_periode', SyncStatus.pending));
      expect(jsonDecode(d.payload), {'period': '2027-02'});
      expect(await db.select(db.periodicClosures).get(), isEmpty);
      expect(find.byKey(Key('cloture-demande-${d.id}')), findsOneWidget);
    });

    ecranTest('un mois clôturé : « Mois Déjà Clôturé » ; la déclôture est réservée à l\'administrateur', (tester) async {
      await db.into(db.periodicClosures).insert(PeriodicClosuresCompanion.insert(id: uuid('p1'), period: '2027-02', closedAt: Value(DateTime(2027, 2, 2))));
      await afficher(tester, admin: false);

      expect(find.text('Mois Déjà Clôturé'), findsOneWidget);
      expect(find.text("Réservé à l'Administrateur"), findsOneWidget);
      expect(find.byKey(const Key('cloture-decloturer-2027-02')), findsNothing);
    });

    ecranTest('déclôture par l\'administrateur : modale puis demande', (tester) async {
      await db.into(db.periodicClosures).insert(PeriodicClosuresCompanion.insert(id: uuid('p1'), period: '2027-02', closedAt: Value(DateTime(2027, 2, 2))));
      await afficher(tester);

      await tester.tap(find.byKey(const Key('cloture-decloturer-2027-02')));
      await tester.pumpAndSettle();
      expect(find.text('Déclôturer ce Mois ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloture-decloture-confirmer')));
      await tester.pumpAndSettle();

      expect((await demandes()).single.kind, 'decloturer_periode');
    });

    ecranTest('⚠️⚠️ clôture annuelle : le bouton est grisé avec son motif, les étapes s\'enchaînent, la modale confirme', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('cloture-tab-annuelle')));
      await tester.pumpAndSettle();

      expect(find.text('EXERCICE 2026 — OUVERT (Lecture / Écriture)'), findsOneWidget);
      expect(find.byKey(const Key('kpi-cloture-resultat')), findsOneWidget);
      expect(find.text('300 000 F'), findsOneWidget);
      expect(find.text("Assistant de Clôture d'Exercice (2026 → 2027)"), findsOneWidget);
      expect(find.byKey(const Key('cloture-step3-motif')), findsOneWidget);
      expect(find.textContaining('Étape 1 non confirmée'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('cloture-step3'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('cloture-step1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloture-step1-demandee')), findsOneWidget);
      expect(find.textContaining('Étape 2 non faite'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cloture-step2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloture-step2-demandee')), findsOneWidget);
      expect(find.byKey(const Key('cloture-step3-motif')), findsNothing);

      await tester.tap(find.byKey(const Key('cloture-step3')));
      await tester.pumpAndSettle();
      expect(find.text("Clôturer l'Exercice 2026 ?"), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloture-confirmer')));
      await tester.pumpAndSettle();

      expect([for (final d in await demandes()) d.kind], ['confirmer_etape1', 'solder_comptes_gestion', 'cloturer_exercice']);
    });

    ecranTest('un exercice clos : lecture seule, « Rouvrir l\'Exercice » pour l\'administrateur seulement', (tester) async {
      await (db.update(db.fiscalYears)).write(FiscalYearsCompanion(status: const Value('cloture'), closedAt: Value(DateTime(2027, 2, 1, 9, 30))));
      await afficher(tester);
      await tester.tap(find.byKey(const Key('cloture-tab-annuelle')));
      await tester.pumpAndSettle();
      // Comme au web : sans exercice ouvert, l'écran s'ouvre sur l'année du jour (2027, inexistant) — on revient à 2026.
      expect(find.text('EXERCICE 2027 — INEXISTANT'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloture-annee-precedente')));
      await tester.pumpAndSettle();

      expect(find.text('Cet exercice est clôturé.'), findsOneWidget);
      expect(find.text('Consultable en lecture seule — clôturé le 01/02/2027 à 09:30.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloture-rouvrir')));
      await tester.pumpAndSettle();
      expect(find.text("Rouvrir l'Exercice 2026 ?"), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloture-reouverture-confirmer')));
      await tester.pumpAndSettle();
      expect((await demandes()).single.kind, 'rouvrir_exercice');
    });

    ecranTest('« Ouvrir l\'exercice N+1 » n\'est offert qu\'à partir du 1er décembre', (tester) async {
      maintenant = DateTime(2026, 11, 20);
      await afficher(tester);
      await tester.tap(find.byKey(const Key('cloture-tab-annuelle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloture-ouvrir-suivant')), findsNothing);
    });

    ecranTest('le lettrage sans relevé est « — » avec « Disponible après … », jamais 100 %', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('cloture-tab-annuelle')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('kpi-cloture-lettrage')), matching: find.text('—')), findsOneWidget);
      expect(find.textContaining('Disponible après'), findsOneWidget);
    });
  });
}
