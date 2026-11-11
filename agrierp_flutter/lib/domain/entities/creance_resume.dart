/// Entité de domaine pure pour une créance, vue par l'écran Historique des Ventes.
///
/// Ne dépend pas de Drift. Contient exactement les champs dont [InstantaneHistorique]
/// a besoin pour calculer le reste dû d'une vente à crédit :
/// [montantDu] − [montantPaye] = solde affiché dans [LigneVente.reste].
class CreanceResume {
  const CreanceResume({
    required this.id,
    required this.venteId,
    required this.montantDu,
    required this.montantPaye,
    required this.estEchue,
  });

  /// UUID de la créance (clé primaire Drift).
  final String id;

  /// UUID de la vente associée (`Receivable.saleId`).
  final String venteId;

  /// Montant total dû (`Receivable.amount`).
  final double montantDu;

  /// Montant déjà encaissé (`Receivable.amountPaid`).
  final double montantPaye;

  /// `true` si la créance n'est pas soldée (`Receivable.status != 'soldee'`).
  final bool estEchue;
}
