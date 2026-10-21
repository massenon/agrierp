import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/reproducteurs_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket BS3 — PARITÉ EXÉCUTÉE du « Registre des Reproducteurs » : le VRAI composant `RegistreReproducteurs` du web
/// rend, sur un jeu tiré au hasard (graine fixe), ce que le poste calcule — indicateurs, ordre et filtres du tableau,
/// bandes proposées — et les MESSAGES de validation de chaque saisie invalide, mot pour mot (enregistrement et sortie).
///
/// ⚠️ Un doublon d'identifiant ne différant que par la CASSE n'est pas comparé : l'unicité est celle de la base — la collation
/// `utf8mb4_unicode_ci` de MySQL (production) les confond, le SQLite en mémoire de ce test non. Le poste suit MySQL
/// (`cleCommeLeServeur`), prouvé dans `reproducteurs_poste_test.dart`.
///
/// Rien n'est recopié : le test envoie son jeu en JSON, le PHP du dépôt Laravel l'exécute, le test compare. Sans PHP ni
/// dépôt Laravel, il se SAUTE avec sa raison.
void main() {
  final saut = sautSansPhp();

  test('⚠️⚠️ BS3 — indicateurs, tableau, filtres, bandes proposées et messages de validation : ceux du web exécuté', () async {
    final hasard = Random(2111);
    String uuid() => [
      for (final n in [8, 4, 4, 4, 12]) List.generate(n, (_) => '0123456789abcdef'[hasard.nextInt(16)]).join(),
    ].join('-');
    String jour(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    // Les trois premières : modules ACTIFS (servies au poste). La quatrième : module ÉTEINT (BS-Q12) — ni le web ni le
    // tirage ne la proposent ; un sujet qui la porte garde pourtant son espèce.
    final especes = [
      {'id': uuid(), 'code': 'cuniculture', 'label': 'Lapins'},
      {'id': uuid(), 'code': 'aviculture', 'label': 'Volailles'},
      {'id': uuid(), 'code': 'porciculture', 'label': 'Porcs'},
    ];
    final eteinte = {'id': uuid(), 'code': 'helico', 'label': 'Escargots'};
    final lots = <Map<String, dynamic>>[];
    for (var i = 0; i < 9; i++) {
      final e = especes[hasard.nextInt(3)];
      lots.add({
        'id': uuid(),
        'code': 'LOT-${e['code'].toString().substring(0, 3).toUpperCase()}-${i + 1}',
        'espece': e['id'],
        'statut': hasard.nextInt(4) == 0 ? 'cloture' : 'actif',
        'actif': hasard.nextInt(6) != 0,
      });
    }
    const races = ['Néo-Zélandais Blanc', 'Californien', 'Sussex', 'Large White', 'Fauve de Bourgogne', null];
    final sujets = <Map<String, dynamic>>[];
    final identifiants = <String>{};
    for (var i = 0; i < 22; i++) {
      var identifiant = '';
      do {
        identifiant = '${['LAP', 'POU', 'POR'][hasard.nextInt(3)]}-2026-${(1 + hasard.nextInt(60)).toString().padLeft(4, '0')}';
      } while (!identifiants.add(identifiant));
      final e = especes[hasard.nextInt(3)];
      final statut = ['actif', 'actif', 'actif', 'reforme', 'vendu', 'mort'][hasard.nextInt(6)];
      sujets.add({
        'id': uuid(),
        'identifiant': identifiant,
        'espece': e['id'],
        'lot': hasard.nextBool() ? lots[hasard.nextInt(lots.length)]['id'] : null,
        'categorie': hasard.nextInt(8) == 0 ? 'engraissement' : 'reproducteur',
        'sexe': hasard.nextBool() ? 'F' : 'M',
        'race': races[hasard.nextInt(races.length)],
        'cage': hasard.nextBool() ? 'C${hasard.nextInt(30)}' : null,
        'statut': statut,
        'actif': hasard.nextInt(9) != 0,
        'entree': jour(DateTime(2026, 1, 1).add(Duration(days: hasard.nextInt(250)))),
      });
    }

    // Un sujet de l'espèce au module éteint : il figure au tableau (son espèce se lit), pas dans les filtres.
    final sujetEteint = {
      'id': uuid(),
      'identifiant': 'ESC-2026-0001',
      'espece': eteinte['id'],
      'lot': null,
      'categorie': 'reproducteur',
      'sexe': 'F',
      'race': null,
      'cage': null,
      'statut': 'actif',
      'actif': true,
      'entree': '2026-03-01',
    };

    final entree = {
      'maintenant': '2026-10-21 10:30:00',
      'especes': [...especes, eteinte],
      'modules_actifs': [for (final e in especes) e['code']],
      'lots': lots,
      'sujets': [...sujets, sujetEteint],
    };
    final web = executerPhp('<?php\n$amorceApplication\n$_script', entree, application: true) as Map<String, dynamic>;

    // ── Le même jeu dans la base du poste ────────────────────────────────────────────────────────────────────────
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    for (final e in especes) {
      await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: e['id']!, code: e['code']!, label: e['label']!));
    }
    for (final l in lots) {
      final e = especes.firstWhere((x) => x['id'] == l['espece']);
      await db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: l['id'] as String,
          code: l['code'] as String,
          speciesId: l['espece'] as String,
          speciesCode: Value(e['code']),
          stage: const Value('reproduction'),
          initialQuantity: const Value(10),
          currentQuantity: const Value(10),
          createdDate: Value(DateTime(2026, 2, 1)),
          status: Value(l['statut'] as String),
          isActive: Value(l['actif'] as bool),
        ),
      );
    }
    for (final s in [...sujets, sujetEteint]) {
      final e = [...especes, eteinte].firstWhere((x) => x['id'] == s['espece']);
      final lot = lots.where((l) => l['id'] == s['lot']).firstOrNull;
      final d = (s['entree'] as String).split('-').map(int.parse).toList();
      await db.into(db.animals).insert(
        AnimalsCompanion.insert(
          id: s['id'] as String,
          identifier: s['identifiant'] as String,
          speciesId: Value(e['id']),
          speciesLabel: Value(e['label']),
          lotId: Value(lot?['id'] as String?),
          lotCode: Value(lot?['code'] as String?),
          category: Value(s['categorie'] as String),
          sex: Value(s['sexe'] as String),
          breed: Value(s['race'] as String?),
          cage: Value(s['cage'] as String?),
          entryDate: Value(DateTime(d[0], d[1], d[2])),
          status: Value(s['statut'] as String),
          isActive: Value(s['actif'] as bool),
        ),
      );
    }
    final depot = ReproducteursRepository(database: db, deviceId: 'poste-test', horloge: () => DateTime(2026, 10, 21, 10, 30));

    // Indicateurs.
    final k = await depot.indicateurs();
    expect([k.total, k.presents, k.femelles, k.males], [web['kpis']['total'], web['kpis']['presents'], web['kpis']['femelles'], web['kpis']['males']]);

    // Tableau : ordre et filtres.
    Future<List<String>> codes({String recherche = '', String espece = '', String statut = ''}) async => [
      for (final l in await depot.reproducteurs(recherche: recherche, speciesId: espece, statut: statut)) l.animal.identifier,
    ];
    expect(await codes(), web['tous'], reason: 'ordre et contenu du tableau');
    for (final r in ['lap', 'POU', 'blanc', 'sussex', 'zz']) {
      expect(await codes(recherche: r), web['recherches'][r], reason: 'recherche « $r »');
    }
    for (final e in especes) {
      expect(await codes(espece: e['id']!), web['especes'][e['id']], reason: 'filtre espèce ${e['label']}');
    }
    for (final st in ['actif', 'reforme', 'vendu', 'mort']) {
      expect(await codes(statut: st), web['statuts'][st], reason: 'filtre statut $st');
    }
    expect(await codes(recherche: 'a', espece: especes[0]['id']!, statut: 'actif'), web['combine']);

    // Colonnes affichées : espèce, bande, sexe.
    final lignes = {for (final l in await depot.reproducteurs()) l.animal.identifier: l};
    for (final MapEntry(:key, :value) in (web['colonnes'] as Map<String, dynamic>).entries) {
      final l = lignes[key]!;
      expect([l.especeLibelle ?? '—', l.lotCode ?? '—', l.animal.sex == 'F' ? 'Femelle' : 'Mâle'], [value['espece'], value['bande'], value['sexe']], reason: key);
    }

    // Bandes proposées (toutes, puis par espèce).
    expect([for (final b in await depot.bandes()) b.code], web['bandes']['toutes']);
    for (final e in especes) {
      expect([for (final b in await depot.bandes(speciesId: e['id']!)) b.code], web['bandes'][e['id']], reason: 'bandes de ${e['label']}');
    }
    expect([for (final e in await depot.especes()) e.label], web['especes_libelles'], reason: 'BS-Q12 : mêmes espèces proposées, même ordre');
    expect(web['especes_libelles'], web['especes_servies'], reason: 'BS-Q12 : le registre web propose ce que le tirage sert au poste');
    expect(web['especes_libelles'], isNot(contains('Escargots')));
    // Modale en modification d'un sujet dont le module est éteint : son espèce s'ajoute, comme au web.
    final propre = (await depot.reproducteurs()).firstWhere((l) => l.animal.identifier == 'ESC-2026-0001').animal;
    expect([for (final e in await depot.especesDuFormulaire(sujet: propre)) e.label], web['especes_modale_eteinte']);
    expect([for (final e in await depot.especesDuFormulaire()) e.label], web['especes_modale_creation']);

    // BS-Q11 : libellé de statut — la correspondance du web (modèle `Animal`), puis ce que le registre rend par ligne.
    for (final st in ['actif', 'reforme', 'vendu', 'mort', 'disparu']) {
      expect(ReproducteursRepository.libelleStatut(st), web['libelles_statut'][st], reason: 'libellé du statut « $st »');
    }
    for (final MapEntry(:key, :value) in (web['statuts_affiches'] as Map<String, dynamic>).entries) {
      final l = lignes[key]!;
      expect(ReproducteursRepository.libelleStatut(l.animal.status), value, reason: 'statut affiché de $key');
    }

    // Messages de validation : chaque saisie invalide, mot pour mot.
    final existant = sujets.firstWhere((s) => s['categorie'] == 'reproducteur' && s['actif'] == true);
    final lap = especes[0]['id']!;
    DateTime d(String iso) {
      final p = iso.split('-').map(int.parse).toList();
      return DateTime(p[0], p[1], p[2]);
    }

    // PHP encode un tableau vide en liste : aucune erreur.
    Map<String, String> attendu(Object? v) => v is Map ? v.map((k, x) => MapEntry(k as String, x as String)) : <String, String>{};

    final cas = <String, FormulaireReproducteur>{
      'vide': const FormulaireReproducteur(),
      'longs': FormulaireReproducteur(identifier: 'x' * 51, speciesId: lap, breed: 'x' * 101, origin: 'x' * 151, cage: 'x' * 31, entryDate: d('2026-01-01')),
      'doublon': FormulaireReproducteur(identifier: existant['identifiant'] as String, speciesId: lap, entryDate: d('2026-01-01')),
      'futur': FormulaireReproducteur(identifier: 'N1', speciesId: lap, birthDate: d('2026-12-01'), entryDate: d('2026-12-31')),
      'inconnus': FormulaireReproducteur(identifier: 'N2', speciesId: 'zzz', lotId: 'yyy', entryDate: d('2026-01-01')),
      'naissance après entrée': FormulaireReproducteur(identifier: 'N3', speciesId: lap, birthDate: d('2026-03-01'), entryDate: d('2026-02-01')),
    };
    final erreursPoste = <String, Map<String, String>>{};
    for (final MapEntry(:key, :value) in cas.entries) {
      try {
        await depot.enregistrer(value);
        erreursPoste[key] = {};
      } on ReproducteurRefuse catch (e) {
        erreursPoste[key] = e.erreurs;
      }
    }
    for (final MapEntry(:key, :value) in cas.entries) {
      expect(erreursPoste[key], attendu(web['validation'][key]), reason: 'saisie « $key »');
      expect(value, isNotNull);
    }

    // Sortie : mêmes messages.
    final present = sujets.firstWhere((s) => s['statut'] == 'actif' && s['categorie'] == 'reproducteur' && s['actif'] == true);
    final sorties = <String, FormulaireSortie>{
      'sortie invalide': FormulaireSortie(status: 'zz', exitDate: d('2026-12-01'), reason: 'x' * 151),
      'sortie vide': const FormulaireSortie(status: ''),
      'sortie avant entrée': FormulaireSortie(status: 'mort', exitDate: d('2000-01-01')),
    };
    for (final MapEntry(:key, :value) in sorties.entries) {
      Map<String, String> erreurs = {};
      try {
        await depot.sortir(present['id'] as String, value);
      } on ReproducteurRefuse catch (e) {
        erreurs = e.erreurs;
      }
      expect(erreurs, attendu(web['validation'][key]), reason: 'saisie « $key »');
    }
    // BS-Q13 : le message exact du refus d'un identifiant modifié, exécuté au web (formulaire forgé) puis au poste.
    final depuis = (await depot.reproducteurs()).firstWhere((l) => l.animal.identifier == existant['identifiant']).animal;
    String? refusPoste;
    try {
      await depot.modifier(depuis.id, FormulaireReproducteur.depuis(depuis).copieAvec(identifier: 'ZZ-NOUVEAU'));
    } on ReproducteurRefuse catch (e) {
      refusPoste = e.erreurs['identifier'];
    }
    expect(refusPoste, web['identifiant_fige'], reason: 'BS-Q13 : message du refus');
    expect(ReproducteursRepository.messageIdentifiantFige, web['identifiant_fige_constante']);
    expect(web['identifiant_fige'], web['identifiant_fige_constante'], reason: 'le web refuse bien sous « identifier » avec ce message');
    expect(web['identifiant_inchange'], isTrue);
    expect(ReproducteursRepository.messageDejaSorti('vendu'), web['deja_sorti_vendu']);
    expect(ReproducteursRepository.toastEnregistre, web['toast_enregistre']);
    expect(ReproducteursRepository.toastMisAJour, web['toast_maj']);
    expect(ReproducteursRepository.toastSortie, web['toast_sortie']);
  }, skip: saut);
}

