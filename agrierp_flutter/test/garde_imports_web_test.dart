import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PWA-2b — GARDE-FOU WINDOWS : aucun import propre au navigateur (`dart:html`, `dart:js_interop`, `dart:js_util`, `package:web`)
/// hors d'un fichier `*_web.dart`, et jamais d'import `dart:io` / `dart:ffi` / `drift/native.dart` dans un fichier `*_web.dart`
/// ni dans `app_database.dart` (ce qui casse la compilation web) ; chaque `if (dart.library.js_interop)` désigne un fichier
/// `_web.dart` existant, et son pendant `_native.dart` existe.
void main() {
  final fichiers = [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart') && !f.path.endsWith('.g.dart')) f,
  ];
  final importNavigateur = RegExp(r'''^\s*(import|export)\s+['"](dart:html|dart:js_interop|dart:js_util|dart:js|package:web/)''', multiLine: true);
  final importNatif = RegExp(r'''^\s*(import|export)\s+['"](dart:io|dart:ffi|package:drift/native\.dart)''', multiLine: true);

  test('aucun import propre au navigateur hors des fichiers *_web.dart', () {
    final fautifs = [
      for (final f in fichiers)
        if (!f.path.endsWith('_web.dart') && importNavigateur.hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(fautifs, isEmpty);
  });

  test('aucun import natif (dart:io, dart:ffi, drift/native) dans un fichier *_web.dart ni dans app_database.dart', () {
    final fautifs = [
      for (final f in fichiers)
        if ((f.path.endsWith('_web.dart') || f.path.endsWith('app_database.dart')) && importNatif.hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(fautifs, isEmpty);
  });

  test('chaque import conditionnel js_interop désigne un fichier _web.dart et son pendant _native.dart', () {
    final conditionnel = RegExp(r'''['"]([\w/.]+_native\.dart)['"]\s+if\s*\(dart\.library\.js_interop\)\s*['"]([\w/.]+_web\.dart)['"]''');
    var vus = 0;
    for (final f in fichiers) {
      for (final m in conditionnel.allMatches(f.readAsStringSync())) {
        vus++;
        final dossier = f.parent.path;
        expect(File('$dossier/${m.group(1)}').existsSync(), isTrue, reason: '${f.path} : ${m.group(1)} manquant');
        expect(File('$dossier/${m.group(2)}').existsSync(), isTrue, reason: '${f.path} : ${m.group(2)} manquant');
      }
    }
    expect(vus, greaterThanOrEqualTo(5), reason: 'ouverture_base, fichiers_poste, ouvreur_url, justificatifs, evenements');
  });
}
