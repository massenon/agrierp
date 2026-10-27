import 'dart:math';

import 'package:agrierp/features/rh/calcul_paie.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket RH-4 — PARITÉ EXÉCUTÉE : le VRAI `App\Services\PayrollCalculationService` du serveur et `CalculPaie` du poste
/// reçoivent les mêmes brut, jours d'absence, barème et taux, et doivent rendre les mêmes montants (brut, retenues,
/// ITS, net, charges patronales), au centime. Un net « vu au poste » qui différerait du bulletin serait son salaire.
///
/// Rien n'est recopié : les cas sont une donnée JSON jouée des deux côtés (SQLite en mémoire côté PHP, barème et taux
/// insérés par le script). Sans PHP ni dépôt Laravel, le test est SAUTÉ AVEC SA RAISON.
const _script = r'''<?php
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
$svc = app(App\Services\PayrollCalculationService::class);
$sortie = [];
foreach ($in as $c) {
    App\Models\IncomeTaxBracket::query()->delete();
    foreach ($c['bareme'] as $t) {
        App\Models\IncomeTaxBracket::create(['from_amount' => $t['plancher'], 'to_amount' => $t['plafond'], 'rate' => $t['taux'], 'is_active' => true]);
    }
    App\Models\CompanySetting::query()->delete();
    if ($c['taux'] !== null) {
        App\Models\CompanySetting::create(['company_name' => 'Essai'] + $c['taux']);
    }
    $r = $svc->calculer((float) $c['brut'], (int) $c['absences']);
    $sortie[] = [
        'brut' => $r['brut'], 'retenue_absence' => $r['retenue_absence'], 'salaire_du' => $r['salaire_du'],
        'cnss_salariale' => $r['cnss_salariale'], 'net_imposable' => $r['net_imposable'], 'its' => $r['its'], 'net' => $r['net'],
        'vps' => $r['vps'], 'cnss_patronale_pension' => $r['cnss_patronale_pension'], 'cnss_patronale_famille' => $r['cnss_patronale_famille'],
        'cnss_patronale_risque' => $r['cnss_patronale_risque'], 'total_charges_patronales' => $r['total_charges_patronales'],
        'cout_employeur' => $r['cout_employeur'], 'bareme_its_renseigne' => $r['bareme_its_renseigne'],
    ];
}
echo json_encode($sortie);
''';

void main() {
  final saut = sautSansPhp();

  /// Le barème de l'exemple du PRD (§5) : 0–60 000 à 0 %, 60 000–150 000 à 10 %, au-delà 15 %.
  const baremePrd = [
    {'plancher': 0, 'plafond': 60000, 'taux': 0},
    {'plancher': 60000, 'plafond': 150000, 'taux': 10},
    {'plancher': 150000, 'plafond': null, 'taux': 15},
  ];
  const tauxServeur = {
    'cnss_employee_rate': 3.6, 'vps_rate': 4, 'cnss_employer_pension_rate': 6.4, 'cnss_employer_family_rate': 9, 'cnss_employer_risk_rate': 2,
  };

  final alea = Random(2026);
  final cas = <Map<String, Object?>>[
    // L'exemple calculé À LA MAIN du PRD : 120 000, 2 absences.
    {'brut': 120000, 'absences': 2, 'bareme': baremePrd, 'taux': tauxServeur},
    // Sans barème (ITS nul, dit), sans paramètres (défauts du web), brut nul, absences au-delà du mois.
    {'brut': 100000, 'absences': 0, 'bareme': <Object>[], 'taux': null},
    {'brut': 0, 'absences': 3, 'bareme': baremePrd, 'taux': tauxServeur},
    {'brut': 85000, 'absences': 30, 'bareme': baremePrd, 'taux': tauxServeur},
    // Taux modifiés par la ferme, centimes.
    {'brut': 137650.75, 'absences': 1, 'bareme': baremePrd, 'taux': {'cnss_employee_rate': 4.2, 'vps_rate': 2, 'cnss_employer_pension_rate': 6, 'cnss_employer_family_rate': 8.5, 'cnss_employer_risk_rate': 3.5}},
    // Vingt cas au hasard.
    for (var i = 0; i < 20; i++)
      {
        'brut': (alea.nextInt(400000) + alea.nextInt(100) / 100 * (alea.nextBool() ? 1 : 0)),
        'absences': alea.nextInt(8),
        'bareme': alea.nextInt(5) == 0 ? <Object>[] : baremePrd,
        'taux': alea.nextBool() ? tauxServeur : null,
      },
  ];

  List<Map<String, Object>> local() => [
    for (final c in cas)
      CalculPaie.calculer(
        (c['brut'] as num).toDouble(),
        c['absences'] as int,
        bareme: [
          for (final t in c['bareme'] as List)
            TrancheIts(
              plancher: ((t as Map)['plancher'] as num).toDouble(),
              plafond: (t['plafond'] as num?)?.toDouble(),
              taux: (t['taux'] as num).toDouble(),
            ),
        ],
        taux: c['taux'] == null
            ? TauxPaie.defaut
            : TauxPaie(
                cnssSalarie: ((c['taux'] as Map)['cnss_employee_rate'] as num).toDouble(),
                vps: ((c['taux'] as Map)['vps_rate'] as num).toDouble(),
                cnssPatronalePension: ((c['taux'] as Map)['cnss_employer_pension_rate'] as num).toDouble(),
                cnssPatronaleFamille: ((c['taux'] as Map)['cnss_employer_family_rate'] as num).toDouble(),
                cnssPatronaleRisque: ((c['taux'] as Map)['cnss_employer_risk_rate'] as num).toDouble(),
              ),
      ).versJson(),
  ];

  test("l'exemple du PRD, à la main : 120 000 brut, 2 absences", () {
    final p = local().first;
    expect(p['retenue_absence'], 9230.77);
    expect(p['salaire_du'], 110769.23);
    expect(p['cnss_salariale'], 3987.69);
    expect(p['net_imposable'], 106781.54);
    expect(p['its'], 4678.15);
    expect(p['net'], 102103.39);
    // Somme des quatre parts ARRONDIES, comme le PHP : 4 430,77 + 7 089,23 + 9 969,23 + 2 215,38.
    expect(p['total_charges_patronales'], 23704.61);
  });

  test('⚠️⚠️ mêmes montants au centime : le serveur et le poste, sur 25 cas', () {
    final attendu = (executerPhp(_script, cas, application: true) as List).cast<Map>();
    final obtenu = local();

    expect(attendu, hasLength(cas.length));
    for (var i = 0; i < cas.length; i++) {
      for (final cle in obtenu[i].keys) {
        final a = attendu[i][cle];
        final o = obtenu[i][cle];
        if (o is bool) {
          expect(a, o, reason: 'cas $i ($cle)');
        } else {
          expect((a as num).toDouble(), closeTo(o as double, 0.005), reason: 'cas $i : brut ${cas[i]['brut']}, ${cas[i]['absences']} absence(s) — $cle');
        }
      }
    }
  }, skip: saut);
}
