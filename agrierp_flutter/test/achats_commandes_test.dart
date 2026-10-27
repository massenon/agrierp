import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/achats/achats_commandes_screen.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.45 — HUB ACHATS & COMMANDES (`achats-commandes.html`).
///
/// ⚠️⚠️ **LE POSTE ENREGISTRE UNE INTENTION, LE SERVEUR APPLIQUE LES EFFETS.**
/// Un achat porte cinq effets — pièce et lignes, entrée en stock avec recalcul
/// du PMP, décaissement, dette fournisseur si le règlement est partiel,
/// écriture SYSCOHADA. AUCUN n'est joué au poste : `RecordPurchaseAction` les
/// rejoue tous à la réception. Décrémenter un stock local ferait diverger deux
/// valorisations.
void main() {
  late AppDatabase db;
  late AchatsRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = AchatsRepository(database: db, identifiantPoste: 'poste-test');
  });

  tearDown(() async => db.close());

  Future<void> fournisseur(String cle, String nom, {String? categorie}) => db
      .into(db.suppliers)
      .insert(
        SuppliersCompanion.insert(
          id: uuid(cle),
          name: nom,
          category: Value(categorie),
        ),
      );

  Future<void> produit(String cle, String nom) => db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: uuid(cle),
          sku: 'SKU-$cle',
          name: nom,
          unit: 'sac',
          pricingMode: 'fourchette',
        ),
      );

  Future<void> compte(String cle, String libelle) => db
      .into(db.treasuryAccounts)
      .insert(
        TreasuryAccountsCompanion.insert(
          id: uuid(cle),
          label: libelle,
          accountCode: const Value('531'),
          type: const Value('caisse'),
        ),
      );

  Future<void> achatServeur(
    String cle, {
    required String cleFournisseur,
    required double total,
    bool dette = false,
    double regle = 0,
    String nomFournisseur = 'Provenderie du Plateau',
    String? categorie = 'Aliments',
    bool avecDetteServie = true,
  }) async {
    // ⚠️ F0.77 : comme le tirage réel, l'ACHAT est servi SANS `amount_paid` (colonne à son
    // défaut, 0) ; le règlement partiel ne se lit que sur la DETTE servie à côté.
    await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            id: uuid(cle),
            deviceId: 'serveur',
            updatedAt: DateTime.now(),
            syncStatus: const Value(SyncStatus.synced),
            supplierId: uuid(cleFournisseur),
            supplierName: Value(nomFournisseur),
            supplierCategory: Value(categorie),
            paymentMode: 'especes',
            total: total,
            hasDebt: Value(dette),
            purchaseDate: DateTime.now(),
          ),
        );
    if (dette && avecDetteServie) {
      await db
          .into(db.payables)
          .insert(
            PayablesCompanion.insert(
              id: uuid('d$cle'),
              supplierId: uuid(cleFournisseur),
              purchaseId: Value(uuid(cle)),
              amount: total,
              amountPaid: Value(regle),
            ),
          );
    }
  }

  /// Achat saisi ICI et pas encore parti.
  ///
  /// ⚠️ `hasDebt` reste à `false` — sa valeur par défaut : le serveur n'a pas
  /// encore statué. C'est précisément le piège que le ticket F0.55 verrouille.
  Future<void> achatLocal(
    String cle, {
    required String cleFournisseur,
    required double total,
  }) => db
      .into(db.purchases)
      .insert(
        PurchasesCompanion.insert(
          id: uuid(cle),
          deviceId: 'poste-test',
          updatedAt: DateTime.now(),
          syncStatus: const Value(SyncStatus.pending),
          supplierId: uuid(cleFournisseur),
          paymentMode: 'especes',
          total: total,
          purchaseDate: DateTime.now(),
        ),
      );

  Future<void> bonCommande(String cle, {required double estime}) => db
      .into(db.purchaseOrders)
      .insert(
        PurchaseOrdersCompanion.insert(
          id: uuid(cle),
          deviceId: 'serveur',
          updatedAt: DateTime.now(),
          syncStatus: const Value(SyncStatus.synced),
          supplierName: const Value('Provenderie du Plateau'),
          expectedDeliveryDate: Value(
            DateTime.now().add(const Duration(days: 7)),
          ),
          status: const Value('envoye'),
          createdAt: Value(DateTime.now()),
          estimatedTotal: Value(estime),
        ),
      );

  Future<void> jeuComplet() async {
    await fournisseur('f1', 'Provenderie du Plateau', categorie: 'Aliments');
    await produit('p1', 'Aliment ponte 25kg');
    await compte('c1', 'Caisse Physique');
  }

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(home: AchatsCommandesScreen(depot: depot)),
    );
    // Un pump() laisse _charger() compléter et retire le CircularProgressIndicator
    // (animation infinie) AVANT pumpAndSettle — sinon le spinner tourne indéfiniment
    // et provoque un timeout avec 6000+ assertions !semantics.parentDataDirty.
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// ⚠️ LA MAQUETTE N'EN PRÉSÉLECTIONNE AUCUN : ses deux listes ouvrent sur
  /// « Choisir le fournisseur… » et « Choisir un produit… ». Le test doit donc
  /// choisir, comme l'acheteur.
  Future<void> choisir(WidgetTester tester, String cle, String libelle) async {
    await tester.tap(find.byKey(Key('liste-$cle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-achats-$onglet')));
    await tester.pumpAndSettle();
  }

  group('dépôt', () {
    /// ⚠️⚠️ LE CŒUR DU TICKET : l'achat est écrit LOCALEMENT, en attente.
    test('⚠️⚠️ un achat saisi part en attente de synchronisation', () async {
      await jeuComplet();
      final produits = (await depot.charger()).produits;

      final id = await depot.enregistrer(
        fournisseurId: uuid('f1'),
        lignes: [
          LigneSaisieAchat(
            produit: produits.single,
            quantite: 20,
            prixUnitaire: 5000,
          ),
        ],
        modePaiement: 'especes',
        compteId: uuid('c1'),
        montantPaye: 100000,
      );

      final achat = await (db.select(
        db.purchases,
      )..where((t) => t.id.equals(id))).getSingle();

      expect(achat.syncStatus, SyncStatus.pending);
      expect(achat.deviceId, 'poste-test');
      expect(achat.total, 100000);
      expect(achat.supplierName, 'Provenderie du Plateau');
      expect((await depot.lignesDe(id)).single.qty, 20);
    });

    /// ⚠️⚠️ AUCUN DES CINQ EFFETS N'EST JOUÉ AU POSTE. Le stock du produit ne
    /// bouge pas : le serveur seul entre la marchandise et recalcule le PMP.
    test(
      '⚠️⚠️ le stock local ne bouge pas — le serveur applique les effets',
      () async {
        await jeuComplet();
        final produits = (await depot.charger()).produits;

        await depot.enregistrer(
          fournisseurId: uuid('f1'),
          lignes: [
            LigneSaisieAchat(
              produit: produits.single,
              quantite: 20,
              prixUnitaire: 5000,
            ),
          ],
          modePaiement: 'especes',
          compteId: uuid('c1'),
          montantPaye: 100000,
        );

        final produitApres = await (db.select(
          db.products,
        )..where((t) => t.id.equals(uuid('p1')))).getSingle();

        expect(produitApres.stockQty, 0);
      },
    );

    /// ⚠️ On ne règle jamais plus que le total : le serveur plafonne aussi,
    /// mais un envoi absurde serait rejeté pour rien.
    test('⚠️ le montant payé est plafonné au total', () async {
      await jeuComplet();
      final produits = (await depot.charger()).produits;

      final id = await depot.enregistrer(
        fournisseurId: uuid('f1'),
        lignes: [
          LigneSaisieAchat(
            produit: produits.single,
            quantite: 2,
            prixUnitaire: 1000,
          ),
        ],
        modePaiement: 'especes',
        compteId: uuid('c1'),
        montantPaye: 999999,
      );

      final achat = await (db.select(
        db.purchases,
      )..where((t) => t.id.equals(id))).getSingle();

      expect(achat.amountPaid, 2000);
    });

    test('un achat sans ligne est refusé', () async {
      await jeuComplet();

      expect(
        () => depot.enregistrer(
          fournisseurId: uuid('f1'),
          lignes: const [],
          modePaiement: 'especes',
          compteId: uuid('c1'),
          montantPaye: 0,
        ),
        throwsArgumentError,
      );
    });

    test('les achats en attente sont comptés', () async {
      await jeuComplet();
      await achatServeur('a1', cleFournisseur: 'f1', total: 50000);
      final produits = (await depot.charger()).produits;

      await depot.enregistrer(
        fournisseurId: uuid('f1'),
        lignes: [
          LigneSaisieAchat(
            produit: produits.single,
            quantite: 1,
            prixUnitaire: 3000,
          ),
        ],
        modePaiement: 'especes',
        compteId: uuid('c1'),
        montantPaye: 3000,
      );

      expect((await depot.charger()).enAttente, 1);
    });
  });

  group('cartes de la maquette (ticket F0.55)', () {
    /// ⚠️ La ferme a dépensé l'argent au moment de l'achat, pas au moment de la
    /// synchronisation.
    test(
      '⚠️ les dépenses totales incluent un achat pas encore envoyé',
      () async {
        await fournisseur('f1', 'Provenderie du Plateau');
        await achatServeur('a1', cleFournisseur: 'f1', total: 500000);
        await achatLocal('a2', cleFournisseur: 'f1', total: 285500);

        final d = await depot.charger();

        expect(d.depensesTotales, 785500);
      },
    );

    /// ⚠️⚠️ **LE PIÈGE DE CE TICKET.** `hasDebt` est calculé par le SERVEUR et
    /// vaut `false` par défaut : un achat saisi ici et pas encore parti le
    /// porte sans que personne n'ait statué sur son règlement. Le compter comme
    /// réglé afficherait un « payé » que rien n'appuie — et le chiffre se
    /// corrigerait tout seul au tirage suivant.
    test('⚠️⚠️ un achat non envoyé n est pas compté réglé', () async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achatLocal('a1', cleFournisseur: 'f1', total: 60000);

      final d = await depot.charger();

      expect(d.achatsRegles, 0);
      // …et il ne compte pas non plus comme dette : le serveur n'a rien dit.
      expect(d.dettesEnCours, 0);
    });

    test('les achats réglés sont ceux que le serveur dit sans dette', () async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achatServeur('a1', cleFournisseur: 'f1', total: 100000);
      await achatServeur('a2', cleFournisseur: 'f1', total: 200000);
      await achatServeur(
        'a3',
        cleFournisseur: 'f1',
        total: 300000,
        dette: true,
      );

      final d = await depot.charger();

      expect(d.achatsRegles, 2);
    });

    /// ⚠️ Le reste dû se CALCULE (`total − amountPaid`), il n'est pas stocké.
    test(
      '⚠️ la dette en cours est le reste dû, pas le montant facturé',
      () async {
        await fournisseur('f1', 'Provenderie du Plateau');
        await achatServeur(
          'a1',
          cleFournisseur: 'f1',
          total: 100000,
          regle: 37500,
          dette: true,
        );

        final d = await depot.charger();

        expect(d.dettesEnCours, 62500);
      },
    );

    /// ⚠️⚠️ F0.77 — DONNÉE ABSENTE = TIRET, JAMAIS 0 NI LE TOTAL. Un achat endetté dont la
    /// dette n'a pas été servie a un reste dû INCONNU.
    test(
      '⚠️⚠️ un achat endetté sans dette servie : reste dû inconnu (null)',
      () async {
        await fournisseur('f1', 'Provenderie du Plateau');
        await achatServeur(
          'a1',
          cleFournisseur: 'f1',
          total: 100000,
          regle: 37500,
          dette: true,
          avecDetteServie: false,
        );

        final d = await depot.charger();

        expect(d.dettesEnCours, isNull);
        expect(d.achatsEndettesSansDette, 1);
      },
    );

    testWidgets(
      '⚠️ la carte « Dettes en Cours » affiche un tiret quand le reste dû '
      'est inconnu',
      (tester) async {
        await fournisseur('f1', 'Provenderie du Plateau');
        await achatServeur(
          'a1',
          cleFournisseur: 'f1',
          total: 100000,
          dette: true,
          avecDetteServie: false,
        );

        await afficher(tester);
        await ouvrir(tester, "Liste d'Achats");

        final carte = find.byKey(const Key('kpi-achats-dettes'));
        expect(
          find.descendant(of: carte, matching: find.text('—')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: carte, matching: find.text('100 000')),
          findsNothing,
        );
      },
    );

    /// ⚠️ F0.74 : `returned_at` descend et le poste acquitte ses retours — la carte est
    /// CALCULABLE ; sans aucun retour, c'est un vrai zéro. Ticket U8 : elle compte des LIGNES
    /// de retour comme le web (voir `retour_fournisseur_poste_test` pour le recalcul SQL
    /// indépendant, `retours_achats_sync_test` pour les lignes servies) — ici, un achat retourné
    /// dont aucune ligne de retour n'est encore servie compte ses lignes d'achat.
    test('⚠️⚠️ « Écarts / Retours » est calculé : zéro sans retour, le compte '
        'sinon', () async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achatServeur('a1', cleFournisseur: 'f1', total: 100000);
      for (var i = 0; i < 2; i++) {
        await db.into(db.purchaseLines).insert(
          PurchaseLinesCompanion.insert(
            id: uuid('la1-$i'),
            purchaseId: uuid('a1'),
            productId: uuid('p1'),
            qty: 1,
            unitPrice: 50000,
          ),
        );
      }

      expect((await depot.charger()).ecartsEtRetours, 0);

      await (db.update(db.purchases)..where((t) => t.id.equals(uuid('a1'))))
          .write(PurchasesCompanion(returnedAt: Value(DateTime(2026, 10, 5))));

      expect((await depot.charger()).ecartsEtRetours, 2);
    });

    testWidgets('la liste d achats porte ses quatre cartes', (tester) async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achatServeur(
        'a1',
        cleFournisseur: 'f1',
        total: 100000,
        regle: 37500,
        dette: true,
      );

      await afficher(tester);
      await ouvrir(tester, "Liste d'Achats");

      for (final libelle in [
        'DÉPENSES TOTALES',
        'ACHATS RÉGLÉS',
        'DETTES EN COURS',
        'ÉCARTS / RETOURS',
      ]) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }

      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-achats-dettes')),
          matching: find.text('62 500'),
        ),
        findsOneWidget,
      );

      // F0.74 : la carte est calculable, elle n'est plus un tiret — cherché DANS sa carte.
      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-achats-ecarts')),
          matching: find.text('—'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-achats-ecarts')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
    });
  });

  group('écran', () {
    /// ⚠️⚠️ **LE NOMBRE DE CARTES, ONGLET PAR ONGLET** (ticket F0.54). Chaque
    /// onglet du hub est une page distincte de la maquette : le contrôle se fait
    /// donc page par page, sans arbitrage sur la répartition.
    testWidgets('⚠️⚠️ chaque onglet rend le nombre de cartes de sa page', (
      tester,
    ) async {
      await afficher(tester);

      const pages = <String, String>{
        'Enregistrer un Achat': 'enregistrer-achat.html',
        "Liste d'Achats": 'liste-achats.html',
        'Bons de Commande': 'bons-commande.html',
      };

      for (final onglet in pages.keys) {
        await ouvrir(tester, onglet);
        expect(
          find.byType(CarteKpi),
          findsNWidgets(cartesAttendues(pages[onglet]!)),
          reason: onglet,
        );
      }
    });

    testWidgets('⚠️ les trois onglets du hub sont là, dans son ordre', (
      tester,
    ) async {
      await afficher(tester);

      for (final onglet in [
        'Enregistrer un Achat',
        "Liste d'Achats",
        'Bons de Commande',
      ]) {
        expect(find.text(onglet), findsWidgets, reason: onglet);
      }
    });

    /// ⚠️ Les libellés sans accent sont ceux de la maquette : les accentuer
    /// serait harmoniser en silence une incohérence du template.
    testWidgets('⚠️ la saisie porte les étiquettes de la maquette', (
      tester,
    ) async {
      await jeuComplet();
      await afficher(tester);

      for (final etiquette in [
        'SELECTIONNER FOURNISSEUR',
        'AJOUTER UN ARTICLE',
        'PRODUIT / ARTICLE',
        'QUANTITE',
        'PRIX UNITAIRE',
        'MODE DE PAIEMENT',
        'COMPTE DEBITE',
        'MONTANT PAYE (FCFA)',
      ]) {
        expect(find.text(etiquette), findsOneWidget, reason: etiquette);
      }

      expect(find.text("Ajouter au bon d'achat"), findsOneWidget);
      expect(find.text("Enregistrer l'Achat"), findsOneWidget);
    });

    testWidgets('le bon d achat porte les quatre colonnes de la maquette', (
      tester,
    ) async {
      await jeuComplet();
      await afficher(tester);

      for (final colonne in ['DESIGNATION', 'QTE', 'P.U', 'TOTAL']) {
        expect(find.text(colonne), findsWidgets, reason: colonne);
      }
    });

    testWidgets('un article ajouté apparaît au bon et dans le total', (
      tester,
    ) async {
      await jeuComplet();
      await afficher(tester);

      await choisir(tester, 'fournisseur', 'Provenderie du Plateau');
      await choisir(tester, 'produit', 'Aliment ponte 25kg');

      await tester.enterText(find.byKey(const Key('champ-quantite')), '20');
      await tester.enterText(
        find.byKey(const Key('champ-prix-unitaire')),
        '5000',
      );
      await tester.tap(find.byKey(const Key('ajouter-au-bon')));
      await tester.pumpAndSettle();

      expect(find.text('Aliment ponte 25kg'), findsWidgets);
      expect(find.text('100 000 FCFA'), findsOneWidget);
    });

    testWidgets('⚠️ un bon vide refuse l enregistrement, avec son motif', (
      tester,
    ) async {
      await jeuComplet();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('enregistrer-achat')));
      await tester.pumpAndSettle();

      expect(
        find.text('Choisissez le fournisseur de cet achat.'),
        findsOneWidget,
      );

      await choisir(tester, 'fournisseur', 'Provenderie du Plateau');
      await tester.tap(find.byKey(const Key('enregistrer-achat')));
      await tester.pumpAndSettle();

      expect(
        find.text("Ajoutez au moins un article au bon d'achat."),
        findsOneWidget,
      );
    });

    /// ⚠️⚠️ L'ÉCRAN DIT QUE LA FERME NE CONNAÎT PAS ENCORE CET ACHAT.
    testWidgets('⚠️⚠️ un achat enregistré est annoncé en attente d envoi', (
      tester,
    ) async {
      await jeuComplet();
      await afficher(tester);

      await choisir(tester, 'fournisseur', 'Provenderie du Plateau');
      await choisir(tester, 'produit', 'Aliment ponte 25kg');

      await tester.enterText(find.byKey(const Key('champ-quantite')), '2');
      await tester.enterText(
        find.byKey(const Key('champ-prix-unitaire')),
        '1000',
      );
      await tester.tap(find.byKey(const Key('ajouter-au-bon')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('enregistrer-achat')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('il partira à la prochaine synchronisation'),
        findsOneWidget,
      );
      expect(find.text('En attente de synchronisation'), findsOneWidget);
    });

    testWidgets('la liste porte les sept colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, "Liste d'Achats");

      for (final colonne in [
        'RÉFÉRENCE ACHAT',
        'DATE',
        'FOURNISSEUR',
        'CATÉGORIE',
        'MONTANT TOTAL',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    /// ⚠️ Le statut vient du SERVEUR : deux règles donneraient deux listes.
    testWidgets('⚠️ un achat descendu porte le statut calculé par le serveur', (
      tester,
    ) async {
      await fournisseur('f1', 'Véto-Santé Bénin', categorie: 'Vétérinaire');
      await achatServeur(
        'a1',
        cleFournisseur: 'f1',
        total: 62500,
        dette: true,
        nomFournisseur: 'Véto-Santé Bénin',
        categorie: 'Vétérinaire',
      );

      await afficher(tester);
      await ouvrir(tester, "Liste d'Achats");

      expect(find.text('Véto-Santé Bénin'), findsOneWidget);
      // Ticket U8 — la colonne « Catégorie » est celle du PRODUIT de la première ligne (comme le web),
      // jamais celle du fournisseur : sans ligne, un tiret.
      expect(find.text('Vétérinaire'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('categorie-achat-0'))).data,
        '—',
      );
      expect(find.text('Dette fournisseur'), findsOneWidget);
    });

    /// ⚠️⚠️ AUCUNE RÉFÉRENCE D'ACHAT N'EXISTE DANS LE SCHÉMA — la maquette
    /// affiche « ACH-2026-101 », `purchases` n'a pas de colonne pour ça.
    testWidgets('⚠️⚠️ la référence est un tiret, jamais un numéro inventé', (
      tester,
    ) async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achatServeur('a1', cleFournisseur: 'f1', total: 185000);

      await afficher(tester);
      await ouvrir(tester, "Liste d'Achats");

      expect(find.text('—'), findsWidgets);
      expect(find.textContaining('ACH-'), findsNothing);
    });

    testWidgets(
      'les bons de commande portent les sept colonnes de la maquette',
      (tester) async {
        await afficher(tester);
        await ouvrir(tester, 'Bons de Commande');

        for (final colonne in [
          'RÉF COMMANDE',
          "DATE D'ÉMISSION",
          'LIVRAISON ATTENDUE',
          'FOURNISSEUR',
          'MONTANT ESTIMÉ',
          'STATUT',
          'ACTIONS',
        ]) {
          // Ticket AC-1 : « FOURNISSEUR » est aussi l'étiquette du formulaire de saisie du bon (Blade) — au moins un.
          expect(find.text(colonne), findsWidgets, reason: colonne);
        }
      },
    );

    /// ⚠️⚠️ LE MONTANT ESTIMÉ EST CALCULÉ PAR LE SERVEUR sur
    /// `estimated_unit_price` — écrit `unit_price` par habitude, il valait 0
    /// pour un bon de 405 000 FCFA.
    testWidgets('⚠️⚠️ le montant estimé d un bon est affiché tel que servi', (
      tester,
    ) async {
      await bonCommande('b1', estime: 405000);

      await afficher(tester);
      await ouvrir(tester, 'Bons de Commande');

      expect(find.text('405 000'), findsOneWidget);
      expect(find.text('ENVOYÉ / EN COURS'), findsOneWidget);
    });

    /// Ticket AC-1 — la saisie d'un bon n'est plus réservée au web : le formulaire du Blade est là, et le rappel Stocks
    /// (Classe 3) aussi ; l'ancienne mention « lecture seule » a disparu.
    testWidgets('⚠️ les bons se saisissent ici : formulaire du Blade, plus de mention « lecture seule »', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Bons de Commande');

      expect(find.byKey(const Key('mention-poste')), findsNothing);
      expect(find.textContaining('le serveur sert les bons en lecture seule'), findsNothing);
      expect(find.text("Saisie d'un Bon de Commande"), findsOneWidget);
      expect(find.byKey(const Key('bon-generer')), findsOneWidget);
      expect(find.byKey(const Key('bon-rappel')), findsOneWidget);
    });

    testWidgets('sans donnée, chaque tableau le dit', (tester) async {
      await afficher(tester);
      expect(find.text('— Aucun achat enregistré —'), findsOneWidget);

      await ouvrir(tester, "Liste d'Achats");
      expect(find.text('— Aucun achat pour ces critères —'), findsOneWidget);

      await ouvrir(tester, 'Bons de Commande');
      expect(
        find.text('Aucun bon de commande émis pour le moment.'),
        findsOneWidget,
      );
    });
  });
}
