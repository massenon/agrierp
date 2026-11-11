/// Bande pouvant être déclarée comme source d'une nouvelle bande.
///
/// Type de domaine pur : ne dépend pas de Drift. Fournit les informations
/// nécessaires au sélecteur « Bande d'Origine » de Gestion des Bandes.
class BandeOrigine {
  const BandeOrigine({
    required this.id,
    required this.code,
    required this.quantiteActuelle,
  });

  final String id;
  final String code;
  final double quantiteActuelle;
}
