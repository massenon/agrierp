import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrierp/core/config/fichiers_entreprise.dart';
import 'package:agrierp/core/widgets/logo_entreprise.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket CONF-1 — LOGO ET FAVICON DU POSTE : mêmes formats, mêmes messages que le web, logo choisi dans l'interface.
void main() {
  final png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));
  final ico = Uint8List.fromList([0, 0, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0, 32, 0, 4, 0, 0, 0, 22, 0, 0, 0, 0, 0, 0, 0]);
  final webp = Uint8List.fromList(base64Decode('UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA=='));
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0x49, 0x46]);

  group('formats (en-tête binaire, jamais le seul nom)', () {
    test('logo : PNG, JPG et WEBP acceptés', () {
      expect(FichiersEntreprise.valider('logo', 'a.png', png), isNull);
      expect(FichiersEntreprise.valider('logo', 'a.jpg', jpeg), isNull);
      expect(FichiersEntreprise.valider('logo', 'a.jpeg', jpeg), isNull);
      expect(FichiersEntreprise.valider('logo', 'a.webp', webp), isNull);
    });

    test('logo : ICO, GIF, SVG, texte nommé .png et extension inconnue refusés avec le message exact', () {
      const message = 'Le logo doit être une image PNG, JPG ou WEBP.';
      expect(FichiersEntreprise.valider('logo', 'a.ico', ico), message);
      expect(FichiersEntreprise.valider('logo', 'a.gif', Uint8List.fromList('GIF89a....'.codeUnits)), message);
      expect(FichiersEntreprise.valider('logo', 'a.svg', Uint8List.fromList('<svg/>'.codeUnits)), message);
      expect(FichiersEntreprise.valider('logo', 'a.png', Uint8List.fromList('du texte'.codeUnits)), message);
      expect(FichiersEntreprise.valider('logo', 'a.exe', png), message);
    });

    test('favicon : ICO et PNG acceptés, WEBP et ICO tronqué refusés', () {
      const message = "L'icône du site doit être un fichier ICO ou PNG.";
      expect(FichiersEntreprise.valider('favicon', 'f.ico', ico), isNull);
      expect(FichiersEntreprise.valider('favicon', 'f.png', png), isNull);
      expect(FichiersEntreprise.valider('favicon', 'f.webp', webp), message);
      expect(FichiersEntreprise.valider('favicon', 'f.ico', Uint8List.fromList([0, 0, 1, 0, 5, 0, 1, 1])), message);
      expect(FichiersEntreprise.valider('favicon', 'f.ico', Uint8List.fromList([0, 0, 2, 0, 1, 0, ...ico.skip(6)])), message);
    });

    test('tailles : logo 2 Mo, favicon 500 Ko', () {
      expect(FichiersEntreprise.valider('logo', 'a.png', Uint8List.fromList([...png, ...Uint8List(2 * 1024 * 1024)])), 'Le logo ne doit pas dépasser 2 Mo.');
      expect(FichiersEntreprise.valider('favicon', 'f.png', Uint8List.fromList([...png, ...Uint8List(501 * 1024)])), "L'icône du site ne doit pas dépasser 500 Ko.");
      expect(FichiersEntreprise.valider('favicon', 'f.png', Uint8List.fromList([...png, ...Uint8List(400 * 1024)])), isNull);
    });
  });

  group('parité avec le web', () {
    test('⚠️ les messages sont ceux de lang/fr/validation.php (groupe fichiers_entreprise), mot pour mot', () {
      final fichier = File('$dossierLaravel/lang/fr/validation.php');
      if (!fichier.existsSync()) {
        markTestSkipped('agrierp_laravel introuvable (AGRIERP_LARAVEL) : parité des messages non vérifiée.');
        return;
      }
      final php = fichier.readAsStringSync();
      for (final genre in FichiersEntreprise.messages.keys) {
        for (final motif in ['format', 'taille']) {
          final attendu = FichiersEntreprise.messages[genre]![motif]!;
          final entreGuillemets = '"${attendu.replaceAll('"', r'\"')}"';
          final entreApostrophes = "'${attendu.replaceAll("'", r"\'")}'";
          expect(php.contains(entreGuillemets) || php.contains(entreApostrophes), isTrue, reason: '$genre.$motif : « $attendu » absent du fichier de langue');
        }
      }
    });

    test('⚠️ les textes d\'aide et le glisser-déposer du Blade sont repris (hors glisser-déposer, impossible sans paquet au poste)', () {
      final blade = File('$dossierLaravel/resources/views/livewire/parametres/donnees-entreprise.blade.php');
      if (!blade.existsSync()) {
        markTestSkipped('agrierp_laravel introuvable : parité de la vue non vérifiée.');
        return;
      }
      final texte = blade.readAsStringSync();
      final ui = File('lib/features/parametres/reglages_ferme_ui.dart').readAsStringSync();
      for (final aide in ['PNG carré, fond transparent recommandé, max 2 Mo', 'ICO ou PNG 32x32px, max 500 Ko']) {
        expect(texte, contains(aide));
        expect(ui, contains(aide));
      }
      expect(ui, contains('SymbolesAgri.add_photo_alternate'));
      expect(ui, contains("'Supprimer'"));
    });
  });

  group('logo dans l\'interface', () {
    late Directory dossier;

    setUp(() async {
      dossier = await Directory.systemTemp.createTemp('logo_ui');
      FichiersEntreprise.courant = FichiersEntreprise(dossier: () async => dossier);
    });
    tearDown(() async {
      FichiersEntreprise.courant = FichiersEntreprise();
      await dossier.delete(recursive: true);
    });

    testWidgets('sans logo choisi : l\'icône d\'installation ; avec : l\'image, redessinée au changement', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LogoEntreprise(taille: 30, couleurRepli: Colors.yellow)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byKey(const Key('logo-entreprise')), findsNothing);
      expect(find.byType(Icon), findsOneWidget);

      await tester.runAsync(() => FichiersEntreprise.courant.enregistrer('logo', png, 'logo.png'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byKey(const Key('logo-entreprise')), findsOneWidget);

      await tester.runAsync(() => FichiersEntreprise.courant.effacer('logo'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byKey(const Key('logo-entreprise')), findsNothing);
    });

    test('la barre latérale et la connexion emploient le composant (jamais l\'icône en dur)', () {
      for (final f in ['lib/main.dart', 'lib/features/auth/login_screen.dart']) {
        final src = File(f).readAsStringSync();
        expect(src, contains('LogoEntreprise('), reason: f);
        expect(src.contains('const Icon(SymbolesAgri.agriculture') || RegExp(r'const Icon\(\s*SymbolesAgri\.agriculture').hasMatch(src), isFalse, reason: f);
      }
    });
  });
}
