import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// PWA-2b — GARDE DE PERFORMANCE DE L'ABSORPTION (priorité 1 : synchronisation incrémentale lente au navigateur).
///
/// CAUSE MESURÉE dans Chromium : le plan comptable (1 337 lignes, servi EN ENTIER à chaque tirage, incrémental compris)
/// était écrit par un `await insert` PAR LIGNE. Sur le web chaque instruction attendue est un aller-retour vers le worker
/// SQLite (≈ 55 ms) : 73 s pour cette seule table (95 s la page 1). Sur le poste Windows (isolat natif) le même code ne
/// coûtait que ≈ 0,1 s : le défaut est invisible en VM par la DURÉE, d'où une garde sur le NOMBRE D'INSTRUCTIONS émises
/// (ce qui fait le coût au navigateur), plus une durée à marge très large.
///
/// Sémantique inchangée et verrouillée ici : une ligne `pending` n'est jamais écrasée par le tirage.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class _Serveur extends Interceptor {
  _Serveur(this.comptes);
  final List<Map<String, dynamic>> comptes;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path.contains('push')
            ? <String, dynamic>{}
            : {
                'chart_of_accounts': comptes,
                'server_time': '2026-11-09T12:00:00+00:00',
              },
      ),
    );
  }
}

/// Compte les instructions qui atteignent le moteur SQLite (chaque appel = un aller-retour au navigateur).
/// Un serveur qui sert TOUTES les clés de la page, vides : un tirage incrémental à charge faible.
class _ServeurVide extends Interceptor {
  _ServeurVide(this.cles);
  final Set<String> cles;

  /// Les clés servies sous forme d'OBJET (singletons), pas de liste.
  static const objets = {
    'elevage_numbering',
    'company_settings',
    'attestation_counts',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path.contains('push')
            ? <String, dynamic>{}
            : {
                for (final c in cles)
                  c: objets.contains(c) ? <String, dynamic>{} : <dynamic>[],
                'server_time': '2026-11-09T12:00:00+00:00',
              },
      ),
    );
  }
}

/// PWA-2c (2) — un serveur qui sert, EN PLUS des clés vides, quelques lignes pour les huit tables jusque-là écrites ligne à ligne.
class _ServeurCharge extends Interceptor {
  _ServeurCharge(this.cles, this.corps);
  final Set<String> cles;
  final Map<String, Object?> corps;
  bool actif = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: options.path.contains('push')
            ? <String, dynamic>{}
            : {
                for (final c in cles) c: _ServeurVide.objets.contains(c) ? <String, dynamic>{} : <dynamic>[],
                if (actif) ...corps,
                'server_time': '2026-11-09T12:00:00+00:00',
              },
      ),
    );
  }
}

class _Compteur extends QueryInterceptor {
  int instructions = 0;

  /// Les instructions vues (texte SQL), pour savoir QUI les émet.
  final List<String> journal = [];

  // Une transaction (ou un point de sauvegarde imbriqué) = deux messages de plus au navigateur.
  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    instructions++;
    journal.add('BEGIN');
    return super.beginTransaction(parent);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    instructions++;
    journal.add('COMMIT');
    return super.commitTransaction(inner);
  }

  @override
  Future<void> runBatched(QueryExecutor e, BatchedStatements s) {
    instructions++;
    journal.add(s.statements.isEmpty ? 'batch vide' : s.statements.first);
    return super.runBatched(e, s);
  }

  @override
  Future<void> runCustom(QueryExecutor e, String s, List<Object?> a) {
    instructions++;
    journal.add(s);
    return super.runCustom(e, s, a);
  }

  @override
  Future<int> runInsert(QueryExecutor e, String s, List<Object?> a) {
    instructions++;
    journal.add(s);
    return super.runInsert(e, s, a);
  }

  @override
  Future<int> runUpdate(QueryExecutor e, String s, List<Object?> a) {
    instructions++;
    journal.add(s);
    return super.runUpdate(e, s, a);
  }

  @override
  Future<int> runDelete(QueryExecutor e, String s, List<Object?> a) {
    instructions++;
    journal.add(s);
    return super.runDelete(e, s, a);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor e,
    String s,
    List<Object?> a,
  ) {
    instructions++;
    journal.add(s);
    return super.runSelect(e, s, a);
  }
}

