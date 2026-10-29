
import 'package:agrierp/core/aide/aide_ecrans.dart';
import 'package:agrierp/core/aide/placement_visite.dart';
import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_theme.dart';
import 'package:agrierp/core/widgets/aide_flottante.dart';
import 'package:agrierp/core/config/parametres_poste.dart';
import 'package:agrierp/features/demarrage/premier_demarrage_repository.dart';
import 'package:agrierp/features/demarrage/premier_demarrage_screen.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coque_poste.dart';

/// Ticket AIDE-1 — bouton flottant d'aide, panneau, relance de l'assistant, visite guidée au poste.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> allumerModule(bool actif) => db.into(db.modulesConfig).insert(
    ModulesConfigCompanion.insert(
      id: 'cccccccc-0001-4000-8000-000000000001',
      speciesCode: 'assistant_demarrage',
      isEnabled: Value(actif),
      updatedAt: Value(DateTime(2026, 10, 29)),
    ),
  );

  void fenetre(WidgetTester t) {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  group('placement (valeurs de tests/Js/aide-logique.test.mjs, calculées à la main)', () {
    const f = Size(1000, 800);
    const c = Size(352, 240);

    test('rectUtilisable et trouAutour', () {
      expect(PlacementVisite.rectUtilisable(null, f), isFalse);
      expect(PlacementVisite.rectUtilisable(const Rect.fromLTWH(0, 0, 0, 0), f), isFalse);
      expect(PlacementVisite.rectUtilisable(const Rect.fromLTWH(-288, 0, 288, 800), f), isFalse);
      expect(PlacementVisite.rectUtilisable(const Rect.fromLTWH(1000, 0, 60, 60), f), isFalse);
      expect(PlacementVisite.rectUtilisable(const Rect.fromLTWH(0, 0, 288, 800), f), isTrue);
      expect(PlacementVisite.trouAutour(const Rect.fromLTWH(10, 10, 100, 50), f), const Rect.fromLTWH(4, 4, 112, 62));
      expect(PlacementVisite.trouAutour(const Rect.fromLTWH(0, 0, 288, 800), f), const Rect.fromLTWH(0, 0, 294, 800));
    });

    test('la carte : dessous, dessus, droite, bas, centre', () {
      var p = PlacementVisite.placerCarte(const Rect.fromLTWH(4, 4, 112, 62), c, f);
      expect((p.position, p.lieu), (const Offset(16, 78), 'dessous'));
      p = PlacementVisite.placerCarte(const Rect.fromLTWH(930, 690, 60, 60), c, f);
      expect((p.position, p.lieu), (const Offset(632, 438), 'dessus'));
      p = PlacementVisite.placerCarte(const Rect.fromLTWH(0, 0, 294, 800), c, f);
      expect((p.position, p.lieu), (const Offset(306, 16), 'droite'));
      p = PlacementVisite.placerCarte(const Rect.fromLTWH(294, 64, 706, 736), c, f);
      expect((p.position, p.lieu), (const Offset(324, 544), 'bas'));
      p = PlacementVisite.placerCarte(null, c, f);
      expect((p.position, p.lieu), (const Offset(324, 280), 'centre'));
      p = PlacementVisite.placerCarte(null, c, const Size(320, 500));
      expect((p.position, p.lieu), (const Offset(16, 130), 'centre'));
    });

    test('l indicateur remplit le gabarit', () {
      expect(PlacementVisite.indicateur('Étape :numero sur :total', 0, 4), 'Étape 1 sur 4');
      expect(PlacementVisite.indicateur('Étape :numero sur :total', 3, 4), 'Étape 4 sur 4');
    });
  });

  testWidgets('module éteint : aucun bouton d aide (comme aujourd hui) ; Accès rapide reste', (t) async {
    fenetre(t);
    await t.pumpWidget(MaterialApp(theme: AgriTheme.light, home: coqueDeTest(db)));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('bouton-aide')), findsNothing);
    expect(find.byKey(const Key('bouton-acces-rapide')), findsOneWidget);
  });

  testWidgets('module allumé : le bouton est là, au-dessus d Accès rapide sans le chevaucher ; son panneau lit l aide de l écran', (t) async {
    fenetre(t);
    await allumerModule(true);
    await t.pumpWidget(MaterialApp(theme: AgriTheme.light, home: coqueDeTest(db)));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('bouton-aide')), findsOneWidget);
    final aide = t.getRect(find.byKey(const Key('bouton-aide')));
    final acces = t.getRect(find.byKey(const Key('bouton-acces-rapide')));
    expect(aide.size, const Size(48, 48));
    expect(acces.top - aide.top, 60, reason: '48 px de diamètre + 12 px d\'écart');
    expect(aide.overlaps(acces), isFalse);
    expect(aide.right, acces.right);

    await t.tap(find.byKey(const Key('bouton-aide')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('panneau-aide')), findsOneWidget);
    final attendu = AideEcrans.pour(EcranPoste.tableauDeBord);
    expect(t.widget<Text>(find.byKey(const Key('aide-ecran-titre'))).data, attendu.titre);
    for (final puce in attendu.puces) {
      expect(find.text(puce), findsOneWidget);
    }
    expect(find.text('Aide de cet écran'.toUpperCase()), findsOneWidget);
    expect(find.byKey(const Key('aide-visite')), findsOneWidget);
    // Sans le droit de l'assistant (aucun rôle admin dans la coque de test), pas de « Relancer ».
    expect(find.byKey(const Key('aide-relancer')), findsNothing);

    await t.tap(find.byKey(const Key('aide-fermer')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('panneau-aide')), findsNothing);
  });

  /// Une page de test avec les quatre cibles de la visite, comme le socle.
  Widget page(CiblesVisite cibles, {VoidCallback? surRelancer, bool menu = true}) => MaterialApp(
    theme: AgriTheme.light,
    home: Scaffold(
      body: Stack(
        children: [
          Positioned(left: 0, top: 0, width: 200, height: 600, child: menu ? KeyedSubtree(key: cibles.menu, child: const ColoredBox(color: Colors.green)) : const SizedBox()),
          Positioned(left: 200, top: 0, right: 0, height: 60, child: KeyedSubtree(key: cibles.topbar, child: const ColoredBox(color: Colors.blue))),
          Positioned(left: 200, top: 60, right: 0, bottom: 0, child: KeyedSubtree(key: cibles.contenu, child: const ColoredBox(color: Colors.grey))),
          BoutonAide(ecran: EcranPoste.gestionStocks, cibles: cibles, surRelancer: surRelancer),
        ],
      ),
    ),
  );

  testWidgets('« Relancer l assistant de démarrage » ferme le panneau puis appelle la relance', (t) async {
    fenetre(t);
    var relances = 0;
    await t.pumpWidget(page(CiblesVisite(), surRelancer: () => relances++));
    await t.tap(find.byKey(const Key('bouton-aide')));
    await t.pumpAndSettle();

    expect(find.text(AideEcrans.panneau['relancer']!), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('aide-relancer')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('aide-relancer')));
    await t.pumpAndSettle();

    expect(relances, 1);
    expect(find.byKey(const Key('panneau-aide')), findsNothing);
  });

  testWidgets('visite guidée : 4 étapes, indicateur et points, « Passer » toujours visible, trou sur la cible, fin sobre', (t) async {
    fenetre(t);
    await t.pumpWidget(page(CiblesVisite()));
    await t.tap(find.byKey(const Key('bouton-aide')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('aide-visite')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('aide-visite')));
    await t.pumpAndSettle();

    final etapes = AideEcrans.etapesVisite;
    CustomPaint voile() => t.widget<CustomPaint>(find.byKey(const Key('visite-voile')));
    String indicateur() => t.widget<Text>(find.byKey(const Key('visite-indicateur'))).data!;

    for (var i = 0; i < 4; i++) {
      expect(indicateur(), 'Étape ${i + 1} sur 4'.toUpperCase());
      expect(t.widget<Text>(find.byKey(const Key('visite-titre'))).data, etapes[i].titre);
      expect(t.widget<Text>(find.byKey(const Key('visite-texte'))).data, etapes[i].texte);
      expect(find.byKey(const Key('visite-passer')), findsOneWidget, reason: '« Passer » visible à l\'étape ${i + 1}');
      expect(find.descendant(of: find.byKey(const Key('visite-points')), matching: find.byType(AnimatedContainer)), findsNWidgets(4));
      expect(find.byKey(const Key('visite-precedent')), i == 0 ? findsNothing : findsOneWidget);
      // Chaque étape met en valeur son élément : le voile est percé.
      expect((voile().painter as dynamic).trou, isNotNull, reason: 'étape ${i + 1}');
      expect(t.widget<Text>(find.descendant(of: find.byKey(const Key('visite-suivant')), matching: find.byType(Text))).data,
          i == 3 ? AideEcrans.libellesVisite['terminer'] : AideEcrans.libellesVisite['suivant']);
      if (i == 1) {
        // Précédent revient d'une étape, Suivant repart.
        await t.tap(find.byKey(const Key('visite-precedent')));
        await t.pumpAndSettle();
        expect(indicateur(), 'Étape 1 sur 4'.toUpperCase());
        await t.tap(find.byKey(const Key('visite-suivant')));
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const Key('visite-suivant')));
      await t.pumpAndSettle();
    }

    // Message de fin : sobre, sans voile percé ni « Passer ».
    expect(find.byKey(const Key('visite-fin-titre')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('visite-fin-texte'))).data, AideEcrans.libellesVisite['fin_texte']);
    expect((voile().painter as dynamic).trou, isNull);
    expect(find.byKey(const Key('visite-passer')), findsNothing);
    await t.tap(find.byKey(const Key('visite-fin-fermer')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('visite-guidee')), findsNothing);
  });

  testWidgets('« Passer » ferme la visite à n importe quelle étape ; une cible absente (menu replié) donne une étape sans trou', (t) async {
    fenetre(t);
    await t.pumpWidget(page(CiblesVisite(), menu: false));
    await t.tap(find.byKey(const Key('bouton-aide')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('aide-visite')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('aide-visite')));
    await t.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const Key('visite-suivant')));
      await t.pumpAndSettle();
    }
    // Étape 4 = le menu, absent de l'arbre : texte affiché, voile plein.
    expect(t.widget<Text>(find.byKey(const Key('visite-indicateur'))).data, 'Étape 4 sur 4'.toUpperCase());
    expect((t.widget<CustomPaint>(find.byKey(const Key('visite-voile'))).painter as dynamic).trou, isNull);

    await t.tap(find.byKey(const Key('visite-passer')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('visite-guidee')), findsNothing);
  });

  testWidgets('relancer l assistant : le même écran, rouvert sans « Plus tard » ni première synchronisation imposée', (t) async {
    fenetre(t);
    var fermetures = 0;
    final socle = coqueDeTest(db);
    // Le socle fournit le dépôt ; ici on rend l'écran directement avec ce que le socle lui passe.
    await t.pumpWidget(MaterialApp(
      theme: AgriTheme.light,
      home: PremierDemarrageScreen(
        depot: PremierDemarrageRepository(database: db, parametres: ParametresPoste(database: db), client: Dio()),
        engine: socle.engine,
        utilisateur: 'Admin',
        relance: true,
        onTermine: () => fermetures++,
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('Assistant de démarrage'), findsOneWidget);
    expect(find.text('Premier démarrage du poste'), findsNothing);
    expect(find.byKey(const Key('premier-plus-tard')), findsNothing);
    expect(find.byKey(const Key('premier-etape-serveur')), findsOneWidget);
    await t.tap(find.byKey(const Key('premier-fermer')));
    expect(fermetures, 1);
  });

  testWidgets('la carte « Assistant de démarrage » de Paramètres prévient le socle (le bouton d aide se rafraîchit)', (t) async {
    fenetre(t);
    var bascules = 0;
    await t.pumpWidget(MaterialApp(
      theme: AgriTheme.light,
      home: ParametresGenerauxScreen(
        depot: ParametresGenerauxRepository(database: db),
        surAssistantBascule: () => bascules++,
      ),
    ));
    await t.pumpAndSettle();
    final onglet = find.byKey(const Key('onglet-parametres-generaux-Modules Actifs'));
    await t.ensureVisible(onglet);
    await t.pumpAndSettle();
    await t.tap(onglet);
    await t.pumpAndSettle();

    expect(await ParametresGenerauxRepository(database: db).assistantActif(), isFalse, reason: 'éteint par défaut');
    await t.tap(find.byKey(const Key('bascule-module-assistant_demarrage')));
    await t.pumpAndSettle();

    expect(bascules, 1);
    expect(await ParametresGenerauxRepository(database: db).assistantActif(), isTrue);
    await t.pump(const Duration(seconds: 10));
  });
}
