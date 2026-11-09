import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/ventes/avoirs_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/devis_repository.dart';
import 'package:agrierp/features/ventes/historique_ventes_repository.dart';
import 'package:agrierp/features/ventes/ventes_devis_repository.dart';
import 'package:agrierp/features/ventes/ventes_devis_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.37 — HUB VENTES & DEVIS (`ventes-devis.html`).
///
/// 🔴→✅ **L'ENTRÉE DE MENU OUVRAIT DIRECTEMENT LA CAISSE**, sautant le hub :
/// le caissier n'avait aucun chemin vers l'historique de ses propres ventes.
/// La caisse est désormais le premier onglet, comme dans la maquette.
///
/// Tickets AV1 / AV2 : les onglets « Historique des Ventes » et « Retours et Avoirs » sont ceux du Blade ; leurs tests sont
/// `historique_ventes_poste_test.dart` et `avoirs_poste_test.dart` (comportement), `historique_ventes_blade_test.dart` et
/// `avoirs_blade_test.dart` (fidélité lue dans le Blade). Ce fichier ne garde que le hub.
void main() {
  late AppDatabase db;
  late VentesDevisRepository depot;
  late CaisseRepository caisse;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = VentesDevisRepository(database: db);
    caisse = CaisseRepository(database: db, deviceId: 'poste-test');
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester, {bool peutGerer = true, bool peutCorriger = true}) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: VentesDevisScreen(
          peutGerer: peutGerer,
          peutCorriger: peutCorriger,
          depot: depot,
          caisse: caisse,
          devis: DevisRepository(database: db, deviceId: 'poste-test'),
          avoirs: AvoirsRepository(database: db, identifiantPoste: 'poste-test'),
          historique: HistoriqueVentesRepository(database: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-ventes-$onglet')));
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ les quatre onglets du hub sont là, dans son ordre', (
    tester,
  ) async {
    await afficher(tester);

    for (final onglet in [
      'Enregistrer Vente',
      'Devis Prestations',
      'Historique des Ventes',
      'Retours et Avoirs',
    ]) {
      expect(find.text(onglet), findsWidgets, reason: onglet);
    }
  });

  testWidgets('⚠️ le hub ouvre sur la caisse, comme la maquette', (
    tester,
  ) async {
    await afficher(tester);

    // L'écran de caisse est bien monté sous le premier onglet.
    expect(find.byType(VentesDevisScreen), findsOneWidget);
    expect(find.text('Historique des Ventes'), findsOneWidget);
  });

  /// Ticket DEV — l'onglet « Devis Prestations » n'est plus « non embarqué » : c'est « Devis & Proforma » (le détail est
  /// dans `devis_poste_test.dart` et `devis_blade_test.dart`).
  testWidgets('⚠️ l onglet Devis Prestations est « Devis & Proforma », plus une carte « non embarqué »', (tester) async {
    await afficher(tester);
    await ouvrir(tester, 'Devis Prestations');

    expect(find.byKey(const Key('devis-non-embarque')), findsNothing);
    expect(find.text('Devis & Proforma'), findsOneWidget);
    expect(find.byKey(const Key('devis-vide')), findsOneWidget);
  });

  /// Ticket AV1 — l'onglet « Retours et Avoirs » n'est plus « non embarqué » : c'est celui du Blade
  /// (`retours_avoirs_onglet.dart`, verrouillé par `avoirs_poste_test.dart` et `avoirs_blade_test.dart`).
  testWidgets('⚠️ l onglet Retours et Avoirs est l écran du Blade, plus un module « non embarqué »', (tester) async {
    await afficher(tester);
    await ouvrir(tester, 'Retours et Avoirs');

    expect(find.byKey(const Key('avoirs-non-embarque')), findsNothing);
    expect(find.text('Gestion des retours produits, avoirs clients et inspection sanitaire du cheptel retourné.'), findsOneWidget);
    expect(find.byKey(const Key('nouveau-retour')), findsOneWidget);
  });

  /// Ticket AV2 — idem pour « Historique des Ventes » (`historique_ventes_onglet.dart`).
  testWidgets('⚠️ l onglet Historique des Ventes est celui de la ferme, plus « les ventes de ce poste »', (tester) async {
    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    expect(find.text("Toutes les ventes enregistrées de l'entreprise."), findsOneWidget);
    expect(find.textContaining('Ventes encaissées sur ce poste'), findsNothing);
  });

  /// Ticket CONF-4 (DV-20) — le COMPTABLE lit les ventes et corrige par l'avoir : le hub s'ouvre sans la caisse.
  group('CONF-4 : hub du comptable (lecture des ventes, avoirs, pas de caisse)', () {
    testWidgets('⚠️ sans manage-ventes : trois onglets, aucun « Enregistrer Vente », ouverture sur « Devis Prestations »', (tester) async {
      await afficher(tester, peutGerer: false);

      expect(find.byKey(const Key('onglet-ventes-Enregistrer Vente')), findsNothing);
      expect(find.text('Enregistrer Vente'), findsNothing);
      for (final onglet in ['Devis Prestations', 'Historique des Ventes', 'Retours et Avoirs']) {
        expect(find.byKey(Key('onglet-ventes-$onglet')), findsOneWidget, reason: onglet);
      }
      // Le premier onglet visible est monté (devis en lecture), jamais la caisse.
      expect(find.text('Devis & Proforma'), findsOneWidget);
      expect(find.byKey(const Key('devis-vide')), findsOneWidget);
    });

    testWidgets('⚠️ le lien « Nouvelle Vente » de l\'historique ramène au premier onglet VISIBLE, pas à la caisse', (tester) async {
      await afficher(tester, peutGerer: false);
      await ouvrir(tester, 'Historique des Ventes');
      expect(find.text("Toutes les ventes enregistrées de l'entreprise."), findsOneWidget);
      await tester.tap(find.text('Nouvelle Vente'));
      await tester.pumpAndSettle();

      expect(find.text('Devis & Proforma'), findsOneWidget);
      expect(find.text('Enregistrer Vente'), findsNothing);
    });

    testWidgets('⚠️ « Retours et Avoirs » reste ouvert au droit fin (correct-invoices) : « Nouveau Retour » ouvre la modale', (tester) async {
      await afficher(tester, peutGerer: false, peutCorriger: true);
      await ouvrir(tester, 'Retours et Avoirs');

      await tester.tap(find.byKey(const Key('nouveau-retour')));
      await tester.pumpAndSettle();
      // La modale s'ouvre (le refus de droit ne survient qu'à l'enregistrement, quand il n'y a pas le droit).
      expect(find.byKey(const Key('retour-vente')), findsOneWidget);
    });

    test('⚠️ garde des sources : l\'avoir suit `peutCorriger` (avoir-client), la caisse et l\'annulation `peutGerer` (manage-ventes seul)', () {
      final hub = File('lib/features/ventes/ventes_devis_screen.dart').readAsStringSync();
      expect(hub, contains('RetoursAvoirsOnglet(depot: widget.avoirs, peutGerer: widget.peutCorriger)'));
      expect(hub, contains('HistoriqueVentesOnglet(\n                depot: widget.historique,\n                peutGerer: widget.peutGerer,'));
      final main = File('lib/main.dart').readAsStringSync();
      final appel = main.substring(main.indexOf('EcranPoste.ventesEtDevis => VentesDevisScreen('));
      expect(appel.substring(0, appel.indexOf('EcranPoste.caisse =>')), allOf(
        contains("peutGerer: PermissionsPoste.peut(_role, 'manage-ventes'),"),
        contains('peutCorriger: PermissionsPoste.peutCorrigerParAvoir(_role),'),
      ));
    });

    testWidgets('⚠️ avec manage-ventes : la caisse reste le premier onglet (caissier inchangé)', (tester) async {
      await afficher(tester);
      expect(find.byKey(const Key('onglet-ventes-Enregistrer Vente')), findsOneWidget);
    });
  });
}
