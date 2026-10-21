import 'dart:io';

import 'package:agrierp/core/comptabilite/exercice_choisi.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/theme/symboles_agri.dart';
import 'package:agrierp/core/widgets/bandeau_exercice.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:agrierp/core/widgets/pagination_agri.dart';
import 'package:agrierp/core/widgets/selecteur_exercice.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/saisie_depenses_screen.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/etats_comparatifs.dart';
import 'package:agrierp/features/elevage/elements_fiche.dart' show LectureSeuleDuJour;
import 'package:agrierp/features/elevage/transferts_bandes_screen.dart';
import 'package:agrierp/features/elevage/transferts_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket EX7 (EF8, EF9, EF10 du PRD `docs/prd/exercices-comptables.md`) — le sélecteur d'exercice au poste, à
/// l'identique du web (`App\Support\ExerciceChoisi`, maître).
///
/// Écrit AVANT les écrans (rouge d'abord) :
///  - PARITÉ EXÉCUTÉE avec le PHP : liste et badges, défaut à l'heure du Bénin, choix mémorisé, bornes, motif, bandeau,
///    période par défaut, mois de référence, libellés de la Balance — 7 décors × 5 « aujourd'hui » × 4 choix ;
///  - choix mémorisé dans les paramètres locaux du poste ;
///  - sélecteur dans la barre supérieure, à gauche de « Synchroniser » ; bandeau « Passer à 2027 » ;
///  - boutons de saisie grisés avec leur motif dans un exercice clos ; listes paginées dans l'exercice ;
///  - garde-fou Blade ↔ poste sur les libellés ;
///  - EX-Q5 : la date d'une dépense comptabilisée est grisée.
String _uuid(String cle) {
  final hex = cle.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  final h = hex.padRight(32, '0').substring(0, 32);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-8${h.substring(17, 20)}-${h.substring(20, 32)}';
}

FiscalYear _ex(int annee, String statut) => FiscalYear(
  id: _uuid('ex$annee'),
  year: annee,
  startDate: DateTime(annee),
  endDate: DateTime(annee, 12, 31),
  status: statut,
);

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Chaînes littérales d'un fichier Dart (`'…'` et `"…"`), comme `chainesDe` de `fidelite_libelles_test.dart` : un
/// commentaire ne satisfait jamais le garde-fou.
Set<String> _litteraux(String chemin) {
  final source = File(chemin).readAsStringSync();
  return {
    for (final m in RegExp(r"'((?:[^'\\\n]|\\.)*)'|" r'"((?:[^"\\\n]|\\.)*)"').allMatches(source))
      (m.group(1) ?? m.group(2)!).replaceAll(r"\'", "'"),
  };
}

