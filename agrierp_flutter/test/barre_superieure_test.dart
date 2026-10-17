import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.25 — BARRE SUPÉRIEURE.
///
/// ⚠️⚠️ ELLE N'EXISTAIT PAS. La maquette porte, au-dessus de chaque écran : la
/// bascule du menu, le **fil d'Ariane**, la recherche, l'indicateur **Sync** et
/// la **cloche de notifications**. Le poste passait directement au contenu —
/// l'animalier n'avait aucun repère de sa position dans l'application.
///
/// ⚠️ **LES COMMANDES DE FENÊTRE SONT UN AJOUT ASSUMÉ.** La fenêtre est
/// désormais affichée **sans cadre système** : sans bouton réduire ni fermer,
/// l'utilisateur serait enfermé dans l'application. La maquette, étant une page
/// web, ne peut pas les avoir.
void main() {
  Future<void> afficher(
    WidgetTester tester, {
    String groupe = 'PRODUCTION ÉLEVAGE & SOINS',
    String ecran = 'Fiches Lapins',
    int enAttente = 0,
    bool menuOuvert = true,
    VoidCallback? onBascule,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarreSuperieure(
            groupe: groupe,
            ecran: ecran,
            enAttente: enAttente,
            menuOuvert: menuOuvert,
            onBasculerMenu: onBascule ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    "⚠️ le fil d'Ariane affiche « Groupe > Écran », comme la maquette",
    (tester) async {
      await afficher(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('fil-ariane'))).data,
        'PRODUCTION ÉLEVAGE & SOINS > Fiches Lapins',
      );
    },
  );

  testWidgets('les cinq éléments de la maquette sont présents', (tester) async {
    await afficher(tester);

    expect(find.byKey(const Key('bascule-menu')), findsOneWidget);
    expect(find.byKey(const Key('fil-ariane')), findsOneWidget);
    expect(find.byKey(const Key('recherche-globale')), findsOneWidget);
    expect(find.byKey(const Key('pastille-sync')), findsOneWidget);
    expect(find.byKey(const Key('cloche-notifications')), findsOneWidget);
  });

  testWidgets('la bascule du menu change d icône selon son état', (
    tester,
  ) async {
    await afficher(tester);
    expect(find.byIcon(Icons.menu_open), findsOneWidget);

    await afficher(tester, menuOuvert: false);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });

  testWidgets('la bascule prévient le socle', (tester) async {
    var bascule = 0;
    await afficher(tester, onBascule: () => bascule++);

    await tester.tap(find.byKey(const Key('bascule-menu')));
    await tester.pumpAndSettle();

    expect(bascule, 1);
  });

  /// ⚠️ LA PASTILLE COMPTE CE QUI ATTEND D'ÊTRE ENVOYÉ : c'est le seul chiffre
  /// qui dise à l'animalier si sa journée est partie.
  testWidgets('la pastille Sync annonce les enregistrements en attente', (
    tester,
  ) async {
    await afficher(tester, enAttente: 4);

    expect(find.text('Sync · 4 en attente'), findsOneWidget);
  });

  testWidgets('sans rien en attente, la pastille dit simplement « Sync »', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.text('Sync'), findsOneWidget);
  });

  /// ⚠️ LA RECHERCHE GLOBALE PARCOURT TOUS LES ÉCRANS DU WEB ; le poste n'en
  /// embarque qu'une poignée. Le champ annonce sa portée au lieu de promettre
  /// une recherche qu'il ne peut pas rendre.
  testWidgets('le champ de recherche annonce sa portée', (tester) async {
    await afficher(tester);

    expect(find.text('Recherche (application web)'), findsOneWidget);
  });

  /// ⚠️ AUCUN COMPTEUR SUR LA CLOCHE : les notifications vivent côté serveur.
  /// Un « 0 » ferait croire à une boîte vide alors qu'elle est inaccessible.
  testWidgets('la cloche explique où vivent les notifications', (tester) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('cloche-notifications')));
    await tester.pumpAndSettle();

    expect(find.textContaining("l'application web"), findsOneWidget);
  });

  // ── Les commandes de fenêtre ───────────────────────────────────────────

  testWidgets('⚠️ réduire et fermer sont offerts, faute de cadre système', (
    tester,
  ) async {
    await afficher(tester);

    expect(find.byKey(const Key('fenetre-reduire')), findsOneWidget);
    expect(find.byKey(const Key('fenetre-fermer')), findsOneWidget);
  });

  /// ⚠️⚠️ FERMER SE CONFIRME QUAND UNE SAISIE ATTEND ENCORE. Quitter ne perd
  /// rien — les journées restent en base locale — mais l'animalier doit le
  /// savoir, sans quoi il croira son travail parti.
  testWidgets('fermer avec des saisies en attente demande confirmation', (
    tester,
  ) async {
    await afficher(tester, enAttente: 3);

    await tester.tap(find.byKey(const Key('fenetre-fermer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modale-fermeture')), findsOneWidget);
    expect(find.textContaining('3 enregistrement(s)'), findsOneWidget);
    expect(find.textContaining('restent enregistrés'), findsOneWidget);
  });

  testWidgets('sans rien en attente, fermer ne demande rien', (tester) async {
    await afficher(tester);

    await tester.tap(find.byKey(const Key('fenetre-fermer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modale-fermeture')), findsNothing);
  });
}
