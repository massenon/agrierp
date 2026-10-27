import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Ticket AC-3 — choix d'un justificatif (JPG, PNG, PDF) : le fichier est COPIÉ dans le dossier local de l'application, et
/// son chemin est rendu. `null` : l'utilisateur a annulé.
///
/// Partagé par la dépense et l'achat. La copie reste sur le poste ; le moteur de synchronisation l'ENVOIE ensuite au
/// serveur (`POST /api/sync/receipts`) quand l'enregistrement a été accepté — la colonne `receipt_sent` dit si c'est fait.
typedef ChoisirJustificatif = Future<String?> Function();

Future<String?> choisirEtCopierJustificatif() async {
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
