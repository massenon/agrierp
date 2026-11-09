import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/auth/verrou_inactivite.dart';
import '../../core/auth/verrou_local.dart';
import '../../core/theme/agri_tokens.dart';
import '../auth/ecran_changement_mot_de_passe.dart';
import 'ecran_definir_pin.dart';
import 'ecran_verrou.dart';

/// Ticket VL-1 — la PORTE de l'application : décide, à chaque lancement et après chaque connexion, quel écran
/// est montré, et n'en montre AUCUN avant que l'état soit connu (pas de flash de l'application avant le verrou).
///
/// ```
/// chargement ──(session restaurée, PIN défini)──► verrou ──(bon PIN)──► application
///     │                      └─(session restaurée, sans PIN)──► définition ──► application
///     └─(pas de session)──► connexion ──(connecté)──► [définition si pas de PIN] ──► application
/// ```
///
/// ⚠️ Après une connexion EN LIGNE réussie, le PIN n'est pas redemandé dans la même exécution : le mot de passe
/// vient d'être saisi. S'il n'y en a pas encore, il se définit d'abord ; s'il y en a déjà un, on ne le demande pas.
///
/// ⚠️ Verrouiller, c'est DÉMONTER l'application : l'écran de verrouillage la remplace, il ne la recouvre pas. Un
/// formulaire en cours de saisie est donc perdu — assumé, c'est le prix de ne rien laisser lisible.
///
/// Ticket VL-2 — le verrouillage par inactivité ([inactivite]) passe par la même porte : armé à l'ouverture de
/// l'application, désarmé dès qu'on la quitte (verrou, définition, connexion). À l'échéance, les fenêtres modales
/// encore ouvertes sont fermées (elles recouvriraient l'écran de verrouillage) puis l'application est démontée.
class PorteSession extends StatefulWidget {
  const PorteSession({
    super.key,
    required this.auth,
    required this.verrou,
    required this.ecranConnexion,
    required this.application,
    this.avantOuverture,
    this.inactivite,
    this.surFinDeSession,
    this.surOuverture,
  });

  final AuthService auth;
  final VerrouLocal verrou;

  /// L'écran de connexion ; [onConnecte] est à appeler après une connexion réussie.
  final Widget Function(VoidCallback onConnecte) ecranConnexion;

  /// L'application ; [verrouiller] la remplace par l'écran de verrouillage, [onDeconnecte] ramène à la connexion
  /// (à appeler APRÈS `auth.deconnecter()`).
  final Widget Function(VoidCallback verrouiller, VoidCallback onDeconnecte) application;

  /// Appelé juste avant d'ouvrir l'application (poste neuf ou non).
  final Future<void> Function()? avantOuverture;

  /// Ticket VL-2 — verrouillage après inactivité ; `null` : pas de verrouillage automatique.
  final VerrouInactivite? inactivite;

  /// Appelé quand la SESSION prend fin (déconnexion, « PIN oublié ») : la coque y vide ce qu'elle garde en mémoire
  /// pour survivre à un verrouillage (brouillons), afin qu'un autre utilisateur ne le retrouve pas.
  final VoidCallback? surFinDeSession;

  /// Ticket POP3 — appelé UNE fois à chaque OUVERTURE DE SESSION : au lancement (après le PIN) et à chaque connexion.
  /// Jamais à un déverrouillage (verrouillage manuel ou par inactivité) : le poste reste ouvert dans la même session.
  /// C'est là que s'ouvre la fenêtre « Rappels du jour ». Toute erreur levée ici est avalée (journalisée par
  /// l'appelant) : elle ne bloque jamais l'ouverture de l'application.
  final Future<void> Function(BuildContext context)? surOuverture;

  @override
  State<PorteSession> createState() => _PorteSessionState();
}

enum _Phase { chargement, connexion, changementMotDePasse, definition, verrouille, ouverte }

class _PorteSessionState extends State<PorteSession> {
  _Phase _phase = _Phase.chargement;

  /// POP3 — une nouvelle SESSION vient de commencer (lancement avec session restaurée, ou connexion) : la prochaine
  /// ouverture de l'application déclenche [PorteSession.surOuverture], puis le drapeau retombe. Un déverrouillage ne
  /// le relève pas.
  bool _sessionNeuve = false;

  String get _id => widget.auth.utilisateur?.id ?? '';

  @override
  void initState() {
    super.initState();
    _reprendre();
  }

