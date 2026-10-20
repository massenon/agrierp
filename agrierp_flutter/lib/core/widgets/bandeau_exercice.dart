import 'package:flutter/material.dart';

import '../comptabilite/exercice_choisi.dart';
import '../theme/agri_tokens.dart';
import '../theme/symboles_agri.dart';

/// Ticket EX7 (EF10, PRD § 7) — copie de `livewire/shared/bandeau-exercice.blade.php` : en haut du contenu, tant que
/// l'exercice affiché est clos, « Exercice 2026 clôturé — lecture seule. Les saisies se font dans l'exercice 2027. »
/// et le lien « Passer à 2027 ». Rien hors du socle (pas de [PorteeExerciceChoisi]) ni pour un exercice ouvert.
class BandeauExercice extends StatelessWidget {
  const BandeauExercice({super.key});

  @override
  Widget build(BuildContext context) {
    final service = PorteeExerciceChoisi.de(context);
    final bandeau = service?.etat?.bandeau;
    if (service == null || bandeau == null) return const SizedBox.shrink();
    final cible = bandeau.cible;

    // `bg-surface-zebra border border-outline-variant rounded-lg p-sm mb-lg`, cadenas `text-outline` 20 px.
    return Container(
      key: const Key('bandeau-exercice'),
      margin: const EdgeInsets.fromLTRB(AgriSpacing.lg, AgriSpacing.lg, AgriSpacing.lg, 0),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.surfaceZebra,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        children: [
          const Icon(SymbolesAgri.lock, size: 20, color: AgriColors.outline),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: Text(
              bandeau.texte,
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.bold,
                color: AgriColors.onSurface,
              ),
            ),
          ),
          if (cible != null)
            TextButton(
              key: const Key('bandeau-exercice-passer'),
              onPressed: () => service.choisir(cible),
              style: TextButton.styleFrom(foregroundColor: AgriColors.brandEmerald),
              child: Text(
                'Passer à $cible',
                style: const TextStyle(
                  fontSize: AgriTypography.xs,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
