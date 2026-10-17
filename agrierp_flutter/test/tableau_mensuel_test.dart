import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.26 — TABLEAU MENSUEL DE LA FICHE LAPINS.
///
/// ⚠️⚠️ **IL MANQUAIT SUR LES CINQ FICHES.** La maquette termine chaque fiche
/// par le mois entier, avec ses deux rangées d'en-têtes et l'invite « Touchez un
/// jour pour charger sa fiche dans le formulaire ». Le poste s'arrêtait au
/// formulaire : l'animalier ne pouvait **ni relire une journée passée ni la
/// corriger** — il ne voyait que le jour courant.
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

  /// Une journée du mois courant, au jour indiqué.
  Future<void> journee(int jour, {int mort = 0, int achat = 0}) async {
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
            achat: Value(achat),
            mort: Value(mort),
            effectifFinal: Value(40 + achat - mort),
          ),
        );
  }

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FicheLapinsScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sans journée saisie, le tableau le dit', (tester) async {
    await afficher(tester);

    expect(find.text('— Aucune journée saisie ce mois-ci —'), findsOneWidget);
  });

  testWidgets('⚠️ les colonnes de la maquette sont toutes présentes', (
    tester,
  ) async {
    await journee(3, mort: 2);
    await afficher(tester);

    // Groupes.
    for (final g in ['ENTRÉES', 'SORTIES', 'EFFECTIF FINAL DU JOUR']) {
      expect(find.text(g), findsOneWidget, reason: g);
    }

    // Colonnes.
    for (final c in [
      'DATE',
      'ACHAT',
      'NÉ',
      'MORT',
      'VENTE',
      'DON',
      'M',
      'F',
      // Ticket F0.92 : « Sevrés » devient « Jeunes » (décision client du
      // 14/10/2026) ; la maquette dit encore « Sevrés » — écart assumé.
      'JEUNES',
      'S/MÈRES',
      'TOTAL',
      'TAUX MORT %',
      'POIDS GÉNÉRAL (G)',
      'TRAITEMENTS & PROPHYLAXIE',
    ]) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
  });

  testWidgets("l'invite de la maquette est reprise mot pour mot", (
    tester,
  ) async {
    await journee(3);
    await afficher(tester);

    expect(
      find.text('Touchez un jour pour charger sa fiche dans le formulaire'),
      findsOneWidget,
    );
  });

  testWidgets('chaque journée du mois forme une ligne', (tester) async {
    await journee(3);
    await journee(7);
    await journee(11);

    await afficher(tester);

    expect(find.byKey(const Key('ligne-mois-0')), findsOneWidget);
    expect(find.byKey(const Key('ligne-mois-1')), findsOneWidget);
    expect(find.byKey(const Key('ligne-mois-2')), findsOneWidget);
    expect(find.byKey(const Key('ligne-mois-3')), findsNothing);
  });

  /// ⚠️⚠️ TOUCHER UNE LIGNE CHARGE LA JOURNÉE : c'est la seule façon de revenir
  /// sur une saisie de la veille pour la corriger.
  testWidgets('toucher une ligne charge cette journée dans le formulaire', (
    tester,
  ) async {
    await journee(3, mort: 5);
    await journee(9, mort: 0);

    await afficher(tester);

    final ligne = find.byKey(const Key('ligne-mois-0'));
    await tester.ensureVisible(ligne);
    await tester.tap(ligne);
    await tester.pumpAndSettle();

    // L'en-tête du formulaire porte désormais le jour choisi.
    expect(find.textContaining('Jour 3 ('), findsWidgets);
  });

  /// ⚠️ QUATRE COLONNES NON SYNCHRONISÉES AFFICHENT UN TIRET. Le serveur les
  /// tient dans `effectif_m/f/sevres/smeres` ; le contrat ne les descend pas.
  /// Un zéro se lirait « plus aucun reproducteur ».
  testWidgets('⚠️ les colonnes non synchronisées affichent un tiret', (
    tester,
  ) async {
    await journee(3, mort: 2);
    await afficher(tester);

    // M, F, Jeunes, S/Mères + Traitements = au moins cinq tirets sur la ligne.
    expect(find.text('—'), findsAtLeastNWidgets(5));
  });

  testWidgets('le taux de mortalité se calcule sur l effectif de départ', (
    tester,
  ) async {
    // 40 au départ, 2 morts → 5,0 %.
    await journee(3, mort: 2);
    await afficher(tester);

    expect(find.text('5.0 %'), findsOneWidget);
  });
}
