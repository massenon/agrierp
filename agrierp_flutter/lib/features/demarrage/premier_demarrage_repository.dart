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
/// Code de la ligne `modules_config` du module (le même qu'au serveur : `ModuleConfig::ASSISTANT_DEMARRAGE`).
const codeModuleAssistant = 'assistant_demarrage';

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

  /// Module « Assistant de démarrage » (Paramètres > Modules Actifs) : ÉTEINT par défaut, comme au web (absence de ligne = éteint).
  Future<bool> moduleActif() async {
    final ligne = await (_db.select(_db.modulesConfig)..where((m) => m.speciesCode.equals(codeModuleAssistant))).getSingleOrNull();
    return ligne?.isEnabled ?? false;
  }

  /// Un poste neuf ne montre l'assistant que si le module est allumé.
  ///
  /// Un poste neuf n'a encore tiré aucun réglage : il LIT le module au serveur, à la connexion (`GET /api/auth/me`,
  /// clé `assistant_demarrage_actif`). Hors ligne ou en erreur, il retombe sur sa copie locale (éteint par défaut).
  Future<bool> afficherAssistant() async {
    if (!await posteNeuf()) return false;
    try {
      final reponse = await _http.get<Map<String, dynamic>>('/api/auth/me');
      final cle = reponse.data?['assistant_demarrage_actif'];
      if (cle is bool) return cle;
    } on DioException {
      // Hors ligne : la copie locale décide.
    }
    return moduleActif();
  }

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
