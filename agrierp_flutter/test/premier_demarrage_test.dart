import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/core/config/parametres_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/auth/login_screen.dart';
import 'package:agrierp/features/comptabilite/cloture_exercice_repository.dart';
import 'package:agrierp/features/demarrage/premier_demarrage_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/demarrage/premier_demarrage_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.98 — PREMIER DÉMARRAGE DU POSTE.
///
/// Un poste neuf (jamais tiré, rien en attente) montre son serveur dès la connexion, peut en changer
/// sans administrateur, puis guide la première synchronisation. Un poste en service ne peut PAS changer
/// de serveur depuis l'écran de connexion.
class _Connectivite implements Connectivity {
  _Connectivite(this.resultat);

  final ConnectivityResult resultat;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [resultat];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  /// Réponse de `GET /api/auth/me` (clé `assistant_demarrage_actif`) ; `null` = clé absente (serveur ancien).
  static bool? assistantServeur;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path.contains('auth/me')
            ? <String, dynamic>{if (assistantServeur != null) 'assistant_demarrage_actif': assistantServeur}
            : options.path.contains('push')
            ? <String, dynamic>{}
            : {'server_time': '2026-10-17T12:00:00Z'},
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late Dio client;
  late PremierDemarrageRepository depot;

  setUp(() {
    _Serveur.assistantServeur = null;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = Dio(BaseOptions(baseUrl: ParametresPoste.adresseParDefaut))..interceptors.add(_Serveur());
    depot = PremierDemarrageRepository(
      database: db,
      parametres: ParametresPoste(database: db),
      client: client,
    );
  });

  tearDown(() async => db.close());

  SyncEngine moteur({ConnectivityResult reseau = ConnectivityResult.wifi}) => SyncEngine(
    database: db,
    client: client,
    deviceId: 'poste-test',
    connectivity: _Connectivite(reseau),
    maintenant: () => DateTime(2026, 10, 17, 16),
  );

  group('dépôt', () {
    test('un poste jamais tiré et sans attente est neuf ; un tirage le fait sortir', () async {
      expect(await depot.posteNeuf(), isTrue);
      await db.noterEtatDeSynchronisation(tire: DateTime(2026, 10, 17));
      expect(await depot.posteNeuf(), isFalse);
    });

    test('module « Assistant de démarrage » : éteint par défaut, allumé depuis Paramètres, seulement pour un poste neuf', () async {
      final reglages = ParametresGenerauxRepository(database: db);
      expect(await depot.moduleActif(), isFalse);
      expect(await depot.afficherAssistant(), isFalse);

      await reglages.definirAssistant(actif: true);
      expect(await depot.moduleActif(), isTrue);
      expect((await reglages.charger()).assistantActif, isTrue);
      // La bascule attend son envoi (`pending`) : le poste n'est plus « neuf » ; une ligne déjà acquittée, si.
      expect(await depot.afficherAssistant(), isFalse);
      await (db.update(db.modulesConfig)..where((m) => m.speciesCode.equals('assistant_demarrage')))
          .write(const ModulesConfigCompanion(syncStatus: Value(SyncStatus.synced)));
      expect(await depot.afficherAssistant(), isTrue);

      await db.noterEtatDeSynchronisation(tire: DateTime(2026, 10, 17));
      expect(await depot.afficherAssistant(), isFalse);

      await reglages.definirAssistant(actif: false);
      expect((await reglages.charger()).assistantActif, isFalse);
    });

    test('poste vraiment neuf : le module est LU au serveur à la connexion, sans tirage préalable', () async {
      _Serveur.assistantServeur = true;
      expect(await depot.afficherAssistant(), isTrue);
      _Serveur.assistantServeur = false;
      expect(await depot.afficherAssistant(), isFalse);
      _Serveur.assistantServeur = true;
      await db.noterEtatDeSynchronisation(tire: DateTime(2026, 10, 17));
      expect(await depot.afficherAssistant(), isFalse, reason: 'un poste qui a déjà synchronisé n\'est plus neuf');
    });

    test('une saisie en attente suffit à ne plus être neuf', () async {
      await db.into(db.livestockDailyEntries).insert(
        LivestockDailyEntriesCompanion.insert(
          id: 'dddddddd-1510-4000-8000-000000000001',
          deviceId: 'poste-test',
          updatedAt: DateTime(2026, 10, 17),
          lotId: 'bbbbbbbb-1510-4000-8000-000000000001',
          entryDate: DateTime(2026, 10, 17),
          mort: const Value(1),
        ),
      );
      expect(await depot.posteNeuf(), isFalse);
    });

    test('poste neuf : la nouvelle adresse est normalisée ET appliquée au client partagé', () async {
      final enregistree = await depot.changerAdresse('192.168.1.10:8002/');

      expect(enregistree, 'http://192.168.1.10:8002');
      expect(client.options.baseUrl, 'http://192.168.1.10:8002');
      expect(await depot.adresse(), 'http://192.168.1.10:8002');
    });

    test('⚠️ poste en service : changer d\'adresse est refusé, rien n\'est écrit', () async {
      await db.noterEtatDeSynchronisation(tire: DateTime(2026, 10, 17));

      await expectLater(depot.changerAdresse('http://ailleurs'), throwsStateError);
      expect(client.options.baseUrl, ParametresPoste.adresseParDefaut);
      expect(await depot.adresse(), ParametresPoste.adresseParDefaut);
    });
  });

