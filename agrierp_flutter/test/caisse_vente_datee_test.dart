import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/caisse_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
// Drift exporte `isNull` / `isNotNull` (expressions SQL) : masqués ici pour
// laisser accessibles les matchers homonymes de `flutter_test`.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.89 — CHAMP « DATE DE LA VENTE » À LA CAISSE DU POSTE (ventes antérieures).
///
/// Décision client du 14/10/2026 : UN SEUL champ « Date de la vente » au PANIER (pas dans la
/// modale « Vente à la Pièce »). Écart ASSUMÉ avec `pos-interface.html`, qui n'a aucun champ de
/// date. Serveur : 15.30 (gardes de date, rejets motivés, double comptage fiche + vente), 15.31
/// (cascade des fiches), 15.32 (champ du POS web, bornes indicatives).
///
/// Horloge FIGÉE au mardi 14/10/2026 10:15:30 (comme les tests serveur 15.30–15.32) : la date du
/// jour n'est jamais lue sur la machine qui exécute le test.
///
/// ⚠️ Tous les chiffres attendus sont des LITTÉRAUX calculés à la main (détail en commentaire)
/// ou recalculés ici par une boucle indépendante — jamais obtenus en appelant le code testé.
class _ConnectiviteFeinte implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Serveur simulé : rend la réponse voulue au push, et peut « perdre » la réponse.
class _ServeurFeint extends Interceptor {
  _ServeurFeint({this.push = const {}, this.reponsePerdue = false});

  final Map<String, dynamic> push;

  /// Le serveur a reçu l'envoi mais la réponse ne revient jamais (coupure réseau).
  final bool reponsePerdue;

  final List<Map<String, dynamic>> corpsRecus = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final estPush = options.path.contains('push');

    if (estPush && options.data is Map<String, dynamic>) {
      corpsRecus.add(options.data as Map<String, dynamic>);
      if (reponsePerdue) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
          ),
        );
        return;
      }
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: estPush ? push : const {},
      ),
    );
  }
}

/// MODÈLE de la règle serveur 15.30 (`SyncController::push` + `RecordSaleOnFicheElevageAction`),
/// réécrit ici à la main pour compter ce que le SERVEUR inscrirait en `vente` sur la fiche
/// (bande, jour) au fil des envois :
///  - une fiche reçue et acceptée écrit SES clés présentes sur la valeur serveur (dernier écrivain
///    gagne, `fill` d'Eloquent) — F0.90 : une fiche d'IDENTITÉ (sans `vente`) ne change pas la
///    vente inscrite, mais compte comme fiche reçue dans cet envoi ;
///  - une vente acceptée ajoute sa quantité, SAUF si la fiche (bande, jour) a été acceptée dans
///    le MÊME envoi (elle porte déjà la vente).
class _ModeleServeurVentes {
  /// `lot|AAAA-MM-JJ` → vente inscrite sur la fiche du serveur.
  final Map<String, int> venteParFiche = {};

  /// Identifiants des fiches que le serveur connaît (S-T9).
  final Set<String> fichesConnues = {};

  void appliquer(
    Map<String, dynamic> corps, {
    required Set<String> fichesAcceptees,
    required Set<String> ventesAcceptees,
  }) {
    // S-T9 : seule une fiche CRÉÉE par l'envoi (inconnue du serveur) porte sa vente et dispense les ventes du même
    // envoi ; la vente d'une fiche connue n'est jamais reprise du poste.
    final recues = <String>{};
    for (final f in (corps['livestock_daily_entries'] as List? ?? const [])) {
      final fiche = f as Map;
      if (!fichesAcceptees.contains(fiche['id'])) continue;
      final cle = '${fiche['lot_id']}|${fiche['entry_date']}';
      if (!fichesConnues.add(fiche['id'] as String)) continue;
      if (fiche.containsKey('vente')) {
        venteParFiche[cle] = fiche['vente'] as int;
      }
      recues.add(cle);
    }
    for (final v in (corps['sales'] as List? ?? const [])) {
      final vente = v as Map;
      if (!ventesAcceptees.contains(vente['id'])) continue;
      final jour = (vente['sold_at'] as String).substring(0, 10);
      for (final l in vente['lines'] as List) {
        final ligne = l as Map;
        if (ligne['lot_id'] == null) continue;
        final cle = '${ligne['lot_id']}|$jour';
        if (recues.contains(cle)) continue;
        venteParFiche[cle] =
            (venteParFiche[cle] ?? 0) + (ligne['qty'] as num).toInt();
      }
    }
  }
}

