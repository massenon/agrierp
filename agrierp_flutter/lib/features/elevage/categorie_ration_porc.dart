import '../../core/database/app_database.dart';
import 'categorie_ration_lapin.dart';

/// Ticket F0.99 — CLÉ STABLE des catégories de rationnement des PORCS : transposition de
/// `App\Support\CategorieRationPorc` (ticket 15.42).
///
/// 🔴 Avant : le poste rattachait le barème au STADE DE LA BANDE par sous-chaîne
/// (`stade.contains('porcelet')`, `libelle.contains('jeune')`) et donnait TOUT l'effectif final à une
/// seule ligne. Une bande en `croissance` (Porcelet au serveur) nourrissait la ligne « Jeune porc »,
/// « Engraissement » n'était pas reconnu, « Jeunes » l'était : deux provendes différentes pour la
/// même bande, aucun message.
///
///   reproducteur → « Reproducteur »   (2 000 g/j)   barème : « Porc reproducteur »
///   porcelet     → « Porcelet »       (300 g/j)     barème : « Porcelet »
///   marchand     → « Porc Marchand »  (600 g/j)     barème : « Jeune porc » (D15, NON renommé)
///
/// ⚠️ Ordre de test du serveur : « reproducteur » avant « porcelet » avant « marchand ».
abstract final class CategorieRationPorc {
  static const reproducteur = 'reproducteur';
  static const porcelet = 'porcelet';
  static const marchand = 'marchand';

  /// Ordre d'affichage du web (`fiche-porcs.blade.php`, tableau du rationnement).
  static const ordre = [porcelet, marchand, reproducteur];

  /// Libellés affichés (`LIBELLES` du serveur, maquette `fiche-porcs.html`).
  static const libelles = {
    reproducteur: 'Reproducteur',
    porcelet: 'Porcelet',
    marchand: 'Porc Marchand',
  };

  /// Valeurs de secours (g/j) — UNIQUEMENT si le barème ne porte pas la catégorie.
  static const rationsDeSecours = <String, double>{
    reproducteur: 2000,
    porcelet: 300,
    marchand: 600,
  };

  static final _jeuneSeul = RegExp(r'^jeune( porc)?$');

  /// Clé d'un libellé de barème (casse et accents indifférents), ou `null`.
  static String? cle(String? libelle) {
    final l = CategorieRationLapin.normaliser(libelle);

    if (l.isEmpty) return null;
    if (l.contains('reproducteur')) return reproducteur;
    if (l.contains('porcelet')) return porcelet;
    if (l.contains('marchand') ||
        l.contains('engraissement') ||
        _jeuneSeul.hasMatch(l)) {
      return marchand;
    }
    return null;
  }

  /// Ration (g/j) : la PREMIÈRE ligne du barème de la catégorie (`first` du serveur), sinon le secours.
  static double ration(List<FeedRationStandard> rations, String cleCategorie) {
    for (final r in rations) {
      if (cle(r.stageLabel) == cleCategorie) return r.rationGPerDay;
    }
    return rationsDeSecours[cleCategorie]!;
  }
}
