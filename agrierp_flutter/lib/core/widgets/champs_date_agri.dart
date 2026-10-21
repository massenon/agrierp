import 'package:flutter/material.dart';

import '../theme/agri_tokens.dart';
import '../theme/symboles_agri.dart';

/// Ticket MP1 — LES CHAMPS « DATE » ET « MOIS » DU WEB, UNE SEULE FOIS.
///
/// Les écrans du poste dessinaient chacun leur champ Date (`OutlinedButton`, `InputDecorator`, `Container` à la main),
/// avec des hauteurs, des marges et des libellés qui dérivaient du Blade. Les cinq gabarits du web sont ici, chacun
/// avec les classes Tailwind qu'il traduit (`docs/AUDIT_FIDELITE_ECRANS.md` § 9) ; les valeurs viennent de
/// [AgriChamps], [AgriSpacing] et [AgriTypography], jamais de nombres en dur. Le garde-fou
/// `test/champs_date_mise_en_page_test.dart` mesure ces champs et relit les classes du Blade.
///
/// ⚠️ Le calendrier s'ouvre dans le `showDatePicker` de Flutter : le sélecteur natif d'un navigateur n'existe pas au
/// poste. L'indicateur de calendrier que le navigateur dessine à droite d'un `<input type="date">` est reproduit
/// (icône de [AgriChamps.iconeCalendrier]) : sans lui, le champ serait ~ 25 px plus étroit que celui du web.

/// Styles de texte des champs Date / Mois : taille, graisse, couleur ET interligne du Blade.
abstract final class StylesChampsAgri {
  static const double _interligneXs = AgriTypography.xsInterligne / AgriTypography.xs;

  /// `text-xs text-outline font-semibold` : « Bande : », « Date : », « Mois : ».
  static const etiquetteEnLigne = TextStyle(
    fontSize: AgriTypography.xs,
    fontWeight: AgriTypography.demiGras,
    color: AgriColors.outline,
    height: _interligneXs,
  );

  /// `text-xs font-bold text-brand-forest` : valeur d'un sélecteur de l'en-tête des fiches et du Grand Livre.
  static const valeurFiche = TextStyle(
    fontSize: AgriTypography.xs,
    fontWeight: AgriTypography.gras,
    color: AgriColors.brandForest,
    height: _interligneXs,
  );

  /// `text-xs` : valeur d'un champ de filtre (début / fin d'une période).
  static const valeurFiltre = TextStyle(
    fontSize: AgriTypography.xs,
    color: AgriColors.onSurface,
    height: _interligneXs,
  );

  /// « au » entre deux champs de période : `text-xs text-outline`.
  static const motPeriode = TextStyle(
    fontSize: AgriTypography.xs,
    color: AgriColors.outline,
    height: _interligneXs,
  );

  /// `block text-[10px] text-brand-forest font-bold uppercase mb-xs` (la marge est posée par le champ).
  static const etiquetteFormulaire = TextStyle(
    fontSize: AgriChamps.etiquetteFormulaire,
    fontWeight: AgriTypography.gras,
    color: AgriColors.brandForest,
    height: AgriTypography.interligneCorps,
  );

  /// `text-sm` : valeur d'un champ de formulaire.
  static const valeurFormulaire = TextStyle(
    fontSize: AgriTypography.sm,
    color: AgriColors.onSurface,
    height: AgriTypography.smInterligne / AgriTypography.sm,
  );

  /// `text-xs` : valeur du champ « Date de la vente » de la caisse (`h-10 … text-xs`).
  static const valeurCaisse = valeurFiltre;

  /// `.invalid-feedback` : 11 px, `#BA1A1A`.
  static const erreur = TextStyle(
    fontSize: AgriChamps.erreurTaille,
    color: AgriColors.errorDeep,
  );

  /// Format d'affichage d'un `<input type="date">` en français : `jj/mm/aaaa`.
  static String jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Fond d'un champ en erreur : `.is-invalid { background-color: #FFF5F5 }` de `resources/css/app.css`.
const Color kFondChampInvalide = Color(0xFFFFF5F5);

/// L'indicateur de calendrier du navigateur : icône de [AgriChamps.iconeCalendrier], à droite de la valeur.
class _IndicateurCalendrier extends StatelessWidget {
  const _IndicateurCalendrier();

