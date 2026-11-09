import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Écrit [octets] dans `Documents\AgriERP\[nom]` (créé au besoin) et rend le chemin complet : comportement du poste Windows,
/// INCHANGÉ (c'est celui que les écrans annoncent).
Future<String> livrerFichier(String nom, List<int> octets) async {
  final racine = await getApplicationDocumentsDirectory();
  final dossier = Directory(p.join(racine.path, 'AgriERP'));
  if (!dossier.existsSync()) dossier.createSync(recursive: true);
  final chemin = p.join(dossier.path, nom);
  File(chemin).writeAsBytesSync(octets);
  return chemin;
}

/// Octets du fichier choisi dans le sélecteur ; `null` si le sélecteur n'a rendu ni chemin ni octets.
Future<Uint8List?> octetsDuFichierChoisi(PlatformFile fichier) async {
  final chemin = fichier.path;
  if (chemin == null) return fichier.bytes;
  return File(chemin).readAsBytes();
}

/// Sélecteur : sur Windows les octets se lisent par le chemin (pas besoin de les charger d'avance).
const bool selecteurAvecOctets = false;

/// PWA-2c — natif : la restauration complète garde SON mécanisme (installée au prochain lancement) ; rien à recharger.
Future<void> rechargerPage() async {}
