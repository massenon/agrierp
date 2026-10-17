import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/elevage/parametres_elevage_repository.dart';
import 'package:agrierp/features/elevage/parametres_elevage_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.44 — PARAMÈTRES ÉLEVAGE (`parametres-elevage.html`).
///
/// ⚠️⚠️ **CET ÉCRAN NE CRÉE RIEN : IL MONTRE ENFIN LA RÈGLE QUE LE POSTE
/// APPLIQUE DÉJÀ.** Les rations pilotent la provende du Dashboard Élevage
/// depuis le ticket 14.52, le calendrier alimente les traitements prévus de
/// Soins et Vaccins depuis 14.54. L'éleveur voyait les conséquences sans
/// pouvoir consulter la cause.
///
/// ⚠️ **DEUX RÉFÉRENTIELS NE DESCENDAIENT PAS** : les types de provende
/// (`feed_types`, 5 lignes, qui portent le poids du sac) et les préfixes de
/// numérotation (`elevage_numbering_settings`, table à une ligne, qui nomment
/// les animaux sur le terrain). Ticket 14.77.
void main() {
  late AppDatabase db;
  late ParametresElevageRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ParametresElevageRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> ration(
    String cle, {
    required String espece,
    required String stade,
    required double grammes,
  }) => db
      .into(db.feedRationStandards)
      .insert(
        FeedRationStandardsCompanion.insert(
          id: uuid(cle),
          speciesCode: espece,
          stageLabel: stade,
          rationGPerDay: grammes,
        ),
      );

  Future<void> prophylaxie(
    String cle, {
    required String espece,
    required String periode,
    required String traitement,
    int? jourDebut,
    String? produit,
    String? posologie,
    int remanence = 0,
  }) => db
      .into(db.prophylaxisScheduleStandards)
      .insert(
        ProphylaxisScheduleStandardsCompanion.insert(
          id: uuid(cle),
          speciesCode: espece,
          periodLabel: periode,
          treatment: traitement,
          cycleDayStart: Value(jourDebut),
          cycleDayEnd: Value(jourDebut),
          productRecommended: Value(produit),
          dosage: Value(posologie),
          withdrawalDays: Value(remanence),
        ),
      );

  Future<void> provende(
    String cle, {
    required String nom,
    String? espece,
    double? sacKg,
    double? prixKg,
  }) => db
      .into(db.feedTypes)
      .insert(
        FeedTypesCompanion.insert(
          id: uuid(cle),
          name: nom,
          speciesLabel: Value(espece),
          standardBagWeightKg: Value(sacKg),
          pricePerKg: Value(prixKg),
        ),
      );

  Future<void> numerotation() => db
      .into(db.elevageNumberingSettings)
      .insert(
        ElevageNumberingSettingsCompanion.insert(
          bandeFormat: const Value('BANDE B'),
          lapinePrefix: const Value('R'),
          malePrefix: const Value('M'),
          truiePrefix: const Value('T'),
          verratPrefix: const Value('V'),
          porteePrefix: const Value('P'),
          volaillePrefix: const Value('LOT-VOL'),
          parcPrefix: const Value('PARC'),
          escargotPrefix: const Value('FOSSE'),
        ),
      );

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(home: ParametresElevageScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-parametres-$onglet')));
    await tester.pumpAndSettle();
  }

  group('dépôt', () {
    test('les rations se trient par espèce puis par stade', () async {
      await ration(
        'r1',
        espece: 'cuniculture',
        stade: 'Engraissement',
        grammes: 120,
      );
      await ration('r2', espece: 'aviculture', stade: 'Ponte', grammes: 110);
      await ration(
        'r3',
        espece: 'cuniculture',
        stade: 'Allaitement',
        grammes: 250,
      );

      final d = await depot.charger();

      expect(d.rations.map((r) => r.ration.stageLabel), [
        'Ponte',
        'Allaitement',
        'Engraissement',
      ]);
    });

    /// ⚠️ « Le 10e jour » précède « Le 5e jour » dans l'ordre alphabétique :
    /// trier sur le libellé donnerait un calendrier faux.
    test(
      '⚠️ le calendrier se trie sur le jour de cycle, pas sur le libellé',
      () async {
        await prophylaxie(
          'p1',
          espece: 'cuniculture',
          periode: 'Le 10e jour',
          traitement: 'Rappel',
          jourDebut: 10,
        );
        await prophylaxie(
          'p2',
          espece: 'cuniculture',
          periode: 'Le 5e jour',
          traitement: 'Vaccination',
          jourDebut: 5,
        );

        final d = await depot.charger();

        expect(
          d
              .prophylaxiePour(EspeceProphylaxie.lapins)
              .map((p) => p.entree.periodLabel),
          ['Le 5e jour', 'Le 10e jour'],
        );
      },
    );

    /// ⚠️ Une entrée calendaire (« Le 1er du mois ») n'a pas de jour de cycle :
    /// le serveur a refusé de la convertir, et elle ne doit jamais passer pour
    /// due aujourd'hui.
    test(
      '⚠️ une entrée sans bornes de cycle est reconnue comme telle',
      () async {
        await prophylaxie(
          'p1',
          espece: 'aviculture',
          periode: 'Le 1er du mois',
          traitement: 'Déparasitage',
        );

        final d = await depot.charger();

        expect(d.prophylaxies.single.porteeParLeCycle, isFalse);
      },
    );

    test('le calendrier se filtre par espèce', () async {
      await prophylaxie(
        'p1',
        espece: 'cuniculture',
        periode: 'J5',
        traitement: 'Vaccination',
      );
      await prophylaxie(
        'p2',
        espece: 'porciculture',
        periode: 'J7',
        traitement: 'Fer injectable',
      );

      final d = await depot.charger();

      expect(d.prophylaxiePour(EspeceProphylaxie.lapins).length, 1);
      expect(d.prophylaxiePour(EspeceProphylaxie.porcs).length, 1);
      expect(d.prophylaxiePour(EspeceProphylaxie.volailles), isEmpty);
    });

    test('le code espèce devient un libellé lisible', () {
      expect(
        ParametresElevageRepository.especeLisible('cuniculture'),
        'Cuniculture',
      );
      expect(
        ParametresElevageRepository.especeLisible('heliciculture'),
        'Héliciculture',
      );
    });

    /// ⚠️ Sans tirage, les préfixes valent `null` — pas « R » par défaut.
    test('⚠️ les préfixes sont nuls tant que rien n a été tiré', () async {
      final d = await depot.charger();

      expect(d.numerotation, isNull);
    });
  });

  group('écran', () {
    testWidgets('⚠️ les quatre onglets de la maquette, dans son ordre', (
      tester,
    ) async {
      await afficher(tester);

      for (final onglet in [
        'Fiche de Rationnement (g/j)',
        'Calendriers de Prophylaxie',
        'Types de Provende',
        'Numérotation Bandes & Sujets',
      ]) {
        expect(find.text(onglet), findsOneWidget, reason: onglet);
      }
    });

    /// ⚠️⚠️ **ZÉRO CARTE EST UN NOMBRE, PAS UNE ABSENCE DE CONTRÔLE** (ticket
    /// F0.54). `parametres-elevage.html` n'en porte aucune : c'est un écran de
    /// référentiels. En rendre une ici serait un ajout silencieux — le genre
    /// que rien d'autre ne verrait.
    testWidgets('⚠️⚠️ l écran ne rend aucune carte, comme la maquette', (
      tester,
    ) async {
      await afficher(tester);

      expect(
        find.byType(CarteKpi),
        findsNWidgets(cartesAttendues('parametres-elevage.html')),
      );
    });

    testWidgets('le rationnement porte les quatre colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      for (final colonne in [
        'ESPÈCE',
        "STADE PHYSIOLOGIQUE / TRANCHE D'ÂGE",
        'RATION NORMATIVE (G / TÊTE / JOUR)',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('une ration descendue du serveur est affichée', (tester) async {
      await ration(
        'r1',
        espece: 'cuniculture',
        stade: 'Lapine allaitante',
        grammes: 250,
      );

      await afficher(tester);

      expect(find.text('Cuniculture'), findsOneWidget);
      expect(find.text('Lapine allaitante'), findsOneWidget);
      expect(find.text('250 g'), findsOneWidget);
    });

    testWidgets('la prophylaxie porte les six colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Calendriers de Prophylaxie');

      for (final colonne in [
        'JOUR / PÉRIODE',
        'TRAITEMENT PRÉVU',
        'PRODUIT CONSEILLÉ',
        'POSOLOGIE',
        'DÉLAI RÉMANENCE',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('les trois sous-onglets d espèce sont ceux de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Calendriers de Prophylaxie');

      expect(find.text('🐰 Cuniculture (Lapins)'), findsOneWidget);
      expect(find.text('🐔 Aviculture (Volailles)'), findsOneWidget);
      expect(find.text('🐖 Porciculture (Porcs)'), findsOneWidget);
    });

    testWidgets('changer d espèce change le calendrier affiché', (
      tester,
    ) async {
      await prophylaxie(
        'p1',
        espece: 'cuniculture',
        periode: 'J5 — Lapereaux',
        traitement: 'Vitamines',
      );
      await prophylaxie(
        'p2',
        espece: 'porciculture',
        periode: 'J7 — Porcelets',
        traitement: 'Fer injectable',
      );

      await afficher(tester);
      await ouvrir(tester, 'Calendriers de Prophylaxie');

      expect(find.text('Vitamines'), findsOneWidget);
      expect(find.text('Fer injectable'), findsNothing);

      await tester.tap(find.byKey(const Key('espece-porcs')));
      await tester.pumpAndSettle();

      expect(find.text('Fer injectable'), findsOneWidget);
      expect(find.text('Vitamines'), findsNothing);
    });

    /// ⚠️⚠️ ZÉRO JOUR DE RÉMANENCE SE DIT. Une vitamine sans délai d'attente
    /// autorise la vente le jour même : le confondre avec une donnée absente
    /// ferait hésiter l'éleveur sur une bande pourtant vendable.
    testWidgets('⚠️⚠️ un délai de rémanence nul s affiche « 0 j »', (
      tester,
    ) async {
      await prophylaxie(
        'p1',
        espece: 'cuniculture',
        periode: 'J5',
        traitement: 'Vitamines',
        remanence: 0,
      );
      await prophylaxie(
        'p2',
        espece: 'cuniculture',
        periode: 'J20',
        traitement: 'Antibiotique',
        jourDebut: 20,
        remanence: 7,
      );

      await afficher(tester);
      await ouvrir(tester, 'Calendriers de Prophylaxie');

      expect(find.text('0 j'), findsOneWidget);
      expect(find.text('7 j'), findsOneWidget);
    });

    testWidgets('la provende porte les cinq colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Types de Provende');

      for (final colonne in [
        "NOM DU TYPE D'ALIMENT",
        'ESPÈCE CIBLE',
        'POIDS SAC STANDARD (KG)',
        'PRIX INDICATIF (FCFA / KG)',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    /// ⚠️⚠️ LE POIDS DU SAC EXISTE ICI — et c'est justement ce qui manque au
    /// Dashboard Élevage pour calculer l'autonomie alimentaire. Ce test fige
    /// la donnée : le jour où le lien produit ↔ type sera créé, elle sera là.
    testWidgets('⚠️⚠️ le poids du sac descend avec le type d aliment', (
      tester,
    ) async {
      await provende(
        't1',
        nom: 'Aliment Ponte (Pondeuse)',
        espece: 'Aviculture (Volailles)',
        sacKg: 25,
        prixKg: 260,
      );

      await afficher(tester);
      await ouvrir(tester, 'Types de Provende');

      expect(find.text('Aliment Ponte (Pondeuse)'), findsOneWidget);
      expect(find.text('Aviculture (Volailles)'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('260'), findsOneWidget);
    });

    testWidgets('les préfixes descendus sont affichés avec leur aperçu', (
      tester,
    ) async {
      await numerotation();

      await afficher(tester);
      await ouvrir(tester, 'Numérotation Bandes & Sujets');

      expect(find.byKey(const Key('grille-numerotation')), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
      expect(find.text('LOT-VOL'), findsOneWidget);
      expect(find.text('Aperçu : R1, R2, R3...'), findsOneWidget);
      expect(
        find.text('Aperçu : BANDE B1, BANDE B2, BANDE B3...'),
        findsOneWidget,
      );
      expect(find.text('Aperçu : FOSSE F1, FOSSE F2...'), findsOneWidget);
    });

    testWidgets('les quatre espèces ont leur bloc de numérotation', (
      tester,
    ) async {
      await numerotation();

      await afficher(tester);
      await ouvrir(tester, 'Numérotation Bandes & Sujets');

      for (final groupe in [
        'CUNICULTURE (LAPINS)',
        'PORCICULTURE (PORCS)',
        'AVICULTURE (VOLAILLES & PONDEUSES)',
        'HÉLICICULTURE (ESCARGOTS)',
      ]) {
        expect(find.text(groupe), findsOneWidget, reason: groupe);
      }
    });

    /// ⚠️ Sans tirage, on ne montre pas « R » : on dit qu'on ne sait pas.
    testWidgets('⚠️ sans tirage, les préfixes portent leur motif', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Numérotation Bandes & Sujets');

      expect(find.byKey(const Key('grille-numerotation')), findsNothing);
      expect(find.textContaining('Préfixes non synchronisés'), findsOneWidget);
    });

    /// ⚠️⚠️ LES QUATRE ONGLETS SONT EN LECTURE SEULE, et l'écran le dit.
    testWidgets(
      '⚠️⚠️ chaque onglet dit que la modification se fait sur le web',
      (tester) async {
        await afficher(tester);

        for (final onglet in [
          'Fiche de Rationnement (g/j)',
          'Calendriers de Prophylaxie',
          'Types de Provende',
          'Numérotation Bandes & Sujets',
        ]) {
          await ouvrir(tester, onglet);
          expect(
            find.byKey(const Key('mention-referentiel')),
            findsOneWidget,
            reason: onglet,
          );
        }
      },
    );

    testWidgets('sans donnée, chaque tableau le dit', (tester) async {
      await afficher(tester);
      expect(find.text('— Aucune ration synchronisée —'), findsOneWidget);

      await ouvrir(tester, 'Calendriers de Prophylaxie');
      expect(
        find.text('— Aucune échéance pour cette espèce —'),
        findsOneWidget,
      );

      await ouvrir(tester, 'Types de Provende');
      expect(
        find.text('— Aucun type de provende synchronisé —'),
        findsOneWidget,
      );
    });
  });
}
