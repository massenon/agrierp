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

/// Ticket CP-2 — L'ÉCRITURE MANUELLE SE DEMANDE AU POSTE (`Comptabilite\JournalComptable` : newEntry, saveEntry, archiveEntry).
///
/// ⚠️⚠️ **LE POSTE N'ÉCRIT JAMAIS UNE ÉCRITURE** : il écrit la DEMANDE (`pending`). Le serveur (`SaisieEcritureManuelleAction`) la
/// joue avec les refus du web, attribue le numéro `OD-AAAA-NNNN`, et l'écriture revient au tirage de confirmation.
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
  final jour = DateTime(2026, 10, 20);

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
    depot = ComptabiliteRepository(database: db, deviceId: 'poste-test', horloge: () => DateTime(2026, 10, 28, 10));
    await db.into(db.chartOfAccounts).insert(ChartOfAccountsCompanion.insert(id: uuid('c531'), code: '531', label: 'Caisse', accountClass: const Value(5)));
    await db.into(db.chartOfAccounts).insert(ChartOfAccountsCompanion.insert(id: uuid('c701'), code: '701', label: 'Ventes', accountClass: const Value(7)));
    await db.into(db.fiscalYears).insert(
      FiscalYearsCompanion.insert(id: uuid('ex26'), year: 2026, startDate: Value(DateTime(2026, 1, 1)), endDate: Value(DateTime(2026, 12, 31)), status: const Value('ouvert')),
    );
    // Une écriture à deux lignes (modifiable) et une à trois lignes (non représentable), plus une verrouillée.
    Future<void> ecriture(String cle, {bool verrouillee = false, List<(String, double, double)> lignes = const []}) async {
      await db.into(db.accountingEntries).insert(
        AccountingEntriesCompanion.insert(id: uuid(cle), fiscalYearId: Value(uuid('ex26')), entryDate: jour, reference: Value('OD-2026-0001 — Libellé $cle'), isLocked: Value(verrouillee)),
      );
      for (final (i, l) in lignes.indexed) {
        await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: uuid('$cle-l$i'), entryId: uuid(cle), accountId: uuid(l.$1), debit: Value(l.$2), credit: Value(l.$3)));
      }
    }
    await ecriture('e1', lignes: [('c531', 5000, 0), ('c701', 0, 5000)]);
    await ecriture('e3', lignes: [('c531', 5000, 0), ('c701', 0, 3000), ('c701', 0, 2000)]);
    await ecriture('e4', verrouillee: true, lignes: [('c531', 100, 0), ('c701', 0, 100)]);
  });
  tearDown(() async => db.close());

  Future<String?> refusDe(Future<void> Function() geste) async {
    try {
      await geste();
    } on SaisieCompteRefusee catch (e) {
      return e.erreurs.entries.map((x) => '${x.key}=${x.value}').join(' | ');
    }
    return null;
  }

  group('dépôt', () {
    test('⚠️⚠️ une création écrit la DEMANDE (pending, ce poste), jamais une écriture', () async {
      final avant = (await db.select(db.accountingEntries).get()).length;

      final d = await depot.creerEcriture(date: jour, libelle: '  Régularisation  ', debitId: uuid('c531'), creditId: uuid('c701'), montant: '25000');

      expect((d.action, d.syncStatus, d.deviceId), ('creer', SyncStatus.pending, 'poste-test'));
      expect((d.label, d.amount), ('Régularisation', 25000.0));
      expect(d.entryId, isNull);
      expect((await db.select(db.accountingEntries).get()).length, avant, reason: 'aucune écriture écrite au poste');
      expect((await db.select(db.accountingEntryLines).get()).length, 7);
    });

    test('⚠️ les refus du web sont reproduits AVANT d\'écrire, mêmes messages', () async {
      Future<String?> essai({DateTime? date, String libelle = 'x', String debit = '', String credit = '', String montant = '10'}) =>
          refusDe(() => depot.creerEcriture(date: date, libelle: libelle, debitId: debit, creditId: credit, montant: montant));

      expect(await essai(date: null, libelle: '', debit: '', credit: '', montant: ''), allOf(contains("date de l'écriture est obligatoire"), contains('libellé est obligatoire'), contains('compte à débiter est obligatoire'), contains('compte à créditer est obligatoire'), contains('montant est obligatoire')));
      expect(await essai(date: jour, debit: uuid('c531'), credit: uuid('c531')), contains('Le compte à créditer doit être différent du compte à débiter.'));
      expect(await essai(date: jour, debit: uuid('c531'), credit: uuid('c701'), montant: '0'), contains('au moins 1'));
      expect(await essai(date: jour, debit: uuid('c531'), credit: uuid('c701'), montant: 'abc'), contains('doit être un nombre'));
      expect(await essai(date: DateTime(2027, 2, 1), debit: uuid('c531'), credit: uuid('c701')), contains('entryDate='), reason: 'aucun exercice ouvert en 2027 : motif R4');
      expect(await db.select(db.manualEntryRequests).get(), isEmpty);
    });

    test('modifier et archiver visent une écriture à deux lignes, non verrouillée, sans demande déjà en attente', () async {
      expect(await refusDe(() => depot.modifierEcriture(uuid('e4'), date: jour, libelle: 'x', debitId: uuid('c531'), creditId: uuid('c701'), montant: '10')), contains('verrouillée (exercice clôturé) et ne peut plus être modifiée'));
      expect(await refusDe(() => depot.archiverEcriture(uuid('e4'))), contains('ne peut plus être archivée'));
      expect(await refusDe(() => depot.archiverEcriture(uuid('e3'))), contains('plus d\'un débit ou d\'un crédit'));
      expect(await refusDe(() => depot.archiverEcriture(uuid('inconnue'))), contains('Écriture inconnue'));

      final m = await depot.modifierEcriture(uuid('e1'), date: jour, libelle: 'Corrigé', debitId: uuid('c701'), creditId: uuid('c531'), montant: '6000');
      expect((m.action, m.entryId, m.amount), ('modifier', uuid('e1'), 6000.0));
      expect(await refusDe(() => depot.archiverEcriture(uuid('e1'))), contains('demande est déjà en attente'));
    });

    test('l\'écriture d\'à-nouveau est verrouillée avec le motif du serveur', () async {
      await (db.update(db.accountingEntries)..where((e) => e.id.equals(uuid('e1')))).write(const AccountingEntriesCompanion(sourceType: Value('ran')));

      expect(await refusDe(() => depot.archiverEcriture(uuid('e1'))), contains("L'écriture d'à-nouveau de l'exercice 2026 est verrouillée"));
    });
  });

  group('moteur', () {
    test('⚠️⚠️ l\'envoi porte la demande (sans numéro) ; acquittée, elle disparaît de la liste d\'attente', () async {
      final c = await depot.creerEcriture(date: jour, libelle: 'Régularisation', debitId: uuid('c531'), creditId: uuid('c701'), montant: '25000');
      final a = await depot.archiverEcriture(uuid('e1'));

      await moteur.synchroniser();

      final envoyees = {for (final e in (serveur.envois.single['manual_entry_requests'] as List)) (e as Map)['id']: e};
      expect(envoyees[c.id], {'id': c.id, 'action': 'creer', 'entry_date': '2026-10-20', 'label': 'Régularisation', 'debit_account_id': uuid('c531'), 'credit_account_id': uuid('c701'), 'amount': 25000.0});
      expect(envoyees[a.id], {'id': a.id, 'action': 'archiver', 'entry_id': uuid('e1')}, reason: 'un archivage ne porte que l\'écriture visée');
      expect((await depot.charger()).demandes, isEmpty);
    });

    test('un refus du serveur garde son motif et se relance', () async {
      final c = await depot.creerEcriture(date: jour, libelle: 'x', debitId: uuid('c531'), creditId: uuid('c701'), montant: '10');
      serveur.refus[c.id] = 'Ce mois est clôturé — aucune écriture ne peut y être ajoutée ni modifiée.';

      await moteur.synchroniser();

      final demandes = (await depot.charger()).demandes;
      expect(demandes.single.refusee, isTrue);
      expect(demandes.single.motifRefus, contains('Ce mois est clôturé'));
      final conflit = (await db.select(db.syncConflicts).get()).firstWhere((x) => x.sourceTable == 'manual_entry_requests');
      await moteur.relancer(conflit);
      expect((await depot.charger()).demandes.single.refusee, isFalse);
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      await tester.pumpWidget(MaterialApp(home: ComptabiliteScreen(depot: depot, maintenant: () => DateTime(2026, 10, 28, 10))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('carte-journal')));
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️⚠️ « Saisie d\'Écriture » : refus sous les champs, puis la demande est écrite et listée « en attente d\'envoi »', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('journal-saisie-ecriture')));
      await tester.pumpAndSettle();
      expect(find.text("Saisie d'Écriture"), findsWidgets);
      await tester.tap(find.byKey(const Key('ecriture-enregistrer')));
      await tester.pumpAndSettle();
      expect(find.text('Le champ libellé est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ compte à débiter est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ montant est obligatoire.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('ecriture-libelle')), 'Régularisation de caisse');
      await tester.tap(find.byKey(const Key('ecriture-debit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('531 - Caisse').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ecriture-credit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('531 - Caisse').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ecriture-montant')), '25000');
      await tester.tap(find.byKey(const Key('ecriture-enregistrer')));
      await tester.pumpAndSettle();
      expect(find.text('Le compte à créditer doit être différent du compte à débiter.'), findsOneWidget);
      expect(await db.select(db.manualEntryRequests).get(), isEmpty);

      await tester.tap(find.byKey(const Key('ecriture-credit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('701 - Ventes').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ecriture-enregistrer')));
      await tester.pumpAndSettle();

      final d = (await db.select(db.manualEntryRequests).get()).single;
      expect((d.action, d.amount, d.syncStatus), ('creer', 25000.0, SyncStatus.pending));
      expect(find.byKey(const Key('journal-demandes')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('journal-demande-statut-0'))).data, "En attente d'envoi");
      expect(find.textContaining('Régularisation de caisse'), findsWidgets);
      expect(find.textContaining('ne pèserait ni sur le stock ni sur la caisse'), findsNothing, reason: 'l\'ancienne mention a disparu');
    });

    testWidgets('« Modifier » pré-remplit la modale ; le cadenas remplace les actions d\'une écriture verrouillée', (tester) async {
      await afficher(tester);

      expect(find.byTooltip('Écriture verrouillée (exercice clôturé)'), findsOneWidget, reason: 'e4 est verrouillée');
      await tester.tap(find.byKey(const Key('journal-modifier-0')));
      await tester.pumpAndSettle();
      expect(find.text("Modifier l'Écriture"), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('ecriture-montant'))).controller!.text, isNotEmpty);
      await tester.tap(find.byKey(const Key('ecriture-enregistrer')));
      await tester.pumpAndSettle();

      final d = (await db.select(db.manualEntryRequests).get()).single;
      expect(d.action, 'modifier');
      expect(find.textContaining('Modification en attente'), findsOneWidget);
    });

    testWidgets('« Archiver » : confirmation du Blade, demande écrite, écriture marquée en attente', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('journal-archiver-0')));
      await tester.pumpAndSettle();
      expect(find.text("Confirmer l'archivage"), findsOneWidget);
      await tester.tap(find.byKey(const Key('ecriture-archiver-confirmer')));
      await tester.pumpAndSettle();

      expect((await db.select(db.manualEntryRequests).get()).single.action, 'archiver');
      expect(find.textContaining('Archivage en attente'), findsOneWidget);
    });
  });
}
