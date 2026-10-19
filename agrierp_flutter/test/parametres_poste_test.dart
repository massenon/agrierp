import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/config/environnement.dart';
import 'package:agrierp/core/config/parametres_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/parametres/appairage_poste.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

/// Sprint 0 Flutter — RÉGLAGES DU POSTE ; ticket CFG-2 — ONGLET « APPAIRAGE » DE PARAMÈTRES.
///
/// 🔁 L'écran isolé « Paramètres du poste » est devenu l'onglet « Appairage » du hub Paramètres : ses tests le
/// suivent (mêmes clés, mêmes règles), avec l'environnement, le compte connecté, l'état du jeton, le test de
/// connexion et le réappairage.
///
/// 🔴 Ce que ce ticket corrige : `deviceId` valait la constante `'poste-dev'`
/// partout, et l'adresse du serveur pointait sur `127.0.0.1`. Toutes les
/// installations auraient partagé le même identifiant — deux postes de la ferme
/// indiscernables, et plus aucun conflit explicable.
void main() {
  late AppDatabase db;
  late ParametresPoste parametres;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    parametres = ParametresPoste(database: db);
  });

  tearDown(() async => db.close());

  /// ⚠️ L'IDENTIFIANT NE CHANGE JAMAIS APRÈS SON PREMIER TIRAGE : il faut
  /// pouvoir dire quel poste a produit une saisie, des mois plus tard.
  test('l identifiant est tire une fois puis conserve', () async {
    final premier = await parametres.identifiant();
    final second = await parametres.identifiant();

    expect(premier, second);
    expect(premier, startsWith('poste-'));
  });

  /// Deux postes distincts obtiennent des identifiants distincts — c'est tout
  /// l'objet du changement.
  test('deux postes obtiennent des identifiants distincts', () async {
    final autreDb = AppDatabase.forTesting(NativeDatabase.memory());
    final autre = ParametresPoste(database: autreDb);

    final a = await parametres.identifiant();
    final b = await autre.identifiant();

    expect(a, isNot(b));

    await autreDb.close();
  });

  test('l adresse par defaut est locale tant que rien n est designe', () async {
    expect(await parametres.adresseServeur(), ParametresPoste.adresseParDefaut);
  });

  test('l adresse designee est conservee', () async {
    await parametres.definirAdresseServeur('http://192.168.1.10:8000');

    expect(await parametres.adresseServeur(), 'http://192.168.1.10:8000');
  });

  /// ⚠️ Une barre oblique finale produirait `//api/sync/pull` — un chemin que
  /// le serveur ne reconnaît pas, et une panne d'autant plus déroutante que
  /// l'adresse « a l'air bonne ».
  test('la barre oblique finale est retiree', () async {
    await parametres.definirAdresseServeur('http://192.168.1.10:8000/');

    expect(await parametres.adresseServeur(), 'http://192.168.1.10:8000');
  });

  /// ⚠️ Sans schéma, le client HTTP échoue sur une erreur peu parlante.
  test('un schema manquant est ajoute', () async {
    await parametres.definirAdresseServeur('192.168.1.10:8000');

    expect(await parametres.adresseServeur(), 'http://192.168.1.10:8000');
  });

  /// Une saisie vide ne doit pas effacer une adresse valide.
  test('une adresse vide ne remplace rien', () async {
    await parametres.definirAdresseServeur('http://192.168.1.10:8000');
    await parametres.definirAdresseServeur('   ');

    expect(await parametres.adresseServeur(), 'http://192.168.1.10:8000');
  });

  // ── Ticket CFG-2 — l'écran isolé « Paramètres du poste » est devenu l'onglet « Appairage » du hub ─────────

  /// Hub Paramètres ouvert sur « Appairage », comme l'entrée « Paramètres du poste » de la barre latérale.
  Future<void> afficherAppairage(WidgetTester tester, AppairagePoste appairage) async {
    tester.view.physicalSize = const Size(1600, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ParametresGenerauxScreen(
          depot: ParametresGenerauxRepository(database: db),
          appairage: appairage,
          ongletInitial: ParametresGenerauxScreen.ongletAppairage,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> nettoyer(WidgetTester tester) async {
    ToastAgri.toutRetirer();
    await tester.pumpWidget(const SizedBox());
  }

  /// Session reprise du coffre (jeton + compte), comme au démarrage d'un poste déjà appairé.
  Future<AuthService> sessionOuverte(Dio client, {CoffreMemoire? coffre}) async {
    final auth = AuthService(
      client: client,
      deviceName: 'poste-a1b2c3d4',
      coffre:
          coffre ??
          CoffreMemoire({
            'agrierp.token': '12|jeton-du-poste',
            'agrierp.user': jsonEncode({
              'id': 'u1',
              'name': 'Directeur Général',
              'username': 'admin',
              'email': 'dg@olouwachegoun.bj',
              'role': 'admin',
              'role_label': 'Administrateur',
            }),
          }),
    );
    await auth.reprendreSession();
    return auth;
  }

  AppairagePoste appairageDe(
    AuthService auth, {
    bool suspendue = false,
    Future<void> Function()? reappairer,
  }) => AppairagePoste(
    parametres: parametres,
    identifiant: 'poste-a1b2c3d4',
    auth: auth,
    environnement: Environnement.production,
    sessionSuspendue: () => suspendue,
    reappairer: reappairer,
  );

  testWidgets('l onglet Appairage affiche l identifiant et enregistre l adresse', (tester) async {
    final client = Dio(BaseOptions(baseUrl: 'https://agrierp.fermeolouwachegoun.com'));
    await afficherAppairage(tester, appairageDe(await sessionOuverte(client)));

    expect(
      tester.widget<SelectableText>(find.byKey(const Key('identifiant-poste'))).data,
      'poste-a1b2c3d4',
    );

    await tester.enterText(find.byKey(const Key('adresse-serveur')), '10.0.0.5:8000/');
    await tester.tap(find.byKey(const Key('enregistrer-adresse')));
    await tester.pumpAndSettle();

    // Normalisée : schéma ajouté, barre oblique finale retirée.
    expect(await parametres.adresseServeur(), 'http://10.0.0.5:8000');
    expect(
      tester.widget<Text>(find.byKey(const Key('adresse-actuelle'))).data,
      'Actuelle : http://10.0.0.5:8000',
    );
    // ⚠️ Le client HTTP est construit au démarrage : l'écran dit qu'il faut relancer, et quelle adresse sert
    // jusque-là — sinon on croit à une panne réseau.
    expect(find.textContaining('Redémarrez'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('adresse-en-usage'))).data,
      "En usage jusqu'au redémarrage : https://agrierp.fermeolouwachegoun.com",
    );
    await nettoyer(tester);
  });

  // Ticket H13 (B2) — l'intervalle de la synchronisation automatique se règle ici.
  testWidgets('l onglet Appairage règle l intervalle de la synchronisation automatique', (tester) async {
    await afficherAppairage(tester, appairageDe(await sessionOuverte(Dio())));

    expect(find.text('SYNCHRONISATION AUTOMATIQUE'), findsOneWidget);
    // Ticket S-T3 — 5 minutes par défaut, et l'écran le dit.
    expect(find.text('Toutes les 5 minutes'), findsOneWidget);
    expect(find.textContaining('Toutes les 5 minutes par défaut.'), findsOneWidget);
    expect(
      find.textContaining('quelques secondes après une vente, une fiche journalière ou un soin'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('intervalle-synchronisation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toutes les 30 minutes').last);
    await tester.pumpAndSettle();

    expect(await parametres.intervalleSynchronisation(), const Duration(minutes: 30));
    expect(find.textContaining('prochaine ouverture de session'), findsOneWidget);
    await nettoyer(tester);
  });

  testWidgets('l onglet Appairage montre l environnement, le compte connecté et le jeton présent', (tester) async {
    await afficherAppairage(tester, appairageDe(await sessionOuverte(Dio())));

    expect(tester.widget<Text>(find.byKey(const Key('appairage-environnement'))).data, 'Production');
    expect(
      find.textContaining('Serveur par défaut de cet environnement : ${Environnement.production.adresseParDefaut}.'),
      findsOneWidget,
    );
    expect(tester.widget<Text>(find.byKey(const Key('appairage-compte-nom'))).data, 'Directeur Général');
    expect(tester.widget<Text>(find.byKey(const Key('appairage-compte-identifiant'))).data, 'admin');
    expect(tester.widget<Text>(find.byKey(const Key('appairage-compte-role'))).data, 'Administrateur');
    expect(
      find.descendant(of: find.byKey(const Key('appairage-etat-jeton')), matching: find.text('Présent')),
      findsOneWidget,
    );
    await nettoyer(tester);
  });

  /// Ticket S-T1 — une synchronisation automatique suspendue sur 401 / 403 se lit ici : « Session refusée ».
  testWidgets('⚠️ une session suspendue par le serveur est annoncée refusée', (tester) async {
    await afficherAppairage(tester, appairageDe(await sessionOuverte(Dio()), suspendue: true));

    expect(
      find.descendant(of: find.byKey(const Key('appairage-etat-jeton')), matching: find.text('Session refusée')),
      findsOneWidget,
    );
    expect(find.textContaining('réappairez ce poste'), findsOneWidget);
    await nettoyer(tester);
  });

  testWidgets('sans jeton au coffre, le poste se dit non appairé', (tester) async {
    await afficherAppairage(
      tester,
      appairageDe(AuthService(client: Dio(), deviceName: 'poste-a1b2c3d4', coffre: CoffreMemoire())),
    );

    expect(
      find.descendant(of: find.byKey(const Key('appairage-etat-jeton')), matching: find.text('Absent')),
      findsOneWidget,
    );
    expect(tester.widget<Text>(find.byKey(const Key('appairage-compte-nom'))).data, '—');
    // Sans session ni geste de déconnexion fourni, « Réappairer » n'est pas proposé.
    expect(find.byKey(const Key('appairage-reappairer')), findsNothing);
    await nettoyer(tester);
  });

  testWidgets('un coffre illisible donne un état inconnu, jamais une absence affirmée', (tester) async {
    await afficherAppairage(
      tester,
      appairageDe(AuthService(client: Dio(), deviceName: 'poste-a1b2c3d4', coffre: const CoffreIllisible())),
    );

    expect(
      find.descendant(of: find.byKey(const Key('appairage-etat-jeton')), matching: find.text('—')),
      findsOneWidget,
    );
    await nettoyer(tester);
  });

  testWidgets('« Tester la connexion » interroge /api/auth/me et dit ce que le serveur reconnaît', (tester) async {
    final serveur = _ServeurMe(statut: 200);
    final client = Dio()..interceptors.add(serveur);
    await afficherAppairage(tester, appairageDe(await sessionOuverte(client)));

    await tester.tap(find.byKey(const Key('appairage-tester')));
    await tester.pumpAndSettle();

    expect(serveur.chemins, ['/api/auth/me']);
    expect(serveur.autorisation, 'Bearer 12|jeton-du-poste');
    expect(
      find.text(
        'Connexion réussie : le serveur reconnaît ce poste (compte Directeur Général, rôle Administrateur).',
      ),
      findsOneWidget,
    );
    await nettoyer(tester);
  });

  /// ⚠️⚠️ Appairage révoqué au web : `/api/auth/me` répond 401 — l'état passe à « Session refusée ».
  testWidgets('⚠️⚠️ un 401 au test de connexion fait passer la session à refusée', (tester) async {
    final client = Dio()..interceptors.add(_ServeurMe(statut: 401));
    await afficherAppairage(tester, appairageDe(await sessionOuverte(client)));

    await tester.tap(find.byKey(const Key('appairage-tester')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('toast-erreur')), findsOneWidget);
    expect(find.textContaining('Test de connexion impossible — '), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('appairage-etat-jeton')), matching: find.text('Session refusée')),
      findsOneWidget,
    );
    await nettoyer(tester);
  });

  testWidgets('hors ligne, le test de connexion le dit en français', (tester) async {
    final client = Dio()..interceptors.add(_ServeurMe(statut: 0));
    await afficherAppairage(tester, appairageDe(await sessionOuverte(client)));

    await tester.tap(find.byKey(const Key('appairage-tester')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Serveur injoignable'), findsOneWidget);
    // Un échec réseau n'est pas un refus : le jeton reste présent.
    expect(
      find.descendant(of: find.byKey(const Key('appairage-etat-jeton')), matching: find.text('Présent')),
      findsOneWidget,
    );
    await nettoyer(tester);
  });

  /// ⚠️⚠️ RÉAPPAIRER = DÉCONNEXION PROPRE (jeton retiré du coffre) PUIS ÉCRAN DE CONNEXION ; les saisies en
  /// attente ne sont pas touchées.
  testWidgets('⚠️⚠️ « Réappairer » ferme la session après confirmation et garde les saisies', (tester) async {
    final coffre = CoffreMemoire({
      'agrierp.token': '12|jeton-du-poste',
      'agrierp.user': jsonEncode({'id': 'u1', 'name': 'Directeur Général', 'role': 'admin'}),
    });
    final client = Dio()..interceptors.add(_ServeurMe(statut: 200));
    final auth = await sessionOuverte(client, coffre: coffre);
    await db.into(db.appSettings).insert(AppSettingsCompanion.insert(key: 'temoin.saisie', value: 'en attente'));
    var retourALaConnexion = 0;
    await afficherAppairage(
      tester,
      appairageDe(
        auth,
        reappairer: () async {
          await auth.deconnecter();
          retourALaConnexion++;
        },
      ),
    );

    // Annuler ne fait rien.
    await tester.tap(find.byKey(const Key('appairage-reappairer')));
    await tester.pumpAndSettle();
    expect(find.text('Réappairer ce poste'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(retourALaConnexion, 0);
    expect(coffre.contenu, contains('agrierp.token'));

    await tester.tap(find.byKey(const Key('appairage-reappairer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appairage-reappairer-confirmer')));
    await tester.pumpAndSettle();

    expect(retourALaConnexion, 1);
    expect(coffre.contenu, isNot(contains('agrierp.token')));
    expect(auth.utilisateur, isNull);
    expect(
      (await (db.select(db.appSettings)..where((t) => t.key.equals('temoin.saisie'))).getSingle()).value,
      'en attente',
    );
    await nettoyer(tester);
  });

  /// ⚠️ L'entrée « Paramètres du poste » reste réservée à l'administrateur, comme le hub qu'elle ouvre désormais.
  test('⚠️ Paramètres du poste et le hub restent réservés à l administrateur', () {
    for (final ecran in [EcranPoste.parametres, EcranPoste.parametresGeneraux]) {
      expect(PermissionsPoste.autorise('admin', ecran), isTrue);
      for (final role in ['caissier', 'animalier', 'comptable']) {
        expect(PermissionsPoste.autorise(role, ecran), isFalse, reason: '$role › $ecran');
      }
    }
  });

  /// 🔁 L'ancien écran isolé n'existe plus : rien ne doit plus le construire.
  test('🔁 l ancien écran isolé est retiré et l entrée ouvre l onglet Appairage', () {
    expect(File('lib/features/parametres/parametres_poste_screen.dart').existsSync(), isFalse);
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, isNot(contains('ParametresPosteScreen')));
    expect(
      RegExp(
        r'EcranPoste\.parametres => _parametresGeneraux\(\s*ongletInitial: ParametresGenerauxScreen\.ongletAppairage,',
      ).hasMatch(main),
      isTrue,
    );
  });
}

/// Serveur feint de `GET /api/auth/me` : [statut] 200 (compte), 401 (jeton révoqué) ou 0 (injoignable).
class _ServeurMe extends Interceptor {
  _ServeurMe({required this.statut});

  final int statut;
  final chemins = <String>[];
  String? autorisation;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    chemins.add(options.path);
    autorisation = options.headers['Authorization'] as String?;
    if (statut == 0) {
      handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError));
      return;
    }
    if (statut != 200) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: statut, data: {'message': 'Unauthenticated.'}),
        ),
      );
      return;
    }
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'id': 'u1',
          'name': 'Directeur Général',
          'username': 'admin',
          'email': 'dg@olouwachegoun.bj',
          'role': 'admin',
          'role_label': 'Administrateur',
        },
      ),
    );
  }
}
