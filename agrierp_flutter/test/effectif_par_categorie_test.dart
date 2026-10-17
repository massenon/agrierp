import 'dart:math';

import 'package:agrierp/features/elevage/effectif_par_categorie.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket F0.95 — service Dart d'effectif par catégorie, miroir de
/// `App\Services\EffectifParCategorieService` (15.39–15.42).
///
/// Deux preuves indépendantes :
///  1. des JEUX CALCULÉS À LA MAIN (plan du 14/10/2026, tickets 15.39/15.41/15.42) écrits en
///     littéraux, jamais produits par le service ;
///  2. une PARITÉ EXÉCUTÉE : des grilles générées sont soumises au VRAI PHP du dépôt Laravel
///     (fonctions pures par `vendor/autoload.php` ; chaîne, état d'un jour et refus de passage par
///     l'application démarrée sur SQLite EN MÉMOIRE) et les sorties sont comparées une à une.
const _mv0 = MouvementsJour(
  achat: 0,
  ne: 0,
  vente: 0,
  mortRepro: 0,
  mortSevre: 0,
  mortJeune: 0,
  donRepro: 0,
  donSevre: 0,
  donJeune: 0,
  passage: 0,
);

MouvementsJour _mv({
  int achat = 0,
  int ne = 0,
  int vente = 0,
  int mortRepro = 0,
  int mortSevre = 0,
  int mortJeune = 0,
  int donRepro = 0,
  int donSevre = 0,
  int donJeune = 0,
  int passage = 0,
}) => MouvementsJour(
  achat: achat,
  ne: ne,
  vente: vente,
  mortRepro: mortRepro,
  mortSevre: mortSevre,
  mortJeune: mortJeune,
  donRepro: donRepro,
  donSevre: donSevre,
  donJeune: donJeune,
  passage: passage,
);

EffectifCategories _e(int? r, int? s, int? j) =>
    EffectifCategories(repro: r, sevre: s, jeune: j);

List<int?> _trio(EffectifCategoriesJour r) => [r.repro, r.sevre, r.jeune];

/// Fiche de chaîne avec ses totaux `mort`/`don` cohérents (non utilisés par la chaîne).
FicheChaine _f(
  String id,
  int jour,
  int total, {
  int achat = 0,
  int ne = 0,
  int vente = 0,
  int? mortRepro = 0,
  int? mortSevre = 0,
  int? mortJeune = 0,
  int? donRepro = 0,
  int? donSevre = 0,
  int? donJeune = 0,
  int? passage = 0,
  (int, int, int)? depart,
}) => FicheChaine(
  id: id,
  jour: DateTime(2026, 10, jour),
  effectifFinal: total,
  achat: achat,
  ne: ne,
  vente: vente,
  mortRepro: mortRepro,
  mortSevre: mortSevre,
  mortJeune: mortJeune,
  donRepro: donRepro,
  donSevre: donSevre,
  donJeune: donJeune,
  passage: passage,
  departRepro: depart?.$1,
  departSevre: depart?.$2,
  departJeune: depart?.$3,
);

