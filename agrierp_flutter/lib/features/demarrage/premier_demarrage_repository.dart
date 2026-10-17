import 'package:dio/dio.dart';

import '../../core/config/parametres_poste.dart';
import '../../core/database/app_database.dart';

/// Ticket F0.98 — PREMIER DÉMARRAGE DU POSTE.
///
/// Un poste neuf ne disait rien de ce qu'il attendait : il fallait savoir qu'une synchronisation
/// manuelle devait précéder toute saisie (sans elle : aucune bande, aucun produit, aucun exercice), et
/// l'adresse du serveur ne se changeait que dans « Paramètres du poste », écran réservé à
/// l'administrateur… donc inaccessible avant une première connexion réussie.
///
/// ⚠️ **NEUF = jamais tiré ET rien en attente.** Seul un poste neuf peut changer d'adresse avant la
/// connexion : un poste en service qui changerait de serveur sans administrateur couperait la ferme
/// (règle de « Paramètres du poste ») — et n'aurait rien à perdre ici, puisqu'un poste neuf ne
/// contient aucune saisie.
class PremierDemarrageRepository {
  PremierDemarrageRepository({
    required AppDatabase database,
    required ParametresPoste parametres,
    required Dio client,
  }) : _db = database,
       _reglages = parametres,
       _http = client;

  final AppDatabase _db;
  final ParametresPoste _reglages;
  final Dio _http;

  Future<bool> posteNeuf() async =>
      (await _db.etatDeSynchronisation())?.lastPulledAt == null &&
      await _db.pendingCount() == 0;

  Future<String> adresse() => _reglages.adresseServeur();

  Future<String> identifiant() => _reglages.identifiant();

  /// Enregistre l'adresse ET l'applique au client partagé : sur un poste neuf, aucun envoi n'est parti
  /// avec l'ancienne, le redémarrage exigé par « Paramètres du poste » n'a pas lieu d'être.
  Future<String> changerAdresse(String adresse) async {
    if (!await posteNeuf()) {
      throw StateError(
        "Ce poste a déjà synchronisé : l'adresse du serveur se change dans Paramètres du poste "
        '(administrateur).',
      );
    }
    await _reglages.definirAdresseServeur(adresse);
    final enregistree = await _reglages.adresseServeur();
    _http.options.baseUrl = enregistree;
    return enregistree;
  }
}
