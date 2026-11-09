import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:agrierp/features/comptabilite/rapprochement_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket CP-5 — RAPPROCHEMENT BANCAIRE AU POSTE : le calcul est celui de `BankReconciliationService::reconcile` (parité
/// EXÉCUTÉE contre le vrai PHP), l'import d'un relevé est une DEMANDE (`bank_statement_imports`).
const _script = r'''<?php
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
$fy = (string) Illuminate\Support\Str::uuid();
Illuminate\Support\Facades\DB::table('fiscal_years')->insert(['id' => $fy, 'year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert', 'created_at' => now(), 'updated_at' => now()]);
$compte = (string) Illuminate\Support\Str::uuid();
$autre = (string) Illuminate\Support\Str::uuid();
foreach ([[$compte, '521', 5], [$autre, '701', 7]] as [$id, $code, $classe]) {
    Illuminate\Support\Facades\DB::table('chart_of_accounts')->insert(['id' => $id, 'code' => $code, 'label' => 'C'.$code, 'class' => $classe, 'is_active' => 1, 'created_at' => now(), 'updated_at' => now()]);
}
foreach ($in['ecritures'] as $e) {
    $id = (string) Illuminate\Support\Str::uuid();
    Illuminate\Support\Facades\DB::table('accounting_entries')->insert(['id' => $id, 'fiscal_year_id' => $fy, 'entry_date' => $e['date'], 'reference' => $e['reference'], 'is_active' => 1, 'created_at' => now(), 'updated_at' => now()]);
    $d = $e['montant'] > 0 ? $e['montant'] : 0; $c = $e['montant'] < 0 ? -$e['montant'] : 0;
    Illuminate\Support\Facades\DB::table('accounting_entry_lines')->insert(['id' => (string) Illuminate\Support\Str::uuid(), 'entry_id' => $id, 'account_id' => $compte, 'debit' => $d, 'credit' => $c, 'created_at' => now(), 'updated_at' => now()]);
    Illuminate\Support\Facades\DB::table('accounting_entry_lines')->insert(['id' => (string) Illuminate\Support\Str::uuid(), 'entry_id' => $id, 'account_id' => $autre, 'debit' => $c, 'credit' => $d, 'created_at' => now(), 'updated_at' => now()]);
}
foreach ($in['releves'] as $r) {
    App\Models\BankStatementLine::create(['account_id' => $compte, 'statement_date' => $r['date'], 'label' => $r['libelle'], 'amount' => $r['montant']]);
}
$r = app(App\Services\BankReconciliationService::class)->reconcile($compte, $in['debut'], $in['fin']);
echo json_encode([
    'ouverture' => $r['opening_balance'], 'solde_livre' => $r['solde_livre'], 'solde_releve' => $r['solde_releve'],
    'en_instance' => $r['en_instance'], 'nouveau' => $r['nouveau_non_saisi'], 'ecart' => $r['ecart'],
    'pointes_livre' => count(array_filter($r['ledger'], fn ($l) => $l['is_matched'])), 'pointes_releve' => count(array_filter($r['statement'], fn ($l) => $l['is_matched'])),
    'nb_livre' => count($r['ledger']), 'nb_releve' => count($r['statement']),
]);
''';

void main() {
  final saut = sautSansPhp();
  late AppDatabase db;
  late RapprochementRepository depot;

  String uuid(String g) => g.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = RapprochementRepository(database: db, deviceId: 'poste-test', horloge: () => DateTime(2026, 10, 28, 10));
    await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(id: uuid('ex26'), year: 2026, startDate: Value(DateTime(2026, 1, 1)), endDate: Value(DateTime(2026, 12, 31)), status: const Value('ouvert')));
    await db.into(db.chartOfAccounts).insert(ChartOfAccountsCompanion.insert(id: uuid('c521'), code: '521', label: 'Banque', accountClass: const Value(5)));
    await db.into(db.chartOfAccounts).insert(ChartOfAccountsCompanion.insert(id: uuid('c701'), code: '701', label: 'Ventes', accountClass: const Value(7)));
  });
  tearDown(() async => db.close());

  Future<void> ecriture(String id, DateTime date, double montant, String reference) async {
    await db.into(db.accountingEntries).insert(AccountingEntriesCompanion.insert(id: uuid(id), fiscalYearId: Value(uuid('ex26')), entryDate: date, reference: Value(reference)));
    await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: uuid('${id}a'), entryId: uuid(id), accountId: uuid('c521'), debit: Value(montant > 0 ? montant : 0), credit: Value(montant < 0 ? -montant : 0)));
    await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: uuid('${id}b'), entryId: uuid(id), accountId: uuid('c701'), debit: Value(montant < 0 ? -montant : 0), credit: Value(montant > 0 ? montant : 0)));
  }

  Future<void> releve(String id, DateTime date, double montant, [String libelle = 'Opération']) =>
      db.into(db.bankStatementLines).insert(BankStatementLinesCompanion.insert(id: uuid(id), accountId: uuid('c521'), statementDate: date, label: libelle, amount: montant));

  group('lettrage', () {
    test('⚠️ même montant à 5 jours près, une seule fois : le doublon réel n\'est jamais masqué', () async {
      await ecriture('e1', DateTime(2026, 10, 1), 100000, 'OD-1 — Dépôt');
      await ecriture('e2', DateTime(2026, 10, 2), 100000, 'OD-2 — Dépôt bis');
      await releve('r1', DateTime(2026, 10, 6), 100000); // 5 jours de e1 : apparié (borne incluse)
      await releve('r2', DateTime(2026, 10, 15), 100000); // à plus de 5 jours des deux : jamais apparié

      final r = await depot.rapprocher(uuid('c521'), DateTime(2026, 10, 1), DateTime(2026, 10, 31));

      expect(r.livre.map((l) => l.pointee), [true, false]);
      expect(r.releve.map((l) => l.pointee), [true, false]);
      expect((r.soldeLivre, r.soldeReleve, r.enInstance, r.nouveauNonSaisi), (200000, 200000, 100000, 100000));
      expect(r.equilibre, isTrue);
    });

    test('le libellé du livre est la référence après le premier « — », l\'ouverture suit la règle R1', () async {
      await ecriture('e0', DateTime(2026, 9, 10), 50000, 'OD-0 — Apport');
      await ecriture('e1', DateTime(2026, 10, 3), -2500, 'OD-1 — Frais — tenue de compte');

      final r = await depot.rapprocher(uuid('c521'), DateTime(2026, 10, 1), DateTime(2026, 10, 31));

      expect(r.ouverture, 50000);
      expect(r.livre.single.libelle, 'Frais — tenue de compte');
      expect((r.soldeLivre, r.enInstance), (47500, -2500));
    });
  });


  test('⚠️⚠️ mêmes soldes, mêmes écarts, mêmes pointages que le serveur, sur 6 jeux pseudo-aléatoires (montants répétés)', () async {
    final alea = Random(2810);
    final montants = [25000.0, 100000.0, -2500.0, 40000.0, 75000.5, -10000.0];
    String jour(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final jeux = <Map<String, Object?>>[];
    for (var n = 0; n < 6; n++) {
      DateTime tire() => DateTime(2026, 2 + alea.nextInt(3), 1 + alea.nextInt(28));
      jeux.add({
        'debut': '2026-03-01',
        'fin': '2026-04-30',
        'ecritures': [for (var i = 0; i < 22; i++) {'date': jour(tire()), 'montant': montants[alea.nextInt(montants.length)], 'reference': 'OD-$i — Pièce $i'}],
        'releves': [for (var i = 0; i < 20; i++) {'date': jour(tire()), 'montant': montants[alea.nextInt(montants.length)], 'libelle': 'Ligne $i'}],
      });
    }

    for (final jeu in jeux) {
      final attendu = Map<String, dynamic>.from(executerPhp(_script, jeu, application: true) as Map);
      // Le poste reçoit le même jeu.
      final base = AppDatabase.forTesting(NativeDatabase.memory());
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(base.close);
      final dep = RapprochementRepository(database: base, deviceId: 'p');
      {
        await base.into(base.fiscalYears).insert(FiscalYearsCompanion.insert(id: uuid('ex'), year: 2026, startDate: Value(DateTime(2026, 1, 1)), endDate: Value(DateTime(2026, 12, 31)), status: const Value('ouvert')));
        await base.into(base.chartOfAccounts).insert(ChartOfAccountsCompanion.insert(id: uuid('c521'), code: '521', label: 'Banque', accountClass: const Value(5)));
        await base.into(base.chartOfAccounts).insert(ChartOfAccountsCompanion.insert(id: uuid('c701'), code: '701', label: 'Ventes', accountClass: const Value(7)));
        var k = 0;
        for (final e in (jeu['ecritures'] as List).cast<Map>()) {
          final id = uuid('e-${(k++).toString().padLeft(3, '0')}');
          final m = (e['montant'] as num).toDouble();
          await base.into(base.accountingEntries).insert(AccountingEntriesCompanion.insert(id: id, fiscalYearId: Value(uuid('ex')), entryDate: DateTime.parse(e['date'] as String), reference: Value(e['reference'] as String)));
          await base.into(base.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: '${id.substring(0, 34)}-a', entryId: id, accountId: uuid('c521'), debit: Value(m > 0 ? m : 0), credit: Value(m < 0 ? -m : 0)));
        }
        k = 0;
        for (final r in (jeu['releves'] as List).cast<Map>()) {
          await base.into(base.bankStatementLines).insert(BankStatementLinesCompanion.insert(id: uuid('r-${(k++).toString().padLeft(3, '0')}'), accountId: uuid('c521'), statementDate: DateTime.parse(r['date'] as String), label: r['libelle'] as String, amount: (r['montant'] as num).toDouble()));
        }
        final r = await dep.rapprocher(uuid('c521'), DateTime(2026, 3, 1), DateTime(2026, 4, 30));
        expect((r.soldeLivre, r.soldeReleve, r.enInstance, r.nouveauNonSaisi, r.ecart),
            ((attendu['solde_livre'] as num).toDouble(), (attendu['solde_releve'] as num).toDouble(), (attendu['en_instance'] as num).toDouble(), (attendu['nouveau'] as num).toDouble(), (attendu['ecart'] as num).toDouble()));
        expect(r.livre.where((l) => l.pointee).length, attendu['pointes_livre']);
        expect(r.releve.where((l) => l.pointee).length, attendu['pointes_releve']);
        expect((r.livre.length, r.releve.length), (attendu['nb_livre'], attendu['nb_releve']));
      }
    }
  }, skip: saut);

  group('import', () {
    test('⚠️ l\'import écrit une DEMANDE pending avec le texte du fichier ; vide ou trop gros, il est refusé avant d\'écrire', () async {
      final id = await depot.importerReleve(compteId: uuid('c521'), contenu: 'date;libellé;montant\n2026-10-05;Dépôt;1000\n', octets: 40, nomFichier: 'octobre.csv');

      final d = (await db.select(db.bankStatementImports).get()).single;
      expect((d.id, d.syncStatus, d.accountId, d.fileName), (id, SyncStatus.pending, uuid('c521'), 'octobre.csv'));
      expect(d.content, contains('Dépôt'));

      expect(depot.validerImport(compteId: '', contenu: '  ', octets: 0).keys, containsAll(['accountId', 'releve']));
      expect(depot.validerImport(compteId: 'x', contenu: 'a', octets: 3 * 1024 * 1024)['releve'], 'Le fichier relevé ne doit pas dépasser 2048 kilo-octets.');
      await expectLater(depot.importerReleve(compteId: '', contenu: '', octets: 0), throwsA(isA<RapprochementRefuse>()));
      expect((await db.select(db.bankStatementImports).get()).length, 1);
    });

    test('⚠️ le moteur envoie {id, account_id, content}, acquitte, et le tirage remplace les lignes de relevé', () async {
      final envois = <Map<String, dynamic>>[];
      var tirage = <String, dynamic>{'server_time': '2026-10-28T12:00:00Z'};
      final client = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          if (o.path.contains('push')) {
            final corps = o.data as Map<String, dynamic>;
            envois.add(corps);
            h.resolve(Response(requestOptions: o, statusCode: 200, data: {
              for (final e in corps.entries)
                if (e.value is List) e.key: {'accepted': [for (final x in e.value as List) (x as Map)['id']], 'rejected': []},
            }));
          } else {
            h.resolve(Response(requestOptions: o, statusCode: 200, data: tirage));
          }
        }));
      final moteur = SyncEngine(database: db, client: client, deviceId: 'poste-test', connectivity: _Connectivite(), maintenant: () => DateTime(2026, 10, 28, 14));
      final id = await depot.importerReleve(compteId: uuid('c521'), contenu: 'x;y;1', octets: 5);
      tirage = {
        'server_time': '2026-10-28T13:00:00Z',
        'bank_statement_lines': [
          {'id': uuid('r1'), 'account_id': uuid('c521'), 'statement_date': '2026-10-05', 'label': 'Dépôt', 'amount': 125000.5},
        ],
      };

      await moteur.synchroniser();

      expect((envois.single['bank_statement_imports'] as List).single, {'id': id, 'account_id': uuid('c521'), 'content': 'x;y;1'});
      expect((await db.select(db.bankStatementImports).get()).single.syncStatus, SyncStatus.synced);
      final l = (await db.select(db.bankStatementLines).get()).single;
      expect((l.label, l.amount, l.statementDate), ('Dépôt', 125000.5, DateTime(2026, 10, 5)));
    });
  });

  group('écran', () {
    testWidgets('⚠️ la page montre les quatre cartes, le bandeau, les deux tableaux ; l\'import passe par le fichier choisi', (tester) async {
      tester.view.physicalSize = const Size(1700, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await ecriture('e1', DateTime(2026, 10, 3), 100000, 'OD-1 — Dépôt');
      await releve('r1', DateTime(2026, 10, 4), 100000, 'VIR dépôt');
      await tester.pumpWidget(MaterialApp(
        home: ComptabiliteScreen(
          depot: ComptabiliteRepository(database: db),
          depotRapprochement: depot,
          maintenant: () => DateTime(2026, 10, 28, 10),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('carte-rapprochement')));
      await tester.pumpAndSettle();

      expect(find.text('Rapprochement Bancaire'), findsWidgets);
      for (final k in ['livre', 'releve', 'instance', 'ecart']) {
        expect(find.byKey(Key('kpi-rapprochement-$k')), findsOneWidget, reason: k);
      }
      expect(find.text('Rapprochement équilibré — Solde Livre corrigé des opérations en instance et des lignes non saisies = Solde Relevé.'), findsOneWidget);
      expect(find.text('Pointé'), findsNWidgets(2));
      expect(find.textContaining('Lettrage automatique :'), findsOneWidget);
    });
  });
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}
