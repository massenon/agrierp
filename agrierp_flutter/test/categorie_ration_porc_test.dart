import 'package:agrierp/features/elevage/categorie_ration_porc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket F0.99 — LA CLÉ DES RATIONS PORCINES EST CELLE DU SERVEUR (`App\Support\CategorieRationPorc`).
///
/// Valeurs attendues lues dans la règle PHP (15.42), puis vérifiées en EXÉCUTANT cette règle sur chaque
/// libellé quand PHP et le dépôt Laravel sont présents (parité exécutée, jamais recopiée).
void main() {
  const attendus = <String, String?>{
    'Porc reproducteur': CategorieRationPorc.reproducteur,
    'Reproducteur': CategorieRationPorc.reproducteur,
    'REPRODUCTEUR (Truie/Verrat)': CategorieRationPorc.reproducteur,
    'Porcelet': CategorieRationPorc.porcelet,
    'Porcelet (Démarrage / Sevrage)': CategorieRationPorc.porcelet,
    'Jeune porc': CategorieRationPorc.marchand,
    'Jeune': CategorieRationPorc.marchand,
    ' jeune porc ': CategorieRationPorc.marchand,
    'Porc Marchand': CategorieRationPorc.marchand,
    'Jeune marchand': CategorieRationPorc.marchand,
    'Engraissement': CategorieRationPorc.marchand,
    'Jeune porc (Engraissement)': CategorieRationPorc.marchand,
    'Jeunes': null,
    'Jeune porcelet': CategorieRationPorc.porcelet,
    'Truie': null,
    'Lapin Sevré': null,
    '': null,
    ' Jeune': null,
  };

  for (final e in attendus.entries) {
    test('« ${e.key} » → ${e.value}', () {
      expect(CategorieRationPorc.cle(e.key), e.value);
    });
  }

  test('libellés, ordre et secours du serveur', () {
    expect(CategorieRationPorc.libelles, {
      CategorieRationPorc.reproducteur: 'Reproducteur',
      CategorieRationPorc.porcelet: 'Porcelet',
      CategorieRationPorc.marchand: 'Porc Marchand',
    });
    expect(CategorieRationPorc.ordre, [
      CategorieRationPorc.porcelet,
      CategorieRationPorc.marchand,
      CategorieRationPorc.reproducteur,
    ]);
    expect(CategorieRationPorc.rationsDeSecours, {
      CategorieRationPorc.reproducteur: 2000,
      CategorieRationPorc.porcelet: 300,
      CategorieRationPorc.marchand: 600,
    });
  });

  test(
    'parité exécutée : la règle PHP du serveur donne les mêmes clés',
    () {
      final libelles = [
        ...attendus.keys,
        for (final base in ['Jeune', 'Porcelet', 'Porc Marchand', 'Engraissement'])
          for (final bord in [' ', '\t', ' ', ' ', '﻿', '\u000C'])
            '$bord$base$bord',
      ];
      final sortie = executerPhp(r'''<?php
require 'vendor/autoload.php';
$libelles = json_decode(file_get_contents($argv[1]), true);
echo json_encode(array_map(fn ($l) => App\Support\CategorieRationPorc::cle($l), $libelles));
''', libelles) as List;
      for (var i = 0; i < libelles.length; i++) {
        expect(CategorieRationPorc.cle(libelles[i]), sortie[i], reason: '« ${libelles[i]} »');
      }
    },
    skip: sautSansPhp(),
  );
}
