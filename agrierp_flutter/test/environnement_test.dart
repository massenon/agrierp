import 'dart:io';

import 'package:agrierp/core/config/environnement.dart';
import 'package:agrierp/core/config/parametres_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket S-T8 (méthode TATACORA, § 1) — environnement de construction du poste, adresse du serveur par défaut,
/// refus de la version démo en production.
///
/// ⚠️ `build_windows.bat` et `installer/agrierp.iss` ne s'exécutent pas ici (ni Windows ni Inno Setup) : leur
/// contrat est vérifié EN LISANT leur texte, comme les garde-fous de portage.
void main() {
  group('S-T8 — environnements', () {
    test('trois environnements, leurs codes et leurs adresses', () {
      expect(Environnement.codes, ['dev', 'recette', 'production']);
      expect(Environnement.developpement.adresseParDefaut, 'http://127.0.0.1:8002');
      expect(Environnement.production.adresseParDefaut, 'https://agrierp.fermeolouwachegoun.com');
      expect(Environnement.recette.adresseParDefaut, startsWith('https://'));
    });

    test('sans --dart-define : production (un poste livré ne dépend pas d\'un oubli)', () {
      expect(Environnement.codeCompile, 'production');
      expect(Environnement.courant, Environnement.production);
      expect(ParametresPoste.adresseParDefaut, 'https://agrierp.fermeolouwachegoun.com');
    });

    test('lecture du code : casse et blancs ignorés ; ⚠️ un code inconnu retombe sur la PRODUCTION', () {
      expect(Environnement.depuisCode('dev'), Environnement.developpement);
      expect(Environnement.depuisCode(' Recette '), Environnement.recette);
      expect(Environnement.depuisCode('PRODUCTION'), Environnement.production);
      expect(Environnement.depuisCode('recete'), Environnement.production);
      expect(Environnement.depuisCode(''), Environnement.production);
    });

    test('ParametresPoste part de l\'adresse de son environnement ; l\'adresse enregistrée l\'emporte', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final recette = ParametresPoste(database: db, environnement: Environnement.recette);
      expect(await recette.adresseServeur(), Environnement.recette.adresseParDefaut);
      expect(
        await ParametresPoste(database: db, environnement: Environnement.developpement).adresseServeur(),
        'http://127.0.0.1:8002',
      );

      await recette.definirAdresseServeur('https://autre.exemple/');
      expect(await recette.adresseServeur(), 'https://autre.exemple');
    });
  });

  group('S-T8 — version démo', () {
    test('une version démo porte le suffixe -demo (ou -demo.N)', () {
      for (final v in ['1.0.0-demo+1', '1.2.3-demo', '1.0.0-DEMO+4', '2.0.0-demo.2+7']) {
        expect(Environnement.estVersionDemo(v), isTrue, reason: v);
      }
      for (final v in ['1.0.0+1', '1.0.0', '1.0.0-rc1+1', '1.0.0-demonstration+1', 'demo']) {
        expect(Environnement.estVersionDemo(v), isFalse, reason: v);
      }
    });

    test('refusée en production, permise en recette et en développement', () {
      expect(
        Environnement.refusDeConstruction(version: '1.0.0-demo+1', environnement: Environnement.production),
        'Version démo « 1.0.0-demo+1 » : construction refusée pour la production.',
      );
      expect(Environnement.refusDeConstruction(version: '1.0.0-demo+1', environnement: Environnement.recette), isNull);
      expect(
        Environnement.refusDeConstruction(version: '1.0.0-demo+1', environnement: Environnement.developpement),
        isNull,
      );
      expect(Environnement.refusDeConstruction(version: '1.0.0+1', environnement: Environnement.production), isNull);
    });

    test('la version de pubspec.yaml n\'est pas une version démo (le dépôt construit pour la production)', () {
      final ligne = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
      expect(Environnement.estVersionDemo(ligne.substring('version:'.length)), isFalse);
    });
  });

  group('S-T8 — build_windows.bat et agrierp.iss (lus, non exécutés)', () {
    final bat = File('build_windows.bat');
    final iss = File('installer/agrierp.iss');
    late String script;
    late List<String> lignes;

    setUpAll(() {
      script = bat.readAsStringSync();
      lignes = script.split('\n').map((l) => l.replaceAll('\r', '')).toList();
    });

    test('fins de ligne CRLF et texte ASCII : cmd.exe lit mal un .bat en LF ou en UTF-8', () {
      final octets = bat.readAsBytesSync();
      expect(octets.every((o) => o < 0x80), isTrue, reason: 'caractère non ASCII dans le .bat');
      final lf = '\n'.allMatches(script).length;
      final crlf = '\r\n'.allMatches(script).length;
      expect(crlf, lf, reason: 'chaque fin de ligne doit être CRLF');
    });

    test('les environnements acceptés par le script sont exactement ceux de environnement.dart', () {
      final liste = RegExp(r'for %%e in \(([^)]*)\) do').firstMatch(script);
      expect(liste, isNotNull);
      expect(liste![1]!.trim().split(RegExp(r'\s+')), Environnement.codes);
      expect(script, contains('set "ENVIRONNEMENT=production"'), reason: 'défaut : production');
    });

    test('l\'environnement est passé à la compilation release', () {
      final build = lignes.where((l) => l.contains('flutter build windows')).toList();
      expect(build, hasLength(1));
      expect(build.single, contains('--release'));
      expect(build.single, contains('--dart-define=AGRIERP_ENV=%ENVIRONNEMENT%'));
    });

    test('⚠️ version démo refusée en production, AVANT toute compilation', () {
      final refus = script.indexOf('if "%DEMO%"=="1" if /i "%ENVIRONNEMENT%"=="production" (');
      expect(refus, greaterThan(0));
      expect(script.indexOf('exit /b 1', refus), greaterThan(refus));
      expect(refus, lessThan(script.indexOf('flutter pub get')), reason: 'refuser avant de compiler');
      // Le suffixe est reconnu comme dans environnement.dart : -demo, puis rien ou .N.
      expect(script, contains('if /i not "%DEBUT%"=="demo" goto :version_invalide'));
      expect(script, contains(r'findstr /r /x "\.[0-9][0-9]*"'));
    });

    test('syntaxe : étiquettes atteintes et définies, parenthèses équilibrées, pas de tube dans un bloc', () {
      final etiquettes = {
        for (final l in lignes)
          if (RegExp(r'^:(\w+)\s*$').hasMatch(l)) RegExp(r'^:(\w+)').firstMatch(l)![1]!,
      };
      final sauts = RegExp(r'goto :(\w+)').allMatches(script).map((m) => m[1]!).toSet();
      expect(etiquettes.containsAll(sauts), isTrue, reason: 'goto vers une étiquette absente : ${sauts.difference(etiquettes)}');

      // Parenthèses : hors commentaires, hors `^(` / `^)` échappées et hors chaînes entre guillemets.
      var profondeur = 0;
      var tubeDansUnBloc = <String>[];
      for (final l in lignes) {
        final t = l.trimLeft();
        if (t.toLowerCase().startsWith('rem ') || t.startsWith('::')) continue;
        final sansChaines = t.replaceAll(RegExp(r'"[^"]*"'), '""').replaceAll('^(', '').replaceAll('^)', '').replaceAll('^|', '');
        if (profondeur > 0 && sansChaines.contains('|') && sansChaines.contains('!')) tubeDansUnBloc.add(l);
        profondeur += '('.allMatches(sansChaines).length - ')'.allMatches(sansChaines).length;
        expect(profondeur, greaterThanOrEqualTo(0), reason: 'parenthèse fermante orpheline : $l');
      }
      expect(profondeur, 0, reason: 'bloc non refermé');
      expect(tubeDansUnBloc, isEmpty, reason: 'variable retardée dans un tube au sein d\'un bloc');
    });

    test('l\'installateur reçoit version, partie numérique, environnement et nom ; son nom est vérifié', () {
      final iscc = lignes.singleWhere((l) => l.contains('"%ISCC%"'));
      for (final d in [
        '/DAppVersion=%VERSION_COURTE%',
        '/DAppVersionNum=%VERSION_NUM%',
        '/DAppEnv=%ENVIRONNEMENT%',
        '/DNomInstallateur=%NOM_INSTALLATEUR%',
      ]) {
        expect(iscc, contains(d));
      }
      expect(script, contains(r'if not exist "installer\Output\%NOM_INSTALLATEUR%.exe"'));
    });

    test('agrierp.iss : refus de la démo en production aussi à la compilation directe, version numérique', () {
      final source = iss.readAsStringSync();
      expect(source, contains('#if (Pos("-demo", LowerCase(AppVersion)) > 0) && (AppEnv == "production")'));
      expect(source, contains('#error'));
      expect(source, contains('VersionInfoVersion={#AppVersionNum}'));
      expect(source, contains('OutputBaseFilename={#NomInstallateur}'));
      expect(source, contains('AppId={{69B3D13F-4283-4B8E-ABD1-456845FC5182}'), reason: 'AppId inchangé');
      // Directives ISPP équilibrées.
      final si = RegExp(r'^#if', multiLine: true).allMatches(source).length;
      final fin = RegExp(r'^#endif', multiLine: true).allMatches(source).length;
      expect(si, fin);
    });
  });
}
