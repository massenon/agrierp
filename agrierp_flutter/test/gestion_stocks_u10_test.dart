import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/theme/symboles_agri.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/stocks/catalogue_produits_screen.dart';
import 'package:agrierp/features/stocks/gestion_stocks_screen.dart';
import 'package:agrierp/features/stocks/journal_stocks.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket U10 — GESTION DES STOCKS : LES DERNIERS GESTES DU WEB AU POSTE.
///
/// « Exporter » (PDF de `exportStocksPdf()`), « Ajouter Stock » (modale, règles et messages de
/// `submitAjouterStock()`, fait `manual_addition` en attente d'envoi, daté du jour CHOISI), « Configurer les Seuils
/// d'Alerte » et l'icône Modifier (destinations du web), l'écart « 0 » de l'onglet Ajustement, le sablier de la carte
/// « en attente ». Parités EXÉCUTÉES avec le vrai PHP : document d'export, écart affiché, messages de validation.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Serveur feint : acquitte tout envoi par `id` et garde chaque corps.
class _Serveur extends Interceptor {
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [
                    for (final e in value)
                      if (e is Map && e['id'] is String) e['id'],
                  ],
                  'rejected': [],
                },
          },
        ),
      );
      return;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {'server_time': '2026-10-19T12:00:00Z'},
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late StocksRepository depot;

  const provende = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
  const oeufs = 'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb';
  const categorie = 'cccccccc-0000-4000-8000-cccccccccccc';
  final maintenant = DateTime(2026, 10, 19, 14);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = StocksRepository(
      database: db,
      deviceId: 'poste-test',
      horloge: () => maintenant,
    );
    await db
        .into(db.productCategories)
        .insert(
          ProductCategoriesCompanion.insert(id: categorie, label: 'Aliments'),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: provende,
            sku: 'ALI-001',
            name: 'Aliment ponte 25kg',
            categoryId: const Value(categorie),
            unit: 'sac',
            pricingMode: 'fixe',
            stockQty: const Value(45),
            alertThreshold: const Value(15),
          ),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: oeufs,
            sku: 'AVI-002',
            name: 'Œufs de table (plateau)',
            unit: 'plateau',
            pricingMode: 'fixe',
            stockQty: const Value(8),
            alertThreshold: const Value(30),
          ),
        );
  });

  tearDown(() async => db.close());

  // ── Ajouter Stock : règles du web ─────────────────────────────────────────

  group('Ajouter Stock — dépôt', () {
    test(
      '⚠️⚠️ U10 — une ENTRÉE manual_addition en attente, datée du jour CHOISI, et le stock local suit',
      () async {
        final a = await depot.ajouterStock(
          date: DateTime(2026, 10, 3, 17, 45),
          productId: provende,
          quantite: '20',
        );

        expect(a.type, 'entree');
        expect(a.referenceType, 'manual_addition');
        expect(a.quantity, 20);
        expect(a.reason, isNull);
        expect(a.syncStatus, SyncStatus.pending);
        // `Carbon::parse($addDate)` : le jour, à minuit — jamais l'heure de la saisie.
        expect(a.movementDate, DateTime(2026, 10, 3));
        expect(a.updatedAt, maintenant);

        final p = await (db.select(
          db.products,
        )..where((t) => t.id.equals(provende))).getSingle();
        expect(p.stockQty, 65);

        // Projeté au grand livre du poste au jour choisi, libellé « Ajout Manuel » ; jamais compté en écart
        // d'inventaire.
        final journal = await JournalStocks.charger(db, maintenant: maintenant);
        final m = journal.mouvements.single;
        expect(m.date, DateTime(2026, 10, 3));
        expect(m.enAttente, isTrue);
        expect(JournalStocks.libelleReference(m.referenceType), 'Ajout Manuel');
        expect(journal.ecartsDuMois({provende: 1000}, maintenant), 0);
      },
    );

    test('U10 — les refus du web, avec ses messages', () {
      expect(
        StocksRepository.validerAjout(
          date: DateTime(2026, 10, 3),
          productId: null,
          quantite: '',
        ),
        {
          'produit': 'Le champ produit est obligatoire.',
          'quantite': 'Le champ quantité est obligatoire.',
        },
      );
      expect(
        StocksRepository.validerAjout(
          date: null,
          productId: provende,
          quantite: '2.5',
        ),
        {
          'date': 'Le champ date est obligatoire.',
          'quantite': 'Le champ quantité doit être un nombre entier.',
        },
      );
      expect(
        StocksRepository.validerAjout(
          date: DateTime(2026, 10, 3),
          productId: provende,
          quantite: '0',
        ),
        {'quantite': 'Le champ quantité doit être au moins égal à 1.'},
      );
      expect(
        StocksRepository.validerAjout(
          date: DateTime(2026, 10, 3),
          productId: provende,
          quantite: '20.0',
        ),
        isEmpty,
      );
    });

    test('U10 — un refus n écrit rien', () async {
      await expectLater(
        depot.ajouterStock(
          date: DateTime(2026, 10, 3),
          productId: provende,
          quantite: '-3',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await db.select(db.stockAdjustments).get(), isEmpty);
    });

    test(
      '⚠️ U10 — l envoi porte le JOUR du mouvement (`movement_date`), que le serveur reprend pour un ajout manuel',
      () async {
        await depot.ajouterStock(
          date: DateTime(2026, 10, 3),
          productId: provende,
          quantite: '20',
        );
        final serveur = _Serveur();
        final moteur = SyncEngine(
          database: db,
          client: Dio()..interceptors.add(serveur),
          deviceId: 'poste-test',
          connectivity: _Connectivite(),
          maintenant: () => maintenant,
        );

        await moteur.synchroniser();

        final envoi =
            (serveur.envois.single['stock_adjustments'] as List).single as Map;
        expect(envoi['type'], 'entree');
        expect(envoi['reference_type'], 'manual_addition');
        expect(envoi['quantity'], 20);
        expect(envoi['movement_date'], '2026-10-03');
        expect(envoi['client_ref'], envoi['id']);
        expect(
          (await db.select(db.stockAdjustments).getSingle()).syncStatus,
          SyncStatus.synced,
        );
      },
    );
  });

  // ── Écran ─────────────────────────────────────────────────────────────────

  group('écran', () {
    final imprimes = <DocumentOfficiel>[];
    String? seuils;
    String? modifie;

    Future<void> afficher(WidgetTester tester, {bool peutGerer = true}) async {
      imprimes.clear();
      seuils = null;
      modifie = null;
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: GestionStocksScreen(
            depot: depot,
            peutGerer: peutGerer,
            imprimer: (doc, quand) async {
              imprimes.add(doc);
              return null;
            },
            onConfigurerSeuils: () => seuils = 'ouvert',
            onModifierProduit: (id) => modifie = id,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      '⚠️⚠️ U10 — « Exporter » édite le PDF du web, filtré comme l écran',
      (tester) async {
        await afficher(tester);
        await tester.enterText(find.byKey(const Key('stock-recherche')), 'ali');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('stocks-exporter')));
        await tester.pumpAndSettle();

        final doc = imprimes.single;
        expect(doc.titre, 'Gestion des Stocks — Tableau & Valorisation');
        expect(doc.sousTitre, 'État au 19/10/2026');
        expect(doc.entetes, [
          'Code',
          'Désignation',
          'Catégorie',
          'Stock',
          'PMP Unit.',
          'Valeur',
          'Urgence',
        ]);
        // Seul le produit filtré ; aucun achat → PMP et valeur « — » ; seuil 15 non atteint → « — ».
        expect((doc.lignes.single as DonneesDocument).cellules, [
          'ALI-001',
          'Aliment ponte 25kg',
          'Aliments',
          '45,00 sac',
          '—',
          '—',
          '—',
        ]);
      },
    );

    testWidgets(
      '⚠️⚠️ U10 — la modale « Ajouter Stock » : erreurs du web, puis le fait et le toast',
      (tester) async {
        await afficher(tester);
        await tester.tap(find.byKey(const Key('stocks-ajouter')));
        await tester.pumpAndSettle();

        expect(find.text('Ajouter Stock'), findsWidgets);
        expect(find.text('DATE DU NOUVEAU STOCK *'), findsOneWidget);
        expect(find.text('PRODUIT *'), findsOneWidget);
        expect(find.text('QUANTITÉ AJOUTÉE *'), findsOneWidget);
        expect(find.text('-- Sélectionner un produit --'), findsOneWidget);

        await tester.tap(find.byKey(const Key('ajout-enregistrer')));
        await tester.pumpAndSettle();
        expect(find.text('Le champ produit est obligatoire.'), findsOneWidget);
        expect(find.text('Le champ quantité est obligatoire.'), findsOneWidget);
        expect(await db.select(db.stockAdjustments).get(), isEmpty);

        await tester.tap(find.byKey(const Key('ajout-produit')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Œufs de table (plateau)').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('ajout-quantite')), '12');
        await tester.tap(find.byKey(const Key('ajout-enregistrer')));
        await tester.pumpAndSettle();

        final a = await db.select(db.stockAdjustments).getSingle();
        expect(
          [a.productId, a.type, a.quantity, a.referenceType],
          [oeufs, 'entree', 12, 'manual_addition'],
        );
        expect(find.text('Stock ajouté avec succès.'), findsOneWidget);
        // Le tableau relit le stock : 8 + 12.
        expect(find.text('20 plateau'), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'U10 — sans `manage-stocks`, ni « Ajouter Stock » ni icône Modifier (`@can` du Blade)',
      (tester) async {
        await afficher(tester, peutGerer: false);
        expect(find.byKey(const Key('stocks-ajouter')), findsNothing);
        expect(find.byKey(const Key('modifier-stock-0')), findsNothing);
        // « Exporter » reste (`view-stocks`).
        expect(find.byKey(const Key('stocks-exporter')), findsOneWidget);
      },
    );

    testWidgets(
      'U10 — « Configurer les Seuils d Alerte » et l icône Modifier mènent où mène le web',
      (tester) async {
        await afficher(tester);
        expect(find.text("Configurer les Seuils d'Alerte"), findsOneWidget);
        await tester.tap(find.byKey(const Key('stocks-configurer-seuils')));
        expect(seuils, 'ouvert');

        // Ligne 0 = « Aliment ponte 25kg » (tri par nom).
        await tester.tap(find.byKey(const Key('modifier-stock-0')));
        expect(modifie, provende);
      },
    );

    testWidgets(
      '⚠️ U10 — onglet Ajustement : l écart vaut « 0 » tant que rien n est saisi, comme au web',
      (tester) async {
        await afficher(tester);
        await tester.tap(
          find.byKey(const Key('onglet-stocks-Ajustement / Correction')),
        );
        await tester.pumpAndSettle();

        Text ecart() => tester.widget<Text>(find.byKey(const Key('adj-ecart')));
        expect(ecart().data, '0');
        expect(ecart().style!.color, isNot(isNull));

        await tester.enterText(find.byKey(const Key('adj-physique')), '47.5');
        await tester.pumpAndSettle();
        expect(ecart().data, '+2.5');
      },
    );

    testWidgets(
      '⚠️ U10 — la carte « en attente » porte le sablier du web, le tiret estompé',
      (tester) async {
        await afficher(tester);

        final carte = tester.widget<CarteKpi>(
          find.byKey(const Key('kpi-Rotation du Stock')),
        );
        expect(carte.valeur, '—');
        expect(carte.iconeLegende, SymbolesAgri.hourglass_empty);
        expect(
          find.descendant(
            of: find.byKey(const Key('kpi-Rotation du Stock')),
            matching: find.byIcon(SymbolesAgri.hourglass_empty),
          ),
          findsOneWidget,
        );
        // Les trois autres cartes n'ont pas de sablier, et chaque carte a son icône (`x-kpi-card :icon`).
        for (final libelle in [
          'Valorisation Stocks',
          'Alertes de Seuil',
          "Écarts d'Inventaire",
        ]) {
          final c = tester.widget<CarteKpi>(find.byKey(Key('kpi-$libelle')));
          expect(c.iconeLegende, isNull, reason: libelle);
          expect(c.icone, isNotNull, reason: libelle);
        }
      },
    );

    testWidgets('U10 — le Catalogue s ouvre sur l onglet ou l édition demandés', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogueProduitsScreen(
            depot: depot,
            ongletInitial: "Seuils d'Alerte",
          ),
        ),
      );
      await tester.pumpAndSettle();
      // L'onglet « Seuils d'Alerte » est actif (souligné), son contenu affiché.
      final onglet = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key("onglet-catalogue-Seuils d'Alerte")),
          matching: find.byType(Text),
        ),
      );
      expect(onglet.style?.color, isNot(isNull));
      expect(find.textContaining('Seuil'), findsWidgets);
    });
  });

  // ── Parités exécutées ─────────────────────────────────────────────────────

  test(
    'parité exécutée U10 : document d export, écart affiché et messages de « Ajouter Stock » = ceux du web',
    () async {
      final produits = <List<Object?>>[
        // nom, sku, stock, seuil, catégorie (NOT NULL au serveur), actif
        ['Provende ponte', 'ALI-001', 45.0, 15.0, 0, true],
        // « Oeufs » sans ligature : la base SQLite du test trie « Œ » en binaire (après « z »), MySQL comme « oe ».
        ['Oeufs de table (plateau)', 'AVI-002', 8.0, 30.0, 1, true],
        ['Son de blé', 'ALI-003', -2.5, 0.0, 0, true],
        [
          'Maïs grain',
          'ALI-004',
          1234.57,
          2000.0,
          1,
          true,
        ], // `stock_qty` : 2 décimales au serveur
        ['Ancien aliment', 'ALI-005', 3.0, 1.0, 0, false],
      ];
      final achats = [
        [0, 10.0, 18000.0],
        [0, 5.0, 17500.0],
        [3, 100.0, 215.5],
      ];
      // physique saisi (null = rien), produit (null = aucun)
      final ecarts = [
        [null, null],
        [null, 0],
        [40.0, 0],
        [52.5, 0],
        [45.333, 0],
        [1234.777, 3],
        [-2.5, 2],
      ];
      final filtres = [
        ['', ''],
        ['al', ''],
        ['', 'cat-0'],
        ['zzz', ''],
      ];

      final sortie =
          executerPhp('<?php\n$amorceApplication\n$_script', {
                'produits': produits,
                'achats': achats,
                'ecarts': ecarts,
                'filtres': filtres,
              }, application: true)
              as Map<String, dynamic>;

      for (var c = 0; c < 2; c++) {
        await db
            .into(db.productCategories)
            .insert(
              ProductCategoriesCompanion.insert(
                id: 'cat-$c'.padRight(36, '0'),
                label: ['Aliments', 'Céréales'][c],
              ),
            );
      }
      await db.delete(db.products).go();
      for (var i = 0; i < produits.length; i++) {
        final p = produits[i];
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: 'prod-$i'.padRight(36, '0'),
                sku: p[1]! as String,
                name: p[0]! as String,
                unit: 'sac',
                pricingMode: 'fixe',
                stockQty: Value(p[2]! as double),
                alertThreshold: Value(p[3]! as double),
                categoryId: Value(
                  p[4] == null ? null : 'cat-${p[4]}'.padRight(36, '0'),
                ),
                isActive: Value(p[5]! as bool),
              ),
            );
      }
      await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: 'achat'.padRight(36, '0'),
              deviceId: 'serveur',
              updatedAt: DateTime(2026, 10, 1),
              syncStatus: const Value(SyncStatus.synced),
              supplierId: 'fournisseur'.padRight(36, '0'),
              paymentMode: 'especes',
              total: 0,
              purchaseDate: DateTime(2026, 10, 1),
            ),
          );
      for (var a = 0; a < achats.length; a++) {
        await db
            .into(db.purchaseLines)
            .insert(
              PurchaseLinesCompanion.insert(
                id: 'ligne-$a'.padRight(36, '0'),
                purchaseId: 'achat'.padRight(36, '0'),
                productId: 'prod-${achats[a][0]}'.padRight(36, '0'),
                qty: achats[a][1] as double,
                unitPrice: achats[a][2] as double,
              ),
            );
      }

      final d = await depot.charger();

      // 1. Le document d'export, filtre par filtre (catégorie : l'identifiant du poste ↔ celui du serveur).
      final web = (sortie['exports'] as List).cast<List>();
      for (var f = 0; f < filtres.length; f++) {
        final cat = filtres[f][1].isEmpty
            ? ''
            : filtres[f][1].padRight(36, '0');
        final doc = StocksRepository.documentTableau(
          StocksRepository.filtrer(
            d.lignes,
            recherche: filtres[f][0],
            categorie: cat,
          ),
          maintenant,
        );
        expect(
          [
            for (final l in doc.lignes)
              (l as DonneesDocument).cellules
                  .where((c) => c.isNotEmpty)
                  .toList(),
          ],
          [for (final l in web[f]) (l as List).cast<String>()],
          reason: 'filtre $f',
        );
        expect(doc.sousTitre, sortie['sous_titre']);
      }

      // 2. L'écart affiché de l'onglet Ajustement.
      final ecartsWeb = (sortie['ecarts'] as List).cast<String>();
      for (var e = 0; e < ecarts.length; e++) {
        final produit = ecarts[e][1] as int?;
        final ligne = produit == null
            ? null
            : d.lignes.firstWhere(
                (l) => l.produit.id == 'prod-$produit'.padRight(36, '0'),
              );
        expect(
          StocksRepository.ecartAffiche(
            StocksRepository.ecartCalcule(
              theorique: ligne?.produit.stockQty,
              physique: ecarts[e][0] as double?,
            ),
          ),
          ecartsWeb[e],
          reason: 'écart $e',
        );
      }

      // 3. Les messages de validation de « Ajouter Stock ».
      final messages = (sortie['messages'] as Map).cast<String, dynamic>();
      expect(
        StocksRepository.validerAjout(
          date: maintenant,
          productId: null,
          quantite: '',
        ).values.toList(),
        (messages['vide'] as List).cast<String>(),
      );
      expect(
        StocksRepository.validerAjout(
          date: maintenant,
          productId: 'prod-0'.padRight(36, '0'),
          quantite: '0',
        ).values.toList(),
        (messages['zero'] as List).cast<String>(),
      );

      // La grille couvre ce qu'elle prétend couvrir.
      expect(ecartsWeb.toSet().length, greaterThan(4));
      expect(ecartsWeb.first, '0');
      expect(web[0].length, 4, reason: 'les produits actifs');
      expect(web[3].single, [
        'Aucun produit ne correspond aux filtres actifs.',
      ]);
    },
    skip:
        sautSansPhp() ??
        (File(
              '$dossierLaravel/resources/views/exports/gestion-stocks.blade.php',
            ).existsSync()
            ? null
            : 'SAUT : vue d export absente'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Script PHP : crée catégories, produits et achats, puis rend (1) la vue d'export du web
/// (`exports.gestion-stocks`) sur `GestionStocks::stockRows` pour chaque filtre, (2) l'écart affiché par le Blade de
/// l'onglet Ajustement pour chaque saisie, (3) les messages de validation de `submitAjouterStock()`.
const _script = r'''
Carbon\Carbon::setTestNow('2026-10-19 14:00:00');
$entree = json_decode(file_get_contents($argv[1]), true);
$admin = App\Models\User::create(['name' => 'Admin', 'username' => 'admin', 'email' => 'dg@olouwachegoun.bj',
    'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
(new Database\Seeders\RolesAndPermissionsSeeder())->run();
$admin->assignRole('admin');
$categories = [];
foreach (['Aliments', 'Céréales'] as $i => $label) {
    $c = new App\Models\ProductCategory(['label' => $label, 'is_active' => true]);
    $c->id = str_pad('cat-'.$i, 36, '0');
    $c->save();
    $categories[$i] = $c;
}
$produits = [];
foreach ($entree['produits'] as $i => $p) {
    $produits[$i] = App\Models\Product::create([
        'sku' => $p[1], 'name' => $p[0], 'category_id' => $p[4] === null ? null : $categories[$p[4]]->id,
        'unit' => 'sac', 'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 100000,
        'stock_qty' => $p[2], 'alert_threshold' => $p[3], 'is_active' => $p[5],
    ]);
}
$fournisseur = App\Models\Supplier::create(['name' => 'Fournisseur', 'is_active' => true]);
$achat = App\Models\Purchase::create(['supplier_id' => $fournisseur->id, 'payment_mode' => 'especes', 'total' => 0,
    'purchase_date' => '2026-10-01']);
foreach ($entree['achats'] as $a) {
    App\Models\PurchaseLine::create(['purchase_id' => $achat->id, 'product_id' => $produits[$a[0]]->id,
        'qty' => $a[1], 'unit_price' => $a[2]]);
}
function cellules(string $html): array {
    $doc = new DOMDocument();
    @$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
    $lignes = [];
    foreach ($doc->getElementsByTagName('tbody') as $tbody) {
        foreach ($tbody->getElementsByTagName('tr') as $tr) {
            $c = [];
            foreach ($tr->getElementsByTagName('td') as $td) {
                $t = trim(preg_replace('/\s+/u', ' ', $td->textContent));
                if ($t !== '') $c[] = $t;
            }
            $lignes[] = $c;
        }
    }
    return $lignes;
}
$exports = [];
foreach ($entree['filtres'] as [$recherche, $categorie]) {
    $composant = new App\Livewire\Stocks\GestionStocks();
    $composant->search = $recherche;
    $composant->categoryFilter = $categorie === '' ? '' : str_pad($categorie, 36, '0');
    $exports[] = cellules(view('exports.gestion-stocks', ['rows' => $composant->stockRows])->render());
}
$ecarts = [];
foreach ($entree['ecarts'] as [$physique, $produit]) {
    $html = Livewire\Livewire::actingAs($admin)->test(App\Livewire\Stocks\GestionStocks::class)
        ->set('tab', 'ajustements')
        ->set('adjProductId', $produit === null ? '' : $produits[$produit]->id)
        ->set('adjPhysical', $physique)
        ->html();
    $doc = new DOMDocument();
    @$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
    $x = new DOMXPath($doc);
    $ecarts[] = trim(preg_replace('/\s+/u', ' ', $x->query("//p[contains(@class, 'text-xl')]")->item(0)->textContent));
}
$vide = Livewire\Livewire::actingAs($admin)->test(App\Livewire\Stocks\GestionStocks::class)
    ->set('addProductId', '')->set('addQty', null)->call('submitAjouterStock')->errors();
$zero = Livewire\Livewire::actingAs($admin)->test(App\Livewire\Stocks\GestionStocks::class)
    ->set('addProductId', $produits[0]->id)->set('addQty', 0)->call('submitAjouterStock')->errors();
echo json_encode([
    'exports' => $exports,
    'sous_titre' => 'État au '.now()->format('d/m/Y'),
    'ecarts' => $ecarts,
    'messages' => [
        'vide' => array_merge($vide->get('addProductId'), $vide->get('addQty')),
        'zero' => array_merge($zero->get('addProductId'), $zero->get('addQty')),
    ],
], JSON_UNESCAPED_UNICODE);
''';