  Future<void> _reprendre() async {
    final ouverte = await widget.auth.reprendreSession();
    if (!mounted) return;
    if (!ouverte) return _aller(_Phase.connexion);
    _sessionNeuve = true;
    final defini = await widget.verrou.estDefini(_id);
    if (mounted) _aller(defini ? _Phase.verrouille : _Phase.definition);
  }

  /// MDP-1 — mot de passe TEMPORAIRE posé par un administrateur : le changement obligatoire passe AVANT le PIN et
  /// l'accueil, à la connexion comme à la reprise d'une session restaurée.
  bool get _changementRequis => widget.auth.utilisateur?.doitChangerMotDePasse ?? false;

  Future<void> _connecte() async {
    _sessionNeuve = true;
    if (_changementRequis) return _aller(_Phase.changementMotDePasse);
    final defini = await widget.verrou.estDefini(_id);
    if (defini) return _ouvrir();
    if (mounted) _aller(_Phase.definition);
  }

  Future<void> _ouvrir() async {
    if (_changementRequis) return _aller(_Phase.changementMotDePasse);
    await widget.avantOuverture?.call();
    if (!mounted) return;
    setState(() => _phase = _Phase.ouverte);
    _armerInactivite();
    if (_sessionNeuve) {
      _sessionNeuve = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _annoncerOuverture());
    }
  }

  /// POP3 — après le premier affichage de l'application : la fenêtre « Rappels du jour ». Silencieux sur erreur.
  Future<void> _annoncerOuverture() async {
    final surOuverture = widget.surOuverture;
    if (surOuverture == null || !mounted || _phase != _Phase.ouverte) return;
    try {
      await surOuverture(context);
    } on Object catch (e) {
      debugPrint('Rappels du jour : ouverture impossible.');
      debugPrint('$e');
    }
  }

  /// VL-2 — arme le minuteur d'inactivité pour l'utilisateur de la session.
  void _armerInactivite() {
    final inactivite = widget.inactivite;
    if (inactivite == null) return;
    inactivite.modaleOuverte = () => mounted && Navigator.of(context).canPop();
    inactivite.armer(idUtilisateur: _id, verrouiller: _verrouillerParInactivite);
  }

  /// VL-2 — échéance : ferme les fenêtres modales puis remplace l'application par l'écran de verrouillage.
  void _verrouillerParInactivite() {
    if (!mounted || _phase != _Phase.ouverte) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _phase = _Phase.verrouille);
  }

  /// Toute sortie de l'application désarme le minuteur ; [_phase] change ensuite.
  void _aller(_Phase phase) {
    if (phase != _Phase.ouverte) widget.inactivite?.desarmer();
    setState(() => _phase = phase);
  }

  @override
  void dispose() {
    widget.inactivite?.desarmer();
    super.dispose();
  }

  Future<void> _reconnecter() async {
    final id = _id;
    await widget.auth.deconnecter();
    await widget.verrou.effacer(id);
    widget.surFinDeSession?.call();
    if (mounted) _aller(_Phase.connexion);
  }

  @override
  Widget build(BuildContext context) {
    final nom = widget.auth.utilisateur?.nom ?? '—';
    final identifiant = widget.auth.utilisateur?.identifiant ?? '';

    return switch (_phase) {
      _Phase.chargement => const Scaffold(
        backgroundColor: AgriColors.surfaceBg,
        body: Center(child: CircularProgressIndicator()),
      ),
      _Phase.connexion => widget.ecranConnexion(_connecte),
      _Phase.changementMotDePasse => EcranChangementMotDePasseObligatoire(
        auth: widget.auth,
        onChange: _connecte,
        onDeconnecte: () {
          widget.surFinDeSession?.call();
          _aller(_Phase.connexion);
        },
      ),
      _Phase.definition => EcranDefinirPin(
        verrou: widget.verrou,
        idUtilisateur: _id,
        nomUtilisateur: nom,
        identifiant: identifiant,
        onDefini: _ouvrir,
      ),
      _Phase.verrouille => EcranVerrou(
        verrou: widget.verrou,
        idUtilisateur: _id,
        nomUtilisateur: nom,
        identifiant: identifiant,
        onDeverrouille: _ouvrir,
        onReconnexion: _reconnecter,
      ),
      _Phase.ouverte => widget.application(
        () => _aller(_Phase.verrouille),
        () {
          widget.surFinDeSession?.call();
          _aller(_Phase.connexion);
        },
      ),
    };
  }
}