void main() {
  const lap = EffectifParCategorie.lapins;
  const por = EffectifParCategorie.porcs;

  group('jeux calculés à la main — lapins (plan du 14/10/2026)', () {
    test('J1 : achat 2, nés 5, mort Jeune 1 → 10/26/30 (total 66)', () {
      final r = EffectifParCategorie.calculerJour(
        lap,
        _e(10, 20, 30),
        _mv(achat: 2, ne: 5, mortSevre: 1),
        totalFinal: 66,
      );
      expect(_trio(r), [10, 26, 30]);
      expect(r.sommeDifferente, isFalse);
      expect(r.refus, isNull);
    });

    test('J2 : vente 4, morts R1 et C2, don J1 → 9/25/24 (total 58)', () {
      final r = EffectifParCategorie.calculerJour(
        lap,
        _e(10, 26, 30),
        _mv(vente: 4, mortRepro: 1, mortJeune: 2, donSevre: 1),
        totalFinal: 58,
      );
      expect(_trio(r), [9, 25, 24]);
      expect(r.sommeDifferente, isFalse);
    });

    test('⚠️ J3 : vente 30, mort J2 → 9/23/0, total 26 mais SOMME 32 (D8)', () {
      final r = EffectifParCategorie.calculerJour(
        lap,
        _e(9, 25, 24),
        _mv(vente: 30, mortSevre: 2),
        totalFinal: 26,
      );
      expect(_trio(r), [9, 23, 0]);
      expect(r.somme, 32);
      expect(r.sommeDifferente, isTrue);
      expect(r.refus, isNull, reason: 'un avertissement n est pas un refus');
    });

    test('achat → Jeune, jamais Reproducteur ; vente → Chair seulement', () {
      expect(
        _trio(
          EffectifParCategorie.calculerJour(
            lap,
            _e(10, 20, 30),
            _mv(achat: 7),
            totalFinal: 67,
          ),
        ),
        [10, 27, 30],
      );
      expect(
        _trio(
          EffectifParCategorie.calculerJour(
            lap,
            _e(10, 20, 30),
            _mv(vente: 5),
            totalFinal: 55,
          ),
        ),
        [10, 20, 25],
      );
    });

    test('chaîne du plan sur trois jours (simulation) → 10/26/30, 9/25/24, 9/23/0', () {
      final c = EffectifParCategorie.simulerChaine(
        espece: lap,
        initialQuantity: 60,
        fiches: [
          // Ordre d'insertion volontairement mélangé : la chaîne trie par jour.
          _f('j3', 3, 26, vente: 30, mortSevre: 2),
          _f(
            'j1',
            1,
            66,
            achat: 2,
            ne: 5,
            mortSevre: 1,
            depart: (10, 20, 30),
          ),
          _f('j2', 2, 58, vente: 4, mortRepro: 1, mortJeune: 2, donSevre: 1),
        ],
      );
      expect(c.chaine, isTrue);
      expect(c.refus, isNull);
      expect(_trio(c.resultats['j1']!), [10, 26, 30]);
      expect(_trio(c.resultats['j2']!), [9, 25, 24]);
      expect(_trio(c.resultats['j3']!), [9, 23, 0]);
      expect(c.resultats['j3']!.sommeDifferente, isTrue);
    });

    test('jour sauté : la fiche du 04 repart de celle du 01 → 9/26/26', () {
      final c = EffectifParCategorie.simulerChaine(
        espece: lap,
        initialQuantity: 60,
        fiches: [
          _f(
            'j1',
            1,
            66,
            achat: 2,
            ne: 5,
            mortSevre: 1,
            depart: (10, 20, 30),
          ),
          _f('j4', 4, 61, vente: 4, mortRepro: 1),
        ],
      );
      expect(_trio(c.resultats['j4']!), [9, 26, 26]);
      expect(c.resultats['j4']!.sommeDifferente, isFalse, reason: '61');
    });

    test('passage de stade = TRANSFERT Jeune → Chair, total inchangé (10/12/38)', () {
      final c = EffectifParCategorie.simulerChaine(
        espece: lap,
        initialQuantity: 60,
        fiches: [_f('j1', 1, 60, passage: 8, depart: (10, 20, 30))],
      );
      expect(_trio(c.resultats['j1']!), [10, 12, 38]);
      expect(c.resultats['j1']!.somme, 60);
      expect(c.avertissements, isEmpty);
    });

    test(
      '⚠️ passage excessif (25 sur 20) : REFUS à la saisie, ramené à la source en recalcul',
      () {
        final proposee = _f('j1', 1, 60, passage: 25, depart: (10, 20, 30));
        expect(
          EffectifParCategorie.refusDuPassage(
            espece: lap,
            autres: const [],
            proposee: proposee,
          ),
          'Passage de stade refusé : 25 sujet(s) à faire passer, mais la catégorie source '
          "n'en compte que 20.",
        );
        final c = EffectifParCategorie.simulerChaine(
          espece: lap,
          initialQuantity: 60,
          fiches: [proposee],
        );
        expect(c.refus, isNull, reason: 'le refus de chaîne est réservé au départ');
        expect(_trio(c.resultats['j1']!), [10, 0, 50]);
        expect(c.avertissements.single, contains('01/10/2026'));
        expect(c.avertissements.single, contains('saisie conservée'));
      },
    );
  });

  group('jeux calculés à la main — porcs (plan du 14/10/2026)', () {
    test('R10/P24/M86 → 13/31/86, 12/31/80, 12/30/75, J4 plancher 12/0/75', () {
      final c = EffectifParCategorie.simulerChaine(
        espece: por,
        initialQuantity: 120,
        fiches: [
          _f(
            'j1',
            1,
            130,
            achat: 3,
            ne: 9,
            mortSevre: 2,
            depart: (10, 24, 86),
          ),
          _f('j2', 2, 123, vente: 5, mortRepro: 1, donJeune: 1),
          _f('j3', 3, 117, vente: 2, mortJeune: 3, donSevre: 1),
          _f('j4', 4, 77, mortSevre: 40),
        ],
      );
      expect(_trio(c.resultats['j1']!), [13, 31, 86]);
      expect(c.resultats['j1']!.somme, 130);
      expect(_trio(c.resultats['j2']!), [12, 31, 80]);
      expect(c.resultats['j2']!.somme, 123);
      expect(_trio(c.resultats['j3']!), [12, 30, 75]);
      expect(c.resultats['j3']!.somme, 117);
      expect(_trio(c.resultats['j4']!), [12, 0, 75]);
      expect(c.resultats['j4']!.somme, 87, reason: 'somme 87 ≠ total 77');
      expect(c.resultats['j4']!.sommeDifferente, isTrue);
    });

    test('achat de porcs → Reproducteur (D11), nés → Porcelet', () {
      final r = EffectifParCategorie.calculerJour(
        por,
        _e(10, 24, 86),
        _mv(achat: 4, ne: 6),
        totalFinal: 130,
      );
      expect(_trio(r), [14, 30, 86]);
    });

    test('passage Porcelet → Marchand, toute la source permise (5/0/13)', () {
      final r = EffectifParCategorie.calculerJour(
        por,
        _e(5, 10, 3),
        _mv(passage: 10),
        totalFinal: 18,
      );
      expect(_trio(r), [5, 0, 13]);
      expect(r.refus, isNull);
    });

    test('source = APRÈS les autres mouvements du jour : 9 permis, 10 refusé', () {
      final ok = EffectifParCategorie.calculerJour(
        por,
        _e(0, 10, 0),
        _mv(ne: 2, mortSevre: 3, passage: 9),
        totalFinal: 9,
      );
      expect(_trio(ok), [0, 0, 9]);
      expect(ok.refus, isNull);
      final ko = EffectifParCategorie.calculerJour(
        por,
        _e(0, 10, 0),
        _mv(ne: 2, mortSevre: 3, passage: 10),
        totalFinal: 9,
      );
      expect(ko.refus, isNotNull);
      expect(ko.passageApplique, 9);
    });
  });

  group('départ (D4)', () {
    test('somme = total accepté ; somme différente refusée avec les deux nombres', () {
      expect(EffectifParCategorie.verifierDepart(_e(10, 20, 30), 60), isNull);
      expect(
        EffectifParCategorie.verifierDepart(_e(10, 20, 30), 61),
        "La somme des catégories de départ (60) ne correspond pas à l'effectif total au "
        'début du jour de départ (61).',
      );
      expect(EffectifParCategorie.verifierDepart(_e(0, 0, 0), 0), isNull);
    });

    test('départ incomplet ou total inconnu refusés', () {
      expect(
        EffectifParCategorie.verifierDepart(_e(10, null, 30), 40),
        startsWith('Effectif de départ incomplet'),
      );
      expect(
        EffectifParCategorie.verifierDepart(_e(1, 2, 3), null),
        'Effectif total de départ inconnu : la somme des catégories (1 + 2 + 3) ne peut pas '
        'être contrôlée.',
      );
    });

    test('départ incohérent : TOUTE la chaîne refusée, aucun résultat', () {
      final c = EffectifParCategorie.simulerChaine(
        espece: lap,
        initialQuantity: 60,
        fiches: [_f('j1', 1, 61, achat: 1, depart: (10, 20, 31))],
      );
      expect(c.chaine, isTrue);
      expect(c.refus, contains('61'));
      expect(c.resultats, isEmpty);
    });

    test('second départ dans la chaîne : ignoré et signalé', () {
      final c = EffectifParCategorie.simulerChaine(
        espece: lap,
        initialQuantity: 60,
        fiches: [
          _f('j1', 1, 60, depart: (10, 20, 30)),
          _f('j2', 2, 60, depart: (1, 1, 1)),
        ],
      );
      expect(_trio(c.resultats['j2']!), [10, 20, 30]);
      expect(
        c.avertissements.single,
        'Fiche du 02/10/2026 : un départ y est saisi alors que la chaîne démarre déjà le '
        '01/10/2026 ; il est ignoré.',
      );
    });

    test('départ partiel = pas de chaîne ; espèce non suivie = pas de chaîne', () {
      expect(
        EffectifParCategorie.simulerChaine(
          espece: lap,
          initialQuantity: 60,
          fiches: [
            FicheChaine(
              id: 'p',
              jour: DateTime(2026, 10, 1),
              effectifFinal: 60,
              departRepro: 10,
              departSevre: 20,
            ),
          ],
        ).chaine,
        isFalse,
      );
      expect(EffectifParCategorie.especeDuCode('aviculture'), isNull);
      expect(EffectifParCategorie.especeDuCode('cuniculture'), lap);
      expect(EffectifParCategorie.especeDuCode('porciculture'), por);
      expect(
        EffectifParCategorie.simulerChaine(
          espece: null,
          initialQuantity: 60,
          fiches: [_f('j1', 1, 60, depart: (10, 20, 30))],
        ).chaine,
        isFalse,
      );
    });
  });

  group('null = INCONNU, jamais 0', () {
    test('veille inconnue : seule la catégorie concernée est inconnue', () {
      final r = EffectifParCategorie.calculerJour(
        lap,
        _e(10, null, 30),
        _mv(vente: 4),
        totalFinal: 56,
      );
      expect(_trio(r), [10, null, 26]);
      expect(r.sommeDifferente, isNull);
    });

    test('passage inconnu : les deux catégories du transfert inconnues', () {
      final r = EffectifParCategorie.calculerJour(
        por,
        _e(10, 20, 30),
        const MouvementsJour(
          achat: 0,
          ne: 0,
          vente: 0,
          mortRepro: 0,
          mortSevre: 0,
          mortJeune: 0,
          donRepro: 0,
          donSevre: 0,
          donJeune: 0,
        ),
        totalFinal: 60,
      );
      expect(_trio(r), [10, null, null]);
    });

    test('l inconnu se propage au jour suivant ([10, null, 25])', () {
      final c = EffectifParCategorie.simulerChaine(
        espece: lap,
        initialQuantity: 60,
        fiches: [
          _f('j1', 1, 60, depart: (10, 20, 30)),
          _f('j2', 2, 56, vente: 4, mortSevre: null),
          _f('j3', 3, 55, vente: 1),
        ],
      );
      expect(_trio(c.resultats['j2']!), [10, null, 26]);
      expect(_trio(c.resultats['j3']!), [10, null, 25]);
    });

    test('zéro connu reste zéro', () {
      final r = EffectifParCategorie.calculerJour(
        lap,
        _e(0, 0, 0),
        _mv0,
        totalFinal: 0,
      );
      expect(_trio(r), [0, 0, 0]);
      expect(r.sommeDifferente, isFalse);
    });

    test('espèce non prise en charge : refus franc', () {
      expect(
        () => EffectifParCategorie.calculerJour('volailles', _e(1, 1, 1), _mv0),
        throwsArgumentError,
      );
    });
  });

  group('état pour un jour (15.41)', () {
    final fiches = [
      _f('j1', 1, 66, achat: 2, ne: 5, mortSevre: 1, depart: (10, 20, 30)),
      FicheChaine(
        id: 'j3',
        jour: DateTime(2026, 10, 3),
        effectifFinal: 60,
        catEffRepro: 9,
        catEffSevre: null,
        catEffJeune: 24,
      ),
    ];

    test('avant le départ (D12), le jour même (D4) et après un jour sauté', () {
      final avant = EffectifParCategorie.etatPourJour(
        espece: lap,
        fiches: fiches,
        initialQuantity: 60,
        jour: DateTime(2026, 9, 30),
      );
      expect(avant.mode, 'avant_depart');
      final tete = EffectifParCategorie.etatPourJour(
        espece: lap,
        fiches: fiches,
        initialQuantity: 60,
        jour: DateTime(2026, 10, 1),
      );
      expect(tete.mode, 'chaine');
      expect(tete.veille, _e(10, 20, 30));
      final saute = EffectifParCategorie.etatPourJour(
        espece: lap,
        fiches: fiches,
        initialQuantity: 60,
        jour: DateTime(2026, 10, 5),
      );
      expect(
        saute.veille,
        _e(9, null, 24),
        reason: 'catégories STOCKÉES du 03, null conservé',
      );
      expect(
        EffectifParCategorie.etatPourJour(
          espece: lap,
          fiches: const [],
          initialQuantity: 60,
          jour: DateTime(2026, 10, 1),
        ).mode,
        'sans_chaine',
      );
    });
  });

  group('effectif total (14.63)', () {
    test('plancher à 0, formule du serveur', () {
      expect(
        EffectifParCategorie.effectifFinal(
          precedent: 40,
          achat: 0,
          ne: 0,
          mort: 50,
          vente: 0,
          don: 0,
        ),
        0,
      );
      expect(
        EffectifParCategorie.effectifFinal(
          precedent: 50,
          achat: 3,
          ne: 2,
          mort: 1,
          vente: 6,
          don: 1,
        ),
        47,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════ PARITÉ EXÉCUTÉE (PHP)
  final saut = sautSansPhp();

  group('⚠️⚠️ parité EXÉCUTÉE avec le vrai PHP du serveur', () {
    test(
      'calculerJour : grille de 640 combinaisons générées + verifierDepart : 160',
      () {
        final hasard = Random(1595);
        int? n(int max, {double nul = 0.08}) =>
            hasard.nextDouble() < nul ? null : hasard.nextInt(max + 1);

        final jours = <List<Object?>>[];
        for (var i = 0; i < 640; i++) {
          final espece = i.isEven ? lap : por;
          final veille = {'repro': n(40), 'sevre': n(40), 'jeune': n(40)};
          final m = {
            'achat': n(9),
            'ne': n(9),
            'vente': n(60),
            'mort_repro': n(12),
            'mort_sevre': n(12),
            'mort_jeune': n(12),
            'don_repro': n(5),
            'don_sevre': n(5),
            'don_jeune': n(5),
            // Passage autour de la source : 0..45, souvent au-delà (refus).
            'passage': n(45, nul: 0.1),
          };
          final total = hasard.nextInt(4) == 0 ? null : hasard.nextInt(130);
          jours.add([espece, veille, m, total]);
        }
        final departs = <List<Object?>>[];
        for (var i = 0; i < 160; i++) {
          final d = {'repro': n(30), 'sevre': n(30), 'jeune': n(30)};
          final somme = (d['repro'] ?? 0) + (d['sevre'] ?? 0) + (d['jeune'] ?? 0);
          final total = switch (hasard.nextInt(4)) {
            0 => null,
            1 => somme + hasard.nextInt(3) - 1,
            _ => somme,
          };
          departs.add([d, total]);
        }

        final sortie =
            executerPhp(
                  r'''<?php
require 'vendor/autoload.php';
$e = json_decode(file_get_contents($argv[1]), true);
$s = ['jours' => [], 'departs' => []];
foreach ($e['jours'] as $c) {
    $r = App\Services\EffectifParCategorieService::calculerJour($c[0], $c[1], $c[2], $c[3]);
    $s['jours'][] = [$r->repro, $r->sevre, $r->jeune, $r->sommeDifferente, $r->refus, $r->passageApplique];
}
foreach ($e['departs'] as $c) {
    $s['departs'][] = App\Services\EffectifParCategorieService::verifierDepart($c[0], $c[1]);
}
echo json_encode($s);
''',
                  {'jours': jours, 'departs': departs},
                )
                as Map<String, dynamic>;

        final attendusJours = sortie['jours'] as List;
        expect(attendusJours, hasLength(640));
        var refus = 0;
        var inconnus = 0;
        for (var i = 0; i < jours.length; i++) {
          final c = jours[i];
          final v = c[1] as Map<String, int?>;
          final m = c[2] as Map<String, int?>;
          final r = EffectifParCategorie.calculerJour(
            c[0] as String,
            _e(v['repro'], v['sevre'], v['jeune']),
            MouvementsJour(
              achat: m['achat'],
              ne: m['ne'],
              vente: m['vente'],
              mortRepro: m['mort_repro'],
              mortSevre: m['mort_sevre'],
              mortJeune: m['mort_jeune'],
              donRepro: m['don_repro'],
              donSevre: m['don_sevre'],
              donJeune: m['don_jeune'],
              passage: m['passage'],
            ),
            totalFinal: c[3] as int?,
          );
          expect(
            [
              r.repro,
              r.sevre,
              r.jeune,
              r.sommeDifferente,
              r.refus,
              r.passageApplique,
            ],
            attendusJours[i],
            reason: 'combinaison #$i : $c',
          );
          if (r.refus != null) refus++;
          if (r.repro == null || r.sevre == null || r.jeune == null) inconnus++;
        }
        // La grille exerce vraiment les branches (sinon la parité serait vide).
        expect(refus, greaterThan(50));
        expect(inconnus, greaterThan(50));

        final attendusDeparts = sortie['departs'] as List;
        for (var i = 0; i < departs.length; i++) {
          final d = departs[i][0] as Map<String, int?>;
          expect(
            EffectifParCategorie.verifierDepart(
              _e(d['repro'], d['sevre'], d['jeune']),
              departs[i][1] as int?,
            ),
            attendusDeparts[i],
            reason: 'départ #$i : ${departs[i]}',
          );
        }
      },
      skip: saut,
    );

    test(
      'chaîne (recalculerChaine), état d un jour (etatPourJour) et refus de passage '
      '(refusDuPassage) : 160 bandes générées, application démarrée sur SQLite en mémoire',
      () {
        final hasard = Random(9515);
        final scenarios = [for (var i = 0; i < 160; i++) scenarioAuHasard(hasard, i)];

        final sortie =
            executerPhp(
                  '<?php\n$amorceApplication\n$scriptChaine',
                  [for (final s in scenarios) s.versJson()],
                  application: true,
                )
                as List;
        expect(sortie, hasLength(scenarios.length));

        var chaines = 0;
        var refusDepart = 0;
        var avertis = 0;
        var passagesRefuses = 0;
        for (var i = 0; i < scenarios.length; i++) {
          final s = scenarios[i];
          final php = sortie[i] as Map<String, dynamic>;
          final fiches = s.fichesChaine();
          final espece = EffectifParCategorie.especeDuCode(s.especeCode);

          // (1) État d'un jour — lu AVANT tout recalcul, comme au serveur.
          final etats = php['etats'] as List;
          for (var k = 0; k < s.etats.length; k++) {
            final e = EffectifParCategorie.etatPourJour(
              espece: espece,
              fiches: fiches,
              initialQuantity: s.initial,
              jour: s.etats[k],
            );
            final p = etats[k] as Map<String, dynamic>;
            expect(e.mode, p['mode'], reason: 'scénario $i, état $k');
            expect(
              e.departDate == null ? null : _iso(e.departDate!),
              p['depart_date'],
            );
            expect(e.refus, p['refus'], reason: 'scénario $i, état $k');
            expect(_dict(e.depart), p['depart']);
            expect(_dict(e.veille), p['veille'], reason: 'scénario $i, état $k');
          }

          // (2) Refus de passage d'une fiche proposée.
          if (s.proposee != null) {
            final r = EffectifParCategorie.refusDuPassage(
              espece: espece,
              autres: fiches,
              proposee: s.ficheProposee(),
            );
            expect(r, php['passage'], reason: 'scénario $i, passage');
            if (r != null) passagesRefuses++;
          }

          // (3) Chaîne : catégories écrites, refus, avertissements.
          final c = EffectifParCategorie.simulerChaine(
            espece: espece,
            fiches: fiches,
            initialQuantity: s.initial,
          );
          final rapport = php['rapport'] as Map<String, dynamic>;
          expect(c.chaine, rapport['chaine'], reason: 'scénario $i');
          expect(c.refus, rapport['refus'], reason: 'scénario $i');
          expect(c.avertissements, rapport['avertissements'], reason: 'scénario $i');
          final ecrites = php['fiches'] as List;
          for (var k = 0; k < fiches.length; k++) {
            final f = fiches[k];
            final r = (c.chaine && c.refus == null) ? c.resultats[f.id] : null;
            final attendu = r == null
                ? [f.catEffRepro, f.catEffSevre, f.catEffJeune]
                : [r.repro, r.sevre, r.jeune];
            expect(
              attendu,
              (ecrites[k] as List).sublist(1),
              reason: 'scénario $i, fiche $k',
            );
          }
          if (c.chaine) chaines++;
          if (c.refus != null) refusDepart++;
          if (c.avertissements.isNotEmpty) avertis++;
        }
        expect(chaines, greaterThan(80));
        expect(refusDepart, greaterThan(5));
        expect(avertis, greaterThan(5));
        expect(passagesRefuses, greaterThan(5));
      },
      skip: saut,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, int?>? _dict(EffectifCategories? e) =>
    e == null ? null : {'repro': e.repro, 'sevre': e.sevre, 'jeune': e.jeune};

/// Script PHP : pour chaque bande générée, pose les fiches telles quelles, lit `etatPourJour`
/// et `refusDuPassage` (avant tout recalcul), lance `recalculerChaine` (ou la cascade des ventes
/// pour un scénario « cascade »), puis relit chaque fiche et la bande.
const scriptChaine = r'''
$entree = json_decode(file_get_contents($argv[1]), true);
$especes = [];
$sortie = [];
foreach ($entree as $i => $sc) {
    $code = $sc['espece'];
    if (! isset($especes[$code])) {
        $especes[$code] = App\Models\LivestockSpecies::create(['label' => $code, 'code' => $code, 'is_active' => true]);
    }
    $lot = App\Models\LivestockLot::create([
        'code' => 'S'.$i, 'species_id' => $especes[$code]->id, 'stage' => 'croissance',
        'initial_quantity' => $sc['initial'], 'current_quantity' => $sc['initial'],
        'created_date' => '2026-01-01', 'status' => 'actif', 'is_active' => true,
    ]);
    $ids = [];
    foreach ($sc['fiches'] as $f) {
        $e = new App\Models\LivestockDailyEntry(array_merge($f, ['lot_id' => $lot->id]));
        $e->save();
        $ids[] = $e->id;
    }
    $lot = $lot->fresh();
    $service = app(App\Services\EffectifParCategorieService::class);
    $res = ['etats' => [], 'passage' => null, 'rapport' => null];
    foreach ($sc['etats'] as $d) {
        $res['etats'][] = $service->etatPourJour($lot, $d);
    }
    if ($sc['proposee'] !== null) {
        $p = $sc['proposee'];
        if ($p['index'] !== null) {
            $prop = App\Models\LivestockDailyEntry::find($ids[$p['index']]);
            $prop->fill($p['valeurs']);
        } else {
            $prop = new App\Models\LivestockDailyEntry(array_merge(['lot_id' => $lot->id], $p['valeurs']));
            $prop->id = (string) Illuminate\Support\Str::uuid();
        }
        $res['passage'] = $service->refusDuPassage($lot, $prop);
    }
    if ($sc['type'] === 'cascade') {
        app(App\Actions\RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($lot->id, $sc['depuis']);
    } else {
        $res['rapport'] = $service->recalculerChaine($lot->id);
    }
    $res['fiches'] = [];
    foreach ($ids as $id) {
        $x = App\Models\LivestockDailyEntry::find($id);
        $res['fiches'][] = [(int) $x->effectif_final, $x->cat_eff_repro, $x->cat_eff_sevre, $x->cat_eff_jeune];
    }
    $res['bande'] = (int) App\Models\LivestockLot::find($lot->id)->current_quantity;
    $sortie[] = $res;
}
echo json_encode($sortie);
''';

/// Une bande générée et ses fiches, sous la forme des colonnes du serveur.
class Scenario {
  Scenario({
    required this.especeCode,
    required this.initial,
    required this.fiches,
    required this.etats,
    required this.proposee,
    this.type = 'chaine',
    this.depuis,
  });

  final String especeCode;
  final int initial;

  /// Fiches (colonnes du serveur, `entry_date` en `Y-m-d`), dans l'ordre des jours.
  final List<Map<String, Object?>> fiches;
  final List<DateTime> etats;

  /// `{index: int?, valeurs: {…}}` ou null.
  final Map<String, Object?>? proposee;
  final String type;
  final DateTime? depuis;

  Map<String, Object?> versJson() => {
    'espece': especeCode,
    'initial': initial,
    'fiches': fiches,
    'etats': [for (final d in etats) _iso(d)],
    'proposee': proposee,
    'type': type,
    'depuis': depuis == null ? null : _iso(depuis!),
  };

  static FicheChaine ficheDe(String id, Map<String, Object?> f) {
    final j = (f['entry_date'] as String).split('-').map(int.parse).toList();
    return FicheChaine(
      id: id,
      jour: DateTime(j[0], j[1], j[2]),
      effectifFinal: f['effectif_final'] as int? ?? 0,
      achat: f['achat'] as int? ?? 0,
      ne: f['ne'] as int? ?? 0,
      vente: f['vente'] as int? ?? 0,
      mortRepro: f['mort_repro'] as int?,
      mortSevre: f['mort_sevre'] as int?,
      mortJeune: f['mort_jeune'] as int?,
      donRepro: f['don_repro'] as int?,
      donSevre: f['don_sevre'] as int?,
      donJeune: f['don_jeune'] as int?,
      passage: f['passage_sevre_jeune'] as int?,
      departRepro: f['cat_depart_repro'] as int?,
      departSevre: f['cat_depart_sevre'] as int?,
      departJeune: f['cat_depart_jeune'] as int?,
      catEffRepro: f['cat_eff_repro'] as int?,
      catEffSevre: f['cat_eff_sevre'] as int?,
      catEffJeune: f['cat_eff_jeune'] as int?,
    );
  }

  List<FicheChaine> fichesChaine() => [
    for (var k = 0; k < fiches.length; k++) ficheDe('f$k', fiches[k]),
  ];

  FicheChaine ficheProposee() {
    final p = proposee!;
    final index = p['index'] as int?;
    final valeurs = p['valeurs'] as Map<String, Object?>;
    return index == null
        ? ficheDe('proposee', valeurs)
        : ficheDe('f$index', {...fiches[index], ...valeurs});
  }
}

/// Génère une bande : 1 à 6 fiches, jours sautés, ventilations parfois inconnues, départ cohérent
/// (le plus souvent), incohérent, partiel ou absent, second départ, totaux parfois périmés,
/// catégories stockées aléatoires (elles comptent pour `etatPourJour` et avant la tête).
Scenario scenarioAuHasard(Random h, int i, {String type = 'chaine'}) {
  int? n(int max, {double nul = 0.07}) =>
      h.nextDouble() < nul ? null : h.nextInt(max + 1);

  final especeCode = switch (h.nextInt(10)) {
    0 => 'aviculture',
    < 5 => 'cuniculture',
    _ => 'porciculture',
  };
  final initial = 20 + h.nextInt(90);
  final nb = 1 + h.nextInt(6);
  final teteVoulue = h.nextInt(100) < 85 ? h.nextInt(nb) : -1;

  var jour = DateTime(2026, 9, 25 + h.nextInt(4));
  var courant = initial;
  final fiches = <Map<String, Object?>>[];
  for (var k = 0; k < nb; k++) {
    final f = <String, Object?>{
      'entry_date': _iso(jour),
      'achat': h.nextInt(5),
      'ne': h.nextInt(7),
      'vente': h.nextInt(6) == 0 ? h.nextInt(60) : h.nextInt(8),
      'mort_repro': n(4),
      'mort_sevre': n(h.nextInt(8) == 0 ? 40 : 5),
      'mort_jeune': n(5),
      'don_repro': n(2),
      'don_sevre': n(2),
      'don_jeune': n(2),
      'passage_sevre_jeune': n(h.nextInt(4) == 0 ? 40 : 10, nul: 0.1),
      'cat_eff_repro': n(30, nul: 0.4),
      'cat_eff_sevre': n(30, nul: 0.4),
      'cat_eff_jeune': n(30, nul: 0.4),
    };
    int somme(String g) => [
      f['${g}_repro'],
      f['${g}_sevre'],
      f['${g}_jeune'],
    ].fold<int>(0, (t, x) => t + ((x as int?) ?? 0));
    f['mort'] = somme('mort');
    f['don'] = somme('don');

    if (k == teteVoulue) {
      // Départ = effectif au DÉBUT du jour (fin de la fiche précédente, sinon l'initial).
      final total = courant;
      final r = h.nextInt(total + 1);
      final s = h.nextInt(total - r + 1);
      final j = total - r - s;
      switch (h.nextInt(20)) {
        case 0:
          f.addAll({'cat_depart_repro': r, 'cat_depart_sevre': s, 'cat_depart_jeune': j + 1});
        case 1:
          f.addAll({'cat_depart_repro': r, 'cat_depart_sevre': s});
        default:
          f.addAll({'cat_depart_repro': r, 'cat_depart_sevre': s, 'cat_depart_jeune': j});
      }
    } else if (teteVoulue >= 0 && k > teteVoulue && h.nextInt(12) == 0) {
      f['cat_depart_repro'] = h.nextInt(5);
      if (h.nextBool()) {
        f['cat_depart_sevre'] = 1;
        f['cat_depart_jeune'] = 1;
      }
    }

    courant = max(
      0,
      courant +
          (f['achat'] as int) +
          (f['ne'] as int) -
          ((f['mort'] as int) + (f['vente'] as int) + (f['don'] as int)),
    );
    // Total parfois périmé (une cascade n'est pas encore passée).
    f['effectif_final'] = h.nextInt(7) == 0
        ? max(0, courant + h.nextInt(7) - 3)
        : courant;
    fiches.add(f);
    // Jours calendaires (jamais `add(Duration)`, faux d'une heure lors d'un changement d'heure).
    jour = DateTime(
      jour.year,
      jour.month,
      jour.day + 1 + (h.nextInt(4) == 0 ? h.nextInt(3) : 0),
    );
  }

  final premier = DateTime.parse(fiches.first['entry_date'] as String);
  final etats = [
    for (var k = 0; k < 3; k++)
      DateTime(premier.year, premier.month, premier.day + h.nextInt(nb + 4) - 1),
  ];

  Map<String, Object?>? proposee;
  if (h.nextInt(4) != 0) {
    final valeurs = <String, Object?>{
      'passage_sevre_jeune': h.nextInt(4) == 0 ? null : h.nextInt(45),
      'mort_sevre': n(6),
    };
    if (h.nextBool()) {
      proposee = {'index': h.nextInt(nb), 'valeurs': valeurs};
    } else {
      proposee = {
        'index': null,
        'valeurs': {
          ...valeurs,
          'entry_date': _iso(jour),
          'achat': h.nextInt(4),
          'ne': h.nextInt(4),
          'vente': h.nextInt(6),
          'mort': 0,
          'don': 0,
          'effectif_final': 0,
          'mort_repro': 0,
          'mort_jeune': 0,
          'don_repro': 0,
          'don_sevre': 0,
          'don_jeune': 0,
        },
      };
    }
  }

  DateTime? depuis;
  if (type == 'cascade') {
    final choix = DateTime.parse(
      fiches[h.nextInt(nb)]['entry_date'] as String,
    );
    // Parfois un jour SANS fiche (veille, ou le lendemain d'une fiche dans un trou).
    depuis = switch (h.nextInt(4)) {
      0 => DateTime(choix.year, choix.month, choix.day - 1),
      1 => DateTime(choix.year, choix.month, choix.day + 1),
      _ => choix,
    };
  }

  return Scenario(
    especeCode: especeCode,
    initial: initial,
    fiches: fiches,
    etats: etats,
    proposee: proposee,
    type: type,
    depuis: depuis,
  );
}
