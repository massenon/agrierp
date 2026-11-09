import 'dart:convert';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/releve_terrain.dart';
import 'package:agrierp/features/elevage/releve_terrain_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket RELEVES-1 — PARITÉ EXÉCUTÉE : le VRAI `ReleveTerrainService` du serveur (base SQLite en mémoire, migrée : les
/// propositions « À valider » sont semées par la migration) et `ReleveTerrain` / `ReleveTerrainRepository` du poste
/// reçoivent les mêmes entrées et doivent rendre les MÊMES valeurs : durée observée, taux de fertilité et d'éclosion,
/// résumé des valeurs, refus (mêmes messages, mêmes champs), délais constatés sur les 5 derniers bons, règle
/// critique / alerte en vigueur (à valider, validée « le plus long des 5 », valeurs saisies) et synthèse du Dashboard.
const _script = r'''<?php
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
use App\Services\Elevage\ReleveTerrainService as S;
use App\Models\FieldSurveyEntry;
use Illuminate\Validation\ValidationException;

$svc = app(S::class);
$sortie = ['graines' => [], 'lots' => [], 'normalisations' => []];

foreach (FieldSurveyEntry::orderBy('id')->get() as $l) {
    $sortie['graines'][] = ['id' => $l->id, 'type' => $l->type, 'label' => $l->label, 'species_code' => $l->species_code,
        'data' => $l->data, 'status' => $l->status, 'resume' => S::resume($l->type, $l->data)];
}
foreach ($in['lots'] as $d) {
    $sortie['lots'][] = ['calculs' => S::calculsLot($d), 'resume' => S::resume('incubation_lot', $d)];
}
foreach ($in['normalisations'] as $c) {
    $existante = isset($c['existante']) ? FieldSurveyEntry::find($c['existante']) : null;
    try {
        $n = $svc->normaliser($c['type'], ['label' => $c['label'], 'species_code' => $c['species_code'] ?? null, 'data' => $c['data']], $existante);
        $sortie['normalisations'][] = ['ok' => $n];
    } catch (ValidationException $e) {
        $sortie['normalisations'][] = ['erreurs' => array_map(fn ($m) => $m[0], $e->errors())];
    }
}

$fournisseurs = [];
foreach ($in['bons'] as $i => $b) {
    $f = $fournisseurs[$b['f']] ??= App\Models\Supplier::create(['name' => $b['f'], 'is_active' => true]);
    $cat = App\Models\ProductCategory::firstOrCreate(['label' => $b['cat']], ['is_active' => true]);
    $p = App\Models\Product::create(['sku' => 'P-'.$i, 'name' => 'Produit '.$i, 'category_id' => $cat->id, 'unit' => 'sac', 'pricing_mode' => 'fourchette',
        'price_min' => 1, 'price_max' => 2, 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true]);
    $bon = App\Models\PurchaseOrder::create(['supplier_id' => $f->id, 'status' => 'recu']);
    DB::table('purchase_orders')->where('id', $bon->id)->update(['created_at' => $b['bon'].' 10:00:00']);
    App\Models\PurchaseOrderLine::create(['purchase_order_id' => $bon->id, 'product_id' => $p->id, 'qty' => 1, 'estimated_unit_price' => 1]);
    App\Models\Purchase::create(['supplier_id' => $f->id, 'purchase_order_id' => $bon->id, 'payment_mode' => 'credit', 'total' => 1, 'purchase_date' => $b['recu']]);
}
$brut = fn () => array_map(fn ($f) => ['supplier' => $f['supplier'], 'nb' => $f['nb'], 'bons' => array_map(fn ($x) => [$x['date_bon'], $x['date_reception'], $x['delai_jours']], $f['bons']), 'critique' => $f['critique_propose']], S::delaisFournisseurs());
$sortie['delais'] = $brut();
$regle = fn () => (function ($r) { return [$r['critique'], $r['alerte'], $r['source']]; })(S::regleEnVigueur());

$sortie['regle_a_valider'] = $regle();
$id = S::idDuSemis('delai_provende');
$ligne = FieldSurveyEntry::findOrFail($id);
$svc->valider($ligne, null, null);
$sortie['regle_validee'] = $regle();
$svc->modifier($ligne->fresh(), ['label' => $ligne->label, 'data' => ['mode' => 'manuel', 'marge_jours' => 4, 'critique_jours' => 2, 'alerte_jours' => 5]], null);
$sortie['regle_manuelle'] = $regle();
$svc->modifier($ligne->fresh(), ['label' => $ligne->label, 'data' => ['mode' => 'constate', 'marge_jours' => 2, 'critique_jours' => 3, 'alerte_jours' => 7]], null);
$sortie['regle_marge2'] = $regle();

foreach ($in['creations'] as $c) {
    $svc->creer($c['type'], ['label' => $c['label'], 'species_code' => $c['species_code'], 'data' => $c['data']], null);
}
$s = $svc->synthese();
$sortie['synthese'] = [$s['a_valider'], $s['nb_lots'], $s['fertilite_moyenne'], $s['eclosion_moyenne'], $s['duree_observee_moyenne'], $s['duree_regle_moyenne'], $s['delai_constate_max']];
echo json_encode($sortie);
''';

