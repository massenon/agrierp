import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import '../demarrage/premier_demarrage_repository.dart';
import '../../core/theme/symboles_agri.dart';

/// `prototype_html/login.html` → écran de connexion Desktop.
///
/// STRUCTURE REPRISE DE LA MAQUETTE, section par section :
///   • panneau gauche 50 % (≥ lg) : dégradé forestier, logo en haut,
///     mentions PAEB / FAGUEZ SARL en pied ;
///   • colonne droite : barre supérieure (mode sombre, langue, `v1.0.0`),
///     bloc centré de 440 px de large — logo, bandeau de 7 icônes de modules,
///     « Bienvenue ! », bandeau de blocage, formulaire, pied de page.
///
/// ⚠️ LIBELLÉS REPRIS AU MOT : « NOM D'UTILISATEUR OU EMAIL », « MOT DE
/// PASSE », « Se souvenir de moi », « Mot de passe oublié ? », « SE
/// CONNECTER », et le titre « Bienvenue ! » avec son point d'exclamation.
///
/// ÉCARTS ASSUMÉS PAR RAPPORT À LA MAQUETTE :
/// 1. Le sélecteur de langue et le bouton « Mode sombre » sont affichés mais
///    INACTIFS. La maquette bascule un thème sombre en CSS ; le porter ici
///    demande une palette sombre complète qui n'existe dans aucun document.
///    ⚠️ Affichés désactivés plutôt que retirés : leur absence ferait croire
///    à un oubli de conversion, leur présence active à une fonction livrée.
/// 2. Le compteur de tentatives restantes du toast d'erreur n'est pas repris —
///    même décision que côté web (ticket 1.1) : il facilite l'énumération de
///    comptes. Le bandeau de blocage, lui, est conservé.
/// 3. La maquette authentifie contre deux adresses codées en dur ; ici,
///    authentification RÉELLE contre `POST /api/auth/login`.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    required this.onConnecte,
    this.demarrage,
  });

  final AuthService auth;
  final VoidCallback onConnecte;

  /// Ticket F0.98 — sur un poste NEUF, l'adresse du serveur s'affiche et se change avant la connexion
  /// (« Paramètres du poste », réservé à l'administrateur, n'est pas encore accessible).
  final PremierDemarrageRepository? demarrage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifiant = TextEditingController();
  final _motDePasse = TextEditingController();

  bool _motDePasseVisible = false;
  bool _seSouvenir = false;
  bool _enCours = false;
  String? _erreur;

  /// Ticket F0.98 — adresse affichée seulement sur un poste neuf (null sinon).
  String? _adresseServeur;

  @override
  void initState() {
    super.initState();
    _lireServeur();
  }

  Future<void> _lireServeur() async {
    final depot = widget.demarrage;
    if (depot == null || !await depot.posteNeuf()) return;
    final adresse = await depot.adresse();
    if (mounted) setState(() => _adresseServeur = adresse);
  }

  Future<void> _changerServeur() async {
    final nouvelle = await afficherModale<String>(
      context: context,
      constructeur: (_) => _DialogueServeur(adresse: _adresseServeur ?? ''),
    );
    if (nouvelle == null || nouvelle.trim().isEmpty) return;
    try {
      final enregistree = await widget.demarrage!.changerAdresse(nouvelle);
      if (mounted) setState(() => _adresseServeur = enregistree);
    } on StateError catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    }
  }

  @override
  void dispose() {
    _identifiant.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _soumettre() async {
    final identifiant = _identifiant.text.trim();
    final motDePasse = _motDePasse.text;

    // Messages exacts de la maquette, adaptés au champ réellement demandé.
    if (identifiant.isEmpty) {
      setState(
        () => _erreur =
            "Le nom d'utilisateur ou l'adresse e-mail est obligatoire.",
      );
      return;
    }
    if (motDePasse.isEmpty) {
      setState(() => _erreur = 'Le mot de passe est obligatoire.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      await widget.auth.connecter(
        identifiant: identifiant,
        motDePasse: motDePasse,
      );
      if (mounted) widget.onConnecte();
    } on EchecConnexion catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.surfaceCard,
      body: Builder(
        // ⚠️ `Builder` ET NON `LayoutBuilder` : la mise en page se
        // décide sur la largeur de l'ÉCRAN (MediaQuery), jamais sur
        // celle du contenu. Retirer les contraintes de la portée
        // interdit la rechute.
        builder: (context) {
          // La maquette masque le panneau gauche sous le point de rupture
          // `lg` de Tailwind (1024 px) : `hidden lg:flex lg:w-[50%]`.
          final panneauVisible = AgriBreakpoints.large(context);

          return Row(
            children: [
              if (panneauVisible) const Expanded(child: _PanneauFerme()),
              Expanded(child: _colonneFormulaire()),
            ],
          );
        },
      ),
    );
  }

  Widget _colonneFormulaire() {
    return Padding(
      padding: const EdgeInsets.all(AgriSpacing.xl),
      child: Column(
        children: [
          const _BarreSuperieure(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _EnTeteMarque(),
                      const SizedBox(height: AgriSpacing.lg),
                      const _BandeauModules(),
                      const SizedBox(height: AgriSpacing.lg),
                      const Text(
                        'Bienvenue !',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AgriColors.brandForest,
                        ),
                      ),
                      const SizedBox(height: AgriSpacing.xs),
                      const Text(
                        "Connectez-vous à votre espace d'administration AgriERP.",
                        style: TextStyle(
                          fontSize: AgriTypography.xs,
                          color: AgriColors.outline,
                        ),
                      ),
                      const SizedBox(height: AgriSpacing.lg),
                      if (_erreur != null) ...[
                        _BandeauErreur(message: _erreur!),
                        const SizedBox(height: AgriSpacing.md),
                      ],
                      _champ(
                        libelle: "NOM D'UTILISATEUR OU EMAIL",
                        controleur: _identifiant,
                        icone: SymbolesAgri.person_outline,
                        indice: 'admin ou contact@fermeolouwachegoun.com',
                      ),
                      const SizedBox(height: AgriSpacing.md),
                      _champ(
                        libelle: 'MOT DE PASSE',
                        controleur: _motDePasse,
                        icone: SymbolesAgri.lock_outline,
                        indice: 'AgriERP@2026',
                        masque: !_motDePasseVisible,
                        suffixe: IconButton(
                          icon: Icon(
                            _motDePasseVisible
                                ? SymbolesAgri.visibility_off
                                : SymbolesAgri.visibility,
                            size: 18,
                            color: AgriColors.outline,
                          ),
                          onPressed: () => setState(
                            () => _motDePasseVisible = !_motDePasseVisible,
                          ),
                        ),
                      ),
                      const SizedBox(height: AgriSpacing.md),
                      _ligneOptions(),
                      const SizedBox(height: AgriSpacing.md),
                      _boutonConnexion(),
                      if (_adresseServeur != null) ...[
                        const SizedBox(height: AgriSpacing.md),
                        Row(
                          key: const Key('login-serveur'),
                          children: [
                            Expanded(
                              child: Text(
                                'Serveur : $_adresseServeur',
                                style: const TextStyle(
                                  fontSize: AgriTypography.xs,
                                  color: AgriColors.outline,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const Key('login-modifier-serveur'),
                              onPressed: _changerServeur,
                              child: const Text(
                                'Modifier',
                                style: TextStyle(fontSize: AgriTypography.xs),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const _PiedDePage(),
        ],
      ),
    );
  }

  Widget _champ({
    required String libelle,
    required TextEditingController controleur,
    required IconData icone,
    required String indice,
    bool masque = false,
    Widget? suffixe,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          libelle,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: AgriColors.brandForest,
          ),
        ),
        const SizedBox(height: AgriSpacing.xs),
        TextField(
          key: Key('champ-${libelle.hashCode}'),
          controller: controleur,
          obscureText: masque,
          onSubmitted: (_) => _soumettre(),
          style: const TextStyle(fontSize: AgriTypography.xs),
          decoration: InputDecoration(
            hintText: indice,
            hintStyle: const TextStyle(
              fontSize: AgriTypography.xs,
              color: AgriColors.outline,
            ),
            prefixIcon: Icon(icone, size: 18, color: AgriColors.outline),
            suffixIcon: suffixe,
          ),
        ),
      ],
    );
  }

  Widget _ligneOptions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Flexible : à 440 px de colonne, une police plus large ne déborde pas (vu au test F0.98).
        Flexible(
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: _seSouvenir,
                  onChanged: (v) => setState(() => _seSouvenir = v ?? false),
                  activeColor: AgriColors.brandEmerald,
                ),
              ),
              const SizedBox(width: AgriSpacing.sm),
              const Flexible(
                child: Text(
                  'Se souvenir de moi',
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    color: AgriColors.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: TextButton(
            // ⚠️ La réinitialisation passe par un lien envoyé par E-MAIL : elle
            // exige donc le réseau ET une adresse. Ouvrir une saisie hors ligne
            // laisserait croire à un envoi qui n'aura pas lieu — l'écran renvoie
            // vers la surface web, qui porte ce parcours en entier.
            onPressed: () => afficherModale<void>(
              context: context,
              constructeur: (_) => const _DialogueMotDePasseOublie(),
            ),
            child: const Text(
              'Mot de passe oublié ?',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.w600,
                color: AgriColors.brandEmerald,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _boutonConnexion() {
    return SizedBox(
      height: 44,
      child: FilledButton(
        key: const Key('bouton-connexion'),
        onPressed: _enCours ? null : _soumettre,
        style: FilledButton.styleFrom(
          backgroundColor: AgriColors.brandEmerald,
          disabledBackgroundColor: AgriColors.brandEmerald.withValues(
            alpha: 0.5,
          ),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AgriRadius.lg),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_enCours)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              const Icon(SymbolesAgri.lock_open, size: 16),
            const SizedBox(width: AgriSpacing.sm),
            const Text(
              'SE CONNECTER',
              style: TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panneau gauche : dégradé forestier et mentions institutionnelles.
class _PanneauFerme extends StatelessWidget {
  const _PanneauFerme();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AgriColors.brandForest, AgriColors.brandEmerald],
        ),
      ),
      padding: const EdgeInsets.all(AgriSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                SymbolesAgri.agriculture,
                color: AgriColors.accentYellow,
                size: 26,
              ),
              const SizedBox(width: AgriSpacing.sm),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  children: [
                    TextSpan(text: 'Agri'),
                    TextSpan(
                      text: 'ERP',
                      style: TextStyle(color: AgriColors.accentYellow),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          const Divider(color: Colors.white24),
          const SizedBox(height: AgriSpacing.md),
          const Text(
            "PROJET D'APPUI À L'ENTREPRENEURIAT AU BÉNIN (PAEB)",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: AgriSpacing.xs),
          const Text(
            'FAGUEZ SARL',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarreSuperieure extends StatelessWidget {
  const _BarreSuperieure();

  @override
  Widget build(BuildContext context) {
    // ⚠️ Mode sombre et langue : présents comme dans la maquette, mais
    // DÉSACTIVÉS — aucune palette sombre n'est documentée, et l'application
    // n'est qu'en français. Désactivés plutôt que retirés : leur absence
    // ferait croire à un oubli de conversion.
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(SymbolesAgri.dark_mode, size: 16),
          label: const Text('Mode sombre', style: TextStyle(fontSize: 11)),
        ),
        const SizedBox(width: AgriSpacing.sm),
        OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(SymbolesAgri.translate, size: 16),
          label: const Text('Français', style: TextStyle(fontSize: 11)),
        ),
        const SizedBox(width: AgriSpacing.sm),
        const Text(
          'v1.0.0',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: AgriColors.outline,
          ),
        ),
      ],
    );
  }
}

class _EnTeteMarque extends StatelessWidget {
  const _EnTeteMarque();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              SymbolesAgri.agriculture,
              color: AgriColors.brandEmerald,
              size: 38,
            ),
            const SizedBox(width: AgriSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AgriColors.brandForest,
                    ),
                    children: [
                      TextSpan(text: 'Agri'),
                      TextSpan(
                        text: 'ERP',
                        style: TextStyle(color: AgriColors.accentYellow),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'FERME OLOUWACHEGOUN',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                    color: AgriColors.brandEmerald,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.sm),
        const Divider(color: AgriColors.outlineVariant),
        const Text(
          'VOTRE LOGICIEL DE GESTION INTÉGRÉE',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
            color: AgriColors.brandEmerald,
          ),
        ),
      ],
    );
  }
}

/// Bandeau des 7 icônes de modules — mêmes symboles et même ordre que la
/// maquette : `local_florist`, `account_balance`, `point_of_sale`,
/// `inventory_2`, `pets`, `analytics`, `settings`.
class _BandeauModules extends StatelessWidget {
  const _BandeauModules();

  static const _icones = [
    SymbolesAgri.local_florist,
    SymbolesAgri.account_balance,
    SymbolesAgri.point_of_sale,
    SymbolesAgri.inventory_2,
    SymbolesAgri.pets,
    SymbolesAgri.analytics,
    SymbolesAgri.settings,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AgriSpacing.sm + 4),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AgriColors.outlineVariant),
          bottom: BorderSide(color: AgriColors.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final i in _icones) Icon(i, size: 16, color: AgriColors.outline),
        ],
      ),
    );
  }
}

