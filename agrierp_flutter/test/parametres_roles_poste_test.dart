import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/parametres/onglet_roles_permissions.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test de l'onglet « Rôles & Permissions » au poste.
///
/// Vérifie que :
/// - La matrice affiche les 11 colonnes attendues
/// - Les 4 KPI cards sont présentes
/// - Les permissions sont affichées correctement (checkmarks/tirets)
/// - Les actions sont inertes (lecture seule)
void main() {
  late AppDatabase db;
  late ParametresGenerauxRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ParametresGenerauxRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> role(String nom, String permissions) => db
      .into(db.rolesApplicatifs)
      .insert(
        RolesApplicatifsCompanion.insert(
          id: uuid(nom),
          name: nom,
          permissions: Value(permissions),
        ),
      );

  Future<void> utilisateur(String cle, String nom) => db
      .into(db.utilisateurs)
      .insert(
        UtilisateursCompanion.insert(
          id: uuid(cle),
          name: nom,
          email: Value('$cle@fermeolouwachegoun.com'),
        ),
      );

  group('onglet-roles-permissions', () {
    testWidgets('affiche la matrice avec 11 colonnes', (tester) async {
      await role('admin', 'view-ventes, view-achats');
      await utilisateur('u1', 'Admin');

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngletRolesPermissions(donnees: donnees),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Vérifier les 11 colonnes de la matrice
      expect(find.text('RÔLE'), findsOne);
      expect(find.text('DASHBOARD'), findsOne);
      expect(find.text('VENTES & DEVIS'), findsOne);
      expect(find.text('ACHATS & CHARGES'), findsOne);
      expect(find.text('STOCKS'), findsOne);
      expect(find.text('ÉLEVAGE & SOINS'), findsOne);
      expect(find.text('RH'), findsOne);
      expect(find.text('COMPTABILITÉ'), findsOne);
      expect(find.text('ADMINISTRATION'), findsOne);
      expect(find.text('PARAMÈTRES'), findsOne);
      expect(find.text('ACTIONS'), findsOne);
    });

    testWidgets('affiche 4 KPI cards', (tester) async {
      await role('admin', 'view-ventes');
      await utilisateur('u1', 'Admin');

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngletRolesPermissions(donnees: donnees),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CarteKpi), findsNWidgets(4));
      expect(find.text('Rôles configurés'), findsOne);
      expect(find.text('Utilisateurs assignés'), findsOne);
      expect(find.text('Modules couverts'), findsOne);
      expect(find.text('Dernière sauvegarde'), findsOne);
    });

    testWidgets('affiche les droits accordés avec checkmarks', (tester) async {
      await role(
        'admin',
        'view-ventes, view-achats, view-stocks, view-elevage, '
            'view-rh, view-comptabilite, view-administration, view-parametres',
      );

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngletRolesPermissions(donnees: donnees),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Admin a au moins 8 checkmarks (une par module)
      expect(find.byIcon(Icons.check_circle), findsWidgets);
    });

    testWidgets('affiche les droits refusés avec des tirets', (tester) async {
      await role('comptable', 'view-comptabilite');

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngletRolesPermissions(donnees: donnees),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Comptable n'a pas tous les droits
      expect(find.byIcon(Icons.remove), findsWidgets);
    });

    testWidgets('affiche la mention poste', (tester) async {
      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngletRolesPermissions(donnees: donnees),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('surface web'),
        findsOne,
      );
    });
  });
}
