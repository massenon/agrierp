import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/ventes/avoirs_repository.dart';
import 'package:agrierp/features/ventes/historique_ventes_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Tickets AV1 / AV2 — PARITÉ EXÉCUTÉE : le VRAI `SyncController` du serveur reçoit ce que le poste envoie et sert ce que le
/// poste absorbe.
///
/// ⚠️⚠️ Rien n'est recopié : le poste (`SyncEngine`, vrais dépôts) fabrique son envoi — une demande de retour, puis
/// l'annulation d'une vente —, le PHP du dépôt Laravel (SQLite en mémoire, migrations réelles, rôle `caissier` du seeder)
/// le traite par `POST /api/sync/push` (`pushCreditNotes`, `pushSales`, `AvoirClientService`, `AnnulerVenteAction`) puis sert
/// son VRAI tirage (`GET /api/sync/pull`), que le poste absorbe. Un décalage de format (date, clé, statut) entre les deux
/// côtés fait rougir ce test, alors que chaque moitié passe seule.
///
/// Sans PHP ni dépôt Laravel, le test est SAUTÉ AVEC SA RAISON (jamais vert à vide).
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Garde les corps d'envoi et sert [tirage]. Accepte tout (l'accusé du vrai serveur est lu dans la sortie du PHP).
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-21T09:00:00Z'};
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
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

const _script = r'''<?php
use Illuminate\Http\Request;
use Laravel\Sanctum\Sanctum;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
Artisan::call('db:seed', ['--class' => 'Database\\Seeders\\RolesAndPermissionsSeeder', '--force' => true]);
Carbon::setTestNow('2026-10-21 12:00:00');

App\Models\FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
foreach ([['531', 'Caisse', 5], ['411', 'Clients', 4], ['443', 'TVA facturée', 4], ['701', 'Ventes de produits', 7]] as [$c, $l, $k]) {
    App\Models\ChartOfAccount::create(['code' => $c, 'label' => $l, 'class' => $k, 'is_active' => true]);
}
$cat = App\Models\ProductCategory::create(['label' => 'Œufs', 'is_active' => true]);
$produit = new App\Models\Product([
    'sku' => 'OEUF', 'name' => "Plaquette d'œufs", 'category_id' => $cat->id, 'unit' => 'plaquette',
    'pricing_mode' => 'fourchette', 'price_min' => 2000, 'price_max' => 6000, 'tva_rate' => 18, 'stock_qty' => 100, 'is_active' => true,
]);
$produit->id = $in['produit'];
$produit->save();
$vente = new App\Models\Sale([
    'payment_mode' => 'especes', 'subtotal' => 59000, 'discount' => 0, 'total' => 59000, 'status' => 'validee',
    'sold_at' => '2026-10-20 15:00:00',
]);
$vente->id = $in['vente'];
$vente->save();
App\Models\SaleLine::create(['sale_id' => $vente->id, 'product_id' => $produit->id, 'qty' => 10, 'unit_price' => 5900, 'manual_total_amount' => 59000]);

$u = App\Models\User::create(['name' => 'Caisse', 'username' => 'caisse', 'email' => 'caisse@fermeolouwachegoun.com', 'password' => bcrypt('x'), 'is_active' => true]);
$u->assignRole('caissier');
Sanctum::actingAs($u, ['*']);
$noyau = $app->make(Illuminate\Contracts\Http\Kernel::class);

$envoyer = function (array $corps) use ($noyau) {
    $r = $noyau->handle(Request::create('/api/sync/push', 'POST', [], [], [], ['CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json'], json_encode($corps)));
    return ['statut' => $r->getStatusCode(), 'corps' => json_decode($r->getContent(), true)];
};

$sortie = ['envoi_retour' => $envoyer($in['retour'])];
$sortie['stock_apres_retour'] = (float) $produit->fresh()->stock_qty;
$sortie['ecritures_apres_retour'] = App\Models\AccountingEntry::count();
$sortie['avoir'] = App\Models\CreditNote::first()?->only(['id', 'credit_note_number', 'qty', 'amount', 'status', 'decision']);
$sortie['avoir_cree_le'] = App\Models\CreditNote::first()?->created_at?->format('Y-m-d H:i:s');

$sortie['envoi_annulation'] = $envoyer($in['annulation']);
$sortie['vente_statut'] = $vente->fresh()->status;
$sortie['stock_apres_annulation'] = (float) $produit->fresh()->stock_qty;

Carbon::setTestNow('2026-10-21 12:05:00');
$tirage = $noyau->handle(Request::create('/api/sync/pull?page=1', 'GET', [], [], [], ['HTTP_ACCEPT' => 'application/json']));
$sortie['tirage'] = json_decode($tirage->getContent(), true);
echo json_encode($sortie);
''';

