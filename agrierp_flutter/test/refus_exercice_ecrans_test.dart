import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/achats/achats_commandes_screen.dart';
import 'package:agrierp/features/achats/achats_modales.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_screen.dart';
import 'package:agrierp/features/achats/profil_fournisseur_screen.dart';
import 'package:agrierp/features/achats/saisie_depenses_screen.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/clients/clients_creances_screen.dart';
import 'package:agrierp/features/elevage/fiche_escargots_screen.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/stocks/gestion_stocks_screen.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'depenses_aide.dart';

/// Ticket EX6 (EF7) — LE REFUS D'EXERCICE À L'ÉCRAN, À LA PLACE QUE LUI DONNE LA VUE BLADE, et les calendriers bornés.
///
/// Les dépôts refusent (voir `refus_exercice_clos_test.dart`) ; ici, chaque écran montre le motif R4 là où le web le
/// montre :
///  - sous « Date » : Saisie des Dépenses (`addError('expenseDate')`), Ajout de stock (`addError('addDate')`),
///    règlement des Dettes Fournisseurs (`addError('paymentDate')`, ticket EX6 au web) ;
///  - sous un autre champ : remboursement fournisseur sous « Montant » (`addError('refundAmount')`), retour fournisseur
///    sous « Motif » (`addError('returnReason')`) ;
///  - en toast d'erreur : achat (« Achat refusé : » + motif, `EnregistrerAchat`), archivage d'une dépense, inventaire
///    (`validateAdjustment`), avance client (`HistoriqueAvances`), règlement depuis le profil fournisseur, fiche
///    d'élevage (`saveDay`).
///
/// Horloge figée au mardi 20/10/2026 10:00 (heure du Bénin). Décor « clos » : 2025 et 2026 CLÔTURÉS — toute saisie du
/// jour est refusée « L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 20/10/2026. » (littéral écrit à
/// la main).
const _clos = "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 20/10/2026.";

String _uuid(String cle) {
  final hex = cle.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  final h = hex.padRight(32, '0').substring(0, 32);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-8${h.substring(17, 20)}-${h.substring(20, 32)}';
}

