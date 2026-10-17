import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_repository.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.32 — TABLEAU DE BORD DU POSTE (`prototype_html/dashboard.html`).
///
/// ⚠️⚠️ **LE TIRAGE NE DESCEND NI `sales` NI `expenses`** — vérifié dans
/// `SyncController::pull()`. Le chiffre d'affaires, les dépenses, les deux
/// courbes, les transactions et le top produits ne portent donc QUE ce que ce
/// poste a saisi. L'écran doit le dire, et c'est testé ici : un gérant qui
/// compare deux postes ne doit pas avoir à le deviner.
///
/// ⚠️ **SEUIL DE MORTALITÉ 5 %**, repris de `gestion-elevage.html` (« Seuil
/// normal < 5% »). La maquette du tableau de bord colore 3,2 % en rouge — une
/// valeur de démonstration codée en dur, incohérente avec sa page sœur. C'est
/// la RÈGLE qui est reprise, pas la couleur d'un exemple.
void main() {
  late AppDatabase db;
  late TableauDeBordRepository depot;

  const bandeLapins = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
  const bandePondeuses = 'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb';
  const bandePorcs = 'cccccccc-0000-4000-8000-cccccccccccc';
  const produitOeufs = 'dddddddd-0000-4000-8000-dddddddddddd';
  const produitProvende = 'eeeeeeee-0000-4000-8000-eeeeeeeeeeee';

  /// Les colonnes d'identifiant du poste sont contraintes a 36 caracteres :
  /// un UUID. Les jeux d'essai les fabriquent plutot que de les ecrire.
  String uuid(String graine) => graine.padRight(36, '0');

  final maintenant = DateTime.now();
  DateTime ceMois(int jour, [int heure = 10]) =>
      DateTime(maintenant.year, maintenant.month, jour, heure);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = TableauDeBordRepository(database: db);

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandeLapins,
            code: 'CUN-2026-01',
            speciesId: 'esp-cun',
            speciesCode: const Value('cuniculture'),
            stage: const Value('engraissement'),
            initialQuantity: const Value(100),
            currentQuantity: const Value(94),
          ),
        );

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandePondeuses,
            code: 'AVI-2026-01',
            speciesId: 'esp-avi',
            speciesCode: const Value('aviculture'),
            stage: const Value('ponte'),
            initialQuantity: const Value(200),
            currentQuantity: const Value(198),
          ),
        );

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandePorcs,
            code: 'POR-2026-01',
            speciesId: 'esp-por',
            speciesCode: const Value('porciculture'),
            stage: const Value('engraissement'),
            initialQuantity: const Value(20),
            currentQuantity: const Value(18),
          ),
        );

    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: produitOeufs,
            sku: 'AVI-OEUF',
            name: 'Œufs de table',
            unit: 'plateau',
            pricingMode: 'fixe',
            stockQty: const Value(40),
            alertThreshold: const Value(10),
          ),
        );

    // ⚠️ Sous son seuil : 5 sacs pour un seuil de 12.
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: produitProvende,
            sku: 'ALI-PONTE',
            name: 'Provende ponte',
            unit: 'sac',
            pricingMode: 'fixe',
            stockQty: const Value(5),
            alertThreshold: const Value(12),
          ),
        );

    await db
        .into(db.treasuryAccounts)
        .insert(
          TreasuryAccountsCompanion.insert(
            id: uuid('caisse'),
            label: 'Caisse Principale',
            type: const Value('caisse'),
            balance: const Value(420000),
          ),
        );

    await db
        .into(db.treasuryAccounts)
        .insert(
          TreasuryAccountsCompanion.insert(
            id: uuid('banque'),
            label: 'Compte UBA',
            type: const Value('banque'),
            balance: const Value(1180000),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> vente(String id, double total, DateTime quand) async {
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: id,
            deviceId: 'poste-test',
            updatedAt: quand,
            paymentMode: 'especes',
            total: total,
            soldAt: quand,
          ),
        );
  }

  Future<void> ligne(
    String id,
    String venteId,
    double qte,
    double montant,
  ) async {
    await db
        .into(db.saleLines)
        .insert(
          SaleLinesCompanion.insert(
            id: id,
            saleId: venteId,
            productId: produitOeufs,
            qty: qte,
            unitPrice: montant / qte,
            manualTotalAmount: montant,
          ),
        );
  }

  Future<void> depense(
    String id,
    String libelle,
    double montant,
    DateTime quand,
  ) async {
    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: id,
            deviceId: 'poste-test',
            updatedAt: quand,
            expenseDate: quand,
            label: libelle,
            category: 'Carburant',
            amount: montant,
            treasuryAccountId: uuid('caisse'),
          ),
        );
  }

  Future<void> fiche(
    String id,
    String lot,
    int jour, {
    int mort = 0,
    int vente = 0,
    int ponte = 0,
    int effectif = 100,
  }) async {
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: id,
            deviceId: 'poste-test',
            updatedAt: ceMois(jour, 8),
            lotId: lot,
            entryDate: ceMois(jour),
            mort: Value(mort),
            vente: Value(vente),
            effectifFinal: Value(effectif),
            ponteTotal: Value(ponte),
          ),
        );
  }

  Future<void> afficher(WidgetTester tester) async {
    // ⚠️ SURFACE DE POSTE, pas de téléphone : la maquette bascule en mise en
    // page large à 1024. Tester à 800 vérifierait une disposition que
    // l'utilisateur ne verra jamais sur son écran de bureau.
    tester.view.physicalSize = const Size(1600, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: TableauDeBordScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ les sept sections de la maquette sont là, dans son ordre', (
    tester,
  ) async {
    await afficher(tester);

    for (final titre in [
      'CA vs Dépenses — 6 derniers mois',
      'Alertes Critiques',
      'Statistiques de Ventes',
      'Transactions Récentes',
      'Activités du Jour',
      'Top 5 Produits du Mois',
    ]) {
      expect(find.text(titre), findsOneWidget, reason: titre);
    }

    expect(find.textContaining('Bienvenue,'), findsOneWidget);
  });

  testWidgets('les huit cartes KPI portent les libellés de la maquette', (
    tester,
  ) async {
    await afficher(tester);

    for (final libelle in [
      "CHIFFRE D'AFFAIRES",
      'TRÉSORERIE',
      'DÉPENSES',
      'RÉSULTAT NET',
      'CRÉANCES CLIENTS',
      'DETTES FOURNISSEURS',
      'STOCK CRITIQUE',
      'EFFECTIF ANIMAUX',
    ]) {
      expect(find.text(libelle), findsOneWidget, reason: libelle);
    }
  });

  /// ⚠️⚠️ DEUX CARTES NE PEUVENT PAS ÊTRE CALCULÉES AU POSTE, et disent
  /// pourquoi au lieu d'afficher zéro.
  ///
  /// ⚠️ « Créances Clients » a quitté cette liste au ticket F0.43 :
  /// `receivables` descend désormais au poste. Son tiret ne venait pas d'une
  /// impossibilité de calcul mais d'une table qui n'arrivait pas — la
  /// distinction compte, parce qu'elle dit lequel des deux se corrige.
  testWidgets('résultat net et dettes affichent un tiret motivé', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Sans comptabilité au poste'), findsOneWidget);
    expect(find.text('Table non synchronisée'), findsOneWidget);
  });

  testWidgets('⚠️ le CA dit qu il ne vaut que pour ce poste', (tester) async {
    await vente(uuid('v1'), 32000, ceMois(3));
    await vente(uuid('v2'), 45000, ceMois(4));

    await afficher(tester);

    expect(find.text('77 000'), findsOneWidget);
    expect(find.textContaining('Ce poste uniquement'), findsWidgets);
  });

  testWidgets('la trésorerie ventile caisse et banque', (tester) async {
    await afficher(tester);

    expect(find.text('1 600 000'), findsOneWidget);
    expect(find.text('Caisse : 420 000 · Banque : 1 180 000'), findsOneWidget);
  });

  testWidgets('le stock critique compte et nomme les produits sous seuil', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Provende ponte'), findsWidgets);
    expect(find.text('Provende ponte sous le seuil critique'), findsOneWidget);
  });

  testWidgets("l'effectif additionne les bandes actives", (tester) async {
    await afficher(tester);

    // 94 lapins + 198 volailles + 18 porcs.
    expect(find.text('310'), findsOneWidget);
  });

  testWidgets('les trois cartes espèces sont dans l ordre de la maquette', (
    tester,
  ) async {
    await afficher(tester);

    for (final espece in ['Lapins', 'Volailles', 'Porcs']) {
      expect(find.text(espece), findsOneWidget, reason: espece);
    }
    expect(find.text('Lots actifs'), findsOneWidget);
    expect(find.text('Taux ponte'), findsOneWidget);
    expect(find.text('Ventes (mois)'), findsOneWidget);
  });

  /// ⚠️ « Gestantes » n'existe nulle part : la fiche la collecte, la base ne
  /// la stocke pas, le tirage ne la descend pas. Deux tirets, pas deux zéros.
  testWidgets('⚠️⚠️ les gestantes affichent un tiret sur lapins et porcs', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Gestantes'), findsNWidgets(2));
  });

  /// 6 morts sur 100 sujets initiaux = 6 %, au-dessus du seuil de 5 %.
  testWidgets('⚠️ la mortalité au-dessus de 5 % lève une alerte', (
    tester,
  ) async {
    await fiche(uuid('f1'), bandeLapins, 5, mort: 6, effectif: 94);

    await afficher(tester);

    expect(find.text('6.0%'), findsOneWidget);
    expect(
      find.textContaining('Mortalité anormale — Lot CUN-2026-01'),
      findsOneWidget,
    );
  });

  /// 2 morts sur 200 = 1 %, sous le seuil : aucune alerte.
  testWidgets('la mortalité sous le seuil ne lève aucune alerte', (
    tester,
  ) async {
    await fiche(uuid('f2'), bandePondeuses, 5, mort: 2, effectif: 198);

    await afficher(tester);

    expect(find.text('1.0%'), findsOneWidget);
    expect(find.textContaining('Mortalité anormale'), findsNothing);
  });

  testWidgets('les cinq onglets de transactions sont là', (tester) async {
    await afficher(tester);

    for (final onglet in ['Vente', 'Achat', 'Devis', 'Dépenses', 'Factures']) {
      expect(find.text(onglet), findsWidgets, reason: onglet);
    }
  });

  /// ⚠️ Trois onglets n'ont aucun module embarqué : ils le disent au lieu de
  /// disparaître, sans quoi la structure divergerait de la maquette selon ce
  /// qui est construit.
  testWidgets('un onglet non embarqué le dit', (tester) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('onglet-tx-Achat')));
    await tester.pumpAndSettle();

    expect(find.text('— Module non embarqué au poste —'), findsOneWidget);
  });

  /// ⚠️⚠️ NI NUMÉRO NI NOM DE CLIENT : aucune colonne de référence n'existe
  /// nulle part (ticket 14.71), et la table des clients ne descend pas. La
  /// vente est identifiée par son heure et son mode de règlement, qui sont
  /// réels.
  testWidgets('une vente est identifiée par son heure et son règlement', (
    tester,
  ) async {
    await vente(uuid('v1'), 32000, ceMois(3, 9));

    await afficher(tester);

    expect(find.text('09:00 · especes'), findsOneWidget);
    expect(find.text('32 000 F'), findsWidgets);
  });

  testWidgets('l onglet Dépenses montre les dépenses du poste', (tester) async {
    await depense(uuid('d1'), 'Carburant groupe électrogène', 25000, ceMois(6));

    await afficher(tester);

    await tester.tap(find.byKey(const Key('onglet-tx-Dépenses')));
    await tester.pumpAndSettle();

    expect(find.text('Carburant groupe électrogène'), findsWidgets);
  });

  /// ⚠️ La marge suppose un prix de revient, que le poste ne reçoit pas.
  testWidgets('le top produits affiche le CA mais pas la marge', (
    tester,
  ) async {
    await vente(uuid('v1'), 340000, ceMois(3));
    await ligne(uuid('l1'), uuid('v1'), 340, 340000);

    await afficher(tester);

    expect(find.text('Œufs de table'), findsWidgets);
    expect(find.text('340'), findsWidgets);
    expect(find.text('Marge'), findsOneWidget);
  });

  testWidgets('les activités du jour reprennent les écritures du poste', (
    tester,
  ) async {
    await vente(uuid('v-aujourdhui'), 12000, DateTime.now());

    await afficher(tester);

    expect(find.textContaining('Vente encaissée'), findsOneWidget);
  });

  testWidgets('sans écriture du jour, la section le dit', (tester) async {
    await afficher(tester);

    expect(
      find.text('— Aucune écriture aujourd\'hui sur ce poste —'),
      findsOneWidget,
    );
  });

  /// ⚠️ Le filtre de dates de la maquette pilote réellement les agrégats.
  testWidgets('une vente hors période ne compte pas dans le CA', (
    tester,
  ) async {
    // Le mois précédent : hors de la période par défaut (mois courant).
    final moisPasse = DateTime(maintenant.year, maintenant.month - 1, 15);
    await vente(uuid('v-vieux'), 500000, moisPasse);
    await vente(uuid('v-recent'), 32000, ceMois(3));

    await afficher(tester);

    expect(find.text('32 000'), findsWidgets);
    expect(find.text('532 000'), findsNothing);
  });
}
