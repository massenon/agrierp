import '../../core/database/app_database.dart';
import 'categorie_ration_lapin.dart';
import 'categorie_volaille.dart';

/// Une ligne du rationnement avicole : `effectif` / `totalG` `null` = inconnus (« — »).
class LigneRationVolaille {
  const LigneRationVolaille({
    required this.libelle,
    required this.ration,
    required this.effectif,
    required this.totalG,
  });

  final String libelle;
  final double ration;
  final int? effectif;
  final double? totalG;
}

/// Ticket 15.57 — RATIONNEMENT DES FICHES AVICOLES (Pondeuses, Reproducteurs) : transposition de
/// `App\Support\RationVolaille`, la même règle des deux côtés.
///
///  - lignes = barème de l'aviculture, dans l'ordre de leur libellé (le dépôt les sert triées) ;
///  - l'effectif final du jour va à la PREMIÈRE ligne dont le libellé (normalisé comme au serveur)
///    contient la clé de la fiche, 0 aux autres ;
///  - 🔴 aucune ligne ne correspond : effectifs et total `null` (« — »), plus « 0 g » partout comme
///    l'affichait la fiche Reproducteurs (le barème du semis n'a pas de ligne « reproducteur »).
abstract final class RationVolaille {
  static const pondeuse = 'pondeuse';
  static const reproducteur = 'reproducteur';

  static List<LigneRationVolaille> lignes(
    List<FeedRationStandard> toutes,
    String cle,
    int effectif,
  ) {
    // Ticket VOL-1 : les trois lignes « Reproducteur / Jeune / Poussin » appartiennent à la fiche Reproducteurs
    // (`CategorieVolaille.tableauReproducteurs`) : elles ne figurent jamais au tableau de la fiche Pondeuses, dont le
    // comportement reste celui d'avant (`RationVolaille::tableau` du serveur).
    final rations = [
      for (final r in toutes)
        if (!CategorieVolaille.estUneLigneDeReproducteurs(r.stageLabel)) r,
    ];
    final rang = rations.indexWhere(
      (r) => CategorieRationLapin.normaliser(r.stageLabel).contains(cle),
    );
    return [
      for (var i = 0; i < rations.length; i++)
        () {
          final n = rang < 0 ? null : (i == rang ? effectif : 0);
          return LigneRationVolaille(
            libelle: rations[i].stageLabel,
            ration: rations[i].rationGPerDay,
            effectif: n,
            totalG: n == null ? null : n * rations[i].rationGPerDay,
          );
        }(),
    ];
  }

  static bool rattachee(List<LigneRationVolaille> lignes) =>
      lignes.any((l) => l.effectif != null);

  /// Total (g), `null` si aucune ligne ne correspond.
  static double? totalG(List<LigneRationVolaille> lignes) => rattachee(lignes)
      ? lignes.fold<double>(0, (a, l) => a + (l.totalG ?? 0))
      : null;

  /// `round($g / 1000, 2)` affiché par PHP : « 6.6 », « 9 ».
  static String kgCommePhp(double g) =>
      (g / 1000).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  /// Texte « {g} g ({kg} Kg) » du web, ou « — ».
  static String totalAffiche(double? g) =>
      g == null ? '—' : '${g.round()} g (${kgCommePhp(g)} Kg)';
}
