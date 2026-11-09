import 'passerelle_boitier.dart';

/// Navigateur : pas de boîtier. Chaque appel dit « non disponible » et ne touche aucun réseau.
PasserelleBoitier creerPasserelleBoitierPlateforme({Uri? adresse}) => const _PasserelleAbsente();

class _PasserelleAbsente implements PasserelleBoitier {
  const _PasserelleAbsente();

  static const _motif = 'Le boîtier se pilote depuis le poste Windows : il n\'est pas disponible dans le navigateur.';

  @override
  Future<EtatBoitier> verifier() async => const EtatBoitier(pret: false, message: _motif);

  @override
  Future<InfoBoitier?> informations() async => null;

  @override
  Future<ResultatFacturation> facturer(Map<String, Object?> charge) async => const BoitierInjoignable(_motif);
}
