// Ticket U12a — outils communs des garde-fous « le Blade fait foi » et des parités exécutées des fiches Lapins, Porcs,
// Reproducteurs et Escargots (modèle : `fiche_pondeuses_blade_test.dart`, ticket U11).
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Vue Blade d'une fiche (`fiche-lapins`, `fiche-porcs`, `fiche-reproducteurs`, `fiche-escargots`).
File bladeDe(String nom) => File('$dossierLaravel/resources/views/livewire/elevage/$nom.blade.php');

/// Le texte d'un morceau de Blade : sans commentaires Blade ni balises, entités courantes décodées.
String texteBlade(String html) => html
    .replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '')
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Les LITTÉRAUX des fichiers de l'écran, en minuscules : chaînes entre quotes (simples ou doubles, échappements
/// compris), les littéraux ADJACENTS recollés (`'…' "…"` sur deux lignes, quelles que soient leurs quotes) ; les
/// commentaires ne comptent pas (ils citent parfois ce qui a été retiré).
String litterauxDe(List<String> fichiers) {
  final morceaux = <String>[];
  for (final f in fichiers) {
    final source = File(f).readAsStringSync();
    var i = 0;
    String? courant;
    var finCourant = -1;
    while (i < source.length) {
      final c = source[i];
      if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
        i = source.indexOf('\n', i);
        if (i < 0) break;
        continue;
      }
      if (c == "'" || c == '"') {
        final brut = i > 0 && source[i - 1] == 'r';
        final buffer = StringBuffer();
        var j = i + 1;
        while (j < source.length && source[j] != c && source[j] != '\n') {
          if (source[j] == '\\' && !brut && j + 1 < source.length) {
            buffer.write(source[j + 1]);
            j += 2;
            continue;
          }
          buffer.write(source[j]);
          j++;
        }
        final texte = buffer.toString();
        // Littéral adjacent au précédent (seuls des blancs entre eux) : recollé.
        if (courant != null && source.substring(finCourant, brut ? i - 1 : i).trim().isEmpty) {
          courant = courant + texte;
        } else {
          if (courant != null) morceaux.add(courant.toLowerCase());
          courant = texte;
        }
        finCourant = j + 1;
        i = j + 1;
        continue;
      }
      i++;
    }
    if (courant != null) morceaux.add(courant.toLowerCase());
  }
  return morceaux.join('\n');
}

/// Les `<th>` d'un `<thead>` du Blade, dans l'ordre du document (groupes puis sous-colonnes).
List<String> entetesDe(String blade, {String apres = '<thead class="bg-surface-zebra border-b'}) {
  final debut = blade.indexOf(apres);
  final thead = blade.substring(debut, blade.indexOf('</thead>', debut));
  return [for (final m in RegExp(r'<th[^>]*>(.*?)</th>', dotAll: true).allMatches(thead)) texteBlade(m[1]!)];
}

/// Les `<label>` du Blade (texte, précisions entre parenthèses comprises).
Set<String> etiquettesDe(String blade) => {
  for (final m in RegExp(r'<label[^>]*>(.*?)</label>', dotAll: true).allMatches(blade)) texteBlade(m[1]!),
};

/// Un libellé du Blade est dans les littéraux de l'écran : entier, ou libellé principal + précision écrits à part
/// (« Ventes » + « (POS, réel) »).
void attendreLibelle(String litteraux, String libelle, {String? raison}) {
  final m = RegExp(r'^(.*?)\s*(\([^()]*(\([^()]*\))?[^()]*\))?$').firstMatch(libelle)!;
  final principal = m[1]!.toLowerCase();
  final precision = m[2]?.toLowerCase();
  final complet = libelle.toLowerCase();
  expect(
    litteraux.contains(complet) || (litteraux.contains(principal) && (precision == null || litteraux.contains(precision))),
    isTrue,
    reason: raison ?? libelle,
  );
}

/// Générateur pseudo-aléatoire reproductible (même suite des deux côtés du test).
class Hasard {
  Hasard(this._graine);
  int _graine;
  int call(int n) => ((_graine = (_graine * 1103515245 + 12345) & 0x7fffffff) >> 16) % n;
}

String uuidDe(String g) => g.padRight(36, '0').substring(0, 36);
String jourDe(int mois, int j) => '2026-${mois.toString().padLeft(2, '0')}-${j.toString().padLeft(2, '0')}';

