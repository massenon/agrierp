import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'justificatifs_navigateur.dart';
import 'plateforme_poste.dart';

/// Ticket AC-3 — choix d'un justificatif (JPG, PNG, PDF) : le fichier est COPIÉ dans le dossier local de l'application, et
/// son chemin est rendu. `null` : l'utilisateur a annulé.
///
/// Partagé par la dépense et l'achat. La copie reste sur le poste ; le moteur de synchronisation l'ENVOIE ensuite au
/// serveur (`POST /api/sync/receipts`) quand l'enregistrement a été accepté — la colonne `receipt_sent` dit si c'est fait.
typedef ChoisirJustificatif = Future<String?> Function();

/// PWA-2b — navigateur : le sélecteur rend des OCTETS (jamais de chemin) ; ils sont rangés dans le magasin local du navigateur
/// ([JustificatifsNavigateur]) et la colonne `receipt_local_path` garde une référence `navigateur:<clé>/<nom>`. Même parcours
/// ensuite que le natif (envoi `POST /api/sync/receipts`, ouverture depuis l'écran). Refus : fichier de plus de 2 Mo.
///
/// Conservé pour compatibilité des écrans : plus aucun refus systématique au navigateur.
const motifJustificatifNavigateur = 'Le justificatif est rangé dans le navigateur (2 Mo au plus).';

/// Message du dernier refus du choix (navigateur : fichier trop gros) ; l'écran peut le lire après un `null`.
String? dernierRefusJustificatif;

Future<String?> choisirEtCopierJustificatif() async {
  dernierRefusJustificatif = null;
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: JustificatifsNavigateur.formats,
    dialogTitle: 'Joindre un justificatif',
    withData: PlateformePoste.navigateur,
  );
  if (result == null || result.files.isEmpty) return null;
  if (PlateformePoste.navigateur) return rangerJustificatifNavigateur(result.files.first.name, result.files.first.bytes);

  final source = File(result.files.first.path!);
  final dir = await getApplicationDocumentsDirectory();
  final nomFichier = '${DateTime.now().millisecondsSinceEpoch}_${result.files.first.name}';
  final destination = File('${dir.path}/agrierp_justificatifs/$nomFichier');
  await destination.parent.create(recursive: true);

  return (await source.copy(destination.path)).path;
}

/// Navigateur : range [octets] dans le magasin local et rend la référence à porter par l'enregistrement ; `null` si le
/// fichier est vide ou trop gros ([dernierRefusJustificatif] dit pourquoi). Public : le test VM joue ce chemin sans navigateur.
Future<String?> rangerJustificatifNavigateur(String nom, Uint8List? octets, {DateTime? maintenant}) async {
  dernierRefusJustificatif = null;
  if (octets == null || octets.isEmpty) {
    dernierRefusJustificatif = 'Le fichier choisi est vide ou illisible.';
    return null;
  }
  final refus = JustificatifsNavigateur.refus(octets.length);
  if (refus != null) {
    dernierRefusJustificatif = refus;
    return null;
  }
  final cle = 'j${(maintenant ?? DateTime.now()).microsecondsSinceEpoch}';
  await JustificatifsNavigateur.magasin.ecrire(cle, octets);
  return JustificatifsNavigateur.reference(cle, nom);
}