void main() {
  late AppDatabase db;

  Future<void> exercice(int annee, String statut) => db
      .into(db.fiscalYears)
      .insert(
        FiscalYearsCompanion.insert(
          id: _uuid('ex$annee'),
          year: annee,
          startDate: Value(DateTime(annee)),
          endDate: Value(DateTime(annee, 12, 31)),
          status: Value(statut),
        ),
      );

  /// 2025 et 2026 clos : aujourd'hui (20/10/2026) est dans un exercice clos.
  Future<void> decorClos() async {
    await exercice(2025, 'cloture');
    await exercice(2026, 'cloture');
  }

  /// 2024 clos, 2025 et 2026 ouverts : bornes des calendriers = 01/01/2025.
  Future<void> decorOuvert() async {
    await exercice(2024, 'cloture');
    await exercice(2025, 'ouvert');
    await exercice(2026, 'ouvert');
  }

  setUp(() async {
    HeureBenin.horloge = () => DateTime.utc(2026, 10, 20, 9);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.treasuryAccounts)
        .insert(TreasuryAccountsCompanion.insert(id: _uuid('t1'), label: 'Caisse Physique', type: const Value('caisse'), balance: const Value(500000)));
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: _uuid('f1'), name: 'Provenderie du Plateau'));
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: _uuid('p1'),
            sku: 'ALI-001',
            name: 'Aliment ponte 25kg',
            unit: 'sac',
            pricingMode: 'fixe',
            stockQty: const Value(30),
          ),
        );
  });

  tearDown(() async {
    ToastAgri.toutRetirer();
    HeureBenin.reinitialiser();
    await db.close();
  });

  void grandEcran(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> choisir(WidgetTester tester, String cle, String texte) async {
    await tester.tap(find.byKey(Key(cle)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(texte).last);
    await tester.pumpAndSettle();
  }

  /// Le toast du web reste 3,5 s : on le laisse partir, sinon sa minuterie survit au test.
  Future<void> laisserPartirLeToast(WidgetTester tester) async {
    await tester.pump(ToastAgri.duree);
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, String cle) => tester.widget<Text>(find.byKey(Key(cle))).data!;

  /// Ouvre le calendrier par [cle], rend sa borne basse et le referme.
  Future<DateTime> premierJourDuCalendrier(WidgetTester tester, String cle) async {
    await tester.tap(find.byKey(Key(cle)));
    await tester.pumpAndSettle();
    final dialogue = find.byType(DatePickerDialog);
    final premier = tester.widget<DatePickerDialog>(dialogue).firstDate;
    Navigator.of(tester.element(dialogue)).pop();
    await tester.pumpAndSettle();
    return premier;
  }

  group('Saisie des Dépenses', () {
    setUp(() async {
      await semerPlanDeCharge(db);
    });

    Future<void> afficher(WidgetTester tester) async {
      grandEcran(tester);
      await tester.pumpWidget(
        MaterialApp(home: SaisieDepensesScreen(depot: DepensesRepository(database: db, deviceId: 'poste-test'))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('nouvelle dépense d’un exercice clos : le motif R4 sous « Date », rien d’écrit', (tester) async {
      await decorClos();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('bouton-nouvelle-depense')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ-ligne.0.libelle')), 'Sac de provende ponte');
      await tester.enterText(find.byKey(const Key('champ-ligne.0.montant')), '25000');
      await choisir(tester, 'liste-ligne-0-compte', '601 - Achats de marchandises');
      await choisir(tester, 'liste-mode', 'Espèces');
      await choisir(tester, 'liste-compte', 'Caisse Physique (500 000 FCFA)');
      await choisir(tester, 'liste-centre', 'Général');   // DEP6 : le centre de coût est obligatoire
      await tester.tap(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.pumpAndSettle();

      expect(texte(tester, 'erreur-date'), _clos);
      expect(await db.select(db.expenses).get(), isEmpty);
    });

    testWidgets('archiver une dépense d’un exercice clos : le motif R4 en toast, elle reste active', (tester) async {
      await decorClos();
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: _uuid('e1'),
              deviceId: 'serveur',
              syncStatus: const Value(SyncStatus.synced),
              updatedAt: DateTime(2026, 10, 20),
              expenseDate: DateTime(2026, 10, 20),
              label: 'Facture SBEE',
              category: '601 - Aliments',
              amount: 25000,
              treasuryAccountId: Value(_uuid('t1')),
            ),
          );
      await afficher(tester);

      await tester.tap(find.byKey(Key('depense-archiver-${_uuid('e1')}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('archivage-depense-confirmer')));
      await tester.pumpAndSettle();

      expect(find.text(_clos), findsOneWidget);
    await laisserPartirLeToast(tester);
      await laisserPartirLeToast(tester);
      final d = await db.select(db.expenses).getSingle();
      expect(d.isActive, isTrue);
      expect(d.syncStatus, SyncStatus.synced);
    });

    testWidgets('calendrier « Date de la Transaction » borné au plus ancien exercice ouvert', (tester) async {
      await decorOuvert();
      await afficher(tester);
      await tester.tap(find.byKey(const Key('bouton-nouvelle-depense')));
      await tester.pumpAndSettle();
      expect(await premierJourDuCalendrier(tester, 'champ-date'), DateTime(2025));
    });
  });

  group('Gestion des Stocks', () {
    Future<void> afficher(WidgetTester tester) async {
      grandEcran(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: GestionStocksScreen(depot: StocksRepository(database: db, deviceId: 'poste-test'), peutGerer: true),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('ajout de stock d’un exercice clos : le motif R4 sous « Date », rien d’écrit', (tester) async {
      await decorClos();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('stocks-ajouter')));
      await tester.pumpAndSettle();
      await choisir(tester, 'ajout-produit', 'Aliment ponte 25kg');
      await tester.enterText(find.byKey(const Key('ajout-quantite')), '12');
      await tester.tap(find.byKey(const Key('ajout-enregistrer')));
      await tester.pumpAndSettle();

      expect(texte(tester, 'ajout-erreur-date'), _clos);
      expect(await db.select(db.stockAdjustments).get(), isEmpty);
    });

    testWidgets('calendrier « Date du Nouveau Stock » borné au lendemain du dernier exercice clos', (tester) async {
      await decorOuvert();
      await afficher(tester);
      await tester.tap(find.byKey(const Key('stocks-ajouter')));
      await tester.pumpAndSettle();
      expect(await premierJourDuCalendrier(tester, 'ajout-date'), DateTime(2025));
    });

    testWidgets('inventaire d’un exercice clos : le motif R4 en toast, rien d’écrit', (tester) async {
      await decorClos();
      await afficher(tester);
      await tester.tap(find.byKey(const Key('onglet-stocks-Ajustement / Correction')));
      await tester.pumpAndSettle();

      await choisir(tester, 'adj-produit', 'Aliment ponte 25kg (Théorique : 30)');
      await tester.enterText(find.byKey(const Key('adj-physique')), '25');
      await tester.tap(find.byKey(const Key('adj-valider')));
      await tester.pumpAndSettle();

      expect(find.text(_clos), findsOneWidget);
    await laisserPartirLeToast(tester);
      await laisserPartirLeToast(tester);
      expect(await db.select(db.stockAdjustments).get(), isEmpty);
    });
  });

  group('Fournisseurs — règlement', () {
    setUp(() async {
      await db
          .into(db.payables)
          .insert(PayablesCompanion.insert(id: _uuid('d1'), supplierId: _uuid('f1'), amount: 90000));
    });

    Future<void> ouvrirModale(WidgetTester tester) async {
      grandEcran(tester);
      await tester.pumpWidget(
        MaterialApp(home: FournisseursScreen(depot: FournisseursRepository(database: db, deviceId: 'poste-test'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onglet-fournisseurs-Dettes Fournisseurs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('enregistrer-reglement')));
      await tester.pumpAndSettle();
    }

    testWidgets('règlement d’un exercice clos : le motif R4 sous « Date de règlement », rien d’écrit', (
      tester,
    ) async {
      await decorClos();
      await ouvrirModale(tester);

      await choisir(tester, 'reglement-fournisseur', 'Provenderie du Plateau');
      await tester.enterText(find.byKey(const Key('reglement-montant')), '20000');
      await choisir(tester, 'reglement-compte', 'Caisse Physique');
      await tester.tap(find.byKey(const Key('reglement-enregistrer')));
      await tester.pumpAndSettle();

      expect(texte(tester, 'reglement-erreur-date'), _clos);
      expect(find.byKey(const Key('reglement-erreur')), findsNothing);
      expect(await db.select(db.supplierPayments).get(), isEmpty);
    });

    testWidgets('calendrier « Date de règlement » borné au plus ancien exercice ouvert', (tester) async {
      await decorOuvert();
      await ouvrirModale(tester);
      expect(await premierJourDuCalendrier(tester, 'reglement-date'), DateTime(2025));
    });
  });

  testWidgets('Profil fournisseur — règlement du jour dans un exercice clos : motif R4 en toast', (tester) async {
    await decorClos();
    await db
        .into(db.payables)
        .insert(PayablesCompanion.insert(id: _uuid('d1'), supplierId: _uuid('f1'), amount: 90000));
    grandEcran(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilFournisseurScreen(
          depot: FournisseursRepository(database: db, deviceId: 'poste-test'),
          fournisseurId: _uuid('f1'),
          onRetour: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profil-reglement')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reglement-profil-montant')), '30000');
    await choisir(tester, 'reglement-profil-compte', 'Caisse Physique');
    await tester.tap(find.byKey(const Key('reglement-profil-valider')));
    await tester.pumpAndSettle();

    expect(find.text(_clos), findsOneWidget);
    await laisserPartirLeToast(tester);
    expect(await db.select(db.supplierPayments).get(), isEmpty);
  });

  group('Achats & Commandes', () {
    Future<void> afficher(WidgetTester tester, {String? onglet}) async {
      grandEcran(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AchatsCommandesScreen(
            depot: AchatsRepository(database: db, identifiantPoste: 'poste-test'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (onglet != null) {
        await tester.tap(find.byKey(Key('onglet-achats-$onglet')));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('achat du jour dans un exercice clos : « Achat refusé : » + motif R4 en toast, panier gardé', (
      tester,
    ) async {
      await decorClos();
      await afficher(tester);

      await choisir(tester, 'liste-fournisseur', 'Provenderie du Plateau');
      await choisir(tester, 'liste-produit', 'Aliment ponte 25kg');
      await tester.enterText(find.byKey(const Key('champ-quantite')), '2');
      await tester.enterText(find.byKey(const Key('champ-prix-unitaire')), '1000');
      await tester.tap(find.byKey(const Key('ajouter-au-bon')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('enregistrer-achat')));
      await tester.pumpAndSettle();

      expect(find.text('Achat refusé : $_clos'), findsOneWidget);
      await laisserPartirLeToast(tester);
      expect(await db.select(db.purchases).get(), isEmpty);
      expect(find.text('2 000 FCFA'), findsWidgets, reason: 'le panier est conservé, comme au web');
    });

    testWidgets('retour d’un achat le jour d’un exercice clos : le motif R4 sous « Motif »', (tester) async {
      await decorClos();
      await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: _uuid('a1'),
              deviceId: 'serveur',
              updatedAt: DateTime(2026, 9, 2),
              syncStatus: const Value(SyncStatus.synced),
              supplierId: _uuid('f1'),
              supplierName: const Value('Provenderie du Plateau'),
              paymentMode: 'especes',
              total: 100000,
              purchaseDate: DateTime(2026, 9, 2),
            ),
          );
      await afficher(tester, onglet: "Liste d'Achats");

      await tester.tap(find.byKey(const Key('retour-achat-0')));
      await tester.pumpAndSettle();
      await choisir(tester, 'retour-motif', motifsRetour[0]);
      await tester.tap(find.byKey(const Key('retour-confirmer')));
      await tester.pumpAndSettle();

      expect(texte(tester, 'retour-refus'), _clos);
      expect(await db.select(db.purchaseReturns).get(), isEmpty);
    });

    group('remboursement', () {
      setUp(() async {
        await db
            .into(db.supplierCredits)
            .insert(SupplierCreditsCompanion.insert(supplierId: _uuid('f1'), openCredit: 40000));
      });

      testWidgets('d’un exercice clos : le motif R4 sous « Montant Remboursé », rien d’écrit', (tester) async {
        await decorClos();
        await afficher(tester, onglet: "Liste d'Achats");

        await tester.tap(find.byKey(const Key('ajouter-remboursement')));
        await tester.pumpAndSettle();
        await choisir(tester, 'remb-fournisseur', 'Provenderie du Plateau');
        await tester.enterText(find.byKey(const Key('remb-montant')), '10000');
        await tester.tap(find.byKey(const Key('remb-enregistrer')));
        await tester.pumpAndSettle();

        expect(texte(tester, 'remb-erreur-montant'), _clos);
        expect(await db.select(db.supplierRefunds).get(), isEmpty);
      });

      testWidgets('calendrier « Date du Remboursement » borné au plus ancien exercice ouvert', (tester) async {
        await decorOuvert();
        await afficher(tester, onglet: "Liste d'Achats");
        await tester.tap(find.byKey(const Key('ajouter-remboursement')));
        await tester.pumpAndSettle();
        expect(await premierJourDuCalendrier(tester, 'remb-date'), DateTime(2025));
      });
    });
  });

  testWidgets('Historique des Avances — avance du jour dans un exercice clos : motif R4 en toast, rien d’écrit', (
    tester,
  ) async {
    await decorClos();
    await db.into(db.customers).insert(CustomersCompanion.insert(id: _uuid('c1'), name: 'AMOUSSOU Régis'));
    grandEcran(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ClientsCreancesScreen(
          depot: ClientsCreancesRepository(database: db, deviceId: 'poste-test'),
          maintenant: () => DateTime(2026, 10, 20, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onglet-clients-Historique Avances')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nouvelle-avance')));
    await tester.pumpAndSettle();
    await choisir(tester, 'acompte-client', 'AMOUSSOU Régis');
    await tester.enterText(find.byKey(const Key('acompte-motif')), "Réservation 50 poussins d'un jour");
    await tester.enterText(find.byKey(const Key('acompte-montant')), '20000');
    await choisir(tester, 'acompte-compte', 'Caisse Physique');
    await tester.tap(find.byKey(const Key('acompte-enregistrer')));
    await tester.pumpAndSettle();

    expect(find.text(_clos), findsOneWidget);
    await laisserPartirLeToast(tester);
    expect(find.text('Nouvel Acompte'), findsOneWidget, reason: 'la modale reste ouverte, comme au web');
    expect(await db.select(db.customerAdvances).get(), isEmpty);
  });

  testWidgets('Fiche Escargots — fiche du jour dans un exercice clos (Q3) : motif R4 en toast, rien d’écrit', (
    tester,
  ) async {
    await decorClos();
    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: _uuid('b1'),
            code: 'HEL-2026-01',
            speciesId: _uuid('esp'),
            speciesCode: const Value('helico'),
            stage: const Value('engraissement'),
            initialQuantity: const Value(2000),
            currentQuantity: const Value(2000),
          ),
        );
    await db
        .into(db.modulesConfig)
        .insert(ModulesConfigCompanion.insert(id: _uuid('mod'), speciesCode: 'helico', isEnabled: const Value(true)));
    grandEcran(tester);
    final depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    await tester.pumpWidget(
      MaterialApp(
        home: FicheEscargotsScreen(
          depot: depot,
          soins: SoinsRepository(database: db, deviceId: 'poste-test'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Depuis EX7 + EX8, un jour d'exercice clos est en LECTURE SEULE : bandeau, bouton sans effet. Le refus R4
    // du serveur reste la garantie (testé côté Laravel et à l'envoi) ; ici, rien ne doit s'écrire.
    expect(find.textContaining('lecture seule'), findsWidgets);
    final bouton = find.byKey(const Key('bouton-enregistrer'));
    if (bouton.evaluate().isNotEmpty) {
      await tester.ensureVisible(bouton);
      await tester.tap(bouton, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    await laisserPartirLeToast(tester);
    expect(find.text('Jour enregistré avec succès.'), findsNothing);
    expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
  });
}
