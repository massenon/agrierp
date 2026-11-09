import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import 'login_screen.dart';

/// Ticket MDP-1 — CHANGEMENT DE MOT DE PASSE OBLIGATOIRE (`livewire/auth/changement-mot-de-passe-obligatoire.blade.php`).
///
/// Un administrateur a posé un mot de passe TEMPORAIRE : après la connexion et AVANT l'accueil, le poste n'affiche que
/// ce formulaire (même cadre que l'écran de connexion, mêmes libellés que le Blade, lus par
/// `test/changement_mot_de_passe_obligatoire_test.dart`). Il réutilise `AuthService.changerMotDePasse`
/// (`POST /api/auth/password`, ticket 15.9) : le serveur vérifie le temporaire, applique la même politique que « Mon
/// Profil », refuse un nouveau mot de passe identique au temporaire et remet le drapeau à faux. Tant qu'il n'est pas
/// fait, le serveur refuse tout le reste de l'API (403).
///
/// ⚠️ Ce geste EXIGE LE RÉSEAU (le serveur vérifie le hachage) ; hors ligne, le message le dit. « Se déconnecter »
/// ramène à la connexion.
class EcranChangementMotDePasseObligatoire extends StatefulWidget {
  const EcranChangementMotDePasseObligatoire({
    super.key,
    required this.auth,
    required this.onChange,
    required this.onDeconnecte,
  });

  final AuthService auth;

  /// Appelé après un changement réussi.
  final VoidCallback onChange;

  /// Appelé APRÈS `auth.deconnecter()` : retour à l'écran de connexion.
  final VoidCallback onDeconnecte;

  @override
  State<EcranChangementMotDePasseObligatoire> createState() => _EtatEcranChangement();
}

class _EtatEcranChangement extends State<EcranChangementMotDePasseObligatoire> {
  final _temporaire = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();

  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _temporaire.dispose();
    _nouveau.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (_temporaire.text.isEmpty) {
      setState(() => _erreur = 'Le mot de passe temporaire est obligatoire.');
      return;
    }
    if (_nouveau.text != _confirmation.text) {
      setState(() => _erreur = 'La confirmation ne correspond pas au mot de passe saisi.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.auth.changerMotDePasse(
        ancien: _temporaire.text,
        nouveau: _nouveau.text,
        confirmation: _confirmation.text,
      );
      if (mounted) widget.onChange();
    } on EchecChangementMotDePasse catch (e) {
      if (mounted) {
        setState(() => _erreur = e.champs['nouveau'] ?? e.champs['ancien'] ?? e.champs['confirmation'] ?? e.message);
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _deconnecter() async {
    await widget.auth.deconnecter();
    if (mounted) widget.onDeconnecte();
  }

  @override
  Widget build(BuildContext context) {
    return CadreConnexion(
      titre: 'Changement de mot de passe obligatoire',
      sousTitre:
          "Un administrateur vous a donné un mot de passe temporaire. Choisissez maintenant votre propre mot de passe pour accéder à l'application.",
      enfants: [
        if (_erreur != null) ...[
          BandeauErreurConnexion(message: _erreur!),
          const SizedBox(height: AgriSpacing.md),
        ],
        ChampConnexion(
          libelle: 'MOT DE PASSE TEMPORAIRE',
          controleur: _temporaire,
          icone: SymbolesAgri.lock_outline,
          indice: '',
          masque: true,
          cleChamp: const Key('changement-temporaire'),
        ),
        const SizedBox(height: AgriSpacing.md),
        ChampConnexion(
          libelle: 'NOUVEAU MOT DE PASSE',
          controleur: _nouveau,
          icone: SymbolesAgri.lock_outline,
          indice: 'Min. 8 caractères, 1 majuscule, 1 chiffre',
          masque: true,
          cleChamp: const Key('changement-nouveau'),
        ),
        const SizedBox(height: AgriSpacing.md),
        ChampConnexion(
          libelle: 'CONFIRMER LE NOUVEAU MOT DE PASSE',
          controleur: _confirmation,
          icone: SymbolesAgri.lock_outline,
          indice: '',
          masque: true,
          cleChamp: const Key('changement-confirmation'),
          onSubmitted: _enregistrer,
        ),
        const SizedBox(height: AgriSpacing.md),
        BoutonConnexion(
          cle: const Key('bouton-changement-mot-de-passe'),
          libelle: 'ENREGISTRER LE MOT DE PASSE',
          enCours: _enCours,
          onPressed: _enregistrer,
        ),
        const SizedBox(height: AgriSpacing.md),
        Center(
          child: TextButton(
            key: const Key('changement-se-deconnecter'),
            onPressed: _deconnecter,
            child: const Text(
              'Se déconnecter',
              style: TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.w600, color: AgriColors.outline),
            ),
          ),
        ),
      ],
    );
  }
}
