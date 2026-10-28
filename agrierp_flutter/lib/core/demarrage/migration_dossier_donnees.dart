import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Ticket DES-2 — le dossier des données du poste passe de `%APPDATA%\\bj.olouwachegoun\\agrierp` à
/// `%APPDATA%\\OLOUWACHEGOUN\\agrierp` (CompanyName de `Runner.rc`).
///
/// ⚠️ Appelé AU LANCEMENT, avant d'ouvrir la base : un poste déjà en service retrouve ses données (base, journaux,
/// logo, sauvegardes) sans rien faire. Le dossier est DÉPLACÉ (même disque : un renommage, instantané) ; à défaut, copié puis
/// l'ancien est retiré. Une panne laisse l'ancien dossier intact et le poste démarre sur un dossier neuf plutôt que de bloquer.
class MigrationDossierDonnees {
  const MigrationDossierDonnees._();

  static const ancienNomEditeur = 'bj.olouwachegoun';

  /// Déplace l'ancien dossier vers [nouveau] (par défaut, le dossier de données courant). Rend `true` si une migration a eu lieu.
  static Future<bool> migrer({Directory? nouveau}) async {
    try {
      final cible = nouveau ?? await getApplicationSupportDirectory();
      final ancien = Directory(p.join(cible.parent.parent.path, ancienNomEditeur, p.basename(cible.path)));
      if (p.equals(ancien.path, cible.path) || !await ancien.exists()) return false;
      // Un dossier courant qui porte déjà une base n'est JAMAIS écrasé.
      if (await File(p.join(cible.path, 'agrierp.sqlite')).exists()) return false;

      await cible.parent.create(recursive: true);
      if (await cible.exists()) await cible.delete(recursive: true);
      try {
        await ancien.rename(cible.path);
      } on FileSystemException {
        await _copier(ancien, cible);
        await ancien.delete(recursive: true);
      }
      // L'éditeur n'a plus rien : son dossier vide disparaît (un dossier qui ne l'est pas reste).
      final editeur = ancien.parent;
      if (await editeur.exists() && await editeur.list().isEmpty) await editeur.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _copier(Directory source, Directory cible) async {
    await cible.create(recursive: true);
    await for (final e in source.list()) {
      final destination = p.join(cible.path, p.basename(e.path));
      if (e is Directory) {
        await _copier(e, Directory(destination));
      } else if (e is File) {
        await e.copy(destination);
      }
    }
  }
}
