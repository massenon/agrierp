import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
// Drift exporte `isNull` / `isNotNull` (expressions SQL) : masqués ici pour
// laisser accessibles les matchers homonymes de `flutter_test`.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.90 — correctifs du poste issus de l'audit indépendant de la chaîne « ventes datées ».
///
///  - **D2** : « Relancer » une vente renvoyait la fiche `synced` du jour de la vente TELLE QUE LE
///    POSTE LA DÉTIENT ; le serveur applique « dernier écrivain gagne » (`pushDailyEntries` :
///    `fill` de toutes les colonnes reçues) : une correction faite entre-temps sur le web (2 morts)
///    était écrasée.
///  - **B1** : deux lignes du même produit dans un panier → stock local 19 au lieu de 17.
///  - **B2** : `_absorberVentes` mettait `updatedAt = sold_at` (horodatage antidaté).
///
/// ⚠️ Tous les chiffres attendus sont des LITTÉRAUX calculés à la main (détail en commentaire),
/// jamais obtenus en appelant le code testé.
class _ConnectiviteFeinte implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// MODÈLE du serveur, réécrit à la main d'après la LECTURE de `SyncController::push`,
/// `pushDailyEntries`, `pushSales` et `RecordSaleOnFicheElevageAction::execute` (Laravel, 15.33).
///
///  - fiche reçue : retrouvée par `id`, sinon créée avec les DÉFAUTS de la migration (achat, ne,
///    mort, vente = 0, don = nul) ; `lot_id` et `entry_date` sont EXIGÉS (validateur) ; puis
///    `fill(except id, effectif_final)` : SEULES les clés PRÉSENTES sont écrites (Eloquent) ;
///    une seconde fiche (bande, jour) sous un autre `id` est refusée (contrainte unique) ;
///  - vente reçue : refusée si son `id` est dans [ventesRefusees] (motif tel quel) ; déjà connue =
///    succès silencieux sans effet ; sinon `vente += qty` sur la fiche (bande, jour de `sold_at`)
///    — créée au besoin (`firstOrCreate`) — SAUF si une fiche (bande, jour) a été CRÉÉE par le
///    MÊME envoi (15.30, restreint par S-T9) ; refusée, elle est retirée de cette fiche créée ;
///  - S-T9 : la `vente` d'une fiche DÉJÀ connue (même `id`) n'est jamais reprise du poste.
class _ServeurModele extends Interceptor {
  _ServeurModele({this.tirage = const {}});

  /// Corps servi à `GET /api/sync/pull`.
  Map<String, dynamic> tirage;

  /// `id` de vente → motif de refus (mois clôturé…).
  final Map<String, String> ventesRefusees = {};

  /// `id` de fiche → colonnes stockées.
  final Map<String, Map<String, Object?>> fiches = {};

  final Set<String> ventesConnues = {};

  final List<Map<String, dynamic>> corpsRecus = [];

  static const _remplissables = {
    'lot_id',
    'entry_date',
    'achat',
    'ne',
    'mort',
    'vente',
    'don',
    'ponte_total',
    'ponte_casses',
    'feed_qty_kg',
    'weight_sample_avg_g',
  };

  /// Fiche (bande, jour) côté serveur.
  Map<String, Object?>? ficheDe(String lot, String jour) {
    for (final f in fiches.values) {
      if (f['lot_id'] == lot && f['entry_date'] == jour) return f;
    }
    return null;
  }

  /// Fiche connue du serveur (déjà synchronisée par le poste).
  void connaitre(
    String id,
    String lot,
    String jour, {
    int mort = 0,
    int achat = 0,
    int vente = 0,
  }) {
    fiches[id] = {
      'lot_id': lot,
      'entry_date': jour,
      'achat': achat,
      'ne': 0,
      'mort': mort,
      'vente': vente,
      'don': null,
    };
  }

