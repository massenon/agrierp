import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../demarrage/dossier_donnees.dart';
import '../systeme/plateforme_poste.dart';

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

  /// Incrémenté à chaque écriture ou effacement : l'interface (barre latérale, connexion) se redessine avec le fichier courant.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// Limites du web (`DonneesEntreprise` : logo 2 048 Ko, favicon 500 Ko).
  static const tailleMax = {'logo': 2048 * 1024, 'favicon': 500 * 1024};

  /// Formats admis par genre (ticket CONF-1) : le LOGO en PNG, JPG ou WEBP ; le FAVICON en ICO ou PNG. Mêmes listes que
  /// `EntrepriseService::EXTENSIONS_NOM` du serveur.
  static const extensionsParGenre = {
    'logo': ['png', 'jpg', 'jpeg', 'webp'],
    'favicon': ['ico', 'png'],
  };

  /// Toutes les extensions proposées par le sélecteur de fichier.
  static const extensions = ['png', 'jpg', 'jpeg', 'webp', 'ico'];

  /// Messages de refus : RECOPIÉS MOT POUR MOT de `lang/fr/validation.php` (groupe `fichiers_entreprise`) ; la garde
  /// `fichiers_entreprise_test` les compare au fichier de langue du serveur.
  static const messages = {
    'logo': {
      'format': 'Le logo doit être une image PNG, JPG ou WEBP.',
      'taille': 'Le logo ne doit pas dépasser 2 Mo.',
    },
    'favicon': {
      'format': "L'icône du site doit être un fichier ICO ou PNG.",
      'taille': "L'icône du site ne doit pas dépasser 500 Ko.",
    },
  };

  /// Type d'une image d'après ses premiers octets (`IdentiteVisuelle::typeMime` du serveur) : `png`, `jpg`, `webp`, `ico`, ou `null`.
  static String? typeDuContenu(Uint8List o) {
    bool debut(List<int> m) => o.length >= m.length && [for (var i = 0; i < m.length; i++) o[i] == m[i]].every((x) => x);
    if (debut(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return 'png';
    if (debut(const [0xFF, 0xD8, 0xFF])) return 'jpg';
    if (o.length >= 12 && debut(const [0x52, 0x49, 0x46, 0x46]) && o[8] == 0x57 && o[9] == 0x45 && o[10] == 0x42 && o[11] == 0x50) return 'webp';
    if (o.length >= 6 && debut(const [0x00, 0x00, 0x01, 0x00])) {
      final nombre = o[4] | (o[5] << 8);
      // L'annuaire (6 octets d'en-tête + 16 par image) doit tenir dans le fichier.
      if (nombre >= 1 && o.length >= 6 + 16 * nombre) return 'ico';
    }
    return null;
  }

  /// PWA-2 — navigateur : pas de dossier de données ; le logo et l'icône tirés du serveur restent EN MÉMOIRE pour la session
  /// (retirés à chaque tirage, donc rechargés au démarrage suivant). Jamais écrits sur un disque.
  static final Map<String, ({Uint8List octets, String nom, String? source})> _memoireNavigateur = {};

  static Future<Directory> _dossierParDefaut() async => Directory(p.join((await DossierDonnees.courant()).path, 'entreprise'));

  /// Refus AVANT d'écrire, mêmes règles et mêmes mots que le serveur (`EntrepriseService::jugerFichier`) : le nom (extension),
  /// puis l'EN-TÊTE binaire du contenu (jamais le seul nom), puis la taille. `null` si le fichier convient.
  static String? valider(String genre, String nom, Uint8List octets) {
    final ext = p.extension(nom).replaceFirst('.', '').toLowerCase();
    final type = typeDuContenu(octets);
    final formatOk = extensionsParGenre[genre]!.contains(ext) &&
        type != null &&
        (genre == 'logo' ? const ['png', 'jpg', 'webp'] : const ['ico', 'png']).contains(type);
    if (!formatOk) return messages[genre]!['format'];
    if (octets.length > tailleMax[genre]!) return messages[genre]!['taille'];
    return null;
  }

  Future<File?> fichier(String genre) async {
    if (PlateformePoste.navigateur) return null;
    final d = await _dossier();
    if (!await d.exists()) return null;
    await for (final f in d.list()) {
      if (f is File && p.basenameWithoutExtension(f.path) == genre && p.extension(f.path) != '.source') return f;
    }
    return null;
  }

  Future<Uint8List?> lire(String genre) async =>
      PlateformePoste.navigateur ? _memoireNavigateur[genre]?.octets : (await fichier(genre))?.readAsBytes();

  /// Remplace le fichier du genre (l'ancien, d'une autre extension, est effacé) ; [sourceServeur] mémorise le chemin d'où il vient.
  Future<void> enregistrer(String genre, Uint8List octets, String nom, {String? sourceServeur}) async {
    if (PlateformePoste.navigateur) {
      _memoireNavigateur[genre] = (octets: octets, nom: nom, source: sourceServeur);
      version.value++;
      return;
    }
    final d = await _dossier();
    await d.create(recursive: true);
    await effacer(genre);
    final ext = p.extension(nom).replaceFirst('.', '').toLowerCase();
    await File(p.join(d.path, '$genre.$ext')).writeAsBytes(octets, flush: true);
    if (sourceServeur != null) await File(p.join(d.path, '$genre.source')).writeAsString(sourceServeur);
    version.value++;
  }

  Future<void> effacer(String genre) async {
    if (PlateformePoste.navigateur) {
      _memoireNavigateur.remove(genre);
      version.value++;
      return;
    }
    final d = await _dossier();
    if (!await d.exists()) return;
    await for (final f in d.list()) {
      if (f is File && p.basenameWithoutExtension(f.path) == genre) await f.delete();
    }
    version.value++;
  }

  Future<String?> sourceServeur(String genre) async {
    if (PlateformePoste.navigateur) return _memoireNavigateur[genre]?.source;
    final d = await _dossier();
    final f = File(p.join(d.path, '$genre.source'));
    return await f.exists() ? f.readAsString() : null;
  }

  /// Le logo de l'entreprise pour les PDF : PNG ou JPEG seulement (le moteur PDF n'en lit pas d'autres), sinon `null`.
  Future<Uint8List?> logoPourPdf() async {
    if (PlateformePoste.navigateur) {
      final m = _memoireNavigateur['logo'];
      return m != null && const ['.png', '.jpg', '.jpeg'].contains(p.extension(m.nom).toLowerCase()) ? m.octets : null;
    }
    final f = await fichier('logo');
    if (f == null || !const ['.png', '.jpg', '.jpeg'].contains(p.extension(f.path).toLowerCase())) return null;
    return f.readAsBytes();
  }
}
