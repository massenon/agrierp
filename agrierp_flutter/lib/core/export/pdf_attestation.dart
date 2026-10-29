import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Un signataire tel qu'il s'imprime : position serveur (1 = Directeur Général, 2 = Examinateur, 3 = Président du Jury),
/// intitulé souligné (vide pour le Directeur), nom, fonction.
class LigneSignataire {
  const LigneSignataire({required this.position, this.titre = '', this.nom = '', this.fonction = ''});

  final int position;
  final String titre;
  final String nom;
  final String fonction;
}

/// Tout ce que le document imprime — calculé par `AttestationsRepository`, jamais par le constructeur.
class DonneesAttestation {
  const DonneesAttestation({
    required this.titre,
    required this.corps,
    required this.puces,
    required this.appreciation,
    required this.numero,
    required this.dateLieu,
    required this.signataires,
  });

  /// « Attestation de Formation » — imprimé en capitales.
  final String titre;

  /// Corps du modèle, balises remplacées, marques `**gras**` conservées.
  final String corps;

  /// Une ligne à puce (➢) par domaine coché, dans l'ordre du modèle.
  final List<String> puces;

  /// Phrase d'appréciation (marques `**gras**` conservées), `null` : rien à imprimer.
  final String? appreciation;

  /// « N°04/2026/FEO/DG », ou « N°—/2026/FEO/DG » tant que le serveur ne l'a pas attribué (JAMAIS inventé au poste).
  final String numero;

  /// « 24 octobre 2026 ».
  final String dateLieu;

  /// De gauche à droite : Examinateur, Président du Jury, Directeur Général (ceux que la durée appelle).
  final List<LigneSignataire> signataires;
}

/// Polices et images du modèle officiel, chargées une fois.
class RessourcesAttestation {
  const RessourcesAttestation({
    required this.corps,
    required this.corpsGras,
    required this.corpsItalique,
    required this.corpsGrasItalique,
    required this.note,
    required this.noteGras,
    required this.noteGrasItalique,
    required this.titre,
    required this.logo,
    required this.filigrane,
    required this.decor,
  });

  final pw.Font corps;
  final pw.Font corpsGras;
  final pw.Font corpsItalique;
  final pw.Font corpsGrasItalique;
  final pw.Font note;
  final pw.Font noteGras;
  final pw.Font noteGrasItalique;
  final pw.Font titre;
  final pw.MemoryImage logo;
  final pw.MemoryImage filigrane;
  final pw.MemoryImage decor;

  static Future<RessourcesAttestation> charger() async {
    Future<pw.Font> police(String nom) async => pw.Font.ttf(await rootBundle.load('assets/attestation/$nom'));
    Future<pw.MemoryImage> image(String chemin) async =>
        pw.MemoryImage((await rootBundle.load(chemin)).buffer.asUint8List());

    return RessourcesAttestation(
      corps: await police('Caladea-400.ttf'),
      corpsGras: await police('Caladea-700.ttf'),
      corpsItalique: await police('Caladea-400i.ttf'),
      corpsGrasItalique: await police('Caladea-700i.ttf'),
      note: await police('Carlito-400.ttf'),
      noteGras: await police('Carlito-700.ttf'),
      noteGrasItalique: await police('Carlito-700i.ttf'),
      titre: await police('Bevan-400.ttf'),
      logo: await image('assets/attestation/logo-ferme.png'),
      filigrane: await image('assets/attestation/filigrane.png'),
      decor: await image('assets/attestation/decor-floral.png'),
    );
  }
}

/// ATT-3 — LE POSTE PRODUIT LUI-MÊME L'ATTESTATION (hors ligne comprise) : transposition de
/// `resources/views/exports/attestation.blade.php` du serveur — mêmes mesures (points, relevées sur le modèle du client),
/// mêmes polices libres, même logo, même filigrane, même décor. ⚠️ Constructeur PUR : il imprime ce qu'on lui donne
/// (`DonneesAttestation`) ; le texte, la règle de signature et le numéro sont décidés ailleurs.
///
/// Le web reste le maître du visuel : toute mesure changée là-bas se change ici, et
/// `test/attestation_pdf_poste_test.dart` compare les positions des deux documents.
class ExportAttestation {
  const ExportAttestation._();

  static const _vert = PdfColor.fromInt(0xFF2E6B1A);
  static const _lien = PdfColor.fromInt(0xFF0563C1);
  static const _noir = PdfColors.black;

  // ── En-tête et pied : texte du modèle officiel (config/attestation.php du serveur) ──
  static const nom = 'FERME ÉCOLE OLOUWACHEGOUN';
  static const activites = [
    'Production Animale | Production Végétale | Transformation Agro-alimentaire| Fabrication de Cages',
    'Galvanisées | Formation Agricole | Suivi-Appuis et Conseils',
  ];
  static const adresse = "Attan-Ewé, Arrondissement d'Ikpinlè, Commune d'Adja-Ouèrè, Bénin";
  static const telephones = '+229 01 97 84 02 85 / 01 43 46 08 71';
  static const rccm = 'RB/PNO/22 A 33870';
  static const lieu = 'ATTAN - ÉWÉ';
  static const emails = ['olomagloire1@gmail.com', 'contact@fermeolouwachegoun.com'];
  static const site = 'www.fermeolouwachegoun.com';

