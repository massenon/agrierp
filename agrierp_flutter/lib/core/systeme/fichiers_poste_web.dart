import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

import 'fichiers_poste_commun.dart';

/// Navigateur : déclenche le TÉLÉCHARGEMENT de [octets] sous [nom] et rend la phrase à annoncer (pas de chemin).
Future<String> livrerFichier(String nom, List<int> octets) async {
  final nomPropre = nomFichierSur(nom);
  final blob = web.Blob(
    [Uint8List.fromList(octets).toJS].toJS,
    web.BlobPropertyBag(type: typeMimeDe(nomPropre)),
  );
  final url = web.URL.createObjectURL(blob);
  final lien = web.HTMLAnchorElement()
    ..href = url
    ..download = nomPropre
    ..style.display = 'none';
  web.document.body!.append(lien);
  lien.click();
  lien.remove();
  web.URL.revokeObjectURL(url);
  return messageTelechargement(nomPropre);
}

/// Navigateur : le sélecteur rend des octets, jamais de chemin (`withData`).
Future<Uint8List?> octetsDuFichierChoisi(PlatformFile fichier) async => fichier.bytes;

const bool selecteurAvecOctets = true;
