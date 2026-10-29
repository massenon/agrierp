import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../config/fichiers_entreprise.dart';

/// Une ligne du corps d'un document officiel.
///
/// ⚠️ **QUATRE FORMES, PARCE QUE LA MAQUETTE EN EMPLOIE QUATRE.** Les exports
/// de `rapport-recettes-depenses.html` et `rapport-elevage-synth.html` ne sont
/// pas de simples tableaux : ils intercalent des BANDES de section
/// (« RECETTES », « TABLEAU 1 — RECENSEMENT HEBDOMADAIRE »), réécrivent une
/// ligne d'en-tête EN GRAS sous chaque bande, et referment sur un bloc de
/// TOTAUX souligné. Rendre tout cela en lignes ordinaires produirait un
/// document lisible mais différent de celui que le commanditaire a validé.
sealed class LigneDocument {
  const LigneDocument();
}

/// Bande de section : un libellé sur toute la largeur, gras, fond gris.
class BandeDocument extends LigneDocument {
  const BandeDocument(this.libelle);

  final String libelle;
}

/// Ligne d'en-tête réécrite dans le corps, en gras et sans fond.
class EnteteDocument extends LigneDocument {
  const EnteteDocument(this.cellules);

  final List<String> cellules;
}

/// Ligne de données ordinaire.
class DonneesDocument extends LigneDocument {
  const DonneesDocument(this.cellules);

  final List<String> cellules;
}

/// Ligne de total. [premiere] pose le filet épais qui ouvre le bloc.
class TotalDocument extends LigneDocument {
  const TotalDocument(this.cellules, {this.premiere = false});

  final List<String> cellules;
  final bool premiere;
}

/// Un document officiel AgriERP, prêt à imprimer.
///
/// Transposition de `prototype_html/assets/js/pdf-export.js` —
/// `exportOfficialPDF(opts)`.
///
/// ⚠️ **LE PROJET VOISIN LogiALVIA EMPLOIE `generateOfficialPDF()` ET UNE AUTRE
/// PALETTE.** Ne jamais reporter ses conventions ici, ni l'inverse.
class DocumentOfficiel {
  const DocumentOfficiel({
    required this.titre,
    required this.sousTitre,
    required this.lignes,
    this.entetes = const [],
    this.filigrane,
    this.noteDePied,
    this.fichier,
  });

  /// 🔴→✅ Ticket U11 — NOM DU FICHIER PDF, celui que le web donne au même export (`streamDownload(…, 'stocks-'.
  /// now()->format('Y-m-d').'.pdf')`), avec deux marques remplacées à l'édition par la date du poste :
  /// `{jour}` → `AAAA-MM-JJ`, `{mois}` → `AAAA-MM` (voir [nomPdf]). `null` : le web n'édite pas ce document (nom
  /// tiré du titre, horodaté).
  final String? fichier;

