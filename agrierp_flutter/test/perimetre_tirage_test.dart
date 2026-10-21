import 'dart:io';

import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket S-T4 (méthode TATACORA) — AUCUN ÉCRAN AUTORISÉ N'EST PRIVÉ DE SES DONNÉES.
///
/// Le serveur ne sert plus à un compte que les tables dont il a l'usage : `SyncController::PERMISSIONS_DE_TIRAGE`
/// (Laravel), correspondance UNIQUE table tirée → permission(s) de lecture. Une table retirée à tort ne lève aucune
/// erreur : l'écran s'ouvre, vide ou périmé — un défaut silencieux. Ce test croise donc, LU DANS LE CODE SOURCE :
///  1. la correspondance du serveur (lue dans le PHP, aucune copie au poste) ;
///  2. les permissions de chaque rôle (`PermissionsPoste.permissionsDuRole`, elle-même comparée au seeder par le
///     test de H9b ; l'administrateur a toutes les permissions) ;
///  3. les écrans que chaque rôle ouvre (`PermissionsPoste.ecransDe`, la carte de la maquette) ;
///  4. les tables Drift que chaque écran lit : son fichier et ce qu'il importe (dépôts, services), transitivement
///     — les imports `show` (un type seulement) ne comptent pas, ni la base ni le moteur de synchronisation ;
///     une table est « lue » quand le code écrit `_db.<table>` / `db.` / `database.` ou `FROM` / `JOIN <table>` ;
///  5. les lecteurs transverses : la cloche (tous rôles) et la recherche globale (par domaine, avec les droits du
///     web : `RechercheGlobaleRepository.peut`).
/// ⚠️ L'analyse par imports SUR-APPROXIME (un dépôt importé est compté en entier) : elle peut exiger une table de
/// trop, jamais en oublier une — c'est le sens prudent.
///
/// Les tables propres au poste (saisies jamais tirées : ajustements, imputations… ; les dépenses sont tirées depuis
/// U13) sont listées ici ; toute
/// table Drift doit être soit tirée, soit dans cette liste : une table ajoutée au schéma impose une décision.
void main() {
  final php = File(
    '$dossierLaravel/app/Http/Controllers/Api/SyncController.php',
  );
  final saut = php.existsSync()
      ? null
      : 'SAUT : dépôt Laravel absent ($dossierLaravel) — correspondance du serveur illisible';

  /// Table tirée → table Drift qui la reçoit (`null` : un réglage local, pas une table).
  const tableDrift = <String, String?>{
    'products': 'products',
    'product_categories': 'product_categories',
    'livestock_lots': 'livestock_lots',
    'livestock_daily_entries': 'livestock_daily_entries',
    'livestock_transfers': 'livestock_transfers',
    'feed_ration_standards': 'feed_ration_standards',
    'growth_standards': 'growth_standards',
    'veterinary_withdrawal_periods': 'veterinary_withdrawal_periods',
    'prophylaxis_schedule_standards': 'prophylaxis_schedule_standards',
    'veterinary_records': 'veterinary_records',
    'infirmary_records': 'infirmary_records',
    'veterinary_calendar_events': 'veterinary_calendar_events',
    'livestock_reproduction_events': 'livestock_reproduction_events',
    'customers': 'customers',
    // Ticket DEV — devis (table mixte : saisie ET tirée), lus par l'onglet « Devis Prestations » de Ventes & Devis.
    'quotes': 'quotes',
    'receivables': 'receivables',
    'customer_advances': 'customer_advances',
    'customer_reminders': 'customer_reminders',
    'feed_types': 'feed_types',
    'elevage_numbering': 'elevage_numbering_settings',
    'suppliers': 'suppliers',
    'purchases': 'purchases',
    'purchase_lines': 'purchase_lines',
    'purchase_returns': 'purchase_returns',
    'supplier_credits': 'supplier_credits',
    'purchase_orders': 'purchase_orders',
    'payables': 'payables',
    'employees': 'employees',
    'internships': 'internships',
    'attendance_records': 'attendance_records',
    'mails': 'mails',
    'administrative_documents': 'administrative_documents',
    'archived_documents': 'archived_documents',
    'chart_of_accounts': 'chart_of_accounts',
    'fiscal_years': 'fiscal_years',
    'accounting_entries': 'accounting_entries',
    'accounting_entry_lines': 'accounting_entry_lines',
    'accounting_entry_ids': 'accounting_entries',
    'company_settings': 'company_settings',
    'modules_config': 'modules_config',
    'roles': 'roles_applicatifs',
    'users': 'utilisateurs',
    'audit_logs': 'audit_logs',
    'notifications': 'notifications',
    'lot_revenues': 'lot_revenues',
    'animals': 'animals',
    'livestock_species': 'livestock_species',
    'attestation_templates': 'attestation_templates',
    'attestation_counts': null,
    'sales': 'sales',
    'sale_lines': 'sale_lines',
    // Tickets AV1 / AV2 — retours et avoirs clients (table mixte : demandes saisies au poste ET avoirs tirés du serveur).
    'credit_notes': 'credit_notes',
    'stock_movements': 'stock_movements',
    'treasury_accounts': 'treasury_accounts',
    'expense_categories': 'expense_categories',
    // Ticket U13 — dépenses (table mixte : saisies au poste ET tirées) et paie réglée (lecture seule).
    'expenses': 'expenses',
    // Ticket DEP4 — lignes de dépense (avec leur dépense) et centres de coût (référentiel).
    'expense_lines': 'expense_lines',
    'cost_centers': 'cost_centers',
    'payslips': 'payslips',
  };

  /// Tables Drift propres au poste : saisies envoyées mais jamais tirées, file, réglages.
  const tablesLocales = {
    'stock_adjustments',
    'advance_imputations',
    'supplier_payments',
    'supplier_refunds',
    'sync_conflicts',
    'app_settings',
    'sync_state',
  };

  /// Fichier de chaque écran du poste (celui que `main.dart` construit pour lui).
  const fichierEcran = <EcranPoste, String>{
    EcranPoste.tableauDeBord: 'pilotage/tableau_de_bord_screen.dart',
    EcranPoste.gestionElevage: 'elevage/gestion_elevage_screen.dart',
    EcranPoste.dashboardElevage: 'elevage/dashboard_elevage_screen.dart',
    EcranPoste.suiviReproduction: 'elevage/suivi_reproduction_screen.dart',
    EcranPoste.ficheSujet: 'elevage/fiche_sujet_screen.dart',
    EcranPoste.soinsEtVaccins: 'elevage/soins_vaccins_screen.dart',
    EcranPoste.parametresElevage: 'elevage/parametres_elevage_screen.dart',
    EcranPoste.ficheElevage: 'elevage/fiche_lapins_screen.dart',
    EcranPoste.fichePondeuses: 'elevage/fiche_pondeuses_screen.dart',
    EcranPoste.fichePorcs: 'elevage/fiche_porcs_screen.dart',
    EcranPoste.ficheReproducteurs: 'elevage/fiche_reproducteurs_screen.dart',
    EcranPoste.ficheEscargots: 'elevage/fiche_escargots_screen.dart',
    EcranPoste.ventesEtDevis: 'ventes/ventes_devis_screen.dart',
    EcranPoste.clientsEtCreances: 'clients/clients_creances_screen.dart',
    EcranPoste.caisse: 'ventes/caisse_screen.dart',
    EcranPoste.achatsEtCommandes: 'achats/achats_commandes_screen.dart',
    EcranPoste.fournisseurs: 'achats/fournisseurs_screen.dart',
    EcranPoste.facturation: 'ventes/facturation_screen.dart',
    EcranPoste.personnelEtStages: 'rh/personnel_stages_screen.dart',
    EcranPoste.administrationEtDocument:
        'administration/administration_screen.dart',
    EcranPoste.comptabilite: 'comptabilite/comptabilite_screen.dart',
    EcranPoste.parametresGeneraux: 'parametres/parametres_generaux_screen.dart',
    EcranPoste.saisieDepenses: 'achats/saisie_depenses_screen.dart',
    EcranPoste.gestionStocks: 'stocks/gestion_stocks_screen.dart',
    EcranPoste.catalogueProduits: 'stocks/catalogue_produits_screen.dart',
    EcranPoste.rapportsEtExports: 'rapports/rapports_exports_screen.dart',
    EcranPoste.monProfil: 'profil/mon_profil_screen.dart',
    EcranPoste.notifications: 'notifications/notifications_screen.dart',
    EcranPoste.aideEtAPropos: 'aide/aide_a_propos_screen.dart',
    EcranPoste.contactEditeur: 'contact/contact_editeur_screen.dart',
    EcranPoste.synchronisation: 'sync/synchronisation_screen.dart',
    // CFG-2 : « Paramètres du poste » ouvre le hub Paramètres sur l'onglet Appairage.
    EcranPoste.parametres: 'parametres/parametres_generaux_screen.dart',
    EcranPoste.transfertsBandes: 'elevage/transferts_bandes_screen.dart',
    EcranPoste.gestionBandes: 'elevage/gestion_bandes_screen.dart',
    EcranPoste.enregistrerSujets: 'elevage/enregistrer_sujets_screen.dart',
    EcranPoste.registreReproducteurs: 'elevage/registre_reproducteurs_screen.dart',
  };

  /// Recherche globale de la barre supérieure (tous rôles) : tables lues PAR DOMAINE, sous la permission du web
  /// qui ouvre le domaine. Vérifié ci-dessous contre ce que le dépôt de la recherche lit réellement.
  /// Ticket EX1 — tables qu'un écran ne lit que SI le compte a le droit indiqué, le serveur le lui disant.
  /// « Synchronisation » : le contrôle « ouverture N+1 = clôture N » (S-T6) ne relit le journal du poste que si le
  /// serveur a servi `anouveaux` (`SupervisionSynchronisationController::coherence`, comptes `view-comptabilite`, ceux
  /// à qui le journal descend) ; `coherence_synchronisation_test.dart` vérifie qu'un compte sans ce droit n'y touche
  /// pas. Pour un compte qui a le droit, ces tables restent exigées.
  const lecturesConditionnelles = <EcranPoste, Map<String, Set<String>>>{
    EcranPoste.synchronisation: {
      'view-comptabilite': {
        'chart_of_accounts',
        'accounting_entries',
        'accounting_entry_lines',
      },
    },
  };

  const rechercheParPermission = <String, Set<String>>{
    'view-elevage': {
      'livestock_lots',
      'livestock_species',
      'livestock_reproduction_events',
      'veterinary_records',
    },
    'view-ventes': {'customers', 'sales'},
    'view-stocks': {'products'},
    'view-achats': {'suppliers', 'purchase_orders'},
    'view-comptabilite': {'accounting_entries', 'chart_of_accounts'},
    'view-rh': {'employees'},
  };

  /// Correspondance du serveur : table → permissions (`null` : servie à tout compte).
  Map<String, List<String>?> correspondance() {
    final source = php.readAsStringSync();
    final bloc = source
        .split('public const PERMISSIONS_DE_TIRAGE = [')[1]
        .split('];')
        .first;
    return {
      for (final m in RegExp(
        r"'(\w+)' => (null|\[([^\]]*)\]),",
      ).allMatches(bloc))
        m.group(1)!: m.group(2) == 'null'
            ? null
            : [
                for (final p in RegExp(r"'([\w-]+)'").allMatches(m.group(3)!))
                  p.group(1)!,
              ],
    };
  }

  /// Tables Drift du schéma : nom SQL par accesseur Dart (`livestockLots` → `livestock_lots`).
  Map<String, String> tablesDuSchema() {
    final source = File(
      'lib/core/database/app_database.dart',
    ).readAsStringSync();
    return {
      for (final m in RegExp(
        r'^class (\w+) extends Table',
        multiLine: true,
      ).allMatches(source))
        m.group(1)![0].toLowerCase() + m.group(1)!.substring(1): m
            .group(1)!
            .replaceAllMapped(RegExp(r'(?<!^)([A-Z])'), (x) => '_${x.group(1)}')
            .toLowerCase(),
    };
  }

  final schema = tablesDuSchema();

  Set<String> tablesLuesDans(String chemin) {
    final source = File(chemin).readAsStringSync();
    return {
      for (final MapEntry(key: accesseur, value: table) in schema.entries)
        if (RegExp(
              r'\b(?:_db|db|database|_database)\s*\.\s*' + accesseur + r'\b',
            ).hasMatch(source) ||
            RegExp(
              r'(?:FROM|JOIN|from|join)\s+' + table + r'\b',
            ).hasMatch(source))
          table,
    };
  }

  /// Le fichier et tout ce qu'il importe du poste, transitivement (sauf `show`, base et moteur).
  Set<String> fermeture(String chemin) {
    final vus = <String>{};
    final pile = [chemin];
    while (pile.isNotEmpty) {
      final f = pile.removeLast();
      if (!vus.add(f)) continue;
      final source = File(f).readAsStringSync();
      for (final m in RegExp(
        r"^import '([^']+)'(?! show)",
        multiLine: true,
      ).allMatches(source)) {
        final cible = m.group(1)!;
        if (cible.startsWith('package:') || cible.startsWith('dart:')) continue;
        // Sous Windows `toFilePath()` rend des `\\` : on normalise avant de chercher `lib/`.
        final resolu = File(f).parent.uri.resolve(cible).toFilePath().replaceAll('\\', '/');
        final relatif = resolu.substring(resolu.indexOf('lib/'));
        if (relatif.startsWith('lib/core/database/') ||
            relatif == 'lib/core/sync/sync_engine.dart') {
          continue;
        }
        if (File(relatif).existsSync()) pile.add(relatif);
      }
    }
    return vus;
  }

  Set<String> tablesLuesParEcran(EcranPoste ecran) => {
    for (final f in fermeture('lib/features/${fichierEcran[ecran]}'))
      ...tablesLuesDans(f),
  };

  /// Permissions du rôle : celles du seeder (copie du poste vérifiée par H9b) ; l'administrateur a tout.
  Set<String> permissionsDe(String role, Map<String, List<String>?> c) =>
      role == 'admin'
      ? {for (final l in c.values) ...?l}
      : PermissionsPoste.permissionsDuRole[role]!;

  Set<String> tablesDriftServies(String role, Map<String, List<String>?> c) {
    final permissions = permissionsDe(role, c);
    return {
      for (final MapEntry(:key, :value) in c.entries)
        if (value == null || value.any(permissions.contains)) ?tableDrift[key],
    };
  }

  test(
    'la correspondance du serveur nomme exactement les tables que le poste sait recevoir',
    () {
      final c = correspondance();
      expect(c.length, greaterThan(40), reason: 'correspondance illisible');
      expect(c.keys.toSet(), tableDrift.keys.toSet());

      // Et le moteur absorbe exactement ces clés-là (`_absorberPage`) : une table servie sans absorbeur serait
      // perdue, un absorbeur sans table serait mort.
      final moteur = File('lib/core/sync/sync_engine.dart').readAsStringSync();
      final page = moteur
          .split(
            'Future<int> _absorberPage(Map<String, dynamic> corps) async {',
          )[1]
          .split('\n  }\n')
          .first;
      final absorbees = {
        for (final m in RegExp(r"corps\['(\w+)'\]").allMatches(page))
          m.group(1)!,
      };
      expect(absorbees, c.keys.toSet());
    },
    skip: saut,
  );

  test('toute table Drift est soit tirée, soit propre au poste', () {
    final recues = {...tableDrift.values.whereType<String>()};
    expect(recues.intersection(tablesLocales), isEmpty);
    expect({...recues, ...tablesLocales}, schema.values.toSet());
  });

  test(
    'chaque écran du poste a son fichier, et l\'analyse y voit des tables',
    () {
      expect(fichierEcran.keys.toSet(), EcranPoste.values.toSet());
      for (final f in fichierEcran.values) {
        expect(File('lib/features/$f').existsSync(), isTrue, reason: f);
      }
      // Garde-fou de l'analyse elle-même : si elle ne voyait plus rien, le croisement serait vert à vide.
      expect(
        tablesLuesParEcran(EcranPoste.tableauDeBord),
        containsAll([
          'sales',
          'sale_lines',
          'purchases',
          'livestock_lots',
          'treasury_accounts',
        ]),
      );
      expect(
        tablesLuesParEcran(EcranPoste.fichePondeuses),
        containsAll(['stock_movements', 'veterinary_withdrawal_periods']),
      );
    },
  );

  test(
    'la recherche globale lit exactement les tables déclarées par domaine',
    () {
      expect(
        tablesLuesDans(
          'lib/features/recherche/recherche_globale_repository.dart',
        ),
        {for (final t in rechercheParPermission.values) ...t},
      );
    },
  );

  for (final role in ['caissier', 'animalier', 'comptable', 'admin']) {
    test(
      'rôle $role : toute table lue par un écran qu\'il ouvre lui est servie',
      () {
        final c = correspondance();
        final servies = tablesDriftServies(role, c);
        final manques = <String>[];

        for (final ecran in PermissionsPoste.ecransDe(role)) {
          // Lectures CONDITIONNELLES, sous le même droit que le serveur : elles n'ont lieu que si le compte l'a.
          final conditionnelles = {
            for (final MapEntry(key: permission, value: tables)
                in (lecturesConditionnelles[ecran] ?? const {}).entries)
              if (!PermissionsPoste.peut(role, permission)) ...tables,
          };
          final privees = tablesLuesParEcran(ecran)
              .difference(tablesLocales)
              .difference(servies)
              .difference(conditionnelles);
          if (privees.isNotEmpty) {
            manques.add('${ecran.name} : ${privees.join(', ')}');
          }
        }
        // La cloche (barre supérieure, tous rôles).
        final cloche = tablesLuesDans(
          'lib/features/notifications/notifications_repository.dart',
        ).difference(servies);
        if (cloche.isNotEmpty) manques.add('cloche : ${cloche.join(', ')}');
        // La recherche globale, domaine par domaine, avec les droits du web.
        for (final MapEntry(key: permission, value: tables)
            in rechercheParPermission.entries) {
          if (PermissionsPoste.peut(role, permission)) {
            final privees = tables.difference(servies);
            if (privees.isNotEmpty) {
              manques.add('recherche ($permission) : ${privees.join(', ')}');
            }
          }
        }

        expect(
          manques,
          isEmpty,
          reason: 'écrans autorisés privés de leurs données',
        );
      },
      skip: saut,
    );
  }

  test(
    'échantillon documenté : ce que le filtrage retire, et ce qu\'il ne doit jamais retirer',
    () {
      final c = correspondance();
      final caissier = tablesDriftServies('caissier', c);
      final animalier = tablesDriftServies('animalier', c);
      final comptable = tablesDriftServies('comptable', c);

      // Le tableau de bord, ouvert aux quatre rôles, lit les ventes, les achats et l'élevage : base pour tous.
      for (final role in [caissier, animalier, comptable]) {
        expect(
          role,
          containsAll([
            'sales',
            'sale_lines',
            'purchases',
            'purchase_lines',
            'livestock_daily_entries',
          ]),
        );
      }
      // La caisse du caissier bloque une vente sous rémanence : la rémanence lui est servie.
      expect(caissier, contains('veterinary_withdrawal_periods'));
      // La fiche Pondeuses (Tableau 3) lit le grand livre des stocks : servi à l'animalier, pas au caissier.
      expect(animalier, contains('stock_movements'));
      expect(caissier, isNot(contains('stock_movements')));
      // Le journal comptable ne descend qu'au comptable (et à l'administrateur) ; le personnel, à aucun des trois.
      expect(
        comptable,
        containsAll([
          'accounting_entries',
          'accounting_entry_lines',
          'chart_of_accounts',
        ]),
      );
      expect(caissier, isNot(contains('accounting_entries')));
      expect(animalier, isNot(contains('accounting_entries')));
      for (final role in [caissier, animalier, comptable]) {
        expect(role, isNot(contains('employees')));
        expect(role, isNot(contains('mails')));
      }
    },
    skip: saut,
  );
}
