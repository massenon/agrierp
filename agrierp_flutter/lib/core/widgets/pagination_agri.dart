import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../comptabilite/exercice_choisi.dart';
import '../theme/agri_tokens.dart';
import '../theme/symboles_agri.dart';

/// Ticket EX7 (EF9) — LE pied de pagination du poste, copie de `components/pagination.blade.php` (web, le maître) :
/// « 27 lignes dans l'exercice 2026 — page 1 sur 2 », puis « Précédent » / « Suivant » quand il y a plus d'une page.
/// [ExerciceChoisi.parPage] lignes par page. Libellés vérifiés contre le Blade (`test/selecteur_exercice_test.dart`).
class PaginationAgri extends StatelessWidget {
  const PaginationAgri({
    super.key,
    required this.nom,
    required this.total,
    required this.page,
    required this.annee,
    required this.onPage,
  });

  /// Nom de la liste (clés `pagination-<nom>`, `-precedent`, `-suivant`) : deux listes d'un écran ne se confondent pas.
  final String nom;
  final int total;

  /// Page affichée, à partir de 1.
  final int page;

  /// Exercice affiché.
  final int annee;
  final ValueChanged<int> onPage;

  /// Nombre de pages (au moins une, comme `lastPage()` de Laravel).
  static int pages(int total) => math.max(1, (total / ExerciceChoisi.parPage).ceil());

  /// La page [page] de [tout] (bornée aux pages existantes).
  static List<T> tranche<T>(List<T> tout, int page) {
    final p = page.clamp(1, pages(tout.length));
    return tout.skip((p - 1) * ExerciceChoisi.parPage).take(ExerciceChoisi.parPage).toList();
  }

  /// Le texte du Blade, mot pour mot.
  static String texte({required int total, required int page, required int pages, required int annee}) =>
      "$total ${total > 1 ? 'lignes' : 'ligne'} dans l'exercice $annee — page $page sur $pages";

  @override
  Widget build(BuildContext context) {
    final dernier = pages(total);
    final courante = page.clamp(1, dernier);
    // `text-xs font-bold px-sm py-1 rounded-lg border border-outline-variant text-brand-forest`, `disabled:opacity-50`.
    final style = OutlinedButton.styleFrom(
      foregroundColor: AgriColors.brandForest,
      side: const BorderSide(color: AgriColors.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: AgriSpacing.xs),
      textStyle: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
    );
    return Container(
      key: Key('pagination-$nom'),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
      decoration: const BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border(top: BorderSide(color: AgriColors.outlineVariant)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AgriSpacing.sm,
        runSpacing: AgriSpacing.sm,
        children: [
          Text(
            texte(total: total, page: courante, pages: dernier, annee: annee),
            style: const TextStyle(fontSize: 11, color: AgriColors.outline),
          ),
          if (dernier > 1)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  key: Key('pagination-$nom-precedent'),
                  style: style,
                  onPressed: courante > 1 ? () => onPage(courante - 1) : null,
                  icon: const Icon(SymbolesAgri.chevron_left, size: 16),
                  label: const Text('Précédent'),
                ),
                const SizedBox(width: AgriSpacing.xs),
                OutlinedButton(
                  key: Key('pagination-$nom-suivant'),
                  style: style,
                  onPressed: courante < dernier ? () => onPage(courante + 1) : null,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('Suivant'), Icon(SymbolesAgri.chevron_right, size: 16)],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