  /// Nom proposé à la boîte d'impression (« Enregistrer au format PDF ») : [fichier] daté, sinon le titre réduit
  /// en tirets et horodaté à la minute. 🔴 Avant U11, TOUS les PDF du poste portaient le nom du classeur
  /// (`…-AAAAMMJJ-HHMM.xlsx`) : extension fausse et nom différent du web.
  static String nomPdf(DocumentOfficiel document, DateTime maintenant) {
    String deux(int n) => n.toString().padLeft(2, '0');
    final mois = '${maintenant.year}-${deux(maintenant.month)}';
    final modele = document.fichier;
    if (modele != null) {
      return modele
          .replaceAll('{jour}', '$mois-${deux(maintenant.day)}')
          .replaceAll('{mois}', mois);
    }
    final base = document.titre
        .replaceAll(RegExp(r'[^A-Za-zÀ-ÿ0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '$base-${maintenant.year}${deux(maintenant.month)}${deux(maintenant.day)}'
        '-${deux(maintenant.hour)}${deux(maintenant.minute)}.pdf';
  }

  /// `opts.title` — repris tel quel du bouton d'export de chaque rapport.
  final String titre;

  /// `opts.subtitle`.
  final String sousTitre;

  /// `opts.tableHeadHtml`. Vide quand le document porte ses en-têtes dans le
  /// corps, sous chaque bande de section (recettes/dépenses, élevage).
  final List<String> entetes;

  final List<LigneDocument> lignes;

  /// `opts.watermark` — « PROFORMA » et consorts.
  final String? filigrane;

  /// `opts.footerNote`.
  final String? noteDePied;

  /// Nombre de colonnes du document, bandes exclues.
  int get colonnes {
    if (entetes.isNotEmpty) return entetes.length;

    var maximum = 0;
    for (final ligne in lignes) {
      final n = switch (ligne) {
        BandeDocument() => 0,
        EnteteDocument(:final cellules) => cellules.length,
        DonneesDocument(:final cellules) => cellules.length,
        TotalDocument(:final cellules) => cellules.length,
      };
      if (n > maximum) maximum = n;
    }
    return maximum;
  }
}

/// Polices embarquées d'un document (octets TrueType).
///
/// ⚠️⚠️ **SANS ELLES, LE PDF DESSINE UN CARRÉ BARRÉ** à la place de « — » et de
/// « ’ » : la police par défaut du moteur (Helvetica) n'a pas Unicode. Le pied de
/// page des trois structures et l'adresse de la ferme en portent ; le tiret des
/// valeurs inconnues aussi. Constaté en octets (ticket F0.75) : l'opérateur
/// graphique du carré barré remplace le texte, sans aucune erreur.
class PolicesDocument {
  const PolicesDocument({required this.normale, required this.grasse});

  final Uint8List normale;
  final Uint8List grasse;
}

/// Fabrique de documents officiels.
///
/// ⚠️⚠️ **LA CONSTRUCTION ET L'IMPRESSION SONT SÉPARÉES, ET C'EST VOLONTAIRE.**
/// [construire] ne touche ni l'imprimante ni le système : elle est donc
/// vérifiable par un test ordinaire, sans périphérique. Un moteur d'édition
/// qu'on ne peut contrôler qu'en imprimant vraiment ne serait contrôlé nulle
/// part.
class ExportOfficiel {
  const ExportOfficiel._();

  // ── Identité, reprise mot pour mot de `pdf-export.js` ──────────────────────

  static const cheminLogo = 'assets/images/logo.png';
  static const nomFerme = 'FERME ÉCOLE OLOUWACHEGOUN';
  static const adresseFerme =
      'Attan-Ewé, Arrondissement d’Ikpinlè, Adja-Ouèrè, Bénin';

  /// ⚠️⚠️ **LES TROIS STRUCTURES, ET NON LES DEUX DE LA MAQUETTE.**
  /// `pdf-export.js` a été écrit avant les tickets 15.7 et 15.8 : son pied ne
  /// nomme que le PAEB et le cabinet. L'application, elle, crédite désormais
  /// les trois — maîtrise d'ouvrage, accompagnement, éditeur — et un test
  /// dédié (`CreditsProjetTest`) l'y verrouille, précisément parce qu'un
  /// crédit disparu n'émet aucune erreur.
  ///
  /// Un rapport imprimé SORT DE LA FERME. C'est le support où la mention
  /// compte le plus, et la règle de hiérarchie du projet est claire : sur une
  /// règle métier, l'implémentation Laravel l'emporte sur la maquette. La
  /// ligne est donc celle du pied de page de l'application, au mot près.
  static const creditsProjet =
      'LogiAgriERP — Projet d’Appui à l’Entrepreneuriat au Bénin (PAEB) '
      '— Accompagnement : Cabinet FAGUEZ SARL '
      '— Édité par Dr MASSENON Rhodes';

  // ── Palette du document, relevée sur la feuille de style de l'export ───────

  static const _encreForet = PdfColor.fromInt(0xFF052E16);
  static const _encreEmeraude = PdfColor.fromInt(0xFF065F46);
  static const _encreSousEntete = PdfColor.fromInt(0xFF15803D);
  static const _encreTexte = PdfColor.fromInt(0xFF191C1D);
  static const _encreDiscrete = PdfColor.fromInt(0xFF6F7973);
  static const _filet = PdfColor.fromInt(0xFFBEC9C2);
  static const _fondBande = PdfColor.fromInt(0xFFF3F4F5);

  /// `rgba(186,26,26,0.12)` — le rouge profond du projet, à 12 %.
  static const _encreFiligrane = PdfColor(186 / 255, 26 / 255, 26 / 255, 0.12);

  /// Construit le PDF. [maintenant] est injecté : un document daté par
  /// `DateTime.now()` ne pourrait pas être comparé d'une exécution à l'autre.
  static Future<Uint8List> construire(
    DocumentOfficiel doc, {
    required DateTime maintenant,
    Uint8List? logo,
    PolicesDocument? polices,
  }) async {
    final document = pw.Document(title: 'LogiAgriERP - ${doc.titre}');
    final image = logo == null ? null : pw.MemoryImage(logo);
    final theme = polices == null
        ? null
        : pw.ThemeData.withFont(
            base: pw.Font.ttf(ByteData.sublistView(polices.normale)),
            bold: pw.Font.ttf(ByteData.sublistView(polices.grasse)),
          );

    document.addPage(
      pw.MultiPage(
        // ⚠️⚠️ **LE FILIGRANE EST UN FOND DE PAGE, PAS UN BLOC DU CORPS.**
        // `pdf-export.js` le pose en `position:fixed` : il flotte au-dessus de
        // la page sans occuper de place. Rendu comme un widget ordinaire, il
        // pousserait le tableau de 90 px vers le bas sur CHAQUE page — un
        // document toujours lisible, et toujours différent de celui qui a été
        // validé. Il se répète aussi sur toutes les pages, comme le ferait un
        // élément fixe à l'impression.
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(15),
          theme: theme,
          buildBackground: doc.filigrane == null
              ? null
              : (_) => _filigrane(doc.filigrane!),
        ),
        header: (_) => _entete(doc, image, maintenant),
        footer: (_) => _pied(maintenant),
        build: (_) => [
          _tableau(doc),
          if (doc.noteDePied != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                doc.noteDePied!,
                style: const pw.TextStyle(fontSize: 9, color: _encreTexte),
              ),
            ),
        ],
      ),
    );

    return document.save();
  }

