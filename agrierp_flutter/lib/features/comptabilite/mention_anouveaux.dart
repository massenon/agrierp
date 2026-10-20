import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';
import '../../core/theme/symboles_agri.dart';
import 'soldes_exercice.dart';

/// Ticket EX2 — mention « À-nouveaux provisoires » (PRD `docs/prd/exercices-comptables.md`, R3 et § 7) : sous le titre
/// d'un état dont l'ouverture est CALCULÉE parce que l'exercice précédent est encore ouvert.
///
/// ⚠️ Transposition du composant web `resources/views/components/anouveaux-provisoires.blade.php` : même fond
/// (`bg-accent-yellow/10`, bordure `accent-yellow`), même sablier, mêmes textes MOT POUR MOT —
/// `test/bascule_exercice_parite_test.dart` lit le composant Blade et compare.
class MentionAnouveauxProvisoires extends StatelessWidget {
  const MentionAnouveauxProvisoires({super.key, required this.ouverture});

  final OuvertureExercice? ouverture;

  static const titre = 'À-nouveaux provisoires';

  /// Le paragraphe du composant web, `{{ $ouverture['precedent'] }}` → [precedent], `{{ $ouverture['annee'] }}` →
  /// [annee].
  static String explication({required int precedent, required int annee}) =>
      "L'exercice $precedent n'est pas clôturé : l'ouverture de l'exercice $annee est calculée à partir de ses soldes "
      "au 31/12/$precedent, avec le résultat de l'exercice $precedent (provisoire). Elle suit toute écriture passée "
      "en $precedent ; à la clôture, l'à-nouveau définitif la remplace sans changer aucun chiffre.";

  /// Suffixe du sous-titre des documents PDF, comme les exports du web.
  static const suffixeDocument = ' — À-nouveaux provisoires';

  @override
  Widget build(BuildContext context) {
    final o = ouverture;
    final precedent = o?.precedent;
    if (o == null || !o.provisoire || precedent == null) {
      return const SizedBox.shrink();
    }

    return Container(
      key: const Key('anouveaux-provisoires'),
      margin: const EdgeInsets.only(bottom: AgriSpacing.lg),
      padding: const EdgeInsets.all(AgriSpacing.sm),
      decoration: BoxDecoration(
        color: AgriColors.accentYellow.withValues(alpha: 0.10),
        border: Border.all(color: AgriColors.accentYellow),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            SymbolesAgri.hourglass_empty,
            size: 20,
            color: AgriColors.brandForest,
          ),
          const SizedBox(width: AgriSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  titre,
                  style: TextStyle(
                    fontSize: AgriTypography.xs,
                    fontWeight: AgriTypography.gras,
                    color: AgriColors.brandForest,
                  ),
                ),
                const SizedBox(height: AgriSpacing.xs),
                Text(
                  explication(precedent: precedent, annee: o.annee),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AgriColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
