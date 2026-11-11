// Ticket MP2 -- Les champs VOISINS d'une date dans les modales respectent
// la meme charte visuelle que les champs date :
//   - hauteur h-11 (44 px)
//   - padding horizontal px-md
//   - libelle text-[10px] uppercase forest
//   - pas de labelText flottant Material

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agrierp/core/widgets/champs_formulaire_agri.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';

void main() {
  // -- 1. BlocChampFormulaire ------------------------------------------------

  group('BlocChampFormulaire', () {
    testWidgets('affiche le libelle en majuscules au-dessus du champ',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlocChampFormulaire(
              libelle: 'categorie',
              enfant: SizedBox(height: 44),
            ),
          ),
        ),
      );

      final texte = tester.widget<Text>(find.text('CATEGORIE'));
      expect(texte.style!.fontSize, AgriChamps.etiquetteFormulaire);
      expect(texte.style!.color, AgriColors.brandForest);
      expect(texte.style!.fontWeight, FontWeight.bold);
    });

    testWidgets('affiche le message erreur quand erreur != null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlocChampFormulaire(
              libelle: 'Champ',
              enfant: SizedBox(height: 44),
              erreur: 'Champ obligatoire',
            ),
          ),
        ),
      );

      expect(find.text('Champ obligatoire'), findsOneWidget);
    });

    testWidgets('affiche le texte aide quand aide != null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlocChampFormulaire(
              libelle: 'Champ',
              enfant: SizedBox(height: 44),
              aide: 'Ex. : valeur',
            ),
          ),
        ),
      );

      expect(find.text('Ex. : valeur'), findsOneWidget);
    });
  });

  // -- 2. ChampTexteFormulaire -----------------------------------------------

  group('ChampTexteFormulaire', () {
    testWidgets('height = AgriChamps.hauteurFormulaire (44 px)', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChampTexteFormulaire(controleur: ctrl),
          ),
        ),
      );

      final box = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(box.height, AgriChamps.hauteurFormulaire);
    });

    testWidgets('pas de labelText flottant Material', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChampTexteFormulaire(controleur: ctrl),
          ),
        ),
      );

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.decoration!.labelText, isNull,
          reason:
              'labelText flottant interdit -- libelle separe via BlocChampFormulaire');
    });
  });

  // -- 3. ChampLectureFormulaire ---------------------------------------------

  group('ChampLectureFormulaire', () {
    testWidgets('affiche la valeur et respecte h-11', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChampLectureFormulaire(valeur: 'Bande Alpha'),
          ),
        ),
      );

      expect(find.text('Bande Alpha'), findsOneWidget);
    });
  });

  // -- 4. cadreChampFormulaire -----------------------------------------------

  group('cadreChampFormulaire', () {
    test('fond blanc par defaut', () {
      final d = cadreChampFormulaire();
      expect(d.color?.toARGB32(), AgriColors.surfaceCard.toARGB32());
    });

    test('fond teinte quand grise = true', () {
      final d = cadreChampFormulaire(grise: true);
      expect(d.color?.toARGB32(), AgriColors.surfaceZebra.toARGB32());
    });

    test('bordure rouge quand enErreur = true', () {
      final d = cadreChampFormulaire(enErreur: true);
      final border = d.border! as Border;
      expect(border.top.color.toARGB32(), AgriColors.errorDeep.toARGB32());
    });

    test('fond rouge teinte quand enErreur = true', () {
      final d = cadreChampFormulaire(enErreur: true);
      expect(d.color?.toARGB32(), const Color(0xFFFFF5F5).toARGB32());
    });
  });
}
