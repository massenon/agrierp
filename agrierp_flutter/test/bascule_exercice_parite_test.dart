import 'dart:io';
import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:agrierp/features/comptabilite/mention_anouveaux.dart';
import 'package:agrierp/features/comptabilite/soldes_exercice.dart';
import 'package:agrierp/features/rapports/rapports_repository.dart';
import 'package:agrierp/features/sync/coherence_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Tickets EX1 / EX2 — BASCULE D'EXERCICE AU POSTE : Balance, Grand Livre, État de trésorerie et contrôle
/// « ouverture N+1 = clôture N » du poste ÉGAUX au PHP du serveur (parité EXÉCUTÉE), avant la clôture de 2026
/// (à-nouveaux provisoires, R3) et après (à-nouveau écrit, R1).
///
/// Le jeu est l'exemple du PRD `docs/prd/exercices-comptables.md` § 5 (caisse 531, banque 521101), l'exemple R3 (une
/// dotation de 30 000 passée en 2026 le 20/02/2027), plus 40 écritures pseudo-aléatoires (graine fixe) sur les deux
/// exercices. Le serveur les enregistre par `AccountingEntryService::record()`, clôt 2026 par le VRAI assistant
/// (étapes 1, 2, 3), et rend son journal et ses états ; le poste range ce journal dans Drift et calcule.
///
/// ⚠️ Les valeurs du § 5 sont aussi vérifiées en LITTÉRAUX calculés à la main (caisse 250 000, total 1 250 000…),
/// indépendamment du PHP : une parité entre deux implémentations fausses de la même façon ne protégerait rien.
void main() {
  // ── Le jeu ──────────────────────────────────────────────────────────────────────────────────────────────────
  final ecritures = <Map<String, Object>>[
    {'date': '2026-01-02', 'debit': '521101', 'credit': '101', 'montant': 1000000, 'libelle': 'Apport'},
    {'date': '2026-03-10', 'debit': '531', 'credit': '701', 'montant': 300000, 'libelle': 'Vente comptant'},
    {'date': '2026-04-15', 'debit': '605', 'credit': '531', 'montant': 100000, 'libelle': 'Énergie payée en caisse'},
    {'date': '2027-01-15', 'debit': '531', 'credit': '701', 'montant': 50000, 'libelle': 'Vente comptant'},
  ];
  // 40 écritures pseudo-aléatoires, chacune un JOUR DIFFÉRENT (l'ordre de deux pièces du même jour n'est pas défini
  // au serveur), jamais le 31/12 ni le 01/01 (étape 2 et à-nouveau), jamais avant le 03/01/2026.
  final alea = Random(20271020);
  final codes = ['101', '401', '411', '521101', '531', '601', '605', '701'];
  final jours = <String>{};
  while (jours.length < 40) {
    final d = DateTime(2026, 1, 3).add(Duration(days: alea.nextInt(540)));
    if ((d.month == 12 && d.day == 31) || (d.month == 1 && d.day == 1)) continue;
    if (d.isAfter(DateTime(2027, 6, 29))) continue;
    final cle = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (ecritures.any((e) => e['date'] == cle) || cle == '2026-12-31') continue;
    jours.add(cle);
  }
  for (final j in jours.toList()..sort()) {
    final a = codes[alea.nextInt(codes.length)];
    var b = codes[alea.nextInt(codes.length)];
    if (b == a) b = codes[(codes.indexOf(a) + 1) % codes.length];
    ecritures.add({
      'date': j,
      'debit': a,
      'credit': b,
      'montant': (alea.nextInt(4000000) + 1) / 100,
      'libelle': 'Pièce $j',
    });
  }

  const periodesBalance = [
    ['2026-01-01', '2026-12-31'],
    ['2026-03-01', '2026-03-31'],
    ['2027-01-01', '2027-12-31'],
    ['2027-01-01', '2027-01-31'],
    ['2027-02-01', '2027-02-28'],
  ];
  const comptesGrandLivre = ['531', '521101', '101', '131', '701', '2841'];
  const periodesGrandLivre = [
    ['2026-01-01', '2026-12-31'],
    ['2027-01-01', '2027-01-31'],
    ['2027-02-01', '2027-12-31'],
  ];
  const periodesTresorerie = [
    ['2026-01-01', '2026-12-31'],
    ['2027-01-01', '2027-06-30'],
  ];

  Map<String, dynamic>? serveur;
  setUpAll(() {
    if (sautSansPhp() != null) return;
    serveur =
        executerPhp('<?php\n$amorceApplication\n$_script', {
              'ecritures': ecritures,
              'balances': periodesBalance,
              'comptes_gl': comptesGrandLivre,
              'periodes_gl': periodesGrandLivre,
              'tresorerie': periodesTresorerie,
            }, application: true)
            as Map<String, dynamic>;
  });

  /// Range dans une base Drift NEUVE ce que le serveur a servi (exercices, plan, journal actif).
  Future<AppDatabase> basePoste(Map<String, dynamic> photo) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    for (final e in photo['exercices'] as List) {
      await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          id: e['id'] as String,
          year: e['year'] as int,
          startDate: Value(DateTime.parse(e['start_date'] as String)),
          endDate: Value(DateTime.parse(e['end_date'] as String)),
          status: Value(e['status'] as String),
        ),
      );
    }
    for (final c in photo['plan'] as List) {
      await db.into(db.chartOfAccounts).insert(
        ChartOfAccountsCompanion.insert(
          id: c['id'] as String,
          code: c['code'] as String,
          label: c['label'] as String,
          accountClass: Value(c['class'] as int),
        ),
      );
    }
    for (final e in photo['journal'] as List) {
      await db.into(db.accountingEntries).insert(
        AccountingEntriesCompanion.insert(
          id: e['id'] as String,
          fiscalYearId: Value(e['fiscal_year_id'] as String?),
          entryDate: DateTime.parse(e['entry_date'] as String),
          reference: Value(e['reference'] as String?),
          sourceType: Value(e['source_type'] as String?),
          isLocked: Value(e['is_locked'] as bool),
          createdAt: Value(DateTime.parse(e['created_at'] as String)),
        ),
      );
      for (final l in e['lines'] as List) {
        await db.into(db.accountingEntryLines).insert(
          AccountingEntryLinesCompanion.insert(
            id: l['id'] as String,
            entryId: e['id'] as String,
            accountId: l['account_id'] as String,
            debit: Value((l['debit'] as num).toDouble()),
            credit: Value((l['credit'] as num).toDouble()),
          ),
        );
      }
    }
    return db;
  }

  double n(Object? v) => (v as num).toDouble();

  Future<void> comparer(String phase) async {
    final photo = serveur![phase] as Map<String, dynamic>;

    // La grille couvre ce qu'elle prétend couvrir : le jeu entier, une ligne provisoire avant la clôture, un
    // à-nouveau écrit après.
    final journal = photo['journal'] as List;
    final sources = {for (final e in journal) e['source_type']};
    final lignesJanvier = ((photo['balances'] as List)[3] as Map)['rows'] as List;
    if (phase == 'provisoire') {
      expect(journal.length, 45, reason: '4 du § 5 + 40 aléatoires + la dotation');
      expect(sources.contains('ran'), isFalse);
      expect(lignesJanvier.where((r) => r['provisoire'] == true), hasLength(1));
    } else {
      expect(sources, containsAll(['ran', 'closing']));
      expect(lignesJanvier.where((r) => r['provisoire'] == true), isEmpty);
      expect((photo['controle'] as List).single['statut_precedent'], 'cloture');
    }

    final db = await basePoste(photo);
    addTearDown(db.close);
    final d = await ComptabiliteRepository(database: db).charger();
    expect(d.ecrituresIncompletes, 0);

    // Balance.
    final balances = photo['balances'] as List;
    for (var i = 0; i < periodesBalance.length; i++) {
      final p = periodesBalance[i];
      final attendu = balances[i] as Map<String, dynamic>;
      final b = d.balanceGenerale(debut: DateTime.parse(p[0]), fin: DateTime.parse(p[1]));
      final raison = '$phase — balance ${p[0]} → ${p[1]}';
      final rows = attendu['rows'] as List;
      expect(
        [for (final l in b.lignes) [l.code, l.libelle, l.provisoire]],
        [for (final r in rows) [r['code'], r['label'], r['provisoire']]],
        reason: raison,
      );
      for (var k = 0; k < rows.length; k++) {
        final r = rows[k] as Map<String, dynamic>;
        final l = b.lignes[k];
        expect(
          [l.ouvertureDebit, l.ouvertureCredit, l.mouvementsDebit, l.mouvementsCredit, l.finalDebit, l.finalCredit],
          [
            n(r['opening_debit']), n(r['opening_credit']), n(r['period_debit']),
            n(r['period_credit']), n(r['final_debit']), n(r['final_credit']),
          ],
          reason: '$raison, compte ${r['code']}',
        );
      }
      expect(
        [b.totalOuvertureDebit, b.totalOuvertureCredit, b.totalMouvementsDebit, b.totalMouvementsCredit, b.totalFinalDebit, b.totalFinalCredit, b.ecart],
        [
          n(attendu['total_opening_debit']), n(attendu['total_opening_credit']), n(attendu['total_period_debit']),
          n(attendu['total_period_credit']), n(attendu['total_final_debit']), n(attendu['total_final_credit']),
          n(attendu['ecart']),
        ],
        reason: raison,
      );
      expect(b.ouverture?.provisoire, (attendu['ouverture'] as Map)['provisoire'], reason: raison);
    }

    // Grand Livre.
    final plan = {for (final c in d.comptes) c.code: c.id};
    final livres = photo['grands_livres'] as Map<String, dynamic>;
    for (final code in comptesGrandLivre) {
      for (final p in periodesGrandLivre) {
        final attendu = livres['$code|${p[0]}|${p[1]}'] as Map<String, dynamic>;
        final g = d.grandLivreCompte(plan[code]!, debut: DateTime.parse(p[0]), fin: DateTime.parse(p[1]));
        final raison = '$phase — grand livre $code ${p[0]} → ${p[1]}';
        if (g.sansEcriture) {
          // Le poste dit « — » d'un compte sans écriture ni ouverture ; le serveur rend 0.
          expect([n(attendu['opening_balance']), n(attendu['closing_balance'])], [0.0, 0.0], reason: raison);
          continue;
        }
        expect(g.soldeOuverture, n(attendu['opening_balance']), reason: raison);
        expect(g.soldeFinal, n(attendu['closing_balance']), reason: raison);
        expect([g.totalDebit, g.totalCredit], [n(attendu['total_debit']), n(attendu['total_credit'])], reason: raison);
        expect(
          [for (final m in g.mouvements) [m.piece, m.soldeProgressif]],
          [for (final l in attendu['lines'] as List) [l['reference'], n(l['running_balance'])]],
          reason: raison,
        );
        expect(g.ouverture?.provisoire, (attendu['ouverture'] as Map)['provisoire'], reason: raison);
      }
    }

    // État de trésorerie (Rapports).
    final tresoreries = photo['tresorerie'] as List;
    final ecrituresPoste = await db.select(db.accountingEntries).get();
    final lignesPoste = await db.select(db.accountingEntryLines).get();
    final planPoste = await db.select(db.chartOfAccounts).get();
    final exercicesPoste = await db.select(db.fiscalYears).get();
    for (var i = 0; i < periodesTresorerie.length; i++) {
      final p = periodesTresorerie[i];
      final soldes = RapportsRepository.soldesTresorerie(
        ecritures: ecrituresPoste,
        lignes: lignesPoste,
        comptes: planPoste,
        du: DateTime.parse(p[0]),
        au: DateTime.parse(p[1]),
        exercices: exercicesPoste,
      );
      expect(
        [for (final s in soldes) [RapportsRepository.date(s.date), s.caisse, s.banque, s.total]],
        [
          for (final r in tresoreries[i] as List)
            [r['date'], n(r['caisse']), n(r['banque']), n(r['total'])],
        ],
        reason: '$phase — trésorerie ${p[0]} → ${p[1]}',
      );
    }

    // Contrôle S-T6 « ouverture N+1 = clôture N ».
    expect(
      [
        for (final c in d.soldesExercice.controleAnouveaux())
          [c.exercice, c.precedent, c.statutPrecedent, [for (final e in c.ecarts) [e.code, e.cloture, e.ouverture]]],
      ],
      [
        for (final c in photo['controle'] as List)
          [
            c['exercice'], c['precedent'], c['statut_precedent'],
            [for (final e in c['ecarts'] as List) [e['code'], n(e['cloture']), n(e['ouverture'])]],
          ],
      ],
      reason: '$phase — contrôle des à-nouveaux',
    );
  }

  test(
    'parité exécutée EX1/EX2 — avant la clôture de 2026 (à-nouveaux provisoires) : Balance, Grand Livre, trésorerie',
    () => comparer('provisoire'),
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'parité exécutée EX1/EX2 — après la clôture de 2026 (à-nouveau écrit) : mêmes chiffres qu avant',
    () async {
      await comparer('definitif');
      // Rien ne bouge : la Balance 2027 et la trésorerie sont identiques avant et après.
      final avant = serveur!['provisoire'] as Map<String, dynamic>;
      final apres = serveur!['definitif'] as Map<String, dynamic>;
      for (var i = 2; i < periodesBalance.length; i++) {
        for (final cle in ['total_final_debit', 'total_final_credit', 'total_opening_debit']) {
          expect((apres['balances'] as List)[i][cle], (avant['balances'] as List)[i][cle], reason: '$i $cle');
        }
      }
      expect(apres['tresorerie'], avant['tresorerie']);
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'EX1 — les chiffres du § 5, calculés à la main, au poste : avant et après la clôture',
    () async {
      for (final phase in ['provisoire', 'definitif']) {
        final photo = serveur![phase] as Map<String, dynamic>;
        // Le jeu du § 5 seul (sans les écritures pseudo-aléatoires ni la dotation) : rendu à part par le PHP.
        final db = await basePoste(photo['exemple'] as Map<String, dynamic>);
        final d = await ComptabiliteRepository(database: db).charger();
        final b = d.balanceGenerale(debut: DateTime(2027, 1, 1), fin: DateTime(2027, 1, 31));
        final parCode = {for (final l in b.lignes) l.code: l};
        expect(parCode['531']!.ouvertureDebit, 200000, reason: phase);
        expect(parCode['531']!.mouvementsDebit, 50000, reason: '$phase : l à-nouveau n est pas un mouvement');
        expect(parCode['531']!.finalDebit, 250000, reason: phase);
        expect(parCode['521101']!.finalDebit, 1000000, reason: phase);
        expect(parCode['101']!.finalCredit, 1000000, reason: phase);
        expect(parCode['131']!.finalCredit, 200000, reason: phase);
        expect(parCode['131']!.provisoire, phase == 'provisoire');
        expect(parCode['701']!.finalCredit, 50000, reason: '$phase : la classe 7 repart de zéro');
        expect([b.totalFinalDebit, b.totalFinalCredit], [1250000, 1250000], reason: phase);
        final plan = {for (final c in d.comptes) c.code: c.id};
        final caisse = d.grandLivreCompte(plan['531']!, debut: DateTime(2027, 1, 1), fin: DateTime(2027, 1, 31));
        expect([caisse.soldeOuverture, caisse.soldeFinal, caisse.mouvements.length], [200000, 250000, 1]);
        await db.close();
      }
    },
    skip: sautSansPhp(),
  );

  test(
    'EX2 — la mention « À-nouveaux provisoires » du poste est celle du composant web, mot pour mot (rendue par le PHP)',
    () {
      expect(serveur!['mention'], [
        MentionAnouveauxProvisoires.titre,
        MentionAnouveauxProvisoires.explication(precedent: 2026, annee: 2027),
      ]);
      expect(SoldesExercice.libelleResultatProvisoire(2026), serveur!['libelle_provisoire']);
      // Le suffixe des documents PDF, écrit dans les exports du web.
      for (final f in ['BalanceGenerale.php', 'GrandLivre.php']) {
        expect(
          File('$dossierLaravel/app/Livewire/Comptabilite/$f').readAsStringSync(),
          contains("'${MentionAnouveauxProvisoires.suffixeDocument}'"),
          reason: f,
        );
      }
    },
    skip: sautSansPhp(),
  );

  testWidgets(
    'EX2 — l écran Balance du poste : mention et ligne « Résultat de l exercice 2026 (provisoire) » tant que 2026 est ouvert, plus après',
    (tester) async {
      tester.view.physicalSize = const Size(1700, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final phase in ['provisoire', 'definitif']) {
        final photo = serveur![phase] as Map<String, dynamic>;
        final db = await basePoste(photo['exemple'] as Map<String, dynamic>);
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(phase),
            home: ComptabiliteScreen(
              depot: ComptabiliteRepository(database: db),
              maintenant: () => DateTime(2027, 1, 20),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('carte-balance')));
        await tester.pumpAndSettle();

        final provisoire = phase == 'provisoire';
        expect(find.text('Janvier 2027 (période courante)'), findsOneWidget);
        expect(find.byKey(const Key('anouveaux-provisoires')), provisoire ? findsOneWidget : findsNothing, reason: phase);
        expect(find.text(MentionAnouveauxProvisoires.titre), provisoire ? findsOneWidget : findsNothing, reason: phase);
        expect(
          find.text(MentionAnouveauxProvisoires.explication(precedent: 2026, annee: 2027)),
          provisoire ? findsOneWidget : findsNothing,
        );
        expect(
          find.text("Résultat de l'exercice 2026 (provisoire)"),
          provisoire ? findsOneWidget : findsNothing,
          reason: phase,
        );
        await tester.pumpWidget(const SizedBox());
        await db.close();
      }
    },
    skip: sautSansPhp() != null,
  );

  test(
    'EX1 — contrôle de cohérence S-T6 : « anouveaux » du serveur lu au poste, et le même calcul sur la base du poste',
    () async {
      expect(ControleCoherenceRepository.lireAnouveaux({'tables': const {}}), isNull, reason: 'non servi');
      expect(ControleCoherenceRepository.lireAnouveaux({'anouveaux': null}), isNull);

      final photo = serveur!['definitif'] as Map<String, dynamic>;
      // Un à-nouveau altéré (caisse 180 000 au lieu de la clôture), comme dans `BasculeExerciceEtatsTest`.
      final lu = ControleCoherenceRepository.lireAnouveaux({
        'anouveaux': [
          {
            'exercice': 2027,
            'precedent': 2026,
            'statut_precedent': 'cloture',
            'ecarts': [
              {'code': '531', 'libelle': 'Caisse', 'cloture': 200000, 'ouverture': 180000.0},
            ],
          },
        ],
      })!;
      expect(lu.single.ecarts.single.cloture, 200000.0);
      expect(lu.single.ecarts.single.ouverture, 180000.0);

      final db = await basePoste(photo);
      addTearDown(db.close);
      final local = await ControleCoherenceRepository(
        database: db,
        serveur: (_) async => {'tables': const {}, 'anouveaux': photo['controle']},
      ).anouveauxLocaux();
      expect(local.single.exercice, 2027);
      expect(local.single.ecarts, isEmpty, reason: 'à-nouveau écrit = clôture calculée');

      // L'à-nouveau de la caisse altéré au poste : l'écart se voit, au centime.
      final ran = (photo['journal'] as List).firstWhere((e) => e['source_type'] == 'ran');
      final caisse = (photo['plan'] as List).firstWhere((c) => c['code'] == '531')['id'];
      final ligne = (ran['lines'] as List).firstWhere((l) => l['account_id'] == caisse);
      await (db.update(db.accountingEntryLines)..where((l) => l.id.equals(ligne['id'] as String)))
          .write(AccountingEntryLinesCompanion(debit: Value(n(ligne['debit']) - 20000)));
      final altere = await ControleCoherenceRepository(
        database: db,
        serveur: (_) async => const {},
      ).anouveauxLocaux();
      expect(
        [for (final e in altere.single.ecarts) [e.code, e.cloture - e.ouverture]],
        [['531', 20000.0]],
      );
    },
    skip: sautSansPhp(),
  );

  test('EX2 — la mention ne s affiche que pour une ouverture provisoire', () {
    const provisoire = OuvertureExercice(
      annee: 2027,
      mode: 'provisoire',
      precedent: 2026,
      comptes: {},
      resultatProvisoire: null,
    );
    const definitive = OuvertureExercice(
      annee: 2027,
      mode: 'anouveau',
      precedent: 2026,
      comptes: {},
      resultatProvisoire: null,
    );
    expect(provisoire.provisoire, isTrue);
    expect(definitive.provisoire, isFalse);
  });
}

