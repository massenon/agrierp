import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/verrou_local.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/widgets/modale_agri.dart';
import '../../core/theme/symboles_agri.dart';
import '../auth/login_screen.dart';
import 'pave_pin.dart';

/// Ticket VL-1 — écran de verrouillage : PLEIN ÉCRAN qui REMPLACE l'application (jamais une surcouche : aucune
/// donnée n'est construite, donc aucune n'est lisible, tant que le code n'est pas bon).
///
/// ⚠️ **AUCUN APPEL RÉSEAU** : la vérification est locale (`VerrouLocal`). Le seul geste en ligne est « PIN oublié ?
/// Se reconnecter », qui ferme la session ; la connexion qui suit redéfinit le PIN.
class EcranVerrou extends StatefulWidget {
  const EcranVerrou({
    super.key,
    required this.verrou,
    required this.idUtilisateur,
    required this.nomUtilisateur,
    required this.identifiant,
    required this.onDeverrouille,
    required this.onReconnexion,
  });

  final VerrouLocal verrou;
  final String idUtilisateur;
  final String nomUtilisateur;

  /// Identifiant de connexion, affiché en lecture seule (comme le champ de l'écran de connexion).
  final String identifiant;
  final VoidCallback onDeverrouille;

  /// Ferme la session et ramène à la connexion (après confirmation, ou d'office après dix échecs).
  final Future<void> Function() onReconnexion;

  @override
  State<EcranVerrou> createState() => _EcranVerrouState();
}

class _EcranVerrouState extends State<EcranVerrou> {
  String? _message;
  int _reste = 0;
  bool _reconnexionRequise = false;
  bool _enCours = false;
  Timer? _minuterie;
  final _pave = ControleurPave();
  late final _champIdentifiant = TextEditingController(text: widget.identifiant);

  @override
  void initState() {
    super.initState();
    _lireEtat();
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    _champIdentifiant.dispose();
    super.dispose();
  }

  Future<void> _lireEtat() async {
    final t = await widget.verrou.etat(widget.idUtilisateur);
    if (mounted) _appliquer(t);
  }

  void _appliquer(TentativeVerrou t) {
    switch (t.resultat) {
      case ResultatVerrou.reconnexionRequise:
        setState(() {
          _reconnexionRequise = true;
          _message = "Trop d'échecs : l'accès local est refusé. Reconnectez-vous en ligne.";
        });
      case ResultatVerrou.temporise:
        _demarrerAttente(t.attente ?? const Duration(seconds: 30));
      case ResultatVerrou.refuse:
        setState(() => _message = 'Code PIN incorrect.');
      case ResultatVerrou.ok:
        break;
    }
  }

  void _demarrerAttente(Duration attente) {
    _minuterie?.cancel();
    setState(() {
      _reste = (attente.inMilliseconds / 1000).ceil();
      _message = null;
    });
    _minuterie = Timer.periodic(const Duration(seconds: 1), (m) {
      if (!mounted) return m.cancel();
      setState(() => _reste--);
      if (_reste <= 0) m.cancel();
    });
  }

  Future<void> _valider(String pin) async {
    if (!VerrouLocal.pinValide(pin)) {
      setState(() => _message = 'Le code PIN comporte de 4 à 6 chiffres.');
      return;
    }
    final t = await widget.verrou.verifier(widget.idUtilisateur, pin);
    if (!mounted) return;
    if (t.resultat == ResultatVerrou.ok) {
      widget.onDeverrouille();
    } else {
      _appliquer(t);
    }
  }

  Future<void> _reconnecter({required bool confirmer}) async {
    if (confirmer) {
      final oui = await afficherModale<bool>(
        context: context,
        confirmation: true,
        constructeur: (c) => ModaleConfirmation(
          icone: SymbolesAgri.lock_open,
          titre: 'PIN oublié ?',
          message:
              'Vous allez être déconnecté. Il faudra vous reconnecter EN LIGNE avec votre mot de passe, '
              'puis définir un nouveau code PIN. Les saisies en attente restent sur le poste.',
          actions: [
            BoutonModalePrimaire(
              key: const Key('verrou-oublie-confirmer'),
              libelle: 'Me reconnecter',
              onPressed: () => Navigator.pop(c, true),
            ),
            BoutonModaleSecondaire(
              key: const Key('verrou-oublie-annuler'),
              libelle: 'Annuler',
              onPressed: () => Navigator.pop(c, false),
            ),
          ],
        ),
      );
      if (oui != true || !mounted) return;
    }
    setState(() => _enCours = true);
    await widget.onReconnexion();
  }

  @override
  Widget build(BuildContext context) {
    final attente = _reste > 0;
    final message = attente
        ? "Trop d'essais. Réessayez dans ${_formater(_reste)}."
        : _message;

    // ⚠️ Même cadre, mêmes champs et même bouton que l'écran de connexion (client, 21/10/2026) : seul le secret
    // change (le code PIN), et RIEN ne part vers le serveur.
    return CadreConnexion(
      titre: 'Application verrouillée',
      sousTitre:
          'Session de ${widget.nomUtilisateur}. Saisissez votre code PIN : aucune connexion au serveur n\'est nécessaire.',
      enfants: [
        if (message != null) ...[
          KeyedSubtree(
            key: Key(attente ? 'verrou-attente' : 'verrou-message'),
            child: BandeauErreurConnexion(message: message),
          ),
          const SizedBox(height: AgriSpacing.md),
        ],
        ChampConnexion(
          libelle: "NOM D'UTILISATEUR",
          controleur: _champIdentifiant,
          icone: SymbolesAgri.person_outline,
          indice: '',
          lectureSeule: true,
          cleChamp: const Key('verrou-utilisateur'),
        ),
        const SizedBox(height: AgriSpacing.md),
        const Text(
          'CODE PIN',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: AgriColors.brandForest,
          ),
        ),
        const SizedBox(height: AgriSpacing.sm),
        if (!_reconnexionRequise) ...[
          PavePin(
            controleur: _pave,
            actif: !attente && !_enCours,
            onValider: _valider,
          ),
          const SizedBox(height: AgriSpacing.md),
          BoutonConnexion(
            cle: const Key('verrou-bouton'),
            libelle: 'DÉVERROUILLER',
            enCours: _enCours,
            desactive: attente,
            onPressed: _pave.valider,
          ),
        ],
        const SizedBox(height: AgriSpacing.md),
        Center(
          child: TextButton(
            key: const Key('verrou-oublie'),
            onPressed: _enCours ? null : () => _reconnecter(confirmer: !_reconnexionRequise),
            child: Text(
              _reconnexionRequise ? 'Se reconnecter' : 'PIN oublié ? Se reconnecter',
              style: const TextStyle(
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

  static String _formater(int secondes) => secondes >= 60
      ? '${secondes ~/ 60} min ${(secondes % 60).toString().padLeft(2, '0')} s'
      : '$secondes s';
}
