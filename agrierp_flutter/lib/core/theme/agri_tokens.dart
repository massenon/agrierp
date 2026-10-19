import 'package:flutter/material.dart';

/// Tokens de design AgriERP — transposition FIDÈLE de
/// `prototype_html/assets/js/tailwind-config.js`, source unique de vérité
/// partagée par les 97 écrans du prototype.
///
/// ⚠️ LES 14 COULEURS SONT REPRISES UNE À UNE DU FICHIER RÉEL, jamais de
/// mémoire ni « à peu près ». Le CDC a dû résoudre une incohérence sur ce
/// point précis (14 couleurs annoncées contre 54 dans un transcript) : la
/// relecture du fichier a tranché à 14. Toute couleur ajoutée ici sans
/// exister là-bas est une divergence, pas une amélioration.
///
/// ⚠️ `brandMaize` N'EXISTE PAS. `sidebar.js` y fait référence
/// (`hover:text-brand-maize`) alors que la configuration ne la définit nulle
/// part : c'est un bug réel du prototype. L'accent est `accentYellow`
/// (#FFD55F), sans exception — la classe Tailwind fantôme ne produit aucun
/// style dans le navigateur, donc reproduire l'intention plutôt que le bug.
class AgriColors {
  const AgriColors._();

  static const brandForest = Color(0xFF052E16);
  static const brandForestDark = Color(0xFF00210D);
  static const brandEmerald = Color(0xFF065F46);
  static const accentYellow = Color(0xFFFFD55F);
  static const errorRed = Color(0xFFDC2626);
  static const errorDeep = Color(0xFFBA1A1A);
  static const errorBg = Color(0xFFFFDAD6);
  static const infoBlue = Color(0xFF2563EB);
  static const surfaceBg = Color(0xFFF8F9FA);
  static const surfaceCard = Color(0xFFFFFFFF);
  static const surfaceZebra = Color(0xFFF3F4F5);
  static const outlineVariant = Color(0xFFBEC9C2);
  static const outline = Color(0xFF6F7973);
  static const onSurface = Color(0xFF191C1D);
}

/// Échelle d'espacement du prototype, en pixels exacts.
///
/// ⚠️ Ce sont les mêmes noms que les classes Tailwind (`p-md`, `gap-sm`…) :
/// convertir un `px-md` du HTML donne `AgriSpacing.md` sans arbitrage, ce qui
/// rend la fidélité vérifiable plutôt qu'appréciée à l'œil.
class AgriSpacing {
  const AgriSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Rayons de bordure : `borderRadius: { lg: '0.5rem', xl: '0.75rem' }`.
/// La racine du prototype vaut 16 px, donc 8 px et 12 px.
class AgriRadius {
  const AgriRadius._();

  static const double lg = 8;
  static const double xl = 12;

  /// `rounded-full` des boutons d'action du prototype.
  static const double full = 999;
}

/// Point de rupture des tableaux responsives.
///
/// ⚠️ **640 px EXACTEMENT** — au-delà le tableau s'affiche en colonnes, en
/// deçà chaque ligne s'empile et chaque cellule doit porter son libellé (le
/// `data-label` du HTML). Une valeur approchée décalerait le basculement par
/// rapport au web sur les mêmes appareils.
const double kTableStackBreakpoint = 640;

/// Points de rupture Tailwind, **lus depuis `MediaQuery`**.
///
/// ⚠️⚠️ **JAMAIS DEPUIS `constraints.maxWidth`.** La largeur d'un
/// `LayoutBuilder` est celle du CONTENU, pas celle de l'écran : dans le socle
/// du poste, la zone de contenu est amputée de la barre latérale (256 px) et
/// des marges. Un écran de 1280 px présentait donc une contrainte de ~980 px
/// et basculait en mise en page « moyenne » alors que le navigateur, lui,
/// appliquait `lg:` au même moment. C'est le défaut de responsive n° 1, et il
/// est invisible : la page reste belle, simplement pas celle qui a été
/// validée.
///
/// Valeurs Tailwind par défaut, confirmées par `assets/css/common.css`, qui
/// n'emploie que 640 px (`table.rtable`), 768 px (`kpi-mobile-collapsed`) et
/// 1023/1024 px (barre latérale).
class AgriBreakpoints {
  const AgriBreakpoints._();

