import 'package:flutter/material.dart';

import '../../core/theme/agri_tokens.dart';

/// Pièces communes aux onglets « Historique des Ventes » et « Retours et Avoirs » du hub Ventes & Devis : les deux Blade
/// (`historique-ventes.blade.php`, `retours-avoirs.blade.php`) dessinent les mêmes gabarits, écrits ici UNE fois.

/// `px-md py-sm text-left text-[10px] text-outline font-bold uppercase` — l'en-tête d'une colonne du tableau.
const TextStyle styleEnteteColonne = TextStyle(
  fontSize: 10,
  fontWeight: AgriTypography.gras,
  color: AgriColors.outline,
);

/// `text-xs` d'une cellule du tableau.
const TextStyle styleCellule = TextStyle(fontSize: AgriTypography.xs, color: AgriColors.onSurface);

/// `bg-white rounded-lg border border-outline-variant shadow-sm overflow-hidden` : le cadre d'un tableau.
class CadreTableau extends StatelessWidget {
  const CadreTableau({super.key, required this.enfant});

  final Widget enfant;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AgriColors.surfaceCard,
      border: Border.all(color: AgriColors.outlineVariant),
      borderRadius: BorderRadius.circular(AgriRadius.lg),
      boxShadow: AgriShadows.sm,
    ),
    child: enfant,
  );
}

/// Une cellule de [LigneTableau] : [flex] est la largeur relative de la colonne.
class ColonneTableau {
  const ColonneTableau(this.titre, this.flex, {this.droite = false});

  final String titre;
  final int flex;

  /// `text-right` : montants et actions.
  final bool droite;
}

/// Un tableau à colonnes proportionnelles, dont la LARGEUR MINIMALE ([largeur]) défile horizontalement (`overflow-x-auto`
/// du web ; au poste de bureau, pas de bascule en cartes sous 640 px : la fenêtre ne descend pas si bas).
///
/// En-tête `bg-surface-zebra border-b border-outline-variant`, lignes `border-b border-outline-variant` en alternance
/// blanc / `bg-surface-zebra` (la ligne d'indice impair est grise). Les clés de ligne sont `[clePrefixe]-N` (N : l'indice de la ligne).
class TableauAgri extends StatelessWidget {
  const TableauAgri({
    super.key,
    required this.colonnes,
    required this.lignes,
    required this.largeur,
    required this.clePrefixe,
    required this.videTexte,
    this.opaciteLigne,
    this.pied,
  });

  final List<ColonneTableau> colonnes;

  /// Cellules de chaque ligne, une par colonne.
  final List<List<Widget>> lignes;
  final double largeur;
  final String clePrefixe;

  /// `<td colspan class="px-md py-lg text-center text-outline">` de la ligne vide.
  final String videTexte;

  /// `opacity-50` d'une ligne annulée.
  final double Function(int index)? opaciteLigne;

  /// Pied du cadre (pagination), sous le défilement horizontal.
  final Widget? pied;

