import 'dart:io';
import 'dart:typed_data';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/elevage/dashboard_elevage_repository.dart';
import 'package:agrierp/features/elevage/dashboard_elevage_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/stocks/catalogue_produits_screen.dart';
import 'package:agrierp/features/stocks/gestion_stocks_screen.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/caisse_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// NON-RÉGRESSION — « Duplicate keys found » et débordement de la carte « Rotation du Stock ».
///
/// 🔴→✅ Le client a lancé `flutter run -d windows` avec, dans ses données, DEUX bandes de même code
/// (`AVI-2026-01`) et DEUX catégories de même libellé (« Aliments »). Les écrans fabriquaient leurs clés de
/// widget à partir du code ou du libellé : « Duplicate keys found », puis une cascade de « Tried to build dirty
/// widget in the wrong build scope ». Aucun test ne mettait deux fois le même code : les jeux d'essai étaient
/// propres, les données réelles ne l'étaient pas.
///
/// Chaque test ci-dessous a été vu ROUGE sur l'ancien code (correctif retiré) avant de passer au vert.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  group('Dashboard Élevage — deux bandes de même code', () {
    late DashboardElevageRepository depot;
    final aujourdhui = DateTime.now();
    DateTime ilYA(int jours) =>
        DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day - jours);

    setUp(() async {
      depot = DashboardElevageRepository(
        database: db,
        soins: SoinsRepository(database: db, deviceId: 'poste-test'),
      );

      for (final (id, effectif) in [('b1', 310), ('b2', 120)]) {
        await db
            .into(db.livestockLots)
            .insert(
              LivestockLotsCompanion.insert(
                id: uuid(id),
                code: 'AVI-2026-01',
                speciesId: 'esp-aviculture',
                speciesCode: const Value('aviculture'),
                stage: const Value('ponte'),
                initialQuantity: const Value(320),
                currentQuantity: Value(effectif),
                status: const Value('actif'),
              ),
            );
        // Trois pesées : le GMQ, la synthèse et la prévision (régression) ont chacun leur ligne.
        for (final (jours, poids) in [(14, 800.0), (7, 900.0), (0, 1100.0)]) {
          await db
              .into(db.livestockDailyEntries)
              .insert(
                LivestockDailyEntriesCompanion.insert(
                  id: uuid('$jours-p-$id'),
                  deviceId: 'poste-test',
                  updatedAt: aujourdhui,
                  lotId: uuid(id),
                  entryDate: ilYA(jours),
                  effectifFinal: Value(effectif),
                  weightSampleAvgG: Value(poids),
                ),
              );
        }
        await db
            .into(db.veterinaryRecords)
            .insert(
              VeterinaryRecordsCompanion.insert(
                id: uuid('soin-$id'),
                deviceId: 'poste-test',
                updatedAt: aujourdhui,
                lotId: uuid(id),
                actionType: 'Vaccination',
                cost: const Value(5000),
                recordDate: aujourdhui,
              ),
            );
      }
    });

    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: DashboardElevageScreen(depot: depot)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'les cinq onglets se dessinent sans exception, chaque bande a sa ligne',
      (tester) async {
        await afficher(tester);
        expect(tester.takeException(), isNull, reason: 'Synthèse Globale');

        // Synthèse : une ligne de résumé GMQ par bande, première clé inchangée.
        expect(find.byKey(const Key('resume-gmq-AVI-2026-01')), findsOneWidget);
        expect(
          find.byKey(const Key('resume-gmq-AVI-2026-01-2')),
          findsOneWidget,
        );

        for (final onglet in [
          'GMQ & Croissance',
          'Rentabilité',
          'Analyse Sanitaire',
          'Prévision de Croissance',
        ]) {
          await tester.tap(find.byKey(Key('onglet-$onglet')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: onglet);

          if (onglet == 'GMQ & Croissance') {
            expect(
              find.byKey(const Key('ligne-gmq-AVI-2026-01')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('ligne-gmq-AVI-2026-01-2')),
              findsOneWidget,
            );
          }
          if (onglet == 'Prévision de Croissance') {
            expect(
              find.byKey(const Key('ligne-prevision-AVI-2026-01')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('ligne-prevision-AVI-2026-01-2')),
              findsOneWidget,
            );
          }
        }
      },
    );
    /// L'analyse sanitaire est une ligne par ESPÈCE (clé = code d'espèce) : deux fiches d'espèce de même code
    /// (référentiel reçu en double) donnaient la même collision.
    testWidgets('deux espèces de même code : l\'analyse sanitaire a deux lignes', (
      tester,
    ) async {
      for (final id in ['s1', 's2']) {
        await db
            .into(db.livestockSpecies)
            .insert(
              LivestockSpeciesCompanion.insert(
                id: uuid(id),
                code: 'aviculture',
                label: 'Aviculture',
              ),
            );
      }
      await afficher(tester);
      await tester.tap(find.byKey(const Key('onglet-Analyse Sanitaire')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('ligne-sanitaire-aviculture')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ligne-sanitaire-aviculture-2')),
        findsOneWidget,
      );
    });
  });

  group('Catalogue Produits — deux catégories de même libellé', () {
    late StocksRepository depot;
    const cat1 = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
    const cat2 = 'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb';
    const cat3 = 'cccccccc-0000-4000-8000-cccccccccccc';

    setUp(() async {
      depot = StocksRepository(database: db, deviceId: 'poste-test');
      for (final (id, libelle) in [
        (cat1, 'Aliments'),
        (cat2, 'Aliments'),
        (cat3, 'Aviculture'),
      ]) {
        await db
            .into(db.productCategories)
            .insert(ProductCategoriesCompanion.insert(id: id, label: libelle));
      }
      for (final (sku, nom, cat) in [
        ('ALI-001', 'Aliment ponte 25kg', cat1),
        ('ALI-002', 'Aliment chair 25kg', cat2),
        ('AVI-002', 'Œufs de table', cat3),
      ]) {
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: uuid('p-$sku'),
                sku: sku,
                name: nom,
                categoryId: Value(cat),
                unit: 'u',
                pricingMode: 'fixe',
                stockQty: const Value(10),
              ),
            );
      }
    });

    testWidgets(
      'une seule pastille par libellé, et elle montre les produits des deux catégories',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(home: CatalogueProduitsScreen(depot: depot)),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('pastille-Aliments')), findsOneWidget);
        expect(find.byKey(const Key('pastille-Aviculture')), findsOneWidget);

        await tester.tap(find.byKey(const Key('pastille-Aliments')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Aliment ponte 25kg'), findsOneWidget);
        expect(find.text('Aliment chair 25kg'), findsOneWidget);
        expect(find.text('Œufs de table'), findsNothing);
      },
    );
  });

  group('Caisse — deux bandes de même code', () {
    testWidgets('la zone de désignation de la bande liste les deux, sans exception', (
      tester,
    ) async {
      final depot = CaisseRepository(database: db, deviceId: 'poste-test');
      for (final id in ['b1', 'b2', 'b3']) {
        await db
            .into(db.livestockLots)
            .insert(
              LivestockLotsCompanion.insert(
                id: uuid(id),
                code: 'AVI-2026-01',
                speciesId: 'esp-1',
                initialQuantity: const Value(50),
                currentQuantity: const Value(50),
              ),
            );
      }
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: uuid('prod'),
              sku: 'AVI-001',
              name: 'Poulet goliath',
              speciesId: const Value('esp-1'),
              unit: 'u',
              pricingMode: 'fourchette',
              priceMin: const Value(3000),
              priceMax: const Value(4000),
              stockQty: const Value(50),
            ),
          );

      await tester.pumpWidget(MaterialApp(home: CaisseScreen(depot: depot)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('produit-AVI-001')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('bande-AVI-2026-01')), findsOneWidget);
      expect(find.byKey(const Key('bande-AVI-2026-01-2')), findsOneWidget);
      expect(find.byKey(const Key('bande-AVI-2026-01-3')), findsOneWidget);
    });
  });

  group('Gestion Stocks — cartes KPI', () {
    late StocksRepository depot;
    setUp(() => depot = StocksRepository(database: db, deviceId: 'poste-test'));

    /// ⚠️ La police par défaut des tests (Ahem, un carré par lettre) est deux fois plus large que n'importe quelle
    /// vraie police : une légende y prendrait trois lignes là où Windows en trace deux, et le test rougirait sur un
    /// code juste. On charge donc Roboto, livrée avec le SDK Flutter (`material_fonts`), seule police réaliste
    /// disponible sur toute machine de développement ; à défaut, le groupe se saute en le disant.
    String? raisonSaut;
    setUpAll(() async {
      final racines = [
        Platform.environment['FLUTTER_ROOT'],
        '/opt/flutter',
        r'C:\src\flutter',
      ].whereType<String>();
      for (final racine in racines) {
        final dossier = '$racine/bin/cache/artifacts/material_fonts';
        final regulier = File('$dossier/Roboto-Regular.ttf');
        final gras = File('$dossier/Roboto-Bold.ttf');
        if (regulier.existsSync() && gras.existsSync()) {
          final police = FontLoader('Roboto')
            ..addFont(Future.value(ByteData.sublistView(regulier.readAsBytesSync())))
            ..addFont(Future.value(ByteData.sublistView(gras.readAsBytesSync())));
          await police.load();
          return;
        }
      }
      raisonSaut = 'Roboto introuvable dans le SDK Flutter (FLUTTER_ROOT)';
    });

    /// Hauteur naturelle d'une carte « Rotation du Stock » (légende de deux lignes) à une largeur donnée.
    Future<double> hauteurNaturelle(
      WidgetTester tester,
      double largeur,
      double echelle,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(echelle)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: largeur,
                  child: const CarteKpi(
                    key: Key('mesure'),
                    libelle: 'Rotation du Stock',
                    valeur: '—',
                    couleurLisere: Colors.blue,
                    legende:
                        'Disponible après un stock valorisable non nul sur le mois, et de quoi remplir deux lignes',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('mesure'))).height;
    }

    for (final largeur in [1280.0, 1024.0, 800.0]) {
      for (final echelle in [1.0, 1.2]) {
        testWidgets(
          'largeur $largeur, police x$echelle : aucun débordement, carte au moins aussi haute que son contenu',
          (tester) async {
            if (raisonSaut != null) {
              markTestSkipped(raisonSaut!);
              return;
            }
            tester.view.physicalSize = Size(largeur, 1400);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(largeur, 1400),
                    textScaler: TextScaler.linear(echelle),
                  ),
                  child: GestionStocksScreen(depot: depot),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            final carte = find.byKey(const Key('kpi-Rotation du Stock'));
            expect(carte, findsOneWidget);
            final tailleCarte = tester.getSize(carte);

            // La légende réelle de la carte tient sur deux lignes : sa hauteur naturelle est la référence.
            final naturelle = await hauteurNaturelle(
              tester,
              tailleCarte.width,
              echelle,
            );
            expect(
              tailleCarte.height,
              greaterThanOrEqualTo(naturelle),
              reason:
                  'carte ${tailleCarte.width}×${tailleCarte.height} pour un contenu de $naturelle',
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
