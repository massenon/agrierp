import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/ventes/avoirs_repository.dart';
import 'package:agrierp/features/ventes/historique_ventes_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tickets AV1 / AV2 — LES RETOURS CLIENTS ET L'ANNULATION D'UNE VENTE DANS LA SYNCHRONISATION DU POSTE.
///
/// ⚠️⚠️ CE QUE CES TESTS PROTÈGENT.
///  - L'ENVOI : le poste n'envoie que la DEMANDE (`credit_notes` : vente, produit, quantité, montant, motif, décision, notes,
///    statut, jour du fait) — jamais d'ajustement de stock, jamais de numéro `AV-…`, jamais d'écriture ; l'annulation d'une
///    vente part comme la vente renvoyée au statut `annulee` ; le serveur répond table par table, l'accusé acquitte, le refus
///    passe en `conflict` AVEC son motif et se relance.
///  - LE TIRAGE : `credit_notes` est une table MIXTE (comme `expenses`). Un avoir `synced` est remplacé par la version du
///    serveur (numéro `AV-AAAA-NNN`, statut posé au web) ; ⚠️⚠️ une demande `pending` / `conflict` du poste n'est JAMAIS
///    écrasée ; l'absorbeur est STRICT (vente ou produit inconnu, montant négatif, statut illisible, identifiant servi deux
///    fois : le lot est refusé, rien n'est écrit, le curseur n'avance pas). Les ventes servies portent leur remise.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Serveur feint : sert [tirage], garde chaque corps d'envoi dans [envois], accepte tout sauf les [refus] (id → motif).
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-21T09:00:00Z'};
  final Map<String, String> refus = {};
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
                  'accepted': [
                    for (final e in value)
                      if (e is Map && e['id'] is String && !refus.containsKey(e['id'])) e['id'],
                  ],
                  'rejected': [
                    for (final e in value)
                      if (e is Map && refus.containsKey(e['id'])) {'id': e['id'], 'reason': refus[e['id']]},
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

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late AvoirsRepository avoirs;
  late HistoriqueVentesRepository historique;

  const oeufs = 'aaaaaaaa-0000-4000-8000-000000000001';
  const client = 'cccccccc-0000-4000-8000-000000000001';
  const vente1 = 'bbbbbbbb-1111-4000-8000-000000000001';
  final maintenant = DateTime(2026, 10, 21, 10, 30, 5);

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime.utc(2026, 10, 21, 9, 30, 5),
    );
    avoirs = AvoirsRepository(database: db, identifiantPoste: 'poste-test', horloge: () => maintenant);
    historique = HistoriqueVentesRepository(database: db, horloge: () => maintenant);

    await db.into(db.products).insert(
      ProductsCompanion.insert(id: oeufs, sku: 'OEUF', name: "Plaquette d'œufs", unit: 'plaquette', pricingMode: 'fourchette'),
    );
    await db.into(db.customers).insert(CustomersCompanion.insert(id: client, name: 'GBAGUIDI Solange'));
    await db.into(db.fiscalYears).insert(
      FiscalYearsCompanion.insert(
        id: uuid('exercice-2026'),
        year: 2026,
        startDate: Value(DateTime(2026)),
        endDate: Value(DateTime(2026, 12, 31)),
        status: const Value('ouvert'),
      ),
    );
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: vente1,
        deviceId: 'serveur',
        syncStatus: const Value(SyncStatus.synced),
        updatedAt: DateTime(2026, 10, 20),
        customerId: const Value(client),
        paymentMode: 'especes',
        subtotal: const Value(59000),
        total: 59000,
        soldAt: DateTime(2026, 10, 20, 15),
      ),
    );
    await db.into(db.saleLines).insert(
      SaleLinesCompanion.insert(
        id: uuid('ligne-1'),
        saleId: vente1,
        productId: oeufs,
        qty: 10,
        unitPrice: 5900,
        manualTotalAmount: 59000,
      ),
    );
  });

  tearDown(() async => db.close());

  Map<String, dynamic> avoirJson(
    String id, {
    String vente = vente1,
    Object? montant = 11800,
    Object? statut = 'en_attente',
    Object? numero = 'AV-2026-007',
    Object? quantite = 2,
    Object? decision = 'reintegre',
    String creation = '2026-10-21 09:30:00',
  }) => {
    'id': id,
    'credit_note_number': numero,
    'sale_id': vente,
    'product_id': oeufs,
    'qty': quantite,
    'amount': montant,
    'reason': 'Plaquette détériorée',
    'decision': decision,
    'inspection_notes': null,
    'status': statut,
    'created_at': creation,
  };

  Future<List<AvoirClient>> lus() async =>
      (await db.select(db.creditNotes).get())..sort((a, b) => a.id.compareTo(b.id));

  group('ENVOI de la demande', () {
    test('⚠️⚠️ une demande de retour part avec ses champs, SANS numéro, SANS ajustement de stock ni écriture', () async {
      final r = await avoirs.enregistrer(
        venteId: vente1,
        produitId: oeufs,
        quantite: 2,
        montant: 11800,
        motif: 'Plaquette détériorée',
        decision: 'reintegre',
        notes: 'Contrôle visuel effectué, RAS',
      );

      await moteur.synchroniser();

      final corps = serveur.envois.single;
      expect(corps['stock_adjustments'], isEmpty, reason: 'le serveur réintègre le stock, le poste ne l\'ajuste pas');
      expect(corps.keys, isNot(contains('accounting_entries')));
      final demande = (corps['credit_notes'] as List).single as Map;
      expect(demande, {
        'id': r.avoir!.id,
        'sale_id': vente1,
        'product_id': oeufs,
        'qty': 2.0,
        'amount': 11800.0,
        'reason': 'Plaquette détériorée',
        'decision': 'reintegre',
        'inspection_notes': 'Contrôle visuel effectué, RAS',
        'status': 'en_attente',
        // Le JOUR du fait, heure murale du Bénin, SANS conversion UTC (comme `sold_at`).
        'credit_date': '2026-10-21 10:30:05',
        'device_id': 'poste-test',
      });
      expect(demande.containsKey('credit_note_number'), isFalse, reason: 'AV-AAAA-NNN est attribué par le serveur seul');
    });

    test('l accusé acquitte la demande (synced) ; le numéro viendra au tirage', () async {
      final r = await avoirs.enregistrer(
        venteId: vente1, produitId: oeufs, quantite: 2, montant: 11800, motif: 'Détériorée', decision: 'reintegre',
      );

      await moteur.synchroniser();

      final a = (await lus()).single;
      expect(a.id, r.avoir!.id);
      expect(a.syncStatus, SyncStatus.synced);
      expect(a.creditNoteNumber, isNull);
      expect((await db.select(db.syncConflicts).get()), isEmpty);
    });

    test('⚠️⚠️ le refus du serveur passe la demande en conflict AVEC son motif, et « Relancer » la remet en file', () async {
      final r = await avoirs.enregistrer(
        venteId: vente1, produitId: oeufs, quantite: 2, montant: 11800, motif: 'Détériorée', decision: 'reintegre',
      );
      const motif = "Retour refusé : L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 21/10/2026.";
      serveur.refus[r.avoir!.id] = motif;

      await moteur.synchroniser();

      expect((await lus()).single.syncStatus, SyncStatus.conflict);
      final conflit = (await db.select(db.syncConflicts).get()).single;
      expect(conflit.id, 'credit_notes:${r.avoir!.id}');
      expect(conflit.reason, contains(motif));
      expect((await avoirs.charger()).lignes.single.motifRefus, contains(motif));

      // Un refus ne repart pas tout seul : un second envoi ne contient plus la demande.
      serveur.envois.clear();
      await moteur.synchroniser();
      expect(serveur.envois.every((e) => !e.containsKey('credit_notes') || (e['credit_notes'] as List).isEmpty), isTrue);

      await moteur.relancer(conflit);
      expect((await lus()).single.syncStatus, SyncStatus.pending, reason: '« Relancer » remet la demande en file');
      expect(await db.select(db.syncConflicts).get(), isEmpty);

      serveur.refus.clear();
      await moteur.synchroniser();
      expect((await lus()).single.syncStatus, SyncStatus.synced, reason: 'relancée puis acquittée');
    });

    test('« Marquer comme traité » repart : statut traite, même identifiant', () async {
      await db.into(db.creditNotes).insert(
        CreditNotesCompanion.insert(
          id: uuid('avoir-traite'),
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: DateTime(2026, 10, 21),
          saleId: vente1,
          productId: oeufs,
          creditNoteNumber: const Value('AV-2026-007'),
          qty: const Value(2),
          amount: 11800,
          createdAt: DateTime(2026, 10, 21, 9),
        ),
      );
      await avoirs.marquerTraite(uuid('avoir-traite'));

      await moteur.synchroniser();

      final demande = ((serveur.envois.single['credit_notes']) as List).single as Map;
      expect(demande['id'], uuid('avoir-traite'));
      expect(demande['status'], 'traite');
      expect((await lus()).single.syncStatus, SyncStatus.synced);
    });

    test('⚠️⚠️ l annulation d une vente part comme la vente renvoyée au statut annulee, avec ses lignes', () async {
      expect(await historique.annuler(vente1), isTrue);
      final vente = await (db.select(db.sales)..where((v) => v.id.equals(vente1))).getSingle();
      expect(vente.status, 'annulee');
      expect(vente.syncStatus, SyncStatus.pending);

      await moteur.synchroniser();

      final envoyee = ((serveur.envois.single['sales']) as List).single as Map;
      expect(envoyee['id'], vente1);
      expect(envoyee['status'], 'annulee');
      expect((envoyee['lines'] as List), hasLength(1));
      expect(serveur.envois.single['stock_adjustments'], isEmpty, reason: 'le serveur réintègre le stock');
      expect((await (db.select(db.sales)..where((v) => v.id.equals(vente1))).getSingle()).syncStatus, SyncStatus.synced);
      // Le stock LOCAL n'a pas bougé : il se met à jour au tirage.
      expect((await (db.select(db.products)..where((p) => p.id.equals(oeufs))).getSingle()).stockQty, 0);
    });

    test('une vente déjà annulée n est pas annulée une seconde fois (le web ne fait rien non plus)', () async {
      await historique.annuler(vente1);

      expect(await historique.annuler(vente1), isFalse);
    });
  });

  group('TIRAGE : absorbeur de `credit_notes`', () {
    test('les avoirs servis sont absorbés (numéro, statut, jour du fait), marqués « serveur » et acquittés', () async {
      serveur.tirage = {
        'server_time': '2026-10-21T09:00:00Z',
        'credit_notes': [
          avoirJson(uuid('a1')),
          avoirJson(uuid('a2'), numero: 'AV-2026-008', statut: 'traite', quantite: null, decision: null, creation: '2026-10-19 08:00:00'),
        ],
      };

      await moteur.synchroniser();

      final l = await lus();
      expect(l.map((a) => a.id), [uuid('a1'), uuid('a2')]);
      expect(l.first.deviceId, 'serveur');
      expect(l.first.syncStatus, SyncStatus.synced);
      expect(l.first.creditNoteNumber, 'AV-2026-007');
      expect(l.first.qty, 2);
      expect(l.first.amount, 11800);
      expect(l.first.decision, 'reintegre');
      expect(l.first.status, 'en_attente');
      // Heure MURALE du serveur, lue telle quelle (jamais `toLocal()`).
      expect(l.first.createdAt, DateTime(2026, 10, 21, 9, 30));
      expect(l.last.status, 'traite');
      expect(l.last.qty, isNull);
      expect(l.last.decision, isNull);
    });

    test('la demande ACQUITTÉE du poste reçoit son numéro : l\'avoir du serveur remplace la ligne, l\'identifiant est le même', () async {
      final r = await avoirs.enregistrer(
        venteId: vente1, produitId: oeufs, quantite: 2, montant: 11800, motif: 'Détériorée', decision: 'reintegre',
      );
      await moteur.synchroniser();
      expect((await lus()).single.creditNoteNumber, isNull);

      serveur.tirage = {
        'server_time': '2026-10-21T09:05:00Z',
        'credit_notes': [avoirJson(r.avoir!.id, numero: 'AV-2026-009')],
      };
      await moteur.synchroniser();

      final a = (await lus()).single;
      expect(a.id, r.avoir!.id);
      expect(a.creditNoteNumber, 'AV-2026-009');
      expect(a.deviceId, 'poste-test', reason: 'l\'origine de la saisie est gardée');
      expect(a.syncStatus, SyncStatus.synced);
    });

    for (final statut in [SyncStatus.pending, SyncStatus.conflict]) {
      test('⚠️⚠️ une demande ${statut.name} du poste n est ni effacée ni écrasée par le tirage', () async {
        final id = uuid('demande-${statut.name}');
        await db.into(db.creditNotes).insert(
          CreditNotesCompanion.insert(
            id: id,
            deviceId: 'poste-test',
            syncStatus: Value(statut),
            updatedAt: DateTime(2026, 10, 21),
            saleId: vente1,
            productId: oeufs,
            qty: const Value(2),
            amount: 11800,
            reason: const Value('Demande du poste'),
            status: const Value('traite'),
            createdAt: DateTime(2026, 10, 21, 8),
          ),
        );
        final avant = (await lus()).single;
        // Envoi sans accusé : la demande `pending` reste en attente (une `conflict` ne part pas).
        serveur.refus[id] = 'refus';
        serveur.tirage = {
          'server_time': '2026-10-21T09:00:00Z',
          // Le serveur sert une AUTRE version de la même ligne : elle ne doit pas écraser la saisie locale.
          'credit_notes': [avoirJson(id, statut: 'en_attente', numero: 'AV-2026-099', montant: 1)],
        };

        await moteur.synchroniser();

        final apres = (await lus()).single;
        expect(apres.amount, avant.amount);
        expect(apres.reason, avant.reason);
        expect(apres.status, 'traite');
        expect(apres.creditNoteNumber, isNull);
        expect(apres.deviceId, 'poste-test');
      });
    }

    group('STRICT : le lot est refusé, rien n est écrit, le curseur n avance pas', () {
      Future<void> refuse(Map<String, dynamic> avoir, {List<Map<String, dynamic>> plus = const []}) async {
        serveur.tirage = {
          'server_time': '2026-10-21T09:00:00Z',
          'credit_notes': [avoirJson(uuid('bon')), avoir, ...plus],
        };

        await expectLater(moteur.synchroniser(), throwsA(isA<Object>()));

        expect(await lus(), isEmpty, reason: 'le bon avoir du même lot n\'est pas écrit non plus');
      }

      test('vente inconnue du poste', () => refuse(avoirJson(uuid('x'), vente: uuid('vente-inconnue'))));
      test('montant négatif', () => refuse(avoirJson(uuid('x'), montant: -1)));
      test('montant absent', () => refuse(avoirJson(uuid('x'), montant: null)));
      test('statut illisible', () => refuse(avoirJson(uuid('x'), statut: 'rembourse')));
      test('décision illisible', () => refuse(avoirJson(uuid('x'), decision: 'detruit')));
      test('identifiant servi deux fois', () => refuse(avoirJson(uuid('bon'))));
      test('date illisible', () => refuse(avoirJson(uuid('x'), creation: 'hier')));
      test('quantité négative', () => refuse(avoirJson(uuid('x'), quantite: -3)));
    });

    test('clé absente (serveur antérieur, ou table non servie à ce compte) : rien n est touché', () async {
      await db.into(db.creditNotes).insert(
        CreditNotesCompanion.insert(
          id: uuid('local'),
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: DateTime(2026, 10, 21),
          saleId: vente1,
          productId: oeufs,
          amount: 5,
          createdAt: DateTime(2026, 10, 21),
        ),
      );
      serveur.tirage = {'server_time': '2026-10-21T09:00:00Z'};

      await moteur.synchroniser();

      expect((await lus()).single.id, uuid('local'));
    });
  });

  group('TIRAGE : les ventes portent leur remise et leur sous-total', () {
    test('discount et subtotal servis sont absorbés ; absents (serveur antérieur) : remise 0, sous-total = total', () async {
      serveur.tirage = {
        'server_time': '2026-10-21T09:00:00Z',
        'sales': [
          {
            'id': uuid('vente-remise'),
            'customer_id': null,
            'customer_name': null,
            'payment_mode': 'especes',
            'subtotal': 10000,
            'discount': 1500,
            'total': 8500,
            'status': 'validee',
            'sold_at': '2026-10-21T08:00:00+01:00',
          },
          {
            'id': uuid('vente-ancienne'),
            'payment_mode': 'especes',
            'total': 7000,
            'status': 'validee',
            'sold_at': '2026-10-21T08:30:00+01:00',
          },
        ],
      };

      await moteur.synchroniser();

      final v = {for (final s in await db.select(db.sales).get()) s.id: s};
      expect(v[uuid('vente-remise')]!.subtotal, 10000);
      expect(v[uuid('vente-remise')]!.discount, 1500);
      expect(v[uuid('vente-remise')]!.total, 8500);
      expect(v[uuid('vente-ancienne')]!.discount, 0);
      expect(v[uuid('vente-ancienne')]!.subtotal, 7000);
    });
  });
}