  /// Taille (en points PDF, pas en pixels d'écran) de la ligne du lieu, de la date et du numéro — mesurée sur le modèle.
  static const _taillePied = 12.0;

  /// Les deux apostrophes droites du texte deviennent typographiques, comme au serveur (puces et fonctions).
  static String apostrophes(String t) => t.replaceAll("'", '’');

  /// Texte marqué → segments : `**gras**` en gras, et en gras VERT quand il porte le nom de la ferme.
  static List<pw.InlineSpan> segments(String marque, pw.TextStyle normal, pw.TextStyle gras) {
    final morceaux = marque.split('**');

    return [
      for (var i = 0; i < morceaux.length; i++)
        if (morceaux[i].isNotEmpty)
          pw.TextSpan(
            text: morceaux[i],
            style: i.isOdd
                ? (morceaux[i].toUpperCase().contains('OLOUWACHEGOUN') ? gras.copyWith(color: _vert) : gras)
                : normal,
          ),
    ];
  }

  static Future<Uint8List> construire(DonneesAttestation d, {RessourcesAttestation? ressources}) async {
    final r = ressources ?? await RessourcesAttestation.charger();
    final doc = pw.Document(title: d.titre, author: nom, creator: 'LogiAgriERP');

    // A4 paysage : 842 × 595 pt, aucune marge — tout est positionné au point près, comme au serveur.
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(842, 595),
        margin: pw.EdgeInsets.zero,
        build: (_) => _page(d, r),
      ),
    );

    return doc.save();
  }

  static pw.Widget _page(DonneesAttestation d, RessourcesAttestation r) {
    final long = d.corps.length + (d.appreciation ?? '').length + d.puces.fold<int>(0, (a, p) => a + p.length);
    final taille = long > 1000 ? 13.4 : 15.2;
    final pas = long > 1000 ? 15.9 : 17.7;

    // ⚠️ Une police par style, jamais `copyWith(font: …)` : le moteur choisit la variante d'après `fontWeight`, et la copie
    // gardait la police normale (tout le gras du document sortait en maigre).
    pw.TextStyle corps(double t, {pw.Font? police, PdfColor? couleur, double? hauteur}) =>
        pw.TextStyle(font: police ?? r.corps, fontSize: t, color: couleur ?? _noir, height: hauteur);

    final normal = corps(taille, hauteur: pas / taille);
    final gras = corps(taille, police: r.corpsGras, hauteur: pas / taille);

    pw.Widget place({required double haut, double? gauche, double? droite, double? largeur, required pw.Widget enfant}) =>
        pw.Positioned(
          left: gauche,
          right: droite,
          top: haut,
          child: largeur == null ? enfant : pw.SizedBox(width: largeur, child: enfant),
        );

    final ligneActivite = corps(13, police: r.corpsGras);
    final ligneIdentite = corps(13);

    return pw.Stack(
      children: [
        pw.Positioned(left: 0, top: 0, child: pw.Image(r.decor, width: 842, height: 595, fit: pw.BoxFit.fill)),
        pw.Positioned(left: 224, top: 128, child: pw.Image(r.filigrane, width: 395)),
        pw.Positioned(left: 6, top: -6, child: pw.Image(r.logo, width: 146)),

        // En-tête : nom de la ferme, activités, adresse, téléphone.
        place(
          gauche: 150, haut: 8, largeur: 596,
          enfant: pw.Text(
            nom,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: r.titre, fontSize: 20, color: _vert),
          ),
        ),
        for (final (i, ligne) in activites.indexed)
          place(
            gauche: 150, haut: 34.5 + i * 15.2, largeur: 660,
            enfant: pw.Text(ligne, textAlign: pw.TextAlign.center, style: ligneActivite),
          ),
        place(
          gauche: 150, haut: 64.9, largeur: 660,
          enfant: pw.RichText(
            textAlign: pw.TextAlign.center,
            text: pw.TextSpan(
              style: ligneIdentite,
              children: [
                pw.TextSpan(text: 'Adresse', style: ligneActivite),
                pw.TextSpan(text: ' : $adresse'),
              ],
            ),
          ),
        ),
        place(
          gauche: 150, haut: 80.1, largeur: 660,
          enfant: pw.RichText(
            textAlign: pw.TextAlign.center,
            text: pw.TextSpan(
              style: ligneIdentite,
              children: [
                pw.TextSpan(text: 'Téléphone', style: ligneActivite),
                pw.TextSpan(text: ' : $telephones, '),
                pw.TextSpan(text: 'RCCM', style: ligneActivite),
                pw.TextSpan(text: ' : $rccm'),
              ],
            ),
          ),
        ),

        // Lieu et date, numéro.
        place(
          droite: 27, haut: 111.4, largeur: 400,
          enfant: pw.Text(
            '$lieu, le ${d.dateLieu}',
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(font: r.noteGrasItalique, fontSize: _taillePied),
          ),
        ),
        place(
          gauche: 34, haut: 147,
          enfant: pw.Text(d.numero, style: pw.TextStyle(font: r.noteGras, fontSize: _taillePied)),
        ),

        // Titre : soulignement par une bordure (l'épaisseur et la position suivent la ligne, pas la police).
        place(
          gauche: 34, haut: 194.5, largeur: 781,
          enfant: pw.Center(
            child: pw.Container(
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1.3))),
              child: pw.Text(
                d.titre.toUpperCase(),
                style: pw.TextStyle(font: r.corpsGras, fontSize: 25, height: 24 / 25),
              ),
            ),
          ),
        ),

        // Corps : paragraphe justifié, puces, appréciation, formule de clôture.
        place(
          gauche: 34, haut: 232.7, largeur: 781,
          enfant: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.RichText(
                textAlign: pw.TextAlign.justify,
                text: pw.TextSpan(style: normal, children: segments(d.corps, normal, gras)),
              ),
              if (d.puces.isNotEmpty) ...[
                pw.SizedBox(height: 7.3),
                for (final ligne in d.puces)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 21),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.SizedBox(width: 16, height: pas, child: pw.Align(alignment: pw.Alignment.centerLeft, child: _fleche())),
                        pw.Expanded(
                          child: pw.Text(
                            apostrophes(ligne),
                            style: corps(14.2, hauteur: pas / 14.2),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (d.appreciation != null && d.appreciation!.trim().isNotEmpty)
                pw.RichText(
                  textAlign: pw.TextAlign.justify,
                  text: pw.TextSpan(style: normal, children: segments(d.appreciation!, normal, gras)),
                ),
              pw.SizedBox(height: 5.5),
              pw.Text(
                'En foi de quoi, la présente attestation lui est délivrée pour servir et valoir ce que de droit.',
                style: normal,
              ),
            ],
          ),
        ),

        // Signataires, de gauche à droite.
        for (final s in d.signataires) _signataire(s, r, corps),

        // Pied de page : e-mails et site, liens soulignés par une bordure.
        place(
          gauche: 34, haut: 559, largeur: 825,
          enfant: pw.Center(
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('E-mail', style: ligneActivite),
                pw.Text(' : ', style: ligneIdentite),
                _lien2(emails[0], ligneIdentite),
                pw.Text(' / ', style: ligneIdentite),
                _lien2(emails[1], ligneIdentite),
              ],
            ),
          ),
        ),
        place(
          gauche: 34, haut: 571.4, largeur: 825,
          enfant: pw.Center(
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('Site web', style: ligneActivite),
                pw.Text(':', style: ligneIdentite),
                _lien2(site, ligneIdentite),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Lien bleu souligné par une bordure.
  static pw.Widget _lien2(String texte, pw.TextStyle base) => pw.Container(
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.8, color: _lien))),
    child: pw.Text(texte, style: pw.TextStyle(font: base.font, fontSize: base.fontSize, color: _lien)),
  );

  /// Puce ➢ : une pointe de flèche pleine.
  static pw.Widget _fleche() => pw.CustomPaint(
    size: const PdfPoint(11, 9),
    painter: (canvas, taille) {
      canvas
        ..setFillColor(_noir)
        ..moveTo(0, 0)
        ..lineTo(taille.x, taille.y / 2)
        ..lineTo(0, taille.y)
        ..lineTo(taille.x * 0.28, taille.y / 2)
        ..closePath()
        ..fillPath();
    },
  );

  /// Un signataire : [bord gauche, largeur, retrait de la fonction] mesurés sur le modèle (pt).
  static const _boites = {
    2: (38.0, 205.0, 0.0),
    3: (316.0, 208.0, 0.0),
    1: (623.0, 190.0, 40.0),
  };

  static pw.Widget _signataire(
    LigneSignataire s,
    RessourcesAttestation r,
    pw.TextStyle Function(double, {pw.Font? police, PdfColor? couleur, double? hauteur}) corps,
  ) {
    final (gauche, largeur, retrait) = _boites[s.position] ?? _boites[1]!;
    final haut = s.titre.isNotEmpty ? (s.position == 3 ? 482.5 : 479.0) : 500.0;

    return pw.Positioned(
      left: gauche,
      top: haut,
      child: pw.SizedBox(
        width: largeur,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (s.titre.isNotEmpty)
              pw.Center(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1))),
                  child: pw.Text(s.titre, style: corps(11.7, police: r.corpsGras, hauteur: 12.5 / 11.7)),
                ),
              ),
            if (s.titre.isNotEmpty) pw.SizedBox(height: 6),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              // Jamais à la ligne : le nom du modèle (« SOGNIGBE Gbédjinou Serge Bruno ») dépasse la boîte de quelques points.
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.centerRight,
                child: pw.Text(s.nom, style: corps(13.7, police: r.corpsGras)),
              ),
            ),
            if (s.fonction.isNotEmpty)
              pw.Padding(
                padding: pw.EdgeInsets.only(top: 1.5, left: retrait),
                child: pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    apostrophes(s.fonction),
                    textAlign: pw.TextAlign.right,
                    style: corps(11.5, hauteur: 13 / 11.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
