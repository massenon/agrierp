// Ticket PWA-2 — E/S de fichiers du poste : natif (Documents\AgriERP, sélecteur à chemin) ou navigateur (téléchargement,
// octets du sélecteur). Les pièces pures sont dans fichiers_poste_commun.dart.
export 'fichiers_poste_commun.dart';
export 'fichiers_poste_native.dart' if (dart.library.js_interop) 'fichiers_poste_web.dart';
