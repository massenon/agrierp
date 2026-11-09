import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.91 — PARITÉ DU PROTOCOLE DU JOUR AVEC LE SERVICE SERVEUR (15.35).
///
/// ⚠️⚠️ CE FICHIER REJOUE AU POSTE LE JEU DE `ProtocoleDuJourServiceTest`
/// (dépôt Laravel, ticket 15.35), recopié À LA MAIN — jamais calculé par le
/// code testé. Une règle sanitaire écrite deux fois (serveur et poste) finit
/// toujours par diverger ; ce jeu commun est ce qui le verra.
///
/// Barème à TROIS entrées, comme au serveur :
///   - « Anti-stress »    : jours 2 à 4, sans rémanence ;
///   - « Anti-coccidien » : jour 5 uniquement, rémanence 5 jours ;
///   - « Déparasitage »   : « Le 1er du mois », bornes nulles (calendaire).
///
/// Maintenant figé au 14/10/2026 À 15 h 30 (et non à minuit), comme au
/// serveur : c'est l'heure qui révélait son défaut de flottant (5,64 au lieu
/// de 5).
///
/// Jours calculés à la main :
///   - mise en lot 10/10 : 10 → J1, 11 → J2, 12 → J3, 13 → J4, 14 → J5 ;
///   - reproduction, saillies 01/10 et 12/10 : 12 → J1, 13 → J2, 14 → J3
///     (et non J287 de la mise en lot du 01/01) ;
///   - fin de rémanence de l'Anti-coccidien validé le 14/10 : 14 + 5 = 19/10.
void main() {
  late AppDatabase db;
  late SoinsRepository soins;

  final maintenant = DateTime(2026, 10, 14, 15, 30);
  var compteur = 0;

  String id(String prefixe) {
    compteur++;
    return '$prefixe${compteur.toString().padLeft(4, '0')}-1111-4111-8111-111111111111';
  }

  Future<void> standard(
    String traitement,
    int? debut,
    int? fin,
    int remanence,
    String produit,
    String dosage, {
    String? libelle,
    String espece = 'cuniculture',
  }) async {
    await db
        .into(db.prophylaxisScheduleStandards)
        .insert(
          ProphylaxisScheduleStandardsCompanion.insert(
            id: id('5555'),
            speciesCode: espece,
            periodLabel: libelle ?? 'J$debut',
            cycleDayStart: Value(debut),
            cycleDayEnd: Value(fin),
            treatment: traitement,
            productRecommended: Value(produit),
            dosage: Value(dosage),
            withdrawalDays: Value(remanence),
          ),
        );
  }

  Future<LivestockLot> bande(
    String code,
    String stade,
    DateTime miseEnLot,
  ) async {
    final lotId = id('aaaa');
    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: lotId,
            code: code,
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            speciesCode: const Value('cuniculture'),
            stage: Value(stade),
            createdDate: Value(miseEnLot),
            initialQuantity: const Value(20),
            currentQuantity: const Value(20),
          ),
        );
    return (db.select(
      db.livestockLots,
    )..where((t) => t.id.equals(lotId))).getSingle();
  }

  Future<void> saillie(
    LivestockLot lot,
    DateTime date, {
    SyncStatus statut = SyncStatus.synced,
  }) async {
    await db
        .into(db.livestockReproductionEvents)
        .insert(
          LivestockReproductionEventsCompanion.insert(
            id: id('cccc'),
            deviceId: statut == SyncStatus.synced ? 'serveur' : 'poste-test',
            syncStatus: Value(statut),
            updatedAt: date,
            lotId: lot.id,
            motherRef: 'F-01',
            saillieDate: Value(date),
          ),
        );
  }

  Future<ProtocoleDuJour> protocole(LivestockLot lot, [DateTime? quand]) =>
      soins.protocoleDuJour(
        bande: lot,
        codeEspece: 'cuniculture',
        quand: quand ?? maintenant,
      );

  List<String> noms(ProtocoleDuJour p) =>
      p.traitements.map((t) => t.standard.treatment).toList();

  setUp(() async {
    compteur = 0;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    soins = SoinsRepository(database: db, deviceId: 'poste-test');

    await standard('Anti-stress', 2, 4, 0, 'Vitalyte', "1C / 10L d'eau");
    await standard('Anti-coccidien', 5, 5, 5, 'Antcox', "1C / 20L d'eau");
    await standard(
      'Déparasitage',
      null,
      null,
      7,
      'Levalap',
      "1C / 5L d'eau",
      libelle: 'Le 1er du mois',
    );
  });

  tearDown(() => db.close());

  group('jeu commun 15.35 — mêmes réponses que le service serveur', () {
    test(
      'le jour de cycle est un entier, J1 étant le jour de référence',
      () async {
        final lot = await bande('LOT-A', 'croissance', DateTime(2026, 10, 10));

        expect(
          (await protocole(lot)).jourDeCycle,
          5,
          reason:
              "le 14/10 à 15 h 30 est le J5 d'une bande mise en lot le 10/10",
        );
        expect(
          (await protocole(lot, DateTime(2026, 10, 10, 23, 59))).jourDeCycle,
          1,
        );
        expect((await protocole(lot, DateTime(2026, 10, 12))).jourDeCycle, 3);
      },
    );

    test(
      'une bande en reproduction se compte depuis sa DERNIÈRE saillie',
      () async {
        final lot = await bande('LOT-R', 'reproduction', DateTime(2026, 1, 1));
        await saillie(lot, DateTime(2026, 10, 1));
        await saillie(lot, DateTime(2026, 10, 12));

        final p = await protocole(lot);

        expect(p.jourDeCycle, 3, reason: '12/10 → J1, 13 → J2, 14 → J3');
        expect(p.determinable, isTrue);
        expect(noms(p), ['Anti-stress']);
      },
    );

    test(
      'une bande en reproduction sans saillie est indéterminée et dit pourquoi',
      () async {
        final lot = await bande('LOT-R', 'reproduction', DateTime(2026, 1, 1));

        final p = await protocole(lot);

        expect(
          p.jourDeCycle,
          isNull,
          reason: 'jamais de repli sur la mise en lot',
        );
        expect(p.determinable, isFalse);
        // Ticket #45 : Anti-stress J2-J4 + Anti-coccidien J5 sont exposés même
        // sans saillie — le cycle est inconnu mais l'administration reste possible.
        expect(p.traitements, hasLength(2));
        expect(noms(p), containsAll(['Anti-stress', 'Anti-coccidien']));
        expect(p.motifIndetermine, contains('saillie'));
      },
    );

    test(
      'une bande en reproduction sans saillie, mise en lot le 10/10, reste indéterminée (le serveur ne la notifie pas)',
      () async {
        final lot = await bande(
          'LOT-R',
          'reproduction',
          DateTime(2026, 10, 10),
        );
        // Entrée « large » : due n'importe quel jour de 1 à 999 si la bande
        // était évaluée sur sa mise en lot.
        await standard('Large', 1, 999, 0, 'Z', 'z');

        final p = await protocole(lot);

        expect(p.determinable, isFalse);
        // Ticket #45 : Anti-stress + Anti-coccidien + Large (1-999) exposés.
        expect(p.traitements, hasLength(3));
        expect(noms(p), containsAll(['Anti-stress', 'Anti-coccidien', 'Large']));
      },
    );

    test(
      'les traitements dus viennent du barème selon les bornes entières',
      () async {
        final lot = await bande('LOT-A', 'croissance', DateTime(2026, 10, 10));

        Future<List<String>> auJour(int j) async =>
            noms(await protocole(lot, DateTime(2026, 10, 9 + j, 15, 30)));

        expect(await auJour(1), <String>[]);
        expect(await auJour(2), ['Anti-stress']);
        expect(await auJour(4), ['Anti-stress']);
        expect(await auJour(5), ['Anti-coccidien']);
        expect(await auJour(6), <String>[]);
      },
    );

    test("une entrée d'une autre espèce n'est jamais due", () async {
      await standard('Porcin', 5, 5, 0, 'Y', 'y', espece: 'porciculture');
      final lot = await bande('LOT-A', 'croissance', DateTime(2026, 10, 10));

      expect(noms(await protocole(lot)), ['Anti-coccidien']);
    });

    test(
      "« Le 1er du mois » n'est jamais évaluée, mais elle est COMPTÉE",
      () async {
        final lot = await bande('LOT-A', 'croissance', DateTime(2026, 10, 10));

        // J-3 à J40, comme au serveur (range(-3, 40)).
        for (var j = -3; j <= 40; j++) {
          final p = await protocole(lot, DateTime(2026, 10, 9 + j, 15, 30));
          expect(noms(p), isNot(contains('Déparasitage')), reason: 'J$j');
        }

        expect((await protocole(lot)).calendairesNonEvalues, 1);
      },
    );

    test("le protocole du jour d'une bande en croissance", () async {
      final lot = await bande('LOT-A', 'croissance', DateTime(2026, 10, 10));

      final p = await protocole(lot);

      expect(p.determinable, isTrue);
      expect(p.jourDeCycle, 5);
      expect(noms(p), ['Anti-coccidien']);
      expect(p.enAttente, 1);
      expect(p.traitements.single.remanenceJours, 5);
    });

    test(
      "valider l'Anti-coccidien le 14/10 bloque la bande jusqu'au 19/10 (14 + 5)",
      () async {
        final lot = await bande('LOT-A', 'croissance', DateTime(2026, 10, 10));
        final t = (await protocole(lot)).traitements.single;

        await soins.enregistrer(
          lotId: lot.id,
          typeAction: t.standard.treatment,
          produit: t.standard.productRecommended,
          dose: t.standard.dosage,
          delaiAttenteJours: t.remanenceJours,
          quand: maintenant,
        );

        final remanence = await db
            .select(db.veterinaryWithdrawalPeriods)
            .getSingle();
        expect(remanence.endDate, DateTime(2026, 10, 19));
        expect((await protocole(lot)).enAttente, 0);
      },
    );

    test('un jour sans traitement est libre et non indéterminé', () async {
      // Mise en lot 01/10 : le 14/10 est le J14, rien au barème.
      final lot = await bande('LOT-A', 'croissance', DateTime(2026, 10, 1));

      final p = await protocole(lot);

      expect(p.determinable, isTrue);
      expect(p.jourDeCycle, 14);
      expect(p.traitements, isEmpty);
    });

    test(
      "une bande pas encore mise en lot à la date n'a aucun traitement",
      () async {
        final lot = await bande('LOT-A', 'croissance', DateTime(2026, 10, 20));

        final p = await protocole(lot);

        expect(p.jourDeCycle, lessThan(1));
        expect(p.traitements, isEmpty);
      },
    );
  });

  group('jours calendaires entiers (défaut de flottant payé au serveur)', () {
    test("l'heure des deux dates est ignorée", () {
      expect(
        SoinsRepository.joursCalendairesEntre(
          DateTime(2026, 10, 12, 23, 59),
          DateTime(2026, 10, 14, 0, 1),
        ),
        2,
      );
      expect(
        SoinsRepository.joursCalendairesEntre(
          DateTime(2026, 10, 10),
          DateTime(2026, 10, 14, 6),
        ),
        4,
        reason: '06 h 00 : 4 et non 4,25 (le J5 du serveur avant 15.35)',
      );
    });

    test('fin de mois, fin d\'année, année bissextile, sens négatif', () {
      expect(
        SoinsRepository.joursCalendairesEntre(
          DateTime(2026, 12, 31, 22),
          DateTime(2027, 1, 1, 1),
        ),
        1,
      );
      expect(
        SoinsRepository.joursCalendairesEntre(
          DateTime(2028, 2, 28),
          DateTime(2028, 3, 1),
        ),
        2,
      );
      expect(
        SoinsRepository.joursCalendairesEntre(
          DateTime(2026, 10, 12),
          DateTime(2026, 10, 11, 9),
        ),
        -1,
      );
    });

    test(
      'une date UTC et une date locale du même jour calendaire : même écart',
      () {
        expect(
          SoinsRepository.joursCalendairesEntre(
            DateTime.utc(2026, 10, 12, 23),
            DateTime(2026, 10, 14),
          ),
          2,
        );
      },
    );
  });

  group('règle du serveur appliquée au poste — cas propres au poste', () {
    test(
      "⚠️ une saillie déclarée au poste et pas encore acquittée compte déjà",
      () async {
        final lot = await bande('LOT-R', 'reproduction', DateTime(2026, 1, 1));
        await saillie(lot, DateTime(2026, 10, 1));
        await saillie(lot, DateTime(2026, 10, 12), statut: SyncStatus.pending);

        expect((await protocole(lot)).jourDeCycle, 3);
      },
    );

    test(
      "⚠️ une saillie REFUSÉE par le serveur (conflit) ne compte pas : il ne la connaît pas",
      () async {
        final lot = await bande('LOT-R', 'reproduction', DateTime(2026, 1, 1));
        await saillie(lot, DateTime(2026, 10, 1));
        await saillie(lot, DateTime(2026, 10, 12), statut: SyncStatus.conflict);

        // Seule reste la saillie du 01/10 : 01 → J1 … 14 → J14.
        expect((await protocole(lot)).jourDeCycle, 14);
      },
    );

    test(
      'un événement de reproduction sans date de saillie est ignoré, sans erreur',
      () async {
        // Colonne NOT NULL au serveur, nullable au poste : une ligne locale sans
        // date ne doit ni planter le calcul ni servir de référence.
        final lot = await bande('LOT-R', 'reproduction', DateTime(2026, 1, 1));
        await db
            .into(db.livestockReproductionEvents)
            .insert(
              LivestockReproductionEventsCompanion.insert(
                id: id('cccc'),
                deviceId: 'poste-test',
                updatedAt: maintenant,
                lotId: lot.id,
                motherRef: 'F-02',
              ),
            );
        await saillie(lot, DateTime(2026, 10, 12));

        expect((await protocole(lot)).jourDeCycle, 3);
      },
    );

    test("la saillie d'une AUTRE bande n'est jamais la référence", () async {
      final lot = await bande('LOT-R', 'reproduction', DateTime(2026, 1, 1));
      final autre = await bande('LOT-S', 'reproduction', DateTime(2026, 1, 1));
      await saillie(lot, DateTime(2026, 10, 1));
      await saillie(autre, DateTime(2026, 10, 12));

      expect((await protocole(lot)).jourDeCycle, 14);
    });

    test(
      "⚠️ comme au serveur, la DERNIÈRE saillie connue vaut aussi pour un jour qui la précède",
      () async {
        // Le serveur prend `latest('saillie_date')` sans borne sur le jour
        // consulté : le 11/10, la référence reste le 12/10 → J0, pas le J11
        // compté depuis le 01/10. Recopié tel quel (décision ouverte, voir F0.91).
        final lot = await bande('LOT-R', 'reproduction', DateTime(2026, 1, 1));
        await saillie(lot, DateTime(2026, 10, 1));
        await saillie(lot, DateTime(2026, 10, 12));

        final p = await protocole(lot, DateTime(2026, 10, 11, 9));

        expect(p.jourDeCycle, 0);
        expect(p.traitements, isEmpty);
      },
    );

    test(
      "⚠️ l'heure portée par une date de référence ne décale pas le jour de cycle",
      () async {
        // Jours calendaires entiers, minuit à minuit : une saillie lue à 23 h
        // et un jour consulté à 06 h restent trois jours calendaires (12, 13, 14).
        final lot = await bande('LOT-R', 'reproduction', DateTime(2026, 1, 1));
        await saillie(lot, DateTime(2026, 10, 12, 23));
        final croissance = await bande(
          'LOT-A',
          'croissance',
          DateTime(2026, 10, 10, 18),
        );

        expect(
          (await protocole(lot, DateTime(2026, 10, 14, 6))).jourDeCycle,
          3,
        );
        expect(
          (await protocole(croissance, DateTime(2026, 10, 14, 6))).jourDeCycle,
          5,
        );
      },
    );

    test(
      '⚠️ un soin daté du jour avec une heure est reconnu (rapprochement sur le JOUR, comme `whereDate`)',
      () async {
        final lot = await bande('LOT-A', 'croissance', DateTime(2026, 10, 10));
        await db
            .into(db.veterinaryRecords)
            .insert(
              VeterinaryRecordsCompanion.insert(
                id: id('dddd'),
                deviceId: 'serveur',
                syncStatus: const Value(SyncStatus.synced),
                updatedAt: maintenant,
                lotId: lot.id,
                actionType: 'Anti-coccidien',
                recordDate: DateTime(2026, 10, 14, 10, 15),
              ),
            );
        // Un soin daté du 14/10 À MINUIT PILE (Anti-stress) appartient au 14/10,
        // jamais à la veille : la borne haute du 13/10 est exclusive.
        await db
            .into(db.veterinaryRecords)
            .insert(
              VeterinaryRecordsCompanion.insert(
                id: id('dddd'),
                deviceId: 'serveur',
                syncStatus: const Value(SyncStatus.synced),
                updatedAt: maintenant,
                lotId: lot.id,
                actionType: 'Anti-stress',
                recordDate: DateTime(2026, 10, 14),
              ),
            );

        final p = await protocole(lot);

        expect(p.traitements.single.dejaAdministre, isTrue);
        expect(p.enAttente, 0);

        // Le 13/10 (J4) a l'Anti-stress au barème : le soin du 14/10 00 h 00 ne
        // le valide pas.
        final veille = await protocole(lot, DateTime(2026, 10, 13, 15, 30));
        expect(veille.traitements.single.dejaAdministre, isFalse);
      },
    );

    test(
      "le soin d'une AUTRE bande, même libellé, même jour, ne valide rien (filtre `lot_id` du serveur)",
      () async {
        final lot = await bande('LOT-A', 'croissance', DateTime(2026, 10, 10));
        final autre = await bande(
          'LOT-B',
          'croissance',
          DateTime(2026, 10, 10),
        );
        await soins.enregistrer(
          lotId: autre.id,
          typeAction: 'Anti-coccidien',
          produit: 'Antcox',
          quand: maintenant,
        );

        expect(
          (await protocole(lot)).traitements.single.dejaAdministre,
          isFalse,
        );
        expect(
          (await protocole(autre)).traitements.single.dejaAdministre,
          isTrue,
        );
      },
    );

    test(
      "les traitements dus sont rangés comme au serveur : jour de début, puis libellé du traitement",
      () async {
        // `period_label` volontairement trompeurs : un tri sur le libellé de
        // période (ancien tri du poste) donnerait Calcium, Vitamines, Anti-stress.
        await (db.delete(db.prophylaxisScheduleStandards)).go();
        await standard('Vitamines', 3, 3, 0, 'V', 'v', libelle: 'A');
        await standard('Anti-stress', 2, 4, 0, 'S', 's', libelle: 'Z');
        await standard('Calcium', 2, 4, 0, 'C', 'c', libelle: 'A0');
        final lot = await bande('LOT-A', 'croissance', DateTime(2026, 10, 10));

        final p = await protocole(lot, DateTime(2026, 10, 12));

        expect(p.jourDeCycle, 3);
        expect(noms(p), ['Anti-stress', 'Calcium', 'Vitamines']);
      },
    );
  });
}
