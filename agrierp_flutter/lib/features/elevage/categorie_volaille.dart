import '../../core/database/app_database.dart';
import '../stocks/pmp_service.dart';
import 'categorie_ration_lapin.dart';

/// Une ligne du rationnement par catégorie (fiche Volailles Reproducteurs). [effectif] / [totalG] `null` = indisponibles
/// (départ pas encore valide).
class LigneRationReproducteurs {
  const LigneRationReproducteurs({
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

/// Tableau de rationnement par catégorie : trois lignes (Reproducteur, Jeune, Poussin), total en g et en kg.
class TableauRationReproducteurs {
  const TableauRationReproducteurs(this.lignes);

  final List<LigneRationReproducteurs> lignes;

  int? get totalG => lignes.any((l) => l.totalG == null) ? null : lignes.fold<int>(0, (t, l) => t + l.totalG!);

  /// `round($total / 1000, 2)` du serveur (arrondi PHP : la moitié s'éloigne de zéro) ; null si le total est inconnu.
  double? get totalKg => totalG == null ? null : PmpService.arrondi(totalG! / 1000, 2);

  /// Pied du tableau : « N g (X Kg) », le kilo affiché tel quel par PHP (« 6.28 », « 6.5 », « 6 »).
  String get totalAffiche => totalG == null ? '—' : '$totalG g (${PmpService.flottant(totalKg!)} Kg)';
}

/// Ticket VOL-1 (décision client du 04/11/2026) — LES TROIS CATÉGORIES DES VOLAILLES REPRODUCTRICES : transposition de
/// `App\Support\CategorieVolaille` (même règle, mêmes libellés, mêmes clés).
///
/// ⚠️ Libellé affiché : « Jeune » — JAMAIS « Jeune à maturité », jamais « Poulet » (nom interne d'avant le ticket).
///
/// EMPLACEMENTS GÉNÉRIQUES (colonnes de synchronisation) : reproducteur → `repro` ; jeune → `jeune` ; poussin → `sevre`.
/// Les ACHATS vont aux Jeunes, les ÉCLOSIONS (poussins nés) aux Poussins, les VENTES à la catégorie du PRODUIT vendu
/// (`products.categorie_effectif`). La ration se retrouve par CLÉ STABLE : libellé du barème en ÉGALITÉ STRICTE
/// (« reproducteur », « jeune », « poussin »), jamais par sous-chaîne — « Poussin ponte (0 à 2 mois) » n'en est pas une.
/// ⚠️ Rations PROVISOIRES (130 / 80 / 30 g/j), à confirmer avec le client ; modifiables dans Paramètres Élevage.
abstract final class CategorieVolaille {
  static const reproducteur = 'reproducteur';
  static const jeune = 'jeune';
  static const poussin = 'poussin';

  /// Ordre d'affichage : Reproducteur, Jeune, Poussin.
  static const cles = [reproducteur, jeune, poussin];

  static const libelles = {reproducteur: 'Reproducteur', jeune: 'Jeune', poussin: 'Poussin'};

  static const emplacements = {reproducteur: 'repro', jeune: 'jeune', poussin: 'sevre'};

  /// ⚠️ VALEURS PROVISOIRES À CONFIRMER AVEC LE CLIENT (g/j par sujet).
  static const rationsProvisoires = {reproducteur: 130, jeune: 80, poussin: 30};

  static bool estValide(String? cle) => cle != null && cles.contains(cle);

  static String libelle(String cle) => libelles[cle]!;

  /// Emplacement générique d'une clé de catégorie, null si la clé est inconnue.
  static String? emplacement(String? cle) => emplacements[cle];

  /// Clé d'une ligne du barème par ÉGALITÉ STRICTE du libellé normalisé (casse et accents ignorés), ou null.
  static String? cleDuLibelle(String? libelle) {
    final l = CategorieRationLapin.normaliser(libelle);
    for (final c in cles) {
      if (l == CategorieRationLapin.normaliser(libelles[c])) return c;
    }
    return null;
  }

  static bool estUneLigneDeReproducteurs(String? libelle) => cleDuLibelle(libelle) != null;

  /// Ration (g/j) : celle du barème si la ligne existe, sinon la valeur provisoire (`(int)` du serveur).
  static int ration(List<FeedRationStandard> rations, String cle) {
    for (final r in rations) {
      if (cleDuLibelle(r.stageLabel) == cle) return r.rationGPerDay.truncate();
    }
    return rationsProvisoires[cle]!;
  }

  /// `tableauReproducteurs` : effectif calculé de chaque catégorie × la ration de sa ligne. [effectifs] par
  /// emplacement (`repro`, `sevre`, `jeune`), `null` = indisponible.
  static TableauRationReproducteurs tableauReproducteurs(
    List<FeedRationStandard> rations,
    Map<String, int?> effectifs,
  ) => TableauRationReproducteurs([
    for (final c in cles)
      LigneRationReproducteurs(
        cle: c,
        libelle: libelles[c]!,
        ration: ration(rations, c),
        effectif: effectifs[emplacements[c]],
      ),
  ]);

  /// Catégorie d'effectif PAR DÉFAUT d'un produit de l'aviculture d'après son nom (migration et semis du serveur) :
  /// poussin d'un jour → poussin ; coq / poule reproductrice → reproducteur ; poulet / jeune / maturité / goliath →
  /// jeune ; aliments, provendes et œufs jamais rangés. Null = pas de règle sûre.
  static String? devinerDepuisLeNom(String? nom) {
    final n = CategorieRationLapin.normaliser(nom);
    if (n.isEmpty || RegExp(r'aliment|provende|oeuf|sac\b|plateau|medicament|vaccin').hasMatch(n)) return null;
    if (n.contains('poussin')) return poussin;
    if (n.contains('reproducteur') || RegExp(r'\bcoqs?\b|\bpoules?\b').hasMatch(n)) return reproducteur;
    if (n.contains('poulet') || n.contains('jeune') || n.contains('maturite') || n.contains('goliath')) return jeune;
    return null;
  }
}
