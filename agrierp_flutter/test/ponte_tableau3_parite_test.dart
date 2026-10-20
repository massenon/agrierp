import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/rapports/rapports_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket U9 — TABLEAU 3 « SUIVI INTÉGRAL DE LA PONTE » : PARITÉ EXÉCUTÉE AVEC LE VRAI BLADE.
///
/// Le poste produisait un autre tableau que le web (soldes PAR BANDE, EN ŒUFS, depuis ses fiches et ses lignes de
/// vente, sans colonne « Lot »). Le web est maître : ce test fait RENDRE le Tableau 3 par Laravel
/// (`Livewire::test(ElevageSynth)` sur `elevage-synth.blade.php`, base SQLite en mémoire), lit chaque cellule du HTML,
/// et exige les MÊMES lignes, cellule pour cellule, au poste ([RapportsRepository.elevagePonte] via `charger`) sur le
/// même jeu : bandes (dont deux créées après certaines de leurs fiches), fiches de ponte (casses
/// absentes, ponte nulle, effectif nul, deux bandes le même jour), grand livre des stocks (production, ventes,
/// casses, ajustements bruts, un autre produit, un leurre « Oeufs à couver » qui n'est pas le produit retenu).
void main() {
  test(
    'parité exécutée U9 : le Tableau 3 du poste = le Tableau 3 rendu par le Blade',
    () async {
      var graine = 91;
      int hasard(int n) =>
          ((graine = (graine * 1103515245 + 12345) & 0x7fffffff) >> 16) % n;
      String jour(int mois, int j) =>
          '2026-${mois.toString().padLeft(2, '0')}-${j.toString().padLeft(2, '0')}';
      String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

      final bandes = [
        {'code': 'PON-A', 'creee': '2026-01-05'},
        {'code': 'PON-B', 'creee': '2026-07-12'},
        // `created_date` est NOT NULL au serveur : le « — » d'âge n'y apparaît jamais (couvert à la main ailleurs).
        {'code': 'PON-C', 'creee': '2026-07-20'},
      ];
      final fiches = <Map<String, Object?>>[];
      final vus = <String>{};
      for (var f = 0; f < 30; f++) {
        final bande = hasard(3);
        final j = 1 + hasard(31);
        // Une fiche par (bande, jour), comme au serveur ; quelques-unes hors période (juin, août).
        final mois = f % 9 == 0 ? (f.isEven ? 6 : 8) : 7;
        final date = jour(mois, mois == 8 ? 1 + (j % 28) : (mois == 6 ? 1 + (j % 30) : j));
        // `unique(['lot_id', 'entry_date'])` au serveur.
        if (!vus.add('$bande $date')) continue;
        final ponte = hasard(6) == 0 ? 0 : 50 + hasard(500);
        fiches.add({
          'bande': bande,
          'date': date,
          'ponte': ponte,
          'casses': f % 5 == 1 ? null : hasard(ponte + 1 > 40 ? 40 : ponte + 1),
          'effectif': f % 7 == 3 ? 0 : 300 + hasard(200),
        });
      }
      // Grand livre : produit œufs (index 0), leurre (1), autre produit (2).
      final mouvements = [
        for (var m = 0; m < 45; m++)
          () {
            final reference = [
              'sale', 'sale', 'daily_entry', 'daily_entry', 'inventaire', 'adjustment', 'purchase', //
            ][hasard(7)];
            final type = m % 11 == 0
                ? 'ajustement'
                : reference == 'sale'
                ? 'sortie'
                : reference == 'daily_entry' || reference == 'purchase'
                ? 'entree'
                : (hasard(2) == 0 ? 'entree' : 'sortie');
            final mois = [6, 7, 7, 7][hasard(4)];
            return {
              'produit': [0, 0, 0, 0, 1, 2][hasard(6)],
              'type': type,
              'qty': (1 + hasard(1500)) / 100,
              'ref': reference,
              'date': '${jour(mois, 1 + hasard(mois == 6 ? 30 : 31))} '
                  '${(hasard(24)).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}:00',
            };
          }(),
      ];
      final produits = ['Œufs de table (plateau)', 'Oeufs à couver', 'Provende ponte'];

      final sortie =
          executerPhp('<?php\n$amorceApplication\n$_script', {
                'bandes': bandes,
                'fiches': fiches,
                'mouvements': mouvements,
                'produits': produits,
              }, application: true)
              as Map<String, dynamic>;

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      for (var i = 0; i < produits.length; i++) {
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: uuid('produit-$i-'),
                sku: 'P$i',
                name: produits[i],
                unit: 'plateau',
                pricingMode: 'fixe',
              ),
            );
      }
      for (var b = 0; b < bandes.length; b++) {
        final creee = bandes[b]['creee'];
        await db
            .into(db.livestockLots)
            .insert(
              LivestockLotsCompanion.insert(
                id: uuid('bande-$b-'),
                code: bandes[b]['code']!,
                speciesId: uuid('espece'),
                speciesCode: const Value('aviculture'),
                stage: const Value('ponte'),
                createdDate: Value(creee == null ? null : DateTime.parse(creee)),
              ),
            );
      }
      for (var f = 0; f < fiches.length; f++) {
        final x = fiches[f];
        await db
            .into(db.livestockDailyEntries)
            .insert(
              LivestockDailyEntriesCompanion.insert(
                id: uuid('fiche-$f-'),
                deviceId: 'serveur',
                // Fiches du serveur : rien n'est projeté.
                syncStatus: const Value(SyncStatus.synced),
                updatedAt: DateTime(2026, 8, 1),
                lotId: uuid('bande-${x['bande']}-'),
                entryDate: DateTime.parse(x['date']! as String),
                effectifFinal: Value(x['effectif']! as int),
                ponteTotal: Value(x['ponte']! as int),
                ponteCasses: Value(x['casses'] as int?),
              ),
            );
      }
      for (var m = 0; m < mouvements.length; m++) {
        final x = mouvements[m];
        await db
            .into(db.stockMovements)
            .insert(
              StockMovementsCompanion.insert(
                id: uuid('mvt-$m-'),
                productId: uuid('produit-${x['produit']}-'),
                type: x['type']! as String,
                quantity: (x['qty']! as num).toDouble(),
                referenceType: x['ref']! as String,
                movementDate: DateTime.parse(x['date']! as String),
              ),
            );
      }

      final d = await RapportsRepository(
        database: db,
      ).charger(du: DateTime(2026, 7, 1), au: DateTime(2026, 7, 31));

      // L'ordre de deux bandes du même jour n'est pas défini au web (`orderByDesc('entry_date')` seul) : les
      // lignes se comparent triées par jour décroissant puis par code de bande.
      List<List<String>> trie(List<List<String>> lignes) => [...lignes]
        ..sort((a, b) {
          String iso(String d) => d.split('/').reversed.join();
          final parJour = iso(b[1]).compareTo(iso(a[1]));
          return parJour != 0 ? parJour : a[2].compareTo(b[2]);
        });

      final web = trie([
        for (final l in sortie['lignes'] as List) (l as List).cast<String>(),
      ]);
      final poste = trie([for (final l in d.elevageT3) l.cellules]);

      expect(poste, web);
      // La grille couvre ce qu'elle prétend couvrir.
      expect(web.length, greaterThan(10));
      expect(web.where((l) => l[4] == '— %'), isNotEmpty, reason: 'effectif nul');
      expect(web.where((l) => l[5] == ''), isNotEmpty, reason: 'casses absentes');
      expect(web.where((l) => l[0].startsWith('-')), isNotEmpty, reason: 'âge négatif');
      expect(web.where((l) => l[10].contains('vrac')), isNotEmpty);
      expect(web.where((l) => l[7] != '0'), isNotEmpty, reason: 'un SRH non nul');
      expect(web.where((l) => l[9] != '0'), isNotEmpty, reason: 'une sortie de vente');
      final jours = web.map((l) => l[1]).toList();
      expect(jours.toSet().length, lessThan(jours.length), reason: 'deux bandes le même jour');
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Crée le jeu dans Laravel (SQLite en mémoire), fait rendre le Tableau 3 par le VRAI composant et sa vue, et rend
/// chaque ligne du tableau, cellule par cellule (texte du HTML, espaces normalisés).
const _script = r'''
$entree = json_decode(file_get_contents($argv[1]), true);
Carbon\Carbon::setTestNow('2026-08-25 14:30:00');
$espece = App\Models\LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true]);
$categorie = App\Models\ProductCategory::create(['label' => 'Produits', 'is_active' => true]);
$produits = [];
foreach ($entree['produits'] as $i => $nom) {
    $produits[$i] = App\Models\Product::create([
        'sku' => 'P'.$i, 'name' => $nom, 'category_id' => $categorie->id, 'unit' => 'plateau', 'pricing_mode' => 'fourchette',
        'price_min' => 1, 'price_max' => 100000, 'stock_qty' => 0, 'is_active' => true,
    ]);
}
$bandes = [];
foreach ($entree['bandes'] as $i => $b) {
    $bandes[$i] = App\Models\LivestockLot::create([
        'code' => $b['code'], 'species_id' => $espece->id, 'stage' => 'ponte',
        'initial_quantity' => 400, 'current_quantity' => 400, 'created_date' => $b['creee'],
        'status' => 'actif', 'is_active' => true,
    ]);
}
foreach ($entree['fiches'] as $f) {
    $e = new App\Models\LivestockDailyEntry([
        'lot_id' => $bandes[$f['bande']]->id, 'entry_date' => $f['date'], 'effectif_final' => $f['effectif'],
        'ponte_total' => $f['ponte'], 'ponte_casses' => $f['casses'],
    ]);
    $e->save();
}
foreach ($entree['mouvements'] as $m) {
    App\Models\StockMovement::create([
        'product_id' => $produits[$m['produit']]->id, 'type' => $m['type'], 'quantity' => $m['qty'],
        'reference_type' => $m['ref'], 'movement_date' => $m['date'],
    ]);
}
$html = Livewire\Livewire::test(App\Livewire\Rapports\ElevageSynth::class, ['startDate' => '2026-07-01', 'endDate' => '2026-07-31'])
    ->set('activeTable', 't3')
    ->html();
$doc = new DOMDocument();
@$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
$lignes = [];
foreach ($doc->getElementsByTagName('tbody') as $tbody) {
    foreach ($tbody->getElementsByTagName('tr') as $tr) {
        $cellules = [];
        foreach ($tr->getElementsByTagName('td') as $td) {
            $cellules[] = trim(preg_replace('/\s+/u', ' ', $td->textContent));
        }
        if (count($cellules) === 11) {
            $lignes[] = $cellules;
        }
    }
}
echo json_encode(['lignes' => $lignes], JSON_UNESCAPED_UNICODE);
''';
