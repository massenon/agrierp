import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../comptabilite/exercice_choisi.dart';
import '../theme/agri_tokens.dart';
import '../theme/symboles_agri.dart';

/// Ticket EX7 (EF9) — LE pied de pagination du poste, copie de `components/pagination.blade.php` (web, le maître) :
/// « 27 lignes dans l'exercice 2026 — page 1 sur 2 », puis « Précédent » / « Suivant » quand il y a plus d'une page.
/// [ExerciceChoisi.parPage] lignes par page. Libellés vérifiés contre le Blade (`test/selecteur_exercice_test.dart`).
///
/// Ticket E2 — extension : [perPage] optionnel (10 ou 25). Quand fourni, le widget affiche
/// « X–Y sur Z résultats » + sélecteur « Par page : [10] [25] » et appelle [onPerPageChanged].
/// [onPageChanged] est un alias optionnel pour [onPage] destiné aux nouveaux callers E2.
class PaginationAgri extends StatelessWidget {
  const PaginationAgri({
    super.key,
    required this.nom,
    required this.total,
    required this.page,
    required this.annee,
    required this.onPage,
    this.perPage,
    this.onPageChanged,
    this.onPerPageChanged,
  });

  /// Nom de la liste (clés `pagination-<nom>`, `-precedent`, `-suivant`) : deux listes d'un écran ne se confondent pas.
  final String nom;
  final int total;

  /// Page affichée, à partir de 1.
  final int page;

  /// Exercice affiché.
  final int annee;
  final ValueChanged<int> onPage;

  /// Ticket E2 — taille de page explicite (10 ou 25). Quand null, [ExerciceChoisi.parPage] s'applique (EX7).
  final int? perPage;

  /// Ticket E2 — alias optionnel pour [onPage] destiné aux nouveaux callers.
  final ValueChanged<int>? onPageChanged;

  /// Ticket E2 — callback appelé quand l'utilisateur choisit 10 ou 25.
  final ValueChanged<int>? onPerPageChanged;

  /// Nombre de pages (au moins une, comme `lastPage()` de Laravel).
  /// Si [parPage] est fourni (E2), il remplace [ExerciceChoisi.parPage].
  static int pages(int total, {int? parPage}) {
    final taille = parPage ?? ExerciceChoisi.parPage;
    return math.max(1, (total / taille).ceil());
  }

  /// La page [page] de [tout] (bornée aux pages existantes).
  /// Si [parPage] est fourni (E2), il remplace [ExerciceChoisi.parPage].
  static List<T> tranche<T>(List<T> tout, int page, {int? parPage}) {
    final taille = parPage ?? ExerciceChoisi.parPage;
    final p = page.clamp(1, pages(tout.length, parPage: taille));
    return tout.skip((p - 1) * taille).take(taille).toList();
  }

  /// Le texte du Blade, mot pour mot.
  static String texte({required int total, required int page, required int pages, required int annee}) =>
      "$total ${total > 1 ? 'lignes' : 'ligne'} dans l'exercice $annee — page $page sur $pages";

  @override
  Widget build(BuildContext context) {
    final dernier = pages(total, parPage: perPage);
    final courante = page.clamp(1, dernier);
    // `text-xs font-bold px-sm py-1 rounded-lg border border-outline-variant text-brand-forest`, `disabled:opacity-50`.
    final style = OutlinedButton.styleFrom(
      foregroundColor: AgriColors.brandForest,
      side: const BorderSide(color: AgriColors.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: AgriSpacing.xs),
      textStyle: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
    );
    // Ticket E2 : callback de changement de page, [onPageChanged] prime sur [onPage].
    void changerPage(int p) => (onPageChanged ?? onPage)(p);

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
          // Ticket E2 : quand [perPage] est fourni, affiche « X–Y sur Z résultats » ; sinon EX7.
          if (perPage != null) ...[
            Text(
              total > 0
                  ? '${(courante - 1) * perPage! + 1}–${math.min(courante * perPage!, total)} sur $total résultats'
                  : 'Aucun résultat',
              style: const TextStyle(fontSize: 11, color: AgriColors.outline),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Par page :', style: TextStyle(fontSize: 11, color: AgriColors.outline)),
                const SizedBox(width: AgriSpacing.xs),
                for (final n in [10, 25]) ...[
                  OutlinedButton(
                    key: Key('pagination-$nom-par-page-$n'),
                    style: n == perPage
                        ? OutlinedButton.styleFrom(
                            foregroundColor: AgriColors.surfaceCard,
                            backgroundColor: AgriColors.brandForest,
                            side: const BorderSide(color: AgriColors.brandForest),
                            padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: AgriSpacing.xs),
                            textStyle: const TextStyle(fontSize: AgriTypography.xs, fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.lg)),
                          )
                        : style,
                    onPressed: onPerPageChanged != null ? () => onPerPageChanged!(n) : null,
                    child: Text('$n'),
                  ),
                  const SizedBox(width: 2),
                ],
                if (dernier > 1) ...[
                  const SizedBox(width: AgriSpacing.xs),
                  OutlinedButton.icon(
                    key: Key('pagination-$nom-precedent'),
                    style: style,
                    onPressed: courante > 1 ? () => changerPage(courante - 1) : null,
                    icon: const Icon(SymbolesAgri.chevron_left, size: 16),
                    label: const Text('Précédent'),
                  ),
                  const SizedBox(width: AgriSpacing.xs),
                  OutlinedButton(
                    key: Key('pagination-$nom-suivant'),
                    style: style,
                    onPressed: courante < dernier ? () => changerPage(courante + 1) : null,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text('Suivant'), Icon(SymbolesAgri.chevron_right, size: 16)],
                    ),
                  ),
                ],
              ],
            ),
          ] else ...[
            // EX7 : « X lignes dans l'exercice YYYY — page N sur M »
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
                    onPressed: courante > 1 ? () => changerPage(courante - 1) : null,
                    icon: const Icon(SymbolesAgri.chevron_left, size: 16),
                    label: const Text('Précédent'),
                  ),
                  const SizedBox(width: AgriSpacing.xs),
                  OutlinedButton(
                    key: Key('pagination-$nom-suivant'),
                    style: style,
                    onPressed: courante < dernier ? () => changerPage(courante + 1) : null,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text('Suivant'), Icon(SymbolesAgri.chevron_right, size: 16)],
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
