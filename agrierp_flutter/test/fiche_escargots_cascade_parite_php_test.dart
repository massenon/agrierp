import 'package:agrierp/core/comptabilite/exercice_de_saisie.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket 3.F5 / A1-bis — LA CASCADE DE LA FICHE ESCARGOTS : le poste = le vrai `FicheEscargots::saveDay` du web.
///
/// Le web (`FicheEscargots` : `loadDay`, champs, `saveDay`, puis `RecordSaleOnFicheElevageAction::recalculerEnCascade`,
/// module `helico` activé, exercice clos refusé) et le poste (`FicheJournaliereRepository.enregistrer` + sa cascade)
/// reçoivent les MÊMES suites de saisies — jours dans le désordre (une fiche ANTÉRIEURE à la dernière doit recalculer les
/// suivantes), naissains, achats, morts et dons par catégorie, ventes de la caisse, œufs, effectifs saisis, pesées,
/// jours d'un exercice clos — et doivent aboutir aux mêmes veille, effectif du jour, taux de mortalité, fiches écrites
/// (toute la chaîne) et effectif de la bande. Les Reproducteurs (volailles) ont leur parité exécutée en VOL-1
/// (`volailles_effectif_test.dart`) : non refaite ici.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  const lotId = '11111111-1111-1111-1111-111111111111';
  const especeId = '22222222-2222-2222-2222-222222222222';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
  });
  tearDown(() async => db.close());

  String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Jeux : `(graine, effectif initial, nombre de saisies)`. Plusieurs centaines de saisies au total.
  final jeux = [for (var g = 0; g < 16; g++) (g * 37 + 5, 30 + (g * 53) % 400, 14 + g % 9)];

  List<Map<String, Object?>> saisies(int graine, int nombre) {
    var s = graine;
    int h(int n) => (s = (s * 1103515245 + 12345) & 0x7fffffff) % n;
    return [
      for (var i = 0; i < nombre; i++)
        () {
          // Dans le désordre, de décembre 2025 (exercice 2025 CLOS) à octobre 2026.
          final jour = DateTime(2025, 12, 20).add(Duration(days: h(310)));
          final repartir = h(3) != 0;
          return {
            'jour': ymd(jour),
            'achat': h(4) == 0 ? h(30) : 0,
            'ne': h(3) == 0 ? h(80) : 0,
            'oeufs': h(3) == 0 ? h(50) : 0,
            'morts': repartir && h(2) == 0 ? [h(6), h(5), h(4)] : [0, 0, 0],
            'dons': repartir && h(4) == 0 ? [h(3), h(3), h(2)] : [0, 0, 0],
            'eff': [h(200), h(200), h(60)],
            'pesee': h(3) == 0 ? null : 500 + h(9000),
            'vente_avant': h(5) == 0 ? 1 + h(12) : null,
          };
        }(),
    ];
  }

  test(
    'parité exécutée : suites de saisies de la fiche Escargots, cascade comprise, web = poste',
    () async {
      var comparees = 0;
      var refusees = 0;
      for (final (graine, initial, nombre) in jeux) {
        final ops = saisies(graine, nombre);
        final php =
            executerPhp(
                  '<?php\n$amorceApplication\n$_scriptPhp',
                  {'espece': especeId, 'lot': lotId, 'initial': initial, 'ops': ops},
                  application: true,
                )
                as List;

        await db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(
            id: '33333333-3333-3333-3333-333333333333',
            year: 2025,
            startDate: Value(DateTime(2025)),
            endDate: Value(DateTime(2025, 12, 31)),
            status: const Value('cloture'),
          ),
        );
        await db.into(db.livestockLots).insert(
          LivestockLotsCompanion.insert(
            id: lotId,
            code: 'ESC-A',
            speciesId: especeId,
            speciesCode: const Value('helico'),
            stage: const Value('engraissement'),
            initialQuantity: Value(initial),
            currentQuantity: Value(initial),
          ),
        );

        for (var i = 0; i < ops.length; i++) {
          final o = ops[i];
          final p = php[i] as Map<String, dynamic>;
          final jour = DateTime.parse(o['jour']! as String);
          final raison = 'jeu $graine, saisie $i (${o['jour']})';

          // Ventes posées AVANT par la caisse (le formulaire ne les écrit jamais).
          final venteAvant = o['vente_avant'] as int?;
          if (venteAvant != null) {
            final existante = await depot.chargerJour(lotId, jour);
            if (existante != null) {
              await (db.update(db.livestockDailyEntries)..where((t) => t.id.equals(existante.id))).write(
                LivestockDailyEntriesCompanion(vente: Value(venteAvant)),
              );
            } else {
              await db.into(db.livestockDailyEntries).insert(
                LivestockDailyEntriesCompanion.insert(
                  id: '99999999-0000-0000-0000-${i.toString().padLeft(12, '0')}',
                  deviceId: 'serveur',
                  updatedAt: jour,
                  lotId: lotId,
                  entryDate: jour,
                  vente: Value(venteAvant),
                ),
              );
            }
          }

          // Ce que l'écran calcule avant d'enregistrer (miroir de `getEffectifFinalCalcProperty` & co).
          final existante = await depot.chargerJour(lotId, jour);
          final morts = (o['morts']! as List).cast<int>();
          final dons = (o['dons']! as List).cast<int>();
          final totalMorts = morts.fold(0, (a, b) => a + b) > 0 ? morts.fold(0, (a, b) => a + b) : ((existante?.mort ?? 0) > 0 ? existante!.mort : 0);
          final totalDons = dons.fold(0, (a, b) => a + b) > 0 ? dons.fold(0, (a, b) => a + b) : ((existante?.don ?? 0) > 0 ? existante!.don : 0);
          final precedent = await depot.effectifPrecedent(lotId, jour);
          final effectifFinal = FicheJournaliereRepository.calculerEffectifFinal(
            effectifPrecedent: precedent,
            achat: o['achat']! as int,
            ne: o['ne']! as int,
            mort: totalMorts,
            vente: existante?.vente ?? 0,
            don: totalDons,
          ).clamp(0, 1 << 30);
          expect(precedent, p['precedent'], reason: 'veille — $raison');
          expect(effectifFinal, p['final'], reason: 'effectif du jour — $raison');
          expect(precedent > 0 ? ((totalMorts / precedent * 1000).round() / 10) : 0.0, (p['taux'] as num).toDouble(), reason: 'taux de mortalité — $raison');

          var refus = false;
          try {
            final eff = o['eff']! as List;
            await depot.enregistrer(
              lotId: lotId,
              jour: jour,
              achat: o['achat']! as int,
              ne: o['ne']! as int,
              mort: totalMorts,
              don: totalDons,
              ponteTotal: o['oeufs']! as int,
              poidsMoyen: FicheJournaliereRepository.poidsMoyen(
                poidsTotalG: ((o['pesee'] as int?) ?? 0).toDouble(),
                tailleEchantillon: effectifFinal,
              ),
              effectifs: EffectifsSaisis(m: eff[0] as int, f: eff[1] as int, sevres: eff[2] as int),
            );
          } on RefusExercice {
            refus = true;
            refusees++;
          }
          expect(refus, p['refus'], reason: 'refus d\'exercice clos — $raison');

          final fiches = await (db.select(db.livestockDailyEntries)..orderBy([(t) => OrderingTerm(expression: t.entryDate)])).get();
          expect(
            [
              for (final f in fiches)
                [ymd(f.entryDate), f.achat, f.ne, f.mort, f.vente, f.don, f.effectifFinal, f.ponteTotal, f.effectifM, f.effectifF, f.effectifSevres, f.weightSampleAvgG?.round()],
            ],
            [
              for (final f in p['fiches'] as List)
                [for (final c in f as List) c is num && c is! int ? c.round() : c],
            ],
            reason: 'chaîne des fiches — $raison',
          );
          final bande = await (db.select(db.livestockLots)..where((t) => t.id.equals(lotId))).getSingle();
          expect(bande.currentQuantity, p['bande'], reason: 'effectif de la bande — $raison');
          comparees++;
        }
        await db.delete(db.livestockDailyEntries).go();
        await db.delete(db.livestockLots).go();
        await db.delete(db.fiscalYears).go();
      }
      expect(comparees, greaterThan(200));
      expect(refusees, greaterThan(5), reason: 'la grille doit viser l\'exercice clos');
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

const _scriptPhp = r'''
Carbon\Carbon::setTestNow('2026-10-20 10:00:00');
$entree = json_decode(file_get_contents($argv[1]), true);
Illuminate\Support\Facades\Artisan::call('db:seed', ['--class' => Database\Seeders\RolesAndPermissionsSeeder::class, '--force' => true]);
$u = App\Models\User::create(['name' => 'Animalier', 'username' => 'animalier-3f5', 'email' => 'a3f5@fermeolouwachegoun.com',
    'password' => bcrypt('LogiAgriERP@2026'), 'is_active' => true]);
$u->assignRole('admin');
Illuminate\Support\Facades\Auth::login($u);
App\Models\ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => true]);
$espece = new App\Models\LivestockSpecies(['code' => 'helico', 'label' => 'helico', 'is_enabled' => true]);
$espece->id = $entree['espece'];
$espece->save();
$lot = new App\Models\LivestockLot([
    'code' => 'ESC-A', 'species_id' => $espece->id, 'stage' => 'engraissement', 'initial_quantity' => $entree['initial'],
    'current_quantity' => $entree['initial'], 'created_date' => '2025-01-05', 'status' => 'actif', 'is_active' => true,
]);
$lot->id = $entree['lot'];
$lot->save();
$f = new App\Models\FiscalYear();
$f->forceFill(['year' => 2025, 'start_date' => '2025-01-01', 'end_date' => '2025-12-31', 'status' => 'cloture'])->save();
try {
$t = Livewire\Livewire::test(App\Livewire\Elevage\FicheEscargots::class)->set('bandeId', $lot->id);
$sortie = [];
foreach ($entree['ops'] as $o) {
    if ($o['vente_avant'] !== null) {
        $e = App\Models\LivestockDailyEntry::where('lot_id', $lot->id)->whereDate('entry_date', $o['jour'])->first();
        if ($e) {
            $e->vente = $o['vente_avant'];
            $e->save();
        } else {
            $e = new App\Models\LivestockDailyEntry(['lot_id' => $lot->id, 'entry_date' => $o['jour'], 'vente' => $o['vente_avant'], 'effectif_final' => 0]);
            $e->save();
        }
    }
    $t->call('loadDay', $o['jour'])
        ->set('achat', $o['achat'])->set('naissainsNes', $o['ne'])->set('oeufsTerre', $o['oeufs'])
        ->set('mortBorde', $o['morts'][0])->set('mortEngraissement', $o['morts'][1])->set('mortNaissain', $o['morts'][2])
        ->set('donBorde', $o['dons'][0])->set('donEngraissement', $o['dons'][1])->set('donNaissain', $o['dons'][2])
        ->set('effectifNaissains', $o['eff'][0])->set('effectifEngraissement', $o['eff'][1])->set('effectifBordes', $o['eff'][2])
        ->set('peseeTotal', $o['pesee']);
    $i = $t->instance();
    $avant = ['precedent' => $i->previousEffectif, 'final' => $i->effectifFinalCalc, 'taux' => $i->mortalityRateCalc];
    $refus = app(App\Services\AccountingEntryService::class)->refusExerciceClos($o['jour']) !== null;
    $t->call('saveDay');
    $fiches = [];
    foreach (App\Models\LivestockDailyEntry::where('lot_id', $lot->id)->orderBy('entry_date')->get() as $x) {
        $fiches[] = [$x->entry_date->format('Y-m-d'), (int) $x->achat, (int) $x->ne, (int) $x->mort, (int) $x->vente, (int) $x->don,
            (int) $x->effectif_final, $x->ponte_total === null ? null : (int) $x->ponte_total,
            $x->effectif_m === null ? null : (int) $x->effectif_m, $x->effectif_f === null ? null : (int) $x->effectif_f,
            $x->effectif_sevres === null ? null : (int) $x->effectif_sevres,
            $x->weight_sample_avg_g === null ? null : (int) $x->weight_sample_avg_g];
    }
    $sortie[] = $avant + ['refus' => $refus, 'fiches' => $fiches, 'bande' => (int) App\Models\LivestockLot::find($lot->id)->current_quantity];
}
echo json_encode($sortie);
} catch (Throwable $e) { fwrite(STDERR, get_class($e).': '.$e->getMessage()); exit(9); }
''';
