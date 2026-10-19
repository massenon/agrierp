import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/ration_volaille.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket 15.57 — LE RATIONNEMENT AVICOLE EST LE MÊME AU WEB ET AU POSTE (`App\Support\RationVolaille`).
void main() {
  FeedRationStandard ligne(String libelle, double g) => FeedRationStandard(
    id: libelle,
    speciesCode: 'aviculture',
    stageLabel: libelle,
    rationGPerDay: g,
    isActive: true,
    syncStatus: SyncStatus.synced,
  );

  // Barème du semis, trié par libellé comme le dépôt le sert.
  final bareme = [
    ligne('Pondeuse (6 à 18 mois)', 110),
    ligne('Poulette (4 à 5.5 mois)', 80),
    ligne('Poussin en croissance (2 à 4 mois)', 60),
    ligne('Poussin ponte (0 à 2 mois)', 30),
  ];

  test('pondeuses : 60 sur la ligne Pondeuse, 0 ailleurs, 6 600 g (6.6 Kg)', () {
    final l = RationVolaille.lignes(bareme, RationVolaille.pondeuse, 60);
    expect([for (final x in l) x.effectif], [60, 0, 0, 0]);
    expect(RationVolaille.totalAffiche(RationVolaille.totalG(l)), '6600 g (6.6 Kg)');
  });

  test('🔴 reproducteurs sans ligne au barème : « — », plus « 0 g »', () {
    final l = RationVolaille.lignes(bareme, RationVolaille.reproducteur, 60);
    expect(RationVolaille.rattachee(l), isFalse);
    expect([for (final x in l) x.effectif], [null, null, null, null]);
    expect(RationVolaille.totalAffiche(RationVolaille.totalG(l)), '—');
  });

  test('deux lignes « pondeuse » : seule la PREMIÈRE reçoit l effectif', () {
    final l = RationVolaille.lignes(
      [ligne('Pondeuse A', 100), ligne('PONDEUSE B', 120)],
      RationVolaille.pondeuse,
      10,
    );
    expect([for (final x in l) x.effectif], [10, 0]);
    expect(RationVolaille.totalG(l), 1000);
  });

  test('kilos à la manière de PHP : 9 000 g → « 9 », 6 650 g → « 6.65 »', () {
    expect(RationVolaille.kgCommePhp(9000), '9');
    expect(RationVolaille.kgCommePhp(6650), '6.65');
  });

  test(
    'parité exécutée : la règle PHP rend les mêmes effectifs et le même total',
    () {
      final hasard = Random(1557);
      const libelles = ['Pondeuse', 'Poulette', 'Reproducteur', 'Poussin', 'Coq REPRODUCTEUR', 'Pondeuse réformée'];
      final cas = [
        for (var i = 0; i < 60; i++)
          {
            'cle': i.isEven ? RationVolaille.pondeuse : RationVolaille.reproducteur,
            'effectif': hasard.nextInt(500),
            'rations': [
              for (final l in (List.of(libelles)..shuffle(hasard)).take(1 + hasard.nextInt(4)))
                {'stage_label': l, 'ration_g_per_day': 20 + hasard.nextInt(200)},
            ]..sort((a, b) => (a['stage_label'] as String).compareTo(b['stage_label'] as String)),
          },
      ];
      final sortie = executerPhp(r'''<?php
require 'vendor/autoload.php';
$cas = json_decode(file_get_contents($argv[1]), true);
echo json_encode(array_map(function ($c) {
    $t = App\Support\RationVolaille::tableau(collect($c['rations'])->map(fn ($r) => (object) $r), $c['cle'], $c['effectif']);
    return ['effectifs' => array_column($t['lignes'], 'effectif'), 'total' => $t['total_g']];
}, $cas));
''', cas) as List;

      for (var i = 0; i < cas.length; i++) {
        final c = cas[i];
        final l = RationVolaille.lignes(
          [for (final r in c['rations'] as List) ligne(r['stage_label'] as String, (r['ration_g_per_day'] as int).toDouble())],
          c['cle'] as String,
          c['effectif'] as int,
        );
        final php = sortie[i] as Map<String, dynamic>;
        expect([for (final x in l) x.effectif], php['effectifs'], reason: 'cas $i');
        expect(RationVolaille.totalG(l), (php['total'] as num?)?.toDouble(), reason: 'cas $i');
      }
    },
    skip: sautSansPhp(),
  );
}
