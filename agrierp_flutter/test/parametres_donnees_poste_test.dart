import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/parametres/onglet_donnees_entreprise.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test de l'onglet « Données de l'Entreprise » au poste.
///
/// Vérifie que :
/// - Tous les champs s'affichent (raison sociale, adresse, IFU, RCCM, etc.)
/// - Les infos légales portent le bon pied de page
/// - Un tirage absent affiche une mention d'ignorance
/// - Pas de secret descendu (pas de colonne SMTP password)
void main() {
  late AppDatabase db;
  late ParametresGenerauxRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ParametresGenerauxRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> entreprise() => db
      .into(db.companySettings)
      .insert(
        CompanySettingsCompanion.insert(
          id: const Value('unique'),
          companyName: const Value('Ferme École OLOUWACHEGOUN'),
          promoterName: const Value('OLOUKOUNLE Olouchégoun Hassimiyou'),
          address: const Value('Attan-Ewé, Ikpinlè, Adja-Ouèrè, Bénin'),
          ifu: const Value('3202601234567'),
          rccm: const Value('RB/ADJ/26 B 0123'),
        ),
      );

  group('onglet-donnees-entreprise', () {
    testWidgets('affiche tous les champs d\'une entreprise', (tester) async {
      await entreprise();

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletDonneesEntreprise(donnees: donnees),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RAISON SOCIALE'), findsOne);
      expect(find.text('Ferme École OLOUWACHEGOUN'), findsOne);
      expect(find.text('NOM DU PROMOTEUR'), findsOne);
      expect(find.text('OLOUKOUNLE Olouchégoun Hassimiyou'), findsOne);
      expect(find.text("ADRESSE DU SIÈGE D'EXPLOITATION"), findsOne);
      expect(find.text('Attan-Ewé, Ikpinlè, Adja-Ouèrè, Bénin'), findsOne);
      expect(find.text('IDENTIFIANT FISCAL UNIQUE (IFU)'), findsOne);
      expect(find.text('3202601234567'), findsOne);
      expect(find.text('REGISTRE DU COMMERCE (RCCM)'), findsOne);
      expect(find.text('RB/ADJ/26 B 0123'), findsOne);
    });

    testWidgets('affiche le pied de page légales & fiscales', (tester) async {
      await entreprise();

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletDonneesEntreprise(donnees: donnees),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('factures normalisées MeCeF'),
        findsOne,
      );
    });

    testWidgets('affiche une mention quand aucune entreprise n\'est synchronisée', (tester) async {
      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletDonneesEntreprise(donnees: donnees),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('bloc-informations-generales')),
        findsNothing,
      );
      expect(
        find.textContaining("aucun tirage n'a encore eu lieu"),
        findsOne,
      );
    });

    testWidgets('n\'affiche aucun champ SMTP password', (tester) async {
      await entreprise();

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletDonneesEntreprise(donnees: donnees),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Vérifier qu'aucun mot de passe ou token n'est affiché
      expect(find.text('PASSWORD'), findsNothing);
      expect(find.text('SECRET'), findsNothing);
      expect(find.text('TOKEN'), findsNothing);
    });

    testWidgets('affiche la mention technique', (tester) async {
      await entreprise();

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletDonneesEntreprise(donnees: donnees),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('onglet Email (SMTP)'),
        findsOne,
      );
    });
  });
}
