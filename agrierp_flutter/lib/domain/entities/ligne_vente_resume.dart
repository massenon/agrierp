/// Entité de domaine pure pour une ligne de vente, vue par l'écran Historique des Ventes.
///
/// Ne dépend pas de Drift. Contient exactement les champs dont [InstantaneHistorique]
/// a besoin : identifiant, rattachement à la vente, produit, quantité, prix unitaire
/// et montant total de la ligne.
class LigneVenteResume {
  const LigneVenteResume({
    required this.id,
    required this.venteId,
    required this.produitId,
    required this.quantite,
    required this.prixUnitaire,
    required this.manualTotalAmount,
  });

  /// UUID de la ligne (clé primaire Drift).
  final String id;

  /// UUID de la vente parente (`SaleLine.saleId`).
  final String venteId;

  /// UUID du produit vendu (`SaleLine.productId`).
  final String produitId;

  /// Quantité vendue (`SaleLine.qty`).
  final double quantite;

  /// Prix unitaire affiché (`SaleLine.unitPrice`).
  final double prixUnitaire;

  /// Montant total de la ligne, source de vérité (`SaleLine.manualTotalAmount`).
  final double manualTotalAmount;
}
