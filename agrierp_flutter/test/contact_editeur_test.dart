import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/contact/contact_editeur_repository.dart';
import 'package:agrierp/features/contact/contact_editeur_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.62 — CONTACTEZ L'ÉDITEUR (`contact-editeur.html`).
///
/// ⚠️⚠️ **« ENVOYÉ » NE S'AFFICHE QUE SUR RÉPONSE DU SERVEUR, ET UN TEXTE REFUSÉ
/// RESTE DANS LE FORMULAIRE.** Le serveur envoie un e-mail réel ; hors ligne,
/// l'envoi est refusé, jamais affirmé, jamais perdu.
class _ServeurFeint extends Interceptor {
  _ServeurFeint({this.code = 200, this.corps, this.horsLigne = false});

  final int code;
  final Object? corps;
  final bool horsLigne;

  String? chemin;
  Map<String, dynamic>? recu;
  var appels = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    appels++;
    chemin = options.path;
    recu = options.data as Map<String, dynamic>?;

    if (horsLigne) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
    } else if (code >= 400) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: code,
            data: corps,
          ),
        ),
      );
    } else {
      handler.resolve(
        Response<dynamic>(requestOptions: options, statusCode: 200),
      );
    }
  }
}

void main() {
  ContactEditeurRepository depot(_ServeurFeint? serveur) {
    if (serveur == null) return const ContactEditeurRepository();
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
      ..interceptors.add(serveur);
    return ContactEditeurRepository(client: ClientContact(client));
  }

  group('client HTTP', () {
    test(
      'un message part vers /api/contact avec les clés du serveur',
      () async {
        final s = _ServeurFeint();

        await depot(s).envoyerMessage(objet: 'Question', message: 'Bonjour');

        expect(s.chemin, '/api/contact');
        expect(s.recu, {
          'type': 'message',
          'subject': 'Question',
          'message': 'Bonjour',
        });
      },
    );

    test('⚠️ un bug n\'envoie « steps » que s\'il est rempli', () async {
      final s = _ServeurFeint();

      await depot(
        s,
      ).signalerBug(module: 'Stocks', description: 'd', etapes: '');
      expect(s.recu!.containsKey('steps'), isFalse);
      expect(s.recu!['type'], 'bug');
      expect(s.recu!['module'], 'Stocks');

      await depot(
        s,
      ).signalerBug(module: 'Stocks', description: 'd', etapes: '1. Ajuster');
      expect(s.recu!['steps'], '1. Ajuster');
    });

    test(
      'un 422 est rendu PAR CHAMP, sous le nom que l\'écran emploie',
      () async {
        final r = depot(
          _ServeurFeint(
            code: 422,
            corps: {
              'errors': {
                'subject': ['Objet manquant.'],
                'steps': ['Trop long.'],
              },
            },
          ),
        );

        await expectLater(
          r.envoyerMessage(objet: 'x', message: 'y'),
          throwsA(
            isA<EchecContact>().having((e) => e.champs, 'champs', {
              'objet': 'Objet manquant.',
              'etapes': 'Trop long.',
            }),
          ),
        );
      },
    );

    test('401, 429 et 502 disent chacun la bonne chose', () async {
      Future<String> message(int code, [Object? corps]) async {
        try {
          await depot(
            _ServeurFeint(code: code, corps: corps),
          ).envoyerMessage(objet: 'x', message: 'y');
        } on EchecContact catch (e) {
          return e.message;
        }
        return '';
      }

      expect(await message(401), contains('Session expirée'));
      expect(await message(429), contains('Trop d\'envois'));
      // Le serveur dit lui-même pourquoi l'e-mail n'est pas parti.
      expect(
        await message(502, {'message': 'Conservez votre texte et réessayez.'}),
        'Conservez votre texte et réessayez.',
      );
    });

    test(
      '⚠️ hors ligne : la phrase promet que le texte est conservé',
      () async {
        await expectLater(
          depot(
            _ServeurFeint(horsLigne: true),
          ).envoyerMessage(objet: 'x', message: 'y'),
          throwsA(
            isA<EchecContact>().having(
              (e) => e.message,
              'message',
              allOf(contains('nécessite le réseau'), contains('conservé')),
            ),
          ),
        );
      },
    );

    test('sans session, rien n\'est tenté', () async {
      await expectLater(
        depot(null).envoyerMessage(objet: 'x', message: 'y'),
        throwsA(
          isA<EchecContact>().having(
            (e) => e.message,
            'message',
            contains('Aucune session'),
          ),
        ),
      );
    });
  });

  group('règles de saisie', () {
    test('message : objet et message obligatoires', () {
      expect(ContactEditeurRepository.validerMessage(objet: ' ', message: ''), {
        'objet': 'Ce champ est obligatoire.',
        'message': 'Ce champ est obligatoire.',
      });
      expect(
        ContactEditeurRepository.validerMessage(objet: 'o', message: 'm'),
        isEmpty,
      );
    });

    test('bug : module et description obligatoires, étapes facultatives', () {
      expect(
        ContactEditeurRepository.validerBug(module: '', description: ''),
        hasLength(2),
      );
      expect(
        ContactEditeurRepository.validerBug(module: 'Autre', description: 'd'),
        isEmpty,
      );
    });

    test('les six modules, dans l\'ordre de la maquette', () {
      expect(ContactEditeurRepository.modules, [
        'Élevage & Soins',
        'Ventes & POS',
        'Stocks',
        'Comptabilité',
        'Ressources Humaines',
        'Autre',
      ]);
    });

    test('⚠️⚠️ les coordonnées sont celles de Laravel, pas des « XX XX »', () {
      expect(ContactEditeurRepository.editeurNom, 'Dr MASSENON Rhodes');
      for (final t in ContactEditeurRepository.editeurTelephones) {
        expect(t, isNot(contains('XX')));
        expect(t, startsWith('+229'));
      }
      expect(ContactEditeurRepository.editeurEmails, hasLength(2));
      expect(
        ContactEditeurRepository.editeurEmails,
        isNot(contains('support@faguez-sarl.bj')),
      );
    });
  });

  group('écran', () {
    late BrouillonContact brouillon;

    setUp(() => brouillon = BrouillonContact());
    tearDown(() => brouillon.dispose());

    Future<void> afficher(
      WidgetTester tester, {
      ContactEditeurRepository? d,
      VoidCallback? onAide,
      Size taille = const Size(1600, 2400),
      BrouillonContact? avec,
    }) async {
      tester.view.physicalSize = taille;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ContactEditeurScreen(
            depot: d ?? depot(_ServeurFeint()),
            brouillon: avec ?? brouillon,
            onAide: onAide,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> saisirMessage(
      WidgetTester tester, {
      String objet = '',
      String message = '',
    }) async {
      await tester.enterText(find.byKey(const Key('contact-objet')), objet);
      await tester.enterText(find.byKey(const Key('contact-message')), message);
      await tester.ensureVisible(find.byKey(const Key('contact-envoyer')));
      await tester.tap(find.byKey(const Key('contact-envoyer')));
      await tester.pumpAndSettle();
    }

    Future<void> ouvrirBug(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('onglet-contact-Signaler un Bug')));
      await tester.pumpAndSettle();
    }

    String contenu(WidgetTester tester, String cle) =>
        tester.widget<TextField>(find.byKey(Key(cle))).controller!.text;

    testWidgets('titre, sous-titre et aucune carte d\'indicateur', (
      tester,
    ) async {
      await afficher(tester);

      expect(find.text("Contactez l'Éditeur"), findsOneWidget);
      expect(
        find.text(
          "Assistance technique, suggestions et signalement d'anomalies pour "
          'AgriERP.',
        ),
        findsOneWidget,
      );
      expect(
        find.byType(CarteKpi),
        findsNWidgets(cartesAttendues('contact-editeur.html')),
      );
    });

    testWidgets('deux onglets dans l\'ordre de la maquette', (tester) async {
      await afficher(tester);

      final x1 = tester.getTopLeft(
        find.byKey(const Key('onglet-contact-Envoyer un Message')),
      );
      final x2 = tester.getTopLeft(
        find.byKey(const Key('onglet-contact-Signaler un Bug')),
      );
      expect(x2.dx, greaterThan(x1.dx));
    });

    testWidgets('onglet message : deux champs et le bouton de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      expect(find.text('OBJET *'), findsOneWidget);
      expect(find.text('MESSAGE *'), findsOneWidget);
      expect(find.text('Envoyer le Message'), findsOneWidget);
      expect(
        find.text('ex : Question sur le module Comptabilité'),
        findsOneWidget,
      );
    });

    testWidgets('champs vides : deux « obligatoire », rien n\'est envoyé', (
      tester,
    ) async {
      final s = _ServeurFeint();
      await afficher(tester, d: depot(s));
      await saisirMessage(tester);

      expect(find.text('Ce champ est obligatoire.'), findsNWidgets(2));
      expect(s.appels, 0);
    });

    testWidgets('⚠️⚠️ un message valide est ENVOYÉ puis les champs se vident', (
      tester,
    ) async {
      final s = _ServeurFeint();
      await afficher(tester, d: depot(s));
      await saisirMessage(tester, objet: 'Question', message: 'Bonjour');

      expect(s.appels, 1);
      expect(s.recu!['subject'], 'Question');
      expect(find.byKey(const Key('contact-reussi')), findsOneWidget);
      expect(find.text('Message envoyé avec succès.'), findsOneWidget);
      expect(contenu(tester, 'contact-objet'), isEmpty);
    });

    testWidgets(
      '⚠️⚠️ hors ligne : échec visible, TEXTE CONSERVÉ, pas de succès',
      (tester) async {
        await afficher(tester, d: depot(_ServeurFeint(horsLigne: true)));
        await saisirMessage(
          tester,
          objet: 'Question',
          message: 'Un long texte',
        );

        expect(find.byKey(const Key('contact-echec')), findsOneWidget);
        expect(find.byKey(const Key('contact-reussi')), findsNothing);
        expect(find.textContaining('nécessite le réseau'), findsOneWidget);
        expect(contenu(tester, 'contact-objet'), 'Question');
        expect(contenu(tester, 'contact-message'), 'Un long texte');
      },
    );

    testWidgets('⚠️ le brouillon survit à un changement d\'écran', (
      tester,
    ) async {
      await afficher(tester);
      await tester.enterText(
        find.byKey(const Key('contact-objet')),
        'Brouillon',
      );
      await tester.pump();

      // L'écran est détruit, puis reconstruit avec le MÊME brouillon.
      await tester.pumpWidget(const SizedBox());
      await afficher(tester);

      expect(contenu(tester, 'contact-objet'), 'Brouillon');
    });

    testWidgets(
      'onglet bug : module, description, étapes, capture, bouton rouge',
      (tester) async {
        await afficher(tester);
        await ouvrirBug(tester);

        expect(find.text('MODULE CONCERNÉ *'), findsOneWidget);
        expect(find.text('DESCRIPTION DU PROBLÈME *'), findsOneWidget);
        expect(find.text('ÉTAPES POUR REPRODUIRE'), findsOneWidget);
        expect(find.text("CAPTURE D'ÉCRAN (OPTIONNEL)"), findsOneWidget);
        expect(find.text('Signaler le Bug'), findsWidgets);
        expect(find.byKey(const Key('contact-signaler')), findsOneWidget);
      },
    );

    testWidgets(
      '⚠️ la capture d\'écran est un texte explicatif, pas un faux bouton',
      (tester) async {
        await afficher(tester);
        await ouvrirBug(tester);

        expect(find.byKey(const Key('contact-capture')), findsOneWidget);
        expect(find.textContaining('ne peut pas joindre'), findsOneWidget);
        // Aucun contrôle cliquable dans la zone.
        expect(
          find.descendant(
            of: find.byKey(const Key('contact-capture')),
            matching: find.byType(InkWell),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('bug : module et description obligatoires', (tester) async {
      final s = _ServeurFeint();
      await afficher(tester, d: depot(s));
      await ouvrirBug(tester);

      await tester.ensureVisible(find.byKey(const Key('contact-signaler')));
      await tester.tap(find.byKey(const Key('contact-signaler')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('erreur-module')), findsOneWidget);
      expect(find.byKey(const Key('erreur-description')), findsOneWidget);
      expect(find.byKey(const Key('erreur-etapes')), findsNothing);
      expect(s.appels, 0);
    });

    testWidgets('bug valide : envoyé avec le module choisi', (tester) async {
      final s = _ServeurFeint();
      await afficher(tester, d: depot(s));
      await ouvrirBug(tester);

      await tester.tap(find.byKey(const Key('contact-module')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stocks').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('contact-description')),
        'Le stock ne bouge pas',
      );
      await tester.ensureVisible(find.byKey(const Key('contact-signaler')));
      await tester.tap(find.byKey(const Key('contact-signaler')));
      await tester.pumpAndSettle();

      expect(s.recu!['type'], 'bug');
      expect(s.recu!['module'], 'Stocks');
      expect(s.recu!['description'], 'Le stock ne bouge pas');
      expect(
        find.text('Signalement envoyé — merci pour votre retour.'),
        findsOneWidget,
      );
    });

    testWidgets('changer d\'onglet efface les erreurs affichées', (
      tester,
    ) async {
      await afficher(tester);
      await saisirMessage(tester);
      expect(find.byKey(const Key('erreur-objet')), findsOneWidget);

      await ouvrirBug(tester);
      await tester.tap(
        find.byKey(const Key('onglet-contact-Envoyer un Message')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('erreur-objet')), findsNothing);
    });

    testWidgets('sans session, l\'écran le dit sans rien simuler', (
      tester,
    ) async {
      await afficher(tester, d: depot(null));
      await saisirMessage(tester, objet: 'o', message: 'm');

      expect(
        find.text('Aucune session ouverte : connectez-vous.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('contact-reussi')), findsNothing);
      expect(contenu(tester, 'contact-objet'), 'o');
    });

    testWidgets('⚠️⚠️ coordonnées de Laravel : éditeur, e-mails, téléphones', (
      tester,
    ) async {
      await afficher(tester);

      expect(find.text('Dr MASSENON Rhodes'), findsOneWidget);
      expect(find.text('Docteur en Génie Logiciel et IA'), findsOneWidget);
      expect(find.text('rarhodes06@gmail.com'), findsOneWidget);
      expect(find.text('contact@massenonrhodes.com'), findsOneWidget);
      expect(find.text('+229 01 51 33 50 40'), findsOneWidget);
      expect(find.text('Lun-Ven, 8h-17h (GMT)'), findsOneWidget);
      expect(find.textContaining('XX XX'), findsNothing);
    });

    testWidgets(
      '« Qui contacter ? » oriente le chiffre réglementaire vers FAGUEZ',
      (tester) async {
        await afficher(tester);

        final carte = find.byKey(const Key('carte-qui-contacter'));
        expect(carte, findsOneWidget);
        expect(
          find.descendant(
            of: carte,
            matching: find.textContaining(
              'Cabinet FAGUEZ SARL',
              findRichText: true,
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('le lien « Aide & FAQ » ouvre l\'aide', (tester) async {
      var ouvert = 0;
      await afficher(tester, onAide: () => ouvert++);

      await tester.tap(find.byKey(const Key('contact-aide')));
      await tester.pumpAndSettle();

      expect(ouvert, 1);
    });

    testWidgets('lg: deux colonnes 60 / 40', (tester) async {
      await afficher(tester, taille: const Size(1400, 2400));

      final g = tester.getRect(find.byKey(const Key('carte-formulaire')));
      final d = tester.getRect(find.byKey(const Key('carte-coordonnees')));

      expect(g.top, d.top);
      expect(g.width / d.width, closeTo(60 / 40, 0.01));
    });

    testWidgets('sous lg: les cartes s\'empilent', (tester) async {
      await afficher(tester, taille: const Size(800, 3000));

      final g = tester.getRect(find.byKey(const Key('carte-formulaire')));
      final d = tester.getRect(find.byKey(const Key('carte-coordonnees')));

      expect(d.top, greaterThan(g.bottom));
    });
  });

  group('menu du compte', () {
    testWidgets('« Contactez l\'Éditeur » suit « Aide & À Propos »', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var contact = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarreSuperieure(
              groupe: '',
              ecran: "Contactez l'Éditeur",
              enAttente: 0,
              onBasculerMenu: () {},
              onMonProfil: () {},
              onAide: () {},
              onContact: () => contact++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-compte')));
      await tester.pumpAndSettle();

      final aide = tester.getTopLeft(find.byKey(const Key('menu-compte-aide')));
      final entree = tester.getTopLeft(
        find.byKey(const Key('menu-compte-contact')),
      );
      expect(entree.dy, greaterThan(aide.dy));

      await tester.tap(find.byKey(const Key('menu-compte-contact')));
      await tester.pumpAndSettle();
      expect(contact, 1);
    });
  });

  group('RBAC', () {
    test('⚠️ ouvert à tout rôle — extension à confirmer par le client', () {
      for (final role in ['admin', 'caissier', 'animalier', 'comptable', 'x']) {
        expect(
          PermissionsPoste.autorise(role, EcranPoste.contactEditeur),
          isTrue,
          reason: role,
        );
      }
    });

    test('la carte du prototype reste recopiée sans la page', () {
      final listes = PermissionsPoste.carte.values
          .whereType<List<String>>()
          .expand((l) => l);
      expect(listes, isNot(contains('contact-editeur.html')));
    });
  });
}
