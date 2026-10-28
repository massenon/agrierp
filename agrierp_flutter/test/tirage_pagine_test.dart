import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/perimetre_tirage.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/sync/coherence_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket S-T4 (méthode TATACORA) — TIRAGE PAGINÉ, ET LIMITÉ AUX TABLES QUE LE COMPTE LIT, côté poste.
///
/// Verrouillé ici :
///  - un serveur ANCIEN (réponse sans `page_suivante`) : une seule requête, comme avant ;
///  - plusieurs pages : le jeton rendu est renvoyé, le même `since` partout, tout est absorbé, le curseur prend le
///    `server_time` de la DERNIÈRE page ;
///  - ⚠️⚠️ échec au milieu : le curseur ne bouge pas, rien n'est perdu, et la reprise ne double rien ;
///  - ⚠️⚠️ une page est absorbée dans UNE transaction : un refus strict annule toute la page ;
///  - une ligne servie sans sa pièce (pièce sur une autre page) est refusée : le serveur ne doit jamais les séparer ;
///  - périmètre : changement de rôle (table ajoutée) → tirage complet, une fois ; périmètre qui rétrécit → rien
///    n'est vidé ; intersection des pages ; resynchronisations uniques écrites même sans grand livre servi ;
///  - contrôle de cohérence : une table hors périmètre n'est pas contrôlée ;
///  - PARITÉ EXÉCUTÉE : le VRAI tirage paginé du serveur (PHP), absorbé page à page, donne au poste exactement ce
///    que donne le tirage complet ; et le caissier ne reçoit ni le grand livre ni le journal.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Serveur feint. [jeu] rend les pages selon le `since` reçu (null : tirage complet) ; chaque page désigne la
/// suivante par son jeton `page_suivante`, comme le vrai serveur.
class _Serveur extends Interceptor {
  List<Map<String, dynamic>> Function(String? since) jeu = (_) => [
    {'server_time': '2026-10-19T12:00:00+00:00'},
  ];

  /// Paramètres de chaque requête de tirage, dans l'ordre.
  final List<Map<String, dynamic>> requetes = [];

