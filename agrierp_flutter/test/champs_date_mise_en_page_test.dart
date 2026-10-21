import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/theme/symboles_agri.dart';
import 'package:agrierp/core/widgets/champs_date_agri.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/saisie_depenses_screen.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:agrierp/features/elevage/elements_fiche.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_repository.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_screen.dart';
import 'package:agrierp/features/rapports/rapports_exports_screen.dart';
import 'package:agrierp/features/rapports/rapports_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket MP1 — MISE EN PAGE DES LIBELLÉS ET CHAMPS « DATE » ET « MOIS » (demande client : marges, espacements,
/// alignements et proportions), le Blade étant le maître (doctrine, article 5).
///
/// Trois familles de garde-fous, toutes écrites avant le code :
///  1. **mesures** (`getRect` / `getSize` / `getTopLeft`) des champs partagés ([ChampDateFormulaire],
///     [ChampDateFiltre], l'en-tête des fiches) à 640, 1024 et 1440 px : libellé à la marge attendue, champs de même
///     hauteur sur une même ligne, aucun débordement ;
///  2. **mesures des écrans** qui portent ces champs (Rapports, Tableau de bord, Grand Livre, Saisie des Dépenses) ;
///  3. **lecture du Blade** : les classes Tailwind des `<input type="date">` et de `mois-de-fiche` sont LUES et
///     comparées aux constantes du poste ([AgriChamps], [AgriSpacing]) — une retouche du web rougit ce fichier ;
///     chaque écran du poste qui ouvre un calendrier passe par un champ partagé.
void main() {
  const largeurs = [640.0, 1024.0, 1440.0];

  Future<void> monter(WidgetTester tester, Widget enfant, {required double largeur}) async {
    tester.view.physicalSize = Size(largeur, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: enfant),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'débordement à $largeur px');
  }

  Rect rect(WidgetTester tester, Finder f) => tester.getRect(f.first);

  // ── 1. Champ de formulaire : libellé AU-DESSUS, h-11 ────────────────────────────────────────────────────────
  group('ChampDateFormulaire — libellé au-dessus, marge mb-xs, h-11', () {
    for (final largeur in largeurs) {
      testWidgets('à ${largeur.toInt()} px', (tester) async {
        await monter(
          tester,
          SizedBox(
            width: largeur - 2 * AgriSpacing.md,
            child: ChampDateFormulaire(
              cle: const Key('champ'),
              etiquette: 'Date du Soin *',
              valeur: DateTime(2026, 10, 20),
              onTap: () {},
            ),
          ),
          largeur: largeur,
        );
        final etiquette = rect(tester, find.text('DATE DU SOIN *'));
        final champ = rect(tester, find.byKey(const Key('champ')));
        expect(champ.height, AgriChamps.hauteurFormulaire);
        expect(champ.width, largeur - 2 * AgriSpacing.md, reason: 'w-full');
        expect(champ.left, etiquette.left, reason: 'libellé et champ alignés à gauche');
        expect(champ.top - etiquette.bottom, closeTo(AgriSpacing.xs, 0.01), reason: 'mb-xs entre libellé et champ');
        expect(etiquette.height, AgriChamps.etiquetteFormulaire * AgriTypography.interligneCorps);
        final style = tester.widget<Text>(find.text('DATE DU SOIN *')).style!;
        expect(style.fontSize, AgriChamps.etiquetteFormulaire);
        expect(style.fontWeight, AgriTypography.gras);
        expect(style.color, AgriColors.brandForest);
        // Le texte de la date est centré verticalement dans le champ, à `px-md` du bord gauche.
        final texte = rect(tester, find.text('20/10/2026'));
        expect(texte.left - champ.left, closeTo(AgriSpacing.md + AgriChamps.bordure, 0.01));
        expect((texte.center.dy - champ.center.dy).abs(), lessThan(1));
        expect(tester.widget<Text>(find.text('20/10/2026')).style!.fontSize, AgriTypography.sm);
      });
    }

    testWidgets('erreur : 11 px à 2 px sous le champ, bord et fond d is-invalid', (tester) async {
      await monter(
        tester,
        SizedBox(
          width: 300,
          child: ChampDateFormulaire(
            cle: const Key('champ'),
            etiquette: 'Date *',
            valeur: DateTime(2026, 10, 20),
            onTap: () {},
            erreur: 'Exercice clos.',
            cleErreur: const Key('erreur'),
          ),
        ),
        largeur: 640,
      );
      final champ = rect(tester, find.byKey(const Key('champ')));
      final erreur = rect(tester, find.byKey(const Key('erreur')));
      expect(erreur.top - champ.bottom, closeTo(AgriChamps.erreurMarge, 0.01));
      expect(erreur.left, champ.left);
      expect(tester.widget<Text>(find.byKey(const Key('erreur'))).style!.fontSize, AgriChamps.erreurTaille);
      final cadre = tester.widget<Material>(find.ancestor(of: find.byKey(const Key('champ')), matching: find.byType(Material)).first);
      expect((cadre.shape! as RoundedRectangleBorder).side.color, AgriColors.errorDeep, reason: 'is-invalid : bord #BA1A1A');
      expect(cadre.color, kFondChampInvalide, reason: 'is-invalid : fond #FFF5F5');
    });

    testWidgets('paire Début / Fin : grid-cols-2 gap-sm, même hauteur, même ligne', (tester) async {
      await monter(
        tester,
        SizedBox(
          width: 500,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: ChampDateFormulaire(cle: const Key('debut'), etiquette: 'Date de Début', valeur: DateTime(2026, 1, 5), onTap: () {})),
              const SizedBox(width: AgriSpacing.sm),
              Expanded(child: ChampDateFormulaire(cle: const Key('fin'), etiquette: 'Date de Fin', valeur: null, onTap: () {})),
            ],
          ),
        ),
        largeur: 640,
      );
      final debut = rect(tester, find.byKey(const Key('debut')));
      final fin = rect(tester, find.byKey(const Key('fin')));
      expect(debut.width, fin.width);
      expect(debut.height, fin.height);
      expect(debut.top, fin.top);
      expect(fin.left - debut.right, closeTo(AgriSpacing.sm, 0.01));
      expect(find.text('jj/mm/aaaa'), findsOneWidget, reason: 'date absente : le format attendu');
    });

    testWidgets('désactivé : fond bg-surface-zebra, texte text-outline, aucun geste', (tester) async {
      var appuis = 0;
      await monter(
        tester,
        SizedBox(
          width: 300,
          child: ChampDateFormulaire(
            cle: const Key('champ'),
            etiquette: 'Date du Transfert *',
            valeur: DateTime(2026, 10, 20),
            onTap: () => appuis++,
            desactive: true,
          ),
        ),
        largeur: 640,
      );
      await tester.tap(find.byKey(const Key('champ')));
      expect(appuis, 0);
      expect(tester.widget<Text>(find.text('20/10/2026')).style!.color, AgriColors.outline);
    });
  });

  // ── 1b. Champ de filtre : px-sm py-2 / py-1.5, text-xs ──────────────────────────────────────────────────────
  group('ChampDateFiltre — px-sm, py-2 ou py-1.5, text-xs', () {
    testWidgets('hauteurs : 34 px (py-2) et 30 px (py-1.5), texte à px-sm', (tester) async {
      await monter(
        tester,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChampDateFiltre(cle: const Key('standard'), valeur: DateTime(2026, 10, 1), onTap: () {}),
            const SizedBox(width: AgriSpacing.sm),
            ChampDateFiltre(cle: const Key('compact'), valeur: DateTime(2026, 10, 1), onTap: () {}, compact: true),
          ],
        ),
        largeur: 640,
      );
      final standard = rect(tester, find.byKey(const Key('standard')));
      final compact = rect(tester, find.byKey(const Key('compact')));
      expect(standard.height, AgriChamps.hauteurFiltre(margeVerticale: AgriSpacing.sm));
      expect(standard.height, 34);
      expect(compact.height, AgriChamps.hauteurFiltre(margeVerticale: AgriChamps.margeVerticaleCompacte));
      expect(compact.height, 30);
      final texte = rect(tester, find.descendant(of: find.byKey(const Key('standard')), matching: find.text('01/10/2026')));
      expect(texte.left - standard.left, closeTo(AgriSpacing.sm + AgriChamps.bordure, 0.01));
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('standard')), matching: find.text('01/10/2026'))).style!.fontSize, AgriTypography.xs);
    });
  });

  // ── 1c. En-tête des fiches : « Bande : », « Date : », « Mois : » ───────────────────────────────────────────
  group('EnTeteSaisieFiche — libellés en ligne, h-9, gap-xs', () {
    Widget entete() => EnTeteSaisieFiche(
      titre: 'Saisie Journalière du Cheptel',
      jour: DateTime(2026, 10, 20),
      onJour: (_) {},
      bandes: const [('b1', 'LAP-01'), ('b2', 'LAP-02')],
      bandeId: 'b1',
      onBande: (_) {},
      maintenant: DateTime(2026, 10, 20),
      onMoisPrecedent: () {},
      onMoisSuivant: () {},
    );

    for (final largeur in [...largeurs, 360.0]) {
      testWidgets('à ${largeur.toInt()} px', (tester) async {
        await monter(tester, SizedBox(width: largeur, child: entete()), largeur: largeur);
        final etiqDate = rect(tester, find.text('Date :'));
        final champ = rect(tester, find.byKey(const Key('date-fiche')));
        final etiqMois = rect(tester, find.text('Mois :'));
        final mois = rect(tester, find.byKey(const Key('mois-de-fiche')));
        final etiqBande = rect(tester, find.text('Bande :'));
        final bande = rect(tester, find.byKey(const Key('bande-fiche')));

        for (final r in [champ, mois, bande]) {
          expect(r.height, AgriChamps.hauteurCompacte, reason: 'h-9 pour les trois sélecteurs');
        }
        // Chaque libellé et chaque champ est un enfant PROPRE du `flex-wrap gap-xs` : un libellé reste collé à son champ
        // (gap-xs, centré dessus) tant qu'ils tiennent sur la même ligne ; sinon le champ passe à la ligne SEUL, au
        // début de la ligne suivante, comme au Blade. (Le banc de test dessine en police Ahem : toutes les chaînes y
        // sont deux fois plus larges qu'en Inter, d'où des replis que le navigateur ne fait qu'à 360 px.)
        bool memeLigne(Rect a, Rect b) => (a.center.dy - b.center.dy).abs() < 1;
        void paire(Rect etiquette, Rect champ, String nom) {
          if (memeLigne(etiquette, champ)) {
            expect(champ.left - etiquette.right, closeTo(AgriSpacing.xs, 0.01), reason: '$nom : gap-xs');
          } else {
            expect(champ.left, 0, reason: '$nom : le champ replié commence la ligne suivante');
          }
        }

        paire(etiqDate, champ, 'Date');
        paire(etiqMois, mois, 'Mois');
        paire(etiqBande, bande, 'Bande');
        expect(etiqMois.left - champ.right, closeTo(AgriSpacing.xs, 0.01), reason: 'gap-xs entre le champ Date et « Mois : »', skip: !memeLigne(champ, etiqMois));
        // gap-y xs entre deux lignes de repli de la barre (sans le titre, qui est dans l'autre ligne du `justify-between`).
        final lignes = <double, List<Rect>>{};
        for (final r in [etiqBande, bande, etiqDate, champ, etiqMois, mois]) {
          lignes.putIfAbsent(r.center.dy.roundToDouble(), () => []).add(r);
        }
        final ordre = lignes.keys.toList()..sort();
        for (var i = 1; i < ordre.length; i++) {
          final avant = lignes[ordre[i - 1]]!.map((r) => r.bottom).reduce((a, b) => a > b ? a : b);
          final apres = lignes[ordre[i]]!.map((r) => r.top).reduce((a, b) => a < b ? a : b);
          expect(apres - avant, closeTo(AgriSpacing.xs, 0.01), reason: 'gap-y xs entre les lignes de repli');
        }
        // Flèches : w-8 × h-9, icône 18 px.
        // `h-9` dans une boîte `h-9 border` à bords rognés (`overflow-hidden`) : 36 − 2 traits visibles.
        expect(rect(tester, find.byKey(const Key('mois-precedent'))).size, const Size(AgriChamps.largeurFleche, AgriChamps.hauteurCompacte - 2 * AgriChamps.bordure));
        expect(rect(tester, find.byKey(const Key('mois-suivant'))).width, AgriChamps.largeurFleche);
        final icone = tester.widget<Icon>(find.descendant(of: find.byKey(const Key('mois-precedent')), matching: find.byType(Icon)));
        expect(icone.size, AgriChamps.iconeFleche);
        // Le mois affiché est à px-sm de chaque flèche.
        final libelle = rect(tester, find.byKey(const Key('mois-affiche')));
        expect(libelle.left - rect(tester, find.byKey(const Key('mois-precedent'))).right, AgriSpacing.sm);
        expect(rect(tester, find.byKey(const Key('mois-suivant'))).left - libelle.right, AgriSpacing.sm);
        // `justify-between` : le groupe de droite finit au bord de la carte quand il tient à côté du titre.
        if (memeLigne(rect(tester, find.text('Saisie Journalière du Cheptel')), mois)) {
          expect(mois.right, closeTo(largeur, 1));
        }
      });
    }

    testWidgets('le champ Date porte l indicateur de calendrier du navigateur (16 px) à droite du texte', (tester) async {
      await monter(tester, SizedBox(width: 1024, child: entete()), largeur: 1024);
      final champ = rect(tester, find.byKey(const Key('date-fiche')));
      final icone = find.descendant(of: find.byKey(const Key('date-fiche')), matching: find.byIcon(SymbolesAgri.calendar_today));
      expect(icone, findsOneWidget);
      expect(tester.getSize(icone).width, AgriChamps.iconeCalendrier);
      expect(champ.right - tester.getRect(icone).right, AgriSpacing.md + AgriChamps.bordure);
    });
  });

  // ── 2. Écrans ──────────────────────────────────────────────────────────────────────────────────────────────
  group('écrans', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    testWidgets('Rapports & Exports — du / au : deux champs de 34 px alignés, « au » centré', (tester) async {
      for (final largeur in largeurs) {
        tester.view.physicalSize = Size(largeur, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(home: RapportsExportsScreen(depot: RapportsRepository(database: db), peutExporter: true)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'débordement à $largeur px');
        final du = rect(tester, find.byKey(const Key('hub-filter-du')));
        final au = rect(tester, find.byKey(const Key('hub-filter-au')));
        final mot = rect(tester, find.text('au').first);
        expect(du.height, AgriChamps.hauteurFiltre(margeVerticale: AgriSpacing.sm), reason: 'py-2 + text-xs à $largeur');
        expect(au.height, du.height);
        expect(au.top, du.top);
        expect(mot.left - du.right, closeTo(AgriSpacing.sm, 0.01), reason: 'gap-sm');
        expect(au.left - mot.right, closeTo(AgriSpacing.sm, 0.01), reason: 'gap-sm');
        expect((mot.center.dy - du.center.dy).abs(), lessThan(1));
      }
    });

    testWidgets('Tableau de bord — période : py-1.5, flex-1, icône 18 px à gap-xs ; ligne dès 640 px (sm:)', (tester) async {
      Future<void> afficher(double largeur) async {
        tester.view.physicalSize = Size(largeur, 3000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(home: TableauDeBordScreen(depot: TableauDeBordRepository(database: db))),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'débordement à $largeur px');
      }

      await afficher(1024);
      var du = rect(tester, find.byKey(const Key('date-du')));
      var au = rect(tester, find.byKey(const Key('date-au')));
      expect(du.height, AgriChamps.hauteurFiltre(margeVerticale: AgriChamps.margeVerticaleCompacte));
      expect(au.height, du.height);
      expect(au.top, du.top);
      expect((au.width - du.width).abs(), lessThan(1), reason: 'flex-1 des deux champs');
      final icone = tester.getRect(find.byIcon(SymbolesAgri.calendar_month).first);
      expect(icone.width, AgriChamps.iconePeriode);
      expect(du.left - icone.right, closeTo(AgriSpacing.xs, 0.01), reason: 'gap-xs entre l icône et le champ');

      // sm: (640 px) bascule en ligne ; en dessous, la colonne empile les dates puis le choix d'état.
      await afficher(700);
      du = rect(tester, find.byKey(const Key('date-du')));
      var etat = rect(tester, find.byKey(const Key('choix-etat')));
      expect((etat.center.dy - du.center.dy).abs(), lessThan(AgriChamps.hauteurFiltre(margeVerticale: AgriSpacing.sm) / 2),
          reason: 'à 700 px (≥ sm) les dates et le choix d état sont sur UNE ligne');
      expect(etat.width + 2 * (AgriSpacing.sm + AgriChamps.bordure), AgriChamps.largeurChoixEtat, reason: 'sm:w-56 = 224 px (cadre compris)');

      await afficher(600);
      du = rect(tester, find.byKey(const Key('date-du')));
      etat = rect(tester, find.byKey(const Key('choix-etat')));
      expect(etat.top, greaterThanOrEqualTo(du.bottom), reason: 'sous sm, flex-col');
    });

    testWidgets('Grand Livre — champs sans bordure p-1 dans un conteneur gris px-sm py-1', (tester) async {
      tester.view.physicalSize = const Size(1440, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: ComptabiliteScreen(depot: ComptabiliteRepository(database: db))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('carte-grandLivre')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final zone = rect(tester, find.byKey(const Key('gl-periode')));
      final debut = rect(tester, find.byKey(const Key('gl-date-debut')));
      final fin = rect(tester, find.byKey(const Key('gl-date-fin')));
      final mot = rect(tester, find.descendant(of: find.byKey(const Key('gl-periode')), matching: find.text('au')));
      expect(debut.height, AgriTypography.xsInterligne + 2 * AgriChamps.margeSansBordure, reason: 'text-xs + p-1');
      expect(zone.height, debut.height + 2 * AgriChamps.margeVerticaleConteneur, reason: 'py-1');
      expect(debut.left - zone.left, closeTo(AgriSpacing.sm, 0.01), reason: 'px-sm');
      expect(mot.left - debut.right, closeTo(AgriSpacing.xs, 0.01), reason: 'gap-xs');
      expect(fin.left - mot.right, closeTo(AgriSpacing.xs, 0.01), reason: 'gap-xs');
      expect(zone.right - fin.right, closeTo(AgriSpacing.sm, 0.01), reason: 'px-sm');
      expect((mot.center.dy - debut.center.dy).abs(), lessThan(1));
    });

    testWidgets('Saisie des Dépenses — « Date de la Transaction * » : libellé mb-xs, h-11, à 640 / 1024 / 1440', (tester) async {
      final depot = DepensesRepository(database: db, deviceId: 'poste-test');
      for (final largeur in largeurs) {
        tester.view.physicalSize = Size(largeur, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(home: SaisieDepensesScreen(depot: depot)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'débordement à $largeur px');
        final etiquette = rect(tester, find.text('DATE DE LA TRANSACTION *'));
        final champ = rect(tester, find.byKey(const Key('champ-date')));
        expect(champ.height, AgriChamps.hauteurFormulaire);
        expect(champ.top - etiquette.bottom, closeTo(AgriSpacing.xs, 0.01));
        expect(champ.left, etiquette.left);
        final libelle = rect(tester, find.byKey(const Key('champ-libelle')));
        // md:grid-cols-2 gap-md : deux colonnes égales dès 768 px, une colonne en dessous.
        if (largeur >= AgriBreakpoints.md) {
          expect(libelle.left - champ.right, closeTo(AgriSpacing.md, 0.01));
          expect(libelle.width, champ.width);
          expect(libelle.height, champ.height, reason: 'même hauteur h-11 sur une même ligne');
        } else {
          expect(libelle.top, greaterThan(champ.bottom));
          expect(libelle.left, champ.left);
        }
      }
    });
  });

  // ── 3. Garde-fous : les classes du Blade, LUES ─────────────────────────────────────────────────────────────
  group('Blade → poste', () {
    final vues = Directory('$dossierLaravel/resources/views');
    final sautSansWeb = vues.existsSync() ? null : 'SAUT : dépôt Laravel introuvable ($dossierLaravel)';

    /// Tailwind → pixels, avec l'échelle du projet (`xs…2xl`) PUIS l'échelle par défaut (×4).
    double? px(String classe) {
      final m = RegExp(r'^-?(?:h|w|p|px|py|pt|pb|m|mx|my|mt|mb|gap)-(.+)$').firstMatch(classe);
      if (m == null) return null;
      final v = m.group(1)!;
      const echelle = {
        'xs': AgriSpacing.xs,
        'sm': AgriSpacing.sm,
        'md': AgriSpacing.md,
        'lg': AgriSpacing.lg,
        'xl': AgriSpacing.xl,
      };
      if (echelle.containsKey(v)) return echelle[v];
      final arbitraire = RegExp(r'^\[(\d+(?:\.\d+)?)px\]$').firstMatch(v);
      if (arbitraire != null) return double.parse(arbitraire.group(1)!);
      final n = double.tryParse(v);
      return n == null ? null : n * 4;
    }

    Set<String> classes(String attribut) => attribut.trim().split(RegExp(r'\s+')).toSet();

    /// `class="…"` de chaque `<input … type="date" …>` d'un fichier Blade.
    List<Set<String>> champsDate(String blade) => [
      for (final m in RegExp(r'<input\b(?:[^>]|(?<=-)>)*?type="date"(?:[^>]|(?<=-)>)*>', dotAll: true).allMatches(blade))
        classes(RegExp(r'class="([^"]*)"').firstMatch(m.group(0)!)?.group(1) ?? ''),
    ];

    final tousLesBlades = vues.existsSync()
        ? [
            for (final f in vues.listSync(recursive: true).whereType<File>())
              if (f.path.endsWith('.blade.php')) f,
          ]
        : <File>[];

    test('les cinq fiches : sélecteur h-9 px-md text-xs font-bold, libellé text-xs text-outline font-semibold, gap-xs', () {
      for (final nom in ['lapins', 'porcs', 'pondeuses', 'reproducteurs', 'escargots']) {
        final blade = File('$dossierLaravel/resources/views/livewire/elevage/fiche-$nom.blade.php').readAsStringSync();
        final champs = champsDate(blade);
        expect(champs, hasLength(1), reason: 'fiche-$nom : un seul champ Date');
        final c = champs.single;
        expect(px(c.firstWhere((x) => x.startsWith('h-'))), AgriChamps.hauteurCompacte, reason: 'fiche-$nom h-9');
        expect(px(c.firstWhere((x) => x.startsWith('px-'))), AgriSpacing.md, reason: 'fiche-$nom px-md');
        expect(c, containsAll(['text-xs', 'font-bold', 'text-brand-forest', 'bg-surface-zebra', 'rounded-lg', 'border-outline-variant']));
        expect(blade, contains('<span class="text-xs text-outline font-semibold">Date :</span>'));
        // ⚠️ La fiche Reproducteurs écrit `flex items-center gap-xs` SANS `flex-wrap` : sa barre ne se replie pas au web.
        // Le poste la replie dans tous les cas (écart assumé, identique dès 640 px) ; `gap-xs` est commun aux cinq.
        expect(blade, contains(nom == 'reproducteurs' ? '<div class="flex items-center gap-xs">\n                <span class="text-xs text-outline font-semibold">Date :' : 'flex items-center gap-xs flex-wrap'), reason: 'fiche-$nom : barre gap-xs');
        expect(blade, contains('flex items-center justify-between border-b border-outline-variant pb-sm mb-md flex-wrap gap-xs'));
      }
      const etiquette = StylesChampsAgri.etiquetteEnLigne;
      expect(etiquette.fontSize, AgriTypography.xs);
      expect(etiquette.fontWeight, AgriTypography.demiGras);
      expect(etiquette.color, AgriColors.outline);
      const valeur = StylesChampsAgri.valeurFiche;
      expect(valeur.fontSize, AgriTypography.xs);
      expect(valeur.fontWeight, AgriTypography.gras);
      expect(valeur.color, AgriColors.brandForest);
    }, skip: sautSansWeb);

    test('mois-de-fiche : h-9, flèches w-8 h-9, icône 18 px, mois à px-sm, libellé « Mois : » identique', () {
      final blade = File('$dossierLaravel/resources/views/components/mois-de-fiche.blade.php').readAsStringSync();
      expect(blade, contains('<span class="text-xs text-outline font-semibold">Mois :</span>'));
      expect(blade, contains('flex items-center h-9 border border-outline-variant rounded-lg bg-surface-zebra'));
      expect(blade, contains('w-8 h-9 flex items-center justify-center'));
      expect(blade, contains('material-symbols-outlined text-[18px]'));
      expect(blade, contains('px-sm text-xs font-bold text-brand-forest'));
      expect(px('h-9'), AgriChamps.hauteurCompacte);
      expect(px('w-8'), AgriChamps.largeurFleche);
      expect(px('text-[18px]'.replaceFirst('text-', 'h-')), AgriChamps.iconeFleche);
      expect(px('px-sm'), AgriSpacing.sm);
    }, skip: sautSansWeb);

    test('chaque champ Date du Blade appartient à un gabarit connu du poste (sinon : à auditer)', () {
      final inconnus = <String>[];
      for (final f in tousLesBlades) {
        final nom = f.path.split('resources/views/').last;
        final blade = f.readAsStringSync();
        for (final c in champsDate(blade)) {
          String? gabarit;
          if (c.contains('h-9') && c.contains('bg-surface-zebra')) {
            gabarit = 'fiche';
          } else if (c.contains('h-11') && c.contains('px-md') && c.contains('text-sm')) {
            gabarit = 'formulaire';
          } else if (c.contains('h-10') && c.contains('px-md') && c.contains('text-xs')) {
            gabarit = 'caisse';
          } else if (c.contains('px-sm') && c.contains('py-2') && c.contains('text-xs')) {
            gabarit = 'filtre';
          } else if (c.contains('px-sm') && c.contains('py-1.5') && c.contains('text-xs')) {
            gabarit = 'filtre-compact';
          } else if (c.contains('p-1') && c.contains('border-0') && c.contains('text-xs')) {
            gabarit = 'sans-bordure';
          } else if (c.contains('px-md') && c.contains('py-2') && c.contains('text-sm')) {
            gabarit = 'immobilisations'; // arrêté d'immobilisations : absent du poste, hors périmètre
          } else if (c.contains('px-md') && c.contains('py-2')) {
            gabarit = 'immobilisations';
          } else if (c.contains('text-xs') && c.contains('font-bold') && c.contains('text-brand-forest')) {
            gabarit = 'rapprochement';
          }
          if (gabarit == null) inconnus.add('$nom : ${c.join(' ')}');
        }
      }
      expect(inconnus, isEmpty, reason: 'gabarit de champ Date nouveau au Blade : l\'auditer au poste');
    }, skip: sautSansWeb);

    test('gabarit formulaire : h-11 px-md text-sm ; libellé text-[10px] font-bold uppercase mb-xs ; caisse h-10 text-xs', () {
      var formulaires = 0;
      for (final f in tousLesBlades) {
        final blade = f.readAsStringSync();
        for (final c in champsDate(blade)) {
          if (c.contains('h-11')) {
            formulaires++;
            expect(px('h-11'), AgriChamps.hauteurFormulaire);
            expect(px(c.firstWhere((x) => x.startsWith('px-'))), AgriSpacing.md);
            expect(c, contains('w-full'));
            expect(c, contains('rounded-lg'));
          }
          if (c.contains('h-10')) {
            expect(px('h-10'), AgriChamps.hauteurCaisse);
          }
        }
        // Bons de commande : libellé `text-[9px] text-outline mb-1` propre à cet écran, absent du poste (hors périmètre).
        if (f.path.contains('bons-commande')) continue;
        for (final m in RegExp(r'<label[^>]*>(Date[^<]*)</label>').allMatches(blade)) {
          final etiq = classes(RegExp(r'class="([^"]*)"').firstMatch(m.group(0)!)!.group(1)!);
          expect(etiq, containsAll(['block', 'text-[10px]', 'text-brand-forest', 'font-bold', 'uppercase', 'mb-xs']), reason: '${f.path} : ${m.group(0)}');
        }
      }
      expect(formulaires, greaterThan(15), reason: 'le Blade compte plus de quinze champs Date de formulaire');
      expect(AgriChamps.etiquetteFormulaire, 10);
      expect(px('mb-xs'), AgriSpacing.xs);
      expect(StylesChampsAgri.etiquetteFormulaire.fontWeight, AgriTypography.gras);
    }, skip: sautSansWeb);

    test('gabarits de filtre : py-2 → 34 px, py-1.5 → 30 px ; Grand Livre p-1 dans px-sm py-1', () {
      expect(px('py-2'), AgriSpacing.sm);
      expect(px('py-1.5'), AgriChamps.margeVerticaleCompacte);
      expect(px('p-1'), AgriChamps.margeSansBordure);
      expect(px('py-1'), AgriChamps.margeVerticaleConteneur);
      final gl = File('$dossierLaravel/resources/views/livewire/comptabilite/grand-livre.blade.php').readAsStringSync();
      expect(gl, contains('flex items-center gap-xs bg-surface-zebra rounded-lg px-sm py-1'));
      final tdb = File('$dossierLaravel/resources/views/livewire/dashboard/index.blade.php').readAsStringSync();
      expect(tdb, contains('flex flex-col sm:flex-row items-stretch sm:items-center gap-sm bg-white border border-outline-variant rounded-lg p-sm'));
      expect(tdb, contains('<select x-model="report" class="text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white flex-1 sm:w-56">'));
      expect(AgriBreakpoints.sm, 640);
      final hub = File('$dossierLaravel/resources/views/livewire/rapports/rapports-exports-hub.blade.php').readAsStringSync();
      expect(hub, contains('bg-white border border-outline-variant rounded-lg p-md mb-lg flex flex-wrap items-center gap-sm'));
    }, skip: sautSansWeb);

    test('chaque écran du poste qui ouvre un calendrier passe par un champ partagé (champs_date_agri.dart)', () {
      final fautifs = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.endsWith('champs_date_agri.dart')) continue;
        final source = f.readAsStringSync();
        if (!source.contains('showDatePicker')) continue;
        // Un appel de code, pas une mention dans un commentaire.
        final appelle = source.split('\n').any((l) => RegExp(r'^\s*[^/\s].*showDatePicker\(').hasMatch(l));
        if (!appelle) continue;
        if (!source.contains("core/widgets/champs_date_agri.dart")) {
          fautifs.add(f.path);
        }
      }
      expect(fautifs, isEmpty, reason: 'un écran dessine seul son champ Date : OutlinedButton / InputDecorator');
    });

    test('plus aucun champ Date n est un OutlinedButton ni un InputDecorator nu', () {
      final fautifs = <String>[];
      for (final f in Directory('lib/features').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lignes = f.readAsLinesSync();
        for (var i = 0; i < lignes.length; i++) {
          if (!RegExp(r'^\s*[^/\s].*showDatePicker\(').hasMatch(lignes[i])) continue;
          final debut = i < 12 ? 0 : i - 12;
          final fenetre = lignes.sublist(debut, i).where((l) => !l.trimLeft().startsWith('//')).join('\n');
          if (fenetre.contains('OutlinedButton') || fenetre.contains('InputDecorator(')) {
            fautifs.add('${f.path}:${i + 1}');
          }
        }
      }
      expect(fautifs, isEmpty);
    });
  });
}
