import 'dart:math' as math;
import 'dart:ui';

/// Ticket AIDE-1 — PLACEMENT DE LA VISITE GUIDÉE : où mettre le trou lumineux et où poser la carte.
///
/// Transposition fidèle de `agrierp_laravel/resources/js/aide-logique.js` (le maître) : mêmes marges, mêmes règles
/// d'ordre (dessous, dessus, droite, gauche, puis centrée en bas), et `test/aide_flottante_test.dart` rejoue les valeurs
/// calculées à la main de `tests/Js/aide-logique.test.mjs`. Logique pure : aucune dépendance aux widgets.
class PlacementVisite {
  const PlacementVisite._();

  /// Marge laissée autour de l'élément mis en valeur, et distance carte ↔ élément.
  static const double margeTrou = 6;
  static const double ecartCarte = 12;
  static const double bordEcran = 16;

  /// L'élément est-il réellement visible dans la fenêtre ? Un menu replié (absent de l'arbre, rectangle nul) ou hors champ
  /// n'a rien à mettre en valeur : l'étape s'affiche alors sans trou, sur le seul voile.
  static bool rectUtilisable(Rect? rect, Size fenetre) {
    if (rect == null) return false;
    if (rect.width < 1 || rect.height < 1) return false;
    return rect.right > 0 && rect.bottom > 0 && rect.left < fenetre.width && rect.top < fenetre.height;
  }

  /// Le trou lumineux : le rectangle élargi de la marge, rogné à la fenêtre.
  static Rect trouAutour(Rect rect, Size fenetre, {double marge = margeTrou}) {
    final gauche = math.max(0, rect.left - marge).toDouble();
    final haut = math.max(0, rect.top - marge).toDouble();
    final droite = math.min(fenetre.width, rect.right + marge);
    final bas = math.min(fenetre.height, rect.bottom + marge);
    return Rect.fromLTRB(gauche, haut, droite, bas);
  }

  /// Position de la carte (coin haut-gauche) : sous le trou, sinon au-dessus, sinon à droite, sinon à gauche ; si rien ne
  /// tient, centrée en bas. Sans trou : centrée dans la fenêtre. Jamais hors de la fenêtre ([bordEcran]).
  static ({Offset position, String lieu}) placerCarte(Rect? trou, Size carte, Size fenetre) {
    final maxGauche = math.max(bordEcran, fenetre.width - carte.width - bordEcran);
    final maxHaut = math.max(bordEcran, fenetre.height - carte.height - bordEcran);
    double borner(double valeur, double max) => math.min(math.max(valeur, bordEcran), max);

    if (trou == null) {
      return (
        position: Offset(
          borner((fenetre.width - carte.width) / 2, maxGauche),
          borner((fenetre.height - carte.height) / 2, maxHaut),
        ),
        lieu: 'centre',
      );
    }

    final sousLeTrou = trou.bottom + ecartCarte;
    if (sousLeTrou + carte.height + bordEcran <= fenetre.height) {
      return (position: Offset(borner(trou.left, maxGauche), sousLeTrou), lieu: 'dessous');
    }

    final auDessus = trou.top - ecartCarte - carte.height;
    if (auDessus >= bordEcran) {
      return (position: Offset(borner(trou.left, maxGauche), auDessus), lieu: 'dessus');
    }

    final aDroite = trou.right + ecartCarte;
    if (aDroite + carte.width + bordEcran <= fenetre.width) {
      return (position: Offset(aDroite, borner(trou.top, maxHaut)), lieu: 'droite');
    }

    final aGauche = trou.left - ecartCarte - carte.width;
    if (aGauche >= bordEcran) {
      return (position: Offset(aGauche, borner(trou.top, maxHaut)), lieu: 'gauche');
    }

    return (position: Offset(borner((fenetre.width - carte.width) / 2, maxGauche), maxHaut), lieu: 'bas');
  }

  /// « Étape 1 sur 4 » : le gabarit du fichier de langue (`:numero`, `:total`) rempli.
  static String indicateur(String gabarit, int etape, int total) =>
      gabarit.replaceFirst(':numero', '${etape + 1}').replaceFirst(':total', '$total');
}
