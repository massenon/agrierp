import 'dart:io';

import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/rapports/rapports_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.86-bis — UN MONTANT ARRONDI À ZÉRO NE PORTE JAMAIS DE SIGNE.
///
/// Réserve de l'audit indépendant de F0.86 : le `_montant` de la Balance testait le signe sur la
/// valeur BRUTE (`valeur < 0 ? '-' : ''`) puis écrivait la valeur ARRONDIE : un écart de -0,4 sortait
/// « -0 F ». Le serveur écrit « 0 F » : `number_format(-0.4, 0, ',', ' ')` (PHP 8.3.30, mesuré :
/// -0,4 → « 0 », -0,49 → « 0 », -0,5 → « -1 », -0,6 → « -1 », -1 234,4 → « -1 234 »,
/// -12 345,6 → « -12 346 »).
///
/// Le MÊME mécanisme était recopié dans quinze formateurs du poste (un seul, celui du bilan
/// technico-économique, testait déjà le signe sur l'arrondi). Les trois formateurs PUBLICS sont
/// testés ici sur leur comportement ; les douze copies PRIVÉES (dans des `State` d'écran) sont
/// tenues par le garde-fou sur le source plus bas, et la Balance / le Grand Livre par leurs tests
/// d'écran (`balance_poste_test.dart`, `grand_livre_poste_test.dart`).
void main() {
  /// Attendus écrits À LA MAIN d'après la mesure PHP ci-dessus, jamais obtenus du code testé.
  const attendus = <(double, String)>[
    (-0.4, '0'),
    (-0.49, '0'),
    (-0.0, '0'),
    (0.4, '0'),
    (-0.5, '-1'),
    (-0.6, '-1'),
    (-1234.4, '-1 234'),
    (-12345.6, '-12 346'),
    (1234567, '1 234 567'),
    (999, '999'),
    (1000, '1 000'),
  ];

  final formateurs = <String, String Function(double)>{
    'RapportsRepository.montant': RapportsRepository.montant,
    'AchatsRepository.montant': AchatsRepository.montant,
    'DocumentsAvances.formaterMontant': DocumentsAvances.formaterMontant,
  };

  for (final MapEntry(key: nom, value: f) in formateurs.entries) {
    test('⚠️⚠️ $nom : jamais « -0 », signe et milliers comme le serveur', () {
      for (final (v, texte) in attendus) {
        expect(f(v), texte, reason: '$nom($v)');
      }
    });
  }

  group('garde-fou sur le source : le signe se teste sur l ARRONDI', () {
    // ⚠️ Lit le SOURCE, délibérément : les copies privées ne sont pas appelables d'un test, et le
    // défaut est invisible à l'exécution tant qu'aucune valeur de ]-0,5 ; 0[ n'arrive à l'écran.
    final fichiers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .toList();

    // Formateur « maison » : la partie entière vient de `x.round().abs()`.
    final formateur = RegExp(r'(\w+)\.round\(\)\.abs\(\)');
    // Signe testé sur la valeur BRUTE : `${valeur < 0 ? '-' : ''}`.
    final signeBrut = RegExp(r"\$\{\s*\w+\s*<\s*0\s*\?\s*'-'");

    test('aucun formateur ne teste le signe sur la valeur brute', () {
      final fautifs = <String>[];
      var vus = 0;
      for (final f in fichiers) {
        final source = f.readAsStringSync();
        if (!formateur.hasMatch(source)) continue;
        vus++;
        for (final m in signeBrut.allMatches(source)) {
          final ligne =
              '\n'.allMatches(source.substring(0, m.start)).length + 1;
          fautifs.add('${f.path}:$ligne');
        }
      }
      // Quinze au ticket F0.86-bis : si ce nombre tombe à zéro, le motif ne voit plus rien et le
      // garde-fou passerait en silence.
      expect(vus, greaterThanOrEqualTo(15));
      expect(fautifs, isEmpty, reason: 'signe testé avant arrondi : « -0 »');
    });

    test('chaque formateur teste le signe sur `x.round() < 0`', () {
      final sansSigneArrondi = <String>[];
      for (final f in fichiers) {
        final source = f.readAsStringSync();
        for (final m in formateur.allMatches(source)) {
          final variable = m.group(1)!;
          if (!source.contains("\${$variable.round() < 0 ? '-' : ''}")) {
            sansSigneArrondi.add('${f.path} ($variable)');
          }
        }
      }
      expect(sansSigneArrondi, isEmpty);
    });
  });
}
