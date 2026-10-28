import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../demarrage/dossier_donnees.dart';

/// Ticket AUT-2 — LOGO ET FAVICON DE L'ENTREPRISE, gardés sur le poste (hors base, hors réseau).
///
/// Le poste les enregistre tout de suite (il reste autonome) ; la demande de réglage les envoie au serveur à la prochaine
/// synchronisation. Un fichier posé au web descend, lui, quand son chemin change (`<genre>.source` retient le chemin du serveur).
class FichiersEntreprise {
  FichiersEntreprise({Future<Directory> Function()? dossier}) : _dossier = dossier ?? _dossierParDefaut;

  /// Instance du poste ; les tests la remplacent par un dossier temporaire.
  static FichiersEntreprise courant = FichiersEntreprise();

  final Future<Directory> Function() _dossier;

  static const genres = ['logo', 'favicon'];

  /// Limites du web (`DonneesEntreprise` : logo 2 048 Ko, favicon 500 Ko).
  static const tailleMax = {'logo': 2048 * 1024, 'favicon': 500 * 1024};

  /// Formats que l'image du poste sait afficher (`image` du web, moins le SVG).
  static const extensions = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'];

  static Future<Directory> _dossierParDefaut() async => Directory(p.join((await DossierDonnees.courant()).path, 'entreprise'));

  /// Refus AVANT d'écrire, mêmes mots que le serveur (`EntrepriseService::fichiersDepuisBase64`) ; `null` si le fichier convient.
  static String? valider(String genre, String nom, int octets) {
    final ext = p.extension(nom).replaceFirst('.', '').toLowerCase();
    if (!extensions.contains(ext)) return 'Le $genre doit être une image (png, jpg, gif, bmp ou webp).';
    if (octets > tailleMax[genre]!) return 'Le $genre ne doit pas dépasser ${tailleMax[genre]! ~/ 1024} Ko.';
    return null;
  }

  Future<File?> fichier(String genre) async {
    final d = await _dossier();
    if (!await d.exists()) return null;
    await for (final f in d.list()) {
      if (f is File && p.basenameWithoutExtension(f.path) == genre && p.extension(f.path) != '.source') return f;
    }
    return null;
  }

  Future<Uint8List?> lire(String genre) async => (await fichier(genre))?.readAsBytes();

  /// Remplace le fichier du genre (l'ancien, d'une autre extension, est effacé) ; [sourceServeur] mémorise le chemin d'où il vient.
  Future<void> enregistrer(String genre, Uint8List octets, String nom, {String? sourceServeur}) async {
    final d = await _dossier();
    await d.create(recursive: true);
    await effacer(genre);
    final ext = p.extension(nom).replaceFirst('.', '').toLowerCase();
    await File(p.join(d.path, '$genre.$ext')).writeAsBytes(octets, flush: true);
    if (sourceServeur != null) await File(p.join(d.path, '$genre.source')).writeAsString(sourceServeur);
  }

  Future<void> effacer(String genre) async {
    final d = await _dossier();
    if (!await d.exists()) return;
    await for (final f in d.list()) {
      if (f is File && p.basenameWithoutExtension(f.path) == genre) await f.delete();
    }
  }

  Future<String?> sourceServeur(String genre) async {
    final d = await _dossier();
    final f = File(p.join(d.path, '$genre.source'));
    return await f.exists() ? f.readAsString() : null;
  }

  /// Le logo de l'entreprise pour les PDF : PNG ou JPEG seulement (le moteur PDF n'en lit pas d'autres), sinon `null`.
  Future<Uint8List?> logoPourPdf() async {
    final f = await fichier('logo');
    if (f == null || !const ['.png', '.jpg', '.jpeg'].contains(p.extension(f.path).toLowerCase())) return null;
    return f.readAsBytes();
  }
}
