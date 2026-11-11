/// Entité de domaine pure pour un client, vue par l'écran Historique des Ventes.
///
/// Ne dépend pas de Drift. Contient exactement les champs dont [InstantaneHistorique]
/// a besoin : identifiant, nom affiché et indicateur d'activité.
class ClientResume {
  const ClientResume({
    required this.id,
    required this.nom,
    required this.estActif,
  });

  /// UUID du client (clé primaire Drift).
  final String id;

  /// Nom complet du client (`Customer.name`).
  final String nom;

  /// `true` si le compte est actif (`Customer.isActive`).
  final bool estActif;
}
