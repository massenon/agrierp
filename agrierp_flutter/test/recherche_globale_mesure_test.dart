import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:agrierp/features/recherche/recherche_globale_champ.dart';
import 'package:agrierp/features/recherche/recherche_globale_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';

/// Ticket ENV1 (demande 3) — LA BARRE DE RECHERCHE GLOBALE A LA HAUTEUR DU WEB.
///
/// Le poste la dessinait en 32 px de haut (`SizedBox(height: 32)`, valeur « à l'œil »). Le web
/// (`livewire/shared/global-search.blade.php`) la fait 44 px : pastille `border` + `py-xs` autour d'un `<input>`
/// qui garde, faute de `border-0` / `p-0`, le style de base de `@tailwindcss/forms` (bordure 1 px, `padding: .5rem
/// .75rem`), le tout à l'interligne `text-xs` (1 rem). La hauteur n'est écrite nulle part : elle SORT des classes.
/// Le poste la fait sortir des mêmes jetons, et ce test la mesure de deux façons indépendantes (le rendu, et la
/// somme recalculée depuis les fichiers du web).
///
/// ⚠️ Les mesures du rendu portent sur la police de test (Ahem) : la HAUTEUR d'une ligne ne dépend que de la taille
/// et de l'interligne, pas des glyphes ; la largeur du texte n'est pas mesurée.
void main() {
  final blade = File('$dossierLaravel/resources/views/livewire/shared/global-search.blade.php');
  final sansLaravel = blade.existsSync() ? null : 'dépôt Laravel absent (AGRIERP_LARAVEL)';

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> afficher(WidgetTester tester, double largeur) async {
    tester.view.physicalSize = Size(largeur, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarreSuperieure(
            groupe: '',
            ecran: 'Tableau de Bord',
            enAttente: 0,
            onBasculerMenu: () {},
            recherche: RechercheGlobaleChamp(
              depot: RechercheGlobaleRepository(database: db),
              role: 'admin',
              onNaviguer: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Centre vertical du contenu de la barre : 64 px de haut dont 1 px de trait bas (`border-b`).
  double centreBarre(WidgetTester tester) =>
      tester.getTopLeft(find.byType(BarreSuperieure)).dy + (tester.getSize(find.byType(BarreSuperieure)).height - AgriChamps.bordure) / 2;

  group('lecture du Blade et du CSS compilé du web', () {
    String classesDe(String source, String debut) {
      final i = source.indexOf(debut);
      expect(i, greaterThanOrEqualTo(0), reason: debut);
      return RegExp(r'class="([^"]*)"').firstMatch(source.substring(i))!.group(1)!;
    }

    test('la pastille du Blade : `hidden md:flex items-center gap-xs bg-surface-zebra border border-outline-variant rounded-full px-md py-xs w-64`', () {
      final classes = classesDe(blade.readAsStringSync(), '<div class="hidden md:flex').split(RegExp(r'\s+')).toSet();
      expect(classes, containsAll(['hidden', 'md:flex', 'items-center', 'gap-xs', 'bg-surface-zebra', 'border', 'border-outline-variant', 'rounded-full', 'px-md', 'py-xs', 'w-64']));
    }, skip: sansLaravel);

    test("le champ du Blade : `bg-transparent outline-none text-xs w-full` — SANS `border-0` ni `p-*` : il garde le style de base des formulaires", () {
      final classes = classesDe(blade.readAsStringSync(), '<input\n            x-ref="searchInput"').split(RegExp(r'\s+')).toSet();
      expect(classes, containsAll(['bg-transparent', 'outline-none', 'text-xs', 'w-full']));
      expect(classes.where((c) => c == 'border-0' || c == 'border-none' || RegExp(r'^p[xytblr]?-').hasMatch(c)), isEmpty,
          reason: "un `border-0` ou `p-0` sur l'input changerait la hauteur du web : refaire le calcul du poste");
    }, skip: sansLaravel);

    test("@tailwindcss/forms est actif au web : c'est lui qui donne son padding et sa bordure à l'input", () {
      expect(File('$dossierLaravel/tailwind.config.js').readAsStringSync(), contains("require('@tailwindcss/forms')"));
    }, skip: sansLaravel);

    test("la hauteur du web recalculée depuis ses fichiers (config Tailwind + CSS compilé) vaut celle du poste", () {
      final config = File('$dossierLaravel/tailwind.config.js').readAsStringSync();
      double espace(String nom) => double.parse(RegExp("$nom: '(\\d+)px'").firstMatch(config)!.group(1)!);
      final xs = espace('xs');
      final md = espace('md');

      final dossier = Directory('$dossierLaravel/public/build/assets');
      final css = dossier.existsSync()
          ? dossier.listSync().whereType<File>().where((f) => f.path.endsWith('.css')).map((f) => f.readAsStringSync()).join('\n')
          : '';
      if (css.isEmpty) {
        markTestSkipped('CSS compilé absent (npm run build)');
        return;
      }
      // `.text-xs{font-size:.75rem;line-height:1rem}` (la taille est surchargée à 0,85 rem, pas l'interligne).
      final interligne = double.parse(RegExp(r'\.text-xs\{font-size:[^;]+;line-height:([\d.]+)rem').firstMatch(css)!.group(1)!) * 16;
      // Base @tailwindcss/forms : `border-width:1px; padding:.5rem .75rem`.
      final forms = RegExp(r'input:where\(\[type=text\]\)[^{]*\{[^}]*border-width:(\d+)px;[^}]*padding:([\d.]+)rem ([\d.]+)rem').firstMatch(css)!;
      final bordureInput = double.parse(forms.group(1)!);
      final rembourrageV = double.parse(forms.group(2)!) * 16;
      final rembourrageH = double.parse(forms.group(3)!) * 16;

      const bordurePastille = 1.0; // `border`
      final input = bordureInput * 2 + rembourrageV * 2 + interligne;
      final pastille = bordurePastille * 2 + xs * 2 + input; // `py-xs`
      expect(pastille, 44, reason: 'hauteur de la pastille du web, calculée');
      expect(pastille, AgriChamps.hauteurRechercheGlobale);
      expect(rembourrageH, AgriChamps.rembourrageHorizontalChampBrut);
      expect(rembourrageV, AgriChamps.rembourrageVerticalChampBrut);
      expect(md, AgriSpacing.md);
      expect(xs, AgriSpacing.xs);
      expect(interligne, AgriTypography.xsInterligne);
    }, skip: sansLaravel);

    test("`w-64` du web = 16 rem = 256 px, jeton `AgriChamps.largeurRechercheGlobale`", () {
      expect(AgriChamps.largeurRechercheGlobale, 256);
    });
  });

  group('rendu : pastille de 256 x 44, centrée dans la barre de 64 px', () {
    for (final largeur in [1024.0, 1440.0]) {
      testWidgets('à ${largeur.toInt()} px', (tester) async {
        await afficher(tester, largeur);
        final champ = find.byKey(const Key('recherche-globale'));

        expect(tester.getSize(champ), const Size(256, 44));
        // Alignement vertical : centre de la pastille = centre de la barre (`items-center`).
        expect(tester.getCenter(champ).dy, centreBarre(tester));
        expect(find.byKey(const Key('recherche-globale-icone')), findsNothing);
      });
    }

    testWidgets("à 768 px (`md:`), la pastille s'affiche déjà", (tester) async {
      await afficher(tester, 768);
      expect(tester.getSize(find.byKey(const Key('recherche-globale'))), const Size(256, 44));
    });

    testWidgets("le décor : fond surface-zebra, trait outline-variant 1 px, rayon plein (`rounded-full`)", (tester) async {
      await afficher(tester, 1024);
      final deco = tester.widget<DecoratedBox>(find.byKey(const Key('recherche-globale-pastille'))).decoration as BoxDecoration;

      expect(deco.color, AgriColors.surfaceZebra);
      expect(deco.borderRadius, BorderRadius.circular(AgriRadius.full));
      expect((deco.border! as Border).top, const BorderSide(color: AgriColors.outlineVariant));
    });

    testWidgets("le padding : `px-md py-xs` autour, icône 16 px, `gap-xs`, champ en `text-xs`", (tester) async {
      await afficher(tester, 1024);
      final pastille = find.byKey(const Key('recherche-globale'));
      final icone = find.descendant(of: pastille, matching: find.byType(Icon)).first;
      final saisie = find.byKey(const Key('recherche-globale-saisie'));

      // Bord gauche de la pastille + trait 1 + `px-md` 16 = début de l'icône.
      expect(tester.getTopLeft(icone).dx - tester.getTopLeft(pastille).dx, 1 + AgriSpacing.md);
      expect(tester.getSize(icone), const Size(16, 16));
      // L'icône est suivie d'un `gap-xs` de 4 px, puis du champ.
      expect(tester.getTopLeft(find.byKey(const Key('recherche-globale-boite'))).dx - tester.getTopRight(icone).dx, AgriSpacing.xs);
      // Hauteur de la boîte du champ : trait 1 + `.5rem` + interligne 1 rem + `.5rem` + trait 1 = 34.
      expect(tester.getSize(find.byKey(const Key('recherche-globale-boite'))).height, 34);
      // Haut de la boîte : trait 1 + `py-xs` 4.
      expect(tester.getTopLeft(find.byKey(const Key('recherche-globale-boite'))).dy - tester.getTopLeft(pastille).dy, 1 + AgriSpacing.xs);

      final style = tester.widget<TextField>(saisie).style!;
      expect(style.fontSize, AgriTypography.xs);
      expect(style.height! * style.fontSize!, closeTo(AgriTypography.xsInterligne, 0.001));
    });

    testWidgets("au focus : anneau émeraude de 2 px autour de la pastille, et trait bleu sur la boîte du champ (`focus-within:ring-2 ring-brand-emerald` + base des formulaires)", (tester) async {
      await afficher(tester, 1024);
      await tester.tap(find.byKey(const Key('recherche-globale-saisie')));
      await tester.pump();

      final pastille = tester.widget<DecoratedBox>(find.byKey(const Key('recherche-globale-pastille'))).decoration as BoxDecoration;
      expect(pastille.boxShadow!.single.spreadRadius, AgriChamps.anneauFocus);
      expect(pastille.boxShadow!.single.color, AgriColors.brandEmerald);
      final boite = tester.widget<DecoratedBox>(find.byKey(const Key('recherche-globale-boite'))).decoration as BoxDecoration;
      expect((boite.border! as Border).top.color, AgriColors.infoBlue);
      // Le focus ne change PAS la hauteur : l'anneau est une ombre, pas de l'espace.
      expect(tester.getSize(find.byKey(const Key('recherche-globale'))).height, 44);
    });

    testWidgets("saisir du texte fait apparaître le bouton d'effacement (`close` 14 px) sans changer la hauteur", (tester) async {
      await afficher(tester, 1024);
      await tester.enterText(find.byKey(const Key('recherche-globale-saisie')), 'a');
      await tester.pump();

      final effacer = find.byKey(const Key('recherche-globale-effacer'));
      expect(effacer, findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('recherche-globale'))), const Size(256, 44));
      await tester.tap(effacer);
      await tester.pump();
      expect(find.byKey(const Key('recherche-globale-effacer')), findsNothing);
    });
  });

  group("sous `md` (768 px) : l'icône seule, comme le web (`hidden md:flex` / `md:hidden`)", () {
    testWidgets("à 640 px : une icône `search` de 24 px, pas de pastille", (tester) async {
      await afficher(tester, 640);

      expect(find.byKey(const Key('recherche-globale')), findsNothing);
      final icone = find.byKey(const Key('recherche-globale-icone'));
      expect(tester.getSize(icone), const Size(24, 24));
      expect(tester.getCenter(icone).dy, centreBarre(tester));
    });

    testWidgets("un clic sur l'icône déploie le champ (même pastille 256 x 44) et lui donne le focus", (tester) async {
      await afficher(tester, 640);
      await tester.tap(find.byKey(const Key('recherche-globale-icone')));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byKey(const Key('recherche-globale'))), const Size(256, 44));
      expect(tester.widget<TextField>(find.byKey(const Key('recherche-globale-saisie'))).focusNode!.hasFocus, isTrue);
    });
  });

  group('Ctrl+K (H1b) reste branché', () {
    testWidgets("donne le focus à la pastille à 1024 px", (tester) async {
      await afficher(tester, 1024);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(tester.widget<TextField>(find.byKey(const Key('recherche-globale-saisie'))).focusNode!.hasFocus, isTrue);
    });

    testWidgets("à 640 px, Ctrl+K déploie le champ puis le focalise (le web n'a pas de champ visible là)", (tester) async {
      await afficher(tester, 640);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byKey(const Key('recherche-globale-saisie'))).focusNode!.hasFocus, isTrue);
    });
  });

  group('garde-fou sur le code du poste', () {
    test("plus de hauteur « à l'œil » : la hauteur sort des jetons, aucun `height: 32` ni `width: 256` en dur", () {
      final champ = File('lib/features/recherche/recherche_globale_champ.dart').readAsStringSync();
      final cadre = File('lib/core/widgets/cadre_recherche_globale.dart').readAsStringSync();
      for (final source in [champ, cadre]) {
        final code = source.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
        expect(code, isNot(contains('height: 32')));
        expect(code, isNot(contains('height: 34')));
        expect(code, isNot(contains('width: 256')));
      }
      expect(cadre, contains('AgriChamps.largeurRechercheGlobale'));
      expect(cadre, contains('AgriSpacing.xs'));
      expect(cadre, contains('AgriSpacing.md'));
    });

    test("la barre sans source de recherche dessine la MÊME pastille (un seul composant)", () {
      final barre = File('lib/core/widgets/barre_superieure.dart').readAsStringSync();
      expect(barre, contains('CadreRechercheGlobale('));
      expect(barre, isNot(contains('height: 34')));
    });
  });
}
