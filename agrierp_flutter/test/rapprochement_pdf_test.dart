import 'dart:io';

import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/features/comptabilite/documents_comptabilite.dart';
import 'package:agrierp/features/comptabilite/rapprochement_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket AUT-1 — l'export PDF du rapprochement se produit AU POSTE (sans réseau), avec les mots du Blade d'export.
void main() {
  Rapprochement exemple({double ecart = 0}) {
    final l = LigneRapprochement(id: 'a', date: DateTime(2026, 10, 3), libelle: 'Vente comptoir', montant: 15000)..pointee = true;
    final i = LigneRapprochement(id: 'b', date: DateTime(2026, 10, 9), libelle: 'Chèque 112', montant: -4000);
    final n = LigneRapprochement(id: 'c', date: DateTime(2026, 10, 12), libelle: 'Frais bancaires', montant: -500);
    return Rapprochement(livre: [l, i], releve: [l, n], ouverture: 0, soldeLivre: 11000, soldeReleve: 14500, enInstance: -4000, nouveauNonSaisi: -500, ecart: ecart);
  }

  final doc = DocumentsComptabilite.rapprochement(exemple(), compte: '521 Banque', debut: DateTime(2026, 10, 1), fin: DateTime(2026, 10, 28));

  test('le document porte le titre, la période et le nom de fichier du web', () {
    expect(doc.titre, 'Rapprochement Bancaire — Compte 521 Banque');
    expect(doc.sousTitre, 'Période du 01/10/2026 au 28/10/2026');
    expect(DocumentOfficiel.nomPdf(doc, DateTime(2026, 10, 28)), 'rapprochement-bancaire-2026-10-28.pdf');
    expect(doc.entetes, ['Date', 'Libellé', 'Montant', 'Statut']);
  });

  test('les deux tableaux et leurs statuts sont ceux du web', () {
    final textes = doc.lignes.map((x) => switch (x) {
          BandeDocument(:final libelle) => libelle,
          EnteteDocument(:final cellules) || DonneesDocument(:final cellules) || TotalDocument(:final cellules) => cellules.join('|'),
        }).toList();
    expect(textes, contains('03/10/2026|Vente comptoir|15 000|Pointé'));
    expect(textes, contains('09/10/2026|Chèque 112|-4 000|En instance'));
    expect(textes, contains('12/10/2026|Frais bancaires|-500|Nouveau — à saisir'));
    expect(textes.first, 'Solde Livre : 11 000 FCFA — Solde Relevé : 14 500 FCFA — Opérations en instance : 4 000 FCFA');
    expect(textes, contains('RELEVÉ BANCAIRE IMPORTÉ'));
  });

  test('le verdict : équilibré, ou écart à justifier', () {
    expect(doc.noteDePied, 'Rapprochement équilibré — écart nul.');
    final d = DocumentsComptabilite.rapprochement(exemple(ecart: 1500), compte: '', debut: DateTime(2026, 10, 1), fin: DateTime(2026, 10, 28));
    expect(d.noteDePied, 'Rapprochement déséquilibré — écart de 1 500 FCFA à justifier avant clôture.');
  });

  test('les libellés fixes sont ceux du Blade d\'export', () {
    final blade = File('$dossierLaravel/resources/views/exports/rapprochement-bancaire.blade.php');
    if (!blade.existsSync()) return;
    final src = blade.readAsStringSync();
    for (final mot in ['GRAND LIVRE', 'RELEVÉ BANCAIRE IMPORTÉ', 'Nouveau — à saisir', 'En instance', 'Pointé', 'Rapprochement équilibré — écart nul.']) {
      expect(src, contains(mot));
    }
  });
}
