import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_pondeuses_screen.dart';
import 'package:agrierp/features/elevage/production_oeufs_service.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.27 — TABLEAU MENSUEL DE LA FICHE PONDEUSES.
///
/// ⚠️⚠️ **LES QUATRE COLONNES DU GRAND LIVRE D'ŒUFS AFFICHENT UN TIRET.** SRH,
/// TS, OS et Stock Final sont reconstruits par `EggStockLedgerService` depuis
/// l'historique réel de `stock_movements` — une table que le poste ne reçoit
/// pas. Les calculer sur le seul solde courant donnerait un « stock reporté »
/// qui ne reporte rien : c'est exactement le défaut corrigé côté serveur au
/// ticket 14.13. Mieux vaut la colonne vide que le chiffre faux.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;
  late ProductionOeufsService production;

  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
    production = ProductionOeufsService(database: db);

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'AVI-PON-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            speciesCode: const Value('aviculture'),
            stage: const Value('ponte'),
            createdDate: Value(DateTime.now()),
            initialQuantity: const Value(480),
            currentQuantity: const Value(480),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> journee(
    int jour, {
    int mort = 0,
    int recoltes = 0,
    int casses = 0,
    int effectif = 480,
  }) async {
    final maintenant = DateTime.now();
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: 'fiche-$jour'.padRight(36, '-'),
            deviceId: 'poste-test',
            updatedAt: maintenant,
            lotId: bandeId,
            entryDate: DateTime(maintenant.year, maintenant.month, jour),
            mort: Value(mort),
            effectifFinal: Value(effectif),
            ponteTotal: Value(recoltes),
            ponteCasses: Value(casses),
          ),
        );
  }

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FichePondeusesScreen(
          depot: depot,
          soins: soins,
          production: production,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ les groupes de la maquette sont présents', (tester) async {
    await journee(4, recoltes: 435, casses: 15);
    await afficher(tester);

    for (final g in [
      'CHEPTEL DU JOUR',
      'SUIVI DE LA PONTE & RÉCOLTE',
      'STOCK ŒUFS & PLATEAUX (30)',
    ]) {
      expect(find.text(g), findsOneWidget, reason: g);
    }
  });

  testWidgets('toutes les colonnes de la maquette sont là', (tester) async {
    await journee(4, recoltes: 435, casses: 15);
    await afficher(tester);

    for (final c in [
      'EFF. DÉBUT',
      'MORTS',
      'TAUX MORT %',
      'EFF. FIN',
      'TOTAL (OR)',
      'TAUX PONTE %',
      'CASSÉS (OF)',
      'COMM. (OR-OF)',
      'STOCK HIER (SRH)',
      'TOTAL STOCK (TS)',
      'SORTIE VENTE (OS)',
      'STOCK FINAL',
      'TRAITEMENTS & RAPPELS',
    ]) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
  });

  /// ⚠️ Les valeurs sont calculées avec les mêmes formules que le formulaire :
  /// 435 − 15 = 420 commercialisables.
  testWidgets('la ligne porte les valeurs de la ponte du jour', (tester) async {
    await journee(4, recoltes: 435, casses: 15);
    await afficher(tester);

    expect(find.text('435'), findsWidgets);
    expect(find.text('420'), findsWidgets);
  });

  testWidgets(
    '⚠️⚠️ le grand livre d œufs affiche un tiret, jamais un chiffre faux',
    (tester) async {
      await journee(4, recoltes: 435, casses: 15);
      await afficher(tester);

      // SRH, TS, OS, Stock Final, Traitements : au moins cinq tirets.
      expect(find.text('—'), findsAtLeastNWidgets(5));
    },
  );

  testWidgets('toucher une ligne charge cette journée', (tester) async {
    await journee(4, recoltes: 100);
    await journee(9, recoltes: 200);

    await afficher(tester);

    final ligne = find.byKey(const Key('ligne-mois-0'));
    await tester.ensureVisible(ligne);
    await tester.tap(ligne);
    await tester.pumpAndSettle();

    expect(find.textContaining('Jour 4 ('), findsWidgets);
  });

  testWidgets('sans journée saisie, le tableau le dit', (tester) async {
    await afficher(tester);

    expect(find.text('— Aucune journée saisie ce mois-ci —'), findsOneWidget);
  });
}
