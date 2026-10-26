import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/rappels_du_jour_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket POP4 — PARITÉ EXÉCUTÉE : le VRAI `App\Services\RappelsDuJourService` du serveur et le calcul LOCAL du poste
/// reçoivent le même jeu et doivent rendre exactement les mêmes lignes, dans le même ordre (urgence, type, bande, espèce,
/// libellé, produit, jour prévu, écart, échéance).
///
/// Rien n'est recopié : le jeu est une donnée JSON semée des deux côtés (SQLite en mémoire côté PHP, Drift en mémoire
/// côté poste). Jour fixé au 14/10/2026. Sans PHP ni dépôt Laravel, les tests sont SAUTÉS AVEC LEUR RAISON.
const _script = r'''<?php
use Illuminate\Support\Carbon;
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
Carbon::setTestNow('2026-10-14 10:00:00');
foreach ($in['especes'] as $e) {
    App\Models\LivestockSpecies::create(['code' => $e['code'], 'label' => $e['label'], 'is_enabled' => true]);
    App\Models\ModuleConfig::create(['species_code' => $e['code'], 'is_enabled' => $e['actif']]);
}
$lots = [];
foreach ($in['bandes'] as $b) {
    $lots[$b['code']] = App\Models\LivestockLot::create([
        'code' => $b['code'], 'species_id' => App\Models\LivestockSpecies::where('code', $b['espece'])->value('id'),
        'stage' => 'croissance', 'initial_quantity' => 100, 'current_quantity' => 100,
        'created_date' => $b['miseEnLot'], 'status' => $b['statut'], 'is_active' => true,
    ]);
}
foreach ($in['soins'] as $s) {
    App\Models\VeterinaryCalendarEvent::create(['lot_id' => $lots[$s['bande']]->id, 'task_type' => $s['tache'], 'scheduled_date' => $s['date'], 'status' => $s['statut']]);
}
foreach ($in['bareme'] as $s) {
    App\Models\ProphylaxisScheduleStandard::create(['species_code' => $s['espece'], 'period_label' => 'J'.$s['jour'], 'cycle_day_start' => $s['jour'],
        'cycle_day_end' => $s['jour'], 'treatment' => $s['traitement'], 'product_recommended' => $s['produit'], 'dosage' => '-', 'withdrawal_days' => 0, 'is_active' => $s['actif']]);
}
foreach ($in['administres'] as $a) {
    App\Models\VeterinaryRecord::create(['lot_id' => $lots[$a['bande']]->id, 'action_type' => $a['traitement'], 'record_date' => $a['date'], 'is_active' => true]);
}
foreach ($in['remanences'] as $r) {
    App\Models\VeterinaryWithdrawalPeriod::create(['lot_id' => $lots[$r['bande']]->id, 'product_used' => $r['produit'], 'start_date' => '2026-10-01',
        'withdrawal_days' => 1, 'end_date' => $r['fin']]);
}
if ($in['delai'] !== null) {
    App\Models\CompanySetting::current()->update(['rappel_soins_jours' => $in['delai']]);
}
echo json_encode(app(App\Services\RappelsDuJourService::class)->calculer());
''';