void main() {
  late AppDatabase db;
  late CaisseRepository caisse;

  /// Mardi 14/10/2026, 10:15:30 — l'instant de la SAISIE dans tout ce fichier.
  final maintenant = DateTime(2026, 10, 14, 10, 15, 30);

  const bande = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const espece = 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee';
  const idPoulet = 'pppppppp-1111-4111-8111-pppppppppppp';
  const idProvende = 'qqqqqqqq-1111-4111-8111-qqqqqqqqqqqq';

  late Product poulet;
  late Product provende;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    caisse = CaisseRepository(
      database: db,
      deviceId: 'poste-test',
      maintenant: () => maintenant,
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

  Future<void> exercice(
    String id,
    int annee,
    DateTime debut,
    DateTime fin,
    String statut,
  ) => db
      .into(db.fiscalYears)
      .insert(
        FiscalYearsCompanion.insert(
          id: id,
          year: annee,
          startDate: Value(debut),
          endDate: Value(fin),
          status: Value(statut),
        ),
      );

  /// Exercice 2025 CLOS, exercice 2026 OUVERT.
  Future<void> exercicesUsuels() async {
    await exercice(
      'f2025000-0000-4000-8000-000000000000',
      2025,
      DateTime(2025, 1, 1),
      DateTime(2025, 12, 31),
      'cloture',
    );
    await exercice(
      'f2026000-0000-4000-8000-000000000000',
      2026,
      DateTime(2026, 1, 1),
      DateTime(2026, 12, 31),
      'ouvert',
    );
  }

  /// Fiche déjà saisie et SYNCHRONISÉE (venue d'une saisie antérieure).
  Future<void> fiche(
    String id,
    DateTime jour, {
    int achat = 0,
    int mort = 0,
    int vente = 0,
    required int effectif,
  }) => db
      .into(db.livestockDailyEntries)
      .insert(
        LivestockDailyEntriesCompanion.insert(
          id: id,
          deviceId: 'poste-test',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: jour,
          lotId: bande,
          entryDate: jour,
          achat: Value(achat),
          mort: Value(mort),
          vente: Value(vente),
          effectifFinal: Value(effectif),
        ),
      );

  /// Jeu de 15.31 : 12/10 mort 1 → 49 ; 13/10 mort 2 → 47 ; 14/10 achat 3 → 50 ; bande à 50.
  Future<void> troisFiches() async {
    await fiche(
      'f1200000-0000-4000-8000-000000000000',
      DateTime(2026, 10, 12),
      mort: 1,
      effectif: 49,
    );
    await fiche(
      'f1300000-0000-4000-8000-000000000000',
      DateTime(2026, 10, 13),
      mort: 2,
      effectif: 47,
    );
    await fiche(
      'f1400000-0000-4000-8000-000000000000',
      DateTime(2026, 10, 14),
      achat: 3,
      effectif: 50,
    );
  }

  Future<Map<String, int>> effectifs() async {
    final fiches = await (db.select(
      db.livestockDailyEntries,
    )..orderBy([(t) => OrderingTerm(expression: t.entryDate)])).get();
    return {
      for (final f in fiches)
        '${f.entryDate.day.toString().padLeft(2, '0')}/10': f.effectifFinal,
    };
  }

  Future<int> effectifBande() async => (await (db.select(
    db.livestockLots,
  )..where((t) => t.id.equals(bande))).getSingle()).currentQuantity;

  List<LignePanier> sixPoulets() => [
    LignePanier(produit: poulet, quantite: 6, montant: 21000, lotId: bande),
  ];

  SyncEngine moteur(_ServeurFeint serveur) {
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'));
    client.interceptors.add(serveur);
    return SyncEngine(
      database: db,
      client: client,
      deviceId: 'poste-test',
      connectivity: _ConnectiviteFeinte(),
    );
  }

  group('dépôt — dates de la vente', () {
    test(
      '🔴 vente datée J-3 : sold_at = J-3 à l heure de la saisie, updated_at = instant de saisie',
      () async {
        await exercicesUsuels();

        final vente = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 11),
        );

        expect(vente.soldAt, DateTime(2026, 10, 11, 10, 15, 30));
        expect(
          vente.updatedAt,
          DateTime(2026, 10, 14, 10, 15, 30),
          reason: 'updated_at = instant de la SAISIE, jamais antidaté',
        );
        expect(vente.syncStatus, SyncStatus.pending);
      },
    );

    test(
      '🔴 vente du jour strictement inchangée : sold_at = updated_at = maintenant',
      () async {
        await exercicesUsuels();

        final sansDate = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
        );
        final aujourdhui = await caisse.enregistrerVente(
          panier: [LignePanier(produit: provende, quantite: 1, montant: 6500)],
          modePaiement: 'especes',
          // Le jour même, à minuit : l'heure réelle de la saisie est gardée.
          dateVente: DateTime(2026, 10, 14),
        );

        for (final v in [sansDate, aujourdhui]) {
          expect(v.soldAt, maintenant);
          expect(v.updatedAt, maintenant);
        }

        final fiche = await db.select(db.livestockDailyEntries).getSingle();
        expect(fiche.entryDate, DateTime(2026, 10, 14));
        expect(fiche.vente, 6);
        expect(fiche.effectifFinal, 44, reason: '50 - 6');
        expect(await effectifBande(), 44);
      },
    );

    test(
      '🔴 date future refusée localement, message du serveur, aucune trace',
      () async {
        await exercicesUsuels();

        await expectLater(
          caisse.enregistrerVente(
            panier: sixPoulets(),
            modePaiement: 'especes',
            dateVente: DateTime(2026, 10, 15),
          ),
          throwsA(
            isA<VenteRefusee>().having(
              (e) => e.message,
              'message',
              'Vente refusée : la date du 15/10/2026 est dans le futur.',
            ),
          ),
        );

        expect(await db.select(db.sales).get(), isEmpty);
        expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
        expect(
          (await (db.select(
            db.products,
          )..where((t) => t.id.equals(idPoulet))).getSingle()).stockQty,
          50,
        );
      },
    );

    test(
      '🔴 date avant le plus ancien exercice ouvert refusée localement (exercice clos)',
      () async {
        await exercicesUsuels();

        await expectLater(
          caisse.enregistrerVente(
            panier: sixPoulets(),
            modePaiement: 'especes',
            dateVente: DateTime(2025, 12, 31),
          ),
          throwsA(
            isA<VenteRefusee>().having(
              (e) => e.message,
              'message',
              "Vente refusée : l'exercice comptable qui couvre le 31/12/2025 "
                  'est clos. Aucune vente ne peut y être datée.',
            ),
          ),
        );
        expect(await db.select(db.sales).get(), isEmpty);
      },
    );

    test(
      '🔴 date avant le plus ancien exercice ouvert refusée localement (aucun exercice)',
      () async {
        await exercice(
          'f2026000-0000-4000-8000-000000000000',
          2026,
          DateTime(2026, 1, 1),
          DateTime(2026, 12, 31),
          'ouvert',
        );

        expect(
          await caisse.refusDeDate(DateTime(2025, 12, 31)),
          'Vente refusée : aucun exercice comptable ne couvre le 31/12/2025. '
          "Créez l'exercice avant d'enregistrer cette vente.",
        );
        // Le premier jour de l'exercice est accepté (borne incluse).
        expect(await caisse.refusDeDate(DateTime(2026, 1, 1)), isNull);
        expect(await caisse.refusDeDate(DateTime(2026, 10, 13)), isNull);
      },
    );

    test(
      '🔴 aucun exercice connu au poste : rien n est bloqué, le serveur jugera',
      () async {
        final vente = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2024, 3, 2),
        );
        expect(vente.soldAt, DateTime(2024, 3, 2, 10, 15, 30));
        // Le futur, lui, reste refusé même sans exercice.
        expect(
          await caisse.refusDeDate(DateTime(2026, 10, 15)),
          contains('dans le futur'),
        );
      },
    );

    test(
      '🔴 la vente du jour ne subit AUCUN garde de date (comme le web 15.32)',
      () async {
        // Seul exercice connu : 2026 CLOS. Une vente antérieure est refusée, celle du jour non.
        await exercice(
          'f2026000-0000-4000-8000-000000000000',
          2026,
          DateTime(2026, 1, 1),
          DateTime(2026, 12, 31),
          'cloture',
        );

        expect(await caisse.refusDeDate(DateTime(2026, 10, 14)), isNull);
        expect(await caisse.refusDeDate(DateTime(2026, 10, 13)), isNotNull);
        final vente = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
        );
        expect(vente.soldAt, maintenant);
      },
    );

    test(
      '🔴 bornes du sélecteur : min = début du plus ancien exercice OUVERT, max = aujourd hui',
      () async {
        expect(
          (await caisse.bornesDateVente()).premier,
          isNull,
          reason: 'aucun exercice connu : aucune borne basse',
        );
        expect(
          (await caisse.bornesDateVente()).dernier,
          DateTime(2026, 10, 14),
        );

        await exercicesUsuels();
        await exercice(
          'f2024000-0000-4000-8000-000000000000',
          2024,
          DateTime(2024, 1, 1),
          DateTime(2024, 12, 31),
          'cloture',
        );
        await exercice(
          'f2025070-0000-4000-8000-000000000000',
          2027,
          DateTime(2027, 1, 1),
          DateTime(2027, 12, 31),
          'ouvert',
        );

        final bornes = await caisse.bornesDateVente();
        expect(
          bornes.premier,
          DateTime(2026, 1, 1),
          reason: '2024 et 2025 sont clos ; 2026 est le plus ancien ouvert',
        );
        expect(bornes.dernier, DateTime(2026, 10, 14));
      },
    );

    test(
      '🔴 rémanence : vente du jour bloquée, vente ANTÉRIEURE enregistrée (web 15.32)',
      () async {
        await exercicesUsuels();
        await db
            .into(db.veterinaryWithdrawalPeriods)
            .insert(
              VeterinaryWithdrawalPeriodsCompanion.insert(
                id: 'rrrrrrrr-1111-4111-8111-rrrrrrrrrrrr',
                lotId: bande,
                productUsed: const Value('Antibiotique polyvalent'),
                endDate: DateTime(2026, 10, 20),
              ),
            );

        await expectLater(
          caisse.enregistrerVente(
            panier: sixPoulets(),
            modePaiement: 'especes',
          ),
          throwsA(isA<VenteRefusee>()),
        );

        final anterieure = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 11),
        );
        expect(anterieure.soldAt, DateTime(2026, 10, 11, 10, 15, 30));
      },
    );
  });

  group('dépôt — fiche du jour de la vente et cascade', () {
    test(
      '🔴 jeu 15.31 : 49/47/50 + vente de 6 à J-2 → 43/41/44, bande à 44',
      () async {
        await exercicesUsuels();
        await troisFiches();

        await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 12),
        );

        // RECALCUL INDÉPENDANT (boucle écrite ici) : départ = effectif initial 50.
        final mouvements = {
          '12/10': (achat: 0, mort: 1, vente: 6),
          '13/10': (achat: 0, mort: 2, vente: 0),
          '14/10': (achat: 3, mort: 0, vente: 0),
        };
        var courant = 50;
        final attendu = <String, int>{};
        mouvements.forEach((jour, m) {
          courant = courant + m.achat - (m.mort + m.vente);
          attendu[jour] = courant;
        });

        expect(attendu, {'12/10': 43, '13/10': 41, '14/10': 44});
        expect(await effectifs(), attendu);
        expect(
          await effectifBande(),
          44,
          reason:
              'la bande suit la DERNIÈRE fiche (14/10), jamais celle de la vente (43)',
        );
      },
    );

    test(
      '🔴 la vente s ajoute à la fiche du JOUR DE LA VENTE, mouvements saisis intacts',
      () async {
        await exercicesUsuels();
        await troisFiches();

        await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 12),
        );

        final fiches = await (db.select(
          db.livestockDailyEntries,
        )..orderBy([(t) => OrderingTerm(expression: t.entryDate)])).get();

        expect([for (final f in fiches) f.vente], [6, 0, 0]);
        expect([for (final f in fiches) f.mort], [1, 2, 0]);
        expect([for (final f in fiches) f.achat], [0, 0, 3]);

        final duJour = fiches.first;
        expect(duJour.id, 'f1200000-0000-4000-8000-000000000000');
        // S-T9 : la fiche du 12 était synchronisée — la vente s'y affiche, la fiche ne repart pas et garde son
        // horodatage (la vente l'inscrit elle-même au serveur ; renvoyée, elle porterait des morts périmés).
        expect(duJour.syncStatus, SyncStatus.synced);
        expect(
          duJour.updatedAt.isBefore(maintenant),
          isTrue,
          reason: 'une fiche qui ne repart pas garde l\'horodatage de la saisie qui l\'a produite',
        );
        // Les fiches postérieures : seul l'effectif DÉRIVÉ change ; le serveur recalcule le sien
        // par sa propre cascade (15.31) et n'accepte jamais l'effectif du poste.
        expect(fiches[1].syncStatus, SyncStatus.synced);
        expect(fiches[2].syncStatus, SyncStatus.synced);
      },
    );

    test(
      '🔴 vente un jour SANS fiche avant des fiches saisies : fiche créée puis cascade',
      () async {
        await exercicesUsuels();
        await troisFiches();

        await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 11),
        );

        // 11/10 : 50 - 6 = 44 ; 12/10 : 44 - 1 = 43 ; 13/10 : 43 - 2 = 41 ; 14/10 : 41 + 3 = 44.
        expect(await effectifs(), {
          '11/10': 44,
          '12/10': 43,
          '13/10': 41,
          '14/10': 44,
        });
        expect(await effectifBande(), 44);
      },
    );

    test(
      '🔴 deux ventes antérieures successives : la cascade reste juste (idempotente)',
      () async {
        await exercicesUsuels();
        await troisFiches();

        await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 12),
        );
        await caisse.enregistrerVente(
          panier: [
            LignePanier(
              produit: poulet,
              quantite: 4,
              montant: 14000,
              lotId: bande,
            ),
          ],
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 13),
        );

        // 12/10 : 50 - 1 - 6 = 43 ; 13/10 : 43 - 2 - 4 = 37 ; 14/10 : 37 + 3 = 40.
        expect(await effectifs(), {'12/10': 43, '13/10': 37, '14/10': 40});
        expect(await effectifBande(), 40);
      },
    );
  });

  group('synchronisation des ventes datées', () {
    test(
      '🔴 la vente datée J-3 part avec sold_at J-3 et updated_at = instant de saisie',
      () async {
        await exercicesUsuels();
        final vente = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 11),
        );

        final serveur = _ServeurFeint(
          push: {
            'sales': {
              'accepted': [vente.id],
              'rejected': [],
            },
          },
        );
        await moteur(serveur).synchroniser();

        final envoyee =
            (serveur.corpsRecus.single['sales'] as List).single as Map;
        expect(envoyee['id'], vente.id);
        expect(
          envoyee['sold_at'],
          '2026-10-11 10:15:30',
          reason: 'heure LOCALE, sans conversion UTC (ticket 14.71)',
        );
        expect(
          envoyee['updated_at'],
          DateTime(2026, 10, 14, 10, 15, 30).toUtc().toIso8601String(),
        );

        final relue = await (db.select(
          db.sales,
        )..where((t) => t.id.equals(vente.id))).getSingle();
        expect(relue.syncStatus, SyncStatus.synced);
      },
    );

    test(
      '🔴 fiche et vente partent dans le MÊME envoi : le serveur ne compte pas 2N',
      () async {
        await exercicesUsuels();
        await troisFiches();
        final vente = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 12),
        );

        final serveur = _ServeurFeint(
          push: {
            'livestock_daily_entries': {
              'accepted': ['f1200000-0000-4000-8000-000000000000'],
              'rejected': [],
            },
            'sales': {
              'accepted': [vente.id],
              'rejected': [],
            },
          },
        );
        await moteur(serveur).synchroniser();

        final corps = serveur.corpsRecus.single;
        final fiches = corps['livestock_daily_entries'] as List;
        expect(
          fiches,
          hasLength(1),
          reason: 'seule la fiche du jour de la vente',
        );
        expect((fiches.single as Map)['entry_date'], '2026-10-12');
        // S-T9 : fiche déjà synchronisée — elle part réduite à son identité, la vente compte ses 6 sujets.
        expect((fiches.single as Map).keys, unorderedEquals(['id', 'lot_id', 'entry_date']));

        // La fiche du 12 est déjà synchronisée : le serveur la connaît (S-T9).
        final modele = _ModeleServeurVentes()
          ..fichesConnues.add('f1200000-0000-4000-8000-000000000000');
        modele.appliquer(
          corps,
          fichesAcceptees: {'f1200000-0000-4000-8000-000000000000'},
          ventesAcceptees: {vente.id},
        );
        expect(modele.venteParFiche, {'$bande|2026-10-12': 6});
      },
    );

    for (final motif in const [
      'Vente refusée : la date du 11/10/2026 est dans le futur.',
      'Vente refusée : le mois 2026-10 est clôturé — aucune vente ne peut y être '
          'datée (le Journal Comptable applique la même règle). Un Administrateur '
          'peut déclôturer ce mois exceptionnellement.',
      'Vente refusée : aucun exercice comptable ne couvre le 11/10/2026. Créez '
          "l'exercice avant d'enregistrer cette vente.",
      "Vente refusée : l'exercice comptable qui couvre le 11/10/2026 est clos. "
          'Aucune vente ne peut y être datée.',
    ]) {
      test(
        '🔴 rejet serveur « ${motif.substring(16, 40)}… » : conflict, motif tel quel, sans boucle',
        () async {
          final vente = await caisse.enregistrerVente(
            panier: sixPoulets(),
            modePaiement: 'especes',
            dateVente: DateTime(2026, 10, 11),
          );

          final refus = _ServeurFeint(
            push: {
              'sales': {
                'accepted': <String>[],
                'rejected': [
                  {'id': vente.id, 'reason': motif},
                ],
              },
            },
          );
          final resultat = await moteur(refus).synchroniser();

          expect(resultat.rejete, greaterThanOrEqualTo(1));
          expect(resultat.motifs, contains(motif));

          final relue = await (db.select(
            db.sales,
          )..where((t) => t.id.equals(vente.id))).getSingle();
          expect(relue.syncStatus, SyncStatus.conflict);

          final conflit = await db.select(db.syncConflicts).getSingle();
          expect(conflit.sourceTable, 'sales');
          expect(conflit.recordId, vente.id);
          expect(conflit.reason, motif, reason: 'mot pour mot');

          // Pas de boucle : la synchronisation suivante n'envoie plus la vente.
          final second = _ServeurFeint();
          await moteur(second).synchroniser();
          final renvoyees = second.corpsRecus.isEmpty
              ? const []
              : second.corpsRecus.single['sales'] as List? ?? const [];
          expect(renvoyees, isEmpty);
        },
      );
    }

    test(
      '🔴 relancer() : même UUID, même sold_at, même updated_at — et la fiche repart avec (identité seule, F0.90)',
      () async {
        await exercicesUsuels();
        await troisFiches();
        final vente = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 12),
        );

        // 1er envoi : la fiche est ACCEPTÉE, la vente REFUSÉE (mois clôturé).
        // La fiche du 12 est déjà synchronisée : le serveur la connaît (S-T9).
        final modele = _ModeleServeurVentes()
          ..fichesConnues.add('f1200000-0000-4000-8000-000000000000');
        final premier = _ServeurFeint(
          push: {
            'livestock_daily_entries': {
              'accepted': ['f1200000-0000-4000-8000-000000000000'],
              'rejected': [],
            },
            'sales': {
              'accepted': <String>[],
              'rejected': [
                {
                  'id': vente.id,
                  'reason': 'Vente refusée : le mois 2026-10 est clôturé.',
                },
              ],
            },
          },
        );
        final sync = moteur(premier);
        await sync.synchroniser();
        modele.appliquer(
          premier.corpsRecus.single,
          fichesAcceptees: {'f1200000-0000-4000-8000-000000000000'},
          ventesAcceptees: const {},
        );
        final envoi1 =
            (premier.corpsRecus.single['sales'] as List).single as Map;

        // L'obstacle est levé sur le web ; le caissier relance.
        await sync.relancer(await db.select(db.syncConflicts).getSingle());
        expect(
          (await (db.select(
            db.sales,
          )..where((t) => t.id.equals(vente.id))).getSingle()).syncStatus,
          SyncStatus.pending,
        );

        final second = _ServeurFeint(
          push: {
            'livestock_daily_entries': {
              'accepted': ['f1200000-0000-4000-8000-000000000000'],
              'rejected': [],
            },
            'sales': {
              'accepted': [vente.id],
              'rejected': [],
            },
          },
        );
        await moteur(second).synchroniser();
        final corps2 = second.corpsRecus.single;
        final envoi2 = (corps2['sales'] as List).single as Map;

        // SEULE la fiche (bande, jour de la vente) repart : les fiches du 13 et du 14, déjà
        // synchronisées, ne sont pas renvoyées (elles écraseraient une correction faite sur le web).
        // F0.90 : et elle repart réduite à son IDENTITÉ — voir `ventes_correctifs_f090_test.dart`.
        expect(
          [
            for (final f in corps2['livestock_daily_entries'] as List)
              (f as Map)['id'],
          ],
          ['f1200000-0000-4000-8000-000000000000'],
        );
        expect(
          ((corps2['livestock_daily_entries'] as List).single as Map).keys,
          unorderedEquals(['id', 'lot_id', 'entry_date']),
        );
        expect(
          envoi2['id'],
          envoi1['id'],
          reason: 'même UUID, jamais régénéré',
        );
        expect(envoi2['sold_at'], envoi1['sold_at']);
        expect(envoi2['updated_at'], envoi1['updated_at']);

        // ⚠️⚠️ SANS LA FICHE dans ce second envoi, le serveur ajouterait 6 à sa fiche qui porte
        // déjà 6 (limite connue de 15.30) : 12 au lieu de 6.
        modele.appliquer(
          corps2,
          fichesAcceptees: {'f1200000-0000-4000-8000-000000000000'},
          ventesAcceptees: {vente.id},
        );
        expect(modele.venteParFiche, {'$bande|2026-10-12': 6});

        expect(
          (await (db.select(
            db.sales,
          )..where((t) => t.id.equals(vente.id))).getSingle()).syncStatus,
          SyncStatus.synced,
        );
        expect(await db.select(db.syncConflicts).get(), isEmpty);
      },
    );

    test(
      '🔴 réponse perdue : la vente reste en file et repart à l identique (idempotence)',
      () async {
        await exercicesUsuels();
        final vente = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 11),
        );

        final perdu = _ServeurFeint(reponsePerdue: true);
        // L'échec réseau remonte à l'appelant (bouton de synchronisation), rien n'est acquitté.
        await expectLater(
          moteur(perdu).synchroniser(),
          throwsA(isA<DioException>()),
        );
        expect(
          (await (db.select(
            db.sales,
          )..where((t) => t.id.equals(vente.id))).getSingle()).syncStatus,
          SyncStatus.pending,
          reason: 'jamais `synced` sans accusé du serveur',
        );

        // Le serveur l'a déjà : son second passage est un succès silencieux (15.30 : même si le
        // mois a été clôturé entre-temps, `unique:sales,id` passe AVANT le garde de date).
        final rejoue = _ServeurFeint(
          push: {
            'sales': {
              'accepted': [vente.id],
              'rejected': [],
            },
          },
        );
        await moteur(rejoue).synchroniser();

        final a = (perdu.corpsRecus.single['sales'] as List).single as Map;
        final b = (rejoue.corpsRecus.single['sales'] as List).single as Map;
        expect(b['id'], a['id']);
        expect(b['sold_at'], a['sold_at']);
        expect(b['updated_at'], a['updated_at']);
        expect(b['total'], a['total']);
        expect(
          (await (db.select(
            db.sales,
          )..where((t) => t.id.equals(vente.id))).getSingle()).syncStatus,
          SyncStatus.synced,
        );
      },
    );

    test(
      '🔴 une vente déjà synchronisée reste acquittée et ne repart pas',
      () async {
        await exercicesUsuels();
        final vente = await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 11),
        );
        await moteur(
          _ServeurFeint(
            push: {
              'sales': {
                'accepted': [vente.id],
                'rejected': [],
              },
            },
          ),
        ).synchroniser();

        // Une vente acquittée ne repart plus : le serveur, qui la refuserait peut-être aujourd'hui
        // (mois clos depuis), ne la reçoit pas.
        final apres = _ServeurFeint();
        await moteur(apres).synchroniser();

        final renvoyees = apres.corpsRecus.isEmpty
            ? const []
            : apres.corpsRecus.single['sales'] as List? ?? const [];
        expect(renvoyees, isEmpty);
        expect(
          (await (db.select(
            db.sales,
          )..where((t) => t.id.equals(vente.id))).getSingle()).syncStatus,
          SyncStatus.synced,
        );
      },
    );

    test(
      '🔴 les fiches partent dans l ordre des jours (le serveur recalcule dans l ordre reçu)',
      () async {
        await exercicesUsuels();
        // Vente du jour d'abord (fiche du 14 créée), puis vente antérieure (fiche du 11 créée
        // APRÈS) : l'ordre d'insertion est inverse de l'ordre des jours.
        await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
        );
        await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 11),
        );

        final serveur = _ServeurFeint();
        await moteur(serveur).synchroniser();

        final jours = [
          for (final f
              in serveur.corpsRecus.single['livestock_daily_entries'] as List)
            (f as Map)['entry_date'],
        ];
        expect(jours, ['2026-10-11', '2026-10-14']);
      },
    );

    test(
      '🔴 aucune écriture comptable ni de trésorerie au poste : seul le FAIT part',
      () async {
        await exercicesUsuels();
        await caisse.enregistrerVente(
          panier: sixPoulets(),
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 11),
        );

        expect(await db.select(db.accountingEntries).get(), isEmpty);
        expect(await db.select(db.accountingEntryLines).get(), isEmpty);
      },
    );
  });

  group('écran — champ « Date de la vente » au panier', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(home: CaisseScreen(depot: caisse)));
      await tester.pumpAndSettle();
    }

    Finder dans(String cle, String texte) =>
        find.descendant(of: find.byKey(Key(cle)), matching: find.text(texte));

    Future<void> ajouterProvende(
      WidgetTester tester, {
      String quantite = '2',
      String montant = '13000',
    }) async {
      await tester.tap(find.byKey(const Key('produit-ALI-001')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('saisie-quantite')),
        quantite,
      );
      await tester.enterText(find.byKey(const Key('saisie-montant')), montant);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmer-ligne')));
      await tester.pumpAndSettle();
    }

    Future<void> choisirJour(WidgetTester tester, String jour) async {
      await tester.tap(find.byKey(const Key('date-vente')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text(jour)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    Future<void> valider(WidgetTester tester) async {
      final bouton = find.byKey(const Key('valider-vente'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();
    }

    testWidgets(
      '🔴 le champ est au PANIER, défaut aujourd hui, et absent de « Vente à la Pièce »',
      (tester) async {
        await afficher(tester);

        expect(find.text('DATE DE LA VENTE'), findsOneWidget);
        expect(dans('date-vente', '14/10/2026'), findsOneWidget);

        await tester.tap(find.byKey(const Key('produit-ALI-001')));
        await tester.pumpAndSettle();
        expect(find.text('Vente à la Pièce'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byKey(const Key('date-vente')),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.textContaining('Date'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      '🔴 bornes du calendrier : début du plus ancien exercice ouvert → aujourd hui',
      (tester) async {
        await exercicesUsuels();
        await afficher(tester);

        await tester.tap(find.byKey(const Key('date-vente')));
        await tester.pumpAndSettle();

        final calendrier = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        expect(calendrier.firstDate, DateTime(2026, 1, 1));
        expect(calendrier.lastDate, DateTime(2026, 10, 14));
        expect(calendrier.initialDate, DateTime(2026, 10, 14));
      },
    );

    testWidgets(
      '🔴 vente antérieure choisie au calendrier : aide affichée, vente datée, retour à aujourd hui',
      (tester) async {
        await exercicesUsuels();
        await afficher(tester);

        await choisirJour(tester, '11');
        expect(dans('date-vente', '11/10/2026'), findsOneWidget);
        expect(
          find.text(
            'Vente antérieure : écriture, stock, créance et fiche seront '
            'datés du 11/10/2026.',
          ),
          findsOneWidget,
        );

        await ajouterProvende(tester);
        await valider(tester);

        final vente = await db.select(db.sales).getSingle();
        expect(vente.soldAt, DateTime(2026, 10, 11, 10, 15, 30));
        expect(vente.updatedAt, maintenant);

        await tester.tap(find.byKey(const Key('bouton-nouvelle-vente')));
        await tester.pumpAndSettle();
        expect(
          dans('date-vente', '14/10/2026'),
          findsOneWidget,
          reason: 'après une vente, le champ revient à aujourd hui (web 15.32)',
        );
        expect(find.textContaining('Vente antérieure'), findsNothing);
      },
    );

    testWidgets(
      '🔴 date refusée : motif SOUS le champ dès le choix, et validation refusée',
      (tester) async {
        // Seul exercice connu : octobre 2026 dans un exercice CLOS.
        await exercice(
          'f2026000-0000-4000-8000-000000000000',
          2026,
          DateTime(2026, 1, 1),
          DateTime(2026, 12, 31),
          'cloture',
        );
        await afficher(tester);

        await choisirJour(tester, '11');
        const motif =
            "Vente refusée : l'exercice comptable qui couvre le 11/10/2026 "
            'est clos. Aucune vente ne peut y être datée.';
        expect(
          find.descendant(
            of: find.byKey(const Key('date-vente-erreur')),
            matching: find.text(motif),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Vente antérieure'), findsNothing);

        await ajouterProvende(tester);
        await valider(tester);

        expect(await db.select(db.sales).get(), isEmpty);
        expect(find.byKey(const Key('modale-vente-enregistree')), findsNothing);
        expect(find.text(motif), findsWidgets, reason: 'motif montré tel quel');
      },
    );

    testWidgets(
      '🔴 vente du jour à l écran : inchangée (sold_at = updated_at = maintenant)',
      (tester) async {
        await exercicesUsuels();
        await afficher(tester);

        await ajouterProvende(tester);
        await valider(tester);

        final vente = await db.select(db.sales).getSingle();
        expect(vente.soldAt, maintenant);
        expect(vente.updatedAt, maintenant);
        expect(find.textContaining('Vente antérieure'), findsNothing);
      },
    );

    testWidgets(
      '🔴 recalcul indépendant des totaux : écran = vente enregistrée = calcul du test',
      (tester) async {
        await exercicesUsuels();
        await afficher(tester);

        // Trois lignes, une remise, un montant reçu.
        await ajouterProvende(tester, quantite: '2', montant: '13000');
        await ajouterProvende(tester, quantite: '1', montant: '6500');
        await ajouterProvende(tester, quantite: '3', montant: '19250');
        await tester.enterText(find.byKey(const Key('remise')), '750');
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('montant-recu')), '40000');
        await tester.pumpAndSettle();

        // Calcul indépendant : 13 000 + 6 500 + 19 250 = 38 750 ; − 750 = 38 000 ; 40 000 − 38 000.
        const sousTotal = 13000 + 6500 + 19250;
        const total = sousTotal - 750;
        const monnaie = 40000 - total;
        expect(sousTotal, 38750);
        expect(total, 38000);
        expect(monnaie, 2000);

        expect(find.text('38 750 FCFA'), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('total-a-payer'))).data,
          '38 000 FCFA',
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('monnaie'))).data,
          '2 000 FCFA',
        );

        await choisirJour(tester, '10');
        await valider(tester);

        final vente = await db.select(db.sales).getSingle();
        expect(vente.subtotal, sousTotal);
        expect(vente.discount, 750);
        expect(vente.total, total);
        expect(vente.changeDue, monnaie);
        expect(vente.soldAt, DateTime(2026, 10, 10, 10, 15, 30));

        final lignes = await db.select(db.saleLines).get();
        expect(
          lignes.fold<double>(0, (s, l) => s + l.manualTotalAmount),
          sousTotal,
        );
      },
    );
  });
}
