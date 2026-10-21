import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/auth/verrou_local.dart';
import '../../core/theme/agri_tokens.dart';
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
class PorteSession extends StatefulWidget {
  const PorteSession({
    super.key,
    required this.auth,
    required this.verrou,
    required this.ecranConnexion,
    required this.application,
    this.avantOuverture,
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

  @override
  State<PorteSession> createState() => _PorteSessionState();
}

enum _Phase { chargement, connexion, definition, verrouille, ouverte }

class _PorteSessionState extends State<PorteSession> {
  _Phase _phase = _Phase.chargement;

  String get _id => widget.auth.utilisateur?.id ?? '';

  @override
  void initState() {
    super.initState();
    _reprendre();
  }

  Future<void> _reprendre() async {
    final ouverte = await widget.auth.reprendreSession();
    if (!mounted) return;
    if (!ouverte) return setState(() => _phase = _Phase.connexion);
    final defini = await widget.verrou.estDefini(_id);
    if (mounted) setState(() => _phase = defini ? _Phase.verrouille : _Phase.definition);
  }

  Future<void> _connecte() async {
    final defini = await widget.verrou.estDefini(_id);
    if (defini) return _ouvrir();
    if (mounted) setState(() => _phase = _Phase.definition);
  }

  Future<void> _ouvrir() async {
    await widget.avantOuverture?.call();
    if (mounted) setState(() => _phase = _Phase.ouverte);
  }

  Future<void> _reconnecter() async {
    final id = _id;
    await widget.auth.deconnecter();
    await widget.verrou.effacer(id);
    if (mounted) setState(() => _phase = _Phase.connexion);
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
        () => setState(() => _phase = _Phase.verrouille),
        () => setState(() => _phase = _Phase.connexion),
      ),
    };
  }
}
