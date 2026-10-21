import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/bandes_repository.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/sujets_entrees_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Tickets BS1 et BS2 — PARITÉ EXÉCUTÉE : le VRAI composant `GestionBandes` et le VRAI `EnregistrerSujets` du web
/// rendent, sur un jeu tiré au hasard (graine fixe), ce que le poste calcule : indicateurs, ordre et filtres du tableau,
/// mortalité du Blade, code suggéré, espèces proposées, tiroir (rémanence, infirmerie, mortalité 7 jours, soins,
/// provende servie, autonomie), journal des sujets et ses indicateurs, et les MESSAGES de validation, mot pour mot.
///
/// Rien n'est recopié : le test envoie son jeu en JSON, le PHP du dépôt Laravel l'exécute, le test compare. Sans PHP ni
/// dépôt Laravel, il se SAUTE avec sa raison.
void main() {
  final saut = sautSansPhp();

  test('⚠️⚠️ BS1/BS2 — indicateurs, tableau, tiroir, journal et messages : ceux du web exécuté', () async {
    final hasard = Random(2110);
    String uuid() => [
      for (final n in [8, 4, 4, 4, 12]) List.generate(n, (_) => '0123456789abcdef'[hasard.nextInt(16)]).join(),
    ].join('-');
    String jour(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final aujourdhui = DateTime(2026, 10, 21);

    const codes = ['cuniculture', 'aviculture', 'porciculture', 'helico'];
    const prefixes = {'cuniculture': 'LOT-LAP', 'aviculture': 'LOT-VOL', 'porciculture': 'LOT-POR', 'helico': 'FOSSE'};
    final especes = [for (final c in codes) {'id': uuid(), 'code': c, 'label': c == 'helico' ? 'Héliciculture' : '${c[0].toUpperCase()}${c.substring(1)}'}];
    const modules = {'cuniculture': true, 'aviculture': true, 'porciculture': false, 'helico': true};
    const stadesLapins = ['reproduction', 'engraissement', 'croissance'];
    const stadesAutres = ['reproduction', 'croissance', 'ponte', 'engraissement'];

    final pris = <String>{};
    final lots = <Map<String, dynamic>>[];
    for (var i = 0; i < 14; i++) {
      final e = especes[hasard.nextInt(especes.length)];
      var code = '';
      do {
        code = '${prefixes[e['code']]}-${1 + hasard.nextInt(30)}';
      } while (!pris.add(code));
      final initial = hasard.nextInt(6) == 0 ? 0 : 1 + hasard.nextInt(40);
      lots.add({
        'id': uuid(),
        'code': code,
        'espece': e['id'],
        'stade': (e['code'] == 'cuniculture' ? stadesLapins : stadesAutres)[hasard.nextInt(e['code'] == 'cuniculture' ? 3 : 4)],
        'initial': initial,
        'courant': initial == 0 ? 0 : hasard.nextInt(initial + 1),
        'statut': hasard.nextInt(4) == 0 ? 'cloture' : 'actif',
        'actif': hasard.nextInt(7) != 0,
        'creee': jour(DateTime(2026, 1, 1).add(Duration(days: 20 * i + hasard.nextInt(15)))),
      });
    }

    final fiches = <Map<String, dynamic>>[];
    for (final l in lots) {
      final jours = <int>{};
      final n = hasard.nextInt(4);
      for (var k = 0; k < n; k++) {
        jours.add(hasard.nextInt(30));
      }
      for (final dj in jours) {
        fiches.add({
          'id': uuid(),
          'lot': l['id'],
          'jour': jour(aujourdhui.subtract(Duration(days: dj))),
          'achat': hasard.nextInt(3) == 0 ? hasard.nextInt(6) : 0,
          'ne': hasard.nextInt(3) == 0 ? 1 + hasard.nextInt(6) : 0,
          'mort': hasard.nextInt(3),
          'vente': hasard.nextInt(2),
          'don': hasard.nextInt(4) == 0 ? hasard.nextInt(3) : 0,
          'final': hasard.nextInt(40),
          'aliment': hasard.nextInt(3) == 0 ? null : (hasard.nextInt(900) + 5) / 100,
        });
      }
    }
    final periodes = [
      for (var i = 0; i < 6; i++)
        {
          'id': uuid(),
          'lot': lots[hasard.nextInt(lots.length)]['id'],
          'produit': i.isEven ? 'Oxytétracycline' : 'Vermifuge',
          'fin': jour(aujourdhui.add(Duration(days: hasard.nextInt(9) - 3))),
        },
    ];
    final infirmerie = [
      for (var i = 0; i < 5; i++)
        {'id': uuid(), 'lot': lots[hasard.nextInt(lots.length)]['id'], 'statut': ['en_cours', 'reintegre', 'deces'][hasard.nextInt(3)]},
    ];
    final soins = [
      for (var i = 0; i < 9; i++)
        {
          'id': uuid(),
          'lot': lots[hasard.nextInt(lots.length)]['id'],
          'action': ['Vaccination', 'Déparasitage', 'Traitement'][hasard.nextInt(3)],
          'produit': hasard.nextBool() ? 'Produit ${hasard.nextInt(9)}' : null,
          'jour': jour(aujourdhui.subtract(Duration(days: hasard.nextInt(40)))),
          'actif': hasard.nextInt(5) != 0,
        },
    ];
    final produits = [
      {'id': uuid(), 'nom': 'Provende volailles', 'sku': 'PRV-01', 'espece': especes[1]['id'], 'stock': 87.5, 'unite': 'sac'},
      {'id': uuid(), 'nom': 'Aliment escargots', 'sku': 'PRV-02', 'espece': especes[3]['id'], 'stock': 0.0, 'unite': 'kg'},
    ];

    final entree = {
      'maintenant': '2026-10-21 10:30:00',
      'especes': especes,
      'modules': modules,
      'lots': lots,
      'fiches': fiches,
      'periodes': periodes,
      'infirmerie': infirmerie,
      'soins': soins,
      'produits': produits,
    };
    final web = executerPhp('<?php\n$amorceApplication\n$_script', entree, application: true) as Map<String, dynamic>;

    // ── Le même jeu dans la base du poste ────────────────────────────────────────────────────────────────────────
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    for (final e in especes) {
      await db.into(db.livestockSpecies).insert(LivestockSpeciesCompanion.insert(id: e['id']!, code: e['code']!, label: e['label']!));
      await db.into(db.modulesConfig).insert(ModulesConfigCompanion.insert(id: uuid(), speciesCode: e['code']!, isEnabled: Value(modules[e['code']]!)));
    }
    for (final l in lots) {
      await db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: l['id'] as String,
          code: l['code'] as String,
          speciesId: l['espece'] as String,
          speciesCode: Value(especes.firstWhere((e) => e['id'] == l['espece'])['code']),
          stage: Value(l['stade'] as String),
          initialQuantity: Value(l['initial'] as int),
          currentQuantity: Value(l['courant'] as int),
          createdDate: Value(DateTime.parse(l['creee'] as String)),
          status: Value(l['statut'] as String),
          isActive: Value(l['actif'] as bool),
        ),
      );
    }
    for (final f in fiches) {
      await db.into(db.livestockDailyEntries).insert(
        LivestockDailyEntriesCompanion.insert(
          id: f['id'] as String,
          deviceId: 'serveur',
          updatedAt: DateTime(2026, 10, 21),
          lotId: f['lot'] as String,
          entryDate: DateTime.parse(f['jour'] as String),
          achat: Value(f['achat'] as int),
          ne: Value(f['ne'] as int),
          mort: Value(f['mort'] as int),
          vente: Value(f['vente'] as int),
          don: Value(f['don'] as int),
          effectifFinal: Value(f['final'] as int),
          feedQtyKg: Value((f['aliment'] as num?)?.toDouble()),
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
    }
    for (final p in periodes) {
      await db.into(db.veterinaryWithdrawalPeriods).insert(
        VeterinaryWithdrawalPeriodsCompanion.insert(id: p['id'] as String, lotId: p['lot'] as String, endDate: DateTime.parse(p['fin'] as String), productUsed: Value(p['produit'] as String?)),
      );
    }
    for (final i in infirmerie) {
      await db.into(db.infirmaryRecords).insert(
        InfirmaryRecordsCompanion.insert(id: i['id'] as String, deviceId: 'serveur', updatedAt: DateTime(2026, 10, 21), lotId: i['lot'] as String, motif: 'Boiterie', entryDate: DateTime(2026, 10, 1), status: Value(i['statut'] as String)),
      );
    }
    for (final s in soins) {
      await db.into(db.veterinaryRecords).insert(
        VeterinaryRecordsCompanion.insert(
          id: s['id'] as String,
          deviceId: 'serveur',
          updatedAt: DateTime(2026, 10, 21),
          lotId: s['lot'] as String,
          actionType: s['action'] as String,
          productUsed: Value(s['produit'] as String?),
          recordDate: DateTime.parse(s['jour'] as String),
          isActive: Value(s['actif'] as bool),
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
    }
    for (final p in produits) {
      await db.into(db.products).insert(
        ProductsCompanion.insert(id: p['id']! as String, sku: p['sku']! as String, name: p['nom']! as String, unit: p['unite']! as String, pricingMode: 'fourchette', speciesId: Value(p['espece'] as String?), stockQty: Value((p['stock']! as num).toDouble())),
      );
    }

    final horloge = DateTime(2026, 10, 21, 10, 30);
    final bandes = BandesRepository(database: db, deviceId: 'poste-test', horloge: () => horloge);
    final sujets = SujetsEntreesRepository(database: db, fiches: FicheJournaliereRepository(database: db, deviceId: 'poste-test'), horloge: () => horloge);

    // ── Bandes : indicateurs, tableau, filtres, mortalité du Blade ──────────────────────────────────────────────
    final k = await bandes.indicateurs();
    expect({'bandes_actives': k.bandesActives, 'en_reproduction': k.enReproduction, 'effectif_total': k.effectifTotal, 'alertes_sanitaires': k.alertesSanitaires}, web['kpis']);
    expect([for (final l in await bandes.bandes()) l.bande.code], web['codes'], reason: 'ordre du tableau');
    expect({for (final l in await bandes.bandes()) l.bande.code: BandesRepository.formaterMortalite(l.mortalite)}, web['mortalite'], reason: 'mortalité du Blade');
    expect({for (final l in await bandes.bandes()) l.bande.code: l.libelleStade}, web['stades'], reason: 'libellé de stade selon l espèce');
    for (final recherche in ['LAP', 'vol', 'FOSSE', 'zz']) {
      expect([for (final l in await bandes.bandes(recherche: recherche)) l.bande.code], (web['recherches'] as Map)[recherche], reason: 'recherche « $recherche »');
    }
    for (final filiere in codes) {
      expect([for (final l in await bandes.bandes(filiere: filiere)) l.bande.code], (web['filieres'] as Map)[filiere], reason: 'filière $filiere');
    }
    expect([for (final e in await bandes.especes()) e.label], web['especes'], reason: 'espèces proposées');
    for (final e in especes) {
      expect(await bandes.codeSuggere(e['id']!), (web['codes_suggeres'] as Map)[e['code']], reason: 'code suggéré ${e['code']}');
    }

    // ── Tiroir ──────────────────────────────────────────────────────────────────────────────────────────────────
    var avecRemanence = 0;
    for (final l in lots) {
      final d = (await bandes.detail(l['id'] as String))!;
      final w = (web['tiroirs'] as Map)[l['id']] as Map<String, dynamic>;
      final ici = {
        'remanence': d.remanence == null ? null : '${d.remanence!.productUsed ?? ''}|${jour(d.remanence!.endDate)}',
        'infirmerie': d.infirmerie,
        'morts_7j': d.mortsSurSeptJours,
        'mortalite_7j': d.mortaliteSurSeptJours,
        'soins': [for (final s in d.derniersSoins) '${jour(s.recordDate)}|${s.actionType}|${s.productUsed ?? ''}'],
        'provende': d.provendeBandeKg,
        'date_fiche': d.dateDerniereFiche == null ? null : jour(d.dateDerniereFiche!),
        'autonomie': {
          'disponible': d.autonomie.disponible,
          'inconnu': d.autonomie.inconnu,
          'critique': d.autonomie.critique,
          'rupture': d.autonomie.rupture,
          'jours': d.autonomie.jours,
          'stock_kg': d.autonomie.stockKg,
        },
      };
      expect(_normaliser(ici), _normaliser(w), reason: 'tiroir de ${l['code']}');
      if (d.remanence != null) avecRemanence++;
    }
    expect(avecRemanence, greaterThan(1), reason: 'le jeu doit contenir des rémanences en cours');

    // ── Sujets : indicateurs et journal ─────────────────────────────────────────────────────────────────────────
    final ks = await sujets.indicateurs();
    expect({'naissances_mois': ks.naissancesMois, 'acquisitions_mois': ks.acquisitionsMois, 'effectif_total': ks.effectifTotal}, web['kpis_sujets']);
    List<String> journal(List<LigneSujet> l) => [for (final x in l) '${jour(x.fiche.entryDate)}|${x.codeBande}|${x.origine}|${x.quantite}'];
    for (final (cle, statut, recherche) in [('tous', '', ''), ('naissance', 'Naissance', ''), ('achat', 'Achat', ''), ('recherche', '', 'LOT')]) {
      expect(journal(await sujets.entrees(statut: statut, recherche: recherche)), (web['journal'] as Map)[cle], reason: 'journal « $cle »');
    }

    // ── Messages de validation, mot pour mot ────────────────────────────────────────────────────────────────────
    for (final c in web['validation_bandes'] as List) {
      final cas = c as Map<String, dynamic>;
      final f = cas['formulaire'] as Map<String, dynamic>;
      final espece = especes.where((e) => e['id'] == f['species_id']).firstOrNull;
      final ici = BandesRepository.valider(
        FormulaireBande(
          speciesId: f['species_id'] as String,
          code: f['code'] as String,
          stage: f['stage'] as String,
          createdDate: (f['created_date'] as String).isEmpty ? null : DateTime.parse(f['created_date'] as String),
          quantite: '${f['quantity']}',
        ),
        codeEspece: espece?['code'],
        especeConnue: espece != null,
        codeDejaPris: lots.any((l) => (l['code'] as String).toLowerCase() == (f['code'] as String).toLowerCase()),
      );
      expect(ici, Map<String, dynamic>.from(cas['erreurs'] as Map), reason: 'saveLot « ${cas['nom']} »');
    }
    for (final c in web['validation_sujets'] as List) {
      final cas = c as Map<String, dynamic>;
      final f = cas['formulaire'] as Map<String, dynamic>;
      final ici = SujetsEntreesRepository.valider(
        FormulaireSujet(
          speciesId: f['species_id'] as String,
          lotId: f['lot_id'] as String,
          origine: f['origine'] as String,
          quantite: '${f['quantite']}',
          date: (f['entry_date'] as String).isEmpty ? null : DateTime.parse(f['entry_date'] as String),
        ),
        especeConnue: especes.any((e) => e['id'] == f['species_id']),
        bandeConnue: lots.any((l) => l['id'] == f['lot_id']),
      );
      expect(ici, Map<String, dynamic>.from(cas['erreurs'] as Map), reason: 'saveEntry « ${cas['nom']} »');
    }
    expect((web['validation_bandes'] as List).length, greaterThan(5));
    expect((web['validation_sujets'] as List).length, greaterThan(2));
  }, skip: saut);
}

/// Les nombres du JSON PHP (entiers ou flottants) comparés à ceux de Dart : `12` et `12.0` sont la même valeur.
Object? _normaliser(Object? v) => switch (v) {
  num() => v.toDouble(),
  Map() => {for (final e in v.entries) e.key.toString(): _normaliser(e.value)},
  List() => [for (final e in v) _normaliser(e)],
  _ => v,
};

const _script = r'''
use App\Livewire\Elevage\EnregistrerSujets;
use App\Livewire\Elevage\GestionBandes;
use App\Models\LivestockDailyEntry;
use App\Models\LivestockLot;
use App\Models\LivestockSpecies;
use App\Models\ModuleConfig;
use App\Models\Product;
use App\Models\ProductCategory;
use App\Models\User;
use Illuminate\Support\Facades\DB;
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

foreach ($e['especes'] as $x) {
    (new LivestockSpecies())->forceFill(['id' => $x['id'], 'code' => $x['code'], 'label' => $x['label'], 'is_enabled' => true])->save();
}
foreach ($e['modules'] as $code => $actif) {
    ModuleConfig::create(['species_code' => $code, 'is_enabled' => $actif]);
}
foreach ($e['lots'] as $l) {
    (new LivestockLot())->forceFill([
        'id' => $l['id'], 'code' => $l['code'], 'species_id' => $l['espece'], 'stage' => $l['stade'],
        'initial_quantity' => $l['initial'], 'current_quantity' => $l['courant'], 'created_date' => $l['creee'],
        'status' => $l['statut'], 'is_active' => $l['actif'],
    ])->save();
}
foreach ($e['fiches'] as $f) {
    (new LivestockDailyEntry())->forceFill([
        'id' => $f['id'], 'lot_id' => $f['lot'], 'entry_date' => $f['jour'], 'achat' => $f['achat'], 'ne' => $f['ne'],
        'mort' => $f['mort'], 'vente' => $f['vente'], 'don' => $f['don'], 'effectif_final' => $f['final'],
        'feed_qty_kg' => $f['aliment'],
    ])->save();
}
foreach ($e['periodes'] as $p) {
    DB::table('veterinary_withdrawal_periods')->insert([
        'id' => $p['id'], 'lot_id' => $p['lot'], 'product_used' => $p['produit'], 'start_date' => '2026-10-01',
        'withdrawal_days' => 5, 'end_date' => $p['fin'], 'created_at' => now(), 'updated_at' => now(),
    ]);
}
foreach ($e['infirmerie'] as $i) {
    DB::table('infirmary_records')->insert([
        'id' => $i['id'], 'lot_id' => $i['lot'], 'motif' => 'Boiterie', 'entry_date' => '2026-10-01',
        'status' => $i['statut'], 'created_at' => now(), 'updated_at' => now(),
    ]);
}
foreach ($e['soins'] as $s) {
    DB::table('veterinary_records')->insert([
        'id' => $s['id'], 'lot_id' => $s['lot'], 'action_type' => $s['action'], 'product_used' => $s['produit'],
        'record_date' => $s['jour'], 'is_active' => $s['actif'], 'created_at' => now(), 'updated_at' => now(),
    ]);
}
$categorie = ProductCategory::create(['label' => 'Provende', 'is_active' => true]);
foreach ($e['produits'] as $p) {
    (new Product())->forceFill([
        'id' => $p['id'], 'sku' => $p['sku'], 'name' => $p['nom'], 'category_id' => $categorie->id, 'unit' => $p['unite'],
        'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 1, 'tva_rate' => 0, 'stock_qty' => $p['stock'],
        'species_id' => $p['espece'], 'is_active' => true,
    ])->save();
}

$sortie = [];
$composant = Livewire::test(GestionBandes::class);
$sortie['kpis'] = $composant->instance()->kpis;
$sortie['codes'] = $composant->instance()->lots->pluck('code')->all();

$html = $composant->html();
$doc = new DOMDocument();
@$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
$xp = new DOMXPath($doc);
$sortie['mortalite'] = [];
$sortie['stades'] = [];
foreach ($xp->query("//tr[contains(@class, 'rrow')]") as $tr) {
    $code = trim($xp->query(".//td[@data-label='Code Bande']", $tr)->item(0)->textContent);
    $sortie['mortalite'][$code] = trim(preg_replace('/\s+/u', ' ', $xp->query(".//td[@data-label='Mortalité']", $tr)->item(0)->textContent));
    $sortie['stades'][$code] = trim(preg_replace('/\s+/u', ' ', $xp->query(".//td[@data-label='Stade']", $tr)->item(0)->textContent));
}
$sortie['recherches'] = [];
foreach (['LAP', 'vol', 'FOSSE', 'zz'] as $r) {
    $sortie['recherches'][$r] = Livewire::test(GestionBandes::class)->set('search', $r)->instance()->lots->pluck('code')->all();
}
$sortie['filieres'] = [];
foreach (['cuniculture', 'aviculture', 'porciculture', 'helico'] as $f) {
    $sortie['filieres'][$f] = Livewire::test(GestionBandes::class)->set('filiere', $f)->instance()->lots->pluck('code')->all();
}
$sortie['especes'] = $composant->instance()->speciesOptions->pluck('label')->all();
$sortie['codes_suggeres'] = [];
foreach ($e['especes'] as $x) {
    $sortie['codes_suggeres'][$x['code']] = LivestockLot::suggestNextCode($x['code']);
}

$sortie['tiroirs'] = [];
foreach ($e['lots'] as $l) {
    $c = Livewire::test(GestionBandes::class)->call('view', $l['id']);
    $s = $c->instance()->suiviSanitaireBande;
    $a = $c->instance()->autonomieBande;
    $f = $a['filiere'];
    $sortie['tiroirs'][$l['id']] = [
        'remanence' => $s['remanence'] ? ($s['remanence']->product_used ?? '').'|'.$s['remanence']->end_date->format('Y-m-d') : null,
        'infirmerie' => $s['infirmerie'],
        'morts_7j' => $s['morts_7j'],
        'mortalite_7j' => $s['mortalite_7j'],
        'soins' => $s['derniers_soins']->map(fn ($x) => $x->record_date->format('Y-m-d').'|'.$x->action_type.'|'.($x->product_used ?? ''))->all(),
        'provende' => $a['provende_bande_kg'],
        'date_fiche' => $a['date_fiche']?->format('Y-m-d'),
        'autonomie' => [
            'disponible' => (bool) ($f['available'] ?? false),
            'inconnu' => (bool) ($f['inconnu'] ?? false),
            'critique' => (bool) ($f['critique'] ?? false),
            'rupture' => (bool) ($f['rupture'] ?? false),
            'jours' => isset($f['autonomie_jours']) ? (float) $f['autonomie_jours'] : null,
            'stock_kg' => isset($f['stock_kg']) ? (float) $f['stock_kg'] : null,
        ],
    ];
}

$journal = fn ($c) => $c->instance()->entries->map(fn ($r) => $r->entry->entry_date->format('Y-m-d').'|'.$r->entry->lot->code.'|'.$r->origine.'|'.$r->quantite)->all();
$sortie['kpis_sujets'] = Livewire::test(EnregistrerSujets::class)->instance()->kpis;
$sortie['journal'] = [
    'tous' => $journal(Livewire::test(EnregistrerSujets::class)),
    'naissance' => $journal(Livewire::test(EnregistrerSujets::class)->set('statut', 'Naissance')),
    'achat' => $journal(Livewire::test(EnregistrerSujets::class)->set('statut', 'Achat')),
    'recherche' => $journal(Livewire::test(EnregistrerSujets::class)->set('search', 'LOT')),
];

// ── Validation : uniquement des saisies INVALIDES (rien n'est écrit) ──────────────────────────────────────────────
$lap = collect($e['especes'])->firstWhere('code', 'cuniculture')['id'];
$existant = $e['lots'][0]['code'];
$casBandes = [
    'tout vide' => ['species_id' => '', 'code' => '', 'stage' => 'reproduction', 'created_date' => '', 'quantity' => 0],
    'code trop long' => ['species_id' => $lap, 'code' => str_repeat('x', 51), 'stage' => 'reproduction', 'created_date' => '2026-10-20', 'quantity' => 5],
    'code déjà pris' => ['species_id' => $lap, 'code' => $existant, 'stage' => 'reproduction', 'created_date' => '2026-10-20', 'quantity' => 5],
    'quantité négative' => ['species_id' => $lap, 'code' => 'ZZ-1', 'stage' => 'reproduction', 'created_date' => '2026-10-20', 'quantity' => -3],
    'quantité nulle' => ['species_id' => $lap, 'code' => 'ZZ-1', 'stage' => 'reproduction', 'created_date' => '2026-10-20', 'quantity' => 0],
    'stade absent de l espèce' => ['species_id' => $lap, 'code' => 'ZZ-1', 'stage' => 'ponte', 'created_date' => '2026-10-20', 'quantity' => 3],
    'espèce inconnue' => ['species_id' => 'inconnue', 'code' => 'ZZ-1', 'stage' => 'reproduction', 'created_date' => '2026-10-20', 'quantity' => 3],
];
$sortie['validation_bandes'] = [];
foreach ($casBandes as $nom => $c) {
    $t = Livewire::test(GestionBandes::class);
    $t->set('species_id', $c['species_id'])->set('code', $c['code'])->set('stage', $c['stage'])->set('created_date', $c['created_date'])->set('quantity', $c['quantity']);
    $t->call('saveLot');
    $erreurs = [];
    foreach ($t->errors()->toArray() as $champ => $messages) {
        $erreurs[$champ] = $messages[0];
    }
    $sortie['validation_bandes'][] = ['nom' => $nom, 'formulaire' => $c, 'erreurs' => $erreurs];
}
$lot = $e['lots'][0]['id'];
$casSujets = [
    'tout vide' => ['species_id' => '', 'lot_id' => '', 'origine' => '', 'quantite' => 0, 'entry_date' => ''],
    'valeurs hors liste' => ['species_id' => $lap, 'lot_id' => 'zzz', 'origine' => 'Vol', 'quantite' => -2, 'entry_date' => '2026-10-20'],
    'quantité nulle' => ['species_id' => $lap, 'lot_id' => $lot, 'origine' => 'Achat', 'quantite' => 0, 'entry_date' => '2026-10-20'],
];
$sortie['validation_sujets'] = [];
foreach ($casSujets as $nom => $c) {
    $t = Livewire::test(EnregistrerSujets::class);
    foreach ($c as $k => $v) {
        $t->set($k, $v);
    }
    $t->call('saveEntry');
    $erreurs = [];
    foreach ($t->errors()->toArray() as $champ => $messages) {
        $erreurs[$champ] = $messages[0];
    }
    $sortie['validation_sujets'][] = ['nom' => $nom, 'formulaire' => $c, 'erreurs' => $erreurs];
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
''';