/// Un jeu de données d'une fiche : espèce, bandes, produits, types d'aliment, fiches, soins — inséré À L'IDENTIQUE
/// dans Laravel (SQLite en mémoire) et dans Drift.
class JeuFiches {
  JeuFiches({
    required this.codeEspece,
    required this.bandes,
    required this.produits,
    required this.fiches,
    required this.soins,
    this.typesAliment = const [],
    this.rations = const [],
  });

  final String codeEspece;
  final List<Map<String, Object?>> bandes;
  final List<Map<String, Object?>> produits;
  final List<Map<String, Object?>> fiches;
  final List<Map<String, Object?>> soins;
  final List<Map<String, Object?>> typesAliment;

  /// Barème `feed_ration_standards` de l'espèce : `(libellé, g/j)`.
  final List<(String, double)> rations;

  String get idEspece => uuidDe('espece-$codeEspece-');

  Map<String, Object?> versJson() => {
    'espece': {'id': idEspece, 'code': codeEspece},
    'bandes': bandes,
    'produits': produits,
    'fiches': fiches,
    'soins': soins,
    'types': typesAliment,
    'rations': [for (final (l, g) in rations) {'libelle': l, 'g': g}],
  };

  /// Insertion Drift : les bandes « actives » (statut `actif`) de l'espèce, comme le tirage les sert.
  Future<void> inserer(AppDatabase db) async {
    await db.into(db.livestockSpecies).insert(
      LivestockSpeciesCompanion.insert(id: idEspece, code: codeEspece, label: codeEspece),
    );
    if (codeEspece == 'helico') {
      await db.into(db.modulesConfig).insert(
        ModulesConfigCompanion.insert(id: uuidDe('module-helico-'), speciesCode: 'helico', isEnabled: const Value(true)),
      );
    }
    for (final p in produits) {
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: p['id']! as String,
          sku: p['id']! as String,
          name: p['nom']! as String,
          unit: (p['unite'] as String?) ?? 'u',
          pricingMode: 'fixe',
          speciesId: Value(p['espece'] == true ? idEspece : null),
          stockQty: Value((p['stock']! as num).toDouble()),
        ),
      );
    }
    for (final t in typesAliment) {
      await db.into(db.feedTypes).insert(
        FeedTypesCompanion.insert(
          id: t['id']! as String,
          name: t['nom']! as String,
          standardBagWeightKg: Value((t['sac']! as num).toDouble()),
        ),
      );
    }
    for (var i = 0; i < rations.length; i++) {
      await db.into(db.feedRationStandards).insert(
        FeedRationStandardsCompanion.insert(
          id: uuidDe('ration-$i-'),
          speciesCode: codeEspece,
          stageLabel: rations[i].$1,
          rationGPerDay: rations[i].$2,
        ),
      );
    }
    for (final b in bandes) {
      await db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: b['id']! as String,
          code: b['code']! as String,
          speciesId: idEspece,
          speciesCode: Value(codeEspece),
          stage: Value(b['stade'] as String?),
          status: const Value('actif'),
          createdDate: Value(DateTime(2026, 1, 5)),
          initialQuantity: Value(b['initial']! as int),
          currentQuantity: Value(b['courant']! as int),
        ),
      );
    }
    int? n(Map<String, Object?> f, String c) => f[c] as int?;
    for (final f in fiches) {
      await db.into(db.livestockDailyEntries).insert(
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
          ponteTotal: Value(n(f, 'ponte')),
          effectifM: Value(n(f, 'eff_m')),
          effectifF: Value(n(f, 'eff_f')),
          effectifSevres: Value(n(f, 'eff_sevres')),
          effectifSmeres: Value(n(f, 'eff_smeres')),
          weightSampleAvgG: Value((f['poids'] as int?)?.toDouble()),
          treatmentProductId: Value(f['traitement'] == null ? null : produits[f['traitement']! as int]['id']! as String),
          symptomes: Value(f['symptomes'] as String?),
          mortRepro: Value(n(f, 'mort_repro')),
          mortSevre: Value(n(f, 'mort_sevre')),
          mortJeune: Value(n(f, 'mort_jeune')),
          donRepro: Value(n(f, 'don_repro')),
          donSevre: Value(n(f, 'don_sevre')),
          donJeune: Value(n(f, 'don_jeune')),
          passageSevreJeune: Value(n(f, 'passage')),
          catDepartRepro: Value(n(f, 'depart_repro')),
          catDepartSevre: Value(n(f, 'depart_sevre')),
          catDepartJeune: Value(n(f, 'depart_jeune')),
          catEffRepro: Value(n(f, 'cat_repro')),
          catEffSevre: Value(n(f, 'cat_sevre')),
          catEffJeune: Value(n(f, 'cat_jeune')),
        ),
      );
    }
    for (final s in soins) {
      await db.into(db.veterinaryRecords).insert(
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
  }

  /// Soins du registre d'octobre : actifs et archivés, types et produits vides ou « 0 », deux le même jour.
  /// ⚠️ Pas de soin le 31 : sur SQLite, `whereBetween('record_date', ['…-01', '…-31'])` du web exclut « 2026-10-31
  /// 00:00:00 » (comparaison de chaînes) ; MySQL, lui, l'inclut — comme le poste.
  static List<Map<String, Object?>> soinsAuHasard(Hasard hasard, int nbBandes) => [
    for (var s = 0; s < 40; s++)
      {
        'id': uuidDe('soin-$s-'),
        'bande': hasard(nbBandes),
        'date': jourDe(10, 2 + hasard(29)),
        'type': ['Vaccination', 'Déparasitage', 'Vitamines', '', '0', 'Vaccination'][hasard(6)],
        'produit': [null, '', '0', 'Newcastle', 'Ivermectine'][hasard(5)],
        'actif': hasard(5) != 0,
        'cree': '2026-10-${(1 + s ~/ 2).toString().padLeft(2, '0')} ${(8 + s % 2).toString().padLeft(2, '0')}:00:00',
      },
  ];
}

