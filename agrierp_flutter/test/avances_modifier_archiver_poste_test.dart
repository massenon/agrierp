import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/clients/clients_creances_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serveur de synchronisation feint : sert les blocs [tirages], répond [reponsePush] à l'envoi et note ce qui part.
class _ServeurSync extends Interceptor {
  _ServeurSync({this.reponsePush = const {}, this.tirages = const [{}]});

  final Map<String, dynamic> reponsePush;
  final List<Map<String, dynamic>> tirages;
  final List<Map<String, dynamic>> envois = [];
  var nbTirages = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final push = options.path.contains('push');
    if (push) envois.add(Map<String, dynamic>.from(options.data as Map));
    Map<String, dynamic> corps;
    if (push) {
      corps = reponsePush;
    } else {
      final bloc = tirages[nbTirages < tirages.length ? nbTirages : tirages.length - 1];
      nbTirages++;
      corps = {
        'server_time': '2026-10-09T12:0$nbTirages:00.000Z',
        'product_categories': <dynamic>[],
        'products': <dynamic>[],
        'livestock_lots': <dynamic>[],
        ...bloc,
      };
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: corps));
  }
}

class _ConnectiviteFeinte implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Ticket VC-4 — MODIFIER ET ARCHIVER UNE AVANCE AU POSTE (décision du client : « OUI LE POSTE DOIT LE FAIRE »).
///
/// Les décisions D4/D5 (« le poste ne modifie ni n'archive une avance ») sont REVUES : le poste applique, avant d'écrire, les règles
/// de `CustomerAdvanceService::modifier` / `archiver` (parité exécutée : `avances_modifier_archiver_parite_php_test.dart`), repasse
/// la ligne en `pending` et le moteur l'envoie ENTIÈRE avec `is_active` ; le serveur reconnaît une ligne connue.
void main() {
  late AppDatabase db;
  late ClientsCreancesRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    HeureBenin.horloge = () => DateTime.utc(2026, 10, 9, 10);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ClientsCreancesRepository(database: db, deviceId: 'poste-test');
    for (final (cle, nom) in [('c1', 'AMOUSSOU Régis'), ('c2', 'TOSSOU Marcel')]) {
      await db.into(db.customers).insert(CustomersCompanion.insert(id: uuid(cle), name: nom));
    }
    await db.into(db.treasuryAccounts).insert(TreasuryAccountsCompanion.insert(id: uuid('t1'), label: 'Caisse principale', balance: const Value(100000)));
  });

  tearDown(() async {
    HeureBenin.reinitialiser();
    ToastAgri.toutRetirer();
    await db.close();
  });

  SyncEngine moteur(_ServeurSync serveur) => SyncEngine(
    database: db,
    client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur),
    deviceId: 'poste-test',
    connectivity: _ConnectiviteFeinte(),
  );

  /// Avance servie : [comptabilisee] = elle porte un compte de trésorerie (toute avance saisie depuis 15.19).
  Future<void> avance(
    String cle, {
    double montant = 40000,
    double utilise = 0,
    bool comptabilisee = false,
    SyncStatus statut = SyncStatus.synced,
    bool active = true,
    String client = 'c1',
  }) => db.into(db.customerAdvances).insert(
    CustomerAdvancesCompanion.insert(
      id: uuid(cle),
      customerId: uuid(client),
      amount: montant,
      amountUsed: Value(utilise),
      advanceDate: Value(DateTime(2026, 10, 1)),
      isActive: Value(active),
      treasuryAccountId: Value(comptabilisee ? uuid('t1') : null),
      syncStatus: Value(statut),
    ),
  );

  Future<CustomerAdvance> lire(String cle) => (db.select(db.customerAdvances)..where((a) => a.id.equals(uuid(cle)))).getSingle();

  Future<String> empreinte() async {
    final tresor = await db.select(db.treasuryAccounts).get();
    final ecritures = await db.select(db.accountingEntries).get();
    final imputations = await db.select(db.advanceImputations).get();
    return [for (final t in tresor) 'T:${t.id}:${t.balance}', 'E:${ecritures.length}', 'I:${imputations.length}'].join('|');
  }

  Future<void> refuseModif(String cle, String champ, String motif, {String client = 'c1', String montant = '40000', DateTime? date}) async {
    final avant = await lire(cle);
    await expectLater(
      depot.modifierAvance(uuid(cle), clientId: uuid(client), montant: montant, date: date ?? DateTime(2026, 10, 1)),
      throwsA(isA<SaisieAvanceRefusee>().having((e) => e.erreurs[champ], champ, motif)),
    );
    final apres = await lire(cle);
    expect(apres, avant, reason: 'un refus n’écrit rien');
  }

  group('modifierAvance : les règles du web, refusées avant d’écrire', () {
    test('⚠️ une avance d’avant 15.19 (jamais comptabilisée, jamais entamée) change de client, de montant et de date', () async {
      await avance('a1');
      final avant = await empreinte();

      final ecrit = await depot.modifierAvance(uuid('a1'), clientId: uuid('c2'), montant: '55000', date: DateTime(2026, 10, 4, 15));

      expect(ecrit, isTrue);
      final a = await lire('a1');
      expect(a.customerId, uuid('c2'));
      expect(a.amount, 55000);
      expect(a.advanceDate, DateTime(2026, 10, 4));
      expect(a.syncStatus, SyncStatus.pending, reason: 'la ligne repart au prochain envoi');
      expect(a.isActive, isTrue);
      expect(await empreinte(), avant, reason: 'le poste n’écrit que le fait : ni caisse ni écriture');
    });

    test('⚠️ une saisie identique n’écrit rien et ne remet rien en attente', () async {
      await avance('a1', comptabilisee: true);

      final ecrit = await depot.modifierAvance(uuid('a1'), clientId: uuid('c1'), montant: '40000', date: DateTime(2026, 10, 1));

      expect(ecrit, isFalse);
      expect((await lire('a1')).syncStatus, SyncStatus.synced);
    });

    test('⚠️ comptabilisée : montant, client et date figés, avec les motifs du web', () async {
      await avance('a1', comptabilisee: true);
      await refuseModif('a1', 'amount', "Le montant d'une avance déjà comptabilisée ne peut plus être modifié.", montant: '50000');
      await refuseModif('a1', 'customerId', "Le client d'une avance déjà comptabilisée ne peut plus être modifié.", client: 'c2');
      await refuseModif(
        'a1',
        'advanceDate',
        "La date d'une avance comptabilisée ne peut plus être modifiée : l'écriture est datée du jour de l'encaissement.",
        date: DateTime(2026, 10, 2),
      );
    });

    test('⚠️ entamée : montant et client figés, la date reste libre tant qu’elle n’est pas comptabilisée', () async {
      await avance('a1', utilise: 10000);
      await refuseModif('a1', 'amount', "Le montant d'une avance déjà entamée ne peut plus être modifié.", montant: '30000');
      await refuseModif('a1', 'customerId', "Le client d'une avance déjà entamée ne peut plus être modifié.", client: 'c2');

      expect(await depot.modifierAvance(uuid('a1'), clientId: uuid('c1'), montant: '40000', date: DateTime(2026, 10, 3)), isTrue);
    });

    test('⚠️ une imputation en attente sur ce poste rend déjà l’avance « entamée »', () async {
      await avance('a1');
      await db.into(db.advanceImputations).insert(
        AdvanceImputationsCompanion.insert(
          id: uuid('i1'),
          deviceId: 'poste-test',
          updatedAt: DateTime.now(),
          customerAdvanceId: uuid('a1'),
          receivableId: Value(uuid('r1')),
          amount: 5000,
          imputationDate: DateTime(2026, 10, 9),
        ),
      );

      await refuseModif('a1', 'amount', "Le montant d'une avance déjà entamée ne peut plus être modifié.", montant: '30000');
    });

    test('règles du formulaire : client, montant (au moins 1) et date, sous leur champ', () async {
      await avance('a1');
      Future<Map<String, String>> erreurs({String client = 'c1', String montant = '40000', DateTime? date}) async {
        try {
          await depot.modifierAvance(uuid('a1'), clientId: client.isEmpty ? '' : uuid(client), montant: montant, date: date);
        } on SaisieAvanceRefusee catch (e) {
          expect(e.deFormulaire, isTrue);
          return e.erreurs;
        }
        return {};
      }

      expect(await erreurs(client: '', date: DateTime(2026, 10, 1)), {'customerId': 'Le champ client est obligatoire.'});
      expect(await erreurs(montant: '', date: DateTime(2026, 10, 1)), {'amount': 'Le champ montant est obligatoire.'});
      expect(await erreurs(montant: '0.5', date: DateTime(2026, 10, 1)), {'amount': 'Le champ montant doit être au moins égal à 1.'});
      expect(await erreurs(), {'advanceDate': 'Le champ date est obligatoire.'});
      expect((await lire('a1')).syncStatus, SyncStatus.synced);
    });

    test('une avance archivée ne se modifie plus (jamais de réactivation)', () async {
      await avance('a1', active: false);
      await refuseModif('a1', 'advance', 'Cette avance est archivée : elle ne peut plus être modifiée.');
    });
  });

  group('archiverAvance : D5 revue, refusée tant qu’il reste un reste', () {
    test('⚠️ avec un reste : refusée avec le motif du web, rien n’est écrit', () async {
      await avance('a1', utilise: 15000, comptabilisee: true);

      await expectLater(
        depot.archiverAvance(uuid('a1')),
        throwsA(isA<SaisieAvanceRefusee>().having((e) => e.motif, 'motif', "Cette avance a encore un reste de 25 000 FCFA : imputez-la avant de l'archiver.")),
      );
      final a = await lire('a1');
      expect(a.isActive, isTrue);
      expect(a.syncStatus, SyncStatus.synced);
    });

    test('⚠️ le reste est NET des imputations en attente sur ce poste', () async {
      await avance('a1', utilise: 30000);
      await db.into(db.advanceImputations).insert(
        AdvanceImputationsCompanion.insert(
          id: uuid('i1'),
          deviceId: 'poste-test',
          updatedAt: DateTime.now(),
          customerAdvanceId: uuid('a1'),
          receivableId: Value(uuid('r1')),
          amount: 10000,
          imputationDate: DateTime(2026, 10, 9),
        ),
      );

      // 40 000 − 30 000 − 10 000 en attente = soldée : archivable.
      expect(await depot.archiverAvance(uuid('a1')), isTrue);
    });

    test('⚠️ soldée : archivage logique, en attente d’envoi, retirée de la liste ; un second archivage ne fait rien', () async {
      await avance('a1', utilise: 40000, comptabilisee: true);
      await avance('a2');
      final avant = await empreinte();

      expect(await depot.archiverAvance(uuid('a1')), isTrue);

      final a = await lire('a1');
      expect(a.isActive, isFalse);
      expect(a.syncStatus, SyncStatus.pending);
      expect(await db.select(db.customerAdvances).get(), hasLength(2), reason: 'jamais de suppression physique');
      expect(await empreinte(), avant, reason: 'ni caisse ni écriture au poste');
      expect((await depot.charger()).avances.map((l) => l.avance.id), [uuid('a2')]);

      expect(await depot.archiverAvance(uuid('a1')), isFalse);
      expect(await depot.archiverAvance(uuid('inconnue')), isFalse);
    });
  });

  group('moteur de synchronisation', () {
    test('⚠️ une avance modifiée repart ENTIÈRE avec is_active, puis est acquittée', () async {
      await avance('a1');
      await depot.modifierAvance(uuid('a1'), clientId: uuid('c2'), montant: '55000', date: DateTime(2026, 10, 4));
      final serveur = _ServeurSync(
        reponsePush: {
          'customer_advances': {'accepted': [uuid('a1')], 'rejected': []},
        },
      );

      await moteur(serveur).synchroniser();

      expect((serveur.envois.single['customer_advances'] as List).single, {
        'id': uuid('a1'),
        'customer_id': uuid('c2'),
        'treasury_account_id': null,
        'amount': 55000.0,
        'advance_date': '2026-10-04',
        'payment_mode': null,
        'motif': null,
        'is_active': true,
      });
      expect((await lire('a1')).syncStatus, SyncStatus.synced);
    });

    test('⚠️ une avance archivée part avec is_active: false ; acquittée, le tirage suivant la retire', () async {
      await avance('a1', utilise: 40000, comptabilisee: true);
      await depot.archiverAvance(uuid('a1'));
      final serveur = _ServeurSync(
        reponsePush: {
          'customer_advances': {'accepted': [uuid('a1')], 'rejected': []},
        },
        // Le serveur ne sert que les avances ACTIVES : celle-ci n'y figure plus.
        tirages: const [
          {'customer_advances': <dynamic>[]},
        ],
      );

      await moteur(serveur).synchroniser();

      expect(((serveur.envois.single['customer_advances'] as List).single as Map)['is_active'], isFalse);
      expect(await db.select(db.customerAdvances).get(), isEmpty, reason: 'synced puis absente du tirage : retirée, comme au web');
    });

    test('⚠️ le tirage n’écrase pas une modification en attente', () async {
      await avance('a1');
      await depot.modifierAvance(uuid('a1'), clientId: uuid('c1'), montant: '55000', date: DateTime(2026, 10, 1));
      final serveur = _ServeurSync(
        tirages: [
          {
            'customer_advances': [
              {'id': uuid('a1'), 'customer_id': uuid('c1'), 'amount': 40000, 'amount_used': 0, 'advance_date': '2026-10-01', 'is_active': true},
            ],
          },
        ],
      );

      await moteur(serveur).synchroniser();

      expect((await lire('a1')).amount, 55000, reason: 'la ligne pending est protégée du tirage');
    });

    test('⚠️ refus du serveur : conflict, motif mot pour mot, puis « Relancer » remet la ligne en file', () async {
      await avance('a1', utilise: 40000);
      await depot.archiverAvance(uuid('a1'));
      const motif = "Cette avance a encore un reste de 5 000 FCFA : imputez-la avant de l'archiver.";
      final serveur = _ServeurSync(
        reponsePush: {
          'customer_advances': {
            'accepted': [],
            'rejected': [
              {'id': uuid('a1'), 'reason': motif},
            ],
          },
        },
      );
      final m = moteur(serveur);

      await m.synchroniser();

      expect((await lire('a1')).syncStatus, SyncStatus.conflict);
      final conflit = await db.select(db.syncConflicts).getSingle();
      expect(conflit.reason, motif);

      await m.relancer(conflit);
      expect((await lire('a1')).syncStatus, SyncStatus.pending);
    });
  });

  group('écran « Historique des Avances »', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(home: ClientsCreancesScreen(depot: depot, maintenant: () => DateTime(2026, 10, 9, 10))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onglet-clients-Historique Avances')));
      await tester.pumpAndSettle();
    }

    /// `testWidgets` qui retire les toasts à la fin (leur minuterie ne doit pas survivre à l’arbre).
    void cas(String nom, Future<void> Function(WidgetTester tester) corps) => testWidgets(nom, (tester) async {
      await corps(tester);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle();
    });

    cas('⚠️ le crayon ouvre « Modifier l’Avance » : Client, Montant grisé et sa note, Date, Annuler / Enregistrer', (tester) async {
      await avance('a1', comptabilisee: true);
      await afficher(tester);

      await tester.tap(find.byKey(Key('modifier-avance-${uuid('a1')}')));
      await tester.pumpAndSettle();

      expect(find.text("Modifier l'Avance"), findsOneWidget);
      for (final libelle in ['CLIENT *', 'MONTANT (FCFA) *', 'DATE *', 'Annuler', 'Enregistrer']) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }
      expect(tester.widget<TextField>(find.byKey(const Key('avance-modif-montant'))).enabled, isFalse);
      expect(find.text("Le montant d'une avance entamée ou comptabilisée ne peut plus être modifié."), findsOneWidget);
    });

    cas('⚠️ avance d’avant 15.19 : le montant se modifie, « Avance modifiée avec succès. », ligne en attente', (tester) async {
      await avance('a1');
      await afficher(tester);

      await tester.tap(find.byKey(Key('modifier-avance-${uuid('a1')}')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('avance-modif-montant'))).enabled, isTrue);
      expect(find.byKey(const Key('avance-modif-montant-fige')), findsNothing);
      await tester.enterText(find.byKey(const Key('avance-modif-montant')), '60000');
      await tester.tap(find.byKey(const Key('avance-modif-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.text('Avance modifiée avec succès.'), findsOneWidget);
      final a = await lire('a1');
      expect(a.amount, 60000);
      expect(a.syncStatus, SyncStatus.pending);
    });

    cas('⚠️ un champ vide est signalé sous son champ (phrases du web), rien n’est écrit', (tester) async {
      await avance('a1');
      await afficher(tester);

      await tester.tap(find.byKey(Key('modifier-avance-${uuid('a1')}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('avance-modif-montant')), '');
      await tester.tap(find.byKey(const Key('avance-modif-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.text('Le champ montant est obligatoire.'), findsOneWidget);
      expect(find.text("Modifier l'Avance"), findsOneWidget, reason: 'la modale reste ouverte');
      expect((await lire('a1')).syncStatus, SyncStatus.synced);
    });

    cas('⚠️ archiver : confirmation au texte du web ; un reste est refusé en toast d’erreur', (tester) async {
      await avance('a1', utilise: 15000, comptabilisee: true);
      await afficher(tester);

      await tester.tap(find.byKey(Key('archiver-avance-${uuid('a1')}')));
      await tester.pumpAndSettle();
      expect(find.text("Confirmer l'archivage"), findsOneWidget);
      expect(
        find.text(
          "AMOUSSOU Régis — 40 000 FCFA sera marqué(e) comme archivé(e) (statut inactif). Aucune suppression définitive n'est effectuée.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('archivage-avance-confirmer')));
      await tester.pumpAndSettle();

      expect(find.text("Cette avance a encore un reste de 25 000 FCFA : imputez-la avant de l'archiver."), findsOneWidget);
      expect((await lire('a1')).isActive, isTrue);
    });

    cas('⚠️ archiver une avance soldée : « Avance archivée avec succès. » et la ligne disparaît', (tester) async {
      await avance('a1', utilise: 40000, comptabilisee: true);
      await afficher(tester);

      await tester.tap(find.byKey(Key('archiver-avance-${uuid('a1')}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('archivage-avance-confirmer')));
      await tester.pumpAndSettle();

      expect(find.text('Avance archivée avec succès.'), findsOneWidget);
      expect(find.byKey(Key('archiver-avance-${uuid('a1')}')), findsNothing);
      expect((await lire('a1')).isActive, isFalse);
    });
  });
}
