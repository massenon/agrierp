import 'dart:io';
import 'dart:typed_data';

import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/theme/symboles_agri.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// GARDE-FOU — « les tailles des cartes KPI doivent être uniformes partout » (demande client, web ET poste).
///
/// 1. Aucune grille de cartes KPI à rapport fixe (`childAspectRatio`) ni à hauteur fixe (`mainAxisExtent`) :
///    elles donnaient des cartes minuscules ici et démesurées (~300 px, presque vides) là.
/// 2. Une `CarteKpi` a la même hauteur avec ou sans légende, avec ou sans icône, avec ou sans unité.
/// 3. Dans une `GrilleKpi`, toutes les cartes d'une rangée ont la même hauteur.
void main() {
  group('Aucune grille de cartes KPI à taille fixe', () {
    test('childAspectRatio / mainAxisExtent ne coiffent jamais une carte KPI', () {
      final fautifs = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final lignes = f.readAsLinesSync();
        for (var i = 0; i < lignes.length; i++) {
          if (!lignes[i].contains(RegExp(r'^\s*(childAspectRatio|mainAxisExtent):'))) {
            continue;
          }
          // Les 40 lignes qui suivent : si elles posent une carte KPI, la grille est interdite.
          final suite = lignes.skip(i).take(40).join('\n');
          if (suite.contains(RegExp(r'CarteKpi\(|_carteKpi\(|_carteGmq\('))) {
            fautifs.add('${f.path}:${i + 1}');
          }
        }
      }
      expect(
        fautifs,
        isEmpty,
        reason: 'Utiliser `GrilleKpi` (core/widgets/carte_kpi.dart) : la rangée prend la hauteur de sa plus haute carte.',
      );
    });
  });

  group('Hauteur uniforme des cartes', () {
    String? raisonSaut;

    setUpAll(() async {
      final racines = [Platform.environment['FLUTTER_ROOT'], '/opt/flutter', r'C:\src\flutter'].whereType<String>();
      for (final racine in racines) {
        final dossier = '$racine/bin/cache/artifacts/material_fonts';
        final regulier = File('$dossier/Roboto-Regular.ttf');
        final gras = File('$dossier/Roboto-Bold.ttf');
        if (regulier.existsSync() && gras.existsSync()) {
          final police = FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(regulier.readAsBytesSync())))
            ..addFont(Future.value(ByteData.sublistView(gras.readAsBytesSync())));
          await police.load();
          return;
        }
      }
      raisonSaut = 'Roboto introuvable dans le SDK Flutter (FLUTTER_ROOT)';
    });

    Future<double> hauteur(WidgetTester tester, CarteKpi carte, double largeur) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: largeur, child: carte),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(CarteKpi)).height;
    }

    for (final largeur in [200.0, 280.0, 400.0]) {
      testWidgets('largeur $largeur : avec ou sans légende, la hauteur est la même', (tester) async {
        if (raisonSaut != null) {
          markTestSkipped(raisonSaut!);
          return;
        }
        final sans = await hauteur(
          tester,
          const CarteKpi(libelle: 'Alertes de Seuil', valeur: '3 réf.', couleurLisere: Colors.red),
          largeur,
        );
        final avec = await hauteur(
          tester,
          const CarteKpi(
            libelle: 'Valorisation Stocks',
            valeur: '1 250 000',
            unite: 'FCFA',
            legende: 'Basée sur le PMP réel (achats)',
            couleurLisere: Colors.green,
            icone: SymbolesAgri.payments,
          ),
          largeur,
        );
        expect(sans, CarteKpi.hauteurMin);
        expect(avec, sans, reason: 'Une carte sans légende ne doit pas être plus petite qu\'une carte avec légende.');
      });
    }

    testWidgets('dans une GrilleKpi, une rangée a une seule hauteur, avec et sans légende', (tester) async {
      if (raisonSaut != null) {
        markTestSkipped(raisonSaut!);
        return;
      }
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: GrilleKpi(
                colonnes: 3,
                children: [
                  CarteKpi(key: Key('a'), libelle: 'A', valeur: '1', couleurLisere: Colors.red),
                  CarteKpi(
                    key: Key('b'),
                    libelle: 'B',
                    valeur: '2',
                    legende: 'Une légende assez longue pour passer sur deux lignes dans une carte étroite, ou même trois',
                    couleurLisere: Colors.red,
                  ),
                  CarteKpi(key: Key('c'), libelle: 'C', valeur: '3', couleurLisere: Colors.red),
                  CarteKpi(key: Key('d'), libelle: 'D', valeur: '4', couleurLisere: Colors.red),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final h = {
        for (final k in ['a', 'b', 'c', 'd']) k: tester.getSize(find.byKey(Key(k))).height,
      };
      expect(h['a'], h['b']);
      expect(h['b'], h['c']);
      expect(h['d'], greaterThanOrEqualTo(CarteKpi.hauteurMin));
    });
  });
}
