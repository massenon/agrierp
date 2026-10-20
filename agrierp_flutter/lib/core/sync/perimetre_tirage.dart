import 'dart:convert';

import '../database/app_database.dart';

/// Ticket S-T4 (méthode TATACORA) — PÉRIMÈTRE DU TIRAGE : les tables que le serveur sert au compte connecté.
///
/// Le serveur ne sert à un compte que les tables dont il a l'usage (`SyncController::PERMISSIONS_DE_TIRAGE`, d'après
/// les permissions Spatie du compte), et les nomme à chaque page du tirage paginé (`tables_servies`). Le poste garde
/// celles de son DERNIER tirage réussi (l'intersection de toutes ses pages : un droit retiré pendant le tirage compte
/// comme retiré).
///
/// ⚠️⚠️ **RÈGLE DU CHANGEMENT DE RÔLE.** Le curseur du poste (`server_time`) est UNIQUE pour toutes les tables : une
/// table qui n'était pas servie au tirage précédent n'a jamais été tirée jusqu'à ce curseur. Si le serveur sert
/// désormais une table ABSENTE du périmètre gardé (rôle changé, droits élargis dans la matrice du web, autre
/// utilisateur sur le même poste), un tirage incrémental n'en apporterait que les changements récents : tout son
/// historique antérieur manquerait, sans erreur. Le poste repart alors d'un tirage COMPLET (sans `since`) — une
/// fois : le périmètre est réécrit à la fin de ce tirage. Un périmètre qui RÉTRÉCIT ne demande rien : la table qui
/// n'est plus servie n'est pas vidée (elle n'est simplement plus mise à jour, et les écrans du nouveau rôle ne
/// l'ouvrent pas) ; si elle revient plus tard, elle est de nouveau « ajoutée », donc resynchronisée en entier.
///
/// Cette règle ne dépend d'aucune date du serveur : la datation des rôles (S-T7) et l'absence de datation de
/// `model_has_roles` n'y jouent aucun rôle, le serveur disant lui-même ce qu'il sert.
///
/// Périmètre INCONNU (`null`) : aucun tirage paginé encore fait (poste d'avant S-T4, ou serveur ancien qui sert
/// tout, non filtré) — le poste a alors reçu TOUTES les tables, rien n'est à resynchroniser.
class PerimetreTirage {
  const PerimetreTirage._();

  /// Clé du réglage local (`app_settings`).
  static const cle = 'perimetre_tirage';

  static Future<Set<String>?> lire(AppDatabase db) async {
    final ligne = await (db.select(
      db.appSettings,
    )..where((t) => t.key.equals(cle))).getSingleOrNull();
    if (ligne == null) return null;
    try {
      final valeur = jsonDecode(ligne.value);
      if (valeur is List) return {for (final t in valeur) t.toString()};
    } on FormatException {
      // Réglage illisible : traité comme inconnu (tout a été reçu au dernier tirage complet).
    }
    return null;
  }

  static Future<void> ecrire(AppDatabase db, Set<String> tables) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: cle,
          value: jsonEncode(tables.toList()..sort()),
        ),
      );

  static Future<void> effacer(AppDatabase db) =>
      (db.delete(db.appSettings)..where((t) => t.key.equals(cle))).go();

  /// Vrai si [servies] contient une table que le périmètre [garde] ne servait pas : le tirage doit être complet.
  static bool elargi(Set<String>? garde, Set<String> servies) =>
      garde != null && !garde.containsAll(servies);

  /// `tables_servies` d'une page du tirage ; `null` si la clé manque (serveur antérieur à S-T4). Illisible →
  /// [FormatException] : le tirage est refusé plutôt que deviné.
  static Set<String>? depuisReponse(Map<String, dynamic> corps) {
    if (!corps.containsKey('tables_servies')) return null;
    final brut = corps['tables_servies'];
    if (brut is! List || brut.any((t) => t is! String)) {
      throw const FormatException(
        'Tirage refusé : « tables_servies » illisible.',
      );
    }
    return {for (final t in brut) t as String};
  }
}
