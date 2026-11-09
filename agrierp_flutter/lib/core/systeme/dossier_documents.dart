import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Nom du dossier du poste dans « Documents » (archives, exports PDF et Excel, reçus) depuis le renommage du produit
/// en LogiAgriERP.
const nomDossierDocuments = 'LogiAgriERP';

/// Ancien nom du même dossier (avant le renommage) : son contenu est REPRIS, jamais abandonné.
const ancienNomDossierDocuments = 'AgriERP';

/// `Documents\LogiAgriERP`, créé au besoin, après reprise de l'ancien dossier `Documents\AgriERP` s'il existe.
///
/// [racine] ne sert qu'aux tests (dossier « Documents » simulé).
Future<Directory> dossierDocumentsPoste({Directory? racine}) async {
  final documents = racine ?? await getApplicationDocumentsDirectory();
  reprendreAncienDossierDocuments(documents);
  final dossier = Directory(p.join(documents.path, nomDossierDocuments));
  if (!dossier.existsSync()) dossier.createSync(recursive: true);
  return dossier;
}

/// Reprise de l'ancien dossier, au mieux (une panne de disque ne doit jamais empêcher d'exporter) :
/// - ancien présent, nouveau absent : l'ancien est RENOMMÉ ;
/// - les deux présents : chaque élément de l'ancien est déplacé dans le nouveau SAUF s'il y porte déjà le même nom
///   (rien n'est jamais écrasé : l'élément en collision reste dans l'ancien dossier) ; l'ancien dossier est supprimé
///   seulement s'il est devenu vide.
void reprendreAncienDossierDocuments(Directory documents) {
  try {
    final ancien = Directory(p.join(documents.path, ancienNomDossierDocuments));
    if (!ancien.existsSync()) return;
    final nouveau = Directory(p.join(documents.path, nomDossierDocuments));
    if (!nouveau.existsSync()) {
      ancien.renameSync(nouveau.path);
      return;
    }
    for (final element in ancien.listSync(followLinks: false)) {
      final cible = p.join(nouveau.path, p.basename(element.path));
      if (FileSystemEntity.typeSync(cible, followLinks: false) != FileSystemEntityType.notFound) continue;
      element.renameSync(cible);
    }
    if (ancien.listSync(followLinks: false).isEmpty) ancien.deleteSync();
  } on FileSystemException {
    // Au mieux : l'export continue dans le nouveau dossier, l'ancien reste tel quel.
  }
}