  /// Numéro de page (1, 2…) qui tombe UNE fois en panne réseau.
  int? panneALaPage;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{},
        ),
      );
      return;
    }
    final parametres = Map<String, dynamic>.of(options.queryParameters);
    requetes.add(parametres);
    final pages = jeu(parametres['since'] as String?);
    final jeton = parametres['curseur_page'];
    final i = jeton == null
        ? 0
        : pages.indexWhere((p) => p['page_suivante'] == jeton) + 1;
    if (panneALaPage == i + 1) {
      panneALaPage = null;
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'coupure du réseau',
        ),
      );
      return;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: pages[i],
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;

  const porc = 'd1d2d3d4-0000-4000-8000-00000000000c';
  const inconnu = 'd1d2d3d4-0000-4000-8000-0000000000ff';
  const curseurPrecedent = '2026-10-18T12:00:00.000Z';

  String vente(int n) => 'a1b2c3d4-1111-4000-8000-00000000000$n';
  String ligne(int n, int k) => 'b1b2c3d4-2222-4000-8000-0000000000$n$k';

  Map<String, dynamic> produit() => {
    'id': porc,
    'sku': 'POR-CHA',
    'name': 'Porc charcutier',
    'unit': 'tête',
    'pricing_mode': 'fourchette',
    'is_active': true,
  };

  /// Une vente servie et SES lignes (deux), comme le serveur les met dans une même page.
  Map<String, List<Map<String, dynamic>>> venteEtLignes(int n) => {
    'sales': [
      {
        'id': vente(n),
        'payment_mode': 'especes',
        'total': 60000,
        'status': 'validee',
        'sold_at': '2026-10-10T09:00:00+00:00',
      },
    ],
    'sale_lines': [
      for (var k = 1; k <= 2; k++)
        {
          'id': ligne(n, k),
          'sale_id': vente(n),
          'product_id': porc,
          'lot_id': null,
          'qty': 1,
          'unit_price': 30000,
          'manual_total_amount': 30000,
        },
    ],
  };

  const baseServies = [
    'products',
    'sales',
    'sale_lines',
    'stock_movements',
    'customer_reminders',
  ];

  /// Pages d'un tirage paginé : `tables_servies` sur chacune, `server_time` sur la dernière, jetons entre elles.
  List<Map<String, dynamic>> pagine(
    List<Map<String, dynamic>> contenus, {
    List<String> servies = baseServies,
    String serverTime = '2026-10-19T12:00:00+00:00',
  }) => [
    for (var i = 0; i < contenus.length; i++)
      {
        'page': i + 1,
        'tables_servies': servies,
        ...contenus[i],
        if (i == contenus.length - 1) 'server_time': serverTime,
        'page_suivante': i == contenus.length - 1 ? null : 'jeton-${i + 2}',
      },
  ];

  /// Les trois pages ordinaires : le produit et la vente 1, puis la vente 2, puis la vente 3.
  List<Map<String, dynamic>> troisPages() => pagine([
    {
      'products': [produit()],
      ...venteEtLignes(1),
    },
    venteEtLignes(2),
    venteEtLignes(3),
  ]);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 19, 14),
    );
  });

  tearDown(() async => db.close());

  /// Un poste déjà en service : resynchronisations uniques faites, curseur au 18/10 12:00.
  Future<void> posteEnService({Set<String>? perimetre}) async {
    for (final cle in [
      SyncEngine.cleJournalResync,
      SyncEngine.cleJournalResyncCreation,
      SyncEngine.cleFichesResync,
      SyncEngine.cleFichesResyncCategories,
      SyncEngine.cleFichesResyncU10,
      SyncEngine.cleLignesResync,
      SyncEngine.cleRetoursResync,
      SyncEngine.cleMouvementsResync,
      SyncEngine.cleDepensesResync,
      SyncEngine.cleDepensesResyncU14,
      SyncEngine.cleDepensesResyncDep1,
    ]) {
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: cle, value: '1'),
          );
    }
    await db.noterEtatDeSynchronisation(tire: DateTime.parse(curseurPrecedent));
    if (perimetre != null) await PerimetreTirage.ecrire(db, perimetre);
  }

  Future<DateTime?> curseur() async =>
      (await db.etatDeSynchronisation())?.lastPulledAt?.toUtc();

  Future<Set<String>> ventes() async => {
    for (final v in await db.select(db.sales).get()) v.id,
  };

  Future<List<SaleLine>> lignes() => db.select(db.saleLines).get();

  test(
    'serveur ANCIEN (réponse sans page_suivante) : une seule requête, curseur avancé, périmètre effacé',
    () async {
      await posteEnService(perimetre: {'products'});
      serveur.jeu = (_) => [
        {
          'server_time': '2026-10-19T12:00:00+00:00',
          'products': [produit()],
          ...venteEtLignes(1),
        },
      ];

      await moteur.synchroniser();

      expect(serveur.requetes, hasLength(1));
      expect(serveur.requetes.single['page'], 1);
      expect(serveur.requetes.single['since'], curseurPrecedent);
      expect(await ventes(), {vente(1)});
      expect(await curseur(), DateTime.utc(2026, 10, 19, 12));
      // Il a tout servi, non filtré : le périmètre n'est plus connu (rien à resynchroniser plus tard).
      expect(await PerimetreTirage.lire(db), isNull);
    },
  );

  test(
    'plusieurs pages : jeton renvoyé, même since, tout absorbé, curseur de la DERNIÈRE page',
    () async {
      await posteEnService();
      serveur.jeu = (_) => troisPages();

      await moteur.synchroniser();

      expect(serveur.requetes.map((r) => r['page']), [1, 2, 3]);
      expect(serveur.requetes.map((r) => r['curseur_page']), [
        null,
        'jeton-2',
        'jeton-3',
      ]);
      expect(serveur.requetes.map((r) => r['since']).toSet(), {
        curseurPrecedent,
      });
      expect(await ventes(), {vente(1), vente(2), vente(3)});
      expect(await lignes(), hasLength(6));
      expect(await curseur(), DateTime.utc(2026, 10, 19, 12));
      expect(await PerimetreTirage.lire(db), baseServies.toSet());
    },
  );

  test(
    '⚠️⚠️ échec au milieu : curseur inchangé, rien de perdu, la reprise ne double rien',
    () async {
      await posteEnService();
      serveur.jeu = (_) => troisPages();
      serveur.panneALaPage = 2;

      await expectLater(moteur.synchroniser(), throwsA(isA<DioException>()));

      // La page 1 est absorbée (sa transaction est faite), mais le curseur n'a PAS bougé.
      expect(await ventes(), {vente(1)});
      expect(await curseur(), DateTime.parse(curseurPrecedent));

      serveur.requetes.clear();
      await moteur.synchroniser();

      // La reprise repart du MÊME curseur, depuis la page 1 ; ce qui revient est remplacé, jamais doublé.
      expect(serveur.requetes.first['since'], curseurPrecedent);
      expect(serveur.requetes.first['curseur_page'], isNull);
      expect(await ventes(), {vente(1), vente(2), vente(3)});
      final toutes = await lignes();
      expect(toutes, hasLength(6));
      expect(toutes.where((l) => l.saleId == vente(1)), hasLength(2));
      expect(await curseur(), DateTime.utc(2026, 10, 19, 12));
    },
  );

  test(
    '⚠️⚠️ une page est UNE transaction : un refus strict annule toute la page, et le curseur reste',
    () async {
      await posteEnService();
      serveur.jeu = (_) => pagine([
        {
          'products': [produit()],
          ...venteEtLignes(1),
        },
        {
          // La vente 2 et ses lignes sont valides ; le mouvement de stock porte un produit inconnu : refus strict.
          ...venteEtLignes(2),
          'stock_movements': [
            {
              'id': 'c1c2c3c4-3333-4000-8000-000000000001',
              'product_id': inconnu,
              'type': 'sortie',
              'quantity': 1,
              'reference_type': 'sale',
              'reference_id': vente(2),
              'reason': null,
              'movement_date': '2026-10-10 09:00:00',
            },
          ],
        },
      ]);

      await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));

      expect(
        await ventes(),
        {vente(1)},
        reason:
            'la vente 2, absorbée AVANT le refus dans la même page, est annulée',
      );
      expect((await lignes()).where((l) => l.saleId == vente(2)), isEmpty);
      expect(await curseur(), DateTime.parse(curseurPrecedent));
    },
  );

  test(
    'une ligne servie sur une autre page que sa vente est refusée : le serveur ne doit jamais les séparer',
    () async {
      await posteEnService();
      final page1 = venteEtLignes(1);
      serveur.jeu = (_) => pagine([
        {
          'products': [produit()],
          'sales': page1['sales'],
          'sale_lines': <Map<String, dynamic>>[],
        },
        {'sales': <Map<String, dynamic>>[], 'sale_lines': page1['sale_lines']},
      ]);

      await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));

      expect(await lignes(), isEmpty);
      expect(await curseur(), DateTime.parse(curseurPrecedent));
    },
  );

  test(
    'changement de rôle : une table AJOUTÉE au périmètre fait repartir un tirage complet, une fois',
    () async {
      await posteEnService(perimetre: {'products', 'sales', 'sale_lines'});
      // Au tirage incrémental, le serveur sert désormais aussi le grand livre : la page 1 n'est pas absorbée.
      serveur.jeu = (since) => since == null
          ? pagine(
              [
                {
                  'products': [produit()],
                  ...venteEtLignes(2),
                },
              ],
              servies: ['products', 'sales', 'sale_lines', 'stock_movements'],
            )
          : pagine(
              [
                {
                  'products': [produit()],
                  ...venteEtLignes(1),
                },
              ],
              servies: ['products', 'sales', 'sale_lines', 'stock_movements'],
            );

      await moteur.synchroniser();

      expect(serveur.requetes.map((r) => r['since']), [curseurPrecedent, null]);
      expect(await ventes(), {
        vente(2),
      }, reason: 'rien de la réponse incrémentale n\'est absorbé');
      expect(await PerimetreTirage.lire(db), {
        'products',
        'sales',
        'sale_lines',
        'stock_movements',
      });

      // La synchronisation suivante est de nouveau incrémentale.
      serveur.requetes.clear();
      await moteur.synchroniser();
      expect(serveur.requetes.first['since'], isNotNull);
    },
  );

  test(
    'premier tirage paginé d\'un poste en service (périmètre inconnu : il avait tout reçu) : incrémental',
    () async {
      await posteEnService();
      serveur.jeu = (_) => troisPages();

      await moteur.synchroniser();

      expect(serveur.requetes.map((r) => r['since']).toSet(), {
        curseurPrecedent,
      });
    },
  );

  test(
    'périmètre qui RÉTRÉCIT : aucun tirage complet, la table qui n\'est plus servie n\'est pas vidée',
    () async {
      await posteEnService(perimetre: {...baseServies, 'customer_reminders'});
      await db
          .into(db.customerReminders)
          .insert(
            CustomerRemindersCompanion.insert(
              deviceId: 'serveur',
              updatedAt: DateTime(2026, 1, 1),
              syncStatus: const Value(SyncStatus.synced),
              id: 'e1e2e3e4-4444-4000-8000-000000000001',
              customerId: 'e1e2e3e4-5555-4000-8000-000000000001',
              channel: 'appel',
            ),
          );
      final servies = ['products', 'sales', 'sale_lines'];
      serveur.jeu = (_) => pagine([
        {
          'products': [produit()],
          ...venteEtLignes(1),
        },
      ], servies: servies);

      await moteur.synchroniser();

      expect(serveur.requetes, hasLength(1));
      expect(serveur.requetes.single['since'], curseurPrecedent);
      expect(await db.select(db.customerReminders).get(), hasLength(1));
      expect(await PerimetreTirage.lire(db), servies.toSet());
    },
  );

  test(
    'le périmètre gardé est l\'INTERSECTION des pages (un droit retiré pendant le tirage compte comme retiré)',
    () async {
      await posteEnService();
      final pages = troisPages();
      pages[2]['tables_servies'] = ['products', 'sales', 'sale_lines'];
      serveur.jeu = (_) => pages;

      await moteur.synchroniser();

      expect(await PerimetreTirage.lire(db), {
        'products',
        'sales',
        'sale_lines',
      });
    },
  );

  test(
    'resynchronisations uniques écrites au tirage paginé même sans grand livre servi (caissier)',
    () async {
      // Poste neuf : aucune resynchronisation faite, le premier tirage est complet.
      serveur.jeu = (_) => pagine(
        [
          {
            'products': [produit()],
            ...venteEtLignes(1),
          },
        ],
        servies: ['products', 'sales', 'sale_lines'],
      );

      await moteur.synchroniser();
      expect(serveur.requetes.single['since'], isNull);
      expect(
        await (db.select(db.appSettings)
              ..where((t) => t.key.equals(SyncEngine.cleMouvementsResync)))
            .getSingleOrNull(),
        isNotNull,
        reason: 'sinon chaque tirage du caissier resterait complet',
      );

      serveur.requetes.clear();
      await moteur.synchroniser();
      expect(serveur.requetes.single['since'], isNotNull);
    },
  );

  test(
    'contrôle de cohérence : une table hors du périmètre n\'est pas contrôlée',
    () async {
      await PerimetreTirage.ecrire(db, {
        'sales',
        'purchases',
        'livestock_daily_entries',
      });
      final controle = ControleCoherenceRepository(
        database: db,
        serveur: (_) async => {
          'tables': {
            'sales': {'libelle': 'Ventes', 'jours': <String, dynamic>{}},
          },
        },
        maintenant: () => DateTime(2026, 10, 19, 14),
      );

      final resultat = await controle.verifier();

      expect(resultat.tables.map((t) => t.table), [
        'sales',
        'purchases',
        'livestock_daily_entries',
      ]);

      // Périmètre inconnu : toutes les tables sont contrôlées, comme avant S-T4.
      await PerimetreTirage.effacer(db);
      expect((await controle.verifier()).tables, hasLength(8)); // U13 : les dépenses y entrent
    },
  );

  test(
    'PARITÉ EXÉCUTÉE : le VRAI tirage paginé, absorbé page à page, donne au poste ce que donne le tirage complet',
    () async {
      // Trois bases ouvertes l'une après l'autre dans ce test : voulu.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final sortie =
          executerPhp(
                '<?php\n$amorceApplication\n$_scriptTirages',
                const <String, dynamic>{},
                application: true,
              )
              as Map<String, dynamic>;

      List<Map<String, dynamic>> pagesDe(String role) => [
        for (final p in sortie[role] as List)
          (p as Map).cast<String, dynamic>(),
      ];
      final pagesAdmin = pagesDe('admin');
      expect(
        pagesAdmin.length,
        greaterThan(3),
        reason: 'la taille 4 impose plusieurs pages',
      );
      // Sur chaque page, pas une ligne sans sa pièce.
      for (final p in pagesAdmin) {
        final pieces = {for (final v in p['sales'] as List) (v as Map)['id']};
        for (final l in p['sale_lines'] as List) {
          expect(pieces, contains((l as Map)['sale_id']));
        }
        final ecritures = {
          for (final e in p['accounting_entries'] as List) (e as Map)['id'],
        };
        for (final l in p['accounting_entry_lines'] as List) {
          expect(ecritures, contains((l as Map)['entry_id']));
        }
      }

      Future<Map<String, Set<String>>> absorber(
        List<Map<String, dynamic>> pages,
      ) async {
        final base = AppDatabase.forTesting(NativeDatabase.memory());
        final serveurReel = _Serveur()..jeu = (_) => pages;
        try {
          await SyncEngine(
            database: base,
            client: Dio()..interceptors.add(serveurReel),
            deviceId: 'poste-test',
            connectivity: _Connectivite(),
            maintenant: () => DateTime(2026, 10, 19, 14),
          ).synchroniser();
          expect(serveurReel.requetes, hasLength(pages.length));
          return {
            'ventes': {
              for (final v in await base.select(base.sales).get())
                '${v.id} ${v.total}',
            },
            'lignes de vente': {
              for (final l in await base.select(base.saleLines).get())
                '${l.id} ${l.saleId} ${l.manualTotalAmount}',
            },
            'achats': {
              for (final a in await base.select(base.purchases).get())
                '${a.id} ${a.total}',
            },
            "lignes d'achat": {
              for (final l in await base.select(base.purchaseLines).get())
                '${l.id} ${l.purchaseId} ${l.qty} ${l.unitPrice}',
            },
            'mouvements': {
              for (final m in await base.select(base.stockMovements).get())
                '${m.id} ${m.productId} ${m.quantity}',
            },
            'écritures': {
              for (final e in await base.select(base.accountingEntries).get())
                e.id,
            },
            "lignes d'écriture": {
              for (final l
                  in await base.select(base.accountingEntryLines).get())
                '${l.id} ${l.entryId} ${l.debit} ${l.credit}',
            },
            'périmètre': {...?await PerimetreTirage.lire(base)},
          };
        } finally {
          await base.close();
        }
      }

      final complet = await absorber([
        (sortie['complet'] as Map).cast<String, dynamic>(),
      ]);
      final pagine = await absorber(pagesAdmin);

      expect(complet['ventes'], hasLength(7));
      expect(complet['lignes de vente'], hasLength(13));
      expect(complet['mouvements'], hasLength(7));
      expect(complet["lignes d'écriture"], hasLength(8));
      for (final cle in complet.keys.where((c) => c != 'périmètre')) {
        expect(pagine[cle], complet[cle], reason: cle);
      }

      // Le caissier : mêmes ventes, ni grand livre ni journal (ses écrans ne les lisent pas).
      final pagesCaissier = pagesDe('caissier');
      final caissier = await absorber(pagesCaissier);
      expect(caissier['ventes'], complet['ventes']);
      expect(caissier['lignes de vente'], complet['lignes de vente']);
      expect(caissier['mouvements'], isEmpty);
      expect(caissier['écritures'], isEmpty);
      expect(caissier['périmètre'], {
        for (final t in pagesCaissier.first['tables_servies'] as List)
          t as String,
      });
      expect(caissier['périmètre'], isNot(contains('stock_movements')));
    },
    skip: sautSansPhp(),
  );
}

