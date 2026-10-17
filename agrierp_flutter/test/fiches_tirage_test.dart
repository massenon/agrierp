import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
// Drift exporte `isNull` / `isNotNull` (expressions SQL) : masqués ici pour
// laisser accessibles les matchers homonymes de `flutter_test`.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.94 — L'HISTORIQUE DES FICHES JOURNALIÈRES DESCEND AU POSTE.
///
/// ⚠️⚠️ Avant ce ticket, `/sync/pull` servait `livestock_daily_entries` et le poste n'avait AUCUN
/// absorbeur pour cette table : une journée saisie sur le web n'arrivait jamais au poste, et les
/// fiches recalculées en cascade par le serveur (15.31) non plus. Aucune erreur : la clé était
/// simplement ignorée.
///
/// Le serveur ci-dessous est un MODÈLE écrit à la main d'après la LECTURE de
/// `SyncController::pull` (fiches servies par `updated_at > since`, sérialisées par le modèle
/// `LivestockDailyEntry` : `entry_date` en `Y-m-d`, `feed_qty_kg` en chaîne décimale, `don`
/// nullable) et de `pushDailyEntries` (contrainte unique (bande, jour) → refus motivé).
/// Tous les chiffres attendus sont des LITTÉRAUX.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Un VRAI UUID (8-4-4-4-12 hexadécimal) déduit d'une graine lisible.
String _uuid(String graine) {
  final hex = graine.codeUnits
      .map((c) => c.toRadixString(16).padLeft(2, '0'))
      .join()
      .padRight(32, '0')
      .substring(0, 32);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

const _motifDoublon =
    'Une fiche existe deja pour cette bande a cette date, saisie depuis un '
    'autre poste. Comparez les deux avant de trancher.';

/// Serveur MODÈLE : sert [tirage] (déformable) et applique l'unicité (bande, jour) au push.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {};

  /// Fiches stockées côté serveur : id → (bande, jour).
  final Map<String, (String, String)> fiches = {};

  final List<String?> demandes = [];
  final List<Map<String, dynamic>> envois = [];
  var horloge = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      final acceptees = <String>[];
      final refusees = <Map<String, String>>[];
      for (final brut
          in corps['livestock_daily_entries'] as List? ?? const []) {
        final e = brut as Map;
        final id = e['id'] as String;
        final cle = (e['lot_id'] as String, e['entry_date'] as String);
        final doublon = fiches.entries.any(
          (f) => f.key != id && f.value == cle,
        );
        if (!fiches.containsKey(id) && doublon) {
          refusees.add({'id': id, 'reason': _motifDoublon});
          continue;
        }
        fiches[id] = cle;
        acceptees.add(id);
      }
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'livestock_daily_entries': {
              'accepted': acceptees,
              'rejected': refusees,
            },
          },
        ),
      );
      return;
    }

    demandes.add(options.queryParameters['since'] as String?);
    horloge++;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'server_time': DateTime.utc(
            2026,
            10,
            14,
            12,
            0,
            horloge,
          ).toIso8601String(),
          ...tirage,
        },
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;

  final bande = _uuid('bande-lapins');
  final autreBande = _uuid('bande-porcs');
  final espece = _uuid('espece');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    for (final (id, code) in [(bande, 'LAP-01'), (autreBande, 'POR-01')]) {
      await db
          .into(db.livestockLots)
          .insert(
            LivestockLotsCompanion.insert(
              id: id,
              code: code,
              speciesId: espece,
              initialQuantity: const Value(50),
              currentQuantity: const Value(44),
              isActive: const Value(true),
            ),
          );
    }
  });

  tearDown(() async => db.close());

  SyncEngine moteur() {
    final client = Dio(BaseOptions(baseUrl: 'http://serveur-modele'));
    client.interceptors.add(serveur);
    return SyncEngine(
      database: db,
      client: client,
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 14, 16),
    );
  }

  /// Fiche telle que le serveur la sérialise (modèle `LivestockDailyEntry`, casts compris).
  Map<String, dynamic> servie(
    String graine,
    String jour, {
    String? lot,
    int achat = 0,
    int ne = 0,
    int mort = 0,
    int vente = 0,
    Object? don,
    int effectif = 50,
  }) => {
    'id': _uuid(graine),
    'lot_id': lot ?? bande,
    'entry_date': jour,
    'achat': achat,
    'ne': ne,
    'mort': mort,
    'vente': vente,
    'don': don,
    'effectif_final': effectif,
    'effectif_m': null,
    'effectif_f': null,
    'effectif_sevres': null,
    'effectif_smeres': null,
    'cat_eff_repro': null,
    'cat_eff_sevre': null,
    'cat_eff_jeune': null,
    'cat_eff_4': null,
    // F0.95 — colonnes de ventilation de 15.39, servies à null pour une fiche non ventilée.
    for (final c in SyncEngine.colonnesVentilation) c: null,
    'feed_qty_kg': null,
    'feed_product_id': null,
    'weight_sample_avg_g': null,
    'ponte_total': null,
    'ponte_casses': null,
    'treatment_product_id': null,
    'treatment_dose': null,
    'symptomes': null,
    'vente_sexe': null,
    'vente_montant': null,
    'created_at': '2026-10-14T08:00:00.000000Z',
    'updated_at': '2026-10-14T08:30:00.000000Z',
  };

  Future<void> ficheLocale(
    String id,
    DateTime jour,
    SyncStatus statut, {
    int mort = 0,
    int effectif = 50,
    String? lot,
  }) => db
      .into(db.livestockDailyEntries)
      .insert(
        LivestockDailyEntriesCompanion.insert(
          id: id,
          deviceId: 'poste-test',
          syncStatus: Value(statut),
          updatedAt: DateTime(2026, 10, 14, 9),
          lotId: lot ?? bande,
          entryDate: jour,
          mort: Value(mort),
          effectifFinal: Value(effectif),
        ),
      );

  Future<LivestockDailyEntry?> fiche(String id) => (db.select(
    db.livestockDailyEntries,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<LivestockDailyEntry>> toutes() => (db.select(
    db.livestockDailyEntries,
  )..orderBy([(t) => OrderingTerm(expression: t.entryDate)])).get();

  group('absorption', () {
    test(
      '⚠️⚠️ une journée saisie sur le web descend au poste, colonne par colonne',
      () async {
        serveur.tirage = {
          'livestock_daily_entries': [
            {
              ...servie(
                'web-12',
                '2026-10-12',
                achat: 2,
                ne: 3,
                mort: 1,
                vente: 4,
                don: 1,
                effectif: 49,
              ),
              'ponte_total': 120,
              'ponte_casses': 3,
              // `decimal:2` : Laravel sert une CHAÎNE.
              'feed_qty_kg': '12.50',
              'weight_sample_avg_g': 1830,
            },
          ],
        };

        await moteur().synchroniser();

        final f = (await fiche(_uuid('web-12')))!;
        expect(f.lotId, bande);
        expect(f.entryDate, DateTime(2026, 10, 12));
        expect(
          [f.achat, f.ne, f.mort, f.vente, f.don, f.effectifFinal],
          [2, 3, 1, 4, 1, 49],
        );
        expect(f.ponteTotal, 120);
        expect(f.ponteCasses, 3);
        expect(f.feedQtyKg, 12.5);
        expect(f.weightSampleAvgG, 1830);
        expect(f.syncStatus, SyncStatus.synced);
        expect(f.deviceId, 'serveur');
        expect(f.updatedAt, DateTime.utc(2026, 10, 14, 8, 30).toLocal());
      },
    );

    test(
      'une bande créée sur le web arrive avec ses fiches dans le même tirage',
      () async {
        final neuve = _uuid('bande-neuve');
        serveur.tirage = {
          'livestock_lots': [
            {
              'id': neuve,
              'code': 'LAP-02',
              'species_id': espece,
              'initial_quantity': 10,
              'current_quantity': 9,
              'is_active': true,
            },
          ],
          'livestock_daily_entries': [
            servie('neuve-1', '2026-10-13', lot: neuve, mort: 1, effectif: 9),
          ],
        };

        await moteur().synchroniser();

        expect((await fiche(_uuid('neuve-1')))!.lotId, neuve);
      },
    );

    test(
      '⚠️⚠️ une fiche synchronisée prend la version du serveur (cascade 15.31 : 49/47/50 → 43/41/44)',
      () async {
        await ficheLocale(
          _uuid('f12'),
          DateTime(2026, 10, 12),
          SyncStatus.synced,
          effectif: 49,
        );
        await ficheLocale(
          _uuid('f13'),
          DateTime(2026, 10, 13),
          SyncStatus.synced,
          effectif: 47,
        );
        await ficheLocale(
          _uuid('f14'),
          DateTime(2026, 10, 14),
          SyncStatus.synced,
          effectif: 50,
        );
        // Vente de 6 sujets à J-2 sur le web : le serveur recalcule les trois fiches.
        // 49 − 6 = 43 ; 47 − 6 = 41 ; 50 − 6 = 44 (le 12 porte la vente).
        serveur.tirage = {
          'livestock_daily_entries': [
            servie('f12', '2026-10-12', vente: 6, effectif: 43),
            servie('f13', '2026-10-13', effectif: 41),
            servie('f14', '2026-10-14', effectif: 44),
          ],
        };

        await moteur().synchroniser();

        final f = await toutes();
        expect(f.map((x) => x.effectifFinal), [43, 41, 44]);
        expect(f.first.vente, 6);
        expect(f.every((x) => x.syncStatus == SyncStatus.synced), isTrue);
        expect(
          f.every((x) => x.deviceId == 'poste-test'),
          isTrue,
          reason: 'l origine d une fiche déjà connue est gardée',
        );
      },
    );

    test(
      '⚠️⚠️ une fiche EN ATTENTE n est jamais écrasée, même si le serveur en sert une autre version',
      () async {
        await ficheLocale(
          _uuid('f12'),
          DateTime(2026, 10, 12),
          SyncStatus.pending,
          mort: 2,
          effectif: 48,
        );
        serveur.tirage = {
          'livestock_daily_entries': [
            servie('f12', '2026-10-12', mort: 9, effectif: 41),
          ],
        };

        // Tirage seul : la fiche part ensuite au push, c'est le serveur qui arbitrera.
        await moteur().synchroniser();

        final f = (await fiche(_uuid('f12')))!;
        expect(f.mort, 2);
        expect(f.effectifFinal, 48);
        expect(f.deviceId, 'poste-test');
        expect(f.updatedAt, DateTime(2026, 10, 14, 9));
        // Elle est partie au push (dernier écrivain gagne côté serveur) et a été acquittée.
        final envoyees =
            serveur.envois.single['livestock_daily_entries'] as List;
        expect(envoyees.single['mort'], 2);
      },
    );

    test('⚠️⚠️ une fiche EN CONFLIT n est jamais écrasée', () async {
      await ficheLocale(
        _uuid('f12'),
        DateTime(2026, 10, 12),
        SyncStatus.conflict,
        mort: 2,
        effectif: 48,
      );
      serveur.tirage = {
        'livestock_daily_entries': [
          servie('f12', '2026-10-12', mort: 9, effectif: 41),
        ],
      };

      await moteur().synchroniser();

      final f = (await fiche(_uuid('f12')))!;
      expect(f.mort, 2);
      expect(f.effectifFinal, 48);
      expect(f.syncStatus, SyncStatus.conflict);
      expect(
        serveur.envois,
        isEmpty,
        reason: 'une fiche en conflit ne part pas',
      );
    });

    test(
      '⚠️⚠️ un tirage INCRÉMENTAL n efface rien : seules les fiches servies changent',
      () async {
        serveur.tirage = {
          'livestock_daily_entries': [
            servie('a', '2026-10-11', effectif: 50),
            servie('b', '2026-10-12', effectif: 49),
            servie('c', '2026-10-13', effectif: 48),
          ],
        };
        await moteur().synchroniser();

        serveur.tirage = {
          'livestock_daily_entries': [
            servie('c', '2026-10-13', mort: 2, effectif: 47),
          ],
        };
        await moteur().synchroniser();

        expect(serveur.demandes.first, isNull);
        expect(serveur.demandes.last, isNotNull, reason: 'avec since');
        final f = await toutes();
        expect(f.map((x) => x.id), [_uuid('a'), _uuid('b'), _uuid('c')]);
        expect(f.map((x) => x.effectifFinal), [50, 49, 47]);
      },
    );

    test(
      '« don » nul au serveur (colonne nullable) = 0 au poste ; ponte nulle reste nulle',
      () async {
        serveur.tirage = {
          'livestock_daily_entries': [servie('a', '2026-10-11')],
        };
        await moteur().synchroniser();

        final f = (await fiche(_uuid('a')))!;
        expect(f.don, 0);
        expect(f.ponteTotal, isNull);
        expect(f.feedQtyKg, isNull);
      },
    );

    test('nombres servis en chaîne (pilote MySQL) acceptés', () async {
      serveur.tirage = {
        'livestock_daily_entries': [
          {
            ...servie('a', '2026-10-11'),
            'mort': '3',
            'effectif_final': '47',
            'weight_sample_avg_g': '1830',
          },
        ],
      };
      await moteur().synchroniser();

      final f = (await fiche(_uuid('a')))!;
      expect([f.mort, f.effectifFinal], [3, 47]);
      expect(f.weightSampleAvgG, 1830);
    });

    test('sans la clé, rien ne bouge et rien n échoue', () async {
      await ficheLocale(
        _uuid('f12'),
        DateTime(2026, 10, 12),
        SyncStatus.synced,
      );
      serveur.tirage = {};

      await moteur().synchroniser();

      expect(await toutes(), hasLength(1));
    });
  });

  group('bande et compteurs', () {
    test(
      '⚠️⚠️ la fiche absorbée ne touche PAS l effectif courant de la bande',
      () async {
        serveur.tirage = {
          'livestock_daily_entries': [
            servie('a', '2026-10-13', mort: 20, effectif: 30),
          ],
        };

        await moteur().synchroniser();

        final lot = await (db.select(
          db.livestockLots,
        )..where((t) => t.id.equals(bande))).getSingle();
        expect(lot.currentQuantity, 44, reason: 'c est le serveur qui le sert');
      },
    );

    test(
      '⚠️ un tirage ne fausse pas le compteur « en attente » et une fiche absorbée ne repart pas',
      () async {
        await ficheLocale(
          _uuid('locale'),
          DateTime(2026, 10, 10),
          SyncStatus.pending,
        );
        await ficheLocale(
          _uuid('refusee'),
          DateTime(2026, 10, 9),
          SyncStatus.conflict,
        );
        expect(await db.pendingCount(), 2);

        serveur.tirage = {
          'livestock_daily_entries': [
            servie('a', '2026-10-11'),
            servie('b', '2026-10-12'),
            servie('c', '2026-10-13'),
          ],
        };
        // On mesure le compteur juste après le tirage, avant l'acquittement : un serveur qui ne
        // répond rien au push laisse la file intacte.
        final client = Dio(BaseOptions(baseUrl: 'http://serveur-modele'));
        client.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              if (o.path.contains('push')) {
                serveur.envois.add(o.data as Map<String, dynamic>);
                h.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: o,
                    statusCode: 200,
                    data: <String, dynamic>{},
                  ),
                );
                return;
              }
              serveur.onRequest(o, h);
            },
          ),
        );
        await SyncEngine(
          database: db,
          client: client,
          deviceId: 'poste-test',
          connectivity: _Connectivite(),
        ).synchroniser();

        expect(await db.pendingCount(), 2);
        final parties =
            serveur.envois.single['livestock_daily_entries'] as List;
        expect(parties.map((e) => e['id']), [_uuid('locale')]);
      },
    );
  });

  group('même bande, même jour, autre identifiant', () {
    test(
      '⚠️⚠️ saisie locale EN ATTENTE conservée, avertissement, puis refus VISIBLE du serveur',
      () async {
        await ficheLocale(
          _uuid('poste'),
          DateTime(2026, 10, 12),
          SyncStatus.pending,
          mort: 2,
          effectif: 48,
        );
        serveur.fiches[_uuid('web')] = (bande, '2026-10-12');
        serveur.tirage = {
          'livestock_daily_entries': [
            servie('web', '2026-10-12', mort: 5, effectif: 45),
          ],
        };

        final resultat = await moteur().synchroniser();

        final f = await toutes();
        expect(f.map((x) => x.id), [_uuid('poste')], reason: 'rien supprimé');
        expect(f.single.mort, 2);
        expect(
          resultat.avertissements.join(' '),
          allOf(contains('12/10/2026'), contains('LAP-01')),
        );
        // Le serveur a refusé la saisie du poste (unicité bande, jour) : conflit avec son motif.
        expect(f.single.syncStatus, SyncStatus.conflict);
        final conflit = (await moteur().conflits()).single;
        expect(conflit.recordId, _uuid('poste'));
        expect(conflit.reason, _motifDoublon);
      },
    );

    test('saisie locale EN CONFLIT conservée, avertissement', () async {
      await ficheLocale(
        _uuid('poste'),
        DateTime(2026, 10, 12),
        SyncStatus.conflict,
        mort: 2,
      );
      serveur.tirage = {
        'livestock_daily_entries': [servie('web', '2026-10-12', mort: 5)],
      };

      final resultat = await moteur().synchroniser();

      final f = await toutes();
      expect(f.single.id, _uuid('poste'));
      expect(f.single.mort, 2);
      expect(f.single.syncStatus, SyncStatus.conflict);
      expect(resultat.avertissements, hasLength(1));
    });

    test(
      '⚠️ copie locale SYNCHRONISÉE sous un autre id : jamais supprimée, avertissement',
      () async {
        await ficheLocale(
          _uuid('ancienne'),
          DateTime(2026, 10, 12),
          SyncStatus.synced,
          mort: 2,
        );
        serveur.tirage = {
          'livestock_daily_entries': [servie('web', '2026-10-12', mort: 5)],
        };

        final resultat = await moteur().synchroniser();

        final f = await toutes();
        expect(f.single.id, _uuid('ancienne'));
        expect(f.single.mort, 2);
        expect(resultat.avertissements, hasLength(1));
      },
    );

    test(
      '⚠️ une fiche synchronisée dont le serveur change le jour vers un jour déjà occupé : rien n est écrasé',
      () async {
        await ficheLocale(
          _uuid('x'),
          DateTime(2026, 10, 12),
          SyncStatus.synced,
          mort: 1,
        );
        await ficheLocale(
          _uuid('y'),
          DateTime(2026, 10, 13),
          SyncStatus.pending,
          mort: 2,
        );
        serveur.tirage = {
          'livestock_daily_entries': [servie('x', '2026-10-13', mort: 7)],
        };

        final resultat = await moteur().synchroniser();

        expect((await fiche(_uuid('x')))!.mort, 1);
        expect((await fiche(_uuid('y')))!.mort, 2);
        expect(resultat.avertissements, hasLength(1));
      },
    );

    test(
      '⚠️⚠️ une fiche web absorbée est REPRISE par la saisie du poste (même id : plus de collision)',
      () async {
        serveur.fiches[_uuid('web')] = (bande, '2026-10-12');
        serveur.tirage = {
          'livestock_daily_entries': [
            servie('web', '2026-10-12', mort: 1, effectif: 49),
          ],
        };
        await moteur().synchroniser();

        final depot = FicheJournaliereRepository(
          database: db,
          deviceId: 'poste-test',
        );
        await depot.enregistrer(
          lotId: bande,
          jour: DateTime(2026, 10, 12),
          achat: 0,
          ne: 0,
          mort: 3,
          don: 0,
        );
        serveur.tirage = {};
        await moteur().synchroniser();

        final f = await toutes();
        expect(f.single.id, _uuid('web'));
        expect(f.single.mort, 3);
        expect(f.single.syncStatus, SyncStatus.synced, reason: 'acceptée');
        expect(await moteur().conflits(), isEmpty);
      },
    );
  });

  group('⚠️⚠️ refus STRICT de tout le lot', () {
    final cas = <String, Object? Function(Map<String, dynamic> valide)>{
      'bande inconnue': (v) => {...v, 'lot_id': _uuid('fantome')},
      'bande non UUID': (v) => {...v, 'lot_id': 'LAP-01'},
      'bande absente': (v) => {...v}..remove('lot_id'),
      'identifiant non UUID': (v) => {...v, 'id': 'f-12'},
      'identifiant absent': (v) => {...v}..remove('id'),
      'date illisible': (v) => {...v, 'entry_date': '14/10/2026'},
      'date impossible': (v) => {...v, 'entry_date': '2026-02-30'},
      'date en instant': (v) => {...v, 'entry_date': '2026-10-13T23:00:00Z'},
      'date absente': (v) => {...v, 'entry_date': null},
      'achat négatif': (v) => {...v, 'achat': -1},
      'morts NaN': (v) => {...v, 'mort': 'NaN'},
      'vente fractionnaire': (v) => {...v, 'vente': 2.5},
      'effectif absent': (v) => {...v}..remove('effectif_final'),
      'effectif négatif': (v) => {...v, 'effectif_final': -3},
      'don illisible': (v) => {...v, 'don': 'deux'},
      'provende Infinity': (v) => {...v, 'feed_qty_kg': 'Infinity'},
      'provende négative': (v) => {...v, 'feed_qty_kg': '-1.00'},
      'ponte négative': (v) => {...v, 'ponte_total': -5},
      'horodatage illisible': (v) => {...v, 'updated_at': 'hier'},
      'élément non objet': (v) => 'fiche',
    };

    for (final MapEntry(key: nom, value: casser) in cas.entries) {
      test(
        'refus : $nom (rien n est écrit, le curseur n avance pas)',
        () async {
          await ficheLocale(
            _uuid('locale'),
            DateTime(2026, 10, 10),
            SyncStatus.pending,
            mort: 4,
          );
          serveur.tirage = {
            'livestock_daily_entries': [
              servie('valide', '2026-10-12', mort: 1),
              casser(servie('casse', '2026-10-13')),
            ],
          };

          await expectLater(
            moteur().synchroniser(),
            throwsA(isA<FormatException>()),
          );

          final f = await toutes();
          expect(f.map((x) => x.id), [_uuid('locale')], reason: 'rollback');
          expect(f.single.mort, 4);
          expect(f.single.syncStatus, SyncStatus.pending);
          expect((await db.etatDeSynchronisation())?.lastPulledAt, isNull);
        },
      );
    }

    test('refus : la clé n est pas une liste', () async {
      serveur.tirage = {'livestock_daily_entries': 'fiches'};
      await expectLater(
        moteur().synchroniser(),
        throwsA(isA<FormatException>()),
      );
    });

    test('refus : même identifiant servi deux fois', () async {
      serveur.tirage = {
        'livestock_daily_entries': [
          servie('a', '2026-10-12'),
          servie('a', '2026-10-13'),
        ],
      };
      await expectLater(
        moteur().synchroniser(),
        throwsA(isA<FormatException>()),
      );
      expect(await toutes(), isEmpty);
    });

    test('refus : deux fiches pour la même bande le même jour', () async {
      serveur.tirage = {
        'livestock_daily_entries': [
          servie('a', '2026-10-12'),
          servie('b', '2026-10-12'),
        ],
      };
      await expectLater(
        moteur().synchroniser(),
        throwsA(isA<FormatException>()),
      );
      expect(await toutes(), isEmpty);
    });

    test('le même jour sur deux bandes différentes est accepté', () async {
      serveur.tirage = {
        'livestock_daily_entries': [
          servie('a', '2026-10-12'),
          servie('b', '2026-10-12', lot: autreBande),
        ],
      };
      await moteur().synchroniser();
      expect(await toutes(), hasLength(2));
    });
  });

  group('resynchronisation unique de l historique', () {
    test(
      '⚠️⚠️ un poste déjà en service redemande TOUT une fois (l historique est antérieur à son curseur)',
      () async {
        await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
        // Le poste a déjà fait ses resynchronisations du journal (F0.84-bis, F0.85).
        for (final cle in [
          SyncEngine.cleJournalResync,
          SyncEngine.cleJournalResyncCreation,
        ]) {
          await db
              .into(db.appSettings)
              .insert(AppSettingsCompanion.insert(key: cle, value: '1'));
        }
        serveur.tirage = {
          'livestock_daily_entries': [servie('ancienne', '2026-09-20')],
        };

        await moteur().synchroniser();
        await moteur().synchroniser();

        expect(serveur.demandes.first, isNull, reason: 'sans since, une fois');
        expect(serveur.demandes.last, isNotNull, reason: 'puis incrémental');
        expect(await fiche(_uuid('ancienne')), isNotNull);
      },
    );

    test('un tirage refusé ne marque pas la resynchronisation faite', () async {
      await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
      for (final cle in [
        SyncEngine.cleJournalResync,
        SyncEngine.cleJournalResyncCreation,
      ]) {
        await db
            .into(db.appSettings)
            .insert(AppSettingsCompanion.insert(key: cle, value: '1'));
      }
      serveur.tirage = {
        'livestock_daily_entries': [
          {...servie('a', '2026-10-12'), 'lot_id': _uuid('fantome')},
        ],
      };
      await expectLater(
        moteur().synchroniser(),
        throwsA(isA<FormatException>()),
      );

      serveur.tirage = {
        'livestock_daily_entries': [servie('a', '2026-10-12')],
      };
      await moteur().synchroniser();

      expect(serveur.demandes, [null, null]);
    });
  });
}
