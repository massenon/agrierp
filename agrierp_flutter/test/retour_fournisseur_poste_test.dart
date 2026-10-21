import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/achats/achats_commandes_screen.dart';
import 'package:agrierp/features/achats/achats_modales.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serveur de synchronisation feint : sert, tirage après tirage, les blocs [tirages]
/// (le dernier se répète), répond [reponsePush] à l'envoi et note ce qui est envoyé.
/// [echecDuTirage] : numéro (à partir de 0) du tirage qui échoue sur le réseau.
class _ServeurSync extends Interceptor {
  _ServeurSync({
    this.reponsePush = const {},
    this.tirages = const [{}],
    this.echecDuTirage,
  });

  final Map<String, dynamic> reponsePush;
  final List<Map<String, dynamic>> tirages;
  final int? echecDuTirage;
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
      final rang = nbTirages;
      nbTirages++;
      if (echecDuTirage == rang) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        );
        return;
      }
      final bloc = tirages[rang < tirages.length ? rang : tirages.length - 1];
      corps = {
        'server_time': '2026-10-09T12:0$rang:00.000Z',
        'product_categories': <dynamic>[],
        'products': <dynamic>[],
        'livestock_lots': <dynamic>[],
        ...bloc,
      };
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: corps,
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

/// Ticket F0.74 — RETOUR FOURNISSEUR ET REMBOURSEMENT FOURNISSEUR SAISIS AU POSTE
/// (`liste-achats.html`).
///
/// ⚠️⚠️ **LE POSTE N'ÉCRIT QUE LE FAIT.** Il ne décrémente PAS le stock local, ne touche ni
/// la trésorerie, ni la dette, ni une écriture, et n'émet JAMAIS de `stock_adjustments`
/// pour un retour (le serveur décrémente et rejette toute sortie qui le désigne : un
/// ajustement ici serait un double décrément silencieux). Le SERVEUR choisit les lignes
/// concernées et peut refuser.
void main() {
  late AppDatabase db;
  late AchatsRepository depot;

  final aujourdhui = DateTime(2026, 10, 9, 10);

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = AchatsRepository(
      database: db,
      identifiantPoste: 'poste-test',
      horloge: () => aujourdhui,
    );
  });

  tearDown(() async => db.close());

  SyncEngine moteur(_ServeurSync serveur) => SyncEngine(
    database: db,
    client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
      ..interceptors.add(serveur),
    deviceId: 'poste-test',
    connectivity: _ConnectiviteFeinte(),
  );

  Future<void> fournisseur(String cle, String nom, {bool actif = true}) => db
      .into(db.suppliers)
      .insert(
        SuppliersCompanion.insert(
          id: uuid(cle),
          name: nom,
          isActive: Value(actif),
        ),
      );

  Future<void> compte(String cle, String libelle, {double solde = 100000}) => db
      .into(db.treasuryAccounts)
      .insert(
        TreasuryAccountsCompanion.insert(
          id: uuid(cle),
          label: libelle,
          balance: Value(solde),
        ),
      );

  Future<void> produit(String cle, {double stock = 30}) => db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: uuid(cle),
          sku: 'SKU-$cle',
          name: 'Provende $cle',
          unit: 'sac',
          pricingMode: 'fixe',
          stockQty: Value(stock),
        ),
      );

  Future<void> achat(
    String cle, {
    String cleFournisseur = 'f1',
    double total = 100000,
    DateTime? date,
    SyncStatus statut = SyncStatus.synced,
    bool dette = false,
    DateTime? retourneLe,
    double? creance,
  }) => db
      .into(db.purchases)
      .insert(
        PurchasesCompanion.insert(
          id: uuid(cle),
          deviceId: statut == SyncStatus.synced ? 'serveur' : 'poste-test',
          updatedAt: date ?? DateTime(2026, 10, 1),
          syncStatus: Value(statut),
          supplierId: uuid(cleFournisseur),
          supplierName: const Value('Provenderie du Plateau'),
          supplierCategory: const Value('Aliments'),
          paymentMode: 'especes',
          total: total,
          hasDebt: Value(dette),
          purchaseDate: date ?? DateTime(2026, 10, 1),
          returnedAt: Value(retourneLe),
          supplierCredit: Value(creance),
        ),
      );

  Future<void> creanceServeur(String cleFournisseur, double montant) => db
      .into(db.supplierCredits)
      .insert(
        SupplierCreditsCompanion.insert(
          supplierId: uuid(cleFournisseur),
          supplierName: const Value('Provenderie du Plateau'),
          openCredit: montant,
        ),
      );

  /// Empreinte de TOUT ce que le poste ne doit jamais toucher en demandant un retour ou un
  /// remboursement : trésorerie, dettes, stock, achats (toutes colonnes), écritures,
  /// ajustements, créances servies.
  Future<String> empreinte() async {
    final tresor = await db.select(db.treasuryAccounts).get();
    final dettes = await db.select(db.payables).get();
    final produits = await db.select(db.products).get();
    final achats = await db.select(db.purchases).get();
    final lignes = await db.select(db.purchaseLines).get();
    final ecritures = await db.select(db.accountingEntries).get();
    final ecrituresLignes = await db.select(db.accountingEntryLines).get();
    final ajustements = await db.select(db.stockAdjustments).get();
    final creances = await db.select(db.supplierCredits).get();
    final reglements = await db.select(db.supplierPayments).get();
    return [
      for (final t in tresor) 'T:${t.id}:${t.balance}',
      for (final d in dettes)
        'D:${d.id}:${d.amount}:${d.amountPaid}:${d.status}',
      for (final p in produits) 'P:${p.id}:${p.stockQty}',
      for (final a in achats)
        'A:${a.id}:${a.total}:${a.amountPaid}:${a.hasDebt}:${a.syncStatus}:'
            '${a.returnedAt}:${a.supplierCredit}',
      'L:${lignes.length}',
      'E:${ecritures.length}:${ecrituresLignes.length}',
      'J:${ajustements.length}',
      for (final c in creances) 'C:${c.supplierId}:${c.openCredit}',
      'R:${reglements.length}',
    ].join('|');
  }

  /// Créance nette recalculée INDÉPENDAMMENT du dépôt : SQL brut.
  Future<double> netSql(String cleFournisseur) async {
    final c = await db
        .customSelect(
          'SELECT COALESCE(SUM(open_credit), 0) AS t FROM supplier_credits '
          'WHERE supplier_id = ?',
          variables: [Variable<String>(uuid(cleFournisseur))],
        )
        .getSingle();
    final r = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0) AS t FROM supplier_refunds '
          "WHERE supplier_id = ? AND sync_status = 'pending'",
          variables: [Variable<String>(uuid(cleFournisseur))],
        )
        .getSingle();
    final net = c.read<double>('t') - r.read<double>('t');
    return net < 0 ? 0 : net;
  }

  group('enregistrerRetour : refuser avant d’écrire', () {
    setUp(() async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achat('a1');
    });

    Future<void> refuse(
      String fragment, {
      String achatId = '',
      String motif = 'Marchandises endommagées / périmées',
      DateTime? date,
    }) async {
      await expectLater(
        depot.enregistrerRetour(
          achatId: achatId.isEmpty ? uuid('a1') : achatId,
          motif: motif,
          date: date,
        ),
        throwsA(
          isA<SaisieAchatRefusee>().having(
            (e) => e.motif,
            'motif',
            contains(fragment),
          ),
        ),
      );
      expect(await db.select(db.purchaseReturns).get(), isEmpty);
    }

    test('motif vide ou de blancs : refusé', () async {
      await refuse('motif du retour est obligatoire', motif: '');
      await refuse('motif du retour est obligatoire', motif: '   ');
    });

    test('motif de plus de 500 caractères : refusé', () async {
      await refuse('500 caractères', motif: 'x' * 501);
    });

    test('achat inconnu : refusé', () async {
      await refuse('Achat inconnu', achatId: uuid('zz'));
    });

    test(
      '⚠️ achat refusé par le serveur (conflict) : rien à retourner',
      () async {
        await achat('a2', statut: SyncStatus.conflict);
        await refuse("il n'existe pas côté ferme", achatId: uuid('a2'));
      },
    );

    test('date future refusée ; date antérieure à l’achat refusée', () async {
      await refuse('dans le futur', date: DateTime(2026, 10, 10));
      await refuse('précéder celle de l', date: DateTime(2026, 9, 30));
    });

    test('⚠️ marqueur du serveur (returned_at) : déjà retourné', () async {
      await achat('a3', retourneLe: DateTime(2026, 10, 5), creance: 0);
      await refuse('déjà été retourné', achatId: uuid('a3'));
    });

    test(
      '⚠️ retour en attente, acquitté ou refusé non relancé : refusé',
      () async {
        final r = await depot.enregistrerRetour(
          achatId: uuid('a1'),
          motif: 'Erreur de saisie / d\'article',
        );
        await expectLater(
          depot.enregistrerRetour(achatId: uuid('a1'), motif: 'Autre'),
          throwsA(
            isA<SaisieAchatRefusee>().having(
              (e) => e.motif,
              'motif',
              contains('déjà en attente'),
            ),
          ),
        );

        await (db.update(
          db.purchaseReturns,
        )..where((t) => t.id.equals(r.id))).write(
          const PurchaseReturnsCompanion(
            syncStatus: Value(SyncStatus.conflict),
          ),
        );
        await expectLater(
          depot.enregistrerRetour(achatId: uuid('a1'), motif: 'Autre'),
          throwsA(
            isA<SaisieAchatRefusee>().having(
              (e) => e.motif,
              'motif',
              contains('refusé le retour déjà demandé'),
            ),
          ),
        );

        await (db.update(
          db.purchaseReturns,
        )..where((t) => t.id.equals(r.id))).write(
          const PurchaseReturnsCompanion(syncStatus: Value(SyncStatus.synced)),
        );
        await expectLater(
          depot.enregistrerRetour(achatId: uuid('a1'), motif: 'Autre'),
          throwsA(
            isA<SaisieAchatRefusee>().having(
              (e) => e.motif,
              'motif',
              contains('déjà été retourné'),
            ),
          ),
        );
        expect((await db.select(db.purchaseReturns).get()).length, 1);
      },
    );

    test('saisie valide : retour en attente, motif et date du fait', () async {
      final r = await depot.enregistrerRetour(
        achatId: uuid('a1'),
        motif: '  Non-conformité technique à la livraison ',
        date: DateTime(2026, 10, 9, 23, 59),
      );

      expect(r.id.length, 36);
      expect(r.syncStatus, SyncStatus.pending);
      expect(r.purchaseId, uuid('a1'));
      expect(r.reason, 'Non-conformité technique à la livraison');
      expect(r.returnDate, DateTime(2026, 10, 9));
      expect(r.deviceId, 'poste-test');
    });

    test(
      'un achat pas encore envoyé peut être retourné (même envoi)',
      () async {
        await achat('a4', statut: SyncStatus.pending);
        final r = await depot.enregistrerRetour(
          achatId: uuid('a4'),
          motif: 'Erreur de saisie / d\'article',
        );
        expect(r.syncStatus, SyncStatus.pending);
      },
    );
  });

  group('⚠️⚠️ le poste n’écrit que le fait (empreinte, garde-fou du stock)', () {
    setUp(() async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await compte('t1', 'Caisse principale');
      await produit('p1', stock: 30);
      await achat('a1', total: 185000, dette: true);
      await db
          .into(db.purchaseLines)
          .insert(
            PurchaseLinesCompanion.insert(
              id: uuid('l1'),
              purchaseId: uuid('a1'),
              productId: uuid('p1'),
              qty: 10,
              unitPrice: 18500,
            ),
          );
      await creanceServeur('f1', 40000);
    });

    test('⚠️⚠️ un retour ne bouge NI stock, NI trésorerie, NI dette, NI '
        'écriture, NI ajustement', () async {
      final avant = await empreinte();

      await depot.enregistrerRetour(
        achatId: uuid('a1'),
        motif: 'Marchandises endommagées / périmées',
      );

      expect(await empreinte(), avant);
      expect(
        (await (db.select(db.products)).getSingle()).stockQty,
        30,
        reason: 'le stock local ne bouge pas : le serveur décrémente',
      );
      expect(await db.select(db.stockAdjustments).get(), isEmpty);
    });

    test('⚠️⚠️ un remboursement ne bouge ni trésorerie, ni dette, ni écriture, '
        'ni créance servie', () async {
      final avant = await empreinte();

      await depot.enregistrerRemboursement(
        fournisseurId: uuid('f1'),
        montant: 15000,
        date: DateTime(2026, 10, 9),
        compteId: uuid('t1'),
      );

      expect(await empreinte(), avant);
      expect(
        (await db.select(db.treasuryAccounts).getSingle()).balance,
        100000,
      );
    });

    test(
      '⚠️⚠️ AUCUN ajustement de stock ni créé ni ENVOYÉ pour un retour',
      () async {
        await depot.enregistrerRetour(
          achatId: uuid('a1'),
          motif: 'Marchandises endommagées / périmées',
        );
        final serveur = _ServeurSync(
          reponsePush: {
            'purchase_returns': {
              'accepted': <String>[],
              'rejected': <dynamic>[],
            },
          },
        );
        await moteur(serveur).synchroniser();

        final envoi = serveur.envois.single;
        expect(envoi['purchase_returns'], hasLength(1));
        expect(envoi['stock_adjustments'], isEmpty);
        expect(await db.select(db.stockAdjustments).get(), isEmpty);
        // Ni quantité ni ligne dans le retour : annulation COMPLÈTE, lignes choisies par
        // le serveur.
        final retour = (envoi['purchase_returns'] as List).single as Map;
        expect(retour.keys.toSet(), {
          'id',
          'purchase_id',
          'reason',
          'return_date',
        });
      },
    );
  });

  group('enregistrerRemboursement : refuser avant d’écrire', () {
    setUp(() async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await compte('t1', 'Caisse principale');
      await creanceServeur('f1', 40000);
    });

    Future<void> refuse(
      String fragment, {
      double montant = 10000,
      String fournisseurId = '',
      String compteId = '',
      DateTime? date,
    }) async {
      await expectLater(
        depot.enregistrerRemboursement(
          fournisseurId: fournisseurId.isEmpty ? uuid('f1') : fournisseurId,
          montant: montant,
          date: date ?? DateTime(2026, 10, 9),
          compteId: compteId.isEmpty ? uuid('t1') : compteId,
        ),
        throwsA(
          isA<SaisieAchatRefusee>().having(
            (e) => e.motif,
            'motif',
            contains(fragment),
          ),
        ),
      );
      expect(await db.select(db.supplierRefunds).get(), isEmpty);
    }

    test(
      '⚠️ NaN, ±Infinity, zéro, négatif, moins de 1 FCFA : refusés',
      () async {
        for (final m in [
          double.nan,
          double.infinity,
          double.negativeInfinity,
          0.0,
          -5.0,
        ]) {
          await refuse('supérieur à zéro', montant: m);
        }
        await refuse('au moins 1 FCFA', montant: 0.5);
      },
    );

    test(
      '⚠️ la saisie « 1e999 » donne bien Infinity, et est refusée',
      () async {
        final saisi = double.tryParse('1e999');
        expect(saisi, double.infinity);
        await refuse('supérieur à zéro', montant: saisi!);
      },
    );

    test('fournisseur inconnu, compte inconnu : refusés', () async {
      await refuse('Fournisseur inconnu', fournisseurId: uuid('zz'));
      await refuse('Compte de trésorerie inconnu', compteId: uuid('zz'));
    });

    test('date future refusée', () async {
      await refuse('dans le futur', date: DateTime(2026, 10, 10));
    });

    test(
      '⚠️ aucune créance ouverte : refusé, jamais d’argent sans créance',
      () async {
        await fournisseur('f2', 'Véto-Santé Bénin');
        await refuse('aucune créance ouverte', fournisseurId: uuid('f2'));
      },
    );

    test(
      '⚠️⚠️ au-delà de la créance NETTE des remboursements en attente',
      () async {
        // Créance serveur 40 000. Au-delà : refusé.
        await refuse('dépasse la créance ouverte', montant: 40001);

        await depot.enregistrerRemboursement(
          fournisseurId: uuid('f1'),
          montant: 25000,
          date: DateTime(2026, 10, 9),
          compteId: uuid('t1'),
        );
        expect(await depot.creanceNette(uuid('f1')), 15000);
        expect(await netSql('f1'), 15000, reason: 'recalcul SQL indépendant');

        // 15 001 > 40 000 − 25 000 : refusé (plafond reproduit, remboursements en
        // attente déduits).
        await expectLater(
          depot.enregistrerRemboursement(
            fournisseurId: uuid('f1'),
            montant: 15001,
            date: DateTime(2026, 10, 9),
            compteId: uuid('t1'),
          ),
          throwsA(isA<SaisieAchatRefusee>()),
        );

        // Le reste exact passe ; ensuite il n'y a plus rien.
        await depot.enregistrerRemboursement(
          fournisseurId: uuid('f1'),
          montant: 15000,
          date: DateTime(2026, 10, 9),
          compteId: uuid('t1'),
        );
        expect(await netSql('f1'), 0);
        await expectLater(
          depot.enregistrerRemboursement(
            fournisseurId: uuid('f1'),
            montant: 1,
            date: DateTime(2026, 10, 9),
            compteId: uuid('t1'),
          ),
          throwsA(
            isA<SaisieAchatRefusee>().having(
              (e) => e.motif,
              'motif',
              contains('aucune créance ouverte'),
            ),
          ),
        );
        expect(await db.select(db.supplierRefunds).get(), hasLength(2));
      },
    );

    test(
      'un remboursement refusé (conflict) ne se déduit pas de la créance',
      () async {
        final r = await depot.enregistrerRemboursement(
          fournisseurId: uuid('f1'),
          montant: 30000,
          date: DateTime(2026, 10, 9),
          compteId: uuid('t1'),
        );
        await (db.update(
          db.supplierRefunds,
        )..where((t) => t.id.equals(r.id))).write(
          const SupplierRefundsCompanion(
            syncStatus: Value(SyncStatus.conflict),
          ),
        );

        expect(await depot.creanceNette(uuid('f1')), 40000);
        expect(await netSql('f1'), 40000);
      },
    );

    test('saisie valide : remboursement en attente, jour du fait', () async {
      final r = await depot.enregistrerRemboursement(
        fournisseurId: uuid('f1'),
        montant: 12500,
        date: DateTime(2026, 10, 8, 18, 30),
        compteId: uuid('t1'),
      );

      expect(r.syncStatus, SyncStatus.pending);
      expect(r.amount, 12500);
      expect(r.refundDate, DateTime(2026, 10, 8));
      expect(r.treasuryAccountId, uuid('t1'));
      expect(r.deviceId, 'poste-test');
    });

    test('un fournisseur archivé avec créance reste remboursable', () async {
      await fournisseur('f3', 'Ancien fournisseur', actif: false);
      await creanceServeur('f3', 5000);
      final r = await depot.enregistrerRemboursement(
        fournisseurId: uuid('f3'),
        montant: 5000,
        date: DateTime(2026, 10, 9),
        compteId: uuid('t1'),
      );
      expect(r.amount, 5000);
    });
  });

  group('synchronisation', () {
    Future<void> garnir() async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await compte('t1', 'Caisse principale');
      await achat('a1', total: 185000);
    }

    Map<String, dynamic> achatServi({
      String id = 'a1',
      String? retourneLe,
      double? credit,
      bool dette = false,
    }) => {
      'id': uuid(id),
      'supplier_id': uuid('f1'),
      'supplier_name': 'Provenderie du Plateau',
      'supplier_category': 'Aliments',
      'payment_mode': 'especes',
      'total': 185000,
      'purchase_date': '2026-10-01',
      'has_debt': dette,
      'returned_at': retourneLe,
      'supplier_credit': credit,
    };

    test(
      '⚠️ l’envoi : champs exacts, device_id à la racine, jour en Y-m-d',
      () async {
        await garnir();
        await depot.enregistrerRetour(
          achatId: uuid('a1'),
          motif: 'Erreur de saisie / d\'article',
          date: DateTime(2026, 10, 8),
        );
        await creanceServeur('f1', 40000);
        await depot.enregistrerRemboursement(
          fournisseurId: uuid('f1'),
          montant: 12000,
          date: DateTime(2026, 10, 9),
          compteId: uuid('t1'),
        );
        final retour = await db.select(db.purchaseReturns).getSingle();
        final remb = await db.select(db.supplierRefunds).getSingle();

        final serveur = _ServeurSync();
        await moteur(serveur).synchroniser();

        final envoi = serveur.envois.single;
        expect(envoi['device_id'], 'poste-test');
        expect(envoi['purchase_returns'], [
          {
            'id': retour.id,
            'purchase_id': uuid('a1'),
            'reason': 'Erreur de saisie / d\'article',
            'return_date': '2026-10-08',
          },
        ]);
        expect(envoi['supplier_refunds'], [
          {
            'id': remb.id,
            'supplier_id': uuid('f1'),
            'treasury_account_id': uuid('t1'),
            'amount': 12000.0,
            'refund_date': '2026-10-09',
          },
        ]);
      },
    );

    test(
      '⚠️ acquitté SEULEMENT sur réponse : sans accusé, tout reste en attente',
      () async {
        await garnir();
        await creanceServeur('f1', 40000);
        await depot.enregistrerRetour(achatId: uuid('a1'), motif: 'x');
        await depot.enregistrerRemboursement(
          fournisseurId: uuid('f1'),
          montant: 1000,
          date: DateTime(2026, 10, 9),
          compteId: uuid('t1'),
        );

        await moteur(_ServeurSync()).synchroniser();

        expect(
          (await db.select(db.purchaseReturns).getSingle()).syncStatus,
          SyncStatus.pending,
        );
        expect(
          (await db.select(db.supplierRefunds).getSingle()).syncStatus,
          SyncStatus.pending,
        );
      },
    );

    test(
      'accepté : acquitté ; rejeté : conflict + motif MOT POUR MOT ; relançable',
      () async {
        await garnir();
        await creanceServeur('f1', 40000);
        final retour = await depot.enregistrerRetour(
          achatId: uuid('a1'),
          motif: 'x',
        );
        final remb = await depot.enregistrerRemboursement(
          fournisseurId: uuid('f1'),
          montant: 1000,
          date: DateTime(2026, 10, 9),
          compteId: uuid('t1'),
        );
        const motifRetour =
            'Stock insuffisant pour retourner « Provende p1 » : 10 à rendre, 4 en '
            'stock. Le stock ne peut pas devenir négatif.';
        const motifRemb = 'Écriture impossible : le compte 409 est absent.';

        final serveur = _ServeurSync(
          reponsePush: {
            'purchase_returns': {
              'accepted': <String>[],
              'rejected': [
                {'id': retour.id, 'reason': motifRetour},
              ],
            },
            'supplier_refunds': {
              'accepted': <String>[],
              'rejected': [
                {'id': remb.id, 'reason': motifRemb},
              ],
            },
          },
        );
        final m = moteur(serveur);
        final resultat = await m.synchroniser();

        expect(resultat.rejete, 2);
        expect(resultat.motifs, containsAll([motifRetour, motifRemb]));
        expect(
          (await db.select(db.purchaseReturns).getSingle()).syncStatus,
          SyncStatus.conflict,
        );
        final conflits = await m.conflits();
        expect(
          conflits.map((c) => c.reason),
          containsAll([motifRetour, motifRemb]),
        );
        expect(
          conflits.map((c) => c.sourceTable),
          containsAll(['purchase_returns', 'supplier_refunds']),
        );

        // Écran : le motif est repris MOT POUR MOT (voir le groupe écran) ; ici la relance.
        for (final c in conflits) {
          await m.relancer(c);
        }
        expect(
          (await db.select(db.purchaseReturns).getSingle()).syncStatus,
          SyncStatus.pending,
        );
        expect(
          (await db.select(db.supplierRefunds).getSingle()).syncStatus,
          SyncStatus.pending,
        );
        expect(await m.conflits(), isEmpty);

        // Relancé puis ré-envoyé : le même id repart (le serveur l'acquitte sans effet).
        final serveur2 = _ServeurSync();
        await moteur(serveur2).synchroniser();
        expect(
          ((serveur2.envois.single['purchase_returns']) as List).single['id'],
          retour.id,
        );
      },
    );

    test('⚠️⚠️ TIRAGE DE CONFIRMATION : après acquittement, la créance et le '
        'marqueur du serveur sont relus', () async {
      await garnir();
      await creanceServeur('f1', 40000);
      final remb = await depot.enregistrerRemboursement(
        fournisseurId: uuid('f1'),
        montant: 15000,
        date: DateTime(2026, 10, 9),
        compteId: uuid('t1'),
      );
      final retour = await depot.enregistrerRetour(
        achatId: uuid('a1'),
        motif: 'x',
      );

      final serveur = _ServeurSync(
        reponsePush: {
          'purchase_returns': {
            'accepted': [retour.id],
            'rejected': <dynamic>[],
          },
          'supplier_refunds': {
            'accepted': [remb.id],
            'rejected': <dynamic>[],
          },
        },
        tirages: [
          // Avant l'envoi : créance 40 000, achat pas retourné.
          {
            'purchases': [achatServi()],
            'supplier_credits': [
              {
                'supplier_id': uuid('f1'),
                'supplier_name': 'Provenderie du Plateau',
                'open_credit': 40000,
              },
            ],
          },
          // Après : le serveur a retourné l'achat (la part payée 185 000 est devenue
          // créance : 40 000 + 185 000 − 15 000 remboursés).
          {
            'purchases': [
              achatServi(
                retourneLe: '2026-10-09T10:05:00+01:00',
                credit: 185000,
              ),
            ],
            'supplier_credits': [
              {
                'supplier_id': uuid('f1'),
                'supplier_name': 'Provenderie du Plateau',
                'open_credit': 210000,
              },
            ],
          },
        ],
      );
      // La base locale a déjà l'achat a1 `synced` et la créance 40 000.
      final m = moteur(serveur);
      await m.synchroniser();

      expect(
        serveur.nbTirages,
        2,
        reason: 'un tirage de confirmation, un seul',
      );
      final a = await (db.select(
        db.purchases,
      )..where((t) => t.id.equals(uuid('a1')))).getSingle();
      expect(a.returnedAt, isNotNull);
      expect(a.supplierCredit, 185000);
      expect(await depot.creanceNette(uuid('f1')), 210000);
      expect(
        (await db.select(db.supplierRefunds).getSingle()).syncStatus,
        SyncStatus.synced,
        reason:
            'acquitté : plus déduit en attente, la créance servie l’a absorbé',
      );
    });

    test(
      '⚠️ pas de tirage de confirmation s’il n’y a rien eu d’acquitté',
      () async {
        await garnir();
        final serveur = _ServeurSync();
        await moteur(serveur).synchroniser();
        expect(serveur.nbTirages, 1);
      },
    );

    test('⚠️ échec réseau du tirage de confirmation : rien n’est annulé, '
        'l’achat reste « retourné »', () async {
      await garnir();
      final retour = await depot.enregistrerRetour(
        achatId: uuid('a1'),
        motif: 'x',
      );
      final serveur = _ServeurSync(
        reponsePush: {
          'purchase_returns': {
            'accepted': [retour.id],
            'rejected': <dynamic>[],
          },
        },
        echecDuTirage: 1,
      );

      final resultat = await moteur(serveur).synchroniser();
      expect(resultat.accepte, 1);
      expect(
        (await db.select(db.purchaseReturns).getSingle()).syncStatus,
        SyncStatus.synced,
      );

      final d = await depot.charger();
      final ligne = d.achats.single;
      expect(ligne.retourne, isTrue, reason: 'acquitté vaut fait accompli');
      expect(ligne.statut, 'Retourné');
      expect(ligne.retournable, isFalse);
      await expectLater(
        depot.enregistrerRetour(achatId: uuid('a1'), motif: 'y'),
        throwsA(isA<SaisieAchatRefusee>()),
      );
    });
  });

  group('tirage : fusion, jamais d’écrasement', () {
    Future<void> garnir() async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await compte('t1', 'Caisse principale');
    }

    Map<String, dynamic> servi(
      String id, {
      String? retourneLe,
      double? credit,
      double total = 185000,
      bool dette = false,
    }) => {
      'id': uuid(id),
      'supplier_id': uuid('f1'),
      'supplier_name': 'Provenderie du Plateau',
      'supplier_category': 'Aliments',
      'payment_mode': 'especes',
      'total': total,
      'purchase_date': '2026-10-01',
      'has_debt': dette,
      'returned_at': retourneLe,
      'supplier_credit': credit,
    };

    test(
      '⚠️⚠️ un achat marqué retourné par le serveur remplace l’état local',
      () async {
        await garnir();
        await achat('a1', dette: true);

        await moteur(
          _ServeurSync(
            tirages: [
              {
                'purchases': [
                  servi(
                    'a1',
                    retourneLe: '2026-10-09T10:00:00+01:00',
                    credit: 60000,
                    total: 100000,
                  ),
                ],
              },
            ],
          ),
        ).synchroniser();

        final a = await db.select(db.purchases).getSingle();
        expect(a.returnedAt, isNotNull);
        expect(a.supplierCredit, 60000);
        expect(
          a.hasDebt,
          isFalse,
          reason: 'has_debt passe à false pour un retourné',
        );

        final ligne = (await depot.charger()).achats.single;
        expect(ligne.statut, 'Retourné');
        expect(ligne.retournable, isFalse);
      },
    );

    test('⚠️⚠️ DEUX TIRAGES SUCCESSIFS : un retour et un remboursement pending '
        'survivent, un achat pending n’est pas écrasé', () async {
      await garnir();
      await creanceServeur('f1', 40000);
      await achat('a1');
      await achat('a2', statut: SyncStatus.pending, total: 777);
      final retour = await depot.enregistrerRetour(
        achatId: uuid('a2'),
        motif: 'x',
      );
      final remb = await depot.enregistrerRemboursement(
        fournisseurId: uuid('f1'),
        montant: 10000,
        date: DateTime(2026, 10, 9),
        compteId: uuid('t1'),
      );

      // Le serveur sert, au premier tirage, l'achat a1 (retourné) ET l'id de l'achat
      // pending a2 avec un autre total (accusé perdu) ; au second, plus rien de neuf.
      final serveur = _ServeurSync(
        tirages: [
          {
            'purchases': [
              servi('a1', retourneLe: '2026-10-09T10:00:00+01:00', credit: 5),
              servi('a2', total: 999999),
            ],
            'supplier_credits': [
              {
                'supplier_id': uuid('f1'),
                'supplier_name': 'Provenderie du Plateau',
                'open_credit': 40000,
              },
            ],
          },
          <String, dynamic>{},
        ],
      );
      final m = moteur(serveur);
      await m.synchroniser();
      await m.synchroniser();

      // L'achat pending n'est NI écrasé NI marqué synced par le tirage.
      final a2 = await (db.select(
        db.purchases,
      )..where((t) => t.id.equals(uuid('a2')))).getSingle();
      expect(a2.total, 777);
      expect(a2.syncStatus, SyncStatus.pending);

      // Le retour et le remboursement du poste survivent aux deux tirages (l'envoi
      // n'a reçu aucun accusé : toujours en attente).
      expect((await db.select(db.purchaseReturns).get()).map((r) => r.id), [
        retour.id,
      ]);
      expect((await db.select(db.supplierRefunds).get()).map((r) => r.id), [
        remb.id,
      ]);
      expect(
        (await db.select(db.purchaseReturns).getSingle()).syncStatus,
        SyncStatus.pending,
      );
      // Et la créance nette en tient compte : 40 000 − 10 000 en attente.
      expect(await depot.creanceNette(uuid('f1')), 30000);
      expect(await netSql('f1'), 30000);
    });

    test(
      'créances servies : remplacées en entier ; liste vide = tout remboursé',
      () async {
        await garnir();
        await fournisseur('f2', 'Véto-Santé Bénin');
        await creanceServeur('f1', 40000);

        final bloc = {
          'supplier_id': uuid('f2'),
          'supplier_name': 'Véto-Santé Bénin',
          'open_credit': 7000,
        };
        final serveur = _ServeurSync(
          tirages: [
            {
              'supplier_credits': [bloc],
            },
            {'supplier_credits': <dynamic>[]},
          ],
        );
        final m = moteur(serveur);

        await m.synchroniser();
        final apres1 = await db.select(db.supplierCredits).get();
        expect(apres1.map((c) => c.supplierId), [uuid('f2')]);
        expect(apres1.single.openCredit, 7000);

        await m.synchroniser();
        expect(await db.select(db.supplierCredits).get(), isEmpty);
      },
    );

    test(
      '⚠️ clé « supplier_credits » ABSENTE (serveur plus ancien) : rien n’est touché',
      () async {
        await garnir();
        await creanceServeur('f1', 40000);

        await moteur(_ServeurSync()).synchroniser();

        expect(
          (await db.select(db.supplierCredits).getSingle()).openCredit,
          40000,
        );
      },
    );

    test(
      '⚠️ clé « returned_at » absente : le marqueur local n’est pas effacé',
      () async {
        await garnir();
        await achat('a1', retourneLe: DateTime(2026, 10, 5), creance: 1000);
        final sansCle = servi('a1')
          ..remove('returned_at')
          ..remove('supplier_credit');

        await moteur(
          _ServeurSync(
            tirages: [
              {
                'purchases': [sansCle],
              },
            ],
          ),
        ).synchroniser();

        final a = await db.select(db.purchases).getSingle();
        expect(a.returnedAt, isNotNull);
        expect(a.supplierCredit, 1000);
      },
    );
  });

  group('garde-fou source', () {
    /// ⚠️⚠️ Le défaut qu'il verrouille ne fait AUCUN bruit : un retour qui décrémente aussi
    /// le stock local, ou qui émet un ajustement, double le décrément quand le serveur
    /// rejoue — ou est rejeté sans que personne ne comprenne pourquoi. Le test lit le
    /// CODE (commentaires exclus), comme `conformite_portage_test`.
    test(
      '⚠️⚠️ le dépôt d’achats ne touche ni stock, ni ajustement, ni trésorerie',
      () {
        final code = File('lib/features/achats/achats_repository.dart')
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');

        for (final interdit in [
          'stockAdjustments',
          'stock_adjustments',
          'StockAdjustments',
          'stockQty',
          'stock_qty',
          'accountingEntries',
          // ⚠️ F0.77 : la LECTURE des dettes servies est légitime (reste dû de « Dettes en
          // Cours ») ; c'est leur ÉCRITURE qui est interdite au poste.
          'into(database.payables)',
          'update(database.payables)',
          'delete(database.payables)',
        ]) {
          expect(code, isNot(contains(interdit)), reason: interdit);
        }
      },
    );

    test(
      '⚠️ le moteur n’associe jamais un retour à un ajustement de stock',
      () {
        final code = File('lib/core/sync/sync_engine.dart')
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        final json = code.substring(
          code.indexOf('Map<String, dynamic> _retourEnJson'),
          code.indexOf('Map<String, dynamic> _remboursementEnJson'),
        );

        expect(json, isNot(contains('stock')));
        expect(json, isNot(contains('qty')));
        expect(json, isNot(contains('quantity')));
      },
    );
  });

  group('migration v31 → v32', () {
    test('⚠️ une base v31 (sans les deux colonnes ni les trois tables) est '
        'migrée sans perdre l’achat', () async {
      // Deux instances successives sur le même fichier, VOULUES (on rouvre la base).
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );
      final dossier = Directory.systemTemp.createTempSync('agrierp_v31_');
      final fichier = File('${dossier.path}${Platform.pathSeparator}v31.db');
      addTearDown(() {
        try {
          dossier.deleteSync(recursive: true);
        } catch (_) {}
      });

      // 1) Une base à jour, avec un achat dedans.
      final neuve = AppDatabase.forTesting(NativeDatabase(fichier));
      await neuve
          .into(neuve.suppliers)
          .insert(
            SuppliersCompanion.insert(id: uuid('f1'), name: 'Fournisseur'),
          );
      await neuve
          .into(neuve.purchases)
          .insert(
            PurchasesCompanion.insert(
              id: uuid('a1'),
              deviceId: 'serveur',
              updatedAt: DateTime(2026, 7, 14),
              supplierId: uuid('f1'),
              paymentMode: 'especes',
              total: 185000,
              purchaseDate: DateTime(2026, 7, 14),
            ),
          );
      await neuve.close();

      // 2) On la ramène à la forme v31 : colonnes et tables du ticket retirées.
      var colonnesAvant = <String>[];
      final v31 = AppDatabase.forTesting(
        NativeDatabase(
          fichier,
          setup: (raw) {
            raw.execute('ALTER TABLE purchases DROP COLUMN returned_at');
            raw.execute('ALTER TABLE purchases DROP COLUMN supplier_credit');
            raw.execute('DROP TABLE purchase_returns');
            raw.execute('DROP TABLE supplier_refunds');
            raw.execute('DROP TABLE supplier_credits');
            // F0.78 (schéma v33) : une vraie base v31 n'a pas non plus les deux colonnes
            // de `mails` ; sans les retirer, la migration v33 les ajouterait en double.
            raw.execute('ALTER TABLE mails DROP COLUMN is_active');
            raw.execute('ALTER TABLE mails DROP COLUMN sync_status');
            raw.execute('ALTER TABLE mails DROP COLUMN known_by_server');
            // F0.79 (schéma v35) : idem pour les trois colonnes des archives.
            raw.execute('ALTER TABLE archived_documents DROP COLUMN is_active');
            raw.execute(
              'ALTER TABLE archived_documents DROP COLUMN sync_status',
            );
            raw.execute(
              'ALTER TABLE archived_documents DROP COLUMN known_by_server',
            );
            // F0.80 (schéma v36) : idem pour les trois colonnes des documents administratifs.
            for (final c in ['is_active', 'sync_status', 'known_by_server']) {
              raw.execute(
                'ALTER TABLE administrative_documents DROP COLUMN $c',
              );
            }
            // F0.85 (schéma v37) : une vraie base plus ancienne n'a pas non plus la date de création
            // des écritures.
            raw.execute(
              'ALTER TABLE accounting_entries DROP COLUMN created_at',
            );
            raw.execute('PRAGMA user_version = 31');
            colonnesAvant = [
              for (final l in raw.select('PRAGMA table_info(purchases)'))
                l['name'] as String,
            ];
          },
        ),
      );
      // Ouvrir la base déclenche la migration 31 → 32.
      final apres = await v31.select(v31.purchases).getSingle();
      expect(colonnesAvant, isNot(contains('returned_at')));
      expect(colonnesAvant, isNot(contains('supplier_credit')));

      expect(apres.id, uuid('a1'));
      expect(apres.total, 185000);
      expect(apres.returnedAt, isNull);
      expect(apres.supplierCredit, isNull);

      // Les trois tables existent et fonctionnent.
      await v31
          .into(v31.purchaseReturns)
          .insert(
            PurchaseReturnsCompanion.insert(
              id: uuid('r1'),
              deviceId: 'poste-test',
              updatedAt: DateTime(2026, 10, 9),
              purchaseId: uuid('a1'),
              reason: 'x',
              returnDate: DateTime(2026, 10, 9),
            ),
          );
      await v31
          .into(v31.supplierRefunds)
          .insert(
            SupplierRefundsCompanion.insert(
              id: uuid('m1'),
              deviceId: 'poste-test',
              updatedAt: DateTime(2026, 10, 9),
              supplierId: uuid('f1'),
              treasuryAccountId: uuid('t1'),
              amount: 1000,
              refundDate: DateTime(2026, 10, 9),
            ),
          );
      await v31
          .into(v31.supplierCredits)
          .insert(
            SupplierCreditsCompanion.insert(
              supplierId: uuid('f1'),
              openCredit: 1,
            ),
          );
      expect(await v31.select(v31.purchaseReturns).get(), hasLength(1));
      expect(await v31.select(v31.supplierRefunds).get(), hasLength(1));
      expect(await v31.select(v31.supplierCredits).get(), hasLength(1));
      await v31.close();
    });
  });

  group('écran « Liste d’Achats »', () {
    late AchatsRepository depotEcran;

    setUp(() {
      // Horloge réelle : la modale de remboursement date du jour même.
      depotEcran = AchatsRepository(
        database: db,
        identifiantPoste: 'poste-test',
      );
    });

    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(home: AchatsCommandesScreen(depot: depotEcran)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key("onglet-achats-Liste d'Achats")));
      await tester.pumpAndSettle();
    }

    Future<void> choisir(WidgetTester tester, String cle, String texte) async {
      await tester.tap(find.byKey(Key(cle)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(texte).last);
      await tester.pumpAndSettle();
    }

    Future<void> jeu() async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await compte('t1', 'Caisse principale');
      // Trié du plus récent au plus ancien : a3 (ligne 0), a2 (ligne 1), a1 (ligne 2).
      await achat('a1', total: 185000, date: DateTime(2026, 7, 14));
      await achat('a2', total: 62500, date: DateTime(2026, 8, 2), dette: true);
      await achat('a3', total: 100000, date: DateTime(2026, 9, 2));
    }

    testWidgets('⚠️ boutons de la maquette : « Ajouter Remboursement » et le '
        'retour de chaque ligne', (tester) async {
      await jeu();
      await afficher(tester);

      expect(find.text('Ajouter Remboursement'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('retour-achat-$i')), findsOneWidget);
      }
    });

    testWidgets('⚠️⚠️ « Retour Fournisseur » : motif obligatoire, rien d’écrit '
        'sans lui', (tester) async {
      await jeu();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('retour-achat-2')));
      await tester.pumpAndSettle();

      expect(find.text('Retour Fournisseur'), findsOneWidget);
      expect(find.text("MOTIF DE L'ANNULATION / RETOUR"), findsOneWidget);
      expect(find.text('Confirmer le Retour'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      // L'écran dit que le SERVEUR choisit les lignes et peut refuser.
      expect(
        find.textContaining('le SERVEUR qui choisit les lignes'),
        findsOneWidget,
      );
      expect(find.textContaining('Il peut REFUSER'), findsOneWidget);

      await tester.tap(find.byKey(const Key('retour-confirmer')));
      await tester.pumpAndSettle();

      expect(find.text('Ce champ est obligatoire.'), findsOneWidget);
      expect(await db.select(db.purchaseReturns).get(), isEmpty);
    });

    testWidgets(
      '⚠️⚠️ retour confirmé : écrit en attente, pastille, bouton retiré, '
      'rien d’autre ne bouge',
      (tester) async {
        await jeu();
        await afficher(tester);
        final avant = await empreinte();

        await tester.tap(find.byKey(const Key('retour-achat-2')));
        await tester.pumpAndSettle();
        await choisir(tester, 'retour-motif', motifsRetour[0]);
        await tester.tap(find.byKey(const Key('retour-confirmer')));
        await tester.pumpAndSettle();

        final r = await db.select(db.purchaseReturns).getSingle();
        expect(r.syncStatus, SyncStatus.pending);
        expect(r.purchaseId, uuid('a1'));
        expect(r.reason, motifsRetour[0]);
        expect(await empreinte(), avant);

        expect(
          find.byKey(const Key('pastille-retour-liste-2')),
          findsOneWidget,
        );
        expect(find.text('Retour en attente'), findsOneWidget);
        expect(find.byKey(const Key('retour-achat-2')), findsNothing);
        expect(find.byKey(const Key('retour-achat-1')), findsOneWidget);
      },
    );

    testWidgets('⚠️ « Retour Fournisseur » du détail ouvre la même modale', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('voir-achat-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-retour')), findsOneWidget);

      await tester.tap(find.byKey(const Key('detail-retour')));
      await tester.pumpAndSettle();

      expect(find.text('Confirmer le Retour'), findsOneWidget);
    });

    testWidgets(
      '⚠️⚠️ statut « Retourné » : plus de bouton, ni dans la ligne ni '
      'dans le détail',
      (tester) async {
        await fournisseur('f1', 'Provenderie du Plateau');
        await achat(
          'a1',
          retourneLe: DateTime(2026, 10, 5),
          creance: 100000,
          date: DateTime(2026, 9, 2),
        );
        await afficher(tester);

        expect(find.text('Retourné'), findsOneWidget);
        expect(find.byKey(const Key('retour-achat-0')), findsNothing);

        await tester.tap(find.byKey(const Key('voir-achat-0')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('detail-retour')), findsNothing);
      },
    );

    testWidgets(
      '⚠️⚠️ un retour refusé affiche le motif du serveur MOT POUR MOT',
      (tester) async {
        await jeu();
        final r = await depot.enregistrerRetour(
          achatId: uuid('a1'),
          motif: 'x',
        );
        const motif =
            'Stock insuffisant pour retourner « Provende p1 » : 10 à rendre, 4 en '
            'stock. Le stock ne peut pas devenir négatif.';
        await (db.update(
          db.purchaseReturns,
        )..where((t) => t.id.equals(r.id))).write(
          const PurchaseReturnsCompanion(
            syncStatus: Value(SyncStatus.conflict),
          ),
        );
        await db
            .into(db.syncConflicts)
            .insert(
              SyncConflictsCompanion.insert(
                id: 'purchase_returns:${r.id}',
                sourceTable: 'purchase_returns',
                recordId: r.id,
                reason: motif,
                detectedAt: DateTime(2026, 10, 9),
              ),
            );
        await afficher(tester);

        expect(find.text('Retour refusé par le serveur'), findsOneWidget);
        expect(find.text(motif), findsOneWidget);
        expect(find.byKey(const Key('retour-achat-2')), findsNothing);
      },
    );

    testWidgets('⚠️ « Ajouter un Remboursement » : champs de la maquette, '
        'obligatoires signalés', (tester) async {
      await jeu();
      await creanceServeur('f1', 40000);
      await afficher(tester);

      await tester.tap(find.byKey(const Key('ajouter-remboursement')));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter un Remboursement'), findsOneWidget);
      for (final libelle in [
        'Fournisseur *',
        'Montant Remboursé (FCFA) *',
        // Ticket MP1 : libellé de champ Date en majuscules, comme le `uppercase` du Blade.
        'DATE DU REMBOURSEMENT *',
        'Compte de Trésorerie',
        'Annuler',
        'Enregistrer',
      ]) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }

      await tester.tap(find.byKey(const Key('remb-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.text('Ce champ est obligatoire.'), findsNWidgets(2));
      expect(await db.select(db.supplierRefunds).get(), isEmpty);
    });

    testWidgets('⚠️⚠️ remboursement au-delà de la créance : refusé avec motif, '
        'puis valide : en attente et listé', (tester) async {
      await jeu();
      await creanceServeur('f1', 40000);
      await afficher(tester);

      await tester.tap(find.byKey(const Key('ajouter-remboursement')));
      await tester.pumpAndSettle();
      await choisir(tester, 'remb-fournisseur', 'Provenderie du Plateau');
      expect(find.byKey(const Key('remb-creance')), findsOneWidget);
      expect(find.textContaining('40 000 FCFA'), findsWidgets);

      await tester.enterText(find.byKey(const Key('remb-montant')), '50000');
      await tester.tap(find.byKey(const Key('remb-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('remb-refus')), findsOneWidget);
      expect(find.textContaining('dépasse la créance ouverte'), findsOneWidget);
      expect(await db.select(db.supplierRefunds).get(), isEmpty);

      await tester.enterText(find.byKey(const Key('remb-montant')), '15000');
      await tester.tap(find.byKey(const Key('remb-enregistrer')));
      await tester.pumpAndSettle();

      final r = await db.select(db.supplierRefunds).getSingle();
      expect(r.syncStatus, SyncStatus.pending);
      expect(r.amount, 15000);
      expect(r.treasuryAccountId, uuid('t1'));
      expect(find.byKey(const Key('remboursements-poste')), findsOneWidget);
      expect(find.text('Remboursement en attente'), findsOneWidget);
      expect(await netSql('f1'), 25000);
    });

    testWidgets('⚠️⚠️ « Écarts / Retours » : plus de tiret, recalculé '
        'indépendamment', (tester) async {
      await jeu();
      // Ticket U8 — la carte compte des LIGNES de retour, comme le web (`PurchaseReturn::count()`).
      // a1 retourné d'après le serveur, ses 2 lignes de retour SERVIES ; a2 retourné d'après un accusé du poste,
      // lignes de retour pas encore servies → ses 3 lignes d'achat (une ligne de retour par ligne d'achat) ;
      // a3 en attente (non compté).
      Future<void> lignesAchat(String achat, int n) async {
        for (var i = 0; i < n; i++) {
          await db.into(db.purchaseLines).insert(
            PurchaseLinesCompanion.insert(
              id: uuid('la-$achat-$i'),
              purchaseId: uuid(achat),
              productId: uuid('p1'),
              qty: 1,
              unitPrice: 1000,
            ),
          );
        }
      }

      await lignesAchat('a1', 2);
      await lignesAchat('a2', 3);
      await lignesAchat('a3', 4);
      await (db.update(db.purchases)..where((t) => t.id.equals(uuid('a1'))))
          .write(PurchasesCompanion(returnedAt: Value(DateTime(2026, 10, 5))));
      for (var i = 0; i < 2; i++) {
        await db.into(db.purchaseReturns).insert(
          PurchaseReturnsCompanion.insert(
            id: uuid('rs-a1-$i'),
            deviceId: 'serveur',
            syncStatus: const Value(SyncStatus.synced),
            updatedAt: DateTime(2026, 10, 5),
            purchaseId: uuid('a1'),
            reason: 'Avarie',
            returnDate: DateTime(2026, 10, 5),
          ),
        );
      }
      final r2 = await depot.enregistrerRetour(achatId: uuid('a2'), motif: 'x');
      await (db.update(
        db.purchaseReturns,
      )..where((t) => t.id.equals(r2.id))).write(
        const PurchaseReturnsCompanion(syncStatus: Value(SyncStatus.synced)),
      );
      await depot.enregistrerRetour(achatId: uuid('a3'), motif: 'x');

      final attendu =
          (await db
                  .customSelect(
                    "SELECT (SELECT COUNT(*) FROM purchase_returns WHERE device_id = 'serveur' "
                    "AND sync_status = 'synced') + (SELECT COUNT(*) FROM purchase_lines l "
                    'JOIN purchases p ON p.id = l.purchase_id WHERE (p.returned_at IS NOT NULL '
                    'OR EXISTS (SELECT 1 FROM purchase_returns r WHERE r.purchase_id = p.id '
                    "AND r.sync_status = 'synced')) AND NOT EXISTS (SELECT 1 FROM purchase_returns s "
                    "WHERE s.purchase_id = p.id AND s.device_id = 'serveur')) AS n",
                  )
                  .getSingle())
              .read<int>('n');
      expect(attendu, 5);

      await afficher(tester);

      final carte = find.byKey(const Key('kpi-achats-ecarts'));
      expect(
        find.descendant(of: carte, matching: find.text('$attendu')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: carte, matching: find.text('—')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: carte,
          matching: find.textContaining('1 demande(s) en attente'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      '⚠️ « Dépenses Totales » : comme le SERVEUR (retournés compris), '
      'et le dit',
      (tester) async {
        await jeu();
        await (db.update(
          db.purchases,
        )..where((t) => t.id.equals(uuid('a3')))).write(
          PurchasesCompanion(returnedAt: Value(DateTime(2026, 10, 5))),
        );
        await afficher(tester);

        final somme =
            (await db
                    .customSelect('SELECT SUM(total) AS t FROM purchases')
                    .getSingle())
                .read<double>('t');
        expect(somme, 347500);

        final carte = find.byKey(const Key('kpi-achats-depenses'));
        expect(
          find.descendant(of: carte, matching: find.text('347 500')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: carte,
            matching: find.textContaining('100 000 FCFA retournés'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('⚠️ la mention dit que le serveur choisit les lignes et peut '
        'refuser', (tester) async {
      await jeu();
      await afficher(tester);

      final mention = find.byKey(const Key('mention-retours'));
      expect(mention, findsOneWidget);
      expect(
        find.descendant(
          of: mention,
          matching: find.textContaining('choisit les lignes concernées'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('se font sur la surface web'), findsNothing);
    });
  });
}
