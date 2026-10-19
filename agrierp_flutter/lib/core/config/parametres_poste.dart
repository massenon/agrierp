import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// Réglages propres à ce poste : son identifiant et l'adresse du serveur.
///
/// 🔴 CE QUE CE SERVICE CORRIGE. Jusqu'ici, `deviceId` valait la constante
/// `'poste-dev'`, répétée en quatre endroits, et l'adresse du serveur pointait
/// sur `127.0.0.1`. Deux conséquences, toutes deux bloquantes pour une
/// installation réelle :
///
/// ⚠️ **TOUS LES POSTES AURAIENT PARTAGÉ LE MÊME IDENTIFIANT.** Le contrat de
/// synchronisation promet de répondre à « qui a écrit quoi, et où ? » —
/// `device_id` est là pour ça. Avec la même valeur partout, deux postes de la
/// ferme deviennent indiscernables : un conflit ne peut plus être expliqué, et
/// la règle de dernière-écriture-gagnante devient un arbitrage aveugle.
///
/// ⚠️ **L'ADRESSE CODÉE EN DUR** aurait envoyé les données de la ferme vers le
/// poste du développeur — ou, plus probablement, nulle part.
class ParametresPoste {
  ParametresPoste({required AppDatabase database, Uuid? uuid})
    : _db = database,
      _uuid = uuid ?? const Uuid();

  static const cleIdentifiant = 'poste.identifiant';
  static const cleAdresseServeur = 'poste.adresse_serveur';

  /// Ticket H13 (B2) — intervalle de la synchronisation automatique, en minutes.
  static const cleIntervalleSynchronisation =
      'poste.intervalle_synchronisation_minutes';

  /// Choix proposés à l'écran ; 5 min par défaut depuis S-T3 (note TATACORA ; 15 min jusqu'ici, D-SYNC-3).
  /// ⚠️ Un intervalle déjà choisi par l'administrateur (15, 30, 60) est conservé : seul le défaut change.
  static const intervallesProposes = [5, 15, 30, 60];
  static const intervalleParDefaut = 5;

  /// Valeur de départ : le serveur de production de la ferme.
  ///
  /// 🔁 Décision client du 17/10/2026 — « le serveur est hébergé à
  /// https://agrierp.fermeolouwachegoun.com ». Le poste installé chez
  /// l'exploitant synchronise avec ce serveur, sans réglage préalable ;
  /// l'administrateur peut toujours le changer dans Paramètres du poste.
  /// L'ancienne valeur (`http://127.0.0.1:8000`, « volontairement locale »)
  /// obligeait à configurer chaque poste avant sa première synchronisation.
  static const adresseParDefaut = 'https://agrierp.fermeolouwachegoun.com';

  final AppDatabase _db;
  final Uuid _uuid;

  /// Identifiant du poste — tiré UNE SEULE FOIS, puis conservé.
  ///
  /// ⚠️ **JAMAIS RÉGÉNÉRÉ.** Un identifiant qui changerait à chaque démarrage
  /// rendrait tout conflit inexplicable : on ne saurait plus quel poste a écrit
  /// quoi, et l'historique de synchronisation deviendrait illisible.
  Future<String> identifiant() async {
    final existant = await _lire(cleIdentifiant);
    if (existant != null && existant.isNotEmpty) return existant;

    // Préfixe lisible : le support doit pouvoir citer l'identifiant au
    // téléphone sans épeler un UUID entier.
    final nouveau = 'poste-${_uuid.v4().substring(0, 8)}';
    await _ecrire(cleIdentifiant, nouveau);

    return nouveau;
  }

  Future<String> adresseServeur() async =>
      await _lire(cleAdresseServeur) ?? adresseParDefaut;

  /// ⚠️ L'ADRESSE EST NORMALISÉE À L'ENREGISTREMENT. Une barre oblique finale
  /// produirait `//api/sync/pull` — un chemin que le serveur ne reconnaît pas,
  /// et une panne d'autant plus déroutante que l'adresse « a l'air bonne ».
  Future<void> definirAdresseServeur(String adresse) async {
    var propre = adresse.trim();

    while (propre.endsWith('/')) {
      propre = propre.substring(0, propre.length - 1);
    }

    if (propre.isEmpty) return;

    // Sans schéma, le client HTTP échouerait sur une erreur peu parlante.
    if (!propre.startsWith('http://') && !propre.startsWith('https://')) {
      propre = 'http://$propre';
    }

    await _ecrire(cleAdresseServeur, propre);
  }

  /// ⚠️ Une valeur absente, illisible ou hors des choix proposés retombe sur 5 min : un intervalle nul ou
  /// négatif lancerait une synchronisation en boucle.
  Future<Duration> intervalleSynchronisation() async {
    final minutes = int.tryParse(await _lire(cleIntervalleSynchronisation) ?? '');
    return Duration(
      minutes: intervallesProposes.contains(minutes)
          ? minutes!
          : intervalleParDefaut,
    );
  }

  Future<void> definirIntervalleSynchronisation(int minutes) async {
    if (!intervallesProposes.contains(minutes)) return;
    await _ecrire(cleIntervalleSynchronisation, '$minutes');
  }

  Future<String?> _lire(String cle) async {
    final ligne = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(cle))).getSingleOrNull();

    return ligne?.value;
  }

  Future<void> _ecrire(String cle, String valeur) {
    return _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: cle, value: valeur),
        );
  }
}
