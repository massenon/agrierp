import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_repository.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.34 — SUIVI REPRODUCTION (`prototype_html/suivi-reproduction.html`).
///
/// ⚠️⚠️ **SEUL ÉCRAN QUI SUIVE UN ANIMAL NOMMÉ.** R1, R2… chez les lapines ;
/// T1, T2… chez les truies. Les fiches journalières ne connaissent que des
/// agrégats de bande. `livestock_reproduction_events` descend au poste depuis
/// le ticket 14.72 — avant, l'écran n'avait littéralement aucune donnée.
///
/// ⚠️ **TROIS ÉTATS DE PALPATION, PAS DEUX.** `palpation_date` nulle ne veut
/// pas dire « négative » : elle veut dire « pas encore faite ». Confondre les
/// deux ferait réformer une lapine qui n'a jamais été palpée.
void main() {
  late AppDatabase db;
  late SuiviReproductionRepository depot;

  const bandeLapins = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
  const bandePorcs = 'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb';
  const bandeVolailles = 'cccccccc-0000-4000-8000-cccccccccccc';

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final aujourdhui = DateTime.now();
  DateTime ilYA(int jours) =>
      DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day - jours);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = SuiviReproductionRepository(database: db);

    Future<void> bande(String id, String code, String espece) => db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: id,
            code: code,
            speciesId: 'esp-$espece',
            speciesCode: Value(espece),
            currentQuantity: const Value(50),
          ),
        );

    await bande(bandeLapins, 'LOT-LAP-2026-06', 'cuniculture');
    await bande(bandePorcs, 'BANDE-POR-P1', 'porciculture');
    await bande(bandeVolailles, 'VOL-REPRO-LOT-1', 'aviculture');
  });

  tearDown(() async => db.close());

  Future<void> cycle(
    String cle,
    String lot,
    String mere, {
    String? male,
    int saillieIlYA = 20,
    int? palpationIlYA,
    int? miseBasIlYA,
    int? nesVivants,
    int? nesMorts,
    String status = 'en_cours',
  }) async {
    await db
        .into(db.livestockReproductionEvents)
        .insert(
          LivestockReproductionEventsCompanion.insert(
            id: uuid('$cle-repro'),
            // ⚠️ « serveur » : ces cycles viennent du tirage, pas du poste.
            deviceId: 'serveur',
            syncStatus: const Value(SyncStatus.synced),
            lotId: lot,
            motherRef: mere,
            sireRef: Value(male),
            saillieDate: Value(ilYA(saillieIlYA)),
            palpationDate: Value(
              palpationIlYA == null ? null : ilYA(palpationIlYA),
            ),
            miseBasDateActual: Value(
              miseBasIlYA == null ? null : ilYA(miseBasIlYA),
            ),
            nesVivants: Value(nesVivants),
            nesMorts: Value(nesMorts),
            status: Value(status),
            updatedAt: aujourdhui,
          ),
        );
  }

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SuiviReproductionScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-repro-$onglet')));
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ les quatre onglets de la maquette sont là, dans son ordre', (
    tester,
  ) async {
    await afficher(tester);

    for (final onglet in ['Lapins', 'Volailles', 'Porcs', 'Escargots']) {
      expect(find.text(onglet), findsOneWidget, reason: onglet);
    }
  });

  /// ⚠️⚠️ **LE NOMBRE DE CARTES, PAS SEULEMENT LEURS LIBELLÉS** (ticket F0.54).
  /// Le contrôle voisin vérifie que les libellés attendus sont là ; il ne dirait
  /// rien d'une carte ajoutée, ni d'une carte de la maquette rendue deux fois.
  /// `cartesMaquette` est relevé sur la maquette (`border-l-4`) : il fait foi.
  testWidgets('⚠️⚠️ l écran rend le nombre de cartes de la maquette', (
    tester,
  ) async {
    await afficher(tester);

    expect(
      find.byType(CarteKpi),
      findsNWidgets(cartesAttendues('suivi-reproduction.html')),
    );
  });

  // Ticket H7 : le Blade fait foi — « Mises bas / Éclosions (mois) ».
  testWidgets('les quatre KPI portent les libellés du Blade', (
    tester,
  ) async {
    await afficher(tester);

    for (final libelle in [
      'REPRODUCTRICES GESTANTES',
      'PALPATIONS / ÉCHÉANCES DUES',
      'MISES BAS / ÉCLOSIONS (MOIS)',
      'ALERTES RÉFORME / PERTES',
    ]) {
      expect(find.text(libelle), findsOneWidget, reason: libelle);
    }
  });

  // Ticket H7 : le Blade fait foi — quatre étapes ; « Boîte à nid J+28 » (ajout du poste,
  // gardé) passe en ligne annexe sous le rappel.
  testWidgets('le bandeau « Rappel du cycle » porte les jalons lapins', (
    tester,
  ) async {
    await afficher(tester);

    for (final jalon in [
      'Saillie J0',
      'Palpation J+14',
      'Mise bas J+30',
      'Sevrage J+60',
    ]) {
      expect(find.text(jalon), findsOneWidget, reason: jalon);
    }
    expect(find.textContaining('Boîte à nid J+28'), findsOneWidget);
  });

  // Ticket H7 : le Blade fait foi — « Mise bas J+114 », sans « (3m3s3j) ».
  testWidgets('le bandeau porcs porte les jalons de la gestation porcine', (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, 'Porcs');

    for (final jalon in [
      'Saillie J0',
      'Retour Chaleur J+21',
      'Mise bas J+114',
      'Sevrage J+42',
    ]) {
      expect(find.text(jalon), findsOneWidget, reason: jalon);
    }
  });

  testWidgets('la lapine est suivie par son numéro', (tester) async {
    await cycle(
      'r1',
      bandeLapins,
      'R1',
      male: 'M3',
      saillieIlYA: 30,
      palpationIlYA: 16,
      miseBasIlYA: 0,
      nesVivants: 7,
      nesMorts: 1,
    );

    await afficher(tester);

    expect(find.text('R1'), findsOneWidget);
    expect(find.text('M3'), findsOneWidget);
    expect(find.text('LOT-LAP-2026-06'), findsOneWidget);
    // Ticket H7 : le Blade fait foi — « 7 (1 morts) » : vivants, puis morts.
    expect(find.text('7 (1 morts)'), findsOneWidget);
  });

  /// ⚠️⚠️ LE CŒUR DU TICKET : trois états, jamais deux.
  testWidgets('⚠️⚠️ une palpation non faite n est pas une palpation négative', (
    tester,
  ) async {
    // Saillie il y a 20 jours, jamais palpée → l'échéance J+14 est passée.
    await cycle('due', bandeLapins, 'R2', saillieIlYA: 20);
    // Saillie il y a 3 jours → l'échéance n'est pas encore là.
    await cycle('att', bandeLapins, 'R3', saillieIlYA: 3);

    await afficher(tester);

    // Ticket H7 : le Blade fait foi — « Prévue jj/mm/aaaa », en rouge une fois échue.
    String jj(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
    final echue = tester.widget<Text>(find.text('Prévue ${jj(ilYA(6))}'));
    final aVenir = tester.widget<Text>(find.text('Prévue ${jj(ilYA(-11))}'));
    expect(echue.style?.color, AgriColors.errorDeep);
    expect(aVenir.style?.color, AgriColors.outline);
    expect(find.textContaining('(Négatif)'), findsNothing);
  });

  testWidgets('une palpation faite se lit positive ou négative', (
    tester,
  ) async {
    await cycle('pos', bandeLapins, 'R4', saillieIlYA: 20, palpationIlYA: 6);
    await cycle(
      'neg',
      bandeLapins,
      'R5',
      saillieIlYA: 20,
      palpationIlYA: 6,
      status: 'echec',
    );

    await afficher(tester);

    // Ticket H7 : le Blade fait foi — « jj/mm/aaaa (Positif|Négatif) ».
    expect(find.textContaining('(Positif)'), findsOneWidget);
    expect(find.textContaining('(Négatif)'), findsOneWidget);
  });

  /// Le KPI compte exactement comme le serveur : cycles `en_cours` sans mise
  /// bas effective, et palpation due à partir de saillie + 14 jours.
  testWidgets('les KPI comptent comme le serveur', (tester) async {
    await cycle('g1', bandeLapins, 'R6', saillieIlYA: 20);
    await cycle('g2', bandePorcs, 'T1', saillieIlYA: 40);
    await cycle(
      'mb',
      bandeLapins,
      'R7',
      saillieIlYA: 35,
      palpationIlYA: 20,
      miseBasIlYA: 2,
      nesVivants: 6,
    );
    await cycle(
      'ec',
      bandeLapins,
      'R8',
      saillieIlYA: 25,
      palpationIlYA: 10,
      status: 'echec',
    );

    await afficher(tester);

    // Gestantes : R6, T1 et R8 sont « en_cours » sans mise bas… mais R8 est
    // en échec, donc hors du décompte. Restent R6 et T1.
    expect(find.text('2'), findsWidgets);
    // Mises bas du mois : R7.
    expect(find.text('1'), findsWidgets);
  });

  /// ⚠️ Retour chaleur et sevrage ne sont stockés nulle part : ils se
  /// déduisent de la saillie, comme le bandeau du cycle l'annonce.
  testWidgets('les échéances porcines se calculent depuis la saillie', (
    tester,
  ) async {
    await cycle('t1', bandePorcs, 'T1', male: 'V2', saillieIlYA: 0);

    await afficher(tester);
    await ouvrir(tester, 'Porcs');

    // Ticket H7 : le Blade fait foi — le retour chaleur à venir s'écrit « Prévue jj/mm/aaaa ».
    final dans21 = ilYA(-21);
    final attendu =
        'Prévue ${dans21.day.toString().padLeft(2, '0')}/'
        '${dans21.month.toString().padLeft(2, '0')}/${dans21.year}';

    expect(find.text(attendu), findsOneWidget);
  });

  /// ⚠️⚠️ Volailles et Escargots sont un RÉSUMÉ, pas un second formulaire :
  /// la donnée est déjà saisie sur les fiches d'espèce.
  testWidgets('⚠️⚠️ le couvoir volailles est un résumé, pas une saisie', (
    tester,
  ) async {
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: uuid('f-couvoir'),
            deviceId: 'poste-test',
            updatedAt: aujourdhui,
            lotId: bandeVolailles,
            entryDate: aujourdhui,
            ne: const Value(102),
            ponteTotal: const Value(120),
            effectifFinal: const Value(200),
          ),
        );

    await afficher(tester);
    await ouvrir(tester, 'Volailles');

    expect(find.text('120'), findsOneWidget);
    expect(find.text('102'), findsOneWidget);
    // Ticket H7 : le Blade fait foi — `number_format(…, 1, ',', ' ')`, et le lien vers la
    // fiche de saisie « Saisir le Couvoir du Jour → ».
    expect(find.text('85,0 %'), findsOneWidget);
    expect(find.text('Saisir le Couvoir du Jour →'), findsOneWidget);
  });

  /// Ticket H7 : le Blade fait foi — sans œuf couvé, le web affiche « 0,0 % »
  /// (`$couves > 0 ? … : 0.0`), et le poste le suit.
  testWidgets("sans œuf couvé, le taux d'éclosion est « 0,0 % » comme au web", (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, 'Volailles');

    expect(find.text('0,0 %'), findsOneWidget);
  });

  /// ⚠️ La saillie se déclare au poste ; palpation, mise bas et sevrage
  /// restent web — ce sont des corrections d'un cycle en évolution.
  testWidgets('⚠️ l écran dit ce qui se déclare ici et ce qui reste web', (
    tester,
  ) async {
    await afficher(tester);

    // Ticket H7 : actions de cycle ouvertes — le bandeau de restriction n'a plus lieu d'être.
    expect(find.byKey(const Key('mention-lecture-seule')), findsNothing);
  });

  // Ticket H7 : le Blade fait foi — l'état vide du web.
  testWidgets('sans cycle reçu, la filière le dit', (tester) async {
    await afficher(tester);

    expect(
      find.text('Aucune saillie déclarée pour le moment.'),
      findsOneWidget,
    );
  });
}
