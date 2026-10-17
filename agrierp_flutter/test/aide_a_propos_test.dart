import 'dart:io';

import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/aide/aide_a_propos_repository.dart';
import 'package:agrierp/features/aide/aide_a_propos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';
import 'inventaire_maquette.g.dart';

/// Ticket F0.60 — AIDE & À PROPOS (`aide-a-propos.html`).
///
/// ⚠️⚠️ **PAGE DE DOCUMENTATION** : aucune donnée, aucun tirage, identique hors
/// ligne. Deux décisions de contenu y sont verrouillées : la présentation des
/// TROIS structures (Laravel l'emporte sur le prototype) et les réponses de la
/// FAQ, écrites pour le poste (décision du commanditaire).
void main() {
  Future<void> afficher(
    WidgetTester tester, {
    void Function(EcranPoste)? onOuvrir,
    bool Function(EcranPoste)? peutOuvrir,
    VoidCallback? onContact,
    Size taille = const Size(1600, 3000),
  }) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: AideAProposScreen(
          onOuvrir: onOuvrir ?? (_) {},
          peutOuvrir: peutOuvrir ?? (_) => true,
          onContact: onContact,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('contenu', () {
    test('les douze modules, dans l\'ordre de la maquette', () {
      expect(AideAProposRepository.modules.map((m) => m.titre), [
        'Tableau de Bord',
        'Gestion Élevage',
        'Soins et Vaccins',
        'Ventes & Devis',
        'Clients et Créances',
        'Achats & Commandes',
        'Gestion Stocks',
        'Facturation & MeCeF',
        'Personnel & Stages',
        'Comptabilité',
        'Administration',
        'Rapports & Exports',
      ]);
    });

    test('⚠️ chaque module ouvre un écran DIFFÉRENT du poste', () {
      final ecrans = AideAProposRepository.modules.map((m) => m.ecran).toList();
      expect(ecrans.toSet(), hasLength(12));
    });

    test(
      '⚠️ les sept questions sont celles que la maquette extraite relève',
      () {
        final inventaire = inventaireMaquette['aide-a-propos.html']!;

        for (final q in AideAProposRepository.questions) {
          expect(inventaire, contains(q.question), reason: q.question);
        }
        expect(AideAProposRepository.questions, hasLength(7));
      },
    );

    test('⚠️⚠️ la présentation nomme les TROIS structures (PAEB, FAGUEZ, '
        'MASSENON)', () {
      const t = AideAProposRepository.descriptionLogiciel;

      expect(t, contains("Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB)"));
      expect(t, contains('Cabinet FAGUEZ SARL'));
      expect(t, contains('Dr MASSENON Rhodes'));
      expect(t, contains('Docteur en Génie Logiciel et IA'));
      // Et non la formulation à deux structures du prototype.
      expect(t, isNot(contains('en partenariat avec FAGUEZ')));
    });

    test('⚠️ la version affichée est celle du pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final lue = RegExp(
        r'^version:\s*([\d.]+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1);

      expect(AideAProposRepository.version, lue);
    });

    test(
      '⚠️⚠️ toute réponse qui renvoie à un écran NON PORTÉ dit que c\'est le '
      'web qui agit',
      () {
        // Écrans que le poste n'a pas : l'utilisateur ne peut pas les suivre.
        const nonPortes = ['Enregistrer Sujets', 'Clôture', 'Attestations)'];

        for (final q in AideAProposRepository.questions) {
          if (nonPortes.any(q.reponse.contains)) {
            expect(
              q.reponse,
              contains('application web'),
              reason:
                  'Sans cela, « ${q.question} » enverrait chercher un menu '
                  'absent du poste.',
            );
          }
        }
      },
    );

    test('⚠️ l\'alerte d\'autonomie suit Laravel : 3 jours, critique à 1', () {
      final r = AideAProposRepository.questions
          .firstWhere((q) => q.question.contains('alerte de stock'))
          .reponse;

      expect(r, contains('3 jours ou moins'));
      expect(r, contains('critique à 1 jour ou moins'));
      expect(r, contains('Centre de Notifications'));
    });

    test('⚠️ les réponses du poste ne promettent rien qu\'il ne fait pas', () {
      final toutes = AideAProposRepository.questions
          .map((q) => q.reponse)
          .join(' ');

      // La caisse ne vend qu'au Client Anonyme ; le poste ne crée pas de bande
      // et ne génère pas d'attestation.
      expect(toutes, contains('Client Anonyme'));
      expect(toutes, contains('ne se crée pas sur le poste'));
      expect(toutes, contains('ne génère pas'));
      expect(toutes, isNot(contains('sélectionnez')));
    });

    test('⚠️ la dernière réponse ne promet pas de ruban d\'accès rapide', () {
      final derniere = AideAProposRepository.questions.last.reponse;

      expect(derniere, isNot(contains('ruban')));
      expect(derniere, contains('icône de menu'));
    });
  });

  group('recherche', () {
    test('sans terme, tout est retenu', () {
      expect(AideAProposRepository.rechercher(''), hasLength(7));
      expect(AideAProposRepository.rechercher('   '), hasLength(7));
    });

    test('⚠️ elle porte sur la question ET sur la réponse', () {
      // « autonomie » n'est que dans la réponse de la question sur l'alerte.
      final l = AideAProposRepository.rechercher('autonomie');
      expect(l.single.question, contains('alerte de stock'));
    });

    test('⚠️ la casse est ignorée, accents de majuscule compris', () {
      // `LIKE` de SQLite échouerait ; la comparaison se fait en Dart.
      expect(AideAProposRepository.rechercher('ÉLEVAGE'), isNotEmpty);
      expect(
        AideAProposRepository.rechercher('élevage'),
        AideAProposRepository.rechercher('ÉLEVAGE'),
      );
    });

    test('aucun résultat', () {
      expect(AideAProposRepository.rechercher('zzzz'), isEmpty);
    });
  });

  group('écran', () {
    testWidgets('titre, sous-titre, présentation et version', (tester) async {
      await afficher(tester);

      expect(find.text('Aide & À Propos'), findsOneWidget);
      expect(
        find.text(
          'Documentation complète, guide des modules et foire aux questions.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('aide-presentation')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('aide-version')))
            .textSpan!
            .toPlainText(),
        'AgriERP v1.0.0',
      );
      expect(find.text('MODULES DU LOGICIEL'), findsOneWidget);
      expect(find.text('FOIRE AUX QUESTIONS'), findsOneWidget);
    });

    testWidgets('aucune carte d\'indicateur, comme la maquette', (
      tester,
    ) async {
      await afficher(tester);

      expect(
        find.byType(CarteKpi),
        findsNWidgets(cartesAttendues('aide-a-propos.html')),
      );
    });

    testWidgets('douze cartes de module, un clic ouvre l\'écran visé', (
      tester,
    ) async {
      EcranPoste? ouvert;
      await afficher(tester, onOuvrir: (e) => ouvert = e);

      for (var i = 0; i < 12; i++) {
        expect(find.byKey(Key('aide-module-$i')), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('aide-module-6')));
      await tester.pumpAndSettle();

      expect(ouvert, EcranPoste.gestionStocks);
    });

    testWidgets('⚠️ un module que le rôle ne peut pas ouvrir est inerte', (
      tester,
    ) async {
      EcranPoste? ouvert;
      await afficher(
        tester,
        onOuvrir: (e) => ouvert = e,
        peutOuvrir: (e) => e != EcranPoste.comptabilite,
      );

      // Comptabilité = 10ᵉ carte (index 9).
      await tester.tap(
        find.byKey(const Key('aide-module-9')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(ouvert, isNull);

      // Les autres restent actives.
      await tester.tap(find.byKey(const Key('aide-module-0')));
      await tester.pumpAndSettle();
      expect(ouvert, EcranPoste.tableauDeBord);
    });

    for (final (largeur, colonnes) in [(1400.0, 3), (800.0, 2), (500.0, 1)]) {
      testWidgets('$colonnes colonne(s) à $largeur px', (tester) async {
        await afficher(tester, taille: Size(largeur, 4000));

        final x = <double>{
          for (var i = 0; i < 12; i++)
            tester.getTopLeft(find.byKey(Key('aide-module-$i'))).dx,
        };
        expect(x, hasLength(colonnes));
      });
    }

    testWidgets('⚠️ les questions s\'ouvrent INDÉPENDAMMENT', (tester) async {
      await afficher(tester);

      expect(find.byKey(const Key('faq-reponse-0')), findsNothing);
      await tester.tap(find.byKey(const Key('faq-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('faq-2')));
      await tester.pumpAndSettle();

      // Ouvrir la troisième n'a PAS refermé la première.
      expect(find.byKey(const Key('faq-reponse-0')), findsOneWidget);
      expect(find.byKey(const Key('faq-reponse-2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('faq-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('faq-reponse-0')), findsNothing);
      expect(find.byKey(const Key('faq-reponse-2')), findsOneWidget);
    });

    testWidgets(
      'la recherche filtre, et garde l\'état ouvert des survivantes',
      (tester) async {
        await afficher(tester);
        await tester.tap(find.byKey(const Key('faq-2')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('faq-recherche')),
          'autonomie',
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('faq-2')), findsOneWidget);
        expect(find.byKey(const Key('faq-0')), findsNothing);
        expect(find.byKey(const Key('faq-reponse-2')), findsOneWidget);
      },
    );

    testWidgets('aucun résultat : le message de la maquette', (tester) async {
      await afficher(tester);

      await tester.enterText(find.byKey(const Key('faq-recherche')), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text('Aucun résultat pour cette recherche.'), findsOneWidget);
    });

    testWidgets(
      '⚠️ pas de lien « Contactez l\'éditeur » tant que son écran n\'existe pas',
      (tester) async {
        await afficher(tester);

        expect(find.byKey(const Key('aide-contact')), findsNothing);
      },
    );

    testWidgets('avec son écran, le lien est rendu et fonctionne', (
      tester,
    ) async {
      var ouvert = 0;
      await afficher(tester, onContact: () => ouvert++);

      await tester.tap(find.byKey(const Key('aide-contact')));
      await tester.pumpAndSettle();

      expect(ouvert, 1);
      expect(
        find.text("Vous ne trouvez pas de réponse ? Contactez l'éditeur"),
        findsOneWidget,
      );
    });
  });

  group('menu du compte', () {
    Future<void> barre(
      WidgetTester tester, {
      VoidCallback? onMonProfil,
      VoidCallback? onAide,
    }) async {
      tester.view.physicalSize = const Size(1600, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarreSuperieure(
              groupe: '',
              ecran: 'Aide & À Propos',
              enAttente: 0,
              onBasculerMenu: () {},
              onMonProfil: onMonProfil,
              onAide: onAide,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('« Aide & À Propos » suit « Mon Profil », dans l\'ordre de la '
        'maquette', (tester) async {
      var aide = 0;
      await barre(tester, onMonProfil: () {}, onAide: () => aide++);

      await tester.tap(find.byKey(const Key('menu-compte')));
      await tester.pumpAndSettle();

      final profil = tester.getTopLeft(
        find.byKey(const Key('menu-compte-profil')),
      );
      final entree = tester.getTopLeft(
        find.byKey(const Key('menu-compte-aide')),
      );
      expect(entree.dy, greaterThan(profil.dy));

      await tester.tap(find.byKey(const Key('menu-compte-aide')));
      await tester.pumpAndSettle();
      expect(aide, 1);
    });

    testWidgets(
      'chaque entrée est indépendante : seule l\'aide, pas le profil',
      (tester) async {
        await barre(tester, onAide: () {});

        await tester.tap(find.byKey(const Key('menu-compte')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('menu-compte-profil')), findsNothing);
        expect(find.byKey(const Key('menu-compte-aide')), findsOneWidget);
      },
    );
  });

  group('RBAC', () {
    test('⚠️ ouvert à tout rôle — extension à confirmer par le client', () {
      for (final role in ['admin', 'caissier', 'animalier', 'comptable', 'x']) {
        expect(
          PermissionsPoste.autorise(role, EcranPoste.aideEtAPropos),
          isTrue,
          reason: role,
        );
      }
    });

    test('la carte du prototype reste recopiée sans la page', () {
      final listes = PermissionsPoste.carte.values
          .whereType<List<String>>()
          .expand((l) => l);
      expect(listes, isNot(contains('aide-a-propos.html')));
    });
  });
}
