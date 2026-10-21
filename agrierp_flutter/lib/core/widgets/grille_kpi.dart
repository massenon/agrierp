import 'package:flutter/material.dart';

import '../theme/agri_tokens.dart';
import 'carte_kpi.dart';

/// `grid grid-cols-2 md:grid-cols-4 gap-md` du web : les cartes KPI passent de DEUX à QUATRE colonnes dès 768 px
/// (`md:`, [AgriBreakpoints.moyen]). C'est [GrilleKpi] (rangées à hauteur du contenu, jamais de rapport fixe) avec le
/// nombre de colonnes choisi d'après la largeur.
class GrilleKpiAdaptative extends StatelessWidget {
  const GrilleKpiAdaptative({super.key, required this.cartes});

  final List<Widget> cartes;

  @override
  Widget build(BuildContext context) =>
      GrilleKpi(colonnes: AgriBreakpoints.moyen(context) ? 4 : 2, children: cartes);
}
