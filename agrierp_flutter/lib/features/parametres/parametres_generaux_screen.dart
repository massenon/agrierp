import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../../core/audit/libelles_audit.dart';

import '../../core/config/envoi_email_test.dart';
import '../../core/config/parametres_smtp.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/carte_kpi.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/widgets/toast_agri.dart';
import 'appairage_poste.dart';
import 'corbeille_repository.dart';
import 'onglet_appairage.dart';
import 'onglet_corbeille.dart';
import 'onglet_email_smtp.dart';
import 'onglet_reinitialisation.dart';
import 'reglages_ferme_repository.dart';
import 'reglages_ferme_ui.dart';
import 'parametres_generaux_repository.dart';
import 'reinitialisation_poste.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/parametres-hub.html` → Paramètres Général.
///
/// ⚠️⚠️ **HUB À SIX ONGLETS**, dans l'ordre du hub : Rôles & Permissions
/// (`roles-permissions.html`) · Données de l'Entreprise (`parametres.html`) ·
/// Modules Actifs (`modules-actifs.html`) · Gestion Utilisateurs
/// (`gestion-utilisateurs.html`) · Modes de Paiement (`modes-paiement.html`) ·
/// Audit Logs (`audit-logs.html`).
///
/// 🔁 Ticket CFG-2 (décision client du 19/10/2026) — HUIT ONGLETS. Comme au web
/// (ticket CFG-1), « Email (SMTP) » suit « Données de l'Entreprise » et
/// l'appairage suit « Gestion Utilisateurs » ([OngletEmailSmtp],
/// [OngletAppairage]). L'onglet « Appairage » remplace l'écran isolé
/// « Paramètres du poste » : l'entrée de la barre latérale ouvre ce hub sur lui
/// ([ongletInitial]).
///
/// 🔁 Ticket ARC4 (demande du client : « une page pour afficher les enregistrements archivés et les restaurer ou les
/// supprimer définitivement, web et poste ») — DIX ONGLETS. « Corbeille » (ex-« Restauration » du web, absente du poste
/// jusqu'ici) s'insère entre « Audit Logs » et « Réinitialisation », comme au web ([OngletCorbeille]).
///
/// 🔁 Ticket R-1 (demande du client : « sur le web et le poste ») — NEUF ONGLETS.
/// « Réinitialisation » suit « Audit Logs », comme au web (où « Restauration »,
/// absent du poste, les sépare) : [OngletReinitialisation], en ligne seulement.
///
/// ⚠️⚠️ **AUCUN SECRET NE DESCEND AU POSTE.** `company_settings` porte côté
/// serveur les mots de passe SMTP et les jetons SMS (Twilio, Vonage), chiffrés.
/// Un poste volé donnerait accès au compte SMS et à la boîte mail de la ferme :
/// seuls l'identité et les taux sont servis, et le poste n'a **pas de colonne**
/// où ranger un secret. Le SMTP DU POSTE est un réglage LOCAL (onglet
/// « Email (SMTP) ») : son mot de passe va au coffre du système, jamais en base
/// (`ParametresSmtp`).
///
/// ⚠️ **CONSULTATION PURE.** Modifier un rôle, une permission, un utilisateur
/// ou un compte de trésorerie depuis un poste changerait les règles de toute la
/// ferme depuis une machine qui n'a pas les derniers mouvements.
class ParametresGenerauxScreen extends StatefulWidget {
  const ParametresGenerauxScreen({
    super.key,
    required this.depot,
    this.smtp,
    this.envoiEmail,
    this.appairage,
    this.reinitialisation,
    this.corbeille,
    this.ongletInitial,
    this.idUtilisateurConnecte,
    this.reglages,
    this.estAdmin = false,
  });

  final ParametresGenerauxRepository depot;

  /// Tickets PA-2/3/4/7/8 — les réglages de la ferme (entreprise, barème ITS, modes de paiement, rôles, SMS) écrits en
  /// DEMANDES ; `null` : les onglets restent en consultation (vues du châssis sans session).
  final ReglagesFermeRepository? reglages;

  /// Le compte connecté est administrateur (rôles, taux de paie et barème arrêtés).
  final bool estAdmin;

  /// Ticket UT-1 — le compte connecté sur ce poste : il ne peut pas s'archiver lui-même (règle du web).
  final String? idUtilisateurConnecte;

  /// Ticket CFG-2 — réglages SMTP de ce poste et e-mail de test ; `null` : l'onglet le dit.
  final ParametresSmtp? smtp;
  final EnvoiEmailTest? envoiEmail;

