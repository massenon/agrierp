import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/stocks/gestion_stocks_screen.dart';
import 'package:agrierp/features/stocks/pmp_service.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket U8 — LA VALORISATION DE LA GESTION DES STOCKS, COMME LE WEB.
///
/// Le poste affichait « — » pour le PMP unitaire, la valeur de chaque ligne, la valorisation totale et les écarts en
/// FCFA : `purchase_lines` ne descendait pas. Depuis U4 elles descendent ; la valorisation reprend EXACTEMENT
/// `GestionStocks` (Livewire) et son Blade, par [PmpService] (`Product::computePmp()`).
///
/// Deux familles de garde-fous :
///  1. un JEU FAIT À LA MAIN, valeurs attendues calculées en commentaire (littéraux, jamais produits par le code
///     testé) — dont la règle des achats refusés (`conflict`) et le plancher du stock négatif ;
///  2. une PARITÉ EXÉCUTÉE avec le vrai PHP (`GestionStocks::stockRows` et `::kpis`, formats du Blade), sautée avec sa
///     raison sans PHP ni `vendor/`.
void main() {
  late AppDatabase db;
  late StocksRepository depot;

  String uuid(String graine) => graine.padRight(36, '0');
  final maintenant = DateTime(2026, 10, 19, 14);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = StocksRepository(
      database: db,
      deviceId: 'poste-test',
      horloge: () => maintenant,
    );
  });

  tearDown(() async => db.close());

  Future<void> produit(
    String cle, {
    required String sku,
    required double stock,
    bool actif = true,
  }) => db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: uuid(cle),
          sku: sku,
          name: 'Produit $sku',
          unit: 'sac',
          pricingMode: 'fixe',
          stockQty: Value(stock),
          isActive: Value(actif),
        ),
      );

  Future<void> achat(
    String cle,
    List<(String, double, double)> lignes, {
    SyncStatus statut = SyncStatus.synced,
  }) async {
    await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            id: uuid(cle),
            deviceId: 'serveur',
            updatedAt: DateTime(2026, 10, 1),
            syncStatus: Value(statut),
            supplierId: uuid('fournisseur'),
            paymentMode: 'especes',
            total: 0,
            purchaseDate: DateTime(2026, 10, 1),
          ),
        );
    for (var i = 0; i < lignes.length; i++) {
      final (p, qte, prix) = lignes[i];
      await db
          .into(db.purchaseLines)
          .insert(
            PurchaseLinesCompanion.insert(
              id: uuid('$cle-l$i-'),
              purchaseId: uuid(cle),
              productId: uuid(p),
              qty: qte,
              unitPrice: prix,
            ),
          );
    }
  }

  Future<void> ajustement(
    String cle,
    String p,
    String type,
    double qte,
    DateTime quand, {
    SyncStatus statut = SyncStatus.synced,
    String reference = 'inventaire',
  }) => db
      .into(db.stockAdjustments)
      .insert(
        StockAdjustmentsCompanion.insert(
          id: uuid(cle),
          deviceId: 'poste-test',
          syncStatus: Value(statut),
          updatedAt: quand,
          productId: uuid(p),
          type: type,
          quantity: qte,
          referenceType: reference,
          reason: Value('Motif $cle'),
          movementDate: quand,
        ),
      );

  /// Ticket U9 — un mouvement du grand livre DESCENDU du serveur (`stock_movements`).
  Future<void> mouvement(
    String cle,
    String p,
    String type,
    double qte,
    DateTime quand, {
    String reference = 'adjustment',
    String? referenceId,
  }) => db
      .into(db.stockMovements)
      .insert(
        StockMovementsCompanion.insert(
          id: uuid(cle),
          productId: uuid(p),
          type: type,
          quantity: qte,
          referenceType: reference,
          referenceId: Value(referenceId),
          reason: Value('Motif $cle'),
          movementDate: quand,
        ),
      );

  /// Jeu fait à la main.
  ///  - A : achats 10 × 6 000 + 30 × 7 000 (reçus) → PMP = 270 000 ÷ 40 = 6 750 ; stock 40 → valeur 270 000.
  ///    Un achat REFUSÉ (`conflict`) de 100 × 1 000 n'entre PAS au PMP (il le ferait tomber à 2 642,86).
  ///  - B : achat EN ATTENTE d'envoi 4 × 1 234,56 → PMP 1 234,56 (affiché « 1 235 ») ; stock −3 → valeur 0 (plancher).
  ///  - C : jamais acheté → PMP « — », valeur « — ».
  ///  - D : stock 2,5 ; achats 3 × 999,99 + 1 × 1 000,01 → PMP = 3 999,98 ÷ 4 = 999,995 → 1 000,00 (arrondi PHP à
  ///    2 décimales) ; valeur round(2,5 × 1 000) = 2 500.
  ///  - E : INACTIF, acheté 5 × 10 000, stock 10 → hors du tableau et de la valorisation.
  ///  Valorisation = 270 000 + 0 + 2 500 = 272 500.
  Future<void> jeuFaitMain() async {
    await produit('A', sku: 'A', stock: 40);
    await produit('B', sku: 'B', stock: -3);
    await produit('C', sku: 'C', stock: 12);
    await produit('D', sku: 'D', stock: 2.5);
    await produit('E', sku: 'E', stock: 10, actif: false);
    await achat('ach1', [('A', 10, 6000), ('A', 30, 7000), ('D', 3, 999.99)]);
    await achat('ach2', [('A', 100, 1000)], statut: SyncStatus.conflict);
    await achat('ach3', [
      ('B', 4, 1234.56),
      ('D', 1, 1000.01),
    ], statut: SyncStatus.pending);
    await achat('ach4', [('E', 5, 10000)]);
  }

  group('jeu fait à la main', () {
    test('PMP, valeur et valorisation : formule et formats du web', () async {
      await jeuFaitMain();

      final d = await depot.charger();
      final parSku = {for (final l in d.lignes) l.produit.sku: l};

      expect(parSku.keys, [
        'A',
        'B',
        'C',
        'D',
      ], reason: 'produits actifs seuls');
      expect(
        {
          for (final l in d.lignes)
            l.produit.sku: (
              l.pmp == null ? '—' : PmpService.francs(l.pmp!),
              l.valeur == null ? '—' : PmpService.francs(l.valeur!),
            ),
        },
        {
          'A': ('6 750', '270 000'),
          'B': ('1 235', '0'),
          'C': ('—', '—'),
          'D': ('1 000', '2 500'),
        },
      );
      expect(parSku['D']!.pmp, 1000.0);
      expect(PmpService.francs(d.valorisation), '272 500');
    });

    test(
      'U9 — écarts du mois : grand livre de la FERME + saisies en attente, sans double compte ni refusés',
      () async {
        await jeuFaitMain();
        // Descendus du serveur :
        //  - A sortie 3 « inventaire » (un autre poste) le 12/10 : −3 × 6 750 = −20 250 ;
        //  - C sortie 5 « adjustment » (le web) le 04/10 : sans PMP → 0 ;
        //  - A sortie 1 le 30/09 : mois précédent, exclu ;
        //  - A sortie 2 « sale » le 05/10 : une vente n'est pas un écart, exclue.
        await mouvement('m1', 'A', 'sortie', 3, DateTime(2026, 10, 12, 9), reference: 'inventaire');
        await mouvement('m2', 'C', 'sortie', 5, DateTime(2026, 10, 4, 9));
        await mouvement('m3', 'A', 'sortie', 1, DateTime(2026, 9, 30, 18));
        await mouvement('m4', 'A', 'sortie', 2, DateTime(2026, 10, 5, 9), reference: 'sale');
        // Saisies du poste :
        //  - B entrée 2, EN ATTENTE, saisie le 28/09 : le serveur la datera de sa RÉCEPTION (`AdjustStockAction` sans
        //    date) → comptée au mois présent : +2 × 1 234,56 = +2 469,12 ;
        //  - A sortie 10, REFUSÉE (`conflict`) : jamais comptée ;
        //  - D sortie 1, EN ATTENTE, mais déjà rejouée par le serveur (renvoi sans accusé) : son mouvement est
        //    descendu (`reference_id` = la ligne) le 10/10 → comptée UNE fois : −1 × 1 000 = −1 000 ;
        //  - A sortie 4, ACQUITTÉE (`synced`) : le serveur l'a, son mouvement descendra — jamais projetée.
        await ajustement('aj1', 'B', 'entree', 2, DateTime(2026, 9, 28, 9), statut: SyncStatus.pending);
        await ajustement('aj2', 'A', 'sortie', 10, DateTime(2026, 10, 5, 9), statut: SyncStatus.conflict);
        await ajustement('aj3', 'D', 'sortie', 1, DateTime(2026, 10, 10, 8), statut: SyncStatus.pending);
        await mouvement('m5', 'D', 'sortie', 1, DateTime(2026, 10, 10, 8, 5), reference: 'inventaire', referenceId: uuid('aj3'));
        await ajustement('aj4', 'A', 'sortie', 4, DateTime(2026, 10, 11, 9));

        final d = await depot.charger();

        // round(−20 250 + 0 + 2 469,12 − 1 000) = round(−18 780,88) = −18 781.
        expect(d.ecartsDuMois, -18781);
        expect(PmpService.francs(d.ecartsDuMois), '-18 781');
        // Journal : `abs(quantité) × PMP`, « — » sans PMP ; ni le refusé, ni l'acquitté, ni le doublon de aj3.
        // Les deux lignes de l'achat EN ATTENTE `ach3` (B 4 × 1 234,56 ; D 1 × 1 000,01) sont projetées en entrées
        // `purchase` à l'instant présent (`RecordPurchaseAction` ne date pas le mouvement).
        expect(
          [
            for (final m in d.journal.where((m) => m.mouvement.referenceType == 'purchase'))
              (m.mouvement.productId, m.mouvement.type, m.mouvement.quantity, m.mouvement.date, m.valeurAffichee),
          ],
          unorderedEquals([
            (uuid('B'), 'entree', 4.0, maintenant, '4 938 FCFA'),
            (uuid('D'), 'entree', 1.0, maintenant, '1 000 FCFA'),
          ]),
        );
        expect(
          {
            for (final m in d.journal)
              if (m.mouvement.reason != null)
                m.mouvement.reason: m.valeur == null
                    ? '—'
                    : PmpService.francs(m.valeur!),
          },
          {
            'Motif m1': '20 250',
            'Motif m2': '—',
            'Motif m3': '6 750',
            'Motif m4': '13 500',
            'Motif aj1': '2 469',
            'Motif m5': '1 000',
          },
        );
        // L'ajustement en attente est daté de l'instant présent : en tête du journal, avec les achats en attente.
        final aj1 = d.journal.firstWhere((m) => m.mouvement.reason == 'Motif aj1');
        expect(d.journal.indexOf(aj1), lessThan(3));
        expect(aj1.mouvement.date, maintenant);
        expect(aj1.mouvement.enAttente, isTrue);
      },
    );

    test('arrondis de PHP : demi loin de zéro, pré-arrondi à 15 chiffres', () {
      expect(PmpService.arrondi(1.005, 2), 1.01);
      expect(PmpService.arrondi(-2.5, 0), -3);
      expect(PmpService.francs(-0.4), '0');
      expect(PmpService.francs(1234567.5), '1 234 568');
    });

    testWidgets(
      'l écran affiche la valorisation du web, « — » là seulement où le web en met un',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.runAsync(() async {
          await jeuFaitMain();
          await mouvement('m1', 'A', 'sortie', 3, DateTime(2026, 10, 12, 9), reference: 'inventaire');
        });

        await tester.pumpWidget(
          MaterialApp(home: GestionStocksScreen(depot: depot)),
        );
        await tester.pumpAndSettle();

        Finder dans(String carte, String texte) => find.descendant(
          of: find.byKey(Key('kpi-$carte')),
          matching: find.text(texte),
        );
        expect(dans('Valorisation Stocks', '272 500 FCFA'), findsOneWidget);
        expect(
          dans('Valorisation Stocks', 'Basée sur le PMP réel (achats)'),
          findsOneWidget,
        );
        expect(dans("Écarts d'Inventaire", '-20 250 FCFA'), findsOneWidget);

        String texte(String cle) =>
            tester.widget<Text>(find.byKey(Key(cle))).data!;
        // Lignes triées par NOM (« Produit A » … « Produit D »).
        expect(
          [for (var i = 0; i < 4; i++) texte('pmp-$i')],
          ['6 750', '1 235', '—', '1 000'],
        );
        expect(
          [for (var i = 0; i < 4; i++) texte('valeur-$i')],
          ['270 000', '0', '—', '2 500'],
        );

        await tester.tap(
          find.byKey(const Key('onglet-stocks-Journal des Mouvements')),
        );
        await tester.pumpAndSettle();
        // Deux entrées de l'achat en attente (B, D) d'abord (datées de maintenant), puis la sortie du 12/10.
        expect(texte('valeur-mouvement-2'), '20 250 FCFA');
      },
    );
  });

  test(
    'parité exécutée U8/U9 : tableau, KPI (dont rotation et écarts) et journal = GestionStocks (Livewire + Blade)',
    () async {
      var graine = 23;
      // ⚠️ Bits HAUTS du générateur : ses bits bas ont une période de 2^k, et deux tirages consécutifs « mois » et
      // « référence » restaient corrélés (aucune vente en octobre).
      int hasard(int n) =>
          ((graine = (graine * 1103515245 + 12345) & 0x7fffffff) >> 16) % n;

      // Dix produits : stocks positifs, nuls, négatifs, décimaux ; deux inactifs ; trois jamais achetés ; seuils nuls,
      // atteints ou non ; noms dont l'ordre n'est pas celui des codes.
      final noms = [
        'Provende ponte', 'Antibiotique', 'Cage grillagée', 'Zinc oxyde', 'Maïs grain', //
        'Bâche', 'Poussins un jour', 'Eau de javel', 'Tourteau soja', 'Litière copeaux',
      ];
      final produits = [
        for (var i = 0; i < 10; i++)
          {
            'sku': 'P$i',
            'nom': noms[i],
            'stock': [0, -4, 12.5, 37, 150, 3.25, -0.5, 80, 9, 41][i],
            'seuil': [0, 5, 20, 0, 10, 3.25, 1, 100, 0, 40][i],
            'actif': i != 4 && i != 8,
          },
      ];
      // Achats reçus (servis au web) sur les produits 0 à 6 ; prix à deux décimales.
      final achats = [
        for (var a = 0; a < 7; a++)
          {
            'lignes': [
              for (var l = 0; l < 1 + hasard(3); l++)
                {
                  'produit': hasard(7),
                  'qty': (1 + hasard(4000)) / 100,
                  'prix': (100 + hasard(2000000)) / 100,
                },
            ],
          },
      ];
      // Grand livre : entrées et sorties d'août à octobre, ventes, achats, production, écarts du web (`adjustment`)
      // et des postes (`inventaire`), un `ajustement` brut ; un instant distinct par mouvement (ordre du journal).
      final references = [
        'adjustment', 'inventaire', 'inventaire', 'sale', 'sale', 'sale', 'purchase', 'daily_entry', //
      ];
      final mouvements = [
        for (var m = 0; m < 60; m++)
          () {
            final mois = [8, 9, 10, 10][hasard(4)];
            final jour = 1 + hasard(mois == 10 ? 19 : 28);
            final reference = references[hasard(references.length)];
            final type = m == 7
                ? 'ajustement'
                : reference == 'purchase' || reference == 'daily_entry'
                ? 'entree'
                : reference == 'sale'
                ? 'sortie'
                : (hasard(2) == 0 ? 'entree' : 'sortie');
            return {
              'produit': hasard(10),
              'type': type,
              'qty': (1 + hasard(2500)) / 100,
              'ref': reference,
              'ref_id': hasard(3) == 0 ? null : uuid('piece-$m-'),
              'date':
                  '2026-${mois.toString().padLeft(2, '0')}-${jour.toString().padLeft(2, '0')} '
                  '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}:00',
              'motif': hasard(3) == 0 ? null : 'Mouvement $m',
            };
          }(),
      ];

      final sortie =
          executerPhp('<?php\n$amorceApplication\n$_scriptPariteStocks', {
                'produits': produits,
                'achats': achats,
                'mouvements': mouvements,
              }, application: true)
              as Map<String, dynamic>;

      for (var i = 0; i < produits.length; i++) {
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: uuid('p$i-'),
                sku: produits[i]['sku']! as String,
                name: produits[i]['nom']! as String,
                unit: 'sac',
                pricingMode: 'fixe',
                stockQty: Value((produits[i]['stock']! as num).toDouble()),
                alertThreshold: Value((produits[i]['seuil']! as num).toDouble()),
                isActive: Value(produits[i]['actif']! as bool),
              ),
            );
      }
      for (var a = 0; a < achats.length; a++) {
        await achat('a$a-', [
          for (final l in achats[a]['lignes']! as List)
            (
              'p${(l as Map)['produit']}-',
              (l['qty'] as num).toDouble(),
              (l['prix'] as num).toDouble(),
            ),
        ]);
      }
      // Un achat REFUSÉ par le serveur : le web ne le connaît pas, il ne doit rien changer au PMP.
      await achat('refuse', [('p0-', 999, 1)], statut: SyncStatus.conflict);
      // Le grand livre DESCENDU tel que le serveur le sert (U9).
      for (var m = 0; m < mouvements.length; m++) {
        final x = mouvements[m];
        await db
            .into(db.stockMovements)
            .insert(
              StockMovementsCompanion.insert(
                id: uuid('mvt-$m-'),
                productId: uuid('p${x['produit']}-'),
                type: x['type']! as String,
                quantity: (x['qty']! as num).toDouble(),
                referenceType: x['ref']! as String,
                referenceId: Value(x['ref_id'] as String?),
                reason: Value(x['motif'] as String?),
                movementDate: DateTime.parse(x['date']! as String),
              ),
            );
      }
      // Un ajustement REFUSÉ et un ACQUITTÉ : ni l'un ni l'autre n'entre (le web ne connaît pas le premier, il sert
      // déjà le second par son mouvement).
      await ajustement('refuse-aj', 'p0-', 'sortie', 50, maintenant, statut: SyncStatus.conflict);
      await ajustement('acquitte-aj', 'p1-', 'sortie', 50, maintenant);

      final d = await depot.charger();

      // Tableau : ordre (tri par NOM), stock, PMP, valeur, urgence.
      final lignes = (sortie['lignes'] as List).cast<List>();
      expect(
        [
          for (final l in d.lignes)
            [
              l.produit.sku,
              PmpService.quantite(l.produit.stockQty),
              l.stockNegatif,
              l.pmp == null ? '—' : PmpService.francs(l.pmp!),
              l.valeur == null ? '—' : PmpService.francs(l.valeur!),
              l.urgence,
            ],
        ],
        lignes,
      );
      // KPI.
      expect('${PmpService.francs(d.valorisation)} FCFA', sortie['valorisation']);
      expect('${d.alertesDeSeuil} réf.', sortie['alertes']);
      expect('${PmpService.francs(d.ecartsDuMois)} FCFA', sortie['ecarts']);
      expect(
        d.rotation.rotation == null
            ? '—'
            : '${PmpService.nombre(d.rotation.rotation!, 1)} fois/mois',
        sortie['rotation'],
      );
      expect(GestionStocksScreen.legendeRotation(d.rotation), sortie['rotation_legende']);
      expect(d.rotation.cogs, closeTo((sortie['cogs'] as num).toDouble(), 1e-9));
      expect(
        d.rotation.stockMoyen,
        closeTo((sortie['stock_moyen'] as num).toDouble(), 1e-9),
      );
      // Journal : les 100 derniers (toutes les pages du web, ticket EX7), dans l'ordre du web, cellule par cellule.
      expect(
        [
          for (final l in d.journal)
            [
              l.dateHeure,
              l.reference,
              l.designation ?? '',
              l.motif,
              l.quantite,
              l.valeurAffichee,
            ],
        ],
        (sortie['journal'] as List).cast<List>(),
      );

      // La grille couvre ce qu'elle prétend couvrir.
      expect(lignes.where((v) => v[3] == '—'), isNotEmpty);
      expect(lignes.where((v) => v[3] != '—'), isNotEmpty);
      expect(lignes.where((v) => v[5] == true), isNotEmpty);
      expect(lignes.where((v) => v[2] == true), isNotEmpty);
      expect(sortie['ecarts'], isNot('0 FCFA'));
      expect(sortie['rotation'], isNot('—'));
      // Plus de message de couverture sous le ratio (demande client, web et poste).
      expect(sortie['rotation_legende'], isEmpty);
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Script PHP de la parité : crée produits, achats (avec leurs lignes) et mouvements, fige l'horloge au 19/10/2026
/// 14 h, et rend ce que le Blade de `gestion-stocks` affiche : lignes du tableau dans SON ordre, KPI (valorisation,
/// alertes, écarts, rotation et sa légende, construites comme dans le Blade) et journal, cellule par cellule.
const _scriptPariteStocks = r'''
Carbon\Carbon::setTestNow('2026-10-19 14:00:00');
$entree = json_decode(file_get_contents($argv[1]), true);
$categorie = App\Models\ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
$produits = [];
foreach ($entree['produits'] as $i => $p) {
    $produits[$i] = App\Models\Product::create([
        'sku' => $p['sku'], 'name' => $p['nom'], 'category_id' => $categorie->id, 'unit' => 'sac',
        'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 100000,
        'stock_qty' => $p['stock'], 'alert_threshold' => $p['seuil'], 'is_active' => $p['actif'],
    ]);
}
$fournisseur = App\Models\Supplier::create(['name' => 'Fournisseur', 'is_active' => true]);
foreach ($entree['achats'] as $a) {
    $achat = App\Models\Purchase::create([
        'supplier_id' => $fournisseur->id, 'payment_mode' => 'especes', 'total' => 0, 'purchase_date' => '2026-10-01',
    ]);
    foreach ($a['lignes'] as $l) {
        App\Models\PurchaseLine::create([
            'purchase_id' => $achat->id, 'product_id' => $produits[$l['produit']]->id,
            'qty' => $l['qty'], 'unit_price' => $l['prix'],
        ]);
    }
}
foreach ($entree['mouvements'] as $m) {
    App\Models\StockMovement::create([
        'product_id' => $produits[$m['produit']]->id, 'type' => $m['type'], 'quantity' => $m['qty'],
        'reference_type' => $m['ref'], 'reference_id' => $m['ref_id'], 'reason' => $m['motif'],
        'movement_date' => $m['date'],
    ]);
}
$composant = new App\Livewire\Stocks\GestionStocks();
$lignes = [];
foreach ($composant->stockRows as $row) {
    $lignes[] = [
        $row['product']->sku,
        rtrim(rtrim(number_format($row['product']->stock_qty, 2, '.', ''), '0'), '.'),
        $row['stock_negatif'],
        $row['pmp'] !== null ? number_format($row['pmp'], 0, ',', ' ') : '—',
        $row['valeur'] !== null ? number_format($row['valeur'], 0, ',', ' ') : '—',
        $row['urgence'],
    ];
}
$kpis = $composant->kpis;
$rotation = $kpis['rotation'];
$rotationLegende = $rotation['rotation'] === null
    ? 'Disponible après un stock valorisable non nul sur le mois'
    : '';
$journal = [];
// Ticket EX7 : le Journal des Mouvements du web est PAGINÉ (25) dans l'exercice affiché (ici l'année civile 2026,
// aucun exercice enregistré) ; la parité lit toutes ses pages, dans l'ordre.
$mouvements = [];
for ($page = 1; $page <= 100; $page++) {
    $composant->setPage($page, 'pageMouvements');
    Illuminate\Pagination\Paginator::currentPageResolver(fn () => $page);
    $paginees = $composant->getMovementsProperty();
    foreach ($paginees as $m) {
        $mouvements[] = $m;
    }
    if (! $paginees->hasMorePages()) {
        break;
    }
}
foreach ($mouvements as $movement) {
    $movPmp = $movement->product?->computePmp();
    $journal[] = [
        $movement->movement_date->format('d/m/Y H:i'),
        $movement->reference_id ? strtoupper(substr($movement->reference_id, 0, 8)) : '—',
        (string) $movement->product?->name,
        $composant->referenceLabel($movement->reference_type).($movement->reason ? ' — '.$movement->reason : ''),
        ($movement->type === 'sortie' ? '-' : '+').rtrim(rtrim(number_format($movement->quantity, 2, '.', ''), '0'), '.'),
        $movPmp !== null ? number_format(abs($movement->quantity) * $movPmp, 0, ',', ' ').' FCFA' : '—',
    ];
}
echo json_encode([
    'lignes' => $lignes,
    'valorisation' => number_format($kpis['valorisation'], 0, ',', ' ').' FCFA',
    'alertes' => $kpis['alertes'].' réf.',
    'ecarts' => number_format($kpis['ecarts'], 0, ',', ' ').' FCFA',
    'rotation' => $rotation['rotation'] === null ? '—' : number_format($rotation['rotation'], 1, ',', ' ').' fois/mois',
    'rotation_legende' => $rotationLegende,
    'cogs' => $rotation['cogs'],
    'stock_moyen' => $rotation['stock_moyen'],
    'journal' => $journal,
]);
''';
