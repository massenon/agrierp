import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coffre_memoire.dart';

/// Ticket UT-1 — LES COMPTES UTILISATEURS S'ÉCRIVENT AU POSTE (demande du client du 27/10/2026).
///
/// Créés, modifiés, archivés, réactivés hors ligne en `pending`, avec les règles de `SaisieUtilisateurAction` ; le mot
/// de passe attend au COFFRE (jamais en base) et part UNE fois ; l'envoi est acquitté ; un refus devient `conflict` et
/// se relance ; le tirage n'écrase jamais un compte en attente.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-27T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];
  final refus = <String, Map<String, String>>{};

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
                  'accepted': [
                    for (final e in value)
                      if (e is Map && e['id'] is String && !(refus[key]?.containsKey(e['id']) ?? false)) e['id'],
                  ],
                  'rejected': [
                    for (final e in value)
                      if (e is Map && e['id'] is String && (refus[key]?.containsKey(e['id']) ?? false))
                        {'id': e['id'], 'reason': refus[key]![e['id']]},
                  ],
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

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late ParametresGenerauxRepository depot;
  late CoffreMemoire coffre;

  String uuid(String graine) => graine.padRight(36, '0');
  const moi = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    coffre = CoffreMemoire();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 27, 14),
      coffre: coffre,
    );
    depot = ParametresGenerauxRepository(database: db, identifiantPoste: 'poste-test', coffre: coffre);
    for (final nom in ['admin', 'comptable', 'caissier', 'animalier']) {
      await db.into(db.rolesApplicatifs).insert(RolesApplicatifsCompanion.insert(id: uuid('r-$nom'), name: nom));
    }
    await db.into(db.utilisateurs).insert(
      UtilisateursCompanion.insert(
        id: moi,
        deviceId: 'serveur',
        updatedAt: DateTime(2026, 1, 1),
        syncStatus: const Value(SyncStatus.synced),
        name: 'Directeur',
        username: const Value('admin'),
        email: const Value('dg@fermeolouwachegoun.com'),
        role: const Value('admin'),
      ),
    );
  });
  tearDown(() async => db.close());

  Future<Utilisateur> compte(String id) => (db.select(db.utilisateurs)..where((t) => t.id.equals(id))).getSingle();

  Future<String> creer({String identifiant = 'afi', String email = 'afi@fermeolouwachegoun.com', String mdp = 'Caisse#2026', String role = 'caissier'}) =>
      depot.enregistrerUtilisateur(nom: 'Afi DOSSOU', identifiant: identifiant, email: email, role: role, motDePasse: mdp);

  group('dépôt', () {
    test('⚠️⚠️ un compte créé est pending, actif, et son mot de passe est au COFFRE — jamais en base', () async {
      final id = await creer();

      final u = await compte(id);
      expect(u.syncStatus, SyncStatus.pending);
      expect(u.deviceId, 'poste-test');
      expect(u.isActive, isTrue);
      expect(u.role, 'caissier');
      expect(await coffre.read(key: SyncEngine.cleMotDePasse(id)), 'Caisse#2026');
      final brut = await db.customSelect("SELECT * FROM utilisateurs WHERE id = '$id'").getSingle();
      expect(brut.data.values.map((v) => '$v').any((v) => v.contains('Caisse#2026')), isFalse, reason: 'le mot de passe ne touche pas SQLite');
    });

    test('les règles du web, champ par champ, avec ses messages', () async {
      Future<Map<String, String>> refus(Future<void> Function() geste) async {
        try {
          await geste();
        } on RefusSaisieUtilisateur catch (e) {
          return e.champs;
        }
        fail('accepté');
      }

      final vide = await refus(() => depot.enregistrerUtilisateur(nom: ' ', identifiant: '', email: '', role: '', motDePasse: ''));
      expect(vide, {
        'nom': 'Le champ nom est obligatoire.',
        'identifiant': "Le champ nom d'utilisateur est obligatoire.",
        'email': 'Le champ courriel est obligatoire.',
        'role': 'Le champ rôle est obligatoire.',
        'motDePasse': 'Le champ mot de passe est obligatoire.',
      });
      // ⚠️ Pas d'arobase dans l'identifiant : la connexion le chercherait parmi les adresses.
      expect((await refus(() => creer(identifiant: 'afi@ferme')))['identifiant'], "Le format du champ nom d'utilisateur n'est pas valide.");
      expect((await refus(() => creer(identifiant: 'ab')))['identifiant'], "Le champ nom d'utilisateur doit contenir au moins 3 caractères.");
      expect((await refus(() => creer(identifiant: 'admin')))['identifiant'], "La valeur du champ nom d'utilisateur est déjà utilisée.");
      expect((await refus(() => creer(email: 'dg@fermeolouwachegoun.com')))['email'], 'La valeur du champ courriel est déjà utilisée.');
      expect((await refus(() => creer(email: 'pas-un-mail')))['email'], 'Le champ courriel doit être une adresse courriel valide.');
      expect((await refus(() => creer(role: 'auditeur')))['role'], "La valeur sélectionnée pour le champ rôle n'existe pas.");
      // ⚠️ 14.65 : « 12345678 » n'est pas un mot de passe.
      expect((await refus(() => creer(mdp: '12345678')))['motDePasse'], 'Le champ mot de passe doit contenir au moins une lettre.');
      expect((await refus(() => creer(mdp: 'Caisse#')))['motDePasse'], 'Le champ mot de passe doit contenir au moins 8 caractères.');
      expect((await refus(() => creer(mdp: 'Caisse#ab')))['motDePasse'], 'Le champ mot de passe doit contenir au moins un chiffre.');
      expect((await refus(() => creer(mdp: 'Caisse2026')))['motDePasse'], 'Le champ mot de passe doit contenir au moins un symbole.');
      expect((await db.select(db.utilisateurs).get()).length, 1, reason: 'rien n\'est écrit sur un refus');
    });

    test('modifier sans mot de passe le conserve ; avec, il remplace celui du coffre', () async {
      final id = await creer();
      await moteur.synchroniser();
      expect(await coffre.read(key: SyncEngine.cleMotDePasse(id)), isNull, reason: 'acquitté : effacé');

      await depot.enregistrerUtilisateur(id: id, nom: 'Afi DOSSOU-KPADÉ', identifiant: 'afi', email: 'afi@fermeolouwachegoun.com', role: 'comptable', motDePasse: '');
      expect((await compte(id)).syncStatus, SyncStatus.pending);
      expect((await compte(id)).role, 'comptable');
      expect(await coffre.read(key: SyncEngine.cleMotDePasse(id)), isNull);

      await depot.enregistrerUtilisateur(id: id, nom: 'Afi DOSSOU-KPADÉ', identifiant: 'afi', email: 'afi@fermeolouwachegoun.com', role: 'comptable', motDePasse: 'Compta#2027');
      expect(await coffre.read(key: SyncEngine.cleMotDePasse(id)), 'Compta#2027');
    });

    test('⚠️ archiver son propre compte est refusé (message du web) ; archiver puis réactiver un autre passe', () async {
      await expectLater(
        depot.archiverUtilisateur(moi, idConnecte: moi),
        throwsA(isA<RefusSaisieUtilisateur>().having((e) => e.champs[''], 'message', 'Vous ne pouvez pas archiver votre propre compte.')),
      );
      expect((await compte(moi)).syncStatus, SyncStatus.synced);

      final id = await creer();
      await moteur.synchroniser();
      await depot.archiverUtilisateur(id, idConnecte: moi);
      var u = await compte(id);
      expect(u.isActive, isFalse);
      expect(u.syncStatus, SyncStatus.pending);

      await moteur.synchroniser();
      await depot.archiverUtilisateur(id, idConnecte: moi);
      expect((await compte(id)).syncStatus, SyncStatus.synced, reason: 'déjà archivé : rien n\'est réécrit');

      await depot.reactiverUtilisateur(id);
      u = await compte(id);
      expect(u.isActive, isTrue);
      expect(u.syncStatus, SyncStatus.pending);
    });
  });

  group('moteur', () {
    test('⚠️⚠️ l\'envoi part sous les clés de `pushUsers` avec le mot de passe UNE fois ; acquitté, le coffre est vidé', () async {
      final id = await creer();

      await moteur.synchroniser();

      final envoye = (serveur.envois.single['users'] as List).single as Map;
      expect(envoye, {
        'id': id, 'name': 'Afi DOSSOU', 'username': 'afi', 'email': 'afi@fermeolouwachegoun.com', 'role': 'caissier',
        'is_active': true, 'password': 'Caisse#2026', 'device_id': 'poste-test',
      });
      expect((await compte(id)).syncStatus, SyncStatus.synced);
      expect(await coffre.read(key: SyncEngine.cleMotDePasse(id)), isNull);

      // Modifié sans mot de passe : la clé `password` ne part pas (le serveur conserve l'actuel).
      await depot.enregistrerUtilisateur(id: id, nom: 'Afi D.', identifiant: 'afi', email: 'afi@fermeolouwachegoun.com', role: 'caissier', motDePasse: '');
      await moteur.synchroniser();
      final renvoye = (serveur.envois.last['users'] as List).single as Map;
      expect(renvoye.containsKey('password'), isFalse);
      expect(renvoye['name'], 'Afi D.');
    });

    test('un refus devient conflict avec son motif, garde le mot de passe au coffre, et se relance', () async {
      final id = await creer();
      serveur.refus['users'] = {id: "La valeur du champ nom d'utilisateur est déjà utilisée."};

      await moteur.synchroniser();

      expect((await compte(id)).syncStatus, SyncStatus.conflict);
      final conflit = (await db.select(db.syncConflicts).get()).firstWhere((c) => c.sourceTable == 'users');
      expect(conflit.reason, contains('déjà utilisée'));
      expect(await coffre.read(key: SyncEngine.cleMotDePasse(id)), 'Caisse#2026', reason: 'refusé : il repartira');

      await moteur.relancer(conflit);
      expect((await compte(id)).syncStatus, SyncStatus.pending);
    });

    test('⚠️⚠️ le tirage n\'écrase jamais un compte pending ; un compte connu et synced suit le serveur', () async {
      final local = await creer();
      serveur.tirage = {
        'server_time': '2026-10-27T12:00:00Z',
        'users': [
          {'id': local, 'name': 'ÉCRASÉ', 'username': 'x', 'email': 'x@x.bj', 'role': 'admin', 'is_active': false, 'updated_at': '2026-10-27T11:00:00+01:00'},
          {'id': moi, 'name': 'Directeur Général', 'username': 'admin', 'email': 'dg@fermeolouwachegoun.com', 'role': 'admin', 'is_active': true, 'updated_at': '2026-10-27T11:00:00+01:00'},
          {'id': uuid('u-serveur'), 'name': 'Comptable', 'username': 'compta', 'email': 'compta@fermeolouwachegoun.com', 'role': 'comptable', 'is_active': true, 'updated_at': '2026-10-27T11:00:00+01:00'},
        ],
      };
      serveur.refus['users'] = {local: 'non'};

      await moteur.synchroniser();

      expect((await compte(local)).name, 'Afi DOSSOU', reason: 'pending/conflict : intouchable');
      expect((await compte(moi)).name, 'Directeur Général');
      final recu = await compte(uuid('u-serveur'));
      expect(recu.syncStatus, SyncStatus.synced);
      expect(recu.deviceId, 'serveur');
      expect(recu.role, 'comptable');
    });
  });

  group('écran', () {
    tearDown(ToastAgri.toutRetirer);

    /// Un geste qui affiche un toast : quelques images, puis le toast est laissé s'éteindre (sinon son minuteur
    /// survit au test).
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

    testWidgets('⚠️⚠️ « Nouvel Utilisateur » : la modale du Blade crée un compte en attente d\'envoi', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('nouvel-utilisateur')));
      await tester.pumpAndSettle();
      for (final libelle in ['NOM COMPLET *', "NOM D'UTILISATEUR *", 'EMAIL *', 'RÔLE *', 'MOT DE PASSE *']) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }
      expect(find.text('Lettres, chiffres, point, tiret et souligne. Sans arobase.'), findsOneWidget);

      // Vide : les refus s'affichent champ par champ, rien n'est écrit.
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Le champ nom est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ mot de passe est obligatoire.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('utilisateur-nom')), 'Afi DOSSOU');
      await tester.enterText(find.byKey(const Key('utilisateur-identifiant')), 'afi');
      await tester.enterText(find.byKey(const Key('utilisateur-email')), 'afi@fermeolouwachegoun.com');
      await tester.tap(find.byKey(const Key('utilisateur-role')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caissier').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('utilisateur-mot-de-passe')), 'Caisse#2026');
      await tester.tap(find.text('Enregistrer'));
      await attendre(tester);

      expect(find.text('Afi DOSSOU'), findsOneWidget);
      expect(find.text('Caissière POS'), findsOneWidget);
      expect(find.text('Pas encore envoyé'), findsOneWidget);
      final cree = (await db.select(db.utilisateurs).get()).firstWhere((u) => u.username == 'afi');
      expect(cree.syncStatus, SyncStatus.pending);
      expect(await coffre.read(key: SyncEngine.cleMotDePasse(cree.id)), 'Caisse#2026');
    });

    testWidgets('archiver (confirmation) puis réactiver ; son propre compte est refusé', (tester) async {
      // ⚠️ Pas de `synchroniser()` dans un test d'écran : le moteur arme des minuteurs que `pumpAndSettle` rejoue sans fin.
      final id = await creer();
      await (db.update(db.utilisateurs)..where((t) => t.id.equals(id))).write(const UtilisateursCompanion(syncStatus: Value(SyncStatus.synced)));
      await afficher(tester);

      // Lignes triées par nom : « Afi DOSSOU » (0) puis « Directeur » (1).
      expect(find.byKey(const Key('utilisateur-archiver-0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('utilisateur-archiver-0')));
      await tester.pumpAndSettle();
      expect(find.text("Archiver l'utilisateur"), findsOneWidget);
      await tester.tap(find.text('Archiver').last);
      await attendre(tester);

      expect((await compte(id)).isActive, isFalse);
      expect(find.text('Désactivé'), findsOneWidget);
      expect(find.byKey(const Key('utilisateur-reactiver-0')), findsOneWidget);

      await tester.tap(find.byKey(const Key('utilisateur-reactiver-0')));
      await attendre(tester);
      expect((await compte(id)).isActive, isTrue);

      await tester.tap(find.byKey(const Key('utilisateur-archiver-1')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("Archiver l'utilisateur"), findsNothing, reason: 'son propre compte : pas de confirmation');
      expect(find.text('Vous ne pouvez pas archiver votre propre compte.'), findsOneWidget);
      expect((await compte(moi)).isActive, isTrue);
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));
    });
  });
}
