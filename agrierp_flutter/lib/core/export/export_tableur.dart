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

  static String _nomOnglet(String titre) {
    final propre = titre.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    return propre.length <= 31 ? propre : propre.substring(0, 31).trim();
  }

  static String _deuxChiffres(int v) => v.toString().padLeft(2, '0');
}
