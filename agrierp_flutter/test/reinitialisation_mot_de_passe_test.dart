import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/core/auth/verrou_local.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/auth/ecran_changement_mot_de_passe.dart';
import 'package:agrierp/features/auth/login_screen.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:agrierp/features/verrou/porte_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'coffre_memoire.dart';

/// Ticket MDP-1 — RÉINITIALISATION DU MOT DE PASSE PAR L'ADMINISTRATEUR (décision du client : plus de lien par e-mail).
///
/// Quatre garanties, chacune éprouvée :
///  1. l'écran de connexion n'a plus de « Mot de passe oublié ? » : le texte NON cliquable « Contactez l'administrateur »
///     (mêmes mots que le Blade, lus dans `login.blade.php`) ;
///  2. le geste « Réinitialiser le mot de passe » (même logique que `SaisieUtilisateurAction`) : jamais son propre compte,
///     jamais un compte archivé, mot de passe temporaire selon `Password::defaults()`, écrit au COFFRE (jamais en base),
///     envoyé avec `reset_password` ;
///  3. le drapeau `must_change_password` descend du serveur (jamais le mot de passe) et s'affiche dans la liste ;
///  4. le changement obligatoire à la connexion : l'écran passe AVANT l'accueil, ses textes sont ceux du Blade.

String _lire(String chemin) => File('$dossierLaravel/$chemin').readAsStringSync();

class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-29T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [for (final e in value) if (e is Map && e['id'] is String) e['id']],
                  'rejected': <Map<String, String>>[],
                },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Serveur d'authentification feint : connexion avec drapeau, changement de mot de passe (corps retenu).
class _ServeurAuth extends Interceptor {
  bool mustChange = true;
  Map<String, dynamic>? corpsChangement;
  Response<dynamic>? refusChangement;
  final chemins = <String>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    chemins.add(options.path);
    if (options.path == '/api/auth/login') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'token': 'jeton',
            'user': {'id': 'u1', 'name': 'Afi DOSSOU', 'username': 'afi', 'email': 'afi@x.bj', 'role': 'caissier', 'role_label': 'Caissière POS'},
            'must_change_password': mustChange,
          },
        ),
      );
      return;
    }
    if (options.path == '/api/auth/password') {
      corpsChangement = options.data as Map<String, dynamic>;
      if (refusChangement != null) {
        handler.reject(DioException(requestOptions: options, response: refusChangement, type: DioExceptionType.badResponse));
        return;
      }
      handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {'message': 'Mot de passe mis à jour avec succès.'}));
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: const {}));
  }
}

