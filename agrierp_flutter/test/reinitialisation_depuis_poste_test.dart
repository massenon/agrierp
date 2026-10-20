import 'dart:async';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/erreurs/message_erreur.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/parametres/onglet_reinitialisation.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:agrierp/features/parametres/reinitialisation_poste.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket R-1 (demande du client : « sur le web et le poste ») — « RÉINITIALISATION DES DONNÉES » DEPUIS LE POSTE.
///
/// Ce que ces tests verrouillent :
///  - le droit est celui du web (`manage-parametres` : l'administrateur seulement), vérifié AVANT tout appel ;
///  - hors ligne, rien n'est tenté (on ne réinitialise pas le serveur sans lui), l'écran le dit, boutons inertes ;
///  - les saisies non envoyées (`pending` ET `conflict`) des tables EFFACÉES sont comptées table par table, et
///    leur perte doit être acceptée explicitement ;
///  - après le succès du serveur, la purge est IMMÉDIATE (mécanisme 15.50 : tables d'activité vides, référentiels
///    gardés, soldes à zéro, marque notée), puis un tirage COMPLET — sans seconde purge ;
///  - sur un échec (refus du serveur, réseau), message français et RIEN n'est purgé ;
///  - aucune synchronisation ne s'intercale entre l'appel au serveur et la purge.
class _Connectivite implements Connectivity {
  bool enLigne = true;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [enLigne ? ConnectivityResult.wifi : ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Faux serveur : routes de la réinitialisation (R-1) et de la synchronisation.
class _Serveur extends Interceptor {
  _Serveur(this.db);

  final AppDatabase db;

  bool modeDemo = true;
  String? marque;

  /// Réponse forcée à `POST /api/parametres/reinitialisation` : (statut, message) ; `null` = succès.
  (int, String)? refus;
  bool reseauCoupe = false;

  /// Retient le premier tirage jusqu'à ce que le test l'ouvre.
  Completer<void>? porteDuTirage;

  final List<String> journal = [];
  final List<Map<String, dynamic>> tirages = [];
  final List<Map<String, dynamic>> envois = [];
  int? lotsAuMomentDeLAppel;

  static const marqueDuServeur = '2026-10-19T10:30:00+00:00';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final chemin = options.path;
    Response<Map<String, dynamic>> ok(Map<String, dynamic> corps) =>
        Response(requestOptions: options, statusCode: 200, data: corps);

    if (chemin == '/api/parametres/reinitialisation' && options.method == 'GET') {
      journal.add('etat');
      return handler.resolve(ok({'mode_demo_actif': modeDemo, 'mot_de_confirmation': 'REINITIALISER'}));
    }
    if (chemin == '/api/parametres/reinitialisation/mode-demo') {
      journal.add('bascule');
      modeDemo = !modeDemo;
      return handler.resolve(
        ok({
          'mode_demo_actif': modeDemo,
          'message': modeDemo
              ? "Mode démonstration activé — l'onglet de réinitialisation est accessible."
              : 'Mode démonstration désactivé.',
          'type': modeDemo ? 'warning' : 'success',
        }),
      );
    }
    if (chemin == '/api/parametres/reinitialisation') {
      journal.add('reinitialisation');
      lotsAuMomentDeLAppel = (await db.select(db.livestockLots).get()).length;
      if (reseauCoupe) {
        return handler.reject(
          DioException(requestOptions: options, type: DioExceptionType.connectionError),
        );
      }
      final r = refus;
      if (r != null) {
        return handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: options, statusCode: r.$1, data: {'message': r.$2}),
          ),
        );
      }
      marque = marqueDuServeur;
      return handler.resolve(
        ok({
          'message': 'Réinitialisation effectuée — 7 enregistrement(s) supprimé(s).',
          'total': 7,
          'data_reset_at': marque,
        }),
      );
    }
    if (chemin.contains('/sync/push')) {
      journal.add('envoi');
      envois.add(Map<String, dynamic>.from(options.data as Map));
      return handler.resolve(ok({}));
    }
    if (chemin.contains('/sync/pull')) {
      journal.add('tirage${options.queryParameters.containsKey('since') ? ' depuis' : ' complet'}');
      tirages.add(options.queryParameters);
      final porte = porteDuTirage;
      if (porte != null) {
        porteDuTirage = null;
        await porte.future;
      }
      return handler.resolve(ok({'server_time': '2026-10-19T11:00:00Z', 'data_reset_at': marque}));
    }
    return handler.resolve(ok({}));
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late _Connectivite reseau;
  late SyncEngine moteur;
  late String role;
  late ReinitialisationPoste depot;

  const lot = 'bbbbbbbb-r100-4000-8000-000000000001';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur(db);
    reseau = _Connectivite();
    final client = Dio()..interceptors.add(serveur);
    moteur = SyncEngine(
      database: db,
      client: client,
      deviceId: 'poste-bureau',
      connectivity: reseau,
      maintenant: () => DateTime(2026, 10, 19, 11),
    );
    role = 'admin';
    depot = ReinitialisationPoste(database: db, client: client, engine: moteur, role: () => role);
  });

  tearDown(() async => db.close());

  /// Activité du poste : une bande, une fiche EN ATTENTE, une vente REFUSÉE par le serveur, et un produit en
  /// attente (référentiel CONSERVÉ : il survit à la purge), un compte de trésorerie, un utilisateur.
  Future<void> activite() async {
    await db.into(db.livestockLots).insert(
      LivestockLotsCompanion.insert(
        id: lot,
        code: 'LAP-A',
        speciesId: 'esp',
        initialQuantity: const Value(20),
        currentQuantity: const Value(20),
      ),
    );
    await db.into(db.livestockDailyEntries).insert(
      LivestockDailyEntriesCompanion.insert(
        id: 'dddddddd-r100-4000-8000-000000000001',
        deviceId: 'poste-bureau',
        updatedAt: DateTime(2026, 10, 18),
        lotId: lot,
        entryDate: DateTime(2026, 10, 18),
        mort: const Value(1),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
    for (final (cle, statut) in [('1', SyncStatus.conflict), ('2', SyncStatus.synced)]) {
      await db.into(db.sales).insert(
        SalesCompanion.insert(
          id: 'vvvvvvvv-r100-4000-8000-00000000000$cle',
          deviceId: 'poste-bureau',
          updatedAt: DateTime(2026, 10, 18),
          paymentMode: 'especes',
          total: 5000,
          soldAt: DateTime(2026, 10, 18),
          syncStatus: Value(statut),
        ),
      );
    }
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: 'pppppppp-r100-4000-8000-000000000001',
        sku: 'ALI-1',
        name: 'Provende',
        categoryId: const Value('cat'),
        unit: 'sac',
        pricingMode: 'fixe',
        stockQty: const Value(40),
        syncStatus: const Value(SyncStatus.pending),
      ),
    );
    await db.into(db.treasuryAccounts).insert(
      TreasuryAccountsCompanion.insert(
        id: 'tttttttt-r100-4000-8000-000000000001',
        label: 'Caisse Principale',
        balance: const Value(250000),
      ),
    );
    await db.into(db.utilisateurs).insert(
      UtilisateursCompanion.insert(id: 'uuuuuuuu-r100-4000-8000-000000000001', name: 'Directeur'),
    );
    await db.noterEtatDeSynchronisation(tire: DateTime(2026, 10, 18));
    // Poste en service : ses resynchronisations uniques sont faites, son tirage ordinaire est incrémental
    // (`since`) — c'est ce qui distingue le tirage COMPLET qui suit la purge (curseur effacé).
    for (final cle in [
      SyncEngine.cleJournalResync,
      SyncEngine.cleJournalResyncCreation,
      SyncEngine.cleFichesResync,
      SyncEngine.cleFichesResyncCategories,
      SyncEngine.cleLignesResync,
      SyncEngine.cleRetoursResync,
      SyncEngine.cleMouvementsResync,
      SyncEngine.cleFichesResyncU10,
      SyncEngine.cleDepensesResync,
      SyncEngine.cleDepensesResyncU14,
    ]) {
      await db.into(db.appSettings).insert(AppSettingsCompanion.insert(key: cle, value: '1'));
    }
  }

  Future<int> lignes(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle()).read<int>('n');

  Future<String?> marqueNotee() async => (await (db.select(db.appSettings)
        ..where((t) => t.key.equals(SyncEngine.cleReinitialisation)))
      .getSingleOrNull())
      ?.value;

  group('dépôt', () {
    test('⚠️ droit du web : seul `manage-parametres` (administrateur) réinitialise ; refus AVANT tout appel', () async {
      await activite();
      for (final r in ['caissier', 'comptable', 'animalier', '']) {
        role = r;
        expect(depot.autorise, isFalse, reason: r);
        await expectLater(
          depot.reinitialiser('REINITIALISER'),
          throwsA(
            isA<RefusReinitialisation>().having(
              (e) => e.message,
              'message',
              'Votre rôle ne permet pas de réinitialiser les données.',
            ),
          ),
        );
      }
      role = 'admin';
      expect(depot.autorise, isTrue);
      expect(serveur.journal, isEmpty);
      expect(await lignes('livestock_lots'), 1);
    });

    test('⚠️ hors ligne : rien n est tenté, rien n est purgé, la raison est dite', () async {
      await activite();
      reseau.enLigne = false;

      await expectLater(
        depot.reinitialiser('REINITIALISER'),
        throwsA(isA<RefusReinitialisation>().having((e) => e.message, 'message', contains('Hors ligne'))),
      );
      await expectLater(depot.basculerModeDemo(), throwsA(isA<RefusReinitialisation>()));

      expect(serveur.journal, isEmpty);
      expect(await lignes('livestock_lots'), 1);
      expect(await marqueNotee(), isNull);
    });

    test('le mot de confirmation est vérifié avant l appel, avec le message du web', () async {
      await activite();

      await expectLater(
        depot.reinitialiser('reinitialiser'),
        throwsA(
          isA<RefusReinitialisation>().having((e) => e.message, 'message', 'Saisissez REINITIALISER pour confirmer.'),
        ),
      );
      expect(serveur.journal, isEmpty);
    });

    test(
      '⚠️ saisies non envoyées : comptées par table, en attente ET refusées, seulement là où la purge efface',
      () async {
        await activite();

        final s = await depot.saisiesNonEnvoyees();

        expect([for (final n in s) (n.table, n.enAttente, n.refusees)], [
          ('livestock_daily_entries', 1, 0),
          ('sales', 0, 1),
        ]);
        expect(s.map((n) => n.libelle), ["Fiches journalières d'élevage", 'Ventes']);
        // Le produit en attente est un référentiel conservé : il repartira, il n'est pas « perdu ».
        expect(s.where((n) => n.table == 'products'), isEmpty);
      },
    );

    test('chaque table envoyée que la purge efface a son libellé', () {
      expect(ReinitialisationPoste.tablesPerdues, isNotEmpty);
      for (final t in ReinitialisationPoste.tablesPerdues) {
        expect(ReinitialisationPoste.libellesTables, contains(t), reason: t);
      }
      // Et aucune table conservée n'y figure.
      expect(ReinitialisationPoste.tablesPerdues.where(AppDatabase.tablesConservees.contains), isEmpty);
    });

    test(
      '🔴 succès : purge IMMÉDIATE après le serveur (activité vide, référentiels gardés, soldes à 0, marque notée), '
      'puis tirage COMPLET sans seconde purge',
      () async {
        await activite();
        final utilisateursAvant = await lignes('utilisateurs');

        final r = await depot.reinitialiser('REINITIALISER');

        // Le serveur a été appelé AVANT la purge : la bande était encore là.
        expect(serveur.lotsAuMomentDeLAppel, 1);
        for (final table in AppDatabase.tablesDActivite) {
          expect(await lignes(table), 0, reason: table);
        }
        expect(await lignes('products'), 1);
        expect((await db.select(db.products).getSingle()).stockQty, 0);
        expect((await db.select(db.treasuryAccounts).getSingle()).balance, 0);
        expect(await lignes('utilisateurs'), utilisateursAvant);
        expect(await marqueNotee(), _Serveur.marqueDuServeur);

        // Message du web, saisies perdues (la fiche en attente et la vente refusée).
        expect(r.message, 'Réinitialisation effectuée — 7 enregistrement(s) supprimé(s).');
        expect(r.perdues, 2);
        // Tirage complet aussitôt (curseur effacé), sans l'avertissement de la purge au tirage : elle est faite.
        expect(serveur.journal, ['reinitialisation', 'tirage complet', 'envoi']);
        expect(r.synchronisation, isNotNull);
        expect(r.synchronisation!.avertissements, isEmpty);
        // L'envoi porte la marque : le serveur l'accepte (15.50).
        expect(serveur.envois.single['data_reset_at'], _Serveur.marqueDuServeur);
        // Le produit en attente (conservé) repart.
        expect(serveur.envois.single['products'], hasLength(1));
      },
    );

    for (final (statut, message) in [
      (409, "Réinitialisation refusée : le mode démonstration n'est pas activé."),
      (403, 'Votre rôle ne permet pas de réinitialiser les données.'),
      (422, 'Saisissez REINITIALISER pour confirmer.'),
    ]) {
      test('refus $statut du serveur : son message, mot pour mot, et RIEN n est purgé', () async {
        await activite();
        serveur.refus = (statut, message);

        await expectLater(
          depot.reinitialiser('REINITIALISER'),
          throwsA(isA<RefusReinitialisation>().having((e) => e.message, 'message', message)),
        );
        await moteur.synchroniser();

        expect(await lignes('livestock_lots'), 1);
        expect(await lignes('livestock_daily_entries'), 1);
        expect((await db.select(db.products).getSingle()).stockQty, 40);
        expect(await marqueNotee(), isNull);
      });
    }

    test('serveur injoignable : message français (messageErreur), RIEN n est purgé', () async {
      await activite();
      serveur.reseauCoupe = true;

      Object? erreur;
      try {
        await depot.reinitialiser('REINITIALISER');
      } catch (e) {
        erreur = e;
      }

      expect(erreur, isA<DioException>());
      expect(messageErreur(erreur!), startsWith('Serveur injoignable'));
      await moteur.synchroniser();
      expect(await lignes('livestock_lots'), 1);
      expect(await marqueNotee(), isNull);
    });

    test(
      '⚠️ aucune synchronisation ne s intercale : la tentative en cours finit avant l appel, la suivante tire après la purge',
      () async {
        await activite();
        final porte = serveur.porteDuTirage = Completer<void>();

        final enCours = moteur.synchroniser();
        await pumpEventQueue();
        final reinitialisation = depot.reinitialiser('REINITIALISER');
        await pumpEventQueue();
        // Le tirage en cours est retenu : le serveur n'a pas encore été appelé pour la réinitialisation.
        expect(serveur.journal, ['tirage depuis']);

        // Une synchronisation demandée PENDANT l'opération (automatique, bouton) attend sa fin.
        porte.complete();
        await enCours;
        final pendant = moteur.synchroniser();
        await reinitialisation;
        await pendant;

        expect(serveur.journal, ['tirage depuis', 'envoi', 'reinitialisation', 'tirage complet', 'envoi']);
        expect(await lignes('livestock_lots'), 0);
      },
    );
  });

  group('onglet', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: OngletReinitialisation(depot: depot)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> nettoyer(WidgetTester tester) async {
      ToastAgri.toutRetirer();
      await tester.pumpWidget(const SizedBox());
    }

    bool actif(WidgetTester tester, String cle) {
      final bouton = tester.widget<ButtonStyleButton>(
        find
            .ancestor(of: find.byKey(Key(cle)), matching: find.bySubtype<ButtonStyleButton>(), matchRoot: true)
            .first,
      );
      return bouton.onPressed != null;
    }

    testWidgets('⚠️ hors ligne : l onglet le dit, la bascule est inerte, rien n est demandé au serveur', (
      tester,
    ) async {
      reseau.enLigne = false;
      await afficher(tester);

      expect(find.byKey(const Key('reinitialisation-hors-ligne')), findsOne);
      expect(find.textContaining('Hors ligne'), findsOne);
      expect(tester.widget<Text>(find.byKey(const Key('reinitialisation-etat-mode-demo'))).data, '—');
      expect(actif(tester, 'reinitialisation-etat-mode-demo'), isFalse);
      expect(find.text('Réinitialisation verrouillée'), findsOne);
      expect(find.byKey(const Key('reinitialisation-ouvrir')), findsNothing);
      expect(serveur.journal, isEmpty);
      await nettoyer(tester);
    });

    testWidgets('le réseau tombe après l affichage : le bouton le découvre, le dit et se désactive', (tester) async {
      await afficher(tester);
      expect(actif(tester, 'reinitialisation-ouvrir'), isTrue);

      reseau.enLigne = false;
      await tester.tap(find.byKey(const Key('reinitialisation-ouvrir')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reinitialisation-confirmation')), 'REINITIALISER');
      await tester.tap(find.byKey(const Key('reinitialisation-confirmer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reinitialisation-hors-ligne')), findsOne);
      expect(actif(tester, 'reinitialisation-ouvrir'), isFalse);
      expect(serveur.journal, ['etat']);
      await nettoyer(tester);
    });

    testWidgets('mode démonstration désactivé : verrou du web, et la bascule l ouvre avec le message du web', (
      tester,
    ) async {
      serveur.modeDemo = false;
      await afficher(tester);

      expect(find.text('Réinitialisation verrouillée'), findsOne);
      expect(find.text('Activez le mode démonstration ci-dessus pour y accéder.'), findsOne);
      expect(find.text('Désactivé'), findsOne);

      await tester.tap(find.byKey(const Key('reinitialisation-basculer')));
      await tester.pumpAndSettle();

      expect(serveur.journal, ['etat', 'bascule']);
      expect(find.text('Activé'), findsOne);
      expect(find.text("Mode démonstration activé — l'onglet de réinitialisation est accessible."), findsOne);
      expect(find.text("Cette opération vide TOUTES les données d'activité"), findsOne);
      expect(find.text('SUPPRIMÉ'), findsOne);
      expect(find.text('CONSERVÉ'), findsOne);
      await nettoyer(tester);
    });

    testWidgets(
      '⚠️ modale : mauvais mot → message du web sous le champ et rien d envoyé ; bon mot → réinitialisé, purgé, toast du web',
      (tester) async {
        await activite();
        await db.update(db.livestockDailyEntries).write(
          const LivestockDailyEntriesCompanion(syncStatus: Value(SyncStatus.synced)),
        );
        await db.update(db.sales).write(const SalesCompanion(syncStatus: Value(SyncStatus.synced)));
        await afficher(tester);

        // Aucune saisie perdue : pas de bloc, pas de case à cocher.
        expect(find.byKey(const Key('reinitialisation-saisies-ecran')), findsNothing);

        await tester.tap(find.byKey(const Key('reinitialisation-ouvrir')));
        await tester.pumpAndSettle();
        expect(find.text("Réinitialiser toutes les données d'activité ?"), findsOne);
        expect(find.byKey(const Key('reinitialisation-accepter-perte')), findsNothing);

        await tester.enterText(find.byKey(const Key('reinitialisation-confirmation')), 'oui');
        await tester.tap(find.byKey(const Key('reinitialisation-confirmer')));
        await tester.pumpAndSettle();
        expect(find.text('Saisissez REINITIALISER pour confirmer.'), findsOne);
        expect(serveur.journal, ['etat']);

        await tester.enterText(find.byKey(const Key('reinitialisation-confirmation')), 'REINITIALISER');
        await tester.tap(find.byKey(const Key('reinitialisation-confirmer')));
        await tester.pumpAndSettle();

        expect(serveur.journal.take(3), ['etat', 'reinitialisation', 'tirage complet']);
        expect(find.text('Réinitialisation effectuée — 7 enregistrement(s) supprimé(s).'), findsOne);
        expect(await lignes('livestock_lots'), 0);
        expect(await lignes('sales'), 0);
        await nettoyer(tester);
      },
    );

    testWidgets(
      '⚠️ saisies non envoyées : annoncées (combien, quelles tables) et leur perte doit être acceptée explicitement',
      (tester) async {
        await activite();
        await afficher(tester);

        expect(find.text('Ce poste a 2 saisie(s) non envoyée(s) au serveur'), findsOne);
        expect(
          find.text("• Fiches journalières d'élevage : 1"),
          findsOne,
        );
        expect(find.text('• Ventes : 1 (dont 1 refusée(s) par le serveur)'), findsOne);

        await tester.tap(find.byKey(const Key('reinitialisation-ouvrir')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reinitialisation-saisies-modale')), findsOne);

        // Bon mot, mais perte non acceptée : rien ne part.
        await tester.enterText(find.byKey(const Key('reinitialisation-confirmation')), 'REINITIALISER');
        await tester.tap(find.byKey(const Key('reinitialisation-confirmer')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('reinitialisation-erreur-perte')), findsOne);
        expect(serveur.journal, ['etat']);
        expect(await lignes('livestock_daily_entries'), 1);

        await tester.tap(find.byKey(const Key('reinitialisation-accepter-perte')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('reinitialisation-confirmer')));
        await tester.pumpAndSettle();

        expect(serveur.journal, contains('reinitialisation'));
        expect(await lignes('livestock_daily_entries'), 0);
        expect(find.byKey(const Key('reinitialisation-saisies-ecran')), findsNothing);
        await nettoyer(tester);
      },
    );

    testWidgets('refus du serveur : toast d erreur au message du serveur, rien n est purgé', (tester) async {
      await activite();
      serveur.refus = (409, "Réinitialisation refusée : le mode démonstration n'est pas activé.");
      await afficher(tester);

      await tester.tap(find.byKey(const Key('reinitialisation-ouvrir')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reinitialisation-confirmation')), 'REINITIALISER');
      await tester.tap(find.byKey(const Key('reinitialisation-accepter-perte')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reinitialisation-confirmer')));
      await tester.pumpAndSettle();

      expect(find.text("Réinitialisation refusée : le mode démonstration n'est pas activé."), findsOne);
      expect(await lignes('livestock_lots'), 1);
      await nettoyer(tester);
    });

    testWidgets('un autre rôle que l administrateur : refus affiché, aucun appel au serveur', (tester) async {
      role = 'comptable';
      await afficher(tester);

      expect(find.text('Votre rôle ne permet pas de réinitialiser les données.'), findsOne);
      expect(find.byKey(const Key('reinitialisation-basculer')), findsNothing);
      expect(serveur.journal, isEmpty);
      await nettoyer(tester);
    });

    testWidgets('hub : « Réinitialisation » est le dernier onglet, ouvert sur l onglet du poste', (tester) async {
      tester.view.physicalSize = const Size(1700, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ParametresGenerauxScreen(
            depot: ParametresGenerauxRepository(database: db),
            reinitialisation: depot,
            ongletInitial: ParametresGenerauxScreen.ongletReinitialisation,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(ParametresGenerauxScreen.onglets.last.$1, 'Réinitialisation');
      expect(find.byType(OngletReinitialisation), findsOne);
      expect(find.text('Réinitialisation des Données'), findsOne);
      await nettoyer(tester);
    });
  });
}
