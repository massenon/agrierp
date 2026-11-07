import 'dart:io';

import 'package:agrierp/features/ventes/choix_facture.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

String? readSource(String chemin) => File(chemin).existsSync() ? File(chemin).readAsStringSync() : null;

/// MECEF-3 — PARITÉ EXÉCUTÉE : le VRAI `App\Services\Mecef\ChoixFactureService` du serveur et `ChoixFacture.valider` du poste
/// reçoivent les mêmes saisies (type, IFU, nom, taux d'AIB) et doivent rendre le même choix validé ou le même refus (champ ET
/// motif). Rien n'est recopié : les cas sont une donnée JSON jouée des deux côtés. Sans PHP ni dépôt Laravel, les tests sont
/// SAUTÉS AVEC LEUR RAISON.
const _script = r'''<?php
use Illuminate\Validation\ValidationException;
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
$svc = app(App\Services\Mecef\ChoixFactureService::class);
$sortie = [];
foreach ($in as $c) {
    try {
        $r = $svc->valider(array_filter($c, fn ($v) => $v !== null));
        $sortie[] = ['ok' => true, 'type' => $r['facture_type'], 'ifu' => $r['client_ifu'], 'nom' => $r['client_nom_facture'], 'aib' => $r['aib_taux']];
    } catch (ValidationException $e) {
        $champ = array_key_first($e->errors());
        $sortie[] = ['ok' => false, 'champ' => $champ, 'motif' => $e->errors()[$champ][0]];
    }
}
echo json_encode($sortie);
''';

void main() {
  final saut = sautSansPhp();

  final cas = <Map<String, Object?>>[
    {},
    {'facture_type': 'simple'},
    {'facture_type': 'simple', 'client_ifu': 'zz', 'client_nom_facture': 'A', 'aib_taux': '9%'},
    {'facture_type': '  '},
    {'facture_type': 'speciale'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'KPOGNON Séraphin', 'client_ifu': '1234567890123', 'aib_taux': '5%'},
    {'facture_type': 'normalisee', 'client_nom_facture': ' A B ', 'client_ifu': '123 456 789 0123', 'aib_taux': '1%'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'Particulier', 'client_ifu': '', 'aib_taux': 'N/A'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'Particulier', 'aib_taux': 'N/A'},
    {'facture_type': 'normalisee', 'client_nom_facture': '', 'aib_taux': '5%'},
    {'facture_type': 'normalisee', 'client_nom_facture': '   ', 'aib_taux': '5%'},
    {'facture_type': 'normalisee', 'aib_taux': '5%'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'A', 'client_ifu': '12345', 'aib_taux': '5%'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'A', 'client_ifu': '12345678901234', 'aib_taux': '5%'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'A', 'client_ifu': 'ABCDEFGHIJKLM', 'aib_taux': '5%'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'A', 'aib_taux': '9%'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'A', 'aib_taux': '5 %'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'A'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'N' * 150, 'aib_taux': '5%'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'N' * 151, 'aib_taux': '5%'},
    // Le nom est jugé avant l'IFU, l'IFU avant l'AIB : le premier refus est le même des deux côtés.
    {'facture_type': 'normalisee', 'client_nom_facture': '', 'client_ifu': '1', 'aib_taux': '9%'},
    {'facture_type': 'normalisee', 'client_nom_facture': 'A', 'client_ifu': '1', 'aib_taux': '9%'},
  ];

  Map<String, Object?> local(Map<String, Object?> c) {
    try {
      final r = ChoixFacture.valider(
        type: c['facture_type'] as String?,
        ifu: c['client_ifu'] as String?,
        nom: c['client_nom_facture'] as String?,
        aib: c['aib_taux'] as String?,
      );
      return {'ok': true, 'type': r.type, 'ifu': r.ifu, 'nom': r.nom, 'aib': r.aib};
    } on ChoixFactureRefuse catch (e) {
      return {'ok': false, 'champ': e.champ, 'motif': e.message};
    }
  }

  test('⚠️⚠️ même choix validé, même refus (champ et motif) : le serveur et le poste', () {
    final attendu = (executerPhp(_script, cas, application: true) as List).cast<Map>();

    expect(attendu, hasLength(cas.length));
    // Le jeu doit réellement produire des acceptations ET des refus de chaque champ.
    expect({for (final a in attendu) a['ok']}, {true, false});
    expect({for (final a in attendu) if (a['ok'] == false) a['champ']}, {'facture_type', 'client_nom_facture', 'client_ifu', 'aib_taux'});

    for (var i = 0; i < cas.length; i++) {
      expect({for (final e in local(cas[i]).entries) e.key: e.value}, {for (final e in local(cas[i]).entries) e.key: attendu[i][e.key]}, reason: 'cas $i : ${cas[i]}');
    }
  }, skip: saut);

  test('les libellés du type de facture et des taux d\'AIB sont ceux du serveur (`FactureType`, `AibTaux`)', () {
    final php = '$dossierLaravel/app/Support';
    final type = readSource('$php/FactureType.php');
    final aib = readSource('$php/AibTaux.php');
    if (type == null || aib == null) {
      markTestSkipped('SAUT : dépôt Laravel absent ($dossierLaravel)');
      return;
    }

    for (final e in ChoixFacture.libellesTypes.entries) {
      expect(type, contains("'${e.value}'"));
    }
    expect(type, contains("MENTION_SIMPLE = '${ChoixFacture.mentionSimple}'"));
    expect(type, contains("MENTION_EN_ATTENTE = '${ChoixFacture.mentionEnAttente}'"));
    for (final e in ChoixFacture.libellesAib.entries) {
      expect(aib, contains("'${e.value}'"));
    }
    expect(aib, contains("DEFAUT = self::CINQ"));
    expect(aib, contains("CINQ = '${ChoixFacture.aibDefaut}'"));
    // Ordre de la liste : 5 % d'abord (le cas général).
    expect(ChoixFacture.libellesAib.keys.first, '5%');
  });
}
