import 'dart:io';
import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/features/elevage/dashboard_elevage_repository.dart';
import 'package:agrierp/features/elevage/dashboard_elevage_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket H6 — DASHBOARD ÉLEVAGE DU POSTE ALIGNÉ SUR LE BLADE (le Blade fait foi, Doctrine art. 5).
///
/// Trois familles de contrôles :
///  1. les libellés, colonnes et textes vides sont LUS DANS LE BLADE (`dashboard-elevage.blade.php`,
///     `bilan-technico-economique.blade.php`) puis cherchés dans l'écran rendu — jamais recopiés ici ;
///  2. le GMQ CUMULÉ et la mortalité sur 7 jours sur un jeu fait à la main, valeurs attendues
///     calculées à la main en commentaire ;
///  3. la PARITÉ EXÉCUTÉE : le vrai composant `Livewire\Elevage\DashboardElevage` et le vrai
///     `GrowthAnalysisService::gmqCumule` calculent sur le même jeu que le repository du poste.
///
/// Décision client du 19/10/2026 : les AJOUTS du poste (courbes, cartes et filtre GMQ, sélecteur et
/// horizons de prévision, liste des rappels VMS…) restent ; ce fichier ne vérifie que la présence
/// et l'exactitude de ce que le web affiche.
void main() {
  final cheminBlade =
      '$dossierLaravel/resources/views/livewire/elevage/dashboard-elevage.blade.php';
  final cheminBladeBilan =
      '$dossierLaravel/resources/views/livewire/elevage/bilan-technico-economique.blade.php';
  final sautBlade = File(cheminBlade).existsSync()
      ? null
      : 'SAUT : vue Blade introuvable ($cheminBlade) — comparaison au maître impossible';

  String blade() => File(cheminBlade).readAsStringSync();

  /// Décode les entités HTML du Blade (`&amp;` → `&`).
  String texte(String brut) => brut
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Le panneau d'un onglet : du `@if($tab === 'cle')` au suivant.
  String panneau(String source, String cle) {
    final debut = source.indexOf("@if(\$tab === '$cle')");
    expect(debut, greaterThanOrEqualTo(0), reason: 'onglet $cle absent du Blade');
    final suite = source.indexOf("@if(\$tab === '", debut + 10);
    return source.substring(debut, suite < 0 ? source.length : suite);
  }

  List<String> entetes(String bloc) => [
    for (final m in RegExp(r'<th[^>]*>([^<]+)</th>').allMatches(bloc))
      texte(m.group(1)!),
  ];

  List<String> libellesKpi(String bloc) => [
    for (final m in RegExp(r'<x-kpi-card label="([^"]+)"').allMatches(bloc))
      texte(m.group(1)!),
  ];

  /// Paragraphes et liens au texte FIXE (sans expression Blade).
  List<String> textesFixes(String bloc, String balise) => [
    for (final m in RegExp(
      '<$balise[^>]*>([^<{@]+)</$balise>',
    ).allMatches(bloc))
      texte(m.group(1)!),
  ];

  String titreH2(String bloc) => texte(
    RegExp(r'<h2[^>]*>.*?</span>([^<]+)</h2>').firstMatch(bloc)!.group(1)!,
  );

  // ── Jeu d'essai du poste ─────────────────────────────────────────────────

  late AppDatabase db;
  late DashboardElevageRepository depot;

  /// Instant de référence : lundi 19/10/2026, 10 h 15 (l'heure compte pour la fenêtre de 7 jours).
  final maintenant = DateTime(2026, 10, 19, 10, 15);

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = DashboardElevageRepository(
      database: db,
      soins: SoinsRepository(database: db, deviceId: 'poste-test'),
    );
  });

  tearDown(() async => db.close());

  Future<String> bande(
    String code,
    String espece, {
    String? statut = 'actif',
    bool active = true,
    int initial = 100,
    int courant = 100,
    double? acquisition,
  }) async {
    final id = uuid('${code.toLowerCase()}-lot');
    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: id,
            code: code,
            speciesId: uuid('esp-$espece'),
            speciesCode: Value(espece),
            stage: const Value('engraissement'),
            initialQuantity: Value(initial),
            currentQuantity: Value(courant),
            status: Value(statut),
            isActive: Value(active),
            acquisitionCost: Value(acquisition),
          ),
        );
    return id;
  }

  Future<void> fiche(
    String lot,
    DateTime jour, {
    double? poids,
    int mort = 0,
    int effectif = 100,
  }) => db
      .into(db.livestockDailyEntries)
      .insert(
        LivestockDailyEntriesCompanion.insert(
          id: uuid('${jour.month}-${jour.day}-$lot'),
          deviceId: 'poste-test',
          updatedAt: maintenant,
          lotId: lot,
          entryDate: jour,
          mort: Value(mort),
          effectifFinal: Value(effectif),
          weightSampleAvgG: Value(poids),
        ),
      );

  Future<void> soin(String graine, String lot, String type, double cout) => db
      .into(db.veterinaryRecords)
      .insert(
        VeterinaryRecordsCompanion.insert(
          id: uuid(graine),
          deviceId: 'poste-test',
          updatedAt: maintenant,
          lotId: lot,
          actionType: type,
          cost: Value(cout),
          recordDate: DateTime(2026, 10, 12),
        ),
      );

  Future<void> afficher(
    WidgetTester tester, {
    VoidCallback? onOuvrirSoins,
  }) async {
    tester.view.physicalSize = const Size(1600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardElevageScreen(
          depot: depot,
          quand: maintenant,
          onOuvrirSoins: onOuvrirSoins,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Titre `<h2>` du panneau ouvert (il répète parfois le libellé de l'onglet : lu par sa clé).
  String titreAffiche(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const Key('titre-panneau')),
          matching: find.byType(Text),
        ),
      )
      .data!;

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-$onglet')));
    await tester.pumpAndSettle();
  }

  // ═══ 1. Libellés, colonnes et textes LUS DANS LE BLADE ═══════════════════

  group('lus dans le Blade', () {
    testWidgets('les cinq onglets : libellés, ordre et icônes du Blade', (
      tester,
    ) async {
      final onglets = RegExp(
        r"\['key' => '(\w+)', 'label' => '([^']+)', 'icon' => '(\w+)'\]",
      ).allMatches(blade()).toList();
      expect(onglets, hasLength(5));

      // Correspondance Material Symbols → Icons. ⚠️ `monitoring` n'existe pas dans `Icons` :
      // `ssid_chart` (axes et ligne brisée) est le glyphe le plus proche.
      const icones = {
        'dashboard': Icons.dashboard,
        'monitoring': Icons.ssid_chart,
        'account_balance_wallet': Icons.account_balance_wallet,
        'coronavirus': Icons.coronavirus,
        'query_stats': Icons.query_stats,
      };

      await afficher(tester);

      for (final o in onglets) {
        final libelle = o.group(2)!;
        expect(
          find.descendant(
            of: find.byKey(Key('onglet-$libelle')),
            matching: find.byIcon(icones[o.group(3)]!),
          ),
          findsOneWidget,
          reason: '$libelle : icône ${o.group(3)}',
        );
      }
      expect(
        [for (final o in onglets) o.group(2)],
        [for (final (l, _) in DashboardElevageScreen.onglets) l],
      );
    }, skip: sautBlade != null);

    testWidgets(
      'Synthèse : KPI, lignes de carte, résumé GMQ et rappels VMS du Blade',
      (tester) async {
        final synthese = panneau(blade(), 'synthese');

        await afficher(tester);

        for (final libelle in libellesKpi(synthese)) {
          expect(
            find.text(libelle.toUpperCase()),
            findsOneWidget,
            reason: 'KPI « $libelle »',
          );
        }
        for (final legende in [
          for (final m in RegExp(
            r' caption="([^"]+)"',
          ).allMatches(synthese))
            texte(m.group(1)!),
        ]) {
          expect(find.text(legende), findsOneWidget, reason: legende);
        }

        // Lignes des cartes de filière (`<span class="text-outline">…</span>`).
        final lignes = [
          for (final m in RegExp(
            r'<span class="text-outline">([^<]+)</span>',
          ).allMatches(synthese))
            texte(m.group(1)!),
        ];
        expect(lignes, [
          'Effectif vivant',
          'Taux mortalité (mois)',
          'Autonomie aliment',
        ]);
        for (final l in lignes) {
          expect(find.text(l), findsWidgets, reason: l);
        }

        for (final titre in [
          for (final m in RegExp(
            r'<h3[^>]*>([^<{]+)</h3>',
          ).allMatches(synthese))
            texte(m.group(1)!),
        ]) {
          expect(find.text(titre), findsOneWidget, reason: titre);
        }

        // Texte du résumé, message vide (aucune bande pesée), texte et lien des rappels.
        final paragraphes = textesFixes(synthese, 'p');
        expect(paragraphes, hasLength(3));
        for (final p in paragraphes) {
          expect(find.text(p), findsOneWidget, reason: p);
        }
        final liens = textesFixes(synthese, 'a');
        expect(liens, ['Voir le calendrier complet →']);
        expect(find.text(liens.single), findsOneWidget);
      },
      skip: sautBlade != null,
    );

    testWidgets('GMQ & Croissance : titre, aide et six colonnes du Blade', (
      tester,
    ) async {
      final gmq = panneau(blade(), 'gmq');
      final colonnes = entetes(gmq);
      expect(colonnes, hasLength(6));

      final pour = await bande('CUN-1', 'cuniculture');
      await fiche(pour, DateTime(2026, 10, 19), poids: 900);

      await afficher(tester);
      await ouvrir(tester, 'GMQ & Croissance');

      expect(titreAffiche(tester), titreH2(gmq));
      expect(find.text(textesFixes(gmq, 'p').single), findsOneWidget);

      // ⚠️ L'ORDRE compte : les en-têtes rendus, de gauche à droite.
      final positions = [
        for (final c in colonnes)
          tester.getTopLeft(find.text(c.toUpperCase())).dx,
      ];
      expect(positions, [...positions]..sort(), reason: colonnes.join(' · '));

      // La source déclare la même suite, dans le même ordre.
      expect(
        DashboardElevageScreen.colonnesGmq.map((c) => c.$1).toList(),
        colonnes,
      );

      // Une seule pesée : « Pesées insuffisantes », jours « — ».
      expect(
        RegExp(r"'(Pesées insuffisantes)'").hasMatch(gmq),
        isTrue,
        reason: 'littéral du Blade',
      );
      expect(find.text('Pesées insuffisantes'), findsOneWidget);
    }, skip: sautBlade != null);

    testWidgets('GMQ & Croissance : message du Blade sans bande active', (
      tester,
    ) async {
      final vide = textesFixes(panneau(blade(), 'gmq'), 'td').single;
      await afficher(tester);
      await ouvrir(tester, 'GMQ & Croissance');
      expect(find.text(vide), findsOneWidget);
    }, skip: sautBlade != null);

    testWidgets('Analyse Sanitaire : titre, KPI et colonnes du Blade', (
      tester,
    ) async {
      final sanitaire = panneau(blade(), 'sanitaire');
      await afficher(tester);
      await ouvrir(tester, 'Analyse Sanitaire');

      expect(titreAffiche(tester), titreH2(sanitaire));
      for (final l in libellesKpi(sanitaire)) {
        expect(find.text(l.toUpperCase()), findsOneWidget, reason: l);
      }
      for (final c in entetes(sanitaire)) {
        expect(find.text(c.toUpperCase()), findsOneWidget, reason: c);
      }
      expect(
        DashboardElevageScreen.colonnesSanitaire.map((c) => c.$1).toList(),
        entetes(sanitaire),
      );
    }, skip: sautBlade != null);

    testWidgets(
      'Prévision : titre, méthode, colonnes et ligne « historique insuffisant »',
      (tester) async {
        final prevision = panneau(blade(), 'prevision');
        final colonnes = entetes(prevision);
        expect(colonnes, hasLength(4));

        final lot = await bande('CUN-1', 'cuniculture');
        await fiche(lot, DateTime(2026, 10, 12), poids: 800);
        await fiche(lot, DateTime(2026, 10, 19), poids: 900);

        await afficher(tester);
        await ouvrir(tester, 'Prévision de Croissance');

        expect(titreAffiche(tester), titreH2(prevision));
        expect(find.text(textesFixes(prevision, 'p').single), findsOneWidget);

        final positions = [
          for (final c in colonnes)
            tester.getTopLeft(find.text(c.toUpperCase())).dx,
        ];
        expect(positions, [...positions]..sort());
        expect(
          DashboardElevageScreen.colonnesPrevision
              .map((c) => c.$1)
              .toList(),
          colonnes,
        );

        // Deux pesées : la ligne du Blade (colspan=3).
        final insuffisant = textesFixes(prevision, 'td').first;
        expect(
          insuffisant,
          'Historique insuffisant (3 pesées minimum requises)',
        );
        expect(find.text(insuffisant), findsOneWidget);
      },
      skip: sautBlade != null,
    );

    testWidgets(
      'Rentabilité : « En attente » pour l acquisition absente, légende du coût de revient',
      (tester) async {
        final bilan = File(cheminBladeBilan).readAsStringSync();
        expect(bilan.contains("?? 'En attente'"), isTrue);
        final legende = RegExp(
          r'Coût de Revient / Sujet</span>.*?<p[^>]*>([^<]+)</p>',
          dotAll: true,
        ).firstMatch(bilan)!.group(1)!;

        // Effectif initial 0 : la valeur est « — », la légende reste celle du Blade.
        await bande('CUN-1', 'cuniculture', initial: 0, acquisition: null);

        await afficher(tester);
        await ouvrir(tester, 'Rentabilité');

        expect(find.text('En attente'), findsOneWidget);
        expect(find.text(texte(legende)), findsOneWidget);
      },
      skip: sautBlade != null,
    );
  });

  // ═══ 2. Calculs sur un jeu fait à la main ════════════════════════════════

  group('GMQ cumulé (première → dernière pesée)', () {
    test('formule pure : null sans deux pesées ou sur 0 jour, arrondi PHP', () {
      expect(DashboardElevageRepository.gmqCumule(const []), isNull);
      expect(
        DashboardElevageRepository.gmqCumule([(DateTime(2026, 10, 1), 500)]),
        isNull,
      );
      // Deux pesées le même jour : aucun gain QUOTIDIEN.
      expect(
        DashboardElevageRepository.gmqCumule([
          (DateTime(2026, 10, 5), 500),
          (DateTime(2026, 10, 5), 600),
        ]),
        isNull,
      );
      // (900 − 500) ÷ 14 = 28,571… → 28,6. Les deux dernières auraient donné (900 − 800) ÷ 7 = 14,3.
      expect(
        DashboardElevageRepository.gmqCumule([
          (DateTime(2026, 10, 5), 500),
          (DateTime(2026, 10, 12), 800),
          (DateTime(2026, 10, 19), 900),
        ]),
        28.6,
      );
      // 29 ÷ 20 = 1,45 : PHP 8.3 arrondit à 1,5 (pré-arrondi), un arrondi naïf du double donne 1,4.
      expect(
        DashboardElevageRepository.gmqCumule([
          (DateTime(2026, 9, 29), 1000),
          (DateTime(2026, 10, 19), 1029),
        ]),
        1.5,
      );
      expect(DashboardElevageRepository.arrondiPhp(1.45, 1), 1.5);
      expect(DashboardElevageRepository.arrondiPhp(-1.45, 1), -1.5);
      expect(DashboardElevageRepository.arrondiPhp(2.5), 3);
    });

    test('pesée à 0 retenue comme le `whereNotNull` du serveur', () async {
      final lot = await bande('POR-1', 'porciculture');
      await fiche(lot, DateTime(2026, 9, 29), poids: 0);
      await fiche(lot, DateTime(2026, 10, 10)); // pas de pesée (null) : ignorée
      await fiche(lot, DateTime(2026, 10, 19), poids: 700);

      final d = await depot.charger(quand: maintenant);
      final l = d.lignesGmq.single;
      // (700 − 0) ÷ 20 = 35,0.
      expect(l.poidsInitial, 0);
      expect(l.poidsActuel, 700);
      expect(l.jours, 20);
      expect(l.gmq, 35.0);
    });

    testWidgets(
      'KPI GMQ Moyen, résumé et tableau sur le GMQ cumulé ; bandes clôturées exclues',
      (tester) async {
        final cun = await bande('CUN-1', 'cuniculture', courant: 65);
        final por = await bande('POR-1', 'porciculture', courant: 54);
        final avi = await bande('AVI-1', 'aviculture', courant: 1310);
        final lap = await bande('CUN-2', 'cuniculture', courant: 40);
        final hel = await bande(
          'HEL-1',
          'helico',
          statut: 'cloture',
          courant: 1250,
        );

        // CUN-1 : (900 − 500) ÷ 14 = 28,6.
        await fiche(cun, DateTime(2026, 10, 5), poids: 500);
        await fiche(cun, DateTime(2026, 10, 12), poids: 800);
        await fiche(cun, DateTime(2026, 10, 19), poids: 900);
        // POR-1 : (700 − 0) ÷ 20 = 35,0 → « 35 g/j » (affichage d'un flottant PHP).
        await fiche(por, DateTime(2026, 9, 29), poids: 0);
        await fiche(por, DateTime(2026, 10, 19), poids: 700);
        // AVI-1 : 29 ÷ 20 = 1,45 → 1,5.
        await fiche(avi, DateTime(2026, 9, 29), poids: 1000);
        await fiche(avi, DateTime(2026, 10, 19), poids: 1029);
        // CUN-2 : une seule pesée → « Pesées insuffisantes ».
        await fiche(lap, DateTime(2026, 10, 19), poids: 300);
        // HEL-1 clôturée : hors périmètre, même avec deux pesées.
        await fiche(hel, DateTime(2026, 10, 5), poids: 10);
        await fiche(hel, DateTime(2026, 10, 19), poids: 40);

        await afficher(tester);

        // Effectif : 65 + 54 + 1310 + 40 = 1 469 (la clôturée n'entre pas).
        expect(find.text('1 469'), findsOneWidget);
        // GMQ Moyen : moyenne des GMQ ARRONDIS (28,6 + 35,0 + 1,5) ÷ 3 = 21,7.
        expect(find.text('21.7 g/j'), findsOneWidget);

        // Résumé : une ligne par bande dont le GMQ existe.
        expect(find.text('28.6 g/j'), findsOneWidget);
        expect(find.text('35 g/j'), findsOneWidget);
        expect(find.text('1.5 g/j'), findsOneWidget);
        expect(find.text('HEL-1'), findsNothing);

        await ouvrir(tester, 'GMQ & Croissance');

        Finder ligne(String code) => find.byKey(Key('ligne-gmq-$code'));
        List<String> cellules(String code) => [
          for (final t in tester.widgetList<Text>(
            find.descendant(of: ligne(code), matching: find.byType(Text)),
          ))
            t.data!,
        ];

        expect(cellules('CUN-1'), [
          'CUN-1',
          'Cuniculture',
          '500',
          '900',
          '14',
          '28.6 g/j',
        ]);
        expect(cellules('POR-1'), [
          'POR-1',
          'Porciculture',
          '0',
          '700',
          '20',
          '35 g/j',
        ]);
        expect(cellules('CUN-2'), [
          'CUN-2',
          'Cuniculture',
          '300',
          '300',
          '—',
          'Pesées insuffisantes',
        ]);
        expect(ligne('HEL-1'), findsNothing);
      },
    );
  });

  group('mortalité', () {
    /// Bande A (cuniculture, effectif initial 100) — fiches :
    ///   11/10 : 2 morts, effectif final 98   (hors fenêtre 7 j)
    ///   13/10 : 3 morts, effectif final 95   (J-6 : HORS fenêtre à 10 h 15, voir plus bas)
    ///   14/10 : 1 mort,  effectif final 94
    ///   19/10 : 2 morts, effectif final 92
    /// ⚠️ `whereBetween('entry_date', [now()->subDays(6), now()])` compare une DATE (minuit) au
    /// 13/10 10 h 15 : le 13/10 est exclu (vérifié en PHP réel). Fenêtre : 14/10 et 19/10.
    ///   morts = 1 + 2 = 3 ; départ = previousEffectif(14/10) 95 + previousEffectif(19/10) 94 = 189
    ///   3 ÷ 189 = 1,587 % → « 1,6 % ».
    /// Mois d'octobre : départs 100 (initial) + 98 + 95 + 94 = 387, morts 8 → 2,067 % → « 2,1 % ».
    Future<void> jeu() async {
      final a = await bande('CUN-1', 'cuniculture', courant: 92);
      await fiche(a, DateTime(2026, 10, 11), mort: 2, effectif: 98);
      await fiche(a, DateTime(2026, 10, 13), mort: 3, effectif: 95);
      await fiche(a, DateTime(2026, 10, 14), mort: 1, effectif: 94);
      await fiche(a, DateTime(2026, 10, 19), mort: 2, effectif: 92);
      // Bande clôturée : 50 morts dans la fenêtre, ignorés.
      final b = await bande('CUN-9', 'cuniculture', statut: 'cloture');
      await fiche(b, DateTime(2026, 10, 18), mort: 50, effectif: 0);
      // Porcs : 2 ÷ 20 = 10,0 % sur le mois → critique (> 5).
      final p = await bande('POR-1', 'porciculture', initial: 20, courant: 18);
      await fiche(p, DateTime(2026, 10, 10), mort: 2, effectif: 18);
      // Volailles : 5 ÷ 100 = 5,0 % → PAS critique (seuil strict > 5).
      final v = await bande('AVI-1', 'aviculture', courant: 95);
      await fiche(v, DateTime(2026, 10, 10), mort: 5, effectif: 95);
    }

    test('KPI 7 jours et cartes du mois : previousEffectif, 1 décimale', () async {
      await jeu();
      final d = await depot.charger(quand: maintenant);

      expect(d.mortalite7j, 1.6);
      final cartes = {for (final c in d.especes) c.code: c};
      expect(cartes['cuniculture']!.lignes[1], ('Taux mortalité (mois)', '2,1 %', false));
      expect(cartes['porciculture']!.lignes[1], ('Taux mortalité (mois)', '10,0 %', true));
      expect(cartes['aviculture']!.lignes[1], ('Taux mortalité (mois)', '5,0 %', false));
    });

    testWidgets('KPI « Mortalité Cumulée (7j) » au format du Blade', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);

      expect(find.text('MORTALITÉ CUMULÉE (7J)'), findsOneWidget);
      expect(find.text('1,6 %'), findsOneWidget);
      expect(find.text('2,1 %'), findsOneWidget);
      final critique = tester.widget<Text>(find.text('10,0 %'));
      expect(critique.style!.color, AgriColors.errorDeep);
      final limite = tester.widget<Text>(find.text('5,0 %'));
      expect(limite.style!.color, isNot(AgriColors.errorDeep));
    });

    test('sans fiche : « 0,0 % » comme le web (dénominateur nul)', () async {
      await bande('CUN-1', 'cuniculture');
      final d = await depot.charger(quand: maintenant);
      expect(d.mortalite7j, 0.0);
      expect(DashboardElevageRepository.pourcent(d.mortalite7j), '0,0 %');
    });
  });

  group('périmètre et espèces', () {
    test('espèces activées : table des espèces ∩ modules actifs', () async {
      for (final (code, libelle) in [
        ('cuniculture', 'Cuniculture (Lapins)'),
        ('aviculture', 'Aviculture (Volailles)'),
        ('porciculture', 'Porciculture (Porcs)'),
      ]) {
        await db
            .into(db.livestockSpecies)
            .insert(
              LivestockSpeciesCompanion.insert(
                id: uuid('esp-$code'),
                code: code,
                label: libelle,
              ),
            );
      }
      for (final (code, actif) in [
        ('cuniculture', true),
        ('aviculture', true),
        ('porciculture', false),
        ('helico', false),
      ]) {
        await db
            .into(db.modulesConfig)
            .insert(
              ModulesConfigCompanion.insert(
                id: uuid('mod-$code'),
                speciesCode: code,
                isEnabled: Value(actif),
              ),
            );
      }

      final d = await depot.charger(quand: maintenant);
      expect([for (final c in d.especes) c.titre], [
        'Cuniculture (Lapins)',
        'Aviculture (Volailles)',
      ]);
      expect([for (final s in d.sanitaire) s.libelleEspece], [
        'Cuniculture (Lapins)',
        'Aviculture (Volailles)',
      ]);
    });

    testWidgets('Analyse sanitaire : KPI sur les bandes actives, tableau sur les bandes non archivées', (
      tester,
    ) async {
      final a = await bande('CUN-1', 'cuniculture');
      final c = await bande('CUN-2', 'cuniculture', statut: 'cloture');
      await soin('s1-soin', a, 'Vaccination', 12000);
      await soin('s2-soin', c, 'Vaccination', 3500);
      await soin('s3-soin', c, 'Déparasitage', 500);

      final d = await depot.charger(quand: maintenant);
      // KPI : la seule bande ACTIVE (status actif) → 1 soin, 12 000 FCFA.
      expect(d.traitementsDuMois, 1);
      expect(d.coutSanitaireDuMois, 12000);
      // Tableau : les bandes NON ARCHIVÉES de l'espèce, clôturée comprise → 3 soins, 16 000.
      final cun = d.sanitaire.firstWhere((s) => s.code == 'cuniculture');
      expect(cun.nombreDeTraitements, 3);
      expect(cun.coutTotal, 16000);

      await afficher(tester);
      await ouvrir(tester, 'Analyse Sanitaire');
      expect(find.text('12 000 FCFA'), findsOneWidget);
      expect(find.text('16 000 FCFA'), findsOneWidget);
      expect(find.text('Vaccination'), findsOneWidget);
    });
  });

  testWidgets('« Voir le calendrier complet → » ouvre Soins et vaccins', (
    tester,
  ) async {
    var ouvert = 0;
    await afficher(tester, onOuvrirSoins: () => ouvert++);

    await tester.tap(find.text('Voir le calendrier complet →'));
    await tester.pumpAndSettle();
    expect(ouvert, 1);
  });

  testWidgets('Prévision : tableau du Blade, régression sur toutes les pesées', (
    tester,
  ) async {
    // Pesées 05/10 = 800, 12/10 = 900, 19/10 = 1100 : x = 0, 7, 14.
    // pente = (3×21700 − 21×2800) ÷ (3×245 − 21²) = 6300 ÷ 294 = 21,4286 → « 21.4 g/j » ;
    // ordonnée = (2800 − 21,4286×21) ÷ 3 = 783,33 ; projection = 783,33 + 21,4286 × (14 + 30)
    // = 1726,19 → 1726.
    final lot = await bande('CUN-1', 'cuniculture');
    await fiche(lot, DateTime(2026, 10, 5), poids: 800);
    await fiche(lot, DateTime(2026, 10, 12), poids: 900);
    await fiche(lot, DateTime(2026, 10, 19), poids: 1100);

    await afficher(tester);
    await ouvrir(tester, 'Prévision de Croissance');

    final cellules = [
      for (final t in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const Key('ligne-prevision-CUN-1')),
          matching: find.byType(Text),
        ),
      ))
        t.data!,
    ];
    expect(cellules, ['CUN-1', '1100', '21.4 g/j', '1726']);
  });

  // ═══ 3. Parité EXÉCUTÉE avec le vrai PHP ═════════════════════════════════

  test(
    '⚠️⚠️ parité exécutée : DashboardElevage (Livewire) et gmqCumule, mêmes chiffres',
    () async {
      final hasard = Random(1906);
      const especes = [
        ('cuniculture', 'Cuniculture (Lapins)', true),
        ('aviculture', 'Aviculture (Volailles)', true),
        ('porciculture', 'Porciculture (Porcs)', true),
        ('helico', 'Héliciculture (Escargots)', false),
      ];
      const types = ['Vaccination', 'Vaccination', 'Déparasitage', 'Vitamines'];

      // ⚠️ Aucune fiche le 1er du mois : SQLite (base du test PHP) compare `entry_date` en chaîne
      // et exclut « 2026-10-01 » de `[startOfMonth 00:00:00, …]`, là où MySQL (production) l'inclut.
      final jours = [
        for (var j = 0; j < 46; j++) DateTime(2026, 9, 4 + j),
      ].where((d) => d.day != 1 && !d.isAfter(DateTime(2026, 10, 19))).toList();

      final lots = <Map<String, Object?>>[];
      final fiches = <Map<String, Object?>>[];
      final soins = <Map<String, Object?>>[];
      for (var i = 0; i < 30; i++) {
        final espece = especes[hasard.nextInt(especes.length)].$1;
        final initial = 20 + hasard.nextInt(300);
        lots.add({
          'code': 'B${i.toString().padLeft(2, '0')}',
          'espece': espece,
          'status': hasard.nextInt(4) == 0 ? 'cloture' : 'actif',
          'is_active': hasard.nextInt(8) != 0,
          'initial': initial,
          'courant': hasard.nextInt(initial + 1),
        });
        final retenus = ([...jours]..shuffle(hasard)).take(hasard.nextInt(12));
        for (final d in retenus) {
          final tirage = hasard.nextInt(10);
          fiches.add({
            'lot': 'B${i.toString().padLeft(2, '0')}',
            'date': _iso(d),
            'mort': hasard.nextInt(5),
            'effectif_final': hasard.nextInt(initial + 1),
            'poids': tirage < 3
                ? null
                : tirage == 3
                ? 0
                : 100 + hasard.nextInt(2900),
          });
        }
      }
      for (var k = 0; k < 40; k++) {
        soins.add({
          'lot': 'B${hasard.nextInt(30).toString().padLeft(2, '0')}',
          'type': types[hasard.nextInt(types.length)],
          'cout': hasard.nextInt(5) == 0 ? null : 500 * hasard.nextInt(40),
          'date': _iso(jours[hasard.nextInt(jours.length)]),
        });
      }

      // ── Poste ──
      for (final (code, libelle, actif) in especes) {
        if (actif) {
          // Le tirage ne sert que les espèces `enabled()`.
          await db
              .into(db.livestockSpecies)
              .insert(
                LivestockSpeciesCompanion.insert(
                  id: uuid('esp-$code'),
                  code: code,
                  label: libelle,
                ),
              );
        }
        await db
            .into(db.modulesConfig)
            .insert(
              ModulesConfigCompanion.insert(
                id: uuid('mod-$code'),
                speciesCode: code,
                isEnabled: Value(actif),
              ),
            );
      }
      final ids = <String, String>{};
      for (final l in lots) {
        ids[l['code'] as String] = await bande(
          l['code'] as String,
          l['espece'] as String,
          statut: l['status'] as String,
          active: l['is_active'] as bool,
          initial: l['initial'] as int,
          courant: l['courant'] as int,
        );
      }
      for (final f in fiches) {
        await fiche(
          ids[f['lot']]!,
          DateTime.parse(f['date'] as String),
          poids: (f['poids'] as int?)?.toDouble(),
          mort: f['mort'] as int,
          effectif: f['effectif_final'] as int,
        );
      }
      for (final (k, s) in soins.indexed) {
        await db
            .into(db.veterinaryRecords)
            .insert(
              VeterinaryRecordsCompanion.insert(
                id: uuid('soin-$k-'),
                deviceId: 'poste-test',
                updatedAt: maintenant,
                lotId: ids[s['lot']]!,
                actionType: s['type'] as String,
                cost: Value((s['cout'] as int?)?.toDouble()),
                recordDate: DateTime.parse(s['date'] as String),
              ),
            );
      }
      final d = await depot.charger(quand: maintenant);

      // ── Serveur ──
      final php =
          executerPhp(
                '<?php\n$amorceApplication\n$_scriptDashboard',
                {
                  'maintenant': '2026-10-19 10:15:00',
                  'especes': [
                    for (final (c, l, a) in especes)
                      {'code': c, 'label': l, 'actif': a},
                  ],
                  'lots': lots,
                  'fiches': fiches,
                  'soins': soins,
                },
                application: true,
              )
              as Map<String, dynamic>;

      double? n(Object? v) => (v as num?)?.toDouble();

      final kpis = php['synthese'] as Map<String, dynamic>;
      expect(d.effectifTotal, kpis['effectif_total']);
      expect(d.gmqMoyen, n(kpis['gmq_moyen']));
      expect(d.mortalite7j, n(kpis['taux_mortalite_7j']));
      expect(d.mortalite7j, greaterThan(0), reason: 'le jeu exerce la fenêtre');

      final cartes = {
        for (final c in php['especes'] as List) (c as List)[0]: c,
      };
      expect(d.especes.map((c) => c.code).toSet(), cartes.keys.toSet());
      for (final c in d.especes) {
        final attendu = cartes[c.code] as List;
        expect(c.lignes[0].$2, '${attendu[1]}', reason: c.code);
        expect(
          c.lignes[1].$2,
          DashboardElevageRepository.pourcent(n(attendu[2])!),
          reason: c.code,
        );
      }

      final tableau = {
        for (final r in php['gmq'] as List) (r as List)[0]: r,
      };
      expect(d.lignesGmq.map((l) => l.code).toSet(), tableau.keys.toSet());
      var avecGmq = 0;
      for (final l in d.lignesGmq) {
        final r = tableau[l.code] as List;
        expect(
          [l.poidsInitial, l.poidsActuel, l.jours?.toDouble(), l.gmq],
          [n(r[1]), n(r[2]), n(r[3]), n(r[4])],
          reason: l.code,
        );
        if (l.gmq != null) avecGmq++;
      }
      expect(avecGmq, greaterThan(5), reason: 'le jeu exerce le GMQ');

      final cumules = php['gmq_cumule'] as Map<String, dynamic>;
      for (final l in lots) {
        final code = l['code'] as String;
        final pesees = [
          for (final f in fiches.where((f) => f['lot'] == code))
            if (f['poids'] != null)
              (
                DateTime.parse(f['date'] as String),
                (f['poids'] as int).toDouble(),
              ),
        ];
        expect(
          DashboardElevageRepository.gmqCumule(pesees),
          n(cumules[code]),
          reason: 'gmqCumule $code',
        );
      }

      final previsions = {
        for (final r in php['previsions'] as List) (r as List)[0]: r,
      };
      expect(
        d.lignesPrevision.map((l) => l.code).toSet(),
        previsions.keys.toSet(),
      );
      for (final l in d.lignesPrevision) {
        final r = previsions[l.code] as List;
        expect(
          [l.insuffisant, l.poidsActuel?.toDouble(), l.tendance, l.projection30j],
          [r[1], n(r[2]), n(r[3]), n(r[4])],
          reason: l.code,
        );
      }

      final sanitaire = php['sanitaire'] as Map<String, dynamic>;
      expect(d.traitementsDuMois, sanitaire['nb']);
      expect(d.coutSanitaireDuMois, n(sanitaire['cout']));
      if (sanitaire['unique'] == true) {
        expect(d.traitementLePlusFrequent, sanitaire['frequent']);
      }
      final parEspece = {
        for (final r in php['sanitaire_especes'] as List) (r as List)[0]: r,
      };
      expect(d.sanitaire.map((s) => s.code).toSet(), parEspece.keys.toSet());
      for (final s in d.sanitaire) {
        final r = parEspece[s.code] as List;
        expect([s.nombreDeTraitements, s.coutTotal], [r[1], n(r[2])]);
      }
    },
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Construit le jeu dans Laravel (SQLite en mémoire) et interroge le VRAI composant.
const _scriptDashboard = r'''
$entree = json_decode(file_get_contents($argv[1]), true);
Carbon\Carbon::setTestNow(Carbon\Carbon::parse($entree['maintenant']));
$especes = [];
foreach ($entree['especes'] as $e) {
    App\Models\ModuleConfig::create(['species_code' => $e['code'], 'is_enabled' => $e['actif']]);
    $especes[$e['code']] = App\Models\LivestockSpecies::create(['code' => $e['code'], 'label' => $e['label'], 'is_enabled' => true]);
}
$lots = [];
foreach ($entree['lots'] as $l) {
    $lots[$l['code']] = App\Models\LivestockLot::create([
        'code' => $l['code'], 'species_id' => $especes[$l['espece']]->id, 'stage' => 'croissance',
        'initial_quantity' => $l['initial'], 'current_quantity' => $l['courant'],
        'created_date' => '2026-08-01', 'status' => $l['status'], 'is_active' => $l['is_active'],
    ]);
}
foreach ($entree['fiches'] as $f) {
    $e = new App\Models\LivestockDailyEntry([
        'lot_id' => $lots[$f['lot']]->id, 'entry_date' => $f['date'], 'mort' => $f['mort'],
        'effectif_final' => $f['effectif_final'], 'weight_sample_avg_g' => $f['poids'],
    ]);
    $e->save();
}
foreach ($entree['soins'] as $s) {
    App\Models\VeterinaryRecord::create([
        'lot_id' => $lots[$s['lot']]->id, 'action_type' => $s['type'], 'cost' => $s['cout'],
        'record_date' => $s['date'], 'is_active' => true,
    ]);
}
$c = new App\Livewire\Elevage\DashboardElevage();
$service = app(App\Services\GrowthAnalysisService::class);
$cumules = [];
foreach ($lots as $code => $lot) {
    $cumules[$code] = $service->gmqCumule($lot->id);
}
$kpis = $c->sanitaireKpis;
$comptes = App\Models\VeterinaryRecord::whereIn('lot_id', $c->activeLots->pluck('id'))->where('is_active', true)
    ->whereMonth('record_date', now()->month)->whereYear('record_date', now()->year)
    ->selectRaw('action_type, COUNT(*) as total')->groupBy('action_type')->orderByDesc('total')->pluck('total')->all();
echo json_encode([
    'synthese' => $c->syntheseKpis,
    'especes' => $c->speciesSummary->map(fn ($r) => [$r['species']->code, $r['effectif'], $r['taux_mortalite']])->values(),
    'gmq' => $c->gmqTable->map(fn ($r) => [$r['lot']->code, $r['poids_initial'], $r['poids_actuel'], $r['jours'], $r['gmq']])->values(),
    'gmq_cumule' => $cumules,
    'previsions' => $c->previsions->map(fn ($r) => [$r['lot']->code, $r['insufficient'], $r['poids_actuel'] ?? null, $r['tendance_g_par_jour'] ?? null, $r['projection_30j'] ?? null])->values(),
    'sanitaire' => ['nb' => $kpis['nb_traitements_mois'], 'cout' => $kpis['cout_sanitaire_mois'], 'frequent' => $kpis['traitement_frequent'],
        'unique' => count($comptes) < 2 || $comptes[0] > $comptes[1]],
    'sanitaire_especes' => $c->sanitaireBySpecies->map(fn ($r) => [$r['species']->code, $r['nb_traitements'], $r['cout_total']])->values(),
]);
''';