Map<String, Object?> _jeu({int? delai}) => {
  'delai': delai,
  'especes': [
    {'code': 'cuniculture', 'label': 'Lapins', 'actif': true},
    {'code': 'aviculture', 'label': 'Volailles', 'actif': true},
    {'code': 'porciculture', 'label': 'Porcs', 'actif': false},
  ],
  'bandes': [
    {'code': 'LAP-A', 'espece': 'cuniculture', 'miseEnLot': '2026-10-10', 'statut': 'actif'},
    {'code': 'LAP-B', 'espece': 'cuniculture', 'miseEnLot': '2026-10-12', 'statut': 'actif'},
    {'code': 'LAP-X', 'espece': 'cuniculture', 'miseEnLot': '2026-09-01', 'statut': 'cloture'},
    {'code': 'AVI-A', 'espece': 'aviculture', 'miseEnLot': '2026-10-01', 'statut': 'actif'},
    {'code': 'POR-A', 'espece': 'porciculture', 'miseEnLot': '2026-10-01', 'statut': 'actif'},
  ],
  'soins': [
    {'bande': 'LAP-A', 'tache': 'Vaccin Newcastle', 'date': '2026-10-12', 'statut': 'planned'},
    {'bande': 'LAP-A', 'tache': 'Déparasitage', 'date': '2026-10-14', 'statut': 'planned'},
    {'bande': 'LAP-A', 'tache': 'Vitamines', 'date': '2026-10-17', 'statut': 'planned'},
    {'bande': 'LAP-A', 'tache': 'Trop tard', 'date': '2026-10-18', 'statut': 'planned'},
    {'bande': 'LAP-A', 'tache': 'Réalisé', 'date': '2026-10-14', 'statut': 'done'},
    {'bande': 'AVI-A', 'tache': 'Contrôle sanitaire', 'date': '2026-10-14', 'statut': 'planned'},
    {'bande': 'AVI-A', 'tache': 'Retard ancien', 'date': '2026-10-01', 'statut': 'planned'},
    {'bande': 'LAP-X', 'tache': 'Bande close', 'date': '2026-10-14', 'statut': 'planned'},
    {'bande': 'POR-A', 'tache': 'Espèce désactivée', 'date': '2026-10-14', 'statut': 'planned'},
  ],
  'bareme': [
    {'espece': 'cuniculture', 'traitement': 'Vermifuge', 'jour': 5, 'produit': 'Ivomec', 'actif': true},
    {'espece': 'cuniculture', 'traitement': 'Vaccin VHD', 'jour': 6, 'produit': 'Filavac', 'actif': true},
    {'espece': 'cuniculture', 'traitement': 'Archivé', 'jour': 7, 'produit': 'Y', 'actif': false},
    {'espece': 'cuniculture', 'traitement': 'Hors horizon', 'jour': 9, 'produit': 'X', 'actif': true},
    {'espece': 'cuniculture', 'traitement': 'Anti-stress', 'jour': 3, 'produit': 'Amin', 'actif': true},
  ],
  'administres': [
    {'bande': 'LAP-B', 'traitement': 'Anti-stress', 'date': '2026-10-14'},
  ],
  'remanences': [
    {'bande': 'LAP-A', 'produit': 'Ivermectine', 'fin': '2026-10-14'},
    {'bande': 'LAP-A', 'produit': 'Oxytétracycline', 'fin': '2026-10-17'},
    {'bande': 'AVI-A', 'produit': 'Trop loin', 'fin': '2026-10-24'},
    {'bande': 'AVI-A', 'produit': 'Terminée', 'fin': '2026-09-08'},
  ],
};

DateTime _d(String s) => DateTime.parse(s);

