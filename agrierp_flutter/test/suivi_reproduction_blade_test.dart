import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/theme/agri_theme.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/widgets/modale_agri.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/elevage/fiche_escargots_screen.dart';
import 'package:agrierp/features/elevage/fiche_reproducteurs_screen.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_repository.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'coque_poste.dart';

/// Ticket H7 — SUIVI REPRODUCTION DU POSTE ALIGNÉ SUR LE BLADE (le maître, doctrine art. 5).
///
/// ⚠️⚠️ **LES ATTENDUS SONT LUS DANS LE BLADE ET DANS LE COMPOSANT LIVEWIRE**, jamais recopiés
/// ici : colonnes, statuts, titres, sous-titres, étapes du rappel du cycle, libellés et icônes des
/// KPI, modales, état vide, messages des toasts. Un libellé qui change au web fait rougir ce
/// fichier au lieu de laisser le poste diverger en silence — c'est précisément ce qui s'était
/// produit : l'écran avait été porté depuis la maquette, et ses garde-fous comparaient à la
/// maquette.
///
/// ⚠️⚠️ **LES ACTIONS DE CYCLE SONT PORTÉES MAIS FERMÉES.** `SyncController::pushReproductionEvents`
/// est « CRÉATION SEULE, JAMAIS MISE À JOUR » : un id déjà connu est acquitté sans rien rejouer.
/// Une palpation saisie au poste partirait donc, serait acquittée, marquée `synced`… puis écrasée
/// par le tirage suivant, sans que rien ne le signale. Le repository sait écrire la ligne (testé
/// ci-dessous, verrou ouvert) ; l'écran affiche les boutons du Blade, grisés, et dit pourquoi.
final _blade = File(
  '$dossierLaravel/resources/views/livewire/elevage/suivi-reproduction.blade.php',
);
final _livewire = File(
  '$dossierLaravel/app/Livewire/Elevage/SuiviReproduction.php',
);
final _rappel = File(
  '$dossierLaravel/resources/views/components/cycle-reminder.blade.php',
);

/// Sans le dépôt Laravel, ces contrôles se sautent : ils n'ont rien à quoi comparer.
final bool _sansBlade =
    !_blade.existsSync() || !_livewire.existsSync() || !_rappel.existsSync();

/// Icônes Material Symbols du Blade → icônes Flutter du poste (mêmes noms).
const _icones = <String, IconData>{
  'cruelty_free': Icons.cruelty_free,
  'egg': Icons.egg,
  'pets': Icons.pets,
  'bug_report': Icons.bug_report,
  'favorite': Icons.favorite,
  'event': Icons.event,
  'child_care': Icons.child_care,
  'warning': Icons.warning,
  'egg_alt': Icons.egg_alt,
  'edit_note': Icons.edit_note,
  'add_circle': Icons.add_circle,
  'event_repeat': Icons.event_repeat,
  'arrow_forward': Icons.arrow_forward,
};

/// Lecture du Blade : chaque expression qu'il emploie est résolue pour une filière donnée.
class _LecteurBlade {
  _LecteurBlade()
    : source = _blade.readAsStringSync(),
      php = _livewire.readAsStringSync(),
      rappel = _rappel.readAsStringSync();

  final String source;
  final String php;
  final String rappel;

  /// `$checkLabel = $isLapins ? 'Palpation' : 'Retour Chaleur';`
  late final (String, String) controles = () {
    final m = RegExp(
      r"\$checkLabel = \$isLapins \? '([^']*)' : '([^']*)';",
    ).firstMatch(source)!;
    return (m[1]!, m[2]!);
  }();

  /// `$offsets = $isLapins ? ['check' => 14, …] : ['check' => 21, …];`
  late final (Map<String, int>, Map<String, int>) decalages = () {
    final m = RegExp(
      r'\$offsets = \$isLapins \? \[(.*?)\] : \[(.*?)\];',
    ).firstMatch(source)!;
    Map<String, int> lire(String s) => {
      for (final e in RegExp(r"'(\w+)' => (\d+)").allMatches(s))
        e[1]!: int.parse(e[2]!),
    };
    return (lire(m[1]!), lire(m[2]!));
  }();

  String controle(bool lapins) => lapins ? controles.$1 : controles.$2;
  Map<String, int> offsets(bool lapins) =>
      lapins ? decalages.$1 : decalages.$2;