  @override
  Widget build(BuildContext context) =>
      const Icon(SymbolesAgri.calendar_today, size: AgriChamps.iconeCalendrier, color: AgriColors.outline);
}

/// Cadre d'un champ : trait `border-outline-variant`, `rounded-lg`, fond plein, vague d'encre du toucher.
/// [hauteur] est EXPLICITE (la mise en page ne dépend pas de la métrique du moteur de texte).
class _CadreChamp extends StatelessWidget {
  const _CadreChamp({
    required this.cle,
    required this.hauteur,
    required this.fond,
    required this.margeHorizontale,
    required this.enfant,
    this.onTap,
    this.couleurTrait = AgriColors.outlineVariant,
    this.pleineLargeur = false,
  });

  final Key? cle;
  final double hauteur;
  final Color fond;
  final double margeHorizontale;
  final Widget enfant;
  final VoidCallback? onTap;
  final Color couleurTrait;

  /// `true` : le cadre remplit la largeur offerte (`w-full`) ; `false` : il épouse son contenu.
  final bool pleineLargeur;

  @override
  Widget build(BuildContext context) {
    final bord = BorderRadius.circular(AgriRadius.lg);
    return Material(
      color: fond,
      shape: RoundedRectangleBorder(
        borderRadius: bord,
        side: BorderSide(color: couleurTrait, width: AgriChamps.bordure),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: cle,
        onTap: onTap,
        child: SizedBox(
          height: hauteur,
          child: Padding(
            // `border-box` : le trait occupe la place d'un pixel de plus avant le texte.
            padding: EdgeInsets.symmetric(horizontal: margeHorizontale + AgriChamps.bordure),
            child: pleineLargeur
                ? enfant
                : Align(alignment: Alignment.centerLeft, widthFactor: 1, child: enfant),
          ),
        ),
      ),
    );
  }
}

/// « Date : » / « Bande : » / « Mois : » — libellé en ligne de l'en-tête des fiches journalières.
class EtiquetteEnLigneFiche extends StatelessWidget {
  const EtiquetteEnLigneFiche(this.texte, {super.key});

  final String texte;

  @override
  Widget build(BuildContext context) => Text(texte, style: StylesChampsAgri.etiquetteEnLigne);
}

/// Sélecteur de l'en-tête des fiches : `h-9 px-md border rounded-lg bg-surface-zebra`. [enfant] est la valeur
/// (liste déroulante de la bande, date) ; le trait et le fond sont ceux du Blade.
class CadreSelectionFiche extends StatelessWidget {
  const CadreSelectionFiche({super.key, required this.cle, required this.enfant, this.onTap, this.avecCalendrier = false});

  final Key cle;
  final Widget enfant;
  final VoidCallback? onTap;

  /// Ajoute l'indicateur de calendrier du navigateur après la valeur (champ Date).
  final bool avecCalendrier;

  @override
  Widget build(BuildContext context) => _CadreChamp(
    cle: cle,
    hauteur: AgriChamps.hauteurCompacte,
    fond: AgriColors.surfaceZebra,
    margeHorizontale: AgriSpacing.md,
    onTap: onTap,
    enfant: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        enfant,
        if (avecCalendrier) ...[
          const SizedBox(width: AgriSpacing.lg),
          const _IndicateurCalendrier(),
        ],
      ],
    ),
  );
}

/// Champ « Date : » de l'en-tête des fiches (`<input type="date" class="h-9 px-md … bg-surface-zebra">`).
class ChampDateFiche extends StatelessWidget {
  const ChampDateFiche({super.key, required this.cle, required this.valeur, required this.onTap, this.cleTexte});

  final Key cle;
  final Key? cleTexte;
  final DateTime valeur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CadreSelectionFiche(
    cle: cle,
    onTap: onTap,
    avecCalendrier: true,
    enfant: Text(StylesChampsAgri.jour(valeur), key: cleTexte, style: StylesChampsAgri.valeurFiche),
  );
}

