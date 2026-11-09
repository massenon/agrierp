import 'dart:io';

import 'package:agrierp/features/ventes/mode_paiement.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// CONF-3 (DV-22) — PARITÉ EXÉCUTÉE : le VRAI `App\Support\ModePaiement::libelle` du serveur et `ModePaiement.libelle` du poste
/// reçoivent les mêmes clés (connues, inconnues, vides, à tiret bas, accentuées) et rendent le même libellé. Sans PHP ni dépôt
/// Laravel, le test est SAUTÉ AVEC SA RAISON.
const _script = r'''<?php
require getcwd() . '/vendor/autoload.php';
$in = json_decode(file_get_contents($argv[1]), true);
echo json_encode(array_map(fn ($c) => App\Support\ModePaiement::libelle($c), $in));
''';

void main() {
  final saut = sautSansPhp();

  final cles = <String?>[
    'especes',
    'mobile_money',
    'virement',
    'cheque',
    'credit',
    'avance',
    'carte_bancaire',
    'carte',
    'moov_money',
    'étrange',
    '  especes  ',
    'ESPECES',
    '',
    '   ',
    null,
    '_',
    'x',
  ];

  test('⚠️⚠️ même libellé pour chaque clé : le serveur et le poste', () {
    final attendu = (executerPhp(_script, cles) as List).cast<String>();

    expect(attendu, hasLength(cles.length));
    expect(attendu.where((l) => l.isEmpty), isEmpty, reason: 'jamais un libellé vide');
    for (var i = 0; i < cles.length; i++) {
      expect(ModePaiement.libelle(cles[i]), attendu[i], reason: 'clé « ${cles[i]} »');
    }
    // Les libellés retenus (DV-22).
    expect(attendu.sublist(0, 6), ['Espèces', 'Mobile Money', 'Virement bancaire', 'Chèque', 'Crédit client', 'Avance']);
    expect(ModePaiement.libelle('carte_bancaire'), 'Carte bancaire');
  }, skip: saut);

  test('le poste n\'écrit jamais la clé brute sur la facture ni dans le détail de facturation', () {
    final facture = _lire('lib/features/ventes/facturation_repository.dart');
    final ecran = _lire('lib/features/ventes/facturation_screen.dart');
    expect(facture, contains('Mode de règlement : \${ModePaiement.libelle(v.paymentMode)}'));
    expect(ecran, contains("ModePaiement.libelle(v.paymentMode)"));
    expect(ecran, isNot(contains("_ligneDetail('Mode de paiement', v.paymentMode)")));
  });
}

String _lire(String chemin) => File(chemin).readAsStringSync();
