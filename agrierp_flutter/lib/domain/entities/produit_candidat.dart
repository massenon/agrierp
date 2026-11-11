/// Produit pouvant être associé à une bande à sa création.
///
/// Type de domaine pur : ne dépend pas de Drift. Produit les informations
/// minimales dont l'écran Gestion des Bandes a besoin pour le sélecteur.
class ProduitCandidat {
  const ProduitCandidat({
    required this.id,
    required this.sku,
    required this.nom,
  });

  final String id;
  final String sku;
  final String nom;
}
