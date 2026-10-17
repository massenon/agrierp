import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chemins_depot.dart';

/// Ticket F0.83 — PLAN COMPTABLE SYSCOHADA RÉVISÉ AU POSTE (phase A de l'item 9).
///
/// Le serveur (ticket 15.27) sert désormais 1 300+ comptes au lieu de 36. Le poste n'embarque
/// AUCUNE copie du plan : il le reçoit par `/sync/pull`. Ces tests relisent le CSV du dépôt
/// Laravel (la source unique, jamais copiée ici) et le comparent à ce que le poste stocke et
/// affiche.
///
/// ⚠️ Ce que ces tests protègent : un compte SANS écriture ne doit jamais apparaître comme un
/// solde 0 dans la balance, et le Grand Livre s'ouvre sur « 531 » comme le serveur (F0.85 ; le ticket
/// F0.83 l'ouvrait sur le premier compte mouvementé, un écart au serveur désormais retiré) — deux
/// défauts qui n'émettent AUCUNE erreur.
final _cheminCsv =
    '$dossierLaravel/database/data/plan-comptable-syscohada-revise.csv';

class _ConnectiviteFeinte implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class _ServeurFeint extends Interceptor {
  _ServeurFeint(this.pull);

  final Map<String, dynamic> pull;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path.contains('push') ? <String, dynamic>{} : pull,
      ),
    );
  }
}

/// Lecture BRUTE et indépendante du CSV : code -> libellé.
Map<String, String> _lireCsv() {
  var texte = File(_cheminCsv).readAsStringSync(encoding: utf8);
  if (texte.startsWith('\uFEFF')) texte = texte.substring(1);

  final plan = <String, String>{};
  final lignes = texte.split(RegExp(r'\r\n|\n|\r'));
  for (var i = 1; i < lignes.length; i++) {
    if (lignes[i].trim().isEmpty) continue;
    final coupe = lignes[i].indexOf(';');
    var libelle = lignes[i].substring(coupe + 1).trim();
    if (libelle.length > 1 &&
        libelle.startsWith('"') &&
        libelle.endsWith('"')) {
      libelle = libelle.substring(1, libelle.length - 1).replaceAll('""', '"');
    }
    plan[lignes[i].substring(0, coupe).trim()] = libelle;
  }

  return plan;
}

String _uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

