import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/comptabilite/cloture_exercice_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket CP-4 — PARITÉ EXÉCUTÉE : le VRAI `App\Services\ClotureExerciceService` (soldes de gestion, résultat, à-nouveau, motif de
/// refus de la clôture) et `OuvertureExerciceService::refusOuverture` du serveur reçoivent les mêmes journaux et les mêmes dates
/// que `CalculCloture` du poste, et doivent rendre les mêmes soldes, le même à-nouveau et les MÊMES MOTIFS, mot pour mot.
///
/// Rien n'est recopié : un message changé au web, une garde déplacée ou un seuil modifié fait rougir ce test.
const _comptes = [
  ('101', 1), ('131', 1), ('139', 1), ('211', 2), ('311', 3), ('411', 4), ('521', 5), ('531', 5),
  ('601', 6), ('605', 6), ('701', 7), ('707', 7), ('811', 8),
];

const _script = r'''<?php
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
use App\Models\ChartOfAccount;
use App\Models\FiscalYear;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

$ids = [];
$classes = [];
foreach ($in['comptes'] as [$code, $classe]) {
    $c = ChartOfAccount::firstOrCreate(['code' => $code], ['label' => "Compte $code", 'class' => $classe, 'is_active' => true]);
    $ids[$code] = $c->id;
    $classes[$code] = (int) $c->class;
}

$sortie = ['classes' => $classes, 'ouvertures' => [], 'clotures' => []];

foreach ($in['ouvertures'] as $o) {
    FiscalYear::query()->delete();
    foreach ($o['exercices'] as [$annee, $statut]) {
        FiscalYear::create(['year' => $annee, 'start_date' => "$annee-01-01", 'end_date' => "$annee-12-31", 'status' => $statut]);
    }
    $sortie['ouvertures'][] = app(App\Services\OuvertureExerciceService::class)->refusOuverture($o['annee'], App\Services\OuvertureExerciceService::BOUTON, Carbon::parse($o['maintenant'], 'Africa/Porto-Novo'));
}
FiscalYear::query()->delete();

$service = app(App\Services\ClotureExerciceService::class);
foreach ($in['clotures'] as $k => $c) {
    $annee = $c['annee'];
    if ($c['precedent'] !== null) {
        FiscalYear::create(['year' => $annee - 1, 'start_date' => ($annee - 1).'-01-01', 'end_date' => ($annee - 1).'-12-31', 'status' => $c['precedent']]);
    }
    $y = FiscalYear::create(['year' => $annee, 'start_date' => "$annee-01-01", 'end_date' => "$annee-12-31", 'status' => $c['statut'],
        'step1_confirmed_at' => $c['etape1'] ? "$annee-12-20 10:00:00" : null]);
    foreach ($c['ecritures'] as $e) {
        $eid = (string) Str::uuid();
        DB::table('accounting_entries')->insert(['id' => $eid, 'fiscal_year_id' => $y->id, 'entry_date' => "$annee-06-15", 'is_active' => true, 'created_at' => now(), 'updated_at' => now()]);
        foreach ($e as [$code, $debit, $credit]) {
            DB::table('accounting_entry_lines')->insert(['id' => (string) Str::uuid(), 'entry_id' => $eid, 'account_id' => $ids[$code], 'debit' => $debit, 'credit' => $credit, 'created_at' => now(), 'updated_at' => now()]);
        }
    }
    Carbon::setTestNow(Carbon::parse($c['maintenant'], 'Africa/Porto-Novo'));
    $y = $y->fresh();
    $inv = array_flip($ids);
    $gestion = array_map(fn ($b) => [(string) $inv[$b['account_id']], $b['class'], $b['balance']], $service->soldesDeGestion($y));
    usort($gestion, fn ($a, $b) => strcmp($a[0], $b[0]));
    $an = array_map(fn ($l) => [(string) $inv[$l['account_id']], $l['debit'], $l['credit']], $service->lignesDAnouveau($y));
    usort($an, fn ($a, $b) => strcmp($a[0], $b[0]));
    $ind = $service->indicateurs($y);
    $sortie['clotures'][] = ['gestion' => $gestion, 'anouveau' => $an, 'resultat' => $ind['resultat'], 'a_solder' => $ind['comptes_a_solder'], 'motif' => $service->motifRefusCloture($y)];
    Carbon::setTestNow();
}
echo json_encode($sortie);
''';

String _jour(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  final saut = sautSansPhp();
  final alea = Random(2610);

  double montant() => (alea.nextInt(900000) + 1000) + (alea.nextInt(4) == 0 ? alea.nextInt(100) / 100 : 0);

  // ── Ouvertures par le bouton ──
  final ouvertures = <Map<String, Object?>>[
    {'exercices': [[2026, 'ouvert']], 'annee': 2027, 'maintenant': '2026-11-30 23:59:59'},
    {'exercices': [[2026, 'ouvert']], 'annee': 2027, 'maintenant': '2026-12-01 00:00:00'},
    {'exercices': [[2026, 'ouvert']], 'annee': 2027, 'maintenant': '2027-03-01 08:00:00'},
    {'exercices': [[2026, 'ouvert'], [2027, 'ouvert']], 'annee': 2028, 'maintenant': '2027-12-05 08:00:00'},
    {'exercices': [[2026, 'cloture'], [2027, 'ouvert']], 'annee': 2028, 'maintenant': '2027-12-05 08:00:00'},
    {'exercices': [[2026, 'ouvert'], [2027, 'ouvert']], 'annee': 2027, 'maintenant': '2027-12-05 08:00:00'},
    {'exercices': [[2026, 'ouvert']], 'annee': 2029, 'maintenant': '2028-12-05 08:00:00'},
    {'exercices': [<Object>[]], 'annee': 2027, 'maintenant': '2027-01-01 00:00:00'},
  ];
  ouvertures[7]['exercices'] = <List<Object>>[];

  // ── Clôtures ──
  final clotures = <Map<String, Object?>>[];
  for (var k = 0; k < 70; k++) {
    final annee = 2100 + 3 * k;
    final ecritures = <List<List<Object>>>[];
    for (var n = 0; n < alea.nextInt(8); n++) {
      final m = montant();
      final a = _comptes[alea.nextInt(_comptes.length)].$1;
      final b = _comptes[alea.nextInt(_comptes.length)].$1;
      // Une pièce sur cinq est déséquilibrée : les soldes comparés ne doivent pas en dépendre.
      ecritures.add([
        [a, m, 0.0],
        [b, 0.0, alea.nextInt(5) == 0 ? m + 1 : m],
      ]);
    }
    final avant = alea.nextInt(3) == 0;
    clotures.add({
      'annee': annee,
      'precedent': alea.nextInt(3) == 0 ? (alea.nextBool() ? 'ouvert' : 'cloture') : null,
      'statut': alea.nextInt(8) == 0 ? 'cloture' : 'ouvert',
      'etape1': alea.nextBool(),
      'maintenant': avant ? '$annee-${1 + alea.nextInt(12)}-${1 + alea.nextInt(28)} 10:00:00' : '${annee + 1}-0${1 + alea.nextInt(9)}-1${alea.nextInt(9)} 10:00:00',
      'ecritures': ecritures,
    });
  }
  // Cas visés : le dernier jour (23:59:59), le lendemain, l'à-nouveau équilibré après solde.
  clotures.addAll([
    {'annee': 2400, 'precedent': null, 'statut': 'ouvert', 'etape1': true, 'maintenant': '2400-12-31 23:59:59', 'ecritures': []},
    {'annee': 2403, 'precedent': null, 'statut': 'ouvert', 'etape1': true, 'maintenant': '2404-01-01 00:00:00', 'ecritures': []},
    {
      'annee': 2406, 'precedent': null, 'statut': 'ouvert', 'etape1': true, 'maintenant': '2407-02-10 09:00:00',
      'ecritures': [
        [['531', 1000000.0, 0.0], ['101', 0.0, 1000000.0]],
        [['811', 50000.0, 0.0], ['101', 0.0, 50000.0]],
      ],
    },
    {
      'annee': 2409, 'precedent': null, 'statut': 'ouvert', 'etape1': true, 'maintenant': '2410-02-10 09:00:00',
      'ecritures': [
        [['531', 1000000.0, 0.0], ['101', 0.0, 1000000.0]],
      ],
    },
  ]);

  final entree = {'comptes': [for (final (c, k) in _comptes) [c, k]], 'ouvertures': ouvertures, 'clotures': clotures};

  String uuid(String code) => 'c$code'.padRight(36, '0').substring(0, 36);

  test('⚠️⚠️ mêmes soldes, même à-nouveau, mêmes motifs au mot près : ClotureExerciceService du serveur et CalculCloture du poste', () async {
    final php = executerPhp(_script, entree, application: true) as Map<String, dynamic>;
    final classes = (php['classes'] as Map).map((k, v) => MapEntry(k as String, v as int));

    // Le plan du poste : les mêmes comptes, la même classe que le serveur (le plan importé du web en porte déjà certains).
    final comptes = [
      for (final MapEntry(:key, :value) in classes.entries)
        ChartOfAccount(id: uuid(key), deviceId: 'x', syncStatus: SyncStatus.synced, updatedAt: DateTime(2026), code: key, label: key, accountClass: value, isActive: true),
    ];
    final codeDe = {for (final c in comptes) c.id: c.code};

    // ── ouvertures ──
    final attenduO = (php['ouvertures'] as List);
    for (var i = 0; i < ouvertures.length; i++) {
      final o = ouvertures[i];
      final exercices = [
        for (final e in (o['exercices'] as List))
          FiscalYear(id: 'y${e[0]}', year: e[0] as int, startDate: DateTime(e[0] as int), endDate: DateTime(e[0] as int, 12, 31), status: e[1] as String, step1ConfirmedAt: null, closedAt: null),
      ];
      final maintenant = DateTime.parse((o['maintenant'] as String).replaceFirst(' ', 'T'));
      expect(
        CalculCloture.refusOuvertureParBouton(o['annee'] as int, maintenant: maintenant, exercices: exercices),
        attenduO[i],
        reason: 'ouverture $i : $o',
      );
    }

    // ── clôtures ──
    final attendu = (php['clotures'] as List);
    for (var k = 0; k < clotures.length; k++) {
      final c = clotures[k];
      final annee = c['annee'] as int;
      final exercice = FiscalYear(
        id: 'ex$annee', year: annee, startDate: DateTime(annee), endDate: DateTime(annee, 12, 31), status: c['statut'] as String,
        step1ConfirmedAt: c['etape1'] == true ? DateTime(annee, 12, 20, 10) : null, closedAt: null,
      );
      final exercices = [
        exercice,
        if (c['precedent'] != null) FiscalYear(id: 'ex${annee - 1}', year: annee - 1, startDate: DateTime(annee - 1), endDate: DateTime(annee - 1, 12, 31), status: c['precedent'] as String, step1ConfirmedAt: null, closedAt: null),
      ];
      final ecritures = <AccountingEntry>[];
      final lignes = <AccountingEntryLine>[];
      var n = 0;
      for (final e in (c['ecritures'] as List)) {
        final id = 'e$k-${n++}';
        ecritures.add(AccountingEntry(id: id, fiscalYearId: exercice.id, entryDate: DateTime(annee, 6, 15), reference: null, sourceType: null, isLocked: false, createdAt: null));
        for (final l in (e as List)) {
          lignes.add(AccountingEntryLine(id: '$id-${lignes.length}', entryId: id, accountId: uuid(l[0] as String), costCenterId: null, debit: (l[1] as num).toDouble(), credit: (l[2] as num).toDouble()));
        }
      }
      final maintenant = DateTime.parse((c['maintenant'] as String).replaceFirst(' ', 'T').replaceAllMapped(RegExp(r'-(\d)(?=-|T)'), (m) => '-0${m[1]}'));

      final gestion = CalculCloture.soldesDeGestion(exercice, ecritures: ecritures, lignes: lignes, comptes: comptes)
        ..sort((a, b) => codeDe[a.compteId]!.compareTo(codeDe[b.compteId]!));
      final anouveau = CalculCloture.lignesDAnouveau(exercice, ecritures: ecritures, lignes: lignes, comptes: comptes)
        ..sort((a, b) => codeDe[a.compteId]!.compareTo(codeDe[b.compteId]!));
      final ind = CalculCloture.indicateurs(gestion);
      final motif = CalculCloture.motifRefusCloture(
        exercice, maintenant: maintenant, exercices: exercices, ecritures: ecritures, lignes: lignes, comptes: comptes,
      );

      final a = attendu[k] as Map<String, dynamic>;
      final contexte = 'cas $k ($annee, ${c['maintenant']}, ${c['statut']}, précédent ${c['precedent']}, étape 1 ${c['etape1']})';
      expect([for (final s in gestion) [codeDe[s.compteId], s.classe, s.solde]], [for (final g in a['gestion'] as List) [g[0], g[1], (g[2] as num).toDouble()]], reason: 'gestion, $contexte');
      expect([for (final l in anouveau) [codeDe[l.compteId], l.debit, l.credit]], [for (final l in a['anouveau'] as List) [l[0], (l[1] as num).toDouble(), (l[2] as num).toDouble()]], reason: 'à-nouveau, $contexte');
      expect(ind.resultat, closeTo((a['resultat'] as num).toDouble(), 0.005), reason: 'résultat, $contexte');
      expect(ind.comptesASolder, a['a_solder'], reason: 'comptes à solder, $contexte');
      expect(motif, a['motif'], reason: 'motif, $contexte');
    }
  }, skip: saut);

  test('PHP et Dart écrivent un flottant de la même façon dans « écart de … FCFA »', () {
    expect(CalculCloture.flottantPhp(500), '500');
    expect(CalculCloture.flottantPhp(0.4), '0.4');
    expect(CalculCloture.flottantPhp(1234.5), '1234.5');
    expect(CalculCloture.flottantPhp(-0.001), '0');
    expect(_jour(DateTime(2026, 3, 4)), '2026-03-04');
  });
}
