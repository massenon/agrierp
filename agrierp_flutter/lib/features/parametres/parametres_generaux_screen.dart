import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import 'parametres_generaux_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/parametres-hub.html` → Paramètres Général.
///
/// ⚠️⚠️ **HUB À SIX ONGLETS**, dans l'ordre du hub : Rôles & Permissions
/// (`roles-permissions.html`) · Données de l'Entreprise (`parametres.html`) ·
/// Modules Actifs (`modules-actifs.html`) · Gestion Utilisateurs
/// (`gestion-utilisateurs.html`) · Modes de Paiement (`modes-paiement.html`) ·
/// Audit Logs (`audit-logs.html`).
///
/// ⚠️⚠️ **AUCUN SECRET NE DESCEND AU POSTE.** `company_settings` porte côté
/// serveur les mots de passe SMTP et les jetons SMS (Twilio, Vonage), chiffrés.
/// Un poste volé donnerait accès au compte SMS et à la boîte mail de la ferme :
/// seuls l'identité et les taux sont servis, et le poste n'a **pas de colonne**
/// où ranger un secret. Le bloc « Configuration Email (SMTP) » de
/// `parametres.html` n'est donc pas porté — pas « plus tard », jamais.
///
/// ⚠️ **CONSULTATION PURE.** Modifier un rôle, une permission, un utilisateur
/// ou un compte de trésorerie depuis un poste changerait les règles de toute la
/// ferme depuis une machine qui n'a pas les derniers mouvements.
class ParametresGenerauxScreen extends StatefulWidget {
  const ParametresGenerauxScreen({super.key, required this.depot});

  final ParametresGenerauxRepository depot;

  /// Les six onglets du hub, dans son ordre.
  static const onglets = <(String, IconData)>[
    ('Rôles & Permissions', SymbolesAgri.admin_panel_settings),
    ("Données de l'Entreprise", SymbolesAgri.domain),
    ('Modules Actifs', SymbolesAgri.tune),
    ('Gestion Utilisateurs', SymbolesAgri.manage_accounts),
    ('Modes de Paiement', SymbolesAgri.account_balance_wallet),
    ('Audit Logs', SymbolesAgri.security),
  ];

  /// ⚠️⚠️ **ONZE COLONNES, PAS TROIS.** `roles-permissions.html` ne liste pas
  /// des permissions en toutes lettres : c'est une MATRICE, un rôle par ligne
  /// et un module par colonne. Rendue en liste, elle perd exactement ce qui
  /// fait sa lecture — comparer deux rôles d'un coup d'œil sur un module.
  static const colonnesMatrice = <(String, int)>[
    ('Rôle', 4),
    ('Dashboard', 2),
    ('Ventes & Devis', 2),
    ('Achats & Charges', 2),
    ('Stocks', 2),
    ('Élevage & Soins', 2),
    ('RH', 2),
    ('Comptabilité', 2),
    ('Administration', 2),
    ('Paramètres', 2),
    ('Actions', 2),
  ];

  /// Permission serveur qui décide de chacune des NEUF colonnes de module.
  ///
  /// ⚠️ **`null` POUR DASHBOARD, ET C'EST LA MAQUETTE QUI LE DIT** : aucune
  /// permission `view-dashboard` n'existe côté serveur, et `dashboard.html`
  /// figure dans les quatre listes de `RBAC_PAGE_MAP`. Le tableau de bord est
  /// l'écran commun à tous les rôles.
  ///
  /// ⚠️ L'alignement avec [colonnesMatrice] est vérifié par un test : une
  /// colonne ajoutée sans sa permission décalerait toute la ligne d'une case,
  /// et la matrice mentirait sans rien signaler.
  static const permissionsMatrice = <String?>[
    null,
    'view-ventes',
    'view-achats',
    'view-stocks',
    'view-elevage',
    'view-rh',
    'view-comptabilite',
    'view-administration',
    'view-parametres',
  ];

