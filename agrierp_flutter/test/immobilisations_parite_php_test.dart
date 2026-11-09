import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/comptabilite/immobilisations_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket CP-3 — PARITÉ EXÉCUTÉE : le VRAI `App\Models\FixedAsset` du serveur et `CalculAmortissement` du poste reçoivent les
/// mêmes biens et les mêmes dates d'arrêté, et doivent rendre la même base, la même annuité, le même cumul et le même état
/// « amorti », au centime.
///
/// ⚠️ Le web appelle `Carbon::diffInMonths`, qui rend depuis Carbon 3 un nombre de mois À VIRGULE (voir
/// `CalculAmortissement`). Les cas visent les fins de mois (31/01 → 28/02, 30/01 → 01/03…), les années bissextiles, les dates
/// d'arrêté avant l'acquisition, les sorties en cours de période et les biens totalement amortis : c'est là que la
/// transposition d'un calcul de dates se trompe sans bruit.
const _script = r'''<?php
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
$sortie = [];
foreach ($in as $c) {
    $b = new App\Models\FixedAsset();
    $b->forceFill([
        'acquisition_date' => $c['acquisition'], 'acquisition_value' => $c['valeur'], 'residual_value' => $c['residuelle'],
        'duration_years' => $c['duree'], 'disposal_date' => $c['sortie'],
    ]);
    $sortie[] = [
        'base' => $b->baseAmortissable(), 'annuite' => $b->annuite(),
        'cumul' => $b->cumulAmortissement($c['arrete']), 'vnc' => $b->valeurNette($c['arrete']),
        'amorti' => $b->estTotalementAmorti($c['arrete']),
    ];
}
echo json_encode($sortie);
''';