Map<String, dynamic> _lot(Map<String, dynamic> remplace) => {
  'mise_date': '2026-10-01',
  'mode': 'couveuse_artificielle',
  'oeufs_mis': 100,
  'oeufs_fertiles': 80,
  'oeufs_eclos': 60,
  'premier_eclos_date': '2026-10-29',
  'dernier_eclos_date': '2026-10-31',
  ...remplace,
};

Map<String, dynamic> _regle(Map<String, dynamic> remplace) => {
  'duree_jours': 30,
  'eclosion_min': 28,
  'eclosion_max': 32,
  'mode': 'couveuse_artificielle',
  'mirages': '7, 14',
  'transfert_jour': '',
  'conservation_max_jours': 10,
  ...remplace,
};

void main() {
  final raison = sautSansPhp();

  test('durée, taux, résumés, refus, délais constatés et règle en vigueur : le poste = le vrai PHP', () async {
    final lots = [
      _lot({}),
      _lot({'oeufs_mis': 90, 'oeufs_fertiles': 70, 'oeufs_eclos': 50}),
      _lot({'oeufs_fertiles': 0, 'oeufs_eclos': 0}),
      _lot({'oeufs_mis': null, 'oeufs_fertiles': null, 'oeufs_eclos': null}),
      _lot({'premier_eclos_date': null, 'dernier_eclos_date': null}),
      _lot({'oeufs_mis': 7, 'oeufs_fertiles': 3, 'oeufs_eclos': 2}),
      _lot({'oeufs_mis': 3, 'oeufs_fertiles': 2, 'oeufs_eclos': 1, 'premier_eclos_date': '2026-10-01'}),
    ];
    final normalisations = <Map<String, dynamic>>[
      {'type': 'incubation_regle', 'label': 'Oie', 'species_code': 'oie', 'data': _regle({})},
      {'type': 'incubation_regle', 'label': 'Oie', 'species_code': 'oie', 'data': _regle({'duree_jours': 70, 'mirages': '14, 7'})},
      {'type': 'incubation_regle', 'label': '', 'species_code': 'oie', 'data': _regle({'eclosion_min': 40, 'eclosion_max': 20, 'mode': 'x', 'transfert_jour': 10})},
      {'type': 'incubation_regle', 'label': 'Oie', 'species_code': 'oie', 'data': _regle({'transfert_jour': 25, 'mirages': ['7', '14'], 'conservation_max_jours': 'abc'})},
      {'type': 'incubation_lot', 'label': 'LOT-A', 'species_code': 'pintade', 'data': _lot({})},
      {'type': 'incubation_lot', 'label': 'LOT-A', 'species_code': 'pintade', 'data': _lot({'oeufs_fertiles': 150, 'oeufs_eclos': 160, 'premier_eclos_date': '2026-09-01', 'dernier_eclos_date': '2026-08-01'})},
      {'type': 'incubation_lot', 'label': 'LOT-B', 'species_code': 'pintade', 'data': {'mode': 'couvaison_naturelle', 'mise_date': '2026-02-30'}},
      {'type': 'delai_regle', 'label': 'Délai', 'existante': 'ID_DELAI', 'data': {'mode': 'manuel', 'marge_jours': 4, 'critique_jours': 6, 'alerte_jours': 3}},
      {'type': 'delai_regle', 'label': 'Délai', 'existante': 'ID_DELAI', 'data': {'mode': 'constate', 'marge_jours': 4, 'critique_jours': 3, 'alerte_jours': 7}},
      {'type': 'poisson_marque', 'label': 'Marque', 'data': {'marque': '  Skretting '}},
      {'type': 'poisson_bareme', 'label': 'Classe', 'data': {'poids_min_g': '5,5', 'poids_max_g': '20', 'biomasse_min_pct': '6', 'biomasse_max_pct': '8', 'granule': '2 mm', 'proteine_pct': '42,5'}},
      {'type': 'poisson_bareme', 'label': 'Classe', 'data': {'poids_min_g': '30', 'poids_max_g': '20', 'biomasse_min_pct': '9', 'biomasse_max_pct': '8', 'proteine_pct': '120'}},
      {'type': 'poisson_temperature', 'label': 'Température', 'data': {'optimale_min': 26, 'optimale_max': 30, 'reduire_sous': 22}},
      {'type': 'poisson_temperature', 'label': 'Température', 'data': {'optimale_min': 30, 'optimale_max': 26, 'reduire_sous': 35}},
      {'type': 'poisson_densite', 'label': 'Densité', 'data': {'densite': '50,5', 'unite': 'poissons/m³'}},
      {'type': 'poisson_densite', 'label': 'Densité', 'data': {'densite': 'beaucoup'}},
      {'type': 'inconnu', 'label': 'x', 'data': {}},
    ];
    // Bons : fournisseur A (6 bons de provende dont un plus ancien : seuls les 5 derniers comptent, + un non « Aliments »),
    // fournisseur B (2 bons seulement : pas de proposition).
    final bons = <Map<String, String>>[
      {'f': 'Provenderie A', 'bon': '2026-01-01', 'recu': '2026-01-31', 'cat': 'Aliments'},
      {'f': 'Provenderie A', 'bon': '2026-02-01', 'recu': '2026-02-04', 'cat': 'Aliments'},
      {'f': 'Provenderie A', 'bon': '2026-03-01', 'recu': '2026-03-05', 'cat': 'Aliments'},
      {'f': 'Provenderie A', 'bon': '2026-04-01', 'recu': '2026-04-04', 'cat': 'Aliments'},
      {'f': 'Provenderie A', 'bon': '2026-05-01', 'recu': '2026-05-07', 'cat': 'Aliments'},
      {'f': 'Provenderie A', 'bon': '2026-06-01', 'recu': '2026-06-05', 'cat': 'Aliments'},
      {'f': 'Provenderie A', 'bon': '2026-07-01', 'recu': '2026-07-20', 'cat': 'Médicaments'},
      {'f': 'Fournisseur B', 'bon': '2026-02-10', 'recu': '2026-02-19', 'cat': 'Aliments'},
      {'f': 'Fournisseur B', 'bon': '2026-03-10', 'recu': '2026-03-12', 'cat': 'Aliments'},
    ];
    final creations = [
      {'type': 'incubation_lot', 'label': 'L1', 'species_code': 'pintade', 'data': _lot({})},
      {'type': 'incubation_lot', 'label': 'L2', 'species_code': 'pintade', 'data': _lot({'oeufs_mis': 90, 'oeufs_fertiles': 70, 'oeufs_eclos': 50, 'premier_eclos_date': '2026-10-27'})},
      {'type': 'incubation_lot', 'label': 'L3', 'species_code': 'goliath', 'data': _lot({'oeufs_mis': 40, 'oeufs_fertiles': 30, 'oeufs_eclos': 21, 'premier_eclos_date': '2026-10-24'})},
      {'type': 'incubation_lot', 'label': 'L4', 'species_code': 'pintade', 'data': {'mode': 'couveuse_artificielle', 'mise_date': '2026-10-05'}},
    ];
    final php = executerPhp(
      _script,
      {'lots': lots, 'normalisations': normalisations, 'bons': bons, 'creations': creations},
      application: true,
    ) as Map<String, dynamic>;

    final graines = (php['graines'] as List).cast<Map<String, dynamic>>();
    final idDelai = graines.firstWhere((g) => g['type'] == 'delai_regle')['id'] as String;
    // Les cas « delai_regle » visent la ligne semée (l'identifiant déterministe n'est connu que du PHP).
    for (final c in normalisations) {
      if (c['existante'] == 'ID_DELAI') c['existante'] = idDelai;
    }

    // ── Calculs d'un lot et résumés (aucun accès base)
    for (var i = 0; i < lots.length; i++) {
      final attendu = (php['lots'] as List)[i] as Map<String, dynamic>;
      final c = ReleveTerrain.calculsLot(lots[i]);
      final p = attendu['calculs'] as Map<String, dynamic>;
      expect([c.dureeJours, c.tauxFertilite, c.tauxEclosion], [p['duree_jours'], p['taux_fertilite'], p['taux_eclosion']], reason: 'lot $i');
      expect(ReleveTerrain.resume('incubation_lot', lots[i]), attendu['resume'], reason: 'résumé du lot $i');
    }
    // Résumé de chaque proposition semée par le serveur.
    for (final g in graines) {
      expect(ReleveTerrain.resume(g['type'] as String, Map<String, dynamic>.from(g['data'] as Map)), g['resume'], reason: '${g['label']}');
    }

    // ── Refus et valeurs normalisées
    for (var i = 0; i < normalisations.length; i++) {
      final c = normalisations[i];
      final attendu = (php['normalisations'] as List)[i] as Map<String, dynamic>;
      final r = ReleveTerrain.normaliser(
        c['type'] as String,
        label: c['label'] as String?,
        especeCode: c['species_code'] as String?,
        data: Map<String, dynamic>.from(c['data'] as Map),
      );
      if (attendu.containsKey('erreurs')) {
        // Les contrôles de base (unicité, règle d'espèce) sont ceux du dépôt, pas de la fonction pure.
        final pur = Map<String, dynamic>.from(attendu['erreurs'] as Map)
          ..removeWhere((k, v) => v.toString().startsWith('Une règle d') || v.toString().startsWith('Aucune règle') || v.toString().startsWith('Un relevé existe') || v.toString().startsWith('La règle du délai'));
        expect(r.erreurs, pur, reason: 'cas $i ${c['type']}');
      } else {
        final ok = attendu['ok'] as Map<String, dynamic>;
        expect(r.valide, isTrue, reason: 'cas $i ${r.erreurs}');
        expect([r.label, r.especeCode, r.data], [ok['label'], ok['species_code'], ok['data']], reason: 'cas $i');
      }
    }

    // ── Délais constatés et règle en vigueur, sur la même base de bons
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final instant = DateTime(2026, 11, 8);
    for (final g in graines) {
      await db.into(db.fieldSurveyEntries).insert(
        FieldSurveyEntriesCompanion.insert(
          id: g['id'] as String,
          type: g['type'] as String,
          label: g['label'] as String,
          speciesCode: Value(g['species_code'] as String?),
          dataJson: Value(jsonEncodeData(g['data'])),
          status: Value(g['status'] as String),
        ),
      );
    }
    final categories = <String, String>{};
    final fournisseurs = <String, String>{};
    for (var i = 0; i < bons.length; i++) {
      final b = bons[i];
      final cat = categories.putIfAbsent(b['cat']!, () => 'c0000000-0000-4000-8000-${(categories.length + 1).toString().padLeft(12, '0')}');
      await db.into(db.productCategories).insertOnConflictUpdate(ProductCategoriesCompanion.insert(id: cat, label: b['cat']!));
      final f = fournisseurs.putIfAbsent(b['f']!, () => 'f0000000-0000-4000-8000-${(fournisseurs.length + 1).toString().padLeft(12, '0')}');
      final pid = 'd0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
      await db.into(db.products).insert(ProductsCompanion.insert(id: pid, sku: 'P-$i', name: 'Produit $i', categoryId: Value(cat), unit: 'sac', pricingMode: 'fourchette'));
      final bonId = 'e0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
      DateTime jour(String iso, {int heure = 0}) => DateTime(int.parse(iso.substring(0, 4)), int.parse(iso.substring(5, 7)), int.parse(iso.substring(8, 10)), heure);
      await db.into(db.purchaseOrders).insert(
        PurchaseOrdersCompanion.insert(
          id: bonId,
          deviceId: 'serveur',
          updatedAt: instant,
          supplierId: Value(f),
          supplierName: Value(b['f']),
          status: const Value('recu'),
          createdAt: Value(jour(b['bon']!, heure: 10)),
        ),
      );
      await db.into(db.purchaseOrderLines).insert(
        PurchaseOrderLinesCompanion.insert(id: 'l0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}', purchaseOrderId: bonId, productId: pid, qty: 1, estimatedUnitPrice: 1),
      );
      await db.into(db.purchases).insert(
        PurchasesCompanion.insert(
          id: 'a1000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
          deviceId: 'serveur',
          updatedAt: instant,
          supplierId: f,
          purchaseOrderId: Value(bonId),
          paymentMode: 'credit',
          total: 1,
          purchaseDate: jour(b['recu']!),
        ),
      );
    }
    final depot = ReleveTerrainRepository(database: db, maintenant: () => instant);

    final delais = await depot.delaisFournisseurs();
    expect(
      [
        for (final d in delais)
          {
            'supplier': d.fournisseur,
            'nb': d.nb,
            'bons': [for (final b in d.bons) [b['date_bon'], b['date_reception'], b['delai_jours']]],
            'critique': d.critiquePropose,
          },
      ],
      php['delais'],
    );
    List<Object> r(RegleDelai x) => [x.critique, x.alerte, x.source];
    expect(r(await depot.regleEnVigueur()), php['regle_a_valider']);
    await depot.valider(idDelai);
    expect(r(await depot.regleEnVigueur()), php['regle_validee']);
    await depot.modifier(idDelai, label: 'Délai fournisseur de provende', data: {'mode': 'manuel', 'marge_jours': 4, 'critique_jours': 2, 'alerte_jours': 5});
    expect(r(await depot.regleEnVigueur()), php['regle_manuelle']);
    await depot.modifier(idDelai, label: 'Délai fournisseur de provende', data: {'mode': 'constate', 'marge_jours': 2, 'critique_jours': 3, 'alerte_jours': 7});
    expect(r(await depot.regleEnVigueur()), php['regle_marge2']);

    // ── Synthèse du Dashboard (lots créés par les deux dépôts)
    for (final c in creations) {
      await depot.creer(c['type'] as String, label: c['label'] as String, especeCode: c['species_code'] as String, data: Map<String, dynamic>.from(c['data'] as Map));
    }
    final s = await depot.synthese();
    expect(
      [s.aValider, s.nbLots, s.fertiliteMoyenne, s.eclosionMoyenne, s.dureeObserveeMoyenne, s.dureeRegleMoyenne, s.delaiConstateMax],
      php['synthese'],
    );
  }, skip: raison);
}

String jsonEncodeData(Object? d) => const JsonEncoder().convert(d);
