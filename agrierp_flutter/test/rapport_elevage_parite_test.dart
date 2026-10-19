import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/rapports/rapports_exports_screen.dart';
import 'package:agrierp/features/rapports/rapports_repository.dart';
import 'package:agrierp/features/stocks/pmp_service.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket U10 — RAPPORT ÉLEVAGE : TABLEAUX 1 ET 2, INDICATEURS ET FILTRE « LOT / SOUCHE » DU BLADE.
///
/// 1. **Lu dans le Blade** (`elevage-synth.blade.php`, sans PHP) : colonnes des trois tableaux dans leur ordre,
///    libellés des pilules, option « Lot / Souche : Tous » — et leur présence dans l'écran du poste.
/// 2. **Parité exécutée** : Laravel REND les Tableaux 1 et 2 et les quatre indicateurs (`Livewire::test(ElevageSynth)`,
///    base SQLite en mémoire), sans filtre puis filtré sur une bande ; le poste ([RapportsRepository.charger]) doit
///    produire les MÊMES cellules et les MÊMES valeurs sur le même jeu : ventilation absente, sexe et montant de vente
///    (absents compris), traitement d'un produit, dose, symptômes (« », « 0 », absents → « RAS »), fiches hors
///    période (fiche précédente de la mortalité), bandes à effectif initial, fiche à effectif nul.
void main() {
  final blade = File(
    '$dossierLaravel/resources/views/livewire/rapports/elevage-synth.blade.php',
  );
  final ecran = File('lib/features/rapports/rapports_exports_screen.dart');

  String decoder(String html) => html
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Colonnes `<th>` du bloc `@if($activeTable === '…')` du Blade.
  List<String> colonnesBlade(String source, String table) {
    final debut = source.indexOf("@if(\$activeTable === '$table')");
    final fin = source.indexOf('@endif', debut);
    final bloc = source.substring(debut, fin);
    return [
      for (final m in RegExp(
        r'<th[^>]*>(.*?)</th>',
        dotAll: true,
      ).allMatches(bloc))
        decoder(m[1]!),
    ];
  }

  /// Colonnes déclarées par l'écran du poste pour le tableau de clé [cle].
  List<String> colonnesPoste(String source, String cle) {
    final debut = source.indexOf("cle: '$cle'");
    final liste = source.indexOf('colonnes: const [', debut);
    final fin = source.indexOf('],', liste);
    return [
      for (final m in RegExp(
        r"\('([^']*)', \d+\)",
      ).allMatches(source.substring(liste, fin)))
        m[1]!,
    ];
  }

  group('lu dans le Blade', () {
    test(
      'U10 — les trois tableaux du poste ont les colonnes du Blade, dans son ordre',
      () {
        final b = blade.readAsStringSync();
        final e = ecran.readAsStringSync();
        for (final (table, cle) in [
          ('t1', 'tableau-elevage-t1'),
          ('t2', 'tableau-elevage-t2'),
          ('t3', 'tableau-elevage-t3'),
        ]) {
          final web = colonnesBlade(b, table);
          expect(web, isNotEmpty, reason: table);
          expect(colonnesPoste(e, cle), web, reason: table);
        }
        // Témoin écrit à la main : le Tableau 1 du Blade (et non les treize colonnes de la maquette).
        expect(colonnesBlade(b, 't1'), [
          'Date',
          'Lot / Souche',
          'Effectif M',
          'Effectif F',
          'Sous Mères',
          'Sevrés',
          'Achats',
          'Nés',
          'Morts',
          'Effectif Final',
        ]);
      },
      skip: blade.existsSync()
          ? null
          : 'SAUT : vue Blade absente ($dossierLaravel)',
    );

    test(
      'U10 — pilules, filtre et indicateurs : libellés du Blade',
      () {
        final b = blade.readAsStringSync();
        final e = ecran.readAsStringSync();
        final pilules = [
          for (final m in RegExp(
            r"\$set\('activeTable', 't\d'\)[^>]*>(.*?)</button>",
            dotAll: true,
          ).allMatches(b))
            decoder(m[1]!),
        ];
        expect(pilules, RapportsExportsScreen.tableauxElevage);
        expect(pilules, [
          'Tableau 1 : Recensement',
          'Tableau 2 : Mouvements, Traitements & Ventes',
          'Tableau 3 : Suivi de la Ponte',
        ]);
        expect(b, contains('Lot / Souche : Tous'));
        expect(e, contains("'Lot / Souche : Tous'"));
        for (final libelle in [
          'Production Totale (Œufs)',
          'Taux de Ponte Moyen',
          'Taux de Mortalité Hebdo',
          'CA Ventes du Lot',
          'Aucune fiche journalière sur la période.',
          'Formule : Taux Mortalité Hebdo (%) = (Cumul Morts ÷ Effectif Début) × 100',
        ]) {
          expect(b, contains(libelle), reason: libelle);
          expect(e, contains(libelle), reason: libelle);
        }
      },
      skip: blade.existsSync()
          ? null
          : 'SAUT : vue Blade absente ($dossierLaravel)',
    );
  });

  test(
    'parité exécutée U10 : Tableaux 1 et 2 et indicateurs du poste = ceux rendus par le Blade, avec et sans filtre',
    () async {
      var graine = 1709;
      int hasard(int n) =>
          ((graine = (graine * 1103515245 + 12345) & 0x7fffffff) >> 16) % n;
      String jour(int mois, int j) =>
          '2026-${mois.toString().padLeft(2, '0')}-${j.toString().padLeft(2, '0')}';
      String uuid(String g) => g.padRight(36, '0').substring(0, 36);

      final bandes = [
        {'code': 'PON-A', 'initial': 500},
        {'code': 'LAP-B', 'initial': 0},
        {'code': 'POR-C', 'initial': 80},
      ];
      final produits = ['Ivermectine 1 %', 'Vitamines AD3E'];
      final fiches = <Map<String, Object?>>[];
      final vus = <String>{};
      // Fiche la plus ancienne de juillet UNIQUE (le web ne définit pas l'ordre de deux fiches du même jour) : PON-A
      // le 2 juillet ; aucune autre fiche de juillet avant le 3.
      fiches.add({
        'bande': 0,
        'date': jour(7, 2),
        'achat': 0,
        'ne': 0,
        'mort': 4,
        'vente': 3,
        'effectif': 470,
        'ponte': 300,
        'm': 20,
        'f': 450,
        'smeres': null,
        'sevres': null,
        'sexe': 'F',
        'montant': 12345.5,
        'traitement': 0,
        'dose': '2 ml',
        'symptomes': 'Toux',
      });
      vus.add('0 ${jour(7, 2)}');
      for (var i = 0; i < 40; i++) {
        final b = hasard(3);
        final mois = i % 8 == 0 ? 6 : (i % 13 == 0 ? 8 : 7);
        final j = mois == 7 ? 3 + hasard(29) : 1 + hasard(28);
        final date = jour(mois, j);
        if (!vus.add('$b $date')) continue;
        fiches.add({
          'bande': b,
          'date': date,
          'achat': hasard(4),
          'ne': hasard(3),
          'mort': hasard(5),
          'vente': hasard(6),
          'effectif': i % 9 == 4 ? 0 : 50 + hasard(450),
          'ponte': hasard(3) == 0
              ? null
              : (hasard(4) == 0 ? 0 : 20 + hasard(400)),
          'm': hasard(3) == 0 ? null : hasard(200),
          'f': hasard(3) == 0 ? null : hasard(200),
          'smeres': hasard(2) == 0 ? null : hasard(50),
          'sevres': hasard(2) == 0 ? null : hasard(50),
          'sexe': [null, 'M', 'F', 'Mixte'][hasard(4)],
          'montant': hasard(3) == 0 ? null : (hasard(2000000) / 100),
          'traitement': hasard(3) == 0 ? hasard(2) : null,
          'dose': [null, '', '1 ml/kg'][hasard(3)],
          'symptomes': [null, '', '0', 'Diarrhée légère'][hasard(4)],
        });
      }

      final sortie =
          executerPhp('<?php\n$amorceApplication\n$_script', {
                'bandes': bandes,
                'produits': produits,
                'fiches': fiches,
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
                sku: 'V$i',
                name: produits[i],
                unit: 'flacon',
                pricingMode: 'fixe',
              ),
            );
      }
      for (var b = 0; b < bandes.length; b++) {
        await db
            .into(db.livestockLots)
            .insert(
              LivestockLotsCompanion.insert(
                id: uuid('bande-$b-'),
                code: bandes[b]['code']! as String,
                speciesId: uuid('espece'),
                speciesCode: const Value('aviculture'),
                stage: const Value('ponte'),
                initialQuantity: Value(bandes[b]['initial']! as int),
              ),
            );
      }
      for (var f = 0; f < fiches.length; f++) {
        final x = fiches[f];
        final t = x['traitement'] as int?;
        await db
            .into(db.livestockDailyEntries)
            .insert(
              LivestockDailyEntriesCompanion.insert(
                id: uuid('fiche-$f-'),
                deviceId: 'serveur',
                syncStatus: const Value(SyncStatus.synced),
                updatedAt: DateTime(2026, 8, 1),
                lotId: uuid('bande-${x['bande']}-'),
                entryDate: DateTime.parse(x['date']! as String),
                achat: Value(x['achat']! as int),
                ne: Value(x['ne']! as int),
                mort: Value(x['mort']! as int),
                vente: Value(x['vente']! as int),
                effectifFinal: Value(x['effectif']! as int),
                ponteTotal: Value(x['ponte'] as int?),
                effectifM: Value(x['m'] as int?),
                effectifF: Value(x['f'] as int?),
                effectifSmeres: Value(x['smeres'] as int?),
                effectifSevres: Value(x['sevres'] as int?),
                venteSexe: Value(x['sexe'] as String?),
                venteMontant: Value((x['montant'] as num?)?.toDouble()),
                treatmentProductId: Value(
                  t == null ? null : uuid('produit-$t-'),
                ),
                treatmentDose: Value(x['dose'] as String?),
                symptomes: Value(x['symptomes'] as String?),
              ),
            );
      }

      final depot = RapportsRepository(database: db);

      // L'ordre de deux fiches du même jour n'est pas défini au web : lignes triées par jour décroissant puis bande.
      List<List<String>> trie(List<List<String>> lignes) =>
          [...lignes]..sort((a, b) {
            String iso(String d) => d.split('/').reversed.join();
            final parJour = iso(b[0]).compareTo(iso(a[0]));
            return parJour != 0 ? parJour : a[1].compareTo(b[1]);
          });
      List<List<String>> lignes(Object? brut) => [
        for (final l in brut! as List) (l as List).cast<String>(),
      ];

      for (final (cas, filtre) in [
        ('toutes', ''),
        ('PON-A', uuid('bande-0-')),
      ]) {
        final web = (sortie[cas] as Map).cast<String, dynamic>();
        final d = await depot.charger(
          du: DateTime(2026, 7, 1),
          au: DateTime(2026, 7, 31),
          lot: filtre,
        );

        expect(
          trie([for (final l in d.elevageT1) l.cellules]),
          trie(lignes(web['t1'])),
          reason: '$cas — Tableau 1',
        );
        expect(
          trie([for (final l in d.elevageT2) l.cellules]),
          trie(lignes(web['t2'])),
          reason: '$cas — Tableau 2',
        );
        expect(
          [
            PmpService.francs(d.indicateurs.productionTotale.toDouble()),
            IndicateursElevage.taux(d.indicateurs.tauxPonteMoyen),
            IndicateursElevage.taux(d.indicateurs.mortaliteHebdo),
            '${PmpService.francs(d.indicateurs.chiffreAffaires)} FCFA',
          ],
          (web['kpis'] as List).cast<String>(),
          reason: '$cas — indicateurs',
        );
      }

      // La grille couvre ce qu'elle prétend couvrir.
      final t1 = lignes((sortie['toutes'] as Map)['t1']);
      final t2 = lignes((sortie['toutes'] as Map)['t2']);
      expect(t1.length, greaterThan(15));
      expect(
        t1.where((l) => l[2] == ''),
        isNotEmpty,
        reason: 'ventilation absente',
      );
      expect(t2.where((l) => l[2] == '—'), isNotEmpty, reason: 'sexe absent');
      expect(
        t2.where((l) => l[4] == '0'),
        isNotEmpty,
        reason: 'montant absent',
      );
      expect(
        t2.where((l) => l[6] == 'Vitamines AD3E' || l[6] == 'Ivermectine 1 %'),
        isNotEmpty,
      );
      expect(t2.where((l) => l[7] == ''), isNotEmpty, reason: 'dose vide');
      expect(t2.where((l) => l[8] == 'RAS'), isNotEmpty);
      expect(
        ((sortie['toutes'] as Map)['kpis'] as List)[2],
        isNot('—'),
        reason: 'une mortalité calculée',
      );
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Crée le jeu dans Laravel (SQLite en mémoire), fait rendre les Tableaux 1 et 2 et les indicateurs par le VRAI
/// composant et sa vue, sans filtre puis filtré sur la première bande, et rend chaque cellule (texte, espaces
/// normalisés).
const _script = r'''
$entree = json_decode(file_get_contents($argv[1]), true);
Carbon\Carbon::setTestNow('2026-08-25 14:30:00');
$espece = App\Models\LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true]);
$categorie = App\Models\ProductCategory::create(['label' => 'Pharmacie', 'is_active' => true]);
$produits = [];
foreach ($entree['produits'] as $i => $nom) {
    $produits[$i] = App\Models\Product::create([
        'sku' => 'V'.$i, 'name' => $nom, 'category_id' => $categorie->id, 'unit' => 'flacon', 'pricing_mode' => 'fourchette',
        'price_min' => 1, 'price_max' => 100000, 'stock_qty' => 0, 'is_active' => true,
    ]);
}
$bandes = [];
foreach ($entree['bandes'] as $i => $b) {
    $bandes[$i] = App\Models\LivestockLot::create([
        'code' => $b['code'], 'species_id' => $espece->id, 'stage' => 'ponte',
        'initial_quantity' => $b['initial'], 'current_quantity' => $b['initial'], 'created_date' => '2026-01-05',
        'status' => 'actif', 'is_active' => true,
    ]);
}
foreach ($entree['fiches'] as $f) {
    $e = new App\Models\LivestockDailyEntry([
        'lot_id' => $bandes[$f['bande']]->id, 'entry_date' => $f['date'], 'achat' => $f['achat'], 'ne' => $f['ne'],
        'mort' => $f['mort'], 'vente' => $f['vente'], 'effectif_final' => $f['effectif'], 'ponte_total' => $f['ponte'],
        'effectif_m' => $f['m'], 'effectif_f' => $f['f'], 'effectif_smeres' => $f['smeres'], 'effectif_sevres' => $f['sevres'],
        'vente_sexe' => $f['sexe'], 'vente_montant' => $f['montant'],
        'treatment_product_id' => $f['traitement'] === null ? null : $produits[$f['traitement']]->id,
        'treatment_dose' => $f['dose'], 'symptomes' => $f['symptomes'],
    ]);
    $e->save();
}
function cellules(string $html, int $colonnes): array {
    $doc = new DOMDocument();
    @$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
    $lignes = [];
    foreach ($doc->getElementsByTagName('tbody') as $tbody) {
        foreach ($tbody->getElementsByTagName('tr') as $tr) {
            $c = [];
            foreach ($tr->getElementsByTagName('td') as $td) {
                $c[] = trim(preg_replace('/\s+/u', ' ', $td->textContent));
            }
            if (count($c) === $colonnes) {
                $lignes[] = $c;
            }
        }
    }
    return $lignes;
}
function indicateurs(string $html): array {
    $doc = new DOMDocument();
    @$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
    $x = new DOMXPath($doc);
    $valeurs = [];
    foreach ($x->query("//span[contains(@class, 'md:text-2xl')]") as $span) {
        $valeurs[] = trim(preg_replace('/\s+/u', ' ', $span->textContent));
    }
    return $valeurs;
}
$sortie = [];
foreach (['toutes' => '', 'PON-A' => $bandes[0]->id] as $cas => $lot) {
    $composant = Livewire\Livewire::test(App\Livewire\Rapports\ElevageSynth::class, ['startDate' => '2026-07-01', 'endDate' => '2026-07-31'])
        ->set('lotFilter', $lot);
    $t1 = $composant->set('activeTable', 't1')->html();
    $t2 = $composant->set('activeTable', 't2')->html();
    $sortie[$cas] = ['t1' => cellules($t1, 10), 't2' => cellules($t2, 9), 'kpis' => indicateurs($t1)];
}
echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
''';
