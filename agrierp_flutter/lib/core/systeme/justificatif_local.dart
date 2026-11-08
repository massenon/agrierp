import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'plateforme_poste.dart';

/// Ticket AC-3 — choix d'un justificatif (JPG, PNG, PDF) : le fichier est COPIÉ dans le dossier local de l'application, et
/// son chemin est rendu. `null` : l'utilisateur a annulé.
///
/// Partagé par la dépense et l'achat. La copie reste sur le poste ; le moteur de synchronisation l'ENVOIE ensuite au
/// serveur (`POST /api/sync/receipts`) quand l'enregistrement a été accepté — la colonne `receipt_sent` dit si c'est fait.
typedef ChoisirJustificatif = Future<String?> Function();

/// PWA-2 — navigateur : un justificatif est un FICHIER du disque (copie locale + envoi `POST /api/sync/receipts` par son
/// chemin) ; le navigateur n'a ni chemin ni dossier. Refus assumé, avec ce motif, tant que le stockage en base n'est pas
/// décidé (voir `docs/PLAN_FINALISATION.md`, PWA-2).
const motifJustificatifNavigateur =
    "Joindre un justificatif n'est pas encore possible dans le navigateur : enregistrez la pièce avec le poste Windows ou le web de gestion.";

Future<String?> choisirEtCopierJustificatif() async {
  if (PlateformePoste.navigateur) return null;
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    dialogTitle: 'Joindre un justificatif',
  );
  if (result == null || result.files.isEmpty) return null;

  final source = File(result.files.first.path!);
  final dir = await getApplicationDocumentsDirectory();
  final nomFichier = '${DateTime.now().millisecondsSinceEpoch}_${result.files.first.name}';
  final destination = File('${dir.path}/agrierp_justificatifs/$nomFichier');
  await destination.parent.create(recursive: true);

  return (await source.copy(destination.path)).path;
}
