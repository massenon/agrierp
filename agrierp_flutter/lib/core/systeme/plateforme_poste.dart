import 'package:flutter/foundation.dart';

import 'fichiers_poste.dart';

/// Ticket PWA-2 — « OÙ TOURNE LE POSTE ? » : Windows (référence) ou navigateur (PWA).
///
/// Point UNIQUE des gardes « pas de dossier, pas de processus, pas de socket » : les fichiers qui touchent au disque ou au
/// système lisent [navigateur] et prennent le chemin du navigateur (motif français, téléchargement). En VM de test,
/// [navigateur] vaut `false` (le natif, inchangé) ; un test du chemin web le force avec [forcerNavigateur] — c'est
/// l'« implémentation de repli » testable sans navigateur.
class PlateformePoste {
  const PlateformePoste._();

  static bool _navigateur = kIsWeb;

  /// `true` quand le poste est compilé pour le web.
  static bool get navigateur => _navigateur;

  /// Pour les tests uniquement : simule le navigateur (`true`), ou rend le natif (`null`).
  @visibleForTesting
  static void forcerNavigateur(bool? valeur) => _navigateur = valeur ?? kIsWeb;

  /// Livraison d'un fichier au navigateur (téléchargement) ; remplaçable en test.
  static Future<String> Function(String nom, List<int> octets) livreurNavigateur = livrerFichier;

  /// Motif affiché quand un geste exige le disque de la machine.
  static const motifSansDisque =
      "Ce geste utilise le disque de l'ordinateur : il n'est pas disponible dans le navigateur. Utilisez le poste Windows "
      'ou le web de gestion.';
}
