// Ticket A7 — UN SEUL RÉSOLVEUR DES CHEMINS DU DÉPÔT pour les tests du poste.
//
// Les tests lisaient `C:/laragon/www/agrierp/...` en dur : hors du poste du développeur (monorepo cloné ailleurs,
// intégration continue), `export_comptabilite_test` échouait et les parités avec le serveur se mettaient en saut.
// La maquette `prototype_html/` n'est plus une source depuis le 09/11/2026 (décision du client, ticket A8) : plus
// aucun test ne la lit, la vue Blade du web fait seule foi. Ordre de recherche, le premier dossier existant gagne :
//  1. la variable d'environnement (`AGRIERP_LARAVEL`) ;
//  2. le monorepo (`../agrierp_laravel`) — `flutter test` s'exécute dans `agrierp_flutter/` ;
//  3. l'ancien emplacement Windows du développeur.
// Aucun dossier trouvé : le chemin du monorepo est rendu, et les tests concernés se sautent AVEC leur raison.
import 'dart:io';

String _premierExistant(String variable, List<String> candidats) {
  final impose = Platform.environment[variable];
  if (impose != null && impose.isNotEmpty) return impose;
  for (final c in candidats) {
    if (Directory(c).existsSync()) return c;
  }
  return candidats.first;
}

String get _racineMonorepo => Directory.current.parent.path.replaceAll(r'\', '/');

/// Racine du dépôt Laravel (`agrierp_laravel/` du monorepo).
final String dossierLaravel = _premierExistant('AGRIERP_LARAVEL', [
  '$_racineMonorepo/agrierp_laravel',
  'C:/laragon/www/agrierp',
]);
