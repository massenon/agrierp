import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/clients/clients_creances_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket VC-1 — L'ENCAISSEMENT D'UNE CREANCE CLIENT SE SAISIT AU POSTE (`suivi-dettes.blade.php`).
///
/// ⚠️⚠️ **LE POSTE N'ECRIT QUE LE FAIT** : ni `amount_paid`, ni solde de compte, ni écriture. Le serveur
/// (`CustomerSettlementService`) solde la créance, entre l'argent dans les deux livres et passe D 5xx / C 411. Le poste
/// affiche des soldes NETS de ce qu'il a saisi et que le serveur n'a pas encore appliqué.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-28T12:00:00Z'};
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
  late ClientsCreancesRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 28, 14),
    );
    depot = ClientsCreancesRepository(database: db, deviceId: 'poste-test');
    await db.into(db.customers).insert(CustomersCompanion.insert(id: uuid('c1'), name: 'AMOUSSOU Régis'));
    await db.into(db.treasuryAccounts).insert(TreasuryAccountsCompanion.insert(id: uuid('t1'), label: 'Caisse principale', balance: const Value(100000)));
    await db.into(db.receivables).insert(
      ReceivablesCompanion.insert(id: uuid('r1'), customerId: uuid('c1'), amount: 100000, dueDate: Value(DateTime(2026, 11, 8))),
    );
  });
  tearDown(() async => db.close());

  Future<Receivable> creance() => (db.select(db.receivables)..where((r) => r.id.equals(uuid('r1')))).getSingle();

  /// Empreinte de ce que le poste ne doit JAMAIS toucher en encaissant.
  Future<String> intouchable() async => [
    for (final t in await db.select(db.treasuryAccounts).get()) 'T:${t.id}:${t.balance}',
    for (final c in await db.select(db.receivables).get()) 'R:${c.id}:${c.amount}:${c.amountPaid}',
    'E:${(await db.select(db.accountingEntries).get()).length}',
  ].join('|');

  group('dépôt', () {
    test('⚠️⚠️ un encaissement est pending, ne touche ni créance ni trésorerie ni écriture', () async {
      final avant = await intouchable();

      final e = await depot.encaisserCreance(creanceId: uuid('r1'), montant: 30000, compteId: uuid('t1'));

      expect(e.syncStatus, SyncStatus.pending);
      expect(e.deviceId, 'poste-test');
      expect(e.customerId, uuid('c1'));
      expect(e.receivableId, uuid('r1'));
      expect(await intouchable(), avant);
    });

    test('le solde affiché est NET des encaissements et des imputations en attente', () async {
      await depot.encaisserCreance(creanceId: uuid('r1'), montant: 30000, compteId: uuid('t1'));
      await db.into(db.customerAdvances).insert(
        CustomerAdvancesCompanion.insert(id: uuid('a1'), customerId: uuid('c1'), amount: 50000, advanceDate: Value(DateTime(2026, 10, 1))),
      );
      await depot.imputerAvance(avanceId: uuid('a1'), creanceId: uuid('r1'), montant: 20000);

      expect(await depot.soldeCreance(await creance()), 50000);
      final d = await depot.charger();
      expect(d.creances.single.resteDu, 50000);
      expect(d.clients.single.soldeDu, 50000, reason: 'la liste des clients suit le même net');
    });

    test('les refus du serveur sont reproduits AVANT d\'écrire, mêmes messages', () async {
      Future<String> refuse(Future<void> Function() geste) async {
        try {
          await geste();
        } on SaisieRefusee catch (e) {
          return e.motif;
        }
        fail('accepté');
      }

      Future<void> enc({String creanceId = '', double montant = 1000, String compte = ''}) => depot.encaisserCreance(
        creanceId: creanceId.isEmpty ? uuid('r1') : creanceId,
        montant: montant,
        compteId: compte.isEmpty ? uuid('t1') : compte,
      );

      expect(await refuse(() => enc(montant: 0)), 'Le montant du règlement doit être supérieur à zéro.');
      expect(await refuse(() => enc(montant: 0.5)), "Le montant du règlement doit être d'au moins 1 FCFA.");
      expect(await refuse(() => enc(creanceId: uuid('inconnue'))), 'Créance introuvable — synchronisez le poste.');
      expect(await refuse(() => enc(compte: uuid('inconnu'))), contains('Compte de trésorerie inconnu'));
      expect(await refuse(() => enc(montant: 100001)), contains('dépasse le solde de la créance (100000 F)'));

      await depot.encaisserCreance(creanceId: uuid('r1'), montant: 100000, compteId: uuid('t1'));
      expect(await refuse(() => enc()), 'Cette créance est déjà soldée : rien à encaisser.');
      expect((await db.select(db.receivablePayments).get()).length, 1);
    });

    test('⚠️ un second encaissement est plafonné par le NET du premier (jamais deux fois le même solde)', () async {
      await depot.encaisserCreance(creanceId: uuid('r1'), montant: 70000, compteId: uuid('t1'));

      await expectLater(
        depot.encaisserCreance(creanceId: uuid('r1'), montant: 40000, compteId: uuid('t1')),
        throwsA(isA<SaisieRefusee>().having((e) => e.motif, 'motif', contains('(30000 F)'))),
      );
    });
  });

  group('moteur', () {
    test('⚠️⚠️ l\'envoi ne porte que le FAIT, sous les clés de `pushReceivablePayments`, et est acquitté', () async {
      final e = await depot.encaisserCreance(creanceId: uuid('r1'), montant: 30000, compteId: uuid('t1'), date: DateTime(2026, 10, 28));

      await moteur.synchroniser();

      final envoye = (serveur.envois.single['receivable_payments'] as List).single as Map;
      expect(envoye, {
        'id': e.id, 'customer_id': uuid('c1'), 'receivable_id': uuid('r1'), 'treasury_account_id': uuid('t1'),
        'amount': 30000.0, 'payment_date': '2026-10-28',
      });
      expect((await db.select(db.receivablePayments).get()).single.syncStatus, SyncStatus.synced);
    });

    test('un refus du serveur devient conflict avec son motif, ne réduit plus le solde, et se relance', () async {
      final e = await depot.encaisserCreance(creanceId: uuid('r1'), montant: 30000, compteId: uuid('t1'));
      serveur.refus['receivable_payments'] = {e.id: 'Cette créance est déjà soldée : rien à encaisser.'};

      await moteur.synchroniser();

      expect((await db.select(db.receivablePayments).get()).single.syncStatus, SyncStatus.conflict);
      final conflit = (await db.select(db.syncConflicts).get()).firstWhere((c) => c.sourceTable == 'receivable_payments');
      expect(conflit.reason, contains('déjà soldée'));
      expect(await depot.soldeCreance(await creance()), 100000, reason: 'refusé : le solde redevient celui du serveur');

      await moteur.relancer(conflit);
      expect((await db.select(db.receivablePayments).get()).single.syncStatus, SyncStatus.pending);
    });

    test('acquitté, le tirage de confirmation rend la créance soldée du serveur sans double compte', () async {
      await depot.encaisserCreance(creanceId: uuid('r1'), montant: 30000, compteId: uuid('t1'));
      serveur.tirage = {
        'server_time': '2026-10-28T13:00:00Z',
        'receivables': [
          {'id': uuid('r1'), 'customer_id': uuid('c1'), 'sale_id': null, 'amount': 100000, 'amount_paid': 30000, 'due_date': '2026-11-08', 'status': 'en_cours'},
        ],
      };

      await moteur.synchroniser();

      expect((await creance()).amountPaid, 30000);
      expect(await depot.soldeCreance(await creance()), 70000, reason: 'encaissé acquitté + tiré : 70 000 restent dus, pas 40 000');
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      await tester.pumpWidget(
        MaterialApp(home: ClientsCreancesScreen(depot: depot, maintenant: () => DateTime(2026, 10, 28, 10))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onglet-clients-Suivi des Dettes')));
      await tester.pumpAndSettle();
    }

    String texteDe(WidgetTester tester, String cle) => tester.widget<Text>(find.byKey(Key(cle))).data!;

    testWidgets('⚠️⚠️ « Enregistrer un Recouvrement » : la modale du Blade écrit le fait et le solde baisse', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('creance-encaisser-0')));
      await tester.pumpAndSettle();
      expect(find.text('Enregistrer un Recouvrement'), findsOneWidget);
      expect(find.text('Valider le Règlement'), findsOneWidget);
      expect(find.byKey(const Key('recouvrement-solde')), findsOneWidget);
      expect(texteDe(tester, 'recouvrement-solde'), '100 000 FCFA');

      // Rien de saisi : les refus sous les champs, rien d'écrit.
      await tester.tap(find.text('Valider le Règlement'));
      await tester.pumpAndSettle();
      expect(find.text('Le champ montant du règlement est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ compte de trésorerie est obligatoire.'), findsOneWidget);
      expect((await db.select(db.receivablePayments).get()), isEmpty);

      await tester.enterText(find.byKey(const Key('recouvrement-montant')), '30000');
      await tester.pump();
      expect(texteDe(tester, 'recouvrement-nouveau-solde'), '70 000 FCFA');
      await tester.tap(find.byKey(const Key('recouvrement-compte')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caisse principale').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider le Règlement'));
      await tester.pumpAndSettle();
      await tester.pump(ToastAgri.duree + const Duration(seconds: 1));

      final e = (await db.select(db.receivablePayments).get()).single;
      expect(e.amount, 30000);
      expect(e.syncStatus, SyncStatus.pending);
      expect(find.text('70 000'), findsWidgets, reason: 'solde restant net dans le tableau');
    });

    testWidgets('« Ajouter un Recouvrement » (en-tête) propose les créances ouvertes', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('ajouter-recouvrement')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recouvrement-creance')), findsOneWidget);
      expect(texteDe(tester, 'recouvrement-solde'), '—');

      await tester.tap(find.byKey(const Key('recouvrement-creance')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('AMOUSSOU Régis').last);
      await tester.pumpAndSettle();
      expect(texteDe(tester, 'recouvrement-solde'), '100 000 FCFA');
    });
  });
}
