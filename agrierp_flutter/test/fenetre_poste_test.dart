import 'dart:io';

import 'package:agrierp/core/fenetre/fenetre_poste.dart';
import 'package:agrierp/core/theme/symboles_agri.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket ENV1 (demande 5) — LA FENÊTRE DU POSTE OCCUPE LA ZONE DE TRAVAIL, PAS LE MONITEUR.
///
/// Défaut constaté chez le client : la fenêtre est sans cadre (`WS_POPUP`) et était « maximisée » par
/// `SW_SHOWMAXIMIZED`, qui la fait couvrir TOUT l'écran, barre des tâches de Windows comprise.
///
/// ⚠️⚠️ CE QUE CES TESTS PROUVENT ET NE PROUVENT PAS.
///  - Le CANAL `agrierp/fenetre` est SIMULÉ ici par `NativeSimule`, qui rejoue le contrat attendu du côté Windows
///    (agrandir = zone de travail, jamais le moniteur entier). Ils prouvent le côté Dart : bons appels, état
///    relu du natif, aucun calcul de géométrie en Dart, aucune panne en l'absence de natif.
///  - Le comportement NATIF (`win32_window.cpp`) n'a PAS pu être exécuté dans l'environnement de développement
///    (Linux, sans Windows). Les tests de lecture du source verrouillent les appels qui lui donnent ce
///    comportement (`rcWork`, `MonitorFromWindow`, messages de changement de résolution) et l'absence de
///    `SW_SHOWMAXIMIZED`, mais seul un essai sur un poste Windows prouve le rendu.
const _canal = MethodChannel('agrierp/fenetre');

/// Le natif tel que le contrat le décrit : un moniteur 1920x1080, une barre des tâches qui retire `barre` pixels
/// d'un côté, une fenêtre restaurée de 1280x720.
class NativeSimule {
  NativeSimule({this.moniteur = const Rect.fromLTWH(0, 0, 1920, 1080), this.zoneDeTravail = const Rect.fromLTWH(0, 0, 1920, 1040)});

  Rect moniteur;
  Rect zoneDeTravail;
  Rect fenetre = const Rect.fromLTWH(10, 10, 1280, 720);
  Rect restauration = const Rect.fromLTWH(10, 10, 1280, 720);
  bool agrandie = false;
  final appels = <String>[];

  Map<String, Object> get etat => {
    'agrandie': agrandie,
    'x': zoneDeTravail.left.toInt(),
    'y': zoneDeTravail.top.toInt(),
    'largeur': zoneDeTravail.width.toInt(),
    'hauteur': zoneDeTravail.height.toInt(),
  };

  Future<Object?> appel(MethodCall c) async {
    appels.add(c.method);
    switch (c.method) {
      case 'etat':
        return etat;
      case 'basculerAgrandissement':
        if (agrandie) {
          agrandie = false;
          fenetre = restauration;
        } else {
          restauration = fenetre;
          agrandie = true;
          fenetre = zoneDeTravail; // JAMAIS `moniteur`
        }
        return etat;
      case 'deplacer':
      case 'reduire':
      case 'fermer':
        return null;
      default:
        throw MissingPluginException('méthode inconnue du natif : ${c.method}');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NativeSimule natif;

  void brancher(NativeSimule n) {
    natif = n;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_canal, n.appel);
  }

  setUp(() {
    FenetrePoste.reinitialiserPourTest();
    brancher(NativeSimule());
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_canal, null);
  });