/// La barre de choix d'une fiche : `flex items-center gap-xs flex-wrap`. Chaque libellé et chaque champ est un
/// enfant PROPRE de la barre, comme au Blade : à largeur réduite ils se replient un par un, à `gap-xs` dans les deux
/// sens.
class BarreChoixFiche extends StatelessWidget {
  const BarreChoixFiche({super.key, required this.enfants});

  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AgriSpacing.xs,
    runSpacing: AgriSpacing.xs,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: enfants,
  );
}

/// Champ de période d'un filtre : `<input type="date" class="text-xs border border-outline-variant rounded-lg px-sm
/// py-2 bg-white">` (34 px) ; [compact] : `py-1.5` (30 px). [desactive] : le champ du Tableau de bord, grisé.
class ChampDateFiltre extends StatelessWidget {
  const ChampDateFiltre({
    super.key,
    required this.cle,
    required this.valeur,
    this.onTap,
    this.compact = false,
    this.desactive = false,
  });

  final Key cle;
  final DateTime valeur;
  final VoidCallback? onTap;
  final bool compact;
  final bool desactive;

  /// Hauteur du champ : interligne + marges verticales + deux traits.
  static double hauteur({required bool compact}) => AgriChamps.hauteurFiltre(
    margeVerticale: compact ? AgriChamps.margeVerticaleCompacte : AgriSpacing.sm,
  );

  @override
  Widget build(BuildContext context) => _CadreChamp(
    cle: cle,
    hauteur: hauteur(compact: compact),
    fond: desactive ? AgriColors.surfaceZebra : AgriColors.surfaceCard,
    margeHorizontale: AgriSpacing.sm,
    onTap: desactive ? null : onTap,
    enfant: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            StylesChampsAgri.jour(valeur),
            overflow: TextOverflow.ellipsis,
            style: desactive
                ? StylesChampsAgri.valeurFiltre.copyWith(color: AgriColors.outline)
                : StylesChampsAgri.valeurFiltre,
          ),
        ),
        const SizedBox(width: AgriSpacing.lg),
        const _IndicateurCalendrier(),
      ],
    ),
  );
}

/// Champ de période du Grand Livre : `text-xs font-bold text-brand-forest border-0 bg-transparent p-1`, dans la zone
/// grise `flex items-center gap-xs bg-surface-zebra rounded-lg px-sm py-1` ([PeriodeDatesZebra]).
class ChampDateSansBordure extends StatelessWidget {
  const ChampDateSansBordure({super.key, required this.cle, required this.valeur, required this.onTap});

  final Key cle;
  final DateTime valeur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: cle,
    onTap: onTap,
    borderRadius: BorderRadius.circular(AgriRadius.lg),
    child: Padding(
      padding: const EdgeInsets.all(AgriChamps.margeSansBordure),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(StylesChampsAgri.jour(valeur), style: StylesChampsAgri.valeurFiche),
          const SizedBox(width: AgriSpacing.lg),
          const _IndicateurCalendrier(),
        ],
      ),
    ),
  );
}

/// Zone grise de la période du Grand Livre : [debut], « au », [fin].
class PeriodeDatesZebra extends StatelessWidget {
  const PeriodeDatesZebra({super.key, required this.debut, required this.fin});

  final Widget debut;
  final Widget fin;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AgriSpacing.sm,
      vertical: AgriChamps.margeVerticaleConteneur,
    ),
    decoration: BoxDecoration(
      color: AgriColors.surfaceZebra,
      borderRadius: BorderRadius.circular(AgriRadius.lg),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        debut,
        const SizedBox(width: AgriSpacing.xs),
        const Text('au', style: StylesChampsAgri.motPeriode),
        const SizedBox(width: AgriSpacing.xs),
        fin,
      ],
    ),
  );
}

