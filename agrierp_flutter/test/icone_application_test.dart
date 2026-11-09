import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Ticket ENV1 (demande 2) — L'ICÔNE DE L'APPLICATION EST LE LOGO DE LA FERME, PARTOUT.
///
/// ⚠️ Ces tests LISENT LES FICHIERS : un `.ico` manquant ou mal référencé ne casse rien à l'exécution du poste de
/// développement, il donne seulement l'icône par défaut de Flutter sur le bureau du client. Ce que ni `flutter
/// analyze` ni un test de rendu ne voient. Le rendu réel (barre des tâches, raccourci, installateur) n'est vérifiable
/// que sur Windows : voir le ticket ENV1 de `README_SPRINT0.md`.
void main() {
  const ico = 'windows/runner/resources/app_icon.ico';
  const taillesAttendues = {16, 24, 32, 48, 64, 128, 256};

  /// Entrées du répertoire d'un `.ico` : (largeur, hauteur, profondeur, taille, décalage).
  List<({int largeur, int hauteur, int bits, int taille, int decalage})> repertoire(Uint8List o) {
    final d = ByteData.sublistView(o);
    expect(d.getUint16(0, Endian.little), 0, reason: 'réservé');
    expect(d.getUint16(2, Endian.little), 1, reason: 'type 1 = icône');
    final n = d.getUint16(4, Endian.little);
    return [
      for (var i = 0; i < n; i++)
        (
          largeur: d.getUint8(6 + 16 * i) == 0 ? 256 : d.getUint8(6 + 16 * i),
          hauteur: d.getUint8(7 + 16 * i) == 0 ? 256 : d.getUint8(7 + 16 * i),
          bits: d.getUint16(12 + 16 * i, Endian.little),
          taille: d.getUint32(14 + 16 * i, Endian.little),
          decalage: d.getUint32(18 + 16 * i, Endian.little),
        ),
    ];
  }

  test("l'.ico contient exactement les tailles 16, 24, 32, 48, 64, 128 et 256 px, carrées, en 32 bits", () {
    final entrees = repertoire(File(ico).readAsBytesSync());
    expect({for (final e in entrees) e.largeur}, taillesAttendues);
    expect(entrees.length, taillesAttendues.length, reason: 'une seule entrée par taille');
    for (final e in entrees) {
      expect(e.hauteur, e.largeur, reason: 'jamais étiré : entrée carrée');
      expect(e.bits, 32);
    }
  });

  test("chaque entrée est lisible : 256 px en PNG, les autres en BMP (BGRA + masque) de la bonne taille", () {
    final o = File(ico).readAsBytesSync();
    final d = ByteData.sublistView(o);
    for (final e in repertoire(o)) {
      expect(e.decalage + e.taille, lessThanOrEqualTo(o.length), reason: '${e.largeur} px : entrée tronquée');
      if (e.largeur == 256) {
        expect(o.sublist(e.decalage, e.decalage + 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
            reason: '256 px en PNG');
      } else {
        final n = e.largeur;
        expect(d.getUint32(e.decalage, Endian.little), 40, reason: '$n px : BITMAPINFOHEADER');
        expect(d.getInt32(e.decalage + 4, Endian.little), n);
        expect(d.getInt32(e.decalage + 8, Endian.little), n * 2, reason: 'hauteur doublée (image + masque)');
        expect(d.getUint16(e.decalage + 14, Endian.little), 32);
        final attendu = 40 + n * n * 4 + ((n + 31) ~/ 32) * 4 * n;
        expect(e.taille, attendu, reason: '$n px : taille BMP');
      }
    }
  });

  test("l'.ico est bien celui que le script produit depuis assets/images/logo.png (le logo, pas une autre image)", () {
    // Le script est du code du dépôt, pas une entrée non fiable : pas d'option `-I` (mode isolé), qui ignorerait les
    // paquets installés « pour l'utilisateur » (`pip install` sans droits d'administrateur sous Windows : AppData\\Roaming).
    // Candidats : `python3` (Linux, macOS), `python`, puis le lanceur `py -3` de Windows ; `python3` peut y être un simple
    // raccourci du Microsoft Store qui ne lance rien.
    const candidats = <(String, List<String>)>[
      ('python3', <String>[]),
      ('python', <String>[]),
      ('py', <String>['-3']),
    ];
    ProcessResult? r;
    for (final (exe, args) in candidats) {
      try {
        final essai = Process.runSync(exe, [...args, 'outils/generer_icone.py', '--verifier']);
        if ('${essai.stderr}'.contains('No module named')) {
          r = essai; // cet interpréteur n'a pas Pillow : on essaie le suivant
          continue;
        }
        if (essai.exitCode != 0 && '${essai.stderr}${essai.stdout}'.contains('Python was not found')) continue;
        r = essai;
        break;
      } on ProcessException {
        continue;
      }
    }
    if (r == null) {
      markTestSkipped('Python introuvable');
      return;
    }
    if ('${r.stderr}'.contains('No module named')) {
      markTestSkipped('Pillow absent de tous les interpréteurs essayés (pip install pillow) : ${r.stderr}');
      return;
    }
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  }, timeout: const Timeout(Duration(minutes: 1)));

  test("Runner.rc référence l'.ico pour IDI_APP_ICON, dont resource.h donne l'identifiant", () {
    final rc = File('windows/runner/Runner.rc').readAsStringSync();
    expect(RegExp(r'IDI_APP_ICON\s+ICON\s+"resources\\\\app_icon\.ico"').hasMatch(rc), isTrue);
    expect(File('windows/runner/resource.h').readAsStringSync(), contains('#define IDI_APP_ICON'));
    // L'icône DOIT rester la première ressource du .rc : c'est celle que l'Explorateur montre pour l'exécutable.
    expect(rc.indexOf('IDI_APP_ICON            ICON'), lessThan(rc.indexOf('VS_VERSION_INFO')));
  });

  test("la fenêtre charge cette icône en grande et en petite taille (barre des tâches, Alt+Tab, titre)", () {
    final fen = File('windows/runner/win32_window.cpp').readAsStringSync();
    expect(fen, contains('MAKEINTRESOURCE(IDI_APP_ICON)'));
    expect(fen, contains('WM_SETICON'));
    expect(fen, contains('ICON_BIG'));
    expect(fen, contains('ICON_SMALL'));
    expect(fen, contains('SM_CXICON'));
    expect(fen, contains('SM_CXSMICON'));
    expect(fen, contains('hIconSm'), reason: 'classe enregistrée avec sa petite icône');
  });

  test("le titre de la fenêtre est celui de l'application", () {
    expect(File('windows/runner/main.cpp').readAsStringSync(), contains('L"LogiAgriERP - Ferme Ecole OLOUWACHEGOUN"'));
  });

  test("l'installateur utilise l'.ico : assistant, programme désinstallable et raccourcis", () {
    final iss = File('installer/agrierp.iss').readAsStringSync();
    expect(iss, contains(r'SetupIconFile=..\windows\runner\resources\app_icon.ico'));
    expect(iss, contains(r'UninstallDisplayIcon={app}\agrierp.exe'));
    // Chaque raccourci nomme l'icône explicitement (celle de l'exécutable) plutôt que de s'en remettre au défaut.
    final raccourcis = RegExp(r'^Name: "\{(group|autodesktop)\}\\LogiAgriERP".*$', multiLine: true).allMatches(iss).toList();
    expect(raccourcis.length, 2);
    for (final r in raccourcis) {
      expect(r.group(0), contains(r'IconFilename: "{app}\agrierp.exe"'));
    }
    // Le fichier désigné existe bien dans le dépôt.
    expect(File('installer/../windows/runner/resources/app_icon.ico').existsSync(), isTrue);
  });

  test("build_windows.bat refuse de construire sans l'.ico, et le dossier Release l'embarque dans l'exécutable", () {
    final bat = File('build_windows.bat').readAsStringSync();
    expect(bat, contains(r'windows\runner\resources\app_icon.ico'));
    // L'icône de agrierp.exe vient de Runner.rc (ressource) : la CMake du runner compile bien ce fichier.
    expect(File('windows/runner/CMakeLists.txt').readAsStringSync(), contains('"Runner.rc"'));
  });
}
