import 'package:flutter/material.dart';

import '../comptabilite/exercice_choisi.dart';
import '../theme/agri_tokens.dart';
import '../theme/symboles_agri.dart';

/// Ticket EX7 (EF10, PRD § 7) — copie de `livewire/shared/bandeau-exercice.blade.php` : en haut du contenu, tant que
/// l'exercice affiché est clos, « Exercice 2026 clôturé — lecture seule. Les saisies se font dans l'exercice 2027. »
/// et le lien « Passer à 2027 » (qui CHOISIT l'exercice de saisie). Rien hors du socle (pas de
/// [PorteeExerciceChoisi]) ni pour un exercice ouvert.
class BandeauExercice extends StatelessWidget {
  const BandeauExercice({super.key});

  @override
  Widget build(BuildContext context) {
    final service = PorteeExerciceChoisi.de(context);
    final bandeau = service?.etat?.bandeau;
    if (service == null || bandeau == null) return const SizedBox.shrink();
    final cible = bandeau.cible;

    // `mb-lg` du Blade (`<x-bandeau-lecture-seule … class="mb-lg">`), au-dessus du contenu.
    return Padding(
      padding: const EdgeInsets.fromLTRB(AgriSpacing.lg, AgriSpacing.lg, AgriSpacing.lg, 0),
      child: BandeauLectureSeule(
        key: const Key('bandeau-exercice'),
        texte: bandeau.texte,
        cible: cible,
        onPasser: cible == null ? null : () => service.choisir(cible),
        clePasser: const Key('bandeau-exercice-passer'),
      ),
    );
  }
}

/// Fusion EX7 + EX8 — copie de `components/bandeau-lecture-seule.blade.php` : LE bandeau de lecture seule d'un exercice
/// clos, un seul widget pour le haut du contenu ([BandeauExercice], l'exercice affiché) et la tête du formulaire d'une
/// fiche d'élevage (EF12, l'exercice du jour choisi). `bg-surface-zebra border border-outline-variant rounded-lg
/// p-sm`, cadenas `text-outline` 20 px, texte `text-xs font-bold`, lien « Passer à … » `text-brand-emerald underline`.
class BandeauLectureSeule extends StatelessWidget {
  const BandeauLectureSeule({
    super.key,
    required this.texte,
    required this.cible,
    required this.onPasser,
    this.clePasser,
  });

  /// `ExerciceChoisi::bandeauDe()['texte']`.
  final String texte;

  /// L'année du lien « Passer à … » (`null` : aucun exercice ouvert, pas de lien).
  final int? cible;
  final VoidCallback? onPasser;
  final Key? clePasser;

  @override
  Widget build(BuildContext context) => Container(
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
            texte,
            style: const TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
              color: AgriColors.onSurface,
            ),
          ),
        ),
        if (cible != null && onPasser != null)
          TextButton(
            key: clePasser,
            onPressed: onPasser,
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