  /// Charge le logo officiel embarqué. Rendu séparément pour qu'un test
  /// puisse construire un document sans dépendre du chargeur d'actifs.
  static Future<Uint8List> chargerLogo() async {
    // Ticket AUT-2 — le logo choisi par la ferme (Paramètres > Données de l'Entreprise) passe avant celui de l'installation.
    try {
      final choisi = await FichiersEntreprise.courant.logoPourPdf();
      if (choisi != null) return choisi;
    } catch (_) {}
    return (await rootBundle.load(cheminLogo)).buffer.asUint8List();
  }

  static const cheminPoliceNormale = 'assets/fonts/Roboto-Regular.ttf';
  static const cheminPoliceGrasse = 'assets/fonts/Roboto-Bold.ttf';

  /// Charge les polices embarquées — OBLIGATOIRE pour tout document qui sort
  /// de la ferme (voir [PolicesDocument]).
  static Future<PolicesDocument> chargerPolices() async => PolicesDocument(
    normale: (await rootBundle.load(cheminPoliceNormale)).buffer.asUint8List(),
    grasse: (await rootBundle.load(cheminPoliceGrasse)).buffer.asUint8List(),
  );

  // ── Blocs ─────────────────────────────────────────────────────────────────

  static pw.Widget _entete(
    DocumentOfficiel doc,
    pw.MemoryImage? logo,
    DateTime maintenant,
  ) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    margin: const pw.EdgeInsets.only(bottom: 15),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _encreForet, width: 2)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null) ...[
                pw.SizedBox(height: 48, child: pw.Image(logo)),
                pw.SizedBox(width: 12),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      nomFerme,
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: _encreForet,
                      ),
                    ),
                    pw.Text(
                      doc.titre.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _encreEmeraude,
                      ),
                    ),
                    if (doc.sousTitre.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 2),
                        child: pw.Text(
                          doc.sousTitre,
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: _encreTexte,
                          ),
                        ),
                      ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text(
                        adresseFerme,
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: _encreDiscrete,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.Text(
          'Imprimé le ${_date(maintenant)}',
          style: const pw.TextStyle(fontSize: 9, color: _encreDiscrete),
        ),
      ],
    ),
  );

  static pw.Widget _pied(DateTime maintenant) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 20),
    padding: const pw.EdgeInsets.only(top: 5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _filet)),
    ),
    child: pw.Text(
      '© ${maintenant.year} $creditsProjet',
      textAlign: pw.TextAlign.center,
      style: const pw.TextStyle(fontSize: 9, color: _encreDiscrete),
    ),
  );

  /// ⚠️ `rotate(-25deg)` EN CSS VAUT +25° ICI : le sens positif du CSS est
  /// horaire, celui de `Transform.rotate` antihoraire. Le signe recopié tel
  /// quel inclinerait le filigrane du mauvais côté.
  static pw.Widget _filigrane(String texte) => pw.FullPage(
    ignoreMargins: true,
    child: pw.Center(
      child: pw.Transform.rotate(
        angle: 25 * 3.1415926535897932 / 180,
        child: pw.Text(
          texte,
          style: pw.TextStyle(
            fontSize: 90,
            fontWeight: pw.FontWeight.bold,
            color: _encreFiligrane,
          ),
        ),
      ),
    ),
  );

  static pw.Widget _tableau(DocumentOfficiel doc) {
    final colonnes = doc.colonnes;
    if (colonnes == 0) return pw.SizedBox();

    return pw.Table(
      children: [
        if (doc.entetes.isNotEmpty)
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _encreForet),
            children: [
              for (final libelle in doc.entetes)
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _encreForet),
                  ),
                  child: pw.Text(
                    libelle.toUpperCase(),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
            ],
          ),
        for (final ligne in doc.lignes) _rangee(ligne, colonnes),
      ],
    );
  }

  static pw.TableRow _rangee(LigneDocument ligne, int colonnes) =>
      switch (ligne) {
        // ⚠️ La bande occupe TOUTE la largeur dans la maquette (`colspan`).
        // `pw.Table` n'a pas de fusion de cellules : la bande est rendue dans
        // la première colonne et les suivantes restent vides, sur le même
        // fond — le résultat est identique à l'œil, sans quoi la bande
        // n'occuperait qu'un treizième de la ligne.
        BandeDocument(:final libelle) => pw.TableRow(
          decoration: const pw.BoxDecoration(color: _fondBande),
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
              child: pw.Text(
                libelle,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _encreTexte,
                ),
              ),
            ),
            for (var i = 1; i < colonnes; i++) pw.SizedBox(),
          ],
        ),

        EnteteDocument(:final cellules) => pw.TableRow(
          children: [
            for (var i = 0; i < colonnes; i++)
              pw.Container(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text(
                  i < cellules.length ? cellules[i] : '',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _encreSousEntete,
                  ),
                ),
              ),
          ],
        ),

        DonneesDocument(:final cellules) => pw.TableRow(
          children: [
            for (var i = 0; i < colonnes; i++)
              pw.Container(
                padding: const pw.EdgeInsets.all(5),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: _filet)),
                ),
                child: pw.Text(
                  i < cellules.length ? cellules[i] : '',
                  style: const pw.TextStyle(fontSize: 10, color: _encreTexte),
                ),
              ),
          ],
        ),

        TotalDocument(:final cellules, :final premiere) => pw.TableRow(
          children: [
            for (var i = 0; i < colonnes; i++)
              pw.Container(
                padding: pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: premiere ? 8 : 4,
                ),
                decoration: premiere
                    ? const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: _encreForet, width: 2),
                        ),
                      )
                    : null,
                child: pw.Text(
                  i < cellules.length ? cellules[i] : '',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _encreTexte,
                  ),
                ),
              ),
          ],
        ),
      };

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
