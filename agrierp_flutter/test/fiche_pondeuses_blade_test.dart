import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/features/elevage/mois_pondeuses.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket U11 — FICHE PONDEUSES : LE BLADE FAIT FOI (doctrine, article 5).
///
/// 1. **Lu dans le Blade** (`fiche-pondeuses.blade.php`, sans PHP) : sections dans leur ordre, libellés des champs,
///    cartes, colonnes du tableau du mois, note, textes d'aide — tous présents dans l'écran du poste ; ce que le Blade
///    n'a pas (« Réinitialiser », « Attribution Bâtiments… ») n'y est plus.
/// 2. **Parité exécutée** : le VRAI composant `FichePondeuses` rend le tableau du mois (tous les jours, « Traitements
///    & Rappels » compris) et les quatre cartes, sur deux bandes, avec des soins actifs et archivés, des fiches sans
///    ponte, des symptômes « », « 0 », un produit de traitement ; le PDF du mois passe par la vue d'export du web.
///    [MoisPondeuses] doit rendre les MÊMES cellules.
void main() {
  final blade = File(
    '$dossierLaravel/resources/views/livewire/elevage/fiche-pondeuses.blade.php',
  );
  final ecran = File('lib/features/elevage/fiche_pondeuses_screen.dart');
  final saut = blade.existsSync()
      ? null
      : 'SAUT : vue Blade absente ($dossierLaravel)';

  String texte(String html) => html
      .replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Littéraux de l'écran, recollés quand ils sont coupés sur deux lignes, en minuscules (l'écran met en capitales
  /// à l'affichage, comme `uppercase`).
  String litterauxEcran() => ecran
      .readAsStringSync()
      .replaceAll(RegExp(r'''["']\s*\n\s*["']'''), '')
      .replaceAll(r"\'", "'")
      .toLowerCase();

  group('lu dans le Blade', () {
    test(
      '⚠️ U11 — les sections du Blade, dans son ordre, sont celles de l écran',
      () {
        final b = blade.readAsStringSync();
        final e = litterauxEcran();
        const sections = [
          'Fiches Pondeuses - Aviculture',
          "Suivi quotidien de la ponte et récolte d'œufs — transcription fidèle du registre de la ferme.",
          'Exporter PDF',
          'Saisie Journalière Ponte &amp; Cheptel',
          'Achats / Entrées du jour',
          "Workflow Récolte &amp; Stock d'Œufs",
          'Morts par catégorie',
          'Dons par catégorie',
          'Effectif Final du Jour',
          'x-ration-volaille',
          'Poids Général Pesé (g)',
          'Stock Œufs &amp; Plateaux (30) — Jour Sélectionné',
          'Traitements &amp; Rappels</p>',
          'Observations',
          'Enregistrer ce Jour',
          'Cheptel du Jour',
        ];
        var precedent = -1;
        for (final s in sections) {
          final i = b.indexOf(s, precedent + 1);
          expect(i, greaterThan(precedent), reason: 'ordre du Blade : $s');
          precedent = i;
          if (s == 'x-ration-volaille') continue;
          final libelle = texte(s).toLowerCase();
          expect(e, contains(libelle), reason: 'écran : $s');
        }
      },
      skip: saut,
    );

    test(
      'U11 — chaque libellé de champ du Blade est dans l écran',
      () {
        final b = blade.readAsStringSync();
        final e = litterauxEcran();
        final libelles = {
          for (final m in RegExp(
            r'<label[^>]*>(.*?)</label>',
            dotAll: true,
          ).allMatches(b))
            texte(m[1]!),
        };
        expect(libelles, contains('Taux de Ponte Calculé (%)'));
        for (final l in libelles) {
          // « Ventes (POS, réel) » : libellé et précision en petits caractères, écrits à part à l'écran.
          final morceaux = RegExp(r'^(.*?)\s*(\([^()]*(\([^()]*\))?[^()]*\))?$').firstMatch(l)!;
          final principal = morceaux[1]!.toLowerCase();
          final precision = morceaux[2]?.toLowerCase();
          final complet = l.toLowerCase();
          expect(
            e.contains("'$complet'") ||
                (e.contains("'$principal'") &&
                    (precision == null || e.contains("'$precision'"))),
            isTrue,
            reason: l,
          );
        }
        for (final indice in ['ex : 1800', 'ex : RAS']) {
          expect(b, contains('placeholder="$indice"'));
          expect(e, contains("'${indice.toLowerCase()}'"), reason: indice);
        }
      },
      skip: saut,
    );

    test(
      'U11 — cartes, colonnes du tableau du mois, note et mentions : celles du Blade',
      () {
        final b = blade.readAsStringSync();
        final e = litterauxEcran();
        final cartes = [
          for (final m in RegExp(r'<x-kpi-card label="([^"]+)"').allMatches(b))
            m[1]!,
        ];
        expect(cartes.toSet(), {
          'Effectif Pondeuses Vivantes',
          'Taux de Ponte Moyen',
          'Stock Plateaux (30 œufs)',
          'Taux de Mortalité',
        });
        for (final c in cartes) {
          expect(e, contains("'${c.toLowerCase()}'"), reason: c);
        }

        final thead = b.substring(b.indexOf('<thead'), b.indexOf('</thead>'));
        final colonnes = [
          for (final m in RegExp(r'<th[^>]*>(.*?)</th>').allMatches(thead))
            texte(m[1]!),
        ];
        expect(colonnes, [
          'Date / Jour',
          'Cheptel du Jour',
          'Suivi de la Ponte & Récolte',
          'Stock Œufs & Plateaux (30)',
          'Traitements & Rappels',
          'Eff. Début',
          'Morts',
          'Taux Mort %',
          'Eff. Fin',
          'Total (OR)',
          'Taux Ponte %',
          'Cassés (OF)',
          'Comm. (OR-OF)',
          'SRH',
          'TS',
          'OS',
          'Stock Final',
        ]);
        for (final c in colonnes) {
          expect(e, contains("'${c.toLowerCase()}'"), reason: c);
        }

        for (final m in [
          RegExp(r'<p class="text-\[10px\] text-outline p-sm border-t[^"]*">(.*?)</p>', dotAll: true),
          RegExp(r'<p class="text-sm font-semibold[^"]*">(.*?)</p>'),
        ]) {
          final t = texte(m.firstMatch(b)![1]!);
          expect(e, contains(t.toLowerCase()), reason: t);
        }
        for (final t in [
          'Créer une bande depuis Bandes & Sujets →',
          "Aucun produit \"Œufs de table\" trouvé au catalogue — le stock ne sera pas incrémenté.",
          '= Effectif (J-1) + Achats/Nés − (Morts + Ventes + Dons)',
          '= (Morts du Jour ÷ Effectif J-1) × 100',
          'Plateaux Nets Générés (30 œufs/plateau) :',
          'Incrémentation Automatique du Stock :',
        ]) {
          expect(texte(b), contains(t), reason: 'Blade : $t');
          expect(e, contains(t.toLowerCase()), reason: 'écran : $t');
        }
        // Ce que la maquette avait et que le Blade n'a pas : absent des LITTÉRAUX de l'écran (ses commentaires le
        // citent pour dire pourquoi).
        final source = ecran.readAsStringSync();
        final litteraux = [
          for (final motif in [
            RegExp(r"'((?:[^'\\\n]|\\.)*)'"),
            RegExp(r'"((?:[^"\\\n]|\\.)*)"'),
          ])
            for (final m in motif.allMatches(source)) m[1]!.toLowerCase(),
        ].join('\n');
        for (final absent in ['Réinitialiser', 'Attribution Bâtiments', 'Pré-rempli de J-1', 'COMBINE LES FICHES']) {
          expect(b.toLowerCase(), isNot(contains(absent.toLowerCase())), reason: absent);
          expect(litteraux, isNot(contains(absent.toLowerCase())), reason: absent);
        }
      },
      skip: saut,
    );
  });

  test(
    'parité exécutée U11 : tableau du mois, « Traitements & Rappels », cartes et PDF = ceux du web',
    () async {
      var graine = 2026;
      int hasard(int n) =>
          ((graine = (graine * 1103515245 + 12345) & 0x7fffffff) >> 16) % n;
      String uuid(String g) => g.padRight(36, '0').substring(0, 36);
      String jour(int mois, int j) =>
          '2026-${mois.toString().padLeft(2, '0')}-${j.toString().padLeft(2, '0')}';

      final bandes = [
        {'id': uuid('bande-a-'), 'code': 'PON-A', 'initial': 500, 'courant': 463},
        {'id': uuid('bande-b-'), 'code': 'PON-B', 'initial': 300, 'courant': 291},
      ];
      final produits = [
        {'id': uuid('produit-0-'), 'nom': 'Œufs de table (plateau)', 'stock': 47.6},
        {'id': uuid('produit-1-'), 'nom': 'Ivermectine 1 %', 'stock': 0},
        {'id': uuid('produit-2-'), 'nom': 'Vitamines AD3E', 'stock': 0},
      ];
      final fiches = <Map<String, Object?>>[];
      // ⚠️ Pas de fiche le 1er octobre : `entry_date` est rangée « 2026-10-01 » (`date:Y-m-d`) et, sur SQLite, le
      // `whereBetween('entry_date', [now()->startOfMonth(), …])` du web compare des CHAÎNES (« 2026-10-01 » <
      // « 2026-10-01 00:00:00 ») et l'exclut ; MySQL (colonne DATE, la production) l'inclut — comme le poste.
      for (var b = 0; b < bandes.length; b++) {
        for (final (mois, j) in [
          for (var d = 24; d <= 30; d++) (9, d),
          for (var d = 2; d <= 31; d++) (10, d),
        ]) {
          if (hasard(10) < 4) continue;
          fiches.add({
            'id': uuid('fiche-$b-$mois-$j-'),
            'bande': b,
            'date': jour(mois, j),
            'achat': hasard(3),
            'ne': hasard(2),
            'mort': hasard(5) == 0 ? 0 : hasard(6),
            'vente': hasard(4),
            'don': hasard(3),
            'effectif': hasard(15) == 0 ? 0 : 250 + hasard(250),
            'ponte': hasard(5) == 0 ? null : hasard(480),
            'casses': hasard(5) == 0 ? null : hasard(20),
            'traitement': hasard(6) == 0 ? 1 + hasard(2) : null,
            'symptomes': [null, '', '0', 'Toux', 'Plumes ternies'][hasard(5)],
          });
        }
      }
      // ⚠️ Pas de soin le 31 : sur SQLite, `whereBetween('record_date', ['…-01', '…-31'])` du web exclut
      // « 2026-10-31 00:00:00 » (comparaison de chaînes) ; MySQL, lui, l'inclut — comme le poste.
      final soins = <Map<String, Object?>>[];
      for (var s = 0; s < 45; s++) {
        soins.add({
          'id': uuid('soin-$s-'),
          'bande': hasard(4) == 0 ? 1 : 0,
          'date': jour(10, 1 + hasard(30)),
          'type': ['Vaccination', 'Déparasitage', 'Vitamines', '', '0', 'Vaccination'][hasard(6)],
          'produit': [null, '', '0', 'Newcastle', 'Ivermectine'][hasard(5)],
          'actif': hasard(5) != 0,
          // Instant de saisie, croissant (ordre `created_at` du web).
          'cree': '2026-10-${(1 + s ~/ 2).toString().padLeft(2, '0')} ${(8 + s % 2).toString().padLeft(2, '0')}:00:00',
        });
      }

      final sortie =
          executerPhp('<?php\n$amorceApplication\n$_script', {
                'bandes': bandes,
                'produits': produits,
                'fiches': fiches,
                'soins': soins,
              }, application: true)
              as Map<String, dynamic>;

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      for (final p in produits) {
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: p['id']! as String,
                sku: p['id']! as String,
                name: p['nom']! as String,
                unit: 'u',
                pricingMode: 'fixe',
                stockQty: Value((p['stock']! as num).toDouble()),
              ),
            );
      }
      final lots = <LivestockLot>[];
      for (final b in bandes) {
        await db
            .into(db.livestockLots)
            .insert(
              LivestockLotsCompanion.insert(
                id: b['id']! as String,
                code: b['code']! as String,
                speciesId: uuid('espece'),
                speciesCode: const Value('aviculture'),
                stage: const Value('ponte'),
                status: const Value('actif'),
                createdDate: Value(DateTime(2026, 1, 5)),
                initialQuantity: Value(b['initial']! as int),
                currentQuantity: Value(b['courant']! as int),
              ),
            );
      }
      lots.addAll(await db.select(db.livestockLots).get());
      lots.sort((a, b) => a.code.compareTo(b.code));
      for (final f in fiches) {
        final t = f['traitement'] as int?;
        await db
            .into(db.livestockDailyEntries)
            .insert(
              LivestockDailyEntriesCompanion.insert(
                id: f['id']! as String,
                deviceId: 'serveur',
                syncStatus: const Value(SyncStatus.synced),
                updatedAt: DateTime(2026, 10, 20),
                lotId: bandes[f['bande']! as int]['id']! as String,
                entryDate: DateTime.parse(f['date']! as String),
                achat: Value(f['achat']! as int),
                ne: Value(f['ne']! as int),
                mort: Value(f['mort']! as int),
                vente: Value(f['vente']! as int),
                don: Value(f['don']! as int),
                effectifFinal: Value(f['effectif']! as int),
                ponteTotal: Value(f['ponte'] as int?),
                ponteCasses: Value(f['casses'] as int?),
                treatmentProductId: Value(t == null ? null : produits[t]['id']! as String),
                symptomes: Value(f['symptomes'] as String?),
              ),
            );
      }
      for (final s in soins) {
        await db
            .into(db.veterinaryRecords)
            .insert(
              VeterinaryRecordsCompanion.insert(
                id: s['id']! as String,
                deviceId: 'serveur',
                syncStatus: const Value(SyncStatus.synced),
                updatedAt: DateTime.parse(s['cree']! as String),
                lotId: bandes[s['bande']! as int]['id']! as String,
                actionType: s['type']! as String,
                productUsed: Value(s['produit'] as String?),
                recordDate: DateTime.parse(s['date']! as String),
                isActive: Value(s['actif']! as bool),
              ),
            );
      }

      final maintenant = DateTime(2026, 10, 20, 10);
      for (var b = 0; b < bandes.length; b++) {
        final web = (sortie[bandes[b]['code']] as Map).cast<String, dynamic>();
        final d = await MoisPondeuses.charger(
          db,
          bandes: lots,
          bande: lots[b],
          maintenant: maintenant,
        );
        final lignesWeb = [for (final l in web['lignes'] as List) (l as List).cast<String>()];
        expect(lignesWeb, hasLength(31), reason: 'tous les jours d octobre');
        expect(d.jours, hasLength(31));
        for (var i = 0; i < 31; i++) {
          final w = lignesWeb[i];
          final p = d.jours[i];
          expect(
            [p.date, ...p.cellules, p.traitements],
            [...w.take(9), w[13]],
            reason: '${bandes[b]['code']} — ligne ${w[0]}',
          );
          if (i != 19) {
            expect(w.sublist(9, 13), List.filled(4, '—'), reason: 'grand livre hors du jour choisi');
          }
        }
        expect(
          [
            d.indicateurs.effectif,
            d.indicateurs.tauxPonteMoyen,
            d.indicateurs.stockPlateaux ?? '—',
            d.indicateurs.tauxMortaliteMois,
          ],
          (web['cartes'] as List).cast<String>(),
          reason: '${bandes[b]['code']} — cartes',
        );
        // PDF : la vue d'export du web, cellule par cellule ; sous-titre et nom du fichier.
        expect(d.document.sousTitre, web['periode']);
        expect(
          [
            for (final l in d.document.lignes) (l as DonneesDocument).cellules,
          ],
          [for (final l in web['pdf'] as List) (l as List).cast<String>()],
          reason: '${bandes[b]['code']} — PDF',
        );
        expect(DocumentOfficiel.nomPdf(d.document, maintenant), web['fichier']);
      }

      // La grille couvre ce qu'elle prétend couvrir.
      final a = [
        for (final l in (sortie['PON-A'] as Map)['lignes'] as List) (l as List).cast<String>(),
      ];
      final traitements = [for (final l in a) l[13]];
      expect(traitements.where((t) => t.contains(', ')), isNotEmpty, reason: 'deux soins le même jour');
      expect(traitements.where((t) => t.contains('(')), isNotEmpty, reason: 'un produit de soin');
      expect(traitements.where((t) => t == 'Toux' || t == 'Plumes ternies'), isNotEmpty, reason: 'symptômes');
      expect(a.where((l) => l[1] == '—'), isNotEmpty, reason: 'un jour sans fiche');
      expect(a.where((l) => l[5] == '—' && l[1] != '—'), isNotEmpty, reason: 'une fiche sans ponte');
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Crée le jeu dans Laravel (SQLite en mémoire), puis, pour chaque bande, fait rendre la fiche Pondeuses par le VRAI
/// composant (bande choisie, 20/10/2026) : lignes du tableau du mois (14 cellules), valeurs des quatre cartes, et les
/// lignes du PDF du mois rendues par la vue d'export du web.
const _script = r'''
$entree = json_decode(file_get_contents($argv[1]), true);
Carbon\Carbon::setTestNow('2026-10-20 10:00:00');
$espece = App\Models\LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true]);
$categorie = App\Models\ProductCategory::create(['label' => 'Produits', 'is_active' => true]);
$produits = [];
foreach ($entree['produits'] as $i => $p) {
    $produit = new App\Models\Product([
        'sku' => 'P'.$i, 'name' => $p['nom'], 'category_id' => $categorie->id, 'unit' => 'u', 'pricing_mode' => 'fourchette',
        'price_min' => 1, 'price_max' => 100000, 'stock_qty' => $p['stock'], 'is_active' => true,
    ]);
    $produit->id = $p['id'];
    $produit->save();
    $produits[$i] = $produit;
}
$bandes = [];
foreach ($entree['bandes'] as $i => $b) {
    $bande = new App\Models\LivestockLot([
        'code' => $b['code'], 'species_id' => $espece->id, 'stage' => 'ponte', 'initial_quantity' => $b['initial'],
        'current_quantity' => $b['courant'], 'created_date' => '2026-01-05', 'status' => 'actif', 'is_active' => true,
    ]);
    $bande->id = $b['id'];
    $bande->save();
    $bandes[$i] = $bande;
}
foreach ($entree['fiches'] as $f) {
    $e = new App\Models\LivestockDailyEntry([
        'lot_id' => $bandes[$f['bande']]->id, 'entry_date' => $f['date'], 'achat' => $f['achat'], 'ne' => $f['ne'],
        'mort' => $f['mort'], 'vente' => $f['vente'], 'don' => $f['don'], 'effectif_final' => $f['effectif'],
        'ponte_total' => $f['ponte'], 'ponte_casses' => $f['casses'],
        'treatment_product_id' => $f['traitement'] === null ? null : $produits[$f['traitement']]->id,
        'symptomes' => $f['symptomes'],
    ]);
    $e->id = $f['id'];
    $e->save();
}
foreach ($entree['soins'] as $s) {
    Carbon\Carbon::setTestNow($s['cree']);
    $r = new App\Models\VeterinaryRecord([
        'lot_id' => $bandes[$s['bande']]->id, 'action_type' => $s['type'], 'product_used' => $s['produit'],
        'record_date' => $s['date'], 'is_active' => $s['actif'],
    ]);
    $r->id = $s['id'];
    $r->save();
}
Carbon\Carbon::setTestNow('2026-10-20 10:00:00');
function cellulesDe(DOMXPath $x, string $chemin): array {
    $lignes = [];
    foreach ($x->query($chemin) as $tr) {
        $c = [];
        foreach ($tr->getElementsByTagName('td') as $td) {
            $c[] = trim(preg_replace('/\s+/u', ' ', $td->textContent));
        }
        $lignes[] = $c;
    }
    return $lignes;
}
$sortie = [];
foreach ($bandes as $bande) {
    $composant = Livewire\Livewire::test(App\Livewire\Elevage\FichePondeuses::class)->set('bandeId', $bande->id);
    $doc = new DOMDocument();
    @$doc->loadHTML('<?xml encoding="utf-8"?>'.$composant->html());
    $x = new DOMXPath($doc);
    $cartes = [];
    foreach ($x->query("//span[contains(@class, 'md:text-2xl')]") as $span) {
        $cartes[] = trim(preg_replace('/\s+/u', ' ', $span->textContent));
    }
    $pdf = new DOMDocument();
    @$pdf->loadHTML('<?xml encoding="utf-8"?>'.view('exports.fiche-elevage', ['entries' => $composant->instance()->monthlyEntries->values()])->render());
    $sortie[$bande->code] = [
        'lignes' => cellulesDe($x, "//table[.//th[contains(., 'Date / Jour')]]/tbody/tr"),
        'cartes' => $cartes,
        'pdf' => cellulesDe(new DOMXPath($pdf), '//tbody/tr'),
        'periode' => now()->translatedFormat('F Y'),
        'fichier' => 'fiche-'.now()->format('Y-m').'.pdf',
    ];
}
echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
''';
