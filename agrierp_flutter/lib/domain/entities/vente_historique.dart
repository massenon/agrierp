/// Entité de domaine pure pour une vente, vue par l'écran Historique des Ventes.
///
/// Ne dépend pas de Drift. Contient exactement les champs dont [LigneVente] et
/// [HistoriqueVentesOnglet] ont besoin : identifiant, horodatage, montants,
/// mode de paiement, statut métier et statuts techniques (device, MeCeF).
class VenteHistorique {
  const VenteHistorique({
    required this.id,
    required this.soldAt,
    required this.total,
    required this.subtotal,
    required this.discount,
    required this.paymentMode,
    required this.status,
    this.deviceId,
    this.mecefStatus,
  });

  /// UUID de la vente (clé primaire Drift).
  final String id;

  /// Instant effectif de la vente (heure du Bénin, UTC+1 fixe).
  final DateTime soldAt;

  /// Total TTC de la vente.
  final double total;

  /// Sous-total avant remise.
  final double subtotal;

  /// Remise accordée (`$sale->discount`).
  final double discount;

  /// Mode de paiement : `especes`, `mobile_money`, `virement`, `credit`, `avance`.
  final String paymentMode;

  /// Statut métier : `validee` ou `annulee`.
  final String status;

  /// Identifiant du poste qui a saisi la vente (`null` pour les ventes venues du serveur).
  final String? deviceId;

  /// Statut de normalisation fiscale MeCeF : `transmise`, `en_attente`, `erreur`, `expiree` ou `null`.
  final String? mecefStatus;
}
