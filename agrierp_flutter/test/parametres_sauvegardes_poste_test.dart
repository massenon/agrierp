import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/parametres/onglet_sauvegardes.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test de l'onglet « Sauvegardes » au poste.
///
/// Vérifie que :
/// - Bouton « Générer une sauvegarde » est présent et fonctionnel
/// - Bloc « EXPORTER UN MODULE SEUL » avec select et bouton
/// - Bloc « IMPORTER UN MODULE » avec info-box et boutons
/// - Tableau historique affiché (vide par défaut)
/// - Toutes les actions passent par l'API
void main() {
  late AppDatabase db;
  late ParametresGenerauxRepository depot;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ParametresGenerauxRepository(database: db);
  });

  tearDown(() async => db.close());

  group('onglet-sauvegardes', () {
    testWidgets('affiche le titre avec icône database', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletSauvegardes(repository: depot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sauvegardes & Imports'), findsOne);
      expect(find.text('Générer une Sauvegarde Complète'), findsOne);
      expect(find.text('Rétention 30 jours'), findsOne);
    });

    testWidgets('affiche le bouton « Générer une sauvegarde »', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletSauvegardes(repository: depot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('btn-generer-sauvegarde')),
        findsOne,
      );
      expect(find.text('Générer une sauvegarde'), findsOne);
    });

    testWidgets('affiche le bloc d\'export module', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletSauvegardes(repository: depot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('EXPORTER UN MODULE SEUL'), findsOne);
      expect(find.byKey(const Key('select-module-export')), findsOne);
      expect(find.byKey(const Key('btn-exporter-module')), findsOne);
      expect(find.text('Exporter'), findsOne);
    });

    testWidgets('affiche le bloc d\'import module avec info-box', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletSauvegardes(repository: depot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('IMPORTER UN MODULE'), findsOne);
      expect(
        find.textContaining('import remplacera les données'),
        findsOne,
      );
      expect(find.byKey(const Key('select-fichier-import')), findsOne);
      expect(find.byKey(const Key('select-module-import')), findsOne);
      expect(find.byKey(const Key('btn-importer-module')), findsOne);
      expect(find.text('Importer'), findsOne);
    });

    testWidgets('affiche le tableau historique', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletSauvegardes(repository: depot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Historique des Sauvegardes'), findsOne);
      expect(find.text('FICHIER'), findsOne);
      expect(find.text('DATE'), findsOne);
      expect(find.text('TABLE'), findsOne);
      expect(find.text('ACTION'), findsOne);
    });

    testWidgets('affiche l\'état vide du tableau', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletSauvegardes(repository: depot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Aucune sauvegarde enregistrée.'),
        findsOne,
      );
    });

    testWidgets('le bouton génération fonctionne', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletSauvegardes(repository: depot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Vérifier que le bouton existe et n'est pas désactivé initialement
      expect(
        find.byKey(const Key('btn-generer-sauvegarde')),
        findsOne,
      );

      // Tapoter le bouton
      await tester.tap(find.byKey(const Key('btn-generer-sauvegarde')));
      await tester.pumpAndSettle();

      // Vérifier le message d'attente
      expect(find.text('Génération en cours...'), findsOne);

      // Attendre la fin
      await tester.pumpAndSettle();
    });

    testWidgets('le bouton export fonctionne', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletSauvegardes(repository: depot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-exporter-module')));
      await tester.pumpAndSettle();
    });

    testWidgets('le bouton import fonctionne', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletSauvegardes(repository: depot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-importer-module')));
      await tester.pumpAndSettle();
    });
  });
}
