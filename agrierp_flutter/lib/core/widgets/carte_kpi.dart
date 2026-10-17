import 'package:flutter/material.dart';

import '../theme/agri_tokens.dart';

/// Carte d'indicateur du prototype — `dashboard.html` l.152, et la même sur
/// onze autres écrans.
///
/// Structure de la maquette, au caractère près :
///
/// ```html
/// <div class="bg-white p-md rounded-lg border border-outline-variant
///             border-l-4 border-l-brand-emerald shadow-sm">
///   <div class="flex justify-between items-start">
///     <span class="text-[10px] text-outline font-bold uppercase">…</span>
///     <span class="material-symbols-outlined text-[18px] …">…</span>
///   </div>
///   <span class="text-lg md:text-2xl font-extrabold block mt-xs truncate">…</span>
///   <p class="text-[10px] text-outline mt-xs">…</p>
/// </div>
/// ```
///
/// ⚠️⚠️ **LE LISERÉ DE GAUCHE EST UN `Positioned`, JAMAIS UN ENFANT ÉTIRÉ.**
/// La traduction naïve de `border-l-4` est un `Container(width: 4)` dans une
/// `Row(crossAxisAlignment: stretch)` — et elle lève « BoxConstraints forces
/// an infinite height » dès que la carte est placée dans une colonne
/// défilante, parce qu'un enfant étiré réclame une hauteur bornée que la
/// colonne ne donne pas. Le défaut ne se voit qu'au RENDU : ni l'analyseur ni
/// la compilation ne le signalent. Il s'est produit deux fois sur ce projet
/// (tickets F0.32 et F0.39) avant que la règle ne soit posée.
///
/// Avec `Stack`, la carte se dimensionne sur son contenu et le liseré s'étire
/// à la hauteur obtenue : la contrainte infinie ne peut plus exister.
///
/// ⚠️ **UNE SEULE IMPLÉMENTATION POUR TOUS LES ÉCRANS.** Elle vivait en
/// treize exemplaires recopiés, dont deux avaient déjà divergé sur la taille
/// du libellé. Deux copies d'un même composant finissent toujours par
/// diverger — c'est une question de temps.
class CarteKpi extends StatelessWidget {
  const CarteKpi({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.couleurLisere,
    this.unite,
    this.legende,
    this.icone,
    this.couleurIcone = AgriColors.brandEmerald,
    this.couleurValeur = AgriColors.onSurface,
    this.tailleValeur = 22,
  });

  /// Rendu en capitales, comme `uppercase` dans la maquette.
  final String libelle;

  final String valeur;

  /// Petite unité accolée à la valeur — « FCFA », « têtes », « produits ».
  final String? unite;

  /// Ligne de commentaire sous la valeur.
  final String? legende;

  final IconData? icone;
  final Color couleurIcone;
  final Color couleurValeur;
  final Color couleurLisere;
  final double tailleValeur;

  /// Épaisseur de `border-l-4`.
  static const double lisere = 4;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AgriColors.surfaceCard,
        border: Border.all(color: AgriColors.outlineVariant),
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        boxShadow: AgriShadows.sm,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AgriRadius.lg),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AgriSpacing.md + lisere,
                AgriSpacing.md,
                AgriSpacing.md,
                AgriSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          libelle.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: AgriTypography.gras,
                            color: AgriColors.outline,
                          ),
                        ),
                      ),
                      if (icone != null)
                        Icon(icone, size: 18, color: couleurIcone),
                    ],
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  // `truncate` de la maquette : la valeur ne pousse jamais la
                  // carte, elle se réduit.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          valeur,
                          style: TextStyle(
                            fontSize: tailleValeur,
                            fontWeight: AgriTypography.extraGras,
                            color: couleurValeur,
                          ),
                        ),
                        if (unite != null) ...[
                          const SizedBox(width: AgriSpacing.xs),
                          Text(
                            unite!,
                            style: const TextStyle(
                              fontSize: AgriTypography.xs,
                              fontWeight: AgriTypography.normal,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (legende != null && legende!.isNotEmpty) ...[
                    const SizedBox(height: AgriSpacing.xs),
                    Text(
                      legende!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AgriColors.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // ⚠️ `border-l-4` : posé, jamais étiré. Voir le docblock.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: lisere,
              child: ColoredBox(color: couleurLisere),
            ),
          ],
        ),
      ),
    );
  }
}
