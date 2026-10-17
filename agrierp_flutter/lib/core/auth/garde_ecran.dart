import 'package:flutter/material.dart';

import '../theme/agri_tokens.dart';
import 'permissions_poste.dart';

/// Garde d'accès posée SUR l'écran lui-même.
///
/// ⚠️ **MASQUER UNE ENTRÉE DE MENU N'EST PAS UNE AUTORISATION.** C'est une
/// règle explicite du projet côté serveur (« RBAC à deux niveaux »), et elle
/// vaut ici : l'état d'un écran est modifiable, une navigation peut être
/// rétablie par un défaut de code, et un écran atteint autrement resterait
/// pleinement fonctionnel. Le refus doit donc être posé à l'endroit qui rend.
///
/// La maquette montre un voile plein écran (`show403Overlay`) plutôt qu'une
/// page blanche : l'utilisateur doit comprendre qu'il n'a pas le droit, non
/// croire à une panne.
class GardeEcran extends StatelessWidget {
  const GardeEcran({
    super.key,
    required this.role,
    required this.ecran,
    required this.enfant,
  });

  final String role;
  final EcranPoste ecran;
  final Widget enfant;

  @override
  Widget build(BuildContext context) {
    if (PermissionsPoste.autorise(role, ecran)) return enfant;

    return Scaffold(
      backgroundColor: AgriColors.brandForest,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AgriSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 64, color: AgriColors.accentYellow),
              const SizedBox(height: AgriSpacing.md),
              const Text(
                'Accès refusé',
                key: Key('acces-refuse'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AgriSpacing.sm),
              Text(
                // Le rôle est nommé : « accès refusé » sans dire à qui ni
                // pourquoi envoie l'utilisateur chercher une panne inexistante.
                'Votre rôle ($role) ne donne pas accès à cet écran.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
