import 'package:agrierp/features/rh/attestations_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket ATT-2 — PARITÉ EXÉCUTÉE : le VRAI `App\Services\AttestationService` du serveur et la règle du poste
/// (`ReglageSignature`, `AttestationsRepository`) reçoivent les mêmes dates et doivent rendre les mêmes palier, signataires,
/// durées en toutes lettres et dates longues. Jour fixé au 24/10/2026 (sans date de fin, la durée court jusqu'à lui).
///
/// Rien n'est recopié : les cas sont une donnée JSON jouée des deux côtés (SQLite en mémoire côté PHP). Sans PHP ni dépôt
/// Laravel, les tests sont SAUTÉS AVEC LEUR RAISON.
const _script = r'''<?php
use Illuminate\Support\Carbon;
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
Carbon::setTestNow('2026-10-24 10:00:00');
$svc = app(App\Services\AttestationService::class);
$sortie = [];
foreach ($in as $c) {
    App\Models\AttestationTemplate::forType('stagiaire')->update($c['modele']);
    $debut = $c['debut']; $fin = $c['fin'];
    $sortie[] = [
        'palier' => App\Services\AttestationService::palier($debut, $fin, (int) $c['modele']['seuil_signature_mois']),
        'positions' => array_column($svc->signataires('stagiaire', $debut, $fin, $c['surcharges']), 'position'),
        'noms' => array_column($svc->signataires('stagiaire', $debut, $fin, $c['surcharges']), 'nom'),
        'duree' => App\Services\AttestationService::formatDuree($debut, $fin),
        'deDuree' => App\Services\AttestationService::deDuree($debut, $fin),
        'debutLongue' => $debut ? App\Services\AttestationService::dateLongue(Carbon::parse($debut)) : '',
    ];
}
echo json_encode($sortie);
''';

DateTime? _d(String? s) => s == null ? null : DateTime.parse(s);

void main() {
  final saut = sautSansPhp();
  final aujourdhui = DateTime(2026, 10, 24);

  /// Un modèle du serveur : seuil et drapeaux court / long de chaque signataire.
  Map<String, Object?> modele({int seuil = 12, List<bool> court = const [true, false, false], List<bool> long = const [true, true, true]}) => {
    'seuil_signature_mois': seuil,
    for (var n = 1; n <= 3; n++) ...{'sig${n}_court': court[n - 1], 'sig${n}_long': long[n - 1]},
  };

  final cas = <Map<String, Object?>>[
    // Autour du seuil de douze mois.
    for (final (d, f) in [
      ('2026-09-24', '2026-10-24'), ('2026-10-20', '2026-10-24'), ('2025-10-15', '2026-10-15'), ('2025-10-15', '2026-10-16'),
      ('2025-10-16', '2026-10-15'), ('2024-01-01', '2026-10-24'), ('2025-03-01', '2026-03-01'), ('2025-03-01', '2026-03-02'),
      // Fins de mois : le 31 janvier + 1 mois, années bissextiles.
      ('2026-01-31', '2026-02-28'), ('2024-01-31', '2024-02-29'), ('2025-02-28', '2026-02-28'), ('2024-02-29', '2025-02-28'),
      ('2024-02-29', '2025-03-01'), ('2025-01-31', '2026-01-31'), ('2025-01-31', '2026-02-01'), ('2025-11-30', '2026-02-28'),
      // Sans fin : jusqu'au 24/10/2026.
      ('2024-03-01', null), ('2026-06-01', null), ('2025-10-24', null), ('2025-10-23', null), ('2026-10-24', null),
      // Sans début.
      (null, null), (null, '2026-10-24'),
    ])
      {'debut': d, 'fin': f, 'modele': modele(), 'surcharges': <String, Object?>{}},
    // Un seuil réglé, des paliers réglés, des signataires modifiés pour l'attestation.
    {'debut': '2026-04-24', 'fin': '2026-10-24', 'modele': modele(seuil: 6), 'surcharges': <String, Object?>{}},
    {'debut': '2026-04-23', 'fin': '2026-10-24', 'modele': modele(seuil: 6), 'surcharges': <String, Object?>{}},
    {'debut': '2026-09-24', 'fin': '2026-10-24', 'modele': modele(court: [true, true, false]), 'surcharges': <String, Object?>{}},
    {'debut': '2024-01-01', 'fin': '2026-10-24', 'modele': modele(long: [false, true, true]), 'surcharges': <String, Object?>{}},
    {'debut': '2024-01-01', 'fin': '2026-10-24', 'modele': modele(), 'surcharges': {'sig2': {'nom': 'KPOHAZOUNDE Jean'}, 'sig3': {'fonction': 'Président'}}},
    {'debut': '2026-09-24', 'fin': '2026-10-24', 'modele': modele(), 'surcharges': {'sig2': {'nom': 'KPOHAZOUNDE Jean'}}},
  ];

  List<Map<String, Object?>> local() => [
    for (final c in cas)
      () {
        final m = c['modele'] as Map<String, Object?>;
        final debut = _d(c['debut'] as String?);
        final fin = _d(c['fin'] as String?);
        final base = ReglageSignature.defaut;
        final reglage = ReglageSignature(
          seuilMois: m['seuil_signature_mois'] as int,
          signataires: {
            for (final n in [1, 2, 3])
              n: base.signataires[n]!.avec(court: m['sig${n}_court'] as bool, long: m['sig${n}_long'] as bool),
          },
        );
        final surcharges = <int, Map<String, String>>{
          for (final e in (c['surcharges'] as Map<String, Object?>).entries)
            int.parse(e.key.substring(3)): {for (final x in (e.value as Map).entries) x.key as String: x.value as String},
        };
        final requis = reglage.requis(debut: debut, fin: fin, aujourdhui: aujourdhui, surcharges: surcharges);

        return <String, Object?>{
          'palier': ReglageSignature.palier(debut, fin, reglage.seuilMois, aujourdhui),
          'positions': [for (final s in requis) s.position],
          'noms': [for (final s in requis) s.nom],
          'duree': AttestationsRepository.formatDuree(debut, fin, aujourdhui: aujourdhui),
          'deDuree': AttestationsRepository.deDuree(debut, fin, aujourdhui: aujourdhui),
          'debutLongue': debut == null ? '' : AttestationsRepository.dateLongue(debut),
        };
      }(),
  ];

  test('⚠️⚠️ même palier, mêmes signataires, même durée en lettres, même date longue : le serveur et le poste', () {
    final attendu = (executerPhp(_script, cas, application: true) as List).cast<Map>();
    final obtenu = local();

    expect(attendu, hasLength(cas.length));
    // Le jeu doit réellement produire les deux paliers.
    expect({for (final l in attendu) l['palier']}, {'court', 'long'});

    for (var i = 0; i < cas.length; i++) {
      expect(
        {for (final k in obtenu[i].keys) k: obtenu[i][k]},
        {for (final k in obtenu[i].keys) k: attendu[i][k]},
        reason: 'cas $i : ${cas[i]['debut']} → ${cas[i]['fin']}',
      );
    }
  }, skip: saut);
}