  Map<String, dynamic> _push(Map<String, dynamic> corps) {
    final fichesAcceptees = <String>[];
    final fichesRefusees = <Map<String, String>>[];
    final recues = <String>{};

    for (final brut in corps['livestock_daily_entries'] as List? ?? const []) {
      final e = brut as Map;
      final id = e['id'] as String;
      if (e['lot_id'] == null || e['entry_date'] == null) {
        fichesRefusees.add({
          'id': id,
          'reason': 'Le champ bande ou date est obligatoire.',
        });
        continue;
      }
      final existante = fiches[id];
      final cible =
          existante ??
          <String, Object?>{
            'achat': 0,
            'ne': 0,
            'mort': 0,
            'vente': 0,
            'don': null,
          };
      final doublon = ficheDe(e['lot_id'] as String, e['entry_date'] as String);
      if (existante == null && doublon != null) {
        fichesRefusees.add({
          'id': id,
          'reason': 'Une fiche existe deja pour cette bande a cette date.',
        });
        continue;
      }
      for (final cle in e.keys) {
        if (!_remplissables.contains(cle)) continue;
        // S-T9 : la vente d'une fiche connue appartient au serveur.
        if (cle == 'vente' && existante != null) continue;
        cible[cle as String] = e[cle];
      }
      fiches[id] = cible;
      fichesAcceptees.add(id);
      if (existante == null) recues.add('${cible['lot_id']}|${cible['entry_date']}');
    }

    final ventesAcceptees = <String>[];
    final ventesRejetees = <Map<String, String>>[];

    for (final brut in corps['sales'] as List? ?? const []) {
      final v = brut as Map;
      final id = v['id'] as String;
      if (ventesConnues.contains(id)) {
        ventesAcceptees.add(id);
        continue;
      }
      final motif = ventesRefusees[id];
      if (motif != null) {
        ventesRejetees.add({'id': id, 'reason': motif});
        // S-T9 : la vente refusée est retirée de la fiche CRÉÉE par le même envoi.
        final jourRefuse = (v['sold_at'] as String).substring(0, 10);
        for (final l in v['lines'] as List) {
          final lot = (l as Map)['lot_id'] as String?;
          final fiche = lot == null ? null : ficheDe(lot, jourRefuse);
          if (fiche != null && recues.contains('$lot|$jourRefuse')) {
            final reste = (fiche['vente'] as int) - (l['qty'] as num).toInt();
            fiche['vente'] = reste < 0 ? 0 : reste;
          }
        }
        continue;
      }
      final jour = (v['sold_at'] as String).substring(0, 10);
      for (final l in v['lines'] as List) {
        final ligne = l as Map;
        final lot = ligne['lot_id'] as String?;
        if (lot == null) continue;
        final cle = '$lot|$jour';
        var fiche = ficheDe(lot, jour);
        if (fiche == null) {
          fiche = {
            'lot_id': lot,
            'entry_date': jour,
            'achat': 0,
            'ne': 0,
            'mort': 0,
            'vente': 0,
            'don': 0,
          };
          fiches['serveur-$cle'] = fiche;
        }
        if (!recues.contains(cle)) {
          fiche['vente'] =
              (fiche['vente'] as int) + (ligne['qty'] as num).toInt();
        }
      }
      ventesConnues.add(id);
      ventesAcceptees.add(id);
    }

    return {
      'livestock_daily_entries': {
        'accepted': fichesAcceptees,
        'rejected': fichesRefusees,
      },
      'sales': {'accepted': ventesAcceptees, 'rejected': ventesRejetees},
    };
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final estPush = options.path.contains('push');
    Map<String, dynamic> reponse = tirage;
    if (estPush && options.data is Map<String, dynamic>) {
      final corps = options.data as Map<String, dynamic>;
      corpsRecus.add(corps);
      reponse = _push(corps);
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: reponse,
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late CaisseRepository caisse;

  /// Mardi 14/10/2026, 10:15:30 — l'instant de la SAISIE au comptoir.
  final saisie = DateTime(2026, 10, 14, 10, 15, 30);

  /// Mardi 14/10/2026, 16:00:00 — l'instant de la RÉCEPTION au tirage (horloge du moteur).
  final reception = DateTime(2026, 10, 14, 16);

  const bande = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const espece = 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee';
  const idPoulet = 'pppppppp-1111-4111-8111-pppppppppppp';
  const idProvende = 'qqqqqqqq-1111-4111-8111-qqqqqqqqqqqq';
  const f12 = 'f1200000-0000-4000-8000-000000000000';
  const f13 = 'f1300000-0000-4000-8000-000000000000';
  const f14 = 'f1400000-0000-4000-8000-000000000000';
  const moisClos = 'Vente refusée : le mois 2026-10 est clôturé.';

  late Product poulet;
  late Product provende;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    caisse = CaisseRepository(
      database: db,
      deviceId: 'poste-test',
      maintenant: () => saisie,
    );

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bande,
            code: 'AVI-2026-01',
            speciesId: espece,
            initialQuantity: const Value(50),
            currentQuantity: const Value(50),
          ),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: idPoulet,
            sku: 'AVI-001',
            name: 'Poulet goliath',
            speciesId: const Value(espece),
            unit: 'u',
            pricingMode: 'fourchette',
            priceMin: const Value(3000),
            priceMax: const Value(4000),
            stockQty: const Value(50),
          ),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: idProvende,
            sku: 'ALI-001',
            name: 'Provende ponte',
            unit: 'sac',
            pricingMode: 'fixe',
            priceMin: const Value(6500),
            stockQty: const Value(20),
          ),
        );
    poulet = await (db.select(
      db.products,
    )..where((t) => t.id.equals(idPoulet))).getSingle();
    provende = await (db.select(
      db.products,
    )..where((t) => t.id.equals(idProvende))).getSingle();
  });

  tearDown(() async => db.close());

  SyncEngine moteur(_ServeurModele serveur) {
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'));
    client.interceptors.add(serveur);
    return SyncEngine(
      database: db,
      client: client,
      deviceId: 'poste-test',
      connectivity: _ConnectiviteFeinte(),
      maintenant: () => reception,
    );
  }

  /// Fiche déjà saisie et SYNCHRONISÉE au poste.
  Future<void> fiche(
    String id,
    DateTime jour, {
    int achat = 0,
    int mort = 0,
    required int effectif,
    SyncStatus statut = SyncStatus.synced,
  }) => db
      .into(db.livestockDailyEntries)
      .insert(
        LivestockDailyEntriesCompanion.insert(
          id: id,
          deviceId: 'poste-test',
          syncStatus: Value(statut),
          updatedAt: jour,
          lotId: bande,
          entryDate: jour,
          achat: Value(achat),
          mort: Value(mort),
          effectifFinal: Value(effectif),
        ),
      );

  /// Jeu de 15.31, au poste ET au serveur : 12/10 mort 1 → 49 ; 13/10 mort 2 → 47 ;
  /// 14/10 achat 3 → 50.
  Future<_ServeurModele> troisFichesSynchronisees() async {
    await fiche(f12, DateTime(2026, 10, 12), mort: 1, effectif: 49);
    await fiche(f13, DateTime(2026, 10, 13), mort: 2, effectif: 47);
    await fiche(f14, DateTime(2026, 10, 14), achat: 3, effectif: 50);
    final serveur = _ServeurModele();
    serveur.connaitre(f12, bande, '2026-10-12', mort: 1);
    serveur.connaitre(f13, bande, '2026-10-13', mort: 2);
    serveur.connaitre(f14, bande, '2026-10-14', achat: 3);
    return serveur;
  }

  List<LignePanier> sixPoulets() => [
    LignePanier(produit: poulet, quantite: 6, montant: 21000, lotId: bande),
  ];

  Future<LivestockDailyEntry> ficheLocale(String id) => (db.select(
    db.livestockDailyEntries,
  )..where((t) => t.id.equals(id))).getSingle();

  Future<Sale> venteLocale(String id) =>
      (db.select(db.sales)..where((t) => t.id.equals(id))).getSingle();

  /// Vente de 6 poulets datée du 12/10, refusée au 1er envoi (mois clôturé), puis relancée.
  Future<(Sale, SyncEngine)> venteRefuseePuisRelancee(
    _ServeurModele serveur,
  ) async {
    final vente = await caisse.enregistrerVente(
      panier: sixPoulets(),
      modePaiement: 'especes',
      dateVente: DateTime(2026, 10, 12),
    );
    serveur.ventesRefusees[vente.id] = moisClos;
    final sync = moteur(serveur);
    await sync.synchroniser();
    serveur.ventesRefusees.remove(vente.id);
    return (vente, sync);
  }

  group('D2 — relancer une vente : ni double comptage, ni écrasement', () {
    test(
      '🔴 correction web (2 morts) entre le refus et la relance : conservée, vente = 6',
      () async {
        final serveur = await troisFichesSynchronisees();
        final (vente, sync) = await venteRefuseePuisRelancee(serveur);

        // 1er envoi : la vente est refusée. S-T9 : la fiche du 12, déjà synchronisée, n'est partie que
        // réduite à son identité — elle ne porte pas une vente qui n'existe pas au serveur (avant S-T9 :
        // 6 sujets « vendus » sur la fiche pour une vente refusée).
        expect(serveur.fiches[f12]!['vente'], 0);
        expect(serveur.fiches[f12]!['mort'], 1);

        // Entre-temps, sur le web : l'animalier corrige la fiche du 12 à 2 morts.
        serveur.fiches[f12]!['mort'] = 2;

        await sync.relancer(await db.select(db.syncConflicts).getSingle());
        await sync.synchroniser();

        expect(
          serveur.fiches[f12]!['mort'],
          2,
          reason:
              'la correction web ne doit pas être écrasée par la copie du poste (1)',
        );
        expect(
          serveur.fiches[f12]!['vente'],
          6,
          reason: '6 et non 12 : la vente ne compte qu une fois',
        );
        expect(serveur.ventesConnues, contains(vente.id));
        expect((await venteLocale(vente.id)).syncStatus, SyncStatus.synced);
        expect(await db.select(db.syncConflicts).get(), isEmpty);
      },
    );

    test(
      '🔴 la fiche qui accompagne la relance ne porte QUE son identité (id, bande, jour)',
      () async {
        final serveur = await troisFichesSynchronisees();
        final (_, sync) = await venteRefuseePuisRelancee(serveur);

        await sync.relancer(await db.select(db.syncConflicts).getSingle());
        await sync.synchroniser();

        final fiches =
            serveur.corpsRecus.last['livestock_daily_entries'] as List;
        expect(
          fiches,
          hasLength(1),
          reason: 'seule la fiche du 12 (pas le 13 ni le 14)',
        );
        expect(fiches.single, {
          'id': f12,
          'lot_id': bande,
          'entry_date': '2026-10-12',
        });
      },
    );

    test(
      '🔴 relancer ne remet PAS la fiche locale en file : elle reste synced',
      () async {
        final serveur = await troisFichesSynchronisees();
        final (_, sync) = await venteRefuseePuisRelancee(serveur);
        expect((await ficheLocale(f12)).syncStatus, SyncStatus.synced);

        await sync.relancer(await db.select(db.syncConflicts).getSingle());

        expect(
          (await ficheLocale(f12)).syncStatus,
          SyncStatus.synced,
          reason: 'le poste ne prétend pas avoir modifié cette fiche',
        );
        for (final id in [f13, f14]) {
          expect((await ficheLocale(id)).syncStatus, SyncStatus.synced);
        }
      },
    );

    test(
      '🔴 une fiche locale en conflict ne repart pas avec la relance (le serveur ajoutera la vente à SA fiche)',
      () async {
        final serveur = _ServeurModele();
        // La fiche du 12 de CE poste a été refusée (doublon d'un autre poste) ; le serveur a la sienne.
        await fiche(
          f12,
          DateTime(2026, 10, 12),
          mort: 1,
          effectif: 49,
          statut: SyncStatus.conflict,
        );
        serveur.connaitre('web-fiche-12', bande, '2026-10-12', mort: 1);

        final vente = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 12),
        );
        // La vente répercutée a remis la fiche en file : on reproduit l'état « conflict » d'après
        // le refus du doublon.
        await (db.update(
          db.livestockDailyEntries,
        )..where((t) => t.id.equals(f12))).write(
          const LivestockDailyEntriesCompanion(
            syncStatus: Value(SyncStatus.conflict),
          ),
        );
        await (db.update(db.sales)..where((t) => t.id.equals(vente.id))).write(
          const SalesCompanion(syncStatus: Value(SyncStatus.conflict)),
        );
        await db
            .into(db.syncConflicts)
            .insert(
              SyncConflictsCompanion.insert(
                id: 'sales:${vente.id}',
                sourceTable: 'sales',
                recordId: vente.id,
                reason: moisClos,
                detectedAt: saisie,
              ),
            );

        final sync = moteur(serveur);
        await sync.relancer(
          await (db.select(
            db.syncConflicts,
          )..where((t) => t.sourceTable.equals('sales'))).getSingle(),
        );
        await sync.synchroniser();

        final fiches =
            serveur.corpsRecus.single['livestock_daily_entries'] as List;
        expect(fiches, isEmpty);
        expect(serveur.fiches['web-fiche-12']!['vente'], 6);
        expect((await ficheLocale(f12)).syncStatus, SyncStatus.conflict);
      },
    );

    test(
      '🔴 fiches d identité et fiches complètes partent ensemble, dans l ordre des jours, sans doublon',
      () async {
        final serveur = await troisFichesSynchronisees();
        final (_, sync) = await venteRefuseePuisRelancee(serveur);
        await sync.relancer(await db.select(db.syncConflicts).getSingle());

        // Nouvelle vente du jour : S-T9 — la fiche du 14, déjà synchronisée, part elle aussi réduite à son identité ;
        // c'est la vente qui y inscrit ses 2 sujets au serveur.
        await caisse.enregistrerVente(
          panier: [
            LignePanier(
              produit: poulet,
              quantite: 2,
              montant: 7000,
              lotId: bande,
            ),
          ],
          modePaiement: 'especes',
        );
        await sync.synchroniser();

        final fiches = [
          for (final f
              in serveur.corpsRecus.last['livestock_daily_entries'] as List)
            f as Map,
        ];
        expect(
          [for (final f in fiches) f['entry_date']],
          ['2026-10-12', '2026-10-14'],
        );
        expect(fiches.first.containsKey('mort'), isFalse);
        expect(fiches.last['id'], f14);
        expect(fiches.last.containsKey('vente'), isFalse);
        expect(
          fiches.where((f) => f['id'] == f12),
          hasLength(1),
          reason: 'jamais deux fois le même identifiant dans un envoi',
        );
        // Fiche du 12 : 6 (relance, comptée une fois) ; fiche du 14 : 2 (inscrits par la vente, une fois).
        expect(serveur.fiches[f12]!['vente'], 6);
        expect(serveur.fiches[f14]!['vente'], 2);
      },
    );

    test(
      '🔴 une vente fraîche part avec la fiche RÉDUITE de son jour (S-T9), une vente déjà acquittée ne fait rien repartir',
      () async {
        final serveur = await troisFichesSynchronisees();
        await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 12),
        );
        final sync = moteur(serveur);
        await sync.synchroniser();

        final premiers =
            serveur.corpsRecus.single['livestock_daily_entries'] as List;
        // S-T9 : la fiche du 12 est déjà synchronisée ; renvoyée complète, elle porterait les morts TELS QUE LE
        // COMPTOIR LES A TIRÉS (une correction de l'animalier écrasée). Seule son identité part ; la vente compte.
        expect(premiers, hasLength(1));
        expect((premiers.single as Map).keys, unorderedEquals(['id', 'lot_id', 'entry_date']));
        expect(serveur.fiches[f12]!['vente'], 6);
        expect(serveur.fiches[f12]!['mort'], 1);

        // Synchronisation suivante : rien en file, aucune fiche ne repart.
        await sync.synchroniser();
        final suivants = serveur.corpsRecus.length > 1
            ? serveur.corpsRecus.last['livestock_daily_entries'] as List
            : const [];
        expect(suivants, isEmpty);
        expect(serveur.fiches[f12]!['vente'], 6);
      },
    );

    test(
      '🔴 le jour de la fiche d identité est celui de la VENTE (sold_at), pas de la saisie',
      () async {
        final serveur = await troisFichesSynchronisees();
        final (_, sync) = await venteRefuseePuisRelancee(serveur);
        await sync.relancer(await db.select(db.syncConflicts).getSingle());
        await sync.synchroniser();

        final fiches =
            serveur.corpsRecus.last['livestock_daily_entries'] as List;
        expect([for (final f in fiches) (f as Map)['id']], [f12]);
        // La fiche du 14 (jour de la saisie) n'a rien reçu.
        expect(serveur.fiches[f14]!['vente'], 0);
      },
    );
  });

  group('B1 — deux lignes du même produit dans un panier', () {
    test('🔴 stock 20, lignes de 2 et 1 → 17 (et non 19)', () async {
      await caisse.enregistrerVente(
        panier: [
          LignePanier(produit: provende, quantite: 2, montant: 13000),
          LignePanier(produit: provende, quantite: 1, montant: 6500),
        ],
        modePaiement: 'especes',
      );

      final relu = await (db.select(
        db.products,
      )..where((t) => t.id.equals(idProvende))).getSingle();
      // 20 − 2 − 1 = 17.
      expect(relu.stockQty, 17);
    });

    test(
      '🔴 deux lignes de poulets (3 et 2) de la même bande : stock 45, fiche vente 5, bande 45',
      () async {
        await caisse.enregistrerVente(
          panier: [
            LignePanier(
              produit: poulet,
              quantite: 3,
              montant: 10500,
              lotId: bande,
            ),
            LignePanier(
              produit: poulet,
              quantite: 2,
              montant: 7000,
              lotId: bande,
            ),
          ],
          modePaiement: 'especes',
        );

        final relu = await (db.select(
          db.products,
        )..where((t) => t.id.equals(idPoulet))).getSingle();
        // 50 − 3 − 2 = 45.
        expect(relu.stockQty, 45);

        final fiches = await db.select(db.livestockDailyEntries).get();
        expect(fiches, hasLength(1));
        expect(fiches.single.vente, 5);
        // Effectif initial 50, aucune fiche antérieure : 50 − 5 = 45.
        expect(fiches.single.effectifFinal, 45);
        final lot = await (db.select(
          db.livestockLots,
        )..where((t) => t.id.equals(bande))).getSingle();
        expect(lot.currentQuantity, 45);
      },
    );

    test(
      '🔴 le stock part de l état RÉEL du produit, pas de l instantané du panier',
      () async {
        // Le produit a été mis au panier à 20 ; un tirage l'a porté à 30 avant la validation.
        await (db.update(db.products)..where((t) => t.id.equals(idProvende)))
            .write(const ProductsCompanion(stockQty: Value(30)));

        await caisse.enregistrerVente(
          panier: [LignePanier(produit: provende, quantite: 2, montant: 13000)],
          modePaiement: 'especes',
        );

        final relu = await (db.select(
          db.products,
        )..where((t) => t.id.equals(idProvende))).getSingle();
        // 30 − 2 = 28 (l'instantané aurait donné 20 − 2 = 18).
        expect(relu.stockQty, 28);
      },
    );
  });

  group('B2 — updatedAt des ventes tirées du serveur', () {
    Map<String, dynamic> venteServie(String id, String soldAt) => {
      'id': id,
      'customer_id': null,
      'customer_name': null,
      'payment_mode': 'especes',
      'total': 21000,
      'status': 'validee',
      'mecef_status': 'transmise',
      'mecef_qr_ref': 'QR-1',
      'sold_at': soldAt,
    };

    test(
      '🔴 vente inconnue du poste : updatedAt = instant de RÉCEPTION, jamais sold_at',
      () async {
        const id = 'v0000000-0000-4000-8000-000000000001';
        final serveur = _ServeurModele(
          tirage: {
            'sales': [venteServie(id, '2026-10-11T09:00:00+01:00')],
          },
        );
        await moteur(serveur).synchroniser();

        final v = await venteLocale(id);
        expect(
          v.updatedAt.isAtSameMomentAs(reception),
          isTrue,
          reason:
              'reçu le 14/10 à 16:00, et non antidaté au 11/10 (${v.updatedAt})',
        );
        expect(
          v.soldAt.isAtSameMomentAs(DateTime.utc(2026, 10, 11, 8)),
          isTrue,
          reason: 'la date de la vente, elle, reste celle du serveur',
        );
        expect(v.syncStatus, SyncStatus.synced);
      },
    );

    test(
      '🔴 vente saisie sur CE poste (antidatée) puis redescendue : updatedAt = instant de la SAISIE',
      () async {
        final vente = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 11),
        );
        final serveur = _ServeurModele();
        final sync = moteur(serveur);
        await sync.synchroniser();
        expect((await venteLocale(vente.id)).syncStatus, SyncStatus.synced);

        // Tirage suivant : le serveur la sert (statut MeCeF mis à jour).
        serveur.tirage = {
          'sales': [venteServie(vente.id, '2026-10-11T10:15:30+01:00')],
        };
        await sync.synchroniser();

        final v = await venteLocale(vente.id);
        expect(v.mecefStatus, 'transmise', reason: 'la fusion a bien eu lieu');
        expect(
          v.updatedAt.isAtSameMomentAs(saisie),
          isTrue,
          reason: 'saisie le 14/10 à 10:15:30 (${v.updatedAt})',
        );
      },
    );

    test(
      '🔴 F0.93 — vente servie SANS sold_at : repli sur l HORLOGE INJECTÉE, jamais DateTime.now()',
      () async {
        // Réserve 2 de l'audit indépendant du 14/10/2026 : le repli de
        // `sold_at` absent lisait l'horloge système, alors que le moteur porte
        // une horloge injectée (`maintenant`, F0.90). Une vente reçue deux
        // fois aurait reçu deux dates de vente différentes, et aucun test à
        // horloge figée n'aurait pu le voir.
        const id = 'v0000000-0000-4000-8000-000000000093';
        final servie = venteServie(id, 'x')..['sold_at'] = null;
        await moteur(
          _ServeurModele(
            tirage: {
              'sales': [servie],
            },
          ),
        ).synchroniser();

        final v = await venteLocale(id);
        expect(
          v.soldAt.isAtSameMomentAs(reception),
          isTrue,
          reason: 'horloge figée au 14/10 16:00, lu ${v.soldAt}',
        );
        expect(v.updatedAt.isAtSameMomentAs(reception), isTrue);
      },
    );

    test(
      '🔴 F0.93 — sold_at illisible : même repli sur l horloge injectée',
      () async {
        const id = 'v0000000-0000-4000-8000-000000000094';
        await moteur(
          _ServeurModele(
            tirage: {
              'sales': [venteServie(id, 'pas-une-date')],
            },
          ),
        ).synchroniser();

        final v = await venteLocale(id);
        expect(
          v.soldAt.isAtSameMomentAs(reception),
          isTrue,
          reason: '${v.soldAt}',
        );
      },
    );

    test(
      '🔴 vente pending du poste : le tirage ne la touche pas (ni horodatage, ni statut)',
      () async {
        final vente = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
        );
        // Le serveur ne répond rien au push (réponse vide) : la vente reste `pending`.
        final serveur = _ServeurModele(
          tirage: {
            'sales': [venteServie(vente.id, '2026-10-01T08:00:00+01:00')],
          },
        );
        serveur.ventesRefusees[vente.id] = moisClos;
        await moteur(serveur).synchroniser();

        final v = await venteLocale(vente.id);
        expect(v.updatedAt.isAtSameMomentAs(saisie), isTrue);
        expect(v.soldAt.isAtSameMomentAs(saisie), isTrue);
        expect(v.mecefStatus, isNull);
      },
    );
  });
}
