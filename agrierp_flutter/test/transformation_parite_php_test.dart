import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/transformation_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket EL-1 — PARITÉ EXÉCUTÉE : le VRAI `SaisieTransformationAction` du serveur (précédé de la validation du formulaire web,
/// `SaisieTransformationAction::REGLES` et `lang/fr/validation.php`) et `TransformationRepository` du poste reçoivent les mêmes
/// saisies, sur la même bande et le même produit, et doivent refuser avec les MÊMES messages, sous les MÊMES champs.
///
/// Rien n'est recopié : un message changé au web (langue, règle, exercice clos, effectif) fait rougir ce test.
const _lot = 'a0000000-0000-4000-8000-000000000001';
const _produit = 'b0000000-0000-4000-8000-000000000001';
const _inconnu = 'ffffffff-0000-4000-8000-000000000000';

const _script = r'''<?php
$in = json_decode(file_get_contents($argv[1]), true);
''' + amorceApplication + r'''
use App\Actions\SaisieTransformationAction;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

$espece = (new App\Models\LivestockSpecies())->forceFill(['id' => $in['espece'], 'code' => 'aviculture', 'label' => 'Aviculture', 'is_enabled' => true]);
$espece->save();
(new App\Models\LivestockLot())->forceFill([
    'id' => $in['lot'], 'code' => 'AVI-ENG-1', 'species_id' => $in['espece'], 'stage' => 'engraissement', 'initial_quantity' => 40,
    'current_quantity' => 40, 'created_date' => '2025-01-01', 'status' => 'actif', 'is_active' => true,
])->save();
$categorie = App\Models\ProductCategory::create(['label' => 'Transformés', 'is_active' => true]);
(new App\Models\Product())->forceFill([
    'id' => $in['produit'], 'sku' => 'AVI-005', 'name' => 'Poulet fumé', 'category_id' => $categorie->id, 'unit' => 'pièce',
    'pricing_mode' => 'fourchette', 'price_min' => 5000, 'price_max' => 6000, 'tva_rate' => 0, 'stock_qty' => 0, 'is_active' => true,
])->save();
$u = App\Models\User::create(['name' => 'Animalier', 'username' => 'animalier', 'email' => 'a@ferme.test', 'password' => bcrypt('x'), 'is_active' => true]);

$sortie = [];
foreach ($in['cas'] as $c) {
    // L'exercice 2026 (celui du jour) n'est clôturé qu'à partir du premier cas qui le demande.
    if (!empty($c['clos']) && !App\Models\FiscalYear::where('year', 2026)->exists()) {
        App\Models\FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'cloture']);
    }
    $data = ['lotId' => $c['lotId'], 'qtyAnimals' => $c['qtyAnimals'], 'productId' => $c['productId'], 'qtyProduced' => $c['qtyProduced'], 'transformationDate' => $c['date']];
    $v = Validator::make($data, SaisieTransformationAction::REGLES);
    if ($v->fails()) {
        $sortie[] = (object) array_map(fn ($m) => $m[0], $v->errors()->toArray());
        continue;
    }
    try {
        app(SaisieTransformationAction::class)->enregistrer($data, $u->id);
        $sortie[] = (object) [];
    } catch (ValidationException $e) {
        $sortie[] = (object) array_map(fn ($m) => $m[0], $e->errors());
    }
}
echo json_encode($sortie);
''';

Map<String, dynamic> _cas(
  String nom, {
  String lot = _lot,
  String sujets = '5',
  String produit = _produit,
  String produite = '5',
  String? date = '2025-06-10',
  bool clos = false,
}) => {'clos': clos, 'nom': nom, 'lotId': lot, 'qtyAnimals': sujets, 'productId': produit, 'qtyProduced': produite, 'date': date};

void main() {
  final saut = sautSansPhp();

  test('⚠️ chaque refus du poste est celui du web, mot pour mot, sous le même champ', () async {
    final cas = [
      _cas('tout vide', lot: '', sujets: '', produit: '', produite: '', date: null),
      _cas('bande inconnue', lot: _inconnu),
      _cas('produit inconnu', produit: _inconnu),
      _cas('sujets non numériques', sujets: 'abc'),
      _cas('sujets décimaux', sujets: '2.5'),
      _cas('zéro sujet', sujets: '0'),
      _cas('sujets négatifs', sujets: '-3'),
      _cas('quantité produite non numérique', produite: 'abc'),
      _cas('quantité produite négative', produite: '-1'),
      _cas('effectif insuffisant', sujets: '41'),
      _cas('saisie valide', sujets: '5', produite: '12.5'),
      // Dès ici l'exercice 2026 est clos : le jour saisi, puis le jour même (le stock entre à la date du jour).
      _cas('exercice clos : jour saisi', date: '2026-10-10', clos: true),
      _cas('exercice clos : jour du stock', date: '2025-06-10', clos: true),
    ];
    final web = (executerPhp(_script, {'espece': 'c0000000-0000-4000-8000-000000000001', 'lot': _lot, 'produit': _produit, 'cas': cas}, application: true) as List)
        .map((e) => (e as Map).cast<String, String>())
        .toList();

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.livestockLots).insert(
      LivestockLotsCompanion.insert(id: _lot, code: 'AVI-ENG-1', speciesId: 'c0000000-0000-4000-8000-000000000001', status: const Value('actif'), currentQuantity: const Value(40)),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(id: _produit, sku: 'AVI-005', name: 'Poulet fumé', unit: 'pièce', pricingMode: 'fourchette', stockQty: const Value(0)),
    );
    final depot = TransformationRepository(database: db, deviceId: 'poste-test');

    final ecarts = <String>[];
    for (var i = 0; i < cas.length; i++) {
      final c = cas[i];
      if (c['clos'] == true) {
        await db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(id: 'd0000000-0000-4000-8000-000000000001', year: 2026, startDate: Value(DateTime(2026, 1, 1)), endDate: Value(DateTime(2026, 12, 31)), status: const Value('cloture')),
          mode: InsertMode.insertOrIgnore,
        );
      }
      Map<String, String> poste;
      try {
        await depot.enregistrer(
          lotId: c['lotId'] as String,
          qtyAnimals: c['qtyAnimals'] as String,
          productId: c['productId'] as String,
          qtyProduced: c['qtyProduced'] as String,
          date: c['date'] == null ? null : DateTime.parse(c['date'] as String),
        );
        poste = {};
      } on TransformationRefusee catch (e) {
        poste = e.erreurs;
      }
      if (poste.toString() != web[i].toString()) ecarts.add('${c['nom']} : poste $poste, web ${web[i]}');
    }
    expect(ecarts, isEmpty);
  }, skip: saut);
}
