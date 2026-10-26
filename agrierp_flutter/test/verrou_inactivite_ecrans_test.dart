import 'dart:convert';
import 'dart:math';

import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/core/auth/verrou_inactivite.dart';
import 'package:agrierp/core/auth/verrou_local.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/features/profil/mon_profil_repository.dart';
import 'package:agrierp/features/profil/mon_profil_screen.dart';
import 'package:agrierp/features/verrou/porte_session.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

/// Ticket VL-2 — verrouillage automatique après inactivité, monté dans la vraie porte de session
/// (`PorteSession` + `SurveillanceInactivite` au-dessus du navigateur, comme `main.dart`).
void main() {
  const sentinelle = 'DONNEES-DE-LA-FERME';
  late CoffreMemoire coffre;
  late AuthService auth;
  late VerrouLocal verrou;
  late VerrouInactivite inactivite;
  late int finsDeSession;
  late VoidCallback deconnecter;

  setUp(() {
    coffre = CoffreMemoire();
    auth = AuthService(
      client: Dio(BaseOptions(baseUrl: 'http://serveur-feint')),
      deviceName: 'poste',
      coffre: coffre,
    );
    verrou = VerrouLocal(coffre: coffre, alea: Random(3), iterations: 20);
    inactivite = VerrouInactivite(reglage: ReglageInactivite(coffre: coffre), verrou: verrou);
    finsDeSession = 0;
    coffre.contenu['agrierp.token'] = 'jeton';
    coffre.contenu['agrierp.user'] = jsonEncode({
      'id': 'u1',
      'name': 'Comptable Ferme',
      'username': 'compta',
      'email': 'c@x.bj',
      'role': 'comptable',
      'role_label': 'Comptable',
    });
  });

  Future<void> monterEtDeverrouiller(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await verrou.definir('u1', '1234');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SurveillanceInactivite(controleur: inactivite, child: child!),
        home: PorteSession(
          auth: auth,
          verrou: verrou,
          inactivite: inactivite,
          surFinDeSession: () => finsDeSession++,
          ecranConnexion: (onConnecte) => const Scaffold(body: Text('FAUX-LOGIN')),
          application: (verrouiller, onDeconnecte) {
            deconnecter = onDeconnecte;
            return Scaffold(
              body: Column(
                children: [
                  const Text(sentinelle),
                  Builder(
                    builder: (context) => TextButton(
                      key: const Key('ouvrir-modale'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const AlertDialog(content: Text('FORMULAIRE-MODAL')),
                      ),
                      child: const Text('modale'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final c in '1234'.split('')) {
      await tester.tap(find.byKey(Key('touche-$c')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('verrou-bouton')));
    await tester.pumpAndSettle();
    expect(find.text(sentinelle), findsOneWidget);
  }

  testWidgets('5 min sans interaction : l\'écran de verrouillage remplace l\'application (sans réseau)', (tester) async {
    await monterEtDeverrouiller(tester);
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(find.text(sentinelle), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Application verrouillée'), findsOneWidget);
    expect(find.text(sentinelle), findsNothing);
    expect(find.byKey(const Key('verrou-bouton')), findsOneWidget);
  });

  testWidgets('un clic repousse l\'échéance', (tester) async {
    await monterEtDeverrouiller(tester);
    await tester.pump(const Duration(minutes: 4));
    await tester.tapAt(const Offset(600, 800));
    await tester.pump(const Duration(minutes: 4));
    expect(find.text(sentinelle), findsOneWidget);
  });

  testWidgets('l\'écran de verrouillage ne se re-verrouille pas : toujours LUI, le temps passe, activité ou non', (tester) async {
    await monterEtDeverrouiller(tester);
    await tester.pump(const Duration(minutes: 6));
    await tester.pumpAndSettle();
    expect(find.text('Application verrouillée'), findsOneWidget);
    expect(inactivite.arme, isFalse);
    inactivite.activite();
    await tester.pump(const Duration(hours: 2));
    expect(find.text('Application verrouillée'), findsOneWidget);
    // Le bon PIN rouvre, et le minuteur repart.
    for (final c in '1234'.split('')) {
      await tester.tap(find.byKey(Key('touche-$c')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('verrou-bouton')));
    await tester.pumpAndSettle();
    expect(find.text(sentinelle), findsOneWidget);
    expect(inactivite.arme, isTrue);
  });

  testWidgets('formulaire modal ouvert : report d\'1 min, puis verrou ET la fenêtre est fermée', (tester) async {
    await monterEtDeverrouiller(tester);
    await tester.tap(find.byKey(const Key('ouvrir-modale')));
    await tester.pumpAndSettle();
    expect(find.text('FORMULAIRE-MODAL'), findsOneWidget);

    await tester.pump(const Duration(minutes: 5, seconds: 30));
    expect(find.text('FORMULAIRE-MODAL'), findsOneWidget, reason: 'report accordé, rien n\'est perdu');
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('Application verrouillée'), findsOneWidget);
    expect(find.text('FORMULAIRE-MODAL'), findsNothing, reason: 'la fenêtre ne recouvre pas l\'écran de verrouillage');
  });

  testWidgets('une interaction DANS la fenêtre modale compte (le Listener est au-dessus du navigateur)', (tester) async {
    await monterEtDeverrouiller(tester);
    await tester.tap(find.byKey(const Key('ouvrir-modale')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 4));
    await tester.tap(find.text('FORMULAIRE-MODAL'));
    await tester.pump(const Duration(minutes: 4));
    expect(find.text(sentinelle), findsOneWidget);
  });

  testWidgets('la déconnexion signale la fin de session (brouillons de la coque vidés) et désarme', (tester) async {
    await monterEtDeverrouiller(tester);
    deconnecter();
    await tester.pumpAndSettle();
    expect(finsDeSession, 1);
    expect(inactivite.arme, isFalse);
    expect(find.text('FAUX-LOGIN'), findsOneWidget);
  });

  group('Mon profil — Verrouillage automatique', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    testWidgets('rubrique à 5 min par défaut ; le choix est enregistré par utilisateur et appliqué aussitôt', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await verrou.definir('u1', '1234');
      inactivite.armer(idUtilisateur: 'u1', verrouiller: () {});
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
            changerPin: ({required ancien, required nouveau, required confirmation}) async => (true, ''),
            delaiInactivite: () => inactivite.reglage.lire('u1'),
            changerDelaiInactivite: inactivite.regler,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('carte-inactivite')), findsOneWidget);
      expect(find.text('5 minutes'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delai-inactivite')));
      await tester.pumpAndSettle();
      for (final l in ['Jamais', '1 minute', '15 minutes', '30 minutes']) {
        expect(find.text(l), findsWidgets);
      }
      await tester.tap(find.text('15 minutes').last);
      await tester.pumpAndSettle();

      expect(coffre.contenu['agrierp.inactivite.u1'], '15');
      expect(inactivite.minutes, 15);
      expect(await ReglageInactivite(coffre: coffre).lire('u2'), 5);
      inactivite.desarmer();
    });

    testWidgets('sans minuteur fourni (tests du châssis) : la rubrique est absente', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MonProfilScreen(
            depot: MonProfilRepository(database: db),
            session: null,
            changerPin: ({required ancien, required nouveau, required confirmation}) async => (true, ''),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('carte-inactivite')), findsNothing);
    });
  });
}