  @override
  State<ParametresGenerauxScreen> createState() =>
      _ParametresGenerauxScreenState();
}

class _ParametresGenerauxScreenState extends State<ParametresGenerauxScreen> {
  String _onglet = ParametresGenerauxScreen.onglets.first.$1;
  DonneesParametresGeneraux? _donnees;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    if (!mounted) return;
    setState(() => _donnees = donnees);
  }

  @override
  Widget build(BuildContext context) {
    final d = _donnees;

    return Scaffold(
      backgroundColor: AgriColors.surfaceBg,
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final large = AgriBreakpoints.large(context);

                return SingleChildScrollView(
                  padding: EdgeInsets.all(
                    large ? AgriSpacing.lg : AgriSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _barreOnglets(),
                      const SizedBox(height: AgriSpacing.lg),
                      switch (_onglet) {
                        "Données de l'Entreprise" => _ongletEntreprise(
                          d,
                          large,
                        ),
                        'Modules Actifs' => _ongletModules(d, large),
                        'Gestion Utilisateurs' => _ongletUtilisateurs(d, large),
                        'Modes de Paiement' => _ongletPaiement(d, large),
                        'Audit Logs' => _ongletAudit(d, large),
                        _ => _ongletRoles(d, large),
                      },
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _barreOnglets() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (titre, icone) in ParametresGenerauxScreen.onglets)
            InkWell(
              key: Key('onglet-parametres-generaux-$titre'),
              onTap: () => setState(() => _onglet = titre),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AgriSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icone,
                      size: 18,
                      color: _onglet == titre
                          ? AgriColors.brandEmerald
                          : AgriColors.outline,
                    ),
                    const SizedBox(width: AgriSpacing.xs),
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: AgriTypography.gras,
                        color: _onglet == titre
                            ? AgriColors.brandEmerald
                            : AgriColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  // ── Onglet 1 : Rôles & Permissions ────────────────────────────────────────

  Widget _ongletRoles(DonneesParametresGeneraux d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entete(
        'Rôles & Permissions',
        "Matrice de droits d'accès et sauvegardes de la base de données.",
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      _grilleKpis(large, [
        CarteKpi(
          libelle: 'Rôles configurés',
          valeur: '${d.roles.length}',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.shield,
        ),
        CarteKpi(
          libelle: 'Utilisateurs assignés',
          valeur: '${d.utilisateurs.length}',
          couleurLisere: AgriColors.infoBlue,
          icone: SymbolesAgri.group,
          couleurIcone: AgriColors.infoBlue,
        ),
        CarteKpi(
          libelle: 'Modules couverts',
          valeur: '${ParametresGenerauxScreen.permissionsMatrice.length}',
          couleurLisere: AgriColors.brandForest,
          icone: SymbolesAgri.apps,
          couleurIcone: AgriColors.brandForest,
        ),
        // ⚠️ LES SAUVEGARDES NE DESCENDENT PAS : ce sont des fichiers `.sql`
        // de plusieurs dizaines de méga-octets, produits et gardés sur le
        // serveur. Une date inventée ici laisserait croire que le poste sait
        // quand la ferme a été sauvegardée pour la dernière fois.
        const CarteKpi(
          libelle: 'Dernière sauvegarde',
          valeur: '—',
          legende: 'Sauvegardes gardées sur le serveur',
          couleurLisere: AgriColors.outline,
          icone: SymbolesAgri.backup,
          couleurIcone: AgriColors.outline,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _sousTitre("Matrice des Droits d'Accès"),
      const SizedBox(height: AgriSpacing.sm),
      _tableau(
        largeur: 1180,
        colonnes: ParametresGenerauxScreen.colonnesMatrice,
        vide: '— Aucun rôle synchronisé —',
        lignes: [
          for (var i = 0; i < d.roles.length; i++)
            _ligne(i, [
              (
                Text(
                  d.roles[i].name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandEmerald,
                  ),
                ),
                4,
              ),
              for (final permission
                  in ParametresGenerauxScreen.permissionsMatrice)
                (_droit(_accorde(d.roles[i], permission)), 2),
              (_actionInerte(), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ LE NOMBRE DE RÔLES EST UNE CONTRADICTION CONNUE DU PROJET : le CDC
      // en annonce 7, l'énumération 6, la matrice du CDC 5, la maquette en
      // affiche 5 nommés (Directeur Général, Comptable, Caissière POS, Chef
      // d'élevage, Support Technique) et le serveur en porte 4. Le poste montre
      // CE QUE LE SERVEUR APPLIQUE — le reste est un arbitrage client ouvert
      // qu'il n'appartient pas à un écran de trancher.
      _mentionPoste(
        'La matrice montre les rôles que le SERVEUR applique réellement, avec '
        'leurs permissions — la maquette, elle, en dessine cinq nommés. Cet '
        'écart est un arbitrage client ouvert. Créer ou modifier un rôle, comme '
        'générer une sauvegarde, se fait sur la surface web.',
        cle: 'roles',
      ),
    ],
  );

  /// Un rôle accorde-t-il ce module ?
  ///
  /// ⚠️ `admin` porte toutes les permissions nommées : rien n'est présumé, la
  /// liste descend telle quelle du serveur.
  bool _accorde(RolesApplicatif role, String? permission) {
    // Le tableau de bord n'a pas de permission : il est l'écran commun.
    if (permission == null) return true;

    final accordees = (role.permissions ?? '')
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);

    return accordees.contains(permission);
  }

  Widget _droit(bool accorde) => Align(
    alignment: Alignment.centerLeft,
    child: Icon(
      accorde ? SymbolesAgri.check_circle : SymbolesAgri.remove,
      size: 16,
      color: accorde ? AgriColors.brandEmerald : AgriColors.outline,
    ),
  );

  // ── Onglet 2 : Données de l'Entreprise ────────────────────────────────────

  Widget _ongletEntreprise(DonneesParametresGeneraux d, bool large) {
    final e = d.entreprise;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entete(
          "Données de l'Entreprise",
          'Identité légale, fiscale et configuration technique de la Ferme '
              'École OLOUWACHEGOUN.',
          large,
        ),
        const SizedBox(height: AgriSpacing.md),
        if (e == null)
          _mentionPoste(
            "Identité de la ferme non synchronisée — aucun tirage n'a encore "
            "eu lieu. L'afficher vide laisserait croire à une fiche vide côté "
            'serveur.',
            cle: 'entreprise-absente',
          )
        else ...[
          _fiche(
            cle: const Key('bloc-informations-generales'),
            titre: 'Informations Générales',
            champs: [
              ('Raison Sociale', e.companyName),
              ('Nom du Promoteur', e.promoterName),
              ("Adresse du Siège d'Exploitation", e.address),
              ('Téléphone Principal', e.phone),
              ('Email de Contact', e.email),
            ],
          ),
          const SizedBox(height: AgriSpacing.md),
          _fiche(
            cle: const Key('bloc-informations-legales'),
            titre: 'Informations Légales & Fiscales',
            champs: [
              ('Identifiant Fiscal Unique (IFU)', e.ifu),
              ('Registre du Commerce (RCCM)', e.rccm),
            ],
            pied:
                'Ces informations apparaissent sur toutes les factures '
                'normalisées MeCeF et les documents officiels générés par '
                'AgriERP.',
          ),
        ],
        const SizedBox(height: AgriSpacing.md),
        // ⚠️⚠️ LA CONFIGURATION TECHNIQUE N'EST PAS « À FAIRE PLUS TARD ».
        // SMTP porte un mot de passe : le descendre ferait d'un poste volé une
        // clé d'accès à la messagerie de la ferme. Le logo et le favicon, eux,
        // se téléversent — le poste n'a pas de canal pour remonter un fichier.
        _mentionPoste(
          "Serveur d'envoi (SMTP), logo et favicon ne descendent pas au "
          'poste : le premier porte un mot de passe, les deux autres se '
          "téléversent. Un poste perdu ne doit pas ouvrir la boîte mail de la "
          'ferme. Ces réglages se font sur la surface web.',
          cle: 'entreprise-technique',
        ),
      ],
    );
  }

  Widget _fiche({
    required Key cle,
    required String titre,
    required List<(String, String?)> champs,
    String? pied,
  }) => Container(
    key: cle,
    padding: const EdgeInsets.all(AgriSpacing.lg),
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      boxShadow: AgriShadows.sm,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sousTitre(titre),
        const SizedBox(height: AgriSpacing.md),
        for (final (libelle, valeur) in champs) _champ(libelle, valeur),
        if (pied != null) ...[
          const SizedBox(height: AgriSpacing.xs),
          Text(
            pied,
            style: const TextStyle(fontSize: 10, color: AgriColors.outline),
          ),
        ],
      ],
    ),
  );

  Widget _champ(String libelle, String? valeur) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          child: Text(
            libelle.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: AgriTypography.gras,
              color: AgriColors.outline,
            ),
          ),
        ),
        Expanded(
          child: Text(
            valeur == null || valeur.isEmpty ? '—' : valeur,
            style: const TextStyle(
              fontSize: AgriTypography.sm,
              color: AgriColors.onSurface,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Onglet 3 : Modules Actifs ─────────────────────────────────────────────

  /// Le sous-titre de chaque module, mot pour mot comme la maquette.
  static const _descriptionsModules = <ModuleEspece, String>{
    ModuleEspece.cuniculture: 'Fiches, VMS, catalogue POS liés aux lapins',
    ModuleEspece.aviculture: 'Fiches, VMS, catalogue POS liés aux volailles',
    ModuleEspece.porciculture: 'Fiches, VMS, catalogue POS liés aux porcs',
    ModuleEspece.helico: 'Module en préparation — désactivé par défaut',
  };

  static const _iconesModules = <ModuleEspece, IconData>{
    ModuleEspece.cuniculture: SymbolesAgri.cruelty_free,
    ModuleEspece.aviculture: SymbolesAgri.egg,
    ModuleEspece.porciculture: SymbolesAgri.pets,
    ModuleEspece.helico: SymbolesAgri.bug_report,
  };

  Widget _ongletModules(DonneesParametresGeneraux d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entete(
        'Modules Actifs',
        "Activez ou désactivez indépendamment chaque espèce d'élevage. La "
            'désactivation masque les menus et onglets concernés, sans jamais '
            'toucher à la comptabilité générale.',
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      for (final module in ModuleEspece.values)
        Padding(
          padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
          child: Container(
            key: Key('module-${module.code}'),
            padding: const EdgeInsets.all(AgriSpacing.md),
            decoration: BoxDecoration(
              color: AgriColors.surfaceCard,
              border: Border.all(color: AgriColors.outlineVariant),
              borderRadius: BorderRadius.circular(AgriRadius.lg),
              boxShadow: AgriShadows.sm,
            ),
            child: Row(
              children: [
                Icon(
                  _iconesModules[module],
                  size: 24,
                  color: d.moduleActif(module)
                      ? AgriColors.brandEmerald
                      : AgriColors.outline,
                ),
                const SizedBox(width: AgriSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              module.libelle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: AgriTypography.sm,
                                fontWeight: AgriTypography.gras,
                                color: AgriColors.brandForest,
                              ),
                            ),
                          ),
                          // ⚠️ « FUTUR » est le mot de la maquette, porté tel
                          // quel : l'héliciculture n'est pas éteinte par
                          // accident, elle n'est pas encore exploitée.
                          if (module == ModuleEspece.helico) ...[
                            const SizedBox(width: AgriSpacing.sm),
                            // ⚠️ EN GRIS, PAS EN JAUNE. Le jaune d'accent sur
                            // blanc est précisément le défaut de contraste
                            // corrigé sur la surface web au ticket 14.79 : le
                            // reproduire ici rendrait la pastille illisible.
                            _pastille('FUTUR', couleur: AgriColors.outline),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _descriptionsModules[module]!,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AgriColors.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AgriSpacing.sm),
                Icon(
                  d.moduleActif(module) ? SymbolesAgri.toggle_on : SymbolesAgri.toggle_off,
                  size: 28,
                  color: d.moduleActif(module)
                      ? AgriColors.brandEmerald
                      : AgriColors.outline,
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: AgriSpacing.sm),
      // ⚠️⚠️ CE RÉGLAGE PILOTE CE QUE LE POSTE MONTRE. Une espèce éteinte
      // disparaît des cartes de « Gestion Élevage » et des onglets de « Suivi
      // Reproduction », comme la maquette masque ses blocs `data-module`. Le
      // poste l'ignorait : il proposait la fiche Escargots d'une ferme qui
      // n'élève pas d'escargots.
      _mentionPoste(
        'Ces réglages sont appliqués immédiatement sur tous les onglets de '
        'Gestion Élevage et du Dashboard Élevage. Les données déjà '
        "enregistrées d'une espèce désactivée restent conservées et "
        'réapparaissent dès la réactivation du module. Le réglage lui-même se '
        'fait sur la surface web.',
        cle: 'modules',
      ),
    ],
  );

  // ── Onglet 4 : Gestion Utilisateurs ───────────────────────────────────────

  Widget _ongletUtilisateurs(DonneesParametresGeneraux d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entete(
        'Gestion des Utilisateurs',
        "Administration des comptes d'accès à AgriERP.",
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      _grilleKpis(large, [
        CarteKpi(
          libelle: 'Utilisateurs actifs',
          valeur: '${d.utilisateursActifs}',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.group,
        ),
        CarteKpi(
          libelle: 'Rôles définis',
          valeur: '${d.roles.length}',
          couleurLisere: AgriColors.infoBlue,
          icone: SymbolesAgri.badge,
          couleurIcone: AgriColors.infoBlue,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 900,
        colonnes: const [
          ('Nom', 5),
          ('Email', 5),
          ('Rôle', 4),
          ('Statut', 3),
          ('Actions', 2),
        ],
        vide: '— Aucun utilisateur synchronisé —',
        lignes: [
          for (var i = 0; i < d.utilisateurs.length; i++)
            _ligne(i, [
              (
                Text(
                  d.utilisateurs[i].name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                5,
              ),
              (
                Text(
                  d.utilisateurs[i].email ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                5,
              ),
              (
                Text(
                  d.utilisateurs[i].role ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              // ⚠️ « Désactivé » est le mot de la maquette — pas « Suspendu »,
              // pas « Inactif ». Un compte désactivé n'est jamais supprimé :
              // l'archivage logique est la règle du projet.
              (
                _pastille(
                  d.utilisateurs[i].isActive ? 'Actif' : 'Désactivé',
                  couleur: d.utilisateurs[i].isActive
                      ? AgriColors.brandEmerald
                      : AgriColors.outline,
                ),
                3,
              ),
              (_actionInerte(), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ NI MOT DE PASSE NI JETON NE DESCENDENT. La liste sert à savoir QUI
      // travaille sur la ferme ; l'authentification du poste passe par
      // `POST /api/auth/login`, contre le serveur.
      _mentionPoste(
        'La liste dit qui travaille sur la ferme — jamais comment se '
        'connecter : aucun mot de passe ni jeton ne descend. Créer un compte, '
        'archiver un utilisateur ou réinitialiser un mot de passe se fait sur '
        'la surface web.',
        cle: 'utilisateurs',
      ),
    ],
  );

  // ── Onglet 5 : Modes de Paiement ──────────────────────────────────────────

  /// Les trois familles de comptes, dans l'ordre de la maquette, avec le
  /// `type` que le serveur leur donne.
  static const _famillesTresorerie = <(String, String, IconData)>[
    ('Caisse Physique (531)', 'caisse', SymbolesAgri.payments),
    (
      'Comptes Bancaires - Multi-Banques (521)',
      'banque',
      SymbolesAgri.account_balance,
    ),
    (
      'Mobile Money - Multi-Opérateurs (5212)',
      'mobile_money',
      SymbolesAgri.smartphone,
    ),
  ];

  Widget _ongletPaiement(DonneesParametresGeneraux d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entete(
        'Modes de Paiement',
        'Comptes de trésorerie (Classe 5 SYSCOHADA) : caisse, banques et '
            'mobile money.',
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      _sousTitre('Résumé des comptes de trésorerie'),
      const SizedBox(height: AgriSpacing.sm),
      _grilleKpis(large, [
        CarteKpi(
          libelle: 'Solde Caisse (531)',
          valeur: _montant(d.soldeDe('caisse')),
          unite: 'F',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.payments,
        ),
        CarteKpi(
          libelle: 'Solde Banques (521)',
          valeur: _montant(d.soldeDe('banque')),
          unite: 'F',
          couleurLisere: AgriColors.infoBlue,
          icone: SymbolesAgri.account_balance,
          couleurIcone: AgriColors.infoBlue,
        ),
        CarteKpi(
          libelle: 'Solde Mobile Money (5212)',
          valeur: _montant(d.soldeDe('mobile_money')),
          unite: 'F',
          couleurLisere: AgriColors.brandForest,
          icone: SymbolesAgri.smartphone,
          couleurIcone: AgriColors.brandForest,
        ),
      ]),
      const SizedBox(height: AgriSpacing.lg),
      for (final (titre, type, icone) in _famillesTresorerie) ...[
        Row(
          children: [
            Icon(icone, size: 18, color: AgriColors.brandForest),
            const SizedBox(width: AgriSpacing.xs),
            Expanded(child: _sousTitre(titre)),
          ],
        ),
        const SizedBox(height: AgriSpacing.sm),
        if (d.comptesDe(type).isEmpty)
          _vide('— Aucun compte de ce type synchronisé —')
        else
          for (final compte in d.comptesDe(type)) _carteCompte(compte),
        const SizedBox(height: AgriSpacing.md),
      ],
      // ⚠️⚠️ UN VIREMENT ENTRE COMPTES PASSE UNE ÉCRITURE. La maquette permet
      // d'ajouter un compte bancaire ou une ligne mobile money : c'est ouvrir
      // un compte du plan SYSCOHADA, pas cocher une case — et le poste n'a
      // aucun canal pour le remonter.
      _mentionPoste(
        'Les soldes sont ceux du dernier tirage. Ajouter un compte bancaire ou '
        'une ligne mobile money ouvre un compte du plan SYSCOHADA, et un '
        'virement entre comptes passe une écriture : les deux se font sur la '
        'surface web.',
        cle: 'paiement',
      ),
    ],
  );

  Widget _carteCompte(TreasuryAccount compte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
    child: Container(
      key: Key('compte-tresorerie-${compte.id}'),
      padding: const EdgeInsets.all(AgriSpacing.md),
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        boxShadow: AgriShadows.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        compte.accountCode == null
                            ? compte.label
                            : '${compte.label} - ${compte.accountCode}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AgriTypography.sm,
                          fontWeight: AgriTypography.gras,
                          color: AgriColors.brandForest,
                        ),
                      ),
                    ),
                    const SizedBox(width: AgriSpacing.sm),
                    _pastille('Actif'),
                  ],
                ),
                const SizedBox(height: 2),
                // ⚠️ NI RIB, NI IBAN, NI NUMÉRO DE LIGNE : ces coordonnées ne
                // descendent pas. La maquette les affiche sur la surface web,
                // où l'on sait qui est devant l'écran.
                Text(
                  'Compte ${compte.accountCode ?? '—'}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AgriColors.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          Text(
            '${_montant(compte.balance)} FCFA',
            style: const TextStyle(
              fontSize: AgriTypography.sm,
              fontWeight: AgriTypography.gras,
              color: AgriColors.onSurface,
            ),
          ),
        ],
      ),
    ),
  );

  // ── Onglet 6 : Audit Logs ─────────────────────────────────────────────────

  Widget _ongletAudit(DonneesParametresGeneraux d, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _entete(
        'Audit Logs & Sécurité',
        'Historique horodaté des actions sensibles effectuées dans AgriERP.',
        large,
      ),
      const SizedBox(height: AgriSpacing.md),
      _grilleKpis(large, [
        // ⚠️⚠️ « 24 h » SE COMPTE DEPUIS MAINTENANT, PAS DEPUIS LE TIRAGE. Si
        // le dernier tirage remonte à plus de 24 h, le compte serait
        // structurellement nul : afficher « 0 » dirait « rien ne s'est passé
        // sur la ferme » alors que le poste ne sait simplement rien. Le tiret
        // le dit, la légende l'explique.
        CarteKpi(
          libelle: 'Événements (24h)',
          valeur: d.auditRecent ? '${d.evenements24h}' : '—',
          legende: d.auditRecent ? null : 'Dernier tirage il y a plus de 24 h',
          couleurLisere: AgriColors.brandEmerald,
          icone: SymbolesAgri.history,
        ),
        CarteKpi(
          libelle: 'Connexions échouées',
          valeur: '${d.connexionsEchouees}',
          legende: 'Sur les traces reçues',
          couleurLisere: d.connexionsEchouees > 0
              ? AgriColors.errorRed
              : AgriColors.outline,
          icone: SymbolesAgri.lock,
          couleurIcone: d.connexionsEchouees > 0
              ? AgriColors.errorRed
              : AgriColors.outline,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      _tableau(
        largeur: 980,
        colonnes: const [
          ('Horodatage', 3),
          ('Utilisateur', 4),
          ('Action', 5),
          ('Module', 3),
          ('Actions', 3),
        ],
        vide: '— Aucune trace synchronisée —',
        lignes: [
          for (var i = 0; i < d.audit.length; i++)
            _ligne(i, [
              (Text(_dateHeure(d.audit[i].createdAt), style: _cellule), 3),
              (
                Text(
                  d.audit[i].userName ?? 'Inconnu',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              (
                Text(
                  d.audit[i].action,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                  ),
                ),
                5,
              ),
              (
                Text(
                  d.audit[i].module ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              // La maquette écrit « Lecture seule » dans cette colonne : une
              // trace d'audit ne se modifie ni ne s'efface, par définition.
              (
                const Text(
                  'Lecture seule',
                  style: TextStyle(fontSize: 10, color: AgriColors.outline),
                ),
                3,
              ),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ CENT LIGNES, PAS TOUT L'HISTORIQUE : la table grossit d'une ligne
      // par action et n'a d'intérêt, au poste, que pour les dernières.
      _mentionPoste(
        'Les cent dernières actions de la ferme. La trace complète vit sur le '
        "serveur : elle grossit d'une ligne à chaque opération, et un poste "
        "n'a pas à en porter des années. L'export du journal se fait sur la "
        'surface web.',
        cle: 'audit',
      ),
    ],
  );

  // ── Briques communes ──────────────────────────────────────────────────────

  static const _cellule = TextStyle(fontSize: AgriTypography.xs);

  static const _enteteColonne = TextStyle(
    fontSize: 10,
    fontWeight: AgriTypography.gras,
    color: AgriColors.outline,
  );

  Widget _entete(String titre, String sousTitre, bool large) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _titre(titre, large),
      const SizedBox(height: 2),
      Text(
        sousTitre,
        style: const TextStyle(
          fontSize: AgriTypography.xs,
          color: AgriColors.outline,
        ),
      ),
    ],
  );

  Widget _titre(String texte, bool large) => Text(
    texte,
    style: TextStyle(
      fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
      fontWeight: AgriTypography.gras,
      color: AgriColors.onSurface,
    ),
  );

  Widget _sousTitre(String texte) => Text(
    texte,
    style: const TextStyle(
      fontSize: AgriTypography.sm,
      fontWeight: AgriTypography.gras,
      color: AgriColors.brandForest,
    ),
  );

  Widget _vide(String texte) => Padding(
    padding: const EdgeInsets.only(bottom: AgriSpacing.sm),
    child: Text(
      texte,
      style: const TextStyle(
        fontSize: AgriTypography.xs,
        fontStyle: FontStyle.italic,
        color: AgriColors.outline,
      ),
    ),
  );

  Widget _pastille(String libelle, {Color couleur = AgriColors.brandEmerald}) =>
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          libelle,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            fontWeight: AgriTypography.gras,
            color: couleur,
          ),
        ),
      );

  Widget _grilleKpis(bool large, List<Widget> cartes) => GridView.count(
    crossAxisCount: large ? cartes.length : 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AgriSpacing.md,
    crossAxisSpacing: AgriSpacing.md,
    childAspectRatio: large ? 2.4 : 1.6,
    children: cartes,
  );

  Widget _tableau({
    required double largeur,
    required List<(String, int)> colonnes,
    required List<Widget> lignes,
    required String vide,
  }) => Container(
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: largeur,
        child: Column(
          children: [
            Container(
              color: AgriColors.surfaceZebra,
              padding: const EdgeInsets.symmetric(
                horizontal: AgriSpacing.md,
                vertical: AgriSpacing.sm,
              ),
              child: Row(
                children: [
                  for (final (libelle, flex) in colonnes)
                    Expanded(
                      flex: flex,
                      child: Text(
                        libelle.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: _enteteColonne,
                      ),
                    ),
                ],
              ),
            ),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AgriSpacing.lg),
                child: Text(
                  vide,
                  style: const TextStyle(
                    fontSize: AgriTypography.xs,
                    fontStyle: FontStyle.italic,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            ...lignes,
          ],
        ),
      ),
    ),
  );

  Widget _ligne(int index, List<(Widget, int)> cellules) => Container(
    key: Key('ligne-$index'),
    color: index.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.md,
      vertical: AgriSpacing.sm,
    ),
    child: Row(
      children: [
        for (final (contenu, flex) in cellules)
          Expanded(flex: flex, child: contenu),
      ],
    ),
  );

  Widget _actionInerte() => const Opacity(
    opacity: 0.4,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Icon(SymbolesAgri.visibility, size: 16, color: AgriColors.outline),
    ),
  );

  /// ⚠️ CHAQUE MENTION PORTE SA PROPRE CLÉ : l'onglet Entreprise en affiche
  /// DEUX quand aucun tirage n'a eu lieu, et deux clés identiques dans une
  /// même colonne lèvent « Duplicate keys found » — l'écran cesse alors de se
  /// peindre, sans que l'analyseur n'ait rien vu.
  Widget _mentionPoste(String texte, {required String cle}) => Container(
    key: Key('mention-$cle'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: AgriColors.accentYellow.withValues(alpha: 0.10),
      border: Border.all(
        color: AgriColors.accentYellow.withValues(alpha: 0.30),
      ),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(SymbolesAgri.info, size: 18, color: AgriColors.brandForest),
        const SizedBox(width: AgriSpacing.sm),
        Expanded(
          child: Text(
            texte,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.brandForest,
            ),
          ),
        ),
      ],
    ),
  );

  static String _montant(double valeur) {
    final entier = valeur.round().abs().toString();
    final morceaux = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      morceaux.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${valeur.round() < 0 ? '-' : ''}${morceaux.join(' ')}';
  }

  static String _dateHeure(DateTime? d) => d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year} '
            '${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}';
}