/// Fait rendre la fiche par le VRAI composant Livewire, pour chaque bande (choisie par [propriete]), le 20/10/2026 à
/// 10 h : lignes du tableau du mois (cellules `td`), valeurs des cartes, lignes du PDF du mois (vue d'export du web),
/// période et nom du fichier ; [extra] : code PHP qui complète `$s` (accès à `$composant`, `$x`, `$bande`).
List<Map<String, dynamic>> renduWeb(JeuFiches jeu, {required String classe, required String propriete, String extra = '', bool cascade = false}) {
  final script = '<?php\n$amorceApplication\n${_script.replaceAll('/*CLASSE*/', classe).replaceAll('/*PROPRIETE*/', propriete).replaceAll('/*EXTRA*/', extra).replaceAll('/*CASCADE*/', cascade ? 'true' : 'false')}';
  return [
    for (final b in executerPhp(script, jeu.versJson(), application: true)! as List) (b as Map).cast<String, dynamic>(),
  ];
}

const _script = r'''
$entree = json_decode(file_get_contents($argv[1]), true);
Carbon\Carbon::setTestNow('2026-10-20 10:00:00');
$espece = new App\Models\LivestockSpecies(['code' => $entree['espece']['code'], 'label' => $entree['espece']['code'], 'is_enabled' => true]);
$espece->id = $entree['espece']['id'];
$espece->save();
if ($entree['espece']['code'] === 'helico') {
    App\Models\ModuleConfig::create(['species_code' => 'helico', 'is_enabled' => true]);
}
$categorie = App\Models\ProductCategory::create(['label' => 'Produits', 'is_active' => true]);
$produits = [];
foreach ($entree['produits'] as $i => $p) {
    $produit = new App\Models\Product([
        'sku' => 'P'.$i, 'name' => $p['nom'], 'category_id' => $categorie->id, 'unit' => $p['unite'] ?? 'u',
        'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 100000, 'stock_qty' => $p['stock'],
        'is_active' => true, 'species_id' => ($p['espece'] ?? false) ? $espece->id : null,
    ]);
    $produit->id = $p['id'];
    $produit->save();
    $produits[$i] = $produit;
}
foreach ($entree['types'] as $t) {
    $type = new App\Models\FeedType(['name' => $t['nom'], 'standard_bag_weight_kg' => $t['sac'], 'price_per_kg' => 500, 'is_active' => true]);
    $type->id = $t['id'];
    $type->save();
}
foreach ($entree['rations'] as $r) {
    App\Models\FeedRationStandard::create(['species_code' => $entree['espece']['code'], 'stage_label' => $r['libelle'], 'ration_g_per_day' => $r['g'], 'is_active' => true]);
}
$bandes = [];
foreach ($entree['bandes'] as $i => $b) {
    $bande = new App\Models\LivestockLot([
        'code' => $b['code'], 'species_id' => $espece->id, 'stage' => $b['stade'], 'initial_quantity' => $b['initial'],
        'current_quantity' => $b['courant'], 'created_date' => '2026-01-05', 'status' => 'actif', 'is_active' => true,
    ]);
    $bande->id = $b['id'];
    $bande->save();
    $bandes[$i] = $bande;
}
$colonnes = [
    'ponte' => 'ponte_total', 'eff_m' => 'effectif_m', 'eff_f' => 'effectif_f', 'eff_sevres' => 'effectif_sevres',
    'eff_smeres' => 'effectif_smeres', 'poids' => 'weight_sample_avg_g', 'symptomes' => 'symptomes',
    'mort_repro' => 'mort_repro', 'mort_sevre' => 'mort_sevre', 'mort_jeune' => 'mort_jeune', 'don_repro' => 'don_repro',
    'don_sevre' => 'don_sevre', 'don_jeune' => 'don_jeune', 'passage' => 'passage_sevre_jeune',
    'depart_repro' => 'cat_depart_repro', 'depart_sevre' => 'cat_depart_sevre', 'depart_jeune' => 'cat_depart_jeune',
    'cat_repro' => 'cat_eff_repro', 'cat_sevre' => 'cat_eff_sevre', 'cat_jeune' => 'cat_eff_jeune',
];
$premiers = [];
foreach ($entree['fiches'] as $f) {
    $valeurs = [
        'lot_id' => $bandes[$f['bande']]->id, 'entry_date' => $f['date'], 'achat' => $f['achat'], 'ne' => $f['ne'],
        'mort' => $f['mort'], 'vente' => $f['vente'], 'don' => $f['don'], 'effectif_final' => $f['effectif'],
        'treatment_product_id' => ($f['traitement'] ?? null) === null ? null : $produits[$f['traitement']]->id,
    ];
    foreach ($colonnes as $cle => $colonne) {
        $valeurs[$colonne] = $f[$cle] ?? null;
    }
    $e = new App\Models\LivestockDailyEntry($valeurs);
    $e->id = $f['id'];
    $e->save();
    $premiers[$f['bande']] = min($premiers[$f['bande']] ?? '9999-99-99', $f['date']);
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
if (/*CASCADE*/) {
    foreach ($premiers as $i => $date) {
        app(App\Actions\RecordSaleOnFicheElevageAction::class)->recalculerEnCascade($bandes[$i]->id, $date);
    }
}
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
function texteDe($noeud): string {
    return trim(preg_replace('/\s+/u', ' ', $noeud->textContent));
}
$sortie = [];
foreach ($bandes as $i => $bande) {
    $composant = Livewire\Livewire::test(/*CLASSE*/::class)->set('/*PROPRIETE*/', $bande->id);
    $doc = new DOMDocument();
    @$doc->loadHTML('<?xml encoding="utf-8"?>'.$composant->html());
    $x = new DOMXPath($doc);
    $cartes = [];
    foreach ($x->query("//span[contains(@class, 'md:text-2xl')]") as $span) {
        $cartes[] = texteDe($span);
    }
    $pdf = new DOMDocument();
    @$pdf->loadHTML('<?xml encoding="utf-8"?>'.view('exports.fiche-elevage', ['entries' => $composant->instance()->monthlyEntries->values()])->render());
    $s = [
        'lignes' => cellulesDe($x, "//table[.//th[contains(., 'Taux Mort')]]/tbody/tr"),
        'cartes' => $cartes,
        'pdf' => cellulesDe(new DOMXPath($pdf), '//tbody/tr'),
        'periode' => now()->translatedFormat('F Y'),
        'fichier' => 'fiche-'.now()->format('Y-m').'.pdf',
        'bande' => $bande->code,
    ];
    /*EXTRA*/
    $sortie[] = $s;
}
echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
''';
