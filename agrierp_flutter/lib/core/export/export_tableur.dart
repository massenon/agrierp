import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'document_officiel.dart';

/// Édition tableur d'un [DocumentOfficiel].
///
/// ⚠️⚠️ **CE CLASSEUR EST UN AJOUT ASSUMÉ, PAS UN PORTAGE.** La maquette
/// **ne fait pas** l'export Excel : ses six boutons affichent tous un message
/// « fonctionnalité prévue pour une prochaine itération (nécessite une
/// librairie tableur côté client) ». Le rendre réel au poste dépasse donc la
/// maquette — c'est un **arbitrage du commanditaire**, au même titre que les
/// boutons de fenêtre de la barre supérieure, et il est écrit ici pour que
/// personne ne le prenne plus tard pour une dérive de portage.
///
/// ⚠️ **LE CLASSEUR N'EST PAS UNE COPIE DU PDF.** Un tableur sert à recalculer :
/// les bandes de section y deviennent des lignes de titre, et les cellules
/// gardent leur texte tel qu'il est affiché à l'écran — jamais un montant
/// reformaté ici, qui ne correspondrait plus à ce que l'utilisateur a lu.
class ExportTableur {
  const ExportTableur._();

  /// Construit le classeur. Fonction pure : aucun accès disque, donc
  /// vérifiable par un test ordinaire.
  static Uint8List construire(DocumentOfficiel doc) {
    final classeur = Excel.createExcel();

    // ⚠️ Le nom d'onglet d'un classeur est limité à 31 caractères et refuse
    // `: \ / ? * [ ]`. « Rapport Élevage — Synthèse Détaillée » dépasse les
    // deux : un nom rejeté produirait un fichier que Excel dit corrompu.
    final onglet = _nomOnglet(doc.titre);
    classeur.rename(classeur.getDefaultSheet()!, onglet);
    final feuille = classeur[onglet];

    feuille.appendRow([TextCellValue(doc.titre)]);
    if (doc.sousTitre.isNotEmpty) {
      feuille.appendRow([TextCellValue(doc.sousTitre)]);
    }
    feuille.appendRow([]);

    if (doc.entetes.isNotEmpty) {
      feuille.appendRow([for (final e in doc.entetes) TextCellValue(e)]);
    }

    for (final ligne in doc.lignes) {
      feuille.appendRow(switch (ligne) {
        BandeDocument(:final libelle) => [TextCellValue(libelle)],
        EnteteDocument(:final cellules) => [
          for (final c in cellules) TextCellValue(c),
        ],
        DonneesDocument(:final cellules) => [
          for (final c in cellules) TextCellValue(c),
        ],
        TotalDocument(:final cellules) => [
          for (final c in cellules) TextCellValue(c),
        ],
      });
    }

    if (doc.noteDePied != null) {
      feuille.appendRow([]);
      feuille.appendRow([TextCellValue(doc.noteDePied!)]);
    }

    final octets = classeur.encode();
    if (octets == null) {
      throw StateError('Le classeur n’a pas pu être encodé.');
    }
    return Uint8List.fromList(octets);
  }

  /// Écrit le classeur dans « Documents\AgriERP » et rend son chemin complet.
  ///
  /// ⚠️ **AUCUNE BOÎTE DE DIALOGUE ICI, ET C'EST DÉLIBÉRÉ.** Un sélecteur de
  /// fichier demanderait une dépendance de plus sur un poste qui doit rester
  /// installable hors ligne. Le dossier est fixe, et l'écran **annonce le
  /// chemin** : un fichier écrit sans le dire est un fichier introuvable.
  static Future<String> enregistrer(
    DocumentOfficiel doc, {
    required DateTime maintenant,
  }) async {
    final racine = await getApplicationDocumentsDirectory();
    final dossier = Directory(p.join(racine.path, 'AgriERP'));
    if (!dossier.existsSync()) dossier.createSync(recursive: true);

    final chemin = p.join(dossier.path, nomFichier(doc.titre, maintenant));
    File(chemin).writeAsBytesSync(construire(doc));
    return chemin;
  }

