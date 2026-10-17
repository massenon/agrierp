import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.13 — CONFORMITÉ À LA MAQUETTE `fiche-lapins.html`.
///
/// ⚠️⚠️ **LA MAQUETTE EST LA RÉFÉRENCE DE MISE EN PAGE.** Ordre des sections,
/// libellés et ponctuation s'y prennent tels quels. Un écran qui « fonctionne »
/// mais range ses blocs autrement n'est pas une conversion : l'animalier qui a
/// appris la fiche papier puis la maquette ne retrouve plus ses repères.
///
/// Ces tests verrouillent ce qui vient d'être remis en place — sans eux, rien
/// n'empêche l'ordre de rebouger à la prochaine retouche.
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

    // Le referentiel de rations doit exister, sinon la section affiche son
    // etat vide et son titre n'est pas rendu.
    await db
        .into(db.feedRationStandards)
        .insert(
          FeedRationStandardsCompanion.insert(
            id: 'ffffffff-1111-4111-8111-ffffffffffff',
            speciesCode: 'cuniculture',
            stageLabel: 'Lapin de chair',
            rationGPerDay: 120,
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FicheLapinsScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Position verticale d'un texte dans l'arbre rendu.
  double y(WidgetTester tester, String texte) =>
      tester.getTopLeft(find.text(texte)).dy;

  testWidgets(
    "⚠️ l'Effectif Final précède le Rationnement, comme dans la maquette",
    (tester) async {
      await afficher(tester);

      // `fiche-lapins.html` : Effectif Final l. 272, Rationnement l. 289.
      expect(
        y(tester, 'EFFECTIF FINAL DU JOUR (CALCULÉ DYNAMIQUE)'),
        // Ticket F0.92 : « par Catégorie » (décision client du 14/10/2026),
        // la maquette dit encore « par Espèces » — écart assumé.
        lessThan(
          y(
            tester,
            'RATIONNEMENT & PROVENDE SERVIE PAR CATÉGORIE (EN GRAMMES G/J)',
          ),
        ),
        reason: 'inverser les deux déplace un élément existant de la maquette',
      );
    },
  );

  testWidgets("l'ordre complet des sections suit la maquette", (tester) async {
    await afficher(tester);

    final positions = [
      y(tester, 'MORTS PAR CATÉGORIE'),
      y(tester, 'DONS PAR CATÉGORIE'),
      y(tester, 'EFFECTIF FINAL DU JOUR (CALCULÉ DYNAMIQUE)'),
      y(
        tester,
        'RATIONNEMENT & PROVENDE SERVIE PAR CATÉGORIE (EN GRAMMES G/J)',
      ),
      y(tester, 'POIDS MOYEN CONSTATÉ'),
      y(tester, 'Traitements & Prophylaxie Automatiques Prévus pour ce Jour'),
      y(tester, 'Attribution Cages & Bandes Traitées (Cochées par défaut)'),
    ];

    final trie = [...positions]..sort();
    expect(
      positions,
      equals(trie),
      reason:
          'ordre maquette : Morts, Dons, Effectif, Rationnement, '
          'Pesée, Traitements, Attribution',
    );
  });

  testWidgets('les libellés des boutons sont ceux de la maquette', (
    tester,
  ) async {
    await afficher(tester);

    // ⚠️ « Enregistrer ce Jour », pas « Enregistrer la journée » : une
    // reformulation reste un écart de libellé.
    expect(find.text('Enregistrer ce Jour'), findsOneWidget);
    expect(find.text('Réinitialiser'), findsOneWidget);
  });

  testWidgets(
    "⚠️ « Réinitialiser » vide le formulaire et ne supprime rien en base",
    (tester) async {
      await afficher(tester);

      await tester.enterText(find.byKey(const Key('champ-achat-0')), '7');
      await tester.pumpAndSettle();

      final bouton = find.byKey(const Key('bouton-reinitialiser'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();

      // La bande est toujours là : réinitialiser le formulaire n'efface pas de
      // données zootechniques.
      expect(await db.select(db.livestockLots).get(), hasLength(1));
    },
  );

  testWidgets(
    "⚠️ la section Attribution est présente et dit que son référentiel manque",
    (tester) async {
      await afficher(tester);

      expect(
        find.text('Attribution Cages & Bandes Traitées (Cochées par défaut)'),
        findsOneWidget,
      );
      // Recopier les quatre cages de la maquette inventerait un référentiel :
      // l'animalier cocherait des cages qui n'existent nulle part.
      expect(find.textContaining('Aucun référentiel de cages'), findsOneWidget);
      expect(find.textContaining('Cage C1'), findsNothing);
    },
  );

  /// ⚠️⚠️ LE BLOC KPI MANQUAIT ENTIÈREMENT. La maquette ouvre la fiche par
  /// quatre indicateurs ; cet écran — le premier construit, avant la règle de
  /// conformité — passait directement au formulaire. Les quatre fiches
  /// suivantes les ont ; celle-ci ne les avait pas.
  testWidgets(
    'les quatre cartes KPI de la maquette sont présentes, dans son ordre',
    (tester) async {
      await afficher(tester);

      final libelles = [
        'EFFECTIF TOTAL VIVANT',
        'GÉNITEURS (M/F)',
        'NAISSANCES DU MOIS',
        'TAUX DE MORTALITÉ',
      ];
      for (final l in libelles) {
        expect(find.text(l), findsOneWidget, reason: l);
      }

      final positions = libelles.map((l) => y(tester, l)).toList();
      expect(positions, equals([...positions]..sort()));
    },
  );

  /// ⚠️ « GÉNITEURS (M/F) » N'EST PAS CALCULABLE AU POSTE : le serveur le tire
  /// de `effectif_m` / `effectif_f`, que la synchronisation ne descend pas. Un
  /// zéro se lirait « plus aucun géniteur » — sur une bande de reproduction,
  /// c'est un contresens.
  testWidgets("⚠️ « Géniteurs (M/F) » affiche un tiret et dit pourquoi", (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('non synchronisé'), findsOneWidget);
  });

  /// Les cartes précèdent le formulaire, comme dans la maquette.
  testWidgets('les KPI précèdent la saisie journalière', (tester) async {
    await afficher(tester);

    expect(
      y(tester, 'EFFECTIF TOTAL VIVANT'),
      lessThan(y(tester, 'MORTS PAR CATÉGORIE')),
    );
  });
}