void main() {
  final saut = sautSansPhp();

  const oeufs = 'aaaaaaaa-0000-4000-8000-000000000001';
  const vente1 = 'bbbbbbbb-1111-4000-8000-000000000001';

  test('⚠️⚠️ le serveur réel traite la demande et l\'annulation du poste, puis sert un tirage que le poste absorbe', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final serveur = _Serveur();
    final moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime.utc(2026, 10, 21, 9, 30, 5),
    );
    final maintenant = DateTime(2026, 10, 21, 10, 30, 5);
    final avoirs = AvoirsRepository(database: db, identifiantPoste: 'poste-test', horloge: () => maintenant);
    final historique = HistoriqueVentesRepository(database: db, horloge: () => maintenant);

    await db.into(db.products).insert(
      ProductsCompanion.insert(id: oeufs, sku: 'OEUF', name: "Plaquette d'œufs", unit: 'plaquette', pricingMode: 'fourchette'),
    );
    await db.into(db.fiscalYears).insert(
      FiscalYearsCompanion.insert(
        id: 'eeeeeeee-2026-4000-8000-000000000001',
        year: 2026,
        startDate: Value(DateTime(2026)),
        endDate: Value(DateTime(2026, 12, 31)),
        status: const Value('ouvert'),
      ),
    );
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: vente1,
        deviceId: 'serveur',
        syncStatus: const Value(SyncStatus.synced),
        updatedAt: DateTime(2026, 10, 20),
        paymentMode: 'especes',
        subtotal: const Value(59000),
        total: 59000,
        soldAt: DateTime(2026, 10, 20, 15),
      ),
    );
    await db.into(db.saleLines).insert(
      SaleLinesCompanion.insert(
        id: 'dddddddd-0000-4000-8000-000000000001',
        saleId: vente1,
        productId: oeufs,
        qty: 10,
        unitPrice: 5900,
        manualTotalAmount: 59000,
      ),
    );

    // 1. Le poste enregistre la demande de retour et la pousse (le moteur fabrique le corps).
    final retour = await avoirs.enregistrer(
      venteId: vente1,
      produitId: oeufs,
      quantite: 2,
      montant: 11800,
      motif: 'Plaquette détériorée',
      decision: 'reintegre',
    );
    await moteur.synchroniser();
    final corpsRetour = serveur.envois.single;
    // 2. Puis annule la vente (la vente repart, annulée).
    await historique.annuler(vente1);
    await moteur.synchroniser();
    final corpsAnnulation = serveur.envois.last;

    final sortie = executerPhp(
      _script,
      {'produit': oeufs, 'vente': vente1, 'retour': corpsRetour, 'annulation': corpsAnnulation},
      application: true,
    ) as Map<String, dynamic>;

    // Le vrai serveur ACCEPTE la demande du poste, sans refus.
    final envoi = sortie['envoi_retour'] as Map<String, dynamic>;
    expect(envoi['statut'], 200, reason: '${envoi['corps']}');
    final reponse = envoi['corps']['credit_notes'] as Map<String, dynamic>;
    expect(reponse['rejected'], isEmpty, reason: 'refus du serveur : ${reponse['rejected']}');
    expect(reponse['accepted'], [retour.avoir!.id]);
    // Il fait les effets : numéro, stock réintégré, écriture inverse, date du FAIT.
    expect(sortie['avoir'], {
      'id': retour.avoir!.id,
      'credit_note_number': 'AV-2026-001',
      'qty': '2.00',
      'amount': '11800.00',
      'status': 'en_attente',
      'decision': 'reintegre',
    });
    expect(sortie['avoir_cree_le'], '2026-10-21 10:30:05', reason: 'le jour du fait envoyé par le poste, sans décalage de fuseau');
    expect(sortie['stock_apres_retour'], 102.0);
    expect(sortie['ecritures_apres_retour'], 1);

    // L'annulation : la vente connue renvoyée annulée est annulée UNE fois, le stock des lignes revient.
    final annulation = (sortie['envoi_annulation'] as Map<String, dynamic>)['corps'];
    expect(annulation['sales']['rejected'], isEmpty);
    expect(sortie['vente_statut'], 'annulee');
    expect(sortie['stock_apres_annulation'], 112.0, reason: '102 + 10 vendus ré-entrés');

    // 3. Le poste absorbe le VRAI tirage : l'avoir reçoit son numéro, la vente son statut et ses sous-total / remise.
    serveur.tirage = (sortie['tirage'] as Map).cast<String, dynamic>();
    await moteur.synchroniser();

    final lus = await db.select(db.creditNotes).get();
    expect(lus, hasLength(1));
    expect(lus.single.id, retour.avoir!.id);
    expect(lus.single.creditNoteNumber, 'AV-2026-001');
    expect(lus.single.syncStatus, SyncStatus.synced);
    expect(lus.single.qty, 2);
    expect(lus.single.amount, 11800);
    expect(lus.single.createdAt, DateTime(2026, 10, 21, 10, 30, 5));
    final vente = await (db.select(db.sales)..where((v) => v.id.equals(vente1))).getSingle();
    expect(vente.status, 'annulee');
    expect(vente.subtotal, 59000);
    expect(vente.discount, 0);
  }, skip: saut);
}
