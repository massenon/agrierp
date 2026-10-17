import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.12 — PROTOCOLE PROPHYLACTIQUE DU JOUR.
///
/// ⚠️⚠️ Ce que ces tests protègent : **le jour du cycle est calculé, jamais
/// deviné**. `period_label` est du texte libre (« Le 5e jour », « Le 1er du
/// mois ») ; le serveur a explicitement refusé de l'interpréter et porte des
/// bornes entières à la place. Un jour deviné à tort ferait administrer un
/// traitement au mauvais moment, ou en sauter un.
void main() {
  late AppDatabase db;
  late SoinsRepository soins;

  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  final miseEnLot = DateTime(2026, 8, 1);

  /// Une entrée du protocole telle que le serveur la sert.
  Future<void> standard({
    required String id,
    required String traitement,
    int? debut,
    int? fin,
    int remanence = 0,
  }) async {
    await db
        .into(db.prophylaxisScheduleStandards)
        .insert(
          ProphylaxisScheduleStandardsCompanion.insert(
            id: id,
            speciesCode: 'cuniculture',
            periodLabel: 'libellé libre',
            cycleDayStart: Value(debut),
            cycleDayEnd: Value(fin),
            treatment: traitement,
            productRecommended: const Value('Ivermectine'),
            dosage: const Value('0,2 ml / kg'),
            withdrawalDays: Value(remanence),
          ),
        );
  }

  Future<LivestockLot> bande({String? stade, DateTime? creee}) async {
    await db
        .into(db.livestockLots)
        .insertOnConflictUpdate(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'CUN-2026-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            stage: Value(stade),
            createdDate: Value(creee),
            currentQuantity: const Value(40),
          ),
        );

    return (db.select(
      db.livestockLots,
    )..where((t) => t.id.equals(bandeId))).getSingle();
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
  });

  tearDown(() => db.close());

  test('J1 est le jour de mise en lot lui-même, comme au serveur', () async {
    await standard(
      id: '11111111-1111-4111-8111-111111111111',
      traitement: 'Vitamines',
      debut: 1,
      fin: 1,
    );

    final resultat = await soins.protocoleDuJour(
      bande: await bande(creee: miseEnLot),
      codeEspece: 'cuniculture',
      quand: miseEnLot,
    );

    expect(resultat.jourDeCycle, 1, reason: 'J1 = le jour de référence');
    expect(resultat.traitements, hasLength(1));
  });

  test('un traitement est dû sur toute sa plage, bornes comprises', () async {
    await standard(
      id: '11111111-1111-4111-8111-111111111111',
      traitement: 'Anticoccidien',
      debut: 5,
      fin: 7,
    );
    final lot = await bande(creee: miseEnLot);

    Future<int> dusAu(int jour) async {
      final r = await soins.protocoleDuJour(
        bande: lot,
        codeEspece: 'cuniculture',
        quand: miseEnLot.add(Duration(days: jour - 1)),
      );
      return r.traitements.length;
    }

    expect(await dusAu(4), 0, reason: 'la veille');
    expect(await dusAu(5), 1, reason: 'borne basse comprise');
    expect(await dusAu(7), 1, reason: 'borne haute comprise');
    expect(await dusAu(8), 0, reason: 'le lendemain');
  });

  test(
    "⚠️ une entrée calendaire (bornes nulles) n'est JAMAIS présentée comme due",
    () async {
      // « Le 1er du mois » : le serveur laisse ses bornes vides parce que sa base
      // de calcul n'est pas le jour de cycle. Un zéro implicite la rendrait due
      // au premier jour de chaque bande.
      await standard(
        id: '11111111-1111-4111-8111-111111111111',
        traitement: 'Désinfection des cages',
      );

      final resultat = await soins.protocoleDuJour(
        bande: await bande(creee: miseEnLot),
        codeEspece: 'cuniculture',
        quand: miseEnLot,
      );

      expect(resultat.traitements, isEmpty);
      expect(
        resultat.calendairesNonEvalues,
        1,
        reason: 'comptée et signalée, jamais masquée',
      );
    },
  );

  test(
    "⚠️ F0.91 : une bande en reproduction se compte depuis sa dernière saillie, pas depuis la mise en lot",
    () async {
      await standard(
        id: '11111111-1111-4111-8111-111111111111',
        traitement: 'Vitamines',
        debut: 1,
        fin: 30,
      );
      final lot = await bande(stade: 'reproduction', creee: miseEnLot);
      await db
          .into(db.livestockReproductionEvents)
          .insert(
            LivestockReproductionEventsCompanion.insert(
              id: 'cccccccc-1111-4111-8111-cccccccccccc',
              deviceId: 'serveur',
              syncStatus: const Value(SyncStatus.synced),
              updatedAt: miseEnLot,
              lotId: bandeId,
              motherRef: 'R1',
              saillieDate: Value(DateTime(2026, 8, 20)),
            ),
          );

      final resultat = await soins.protocoleDuJour(
        bande: lot,
        codeEspece: 'cuniculture',
        quand: DateTime(2026, 8, 25),
      );

      // Calculé à la main : 20/08 = J1 … 25/08 = J6 (et non J25 de la mise en lot).
      expect(resultat.determinable, isTrue);
      expect(resultat.jourDeCycle, 6);
      expect(resultat.motifIndetermine, isNull);
      expect(resultat.traitements, hasLength(1));
    },
  );

  test(
    "⚠️ une bande en reproduction SANS saillie connue reste indéterminée, jamais calculée sur la mise en lot",
    () async {
      await standard(
        id: '11111111-1111-4111-8111-111111111111',
        traitement: 'Vitamines',
        debut: 1,
        fin: 30,
      );

      final resultat = await soins.protocoleDuJour(
        bande: await bande(stade: 'reproduction', creee: miseEnLot),
        codeEspece: 'cuniculture',
        quand: miseEnLot,
      );

      expect(resultat.determinable, isFalse);
      expect(resultat.jourDeCycle, isNull);
      expect(
        resultat.traitements,
        isEmpty,
        reason: 'aucune liste calculée sur une base de calcul erronée',
      );
      expect(resultat.motifIndetermine, contains('saillie'));
      expect(
        resultat.motifIndetermine,
        isNot(contains('hors ligne')),
        reason:
            'la saillie descend au poste depuis 14.72 : ce motif était faux',
      );
    },
  );

  test('une bande sans date de mise en lot est indéterminable', () async {
    await standard(
      id: '11111111-1111-4111-8111-111111111111',
      traitement: 'Vitamines',
      debut: 1,
      fin: 30,
    );

    final resultat = await soins.protocoleDuJour(
      bande: await bande(creee: null),
      codeEspece: 'cuniculture',
      quand: miseEnLot,
    );

    expect(resultat.determinable, isFalse);
    expect(resultat.motifIndetermine, contains('mise en lot'));
  });

  test(
    'un soin déjà enregistré ce jour-là marque le traitement comme fait',
    () async {
      await standard(
        id: '11111111-1111-4111-8111-111111111111',
        traitement: 'Anticoccidien',
        debut: 1,
        fin: 1,
      );
      final lot = await bande(creee: miseEnLot);

      var resultat = await soins.protocoleDuJour(
        bande: lot,
        codeEspece: 'cuniculture',
        quand: miseEnLot,
      );
      expect(resultat.enAttente, 1);

      await soins.enregistrer(
        lotId: bandeId,
        typeAction: 'Anticoccidien',
        produit: 'Ivermectine',
        quand: miseEnLot,
      );

      resultat = await soins.protocoleDuJour(
        bande: lot,
        codeEspece: 'cuniculture',
        quand: miseEnLot,
      );
      expect(resultat.traitements.single.dejaAdministre, isTrue);
      expect(resultat.enAttente, 0);
    },
  );

  test("un soin d'un AUTRE jour ne valide pas celui d'aujourd'hui", () async {
    await standard(
      id: '11111111-1111-4111-8111-111111111111',
      traitement: 'Anticoccidien',
      debut: 1,
      fin: 10,
    );
    final lot = await bande(creee: miseEnLot);

    await soins.enregistrer(
      lotId: bandeId,
      typeAction: 'Anticoccidien',
      produit: 'Ivermectine',
      quand: miseEnLot,
    );

    final resultat = await soins.protocoleDuJour(
      bande: lot,
      codeEspece: 'cuniculture',
      quand: miseEnLot.add(const Duration(days: 3)),
    );

    expect(
      resultat.traitements.single.dejaAdministre,
      isFalse,
      reason: 'la validation vaut pour un jour, pas pour la plage',
    );
  });

  test("le protocole d'une autre espèce n'est jamais servi", () async {
    await db
        .into(db.prophylaxisScheduleStandards)
        .insert(
          ProphylaxisScheduleStandardsCompanion.insert(
            id: '22222222-2222-4222-8222-222222222222',
            speciesCode: 'aviculture',
            periodLabel: 'J1',
            cycleDayStart: const Value(1),
            cycleDayEnd: const Value(1),
            treatment: 'Vaccin Newcastle',
          ),
        );

    final resultat = await soins.protocoleDuJour(
      bande: await bande(creee: miseEnLot),
      codeEspece: 'cuniculture',
      quand: miseEnLot,
    );

    expect(resultat.traitements, isEmpty);
  });
}
