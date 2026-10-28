import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/clients/clients_creances_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serveur de synchronisation feint : sert, tirage après tirage, les blocs [tirages]
/// (le dernier se répète), répond [reponsePush] à l'envoi et note ce qui est envoyé.
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
      final bloc =
          tirages[nbTirages < tirages.length ? nbTirages : tirages.length - 1];
      nbTirages++;
      corps = {
        'server_time': '2026-10-09T12:0$nbTirages:00.000Z',
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

/// Ticket F0.73 — AVANCES ET IMPUTATIONS D'ACOMPTE SAISIES AU POSTE
/// (`historique-avances.html`).
///
/// ⚠️⚠️ **LE POSTE N'ÉCRIT QUE LE FAIT.** Il ne modifie NI un solde de trésorerie, NI
/// `amount_used`, NI `receivables.amount_paid` : le serveur plafonne, entre l'argent dans
/// les deux livres et passe D 5xx / C 419 puis D 419 / C 411. Il affiche des soldes NETS
/// de ce qu'il a saisi et que le serveur n'a pas encore appliqué.
void main() {
  late AppDatabase db;
  late ClientsCreancesRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ClientsCreancesRepository(database: db, deviceId: 'poste-test');
  });

  tearDown(() async => db.close());

  SyncEngine moteur(_ServeurSync serveur) => SyncEngine(
    database: db,
    client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
      ..interceptors.add(serveur),
    deviceId: 'poste-test',
    connectivity: _ConnectiviteFeinte(),
  );

  Future<void> client(String cle, String nom, {bool actif = true}) => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
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

  Future<void> creance(
    String cle,
    String cleClient, {
    required double montant,
    double regle = 0,
  }) => db
      .into(db.receivables)
      .insert(
        ReceivablesCompanion.insert(
          id: uuid(cle),
          customerId: uuid(cleClient),
          amount: montant,
          amountPaid: Value(regle),
          dueDate: Value(DateTime(2026, 11, 8)),
        ),
      );

  Future<void> avance(
    String cle,
    String cleClient, {
    required double montant,
    double utilise = 0,
    SyncStatus statut = SyncStatus.synced,
    bool active = true,
  }) => db
      .into(db.customerAdvances)
      .insert(
        CustomerAdvancesCompanion.insert(
          id: uuid(cle),
          customerId: uuid(cleClient),
          amount: montant,
          amountUsed: Value(utilise),
          advanceDate: Value(DateTime(2026, 10, 1)),
          isActive: Value(active),
          syncStatus: Value(statut),
        ),
      );

  /// Somme INDÉPENDANTE du dépôt : SQL brut sur la table, pas le code testé.
  Future<double> sommeEnAttente(String colonne, String id) async {
    final ligne = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0) AS t FROM advance_imputations '
          "WHERE $colonne = ? AND sync_status = 'pending'",
          variables: [Variable<String>(id)],
        )
        .getSingle();
    return ligne.read<double>('t');
  }

  /// Empreinte de ce que le poste ne doit JAMAIS toucher en saisissant.
  Future<String> empreinteIntouchable({String? sauf}) async {
    final tresor = await db.select(db.treasuryAccounts).get();
    final creances = await db.select(db.receivables).get();
    final ecritures = await db.select(db.accountingEntries).get();
    final avances = await db.select(db.customerAdvances).get();
    return [
      for (final t in tresor) 'T:${t.id}:${t.balance}',
      for (final c in creances) 'R:${c.id}:${c.amount}:${c.amountPaid}',
      for (final a in avances)
        if (a.id != sauf) 'A:${a.id}:${a.amount}:${a.amountUsed}',
      'E:${ecritures.length}',
    ].join('|');
  }

  group('enregistrerAvance : refuser avant d’écrire', () {
    setUp(() async {
      await client('c1', 'AMOUSSOU Régis');
      await compte('t1', 'Caisse principale');
    });

    Future<void> refuse(
      String motifAttendu, {
      String clientId = '',
      double montant = 20000,
      String compteId = '',
      String motif = 'Réservation 50 poussins',
      String mode = 'Espèces',
    }) async {
      await expectLater(
        depot.enregistrerAvance(
          clientId: clientId.isEmpty ? uuid('c1') : clientId,
          montant: montant,
          compteId: compteId.isEmpty ? uuid('t1') : compteId,
          motif: motif,
          modePaiement: mode,
        ),
        throwsA(
          isA<SaisieRefusee>().having(
            (e) => e.motif,
            'motif',
            contains(motifAttendu),
          ),
        ),
      );
      expect(
        await db.select(db.customerAdvances).get(),
        isEmpty,
        reason: 'un refus n’écrit rien : $motifAttendu',
      );
    }

    test(
      '⚠️ un montant infini (« 1e999 ») est refusé : il bloquerait la file',
      () async {
        for (final infini in [double.infinity, double.negativeInfinity]) {
          await refuse('supérieur à zéro', montant: infini);
        }
        expect(double.tryParse('1e999'), double.infinity);
      },
    );

    test(
      '⚠️ écrit le FAIT en attente, sans toucher ni caisse ni écriture',
      () async {
        final avant = await empreinteIntouchable();

        final a = await depot.enregistrerAvance(
          clientId: uuid('c1'),
          montant: 20000,
          compteId: uuid('t1'),
          motif: '  Réservation 50 poussins d’un jour  ',
          modePaiement: 'MTN Mobile Money',
          date: DateTime(2026, 10, 9, 14, 30),
        );

        expect(a.id, hasLength(36));
        expect(a.syncStatus, SyncStatus.pending);
        expect(a.customerId, uuid('c1'));
        expect(a.treasuryAccountId, uuid('t1'));
        expect(a.amount, 20000);
        expect(a.amountUsed, 0);
        expect(a.paymentMode, 'mobile_money');
        expect(a.motif, 'Réservation 50 poussins d’un jour');
        expect(a.deviceId, 'poste-test');
        expect(a.advanceDate, DateTime(2026, 10, 9));
        expect(a.isActive, isTrue);

        // Seule la nouvelle avance a bougé : trésorerie, créances, journal intacts.
        expect(
          await empreinteIntouchable(sauf: a.id),
          avant,
          reason: 'le poste n’écrit que le fait',
        );
        expect(
          (await db.select(db.treasuryAccounts).getSingle()).balance,
          100000,
        );
      },
    );

    test(
      '⚠️ le mode de paiement suit le contrat (Moov et MTN = mobile_money)',
      () async {
        for (final (libelle, code) in [
          ('Espèces', 'especes'),
          ('MTN Mobile Money', 'mobile_money'),
          ('Moov Money', 'mobile_money'),
          ('Chèque', 'cheque'),
        ]) {
          final a = await depot.enregistrerAvance(
            clientId: uuid('c1'),
            montant: 1000,
            compteId: uuid('t1'),
            motif: 'm',
            modePaiement: libelle,
          );
          expect(a.paymentMode, code, reason: libelle);
        }
      },
    );

    test('montant nul, négatif ou inférieur à 1 FCFA : refusé', () async {
      await refuse('supérieur à zéro', montant: 0);
      await refuse('supérieur à zéro', montant: -500);
      await refuse('supérieur à zéro', montant: double.nan);
      await refuse("d'au moins 1 FCFA", montant: 0.5);
    });

    test('client inconnu ou archivé : refusé', () async {
      await refuse('Client inconnu', clientId: uuid('zz'));
      await client('c2', 'Archivé', actif: false);
      await refuse('Client inconnu', clientId: uuid('c2'));
    });

    test('compte de trésorerie inconnu : refusé', () async {
      await refuse('Compte de trésorerie inconnu', compteId: uuid('zz'));
    });

    test(
      '⚠️ motif vide : refusé (la maquette le marque obligatoire)',
      () async {
        await refuse('motif', motif: '');
        await refuse('motif', motif: '   ');
        await refuse('255 caractères', motif: 'x' * 256);
      },
    );

    test('mode de paiement inconnu : refusé', () async {
      await refuse('Mode de paiement inconnu', mode: 'Troc');
    });
  });

  group('imputerAvance : plafonds nets des imputations en attente', () {
    setUp(() async {
      await client('c1', 'AMOUSSOU Régis');
      await client('c2', 'TOSSOU Marcel');
      // Avance de 20 000, créance de 50 000 dont 10 000 déjà réglés (solde 40 000).
      await avance('a1', 'c1', montant: 20000);
      await creance('r1', 'c1', montant: 50000, regle: 10000);
    });

    Future<void> refuse(
      String motifAttendu, {
      required double montant,
      String avanceCle = 'a1',
      String creanceCle = 'r1',
    }) async {
      final avant = await db.select(db.advanceImputations).get();
      await expectLater(
        depot.imputerAvance(
          avanceId: uuid(avanceCle),
          creanceId: uuid(creanceCle),
          montant: montant,
        ),
        throwsA(
          isA<SaisieRefusee>().having(
            (e) => e.motif,
            'motif',
            contains(motifAttendu),
          ),
        ),
      );
      expect(
        (await db.select(db.advanceImputations).get()).length,
        avant.length,
        reason: 'un refus n’écrit rien : $motifAttendu',
      );
    }

    test('⚠️ un montant infini (« 1e999 ») est refusé, jamais écrit', () async {
      for (final infini in [double.infinity, double.negativeInfinity]) {
        await refuse('supérieur à zéro', montant: infini);
      }
      // Le piège réel : la saisie « 1e999 » donne Infinity et non une erreur d'analyse.
      expect(double.tryParse('1e999'), double.infinity);
    });

    test(
      '⚠️ écrit en attente et ne touche NI amount_used NI amount_paid',
      () async {
        final avant = await empreinteIntouchable();

        final i = await depot.imputerAvance(
          avanceId: uuid('a1'),
          creanceId: uuid('r1'),
          montant: 12000,
          date: DateTime(2026, 10, 9, 8),
        );

        expect(i.syncStatus, SyncStatus.pending);
        expect(i.customerAdvanceId, uuid('a1'));
        expect(i.receivableId, uuid('r1'));
        expect(i.saleId, isNull);
        expect(i.amount, 12000);
        expect(i.deviceId, 'poste-test');
        expect(i.imputationDate, DateTime(2026, 10, 9));
        expect(await empreinteIntouchable(), avant);
      },
    );

    test('montant nul, négatif ou inférieur à 1 : refusé', () async {
      await refuse('supérieur à zéro', montant: 0);
      await refuse('supérieur à zéro', montant: -1);
      await refuse("d'au moins 1 FCFA", montant: 0.4);
    });

    test(
      '⚠️ au-delà du reste de l’avance, imputations en attente déduites',
      () async {
        await depot.imputerAvance(
          avanceId: uuid('a1'),
          creanceId: uuid('r1'),
          montant: 12000,
        );

        // Reste net = 20 000 − 0 − 12 000 = 8 000.
        await refuse("reste de l'avance (8000 F)", montant: 8001);
        await depot.imputerAvance(
          avanceId: uuid('a1'),
          creanceId: uuid('r1'),
          montant: 8000,
        );

        // Avance épuisée par les deux imputations en attente.
        await refuse('entièrement imputée', montant: 1);
      },
    );

    test(
      '⚠️ au-delà du solde de la créance, imputations en attente déduites',
      () async {
        // Avance de 100 000 : seul le solde de la créance plafonne.
        await avance('a2', 'c1', montant: 100000);
        await refuse(
          'solde de la créance (40000 F)',
          montant: 40001,
          avanceCle: 'a2',
        );
        await depot.imputerAvance(
          avanceId: uuid('a2'),
          creanceId: uuid('r1'),
          montant: 25000,
        );

        // Solde net = 50 000 − 10 000 − 25 000 = 15 000.
        await refuse(
          'solde de la créance (15000 F)',
          montant: 15001,
          avanceCle: 'a2',
        );
        await depot.imputerAvance(
          avanceId: uuid('a2'),
          creanceId: uuid('r1'),
          montant: 15000,
        );
        await refuse('déjà soldée', montant: 1, avanceCle: 'a2');
      },
    );

    test('créance d’un autre client : refusée', () async {
      await creance('r2', 'c2', montant: 30000);
      await refuse(
        'n\'appartient pas au client',
        montant: 5000,
        creanceCle: 'r2',
      );
    });

    test('avance ou créance inconnue, avance archivée : refusé', () async {
      await refuse('Avance introuvable', montant: 100, avanceCle: 'zz');
      await refuse('Créance introuvable', montant: 100, creanceCle: 'zz');
      await avance('a3', 'c1', montant: 5000, active: false);
      await refuse('introuvable ou archivée', montant: 100, avanceCle: 'a3');
    });

    test(
      '⚠️ avance refusée par le serveur (conflict) : non imputable',
      () async {
        await avance('a4', 'c1', montant: 5000, statut: SyncStatus.conflict);
        await refuse('refusée par le serveur', montant: 100, avanceCle: 'a4');
      },
    );

    test(
      'une avance encore en attente PEUT être imputée (même envoi)',
      () async {
        await avance('a5', 'c1', montant: 5000, statut: SyncStatus.pending);
        final i = await depot.imputerAvance(
          avanceId: uuid('a5'),
          creanceId: uuid('r1'),
          montant: 5000,
        );
        expect(i.syncStatus, SyncStatus.pending);
      },
    );

    test('⚠️⚠️ soldes affichés NETS, recalculés indépendamment', () async {
      await depot.imputerAvance(
        avanceId: uuid('a1'),
        creanceId: uuid('r1'),
        montant: 7000,
      );
      await depot.imputerAvance(
        avanceId: uuid('a1'),
        creanceId: uuid('r1'),
        montant: 5000,
      );
      // Acquittée : déjà dans les soldes servis, ne se déduit plus.
      await db
          .into(db.advanceImputations)
          .insert(
            AdvanceImputationsCompanion.insert(
              id: uuid('i-ack'),
              deviceId: 'poste-test',
              syncStatus: const Value(SyncStatus.synced),
              updatedAt: DateTime.now(),
              customerAdvanceId: uuid('a1'),
              receivableId: Value(uuid('r1')),
              amount: 999,
              imputationDate: DateTime(2026, 10, 9),
            ),
          );
      // Refusée : n'a rien appliqué.
      await db
          .into(db.advanceImputations)
          .insert(
            AdvanceImputationsCompanion.insert(
              id: uuid('i-conf'),
              deviceId: 'poste-test',
              syncStatus: const Value(SyncStatus.conflict),
              updatedAt: DateTime.now(),
              customerAdvanceId: uuid('a1'),
              receivableId: Value(uuid('r1')),
              amount: 888,
              imputationDate: DateTime(2026, 10, 9),
            ),
          );

      final d = await depot.charger();

      // Recalcul : SQL brut + lecture des colonnes servies.
      final enAttenteAvance = await sommeEnAttente(
        'customer_advance_id',
        uuid('a1'),
      );
      final enAttenteCreance = await sommeEnAttente(
        'receivable_id',
        uuid('r1'),
      );
      expect(enAttenteAvance, 12000);
      expect(enAttenteCreance, 12000);

      final a = d.avances.single;
      expect(a.soldeRestant, 20000 - 0 - enAttenteAvance);
      expect(a.soldeRestant, 8000);
      expect(a.imputeEnAttente, 12000);
      expect(a.imputationEnAttente, isTrue);

      final c = d.creances.single;
      expect(c.resteDu, 50000 - 10000 - enAttenteCreance);
      expect(c.resteDu, 28000);

      // Les KPI suivent le net (une avance entamée par l'attente compte pour le reste).
      expect(d.avancesEnCours, 8000);
      expect(d.encoursGlobal, 28000);
    });

    test('un solde net ne descend jamais sous zéro', () async {
      // Cas d'un tirage plus récent que la saisie : amount_used a déjà absorbé 20 000.
      await depot.imputerAvance(
        avanceId: uuid('a1'),
        creanceId: uuid('r1'),
        montant: 5000,
      );
      await (db.update(db.customerAdvances)
            ..where((a) => a.id.equals(uuid('a1'))))
          .write(const CustomerAdvancesCompanion(amountUsed: Value(20000)));

      final d = await depot.charger();
      expect(d.avances.single.soldeRestant, 0);
      expect(d.avances.single.soldee, isTrue);
    });
  });

  group('synchronisation', () {
    test(
      '⚠️ avance et imputation partent ensemble, sans solde, device_id à la racine',
      () async {
        await client('c1', 'AMOUSSOU Régis');
        await compte('t1', 'Caisse');
        await creance('r1', 'c1', montant: 50000);
        final a = await depot.enregistrerAvance(
          clientId: uuid('c1'),
          montant: 20000,
          compteId: uuid('t1'),
          motif: 'Poussins',
          modePaiement: 'Chèque',
          date: DateTime(2026, 10, 9),
        );
        final i = await depot.imputerAvance(
          avanceId: a.id,
          creanceId: uuid('r1'),
          montant: 15000,
          date: DateTime(2026, 10, 9),
        );
        final serveur = _ServeurSync(
          reponsePush: {
            'customer_advances': {
              'accepted': [a.id],
              'rejected': [],
            },
            'advance_imputations': {
              'accepted': [i.id],
              'rejected': [],
            },
          },
        );

        await moteur(serveur).synchroniser();

        final envoi = serveur.envois.single;
        expect(envoi['device_id'], 'poste-test');
        expect((envoi['customer_advances'] as List).single, {
          'id': a.id,
          'customer_id': uuid('c1'),
          'treasury_account_id': uuid('t1'),
          'amount': 20000.0,
          'advance_date': '2026-10-09',
          'payment_mode': 'cheque',
          'motif': 'Poussins',
          'is_active': true,
        });
        expect((envoi['advance_imputations'] as List).single, {
          'id': i.id,
          'customer_advance_id': a.id,
          'receivable_id': uuid('r1'),
          'amount': 15000.0,
          'imputation_date': '2026-10-09',
        });
        expect(
          (await db.select(db.customerAdvances).getSingle()).syncStatus,
          SyncStatus.synced,
        );
        expect(
          (await db.select(db.advanceImputations).getSingle()).syncStatus,
          SyncStatus.synced,
        );
      },
    );

    test('⚠️ une imputation par sale_id part sans receivable_id', () async {
      await client('c1', 'A');
      await avance('a1', 'c1', montant: 5000);
      await db
          .into(db.advanceImputations)
          .insert(
            AdvanceImputationsCompanion.insert(
              id: uuid('i1'),
              deviceId: 'poste-test',
              updatedAt: DateTime.now(),
              customerAdvanceId: uuid('a1'),
              saleId: Value(uuid('v1')),
              amount: 3000,
              imputationDate: DateTime(2026, 10, 9),
            ),
          );
      final serveur = _ServeurSync();

      await moteur(serveur).synchroniser();

      final envoye =
          (serveur.envois.single['advance_imputations'] as List).single as Map;
      expect(envoye.containsKey('receivable_id'), isFalse);
      expect(envoye['sale_id'], uuid('v1'));
    });

    test(
      '⚠️ rien n’est marqué synced sans accusé : un envoi sans réponse reste en attente',
      () async {
        await client('c1', 'A');
        await compte('t1', 'Caisse');
        await depot.enregistrerAvance(
          clientId: uuid('c1'),
          montant: 1000,
          compteId: uuid('t1'),
          motif: 'm',
        );
        final serveur = _ServeurSync(); // répond {} : aucun accusé

        await moteur(serveur).synchroniser();

        expect(
          (await db.select(db.customerAdvances).getSingle()).syncStatus,
          SyncStatus.pending,
        );
        // …et repart au passage suivant (le serveur le reçoit comme un renvoi).
        await moteur(serveur).synchroniser();
        expect(serveur.envois, hasLength(2));
        expect(serveur.envois.last['customer_advances'], hasLength(1));
      },
    );

    test(
      '⚠️ un acquittement ne repart pas : second passage, plus rien à envoyer',
      () async {
        await client('c1', 'A');
        await compte('t1', 'Caisse');
        final a = await depot.enregistrerAvance(
          clientId: uuid('c1'),
          montant: 1000,
          compteId: uuid('t1'),
          motif: 'm',
        );
        final serveur = _ServeurSync(
          reponsePush: {
            'customer_advances': {
              'accepted': [a.id],
              'rejected': [],
            },
          },
        );
        final m = moteur(serveur);

        await m.synchroniser();
        await m.synchroniser();

        expect(serveur.envois, hasLength(1), reason: 'pas de second envoi');
      },
    );

    test(
      '⚠️ refus du serveur : conflict, motif conservé mot pour mot, rien n’est perdu',
      () async {
        await client('c1', 'AMOUSSOU Régis');
        await compte('t1', 'Caisse');
        final a = await depot.enregistrerAvance(
          clientId: uuid('c1'),
          montant: 1000,
          compteId: uuid('t1'),
          motif: 'm',
        );
        const motif =
            "Écriture impossible : le compte 419 (avances et acomptes reçus) est absent du plan comptable.";
        final serveur = _ServeurSync(
          reponsePush: {
            'customer_advances': {
              'accepted': [],
              'rejected': [
                {'id': a.id, 'reason': motif},
              ],
            },
          },
        );
        final m = moteur(serveur);

        final sortie = await m.synchroniser();

        expect(sortie.rejete, 1);
        expect(sortie.motifs, contains(motif));
        final ligne = await db.select(db.customerAdvances).getSingle();
        expect(ligne.syncStatus, SyncStatus.conflict);
        expect(ligne.amount, 1000, reason: 'la saisie reste sur le poste');
        expect((await m.conflits()).single.reason, motif);

        // Le motif remonte à l'écran de l'avance.
        final d = await depot.charger();
        expect(d.avances.single.refusee, isTrue);
        expect(d.avances.single.motifRefus, motif);

        // Un conflit ne repart pas tout seul.
        await m.synchroniser();
        expect(serveur.envois, hasLength(1));
      },
    );

    test(
      '⚠️ un conflit d’imputation se relance : elle repasse en attente',
      () async {
        await client('c1', 'A');
        await avance('a1', 'c1', montant: 5000);
        await creance('r1', 'c1', montant: 9000);
        final i = await depot.imputerAvance(
          avanceId: uuid('a1'),
          creanceId: uuid('r1'),
          montant: 4000,
        );
        final serveur = _ServeurSync(
          reponsePush: {
            'advance_imputations': {
              'accepted': [],
              'rejected': [
                {'id': i.id, 'reason': 'Cette créance est déjà soldée.'},
              ],
            },
          },
        );
        final m = moteur(serveur);
        await m.synchroniser();

        expect(
          (await db.select(db.advanceImputations).getSingle()).syncStatus,
          SyncStatus.conflict,
        );
        // Une imputation refusée n'a rien appliqué : elle ne se déduit pas.
        expect((await depot.charger()).avances.single.soldeRestant, 5000);

        await m.relancer((await m.conflits()).single);

        expect(
          (await db.select(db.advanceImputations).getSingle()).syncStatus,
          SyncStatus.pending,
        );
        expect(await m.conflits(), isEmpty);
        expect((await depot.charger()).avances.single.soldeRestant, 1000);
      },
    );

    test('⚠️ une avance refusée se relance aussi', () async {
      await client('c1', 'A');
      await compte('t1', 'Caisse');
      final a = await depot.enregistrerAvance(
        clientId: uuid('c1'),
        montant: 1000,
        compteId: uuid('t1'),
        motif: 'm',
      );
      final serveur = _ServeurSync(
        reponsePush: {
          'customer_advances': {
            'accepted': [],
            'rejected': [
              {'id': a.id, 'reason': 'Refus.'},
            ],
          },
        },
      );
      final m = moteur(serveur);
      await m.synchroniser();

      await m.relancer((await m.conflits()).single);

      expect(
        (await db.select(db.customerAdvances).getSingle()).syncStatus,
        SyncStatus.pending,
      );
    });

    test(
      '⚠️⚠️ tirage de confirmation : le solde servi absorbe l’imputation acquittée',
      () async {
        await client('c1', 'A');
        await avance('a1', 'c1', montant: 20000);
        await creance('r1', 'c1', montant: 50000);
        final i = await depot.imputerAvance(
          avanceId: uuid('a1'),
          creanceId: uuid('r1'),
          montant: 8000,
        );

        Map<String, dynamic> serveurAvant() => {
          'customer_advances': [
            {
              'id': uuid('a1'),
              'customer_id': uuid('c1'),
              'amount': 20000,
              'amount_used': 0,
              'is_active': true,
            },
          ],
          'receivables': [
            {
              'id': uuid('r1'),
              'customer_id': uuid('c1'),
              'amount': 50000,
              'amount_paid': 0,
            },
          ],
        };
        Map<String, dynamic> serveurApres() => {
          'customer_advances': [
            {
              'id': uuid('a1'),
              'customer_id': uuid('c1'),
              'amount': 20000,
              'amount_used': 8000,
              'is_active': true,
            },
          ],
          'receivables': [
            {
              'id': uuid('r1'),
              'customer_id': uuid('c1'),
              'amount': 50000,
              'amount_paid': 8000,
            },
          ],
        };
        final serveur = _ServeurSync(
          tirages: [serveurAvant(), serveurApres()],
          reponsePush: {
            'advance_imputations': {
              'accepted': [i.id],
              'rejected': [],
            },
          },
        );

        await moteur(serveur).synchroniser();

        expect(serveur.nbTirages, 2, reason: 'un tirage de confirmation');
        final d = await depot.charger();
        // Ni 20 000 (solde d'avant l'acquittement), ni 4 000 (déduit deux fois).
        expect(d.avances.single.soldeRestant, 20000 - 8000);
        expect(d.avances.single.imputeEnAttente, 0);
        expect(d.creances.single.resteDu, 50000 - 8000);
      },
    );

    test('pas d’avance ni d’imputation acquittée : un seul tirage', () async {
      await client('c1', 'A');
      final serveur = _ServeurSync();

      await moteur(serveur).synchroniser();

      expect(serveur.nbTirages, 1);
    });

    test(
      'un échec réseau du tirage de confirmation n’annule pas l’acquittement',
      () async {
        await client('c1', 'A');
        await compte('t1', 'Caisse');
        final a = await depot.enregistrerAvance(
          clientId: uuid('c1'),
          montant: 1000,
          compteId: uuid('t1'),
          motif: 'm',
        );
        var appels = 0;
        final dio = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                if (options.path.contains('push')) {
                  handler.resolve(
                    Response(
                      requestOptions: options,
                      statusCode: 200,
                      data: {
                        'customer_advances': {
                          'accepted': [a.id],
                          'rejected': [],
                        },
                      },
                    ),
                  );
                  return;
                }
                appels++;
                if (appels == 2) {
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      type: DioExceptionType.connectionError,
                    ),
                  );
                  return;
                }
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'server_time': '2026-10-09T12:00:00.000Z'},
                  ),
                );
              },
            ),
          );

        await SyncEngine(
          database: db,
          client: dio,
          deviceId: 'poste-test',
          connectivity: _ConnectiviteFeinte(),
        ).synchroniser();

        expect(
          (await db.select(db.customerAdvances).getSingle()).syncStatus,
          SyncStatus.synced,
        );
      },
    );
  });

  group('tirage : fusion par identifiant', () {
    Map<String, dynamic> ligneAvance(
      String cle, {
      double utilise = 0,
      double montant = 10000,
    }) => {
      'id': uuid(cle),
      'customer_id': uuid('c1'),
      'amount': montant,
      'amount_used': utilise,
      'advance_date': '2026-10-01',
      'is_active': true,
      'treasury_account_id': uuid('t1'),
      'payment_mode': 'especes',
      'motif': 'Poussins',
      'device_id': 'autre-poste',
    };

    test(
      '⚠️⚠️ deux tirages : l’avance non servie est supprimée, les autres fusionnées',
      () async {
        final serveur = _ServeurSync(
          tirages: [
            {
              'customer_advances': [ligneAvance('a1'), ligneAvance('a2')],
            },
            {
              // a2 archivée côté serveur : plus servie. a1 a été entamée.
              'customer_advances': [ligneAvance('a1', utilise: 4000)],
            },
          ],
        );
        final m = moteur(serveur);

        await m.synchroniser();
        expect(
          (await db.select(db.customerAdvances).get()).map((a) => a.id),
          unorderedEquals([uuid('a1'), uuid('a2')]),
        );

        await m.synchroniser();
        final restantes = await db.select(db.customerAdvances).get();
        expect(restantes.map((a) => a.id), [uuid('a1')]);
        expect(restantes.single.amountUsed, 4000);
        // Les colonnes du contrat 15.19 descendent.
        expect(restantes.single.treasuryAccountId, uuid('t1'));
        expect(restantes.single.paymentMode, 'especes');
        expect(restantes.single.motif, 'Poussins');
        expect(restantes.single.deviceId, 'autre-poste');
        expect(restantes.single.syncStatus, SyncStatus.synced);
      },
    );

    test(
      '⚠️⚠️ une avance pending ou conflict n’est NI écrasée NI effacée',
      () async {
        await client('c1', 'A');
        await avance('p1', 'c1', montant: 7000, statut: SyncStatus.pending);
        await avance('k1', 'c1', montant: 3000, statut: SyncStatus.conflict);
        await avance(
          's1',
          'c1',
          montant: 500,
        ); // synced, plus servie : supprimée
        final serveur = _ServeurSync(
          tirages: [
            {
              'customer_advances': [
                // Le serveur ressert l'id de la saisie avec d'autres valeurs.
                ligneAvance('p1', montant: 1),
                ligneAvance('n1'),
              ],
            },
          ],
        );

        await moteur(serveur).synchroniser();

        final parId = {
          for (final a in await db.select(db.customerAdvances).get()) a.id: a,
        };
        expect(
          parId.keys,
          unorderedEquals([uuid('p1'), uuid('k1'), uuid('n1')]),
        );
        expect(
          parId[uuid('p1')]!.amount,
          7000,
          reason: 'saisie du poste intacte',
        );
        expect(parId[uuid('p1')]!.syncStatus, SyncStatus.pending);
        expect(parId[uuid('k1')]!.syncStatus, SyncStatus.conflict);
      },
    );

    test(
      'une liste vide supprime les avances synchronisées, jamais les saisies',
      () async {
        await client('c1', 'A');
        await avance('s1', 'c1', montant: 500);
        await avance('p1', 'c1', montant: 700, statut: SyncStatus.pending);
        final serveur = _ServeurSync(
          tirages: [
            {'customer_advances': <dynamic>[]},
          ],
        );

        await moteur(serveur).synchroniser();

        expect((await db.select(db.customerAdvances).get()).map((a) => a.id), [
          uuid('p1'),
        ]);
      },
    );

    test('un bloc absent ne touche à rien', () async {
      await client('c1', 'A');
      await avance('s1', 'c1', montant: 500);
      final serveur = _ServeurSync(tirages: [{}]);

      await moteur(serveur).synchroniser();

      expect(await db.select(db.customerAdvances).get(), hasLength(1));
    });

    test(
      '⚠️⚠️ créances : fusionnées, puis supprimées quand le serveur ne les sert plus',
      () async {
        Map<String, dynamic> ligne(String cle, double paye) => {
          'id': uuid(cle),
          'customer_id': uuid('c1'),
          'amount': 10000,
          'amount_paid': paye,
          'due_date': '2026-11-08',
        };
        final serveur = _ServeurSync(
          tirages: [
            {
              'receivables': [ligne('r1', 0), ligne('r2', 0)],
            },
            {
              // r1 soldée (servie car modifiée), r2 plus servie (soldée plus tôt).
              'receivables': [ligne('r1', 10000)],
            },
            {'receivables': <dynamic>[]},
          ],
        );
        final m = moteur(serveur);

        await m.synchroniser();
        expect(await db.select(db.receivables).get(), hasLength(2));

        await m.synchroniser();
        final apres = await db.select(db.receivables).get();
        expect(apres.map((c) => c.id), [uuid('r1')]);
        expect(apres.single.amountPaid, 10000);

        await m.synchroniser();
        expect(await db.select(db.receivables).get(), isEmpty);
      },
    );

    test(
      '⚠️ le tirage ne détruit pas une imputation en attente ni sa cible',
      () async {
        await client('c1', 'A');
        await avance('a1', 'c1', montant: 20000);
        await creance('r1', 'c1', montant: 50000);
        await depot.imputerAvance(
          avanceId: uuid('a1'),
          creanceId: uuid('r1'),
          montant: 6000,
        );
        final serveur = _ServeurSync(
          tirages: [
            {
              'customer_advances': [ligneAvance('a1', montant: 20000)],
              'receivables': [
                {
                  'id': uuid('r1'),
                  'customer_id': uuid('c1'),
                  'amount': 50000,
                  'amount_paid': 0,
                },
              ],
            },
          ],
        );

        // Aucune réponse d'accusé : l'imputation reste en attente après l'envoi.
        await moteur(serveur).synchroniser();

        final imp = await db.select(db.advanceImputations).getSingle();
        expect(imp.syncStatus, SyncStatus.pending);
        final d = await depot.charger();
        expect(d.avances.single.soldeRestant, 14000);
        expect(d.creances.single.resteDu, 44000);
      },
    );
  });

  group('écran « Historique Avances »', () {
    final espions = <DocumentOfficiel>[];
    late List<int> avancesAuMomentDuRecu;

    Future<String?> editeurEspion(DocumentOfficiel doc, DateTime _) async {
      espions.add(doc);
      avancesAuMomentDuRecu.add(
        (await db.select(db.customerAdvances).get()).length,
      );
      return null;
    }

    setUp(() {
      espions.clear();
      avancesAuMomentDuRecu = [];
    });

    Future<void> afficher(WidgetTester tester, {bool editeur = true}) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: ClientsCreancesScreen(
            depot: depot,
            imprimer: editeur ? editeurEspion : null,
            maintenant: () => DateTime(2026, 10, 9, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('onglet-clients-Historique Avances')),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choisir(WidgetTester tester, String cle, String texte) async {
      await tester.tap(find.byKey(Key(cle)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(texte).last);
      await tester.pumpAndSettle();
    }

    Future<void> garnir() async {
      await client('c1', 'AMOUSSOU Régis');
      await client('c2', 'TOSSOU Marcel');
      await compte('t1', 'Caisse principale');
    }

    testWidgets(
      '⚠️ « Nouvelle Avance » : champs obligatoires signalés, rien d’écrit',
      (tester) async {
        await garnir();
        await afficher(tester);

        await tester.tap(find.byKey(const Key('nouvelle-avance')));
        await tester.pumpAndSettle();
        expect(find.text('Nouvel Acompte'), findsOneWidget);
        for (final libelle in [
          'Client *',
          'Motif / Commande réservée *',
          "Montant de l'Acompte (FCFA) *",
          'Mode de Paiement',
          'Compte de Trésorerie *',
          'Enregistrer et Délivrer le Reçu',
        ]) {
          expect(find.text(libelle), findsOneWidget, reason: libelle);
        }

        await tester.tap(find.byKey(const Key('acompte-enregistrer')));
        await tester.pumpAndSettle();

        expect(find.text('Ce champ est obligatoire.'), findsNWidgets(4));
        expect(await db.select(db.customerAdvances).get(), isEmpty);
        expect(
          espions,
          isEmpty,
          reason: 'aucun reçu pour une saisie non écrite',
        );
      },
    );

    testWidgets(
      '⚠️⚠️ saisie valide : avance en attente, puis reçu non numéroté APRÈS l’écriture',
      (tester) async {
        await garnir();
        await afficher(tester);

        await tester.tap(find.byKey(const Key('nouvelle-avance')));
        await tester.pumpAndSettle();
        await choisir(tester, 'acompte-client', 'AMOUSSOU Régis');
        await tester.enterText(
          find.byKey(const Key('acompte-motif')),
          "Réservation 50 poussins d'un jour",
        );
        await tester.enterText(
          find.byKey(const Key('acompte-montant')),
          '20000',
        );
        await choisir(tester, 'acompte-mode', 'Moov Money');
        await choisir(tester, 'acompte-compte', 'Caisse principale');
        await tester.tap(find.byKey(const Key('acompte-enregistrer')));
        await tester.pumpAndSettle();

        // Écrite en attente…
        final a = await db.select(db.customerAdvances).getSingle();
        expect(a.syncStatus, SyncStatus.pending);
        expect(a.amount, 20000);
        expect(a.paymentMode, 'mobile_money');
        expect(a.treasuryAccountId, uuid('t1'));
        expect(find.byKey(Key('avance-en-attente-${a.id}')), findsOneWidget);
        expect(find.text('En attente'), findsOneWidget);
        expect(find.text('AMOUSSOU Régis'), findsOneWidget);

        // …et le reçu n'est sorti qu'une fois, APRÈS l'écriture (l'avance existait déjà).
        expect(espions, hasLength(1));
        expect(avancesAuMomentDuRecu, [1]);
        final recu = espions.single;
        expect(recu.titre, "Reçu d'Acompte");
        expect(recu.sousTitre, 'Justificatif de versement — à conserver');
        final cellules = [
          for (final l in recu.lignes)
            if (l is DonneesDocument) l.cellules,
        ];
        expect(
          cellules,
          containsAll([
            ['Client', 'AMOUSSOU Régis'],
            ['Motif / Commande réservée', "Réservation 50 poussins d'un jour"],
            ["Montant de l'acompte", '20 000 FCFA'],
            ['Mode de paiement', 'Moov Money'],
            // F0.83 : la date du reçu est celle du JOUR de la saisie ; elle était écrite en dur
            // (« 09/10/2026 ») et le test est devenu rouge dès le lendemain, sans défaut de code.
            [
              'Date',
              '${HeureBenin.maintenant().day.toString().padLeft(2, '0')}/'
                  '${HeureBenin.maintenant().month.toString().padLeft(2, '0')}/'
                  '${HeureBenin.maintenant().year}',
            ],
          ]),
        );
        // Non numéroté, mention « Reçu du poste », dit que la ferme ne l'a pas encore reçu.
        expect(
          cellules.any(
            (c) => c[0] == 'Numéro' && c[1].contains('non numéroté'),
          ),
          isTrue,
        );
        expect(recu.noteDePied, contains('Reçu du poste'));
        expect(recu.noteDePied, contains('pas encore reçu par la ferme'));
        expect(
          recu.lignes
              .whereType<DonneesDocument>()
              .expand((l) => l.cellules)
              .join(' '),
          isNot(contains(RegExp(r'REC-|N°\s*\d'))),
          reason: 'aucun numéro inventé',
        );
      },
    );

    testWidgets(
      '⚠️ refus du dépôt (montant sous 1 FCFA) : le motif reste dans la modale, rien d’écrit, pas de reçu',
      (tester) async {
        await garnir();
        await afficher(tester);

        await tester.tap(find.byKey(const Key('nouvelle-avance')));
        await tester.pumpAndSettle();
        await choisir(tester, 'acompte-client', 'AMOUSSOU Régis');
        await tester.enterText(
          find.byKey(const Key('acompte-motif')),
          'Poussins',
        );
        await tester.enterText(find.byKey(const Key('acompte-montant')), '0.5');
        await choisir(tester, 'acompte-compte', 'Caisse principale');
        await tester.tap(find.byKey(const Key('acompte-enregistrer')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('acompte-refus')), findsOneWidget);
        expect(find.textContaining("d'au moins 1 FCFA"), findsOneWidget);
        expect(await db.select(db.customerAdvances).get(), isEmpty);
        expect(espions, isEmpty);
      },
    );

    testWidgets('sans éditeur injecté, l’avance est écrite quand même', (
      tester,
    ) async {
      await garnir();
      await afficher(tester, editeur: false);

      await tester.tap(find.byKey(const Key('nouvelle-avance')));
      await tester.pumpAndSettle();
      await choisir(tester, 'acompte-client', 'TOSSOU Marcel');
      await tester.enterText(
        find.byKey(const Key('acompte-motif')),
        'Aliments',
      );
      await tester.enterText(find.byKey(const Key('acompte-montant')), '5000');
      await choisir(tester, 'acompte-compte', 'Caisse principale');
      await tester.tap(find.byKey(const Key('acompte-enregistrer')));
      await tester.pumpAndSettle();

      expect(await db.select(db.customerAdvances).get(), hasLength(1));
    });

    testWidgets(
      '⚠️⚠️ « Imputer » : écrit en attente, solde AFFICHÉ net, serveur intact',
      (tester) async {
        await garnir();
        await avance('a1', 'c1', montant: 20000);
        await creance('r1', 'c1', montant: 50000, regle: 10000);
        await afficher(tester);

        final avant = await empreinteIntouchable();

        await tester.tap(find.byKey(Key('imputer-avance-${uuid('a1')}')));
        await tester.pumpAndSettle();
        expect(find.text('Imputer un Acompte'), findsOneWidget);
        for (final libelle in [
          'Acompte sélectionné',
          "Valeur de l'acompte",
          'Choix Facture de Vente',
          "Valider l'Imputation",
          'Affecter',
        ]) {
          expect(find.text(libelle), findsOneWidget, reason: libelle);
        }
        expect(find.byKey(const Key('imputation-solde')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('imputation-solde'))).data,
          '20 000 FCFA',
        );

        // Sans facture : le message de la maquette.
        await tester.tap(find.byKey(const Key('imputation-valider')));
        await tester.pumpAndSettle();
        expect(
          find.text('Veuillez choisir une facture active.'),
          findsOneWidget,
        );
        expect(await db.select(db.advanceImputations).get(), isEmpty);

        await tester.tap(find.byKey(const Key('imputation-creance')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Solde 40 000 FCFA').last);
        await tester.pumpAndSettle();
        // min(20 000 reste, 40 000 solde) = 20 000.
        expect(
          find.textContaining('Montant imputé : 20 000 FCFA'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('imputation-valider')));
        await tester.pumpAndSettle();

        final imp = await db.select(db.advanceImputations).getSingle();
        expect(imp.syncStatus, SyncStatus.pending);
        expect(imp.amount, 20000);
        expect(imp.receivableId, uuid('r1'));
        expect(await empreinteIntouchable(), avant);

        // Solde net : 20 000 − 0 − 20 000 = 0 → soldée, imputation en attente signalée.
        expect(find.text('Soldée'), findsOneWidget);
        expect(
          find.byKey(Key('avance-imputation-attente-${uuid('a1')}')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(find.byKey(Key('avance-solde-${uuid('a1')}')))
              .data,
          '0',
        );
        expect(
          find.byKey(Key('avance-solde-net-${uuid('a1')}')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '⚠️ « Affecter » change l’acompte choisi ; les créances sont celles du client',
      (tester) async {
        await garnir();
        await avance('a1', 'c1', montant: 20000);
        await avance('a2', 'c2', montant: 9000);
        await creance('r1', 'c1', montant: 50000);
        await creance('r2', 'c2', montant: 7000);
        await afficher(tester);

        await tester.tap(find.byKey(Key('imputer-avance-${uuid('a1')}')));
        await tester.pumpAndSettle();
        expect(find.text('AMOUSSOU Régis'), findsWidgets);

        await tester.tap(find.byKey(Key('affecter-${uuid('a2')}')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const Key('imputation-client'))).data,
          'TOSSOU Marcel',
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('imputation-solde'))).data,
          '9 000 FCFA',
        );

        await tester.tap(find.byKey(const Key('imputation-creance')));
        await tester.pumpAndSettle();
        // Seule la créance de TOSSOU (7 000) est proposée, pas celle de AMOUSSOU.
        expect(find.textContaining('Solde 7 000 FCFA'), findsWidgets);
        expect(find.textContaining('Solde 50 000 FCFA'), findsNothing);
      },
    );

    testWidgets(
      '⚠️ « Modifier », « Imputer » et « Archiver » sur une avance, comme au Blade (VC-4, D4/D5 revues)',
      (tester) async {
        await garnir();
        await avance('a1', 'c1', montant: 20000);
        await afficher(tester);

        expect(find.byTooltip('Modifier'), findsOneWidget);
        expect(find.byTooltip('Archiver'), findsOneWidget);
        expect(find.byTooltip('Imputer'), findsOneWidget);
      },
    );

    testWidgets(
      '⚠️ avance refusée : « Refusée par le serveur » + motif mot pour mot, non imputable',
      (tester) async {
        await garnir();
        await avance('k1', 'c1', montant: 4000, statut: SyncStatus.conflict);
        await db
            .into(db.syncConflicts)
            .insert(
              SyncConflictsCompanion.insert(
                id: 'customer_advances:${uuid('k1')}',
                sourceTable: 'customer_advances',
                recordId: uuid('k1'),
                reason: 'Compte de trésorerie introuvable.',
                detectedAt: DateTime(2026, 10, 9),
              ),
            );
        await afficher(tester);

        expect(find.text('Refusée par le serveur'), findsOneWidget);
        expect(find.text('Compte de trésorerie introuvable.'), findsOneWidget);
        expect(find.byTooltip('Imputer'), findsNothing);
      },
    );

    testWidgets(
      'l’écran dit que les soldes sont nets des imputations en attente',
      (tester) async {
        await afficher(tester);

        expect(find.textContaining('NETS des imputations'), findsOneWidget);
      },
    );

    testWidgets(
      '⚠️ « Exporter » édite la liste (soldes nets, avances en attente signalées)',
      (tester) async {
        await garnir();
        await avance('a1', 'c1', montant: 20000, utilise: 5000);
        await avance('p1', 'c2', montant: 3000, statut: SyncStatus.pending);
        await afficher(tester);

        await tester.tap(find.byKey(const Key('exporter-avances')));
        await tester.pumpAndSettle();

        final doc = espions.single;
        expect(doc.titre, 'Historique des Avances Clients');
        expect(doc.sousTitre, 'Acomptes et réservations de commandes');
        expect(doc.entetes, [
          'Client',
          'Montant Avance',
          'Solde Restant',
          'Date',
          'Statut',
        ]);
        final lignes = doc.lignes.whereType<DonneesDocument>().toList();
        expect(lignes, hasLength(2));
        final parClient = {for (final l in lignes) l.cellules[0]: l.cellules};
        // 20 000 − 5 000 = 15 000 ; la ligne en attente est signalée.
        expect(parClient['AMOUSSOU Régis']![2], '15 000 FCFA');
        expect(parClient['AMOUSSOU Régis']![4], 'En cours');
        expect(
          parClient['TOSSOU Marcel']![4],
          contains('en attente de synchronisation'),
        );
        expect(doc.noteDePied, contains('1 avance(s) saisie(s) sur ce poste'));
      },
    );

    testWidgets('« Exporter » sur une liste vide n’édite rien et le dit', (
      tester,
    ) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('exporter-avances')));
      await tester.pumpAndSettle();

      expect(espions, isEmpty);
      expect(find.text('Aucune avance à exporter.'), findsOneWidget);
    });
  });

  group('documents', () {
    test('le reçu reprend la maquette mot pour mot et se dit « du poste »', () {
      final doc = DocumentsAvances.recu(
        client: 'X',
        motif: 'Y',
        montant: 1234567,
        mode: 'Chèque',
        date: DateTime(2026, 1, 2),
      );

      expect(doc.titre, "Reçu d'Acompte");
      expect(doc.entetes, ['Champ', 'Valeur']);
      expect((doc.lignes[2] as DonneesDocument).cellules, [
        "Montant de l'acompte",
        '1 234 567 FCFA',
      ]);
      expect((doc.lignes[4] as DonneesDocument).cellules, [
        'Date',
        '02/01/2026',
      ]);
      expect(doc.noteDePied, startsWith("Ce reçu fait foi du versement"));
    });
  });
}
