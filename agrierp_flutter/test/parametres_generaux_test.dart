import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/elevage/gestion_elevage_repository.dart';
import 'package:agrierp/features/elevage/gestion_elevage_screen.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';
import 'package:agrierp/core/theme/symboles_agri.dart';

/// Ticket F0.51 — PARAMÈTRES GÉNÉRAL (`parametres-hub.html`, six onglets).
///
/// ⚠️⚠️ **AUCUN SECRET NE DESCEND AU POSTE.** Mots de passe SMTP et jetons SMS
/// restent sur le serveur : le poste n'a même pas de colonne où les ranger.
/// C'est vérifié ici sur le SCHÉMA, pas sur une intention — une colonne ajoutée
/// un jour par commodité ferait échouer ce test.
///
/// ⚠️⚠️ **`modules_config` DÉCIDE DES ESPÈCES VISIBLES.** L'héliciculture est
/// éteinte sur cette ferme et le poste proposait pourtant la fiche Escargots.
void main() {
  late AppDatabase db;
  late ParametresGenerauxRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ParametresGenerauxRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> entreprise() => db
      .into(db.companySettings)
      .insert(
        CompanySettingsCompanion.insert(
          id: const Value('unique'),
          companyName: const Value('Ferme École OLOUWACHEGOUN'),
          promoterName: const Value('OLOUKOUNLE Olouchégoun Hassimiyou'),
          address: const Value('Attan-Ewé, Ikpinlè, Adja-Ouèrè, Bénin'),
          ifu: const Value('3202601234567'),
          rccm: const Value('RB/ADJ/26 B 0123'),
        ),
      );

  Future<void> module(String code, {required bool actif}) => db
      .into(db.modulesConfig)
      .insert(
        ModulesConfigCompanion.insert(
          id: uuid(code),
          speciesCode: code,
          isEnabled: Value(actif),
        ),
      );

  Future<void> role(String nom, String permissions) => db
      .into(db.rolesApplicatifs)
      .insert(
        RolesApplicatifsCompanion.insert(
          id: uuid(nom),
          name: nom,
          permissions: Value(permissions),
        ),
      );

  Future<void> utilisateur(
    String cle,
    String nom, {
    String role = 'admin',
    bool actif = true,
  }) => db
      .into(db.utilisateurs)
      .insert(
        UtilisateursCompanion.insert(
          id: uuid(cle),
          deviceId: 'serveur',
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: const Value(SyncStatus.synced),
          name: nom,
          username: Value(cle),
          email: Value('$cle@fermeolouwachegoun.com'),
          role: Value(role),
          isActive: Value(actif),
        ),
      );

  Future<void> compte(
    String cle,
    String libelle,
    String code,
    String type,
    double solde,
  ) => db
      .into(db.treasuryAccounts)
      .insert(
        TreasuryAccountsCompanion.insert(
          id: uuid(cle),
          label: libelle,
          accountCode: Value(code),
          type: Value(type),
          balance: Value(solde),
        ),
      );

  Future<void> trace(
    String cle,
    String action, {
    DateTime? quand,
    String module = 'auth',
  }) => db
      .into(db.auditLogs)
      .insert(
        AuditLogsCompanion.insert(
          id: uuid(cle),
          userName: const Value('M. Olouchègoun'),
          action: action,
          module: Value(module),
          createdAt: Value(quand ?? DateTime.now()),
        ),
      );

  Future<void> fermeComplete() async {
    await entreprise();
    for (final code in ['cuniculture', 'aviculture', 'porciculture']) {
      await module(code, actif: true);
    }
    await module('helico', actif: false);
    await role(
      'admin',
      'view-ventes, view-achats, view-stocks, view-elevage, '
          'view-rh, view-comptabilite, view-administration, view-parametres',
    );
    await role('comptable', 'view-comptabilite, view-rapports');
    await utilisateur('u1', 'M. Olouchègoun');
    await utilisateur('u2', 'Ancien Stagiaire IT', actif: false);
    await compte('t1', 'Caisse Principale', '531', 'caisse', 185000);
    await compte('t2', 'BOA Bénin', '521101', 'banque', 1850000);
    await compte('t3', 'Ecobank Bénin', '521102', 'banque', 490000);
    await compte('t4', 'MTN MoMo', '521201', 'mobile_money', 62000);
  }

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 2400);
    tester.view.devicePixelRatio = 1;
    // La taille de vue survit au test qui l'a posee : sans remise a zero, un
    // ecran suivant se rend dans la fenetre du precedent et ses onglets
    // sortent du cadre — le tap tombe alors dans le vide, sans echouer.
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: ParametresGenerauxScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    // ⚠️ LA BARRE DES SIX ONGLETS DEFILE HORIZONTALEMENT, comme celle du hub :
    // le dernier onglet sort du cadre, et un `tap` hors cadre ne touche rien
    // sans faire echouer le test — il laisse simplement l'ecran sur l'onglet
    // precedent, et l'assertion suivante accuse le mauvais coupable.
    final cible = find.byKey(Key('onglet-parametres-generaux-$onglet'));
    await tester.ensureVisible(cible);
    await tester.pumpAndSettle();
    await tester.tap(cible);
    await tester.pumpAndSettle();
  }

  group('schéma', () {
    /// ⚠️⚠️ LA GARDE LA PLUS IMPORTANTE DU TICKET. `company_settings` porte
    /// côté serveur `smtp_password_encrypted`, `twilio_auth_token_encrypted` et
    /// `vonage_api_secret_encrypted`. Un poste volé ne doit pas ouvrir la boîte
    /// mail ni le compte SMS de la ferme : la table locale n'a AUCUNE colonne
    /// où un secret pourrait se ranger, et c'est ce que ce test verrouille.
    test('⚠️⚠️ aucune colonne du poste ne peut porter un secret', () {
      final colonnes = db.companySettings.$columns
          .map((c) => c.name.toLowerCase())
          .toList();

      for (final interdit in [
        'password',
        'secret',
        'token',
        'api_key',
        'apikey',
      ]) {
        expect(
          colonnes.where((c) => c.contains(interdit)),
          isEmpty,
          reason:
              'La table locale porte une colonne « $interdit » : un secret '
              'descendrait au poste, et un poste perdu ouvrirait le service '
              'correspondant.',
        );
      }
    });
  });

  group('dépôt', () {
    test('un module absent du tirage est considéré actif', () async {
      final d = await depot.charger();

      // ⚠️ ACTIF PAR DÉFAUT : masquer une espèce sur l'ignorance du poste
      // ferait disparaître le cheptel réel de la ferme.
      expect(d.moduleActif(ModuleEspece.cuniculture), isTrue);
      expect(d.especesActives.length, ModuleEspece.values.length);
    });

    test(
      '⚠️⚠️ un module éteint par le serveur disparaît des espèces',
      () async {
        await fermeComplete();

        final d = await depot.charger();

        expect(d.moduleActif(ModuleEspece.helico), isFalse);
        expect(d.especesActives, isNot(contains('helico')));
        expect(d.modulesActifs, 3);
      },
    );

    /// ⚠️ LA FERME A DEUX BANQUES : prendre le premier compte trouvé
    /// afficherait la moitié de la trésorerie réelle.
    test('le solde d une famille cumule tous ses comptes', () async {
      await fermeComplete();

      final d = await depot.charger();

      expect(d.soldeDe('banque'), 2340000);
      expect(d.comptesDe('banque').length, 2);
      expect(d.soldeDe('caisse'), 185000);
      expect(d.tresorerieTotale, 2587000);
    });

    /// ⚠️ Le nom technique, pas le libellé affiché : faire dépendre une alerte
    /// de sécurité d'une traduction serait une mauvaise plaisanterie.
    test('les connexions échouées se comptent sur login.failed', () async {
      await trace('a1', 'api.login');
      await trace('a2', 'login.failed');
      await trace('a3', 'login.failed');

      final d = await depot.charger();

      expect(d.connexionsEchouees, 2);
      expect(d.evenements24h, 3);
      expect(d.auditRecent, isTrue);
    });

    /// ⚠️⚠️ UN TIRAGE VIEUX DE PLUS DE 24 H NE VEUT PAS DIRE « RIEN NE S'EST
    /// PASSÉ ». Le compteur passe au tiret plutôt que d'afficher un zéro qui
    /// affirmerait le calme sur la ferme.
    test(
      '⚠️⚠️ un tirage ancien ne fait pas passer le compteur à zéro',
      () async {
        await trace(
          'a1',
          'api.login',
          quand: DateTime.now().subtract(const Duration(days: 4)),
        );

        final d = await depot.charger();

        expect(d.auditRecent, isFalse);
        expect(d.evenements24h, 0);
      },
    );

    test(
      'les traces sont rendues de la plus récente à la plus ancienne',
      () async {
        await trace(
          'a1',
          'ancienne',
          quand: DateTime.now().subtract(const Duration(hours: 5)),
        );
        await trace('a2', 'recente');

        final d = await depot.charger();

        expect(d.audit.first.action, 'recente');
      },
    );
  });

  group('écran', () {
    // Ticket CFG-2 — les six onglets de la maquette, plus « Email (SMTP) » et « Appairage » aux places que
    // le web donne à « Email (SMTP) » et « Postes & Appairage » (CFG-1). Ticket R-1 : « Réinitialisation » après
    // « Audit Logs », comme au web.
    testWidgets('les dix onglets du hub sont présents, dans son ordre', (
      tester,
    ) async {
      await fermeComplete();
      await afficher(tester);

      expect(ParametresGenerauxScreen.onglets.map((o) => o.$1).toList(), [
        'Rôles & Permissions',
        "Données de l'Entreprise",
        'Email (SMTP)',
        'Modules Actifs',
        'Gestion Utilisateurs',
        'Appairage',
        'Modes de Paiement',
        'Audit Logs',
        'Corbeille',
        'Réinitialisation',
      ]);

      for (final (titre, _) in ParametresGenerauxScreen.onglets) {
        expect(find.byKey(Key('onglet-parametres-generaux-$titre')), findsOne);
      }
    });

    /// ⚠️⚠️ ONZE COLONNES : un rôle par ligne, neuf modules, une colonne
    /// d'actions. Rendue en liste de permissions, la matrice perdrait ce qui
    /// fait sa lecture.
    /// ⚠️⚠️ **LE NOMBRE DE CARTES, ONGLET PAR ONGLET** (ticket F0.54). Chaque
    /// onglet du hub est une page distincte de la maquette : le contrôle se fait
    /// donc page par page, sans arbitrage sur la répartition.
    testWidgets('⚠️⚠️ chaque onglet rend le nombre de cartes de sa page', (
      tester,
    ) async {
      await afficher(tester);

      const pages = <String, String>{
        'Rôles & Permissions': 'roles-permissions.html',
        "Données de l'Entreprise": 'parametres.html',
        'Modules Actifs': 'modules-actifs.html',
        'Gestion Utilisateurs': 'gestion-utilisateurs.html',
        'Modes de Paiement': 'modes-paiement.html',
        'Audit Logs': 'audit-logs.html',
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

    testWidgets('la matrice porte les onze colonnes de la maquette', (
      tester,
    ) async {
      await fermeComplete();
      await afficher(tester);

      expect(ParametresGenerauxScreen.colonnesMatrice.length, 11);
      for (final (libelle, _) in ParametresGenerauxScreen.colonnesMatrice) {
        expect(find.text(libelle.toUpperCase()), findsOne);
      }
    });

    /// ⚠️⚠️ UNE COLONNE AJOUTÉE SANS SA PERMISSION DÉCALERAIT TOUTE LA LIGNE
    /// d'une case : la matrice mentirait sur les droits de chaque rôle sans
    /// que rien ne le signale.
    test('chaque colonne de module porte sa permission', () {
      expect(
        ParametresGenerauxScreen.permissionsMatrice.length,
        ParametresGenerauxScreen.colonnesMatrice.length - 2,
        reason:
            'Une colonne de module sans permission — ou une permission sans '
            'colonne — décale la matrice entière.',
      );
    });

    testWidgets('un rôle sans permission comptable ne porte pas la coche', (
      tester,
    ) async {
      await fermeComplete();
      await afficher(tester);

      // `comptable` : Dashboard (commun) + Comptabilité, rien d'autre.
      expect(find.byIcon(SymbolesAgri.check_circle), findsNWidgets(9 + 2));
    });

    testWidgets('⚠️ la dernière sauvegarde porte un tiret motivé', (
      tester,
    ) async {
      await fermeComplete();
      await afficher(tester);

      expect(find.text('DERNIÈRE SAUVEGARDE'), findsOne);
      expect(find.text('Sauvegardes gardées sur le serveur'), findsOne);
    });

    testWidgets("l'identité de la ferme est affichée avec ses libellés", (
      tester,
    ) async {
      await fermeComplete();
      await afficher(tester);
      await ouvrir(tester, "Données de l'Entreprise");

      expect(find.text('RAISON SOCIALE'), findsOne);
      expect(find.text('Ferme École OLOUWACHEGOUN'), findsOne);
      expect(find.text("ADRESSE DU SIÈGE D'EXPLOITATION"), findsOne);
      expect(find.text('3202601234567'), findsOne);
    });

    /// ⚠️ Sans tirage, l'écran DIT qu'il ne sait rien plutôt que d'afficher
    /// une fiche vide qui laisserait croire à une fiche vide côté serveur.
    testWidgets('⚠️ sans tirage, la fiche entreprise dit son ignorance', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, "Données de l'Entreprise");

      expect(
        find.byKey(const Key('bloc-informations-generales')),
        findsNothing,
      );
      expect(find.textContaining("aucun tirage n'a encore eu lieu"), findsOne);
    });

    testWidgets('les quatre modules sont affichés avec leur état', (
      tester,
    ) async {
      await fermeComplete();
      await afficher(tester);
      await ouvrir(tester, 'Modules Actifs');

      for (final module in ModuleEspece.values) {
        expect(find.byKey(Key('module-${module.code}')), findsOne);
      }
      expect(find.text('FUTUR'), findsOne);
      expect(find.byIcon(SymbolesAgri.toggle_on), findsNWidgets(3));
      expect(find.byIcon(SymbolesAgri.toggle_off), findsOne);
    });

    testWidgets('un utilisateur désactivé porte le mot de la maquette', (
      tester,
    ) async {
      await fermeComplete();
      await afficher(tester);
      await ouvrir(tester, 'Gestion Utilisateurs');

      expect(find.text('Actif'), findsOne);
      expect(find.text('Désactivé'), findsOne);
      expect(find.text('Ancien Stagiaire IT'), findsOne);
    });

    testWidgets('les trois familles de trésorerie sont rendues', (
      tester,
    ) async {
      await fermeComplete();
      await afficher(tester);
      await ouvrir(tester, 'Modes de Paiement');

      expect(find.text('Caisse Physique (531)'), findsOne);
      expect(find.text('Comptes Bancaires - Multi-Banques (521)'), findsOne);
      expect(find.text('Mobile Money - Multi-Opérateurs (5212)'), findsOne);
      // Les deux banques sont cumulées, pas la première seule.
      expect(find.text('2 340 000'), findsOne);
    });

    // 🔴→✅ Ticket U14 — l'onglet du Blade (`audit-logs.blade.php`, `AuditLogs.php`).
    test('U14 — connexions échouées sur 24 h, comme le web', () async {
      await trace('a1', 'login.failed');
      await trace('a2', 'login.failed', quand: DateTime.now().subtract(const Duration(days: 2)));

      expect((await depot.charger()).connexionsEchouees, 1);
    });

    test('U14 — « Rechercher... » : clés techniques de l action OU du module, comme `LIKE`', () async {
      await trace('a1', 'sale.created', module: 'ventes');
      await trace('a2', 'expense.archived', module: 'achats');
      await trace('a3', 'login.failed', module: 'auth');
      final lignes = (await depot.charger()).audit;
      List<String> chercher(String r) => [
        for (final l in DonneesParametresGeneraux.filtrerAudit(lignes, r)) l.action,
      ]..sort();

      expect(chercher('SALE'), ['sale.created']);
      expect(chercher('achat'), ['expense.archived'], reason: 'le module');
      expect(chercher('Vente enregistrée'), isEmpty, reason: 'le libellé n est pas cherché, comme au web');
      expect(chercher('e_p'), ['expense.archived'], reason: '`_` : un caractère');
      expect(chercher('0'), hasLength(3));
    });

    testWidgets('U14 — libellés, info-bulle, carte bleue « Sur les dernières 24 h », recherche à 300 ms, état vide', (
      tester,
    ) async {
      await fermeComplete();
      await trace('a1', 'sale.created', module: 'ventes');
      await trace('a2', 'login.failed', module: 'auth');
      await afficher(tester);
      await ouvrir(tester, 'Audit Logs');

      expect(find.text('Vente enregistrée'), findsOne, reason: '`action_label`');
      expect(find.text('Ventes & Devis'), findsOne, reason: '`module_label`');
      expect(find.text('sale.created'), findsNothing);
      expect(find.text('Sur les dernières 24 h'), findsOne);
      final carte = tester.widget<CarteKpi>(
        find.ancestor(of: find.text('CONNEXIONS ÉCHOUÉES'), matching: find.byType(CarteKpi)),
      );
      expect((carte.valeur, carte.couleurLisere), ('1', AgriColors.infoBlue));
      expect(
        find.byTooltip("Les journaux d'audit sont immuables : aucune modification ni suppression n'est possible."),
        findsNWidgets(2),
      );

      await tester.enterText(find.byKey(const Key('audit-recherche')), 'login');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Vente enregistrée'), findsOne, reason: 'pas avant 300 ms');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(find.text('Vente enregistrée'), findsNothing);

      await tester.enterText(find.byKey(const Key('audit-recherche')), 'zzz');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Aucun événement pour le moment.'), findsOne);
    });

    testWidgets('la trace d audit porte les cinq colonnes de la maquette', (
      tester,
    ) async {
      await fermeComplete();
      await trace('a1', 'Modification Plan Comptable', module: 'Comptabilité');
      await afficher(tester);
      await ouvrir(tester, 'Audit Logs');

      for (final colonne in [
        'HORODATAGE',
        'UTILISATEUR',
        'ACTION',
        'MODULE',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOne);
      }
      expect(find.text('Lecture seule'), findsOne);
    });

    /// ⚠️⚠️ LE DÉFAUT QUE CE TICKET CORRIGE : le poste proposait « Fiches
    /// Escargots » à une ferme dont l'héliciculture est éteinte. La carte
    /// menait à une fiche vide, sans dire pourquoi.
    ///
    /// Ticket H4 : le Blade fait foi — `gestion-elevage.blade.php` GRISE la
    /// carte (« Héliciculture — module désactivé ») au lieu de la masquer, et
    /// ne conditionne que l'héliciculture : la carte dit désormais pourquoi.
    testWidgets('⚠️⚠️ Gestion Élevage grise une espèce désactivée (Blade)', (
      tester,
    ) async {
      await fermeComplete();

      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: GestionElevageScreen(
            onOuvrir: (_) {},
            depot: GestionElevageRepository(database: db),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      final escargots = find.byKey(
        Key('carte-${EcranPoste.ficheEscargots.name}'),
      );
      expect(escargots, findsOne);
      expect(
        find.descendant(
          of: escargots,
          matching: find.text('Héliciculture — module désactivé'),
        ),
        findsOne,
      );
      // Les trois espèces exploitées restent, dont les DEUX fiches avicoles.
      expect(find.text('Fiches Lapins'), findsOne);
      expect(find.text('Fiches Pondeuses'), findsOne);
      expect(find.text('Fiches Volailles'), findsOne);
      expect(find.text('Fiches Porcs'), findsOne);
    });
  });

  group('accès', () {
    /// ⚠️⚠️ NI LE HUB NI SES SIX PAGES N'APPARAISSENT DANS `RBAC_PAGE_MAP` —
    /// vérifié dans `common.js`. La règle du prototype s'applique donc telle
    /// quelle : seul `admin`, dont la liste vaut `null`, y accède.
    test("⚠️⚠️ seul l'administrateur atteint les paramètres généraux", () {
      expect(
        PermissionsPoste.autorise('admin', EcranPoste.parametresGeneraux),
        isTrue,
      );

      for (final role in ['caissier', 'animalier', 'comptable']) {
        expect(
          PermissionsPoste.autorise(role, EcranPoste.parametresGeneraux),
          isFalse,
          reason:
              '$role atteindrait la matrice des droits et le journal d audit.',
        );
      }
    });
  });
}
