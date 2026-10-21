import 'dart:convert';
import 'dart:math';

import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/core/auth/verrou_local.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:agrierp/features/profil/mon_profil_repository.dart';
import 'package:agrierp/features/profil/mon_profil_screen.dart';
import 'package:agrierp/features/verrou/changement_pin.dart';
import 'package:agrierp/features/verrou/porte_session.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

/// Ticket VL-1 — verrou local : la porte de session, l'écran de verrouillage, la définition du PIN, Mon profil.
///
/// Les « écrans de l'application » sont ici un texte-sentinelle : il ne doit JAMAIS être dans l'arbre tant que
/// l'écran de verrouillage ou de définition est montré.
class _ServeurFeint extends Interceptor {
  final chemins = <String>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    chemins.add(options.path);
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path == '/api/auth/login'
            ? {
                'token': 'jeton',
                'user': {
                  'id': 'u1',
                  'name': 'Comptable Ferme',
                  'username': 'compta',
                  'email': 'c@x.bj',
                  'role': 'comptable',
                  'role_label': 'Comptable',
                },
              }
            : const {},
      ),
    );
  }
}

void main() {
  const sentinelle = 'DONNEES-DE-LA-FERME';
  late CoffreMemoire coffre;
  late _ServeurFeint serveur;
  late AuthService auth;
  late VerrouLocal verrou;
  late DateTime maintenant;
  late VoidCallback verrouillerApp;

  void sessionRestauree() {
    coffre.contenu['agrierp.token'] = 'jeton';
    coffre.contenu['agrierp.user'] = jsonEncode({
      'id': 'u1',
      'name': 'Comptable Ferme',
      'username': 'compta',
      'email': 'c@x.bj',
      'role': 'comptable',
      'role_label': 'Comptable',
    });
  }

  setUp(() {
    coffre = CoffreMemoire();
    serveur = _ServeurFeint();
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur);
    auth = AuthService(client: client, deviceName: 'poste', coffre: coffre);
    maintenant = DateTime.utc(2026, 10, 21, 8);
    verrou = VerrouLocal(coffre: coffre, horloge: () => maintenant, alea: Random(3), iterations: 20);
  });

  Future<void> monter(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PorteSession(
          auth: auth,
          verrou: verrou,
          ecranConnexion: (onConnecte) => Scaffold(
            body: Column(
              children: [
                const Text('FAUX-LOGIN'),
                TextButton(
                  key: const Key('faux-connexion'),
                  onPressed: () async {
                    await auth.connecter(identifiant: 'compta', motDePasse: 'x');
                    onConnecte();
                  },
                  child: const Text('connexion'),
                ),
              ],
            ),
          ),
          application: (verrouiller, onDeconnecte) {
            verrouillerApp = verrouiller;
            return const Scaffold(body: Text(sentinelle));
          },
        ),
      ),
    );
  }

  Future<void> saisir(WidgetTester tester, String chiffres, {bool valider = true, String touche = 'verrou-bouton'}) async {
    for (final c in chiffres.split('')) {
      await tester.tap(find.byKey(Key('touche-$c')));
      await tester.pump();
    }
    if (valider) {
      await tester.tap(find.byKey(Key(touche)));
      await tester.pumpAndSettle();
    }
  }

  testWidgets("pas de session : la connexion, ni écran PIN ni application", (tester) async {
    await monter(tester);
    await tester.pumpAndSettle();
    expect(find.text('FAUX-LOGIN'), findsOneWidget);
    expect(find.byKey(const Key('pin-saisie')), findsNothing);
    expect(find.text(sentinelle), findsNothing);
  });

  testWidgets("rien n'est montré avant que l'état soit connu (pas de flash de l'application)", (tester) async {
    sessionRestauree();
    await verrou.definir('u1', '1234');
    await monter(tester);
    // Premier cadre : la reprise de session n'a pas encore répondu.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(sentinelle), findsNothing);
    expect(find.text('FAUX-LOGIN'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('session restaurée + PIN : écran de verrouillage, logo, nom, AUCUN texte de l\'application', (tester) async {
    sessionRestauree();
    await verrou.definir('u1', '1234');
    await monter(tester);
    await tester.pumpAndSettle();

    // Même présentation que la connexion : panneau de la ferme, champ d'identifiant en lecture seule.
    expect(find.byKey(const Key('login-panneau-gauche')), findsOneWidget);
    expect(find.text('Bienvenue !'), findsNothing);
    expect(find.textContaining('Comptable Ferme'), findsOneWidget);
    final champ = tester.widget<TextField>(find.byKey(const Key('verrou-utilisateur')));
    expect(champ.readOnly, isTrue);
    expect(champ.controller!.text, 'compta');
    expect(find.text('DÉVERROUILLER'), findsOneWidget);
    expect(find.text('Application verrouillée'), findsOneWidget);
    expect(find.text(sentinelle), findsNothing);
    expect(serveur.chemins, isEmpty, reason: 'aucun appel réseau pour le verrou');
  });

  testWidgets('le bon PIN (clavier à l\'écran) ouvre l\'application', (tester) async {
    sessionRestauree();
    await verrou.definir('u1', '1234');
    await monter(tester);
    await tester.pumpAndSettle();

    await saisir(tester, '1234');
    expect(find.text(sentinelle), findsOneWidget);
    expect(find.text('Application verrouillée'), findsNothing);
    expect(serveur.chemins, isEmpty);
  });

  testWidgets("un mauvais PIN : message, l'application reste fermée", (tester) async {
    sessionRestauree();
    await verrou.definir('u1', '1234');
    await monter(tester);
    await tester.pumpAndSettle();

    await saisir(tester, '9999');
    expect(find.text('Code PIN incorrect.'), findsOneWidget);
    expect(find.text(sentinelle), findsNothing);
    // La saisie est vidée.
    expect(find.byKey(const Key('pin-rempli-0')), findsNothing);
  });

  testWidgets('saisie au clavier physique : chiffres, Retour arrière, Entrée', (tester) async {
    sessionRestauree();
    await verrou.definir('u1', '1234');
    await monter(tester);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad2);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
    await tester.pump();
    expect(find.byKey(const Key('pin-rempli-2')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text(sentinelle), findsOneWidget);
  });

  testWidgets('le point de saisie est masqué : jamais un chiffre à l\'écran en dehors des touches', (tester) async {
    sessionRestauree();
    await verrou.definir('u1', '1234');
    await monter(tester);
    await tester.pumpAndSettle();

    await saisir(tester, '57', valider: false);
    expect(find.byKey(const Key('pin-rempli-1')), findsOneWidget);
    expect(find.byKey(const Key('pin-vide-2')), findsOneWidget);
    // Chaque chiffre n'apparaît qu'une fois : sur sa touche.
    expect(find.text('5'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    // Le seul champ de texte est l'identifiant, en lecture seule : le PIN n'est saisi dans aucun champ.
    expect(tester.widget<EditableText>(find.byType(EditableText)).readOnly, isTrue);
  });

  testWidgets('« PIN oublié ? » : confirmation, puis déconnexion et retour à la connexion', (tester) async {
    sessionRestauree();
    await verrou.definir('u1', '1234');
    await monter(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('verrou-oublie')));
    await tester.pumpAndSettle();
    // Annuler : on reste verrouillé.
    await tester.tap(find.byKey(const Key('verrou-oublie-annuler')));
    await tester.pumpAndSettle();
    expect(find.text('Application verrouillée'), findsOneWidget);
    expect(coffre.contenu['agrierp.token'], 'jeton');

    await tester.tap(find.byKey(const Key('verrou-oublie')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('verrou-oublie-confirmer')));
    await tester.pumpAndSettle();

    expect(find.text('FAUX-LOGIN'), findsOneWidget);
    expect(coffre.contenu.containsKey('agrierp.token'), isFalse);
    expect(await verrou.estDefini('u1'), isFalse);
    expect(find.text(sentinelle), findsNothing);
  });

  testWidgets('session restaurée sans PIN : définition obligatoire avant toute donnée', (tester) async {
    sessionRestauree();
    await monter(tester);
    await tester.pumpAndSettle();

    expect(find.text('Définir votre code PIN'), findsOneWidget);
    expect(find.text(sentinelle), findsNothing);
    // Aucune sortie : ni « Plus tard » ni « Passer ».
    expect(find.textContaining('Plus tard'), findsNothing);
    expect(find.textContaining('Passer'), findsNothing);
  });

  testWidgets('définition : confirmation différente refusée, on recommence', (tester) async {
    sessionRestauree();
    await monter(tester);
    await tester.pumpAndSettle();

    await saisir(tester, '1234');
    expect(find.text('Confirmez votre code PIN'), findsOneWidget);
    await saisir(tester, '4321');
    expect(find.text('Les deux codes ne correspondent pas. Recommencez.'), findsOneWidget);
    expect(find.text('Définir votre code PIN'), findsOneWidget);
    expect(await verrou.estDefini('u1'), isFalse);
    expect(find.text(sentinelle), findsNothing);
  });

  testWidgets('définition : moins de 4 chiffres refusé, plus de 6 impossible', (tester) async {
    sessionRestauree();
    await monter(tester);
    await tester.pumpAndSettle();

    await saisir(tester, '123');
    expect(find.text('Le code PIN comporte de 4 à 6 chiffres.'), findsOneWidget);
    expect(find.text('Définir votre code PIN'), findsOneWidget);

    for (final c in '12345678'.split('')) {
      await tester.tap(find.byKey(Key('touche-$c')));
      await tester.pump();
    }
    expect(find.byKey(const Key('pin-rempli-5')), findsOneWidget);
    expect(find.byKey(const Key('pin-rempli-6')), findsNothing);
    await tester.tap(find.byKey(const Key('verrou-bouton')));
    await tester.pumpAndSettle();
    expect(find.text('Confirmez votre code PIN'), findsOneWidget);
  });

  testWidgets('définition réussie (6 chiffres) : l\'application s\'ouvre, le PIN est défini', (tester) async {
    sessionRestauree();
    await monter(tester);
    await tester.pumpAndSettle();

    await saisir(tester, '246810');
    await saisir(tester, '246810');
    expect(find.text(sentinelle), findsOneWidget);
    expect((await verrou.verifier('u1', '246810')).resultat, ResultatVerrou.ok);
  });

  testWidgets('connexion en ligne sans PIN : définition, puis application (pas de second écran PIN)', (tester) async {
    await monter(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('faux-connexion')));
    await tester.pumpAndSettle();

    expect(find.text('Définir votre code PIN'), findsOneWidget);
    await saisir(tester, '1234');
    await saisir(tester, '1234');
    expect(find.text(sentinelle), findsOneWidget);
    expect(find.text('Application verrouillée'), findsNothing);
  });

  testWidgets("connexion en ligne avec un PIN déjà défini : on ne le redemande pas dans cette exécution", (tester) async {
    await verrou.definir('u1', '1234');
    await monter(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('faux-connexion')));
    await tester.pumpAndSettle();

    expect(find.text(sentinelle), findsOneWidget);
    expect(find.text('Application verrouillée'), findsNothing);
    expect(find.text('Définir votre code PIN'), findsNothing);
  });

  testWidgets('verrouillage manuel : l\'application est REMPLACÉE par l\'écran de verrouillage', (tester) async {
    sessionRestauree();
    await verrou.definir('u1', '1234');
    await monter(tester);
    await tester.pumpAndSettle();
    await saisir(tester, '1234');
    expect(find.text(sentinelle), findsOneWidget);

    verrouillerApp();
    await tester.pumpAndSettle();
    expect(find.text('Application verrouillée'), findsOneWidget);
    expect(find.text(sentinelle), findsNothing);

    await saisir(tester, '1234');
    expect(find.text(sentinelle), findsOneWidget);
  });

  testWidgets('cinq échecs : temporisation affichée, pavé inactif, puis il se rouvre', (tester) async {
    sessionRestauree();
    await verrou.definir('u1', '1234');
    await monter(tester);
    await tester.pumpAndSettle();

    for (var i = 0; i < 5; i++) {
      await saisir(tester, '0000');
    }
    expect(find.byKey(const Key('verrou-attente')), findsOneWidget);
    expect(find.textContaining('30 s'), findsOneWidget);
    // Pavé inactif : une touche n'ajoute rien.
    await tester.tap(find.byKey(const Key('touche-1')));
    await tester.pump();
    expect(find.byKey(const Key('pin-rempli-0')), findsNothing);

    await tester.pump(const Duration(seconds: 31));
    expect(find.byKey(const Key('verrou-attente')), findsNothing);
    await tester.tap(find.byKey(const Key('touche-1')));
    await tester.pump();
    expect(find.byKey(const Key('pin-rempli-0')), findsOneWidget);
    // Démonter l'écran arrête la minuterie.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dix échecs : accès refusé, « Se reconnecter » ramène à la connexion et efface le PIN', (tester) async {
    sessionRestauree();
    await verrou.definir('u1', '1234');
    await monter(tester);
    await tester.pumpAndSettle();

    for (var i = 0; i < 10; i++) {
      await saisir(tester, '0000');
      if (find.byKey(const Key('verrou-attente')).evaluate().isNotEmpty) {
        maintenant = maintenant.add(const Duration(hours: 1));
        await tester.pump(const Duration(hours: 1));
      }
    }
    expect(find.textContaining('Reconnectez-vous en ligne'), findsOneWidget);
    expect(find.byKey(const Key('touche-1')), findsNothing, reason: 'plus de pavé : plus rien à essayer');
    expect(find.text(sentinelle), findsNothing);

    await tester.tap(find.byKey(const Key('verrou-oublie')));
    await tester.pumpAndSettle();
    expect(find.text('FAUX-LOGIN'), findsOneWidget);
    expect(await verrou.estDefini('u1'), isFalse);
  });

  testWidgets('menu du compte : « Verrouiller » est proposé avant le séparateur de Déconnexion, et prévient le socle', (t) async {
    var verrouillages = 0;
    t.view.physicalSize = const Size(1100, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarreSuperieure(
            groupe: '',
            ecran: 'Tableau de Bord',
            enAttente: 0,
            onBasculerMenu: () {},
            nomUtilisateur: 'M. Olouchègoun',
            onParametres: () {},
            onVerrouiller: () => verrouillages++,
            onDeconnexion: () {},
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('menu-compte')));
    await t.pumpAndSettle();
    expect(
      t.getTopLeft(find.byKey(const Key('menu-compte-parametres'))).dy,
      lessThan(t.getTopLeft(find.byKey(const Key('menu-compte-verrouiller'))).dy),
    );
    expect(
      t.getTopLeft(find.byKey(const Key('menu-compte-verrouiller'))).dy,
      lessThan(t.getTopLeft(find.byKey(const Key('menu-compte-deconnexion'))).dy),
    );
    await t.tap(find.byKey(const Key('menu-compte-verrouiller')));
    await t.pumpAndSettle();
    expect(verrouillages, 1);
  });

  group('Mon profil — Changer le code PIN', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    Future<void> afficher(WidgetTester tester, {bool avecPin = true}) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MonProfilScreen(
            depot: MonProfilRepository(database: db),
            session: const SessionUtilisateur(
              id: 'u1',
              nom: 'Comptable Ferme',
              identifiant: 'compta',
              email: 'c@x.bj',
              role: 'comptable',
              roleLibelle: 'Comptable',
            ),
            changerPin: avecPin
                ? ({required ancien, required nouveau, required confirmation}) => changerPinDepuisProfil(
                    verrou,
                    'u1',
                    ancien: ancien,
                    nouveau: nouveau,
                    confirmation: confirmation,
                  )
                : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> remplir(WidgetTester tester, String a, String n, String c) async {
      await tester.enterText(find.byKey(const Key('pin-ancien')), a);
      await tester.enterText(find.byKey(const Key('pin-nouveau')), n);
      await tester.enterText(find.byKey(const Key('pin-confirmation')), c);
      await tester.ensureVisible(find.byKey(const Key('pin-envoyer')));
      await tester.tap(find.byKey(const Key('pin-envoyer')));
      await tester.pumpAndSettle();
    }

    testWidgets('sans verrou (tests du châssis), la section est absente', (tester) async {
      await afficher(tester, avecPin: false);
      expect(find.byKey(const Key('carte-pin')), findsNothing);
    });

    testWidgets("l'ancien PIN est requis ; le bon change le code", (tester) async {
      await verrou.definir('u1', '1234');
      await afficher(tester);
      expect(find.text('CHANGER LE CODE PIN'), findsOneWidget);

      await remplir(tester, '0000', '5678', '5678');
      expect(find.text('Ancien code PIN incorrect.'), findsOneWidget);
      expect((await verrou.verifier('u1', '1234')).resultat, ResultatVerrou.ok);

      await remplir(tester, '1234', '5678', '5678');
      expect(find.byKey(const Key('pin-reussi')), findsOneWidget);
      expect((await verrou.verifier('u1', '5678')).resultat, ResultatVerrou.ok);
    });

    testWidgets('confirmation différente ou nouveau code trop court : refusés sans toucher au PIN', (tester) async {
      await verrou.definir('u1', '1234');
      await afficher(tester);

      await remplir(tester, '1234', '5678', '5679');
      expect(find.text('Les deux codes ne correspondent pas.'), findsOneWidget);
      await remplir(tester, '1234', '56', '56');
      expect(find.text('Le nouveau code PIN comporte de 4 à 6 chiffres.'), findsOneWidget);
      expect((await verrou.verifier('u1', '1234')).resultat, ResultatVerrou.ok);
    });
  });
}
