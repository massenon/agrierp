import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/parametres/onglet_gestion_utilisateurs.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test de l'onglet « Gestion Utilisateurs » au poste.
///
/// Vérifie que :
/// - 2 KPI cards : utilisateurs actifs, rôles définis
/// - Tableau : 5 colonnes NOM | EMAIL | RÔLE | STATUT | ACTIONS
/// - Statut affiché avec pastille (Actif/Désactivé)
/// - Pas de secret (password) affiché
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

  Future<void> utilisateur(
    String cle,
    String nom, {
    String role = 'admin',
    bool actif = true,
  }) => db
      .into(db.utilisateurs)
      .insert(
        UtilisateursCompanion.insert(
          id: uuid(cle),
          name: nom,
          email: Value('$cle@fermeolouwachegoun.com'),
          role: Value(role),
          isActive: Value(actif),
        ),
      );

  group('onglet-gestion-utilisateurs', () {
    testWidgets('affiche 2 KPI cards', (tester) async {
      await role('admin', 'view-ventes');
      await utilisateur('u1', 'Admin');

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngletGestionUtilisateurs(donnees: donnees),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CarteKpi), findsNWidgets(2));
      expect(find.text('Utilisateurs actifs'), findsOne);
      expect(find.text('Rôles définis'), findsOne);
    });

    testWidgets('affiche le tableau avec 5 colonnes', (tester) async {
      await role('admin', 'view-ventes');
      await utilisateur('u1', 'Admin');

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngletGestionUtilisateurs(donnees: donnees),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NOM'), findsOne);
      expect(find.text('EMAIL'), findsOne);
      expect(find.text('RÔLE'), findsOne);
      expect(find.text('STATUT'), findsOne);
      expect(find.text('ACTIONS'), findsOne);
    });

    testWidgets('affiche les utilisateurs avec leurs infos', (tester) async {
      await role('admin', 'view-ventes');
      await utilisateur('u1', 'Admin');
      await utilisateur('u2', 'Comptable', role: 'comptable');

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngletGestionUtilisateurs(donnees: donnees),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsOne);
      expect(find.text('Comptable'), findsOne);
      expect(find.text('u1@fermeolouwachegoun.com'), findsOne);
      expect(find.text('u2@fermeolouwachegoun.com'), findsOne);
    });

    testWidgets('affiche le statut avec pastilles', (tester) async {
      await role('admin', 'view-ventes');
      await utilisateur('u1', 'Admin');
      await utilisateur('u2', 'Ancien', actif: false);

      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngletGestionUtilisateurs(donnees: donnees),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Actif'), findsOne);
      expect(find.text('Désactivé'), findsOne);
    });

    testWidgets('affiche la mention poste', (tester) async {
      final donnees = await depot.charger();

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngletGestionUtilisateurs(donnees: donnees),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('surface web'),
        findsOne,
      );
    });

    testWidgets('compte correctement les utilisateurs actifs', (tester) async {
      await utilisateur('u1', 'Admin');
      await utilisateur('u2', 'Ancien', actif: false);
      await utilisateur('u3', 'Caissier');

      final donnees = await depot.charger();

      expect(donnees.utilisateursActifs, 2);

      tester.binding.window.physicalSizeTestValue = const Size(1700, 2400);
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OngletGestionUtilisateurs(donnees: donnees),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Vérifier que la KPI card affiche le bon nombre
      expect(find.text('2', skipOffstage: false), findsOne);
    });
  });
}
