import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Ticket DES-2 — LE DOSSIER DES DONNÉES DU POSTE : `%APPDATA%\OLOUWACHEGOUN\donnees`.
///
/// Point de passage UNIQUE : la base, `demarrage.log`, le logo, les sauvegardes et la restauration le lisent ici. Il se déduit du
/// dossier d'éditeur de `path_provider` (`CompanyName` de `Runner.rc` = OLOUWACHEGOUN) ; le sous-dossier `donnees` est choisi
/// par le client, plutôt que le nom du produit (`agrierp`).
class DossierDonnees {
  const DossierDonnees._();

  static const nomEditeur = 'OLOUWACHEGOUN';
  static const nom = 'donnees';

  /// Le dossier des données (créé par l'appelant au besoin).
  static Future<Directory> courant() async => Directory(p.join((await _racineEditeur()).path, nom));

  static Future<Directory> _racineEditeur() async => (await getApplicationSupportDirectory()).parent;
}

/// Reprend les données d'un poste en service quand le dossier change de nom — au LANCEMENT, avant d'ouvrir la base.
///
/// Deux anciens emplacements : `%APPDATA%\bj.olouwachegoun\agrierp` (avant DES-2) et `%APPDATA%\OLOUWACHEGOUN\agrierp`
/// (premier renommage). Le dossier est DÉPLACÉ (même disque : un renommage, instantané) ; à défaut, copié puis l'ancien retiré. Une
/// base déjà présente dans le dossier courant n'est JAMAIS écrasée ; une panne laisse l'ancien dossier intact et le poste démarre
/// sur un dossier neuf plutôt que de bloquer.
class MigrationDossierDonnees {
  const MigrationDossierDonnees._();

  static const ancienNomEditeur = 'bj.olouwachegoun';
  static const ancienNomProduit = 'agrierp';

  /// [appData] : `%APPDATA%` (par défaut, celui de `path_provider`). Rend `true` si une migration a eu lieu.
  static Future<bool> migrer({Directory? appData}) async {
    try {
      final racine = appData ?? (await getApplicationSupportDirectory()).parent.parent;
      final cible = Directory(p.join(racine.path, DossierDonnees.nomEditeur, DossierDonnees.nom));
      final sources = [
        Directory(p.join(racine.path, DossierDonnees.nomEditeur, ancienNomProduit)),
        Directory(p.join(racine.path, ancienNomEditeur, ancienNomProduit)),
      ];

      var migre = false;
      if (!await File(p.join(cible.path, 'agrierp.sqlite')).exists()) {
        for (final source in sources) {
          if (!await source.exists() || await source.list().isEmpty) continue;
          await cible.parent.create(recursive: true);
          if (await cible.exists()) await cible.delete(recursive: true);
          try {
            await source.rename(cible.path);
          } on FileSystemException {
            await _copier(source, cible);
            await source.delete(recursive: true);
          }
          migre = true;
          break;
        }
      }
      // Dossiers vides laissés par les anciens noms : ils disparaissent (un dossier qui ne l'est pas reste).
      for (final reste in [...sources, sources[0].parent, sources[1].parent]) {
        if (await reste.exists() && await reste.list().isEmpty && !p.equals(reste.path, cible.path) && !p.equals(reste.path, cible.parent.path)) {
          await reste.delete();
        }
      }
      return migre;
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
