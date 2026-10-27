import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../temps/heure_benin.dart';

/// Un PDF en octets : reçu du serveur (fiche sujet) ou fabriqué au poste (attestation, ATT-3 : l'émission est alors
/// déclarée au serveur, qui en attribue le numéro et garde la trace d'audit). Le poste l'écrit et l'imprime.
class PdfRecu {
  const PdfRecu({required this.octets, required this.fichier});

  final Uint8List octets;

  /// Nom proposé par le serveur (`attestation-agossou-jean.pdf`).
  final String fichier;

  /// Nom de fichier lu dans `Content-Disposition`, `repli` s'il n'y en a pas.
  static String nomDepuis(
    String? disposition, {
    String repli = 'document.pdf',
  }) {
    final m = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition ?? '');
    return m?.group(1) ?? repli;
  }
}

/// Ce que le poste fait d'un [PdfRecu] : l'écrire dans `Documents\AgriERP`, ou
/// ouvrir la boîte d'impression de Windows (qui sait aussi « Enregistrer au
/// format PDF »). Injectés dans les écrans : les tests n'ont ni disque ni
/// imprimante.
class LivraisonPdf {
  const LivraisonPdf._();

  /// Écrit le PDF et rend son chemin.
  ///
  /// ⚠️ **L'HORODATAGE VA JUSQU'AUX MINUTES** : deux éditions du même document le
  /// même jour (une correction) sont un cas normal, et la seconde ne doit pas
  /// écraser la première sans rien demander.
  static Future<String> enregistrer(PdfRecu pdf, {DateTime? maintenant}) async {
    final racine = await getApplicationDocumentsDirectory();
    final dossier = Directory(p.join(racine.path, 'AgriERP'));
    if (!dossier.existsSync()) dossier.createSync(recursive: true);

    final h = maintenant ?? HeureBenin.maintenant();
    String d(int n) => n.toString().padLeft(2, '0');
    final base = pdf.fichier.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    final chemin = p.join(
      dossier.path,
      '$base-${h.year}${d(h.month)}${d(h.day)}-${d(h.hour)}${d(h.minute)}.pdf',
    );

    File(chemin).writeAsBytesSync(pdf.octets);
    return chemin;
  }

  static Future<void> imprimer(PdfRecu pdf) =>
      Printing.layoutPdf(onLayout: (_) async => pdf.octets, name: pdf.fichier);
}
