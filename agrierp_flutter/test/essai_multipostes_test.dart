@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:agrierp/core/auth/auth_service.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/gestes_importants.dart';
import 'package:agrierp/core/sync/perimetre_tirage.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/sync/synchronisation_automatique.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/elevage/transferts_repository.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:agrierp/features/sync/coherence_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'coffre_memoire.dart';

/// Ticket S-T9 — ESSAI À PLUSIEURS POSTES CONTRE LE VRAI SERVEUR, AVEC COUPURES AU HASARD (méthode TATACORA).
///
/// Cinq postes (cinq bases Drift en mémoire, cinq identifiants, cinq jetons nommés d'après eux, quatre rôles), chacun
/// avec son `SyncEngine` RÉEL et sa synchronisation automatique RÉELLE, travaillent plusieurs « journées » par leurs
/// VRAIS dépôts (caisse, fiches, soins, clients, fournisseurs, achats, stocks, avances, transferts) contre le VRAI
/// serveur Laravel, pendant que le web écrit de son côté (vente à la caisse web, ration modifiée). Un intercepteur
/// Dio coupe le réseau au hasard — requête qui n'arrive pas, RÉPONSE PERDUE APRÈS TRAITEMENT (le cas des doublons),
/// délai dépassé, 500, corps trop gros (413 d'un mandataire) — avec une graine fixée et journalisée pour rejouer.
/// Puis le réseau redevient parfait et chacun synchronise jusqu'à ce que plus rien ne soit en attente.
///
/// Invariants vérifiés à la fin (un `expect` chacun, message en clair) : aucune saisie perdue, aucun doublon au
/// serveur, aucune vente comptée deux fois (ni zéro fois) sur une fiche, stock = grand livre, journal équilibré,
/// contrôle de cohérence S-T6 de chaque poste sans écart, écritures du web reçues partout, refus seulement là où ils
/// sont attendus et toujours motivés. Un rapport lisible est écrit hors du dépôt (`AGRIERP_ESSAI_RAPPORT`).
///
/// ⚠️⚠️ CE TEST ÉCRIT SUR LE SERVEUR (ventes, achats, écritures). Il ne tourne QUE si `AGRIERP_ESSAI_URL` est posée —
/// par `outils/essai_multipostes.sh`, qui crée une base jetable — et se marque SAUTÉ sinon, avec sa raison. Jamais
/// contre le serveur de développement (`:8002`) par accident.
///
/// Rejouer : `outils/essai_multipostes.sh <graine>`. ⚠️ Le rejeu est fidèle pour les décisions de coupure de CHAQUE
/// poste (une suite aléatoire par poste, tirée dans l'ordre de ses propres requêtes) ; l'entrelacement des cinq postes
/// au serveur, lui, dépend de l'horloge — comme à la ferme.
void main() {
  final env = Platform.environment;
  final adresse = env['AGRIERP_ESSAI_URL'];
  final graine = int.tryParse(env['AGRIERP_ESSAI_GRAINE'] ?? '') ?? 20261019;
  final nombreDeJours = int.tryParse(env['AGRIERP_ESSAI_JOURS'] ?? '') ?? 4;
  final fichierRapport =
      env['AGRIERP_ESSAI_RAPPORT'] ??
      '${Directory.systemTemp.path}/agrierp-essai-multipostes-$graine.txt';

  test(
    '⚠️⚠️ cinq postes, coupures au hasard : rien de perdu, rien en double, tout se rejoint',
    () async {
      if (adresse == null || adresse.isEmpty) {
        markTestSkipped(
          "Essai à plusieurs postes non lancé : il écrit sur le serveur et exige une base jetable. Lancez "
          "`outils/essai_multipostes.sh` (base dédiée, serveur, test, arrêt propre).",
        );
        return;
      }
      if (!await _serveurJoignable(adresse)) {
        markTestSkipped('Serveur de l\'essai injoignable sur $adresse.');
        return;
      }

      final essai = _Essai(
        adresse: adresse,
        graine: graine,
        jours: nombreDeJours,
        base: env['AGRIERP_ESSAI_BASE'] ?? '?',
      );
      try {
        await essai.derouler();
      } finally {
        await File(fichierRapport).writeAsString(essai.rapport());
        // ignore: avoid_print
        print('Rapport de l\'essai : $fichierRapport');
        await essai.fermer();
      }
      essai.verifier();
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Future<bool> _serveurJoignable(String adresse) async {
  try {
    final r = await Dio(BaseOptions(baseUrl: adresse, connectTimeout: const Duration(seconds: 5)))
        .get<dynamic>('/up');
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Réseau
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// `connectivity_plus` passe par un canal de plateforme, absent d'un `flutter test` (voir `sync_reel_test.dart`).
/// [enLigne] simule le câble débranché d'une journée entière : le moteur répond alors « hors ligne », sans erreur.
class _Connectivite implements Connectivity {
  bool enLigne = true;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [enLigne ? ConnectivityResult.wifi : ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Coupures au hasard sur `/api/sync/pull` et `/api/sync/push`.
///
/// Chaque poste a SA suite aléatoire (graine de l'essai × rang du poste), tirée une fois par requête dans l'ordre de
/// ses propres requêtes : le journal dit, pour chaque coupure, quelle requête et quel cas.
class _Perturbateur extends Interceptor {
  _Perturbateur(this.poste, int graine, this.journal) : _alea = Random(graine);

  final String poste;
  final Random _alea;
  final void Function(String) journal;
  bool actif = false;

  /// Un mandataire (proxy) qui refuse les corps de plus de [limiteCorps] octets : 413, la requête n'arrive pas.
  /// Le poste doit couper son lot en deux (S-T1) sans jamais séparer une journée couplée (H13b).
  int limiteCorps = 6000;

  int requetes = 0;
  final compteurs = <String, int>{};

  void _compter(String cas, RequestOptions o, [String detail = '']) {
    compteurs[cas] = (compteurs[cas] ?? 0) + 1;
    journal('$poste  ${o.method} ${o.path}${o.queryParameters.isEmpty ? '' : ' ${o.queryParameters}'}  → $cas$detail');
  }

  static bool _concerne(RequestOptions o) => o.path.startsWith('/api/sync/pull') || o.path.startsWith('/api/sync/push');

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.path.startsWith('/api/sync/push') && options.data is Map) {
      journal('$poste  POST /api/sync/push  ← ${resumeCorps(options.data as Map)}');
    }
    if (!actif || !_concerne(options)) return handler.next(options);
    requetes++;

    // Lenteur de la liaison : 0 à 250 ms, ce qui laisse aux gestes le temps de tomber PENDANT un envoi.
    await Future<void>.delayed(Duration(milliseconds: _alea.nextInt(250)));

    if (options.method == 'POST' && options.data is Map) {
      final taille = utf8.encode(jsonEncode(options.data)).length;
      if (taille > limiteCorps) {
        _compter('413 (corps de $taille octets refusé par le mandataire)', options);
        return handler.reject(
          DioException.badResponse(
            statusCode: 413,
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 413, data: '<html>413 Request Entity Too Large</html>'),
          ),
        );
      }
    }

    final tirage = _alea.nextDouble();
    if (tirage < 0.07) {
      _compter('requête perdue (n\'arrive pas)', options);
      return handler.reject(
        DioException.connectionError(
          requestOptions: options,
          reason: 'coupure simulée',
          error: const SocketException('coupure simulée : la requête n\'arrive pas'),
        ),
      );
    }
    if (tirage < 0.17) {
      options.extra['essai_perdre_reponse'] = 'réponse perdue APRÈS traitement';
    } else if (tirage < 0.21) {
      options.extra['essai_perdre_reponse'] = 'délai dépassé APRÈS traitement';
    } else if (tirage < 0.25) {
      _compter('500 simulée (n\'arrive pas)', options);
      return handler.reject(
        DioException.badResponse(
          statusCode: 500,
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 500, data: {'message': 'Server Error'}),
        ),
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final perte = response.requestOptions.extra['essai_perdre_reponse'];
    if (perte is String) {
      _compter(perte, response.requestOptions, ' (statut ${response.statusCode})');
      return handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          type: perte.startsWith('délai') ? DioExceptionType.receiveTimeout : DioExceptionType.connectionError,
          error: perte.startsWith('délai') ? null : const SocketException('coupure simulée : réponse perdue'),
          message: 'coupure simulée : $perte',
        ),
      );
    }
    if (response.requestOptions.path.startsWith('/api/sync/push') && response.data is Map) {
      journal('$poste  POST /api/sync/push  → ${resumeEnvoi(response.data as Map)}');
    }
    handler.next(response);
  }

  /// Ce qui part : fiches (identifiant court, jour, vente) et ventes (identifiant court) — de quoi suivre une vente.
  static String resumeCorps(Map corps) {
    String court(Object? id) => '$id'.length > 8 ? '$id'.substring(0, 8) : '$id';
    final fiches = [
      for (final f in (corps['livestock_daily_entries'] as List?) ?? const [])
        if (f is Map) '${court(f['id'])} ${f['entry_date']}${f.containsKey('vente') ? ' v=${f['vente']}' : ' (identité)'}',
    ];
    final ventes = [
      for (final v in (corps['sales'] as List?) ?? const [])
        if (v is Map) court(v['id']),
    ];
    final autres = [
      for (final MapEntry(:key, :value) in corps.entries)
        if (value is List && value.isNotEmpty && key != 'livestock_daily_entries' && key != 'sales') '$key ${value.length}',
    ];
    return [
      if (fiches.isNotEmpty) 'fiches [${fiches.join(', ')}]',
      if (ventes.isNotEmpty) 'ventes [${ventes.join(', ')}]',
      ...autres,
    ].join(' · ');
  }

  /// « fiches 2 acquittées (1 fusionnées) 0 refusées · ventes 3 acquittées … » : les tables non vides de la réponse.
  static String resumeEnvoi(Map corps) {
    final parties = <String>[];
    corps.forEach((table, r) {
      if (r is! Map) return;
      final a = (r['accepted'] as List?)?.length ?? 0;
      final f = (r['merged'] as List?)?.length ?? 0;
      final k = (r['rejected'] as List?)?.length ?? 0;
      if (a + f + k == 0) return;
      final fusions = [
        for (final m in (r['merged'] as List?) ?? const [])
          if (m is Map) '${'${m['id']}'.substring(0, 8)}→${'${m['id_serveur']}'.substring(0, 8)}',
      ];
      parties.add('$table $a acquitté(s)${f > 0 ? ' dont $f fusionné(s) ${fusions.join(' ')}' : ''}${k > 0 ? ', $k refusé(s)' : ''}');
    });
    return parties.isEmpty ? 'rien à traiter' : parties.join(' · ');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Postes
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// Ce que chaque poste a saisi, table par table (identifiants du POSTE) — comparé au serveur à la fin.
typedef _Saisies = Map<String, List<String>>;

class _Poste {
  _Poste({
    required this.nom,
    required this.compte,
    required this.role,
    required this.rang,
    required String adresse,
    required int graine,
    required void Function(String) journal,
  }) : db = AppDatabase.forTesting(NativeDatabase.memory()),
       client = Dio(
         BaseOptions(
           baseUrl: adresse,
           // Comme le client de production (`main.dart`), en plus court : l'essai simule ses propres délais.
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 60),
         ),
       ) {
    perturbateur = _Perturbateur(nom, graine * 31 + rang, journal);
    client.interceptors.add(perturbateur);
    alea = Random(graine * 17 + rang);
  }

  final String nom;
  final String compte;
  final String role;
  final int rang;
  final AppDatabase db;
  final Dio client;
  final connectivite = _Connectivite();
  final gestes = GestesImportants();
  late final _Perturbateur perturbateur;
  late final Random alea;
  late final SyncEngine moteur;
  late final SynchronisationAutomatique auto;

  /// Jour simulé du poste (minuit) et horloge qui en découle (l'heure réelle, ce jour-là).
  DateTime jour = DateTime.now();
  DateTime maintenant() {
    final n = DateTime.now();
    return DateTime(jour.year, jour.month, jour.day, n.hour, n.minute, n.second, n.millisecond);
  }

  final _Saisies saisies = {};
  void noter(String table, String id) => (saisies[table] ??= []).add(id);

  final resultats = <String, int>{};
  final erreursInattendues = <String>[];

  Future<void> connecter(String motDePasse) async {
    final auth = AuthService(client: client, deviceName: nom, coffre: CoffreMemoire());
    await auth.connecter(identifiant: compte, motDePasse: motDePasse);
    moteur = SyncEngine(database: db, client: client, deviceId: nom, connectivity: connectivite);
    auto = SynchronisationAutomatique(
      synchroniser: moteur.synchroniser,
      changementsReseau: const Stream.empty(),
      intervalle: Duration(seconds: 6 + rang),
      gestes: gestes,
      delaiAgregation: const Duration(milliseconds: 300),
    );
  }

  /// Une synchronisation « manuelle » (bouton) : son issue est comptée, jamais propagée — sauf une erreur qui
  /// n'est ni un refus du serveur ni un échec de liaison, notée comme INATTENDUE (elle fait échouer l'essai).
  Future<SyncOutcome?> synchroniser(String quand) async {
    try {
      final r = await moteur.synchroniser();
      _compter(r.horsLigne ? 'hors ligne' : (r.rejete > 0 ? 'aboutie avec refus' : 'aboutie'));
      return r;
    } on EchecSynchronisation catch (e) {
      _compter('refus HTTP ${e.statut}');
      return null;
    } catch (e) {
      if (SynchronisationAutomatique.estReessayable(e)) {
        _compter('échec réessayable');
        return null;
      }
      erreursInattendues.add('$quand : ${e.runtimeType} — $e');
      _compter('ERREUR INATTENDUE');
      return null;
    }
  }

  void _compter(String cas) => resultats[cas] = (resultats[cas] ?? 0) + 1;

  // ── Dépôts, à l'horloge du jour simulé ───────────────────────────────────────────────────────────────────────
  CaisseRepository get caisse => CaisseRepository(database: db, deviceId: nom, maintenant: maintenant, gestes: gestes);
  FicheJournaliereRepository get fiches => FicheJournaliereRepository(database: db, deviceId: nom, gestes: gestes);
  SoinsRepository get soins => SoinsRepository(database: db, deviceId: nom, gestes: gestes);
  ClientsCreancesRepository get clients => ClientsCreancesRepository(database: db, deviceId: nom);
  FournisseursRepository get fournisseurs => FournisseursRepository(database: db, deviceId: nom);
  AchatsRepository get achats => AchatsRepository(database: db, identifiantPoste: nom, horloge: maintenant);
  StocksRepository get stocks => StocksRepository(database: db, deviceId: nom, horloge: maintenant);
  TransfertsRepository get transferts => TransfertsRepository(database: db, deviceId: nom);

  Future<Product> produit(String debutDuNom) async =>
      (await db.select(db.products).get()).firstWhere((p) => p.name.startsWith(debutDuNom));
  Future<LivestockLot> bande(String code) async =>
      (await db.select(db.livestockLots).get()).firstWhere((b) => b.code == code);

  /// Lignes encore `pending`, table par table (toutes les tables synchronisables du poste).
  Future<Map<String, int>> enAttente() async {
    final resultat = <String, int>{};
    for (final t in db.allTables) {
      if (!t.$columns.any((c) => c.name == 'sync_status')) continue;
      final n = (await db
              .customSelect("SELECT COUNT(*) AS n FROM ${t.actualTableName} WHERE sync_status = 'pending'")
              .getSingle())
          .read<int>('n');
      if (n > 0) resultat[t.actualTableName] = n;
    }
    return resultat;
  }

  Future<void> fermer() async {
    auto.arreter();
    await db.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// L'essai
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

class _Essai {
  _Essai({required this.adresse, required this.graine, required this.jours, required this.base});

  final String adresse;
  final int graine;
  final int jours;
  final String base;
  final debut = DateTime.now();
  final _journal = <String>[];
  final _evenements = <String>[];
  late final List<_Poste> postes;
  late final _Poste bureau, caisse1, caisse2, elevage, compta;
  late final Directory _travail;
  late final String _instantane;

  Map<String, dynamic> etatServeur = {};
  final webVentes = <String>[];
  String? rationWeb;
  int? grammesWeb;
  final coherence = <String, ResultatCoherence?>{};
  final conflits = <String, List<SyncConflict>>{};
  final enAttenteFin = <String, Map<String, int>>{};
  final webRecu = <String, List<String>>{};

  void journaliser(String ligne) {
    final t = DateTime.now().difference(debut);
    _journal.add('[${(t.inMilliseconds / 1000).toStringAsFixed(1).padLeft(6)} s] $ligne');
  }

  void evenement(String ligne) {
    journaliser('— $ligne');
    _evenements.add(ligne);
  }

  // ── Côté serveur (le « web » et l'état final) ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _serveur(List<String> arguments) async {
    final r = await Process.run('php', [
      '${Directory.current.path}/outils/essai_multipostes_serveur.php',
      dossierLaravel,
      ...arguments,
    ], workingDirectory: dossierLaravel);
    if (r.exitCode != 0) {
      throw StateError('Commande serveur « ${arguments.first} » en échec (${r.exitCode}) : ${r.stdout}\n${r.stderr}');
    }
    return jsonDecode(r.stdout as String) as Map<String, dynamic>;
  }

  Future<void> derouler() async {
    _travail = await Directory.systemTemp.createTemp('agrierp-essai-');
    _instantane = '${_travail.path}/instantane.json';
    journaliser('Essai S-T9 — graine $graine, $jours journées, base $base, serveur $adresse');

    // Deux bandes créées AU WEB, sans fiche dans la fenêtre de l'essai : c'est là que deux postes se disputeront
    // la fiche (bande, jour). Puis l'instantané du serveur (stocks, grand livre, fiches, ventes connues).
    final prepare = await _serveur(['preparer', _instantane]);
    evenement('Web : bandes ${(prepare['bandes'] as Map).keys.join(', ')} créées (GestionBandes)');

    postes = [
      bureau = _Poste(nom: 'poste-bureau', compte: 'admin', role: 'admin', rang: 1, adresse: adresse, graine: graine, journal: journaliser),
      caisse1 = _Poste(nom: 'poste-caisse-1', compte: 'caisse', role: 'caissier', rang: 2, adresse: adresse, graine: graine, journal: journaliser),
      caisse2 = _Poste(nom: 'poste-caisse-2', compte: 'caisse', role: 'caissier', rang: 3, adresse: adresse, graine: graine, journal: journaliser),
      elevage = _Poste(nom: 'poste-elevage', compte: 'elevage', role: 'animalier', rang: 4, adresse: adresse, graine: graine, journal: journaliser),
      compta = _Poste(nom: 'poste-compta', compte: 'compta', role: 'comptable', rang: 5, adresse: adresse, graine: graine, journal: journaliser),
    ];

    // Connexion réelle (5 connexions : le limiteur du serveur en accepte 5 par minute et par adresse), puis le
    // premier tirage complet, réseau parfait — l'installation du poste.
    for (final p in postes) {
      await p.connecter('AgriERP@2026');
    }
    await Future.wait([for (final p in postes) p.synchroniser('premier tirage')]);
    for (final p in postes) {
      final ventes = await p.db.select(p.db.sales).get();
      journaliser('${p.nom} (${p.role}) : premier tirage — ${ventes.length} ventes, '
          '${(await p.db.select(p.db.livestockDailyEntries).get()).length} fiches, '
          'périmètre ${(await PerimetreTirage.lire(p.db))?.length ?? '?'} tables');
    }

    // ── Journées perturbées ──────────────────────────────────────────────────────────────────────────────────
    for (final p in postes) {
      p.perturbateur.actif = true;
      p.auto.demarrer();
    }
    final aujourdHui = DateTime.now();
    for (var d = 0; d < jours; d++) {
      final jour = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day).subtract(Duration(days: jours - 1 - d));
      for (final p in postes) {
        p.jour = jour;
      }
      // Une journée sans réseau pour la deuxième caisse (le câble du comptoir) : elle saisit, elle n'envoie rien.
      caisse2.connectivite.enLigne = d != 1;
      evenement('Journée ${d + 1}/$jours (${_jourFr(jour)})${d == 1 ? ' — poste-caisse-2 hors ligne toute la journée' : ''}');

      await Future.wait([
        _journeeBureau(d),
        _journeeCaisse(caisse1, d),
        _journeeCaisse(caisse2, d),
        _journeeElevage(d),
        _journeeCompta(d),
        _journeeWeb(d, jour),
      ]);

      // Fin de journée : chacun tente sa synchronisation (le réseau reste perturbé).
      await Future.wait([for (final p in postes) p.synchroniser('fin de journée ${d + 1}')]);
    }

    // ── Rétablissement : réseau parfait, synchronisations jusqu'à ce que plus rien ne soit en attente ────────────
    for (final p in postes) {
      p.auto.arreter();
      p.perturbateur.actif = false;
      p.connectivite.enLigne = true;
    }
    evenement('Rétablissement : réseau parfait');
    for (var tour = 1; tour <= 8; tour++) {
      for (final p in postes) {
        final r = await p.synchroniser('rétablissement $tour');
        if (r == null) await Future<void>.delayed(const Duration(seconds: 2));
      }
      final restants = {for (final p in postes) p.nom: await p.enAttente()}..removeWhere((_, v) => v.isEmpty);
      journaliser('Rétablissement, tour $tour : ${restants.isEmpty ? 'plus rien en attente' : 'en attente $restants'}');
      if (restants.isEmpty) break;
    }
    // Un dernier tirage pour tous : chacun reçoit ce que les autres ont envoyé au dernier tour.
    for (final p in postes) {
      await p.synchroniser('tirage final');
    }

    // ── Relevés ──────────────────────────────────────────────────────────────────────────────────────────────
    final depuis = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day).subtract(Duration(days: jours + 2));
    for (final p in postes) {
      enAttenteFin[p.nom] = await p.enAttente();
      conflits[p.nom] = await p.moteur.conflits();
      try {
        coherence[p.nom] = await ControleCoherenceRepository(
          database: p.db,
          serveur: p.moteur.coherenceDuServeur,
        ).verifier(depuis: depuis);
      } catch (e) {
        p.erreursInattendues.add('contrôle de cohérence : $e');
        coherence[p.nom] = null;
      }
      final ventesLocales = {for (final v in await p.db.select(p.db.sales).get()) v.id};
      webRecu[p.nom] = [
        for (final v in webVentes)
          if (!ventesLocales.contains(v)) 'vente web $v absente',
        if (rationWeb != null && (await PerimetreTirage.lire(p.db) ?? const {}).contains('feed_ration_standards'))
          ...await () async {
            final r = await (p.db.select(p.db.feedRationStandards)..where((t) => t.id.equals(rationWeb!))).getSingleOrNull();
            return [if (r?.rationGPerDay != grammesWeb) 'ration web : ${r?.rationGPerDay} g au lieu de $grammesWeb g'];
          }(),
      ];
    }

    await _classerEcarts();
    for (final c in conflits[elevage.nom]!) {
      if (c.sourceTable != 'livestock_daily_entries') continue;
      final f = await (elevage.db.select(elevage.db.livestockDailyEntries)..where((t) => t.id.equals(c.recordId))).getSingleOrNull();
      if (f != null) clesRefuseesElevage.add('${f.lotId}|${_jourIso(f.entryDate)}');
    }

    final toutes = <String, List<String>>{};
    for (final p in postes) {
      for (final MapEntry(:key, :value) in p.saisies.entries) {
        (toutes[key] ??= []).addAll(value);
      }
    }
    final fichierSaisies = '${_travail.path}/saisies.json';
    await File(fichierSaisies).writeAsString(jsonEncode(toutes));
    etatServeur = await _serveur(['etat', _instantane, fichierSaisies]);
  }

  // ── Gestes de chaque rôle ───────────────────────────────────────────────────────────────────────────────────

  /// Petite pause entre deux gestes : les envois automatiques (agrégation 300 ms) partent PENDANT la journée, et
  /// un geste peut tomber pendant un envoi.
  Future<void> _pause(_Poste p) => Future<void>.delayed(Duration(milliseconds: 100 + p.alea.nextInt(500)));

  /// Un geste qui lève (refus du dépôt, comme l'écran le montrerait) est journalisé, jamais fatal : l'essai porte
  /// sur la synchronisation, pas sur les contrôles de saisie.
  Future<void> _geste(_Poste p, String quoi, Future<void> Function() geste) async {
    try {
      await geste();
      journaliser('${p.nom}  ✎ $quoi');
    } catch (e) {
      journaliser('${p.nom}  ✎ $quoi — REFUSÉ AU POSTE : $e');
      p._compter('geste refusé au poste');
    }
    await _pause(p);
  }

  Future<String> _compteCaisse(_Poste p) async {
    final comptes = await p.db.select(p.db.treasuryAccounts).get();
    return comptes.firstWhere((c) => c.label.toLowerCase().contains('caisse'), orElse: () => comptes.first).id;
  }

  Future<void> _vente(_Poste p, String produit, int quantite, double prixUnitaire, {String? bande, String mode = 'especes', String? clientId}) async {
    final pr = await p.produit(produit);
    final lot = bande == null ? null : await p.bande(bande);
    final v = await p.caisse.enregistrerVente(
      panier: [LignePanier(produit: pr, quantite: quantite, montant: quantite * prixUnitaire, lotId: lot?.id)],
      modePaiement: mode,
      clientId: clientId,
      especesRecues: mode == 'especes' ? quantite * prixUnitaire : null,
    );
    p.noter('sales', v.id);
    journaliser('${p.nom}  · vente ${v.id.substring(0, 8)} : $quantite × $produit${bande == null ? '' : ' de $bande'} le ${_jourIso(p.jour)}');
  }

  Future<void> _journeeBureau(int d) async {
    final p = bureau;
    switch (d) {
      case 0:
        await _geste(p, 'client « ESSAI Client Commun » (même client qu\'au comptoir 1)', () async {
          final c = await p.clients.creerClient(const FormulaireClient(nom: 'ESSAI Client Commun', telephone: '+229 97 11 22 33', ville: 'Ikpinlè'));
          p.noter('customers', c.id);
        });
        await _geste(p, 'fournisseur « Provenderie ESSAI »', () async {
          final f = await p.fournisseurs.creerFournisseur(const FormulaireFournisseur(nom: 'Provenderie ESSAI', categorie: 'Aliments', telephone: '+229 96 44 55 66'));
          p.noter('suppliers', f.id);
        });
        await _geste(p, 'ajout de stock : 60 Poulet goliath', () async {
          final pr = await p.produit('Poulet goliath');
          final a = await p.stocks.ajouterStock(date: p.jour, productId: pr.id, quantite: '60');
          p.noter('stock_adjustments', a.id);
        });
        await _geste(p, 'achat de 3 sacs d\'aliment croissance', () async {
          final f = (await p.db.select(p.db.suppliers).get()).firstWhere((s) => s.name == 'Provenderie ESSAI');
          final id = await p.achats.enregistrer(
            fournisseurId: f.id,
            lignes: [LigneSaisieAchat(produit: await p.produit('Aliment croissance'), quantite: 3, prixUnitaire: 15000)],
            modePaiement: 'especes',
            compteId: await _compteCaisse(p),
            montantPaye: 45000,
            date: p.jour,
          );
          p.noter('purchases', id);
        });
      case 1:
        await _geste(p, 'inventaire : fumier composté, 2 sacs manquants', () async {
          final pr = await p.produit('Fumier compost');
          final a = await p.stocks.enregistrerEcart(productId: pr.id, stockPhysique: pr.stockQty - 2, motif: StocksRepository.motifs[1], quand: p.maintenant());
          p.noter('stock_adjustments', a.id);
        });
        await _geste(p, 'vente au bureau : 2 Poulet goliath de ESSAI-B', () => _vente(p, 'Poulet goliath', 2, 3500, bande: 'ESSAI-B'));
      case 2:
        await _geste(p, 'achat de 2 flacons d\'antibiotique', () async {
          final f = (await p.db.select(p.db.suppliers).get()).firstWhere((s) => s.name == 'Provenderie ESSAI', orElse: () => throw StateError('fournisseur pas encore reçu'));
          final id = await p.achats.enregistrer(
            fournisseurId: f.id,
            lignes: [LigneSaisieAchat(produit: await p.produit('Antibiotique'), quantite: 2, prixUnitaire: 4500)],
            modePaiement: 'especes',
            compteId: await _compteCaisse(p),
            montantPaye: 9000,
            date: p.jour,
          );
          p.noter('purchases', id);
        });
        await _geste(p, 'ajout de stock : 5 Lapin vivant', () async {
          final a = await p.stocks.ajouterStock(date: p.jour, productId: (await p.produit('Lapin vivant')).id, quantite: '5');
          p.noter('stock_adjustments', a.id);
        });
      default:
        await _geste(p, 'inventaire : vitamines, 1 sachet en trop', () async {
          final pr = await p.produit('Vitamines');
          final a = await p.stocks.enregistrerEcart(productId: pr.id, stockPhysique: pr.stockQty + 1, motif: StocksRepository.motifs[5], quand: p.maintenant());
          p.noter('stock_adjustments', a.id);
        });
    }
    if (p.alea.nextBool()) await p.synchroniser('bureau, en cours de journée ${d + 1}');
  }

  Future<void> _journeeCaisse(_Poste p, int d) async {
    final bandeDuJour = p.alea.nextBool() ? 'ESSAI-A' : 'ESSAI-B';
    await _geste(p, 'vente : Poulet goliath de $bandeDuJour', () => _vente(p, 'Poulet goliath', 1 + p.alea.nextInt(3), 3500, bande: bandeDuJour));
    await _geste(p, 'vente : 2 sacs de fumier composté (mobile money)', () => _vente(p, 'Fumier compost', 2, 1500, mode: 'mobile_money'));

    // Un envoi lancé SANS l'attendre (bouton pressé), pendant que la caisse continue : la vente suivante tombe
    // pendant l'envoi de la précédente.
    final envoi = p.synchroniser('${p.nom}, envoi en arrière-plan, journée ${d + 1}');
    await _geste(p, 'vente : Lapin vivant de CUN-2026-01', () => _vente(p, 'Lapin vivant', 1, 6000, bande: 'CUN-2026-01'));
    await _geste(p, 'vente pendant l\'envoi : Poulet goliath de ESSAI-A', () => _vente(p, 'Poulet goliath', 1, 3500, bande: 'ESSAI-A'));
    await envoi;

    if (d == 0 && p == caisse1) {
      await _geste(p, 'client « ESSAI Client Commun » (même client qu\'au bureau, autre écriture du téléphone)', () async {
        final c = await p.clients.creerClient(const FormulaireClient(nom: 'Essai client commun', telephone: '97112233'));
        p.noter('customers', c.id);
      });
    }
    if (d == 2 && p == caisse2) {
      await _geste(p, 'client « ESSAI Client Commun » saisi une troisième fois', () async {
        final c = await p.clients.creerClient(const FormulaireClient(nom: 'ESSAI CLIENT COMMUN', telephone: '+22997112233'));
        p.noter('customers', c.id);
      });
    }
    if (d == 1 && p == caisse1) {
      await _geste(p, 'avance de 5 000 FCFA d\'un client connu', () async {
        final client = (await p.db.select(p.db.customers).get()).firstWhere((c) => c.isActive && c.syncStatus == SyncStatus.synced);
        final a = await p.clients.enregistrerAvance(clientId: client.id, montant: 5000, compteId: await _compteCaisse(p), motif: 'Commande de poulets (essai)', date: p.jour);
        p.noter('customer_advances', a.id);
      });
    }
    if (d >= 1) {
      await _geste(p, 'vente à crédit à un client connu', () async {
        final client = (await p.db.select(p.db.customers).get()).firstWhere((c) => c.isActive && c.syncStatus == SyncStatus.synced);
        await _vente(p, 'Fumier compost', 1, 1500, mode: 'credit', clientId: client.id);
      });
    }
  }

  Future<void> _journeeElevage(int d) async {
    final p = elevage;
    for (final code in ['ESSAI-A', 'ESSAI-B']) {
      await _geste(p, 'fiche du jour de $code', () async {
        final b = await p.bande(code);
        final f = await p.fiches.enregistrer(lotId: b.id, jour: p.jour, achat: 0, ne: 0, mort: p.alea.nextInt(3), don: 0, aliment: 12.5);
        p.noter('fiches', '${b.id}|${_jourIso(p.jour)}');
        mortsSaisis['${b.id}|${_jourIso(p.jour)}'] = f.mort;
        journaliser('${p.nom}  · fiche ${f.id} ($code, ${_jourIso(p.jour)}) : ${f.mort} mort(s)');
      });
    }
    if (d == 1) {
      await _geste(p, 'soin : vitamines sur ESSAI-B (sans délai d\'attente)', () async {
        final s = await p.soins.enregistrer(lotId: (await p.bande('ESSAI-B')).id, typeAction: 'Traitement', produit: 'Vitamines AD3E', dose: '1 g/L', cout: 2500, quand: p.maintenant());
        p.noter('veterinary_records', s.id);
      });
    }
    if (d == 2) {
      await _geste(p, 'transfert de 10 sujets ESSAI-A → ESSAI-B', () async {
        final t = await p.transferts.creer(sourceLotId: (await p.bande('ESSAI-A')).id, targetLotId: (await p.bande('ESSAI-B')).id, jour: p.jour, quantite: 10, motif: 'Essai S-T9');
        p.noter('livestock_transfers', t.id);
      });
    }
    // L'animalier corrige sa fiche en fin de journée (un mort de plus), parfois pendant un envoi.
    final envoi = p.alea.nextBool() ? p.synchroniser('élevage, envoi en arrière-plan, journée ${d + 1}') : Future<SyncOutcome?>.value();
    await _geste(p, 'correction de la fiche ESSAI-A : un mort de plus', () async {
      final b = await p.bande('ESSAI-A');
      final f = await p.fiches.chargerJour(b.id, p.jour);
      if (f == null) throw StateError('fiche absente');
      final g = await p.fiches.enregistrer(lotId: b.id, jour: p.jour, achat: f.achat, ne: f.ne, mort: f.mort + 1, don: f.don, aliment: f.feedQtyKg);
      mortsSaisis['${b.id}|${_jourIso(p.jour)}'] = g.mort;
      journaliser('${p.nom}  · fiche ${g.id} (ESSAI-A, ${_jourIso(p.jour)}) : ${g.mort} mort(s), état ${f.syncStatus.name} avant correction');
    });
    await envoi;
  }

  Future<void> _journeeCompta(int d) async {
    await _pause(compta);
    await compta.synchroniser('comptabilité, journée ${d + 1}');
  }

  /// Écritures faites AU WEB pendant que les postes travaillent : le tirage doit les ramener (curseur S-T4).
  Future<void> _journeeWeb(int d, DateTime jour) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (d == 1) {
      final r = await _serveur(['vente-web', jsonEncode({
        'produit': (await bureau.produit('Poulet goliath')).id,
        'lot': (await bureau.bande('ESSAI-A')).id,
        'quantite': 2,
        'montant': 7000,
        'jour': _jourIso(jour),
      })]);
      webVentes.add(r['vente'] as String);
      evenement('Web : vente de 2 Poulet goliath (ESSAI-A) du ${_jourFr(jour)} par la caisse web — ${r['vente']}');
    }
    if (d == 2) {
      final r = await _serveur(['ration-web', jsonEncode({'espece': 'aviculture', 'grammes': 777})]);
      rationWeb = r['ration'] as String;
      grammesWeb = r['grammes'] as int;
      evenement('Web : ration aviculture portée à 777 g/jour (Paramètres Élevage)');
    }
  }

  // ── Invariants ──────────────────────────────────────────────────────────────────────────────────────────────

  /// Refus attendus dans CE scénario : AUCUN. Chaque saisie est recevable (droits du rôle, dates ouvertes, stocks
  /// non bloquants). Le seul refus métier de la synchronisation entre postes — deux saisies d'élevage DIFFÉRENTES
  /// pour la même (bande, jour), « Une fiche existe deja… » — ne peut pas naître ici : un seul animalier saisit, et
  /// les fiches nées d'une vente au comptoir sont fusionnées (S-T9). Avant S-T9, toutes les fiches de l'animalier
  /// étaient refusées ainsi dès qu'un comptoir avait vendu dans la bande le même jour (graine 42 : 8 sur 8).
  static final _refusAttendus = <RegExp>[];

  static bool refusAttendu(SyncConflict c) =>
      c.reason.trim().isNotEmpty && _refusAttendus.any((r) => r.hasMatch(c.reason));

  /// Jours (`AAAA-MM-JJ`) des fiches refusées d'un poste : un écart du contrôle de cohérence sur les fiches de ces
  /// jours-là est la conséquence attendue du refus (le poste garde sa copie refusée, jamais écrasée).
  Future<Set<String>> joursDeFichesRefusees(_Poste p) async {
    final jours = <String>{};
    for (final c in conflits[p.nom] ?? const <SyncConflict>[]) {
      if (c.sourceTable != 'livestock_daily_entries') continue;
      final f = await (p.db.select(p.db.livestockDailyEntries)..where((t) => t.id.equals(c.recordId))).getSingleOrNull();
      if (f != null) jours.add(_jourIso(f.entryDate));
    }
    return jours;
  }

  /// Dernier nombre de morts saisi par l'animalier, par (bande, jour) : c'est ce que le serveur doit détenir.
  final mortsSaisis = <String, int>{};

  /// (bande, jour) des fiches de l'animalier refusées (attendu, motivé) : leur saisie reste au poste.
  final clesRefuseesElevage = <String>{};

  final ecartsExpliques = <String, List<String>>{};
  final ecartsInexpliques = <String, List<String>>{};

  Future<void> _classerEcarts() async {
    for (final p in postes) {
      final excuses = await joursDeFichesRefusees(p);
      for (final t in coherence[p.nom]?.tables ?? const <TableCoherence>[]) {
        for (final l in t.ecarts) {
          final texte = '${t.table} ${l.jour} : poste ${l.poste} / serveur ${l.serveur}';
          if (t.table == 'livestock_daily_entries' && excuses.contains(l.jour)) {
            (ecartsExpliques[p.nom] ??= []).add('$texte (fiche refusée ce jour-là)');
          } else {
            (ecartsInexpliques[p.nom] ??= []).add(texte);
          }
        }
      }
    }
  }

  void verifier() {
    expect(etatServeur, isNotEmpty, reason: 'l\'état du serveur n\'a pas pu être relevé');

    for (final p in postes) {
      expect(p.erreursInattendues, isEmpty,
          reason: '${p.nom} : erreur ni réseau ni refus du serveur pendant l\'essai — ${p.erreursInattendues.join(' | ')}');
      expect(enAttenteFin[p.nom], isEmpty,
          reason: '${p.nom} : des saisies sont encore en attente après le rétablissement : ${enAttenteFin[p.nom]}');
      final inattendus = [for (final c in conflits[p.nom]!) if (!refusAttendu(c)) '${c.sourceTable} ${c.recordId} : « ${c.reason} »'];
      expect(inattendus, isEmpty, reason: '${p.nom} : refus du serveur NON attendus (ou sans motif) : $inattendus');
      expect(coherence[p.nom], isNotNull, reason: '${p.nom} : le contrôle de cohérence S-T6 n\'a pas pu se faire');
      expect(ecartsInexpliques[p.nom] ?? const [], isEmpty,
          reason: '${p.nom} : le contrôle de cohérence S-T6 montre des écarts : ${ecartsInexpliques[p.nom]}');
      expect(webRecu[p.nom], isEmpty, reason: '${p.nom} : écritures du web non reçues : ${webRecu[p.nom]}');
    }

    // Aucune saisie perdue, aucune en double : chaque identifiant saisi sur un poste existe UNE fois au serveur —
    // sauf les fiches refusées (attendu : la (bande, jour) est tenue par la fiche d'un autre poste).
    final refusees = {for (final p in postes) for (final c in conflits[p.nom]!) c.recordId};
    final presence = (etatServeur['presence'] as Map? ?? {}).cast<String, dynamic>();
    final perdues = <String>[];
    final doublees = <String>[];
    for (final MapEntry(key: table, value: ids) in presence.entries) {
      for (final MapEntry(key: id, value: n) in (ids as Map).cast<String, int>().entries) {
        if (n == 0 && !refusees.contains(id)) perdues.add('$table $id');
        if (n > 1) doublees.add('$table $id ($n fois)');
      }
    }
    expect(perdues, isEmpty, reason: 'saisies des postes ABSENTES du serveur : $perdues');
    expect(doublees, isEmpty, reason: 'saisies des postes présentes PLUSIEURS FOIS au serveur : $doublees');

    final doublons = (etatServeur['doublons'] as Map).cast<String, dynamic>();
    expect(doublons['fiches_bande_jour'], isEmpty, reason: 'deux fiches pour une même (bande, jour) au serveur');
    expect(doublons['mouvements_par_reference'], isEmpty, reason: 'un ajustement de stock rejoué plusieurs fois');
    expect(doublons['mouvements_de_vente'], isEmpty, reason: 'une vente a décrémenté le stock plus (ou moins) d\'une fois par ligne');
    expect(doublons['clients_meme_cle'], isEmpty, reason: 'le même client (nom + téléphone) existe plusieurs fois : fusion S-T5 en défaut');
    expect(doublons['fournisseurs_meme_cle'], isEmpty, reason: 'le même fournisseur existe plusieurs fois');

    final fiches = (etatServeur['fiches_vente'] as Map).cast<String, dynamic>();
    final fausses = [
      for (final MapEntry(key: cle, value: f) in fiches.entries)
        if ((f['apres'] ?? 0) - f['avant'] != f['attendu'])
          '$cle : vente ${f['avant']} → ${f['apres']}, attendu +${f['attendu']}',
    ];
    expect(fausses, isEmpty, reason: 'ventes comptées deux fois, ou zéro fois, sur une fiche (15.30) : $fausses');

    final stocks = (etatServeur['stocks'] as Map).cast<String, dynamic>();
    final derives = [
      for (final s in stocks.values)
        if ((s['ecart_fin'] as num) != (s['ecart_ouverture'] as num))
          '${s['nom']} : stock − grand livre = ${s['ecart_ouverture']} avant, ${s['ecart_fin']} après',
    ];
    expect(derives, isEmpty, reason: 'stock du produit ≠ somme de son grand livre (AdjustStockAction contourné) : $derives');

    // La saisie de l'animalier (morts) est arrivée au serveur, quelle que soit la fiche qui tient la (bande, jour) —
    // sauf refus attendu et motivé, qui reste au poste pour que l'éleveur tranche.
    final fichesApres = (etatServeur['fiches_apres'] as Map).cast<String, dynamic>();
    final mortsPerdus = <String>[];
    mortsSaisis.forEach((cle, morts) {
      final auServeur = (fichesApres[cle] as Map?)?['mort'];
      if (auServeur != morts && !clesRefuseesElevage.contains(cle)) {
        mortsPerdus.add('$cle : $morts saisis au poste, $auServeur au serveur');
      }
    });
    expect(mortsPerdus, isEmpty, reason: 'morts saisis par l\'animalier absents du serveur (saisie perdue) : $mortsPerdus');

    final journal = (etatServeur['journal'] as Map).cast<String, dynamic>();
    expect(journal['debit'], journal['credit'], reason: 'journal comptable déséquilibré (débit ≠ crédit)');
    expect(journal['desequilibrees'], isEmpty, reason: 'écritures déséquilibrées : ${journal['desequilibrees']}');
  }

  // ── Rapport ─────────────────────────────────────────────────────────────────────────────────────────────────
  String rapport() {
    final b = StringBuffer()
      ..writeln('ESSAI À PLUSIEURS POSTES — ticket S-T9 (méthode TATACORA)')
      ..writeln('Graine : $graine   Journées : $jours   Base : $base   Serveur : $adresse')
      ..writeln('Rejouer : agrierp_flutter/outils/essai_multipostes.sh $graine')
      ..writeln('Début : $debut   Durée : ${DateTime.now().difference(debut).inSeconds} s')
      ..writeln();
    b.writeln('ÉVÉNEMENTS');
    for (final e in _evenements) {
      b.writeln('  $e');
    }
    b.writeln();
    b.writeln('COMPTEURS PAR POSTE');
    for (final p in (_postesOuVide())) {
      b.writeln('  ${p.nom} (${p.compte}, ${p.role}) — ${p.perturbateur.requetes} requêtes perturbables');
      b.writeln('    coupures : ${p.perturbateur.compteurs}');
      b.writeln('    synchronisations : ${p.resultats}');
      b.writeln('    saisies : ${{for (final e in p.saisies.entries) e.key: e.value.length}}');
      b.writeln('    en attente à la fin : ${enAttenteFin[p.nom]}');
      for (final c in conflits[p.nom] ?? const <SyncConflict>[]) {
        b.writeln('    refus ${refusAttendu(c) ? '(attendu)' : '(NON ATTENDU)'} ${c.sourceTable} ${c.recordId} : ${c.reason}');
      }
      for (final e in ecartsExpliques[p.nom] ?? const <String>[]) {
        b.writeln('    écart de cohérence expliqué : $e');
      }
      for (final e in ecartsInexpliques[p.nom] ?? const <String>[]) {
        b.writeln('    ÉCART DE COHÉRENCE : $e');
      }
      for (final e in webRecu[p.nom] ?? const <String>[]) {
        b.writeln('    WEB NON REÇU : $e');
      }
      for (final e in p.erreursInattendues) {
        b.writeln('    ERREUR INATTENDUE : $e');
      }
    }
    b.writeln();
    b.writeln('SERVEUR (fin d\'essai)');
    b.writeln(const JsonEncoder.withIndent('  ').convert(etatServeur));
    b.writeln();
    b.writeln('JOURNAL');
    for (final l in _journal) {
      b.writeln(l);
    }
    return b.toString();
  }

  List<_Poste> _postesOuVide() {
    try {
      return postes;
    } catch (_) {
      return const [];
    }
  }

  Future<void> fermer() async {
    for (final p in _postesOuVide()) {
      await p.fermer();
    }
  }
}

String _jourIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _jourFr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
