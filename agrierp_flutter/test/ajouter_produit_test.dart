import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/stocks/ajouter_produit_screen.dart';
import 'package:agrierp/features/stocks/catalogue_produits_screen.dart';
import 'package:agrierp/features/stocks/produits_repository.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.67 — « Ajouter un Produit » / « Modifier le Produit »
/// (`ajouter-produit.html`), en ligne.
///
/// ⚠️⚠️ Le poste DEMANDE, le serveur DÉCIDE : le produit inscrit localement est celui
/// que le serveur RÉPOND (SKU engendré, prix effacés sur devis), jamais la saisie.
/// Serveur de synchronisation feint : sert `corps` au tirage, note les envois et
/// répond au push avec `reponsePush`.
class _Tirage extends Interceptor {
  _Tirage(this.corps, {this.reponsePush = const {}});

  final Map<String, dynamic> corps;
  final Map<String, dynamic> reponsePush;
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final push = options.path.contains('push');
    if (push) envois.add(Map<String, dynamic>.from(options.data as Map));
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: push ? reponsePush : corps,
      ),
    );
  }
}

class _ConnectiviteFeinte implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

void main() {
  late AppDatabase db;

  const cat = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
  const esp = 'eeeeeeee-0000-4000-8000-eeeeeeeeeeee';
  const idProduit = 'pppppppp-0000-4000-8000-pppppppppppp';

  Map<String, dynamic> produitServeur({
    String mode = 'fourchette',
    Object? min = 3000,
    Object? max = 4000,
    String sku = 'AVI-007',
    String nom = 'Poulet fermier',
  }) => {
    'id': idProduit,
    'sku': sku,
    'name': nom,
    'category_id': cat,
    'species_id': null,
    'unit': 'u',
    'pricing_mode': mode,
    'price_min': min,
    'price_max': max,
    'tva_rate': '0.00',
    'stock_qty': '12.00',
    'alert_threshold': '5.00',
    'description': 'Vif',
    'is_active': true,
    'updated_at': '2026-10-08T10:00:00.000000Z',
  };

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.productCategories)
        .insert(
          ProductCategoriesCompanion.insert(id: cat, label: 'Aviculture'),
        );
    await db
        .into(db.livestockSpecies)
        .insert(
          LivestockSpeciesCompanion.insert(
            id: esp,
            code: 'cuniculture',
            label: 'Lapins',
          ),
        );
  });
  tearDown(() async => db.close());

  ProduitsRepository depot() => ProduitsRepository(database: db);

  const valide = FormulaireProduit(
    nom: 'Poulet fermier',
    categorieId: cat,
    unite: 'u',
    mode: 'fourchette',
    prixMin: 3000,
    prixMax: 4000,
    stock: 12,
    seuil: 5,
  );

  group('règles de saisie (identiques à ProductCatalogService)', () {
    test('une saisie complète est recevable', () {
      expect(ProduitsRepository.valider(valide, creation: true), isEmpty);
    });

    test('nom, catégorie et unité sont obligatoires', () {
      const vide = FormulaireProduit(
        nom: ' ',
        categorieId: '',
        unite: '',
        mode: 'quote',
      );
      expect(
        ProduitsRepository.valider(vide, creation: true).keys,
        containsAll(['nom', 'categorie', 'unite']),
      );
    });

    test('fourchette : les deux prix, et max au moins égal à min', () {
      const sans = FormulaireProduit(
        nom: 'X',
        categorieId: cat,
        unite: 'u',
        mode: 'fourchette',
      );
      expect(
        ProduitsRepository.valider(sans, creation: true).keys,
        containsAll(['prixMin', 'prixMax']),
      );

      const inverse = FormulaireProduit(
        nom: 'X',
        categorieId: cat,
        unite: 'u',
        mode: 'fourchette',
        prixMin: 4000,
        prixMax: 3000,
      );
      expect(
        ProduitsRepository.valider(inverse, creation: true)['prixMax'],
        'Le prix maximum doit être supérieur ou égal au prix minimum.',
      );
    });

    test('sur devis : aucun prix exigé', () {
      const devis = FormulaireProduit(
        nom: 'Cage sur mesure',
        categorieId: cat,
        unite: 'u',
        mode: 'quote',
      );
      expect(ProduitsRepository.valider(devis, creation: true), isEmpty);
    });

    test('TVA hors 0–100 et seuil négatif sont refusés', () {
      const f = FormulaireProduit(
        nom: 'X',
        categorieId: cat,
        unite: 'u',
        mode: 'quote',
        tva: 120,
        seuil: -1,
      );
      expect(
        ProduitsRepository.valider(f, creation: true).keys,
        containsAll(['tva', 'seuil']),
      );
    });
  });

  group('enregistrement local', () {
    test('⚠️ créé tout de suite, en attente, avec un SKU provisoire', () async {
      final p = await depot().creer(valide);

      expect(p.syncStatus, SyncStatus.pending);
      expect(p.sku, startsWith('LOC-'));
      expect(p.id, hasLength(36));
      expect(p.stockQty, 12);
      expect(p.alertThreshold, 5);
      expect(await db.select(db.products).get(), hasLength(1));
    });

    test('sur devis : aucun prix gardé, même saisi', () async {
      const devis = FormulaireProduit(
        nom: 'Cage',
        categorieId: cat,
        unite: 'u',
        mode: 'quote',
        prixMin: 999,
        prixMax: 9999,
      );
      final p = await depot().creer(devis);

      expect(p.priceMin, isNull);
      expect(p.priceMax, isNull);
      expect(p.pricingMode, 'quote');
    });

    test('⚠️ la modification ne change NI le stock NI le SKU', () async {
      final cree = await depot().creer(valide);
      await (db.update(db.products)..where((x) => x.id.equals(cree.id))).write(
        const ProductsCompanion(
          syncStatus: Value(SyncStatus.synced),
          sku: Value('AVI-007'),
        ),
      );

      final p = await depot().modifier(
        cree.id,
        const FormulaireProduit(
          nom: 'Renommé',
          categorieId: cat,
          unite: 'u',
          mode: 'fourchette',
          prixMin: 3500,
          prixMax: 4500,
          stock: 9999,
          seuil: 5,
        ),
      );

      expect(p.name, 'Renommé');
      expect(p.priceMin, 3500);
      expect(p.stockQty, 12, reason: 'un stock se corrige par un ajustement');
      expect(p.sku, 'AVI-007');
      expect(p.syncStatus, SyncStatus.pending, reason: 'à renvoyer');
    });
  });

  group('synchronisation du produit', () {
    SyncEngine moteur(_Tirage serveur) => SyncEngine(
      database: db,
      client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
        ..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _ConnectiviteFeinte(),
    );

    Map<String, dynamic> tirage([List<dynamic>? produits]) => {
      'server_time': '2026-10-08T12:00:00.000Z',
      'product_categories': <dynamic>[],
      'products': produits ?? <dynamic>[],
      'livestock_lots': <dynamic>[],
    };

    test('⚠️ un produit créé part au push, puis est acquitté', () async {
      final p = await depot().creer(valide);
      final serveur = _Tirage(
        tirage(),
        reponsePush: {
          'products': {
            'accepted': [p.id],
            'rejected': [],
          },
        },
      );

      await moteur(serveur).synchroniser();

      final envoye = (serveur.envois.single['products'] as List).single as Map;
      expect(envoye['id'], p.id);
      expect(envoye['name'], 'Poulet fermier');
      expect(envoye['stock_qty'], 12);
      expect(
        (await depot().produit(p.id))!.syncStatus,
        SyncStatus.synced,
        reason: 'acquitté seulement sur réponse du serveur',
      );
    });

    test('⚠️ refusé par le serveur : conflit, jamais réputé envoyé', () async {
      final p = await depot().creer(valide);
      final serveur = _Tirage(
        tirage(),
        reponsePush: {
          'products': {
            'accepted': [],
            'rejected': [
              {'id': p.id, 'reason': 'Vous ne pouvez pas créer de produit.'},
            ],
          },
        },
      );

      await moteur(serveur).synchroniser();

      expect((await depot().produit(p.id))!.syncStatus, SyncStatus.conflict);
    });

    test("⚠️ le tirage n'écrase PAS un produit en attente", () async {
      final p = await depot().creer(valide);
      final serveur = _Tirage(
        tirage([produitServeur(nom: 'Version du serveur')]),
      );

      // Le serveur ne reconnaît pas encore le produit (pas d'acquittement).
      await moteur(serveur).synchroniser();

      final local = await depot().produit(p.id);
      expect(local, isNotNull);
      expect(local!.name, 'Poulet fermier');
    });

    test('après acquittement, le tirage rend le SKU définitif', () async {
      final p = await depot().creer(valide);
      await (db.update(db.products)..where((x) => x.id.equals(p.id))).write(
        const ProductsCompanion(syncStatus: Value(SyncStatus.synced)),
      );

      final json = produitServeur()..['id'] = p.id;
      await moteur(_Tirage(tirage([json]))).synchroniser();

      expect((await depot().produit(p.id))!.sku, 'AVI-007');
    });
  });

  group('absorption du tirage', () {
    SyncEngine moteur(Map<String, dynamic> pull) => SyncEngine(
      database: db,
      client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
        ..interceptors.add(_Tirage(pull)),
      deviceId: 'poste-test',
      connectivity: _ConnectiviteFeinte(),
    );

    Map<String, dynamic> tirage({Object? especes, Object? produits}) => {
      'server_time': '2026-10-08T12:00:00.000Z',
      'product_categories': <dynamic>[],
      'products': produits ?? <dynamic>[],
      'livestock_lots': <dynamic>[],
      'livestock_species': ?especes,
    };

    test(
      'espèces remplacées, bloc absent sans effet, liste vide = aucune',
      () async {
        await moteur(
          tirage(
            especes: [
              {'id': esp, 'code': 'cuniculture', 'label': 'Lapins'},
              {
                'id': 'ffffffff-0000-4000-8000-ffffffffffff',
                'code': 'aviculture',
                'label': 'Volailles',
              },
            ],
          ),
        ).synchroniser();
        expect(await db.select(db.livestockSpecies).get(), hasLength(2));

        // Serveur plus ancien : rien n'est effacé.
        await moteur(tirage()).synchroniser();
        expect(await db.select(db.livestockSpecies).get(), hasLength(2));

        // Une espèce éteinte côté serveur disparaît d'ici.
        await moteur(
          tirage(
            especes: [
              {'id': esp, 'code': 'cuniculture', 'label': 'Lapins'},
            ],
          ),
        ).synchroniser();
        expect((await db.select(db.livestockSpecies).get()).map((e) => e.id), [
          esp,
        ]);

        // Liste vide : aucun module actif, c'est une réponse.
        await moteur(tirage(especes: <dynamic>[])).synchroniser();
        expect(await db.select(db.livestockSpecies).get(), isEmpty);
      },
    );

    test('la description du produit descend avec le tirage', () async {
      await moteur(tirage(produits: [produitServeur()])).synchroniser();

      final p = await db.select(db.products).getSingle();
      expect(p.description, 'Vif');
      expect(p.sku, 'AVI-007');
    });
  });

  group('formulaire', () {
    Future<void> monter(
      WidgetTester tester,
      ProduitsRepository d, {
      String? id,
      void Function({required bool enregistre})? fin,
    }) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AjouterProduitScreen(
              depot: d,
              produitId: id,
              onTermine: fin ?? ({required bool enregistre}) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('porte les libellés du prototype en création', (tester) async {
      await monter(tester, depot());

      for (final t in [
        'Ajouter un Produit',
        'Nom du produit *',
        'Catégorie *',
        'Unité de comptage *',
        'Mode de Tarification *',
        'Fourchette',
        'Sur devis',
        'Prix Min (FCFA) *',
        'Prix Max (FCFA) *',
        'Stock Initial',
        "Seuil d'Alerte",
        'TVA (%)',
        'Description',
        'Annuler',
        'Enregistrer',
      ]) {
        expect(find.text(t), findsWidgets, reason: t);
      }
    });

    testWidgets('« Sur devis » masque la fourchette', (tester) async {
      await monter(tester, depot());

      await tester.tap(find.byKey(const Key('produit-mode-quote')));
      await tester.pumpAndSettle();

      expect(find.text('Prix Min (FCFA) *'), findsNothing);
      expect(find.byKey(const Key('produit-sur-devis')), findsOneWidget);
    });

    testWidgets("⚠️ une saisie invalide n'écrit rien", (tester) async {
      await monter(tester, depot());

      await tester.tap(find.byKey(const Key('produit-enregistrer')));
      await tester.pumpAndSettle();

      expect(await db.select(db.products).get(), isEmpty);
      expect(find.text('Ce champ est obligatoire.'), findsWidgets);
    });

    testWidgets("⚠️ l'enregistrement marche sans réseau et rend la main", (
      tester,
    ) async {
      bool? resultat;
      await monter(
        tester,
        depot(),
        fin: ({required bool enregistre}) => resultat = enregistre,
      );

      await tester.enterText(find.byKey(const Key('produit-nom')), 'Poulet');
      await tester.tap(find.byKey(const Key('produit-categorie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aviculture').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('produit-prixMin')), '3000');
      await tester.enterText(find.byKey(const Key('produit-prixMax')), '4000');

      await tester.tap(find.byKey(const Key('produit-enregistrer')));
      await tester.pumpAndSettle();

      expect(resultat, isTrue);
      // ⚠️ Aucun réseau en jeu : le produit est local et en attente.
      final p = await db.select(db.products).getSingle();
      expect(p.name, 'Poulet');
      expect(p.syncStatus, SyncStatus.pending);
    });

    testWidgets('en modification : champs préremplis, pas de stock initial', (
      tester,
    ) async {
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: idProduit,
              sku: 'AVI-007',
              name: 'Poulet fermier',
              unit: 'u',
              pricingMode: 'fourchette',
              categoryId: const Value(cat),
              priceMin: const Value(3000),
              priceMax: const Value(4000),
              alertThreshold: const Value(5),
            ),
          );

      await monter(tester, depot(), id: idProduit);

      expect(find.text('Modifier le Produit'), findsOneWidget);
      expect(find.text('Poulet fermier'), findsOneWidget);
      expect(find.text('3000'), findsOneWidget);
      expect(find.text('Stock Initial'), findsNothing);
      expect(find.byKey(const Key('produit-stock-ajustement')), findsOneWidget);
      expect(find.text('Enregistrer les modifications'), findsOneWidget);
    });
  });

  group('catalogue', () {
    testWidgets('avec le dépôt, « Nouveau Produit » ouvre le formulaire', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: CatalogueProduitsScreen(
            depot: StocksRepository(database: db, deviceId: 'poste-test'),
            produits: depot(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nouveau-produit')));
      await tester.pumpAndSettle();
      expect(find.text('Ajouter un Produit'), findsOneWidget);

      await tester.tap(find.byKey(const Key('produit-annuler')));
      await tester.pumpAndSettle();
      expect(find.text('Catalogue Produits'), findsWidgets);
    });
  });
}