  static const double sm = 640;
  static const double md = 768;
  static const double lg = 1024;
  static const double xl = 1280;

  static double _largeur(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  /// `sm:` du prototype.
  static bool petit(BuildContext context) => _largeur(context) >= sm;

  /// `md:` — c'est le point où les grilles de KPI passent à quatre colonnes.
  static bool moyen(BuildContext context) => _largeur(context) >= md;

  /// `lg:` — c'est le point le plus employé du prototype (1300 occurrences).
  static bool large(BuildContext context) => _largeur(context) >= lg;

  static bool tresLarge(BuildContext context) => _largeur(context) >= xl;
}

/// Typographie du prototype — `Inter`, chargée depuis Google Fonts par chaque
/// page (`family=Inter:wght@400;500;600;700;800`).
///
/// ⚠️⚠️ **`text-xs` NE VAUT PAS 12 px DANS CE PROJET.**
/// `assets/css/common.css` l.48-49 le surcharge :
///
/// ```css
/// .text-xs { font-size: 0.85rem !important; }
/// ```
///
/// soit **13,6 px**, et non les 12 px de Tailwind. C'est la taille la plus
/// employée de tout le prototype — **3 569 occurrences** — donc l'écart le
/// plus visible qu'un portage puisse commettre. La surcharge ne touche que la
/// taille : l'interligne reste celui de l'utilitaire, 1 rem = 16 px.
///
/// Les autres tailles sont celles de Tailwind, la racine du prototype valant
/// 16 px. Les tailles arbitraires (`text-[10px]`, `text-[18px]`…) se portent
/// telles quelles.
class AgriTypography {
  const AgriTypography._();

  static const String famille = 'Inter';

  /// ⚠️ 13,6 px — surcharge de `common.css`, PAS les 12 px de Tailwind.
  static const double xs = 13.6;
  static const double xsInterligne = 16;

  static const double sm = 14;

  /// Libellé d'un lien de la barre latérale : `text-[13px]` EXPLICITE de `components/sidebar-link.blade.php`
  /// (ticket H1). Ce n'est pas un `text-xs` mal mesuré : le web l'écrit en pixels.
  static const double lienBarreLaterale = 13;
  static const double base = 16;
  static const double lg = 18;
  static const double xl = 20;
  static const double xxl = 24;

  /// Graisses réellement employées par le prototype.
  static const FontWeight normal = FontWeight.w400;
  static const FontWeight moyen = FontWeight.w500;
  static const FontWeight demiGras = FontWeight.w600;
  static const FontWeight gras = FontWeight.w700;
  static const FontWeight extraGras = FontWeight.w800;
}

/// Ombres portées Tailwind, valeurs exactes.
///
/// ⚠️ Le prototype n'en emploie que quatre : `shadow-sm` (515 occurrences),
/// `shadow-lg` (309), `shadow-xl` (141) et `shadow-md` (43).
class AgriShadows {
  const AgriShadows._();

  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 4),
      blurRadius: 6,
      spreadRadius: -1,
    ),
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 2),
      blurRadius: 4,
      spreadRadius: -2,
    ),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 10),
      blurRadius: 15,
      spreadRadius: -3,
    ),
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 4),
      blurRadius: 6,
      spreadRadius: -4,
    ),
  ];

  static const List<BoxShadow> xl = [
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 20),
      blurRadius: 25,
      spreadRadius: -5,
    ),
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 8),
      blurRadius: 10,
      spreadRadius: -6,
    ),
  ];
}
