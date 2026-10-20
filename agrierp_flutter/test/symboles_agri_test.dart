import 'dart:io';
import 'dart:typed_data';

import 'package:agrierp/core/theme/symboles_agri.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket H1 — les icônes du poste sont celles du web : Material Symbols OUTLINED.
///
/// ⚠️ Ce que ces tests verrouillent ne se voit à aucune exécution : une `Icons.x` rend une icône PLEINE (autre
/// silhouette que le web) sans erreur, et un point de code absent de la fonte embarquée rend un carré vide —
/// toujours sans erreur. Seule la lecture du source et de la fonte les attrape.
void main() {
  final fonte = File('assets/fonts/MaterialSymbolsOutlined.ttf');
  final classe = File('lib/core/theme/symboles_agri.dart').readAsStringSync();

  test('aucune icône Flutter (Icons) dans lib/ : toutes les icônes passent par SymbolesAgri', () {
    final fautifs = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lignes = f.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        final code = lignes[i].split('//').first;
        if (RegExp(r'\bIcons\.[a-z_0-9]+').hasMatch(code)) fautifs.add('${f.path}:${i + 1}');
      }
    }
    expect(fautifs, isEmpty, reason: 'lancer `py outils/icones_poste.py --remplacer`');
  });

  test('la fonte est embarquée et déclarée sous la famille de SymbolesAgri', () {
    expect(fonte.existsSync(), isTrue);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: ${SymbolesAgri.famille}'));
    expect(pubspec, contains('asset: assets/fonts/MaterialSymbolsOutlined.ttf'));
  });

  test('🔴 chaque icône de SymbolesAgri a son glyphe dans la fonte embarquée (sinon : carré vide)', () {
    final points = RegExp(r'IconData\(0x([0-9a-f]+), fontFamily: famille\)')
        .allMatches(classe)
        .map((m) => int.parse(m.group(1)!, radix: 16))
        .toSet();
    expect(points.length, greaterThan(100));

    final cmap = _pointsDeCode(fonte.readAsBytesSync());
    expect(points.difference(cmap), isEmpty);
  });

  test('toutes les constantes portent la famille Material Symbols Outlined', () {
    expect(SymbolesAgri.famille, 'MaterialSymbolsOutlined');
    expect(SymbolesAgri.dashboard.fontFamily, 'MaterialSymbolsOutlined');
    expect(SymbolesAgri.dashboard.fontPackage, isNull);
    expect(RegExp(r'IconData\(').allMatches(classe).length,
        RegExp(r'fontFamily: famille\)').allMatches(classe).length);
  });
}

/// Points de code de la table `cmap` d'une fonte TrueType (sous-tables de format 4 et 12).
Set<int> _pointsDeCode(Uint8List octets) {
  final d = ByteData.sublistView(octets);
  final tables = d.getUint16(4);
  var cmap = -1;
  for (var i = 0; i < tables; i++) {
    final e = 12 + 16 * i;
    if (String.fromCharCodes(octets.sublist(e, e + 4)) == 'cmap') cmap = d.getUint32(e + 8);
  }
  if (cmap < 0) return {};

  final points = <int>{};
  final sousTables = d.getUint16(cmap + 2);
  for (var i = 0; i < sousTables; i++) {
    final st = cmap + d.getUint32(cmap + 4 + 8 * i + 4);
    switch (d.getUint16(st)) {
      case 4:
        final segments = d.getUint16(st + 6) ~/ 2;
        final fins = st + 14;
        final debuts = fins + 2 * segments + 2;
        for (var s = 0; s < segments; s++) {
          final debut = d.getUint16(debuts + 2 * s);
          final fin = d.getUint16(fins + 2 * s);
          if (debut == 0xFFFF) continue;
          for (var c = debut; c <= fin; c++) {
            points.add(c);
          }
        }
      case 12:
        final groupes = d.getUint32(st + 12);
        for (var g = 0; g < groupes; g++) {
          final debut = d.getUint32(st + 16 + 12 * g);
          final fin = d.getUint32(st + 20 + 12 * g);
          for (var c = debut; c <= fin; c++) {
            points.add(c);
          }
        }
    }
  }
  return points;
}
