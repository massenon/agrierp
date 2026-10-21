import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:agrierp/core/fenetre/fenetre_poste.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// RENDU — boutons réduire / restaurer / fermer de la barre supérieure (demande client : « bien positionnés »).
///
/// Défaut constaté sur capture : la rangée de boutons paraissait plus haute que l'axe de la barre, le rond de survol
/// de « Restaurer » était décalé, le séparateur dépassait les icônes. Ces tests MESURENT le rendu : boîtes (centre
/// vertical = centre de la barre, tolérance 0,5 px), taille commune, bord droit, ET encre réelle des glyphes
/// (pixels peints) pour attraper une icône décentrée dans sa propre boîte.
const _canal = MethodChannel('agrierp/fenetre');
const _cles = ['fenetre-reduire', 'fenetre-agrandir', 'fenetre-fermer'];

void main() {
  // Les icônes sont des glyphes de la police Material Symbols : sans elle, le test mesurerait un rectangle de
  // substitution. On la charge explicitement depuis les ressources du poste.
  setUpAll(() async {
    final police = FontLoader('MaterialSymbolsOutlined')
      ..addFont(Future.value(ByteData.sublistView(File('assets/fonts/MaterialSymbolsOutlined.ttf').readAsBytesSync())));
    await police.load();
  });

  setUp(() {
    FenetrePoste.reinitialiserPourTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_canal, null);
  });

  Future<void> afficher(WidgetTester tester, {double largeur = 1280}) async {
    tester.view.physicalSize = Size(largeur, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: const Key('capture'),
              child: BarreSuperieure(groupe: 'PILOTAGE', ecran: 'Tableau de Bord', enAttente: 0, onBasculerMenu: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final largeur in [1280.0, 1024.0, 900.0]) {
    testWidgets('largeur $largeur : même taille, centrés sur la barre, collés au bord droit', (tester) async {
      await afficher(tester, largeur: largeur);

      final barre = tester.getRect(find.byType(BarreSuperieure));
      // Axe de la barre : le centre de sa zone utile (le filet du bas, 1 px, est dans la hauteur de 64).
      final axe = (barre.top + barre.bottom - 1) / 2;
      expect(barre.height, BarreSuperieure.hauteurBarre);
      final rects = [for (final c in _cles) tester.getRect(find.byKey(Key(c)))];

      for (final r in rects) {
        expect(r.center.dy, closeTo(axe, 0.5), reason: 'centre vertical = centre de la barre');
        expect(r.size, rects.first.size, reason: 'trois boutons de même taille');
      }
      expect(rects.first.width, greaterThanOrEqualTo(44));
      expect(rects.first.height, BarreSuperieure.hauteurBarre - 1, reason: 'toute la zone utile de la barre');
      expect(rects.last.right, barre.right, reason: 'aucune marge parasite à droite');
      expect(rects[0].right, rects[1].left);
      expect(rects[1].right, rects[2].left);

      // Le séparateur est centré sur le même axe et plus court que la barre.
      final sep = tester.getRect(find.byKey(const Key('fenetre-separateur')));
      expect(sep.center.dy, closeTo(axe, 0.5));
      expect(sep.right, lessThanOrEqualTo(rects.first.left));

      // Les autres éléments de la barre partagent le même axe.
      for (final autre in ['cloche-notifications']) {
        expect(tester.getCenter(find.byKey(Key(autre))).dy, closeTo(axe, 0.5));
      }
    });
  }

  testWidgets("l'encre de chaque icône est centrée sur l'axe de la barre (±1 px)", (tester) async {
    await afficher(tester);
    final barre = tester.getRect(find.byType(BarreSuperieure));
    final axe = (barre.top + barre.bottom - 1) / 2;
    final frontiere = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('capture')));
    final octets = (await tester.runAsync(() async {
      final image = await frontiere.toImage();
      return (image, (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!);
    }))!;
    final largeurImage = octets.$1.width;
    final data = octets.$2;

    for (final c in _cles) {
      final r = tester.getRect(find.byKey(Key(c)));
      double? haut, bas;
      for (var y = r.top.floor(); y < r.bottom.ceil(); y++) {
        for (var x = r.left.floor(); x < r.right.ceil(); x++) {
          final i = (y * largeurImage + x) * 4;
          final lum = (data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2)) / 3;
          if (lum < 200) {
            haut = (haut == null || y < haut) ? y.toDouble() : haut;
            bas = (bas == null || y + 1 > bas) ? y + 1.0 : bas;
          }
        }
      }
      expect(haut, isNotNull, reason: '$c : une icône est peinte');
      expect((haut! + bas!) / 2, closeTo(axe, 1.0), reason: '$c : encre ($haut–$bas) centrée sur $axe');
    }
  });

  testWidgets('infobulles : Réduire, Agrandir puis Restaurer, Fermer', (tester) async {
    await afficher(tester);
    String info(String c) =>
        tester.widget<Tooltip>(find.descendant(of: find.byKey(Key(c)), matching: find.byType(Tooltip))).message!;

    expect(info('fenetre-reduire'), 'Réduire');
    expect(info('fenetre-fermer'), 'Fermer');
    FenetrePoste.agrandie.value = false;
    await tester.pump();
    expect(info('fenetre-agrandir'), 'Agrandir');
    FenetrePoste.agrandie.value = true;
    await tester.pump();
    expect(info('fenetre-agrandir'), 'Restaurer');
  });

  testWidgets('survol : fermer devient rouge, réduire reste gris', (tester) async {
    await afficher(tester);
    Color fond(String c) => tester
        .widget<Container>(find.descendant(of: find.byKey(Key(c)), matching: find.byType(Container)).first)
        .color!;

    expect(fond('fenetre-fermer'), Colors.transparent);

    final souris = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await souris.addPointer(location: Offset.zero);
    addTearDown(souris.removePointer);

    await souris.moveTo(tester.getCenter(find.byKey(const Key('fenetre-fermer'))));
    await tester.pump();
    expect(fond('fenetre-fermer'), AgriColors.errorRed);

    await souris.moveTo(tester.getCenter(find.byKey(const Key('fenetre-reduire'))));
    await tester.pump();
    expect(fond('fenetre-fermer'), Colors.transparent);
    expect(fond('fenetre-reduire'), AgriColors.surfaceZebra);

    await souris.down(tester.getCenter(find.byKey(const Key('fenetre-reduire'))));
    await tester.pump();
    expect(fond('fenetre-reduire'), AgriColors.outlineVariant);
    await souris.up();
  });
}
