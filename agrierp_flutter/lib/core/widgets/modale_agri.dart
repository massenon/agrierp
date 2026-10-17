import 'package:flutter/material.dart';

import '../theme/agri_tokens.dart';

/// Largeurs de modale du prototype — `max-w-sm`, `max-w-md`, `max-w-lg`.
///
/// ⚠️ Ce sont les trois seules employées : 31 modales en `max-w-sm`, 51 en
/// `max-w-md`, 41 en `max-w-lg`. La racine valant 16 px, elles mesurent
/// respectivement 24, 28 et 32 rem.
enum LargeurModale {
  sm(384),
  md(448),
  lg(512);

  const LargeurModale(this.pixels);

  final double pixels;
}

/// Gabarit de modale du prototype, relevé sur les 125 modales qui le
/// partagent.
///
/// ```html
/// <div class="hidden fixed inset-0 bg-black/50 z-[100] flex items-center
///             justify-center p-md">
///   <div class="bg-white rounded-lg shadow-xl w-full max-w-md p-lg
///               max-h-[90vh] overflow-y-auto">
///     <div class="flex items-center justify-between mb-md">
///       <h3 class="font-bold text-lg text-brand-forest">Titre</h3>
///       <button aria-label="Fermer"
///               class="text-outline hover:text-error-deep">✕</button>
///     </div>
///     …contenu…
///     <div class="flex justify-end gap-sm pt-sm border-t
///                 border-outline-variant">…</div>
///   </div>
/// </div>
/// ```
///
/// ⚠️⚠️ **UN `AlertDialog` N'EST PAS CETTE MODALE.** Le composant Material par
/// défaut porte ses propres marges, sa propre typographie de titre, son propre
/// alignement de boutons et n'a **ni bouton de fermeture ✕ ni séparateur de
/// pied**. Cinq écrans du poste l'employaient : ils affichaient une boîte de
/// dialogue Material là où le commanditaire a validé la modale ci-dessus.
///
/// ⚠️ **LE PIED PORTE `rounded-lg`, PAS `rounded-full`.** Les boutons d'action
/// des en-têtes sont en pilule (`rounded-full`) ; ceux des pieds de modale
/// sont à coins arrondis de 8 px. Les deux se ressemblent assez pour qu'on les
/// confonde, et assez peu pour que ça se voie.
class ModaleAgri extends StatelessWidget {
  const ModaleAgri({
    super.key,
    required this.titre,
    required this.contenu,
    this.surtitre,
    this.actions = const [],
    this.largeur = LargeurModale.md,
  });

  final String titre;
  final Widget contenu;

  /// Petit intitulé au-dessus du titre.
  ///
  /// ⚠️ **DEUX LIBELLÉS, PAS UN SEUL FUSIONNÉ.** La modale de vente à la
  /// pièce porte « Vente à la Pièce » en intitulé d'opération et le nom du
  /// produit en dessous. Les réunir en une seule chaîne remplace deux
  /// libellés validés par un troisième qui n'existe nulle part — c'est un
  /// renommage, pas une traduction.
  final String? surtitre;

  /// Boutons du pied, dans l'ordre de la maquette : secondaire puis primaire.
  final List<Widget> actions;

  final LargeurModale largeur;

