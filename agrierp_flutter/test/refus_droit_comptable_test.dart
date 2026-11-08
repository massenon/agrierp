import 'package:agrierp/core/auth/refus_droit.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/achats/achats_commandes_screen.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_screen.dart';
import 'package:agrierp/features/achats/saisie_depenses_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket CONF-4 (DV-20) — LE COMPTABLE LIT LES ACHATS, IL NE LES ÉCRIT PAS.
///
/// Ses écrans d'achats s'ouvrent (carte du poste, `perimetre_tirage_test` : toutes les tables lues lui sont servies), mais
/// chaque geste d'écriture est refusé ICI par « Votre rôle ne permet pas cette action. » (`RefusDroit`), AVANT d'ouvrir une
/// modale et d'écrire dans la base locale : sinon la saisie serait faite au poste (stock, trésorerie) puis rejetée à la
/// synchronisation (`manage-achats`). Au web, le même geste est un 403 (`authorize('manage-achats')`).
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> grandEcran(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> retirerToasts(WidgetTester tester) async {
    ToastAgri.toutRetirer();
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  test('le motif est celui des onglets de ventes (un seul texte au poste)', () {
    expect(RefusDroit.message, 'Votre rôle ne permet pas cette action.');
  });

  group('Saisie des dépenses', () {
    Future<void> afficher(WidgetTester tester, {required bool peutGerer}) async {
      await grandEcran(tester);
      final depot = DepensesRepository(database: db, deviceId: 'poste-test', auteurId: () => 'uuuuuuuu-0000-4000-8000-000000000001');
      await tester.pumpWidget(MaterialApp(home: SaisieDepensesScreen(depot: depot, peutGerer: peutGerer)));
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️ sans manage-achats : « Nouvelle Dépense » est refusée, aucune modale, rien d\'écrit', (tester) async {
      await afficher(tester, peutGerer: false);
      await tester.tap(find.byKey(const Key('bouton-nouvelle-depense')));
      await tester.pumpAndSettle();

      expect(find.text('Votre rôle ne permet pas cette action.'), findsOneWidget);
      expect(find.byKey(const Key('bouton-ajouter-ligne')), findsNothing, reason: 'la modale ne s\'ouvre pas');
      expect(await db.select(db.expenses).get(), isEmpty);
      await retirerToasts(tester);
    });

    testWidgets('⚠️ avec manage-achats (administrateur) : la modale s\'ouvre comme avant', (tester) async {
      await afficher(tester, peutGerer: true);
      await tester.tap(find.byKey(const Key('bouton-nouvelle-depense')));
      await tester.pumpAndSettle();

      expect(find.text('Votre rôle ne permet pas cette action.'), findsNothing);
      expect(find.byKey(const Key('bouton-ajouter-ligne')), findsOneWidget);
    });
  });

  group('Achats & Commandes', () {
    Future<void> afficher(WidgetTester tester, {required bool peutGerer}) async {
      await grandEcran(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AchatsCommandesScreen(
            depot: AchatsRepository(database: db, identifiantPoste: 'poste-test'),
            depotFournisseurs: FournisseursRepository(database: db),
            peutGerer: peutGerer,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️ sans manage-achats : « Enregistrer l\'achat » et « Générer le Bon » sont refusés, rien d\'écrit', (tester) async {
      await afficher(tester, peutGerer: false);

      await tester.tap(find.byKey(const Key('enregistrer-achat')));
      await tester.pumpAndSettle();
      expect(find.text('Votre rôle ne permet pas cette action.'), findsOneWidget);
      await retirerToasts(tester);

      await tester.tap(find.byKey(const Key('onglet-achats-Bons de Commande')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bon-generer')));
      await tester.pumpAndSettle();
      expect(find.text('Votre rôle ne permet pas cette action.'), findsOneWidget);
      await retirerToasts(tester);

      expect(await db.select(db.purchases).get(), isEmpty);
      expect(await db.select(db.purchaseOrders).get(), isEmpty);
    });

    testWidgets('⚠️ sans manage-achats : « Ajouter un fournisseur » (à la volée) est refusé, aucune modale', (tester) async {
      await afficher(tester, peutGerer: false);
      await tester.tap(find.byKey(const Key('ajouter-fournisseur')));
      await tester.pumpAndSettle();

      expect(find.text('Votre rôle ne permet pas cette action.'), findsOneWidget);
      expect(await db.select(db.suppliers).get(), isEmpty);
      await retirerToasts(tester);
    });

    testWidgets('⚠️ avec manage-achats : le même geste n\'est pas refusé', (tester) async {
      await afficher(tester, peutGerer: true);
      await tester.tap(find.byKey(const Key('ajouter-fournisseur')));
      await tester.pumpAndSettle();

      expect(find.text('Votre rôle ne permet pas cette action.'), findsNothing);
    });
  });

  group('Fournisseurs', () {
    Future<void> afficher(WidgetTester tester, {required bool peutGerer}) async {
      await grandEcran(tester);
      await tester.pumpWidget(MaterialApp(home: FournisseursScreen(depot: FournisseursRepository(database: db), peutGerer: peutGerer)));
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️ sans manage-achats : créer, modifier, archiver un fournisseur et régler une dette sont refusés', (tester) async {
      await db
          .into(db.suppliers)
          .insert(SuppliersCompanion.insert(id: 'fffffff1-0000-4000-8000-000000000001', name: 'Provenderie du Plateau'));
      await afficher(tester, peutGerer: false);
      await tester.tap(find.byKey(const Key('onglet-fournisseurs-Fiches Fournisseurs')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('modifier-fiche-fffffff1-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      expect(find.text('Votre rôle ne permet pas cette action.'), findsOneWidget);
      await retirerToasts(tester);

      await tester.tap(find.byKey(const Key('archiver-fiche-fffffff1-0000-4000-8000-000000000001')));
      await tester.pumpAndSettle();
      expect(find.text('Votre rôle ne permet pas cette action.'), findsOneWidget);
      await retirerToasts(tester);

      final fiche = await db.select(db.suppliers).getSingle();
      expect(fiche.isActive, isTrue, reason: 'la fiche n\'est pas archivée');
    });
  });
}