  /// Nom de fichier horodaté.
  ///
  /// ⚠️ **L'HORODATAGE VA JUSQU'AUX MINUTES.** Deux éditions du même rapport
  /// le même jour sont la situation NORMALE — on filtre, on réédite. Sans
  /// l'heure, la seconde écraserait la première sans rien demander.
  static String nomFichier(String titre, DateTime maintenant) {
    final base = titre
        .replaceAll(RegExp(r'[^A-Za-zÀ-ÿ0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    final h = maintenant;
    final horodatage =
        '${h.year}${_deuxChiffres(h.month)}${_deuxChiffres(h.day)}-${_deuxChiffres(h.hour)}${_deuxChiffres(h.minute)}';

    return '$base-$horodatage.xlsx';
  }

  /// Ticket U12b — classeur d'un export « Excel » du hub Rapports & Exports : les LIGNES DU CSV DU WEB
  /// (`exportReport('csv')` de chaque rapport), en-tête compris, sans titre ni sous-titre ajoutés — le contenu est
  /// celui du web, seul le format (`.xlsx`) est l'ajout validé par le client.
  static Uint8List construireTableau(ClasseurRapport classeur) {
    final excel = Excel.createExcel();
    final onglet = _nomOnglet(classeur.onglet);
    excel.rename(excel.getDefaultSheet()!, onglet);
    final feuille = excel[onglet];
    for (final ligne in classeur.lignes) {
      feuille.appendRow([for (final c in ligne) TextCellValue(c)]);
    }
    final octets = excel.encode();
    if (octets == null) {
      throw StateError('Le classeur n’a pas pu être encodé.');
    }
    return Uint8List.fromList(octets);
  }

  /// Écrit [classeur] dans « Documents\AgriERP » sous le NOM DU WEB ([nomClasseur]) et rend son chemin complet.
  ///
  /// ⚠️ Deux éditions du même rapport le même jour portent le même nom, comme deux téléchargements du web : le
  /// navigateur garde les deux (« nom (1).csv ») ; le poste fait de même (« nom (1).xlsx »), sans rien écraser.
  static Future<String> enregistrerTableau(
    ClasseurRapport classeur, {
    required DateTime maintenant,
  }) async {
    final racine = await getApplicationDocumentsDirectory();
    final dossier = Directory(p.join(racine.path, 'AgriERP'));
    if (!dossier.existsSync()) dossier.createSync(recursive: true);

    final chemin = cheminLibre(
      dossier.path,
      nomClasseur(classeur, maintenant),
      (c) => File(c).existsSync(),
    );
    File(chemin).writeAsBytesSync(construireTableau(classeur));
    return chemin;
  }

  /// Nom du classeur : celui du CSV du web (`recettes-depenses-AAAA-MM-JJ.csv`…), en `.xlsx` — `{jour}` remplacé par
  /// la date du poste (heure du Bénin).
  static String nomClasseur(ClasseurRapport classeur, DateTime maintenant) =>
      classeur.fichier.replaceAll(
        '{jour}',
        '${maintenant.year}-${_deuxChiffres(maintenant.month)}-${_deuxChiffres(maintenant.day)}',
      );

  /// [nom] dans [dossier], ou « base (n).ext » au premier n libre si [existe] le dit pris.
  static String cheminLibre(
    String dossier,
    String nom,
    bool Function(String chemin) existe,
  ) {
    final candidat = p.join(dossier, nom);
    if (!existe(candidat)) return candidat;
    final base = p.basenameWithoutExtension(nom);
    final extension = p.extension(nom);
    for (var n = 1; ; n++) {
      final autre = p.join(dossier, '$base ($n)$extension');
      if (!existe(autre)) return autre;
    }
  }

  static String _nomOnglet(String titre) {
    final propre = titre.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    return propre.length <= 31 ? propre : propre.substring(0, 31).trim();
  }

  static String _deuxChiffres(int v) => v.toString().padLeft(2, '0');
}

/// Ticket U12b — un export « Excel » du hub Rapports & Exports : le contenu du CSV du web, à écrire en `.xlsx`.
class ClasseurRapport {
  const ClasseurRapport({
    required this.fichier,
    required this.onglet,
    required this.lignes,
  });

  /// Nom du fichier, `{jour}` à remplacer par `AAAA-MM-JJ` : `recettes-depenses-{jour}.xlsx`…
  final String fichier;

  /// Nom de l'onglet du classeur (le titre du rapport, raccourci à 31 caractères).
  final String onglet;

  /// Lignes du CSV du web, en-tête compris.
  final List<List<String>> lignes;
}