void main() {
  final csvPresent = File(_cheminCsv).existsSync();
  // Chemin absolu du dépôt Laravel : sur une machine qui ne l'a pas, les tests qui relisent le CSV sont SAUTÉS (jamais
  // échoués). `testWidgets` n'accepte qu'un booléen pour `skip` : la raison est donc écrite dans la sortie du test.
  if (!csvPresent) {
    // ignore: avoid_print
    print(
      'SAUT : CSV du plan absent ($_cheminCsv), dépôt Laravel non présent sur cette machine ; '
      'les tests du plan SYSCOHADA qui le relisent sont sautés, pas réussis.',
    );
  }

  late AppDatabase db;
  late ComptabiliteRepository depot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ComptabiliteRepository(database: db);
  });

  tearDown(() async => db.close());

  /// Ce que le serveur sert : `id`, `code`, `label`, `class` — rien d'autre.
  List<Map<String, dynamic>> charge(Map<String, String> plan) {
    var n = 0;
    return [
      for (final e in plan.entries)
        {
          'id': _uuid(++n),
          'code': e.key,
          'label': e.value,
          'class': int.parse(e.key[0]),
        },
    ];
  }

  SyncEngine moteur(Map<String, dynamic> pull) {
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'));
    client.interceptors.add(_ServeurFeint(pull));

    return SyncEngine(
      database: db,
      client: client,
      deviceId: 'poste-test',
      connectivity: _ConnectiviteFeinte(),
    );
  }

  Map<String, dynamic> tirage(List<Map<String, dynamic>> plan) => {
    'server_time': '2026-10-10T12:00:00+00:00',
    'chart_of_accounts': plan,
  };

  group('absorbeur du plan comptable', () {
    test(
      '⚠️ le poste avale les 1 332 comptes du CSV, contenu compris',
      () async {
        final csv = _lireCsv();
        expect(csv, hasLength(1332), reason: 'recalcul indépendant du CSV');

        final resultat = await moteur(tirage(charge(csv))).synchroniser();
        expect(resultat.tire, 1332);

        final comptes = await db.select(db.chartOfAccounts).get();
        expect(comptes, hasLength(1332));
        expect({for (final c in comptes) c.code: c.label}, csv);
        for (final c in comptes) {
          expect(c.accountClass, int.parse(c.code[0]), reason: c.code);
        }
        expect(
          comptes.map((c) => c.accountClass).toSet(),
          {1, 2, 3, 4, 5, 6, 7, 8, 9},
          reason: 'les neuf classes, dont la 9',
        );
      },
      skip: !csvPresent,
    );

    test(
      'un second tirage ne duplique rien (fusion par identifiant)',
      () async {
        final plan = charge(_lireCsv());
        await moteur(tirage(plan)).synchroniser();
        await moteur(tirage(plan)).synchroniser();

        expect(await db.select(db.chartOfAccounts).get(), hasLength(1332));
      },
      skip: !csvPresent,
    );

    test(
      '⚠️ un tirage incohérent est REFUSÉ en bloc : le plan précédent reste',
      () async {
        final csv = _lireCsv();
        final plan = charge(csv);
        await moteur(tirage(plan)).synchroniser();

        // Deux comptes portant le même identifiant : l'absorbeur est strict, il ne fusionne
        // pas en silence deux comptes différents.
        final casse = [
          ...plan,
          {...plan[3], 'code': '99999'},
        ];
        await expectLater(
          moteur(tirage(casse)).synchroniser(),
          throwsA(anything),
        );

        final restants = await db.select(db.chartOfAccounts).get();
        expect(restants, hasLength(1332), reason: 'transaction annulée');
        expect({for (final c in restants) c.code: c.label}, csv);
      },
      skip: !csvPresent,
    );

    test(
      'l absorption du plan ne touche pas une saisie en attente',
      () async {
        await db
            .into(db.livestockLots)
            .insert(
              LivestockLotsCompanion.insert(
                id: '11111111-1111-4111-8111-111111111111',
                code: 'AVI-2026-01',
                speciesId: '22222222-2222-4222-8222-222222222222',
              ),
            );
        await db
            .into(db.livestockDailyEntries)
            .insert(
              LivestockDailyEntriesCompanion.insert(
                id: '33333333-3333-4333-8333-333333333333',
                deviceId: 'poste-test',
                updatedAt: DateTime(2026, 10, 9),
                lotId: '11111111-1111-4111-8111-111111111111',
                entryDate: DateTime(2026, 10, 9),
              ),
            );
        expect(await db.pendingCount(), 1);

        // Hors ligne le temps du tirage : la saisie doit rester en file.
        final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'));
        client.interceptors.add(_ServeurFeint(tirage(charge(_lireCsv()))));
        final hors = SyncEngine(
          database: db,
          client: client,
          deviceId: 'poste-test',
          connectivity: _ConnectiviteHorsLigne(),
        );
        await hors.synchroniser();
        expect(await db.pendingCount(), 1);
        expect(await db.select(db.chartOfAccounts).get(), isEmpty);
      },
      skip: !csvPresent,
    );
  });

  group('états au poste avec le plan complet', () {
    Future<void> chargerPlan() async {
      await moteur(tirage(charge(_lireCsv()))).synchroniser();
    }

    Future<String> idDe(String code) async => (await (db.select(
      db.chartOfAccounts,
    )..where((c) => c.code.equals(code))).getSingle()).id;

    /// Deux écritures équilibrées sur 5711/7011 (comptes du CSV).
    Future<void> ecritures() async {
      await db
          .into(db.fiscalYears)
          .insert(
            FiscalYearsCompanion.insert(
              id: _uuid(9000),
              year: 2026,
              startDate: Value(DateTime(2026, 1, 1)),
              endDate: Value(DateTime(2026, 12, 31)),
              status: const Value('ouvert'),
            ),
          );
      final caisse = await idDe('5711');
      final vente = await idDe('7011');
      var n = 9100;
      for (final (montant, jour) in [(12000.0, 5), (5000.0, 10)]) {
        final e = _uuid(++n);
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: e,
                fiscalYearId: Value(_uuid(9000)),
                entryDate: DateTime(2026, 3, jour),
                reference: const Value('Vente au comptoir'),
                sourceType: const Value('sale'),
              ),
            );
        await db
            .into(db.accountingEntryLines)
            .insert(
              AccountingEntryLinesCompanion.insert(
                id: _uuid(++n),
                entryId: e,
                accountId: caisse,
                debit: Value(montant),
              ),
            );
        await db
            .into(db.accountingEntryLines)
            .insert(
              AccountingEntryLinesCompanion.insert(
                id: _uuid(++n),
                entryId: e,
                accountId: vente,
                credit: Value(montant),
              ),
            );
      }
    }

    test(
      '⚠️⚠️ la balance ne liste QUE les comptes mouvementés, pas 1 332 soldes à 0',
      () async {
        await chargerPlan();
        await ecritures();

        final d = await depot.charger();
        // Ticket F0.86 : la balance a une période ; mars 2026 couvre les deux écritures.
        final b = d.balanceGenerale(
          debut: DateTime(2026, 3, 1),
          fin: DateTime(2026, 3, 31),
        );
        final balance = b.lignes;

        expect(d.comptes, hasLength(1332));
        expect(balance.map((l) => l.code).toList(), ['5711', '7011']);
        // Recalcul indépendant : 12 000 + 5 000.
        expect(balance[0].mouvementsDebit, 17000);
        expect(balance[0].mouvementsCredit, 0);
        expect(balance[1].mouvementsCredit, 17000);
        expect(b.totalFinalDebit, 17000);
        expect(b.totalFinalCredit, 17000);
      },
      skip: !csvPresent,
    );

    // ⚠️ Ticket F0.85 : REMPLACE la règle du ticket F0.83 (« premier compte mouvementé »). Le serveur
    // ouvre le Grand Livre sur « 531 » quand il existe (`GrandLivre::defaultAccountId`) ; la doctrine
    // « le serveur fait foi, le poste le reproduit » ne permet plus l'écart.
    test(
      '⚠️ le grand livre s ouvre sur 531 comme le serveur, même si d autres comptes sont mouvementés',
      () async {
        await chargerPlan();
        await ecritures();

        final d = await depot.charger();

        expect(
          d.comptes.first.code,
          '1',
          reason: 'le plan commence par la classe 1',
        );
        expect(d.compteGrandLivreParDefaut!.code, '531');

        // Les comptes mouvementés restent consultables, avec leur solde exact.
        final c5711 = d.comptes.firstWhere((c) => c.code == '5711');
        expect(d.grandLivre(c5711.id).map((m) => m.soldeProgressif), [
          12000,
          17000,
        ]);
      },
      skip: !csvPresent,
    );

    test(
      'sans aucune écriture, le grand livre s ouvre aussi sur 531',
      () async {
        await chargerPlan();

        final d = await depot.charger();

        expect(d.compteGrandLivreParDefaut!.code, '531');
        expect(
          d.grandLivreCompte(d.compteGrandLivreParDefaut!.id).sansEcriture,
          isTrue,
        );
      },
      skip: !csvPresent,
    );

    testWidgets(
      '⚠️ l écran plan comptable affiche les 1 332 comptes avec leurs libellés',
      (tester) async {
        await tester.runAsync(
          () => moteur(tirage(charge(_lireCsv()))).synchroniser(),
        );

        tester.view.physicalSize = const Size(1700, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(home: ComptabiliteScreen(depot: depot)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('carte-planComptable')));
        await tester.pumpAndSettle();

        // Les deux cartes de la maquette, « Comptes actifs » = 1332.
        expect(find.byType(CarteKpi), findsNWidgets(2));
        expect(
          find.descendant(
            of: find.byKey(const Key('kpi-plan-comptes')),
            matching: find.text('1332'),
          ),
          findsOneWidget,
        );

        // Le nombre de lignes de code affichées = le nombre de comptes du CSV, recalculé
        // indépendamment depuis le CSV (la liste défile : tout est monté, rien n'est tronqué).
        final csv = _lireCsv();
        final affiches = {
          for (final w in tester.widgetList<Text>(find.byType(Text)))
            if (w.data != null) w.data!,
        };
        final absents = [
          for (final e in csv.entries)
            if (!affiches.contains(e.value) || !affiches.contains(e.key)) e.key,
        ];
        expect(absents, isEmpty, reason: 'comptes du CSV non affichés');
      },
      skip: !csvPresent,
    );
  });
}

class _ConnectiviteHorsLigne implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.none,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}