const _script = r'''
use App\Actions\SaisieReproducteurAction;
use App\Livewire\Elevage\RegistreReproducteurs;
use App\Models\Animal;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Models\User;
use Livewire\Livewire;

set_exception_handler(function (Throwable $t) {
    fwrite(STDERR, get_class($t).' : '.$t->getMessage().' @ '.$t->getFile().':'.$t->getLine());
    exit(2);
});
$e = json_decode(file_get_contents($argv[1]), true);
Carbon\Carbon::setTestNow(Carbon\Carbon::parse($e['maintenant'], config('app.timezone')));
Artisan::call('db:seed', ['--class' => 'RolesAndPermissionsSeeder', '--force' => true]);
$u = User::create(['name' => 'a', 'username' => 'a', 'email' => 'a@a.bj', 'password' => bcrypt('x'), 'is_active' => true]);
$u->assignRole('admin');
auth()->login($u);

// Décision BS-Q12 : l'indicateur `is_enabled` est volontairement VRAI partout ; seuls `modules_config` (« Modules actifs »)
// décident, comme au tirage du poste — l'espèce `helico` a son module ÉTEINT.
foreach ($e['especes'] as $x) {
    (new LivestockSpecies())->forceFill(['id' => $x['id'], 'code' => $x['code'], 'label' => $x['label'], 'is_enabled' => true])->save();
    ModuleConfig::create(['species_code' => $x['code'], 'is_enabled' => in_array($x['code'], $e['modules_actifs'], true)]);
}
foreach ($e['lots'] as $l) {
    (new LivestockLot())->forceFill([
        'id' => $l['id'], 'code' => $l['code'], 'species_id' => $l['espece'], 'stage' => 'reproduction',
        'initial_quantity' => 10, 'current_quantity' => 10, 'created_date' => '2026-02-01',
        'status' => $l['statut'], 'is_active' => $l['actif'],
    ])->save();
}
foreach ($e['sujets'] as $s) {
    (new Animal())->forceFill([
        'id' => $s['id'], 'identifier' => $s['identifiant'], 'species_id' => $s['espece'], 'lot_id' => $s['lot'],
        'category' => $s['categorie'], 'sex' => $s['sexe'], 'breed' => $s['race'], 'cage' => $s['cage'],
        'entry_date' => $s['entree'], 'status' => $s['statut'], 'is_active' => $s['actif'],
    ])->save();
}

$sortie = [];
$c = Livewire::test(RegistreReproducteurs::class);
$sortie['kpis'] = $c->instance()->kpis;
$ids = fn ($t) => $t->instance()->animals->pluck('identifier')->all();
$sortie['tous'] = $ids($c);
$sortie['recherches'] = [];
foreach (['lap', 'POU', 'blanc', 'sussex', 'zz'] as $r) {
    $sortie['recherches'][$r] = $ids(Livewire::test(RegistreReproducteurs::class)->set('search', $r));
}
$sortie['especes'] = [];
foreach ($e['especes'] as $x) {
    $sortie['especes'][$x['id']] = $ids(Livewire::test(RegistreReproducteurs::class)->set('speciesFilter', $x['id']));
}
$sortie['statuts'] = [];
foreach (['actif', 'reforme', 'vendu', 'mort'] as $st) {
    $sortie['statuts'][$st] = $ids(Livewire::test(RegistreReproducteurs::class)->set('statusFilter', $st));
}
$sortie['combine'] = $ids(Livewire::test(RegistreReproducteurs::class)->set('search', 'a')->set('speciesFilter', $e['especes'][0]['id'])->set('statusFilter', 'actif'));

$sortie['colonnes'] = [];
$doc = new DOMDocument();
@$doc->loadHTML('<?xml encoding="utf-8"?>'.$c->html());
$xp = new DOMXPath($doc);
foreach ($xp->query("//tr[contains(@class, 'rrow')]") as $tr) {
    $txt = fn ($label) => trim(preg_replace('/\s+/u', ' ', $xp->query(".//td[@data-label='$label']", $tr)->item(0)->textContent));
    $sortie['colonnes'][$txt('Identifiant')] = ['espece' => $txt('Espèce'), 'bande' => $txt('Bande'), 'sexe' => $txt('Sexe')];
}

$sortie['bandes'] = ['toutes' => Livewire::test(RegistreReproducteurs::class)->instance()->lotOptions->pluck('code')->all()];
foreach ($e['especes'] as $x) {
    $sortie['bandes'][$x['id']] = Livewire::test(RegistreReproducteurs::class)->set('species_id', $x['id'])->instance()->lotOptions->pluck('code')->all();
}
$sortie['especes_libelles'] = $c->instance()->speciesOptions->pluck('label')->all();
// Ce que le tirage sert au poste (`SyncController` : `LivestockSpecies::enabled()->orderBy('label')`).
$sortie['especes_servies'] = LivestockSpecies::query()->enabled()->orderBy('label')->pluck('label')->all();
$eteint = collect($e['sujets'])->firstWhere('identifiant', 'ESC-2026-0001');
$sortie['especes_modale_eteinte'] = Livewire::test(RegistreReproducteurs::class)->call('editAnimal', $eteint['id'])->instance()->speciesFormOptions->pluck('label')->all();
$sortie['especes_modale_creation'] = Livewire::test(RegistreReproducteurs::class)->call('newAnimal')->instance()->speciesFormOptions->pluck('label')->all();
$sortie['libelles_statut'] = [];
foreach (['actif', 'reforme', 'vendu', 'mort', 'disparu'] as $st) {
    $sortie['libelles_statut'][$st] = Animal::libelleStatut($st);
}
$sortie['statuts_affiches'] = [];
foreach ($xp->query("//tr[contains(@class, 'rrow')]") as $tr) {
    $txt = fn ($label) => trim(preg_replace('/\s+/u', ' ', $xp->query(".//td[@data-label='$label']", $tr)->item(0)->textContent));
    $sortie['statuts_affiches'][$txt('Identifiant')] = $txt('Statut');
}

$lap = $e['especes'][0]['id'];
$existant = collect($e['sujets'])->first(fn ($s) => $s['categorie'] === 'reproducteur' && $s['actif'] === true);
$cas = [
    'vide' => ['identifier' => '', 'species_id' => '', 'entry_date' => ''],
    'longs' => ['identifier' => str_repeat('x', 51), 'species_id' => $lap, 'breed' => str_repeat('x', 101), 'origin' => str_repeat('x', 151), 'cage' => str_repeat('x', 31), 'entry_date' => '2026-01-01'],
    'doublon' => ['identifier' => $existant['identifiant'], 'species_id' => $lap, 'entry_date' => '2026-01-01'],
    'futur' => ['identifier' => 'N1', 'species_id' => $lap, 'birth_date' => '2026-12-01', 'entry_date' => '2026-12-31'],
    'inconnus' => ['identifier' => 'N2', 'species_id' => 'zzz', 'lot_id' => 'yyy', 'entry_date' => '2026-01-01'],
    'naissance après entrée' => ['identifier' => 'N3', 'species_id' => $lap, 'birth_date' => '2026-03-01', 'entry_date' => '2026-02-01'],
];
$sortie['validation'] = [];
foreach ($cas as $nom => $champs) {
    $t = Livewire::test(RegistreReproducteurs::class)->call('newAnimal');
    foreach ($champs as $k => $v) {
        $t->set($k, $v);
    }
    $t->call('saveAnimal');
    $sortie['validation'][$nom] = array_map(fn ($m) => $m[0], $t->errors()->toArray());
}
$present = collect($e['sujets'])->first(fn ($s) => $s['statut'] === 'actif' && $s['categorie'] === 'reproducteur' && $s['actif'] === true);
$sorties = [
    'sortie invalide' => ['exitStatus' => 'zz', 'exit_date' => '2026-12-01', 'exit_reason' => str_repeat('x', 151)],
    'sortie vide' => ['exitStatus' => '', 'exit_date' => ''],
    'sortie avant entrée' => ['exitStatus' => 'mort', 'exit_date' => '2000-01-01'],
];
foreach ($sorties as $nom => $champs) {
    $t = Livewire::test(RegistreReproducteurs::class)->call('openExit', $present['id']);
    foreach ($champs as $k => $v) {
        $t->set($k, $v);
    }
    $t->call('confirmExit');
    $sortie['validation'][$nom] = array_map(fn ($m) => $m[0], $t->errors()->toArray());
}
$forge = Livewire::test(RegistreReproducteurs::class)->call('editAnimal', $existant['id'])->set('identifier', 'ZZ-NOUVEAU')->call('saveAnimal');
$sortie['identifiant_fige'] = $forge->errors()->first('identifier');
$sortie['identifiant_fige_constante'] = SaisieReproducteurAction::MESSAGE_IDENTIFIANT_FIGE;
$sortie['identifiant_inchange'] = Animal::find($existant['id'])->identifier === $existant['identifiant'];
$sortie['deja_sorti_vendu'] = SaisieReproducteurAction::messageDejaSorti('vendu');
$toast = function ($t) {
    foreach (array_reverse($t->effects['dispatches'] ?? []) as $d) {
        if (($d['name'] ?? '') === 'toast') {
            return $d['params']['message'] ?? null;
        }
    }

    return null;
};
$ok = Livewire::test(RegistreReproducteurs::class)->call('newAnimal')
    ->set('identifier', 'ZZ-OK')->set('species_id', $lap)->set('entry_date', '2026-01-01')->call('saveAnimal');
$sortie['toast_enregistre'] = $toast($ok);
$id = Animal::where('identifier', 'ZZ-OK')->value('id');
$sortie['toast_maj'] = $toast(Livewire::test(RegistreReproducteurs::class)->call('editAnimal', $id)->set('cage', 'C1')->call('saveAnimal'));
$sortie['toast_sortie'] = $toast(Livewire::test(RegistreReproducteurs::class)->call('openExit', $id)->set('exit_date', '2026-06-01')->call('confirmExit'));

echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
''';