void main() {
  final sansPhp = sautSansPhp();

  // ── Parité exécutée avec le PHP du web ─────────────────────────────────────────────────────────────────────

  test('parité exécutée : liste, badges, défaut, choix, bornes, motif, bandeau, périodes = ExerciceChoisi.php', () {
    const decors = [
      <List<Object>>[],
      [
        [2026, 'ouvert'],
      ],
      [
        [2026, 'ouvert'],
        [2027, 'ouvert'],
      ],
      [
        [2025, 'cloture'],
        [2026, 'cloture'],
        [2027, 'ouvert'],
      ],
      [
        [2025, 'cloture'],
        [2026, 'ouvert'],
        [2027, 'ouvert'],
      ],
      [
        [2026, 'cloture'],
      ],
      [
        [2024, 'cloture'],
        [2026, 'ouvert'],
      ],
    ];
    const aujourdhuis = ['2026-03-15', '2026-12-31', '2027-01-01', '2027-02-10', '2028-06-01'];
    const choix = [null, 2026, 2025, 2019];
    const annees = [2019, 2024, 2025, 2026, 2027, 2028];
    const jours = ['2024-06-30', '2025-12-10', '2026-06-30', '2026-12-31', '2027-01-15'];

    final cas = <Map<String, Object?>>[
      for (var d = 0; d < decors.length; d++)
        for (final a in aujourdhuis)
          for (final c in choix) {'decor': d, 'aujourdhui': a, 'choix': c},
    ];

    final php =
        executerPhp(
              '<?php\n$amorceApplication\n'
              r'''
use App\Support\ExerciceChoisi;
$entree = json_decode(file_get_contents($argv[1]), true);
$sortie = [];
foreach ($entree['cas'] as $cas) {
    Illuminate\Support\Facades\DB::beginTransaction();
    foreach ($entree['decors'][$cas['decor']] as [$annee, $statut]) {
        App\Models\FiscalYear::create(['year' => $annee, 'start_date' => "$annee-01-01", 'end_date' => "$annee-12-31", 'status' => $statut]);
    }
    Carbon\Carbon::setTestNow(Carbon\Carbon::parse($cas['aujourdhui'].' 12:00:00', 'Africa/Porto-Novo'));
    if ($cas['choix'] === null) { session()->forget(ExerciceChoisi::CLE_SESSION); } else { session([ExerciceChoisi::CLE_SESSION => $cas['choix']]); }
    $balance = new App\Livewire\Comptabilite\BalanceGenerale();
    $balance->periode = 'mois';
    $moisBalance = $balance->periodBounds();
    $balance->periode = 'exercice';
    $sortie[] = [
        'liste' => ExerciceChoisi::liste(),
        'annee' => ExerciceChoisi::annee(),
        'bornes' => ExerciceChoisi::bornes(),
        'motif' => ExerciceChoisi::motifLectureSeule(),
        'bandeau' => ExerciceChoisi::bandeau(),
        'defaut' => ExerciceChoisi::periodeParDefaut(now()->startOfMonth()->format('Y-m-d'), now()->format('Y-m-d')),
        'arrete' => ExerciceChoisi::dateArrete(),
        'mois' => ExerciceChoisi::moisDeLExercice(),
        'balance' => $balance->getLibellesPeriodeProperty(),
        'balance_mois' => $moisBalance,
        'balance_exercice' => $balance->periodBounds(),
        // Fusion EX7 + EX8 : la date d'arrêté de chaque année (une seule règle : `arreteDe` = `arreteDeLExercice`).
        'arretes' => array_map(fn ($a) => [ExerciceChoisi::arreteDe($a), app(App\Services\FinancialReportService::class)->arreteDeLExercice($a)], $entree['annees']),
        // Fusion EX7 + EX8 : la lecture seule d'un jour de fiche (`AvecMoisDeFiche`) — exercice du jour, motif, bandeau
        // d'EX7, jour de « Passer à … », bandeau masqué quand l'exercice du jour est l'exercice affiché.
        'fiches' => array_map(function ($jour) {
            $e = ExerciceChoisi::exerciceDuJour($jour);
            $bandeau = ExerciceChoisi::bandeauDe($e);
            $cible = $bandeau['cible'] ?? null;
            return [
                'annee' => $e?->year, 'motif' => ExerciceChoisi::motifLectureSeuleDe($e), 'bandeau' => $bandeau,
                'passer' => $cible === null ? null : min(ExerciceChoisi::arreteDe($cible), ExerciceChoisi::aujourdhui()->format('Y-m-d')),
                'visible' => $e !== null && ! ExerciceChoisi::exercice()?->is($e),
            ];
        }, $entree['jours']),
    ];
    Illuminate\Support\Facades\DB::rollBack();
}
echo json_encode($sortie);
''',
              {'decors': decors, 'cas': cas, 'annees': annees, 'jours': jours},
              application: true,
            )!
            as List;

    expect(php, hasLength(cas.length));
    var compares = 0;
    for (final (i, c) in cas.indexed) {
      final exercices = [
        for (final e in decors[c['decor']! as int]) _ex(e[0] as int, e[1] as String),
      ];
      final auj = DateTime.parse('${c['aujourdhui']} 12:00:00');
      final etat = EtatExercice(exercices: exercices, memorise: c['choix'] as int?, aujourdhui: auj);
      final p = php[i] as Map;
      final contexte = 'décor ${c['decor']}, aujourd’hui ${c['aujourdhui']}, choix ${c['choix']}';

      expect(
        [for (final e in etat.liste) {'annee': e.annee, 'statut': e.statut, 'libelle': e.libelle, 'choisi': e.choisi}],
        p['liste'],
        reason: 'liste — $contexte',
      );
      expect(etat.annee, p['annee'], reason: 'annee — $contexte');
      expect([_iso(etat.bornes.debut), _iso(etat.bornes.fin)], p['bornes'], reason: 'bornes — $contexte');
      expect(etat.motifLectureSeule, p['motif'], reason: 'motif — $contexte');
      final bandeau = etat.bandeau;
      expect(bandeau == null ? null : {'texte': bandeau.texte, 'cible': bandeau.cible}, p['bandeau'], reason: 'bandeau — $contexte');
      final defaut = etat.periodeParDefaut(DateTime(auj.year, auj.month), auj);
      expect([_iso(defaut.debut), _iso(defaut.fin)], p['defaut'], reason: 'période par défaut — $contexte');
      expect(_iso(etat.dateArrete), p['arrete'], reason: 'date d’arrêté — $contexte');
      expect(
        {for (final m in etat.moisDeLExercice) '${m.year}-${m.month.toString().padLeft(2, '0')}': EtatExercice.libelleMois(m)},
        p['mois'],
        reason: 'mois de l’exercice — $contexte',
      );
      final libelles = DonneesComptabilite.libellesPeriodeBalance(etat);
      expect({'mois': libelles.mois, 'exercice': libelles.exercice}, p['balance'], reason: 'libellés de la Balance — $contexte');
      final mois = DonneesComptabilite.bornesBalance(PeriodeBalance.mois, etat);
      expect([_iso(mois.debut), _iso(mois.fin)], p['balance_mois'], reason: 'Balance « mois » — $contexte');
      final exo = DonneesComptabilite.bornesBalance(PeriodeBalance.exercice, etat);
      expect([_iso(exo.debut), _iso(exo.fin)], p['balance_exercice'], reason: 'Balance « exercice » — $contexte');
      // Fusion EX7 + EX8 — date d'arrêté de chaque année, au poste par les deux entrées (`EtatExercice.arreteDe`,
      // `EtatsComparatifs.arreteDeLExercice`, colonne N des États Financiers).
      for (final (k, a) in annees.indexed) {
        final attendu = (p['arretes'] as List)[k] as List;
        expect(attendu[0], attendu[1], reason: 'web : arreteDe = arreteDeLExercice ($a) — $contexte');
        expect(_iso(EtatExercice.arreteDe(exercices, a, auj)), attendu[0], reason: 'arrêté $a — $contexte');
        expect(_iso(EtatsComparatifs.arreteDeLExercice(exercices, a, auj)), attendu[0], reason: 'arrêté EX8 $a — $contexte');
      }
      // Fusion EX7 + EX8 — la lecture seule d'un jour de fiche (`LectureSeuleDuJour`, `AvecMoisDeFiche`).
      for (final (k, j) in jours.indexed) {
        final attendu = (p['fiches'] as List)[k] as Map;
        final ls = LectureSeuleDuJour.juger(exercices, DateTime.parse(j), auj);
        final raison = 'fiche du $j — $contexte';
        expect(etat.exerciceDuJour(DateTime.parse(j))?.year, attendu['annee'], reason: raison);
        expect(ls?.motif, attendu['motif'], reason: raison);
        expect(ls == null ? null : {'texte': ls.texte, 'cible': ls.cible}, attendu['bandeau'], reason: raison);
        expect(ls?.jourDeSaisie == null ? null : _iso(ls!.jourDeSaisie!), attendu['passer'], reason: raison);
        if (ls != null) {
          expect(etat.exercice?.year != ls.annee, attendu['visible'], reason: 'bandeau de la fiche visible — $raison');
        }
      }
      compares++;
    }
    expect(compares, 7 * 5 * 4);
  }, skip: sansPhp);

  test('les règles écrites à la main : badges, défaut au Bénin, motif et bandeau', () {
    // 2025 clos, 2026 et 2027 ouverts : 2027 provisoire (2026 ouvert), 2026 ouvert (2025 clos), 2025 clôturé.
    final etat = EtatExercice(
      exercices: [_ex(2025, 'cloture'), _ex(2026, 'ouvert'), _ex(2027, 'ouvert')],
      memorise: null,
      aujourdhui: DateTime(2026, 12, 31, 23, 30),
    );
    expect([for (final e in etat.liste) '${e.annee} ${e.libelle}'], ['2027 Provisoire', '2026 Ouvert', '2025 Clôturé']);
    expect(etat.annee, 2026, reason: 'le 31/12/2026 à 23 h 30 au Bénin : encore 2026');

    final clos = EtatExercice(
      exercices: [_ex(2026, 'cloture'), _ex(2027, 'ouvert')],
      memorise: 2026,
      aujourdhui: DateTime(2027, 3, 20),
    );
    expect(clos.motifLectureSeule, 'Exercice 2026 clôturé — lecture seule');
    expect(clos.bandeau?.texte, "Exercice 2026 clôturé — lecture seule. Les saisies se font dans l'exercice 2027.");
    expect(clos.bandeau?.cible, 2027);
    expect(DonneesComptabilite.libellesPeriodeBalance(clos).exercice, 'Exercice 2026');
    expect(DonneesComptabilite.libellesPeriodeBalance(clos).mois, 'Décembre 2026');
  });

  // ── Choix mémorisé dans les paramètres locaux ─────────────────────────────────────────────────────────────

  group('le service du poste', () {
    late AppDatabase db;

    Future<void> exercice(int annee, String statut) => db
        .into(db.fiscalYears)
        .insert(
          FiscalYearsCompanion.insert(
            id: _uuid('ex$annee'),
            year: annee,
            startDate: Value(DateTime(annee)),
            endDate: Value(DateTime(annee, 12, 31)),
            status: Value(statut),
          ),
        );

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('choix mémorisé dans app_settings, relu au démarrage ; un exercice inconnu est refusé', () async {
      await exercice(2026, 'ouvert');
      await exercice(2027, 'ouvert');
      final service = ExerciceChoisi(db, maintenant: () => DateTime(2027, 2, 10, 10));
      await service.charger();
      expect(service.etat!.annee, 2027);

      expect(await service.choisir(2026), isTrue);
      expect(service.etat!.annee, 2026);
      final ligne = await (db.select(db.appSettings)..where((t) => t.key.equals(ExerciceChoisi.cleParametre))).getSingle();
      expect(ligne.value, '2026');

      final relu = ExerciceChoisi(db, maintenant: () => DateTime(2027, 2, 10, 10));
      await relu.charger();
      expect(relu.etat!.annee, 2026, reason: 'le choix survit au redémarrage du poste');

      expect(await relu.choisir(2031), isFalse);
      expect(relu.etat!.annee, 2026);
    });
  });

  // ── Écrans ─────────────────────────────────────────────────────────────────────────────────────────────────

  group('à l’écran', () {
    late AppDatabase db;
    late ExerciceChoisi service;

    Future<void> exercice(int annee, String statut) => db
        .into(db.fiscalYears)
        .insert(
          FiscalYearsCompanion.insert(
            id: _uuid('ex$annee'),
            year: annee,
            startDate: Value(DateTime(annee)),
            endDate: Value(DateTime(annee, 12, 31)),
            status: Value(statut),
          ),
        );

    Future<void> bande(String id, String code) => db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: _uuid(id),
            code: code,
            speciesId: _uuid('esp'),
            initialQuantity: const Value(500),
            currentQuantity: const Value(500),
          ),
        );

    Future<void> transfert(int n, DateTime jour) => db
        .into(db.livestockTransfers)
        .insert(
          LivestockTransfersCompanion.insert(
            id: _uuid('tr$n'),
            deviceId: 'poste-test',
            updatedAt: jour,
            sourceLotId: _uuid('b1'),
            targetLotId: _uuid('b2'),
            transferDate: jour,
            quantity: 1,
            syncStatus: const Value(SyncStatus.synced),
          ),
        );

    setUp(() async {
      HeureBenin.horloge = () => DateTime.utc(2027, 3, 20, 9);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await exercice(2026, 'cloture');
      await exercice(2027, 'ouvert');
      service = ExerciceChoisi(db, maintenant: () => DateTime(2027, 3, 20, 10));
      await service.charger();
    });

    tearDown(() async {
      ToastAgri.toutRetirer();
      HeureBenin.reinitialiser();
      await db.close();
    });

    void grandEcran(WidgetTester tester) {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Widget sousPortee(Widget enfant) => MaterialApp(
      home: PorteeExerciceChoisi(
        notifier: service,
        child: Scaffold(body: enfant),
      ),
    );

    testWidgets('le sélecteur est dans la barre supérieure, à gauche de Synchroniser, avec ses badges', (tester) async {
      grandEcran(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: PorteeExerciceChoisi(
            notifier: service,
            child: Scaffold(
              body: BarreSuperieure(
                groupe: '',
                ecran: 'Tableau de Bord',
                enAttente: 0,
                onBasculerMenu: () {},
                selecteurExercice: const SelecteurExercice(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final selecteur = find.byKey(const Key('selecteur-exercice'));
      expect(find.descendant(of: selecteur, matching: find.text('Exercice 2027')), findsOneWidget);
      expect(
        tester.getTopLeft(selecteur).dx,
        lessThan(tester.getTopLeft(find.byKey(const Key('bouton-synchroniser'))).dx),
        reason: 'à gauche du bouton Synchroniser, comme au web',
      );

      await tester.tap(selecteur);
      await tester.pumpAndSettle();
      expect(find.text('Exercice affiché'), findsOneWidget);
      final badge2027 = find.byKey(const Key('badge-exercice-2027'));
      final badge2026 = find.byKey(const Key('badge-exercice-2026'));
      expect(find.descendant(of: badge2027, matching: find.text('Ouvert')), findsOneWidget);
      expect(find.descendant(of: badge2026, matching: find.text('Clôturé')), findsOneWidget);
      expect(find.descendant(of: badge2026, matching: find.byIcon(SymbolesAgri.lock)), findsOneWidget, reason: 'cadenas');

      await tester.tap(find.byKey(const Key('selecteur-exercice-2026')));
      await tester.pumpAndSettle();
      expect(service.etat!.annee, 2026);
      expect(find.descendant(of: selecteur, matching: find.text('Exercice 2026')), findsOneWidget);
    });

    testWidgets('bandeau d’un exercice clos et lien « Passer à 2027 »', (tester) async {
      await service.choisir(2026);
      await tester.pumpWidget(sousPortee(const BandeauExercice()));
      await tester.pumpAndSettle();

      expect(find.text("Exercice 2026 clôturé — lecture seule. Les saisies se font dans l'exercice 2027."), findsOneWidget);
      await tester.tap(find.text('Passer à 2027'));
      await tester.pumpAndSettle();
      expect(service.etat!.annee, 2027);
      expect(find.byKey(const Key('bandeau-exercice')), findsNothing, reason: 'exercice ouvert : pas de bandeau');
    });

    testWidgets('exercice clos : « Nouveau Transfert » grisé, motif en info-bulle ; liste paginée dans l’exercice', (
      tester,
    ) async {
      grandEcran(tester);
      await bande('b1', 'PON-A');
      await bande('b2', 'PON-B');
      // 27 transferts en 2026 (deux pages de 25), un en 2027.
      for (var n = 0; n < 27; n++) {
        await transfert(n, DateTime(2026, 1, 5 + n * 13));
      }
      await transfert(99, DateTime(2027, 1, 20));
      await service.choisir(2026);

      await tester.pumpWidget(sousPortee(TransfertsBandesScreen(depot: TransfertsRepository(database: db, deviceId: 'poste-test'))));
      await tester.pumpAndSettle();

      final bouton = tester.widget<FilledButton>(find.byKey(const Key('transfert-nouveau')));
      expect(bouton.onPressed, isNull, reason: 'grisé dans un exercice clos');
      expect(
        find.ancestor(of: find.byKey(const Key('transfert-nouveau')), matching: find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Exercice 2026 clôturé — lecture seule')),
        findsOneWidget,
      );

      expect(find.byKey(const Key('ligne-transfert-${'tr99'}')), findsNothing);
      expect(find.textContaining('PON-A → PON-B'), findsNWidgets(25));
      expect(find.text("27 lignes dans l'exercice 2026 — page 1 sur 2"), findsOneWidget);
      await tester.tap(find.byKey(const Key('pagination-transferts-suivant')));
      await tester.pumpAndSettle();
      expect(find.textContaining('PON-A → PON-B'), findsNWidgets(2));
      expect(find.text("27 lignes dans l'exercice 2026 — page 2 sur 2"), findsOneWidget);

      // Retour à 2027 (ouvert) : bouton actif, une seule ligne.
      await service.choisir(2027);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(sousPortee(TransfertsBandesScreen(depot: TransfertsRepository(database: db, deviceId: 'poste-test'))));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const Key('transfert-nouveau'))).onPressed, isNotNull);
      expect(find.textContaining('PON-A → PON-B'), findsOneWidget);
      expect(find.text("1 ligne dans l'exercice 2027 — page 1 sur 1"), findsOneWidget);
    });

    testWidgets('exercice clos : « Nouvelle Dépense » grisé avec son motif', (tester) async {
      grandEcran(tester);
      await service.choisir(2026);
      await tester.pumpWidget(sousPortee(SaisieDepensesScreen(depot: DepensesRepository(database: db, deviceId: 'poste-test'))));
      await tester.pumpAndSettle();
      final bouton = tester.widget<FilledButton>(find.byKey(const Key('bouton-nouvelle-depense')));
      expect(bouton.onPressed, isNull);
      expect(
        find.ancestor(
          of: find.byKey(const Key('bouton-nouvelle-depense')),
          matching: find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Exercice 2026 clôturé — lecture seule'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('DEP1 (remplace EX-Q5) : une dépense comptabilisée n’a plus de « Modifier » — sa date comprise', (tester) async {
      grandEcran(tester);
      await db.into(db.treasuryAccounts).insert(TreasuryAccountsCompanion.insert(id: _uuid('t1'), label: 'Caisse', balance: const Value(1000)));
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: _uuid('d1'),
              deviceId: 'poste-test',
              updatedAt: DateTime(2027, 2, 5),
              expenseDate: DateTime(2027, 2, 5),
              label: 'Carburant',
              category: '605 - Énergie',
              amount: 5000,
              treasuryAccountId: _uuid('t1'),
              accountingEntryId: Value(_uuid('e1')),
              syncStatus: const Value(SyncStatus.synced),
            ),
          );
      await tester.pumpWidget(sousPortee(SaisieDepensesScreen(depot: DepensesRepository(database: db, deviceId: 'poste-test'))));
      await tester.pumpAndSettle();

      expect(find.text('Carburant'), findsOneWidget);
      expect(find.byKey(Key('depense-modifier-${_uuid('d1')}')), findsNothing, reason: 'immuable : le web n’offre pas le crayon');
      expect(find.byKey(Key('depense-archiver-${_uuid('d1')}')), findsOneWidget, reason: 'se corrige par archivage (contre-passation)');
    });
  });

  // ── Garde-fou Blade ↔ poste ────────────────────────────────────────────────────────────────────────────────

  final php = File('$dossierLaravel/app/Support/ExerciceChoisi.php');
  final sansLaravel = php.existsSync() ? false : 'dépôt Laravel absent ($dossierLaravel)';

  test('libellés du sélecteur, du bandeau et de la pagination : ceux du web, mot pour mot', () {
    final source = php.readAsStringSync();
    final libellesPhp = {
      for (final m in RegExp(r"'(\w+)' => '([^']+)'").allMatches(RegExp(r'LIBELLES = \[(.*?)\];').firstMatch(source)!.group(1)!))
        m.group(1)!: m.group(2)!,
    };
    expect(ExerciceChoisi.libelles, libellesPhp);
    expect(source, contains("PAR_PAGE = ${ExerciceChoisi.parPage};"));
    expect(source, contains('"Exercice {\$exercice->year} clôturé — lecture seule"'));
    expect(source, contains("\" Les saisies se font dans l'exercice {\$saisie->year}.\""));

    String blade(String f) => File('$dossierLaravel/resources/views/$f').readAsStringSync();
    final selecteur = blade('livewire/shared/selecteur-exercice.blade.php');
    // Fusion EX7 + EX8 : le bandeau du haut du contenu et celui des fiches sont UN composant (`x-bandeau-lecture-seule`).
    final bandeau = blade('components/bandeau-lecture-seule.blade.php');
    expect(blade('livewire/shared/bandeau-exercice.blade.php'), contains('<x-bandeau-lecture-seule'));
    final pagination = blade('components/pagination.blade.php');

    final posteSelecteur = _litteraux('lib/core/widgets/selecteur_exercice.dart');
    final posteBandeau = _litteraux('lib/core/widgets/bandeau_exercice.dart');
    final postePagination = _litteraux('lib/core/widgets/pagination_agri.dart');

    for (final libelle in ['Exercice affiché', "Aucun exercice comptable n'est encore ouvert."]) {
      expect(selecteur, contains(libelle));
      expect(posteSelecteur, contains(libelle), reason: 'sélecteur du poste : « $libelle »');
    }
    expect(selecteur, contains('>lock</span>'), reason: 'cadenas du badge « Clôturé » au web');
    expect(File('lib/core/widgets/selecteur_exercice.dart').readAsStringSync(), contains('SymbolesAgri.lock'));

    expect(bandeau, contains('Passer à {{'));
    expect(posteBandeau.any((s) => s.startsWith('Passer à ')), isTrue);

    for (final libelle in ['Précédent', 'Suivant', "dans l'exercice", 'lignes', 'ligne', 'page', 'sur']) {
      expect(pagination, contains(libelle));
    }
    expect(postePagination, containsAll(['Précédent', 'Suivant']));
    expect(
      PaginationAgri.texte(total: 27, page: 1, pages: 2, annee: 2026),
      "27 lignes dans l'exercice 2026 — page 1 sur 2",
    );
    expect(PaginationAgri.texte(total: 1, page: 1, pages: 1, annee: 2027), "1 ligne dans l'exercice 2027 — page 1 sur 1");
    expect(pagination, contains("{{ \$total }} {{ \$total > 1 ? 'lignes' : 'ligne' }} dans l'exercice {{ \\App\\Support\\ExerciceChoisi::annee() }} — page {{ \$paginator->currentPage() }} sur {{ \$paginator->lastPage() }}"));
  }, skip: sansLaravel);

  test('garde-fou : chaque écran piloté lit l’exercice affiché par le point de passage commun', () {
    // Les écrans de l'EF9 au poste : ils bornent leurs listes et grisent leurs boutons par `PorteeExerciceChoisi`,
    // jamais par une lecture directe de `fiscal_years` ou de l'année du jour.
    const ecrans = [
      'lib/features/comptabilite/comptabilite_screen.dart',
      'lib/features/elevage/transferts_bandes_screen.dart',
      'lib/features/elevage/soins_vaccins_screen.dart',
      'lib/features/achats/saisie_depenses_screen.dart',
      'lib/features/achats/achats_commandes_screen.dart',
      'lib/features/stocks/gestion_stocks_screen.dart',
      'lib/features/ventes/historique_ventes_onglet.dart',
      'lib/features/ventes/facturation_screen.dart',
      'lib/features/rapports/rapports_exports_screen.dart',
      'lib/features/pilotage/tableau_de_bord_screen.dart',
    ];
    for (final chemin in ecrans) {
      expect(File(chemin).readAsStringSync(), contains('PorteeExerciceChoisi'), reason: chemin);
    }
    final socle = File('lib/main.dart').readAsStringSync();
    expect(socle, contains('PorteeExerciceChoisi('));
    expect(socle, contains('SelecteurExercice('));
    expect(socle, contains('BandeauExercice('));
  });
}
