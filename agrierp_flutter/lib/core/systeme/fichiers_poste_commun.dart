/// Ticket PWA-2 — pièces PURES (testables en VM) de la livraison d'un fichier au navigateur.
library;

/// Type MIME d'un fichier livré, selon son extension (le navigateur s'en sert pour le nom et l'ouverture).
String typeMimeDe(String nom) {
  final point = nom.lastIndexOf('.');
  final ext = point < 0 ? '' : nom.substring(point + 1).toLowerCase();
  return switch (ext) {
    'pdf' => 'application/pdf',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'csv' => 'text/csv;charset=utf-8',
    'json' => 'application/json',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => 'application/octet-stream',
  };
}

/// Nom de fichier sans séparateur de dossier ni caractère interdit : un téléchargement ne doit jamais porter un chemin.
String nomFichierSur(String nom) {
  final propre = nom.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_').trim();
  return propre.isEmpty ? 'document' : propre;
}

/// Phrase annoncée à l'écran à la place du chemin d'un fichier écrit sur le disque de Windows.
String messageTelechargement(String nom) =>
    "« ${nomFichierSur(nom)} » a été téléchargé par le navigateur (dossier Téléchargements).";
