import 'dart:io';

import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/features/auth/login_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket ENV1 (demande 4) — LA PARTIE GAUCHE DE L'ÉCRAN DE CONNEXION MONTRE L'IMAGE DU WEB.
///
/// Le Blade (`livewire/auth/login.blade.php`) pose `assets/images/image_login.png` en fond du panneau gauche, sous un
/// voile `linear-gradient(180deg, rgba(5,46,22,0.10), rgba(0,33,13,0.55))`, `background-size: cover`. Le poste ne
/// déclarait pas l'image : le panneau n'était qu'un aplat dégradé. C'est « le même fichier, copié et non redessiné ».
///
/// ⚠️ Sans le fichier (poste de développement qui ne l'aurait pas commité), l'écran ne doit JAMAIS se casser :
/// panneau de repli aux couleurs de la marque. C'est ce que le dernier groupe prouve, en retirant l'image du lot
/// d'assets.
const _cheminImage = 'assets/images/image_login.png';

class _LotSansImage extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == _cheminImage) throw FlutterError('Unable to load asset: "$key".');
    return rootBundle.load(key);
  }
}

void main() {
  Future<void> afficher(WidgetTester tester, {double largeur = 1280, AssetBundle? lot}) async {
    tester.view.physicalSize = Size(largeur, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget ecran = MaterialApp(
      home: LoginScreen(auth: AuthService(client: Dio(), deviceName: 'poste-test'), onConnecte: () {}),
    );
    if (lot != null) ecran = DefaultAssetBundle(bundle: lot, child: ecran);
    await tester.pumpWidget(ecran);
    await tester.pumpAndSettle();
  }

  final blade = File('$dossierLaravel/resources/views/livewire/auth/login.blade.php');
  final fichierWeb = File('$dossierLaravel/public/assets/images/image_login.png');

  group("l'image est dans le dépôt du poste, déclarée, et c'est celle du web", () {
    test("pubspec.yaml déclare assets/images/image_login.png", () {
      expect(File('pubspec.yaml').readAsStringSync(), contains('    - $_cheminImage'));
    });

    test("le fichier existe, n'est pas vide, et est un vrai JPEG ou PNG", () {
      final f = File(_cheminImage);
      expect(f.existsSync(), isTrue, reason: 'à copier depuis agrierp_laravel/public/assets/images/');
      final octets = f.readAsBytesSync();
      expect(octets.length, greaterThan(10000));
      final png = octets[0] == 0x89 && octets[1] == 0x50;
      final jpeg = octets[0] == 0xFF && octets[1] == 0xD8;
      expect(png || jpeg, isTrue, reason: "ni PNG ni JPEG : Flutter ne saurait pas le décoder");
    });

    test("c'est le MÊME fichier que celui du web, octet pour octet (copié, jamais redessiné)", () {
      if (!fichierWeb.existsSync()) {
        markTestSkipped('agrierp_laravel introuvable (AGRIERP_LARAVEL)');
        return;
      }
      expect(File(_cheminImage).readAsBytesSync(), fichierWeb.readAsBytesSync());
    });

    test("le Blade pose bien cette image en fond du panneau gauche (sinon la copie n'aurait plus de modèle)", () {
      if (!blade.existsSync()) {
        markTestSkipped('agrierp_laravel introuvable (AGRIERP_LARAVEL)');
        return;
      }
      expect(blade.readAsStringSync(), contains("asset('assets/images/image_login.png')"));
    });

    testWidgets("l'image est dans le manifeste d'assets : elle se charge", (tester) async {
      final donnees = await tester.runAsync(() => rootBundle.load(_cheminImage));
      expect(donnees!.lengthInBytes, File(_cheminImage).lengthSync());
    });
  });

  group('panneau gauche', () {
    testWidgets("à 1280 px : le panneau est là, avec l'image de fond en « cover » du fichier déclaré", (tester) async {
      await afficher(tester);

      expect(find.byKey(const Key('login-panneau-gauche')), findsOneWidget);
      final image = tester.widget<Image>(find.byKey(const Key('login-image-gauche')));
      expect((image.image as AssetImage).assetName, _cheminImage);
      expect(image.fit, BoxFit.cover);
      expect(image.alignment, Alignment.center);
      expect(find.byKey(const Key('login-panneau-repli')), findsNothing);
    });

    testWidgets("la marque et les mentions institutionnelles restent affichées PAR-DESSUS l'image", (tester) async {
      await afficher(tester);

      final panneau = find.byKey(const Key('login-panneau-gauche'));
      expect(find.descendant(of: panneau, matching: find.textContaining("PROJET D'APPUI À L'ENTREPRENEURIAT AU BÉNIN (PAEB)")), findsOneWidget);
      expect(find.descendant(of: panneau, matching: find.textContaining('FAGUEZ SARL')), findsOneWidget);
      expect(find.descendant(of: panneau, matching: find.byType(RichText)), findsWidgets);
      // L'image est sous le voile, lui-même sous le texte.
      final ordre = tester
          .widgetList(find.descendant(of: panneau, matching: find.byWidgetPredicate((w) => w is Image || w.key == const Key('login-voile'))))
          .map((w) => w is Image ? 'image' : 'voile')
          .toList();
      expect(ordre, ['image', 'voile']);
    });

    testWidgets("le voile reprend le dégradé du Blade, lu dans le Blade (rgba(5,46,22,0.10) → rgba(0,33,13,0.55))", (tester) async {
      await afficher(tester);
      final voile = tester.widget<DecoratedBox>(find.byKey(const Key('login-voile')));
      final degrade = (voile.decoration as BoxDecoration).gradient! as LinearGradient;

      expect(degrade.begin, Alignment.topCenter);
      expect(degrade.end, Alignment.bottomCenter);
      expect(degrade.colors, [const Color.fromRGBO(5, 46, 22, 0.10), const Color.fromRGBO(0, 33, 13, 0.55)]);

      if (blade.existsSync()) {
        final m = RegExp(r'linear-gradient\(180deg, rgba\((\d+),(\d+),(\d+),([\d.]+)\) 0%, rgba\((\d+),(\d+),(\d+),([\d.]+)\) 100%\)')
            .firstMatch(blade.readAsStringSync())!;
        expect(degrade.colors, [
          Color.fromRGBO(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), double.parse(m[4]!)),
          Color.fromRGBO(int.parse(m[5]!), int.parse(m[6]!), int.parse(m[7]!), double.parse(m[8]!)),
        ]);
      }
    });

    testWidgets("sous 1024 px, comme le web (`hidden lg:flex`), le panneau gauche disparaît", (tester) async {
      await afficher(tester, largeur: 1000);

      expect(find.byKey(const Key('login-panneau-gauche')), findsNothing);
      expect(find.byKey(const Key('bouton-connexion')), findsOneWidget);
    });

    testWidgets("le panneau occupe la moitié gauche (`lg:w-[50%]`)", (tester) async {
      await afficher(tester);
      expect(tester.getSize(find.byKey(const Key('login-panneau-gauche'))).width, 640);
    });
  });

  group("sans le fichier image : jamais d'écran cassé", () {
    testWidgets("panneau de repli aux couleurs de la marque, texte et formulaire intacts, aucune exception", (tester) async {
      await afficher(tester, lot: _LotSansImage());

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('login-panneau-gauche')), findsOneWidget);
      expect(find.byKey(const Key('login-panneau-repli')), findsOneWidget);
      final repli = tester.widget<DecoratedBox>(find.byKey(const Key('login-panneau-repli')));
      final degrade = (repli.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(degrade.colors.length, 2);
      expect(find.descendant(of: find.byKey(const Key('login-panneau-gauche')), matching: find.textContaining('FAGUEZ SARL')), findsOneWidget);
      expect(find.byKey(const Key('bouton-connexion')), findsOneWidget);
    });
  });
}
