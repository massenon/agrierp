import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_pondeuses_screen.dart';
import 'package:agrierp/features/elevage/production_oeufs_service.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.27 — TABLEAU MENSUEL DE LA FICHE PONDEUSES ; 🔁 ticket U11 : le tableau du BLADE.
///
/// 🔴→✅ Ticket U11 — TOUS les jours du mois (le poste ne listait que les jours saisis, en « Jour N (jj/mm) »),
/// l'effectif de début `previousEffectif()` du web, « — » sur un jour sans fiche, « Traitements & Rappels »
/// rempli depuis le registre vétérinaire. SRH, TS, OS et Stock Final : la ligne du jour sélectionné seulement (U10,
/// `fiche_pondeuses_grand_livre_test.dart`). Parité exécutée avec le PHP : `fiche_pondeuses_blade_test.dart`.
void main() {
  late AppDatabase db;
  late FicheJournaliereRepository depot;
  late SoinsRepository soins;
  late ProductionOeufsService production;

  const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
  // Un jour fixe (le 10 octobre 2026) : 31 jours, et des fiches avant, pendant, après.
  final maintenant = DateTime(2026, 10, 10, 9);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    soins = SoinsRepository(database: db, deviceId: 'poste-test');
    production = ProductionOeufsService(database: db);

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
  });

  tearDown(() async => db.close());

  Future<void> journee(
    int jour, {
    int mort = 0,
    int? recoltes,
    int? casses,
    int effectif = 480,
    String? symptomes,
  }) async {
    await db
        .into(db.livestockDailyEntries)
        .insert(
          LivestockDailyEntriesCompanion.insert(
            id: 'fiche-$jour'.padRight(36, '-'),
            deviceId: 'poste-test',
            syncStatus: const Value(SyncStatus.synced),
            updatedAt: maintenant,
            lotId: bandeId,
            entryDate: DateTime(2026, 10, jour),
            mort: Value(mort),
            effectifFinal: Value(effectif),
            ponteTotal: Value(recoltes),
            ponteCasses: Value(casses),
            symptomes: Value(symptomes),
          ),
        );
  }

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 5200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FichePondeusesScreen(
          depot: depot,
          soins: soins,
          production: production,
          maintenant: () => maintenant,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Les cellules d'une ligne du tableau, dans l'ordre.
  List<String> ligne(WidgetTester tester, int index) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(Key('ligne-mois-$index')),
        matching: find.byType(Text),
      ),
    ))
      t.data!,
  ];

  testWidgets('⚠️ les groupes du Blade sont présents', (tester) async {
    await journee(4, recoltes: 435, casses: 15);
    await afficher(tester);

    for (final g in [
      'CHEPTEL DU JOUR',
      'SUIVI DE LA PONTE & RÉCOLTE',
      'STOCK ŒUFS & PLATEAUX (30)',
    ]) {
      expect(find.text(g), findsOneWidget, reason: g);
    }
  });

  testWidgets('toutes les colonnes du web sont là (sous-colonnes en casse mixte, 15.57)', (tester) async {
    await journee(4, recoltes: 435, casses: 15);
    await afficher(tester);

    for (final c in [
      'Eff. Début',
      'Morts',
      'Taux Mort %',
      'Eff. Fin',
      'Total (OR)',
      'Taux Ponte %',
      'Cassés (OF)',
      'Comm. (OR-OF)',
      'DATE / JOUR',
      'SRH',
      'TS',
      'OS',
      'Stock Final',
    ]) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
    // La colonne, et la section « Traitements & Rappels » du formulaire.
    expect(find.text('TRAITEMENTS & RAPPELS'), findsNWidgets(2));
  });

  /// 🔴→✅ Ticket U11 — `range(1, now()->daysInMonth)` : 31 lignes en octobre, saisies ou non.
  testWidgets('⚠️⚠️ U11 — tous les jours du mois sont listés, saisis ou non', (tester) async {
    await journee(4, recoltes: 435, casses: 15);
    await afficher(tester);

    expect(find.byKey(const Key('ligne-mois-30')), findsOneWidget);
    expect(find.byKey(const Key('ligne-mois-31')), findsNothing);
    // Un jour sans fiche : la date, puis « — » partout (12 colonnes et « Traitements & Rappels »).
    expect(ligne(tester, 0), ['01/10', ...List.filled(13, '—')]);
    expect(find.text('— Aucune journée saisie ce mois-ci —'), findsNothing);
  });

  /// Valeurs calculées à la main. Le 4 : effectif de début = effectif INITIAL de la bande (480, aucune fiche
  /// antérieure) ; 2 morts → 2 ÷ 480 × 100 = 0,4166… → round(…, 2) = 0,42 → « 0.4 » ; 435 œufs ÷ 480 = 90,625 % →
  /// « 90.6 » ; 435 − 15 = 420.
  /// Le 5 : effectif de début = effectif FINAL du 4 (470) — le poste reconstituait « final + morts + ventes − achats −
  /// nés » ; sans ponte ni casse saisies : « — » ; aucun soin, symptômes « Toux » → « Toux ».
  testWidgets('⚠️⚠️ U11 — cellules du Blade : effectif de la veille, taux, tirets, symptômes', (tester) async {
    await journee(4, mort: 2, recoltes: 435, casses: 15, effectif: 470);
    await journee(5, effectif: 470, symptomes: 'Toux');
    await afficher(tester);

    expect(ligne(tester, 3), [
      '04/10', '480', '2', '0.4', '470', '435', '90.6', '15', '420', '—', '—', '—', '—', '—',
    ]);
    expect(ligne(tester, 4), [
      '05/10', '470', '0', '0.0', '470', '—', '0.0', '—', '0', '—', '—', '—', '—', 'Toux',
    ]);
  });

  /// 🔴→✅ Ticket U11 — « Traitements & Rappels » : les soins ACTIFS du registre du jour (« type (produit) », sans
  /// doublon, dans l'ordre de saisie), puis le produit de traitement de la fiche ; un soin archivé n'y est pas.
  testWidgets('⚠️⚠️ U11 — « Traitements & Rappels » reprend les soins du registre', (tester) async {
    await journee(4, recoltes: 100, symptomes: 'Toux');
    for (final (cle, type, produit, actif, minute) in [
      ('s1', 'Vaccination', 'Newcastle', true, 1),
      ('s2', 'Déparasitage', null, true, 2),
      ('s3', 'Vaccination', 'Newcastle', true, 3),
      ('s4', 'Antibiotique', 'Oxytétracycline', false, 4),
    ]) {
      await db
          .into(db.veterinaryRecords)
          .insert(
            VeterinaryRecordsCompanion.insert(
              id: 'soin-$cle'.padRight(36, '-'),
              deviceId: 'poste-test',
              syncStatus: const Value(SyncStatus.synced),
              updatedAt: DateTime(2026, 10, 4, 8, minute),
              lotId: bandeId,
              actionType: type,
              productUsed: Value(produit),
              recordDate: DateTime(2026, 10, 4),
              isActive: Value(actif),
            ),
          );
    }
    // Un soin d'un AUTRE jour n'apparaît que sur sa ligne.
    await db
        .into(db.veterinaryRecords)
        .insert(
          VeterinaryRecordsCompanion.insert(
            id: 'soin-s5'.padRight(36, '-'),
            deviceId: 'poste-test',
            updatedAt: DateTime(2026, 10, 7, 8),
            lotId: bandeId,
            actionType: 'Vitamines',
            recordDate: DateTime(2026, 10, 7),
          ),
        );
    await afficher(tester);

    expect(ligne(tester, 3).last, 'Vaccination (Newcastle), Déparasitage');
    expect(ligne(tester, 6).last, 'Vitamines');
    expect(ligne(tester, 5).last, '—');
  });

  testWidgets('toucher une ligne charge cette journée', (tester) async {
    await journee(4, recoltes: 100);
    await journee(9, recoltes: 200);

    await afficher(tester);

    final ligneDu4 = find.byKey(const Key('ligne-mois-3'));
    await tester.ensureVisible(ligneDu4);
    await tester.tap(ligneDu4);
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('date-choisie'))).data,
      '04/10/2026',
    );
    expect(find.byKey(const Key('champ-oeufs-pondus-100')), findsOneWidget);
  });

  /// `hidden lg:block` : sous 1 024 px de large, le web n'affiche pas le tableau du mois.
  testWidgets('U11 — le tableau du mois ne s affiche qu à partir de 1 024 px, comme au web', (tester) async {
    await journee(4, recoltes: 100);
    tester.view.physicalSize = const Size(1000, 5200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FichePondeusesScreen(
          depot: depot,
          soins: soins,
          production: production,
          maintenant: () => maintenant,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tableau-mois-pondeuses')), findsNothing);
  });
}
