import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket VTE-1 — PARITÉ EXÉCUTÉE de la vente enregistrée au poste SANS client (ou avec un client que le serveur ne
/// connaît pas encore) : le VRAI `SyncController` reçoit l'envoi que le poste fabrique avec ses vrais dépôt et moteur.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Capte les envois et coupe le réseau : rien n'est acquitté.
class _Coupure extends Interceptor {
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      envois.add(options.data as Map<String, dynamic>);
    } else {
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {'server_time': '2026-10-26T09:00:00Z'}));
      return;
    }
    handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError));
  }
}

/// Rend la VRAIE réponse du serveur à l'envoi ; tirage vide.
class _VraiServeur extends Interceptor {
  _VraiServeur(this.reponse);

  final Map<String, dynamic> reponse;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path.contains('push') ? reponse : {'server_time': '2026-10-26T09:00:00Z'},
      ),
    );
  }
}

const _script = r'''<?php
use Illuminate\Http\Request;
use Laravel\Sanctum\Sanctum;
use Illuminate\Support\Carbon;
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
Artisan::call('db:seed', ['--class' => 'Database\\Seeders\\RolesAndPermissionsSeeder', '--force' => true]);
Carbon::setTestNow('2026-10-26 12:00:00');

App\Models\FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
foreach ([['531', 'Caisse', 5], ['411', 'Clients', 4], ['701', 'Ventes de produits', 7]] as [$c, $l, $k]) {
    App\Models\ChartOfAccount::create(['code' => $c, 'label' => $l, 'class' => $k, 'is_active' => true]);
}
App\Models\TreasuryAccount::create(['type' => 'caisse', 'label' => 'Caisse', 'account_code' => '531', 'balance' => 0, 'is_active' => true]);
$cat = App\Models\ProductCategory::create(['label' => 'Aviculture', 'is_active' => true]);
$espece = App\Models\LivestockSpecies::create(['label' => 'Aviculture', 'code' => 'AVI', 'is_active' => true]);
foreach ($in['produits'] as $p) {
    $produit = new App\Models\Product(['sku' => $p['sku'], 'name' => $p['name'], 'category_id' => $cat->id, 'species_id' => $p['espece'] ? $espece->id : null, 'unit' => 'u', 'pricing_mode' => 'fourchette', 'price_min' => 100, 'price_max' => 9000, 'tva_rate' => 0, 'stock_qty' => 50, 'is_active' => true]);
    $produit->id = $p['id'];
    $produit->save();
}
if (! empty($in['bande'])) {
    $b = new App\Models\LivestockLot(['code' => 'AVI-2026-01', 'species_id' => $espece->id, 'stage' => 'croissance', 'initial_quantity' => 50, 'current_quantity' => 50, 'created_date' => '2026-01-05', 'status' => 'actif', 'is_active' => true]);
    $b->id = $in['bande'];
    $b->save();
}
foreach ($in['clients_serveur'] ?? [] as $cid) {
    $c = new App\Models\Customer(['name' => 'Client serveur', 'is_active' => true]);
    $c->id = $cid;
    $c->save();
}

$u = App\Models\User::create(['name' => 'Direction', 'username' => 'admin', 'email' => 'admin@fermeolouwachegoun.com', 'password' => bcrypt('x'), 'is_active' => true]);
$u->assignRole('admin');
Sanctum::actingAs($u, ['*']);
$noyau = $app->make(Illuminate\Contracts\Http\Kernel::class);

$r = $noyau->handle(Request::create('/api/sync/push', 'POST', [], [], [], ['CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json'], json_encode($in['envoi'])));
$sortie = ['statut' => $r->getStatusCode(), 'reponse' => json_decode($r->getContent(), true)];
$sortie['ventes'] = App\Models\Sale::all()->map(fn ($v) => ['id' => $v->id, 'customer_id' => $v->customer_id, 'payment_mode' => $v->payment_mode, 'total' => (float) $v->total])->all();
$sortie['creances'] = App\Models\Receivable::count();
$sortie['clients'] = App\Models\Customer::pluck('name', 'id')->all();
echo json_encode($sortie);
''';

