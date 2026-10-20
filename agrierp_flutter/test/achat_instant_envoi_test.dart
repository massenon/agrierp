import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket S-T12 — L'ACHAT DU POSTE PART AVEC SON INSTANT (`purchased_at`), comme une vente avec `sold_at`.
///
/// Le serveur datait l'entrée en stock d'un achat du poste de sa RÉCEPTION : un achat fait mardi 10 h 30 sur un poste
/// hors ligne, un comptage des rayons mardi midi, la réception jeudi — l'achat passait pour postérieur au comptage et
/// la marchandise, déjà comptée, entrait une seconde fois (`agrierp_laravel/tests/Feature/SyncInventaireRegularisationTest.php`).
/// Attendus à la main : 10 h 30 au Bénin (UTC+1) = 09 h 30 UTC, quel que soit le fuseau du poste (S-T11).
class _Connexion implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  final envois = <Map<String, dynamic>>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      return handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [for (final e in value) if (e is Map && e['id'] is String) e['id']],
                  'rejected': [],
                },
          },
        ),
      );
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {'server_time': '2026-10-21T11:00:00Z'},
      ),
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: 'p0000000-0000-4000-8000-000000000001',
        sku: 'ALI-001',
        name: 'Aliment croissance',
        unit: 'sac',
        pricingMode: 'fixe',
        syncStatus: const Value(SyncStatus.synced),
      ),
    );
    await db.into(db.suppliers).insert(
      SuppliersCompanion.insert(
        id: 's0000000-0000-4000-8000-000000000001',
        name: 'Provenderie du Sud',
        syncStatus: const Value(SyncStatus.synced),
      ),
    );
  });

  tearDown(() async => db.close());

  test('⚠️⚠️ l\'achat part avec son INSTANT en UTC (purchased_at) et son jour (purchase_date)', () async {
    final serveur = _Serveur();
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur);
    final moteur = SyncEngine(database: db, client: client, deviceId: 'poste-bureau', connectivity: _Connexion());
    final produit = await db.select(db.products).getSingle();

    final id = await AchatsRepository(database: db, identifiantPoste: 'poste-bureau').enregistrer(
      fournisseurId: 's0000000-0000-4000-8000-000000000001',
      lignes: [LigneSaisieAchat(produit: produit, quantite: 10, prixUnitaire: 15000)],
      modePaiement: 'especes',
      compteId: 'c0000000-0000-4000-8000-000000000001',
      montantPaye: 150000,
      // Heure MURALE du Bénin : mardi 20 octobre, 10 h 30.
      date: DateTime(2026, 10, 20, 10, 30),
    );
    await moteur.synchroniser();

    final achat = ((serveur.envois.single['purchases'] as List).single as Map).cast<String, dynamic>();
    expect(achat['id'], id);
    expect(achat['purchase_date'], '2026-10-20');
    expect(achat['purchased_at'], '2026-10-20T09:30:00.000Z', reason: '10 h 30 au Bénin = 09 h 30 UTC');
  });
}
