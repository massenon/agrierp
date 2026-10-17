import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_porcs_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.28 — TABLEAU MENSUEL DE LA FICHE PORCS.
///
/// ⚠️⚠️ **LA COLONNE DE POIDS EST EN KILOS, seule fiche à cette échelle.** La
/// base stocke la MOYENNE par sujet en grammes (`weight_sample_avg_g`, colonne
/// commune aux cinq fiches) ; la maquette annonce le TOTAL pesé en kilos. La
/// reconstitution `moyenne × effectif ÷ 1000` est exactement l'aller-retour
/// corrigé côté serveur au ticket 14.60 — recopier la moyenne afficherait 45
/// là où 540 Kg ont été pesés.
///
/// ⚠️ **TRUIES GEST. / VERRATS / PORCELETS / ENGRAISS. AFFICHENT UN TIRET** :
/// le serveur les tient dans `effectif_f`, `effectif_m`, `effectif_sevres` et
/// `effectif_smeres`, que le contrat de synchronisation ne descend pas.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'cccccccc-1111-4111-8111-cccccccccccc';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'POR-ENG-01',
            speciesId: 'ffffffff-1111-4111-8111-ffffffffffff',
            speciesCode: const Value('porciculture'),
            stage: const Value('engraissement'),
            createdDate: Value(DateTime.now()),
            initialQuantity: const Value(12),
            currentQuantity: const Value(12),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> journee(
    int jour, {
    int achat = 0,
    int ne = 0,
    int mort = 0,
    int vente = 0,
    int don = 0,
    int effectif = 12,
    double? moyenneG,
  }) async {
    final maintenant = DateTime.now();
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: 'fiche-porc-$jour'.padRight(36, '-'),
            deviceId: 'poste-test',
            updatedAt: maintenant,
            lotId: bandeId,
            entryDate: DateTime(maintenant.year, maintenant.month, jour),
            achat: Value(achat),
            ne: Value(ne),
            mort: Value(mort),
            vente: Value(vente),
            don: Value(don),
            effectifFinal: Value(effectif),
            weightSampleAvgG: Value(moyenneG),
          ),
        );
  }

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FichePorcsScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ les groupes de la maquette sont présents', (tester) async {
    await journee(6, ne: 2);
    await afficher(tester);

    for (final g in ['ENTRÉES', 'SORTIES', 'EFFECTIF FINAL DU JOUR']) {
      expect(find.text(g), findsOneWidget, reason: g);
    }
  });

  testWidgets('toutes les colonnes du web sont là (sous-colonnes en casse mixte, 15.57)', (tester) async {
    await journee(6, ne: 2);
    await afficher(tester);

    for (final c in [
      'DATE',
      'Achat',
      'Né',
      'Mort',
      'Vente',
      'Don',
      'Truies Gest.',
      'Verrats',
      'Porcelets',
      'Engraiss.',
      'Total',
      'TAUX MORT %',
      'POIDS GÉNÉRAL (KG)',
      'TRAITEMENTS & PROPHYLAXIE',
    ]) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
  });

  /// ⚠️⚠️ LE CŒUR DU TICKET : 45 000 g de moyenne × 12 sujets = 540,0 Kg.
  /// Afficher « 45,0 » serait la moyenne prise pour un total.
  testWidgets('la pesée se reconstitue en kilos, pas en moyenne', (
    tester,
  ) async {
    await journee(6, effectif: 12, moyenneG: 45000);
    await afficher(tester);

    expect(find.text('540.0'), findsOneWidget);
    expect(find.text('45.0'), findsNothing);
  });

  /// ⚠️ SANS PESÉE, LA CELLULE PORTE UN TIRET, jamais « 0.0 » : un zéro se
  /// lirait comme un cheptel pesé à vide. La ligne compte alors six tirets —
  /// les quatre catégories, le poids, le suivi clinique. Le « 0.0 » restant
  /// est le taux de mortalité, qui lui vaut bien zéro.
  testWidgets('sans pesée, la colonne poids reste vide et non nulle', (
    tester,
  ) async {
    await journee(6, effectif: 12);
    await afficher(tester);

    final ligne = find.byKey(const Key('ligne-mois-0'));
    expect(
      find.descendant(of: ligne, matching: find.text('—')),
      findsNWidgets(6),
    );
  });

  testWidgets(
    '⚠️⚠️ les quatre catégories non synchronisées affichent un tiret',
    (tester) async {
      await journee(6, effectif: 12, moyenneG: 45000);
      await afficher(tester);

      // Truies Gest., Verrats, Porcelets, Engraiss. + Suivi Clinique — la
      // colonne poids, elle, est renseignée.
      final ligne = find.byKey(const Key('ligne-mois-0'));
      expect(
        find.descendant(of: ligne, matching: find.text('—')),
        findsNWidgets(5),
      );
    },
  );

  testWidgets(
    'le taux de mortalité du jour se calcule sur l effectif de début',
    (tester) async {
      // 12 fin + 1 mort = 13 au départ → 1/13 = 7,7 %.
      await journee(6, mort: 1, effectif: 12);
      await afficher(tester);

      expect(find.text('7.7'), findsOneWidget);
    },
  );

  testWidgets('toucher une ligne charge cette journée', (tester) async {
    await journee(6);
    await journee(11);

    await afficher(tester);

    final ligne = find.byKey(const Key('ligne-mois-0'));
    await tester.ensureVisible(ligne);
    await tester.tap(ligne);
    await tester.pumpAndSettle();

    expect(find.textContaining('Jour 6 ('), findsWidgets);
  });

  testWidgets('sans journée saisie, le tableau le dit', (tester) async {
    await afficher(tester);

    expect(find.text('— Aucune journée saisie ce mois-ci —'), findsOneWidget);
  });
}
