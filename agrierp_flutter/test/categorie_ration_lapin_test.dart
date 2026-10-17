import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/categorie_ration_lapin.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.92 — PARITÉ DE LA CLÉ STABLE DES CATÉGORIES DE RATIONNEMENT
/// DES LAPINS avec `App\Support\CategorieRationLapin` (serveur, ticket 15.36).
///
/// 🔁 F0.96 — glossaire du 17/10/2026 : « Sous-mères » (30 g) et « Jeune » (60 g). Les valeurs attendues
/// ont été CONTRÔLÉES en exécutant la règle PHP du serveur sur chaque libellé de ce fichier.
///
/// ⚠️⚠️ **LE PIÈGE** : après la migration serveur 15.36, le barème descend
/// avec « Jeune » et « Lapin de Chair » au lieu de « Lapin Sevré » et « Jeune
/// Lapin (engraissement) ». Le poste rattachait l'effectif de la bande à une
/// ligne par `stageLabel.contains(stade)` : une bande au stade
/// `engraissement` ne trouvait plus « Lapin de Chair » — effectif 0, total
/// de provende faux, AUCUN message.
///
/// Le jeu de libellés ci-dessous est RECOPIÉ À LA MAIN de
/// `tests/Feature/GlossaireFicheLapinsTest.php`
/// (`test_la_cle_stable_classe_anciens_et_nouveaux_libelles_sans_confondre_chair_et_jeune`),
/// complété des cas que la règle PHP tranche sans que son test les cite.
void main() {
  group('clé stable — parité avec le serveur', () {
    // Jeu du serveur, mot pour mot.
    const jeuDuServeur = <String, String?>{
      'Reproducteur': CategorieRationLapin.reproducteur,
      'Lapine Mère / Reproducteur': CategorieRationLapin.reproducteur,
      'Jeune': CategorieRationLapin.chair,
      ' jeune ': CategorieRationLapin.chair,
      'Sevré': CategorieRationLapin.sousMeres,
      'Lapin Sevré': CategorieRationLapin.sousMeres,
      'Lapin Sevre': CategorieRationLapin.sousMeres,
      'Lapin de Chair': CategorieRationLapin.chair,
      // Contient « Jeune » : doit rester CHAIR (chair testé avant jeune).
      'Jeune Lapin (engraissement)': CategorieRationLapin.chair,
      'Jeune (engraissement)': CategorieRationLapin.chair,
      'Porcelet': null,
      '': null,
    };

    for (final e in jeuDuServeur.entries) {
      test('« ${e.key} » → ${e.value}', () {
        expect(CategorieRationLapin.cle(e.key), e.value);
      });
    }

    // Cas que la règle PHP tranche (Str::lower + Str::ascii + trim, puis
    // `str_contains` / égalité stricte pour « jeune »).
    const casDeduits = <String, String?>{
      'REPRODUCTEUR': CategorieRationLapin.reproducteur,
      'lapin de chair': CategorieRationLapin.chair,
      'LAPIN SEVRÉ': CategorieRationLapin.sousMeres,
      'Jeune Lapin (Engraissement)': CategorieRationLapin.chair,
      // « jeune » n'est reconnu QU'EN ÉGALITÉ STRICTE côté serveur.
      'Jeunes': null,
      'Jeune porc': null,
      'Lapereau': null,
      '   ': null,
      // Le stade technique de la bande passe par la même règle.
      'engraissement': CategorieRationLapin.chair,
      'reproduction': null,
      'croissance': null,
    };

    for (final e in casDeduits.entries) {
      test('cas déduit « ${e.key} » → ${e.value}', () {
        expect(CategorieRationLapin.cle(e.key), e.value);
      });
    }

    test('null → null', () {
      expect(CategorieRationLapin.cle(null), isNull);
    });

    // Ticket F0.93 — les deux AUTRES méthodes du test serveur qui interrogent
    // `CategorieRationLapin::cle`, recopiées mot pour mot :
    //  - `test_jeune_est_une_egalite_stricte_jamais_une_sous_chaine` (15.37) ;
    //  - `test_comportement_actuel_une_espace_unicode_autour_de_jeune_ne_donne_aucune_cle` (15.37).
    const egaliteStricteDuServeur = <String, String?>{
      'Jeune Lapin (engraissement)': CategorieRationLapin.chair,
      'Jeune (engraissement)': CategorieRationLapin.chair,
      'Jeunes': null,
      'Jeune porc': null,
      'Jeune.': null,
      'Jeune lapin': null,
      'Jeune': CategorieRationLapin.chair,
      'jeune': CategorieRationLapin.chair,
      'JEUNE': CategorieRationLapin.chair,
      ' Jeune ': CategorieRationLapin.chair,
      'Jéune': CategorieRationLapin.chair,
      'JÉUNE': CategorieRationLapin.chair,
    };
    for (final e in egaliteStricteDuServeur.entries) {
      test('égalité stricte (serveur) « ${e.key} » → ${e.value}', () {
        expect(CategorieRationLapin.cle(e.key), e.value);
      });
    }

    // 🔴 F0.93 — `trim()` de Dart retire les espaces Unicode, `trim()` de PHP
    // non : le poste donnait `chair` (ration du barème) là où le serveur donne
    // `null` (ration de secours).
    const unicodeDuServeur = <String, String?>{
      ' Jeune': null, // espace insécable avant
      'Jeune ': null, // espace insécable après
      ' Jeune': null, // cadratin avant
      'Jeune ': null, // cadratin après
      ' \tJeune\n':
          CategorieRationLapin.chair, // témoin : espaces ASCII retirées
    };
    for (final e in unicodeDuServeur.entries) {
      test('🔴 unicode (serveur) ${_visible(e.key)} → ${e.value}', () {
        expect(CategorieRationLapin.cle(e.key), e.value);
      });
    }

    // Cas MESURÉS le 14/10/2026 en exécutant la règle PHP elle-même
    // (`php` + `vendor/autoload.php`, lecture seule) : `trim()` PHP retire
    // « \x20 \t \n \r \0 \x0B » au bord ; PUIS `Str::ascii` change les espaces
    // Unicode en espace simple (qui reste : pas « jeune ») et SUPPRIME les
    // autres caractères de contrôle — d'où `\f`, U+FEFF et U+0085 qui donnent
    // `jeune`. Un simple « trim ASCII » aurait créé ces trois divergences-là.
    const mesuresSurLeServeur = <String, String?>{
      '\x0BJeune\r': CategorieRationLapin.chair,
      '\x00Jeune\x00': CategorieRationLapin.chair,
      '\x0CJeune': CategorieRationLapin
          .chair, // \f : non retiré par trim, supprimé par Str::ascii
      'Jeune\x0C': CategorieRationLapin.chair,
      '﻿Jeune': CategorieRationLapin.chair, // supprimé par Str::ascii
      '\u0085Jeune': CategorieRationLapin.chair, // supprimé par Str::ascii
      ' Jeune': null,
      '　Jeune': null,
      ' Jeune': null,
      ' Jeune': null,
      '​Jeune': null, // U+200B devient une espace
      'Jeu‌ne': CategorieRationLapin.chair, // U+200C est supprimé
      'J eune': null,
      'Jeu\tne': null, // \t intérieur : devient une espace, pas supprimé
      'Jeu\x0Cne': CategorieRationLapin.chair, // \f intérieur : supprimé
      'Jeu\x10ne':
          null, // U+0010 : CONSERVÉ par Str::ascii (bizarrerie mesurée)
      ' Lapin de Chair ': CategorieRationLapin.chair,
      ' Reproducteur': CategorieRationLapin.reproducteur,
      ' Lapin Sevré': CategorieRationLapin.sousMeres,
      '\t\t': null,
      ' ': null,
      'ponte': null,
    };
    for (final e in mesuresSurLeServeur.entries) {
      test('🔴 mesuré sur PHP ${_visible(e.key)} → ${e.value}', () {
        expect(CategorieRationLapin.cle(e.key), e.value);
      });
    }

    // 🔁 F0.96 — le stade se rattache par la règle du SERVEUR (`STADE_VERS_CATEGORIE`), plus par `cle`.
    test('stade de la bande : reproduction, croissance, engraissement (règle du serveur)', () {
      expect(
        CategorieRationLapin.cleDuStade('reproduction'),
        CategorieRationLapin.reproducteur,
      );
      expect(
        CategorieRationLapin.cleDuStade('croissance'),
        CategorieRationLapin.sousMeres,
      );
      expect(
        CategorieRationLapin.cleDuStade('engraissement'),
        CategorieRationLapin.chair,
      );
      for (final s in ['ponte', null, '', ' engraissement', 'Jeune']) {
        expect(CategorieRationLapin.cleDuStade(s), isNull, reason: '$s');
      }
    });
  });

  group('ration — barème d\'abord, secours ensuite', () {
    FeedRationStandard ligne(String libelle, double g, [String id = 'x']) =>
        FeedRationStandard(
          id: id.padRight(36, '0'),
          speciesCode: 'cuniculture',
          stageLabel: libelle,
          rationGPerDay: g,
        );

    // Rations VOLONTAIREMENT différentes des secours (150/40/70, comme le
    // serveur) : 120/30/60 lu ici voudrait dire « barème ignoré ».
    const jeux = <String, List<String>>{
      'anciens (seeder d\'avant)': [
        'Lapine Mère / Reproducteur',
        'Lapin Sevré',
        'Jeune Lapin (engraissement)',
      ],
      'intermédiaires (tests 14.11)': [
        'Reproducteur',
        'Sevré',
        'Jeune (engraissement)',
      ],
      'glossaire du 14/10/2026': ['Reproducteur', 'Lapin Sevré', 'Lapin de Chair'],
      // F0.96 — glossaire du 17/10/2026 (serveur 15.44), mot pour mot.
      'glossaire du 17/10/2026': ['Reproducteur', 'Sous-mères', 'Jeune'],
      'glossaire en casse libre': ['REPRODUCTEUR', 'sous-mères', 'jeune'],
    };

    for (final j in jeux.entries) {
      test('jeu ${j.key} : 150 / 40 / 70', () {
        final bareme = [
          ligne(j.value[0], 150, 'a'),
          ligne(j.value[1], 40, 'b'),
          ligne(j.value[2], 70, 'c'),
        ];
        expect(
          CategorieRationLapin.ration(
            bareme,
            CategorieRationLapin.reproducteur,
          ),
          150,
        );
        expect(
          CategorieRationLapin.ration(bareme, CategorieRationLapin.sousMeres),
          40,
        );
        expect(
          CategorieRationLapin.ration(bareme, CategorieRationLapin.chair),
          70,
        );
      });
    }

    test('barème vide : secours 120 / 30 / 60', () {
      expect(
        CategorieRationLapin.ration(
          const [],
          CategorieRationLapin.reproducteur,
        ),
        120,
      );
      expect(
        CategorieRationLapin.ration(const [], CategorieRationLapin.sousMeres),
        30,
      );
      expect(
        CategorieRationLapin.ration(const [], CategorieRationLapin.chair),
        60,
      );
    });

    test('libellés inconnus : secours 120 / 30 / 60', () {
      final bareme = [
        ligne('Lapereau', 999, 'a'),
        ligne('Jeunes', 888, 'b'),
        ligne('Porcelet', 777, 'c'),
      ];
      expect(
        CategorieRationLapin.ration(bareme, CategorieRationLapin.reproducteur),
        120,
      );
      expect(
        CategorieRationLapin.ration(bareme, CategorieRationLapin.sousMeres),
        30,
      );
      expect(
        CategorieRationLapin.ration(bareme, CategorieRationLapin.chair),
        60,
      );
    });

    test(
      'une catégorie absente retombe sur SON secours sans toucher aux autres',
      () {
        final bareme = [ligne('Sous-mères', 45)];
        expect(
          CategorieRationLapin.ration(bareme, CategorieRationLapin.sousMeres),
          45,
        );
        expect(
          CategorieRationLapin.ration(
            bareme,
            CategorieRationLapin.reproducteur,
          ),
          120,
        );
        expect(
          CategorieRationLapin.ration(bareme, CategorieRationLapin.chair),
          60,
        );
      },
    );

    test(
      'deux lignes d\'une même catégorie : la PREMIÈRE gagne (comme `first`)',
      () {
        final bareme = [
          ligne('Jeune Lapin (engraissement)', 65, 'a'),
          ligne('Lapin de Chair', 70, 'b'),
        ];
        expect(
          CategorieRationLapin.ration(bareme, CategorieRationLapin.chair),
          65,
        );
      },
    );

    test('libellés affichés : ceux de la décision client du 17/10/2026', () {
      expect(CategorieRationLapin.libelles, {
        CategorieRationLapin.reproducteur: 'Reproducteur',
        CategorieRationLapin.sousMeres: 'Sous-mères',
        CategorieRationLapin.chair: 'Jeune',
      });
      // Ordre d'affichage du web (fiche-lapins.blade.php) : Reproducteur, Jeune, Sous-mères.
      expect(CategorieRationLapin.ordre, [
        CategorieRationLapin.reproducteur,
        CategorieRationLapin.chair,
        CategorieRationLapin.sousMeres,
      ]);
      expect(CategorieRationLapin.rationsDeSecours, {
        CategorieRationLapin.reproducteur: 120,
        CategorieRationLapin.sousMeres: 30,
        CategorieRationLapin.chair: 60,
      });
    });
  });
}

/// Rend lisibles dans le nom d'un test les caractères invisibles.
String _visible(String s) {
  final sb = StringBuffer('«');
  for (final r in s.runes) {
    if (r < 0x21 || (r >= 0x7F && r <= 0xA0) || r >= 0x1680) {
      sb.write('U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}');
    } else {
      sb.writeCharCode(r);
    }
  }
  sb.write('»');
  return sb.toString();
}
