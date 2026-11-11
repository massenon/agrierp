/// Entité de domaine pure pour un article (produit), vue par l'écran Historique des Ventes.
///
/// Ne dépend pas de Drift. Contient exactement les champs dont [InstantaneHistorique]
/// a besoin : identifiant, nom affiché, prix unitaire et unité de mesure.
class ArticleResume {
  const ArticleResume({
    required this.id,
    required this.nom,
    required this.prixUnitaire,
    required this.unite,
  });

  /// UUID de l'article (clé primaire Drift).
  final String id;

  /// Nom complet de l'article (`Product.name`).
  final String nom;

  /// Prix unitaire de l'article (`Product.price`).
  final double prixUnitaire;

  /// Unité de mesure de l'article (`Product.unit`).
  final String unite;
}