/// Script PHP de la parité : sept ventes (une à trois lignes, chacune avec son mouvement de stock), trois achats de
/// deux lignes, quatre écritures (deux lignes chacune), puis le VRAI tirage (`SyncController::pull`) : toutes les
/// pages pour l'administrateur et pour le caissier (taille 4), et le tirage complet d'un poste ancien.
const _scriptTirages = r'''
Carbon\Carbon::setTestNow('2026-10-19 08:00:00');
Illuminate\Support\Facades\Artisan::call('db:seed', ['--class' => 'Database\\Seeders\\RolesAndPermissionsSeeder', '--force' => true]);
$comptes = [];
foreach (['admin', 'caissier'] as $role) {
    $compte = App\Models\User::create([
        'name' => 'Compte '.$role, 'username' => $role, 'email' => $role.'@fermeolouwachegoun.com',
        'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
    ]);
    $compte->assignRole($role);
    $comptes[$role] = $compte;
}
$categorie = App\Models\ProductCategory::create(['label' => 'Porciculture', 'is_active' => true]);
$porc = App\Models\Product::create([
    'sku' => 'POR-CHA', 'name' => 'Porc charcutier', 'category_id' => $categorie->id, 'unit' => 'u',
    'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 100000, 'stock_qty' => 1000, 'is_active' => true,
]);
$fournisseur = App\Models\Supplier::create(['name' => 'Fournisseur', 'category' => 'Aliments', 'is_active' => true]);
App\Models\FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
$caisse = App\Models\ChartOfAccount::create(['code' => '531', 'label' => 'Caisse', 'class' => 5, 'is_active' => true]);
$produits = App\Models\ChartOfAccount::create(['code' => '701', 'label' => 'Ventes', 'class' => 7, 'is_active' => true]);
$instant = Carbon\Carbon::parse('2026-10-19 08:00:00');
for ($i = 0; $i < 7; $i++) {
    $instant = $instant->copy()->addSecond();
    Carbon\Carbon::setTestNow($instant);
    $nombre = $i % 3 + 1;
    $vente = App\Models\Sale::create([
        'payment_mode' => 'especes', 'subtotal' => 1000 * $nombre, 'total' => 1000 * $nombre, 'status' => 'validee',
    ]);
    for ($k = 0; $k < $nombre; $k++) {
        App\Models\SaleLine::create([
            'sale_id' => $vente->id, 'product_id' => $porc->id, 'qty' => 1, 'unit_price' => 1000,
            'manual_total_amount' => 1000, 'is_manual_price' => true,
        ]);
    }
    app(App\Actions\AdjustStockAction::class)->execute($porc, -1, 'sale', $vente->id);
}
for ($i = 0; $i < 3; $i++) {
    $instant = $instant->copy()->addSecond();
    Carbon\Carbon::setTestNow($instant);
    $achat = App\Models\Purchase::create([
        'supplier_id' => $fournisseur->id, 'payment_mode' => 'especes', 'total' => 2000, 'purchase_date' => '2026-10-05',
    ]);
    for ($k = 0; $k < 2; $k++) {
        App\Models\PurchaseLine::create(['purchase_id' => $achat->id, 'product_id' => $porc->id, 'qty' => 2, 'unit_price' => 500]);
    }
}
for ($i = 1; $i <= 4; $i++) {
    app(App\Services\AccountingEntryService::class)->recordManual($caisse->id, $produits->id, 1000 * $i, '2026-10-05', 'OD-000'.$i);
}
Carbon\Carbon::setTestNow('2026-10-19 10:00:00');
$tirer = function ($compte, array $parametres) {
    $requete = Illuminate\Http\Request::create('/api/sync/pull', 'GET', $parametres);
    $requete->setUserResolver(fn () => $compte);
    return app(App\Http\Controllers\Api\SyncController::class)->pull($requete)->getData(true);
};
$sortie = [];
foreach ($comptes as $role => $compte) {
    $pages = [];
    $jeton = null;
    $numero = 1;
    do {
        $parametres = ['page' => $numero, 'taille' => 4];
        if ($jeton !== null) {
            $parametres['curseur_page'] = $jeton;
        }
        $page = $tirer($compte, $parametres);
        $pages[] = $page;
        $jeton = $page['page_suivante'];
        $numero++;
    } while ($jeton !== null && $numero < 200);
    $sortie[$role] = $pages;
}
$sortie['complet'] = $tirer($comptes['admin'], []);
echo json_encode($sortie);
''';
