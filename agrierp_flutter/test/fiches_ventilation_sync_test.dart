import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
// Drift exporte `isNull` / `isNotNull` (expressions SQL) : masqués pour les matchers.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'php_laravel.dart';

/// Ticket F0.95 — fiches journalières et EFFECTIF PAR CATÉGORIE dans la synchronisation.
///
/// Serveur MODÈLE écrit d'après la LECTURE de `SyncController::pull` (toutes les colonnes du
/// modèle servies, `null` compris) et de `pushDailyEntries` (15.40). Les motifs de refus sont
/// ceux de `App\Support\MotifsRefusPush` MOT POUR MOT ; un test les compare au vrai PHP.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

String _uuid(String graine) {
  final hex = graine.codeUnits
      .map((c) => c.toRadixString(16).padLeft(2, '0'))
      .join()
      .padRight(32, '0')
      .substring(0, 32);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Motifs de `MotifsRefusPush` (15.40), recopiés ; comparés au PHP plus bas.
const _motifD7 =
    'Fiche refusée : cette bande suit son effectif par catégorie et les morts de la fiche ne '
    'sont pas ventilés par catégorie. Votre poste est un ancien poste : une mise à jour du poste '
    'est nécessaire avant de pouvoir saisir cette fiche.';
const _motifDepartFixe =
    'Effectif de départ refusé : effectif de départ déjà fixé le 01/10/2026 pour cette bande.';
const _motifIncoherent =
    'Ventilation incohérente : les morts de la fiche (5) ne correspondent pas à la somme des '
    'trois catégories (3).';
const _motifPassage =
    'Passage de stade refusé : 25 sujet(s) à faire passer, mais la catégorie source '
    "n'en compte que 20.";

class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {};

  /// id → motif de refus à opposer au push.
  final Map<String, String> refus = {};
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
        final id = (brut as Map)['id'] as String;
        final motif = refus[id];
        if (motif != null) {
          refusees.add({'id': id, 'reason': motif});
        } else {
          acceptees.add(id);
        }
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
  final espece = _uuid('espece');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    await db
        .into(db.livestockLots)
        .insert(
          LivestockLotsCompanion.insert(
            id: bande,
            code: 'LAP-01',
            speciesId: espece,
            speciesCode: const Value('cuniculture'),
            initialQuantity: const Value(60),
            currentQuantity: const Value(60),
            isActive: const Value(true),
          ),
        );
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

  /// Fiche telle que le serveur la sérialise après 15.39 (toutes les colonnes, null compris).
  Map<String, dynamic> servie(String graine, String jour, [Map<String, Object?> v = const {}]) => {
    'id': _uuid(graine),
    'lot_id': bande,
    'entry_date': jour,
    'achat': 0,
    'ne': 0,
    'mort': 0,
    'vente': 0,
    'don': 0,
    'effectif_final': 60,
    for (final c in [
      'effectif_m',
      'effectif_f',
      'effectif_sevres',
      'effectif_smeres',
      'cat_eff_repro',
      'cat_eff_sevre',
      'cat_eff_jeune',
      'cat_eff_4',
      ...SyncEngine.colonnesVentilation,
    ])
      c: null,
    'feed_qty_kg': null,
    'weight_sample_avg_g': null,
    'ponte_total': null,
    'ponte_casses': null,
    'created_at': '2026-10-14T08:00:00.000000Z',
    'updated_at': '2026-10-14T08:30:00.000000Z',
    ...v,
  };

  Future<void> ficheLocale(
    String graine,
    int jour,
    SyncStatus statut, {
    int mort = 0,
    int don = 0,
    int effectif = 60,
    int? mR,
    int? mS,
    int? mJ,
    int? dR,
    int? dS,
    int? dJ,
    int? passage,
    (int, int, int)? depart,
    (int, int, int)? categories,
    int? effectifM,
  }) => db
      .into(db.livestockDailyEntries)
      .insert(
        LivestockDailyEntriesCompanion.insert(
          id: _uuid(graine),
          deviceId: 'poste-test',
          syncStatus: Value(statut),
          updatedAt: DateTime(2026, 10, 14, 9),
          lotId: bande,
          entryDate: DateTime(2026, 10, jour),
          mort: Value(mort),
          don: Value(don),
          effectifFinal: Value(effectif),
          mortRepro: Value(mR),
          mortSevre: Value(mS),
          mortJeune: Value(mJ),
          donRepro: Value(dR),
          donSevre: Value(dS),
          donJeune: Value(dJ),
          passageSevreJeune: Value(passage),
          catDepartRepro: Value(depart?.$1),
          catDepartSevre: Value(depart?.$2),
          catDepartJeune: Value(depart?.$3),
          catEffRepro: Value(categories?.$1),
          catEffSevre: Value(categories?.$2),
          catEffJeune: Value(categories?.$3),
          effectifM: Value(effectifM),
        ),
      );

  Future<LivestockDailyEntry> fiche(String graine) => (db.select(
    db.livestockDailyEntries,
  )..where((t) => t.id.equals(_uuid(graine)))).getSingle();

  Future<void> resyncDejaFaites() async {
    for (final cle in [
      SyncEngine.cleJournalResync,
      SyncEngine.cleJournalResyncCreation,
      SyncEngine.cleFichesResync,
    ]) {
      await db
          .into(db.appSettings)
          .insert(AppSettingsCompanion.insert(key: cle, value: '1'));
    }
  }

  List<Map<String, dynamic>> fichesEnvoyees() => [
    for (final e in serveur.envois.last['livestock_daily_entries'] as List)
      (e as Map).cast<String, dynamic>(),
  ];

  group('absorbeur (F0.94 étendu)', () {
    test('⚠️⚠️ les 18 nouvelles colonnes descendent, valeur par valeur', () async {
      serveur.tirage = {
        'livestock_daily_entries': [
          servie('a', '2026-10-01', {
            'mort': 3,
            'don': 1,
            'mort_repro': 1,
            'mort_sevre': 2,
            'mort_jeune': 0,
            'don_repro': 0,
            'don_sevre': 1,
            'don_jeune': 0,
            'passage_sevre_jeune': 4,
            'cat_depart_repro': 10,
            'cat_depart_sevre': 20,
            'cat_depart_jeune': 30,
            'cat_eff_repro': 9,
            'cat_eff_sevre': 13,
            'cat_eff_jeune': 34,
            'cat_eff_4': 7,
            'effectif_m': 11,
            'effectif_f': 12,
            'effectif_sevres': 13,
            'effectif_smeres': 14,
          }),
        ],
      };
      await moteur().synchroniser();

      final f = await fiche('a');
      expect(
        [f.mortRepro, f.mortSevre, f.mortJeune, f.donRepro, f.donSevre, f.donJeune],
        [1, 2, 0, 0, 1, 0],
      );
      expect(f.passageSevreJeune, 4);
      expect([f.catDepartRepro, f.catDepartSevre, f.catDepartJeune], [10, 20, 30]);
      expect([f.catEffRepro, f.catEffSevre, f.catEffJeune, f.catEff4], [9, 13, 34, 7]);
      expect([f.effectifM, f.effectifF, f.effectifSevres, f.effectifSmeres], [11, 12, 13, 14]);
    });

    test('null servi = inconnu (null au poste), JAMAIS 0', () async {
      serveur.tirage = {
        'livestock_daily_entries': [servie('a', '2026-10-01')],
      };
      await moteur().synchroniser();
      final f = await fiche('a');
      expect(
        [
          f.mortRepro,
          f.passageSevreJeune,
          f.catDepartRepro,
          f.catEffRepro,
          f.catEff4,
          f.effectifM,
        ],
        everyElement(isNull),
      );
    });

    test(
      '⚠️⚠️ CLÉ ABSENTE (serveur pas à jour) : la valeur locale est GARDÉE',
      () async {
        await ficheLocale(
          'a',
          1,
          SyncStatus.synced,
          mort: 3,
          mR: 1,
          mS: 2,
          mJ: 0,
          categories: (9, 13, 34),
          effectifM: 5,
        );
        final ancien = servie('a', '2026-10-01', {'mort': 3, 'effectif_final': 57});
        for (final c in [
          ...SyncEngine.colonnesVentilation,
          'cat_eff_repro',
          'cat_eff_sevre',
          'cat_eff_jeune',
          'cat_eff_4',
          'effectif_m',
        ]) {
          ancien.remove(c);
        }
        serveur.tirage = {
          'livestock_daily_entries': [ancien],
        };
        await moteur().synchroniser();

        final f = await fiche('a');
        expect(f.effectifFinal, 57, reason: 'le reste de la fiche suit le serveur');
        expect([f.mortRepro, f.mortSevre, f.mortJeune], [1, 2, 0]);
        expect([f.catEffRepro, f.catEffSevre, f.catEffJeune], [9, 13, 34]);
        expect(f.effectifM, 5);
      },
    );

    test(
      '⚠️⚠️ NULL EXPLICITE : la valeur locale d une fiche synchronisée est remplacée',
      () async {
        await ficheLocale(
          'a',
          1,
          SyncStatus.synced,
          categories: (9, 13, 34),
          mR: 0,
          mS: 0,
          mJ: 0,
        );
        serveur.tirage = {
          'livestock_daily_entries': [servie('a', '2026-10-01')],
        };
        await moteur().synchroniser();
        final f = await fiche('a');
        expect([f.catEffRepro, f.catEffSevre, f.catEffJeune], [null, null, null]);
        expect(f.mortRepro, isNull);
      },
    );

    test(
      '⚠️⚠️ cascade du serveur : `effectif_final` et `cat_eff_*` corrigés remplacent ceux d une fiche synchronisée',
      () async {
        await ficheLocale('a', 2, SyncStatus.synced, effectif: 58, categories: (9, 25, 24));
        serveur.tirage = {
          'livestock_daily_entries': [
            servie('a', '2026-10-02', {
              'effectif_final': 52,
              'cat_eff_repro': 9,
              'cat_eff_sevre': 25,
              'cat_eff_jeune': 18,
            }),
          ],
        };
        await moteur().synchroniser();
        final f = await fiche('a');
        expect(f.effectifFinal, 52);
        expect([f.catEffRepro, f.catEffSevre, f.catEffJeune], [9, 25, 18]);
      },
    );

    test('⚠️⚠️ fiche EN ATTENTE ou EN CONFLIT : ventilation locale intouchable', () async {
      await ficheLocale('p', 1, SyncStatus.pending, mort: 3, mR: 1, mS: 2, mJ: 0);
      await ficheLocale('c', 2, SyncStatus.conflict, mort: 1, mR: 1, mS: 0, mJ: 0);
      serveur.refus[_uuid('p')] = _motifIncoherent;
      serveur.tirage = {
        'livestock_daily_entries': [
          servie('p', '2026-10-01', {'mort_repro': 9, 'mort_sevre': 9, 'mort_jeune': 9}),
          servie('c', '2026-10-02', {'mort_repro': 8, 'mort_sevre': 8, 'mort_jeune': 8}),
        ],
      };
      await moteur().synchroniser();
      final p = await fiche('p');
      final c = await fiche('c');
      expect([p.mortRepro, p.mortSevre, p.mortJeune], [1, 2, 0]);
      expect([c.mortRepro, c.mortSevre, c.mortJeune], [1, 0, 0]);
    });

    test('nombres servis en chaîne (MySQL) acceptés', () async {
      serveur.tirage = {
        'livestock_daily_entries': [
          servie('a', '2026-10-01', {'mort_sevre': '3', 'cat_eff_jeune': '40'}),
        ],
      };
      await moteur().synchroniser();
      final f = await fiche('a');
      expect([f.mortSevre, f.catEffJeune], [3, 40]);
    });

    final casses = <String, Object>{
      'mort_repro négatif': {'mort_repro': -1},
      'cat_eff_sevre fractionnaire': {'cat_eff_sevre': 2.5},
      'passage NaN (chaîne)': {'passage_sevre_jeune': 'NaN'},
      'passage NaN (nombre)': {'passage_sevre_jeune': double.nan},
      'départ infini': {'cat_depart_jeune': double.infinity},
      'effectif_m illisible': {'effectif_m': 'onze'},
      'don_jeune décimal en chaîne': {'don_jeune': '1.5'},
      'cat_eff_4 négatif en chaîne': {'cat_eff_4': '-2'},
    };
    for (final MapEntry(key: nom, value: v) in casses.entries) {
      test('refus STRICT du lot : $nom (rien écrit, curseur bloqué)', () async {
        await ficheLocale('l', 9, SyncStatus.synced, mR: 4, mS: 0, mJ: 0, mort: 4);
        serveur.tirage = {
          'livestock_daily_entries': [
            servie('ok', '2026-10-01', {'mort_repro': 0}),
            servie('casse', '2026-10-02', v as Map<String, Object?>),
          ],
        };
        await expectLater(moteur().synchroniser(), throwsA(isA<FormatException>()));
        final toutes = await db.select(db.livestockDailyEntries).get();
        expect(toutes.map((f) => f.id), [_uuid('l')]);
        expect(toutes.single.mortRepro, 4);
        expect((await db.etatDeSynchronisation())?.lastPulledAt, isNull);
        expect(
          await (db.select(db.appSettings)
                ..where((t) => t.key.equals(SyncEngine.cleFichesResyncCategories)))
              .getSingleOrNull(),
          isNull,
        );
      });
    }
  });

  group('resynchronisation unique `fiches_resync_f095`', () {
    test(
      '⚠️⚠️ un poste en v37 redemande TOUT une fois, puis reprend l incrémental',
      () async {
        await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
        await resyncDejaFaites();
        // Fiche absorbée en v37 : aucune colonne d'effectif par catégorie.
        await ficheLocale('ancienne', 1, SyncStatus.synced);
        serveur.tirage = {
          'livestock_daily_entries': [
            servie('ancienne', '2026-10-01', {'cat_eff_repro': 10, 'cat_eff_sevre': 20, 'cat_eff_jeune': 30}),
          ],
        };

        await moteur().synchroniser();
        await moteur().synchroniser();

        expect(serveur.demandes.first, isNull, reason: 'sans since, une fois');
        expect(serveur.demandes.last, isNotNull, reason: 'puis incrémental');
        final f = await fiche('ancienne');
        expect([f.catEffRepro, f.catEffSevre, f.catEffJeune], [10, 20, 30]);
      },
    );

    test(
      '⚠️ serveur antérieur à 15.39 (ventilation non servie) : la resynchronisation N EST PAS marquée faite',
      () async {
        await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
        await resyncDejaFaites();
        final ancien = servie('a', '2026-10-01');
        for (final c in SyncEngine.colonnesVentilation) {
          ancien.remove(c);
        }
        serveur.tirage = {
          'livestock_daily_entries': [ancien],
        };

        await moteur().synchroniser();
        await moteur().synchroniser();

        expect(serveur.demandes, [null, null]);
      },
    );

    test('ferme sans fiche : marquée faite (rien à rapporter)', () async {
      await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
      await resyncDejaFaites();
      await moteur().synchroniser();
      await moteur().synchroniser();
      expect(serveur.demandes.first, isNull);
      expect(serveur.demandes.last, isNotNull);
    });
  });

  group('envoi (`_ficheEnJson`, contrat 15.40)', () {
    test(
      '⚠️⚠️ ventilation, passage et départ partent ; JAMAIS `effectif_final` ni `cat_eff_*`',
      () async {
        await ficheLocale(
          'tete',
          1,
          SyncStatus.pending,
          mort: 3,
          don: 1,
          mR: 1,
          mS: 2,
          mJ: 0,
          dR: 0,
          dS: 1,
          dJ: 0,
          passage: 4,
          depart: (10, 20, 30),
          categories: (9, 13, 34),
          effectif: 56,
        );
        await moteur().synchroniser();

        final e = fichesEnvoyees().single;
        expect(e.containsKey('effectif_final'), isFalse);
        for (final c in ['cat_eff_repro', 'cat_eff_sevre', 'cat_eff_jeune', 'cat_eff_4']) {
          expect(e.containsKey(c), isFalse, reason: c);
        }
        expect(
          [e['mort_repro'], e['mort_sevre'], e['mort_jeune'], e['mort']],
          [1, 2, 0, 3],
        );
        expect([e['don_repro'], e['don_sevre'], e['don_jeune'], e['don']], [0, 1, 0, 1]);
        expect(e['passage_sevre_jeune'], 4);
        expect(
          [e['cat_depart_repro'], e['cat_depart_sevre'], e['cat_depart_jeune']],
          [10, 20, 30],
        );
        expect((await fiche('tete')).syncStatus, SyncStatus.synced);
      },
    );

    test('`mort` = somme des `mort_*`, `don` = somme des `don_*` (ventilation complète)', () async {
      // Total local contradictoire (donnée abîmée) : c'est la somme qui part.
      await ficheLocale('a', 1, SyncStatus.pending, mort: 9, don: 9, mR: 1, mS: 1, mJ: 1, dR: 2, dS: 0, dJ: 0);
      await moteur().synchroniser();
      final e = fichesEnvoyees().single;
      expect([e['mort'], e['don']], [3, 2]);
    });

    test('ventilation inconnue (null) : la clé ne part pas, le total stocké part', () async {
      await ficheLocale('a', 1, SyncStatus.pending, mort: 4, don: 2, mR: 4, mS: null, mJ: 0);
      await moteur().synchroniser();
      final e = fichesEnvoyees().single;
      expect(e['mort'], 4);
      expect(e['don'], 2);
      expect(e.containsKey('mort_sevre'), isFalse);
      expect(e['mort_repro'], 4, reason: 'partielle : le serveur la refusera, motif visible');
      for (final c in ['don_repro', 'don_sevre', 'don_jeune', 'passage_sevre_jeune', 'effectif_m']) {
        expect(e.containsKey(c), isFalse, reason: c);
      }
    });

    test(
      '⚠️ le départ ne part QU AVEC la fiche tête ; un départ postérieur ne part pas',
      () async {
        await ficheLocale('tete', 1, SyncStatus.synced, depart: (10, 20, 30));
        await ficheLocale('j3', 3, SyncStatus.pending, depart: (1, 1, 1));
        await moteur().synchroniser();
        final e = fichesEnvoyees().single;
        expect(e['id'], _uuid('j3'));
        for (final c in ['cat_depart_repro', 'cat_depart_sevre', 'cat_depart_jeune']) {
          expect(e.containsKey(c), isFalse, reason: c);
        }
      },
    );

    test('`effectif_m/f/sevres/smeres` partent seulement connus', () async {
      await ficheLocale('a', 1, SyncStatus.pending, effectifM: 7);
      await moteur().synchroniser();
      final e = fichesEnvoyees().single;
      expect(e['effectif_m'], 7);
      expect(e.containsKey('effectif_f'), isFalse);
    });

    test(
      '⚠️⚠️ le formulaire actuel (totaux seuls) : un total qui contredit la ventilation la rend INCONNUE — jamais la somme périmée à la place du total saisi',
      () async {
        await ficheLocale('w', 1, SyncStatus.synced, mort: 3, mR: 1, mS: 2, mJ: 0, dR: 0, dS: 0, dJ: 0);
        final depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
        await depot.enregistrer(
          lotId: bande,
          jour: DateTime(2026, 10, 1),
          achat: 0,
          ne: 0,
          mort: 5,
          don: 0,
        );
        final f = await fiche('w');
        expect([f.mortRepro, f.mortSevre, f.mortJeune], [null, null, null]);
        expect([f.donRepro, f.donSevre, f.donJeune], [0, 0, 0], reason: 'les dons concordent');

        await moteur().synchroniser();
        final e = fichesEnvoyees().single;
        expect(e['mort'], 5);
        expect(e.containsKey('mort_repro'), isFalse);
      },
    );

    test('le même total ne touche pas la ventilation', () async {
      await ficheLocale('w', 1, SyncStatus.synced, mort: 3, mR: 1, mS: 2, mJ: 0);
      await FicheJournaliereRepository(database: db, deviceId: 'poste-test').enregistrer(
        lotId: bande,
        jour: DateTime(2026, 10, 1),
        achat: 0,
        ne: 0,
        mort: 3,
        don: 0,
      );
      final f = await fiche('w');
      expect([f.mortRepro, f.mortSevre, f.mortJeune], [1, 2, 0]);
    });

    final motifs = {
      'D7 (morts non ventilés sur une bande à chaîne)': _motifD7,
      'D4 (départ déjà fixé)': _motifDepartFixe,
      'total ≠ somme de la ventilation': _motifIncoherent,
      'passage de stade trop grand (D3)': _motifPassage,
    };
    for (final MapEntry(key: nom, value: motif) in motifs.entries) {
      test('⚠️⚠️ refus $nom : `conflict` avec le motif MOT POUR MOT, puis relance', () async {
        await ficheLocale('r', 2, SyncStatus.pending, mort: 3, mR: 1, mS: 2, mJ: 0);
        serveur.refus[_uuid('r')] = motif;
        final m = moteur();
        final resultat = await m.synchroniser();

        expect((await fiche('r')).syncStatus, SyncStatus.conflict);
        final conflit = (await m.conflits()).single;
        expect(conflit.reason, motif);
        expect(resultat.motifs, contains(motif));
        expect(await db.pendingCount(), 1, reason: 'le conflit reste compté, une fois');

        // Plus envoyé tant qu'il n'est pas relancé.
        serveur.refus.clear();
        await m.synchroniser();
        expect(serveur.envois, hasLength(1));

        await m.relancer(conflit);
        expect((await fiche('r')).syncStatus, SyncStatus.pending);
        await m.synchroniser();
        expect((await fiche('r')).syncStatus, SyncStatus.synced);
        expect(await m.conflits(), isEmpty);
        expect(await db.pendingCount(), 0);
      });
    }

    test(
      'la fiche D IDENTITÉ de F0.90 reste {id, lot_id, entry_date}, même ventilée',
      () async {
        await ficheLocale('jour', 1, SyncStatus.synced, mort: 3, mR: 1, mS: 2, mJ: 0, depart: (10, 20, 30));
        final produit = _uuid('produit');
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                id: produit,
                sku: 'LAP',
                name: 'Lapin',
                unit: 'u',
                pricingMode: 'fixe',
              ),
            );
        await db
            .into(db.sales)
            .insert(
              SalesCompanion.insert(
                id: _uuid('vente'),
                deviceId: 'poste-test',
                syncStatus: const Value(SyncStatus.pending),
                updatedAt: DateTime(2026, 10, 14),
                paymentMode: 'especes',
                total: 3000,
                soldAt: DateTime(2026, 10, 1, 10),
              ),
            );
        await db
            .into(db.saleLines)
            .insert(
              SaleLinesCompanion.insert(
                id: _uuid('ligne'),
                saleId: _uuid('vente'),
                productId: produit,
                lotId: Value(bande),
                qty: 1,
                unitPrice: 3000,
                manualTotalAmount: 3000,
              ),
            );
        await moteur().synchroniser();
        expect(fichesEnvoyees().single.keys.toSet(), {'id', 'lot_id', 'entry_date'});
      },
    );
  });

  test(
    'les motifs du modèle de serveur sont ceux du VRAI `MotifsRefusPush` (PHP exécuté)',
    () {
      final php = executerPhp(r'''<?php
require 'vendor/autoload.php';
echo json_encode([
    App\Support\MotifsRefusPush::ficheNonVentilee('morts'),
    App\Support\MotifsRefusPush::departDejaFixe('01/10/2026'),
    App\Support\MotifsRefusPush::ventilationIncoherente('morts', 5, 3),
    App\Services\EffectifParCategorieService::calculerJour('lapins', ['repro' => 10, 'sevre' => 20, 'jeune' => 30],
        ['achat' => 0, 'ne' => 0, 'vente' => 0, 'mort_repro' => 0, 'mort_sevre' => 0, 'mort_jeune' => 0,
         'don_repro' => 0, 'don_sevre' => 0, 'don_jeune' => 0, 'passage' => 25])->refus,
]);
''', null);
      expect(php, [_motifD7, _motifDepartFixe, _motifIncoherent, _motifPassage]);
    },
    skip: sautSansPhp(),
  );
}