/// Laisse le client HTTP feint répondre : sous `testWidgets` l'horloge est factice, c'est `pump` qui fait avancer les
/// minuteurs et les microtâches du client (un `await` direct dans le corps du test ne se résoudrait jamais).
Future<void> laisserPasser(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  const moi = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  String uuid(String graine) => graine.padRight(36, '0');
  final sansDepotLaravel = Directory(dossierLaravel).existsSync() ? null : 'SAUT : dépôt Laravel absent ($dossierLaravel)';

  // ───────────────────────── 1. Écran de connexion ─────────────────────────
  group('écran de connexion', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = AuthService(client: Dio(), deviceName: 'poste', coffre: CoffreMemoire());
      await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth, onConnecte: () {})));
      await tester.pump();
    }

    testWidgets('⚠️ plus de « Mot de passe oublié ? » : le texte NON cliquable « Contactez l\'administrateur » le remplace', (tester) async {
      await afficher(tester);

      expect(find.text('Mot de passe oublié ?'), findsNothing);
      expect(find.text('Mot de passe oublié'), findsNothing);
      final texte = find.byKey(const Key('login-contacter-administrateur'));
      expect(texte, findsOneWidget);
      expect(find.text("Contactez l'administrateur"), findsOneWidget);

      // NON cliquable : ni bouton ni zone tactile autour du texte, et aucun dialogue ne s'ouvre au toucher.
      expect(find.ancestor(of: texte, matching: find.byType(TextButton)), findsNothing);
      expect(find.ancestor(of: texte, matching: find.byType(InkWell)), findsNothing);
      expect(find.ancestor(of: texte, matching: find.byType(GestureDetector)), findsNothing);
      await tester.tap(texte);
      await tester.pump();
      expect(find.byType(Dialog), findsNothing);
      // « Se souvenir de moi » reste à sa place.
      expect(find.text('Se souvenir de moi'), findsOneWidget);
    });

    test('⚠️ la source n\'a plus ni la fenêtre ni le texte de l\'ancien lien', () {
      final source = File('lib/features/auth/login_screen.dart').readAsStringSync();
      expect(source, isNot(contains('_DialogueMotDePasseOublie')));
      expect(source, isNot(contains('Mot de passe oublié')));
      expect(source, contains("Contactez l'administrateur"));
      // « PIN oublié ? » du verrou reste inchangé.
      expect(File('lib/features/verrou/ecran_verrou.dart').readAsStringSync(), contains('PIN oublié ?'));
    });

    test('parité : le Blade de connexion porte les MÊMES mots, sans lien ni fenêtre', () {
      final blade = _lire('resources/views/livewire/auth/login.blade.php');
      expect(blade, contains("Contactez l'administrateur"));
      expect(blade, isNot(contains('Mot de passe oublié')));
      expect(blade, isNot(contains('forgot-password')));
      expect(File('lib/features/auth/login_screen.dart').readAsStringSync(), contains("Contactez l'administrateur"));
    }, skip: sansDepotLaravel);
  });

  // ───────────────────────── 2. Geste administrateur ─────────────────────────
  group('dépôt', () {
    late AppDatabase db;
    late CoffreMemoire coffre;
    late ParametresGenerauxRepository depot;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      coffre = CoffreMemoire();
      depot = ParametresGenerauxRepository(database: db, identifiantPoste: 'poste-test', coffre: coffre);
      await db.into(db.rolesApplicatifs).insert(RolesApplicatifsCompanion.insert(id: uuid('r-caissier'), name: 'caissier'));
      Future<void> ligne(String id, String nom, String identifiant, {bool actif = true}) => db.into(db.utilisateurs).insert(
        UtilisateursCompanion.insert(
          id: id,
          deviceId: 'serveur',
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: const Value(SyncStatus.synced),
          name: nom,
          username: Value(identifiant),
          email: Value('$identifiant@fermeolouwachegoun.com'),
          role: const Value('caissier'),
          isActive: Value(actif),
        ),
      );
      await ligne(moi, 'Directeur', 'admin');
      await ligne(uuid('afi'), 'Afi DOSSOU', 'afi');
      await ligne(uuid('archive'), 'Ancien', 'ancien', actif: false);
    });
    tearDown(() async => db.close());

    Future<Utilisateur> compte(String id) => (db.select(db.utilisateurs)..where((t) => t.id.equals(id))).getSingle();

    Future<Map<String, String>> refus(Future<void> Function() geste) async {
      try {
        await geste();
      } on RefusSaisieUtilisateur catch (e) {
        return e.champs;
      }
      fail('accepté');
    }

    test('⚠️⚠️ le temporaire attend au COFFRE (jamais en base) ; le compte passe pending avec le drapeau', () async {
      await depot.reinitialiserMotDePasseUtilisateur(uuid('afi'), 'Temp#Ferme2026', idConnecte: moi);

      final u = await compte(uuid('afi'));
      expect(u.syncStatus, SyncStatus.pending);
      expect(u.mustChangePassword, isTrue);
      expect(u.deviceId, 'poste-test');
      expect(await coffre.read(key: SyncEngine.cleMotDePasse(uuid('afi'))), 'Temp#Ferme2026');
      expect(await coffre.read(key: SyncEngine.cleMotDePasseTemporaire(uuid('afi'))), '1');
      final brut = await db.customSelect("SELECT * FROM utilisateurs WHERE id = '${uuid('afi')}'").getSingle();
      expect(brut.data.values.map((v) => '$v').any((v) => v.contains('Temp#Ferme2026')), isFalse, reason: 'le mot de passe ne touche pas SQLite');
    });

    test('⚠️ son propre compte est refusé (message du serveur), rien n\'est écrit', () async {
      final champs = await refus(() => depot.reinitialiserMotDePasseUtilisateur(moi, 'Temp#Ferme2026', idConnecte: moi));

      expect(champs, {'': 'Vous ne pouvez pas réinitialiser votre propre mot de passe : utilisez Mon Profil.'});
      expect((await compte(moi)).mustChangePassword, isFalse);
      expect((await compte(moi)).syncStatus, SyncStatus.synced);
      expect(coffre.contenu, isEmpty);
    });

    test('un compte archivé est refusé ; un mot de passe faible aussi (politique de création)', () async {
      expect(
        await refus(() => depot.reinitialiserMotDePasseUtilisateur(uuid('archive'), 'Temp#Ferme2026', idConnecte: moi)),
        {'': 'Ce compte est archivé : réactivez-le avant de réinitialiser son mot de passe.'},
      );
      for (final faible in ['', '12345678', 'motdepasse', 'Court#1']) {
        final champs = await refus(() => depot.reinitialiserMotDePasseUtilisateur(uuid('afi'), faible, idConnecte: moi));
        expect(champs.keys, ['motDePasse'], reason: 'faible : « $faible »');
      }
      expect((await compte(uuid('afi'))).mustChangePassword, isFalse);
      expect(coffre.contenu, isEmpty);
    });

    test('une modification ordinaire avec mot de passe remplace une réinitialisation en attente (marqueur effacé)', () async {
      await depot.reinitialiserMotDePasseUtilisateur(uuid('afi'), 'Temp#Ferme2026', idConnecte: moi);

      await depot.enregistrerUtilisateur(
        id: uuid('afi'), nom: 'Afi DOSSOU', identifiant: 'afi', email: 'afi@fermeolouwachegoun.com', role: 'caissier', motDePasse: 'Autre#Mdp2026',
      );

      expect(await coffre.read(key: SyncEngine.cleMotDePasse(uuid('afi'))), 'Autre#Mdp2026');
      expect(await coffre.read(key: SyncEngine.cleMotDePasseTemporaire(uuid('afi'))), isNull);
    });

    test('parité : les messages sont ceux de `SaisieUtilisateurAction` (lus dans le PHP)', () {
      final php = _lire('app/Actions/SaisieUtilisateurAction.php');
      expect(php, contains("'${ParametresGenerauxRepository.messagePropreReinitialisation}'"));
      expect(php, contains('"${ParametresGenerauxRepository.messageCompteArchiveReinitialisation}"'));
      final web = _lire('resources/views/livewire/parametres/gestion-utilisateurs.blade.php');
      for (final mot in ['Réinitialiser le mot de passe', 'Mot de passe temporaire *', 'Mot de passe à changer', 'Réinitialiser']) {
        expect(web, contains(mot), reason: mot);
      }
      expect(_lire('app/Livewire/Parametres/GestionUtilisateurs.php'), contains('Mot de passe réinitialisé : le compte devra le changer à sa prochaine connexion.'));
    }, skip: sansDepotLaravel);
  });

  // ───────────────────────── 3. Moteur ─────────────────────────
  group('moteur', () {
    late AppDatabase db;
    late _Serveur serveur;
    late CoffreMemoire coffre;
    late SyncEngine moteur;
    late ParametresGenerauxRepository depot;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      serveur = _Serveur();
      coffre = CoffreMemoire();
      moteur = SyncEngine(
        database: db,
        client: Dio()..interceptors.add(serveur),
        deviceId: 'poste-test',
        connectivity: _Connectivite(),
        maintenant: () => DateTime(2026, 10, 29, 14),
        coffre: coffre,
      );
      depot = ParametresGenerauxRepository(database: db, identifiantPoste: 'poste-test', coffre: coffre);
      await db.into(db.rolesApplicatifs).insert(RolesApplicatifsCompanion.insert(id: uuid('r-caissier'), name: 'caissier'));
      await db.into(db.utilisateurs).insert(
        UtilisateursCompanion.insert(
          id: uuid('afi'), deviceId: 'serveur', updatedAt: DateTime(2026, 1, 1), syncStatus: const Value(SyncStatus.synced),
          name: 'Afi DOSSOU', username: const Value('afi'), email: const Value('afi@fermeolouwachegoun.com'), role: const Value('caissier'),
        ),
      );
    });
    tearDown(() async => db.close());

    Future<Utilisateur> compte(String id) => (db.select(db.utilisateurs)..where((t) => t.id.equals(id))).getSingle();

    test('⚠️⚠️ l\'envoi porte `reset_password: true` avec le temporaire UNE fois ; acquitté, le coffre est vidé', () async {
      await depot.reinitialiserMotDePasseUtilisateur(uuid('afi'), 'Temp#Ferme2026', idConnecte: moi);

      await moteur.synchroniser();

      final envoye = (serveur.envois.single['users'] as List).single as Map;
      expect(envoye['id'], uuid('afi'));
      expect(envoye['password'], 'Temp#Ferme2026');
      expect(envoye['reset_password'], isTrue);
      expect(envoye['is_active'], isTrue);
      expect((await compte(uuid('afi'))).syncStatus, SyncStatus.synced);
      expect(await coffre.read(key: SyncEngine.cleMotDePasse(uuid('afi'))), isNull);
      expect(await coffre.read(key: SyncEngine.cleMotDePasseTemporaire(uuid('afi'))), isNull);
    });

    test('une modification ordinaire n\'envoie jamais `reset_password`', () async {
      await depot.enregistrerUtilisateur(
        id: uuid('afi'), nom: 'Afi D.', identifiant: 'afi', email: 'afi@fermeolouwachegoun.com', role: 'caissier', motDePasse: 'Autre#Mdp2026',
      );

      await moteur.synchroniser();

      final envoye = (serveur.envois.single['users'] as List).single as Map;
      expect(envoye['password'], 'Autre#Mdp2026');
      expect(envoye.containsKey('reset_password'), isFalse);
    });

    test('⚠️ le tirage sert le DRAPEAU (jamais le mot de passe) et n\'écrase pas une réinitialisation en attente', () async {
      serveur.tirage = {
        'server_time': '2026-10-29T12:00:00Z',
        'users': [
          {'id': uuid('afi'), 'name': 'Afi DOSSOU', 'username': 'afi', 'email': 'afi@fermeolouwachegoun.com', 'role': 'caissier', 'is_active': true, 'must_change_password': true, 'updated_at': '2026-10-29T11:00:00+01:00'},
          {'id': uuid('autre'), 'name': 'Comptable', 'username': 'compta', 'email': 'compta@fermeolouwachegoun.com', 'role': 'comptable', 'is_active': true, 'updated_at': '2026-10-29T11:00:00+01:00'},
        ],
      };
      await moteur.synchroniser();
      expect((await compte(uuid('afi'))).mustChangePassword, isTrue, reason: 'le drapeau descend');
      expect((await compte(uuid('autre'))).mustChangePassword, isFalse, reason: 'absent d\'un serveur ancien = faux');
      final colonnes = (await db.customSelect('PRAGMA table_info(utilisateurs)').get()).map((c) => c.read<String>('name')).toSet();
      expect(colonnes.any((c) => c.contains('password') && c != 'must_change_password'), isFalse, reason: 'aucune colonne de mot de passe');

      // Réinitialisation en attente : un tirage où le drapeau est faux ne l'écrase pas.
      await depot.reinitialiserMotDePasseUtilisateur(uuid('autre'), 'Temp#Ferme2026', idConnecte: moi);
      serveur.tirage = {
        'server_time': '2026-10-29T12:30:00Z',
        'users': [
          {'id': uuid('autre'), 'name': 'ÉCRASÉ', 'username': 'compta', 'email': 'compta@fermeolouwachegoun.com', 'role': 'comptable', 'is_active': true, 'must_change_password': false, 'updated_at': '2026-10-29T12:00:00+01:00'},
        ],
      };
      await moteur.synchroniser();
      // (l'envoi a eu lieu avant le tirage : la ligne est acquittée, le tirage suit le serveur)
      expect(serveur.envois.any((e) => (e['users'] as List?)?.any((u) => (u as Map)['reset_password'] == true) ?? false), isTrue);
    });
  });

  // ───────────────────────── 4. Écran Gestion Utilisateurs ─────────────────────────
  group('écran Gestion Utilisateurs', () {
    late AppDatabase db;
    late CoffreMemoire coffre;
    late ParametresGenerauxRepository depot;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      coffre = CoffreMemoire();
      depot = ParametresGenerauxRepository(database: db, identifiantPoste: 'poste-test', coffre: coffre);
      await db.into(db.rolesApplicatifs).insert(RolesApplicatifsCompanion.insert(id: uuid('r-caissier'), name: 'caissier'));
      Future<void> ligne(String id, String nom, String identifiant, {bool drapeau = false}) => db.into(db.utilisateurs).insert(
        UtilisateursCompanion.insert(
          id: id, deviceId: 'serveur', updatedAt: DateTime(2026, 1, 1), syncStatus: const Value(SyncStatus.synced),
          name: nom, username: Value(identifiant), email: Value('$identifiant@fermeolouwachegoun.com'), role: const Value('caissier'),
          mustChangePassword: Value(drapeau),
        ),
      );
      await ligne(moi, 'Directeur', 'admin');
      await ligne(uuid('afi'), 'Afi DOSSOU', 'afi');
      await ligne(uuid('kossi'), 'Kossi', 'kossi', drapeau: true);
    });
    tearDown(() async {
      await db.close();
      ToastAgri.toutRetirer();
    });

    Future<void> attendre(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1700, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ParametresGenerauxScreen(depot: depot, idUtilisateurConnecte: moi)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('onglet-parametres-generaux-Gestion Utilisateurs')));
      await tester.tap(find.byKey(const Key('onglet-parametres-generaux-Gestion Utilisateurs')));
      await tester.pumpAndSettle();
    }

    // Lignes triées par nom : « Afi DOSSOU » (0), « Directeur » (1), « Kossi » (2).
    testWidgets('⚠️ le geste « Réinitialiser le mot de passe » : la fenêtre du Blade, puis un compte pending au drapeau levé', (tester) async {
      await afficher(tester);

      expect(find.byKey(const Key('utilisateur-mdp-a-changer-2')), findsOneWidget, reason: 'le drapeau descendu s\'affiche');
      expect(find.text('Mot de passe à changer'), findsOneWidget);
      expect(find.byKey(const Key('utilisateur-mdp-a-changer-0')), findsNothing);

      await tester.tap(find.byKey(const Key('utilisateur-reinitialiser-0')));
      await tester.pumpAndSettle();
      expect(find.text('Réinitialiser le mot de passe'), findsOneWidget);
      expect(find.text('MOT DE PASSE TEMPORAIRE *'), findsOneWidget);

      // Faible : refus champ par champ, rien n'est écrit.
      await tester.enterText(find.byKey(const Key('reinitialisation-mot-de-passe')), '12345678');
      await tester.tap(find.text('Réinitialiser').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('doit contenir au moins'), findsOneWidget);
      expect(coffre.contenu, isEmpty);

      await tester.enterText(find.byKey(const Key('reinitialisation-mot-de-passe')), 'Temp#Ferme2026');
      await tester.tap(find.text('Réinitialiser').last);
      await attendre(tester);

      final u = await (db.select(db.utilisateurs)..where((t) => t.id.equals(uuid('afi')))).getSingle();
      expect(u.syncStatus, SyncStatus.pending);
      expect(u.mustChangePassword, isTrue);
      expect(await coffre.read(key: SyncEngine.cleMotDePasse(uuid('afi'))), 'Temp#Ferme2026');
      expect(find.byKey(const Key('utilisateur-mdp-a-changer-0')), findsOneWidget);
    });

    testWidgets('⚠️ son propre compte : refus sur l\'écran, avec le message français, sans fenêtre', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('utilisateur-reinitialiser-1')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('MOT DE PASSE TEMPORAIRE *'), findsNothing);
      expect(find.text('Vous ne pouvez pas réinitialiser votre propre mot de passe : utilisez Mon Profil.'), findsOneWidget);
      expect(coffre.contenu, isEmpty);
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));
    });
  });

  // ───────────────────────── 5. Changement obligatoire ─────────────────────────
  group('changement de mot de passe obligatoire', () {
    late CoffreMemoire coffre;
    late _ServeurAuth serveur;
    late AuthService auth;

    setUp(() {
      coffre = CoffreMemoire();
      serveur = _ServeurAuth();
      auth = AuthService(client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur), deviceName: 'poste', coffre: coffre);
    });

    test('la connexion lit `must_change_password` et le garde au coffre (une reprise de session le retrouve)', () async {
      final session = await auth.connecter(identifiant: 'afi', motDePasse: 'Temp#Ferme2026');
      expect(session.doitChangerMotDePasse, isTrue);

      final autre = AuthService(client: Dio(BaseOptions(baseUrl: 'http://serveur-feint')), deviceName: 'poste', coffre: coffre);
      expect(await autre.reprendreSession(), isTrue);
      expect(autre.utilisateur!.doitChangerMotDePasse, isTrue);

      // Un serveur ancien (sans la clé) : faux.
      serveur.mustChange = false;
      expect((await auth.connecter(identifiant: 'afi', motDePasse: 'x')).doitChangerMotDePasse, isFalse);
    });

    test('un changement réussi lève le drapeau, y compris dans la session conservée', () async {
      await auth.connecter(identifiant: 'afi', motDePasse: 'Temp#Ferme2026');

      await auth.changerMotDePasse(ancien: 'Temp#Ferme2026', nouveau: 'MonSecret2026', confirmation: 'MonSecret2026');

      expect(auth.utilisateur!.doitChangerMotDePasse, isFalse);
      expect(serveur.corpsChangement, {'current_password': 'Temp#Ferme2026', 'new_password': 'MonSecret2026', 'new_password_confirmation': 'MonSecret2026'});
      final autre = AuthService(client: Dio(), deviceName: 'poste', coffre: coffre);
      await autre.reprendreSession();
      expect(autre.utilisateur!.doitChangerMotDePasse, isFalse);
    });

    Future<void> afficher(WidgetTester tester, {VoidCallback? onChange, VoidCallback? onDeconnecte}) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => auth.connecter(identifiant: 'afi', motDePasse: 'Temp#Ferme2026'));
      await tester.pumpWidget(
        MaterialApp(home: EcranChangementMotDePasseObligatoire(auth: auth, onChange: onChange ?? () {}, onDeconnecte: onDeconnecte ?? () {})),
      );
      await tester.pump();
    }

    testWidgets('⚠️ l\'écran porte les textes du Blade et envoie le temporaire + le nouveau mot de passe', (tester) async {
      var fait = false;
      await afficher(tester, onChange: () => fait = true);

      for (final texte in [
        'Changement de mot de passe obligatoire',
        "Un administrateur vous a donné un mot de passe temporaire. Choisissez maintenant votre propre mot de passe pour accéder à l'application.",
        'MOT DE PASSE TEMPORAIRE',
        'NOUVEAU MOT DE PASSE',
        'CONFIRMER LE NOUVEAU MOT DE PASSE',
        'ENREGISTRER LE MOT DE PASSE',
        'Se déconnecter',
      ]) {
        expect(find.text(texte), findsOneWidget, reason: texte);
      }

      await tester.enterText(find.byKey(const Key('changement-temporaire')), 'Temp#Ferme2026');
      await tester.enterText(find.byKey(const Key('changement-nouveau')), 'MonSecret2026');
      await tester.enterText(find.byKey(const Key('changement-confirmation')), 'MonSecret2026');
      await tester.tap(find.byKey(const Key('bouton-changement-mot-de-passe')));
      await laisserPasser(tester);

      expect(serveur.corpsChangement!['current_password'], 'Temp#Ferme2026');
      expect(fait, isTrue);
    });

    testWidgets('une confirmation différente, un temporaire vide et un refus du serveur sont dits sans rien envoyer de faux', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('bouton-changement-mot-de-passe')));
      await tester.pump();
      expect(find.text('Le mot de passe temporaire est obligatoire.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('changement-temporaire')), 'Temp#Ferme2026');
      await tester.enterText(find.byKey(const Key('changement-nouveau')), 'MonSecret2026');
      await tester.enterText(find.byKey(const Key('changement-confirmation')), 'Autre');
      await tester.tap(find.byKey(const Key('bouton-changement-mot-de-passe')));
      await tester.pump();
      expect(find.text('La confirmation ne correspond pas au mot de passe saisi.'), findsOneWidget);
      expect(serveur.corpsChangement, isNull);

      serveur.refusChangement = Response<dynamic>(
        requestOptions: RequestOptions(path: '/api/auth/password'),
        statusCode: 422,
        data: {'errors': {'new_password': ['Le nouveau mot de passe doit être différent du mot de passe temporaire.']}},
      );
      await tester.enterText(find.byKey(const Key('changement-confirmation')), 'MonSecret2026');
      await tester.tap(find.byKey(const Key('bouton-changement-mot-de-passe')));
      await laisserPasser(tester);
      expect(find.text('Le nouveau mot de passe doit être différent du mot de passe temporaire.'), findsOneWidget);
      expect(auth.utilisateur!.doitChangerMotDePasse, isTrue);
    });

    testWidgets('« Se déconnecter » ramène à la connexion', (tester) async {
      var retour = false;
      await afficher(tester, onDeconnecte: () => retour = true);

      await tester.tap(find.byKey(const Key('changement-se-deconnecter')));
      await laisserPasser(tester);

      expect(retour, isTrue);
      expect(auth.utilisateur, isNull);
    });

    test('parité : les libellés sont ceux du Blade', () {
      final blade = _lire('resources/views/livewire/auth/changement-mot-de-passe-obligatoire.blade.php');
      for (final texte in [
        'Changement de mot de passe obligatoire',
        "Un administrateur vous a donné un mot de passe temporaire. Choisissez maintenant votre propre mot de passe pour accéder à l'application.",
        'MOT DE PASSE TEMPORAIRE',
        'NOUVEAU MOT DE PASSE',
        'CONFIRMER LE NOUVEAU MOT DE PASSE',
        'Enregistrer le mot de passe',
        'Se déconnecter',
        'Min. 8 caractères, 1 majuscule, 1 chiffre',
      ]) {
        expect(blade, contains(texte), reason: texte);
      }
      final poste = File('lib/features/auth/ecran_changement_mot_de_passe.dart').readAsStringSync();
      expect(poste, contains('ENREGISTRER LE MOT DE PASSE'));
      expect(poste, contains('Min. 8 caractères, 1 majuscule, 1 chiffre'));
      final livewire = _lire('app/Livewire/Auth/ChangementMotDePasseObligatoire.php');
      expect(livewire, contains('Le mot de passe temporaire est obligatoire.'));
      expect(livewire, contains('La confirmation ne correspond pas au mot de passe saisi.'));
    }, skip: sansDepotLaravel);
  });

  // ───────────────────────── 6. Porte de session ─────────────────────────
  group('porte de session', () {
    const sentinelle = 'DONNEES-DE-LA-FERME';
    late CoffreMemoire coffre;
    late _ServeurAuth serveur;
    late AuthService auth;
    late VerrouLocal verrou;

    setUp(() {
      coffre = CoffreMemoire();
      serveur = _ServeurAuth();
      auth = AuthService(client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur), deviceName: 'poste', coffre: coffre);
      verrou = VerrouLocal(coffre: coffre, horloge: () => DateTime.utc(2026, 10, 29, 8), alea: Random(3), iterations: 20);
    });

    Future<void> monter(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PorteSession(
            auth: auth,
            verrou: verrou,
            ecranConnexion: (onConnecte) => Scaffold(
              body: TextButton(
                key: const Key('faux-connexion'),
                onPressed: () async {
                  await auth.connecter(identifiant: 'afi', motDePasse: 'Temp#Ferme2026');
                  onConnecte();
                },
                child: const Text('connexion'),
              ),
            ),
            application: (verrouiller, onDeconnecte) => const Scaffold(body: Text(sentinelle)),
          ),
        ),
      );
      await laisserPasser(tester);
      await laisserPasser(tester);
    }

    testWidgets('⚠️⚠️ connecté avec un temporaire : l\'écran de changement passe AVANT le PIN et l\'accueil, qui n\'est jamais monté', (tester) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('faux-connexion')));
      await laisserPasser(tester);
      await laisserPasser(tester);
      expect(find.text('Changement de mot de passe obligatoire'), findsOneWidget);
      expect(find.text(sentinelle), findsNothing);

      await tester.enterText(find.byKey(const Key('changement-temporaire')), 'Temp#Ferme2026');
      await tester.enterText(find.byKey(const Key('changement-nouveau')), 'MonSecret2026');
      await tester.enterText(find.byKey(const Key('changement-confirmation')), 'MonSecret2026');
      await tester.tap(find.byKey(const Key('bouton-changement-mot-de-passe')));
      await laisserPasser(tester);
      await laisserPasser(tester);

      // Changé : le poste passe à la suite normale (définition du PIN d'un poste neuf), toujours pas l'accueil.
      expect(find.text('Changement de mot de passe obligatoire'), findsNothing);
      expect(find.text(sentinelle), findsNothing);
      expect(auth.utilisateur!.doitChangerMotDePasse, isFalse);
    });

    testWidgets('sans temporaire : pas d\'écran de changement', (tester) async {
      serveur.mustChange = false;
      await monter(tester);

      await tester.tap(find.byKey(const Key('faux-connexion')));
      await laisserPasser(tester);
      await laisserPasser(tester);

      expect(find.text('Changement de mot de passe obligatoire'), findsNothing);
    });

    testWidgets('une session restaurée au drapeau levé repasse par le changement après le PIN', (tester) async {
      coffre.contenu['agrierp.token'] = 'jeton';
      coffre.contenu['agrierp.user'] = jsonEncode({
        'id': 'u1', 'name': 'Afi', 'username': 'afi', 'email': 'a@x.bj', 'role': 'caissier', 'role_label': 'Caissière POS',
        'must_change_password': true,
      });
      await monter(tester);

      // Sans PIN défini : « définition » d'abord ; le drapeau est lu sur la session reprise.
      expect(auth.utilisateur!.doitChangerMotDePasse, isTrue);
      expect(find.text(sentinelle), findsNothing);
    });
  });
}
