import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/ventes/devis_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket DEV3 — PARITÉ EXÉCUTÉE de « Convertir en Facture » : le VRAI `SyncController` et le VRAI
/// `ConvertirDevisEnFactureAction` du serveur reçoivent la DEMANDE que le poste fabrique, et le poste absorbe leur VRAIE
/// réponse (les factures rendues) et leur VRAI tirage (le devis facturé, la vente sans ligne).
///
/// ⚠️⚠️ Rien n'est recopié : le poste (vrais dépôt et moteur) écrit la demande puis fabrique son envoi — il est capté sur une
/// coupure réseau, le devis restant `pending` — ; le PHP du dépôt Laravel (SQLite en mémoire, migrations réelles, rôle
/// `admin` du seeder, qui porte `manage-ventes` ET `manage-facturation`) le traite par `POST /api/sync/push` puis sert son
/// tirage ; le poste rejoue la synchronisation contre CES réponses. Un décalage de format (clé `quote_conversions`,
/// `requested_at`, `invoices`, `converted_sale_id`, `invoice_number`) entre les deux côtés fait rougir ce test, alors que
/// chaque moitié passe seule.
///
/// Sans PHP ni dépôt Laravel, le test est SAUTÉ AVEC SA RAISON (jamais vert à vide).
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Capte les envois et coupe le réseau : rien n'est acquitté, le devis reste `pending`.
class _Coupure extends Interceptor {
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      envois.add(options.data as Map<String, dynamic>);
    } else {
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {'server_time': '2026-10-21T09:00:00Z'}));
      return;
    }
    handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError));
  }
}

/// Rend la vraie réponse du serveur à l'envoi, et son vrai tirage.
class _VraiServeur extends Interceptor {
  _VraiServeur(this.reponse, this.tirage);

