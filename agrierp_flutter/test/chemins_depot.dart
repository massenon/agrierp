// Ticket A7 — UN SEUL RÉSOLVEUR DES CHEMINS DU DÉPÔT pour les tests du poste.
//
// Les tests lisaient `C:/laragon/www/agrierp/...` et `C:/Projects/agrierp_laravel/prototype_html/...` en dur :
// hors du poste du développeur (monorepo cloné ailleurs, intégration continue), `export_comptabilite_test` échouait
// et les parités avec le serveur se mettaient en saut. Ordre de recherche, le premier dossier existant gagne :
//  1. la variable d'environnement (`AGRIERP_LARAVEL`, `AGRIERP_PROTOTYPE`) ;
//  2. le monorepo (`../agrierp_laravel`, `../prototype_html`) — `flutter test` s'exécute dans `agrierp_flutter/` ;
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

/// Dossier `prototype_html/` de la maquette (absent du monorepo à ce jour : plan, A8).
final String dossierPrototype = _premierExistant('AGRIERP_PROTOTYPE', [
  '$_racineMonorepo/prototype_html',
  'C:/Projects/agrierp_laravel/prototype_html',
]);