void main() {
  final saut = sautSansPhp();

  const produitSimple = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
  const produitBande = 'cccccccc-3333-4333-8333-cccccccccccc';
  const bande = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const espece = 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee';

  late AppDatabase db;
  late CaisseRepository caisse;

  setUp(() async {
    HeureBenin.horloge = () => DateTime.utc(2026, 10, 26, 9);
    addTearDown(HeureBenin.reinitialiser);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    caisse = CaisseRepository(database: db, deviceId: 'poste-test', maintenant: () => DateTime(2026, 10, 26, 10));
    await db.into(db.products).insert(
      ProductsCompanion.insert(id: produitSimple, sku: 'OEU-001', name: 'Oeufs', unit: 'u', pricingMode: 'fourchette', stockQty: const Value(50)),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(id: produitBande, sku: 'AVI-001', name: 'Poulet', speciesId: const Value(espece), unit: 'u', pricingMode: 'fourchette', stockQty: const Value(50)),
    );
    await db.into(db.livestockLots).insert(
      LivestockLotsCompanion.insert(id: bande, code: 'AVI-2026-01', speciesId: espece, initialQuantity: const Value(50), currentQuantity: const Value(50)),
    );
  });

  SyncEngine moteur(Interceptor serveur) => SyncEngine(
    database: db,
    client: Dio()..interceptors.add(serveur),
    deviceId: 'poste-test',
    connectivity: _Connectivite(),
    maintenant: () => DateTime.utc(2026, 10, 26, 9),
  );

  Future<Map<String, dynamic>> envoyer({List<String> clientsServeur = const []}) async {
    final coupure = _Coupure();
    try {
      await moteur(coupure).synchroniser();
    } catch (_) {}
    return executerPhp(
          _script,
          {
            'envoi': coupure.envois.first,
            'clients_serveur': clientsServeur,
            'bande': bande,
            'produits': [
              {'id': produitSimple, 'sku': 'OEU-001', 'name': 'Oeufs', 'espece': false},
              {'id': produitBande, 'sku': 'AVI-001', 'name': 'Poulet', 'espece': true},
            ],
          },
          application: true,
        )
        as Map<String, dynamic>;
  }

  Future<Product> produit(String id) => (db.select(db.products)..where((t) => t.id.equals(id))).getSingle();

  test('garde-fou : une vente au comptant sans client, produit simple, est acceptée par le vrai serveur', () async {
    await caisse.enregistrerVente(
      panier: [LignePanier(produit: await produit(produitSimple), quantite: 2, montant: 1000)],
      modePaiement: 'especes',
    );
    final sortie = await envoyer();
    final reponse = (sortie['reponse'] as Map)['sales'] as Map;
    expect(reponse['rejected'], isEmpty, reason: '${sortie['reponse']}');
    expect(sortie['ventes'], hasLength(1));
  }, skip: saut);

  test('garde-fou : une vente au comptant sans client, avec bande, est acceptée par le vrai serveur', () async {
    await caisse.enregistrerVente(
      panier: [LignePanier(produit: await produit(produitBande), quantite: 3, montant: 9000, lotId: bande)],
      modePaiement: 'especes',
    );
    final sortie = await envoyer();
    final reponse = (sortie['reponse'] as Map)['sales'] as Map;
    expect(reponse['rejected'], isEmpty, reason: '${sortie['reponse']}');
    expect(sortie['ventes'], hasLength(1));
  }, skip: saut);

  test('⚠️ un client créé au poste part AVANT sa vente à crédit, dans le même envoi : le vrai serveur accepte les deux et crée la créance', () async {
    final c = await caisse.creerClient(nom: 'GBAGUIDI Solange', telephone: '97123456');
    await caisse.enregistrerVente(
      panier: [LignePanier(produit: await produit(produitSimple), quantite: 2, montant: 6000)],
      modePaiement: 'credit',
      clientId: c.id,
    );

    final sortie = await envoyer();
    final reponse = sortie['reponse'] as Map<String, dynamic>;

    expect((reponse['customers'] as Map)['accepted'], [c.id], reason: '${reponse['customers']}');
    expect((reponse['sales'] as Map)['rejected'], isEmpty, reason: '${reponse['sales']}');
    expect(sortie['ventes'], [
      {'id': (await db.select(db.sales).getSingle()).id, 'customer_id': c.id, 'payment_mode': 'credit', 'total': 6000.0},
    ]);
    expect(sortie['creances'], 1);
  }, skip: saut);

  test('⚠️ une vente au comptant dont le client est inconnu du serveur : refus MOTIVÉ de cette vente seule, lisible, relançable', () async {
    const inconnu = 'dddddddd-0000-4000-8000-000000000009';
    // Le poste croit le client déjà envoyé (`synced`) ; le serveur ne le connaît pas (client refusé, base restaurée).
    await db.into(db.customers).insert(CustomersCompanion.insert(id: inconnu, name: 'Fantôme'));
    final p = await produit(produitSimple);
    final avecClient = await caisse.enregistrerVente(panier: [LignePanier(produit: p, quantite: 1, montant: 3000)], modePaiement: 'especes', clientId: inconnu);
    final sansClient = await caisse.enregistrerVente(panier: [LignePanier(produit: p, quantite: 1, montant: 2000)], modePaiement: 'especes');

    final sortie = await envoyer();
    final reponse = sortie['reponse'] as Map<String, dynamic>;
    final ventes = reponse['sales'] as Map;

    expect(ventes['accepted'], [sansClient.id], reason: 'l\'autre vente du même envoi passe');
    expect((ventes['rejected'] as List).single, {
      'id': avecClient.id,
      'reason': "Client inconnu du serveur : cette vente porte un client qui n'a pas encore été envoyé (ou qu'il a refusé). Envoyez d'abord le client, puis relancez la vente.",
    });

    // Le poste absorbe le VRAI refus : la vente passe en `conflict` avec ce motif, relançable depuis l'écran Synchronisation.
    await moteur(_VraiServeur(reponse)).synchroniser();
    final v = await (db.select(db.sales)..where((t) => t.id.equals(avecClient.id))).getSingle();
    expect(v.syncStatus, SyncStatus.conflict);
    final conflit = await (db.select(db.syncConflicts)..where((t) => t.recordId.equals(avecClient.id))).getSingle();
    expect(conflit.reason, contains('Client inconnu du serveur'));
    expect((await (db.select(db.sales)..where((t) => t.id.equals(sansClient.id))).getSingle()).syncStatus, SyncStatus.synced);
  }, skip: saut);

  test('un envoi de poste ancien (crédit sans client, écrit directement en table) est refusé par le vrai serveur, motif lisible', () async {
    // Aucun dépôt ne l'offre plus (le poste refuse avant d'écrire) : la ligne est écrite en table.
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: 'eeeeeeee-9999-4999-8999-eeeeeeeeeeee',
        deviceId: 'poste-test',
        updatedAt: DateTime.utc(2026, 10, 26, 8),
        paymentMode: 'credit',
        total: 6000,
        subtotal: const Value(6000),
        soldAt: DateTime(2026, 10, 26, 9),
      ),
    );
    await db.into(db.saleLines).insert(
      SaleLinesCompanion.insert(id: 'eeeeeeee-9999-4999-8999-ffffffffffff', saleId: 'eeeeeeee-9999-4999-8999-eeeeeeeeeeee', productId: produitSimple, qty: 2, unitPrice: 3000, manualTotalAmount: 6000),
    );

    final sortie = await envoyer();

    expect(((sortie['reponse'] as Map)['sales'] as Map)['rejected'], [
      {'id': 'eeeeeeee-9999-4999-8999-eeeeeeeeeeee', 'reason': 'Une vente à crédit exige un client.'},
    ]);
    expect(sortie['ventes'], isEmpty);
    expect(sortie['creances'], 0);
  }, skip: saut);
}
