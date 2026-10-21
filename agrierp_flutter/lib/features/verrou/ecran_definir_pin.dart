import 'package:flutter/material.dart';

import '../../core/auth/verrou_local.dart';
import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import '../auth/login_screen.dart';
import 'pave_pin.dart';

/// Ticket VL-1 — « Définir votre code PIN » : saisie puis confirmation, OBLIGATOIRE (aucune sortie « Plus tard »,
/// le client veut le verrou à chaque lancement). Montré après une connexion en ligne réussie, ou au lancement d'une
/// session restaurée qui n'a pas encore de PIN.
class EcranDefinirPin extends StatefulWidget {
  const EcranDefinirPin({
    super.key,
    required this.verrou,
    required this.idUtilisateur,
    required this.nomUtilisateur,
    required this.identifiant,
    required this.onDefini,
  });

  final VerrouLocal verrou;
  final String idUtilisateur;
  final String nomUtilisateur;
  final String identifiant;
  final VoidCallback onDefini;

  @override
  State<EcranDefinirPin> createState() => _EcranDefinirPinState();
}

class _EcranDefinirPinState extends State<EcranDefinirPin> {
  String? _premier;
  String? _erreur;
  final _pave = ControleurPave();
  late final _champIdentifiant = TextEditingController(text: widget.identifiant);

  @override
  void dispose() {
    _champIdentifiant.dispose();
    super.dispose();
  }

  Future<void> _valider(String pin) async {
    if (!VerrouLocal.pinValide(pin)) {
      setState(() {
        _premier = null;
        _erreur = 'Le code PIN comporte de 4 à 6 chiffres.';
      });
      return;
    }
    final premier = _premier;
    if (premier == null) {
      setState(() {
        _premier = pin;
        _erreur = null;
      });
      return;
    }
    if (premier != pin) {
      setState(() {
        _premier = null;
        _erreur = 'Les deux codes ne correspondent pas. Recommencez.';
      });
      return;
    }
    await widget.verrou.definir(widget.idUtilisateur, pin);
    if (mounted) widget.onDefini();
  }

  @override
  Widget build(BuildContext context) {
    final confirmation = _premier != null;

    return CadreConnexion(
      titre: confirmation ? 'Confirmez votre code PIN' : 'Définir votre code PIN',
      sousTitre: confirmation
          ? 'Saisissez le même code une seconde fois.'
          : "De 4 à 6 chiffres. Il sera demandé à chaque lancement de l'application, même sans réseau.",
      enfants: [
        if (_erreur != null) ...[
          KeyedSubtree(
            key: const Key('verrou-message'),
            child: BandeauErreurConnexion(message: _erreur!),
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
        Text(
          confirmation ? 'CONFIRMER LE CODE PIN' : 'CODE PIN',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: AgriColors.brandForest,
          ),
        ),
        const SizedBox(height: AgriSpacing.sm),
        PavePin(key: ValueKey(confirmation), controleur: _pave, onValider: _valider),
        const SizedBox(height: AgriSpacing.md),
        BoutonConnexion(
          cle: const Key('verrou-bouton'),
          libelle: confirmation ? 'CONFIRMER' : 'CONTINUER',
          enCours: false,
          onPressed: _pave.valider,
        ),
      ],
    );
  }
}