  /// Résout un fragment du Blade en texte affiché (balises, icônes et entités retirées).
  String resoudre(String s, {bool lapins = true, bool volailles = true}) {
    var t = s.replaceAll(
      RegExp(r'<span class="material-symbols-outlined[^"]*">.*?</span>'),
      '',
    );
    t = t.replaceAllMapped(
      RegExp(r"\{\{\s*\$isLapins \? '([^']*)' : '([^']*)'\s*\}\}"),
      (m) => lapins ? m[1]! : m[2]!,
    );
    t = t.replaceAllMapped(
      RegExp(r"\{\{\s*\$tab === 'volailles' \? '([^']*)' : '([^']*)'\s*\}\}"),
      (m) => volailles ? m[1]! : m[2]!,
    );
    t = t.replaceAll(
      RegExp(r'\{\{\s*strtolower\(\$checkLabel\)\s*\}\}'),
      controle(lapins).toLowerCase(),
    );
    t = t.replaceAll(
      RegExp(r'\{\{\s*\$checkLabel\s*\}\}'),
      controle(lapins),
    );
    t = t.replaceAllMapped(
      RegExp(r"\{\{\s*\$offsets\['(\w+)'\]\s*\}\}"),
      (m) => '${offsets(lapins)[m[1]]}',
    );
    t = t.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&amp;', '&');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> tous(String motif, {bool lapins = true, bool volailles = true}) =>
      [
        for (final m in RegExp(motif, dotAll: true).allMatches(source))
          resoudre(m[1]!, lapins: lapins, volailles: volailles),
      ];

  /// Les neuf `<th>` du tableau.
  List<String> colonnes(bool lapins) =>
      tous(r'<th[^>]*>(.*?)</th>', lapins: lapins);

  /// Les quatre pastilles de statut, dans l'ordre du `@if`.
  List<String> get statuts => tous(
    r'<span class="inline-flex items-center px-sm[^"]*">([^<]+)</span>',
  );

  /// Les boutons de la cellule « Action ».
  List<String> actions(bool lapins) => tous(
    r'<button type="button" wire:click="(?:recordPalpation|openMiseBasModal|closeCycle)[^"]*"[^>]*>(.*?)</button>',
    lapins: lapins,
  );

  String get etatVide =>
      RegExp(r'colspan="9"[^>]*>([^<]+)</td>').firstMatch(source)![1]!.trim();

  /// `<h2>` : le premier est celui de Lapins / Porcs, le second celui du couvoir.
  String titre(bool lapins) => tous(r'<h2[^>]*>(.*?)</h2>', lapins: lapins)[0];
  String titreCouvoir(bool volailles) =>
      tous(r'<h2[^>]*>(.*?)</h2>', volailles: volailles)[1];

  String sousTitre(bool lapins) =>
      tous(r'<p class="text-xs text-outline mt-xs">(.*?)</p>', lapins: lapins)[0];
  String get texteCouvoir =>
      tous(r'<p class="text-xs text-outline mt-xs">(.*?)</p>')[1];

  String boutonDeclarer(bool lapins) => tous(
    r'<button type="button" wire:click="newDeclaration"[^>]*>(.*?)</button>',
    lapins: lapins,
  ).single;

  String get lienCouvoir => tous(r'<a href=[^>]*>(.*?)</a>').single;
  String get iconeLienCouvoir => RegExp(
    r'<a href=[^>]*>\s*<span class="material-symbols-outlined[^"]*">(\w+)</span>',
  ).firstMatch(source)![1]!;

  /// `<x-kpi-card label="…" icon="…">` : les quatre du haut, puis les trois du couvoir.
  List<(String, String)> get kpi => [
    for (final m in RegExp(
      r'<x-kpi-card label="([^"]+)" icon="([^"]+)"',
    ).allMatches(source))
      (m[1]!.replaceAll('&amp;', '&'), m[2]!),
  ];

  List<(String, String)> get onglets => [
    for (final m in RegExp(
      r"\['key' => '\w+', 'label' => '([^']+)', 'icon' => '(\w+)'\]",
    ).allMatches(source))
      (m[1]!, m[2]!),
  ];

  /// Étapes de `<x-cycle-reminder :steps="[…]">`, évaluées pour la filière, et leur état actif.
  List<(String, bool)> etapes(bool lapins) {
    final bloc = RegExp(
      r'<x-cycle-reminder :steps="\[(.*?)\]" />',
      dotAll: true,
    ).firstMatch(source)![1]!;
    // ⚠️ Une étape par ligne, ancrée en fin de ligne : sans l'ancre, le `],` de
    // `$offsets['misebas'],` passait pour la fin de l'étape et « active » était perdu.
    return [
      for (final m in RegExp(
        r"\['label' => (.*?)(, 'active' => true)?\],?$",
        multiLine: true,
      ).allMatches(bloc))
        (
          RegExp(r"'([^']*)'|\$checkLabel|\$offsets\['(\w+)'\]")
              .allMatches(m[1]!)
              .map(
                (j) => j[0] == r'$checkLabel'
                    ? controle(lapins)
                    : j[2] != null
                    ? '${offsets(lapins)[j[2]]}'
                    : j[1]!,
              )
              .join(),
          m[2] != null,
        ),
    ];
  }

  String get libelleRappel => RegExp(
    r'<p class="text-xs font-bold text-brand-forest[^"]*">([^<]+)</p>',
  ).firstMatch(rappel)![1]!.trim();

  List<String> titresModales(bool lapins) =>
      tous(r'<h3[^>]*>(.*?)</h3>', lapins: lapins);
  List<String> etiquettes(bool lapins) =>
      tous(r'<label[^>]*>(.*?)</label>', lapins: lapins);
  List<String> exemples(bool lapins) =>
      tous(r'placeholder="([^"]*)"', lapins: lapins);
  String get optionVide =>
      RegExp(r'<option value="">([^<]+)</option>').firstMatch(source)![1]!;
  List<String> get boutonsValider =>
      tous(r'<button type="submit"[^>]*>(.*?)</button>');

  /// Les messages des toasts du composant, dans l'ordre : saillie, palpation, mise bas, clôture.
  List<String> get messages => [
    for (final m in RegExp(
      r"dispatch\('toast', message: '([^']+)'",
    ).allMatches(php))
      m[1]!,
  ];
}

void main() {
  late AppDatabase db;
  late SuiviReproductionRepository depot;
  late _LecteurBlade blade;

  const bandeLapins = 'aaaaaaaa-0000-4000-8000-aaaaaaaaaaaa';
  const bandePorcs = 'bbbbbbbb-0000-4000-8000-bbbbbbbbbbbb';
  const bandeVolailles = 'cccccccc-0000-4000-8000-cccccccccccc';

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final maintenant = DateTime.now();
  final aujourdhui = DateTime(
    maintenant.year,
    maintenant.month,
    maintenant.day,
  );
  DateTime ilYA(int jours) => DateTime(
    aujourdhui.year,
    aujourdhui.month,
    aujourdhui.day - jours,
  );
  String jj(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  setUp(() async {
    if (!_sansBlade) blade = _LecteurBlade();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = SuiviReproductionRepository(database: db, deviceId: 'poste-test');

    Future<void> bande(
      String id,
      String code,
      String espece, {
      String? statut = 'actif',
      bool active = true,
    }) => db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: id,
            code: code,
            speciesId: 'esp-$espece',
            speciesCode: Value(espece),
            currentQuantity: const Value(50),
            status: Value(statut),
            isActive: Value(active),
          ),
        );

    await bande(bandeLapins, 'LOT-LAP-2026-06', 'cuniculture');
    await bande(bandePorcs, 'BANDE-POR-P1', 'porciculture');
    await bande(bandeVolailles, 'VOL-REPRO-LOT-1', 'aviculture');
    // Deux bandes de lapins que la modale ne doit PAS proposer : le Blade filtre
    // `status = 'actif'` ET `is_active`.
    await bande(
      'dddddddd-0000-4000-8000-dddddddddddd',
      'LOT-LAP-VENDU',
      'cuniculture',
      statut: 'vendu',
    );
    await bande(
      'eeeeeeee-0000-4000-8000-eeeeeeeeeeee',
      'LOT-LAP-ARCHIVE',
      'cuniculture',
      active: false,
    );
  });