  final Map<String, dynamic> reponse;
  final Map<String, dynamic> tirage;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path.contains('push') ? reponse : tirage,
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
Carbon::setTestNow('2026-10-21 12:00:00');

App\Models\FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
foreach ([['411', 'Clients', 4], ['443', 'TVA facturée', 4], ['701', 'Ventes de produits', 7]] as [$c, $l, $k]) {
    App\Models\ChartOfAccount::create(['code' => $c, 'label' => $l, 'class' => $k, 'is_active' => true]);
}
$client = new App\Models\Customer(['name' => 'AMOUSSOU Régis', 'phone' => '97123456', 'is_active' => true]);
$client->id = $in['client'];
$client->save();

$u = App\Models\User::create(['name' => 'Direction', 'username' => 'admin', 'email' => 'admin@fermeolouwachegoun.com', 'password' => bcrypt('x'), 'is_active' => true]);
$u->assignRole('admin');
Sanctum::actingAs($u, ['*']);
$noyau = $app->make(Illuminate\Contracts\Http\Kernel::class);

$r = $noyau->handle(Request::create('/api/sync/push', 'POST', [], [], [], ['CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json'], json_encode($in['envoi'])));
$sortie = ['statut' => $r->getStatusCode(), 'reponse' => json_decode($r->getContent(), true)];

$vente = App\Models\Sale::first();
$sortie['vente'] = $vente?->only(['payment_mode', 'status', 'customer_id']) + ['total' => (float) $vente?->total, 'sold_at' => $vente?->sold_at?->format('Y-m-d H:i:s'), 'lignes' => $vente?->lines()->count()];
$sortie['creance'] = (float) App\Models\Receivable::where('sale_id', $vente?->id)->value('amount');
$sortie['ecriture'] = App\Models\AccountingEntryLine::with('account')->get()->mapWithKeys(fn ($l) => [$l->account->code => [(float) $l->debit, (float) $l->credit]])->all();
$devis = App\Models\Quote::first();
$sortie['devis'] = ['status' => $devis->status, 'converted_sale_id' => $devis->converted_sale_id, 'numero_facture' => $devis->numero_facture];

Carbon::setTestNow('2026-10-21 12:05:00');
$tirage = $noyau->handle(Request::create('/api/sync/pull', 'GET', [], [], [], ['HTTP_ACCEPT' => 'application/json']));
$sortie['tirage'] = json_decode($tirage->getContent(), true);
echo json_encode($sortie);
''';

void main() {
  final saut = sautSansPhp();

  const client = 'cccccccc-0000-4000-8000-000000000001';
  const devisId = 'dddddddd-3333-4000-8000-000000000001';

  test('⚠️⚠️ le serveur réel crée la facture de la demande du poste, et le poste absorbe sa vraie réponse et son vrai tirage', () async {
    HeureBenin.horloge = () => DateTime.utc(2026, 10, 21, 9);
    addTearDown(HeureBenin.reinitialiser);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final depot = DevisRepository(database: db, deviceId: 'poste-test');
    final coupure = _Coupure();
    SyncEngine moteur(Interceptor serveur) => SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime.utc(2026, 10, 21, 9),
    );

    await db.into(db.customers).insert(CustomersCompanion.insert(id: client, name: 'AMOUSSOU Régis'));
    await db.into(db.fiscalYears).insert(
      FiscalYearsCompanion.insert(
        id: 'eeeeeeee-2026-4000-8000-000000000001',
        year: 2026,
        startDate: Value(DateTime(2026)),
        endDate: Value(DateTime(2026, 12, 31)),
        status: const Value('ouvert'),
      ),
    );
    // Un devis accepté, déjà connu du serveur par un envoi précédent (devis `accepte`, acquitté) : ici il est créé au poste
    // et part DANS LE MÊME envoi que sa demande (hors ligne : créer, envoyer, accepter, convertir).
    await db.into(db.quotes).insert(
      QuotesCompanion.insert(
        id: devisId,
        deviceId: 'poste-test',
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: DateTime.utc(2026, 10, 20, 9),
        customerId: client,
        articlesDescription: '2 cages galvanisées 6 compartiments sur mesure',
        amount: 150000,
        tvaRate: const Value(18),
        quoteDate: DateTime(2026, 10, 20),
        status: const Value('accepte'),
      ),
    );
    await depot.demanderConversion(devisId);

    // 1. Le poste fabrique son envoi (réseau coupé : rien n'est acquitté).
    try {
      await moteur(coupure).synchroniser();
    } catch (_) {
      // Réseau coupé : l'échec est voulu, seul l'envoi capté compte.
    }
    final envoi = coupure.envois.single;
    expect(envoi['quote_conversions'], [
      {'id': devisId, 'requested_at': '2026-10-21 10:00:00'},
    ]);

    // 2. Le VRAI serveur le traite et sert son tirage.
    final sortie = executerPhp(_script, {'client': client, 'envoi': envoi}, application: true) as Map<String, dynamic>;

    expect(sortie['statut'], 200, reason: '${sortie['reponse']}');
    final reponse = sortie['reponse'] as Map<String, dynamic>;
    expect((reponse['quotes'] as Map)['rejected'], isEmpty, reason: 'devis refusé : ${(reponse['quotes'] as Map)['rejected']}');
    final conversion = reponse['quote_conversions'] as Map<String, dynamic>;
    expect(conversion['rejected'], isEmpty, reason: 'conversion refusée : ${conversion['rejected']}');
    expect(conversion['accepted'], [devisId]);
    final facture = (conversion['invoices'] as Map)[devisId] as Map;
    // La facture : vente à crédit sans ligne, 150 000 HT + 18 % = 177 000 TTC, datée du clic du poste (10:00 Bénin).
    expect(sortie['vente'], {
      'payment_mode': 'credit',
      'status': 'validee',
      'customer_id': client,
      'total': 177000.0,
      'sold_at': '2026-10-21 10:00:00',
      'lignes': 0,
    });
    expect(sortie['creance'], 177000.0);
    expect(sortie['ecriture'], {
      '411': [177000.0, 0.0],
      '701': [0.0, 150000.0],
      '443': [0.0, 27000.0],
    });
    final numero = 'FV-2026-${(facture['sale_id'] as String).substring(0, 6).toUpperCase()}';
    expect(facture['invoice_number'], numero);
    expect(sortie['devis'], {'status': 'facture', 'converted_sale_id': facture['sale_id'], 'numero_facture': numero});

    // 3. Le poste rejoue la synchronisation contre la VRAIE réponse et le VRAI tirage.
    await moteur(_VraiServeur(reponse, (sortie['tirage'] as Map).cast<String, dynamic>())).synchroniser();

    // Le tirage précède l'envoi : l'acquittement ferme la demande, le tirage suivant apporte numéro de devis et vente.
    var d = await (db.select(db.quotes)..where((t) => t.id.equals(devisId))).getSingle();
    expect(
      [d.status, d.convertedSaleId, d.invoiceNumber, d.conversionRequestedAt, d.syncStatus],
      ['facture', facture['sale_id'], numero, null, SyncStatus.synced],
    );
    await moteur(_VraiServeur(reponse, (sortie['tirage'] as Map).cast<String, dynamic>())).synchroniser();
    d = await (db.select(db.quotes)..where((t) => t.id.equals(devisId))).getSingle();
    expect([d.quoteNumber, d.status, d.invoiceNumber], ['DEV-2026-001', 'facture', numero]);
    // La vente SANS LIGNE descend et s'absorbe : l'écran Facturation la liste, son total est le TTC du devis.
    final vente = await (db.select(db.sales)..where((v) => v.id.equals(facture['sale_id'] as String))).getSingle();
    expect([vente.paymentMode, vente.total, vente.status, vente.customerName, vente.syncStatus], ['credit', 177000, 'validee', 'AMOUSSOU Régis', SyncStatus.synced]);
    expect(await (db.select(db.saleLines)..where((l) => l.saleId.equals(vente.id))).get(), isEmpty);
    // Une seconde synchronisation est calme : plus de demande, plus rien en attente.
    expect(await db.pendingCount(), 0);
  }, skip: saut);
}