/// Champ Date d'un formulaire : libellé AU-DESSUS (`block text-[10px] text-brand-forest font-bold uppercase mb-xs`),
/// puis `w-full h-11 px-md border border-outline-variant rounded-lg text-sm`, puis l'erreur (`.invalid-feedback`).
///
/// [caisse] : le gabarit de « Date de la vente » (`h-10 … text-xs bg-white`). [desactive] : `bg-surface-zebra
/// text-outline`, aucun geste. [erreur] : bord `#BA1A1A` et fond `#FFF5F5` (`is-invalid`) et message dessous.
/// [valeur] absente : le format attendu, `jj/mm/aaaa`.
class ChampDateFormulaire extends StatelessWidget {
  const ChampDateFormulaire({
    super.key,
    required this.cle,
    required this.etiquette,
    required this.valeur,
    required this.onTap,
    this.desactive = false,
    this.caisse = false,
    this.erreur,
    this.cleErreur,
    this.infobulle,
    this.aide,
    this.cleAide,
    this.surEffacer,
    this.cleEffacer,
  });

  /// Clé du champ lui-même (la zone qui reçoit le geste).
  final Key cle;

  /// Sans étoile ajoutée ni majuscules : le libellé du Blade, tel quel (« Date du Soin * »).
  final String etiquette;
  final DateTime? valeur;
  final VoidCallback? onTap;
  final bool desactive;
  final bool caisse;
  final String? erreur;
  final Key? cleErreur;

  /// Info-bulle du champ (motif d'un champ verrouillé).
  final String? infobulle;

  /// Texte d'aide sous le champ (`text-[10px] text-outline mt-xs` de la caisse).
  final String? aide;
  final Key? cleAide;

  /// Ajout du poste (le navigateur efface une date au clavier) : « ✕ » dans le champ, à droite du calendrier.
  final VoidCallback? surEffacer;
  final Key? cleEffacer;

  @override
  Widget build(BuildContext context) {
    final enErreur = erreur != null;
    final style = caisse ? StylesChampsAgri.valeurCaisse : StylesChampsAgri.valeurFormulaire;
    final texte = valeur == null ? 'jj/mm/aaaa' : StylesChampsAgri.jour(valeur!);
    Widget champ = _CadreChamp(
      cle: cle,
      hauteur: caisse ? AgriChamps.hauteurCaisse : AgriChamps.hauteurFormulaire,
      fond: desactive
          ? AgriColors.surfaceZebra
          : enErreur
          ? kFondChampInvalide
          : AgriColors.surfaceCard,
      margeHorizontale: AgriSpacing.md,
      couleurTrait: enErreur ? AgriColors.errorDeep : AgriColors.outlineVariant,
      onTap: desactive ? null : onTap,
      pleineLargeur: true,
      enfant: Row(
        children: [
          Expanded(
            child: Text(
              texte,
              overflow: TextOverflow.ellipsis,
              style: valeur == null || desactive ? style.copyWith(color: AgriColors.outline) : style,
            ),
          ),
          const SizedBox(width: AgriSpacing.sm),
          const _IndicateurCalendrier(),
          if (surEffacer != null) ...[
            const SizedBox(width: AgriSpacing.xs),
            InkWell(
              key: cleEffacer,
              onTap: surEffacer,
              child: const Tooltip(
                message: 'Effacer',
                child: Icon(SymbolesAgri.close, size: AgriChamps.iconeCalendrier, color: AgriColors.outline),
              ),
            ),
          ],
        ],
      ),
    );
    if (infobulle != null) champ = Tooltip(message: infobulle!, child: champ);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AgriSpacing.xs),
          child: Text(etiquette.toUpperCase(), style: StylesChampsAgri.etiquetteFormulaire),
        ),
        champ,
        if (erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: AgriChamps.erreurMarge),
            child: Text(erreur!, key: cleErreur, style: StylesChampsAgri.erreur),
          ),
        if (aide != null && erreur == null)
          Padding(
            padding: const EdgeInsets.only(top: AgriSpacing.xs),
            child: Text(
              aide!,
              key: cleAide,
              style: const TextStyle(
                fontSize: AgriChamps.etiquetteFormulaire,
                color: AgriColors.outline,
                height: AgriTypography.interligneCorps,
              ),
            ),
          ),
      ],
    );
  }
}
