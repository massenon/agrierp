import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_repository.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_repository.dart';
import 'package:agrierp/features/sync/coherence_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket S-T11 — LES DATES DU POSTE EN HEURE DU BÉNIN, QUEL QUE SOIT LE RÉGLAGE DE WINDOWS.
///
/// Règle : le JOUR métier est toujours le jour à l'heure du Bénin (UTC+1 toute l'année) ; les instants techniques
/// restent des instants. Point de passage unique : `lib/core/temps/heure_benin.dart`.
///
/// ⚠️⚠️ CE FICHIER DOIT PASSER DANS N'IMPORTE QUEL FUSEAU. Il est lancé dans le fuseau de la machine (UTC dans le
/// conteneur) ET, à la main ou en intégration continue, sous `TZ=America/New_York`, `TZ=Asia/Tokyo`, `TZ=UTC` et
/// `TZ=Africa/Porto-Novo` (`flutter test` respecte `TZ` : vérifié, décalage −4 h à New York, +9 h à Tokyo). L'horloge
/// est figée par [HeureBenin.horloge] sur des INSTANTS UTC : aucun attendu ne dépend du fuseau de la machine — ils
/// sont écrits à la main en heure du Bénin.
///
/// Les deux instants pivots : 00 h 30 au Bénin le 15/06 (= 23 h 30 UTC le 14 : la VEILLE pour un poste réglé en UTC
/// ou à New York) et 23 h 30 au Bénin le 15/06 (= 22 h 30 UTC ; le LENDEMAIN, 07 h 30, pour un poste réglé à Tokyo).
class _Connexion implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Serveur feint : sert [tirage] au tirage, acquitte tout envoi par `id` et garde chaque corps.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = const {};
  final envois = <Map<String, dynamic>>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      return handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [for (final e in value) if (e is Map && e['id'] is String) e['id']],
                  'rejected': [],
                },
          },
        ),
      );
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {...tirage, 'server_time': '2026-06-15T23:45:00+01:00'},
      ),
    );
  }
}