void main() {
  const n = 3000;
  String id(int i) =>
      'c0c0c0c0-0000-4000-8000-${i.toString().padLeft(12, '0')}';

  test(
    'absorber $n comptes déjà connus : peu d\'instructions, jamais d\'écrasement d\'une ligne en attente',
    () async {
      final comptes = [
        for (var i = 0; i < n; i++)
          {'id': id(i), 'code': '${100000 + i}', 'label': 'Compte $i', 'class': 6},
      ];
      final compteur = _Compteur();
      final db = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(compteur),
      );
      addTearDown(db.close);
      final moteur = SyncEngine(
        database: db,
        client: Dio()..interceptors.add(_Serveur(comptes)),
        deviceId: 'poste-perf',
        connectivity: _Connectivite(),
      );

      // Un compte saisi au poste, en attente : le tirage ne doit pas le toucher.
      await db
          .into(db.chartOfAccounts)
          .insert(
            ChartOfAccountsCompanion.insert(
              id: id(7),
              code: 'LOCAL',
              label: 'Saisi au poste',
              syncStatus: const Value(SyncStatus.pending),
            ),
          );

      await moteur.synchroniser(); // tirage 1 : insère les comptes
      expect(await db.select(db.chartOfAccounts).get(), hasLength(n));

      compteur.instructions = 0;
      final chrono = Stopwatch()..start();
      await moteur.synchroniser(); // tirage 2 : les 3 000 sont DÉJÀ connus
      chrono.stop();

      // Avant : ≥ 3 000 instructions (une par ligne) ; après : une poignée (+ réglages, envoi, curseur).
      expect(
        compteur.instructions,
        lessThan(150),
        reason: 'une instruction par ligne coûterait ≈ 55 ms chacune au navigateur',
      );
      expect(
        chrono.elapsed,
        lessThan(const Duration(seconds: 60)),
        reason: 'marge très large : la VM mesure ≈ 0,3 s',
      );
      final protege = await (db.select(db.chartOfAccounts)
            ..where((t) => t.id.equals(id(7))))
          .getSingle();
      expect(protege.code, 'LOCAL', reason: 'la ligne en attente survit');
    },
  );

  test(
    'tirage incrémental de ~60 tables à charge faible : nombre d\'instructions borné',
    () async {
      // Les clés que le moteur absorbe, lues dans `_absorberPage` (comme le fait `perimetre_tirage_test`).
      final page = File('lib/core/sync/sync_engine.dart')
          .readAsStringSync()
          .split('Future<int> _absorberPage(Map<String, dynamic> corps) async {')[1]
          .split('\n  }\n')
          .first;
      final cles = {
        for (final m in RegExp(r"corps\['(\w+)'\]").allMatches(page))
          m.group(1)!,
      };
      expect(cles.length, greaterThan(50));

      final compteur = _Compteur();
      final db = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(compteur),
      );
      addTearDown(db.close);
      final moteur = SyncEngine(
        database: db,
        client: Dio()..interceptors.add(_ServeurVide(cles)),
        deviceId: 'poste-perf',
        connectivity: _Connectivite(),
      );

      await moteur.synchroniser(); // tirage initial
      compteur.journal.clear();
      compteur.instructions = 0;
      await moteur.synchroniser(); // tirage incrémental : rien n'a changé
      final parTable = <String, int>{};
      for (final sql in compteur.journal) {
        final t = RegExp(r'(?:FROM|INTO|UPDATE)\s+"?(\w+)"?', caseSensitive: false)
            .firstMatch(sql)
            ?.group(1) ?? sql.split(' ').first;
        parTable[t] = (parTable[t] ?? 0) + 1;
      }

      // PWA-2c — avant : 228 (dont 82 messages de transactions imbriquées, un `select` par réglage de
      // resynchronisation, 2 à 3 instructions pour une table de fusion VIDE) ; après : ≈ 134, dont ≈ 25 contrôles
      // « rien à envoyer » du côté envoi. Borne large : un retour aux 3 à 5 instructions par absorbeur la dépasserait.
      expect(
        compteur.instructions,
        lessThan(170),
        reason:
            'chaque instruction coûte un aller-retour au navigateur ; par table : $parTable',
      );
      expect(
        compteur.journal.where((s) => s == 'BEGIN').length,
        lessThan(10),
        reason: 'une seule transaction par page : plus de point de sauvegarde par absorbeur',
      );
    },
  );

  // PWA-2c (2) — huit tables à petite charge (8 lignes chacune) : créances, prophylaxie, sujets, rations, relevés, revenus de bande,
  // transformations, calendrier vétérinaire. Avant : une à trois instructions PAR LIGNE ; après : une rafale par table.
  test(
    'tirage incrémental de huit tables à petite charge : instructions bornées, aucune ligne pending écrasée',
    () async {
      final page = File('lib/core/sync/sync_engine.dart')
          .readAsStringSync()
          .split('Future<int> _absorberPage(Map<String, dynamic> corps) async {')[1]
          .split('\n  }\n')
          .first;
      final cles = {for (final m in RegExp(r"corps\['(\w+)'\]").allMatches(page)) m.group(1)!};
      String u(String t, int i) => '$t-0000-4000-8000-${i.toString().padLeft(12, '0')}';
      const n = 8;
      final lot = u('b0b0b0b0', 1);
      final corps = <String, Object?>{
        'receivables': [for (var i = 0; i < n; i++) {'id': u('a1a1a1a1', i), 'customer_id': u('c1c1c1c1', 1), 'amount': 1000 + i, 'amount_paid': 0, 'status': 'en_cours'}],
        'prophylaxis_schedule_standards': [for (var i = 0; i < n; i++) {'id': u('a2a2a2a2', i), 'species_code': 'lapin', 'period_label': 'P$i', 'treatment': 'T$i', 'is_active': true}],
        'animals': [for (var i = 0; i < n; i++) {'id': u('a3a3a3a3', i), 'identifier': 'S$i', 'is_active': true}],
        'feed_ration_standards': [for (var i = 0; i < n; i++) {'id': u('a4a4a4a4', i), 'species_code': 'lapin', 'stage_label': 'S$i', 'ration_g_per_day': 50 + i, 'is_active': true}],
        'field_survey_entries': [for (var i = 0; i < n; i++) {'id': u('a5a5a5a5', i), 'type': 'delai_regle', 'label': 'R$i', 'status': 'valide', 'data': <String, dynamic>{}, 'is_active': true}],
        'lot_revenues': [for (var i = 0; i < n; i++) {'lot_id': lot, 'product_id': u('d1d1d1d1', i), 'label': 'Rev $i', 'amount': 10 + i}],
        'transformations': [for (var i = 0; i < n; i++) {'id': u('a6a6a6a6', i), 'lot_id': lot, 'product_id': u('d1d1d1d1', 1), 'qty_animals': 2, 'qty_produced': 3, 'transformation_date': '2026-11-0${1 + i % 8}'}],
        'veterinary_calendar_events': [for (var i = 0; i < n; i++) {'id': u('a7a7a7a7', i), 'lot_id': lot, 'task_type': 'vaccin', 'scheduled_date': '2026-11-0${1 + i % 8}', 'status': 'planned'}],
      };
      final serveur = _ServeurCharge(cles, corps);
      final compteur = _Compteur();
      final db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(compteur));
      addTearDown(db.close);
      final moteur = SyncEngine(database: db, client: Dio()..interceptors.add(serveur), deviceId: 'poste-perf', connectivity: _Connectivite());
      await db.into(db.livestockLots).insert(LivestockLotsCompanion.insert(id: lot, code: 'B1', speciesId: u('e1e1e1e1', 1)));
      // Une saisie du poste en attente (sujet) : le tirage ne doit jamais la toucher.
      await db.into(db.animals).insert(AnimalsCompanion.insert(id: u('a3a3a3a3', 3), identifier: 'LOCAL', syncStatus: const Value(SyncStatus.pending)));

      await moteur.synchroniser(); // tirage initial, tout vide
      serveur.actif = true;
      await moteur.synchroniser(); // premier tirage de la charge : 8 lignes par table
      expect((await db.select(db.receivables).get()).length, n);
      expect((await db.select(db.prophylaxisScheduleStandards).get()).length, n);
      expect((await db.select(db.feedRationStandards).get()).length, n);
      expect((await db.select(db.fieldSurveyEntries).get()).length, n);
      expect((await db.select(db.lotRevenues).get()).length, n);
      expect((await db.select(db.transformations).get()).length, n);
      expect((await db.select(db.veterinaryCalendarEvents).get()).length, n);
      final sujets = await db.select(db.animals).get();
      expect(sujets.length, n, reason: '7 reçus + le sujet LOCAL conservé, qui occupe l\'identifiant 3');
      expect(sujets.firstWhere((a) => a.id == u('a3a3a3a3', 3)).identifier, 'LOCAL', reason: 'jamais écrasé');

      compteur.journal.clear();
      compteur.instructions = 0;
      await moteur.synchroniser(); // même charge, tout déjà connu
      final parTable = <String, int>{};
      for (final sql in compteur.journal) {
        final t = RegExp(r'(?:FROM|INTO|UPDATE)\s+"?(\w+)"?', caseSensitive: false).firstMatch(sql)?.group(1) ?? sql.split(' ').first;
        parTable[t] = (parTable[t] ?? 0) + 1;
      }
      // Mesuré : 224 instructions avant le regroupement (une à deux PAR LIGNE : 17 pour les transformations, 17 pour le calendrier,
      // 11 pour les rations / la prophylaxie / les relevés, 9 pour les créances), 156 après (une rafale par table ; il reste ≈ 25
      // contrôles « rien à envoyer »). Un retour à la ligne à ligne dépasse la borne (mutation vérifiée sur l'ancien moteur : 224).
      expect(compteur.instructions, lessThan(165), reason: 'par table : $parTable');
    },
  );
}
