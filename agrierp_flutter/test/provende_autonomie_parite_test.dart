import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/jour_categories.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// 🔴→✅ Ticket U14 — LE PRODUIT DE PROVENDE D'UNE FILIÈRE ET SON STOCK EN KG : la règle exacte du web, plus une
/// approximation (U12a).
///
/// Le web choisissait `first()` SANS ordre (`AutonomieAlimentaireService::produitProvende`) et le poids du sac par
/// `value()` sans ordre (`Product::stockEnKg`) : MySQL rendait la ligne de son plan d'exécution, le poste supposait « la
/// plus petite clé ». Le web a désormais `orderBy('id')` des deux côtés ; le poste compare le nom sous la collation du
/// serveur (casse ET accents). Parité EXÉCUTÉE : le vrai service PHP sur un jeu tiré au hasard (graine fixe).
void main() {
  final saut = sautSansPhp();

  test('⚠️⚠️ U14 — produit de provende et stock en Kg : ceux du service du web, filière par filière', () async {
    final hasard = Random(1404);
    String uuid() => [
      for (final n in [8, 4, 4, 4, 12])
        List.generate(n, (_) => '0123456789abcdef'[hasard.nextInt(16)]).join(),
    ].join('-');

    final especes = [
      for (final code in ['cuniculture', 'porciculture', 'aviculture']) {'id': uuid(), 'code': code},
    ];
    // Noms ASCII seulement : la base SQLite des tests n'ignore pas les accents (MySQL, si — témoin plus bas).
    const noms = [
      'Provende lapin', 'ALIMENT porc', 'aliments croissance', 'Granules', 'Sac de PROVENDE', 'Foin',
      'Lapin vivant', 'Complement alimentaire', 'Provende', 'Porc charcutier',
    ];
    final produits = [
      for (var i = 0; i < 24; i++)
        {
          'id': uuid(),
          'nom': noms[hasard.nextInt(noms.length)],
          'espece': hasard.nextInt(5) == 0 ? null : especes[hasard.nextInt(especes.length)]['id'],
          'unite': hasard.nextBool() ? 'sac' : 'kg',
          'stock': (hasard.nextInt(4000) - 200) / 10,
        },
    ];
    final types = [
      for (var i = 0; i < 4; i++)
        {'id': uuid(), 'nom': 'Type $i', 'sac': [25, 50, 0, 40.5][hasard.nextInt(4)]},
    ];

    final sortie = executerPhp('<?php\n$amorceApplication\n$_script', {
      'especes': especes,
      'produits': produits,
      'types': types,
    }, application: true) as Map<String, dynamic>;

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    for (final e in especes) {
      await db.into(db.livestockSpecies).insert(
        LivestockSpeciesCompanion.insert(id: e['id']!, code: e['code']!, label: e['code']!),
      );
    }
    for (final p in produits) {
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: p['id']! as String,
          sku: 'SKU-${p['id']}',
          name: p['nom']! as String,
          unit: p['unite']! as String,
          pricingMode: 'fourchette',
          speciesId: Value(p['espece'] as String?),
          stockQty: Value((p['stock']! as num).toDouble()),
        ),
      );
    }
    for (final t in types) {
      await db.into(db.feedTypes).insert(
        FeedTypesCompanion.insert(
          id: t['id']! as String,
          name: t['nom']! as String,
          standardBagWeightKg: Value((t['sac']! as num).toDouble()),
        ),
      );
    }
    final lesProduits = await db.select(db.products).get();
    final lesEspeces = await db.select(db.livestockSpecies).get();
    final lesTypes = await db.select(db.feedTypes).get();

    var avecProduit = 0;
    for (final e in especes) {
      final code = e['code']!;
      final web = sortie[code] as Map<String, dynamic>;
      final ici = AutonomieAlimentaire.produitProvende(code, lesProduits, lesEspeces);
      expect(ici?.id, web['produit'], reason: '$code : produit de provende');
      if (ici != null) {
        avecProduit++;
        expect(AutonomieAlimentaire.stockEnKg(ici, lesTypes), (web['stock_kg'] as num).toDouble(), reason: '$code : stock en Kg');
      }
    }
    expect(avecProduit, greaterThan(1), reason: 'le jeu doit départager plusieurs candidats');
  }, skip: saut);

  test('U14 — le nom se compare sans casse NI accents, comme `LIKE` sous `utf8mb4_unicode_ci`', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.livestockSpecies).insert(
      LivestockSpeciesCompanion.insert(id: 'eeeeeeee-0000-4000-8000-000000000001', code: 'cuniculture', label: 'Lapins'),
    );
    for (final (id, nom) in [
      ('bbbbbbbb-0000-4000-8000-000000000002', 'Lapin vivant'),
      ('cccccccc-0000-4000-8000-000000000003', 'ALIMÉNT lapin (granulés)'),
      ('dddddddd-0000-4000-8000-000000000004', 'Provende lapin'),
    ]) {
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: id,
          sku: id,
          name: nom,
          unit: 'kg',
          pricingMode: 'fourchette',
          speciesId: const Value('eeeeeeee-0000-4000-8000-000000000001'),
        ),
      );
    }

    final choisi = AutonomieAlimentaire.produitProvende(
      'cuniculture',
      await db.select(db.products).get(),
      await db.select(db.livestockSpecies).get(),
    );

    // « ALIMÉNT » répond à `LIKE '%aliment%'` sous la collation du serveur, et sa clé est la plus petite.
    expect(choisi?.name, 'ALIMÉNT lapin (granulés)');
  });
}

const _script = r'''
$e = json_decode(file_get_contents($argv[1]), true);
$t = '2026-10-19 10:00:00';
$categorie = (string) Illuminate\Support\Str::uuid();
app('db')->table('product_categories')->insert(['id' => $categorie, 'label' => 'Divers', 'is_active' => 1, 'created_at' => $t, 'updated_at' => $t]);
foreach ($e['especes'] as $s) {
    app('db')->table('livestock_species')->insert(['id' => $s['id'], 'code' => $s['code'], 'label' => $s['code'], 'is_enabled' => 1, 'created_at' => $t, 'updated_at' => $t]);
}
foreach ($e['produits'] as $p) {
    app('db')->table('products')->insert([
        'id' => $p['id'], 'sku' => 'SKU-'.$p['id'], 'name' => $p['nom'], 'category_id' => $categorie,
        'species_id' => $p['espece'], 'unit' => $p['unite'], 'pricing_mode' => 'fourchette', 'price_min' => 1,
        'price_max' => 2, 'tva_rate' => 0, 'stock_qty' => $p['stock'], 'is_active' => 1, 'created_at' => $t, 'updated_at' => $t,
    ]);
}
foreach ($e['types'] as $f) {
    app('db')->table('feed_types')->insert([
        'id' => $f['id'], 'name' => $f['nom'], 'standard_bag_weight_kg' => $f['sac'], 'price_per_kg' => 100,
        'is_active' => 1, 'created_at' => $t, 'updated_at' => $t,
    ]);
}
$service = app(App\Services\AutonomieAlimentaireService::class);
$sortie = [];
foreach ($e['especes'] as $s) {
    $produit = $service->produitProvende($s['code']);
    $sortie[$s['code']] = ['produit' => $produit?->id, 'stock_kg' => $produit?->stockEnKg()];
}
echo json_encode($sortie);
''';
