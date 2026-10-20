import 'package:flutter/material.dart';

import '../comptabilite/exercice_choisi.dart';
import '../theme/agri_tokens.dart';
import '../theme/symboles_agri.dart';

/// Ticket EX7 (EF8, PRD § 7) — copie de `livewire/shared/selecteur-exercice.blade.php` : « Exercice 2027 ▾ » dans la
/// barre supérieure, à gauche de « Synchroniser » ; chaque exercice avec son badge « Ouvert » (vert), « Provisoire »
/// (ambre : à-nouveaux calculés) ou « Clôturé » (gris, cadenas). Le choix est mémorisé dans les paramètres locaux du
/// poste (`ExerciceChoisi.choisir`). Ouvert à tous les rôles : il ne choisit que ce qui s'affiche.
class SelecteurExercice extends StatelessWidget {
  const SelecteurExercice({super.key});

  @override
  Widget build(BuildContext context) {
    final service = PorteeExerciceChoisi.de(context);
    final etat = service?.etat;
    if (service == null || etat == null) return const SizedBox.shrink();
    final liste = etat.liste;

    return PopupMenuButton<int>(
      key: const Key('selecteur-exercice'),
      tooltip: 'Exercice affiché',
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        side: const BorderSide(color: AgriColors.outlineVariant),
      ),
      onSelected: service.choisir,
      itemBuilder: (_) => [
        // `px-md py-sm border-b font-bold text-xs text-brand-forest`.
        const PopupMenuItem<int>(
          enabled: false,
          height: 32,
          child: Text(
            'Exercice affiché',
            style: TextStyle(
              fontSize: AgriTypography.xs,
              fontWeight: FontWeight.bold,
              color: AgriColors.brandForest,
            ),
          ),
        ),
        if (liste.isEmpty)
          const PopupMenuItem<int>(
            enabled: false,
            child: Text(
              "Aucun exercice comptable n'est encore ouvert.",
              style: TextStyle(fontSize: 11, color: AgriColors.outline),
            ),
          ),
        for (final e in liste)
          PopupMenuItem<int>(
            key: Key('selecteur-exercice-${e.annee}'),
            value: e.annee,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Exercice ${e.annee}',
                    style: TextStyle(
                      fontSize: AgriTypography.xs,
                      fontWeight: e.choisi ? FontWeight.bold : FontWeight.normal,
                      color: e.choisi ? AgriColors.brandEmerald : AgriColors.onSurface,
                    ),
                  ),
                ),
                _Badge(entree: e),
              ],
            ),
          ),
      ],
      // `flex items-center gap-xs text-brand-forest font-semibold text-xs border rounded-full px-sm py-1`.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: AgriColors.outlineVariant),
          borderRadius: BorderRadius.circular(AgriRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(SymbolesAgri.calendar_month, size: 16, color: AgriColors.brandForest),
            const SizedBox(width: AgriSpacing.xs),
            Text(
              'Exercice ${etat.annee}',
              style: const TextStyle(
                fontSize: AgriTypography.xs,
                fontWeight: FontWeight.w600,
                color: AgriColors.brandForest,
              ),
            ),
            const Icon(SymbolesAgri.expand_more, size: 16, color: AgriColors.brandForest),
          ],
        ),
      ),
    );
  }
}

/// Badge du web : `bg-brand-emerald/10 text-brand-emerald` (Ouvert), `bg-accent-yellow/20 text-brand-forest border-accent-yellow`
/// (Provisoire), `bg-surface-zebra text-outline` + cadenas (Clôturé).
class _Badge extends StatelessWidget {
  const _Badge({required this.entree});

  final EntreeExercice entree;

  @override
  Widget build(BuildContext context) {
    final (fond, texte, bord) = switch (entree.statut) {
      'ouvert' => (
        AgriColors.brandEmerald.withValues(alpha: 0.10),
        AgriColors.brandEmerald,
        AgriColors.brandEmerald.withValues(alpha: 0.30),
      ),
      'provisoire' => (
        AgriColors.accentYellow.withValues(alpha: 0.20),
        AgriColors.brandForest,
        AgriColors.accentYellow,
      ),
      _ => (AgriColors.surfaceZebra, AgriColors.outline, AgriColors.outlineVariant),
    };
    return Container(
      key: Key('badge-exercice-${entree.annee}'),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: fond,
        border: Border.all(color: bord),
        borderRadius: BorderRadius.circular(AgriRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entree.statut == 'cloture') ...[
            Icon(SymbolesAgri.lock, size: 12, color: texte),
            const SizedBox(width: 2),
          ],
          Text(
            entree.libelle,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: texte),
          ),
        ],
      ),
    );
  }
}
