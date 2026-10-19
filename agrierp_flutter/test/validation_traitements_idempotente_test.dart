import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.93 (réserve 3 de l'audit indépendant du 14/10/2026) — VALIDER LES
/// TRAITEMENTS DU PROTOCOLE DU JOUR EST IDEMPOTENT AU NIVEAU DU DÉPÔT.
///
/// ⚠️⚠️ **LE DÉFAUT** : les cinq fiches (`_validerTraitements`) parcouraient
/// l'INSTANTANÉ `_protocole` chargé à l'affichage et appelaient
/// `SoinsRepository.enregistrer` pour chaque case cochée, sans relire le
/// registre. Seule la désactivation du bouton empêchait un double soin : deux
/// appels en rafale (double clic avant le `setState`, deux fenêtres) écrivaient
/// DEUX soins et DEUX périodes de rémanence pour le même traitement — et le
/// serveur, qui recalcule sous verrou (15.35, `ValidateProphylaxisTreatmentsAction`),
/// aurait reçu deux enregistrements distincts (deux UUID) qu'il ne peut pas
/// fusionner.
///
/// Portage de la règle serveur : le protocole est RECALCULÉ à l'instant de
/// l'écriture, dans une transaction ; seuls les traitements DUS ce jour-là, non
/// encore administrés et cochés sont écrits. Aucune règle sanitaire ne change :
/// « déjà administré » reste « un soin du même libellé, même bande, même jour
/// calendaire » (`protocoleDuJour`).
void main() {
  late AppDatabase db;
  late SoinsRepository soins;

  const bandeA = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const bandeB = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';
  const vaccin = '11111111-1111-4111-8111-111111111111';
  const vitamines = '22222222-2222-4222-8222-222222222222';
  const plusTard = '33333333-3333-4333-8333-333333333333';
  final miseEnLot = DateTime(2026, 8, 1);
  // J5 de la bande.
  final jourJ5 = DateTime(2026, 8, 5);

  Future<void> standard({
    required String id,
    required String traitement,
    required int debut,
    required int fin,
    int remanence = 0,
    String? produit = 'Ivermectine',
  }) => db
      .into(db.prophylaxisScheduleStandards)
      .insert(
        ProphylaxisScheduleStandardsCompanion.insert(
          id: id,
          speciesCode: 'cuniculture',
          periodLabel: 'libellé libre',
          cycleDayStart: Value(debut),
          cycleDayEnd: Value(fin),
          treatment: traitement,
          productRecommended: Value(produit),
          dosage: const Value('0,2 ml / kg'),
          withdrawalDays: Value(remanence),
        ),
      );

  Future<LivestockLot> bande(String id) async {
    await db
        .into(db.livestockLots)
        .insertOnConflictUpdate(
          LivestockLotsCompanion.insert(
            id: id,
            code: 'CUN-$id'.substring(0, 12),
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            stage: const Value('croissance'),
            createdDate: Value(miseEnLot),
            currentQuantity: const Value(40),
          ),
        );
    return (db.select(
      db.livestockLots,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  Future<List<VeterinaryRecord>> soinsDe(String lot) => (db.select(
    db.veterinaryRecords,
  )..where((t) => t.lotId.equals(lot))).get();

  Future<List<VeterinaryWithdrawalPeriod>> remanencesDe(String lot) =>
      (db.select(
        db.veterinaryWithdrawalPeriods,
      )..where((t) => t.lotId.equals(lot))).get();

  Future<List<VeterinaryRecord>> valider(
    LivestockLot lot,
    Set<String> ids, {
    DateTime? jour,
    String? observations,
  }) => soins.validerTraitementsDuJour(
    bande: lot,
    codeEspece: 'cuniculture',
    quand: jour ?? jourJ5,
    idsBareme: ids,
    observations: observations,
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
    // Vaccin J5 avec 14 j de rémanence ; vitamines J5-J6 sans rémanence ;
    // un traitement J20 (pas dû au J5).
    await standard(
      id: vaccin,
      traitement: 'Vaccin VHD',
      debut: 5,
      fin: 5,
      remanence: 14,
    );
    await standard(id: vitamines, traitement: 'Vitamines', debut: 5, fin: 6);
    await standard(id: plusTard, traitement: 'Vermifuge', debut: 20, fin: 20);
  });

  tearDown(() => db.close());

  group('idempotence — un seul soin, une seule rémanence', () {
    test(
      '🔴 deux validations EN RAFALE (sans attendre) : un seul soin et une seule rémanence',
      () async {
        final lot = await bande(bandeA);

        // Les deux appels partent AVANT qu'aucun ne soit terminé : c'est le
        // double clic ou les deux fenêtres, sans le bouton pour s'interposer.
        final resultats = await Future.wait([
          valider(lot, {vaccin}),
          valider(lot, {vaccin}),
        ]);

        final registre = await soinsDe(bandeA);
        expect(
          registre,
          hasLength(1),
          reason: 'deux soins « Vaccin VHD » le même jour = double traitement',
        );
        expect(await remanencesDe(bandeA), hasLength(1));
        expect(
          resultats.map((r) => r.length).toList()..sort(),
          [0, 1],
          reason: 'un appel écrit, l autre ne trouve plus rien à écrire',
        );
      },
    );

    test(
      '🔴 trois validations en rafale de deux traitements : deux soins, une rémanence',
      () async {
        final lot = await bande(bandeA);

        await Future.wait([
          valider(lot, {vaccin, vitamines}),
          valider(lot, {vaccin, vitamines}),
          valider(lot, {vitamines, vaccin}),
        ]);

        final registre = await soinsDe(bandeA);
        expect(registre.map((s) => s.actionType).toList()..sort(), [
          'Vaccin VHD',
          'Vitamines',
        ]);
        // Seul le vaccin porte un délai d'attente (et un produit).
        final remanences = await remanencesDe(bandeA);
        expect(remanences, hasLength(1));
        expect(
          remanences.single.endDate,
          DateTime(2026, 8, 19),
          reason: '5 août + 14 jours',
        );
      },
    );

    test(
      '🔴 validation répétée APRÈS la première (séquentielle) : rien de plus',
      () async {
        final lot = await bande(bandeA);

        final premier = await valider(lot, {vaccin});
        final second = await valider(lot, {vaccin});

        expect(premier, hasLength(1));
        expect(second, isEmpty);
        expect(await soinsDe(bandeA), hasLength(1));
        expect(await remanencesDe(bandeA), hasLength(1));
      },
    );

    test(
      '🔴 un soin déjà au registre ce jour-là, à une autre heure : non réécrit',
      () async {
        final lot = await bande(bandeA);
        await soins.enregistrer(
          lotId: bandeA,
          typeAction: 'Vaccin VHD',
          produit: 'Ivermectine',
          delaiAttenteJours: 14,
          quand: DateTime(2026, 8, 5, 10, 15),
        );

        final crees = await valider(lot, {vaccin, vitamines});

        expect(crees.map((s) => s.actionType), ['Vitamines']);
        expect(await soinsDe(bandeA), hasLength(2));
        expect(await remanencesDe(bandeA), hasLength(1));
      },
    );
  });

  group('portée — ce que l idempotence ne doit PAS bloquer', () {
    test('même traitement, AUTRE bande : deux soins (un par bande)', () async {
      final a = await bande(bandeA);
      final b = await bande(bandeB);

      await Future.wait([
        valider(a, {vaccin}),
        valider(b, {vaccin}),
      ]);

      expect(await soinsDe(bandeA), hasLength(1));
      expect(await soinsDe(bandeB), hasLength(1));
      expect(await remanencesDe(bandeA), hasLength(1));
      expect(await remanencesDe(bandeB), hasLength(1));
    });

    test(
      'même traitement, AUTRE jour où il est encore dû : un second soin',
      () async {
        final lot = await bande(bandeA);
        await valider(lot, {vitamines});
        await valider(lot, {vitamines}, jour: DateTime(2026, 8, 6));

        final registre = await soinsDe(bandeA);
        expect(registre, hasLength(2));
        expect(registre.map((s) => s.recordDate).toSet(), {
          DateTime(2026, 8, 5),
          DateTime(2026, 8, 6),
        });
      },
    );

    test(
      'un identifiant non dû ce jour-là (ou inconnu) est ignoré, comme au serveur',
      () async {
        final lot = await bande(bandeA);

        final crees = await valider(lot, {
          plusTard,
          'ffffffff-ffff-4fff-8fff-ffffffffffff',
        });

        expect(crees, isEmpty);
        expect(await soinsDe(bandeA), isEmpty);
      },
    );

    test('une case non cochée n est pas écrite', () async {
      final lot = await bande(bandeA);
      await valider(lot, {vitamines});
      final registre = await soinsDe(bandeA);
      expect(registre.single.actionType, 'Vitamines');
      expect(await remanencesDe(bandeA), isEmpty);
    });

    test(
      'le soin écrit porte le libellé, le produit, la dose, le jour, les observations et part en pending',
      () async {
        final lot = await bande(bandeA);
        await valider(lot, {vaccin}, observations: 'RAS');
        final s = (await soinsDe(bandeA)).single;
        expect(s.actionType, 'Vaccin VHD');
        expect(s.productUsed, 'Ivermectine');
        expect(s.dose, '0,2 ml / kg');
        expect(s.recordDate, DateTime(2026, 8, 5));
        expect(s.symptomes, 'RAS');
        expect(s.withdrawalDays, 14);
        expect(s.syncStatus, SyncStatus.pending);
        // La rémanence porte l'identifiant du soin (renvoi sans doublon).
        expect((await remanencesDe(bandeA)).single.id, s.id);
      },
    );

    test(
      'règle sanitaire inchangée : délai d attente SANS produit nommé → soin, mais aucune rémanence',
      () async {
        const sansProduit = '44444444-4444-4444-8444-444444444444';
        await standard(
          id: sansProduit,
          traitement: 'Désinfection clapier',
          debut: 5,
          fin: 5,
          remanence: 7,
          produit: null,
        );
        final lot = await bande(bandeA);
        await valider(lot, {sansProduit});
        expect((await soinsDe(bandeA)).single.withdrawalDays, 7);
        expect(await remanencesDe(bandeA), isEmpty);
      },
    );

    test('observations vides ou blanches : aucun symptôme consigné', () async {
      final lot = await bande(bandeA);
      await valider(lot, {vaccin}, observations: '   ');
      expect((await soinsDe(bandeA)).single.symptomes, isNull);
    });
  });

  group('les fiches à protocole du jour passent par le dépôt idempotent', () {
    // ⚠️ Lecture du SOURCE, comme `conformite_portage_test.dart` : un retour
    // à la boucle sur l'instantané `_protocole` rend l'écran visuellement
    // identique, et seul le double clic le trahirait.
    // 🔁 Ticket U12a — Lapins et Porcs partagent la vue du Blade (`fiche_categories_vue.dart`) ; la fiche Escargots
    // n'a plus de protocole du jour : son Blade n'a pas `x-prophylaxie-du-jour` (vérifié ci-dessous).
    const fiches = [
      'fiche_categories_vue.dart',
      'fiche_pondeuses_screen.dart',
      'fiche_reproducteurs_screen.dart',
    ];

    test('fiche_escargots_screen.dart : aucun protocole du jour, comme son Blade', () {
      final source = File('lib/features/elevage/fiche_escargots_screen.dart').readAsStringSync();
      expect(source, isNot(contains('_validerTraitements')));
      expect(source, isNot(contains('ProphylaxieDuJourFiche(')));
    });

    String corpsDeValider(String source) {
      final debut = source.indexOf(
        'Future<void> _validerTraitements() async {',
      );
      expect(debut, isNonNegative, reason: '_validerTraitements introuvable');
      final suivant = source.indexOf('\n  }\n', debut);
      expect(suivant, isNonNegative, reason: 'fin de méthode introuvable');
      return source.substring(debut, suivant);
    }

    for (final f in fiches) {
      test('$f : _validerTraitements délègue à validerTraitementsDuJour', () {
        // Les fiches sont en CRLF : normalisées avant découpe.
        final corps = corpsDeValider(
          File(
            'lib/features/elevage/$f',
          ).readAsStringSync().replaceAll('\r\n', '\n'),
        );
        expect(corps, contains('widget.soins.validerTraitementsDuJour('));
        expect(
          corps,
          isNot(contains('soins.enregistrer(')),
          reason:
              'écrire soin par soin depuis l instantané = double soin possible',
        );
        expect(
          corps,
          contains('if (_validationEnCours) return;'),
          reason: 'garde de l écran, en plus du dépôt',
        );
      });
    }
  });
}
