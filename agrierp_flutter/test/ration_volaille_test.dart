import 'dart:io';
import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/categorie_volaille.dart';
import 'package:agrierp/features/elevage/stade_pondeuse.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket 15.57 → VOL-1 → VOL-2 — LE RATIONNEMENT DES FICHES AVICOLES EST LE MÊME AU WEB ET AU POSTE. Depuis VOL-2, la fiche
/// Pondeuses calcule son rationnement PAR STADE (`App\Support\StadePondeuse::tableau` : effectif calculé × ration de la ligne
/// du barème) ; l'ancienne règle `RationVolaille` (une ligne par sous-chaîne « pondeuse ») et son fichier n'existent plus.
void main() {
  FeedRationStandard ligne(String libelle, double g) => FeedRationStandard(
    id: libelle,
    speciesCode: 'aviculture',
    stageLabel: libelle,
    rationGPerDay: g,
    isActive: true,
    syncStatus: SyncStatus.synced,
  );

  // Barème du semis, trié par libellé comme le dépôt le sert (les trois lignes de VOL-1 y figurent aussi).
  final bareme = [
    ligne('Jeune', 80),
    ligne('Pondeuse (6 à 18 mois)', 110),
    ligne('Poulette (4 à 5.5 mois)', 80),
    ligne('Poussin', 30),
    ligne('Poussin en croissance (2 à 4 mois)', 60),
    ligne('Poussin ponte (0 à 2 mois)', 30),
    ligne('Reproducteur', 130),
  ];

  test('quatre lignes dans l ordre de la chaîne, jamais celles des reproducteurs', () {
    final t = StadePondeuse.tableau(bareme, {'quatre': 11, 'sevre': 17, 'jeune': 28, 'repro': 42});
    expect([for (final l in t.lignes) l.libelle], [
      'Poussin ponte (0 à 2 mois)',
      'Poussin en croissance (2 à 4 mois)',
      'Poulette (4 à 5.5 mois)',
      'Pondeuse (6 à 18 mois)',
    ]);
    // 11 × 30 + 17 × 60 + 28 × 80 + 42 × 110 = 330 + 1 020 + 2 240 + 4 620 = 8 210 g.
    expect([for (final l in t.lignes) l.totalG], [330, 1020, 2240, 4620]);
    expect(t.totalG, 8210);
    expect(t.totalKg, 8.21);
    expect(t.totalAffiche, '8210 g (8.21 Kg)');
  });

  test('le total est arrondi comme PHP : 1 125 g → 1.13 Kg, 5 000 g → 5 Kg', () {
    final t = StadePondeuse.tableau(
      [ligne('Pondeuse (6 à 18 mois)', 105)],
      {'quatre': 1, 'sevre': 2, 'jeune': 3, 'repro': 7},
    );
    // 1 × 30 + 2 × 60 + 3 × 80 + 7 × 105 = 1 125 (les trois premières lignes retombent sur les valeurs d'origine).
    expect(t.totalG, 1125);
    expect(t.totalAffiche, '1125 g (1.13 Kg)');
    expect(StadePondeuse.tableau(bareme, {'quatre': 10, 'sevre': 10, 'jeune': 10, 'repro': 30}).totalAffiche, '5000 g (5 Kg)');
  });

  test('🔴 un stade indisponible rend le total inconnu : « — », jamais 0 g', () {
    final t = StadePondeuse.tableau(bareme, {'quatre': null, 'sevre': 2, 'jeune': 3, 'repro': 7});
    expect(t.totalG, isNull);
    expect(t.totalKg, isNull);
    expect(t.totalAffiche, '—');
  });

  test('une ligne du barème absente retombe sur la valeur d origine', () {
    final t = StadePondeuse.tableau(
      [for (final l in bareme) if (!l.stageLabel.startsWith('Poulette')) l],
      {'quatre': 0, 'sevre': 0, 'jeune': 1, 'repro': 0},
    );
    expect(t.totalG, 80);
  });

  test('les clés de ration sont exactes, jamais par sous-chaîne, et disjointes de celles des reproducteurs', () {
    expect(StadePondeuse.cleDuLibelle('Poussin ponte (0 à 2 mois)'), StadePondeuse.poussinPonte);
    expect(StadePondeuse.cleDuLibelle('poussin en croissance'), StadePondeuse.poussinCroissance);
    expect(StadePondeuse.cleDuLibelle(' Poulette (4 à 5.5 mois) '), StadePondeuse.poulette);
    expect(StadePondeuse.cleDuLibelle('Pondeuse (6 à 18 mois)'), StadePondeuse.pondeuse);
    for (final autre in ['Poussin', 'Jeune', 'Reproducteur', 'Pondeuse réformée']) {
      expect(StadePondeuse.cleDuLibelle(autre), isNull, reason: autre);
    }
    expect(CategorieVolaille.cleDuLibelle('Poussin ponte (0 à 2 mois)'), isNull);
    expect(CategorieVolaille.cleDuLibelle('Pondeuse (6 à 18 mois)'), isNull);
  });

  test('le fichier de l ancienne règle n existe plus', () {
    expect(File('lib/features/elevage/ration_volaille.dart').existsSync(), isFalse);
  });

  test(
    'parité exécutée : le vrai PHP rend les mêmes lignes, le même total et les mêmes clés',
    () {
      final hasard = Random(2005);
      const libelles = [
        'Pondeuse (6 à 18 mois)',
        'Poulette (4 à 5.5 mois)',
        'Poussin en croissance (2 à 4 mois)',
        'Poussin ponte (0 à 2 mois)',
        'Reproducteur',
        'Jeune',
        'Poussin',
        'poussin PONTE',
        'Pondeuse réformée',
      ];
      final cas = [
        for (var i = 0; i < 80; i++)
          {
            'effectifs': {
              'quatre': hasard.nextInt(12) == 0 ? null : hasard.nextInt(300),
              'sevre': hasard.nextInt(300),
              'jeune': hasard.nextInt(300),
              'repro': hasard.nextInt(300),
            },
            'rations': [
              for (final l in (List.of(libelles)..shuffle(hasard)).take(hasard.nextInt(8)))
                {'stage_label': l, 'ration_g_per_day': 20 + hasard.nextInt(200) + (hasard.nextBool() ? 0.5 : 0)},
            ],
          },
      ];
      final sortie = executerPhp(r'''<?php
require 'vendor/autoload.php';
$cas = json_decode(file_get_contents($argv[1]), true);
echo json_encode(array_map(function ($c) {
    $t = App\Support\StadePondeuse::tableau(collect($c['rations'])->map(fn ($r) => (object) $r), $c['effectifs']);
    return [
        'effectifs' => array_column($t['lignes'], 'effectif'),
        'rations' => array_column($t['lignes'], 'ration'),
        'totaux' => array_column($t['lignes'], 'total_g'),
        'total' => $t['total_g'],
        'kg' => $t['total_kg'],
        'cles' => array_map(fn ($r) => App\Support\StadePondeuse::cleDuLibelle($r['stage_label']), $c['rations']),
    ];
}, $cas));
''', cas) as List;

      for (var i = 0; i < cas.length; i++) {
        final c = cas[i];
        final rations = [
          for (final r in c['rations'] as List) ligne(r['stage_label'] as String, (r['ration_g_per_day'] as num).toDouble()),
        ];
        final t = StadePondeuse.tableau(rations, {
          for (final e in (c['effectifs'] as Map).entries) e.key as String: e.value as int?,
        });
        final php = sortie[i] as Map<String, dynamic>;
        expect([for (final l in t.lignes) l.effectif], php['effectifs'], reason: 'cas $i');
        expect([for (final l in t.lignes) l.ration], [for (final x in php['rations'] as List) (x as num).toInt()], reason: 'cas $i');
        expect([for (final l in t.lignes) l.totalG], php['totaux'], reason: 'cas $i');
        expect(t.totalG, php['total'], reason: 'cas $i');
        expect(t.totalKg, (php['kg'] as num?)?.toDouble(), reason: 'cas $i');
        expect([for (final r in rations) StadePondeuse.cleDuLibelle(r.stageLabel)], php['cles'], reason: 'cas $i');
      }
    },
    skip: sautSansPhp(),
  );
}
