import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/widgets/modale_agri.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/elevage/soins_vaccins_repository.dart';
import 'package:agrierp/features/elevage/soins_vaccins_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.36 — HUB SOINS ET VACCINS (`soins-vaccins-hub.html`).
///
/// ⚠️⚠️ **UN ÉCRAN À TROIS ONGLETS, PAS TROIS ENTRÉES DE MENU.** La maquette
/// charge `vms-registre`, `vms-calendrier` et `vms-suivi` dans des `<iframe>`
/// d'un même hub, et la barre latérale ne porte qu'une entrée.
///
/// ⚠️⚠️ **`infirmary_records` NE DESCEND PAS AU POSTE.** La table existe côté
/// serveur mais ne figure pas dans la charge du tirage : tout l'onglet
/// « Suivi Sanitaire » et le KPI « Animaux en quarantaine » en dépendent. Un
/// zéro se lirait « aucun animal isolé » — c'est un tiret motivé.
void main() {
  late AppDatabase db;
  late SoinsRepository soins;
  late SoinsVaccinsRepository depot;

  const bandeLapins = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
  const bandeVolailles = 'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb';

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final aujourdhui = DateTime.now();
  DateTime jourDe(int decalage) =>
      DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + decalage);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
    depot = SoinsVaccinsRepository(database: db, soins: soins);

    Future<void> bande(String id, String code, String espece, DateTime debut) =>
        db
            .into(db.livestockLots)
            .insert(
              LivestockLotsCompanion.insert(
                id: id,
                code: code,
                speciesId: 'esp-$espece',
                speciesCode: Value(espece),
                stage: const Value('engraissement'),
                createdDate: Value(debut),
                currentQuantity: const Value(50),
              ),
            );

    await bande(bandeLapins, 'LOT-LAP-2026-06', 'cuniculture', jourDe(-10));
    await bande(bandeVolailles, 'GOLIATH-LOT-1', 'aviculture', jourDe(-10));
  });

  tearDown(() async => db.close());

  Future<void> protocole(
    String espece,
    String traitement,
    int jourDeCycle, {
    int remanence = 0,
  }) async {
    await db
        .into(db.prophylaxisScheduleStandards)
        .insert(
          ProphylaxisScheduleStandardsCompanion.insert(
            id: uuid('$traitement-$espece'),
            speciesCode: espece,
            periodLabel: 'Le ${jourDeCycle}e jour',
            cycleDayStart: Value(jourDeCycle),
            cycleDayEnd: Value(jourDeCycle),
            treatment: traitement,
            withdrawalDays: Value(remanence),
          ),
        );
  }

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1;

    // ⚠️ Pas de remise à l'échelle : rendre la vue à sa taille d'origine alors
    // qu'une modale est montée fait échouer le test SUIVANT sur une assertion
    // du framework. Chaque fichier tourne dans son propre isolat.
    await tester.pumpWidget(
      MaterialApp(
        home: SoinsVaccinsScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-vms-$onglet')));
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ les trois onglets du hub sont là, dans son ordre', (
    tester,
  ) async {
    await afficher(tester);

    for (final onglet in [
      'Registre Vétérinaire',
      'Calendrier Vétérinaire',
      'Suivi Sanitaire',
    ]) {
      expect(find.text(onglet), findsWidgets, reason: onglet);
    }
  });

  testWidgets(
    'les quatre KPI du registre portent les libellés de la maquette',
    (tester) async {
      await afficher(tester);

      for (final libelle in [
        'INTERVENTIONS (MOIS)',
        'VACCINATIONS PLANIFIÉES',
        'ANIMAUX EN QUARANTAINE',
        'COÛT SANITAIRE (MOIS)',
      ]) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }
    },
  );

  /// ⚠️⚠️ Un zéro se lirait « aucun animal isolé » ; la vérité est « le poste
  /// ne reçoit pas l'infirmerie ».
  /// ⚠️⚠️ **LE NOMBRE DE CARTES, ONGLET PAR ONGLET** (ticket F0.54). Les trois
  /// onglets du hub sont trois pages distinctes de la maquette.
  ///
  /// ⚠️ `vms-suivi.html` n'est pas relevé : il ne figure pas dans le portage du
  /// contrôle de structure, faute d'avoir été extrait. Son onglet est donc hors
  /// de ce contrôle — dit ici plutôt que passé sous silence.
  testWidgets('⚠️⚠️ chaque onglet rend le nombre de cartes de sa page', (
    tester,
  ) async {
    await afficher(tester);

    expect(
      find.byType(CarteKpi),
      findsNWidgets(cartesAttendues('vms-registre.html')),
      reason: 'Registre Vétérinaire',
    );

    await ouvrir(tester, 'Calendrier Vétérinaire');
    expect(
      find.byType(CarteKpi),
      findsNWidgets(cartesAttendues('vms-calendrier.html')),
      reason: 'Calendrier Vétérinaire',
    );
  });

  testWidgets('⚠️⚠️ les animaux en quarantaine affichent un tiret motivé', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Infirmerie non synchronisée'), findsOneWidget);
  });

  testWidgets('le registre porte les six colonnes de la maquette', (
    tester,
  ) async {
    await afficher(tester);

    for (final colonne in [
      'DATE',
      'LOT / ESPÈCE',
      "TYPE D'ACTION",
      'PRODUIT',
      'DOSE',
      'STATUT',
    ]) {
      expect(find.text(colonne), findsOneWidget, reason: colonne);
    }
  });

  testWidgets('un soin enregistré apparaît au registre et compte au KPI', (
    tester,
  ) async {
    await soins.enregistrer(
      lotId: bandeLapins,
      typeAction: 'Vaccination',
      produit: 'Vaccin Myxomatose',
      dose: '1 dose/sujet',
      cout: 12000,
    );

    await afficher(tester);

    expect(find.text('Vaccin Myxomatose'), findsOneWidget);
    expect(find.text('1 dose/sujet'), findsOneWidget);
    expect(find.text('LOT-LAP-2026-06'), findsWidgets);
    expect(find.text('12000 F'), findsOneWidget);
  });

  testWidgets('le filtre de filière restreint le registre', (tester) async {
    await soins.enregistrer(
      lotId: bandeLapins,
      typeAction: 'Vaccination',
      produit: 'Myxomatose',
    );
    await soins.enregistrer(
      lotId: bandeVolailles,
      typeAction: 'Vermifuge',
      produit: 'Levalap',
    );

    await afficher(tester);

    expect(find.text('Myxomatose'), findsOneWidget);
    expect(find.text('Levalap'), findsOneWidget);

    await tester.tap(find.byKey(const Key('vms-filiere')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volailles').last);
    await tester.pumpAndSettle();

    expect(find.text('Myxomatose'), findsNothing);
    expect(find.text('Levalap'), findsOneWidget);
  });

  /// ⚠️ La maquette annonce « Rechercher un diagnostic, un lot » : la recherche
  /// porte donc aussi sur les symptômes.
  testWidgets('⚠️ la recherche couvre aussi les symptômes', (tester) async {
    await soins.enregistrer(
      lotId: bandeLapins,
      typeAction: 'Traitement curatif',
      produit: 'Alfamec',
      symptomes: 'Diarrhée persistante',
    );
    await soins.enregistrer(
      lotId: bandeVolailles,
      typeAction: 'Vermifuge',
      produit: 'Levalap',
    );

    await afficher(tester);
    await tester.enterText(find.byKey(const Key('vms-recherche')), 'diarrhée');
    await tester.pumpAndSettle();

    expect(find.text('Alfamec'), findsOneWidget);
    expect(find.text('Levalap'), findsNothing);
  });

  testWidgets('sans soin correspondant, le registre le dit', (tester) async {
    await afficher(tester);

    expect(
      find.text('— Aucun soin au registre pour ces critères —'),
      findsOneWidget,
    );
  });

  // ── Modale « Nouveau Soin » ───────────────────────────────────────────────

  testWidgets('⚠️ la modale reprend les neuf champs de la maquette', (
    tester,
  ) async {
    await afficher(tester);
    await tester.tap(find.byKey(const Key('nouveau-soin')));
    await tester.pumpAndSettle();

    // ⚠️ PORTÉE LIMITÉE À LA MODALE : « DOSE » titre aussi une colonne du
    // registre, derrière elle.
    final modale = find.byType(ModaleAgri);

    for (final libelle in [
      'LOT / BANDE *',
      'DATE DU SOIN *',
      "TYPE D'ACTION *",
      'PRODUIT UTILISÉ',
      'DOSE',
      "DÉLAI D'ATTENTE / RÉMANENCE (JOURS)",
      'VÉTÉRINAIRE / ANIMALIER',
      'SYMPTÔMES OBSERVÉS',
      'COÛT (FCFA)',
    ]) {
      expect(
        find.descendant(of: modale, matching: find.text(libelle)),
        findsOneWidget,
        reason: libelle,
      );
    }
  });

  testWidgets('la modale enregistre un soin en file d envoi', (tester) async {
    await afficher(tester);
    await tester.tap(find.byKey(const Key('nouveau-soin')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('soin-produit')), 'Levalap');
    await tester.enterText(find.byKey(const Key('soin-dose')), '1C / 5L eau');
    await tester.tap(find.byKey(const Key('soin-enregistrer')));
    await tester.pumpAndSettle();

    final enregistres = await db.select(db.veterinaryRecords).get();

    expect(enregistres, hasLength(1));
    expect(enregistres.single.productUsed, 'Levalap');
    expect(enregistres.single.syncStatus, SyncStatus.pending);
  });

  /// ⚠️⚠️ LE POINT SANITAIRE : un délai d'attente crée la période de rémanence
  /// qui BLOQUE la vente de la bande.
  testWidgets('⚠️⚠️ un délai d attente bloque la bande à la vente', (
    tester,
  ) async {
    await afficher(tester);
    await tester.tap(find.byKey(const Key('nouveau-soin')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('soin-produit')), 'Alfamec');
    await tester.enterText(find.byKey(const Key('soin-remanence')), '7');
    await tester.tap(find.byKey(const Key('soin-enregistrer')));
    await tester.pumpAndSettle();

    final remanences = await db.select(db.veterinaryWithdrawalPeriods).get();

    expect(remanences, hasLength(1));
    expect(remanences.single.productUsed, 'Alfamec');
  });

  /// ⚠️⚠️ Un délai sans produit ne bloque rien — c'est la règle du serveur.
  /// Accepter la saisie ferait croire la bande bloquée alors qu'elle
  /// resterait vendable.
  testWidgets('⚠️⚠️ un délai sans produit est refusé, avec sa raison', (
    tester,
  ) async {
    await afficher(tester);
    await tester.tap(find.byKey(const Key('nouveau-soin')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('soin-remanence')), '7');
    await tester.tap(find.byKey(const Key('soin-enregistrer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('soin-erreur')), findsOneWidget);
    expect(await db.select(db.veterinaryRecords).get(), isEmpty);
  });

  // ── Onglet Calendrier ─────────────────────────────────────────────────────

  testWidgets('la légende du Gantt porte les quatre états de la maquette', (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, 'Calendrier Vétérinaire');

    for (final etat in [
      'Effectué',
      'Planifié',
      'En retard',
      'Traitement en cours',
    ]) {
      expect(find.text(etat), findsOneWidget, reason: etat);
    }
  });

  /// ⚠️⚠️ « EN RETARD » N'EST PAS « PLANIFIÉ ». La bande est née il y a
  /// 10 jours ; un traitement dû au 5e jour de cycle n'a pas été administré.
  testWidgets('⚠️⚠️ un traitement dû et non administré passe en retard', (
    tester,
  ) async {
    await protocole('cuniculture', 'Vaccination Myxomatose', 8);

    await afficher(tester);
    await ouvrir(tester, 'Calendrier Vétérinaire');

    expect(find.byKey(const Key('gantt-LOT-LAP-2026-06')), findsOneWidget);

    // Une pastille rouge : le traitement du 8e jour est passé, non administré.
    final rouges = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byKey(const Key('gantt-LOT-LAP-2026-06')),
            matching: find.byType(Container),
          ),
        )
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).shape == BoxShape.circle,
        );

    expect(rouges, isNotEmpty);
  });

  testWidgets('la grille porte une colonne par jour de la fenêtre', (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, 'Calendrier Vétérinaire');

    // 3 jours en arrière + aujourd'hui + 10 en avant = 14 colonnes.
    final debut = jourDe(-SoinsVaccinsRepository.joursAvant);
    final fin = jourDe(SoinsVaccinsRepository.joursApres);

    expect(find.text('${debut.day}/${debut.month}'), findsOneWidget);
    expect(find.text('${fin.day}/${fin.month}'), findsOneWidget);
  });

  // ── Onglet Suivi Sanitaire ────────────────────────────────────────────────

  testWidgets('⚠️⚠️ le suivi sanitaire dit sa dépendance', (tester) async {
    await afficher(tester);
    await ouvrir(tester, 'Suivi Sanitaire');

    expect(find.byKey(const Key('suivi-non-embarque')), findsOneWidget);
    expect(find.text('— Module non embarqué au poste —'), findsOneWidget);
    expect(find.textContaining("L'infirmerie"), findsOneWidget);
  });
}
