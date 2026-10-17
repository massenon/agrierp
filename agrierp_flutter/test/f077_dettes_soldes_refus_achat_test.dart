import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/achats/achats_commandes_screen.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/sync/synchronisation_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serveur de synchronisation feint : sert le bloc [tirage] au tirage, répond
/// [reponsePush] à l'envoi.
class _ServeurSync extends Interceptor {
  _ServeurSync({this.reponsePush = const {}, this.tirage = const {}});

  final Map<String, dynamic> reponsePush;
  final Map<String, dynamic> tirage;
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final push = options.path.contains('push');
    if (push) envois.add(Map<String, dynamic>.from(options.data as Map));

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: push
            ? reponsePush
            : {
                'server_time': '2026-10-09T12:00:00.000Z',
                'product_categories': <dynamic>[],
                'products': <dynamic>[],
                'livestock_lots': <dynamic>[],
                ...tirage,
              },
      ),
    );
  }
}

class _ConnectiviteFeinte implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Ticket F0.77 — reste dû des achats reçus, solde net de la liste clients, refus d'un
/// achat de poste par le serveur (ticket Laravel 15.22).
void main() {
  late AppDatabase db;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async => db = AppDatabase.forTesting(NativeDatabase.memory()));

  tearDown(() async => db.close());

  SyncEngine moteur(_ServeurSync serveur) => SyncEngine(
    database: db,
    client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
      ..interceptors.add(serveur),
    deviceId: 'poste-test',
    connectivity: _ConnectiviteFeinte(),
  );

  group('Dettes en Cours — reste dû lu sur les dettes servies', () {
    /// ⚠️⚠️ LE DÉFAUT : le tirage sert les achats SANS `amount_paid` et les dettes AVEC.
    /// Testé de bout en bout par le vrai moteur, pas par des lignes insérées à la main.
    test('⚠️⚠️ après un vrai tirage, la dette en cours est le reste dû et non le '
        'total', () async {
      final serveur = _ServeurSync(
        tirage: {
          'purchases': [
            {
              'id': uuid('a1'),
              'supplier_id': uuid('f1'),
              'supplier_name': 'Provenderie du Plateau',
              'payment_mode': 'especes',
              'total': 100000,
              'has_debt': true,
              'purchase_date': '2026-10-01T08:00:00.000Z',
            },
            {
              'id': uuid('a2'),
              'supplier_id': uuid('f1'),
              'payment_mode': 'especes',
              'total': 40000,
              'has_debt': true,
              'purchase_date': '2026-10-02T08:00:00.000Z',
            },
          ],
          'payables': [
            {
              'id': uuid('d1'),
              'supplier_id': uuid('f1'),
              'purchase_id': uuid('a1'),
              'amount': 100000,
              'amount_paid': 37500,
            },
            {
              'id': uuid('d2'),
              'supplier_id': uuid('f1'),
              'purchase_id': uuid('a2'),
              'amount': 40000,
              'amount_paid': 0,
            },
          ],
        },
      );

      await moteur(serveur).synchroniser();

      final d = await AchatsRepository(
        database: db,
        identifiantPoste: 'poste-test',
      ).charger();

      // Recalcul INDÉPENDANT : SQL brut sur la table des dettes.
      final ligne = await db
          .customSelect('SELECT SUM(amount - amount_paid) AS t FROM payables')
          .getSingle();
      expect(ligne.read<double>('t'), 102500);

      expect(d.dettesEnCours, 102500);
      // L'ancienne formule (total − amount_paid de l'achat) aurait rendu 140 000.
      expect(d.dettesEnCours, isNot(140000));
    });

    test(
      'une dette soldée (reste nul) compte zéro, jamais un négatif',
      () async {
        await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                id: uuid('a1'),
                deviceId: 'serveur',
                updatedAt: DateTime.now(),
                supplierId: uuid('f1'),
                paymentMode: 'especes',
                total: 50000,
                hasDebt: const Value(true),
                purchaseDate: DateTime.now(),
              ),
            );
        await db
            .into(db.payables)
            .insert(
              PayablesCompanion.insert(
                id: uuid('d1'),
                supplierId: uuid('f1'),
                purchaseId: Value(uuid('a1')),
                amount: 50000,
                amountPaid: const Value(52000),
              ),
            );

        final d = await AchatsRepository(
          database: db,
          identifiantPoste: 'poste-test',
        ).charger();

        expect(d.dettesEnCours, 0);
      },
    );
  });

  group('Liste clients — solde dû NET des imputations en attente', () {
    late ClientsCreancesRepository depot;

    setUp(() => depot = ClientsCreancesRepository(database: db, deviceId: 'p'));

    Future<void> client(String cle, String nom) => db
        .into(db.customers)
        .insert(CustomersCompanion.insert(id: uuid(cle), name: nom));

    Future<void> creance(
      String cle,
      String cleClient,
      double montant,
      double regle,
    ) => db
        .into(db.receivables)
        .insert(
          ReceivablesCompanion.insert(
            id: uuid(cle),
            customerId: uuid(cleClient),
            amount: montant,
            amountPaid: Value(regle),
          ),
        );

    Future<void> imputation(
      String cle,
      String cleCreance,
      double montant,
      SyncStatus statut,
    ) => db
        .into(db.advanceImputations)
        .insert(
          AdvanceImputationsCompanion.insert(
            id: uuid(cle),
            deviceId: 'p',
            updatedAt: DateTime.now(),
            syncStatus: Value(statut),
            customerAdvanceId: uuid('av1'),
            receivableId: Value(uuid(cleCreance)),
            amount: montant,
            imputationDate: DateTime.now(),
          ),
        );

    test(
      '⚠️⚠️ le solde de la liste suit celui des créances et du KPI',
      () async {
        await client('c1', 'AMOUSSOU Régis');
        await creance('r1', 'c1', 8000, 3000); // brut 5 000
        await creance('r2', 'c1', 4000, 0); // brut 4 000
        await imputation('i1', 'r1', 2000, SyncStatus.pending);

        final d = await depot.charger();
        final ligne = d.clients.single;

        // Recalcul indépendant : (8 000 − 3 000 − 2 000) + 4 000.
        expect(ligne.soldeDu, 7000);
        // Cohérence avec les deux autres surfaces du même écran.
        expect(ligne.soldeDu, d.encoursGlobal);
        expect(
          ligne.soldeDu,
          d.creances.fold<double>(0, (t, c) => t + c.resteDu),
        );
      },
    );

    test(
      'une imputation acquittée ou refusée ne se déduit pas deux fois',
      () async {
        await client('c1', 'AMOUSSOU Régis');
        // `amount_paid` du tirage contient déjà l'imputation acquittée (2 000).
        await creance('r1', 'c1', 8000, 2000);
        await imputation('i1', 'r1', 2000, SyncStatus.synced);
        await imputation('i2', 'r1', 1500, SyncStatus.conflict);

        final d = await depot.charger();

        expect(d.clients.single.soldeDu, 6000);
      },
    );

    test(
      'plancher à zéro par créance : une imputation excédentaire ne retranche '
      'rien aux autres',
      () async {
        await client('c1', 'AMOUSSOU Régis');
        await creance('r1', 'c1', 1000, 0);
        await creance('r2', 'c1', 4000, 0);
        await imputation('i1', 'r1', 1500, SyncStatus.pending);

        final d = await depot.charger();

        expect(d.clients.single.soldeDu, 4000);
        expect(d.clients.single.statut, 'Créance en retard');
      },
    );
  });

  group('Achat de poste refusé par le serveur (15.22)', () {
    Future<(AchatsRepository, String)> achatEnAttente() async {
      await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(id: uuid('f1'), name: 'Provenderie'),
          );
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: uuid('p1'),
              sku: 'SKU-1',
              name: 'Aliment ponte',
              unit: 'sac',
              pricingMode: 'fourchette',
            ),
          );
      await db
          .into(db.treasuryAccounts)
          .insert(
            TreasuryAccountsCompanion.insert(id: uuid('c1'), label: 'Caisse'),
          );

      final depot = AchatsRepository(
        database: db,
        identifiantPoste: 'poste-test',
      );
      final produit = (await depot.charger()).produits.single;
      final id = await depot.enregistrer(
        fournisseurId: uuid('f1'),
        lignes: [
          LigneSaisieAchat(produit: produit, quantite: 2, prixUnitaire: 5000),
        ],
        modePaiement: 'especes',
        compteId: uuid('c1'),
        montantPaye: 10000,
      );
      return (depot, id);
    }

    const motif =
        'Achat non comptabilisable : compte 601 absent du plan comptable.';

    _ServeurSync serveurRefus(String id) => _ServeurSync(
      reponsePush: {
        'purchases': {
          'accepted': <String>[],
          'rejected': [
            {'id': id, 'reason': motif},
          ],
        },
      },
    );

    test('⚠️⚠️ le moteur passe l achat en conflict et garde le motif mot pour '
        'mot', () async {
      final (depot, id) = await achatEnAttente();

      final r = await moteur(serveurRefus(id)).synchroniser();

      final achat = await (db.select(
        db.purchases,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(achat.syncStatus, SyncStatus.conflict);
      expect(r.rejete, 1);
      expect(r.motifs, contains(motif));

      final conflit = await db.select(db.syncConflicts).getSingle();
      expect(conflit.sourceTable, 'purchases');
      expect(conflit.recordId, id);
      expect(conflit.reason, motif);

      // Sorti des envois automatiques : un second passage ne le renvoie pas.
      final serveur2 = _ServeurSync();
      await moteur(serveur2).synchroniser();
      expect(
        serveur2.envois.expand((e) => (e['purchases'] as List?) ?? const []),
        isEmpty,
        reason: 'un achat refusé ne repart pas tout seul',
      );

      // Le dépôt le porte avec son motif.
      final ligne = (await depot.charger()).achats.single;
      expect(ligne.refuse, isTrue);
      expect(ligne.envoye, isFalse);
      expect(ligne.motifRefusAchat, motif);
      expect(ligne.statut, 'Refusé par le serveur');
    });

    test(
      '⚠️ « Relancer » remet l achat refusé en file et efface le refus',
      () async {
        final (_, id) = await achatEnAttente();
        final moteurRefus = moteur(serveurRefus(id));
        await moteurRefus.synchroniser();

        await moteurRefus.relancer((await moteurRefus.conflits()).single);

        final achat = await (db.select(
          db.purchases,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(achat.syncStatus, SyncStatus.pending);
        expect(await moteurRefus.conflits(), isEmpty);
      },
    );

    testWidgets(
      '⚠️⚠️ l écran Achats montre « Refusé par le serveur » et le motif',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final (depot, id) = (await tester.runAsync(() async {
          final r = await achatEnAttente();
          await moteur(serveurRefus(r.$2)).synchroniser();
          return r;
        }))!;

        await tester.pumpWidget(
          MaterialApp(home: AchatsCommandesScreen(depot: depot)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key("onglet-achats-Liste d'Achats")));
        await tester.pumpAndSettle();

        expect(find.text('Refusé par le serveur'), findsOneWidget);
        expect(find.text(motif), findsOneWidget);
        expect(find.text('En attente de synchronisation'), findsNothing);
      },
    );

    testWidgets(
      '⚠️ l écran Synchronisation nomme « Achat » et propose Relancer',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        late final SyncEngine m;
        final (_, id) = (await tester.runAsync(() async {
          final r = await achatEnAttente();
          m = moteur(serveurRefus(r.$2));
          await m.synchroniser();
          return r;
        }))!;

        await tester.pumpWidget(
          MaterialApp(
            home: SynchronisationScreen(database: db, engine: m),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Achat'), findsOneWidget);
        expect(find.text('purchases'), findsNothing);
        expect(find.byKey(Key('motif-$id')), findsOneWidget);
        expect(find.byKey(Key('relancer-$id')), findsOneWidget);
      },
    );
  });
}
