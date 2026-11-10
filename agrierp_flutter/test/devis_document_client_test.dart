import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/features/ventes/devis_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// DEV-Q3 (DV-35) — LE DEVIS « DOCUMENT CLIENT » DU POSTE CONFRONTÉ À SON DOCUMENT MAÎTRE DU WEB (`exports/devis-document.blade.php`, `Devis::imprimerDevis`).
/// Libellés et ordre des faits sont LUS dans le Blade ; les montants (FCFA entiers) sont ceux du web (mêmes cas que `DevisDocumentClientTest`) ; le numéro est « — »
/// tant que le serveur ne l'a pas attribué, JAMAIS inventé.
String? _lire(String relatif) {
  final f = File('$dossierLaravel/$relatif');
  return f.existsSync() ? f.readAsStringSync() : null;
}

final String? _document = _lire('resources/views/exports/devis-document.blade.php');
final String? _liste = _lire('resources/views/livewire/ventes/devis.blade.php');
final String? _composant = _lire('app/Livewire/Ventes/Devis.php');
final String? absent = _document == null || _liste == null || _composant == null ? 'dépôt Laravel absent' : null;

String _norme(String t) => t.replaceAll(RegExp(r'\s+'), ' ').trim();

Quote _devis({String? numero, double amount = 100000, double taux = 18, int validite = 15, String? note = 'Paiement à la commande'}) => Quote(
  id: 'q1',
  deviceId: 'poste-test',
  quoteNumber: numero,
  customerId: 'c1',
  articlesDescription: '50 poulets de chair',
  amount: amount,
  tvaRate: taux,
  validityDays: validite,
  quoteDate: DateTime(2026, 11, 9),
  note: note,
  status: 'brouillon',
  isActive: true,
  syncStatus: SyncStatus.pending,
  updatedAt: DateTime(2026, 11, 9),
);

List<String> _textes(DocumentOfficiel d) => [
  d.sousTitre,
  for (final l in d.lignes)
    switch (l) {
      BandeDocument(:final libelle) => libelle,
      DonneesDocument(:final cellules) => cellules.join(' | '),
      TotalDocument(:final cellules) => cellules.where((c) => c.isNotEmpty).join(' | '),
      EnteteDocument(:final cellules) => cellules.join(' | '),
    },
  ...d.mentions,
];

DocumentOfficiel _doc(Quote q) => DevisRepository.documentDevis(
  LigneDevis(devis: q, client: 'Awa KPOGNON', telephone: '97000000', ville: 'Porto-Novo', ifuClient: '1234567890123'),
  DateTime(2026, 11, 10),
);

