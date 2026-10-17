import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.92 — GLOSSAIRE DE LA FICHE LAPINS AU POSTE (suite de 15.36).
///
/// Décision client VALIDÉE le 14/10/2026 : tableau « Rationnement & Provende
/// Servie par Catégorie » = Reproducteur / Jeune (ex-« Sevré ») / Lapin de
/// Chair (ex-« Jeune (engraissement) ») ; colonne « Catégorie » ; « Sevrés »
/// devient « Jeunes » au tableau mensuel (distinct de « S/Mères »).
///
/// ⚠️⚠️ **LE DÉFAUT VERROUILLÉ** : après la migration serveur, le poste tire
/// « Jeune » et « Lapin de Chair ». L'ancien rattachement
/// `stageLabel.toLowerCase().contains(stade)` ne trouvait plus de ligne pour
/// une bande au stade `engraissement` : effectif 0 partout, total « 0 g »,
/// aucune erreur. Les rations de test (150 / 40 / 70) DIFFÈRENT des secours
/// (120 / 30 / 60) : lire un secours ici voudrait dire « barème ignoré ».
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

  Future<void> bande({String? stade, int effectif = 40}) async {
    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'CUN-2026-01',
            speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
            speciesCode: const Value('cuniculture'),
            stage: Value(stade),
            createdDate: Value(DateTime.now()),
            initialQuantity: Value(effectif),
            currentQuantity: Value(effectif),
          ),
        );
  }

  Future<void> bareme(List<(String, double)> lignes) async {
    await db.delete(db.feedRationStandards).go();
    var n = 0;
    for (final (libelle, g) in lignes) {
      n++;
      await db
          .into(db.feedRationStandards)
          .insert(
            FeedRationStandardsCompanion.insert(
              id: 'ffffffff-1111-4111-8111-${'$n'.padLeft(12, '0')}',
              speciesCode: 'cuniculture',
              stageLabel: libelle,
              rationGPerDay: g,
            ),
          );
    }
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
  });

  tearDown(() async => db.close());

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: FicheLapinsScreen(depot: depot, soins: soins),
      ),
    );
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  const nouveaux = [
    ('Reproducteur', 150.0),
    ('Jeune', 40.0),
    ('Lapin de Chair', 70.0),
  ];
  const anciens = [
    ('Lapine Mère / Reproducteur', 150.0),
    ('Lapin Sevré', 40.0),
    ('Jeune Lapin (engraissement)', 70.0),
  ];

  group('tableau de rationnement — libellés du glossaire', () {
    testWidgets('titre, colonne « Catégorie » et trois lignes du glossaire', (
      tester,
    ) async {
      await bande(stade: 'engraissement');
      await bareme(nouveaux);
      await afficher(tester);

      expect(
        find.text(
          'RATIONNEMENT & PROVENDE SERVIE PAR CATÉGORIE (EN GRAMMES G/J)',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'RATIONNEMENT & PROVENDE SERVIE PAR ESPÈCES (EN GRAMMES G/J)',
        ),
        findsNothing,
      );
      expect(find.text('Catégorie'), findsOneWidget);
      expect(find.text('Espèce'), findsNothing);
      expect(texte(tester, 'ration-libelle-reproducteur'), 'Reproducteur');
      expect(texte(tester, 'ration-libelle-jeune'), 'Jeune');
      expect(texte(tester, 'ration-libelle-chair'), 'Lapin de Chair');
    });

    testWidgets(
      '⚠️ barème aux ANCIENS libellés : la fiche affiche quand même le glossaire',
      (tester) async {
        await bande(stade: 'engraissement');
        await bareme(anciens);
        await afficher(tester);

        expect(find.text('Lapin Sevré'), findsNothing);
        expect(find.text('Jeune Lapin (engraissement)'), findsNothing);
        expect(texte(tester, 'ration-libelle-jeune'), 'Jeune');
        expect(texte(tester, 'ration-libelle-chair'), 'Lapin de Chair');
      },
    );
  });

  group('⚠️⚠️ rattachement de la bande par CLÉ STABLE', () {
    testWidgets(
      'bande en engraissement, barème NOUVEAU : 40 × 70 = 2 800 g sur Lapin de Chair',
      (tester) async {
        await bande(stade: 'engraissement');
        await bareme(nouveaux);
        await afficher(tester);

        expect(texte(tester, 'ration-effectif-chair'), '40');
        expect(texte(tester, 'ration-g-chair'), '70 g/j');
        expect(texte(tester, 'ration-grammes-chair'), '2800 g');
        // Recalcul indépendant : 40 sujets × 70 g.
        expect(texte(tester, 'total-provende'), '${40 * 70} g (2.8 Kg)');
      },
    );

    testWidgets('même chiffre avec le barème ANCIEN', (tester) async {
      await bande(stade: 'engraissement');
      await bareme(anciens);
      await afficher(tester);

      expect(texte(tester, 'ration-effectif-chair'), '40');
      expect(texte(tester, 'ration-g-chair'), '70 g/j');
      expect(texte(tester, 'total-provende'), '2800 g (2.8 Kg)');
    });

    testWidgets(
      '⚠️ renommer le libellé du barème ne change NI la ration NI le total',
      (tester) async {
        await bande(stade: 'engraissement');
        await bareme(anciens);
        await afficher(tester);
        final avant = [
          for (final c in ['reproducteur', 'jeune', 'chair']) ...[
            texte(tester, 'ration-effectif-$c'),
            texte(tester, 'ration-g-$c'),
            texte(tester, 'ration-grammes-$c'),
          ],
          texte(tester, 'total-provende'),
        ];

        // La migration 15.36, telle que le pull la rapporte.
        await (db.update(
          db.feedRationStandards,
        )..where((t) => t.stageLabel.equals('Lapin Sevré'))).write(
          const FeedRationStandardsCompanion(stageLabel: Value('Jeune')),
        );
        await (db.update(
              db.feedRationStandards,
            )..where((t) => t.stageLabel.equals('Jeune Lapin (engraissement)')))
            .write(
              const FeedRationStandardsCompanion(
                stageLabel: Value('Lapin de Chair'),
              ),
            );
        await tester.pumpWidget(const SizedBox());
        await afficher(tester);

        final apres = [
          for (final c in ['reproducteur', 'jeune', 'chair']) ...[
            texte(tester, 'ration-effectif-$c'),
            texte(tester, 'ration-g-$c'),
            texte(tester, 'ration-grammes-$c'),
          ],
          texte(tester, 'total-provende'),
        ];
        expect(apres, avant);
        expect(texte(tester, 'total-provende'), '2800 g (2.8 Kg)');
      },
    );

    testWidgets(
      'catégorie absente du barème : ration de secours (60 g pour la chair), comme le serveur',
      (tester) async {
        await bande(stade: 'engraissement');
        await bareme(const [('Reproducteur', 150), ('Jeune', 40)]);
        await afficher(tester);

        expect(texte(tester, 'ration-g-chair'), '60 g/j');
        expect(texte(tester, 'total-provende'), '${40 * 60} g (2.4 Kg)');
      },
    );

    testWidgets(
      'deux lignes d\'une même catégorie : l\'effectif n\'est compté qu\'UNE fois',
      (tester) async {
        await bande(stade: 'engraissement');
        await bareme(const [
          ('Reproducteur', 150),
          ('Jeune', 40),
          ('Lapin de Chair', 70),
          ('Jeune Lapin (engraissement)', 65),
        ]);
        await afficher(tester);

        expect(find.byKey(const Key('ration-libelle-chair')), findsOneWidget);
        final g = texte(tester, 'ration-g-chair');
        final ration = int.parse(g.replaceAll(' g/j', ''));
        expect(
          texte(tester, 'total-provende').startsWith('${40 * ration} g'),
          isTrue,
        );
      },
    );
  });

  group('⚠️ une ligne hors stade de la bande affiche « — », JAMAIS « 0 »', () {
    testWidgets('bande en engraissement : Reproducteur et Jeune en tirets', (
      tester,
    ) async {
      await bande(stade: 'engraissement');
      await bareme(nouveaux);
      await afficher(tester);

      for (final c in ['reproducteur', 'jeune']) {
        expect(texte(tester, 'ration-effectif-$c'), '—', reason: c);
        expect(texte(tester, 'ration-grammes-$c'), '—', reason: c);
      }
      // La ration normative reste connue : elle vient du barème.
      expect(texte(tester, 'ration-g-reproducteur'), '150 g/j');
      expect(texte(tester, 'ration-g-jeune'), '40 g/j');
    });

    testWidgets(
      'stade sans catégorie (reproduction) : trois tirets et un total « — »',
      (tester) async {
        await bande(stade: 'reproduction');
        await bareme(nouveaux);
        await afficher(tester);

        for (final c in ['reproducteur', 'jeune', 'chair']) {
          expect(texte(tester, 'ration-effectif-$c'), '—', reason: c);
          expect(texte(tester, 'ration-grammes-$c'), '—', reason: c);
        }
        expect(texte(tester, 'total-provende'), '—');
      },
    );

    testWidgets('bande sans stade : trois tirets et un total « — »', (
      tester,
    ) async {
      await bande();
      await bareme(nouveaux);
      await afficher(tester);

      expect(texte(tester, 'ration-effectif-chair'), '—');
      expect(texte(tester, 'total-provende'), '—');
    });

    testWidgets(
      'effectif réellement nul sur la ligne du stade : « 0 », c\'est une mesure',
      (tester) async {
        await bande(stade: 'engraissement', effectif: 0);
        await bareme(nouveaux);
        await afficher(tester);

        expect(texte(tester, 'ration-effectif-chair'), '0');
        expect(texte(tester, 'ration-grammes-chair'), '0 g');
        expect(texte(tester, 'total-provende'), '0 g (0.0 Kg)');
        expect(texte(tester, 'ration-effectif-jeune'), '—');
      },
    );
  });

  group('tableau mensuel — « Jeunes » remplace « Sevrés »', () {
    testWidgets('en-tête « JEUNES », distinct de « S/MÈRES »', (tester) async {
      await bande(stade: 'engraissement');
      final maintenant = DateTime.now();
      await db
          .into(db.livestockDailyEntries)
          .insert(
            LivestockDailyEntriesCompanion.insert(
              id: 'fiche-3'.padRight(36, '-'),
              deviceId: 'poste-test',
              updatedAt: maintenant,
              lotId: bandeId,
              entryDate: DateTime(maintenant.year, maintenant.month, 3),
              effectifFinal: const Value(40),
            ),
          );
      await afficher(tester);

      expect(find.text('JEUNES'), findsOneWidget);
      expect(find.text('S/MÈRES'), findsOneWidget);
      expect(find.text('SEVRÉS'), findsNothing);
      expect(find.text('Sevrés'), findsNothing);
    });
  });

  group(
    'écarts ASSUMÉS vis-à-vis de la maquette (décision client 14/10/2026)',
    () {
      final maquette = File(
        'C:/Projects/agrierp_laravel/prototype_html/fiche-lapins.html',
      );
      final ecran = File('lib/features/elevage/fiche_lapins_screen.dart');

      test('la maquette dit encore « Espèce » / « Lapereau » / « Sevrés » : '
          'l\'écran suit la décision client, pas la maquette', () {
        if (!maquette.existsSync()) {
          markTestSkipped('maquette absente de ce poste de développement');
          return;
        }
        final html = maquette.readAsStringSync();
        final code = ecran.readAsStringSync();

        // Si la maquette est alignée un jour, cet écart n'en est plus un :
        // retirer ce test plutôt que le laisser décrire un passé.
        expect(html, contains('<th class="px-md py-xs text-left">Espèce</th>'));
        expect(html, contains('>Lapereau</td>'));
        expect(html, contains('font-bold">Sevrés</th>'));
        expect(html, contains('Provende Servie par Espèces'));

        expect(code, contains("'Catégorie'"));
        expect(code, contains("'Jeunes'"));
        expect(code, contains('PAR CATÉGORIE'));
        expect(code, isNot(contains("'Espèce'")));
        expect(code, isNot(contains("'Sevrés'")));
      });

      test(
        '⚠️ les clés de synchronisation ne sont PAS renommées (`cat_eff_*`, `effectif_sevres`)',
        () {
          final schema = File(
            'lib/core/database/app_database.dart',
          ).readAsStringSync();
          final moteur = File(
            'lib/core/sync/sync_engine.dart',
          ).readAsStringSync();
          expect(schema, isNot(contains('effectifJeunes')));
          expect(moteur, isNot(contains("'effectif_jeunes'")));
          expect(moteur, isNot(contains("'cat_eff_chair'")));
        },
      );
    },
  );

  test('la Fiche Sujet reprend le motif du web 15.36 (glossaire lapins)', () {
    final code = File(
      'lib/features/elevage/fiche_sujet_screen.dart',
    ).readAsStringSync();
    expect(code, isNot(contains('Sevré / Jeune')));
    expect(
      code,
      contains('pour les lapins : Reproducteur / Jeune / Lapin de Chair)'),
    );
  });
}
