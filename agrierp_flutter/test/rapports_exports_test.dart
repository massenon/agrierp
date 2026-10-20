import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/core/export/export_tableur.dart';
import 'package:agrierp/features/rapports/rapports_exports_screen.dart';
import 'package:agrierp/features/rapports/rapports_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
    SyncStatus envoi = SyncStatus.pending,
  }) => db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          id: uuid(cle),
          deviceId: 'poste-test',
          syncStatus: Value(envoi),
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

  Future<void> bande(
    String cle, {
    String code = 'Pondeuses Lot P1',
    DateTime? creee,
    String espece = 'aviculture',
    String stade = 'ponte',
    int initial = 0,
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
          initialQuantity: Value(initial),
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
    double? venteMontant,
    String? venteSexe,
    int? effectifM,
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
          venteMontant: Value(venteMontant),
          venteSexe: Value(venteSexe),
          effectifM: Value(effectifM),
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

  /// Ticket U12b — un achat (descendu du serveur, ou refusé par lui avec [statut]).
  Future<void> achat(
    String cle, {
    required DateTime date,
    required double total,
    String mode = 'especes',
    String? fournisseur,
    SyncStatus statut = SyncStatus.synced,
  }) => db
      .into(db.purchases)
      .insert(
        PurchasesCompanion.insert(
          id: uuid(cle),
          deviceId: 'serveur',
          syncStatus: Value(statut),
          updatedAt: date,
          supplierId: uuid('fournisseur'),
          supplierName: Value(fournisseur),
          paymentMode: mode,
          total: total,
          purchaseDate: date,
        ),
      );

  Future<void> ligneAchat(
    String cle,
    String achatCle,
    String produitCle,
    double quantite,
    double prix,
  ) => db
      .into(db.purchaseLines)
      .insert(
        PurchaseLinesCompanion.insert(
          id: uuid(cle),
          purchaseId: uuid(achatCle),
          productId: uuid(produitCle),
          qty: quantite,
          unitPrice: prix,
        ),
      );

  /// Ticket U12b — un compte du plan comptable et une écriture du grand livre (descendus du serveur).
  Future<void> compte(String cle, String code, int classe) => db
      .into(db.chartOfAccounts)
      .insert(
        ChartOfAccountsCompanion.insert(
          id: uuid(cle),
          code: code,
          label: 'Compte $code',
          accountClass: Value(classe),
        ),
      );

  Future<void> ecriture(
    String cle,
    DateTime date,
    List<(String, double, double)> lignes,
  ) async {
    await db
        .into(db.accountingEntries)
        .insert(AccountingEntriesCompanion.insert(id: uuid(cle), entryDate: date));
    for (var i = 0; i < lignes.length; i++) {
      final (compteCle, debit, credit) = lignes[i];
      await db
          .into(db.accountingEntryLines)
          .insert(
            AccountingEntryLinesCompanion.insert(
              id: uuid('$cle-l$i'),
              entryId: uuid(cle),
              accountId: uuid(compteCle),
              debit: Value(debit),
              credit: Value(credit),
            ),
          );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  group('recettes et dépenses', () {
    test(
      '⚠️ une vente annulée ne compte pas au chiffre d affaires',
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

    /// 🔴→✅ Ticket U12b — `payment_mode != 'credit'` : une vente à crédit n'a rien encaissé, elle est une créance.
    test(
      '⚠️⚠️ U12b — une vente à crédit n est pas une recette, une vente sur avance l est',
      () async {
        await vente('v1', date: DateTime(2026, 7, 10), total: 45000, mode: 'credit');
        await vente('v2', date: DateTime(2026, 7, 10), total: 12000, mode: 'avance');

        final d = await depot.charger(du: du, au: au);

        expect(d.totalRecettes, 12000);
        expect(d.recettes.single.montant, 12000);
      },
    );

    /// Règle U8 : une vente REFUSÉE par le serveur (`conflict`) n'existe pas au web ; une vente en attente d'envoi
    /// compte, elle part vers lui.
    test('⚠️ U12b — une vente refusée par le serveur n est pas une recette', () async {
      await vente('v1', date: DateTime(2026, 7, 10), total: 1000);
      await vente('v2', date: DateTime(2026, 7, 10), total: 2000, envoi: SyncStatus.synced);
      await vente('v3', date: DateTime(2026, 7, 10), total: 4000, envoi: SyncStatus.conflict);

      final d = await depot.charger(du: du, au: au);

      expect(d.totalRecettes, 3000);
    });

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

    /// 🔴→✅ Ticket U12b — libellés et cellules du Blade : « Vente — client » (« Client comptant »), le seul libellé de
    /// la dépense, montants signés suivis de « FCFA ».
    test('U12b — les cellules sont celles du Blade', () async {
      await vente('v1', date: DateTime(2026, 7, 10), total: 45000, client: 'Bar Le Palmier');
      await vente('v2', date: DateTime(2026, 7, 9), total: 1500.5);
      await depense('d1', date: DateTime(2026, 7, 12), montant: 185000);

      final d = await depot.charger(du: du, au: au);

      expect([for (final r in d.recettes) RapportsRepository.celluleRecette(r)], [
        ['10/07/2026', 'Vente — Bar Le Palmier', '+45 000 FCFA'],
        ['09/07/2026', 'Vente — Client comptant', '+1 501 FCFA'],
      ]);
      expect(RapportsRepository.celluleDepense(d.depenses.single), [
        '12/07/2026',
        'Achat provende',
        '-185 000 FCFA',
      ]);
    });

    /// 🔴→✅ Ticket U12b — `depensesRows()` : les ACHATS non à crédit sont des dépenses (« Achat — fournisseur »), et
    /// passent avant une dépense du même jour (tri stable) ; un achat à crédit ou refusé par le serveur n'y est pas.
    test('⚠️⚠️ U12b — les achats payés sont des dépenses, avant celles du même jour', () async {
      await depense('d1', date: DateTime(2026, 7, 12), montant: 5000, libelle: 'Carburant');
      await achat('a1', date: DateTime(2026, 7, 12), total: 70000, fournisseur: 'Provenderie du Plateau');
      await achat('a2', date: DateTime(2026, 7, 12), total: 90000, mode: 'credit');
      await achat('a3', date: DateTime(2026, 7, 13), total: 1000, statut: SyncStatus.conflict);
      await achat('a4', date: DateTime(2026, 7, 11), total: 2000);

      final d = await depot.charger(du: du, au: au);

      expect([for (final m in d.depenses) m.libelle], [
        'Achat — Provenderie du Plateau',
        'Carburant',
        'Achat — Fournisseur',
      ]);
      expect(d.totalDepenses, 77000);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('trésorerie', () {
    /// 🔴→✅ Ticket U12b — `Tresorerie::getRowsProperty()` : une ligne par JOUR de la période où la trésorerie a bougé,
    /// soldes CUMULÉS depuis l'origine (les écritures d'avant la période comptent), comptes 531… en caisse, AUTRES
    /// comptes de classe 5 (banque, Mobile Money) en banque.
    test('⚠️⚠️ U12b — soldes cumulés du grand livre, du plus récent au plus ancien', () async {
      await compte('c531', '531', 5);
      await compte('c5312', '5312', 5);
      await compte('c521', '521', 5);
      await compte('c552', '552', 5);
      // `str_starts_with($b->code, '531')` : un autre compte 53… n'est PAS la caisse.
      await compte('c532', '532', 5);
      await compte('c701', '701', 7);
      // Avant la période : 100 000 en caisse.
      await ecriture('e0', DateTime(2026, 6, 20), [('c531', 100000, 0), ('c701', 0, 100000)]);
      // 03/07 : 20 000 de la caisse à la banque.
      await ecriture('e1', DateTime(2026, 7, 3), [('c521', 20000, 0), ('c531', 0, 20000)]);
      // 10/07 : 5 000 en Mobile Money, 2 500 en caisse annexe.
      await ecriture('e2', DateTime(2026, 7, 10), [('c552', 5000, 0), ('c5312', 2500, 0), ('c701', 0, 7500)]);
      // 12/07 : 1 000 sur un compte 532 — côté banque.
      await ecriture('e5', DateTime(2026, 7, 12), [('c532', 1000, 0), ('c701', 0, 1000)]);
      // 15/07 : aucune ligne de classe 5 — pas de ligne au rapport.
      await ecriture('e3', DateTime(2026, 7, 15), [('c701', 100, 0), ('c701', 0, 100)]);
      // Après la période.
      await ecriture('e4', DateTime(2026, 8, 2), [('c531', 1, 0), ('c701', 0, 1)]);

      final d = await depot.charger(du: du, au: au);

      expect([for (final s in d.tresorerie) RapportsRepository.celluleTresorerie(s)], [
        ['12/07/2026', '82 500', '26 000', '108 500'],
        ['10/07/2026', '82 500', '25 000', '107 500'],
        ['03/07/2026', '80 000', '20 000', '100 000'],
      ]);
    });

    test('U12b — sans écriture de trésorerie, aucune ligne', () async {
      final d = await depot.charger(du: du, au: au);

      expect(d.tresorerie, isEmpty);
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

      expect(RapportsRepository.celluleEcheance(d.creances.single), [
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
              dueDate: Value(DateTime(2026, 7, 5)),
            ),
          );

      final d = await depot.charger(du: du, au: au);

      expect(d.creances, isEmpty);
    });

    /// 🔴→✅ Ticket U12b — la période du hub s'applique à l'ÉCHÉANCE (`whereDate('due_date', …)`) : une échéance hors
    /// période, ou absente, ne figure pas.
    test('⚠️ U12b — seules les échéances de la période figurent', () async {
      await db
          .into(db.customers)
          .insert(CustomersCompanion.insert(id: uuid('cl'), name: 'Client'));
      for (final (cle, echeance) in [
        ('c1', DateTime(2026, 6, 30)),
        ('c2', DateTime(2026, 7, 31)),
        ('c3', null),
        ('c4', DateTime(2026, 8, 1)),
      ]) {
        await db
            .into(db.receivables)
            .insert(
              ReceivablesCompanion.insert(
                id: uuid(cle),
                customerId: uuid('cl'),
                amount: 1000,
                dueDate: Value(echeance),
              ),
            );
      }

      final d = await depot.charger(du: du, au: au);

      expect(d.creances.single.id, uuid('c2'));
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

      expect(d.dettes.single.nom, 'Provenderie du Plateau');
    });

    /// La recherche des Dettes suit `LIKE` sous la collation du serveur (`utf8mb4_unicode_ci`) : ni casse ni accents ;
    /// « 0 » est faux en PHP (`->when('0')`) : il ne filtre rien.
    test('U12b — la recherche des dettes ignore casse et accents', () {
      final jour = DateTime(2026, 7, 10);
      final dettes = [
        EcheanceRapport(id: 'a', nom: 'Pharmacie Vétérinaire Ézéchiel', reste: 1, echeance: jour),
        EcheanceRapport(id: 'b', nom: 'Provenderie du Plateau', reste: 1, echeance: jour),
        EcheanceRapport(id: 'c', nom: null, reste: 1, echeance: jour),
      ];

      expect(RapportsRepository.filtrerDettes(dettes, 'ezechiel').map((e) => e.id), ['a']);
      expect(RapportsRepository.filtrerDettes(dettes, 'PLATEAU').map((e) => e.id), ['b']);
      expect(RapportsRepository.filtrerDettes(dettes, '0'), hasLength(3));
      expect(RapportsRepository.filtrerDettes(dettes, ''), hasLength(3));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('stocks', () {
    /// ⚠️⚠️ **UN STOCK NÉGATIF N'EST PAS UNE DETTE DE MARCHANDISE**, c'est une
    /// entrée non saisie (`Product::valeurStock()` : plancher à zéro). 🔴→✅ Ticket U12b — la valeur est celle du PMP
    /// des achats (`computePmp()`), et non plus le prix de vente minimal.
    test('⚠️⚠️ une quantité négative ne diminue pas la valeur, valorisée au PMP', () async {
      await categorie('ca', 'Aliments & Provendes');
      await produit('p1', nom: 'Maïs', categorie: uuid('ca'), stock: 10, prix: 999);
      await produit('p2', nom: 'Son', categorie: uuid('ca'), stock: -4, prix: 999);
      await achat('a1', date: DateTime(2026, 7, 1), total: 0);
      await ligneAchat('l1', 'a1', 'p1', 4, 400);
      await ligneAchat('l2', 'a1', 'p1', 6, 600);
      await ligneAchat('l3', 'a1', 'p2', 1, 300);

      final d = await depot.charger(du: du, au: au);

      // PMP du maïs = (4 × 400 + 6 × 600) ÷ 10 = 520 ; 10 × 520 = 5 200 ; le son (−4) vaut 0.
      final l = d.stocks.single;
      expect(l.valeur, 5200);
      expect(l.negatifs, 1);
      expect(RapportsRepository.texteValeurStock(l),
          '5 200 FCFA (1 produit(s) en stock négatif, retenus à zéro)');
    });

    test(
      'le compte sous seuil est celui des produits sous leur alerte',
      () async {
        await categorie('ca', 'Produits vétérinaires');
        await produit('p1', nom: 'Vaccin', categorie: uuid('ca'), stock: 2, seuil: 5);
        await produit('p2', nom: 'Antibiotique', categorie: uuid('ca'), stock: 30, seuil: 5);
        // Seuil nul et stock nul : `0 <= 0`, sous seuil au web.
        await produit('p3', nom: 'Seringue', categorie: uuid('ca'), stock: 0, seuil: 0);

        final d = await depot.charger(du: du, au: au);

        expect(d.stocks.single.sousSeuil, 2);
        // Aucun n'a été acheté ; deux sont en stock, donc non valorisés.
        expect(d.stocks.single.nonValorises, 2);
        expect(d.stocks.single.valeur, 0);
      },
    );

    /// 🔴→✅ Ticket U12b — `ProductCategory::where('is_active', true)` puis le filtre « au moins un produit actif » :
    /// ni catégorie archivée, ni catégorie vide, ni « Sans catégorie ».
    test('U12b — seules les catégories actives ayant un produit actif figurent', () async {
      await categorie('c1', 'Œufs');
      await categorie('c2', 'Matériel');
      await db
          .into(db.productCategories)
          .insert(ProductCategoriesCompanion.insert(id: uuid('c3'), label: 'Ancienne', isActive: const Value(false)));
      await produit('p1', nom: 'Plateau', categorie: uuid('c1'), stock: 3);
      await produit('p2', nom: 'Vieux', categorie: uuid('c3'), stock: 3);
      await produit('p3', nom: 'Orphelin', stock: 3);

      final d = await depot.charger(du: du, au: au);

      expect(d.stocks.map((l) => l.categorie), ['Œufs']);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('rapport élevage', () {
    /// 🔴→✅ **TICKET U10 — LE TABLEAU 1 DU BLADE** : dix colonnes (Date, Lot / Souche, Effectif M, Effectif F,
    /// Sous Mères, Sevrés, Achats, Nés, Morts, Effectif Final) ; une ventilation absente rend une cellule VIDE,
    /// comme `{{ $e->effectif_m }}` au web — ni « — » ni 0.
    test(
      '⚠️⚠️ U10 — le tableau 1 a les dix colonnes du Blade, cellule vide pour une ventilation absente',
      () async {
        await bande('b1');
        await journee(
          'j1',
          lot: 'b1',
          date: DateTime(2026, 7, 13),
          effectifM: 40,
          achat: 2,
          ne: 3,
          mort: 1,
        );

        final d = await depot.charger(du: du, au: au);

        expect(d.elevageT1.single.cellules, [
          '13/07/2026',
          'Pondeuses Lot P1',
          '40',
          '',
          '',
          '',
          '2',
          '3',
          '1',
          '100',
        ]);
      },
    );

    /// 🔴→✅ **TICKET U10 — LE TABLEAU 2 DU BLADE**, cellules réelles : sexe vendu, montant (« 0 » sans montant,
    /// comme `number_format(null)`), traitement « — », dose « — », symptômes « RAS ».
    test(
      '⚠️ U10 — le tableau 2 porte le sexe et le montant de la vente, « — » et « RAS » comme le web',
      () async {
        await bande('b1');
        await journee(
          'j1',
          lot: 'b1',
          date: DateTime(2026, 7, 13),
          vente: 12,
          effectifFinal: 488,
          venteSexe: 'F',
          venteMontant: 36500,
        );
        await journee('j2', lot: 'b1', date: DateTime(2026, 7, 12));

        final d = await depot.charger(du: du, au: au);

        expect(d.elevageT2.first.cellules, [
          '13/07/2026',
          'Pondeuses Lot P1',
          'F',
          '12',
          '36 500',
          '488',
          '—',
          '—',
          'RAS',
        ]);
        expect(d.elevageT2.last.cellules.sublist(2, 5), ['—', '0', '0']);
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

    /// 🔴→✅ **TICKET U10 — LA MORTALITÉ DU WEB** : Σ morts de la sélection ÷ `previousEffectif()` de la fiche la
    /// PLUS ANCIENNE — l'effectif final de la fiche précédente de sa bande, même HORS période (30/06 : 500). Le
    /// poste reconstituait l'effectif de début de chaque journée ; une fiche refusée ne compte pas.
    test('⚠️⚠️ U10 — la mortalité se calcule sur l effectif de la veille de la première fiche', () async {
      await bande('b1');
      await journee(
        'j0',
        lot: 'b1',
        date: DateTime(2026, 6, 30),
        effectifFinal: 500,
        mort: 9,
        statut: SyncStatus.synced,
      );
      await journee(
        'j1',
        lot: 'b1',
        date: DateTime(2026, 7, 13),
        effectifFinal: 494,
        mort: 6,
      );
      await journee(
        'j2',
        lot: 'b1',
        date: DateTime(2026, 7, 14),
        effectifFinal: 491,
        mort: 3,
      );
      await journee(
        'refusee',
        lot: 'b1',
        date: DateTime(2026, 7, 15),
        mort: 50,
        statut: SyncStatus.conflict,
      );

      final d = await depot.charger(du: du, au: au);

      // (6 + 3) ÷ 500 × 100 = 1,8 — ni les 9 morts du 30/06 (hors période), ni la fiche refusée.
      expect(d.indicateurs.mortaliteHebdo, 1.8);
      expect(IndicateursElevage.taux(d.indicateurs.mortaliteHebdo), '1.8 %');
      expect(d.elevageT1, hasLength(2));
    });

    /// Ticket U10 — sans fiche antérieure, l'effectif de début est l'effectif INITIAL de la bande
    /// (`$this->lot?->initial_quantity`) : 6 ÷ 480 × 100 = 1,25 → 1,3 (arrondi demi loin de zéro).
    test('U10 — sans fiche antérieure, la mortalité se rapporte à l effectif initial de la bande', () async {
      await bande('b1', initial: 480);
      await journee('j1', lot: 'b1', date: DateTime(2026, 7, 13), mort: 6);

      final d = await depot.charger(du: du, au: au);

      expect(IndicateursElevage.taux(d.indicateurs.mortaliteHebdo), '1.3 %');
    });

    /// 🔴→✅ Ticket U10 — sans fiche antérieure ni effectif initial, l'effectif de début est nul : « — ».
    test('U10 — sans effectif de début, la mortalité est « — »', () async {
      await bande('b1');
      await journee('j1', lot: 'b1', date: DateTime(2026, 7, 13), mort: 6);

      final d = await depot.charger(du: du, au: au);

      expect(IndicateursElevage.taux(d.indicateurs.mortaliteHebdo), '—');
    });

    /// 🔴→✅ Ticket U10 — `vente_montant` descend au poste (schéma v45) : le CA est la somme des montants, « 0 »
    /// sans montant, comme le web (`(float) $entries->sum('vente_montant')`).
    test('⚠️ U10 — le CA du lot est la somme des montants de vente', () async {
      await bande('b1');
      await journee(
        'j1',
        lot: 'b1',
        date: DateTime(2026, 7, 13),
        vente: 20,
        venteMontant: 60000,
      );
      await journee('j2', lot: 'b1', date: DateTime(2026, 7, 14), vente: 2);

      final d = await depot.charger(du: du, au: au);

      expect(d.indicateurs.chiffreAffaires, 60000);
    });

    /// 🔴→✅ Ticket U10 — le filtre « Lot / Souche » restreint indicateurs et tableaux à la bande choisie ; ses
    /// options sont les bandes ACTIVES, par code.
    test('⚠️ U10 — le filtre Lot / Souche restreint la sélection', () async {
      await bande('b1');
      await bande('b2', code: 'Pondeuses Lot P0');
      await journee('j1', lot: 'b1', date: DateTime(2026, 7, 13), ponteTotal: 300);
      await journee('j2', lot: 'b2', date: DateTime(2026, 7, 13), ponteTotal: 200);

      final toutes = await depot.charger(du: du, au: au);
      final p1 = await depot.charger(du: du, au: au, lot: uuid('b1'));

      expect(toutes.indicateurs.productionTotale, 500);
      expect(p1.indicateurs.productionTotale, 300);
      expect(p1.elevageT1.map((l) => l.cellules[1]), ['Pondeuses Lot P1']);
      expect(toutes.bandesElevage.map((b) => b.code), [
        'Pondeuses Lot P0',
        'Pondeuses Lot P1',
      ]);
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

    /// Ticket U12b — le classeur du hub porte les lignes du CSV du web, sans titre ajouté, sous le nom du web.
    test('U12b — classeur du hub : lignes du CSV, nom du web, jamais d écrasement', () {
      const classeur = ClasseurRapport(
        fichier: 'dettes-{jour}.xlsx',
        onglet: 'État des Dettes Fournisseurs',
        lignes: [
          ['Fournisseur', 'Montant Dû', 'Échéance'],
          ['Provenderie du Plateau', '185000', '25/07/2026'],
        ],
      );

      final octets = ExportTableur.construireTableau(classeur);
      expect(octets.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      expect(ExportTableur.nomClasseur(classeur, maintenant), 'dettes-2026-08-25.xlsx');

      // Deux éditions le même jour : « nom (1).xlsx », comme un second téléchargement du navigateur.
      // Chemins construits avec le séparateur de la plateforme (`p.join`), comme l'application : « / » ou « \\ ».
      String d(String nom) => p.join('/d', nom);
      final pris = {d('dettes-2026-08-25.xlsx'), d('dettes-2026-08-25 (1).xlsx')};
      expect(
        ExportTableur.cheminLibre('/d', 'dettes-2026-08-25.xlsx', pris.contains),
        d('dettes-2026-08-25 (2).xlsx'),
      );
      expect(
        ExportTableur.cheminLibre('/d', 'creances-2026-08-25.xlsx', pris.contains),
        d('creances-2026-08-25.xlsx'),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('écran', () {
    /// Éditeurs de test : ils retiennent le document sans rien imprimer.
    late List<DocumentOfficiel> imprimes;
    late List<ClasseurRapport> enregistres;

    setUp(() {
      imprimes = [];
      enregistres = [];
    });

    Future<void> afficher(WidgetTester tester, {bool peutExporter = true}) async {
      addTearDown(ToastAgri.toutRetirer);
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
            peutExporter: peutExporter,
            maintenant: () => maintenant,
            imprimer: (doc, _) async {
              imprimes.add(doc);
              return null;
            },
            enregistrer: (classeur, _) async {
              enregistres.add(classeur);
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

      expect(find.byKey(const Key('tableau-recettes')), findsOneWidget);
      expect(find.byKey(const Key('tableau-depenses')), findsOneWidget);
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
      // Ticket U12b — titre et sous-titre du PDF du WEB : `'État des Créances Clients'`, la période du hub.
      expect(imprimes.last.titre, 'État des Créances Clients');
      expect(imprimes.last.sousTitre, '01/08/2026 au 31/08/2026');
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
              dueDate: Value(DateTime(2026, 8, 10)),
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
      // `exports/creances.blade.php` : le reste dû suivi de « FCFA ».
      expect(ligne.cellules, ['Client X', '5 000 FCFA', '10/08/2026']);
      expect(ligne.cellules.join(), isNot(contains('Lecture seule')));
    });

    /// 🔴→✅ Ticket U12b — comme au web, seul le HUB porte la période et l'export : aucun onglet ne garde l'en-tête de la
    /// maquette (titre, légende, paire « PDF » / « Excel »).
    testWidgets('⚠️ U12b — aucun onglet ne porte l en-tête ni les boutons de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      for (final (onglet, titreMaquette) in const [
        ('Recettes et Dépenses', 'État des Recettes et Dépenses'),
        ('État de Trésorerie', 'Position de trésorerie consolidée.'),
        ('Créances Clients', 'État des Créances Clients'),
        ('Dettes Fournisseurs', 'État des Dettes Fournisseurs'),
        ('Rapport de Stocks', 'Rapport de Stocks — Synthèse'),
      ]) {
        await ouvrir(tester, onglet);
        expect(find.byKey(const Key('hub-export-pdf')), findsOneWidget, reason: onglet);
        expect(find.byKey(const Key('rapport-export-pdf')), findsNothing, reason: onglet);
        expect(find.byKey(const Key('rapport-export-excel')), findsNothing, reason: onglet);
        expect(find.text(titreMaquette), findsNothing, reason: onglet);
        expect(find.text('PDF'), findsNothing, reason: onglet);
      }
    });

    /// 🔴→✅ Ticket U12b — `@can('export-rapports')` : sans le droit, ni « Exporter PDF » ni « Exporter Excel ».
    testWidgets('⚠️⚠️ U12b — sans export-rapports, aucun bouton d export', (tester) async {
      await afficher(tester, peutExporter: false);

      expect(find.byKey(const Key('hub-export-pdf')), findsNothing);
      expect(find.byKey(const Key('hub-export-excel')), findsNothing);
      expect(find.text('Exporter PDF'), findsNothing);
      // La période reste, comme au web.
      expect(find.byKey(const Key('hub-filter-du')), findsOneWidget);
    });

    /// 🔴→✅ Ticket U12b — le CSV du web en classeur : mêmes lignes (en-tête compris), nom du web en `.xlsx`.
    testWidgets('⚠️⚠️ U12b — le classeur porte les lignes du CSV et le nom du web', (tester) async {
      await vente('v1', date: DateTime(2026, 8, 3), total: 12000.5, client: 'Bar Le Palmier');
      await depense('d1', date: DateTime(2026, 8, 4), montant: 3000, libelle: 'Carburant, groupe');

      await afficher(tester);
      await tester.tap(find.byKey(const Key('hub-export-excel')));
      await tester.pumpAndSettle();

      final c = enregistres.single;
      expect(ExportTableur.nomClasseur(c, maintenant), 'recettes-depenses-2026-08-25.xlsx');
      expect(c.lignes, [
        ['Type', 'Date', 'Libellé', 'Montant'],
        ['Recette', '03/08/2026', 'Vente — Bar Le Palmier', '12000.5'],
        ['Dépense', '04/08/2026', 'Carburant, groupe', '-3000'],
      ]);

      await ouvrir(tester, 'Rapport de Stocks');
      await tester.tap(find.byKey(const Key('hub-export-excel')));
      await tester.pumpAndSettle();
      expect(ExportTableur.nomClasseur(enregistres.last, maintenant), 'rapport-stocks-2026-08-25.xlsx');
      expect(enregistres.last.lignes.first, ['Catégorie', 'Valeur Stock', 'Sous Seuil']);
      // Les toasts du chemin se retirent d'eux-mêmes (3,5 s, comme au web).
      await tester.pump(ToastAgri.duree);
    });

    /// 🔴→✅ Ticket U12b — le PDF de chaque onglet est celui du web (`exports/<rapport>.blade.php`).
    testWidgets('⚠️ U12b — titre, sous-titre et colonnes des PDF sont ceux du web', (tester) async {
      await afficher(tester);

      final attendus = <String, (String, String, List<String>, String)>{
        'Recettes et Dépenses': (
          'État des Recettes et Dépenses',
          '01/08/2026 au 31/08/2026',
          [],
          'recettes-depenses-2026-08-25.pdf',
        ),
        'État de Trésorerie': (
          'État de Trésorerie',
          '01/08/2026 au 31/08/2026',
          ['Date', 'Solde Caisse', 'Solde Banque', 'Solde Total'],
          'tresorerie-2026-08-25.pdf',
        ),
        'Créances Clients': (
          'État des Créances Clients',
          '01/08/2026 au 31/08/2026',
          ['Client', 'Montant Dû', 'Échéance'],
          'creances-2026-08-25.pdf',
        ),
        'Dettes Fournisseurs': (
          'État des Dettes Fournisseurs',
          '01/08/2026 au 31/08/2026',
          ['Fournisseur', 'Montant Dû', 'Échéance'],
          'dettes-2026-08-25.pdf',
        ),
        'Rapport de Stocks': (
          'Rapport de Stocks — Synthèse',
          'État au 25/08/2026',
          ['Catégorie', 'Valeur Stock', 'Sous Seuil'],
          'rapport-stocks-2026-08-25.pdf',
        ),
      };
      for (final MapEntry(key: onglet, value: (titre, sousTitre, entetes, fichier)) in attendus.entries) {
        await ouvrir(tester, onglet);
        await tester.tap(find.byKey(const Key('hub-export-pdf')));
        await tester.pumpAndSettle();
        final doc = imprimes.last;
        expect(doc.titre, titre, reason: onglet);
        expect(doc.sousTitre, sousTitre, reason: onglet);
        expect(doc.entetes, entetes, reason: onglet);
        expect(DocumentOfficiel.nomPdf(doc, maintenant), fichier, reason: onglet);
      }
      // Recettes et Dépenses : les trois totaux en tête, puis les deux sections, chacune avec sa ligne vide.
      final rd = imprimes.first.lignes;
      expect((rd[0] as EnteteDocument).cellules, ['Total Recettes', 'Total Dépenses', 'Solde Net']);
      expect((rd[1] as DonneesDocument).cellules, ['0 FCFA', '0 FCFA', '0 FCFA']);
      expect([for (final l in rd.whereType<BandeDocument>()) l.libelle], ['Recettes', 'Dépenses']);
      expect(
        [for (final l in rd.whereType<DonneesDocument>().skip(1)) l.cellules.single],
        ['Aucune recette sur la période.', 'Aucune dépense sur la période.'],
      );
    });

    testWidgets('le classeur annonce son chemin', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('hub-export-excel')));
      await tester.pumpAndSettle();

      expect(enregistres, hasLength(1));
      expect(
        find.textContaining(r'C:\Documents\AgriERP\rapport.xlsx'),
        findsOneWidget,
      );      await tester.pump(ToastAgri.duree);
    });

    /// 🔴→✅ Ticket U12b — la Trésorerie du Blade : une ligne par jour, « Solde Total » en gras, « Lecture seule » avec
    /// son info-bulle ; plus de mention « dernier tirage ».
    testWidgets('⚠️ U12b — la trésorerie montre la série du grand livre', (tester) async {
      await compte('c531', '531', 5);
      await compte('c701', '701', 7);
      await ecriture('e1', DateTime(2026, 8, 3), [('c531', 420000, 0), ('c701', 0, 420000)]);
      await ecriture('e2', DateTime(2026, 8, 5), [('c531', 0, 20000), ('c701', 20000, 0)]);

      await afficher(tester);
      await ouvrir(tester, 'État de Trésorerie');

      expect(find.byKey(const Key('tableau-tresorerie-ligne-0')), findsOneWidget);
      expect(find.byKey(const Key('tableau-tresorerie-ligne-1')), findsOneWidget);
      expect(find.text('05/08/2026'), findsOneWidget);
      expect(find.text('400 000'), findsNWidgets(2), reason: 'caisse et total');
      expect(find.text('Lecture seule'), findsNWidgets(2));
      expect(find.byTooltip(RapportsExportsScreen.bulleEcritures), findsNWidgets(2));
      expect(find.textContaining('dernier tirage'), findsNothing);
      expect(find.byKey(const Key('mention-poste')), findsNothing);
      // Ni recherche ni carte, comme le Blade.
      expect(find.byKey(const Key('recherche-tresorerie')), findsNothing);
    });

    testWidgets('U12b — sans écriture, la trésorerie le dit comme le web', (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'État de Trésorerie');

      expect(find.text('Aucun mouvement de trésorerie sur la période.'), findsOneWidget);
    });

    /// 🔴→✅ Ticket U12b — `stocks-synth.blade.php` : pastille rouge « Sous Seuil », mentions sous la valeur.
    testWidgets('U12b — stocks : pastille sous seuil et mentions du Blade', (tester) async {
      await categorie('c1', 'Aliments & Provendes');
      await produit('p1', nom: 'Maïs', categorie: uuid('c1'), stock: -2, seuil: 5);
      await produit('p2', nom: 'Son', categorie: uuid('c1'), stock: 8, seuil: 5);

      await afficher(tester);
      await ouvrir(tester, 'Rapport de Stocks');

      expect(find.byKey(const Key('sous-seuil-Aliments & Provendes')), findsOneWidget);
      expect(find.text('(1 produit(s) en stock négatif, retenus à zéro)'), findsOneWidget);
      expect(find.text('(1 produit(s) jamais achetés, non valorisés)'), findsOneWidget);
      expect(find.text('0 FCFA'), findsOneWidget);
    });

    /// 🔴→✅ Ticket U12b — changer d'onglet monte un autre composant au web : la recherche part vide.
    testWidgets('U12b — changer d onglet vide la recherche, comme au web', (tester) async {
      await categorie('c1', 'Aliments & Provendes');
      await categorie('c2', 'Produits vétérinaires');
      await produit('p1', nom: 'Maïs', categorie: uuid('c1'), stock: 5);
      await produit('p2', nom: 'Vaccin', categorie: uuid('c2'), stock: 5);

      await afficher(tester);
      await ouvrir(tester, 'Rapport de Stocks');
      await tester.enterText(find.byKey(const Key('recherche-stocks')), 'aliments');
      await tester.pumpAndSettle();
      expect(find.text('Produits vétérinaires'), findsNothing);

      await ouvrir(tester, 'Dettes Fournisseurs');
      await ouvrir(tester, 'Rapport de Stocks');
      expect(find.text('Produits vétérinaires'), findsOneWidget);
      final champ = tester.widget<TextField>(find.byKey(const Key('recherche-stocks')));
      expect(champ.controller!.text, isEmpty);
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

    /// 🔴→✅ Ticket U10 — le filtre « Lot / Souche » du Blade : « Tous » puis les bandes actives ; choisir une bande
    /// restreint indicateurs et tableaux (et le document édité).
    testWidgets('⚠️ U10 — le filtre Lot / Souche restreint le rapport élevage', (tester) async {
      await bande('b1');
      await bande('b2', code: 'Pondeuses Lot P2');
      await journee('j1', lot: 'b1', date: DateTime(maintenant.year, maintenant.month, 1), ponteTotal: 300);
      await journee('j2', lot: 'b2', date: DateTime(maintenant.year, maintenant.month, 1), ponteTotal: 200);
      await afficher(tester);
      await ouvrir(tester, 'Rapport Élevage');

      expect(find.text('Lot / Souche : Tous'), findsOneWidget);
      expect(find.text('500'), findsWidgets, reason: 'Production Totale, toutes bandes');

      await tester.tap(find.byKey(const Key('elevage-lot')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pondeuses Lot P2').last);
      await tester.pumpAndSettle();

      expect(find.text('200'), findsWidgets);
      expect(find.text('500'), findsNothing);
      await tester.tap(find.byKey(const Key('hub-export-pdf')));
      await tester.pumpAndSettle();
      final lignes = imprimes.single.lignes.whereType<DonneesDocument>().toList();
      expect(lignes.every((l) => l.cellules.length < 2 || l.cellules[1] == 'Pondeuses Lot P2'), isTrue);
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

      // Ticket U10 — les trois titres du PDF du web (`exports/elevage-synth.blade.php`).
      expect(bandes, [
        'Tableau 1 — Recensement',
        'Tableau 2 — Mouvements, Traitements & Ventes',
        'Tableau 3 — Suivi de la Ponte',
      ]);
    });

    /// 🔴→✅ Ticket U11 — l'onglet du Blade : ni en-tête de la maquette, ni « Filtrer la Période » et sa modale, ni
    /// paire PDF / Excel propre ; il commence par son filtre « Lot / Souche ». La période et l'export restent ceux du
    /// hub, comme au web.
    testWidgets('⚠️ U11 — l onglet Rapport Élevage est celui du Blade, sans « Filtrer la Période »', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Rapport Élevage');

      expect(find.text('Filtrer la Période'), findsNothing);
      expect(find.byKey(const Key('rapport-export-pdf')), findsNothing);
      expect(find.byKey(const Key('rapport-export-excel')), findsNothing);
      expect(find.text('Rapport Élevage — Synthèse Détaillée'), findsNothing);
      expect(find.text('Lot / Souche : Tous'), findsOneWidget);
      // Le filtre précède les indicateurs.
      expect(
        tester.getTopLeft(find.byKey(const Key('elevage-lot'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('kpi-Production Totale (Œufs)')))
              .dy,
        ),
      );

      // L'export passe par le hub, comme au web (`exportPdf()` → `ElevageSynth::exportReport()`).
      await tester.tap(find.byKey(const Key('hub-export-pdf')));
      await tester.pumpAndSettle();
      expect(imprimes.single.titre, 'Rapport Élevage — Synthèse Détaillée');
    });

    /// 🔴→✅ Ticket U11 — en-tête et barre du hub web (`rapports-exports-hub.blade.php`) ; période par défaut du 1er
    /// au DERNIER jour du mois (`RapportsExportsHub::mount()`).
    testWidgets('U11 — en-tête, boutons et période du hub sont ceux du web', (
      tester,
    ) async {
      await afficher(tester);

      expect(
        find.text(
          'États financiers et opérationnels de la Ferme École OLOUWACHEGOUN.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Centre de décision'), findsNothing);
      expect(find.text('Exporter Excel'), findsOneWidget);
      // `maintenant` = 25/08/2026 : du 01/08/2026 au 31/08/2026.
      expect(
        find.descendant(
          of: find.byKey(const Key('hub-filter-du')),
          matching: find.text('01/08/2026'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('hub-filter-au')),
          matching: find.text('31/08/2026'),
        ),
        findsOneWidget,
      );
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

      expect(find.text('Aucune dette sur la période.'), findsOneWidget);
      await ouvrir(tester, 'Créances Clients');
      expect(find.text('Aucune créance sur la période.'), findsOneWidget);
      await ouvrir(tester, 'Rapport de Stocks');
      expect(find.text('Aucune catégorie active.'), findsOneWidget);
      await ouvrir(tester, 'Recettes et Dépenses');
      expect(find.text('Aucune recette sur la période.'), findsOneWidget);
      expect(find.text('Aucune dépense sur la période.'), findsOneWidget);
    });
  });
}