class _BandeauErreur extends StatelessWidget {
  const _BandeauErreur({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AgriSpacing.md,
        vertical: AgriSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AgriColors.errorBg,
        border: Border.all(color: AgriColors.errorDeep.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        children: [
          const Icon(SymbolesAgri.lock_clock, size: 18, color: AgriColors.errorDeep),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: Text(
              message,
              key: const Key('bandeau-erreur'),
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                color: AgriColors.errorDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ticket F0.98 — saisie de l'adresse du serveur. ⚠️ StatefulWidget : le contrôleur vit avec la modale ;
/// le libérer au retour de `afficherModale` le faisait servir pendant l'animation de fermeture.
class _DialogueServeur extends StatefulWidget {
  const _DialogueServeur({required this.adresse});

  final String adresse;

  @override
  State<_DialogueServeur> createState() => _DialogueServeurState();
}

class _DialogueServeurState extends State<_DialogueServeur> {
  late final _saisie = TextEditingController(text: widget.adresse);

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ModaleAgri(
      titre: 'Adresse du serveur',
      largeur: LargeurModale.sm,
      contenu: TextField(
        key: const Key('login-adresse-serveur'),
        controller: _saisie,
        style: const TextStyle(fontSize: AgriTypography.xs),
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Annuler',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BoutonModalePrimaire(
          libelle: 'Enregistrer',
          onPressed: () => Navigator.of(context).pop(_saisie.text),
        ),
      ],
    );
  }
}

class _DialogueMotDePasseOublie extends StatelessWidget {
  const _DialogueMotDePasseOublie();

  @override
  Widget build(BuildContext context) {
    // ⚠️ Gabarit `max-w-sm` des modales d'information : le prototype n'a pas
    // d'écran de mot de passe oublié au poste, la réinitialisation se faisant
    // sur la surface web.
    return ModaleAgri(
      titre: 'Mot de passe oublié',
      largeur: LargeurModale.sm,
      contenu: const Text(
        "La réinitialisation se fait par un lien envoyé sur votre adresse "
        "e-mail professionnelle, depuis l'espace web AgriERP. Ce poste ne "
        "peut pas l'envoyer lui-même.",
        style: TextStyle(fontSize: AgriTypography.xs),
      ),
      actions: [
        BoutonModaleSecondaire(
          libelle: 'Fermer',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _PiedDePage extends StatelessWidget {
  const _PiedDePage();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: AgriSpacing.md),
      child: Text(
        "© 2026 AgriERP — Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB) — FAGUEZ SARL",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: AgriColors.outline),
      ),
    );
  }
}