  group('contrat « agrandir = zone de travail »', () {
    test("l'état lu au natif donne la zone de travail, plus petite que le moniteur (barre des tâches visible)", () async {
      final etat = await FenetrePoste.etat();

      expect(etat, isNotNull);
      expect(etat!.zone, const Rect.fromLTWH(0, 0, 1920, 1040));
      expect(etat.zone!.height, lessThan(natif.moniteur.height), reason: 'la barre des tâches (40 px) reste libre');
      expect(etat.agrandie, isFalse);
      expect(FenetrePoste.agrandie.value, isFalse);
    });

    test('agrandir place la fenêtre sur la zone de travail, jamais sur le moniteur entier', () async {
      final etat = await FenetrePoste.basculerAgrandissement();

      expect(etat!.agrandie, isTrue);
      expect(natif.fenetre, natif.zoneDeTravail);
      expect(natif.fenetre, isNot(natif.moniteur));
      expect(etat.zone, natif.zoneDeTravail);
      expect(FenetrePoste.agrandie.value, isTrue);
    });

    test('restaurer rend la taille d\'avant, puis agrandir à nouveau retrouve la zone de travail', () async {
      await FenetrePoste.basculerAgrandissement();
      final restaure = await FenetrePoste.basculerAgrandissement();

      expect(restaure!.agrandie, isFalse);
      expect(natif.fenetre, const Rect.fromLTWH(10, 10, 1280, 720));
      expect(FenetrePoste.agrandie.value, isFalse);

      await FenetrePoste.basculerAgrandissement();
      expect(natif.fenetre, natif.zoneDeTravail);
    });

    test('barre des tâches à gauche, en haut ou plus haute : le Dart ne calcule rien, il reprend la zone du natif', () async {
      for (final zone in const [
        Rect.fromLTWH(60, 0, 1860, 1080), // barre à gauche
        Rect.fromLTWH(0, 48, 1920, 1032), // barre en haut
        Rect.fromLTWH(0, 0, 1920, 960), // barre agrandie à 120 px
        Rect.fromLTWH(0, 0, 1920, 1080), // barre masquée automatiquement
      ]) {
        brancher(NativeSimule(zoneDeTravail: zone));
        final etat = await FenetrePoste.basculerAgrandissement();
        expect(etat!.zone, zone);
        expect(natif.fenetre, zone);
      }
    });

    test("changement de résolution : la zone relue au natif est la nouvelle", () async {
      await FenetrePoste.basculerAgrandissement();
      natif.moniteur = const Rect.fromLTWH(0, 0, 1366, 768);
      natif.zoneDeTravail = const Rect.fromLTWH(0, 0, 1366, 728);
      natif.fenetre = natif.zoneDeTravail; // le natif s'est recalé (WM_DISPLAYCHANGE)

      final etat = await FenetrePoste.etat();

      expect(etat!.zone, const Rect.fromLTWH(0, 0, 1366, 728));
      expect(etat.agrandie, isTrue);
    });

    test("aucune commande de plein écran n'existe : seules les méthodes du contrat sont appelées", () async {
      await FenetrePoste.etat();
      await FenetrePoste.basculerAgrandissement();
      await FenetrePoste.deplacer();
      await FenetrePoste.reduire();
      await FenetrePoste.fermer();

      expect(natif.appels, ['etat', 'basculerAgrandissement', 'deplacer', 'reduire', 'fermer']);
    });
  });

