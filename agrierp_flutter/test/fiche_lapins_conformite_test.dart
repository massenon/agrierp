import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.13 — CONFORMITÉ À LA MAQUETTE `fiche-lapins.html`, 🔁 ticket U12a : au BLADE (`fiche-lapins.blade.php`).
///
/// ⚠️⚠️ **LE BLADE EST LA RÉFÉRENCE DE MISE EN PAGE** (doctrine, article 5). Ordre des sections,
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

  /// 🔁 Ticket U12a — l'ordre des sections est celui du Blade (`fiche-lapins.blade.php`) ; « Attribution Cages… » et
  /// « Réinitialiser », absents du Blade, sont retirés.
  testWidgets("l'ordre complet des sections suit le Blade", (tester) async {
    await afficher(tester);

    final positions = [
      y(tester, 'Saisie Journalière du Cheptel'),
      y(tester, 'MORTS PAR CATÉGORIE'),
      y(tester, 'DONS PAR CATÉGORIE'),
      y(tester, 'SEVRAGE DU JOUR (SOUS-MÈRES → JEUNE)'),
      y(tester, 'EFFECTIF DE DÉPART PAR CATÉGORIE (DÉDUIT DU STADE DE LA BANDE)'),
      y(tester, 'EFFECTIF MÂLES'),
      y(tester, 'EFFECTIF FINAL DU JOUR (CALCULÉ DYNAMIQUE)'),
      y(tester, 'RATIONNEMENT & PROVENDE SERVIE PAR CATÉGORIE (EN GRAMMES G/J)'),
      y(tester, 'POIDS MOYEN CONSTATÉ'),
      y(tester, 'TRAITEMENTS & PROPHYLAXIE'),
      y(tester, 'OBSERVATIONS / NOTES ADDITIONNELLES'),
      y(tester, 'Enregistrer ce Jour'),
    ];

    final trie = [...positions]..sort();
    expect(positions, equals(trie), reason: 'ordre du Blade');
  });

  testWidgets('les libellés des boutons sont ceux du Blade, sans « Réinitialiser »', (tester) async {
    await afficher(tester);

    // ⚠️ « Enregistrer ce Jour », pas « Enregistrer la journée » : une reformulation reste un écart de libellé.
    expect(find.text('Enregistrer ce Jour'), findsOneWidget);
    expect(find.text('Exporter PDF'), findsOneWidget);
    expect(find.text('Réinitialiser'), findsNothing);
  });

  testWidgets('⚠️ la section Attribution de la maquette n est plus rendue (absente du Blade)', (tester) async {
    await afficher(tester);

    expect(find.textContaining('Attribution Cages'), findsNothing);
    expect(find.textContaining('Cage C1'), findsNothing);
  });

  /// Le bloc KPI ouvre la fiche, comme au Blade : quatre indicateurs, dans son ordre.
  testWidgets(
    'les quatre cartes KPI du Blade sont présentes, dans son ordre',
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

      final positions = libelles.map((l) => tester.getTopLeft(find.text(l)).dx).toList();
      expect(positions, equals([...positions]..sort()));
    },
  );

  /// 🔁 Ticket U12a — « Géniteurs (M/F) » se calcule au poste comme au web (Σ `effectif_m` / Σ `effectif_f` de la
  /// DERNIÈRE fiche de chaque bande) : les deux colonnes sont synchronisées depuis 15.57. Sans fiche : « 0 / 0 ».
  testWidgets('« Géniteurs (M/F) » : la somme des effectifs saisis, comme au web', (tester) async {
    await afficher(tester);

    expect(
      find.descendant(of: find.byKey(const Key('kpi-Géniteurs (M/F)')), matching: find.text('0 / 0')),
      findsOneWidget,
    );
    expect(find.text('non synchronisé'), findsNothing);
  });

  /// Les cartes précèdent le formulaire, comme dans le Blade.
  testWidgets('les KPI précèdent la saisie journalière', (tester) async {
    await afficher(tester);

    expect(
      y(tester, 'EFFECTIF TOTAL VIVANT'),
      lessThan(y(tester, 'MORTS PAR CATÉGORIE')),
    );
  });
}
