import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/achats/achats_commandes_screen.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket U8 — « ÉCARTS / RETOURS » ET « CATÉGORIE » DE LA LISTE DES ACHATS, COMME LE WEB.
///
///  - Le web compte des LIGNES de retour (`PurchaseReturn::count()`), le poste comptait des achats retournés :
///    `purchase_returns` descend désormais avec ses achats (`_absorberRetoursDAchat`), et la carte compte les lignes.
///  - La colonne « Catégorie » montrait la catégorie du FOURNISSEUR ; le web montre la catégorie de PRODUIT de la
///    première ligne de l'achat.
///
/// Verrouillé ici : l'absorbeur (remplacement des lignes `synced`, ⚠️⚠️ demandes locales `pending`/`conflict`
/// jamais touchées, refus stricts, clé absente), la resynchronisation unique `retours_resync_u8`, le compte de la
/// carte (repli sur les lignes d'achat d'un retour acquitté pas encore servi), et une PARITÉ EXÉCUTÉE : le vrai PHP
/// crée achats, lignes et retours, sert son VRAI tirage au poste, et `ListeAchats` (carte et colonne) est comparé à
/// ce que le poste affiche après absorption.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Serveur feint : sert [tirage] au tirage, et accepte tout ce qu'on lui envoie — ou rien, si [acquitter] est faux
/// (un envoi sans accusé : les saisies du poste restent `pending`).
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-19T12:00:00Z'};
  bool acquitter = true;

  /// `since` de chaque tirage (null : tirage complet).
  final List<Object?> demandes = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            if (acquitter)
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
    demandes.add(options.queryParameters['since']);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: tirage,
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late AchatsRepository depot;

  const provende = 'd1d2d3d4-0000-4000-8000-00000000000b';
  const fournisseur = 'f0f0f0f0-0000-4000-8000-000000000001';
  const achatA = 'abcdef01-4444-4000-8000-000000000001';
  const achatB = 'abcdef01-5555-4000-8000-000000000002';
  const achatC = 'abcdef01-6666-4000-8000-000000000003';

  String uuid(String graine) => graine.padRight(36, '0');

  Map<String, dynamic> achatJson(String id, {String? retourneLe}) => {
    'id': id,
    'supplier_id': fournisseur,
    'supplier_name': 'Provenderie du Plateau',
    'supplier_category': 'Aliments',
    'payment_mode': 'especes',
    'total': 16000,
    'purchase_date': '2026-10-05',
    'has_debt': false,
    'returned_at': retourneLe,
  };

  Map<String, dynamic> ligneAchatJson(String id, String achat) => {
    'id': id,
    'purchase_id': achat,
    'product_id': provende,
    'product_name': 'Provende ponte',
    'qty': 2,
    'unit_price': 8000,
  };

  Map<String, dynamic> retourJson(
    String id,
    String achat, {
    String? motif = 'Sacs éventrés',
    Object? date = '2026-10-12',
  }) => {
    'id': id,
    'purchase_id': achat,
    'return_batch_id': uuid('lot-retour'),
    'purchase_line_id': uuid('la-$id'.substring(0, 10)),
    'product_id': provende,
    'qty': 2,
    'reason': motif,
    'return_date': date,
  };

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 19, 14),
    );
    depot = AchatsRepository(database: db, identifiantPoste: 'poste-test');
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: provende,
            sku: 'ALI-PONTE',
            name: 'Provende ponte',
            unit: 'sac',
            pricingMode: 'fixe',
            syncStatus: const Value(SyncStatus.synced),
          ),
        );
  });

  tearDown(() async => db.close());

  /// Demande de retour saisie SUR CE POSTE pour [achat], au statut [statut].
  Future<void> demandeLocale(String id, String achat, SyncStatus statut) => db
      .into(db.purchaseReturns)
      .insert(
        PurchaseReturnsCompanion.insert(
          id: id,
          deviceId: 'poste-test',
          syncStatus: Value(statut),
          updatedAt: DateTime(2026, 10, 18),
          purchaseId: achat,
          reason: 'Demande du poste',
          returnDate: DateTime(2026, 10, 18),
        ),
      );

  Future<List<RetourFournisseur>> retours() async =>
      (await db.select(db.purchaseReturns).get())
        ..sort((a, b) => a.id.compareTo(b.id));

  group('absorbeur `purchase_returns`', () {
    test(
      'les lignes de retour servies sont absorbées, marquées « serveur »',
      () async {
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'purchases': [achatJson(achatA, retourneLe: '2026-10-12T10:00:00Z')],
          'purchase_lines': [
            ligneAchatJson(uuid('la1'), achatA),
            ligneAchatJson(uuid('la2'), achatA),
          ],
          'purchase_returns': [
            retourJson(uuid('r1'), achatA),
            retourJson(uuid('r2'), achatA, motif: null),
          ],
        };

        await moteur.synchroniser();

        final lus = await retours();
        expect(
          [
            for (final r in lus)
              (
                r.id,
                r.purchaseId,
                r.deviceId,
                r.syncStatus,
                r.reason,
                r.returnDate,
              ),
          ],
          [
            (
              uuid('r1'),
              achatA,
              'serveur',
              SyncStatus.synced,
              'Sacs éventrés',
              DateTime(2026, 10, 12),
            ),
            (
              uuid('r2'),
              achatA,
              'serveur',
              SyncStatus.synced,
              '',
              DateTime(2026, 10, 12),
            ),
          ],
        );
        // Deux LIGNES de retour, comme `PurchaseReturn::count()`.
        expect((await depot.charger()).ecartsEtRetours, 2);
      },
    );

    test(
      'la demande ACQUITTÉE du poste est remplacée par les lignes que le serveur a créées',
      () async {
        await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                id: achatA,
                deviceId: 'serveur',
                updatedAt: DateTime(2026, 10, 5),
                syncStatus: const Value(SyncStatus.synced),
                supplierId: fournisseur,
                paymentMode: 'especes',
                total: 16000,
                purchaseDate: DateTime(2026, 10, 5),
              ),
            );
        await demandeLocale(uuid('lot-retour'), achatA, SyncStatus.synced);
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'purchases': [achatJson(achatA, retourneLe: '2026-10-18T10:00:00Z')],
          'purchase_lines': [
            ligneAchatJson(uuid('la1'), achatA),
            ligneAchatJson(uuid('la2'), achatA),
          ],
          'purchase_returns': [
            retourJson(uuid('r1'), achatA),
            retourJson(uuid('r2'), achatA),
          ],
        };

        await moteur.synchroniser();

        expect((await retours()).map((r) => r.id), [uuid('r1'), uuid('r2')]);
        // 2 lignes, pas 3 : la demande acquittée n'est pas comptée en plus de ses lignes.
        expect((await depot.charger()).ecartsEtRetours, 2);
      },
    );

    for (final statut in [SyncStatus.pending, SyncStatus.conflict]) {
      test(
        '⚠️⚠️ une demande ${statut.name} du poste n est ni effacée, ni écrasée, ni comptée',
        () async {
          await db
              .into(db.purchases)
              .insert(
                PurchasesCompanion.insert(
                  id: achatB,
                  deviceId: 'serveur',
                  updatedAt: DateTime(2026, 10, 5),
                  syncStatus: const Value(SyncStatus.synced),
                  supplierId: fournisseur,
                  paymentMode: 'especes',
                  total: 16000,
                  purchaseDate: DateTime(2026, 10, 5),
                ),
              );
          await demandeLocale(uuid('demande-b'), achatB, statut);
          final avant = await retours();
          // Envoi sans accusé : une demande `pending` reste en attente (une `conflict` ne part pas).
          serveur.acquitter = false;
          // Le web a retourné ce même achat entre-temps : le serveur sert sa ligne de retour.
          serveur.tirage = {
            'server_time': '2026-10-19T12:00:00Z',
            'purchases': [
              achatJson(achatB, retourneLe: '2026-10-12T10:00:00Z'),
            ],
            'purchase_lines': [ligneAchatJson(uuid('lb1'), achatB)],
            'purchase_returns': [retourJson(uuid('rb1'), achatB)],
          };

          await moteur.synchroniser();

          final apres = await retours();
          expect(apres.where((r) => r.id == uuid('demande-b')), avant);
          expect(apres.where((r) => r.deviceId == 'serveur').map((r) => r.id), [
            uuid('rb1'),
          ]);
          // La demande n'est pas comptée ; la ligne du serveur l'est.
          expect((await depot.charger()).ecartsEtRetours, 1);
        },
      );
    }

    group(
      'STRICT : le lot est refusé, rien n est écrit, le curseur n avance pas',
      () {
        Future<void> refuse(Map<String, dynamic> tirage) async {
          serveur.acquitter = false;
          await demandeLocale(uuid('demande-c'), achatC, SyncStatus.pending);
          serveur.tirage = {
            'server_time': '2026-10-19T12:00:00Z',
            'purchases': [
              achatJson(achatA, retourneLe: '2026-10-12T10:00:00Z'),
            ],
            'purchase_lines': [ligneAchatJson(uuid('la1'), achatA)],
            'purchase_returns': [retourJson(uuid('r1'), achatA)],
          };
          await moteur.synchroniser();
          final curseur = (await db.etatDeSynchronisation())?.lastPulledAt;
          final avant = await retours();

          serveur.tirage = {'server_time': '2026-10-19T13:00:00Z', ...tirage};
          await expectLater(
            moteur.synchroniser(),
            throwsA(isA<FormatException>()),
          );

          expect(await retours(), avant);
          expect((await db.etatDeSynchronisation())?.lastPulledAt, curseur);
        }

        test('ligne de retour d un achat non servi (fuite)', () async {
          await refuse({
            'purchases': <Object>[],
            'purchase_returns': [retourJson(uuid('r9'), achatA)],
          });
        });

        test('ligne servie deux fois', () async {
          await refuse({
            'purchases': [achatJson(achatA)],
            'purchase_returns': [
              retourJson(uuid('r1'), achatA),
              retourJson(uuid('r1'), achatA),
            ],
          });
        });

        test('identifiant d une demande locale encore en attente', () async {
          await refuse({
            'purchases': [achatJson(achatC)],
            'purchase_returns': [retourJson(uuid('demande-c'), achatC)],
          });
        });

        test('date illisible', () async {
          await refuse({
            'purchases': [achatJson(achatA)],
            'purchase_returns': [retourJson(uuid('r1'), achatA, date: 'hier')],
          });
        });

        test('motif illisible', () async {
          await refuse({
            'purchases': [achatJson(achatA)],
            'purchase_returns': [
              {...retourJson(uuid('r1'), achatA), 'reason': 12},
            ],
          });
        });
      },
    );

    test(
      'un serveur antérieur à U8 (clé absente) ne touche à aucun retour',
      () async {
        await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                id: achatA,
                deviceId: 'serveur',
                updatedAt: DateTime(2026, 10, 5),
                syncStatus: const Value(SyncStatus.synced),
                supplierId: fournisseur,
                paymentMode: 'especes',
                total: 16000,
                purchaseDate: DateTime(2026, 10, 5),
              ),
            );
        await demandeLocale(uuid('lot-retour'), achatA, SyncStatus.synced);
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'purchases': [achatJson(achatA, retourneLe: '2026-10-18T10:00:00Z')],
          'purchase_lines': [
            ligneAchatJson(uuid('la1'), achatA),
            ligneAchatJson(uuid('la2'), achatA),
          ],
        };

        await moteur.synchroniser();

        expect((await retours()).map((r) => r.id), [uuid('lot-retour')]);
        // Repli : achat retourné sans ligne de retour servie → ses 2 lignes d'achat (une ligne de retour par ligne).
        expect((await depot.charger()).ecartsEtRetours, 2);
      },
    );
  });

  group('resynchronisation unique `retours_resync_u8`', () {
    Future<void> posteEnService() async {
      await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
      for (final cle in [
        SyncEngine.cleJournalResync,
        SyncEngine.cleJournalResyncCreation,
        SyncEngine.cleFichesResync,
        SyncEngine.cleFichesResyncCategories,
        SyncEngine.cleLignesResync,
      ]) {
        await db
            .into(db.appSettings)
            .insert(AppSettingsCompanion.insert(key: cle, value: '1'));
      }
    }

    test(
      '⚠️⚠️ un poste déjà en service redemande TOUT une fois (ses achats retournés sont antérieurs au curseur), puis l incrémental',
      () async {
        await posteEnService();
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'purchases': [achatJson(achatA, retourneLe: '2026-09-12T10:00:00Z')],
          'purchase_lines': [ligneAchatJson(uuid('la1'), achatA)],
          'purchase_returns': [retourJson(uuid('r1'), achatA)],
        };

        await moteur.synchroniser();
        await moteur.synchroniser();

        expect(serveur.demandes.first, isNull, reason: 'sans since, une fois');
        expect(serveur.demandes.last, isNotNull, reason: 'puis incrémental');
        expect(await retours(), hasLength(1));
      },
    );

    test(
      '⚠️ serveur antérieur à U8 (achats servis sans leurs retours) : la resynchronisation N EST PAS marquée faite',
      () async {
        await posteEnService();
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'purchases': [achatJson(achatA)],
          'purchase_lines': [ligneAchatJson(uuid('la1'), achatA)],
        };

        await moteur.synchroniser();
        await moteur.synchroniser();

        expect(serveur.demandes, [null, null]);
      },
    );
  });

  group('carte « Écarts / Retours » et colonne « Catégorie » à l écran', () {
    testWidgets(
      'la carte compte des LIGNES de retour ; la catégorie est celle du PRODUIT de la première ligne',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.runAsync(() async {
          await db
              .into(db.productCategories)
              .insert(
                ProductCategoriesCompanion.insert(
                  id: uuid('cat-ali'),
                  label: 'Provenderie',
                ),
              );
          await (db.update(db.products)..where((p) => p.id.equals(provende)))
              .write(ProductsCompanion(categoryId: Value(uuid('cat-ali'))));
          serveur.tirage = {
            'server_time': '2026-10-19T12:00:00Z',
            'purchases': [
              achatJson(achatA, retourneLe: '2026-10-12T10:00:00Z'),
            ],
            'purchase_lines': [
              ligneAchatJson(uuid('la1'), achatA),
              ligneAchatJson(uuid('la2'), achatA),
              ligneAchatJson(uuid('la3'), achatA),
            ],
            'purchase_returns': [
              retourJson(uuid('r1'), achatA),
              retourJson(uuid('r2'), achatA),
              retourJson(uuid('r3'), achatA),
            ],
          };
          await moteur.synchroniser();
        });

        await tester.pumpWidget(
          MaterialApp(home: AchatsCommandesScreen(depot: depot)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key("onglet-achats-Liste d'Achats")));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('kpi-achats-ecarts')),
            matching: find.text('3'),
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('categorie-achat-0'))).data,
          'Provenderie',
          reason:
              'catégorie du PRODUIT, pas celle du fournisseur (« Aliments »)',
        );
      },
    );
  });

  test(
    'parité exécutée U8 : « Écarts / Retours » et « Catégorie » du poste = ListeAchats, après le VRAI tirage',
    () async {
      // Six achats : deux catégories de produit, un achat sans ligne (« — »), deux achats retournés par le service
      // (une ligne de retour par ligne d'achat), un retour d'AVANT le ticket 15.20 qui ne porte que sur UNE des deux
      // lignes (seul le compte servi est exact), et un achat dont la première ligne n'est pas de la catégorie des
      // suivantes.
      final entree = {
        'achats': [
          {
            'lignes': [0, 1],
            'retour': 'complet',
          },
          {
            'lignes': [1, 0, 0],
            'retour': null,
          },
          {'lignes': <int>[], 'retour': null},
          {
            'lignes': [0, 0, 1],
            'retour': 'complet',
          },
          {
            'lignes': [1, 1],
            'retour': 'ancien_partiel',
          },
          {
            'lignes': [0],
            'retour': null,
          },
        ],
      };
      final sortie =
          executerPhp(
                '<?php\n$amorceApplication\n$_scriptPariteAchats',
                entree,
                application: true,
              )
              as Map<String, dynamic>;

      serveur.tirage = (sortie['tirage'] as Map).cast<String, dynamic>();
      await moteur.synchroniser();
      final d = await depot.charger();

      expect(
        sortie['ecarts'],
        2 + 3 + 1,
        reason: 'la grille couvre les trois cas',
      );
      expect(d.ecartsEtRetours, sortie['ecarts']);
      expect({
        for (final l in d.achats) l.achat.id: l.categorie ?? '—',
      }, (sortie['categories'] as Map).cast<String, String>());
      expect((sortie['categories'] as Map).values.toSet(), {
        'Aliments bétail',
        'Médicaments',
        '—',
      }, reason: 'la grille couvre deux catégories et l achat sans ligne');
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Script PHP de la parité : crée catégories, produits, un fournisseur de catégorie « Fournitures », des achats avec
/// leurs lignes (une seconde d'écart entre chaque : la « première ligne » est sans ambiguïté sur toute base) et
/// leurs retours, puis rend la carte et la colonne de `ListeAchats` et le VRAI tirage (`SyncController::pull`).
const _scriptPariteAchats = r'''
Carbon\Carbon::setTestNow('2026-10-19 08:00:00');
$entree = json_decode(file_get_contents($argv[1]), true);
Illuminate\Support\Facades\Artisan::call('db:seed', ['--class' => 'Database\\Seeders\\RolesAndPermissionsSeeder', '--force' => true]);
$utilisateur = App\Models\User::create([
    'name' => 'Administrateur', 'username' => 'admin', 'email' => 'dg@fermeolouwachegoun.com',
    'password' => bcrypt('AgriERP@2026'), 'is_active' => true,
]);
$utilisateur->assignRole('admin');
$categories = [
    App\Models\ProductCategory::create(['label' => 'Aliments bétail', 'is_active' => true]),
    App\Models\ProductCategory::create(['label' => 'Médicaments', 'is_active' => true]),
];
$produits = [];
foreach ($categories as $i => $c) {
    $produits[$i] = App\Models\Product::create([
        'sku' => 'P'.$i, 'name' => 'Produit '.$i, 'category_id' => $c->id, 'unit' => 'u',
        'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 100000, 'stock_qty' => 100, 'is_active' => true,
    ]);
}
$fournisseur = App\Models\Supplier::create(['name' => 'Fournisseur', 'category' => 'Fournitures', 'is_active' => true]);
$instant = Carbon\Carbon::parse('2026-10-19 08:00:00');
foreach ($entree['achats'] as $a) {
    $instant = $instant->copy()->addSecond();
    Carbon\Carbon::setTestNow($instant);
    $achat = App\Models\Purchase::create([
        'supplier_id' => $fournisseur->id, 'payment_mode' => 'especes', 'total' => 1000, 'purchase_date' => '2026-10-05',
    ]);
    $lignes = [];
    foreach ($a['lignes'] as $p) {
        $instant = $instant->copy()->addSecond();
        Carbon\Carbon::setTestNow($instant);
        $lignes[] = App\Models\PurchaseLine::create([
            'purchase_id' => $achat->id, 'product_id' => $produits[$p]->id, 'qty' => 2, 'unit_price' => 500,
        ]);
    }
    if ($a['retour'] === 'complet') {
        $lot = (string) Illuminate\Support\Str::uuid();
        foreach ($lignes as $l) {
            App\Models\PurchaseReturn::create([
                'purchase_id' => $achat->id, 'product_id' => $l->product_id, 'qty' => $l->qty, 'reason' => 'Avarie',
                'return_batch_id' => $lot, 'purchase_line_id' => $l->id, 'return_date' => '2026-10-12',
            ]);
        }
        $achat->forceFill(['returned_at' => $instant])->save();
    } elseif ($a['retour'] === 'ancien_partiel') {
        // Retour d'avant 15.20 : une seule ligne, sans lot ni date (la migration a posé `returned_at`).
        App\Models\PurchaseReturn::create([
            'purchase_id' => $achat->id, 'product_id' => $lignes[0]->product_id, 'qty' => 1, 'reason' => null,
        ]);
        $achat->forceFill(['returned_at' => $instant])->save();
    }
}
$liste = new App\Livewire\Achats\ListeAchats();
$categoriesParAchat = [];
foreach ($liste->purchases as $p) {
    $categoriesParAchat[$p->id] = $p->categorie;
}
$requete = Illuminate\Http\Request::create('/api/sync/pull', 'GET');
$requete->setUserResolver(fn () => $utilisateur);
$tirage = app(App\Http\Controllers\Api\SyncController::class)->pull($requete)->getData(true);
echo json_encode([
    'ecarts' => $liste->kpis['ecarts_retours'],
    'categories' => $categoriesParAchat,
    'tirage' => $tirage,
]);
''';
