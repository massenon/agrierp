import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_screen.dart';
import 'package:agrierp/features/achats/profil_fournisseur_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.70 — PROFIL FOURNISSEUR (`profile-fournisseur.html`).
///
/// ⚠️⚠️ « Solde Global Dû » est NET des règlements en attente : sans cela le poste
/// afficherait encore dû ce qui vient d'être payé et inviterait à le payer deux fois.
void main() {
  late AppDatabase db;
  late FournisseursRepository depot;

  String uuid(String graine) => graine.padLeft(36, '0');
  final aujourdhui = DateTime(2026, 10, 8);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FournisseursRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: uuid('f1'),
            name: 'Provenderie du Plateau',
            category: const Value("Aliments d'élevage"),
            phone: const Value('+229 97 12 34 56'),
          ),
        );
    await db
        .into(db.suppliers)
        .insert(SuppliersCompanion.insert(id: uuid('f2'), name: 'Autre'));
    await db
        .into(db.treasuryAccounts)
        .insert(
          TreasuryAccountsCompanion.insert(id: uuid('c1'), label: 'Caisse'),
        );
  });

  tearDown(() async => db.close());

  Future<void> dette(String cle, String f, double montant, {double paye = 0}) =>
      db
          .into(db.payables)
          .insert(
            PayablesCompanion.insert(
              id: uuid(cle),
              supplierId: uuid(f),
              amount: montant,
              amountPaid: Value(paye),
              dueDate: Value(DateTime(2026, 11, 1)),
              status: const Value('en_cours'),
            ),
          );

  Future<void> achat(
    String cle,
    String f,
    double total,
    DateTime date, {
    bool credit = false,
    bool synchronise = true,
  }) => db
      .into(db.purchases)
      .insert(
        PurchasesCompanion.insert(
          id: uuid(cle),
          deviceId: 'poste-test',
          updatedAt: date,
          syncStatus: Value(
            synchronise ? SyncStatus.synced : SyncStatus.pending,
          ),
          supplierId: uuid(f),
          paymentMode: 'especes',
          total: total,
          hasDebt: Value(credit),
          purchaseDate: date,
        ),
      );

  Future<void> afficher(WidgetTester tester, {String f = 'f1'}) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfilFournisseurScreen(
          depot: depot,
          fournisseurId: uuid(f),
          onRetour: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('dépôt', () {
    test(
      '⚠️ le solde global somme les dettes OUVERTES, net des règlements',
      () async {
        // 100 000 − 40 000 = 60 000 ; 30 000 soldée (exclue) ; 20 000 ouverte.
        await dette('d1', 'f1', 100000, paye: 40000);
        await dette('d2', 'f1', 30000, paye: 30000);
        await dette('d3', 'f1', 20000);
        await dette('d4', 'f2', 999999);

        var p = (await depot.profil(uuid('f1')))!;
        expect(p.dettes, hasLength(2));
        expect(p.soldeGlobal, 80000); // 60 000 + 20 000, jamais celui de f2

        await depot.enregistrerReglement(
          fournisseurId: uuid('f1'),
          montant: 25000,
          compteId: uuid('c1'),
          date: aujourdhui,
        );
        p = (await depot.profil(uuid('f1')))!;
        expect(p.soldeGlobal, 55000);
      },
    );

    test(
      'achats : les 20 derniers, du plus récent, de CE fournisseur',
      () async {
        for (var i = 0; i < 25; i++) {
          await achat('a$i', 'f1', 1000.0 + i, DateTime(2026, 1, 1 + i));
        }
        await achat('autre', 'f2', 5, aujourdhui);

        final p = (await depot.profil(uuid('f1')))!;

        expect(p.achats, hasLength(20));
        expect(p.achats.first.achat.total, 1024); // le plus récent
        expect(p.achats.every((a) => a.achat.supplierId == uuid('f1')), isTrue);
      },
    );

    test('fournisseur inconnu : null, pas d\'exception', () async {
      expect(await depot.profil(uuid('zz')), isNull);
    });
  });

  group('écran', () {
    testWidgets('porte l\'identité et le solde du fournisseur', (tester) async {
      await dette('d1', 'f1', 100000, paye: 40000);

      await afficher(tester);

      expect(find.text('Profil Fournisseur'), findsOneWidget);
      expect(find.text('Provenderie du Plateau'), findsOneWidget);
      expect(find.text('+229 97 12 34 56'), findsOneWidget);
      expect(find.text("Aliments d'élevage"), findsOneWidget);
      expect(find.text('PD'), findsOneWidget);
      expect(find.text('Solde Global Dû'), findsOneWidget);
      expect(find.text('60 000 FCFA'), findsOneWidget);
    });

    testWidgets('⚠️ « Modifier la fiche » écrit en attente et rafraîchit', (
      tester,
    ) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('profil-modifier')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('fiche-telephone')),
        '+229 90 11 22 33',
      );
      await tester.tap(find.byKey(const Key('fiche-enregistrer')));
      await tester.pumpAndSettle();

      final f = await (db.select(
        db.suppliers,
      )..where((x) => x.id.equals(uuid('f1')))).getSingle();
      expect(f.phone, '+229 90 11 22 33');
      expect(f.syncStatus, SyncStatus.pending);
      expect(find.text('+229 90 11 22 33'), findsOneWidget);
    });

    testWidgets('onglet Achats : statut selon dette ou attente', (
      tester,
    ) async {
      await achat('a1', 'f1', 185000, DateTime(2026, 7, 14));
      await achat('a2', 'f1', 340000, DateTime(2026, 6, 29), credit: true);
      await achat('a3', 'f1', 1000, DateTime(2026, 8, 1), synchronise: false);

      await afficher(tester);

      expect(find.text('14/07/2026'), findsOneWidget);
      expect(find.text('185 000'), findsOneWidget);
      expect(find.text('Payé entièrement'), findsOneWidget);
      expect(find.text('Dette fournisseur'), findsOneWidget);
      expect(find.text('En attente de synchronisation'), findsOneWidget);
    });

    testWidgets('onglet Dettes : message quand tout est réglé', (tester) async {
      await dette('d1', 'f1', 5000, paye: 5000);

      await afficher(tester);
      await tester.tap(find.byKey(const Key('profil-onglet-Dettes')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profil-sans-dette')), findsOneWidget);
    });

    testWidgets('onglet Commandes : statut reçu et dates', (tester) async {
      await db
          .into(db.purchaseOrders)
          .insert(
            PurchaseOrdersCompanion.insert(
              id: uuid('bc1'),
              supplierId: Value(uuid('f1')),
              status: const Value('recu'),
              createdAt: Value(DateTime(2026, 7, 12)),
              expectedDeliveryDate: Value(DateTime(2026, 7, 18)),
            ),
          );

      await afficher(tester);
      await tester.tap(find.byKey(const Key('profil-onglet-Commandes')));
      await tester.pumpAndSettle();

      expect(find.text('12/07/2026'), findsOneWidget);
      expect(find.text('18/07/2026'), findsOneWidget);
      expect(find.text('Reçu'), findsOneWidget);
    });

    testWidgets(
      '⚠️ le règlement est enregistré en attente et le solde baisse',
      (tester) async {
        await dette('d1', 'f1', 100000);

        await afficher(tester);
        await tester.tap(find.byKey(const Key('profil-reglement')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('reglement-profil-solde')), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('reglement-profil-montant')),
          '30000',
        );
        await tester.tap(find.byKey(const Key('reglement-profil-compte')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Caisse').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reglement-profil-valider')));
        await tester.pumpAndSettle();

        final r = await db.select(db.supplierPayments).getSingle();
        expect(r.amount, 30000);
        expect(r.supplierId, uuid('f1'));
        expect(r.syncStatus, SyncStatus.pending);
        expect(find.text('70 000 FCFA'), findsOneWidget);
      },
    );

    testWidgets('⚠️ un montant au-dessus du solde reste dans la modale', (
      tester,
    ) async {
      await dette('d1', 'f1', 10000);

      await afficher(tester);
      await tester.tap(find.byKey(const Key('profil-reglement')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('reglement-profil-montant')),
        '50000',
      );
      await tester.tap(find.byKey(const Key('reglement-profil-compte')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caisse').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reglement-profil-valider')));
      await tester.pumpAndSettle();

      expect(find.textContaining('dépasse ce qui reste dû'), findsOneWidget);
      expect(await db.select(db.supplierPayments).get(), isEmpty);
    });

    testWidgets('fournisseur disparu : phrase, pas de plantage', (
      tester,
    ) async {
      await afficher(tester, f: 'zz');

      expect(find.byKey(const Key('profil-introuvable')), findsOneWidget);
    });
  });

  group('depuis le hub', () {
    testWidgets('le nom d\'un fournisseur ouvre son profil, Retour revient', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: FournisseursScreen(depot: depot)),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('onglet-fournisseurs-Fiches Fournisseurs')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profil-fournisseur-1')));
      await tester.pumpAndSettle();

      expect(find.text('Profil Fournisseur'), findsOneWidget);

      await tester.tap(find.byKey(const Key('profil-retour')));
      await tester.pumpAndSettle();

      expect(find.text('Profil Fournisseur'), findsNothing);
      expect(find.text('Fiches Fournisseurs'), findsWidgets);
    });
  });
}
