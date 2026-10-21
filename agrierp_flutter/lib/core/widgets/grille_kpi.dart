import 'package:flutter/material.dart';

import '../theme/agri_tokens.dart';

/// `grid grid-cols-2 md:grid-cols-4 gap-md` du web : une grille de cartes KPI qui passe de DEUX à QUATRE colonnes dès
/// 768 px (`md:`, [AgriBreakpoints.moyen]), jamais à 1 024 px.
///
/// ⚠️ **CHAQUE CARTE PREND LA HAUTEUR DE SON CONTENU**, comme la grille CSS (la rangée suit sa plus haute carte) : un
/// `GridView` à rapport fixe faisait déborder la légende sur deux lignes (bandeau jaune et noir, bug de « Rotation du
/// Stock », ticket U11). Chaque rangée est une `IntrinsicHeight` dont les cartes s'étirent à la plus haute.
class GrilleKpi extends StatelessWidget {
  const GrilleKpi({super.key, required this.cartes});

  final List<Widget> cartes;

  @override
  Widget build(BuildContext context) {
    final colonnes = AgriBreakpoints.moyen(context) ? 4 : 2;

    return Column(
      children: [
        for (var debut = 0; debut < cartes.length; debut += colonnes) ...[
          if (debut > 0) const SizedBox(height: AgriSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < colonnes; i++) ...[
                  if (i > 0) const SizedBox(width: AgriSpacing.md),
                  Expanded(child: debut + i < cartes.length ? cartes[debut + i] : const SizedBox.shrink()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
