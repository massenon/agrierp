import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/widgets/modale_agri.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
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
/// Tickets H8 / H8b (19/10/2026) : le Blade fait foi, et l'infirmerie comme le
/// calendrier planifié descendent au poste et y sont saisis. Les tests adaptés le
/// disent (« Ticket H8 : le Blade fait foi ») ; la confrontation au Blade lui-même
/// vit dans `soins_infirmerie_calendrier_test.dart`.
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
                // Ticket H8 : le Blade fait foi — seules les bandes `status = actif` ET `is_active` sont
                // proposées et ont leur ligne au calendrier (`getActiveLotsProperty`).
                status: const Value('actif'),
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

  /// Ticket H8 : le Blade fait foi — l'infirmerie descend au poste (H8b) : « Animaux en quarantaine » est
  /// une MESURE (`InfirmaryRecord::where('status', 'en_cours')->count()`), plus un tiret motivé.
  testWidgets('Ticket H8 : « Animaux en quarantaine » compte l infirmerie', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Infirmerie non synchronisée'), findsNothing);
    final carte = tester.widget<CarteKpi>(
      find.byWidgetPredicate(
        (w) => w is CarteKpi && w.libelle == 'Animaux en quarantaine',
      ),
    );
    expect(carte.valeur, '0');
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
    // Ticket H8 : le Blade fait foi — cellule « CODE (Espèce) » (espèce inconnue du poste : « — ») et
    // coût « 12 000 FCFA » (`number_format(…, 0, ',', ' ').' FCFA'`).
    expect(find.text('LOT-LAP-2026-06 (—)'), findsOneWidget);
    expect(find.text('12 000 FCFA'), findsOneWidget);
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

  /// Ticket H8 : le Blade fait foi — registre vide : son message exact ; registre que les FILTRES (ajout du
  /// poste) vident : le dire.
  testWidgets('sans soin correspondant, le registre le dit', (tester) async {
    await afficher(tester);

    expect(find.text('Aucun soin enregistré pour le moment.'), findsOneWidget);

    await soins.enregistrer(
      lotId: bandeLapins,
      typeAction: 'Vaccination',
      produit: 'Myxomatose',
    );
    await tester.pumpWidget(const SizedBox());
    await afficher(tester);
    await tester.enterText(find.byKey(const Key('vms-recherche')), 'introuvable');
    await tester.pumpAndSettle();

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

  /// Ticket H8 : le Blade fait foi — les deux listes s'ouvrent sur « -- Sélectionner -- » : la bande et le
  /// type d'action se CHOISISSENT (`required` de `saveSoin()`).
  Future<void> choisirBandeEtType(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('soin-bande')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LOT-LAP-2026-06 (—)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('soin-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vermifuge').last);
    await tester.pumpAndSettle();
  }

  testWidgets('la modale enregistre un soin en file d envoi', (tester) async {
    await afficher(tester);
    await tester.tap(find.byKey(const Key('nouveau-soin')));
    await tester.pumpAndSettle();

    await choisirBandeEtType(tester);
    await tester.enterText(find.byKey(const Key('soin-produit')), 'Levalap');
    await tester.enterText(find.byKey(const Key('soin-dose')), '1C / 5L eau');
    await tester.tap(find.byKey(const Key('soin-enregistrer')));
    await tester.pumpAndSettle();

    final enregistres = await db.select(db.veterinaryRecords).get();

    expect(enregistres, hasLength(1));
    expect(enregistres.single.productUsed, 'Levalap');
    expect(enregistres.single.syncStatus, SyncStatus.pending);
    // Ticket H8 : le message du composant (`saveSoin()`), en toast unique.
    expect(find.text('Soin enregistré avec succès.'), findsOneWidget);
    ToastAgri.toutRetirer();
  });

  /// ⚠️⚠️ LE POINT SANITAIRE : un délai d'attente crée la période de rémanence
  /// qui BLOQUE la vente de la bande.
  testWidgets('⚠️⚠️ un délai d attente bloque la bande à la vente', (
    tester,
  ) async {
    await afficher(tester);
    await tester.tap(find.byKey(const Key('nouveau-soin')));
    await tester.pumpAndSettle();

    await choisirBandeEtType(tester);
    await tester.enterText(find.byKey(const Key('soin-produit')), 'Alfamec');
    await tester.enterText(find.byKey(const Key('soin-remanence')), '7');
    await tester.tap(find.byKey(const Key('soin-enregistrer')));
    await tester.pumpAndSettle();

    final remanences = await db.select(db.veterinaryWithdrawalPeriods).get();

    expect(remanences, hasLength(1));
    expect(remanences.single.productUsed, 'Alfamec');
    expect(
      find.text('Soin enregistré — bande bloquée à la vente pendant 7 jour(s).'),
      findsOneWidget,
    );
    ToastAgri.toutRetirer();
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

    await choisirBandeEtType(tester);
    await tester.enterText(find.byKey(const Key('soin-remanence')), '7');
    await tester.tap(find.byKey(const Key('soin-enregistrer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('soin-erreur')), findsOneWidget);
    expect(find.textContaining('exige de nommer le produit'), findsOneWidget);
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

  /// Ticket H8 : le Blade fait foi — la fenêtre commence AUJOURD'HUI (J → J+13) : un traitement du protocole
  /// passé n'y figure plus. L'ajout du poste (protocole calculé, gardé par décision client) s'affiche en
  /// ANNEAU jaune « calculé » sur son jour à venir. La bande est née il y a 10 jours (J11 aujourd'hui) : le
  /// traitement du 13e jour tombe à J+2.
  testWidgets('Ticket H8 : un traitement à venir du protocole s affiche en anneau calculé', (
    tester,
  ) async {
    await protocole('cuniculture', 'Vaccination Myxomatose', 13);

    await afficher(tester);
    await ouvrir(tester, 'Calendrier Vétérinaire');

    expect(find.byKey(const Key('gantt-LOT-LAP-2026-06')), findsOneWidget);

    final anneaux = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byKey(const Key('gantt-LOT-LAP-2026-06')),
            matching: find.byType(Container),
          ),
        )
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration &&
              d.shape == BoxShape.circle &&
              d.border is Border &&
              (d.border! as Border).top.color == AgriColors.accentYellow;
        });

    expect(anneaux, hasLength(1));
    expect(find.byTooltip('Vaccination Myxomatose (calculé)'), findsOneWidget);
  });

  testWidgets('la grille porte une colonne par jour de la fenêtre', (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, 'Calendrier Vétérinaire');

    // Ticket H8 : le Blade fait foi — aujourd'hui + 13 jours = 14 colonnes (`range(0, 13)`).
    final debut = jourDe(-SoinsVaccinsRepository.joursAvant);
    final fin = jourDe(SoinsVaccinsRepository.joursApres);

    expect(find.text('${debut.day}/${debut.month}'), findsOneWidget);
    expect(find.text('${fin.day}/${fin.month}'), findsOneWidget);
  });

  // ── Onglet Suivi Sanitaire ────────────────────────────────────────────────

  /// Ticket H8 : le Blade fait foi — l'infirmerie est embarquée (H8b) : l'onglet est COMPLET ; vide, il
  /// porte le message exact du Blade (détail : `soins_infirmerie_calendrier_test.dart`).
  testWidgets('Ticket H8 : le suivi sanitaire est complet, vide il le dit', (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, 'Suivi Sanitaire');

    expect(find.text('— Module non embarqué au poste —'), findsNothing);
    expect(find.byKey(const Key('nouvelle-entree-infirmerie')), findsOneWidget);
    expect(find.byType(CarteKpi), findsNWidgets(4));
    expect(
      find.text("Aucune entrée d'infirmerie pour le moment."),
      findsOneWidget,
    );
  });
}
