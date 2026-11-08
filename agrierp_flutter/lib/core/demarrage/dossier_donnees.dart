import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../systeme/plateforme_poste.dart';

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
  ///
  /// ⚠️ PWA-2 : le navigateur n'a PAS de dossier de données (la base est dans IndexedDB). Tout appelant qui n'est pas sur le
  /// chemin natif doit d'abord tester [disponible] ; sinon [courant] lève une erreur française, jamais un échec obscur.
  static bool get disponible => !PlateformePoste.navigateur;

  static Future<Directory> courant() async {
    if (!disponible) {
      throw UnsupportedError("Le navigateur n'a pas de dossier de données : la base du poste est conservée par le navigateur.");
    }
    return _courantNatif();
  }

  static Future<Directory> _courantNatif() async => Directory(p.join((await _racineEditeur()).path, nom));

  static Future<Directory> _racineEditeur() async => (await getApplicationSupportDirectory()).parent;
}