  /// `max-h-[90vh] overflow-y-auto` — la modale ne dépasse jamais l'écran, son
  /// contenu défile.
  static const double fractionHauteurMax = 0.9;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      // `p-md` autour du panneau, et non les marges par défaut de Material.
      insetPadding: const EdgeInsets.all(AgriSpacing.md),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: largeur.pixels,
        constraints: BoxConstraints(
          maxWidth: largeur.pixels,
          maxHeight: MediaQuery.sizeOf(context).height * fractionHauteurMax,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          boxShadow: AgriShadows.xl,
        ),
        // ⚠️ **LE PANNEAU EST UN `Material`, PAS UN FOND PEINT.** Un
        // `DecoratedBox` colore la modale mais ne fournit AUCUNE surface aux
        // enfants : les `ListTile` du sélecteur de bande y perdent leur fond
        // et leurs ondes, et Flutter lève une assertion. Le fond est donc
        // porté par le `Material`, l'ombre par le conteneur.
        child: Material(
          color: AgriColors.surfaceCard,
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AgriSpacing.lg,
                  AgriSpacing.lg,
                  AgriSpacing.lg,
                  AgriSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (surtitre != null)
                            Text(
                              surtitre!,
                              style: const TextStyle(
                                fontSize: AgriTypography.xs,
                                fontWeight: AgriTypography.gras,
                                color: AgriColors.outline,
                              ),
                            ),
                          Text(
                            titre,
                            style: const TextStyle(
                              fontSize: AgriTypography.lg,
                              fontWeight: AgriTypography.gras,
                              color: AgriColors.brandForest,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ⚠️ Le ✕ de la maquette : `aria-label="Fermer"`, gris qui
                    // passe au rouge profond au survol.
                    InkWell(
                      key: const Key('modale-fermer'),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(AgriSpacing.xs),
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: AgriColors.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AgriSpacing.lg,
                  ),
                  child: contenu,
                ),
              ),
              if (actions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: AgriSpacing.md),
                  padding: const EdgeInsets.fromLTRB(
                    AgriSpacing.lg,
                    AgriSpacing.sm,
                    AgriSpacing.lg,
                    AgriSpacing.lg,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AgriColors.outlineVariant),
                    ),
                  ),
                  // ⚠️ `Wrap` ET NON `Row` : `flex justify-end gap-sm` d'un
                  // navigateur laisse les boutons passer à la ligne quand le
                  // libellé est long (« Enregistrer la Saillie », « Valider le
                  // Décaissement »). Une `Row` déborde à la place — et le
                  // débordement ne se voit qu'au rendu.
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AgriSpacing.sm,
                    runSpacing: AgriSpacing.sm,
                    children: actions,
                  ),
                )
              else
                const SizedBox(height: AgriSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modale de confirmation du prototype — gabarit distinct, employé 31 fois.
///
/// ```html
/// <div class="hidden fixed inset-0 bg-black/60 z-[120] flex items-center
///             justify-center p-md">
///   <div class="bg-white rounded-lg shadow-xl w-full max-w-sm p-lg text-center">
///     <span class="material-symbols-outlined text-brand-emerald"
///           style="font-size:52px;">check_circle</span>
///     <h3 class="font-bold text-lg text-brand-forest mt-sm">Titre</h3>
///     <p class="text-xs text-outline mt-xs">Message</p>
///     <div class="flex flex-col gap-sm mt-lg">…boutons pleine largeur…</div>
///   </div>
/// </div>
/// ```
///
/// ⚠️⚠️ **CE N'EST PAS LA MÊME MODALE QUE [ModaleAgri].** Elle est **centrée**,
/// porte une **grande icône de 52 px**, **n'a pas de bouton ✕**, ses boutons
/// sont **empilés sur toute la largeur** et son voile est plus sombre
/// (`bg-black/60`). Les traiter comme une seule et même modale ferait perdre
/// la moitié de ces sept différences.
class ModaleConfirmation extends StatelessWidget {
  const ModaleConfirmation({
    super.key,
    required this.icone,
    required this.titre,
    required this.message,
    this.couleurIcone = AgriColors.brandEmerald,
    this.actions = const [],
    this.detail,
  });

  final IconData icone;
  final String titre;
  final String message;
  final Color couleurIcone;

  /// Boutons empilés, pleine largeur, dans l'ordre de la maquette.
  final List<Widget> actions;

  /// Ligne supplémentaire sous le message — une référence, par exemple.
  final Widget? detail;

  /// `font-size:52px` du prototype.
  static const double tailleIcone = 52;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AgriSpacing.md),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: LargeurModale.sm.pixels,
        constraints: BoxConstraints(
          maxWidth: LargeurModale.sm.pixels,
          maxHeight:
              MediaQuery.sizeOf(context).height * ModaleAgri.fractionHauteurMax,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          boxShadow: AgriShadows.xl,
        ),
        child: Material(
          color: AgriColors.surfaceCard,
          borderRadius: BorderRadius.circular(AgriRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(AgriSpacing.lg),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(icone, size: tailleIcone, color: couleurIcone),
                  const SizedBox(height: AgriSpacing.sm),
                  Text(
                    titre,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: AgriTypography.lg,
                      fontWeight: AgriTypography.gras,
                      color: AgriColors.brandForest,
                    ),
                  ),
                  const SizedBox(height: AgriSpacing.xs),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: AgriTypography.xs,
                      color: AgriColors.outline,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: AgriSpacing.xs),
                    detail!,
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: AgriSpacing.lg),
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(height: AgriSpacing.sm),
                      actions[i],
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton secondaire du pied — « Annuler », « Fermer ».
///
/// `px-md py-sm rounded-lg border border-outline-variant text-sm font-semibold
///  text-outline hover:bg-surface-zebra`
class BoutonModaleSecondaire extends StatelessWidget {
  const BoutonModaleSecondaire({
    super.key,
    required this.libelle,
    required this.onPressed,
  });

  final String libelle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AgriColors.outline,
        side: const BorderSide(color: AgriColors.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.md,
          vertical: AgriSpacing.sm,
        ),
      ),
      child: Text(
        libelle,
        style: const TextStyle(
          fontSize: AgriTypography.sm,
          fontWeight: AgriTypography.demiGras,
        ),
      ),
    );
  }
}

/// Bouton primaire du pied — « Enregistrer », « Valider… ».
///
/// `px-md py-sm rounded-lg bg-brand-emerald text-white text-sm font-bold
///  hover:bg-brand-forest`
class BoutonModalePrimaire extends StatelessWidget {
  const BoutonModalePrimaire({
    super.key,
    required this.libelle,
    required this.onPressed,
  });

  final String libelle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AgriColors.brandEmerald,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AgriRadius.lg),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AgriSpacing.md,
          vertical: AgriSpacing.sm,
        ),
      ),
      child: Text(
        libelle,
        style: const TextStyle(
          fontSize: AgriTypography.sm,
          fontWeight: AgriTypography.gras,
        ),
      ),
    );
  }
}

/// Ouvre une modale au gabarit du prototype.
///
/// ⚠️ **LE VOILE EST `bg-black/50`**, pas la valeur par défaut de Material
/// (`Colors.black54`, soit 54 %). Deux teintes assez proches pour passer
/// inaperçues côte à côte, et assez différentes pour qu'une comparaison
/// écran-à-écran les sépare.
Future<T?> afficherModale<T>({
  required BuildContext context,
  required WidgetBuilder constructeur,
  bool fermableParVoile = true,
  bool confirmation = false,
}) {
  return showDialog<T>(
    context: context,
    // ⚠️ `bg-black/50` pour une modale de saisie, `bg-black/60` pour une
    // confirmation : le prototype assombrit davantage quand il attend une
    // décision.
    barrierColor: confirmation
        ? const Color(0x99000000)
        : const Color(0x80000000),
    barrierDismissible: fermableParVoile,
    builder: constructeur,
  );
}