  tearDown(() async {
    ToastAgri.toutRetirer();
    await db.close();
  });

  Future<String> cycle(
    String cle,
    String lot,
    String mere, {
    String? male,
    int saillieIlYA = 20,
    int? palpationIlYA,
    int? miseBasIlYA,
    int? nesVivants,
    int? nesMorts,
    String status = 'en_cours',
  }) async {
    final id = uuid('$cle-repro');
    await db
        .into(db.livestockReproductionEvents)
        .insert(
          LivestockReproductionEventsCompanion.insert(
            id: id,
            deviceId: 'serveur',
            syncStatus: const Value(SyncStatus.synced),
            lotId: lot,
            motherRef: mere,
            sireRef: Value(male),
            saillieDate: Value(ilYA(saillieIlYA)),
            palpationDate: Value(
              palpationIlYA == null ? null : ilYA(palpationIlYA),
            ),
            miseBasDateActual: Value(
              miseBasIlYA == null ? null : ilYA(miseBasIlYA),
            ),
            nesVivants: Value(nesVivants),
            nesMorts: Value(nesMorts),
            status: Value(status),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
    return id;
  }

  Future<LivestockReproductionEvent> ligne(String id) => (db.select(
    db.livestockReproductionEvents,
  )..where((t) => t.id.equals(id))).getSingle();

  final ouvertures = <String>[];

  Future<void> afficher(
    WidgetTester tester, {
    SuiviReproductionRepository? avec,
  }) async {
    tester.view.physicalSize = const Size(1800, 2400);
    tester.view.devicePixelRatio = 1;
    ouvertures.clear();

    await tester.pumpWidget(
      MaterialApp(
        home: SuiviReproductionScreen(
          depot: avec ?? depot,
          onSaisirCouvoir: ouvertures.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-repro-$onglet')));
    await tester.pumpAndSettle();
  }

  Finder dansModale(String texte) => find.descendant(
    of: find.byType(ModaleAgri),
    matching: find.text(texte),
  );

  List<String> textesDe(WidgetTester tester, Finder parent) => tester
      .widgetList<Text>(find.descendant(of: parent, matching: find.byType(Text)))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .toList();

  // ── Lecteur du Blade : s'il se trompe, tout le reste se trompe avec lui ─────

  group('lecteur du Blade', () {
    test('il lit neuf colonnes par filière et les résout', () {
      expect(blade.colonnes(true), hasLength(9));
      expect(blade.colonnes(true)[1], 'N° Lapine');
      expect(blade.colonnes(false)[1], 'N° Truie');
      expect(blade.colonnes(false)[4], 'Retour Chaleur');
    }, skip: _sansBlade);

    test('il lit les quatre statuts, les quatre messages, sept KPI', () {
      expect(blade.statuts, hasLength(4));
      expect(blade.messages, hasLength(4));
      expect(blade.kpi, hasLength(7));
      expect(blade.etapes(true), hasLength(4));
    }, skip: _sansBlade);
  });

  // ── Structure et libellés ─────────────────────────────────────────────────

  group('structure', () {
    testWidgets('les onglets du Blade, leurs icônes, PUIS les KPI', (
      tester,
    ) async {
      await afficher(tester);

      for (final (libelle, icone) in blade.onglets) {
        final onglet = find.byKey(Key('onglet-repro-$libelle'));
        expect(onglet, findsOneWidget, reason: libelle);
        expect(
          find.descendant(of: onglet, matching: find.byIcon(_icones[icone]!)),
          findsOneWidget,
          reason: '$libelle : icône $icone',
        );
      }

      // ⚠️ `<x-tab-page>` enveloppe l'accordéon des KPI : les onglets sont AU-DESSUS.
      final yOnglets = tester
          .getTopLeft(find.byKey(Key('onglet-repro-${blade.onglets.first.$1}')))
          .dy;
      final yKpi = tester.getTopLeft(find.byType(CarteKpi).first).dy;
      expect(yOnglets, lessThan(yKpi));
    }, skip: _sansBlade);

    testWidgets('les quatre KPI du Blade : libellés et icônes, dans l ordre', (
      tester,
    ) async {
      await afficher(tester);

      final cartes = tester.widgetList<CarteKpi>(find.byType(CarteKpi)).toList();
      final attendus = blade.kpi.take(4).toList();

      expect(cartes.map((c) => c.libelle), attendus.map((k) => k.$1));
      expect(cartes.map((c) => c.icone), attendus.map((k) => _icones[k.$2]));
    }, skip: _sansBlade);

    for (final lapins in [true, false]) {
      final filiere = lapins ? 'lapins' : 'porcs';

      testWidgets('$filiere : titre, sous-titre et bouton du Blade', (
        tester,
      ) async {
        await afficher(tester);
        if (!lapins) await ouvrir(tester, 'Porcs');

        expect(find.text(blade.titre(lapins)), findsOneWidget);
        expect(find.text(blade.sousTitre(lapins)), findsOneWidget);
        expect(find.text(blade.boutonDeclarer(lapins)), findsOneWidget);
      }, skip: _sansBlade);

      testWidgets(
        '$filiere : le rappel du cycle a les quatre étapes du Blade et ses flèches',
        (tester) async {
          await afficher(tester);
          if (!lapins) await ouvrir(tester, 'Porcs');

          final rappel = find.byKey(Key('rappel-cycle-$filiere'));
          final etapes = blade.etapes(lapins);

          expect(textesDe(tester, rappel), [
            blade.libelleRappel,
            ...etapes.map((e) => e.$1),
          ]);
          expect(
            find.descendant(of: rappel, matching: find.byIcon(Icons.arrow_forward)),
            findsNWidgets(etapes.length - 1),
          );
          // L'étape active du Blade est la seule en vert.
          final active = etapes.firstWhere((e) => e.$2).$1;
          final texte = tester.widget<Text>(
            find.descendant(of: rappel, matching: find.text(active)),
          );
          expect(texte.style?.color, AgriColors.brandEmerald);
        },
        skip: _sansBlade,
      );

      testWidgets(
        '$filiere : neuf colonnes du Blade, dans son ordre, PUIS les ajouts du poste',
        (tester) async {
          await afficher(tester);
          if (!lapins) await ouvrir(tester, 'Porcs');

          final entetes = textesDe(
            tester,
            find.byKey(Key('entete-cycles-$filiere')),
          );

          expect(
            entetes.take(9).toList(),
            blade.colonnes(lapins).map((c) => c.toUpperCase()).toList(),
          );
          // Décision client du 19/10/2026 : les ajouts du poste sont gardés, APRÈS le Blade.
          expect(
            entetes.skip(9).toList(),
            lapins
                ? ['SEVRÉS (M/F)', 'MORTS S/MÈRE', 'POIDS MOYEN (G)', 'CAGES']
                : ['SEVRAGE (J+42)'],
          );
        },
        skip: _sansBlade,
      );
    }

    testWidgets('lapins : « Boîte à nid J+28 » en ligne annexe, hors du rappel', (
      tester,
    ) async {
      await afficher(tester);

      final rappel = find.byKey(const Key('rappel-cycle-lapins'));
      expect(
        find.descendant(of: rappel, matching: find.textContaining('Boîte à nid')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('jalon-annexe-lapins')),
          matching: find.textContaining('Boîte à nid J+28'),
        ),
        findsOneWidget,
      );
    }, skip: _sansBlade);

    testWidgets('sans saillie, l état vide du Blade', (tester) async {
      await afficher(tester);
      expect(find.text(blade.etatVide), findsOneWidget);
    }, skip: _sansBlade);
  });

  // ── Couvoir ───────────────────────────────────────────────────────────────

  group('couvoir', () {
    for (final volailles in [true, false]) {
      final onglet = volailles ? 'Volailles' : 'Escargots';

      testWidgets('$onglet : titre, texte, trois KPI et lien du Blade', (
        tester,
      ) async {
        await afficher(tester);
        await ouvrir(tester, onglet);

        expect(find.text(blade.titreCouvoir(volailles)), findsOneWidget);
        expect(find.text(blade.texteCouvoir), findsOneWidget);

        // Les quatre du haut, puis les trois du couvoir (et « Bandes suivies », ajout gardé).
        final cartes = tester.widgetList<CarteKpi>(find.byType(CarteKpi)).toList();
        final couvoir = blade.kpi.skip(4).toList();
        expect(
          cartes.skip(4).take(3).map((c) => c.libelle),
          couvoir.map((k) => k.$1),
        );
        expect(
          cartes.skip(4).take(3).map((c) => c.icone),
          couvoir.map((k) => _icones[k.$2]),
        );
        expect(cartes.skip(7).map((c) => c.libelle), ['Bandes suivies']);

        // ⚠️ Rien de couvé : le Blade affiche « 0,0 % » (`number_format(0, 1, ',', ' ')`).
        expect(find.text('0,0 %'), findsOneWidget);

        final lien = find.byKey(const Key('lien-couvoir'));
        expect(
          find.descendant(of: lien, matching: find.text(blade.lienCouvoir)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: lien,
            matching: find.byIcon(_icones[blade.iconeLienCouvoir]!),
          ),
          findsOneWidget,
        );

        await tester.tap(lien);
        await tester.pumpAndSettle();
        expect(ouvertures, [volailles ? 'aviculture' : 'helico']);
      }, skip: _sansBlade);
    }

    testWidgets('le taux d éclosion s écrit à la française, une décimale', (
      tester,
    ) async {
      await db
          .into(db.livestockDailyEntries)
          .insert(
            LivestockDailyEntriesCompanion.insert(
              id: uuid('f-couvoir'),
              deviceId: 'poste-test',
              updatedAt: maintenant,
              lotId: bandeVolailles,
              entryDate: aujourdhui,
              ne: const Value(102),
              ponteTotal: const Value(120),
              effectifFinal: const Value(200),
            ),
          );

      await afficher(tester);
      await ouvrir(tester, 'Volailles');

      // 102 / 120 = 85 % — calculé à la main.
      expect(find.text('85,0 %'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('102'), findsOneWidget);
    });
  });

  // ── Cellules et statuts ───────────────────────────────────────────────────

  group('cellules', () {
    testWidgets('palpation, mise bas et nés : les cellules du Blade', (
      tester,
    ) async {
      // Palpée positive il y a 6 jours, mise bas faite il y a 2 jours : 7 vivants, 1 mort.
      await cycle(
        'pos',
        bandeLapins,
        'R1',
        male: 'M3',
        saillieIlYA: 32,
        palpationIlYA: 18,
        miseBasIlYA: 2,
        nesVivants: 7,
        nesMorts: 1,
      );
      // Palpée négative.
      await cycle(
        'neg',
        bandeLapins,
        'R2',
        saillieIlYA: 25,
        palpationIlYA: 10,
        status: 'echec',
      );
      // Non palpée, échéance J+14 passée → « Prévue » en rouge.
      await cycle('due', bandeLapins, 'R3', saillieIlYA: 20);
      // Non palpée, échéance à venir → « Prévue » en gris.
      await cycle('att', bandeLapins, 'R4', saillieIlYA: 3);

      await afficher(tester);

      expect(find.text('${jj(ilYA(18))} (Positif)'), findsOneWidget);
      expect(find.text('${jj(ilYA(10))} (Négatif)'), findsOneWidget);

      final due = tester.widget<Text>(find.text('Prévue ${jj(ilYA(6))}'));
      expect(due.style?.color, AgriColors.errorDeep);
      expect(due.style?.fontWeight, FontWeight.bold);
      final aVenir = tester.widget<Text>(find.text('Prévue ${jj(ilYA(3 - 14))}'));
      expect(aVenir.style?.color, AgriColors.outline);

      // Mise bas : la date RÉELLE quand elle existe, sinon saillie + 30.
      expect(find.text(jj(ilYA(2))), findsOneWidget);
      expect(find.text(jj(ilYA(20 - 30))), findsOneWidget);

      expect(find.text('7 (1 morts)'), findsOneWidget);
      // Le mâle absent et les nés inconnus : un tiret.
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('porcs : retour chaleur J+21 et mise bas J+114', (
      tester,
    ) async {
      await cycle('t1', bandePorcs, 'T1', male: 'V2', saillieIlYA: 0);

      await afficher(tester);
      await ouvrir(tester, 'Porcs');

      expect(find.text('Prévue ${jj(ilYA(-21))}'), findsOneWidget);
      expect(find.text(jj(ilYA(-114))), findsOneWidget);
    });

    testWidgets('les quatre statuts du Blade', (tester) async {
      await cycle('ec', bandeLapins, 'R1', palpationIlYA: 5, status: 'echec');
      await cycle(
        'te',
        bandeLapins,
        'R2',
        saillieIlYA: 80,
        palpationIlYA: 60,
        miseBasIlYA: 45,
        nesVivants: 6,
        nesMorts: 0,
        status: 'termine',
      );
      await cycle(
        'al',
        bandeLapins,
        'R3',
        saillieIlYA: 35,
        palpationIlYA: 20,
        miseBasIlYA: 5,
        nesVivants: 8,
        nesMorts: 0,
      );
      await cycle('ge', bandeLapins, 'R4', saillieIlYA: 5);

      await afficher(tester);

      for (final statut in blade.statuts) {
        expect(find.text(statut), findsOneWidget, reason: statut);
      }
    }, skip: _sansBlade);

    for (final lapins in [true, false]) {
      testWidgets(
        '${lapins ? 'lapins' : 'porcs'} : les boutons d action du Blade, selon l état du cycle',
        (tester) async {
          final lot = lapins ? bandeLapins : bandePorcs;
          await cycle('a', lot, 'F1', saillieIlYA: 5);
          await cycle('b', lot, 'F2', saillieIlYA: 30, palpationIlYA: 10);
          await cycle(
            'c',
            lot,
            'F3',
            saillieIlYA: 40,
            palpationIlYA: 20,
            miseBasIlYA: 3,
            nesVivants: 5,
            nesMorts: 0,
          );
          await cycle(
            'd',
            lot,
            'F4',
            saillieIlYA: 90,
            palpationIlYA: 70,
            miseBasIlYA: 50,
            nesVivants: 5,
            nesMorts: 0,
            status: 'termine',
          );
          await cycle('e', lot, 'F5', palpationIlYA: 3, status: 'echec');

          await afficher(tester);
          if (!lapins) await ouvrir(tester, 'Porcs');

          final actions = blade.actions(lapins);
          // « Palpation + » et « Palpation − » : une fois (F1). « Saisir Mise Bas » : F2.
          // « Clôturer (Sevrage) » : F3. F4 (clos) et F5 (échec) : aucun bouton.
          for (final a in actions) {
            expect(find.text(a), findsOneWidget, reason: a);
          }
        },
        skip: _sansBlade,
      );
    }
  });

  // ── Actions de cycle : le dépôt sait écrire, le serveur n'accepte pas ─────

  group('actions de cycle — dépôt', () {
    final saisie = DateTime(2026, 10, 19, 14, 30);

    SuiviReproductionRepository ouvert() => SuiviReproductionRepository(
      database: db,
      deviceId: 'poste-test',
      miseAJourCycleAccepteeParServeur: true,
    );

    test('les messages des toasts sont ceux du composant Livewire', () {
      expect(blade.messages, [
        SuiviReproductionRepository.messageSaillie,
        SuiviReproductionRepository.messagePalpation,
        SuiviReproductionRepository.messageMiseBas,
        SuiviReproductionRepository.messageCloture,
      ]);
    }, skip: _sansBlade);

    test('une palpation positive écrit la date du jour, en_cours, pending', () async {
      final id = await cycle('p', bandeLapins, 'R1');

      await ouvert().enregistrerPalpation(id, positive: true, maintenant: saisie);

      final e = await ligne(id);
      expect(e.palpationDate, DateTime(2026, 10, 19));
      expect(e.status, 'en_cours');
      expect(e.syncStatus, SyncStatus.pending);
      // ⚠️ L'instant de la SAISIE, jamais celui de l'envoi.
      expect(e.updatedAt, saisie);
    });

    test('une palpation négative passe le cycle en échec', () async {
      final id = await cycle('n', bandeLapins, 'R1');

      await ouvert().enregistrerPalpation(id, positive: false, maintenant: saisie);

      final e = await ligne(id);
      expect(e.palpationDate, DateTime(2026, 10, 19));
      expect(e.status, 'echec');
      expect(e.syncStatus, SyncStatus.pending);
    });

    test('une mise bas écrit la date du jour, les vivants et les morts', () async {
      final id = await cycle('m', bandeLapins, 'R1', palpationIlYA: 10);

      await ouvert().enregistrerMiseBas(
        id,
        nesVivants: 7,
        nesMorts: 1,
        maintenant: saisie,
      );

      final e = await ligne(id);
      expect(e.miseBasDateActual, DateTime(2026, 10, 19));
      expect(e.nesVivants, 7);
      expect(e.nesMorts, 1);
      expect(e.status, 'en_cours');
      expect(e.syncStatus, SyncStatus.pending);
      expect(e.updatedAt, saisie);
    });

    test('une mise bas négative est refusée, comme `min:0`', () async {
      final id = await cycle('m', bandeLapins, 'R1', palpationIlYA: 10);

      expect(
        () => ouvert().enregistrerMiseBas(id, nesVivants: -1, nesMorts: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect((await ligne(id)).syncStatus, SyncStatus.synced);
    });

    test('une clôture passe le cycle à termine, pending', () async {
      final id = await cycle(
        'c',
        bandeLapins,
        'R1',
        palpationIlYA: 20,
        miseBasIlYA: 3,
        nesVivants: 6,
        nesMorts: 0,
      );

      await ouvert().cloturerCycle(id, maintenant: saisie);

      final e = await ligne(id);
      expect(e.status, 'termine');
      expect(e.syncStatus, SyncStatus.pending);
      expect(e.updatedAt, saisie);
    });

    /// ⚠️⚠️ Verrou de sécurité, OUVERT par défaut depuis que le serveur applique les étapes (ticket H7) : fermé, rien
    /// n'est écrit.
    test('⚠️⚠️ verrou fermé : rien n est écrit, et la raison est donnée', () async {
      final id = await cycle('v', bandeLapins, 'R1');
      depot = SuiviReproductionRepository(database: db, deviceId: 'poste-test', miseAJourCycleAccepteeParServeur: false);

      for (final action in <Future<void> Function()>[
        () => depot.enregistrerPalpation(id, positive: true),
        () => depot.enregistrerMiseBas(id, nesVivants: 5, nesMorts: 0),
        () => depot.cloturerCycle(id),
      ]) {
        await expectLater(action(), throwsA(isA<ActionCycleIndisponible>()));
      }

      final e = await ligne(id);
      expect(e.palpationDate, isNull);
      expect(e.status, 'en_cours');
      expect(e.syncStatus, SyncStatus.synced);
      expect(depot.miseAJourCycleAccepteeParServeur, isFalse);
      expect(
        SuiviReproductionRepository.motifActionsCycleFermees,
        contains('création'),
      );
    });

    test('bandes proposées : status actif ET is_active, comme le Blade', () async {
      final bandes = await depot.bandesDeclarables('cuniculture');
      expect(bandes.map((b) => b.code), ['LOT-LAP-2026-06']);
    });
  });

  group('actions de cycle — écran', () {
    testWidgets('⚠️⚠️ verrou fermé : boutons grisés, toast d avertissement, rien écrit', (
      tester,
    ) async {
      final id = await cycle('f', bandeLapins, 'R1', saillieIlYA: 5);
      depot = SuiviReproductionRepository(database: db, deviceId: 'poste-test', miseAJourCycleAccepteeParServeur: false);

      await afficher(tester);

      final plus = find.byKey(Key('action-plus-$id'));
      expect(plus, findsOneWidget);
      await tester.tap(plus);
      await tester.pump();

      expect(find.byKey(const Key('toast-avertissement')), findsOneWidget);
      expect(find.byKey(const Key('toast-succes')), findsNothing);
      expect((await ligne(id)).palpationDate, isNull);
      expect(find.byKey(const Key('mention-lecture-seule')), findsOneWidget);
      ToastAgri.toutRetirer();
    });

    testWidgets('verrou ouvert : « Palpation + » écrit et affiche le message du web', (
      tester,
    ) async {
      final id = await cycle('o', bandeLapins, 'R1', saillieIlYA: 15);

      await afficher(
        tester,
        avec: SuiviReproductionRepository(
          database: db,
          miseAJourCycleAccepteeParServeur: true,
        ),
      );
      await tester.tap(find.byKey(Key('action-plus-$id')));
      await tester.pumpAndSettle();

      final e = await ligne(id);
      expect(e.palpationDate, aujourdhui);
      expect(e.syncStatus, SyncStatus.pending);
      expect(find.text(SuiviReproductionRepository.messagePalpation), findsOneWidget);
      expect(find.byKey(const Key('toast-succes')), findsOneWidget);
      // La ligne est relue : la palpation s'affiche comme au web.
      expect(find.text('${jj(aujourdhui)} (Positif)'), findsOneWidget);
      ToastAgri.toutRetirer();
    });

    testWidgets('verrou ouvert : la modale « Saisir la Mise Bas » du Blade', (
      tester,
    ) async {
      final id = await cycle('mb', bandeLapins, 'R1', saillieIlYA: 30, palpationIlYA: 16);

      await afficher(
        tester,
        avec: SuiviReproductionRepository(
          database: db,
          miseAJourCycleAccepteeParServeur: true,
        ),
      );
      await tester.tap(find.byKey(Key('action-mise-bas-$id')));
      await tester.pumpAndSettle();

      expect(find.text(blade.titresModales(true)[1]), findsOneWidget);
      // Étiquettes de la modale de mise bas : les deux dernières du Blade.
      for (final e in blade.etiquettes(true).skip(4)) {
        expect(find.text(e.toUpperCase()), findsOneWidget, reason: e);
      }
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text(blade.boutonsValider[1]), findsOneWidget);

      await tester.enterText(find.byKey(const Key('mise-bas-vivants')), '7');
      await tester.enterText(find.byKey(const Key('mise-bas-morts')), '1');
      await tester.tap(find.byKey(const Key('mise-bas-enregistrer')));
      await tester.pumpAndSettle();

      final e = await ligne(id);
      expect(e.nesVivants, 7);
      expect(e.nesMorts, 1);
      expect(e.miseBasDateActual, aujourdhui);
      expect(find.text(SuiviReproductionRepository.messageMiseBas), findsOneWidget);
      expect(find.text('7 (1 morts)'), findsOneWidget);
      ToastAgri.toutRetirer();
    }, skip: _sansBlade);

    testWidgets('verrou ouvert : « Clôturer (Sevrage) » clôt le cycle', (
      tester,
    ) async {
      final id = await cycle(
        'cl',
        bandeLapins,
        'R1',
        saillieIlYA: 40,
        palpationIlYA: 20,
        miseBasIlYA: 5,
        nesVivants: 6,
        nesMorts: 0,
      );

      await afficher(
        tester,
        avec: SuiviReproductionRepository(
          database: db,
          miseAJourCycleAccepteeParServeur: true,
        ),
      );
      await tester.tap(find.byKey(Key('action-cloturer-$id')));
      await tester.pumpAndSettle();

      expect((await ligne(id)).status, 'termine');
      expect(find.text(SuiviReproductionRepository.messageCloture), findsOneWidget);
      ToastAgri.toutRetirer();
    });
  });

  // ── Modale de saillie ─────────────────────────────────────────────────────

  group('modale de saillie', () {
    Future<void> ouvrirModale(WidgetTester tester, {bool lapins = true}) async {
      await afficher(tester);
      if (!lapins) await ouvrir(tester, 'Porcs');
      await tester.tap(
        find.byKey(Key('declarer-saillie-${lapins ? 'lapins' : 'porcs'}')),
      );
      await tester.pumpAndSettle();
    }

    for (final lapins in [true, false]) {
      testWidgets(
        '${lapins ? 'lapins' : 'porcs'} : titre, étiquettes, exemples et option vide du Blade',
        (tester) async {
          await ouvrirModale(tester, lapins: lapins);

          // ⚠️ Dans la modale seulement : « VERRAT N° » est aussi l'en-tête du tableau derrière.
          expect(dansModale(blade.titresModales(lapins)[0]), findsOneWidget);
          for (final e in blade.etiquettes(lapins).take(4)) {
            expect(dansModale(e.toUpperCase()), findsOneWidget, reason: e);
          }
          for (final ex in blade.exemples(lapins)) {
            expect(dansModale(ex), findsOneWidget, reason: ex);
          }
          expect(dansModale(blade.optionVide), findsOneWidget);
          expect(dansModale(blade.boutonsValider[0]), findsOneWidget);
        },
        skip: _sansBlade,
      );
    }

    testWidgets('la liste ne propose que les bandes actives', (tester) async {
      await ouvrirModale(tester);
      await tester.tap(find.byKey(const Key('saillie-bande')));
      await tester.pumpAndSettle();

      expect(find.text('LOT-LAP-2026-06'), findsWidgets);
      expect(find.text('LOT-LAP-VENDU'), findsNothing);
      expect(find.text('LOT-LAP-ARCHIVE'), findsNothing);
    });

    testWidgets('sans bande choisie, rien n est écrit', (tester) async {
      await ouvrirModale(tester);
      await tester.enterText(find.byKey(const Key('saillie-femelle')), 'R8');
      await tester.tap(find.byKey(const Key('saillie-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('saillie-erreur')), findsOneWidget);
      expect(await db.select(db.livestockReproductionEvents).get(), isEmpty);
    });

    /// ⚠️⚠️ `'sireRef' => ['nullable', …]` : une saillie par insémination n'a pas de mâle.
    /// MUTATION : rendre le mâle obligatoire dans l'écran fait rougir ce test.
    testWidgets('⚠️⚠️ le n° du mâle est FACULTATIF, comme au web', (tester) async {
      await ouvrirModale(tester);

      await tester.tap(find.byKey(const Key('saillie-bande')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LOT-LAP-2026-06').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('saillie-femelle')), 'R8');
      await tester.tap(find.byKey(const Key('saillie-enregistrer')));
      await tester.pumpAndSettle();

      final ecrits = await db.select(db.livestockReproductionEvents).get();
      expect(ecrits, hasLength(1));
      expect(ecrits.single.motherRef, 'R8');
      expect(ecrits.single.sireRef, isNull);
      expect(ecrits.single.syncStatus, SyncStatus.pending);
      expect(find.text(SuiviReproductionRepository.messageSaillie), findsOneWidget);
      ToastAgri.toutRetirer();
    });
  });

  // ── Câblage du socle (`main.dart`) ────────────────────────────────────────

  /// `route('elevage.fiche-reproducteurs')` / `route('elevage.fiche-escargots')` du Blade : le
  /// lien du couvoir ouvre la fiche de saisie de l'espèce, dans le socle réel du poste.
  for (final (onglet, ecran) in [
    ('Volailles', FicheReproducteursScreen),
    ('Escargots', FicheEscargotsScreen),
  ]) {
    testWidgets('socle : « Saisir le Couvoir du Jour → » ($onglet) ouvre $ecran', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(theme: AgriTheme.light, home: coqueDeTest(db)),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('barre-laterale')),
          matching: find.text('Suivi Reproduction'),
        ),
      );
      await tester.pumpAndSettle();
      await ouvrir(tester, onglet);
      await tester.tap(find.byKey(const Key('lien-couvoir')));
      await tester.pumpAndSettle();

      expect(find.byType(SuiviReproductionScreen), findsNothing);
      expect(find.byType(ecran), findsOneWidget);
    });
  }
}
