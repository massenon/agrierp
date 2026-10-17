@Tags(['integration'])
library;

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.20 — SYNCHRONISATION CONTRE LE SERVEUR RÉEL.
///
/// ⚠️⚠️ **CE QUE LES AUTRES TESTS NE PEUVENT PAS VOIR.** Toute la suite
/// simule le serveur : elle prouve que le poste sait absorber **ce qu'elle lui
/// donne**, jamais qu'il sait absorber **ce que le serveur envoie vraiment**.
/// Un nom de champ divergent (`label` contre `name`, `code` contre
/// `account_number`) passe inaperçu des deux côtés — le serveur sert
/// correctement, le poste absorbe correctement sa propre fiction, et le défaut
/// n'apparaît qu'au déploiement.
///
/// Ce test fait un vrai aller : connexion, tirage, vérification des tables
/// locales.
///
/// ⚠️ **LECTURE SEULE, DÉLIBÉRÉMENT.** Pousser créerait de vraies dépenses,
/// décaisserait une trésorerie réelle et passerait des écritures dans la base
/// de démonstration. Le poussage est déjà couvert côté serveur
/// (`SyncDepensesTest`, `EggProductionStockTest`).
///
/// Exécution : `flutter test test/sync_reel_test.dart`
/// avec le serveur lancé (`php artisan serve --port=8002`).
/// Sans serveur joignable, le test **s'annonce ignoré** plutôt que d'échouer —
/// un échec rouge à chaque exécution hors ligne finirait par être ignoré pour
/// de bon.
/// ⚠️ `connectivity_plus` passe par un canal de plateforme, absent d'un
/// `flutter test`. Le moteur se croirait hors ligne et n'appellerait jamais le
/// serveur — le test passerait alors sans rien prouver.
class _ConnectiviteReelle implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

void main() {
  const adresse = 'http://127.0.0.1:8002';
  const identifiant = 'admin';
  const motDePasse = 'AgriERP@2026';

  late AppDatabase db;
  late Dio client;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = Dio(
      BaseOptions(
        baseUrl: adresse,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
        // Le serveur répond 401/422 avec un corps utile : ne pas jeter dessus.
        validateStatus: (code) => code != null && code < 500,
      ),
    );
  });

  tearDown(() async => db.close());

  /// `null` si le serveur n'est pas joignable.
  Future<String?> connecter() async {
    try {
      final reponse = await client.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {
          'identifiant': identifiant,
          'password': motDePasse,
          'device_name': 'poste-test-integration',
        },
      );

      return reponse.data?['token'] as String?;
    } on DioException {
      return null;
    }
  }

  test(
    '⚠️⚠️ un tirage réel remplit les tables du poste',
    () async {
      final jeton = await connecter();

      if (jeton == null) {
        markTestSkipped(
          'Serveur injoignable sur $adresse — lancez `php artisan serve '
          '--port=8002` pour exécuter ce test.',
        );
        return;
      }

      client.options.headers['Authorization'] = 'Bearer $jeton';

      final moteur = SyncEngine(
        database: db,
        client: client,
        deviceId: 'poste-test-integration',
        connectivity: _ConnectiviteReelle(),
      );

      final resultat = await moteur.synchroniser();

      expect(
        resultat.horsLigne,
        isFalse,
        reason: 'le moteur se croit hors ligne alors que le serveur repond',
      );
      expect(
        resultat.tire,
        greaterThan(0),
        reason: 'un tirage qui ne ramene rien ne prouve rien',
      );

      // ── Ce que le poste doit avoir reçu ────────────────────────────────

      final produits = await db.select(db.products).get();
      final bandes = await db.select(db.livestockLots).get();

      // ⚠️⚠️ SERVEUR DEBOUT MAIS BASE VIDE ≠ CODE CASSE. Un run Dusk permute le
      // `.env` : le serveur sert alors `agrierp_dusk`, vide par construction, et
      // ce test virait au ROUGE pour une raison d'environnement. Un rouge qui
      // n'accuse rien finit par etre ignore — on l'annonce donc comme ignore,
      // avec la cause probable.
      if (produits.isEmpty && bandes.isEmpty) {
        markTestSkipped(
          'Le serveur repond mais sa base est vide — un run Dusk est '
          'probablement en cours (il permute le .env vers agrierp_dusk).',
        );
        return;
      }

      expect(produits, isNotEmpty, reason: 'le catalogue doit descendre');
      expect(
        bandes,
        isNotEmpty,
        reason: 'sans bandes, les cinq fiches sont vides',
      );

      // ⚠️ LE POINT QU'AUCUN TEST SIMULÉ NE COUVRE : le code espèce arrive-t-il
      // vraiment ? C'est lui qui porte le garde-fou du stock d'œufs et le
      // filtrage de chaque fiche.
      expect(
        bandes.every((b) => (b.speciesCode ?? '').isNotEmpty),
        isTrue,
        reason: 'une bande sans code espèce est invisible de toutes les fiches',
      );

      final comptes = await db.select(db.treasuryAccounts).get();
      expect(
        comptes,
        isNotEmpty,
        reason: 'sans compte payeur, aucune dépense ne peut être saisie',
      );
      expect(
        comptes.every((c) => c.label.isNotEmpty),
        isTrue,
        reason:
            'un libellé vide trahirait un nom de champ divergent '
            '(`label` contre `name`)',
      );

      final categories = await db.select(db.expenseCategories).get();
      expect(
        categories,
        isNotEmpty,
        reason: 'sans compte de charge, la saisie de dépense est impossible',
      );

      final rations = await db.select(db.feedRationStandards).get();
      expect(rations, isNotEmpty);

      // ⚠️ Les bornes de cycle : sans elles le poste devrait relire le libellé
      // libre, ce que le serveur a explicitement refusé de faire.
      final protocoles = await db.select(db.prophylaxisScheduleStandards).get();
      expect(protocoles, isNotEmpty);
      expect(
        protocoles.any((p) => p.cycleDayStart != null),
        isTrue,
        reason:
            'aucune borne reçue : le protocole du jour serait indéterminable '
            'partout',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    "⚠️ l'horloge retenue est celle du SERVEUR, pas celle du poste",
    () async {
      final jeton = await connecter();

      if (jeton == null) {
        markTestSkipped('Serveur injoignable sur $adresse.');
        return;
      }

      client.options.headers['Authorization'] = 'Bearer $jeton';

      final moteur = SyncEngine(
        database: db,
        client: client,
        deviceId: 'poste-test-integration',
        connectivity: _ConnectiviteReelle(),
      );

      await moteur.synchroniser();

      final etat = await db.select(db.syncState).getSingleOrNull();

      // Une tablette dont l'horloge retarde redemanderait sans cesse les mêmes
      // changements ; une qui avance en sauterait définitivement.
      expect(
        etat?.lastPulledAt,
        isNotNull,
        reason: 'sans horodatage serveur, le tirage incrémental est impossible',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
