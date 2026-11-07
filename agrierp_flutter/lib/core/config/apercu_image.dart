import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'fichiers_entreprise.dart';

/// Ticket CONF-2 (décision D) — l'APERÇU d'une image du poste, y compris l'ICO que Flutter ne dessine pas.
///
/// Un PNG, un JPEG ou un WEBP se dessinent tels quels (les octets reviennent inchangés). Un ICO est DÉCODÉ avec le paquet
/// `image` (déjà dépendance de `pdf`, désormais déclaré) : on retient la plus grande de ses images et on la rend en PNG.
/// `null` si l'ICO est illisible : l'écran garde alors le nom du fichier et l'icône, comme avant CONF-2.
Uint8List? apercuAffichable(Uint8List octets) {
  if (FichiersEntreprise.typeDuContenu(octets) != 'ico') return octets;
  try {
    final ico = img.decodeIco(octets);
    if (ico == null) return null;
    var meilleure = ico.frames.first;
    for (final f in ico.frames) {
      if (f.width > meilleure.width) meilleure = f;
    }
    return Uint8List.fromList(img.encodePng(meilleure));
  } catch (_) {
    return null;
  }
}
