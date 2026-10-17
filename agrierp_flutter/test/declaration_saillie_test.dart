import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_repository.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.35 — LA SAILLIE SE DÉCLARE AU POSTE, HORS LIGNE.
///
/// ⚠️⚠️ **C'EST L'ACTE QUI SE FAIT AU CLAPIER.** Jusqu'ici il finissait sur un
/// bout de papier, puis se ressaisissait au bureau — ou se perdait. Le ticket
/// 14.73 ouvre `livestock_reproduction_events` à l'envoi ; le poste écrit une
/// ligne `pending` qui part au prochain tirage.
///
/// ⚠️ **PALPATION, MISE BAS ET SEVRAGE RESTENT WEB.** Ce sont des CORRECTIONS
/// d'un cycle que le serveur a pu faire évoluer entre-temps : « dernier
/// écrivain gagne » convient à une fiche journalière qui se corrige dans la
/// journée, pas à une gestation de trois mois.
void main() {
  late AppDatabase db;
  late SuiviReproductionRepository depot;

  const bandeLapins = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
  const bandeVolailles = 'cccccccc-0000-4000-8000-cccccccccccc';

  final aujourdhui = DateTime.now();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = SuiviReproductionRepository(database: db, deviceId: 'poste-test');

    Future<void> bande(String id, String code, String espece) => db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: id,
            code: code,
            speciesId: 'esp-$espece',
            speciesCode: Value(espece),
            currentQuantity: const Value(50),
          ),
        );

    await bande(bandeLapins, 'LOT-LAP-2026-06', 'cuniculture');
    await bande(
      'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb',
      'BANDE-POR-P1',
      'porciculture',
    );
    await bande(bandeVolailles, 'VOL-REPRO-LOT-1', 'aviculture');
  });

  tearDown(() async => db.close());

  Future<List<LivestockReproductionEvent>> cycles() =>
      db.select(db.livestockReproductionEvents).get();

  group('dépôt', () {
    test('⚠️ la saillie déclarée est mise en file d envoi', () async {
      await depot.declarerSaillie(
        lotId: bandeLapins,
        numeroFemelle: 'R8',
        numeroMale: 'M2',
        dateSaillie: aujourdhui,
      );

      final enregistres = await cycles();

      expect(enregistres, hasLength(1));
      expect(enregistres.single.motherRef, 'R8');
      expect(enregistres.single.sireRef, 'M2');
      expect(enregistres.single.status, 'en_cours');
      // ⚠️ `pending` : c'est ce statut qui la fait partir au prochain tirage.
      expect(enregistres.single.syncStatus, SyncStatus.pending);
      expect(enregistres.single.deviceId, 'poste-test');
    });

    /// ⚠️⚠️ Deux gestations concurrentes sur la même femelle sont impossibles :
    /// l'écran les afficherait toutes deux et le KPI compterait double.
    test('⚠️⚠️ un second cycle sur la même femelle est refusé', () async {
      await depot.declarerSaillie(
        lotId: bandeLapins,
        numeroFemelle: 'R8',
        numeroMale: 'M2',
        dateSaillie: aujourdhui,
      );

      expect(
        () => depot.declarerSaillie(
          lotId: bandeLapins,
          numeroFemelle: 'R8',
          numeroMale: 'M5',
          dateSaillie: aujourdhui,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await cycles(), hasLength(1));
    });

    /// La même femelle redevient déclarable une fois son cycle clos.
    test('un cycle clos rouvre la déclaration', () async {
      await depot.declarerSaillie(
        lotId: bandeLapins,
        numeroFemelle: 'R8',
        numeroMale: 'M2',
        dateSaillie: aujourdhui.subtract(const Duration(days: 120)),
      );

      await (db.update(
        db.livestockReproductionEvents,
      )..where((t) => t.motherRef.equals('R8'))).write(
        const LivestockReproductionEventsCompanion(status: Value('termine')),
      );

      await depot.declarerSaillie(
        lotId: bandeLapins,
        numeroFemelle: 'R8',
        numeroMale: 'M5',
        dateSaillie: aujourdhui,
      );

      expect(await cycles(), hasLength(2));
    });

    /// ⚠️ Même borne que le serveur, pour que le refus ne survienne pas trois
    /// jours plus tard, au tirage.
    test('⚠️ une saillie datée du futur est refusée', () async {
      expect(
        () => depot.declarerSaillie(
          lotId: bandeLapins,
          numeroFemelle: 'R9',
          numeroMale: 'M2',
          dateSaillie: aujourdhui.add(const Duration(days: 1)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    /// ⚠️ Le suivi par femelle nommée ne couvre que deux filières — même règle
    /// que le serveur, qui refuse les autres à la réception.
    test('⚠️ une bande avicole n est pas déclarable', () async {
      expect(
        () => depot.declarerSaillie(
          lotId: bandeVolailles,
          numeroFemelle: 'P1',
          numeroMale: 'C1',
          dateSaillie: aujourdhui,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    /// 🔴→✅ Le badge « en attente » comptait les fiches, les ventes, les
    /// ajustements et les soins — mais NI les dépenses NI les saillies.
    test('⚠️ la saillie en attente compte dans le badge', () async {
      expect(await db.pendingCount(), 0);

      await depot.declarerSaillie(
        lotId: bandeLapins,
        numeroFemelle: 'R8',
        numeroMale: 'M2',
        dateSaillie: aujourdhui,
      );

      expect(await db.pendingCount(), 1);
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2200);
      tester.view.devicePixelRatio = 1;

      // ⚠️⚠️ **AUCUNE REMISE À L'ÉCHELLE EN FIN DE TEST.** Rendre la vue à sa
      // taille d'origine alors qu'une modale est encore montée fait échouer le
      // test SUIVANT sur une assertion du framework — un test rouge dont la
      // cause vit dans le test précédent, et qui passe pourtant en exécution
      // isolée. Chaque fichier de test tourne dans son propre isolat : laisser
      // la surface agrandie jusqu'à la fin du fichier n'a aucun effet ailleurs.

      await tester.pumpWidget(
        MaterialApp(home: SuiviReproductionScreen(depot: depot)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('le bouton de déclaration est là sur lapins et porcs', (
      tester,
    ) async {
      await afficher(tester);

      expect(find.byKey(const Key('declarer-saillie-lapins')), findsOneWidget);
      expect(find.text('Déclarer une Saillie Lapin'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onglet-repro-Porcs')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('declarer-saillie-porcs')), findsOneWidget);
      expect(find.text('Déclarer une Saillie Porc'), findsOneWidget);
    });

    testWidgets('⚠️ la modale reprend les champs de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('declarer-saillie-lapins')));
      await tester.pumpAndSettle();

      expect(find.text('Déclarer une Saillie (Cuniculture)'), findsOneWidget);
      expect(find.text('BANDE *'), findsOneWidget);
      expect(find.text('N° LAPINE (R1..RN) *'), findsOneWidget);
      expect(find.text('MÂLE SAILLISSEUR N° *'), findsOneWidget);
      expect(find.text('DATE DE SAILLIE *'), findsOneWidget);
      expect(find.text('CAGES OCCUPÉES'), findsOneWidget);
      expect(find.byKey(const Key('apercu-echeances')), findsOneWidget);
    });

    /// ⚠️⚠️ Aucune table ne modélise de sous-division « cage » : le champ est
    /// présent — la maquette le porte — mais désactivé, car une valeur saisie
    /// se perdrait en silence.
    testWidgets('⚠️⚠️ le champ « Cages Occupées » est présent et inerte', (
      tester,
    ) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('declarer-saillie-lapins')));
      await tester.pumpAndSettle();

      final champ = tester.widget<TextField>(
        find.byKey(const Key('saillie-cages')),
      );

      expect(champ.enabled, isFalse);
      expect(
        find.text('Référentiel des cages absent du schéma'),
        findsOneWidget,
      );
    });

    testWidgets('la déclaration écrit la saillie et l affiche', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('declarer-saillie-lapins')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('saillie-femelle')), 'R8');
      await tester.enterText(find.byKey(const Key('saillie-male')), 'M2');
      await tester.tap(find.byKey(const Key('saillie-enregistrer')));
      await tester.pumpAndSettle();

      expect(await cycles(), hasLength(1));
      expect(find.text('R8'), findsOneWidget);
      expect(find.text('M2'), findsOneWidget);
    });

    testWidgets(
      '⚠️ le refus s affiche dans la modale, pas trois jours plus tard',
      (tester) async {
        await depot.declarerSaillie(
          lotId: bandeLapins,
          numeroFemelle: 'R8',
          numeroMale: 'M2',
          dateSaillie: aujourdhui,
        );

        await afficher(tester);
        await tester.tap(find.byKey(const Key('declarer-saillie-lapins')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('saillie-femelle')), 'R8');
        await tester.enterText(find.byKey(const Key('saillie-male')), 'M5');
        await tester.tap(find.byKey(const Key('saillie-enregistrer')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('saillie-erreur')), findsOneWidget);
        expect(find.textContaining('déjà en cours'), findsOneWidget);
        expect(await cycles(), hasLength(1));
      },
    );

    testWidgets('les deux numéros sont requis', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('declarer-saillie-lapins')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('saillie-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('saillie-erreur')), findsOneWidget);
      expect(await cycles(), isEmpty);
    });

    /// ⚠️ La modale porcine de la maquette n'a ni cages ni aperçu.
    testWidgets('⚠️ la modale porcine n a ni cages ni aperçu', (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('onglet-repro-Porcs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('declarer-saillie-porcs')));
      await tester.pumpAndSettle();

      expect(find.text('Déclarer une Saillie (Porciculture)'), findsOneWidget);
      expect(find.text('N° TRUIE (T1..TN) *'), findsOneWidget);
      expect(find.text('VERRAT N° *'), findsOneWidget);
      expect(find.byKey(const Key('saillie-cages')), findsNothing);
      expect(find.byKey(const Key('apercu-echeances')), findsNothing);
    });
  });
}