/// Construit l'exemple du § 5 (et, à part, le jeu complet) dans Laravel (SQLite en mémoire), par
/// `AccountingEntryService::record()` ; rend journal et états AVANT puis APRÈS la clôture de 2026 par le vrai
/// assistant (étapes 1, 2, 3 le 15/03/2027).
const _script = r'''
$entree = json_decode(file_get_contents($argv[1]), true);
use App\Models\{AccountingEntry, ChartOfAccount, FiscalYear, User};
use App\Services\{AccountingEntryService, FinancialReportService};
use Illuminate\Support\Facades\Artisan;

Artisan::call('db:seed', ['--class' => Database\Seeders\RolesAndPermissionsSeeder::class, '--force' => true]);
$comptable = User::create(['name' => 'Comptable', 'username' => 'compta', 'email' => 'compta@fermeolouwachegoun.com',
    'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
$comptable->assignRole('comptable');
Illuminate\Support\Facades\Auth::login($comptable);

function construire(array $ecritures, bool $dotation): array {
    foreach (AccountingEntry::all() as $e) { $e->lines()->delete(); $e->delete(); }
    ChartOfAccount::query()->delete();
    FiscalYear::query()->delete();
    Carbon\Carbon::setTestNow('2027-02-20 09:00:00');
    $ex2026 = FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
    FiscalYear::create(['year' => 2027, 'start_date' => '2027-01-01', 'end_date' => '2027-12-31', 'status' => 'ouvert']);
    $plan = [];
    foreach ([['101', 'Capital social', 1], ['131', 'Résultat net : bénéfice', 1], ['139', 'Résultat net : perte', 1],
              ['2841', 'Amortissements du matériel', 2], ['401', 'Fournisseurs', 4], ['411', 'Clients', 4],
              ['521101', 'Banque principale', 5], ['531', 'Caisse', 5], ['601', 'Achats', 6],
              ['605', 'Autres achats (énergie)', 6], ['681', 'Dotations aux amortissements', 6],
              ['701', 'Ventes de produits', 7]] as [$code, $libelle, $classe]) {
        $plan[$code] = ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true])->id;
    }
    $ecrire = function (string $date, string $d, string $c, float $m, string $libelle) use ($plan) {
        app(AccountingEntryService::class)->record(
            lines: [['account_id' => $plan[$d], 'debit' => $m, 'credit' => 0], ['account_id' => $plan[$c], 'debit' => 0, 'credit' => $m]],
            entryDate: $date, reference: 'OD-'.$date.' — '.$libelle, sourceType: 'manual');
    };
    foreach ($ecritures as $i => $e) {
        Carbon\Carbon::setTestNow(Carbon\Carbon::parse('2027-02-20 09:00:00')->addSeconds($i));
        $ecrire($e['date'], $e['debit'], $e['credit'], (float) $e['montant'], $e['libelle']);
    }
    if ($dotation) {
        Carbon\Carbon::setTestNow('2027-02-20 10:00:00');
        $ecrire('2026-12-31', '681', '2841', 30000, 'Dotation 2026');
    }
    return $plan;
}

function photo(array $entree, bool $complet): array {
    $s = new FinancialReportService();
    $p = [
        'exercices' => FiscalYear::orderBy('year')->get()->map(fn ($f) => ['id' => $f->id, 'year' => (int) $f->year,
            'start_date' => $f->start_date->format('Y-m-d'), 'end_date' => $f->end_date->format('Y-m-d'), 'status' => $f->status])->all(),
        'plan' => ChartOfAccount::orderBy('code')->get()->map(fn ($c) => ['id' => $c->id, 'code' => $c->code, 'label' => $c->label, 'class' => (int) $c->class])->all(),
        'journal' => AccountingEntry::with('lines')->where('is_active', true)->get()->map(fn ($e) => [
            'id' => $e->id, 'fiscal_year_id' => $e->fiscal_year_id, 'entry_date' => $e->entry_date->format('Y-m-d'),
            'reference' => $e->reference, 'source_type' => $e->source_type, 'is_locked' => (bool) $e->is_locked,
            'created_at' => $e->created_at->toIso8601String(),
            'lines' => $e->lines->map(fn ($l) => ['id' => $l->id, 'account_id' => $l->account_id, 'debit' => (float) $l->debit, 'credit' => (float) $l->credit])->all(),
        ])->all(),
    ];
    if (! $complet) {
        return $p;
    }
    $p['balances'] = array_map(fn ($b) => (new FinancialReportService())->balanceGenerale($b[0], $b[1]), $entree['balances']);
    $p['grands_livres'] = [];
    foreach ($entree['comptes_gl'] as $code) {
        $id = ChartOfAccount::where('code', $code)->value('id');
        foreach ($entree['periodes_gl'] as [$du, $au]) {
            $g = (new FinancialReportService())->grandLivre($id, $du, $au);
            unset($g['account']);
            $p['grands_livres']["$code|$du|$au"] = $g;
        }
    }
    $p['tresorerie'] = array_map(function ($t) {
        $r = new App\Livewire\Rapports\Tresorerie();
        $r->startDate = $t[0];
        $r->endDate = $t[1];
        return array_map(fn ($l) => ['date' => Carbon\Carbon::parse($l['date'])->format('d/m/Y'), 'caisse' => $l['caisse'],
            'banque' => $l['banque'], 'total' => $l['total']], $r->getRowsProperty());
    }, $entree['tresorerie']);
    $p['controle'] = $s->controleAnouveaux();
    return $p;
}

function cloturer2026(): void {
    Carbon\Carbon::setTestNow('2027-03-15 10:00:00');
    Livewire\Livewire::test(App\Livewire\Comptabilite\ClotureExercice::class)
        ->set('selectedYear', '2026')->call('confirmStep1')->call('soldeComptesGestion')->call('confirmCloture');
    if (FiscalYear::where('year', 2026)->value('status') !== 'cloture') {
        fwrite(STDERR, 'La clôture de 2026 n a pas abouti.');
        exit(4);
    }
}

$sortie = [];
// L'exemple du § 5 seul.
construire(array_slice($entree['ecritures'], 0, 4), false);
$exempleAvant = photo($entree, false);
cloturer2026();
$exempleApres = photo($entree, false);

// Le jeu complet.
construire($entree['ecritures'], true);
$sortie['provisoire'] = photo($entree, true) + ['exemple' => $exempleAvant];
cloturer2026();
$sortie['definitif'] = photo($entree, true) + ['exemple' => $exempleApres];

// La mention, RENDUE par le composant Blade.
$html = Illuminate\Support\Facades\Blade::render('<x-anouveaux-provisoires :ouverture="$o" />',
    ['o' => ['provisoire' => true, 'annee' => 2027, 'precedent' => 2026, 'mode' => 'provisoire']]);
$doc = new DOMDocument();
@$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
$sortie['mention'] = array_map(fn ($p) => trim(preg_replace('/\s+/u', ' ', $p->textContent)),
    iterator_to_array($doc->getElementsByTagName('p')));
$sortie['libelle_provisoire'] = FinancialReportService::libelleResultatProvisoire(2026);
echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION);
''';
