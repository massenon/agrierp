import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/clients/clients_creances_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket VC-3 — « PROFIL CLIENT » AU POSTE (`profile-client.blade.php`).
///
/// Le poste écrit le FAIT (règlement global, relance rapide) ; le « Solde Global Dû » est la somme des soldes NETS des
/// créances, ce que le serveur (`CustomerSettlementService::reglerSoldeGlobal`) impute aux plus anciennes d'abord.
void main() {
  late AppDatabase db;
  late ClientsCreancesRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ClientsCreancesRepository(database: db, deviceId: 'poste-test');
    await db.into(db.customers).insert(CustomersCompanion.insert(id: uuid('c1'), name: 'AMOUSSOU Régis', phone: const Value('22997000000'), creditLimit: const Value(200000)));
    await db.into(db.customers).insert(CustomersCompanion.insert(id: uuid('c2'), name: 'Autre Client'));
    await db.into(db.treasuryAccounts).insert(TreasuryAccountsCompanion.insert(id: uuid('t1'), label: 'Caisse principale', balance: const Value(100000)));
    // r2 est PLUS ANCIENNE (échéance 1er novembre) que r1 (8 novembre).
    await db.into(db.receivables).insert(ReceivablesCompanion.insert(id: uuid('r1'), customerId: uuid('c1'), amount: 100000, dueDate: Value(DateTime(2026, 11, 8))));
    await db.into(db.receivables).insert(ReceivablesCompanion.insert(id: uuid('r2'), customerId: uuid('c1'), amount: 50000, dueDate: Value(DateTime(2026, 11, 1))));
    await db.into(db.receivables).insert(ReceivablesCompanion.insert(id: uuid('r3'), customerId: uuid('c2'), amount: 9000, dueDate: Value(DateTime(2026, 11, 1))));
  });
  tearDown(() async => db.close());

  group('dépôt', () {
    test('le solde global est la somme des soldes dus du client, pas ceux des autres', () async {
      final p = (await depot.profil(uuid('c1')))!;

      expect(p.soldeGlobal, 150000);
      expect(p.creances.map((l) => l.creance.id), [uuid('r2'), uuid('r1')], reason: 'les plus anciennes d\'abord');
      expect(p.pourcentageCredit, 75, reason: '150 000 sur 200 000 autorisés');
    });

    test('⚠️⚠️ un règlement global s\'impute aux plus anciennes créances d\'abord et reste pending', () async {
      final e = await depot.encaisserSolde(clientId: uuid('c1'), montant: 120000, compteId: uuid('t1'));

      expect(e.syncStatus, SyncStatus.pending);
      expect(e.receivableId, isNull, reason: 'aucune créance visée : le serveur répartit');
      final p = (await depot.profil(uuid('c1')))!;
      expect(p.soldeGlobal, 30000);
      expect(p.creances.single.creance.id, uuid('r1'), reason: 'r2 (50 000) est soldée en premier, r1 garde 30 000');
      expect(p.creances.single.resteDu, 30000);
      expect((await db.select(db.receivables).get()).every((r) => r.amountPaid == 0), isTrue, reason: 'le poste ne touche jamais amount_paid');
    });

    test('un règlement global est plafonné par le solde global et refusé s\'il est nul', () async {
      await expectLater(
        depot.encaisserSolde(clientId: uuid('c1'), montant: 150001, compteId: uuid('t1')),
        throwsA(isA<SaisieRefusee>()),
      );
      await expectLater(depot.encaisserSolde(clientId: uuid('c1'), montant: 0, compteId: uuid('t1')), throwsA(isA<SaisieRefusee>()));
      expect(await db.select(db.receivablePayments).get(), isEmpty);
    });

    test('la relance rapide s\'écrit sans créance, pending, pour le client', () async {
      final r = await depot.relancer(clientId: uuid('c1'), canal: 'whatsapp', message: 'Relance rapide — solde dû 150 000 FCFA.');

      expect(r.customerId, uuid('c1'));
      expect(r.receivableId, isNull);
      expect(r.syncStatus, SyncStatus.pending);
      expect((await depot.profil(uuid('c1')))!.relances.single.id, r.id);
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      await tester.pumpWidget(MaterialApp(home: ClientsCreancesScreen(depot: depot, maintenant: () => DateTime(2026, 10, 28, 10))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('profil-client-${uuid('c1')}')));
      await tester.pumpAndSettle();
    }

    String texteDe(WidgetTester tester, String cle) => tester.widget<Text>(find.byKey(Key(cle))).data!;

    testWidgets('la fiche montre initiales, nom, téléphone, solde global et barre de crédit', (tester) async {
      await afficher(tester);

      expect(find.text('Profil Client'), findsOneWidget);
      expect(texteDe(tester, 'profil-initiales'), 'AR');
      expect(texteDe(tester, 'profil-nom'), 'AMOUSSOU Régis');
      expect(texteDe(tester, 'profil-telephone'), '22997000000');
      expect(texteDe(tester, 'profil-solde'), '150 000 FCFA');
      expect(texteDe(tester, 'profil-credit'), '150 000 FCFA utilisés sur 200 000 FCFA autorisés (75%)');
    });

    testWidgets('⚠️ les onglets Créances et Relances, puis « Retour » ramène à la liste', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('profil-onglet-Créances')));
      await tester.pumpAndSettle();
      expect(texteDe(tester, 'profil-creance-solde-0'), '50 000', reason: 'la plus ancienne en tête');
      expect(texteDe(tester, 'profil-creance-solde-1'), '100 000');

      await tester.tap(find.byKey(const Key('profil-onglet-Relances')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profil-relances-vide')), findsOneWidget);
      expect(find.text('Aucune relance envoyée à ce client.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('profil-retour')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nouveau-client')), findsOneWidget);
    });

    testWidgets('⚠️⚠️ « Enregistrer un règlement » règle le solde GLOBAL et le solde baisse', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('profil-reglement')));
      await tester.pumpAndSettle();
      expect(find.text('Enregistrer un Règlement'), findsOneWidget);
      expect(find.text('Référence'), findsOneWidget);
      expect(texteDe(tester, 'recouvrement-solde'), '150 000 FCFA');

      await tester.enterText(find.byKey(const Key('recouvrement-montant')), '120000');
      await tester.pump();
      expect(texteDe(tester, 'recouvrement-nouveau-solde'), '30 000 FCFA');
      await tester.tap(find.byKey(const Key('recouvrement-compte')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caisse principale').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider le Règlement'));
      await tester.pumpAndSettle();
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));

      expect((await db.select(db.receivablePayments).get()).single.amount, 120000);
      expect(texteDe(tester, 'profil-solde'), '30 000 FCFA');
    });

    testWidgets('« Envoyer une relance rapide » écrit une relance WhatsApp et l\'onglet Relances la liste', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('profil-relance-rapide')));
      await tester.pumpAndSettle();
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));

      final r = (await db.select(db.customerReminders).get()).single;
      expect(r.channel, 'whatsapp');
      expect(r.message, 'Relance rapide — solde dû 150 000 FCFA.');

      await tester.tap(find.byKey(const Key('profil-onglet-Relances')));
      await tester.pumpAndSettle();
      expect(texteDe(tester, 'profil-relance-canal-0'), 'WhatsApp');
    });
  });
}
