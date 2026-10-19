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
      'écarts du mois : quantité signée × PMP, sans PMP = 0, mois précédent et refusés exclus',
      () async {
        await jeuFaitMain();
        // A : sortie 3 × 6 750 = −20 250 ; B (en attente d'envoi) : entrée 2 × 1 234,56 = +2 469,12 ;
        // C (sans PMP) : 0 ; A en septembre : exclu ; A refusé (`conflict`) : exclu.
        // round(−20 250 + 2 469,12) = round(−17 780,88) = −17 781.
        await ajustement('aj1', 'A', 'sortie', 3, DateTime(2026, 10, 12, 9));
        await ajustement(
          'aj2',
          'B',
          'entree',
          2,
          DateTime(2026, 10, 3, 9),
          statut: SyncStatus.pending,
        );
        await ajustement('aj3', 'C', 'sortie', 5, DateTime(2026, 10, 4, 9));
        await ajustement('aj4', 'A', 'sortie', 1, DateTime(2026, 9, 30, 18));
        await ajustement(
          'aj5',
          'A',
          'sortie',
          10,
          DateTime(2026, 10, 5, 9),
          statut: SyncStatus.conflict,
        );

        final d = await depot.charger();

        expect(d.ecartsDuMois, -17781);
        expect(PmpService.francs(d.ecartsDuMois), '-17 781');
        // Journal : `abs(quantité) × PMP`, « — » sans PMP.
        expect(
          {
            for (final m in d.mouvements)
              m.ajustement.reason: m.valeur == null
                  ? '—'
                  : PmpService.francs(m.valeur!),
          },
          {
            'Motif aj1': '20 250',
            'Motif aj2': '2 469',
            'Motif aj3': '—',
            'Motif aj4': '6 750',
            'Motif aj5': '67 500',
          },
        );
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
          await ajustement('aj1', 'A', 'sortie', 3, DateTime(2026, 10, 12, 9));
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
        // Lignes triées par code : A, B, C, D.
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
        expect(texte('valeur-mouvement-0'), '20 250 FCFA');
      },
    );
  });

  test(
    'parité exécutée U8 : PMP, valeurs, valorisation, écarts et journal = GestionStocks (Livewire + Blade)',
    () async {
      var graine = 23;
      int hasard(int n) =>
          (graine = (graine * 1103515245 + 12345) & 0x7fffffff) % n;

      // Dix produits : stocks positifs, nuls, négatifs, décimaux ; deux inactifs ; trois jamais achetés.
      final produits = [
        for (var i = 0; i < 10; i++)
          {
            'sku': 'P$i',
            'stock': [0, -4, 12.5, 37, 150, 3.25, -0.5, 80, 9, 41][i],
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
      // Mouvements : écarts web (`adjustment`) et poste (`inventaire`) d'octobre et de septembre, et des ventes
      // (`sale`) qui ne sont pas des écarts.
      final mouvements = [
        for (var m = 0; m < 14; m++)
          {
            'produit': hasard(10),
            'type': hasard(2) == 0 ? 'entree' : 'sortie',
            'qty': (1 + hasard(900)) / 100,
            'ref': [
              'adjustment',
              'inventaire',
              'inventaire',
              'sale',
            ][hasard(4)],
            'date': hasard(4) == 0
                ? '2026-09-${(10 + hasard(18)).toString()} 10:00:00'
                : '2026-10-${(1 + hasard(18)).toString().padLeft(2, '0')} 10:00:00',
            'motif': 'Mouvement $m',
          },
      ];

      final sortie =
          executerPhp('<?php\n$amorceApplication\n$_scriptPariteStocks', {
                'produits': produits,
                'achats': achats,
                'mouvements': mouvements,
              }, application: true)
              as Map<String, dynamic>;

      for (var i = 0; i < produits.length; i++) {
        await produit(
          'p$i-',
          sku: produits[i]['sku']! as String,
          stock: (produits[i]['stock']! as num).toDouble(),
          actif: produits[i]['actif']! as bool,
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
      for (var m = 0; m < mouvements.length; m++) {
        final x = mouvements[m];
        // Le journal du poste ne tient que les ajustements.
        if (x['ref'] == 'sale') continue;
        await db
            .into(db.stockAdjustments)
            .insert(
              StockAdjustmentsCompanion.insert(
                id: uuid('mvt-$m-'),
                deviceId: 'poste-test',
                syncStatus: const Value(SyncStatus.synced),
                updatedAt: maintenant,
                productId: uuid('p${x['produit']}-'),
                type: x['type']! as String,
                quantity: (x['qty']! as num).toDouble(),
                referenceType: x['ref']! as String,
                reason: Value(x['motif']! as String),
                movementDate: DateTime.parse(x['date']! as String),
              ),
            );
      }

      final d = await depot.charger();

      final lignes = (sortie['lignes'] as Map).cast<String, dynamic>();
      expect(
        {
          for (final l in d.lignes)
            l.produit.sku: [
              l.pmp == null ? '—' : PmpService.francs(l.pmp!),
              l.valeur == null ? '—' : PmpService.francs(l.valeur!),
            ],
        },
        {
          for (final e in lignes.entries)
            e.key: (e.value as List).cast<String>(),
        },
      );
      expect(
        '${PmpService.francs(d.valorisation)} FCFA',
        sortie['valorisation'],
      );
      expect('${PmpService.francs(d.ecartsDuMois)} FCFA', sortie['ecarts']);
      final journal = (sortie['journal'] as Map).cast<String, String>();
      expect(
        {
          for (final m in d.mouvements)
            m.ajustement.reason!: m.valeur == null
                ? '—'
                : '${PmpService.francs(m.valeur!)} FCFA',
        },
        {
          for (final e in journal.entries)
            if (mouvements.any(
              (x) => x['motif'] == e.key && x['ref'] != 'sale',
            ))
              e.key: e.value,
        },
      );

      // La grille couvre ce qu'elle prétend couvrir.
      expect(lignes.values.where((v) => (v as List).first == '—'), isNotEmpty);
      expect(lignes.values.where((v) => (v as List).first != '—'), isNotEmpty);
      expect(sortie['ecarts'], isNot('0 FCFA'));
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Script PHP de la parité : crée produits, achats (avec leurs lignes) et mouvements, fige l'horloge au 19/10/2026
/// 14 h, et rend ce que le Blade de `gestion-stocks` affiche : PMP et valeur par code produit, valorisation, écarts,
/// valeur de chaque mouvement du journal (par motif).
const _scriptPariteStocks = r'''
Carbon\Carbon::setTestNow('2026-10-19 14:00:00');
$entree = json_decode(file_get_contents($argv[1]), true);
$categorie = App\Models\ProductCategory::create(['label' => 'Aliments', 'is_active' => true]);
$produits = [];
foreach ($entree['produits'] as $i => $p) {
    $produits[$i] = App\Models\Product::create([
        'sku' => $p['sku'], 'name' => 'Produit '.$p['sku'], 'category_id' => $categorie->id, 'unit' => 'sac',
        'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 100000,
        'stock_qty' => $p['stock'], 'is_active' => $p['actif'],
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
        'reference_type' => $m['ref'], 'reason' => $m['motif'], 'movement_date' => $m['date'],
    ]);
}
$composant = new App\Livewire\Stocks\GestionStocks();
$lignes = [];
foreach ($composant->stockRows as $row) {
    $lignes[$row['product']->sku] = [
        $row['pmp'] !== null ? number_format($row['pmp'], 0, ',', ' ') : '—',
        $row['valeur'] !== null ? number_format($row['valeur'], 0, ',', ' ') : '—',
    ];
}
$journal = [];
foreach (App\Models\StockMovement::with('product')->get() as $movement) {
    $movPmp = $movement->product?->computePmp();
    $journal[$movement->reason] = $movPmp !== null ? number_format(abs($movement->quantity) * $movPmp, 0, ',', ' ').' FCFA' : '—';
}
echo json_encode([
    'lignes' => $lignes,
    'valorisation' => number_format($composant->kpis['valorisation'], 0, ',', ' ').' FCFA',
    'ecarts' => number_format($composant->kpis['ecarts'], 0, ',', ' ').' FCFA',
    'journal' => $journal,
]);
''';