  @override
  Widget build(BuildContext context) => CadreTableau(
    enfant: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: largeur),
            child: SizedBox(
              width: largeur,
              child: Column(
                children: [
                  Container(
                    color: AgriColors.surfaceZebra,
                    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
                    child: Row(
                      children: [
                        for (final c in colonnes)
                          Expanded(
                            flex: c.flex,
                            child: Text(
                              c.titre.toUpperCase(),
                              textAlign: c.droite ? TextAlign.right : TextAlign.left,
                              style: styleEnteteColonne,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 1, color: AgriColors.outlineVariant),
                  if (lignes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.lg),
                      child: Center(
                        child: Text(
                          videTexte,
                          key: Key('$clePrefixe-vide'),
                          style: const TextStyle(color: AgriColors.outline),
                        ),
                      ),
                    ),
                  for (var i = 0; i < lignes.length; i++)
                    Opacity(
                      opacity: opaciteLigne?.call(i) ?? 1,
                      child: Container(
                        key: Key('$clePrefixe-$i'),
                        decoration: BoxDecoration(
                          color: i.isOdd ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
                          border: const Border(bottom: BorderSide(color: AgriColors.outlineVariant)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            for (var j = 0; j < colonnes.length; j++)
                              Expanded(
                                flex: colonnes[j].flex,
                                child: Align(
                                  alignment: colonnes[j].droite ? Alignment.centerRight : Alignment.centerLeft,
                                  child: lignes[i][j],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ?pied,
      ],
    ),
  );
}

/// `inline-flex items-center px-sm py-[2px] rounded-full text-[11px] font-bold border` : la pastille d'un statut.
class PastilleStatut extends StatelessWidget {
  const PastilleStatut({
    super.key,
    required this.libelle,
    required this.fond,
    required this.texte,
    required this.bord,
  });

  final String libelle;
  final Color fond;
  final Color texte;
  final Color bord;

  /// `bg-brand-emerald/10 text-brand-emerald border-brand-emerald/30`.
  const PastilleStatut.succes(String libelle, {Key? key})
    : this(
        key: key,
        libelle: libelle,
        fond: const Color(0x1A065F46),
        texte: AgriColors.brandEmerald,
        bord: const Color(0x4D065F46),
      );

  /// `bg-accent-yellow/20 text-brand-forest border-accent-yellow`.
  const PastilleStatut.attente(String libelle, {Key? key})
    : this(
        key: key,
        libelle: libelle,
        fond: const Color(0x33FFD55F),
        texte: AgriColors.brandForest,
        bord: AgriColors.accentYellow,
      );

  /// `bg-error-bg text-error-deep border-error-deep/30`.
  const PastilleStatut.erreur(String libelle, {Key? key})
    : this(
        key: key,
        libelle: libelle,
        fond: AgriColors.errorBg,
        texte: AgriColors.errorDeep,
        bord: const Color(0x4DBA1A1A),
      );

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.sm, vertical: 2),
    decoration: BoxDecoration(
      color: fond,
      border: Border.all(color: bord),
      borderRadius: BorderRadius.circular(AgriRadius.full),
    ),
    child: Text(libelle, style: TextStyle(fontSize: 11, fontWeight: AgriTypography.gras, color: texte)),
  );
}

/// `flex items-center gap-xs bg-brand-emerald hover:bg-brand-forest text-white font-bold text-xs px-md py-sm
/// rounded-full shadow-sm` : le bouton d'action d'un en-tête (« Nouveau Retour », « Nouvelle Vente »).
class BoutonEntete extends StatelessWidget {
  const BoutonEntete({super.key, required this.icone, required this.libelle, required this.onPressed});

  final IconData icone;
  final String libelle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: onPressed,
    icon: Icon(icone, size: 18),
    label: Text(libelle, style: const TextStyle(fontSize: AgriTypography.xs, fontWeight: AgriTypography.gras)),
    style: ElevatedButton.styleFrom(
      backgroundColor: AgriColors.brandEmerald,
      foregroundColor: Colors.white,
      elevation: 1,
      padding: const EdgeInsets.symmetric(horizontal: AgriSpacing.md, vertical: AgriSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AgriRadius.full)),
    ),
  );
}

/// L'en-tête d'un onglet : `h2 text-xl lg:text-2xl font-bold text-on-surface flex items-center gap-xs` (icône 26 px
/// `text-brand-emerald`) et le sous-titre `text-xs text-outline mt-xs`.
class TitreOnglet extends StatelessWidget {
  const TitreOnglet({super.key, required this.icone, required this.titre, required this.sousTitre});

  final IconData icone;
  final String titre;
  final String sousTitre;

  @override
  Widget build(BuildContext context) {
    final large = AgriBreakpoints.large(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icone, size: 26, color: AgriColors.brandEmerald),
            const SizedBox(width: AgriSpacing.xs),
            Flexible(
              child: Text(
                titre,
                style: TextStyle(
                  fontSize: large ? AgriTypography.xxl : AgriTypography.xl,
                  fontWeight: AgriTypography.gras,
                  color: AgriColors.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AgriSpacing.xs),
        Text(sousTitre, style: const TextStyle(fontSize: AgriTypography.xs, color: AgriColors.outline)),
      ],
    );
  }
}

/// `border-b border-outline-variant pb-md` : le trait sous l'en-tête d'un onglet.
class EnteteOnglet extends StatelessWidget {
  const EnteteOnglet({super.key, required this.enfant});

  final Widget enfant;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(bottom: AgriSpacing.md),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AgriColors.outlineVariant))),
    child: enfant,
  );
}

/// `<button class="p-1 …" title="…"><span class="material-symbols-outlined text-[18px]">…</span></button>` : le bouton
/// d'action d'une ligne de tableau — l'icône de 18 px et `p-1` (4 px) autour, soit 26 px, jamais les 48 px d'un
/// `IconButton` Material (deux boutons débordaient de la colonne « Actions »).
IconButton boutonIconeTableau({
  required Key cle,
  required IconData icone,
  required Color couleur,
  required VoidCallback? onPressed,
  String? infobulle,
}) => IconButton(
  key: cle,
  tooltip: infobulle,
  onPressed: onPressed,
  icon: Icon(icone, size: 18, color: couleur),
  padding: const EdgeInsets.all(AgriSpacing.xs),
  constraints: const BoxConstraints(),
  style: IconButton.styleFrom(minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
);