void main() {
  test('libellés du document : ceux du Blade maître, dans l\'ordre', () {
    final blade = _norme(_document!);
    for (final libelle in ['Devis <strong>', 'Client :', 'IFU du client :', "Date d'émission :", "Valable jusqu'au :", '(durée de validité :', 'Désignation', 'Montant HT', 'Montant HT :', 'TVA (', 'Total TTC :', 'Observations :', '<strong>Bon pour accord</strong>', 'Date : ____ / ____ / ________', 'Signature du client :']) {
      expect(blade, contains(libelle), reason: 'absent du Blade : $libelle');
    }
    final d = _doc(_devis(numero: 'DEV-2026-007'));
    expect(d.titre, 'Devis');
    expect(_composant!, contains("'Devis',"));
    expect(d.entetes, ['Désignation', 'Montant HT']);
    final t = _textes(d);
    final attendu = [
      'Devis DEV-2026-007',
      'Client : Awa KPOGNON — 97000000 — Porto-Novo',
      'IFU du client : 1234567890123',
      "Date d'émission : 09/11/2026",
      "Valable jusqu'au : 24/11/2026 (durée de validité : 15 jours)",
      '50 poulets de chair | 100 000',
      'Montant HT : 100 000 FCFA',
      'TVA (18 %) : 18 000 FCFA',
      'Total TTC : 118 000 FCFA',
      'Observations : Paiement à la commande',
      'Bon pour accord',
      'Date : ____ / ____ / ________',
      'Signature du client :',
    ];
    var dernier = -1;
    for (final a in attendu) {
      final i = t.indexOf(a);
      expect(i, greaterThan(dernier), reason: 'absent ou hors ordre : $a');
      dernier = i;
    }
    expect(d.sousTitre, 'N° DEV-2026-007 — émis le 09/11/2026');
    expect(_composant!, contains(r"'N° '.$quote->quote_number.' — émis le '.$quote->quote_date->format('d/m/Y')"));
    expect(d.fichier, 'devis-DEV-2026-007.pdf');
    expect(_composant!, contains(r"'devis-'.$quote->quote_number.'.pdf'"));
  }, skip: absent);

  test('le numéro est « — » tant que le serveur ne l\'a pas attribué, jamais inventé', () {
    final d = _doc(_devis(numero: null));
    final t = _textes(d);
    expect(d.sousTitre, 'N° — — émis le 09/11/2026');
    expect(t, contains('Devis —'));
    expect(t.any((x) => RegExp(r'DEV-\d').hasMatch(x)), isFalse);
    expect(d.fichier, 'devis-en-attente.pdf');
    expect(d.noteDePied, contains('« — » en numéro'));
    expect(_doc(_devis(numero: 'DEV-2026-001')).noteDePied, isNull);
  });

  test('montants en FCFA entiers : mêmes cas que le web (HT, TVA = TTC − HT, TTC)', () {
    for (final c in [
      (100000.0, 18.0, '100 000', '18 000', '118 000', '18'),
      (12345.0, 18.0, '12 345', '2 222', '14 567', '18'),
      (999.5, 0.0, '1 000', '0', '1 000', '0'),
      (1000.0, 7.5, '1 000', '75', '1 075', '7,5'),
    ]) {
      final t = _textes(_doc(_devis(numero: 'DEV-2026-009', amount: c.$1, taux: c.$2)));
      expect(t, contains('Montant HT : ${c.$3} FCFA'), reason: '${c.$1}');
      expect(t, contains('TVA (${c.$6} %) : ${c.$4} FCFA'), reason: 'TVA ${c.$1}/${c.$2}');
      expect(t, contains('Total TTC : ${c.$5} FCFA'), reason: 'TTC ${c.$1}/${c.$2}');
    }
  });

  test('sans observations ni coordonnées : rien d\'inventé ; validité = date + jours du devis', () {
    final d = DevisRepository.documentDevis(LigneDevis(devis: _devis(numero: 'DEV-2026-002', note: null, validite: 30)), DateTime(2026, 11, 10));
    final t = _textes(d);
    expect(t.any((x) => x.startsWith('Observations')), isFalse);
    expect(t.any((x) => x.startsWith('IFU du client')), isFalse);
    expect(t, contains('Client : —'));
    expect(t, contains("Valable jusqu'au : 09/12/2026 (durée de validité : 30 jours)"));
  });

  test('bouton « Imprimer le devis » : au web (droit export-ventes) et au poste, avant « Modifier »', () {
    expect(_liste!, contains('wire:click="imprimerDevis('));
    expect(_liste!, contains('title="Imprimer le devis"'));
    expect(_liste!, contains("@can('export-ventes')"));
    expect(_composant!, contains(r'public function imprimerDevis(string $id)'));
    final onglet = File('lib/features/ventes/devis_onglet.dart').readAsStringSync();
    expect(onglet, contains("infobulle: 'Imprimer le devis'"));
    expect(onglet, contains('widget.peutExporter && widget.imprimer != null'));
    expect(onglet.indexOf("'devis-imprimer-"), lessThan(onglet.indexOf("'devis-modifier-")));
  }, skip: absent);
}