  Future<void> afficher(WidgetTester tester, Widget ecran) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ecran));
    await tester.pumpAndSettle();
  }

  group('écran de premier démarrage', () {
    testWidgets('la première synchronisation est lancée, rendue, puis « Continuer »', (tester) async {
      var termine = false;
      await afficher(
        tester,
        PremierDemarrageScreen(
          depot: depot,
          engine: moteur(),
          utilisateur: 'Directeur',
          onTermine: () => termine = true,
        ),
      );

      expect(find.textContaining(ParametresPoste.adresseParDefaut), findsOneWidget);
      expect(find.byKey(const Key('premier-continuer')), findsNothing);

      await tester.tap(find.byKey(const Key('premier-synchroniser')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('premier-compte-rendu')), findsOneWidget);
      await tester.tap(find.byKey(const Key('premier-continuer')));
      expect(termine, isTrue);
    });

    testWidgets('hors ligne : le message le dit, l\'étape reste à faire', (tester) async {
      await afficher(
        tester,
        PremierDemarrageScreen(
          depot: depot,
          engine: moteur(reseau: ConnectivityResult.none),
          utilisateur: 'Directeur',
          onTermine: () {},
        ),
      );

      await tester.tap(find.byKey(const Key('premier-synchroniser')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('premier-echec')), findsOneWidget);
      expect(find.byKey(const Key('premier-continuer')), findsNothing);
    });

    testWidgets('⚠️ CP-4 : sans exercice reçu, « Ouvrir l\'exercice AAAA » écrit la DEMANDE d\'ouverture (jamais fiscal_years)', (tester) async {
      final cloture = ClotureExerciceRepository(database: db, deviceId: 'poste-test', horloge: () => DateTime(2031, 10, 28, 9));
      await afficher(
        tester,
        PremierDemarrageScreen(
          depot: depot,
          engine: moteur(),
          utilisateur: 'Directeur',
          onTermine: () {},
          depotCloture: cloture,
          peutOuvrirExercice: true,
        ),
      );
      expect(find.byKey(const Key('premier-etape-exercice')), findsOneWidget);
      expect(find.byKey(const Key('premier-ouvrir-exercice')), findsNothing, reason: 'rien n\'est proposé avant la première synchronisation');

      await tester.tap(find.byKey(const Key('premier-synchroniser')));
      await tester.pumpAndSettle();
      expect(find.text("Ouvrir l'exercice 2031"), findsOneWidget, reason: 'l\'année du poste (heure du Bénin)');
      await tester.tap(find.byKey(const Key('premier-ouvrir-exercice')));
      await tester.pumpAndSettle();

      final d = (await db.select(db.fiscalClosureRequests).get()).single;
      expect((d.kind, d.payload), ('ouvrir_exercice', '{"year":2031}'));
      expect(await db.select(db.fiscalYears).get(), isEmpty);
      expect(find.byKey(const Key('premier-ouvrir-exercice')), findsNothing);
    });

    testWidgets('« Plus tard » ouvre l\'application sans synchroniser', (tester) async {
      var termine = false;
      await afficher(
        tester,
        PremierDemarrageScreen(
          depot: depot,
          engine: moteur(),
          utilisateur: 'Directeur',
          onTermine: () => termine = true,
        ),
      );

      await tester.tap(find.byKey(const Key('premier-plus-tard')));
      expect(termine, isTrue);
      expect(await depot.posteNeuf(), isTrue);
    });
  });

  group('écran de connexion', () {
    testWidgets('⚠️ l\'adresse du serveur ne s\'affiche ni ne se change à la connexion : elle se règle dans Paramètres > Appairage', (tester) async {
      await afficher(tester, LoginScreen(auth: AuthService(client: client, deviceName: 'poste-test'), onConnecte: () {}));

      expect(find.byKey(const Key('login-serveur')), findsNothing);
      expect(find.byKey(const Key('login-modifier-serveur')), findsNothing);
      expect(find.textContaining('Serveur :'), findsNothing);
      expect(find.text('Modifier'), findsNothing);
    });
  });
}
