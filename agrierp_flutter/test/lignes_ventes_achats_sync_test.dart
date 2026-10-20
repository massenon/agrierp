import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket U4 (décision D-U4 du 19/10/2026) — LES LIGNES DES VENTES ET DES ACHATS DESCENDENT AU POSTE.
///
/// Le Tableau de bord du poste calculait le Top 5 (marge « — ») et les ventes porcines sur les seules lignes
/// saisies SUR CE POSTE. Ce que ces tests verrouillent, côté absorbeurs (`_absorberLignesDeVente`,
/// `_absorberLignesDAchat`) :
///  - les lignes servies sont absorbées dans `sale_lines` / `purchase_lines` ;
///  - les lignes d'une pièce `synced` sont REMPLACÉES par celles du serveur (une ligne retirée au web disparaît) ;
///  - ⚠️⚠️ une pièce `pending` ou en `conflict` sur ce poste garde SES lignes, jamais écrasées ;
///  - STRICT : ligne d'une pièce non servie, produit inconnu, élément illisible → lot refusé, rien d'écrit, le
///    curseur n'avance pas ;
///  - de bout en bout : le Top 5 et sa marge comptent les ventes et achats du web.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Serveur feint : sert [tirage] au tirage, et accepte tout ce qu'on lui envoie.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-19T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];

  /// `since` de chaque tirage (null : tirage complet).
  final List<Object?> demandes = [];

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

  const porc = 'd1d2d3d4-0000-4000-8000-00000000000c';
  const provende = 'd1d2d3d4-0000-4000-8000-00000000000b';
  const fournisseur = 'f0f0f0f0-0000-4000-8000-000000000001';
  const venteWeb = 'a1b2c3d4-1111-4000-8000-000000000001';
  const venteLocale = 'a1b2c3d4-2222-4000-8000-000000000002';
  const achatWeb = 'abcdef01-4444-4000-8000-000000000001';
  const achatLocal = 'abcdef01-5555-4000-8000-000000000002';

  String uuid(String graine) => graine.padRight(36, '0');

  Map<String, dynamic> venteJson(String id, double total) => {
    'id': id,
    'payment_mode': 'especes',
    'total': total,
    'status': 'validee',
    'sold_at': '2026-10-10T09:00:00+00:00',
  };

  Map<String, dynamic> ligneVenteJson(
    String id,
    String vente,
    double qte,
    double montant, {
    String produit = porc,
  }) => {
    'id': id,
    'sale_id': vente,
    'product_id': produit,
    'lot_id': null,
    'qty': qte,
    'unit_price': montant / qte,
    'manual_total_amount': montant,
  };

  Map<String, dynamic> achatJson(String id, double total) => {
    'id': id,
    'supplier_id': fournisseur,
    'supplier_name': 'Provenderie du Plateau',
    'payment_mode': 'especes',
    'total': total,
    'purchase_date': '2026-10-05',
    'has_debt': false,
  };

  Map<String, dynamic> ligneAchatJson(
    String id,
    String achat,
    double qte,
    double prix, {
    String produit = porc,
  }) => {
    'id': id,
    'purchase_id': achat,
    'product_id': produit,
    'product_name': 'Porc charcutier',
    'qty': qte,
    'unit_price': prix,
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
    for (final (id, nom) in [
      (porc, 'Porc charcutier'),
      (provende, 'Provende ponte'),
    ]) {
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: id,
              sku: nom,
              name: nom,
              unit: 'u',
              pricingMode: 'fixe',
              syncStatus: const Value(SyncStatus.synced),
            ),
          );
    }
  });

  tearDown(() async => db.close());

  Future<List<SaleLine>> lignesDeVente(String vente) =>
      (db.select(db.saleLines)..where((l) => l.saleId.equals(vente))).get();

  Future<List<PurchaseLine>> lignesDAchat(String achat) => (db.select(
    db.purchaseLines,
  )..where((l) => l.purchaseId.equals(achat))).get();

  /// Vente et achat saisis SUR CE POSTE, avec leurs lignes, au statut [statut].
  Future<void> saisiesLocales(SyncStatus statut) async {
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: venteLocale,
            deviceId: 'poste-test',
            updatedAt: DateTime(2026, 10, 19, 9),
            syncStatus: Value(statut),
            paymentMode: 'especes',
            total: 45000,
            soldAt: DateTime(2026, 10, 19, 9),
          ),
        );
    await db
        .into(db.saleLines)
        .insert(
          SaleLinesCompanion.insert(
            id: uuid('ligne-locale-vente'),
            saleId: venteLocale,
            productId: porc,
            qty: 1,
            unitPrice: 45000,
            manualTotalAmount: 45000,
          ),
        );
    await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            id: achatLocal,
            deviceId: 'poste-test',
            updatedAt: DateTime(2026, 10, 19, 9),
            syncStatus: Value(statut),
            supplierId: fournisseur,
            paymentMode: 'especes',
            total: 16000,
            purchaseDate: DateTime(2026, 10, 19),
          ),
        );
    await db
        .into(db.purchaseLines)
        .insert(
          PurchaseLinesCompanion.insert(
            id: uuid('ligne-locale-achat'),
            purchaseId: achatLocal,
            productId: provende,
            qty: 2,
            unitPrice: 8000,
          ),
        );
  }

  test(
    'le tirage absorbe les lignes des ventes et des achats servis',
    () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'sales': [venteJson(venteWeb, 70000)],
        'sale_lines': [
          ligneVenteJson(uuid('lv1'), venteWeb, 1, 30000),
          ligneVenteJson(uuid('lv2'), venteWeb, 2.5, 40000),
        ],
        'purchases': [achatJson(achatWeb, 82000)],
        'purchase_lines': [ligneAchatJson(uuid('la1'), achatWeb, 4, 20500)],
      };

      await moteur.synchroniser();

      final lignes = await lignesDeVente(venteWeb);
      expect(
        {
          for (final l in lignes)
            l.id: (l.qty, l.unitPrice, l.manualTotalAmount),
        },
        {
          uuid('lv1'): (1.0, 30000.0, 30000.0),
          uuid('lv2'): (2.5, 16000.0, 40000.0),
        },
      );
      final achat = (await lignesDAchat(achatWeb)).single;
      expect(
        [achat.productId, achat.productName, achat.qty, achat.unitPrice],
        [porc, 'Porc charcutier', 4.0, 20500.0],
      );
    },
  );

  test(
    'les lignes d une pièce synced sont remplacées : une ligne retirée au web disparaît',
    () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'sales': [venteJson(venteWeb, 70000)],
        'sale_lines': [
          ligneVenteJson(uuid('lv1'), venteWeb, 1, 30000),
          ligneVenteJson(uuid('lv2'), venteWeb, 2.5, 40000),
        ],
        'purchases': [achatJson(achatWeb, 82000)],
        'purchase_lines': [
          ligneAchatJson(uuid('la1'), achatWeb, 4, 20500),
          ligneAchatJson(uuid('la2'), achatWeb, 1, 0),
        ],
      };
      await moteur.synchroniser();

      serveur.tirage = {
        'server_time': '2026-10-19T13:00:00Z',
        'sales': [venteJson(venteWeb, 30000)],
        'sale_lines': [ligneVenteJson(uuid('lv1'), venteWeb, 1, 30000)],
        'purchases': [achatJson(achatWeb, 82000)],
        'purchase_lines': [ligneAchatJson(uuid('la1'), achatWeb, 4, 20500)],
      };
      await moteur.synchroniser();

      expect((await lignesDeVente(venteWeb)).map((l) => l.id), [uuid('lv1')]);
      expect((await lignesDAchat(achatWeb)).map((l) => l.id), [uuid('la1')]);
    },
  );

  for (final statut in [SyncStatus.pending, SyncStatus.conflict]) {
    test(
      '⚠️⚠️ une pièce ${statut.name} sur ce poste garde ses lignes, jamais écrasées',
      () async {
        await saisiesLocales(statut);
        // Le serveur sert la MÊME pièce (accusé perdu en route) avec d'autres lignes.
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'sales': [venteJson(venteLocale, 45000)],
          'sale_lines': [
            ligneVenteJson(uuid('serveur-lv'), venteLocale, 9, 99000),
          ],
          'purchases': [achatJson(achatLocal, 16000)],
          'purchase_lines': [
            ligneAchatJson(uuid('serveur-la'), achatLocal, 9, 99),
          ],
        };

        await moteur.synchroniser();

        expect((await lignesDeVente(venteLocale)).map((l) => l.id), [
          uuid('ligne-locale-vente'),
        ]);
        expect((await lignesDAchat(achatLocal)).map((l) => l.id), [
          uuid('ligne-locale-achat'),
        ]);
      },
    );
  }

  group(
    'absorbeur STRICT : le lot est refusé, rien n est écrit, le curseur n avance pas',
    () {
      Future<void> refuse(Map<String, dynamic> tirage) async {
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'sales': [venteJson(venteWeb, 70000)],
          'sale_lines': [ligneVenteJson(uuid('lv1'), venteWeb, 1, 30000)],
          'purchases': [achatJson(achatWeb, 82000)],
          'purchase_lines': [ligneAchatJson(uuid('la1'), achatWeb, 4, 20500)],
        };
        await moteur.synchroniser();
        final curseur = (await db.etatDeSynchronisation())?.lastPulledAt;
        final avantVente = await db.select(db.saleLines).get();
        final avantAchat = await db.select(db.purchaseLines).get();

        serveur.tirage = {'server_time': '2026-10-19T13:00:00Z', ...tirage};
        await expectLater(
          moteur.synchroniser(),
          throwsA(isA<FormatException>()),
        );

        expect(await db.select(db.saleLines).get(), avantVente);
        expect(await db.select(db.purchaseLines).get(), avantAchat);
        expect((await db.etatDeSynchronisation())?.lastPulledAt, curseur);
      }

      test('ligne de vente d une vente non servie (fuite)', () async {
        await refuse({
          'sales': [venteJson(venteWeb, 70000)],
          'sale_lines': [
            ligneVenteJson(uuid('lv1'), venteWeb, 2, 60000),
            ligneVenteJson(uuid('lv9'), uuid('vente-inconnue'), 1, 1000),
          ],
        });
      });

      test('ligne d achat d un achat non servi (fuite)', () async {
        await refuse({
          'purchases': <Object>[],
          'purchase_lines': [ligneAchatJson(uuid('la1'), achatWeb, 4, 20500)],
        });
      });

      test('produit inconnu du poste', () async {
        await refuse({
          'sales': [venteJson(venteWeb, 70000)],
          'sale_lines': [
            ligneVenteJson(
              uuid('lv1'),
              venteWeb,
              1,
              30000,
              produit: uuid('produit-inconnu'),
            ),
          ],
        });
      });

      test('montant illisible', () async {
        await refuse({
          'sales': [venteJson(venteWeb, 70000)],
          'sale_lines': [
            {
              ...ligneVenteJson(uuid('lv1'), venteWeb, 1, 30000),
              'manual_total_amount': null,
            },
          ],
        });
      });

      test('ligne servie deux fois', () async {
        await refuse({
          'purchases': [achatJson(achatWeb, 82000)],
          'purchase_lines': [
            ligneAchatJson(uuid('la1'), achatWeb, 4, 20500),
            ligneAchatJson(uuid('la1'), achatWeb, 4, 20500),
          ],
        });
      });
    },
  );

  test(
    'un serveur antérieur à U4 (clés absentes) ne touche à aucune ligne',
    () async {
      await saisiesLocales(SyncStatus.synced);
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'sales': [venteJson(venteLocale, 45000)],
        'purchases': [achatJson(achatLocal, 16000)],
      };

      await moteur.synchroniser();

      expect(await lignesDeVente(venteLocale), hasLength(1));
      expect(await lignesDAchat(achatLocal), hasLength(1));
    },
  );

  group('resynchronisation unique `lignes_resync_u4`', () {
    /// Poste déjà en service : un curseur, et toutes les resynchronisations ANTÉRIEURES faites.
    Future<void> posteEnService() async {
      await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
      for (final cle in [
        SyncEngine.cleJournalResync,
        SyncEngine.cleJournalResyncCreation,
        SyncEngine.cleFichesResync,
        SyncEngine.cleFichesResyncCategories,
      ]) {
        await db
            .into(db.appSettings)
            .insert(AppSettingsCompanion.insert(key: cle, value: '1'));
      }
    }

    test(
      '⚠️⚠️ un poste déjà en service redemande TOUT une fois (ses ventes sont antérieures au curseur), puis l incrémental',
      () async {
        await posteEnService();
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'sales': [venteJson(venteWeb, 30000)],
          'sale_lines': [ligneVenteJson(uuid('lv1'), venteWeb, 1, 30000)],
          'purchases': [achatJson(achatWeb, 82000)],
          'purchase_lines': [ligneAchatJson(uuid('la1'), achatWeb, 4, 20500)],
          // Ticket U8 — un serveur à jour sert aussi les retours des achats servis (sinon la resynchronisation
          // `retours_resync_u8` maintient le tirage complet).
          'purchase_returns': <Object>[],
        };

        await moteur.synchroniser();
        await moteur.synchroniser();

        expect(serveur.demandes.first, isNull, reason: 'sans since, une fois');
        expect(serveur.demandes.last, isNotNull, reason: 'puis incrémental');
        expect(await lignesDeVente(venteWeb), hasLength(1));
        expect(await lignesDAchat(achatWeb), hasLength(1));
      },
    );

    test(
      '⚠️ serveur antérieur à U4 (ventes servies sans leurs lignes) : la resynchronisation N EST PAS marquée faite',
      () async {
        await posteEnService();
        serveur.tirage = {
          'server_time': '2026-10-19T12:00:00Z',
          'sales': [venteJson(venteWeb, 30000)],
          'purchases': <Object>[],
        };

        await moteur.synchroniser();
        await moteur.synchroniser();

        expect(serveur.demandes, [null, null]);
      },
    );
  });

  test(
    'de bout en bout : le Top 5 et sa marge comptent les ventes et achats du web',
    () async {
      // Ventes d'octobre servies : porc 1 + 2,5 = 3,5 pour 70 000.
      // Achats servis : porc 4 × 15 000 + 1 × 20 000 = 80 000 pour 5 → PMP 16 000.
      // Marge : round((70 000 − 16 000 × 3,5) ÷ 70 000 × 100) = round(20) = 20 %.
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'sales': [venteJson(venteWeb, 70000)],
        'sale_lines': [
          ligneVenteJson(uuid('lv1'), venteWeb, 1, 30000),
          ligneVenteJson(uuid('lv2'), venteWeb, 2.5, 40000),
        ],
        'purchases': [achatJson(achatWeb, 80000)],
        'purchase_lines': [
          ligneAchatJson(uuid('la1'), achatWeb, 4, 15000),
          ligneAchatJson(uuid('la2'), achatWeb, 1, 20000),
        ],
      };
      await moteur.synchroniser();

      final d = await TableauDeBordRepository(
        database: db,
        horloge: () => DateTime(2026, 10, 19, 14),
      ).charger();

      expect(
        d.topProduits.map(
          (t) => (t.produit, t.quantite, t.chiffreAffaires, t.margePct),
        ),
        [('Porc charcutier', 3.5, 70000.0, 20)],
      );
    },
  );
}