String _jour(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

FixedAsset _bien(Map<String, Object?> c) => FixedAsset(
  id: 'x', deviceId: 'x', syncStatus: SyncStatus.synced, updatedAt: DateTime(2026),
  code: 'X', label: 'X', accountCode: '244',
  acquisitionDate: DateTime.parse(c['acquisition'] as String),
  acquisitionValue: (c['valeur'] as num).toDouble(),
  residualValue: (c['residuelle'] as num).toDouble(),
  durationYears: c['duree'] as int,
  status: 'en_service',
  disposalDate: c['sortie'] == null ? null : DateTime.parse(c['sortie'] as String),
  disposalReason: null, isCapitalized: true, isActive: true, counterpart: null,
);

void main() {
  final saut = sautSansPhp();
  final alea = Random(2026);

  DateTime auHasard(int de, int a) => DateTime(de + alea.nextInt(a - de + 1), 1 + alea.nextInt(12), 1 + alea.nextInt(31));
  // Les jours inexistants (31/04…) débordent : on les écarte en retombant sur le dernier jour du mois.
  DateTime valide(DateTime d) => DateTime(d.year, d.month, min(d.day, DateTime(d.year, d.month + 1, 0).day));

  final cas = <Map<String, Object?>>[
    // Un an plein, six mois pleins : l'exemple du test web (620 000 sur 5 ans).
    {'acquisition': '2025-10-28', 'valeur': 620000, 'residuelle': 0, 'duree': 5, 'sortie': null, 'arrete': '2026-10-28'},
    {'acquisition': '2025-10-28', 'valeur': 620000, 'residuelle': 0, 'duree': 5, 'sortie': null, 'arrete': '2026-04-28'},
    // Fins de mois : 31/01 → 28/02 = 0,903 mois ; 30/01 → 01/03 ; année bissextile.
    {'acquisition': '2026-01-31', 'valeur': 1200000, 'residuelle': 0, 'duree': 5, 'sortie': null, 'arrete': '2026-02-28'},
    {'acquisition': '2026-01-30', 'valeur': 1200000, 'residuelle': 0, 'duree': 5, 'sortie': null, 'arrete': '2026-03-01'},
    {'acquisition': '2024-01-31', 'valeur': 1200000, 'residuelle': 100000, 'duree': 4, 'sortie': null, 'arrete': '2024-02-29'},
    {'acquisition': '2024-02-29', 'valeur': 900000, 'residuelle': 0, 'duree': 3, 'sortie': null, 'arrete': '2025-02-28'},
    // Arrêté avant l'acquisition, le jour même, le lendemain.
    {'acquisition': '2026-06-15', 'valeur': 500000, 'residuelle': 0, 'duree': 5, 'sortie': null, 'arrete': '2026-06-14'},
    {'acquisition': '2026-06-15', 'valeur': 500000, 'residuelle': 0, 'duree': 5, 'sortie': null, 'arrete': '2026-06-15'},
    {'acquisition': '2026-06-15', 'valeur': 500000, 'residuelle': 0, 'duree': 5, 'sortie': null, 'arrete': '2026-06-16'},
    // Sortie en cours de période, sortie avant l'arrêté, sortie après l'arrêté.
    {'acquisition': '2025-01-10', 'valeur': 800000, 'residuelle': 50000, 'duree': 5, 'sortie': '2026-03-20', 'arrete': '2026-10-28'},
    {'acquisition': '2025-01-10', 'valeur': 800000, 'residuelle': 50000, 'duree': 5, 'sortie': '2026-12-31', 'arrete': '2026-10-28'},
    // Totalement amorti (plafonné à la base), durée d'un an.
    {'acquisition': '2018-03-05', 'valeur': 300000, 'residuelle': 30000, 'duree': 2, 'sortie': null, 'arrete': '2026-10-28'},
    {'acquisition': '2025-11-30', 'valeur': 100000, 'residuelle': 0, 'duree': 1, 'sortie': null, 'arrete': '2026-11-30'},
    // Centimes, durée longue.
    {'acquisition': '2023-07-31', 'valeur': 1234567.89, 'residuelle': 1234.56, 'duree': 17, 'sortie': null, 'arrete': '2026-10-28'},
    // Quatre-vingts cas au hasard, jours de fin de mois inclus.
    for (var i = 0; i < 80; i++)
      () {
        final acq = valide(auHasard(2019, 2026));
        final arr = valide(auHasard(2019, 2028));
        final sortie = alea.nextInt(4) == 0 ? valide(auHasard(2019, 2028)) : null;
        final valeur = (alea.nextInt(9000000) + 10000) + (alea.nextBool() ? alea.nextInt(100) / 100 : 0);
        return <String, Object?>{
          'acquisition': _jour(acq),
          'valeur': valeur,
          'residuelle': alea.nextBool() ? 0 : (valeur * alea.nextDouble() * 0.5).roundToDouble(),
          'duree': 1 + alea.nextInt(20),
          'sortie': sortie == null ? null : _jour(sortie),
          'arrete': _jour(arr),
        };
      }(),
  ];

  List<Map<String, Object>> local() {
    final sortie = <Map<String, Object>>[];
    for (final c in cas) {
      final b = _bien(c);
      final arrete = DateTime.parse(c['arrete'] as String);
      sortie.add({
        'base': CalculAmortissement.base(b),
        'annuite': CalculAmortissement.annuite(b),
        'cumul': CalculAmortissement.cumul(b, arrete),
        'vnc': CalculAmortissement.valeurNette(b, arrete),
        'amorti': CalculAmortissement.totalementAmorti(b, arrete),
      });
    }
    return sortie;
  }

  test('Carbon 3 : 31/01 → 28/02 vaut 0,903 mois, pas 1 (arithmétique du web)', () {
    expect(CalculAmortissement.moisEntre(DateTime(2026, 1, 31), DateTime(2026, 2, 28)), closeTo(28 / 31, 1e-9));
    expect(CalculAmortissement.moisEntre(DateTime(2026, 1, 31), DateTime(2026, 3, 31)), 2);
    expect(CalculAmortissement.moisEntre(DateTime(2026, 6, 15), DateTime(2026, 6, 15)), 0);
  });

  test('⚠️⚠️ mêmes montants au centime : le modèle du serveur et le poste, sur ${cas.length} cas', () {
    final attendu = (executerPhp(_script, cas, application: true) as List).cast<Map>();
    final obtenu = local();

    expect(attendu, hasLength(cas.length));
    for (var i = 0; i < cas.length; i++) {
      for (final cle in obtenu[i].keys) {
        final a = attendu[i][cle];
        final o = obtenu[i][cle];
        if (o is bool) {
          expect(a, o, reason: 'cas $i ($cle) : ${cas[i]}');
        } else {
          expect((a as num).toDouble(), closeTo(o as double, 0.005), reason: 'cas $i ($cle) : ${cas[i]}');
        }
      }
    }
  }, skip: saut);
}
