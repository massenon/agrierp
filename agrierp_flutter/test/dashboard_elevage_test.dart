import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/elevage/dashboard_elevage_repository.dart';
import 'package:agrierp/features/elevage/dashboard_elevage_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.33 — DASHBOARD ÉLEVAGE (`prototype_html/elevage-dashboard.html`).
///
/// ⚠️⚠️ **LE GMQ SE CALCULE SUR LES DEUX DERNIÈRES PESÉES**, comme l'écrit le
/// prototype deux fois : en toutes lettres sur l'onglet (« (Poids actuel −
/// Poids précédent) ÷ Jours écoulés ») et dans son JS, qui prend
/// `entries[n-1]` et `entries[n-2]`. `GrowthAnalysisService::gmqCumule()` côté
/// Laravel calcule au contraire un GMQ CUMULÉ depuis la première pesée : pour
/// une même bande, les deux surfaces affichent deux chiffres différents. Le
/// jeu d'essai ci-dessous est construit pour que l'écart soit visible —
/// 14,3 g/j contre 28,6 — et le test échouerait si le poste basculait sur
/// l'autre formule.
void main() {
  late AppDatabase db;
  late DashboardElevageRepository depot;

  const lapins = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
  const volailles = 'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb';
  const porcs = 'cccccccc-0000-4000-8000-cccccccccccc';
  const escargots = 'dddddddd-0000-4000-8000-dddddddddddd';

  /// Les identifiants du poste font exactement 36 caracteres : le jeu d'essai
  /// complete ou tronque, plutot que d'ecrire des UUID a la main.
  ///
  /// ⚠️ LA PARTIE DISCRIMINANTE VIENT EN TETE : la troncature coupe la fin,
  /// et deux graines qui ne different que par leur queue produiraient le meme
  /// identifiant — donc une violation d'unicite au deuxieme insert.
  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final aujourdhui = DateTime.now();
  DateTime ilYA(int jours) =>
      DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day - jours);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = DashboardElevageRepository(
      database: db,
      soins: SoinsRepository(database: db, deviceId: 'poste-test'),
    );

    Future<void> bande(
      String id,
      String code,
      String espece,
      int effectif, {
      String stage = 'engraissement',
      int initial = 100,
    }) {
      return db
          .into(db.livestockLots)
          .insert(
            LivestockLotsCompanion.insert(
              id: id,
              code: code,
              speciesId: 'esp-$espece',
              speciesCode: Value(espece),
              stage: Value(stage),
              initialQuantity: Value(initial),
              currentQuantity: Value(effectif),
            ),
          );
    }

    await bande(lapins, 'CUN-2026-01', 'cuniculture', 65);
    await bande(
      volailles,
      'AVI-2026-01',
      'aviculture',
      310,
      stage: 'ponte',
      initial: 320,
    );
    await bande(porcs, 'POR-2026-01', 'porciculture', 54, initial: 56);
    await bande(escargots, 'HEL-2026-01', 'helico', 1250, initial: 1300);
  });

  tearDown(() async => db.close());

  Future<void> pesee(
    String lot,
    int ilYAJours,
    double poidsG, {
    int mort = 0,
    int effectif = 65,
    int ponte = 0,
  }) async {
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: uuid('$ilYAJours-p-$lot'),
            deviceId: 'poste-test',
            updatedAt: aujourdhui,
            lotId: lot,
            entryDate: ilYA(ilYAJours),
            mort: Value(mort),
            effectifFinal: Value(effectif),
            ponteTotal: Value(ponte),
            weightSampleAvgG: Value(poidsG),
          ),
        );
  }

  Future<void> soin(String lot, String type, double cout) async {
    await db
        .into(db.veterinaryRecords)
        .insert(
          VeterinaryRecordsCompanion.insert(
            id: uuid('$type-s-$lot'),
            deviceId: 'poste-test',
            updatedAt: aujourdhui,
            lotId: lot,
            actionType: type,
            cost: Value(cout),
            recordDate: aujourdhui,
          ),
        );
  }

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: DashboardElevageScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-$onglet')));
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ les cinq onglets de la maquette sont là, dans son ordre', (
    tester,
  ) async {
    await afficher(tester);

    for (final onglet in [
      'Synthèse Globale',
      'GMQ & Croissance',
      'Bilan Technico-Économique',
      'Analyse Sanitaire',
      'Prévision de Croissance',
    ]) {
      expect(find.text(onglet), findsOneWidget, reason: onglet);
    }
  });

  /// ⚠️⚠️ **LE CONTRÔLE SE FAIT PANNEAU PAR PANNEAU, ET C'EST CET ÉCRAN QUI
  /// L'A IMPOSÉ** (ticket F0.54).
  ///
  /// `elevage-dashboard.html` est **une seule page** portant ses cinq panneaux
  /// dans le même document : ses quinze `border-l-4` y coexistent. Contrôlé sur
  /// le TOTAL, l'écran affichait 11 contre 15 — un écart qui ressemblait à
  /// « quatre cartes oubliées ». Le relevé par panneau a montré autre chose :
  /// **−4 sur Bilan, −3 sur Prévision, +3 sur Sanitaire**. Trois écarts
  /// distincts, dont un AJOUT, qui se compensaient presque et qu'une somme
  /// aurait pu masquer entièrement.
  ///
  /// Les trois sont désormais déclarés dans `ecartsPanneaux`, avec leur raison.
  testWidgets('⚠️⚠️ chaque onglet rend le nombre de cartes de son panneau', (
    tester,
  ) async {
    await afficher(tester);

    const panneaux = <String, String>{
      'Synthèse Globale': 'dash-tab-synthese',
      'GMQ & Croissance': 'dash-tab-gmq',
      'Bilan Technico-Économique': 'dash-tab-bilan',
      'Analyse Sanitaire': 'dash-tab-sanitaire',
      'Prévision de Croissance': 'dash-tab-prevision',
    };

    for (final onglet in panneaux.keys) {
      await ouvrir(tester, onglet);

      expect(
        find.byType(CarteKpi),
        findsNWidgets(
          cartesAttenduesPanneau('elevage-dashboard.html', panneaux[onglet]!),
        ),
        reason: onglet,
      );
    }
  });

  testWidgets(
    'les quatre KPI de la synthèse portent les libellés de la maquette',
    (tester) async {
      await afficher(tester);

      for (final libelle in [
        'EFFECTIF TOTAL VIVANT',
        'AUTONOMIE ALIMENT MIN.',
        'GMQ MOYEN',
        'MORTALITÉ CUMULÉE (MOIS)',
      ]) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }

      // 65 + 310 + 54 + 1250.
      expect(find.text('1679'), findsOneWidget);
    },
  );

  /// ⚠️⚠️ L'autonomie alimentaire n'est calculable nulle part : le stock se
  /// compte en sacs et le poids du sac ne vit que dans le NOM du produit.
  testWidgets("l'autonomie alimentaire dit pourquoi elle est absente", (
    tester,
  ) async {
    await afficher(tester);

    expect(
      find.text('Conditionnement (kg/unité) absent du catalogue'),
      findsOneWidget,
    );
  });

  testWidgets('les quatre cartes espèces suivent la maquette', (tester) async {
    await afficher(tester);

    for (final titre in [
      'Cuniculture',
      'Aviculture',
      'Porciculture',
      'Héliciculture',
    ]) {
      expect(find.text(titre), findsWidgets, reason: titre);
    }

    // ⚠️ La deuxième ligne diffère d'une espèce à l'autre — c'est la maquette.
    expect(find.text('Mères / Géniteurs'), findsOneWidget);
    expect(find.text('Taux de ponte'), findsOneWidget);
    expect(find.text('Truies reproductrices'), findsOneWidget);
    expect(find.text("Taux d'éclosion"), findsOneWidget);

    // Autonomie aliment : un tiret sur les quatre cartes.
    expect(find.text('Autonomie aliment'), findsNWidgets(4));
  });

  /// ⚠️⚠️ LE CŒUR DU TICKET. Pesées à J-14 = 500 g, J-7 = 800 g, J-0 = 900 g.
  ///   • formule du prototype (deux dernières)  : (900 − 800) ÷ 7 = 14,3 g/j
  ///   • formule cumulée de Laravel             : (900 − 500) ÷ 14 = 28,6 g/j
  testWidgets('⚠️⚠️ le GMQ se calcule sur les deux dernières pesées', (
    tester,
  ) async {
    await pesee(lapins, 14, 500);
    await pesee(lapins, 7, 800);
    await pesee(lapins, 0, 900);

    await afficher(tester);
    await ouvrir(tester, 'GMQ & Croissance');

    expect(find.text('14.3'), findsOneWidget);
    expect(find.text('28.6'), findsNothing);

    // Le tableau porte bien le poids PRÉCÉDENT, pas le poids initial.
    expect(find.text('800'), findsWidgets);
    expect(find.text('500'), findsNothing);
  });

  testWidgets('le tableau GMQ porte les huit colonnes de la maquette', (
    tester,
  ) async {
    await pesee(lapins, 7, 800);
    await pesee(lapins, 0, 900);

    await afficher(tester);
    await ouvrir(tester, 'GMQ & Croissance');

    for (final colonne in [
      'BANDE',
      'ESPÈCE',
      'DERNIÈRE PESÉE',
      'POIDS PRÉCÉDENT (G)',
      'POIDS ACTUEL (G)',
      'JOURS ÉCOULÉS',
      'GMQ (G/JOUR)',
      'STATUT VS OBJECTIF',
    ]) {
      expect(find.text(colonne), findsOneWidget, reason: colonne);
    }
  });

  /// Objectif cuniculture : 15–20 g/j (table du JS du prototype).
  /// (900 − 800) ÷ 7 = 14,3 → sous objectif.
  testWidgets('le statut compare au barème du prototype', (tester) async {
    await pesee(lapins, 7, 800);
    await pesee(lapins, 0, 900);

    await afficher(tester);
    await ouvrir(tester, 'GMQ & Croissance');

    expect(find.text('Sous objectif'), findsOneWidget);
  });

  /// ⚠️ Le JS du prototype retombe sur `{min:0, max:9999}` pour une espèce
  /// sans barème et affiche « Dans la cible » — un satisfecit délivré sans
  /// objectif. L'héliciculture n'a pas de barème : elle le dit.
  testWidgets("⚠️ une espèce sans barème ne reçoit pas de satisfecit", (
    tester,
  ) async {
    await pesee(escargots, 7, 10, effectif: 1250);
    await pesee(escargots, 0, 12, effectif: 1250);

    await afficher(tester);
    await ouvrir(tester, 'GMQ & Croissance');

    expect(find.text('Sans objectif défini'), findsOneWidget);
    expect(find.text('Dans la cible'), findsNothing);
  });

  testWidgets('le filtre d espèce restreint le tableau', (tester) async {
    await pesee(lapins, 7, 800);
    await pesee(lapins, 0, 900);
    await pesee(porcs, 7, 24000, effectif: 54);
    await pesee(porcs, 0, 26800, effectif: 54);

    await afficher(tester);
    await ouvrir(tester, 'GMQ & Croissance');

    expect(find.text('CUN-2026-01'), findsOneWidget);
    expect(find.text('POR-2026-01'), findsOneWidget);

    await tester.tap(find.byKey(const Key('filtre-espece')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Porciculture (Porcs)').last);
    await tester.pumpAndSettle();

    expect(find.text('CUN-2026-01'), findsNothing);
    expect(find.text('POR-2026-01'), findsOneWidget);
  });

  testWidgets('l analyse sanitaire compte les soins et leur coût', (
    tester,
  ) async {
    await soin(lapins, 'Vaccination', 12000);
    await soin(lapins, 'Déparasitage', 3000);

    await afficher(tester);
    await ouvrir(tester, 'Analyse Sanitaire');

    expect(find.text('2'), findsWidgets);
    expect(find.text('15000 F'), findsWidgets);
  });

  /// ⚠️⚠️ Le taux de morbidité se lit sur `infirmary_records`, table qui
  /// n'existe pas dans la base du poste : quatre tirets, jamais quatre zéros.
  testWidgets('⚠️⚠️ le taux de morbidité affiche un tiret', (tester) async {
    // ⚠️ Un soin est enregistre pour que « Traitement le Plus Frequent » porte
    // une valeur : les quatre tirets restants sont alors, a coup sur, la
    // colonne de morbidite des quatre filieres — et non un KPI vide.
    await soin(lapins, 'Vaccination', 5000);

    await afficher(tester);
    await ouvrir(tester, 'Analyse Sanitaire');

    expect(find.text('TAUX DE MORBIDITÉ %'), findsOneWidget);
    expect(find.text('Vaccination'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(4));
  });

  /// Recalcul INDÉPENDANT, à la main — pesées à J0 (800 g), J7 (900 g), J14
  /// (1100 g) : n=3, ΣX=21, ΣY=2800, ΣXY=21700, ΣX²=245.
  /// pente = (3×21700 − 21×2800) / (3×245 − 21²) = 6300/294 = 21,4286 g/j ;
  /// ordonnée = (2800 − 21,4286×21)/3 = 783,33 ;
  /// projection à 14 j = 783,33 + 21,4286×(14+14) = 1383,33 → 1383 g.
  testWidgets('⚠️ la prévision suit la régression de Laravel, pas 2 points', (
    tester,
  ) async {
    await pesee(lapins, 14, 800);
    await pesee(lapins, 7, 900);
    await pesee(lapins, 0, 1100);

    await afficher(tester);
    await ouvrir(tester, 'Prévision de Croissance');

    expect(find.text('21.4'), findsOneWidget);
    expect(find.text('1100'), findsWidgets);
    // Horizon par défaut : 14 jours.
    expect(find.textContaining('1 383 g'), findsOneWidget);
  });

  testWidgets("⚠️ l'horizon change la projection, arrondie à l'entier", (
    tester,
  ) async {
    await pesee(lapins, 14, 800);
    await pesee(lapins, 7, 900);
    await pesee(lapins, 0, 1100);

    await afficher(tester);
    await ouvrir(tester, 'Prévision de Croissance');

    await tester.tap(find.byKey(const Key('prevision-horizon')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 jours').last);
    await tester.pumpAndSettle();

    // 783,33 + 21,4286 × (14 + 30) = 1726,19 → 1726.
    expect(find.textContaining('1 726 g'), findsOneWidget);
  });

  /// ⚠️ Avec deux pesées la droite passe par les deux points et ne mesure rien :
  /// Laravel exige trois pesées, le poste aussi.
  testWidgets('⚠️ deux pesées ne suffisent pas à projeter', (tester) async {
    await pesee(lapins, 7, 800);
    await pesee(lapins, 0, 900);

    await afficher(tester);
    await ouvrir(tester, 'Prévision de Croissance');

    expect(
      find.text('— Trois pesées au minimum sont nécessaires pour projeter —'),
      findsOneWidget,
    );
  });

  /// ⚠️ Aucun poids cible n'existe hors de la maquette : un tiret expliqué,
  /// jamais un chiffre inventé.
  testWidgets('⚠️ le poids cible est un tiret expliqué, jamais inventé', (
    tester,
  ) async {
    await pesee(lapins, 14, 800);
    await pesee(lapins, 7, 900);
    await pesee(lapins, 0, 1100);

    await afficher(tester);
    await ouvrir(tester, 'Prévision de Croissance');

    expect(find.text("Aucun poids cible n'est paramétré"), findsOneWidget);
    expect(find.text('Dépend du poids cible'), findsOneWidget);
    expect(find.text('2 200 g'), findsNothing);
  });

  testWidgets('sans pesée, rien n est projeté et c est dit', (tester) async {
    await afficher(tester);
    await ouvrir(tester, 'Prévision de Croissance');

    expect(
      find.text('— Trois pesées au minimum sont nécessaires pour projeter —'),
      findsOneWidget,
    );
  });

  /// ⚠️ Une pesée à zéro n'est pas une pesée : c'est l'absence de saisie. La
  /// retenir produirait un GMQ massivement négatif le lendemain.
  testWidgets('⚠️ une journée sans pesée ne compte pas comme une pesée', (
    tester,
  ) async {
    await pesee(lapins, 7, 800);
    await pesee(lapins, 3, 0);
    await pesee(lapins, 0, 900);

    await afficher(tester);
    await ouvrir(tester, 'GMQ & Croissance');

    // Sur 7 jours, pas sur 3.
    expect(find.text('14.3'), findsOneWidget);
    expect(find.text('7'), findsWidgets);
  });
}
