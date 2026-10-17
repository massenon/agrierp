import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_escargots_screen.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_pondeuses_screen.dart';
import 'package:agrierp/features/elevage/fiche_reproducteurs_screen.dart';
import 'package:agrierp/features/elevage/production_oeufs_service.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.99 — LES MORTS D'UN JOUR RECHARGÉ SONT CONSERVÉS (web 15.47 Pondeuses / Escargots, 15.55
/// Reproducteurs).
///
/// 🔴 Avant : les trois fiches remettaient leurs compteurs de morts à 0 au chargement — la répartition
/// n'est pas stockée, seul le total l'est —, et ré-enregistrer le jour EFFAÇAIT ses morts. Le total est
/// désormais gardé tant qu'aucune répartition n'est ressaisie, et l'écran le dit (texte du web).
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'aaaaaaaa-9999-4999-8999-aaaaaaaaaaaa';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
  });

  tearDown(() async => db.close());

  Future<void> bandeEtFiche({required String espece, required String stade}) async {
    final aujourdhui = DateTime.now();
    await db.into(db.livestockLots).insert(
      LivestockLotsCompanion.insert(
        id: bandeId,
        code: 'BANDE-99',
        speciesId: 'eeeeeeee-9999-4999-8999-eeeeeeeeeeee',
        speciesCode: Value(espece),
        stage: Value(stade),
        createdDate: Value(aujourdhui.subtract(const Duration(days: 10))),
        initialQuantity: const Value(50),
        currentQuantity: const Value(47),
      ),
    );
    await db.into(db.livestockDailyEntries).insert(
      LivestockDailyEntriesCompanion.insert(
        id: 'ffffffff-9999-4999-8999-ffffffffffff',
        deviceId: 'poste-test',
        updatedAt: aujourdhui,
        lotId: bandeId,
        entryDate: DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day),
        mort: const Value(3),
        effectifFinal: const Value(47),
      ),
    );
  }

  Future<void> afficherEtEnregistrer(WidgetTester tester, Widget ecran) async {
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ecran));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('morts-enregistres')), findsOneWidget);
    expect(find.textContaining('3 mort(s) déjà enregistré(s) ce jour'), findsOneWidget);

    await tester.ensureVisible(find.text('Enregistrer ce Jour'));
    await tester.tap(find.text('Enregistrer ce Jour'));
    await tester.pumpAndSettle();

    final fiche = await db.select(db.livestockDailyEntries).getSingle();
    // Recalcul indépendant : 50 au départ − 3 morts.
    expect([fiche.mort, fiche.effectifFinal], [3, 47]);
  }

  testWidgets('Pondeuses : les 3 morts du jour survivent au ré-enregistrement', (tester) async {
    await bandeEtFiche(espece: 'aviculture', stade: 'ponte');
    await afficherEtEnregistrer(
      tester,
      FichePondeusesScreen(
        depot: depot,
        soins: soins,
        production: ProductionOeufsService(database: db),
      ),
    );
  });

  testWidgets('Escargots : les 3 morts du jour survivent au ré-enregistrement', (tester) async {
    await bandeEtFiche(espece: 'helico', stade: 'engraissement');
    await afficherEtEnregistrer(tester, FicheEscargotsScreen(depot: depot, soins: soins));
  });

  testWidgets('Reproducteurs : les 3 morts du jour survivent au ré-enregistrement', (tester) async {
    await bandeEtFiche(espece: 'aviculture', stade: 'reproduction');
    await afficherEtEnregistrer(tester, FicheReproducteursScreen(depot: depot, soins: soins));
  });
}
