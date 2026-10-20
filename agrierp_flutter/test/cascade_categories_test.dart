import 'dart:io';
import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/effectif_par_categorie.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
// Drift exporte `isNull` / `isNotNull` (expressions SQL) : masqués pour les matchers.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'effectif_par_categorie_test.dart' show Scenario, scenarioAuHasard, scriptChaine;
import 'php_laravel.dart';

/// Ticket F0.95 — CASCADE LOCALE UNIQUE (totaux + catégories + effectif courant de la bande).
///
/// La caisse et la fiche (F0.96) partagent `FicheJournaliereRepository.recalculerEnCascade`,
/// miroir de `RecordSaleOnFicheElevageAction::recalculerEnCascade` (15.31) suivi de
/// `EffectifParCategorieService::recalculerChaine` (15.39). Chiffres attendus : LITTÉRAUX des
/// tickets 15.39 / 15.42 (calculés à la main), puis parité EXÉCUTÉE contre le vrai PHP.
void main() {
  late AppDatabase db;
  late CaisseRepository caisse;
  late FicheJournaliereRepository depot;

  final maintenant = DateTime(2026, 10, 14, 10, 15, 30);
  const lapins = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const porcs = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';
  const especeLapins = 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee';
  const especePorcs = 'ffffffff-1111-4111-8111-ffffffffffff';
  const idLapin = 'cccccccc-1111-4111-8111-cccccccccccc';
  const idPorc = 'dddddddd-1111-4111-8111-dddddddddddd';

  late Product lapin;
  late Product porc;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    caisse = CaisseRepository(
      database: db,
      deviceId: 'poste-test',
      maintenant: () => maintenant,
    );
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    for (final (id, code, espece, codeEspece, initial) in [
      (lapins, 'LAP-2026-01', especeLapins, 'cuniculture', 60),
      (porcs, 'POR-2026-01', especePorcs, 'porciculture', 120),
    ]) {
      await db
          .into(db.livestockLots)
          .insert(
            LivestockLotsCompanion.insert(
              id: id,
              code: code,
              speciesId: espece,
              speciesCode: Value(codeEspece),
              initialQuantity: Value(initial),
              currentQuantity: Value(initial),
            ),
          );
    }
    for (final (id, espece) in [(idLapin, especeLapins), (idPorc, especePorcs)]) {
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: id,
              sku: id.substring(0, 4),
              name: 'Sujet vif',
              speciesId: Value(espece),
              unit: 'u',
              pricingMode: 'fixe',
              priceMin: const Value(3000),
              stockQty: const Value(200),
            ),
          );
    }
    lapin = await (db.select(
      db.products,
    )..where((t) => t.id.equals(idLapin))).getSingle();
    porc = await (db.select(
      db.products,
    )..where((t) => t.id.equals(idPorc))).getSingle();
  });

  tearDown(() async => db.close());

  /// Fiche SYNCHRONISÉE, ventilée, totaux `mort`/`don` = somme de la ventilation.
  Future<void> fiche(
    String lot,
    int jour,
    int effectif, {
    int achat = 0,
    int ne = 0,
    int vente = 0,
    int? mR = 0,
    int? mS = 0,
    int? mJ = 0,
    int? dR = 0,
    int? dS = 0,
    int? dJ = 0,
    int? passage = 0,
    (int, int, int)? depart,
  }) => db
      .into(db.livestockDailyEntries)
      .insert(
        LivestockDailyEntriesCompanion.insert(
          id: '${lot.substring(0, 8)}-0000-4000-8000-0000000000${jour.toString().padLeft(2, '0')}',
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: DateTime(2026, 10, jour, 8),
          lotId: lot,
          entryDate: DateTime(2026, 10, jour),
          achat: Value(achat),
          ne: Value(ne),
          vente: Value(vente),
          mort: Value((mR ?? 0) + (mS ?? 0) + (mJ ?? 0)),
          don: Value((dR ?? 0) + (dS ?? 0) + (dJ ?? 0)),
          effectifFinal: Value(effectif),
          mortRepro: Value(mR),
          mortSevre: Value(mS),
          mortJeune: Value(mJ),
          donRepro: Value(dR),
          donSevre: Value(dS),
          donJeune: Value(dJ),
          passageSevreJeune: Value(passage),
          catDepartRepro: Value(depart?.$1),
          catDepartSevre: Value(depart?.$2),
          catDepartJeune: Value(depart?.$3),
        ),
      );

  /// Jeu lapins du plan (totaux déjà justes : 66 / 58 / 26), catégories pas encore calculées.
  Future<void> jeuLapins() async {
    await fiche(lapins, 1, 66, achat: 2, ne: 5, mS: 1, depart: (10, 20, 30));
    await fiche(lapins, 2, 58, vente: 4, mR: 1, mJ: 2, dS: 1);
    await fiche(lapins, 3, 26, vente: 30, mS: 2);
  }

  Future<void> jeuPorcs() async {
    await fiche(porcs, 1, 130, achat: 3, ne: 9, mS: 2, depart: (10, 24, 86));
    await fiche(porcs, 2, 123, vente: 5, mR: 1, dJ: 1);
    await fiche(porcs, 3, 117, vente: 2, mJ: 3, dS: 1);
    await fiche(porcs, 4, 77, mS: 40);
  }

  Future<List<LivestockDailyEntry>> fiches(String lot) =>
      (db.select(db.livestockDailyEntries)
            ..where((t) => t.lotId.equals(lot))
            ..orderBy([(t) => OrderingTerm(expression: t.entryDate)]))
          .get();

  List<int?> cats(LivestockDailyEntry f) => [
    f.catEffRepro,
    f.catEffSevre,
    f.catEffJeune,
  ];

  Future<int> bande(String lot) async => (await (db.select(
    db.livestockLots,
  )..where((t) => t.id.equals(lot))).getSingle()).currentQuantity;

  group('cascade du dépôt (miroir 15.31 + 15.39)', () {
    test('jeu lapins : 10/26/30, 9/25/24, 9/23/0 ; bande à 26', () async {
      await jeuLapins();

      await depot.recalculerEnCascade(lapins, DateTime(2026, 10, 1));

      final f = await fiches(lapins);
      expect(f.map(cats), [
        [10, 26, 30],
        [9, 25, 24],
        [9, 23, 0],
      ]);
      expect(f.map((x) => x.effectifFinal), [66, 58, 26]);
      expect(await bande(lapins), 26);
    });

    test('jeu porcs : J4 plancher Porcelet 12/0/75 (total 77, somme 87)', () async {
      await jeuPorcs();

      final rapport = await depot.recalculerEnCascade(
        porcs,
        DateTime(2026, 9, 30),
      );

      final f = await fiches(porcs);
      expect(f.map(cats), [
        [13, 31, 86],
        [12, 31, 80],
        [12, 30, 75],
        [12, 0, 75],
      ]);
      expect(f.map((x) => x.effectifFinal), [130, 123, 117, 77]);
      expect(await bande(porcs), 77);
      expect(rapport.chaine.resultats.values.last.sommeDifferente, isTrue);
    });

    test(
      '⚠️⚠️ IDEMPOTENTE : le second passage n écrit rien (statut et horodatage intacts)',
      () async {
        await jeuLapins();
        await depot.recalculerEnCascade(lapins, DateTime(2026, 10, 1));
        final avant = await fiches(lapins);

        final rapport = await depot.recalculerEnCascade(
          lapins,
          DateTime(2026, 10, 1),
        );

        expect(rapport.totauxModifies, 0);
        expect(rapport.categoriesModifiees, 0);
        expect(await fiches(lapins), avant);
      },
    );

    test(
      '⚠️ les catégories et totaux recalculés ne remettent PAS la fiche en file',
      () async {
        await jeuLapins();
        await depot.recalculerEnCascade(lapins, DateTime(2026, 10, 1));
        final f = await fiches(lapins);
        expect(f.every((x) => x.syncStatus == SyncStatus.synced), isTrue);
        expect(f.map((x) => x.updatedAt), [
          DateTime(2026, 10, 1, 8),
          DateTime(2026, 10, 2, 8),
          DateTime(2026, 10, 3, 8),
        ]);
      },
    );

    test('départ incohérent : AUCUNE catégorie écrite, motif rendu', () async {
      await fiche(lapins, 1, 61, achat: 1, depart: (10, 20, 31));

      final rapport = await depot.recalculerEnCascade(
        lapins,
        DateTime(2026, 9, 30),
      );

      expect(rapport.chaine.refus, contains('61'));
      expect(cats((await fiches(lapins)).single), [null, null, null]);
    });

    test('bande sans départ : aucune catégorie, totaux et bande suivent', () async {
      await fiche(lapins, 1, 60, vente: 3);
      await fiche(lapins, 2, 99, mS: null);

      await depot.recalculerEnCascade(lapins, DateTime(2026, 10, 1));

      final f = await fiches(lapins);
      expect(f.map((x) => x.effectifFinal), [60, 60], reason: 'le 01 n est pas touché (départ de la cascade)');
      expect(f.map(cats), [
        [null, null, null],
        [null, null, null],
      ]);
      expect(await bande(lapins), 60);
    });

    test(
      '⚠️ chaque fiche bornée à 0 comme au serveur (14.63), la suivante repart de 0',
      () async {
        await fiche(lapins, 1, 60);
        await fiche(lapins, 2, 0, mS: 70);
        await fiche(lapins, 3, 0, achat: 5);

        await depot.recalculerEnCascade(lapins, DateTime(2026, 10, 1));

        expect((await fiches(lapins)).map((x) => x.effectifFinal), [60, 0, 5]);
        expect(await bande(lapins), 5);
      },
    );
  });

  group('⚠️⚠️ la CAISSE passe par la cascade unique', () {
    test(
      'vente antidatée de 6 au J1 (lapins) → Chair 24/18/0, totaux 60/52/20, bande 20',
      () async {
        await jeuLapins();

        await caisse.enregistrerVente(
          panier: [
            LignePanier(produit: lapin, quantite: 6, montant: 18000, lotId: lapins),
          ],
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 1),
        );

        final f = await fiches(lapins);
        expect(f.map(cats), [
          [10, 26, 24],
          [9, 25, 18],
          [9, 23, 0],
        ]);
        expect(f.map((x) => x.effectifFinal), [60, 52, 20]);
        expect(await bande(lapins), 20);
        expect(f.first.vente, 6);
        // S-T9 : fiche déjà synchronisée — la vente s'y affiche, la fiche ne repart pas (la vente l'inscrit au serveur).
        expect(f.first.syncStatus, SyncStatus.synced);
        expect(f[1].syncStatus, SyncStatus.synced);
        expect(f[2].syncStatus, SyncStatus.synced);
      },
    );

    test('vente porcs → Marchand : 13/31/86, 12/31/70 (113), 12/30/65, 12/0/65', () async {
      await jeuPorcs();

      await caisse.enregistrerVente(
        panier: [
          LignePanier(produit: porc, quantite: 10, montant: 30000, lotId: porcs),
        ],
        modePaiement: 'especes',
        dateVente: DateTime(2026, 10, 2),
      );

      final f = await fiches(porcs);
      expect(f.map(cats), [
        [13, 31, 86],
        [12, 31, 70],
        [12, 30, 65],
        [12, 0, 65],
      ]);
      expect(f[1].effectifFinal, 113);
    });

    test(
      '⚠️ fiche CRÉÉE par la vente sur une bande à chaîne : mouvements ventilés connus à 0',
      () async {
        await fiche(lapins, 1, 66, achat: 2, ne: 5, mS: 1, depart: (10, 20, 30));
        await fiche(lapins, 3, 65, vente: 1);

        await caisse.enregistrerVente(
          panier: [
            LignePanier(produit: lapin, quantite: 4, montant: 12000, lotId: lapins),
          ],
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 2),
        );

        final f = await fiches(lapins);
        final j2 = f[1];
        expect(j2.entryDate, DateTime(2026, 10, 2));
        expect(j2.vente, 4);
        expect(
          [
            j2.mortRepro,
            j2.mortSevre,
            j2.mortJeune,
            j2.donRepro,
            j2.donSevre,
            j2.donJeune,
            j2.passageSevreJeune,
          ],
          [0, 0, 0, 0, 0, 0, 0],
        );
        expect(j2.catDepartRepro, isNull, reason: 'jamais un départ');
        expect(cats(j2), [10, 26, 26]);
        expect(j2.effectifFinal, 62);
        expect(cats(f[2]), [10, 26, 25]);
        expect(f[2].effectifFinal, 61);
      },
    );

    test(
      'SANS chaîne : comportement inchangé, nouvelles colonnes laissées à null',
      () async {
        await fiche(lapins, 1, 59, mS: 1, mR: null, mJ: null);

        await caisse.enregistrerVente(
          panier: [
            LignePanier(produit: lapin, quantite: 3, montant: 9000, lotId: lapins),
          ],
          modePaiement: 'especes',
          dateVente: DateTime(2026, 10, 2),
        );

        final j2 = (await fiches(lapins))[1];
        expect(j2.vente, 3);
        expect(j2.effectifFinal, 56);
        expect(
          [
            j2.mortRepro,
            j2.mortSevre,
            j2.mortJeune,
            j2.donRepro,
            j2.passageSevreJeune,
            j2.catDepartRepro,
            j2.catEffRepro,
            j2.catEffSevre,
            j2.catEffJeune,
          ],
          everyElement(isNull),
        );
        expect(await bande(lapins), 56);
      },
    );

    test('SANS chaîne : les cat_eff saisis ailleurs ne sont pas touchés', () async {
      await fiche(lapins, 1, 60);
      await (db.update(db.livestockDailyEntries)).write(
        const LivestockDailyEntriesCompanion(
          catEffRepro: Value(9),
          catEffSevre: Value(8),
          catEffJeune: Value(7),
        ),
      );

      await caisse.enregistrerVente(
        panier: [
          LignePanier(produit: lapin, quantite: 2, montant: 6000, lotId: lapins),
        ],
        modePaiement: 'especes',
        dateVente: DateTime(2026, 10, 1),
      );

      expect(cats((await fiches(lapins)).single), [9, 8, 7]);
    });

    test(
      'source : la caisse ne garde AUCUNE cascade à elle (une seule implémentation)',
      () {
        final source = File(
          'lib/features/ventes/caisse_repository.dart',
        ).readAsStringSync();
        expect(source.contains('_recalculerEnCascade'), isFalse);
        // Ticket S-T7 — la caisse n'écrit plus la fiche : elle la confie à son dépôt (un seul écrivain par
        // table), dont `repercuterVente` passe par LA cascade unique.
        expect(source.contains('.repercuterVente('), isTrue);
        expect(source.contains('calculerEffectifFinal('), isFalse);
        final depot = File(
          'lib/features/elevage/fiche_journaliere_repository.dart',
        ).readAsStringSync();
        final repercuter = depot.substring(
          depot.indexOf('Future<void> repercuterVente('),
          depot.indexOf('Future<void> reporterTransferts('),
        );
        expect(repercuter.contains('await recalculerEnCascade(lotId, jour);'), isTrue);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════ PARITÉ EXÉCUTÉE (PHP)
  test(
    '⚠️⚠️ parité EXÉCUTÉE de la cascade : 120 bandes générées, totaux + catégories + bande '
    'identiques à `RecordSaleOnFicheElevageAction::recalculerEnCascade` du serveur',
    () async {
      // Une base en mémoire par scénario, successivement : VOULU.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );
      final hasard = Random(5951);
      final scenarios = [
        for (var i = 0; i < 120; i++) scenarioAuHasard(hasard, i, type: 'cascade'),
      ];
      final sortie =
          executerPhp(
                '<?php\n$amorceApplication\n$scriptChaine',
                [for (final s in scenarios) s.versJson()],
                application: true,
              )
              as List;

      var totauxChanges = 0;
      var categoriesEcrites = 0;
      for (var i = 0; i < scenarios.length; i++) {
        final s = scenarios[i];
        final local = AppDatabase.forTesting(NativeDatabase.memory());
        try {
          final ids = await _poser(local, s, i);
          await FicheJournaliereRepository(
            database: local,
            deviceId: 'poste-test',
          ).recalculerEnCascade('lot-$i'.padRight(36, '0'), s.depuis!);

          final php = sortie[i] as Map<String, dynamic>;
          final attendues = php['fiches'] as List;
          for (var k = 0; k < ids.length; k++) {
            final f = await (local.select(
              local.livestockDailyEntries,
            )..where((t) => t.id.equals(ids[k]))).getSingle();
            final obtenu = [
              f.effectifFinal,
              f.catEffRepro,
              f.catEffSevre,
              f.catEffJeune,
            ];
            expect(obtenu, attendues[k], reason: 'scénario $i, fiche $k');
            if (obtenu[0] != s.fiches[k]['effectif_final']) totauxChanges++;
            if (obtenu[1] != s.fiches[k]['cat_eff_repro']) categoriesEcrites++;
          }
          final lot = await (local.select(
            local.livestockLots,
          )).getSingle();
          expect(lot.currentQuantity, php['bande'], reason: 'scénario $i, bande');
        } finally {
          await local.close();
        }
      }
      expect(totauxChanges, greaterThan(10), reason: 'la grille exerce la cascade des totaux');
      expect(categoriesEcrites, greaterThan(30));
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('constante : mouvements « connus à zéro » = ceux du serveur', () {
    expect(EffectifParCategorie.mouvementsConnusAZero.keys, [
      'mort_repro',
      'mort_sevre',
      'mort_jeune',
      'don_repro',
      'don_sevre',
      'don_jeune',
      'passage_sevre_jeune',
    ]);
  });
}

/// Pose dans [db] la bande et les fiches d'un scénario généré (colonnes du serveur → Drift).
Future<List<String>> _poser(AppDatabase db, Scenario s, int i) async {
  final lot = 'lot-$i'.padRight(36, '0');
  await db
      .into(db.livestockLots)
      .insert(
        LivestockLotsCompanion.insert(
          id: lot,
          code: 'S$i',
          speciesId: 'espece'.padRight(36, '0'),
          speciesCode: Value(s.especeCode),
          initialQuantity: Value(s.initial),
          currentQuantity: Value(s.initial),
        ),
      );
  final ids = <String>[];
  for (var k = 0; k < s.fiches.length; k++) {
    final f = s.fiches[k];
    final id = 'f$i-$k'.padRight(36, '0');
    ids.add(id);
    int? v(String c) => f[c] as int?;
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: id,
            deviceId: 'serveur',
            syncStatus: const Value(SyncStatus.synced),
            updatedAt: DateTime(2026, 10, 1),
            lotId: lot,
            entryDate: DateTime.parse(f['entry_date'] as String),
            achat: Value(v('achat')!),
            ne: Value(v('ne')!),
            mort: Value(v('mort')!),
            vente: Value(v('vente')!),
            don: Value(v('don')!),
            effectifFinal: Value(v('effectif_final')!),
            mortRepro: Value(v('mort_repro')),
            mortSevre: Value(v('mort_sevre')),
            mortJeune: Value(v('mort_jeune')),
            donRepro: Value(v('don_repro')),
            donSevre: Value(v('don_sevre')),
            donJeune: Value(v('don_jeune')),
            passageSevreJeune: Value(v('passage_sevre_jeune')),
            catDepartRepro: Value(v('cat_depart_repro')),
            catDepartSevre: Value(v('cat_depart_sevre')),
            catDepartJeune: Value(v('cat_depart_jeune')),
            catEffRepro: Value(v('cat_eff_repro')),
            catEffSevre: Value(v('cat_eff_sevre')),
            catEffJeune: Value(v('cat_eff_jeune')),
          ),
        );
  }
  return ids;
}
