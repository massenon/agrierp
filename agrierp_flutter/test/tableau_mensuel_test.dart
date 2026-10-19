import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.26 — TABLEAU MENSUEL DE LA FICHE LAPINS, 🔁 ticket U12a : celui du Blade (TOUS les jours du mois, sans
/// invite, « jj/mm », taux sans « % »).
///
/// ⚠️⚠️ **IL MANQUAIT SUR LES CINQ FICHES.** Le poste s'arrêtait au formulaire : l'animalier ne pouvait **ni relire
/// une journée passée ni la corriger** — il ne voyait que le jour courant.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'CUN-2026-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            speciesCode: const Value('cuniculture'),
            createdDate: Value(DateTime.now()),
            initialQuantity: const Value(40),
            currentQuantity: const Value(40),
          ),
        );
  });

  tearDown(() async => db.close());

  final maintenant = HeureBenin.maintenant();
  final joursDuMois = DateTime(maintenant.year, maintenant.month + 1, 0).day;
  String deux(int n) => n.toString().padLeft(2, '0');

  /// Une journée du mois courant, au jour indiqué.
  Future<void> journee(int jour, {int mort = 0, int achat = 0}) async {
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: 'fiche-$jour'.padRight(36, '-'),
            deviceId: 'poste-test',
            updatedAt: maintenant,
            lotId: bandeId,
            entryDate: DateTime(maintenant.year, maintenant.month, jour),
            achat: Value(achat),
            mort: Value(mort),
            effectifFinal: Value(40 + achat - mort),
          ),
        );
  }

  /// `hidden lg:block` : le tableau n'existe qu'à partir de 1 024 px, comme au web.
  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FicheLapinsScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder ligne(int index) => find.byKey(Key('ligne-mois-$index'));

  testWidgets('🔁 U12a — sans journée saisie, TOUS les jours du mois sont listés', (tester) async {
    await afficher(tester);

    expect(ligne(joursDuMois - 1), findsOneWidget);
    expect(ligne(joursDuMois), findsNothing);
    expect(find.text('— Aucune journée saisie ce mois-ci —'), findsNothing);
  });

  testWidgets('⚠️ les colonnes du Blade sont toutes présentes', (tester) async {
    await journee(3, mort: 2);
    await afficher(tester);

    // Groupes.
    for (final g in ['ENTRÉES', 'SORTIES', 'EFFECTIF FINAL DU JOUR']) {
      expect(find.text(g), findsOneWidget, reason: g);
    }

    // Colonnes.
    for (final c in [
      'DATE',
      'Achat',
      'Né',
      'Mort',
      'Vente',
      'Don',
      'M',
      'F',
      // Ticket F0.92 : « Sevrés » devient « Jeunes » (décision client du 14/10/2026), comme le Blade.
      'Jeunes',
      'S/Mères',
      'Total',
      'TAUX MORT %',
      'POIDS GÉNÉRAL (G)',
    ]) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
    // La colonne du tableau ET le titre de la section du formulaire (le Blade porte les deux).
    expect(find.text('TRAITEMENTS & PROPHYLAXIE'), findsNWidgets(2));
  });

  testWidgets("🔁 U12a — l'invite de la maquette n'est plus là (absente du Blade)", (tester) async {
    await journee(3);
    await afficher(tester);

    expect(find.text('Touchez un jour pour charger sa fiche dans le formulaire'), findsNothing);
  });

  testWidgets('chaque jour du mois forme une ligne, datée « jj/mm »', (tester) async {
    await journee(3);
    await journee(7);
    await journee(11);

    await afficher(tester);

    for (var j = 0; j < joursDuMois; j++) {
      expect(ligne(j), findsOneWidget);
    }
    expect(find.descendant(of: ligne(6), matching: find.text('07/${deux(maintenant.month)}')), findsOneWidget);
  });

  /// ⚠️⚠️ TOUCHER UNE LIGNE CHARGE LA JOURNÉE (`loadDay`) : c'est la seule façon de revenir sur une saisie de la veille
  /// pour la corriger.
  testWidgets('toucher une ligne charge cette journée dans le formulaire', (tester) async {
    await journee(3, mort: 5);
    await journee(9, mort: 0);

    await afficher(tester);

    await tester.ensureVisible(ligne(2));
    await tester.tap(ligne(2));
    await tester.pumpAndSettle();

    // « Date : » porte désormais le jour choisi.
    expect(
      tester.widget<Text>(find.byKey(const Key('date-choisie'))).data,
      '03/${deux(maintenant.month)}/${maintenant.year}',
    );
  });

  /// ⚠️ Un effectif saisi inconnu (`effectif_m/f/sevres/smeres` nul) affiche un tiret, jamais 0.
  testWidgets('⚠️ les effectifs saisis inconnus affichent un tiret', (tester) async {
    await journee(3, mort: 2);
    await afficher(tester);

    // M, F, Jeunes, S/Mères, Poids Général et Traitements : six tirets sur la ligne.
    expect(find.descendant(of: ligne(2), matching: find.text('—')), findsNWidgets(6));
  });

  testWidgets('le taux de mortalité se calcule sur l effectif de départ', (tester) async {
    // 40 au départ, 2 morts → `number_format(5.0, 1)` = « 5.0 » (sans « % », comme le Blade).
    await journee(3, mort: 2);
    await afficher(tester);

    expect(find.descendant(of: ligne(2), matching: find.text('5.0')), findsOneWidget);
  });
}