  group('sans côté natif (tests, aperçu)', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_canal, null);
    });

    test("aucune commande ne lève d'exception et l'état reste celui d'origine", () async {
      expect(await FenetrePoste.etat(), isNull);
      expect(await FenetrePoste.basculerAgrandissement(), isNull);
      await FenetrePoste.deplacer();
      await FenetrePoste.reduire();
      await FenetrePoste.fermer();
      expect(FenetrePoste.agrandie.value, isTrue, reason: "la fenêtre s'ouvre agrandie");
    });

    test("une réponse malformée est ignorée, jamais un plantage", () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_canal, (_) async => 'pas un dictionnaire');
      expect(await FenetrePoste.etat(), isNull);
    });
  });

  group('barre supérieure : commandes de fenêtre', () {
    Future<void> afficher(WidgetTester tester, {int enAttente = 0}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarreSuperieure(groupe: 'PILOTAGE', ecran: 'Tableau de Bord', enAttente: enAttente, onBasculerMenu: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets("réduire, agrandir et fermer sont dans cet ordre, à l'extrémité droite de la barre", (tester) async {
      await afficher(tester);

      final reduire = tester.getCenter(find.byKey(const Key('fenetre-reduire'))).dx;
      final agrandir = tester.getCenter(find.byKey(const Key('fenetre-agrandir'))).dx;
      final fermer = tester.getCenter(find.byKey(const Key('fenetre-fermer'))).dx;
      expect(reduire, lessThan(agrandir));
      expect(agrandir, lessThan(fermer));
      expect(fermer, greaterThan(tester.getCenter(find.byKey(const Key('cloche-notifications'))).dx));
    });

    testWidgets("le bouton agrandir appelle le natif et change d'icône : « Agrandir » puis « Restaurer »", (tester) async {
      await afficher(tester);
      IconData icone() => tester.widget<Icon>(find.descendant(of: find.byKey(const Key('fenetre-agrandir')), matching: find.byType(Icon))).icon!;
      String info() => tester.widget<Tooltip>(find.descendant(of: find.byKey(const Key('fenetre-agrandir')), matching: find.byType(Tooltip))).message!;

      expect(info(), 'Agrandir');
      expect(icone(), SymbolesAgri.crop_square);

      await tester.tap(find.byKey(const Key('fenetre-agrandir')));
      await tester.pumpAndSettle();

      expect(natif.appels, contains('basculerAgrandissement'));
      expect(natif.fenetre, natif.zoneDeTravail);
      expect(info(), 'Restaurer');
      expect(icone(), SymbolesAgri.filter_none);

      await tester.tap(find.byKey(const Key('fenetre-agrandir')));
      await tester.pumpAndSettle();
      expect(info(), 'Agrandir');
    });

    testWidgets("la barre relit l'état du natif à son affichage : une fenêtre déjà agrandie montre « Restaurer »", (tester) async {
      natif.agrandie = true;
      await afficher(tester);

      expect(natif.appels, contains('etat'));
      expect(tester.widget<Tooltip>(find.descendant(of: find.byKey(const Key('fenetre-agrandir')), matching: find.byType(Tooltip))).message, 'Restaurer');
    });

    testWidgets("glisser la barre sur sa zone libre démarre le déplacement natif", (tester) async {
      await afficher(tester);

      final zone = find.byKey(const Key('fenetre-zone-glissement'));
      expect(zone, findsOneWidget);
      await tester.drag(zone, const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 500)); // délai du double-clic

      expect(natif.appels.where((a) => a == 'deplacer'), hasLength(1));
    });

    testWidgets("le fil d'Ariane se glisse aussi (c'est de la barre, pas un contrôle)", (tester) async {
      await afficher(tester);

      await tester.drag(find.byKey(const Key('fil-ariane')), const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 500));

      expect(natif.appels, contains('deplacer'));
    });

    testWidgets("double-clic sur la barre : agrandit, puis restaure — toujours via le natif", (tester) async {
      await afficher(tester);
      final zone = find.byKey(const Key('fenetre-zone-glissement'));

      await tester.tap(zone);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(zone);
      await tester.pumpAndSettle();

      expect(natif.agrandie, isTrue);
      expect(natif.fenetre, natif.zoneDeTravail);

      await tester.tap(zone);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(zone);
      await tester.pumpAndSettle();

      expect(natif.agrandie, isFalse);
    });

    testWidgets("un simple clic sur la barre ne fait rien", (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('fenetre-zone-glissement')));
      await tester.pumpAndSettle();

      expect(natif.appels.where((a) => a != 'etat'), isEmpty);
    });

    testWidgets("la bascule du menu et le bouton Synchroniser ne déclenchent ni déplacement ni agrandissement", (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('bascule-menu')));
      await tester.tap(find.byKey(const Key('bouton-synchroniser')));
      await tester.pumpAndSettle();

      expect(natif.appels.where((a) => a != 'etat'), isEmpty);
    });

    testWidgets("réduire appelle le natif", (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('fenetre-reduire')));
      await tester.pump();
      expect(natif.appels, contains('reduire'));
    });

    testWidgets("fermer sans rien en attente ferme tout de suite (la confirmation reste pour les envois en attente)", (tester) async {
      await afficher(tester);
      await tester.tap(find.byKey(const Key('fenetre-fermer')));
      await tester.pump();
      expect(natif.appels, contains('fermer'));
    });

    testWidgets("fermer avec des enregistrements en attente demande confirmation et ne ferme pas avant", (tester) async {
      await afficher(tester, enAttente: 3);
      await tester.tap(find.byKey(const Key('fenetre-fermer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-fermeture')), findsOneWidget);
      expect(natif.appels, isNot(contains('fermer')));

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(natif.appels, isNot(contains('fermer')));
    });
  });

  group('lecture du source natif (Windows, non exécutable ici)', () {
    final fenetreCpp = File('windows/runner/win32_window.cpp').readAsStringSync();
    final fenetreFlutterCpp = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final mainCpp = File('windows/runner/main.cpp').readAsStringSync();

    /// Le code seul : un garde-fou qui se déclenche sur le commentaire qui explique pourquoi on ne fait PLUS
    /// quelque chose serait ingérable.
    String code(String source) => source.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

    test("aucun agrandissement par le système : SW_SHOWMAXIMIZED / SW_MAXIMIZE couvriraient la barre des tâches", () {
      for (final source in [fenetreCpp, fenetreFlutterCpp, mainCpp]) {
        expect(code(source), isNot(contains('SW_SHOWMAXIMIZED')));
        expect(code(source), isNot(contains('SW_MAXIMIZE')));
        expect(code(source), isNot(contains('SW_SHOWFULLSCREEN')));
        expect(code(source), isNot(contains('SC_MAXIMIZE')));
      }
    });

    test("la zone de travail vient du moniteur qui porte la fenêtre : MonitorFromWindow + GetMonitorInfo + rcWork", () {
      final c = code(fenetreCpp);
      expect(c, contains('MonitorFromWindow'));
      expect(c, contains('GetMonitorInfo'));
      expect(c, contains('rcWork'));
      expect(c, contains('SPI_GETWORKAREA'), reason: 'repli si le moniteur ne répond pas');
    });

    test("la fenêtre se recale quand la zone change : résolution, barre des tâches, échelle, sortie de réduction", () {
      final c = code(fenetreCpp);
      expect(c, contains('WM_DISPLAYCHANGE'));
      expect(c, contains('WM_SETTINGCHANGE'));
      expect(c, contains('SPI_SETWORKAREA'));
      expect(c, contains('WM_DPICHANGED'));
      expect(c, contains('SIZE_RESTORED'));
      expect(c, contains('FitToWorkArea'));
      expect(code(fenetreFlutterCpp), contains('OnWorkAreaMessage(message, wparam)'));
    });

    test("un agrandissement par le système (touche Windows) reste dans la zone : WM_GETMINMAXINFO, taille minimale", () {
      final c = code(fenetreCpp);
      expect(c, contains('ptMaxPosition'));
      expect(c, contains('ptMaxSize'));
      expect(c, contains('ptMinTrackSize'));
      expect(code(fenetreFlutterCpp), contains('WM_GETMINMAXINFO'));
    });

    test("la fenêtre s'ouvre agrandie sur la zone de travail, puis s'affiche", () {
      final c = code(fenetreFlutterCpp);
      expect(c, contains('MaximizeToWorkArea();'));
      expect(c, contains('Show();'));
    });

    test("le canal natif porte les cinq commandes du contrat", () {
      final c = code(fenetreFlutterCpp);
      for (final m in ['reduire', 'fermer', 'etat', 'basculerAgrandissement', 'deplacer']) {
        expect(c, contains('"$m"'), reason: 'méthode $m');
      }
    });

    test("la fenêtre reste sans cadre : WS_POPUP, que la barre supérieure remplace (réduire, agrandir, fermer)", () {
      expect(code(fenetreCpp), contains('WS_POPUP'));
      expect(File('lib/core/widgets/barre_superieure.dart').readAsStringSync(), contains("Key('fenetre-agrandir')"));
    });

    test("la zone de travail NE se déduit PAS de GetSystemMetrics(SM_CYSCREEN) : ce serait l'écran entier", () {
      expect(code(fenetreCpp), isNot(contains('SM_CYSCREEN')));
      expect(code(fenetreCpp), isNot(contains('SM_CXSCREEN')));
    });
  });
}
