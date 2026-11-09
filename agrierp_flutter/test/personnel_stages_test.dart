import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/rh/personnel_repository.dart';
import 'package:agrierp/features/rh/personnel_stages_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.48 — HUB PERSONNEL & STAGES (`personnel-stages.html`).
///
/// ⚠️⚠️ **UN SEUL DES CINQ ONGLETS ÉCRIT, ET C'EST LE BON.** Le pointage se
/// fait à 7 h à la ferme, là où le réseau n'est pas. Registres, paie et
/// attestations restent sur la surface web — pour trois raisons différentes,
/// toutes affichées à l'écran.
///
/// ⚠️⚠️ **L'IDENTITÉ D'UN POINTAGE EST LE COUPLE (EMPLOYÉ, JOUR)**, pas son
/// UUID : `unique(employee_id, attendance_date)` côté serveur.
void main() {
  late AppDatabase db;
  late PersonnelRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final aujourdhui = HeureBenin.maintenant();
  final jourSeul = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = PersonnelRepository(database: db, identifiantPoste: 'poste-test');
  });

  tearDown(() async => db.close());

  Future<void> employe(
    String cle,
    String prenom,
    String nom, {
    String? fonction,
    double? salaire,
    DateTime? embauche,
    String statut = 'actif',
  }) => db
      .into(db.employees)
      .insert(
        EmployeesCompanion.insert(
          id: uuid(cle),
          deviceId: 'serveur',
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: const Value(SyncStatus.synced),
          firstName: prenom,
          lastName: nom,
          position: Value(fonction),
          baseSalary: Value(salaire),
          hireDate: Value(embauche ?? DateTime(2025, 3, 1)),
          status: Value(statut),
        ),
      );

  Future<void> stagiaire(
    String cle,
    String prenom,
    String nom, {
    String? ecole,
    DateTime? debut,
    DateTime? fin,
    bool sansFin = false,
    double frais = 25000,
    bool regle = true,
  }) => db
      .into(db.internships)
      .insert(
        InternshipsCompanion.insert(
          id: uuid(cle),
          deviceId: 'serveur',
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: const Value(SyncStatus.synced),
          firstName: prenom,
          lastName: nom,
          school: Value(ecole),
          startDate: Value(debut ?? DateTime(aujourdhui.year, 4, 1)),
          // ⚠️ `sansFin` distingue « convention ouverte » de « fin par
          // défaut » : les deux sont des `null` en base, pas dans le test.
          endDate: sansFin
              ? const Value(null)
              : Value(fin ?? DateTime(aujourdhui.year, 6, 1)),
          monthlyFee: Value(frais),
          feePaid: Value(regle),
        ),
      );

  Future<void> pointageServeur(
    String cle, {
    required String cleEmploye,
    required String statut,
    DateTime? jour,
  }) => db
      .into(db.attendanceRecords)
      .insert(
        AttendanceRecordsCompanion.insert(
          id: uuid(cle),
          deviceId: 'serveur',
          updatedAt: jour ?? jourSeul,
          syncStatus: const Value(SyncStatus.synced),
          employeeId: uuid(cleEmploye),
          attendanceDate: jour ?? jourSeul,
          checkIn: const Value('07:05:00'),
          checkOut: const Value('17:05:00'),
          status: statut,
        ),
      );

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: PersonnelStagesScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-personnel-$onglet')));
    await tester.pumpAndSettle();
  }

  group('dépôt', () {
    /// ⚠️⚠️ LE CŒUR DU TICKET : un pointage part en attente.
    test('⚠️⚠️ un pointage saisi part en attente de synchronisation', () async {
      await employe('e1', 'Kossi', 'AGBODJI');

      final id = await depot.pointer(
        employeId: uuid('e1'),
        jour: aujourdhui,
        statut: StatutPointage.present,
        arrivee: '07:00',
      );

      final ligne = await (db.select(
        db.attendanceRecords,
      )..where((t) => t.id.equals(id))).getSingle();

      expect(ligne.syncStatus, SyncStatus.pending);
      expect(ligne.deviceId, 'poste-test');
      expect(ligne.attendanceDate, jourSeul);
      expect(ligne.checkIn, '07:00');
    });

    /// ⚠️⚠️ UN SEUL POINTAGE PAR EMPLOYÉ ET PAR JOUR : repointer CORRIGE.
    test('⚠️⚠️ repointer le même jour corrige au lieu de doubler', () async {
      await employe('e1', 'Kossi', 'AGBODJI');

      final premier = await depot.pointer(
        employeId: uuid('e1'),
        jour: aujourdhui,
        statut: StatutPointage.present,
        arrivee: '07:00',
      );
      final second = await depot.pointer(
        employeId: uuid('e1'),
        jour: aujourdhui,
        statut: StatutPointage.retard,
        arrivee: '08:30',
      );

      expect(second, premier);

      final lignes = await db.select(db.attendanceRecords).get();
      expect(lignes.length, 1);
      expect(lignes.single.status, 'retard');
      expect(lignes.single.checkIn, '08:30');
    });

    /// ⚠️ Corriger au poste une ligne venue du serveur la remet EN ATTENTE :
    /// sinon la correction ne repartirait jamais.
    test('⚠️ corriger un pointage du serveur le remet en attente', () async {
      await employe('e1', 'Kossi', 'AGBODJI');
      await pointageServeur('p1', cleEmploye: 'e1', statut: 'present');

      await depot.pointer(
        employeId: uuid('e1'),
        jour: aujourdhui,
        statut: StatutPointage.absent,
      );

      final ligne = await db.select(db.attendanceRecords).getSingle();
      expect(ligne.syncStatus, SyncStatus.pending);
      expect(ligne.status, 'absent');
    });

    /// ⚠️⚠️ UN RETARD EST UNE PRÉSENCE — règle du serveur.
    test('⚠️⚠️ un retard compte parmi les présents', () async {
      await employe('e1', 'Kossi', 'AGBODJI');
      await employe('e2', 'Afi', 'DOSSOU');
      await pointageServeur('p1', cleEmploye: 'e1', statut: 'present');
      await pointageServeur('p2', cleEmploye: 'e2', statut: 'retard');

      final d = await depot.charger();

      expect(d.presents, 2);
      expect(d.retards, 1);
      expect(d.absents, 0);
    });

    test('les employés sans pointage du jour sont listés', () async {
      await employe('e1', 'Kossi', 'AGBODJI');
      await employe('e2', 'Afi', 'DOSSOU');
      await pointageServeur('p1', cleEmploye: 'e1', statut: 'present');

      final d = await depot.charger();

      expect(d.nonPointes().single.lastName, 'DOSSOU');
    });

    /// Ticket RH-4 : la paie du mois se calcule au poste comme au web (`CalculPaie`) ; sans employé, rien.
    test('sans employé, la paie du mois est vide', () async {
      final p = await depot.paie(PersonnelRepository.periodeDe(aujourdhui));

      expect(p.lignes, isEmpty);
      expect(p.masseSalariale, 0);
      expect(p.enAttente, 0);
    });
  });

  group('cartes de la maquette (ticket F0.55)', () {
    /// ⚠️⚠️ Le serveur ne sert que les employés `is_active = true`. Le compte
    /// est donc celui des employés SOUS CONTRAT — un salarié en congé reste un
    /// employé, et l'exclure ferait fondre l'effectif à chaque absence.
    test('⚠️⚠️ « Employés actifs » compte les employés sous contrat', () async {
      await employe('e1', 'Koffi', 'ADJOVI');
      await employe('e2', 'Aline', 'DOSSOU', statut: 'conge');

      final d = await depot.charger();

      expect(d.employesActifs, 2);
    });

    test(
      '« Nouveaux (année) » compte les embauches de l année en cours',
      () async {
        await employe(
          'e1',
          'Koffi',
          'ADJOVI',
          embauche: DateTime(aujourdhui.year, 2, 10),
        );
        await employe(
          'e2',
          'Aline',
          'DOSSOU',
          embauche: DateTime(aujourdhui.year - 1, 11, 3),
        );

        final d = await depot.charger();

        expect(d.nouveauxEmployesDeLAnnee, 1);
      },
    );

    /// ⚠️⚠️ **UN STAGE SANS DATE DE FIN EST EN COURS**, pas terminé : la
    /// convention peut rester ouverte. Le compter comme échu ferait
    /// disparaître le stagiaire le jour même de son arrivée.
    test('⚠️⚠️ un stage sans date de fin reste actif', () async {
      await stagiaire(
        's1',
        'Rachid',
        'BIO',
        debut: DateTime(aujourdhui.year, 1, 5),
        sansFin: true,
      );

      final d = await depot.charger();

      expect(d.stagiairesActifs, 1);
    });

    test('un stage terminé et un stage à venir ne sont pas actifs', () async {
      await stagiaire(
        's1',
        'Rachid',
        'BIO',
        debut: DateTime(aujourdhui.year - 1, 1, 5),
        fin: DateTime(aujourdhui.year - 1, 6, 5),
      );
      await stagiaire(
        's2',
        'Sarah',
        'KOTO',
        debut: aujourdhui.add(const Duration(days: 30)),
        fin: aujourdhui.add(const Duration(days: 120)),
      );

      final d = await depot.charger();

      expect(d.stagiairesActifs, 0);
    });

    /// ⚠️ Les deux montants se lisent sur le MÊME `monthlyFee`, séparés par
    /// `feePaid` : leur somme redonne le total dû par la promotion.
    test(
      '⚠️ les frais se répartissent entre collectés et en attente',
      () async {
        await stagiaire('s1', 'Rachid', 'BIO', frais: 45000, regle: true);
        await stagiaire('s2', 'Sarah', 'KOTO', frais: 25000, regle: false);

        final d = await depot.charger();

        expect(d.fraisCollectes, 45000);
        expect(d.fraisEnAttente, 25000);
      },
    );

    /// ⚠️⚠️ Jamais reçu : inconnu, pas nul. « 0 » dirait qu'aucune attestation n'a
    /// été délivrée.
    test(
      '⚠️⚠️ « Attestations émises » est inconnu avant le premier tirage',
      () async {
        await stagiaire('s1', 'Rachid', 'BIO');

        final d = await depot.charger();

        expect(d.attestationsEmises, isNull);
      },
    );

    /// ⚠️ Reçu : le décompte du SERVEUR, tel quel — y compris un vrai zéro.
    test('« Attestations émises » reprend le décompte du serveur', () async {
      Future<void> recu(String valeur) => db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: SyncEngine.cleAttestationsEmises('stagiaire'),
              value: valeur,
            ),
          );

      await recu('150');
      expect((await depot.charger()).attestationsEmises, 150);

      // Un zéro REÇU est un vrai zéro : le serveur a répondu « aucune ».
      await recu('0');
      expect((await depot.charger()).attestationsEmises, 0);
    });

    /// Ticket RH-4 : les quatre cartes de `gestion-paie.html` sont CALCULÉES comme `GestionPaie::getKpisProperty()`
    /// (masse = somme des bruts, CNSS = somme des retenues salariales, bulletins émis / en attente par l'existence
    /// d'un bulletin). Les charges patronales restent HORS de ces cartes, comme au web.
    test('les quatre cartes de paie sont celles du web', () async {
      await employe('e1', 'Koffi', 'ADJOVI', salaire: 120000);
      await employe('e2', 'Aline', 'DOSSOU', salaire: 95000);

      final p = await depot.paie(PersonnelRepository.periodeDe(aujourdhui));

      expect(p.masseSalariale, 215000);
      expect(p.bulletinsEmis, 0);
      expect(p.chargesCnss, closeTo(120000 * 0.036 + 95000 * 0.036, 0.02));
      expect(p.enAttente, 2);
    });

    testWidgets('les quatre cartes de paie portent les montants du mois', (
      tester,
    ) async {
      await employe('e1', 'Koffi', 'ADJOVI', salaire: 120000);

      await afficher(tester);
      await ouvrir(tester, 'Gestion de la Paie');

      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-paie-masse')),
          matching: find.text('120 000'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-paie-attente')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-paie-bulletins')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('le registre employés porte ses deux cartes', (tester) async {
      await employe(
        'e1',
        'Koffi',
        'ADJOVI',
        embauche: DateTime(aujourdhui.year, 2, 10),
      );

      await afficher(tester);

      expect(find.text('EMPLOYÉS ACTIFS'), findsOneWidget);
      expect(find.text('NOUVEAUX (ANNÉE)'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-employes-nouveaux')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('le registre stagiaires porte ses quatre cartes', (
      tester,
    ) async {
      await stagiaire('s1', 'Rachid', 'BIO', frais: 45000, regle: true);

      await afficher(tester);
      await ouvrir(tester, 'Registre Stagiaires');

      for (final libelle in [
        'STAGIAIRES ACTIFS',
        'FRAIS COLLECTÉS',
        'FRAIS EN ATTENTE',
        'ATTESTATIONS ÉMISES',
      ]) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }

      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-stagiaires-collectes')),
          matching: find.text('45 000'),
        ),
        findsOneWidget,
      );

      // ⚠️ Un tiret, jamais un zéro — cherché DANS sa carte.
      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-stagiaires-attestations')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });
  });

  group('écran', () {
    testWidgets('⚠️ les cinq onglets du hub sont là, dans son ordre', (
      tester,
    ) async {
      await afficher(tester);

      for (final onglet in [
        'Registre Employés',
        'Registre Stagiaires',
        'Feuille de Pointage',
        'Gestion de la Paie',
        'Attestations',
      ]) {
        expect(find.text(onglet), findsWidgets, reason: onglet);
      }
    });

    /// ⚠️⚠️ **LE NOMBRE DE CARTES, ONGLET PAR ONGLET** (ticket F0.54). Chaque
    /// onglet du hub est une page distincte de la maquette : le contrôle se fait
    /// donc page par page, sans arbitrage sur la répartition.
    testWidgets('⚠️⚠️ chaque onglet rend le nombre de cartes de sa page', (
      tester,
    ) async {
      await afficher(tester);

      const pages = <String, String>{
        'Registre Employés': 'registre-employes.html',
        'Registre Stagiaires': 'registre-stagiaires.html',
        'Feuille de Pointage': 'feuille-pointage.html',
        'Gestion de la Paie': 'gestion-paie.html',
      };

      for (final onglet in pages.keys) {
        await ouvrir(tester, onglet);
        expect(
          find.byType(CarteKpi),
          findsNWidgets(cartesAttendues(pages[onglet]!)),
          reason: onglet,
        );
      }
    });

    testWidgets('le registre porte les six colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      for (final colonne in [
        'NOM',
        'FONCTION',
        "DATE D'EMBAUCHE",
        'SALAIRE',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    /// RH-Q1 (décision client du 27/10/2026 : OUI) — le filtre « Archivé » du Blade liste les archivés, en lecture.
    testWidgets('RH-Q1 — le filtre « Archivé » liste les employés archivés, en lecture seule', (
      tester,
    ) async {
      await employe('e1', 'Kossi', 'AGBODJI', fonction: "Chef d'élevage");
      await employe('e2', 'Aline', 'DOSSOU', fonction: 'Gardien');
      await (db.update(db.employees)..where((t) => t.id.equals(uuid('e2')))).write(const EmployeesCompanion(isActive: Value(false)));

      await afficher(tester);

      // Par défaut : les actifs seuls, et la carte compte les actifs.
      expect(find.text('Kossi AGBODJI'), findsOneWidget);
      expect(find.text('Aline DOSSOU'), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('kpi-employes-actifs')), matching: find.text('1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('employes-filtre')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archivé').last);
      await tester.pumpAndSettle();

      expect(find.text('Aline DOSSOU'), findsOneWidget);
      expect(find.text('Kossi AGBODJI'), findsNothing);
      expect(find.text('Archivé'), findsWidgets);
      expect(find.byKey(const Key('employe-lecture-seule-0')), findsOneWidget);
      expect(find.byKey(const Key('employe-modifier-0')), findsNothing);
      expect(find.byKey(const Key('employe-archiver-0')), findsNothing);
    });

    testWidgets('un employé descendu est nommé avec sa fonction', (
      tester,
    ) async {
      await employe(
        'e1',
        'Kossi',
        'AGBODJI',
        fonction: 'Chef d\'élevage',
        salaire: 120000,
      );

      await afficher(tester);

      expect(find.text('Kossi AGBODJI'), findsOneWidget);
      expect(find.text('Chef d\'élevage'), findsOneWidget);
      expect(find.text('120 000'), findsOneWidget);
    });

    testWidgets('les stagiaires portent les six colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Registre Stagiaires');

      for (final colonne in [
        'NOM',
        "ÉTABLISSEMENT D'ORIGINE",
        'PÉRIODE',
        'FRAIS DE SCOLARITÉ',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    /// Ticket RH-2 : un stagiaire a ses ABSENCES (modale « Absences »), pas de pointage — comme au web.
    testWidgets('un stagiaire est listé avec son établissement et ses absences', (
      tester,
    ) async {
      await stagiaire('s1', 'Ange', 'TOSSOU', ecole: 'Lycée Agricole de Sékou');

      await afficher(tester);
      await ouvrir(tester, 'Registre Stagiaires');

      expect(find.text('Ange TOSSOU'), findsOneWidget);
      expect(find.text('Lycée Agricole de Sékou'), findsOneWidget);
      expect(find.byKey(const Key('stagiaire-absences-0')), findsOneWidget);
    });

    testWidgets('le pointage porte les six colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Feuille de Pointage');

      for (final colonne in [
        'EMPLOYÉ',
        'DATE',
        'ARRIVÉE',
        'DÉPART',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    /// ⚠️ Le serveur sert « 07:05:00 », la maquette affiche « 07:05 ».
    testWidgets('⚠️ les heures sont affichées sans les secondes', (
      tester,
    ) async {
      await employe('e1', 'Kossi', 'AGBODJI');
      await pointageServeur('p1', cleEmploye: 'e1', statut: 'present');

      await afficher(tester);
      await ouvrir(tester, 'Feuille de Pointage');

      expect(find.text('07:05'), findsOneWidget);
      expect(find.text('17:05'), findsOneWidget);
    });

    /// ⚠️⚠️ LE CHEMIN COMPLET : pointer depuis la modale de la maquette.
    testWidgets('⚠️⚠️ un pointage saisi apparaît et se dit en attente', (
      tester,
    ) async {
      await employe('e1', 'Kossi', 'AGBODJI');

      await afficher(tester);
      await ouvrir(tester, 'Feuille de Pointage');

      await tester.tap(find.byKey(const Key('ouvrir-pointage')));
      await tester.pumpAndSettle();

      expect(find.text('Enregistrer un Pointage'), findsWidgets);

      await tester.tap(find.text('Enregistrer').last);
      await tester.pumpAndSettle();

      expect(find.text('Pas encore envoyé'), findsOneWidget);
      expect(
        find.textContaining('il partira à la prochaine synchronisation'),
        findsOneWidget,
      );
    });

    testWidgets('la paie porte les neuf colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Gestion de la Paie');

      for (final colonne in [
        'EMPLOYÉ',
        'POSTE',
        'SALAIRE BRUT',
        'ABSENCES',
        'RET. ABSENCES',
        'RET. CNSS',
        'NET À PAYER',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    /// Ticket RH-4 : le brut ET le net (même formule que le serveur, `paie_parite_php_test.dart`), avec la mention
    /// qu'un ITS nul faute de barème n'est pas un ITS nul par seuil.
    testWidgets('la paie montre le brut, le net et le dit quand le barème manque', (
      tester,
    ) async {
      await employe('e1', 'Kossi', 'AGBODJI', salaire: 120000);

      await afficher(tester);
      await ouvrir(tester, 'Gestion de la Paie');

      expect(find.byKey(const Key('paie-brut-0')), findsOneWidget);
      expect(find.text('120 000'), findsWidgets);
      // 120 000 − CNSS 3,6 % = 115 680 ; sans barème, ITS = 0.
      expect(find.text('115 680'), findsOneWidget);
      expect(find.textContaining('Barème ITS non renseigné'), findsOneWidget);
    });

    /// ⚠️ SANS ACCÈS AU SERVEUR, L'ONGLET LE DIT au lieu de se taire. Le contenu
    /// de l'onglet (génération, modèles) est testé dans `attestations_test.dart`.
    testWidgets("⚠️ sans accès au serveur, l'onglet Attestations le dit", (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Attestations');

      expect(find.textContaining('aucune session ouverte'), findsOneWidget);
    });

    testWidgets('sans donnée, chaque tableau le dit', (tester) async {
      await afficher(tester);
      expect(find.text('— Aucun employé —'), findsWidgets);

      await ouvrir(tester, 'Registre Stagiaires');
      expect(find.text('— Aucun stagiaire —'), findsOneWidget);

      await ouvrir(tester, 'Feuille de Pointage');
      expect(find.text('— Aucun pointage —'), findsOneWidget);
    });
  });
}
