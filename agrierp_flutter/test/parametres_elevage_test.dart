import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/widgets/modale_agri.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/elevage/parametres_elevage_repository.dart';
import 'package:agrierp/features/elevage/parametres_elevage_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Tickets F0.44, H9 et H9b (poste) — PARAMÈTRES ÉLEVAGE, MODIFIABLES AU POSTE COMME AU WEB.
///
/// 🔴 Avant H9b : quatre onglets en lecture seule, parce que le serveur ignorait tout envoi (référentiels
/// « le serveur a toujours raison »). Décision client D-H9 (19/10/2026) : « Paramètres Élevage modifiables sur
/// le poste et le web ». Le serveur accepte depuis `RecordParametresElevageFromDeviceAction` (droit
/// `manage-elevage`, validations du composant web, archivage logique, dernier écrivain gagne).
///
/// Ce fichier verrouille le DÉPÔT (tris et formats du web, écritures `pending`), le MOTEUR (absorbeurs stricts
/// qui n'écrasent jamais une saisie locale, sérialisation, acquittement, refus, relance) et le COMPORTEMENT de
/// l'écran. Les libellés, colonnes et messages sont confrontés au Blade par `parametres_elevage_blade_test.dart`.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Serveur feint : sert [tirage], accepte tout envoi des Paramètres Élevage (ou le refuse avec [refus]).
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-19T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];
  String? refus;

  /// Saisie faite PENDANT l'envoi (le poste reste utilisable).
  Future<void> Function()? pendantEnvoi;

  static const cles = [
    'feed_ration_standards',
    'prophylaxis_schedule_standards',
    'feed_types',
    'elevage_numbering',
    'company_settings',
  ];

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      await pendantEnvoi?.call();
      Map<String, dynamic> reponse(String cle) {
        final ids = [
          for (final e in corps[cle] as List? ?? const [])
            (e as Map)['id'] as String,
        ];
        return refus == null
            ? {'accepted': ids, 'rejected': <Object>[]}
            : {
                'accepted': <String>[],
                'rejected': [
                  for (final id in ids) {'id': id, 'reason': refus},
                ],
              };
      }

      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final c in cles)
              if (corps.containsKey(c)) c: reponse(c),
          },
        ),
      );
      return;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: tirage,
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late ParametresElevageRepository depot;
  late _Serveur serveur;
  late SyncEngine moteur;
  var horloge = DateTime(2026, 10, 19, 10);

  String uuid(String graine) =>
      '${graine.padRight(8, '0').substring(0, 8)}-0000-4000-8000-000000000000';

  const especeLapins = 'eeeeeeee-0000-4000-8000-000000000001';
  const especePorcs = 'eeeeeeee-0000-4000-8000-000000000002';

  setUp(() async {
    horloge = DateTime(2026, 10, 19, 10);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ParametresElevageRepository(
      database: db,
      maintenant: () => horloge,
    );
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
    );
    for (final (id, code, label) in [
      (especePorcs, 'porciculture', 'Porciculture (Porcs)'),
      (especeLapins, 'cuniculture', 'Cuniculture (Lapins)'),
    ]) {
      await db
          .into(db.livestockSpecies)
          .insert(
            LivestockSpeciesCompanion.insert(id: id, code: code, label: label),
          );
    }
  });

  tearDown(() async => db.close());

  Future<void> ration(
    String cle, {
    required String espece,
    required String stade,
    required double grammes,
    bool actif = true,
    SyncStatus statut = SyncStatus.synced,
  }) => db
      .into(db.feedRationStandards)
      .insert(
        FeedRationStandardsCompanion.insert(
          id: uuid(cle),
          speciesCode: espece,
          stageLabel: stade,
          rationGPerDay: grammes,
          isActive: Value(actif),
          syncStatus: Value(statut),
        ),
      );

  Future<void> prophylaxie(
    String cle, {
    required String espece,
    required String periode,
    required String traitement,
    int? jourDebut,
    DateTime? creee,
    String? produit,
    String? posologie,
    int remanence = 0,
  }) => db
      .into(db.prophylaxisScheduleStandards)
      .insert(
        ProphylaxisScheduleStandardsCompanion.insert(
          id: uuid(cle),
          speciesCode: espece,
          periodLabel: periode,
          treatment: traitement,
          cycleDayStart: Value(jourDebut),
          cycleDayEnd: Value(jourDebut),
          productRecommended: Value(produit),
          dosage: Value(posologie),
          withdrawalDays: Value(remanence),
          createdAt: Value(creee),
        ),
      );

  Future<void> provende(
    String cle, {
    required String nom,
    String? especeId,
    String? espece,
    double? sacKg,
    double? prixKg,
  }) => db
      .into(db.feedTypes)
      .insert(
        FeedTypesCompanion.insert(
          id: uuid(cle),
          name: nom,
          speciesId: Value(especeId),
          speciesLabel: Value(espece),
          standardBagWeightKg: Value(sacKg),
          pricePerKg: Value(prixKg),
        ),
      );

  Future<void> numerotation({SyncStatus statut = SyncStatus.synced}) => db
      .into(db.elevageNumberingSettings)
      .insert(
        ElevageNumberingSettingsCompanion.insert(
          bandeFormat: const Value('BANDE B'),
          lapinePrefix: const Value('R'),
          malePrefix: const Value('M'),
          truiePrefix: const Value('T'),
          verratPrefix: const Value('V'),
          porteePrefix: const Value('P'),
          volaillePrefix: const Value('LOT-VOL'),
          parcPrefix: const Value('PARC'),
          escargotPrefix: const Value('FOSSE'),
          syncStatus: Value(statut),
        ),
      );

  // ══ 1. Le dépôt : tris et formats du web (H9) ═══════════════════════════════════════════════════════

  group('dépôt — lecture', () {
    test(
      'les rations se trient par espèce puis par grammage (orderBy ration_g_per_day du web)',
      () async {
        await ration(
          'r1',
          espece: 'cuniculture',
          stade: 'Allaitante',
          grammes: 250,
        );
        await ration('r2', espece: 'aviculture', stade: 'Ponte', grammes: 110);
        await ration('r3', espece: 'cuniculture', stade: 'Sevré', grammes: 30);

        final d = await depot.charger();

        expect(d.rations.map((r) => r.ration.stageLabel), [
          'Ponte',
          'Sevré',
          'Allaitante',
        ]);
      },
    );

    test(
      'le calendrier se trie sur created_at comme le web, le jour de cycle départage',
      () async {
        await prophylaxie(
          'p1',
          espece: 'cuniculture',
          periode: 'Le 5e jour',
          traitement: 'Vaccination',
          jourDebut: 5,
          creee: DateTime(2026, 10, 2),
        );
        await prophylaxie(
          'p2',
          espece: 'cuniculture',
          periode: 'Le 10e jour',
          traitement: 'Rappel',
          jourDebut: 10,
          creee: DateTime(2026, 10, 1),
        );
        await prophylaxie(
          'p3',
          espece: 'cuniculture',
          periode: 'J3',
          traitement: 'Vitamines',
          jourDebut: 3,
          creee: DateTime(2026, 10, 2),
        );

        final d = await depot.charger();

        expect(
          d
              .prophylaxiePour(EspeceProphylaxie.lapins)
              .map((p) => p.entree.periodLabel),
          ['Le 10e jour', 'J3', 'Le 5e jour'],
        );
      },
    );

    test(
      'les provendes se trient par nom, sans tenir compte de la casse ni des accents',
      () async {
        // Par points de code : « Aliment porc », « Farine », « aliment ponte », « Éleveur lapin ».
        await provende('t1', nom: 'Farine');
        await provende('t2', nom: 'Aliment porc');
        await provende('t3', nom: 'Éleveur lapin');
        await provende('t4', nom: 'aliment ponte');

        final d = await depot.charger();

        expect(d.provendes.map((p) => p.type.name), [
          'aliment ponte',
          'Aliment porc',
          'Éleveur lapin',
          'Farine',
        ]);
      },
    );

    test(
      '⚠️ une ligne archivée (is_active = false) ne s affiche plus',
      () async {
        await ration('r1', espece: 'aviculture', stade: 'Ponte', grammes: 110);
        await ration(
          'r2',
          espece: 'aviculture',
          stade: 'Démarrage',
          grammes: 30,
          actif: false,
        );

        final d = await depot.charger();

        expect(d.rations.map((r) => r.ration.stageLabel), ['Ponte']);
      },
    );

    test(
      '⚠️ une entrée sans bornes de cycle est reconnue comme telle',
      () async {
        await prophylaxie(
          'p1',
          espece: 'aviculture',
          periode: 'Le 1er du mois',
          traitement: 'Déparasitage',
        );

        final d = await depot.charger();

        expect(d.prophylaxies.single.porteeParLeCycle, isFalse);
      },
    );

    test(
      'les espèces de la provende sont celles du référentiel, par libellé',
      () async {
        final d = await depot.charger();

        expect(d.especesProvende.map((e) => e.libelle), [
          'Cuniculture (Lapins)',
          'Porciculture (Porcs)',
        ]);
      },
    );

    test('formats du Blade : grammes, sac, prix', () {
      expect(ParametresElevageRepository.grammes(30), '30 g');
      // `rtrim(rtrim(number_format($kg, 2, '.', ''), '0'), '.') . ' Kg'`
      expect(ParametresElevageRepository.sac(25), '25 Kg');
      expect(ParametresElevageRepository.sac(12.5), '12.5 Kg');
      expect(ParametresElevageRepository.sac(12.25), '12.25 Kg');
      expect(ParametresElevageRepository.sac(null), '—');
      // `number_format($prix, 0, ',', ' ') . ' FCFA'` — arrondi demi loin de zéro.
      expect(ParametresElevageRepository.prix(260), '260 FCFA');
      expect(ParametresElevageRepository.prix(1250), '1 250 FCFA');
      expect(ParametresElevageRepository.prix(1250.5), '1 251 FCFA');
      expect(ParametresElevageRepository.prix(null), '—');
    });

    /// ⚠️ Sans tirage, préfixes et délai valent `null` — pas « R » ni « 3 » par défaut.
    test(
      '⚠️ préfixes et délai de rappel sont nuls tant que rien n a été tiré',
      () async {
        final d = await depot.charger();

        expect(d.numerotation, isNull);
        expect(d.rappelSoinsJours, isNull);
      },
    );

    test('le code espèce devient un libellé lisible', () {
      expect(
        ParametresElevageRepository.especeLisible('cuniculture'),
        'Cuniculture',
      );
      expect(
        ParametresElevageRepository.especeLisible('heliciculture'),
        'Héliciculture',
      );
    });
  });

  // ══ 2. Le dépôt : écritures en attente (H9b) ════════════════════════════════════════════════════════

  group('dépôt — écritures', () {
    test(
      'créer une ration l écrit en pending, active, à l instant de la saisie',
      () async {
        final id = await depot.enregistrerRation(
          espece: 'cuniculture',
          stade: ' Jeune ',
          grammes: 60,
        );

        final r = await db.select(db.feedRationStandards).getSingle();
        expect(id, hasLength(36));
        expect(
          [
            r.id,
            r.speciesCode,
            r.stageLabel,
            r.rationGPerDay,
            r.isActive,
            r.syncStatus,
            r.updatedAt,
          ],
          [
            id,
            'cuniculture',
            'Jeune',
            60.0,
            true,
            SyncStatus.pending,
            DateTime(2026, 10, 19, 10),
          ],
        );
      },
    );

    test('modifier une ration garde son identifiant', () async {
      await ration('r1', espece: 'cuniculture', stade: 'Jeune', grammes: 60);

      await depot.enregistrerRation(
        id: uuid('r1'),
        espece: 'cuniculture',
        stade: 'Jeune',
        grammes: 65,
      );

      final r = await db.select(db.feedRationStandards).getSingle();
      expect(
        [r.id, r.rationGPerDay, r.syncStatus],
        [uuid('r1'), 65.0, SyncStatus.pending],
      );
    });

    test(
      '⚠️⚠️ supprimer = ARCHIVER : la ligne reste, inactive et en attente',
      () async {
        await ration('r1', espece: 'cuniculture', stade: 'Jeune', grammes: 60);

        await depot.archiverRation(uuid('r1'));

        final r = await db.select(db.feedRationStandards).getSingle();
        expect([r.isActive, r.syncStatus], [false, SyncStatus.pending]);
        expect((await depot.charger()).rations, isEmpty);
      },
    );

    test(
      'une échéance modifiée garde sa place (created_at) et ses bornes de cycle',
      () async {
        await prophylaxie(
          'p1',
          espece: 'porciculture',
          periode: 'J+21',
          traitement: 'Vermifuge',
          jourDebut: 21,
          creee: DateTime(2026, 9, 1),
        );

        await depot.enregistrerEcheance(
          id: uuid('p1'),
          espece: 'porciculture',
          periode: 'J+21',
          traitement: 'Vermifuge',
          produit: 'Ivermectine',
          dose: '1 ml / 33 kg',
          remanence: 14,
        );

        final p = await db.select(db.prophylaxisScheduleStandards).getSingle();
        expect(
          [
            p.createdAt,
            p.cycleDayStart,
            p.productRecommended,
            p.withdrawalDays,
            p.syncStatus,
          ],
          [DateTime(2026, 9, 1), 21, 'Ivermectine', 14, SyncStatus.pending],
        );
      },
    );

    test(
      'une provende garde l identifiant, le code et le libellé de son espèce',
      () async {
        final especes = (await depot.charger()).especesProvende;
        await depot.enregistrerProvende(
          nom: 'Aliment porc croissance',
          espece: especes.firstWhere((e) => e.code == 'porciculture'),
          sacKg: 50,
          prixKg: 320,
        );

        final t = await db.select(db.feedTypes).getSingle();
        expect(
          [
            t.speciesId,
            t.speciesCode,
            t.speciesLabel,
            t.standardBagWeightKg,
            t.pricePerKg,
            t.syncStatus,
          ],
          [
            especePorcs,
            'porciculture',
            'Porciculture (Porcs)',
            50.0,
            320.0,
            SyncStatus.pending,
          ],
        );
      },
    );

    test(
      'le délai de rappel s écrit seul : l identité de la ferme n est pas touchée',
      () async {
        await db
            .into(db.companySettings)
            .insert(
              CompanySettingsCompanion.insert(
                companyName: const Value('Ferme École OLOUWACHEGOUN'),
                rappelSoinsJours: const Value(3),
              ),
            );

        await depot.enregistrerRappelSoins(5);

        final e = await db.select(db.companySettings).getSingle();
        expect(
          [e.companyName, e.rappelSoinsJours, e.syncStatus],
          ['Ferme École OLOUWACHEGOUN', 5, SyncStatus.pending],
        );
      },
    );

    test('validations du composant web, messages du serveur', () {
      expect(
        ParametresElevageRepository.erreursRation(
          espece: 'aviculture',
          stade: '',
          grammes: '0',
        ),
        [
          "Le champ Stade Physiologique / Tranche d'Âge est obligatoire.",
          'Le champ Ration Normative (g/tête/jour) est inférieur au minimum autorisé (1).',
        ],
      );
      expect(
        ParametresElevageRepository.erreursRation(
          espece: 'heliciculture',
          stade: 'Naissain',
          grammes: '5',
        ),
        ['Le champ Espèce est obligatoire.'],
      );
      expect(
        ParametresElevageRepository.erreursEcheance(
          periode: 'J+14',
          traitement: 'x' * 151,
          produit: 'P',
          dose: 'D',
          remanence: '0',
        ),
        ['Le champ Traitement Prévu dépasse le maximum autorisé (150).'],
      );
      expect(ParametresElevageRepository.erreursRappelSoins('31'), [
        'Le champ délai de rappel dépasse le maximum autorisé (30).',
      ]);
      expect(ParametresElevageRepository.erreursRappelSoins('0'), isEmpty);
      expect(
        ParametresElevageRepository.erreursProvende(
          nom: 'Aliment',
          especeId: null,
          especes: const [],
          sac: '0',
          prix: '250',
        ),
        [
          'Le champ Espèce Cible est obligatoire.',
          'Le champ Poids Sac Standard (Kg) est inférieur au minimum autorisé (0.01).',
        ],
      );
    });
  });

  // ══ 3. Le moteur : tirage strict ════════════════════════════════════════════════════════════════════

  Map<String, dynamic> tirageComplet() => {
    'server_time': '2026-10-19T12:00:00Z',
    'feed_ration_standards': [
      {
        'id': uuid('r1'),
        'species_code': 'cuniculture',
        'stage_label': 'Jeune',
        'ration_g_per_day': 60,
        'is_active': true,
      },
    ],
    'prophylaxis_schedule_standards': [
      {
        'id': uuid('p1'),
        'species_code': 'porciculture',
        'period_label': 'J+21',
        'cycle_day_start': 21,
        'cycle_day_end': 21,
        'treatment': 'Vermifuge',
        'product_recommended': 'Ivermectine',
        'dosage': '1 ml / 33 kg',
        'withdrawal_days': 14,
        'is_active': true,
        'created_at': '2026-10-01T08:00:00.000000Z',
      },
    ],
    'feed_types': [
      {
        'id': uuid('t1'),
        'name': 'Aliment porc croissance',
        'species_id': especePorcs,
        'species_code': 'porciculture',
        'species_label': 'Porciculture (Porcs)',
        'standard_bag_weight_kg': '50.00',
        'price_per_kg': '320.00',
      },
    ],
    'elevage_numbering': {
      'bande_format': 'LOT',
      'lapine_prefix': 'L',
      'male_prefix': 'M',
      'truie_prefix': 'T',
      'verrat_prefix': 'V',
      'portee_prefix': 'P',
      'volaille_prefix': 'VOL',
      'parc_prefix': 'PARC',
      'escargot_prefix': 'ESC',
    },
    'company_settings': {
      'company_name': 'Ferme École OLOUWACHEGOUN',
      'tva_enabled': false,
      'rappel_soins_jours': 5,
    },
  };

  group('moteur — tirage', () {
    test(
      'le tirage absorbe les cinq paramètres, tous synced, rien en attente',
      () async {
        serveur.tirage = tirageComplet();

        await moteur.synchroniser();

        final r = await db.select(db.feedRationStandards).getSingle();
        expect(
          [r.rationGPerDay, r.isActive, r.syncStatus],
          [60.0, true, SyncStatus.synced],
        );
        final p = await db.select(db.prophylaxisScheduleStandards).getSingle();
        expect(
          [p.withdrawalDays, p.cycleDayStart, p.createdAt!.toUtc()],
          [14, 21, DateTime.utc(2026, 10, 1, 8)],
        );
        final t = await db.select(db.feedTypes).getSingle();
        expect(
          [t.standardBagWeightKg, t.pricePerKg, t.speciesLabel],
          [50.0, 320.0, 'Porciculture (Porcs)'],
        );
        expect(
          (await db.select(db.elevageNumberingSettings).getSingle())
              .lapinePrefix,
          'L',
        );
        expect(
          (await db.select(db.companySettings).getSingle()).rappelSoinsJours,
          5,
        );
        expect(await db.pendingCount(), 0);
      },
    );

    test(
      '⚠️⚠️ STRICT : une saisie locale pending ou refusée n est jamais écrasée',
      () async {
        await ration(
          'r1',
          espece: 'cuniculture',
          stade: 'Jeune',
          grammes: 65,
          statut: SyncStatus.pending,
        );
        await prophylaxie(
          'p1',
          espece: 'porciculture',
          periode: 'J+21',
          traitement: 'Vermifuge corrigé',
        );
        await (db.update(db.prophylaxisScheduleStandards)).write(
          const ProphylaxisScheduleStandardsCompanion(
            syncStatus: Value(SyncStatus.conflict),
          ),
        );
        await numerotation(statut: SyncStatus.pending);
        await db
            .into(db.companySettings)
            .insert(
              CompanySettingsCompanion.insert(
                companyName: const Value('Ancien nom'),
                rappelSoinsJours: const Value(9),
                syncStatus: const Value(SyncStatus.pending),
              ),
            );
        serveur.tirage = tirageComplet();
        // Seul le tirage est éprouvé ici : l'envoi est refusé, rien n'est acquitté.
        serveur.refus = 'Refus de test.';

        await moteur.synchroniser();

        final r = await db.select(db.feedRationStandards).getSingle();
        expect(r.rationGPerDay, 65.0);
        final p = await db.select(db.prophylaxisScheduleStandards).getSingle();
        expect(p.treatment, 'Vermifuge corrigé');
        expect(
          (await db.select(db.elevageNumberingSettings).getSingle())
              .lapinePrefix,
          'R',
        );
        final e = await db.select(db.companySettings).getSingle();
        // L'identité se met à jour ; le délai saisi ici, non.
        expect(
          [e.companyName, e.rappelSoinsJours],
          ['Ferme École OLOUWACHEGOUN', 9],
        );
      },
    );

    test(
      '⚠️ une ligne synced que le serveur ne sert plus a été archivée ailleurs : archivée ici aussi',
      () async {
        await ration('r9', espece: 'aviculture', stade: 'Ponte', grammes: 110);
        serveur.tirage = tirageComplet();

        await moteur.synchroniser();

        final r9 = await (db.select(
          db.feedRationStandards,
        )..where((t) => t.id.equals(uuid('r9')))).getSingle();
        expect(r9.isActive, isFalse);
        expect((await depot.charger()).rations.map((r) => r.ration.id), [
          uuid('r1'),
        ]);
      },
    );

    test(
      '⚠️⚠️ STRICT : une ligne incohérente refuse tout le lot, rien n est écrit',
      () async {
        await ration('r9', espece: 'aviculture', stade: 'Ponte', grammes: 110);
        serveur.tirage = {
          ...tirageComplet(),
          'feed_ration_standards': [
            {
              'id': uuid('r1'),
              'species_code': 'cuniculture',
              'stage_label': 'Jeune',
              'ration_g_per_day': 60,
            },
            {
              'id': uuid('r2'),
              'species_code': 'cuniculture',
              'stage_label': 'Adulte',
              'ration_g_per_day': 'beaucoup',
            },
          ],
        };

        await expectLater(
          moteur.synchroniser(),
          throwsA(isA<FormatException>()),
        );

        final r = await db.select(db.feedRationStandards).get();
        expect(r.map((x) => [x.id, x.isActive]), [
          [uuid('r9'), true],
        ]);
      },
    );

    test(
      '⚠️ STRICT : un délai de rappel hors de 0..30 refuse la ligne de l entreprise',
      () async {
        serveur.tirage = {
          ...tirageComplet(),
          'company_settings': {'company_name': 'X', 'rappel_soins_jours': 45},
        };

        await expectLater(
          moteur.synchroniser(),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  // ══ 4. Le moteur : envoi, acquittement, refus, relance ══════════════════════════════════════════════

  Future<void> toutSaisir() async {
    await depot.enregistrerRation(
      id: uuid('r1'),
      espece: 'cuniculture',
      stade: 'Jeune',
      grammes: 60,
    );
    await depot.enregistrerEcheance(
      id: uuid('p1'),
      espece: 'porciculture',
      periode: 'J+21',
      traitement: 'Vermifuge',
      produit: 'Ivermectine',
      dose: '1 ml / 33 kg',
      remanence: 14,
    );
    final porcs = (await depot.charger()).especesProvende.firstWhere(
      (e) => e.code == 'porciculture',
    );
    await depot.enregistrerProvende(
      id: uuid('t1'),
      nom: 'Aliment porc croissance',
      espece: porcs,
      sacKg: 50,
      prixKg: 320,
    );
    await depot.enregistrerNumerotation({
      'bande_format': 'LOT',
      'lapine_prefix': 'L',
      'male_prefix': 'M',
      'truie_prefix': 'T',
      'verrat_prefix': 'V',
      'portee_prefix': 'P',
      'volaille_prefix': 'VOL',
      'parc_prefix': 'PARC',
      'escargot_prefix': 'ESC',
    });
    await depot.enregistrerRappelSoins(5);
  }

  group('moteur — envoi', () {
    test(
      'les cinq clés partent au format exact de RecordParametresElevageFromDeviceAction',
      () async {
        await toutSaisir();
        await depot.archiverRation(uuid('r1'));

        await moteur.synchroniser();

        final corps = serveur.envois.single;
        expect(corps['feed_ration_standards'], [
          {
            'id': uuid('r1'),
            'species_code': 'cuniculture',
            'stage_label': 'Jeune',
            'ration_g_per_day': 60,
            'is_active': false,
          },
        ]);
        expect(corps['prophylaxis_schedule_standards'], [
          {
            'id': uuid('p1'),
            'species_code': 'porciculture',
            'period_label': 'J+21',
            'treatment': 'Vermifuge',
            'product_recommended': 'Ivermectine',
            'dosage': '1 ml / 33 kg',
            'withdrawal_days': 14,
            'is_active': true,
          },
        ]);
        expect(corps['feed_types'], [
          {
            'id': uuid('t1'),
            'name': 'Aliment porc croissance',
            'species_id': especePorcs,
            'standard_bag_weight_kg': 50.0,
            'price_per_kg': 320.0,
            'is_active': true,
          },
        ]);
        expect(corps['elevage_numbering'], [
          {
            'id': 'elevage_numbering',
            'bande_format': 'LOT',
            'lapine_prefix': 'L',
            'male_prefix': 'M',
            'truie_prefix': 'T',
            'verrat_prefix': 'V',
            'portee_prefix': 'P',
            'volaille_prefix': 'VOL',
            'parc_prefix': 'PARC',
            'escargot_prefix': 'ESC',
          },
        ]);
        expect(corps['company_settings'], [
          {'id': 'company_settings', 'rappel_soins_jours': 5},
        ]);
      },
    );

    test(
      'les cinq tables comptent « en attente », puis passent synced à l accusé',
      () async {
        await toutSaisir();
        expect(await db.compteursSynchronisation(), (aEnvoyer: 5, refuses: 0));

        await moteur.synchroniser();

        expect(await db.compteursSynchronisation(), (aEnvoyer: 0, refuses: 0));
        expect(
          (await db.select(db.elevageNumberingSettings).getSingle()).syncStatus,
          SyncStatus.synced,
        );
        expect(
          (await db.select(db.companySettings).getSingle()).syncStatus,
          SyncStatus.synced,
        );
      },
    );

    test(
      'un refus passe la ligne en conflit avec le motif MOT POUR MOT, visible à l écran',
      () async {
        await toutSaisir();
        serveur.refus =
            'Le champ ration_g_per_day est inférieur au minimum autorisé (1).';

        final issue = await moteur.synchroniser();

        expect(issue.rejete, 5);
        expect(await db.compteursSynchronisation(), (aEnvoyer: 0, refuses: 5));
        final d = await depot.charger();
        expect(d.rations.single.etat.refuse, isTrue);
        expect(d.rations.single.etat.motifRefus, serveur.refus);
        expect(d.etatNumerotation!.motifRefus, serveur.refus);
        expect(d.etatRappelSoins!.motifRefus, serveur.refus);
      },
    );

    test('« Relancer » remet chaque ligne refusée en file', () async {
      await toutSaisir();
      serveur.refus = 'Refus.';
      await moteur.synchroniser();

      for (final c in await db.select(db.syncConflicts).get()) {
        await moteur.relancer(c);
      }

      expect(await db.compteursSynchronisation(), (aEnvoyer: 5, refuses: 0));
      expect(await db.select(db.syncConflicts).get(), isEmpty);
    });

    test(
      '⚠️⚠️ une ration corrigée PENDANT l envoi reste en attente : seule la version partie est acquittée',
      () async {
        await depot.enregistrerRation(
          id: uuid('r1'),
          espece: 'cuniculture',
          stade: 'Jeune',
          grammes: 60,
        );
        serveur.pendantEnvoi = () async {
          horloge = horloge.add(const Duration(minutes: 1));
          await depot.enregistrerRation(
            id: uuid('r1'),
            espece: 'cuniculture',
            stade: 'Jeune',
            grammes: 70,
          );
        };

        await moteur.synchroniser();

        final r = await db.select(db.feedRationStandards).getSingle();
        expect([r.rationGPerDay, r.syncStatus], [70.0, SyncStatus.pending]);
      },
    );

    test('rien en attente : aucune clé des Paramètres Élevage ne part', () async {
      await depot.enregistrerRation(
        id: uuid('r1'),
        espece: 'cuniculture',
        stade: 'Jeune',
        grammes: 60,
      );
      await moteur.synchroniser();
      serveur.envois.clear();
      // Une autre saisie déclenche un envoi : les clés des barèmes n'y figurent pas.
      await db
          .into(db.livestockLots)
          .insert(
            LivestockLotsCompanion.insert(
              id: uuid('b1'),
              code: 'LOT-1',
              speciesId: especeLapins,
            ),
          );
      await db
          .into(db.livestockDailyEntries)
          .insert(
            LivestockDailyEntriesCompanion.insert(
              id: uuid('f1'),
              deviceId: 'poste-test',
              updatedAt: horloge,
              lotId: uuid('b1'),
              entryDate: DateTime(2026, 10, 19),
            ),
          );

      await moteur.synchroniser();

      expect(serveur.envois, hasLength(1));
      for (final cle in _Serveur.cles) {
        expect(serveur.envois.single.containsKey(cle), isFalse, reason: cle);
      }
    });
  });

  // ══ 5. L'écran ══════════════════════════════════════════════════════════════════════════════════════

  Future<void> afficher(WidgetTester tester, {bool droit = true}) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ParametresElevageScreen(depot: depot, peutModifier: droit),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-parametres-$onglet')));
    await tester.pumpAndSettle();
  }

  Future<void> nettoyer(WidgetTester tester) async {
    ToastAgri.toutRetirer();
    await tester.pumpWidget(const SizedBox());
  }

  group('écran', () {
    testWidgets('les quatre onglets, dans l ordre du Blade', (tester) async {
      await afficher(tester);

      final abscisses = [
        for (final onglet in [
          'Fiche de Rationnement (g/j)',
          'Calendriers de Prophylaxie',
          'Types de Provende',
          'Numérotation Bandes & Sujets',
        ])
          tester.getTopLeft(find.text(onglet)).dx,
      ];
      expect([...abscisses]..sort(), abscisses);
      await nettoyer(tester);
    });

    /// ⚠️⚠️ ZÉRO CARTE EST UN NOMBRE (ticket F0.54) : l'écran de référentiels n'en porte aucune.
    testWidgets('⚠️⚠️ l écran ne rend aucune carte', (tester) async {
      await afficher(tester);

      expect(
        find.byType(CarteKpi),
        findsNWidgets(cartesAttendues('parametres-elevage.html')),
      );
      await nettoyer(tester);
    });

    testWidgets(
      'une ration, une échéance et un type s affichent aux formats du Blade',
      (tester) async {
        await ration(
          'r1',
          espece: 'cuniculture',
          stade: 'Lapine allaitante',
          grammes: 250,
        );
        await prophylaxie(
          'p1',
          espece: 'cuniculture',
          periode: 'J20',
          traitement: 'Antibiotique',
          remanence: 7,
        );
        await prophylaxie(
          'p2',
          espece: 'cuniculture',
          periode: 'J5',
          traitement: 'Vitamines',
        );
        await provende(
          't1',
          nom: 'Aliment Ponte (Pondeuse)',
          espece: 'Aviculture (Volailles)',
          sacKg: 25,
          prixKg: 1250,
        );

        await afficher(tester);
        expect(find.text('Cuniculture'), findsOneWidget);
        expect(find.text('250 g'), findsOneWidget);

        await ouvrir(tester, 'Calendriers de Prophylaxie');
        // ⚠️⚠️ ZÉRO JOUR DE RÉMANENCE SE DIT : « 0 j », jamais un tiret.
        expect(find.text('7 j'), findsOneWidget);
        expect(find.text('0 j'), findsOneWidget);

        await ouvrir(tester, 'Types de Provende');
        expect(find.text('25 Kg'), findsOneWidget);
        expect(find.text('1 250 FCFA'), findsOneWidget);
        await nettoyer(tester);
      },
    );

    testWidgets('changer d espèce change le calendrier affiché', (
      tester,
    ) async {
      await prophylaxie(
        'p1',
        espece: 'cuniculture',
        periode: 'J5 — Lapereaux',
        traitement: 'Vitamines',
      );
      await prophylaxie(
        'p2',
        espece: 'porciculture',
        periode: 'J7 — Porcelets',
        traitement: 'Fer injectable',
      );

      await afficher(tester);
      await ouvrir(tester, 'Calendriers de Prophylaxie');
      expect(find.text('Vitamines'), findsOneWidget);
      expect(find.text('Fer injectable'), findsNothing);

      await tester.tap(find.byKey(const Key('espece-porcs')));
      await tester.pumpAndSettle();

      expect(find.text('Fer injectable'), findsOneWidget);
      expect(find.text('Vitamines'), findsNothing);
      await nettoyer(tester);
    });

    testWidgets('⚠️⚠️ sans le droit manage-elevage, aucun bouton d écriture', (
      tester,
    ) async {
      await ration('r1', espece: 'aviculture', stade: 'Ponte', grammes: 110);
      await numerotation();

      await afficher(tester, droit: false);
      expect(find.byKey(const Key('ajouter-ration')), findsNothing);
      expect(find.byKey(Key('modifier-ration-${uuid('r1')}')), findsNothing);
      expect(find.byKey(Key('supprimer-ration-${uuid('r1')}')), findsNothing);

      await ouvrir(tester, 'Calendriers de Prophylaxie');
      expect(find.byKey(const Key('ajouter-echeance')), findsNothing);
      expect(find.byKey(const Key('rappel-soins-enregistrer')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('rappel-soins')))
            .readOnly,
        isTrue,
      );

      await ouvrir(tester, 'Types de Provende');
      expect(find.byKey(const Key('ajouter-provende')), findsNothing);

      await ouvrir(tester, 'Numérotation Bandes & Sujets');
      expect(find.byKey(const Key('numerotation-enregistrer')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('format-lapine_prefix')))
            .readOnly,
        isTrue,
      );
      await nettoyer(tester);
    });

    testWidgets(
      'ajouter une ration : modale, écriture en attente, pastille « En attente d envoi »',
      (tester) async {
        await afficher(tester);
        await tester.tap(find.byKey(const Key('ajouter-ration')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ModaleAgri>(find.byType(ModaleAgri)).titre,
          'Saisir une Ration',
        );

        // Champs vides : rien n'est écrit, l'erreur est dite.
        await tester.tap(find.byKey(const Key('ration-enregistrer')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ration-erreur')), findsOneWidget);
        expect(await db.select(db.feedRationStandards).get(), isEmpty);

        await tester.tap(find.byKey(const Key('ration-espece')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cuniculture (Lapins)').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('ration-stade')), 'Jeune');
        await tester.enterText(find.byKey(const Key('ration-grammes')), '60');
        await tester.tap(find.byKey(const Key('ration-enregistrer')));
        await tester.pumpAndSettle();

        final r = await db.select(db.feedRationStandards).getSingle();
        expect(
          [r.speciesCode, r.stageLabel, r.rationGPerDay, r.syncStatus],
          ['cuniculture', 'Jeune', 60.0, SyncStatus.pending],
        );
        expect(find.byType(ModaleAgri), findsNothing);
        expect(find.byKey(const Key('toast-succes')), findsOneWidget);
        expect(find.text('60 g'), findsOneWidget);
        expect(find.text("En attente d'envoi"), findsOneWidget);
        await nettoyer(tester);
      },
    );

    testWidgets(
      'modifier une ration : « Modifier la Ration », champs pré-remplis',
      (tester) async {
        await ration(
          'r1',
          espece: 'porciculture',
          stade: 'Truie',
          grammes: 2500,
        );

        await afficher(tester);
        await tester.tap(find.byKey(Key('modifier-ration-${uuid('r1')}')));
        await tester.pumpAndSettle();

        expect(
          tester.widget<ModaleAgri>(find.byType(ModaleAgri)).titre,
          'Modifier la Ration',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('ration-grammes')))
              .controller!
              .text,
          '2500',
        );
        await tester.enterText(find.byKey(const Key('ration-grammes')), '2600');
        await tester.tap(find.byKey(const Key('ration-enregistrer')));
        await tester.pumpAndSettle();

        final r = await db.select(db.feedRationStandards).getSingle();
        expect(
          [r.id, r.speciesCode, r.rationGPerDay],
          [uuid('r1'), 'porciculture', 2600.0],
        );
        await nettoyer(tester);
      },
    );

    testWidgets(
      '⚠️⚠️ supprimer : confirmation, puis ARCHIVAGE — la ligne quitte la liste',
      (tester) async {
        await provende('t1', nom: 'Aliment Ponte', sacKg: 25, prixKg: 250);

        await afficher(tester);
        await ouvrir(tester, 'Types de Provende');
        await tester.tap(find.byKey(Key('supprimer-provende-${uuid('t1')}')));
        await tester.pumpAndSettle();

        expect(find.byType(ModaleConfirmation), findsOneWidget);
        expect(
          find.text(
            'Vous êtes sur le point de supprimer le paramètre Aliment Ponte.',
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(Key('supprimer-confirme-provende-${uuid('t1')}')),
        );
        await tester.pumpAndSettle();

        final t = await db.select(db.feedTypes).getSingle();
        expect([t.isActive, t.syncStatus], [false, SyncStatus.pending]);
        expect(find.text('Aliment Ponte'), findsNothing);
        expect(find.byKey(const Key('toast-avertissement')), findsOneWidget);
        await nettoyer(tester);
      },
    );

    testWidgets(
      'une ligne refusée montre « Refusé par le serveur » et le motif',
      (tester) async {
        await ration(
          'r1',
          espece: 'aviculture',
          stade: 'Ponte',
          grammes: 110,
          statut: SyncStatus.conflict,
        );
        await db
            .into(db.syncConflicts)
            .insert(
              SyncConflictsCompanion.insert(
                id: 'feed_ration_standards:${uuid('r1')}',
                sourceTable: 'feed_ration_standards',
                recordId: uuid('r1'),
                reason: 'Action non autorisée pour votre rôle.',
                detectedAt: horloge,
              ),
            );

        await afficher(tester);

        expect(find.text('Refusé par le serveur'), findsOneWidget);
        expect(
          find.text('Action non autorisée pour votre rôle.'),
          findsOneWidget,
        );
        await nettoyer(tester);
      },
    );

    testWidgets('une échéance ajoutée prend l espèce du sous-onglet ouvert', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Calendriers de Prophylaxie');
      await tester.tap(find.byKey(const Key('espece-volailles')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ajouter-echeance')));
      await tester.pumpAndSettle();

      // `public int $prophy_withdrawal_days = 0;`
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('echeance-remanence')))
            .controller!
            .text,
        '0',
      );
      await tester.enterText(find.byKey(const Key('echeance-periode')), 'J+14');
      await tester.enterText(
        find.byKey(const Key('echeance-traitement')),
        'Vaccination Newcastle',
      );
      await tester.enterText(find.byKey(const Key('echeance-produit')), 'HB1');
      await tester.enterText(
        find.byKey(const Key('echeance-dose')),
        '1 goutte',
      );
      await tester.tap(find.byKey(const Key('echeance-enregistrer')));
      await tester.pumpAndSettle();

      final p = await db.select(db.prophylaxisScheduleStandards).getSingle();
      expect(
        [p.speciesCode, p.withdrawalDays, p.createdAt, p.syncStatus],
        ['aviculture', 0, DateTime(2026, 10, 19, 10), SyncStatus.pending],
      );
      expect(find.text('Vaccination Newcastle'), findsOneWidget);
      await nettoyer(tester);
    });

    testWidgets(
      'un type de provende : espèces du référentiel, 25 kg et 250 FCFA par défaut',
      (tester) async {
        await afficher(tester);
        await ouvrir(tester, 'Types de Provende');
        await tester.tap(find.byKey(const Key('ajouter-provende')));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextField>(find.byKey(const Key('provende-sac')))
              .controller!
              .text,
          '25',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('provende-prix')))
              .controller!
              .text,
          '250',
        );
        await tester.enterText(
          find.byKey(const Key('provende-nom')),
          'Aliment lapin',
        );
        await tester.tap(find.byKey(const Key('provende-espece')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cuniculture (Lapins)').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('provende-enregistrer')));
        await tester.pumpAndSettle();

        final t = await db.select(db.feedTypes).getSingle();
        expect(
          [t.name, t.speciesId, t.standardBagWeightKg, t.pricePerKg],
          ['Aliment lapin', especeLapins, 25.0, 250.0],
        );
        expect(find.text('Cuniculture (Lapins)'), findsOneWidget);
        await nettoyer(tester);
      },
    );

    testWidgets('la numérotation s enregistre ; un champ vide est refusé', (
      tester,
    ) async {
      await numerotation();

      await afficher(tester);
      await ouvrir(tester, 'Numérotation Bandes & Sujets');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('format-lapine_prefix')))
            .controller!
            .text,
        'R',
      );

      await tester.enterText(
        find.byKey(const Key('format-escargot_prefix')),
        '',
      );
      await tester.tap(find.byKey(const Key('numerotation-enregistrer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('numerotation-erreur')), findsOneWidget);
      expect(
        (await db.select(db.elevageNumberingSettings).getSingle()).syncStatus,
        SyncStatus.synced,
      );

      await tester.enterText(
        find.byKey(const Key('format-escargot_prefix')),
        'FOSSE',
      );
      await tester.enterText(
        find.byKey(const Key('format-lapine_prefix')),
        'L',
      );
      await tester.tap(find.byKey(const Key('numerotation-enregistrer')));
      await tester.pumpAndSettle();

      final n = await db.select(db.elevageNumberingSettings).getSingle();
      expect(
        [n.lapinePrefix, n.escargotPrefix, n.syncStatus],
        ['L', 'FOSSE', SyncStatus.pending],
      );
      expect(find.byKey(const Key('toast-succes')), findsOneWidget);
      expect(find.byKey(const Key('etat-numerotation')), findsOneWidget);
      await nettoyer(tester);
    });

    testWidgets('les préfixes individuels sont limités à quatre caractères', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Numérotation Bandes & Sujets');

      await tester.enterText(
        find.byKey(const Key('format-truie_prefix')),
        'TRUIE',
      );
      await tester.enterText(
        find.byKey(const Key('format-volaille_prefix')),
        'LOT-VOL',
      );

      expect(find.text('TRUI'), findsOneWidget);
      expect(find.text('LOT-VOL'), findsOneWidget);
      await nettoyer(tester);
    });

    testWidgets(
      '⚠️ sans tirage, la numérotation dit qu elle n est pas synchronisée',
      (tester) async {
        await afficher(tester);
        await ouvrir(tester, 'Numérotation Bandes & Sujets');

        expect(
          find.byKey(const Key('numerotation-non-synchronisee')),
          findsOneWidget,
        );
        await nettoyer(tester);
      },
    );

    testWidgets('le délai de rappel s enregistre de 0 à 30, pas au-delà', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Calendriers de Prophylaxie');

      await tester.enterText(find.byKey(const Key('rappel-soins')), '45');
      await tester.tap(find.byKey(const Key('rappel-soins-enregistrer')));
      await tester.pumpAndSettle();
      expect(
        find.text('Le champ délai de rappel dépasse le maximum autorisé (30).'),
        findsOneWidget,
      );
      expect(await db.select(db.companySettings).get(), isEmpty);

      await tester.enterText(find.byKey(const Key('rappel-soins')), '5');
      await tester.tap(find.byKey(const Key('rappel-soins-enregistrer')));
      await tester.pumpAndSettle();

      final e = await db.select(db.companySettings).getSingle();
      expect([e.rappelSoinsJours, e.syncStatus], [5, SyncStatus.pending]);
      expect(find.byKey(const Key('rappel-soins-erreur')), findsNothing);
      expect(find.byKey(const Key('etat-rappel-soins')), findsOneWidget);
      await nettoyer(tester);
    });
  });
}
