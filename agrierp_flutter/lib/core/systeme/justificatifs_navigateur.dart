import 'dart:typed_data';

import 'justificatifs_navigateur_native.dart'
    if (dart.library.js_interop) 'justificatifs_navigateur_web.dart';

/// PWA-2b — JUSTIFICATIFS AU NAVIGATEUR : le navigateur n'a ni chemin ni dossier. Les octets du justificatif (≤ 2 Mo, JPG,
/// PNG, PDF) sont rangés dans un MAGASIN LOCAL (IndexedDB, base `agrierp_justificatifs`) — SANS changer le schéma Drift : la
/// colonne `receipt_local_path` porte une RÉFÉRENCE `navigateur:<clé>/<nom du fichier>` au lieu d'un chemin Windows.
///
/// Le reste du parcours est celui du natif : `receipt_sent` faux → le moteur lit les octets ici et les envoie par
/// `POST /api/sync/receipts` (multipart `table`, `id`, `file`) ; l'écran « Saisie Dépenses » rouvre le fichier (ici : le
/// télécharge). Natif : ce magasin n'est JAMAIS utilisé (aucune référence `navigateur:` n'y est créée).
abstract class MagasinJustificatifs {
  Future<void> ecrire(String cle, Uint8List octets);

  /// `null` : clé inconnue (vidée par le navigateur, autre profil).
  Future<Uint8List?> lire(String cle);

  Future<void> supprimer(String cle);
}

/// Repli en mémoire : tests VM, et navigateur dont IndexedDB est inaccessible (navigation privée) — le justificatif tient alors
/// jusqu'à la fermeture de l'onglet.
class MagasinJustificatifsMemoire implements MagasinJustificatifs {
  final Map<String, Uint8List> _octets = {};

  @override
  Future<void> ecrire(String cle, Uint8List octets) async => _octets[cle] = Uint8List.fromList(octets);

  @override
  Future<Uint8List?> lire(String cle) async => _octets[cle];

  @override
  Future<void> supprimer(String cle) async => _octets.remove(cle);
}

class JustificatifsNavigateur {
  const JustificatifsNavigateur._();

  static const prefixe = 'navigateur:';

  /// Taille maximale d'un justificatif rangé dans le navigateur (le serveur accepte 5 Mo ; le navigateur garde 2 Mo : le quota
  /// d'IndexedDB est partagé avec toute la base du poste).
  static const tailleMaxOctets = 2 * 1024 * 1024;

  static const formats = ['jpg', 'jpeg', 'png', 'pdf'];

  /// Le magasin courant : IndexedDB dans le navigateur, mémoire sinon ; remplaçable en test.
  static MagasinJustificatifs magasin = creerMagasinJustificatifsPlateforme();

  static bool estReference(String chemin) => chemin.startsWith(prefixe);

  /// `navigateur:<clé>/<nom>` — le nom propre reste le DERNIER segment, comme pour un chemin (les écrans affichent le nom).
  static String reference(String cle, String nom) => '$prefixe$cle/${nom.replaceAll(RegExp(r'[\\/]'), '_')}';

  static ({String cle, String nom})? decoder(String reference) {
    if (!estReference(reference)) return null;
    final reste = reference.substring(prefixe.length);
    final i = reste.indexOf('/');
    if (i <= 0 || i == reste.length - 1) return null;
    return (cle: reste.substring(0, i), nom: reste.substring(i + 1));
  }

  /// Motif du refus d'un fichier trop gros (écran), ou `null` si la taille convient.
  static String? refus(int octets) => octets > tailleMaxOctets
      ? 'Le justificatif dépasse 2 Mo : réduisez-le (photo moins grande) avant de le joindre.'
      : null;
}