void main() {
  final saut = sautSansPhp();
  var n = 0;
  String id(String p) => '$p${(++n).toString().padLeft(4, '0')}-1111-4111-8111-111111111111';

  Future<List<Map<String, Object?>>> calculLocal(Map<String, Object?> jeu) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    for (final e in (jeu['especes'] as List).cast<Map>()) {
      await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: id('eeee'), code: e['code'] as String, label: e['label'] as String));
      await db.into(db.modulesConfig).insert(ModulesConfigCompanion.insert(id: id('ffff'), speciesCode: e['code'] as String, isEnabled: Value(e['actif'] as bool)));
    }
    final lots = <String, String>{};
    final especes = <String, String>{};
    for (final b in (jeu['bandes'] as List).cast<Map>()) {
      final lotId = lots[b['code'] as String] = id('aaaa');
      especes[b['code'] as String] = b['espece'] as String;
      await db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: lotId,
          code: b['code'] as String,
          speciesId: 'esp-${b['espece']}',
          speciesCode: Value(b['espece'] as String),
          stage: const Value('croissance'),
          createdDate: Value(_d(b['miseEnLot'] as String)),
          initialQuantity: const Value(100),
          currentQuantity: const Value(100),
          status: Value(b['statut'] as String),
          isActive: const Value(true),
        ),
      );
    }
    for (final s in (jeu['soins'] as List).cast<Map>()) {
      await db.into(db.veterinaryCalendarEvents).insert(
        VeterinaryCalendarEventsCompanion.insert(
          id: id('bbbb'), deviceId: 'poste-test', updatedAt: DateTime(2026, 10, 14),
          lotId: lots[s['bande']]!, taskType: s['tache'] as String, scheduledDate: _d(s['date'] as String), status: Value(s['statut'] as String),
        ),
      );
    }
    for (final s in (jeu['bareme'] as List).cast<Map>()) {
      await db.into(db.prophylaxisScheduleStandards).insert(
        ProphylaxisScheduleStandardsCompanion.insert(
          id: id('5555'), speciesCode: s['espece'] as String, periodLabel: 'J${s['jour']}',
          cycleDayStart: Value(s['jour'] as int), cycleDayEnd: Value(s['jour'] as int),
          treatment: s['traitement'] as String, productRecommended: Value(s['produit'] as String), isActive: Value(s['actif'] as bool),
        ),
      );
    }
    for (final a in (jeu['administres'] as List).cast<Map>()) {
      await db.into(db.veterinaryRecords).insert(
        VeterinaryRecordsCompanion.insert(
          id: id('dddd'), deviceId: 'poste-test', updatedAt: DateTime(2026, 10, 14), lotId: lots[a['bande']]!,
          actionType: a['traitement'] as String, recordDate: _d(a['date'] as String),
        ),
      );
    }
    for (final r in (jeu['remanences'] as List).cast<Map>()) {
      await db.into(db.veterinaryWithdrawalPeriods).insert(
        VeterinaryWithdrawalPeriodsCompanion.insert(id: id('cccc'), lotId: lots[r['bande']]!, productUsed: Value(r['produit'] as String), endDate: _d(r['fin'] as String)),
      );
    }
    if (jeu['delai'] != null) {
      await db.into(db.companySettings).insert(CompanySettingsCompanion.insert(id: const Value('unique'), rappelSoinsJours: Value(jeu['delai'] as int)));
    }

    final depot = RappelsDuJourRepository(database: db, soins: SoinsRepository(database: db, deviceId: 'poste-test'));
    final r = await depot.calculer(quand: DateTime(2026, 10, 14, 10));
    return [
      for (final l in r.lignes)
        {
          'urgence': switch (l.urgence) {
            UrgenceRappel.retard => 'retard',
            UrgenceRappel.aujourdhui => 'aujourdhui',
            UrgenceRappel.avenir => 'avenir',
          },
          'type': l.type.name,
          'bande': l.bande,
          'espece': l.espece,
          'libelle': l.libelle,
          'produit': l.produit,
          'date': l.cleJour,
          'jours': l.jours,
          'echeance': l.echeance,
        },
    ];
  }

  List<Map<String, Object?>> serveur(Map<String, Object?> jeu) => [
    for (final l in (executerPhp(_script, jeu, application: true) as List).cast<Map>())
      {
        for (final k in ['urgence', 'type', 'bande', 'espece', 'libelle', 'produit', 'date', 'jours', 'echeance']) k: l[k],
      },
  ];

  test('même jeu, mêmes lignes, même ordre : le serveur et le poste (délai par défaut, 3 jours)', () async {
    final jeu = _jeu();
    final attendu = serveur(jeu);
    expect(attendu.length, greaterThanOrEqualTo(8), reason: 'le jeu doit réellement produire des rappels de chaque source');
    expect({for (final l in attendu) l['type']}, {'soin', 'prophylaxie', 'remanence'});
    expect({for (final l in attendu) l['urgence']}, {'retard', 'aujourdhui', 'avenir'});
    expect(await calculLocal(jeu), attendu);
  }, skip: saut);

  test('même jeu avec un délai réglé à 5 jours', () async {
    final jeu = _jeu(delai: 5);
    expect(await calculLocal(jeu), serveur(jeu));
  }, skip: saut);

  test('même jeu avec un délai réglé à 0 jour (le jour même seulement)', () async {
    final jeu = _jeu(delai: 0);
    final attendu = serveur(jeu);
    expect(attendu.every((l) => (l['jours'] as int) <= 0), isTrue);
    expect(await calculLocal(jeu), attendu);
  }, skip: saut);
}
