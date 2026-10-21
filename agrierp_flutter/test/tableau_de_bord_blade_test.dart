import 'dart:io';

import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_repository.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket H5 — LE TABLEAU DE BORD DU POSTE ALIGNÉ SUR LE BLADE (article 5 de la doctrine).
///
/// Maître : `Dashboard/Index.php` + `livewire/dashboard/index.blade.php` (+ `AlertesElevageService` pour la
/// mortalité anormale). Trois familles de garde-fous :
///  1. les LIBELLÉS et MESSAGES VIDES sont LUS DANS LE BLADE (et dans `Index.php` pour les alertes), jamais
///     recopiés : une retouche du web rougit ce fichier ;
///  2. un JEU DE DONNÉES FAIT À LA MAIN, valeurs attendues calculées en commentaire, pour Dettes, Dépenses
///     (achats), Résultat Net, Gestantes et mortalité — littéraux, jamais produits par le code testé ;
///  3. une PARITÉ EXÉCUTÉE avec le vrai PHP (`Index::cartesElevage` et `Index::alertesCritiques`) pour la
///     mortalité, sautée avec sa raison sans PHP ni `vendor/`.
void main() {
  // ── Le Blade et le composant, lus dans le dépôt web ─────────────────────────────────────────────────────
  final fichierBlade = File(
    '$dossierLaravel/resources/views/livewire/dashboard/index.blade.php',
  );
  final fichierComposant = File(
    '$dossierLaravel/app/Livewire/Dashboard/Index.php',
  );
  final sautSansWeb = fichierBlade.existsSync() && fichierComposant.existsSync()
      ? null
      : 'SAUT : dépôt Laravel introuvable ($dossierLaravel) — libellés du Blade illisibles';
  String blade() => fichierBlade.readAsStringSync();
  String composant() => fichierComposant.readAsStringSync();

  /// Retire les icônes Material (`<span class="material-symbols-outlined">bar_chart</span>`) et les balises.
  String texte(String html) => html
      .replaceAll(
        RegExp(r'<span class="material-symbols-outlined[^"]*">[^<]*</span>'),
        '',
      )
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .trim();

  List<String> captures(String source, String motif) => RegExp(
    motif,
    dotAll: true,
  ).allMatches(source).map((m) => texte(m.group(1)!)).toList();

  // ── Base et horloge figées ─────────────────────────────────────────────────────────────────────────────
  late AppDatabase db;
  late TableauDeBordRepository depot;

  /// Lundi 19 octobre 2026, 14 h : mois courant = octobre, mois précédent = septembre, fenêtre des
  /// alertes de mortalité = fiches du 12 octobre et après (`now()->subDays(7)->toDateString()`).
  final maintenant = DateTime(2026, 10, 19, 14);

  String uuid(String graine) => graine.padRight(36, '0');

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = TableauDeBordRepository(database: db, horloge: () => maintenant);
  });

  tearDown(() async => db.close());

  Future<void> bande(
    String id,
    String code,
    String espece, {
    String? statut = 'actif',
    bool active = true,
    String stade = 'croissance',
    int initial = 0,
    int courant = 0,
  }) => db
      .into(db.livestockLots)
      .insert(
        LivestockLotsCompanion.insert(
          id: id,
          code: code,
          speciesId: uuid('esp-$espece'),
          speciesCode: Value(espece),
          stage: Value(stade),
          status: Value(statut),
          isActive: Value(active),
          initialQuantity: Value(initial),
          currentQuantity: Value(courant),
        ),
      );

  Future<void> fiche(
    String id,
    String lot,
    DateTime jour, {
    required int effectifFinal,
    int mort = 0,
    int ne = 0,
    int achat = 0,
    int vente = 0,
    int don = 0,
    int? ponte,
  }) => db
      .into(db.livestockDailyEntries)
      .insert(
        LivestockDailyEntriesCompanion.insert(
          id: id,
          deviceId: 'poste-test',
          updatedAt: jour,
          lotId: lot,
          entryDate: jour,
          effectifFinal: Value(effectifFinal),
          mort: Value(mort),
          ne: Value(ne),
          achat: Value(achat),
          vente: Value(vente),
          don: Value(don),
          ponteTotal: Value(ponte),
        ),
      );

  Future<void> cycle(String id, String lot, String statut) => db
      .into(db.livestockReproductionEvents)
      .insert(
        LivestockReproductionEventsCompanion.insert(
          id: id,
          deviceId: 'poste-test',
          updatedAt: maintenant,
          lotId: lot,
          motherRef: 'R-$id'.substring(0, 6),
          status: Value(statut),
        ),
      );

  Future<void> vente(
    String id,
    double total,
    DateTime quand, {
    String mode = 'especes',
    String? clientId,
    String? clientNom,
    String? mecef,
  }) => db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          id: id,
          deviceId: 'poste-test',
          updatedAt: quand,
          paymentMode: mode,
          total: total,
          soldAt: quand,
          customerId: Value(clientId),
          customerName: Value(clientNom),
          mecefStatus: Value(mecef),
        ),
      );

  Future<void> ligne(
    String id,
    String venteId,
    String produit,
    double qte,
    double montant,
  ) => db
      .into(db.saleLines)
      .insert(
        SaleLinesCompanion.insert(
          id: id,
          saleId: venteId,
          productId: produit,
          qty: qte,
          unitPrice: montant / qte,
          manualTotalAmount: montant,
        ),
      );

  Future<void> achat(
    String id,
    double total,
    DateTime quand, {
    String mode = 'comptant',
    String? fournisseur,
  }) => db
      .into(db.purchases)
      .insert(
        PurchasesCompanion.insert(
          id: id,
          deviceId: 'poste-test',
          updatedAt: quand,
          supplierId: uuid('fournisseur'),
          supplierName: Value(fournisseur),
          paymentMode: mode,
          total: total,
          purchaseDate: quand,
        ),
      );

  Future<void> dette(String id, double montant, double paye) => db
      .into(db.payables)
      .insert(
        PayablesCompanion.insert(
          id: id,
          supplierId: uuid('fournisseur'),
          amount: montant,
          amountPaid: Value(paye),
        ),
      );

  // ── Jeu de données fait à la main ──────────────────────────────────────────────────────────────────────
  const lapins = 'a1b2c3d4-0000-4000-8000-00000000000a';
  const lapins2 = 'a1b2c3d4-0000-4000-8000-00000000000b';
  const lapinsVendus = 'a1b2c3d4-0000-4000-8000-00000000000c';
  const lapinsArchives = 'a1b2c3d4-0000-4000-8000-00000000000d';
  const volailles = 'b1b2c3d4-0000-4000-8000-00000000000a';
  const volaillesVendues = 'b1b2c3d4-0000-4000-8000-00000000000b';
  const porcs = 'c1b2c3d4-0000-4000-8000-00000000000a';
  const oeufs = 'd1d2d3d4-0000-4000-8000-00000000000a';
  const provende = 'd1d2d3d4-0000-4000-8000-00000000000b';
  const porcCharcutier = 'd1d2d3d4-0000-4000-8000-00000000000c';
  const categoriePorcs = 'e1e2e3e4-0000-4000-8000-00000000000a';
  const venteS1 = 'a1b2c3d4-1111-4000-8000-000000000001';
  const venteS2 = 'f9e8d7c6-2222-4000-8000-000000000002';
  const venteS3 = '0a0b0c0d-3333-4000-8000-000000000003';
  const achatP1 = 'abcdef01-4444-4000-8000-000000000001';
  const achatP2 = '12345678-5555-4000-8000-000000000002';
  const clientDossou = 'c0c0c0c0-0000-4000-8000-000000000001';
  const clientKpossou = 'c0c0c0c0-0000-4000-8000-000000000002';

  Future<void> jeuALaMain() async {
    // Bandes. Effectif Animaux = bandes `is_active` ET `status = 'actif'` :
    //   lapins 90 + lapins2 25 + volailles 186 + porcs 17 = 318.
    // Sans le filtre `status` : + lapinsVendus 40 + volaillesVendues 50 = 408 (lapinsArchives : inactive).
    await bande(lapins, 'CUN-2026-01', 'cuniculture', stade: 'engraissement', initial: 100, courant: 90);
    await bande(lapins2, 'CUN-2026-02', 'cuniculture', stade: 'croissance', initial: 30, courant: 25);
    await bande(lapinsVendus, 'CUN-2026-03', 'cuniculture',
        statut: 'vendu', stade: 'engraissement', initial: 40, courant: 40);
    await bande(lapinsArchives, 'CUN-2025-09', 'cuniculture',
        statut: 'archive', active: false, initial: 60, courant: 50);
    await bande(volailles, 'AVI-2026-01', 'aviculture', stade: 'ponte', initial: 200, courant: 186);
    await bande(volaillesVendues, 'AVI-2026-02', 'aviculture',
        statut: 'vendu', stade: 'ponte', initial: 50, courant: 50);
    await bande(porcs, 'POR-2026-01', 'porciculture', stade: 'engraissement', initial: 20, courant: 17);

    // Fiches. Mortalité du mois (PHP `$mortaliteMois`) : bandes `is_active` SEULEMENT (le statut n'y est pas),
    // fiches depuis le 1er octobre, référence = Σ max(effectif_final − achat − né + mort + vente + don, 1).
    //  Lapins : 2/10 (95 + 5 = 100, 5 morts) ; 3/10 (90 − 2 + 3 + 4 = 95, 3 morts) ; vendus 4/10 (40, 0 mort) ;
    //           archivés 16/10 exclus (bande inactive) ; 28/09 exclu (mois précédent).
    //           8 / 235 × 100 = 3,404… → 3,4 % (vert : pas > 5).
    await fiche(uuid('f-lap-0928'), lapins, DateTime(2026, 9, 28), effectifFinal: 100, mort: 50);
    await fiche(uuid('f-lap-1002'), lapins, DateTime(2026, 10, 2), effectifFinal: 95, mort: 5);
    await fiche(uuid('f-lap-1003'), lapins, DateTime(2026, 10, 3), effectifFinal: 90, mort: 3, ne: 2, vente: 4);
    await fiche(uuid('f-lvd-1004'), lapinsVendus, DateTime(2026, 10, 4), effectifFinal: 40);
    await fiche(uuid('f-lar-1016'), lapinsArchives, DateTime(2026, 10, 16), effectifFinal: 30, mort: 20);
    //  Volailles : 5/10 (186 + 14 = 200, 14 morts) ; vendues 17/10 (45 + 5 = 50, 5 morts).
    //           19 / 250 × 100 = 7,6 % (rouge : > 5).
    //  Taux de ponte : 150 œufs / (186 + 45) sujets × 100 = 64,93… → 65 %.
    await fiche(uuid('f-avi-1005'), volailles, DateTime(2026, 10, 5), effectifFinal: 186, mort: 14, ponte: 150);
    await fiche(uuid('f-avv-1017'), volaillesVendues, DateTime(2026, 10, 17), effectifFinal: 45, mort: 5);
    //  Porcs : 15/10 (17 + 3 = 20, 3 morts) → 15,0 % (rouge).
    await fiche(uuid('f-por-1015'), porcs, DateTime(2026, 10, 15), effectifFinal: 17, mort: 3);
    // Alerte « Mortalité anormale » (AlertesElevageService : fiches du 12/10 et après, bandes VIVANTES, pire
    // jour ≥ 5 % rapporté à l'effectif de la fiche précédente, sinon à l'effectif initial) :
    //  - porcs 15/10 : 3 / 20 (initial, aucune fiche avant) = 15,00 % → alerte « (15,0%) » ;
    //  - volailles vendues 17/10 : 10 % mais bande non vivante (statut) → pas d'alerte ;
    //  - lapins archivés 16/10 : bande non vivante (inactive) → pas d'alerte.

    // Gestantes = cycles `en_cours` dont la bande est de l'espèce, SANS filtre sur la bande (PHP) :
    //  lapins 1 + lapins2 1 + lapinsArchives 1 = 3 (échec et terminé exclus) ; porcs 1.
    await cycle(uuid('r1'), lapins, 'en_cours');
    await cycle(uuid('r2'), lapins2, 'en_cours');
    await cycle(uuid('r3'), lapinsArchives, 'en_cours');
    await cycle(uuid('r4'), lapins, 'echec');
    await cycle(uuid('r5'), lapins, 'termine');
    await cycle(uuid('r6'), porcs, 'en_cours');

    // Produits. Stock Critique : seule la provende (5 ≤ 12) ; le porc n'a pas de seuil.
    await db.into(db.productCategories).insert(
      ProductCategoriesCompanion.insert(id: categoriePorcs, label: 'Porciculture'),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: oeufs,
        sku: 'AVI-OEUF',
        name: 'Œufs de table',
        unit: 'plateau',
        pricingMode: 'fixe',
        stockQty: const Value(40),
        alertThreshold: const Value(10),
      ),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: provende,
        sku: 'ALI-PONTE',
        name: 'Provende ponte',
        unit: 'sac',
        pricingMode: 'fixe',
        stockQty: const Value(5),
        alertThreshold: const Value(12),
      ),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: porcCharcutier,
        sku: 'POR-CHA',
        name: 'Porc charcutier',
        unit: 'tête',
        pricingMode: 'fixe',
        categoryId: const Value(categoriePorcs),
        stockQty: const Value(3),
      ),
    );

    await db.into(db.customers).insert(CustomersCompanion.insert(id: clientDossou, name: 'DOSSOU Marc'));
    await db.into(db.customers).insert(CustomersCompanion.insert(id: clientKpossou, name: 'KPOSSOU Éléonore'));

    // Ventes. CA d'octobre = S1 100 000 + S2 50 000 = 150 000 ; septembre = S3 120 000.
    //  Variation : (150 000 − 120 000) / 120 000 × 100 = +25,0 %.
    await vente(venteS1, 100000, DateTime(2026, 10, 3, 9), clientNom: 'AMOUSSOU Régis', mecef: 'transmise');
    await vente(venteS2, 50000, DateTime(2026, 10, 10, 11), mode: 'credit');
    await vente(venteS3, 120000, DateTime(2026, 9, 15, 10), clientId: clientDossou);
    // Lignes. Top 5 d'octobre : Œufs 10 + 20 = 30 pour 30 000 + 50 000 = 80 000 ; Porc 1 + 2,5 = 3,5 pour
    // 30 000 + 40 000 = 70 000. « Ventes (mois) » porcs = 2 lignes « Porciculture » d'octobre (S3 exclue).
    await ligne(uuid('l1'), venteS1, porcCharcutier, 1, 30000);
    await ligne(uuid('l2'), venteS1, porcCharcutier, 2.5, 40000);
    await ligne(uuid('l3'), venteS1, oeufs, 10, 30000);
    await ligne(uuid('l4'), venteS2, oeufs, 20, 50000);
    await ligne(uuid('l5'), venteS3, porcCharcutier, 4, 120000);

    // Achats. Dépenses d'octobre = P1 40 000 + P2 20 000 = 60 000 ; septembre = 80 000.
    //  Variation : (60 000 − 80 000) / 80 000 × 100 = −25,0 %.
    await achat(achatP1, 40000, DateTime(2026, 10, 5), fournisseur: 'Provenderie Sèmè');
    await achat(achatP2, 20000, DateTime(2026, 10, 12), mode: 'credit', fournisseur: 'Couvoir Ikpinlè');
    await achat(uuid('p3'), 80000, DateTime(2026, 9, 20), fournisseur: 'Provenderie Sèmè');
    // ⚠️ Une CHARGE (`expenses`) de 999 999 : le web ne la compte PAS dans « Dépenses » (achats seulement).
    await db.into(db.expenses).insert(
      ExpensesCompanion.insert(
        id: uuid('e1'),
        deviceId: 'poste-test',
        updatedAt: DateTime(2026, 10, 6),
        expenseDate: DateTime(2026, 10, 6),
        label: 'Carburant groupe électrogène',
        category: 'Carburant',
        amount: 999999,
        treasuryAccountId: uuid('caisse'),
      ),
    );

    // Dettes : seules celles où `amount_paid < amount` (PHP) : 75 000 − 25 000 = 50 000 ; 10 000 − 2 500 =
    // 7 500 ; la trop-payée (30 000 / 35 000, solde −5 000) est exclue. Total 57 500 (52 500 sans le filtre).
    await dette(uuid('d1'), 75000, 25000);
    await dette(uuid('d2'), 30000, 35000);
    await dette(uuid('d3'), 10000, 2500);

    // Créances : 30 000 échue le 09/10 ; 20 000 − 5 000 = 15 000 à échoir. Total 45 000.
    // Alerte : (int) now()->diffInDays(due_date) — Carbon 3 SIGNÉ :
    // 09/10 00:00 − 19/10 14:00 = −10,58 j → −10.
    await db.into(db.receivables).insert(
      ReceivablesCompanion.insert(
        id: uuid('c1'),
        customerId: clientKpossou,
        amount: 30000,
        dueDate: Value(DateTime(2026, 10, 9)),
      ),
    );
    await db.into(db.receivables).insert(
      ReceivablesCompanion.insert(
        id: uuid('c2'),
        customerId: clientDossou,
        amount: 20000,
        amountPaid: const Value(5000),
        dueDate: Value(DateTime(2026, 11, 30)),
      ),
    );

    // Journal d'audit : deux actions du 19/10, une de la veille (exclue). `created_at` est un INSTANT (S-T11) : les
    // heures du Bénin sont converties, et l'écran les rend à l'heure du Bénin.
    await db.into(db.auditLogs).insert(
      AuditLogsCompanion.insert(
        id: uuid('a1'),
        action: 'sale.created',
        userName: const Value('KPOSSOU Éléonore'),
        module: const Value('ventes'),
        createdAt: Value(HeureBenin.versInstant(DateTime(2026, 10, 19, 9, 12))),
      ),
    );
    await db.into(db.auditLogs).insert(
      AuditLogsCompanion.insert(id: uuid('a2'), action: 'login', createdAt: Value(HeureBenin.versInstant(DateTime(2026, 10, 19, 8)))),
    );
    await db.into(db.auditLogs).insert(
      AuditLogsCompanion.insert(id: uuid('a3'), action: 'logout', createdAt: Value(HeureBenin.versInstant(DateTime(2026, 10, 18, 18)))),
    );
  }

  // ── 1. Libellés et messages vides lus dans le Blade ────────────────────────────────────────────────────

  group('libellés lus dans le Blade', () {
    Future<void> afficher(WidgetTester tester, {ValueChanged<EcranPoste>? onOuvrir}) async {
      tester.view.physicalSize = const Size(1600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: TableauDeBordScreen(depot: depot, onOuvrir: onOuvrir)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('les huit cartes KPI portent les libellés du Blade, dans son ordre', (tester) async {
      final libelles = captures(blade(), r'<x-kpi-card label="([^"]+)"');
      expect(libelles, hasLength(8));
      await afficher(tester);
      final positions = <double>[];
      for (final l in libelles) {
        final f = find.text(l.toUpperCase());
        expect(f, findsOneWidget, reason: l);
        final p = tester.getTopLeft(f);
        positions.add(p.dy * 10000 + p.dx);
      }
      expect(positions, [...positions]..sort(), reason: 'ordre du Blade');
    }, skip: sautSansWeb != null);

    testWidgets('les titres de section du Blade sont tous à l écran', (tester) async {
      final titres = captures(blade(), r'<h3[^>]*>(.*?)</h3>');
      expect(titres, containsAll(['Alertes Critiques', 'Lapins', 'Top 5 Produits du Mois']));
      await afficher(tester);
      for (final t in titres) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    }, skip: sautSansWeb != null);

    testWidgets('base vide : les messages vides exacts du Blade, onglet par onglet', (tester) async {
      final messages = captures(
        blade(),
        r'<p class="text-xs text-outline text-center py-(?:md|lg)">([^<]+)</p>',
      );
      // Alertes, 5 onglets, Activités, Top 5.
      expect(messages, hasLength(8));
      await afficher(tester);

      final onglets = captures(blade(), r'''@click="tab = '\w+'"[^>]*>([^<]+)</button>''');
      expect(onglets, ['Vente', 'Achat', 'Devis', 'Dépenses', 'Factures']);

      final vus = <String>{};
      for (final onglet in onglets) {
        await tester.ensureVisible(find.byKey(Key('onglet-tx-$onglet')));
        await tester.tap(find.byKey(Key('onglet-tx-$onglet')));
        await tester.pumpAndSettle();
        for (final m in messages) {
          if (find.text(m).evaluate().isNotEmpty) vus.add(m);
        }
      }
      expect(vus, messages.toSet());
      // Aucune mention périmée du poste.
      expect(find.textContaining('Ce poste uniquement'), findsNothing);
      expect(find.textContaining('saisies sur ce poste'), findsNothing);
      expect(find.textContaining('non embarqué'), findsNothing);
      expect(find.textContaining('Table non synchronisée'), findsNothing);
    }, skip: sautSansWeb != null);

    testWidgets('les libellés des cartes espèces sont ceux du Blade, carte par carte', (tester) async {
      final libelles = captures(blade(), r'<p class="text-outline">([^<]+)</p>');
      expect(libelles, [
        'Effectif', 'Gestantes', 'Marchands', 'Mortalité',
        'Lots actifs', 'Taux ponte', 'Effectif', 'Mortalité',
        'Effectif', 'Gestantes', 'Ventes (mois)', 'Mortalité',
      ]);
      final depuisBlade = await depot.charger();
      final lus = [
        for (final c in depuisBlade.especes) ...[for (final m in c.mesures) m.$1, 'Mortalité'],
      ];
      expect(lus, libelles);
    }, skip: sautSansWeb != null);

    testWidgets('le sélecteur d état porte les 8 options du Blade et ouvre Rapports & Exports', (tester) async {
      final options = RegExp(r'<option value="([^"]*)">([^<]+)</option>')
          .allMatches(blade())
          .map((m) => (m.group(1)!, m.group(2)!))
          .toList();
      expect(options, hasLength(9)); // l'invite + 8 états
      final ouverts = <EcranPoste>[];
      await afficher(tester, onOuvrir: ouverts.add);

      expect(find.text(options.first.$2), findsOneWidget);
      final pdf = find.byKey(const Key('export-pdf'));
      // Aucun état choisi : le bouton est désactivé, comme `:disabled="!report"`.
      expect(tester.widget<ElevatedButton>(pdf).onPressed, isNull);

      await tester.tap(find.byKey(const Key('choix-etat')));
      await tester.pumpAndSettle();
      for (final (_, libelle) in options.skip(1)) {
        expect(find.text(libelle), findsWidgets, reason: libelle);
      }
      // « État de Trésorerie » pointe `/rapports-exports?tab=tresorerie` : écran Rapports & Exports du poste.
      final tresorerie = options.firstWhere((o) => o.$2 == 'État de Trésorerie');
      expect(tresorerie.$1, startsWith('/rapports-exports'));
      await tester.tap(find.text('État de Trésorerie').last);
      await tester.pumpAndSettle();
      await tester.tap(pdf);
      await tester.pumpAndSettle();
      expect(ouverts, [EcranPoste.rapportsEtExports]);

      // « Bilan Simplifié » pointe `/rapport-bilan`, page que le poste n'a pas : aucune cible inventée.
      await tester.tap(find.byKey(const Key('choix-etat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bilan Simplifié').last);
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(pdf).onPressed, isNull);
    }, skip: sautSansWeb != null);

    testWidgets('la période est le mois courant, et ses deux champs sont désactivés comme au web', (tester) async {
      expect(blade(), contains('disabled>'));
      await afficher(tester);
      // Horloge figée au 19/10/2026 : du 1er octobre à ce jour.
      expect(find.text('01/10/2026'), findsOneWidget);
      expect(find.text('19/10/2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('date-du')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
    }, skip: sautSansWeb != null);

    test('les préfixes des alertes et des sous-textes sont ceux du web', () async {
      final prefixesAlertes = captures(composant(), r"""'label' => "([^{"]+)\{""");
      expect(prefixesAlertes, ['Stock critique —', 'Mortalité anormale — Lot', 'Créance en retard —']);
      expect(blade(), contains("'Mois précédent : '"));
      expect(blade(), contains("'Marge nette : '"));
      expect(composant(), contains('return array_slice(\$alerts, 0, 6);'));

      await jeuALaMain();
      final d = await depot.charger();
      for (var i = 0; i < 3; i++) {
        expect(d.alertes[i].message, startsWith('${prefixesAlertes[i]} '));
      }
    }, skip: sautSansWeb);
  });

  // ── 2. Jeu de données fait à la main ──────────────────────────────────────────────────────────────────

  group('jeu de données fait à la main', () {
    // Ticket H5 — défauts corrigés AU WEB d'abord (`Sale::nonAnnulees()`, retard positif, exercice ouvert), puis ici.
    test('une vente ANNULÉE ne compte pas au CA ; l en-tête lit l exercice ouvert', () async {
      await jeuALaMain();
      final avant = (await depot.charger()).chiffreAffaires.valeur;
      final maintenant = DateTime.now();
      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 'cccccccc-0000-4000-8000-0000000000aa', deviceId: 'poste-test', updatedAt: maintenant,
        paymentMode: 'especes', total: 77777, soldAt: maintenant, status: const Value('annulee'),
      ));
      final d = await depot.charger();
      expect(d.chiffreAffaires.valeur, avant);
      expect(d.exerciceOuvert, isNull);

      await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(id: 'cccccccc-0000-4000-8000-0000000000fa', year: 2026, status: const Value('ouvert')));
      expect((await depot.charger()).exerciceOuvert, 2026);
    });

    test('KPI : CA, Dépenses sur les ACHATS, Résultat Net, Dettes, Créances, Effectif', () async {
      await jeuALaMain();
      final d = await depot.charger();

      expect(d.chiffreAffaires.valeur, 150000);
      expect(d.legendeChiffreAffaires, 'Mois précédent : 120 000 F (+25,0%)');
      // ⚠️ 60 000 d'achats, PAS 999 999 de charges.
      expect(d.depenses.valeur, 60000);
      expect(d.legendeDepenses, 'Mois précédent : 80 000 F (-25,0%)');
      // 150 000 − 60 000 = 90 000 ; 90 000 / 150 000 = 60 %.
      expect(d.resultatNet.valeur, 90000);
      expect(d.legendeResultatNet, 'Marge nette : 60%');
      expect(d.dettes.valeur, 57500);
      expect(d.creances.valeur, 45000);
      expect(d.effectifAnimaux.valeur, 318);
      expect(d.produitsSousSeuil.map((p) => p.name), ['Provende ponte']);
    });

    test('cartes espèces : gestantes, marchands, mortalité, ponte, ventes du mois', () async {
      await jeuALaMain();
      final d = await depot.charger();

      expect(d.especes.map((c) => c.titre), ['Lapins', 'Volailles', 'Porcs']);
      // Lapins : 90 + 25 ; 3 gestantes ; marchands = stade « engraissement » seul (90, pas 115) ; 3,4 %.
      expect(d.especes[0].mesures, [('Effectif', '115'), ('Gestantes', '3'), ('Marchands', '90')]);
      expect(d.especes[0].mortalite, 3.4);
      expect(TableauDeBordRepository.nombre(d.especes[0].mortalite, 1), '3,4');
      expect(d.especes[1].mesures, [('Lots actifs', '1'), ('Taux ponte', '65%'), ('Effectif', '186')]);
      expect(d.especes[1].mortalite, 7.6);
      expect(d.especes[2].mesures, [('Effectif', '17'), ('Gestantes', '1'), ('Ventes (mois)', '2')]);
      expect(d.especes[2].mortalite, 15.0);
    });

    test('sans fiche, la mortalité vaut 0,0 % (et non « — ») comme le PHP', () async {
      final d = await depot.charger();
      for (final c in d.especes) {
        expect(c.mortalite, 0.0);
        expect(TableauDeBordRepository.nombre(c.mortalite, 1), '0,0');
      }
      expect(d.especes[1].mesures[1], ('Taux ponte', '0%'));
    });

    test('alertes : libellés exacts, ordre stock → mortalité → créance', () async {
      await jeuALaMain();
      final d = await depot.charger();

      expect(d.alertes.map((a) => a.message), [
        'Stock critique — Provende ponte (5.00 sac restant(s))',
        'Mortalité anormale — Lot POR-2026-01 (15,0%)',
        'Créance en retard — KPOSSOU Éléonore (10 jours)',
      ]);
      expect(d.alertes.map((a) => a.grave), [true, true, false]);
      expect(d.alertes.map((a) => a.lien), ['/gestion-stocks', '/gestion-bandes', '/creances-clients']);
    });

    test('alertes : plafond de 6 (5 stocks au plus, puis mortalité, puis créances)', () async {
      await jeuALaMain();
      for (var i = 0; i < 7; i++) {
        await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: uuid('pc$i'),
            sku: 'PC$i',
            name: 'Produit $i',
            unit: 'kg',
            pricingMode: 'fixe',
            stockQty: const Value(0),
            alertThreshold: const Value(1),
          ),
        );
      }
      final d = await depot.charger();
      expect(d.alertes, hasLength(6));
      expect(d.alertes.where((a) => a.message.startsWith('Stock critique')), hasLength(5));
      expect(d.alertes.last.message, startsWith('Mortalité anormale'));
    });

    test('transactions récentes : Vente, Achat, Dépenses, Factures', () async {
      await jeuALaMain();
      final d = await depot.charger();

      expect(d.ventesRecentes.map((l) => (l.libelle, l.montant, l.ton)), [
        ('F9E8D7C6 · Client Anonyme', 50000.0, TonMontant.jaune),
        ('A1B2C3D4 · AMOUSSOU Régis', 100000.0, TonMontant.emeraude),
        ('0A0B0C0D · DOSSOU Marc', 120000.0, TonMontant.emeraude),
      ]);
      expect(d.achatsRecents.map((l) => (l.libelle, l.ton)).take(2), [
        ('12345678 · Couvoir Ikpinlè', TonMontant.jaune),
        ('ABCDEF01 · Provenderie Sèmè', TonMontant.foret),
      ]);
      expect(d.depensesRecentes.single.libelle, 'Carburant groupe électrogène');
      expect(d.facturesRecentes.map((l) => l.libelle), ['A1B2C3D4 · AMOUSSOU Régis']);
    });

    test('activités du jour depuis le journal d audit, top 5 au format du web', () async {
      await jeuALaMain();
      final d = await depot.charger();

      expect(d.activitesDuJour.map((a) => (a.libelle, a.detail)), [
        ('Vente enregistrée', '09:12 — KPOSSOU Éléonore · Ventes & Devis'),
        ('Connexion réussie', '08:00 — Système'),
      ]);
      expect(
        d.topProduits.map(
          (t) => (
            t.produit,
            TableauDeBordRepository.quantiteTop(t.quantite),
            TableauDeBordRepository.nombre(t.chiffreAffaires, 0),
            t.margePct,
          ),
        ),
        [('Œufs de table', '30', '80 000', null), ('Porc charcutier', '3.5', '70 000', null)],
      );
    });

    test('U4 — marge du Top 5 au PMP de TOUTES les lignes d achat, « — » sans ligne d achat', () async {
      await jeuALaMain();
      // Lignes d'achat du porc (ventes ET achats descendent au poste depuis U4) : 2 × 9 000 + 3 × 10 000 =
      // 48 000 pour 5 → PMP 9 600 (`Product::computePmp()`, arrondi à 2 décimales).
      // Porc : CA 70 000, qté 3,5 → coût 9 600 × 3,5 = 33 600 → round((70 000 − 33 600) / 70 000 × 100) = 52.
      // Œufs : aucune ligne d'achat → pas de PMP → « — » (null). La provende n'est pas au Top 5.
      for (final (id, achat, produit, qte, prix) in [
        (uuid('pl1'), achatP1, porcCharcutier, 2.0, 9000.0),
        (uuid('pl2'), achatP2, porcCharcutier, 3.0, 10000.0),
        (uuid('pl3'), achatP1, provende, 10.0, 7500.0),
      ]) {
        await db.into(db.purchaseLines).insert(
          PurchaseLinesCompanion.insert(
            id: id,
            purchaseId: achat,
            productId: produit,
            qty: qte,
            unitPrice: prix,
          ),
        );
      }

      final d = await depot.charger();

      expect(
        d.topProduits.map((t) => (t.produit, t.margePct)),
        [('Œufs de table', null), ('Porc charcutier', 52)],
      );
      expect(TableauDeBordRepository.pmp(porcCharcutier, await db.select(db.purchaseLines).get()), 9600);
      // Marge négative (vendu sous le coût) et cas « — » de la formule du web.
      expect(TableauDeBordRepository.margePct(1000, 2, 1500), -33);
      expect(TableauDeBordRepository.margePct(null, 2, 1500), isNull);
      expect(TableauDeBordRepository.margePct(1000, 0, 1500), isNull);
      expect(TableauDeBordRepository.margePct(1000, 2, 0), isNull);
    });

    /// Ticket U8 — RÈGLE UNIQUE DU TABLEAU DE BORD : ce que le web compte (pièces `synced`) plus ce qui part vers
    /// lui (`pending` : toutes les pièces du jeu ci-dessus sont en attente d'envoi, et comptent). Une pièce REFUSÉE
    /// par le serveur (`conflict`) n'entrera jamais au web : elle ne compte NULLE PART.
    test('U8 — une vente, un achat ou une charge REFUSÉS (conflict) ne comptent à aucun indicateur', () async {
      await jeuALaMain();
      // Lignes d'achat du porc (achats en attente, donc comptés) : PMP 9 600 → marge 52 (voir le test U4).
      for (final (id, achat, qte, prix) in [
        (uuid('pl1'), achatP1, 2.0, 9000.0),
        (uuid('pl2'), achatP2, 3.0, 10000.0),
      ]) {
        await db.into(db.purchaseLines).insert(
          PurchaseLinesCompanion.insert(
            id: id,
            purchaseId: achat,
            productId: porcCharcutier,
            qty: qte,
            unitPrice: prix,
          ),
        );
      }
      // Pièces REFUSÉES, toutes en octobre : une vente de porc transmise au MeCeF, un achat de porc à 1 F (qui
      // ferait tomber le PMP à 100 × 1 + 48 000 → 470,59, marge 98 %), une charge.
      final refusee = uuid('vente-refusee');
      await db.into(db.sales).insert(
        SalesCompanion.insert(
          id: refusee,
          deviceId: 'poste-test',
          updatedAt: DateTime(2026, 10, 18, 9),
          syncStatus: const Value(SyncStatus.conflict),
          paymentMode: 'especes',
          total: 500000,
          soldAt: DateTime(2026, 10, 18, 9),
          mecefStatus: const Value('transmise'),
        ),
      );
      await ligne(uuid('lr1'), refusee, porcCharcutier, 10, 500000);
      await db.into(db.purchases).insert(
        PurchasesCompanion.insert(
          id: uuid('achat-refuse'),
          deviceId: 'poste-test',
          updatedAt: DateTime(2026, 10, 18),
          syncStatus: const Value(SyncStatus.conflict),
          supplierId: uuid('fournisseur'),
          supplierName: const Value('Fournisseur refusé'),
          paymentMode: 'comptant',
          total: 300000,
          purchaseDate: DateTime(2026, 10, 18),
        ),
      );
      await db.into(db.purchaseLines).insert(
        PurchaseLinesCompanion.insert(
          id: uuid('pl-refusee'),
          purchaseId: uuid('achat-refuse'),
          productId: porcCharcutier,
          qty: 100,
          unitPrice: 1,
        ),
      );
      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: uuid('e-refusee'),
          deviceId: 'poste-test',
          updatedAt: DateTime(2026, 10, 18),
          syncStatus: const Value(SyncStatus.conflict),
          expenseDate: DateTime(2026, 10, 18),
          label: 'Charge refusée',
          category: 'Carburant',
          amount: 1234,
          treasuryAccountId: uuid('caisse'),
        ),
      );

      final d = await depot.charger();

      // Mêmes chiffres que sans les pièces refusées (test « KPI » et « courbe » ci-dessus).
      expect(d.chiffreAffaires.valeur, 150000);
      expect(d.depenses.valeur, 60000);
      expect(d.resultatNet.valeur, 90000);
      expect((d.serie[5].chiffreAffaires, d.serie[5].depenses), (150000.0, 60000.0));
      expect(d.especes[2].mesures.last, ('Ventes (mois)', '2'));
      expect(
        d.topProduits.map((t) => (t.produit, t.chiffreAffaires, t.margePct)),
        [('Œufs de table', 80000.0, null), ('Porc charcutier', 70000.0, 52)],
      );
      expect(d.ventesRecentes.map((l) => l.libelle), isNot(contains(startsWith('VENTE-RE'))));
      expect(d.ventesRecentes, hasLength(3));
      expect(d.achatsRecents.map((l) => l.libelle), isNot(contains(contains('Fournisseur refusé'))));
      expect(d.depensesRecentes.map((l) => l.libelle), ['Carburant groupe électrogène']);
      expect(d.facturesRecentes.map((l) => l.libelle), ['A1B2C3D4 · AMOUSSOU Régis']);

      // Contre-épreuve : la même vente ACQUITTÉE par le serveur (`synced`) compte partout.
      await (db.update(db.sales)..where((v) => v.id.equals(refusee))).write(
        const SalesCompanion(syncStatus: Value(SyncStatus.synced)),
      );
      final apres = await depot.charger();
      expect(apres.chiffreAffaires.valeur, 650000);
      expect(apres.especes[2].mesures.last, ('Ventes (mois)', '3'));
      expect(apres.topProduits.first.produit, 'Porc charcutier');
    });

    test('courbe et statistiques : six mois, achats en dépenses', () async {
      await jeuALaMain();
      final d = await depot.charger();
      expect(d.serie.map((p) => p.libelle), ['Mai', 'Juin', 'Juil.', 'Août', 'Sept.', 'Oct.']);
      expect(d.serie[4].chiffreAffaires, 120000);
      expect(d.serie[4].depenses, 80000);
      expect(d.serie[5].depenses, 60000);
      // round((150 000 − 120 000) / 120 000 × 100, 1) = 25.0, écrit « 25 » par PHP.
      expect(TableauDeBordRepository.variationStatistique(d.serie), (' (+25%)', ' (-25%)'));
    });

    testWidgets('rendu : montants, couleur de mortalité > 5, alertes cliquables', (tester) async {
      await tester.runAsync(jeuALaMain);
      tester.view.physicalSize = const Size(1600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ouverts = <EcranPoste>[];
      await tester.pumpWidget(
        MaterialApp(home: TableauDeBordScreen(depot: depot, onOuvrir: ouverts.add)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mois précédent : 120 000 F (+25,0%)'), findsOneWidget);
      expect(find.text('Marge nette : 60%'), findsOneWidget);
      expect(find.text('57 500'), findsOneWidget);
      expect(find.text('90 000'), findsOneWidget);
      expect(find.text('318'), findsOneWidget);

      Color couleur(String t) => tester.widget<Text>(find.text(t)).style!.color!;
      expect(couleur('3,4%'), const Color(0xFF065F46));
      expect(couleur('7,6%'), const Color(0xFFDC2626));

      await tester.ensureVisible(find.text('Stock critique — Provende ponte (5.00 sac restant(s))'));
      await tester.tap(find.text('Stock critique — Provende ponte (5.00 sac restant(s))'));
      await tester.tap(find.text('Mortalité anormale — Lot POR-2026-01 (15,0%)'));
      await tester.tap(find.text('Créance en retard — KPOSSOU Éléonore (10 jours)'));
      await tester.pumpAndSettle();
      // BS1 : `/gestion-bandes` a son écran au poste, l'alerte de mortalité y mène.
      expect(ouverts, [EcranPoste.gestionStocks, EcranPoste.gestionBandes, EcranPoste.clientsEtCreances]);

      // Vente à crédit en jaune, au comptant en émeraude.
      await tester.ensureVisible(find.text('50 000 F'));
      expect(couleur('50 000 F'), const Color(0xFFFFD55F));
      expect(couleur('100 000 F'), const Color(0xFF065F46));
    });
  });

  // ── 3. Parité exécutée avec le vrai PHP ────────────────────────────────────────────────────────────────

  test(
    'parité exécutée : mortalité des cartes et alertes de mortalité = Index.php',
    () async {
      // Scénarios variés : bandes actives / vendues / archivées, fiches avant et pendant le mois, dans et hors
      // de la fenêtre de sept jours, effectifs qui font tomber la référence à 1.
      final bandes = <Map<String, Object?>>[];
      final fiches = <Map<String, Object?>>[];
      const especes = ['cuniculture', 'aviculture', 'porciculture'];
      var graine = 7;
      int hasard(int n) => (graine = (graine * 1103515245 + 12345) & 0x7fffffff) % n;
      for (var b = 0; b < 12; b++) {
        final statut = ['actif', 'actif', 'actif', 'vendu', 'archive'][hasard(5)];
        bandes.add({
          'code': 'B$b',
          'espece': especes[b % 3],
          'initial': 20 + hasard(200),
          'status': statut,
          'is_active': statut == 'archive' ? false : true,
        });
        var jour = DateTime(2026, 9, 20 + hasard(10));
        for (var k = 0; k < 6; k++) {
          jour = jour.add(Duration(days: 1 + hasard(5)));
          if (jour.isAfter(DateTime(2026, 10, 19))) break;
          // ⚠️ ARTEFACT DE SQLITE, PAS DU CALCUL : `where('entry_date', '>=', now()->startOfMonth())` compare la
          // chaîne « 2026-10-01 » à « 2026-10-01 00:00:00 » — fausse sur SQLite (base du test PHP), vraie sur
          // MySQL (production). Le poste suit MySQL (le 1er du mois compte) ; la grille évite donc le 1er.
          if (jour == DateTime(2026, 10, 1)) jour = DateTime(2026, 10, 2);
          fiches.add({
            'bande': b,
            'entry_date': '${jour.year}-${jour.month.toString().padLeft(2, '0')}-'
                '${jour.day.toString().padLeft(2, '0')}',
            'effectif_final': hasard(4) == 0 ? 0 : 10 + hasard(150),
            'mort': hasard(3) == 0 ? hasard(25) : hasard(3),
            'ne': hasard(4) == 0 ? hasard(8) : 0,
            'achat': hasard(5) == 0 ? hasard(10) : 0,
            'vente': hasard(4) == 0 ? hasard(6) : 0,
            'don': hasard(6) == 0 ? 1 : 0,
          });
        }
      }

      final sortie =
          executerPhp(
                '<?php\n$amorceApplication\n$_scriptParite',
                {'bandes': bandes, 'fiches': fiches},
                application: true,
              )
              as Map<String, dynamic>;

      // Le poste reçoit les fiches TELLES QUE LE SERVEUR LES A ENREGISTRÉES (ses événements de modèle peuvent
      // retoucher l'effectif) : la parité porte sur le calcul du tableau de bord, pas sur la saisie.
      for (var b = 0; b < bandes.length; b++) {
        await bande(
          uuid('lot-$b-'),
          'B$b',
          bandes[b]['espece']! as String,
          statut: bandes[b]['status']! as String,
          active: bandes[b]['is_active']! as bool,
          initial: bandes[b]['initial']! as int,
        );
      }
      final stockees = sortie['fiches'] as List;
      for (var i = 0; i < stockees.length; i++) {
        final f = stockees[i] as Map<String, dynamic>;
        await fiche(
          uuid('fp-$i-'),
          uuid('lot-${f['bande']}-'),
          DateTime.parse(f['entry_date'] as String),
          effectifFinal: f['effectif_final'] as int,
          mort: f['mort'] as int,
          ne: f['ne'] as int,
          achat: f['achat'] as int,
          vente: f['vente'] as int,
          don: f['don'] as int,
        );
      }

      final d = await depot.charger();
      final cartes = sortie['cartes'] as Map<String, dynamic>;
      expect(
        [for (final c in d.especes) TableauDeBordRepository.nombre(c.mortalite, 1)],
        [
          for (final cle in ['lapins', 'volailles', 'porcs'])
            TableauDeBordRepository.nombre((cartes[cle]['mortalite'] as num).toDouble(), 1),
        ],
      );
      expect(
        d.alertes.map((a) => a.message).where((m) => m.startsWith('Mortalité')).toList(),
        (sortie['alertes'] as List).cast<String>(),
      );
      expect((sortie['alertes'] as List), isNotEmpty, reason: 'la grille déclenche des alertes');
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'parité exécutée U4 : Top 5 (marge comprise) et ventes porcines du mois = Index.php',
    () async {
      // Ventes de septembre et d'octobre (dont des annulées), lignes sur huit produits de deux catégories,
      // achats et lignes d'achat (PMP) sur une partie d'entre eux seulement : le web et le poste doivent rendre
      // le même Top 5, les mêmes marges (« — » compris) et le même nombre de lignes porcines du mois.
      var graine = 11;
      int hasard(int n) => (graine = (graine * 1103515245 + 12345) & 0x7fffffff) % n;
      final produits = [
        for (var i = 0; i < 8; i++) {'nom': 'Produit $i', 'porc': i < 3},
      ];
      final ventes = <Map<String, Object?>>[];
      for (var v = 0; v < 24; v++) {
        final mois = hasard(3) == 0 ? 9 : 10;
        final jour = mois == 10 ? 2 + hasard(17) : 1 + hasard(30);
        ventes.add({
          'sold_at': '2026-${mois.toString().padLeft(2, '0')}-${jour.toString().padLeft(2, '0')} '
              '${(8 + hasard(10)).toString().padLeft(2, '0')}:00:00',
          'status': hasard(6) == 0 ? 'annulee' : 'validee',
          'lignes': [
            for (var l = 0; l < 1 + hasard(3); l++)
              {
                'produit': hasard(8),
                'qty': (1 + hasard(40)) / 4,
                'montant': (1000 + hasard(90000)).toDouble(),
              },
          ],
        });
      }
      final achats = <Map<String, Object?>>[
        for (var a = 0; a < 6; a++)
          {
            'lignes': [
              for (var l = 0; l < 1 + hasard(3); l++)
                {
                  // Produits 0 à 4 seulement : 5, 6 et 7 n'ont pas de PMP (marge « — »).
                  'produit': hasard(5),
                  'qty': (1 + hasard(20)).toDouble(),
                  'unit_price': (500 + hasard(30000)).toDouble(),
                },
            ],
          },
      ];

      final sortie =
          executerPhp(
                '<?php\n$amorceApplication\n$_scriptPariteTop',
                {'produits': produits, 'ventes': ventes, 'achats': achats},
                application: true,
              )
              as Map<String, dynamic>;

      await db.into(db.productCategories).insert(
        ProductCategoriesCompanion.insert(id: uuid('cat-porc'), label: 'Porciculture'),
      );
      await db.into(db.productCategories).insert(
        ProductCategoriesCompanion.insert(id: uuid('cat-autre'), label: 'Aviculture'),
      );
      for (var i = 0; i < produits.length; i++) {
        await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: uuid('prod-$i-'),
            sku: 'P$i',
            name: produits[i]['nom']! as String,
            unit: 'u',
            pricingMode: 'fixe',
            categoryId: Value(uuid(produits[i]['porc']! as bool ? 'cat-porc' : 'cat-autre')),
          ),
        );
      }
      for (var v = 0; v < ventes.length; v++) {
        final quand = DateTime.parse(ventes[v]['sold_at']! as String);
        final lignes = ventes[v]['lignes']! as List;
        await db.into(db.sales).insert(
          SalesCompanion.insert(
            id: uuid('vente-$v-'),
            deviceId: 'serveur',
            updatedAt: quand,
            paymentMode: 'especes',
            total: lignes.fold<double>(0, (t, l) => t + ((l as Map)['montant'] as double)),
            soldAt: quand,
            status: Value(ventes[v]['status']! as String),
          ),
        );
        for (var l = 0; l < lignes.length; l++) {
          final ligne = lignes[l] as Map<String, Object?>;
          await db.into(db.saleLines).insert(
            SaleLinesCompanion.insert(
              id: uuid('lv-$v-$l-'),
              saleId: uuid('vente-$v-'),
              productId: uuid('prod-${ligne['produit']}-'),
              qty: ligne['qty']! as double,
              unitPrice: (ligne['montant']! as double) / (ligne['qty']! as double),
              manualTotalAmount: ligne['montant']! as double,
            ),
          );
        }
      }
      for (var a = 0; a < achats.length; a++) {
        final lignes = achats[a]['lignes']! as List;
        for (var l = 0; l < lignes.length; l++) {
          final ligne = lignes[l] as Map<String, Object?>;
          await db.into(db.purchaseLines).insert(
            PurchaseLinesCompanion.insert(
              id: uuid('la-$a-$l-'),
              purchaseId: uuid('achat-$a-'),
              productId: uuid('prod-${ligne['produit']}-'),
              qty: ligne['qty']! as double,
              unitPrice: ligne['unit_price']! as double,
            ),
          );
        }
      }

      final d = await depot.charger();

      final top = sortie['top'] as List;
      expect(top, hasLength(5), reason: 'la grille remplit le Top 5');
      expect(
        top.where((t) => (t as Map)['marge'] == null),
        isNotEmpty,
        reason: 'la grille couvre le cas « — » (produit sans PMP)',
      );
      expect(
        top.where((t) => (t as Map)['marge'] != null),
        isNotEmpty,
        reason: 'la grille couvre des marges calculées',
      );
      expect(
        [
          for (final t in d.topProduits)
            (
              t.produit,
              TableauDeBordRepository.quantiteTop(t.quantite),
              TableauDeBordRepository.nombre(t.chiffreAffaires, 0),
              t.margePct,
            ),
        ],
        [
          for (final t in top.cast<Map<String, dynamic>>())
            (
              t['produit'] as String,
              TableauDeBordRepository.quantiteTop((t['qty'] as num).toDouble()),
              TableauDeBordRepository.nombre((t['ca'] as num).toDouble(), 0),
              (t['marge'] as num?)?.toInt(),
            ),
        ],
      );
      expect(d.especes[2].mesures.last, ('Ventes (mois)', '${sortie['ventes_porcs']}'));
      expect(sortie['ventes_porcs'] as int, greaterThan(0));
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Script PHP de la parité : crée les bandes et fiches, fige l'horloge au 19/10/2026 14 h, et rend
/// `Index::cartesElevage`, les libellés des alertes de mortalité et les fiches telles qu'enregistrées.
const _scriptParite = r'''
Carbon\Carbon::setTestNow('2026-10-19 14:00:00');
$entree = json_decode(file_get_contents($argv[1]), true);
$especes = [];
$lots = [];
foreach ($entree['bandes'] as $i => $b) {
    $code = $b['espece'];
    if (! isset($especes[$code])) {
        $especes[$code] = App\Models\LivestockSpecies::create(['label' => $code, 'code' => $code, 'is_active' => true]);
    }
    $lots[$i] = App\Models\LivestockLot::create([
        'code' => $b['code'], 'species_id' => $especes[$code]->id, 'stage' => 'croissance',
        'initial_quantity' => $b['initial'], 'current_quantity' => $b['initial'],
        'created_date' => '2026-09-01', 'status' => $b['status'], 'is_active' => $b['is_active'],
    ]);
}
$ids = [];
foreach ($entree['fiches'] as $f) {
    $b = $f['bande'];
    unset($f['bande']);
    $e = new App\Models\LivestockDailyEntry(array_merge($f, ['lot_id' => $lots[$b]->id]));
    $e->save();
    $ids[] = [$e->id, $b];
}
$fiches = [];
foreach ($ids as [$id, $b]) {
    $x = App\Models\LivestockDailyEntry::find($id);
    $fiches[] = [
        'bande' => $b, 'entry_date' => $x->entry_date->format('Y-m-d'),
        'effectif_final' => (int) $x->effectif_final, 'mort' => (int) $x->mort, 'ne' => (int) $x->ne,
        'achat' => (int) $x->achat, 'vente' => (int) $x->vente, 'don' => (int) $x->don,
    ];
}
$composant = new App\Livewire\Dashboard\Index();
$alertes = array_values(array_map(fn ($a) => $a['label'], array_filter(
    $composant->alertesCritiques, fn ($a) => str_starts_with($a['label'], 'Mortalité')
)));
echo json_encode(['cartes' => $composant->cartesElevage, 'alertes' => $alertes, 'fiches' => $fiches]);
''';

/// Script PHP de la parité U4 : crée catégories, produits, ventes (avec leurs lignes) et achats (avec leurs
/// lignes), fige l'horloge au 19/10/2026 14 h, et rend `Index::topProduits` et `cartesElevage['porcs']['ventes_mois']`.
const _scriptPariteTop = r'''
Carbon\Carbon::setTestNow('2026-10-19 14:00:00');
$entree = json_decode(file_get_contents($argv[1]), true);
$porc = App\Models\ProductCategory::create(['label' => 'Porciculture', 'is_active' => true]);
$autre = App\Models\ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
$produits = [];
foreach ($entree['produits'] as $i => $p) {
    $produits[$i] = App\Models\Product::create([
        'sku' => 'P'.$i, 'name' => $p['nom'], 'category_id' => $p['porc'] ? $porc->id : $autre->id, 'unit' => 'u',
        'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 1000000, 'stock_qty' => 0, 'is_active' => true,
    ]);
}
foreach ($entree['ventes'] as $v) {
    $total = array_sum(array_column($v['lignes'], 'montant'));
    $vente = App\Models\Sale::create([
        'payment_mode' => 'especes', 'subtotal' => $total, 'total' => $total,
        'status' => $v['status'], 'sold_at' => $v['sold_at'],
    ]);
    foreach ($v['lignes'] as $l) {
        App\Models\SaleLine::create([
            'sale_id' => $vente->id, 'product_id' => $produits[$l['produit']]->id, 'qty' => $l['qty'],
            'unit_price' => round($l['montant'] / $l['qty'], 2), 'manual_total_amount' => $l['montant'],
        ]);
    }
}
$fournisseur = App\Models\Supplier::create(['name' => 'Fournisseur', 'is_active' => true]);
foreach ($entree['achats'] as $a) {
    $achat = App\Models\Purchase::create([
        'supplier_id' => $fournisseur->id, 'payment_mode' => 'especes', 'total' => 0, 'purchase_date' => '2026-10-01',
    ]);
    foreach ($a['lignes'] as $l) {
        App\Models\PurchaseLine::create([
            'purchase_id' => $achat->id, 'product_id' => $produits[$l['produit']]->id,
            'qty' => $l['qty'], 'unit_price' => $l['unit_price'],
        ]);
    }
}
$composant = new App\Livewire\Dashboard\Index();
$top = array_map(fn ($r) => [
    'produit' => $r['product']?->name, 'qty' => $r['qty'], 'ca' => $r['ca'], 'marge' => $r['marge_pct'],
], $composant->topProduits);
echo json_encode(['top' => $top, 'ventes_porcs' => $composant->cartesElevage['porcs']['ventes_mois']]);
''';
