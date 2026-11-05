import '../../core/database/app_database.dart';
import '../stocks/pmp_service.dart';
import 'categorie_ration_lapin.dart';

/// Une ligne du rationnement par stade (fiche Pondeuses). [effectif] / [totalG] `null` = indisponibles (départ pas
/// encore valide).
class LigneRationPondeuses {
  const LigneRationPondeuses({
    required this.cle,
    required this.libelle,
    required this.ration,
    required this.effectif,
  });

  final String cle;
  final String libelle;
  final int ration;
  final int? effectif;

  int? get totalG => effectif == null ? null : effectif! * ration;
}

/// Tableau de rationnement par stade : QUATRE lignes (Poussin ponte, Poussin en croissance, Poulette, Pondeuse), total en
/// g et en kg — transposition de `StadePondeuse::tableau` (même arrondi).
class TableauRationPondeuses {
  const TableauRationPondeuses(this.lignes);

  final List<LigneRationPondeuses> lignes;

  int? get totalG => lignes.any((l) => l.totalG == null) ? null : lignes.fold<int>(0, (t, l) => t + l.totalG!);

  /// `round($total / 1000, 2)` du serveur (arrondi PHP : la moitié s'éloigne de zéro) ; null si le total est inconnu.
  double? get totalKg => totalG == null ? null : PmpService.arrondi(totalG! / 1000, 2);

  /// Pied du tableau : « N g (X Kg) », le kilo affiché tel quel par PHP (« 8.21 », « 5 »).
  String get totalAffiche => totalG == null ? '—' : '$totalG g (${PmpService.flottant(totalKg!)} Kg)';
}

/// Ticket VOL-2 (décision client du 05/11/2026) — LES QUATRE STADES DES VOLAILLES PONDEUSES : transposition de
/// `App\Support\StadePondeuse` (même règle, mêmes libellés, mêmes clés).
///
/// Libellés = ceux, EXACTS, des quatre lignes du barème de l'aviculture (`FeedRationStandardsSeeder`), jamais renommés ;
/// ils s'affichent tels quels partout (morts, dons, ventes, départ, passages, rationnement), comme au web.
///
/// EMPLACEMENTS GÉNÉRIQUES (colonnes de synchronisation) : Pondeuse → `repro` ; Poulette → `jeune` ; Poussin en croissance →
/// `sevre` ; Poussin ponte → `quatre` (colonnes `*_4`). Passages : Poussin ponte → Poussin en croissance `passage_4_sevre`,
/// Poussin en croissance → Poulette `passage_sevre_jeune`, Poulette → Pondeuse `passage_jeune_repro`. Les ACHATS vont à
/// Poulette, les ÉCLOSIONS à Poussin ponte, les VENTES au stade du PRODUIT vendu (`products.categorie_effectif`).
///
/// La ration se retrouve par CLÉ STABLE : libellé du barème normalisé (casse, accents ET tranche d'âge entre parenthèses
/// ignorés), en ÉGALITÉ STRICTE — jamais par sous-chaîne.
abstract final class StadePondeuse {
  static const poussinPonte = 'poussin_ponte';
  static const poussinCroissance = 'poussin_croissance';
  static const poulette = 'poulette';
  static const pondeuse = 'pondeuse';

  /// Ordre de la chaîne ET de l'affichage.
  static const cles = [poussinPonte, poussinCroissance, poulette, pondeuse];

  static const libelles = {
    poussinPonte: 'Poussin ponte (0 à 2 mois)',
    poussinCroissance: 'Poussin en croissance (2 à 4 mois)',
    poulette: 'Poulette (4 à 5.5 mois)',
    pondeuse: 'Pondeuse (6 à 18 mois)',
  };

  static const emplacements = {
    pondeuse: 'repro',
    poulette: 'jeune',
    poussinCroissance: 'sevre',
    poussinPonte: 'quatre',
  };

  /// Valeurs du barème d'origine (g/j), valeurs de secours si une ligne manque.
  static const rationsParDefaut = {poussinPonte: 30, poussinCroissance: 60, poulette: 80, pondeuse: 110};

  static bool estValide(String? cle) => cle != null && cles.contains(cle);

  static String libelle(String cle) => libelles[cle]!;

  /// Emplacement générique d'un stade, null si la clé est inconnue.
  static String? emplacement(String? cle) => emplacements[cle];

  /// Libellé du stade d'un emplacement générique (`libelleDeLEmplacement`).
  static String libelleDeLEmplacement(String emplacement) =>
      libelles[emplacements.entries.firstWhere((e) => e.value == emplacement).key]!;

  /// Clé de comparaison : minuscules, sans accent, SANS la tranche d'âge entre parenthèses, espaces réduits.
  static String _normaliser(String? texte) {
    final sansAge = (texte ?? '').replaceAll(RegExp(r'\([^)]*\)'), ' ');
    return CategorieRationLapin.normaliser(sansAge).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Clé d'une ligne du barème par ÉGALITÉ STRICTE du libellé normalisé, ou null.
  static String? cleDuLibelle(String? libelle) {
    final l = _normaliser(libelle);
    for (final c in cles) {
      if (l == _normaliser(libelles[c])) return c;
    }
    return null;
  }

  /// Ration (g/j) : celle du barème si la ligne existe, sinon la valeur d'origine (`(int)` du serveur).
  static int ration(List<FeedRationStandard> rations, String cle) {
    for (final r in rations) {
      if (cleDuLibelle(r.stageLabel) == cle) return r.rationGPerDay.truncate();
    }
    return rationsParDefaut[cle]!;
  }

  /// `tableau` : effectif calculé de chaque stade × la ration de sa ligne. [effectifs] par emplacement (`repro`, `sevre`,
  /// `jeune`, `quatre`), `null` = indisponible.
  static TableauRationPondeuses tableau(List<FeedRationStandard> rations, Map<String, int?> effectifs) =>
      TableauRationPondeuses([
        for (final c in cles)
          LigneRationPondeuses(cle: c, libelle: libelles[c]!, ration: ration(rations, c), effectif: effectifs[emplacements[c]]),
      ]);

  /// Stade PAR DÉFAUT d'un produit de l'aviculture d'après son nom (migration et semis du serveur) ; null = pas de règle sûre.
  static String? devinerDepuisLeNom(String? nom) {
    final n = CategorieRationLapin.normaliser(nom);
    if (n.isEmpty || RegExp(r'aliment|provende|oeuf|sac\b|plateau|medicament|vaccin').hasMatch(n)) return null;
    if (n.contains('poulette')) return poulette;
    if (n.contains('pondeuse') || n.contains('reforme')) return pondeuse;
    if (n.contains('poussin') && n.contains('croissance')) return poussinCroissance;
    if (n.contains('poussin') && n.contains('ponte')) return poussinPonte;
    return null;
  }
}
