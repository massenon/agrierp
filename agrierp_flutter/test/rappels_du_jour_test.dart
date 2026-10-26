import 'dart:convert';
import 'dart:math';

import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/core/auth/verrou_inactivite.dart';
import 'package:agrierp/core/auth/verrou_local.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/rappels_du_jour_modale.dart';
import 'package:agrierp/features/elevage/rappels_du_jour_ouverture.dart';
import 'package:agrierp/features/elevage/rappels_du_jour_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/verrou/porte_session.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

/// Tickets POP2 / POP3 — LA FENÊTRE « RAPPELS DU JOUR » AU POSTE (PRD `docs/prd/popup-rappels.md`, règle R-RAPPELS-01).
///
/// Même jeu d'exemple que `RappelsDuJourTest` du serveur, calculé à la main, jour fixé au 14/10/2026, N = 3 :
///   LAP-A (cuniculture, mise en lot 10/10 : le 14/10 est J5)
///     soin « Vaccin Newcastle » le 12/10 → En retard (2 jours) ; « Déparasitage » le 14/10 → Aujourd'hui ;
///     « Vitamines » le 17/10 → À venir (dans 3 jours) ; « Trop tard » le 18/10 → absent (4 jours > N).
/// Ordre attendu : Vaccin Newcastle, Déparasitage, Vitamines. La parité avec le PHP du serveur est EXÉCUTÉE dans
/// `rappels_du_jour_parite_php_test.dart`.
void main() {
  late AppDatabase db;
  late RappelsDuJourRepository depot;
  final jour = DateTime(2026, 10, 14, 10);
  var n = 0;

  String id(String p) => '$p${(++n).toString().padLeft(4, '0')}-1111-4111-8111-111111111111';

  Future<String> bande(String code, String espece, DateTime miseEnLot, {String statut = 'actif'}) async {
    final lotId = id('aaaa');
    await db.into(db.livestockLots).insert(
      LivestockLotsCompanion.insert(
        id: lotId,
        code: code,
        speciesId: 'esp-$espece',
        speciesCode: Value(espece),
        stage: const Value('croissance'),
        createdDate: Value(miseEnLot),
        initialQuantity: const Value(100),
        currentQuantity: const Value(100),
        status: Value(statut),
        isActive: const Value(true),
      ),
    );
    return lotId;
  }

  Future<void> soin(String lotId, String tache, DateTime date, {String statut = 'planned'}) =>
      db.into(db.veterinaryCalendarEvents).insert(
        VeterinaryCalendarEventsCompanion.insert(
          id: id('bbbb'),
          deviceId: 'poste-test',
          updatedAt: jour,
          lotId: lotId,
          taskType: tache,
          scheduledDate: date,
          status: Value(statut),
        ),
      );

  late String lapA;

  Future<void> jeuDExemple() async {
    await soin(lapA, 'Trop tard', DateTime(2026, 10, 18));
    await soin(lapA, 'Vitamines', DateTime(2026, 10, 17));
    await soin(lapA, 'Déparasitage', DateTime(2026, 10, 14));
    await soin(lapA, 'Vaccin Newcastle', DateTime(2026, 10, 12));
  }

  Future<void> reglerDelai(int? jours) => db.into(db.companySettings).insertOnConflictUpdate(
    CompanySettingsCompanion.insert(id: const Value('unique'), rappelSoinsJours: Value(jours)),
  );

  Future<void> module(String code, bool actif) => db.into(db.modulesConfig).insertOnConflictUpdate(
    ModulesConfigCompanion.insert(id: '$code-0000-0000-0000-000000000000'.substring(0, 36), speciesCode: code, isEnabled: Value(actif)),
  );

  Future<void> standard(String traitement, int jourDeCycle, String produit, {bool actif = true}) =>
      db.into(db.prophylaxisScheduleStandards).insert(
        ProphylaxisScheduleStandardsCompanion.insert(
          id: id('5555'),
          speciesCode: 'cuniculture',
          periodLabel: 'J$jourDeCycle',
          cycleDayStart: Value(jourDeCycle),
          cycleDayEnd: Value(jourDeCycle),
          treatment: traitement,
          productRecommended: Value(produit),
          isActive: Value(actif),
        ),
      );

  Future<void> remanence(String lotId, String produit, DateTime fin) =>
      db.into(db.veterinaryWithdrawalPeriods).insert(
        VeterinaryWithdrawalPeriodsCompanion.insert(id: id('cccc'), lotId: lotId, productUsed: Value(produit), endDate: fin),
      );

  List<String> libelles(RappelsDuJour r) => [for (final l in r.lignes) l.libelle];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = RappelsDuJourRepository(database: db, soins: SoinsRepository(database: db, deviceId: 'poste-test'));
    await module('cuniculture', true);
    await module('aviculture', true);
    for (final (code, libelle) in [('cuniculture', 'Lapins'), ('aviculture', 'Volailles')]) {
      await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: id('eeee'), code: code, label: libelle));
    }
    lapA = await bande('LAP-A', 'cuniculture', DateTime(2026, 10, 10));
  });

  tearDown(() => db.close());

  group('Règle R-RAPPELS-01 — calcul local', () {
    test('jeu d\'exemple du PRD : urgences, échéances et ordre', () async {
      await jeuDExemple();
      final r = await depot.calculer(quand: jour);

      expect(libelles(r), ['Vaccin Newcastle', 'Déparasitage', 'Vitamines'], reason: 'le soin à 4 jours (> N) est absent');
      expect([for (final l in r.lignes) l.urgence], [UrgenceRappel.retard, UrgenceRappel.aujourdhui, UrgenceRappel.avenir]);
      expect([for (final l in r.lignes) l.jours], [-2, 0, 3]);
      expect([for (final l in r.lignes) l.echeance], ['En retard de 2 jours', "Aujourd'hui", 'Dans 3 jours']);
      expect(r.lignes.first.bande, 'LAP-A');
      expect(r.lignes.first.dateTexte, '12/10/2026');
      expect(r.lignes.first.type, TypeRappel.soin);
      expect(r.joursRappel, 3, reason: 'aucun réglage tiré : 3 jours par défaut (R-SOINS-01)');
    });

    test('le délai est celui du réglage rappel_soins_jours', () async {
      await jeuDExemple();
      await reglerDelai(0);
      expect(libelles(await depot.calculer(quand: jour)), ['Vaccin Newcastle', 'Déparasitage']);
      await reglerDelai(4);
      expect(libelles(await depot.calculer(quand: jour)), ['Vaccin Newcastle', 'Déparasitage', 'Vitamines', 'Trop tard']);
    });

    test('un soin réalisé ou en cours et une bande clôturée ne rappellent rien', () async {
      await soin(lapA, 'Réalisé', DateTime(2026, 10, 14), statut: 'done');
      await soin(lapA, 'En cours', DateTime(2026, 10, 14), statut: 'inprogress');
      final close = await bande('LAP-X', 'cuniculture', DateTime(2026, 9, 1), statut: 'cloture');
      await soin(close, 'Bande close', DateTime(2026, 10, 14));
      expect((await depot.calculer(quand: jour)).vide, isTrue);
    });

    test('une espèce désactivée (Modules Actifs) ne génère aucun rappel', () async {
      final volailles = await bande('AVI-A', 'aviculture', DateTime(2026, 10, 1));
      await soin(lapA, 'Soin lapins', DateTime(2026, 10, 14));
      await soin(volailles, 'Soin volailles', DateTime(2026, 10, 14));
      await module('aviculture', false);
      expect(libelles(await depot.calculer(quand: jour)), ['Soin lapins']);
      await module('cuniculture', false);
      expect((await depot.calculer(quand: jour)).vide, isTrue);
    });

    test('traitement du barème : du jour et à venir, sauf déjà administré, archivé ou hors horizon', () async {
      await standard('Vermifuge', 5, 'Ivomec');
      await standard('Vaccin VHD', 6, 'Filavac');
      await standard('Hors horizon', 9, 'X');
      await standard('Archivé', 7, 'Y', actif: false);

      var r = await depot.calculer(quand: jour);
      expect(libelles(r), ['Vermifuge', 'Vaccin VHD']);
      expect([for (final l in r.lignes) l.urgence], [UrgenceRappel.aujourdhui, UrgenceRappel.avenir]);
      expect([for (final l in r.lignes) l.type], [TypeRappel.prophylaxie, TypeRappel.prophylaxie]);
      expect([for (final l in r.lignes) l.produit], ['Ivomec', 'Filavac']);
      expect(r.lignes[1].echeance, 'Dans 1 jour');

      await db.into(db.veterinaryRecords).insert(
        VeterinaryRecordsCompanion.insert(
          id: id('dddd'), deviceId: 'poste-test', updatedAt: jour, lotId: lapA, actionType: 'Vermifuge', recordDate: DateTime(2026, 10, 14),
        ),
      );
      r = await depot.calculer(quand: jour);
      expect(libelles(r), ['Vaccin VHD'], reason: 'déjà administré : plus un rappel (redoser la bande)');
    });

    test('fin de délai d\'attente dans l\'horizon', () async {
      await remanence(lapA, 'Ivermectine', DateTime(2026, 10, 14));
      await remanence(lapA, 'Oxytétracycline', DateTime(2026, 10, 17));
      await remanence(lapA, 'Trop loin', DateTime(2026, 10, 24));
      await remanence(lapA, 'Terminée', DateTime(2026, 9, 8));
      final r = await depot.calculer(quand: jour);
      expect([for (final l in r.lignes) l.type], [TypeRappel.remanence, TypeRappel.remanence]);
      expect([for (final l in r.lignes) l.produit], ['Ivermectine', 'Oxytétracycline']);
      expect([for (final l in r.lignes) l.urgence], [UrgenceRappel.aujourdhui, UrgenceRappel.avenir]);
      expect(libelles(r), ["Fin du délai d'attente", "Fin du délai d'attente"]);
    });

    test('tri : urgence, puis date croissante, puis code de bande', () async {
      final autre = await bande('AVI-A', 'aviculture', DateTime(2026, 10, 1));
      await soin(lapA, 'À venir B', DateTime(2026, 10, 16));
      await soin(lapA, 'Retard récent', DateTime(2026, 10, 13));
      await soin(autre, "Aujourd'hui B", DateTime(2026, 10, 14));
      await soin(autre, 'Retard ancien', DateTime(2026, 10, 10));
      await soin(lapA, "Aujourd'hui A", DateTime(2026, 10, 14));
      await soin(autre, 'À venir A', DateTime(2026, 10, 15));
      expect(libelles(await depot.calculer(quand: jour)), [
        'Retard ancien', 'Retard récent', "Aujourd'hui B", "Aujourd'hui A", 'À venir A', 'À venir B',
      ]);
    });

    test('droits : seuls les rôles qui voient Soins et vaccins (view-elevage) reçoivent la liste', () async {
      await jeuDExemple();
      expect((await depot.pourRole('animalier', quand: jour)).lignes, hasLength(3));
      expect((await depot.pourRole('admin', quand: jour)).lignes, hasLength(3));
      expect((await depot.pourRole('caissier', quand: jour)).vide, isTrue);
      expect((await depot.pourRole(null, quand: jour)).vide, isTrue);
    });
  });

  group('Ouverture — masquage du jour, fenêtre vide, erreur silencieuse', () {
    late CoffreMemoire coffre;
    late OuvertureRappels ouverture;

    setUp(() {
      coffre = CoffreMemoire();
      ouverture = OuvertureRappels(depot: depot, reglage: ReglageRappels(coffre: coffre));
    });

    test('rappels présents : la fenêtre est à montrer', () async {
      await jeuDExemple();
      final r = await ouverture.aMontrer(idUtilisateur: 'u1', role: 'animalier', quand: jour);
      expect(r, isNotNull);
      expect(r!.lignes, hasLength(3));
    });

    test('rien à afficher : pas de fenêtre (jamais une fenêtre vide)', () async {
      expect(await ouverture.aMontrer(idUtilisateur: 'u1', role: 'animalier', quand: jour), isNull);
    });

    test('le caissier ne reçoit pas la fenêtre', () async {
      await jeuDExemple();
      expect(await ouverture.aMontrer(idUtilisateur: 'u2', role: 'caissier', quand: jour), isNull);
    });

    test('« Ne plus afficher aujourd\'hui » : cet utilisateur, ce jour seulement', () async {
      await jeuDExemple();
      await ouverture.masquerAujourdhui('u1', quand: jour);
      expect(coffre.contenu.keys.single, 'agrierp.rappels.masque.u1', reason: 'préférence locale, au coffre, par utilisateur');
      expect(coffre.contenu.values.single, '2026-10-14');

      expect(await ouverture.aMontrer(idUtilisateur: 'u1', role: 'animalier', quand: jour), isNull);
      // Un autre utilisateur du même poste la reçoit toujours.
      expect(await ouverture.aMontrer(idUtilisateur: 'u3', role: 'animalier', quand: jour), isNotNull);
      // Le lendemain, elle revient.
      expect(
        await ouverture.aMontrer(idUtilisateur: 'u1', role: 'animalier', quand: DateTime(2026, 10, 15, 8)),
        isNotNull,
        reason: 'le soin du 17/10 est encore à venir le 15/10',
      );
    });

    test('une erreur de calcul est silencieuse : aucune fenêtre, aucune exception', () async {
      final casse = OuvertureRappels(depot: _DepotCasse(db), reglage: ReglageRappels(coffre: coffre));
      expect(await casse.aMontrer(idUtilisateur: 'u1', role: 'animalier', quand: jour), isNull);
    });

    test('un coffre illisible ne bloque rien : la fenêtre s\'affiche', () async {
      await jeuDExemple();
      final illisible = OuvertureRappels(depot: depot, reglage: ReglageRappels(coffre: _CoffreCasse()));
      expect(await illisible.aMontrer(idUtilisateur: 'u1', role: 'animalier', quand: jour), isNotNull);
    });
  });

  group('Fenêtre', () {
    Future<void> monter(WidgetTester tester, RappelsDuJour donnees, {VoidCallback? masquer, VoidCallback? soins}) async {
      tester.view.physicalSize = const Size(1200, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('ouvrir'),
                onPressed: () => montrerRappelsDuJour(
                  context,
                  donnees: donnees,
                  surMasquer: masquer ?? () {},
                  surOuvrirSoins: soins,
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('ouvrir')));
      await tester.pumpAndSettle();
    }

    late RappelsDuJour donnees;

    setUp(() async {
      await jeuDExemple();
      donnees = await depot.calculer(quand: jour);
    });

    testWidgets('titre, groupes par urgence, lignes et pied', (tester) async {
      await monter(tester, donnees);
      expect(find.text('Rappels du jour'), findsOneWidget);
      expect(find.text('En retard (1)'), findsOneWidget);
      expect(find.text("Aujourd'hui (1)"), findsOneWidget);
      expect(find.text('À venir (sous 3 jours) (1)'), findsOneWidget);
      expect(find.text('LAP-A (Lapins)'), findsNWidgets(3));
      expect(find.textContaining('Vaccin Newcastle'), findsOneWidget);
      expect(find.text('12/10/2026'), findsOneWidget);
      expect(find.text('En retard de 2 jours'), findsOneWidget);
      expect(find.text('Ouvrir Soins et vaccins'), findsOneWidget);
      expect(find.text('Plus tard'), findsOneWidget);
      expect(find.text("Ne plus afficher aujourd'hui"), findsOneWidget);
    });

    testWidgets('« Plus tard » ferme sans rien masquer', (tester) async {
      var masque = 0;
      await monter(tester, donnees, masquer: () => masque++);
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      expect(find.text('Rappels du jour'), findsNothing);
      expect(masque, 0);
    });

    testWidgets('« Ne plus afficher aujourd\'hui » masque puis ferme', (tester) async {
      var masque = 0;
      await monter(tester, donnees, masquer: () => masque++);
      await tester.tap(find.text("Ne plus afficher aujourd'hui"));
      await tester.pumpAndSettle();
      expect(find.text('Rappels du jour'), findsNothing);
      expect(masque, 1);
    });

    testWidgets('« Ouvrir Soins et vaccins » ferme et ouvre l\'écran', (tester) async {
      var ouvert = 0;
      await monter(tester, donnees, soins: () => ouvert++);
      await tester.tap(find.text('Ouvrir Soins et vaccins'));
      await tester.pumpAndSettle();
      expect(find.text('Rappels du jour'), findsNothing);
      expect(ouvert, 1);
    });
  });

  group('Porte de session — quand la fenêtre se déclenche', () {
    late CoffreMemoire coffre;
    late AuthService auth;
    late VerrouLocal verrou;
    late VerrouInactivite inactivite;
    late int ouvertures;
    late VoidCallback verrouiller;
    late VoidCallback deconnecter;

    setUp(() {
      coffre = CoffreMemoire();
      auth = AuthService(client: Dio(BaseOptions(baseUrl: 'http://serveur-feint')), deviceName: 'poste', coffre: coffre);
      verrou = VerrouLocal(coffre: coffre, alea: Random(3), iterations: 20);
      inactivite = VerrouInactivite(reglage: ReglageInactivite(coffre: coffre), verrou: verrou);
      ouvertures = 0;
      coffre.contenu['agrierp.token'] = 'jeton';
      coffre.contenu['agrierp.user'] = jsonEncode({
        'id': 'u1', 'name': 'Animalier', 'username': 'anim', 'email': 'a@x.bj', 'role': 'animalier', 'role_label': 'Animalier',
      });
    });

    Future<void> saisirPin(WidgetTester tester) async {
      for (final c in '1234'.split('')) {
        await tester.tap(find.byKey(Key('touche-$c')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('verrou-bouton')));
      await tester.pumpAndSettle();
    }

    Future<void> monter(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await verrou.definir('u1', '1234');
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => SurveillanceInactivite(controleur: inactivite, child: child!),
          home: PorteSession(
            auth: auth,
            verrou: verrou,
            inactivite: inactivite,
            surOuverture: (context) async => ouvertures++,
            ecranConnexion: (onConnecte) => Scaffold(body: TextButton(key: const Key('se-connecter'), onPressed: onConnecte, child: const Text('login'))),
            application: (v, d) {
              verrouiller = v;
              deconnecter = d;
              return const Scaffold(body: Text('APPLICATION'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('au lancement, après le PIN : une fois', (tester) async {
      await monter(tester);
      expect(ouvertures, 0, reason: 'pas avant le déverrouillage');
      await saisirPin(tester);
      expect(find.text('APPLICATION'), findsOneWidget);
      expect(ouvertures, 1);
    });

    testWidgets('pas à chaque déverrouillage : verrouillage manuel puis PIN', (tester) async {
      await monter(tester);
      await saisirPin(tester);
      verrouiller();
      await tester.pumpAndSettle();
      await saisirPin(tester);
      expect(find.text('APPLICATION'), findsOneWidget);
      expect(ouvertures, 1);
    });

    testWidgets('pas à chaque déverrouillage : verrouillage par inactivité puis PIN', (tester) async {
      await monter(tester);
      await saisirPin(tester);
      await tester.pump(const Duration(minutes: 6));
      await tester.pumpAndSettle();
      expect(find.text('Application verrouillée'), findsOneWidget);
      await saisirPin(tester);
      expect(find.text('APPLICATION'), findsOneWidget);
      expect(ouvertures, 1);
    });

    testWidgets('à chaque connexion : déconnexion puis nouvelle connexion', (tester) async {
      await monter(tester);
      await saisirPin(tester);
      deconnecter();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('se-connecter')));
      await tester.pumpAndSettle();
      expect(find.text('APPLICATION'), findsOneWidget);
      expect(ouvertures, 2);
    });

    testWidgets('une erreur de la fenêtre ne bloque pas l\'ouverture de l\'application', (tester) async {
      tester.view.physicalSize = const Size(1200, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await verrou.definir('u1', '1234');
      await tester.pumpWidget(
        MaterialApp(
          home: PorteSession(
            auth: auth,
            verrou: verrou,
            surOuverture: (context) async => throw StateError('calcul impossible'),
            ecranConnexion: (onConnecte) => const SizedBox(),
            application: (v, d) => const Scaffold(body: Text('APPLICATION')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await saisirPin(tester);
      expect(find.text('APPLICATION'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _DepotCasse extends RappelsDuJourRepository {
  _DepotCasse(AppDatabase db) : super(database: db, soins: SoinsRepository(database: db, deviceId: 'x'));

  @override
  Future<RappelsDuJour> calculer({DateTime? quand}) async => throw StateError('base illisible');
}

class _CoffreCasse extends CoffreMemoire {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('coffre inaccessible');
}
