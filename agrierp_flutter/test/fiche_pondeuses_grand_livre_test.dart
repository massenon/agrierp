import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_pondeuses_screen.dart';
import 'package:agrierp/features/elevage/production_oeufs_service.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/stocks/journal_stocks.dart';
import 'package:agrierp/features/stocks/pmp_service.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket U10 — FICHE PONDEUSES : SRH, TS, OS ET STOCK FINAL DU JOUR SÉLECTIONNÉ, COMME LE WEB.
///
/// Le web les affiche (`FichePondeuses::getStockTodayProperty()` → `EggStockLedgerService::ligne($selectedDate,
/// $commercialisables)`) dans le bloc « Stock Œufs & Plateaux (30) — Jour Sélectionné » et sur la ligne du jour
/// sélectionné du tableau du mois ; le poste affichait « — » partout, faute de grand livre. Il descend depuis U9 :
/// mêmes valeurs, parité EXÉCUTÉE avec le vrai composant et sa vue.
void main() {
  late AppDatabase db;
  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  const oeufs = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'AVI-PON-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            speciesCode: const Value('aviculture'),
            stage: const Value('ponte'),
            createdDate: Value(DateTime(2026, 1, 5)),
            initialQuantity: const Value(480),
            currentQuantity: const Value(480),
          ),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: oeufs,
            sku: 'AVI-002',
            name: 'Œufs de table (plateau)',
            unit: 'plateau',
            pricingMode: 'fixe',
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> mouvement(
    String cle,
    String type,
    double quantite,
    DateTime quand, {
    String reference = 'sale',
  }) => db
      .into(db.stockMovements)
      .insert(
        StockMovementsCompanion.insert(
          id: cle.padRight(36, '0'),
          productId: oeufs,
          type: type,
          quantity: quantite,
          referenceType: reference,
          movementDate: quand,
        ),
      );

  /// SRH, TS, OS, Stock Final calculés À LA MAIN (aujourd'hui, 435 récoltés − 15 cassés = 420 = 14 plateaux) :
  ///   avant aujourd'hui : +20 (achat), −3 (vente), −0,5 (casse d'inventaire) → SRH = 16,5 ;
  ///   TS = 16,5 + 14 = 30,5 ; OS = 2 (vente du jour ; la casse du jour n'est pas une vente) ; final = 28,5.
  testWidgets(
    '⚠️⚠️ U10 — le bloc « Jour Sélectionné » et la ligne du jour portent SRH, TS, OS et Stock Final ; les autres lignes « — »',
    (tester) async {
      final aujourdHui = DateTime.now();
      final jour = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day);
      final autre = DateTime(jour.year, jour.month, jour.day == 1 ? 2 : 1);
      final hier = jour.subtract(const Duration(days: 1));
      await mouvement(
        'm1',
        'entree',
        20,
        hier.subtract(const Duration(days: 3)),
        reference: 'purchase',
      );
      await mouvement('m2', 'sortie', 3, hier.add(const Duration(hours: 10)));
      await mouvement(
        'm3',
        'sortie',
        0.5,
        hier.add(const Duration(hours: 18)),
        reference: 'inventaire',
      );
      await mouvement('m4', 'sortie', 2, jour.add(const Duration(hours: 9)));
      await mouvement(
        'm5',
        'sortie',
        1,
        jour.add(const Duration(hours: 10)),
        reference: 'inventaire',
      );
      for (final (cle, d, r, c) in [
        ('f-jour', jour, 435, 15),
        ('f-autre', autre, 300, 0),
      ]) {
        await db
            .into(db.livestockDailyEntries)
            .insert(
              LivestockDailyEntriesCompanion.insert(
                id: cle.padRight(36, '-'),
                deviceId: 'poste-test',
                // Fiches déjà acquittées : leur production est au grand livre du serveur (non reprise ici), rien
                // n'est projeté — le calcul à la main reste celui des seuls mouvements ci-dessus.
                syncStatus: const Value(SyncStatus.synced),
                updatedAt: d,
                lotId: bandeId,
                entryDate: d,
                effectifFinal: const Value(470),
                ponteTotal: Value(r),
                ponteCasses: Value(c),
              ),
            );
      }

      tester.view.physicalSize = const Size(1600, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: FichePondeusesScreen(
            depot: FicheJournaliereRepository(
              database: db,
              deviceId: 'poste-test',
            ),
            soins: SoinsRepository(database: db, deviceId: 'poste-test'),
            production: ProductionOeufsService(database: db),
          ),
        ),
      );
      await tester.pumpAndSettle();

      String texte(String cle) =>
          tester.widget<Text>(find.byKey(Key(cle))).data!;
      expect(
        find.text('STOCK ŒUFS & PLATEAUX (30) — JOUR SÉLECTIONNÉ'),
        findsOneWidget,
      );
      expect(find.text('STOCK HIER (SRH)'), findsOneWidget);
      expect(texte('stock-srh'), '16.5');
      expect(texte('stock-ts'), '30.5');
      expect(texte('stock-os'), '2');
      expect(texte('stock-final'), '28.5');

      // Tableau du mois : la ligne du jour sélectionné porte les mêmes valeurs ; l'autre ligne garde « — ».
      for (final v in ['16.5', '30.5', '28.5']) {
        expect(find.text(v), findsNWidgets(2), reason: v);
      }
      expect(find.byKey(const Key('note-grand-livre')), findsOneWidget);
    },
  );

  test(
    'parité exécutée U10 : SRH, TS, OS et Stock Final du poste = ceux que rend la fiche Pondeuses du web',
    () async {
      var graine = 314;
      int hasard(int n) =>
          ((graine = (graine * 1103515245 + 12345) & 0x7fffffff) >> 16) % n;
      String date(int mois, int j) =>
          '2026-${mois.toString().padLeft(2, '0')}-${j.toString().padLeft(2, '0')}';

      final mouvements = [
        for (var m = 0; m < 50; m++)
          () {
            final reference = [
              'sale',
              'sale',
              'daily_entry',
              'purchase',
              'inventaire',
              'adjustment',
            ][hasard(6)];
            final type = m % 13 == 0
                ? 'ajustement'
                : reference == 'sale' ||
                      (reference == 'inventaire' && hasard(2) == 0)
                ? 'sortie'
                : 'entree';
            return {
              'type': type,
              'qty': (1 + hasard(900)) / 100 * (hasard(3) == 0 ? 10 : 1),
              'ref': reference,
              'date':
                  '${date(9 + hasard(2), 1 + hasard(28))} ${hasard(24).toString().padLeft(2, '0')}:15:00',
            };
          }(),
      ];
      final cas = [
        for (var c = 0; c < 8; c++)
          {
            'date': date(10, 1 + hasard(28)),
            'recoltes': hasard(5) == 0 ? 0 : hasard(900),
            'casses': hasard(40),
          },
      ];

      final sortie =
          executerPhp('<?php\n$amorceApplication\n$_script', {
                'mouvements': mouvements,
                'cas': cas,
              }, application: true)
              as List;

      for (var m = 0; m < mouvements.length; m++) {
        final x = mouvements[m];
        await mouvement(
          'mvt-$m-',
          x['type']! as String,
          (x['qty']! as num).toDouble(),
          DateTime.parse(x['date']! as String),
          reference: x['ref']! as String,
        );
      }
      final grandLivre = await ProductionOeufsService(
        database: db,
      ).grandLivre(maintenant: DateTime(2026, 10, 30));
      expect(grandLivre.produit, oeufs);

      for (var c = 0; c < cas.length; c++) {
        final l = grandLivre.journal.ligneOeufs(
          grandLivre.produit,
          DateTime.parse(cas[c]['date']! as String),
          ProductionOeufsService.commercialisables(
            recoltes: cas[c]['recoltes']! as int,
            casses: cas[c]['casses']! as int,
          ),
        );
        expect(
          [
            PmpService.flottant(l.srh),
            PmpService.flottant(l.ts),
            PmpService.flottant(l.os),
            PmpService.flottant(l.stockFinal),
          ],
          (sortie[c] as List).cast<String>(),
          reason: 'cas $c (${cas[c]})',
        );
      }

      // La grille couvre ce qu'elle prétend couvrir.
      final valeurs = [for (final v in sortie) ...(v as List).cast<String>()];
      expect(
        valeurs.where((v) => v.contains('.')),
        isNotEmpty,
        reason: 'des décimales',
      );
      expect(
        valeurs.where((v) => v.startsWith('-')),
        isNotEmpty,
        reason: 'un solde négatif',
      );
      expect(
        [for (final v in sortie) (v as List)[2]].where((v) => v != '0'),
        isNotEmpty,
        reason: 'une vente',
      );
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('U10 — un flottant PHP affiché tel quel', () {
    expect(PmpService.flottant(12), '12');
    expect(PmpService.flottant(12.5), '12.5');
    expect(PmpService.flottant(-3), '-3');
    expect(PmpService.flottant(0.1 + 0.2), '0.3');
    expect(PmpService.flottant(0), '0');
    expect(JournalStocks.oeufsParPlateau, 30);
  });
}

/// Crée le produit œufs, une bande pondeuse et le grand livre dans Laravel (SQLite en mémoire), puis, pour chaque
/// cas, fait rendre la fiche Pondeuses par le VRAI composant (jour sélectionné, œufs récoltés et cassés saisis) et
/// lit les quatre encadrés « Stock Œufs & Plateaux (30) — Jour Sélectionné ».
const _script = r'''
$entree = json_decode(file_get_contents($argv[1]), true);
Carbon\Carbon::setTestNow('2026-10-30 14:30:00');
$espece = App\Models\LivestockSpecies::create(['code' => 'aviculture', 'label' => 'Volailles', 'is_enabled' => true]);
$categorie = App\Models\ProductCategory::create(['label' => 'Produits', 'is_active' => true]);
$oeufs = App\Models\Product::create([
    'sku' => 'AVI-002', 'name' => 'Œufs de table (plateau)', 'category_id' => $categorie->id, 'unit' => 'plateau',
    'pricing_mode' => 'fourchette', 'price_min' => 1, 'price_max' => 100000, 'stock_qty' => 0, 'is_active' => true,
]);
App\Models\LivestockLot::create([
    'code' => 'AVI-PON-01', 'species_id' => $espece->id, 'stage' => 'ponte', 'initial_quantity' => 480,
    'current_quantity' => 480, 'created_date' => '2026-01-05', 'status' => 'actif', 'is_active' => true,
]);
foreach ($entree['mouvements'] as $m) {
    App\Models\StockMovement::create([
        'product_id' => $oeufs->id, 'type' => $m['type'], 'quantity' => $m['qty'],
        'reference_type' => $m['ref'], 'movement_date' => $m['date'],
    ]);
}
$sortie = [];
foreach ($entree['cas'] as $c) {
    $html = Livewire\Livewire::test(App\Livewire\Elevage\FichePondeuses::class)
        ->set('selectedDate', $c['date'])
        ->set('oeufsRecoltes', $c['recoltes'])
        ->set('oeufsCasses', $c['casses'])
        ->html();
    $doc = new DOMDocument();
    @$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
    $x = new DOMXPath($doc);
    $valeurs = [];
    foreach (['Stock Hier (SRH)', 'Total Stock (TS)', 'Sortie Vente (OS)', 'Stock Final'] as $libelle) {
        $p = $x->query("//div[contains(@class, 'text-center')]/p[normalize-space(.)='$libelle']/following-sibling::p[1]")->item(0);
        $valeurs[] = trim($p->textContent);
    }
    $sortie[] = $valeurs;
}
echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
''';
