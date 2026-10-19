import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/elevage/fiche_escargots_screen.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.17 — FICHE ESCARGOTS (`fiche-escargots.html`), 🔁 ticket U12a : mise en page du Blade
/// (`fiche-escargots.blade.php`).
///
/// ⚠️⚠️ Deux singularités de cette fiche.
///
/// 1. **Aucun barème de ration n'existe pour l'héliciculture** : la section reste en attente (`x-module-pending`),
///    jamais un tableau à zéro — qui se lirait « aucune provende à servir ».
/// 2. **La maquette portait deux champs « Naissains Nés »** dont un seul alimentait l'effectif ; le Blade n'en a qu'un
///    (« Naissains Nés (Éclosion) ») : le poste aussi.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

  Future<void> bande({
    String? codeEspece = 'helico',
    int effectif = 2000,
  }) async {
    await db
        .into(db.livestockLots)
        .insertOnConflictUpdate(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'HEL-2026-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            speciesCode: Value(codeEspece),
            stage: const Value('engraissement'),
            createdDate: Value(HeureBenin.maintenant()),
            initialQuantity: Value(effectif),
            currentQuantity: Value(effectif),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');

    await bande();
    // `ModuleConfig::isEnabled('helico')` : éteint par défaut, la fiche n'affiche alors que sa carte « non activé ».
    await db.into(db.modulesConfig).insert(
      ModulesConfigCompanion.insert(
        id: 'dddddddd-1111-4111-8111-dddddddddddd',
        speciesCode: 'helico',
        isEnabled: const Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FicheEscargotsScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String texte) => tester.getTopLeft(find.text(texte)).dy;

  String? lecture(WidgetTester tester, String cle) => tester.widget<Text>(find.byKey(Key('champ-$cle'))).data;

  Future<void> saisir(WidgetTester tester, String cle, String valeur) async {
    await tester.ensureVisible(find.byKey(Key('champ-$cle')));
    await tester.enterText(find.byKey(Key('champ-$cle')), valeur);
    await tester.pumpAndSettle();
  }

  String effectif(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('effectif-final'))).data!;

  // ── Conformité au Blade (ticket U12a) ──────────────────────────────────

  testWidgets('les quatre cartes KPI sont celles du Blade, dans son ordre', (tester) async {
    await afficher(tester);

    final libelles = [
      'EFFECTIF TOTAL VIVANT',
      'NAISSAINS NÉS (MOIS)',
      "TAUX D'ÉCLOSION NAISSAINS",
      'TAUX DE MORTALITÉ',
    ];
    for (final l in libelles) {
      expect(find.text(l), findsOneWidget, reason: l);
    }

    final positions = libelles.map((l) => y(tester, l)).toList();
    expect(positions, equals([...positions]..sort()));
  });

  testWidgets("⚠️ l'ordre des sections suit le Blade", (tester) async {
    await afficher(tester);

    final positions = [
      y(tester, 'Saisie Journalière du Cheptel'),
      y(tester, 'ACHATS DU JOUR'),
      y(tester, 'ŒUFS PONDUS (EN TERRE)'),
      y(tester, 'MORTS PAR CATÉGORIE'),
      y(tester, 'DONS PAR CATÉGORIE'),
      y(tester, 'BORDÉS'),
      y(tester, 'EFFECTIF FINAL DU JOUR'),
      y(tester, 'RATIONNEMENT FARINE CALCIQUE & FOURRAGE'),
      y(tester, 'POIDS MOYEN CONSTATÉ'),
      y(tester, 'ENTRETIEN & HYGROMÉTRIE'),
      y(tester, 'OBSERVATIONS'),
      y(tester, 'Enregistrer ce Jour'),
    ];

    expect(positions, equals([...positions]..sort()), reason: 'ordre du Blade');
  });

  // 🔁 F0.99 — catégories des morts du WEB (`fiche-escargots.blade.php`), Dons sur les mêmes catégories (15.56).
  testWidgets('les trois catégories du web portent les morts ET les dons', (tester) async {
    await afficher(tester);

    for (final categorie in ['REPRODUCTEUR (BORDÉ)', 'NAISSAIN']) {
      expect(find.text(categorie), findsNWidgets(2), reason: '$categorie : Morts et Dons');
    }
    // + la saisie « Engraissement » des effectifs (15.57).
    expect(find.text('ENGRAISSEMENT'), findsNWidgets(3));
    expect(find.text('DONS PAR CATÉGORIE'), findsOneWidget);
  });

  // ── Le barème manquant ─────────────────────────────────────────────────

  testWidgets("⚠️⚠️ sans barème hélicicole, la section d'attente du Blade et non un tableau à zéro", (tester) async {
    await afficher(tester);

    expect(
      find.text('Le calcul du rationnement sera alimenté en données réelles dès sa mise en œuvre.'),
      findsOneWidget,
    );
    // Un tableau à zéro se lirait « aucune provende à servir ».
    expect(find.text('Provende Servie (g)'), findsNothing);
  });

  testWidgets('même avec un barème hélicicole, le Blade garde la section en attente', (tester) async {
    await db
        .into(db.feedRationStandards)
        .insert(
          FeedRationStandardsCompanion.insert(
            id: 'ffffffff-1111-4111-8111-ffffffffffff',
            speciesCode: 'helico',
            stageLabel: 'Engraissement',
            rationGPerDay: 2,
          ),
        );

    await afficher(tester);

    // `x-module-pending` sans condition au web : le poste ne calcule pas une provende que le web n'affiche pas.
    expect(find.byKey(const Key('rationnement-en-attente')), findsOneWidget);
    expect(find.text('Provende Servie (g)'), findsNothing);
  });

  // ── Un seul champ « Naissains Nés » (Blade) ────────────────────────────

  testWidgets("⚠️ un seul champ « Naissains Nés » : le second champ de la maquette n'est pas au Blade", (tester) async {
    await afficher(tester);

    expect(find.text('NAISSAINS NÉS (ÉCLOSION)'), findsOneWidget);
    expect(find.text('NAISSAINS NÉS (ÉCLOSION JOUR)'), findsNothing);
  });

  testWidgets("⚠️ les naissains nés augmentent l'effectif final", (tester) async {
    await afficher(tester);

    final avant = effectif(tester);
    await saisir(tester, 'naissains-nes', '150');

    expect(int.parse(effectif(tester)), int.parse(avant) + 150);
  });

  // ── Le taux d'éclosion ─────────────────────────────────────────────────

  testWidgets("sans œuf pondu, le taux d'éclosion du jour vaut « 0,0 % », comme au web", (tester) async {
    await afficher(tester);

    expect(lecture(tester, 'taux-eclosion'), '0,0 %');
  });

  testWidgets('150 naissains de 200 œufs pondus font 75,0 %', (tester) async {
    await afficher(tester);

    await saisir(tester, 'oeufs-terre', '200');
    await saisir(tester, 'naissains-nes', '150');

    expect(lecture(tester, 'taux-eclosion'), '75,0 %');
  });

  // ── Correspondance des colonnes ────────────────────────────────────────

  testWidgets('⚠️⚠️ les œufs pondus vont dans ponteTotal, les naissains dans ne', (tester) async {
    await afficher(tester);

    await saisir(tester, 'oeufs-terre', '200');
    await saisir(tester, 'naissains-nes', '150');

    final bouton = find.byKey(const Key('bouton-enregistrer'));
    await tester.ensureVisible(bouton);
    await tester.tap(bouton);
    await tester.pumpAndSettle();

    final fiche = await depot.chargerJour(bandeId, HeureBenin.maintenant());
    expect(fiche?.ponteTotal, 200, reason: 'les œufs pondus en terre');
    expect(fiche?.ne, 150, reason: 'les naissains nés');
    expect(find.text('Jour enregistré avec succès.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('un mort saisi réduit aussitôt l effectif final', (tester) async {
    await afficher(tester);

    final avant = effectif(tester);
    await tester.ensureVisible(find.byKey(const Key('pas-mort-naissain-1')));
    await tester.tap(find.byKey(const Key('pas-mort-naissain-1')));
    await tester.pumpAndSettle();

    expect(int.parse(effectif(tester)), int.parse(avant) - 1);
  });

  // ── Retirés avec la maquette ───────────────────────────────────────────

  testWidgets('ni « Attribution Parcs », ni protocole du jour, ni « Réinitialiser » (absents du Blade)', (tester) async {
    await afficher(tester);

    expect(find.textContaining('Aucun référentiel de parcs et fosses'), findsNothing);
    expect(find.textContaining('Fosse F1'), findsNothing);
    expect(find.byKey(const Key('prophylaxie-du-jour')), findsNothing);
    expect(find.text('Réinitialiser'), findsNothing);
  });

  testWidgets('sans bande hélicicole, la carte du Blade', (tester) async {
    await bande(codeEspece: 'cuniculture');

    await afficher(tester);

    expect(find.text('Aucune bande active en héliciculture pour le moment.'), findsOneWidget);
  });

  // 🔁 15.56 — un don fait quitter le sujet : l'effectif final baisse aussitôt, comme sur le web.
  testWidgets('un don saisi réduit aussitôt l effectif final', (tester) async {
    await afficher(tester);

    final avant = effectif(tester);
    await tester.ensureVisible(find.byKey(const Key('pas-don-naissain-1')));
    await tester.tap(find.byKey(const Key('pas-don-naissain-1')));
    await tester.pumpAndSettle();

    expect(int.parse(effectif(tester)), int.parse(avant) - 1);
  });
}
