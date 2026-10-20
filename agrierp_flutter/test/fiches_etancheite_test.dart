import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_escargots_screen.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:agrierp/features/elevage/fiche_pondeuses_screen.dart';
import 'package:agrierp/features/elevage/fiche_porcs_screen.dart';
import 'package:agrierp/features/elevage/fiche_reproducteurs_screen.dart';
import 'package:agrierp/features/elevage/production_oeufs_service.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.22 — ÉTANCHÉITÉ DES CINQ FICHES.
///
/// ⚠️⚠️ **CE QUE LES TESTS PAR ÉCRAN NE PEUVENT PAS VOIR.** Chaque suite d'écran
/// sème SES propres bandes — donc toujours celles qu'elle attend. Aucune ne
/// place les cinq espèces côte à côte, ce qui est pourtant la situation réelle :
/// un poste synchronisé reçoit **toutes** les bandes de l'exploitation.
///
/// Le défaut que cela masquait : la fiche Lapins n'avait **aucun filtre** et
/// listait les bandes porcines et avicoles. Un animalier pouvait saisir des
/// morts « Lapereau » sur une bande de porcs — le bon `lot_id`, les bonnes
/// quantités, la mauvaise espèce, et pas la moindre erreur levée.
///
/// Ce fichier place les cinq espèces dans la même base et vérifie que chaque
/// fiche ne voit **que** la sienne, exactement comme le serveur.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;
  late ProductionOeufsService production;

  /// Une bande par espèce et par stade réellement rencontré en base.
  const bandes = [
    ('lapin-a', 'CUN-01', 'cuniculture', 'engraissement'),
    ('lapin-b', 'CUN-02', 'cuniculture', 'reproduction'),
    ('avi-ponte', 'AVI-01', 'aviculture', 'ponte'),
    ('avi-chair', 'AVI-02', 'aviculture', 'engraissement'),
    ('porc-a', 'POR-01', 'porciculture', 'engraissement'),
    ('escargot', 'HEL-01', 'helico', 'engraissement'),
    // ⚠️ Le piège : un escargot AU STADE PONTE. Filtrer sur le seul stade le
    // ferait apparaître sur la fiche Pondeuses.
    ('escargot-ponte', 'HEL-02', 'helico', 'ponte'),
  ];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
    production = ProductionOeufsService(database: db);

    for (final (cle, code, espece, stade) in bandes) {
      await db
          .into(db.livestockLots)
          .insert(
            LivestockLotsCompanion.insert(
              id: cle.padRight(36, '-'),
              code: code,
              speciesId: 'esp-$espece'.padRight(36, '-'),
              speciesCode: Value(espece),
              stage: Value(stade),
              createdDate: Value(DateTime.now()),
              currentQuantity: const Value(40),
            ),
          );
    }
    // 🔁 U12a — la fiche Escargots suit `ModuleConfig::isEnabled('helico')` du web : module activé ici.
    await db.into(db.modulesConfig).insert(
      ModulesConfigCompanion.insert(
        id: 'dddddddd-1111-4111-8111-dddddddddddd',
        speciesCode: 'helico',
        isEnabled: const Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  /// Codes de bande proposés par un écran, lus dans son sélecteur.
  Future<List<String>> bandesVisibles(WidgetTester tester, Widget ecran) async {
    await tester.pumpWidget(MaterialApp(home: ecran));
    await tester.pumpAndSettle();

    // ⚠️ LA LISTE DEROULANTE N'AFFICHE QUE LA BANDE CHOISIE. Se contenter du
    // texte rendu ne montrerait qu'elle : il faut ouvrir le selecteur pour
    // enumerer ce que l'ecran propose reellement.
    final selecteur = find.byType(DropdownButton<String>);
    if (selecteur.evaluate().isNotEmpty) {
      await tester.ensureVisible(selecteur.first);
      await tester.tap(selecteur.first);
      await tester.pumpAndSettle();
    }

    final codes = <String>[];
    for (final (_, code, _, _) in bandes) {
      // 🔁 U12a — la fiche Reproducteurs affiche « code (Stade — N têtes) », comme le Blade.
      if (find.textContaining(code).evaluate().isNotEmpty) codes.add(code);
    }

    return codes;
  }

  testWidgets('⚠️⚠️ la fiche Lapins ne voit que les bandes cunicoles', (
    tester,
  ) async {
    final visibles = await bandesVisibles(
      tester,
      FicheLapinsScreen(depot: depot, soins: soins),
    );

    expect(visibles, containsAll(['CUN-01', 'CUN-02']));
    expect(
      visibles,
      isNot(contains('POR-01')),
      reason:
          'saisir un « Lapereau » sur une bande de porcs doit être '
          'impossible',
    );
    expect(visibles, isNot(contains('AVI-01')));
    expect(visibles, isNot(contains('HEL-01')));
  });

  testWidgets(
    "⚠️⚠️ la fiche Pondeuses ne voit pas un escargot au stade « ponte »",
    (tester) async {
      final visibles = await bandesVisibles(
        tester,
        FichePondeusesScreen(
          depot: depot,
          soins: soins,
          production: production,
        ),
      );

      expect(
        visibles,
        isNot(contains('HEL-02')),
        reason: 'le stade seul ne distingue pas une ponte d escargots',
      );
      expect(visibles, isNot(contains('CUN-01')));
    },
  );

  testWidgets('la fiche Porcs ne voit que les bandes porcines', (tester) async {
    final visibles = await bandesVisibles(
      tester,
      FichePorcsScreen(depot: depot, soins: soins),
    );

    expect(visibles, isNot(contains('CUN-01')));
    expect(visibles, isNot(contains('AVI-01')));
    expect(visibles, isNot(contains('HEL-01')));
  });

  testWidgets('⚠️ la fiche Reproducteurs voit la chair mais jamais la ponte', (
    tester,
  ) async {
    final visibles = await bandesVisibles(
      tester,
      FicheReproducteursScreen(depot: depot, soins: soins),
    );

    // « Reproducteurs & Goliath » : la chair en fait partie (règle serveur
    // `stage != 'ponte'`).
    expect(visibles, contains('AVI-02'));
    expect(
      visibles,
      isNot(contains('AVI-01')),
      reason: 'la ponte a sa propre fiche',
    );
    expect(visibles, isNot(contains('CUN-01')));
  });

  testWidgets('la fiche Escargots ne voit que les bandes hélicicoles', (
    tester,
  ) async {
    final visibles = await bandesVisibles(
      tester,
      FicheEscargotsScreen(depot: depot, soins: soins),
    );

    expect(visibles, containsAll(['HEL-01', 'HEL-02']));
    expect(visibles, isNot(contains('CUN-01')));
    expect(visibles, isNot(contains('POR-01')));
  });
}
