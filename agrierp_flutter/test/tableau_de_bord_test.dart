import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_repository.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.32 — TABLEAU DE BORD DU POSTE (`prototype_html/dashboard.html`).
///
/// Ticket H5 : le Blade fait foi. Les tests qui vérifiaient l'ancien comportement du poste (mentions « Ce poste
/// uniquement », « Table non synchronisée », onglets « non embarqués », activités reconstituées, libellés et
/// formule de mortalité de la maquette) sont adaptés à `livewire/dashboard/index.blade.php` et à
/// `Dashboard/Index.php`. Les libellés lus dans le Blade et le jeu de données calculé à la main vivent dans
/// `tableau_de_bord_blade_test.dart`.
///
/// ⚠️ Depuis 14.79/14.80, `sales`, `purchases` et `payables` descendent au poste : ces blocs portent la ferme.
///
/// ⚠️ **MORTALITÉ** : la couleur des cartes bascule STRICTEMENT au-dessus de 5 (`> 5` du Blade) ; l'alerte
/// « Mortalité anormale » suit `AlertesElevageService` (pire jour des 7 derniers, `>= 5`).
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

  final maintenant = HeureBenin.maintenant();
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
            // Ticket H5 : le Blade fait foi — `is_active` ET `status = 'actif'`.
            status: const Value('actif'),
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
            status: const Value('actif'),
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
            status: const Value('actif'),
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
            treasuryAccountId: Value(uuid('caisse')),
          ),
        );
  }

  Future<void> fiche(
    String id,
    String lot,
    DateTime jour, {
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
            updatedAt: jour,
            lotId: lot,
            entryDate: jour,
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

  /// Ticket H5 : le Blade fait foi. Résultat Net = CA − achats du mois (`Index.php`), Dettes depuis
  /// `payables` (descendue depuis 14.79) : plus de tiret motivé, des chiffres.
  testWidgets('résultat net et dettes sont calculés comme au web', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Sans comptabilité au poste'), findsNothing);
    expect(find.text('Table non synchronisée'), findsNothing);
    expect(find.text('RÉSULTAT NET'), findsOneWidget);
    expect(find.text('DETTES FOURNISSEURS'), findsOneWidget);
  });

  /// Ticket H5 : le Blade fait foi — les ventes de toute la ferme descendent, la mention « Ce poste
  /// uniquement » était périmée.
  testWidgets('⚠️ le CA ne porte plus la mention périmée du poste', (
    tester,
  ) async {
    await vente(uuid('v1'), 32000, ceMois(3));
    await vente(uuid('v2'), 45000, ceMois(4));

    await afficher(tester);

    expect(find.text('77 000'), findsWidgets);
    expect(find.textContaining('Ce poste uniquement'), findsNothing);
  });

  testWidgets('la trésorerie ventile caisse et banque', (tester) async {
    await afficher(tester);

    expect(find.text('1 600 000'), findsOneWidget);
    // Décision D-U8 : Mobile Money en troisième ligne ; même texte que la légende du web, « F » compris.
    expect(find.text('Caisse : 420 000 F · Banque : 1 180 000 F · Mobile Money : 0 F'), findsOneWidget);
  });

  testWidgets('D-U8 : le Mobile Money a sa ligne, comme au web', (tester) async {
    await db
        .into(db.treasuryAccounts)
        .insert(
          TreasuryAccountsCompanion.insert(
            id: uuid('momo'),
            label: 'MTN MoMo',
            type: const Value('mobile_money'),
            balance: const Value(18500),
          ),
        );
    await afficher(tester);

    expect(find.text('1 618 500'), findsOneWidget);
    expect(find.text('Caisse : 420 000 F · Banque : 1 180 000 F · Mobile Money : 18 500 F'), findsOneWidget);
  });

  testWidgets('le stock critique compte et nomme les produits sous seuil', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Provende ponte'), findsWidgets);
    // Ticket H5 : le Blade fait foi — libellé de `Index::getAlertesCritiquesProperty()`.
    expect(
      find.text('Stock critique — Provende ponte (5.00 sac restant(s))'),
      findsOneWidget,
    );
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

  /// Ticket H5 : le Blade fait foi — « Gestantes » se compte sur `livestock_reproduction_events`
  /// (cycles `en_cours`), descendue au poste ; le calcul est vérifié dans `tableau_de_bord_blade_test.dart`.
  testWidgets('⚠️⚠️ les gestantes figurent sur lapins et porcs', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Gestantes'), findsNWidgets(2));
  });

  /// Ticket H5 : le Blade fait foi. Carte : 6 morts / (94 + 6) = 6,0 % (virgule décimale). Alerte : fiche
  /// d'aujourd'hui (fenêtre de 7 jours), 6 / 100 (effectif initial, aucune fiche avant) = 6 % ≥ 5.
  testWidgets('⚠️ la mortalité au-dessus de 5 % lève une alerte', (
    tester,
  ) async {
    final aujourdhui = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
    );
    await fiche(uuid('f1'), bandeLapins, aujourdhui, mort: 6, effectif: 94);

    await afficher(tester);

    expect(find.text('6,0%'), findsOneWidget);
    expect(
      find.textContaining('Mortalité anormale — Lot CUN-2026-01'),
      findsOneWidget,
    );
  });

  /// 2 morts sur 198 + 2 = 1 %, sous le seuil : aucune alerte. Ticket H5 : virgule décimale du Blade.
  testWidgets('la mortalité sous le seuil ne lève aucune alerte', (
    tester,
  ) async {
    final aujourdhui = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
    );
    await fiche(uuid('f2'), bandePondeuses, aujourdhui, mort: 2, effectif: 198);

    await afficher(tester);

    expect(find.text('1,0%'), findsOneWidget);
    expect(find.textContaining('Mortalité anormale'), findsNothing);
  });

  testWidgets('les cinq onglets de transactions sont là', (tester) async {
    await afficher(tester);

    for (final onglet in ['Vente', 'Achat', 'Devis', 'Dépenses', 'Factures']) {
      expect(find.text(onglet), findsWidgets, reason: onglet);
    }
  });

  /// Ticket H5 : le Blade fait foi — `purchases` est au poste, l'onglet Achat est alimenté ; vide, il
  /// affiche le message du web.
  testWidgets('un onglet vide affiche le message du web', (tester) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('onglet-tx-Achat')));
    await tester.pumpAndSettle();

    expect(find.text('Aucun achat récent.'), findsOneWidget);
    expect(find.textContaining('non embarqué'), findsNothing);
  });

  /// Ticket H5 : le Blade fait foi — « ID8 · client », « Client Anonyme » sans client
  /// (`strtoupper(substr($sale->id, 0, 8))`).
  testWidgets('une vente est identifiée par son ID8 et son client', (
    tester,
  ) async {
    await vente(uuid('v1'), 32000, ceMois(3, 9));

    await afficher(tester);

    expect(find.text('V1000000 · Client Anonyme'), findsOneWidget);
    expect(find.text('32 000 F'), findsWidgets);
  });

  testWidgets('l onglet Dépenses montre les dépenses du poste', (tester) async {
    await depense(uuid('d1'), 'Carburant groupe électrogène', 25000, ceMois(6));

    await afficher(tester);

    await tester.tap(find.byKey(const Key('onglet-tx-Dépenses')));
    await tester.pumpAndSettle();

    expect(find.text('Carburant groupe électrogène'), findsWidgets);
  });

  /// Ticket U4 — la marge suppose un PMP (lignes d'achat, qui descendent au poste) : sans aucune ligne
  /// d'achat du produit, pas de PMP, donc « — » comme au web — jamais 0 %.
  testWidgets('le top produits affiche le CA, et « — » en marge sans ligne d achat', (
    tester,
  ) async {
    await vente(uuid('v1'), 340000, ceMois(3));
    await ligne(uuid('l1'), uuid('v1'), 340, 340000);

    await afficher(tester);

    expect(find.text('Œufs de table'), findsWidgets);
    expect(find.text('340'), findsWidgets);
    expect(find.text('Marge'), findsOneWidget);
  });

  /// Ticket H5 : le Blade fait foi — les activités viennent du journal d'audit (`audit_logs`), libellés
  /// de `AuditLog`, auteur, module.
  testWidgets('les activités du jour viennent du journal d audit', (
    tester,
  ) async {
    await db
        .into(db.auditLogs)
        .insert(
          AuditLogsCompanion.insert(
            id: uuid('audit'),
            action: 'sale.created',
            userName: const Value('KPOSSOU Éléonore'),
            module: const Value('ventes'),
            createdAt: Value(DateTime.now()),
          ),
        );

    await afficher(tester);

    expect(find.text('Vente enregistrée'), findsOneWidget);
    expect(
      find.textContaining('— KPOSSOU Éléonore · Ventes & Devis'),
      findsOneWidget,
    );
  });

  testWidgets('sans activité du jour, la section le dit comme le web', (
    tester,
  ) async {
    await afficher(tester);

    expect(
      find.text("Aucune activité enregistrée aujourd'hui pour le moment."),
      findsOneWidget,
    );
  });

  /// Ticket H5 : le Blade fait foi — la période est le mois courant (champs désactivés) ; une vente du mois
  /// précédent ne compte que dans le sous-texte « Mois précédent ».
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
