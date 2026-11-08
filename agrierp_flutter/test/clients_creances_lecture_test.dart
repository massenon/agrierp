import 'dart:io';

import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/auth/refus_droit.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/clients/clients_creances_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket CONF-5 (1) — « CLIENTS ET CRÉANCES » EN LECTURE POUR LE COMPTABLE.
///
/// Le web l'ouvre avec `view-ventes` ; chaque geste d'écriture y est sous `@can('manage-ventes')` / `authorize('manage-ventes')`.
/// Au poste, sans `manage-ventes` : consulter (soldes, profil, historique) reste ouvert ; relancer, encaisser, imputer une avance,
/// créer / modifier / archiver un client sont MASQUÉS et refusés (`RefusDroit`) avant toute modale ou écriture.
void main() {
  late AppDatabase db;
  late ClientsCreancesRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ClientsCreancesRepository(database: db, deviceId: 'poste-test');
    await db.into(db.customers).insert(CustomersCompanion.insert(id: uuid('c1'), name: 'AMOUSSOU Régis', phone: const Value('22997000000'), city: const Value('Cotonou')));
    await db.into(db.receivables).insert(ReceivablesCompanion.insert(
      id: uuid('r1'), customerId: uuid('c1'), amount: 8000, amountPaid: const Value(3000),
      dueDate: Value(DateTime.now().subtract(const Duration(days: 20))),
    ));
    await db.into(db.customerAdvances).insert(CustomerAdvancesCompanion.insert(id: uuid('a1'), customerId: uuid('c1'), amount: 5000, advanceDate: Value(DateTime.now())));
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester, {required bool peutGerer}) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ClientsCreancesScreen(depot: depot, peutGerer: peutGerer)));
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-clients-$onglet')));
    await tester.pumpAndSettle();
  }

  Future<int> ecrits() async =>
      (await db.select(db.customers).get()).length * 1000 +
      (await db.select(db.customerReminders).get()).length * 100 +
      (await db.select(db.customerAdvances).get()).length * 10 +
      (await db.select(db.receivables).get()).fold<double>(0, (s, r) => s + r.amountPaid).toInt();

  group('sans manage-ventes (comptable) : on CONSULTE, on n\'écrit rien', () {
    testWidgets('Liste des Clients : aucun bouton d\'écriture, la liste et le profil restent lisibles', (tester) async {
      await afficher(tester, peutGerer: false);
      expect(find.text('AMOUSSOU Régis'), findsOneWidget);
      expect(find.byKey(const Key('nouveau-client')), findsNothing);
      expect(find.byKey(Key('modifier-client-${uuid('c1')}')), findsNothing);
      expect(find.byKey(Key('archiver-client-${uuid('c1')}')), findsNothing);
      expect(find.byKey(const Key('clients-tout-selectionner')), findsNothing);
      expect(find.byKey(Key('client-case-${uuid('c1')}')), findsNothing);
      // Le profil reste ouvert.
      expect(find.byKey(Key('profil-client-${uuid('c1')}')), findsOneWidget);
    });

    testWidgets('Suivi des Dettes : le solde se lit, ni « Ajouter un Recouvrement » ni encaisser ni relancer', (tester) async {
      await afficher(tester, peutGerer: false);
      await ouvrir(tester, 'Suivi des Dettes');
      expect(find.text('AMOUSSOU Régis'), findsWidgets);
      expect(find.byKey(const Key('ajouter-recouvrement')), findsNothing);
      expect(find.byKey(const Key('creance-encaisser-0')), findsNothing);
      expect(find.byKey(const Key('creance-relancer-0')), findsNothing);
    });

    testWidgets('Relances Clients : aucun canal de relance', (tester) async {
      await afficher(tester, peutGerer: false);
      await ouvrir(tester, 'Relances Clients');
      for (final cle in ['relancer-whatsapp', 'relancer-email', 'exporter-courrier', 'relancer-appel']) {
        expect(find.byKey(Key('$cle-${uuid('r1')}')), findsNothing, reason: cle);
      }
    });

    testWidgets('Historique Avances : l\'historique se lit, ni nouvelle avance, ni modifier, imputer, archiver', (tester) async {
      await afficher(tester, peutGerer: false);
      await ouvrir(tester, 'Historique Avances');
      expect(find.byKey(const Key('exporter-avances')), findsOneWidget);
      expect(find.byKey(const Key('nouvelle-avance')), findsNothing);
      for (final cle in ['modifier-avance', 'imputer-avance', 'archiver-avance']) {
        expect(find.byKey(Key('$cle-${uuid('a1')}')), findsNothing, reason: cle);
      }
    });

    testWidgets('Profil client : consultable, sans modifier, règlement, relance rapide ni « Régler »', (tester) async {
      await afficher(tester, peutGerer: false);
      await tester.tap(find.byKey(Key('profil-client-${uuid('c1')}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profil-nom')), findsOneWidget);
      expect(find.byKey(const Key('profil-solde')), findsOneWidget);
      for (final cle in ['profil-modifier', 'profil-reglement', 'profil-relance-rapide']) {
        expect(find.byKey(Key(cle)), findsNothing, reason: cle);
      }
      await tester.tap(find.byKey(const Key('profil-onglet-Créances')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profil-regler-0')), findsNothing);
      expect(await ecrits(), 1000 + 10 + 3000);
    });
  });

  group('avec manage-ventes (caissier, administrateur) : rien ne change', () {
    testWidgets('tous les boutons d\'écriture sont là', (tester) async {
      await afficher(tester, peutGerer: true);
      expect(find.byKey(const Key('nouveau-client')), findsOneWidget);
      expect(find.byKey(Key('modifier-client-${uuid('c1')}')), findsOneWidget);
      expect(find.byKey(Key('archiver-client-${uuid('c1')}')), findsOneWidget);
      await ouvrir(tester, 'Suivi des Dettes');
      expect(find.byKey(const Key('ajouter-recouvrement')), findsOneWidget);
      expect(find.byKey(const Key('creance-encaisser-0')), findsOneWidget);
      await ouvrir(tester, 'Relances Clients');
      expect(find.byKey(Key('relancer-whatsapp-${uuid('r1')}')), findsOneWidget);
      await ouvrir(tester, 'Historique Avances');
      expect(find.byKey(const Key('nouvelle-avance')), findsOneWidget);
    });

    testWidgets('le profil porte ses trois gestes', (tester) async {
      await afficher(tester, peutGerer: true);
      await tester.tap(find.byKey(Key('profil-client-${uuid('c1')}')));
      await tester.pumpAndSettle();
      for (final cle in ['profil-modifier', 'profil-reglement', 'profil-relance-rapide']) {
        expect(find.byKey(Key(cle)), findsOneWidget, reason: cle);
      }
    });
  });

  group('le branchement et les gardes de code (défense en profondeur)', () {
    test('le droit transmis à l\'écran est manage-ventes : le comptable non, le caissier oui', () {
      expect(PermissionsPoste.peut('comptable', 'manage-ventes'), isFalse);
      expect(PermissionsPoste.peut('caissier', 'manage-ventes'), isTrue);
      expect(PermissionsPoste.peut('admin', 'manage-ventes'), isTrue);
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains("peutGerer: PermissionsPoste.peut(_role, 'manage-ventes')"));
      expect(RefusDroit.message, 'Votre rôle ne permet pas cette action.');
    });

    test('chaque geste d\'écriture commence par RefusDroit.verifier (comme le authorize() de chaque méthode du web)', () {
      final garde = "if (!RefusDroit.verifier(context, widget.peutGerer)) return;";
      final ecran = File('lib/features/clients/clients_creances_screen.dart').readAsStringSync();
      for (final m in [
        '_ouvrirFiche(Customer? existant)',
        '_archiver(List<Customer> clients)',
        '_relancerRapide(LigneCreance l)',
        '_encaisser(DonneesClients d, LigneCreance? depart)',
        '_relancer(LigneCreance l, String canal, {String? message})',
        '_modifierAvance(DonneesClients d, LigneAvance l)',
        '_archiverAvance(LigneAvance l)',
        '_nouvelAcompte(DonneesClients d)',
        '_imputer(DonneesClients d, LigneAvance depart)',
      ]) {
        expect(ecran, contains('Future<void> $m async {\n    $garde'), reason: m);
      }
      final profil = File('lib/features/clients/profil_client_page.dart').readAsStringSync();
      for (final m in ['_modifierFiche(Customer c)', '_reglementGlobal(ProfilClient p)', '_reglerCreance(LigneCreance l)', '_relanceRapide(ProfilClient p)']) {
        expect(profil, contains('Future<void> $m async {\n    $garde'), reason: m);
      }
    });
  });
}
