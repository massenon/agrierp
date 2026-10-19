import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/core/export/export_tableur.dart';
import 'package:agrierp/features/rapports/rapports_exports_screen.dart';
import 'package:agrierp/features/rapports/rapports_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.52 — RAPPORTS & EXPORTS (`rapports-exports.html`).
///
/// ⚠️⚠️ **CE HUB EST LE PREMIER ÉCRAN DU POSTE QUI PRODUIT UN DOCUMENT.** Les
/// six rapports s'éditent en PDF et en classeur, hors ligne, sur la machine de
/// la ferme. Trois familles de défauts sont donc verrouillées ici :
///
/// 1. **Un chiffre faux dans un état officiel** — un total qui oublie le
///    Mobile Money, une créance affichée à son montant facturé, un stock
///    négatif valorisé. Ils ne lèvent aucune erreur ; ils s'impriment.
/// 2. **Une colonne de la maquette silencieusement perdue** — le rapport
///    d'élevage porte 13 + 9 + 10 colonnes, dont seize que le poste ne détient
///    pas. Les retirer serait plus lisible et plus faux.
/// 3. **Un crédit disparu du pied de page** — défaut déjà commis côté web
///    (ticket 15.2), invisible pendant deux tickets.
void main() {
  late AppDatabase db;
  late RapportsRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final du = DateTime(2026, 7, 1);
  final au = DateTime(2026, 7, 31);
  final maintenant = DateTime(2026, 8, 25, 14, 30);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = RapportsRepository(database: db);
  });

  tearDown(() => db.close());

  // ── Fabriques ─────────────────────────────────────────────────────────────

  Future<void> vente(
    String cle, {
    required DateTime date,
    required double total,
    String statut = 'validee',
    String mode = 'especes',
    String? client,
  }) => db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          id: uuid(cle),
          deviceId: 'poste-test',
          updatedAt: date,
          paymentMode: mode,
          total: total,
          soldAt: date,
          status: Value(statut),
          customerName: Value(client),
        ),
      );

  Future<void> depense(
    String cle, {
    required DateTime date,
    required double montant,
    String libelle = 'Achat provende',
    String categorie = 'Aliments',
  }) => db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          id: uuid(cle),
          deviceId: 'poste-test',
          updatedAt: date,
          expenseDate: date,
          label: libelle,
          category: categorie,
          amount: montant,
          treasuryAccountId: uuid('tc'),
        ),
      );

  Future<void> compteTresorerie(
    String cle, {
    required String type,
    required double solde,
  }) => db
      .into(db.treasuryAccounts)
      .insert(
        TreasuryAccountsCompanion.insert(
          id: uuid(cle),
          label: type,
          type: Value(type),
          balance: Value(solde),
        ),
      );

  Future<void> tirageLe(DateTime quand) => db
      .into(db.syncState)
      .insertOnConflictUpdate(
        SyncStateCompanion.insert(lastPulledAt: Value(quand)),
      );

  Future<void> bande(
    String cle, {
    String code = 'Pondeuses Lot P1',
    DateTime? creee,
    String espece = 'aviculture',
    String stade = 'ponte',
  }) => db
      .into(db.livestockLots)
      .insert(
        LivestockLotsCompanion.insert(
          id: uuid(cle),
          code: code,
          speciesId: uuid('sp'),
          speciesCode: Value(espece),
          stage: Value(stade),
          createdDate: Value(creee),
        ),
      );

  Future<void> journee(
    String cle, {
    required String lot,
    required DateTime date,
    int effectifFinal = 100,
    int mort = 0,
    int vente = 0,
    int don = 0,
    int achat = 0,
    int ne = 0,
    int? ponteTotal,
    int? ponteCasses,
    SyncStatus statut = SyncStatus.pending,
  }) => db
      .into(db.livestockDailyEntries)
      .insert(
        LivestockDailyEntriesCompanion.insert(
          id: uuid(cle),
          deviceId: 'poste-test',
          updatedAt: date,
          syncStatus: Value(statut),
          lotId: uuid(lot),
          entryDate: date,
          effectifFinal: Value(effectifFinal),
          mort: Value(mort),
          vente: Value(vente),
          don: Value(don),
          achat: Value(achat),
          ne: Value(ne),
          ponteTotal: Value(ponteTotal),
          ponteCasses: Value(ponteCasses),
        ),
      );

  Future<void> produit(
    String cle, {
    required String nom,
    String? categorie,
    double stock = 0,
    double? prix = 100,
    double? seuil,
  }) => db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: uuid(cle),
          sku: cle,
          name: nom,
          unit: 'u',
          pricingMode: 'fixe',
          categoryId: Value(categorie),
          stockQty: Value(stock),
          priceMin: Value(prix),
          alertThreshold: Value(seuil),
        ),
      );

  /// Ticket U9 — un mouvement du grand livre des stocks DESCENDU du serveur.
  Future<void> mouvement(
    String cle,
    String produitCle,
    String type,
    double quantite,
    DateTime quand, {
    String reference = 'sale',
    String? referenceId,
  }) => db
      .into(db.stockMovements)
      .insert(
        StockMovementsCompanion.insert(
          id: uuid(cle),
          productId: uuid(produitCle),
          type: type,
          quantity: quantite,
          referenceType: reference,
          referenceId: Value(referenceId),
          movementDate: quand,
        ),
      );

  Future<void> categorie(String cle, String libelle) => db
      .into(db.productCategories)
      .insert(ProductCategoriesCompanion.insert(id: uuid(cle), label: libelle));

  // ──────────────────────────────────────────────────────────────────────────
  group('recettes et dépenses', () {
    test(
      '⚠️ une vente annulée figure sans compter au chiffre d affaires',
      () async {
        await vente('v1', date: DateTime(2026, 7, 10), total: 45000);
        await vente(
          'v2',
          date: DateTime(2026, 7, 11),
          total: 30000,
          statut: 'annulee',
        );

        final d = await depot.charger(du: du, au: au);

        expect(d.totalRecettes, 45000);
        // Elle ne figure pas non plus dans la liste : un état des recettes
        // n'est pas un historique de ventes.
        expect(d.recettes, hasLength(1));
      },
    );

    /// ⚠️⚠️ **LA BORNE HAUTE EST INCLUSIVE.** « au 31/07 » compris comme
    /// « jusqu'au 31/07 à 00:00 » perdrait toute la journée de clôture — et
    /// c'est la journée la plus chargée d'un mois de ferme.
    test(
      '⚠️⚠️ une vente du dernier jour au soir est dans la période',
      () async {
        await vente('v1', date: DateTime(2026, 7, 31, 19, 45), total: 12000);

        final d = await depot.charger(du: du, au: au);

        expect(d.totalRecettes, 12000);
      },
    );

    test('une vente hors période est ignorée des deux côtés', () async {
      await vente('v1', date: DateTime(2026, 6, 30, 23, 59), total: 9000);
      await vente('v2', date: DateTime(2026, 8, 1), total: 9000);

      final d = await depot.charger(du: du, au: au);

      expect(d.recettes, isEmpty);
      expect(d.totalRecettes, 0);
    });

    test('le solde net est la différence des deux totaux', () async {
      await vente('v1', date: DateTime(2026, 7, 10), total: 168000);
      await depense('d1', date: DateTime(2026, 7, 12), montant: 242000);

      final d = await depot.charger(du: du, au: au);

      expect(d.soldeNet, -74000);
    });

    test('les montants portent leur signe, comme la maquette', () async {
      await vente('v1', date: DateTime(2026, 7, 10), total: 45000);
      await depense('d1', date: DateTime(2026, 7, 12), montant: 185000);

      final d = await depot.charger(du: du, au: au);

      expect(d.recettes.single.cellules.last, '+45 000 FCFA');
      expect(d.depenses.single.cellules.last, '-185 000 FCFA');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('trésorerie', () {
    /// ⚠️⚠️ **LE PIÈGE PRINCIPAL DE CET ONGLET.** La maquette n'a que deux
    /// colonnes de solde, et son jeu de démonstration porte un Mobile Money à
    /// zéro : le total y semble valoir Caisse + Banque. Sur cette ferme, où le
    /// Mobile Money encaisse réellement, s'en tenir à deux colonnes sur trois
    /// donnerait un total AMPUTÉ — sans que rien ne le dise.
    test('⚠️⚠️ le solde total inclut le mobile money', () async {
      await compteTresorerie('t1', type: 'caisse', solde: 420000);
      await compteTresorerie('t2', type: 'banque', solde: 1180000);
      await compteTresorerie('t3', type: 'mobile_money', solde: 95000);
      await tirageLe(DateTime(2026, 7, 15));

      final d = await depot.charger(du: du, au: au);

      expect(d.tresorerie.caisse, 420000);
      expect(d.tresorerie.banque, 1180000);
      expect(d.tresorerie.total, 1695000);
      // Et surtout : PAS la somme des deux colonnes affichées.
      expect(d.tresorerie.total, isNot(1600000));
    });

    /// ⚠️ Sans tirage, aucune valeur n'est signable : c'est un tiret, jamais
    /// un zéro qui se lirait « la caisse est vide ».
    test('⚠️ sans tirage, la position est inconnue et non nulle', () async {
      final d = await depot.charger(du: du, au: au);

      expect(d.tresorerie.connue, isFalse);
      expect(d.tresorerie.caisse, isNull);
      expect(d.tresorerie.total, isNull);
    });

    test('la date affichée est celle du dernier tirage', () async {
      await compteTresorerie('t1', type: 'caisse', solde: 1000);
      await tirageLe(DateTime(2026, 7, 15, 8, 30));

      final d = await depot.charger(du: du, au: au);

      expect(d.tresorerie.releveLe, DateTime(2026, 7, 15, 8, 30));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('créances et dettes', () {
    /// ⚠️⚠️ **LE RESTE DÛ, PAS LE MONTANT FACTURÉ.** Afficher `amount`
    /// compterait une seconde fois ce qui a déjà été réglé — le défaut que la
    /// balance âgée du serveur a dû corriger.
    test('⚠️⚠️ une créance affiche son reste dû', () async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(id: uuid('cl'), name: 'AMOUSSOU Régis'),
          );
      await db
          .into(db.receivables)
          .insert(
            ReceivablesCompanion.insert(
              id: uuid('cr'),
              customerId: uuid('cl'),
              amount: 60000,
              amountPaid: const Value(15000),
              dueDate: Value(DateTime(2026, 7, 1)),
            ),
          );

      final d = await depot.charger(du: du, au: au);

      expect(d.creances.single.cellules, [
        'AMOUSSOU Régis',
        '45 000',
        '01/07/2026',
      ]);
    });

    test('une créance soldée ne figure pas', () async {
      await db
          .into(db.customers)
          .insert(CustomersCompanion.insert(id: uuid('cl'), name: 'Soldé'));
      await db
          .into(db.receivables)
          .insert(
            ReceivablesCompanion.insert(
              id: uuid('cr'),
              customerId: uuid('cl'),
              amount: 20000,
              amountPaid: const Value(20000),
            ),
          );

      final d = await depot.charger(du: du, au: au);

      expect(d.creances, isEmpty);
    });

    /// ⚠️ Un fournisseur archivé doit rester NOMMÉ sur l'ardoise qu'il a
    /// laissée : le nom porté par la dette prime le référentiel.
    test('⚠️ la dette garde le nom qu elle porte', () async {
      await db
          .into(db.payables)
          .insert(
            PayablesCompanion.insert(
              id: uuid('dt'),
              supplierId: uuid('fo'),
              supplierName: const Value('Provenderie du Plateau'),
              amount: 185000,
              dueDate: Value(DateTime(2026, 7, 25)),
            ),
          );

      final d = await depot.charger(du: du, au: au);

      expect(d.dettes.single.cellules.first, 'Provenderie du Plateau');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('stocks', () {
    /// ⚠️⚠️ **UN STOCK NÉGATIF N'EST PAS UNE DETTE DE MARCHANDISE**, c'est une
    /// entrée non saisie. Le valoriser en négatif retrancherait de la valeur du
    /// magasin de l'argent qui n'a jamais quitté la ferme.
    test('⚠️⚠️ une quantité négative ne diminue pas la valeur', () async {
      await categorie('ca', 'Aliments & Provendes');
      await produit(
        'p1',
        nom: 'Maïs',
        categorie: uuid('ca'),
        stock: 10,
        prix: 500,
      );
      await produit(
        'p2',
        nom: 'Son',
        categorie: uuid('ca'),
        stock: -4,
        prix: 500,
      );

      final d = await depot.charger(du: du, au: au);

      expect(d.stocks.single.cellules, ['Aliments & Provendes', '5 000', '0']);
    });

    test(
      'le compte sous seuil est celui des produits sous leur alerte',
      () async {
        await categorie('ca', 'Produits vétérinaires');
        await produit(
          'p1',
          nom: 'Vaccin',
          categorie: uuid('ca'),
          stock: 2,
          prix: 1000,
          seuil: 5,
        );
        await produit(
          'p2',
          nom: 'Antibiotique',
          categorie: uuid('ca'),
          stock: 30,
          prix: 1000,
          seuil: 5,
        );

        final d = await depot.charger(du: du, au: au);

        expect(d.stocks.single.cellules[2], '1');
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('rapport élevage', () {
    /// ⚠️⚠️ **TREIZE COLONNES, ONZE TIRETS.** La ventilation par sexe et par
    /// stade existe côté serveur mais **ne quitte pas le poste à l'envoi** :
    /// `_ficheEnJson` ne la porte pas. Les colonnes restent AFFICHÉES — les
    /// retirer ferait croire que la maquette ne les demande pas.
    test(
      '⚠️⚠️ le tableau 1 garde ses treize colonnes, tirets compris',
      () async {
        await bande('b1');
        await journee('j1', lot: 'b1', date: DateTime(2026, 7, 13));

        final d = await depot.charger(du: du, au: au);
        final ligne = d.elevageT1.single.cellules;

        expect(ligne, hasLength(13));
        expect(ligne[0], '13/07/2026');
        expect(ligne[1], 'Pondeuses Lot P1');
        expect(ligne.sublist(2).where((c) => c == '—'), hasLength(11));
      },
    );

    test(
      '⚠️ le tableau 2 garde ses neuf colonnes, dont quatre réelles',
      () async {
        await bande('b1');
        await journee(
          'j1',
          lot: 'b1',
          date: DateTime(2026, 7, 13),
          vente: 12,
          effectifFinal: 488,
        );

        final d = await depot.charger(du: du, au: au);
        final ligne = d.elevageT2.single.cellules;

        expect(ligne, hasLength(9));
        expect(ligne[3], '12');
        expect(ligne[5], '488');
        expect(ligne.where((c) => c == '—'), hasLength(5));
      },
    );

    /// 🔴→✅ **TICKET U9 — LE TABLEAU 3 DU WEB** (`ElevageSynth` + `elevage-synth.blade.php`) : onze colonnes dont
    /// « Lot », soldes de FERME en PLATEAUX lus dans le grand livre des stocks (`EggStockLedgerService`), une ligne
    /// du grand livre par JOUR (deux bandes du même jour partagent le solde). Valeurs calculées à la main :
    ///  - grand livre descendu (œufs) : achat +5 le 30/06 ; production +13 le 06/07 ; ventes −2 le 06/07 et −3 le
    ///    10/07 ; casse (`inventaire`) −1 le 12/07 ; production +14 et vente −1 le 13/07 ;
    ///  - 06/07 : commercialisables 392 → 13 plateaux + 2 vrac ; SRH = 5 ; TS = 18 ; OS = 2 ; final 16 ;
    ///  - 13/07 : 428 (P1) + 100 (P2) = 528 → 17 plateaux + 18 vrac ; SRH = 5 + 13 − 2 − 3 − 1 = 12 ; TS = 29 ;
    ///    OS = 1 (ni la casse du 12, ni celle de −2 le 13 au matin ne sont des ventes) ; final 28.
    test('⚠️⚠️ U9 — le tableau 3 est celui du web : soldes de ferme en plateaux', () async {
      await produit('oeufs', nom: 'Œufs de table (plateau)');
      await bande('b1', creee: DateTime(2026, 1, 5));
      await bande('b2', code: 'Pondeuses Lot P2', creee: DateTime(2026, 7, 20));
      await journee('j1', lot: 'b1', date: DateTime(2026, 7, 6), effectifFinal: 443, ponteTotal: 398, ponteCasses: 6, statut: SyncStatus.synced);
      await journee('j2', lot: 'b1', date: DateTime(2026, 7, 13), effectifFinal: 461, ponteTotal: 432, ponteCasses: 4, statut: SyncStatus.synced);
      await journee('j3', lot: 'b2', date: DateTime(2026, 7, 13), effectifFinal: 0, ponteTotal: 100, statut: SyncStatus.synced);
      // Hors du tableau : ponte nulle, et fiche hors période.
      await journee('j4', lot: 'b1', date: DateTime(2026, 7, 14), ponteTotal: 0, statut: SyncStatus.synced);
      await journee('j5', lot: 'b1', date: DateTime(2026, 8, 2), ponteTotal: 300, statut: SyncStatus.synced);
      await mouvement('m1', 'oeufs', 'entree', 5, DateTime(2026, 6, 30, 10), reference: 'purchase');
      await mouvement('m2', 'oeufs', 'entree', 13, DateTime(2026, 7, 6), reference: 'daily_entry', referenceId: uuid('j1'));
      await mouvement('m3', 'oeufs', 'sortie', 2, DateTime(2026, 7, 6, 15));
      await mouvement('m4', 'oeufs', 'sortie', 3, DateTime(2026, 7, 10, 9));
      await mouvement('m5', 'oeufs', 'sortie', 1, DateTime(2026, 7, 12, 18), reference: 'inventaire');
      await mouvement('m6', 'oeufs', 'entree', 14, DateTime(2026, 7, 13), reference: 'daily_entry', referenceId: uuid('j2'));
      await mouvement('m7', 'oeufs', 'sortie', 1, DateTime(2026, 7, 13, 16));
      // Une casse le jour même : elle n'est pas une sortie de VENTE (OS reste 1), et elle n'est pas « avant » le 13.
      await mouvement('m8', 'oeufs', 'sortie', 2, DateTime(2026, 7, 13, 8), reference: 'inventaire');

      final d = await depot.charger(du: du, au: au);
      final lignes = {for (final l in d.elevageT3) '${l.cellules[1]} ${l.cellules[2]}': l.cellules};

      expect(d.elevageT3, hasLength(3));
      // Du plus récent au plus ancien, comme `orderByDesc('entry_date')`.
      expect(d.elevageT3.last.cellules[1], '06/07/2026');
      expect(lignes['06/07/2026 Pondeuses Lot P1'], [
        '26', // 182 jours depuis le 05/01
        '06/07/2026',
        'Pondeuses Lot P1',
        '398',
        '89.8 %', // 398 × 100 ÷ 443 = 89,84
        '6',
        '392',
        '5',
        '18',
        '2',
        '16 plateaux + 2 vrac',
      ]);
      expect(lignes['13/07/2026 Pondeuses Lot P1'], [
        '27',
        '13/07/2026',
        'Pondeuses Lot P1',
        '432',
        '93.7 %',
        '4',
        '428',
        '12',
        '29',
        '1',
        '28 plateaux + 18 vrac',
      ]);
      // P2 : même jour, MÊME solde de ferme ; bande créée APRÈS la fiche → âge signé −1 (Carbon 3 + `intdiv`) ;
      // effectif nul → « — % » ; OF absent → cellule vide (comme `{{ $e->ponte_casses }}`).
      expect(lignes['13/07/2026 Pondeuses Lot P2'], [
        '-1',
        '13/07/2026',
        'Pondeuses Lot P2',
        '100',
        '— %',
        '',
        '100',
        '12',
        '29',
        '1',
        '28 plateaux + 18 vrac',
      ]);
    });

    /// 🔴→✅ **TICKET U9 — RÈGLE DES SAISIES EN ATTENTE AU TABLEAU 3.** Une fiche de ponte ou une vente d'œufs saisie
    /// ici n'est au grand livre du serveur qu'après l'envoi : le poste la PROJETTE selon la règle du serveur
    /// (`RecordEggProductionStockAction` : ⌊(OR − OF) ÷ 30⌋ plateaux au jour de la fiche ; vente : sortie au jour
    /// `sold_at`), la RETIRE dès que son mouvement est descendu (même `reference_id`), et n'en projette aucune
    /// refusée. Calcul à la main, grand livre descendu : achat +10 le 01/07 ; fiche j5 (encore « en attente »,
    /// envoi sans accusé) déjà rejouée : +2 le 18/07.
    ///  - 18/07 (j5, 60 → 2 plateaux) : SRH 10 ; TS 12 ; OS 0 ; final 12 — j5 n'est PAS projetée en plus ;
    ///  - 20/07 (j4 en attente, 90 → 3 plateaux ; vente en attente −2 ; vente refusée −5 ignorée) : SRH 10 + 2 = 12 ;
    ///    TS 15 ; OS 2 ; final 13 ;
    ///  - 21/07 (j6 acquittée, 30 → 1 plateau) : SRH = 10 + 2 + 3 (j4 projetée) − 2 = 13 ; TS 14 ; OS 0 ; final 14.
    test('⚠️⚠️ U9 — saisies en attente projetées, jamais deux fois, jamais refusées', () async {
      await produit('oeufs', nom: 'Œufs de table (plateau)');
      await bande('b1', creee: DateTime(2026, 1, 5));
      await mouvement('m1', 'oeufs', 'entree', 10, DateTime(2026, 7, 1, 8), reference: 'purchase');
      await journee('j5', lot: 'b1', date: DateTime(2026, 7, 18), effectifFinal: 400, ponteTotal: 61, ponteCasses: 1);
      await mouvement('m2', 'oeufs', 'entree', 2, DateTime(2026, 7, 18), reference: 'daily_entry', referenceId: uuid('j5'));
      await journee('j4', lot: 'b1', date: DateTime(2026, 7, 20), effectifFinal: 400, ponteTotal: 95, ponteCasses: 5);
      await journee('j6', lot: 'b1', date: DateTime(2026, 7, 21), effectifFinal: 400, ponteTotal: 30, ponteCasses: 0, statut: SyncStatus.synced);
      Future<void> venteOeufs(String cle, DateTime quand, double plateaux, SyncStatus statut) async {
        await db.into(db.sales).insert(
          SalesCompanion.insert(
            id: uuid(cle),
            deviceId: 'poste-test',
            updatedAt: quand,
            syncStatus: Value(statut),
            paymentMode: 'especes',
            total: plateaux * 2500,
            soldAt: quand,
          ),
        );
        await db.into(db.saleLines).insert(
          SaleLinesCompanion.insert(
            id: uuid('l$cle'),
            saleId: uuid(cle),
            productId: uuid('oeufs'),
            lotId: Value(uuid('b1')),
            qty: plateaux,
            unitPrice: 2500,
            manualTotalAmount: plateaux * 2500,
          ),
        );
      }

      await venteOeufs('v1', DateTime(2026, 7, 20, 10), 2, SyncStatus.pending);
      await venteOeufs('v2', DateTime(2026, 7, 20, 11), 5, SyncStatus.conflict);

      final d = await depot.charger(du: du, au: au);
      final parJour = {for (final l in d.elevageT3) l.cellules[1]: l.cellules.sublist(7)};

      expect(parJour['18/07/2026'], ['10', '12', '0', '12 plateaux']);
      expect(parJour['20/07/2026'], ['12', '15', '2', '13 plateaux']);
      expect(parJour['21/07/2026'], ['13', '14', '0', '14 plateaux']);
    });

    /// Sans produit œufs au catalogue, le web lit des soldes nuls (`stockAvant` / `ventesDu` rendent 0) : le TS est la
    /// seule production du jour, en plateaux — jamais un tiret.
    test('U9 — sans produit œufs, les soldes valent zéro comme au web', () async {
      await bande('b1', creee: DateTime(2026, 7, 1));
      await journee('j1', lot: 'b1', date: DateTime(2026, 7, 13), effectifFinal: 200, ponteTotal: 95, ponteCasses: 5, statut: SyncStatus.synced);

      final d = await depot.charger(du: du, au: au);

      expect(d.elevageT3.single.cellules.sublist(7), ['0', '3', '0', '3 plateaux']);
    });

    test('⚠️ sans date de création de bande, l âge est un tiret', () async {
      await bande('b1');
      await journee(
        'j1',
        lot: 'b1',
        date: DateTime(2026, 7, 13),
        ponteTotal: 100,
      );

      final d = await depot.charger(du: du, au: au);

      expect(d.elevageT3.single.cellules.first, '—');
    });

    /// ⚠️⚠️ **LA MORTALITÉ SE RAPPORTE À L'EFFECTIF DE DÉBUT DE JOURNÉE.**
    /// Diviser par l'effectif FINAL la surestimerait — l'effectif final est
    /// justement amputé des morts.
    test('⚠️⚠️ la mortalité se calcule sur l effectif de début', () async {
      await bande('b1');
      await journee(
        'j1',
        lot: 'b1',
        date: DateTime(2026, 7, 13),
        effectifFinal: 494,
        mort: 6,
      );

      final d = await depot.charger(du: du, au: au);

      // 6 / 500 = 1,2 %, et non 6 / 494 = 1,21 %.
      expect(d.indicateurs.mortaliteHebdo, closeTo(1.2, 0.001));
    });

    /// ⚠️ `vente_montant` n'est pas dans la charge utile d'envoi : le poste ne
    /// l'a jamais eu. « 0 FCFA » dirait « rien n'a été vendu ».
    test('⚠️ le CA du lot est inconnu, pas nul', () async {
      await bande('b1');
      await journee('j1', lot: 'b1', date: DateTime(2026, 7, 13), vente: 20);

      final d = await depot.charger(du: du, au: au);

      expect(d.indicateurs.chiffreAffaires, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('document officiel', () {
    /// ⚠️⚠️ **LES TROIS STRUCTURES, SUR CHAQUE PAGE IMPRIMÉE.** Le ticket 15.2
    /// avait effacé le cabinet des pieds de page côté web sans que personne ne
    /// s'en aperçoive pendant deux tickets : un crédit manquant ne casse rien
    /// et n'émet aucune erreur. `pdf-export.js` ne nomme que deux structures —
    /// il précède les tickets 15.7 et 15.8.
    test('⚠️⚠️ le pied de page crédite les trois structures', () {
      const credits = ExportOfficiel.creditsProjet;

      expect(credits, contains('PAEB'));
      expect(credits, contains('Cabinet FAGUEZ SARL'));
      expect(credits, contains('MASSENON Rhodes'));
    });

    test('l identité de la ferme est celle de la maquette', () {
      expect(ExportOfficiel.nomFerme, 'FERME ÉCOLE OLOUWACHEGOUN');
      expect(ExportOfficiel.adresseFerme, contains('Ikpinlè'));
    });

    test('le document se construit sans logo, et avec', () async {
      const doc = DocumentOfficiel(
        titre: 'État de Trésorerie',
        sousTitre: 'Évolution des soldes Caisse et Banque',
        entetes: ['Date', 'Solde Caisse', 'Solde Banque', 'Solde Total'],
        lignes: [
          DonneesDocument(['15/07/2026', '420 000', '1 180 000', '1 600 000']),
        ],
      );

      final octets = await ExportOfficiel.construire(
        doc,
        maintenant: maintenant,
      );

      // Un PDF commence par `%PDF`.
      expect(octets.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
      expect(octets.length, greaterThan(500));
    });

    /// ⚠️⚠️ **LE FILIGRANE NE DOIT PAS POUSSER LE TABLEAU.** `pdf-export.js`
    /// le pose en `position:fixed` : il flotte sans occuper de place. Rendu
    /// comme un bloc ordinaire, il décalerait le tableau de 90 px sur chaque
    /// page — un document toujours lisible, et toujours différent de celui qui
    /// a été validé. Aucun des six rapports n'en porte aujourd'hui : sans ce
    /// contrôle, le chemin resterait inexercé jusqu'au premier PROFORMA.
    test(
      '⚠️⚠️ un filigrane est un fond de page, pas un bloc du corps',
      () async {
        const corps = [
          DonneesDocument(['15/07/2026', '420 000']),
        ];

        final sans = await ExportOfficiel.construire(
          const DocumentOfficiel(
            titre: 'État de Trésorerie',
            sousTitre: 'Sans filigrane',
            entetes: ['Date', 'Solde'],
            lignes: corps,
          ),
          maintenant: maintenant,
        );

        final avec = await ExportOfficiel.construire(
          const DocumentOfficiel(
            titre: 'État de Trésorerie',
            sousTitre: 'Sans filigrane',
            entetes: ['Date', 'Solde'],
            lignes: corps,
            filigrane: 'PROFORMA',
          ),
          maintenant: maintenant,
        );

        // Le document filigrané est plus lourd — le mot est bien dessiné…
        expect(avec.length, greaterThan(sans.length));
        // …et les deux tiennent en UNE page : le filigrane n'a rien repoussé.
        expect(sans.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
        expect(avec.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
      },
    );

    /// ⚠️ Le nombre de colonnes se déduit du corps quand le document n'a pas
    /// d'en-tête propre — cas des rapports à bandes de section.
    test('⚠️ un document à bandes compte ses colonnes sur son corps', () {
      const doc = DocumentOfficiel(
        titre: 'État des Recettes et Dépenses',
        sousTitre: 'Synthèse financière de la période',
        lignes: [
          BandeDocument('RECETTES'),
          EnteteDocument(['Date', 'Libellé', 'Montant']),
          DonneesDocument(['10/07/2026', 'Vente', '+45 000 FCFA']),
        ],
      );

      expect(doc.colonnes, 3);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('classeur', () {
    test('le classeur est un zip xlsx non vide', () {
      const doc = DocumentOfficiel(
        titre: 'Rapport de Synthèse des Stocks',
        sousTitre: 'Valorisation et alertes de seuil par catégorie',
        entetes: ['Catégorie', 'Valeur Stock', 'Sous Seuil'],
        lignes: [
          DonneesDocument(['Aliments & Provendes', '420 000', '2']),
        ],
      );

      final octets = ExportTableur.construire(doc);

      // Un `.xlsx` est un zip : « PK\x03\x04 ».
      expect(octets.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
    });

    /// ⚠️⚠️ **UN NOM D'ONGLET DE PLUS DE 31 CARACTÈRES PRODUIT UN FICHIER QUE
    /// EXCEL DÉCLARE CORROMPU.** « Rapport Élevage — Synthèse Détaillée » en
    /// fait 36.
    test(
      '⚠️⚠️ le classeur du rapport élevage s ouvre malgré son titre long',
      () {
        const doc = DocumentOfficiel(
          titre: 'Rapport Élevage — Synthèse Détaillée',
          sousTitre: 'Recensement, mouvements et suivi de ponte',
          lignes: [
            BandeDocument('TABLEAU 1 — RECENSEMENT HEBDOMADAIRE'),
            DonneesDocument(['13/07/2026', 'Pondeuses Lot P1']),
          ],
        );

        expect(doc.titre.length, greaterThan(31));
        final octets = ExportTableur.construire(doc);
        expect(octets.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      },
    );

    /// ⚠️ Deux éditions du même rapport le même jour sont la situation
    /// NORMALE — on filtre, on réédite. Sans l'heure, la seconde écraserait la
    /// première sans rien demander.
    test('⚠️ le nom de fichier est horodaté jusqu à la minute', () {
      final nom = ExportTableur.nomFichier('État de Trésorerie', maintenant);

      expect(nom, 'État-de-Trésorerie-20260825-1430.xlsx');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('écran', () {
    /// Éditeurs de test : ils retiennent le document sans rien imprimer.
    late List<DocumentOfficiel> imprimes;
    late List<DocumentOfficiel> enregistres;

    setUp(() {
      imprimes = [];
      enregistres = [];
    });

    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1900, 2400);
      tester.view.devicePixelRatio = 1;
      // ⚠️ La taille de vue SURVIT au test qui l'a posée : sans remise à zéro,
      // l'écran suivant se rend dans la fenêtre de celui-ci.
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: RapportsExportsScreen(
            depot: depot,
            maintenant: () => maintenant,
            imprimer: (doc, _) async {
              imprimes.add(doc);
              return null;
            },
            enregistrer: (doc, _) async {
              enregistres.add(doc);
              return r'C:\Documents\AgriERP\rapport.xlsx';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> ouvrir(WidgetTester tester, String onglet) async {
      final cible = find.byKey(Key('onglet-rapports-$onglet'));
      await tester.ensureVisible(cible);
      await tester.tap(cible);
      await tester.pumpAndSettle();
    }

    /// ⚠️⚠️ **`cartesMaquette` N'AVAIT JAMAIS ÉTÉ LU PAR UN TEST** depuis sa
    /// génération au ticket F0.49. Le ticket F0.53 a cherché pourquoi, et la
    /// réponse n'est pas la négligence : **le nombre de cartes n'est pas
    /// vérifiable en lisant la source.**
    ///
    /// Compter les occurrences de `CarteKpi(` échoue de deux façons opposées :
    ///   • **par défaut** — les cartes construites en boucle n'apparaissent
    ///     qu'UNE fois dans le fichier. Cet écran en rend sept et n'écrit
    ///     `CarteKpi(` qu'une seule fois ;
    ///   • **par excès** — un fichier qui porte plusieurs pages de la maquette
    ///     mélange leurs cartes, sans qu'on puisse les rattacher à l'une ou à
    ///     l'autre.
    ///
    /// Le seul contrôle honnête est donc **au rendu, onglet par onglet**. Il
    /// est posé ici pour les deux pages de ce hub qui portent des cartes ; les
    /// autres écrans demanderont le même geste, chacun dans son test.
    testWidgets('⚠️⚠️ chaque onglet rend le nombre de cartes de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      expect(
        find.byType(CarteKpi),
        findsNWidgets(cartesAttendues('rapport-recettes-depenses.html')),
      );

      await ouvrir(tester, 'Rapport Élevage');
      expect(
        find.byType(CarteKpi),
        findsNWidgets(cartesAttendues('rapport-elevage-synth.html')),
      );

      // ⚠️ Les quatre autres pages n'en portent AUCUNE dans la maquette :
      // en rendre une ici serait un ajout, pas un oubli.
      for (final onglet in const [
        'État de Trésorerie',
        'Créances Clients',
        'Dettes Fournisseurs',
        'Rapport de Stocks',
      ]) {
        await ouvrir(tester, onglet);
        expect(find.byType(CarteKpi), findsNothing, reason: onglet);
      }
    });

    testWidgets('les six onglets du hub sont là, dans son ordre', (
      tester,
    ) async {
      await afficher(tester);

      expect(RapportsExportsScreen.onglets.map((o) => o.$1), [
        'Recettes et Dépenses',
        'État de Trésorerie',
        'Créances Clients',
        'Dettes Fournisseurs',
        'Rapport Élevage',
        'Rapport de Stocks',
      ]);

      for (final (titre, _) in RapportsExportsScreen.onglets) {
        expect(find.byKey(Key('onglet-rapports-$titre')), findsOneWidget);
      }
    });

    testWidgets('le hub ouvre sur les recettes et dépenses', (tester) async {
      await afficher(tester);

      expect(find.text('État des Recettes et Dépenses'), findsOneWidget);
    });

    /// ⚠️⚠️ **CHAQUE ONGLET ÉDITE SON PROPRE DOCUMENT.** Un titre générique
    /// ferait six documents indiscernables dans un classeur de ferme.
    testWidgets('⚠️⚠️ l export suit l onglet actif', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('hub-export-pdf')));
      await tester.pumpAndSettle();
      expect(imprimes.single.titre, 'État des Recettes et Dépenses');

      await ouvrir(tester, 'Créances Clients');
      await tester.tap(find.byKey(const Key('hub-export-pdf')));
      await tester.pumpAndSettle();
      expect(imprimes.last.titre, 'Rapport des Créances Clients');
      expect(
        imprimes.last.sousTitre,
        'Synthèse des sommes dues par les clients',
      );
    });

    /// ⚠️⚠️ **« Lecture seule » NE S'IMPRIME PAS.** La maquette exclut la
    /// colonne Actions de ses exports (`slice(0, 3)`), et pour cause : la
    /// mention n'a aucun sens sur un état officiel.
    testWidgets('⚠️⚠️ la colonne Actions ne part pas au document', (
      tester,
    ) async {
      await db
          .into(db.customers)
          .insert(CustomersCompanion.insert(id: uuid('cl'), name: 'Client X'));
      await db
          .into(db.receivables)
          .insert(
            ReceivablesCompanion.insert(
              id: uuid('cr'),
              customerId: uuid('cl'),
              amount: 5000,
            ),
          );

      await afficher(tester);
      await ouvrir(tester, 'Créances Clients');
      await tester.tap(find.byKey(const Key('hub-export-pdf')));
      await tester.pumpAndSettle();

      final doc = imprimes.single;
      expect(doc.entetes, ['Client', 'Montant Dû', 'Échéance']);
      expect(doc.entetes, isNot(contains('Actions')));

      final ligne = doc.lignes.single as DonneesDocument;
      expect(ligne.cellules, hasLength(3));
      expect(ligne.cellules.join(), isNot(contains('Lecture seule')));
    });

    testWidgets('la barre du rapport porte sa propre paire de boutons', (
      tester,
    ) async {
      await afficher(tester);

      expect(find.byKey(const Key('hub-export-pdf')), findsOneWidget);
      expect(find.byKey(const Key('rapport-export-pdf')), findsOneWidget);
      expect(find.byKey(const Key('rapport-export-excel')), findsOneWidget);
    });

    testWidgets('le classeur annonce son chemin', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('hub-export-excel')));
      await tester.pumpAndSettle();

      expect(enregistres, hasLength(1));
      expect(
        find.textContaining(r'C:\Documents\AgriERP\rapport.xlsx'),
        findsOneWidget,
      );
    });

    /// ⚠️ La série journalière n'existe pas au poste : l'écran le DIT, avec sa
    /// date, au lieu de laisser croire à un tableau complet.
    testWidgets('⚠️ la trésorerie dit ce qu elle ne couvre pas', (
      tester,
    ) async {
      await compteTresorerie('t1', type: 'caisse', solde: 420000);
      await tirageLe(DateTime(2026, 7, 15));

      await afficher(tester);
      await ouvrir(tester, 'État de Trésorerie');

      expect(
        find.textContaining('ne tient PAS la série journalière'),
        findsOneWidget,
      );
      expect(find.textContaining('15/07/2026'), findsWidgets);
    });

    testWidgets('⚠️ sans tirage, la trésorerie invite à synchroniser', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'État de Trésorerie');

      expect(find.textContaining('Synchronisez'), findsOneWidget);
    });

    testWidgets('les trois tableaux d élevage ont leurs pilules', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Rapport Élevage');

      for (final titre in RapportsExportsScreen.tableauxElevage) {
        expect(find.byKey(Key('pilule-$titre')), findsOneWidget);
      }

      expect(find.byKey(const Key('tableau-elevage-t1')), findsOneWidget);
    });

    testWidgets('une pilule change de tableau', (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'Rapport Élevage');

      final pilule = find.byKey(
        Key('pilule-${RapportsExportsScreen.tableauxElevage[2]}'),
      );
      await tester.ensureVisible(pilule);
      await tester.tap(pilule);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tableau-elevage-t3')), findsOneWidget);
      expect(find.byKey(const Key('tableau-elevage-t1')), findsNothing);
      // Le pied de tableau rappelle les formules, comme la maquette.
      expect(
        find.textContaining('Taux de Ponte % = (OR × 100)'),
        findsOneWidget,
      );
    });

    /// ⚠️ Le document d'élevage porte les TROIS tableaux, chacun sous sa
    /// bande — l'onglet affiché n'en montre qu'un à la fois.
    testWidgets('⚠️ le document d élevage porte ses trois bandes', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Rapport Élevage');
      await tester.tap(find.byKey(const Key('hub-export-pdf')));
      await tester.pumpAndSettle();

      final bandes = imprimes.single.lignes
          .whereType<BandeDocument>()
          .map((b) => b.libelle)
          .toList();

      expect(bandes, hasLength(3));
      expect(bandes[0], contains('TABLEAU 1'));
      expect(bandes[2], contains('TABLEAU 3'));
    });

    testWidgets('la modale de période exige un format', (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'Rapport Élevage');

      await tester.tap(find.byKey(const Key('elevage-filtrer-periode')));
      await tester.pumpAndSettle();

      expect(find.text('Filtrer la Période'), findsWidgets);

      await tester.tap(find.byKey(const Key('exp-elevage-generer')));
      await tester.pumpAndSettle();

      expect(find.text('Le champ « Format » est obligatoire.'), findsOneWidget);
      expect(imprimes, isEmpty);
    });

    testWidgets('la recherche filtre les lignes affichées', (tester) async {
      await categorie('c1', 'Aliments & Provendes');
      await categorie('c2', 'Produits vétérinaires');
      await produit('p1', nom: 'Maïs', categorie: uuid('c1'), stock: 5);
      await produit('p2', nom: 'Vaccin', categorie: uuid('c2'), stock: 5);

      await afficher(tester);
      await ouvrir(tester, 'Rapport de Stocks');

      expect(find.text('Aliments & Provendes'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('recherche-stocks')),
        'vétérinaires',
      );
      await tester.pumpAndSettle();

      expect(find.text('Aliments & Provendes'), findsNothing);
      expect(find.text('Produits vétérinaires'), findsOneWidget);
    });

    testWidgets('sans donnée, chaque tableau le dit', (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'Dettes Fournisseurs');

      expect(find.text('— Aucune dette ouverte —'), findsOneWidget);
    });
  });
}
