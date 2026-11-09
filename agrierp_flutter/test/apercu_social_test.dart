import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Aperçu de partage du produit (1280×640) : la même image au web et au poste ; l'éditeur de l'installateur ne cite
/// plus la ferme (« Dr MASSENON Rhodes » seul).
void main() {
  test('l\'image d\'aperçu du poste est celle du web, déclarée dans pubspec', () {
    final poste = File('assets/images/social-preview.png');
    final web = File('$dossierLaravel/public/assets/images/social-preview.png');
    expect(poste.existsSync(), isTrue);
    if (!web.existsSync()) {
      markTestSkipped('dépôt Laravel absent');
      return;
    }
    expect(poste.readAsBytesSync(), web.readAsBytesSync());
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/images/social-preview.png'));
    // En-tête PNG : 1280 × 640.
    final o = poste.readAsBytesSync();
    int lire(int i) => (o[i] << 24) | (o[i + 1] << 16) | (o[i + 2] << 8) | o[i + 3];
    expect([lire(16), lire(20)], [1280, 640]);
  });

  test('le poste web porte les balises de partage', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('property="og:image"'));
    expect(html, contains('social-preview.png'));
  });

  test('l\'éditeur de l\'installateur est « Dr MASSENON Rhodes », sans la ferme', () {
    final iss = File('installer/agrierp.iss').readAsStringSync();
    final ligne = RegExp(r'^AppPublisher=(.*)$', multiLine: true).firstMatch(iss)!.group(1)!.trim();
    expect(ligne, 'Dr MASSENON Rhodes');
    expect(ligne.toLowerCase(), isNot(contains('ferme')));
  });
}
