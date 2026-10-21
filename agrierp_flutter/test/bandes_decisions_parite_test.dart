import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/bandes_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Décisions du client du 21/10/2026 sur « Bandes & Sujets » (BS-Q3, BS-Q4, BS-Q7) — PARITÉ EXÉCUTÉE.
///
/// Le VRAI composant `GestionBandes` (via `SaisieBandeAction`) est exécuté sur SQLite en mémoire et rend les messages
/// de refus ; le poste (`BandesRepository`) doit produire les MÊMES, mot pour mot, sur le même jeu. Sans PHP ni dépôt
/// Laravel, le test se SAUTE avec sa raison.
void main() {
  final saut = sautSansPhp();
  const lapins = 'aaaaaaaa-0000-4000-8000-0000000000a1';
  String uuid(String g) => g.padRight(36, '0');

  test('⚠️⚠️ refus d archivage (singulier, pluriel), refus de correction avec fiches, refus de restauration : les messages du web', () async {
    final web = executerPhp('<?php\n$amorceApplication\n$_script', {'espece': lapins}, application: true) as Map<String, dynamic>;

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: lapins, code: 'cuniculture', label: 'Cuniculture'));
    final depot = BandesRepository(database: db, deviceId: 'poste-test', horloge: () => DateTime(2026, 10, 21, 10));

    Future<void> bande(String id, String code, int courant, {bool active = true}) => db.into(db.livestockLots).insert(
      LivestockLotsCompanion.insert(
        id: id,
        code: code,
        speciesId: lapins,
        speciesCode: const Value('cuniculture'),
        stage: const Value('reproduction'),
        initialQuantity: const Value(300),
        currentQuantity: Value(courant),
        createdDate: Value(DateTime(2026, 9, 1)),
        status: const Value('actif'),
        isActive: Value(active),
      ),
    );

    Future<String?> refus(Future<Object?> Function() geste, String champ) async {
      try {
        await geste();
      } on BandeRefusee catch (e) {
        return e.erreurs[champ];
      }
      return null;
    }

    final poste = <String, Object?>{};
    for (final n in [1, 2, 200]) {
      await bande(uuid('a${n}z'), 'LOT-A$n', n);
      poste['archivage_$n'] = await refus(() => depot.archiver(uuid('a${n}z')), 'bande');
    }
    await bande(uuid('f1'), 'LOT-F', 40);
    await db.into(db.livestockDailyEntries).insert(
      LivestockDailyEntriesCompanion.insert(
        id: uuid('fi1'), deviceId: 'serveur', updatedAt: DateTime(2026, 10, 20), lotId: uuid('f1'), entryDate: DateTime(2026, 10, 20),
      ),
    );
    poste['correction_avec_fiches'] = await refus(() => depot.modifier(uuid('f1'), stage: 'reproduction', quantite: '12', status: 'actif'), 'quantity');
    await bande(uuid('r1'), 'LOT-R', 0, active: false);
    await bande(uuid('r2'), 'lot-r', 4);
    poste['restauration_code_pris'] = await refus(() => depot.restaurer(uuid('r1')), 'bande');
    poste['infobulle'] = BandesRepository.infobulleEffectifParLesFiches;

    expect(poste, web);
  }, skip: saut);
}

const _script = r'''
use App\Actions\SaisieBandeAction;
use App\Livewire\Elevage\GestionBandes;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\User;
use Livewire\Livewire;

set_exception_handler(function (Throwable $t) {
    fwrite(STDERR, get_class($t).' : '.$t->getMessage().' @ '.$t->getFile().':'.$t->getLine());
    exit(2);
});
$e = json_decode(file_get_contents($argv[1]), true);
Carbon\Carbon::setTestNow(Carbon\Carbon::parse('2026-10-21 10:00:00', config('app.timezone')));
Artisan::call('db:seed', ['--class' => 'RolesAndPermissionsSeeder', '--force' => true]);
$u = User::create(['name' => 'a', 'username' => 'a', 'email' => 'a@a.bj', 'password' => bcrypt('x'), 'is_active' => true]);
$u->assignRole('admin');
auth()->login($u);
(new LivestockSpecies())->forceFill(['id' => $e['espece'], 'code' => 'cuniculture', 'label' => 'Cuniculture', 'is_enabled' => true])->save();

$pad = fn (string $g) => str_pad($g, 36, '0');
$cree = function (string $id, string $code, int $courant, bool $actif = true) use ($e, $pad) {
    (new LivestockLot())->forceFill([
        'id' => $pad($id), 'code' => $code, 'species_id' => $e['espece'], 'stage' => 'reproduction', 'initial_quantity' => 300,
        'current_quantity' => $courant, 'created_date' => '2026-09-01', 'status' => 'actif', 'is_active' => $actif,
    ])->save();
};
$toast = function ($composant) {
    foreach (array_reverse($composant->effects['dispatches'] ?? []) as $d) {
        if (($d['name'] ?? '') === 'toast') {
            return $d['params']['message'] ?? null;
        }
    }

    return null;
};

$sortie = [];
foreach ([1, 2, 200] as $n) {
    $cree('a'.$n.'z', 'LOT-A'.$n, $n);
    $sortie['archivage_'.$n] = $toast(Livewire::test(GestionBandes::class)->call('archiveLot', $pad('a'.$n.'z')));
}
$cree('f1', 'LOT-F', 40);
(new LivestockDailyEntry())->forceFill(['id' => $pad('fi1'), 'lot_id' => $pad('f1'), 'entry_date' => '2026-10-20', 'achat' => 0, 'ne' => 0, 'mort' => 0, 'vente' => 0, 'don' => 0, 'effectif_final' => 40])->save();
$t = Livewire::test(GestionBandes::class)->call('editLot', $pad('f1'))->set('quantity', 12)->call('updateLot');
$sortie['correction_avec_fiches'] = $toast($t);
$cree('r1', 'LOT-R', 0, false);
$cree('r2', 'lot-r', 4);
$sortie['restauration_code_pris'] = $toast(Livewire::test(GestionBandes::class)->call('restoreLot', $pad('r1')));
$sortie['infobulle'] = SaisieBandeAction::INFOBULLE_EFFECTIF_PAR_LES_FICHES;

echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
''';
