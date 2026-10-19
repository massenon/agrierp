import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/tableau_mensuel.dart';
import 'package:agrierp/features/elevage/fiche_escargots_screen.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.30 — TABLEAU MENSUEL DE LA FICHE ESCARGOTS, 🔁 ticket U12a : celui du Blade (TOUS les jours du mois).
///
/// ⚠️ **« NAISSAIN NÉ » AU SINGULIER EN ENTRÉE, « NAISSAINS » AU PLURIEL EN EFFECTIF** : deux libellés distincts du
/// Blade, repris tels quels.
///
/// ⚠️⚠️ **NAISSAINS / ENGRAISS. / BORDÉS** (`effectif_m/f/sevres`, saisis, synchronisés depuis 15.57) : « — » quand ils
/// sont inconnus.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;

  const bandeId = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb';
  final maintenant = HeureBenin.maintenant();
  final joursDuMois = DateTime(maintenant.year, maintenant.month + 1, 0).day;
  String deux(int n) => n.toString().padLeft(2, '0');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');

    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bandeId,
            code: 'HEL-ENG-01',
            speciesId: '11111111-1111-4111-8111-111111111111',
            speciesCode: const Value('helico'),
            stage: const Value('engraissement'),
            createdDate: Value(DateTime.now()),
            initialQuantity: const Value(1500),
            currentQuantity: const Value(1500),
          ),
        );
    // `ModuleConfig::isEnabled('helico')` : la fiche n'existe qu'une fois le module activé.
    await db.into(db.modulesConfig).insert(
      ModulesConfigCompanion.insert(
        id: 'dddddddd-1111-4111-8111-dddddddddddd',
        speciesCode: 'helico',
        isEnabled: const Value(true),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<void> journee(int jour, {int ne = 0, int mort = 0, int effectif = 1500, double? moyenneG}) async {
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: 'fiche-esc-$jour'.padRight(36, '-'),
            deviceId: 'poste-test',
            updatedAt: maintenant,
            lotId: bandeId,
            entryDate: DateTime(maintenant.year, maintenant.month, jour),
            ne: Value(ne),
            mort: Value(mort),
            effectifFinal: Value(effectif),
            weightSampleAvgG: Value(moyenneG),
          ),
        );
  }

  final tableau = find.byType(TableauMensuel);

  /// `hidden lg:block` : le tableau n'existe qu'à partir de 1 024 px, comme au web.
  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: FicheEscargotsScreen(depot: depot, soins: soins)));
    await tester.pumpAndSettle();
  }

  Finder ligne(int index) => find.byKey(Key('ligne-mois-$index'));

  testWidgets('⚠️ les groupes du Blade sont présents', (tester) async {
    await journee(5, ne: 40);
    await afficher(tester);

    for (final g in ['ENTRÉES', 'SORTIES', 'EFFECTIF FINAL DU JOUR']) {
      expect(find.descendant(of: tableau, matching: find.text(g)), findsOneWidget, reason: g);
    }
  });

  testWidgets('toutes les colonnes du web sont là, dans le libellé du Blade', (tester) async {
    await journee(5, ne: 40);
    await afficher(tester);

    for (final c in [
      'DATE',
      'Achat',
      'Naissain Né',
      'Mort',
      'Vente',
      'Don',
      'Naissains',
      'Engraiss.',
      'Bordés',
      'Total',
      'TAUX MORT %',
      'POIDS GÉNÉRAL (G)',
      'TRAITEMENTS & PROPHYLAXIE',
    ]) {
      expect(find.descendant(of: tableau, matching: find.text(c)), findsOneWidget, reason: c);
    }
  });

  /// ⚠️ 12 g de moyenne × 1 500 sujets = 18 000 g pesés, pas 12 (`poids_general_g`).
  testWidgets('la pesée se reconstitue en grammes', (tester) async {
    await journee(5, effectif: 1500, moyenneG: 12);
    await afficher(tester);

    expect(find.descendant(of: ligne(4), matching: find.text('18000')), findsOneWidget);
  });

  testWidgets('⚠️⚠️ les trois effectifs saisis inconnus affichent un tiret', (tester) async {
    await journee(5, effectif: 1500, moyenneG: 12);
    await afficher(tester);

    // Naissains, Engraiss., Bordés + Traitements & Prophylaxie.
    expect(find.descendant(of: ligne(4), matching: find.text('—')), findsNWidgets(4));
  });

  /// 🔁 U12a — `mortality_rate` du web : morts ÷ `previousEffectif()` (sans fiche antérieure, l'effectif INITIAL de la
  /// bande : 1 500) — 30 ÷ 1 500 = 2,0 %.
  testWidgets('le taux de mortalité du jour se calcule sur l effectif de début du web', (tester) async {
    await journee(5, mort: 30, effectif: 1470);
    await afficher(tester);

    expect(find.descendant(of: ligne(4), matching: find.text('2.0')), findsOneWidget);
  });

  testWidgets('toucher une ligne charge cette journée', (tester) async {
    await journee(5);
    await journee(12);

    await afficher(tester);

    await tester.ensureVisible(ligne(4));
    await tester.tap(ligne(4));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('date-choisie'))).data,
      '05/${deux(maintenant.month)}/${maintenant.year}',
    );
  });

  testWidgets('🔁 U12a — sans journée saisie, tous les jours du mois sont listés', (tester) async {
    await afficher(tester);

    expect(ligne(joursDuMois - 1), findsOneWidget);
    expect(find.text('— Aucune journée saisie ce mois-ci —'), findsNothing);
  });
}