  /// Ticket CFG-2 — appairage de ce poste (session, réglages du poste) ; `null` : l'onglet le dit.
  final AppairagePoste? appairage;

  /// Ticket R-1 — réinitialisation des données par le serveur, puis purge de ce poste ; `null` : l'onglet le dit.
  final ReinitialisationPoste? reinitialisation;

  /// Ticket ARC4 — la Corbeille (demandes de restauration / de suppression définitive) ; `null` : l'onglet le dit.
  final CorbeilleRepository? corbeille;

  /// Onglet ouvert à l'arrivée (« Appairage » depuis l'entrée « Paramètres du poste ») ; le premier sinon.
  final String? ongletInitial;

  static const ongletEmailSmtp = 'Email (SMTP)';
  static const ongletAppairage = 'Appairage';
  static const ongletCorbeille = 'Corbeille';
  static const ongletReinitialisation = 'Réinitialisation';

  /// Les neuf onglets du hub, dans son ordre : les six de la maquette, plus « Email (SMTP) » et
  /// « Appairage » (CFG-2) aux places des onglets « Email (SMTP) » et « Postes & Appairage » du web, et
  /// « Réinitialisation » (R-1) après « Audit Logs », avec l'icône du web (`restart_alt`).
  static const onglets = <(String, IconData)>[
    ('Rôles & Permissions', SymbolesAgri.admin_panel_settings),
    ("Données de l'Entreprise", SymbolesAgri.domain),
    (ongletEmailSmtp, SymbolesAgri.mail),
    ('Modules Actifs', SymbolesAgri.tune),
    ('Gestion Utilisateurs', SymbolesAgri.manage_accounts),
    (ongletAppairage, SymbolesAgri.settings_applications),
    ('Modes de Paiement', SymbolesAgri.account_balance_wallet),
    ('Audit Logs', SymbolesAgri.security),
    (ongletCorbeille, SymbolesAgri.restore_from_trash),
    (ongletReinitialisation, SymbolesAgri.restart_alt),
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
  late String _onglet = ParametresGenerauxScreen.onglets
      .map((o) => o.$1)
      .firstWhere(
        (o) => o == widget.ongletInitial,
        orElse: () => ParametresGenerauxScreen.onglets.first.$1,
      );
  DonneesParametresGeneraux? _donnees;

  /// Sous-page de l'onglet « Données de l'Entreprise » : `bareme` (PA-7) ou `sms` (PA-8).
  String? _sousPage;
  List<String> _droits = const [];
  String? _message;

  /// Ticket U14 — « Rechercher... » de l'onglet Audit Logs (`wire:model.live.debounce.300ms="search"`).
  final _rechercheAudit = TextEditingController();
  String _filtreAudit = '';
  Timer? _attenteAudit;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _attenteAudit?.cancel();
    _rechercheAudit.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final donnees = await widget.depot.charger();
    final droits = await widget.reglages?.droits() ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _donnees = donnees;
      _droits = droits;
    });
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
                        "Données de l'Entreprise" when _sousPage == 'bareme' && widget.reglages != null =>
                          PageBaremeIts(depot: widget.reglages!, estAdmin: widget.estAdmin, surRetour: () => setState(() => _sousPage = null)),
                        "Données de l'Entreprise" when _sousPage == 'sms' && widget.reglages != null =>
                          PageIntegrationsSms(depot: widget.reglages!, surRetour: () => setState(() => _sousPage = null)),
                        "Données de l'Entreprise" => _ongletEntreprise(
                          d,
                          large,
                        ),
                        ParametresGenerauxScreen.ongletEmailSmtp =>
                          _ongletEmailSmtp(),
                        'Modules Actifs' => _ongletModules(d, large),
                        ParametresGenerauxScreen.ongletAppairage =>
                          _ongletAppairage(),
                        'Gestion Utilisateurs' => _ongletUtilisateurs(d, large),
                        'Modes de Paiement' => _ongletPaiement(d, large),
                        'Audit Logs' => _ongletAudit(d, large),
                        ParametresGenerauxScreen.ongletCorbeille =>
                          _ongletCorbeille(),
                        ParametresGenerauxScreen.ongletReinitialisation =>
                          _ongletReinitialisation(),
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
      Row(
        children: [
          Expanded(child: _sousTitre("Matrice des Droits d'Accès")),
          if (widget.reglages != null && widget.estAdmin)
            ElevatedButton.icon(
              key: const Key('role-nouveau'),
              onPressed: () => _ouvrirRole(null),
              icon: const Icon(SymbolesAgri.add, size: 18),
              style: ElevatedButton.styleFrom(backgroundColor: AgriColors.brandEmerald, foregroundColor: Colors.white, shape: const StadiumBorder()),
              label: const Text('Nouveau Rôle', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
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
              (_actionsRole(d.roles[i]), 2),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ LE NOMBRE DE RÔLES EST UNE CONTRADICTION CONNUE DU PROJET (CDC 7, énumération 6, matrice 5, serveur 4). Le poste montre
      // CE QUE LE SERVEUR APPLIQUE. Créer, modifier ou supprimer un rôle est une DEMANDE réservée à l'administrateur ; les
      // sauvegardes se génèrent et se téléchargent en ligne (ticket PA-6).
      _mentionPoste(
        'La matrice montre les rôles que le SERVEUR applique réellement, avec leurs permissions — la maquette, elle, en dessine '
        'cinq nommés. Cet écart est un arbitrage client ouvert. Créer, modifier ou supprimer un rôle est réservé à '
        "l'administrateur et s'applique à la prochaine synchronisation.",
        cle: 'roles',
      ),
    ],
  );

  Widget _actionsRole(RolesApplicatif r) {
    if (widget.reglages == null || !widget.estAdmin) return _actionInerte();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('role-modifier-${r.name}'),
          tooltip: 'Modifier',
          visualDensity: VisualDensity.compact,
          onPressed: () => _ouvrirRole(r),
          icon: const Icon(SymbolesAgri.edit, size: 16, color: AgriColors.brandEmerald),
        ),
        if (!ReglagesFermeRepository.rolesFondamentaux.contains(r.name))
          IconButton(
            key: Key('role-supprimer-${r.name}'),
            tooltip: 'Supprimer',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final motif = await widget.reglages!.supprimerRole(r.name, estAdmin: widget.estAdmin);
              if (!mounted) return;
              setState(() => _message = motif ?? 'Suppression demandée au serveur : elle sera appliquée à la prochaine synchronisation.');
            },
            icon: const Icon(SymbolesAgri.delete, size: 16, color: AgriColors.errorDeep),
          ),
      ],
    );
  }

  Future<void> _ouvrirRole(RolesApplicatif? role) async {
    if (await ouvrirRole(context: context, depot: widget.reglages!, droits: _droits, existant: role, estAdmin: widget.estAdmin)) {
      setState(() => _message = 'Rôle demandé au serveur : il sera appliqué à la prochaine synchronisation.');
    }
  }

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
        if (widget.reglages != null) ...[
          Wrap(
            spacing: AgriSpacing.sm,
            runSpacing: AgriSpacing.sm,
            children: [
              ElevatedButton.icon(
                key: const Key('entreprise-modifier'),
                onPressed: () async {
                  if (await ouvrirEntreprise(context: context, depot: widget.reglages!, existante: e, estAdmin: widget.estAdmin)) {
                    setState(() => _message = 'Modifications demandées au serveur : elles seront appliquées à la prochaine synchronisation.');
                  }
                },
                icon: const Icon(SymbolesAgri.edit, size: 18),
                style: ElevatedButton.styleFrom(backgroundColor: AgriColors.brandEmerald, foregroundColor: Colors.white, shape: const StadiumBorder()),
                label: const Text('Enregistrer les Modifications', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
              ),
              OutlinedButton.icon(
                key: const Key('entreprise-bareme'),
                onPressed: () => setState(() => _sousPage = 'bareme'),
                icon: const Icon(SymbolesAgri.functions, size: 18),
                label: const Text('Barème IR-PTS / ITS — tranches d\'imposition', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
              ),
              OutlinedButton.icon(
                key: const Key('entreprise-sms'),
                onPressed: () => setState(() => _sousPage = 'sms'),
                icon: const Icon(SymbolesAgri.sms, size: 18),
                label: const Text('Intégrations & Notifications (SMS)', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: AgriSpacing.sm),
              child: Text(_message!, key: const Key('reglage-message'), style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
            ),
          const SizedBox(height: AgriSpacing.md),
        ],
        // Le SMTP du site ne descend pas (mot de passe) : celui du poste est local, son onglet a son coffre (CFG-2). Logo et
        // favicon se téléversent : ils se règlent sur la surface web.
        _mentionPoste(
          "Le serveur d'envoi (SMTP) de ce poste se règle dans l'onglet Email (SMTP) ; son mot de passe reste dans le coffre du "
          'système. Le logo et le favicon se téléversent : ils se règlent sur la surface web.',
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

  // ── Onglet 3 : Email (SMTP) — ticket CFG-2 ───────────────────────────────

  Widget _ongletEmailSmtp() {
    final smtp = widget.smtp;
    final envoi = widget.envoiEmail;
    if (smtp == null || envoi == null) {
      return _mentionPoste(
        'Réglage SMTP indisponible dans cette vue : il se fait depuis '
        'Paramètres, une fois la session ouverte.',
        cle: 'smtp-indisponible',
      );
    }
    return OngletEmailSmtp(parametres: smtp, envoi: envoi);
  }

  // ── Onglet 6 : Appairage — ticket CFG-2 ──────────────────────────────────

  Widget _ongletAppairage() {
    final appairage = widget.appairage;
    if (appairage == null) {
      return _mentionPoste(
        'Appairage indisponible dans cette vue : il se consulte depuis '
        'Paramètres, une fois la session ouverte.',
        cle: 'appairage-indisponible',
      );
    }
    return OngletAppairage(appairage: appairage);
  }

  // ── Onglet « Corbeille » — ticket ARC4 ────────────────────────────────────

  Widget _ongletCorbeille() {
    final corbeille = widget.corbeille;
    if (corbeille == null) {
      return _mentionPoste(
        'La Corbeille est indisponible dans cette vue : elle s\'ouvre depuis '
        'Paramètres, une fois la session ouverte.',
        cle: 'corbeille-indisponible',
      );
    }
    // Pas de défilement imbriqué : l'onglet est lui-même une page (la vue du hub défile déjà).
    return OngletCorbeille(depot: corbeille);
  }

  // ── Onglet 9 : Réinitialisation — ticket R-1 ──────────────────────────────

  Widget _ongletReinitialisation() {
    final reinitialisation = widget.reinitialisation;
    if (reinitialisation == null) {
      return _mentionPoste(
        'Réinitialisation indisponible dans cette vue : elle se fait depuis '
        'Paramètres, une fois la session ouverte.',
        cle: 'reinitialisation-indisponible',
      );
    }
    return OngletReinitialisation(depot: reinitialisation);
  }

  // ── Onglet 4 : Modules Actifs ─────────────────────────────────────────────

  /// Le sous-titre de chaque module, mot pour mot comme la maquette.
  ///
  /// ⚠️ LE BLADE DU WEB EST LE MAÎTRE (`livewire/parametres/modules-actifs.blade.php`) : « Fiches, VMS, catalogue POS liés
  /// à cette filière » pour une espèce exploitée, « Module en préparation — désactivé par défaut » (pastille FUTUR) pour
  /// l'héliciculture. Les sous-titres propres à chaque espèce de l'ancienne maquette étaient périmés.
  static const _descriptionsModules = <ModuleEspece, String>{
    ModuleEspece.cuniculture: 'Fiches, VMS, catalogue POS liés à cette filière',
    ModuleEspece.aviculture: 'Fiches, VMS, catalogue POS liés à cette filière',
    ModuleEspece.porciculture: 'Fiches, VMS, catalogue POS liés à cette filière',
    ModuleEspece.helico: 'Module en préparation — désactivé par défaut',
  };

  /// Toast du web (`$this->dispatch('toast', message: …, type: 'success')`).
  static const messageModuleBascule = 'Modification appliquée avec succès.';

  final _basculesEnCours = <ModuleEspece>{};

  /// `wire:click="toggleModule('…')"` — écrit, relit (les icônes et la couleur suivent), annonce comme le web.
  Future<void> _basculer(ModuleEspece module, bool actif) async {
    if (!_basculesEnCours.add(module)) return;
    try {
      await widget.depot.definirModule(module, actif: actif);
      await _charger();
      if (mounted) ToastAgri.afficher(context, messageModuleBascule);
    } finally {
      _basculesEnCours.remove(module);
    }
  }

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
                          // ⚠️ « FUTUR » est le mot du web, porté tel
                          // quel : l'héliciculture n'est pas éteinte par
                          // accident, elle n'est pas encore exploitée.
                          if (module == ModuleEspece.helico) ...[
                            const SizedBox(width: AgriSpacing.sm),
                            // ⚠️ EN BLEU « info », comme le Blade du web (`text-info-blue`,
                            // fond `info-blue/10`) — jamais en jaune d'accent : sur blanc,
                            // c'est le défaut de contraste corrigé au web au ticket 14.79.
                            _pastille('FUTUR', couleur: AgriColors.infoBlue),
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
                // ⚠️ L'INTERRUPTEUR EST UN BOUTON (ticket MOD1) : c'était une simple icône, qui ne répondait à aucun clic.
                InkWell(
                  key: Key('bascule-module-${module.code}'),
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _basculer(module, !d.moduleActif(module)),
                  child: Semantics(
                    toggled: d.moduleActif(module),
                    label: 'Activer ou désactiver ${module.libelle}',
                    child: Icon(
                      d.moduleActif(module) ? SymbolesAgri.toggle_on : SymbolesAgri.toggle_off,
                      size: 28,
                      color: d.moduleActif(module)
                          ? AgriColors.brandEmerald
                          : AgriColors.outline,
                    ),
                  ),
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
      // Texte et couleur du Blade du web (`bg-info-blue/10 border-info-blue/30`), mot pour mot.
      _mentionPoste(
        'Ces réglages sont appliqués immédiatement sur tous les onglets de '
        'Gestion Élevage et du Dashboard Élevage. Les données déjà '
        "enregistrées d'une espèce désactivée restent conservées et "
        'réapparaissent dès la réactivation du module.',
        cle: 'modules',
        couleur: AgriColors.infoBlue,
      ),
    ],
  );

  // ── Onglet 4 : Gestion Utilisateurs ───────────────────────────────────────

  /// Ticket UT-1 — `gestion-utilisateurs.blade.php` : les deux cartes, le tableau à cinq colonnes, « Nouvel
  /// Utilisateur », « Modifier », « Archiver » (confirmation) / « Réactiver ». Chaque geste s'écrit LOCALEMENT
  /// (`pending`) et part à la prochaine synchronisation ; le serveur rejoue par `SaisieUtilisateurAction`.
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
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const Key('nouvel-utilisateur'),
          onPressed: () => _ouvrirUtilisateur(d, null),
          icon: const Icon(SymbolesAgri.add_circle, size: 18),
          style: FilledButton.styleFrom(backgroundColor: AgriColors.brandEmerald),
          label: const Text('Nouvel Utilisateur', style: TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
        ),
      ),
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
        vide: 'Aucun utilisateur pour le moment.',
        lignes: [
          for (var i = 0; i < d.utilisateurs.length; i++)
            _ligne(i, [
              (
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.utilisateurs[i].name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AgriTypography.xs,
                        fontWeight: AgriTypography.gras,
                      ),
                    ),
                    if (d.utilisateurs[i].username case final String identifiant)
                      Text(identifiant, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AgriColors.outline, fontFamily: 'monospace')),
                  ],
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
                  _libelleRole(d.utilisateurs[i].role),
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              // ⚠️ « Désactivé » est le mot de la maquette — pas « Suspendu »,
              // pas « Inactif ». Un compte désactivé n'est jamais supprimé :
              // l'archivage logique est la règle du projet.
              (
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: _pastille(
                        d.utilisateurs[i].isActive ? 'Actif' : 'Désactivé',
                        couleur: d.utilisateurs[i].isActive ? AgriColors.brandEmerald : AgriColors.outline,
                      ),
                    ),
                    if (d.utilisateurs[i].syncStatus != SyncStatus.synced) ...[
                      const SizedBox(width: AgriSpacing.xs),
                      Flexible(
                        child: _pastille(
                          d.utilisateurs[i].syncStatus == SyncStatus.conflict ? 'Refusé' : 'Pas encore envoyé',
                          couleur: d.utilisateurs[i].syncStatus == SyncStatus.conflict ? AgriColors.errorRed : AgriColors.accentYellow,
                        ),
                      ),
                    ],
                  ],
                ),
                3,
              ),
              (
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      key: Key('utilisateur-modifier-$i'),
                      onPressed: () => _ouvrirUtilisateur(d, d.utilisateurs[i]),
                      icon: const Icon(SymbolesAgri.edit, size: 18, color: AgriColors.infoBlue),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                    if (d.utilisateurs[i].isActive)
                      IconButton(
                        key: Key('utilisateur-archiver-$i'),
                        onPressed: () => _confirmerArchivageUtilisateur(d.utilisateurs[i]),
                        icon: const Icon(SymbolesAgri.archive, size: 18, color: AgriColors.errorRed),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      )
                    else
                      IconButton(
                        key: Key('utilisateur-reactiver-$i'),
                        onPressed: () => _gesteUtilisateur(
                          () => widget.depot.reactiverUtilisateur(d.utilisateurs[i].id),
                          'Utilisateur réactivé avec succès.',
                        ),
                        icon: const Icon(SymbolesAgri.restart_alt, size: 18, color: AgriColors.brandEmerald),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                  ],
                ),
                2,
              ),
            ]),
        ],
      ),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️⚠️ NI MOT DE PASSE NI JETON NE DESCENDENT ; un mot de passe saisi ici attend au coffre du système et part
      // une fois. L'authentification du poste passe par `POST /api/auth/login`, contre le serveur.
      _mentionPoste(
        'Un compte créé, modifié, archivé ou réactivé ici part à la prochaine synchronisation ; il ne peut se '
        "connecter qu'une fois reçu par le serveur. Aucun mot de passe ni jeton ne descend du serveur. "
        '« Déconnecter toutes les sessions » se fait sur la surface web.',
        cle: 'utilisateurs',
      ),
    ],
  );

  /// `User::ROLE_LABELS` du web (`role_label`) ; un rôle inconnu garde son nom, `null` → « — ».
  static String _libelleRole(String? role) => switch (role) {
    null || '' => '—',
    'admin' => 'Administrateur',
    'comptable' => 'Comptable',
    'caissier' => 'Caissière POS',
    'animalier' => "Chef d'Élevage",
    final autre => autre,
  };

  Future<void> _gesteUtilisateur(Future<void> Function() geste, String succes) async {
    try {
      await geste();
    } on RefusSaisieUtilisateur catch (e) {
      if (mounted) ToastAgri.afficher(context, e.toString());
      return;
    }
    if (!mounted) return;
    ToastAgri.afficher(context, succes);
    await _charger();
  }

  Future<void> _confirmerArchivageUtilisateur(Utilisateur u) async {
    if (u.id == widget.idUtilisateurConnecte) {
      ToastAgri.afficher(context, ParametresGenerauxRepository.messagePropreCompte);
      return;
    }
    await afficherModale<void>(
      context: context,
      constructeur: (context) => ModaleConfirmation(
        icone: SymbolesAgri.archive,
        titre: "Archiver l'utilisateur",
        message: '${u.name} sera archivé(e) : le compte ne pourra plus se connecter, sur le web comme sur les postes.',
        couleurIcone: AgriColors.accentYellow,
        actions: [
          BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
          BoutonModalePrimaire(
            libelle: 'Archiver',
            couleur: AgriColors.errorRed,
            onPressed: () async {
              Navigator.of(context).pop();
              await _gesteUtilisateur(
                () => widget.depot.archiverUtilisateur(u.id, idConnecte: widget.idUtilisateurConnecte),
                'Utilisateur archivé avec succès.',
              );
            },
          ),
        ],
      ),
    );
  }

  /// La modale « Nouvel Utilisateur » / « Modifier l'Utilisateur » de `gestion-utilisateurs.blade.php` — mêmes champs.
  void _ouvrirUtilisateur(DonneesParametresGeneraux d, Utilisateur? u) {
    final nom = TextEditingController(text: u?.name ?? '');
    final identifiant = TextEditingController(text: u?.username ?? '');
    final email = TextEditingController(text: u?.email ?? '');
    final motDePasse = TextEditingController();
    var role = u?.role ?? '';
    var erreurs = <String, String>{};

    Widget champ(String cle, TextEditingController c, {String? indication, String? erreur, bool secret = false}) => TextField(
      key: Key(cle),
      controller: c,
      obscureText: secret,
      decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), hintText: indication, errorText: erreur),
      style: const TextStyle(fontSize: AgriTypography.sm),
    );
    Widget etiquette(String texte) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(texte.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
    );

    afficherModale<void>(
      context: context,
      constructeur: (context) => StatefulBuilder(
        builder: (context, majModale) => ModaleAgri(
          titre: u == null ? 'Nouvel Utilisateur' : "Modifier l'Utilisateur",
          contenu: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (erreurs[''] != null) ...[
                Text(erreurs['']!, key: const Key('utilisateur-erreur'), style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.errorRed)),
                const SizedBox(height: AgriSpacing.sm),
              ],
              etiquette('Nom complet *'),
              champ('utilisateur-nom', nom, erreur: erreurs['nom']),
              const SizedBox(height: AgriSpacing.sm),
              etiquette("Nom d'utilisateur *"),
              champ('utilisateur-identifiant', identifiant, indication: 'ex : compta', erreur: erreurs['identifiant']),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Lettres, chiffres, point, tiret et souligne. Sans arobase.', style: TextStyle(fontSize: 10, color: AgriColors.outline)),
              ),
              const SizedBox(height: AgriSpacing.sm),
              etiquette('Email *'),
              champ('utilisateur-email', email, erreur: erreurs['email']),
              const SizedBox(height: AgriSpacing.sm),
              etiquette('Rôle *'),
              DropdownButtonFormField<String>(
                key: const Key('utilisateur-role'),
                initialValue: role,
                isDense: true,
                isExpanded: true,
                decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), errorText: erreurs['role']),
                style: const TextStyle(fontSize: AgriTypography.sm, color: AgriColors.onSurface),
                items: [
                  const DropdownMenuItem(value: '', child: Text('-- Sélectionner --')),
                  for (final r in d.roles) DropdownMenuItem(value: r.name, child: Text(_majuscule(r.name))),
                  if (role.isNotEmpty && !d.roles.any((r) => r.name == role)) DropdownMenuItem(value: role, child: Text(_majuscule(role))),
                ],
                onChanged: (v) => majModale(() => role = v ?? ''),
              ),
              const SizedBox(height: AgriSpacing.sm),
              etiquette(u == null ? 'Mot de passe *' : 'Nouveau mot de passe'),
              champ(
                'utilisateur-mot-de-passe',
                motDePasse,
                indication: u == null ? 'Minimum 8 caractères' : 'Laisser vide pour conserver le mot de passe actuel',
                erreur: erreurs['motDePasse'],
                secret: true,
              ),
            ],
          ),
          actions: [
            BoutonModaleSecondaire(libelle: 'Annuler', onPressed: () => Navigator.of(context).pop()),
            BoutonModalePrimaire(
              libelle: 'Enregistrer',
              onPressed: () async {
                try {
                  await widget.depot.enregistrerUtilisateur(
                    id: u?.id,
                    nom: nom.text,
                    identifiant: identifiant.text,
                    email: email.text,
                    role: role,
                    motDePasse: motDePasse.text,
                  );
                } on RefusSaisieUtilisateur catch (e) {
                  majModale(() => erreurs = e.champs);
                  return;
                }
                if (!context.mounted) return;
                Navigator.of(context).pop();
                if (mounted) ToastAgri.afficher(this.context, u == null ? 'Utilisateur créé avec succès.' : 'Utilisateur modifié avec succès.');
                await _charger();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// `ucfirst()` du Blade sur le nom du rôle.
  static String _majuscule(String texte) => texte.isEmpty ? texte : '${texte[0].toUpperCase()}${texte.substring(1)}';

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
      if (widget.reglages != null) ...[
        Wrap(
          spacing: AgriSpacing.sm,
          runSpacing: AgriSpacing.sm,
          children: [
            for (final (cle, libelle, icone, geste) in [
              ('paiement-banque', 'Ajouter un Compte Bancaire', SymbolesAgri.account_balance, 'banque'),
              ('paiement-momo', 'Ajouter une Ligne Mobile Money', SymbolesAgri.smartphone, 'momo'),
              ('paiement-virement', 'Virement Interne', SymbolesAgri.swap_horiz, 'virement'),
            ])
              OutlinedButton.icon(
                key: Key(cle),
                onPressed: () => _gestePaiement(geste, d),
                icon: Icon(icone, size: 18),
                label: Text(libelle, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: AgriSpacing.sm),
            child: Text(_message!, key: const Key('reglage-message'), style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras, color: AgriColors.brandForest)),
          ),
        const SizedBox(height: AgriSpacing.md),
      ],
      _mentionPoste(
        'Les soldes sont ceux du dernier tirage. Un compte ajouté ou un virement est une DEMANDE : le serveur ouvre le compte, '
        'déplace les soldes et passe l\'écriture à la prochaine synchronisation.',
        cle: 'paiement',
      ),
    ],
  );

  Future<void> _gestePaiement(String geste, DonneesParametresGeneraux d) async {
    final depot = widget.reglages!;
    final bool fait;
    if (geste == 'banque') {
      fait = await ouvrirBanque(context: context, depot: depot);
    } else if (geste == 'momo') {
      fait = await ouvrirMomo(context: context, depot: depot);
    } else {
      fait = await ouvrirVirement(context: context, depot: depot, comptes: d.comptes);
    }
    if (fait && mounted) setState(() => _message = 'Demande envoyée : elle sera appliquée à la prochaine synchronisation.');
  }

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
        // 🔴→✅ Ticket U14 — la carte du Blade : `color="blue"`, légende « Sur les dernières 24 h », compte sur 24 h (le
        // poste comptait toutes les traces reçues, en rouge). Même tiret que la carte voisine quand le poste ne sait pas.
        CarteKpi(
          libelle: 'Connexions échouées',
          valeur: d.auditRecent ? '${d.connexionsEchouees}' : '—',
          legende: d.auditRecent ? 'Sur les dernières 24 h' : 'Dernier tirage il y a plus de 24 h',
          couleurLisere: AgriColors.infoBlue,
          icone: SymbolesAgri.lock,
          couleurIcone: AgriColors.infoBlue,
        ),
      ]),
      const SizedBox(height: AgriSpacing.md),
      // 🔴→✅ Ticket U14 — « Rechercher... » du Blade (en tête du tableau, `max-w-xs`), 300 ms d'attente.
      Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: SizedBox(
            height: 36,
            child: TextField(
              key: const Key('audit-recherche'),
              controller: _rechercheAudit,
              onChanged: (texte) {
                _attenteAudit?.cancel();
                _attenteAudit = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) setState(() => _filtreAudit = texte);
                });
              },
              style: const TextStyle(fontSize: AgriTypography.xs),
              decoration: InputDecoration(
                hintText: 'Rechercher...',
                isDense: true,
                prefixIcon: const Icon(SymbolesAgri.search, size: 18, color: AgriColors.outline),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AgriRadius.lg),
                  borderSide: const BorderSide(color: AgriColors.outlineVariant),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: AgriSpacing.sm),
      _tableauAudit(DonneesParametresGeneraux.filtrerAudit(d.audit, _filtreAudit)),
      const SizedBox(height: AgriSpacing.md),
      // ⚠️ DEUX CENTS LIGNES, comme la liste du web (`limit(200)`) : la table grossit d'une ligne par action et n'a
      // d'intérêt, au poste, que pour les dernières.
      _mentionPoste(
        'Les deux cents dernières actions de la ferme, comme la liste du web. La trace complète vit sur le '
        "serveur : elle grossit d'une ligne à chaque opération, et un poste "
        "n'a pas à en porter des années. L'export du journal se fait sur la "
        'surface web.',
        cle: 'audit',
      ),
    ],
  );

  /// Le tableau du Blade : Horodatage · Utilisateur · Action · Module · Actions, LIBELLÉS de l'action et du module
  /// (`action_label`, `module_label ?? '—'`), « Lecture seule » en italique avec son info-bulle, et l'état vide du web.
  Widget _tableauAudit(List<AuditLog> lignes) => _tableau(
        largeur: 980,
        colonnes: const [
          ('Horodatage', 3),
          ('Utilisateur', 4),
          ('Action', 5),
          ('Module', 3),
          ('Actions', 3),
        ],
        vide: 'Aucun événement pour le moment.',
        lignes: [
          for (var i = 0; i < lignes.length; i++)
            _ligne(i, [
              (Text(_dateHeure(lignes[i].createdAt), style: _cellule), 3),
              (
                Text(
                  lignes[i].userName ?? 'Inconnu',
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                4,
              ),
              (
                Text(
                  LibellesAudit.action(lignes[i].action),
                  key: Key('audit-action-$i'),
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                5,
              ),
              (
                Text(
                  LibellesAudit.module(lignes[i].module) ?? '—',
                  key: Key('audit-module-$i'),
                  overflow: TextOverflow.ellipsis,
                  style: _cellule,
                ),
                3,
              ),
              // Une trace d'audit ne se modifie ni ne s'efface, par définition.
              (
                const Tooltip(
                  message: "Les journaux d'audit sont immuables : aucune modification ni suppression n'est possible.",
                  child: Text(
                    'Lecture seule',
                    style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: AgriColors.outline),
                  ),
                ),
                3,
              ),
            ]),
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

  Widget _grilleKpis(bool large, List<Widget> cartes) => GrilleKpi(colonnes: large ? cartes.length : 2, children: cartes,
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
    child: LayoutBuilder(
      builder: (_, contraintes) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: max(largeur, contraintes.maxWidth),
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
  Widget _mentionPoste(
    String texte, {
    required String cle,
    Color couleur = AgriColors.accentYellow,
  }) => Container(
    key: Key('mention-$cle'),
    padding: const EdgeInsets.all(AgriSpacing.sm),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: 0.10),
      border: Border.all(
        color: couleur.withValues(alpha: 0.30),
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

  /// « Horodatage » du journal d'audit : `$log->created_at->format('d/m/Y H:i')` du web, serveur en
  /// `Africa/Porto-Novo`. 🔴→✅ Ticket U12b (reste de S-T11) — `created_at` est un INSTANT : il s'affiche à l'heure du
  /// Bénin ([HeureBenin.depuisInstant]), jamais à celle de Windows (un poste réglé à New York montrait 18:30 la veille
  /// d'une action faite à 00:30).
  static String _dateHeure(DateTime? d) {
    if (d == null) return '—';
    final l = HeureBenin.depuisInstant(d);
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}