void main() {
  /// 00 h 30 au Bénin le 15/06/2026 — une date ÉLOIGNÉE du jour où le ticket a été écrit (19/10/2026), pour qu'une
  /// horloge système oubliée quelque part ne passe pas les tests par coïncidence.
  final minuitTrente = DateTime.utc(2026, 6, 14, 23, 30);

  /// 23 h 30 au Bénin le 15/06/2026.
  final vingtTroisTrente = DateTime.utc(2026, 6, 15, 22, 30);

  tearDown(HeureBenin.reinitialiser);

  group('S-T11 — conversions (point unique)', () {
    test('un instant devient l\'heure murale du Bénin, jamais celle de Windows', () {
      expect(HeureBenin.depuisInstant(minuitTrente), DateTime(2026, 6, 15, 0, 30));
      expect(HeureBenin.depuisInstant(vingtTroisTrente), DateTime(2026, 6, 15, 23, 30));
      // Le même instant donné en heure LOCALE de la machine (quel que soit son fuseau).
      expect(HeureBenin.depuisInstant(minuitTrente.toLocal()), DateTime(2026, 6, 15, 0, 30));
    });

    test('l\'heure murale du Bénin redevient le même instant (UTC)', () {
      expect(HeureBenin.versInstant(DateTime(2026, 6, 15, 0, 30)), minuitTrente);
      expect(HeureBenin.versInstant(DateTime(2026, 6, 15, 23, 30)), vingtTroisTrente);
      expect(HeureBenin.versInstant(DateTime(2026, 6, 15, 0, 30)).isUtc, isTrue);
    });

    test('⚠️⚠️ une date servie se lit au Bénin : jour pur, heure murale, instant Z, instant +01:00', () {
      // Jour pur et heure murale du serveur : lus tels quels.
      expect(HeureBenin.lire('2026-06-15'), DateTime(2026, 6, 15));
      expect(HeureBenin.lire('2026-06-15 10:30:00'), DateTime(2026, 6, 15, 10, 30));
      // Date Eloquent servie en instant UTC : minuit au Bénin = 23 h UTC la veille → le 15, pas le 14.
      expect(HeureBenin.lire('2026-06-14T23:00:00.000000Z'), DateTime(2026, 6, 15));
      // Vente servie avec son décalage.
      expect(HeureBenin.lire('2026-06-15T00:30:00+01:00'), DateTime(2026, 6, 15, 0, 30));
      expect(HeureBenin.lire('2026-06-15T23:30:00+01:00'), DateTime(2026, 6, 15, 23, 30));
      expect(HeureBenin.lire(null), isNull);
      expect(HeureBenin.lire('pas-une-date'), isNull);
    });

    test('maintenant et aujourd\'hui au Bénin, à 00 h 30 et à 23 h 30', () {
      HeureBenin.horloge = () => minuitTrente;
      expect(HeureBenin.maintenant(), DateTime(2026, 6, 15, 0, 30));
      expect(HeureBenin.aujourdhui(), DateTime(2026, 6, 15));
      HeureBenin.horloge = () => vingtTroisTrente;
      expect(HeureBenin.aujourdhui(), DateTime(2026, 6, 15));
      expect(HeureBenin.cleJour(HeureBenin.maintenant()), '2026-06-15');
    });

    test('⚠️ les jours se comptent au calendrier, jamais en heures (heure d\'été du fuseau de Windows)', () {
      // 1er octobre + 40 jours = 10 novembre, même si le fuseau de la machine change d'heure le 1er novembre.
      expect(HeureBenin.plusJours(DateTime(2026, 10, 1), 40), DateTime(2026, 11, 10));
      expect(HeureBenin.plusJours(DateTime(2026, 3, 1, 9), 14), DateTime(2026, 3, 15, 9));
      expect(HeureBenin.plusJours(DateTime(2026, 11, 10), -40), DateTime(2026, 10, 1));
    });

    test('l\'échéance d\'une saillie porcine (J+21, J+114) tombe le bon jour', () {
      final cycle = CycleReproduction(
        evenement: LivestockReproductionEvent(
          id: 'e1',
          deviceId: 'p',
          syncStatus: SyncStatus.synced,
          updatedAt: DateTime(2026, 10, 1),
          lotId: 'l1',
          motherRef: 'T1',
          saillieDate: DateTime(2026, 10, 1),
          status: 'en_cours',
        ),
        codeEspece: 'porciculture',
        codeBande: 'PORC-01',
      );
      expect(cycle.echeanceControle, DateTime(2026, 10, 22));
      expect(cycle.miseBasAffichee, DateTime(2027, 1, 23));
    });
  });

  group('S-T11 — au poste', () {
    late AppDatabase db;
    late _Serveur serveur;
    late SyncEngine moteur;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      serveur = _Serveur();
      final client = Dio(BaseOptions(baseUrl: 'http://serveur-feint'))..interceptors.add(serveur);
      moteur = SyncEngine(database: db, client: client, deviceId: 'poste-test', connectivity: _Connexion());
      await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          id: 'f2026000-0000-4000-8000-000000000000',
          year: 2026,
          startDate: Value(DateTime(2026, 1, 1)),
          endDate: Value(DateTime(2026, 12, 31)),
          status: const Value('ouvert'),
        ),
      );
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'qqqqqqqq-1111-4111-8111-qqqqqqqqqqqq',
          sku: 'ALI-001',
          name: 'Provende ponte',
          unit: 'sac',
          pricingMode: 'fixe',
          priceMin: const Value(6500),
          stockQty: const Value(20),
        ),
      );
    });

    tearDown(() async => db.close());

    Future<Sale> vendre() async {
      // Horloge PAR DÉFAUT de la caisse : celle du Bénin (aucune horloge injectée).
      final caisse = CaisseRepository(database: db, deviceId: 'poste-test');
      final provende = await db.select(db.products).getSingle();
      return caisse.enregistrerVente(
        panier: [LignePanier(produit: provende, quantite: 1, montant: 6500)],
        modePaiement: 'especes',
        especesRecues: 6500,
      );
    }

    for (final (libelle, instant, attendu) in [
      ('00 h 30', DateTime.utc(2026, 6, 14, 23, 30), '2026-06-15 00:30:00'),
      ('23 h 30', DateTime.utc(2026, 6, 15, 22, 30), '2026-06-15 23:30:00'),
    ]) {
      test('⚠️⚠️ une vente faite à $libelle au Bénin est du 15/06, et part datée du 15/06', () async {
        HeureBenin.horloge = () => instant;
        final caisse = CaisseRepository(database: db, deviceId: 'poste-test');
        expect(caisse.aujourdhui(), DateTime(2026, 6, 15), reason: '« aujourd\'hui » de la caisse');

        final vente = await vendre();
        expect(HeureBenin.cleJour(vente.soldAt), '2026-06-15');
        // `updatedAt` reste l'INSTANT de la saisie.
        expect(vente.updatedAt.isAtSameMomentAs(instant), isTrue);

        await moteur.synchroniser();
        final envoyee = (serveur.envois.single['sales'] as List).single as Map;
        expect(envoyee['sold_at'], attendu, reason: 'heure murale du Bénin, lue telle quelle par le serveur');
        expect(envoyee['updated_at'], instant.toIso8601String());
      });
    }

    test('« activités du jour » du tableau de bord : le jour d\'un instant du journal d\'audit est celui du Bénin', () async {
      HeureBenin.horloge = () => vingtTroisTrente;
      // 23 h 10 UTC le 14 = 00 h 10 au Bénin le 15 : du jour. 22 h 50 UTC le 14 = 23 h 50 au Bénin le 14 : de la veille.
      for (final (id, instant) in [
        ('j0000000-0000-4000-8000-000000000001', DateTime.utc(2026, 6, 14, 23, 10)),
        ('j0000000-0000-4000-8000-000000000002', DateTime.utc(2026, 6, 14, 22, 50)),
      ]) {
        await db.into(db.auditLogs).insert(
          AuditLogsCompanion.insert(id: id, action: 'sale.created', userName: const Value('Caisse'), createdAt: Value(instant)),
        );
      }
      final d = await TableauDeBordRepository(database: db).charger();
      expect([for (final a in d.activitesDuJour) a.detail], ['00:10 — Caisse']);
    });

    test('⚠️⚠️ tirage puis contrôle de cohérence S-T6 : ventes, soins et avances au bon jour, aucun écart', () async {
      HeureBenin.horloge = () => vingtTroisTrente;
      serveur.tirage = {
        'sales': [
          for (final (id, le) in [
            ('v0000000-0000-4000-8000-000000000001', '2026-06-15T00:30:00+01:00'),
            ('v0000000-0000-4000-8000-000000000002', '2026-06-15T23:30:00+01:00'),
          ])
            {
              'id': id,
              'payment_mode': 'especes',
              'total': 21000,
              'status': 'validee',
              'sold_at': le,
            },
        ],
        // `date` Eloquent : minuit du 15 au Bénin, servi 23 h UTC le 14 — exactement ce que l'essai S-T9 a vu.
        'customer_advances': [
          {
            'id': 'a0000000-0000-4000-8000-000000000001',
            'customer_id': 'c0000000-0000-4000-8000-000000000001',
            'amount': 5000,
            'amount_used': 0,
            'advance_date': '2026-06-14T23:00:00.000000Z',
            'is_active': true,
          },
        ],
        'veterinary_records': [
          {
            'id': 's0000000-0000-4000-8000-000000000001',
            'lot_id': 'l0000000-0000-4000-8000-000000000001',
            'action_type': 'Traitement',
            'cost': 2500,
            'record_date': '2026-06-14T23:00:00.000000Z',
            'is_active': true,
            'updated_at': '2026-06-14T23:10:00.000000Z',
          },
        ],
      };
      await moteur.synchroniser();

      final ventes = await (db.select(db.sales)..orderBy([(t) => OrderingTerm(expression: t.soldAt)])).get();
      expect([for (final v in ventes) v.soldAt], [DateTime(2026, 6, 15, 0, 30), DateTime(2026, 6, 15, 23, 30)]);
      expect((await db.select(db.customerAdvances).getSingle()).advanceDate, DateTime(2026, 6, 15));
      final soin = await db.select(db.veterinaryRecords).getSingle();
      expect(soin.recordDate, DateTime(2026, 6, 15));
      // Instant technique : gardé comme instant.
      expect(soin.updatedAt.isAtSameMomentAs(DateTime.utc(2026, 6, 14, 23, 10)), isTrue);

      // Ce que le serveur (à l'heure du Bénin) compte pour ces jours-là.
      String? demande;
      final controle = ControleCoherenceRepository(
        database: db,
        serveur: (depuis) async {
          demande = depuis;
          return {
            'tables': {
              'sales': {
                'jours': {'2026-06-15': {'nombre': 2, 'total': 42000}},
              },
              'customer_advances': {
                'jours': {'2026-06-15': {'nombre': 1, 'total': 5000}},
              },
              'veterinary_records': {
                'jours': {'2026-06-15': {'nombre': 1, 'total': 2500}},
              },
            },
          };
        },
      );
      final resultat = await controle.verifier();

      // Fenêtre « les 30 derniers jours, aujourd'hui compris » : du 17/05 au 15/06, au Bénin.
      expect(demande, '2026-05-17');
      expect(resultat.nombreEcarts, 0, reason: [
        for (final t in resultat.tables)
          for (final l in t.ecarts) '${t.table} ${l.jour} : poste ${l.poste} / serveur ${l.serveur}',
      ].join(' | '));
    });
  });
}
