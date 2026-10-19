import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:agrierp/features/elevage/fiche_porcs_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tickets F0.96 / F0.97 — SAISIE VENTILÉE PAR CATÉGORIE (Lapins, Porcs), comme `saveDay` du web.
///
/// 🔴 Avant : la fiche Lapins enregistrait tous ses morts sur « Reproducteur » (catégorie FABRIQUÉE), la
/// fiche Porcs rechargeait ses morts à 0 — ré-enregistrer le jour les effaçait. Ces tests verrouillent :
///  - les colonnes `mort_*` / `don_*` sont écrites, et les totaux en sont la SOMME ;
///  - une bande sans chaîne reçoit son départ DÉDUIT du stade (`departDepuisStade`, 15.41) ;
///  - un passage de stade supérieur à la catégorie source est REFUSÉ avant toute écriture (D3) ;
///  - une fiche ancienne non ventilée n'est ni écrasée à 0, ni ventilée au hasard.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bande = 'aaaaaaaa-2222-4222-8222-aaaaaaaaaaaa';
  final jour = DateTime(2026, 10, 10);

  Future<void> creerBande({
    required String espece,
    required String stade,
    int effectif = 40,
    DateTime? creation,
  }) async {
    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bande,
            code: 'BANDE-01',
            speciesId: 'eeeeeeee-2222-4222-8222-eeeeeeeeeeee',
            speciesCode: Value(espece),
            stage: Value(stade),
            createdDate: Value(creation ?? DateTime(2026, 10, 1)),
            initialQuantity: Value(effectif),
            currentQuantity: Value(effectif),
          ),
        );
  }

  Future<LivestockDailyEntry> fiche() =>
      db.select(db.livestockDailyEntries).getSingle();

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
  });

  tearDown(() async => db.close());

  group('dépôt — enregistrement ventilé', () {
    test(
      'les morts et dons par catégorie sont écrits, les totaux en sont la somme',
      () async {
        await creerBande(espece: 'cuniculture', stade: 'engraissement');

        await depot.enregistrer(
          lotId: bande,
          jour: jour,
          achat: 0,
          ne: 0,
          // Valeurs contradictoires exprès : la ventilation fait foi, comme sur le web.
          mort: 99,
          don: 99,
          ventilation: const VentilationJour(mortJeune: 2, donJeune: 1),
        );

        final f = await fiche();
        expect([f.mort, f.don], [2, 1]);
        expect([f.mortRepro, f.mortSevre, f.mortJeune], [0, 0, 2]);
        expect([f.donRepro, f.donSevre, f.donJeune], [0, 0, 1]);
        // Recalcul indépendant : 40 − 2 morts − 1 don.
        expect(f.effectifFinal, 40 - 2 - 1);
      },
    );

    test(
      'bande sans chaîne : départ DÉDUIT du stade (40 sur Jeune, 0 ailleurs)',
      () async {
        await creerBande(espece: 'cuniculture', stade: 'engraissement');

        await depot.enregistrer(
          lotId: bande,
          jour: jour,
          achat: 0,
          ne: 0,
          mort: 0,
          don: 0,
          ventilation: const VentilationJour(mortJeune: 1),
        );

        final f = await fiche();
        expect([f.catDepartRepro, f.catDepartSevre, f.catDepartJeune], [
          0,
          0,
          40,
        ]);
      },
    );

    test(
      '🔴 D3 : un passage supérieur à la catégorie source est refusé, rien n\'est écrit',
      () async {
        // En engraissement, tout est sur Jeune : aucune Sous-mère à faire passer.
        await creerBande(espece: 'cuniculture', stade: 'engraissement');

        await expectLater(
          depot.enregistrer(
            lotId: bande,
            jour: jour,
            achat: 0,
            ne: 0,
            mort: 0,
            don: 0,
            ventilation: const VentilationJour(passage: 5),
          ),
          throwsA(isA<FicheRefusee>()),
        );
        expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
      },
    );

    test('un passage couvert par la catégorie source est enregistré', () async {
      await creerBande(espece: 'cuniculture', stade: 'croissance');

      await depot.enregistrer(
        lotId: bande,
        jour: jour,
        achat: 0,
        ne: 0,
        mort: 0,
        don: 0,
        ventilation: const VentilationJour(passage: 5),
      );

      final f = await fiche();
      expect(f.passageSevreJeune, 5);
      // Un passage déplace des sujets, il n'en retire aucun.
      expect(f.effectifFinal, 40);
    });
  });

  Future<void> afficher(WidgetTester tester, Widget ecran) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ecran));
    await tester.pumpAndSettle();
  }

  Future<void> ficheDuJour({
    required int mort,
    int? mortRepro,
    int? mortSevre,
    int? mortJeune,
  }) async {
    final aujourdhui = HeureBenin.maintenant();
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: 'ffffffff-2222-4222-8222-ffffffffffff',
            deviceId: 'poste-test',
            updatedAt: aujourdhui,
            lotId: bande,
            entryDate: DateTime(
              aujourdhui.year,
              aujourdhui.month,
              aujourdhui.day,
            ),
            mort: Value(mort),
            mortRepro: Value(mortRepro),
            mortSevre: Value(mortSevre),
            mortJeune: Value(mortJeune),
            effectifFinal: Value(40 - mort),
          ),
        );
  }

  group('écrans — rechargement fidèle', () {
    testWidgets(
      '🔴 Porcs : les morts ventilés reviennent au rechargement (plus remis à 0)',
      (tester) async {
        await creerBande(
          espece: 'porciculture',
          stade: 'engraissement',
          creation: HeureBenin.maintenant().subtract(const Duration(days: 5)),
        );
        await ficheDuJour(mort: 3, mortRepro: 1, mortSevre: 0, mortJeune: 2);

        await afficher(
          tester,
          FichePorcsScreen(depot: depot, soins: soins),
        );

        Text compteur(String c) =>
            tester.widget<Text>(find.byKey(Key('compteur-mort-$c')));
        expect(compteur('Reproducteur').data, '1');
        expect(compteur('Porc Marchand').data, '2');
        expect(compteur('Porcelet').data, '0');
        expect(find.byKey(const Key('porcs-non-ventilee')), findsNothing);
      },
    );

    testWidgets(
      '⚠️ Lapins : une fiche ancienne non ventilée est signalée et NON écrasée à 0',
      (tester) async {
        await creerBande(
          espece: 'cuniculture',
          stade: 'engraissement',
          creation: HeureBenin.maintenant().subtract(const Duration(days: 5)),
        );
        await ficheDuJour(mort: 3);

        await afficher(
          tester,
          FicheLapinsScreen(depot: depot, soins: soins),
        );

        expect(find.byKey(const Key('lapins-non-ventilee')), findsOneWidget);
        // Aucune catégorie inventée : les compteurs restent à 0, le total ancien est annoncé.
        // `valeur-…` existe dans les blocs Morts ET Dons : on lit tous les compteurs.
        for (final c in ['Reproducteur', 'Jeune', 'Sous-mères']) {
          for (final t in tester.widgetList<Text>(
            find.byKey(Key('valeur-${c.hashCode}')),
          )) {
            expect(t.data, '0', reason: c);
          }
        }

        await tester.ensureVisible(find.text('Enregistrer ce Jour'));
        await tester.tap(find.text('Enregistrer ce Jour'));
        await tester.pumpAndSettle();

        final f = await fiche();
        expect(f.mort, 3, reason: 'les 3 morts anciens ne sont pas effacés');
        expect(f.mortRepro, isNull, reason: 'aucune ventilation fabriquée');
      },
    );
  });
}
