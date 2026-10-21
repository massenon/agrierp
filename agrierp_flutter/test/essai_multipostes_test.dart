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
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/elevage/bandes_repository.dart';
import 'package:agrierp/features/elevage/reproducteurs_repository.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/sujets_entrees_repository.dart';
import 'package:agrierp/features/elevage/parametres_elevage_repository.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/elevage/soins_vaccins_repository.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_repository.dart';
import 'package:agrierp/features/elevage/transferts_repository.dart';
import 'package:agrierp/features/rapports/rapports_repository.dart';
import 'package:agrierp/features/stocks/produits_repository.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:agrierp/features/sync/coherence_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'coffre_memoire.dart';
import 'depenses_aide.dart';

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
/// Ticket S-T12 — L'ESSAI COUVRE TOUT CE QUI SE SYNCHRONISE (cinq journées au moins) : retours, remboursements et
/// règlements fournisseurs, achats à crédit, imputations d'avances (dont une sur la créance d'une vente à crédit du même
/// envoi), produits créés au poste (et le même produit créé au web : fusion S-T5), dépenses, Paramètres Élevage modifiés
/// au poste, infirmerie, calendrier vétérinaire, archivage d'un soin, étapes d'un cycle de reproduction ; une session
/// refusée au web (appairage révoqué, compte désactivé) puis la reconnexion ; trois journées hors ligne pour la
/// deuxième caisse (envoi par lots H13b, tirage en plusieurs pages S-T4) ; un inventaire compté pendant qu'un mouvement
/// ANTÉRIEUR attend sur un poste hors ligne (S-T12, reste de S-T10) ; la demande de synchronisation du web (S-T6) ; la
/// réinitialisation des données au web en fin d'essai (15.50). Invariants ajoutés : dettes, créances, avances et
/// créances sur fournisseurs justes au centime (métier = grand livre), trésorerie concordante dans les DEUX livres,
/// dépenses comptabilisées une fois, aucun refus inattendu.
///
/// Ticket U13 — LA PAIE ET LES DÉPENSES DESCENDENT : le web règle une paie (Gestion de la Paie) et archive une dépense
/// saisie à un poste (Saisie des Dépenses) ; à la fin, le « Recettes et Dépenses » de CHAQUE poste qui ouvre les
/// rapports (bureau, comptabilité) doit être celui du web sur la même période — totaux ET lignes (date, libellé,
/// montant), paie comprise — et la dépense archivée doit l'être sur chaque poste qui la détient.
///
/// Rejouer : `outils/essai_multipostes.sh <graine>`. ⚠️ Le rejeu est fidèle pour les décisions de coupure de CHAQUE
/// poste (une suite aléatoire par poste, tirée dans l'ordre de ses propres requêtes) ; l'entrelacement des cinq postes
/// au serveur, lui, dépend de l'horloge — comme à la ferme.
void main() {
  final env = Platform.environment;
  final adresse = env['AGRIERP_ESSAI_URL'];
  final graine = int.tryParse(env['AGRIERP_ESSAI_GRAINE'] ?? '') ?? 20261019;
  // Ticket S-T12 — cinq journées au moins : la deuxième caisse reste hors ligne trois journées pleines, puis revient.
  final nombreDeJours = int.tryParse(env['AGRIERP_ESSAI_JOURS'] ?? '') ?? 5;
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

      if (nombreDeJours < 5) {
        fail('Ticket S-T12 : l\'essai demande au moins 5 journées (AGRIERP_ESSAI_JOURS=$nombreDeJours) — trois journées '
            'hors ligne pour la deuxième caisse, puis son retour.');
      }
      final essai = _Essai(
        adresse: adresse,
        graine: graine,
        jours: nombreDeJours,
        base: env['AGRIERP_ESSAI_BASE'] ?? '?',
        fuseau: env['AGRIERP_ESSAI_FUSEAU'] ?? env['TZ'] ?? '?',
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
    timeout: const Timeout(Duration(minutes: 30)),
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
  ///
  /// ⚠️ Ticket S-T12 — 14 000 octets (6 000 avant) : au-dessus de la plus grosse JOURNÉE COUPLÉE de l'essai (fiches et
  /// ventes d'un jour de la caisse restée hors ligne, ≈ 12 Ko), au-dessous d'un lot de 50 (≈ 20 Ko). Une journée couplée
  /// est INDIVISIBLE (H13b) : plus grosse que la limite, elle est refusée (« envoi trop volumineux (413) », S-T1) et ses
  /// ventes ne partent pas — ce que 6 000 octets provoquaient dès 20 ventes d'un comptoir dans la journée. En
  /// production la limite est celle de l'hébergement (PHP `post_max_size`, un éventuel ModSecurity) : à vérifier.
  int limiteCorps = 14000;

  int requetes = 0;
  final compteurs = <String, int>{};

  /// Ticket S-T12 — taille de page imposée aux tirages (`taille`, S-T4) : le poste qui revient de trois journées hors
  /// ligne tire en plusieurs pages, comme à la ferme après une semaine (l'essai n'a pas une semaine de saisies).
  int? taillePage;

  /// Ticket S-T12 — pages et envois observés à partir du retour du poste ([observer]).
  bool observer = false;
  int pagesMax = 0;
  final lignesParEnvoi = <int>[];

  void _compter(String cas, RequestOptions o, [String detail = '']) {
    compteurs[cas] = (compteurs[cas] ?? 0) + 1;
    journal('$poste  ${o.method} ${o.path}${o.queryParameters.isEmpty ? '' : ' ${o.queryParameters}'}  → $cas$detail');
  }

  static bool _concerne(RequestOptions o) => o.path.startsWith('/api/sync/pull') || o.path.startsWith('/api/sync/push');

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.path.startsWith('/api/sync/push') && options.data is Map) {
      journal('$poste  POST /api/sync/push  ← ${resumeCorps(options.data as Map)}');
      if (observer) {
        lignesParEnvoi.add((options.data as Map).values.whereType<List>().fold<int>(0, (n, l) => n + l.length));
      }
    }
    if (options.path.startsWith('/api/sync/pull') && taillePage != null) {
      options.queryParameters = {...options.queryParameters, 'taille': taillePage};
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
    final page = response.requestOptions.queryParameters['page'];
    if (observer && response.requestOptions.path.startsWith('/api/sync/pull') && page is int && page > pagesMax) {
      pagesMax = page;
      journal('$poste  GET /api/sync/pull  → page $page reçue (taille $taillePage)');
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
  SyncEngine? _moteur;
  SyncEngine get moteur => _moteur!;

  /// La synchronisation automatique de la SESSION en cours : une reconnexion en crée une neuve (S-T1, S-T3).
  late SynchronisationAutomatique auto;

  /// Ticket S-T12 — tentatives faites par la synchronisation AUTOMATIQUE (pas le bouton).
  int tentativesAuto = 0;

  /// Jour simulé du poste (minuit) et horloge qui en découle (l'heure réelle, ce jour-là) — à l'heure du BÉNIN
  /// (S-T11), quel que soit le fuseau du processus (`TZ`, paramètre `ESSAI_FUSEAUX` du script).
  DateTime jour = HeureBenin.aujourdhui();
  DateTime maintenant() {
    final n = HeureBenin.maintenant();
    return DateTime(jour.year, jour.month, jour.day, n.hour, n.minute, n.second, n.millisecond);
  }

  final _Saisies saisies = {};
  void noter(String table, String id) => (saisies[table] ??= []).add(id);

  final resultats = <String, int>{};
  final erreursInattendues = <String>[];

  /// Connexion réelle (`POST /api/auth/login`, jeton nommé d'après le poste). Une REconnexion (après un 401) garde la
  /// base et le moteur du poste, et ouvre une nouvelle session de synchronisation automatique (comme `SocleAccueil`).
  Future<void> connecter(String motDePasse) async {
    final auth = AuthService(client: client, deviceName: nom, coffre: CoffreMemoire());
    await auth.connecter(identifiant: compte, motDePasse: motDePasse);
    _moteur ??= SyncEngine(database: db, client: client, deviceId: nom, connectivity: connectivite);
    auto = nouvelleAuto();
  }

  /// [demande] (ticket S-T6) : la session interroge le serveur toutes les 30 s, sans autre déclencheur que l'intervalle.
  SynchronisationAutomatique nouvelleAuto({Duration? intervalle, bool demande = false}) => SynchronisationAutomatique(
    synchroniser: () {
      tentativesAuto++;
      return moteur.synchroniser();
    },
    changementsReseau: const Stream.empty(),
    intervalle: intervalle ?? Duration(seconds: 6 + rang),
    gestes: demande ? null : gestes,
    delaiAgregation: const Duration(milliseconds: 300),
    demandeDuServeur: demande ? moteur.demandeDuServeur : null,
  );

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
  BandesRepository get bandes => BandesRepository(database: db, deviceId: nom, gestes: gestes, horloge: maintenant);
  ReproducteursRepository get reproducteurs => ReproducteursRepository(database: db, deviceId: nom, gestes: gestes, horloge: maintenant);
  SujetsEntreesRepository get sujetsEntrees => SujetsEntreesRepository(database: db, fiches: fiches, horloge: maintenant);
  DepensesRepository get depenses => DepensesRepository(database: db, deviceId: nom);
  ProduitsRepository get produits => ProduitsRepository(database: db);
  ParametresElevageRepository get parametresElevage => ParametresElevageRepository(database: db, maintenant: maintenant);
  SoinsVaccinsRepository get soinsVaccins => SoinsVaccinsRepository(database: db, soins: soins);
  SuiviReproductionRepository get reproduction => SuiviReproductionRepository(database: db, deviceId: nom);

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
    if (_moteur != null) auto.arreter();
    await db.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// L'essai
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

class _Essai {
  _Essai({required this.adresse, required this.graine, required this.jours, required this.base, required this.fuseau});

  final String adresse;
  final int graine;
  final int jours;
  final String base;

  /// Ticket S-T11 — fuseau horaire des postes (processus Dart), le serveur restant à l'heure du Bénin.
  final String fuseau;
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

  /// Ticket U13 — la paie réglée au web, la dépense d'un poste archivée au web, et pour chaque poste qui ouvre les
  /// rapports, ce que son « Recettes et Dépenses » diffère de celui du web (vide : identique).
  String? paieWeb;
  String? depenseArchiveeWeb;
  final recettesDepenses = <String, List<String>>{};
  Map<String, dynamic> recettesDepensesWeb = {};

  void journaliser(String ligne) {
    final t = DateTime.now().difference(debut);
    _journal.add('[${(t.inMilliseconds / 1000).toStringAsFixed(1).padLeft(6)} s] $ligne');
  }

  void evenement(String ligne) {
    journaliser('— $ligne');
    _evenements.add(ligne);
  }

  // ── Côté serveur (le « web » et l'état final) ─────────────────────────────────────────────────────────────────
  /// Ticket S-T13 — interblocages de la caisse du web, rejoués par le serveur (`TransactionRejouable`).
  final interblocagesWeb = <String>[];

  Future<Map<String, dynamic>> _serveur(List<String> arguments) async {
    final r = await Process.run('php', [
      '${Directory.current.path}/outils/essai_multipostes_serveur.php',
      dossierLaravel,
      ...arguments,
    ], workingDirectory: dossierLaravel);
    if (r.exitCode != 0) {
      throw StateError('Commande serveur « ${arguments.first} » en échec (${r.exitCode}) : ${r.stdout}\n${r.stderr}');
    }
    try {
      final corps = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      for (final i in (corps['interblocages'] as List?) ?? const []) {
        interblocagesWeb.add('$i');
        evenement('Web : essai de vente rejoué par le serveur après un interblocage MariaDB (S-T13) — $i');
      }
      return corps;
    } on FormatException {
      // Une exception rendue par la console de Laravel (code de sortie 0) : le message entier, pas « caractère inattendu ».
      throw StateError('Commande serveur « ${arguments.first} » : réponse illisible : ${r.stdout}\n${r.stderr}');
    }
  }

  Future<void> derouler() async {
    _travail = await Directory.systemTemp.createTemp('agrierp-essai-');
    _instantane = '${_travail.path}/instantane.json';
    journaliser('Essai S-T9 — graine $graine, $jours journées, base $base, serveur $adresse, postes en $fuseau '
        '(décalage ${DateTime.now().timeZoneOffset.inHours} h)');

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
      await _connecter(p);
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
    final aujourdHui = HeureBenin.aujourdhui();
    for (var d = 0; d < jours; d++) {
      final jour = HeureBenin.plusJours(aujourdHui, -(jours - 1 - d));
      for (final p in postes) {
        p.jour = jour;
      }
      // Ticket S-T12 — la deuxième caisse (le câble du comptoir) reste hors ligne TROIS journées pleines, puis revient :
      // elle saisit, elle n'envoie rien ; à son retour, envoi par lots (H13b) et tirage en plusieurs pages (S-T4).
      caisse2.connectivite.enLigne = !_caisse2HorsLigne(d);
      // Le bureau est hors ligne la première journée (le même produit est créé au web : fusion S-T5) ; l'élevage la
      // troisième (une saillie et sa palpation partent dans le même envoi).
      bureau.connectivite.enLigne = d != 0;
      elevage.connectivite.enLigne = d != 2;
      if (d == 4) {
        caisse2.perturbateur
          ..taillePage = 40
          ..observer = true;
      }
      await _avantLaJournee(d);
      evenement('Journée ${d + 1}/$jours (${_jourFr(jour)})'
          '${_caisse2HorsLigne(d) ? ' — poste-caisse-2 hors ligne toute la journée' : ''}'
          '${d == 0 ? ' — poste-bureau hors ligne' : ''}${d == 2 ? ' — poste-elevage hors ligne' : ''}'
          '${d == 4 ? ' — poste-caisse-2 de retour' : ''}');

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
      await _apresLaJournee(d);
    }

    // ── Rétablissement : réseau parfait, synchronisations jusqu'à ce que plus rien ne soit en attente ────────────
    for (final p in postes) {
      p.auto.arreter();
      p.perturbateur.actif = false;
      p.connectivite.enLigne = true;
    }
    evenement('Rétablissement : réseau parfait');
    for (var tour = 1; tour <= 12; tour++) {
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
      await _jusquAAboutir(p, 'tirage final');
    }

    // ── Ticket S-T6 : la demande de synchronisation du web, servie dans les 30 s ──────────────────────────────────
    await _demandeDuWeb();
    for (final p in postes) {
      await _jusquAAboutir(p, 'tirage final, après la demande du web');
    }

    // ── Ticket U13 : « Recettes et Dépenses » de chaque poste = celui du web, sur la fenêtre de l'essai ────────────
    await _comparerRecettesDepenses(HeureBenin.plusJours(aujourdHui, -(jours + 2)), aujourdHui);

    // ── Relevés ──────────────────────────────────────────────────────────────────────────────────────────────
    final depuis = HeureBenin.plusJours(aujourdHui, -(jours + 2));
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
      final compte = inventaireCompte;
      if (compte != null) {
        final local = await (p.db.select(p.db.products)..where((t) => t.id.equals(compte.produit))).getSingleOrNull();
        if (local != null) stocksComptesAuPoste[p.nom] = local.stockQty;
      }
      final web = inventaireWeb;
      if (web != null) {
        final local = await (p.db.select(p.db.products)..where((t) => t.id.equals(web.produit))).getSingleOrNull();
        if (local != null) stocksInventaireWebAuPoste[p.nom] = local.stockQty;
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
    await _releverLignesLocales();

    // ── Ticket S-T12 : la réinitialisation des données au web, en fin d'essai (15.50) ─────────────────────────────
    await _reinitialisation();
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

  Future<String> _vente(_Poste p, String produit, int quantite, double prixUnitaire, {String? bande, String mode = 'especes', String? clientId}) async {
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
    return v.id;
  }

  /// Un achat du bureau par le VRAI dépôt, à l'instant simulé (comme l'écran, qui ne passe pas de date : l'achat est
  /// daté de l'instant de sa saisie).
  Future<String> _achat(_Poste p, String produit, double quantite, double prix, double paye) async {
    final f = (await p.db.select(p.db.suppliers).get()).firstWhere((s) => s.name == 'Provenderie ESSAI',
        orElse: () => throw StateError('fournisseur pas encore reçu'));
    final id = await p.achats.enregistrer(
      fournisseurId: f.id,
      lignes: [LigneSaisieAchat(produit: await p.produit(produit), quantite: quantite, prixUnitaire: prix)],
      modePaiement: 'especes',
      compteId: await _compteCaisse(p),
      montantPaye: paye,
      date: p.maintenant(),
    );
    p.noter('purchases', id);
    return id;
  }

  Future<String> _fournisseurEssai(_Poste p) async =>
      (await p.db.select(p.db.suppliers).get()).firstWhere((s) => s.name == 'Provenderie ESSAI').id;

  Future<String> _depense(_Poste p, String libelle, double montant) async {
    // Ticket DEP4 — le compte de charge se choisit dans le plan comptable (classe 6) reçu du serveur, plus dans une liste de catégories.
    final compteDeCharge = (await p.depenses.comptesDeCharge()).first.id;
    final e = await p.depenses.enregistrerUneLigne(
      date: p.jour,
      libelle: libelle,
      compteChargeId: compteDeCharge,
      montant: montant,
      compteTresorerieId: await _compteCaisse(p),
    );
    p.noter('expenses', e.id);
    return e.id;
  }

  /// Synchronise [p] jusqu'à ce que [condition] tienne (au plus [essais] fois, réseau perturbé) — l'utilisateur qui
  /// appuie sur « Synchroniser » jusqu'à voir arriver ce qu'il attend du serveur (une dette, une créance).
  Future<bool> _jusqua(_Poste p, String quoi, Future<bool> Function() condition, {int essais = 30}) async {
    for (var i = 0; i < essais; i++) {
      if (await condition()) return true;
      final r = await p.synchroniser('attente : $quoi');
      if (r == null) await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    final ok = await condition();
    if (!ok) journaliser('${p.nom} : $quoi — toujours absent après $essais synchronisations');
    return ok;
  }

  /// Une synchronisation (réseau rétabli) réessayée jusqu'à ce qu'elle aboutisse : un refus de débit (429 — les deux
  /// caisses partagent le compte « caisse », donc son crédit de requêtes par minute) passe en attendant, comme la
  /// synchronisation automatique le ferait (S-T1). Au plus [essais] fois.
  Future<void> _jusquAAboutir(_Poste p, String quoi, {int essais = 10}) async {
    for (var i = 0; i < essais; i++) {
      if (await p.synchroniser(quoi) != null) return;
      await Future<void>.delayed(const Duration(seconds: 7));
    }
    journaliser('${p.nom} : $quoi — toujours en échec après $essais tentatives');
  }

  /// Ticket S-T12 — la deuxième caisse est hors ligne les journées 2, 3 et 4 (index 1 à 3).
  bool _caisse2HorsLigne(int d) => d >= 1 && d <= 3;

  /// Gestes du web qui ouvrent une journée (avant ceux des postes).
  Future<void> _avantLaJournee(int d) async {
    switch (d) {
      case 2:
        // CFG-1 : l'administrateur révoque l'appairage de la caisse 1, qui continue de vendre.
        await _serveur(['revoquer', caisse1.nom]);
        evenement('Web : appairage de poste-caisse-1 révoqué (Paramètres → Postes & Appairage)');
      case 3:
        // La caisse 1 se reconnecte (mot de passe) : nouvelle session, synchronisation automatique neuve (S-T3).
        await _reconnecter(caisse1);
        // Le compte de la comptabilité est désactivé au web (ses jetons sont révoqués avec lui, S3).
        await _serveur(['desactiver', compta.compte]);
        evenement('Web : compte « ${compta.compte} » désactivé (Gestion des utilisateurs)');
      case 4:
        await _serveur(['reactiver', compta.compte]);
        evenement('Web : compte « ${compta.compte} » réactivé');
        await _reconnecter(compta);
    }
  }

  /// Ce qui se constate en fin de journée.
  Future<void> _apresLaJournee(int d) async {
    if (d == 2) sessionsRefusees[caisse1.nom] = await _suspendue(caisse1);
    if (d == 3) sessionsRefusees[compta.nom] = await _suspendue(compta);
  }

  /// Ticket S-T1 — la synchronisation AUTOMATIQUE d'un poste dont la session est refusée (401) s'arrête. Le
  /// déclencheur automatique est appelé (comme son intervalle le ferait), au plus cinq fois le temps qu'une tentative
  /// en cours finisse ; rend l'état constaté.
  Future<({bool suspendue, int tentatives})> _suspendue(_Poste p) async {
    for (var i = 0; i < 5 && !p.auto.suspendue; i++) {
      await p.auto.declencher();
      if (!p.auto.suspendue) await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final avant = p.tentativesAuto;
    // Suspendue : un geste, l'intervalle, plus rien ne part tout seul.
    p.gestes.signaler();
    await p.auto.declencher();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final r = (suspendue: p.auto.suspendue, tentatives: p.tentativesAuto - avant);
    evenement('${p.nom} : session refusée — synchronisation automatique ${r.suspendue ? 'SUSPENDUE' : 'NON suspendue'}'
        ', ${r.tentatives} tentative(s) automatique(s) ensuite ; en attente : ${await p.enAttente()}');
    return r;
  }

  /// Connexions au serveur, pour respecter son limiteur (5 par minute et par adresse : les cinq postes partagent
  /// 127.0.0.1).
  final _connexions = <DateTime>[];

  Future<void> _connecter(_Poste p) async {
    final recentes = _connexions.where((t) => DateTime.now().difference(t) < const Duration(seconds: 61)).toList()..sort();
    if (recentes.length >= 5) {
      final attente = recentes.first.add(const Duration(seconds: 62)).difference(DateTime.now());
      journaliser('${p.nom} : ${attente.inSeconds} s d\'attente avant la connexion (limiteur du serveur, 5 par minute)');
      await Future<void>.delayed(attente);
    }
    _connexions.add(DateTime.now());
    await p.connecter('AgriERP@2026');
  }

  /// Reconnexion après un refus de session : nouvelle connexion, nouvelle session (synchronisation à l'ouverture).
  Future<void> _reconnecter(_Poste p) async {
    p.auto.arreter();
    await _connecter(p);
    p.auto.demarrer(aussitot: true);
    evenement('${p.nom} : reconnecté (nouvelle session, synchronisation automatique reprise)');
  }

  /// Ticket S-T1 — état de la synchronisation automatique constaté après le refus de session, par poste.
  final sessionsRefusees = <String, ({bool suspendue, int tentatives})>{};

  Future<void> _journeeBureau(int d) async {
    final p = bureau;
    switch (d) {
      case 0:
        // Hors ligne toute la journée : tout part au premier envoi de la journée suivante.
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
        await _geste(p, 'achat de 3 sacs d\'aliment croissance (payé)', () => _achat(p, 'Aliment croissance', 3, 15000, 45000));
        await _geste(p, 'achat de 2 flacons d\'anti-coccidien (payé ; il sera retourné)', () async {
          achatARetourner = await _achat(p, 'Anti-coccidien', 2, 6000, 12000);
        });
        await _geste(p, 'achat de 4 sacs d\'aliment ponte, 24 000 F payés sur 64 000 (dette de 40 000 F)',
            () => _achat(p, 'Aliment ponte', 4, 16000, 24000));
        // Ticket S-T12 — produits créés au poste (15.15). Le premier, le web le crée aussi aujourd'hui (fusion S-T5) ;
        // un achat le désigne avant toute synchronisation (référence traduite au serveur, remplacée au poste).
        await _geste(p, 'produit « $produitFusionNom » (12 en stock) — le web crée le même', () async {
          final categorie = (await p.produit('Fumier compost')).categoryId!;
          final pr = await p.produits.creer(FormulaireProduit(nom: produitFusionNom, categorieId: categorie, unite: 'pain', mode: 'fourchette', prixMin: 500, prixMax: 700, stock: 12));
          p.noter('products', pr.id);
          produitFusionPoste = pr.id;
        });
        await _geste(p, 'achat de 6 « $produitFusionNom » (produit pas encore envoyé)', () async {
          produitFusionAchat = await _achat(p, produitFusionNom, 6, 400, 2400);
        });
        await _geste(p, 'produit « ESSAI Miel de la ferme (pot) » (20 en stock)', () async {
          final categorie = (await p.produit('Fumier compost')).categoryId!;
          final pr = await p.produits.creer(FormulaireProduit(nom: 'ESSAI Miel de la ferme (pot)', categorieId: categorie, unite: 'pot', mode: 'fourchette', prixMin: 2500, prixMax: 3000, stock: 20));
          p.noter('products', pr.id);
        });
        await _geste(p, 'dépense : carburant du groupe (15 000 F), libellé corrigé avant envoi (DEP1)', () async {
          depenseAModifier = await _depense(p, 'Carburant du groupe (essai)', 15000);
          // Ticket DEP1 — une dépense SANS pièce (pas encore envoyée) se modifie ; une fois comptabilisée elle est immuable.
          final d = await (p.db.select(p.db.expenses)..where((t) => t.id.equals(depenseAModifier!))).getSingle();
          final ligne = await (p.db.select(p.db.expenseLines)..where((l) => l.expenseId.equals(d.id))).getSingle();
          await p.depenses.enregistrerUneLigne(
            date: d.expenseDate,
            libelle: libelleDepenseModifiee,
            compteChargeId: ligne.chargeAccountId,
            montant: d.amount,
            compteTresorerieId: d.treasuryAccountId,
            idEnModification: d.id,
          );
        });
      case 1:
        await _geste(p, 'inventaire : fumier composté, 2 sacs manquants', () async {
          final pr = await p.produit('Fumier compost');
          final a = await p.stocks.enregistrerEcart(productId: pr.id, stockPhysique: pr.stockQty - 2, motif: StocksRepository.motifs[1], quand: p.maintenant());
          p.noter('stock_adjustments', a.id);
        });
        await _geste(p, 'vente au bureau : 2 Poulet goliath de ESSAI-B', () => _vente(p, 'Poulet goliath', 2, 3500, bande: 'ESSAI-B'));
        // F0.74 / 15.20 — retour de l'achat d'anti-coccidien (payé : il ouvre une créance sur le fournisseur).
        await _geste(p, 'retour fournisseur de l\'achat d\'anti-coccidien', () async {
          final r = await p.achats.enregistrerRetour(achatId: achatARetourner!, motif: 'Flacons abîmés à la livraison (essai)', date: p.maintenant());
          p.noter('purchase_returns', r.id);
          retourFait = true;
        });
        await _geste(p, 'dépense : réparation des abreuvoirs (8 000 F)', () async {
          depenseAArchiverPoste = await _depense(p, 'Réparation des abreuvoirs (essai)', 8000);
        });
      case 2:
        await _geste(p, 'achat de 2 flacons d\'antibiotique', () => _achat(p, 'Antibiotique', 2, 4500, 9000));
        await _geste(p, 'ajout de stock : 5 Lapin vivant', () async {
          final a = await p.stocks.ajouterStock(date: p.jour, productId: (await p.produit('Lapin vivant')).id, quantite: '5');
          p.noter('stock_adjustments', a.id);
        });
        await _inventairePendantUneVente();
        // Ticket U14 — une dépense que le web pourra archiver (U13) : celles des jours 1 et 2 sont modifiée et archivée
        // AU POSTE, et le web ne les touche pas.
        await _geste(p, 'dépense : eau du forage (4 000 F)', () => _depense(p, 'Eau du forage (essai)', 4000));
        // 15.16 — règlement d'une partie de la dette de l'achat à crédit (la dette doit être descendue au poste).
        final fournisseur = await _fournisseurEssai(p);
        await _jusqua(p, 'dette de Provenderie ESSAI', () async => await p.fournisseurs.du(fournisseur) > 0);
        await _geste(p, 'règlement fournisseur de 25 000 F', () async {
          final r = await p.fournisseurs.enregistrerReglement(fournisseurId: fournisseur, montant: 25000, compteId: await _compteCaisse(p), date: p.jour);
          p.noter('supplier_payments', r.id);
          reglements++;
        });
      case 3:
        await _geste(p, 'inventaire : vitamines, 1 sachet en trop', () async {
          final pr = await p.produit('Vitamines');
          final a = await p.stocks.enregistrerEcart(productId: pr.id, stockPhysique: pr.stockQty + 1, motif: StocksRepository.motifs[5], quand: p.maintenant());
          p.noter('stock_adjustments', a.id);
        });
        // 15.20 — remboursement de la créance ouverte par le retour (elle doit être descendue au poste).
        final fournisseur = await _fournisseurEssai(p);
        await _jusqua(p, 'créance sur Provenderie ESSAI', () async => await p.achats.creanceNette(fournisseur) > 0);
        await _geste(p, 'remboursement fournisseur de 12 000 F', () async {
          final r = await p.achats.enregistrerRemboursement(fournisseurId: fournisseur, montant: 12000, date: p.jour, compteId: await _compteCaisse(p));
          p.noter('supplier_refunds', r.id);
          remboursementFait = true;
        });
        await _achatAvantInventaireWeb();
        // Ticket U14 — « Saisie des Dépenses » du poste modifie et archive comme le web : le serveur rejoue les deux
        // gestes par `SaisieDepenseAction` (libellé corrigé ; contre-passation et trésorerie réintégrée).
        await _geste(p, 'dépense comptabilisée : sa modification est refusée au poste, son libellé reste (DEP1)', () async {
          // Le poste connaît la pièce de sa dépense dès que le tirage la lui a rapportée.
          await _jusqua(p, 'pièce de la dépense du carburant', () async =>
              (await (p.db.select(p.db.expenses)..where((t) => t.id.equals(depenseAModifier!))).getSingle()).accountingEntryId != null);
          final d = await (p.db.select(p.db.expenses)..where((t) => t.id.equals(depenseAModifier!))).getSingle();
          final ligne = await (p.db.select(p.db.expenseLines)..where((l) => l.expenseId.equals(d.id))).getSingle();
          Map<String, String>? refus;
          try {
            await p.depenses.enregistrerUneLigne(
              date: d.expenseDate,
              libelle: 'Libellé que le poste n\'a pas le droit de changer',
              compteChargeId: ligne.chargeAccountId,
              montant: d.amount,
              compteTresorerieId: d.treasuryAccountId,
              idEnModification: d.id,
            );
          } on DepenseRefusee catch (e) {
            refus = e.erreurs;
          }
          expect(refus, {'formulaire': DepensesRepository.messageDejaComptabilisee});
          _saisi('expenses', d.id, {'label': libelleDepenseModifiee, 'is_active': true});
        });
        await _geste(p, 'dépense : réparation des abreuvoirs archivée au poste (U14)', () async {
          await p.depenses.archiver(depenseAArchiverPoste!);
          _saisi('expenses', depenseAArchiverPoste!, {'is_active': false});
        });
      default:
        await _geste(p, 'dépense : électricité (6 000 F)', () => _depense(p, 'Électricité (essai)', 6000));
        final fournisseur = await _fournisseurEssai(p);
        await _geste(p, 'règlement du reste de la dette fournisseur', () async {
          final reste = await p.fournisseurs.du(fournisseur);
          if (reste <= 0) throw StateError('aucune dette restante au poste');
          final r = await p.fournisseurs.enregistrerReglement(fournisseurId: fournisseur, montant: reste, compteId: await _compteCaisse(p), date: p.jour);
          p.noter('supplier_payments', r.id);
          reglements++;
        });
    }
    if (p.alea.nextBool()) await p.synchroniser('bureau, en cours de journée ${d + 1}');
  }

  /// Ticket U14 — dépenses du bureau modifiée puis archivée au poste (le web n'archive ni l'une ni l'autre).
  String? depenseAModifier, depenseAArchiverPoste;
  static const libelleDepenseModifiee = 'Carburant du groupe électrogène (essai)';

  /// Ticket S-T12 — scénarios dont l'essai vérifie qu'ils ont bien eu lieu (un geste refusé au poste les ferait taire).
  String? achatARetourner;
  bool retourFait = false;
  bool remboursementFait = false;
  int reglements = 0;
  /// Décision BS-Q13 : changer l'identifiant du reproducteur enregistré est REFUSÉ au poste (le geste a bien eu lieu).
  bool identifiantRefuse = false;
  static const produitFusionNom = 'ESSAI Savon de karité (pain)';
  String? produitFusionPoste;
  String? produitFusionWeb;
  String? produitFusionAchat;

  /// Ticket S-T10 — INVENTAIRE SUR UN POSTE PENDANT QUE LE WEB ET UNE CAISSE VENDENT LE MÊME PRODUIT.
  ///
  /// Le bureau est hors ligne (son stock local de piment ignore donc ce qui suit) ; le web vend 3 sacs de piment ;
  /// le bureau compte ce que les rayons contiennent, moins 2 sacs réellement disparus ; une seconde plus tard la
  /// caisse 1 vend 1 sac. Puis le bureau revient en ligne et envoie son inventaire — APRÈS la vente de la caisse, au
  /// gré des coupures. Stock final attendu (à la main) : quantité comptée − 1. Avant S-T10, le poste envoyait son
  /// écart LOCAL (−5) et le serveur décomptait la vente du web une seconde fois : 3 sacs de moins, sans erreur.
  ///
  /// 🔴→✅ Ticket S-T12 — la caisse 2, hors ligne depuis la veille, a vendu du piment AVANT ce comptage : les rayons ne
  /// le contiennent plus (le comptage en tient compte), mais la vente n'arrive au serveur que deux jours plus tard. Avant
  /// S-T12, elle était décomptée EN PLUS du comptage : [pimentVenduHorsLigne] sacs de moins, sans erreur.
  Future<void> _inventairePendantUneVente() async {
    final p = bureau;
    p.connectivite.enLigne = false;
    evenement('poste-bureau hors ligne : inventaire du piment pendant que le web et la caisse 1 en vendent (S-T10)');
    try {
      final piment = await p.produit('Piment frais');
      final r = await _serveur(['vente-web', jsonEncode({
        'produit': piment.id,
        'quantite': 3,
        'montant': 3600,
        'jour': _jourIso(p.jour),
      })]);
      webVentes.add(r['vente'] as String);
      final rayon = (r['stock_apres'] as num).toDouble();
      evenement('Web : vente de 3 sacs de piment (${r['vente']}) — serveur : $rayon, poste-bureau : ${piment.stockQty}');

      // Les rayons : le stock du serveur, moins ce que la caisse 2 a vendu hors ligne (le serveur ne le sait pas
      // encore), moins 2 sacs réellement disparus.
      final compte = rayon - pimentVenduHorsLigne - 2;
      final a = await p.stocks.enregistrerEcart(
        productId: piment.id,
        stockPhysique: compte,
        motif: StocksRepository.motifs[1],
        quand: p.maintenant(),
      );
      p.noter('stock_adjustments', a.id);
      evenement('poste-bureau : inventaire du piment, $compte comptés (écart LOCAL ${a.type} ${a.quantity}, '
          'écart attendu au serveur : −2, puis −$pimentVenduHorsLigne régularisés à l\'arrivée de la vente de la caisse 2) '
          'à ${a.movementDate}');

      // Une seconde plus tard (le grand livre est daté à la seconde) : la caisse 1 vend un sac.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await _vente(caisse1, 'Piment frais', 1, 1200);
      inventaireCompte = (produit: piment.id, nom: piment.name, attendu: compte - 1);
    } finally {
      p.connectivite.enLigne = true;
    }
  }

  /// Ticket S-T10 — produit compté par le bureau et son stock final attendu (comptage − ventes postérieures).
  ({String produit, String nom, double attendu})? inventaireCompte;

  /// Ticket S-T12 — piment vendu par la caisse 2 hors ligne, AVANT le comptage du bureau.
  int pimentVenduHorsLigne = 0;

  /// Ticket S-T10 — stock du produit compté sur chaque poste après le tirage final (il se recale sur le serveur).
  final stocksComptesAuPoste = <String, double>{};

  /// 🔴→✅ Ticket S-T12 — UN ACHAT FAIT AVANT UN INVENTAIRE ET ARRIVÉ APRÈS LUI. Le bureau, hors ligne, reçoit 5 sacs
  /// d'aliment ponte et les range ; une seconde plus tard, le web fait l'inventaire de l'aliment ponte (Gestion des
  /// Stocks) : les rayons ont ces 5 sacs de plus que le serveur, moins 1 sac abîmé (écart web +4). Puis le bureau revient
  /// et envoie l'achat. Attendu (à la main) : le comptage du web, sans les 5 sacs une seconde fois. Avant S-T12 :
  /// l'achat daté de sa réception, compté en plus — 5 sacs de trop.
  Future<void> _achatAvantInventaireWeb() async {
    final p = bureau;
    await _jusqua(p, 'achats du bureau envoyés', () async => !(await p.enAttente()).containsKey('purchases'));
    p.connectivite.enLigne = false;
    evenement('poste-bureau hors ligne : achat d\'aliment ponte, puis inventaire de l\'aliment ponte au web (S-T12)');
    try {
      final pr = await p.produit('Aliment ponte');
      final achat = await _achat(p, 'Aliment ponte', 5, 16000, 80000);
      evenement('poste-bureau : achat ${achat.substring(0, 8)} de 5 sacs d\'aliment ponte à ${p.maintenant()}');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final r = await _serveur(['inventaire-web', jsonEncode({'produit': pr.id, 'ecart': 4, 'motif': 'Casse'})]);
      inventaireWeb = (produit: pr.id, nom: pr.name, attendu: (r['stock'] as num).toDouble());
      evenement('Web : inventaire de l\'aliment ponte, ${r['stock']} comptés (5 sacs du bureau dans les rayons, 1 abîmé)');
    } finally {
      p.connectivite.enLigne = true;
    }
  }

  /// Ticket S-T12 — produit inventorié au web pendant qu'un achat antérieur attendait au bureau, et son stock attendu.
  ({String produit, String nom, double attendu})? inventaireWeb;
  final stocksInventaireWebAuPoste = <String, double>{};

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
      await _geste(p, 'avance de 5 000 F d\'un client connu', () async {
        final client = (await p.db.select(p.db.customers).get()).firstWhere((c) => c.isActive && c.syncStatus == SyncStatus.synced);
        final a = await p.clients.enregistrerAvance(clientId: client.id, montant: 5000, compteId: await _compteCaisse(p), motif: 'Commande de poulets (essai)', date: p.jour);
        p.noter('customer_advances', a.id);
        avanceCaisse1 = a.id;
      });
    }
    if (d >= 1) {
      await _geste(p, 'vente à crédit à un client connu', () async {
        final client = (await p.db.select(p.db.customers).get()).firstWhere((c) => c.isActive && c.syncStatus == SyncStatus.synced);
        final id = await _vente(p, 'Fumier compost', 1, 1500, mode: 'credit', clientId: client.id);
        if (d == 1 && p == caisse1) venteCreditCaisse1 = id;
      });
    }
    // 15.19 — imputation de l'avance de la veille sur la créance de la vente à crédit, une fois la créance descendue
    // au poste (le poste n'impute que sur une créance qu'il connaît, F0.73). La caisse 1 vient de se reconnecter.
    if (d == 3 && p == caisse1) {
      Future<Receivable?> creance() async => (await p.db.select(p.db.receivables).get())
          .where((c) => c.saleId == venteCreditCaisse1 && c.amount - c.amountPaid > 0).firstOrNull;
      await _jusqua(p, 'créance de la vente à crédit de la veille', () async => await creance() != null);
      await _geste(p, 'imputation de l\'avance sur la créance de la vente à crédit', () async {
        final c = (await creance())!;
        final avance = await (p.db.select(p.db.customerAdvances)..where((a) => a.id.equals(avanceCaisse1!))).getSingle();
        final montant = [await p.clients.resteAvance(avance), await p.clients.soldeCreance(c)].reduce(min);
        final i = await p.clients.imputerAvance(avanceId: avanceCaisse1!, creanceId: c.id, montant: montant, date: p.jour);
        p.noter('advance_imputations', i.id);
        imputationCreance = (avance: avanceCaisse1!, montant: montant);
      });
    }
    if (p == caisse2 && _caisse2HorsLigne(d)) await _journeeHorsLigneCaisse2(d);
  }

  /// Ticket S-T12 — la caisse 1 : son avance, sa vente à crédit, l'imputation faite après sa reconnexion.
  String? avanceCaisse1;
  String? venteCreditCaisse1;
  ({String avance, double montant})? imputationCreance;

  /// Ticket S-T12 — la caisse 2 hors ligne : l'avance et la vente à crédit d'un client, imputée par la vente du MÊME
  /// envoi (`sale_id`, 15.19).
  ({String avance, double montant})? imputationMemeEnvoi;

  /// Ticket S-T12 — la deuxième caisse, hors ligne trois journées : le comptoir continue (15 ventes de plus par jour, de
  /// quoi dépasser un lot de 50 au retour), du piment vendu AVANT le comptage du bureau, et une avance imputée sur la
  /// vente à crédit du même envoi.
  Future<void> _journeeHorsLigneCaisse2(int d) async {
    final p = caisse2;
    for (var i = 0; i < 15; i++) {
      try {
        await _vente(p, 'Fumier compost', 1, 1500);
      } catch (e) {
        journaliser('${p.nom}  ✎ vente de comptoir — REFUSÉ AU POSTE : $e');
        p._compter('geste refusé au poste');
      }
    }
    if (d != 1) return;
    await _geste(p, 'vente de 2 sacs de piment, hors ligne, AVANT le comptage du bureau', () async {
      await _vente(p, 'Piment frais', 2, 1200);
      pimentVenduHorsLigne += 2;
    });
    await _geste(p, 'avance de 3 000 F, vente à crédit de 3 000 F et imputation de l\'une sur l\'autre (même envoi)', () async {
      final clients = (await p.db.select(p.db.customers).get()).where((c) => c.isActive && c.syncStatus == SyncStatus.synced).toList();
      final client = clients.length > 1 ? clients[1] : clients.first;
      final a = await p.clients.enregistrerAvance(clientId: client.id, montant: 3000, compteId: await _compteCaisse(p), motif: 'Acompte sur fumier (essai)', date: p.jour);
      p.noter('customer_advances', a.id);
      final vente = await _vente(p, 'Fumier compost', 2, 1500, mode: 'credit', clientId: client.id);
      // ⚠️ AUCUN DÉPÔT DU POSTE N'ÉCRIT CETTE IMPUTATION (F0.73 : l'écran n'offre que les créances DÉJÀ descendues ;
      // celle d'une vente à crédit pas encore envoyée n'existe pas au poste). La colonne `sale_id` et l'envoi sont
      // prêts : l'essai l'écrit donc directement, pour éprouver le contrat 15.19 du serveur au milieu des coupures.
      final id = 'e5512000-0000-4000-8000-${(DateTime.now().microsecondsSinceEpoch % 1000000000000).toString().padLeft(12, '0')}';
      await p.db.into(p.db.advanceImputations).insert(
        AdvanceImputationsCompanion.insert(
          id: id,
          deviceId: p.nom,
          syncStatus: const Value(SyncStatus.pending),
          updatedAt: DateTime.now(),
          customerAdvanceId: a.id,
          saleId: Value(vente),
          amount: 3000,
          imputationDate: p.jour,
        ),
      );
      p.noter('advance_imputations', id);
      imputationMemeEnvoi = (avance: a.id, montant: 3000);
    });
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
    switch (d) {
      case 0:
        // H8b — infirmerie et calendrier vétérinaire saisis au poste ; H7 — une saillie.
        await _geste(p, 'entrée à l\'infirmerie (ESSAI-B)', () async {
          infirmerie = await p.soinsVaccins.enregistrerEntreeInfirmerie(lotId: (await p.bande('ESSAI-B')).id, sujetRef: 'P-17', motif: 'Boiterie (essai)', niveauIsolement: 'Infirmerie', dateEntree: p.jour, quand: HeureBenin.versInstant(p.maintenant()));
          p.noter('infirmary_records', infirmerie!);
          _saisi('infirmary_records', infirmerie!, {'status': 'en_cours'});
        });
        await _geste(p, 'intervention planifiée (ESSAI-A, dans 3 jours)', () async {
          intervention = await p.soinsVaccins.planifierIntervention(lotId: (await p.bande('ESSAI-A')).id, intervention: 'Vaccin Newcastle (essai)', datePrevue: HeureBenin.plusJours(p.jour, 3), quand: HeureBenin.versInstant(p.maintenant()));
          p.noter('veterinary_calendar_events', intervention!);
          _saisi('veterinary_calendar_events', intervention!, {'status': 'planned'});
        });
        await _geste(p, 'saillie de L-ESSAI-1 (CUN-2026-01)', () async {
          cycle1 = await p.reproduction.declarerSaillie(lotId: (await p.bande('CUN-2026-01')).id, numeroFemelle: 'L-ESSAI-1', numeroMale: 'M-ESSAI', dateSaillie: p.jour, maintenant: p.maintenant());
          p.noter('livestock_reproduction_events', cycle1!);
          _saisi('livestock_reproduction_events', cycle1!, {'status': 'en_cours'});
        });
        // Ticket BS1 — « Bandes & Sujets » : deux bandes CRÉÉES au poste (l'une sera archivée au jour 3).
        for (final (code, effectif) in [('ESSAI-C', 20), ('ESSAI-D', 8)]) {
          await _geste(p, 'bande $code créée au poste ($effectif sujets)', () async {
            final modele = await p.bande('ESSAI-A');
            final b = await p.bandes.creer(
              FormulaireBande(speciesId: modele.speciesId, code: code, stage: 'croissance', createdDate: p.jour, quantite: '$effectif'),
            );
            p.noter('livestock_lots', b.id);
            if (code == 'ESSAI-C') {
              bandeC = b.id;
              _saisi('livestock_lots', b.id, {'code': code, 'stage': 'croissance', 'is_active': true, 'initial_quantity': effectif});
            } else {
              bandeD = b.id;
              _saisi('livestock_lots', b.id, {'code': code, 'is_active': true, 'initial_quantity': effectif});
            }
          });
        }
        // Ticket BS3 — « Registre des Reproducteurs » : un sujet nominatif enregistré au poste, dans la bande ESSAI-A.
        await _geste(p, 'reproducteur REP-ESSAI-1 enregistré au poste (BS3)', () async {
          final modele = await p.bande('ESSAI-A');
          final a = await p.reproducteurs.enregistrer(
            FormulaireReproducteur(speciesId: modele.speciesId, identifier: 'REP-ESSAI-1', lotId: modele.id, sex: 'F', breed: 'Sussex', entryDate: p.jour, cage: 'C1'),
          );
          reproducteur = a.id;
          p.noter('animals', a.id);
          _saisi('animals', a.id, {'identifier': 'REP-ESSAI-1', 'breed': 'Sussex', 'cage': 'C1', 'status': 'actif'});
        });
        // Ticket BS2 — « Enregistrer des Sujets » : 6 naissances dans ESSAI-C (20 + 6 = 26).
        await _geste(p, 'sujets : 6 naissances dans ESSAI-C', () async {
          final f = await p.sujetsEntrees.ajouter(FormulaireSujet(speciesId: (await p.bande('ESSAI-A')).speciesId, lotId: bandeC!, origine: 'Naissance', quantite: '6', date: p.jour));
          ficheNaissance = f.id;
          jourNaissance = p.jour;
          p.noter('livestock_daily_entries', f.id);
          _saisi('livestock_daily_entries', f.id, {'ne': 6, 'achat': 0, 'effectif_final': 26});
        });
      case 1:
        // Ticket BS3 — la cage du reproducteur change (modification d'un sujet déjà envoyé).
        await _geste(p, 'reproducteur REP-ESSAI-1 : cage C1 → C2 (BS3)', () async {
          final actuel = (await p.reproducteurs.sujet(reproducteur!))!;
          await p.reproducteurs.modifier(reproducteur!, FormulaireReproducteur.depuis(actuel).copieAvec(cage: 'C2'));
          _saisi('animals', reproducteur!, {'cage': 'C2'});
        });
        // Décision BS-Q13 — l'identifiant d'un sujet enregistré ne change plus : refusé au poste, rien mis en file ; le
        // serveur garde « REP-ESSAI-1 » (l'identifiant des lignes comparées en fin d'essai est celui de l'enregistrement).
        {
          final actuel = (await p.reproducteurs.sujet(reproducteur!))!;
          try {
            await p.reproducteurs.modifier(reproducteur!, FormulaireReproducteur.depuis(actuel).copieAvec(identifier: 'REP-ESSAI-9'));
            journaliser('${p.nom}  ✎ reproducteur REP-ESSAI-1 : identifiant → REP-ESSAI-9 ACCEPTÉ AU POSTE (BS-Q13 violée)');
          } on ReproducteurRefuse catch (e) {
            identifiantRefuse = e.erreurs['identifier'] == ReproducteursRepository.messageIdentifiantFige;
            journaliser('${p.nom}  ✎ reproducteur REP-ESSAI-1 : changer l\'identifiant refusé au poste, comme voulu (BS-Q13)');
          }
        }
        // Ticket BS1 — le stade d'ESSAI-C change (sans correction d'effectif : il reste celui des fiches).
        await _geste(p, 'bande ESSAI-C : stade → ponte', () async {
          final b = (await p.db.select(p.db.livestockLots).get()).firstWhere((x) => x.id == bandeC);
          await p.bandes.modifier(bandeC!, stage: 'ponte', quantite: '${b.currentQuantity}', status: 'actif');
          _saisi('livestock_lots', bandeC!, {'stage': 'ponte'});
        });
        // Ticket BS2 — 4 achats ; puis les naissances du jour 1 corrigées (6 → 5) : la cascade refait les deux fiches.
        await _geste(p, 'sujets : 4 achats dans ESSAI-C', () async {
          final f = await p.sujetsEntrees.ajouter(FormulaireSujet(speciesId: (await p.bande('ESSAI-A')).speciesId, lotId: bandeC!, origine: 'Achat', quantite: '4', date: p.jour));
          ficheAchat = f.id;
          p.noter('livestock_daily_entries', f.id);
          _saisi('livestock_daily_entries', f.id, {'ne': 0, 'achat': 4, 'effectif_final': 30});
        });
        await _geste(p, 'sujets : naissances de la journée 1 corrigées (6 → 5)', () async {
          await p.sujetsEntrees.modifier(
            ficheNaissance!,
            'Naissance',
            FormulaireSujet(origine: 'Naissance', quantite: '5', date: jourNaissance),
          );
          // 20 + 5 = 25 ; 25 + 4 = 29 : la cascade a refait la fiche des achats.
          _saisi('livestock_daily_entries', ficheNaissance!, {'ne': 5, 'effectif_final': 25});
          _saisi('livestock_daily_entries', ficheAchat!, {'effectif_final': 29});
        });
        await _geste(p, 'soin : vitamines sur ESSAI-B (sans délai d\'attente)', () async {
          final s = await p.soins.enregistrer(lotId: (await p.bande('ESSAI-B')).id, typeAction: 'Traitement', produit: 'Vitamines AD3E', dose: '1 g/L', cout: 2500, quand: p.maintenant());
          p.noter('veterinary_records', s.id);
          soinAArchiver = s.id;
          _saisi('veterinary_records', s.id, {'is_active': true});
        });
        await _geste(p, 'palpation positive de L-ESSAI-1', () async {
          await p.reproduction.enregistrerPalpation(cycle1!, positive: true, maintenant: p.maintenant());
          _saisi('livestock_reproduction_events', cycle1!, {'palpation_date': _jourIso(p.jour), 'status': 'en_cours'});
        });
        // H9b — Paramètres Élevage modifiés au poste (le web, lui, modifie l'aviculture demain).
        await _geste(p, 'ration cuniculture : +5 g/jour (Paramètres Élevage)', () async {
          final ration = (await p.db.select(p.db.feedRationStandards).get()).firstWhere((r) => r.isActive && r.speciesCode == 'cuniculture');
          await p.parametresElevage.enregistrerRation(id: ration.id, espece: 'cuniculture', stade: ration.stageLabel, grammes: ration.rationGPerDay.round() + 5);
          p.noter('feed_ration_standards', ration.id);
          rationPoste = ration.id;
          _saisi('feed_ration_standards', ration.id, {'ration_g_per_day': ration.rationGPerDay.round() + 5, 'is_active': true});
        });
        await _geste(p, 'provende « ESSAI Provende lapin » (Paramètres Élevage)', () async {
          final especes = (await p.parametresElevage.charger()).especesProvende;
          final lapin = especes.firstWhere((e) => e.code == 'cuniculture', orElse: () => especes.first);
          provende = await p.parametresElevage.enregistrerProvende(nom: 'ESSAI Provende lapin', espece: lapin, sacKg: 25, prixKg: 310);
          p.noter('feed_types', provende!);
          _saisi('feed_types', provende!, {'name': 'ESSAI Provende lapin', 'price_per_kg': 310, 'is_active': true});
        });
      case 2:
        // Ticket BS1/BS2 — ESSAI-D archivée ; les achats d'ESSAI-C archivés (29 → 25 sur la fiche, 25 sur la bande).
        // Décisions du 21/10/2026 — BS-Q3 : une bande qui a des sujets vivants ne s'archive pas ; il faut la VIDER d'abord.
        await _geste(p, 'bande ESSAI-D : archivage refusé tant qu\'elle a 8 sujets vivants (BS-Q3)', () async {
          try {
            await p.bandes.archiver(bandeD!);
          } on BandeRefusee {
            return;
          }
          throw StateError('ESSAI-D archivée à tort avec 8 sujets vivants');
        });
        // BS-Q4 : ESSAI-C a des fiches — sa correction d'effectif passe par la fiche, jamais par « Modifier la Bande ».
        await _geste(p, 'bande ESSAI-C : correction d\'effectif refusée, elle a des fiches (BS-Q4)', () async {
          try {
            await p.bandes.modifier(bandeC!, stage: 'ponte', quantite: '3', status: 'actif');
          } on BandeRefusee {
            return;
          }
          throw StateError('effectif d\'ESSAI-C corrigé à tort alors qu\'elle a des fiches');
        });
        await _geste(p, 'bande ESSAI-D vidée (effectif 0, sans fiche) puis archivée au poste', () async {
          await p.bandes.modifier(bandeD!, stage: 'croissance', quantite: '0', status: 'actif');
          await p.bandes.archiver(bandeD!);
          _saisi('livestock_lots', bandeD!, {'is_active': false, 'current_quantity': 0});
        });
        await _geste(p, 'sujets : achats d\'ESSAI-C archivés', () async {
          await p.sujetsEntrees.archiver(ficheAchat!, 'Achat');
          _saisi('livestock_daily_entries', ficheAchat!, {'achat': 0, 'effectif_final': 25});
          _saisi('livestock_lots', bandeC!, {'current_quantity': 25});
        });
        // Hors ligne toute la journée : la saillie et sa palpation (négative) partent dans le MÊME envoi.
        await _geste(p, 'saillie de L-ESSAI-2 puis palpation négative, hors ligne', () async {
          cycle2 = await p.reproduction.declarerSaillie(lotId: (await p.bande('CUN-2026-01')).id, numeroFemelle: 'L-ESSAI-2', dateSaillie: p.jour, maintenant: p.maintenant());
          p.noter('livestock_reproduction_events', cycle2!);
          await p.reproduction.enregistrerPalpation(cycle2!, positive: false, maintenant: p.maintenant());
          _saisi('livestock_reproduction_events', cycle2!, {'status': 'echec', 'palpation_date': _jourIso(p.jour)});
        });
        await _geste(p, 'rappel des soins planifiés : 4 jours (Paramètres Élevage)', () async {
          await p.parametresElevage.enregistrerRappelSoins(4);
          rappelSoins = 4;
        });
        await _geste(p, 'réintégration de l\'animal de l\'infirmerie', () async {
          await p.soinsVaccins.reintegrer(infirmerie!, quand: HeureBenin.versInstant(p.maintenant()));
          _saisi('infirmary_records', infirmerie!, {'status': 'reintegre'});
        });
        await _geste(p, 'transfert de 10 sujets ESSAI-A → ESSAI-B', () async {
          final t = await p.transferts.creer(sourceLotId: (await p.bande('ESSAI-A')).id, targetLotId: (await p.bande('ESSAI-B')).id, jour: p.jour, quantite: 10, motif: 'Essai S-T9');
          p.noter('livestock_transfers', t.id);
        });
      case 3:
        // BS-Q7 : la bande archivée la veille est RESTAURÉE au poste (geste explicite, absorbeur strict, droits).
        await _geste(p, 'bande ESSAI-D restaurée au poste (BS-Q7)', () async {
          await p.bandes.restaurer(bandeD!);
          _saisi('livestock_lots', bandeD!, {'is_active': true, 'current_quantity': 0});
        });
        // Ticket BS3 — la sortie du reproducteur (réforme) : le sujet reste, l'effectif de la bande n'est pas touché.
        await _geste(p, 'reproducteur REP-ESSAI-1 réformé (BS3)', () async {
          await p.reproducteurs.sortir(reproducteur!, FormulaireSortie(status: 'reforme', exitDate: p.jour, reason: 'Réforme pour âge'));
          _saisi('animals', reproducteur!, {'status': 'reforme', 'exit_reason': 'Réforme pour âge'});
        });
        await _geste(p, 'mise bas de L-ESSAI-1 : 7 vivants, 1 mort', () async {
          await p.reproduction.enregistrerMiseBas(cycle1!, nesVivants: 7, nesMorts: 1, maintenant: p.maintenant());
          _saisi('livestock_reproduction_events', cycle1!, {'mise_bas_date_actual': _jourIso(p.jour), 'nes_vivants': 7, 'nes_morts': 1});
        });
        await _geste(p, 'administration confirmée (calendrier)', () async {
          await p.soinsVaccins.confirmerAdministration(intervention!, quand: HeureBenin.versInstant(p.maintenant()));
          _saisi('veterinary_calendar_events', intervention!, {'status': 'done'});
        });
        // U3 — archivage d'un soin au poste.
        await _geste(p, 'archivage du soin de la journée 2', () async {
          await p.soinsVaccins.archiverSoin(soinAArchiver!, quand: HeureBenin.versInstant(p.maintenant()));
          _saisi('veterinary_records', soinAArchiver!, {'is_active': false});
        });
      case 4:
        await _geste(p, 'clôture du cycle de L-ESSAI-1 (sevrage)', () async {
          await p.reproduction.cloturerCycle(cycle1!, maintenant: p.maintenant());
          _saisi('livestock_reproduction_events', cycle1!, {'status': 'termine'});
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

  /// Ticket S-T12 — lignes saisies à l'élevage dont le serveur doit détenir l'état FINAL du poste.
  String? infirmerie, intervention, cycle1, cycle2, soinAArchiver, rationPoste, provende;

  /// Tickets BS1 et BS2 — les bandes ESSAI-C (modifiée, effectif par les sujets) et ESSAI-D (archivée) créées au poste, les
  /// fiches de leurs entrées de sujets.
  String? bandeC, bandeD, ficheNaissance, ficheAchat;

  /// Ticket BS3 — le reproducteur nominatif REP-ESSAI-1 : enregistré (jour 1), cage modifiée (jour 2), sorti (jour 4).
  String? reproducteur;
  DateTime? jourNaissance;
  int? rappelSoins;

  /// Ticket S-T12 — ce que l'animalier a SAISI (dernière valeur de chaque champ), par `table|id` : c'est l'attendu, au
  /// serveur comme sur le poste. ⚠️ Comparer le serveur à l'état FINAL du poste ne suffit pas : une étape acquittée sans
  /// être appliquée est ensuite ÉCRASÉE au poste par le tirage, et les deux côtés concordent… sur la perte.
  final saisiElevage = <String, Map<String, Object?>>{};
  void _saisi(String table, String id, Map<String, Object?> champs) => (saisiElevage['$table|$id'] ??= {}).addAll(champs);

  Future<void> _journeeCompta(int d) async {
    await _pause(compta);
    await compta.synchroniser('comptabilité, journée ${d + 1}');
  }

  /// Écritures faites AU WEB pendant que les postes travaillent : le tirage doit les ramener (curseur S-T4).
  Future<void> _journeeWeb(int d, DateTime jour) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (d == 0) {
      // Ticket S-T12 — le même produit que celui que le bureau, hors ligne, crée aujourd'hui (fusion S-T5).
      final r = await _serveur(['produit-web', jsonEncode({
        'nom': produitFusionNom,
        'categorie': (await bureau.produit('Fumier compost')).categoryId,
        'unite': 'pain',
        'prix_min': 500,
        'prix_max': 700,
        'stock': 12,
      })]);
      produitFusionWeb = r['produit'] as String;
      evenement('Web : produit « $produitFusionNom » créé (Ajouter un Produit) — ${r['produit']}');
    }
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
    if (d == 3) {
      // Ticket U13 — la paie réglée au web descend aux postes qui lisent les rapports.
      final r = await _serveur(['paie-web']);
      paieWeb = r['bulletin'] as String;
      evenement('Web : paie de ${r['employe']} réglée (${r['net']} F net) — ${r['bulletin']}');
    }
    if (d == 4) {
      // Ticket U13 — une dépense saisie à un poste et déjà reçue est ARCHIVÉE au web : elle doit sortir du rapport de
      // chaque poste (le poste qui l'a saisie la croit active jusqu'au tirage suivant).
      // U14 : ni la dépense que le bureau modifie, ni celle qu'il archive (deux gestes du poste, vérifiés à part).
      final candidates = [
        for (final p in postes)
          for (final id in p.saisies['expenses'] ?? const <String>[])
            if (id != depenseAModifier && id != depenseAArchiverPoste) id,
      ];
      final r = await _serveur(['archiver-depense', jsonEncode(candidates)]);
      depenseArchiveeWeb = r['depense'] as String?;
      evenement(depenseArchiveeWeb == null
          ? 'Web : aucune dépense des postes encore reçue à archiver'
          : 'Web : dépense ${r['depense']} (${r['montant']} F) archivée (Saisie des Dépenses)');
    }
  }

  /// Ticket U13 — « Recettes et Dépenses » de chaque poste qui ouvre les rapports (son périmètre de tirage porte la
  /// paie : `view-rapports`) = celui du web, sur la fenêtre de l'essai : totaux et lignes de dépenses (date, libellé,
  /// montant, dans l'ordre), lignes de recettes ; et la dépense archivée au web l'est sur chaque poste qui la détient.
  Future<void> _comparerRecettesDepenses(DateTime du, DateTime au) async {
    recettesDepensesWeb = await _serveur(['recettes-depenses', _jourIso(du), _jourIso(au)]);
    final web = recettesDepensesWeb;
    String m(num v) => v.toDouble().toStringAsFixed(2);
    List<String> lignesWeb(String cle) => [
      for (final l in (web[cle] as List).cast<Map<String, dynamic>>())
        '${l['date']} | ${l['libelle']} | ${m(l['montant'] as num)}',
    ];
    for (final p in postes) {
      final ecarts = <String>[];
      final archivee = depenseArchiveeWeb;
      if (archivee != null) {
        final locale = await (p.db.select(p.db.expenses)..where((t) => t.id.equals(archivee))).getSingleOrNull();
        if (locale != null && locale.isActive) ecarts.add('dépense $archivee archivée au web, encore active au poste');
      }
      final perimetre = await PerimetreTirage.lire(p.db) ?? const <String>{};
      if (!perimetre.contains('payslips')) {
        if (ecarts.isNotEmpty) recettesDepenses[p.nom] = ecarts;
        continue;
      }
      final d = await RapportsRepository(database: p.db).charger(du: du, au: au);
      for (final (quoi, poste, serveur) in [
        ('recettes', d.totalRecettes, web['recettes'] as num),
        ('dépenses', d.totalDepenses, web['depenses'] as num),
        ('solde', d.soldeNet, web['solde'] as num),
      ]) {
        if (m(poste) != m(serveur)) ecarts.add('total des $quoi : poste ${m(poste)}, web ${m(serveur)}');
      }
      String ligne(MouvementRapport x) => '${RapportsRepository.date(x.date)} | ${x.libelle} | ${m(x.montant)}';
      for (final (quoi, poste, serveur) in [
        ('dépenses', [for (final x in d.depenses) ligne(x)], lignesWeb('lignes_depenses')),
        ('recettes', [for (final x in d.recettes) ligne(x)], lignesWeb('lignes_recettes')),
      ]) {
        if (poste.join('\n') != serveur.join('\n')) {
          ecarts.add('lignes de $quoi : poste ${poste.length}, web ${serveur.length} — '
              'poste seul ${poste.where((l) => !serveur.contains(l)).toList()}, '
              'web seul ${serveur.where((l) => !poste.contains(l)).toList()}');
        }
      }
      if (paieWeb != null && !lignesWeb('lignes_depenses').any((l) => l.contains('Paie — '))) {
        ecarts.add('la paie réglée au web ($paieWeb) n\'est pas dans le rapport du web : période mal choisie');
      }
      recettesDepenses[p.nom] = ecarts;
      journaliser('${p.nom} : Recettes et Dépenses — poste ${m(d.totalRecettes)} / ${m(d.totalDepenses)}, '
          'web ${m(web['recettes'] as num)} / ${m(web['depenses'] as num)}${ecarts.isEmpty ? '' : ' — ÉCARTS $ecarts'}');
    }
  }

  /// Ticket S-T6 — le web demande au poste-bureau de se synchroniser ; sa session ne fait rien d'autre qu'interroger le
  /// serveur toutes les 30 s (intervalle d'une heure, aucun geste). Une vente faite au web juste avant doit arriver sur
  /// le poste dans les 30 s (plus le temps du tirage).
  Future<void> _demandeDuWeb() async {
    final p = bureau;
    p.auto.arreter();
    p.auto = p.nouvelleAuto(intervalle: const Duration(hours: 1), demande: true)..demarrer();
    final avant = p.tentativesAuto;
    final vente = await _serveur(['vente-web', jsonEncode({
      'produit': (await p.produit('Fumier compost')).id,
      'quantite': 1,
      'montant': 1500,
    })]);
    webVentes.add(vente['vente'] as String);
    final demande = await _serveur(['demander', p.nom]);
    evenement('Web : vente ${vente['vente']} puis « Demander la synchronisation » de ${p.nom} (S-T6)');
    final debut = DateTime.now();
    while (DateTime.now().difference(debut) < const Duration(seconds: 50)) {
      final recue = await (p.db.select(p.db.sales)..where((v) => v.id.equals(vente['vente'] as String))).getSingleOrNull();
      if (recue != null) {
        delaiDemande = DateTime.now().difference(debut);
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    p.auto.arreter();
    demandeServie = (await _serveur(['demande', demande['demande'] as String]))['servie'] == true;
    tentativesDemande = p.tentativesAuto - avant;
    evenement('${p.nom} : vente du web reçue ${delaiDemande == null ? 'JAMAIS (50 s)' : 'après ${delaiDemande!.inMilliseconds / 1000} s'}'
        ', demande servie : $demandeServie, $tentativesDemande synchronisation(s) automatique(s)');
  }

  Duration? delaiDemande;
  bool demandeServie = false;
  int tentativesDemande = 0;

  /// Ticket S-T12 — l'état final, au poste qui les a saisies, des lignes que le serveur doit détenir à l'identique.
  final lignesLocales = <String, Map<String, Object?>>{};

  Future<void> _releverLignesLocales() async {
    final p = elevage;
    String? jour(DateTime? d) => d == null ? null : _jourIso(d);
    for (final id in [?cycle1, ?cycle2]) {
      final c = await (p.db.select(p.db.livestockReproductionEvents)..where((t) => t.id.equals(id))).getSingleOrNull();
      lignesLocales['livestock_reproduction_events|$id'] = {
        'status': c?.status,
        'palpation_date': jour(c?.palpationDate),
        'mise_bas_date_actual': jour(c?.miseBasDateActual),
        'nes_vivants': c?.nesVivants,
        'nes_morts': c?.nesMorts,
      };
    }
    if (infirmerie != null) {
      final i = await (p.db.select(p.db.infirmaryRecords)..where((t) => t.id.equals(infirmerie!))).getSingleOrNull();
      lignesLocales['infirmary_records|$infirmerie'] = {'status': i?.status};
    }
    if (intervention != null) {
      final i = await (p.db.select(p.db.veterinaryCalendarEvents)..where((t) => t.id.equals(intervention!))).getSingleOrNull();
      lignesLocales['veterinary_calendar_events|$intervention'] = {'status': i?.status};
    }
    if (soinAArchiver != null) {
      final s = await (p.db.select(p.db.veterinaryRecords)..where((t) => t.id.equals(soinAArchiver!))).getSingleOrNull();
      lignesLocales['veterinary_records|$soinAArchiver'] = {'is_active': s?.isActive};
    }
    if (rationPoste != null) {
      final r = await (p.db.select(p.db.feedRationStandards)..where((t) => t.id.equals(rationPoste!))).getSingleOrNull();
      lignesLocales['feed_ration_standards|$rationPoste'] = {'ration_g_per_day': r?.rationGPerDay.round(), 'is_active': r?.isActive};
    }
    if (provende != null) {
      final f = await (p.db.select(p.db.feedTypes)..where((t) => t.id.equals(provende!))).getSingleOrNull();
      lignesLocales['feed_types|$provende'] = {'name': f?.name, 'price_per_kg': f?.pricePerKg, 'is_active': f?.isActive};
    }
    // Tickets BS1 et BS2 — bandes et entrées de sujets de l'élevage, telles que le poste les détient en fin d'essai.
    for (final id in [?bandeC, ?bandeD]) {
      final b = await (p.db.select(p.db.livestockLots)..where((t) => t.id.equals(id))).getSingleOrNull();
      lignesLocales['livestock_lots|$id'] = {
        'code': b?.code,
        'stage': b?.stage,
        'is_active': b?.isActive,
        'initial_quantity': b?.initialQuantity,
        'current_quantity': b?.currentQuantity,
      };
    }
    if (reproducteur != null) {
      final a = await p.reproducteurs.sujet(reproducteur!);
      lignesLocales['animals|$reproducteur'] = {'identifier': a?.identifier, 'breed': a?.breed, 'cage': a?.cage, 'status': a?.status, 'exit_reason': a?.exitReason};
    }
    for (final id in [?ficheNaissance, ?ficheAchat]) {
      final f = await (p.db.select(p.db.livestockDailyEntries)..where((t) => t.id.equals(id))).getSingleOrNull();
      lignesLocales['livestock_daily_entries|$id'] = {'ne': f?.ne, 'achat': f?.achat, 'don': f?.don, 'effectif_final': f?.effectifFinal};
    }
    // Ticket U14 — les dépenses modifiée et archivée au bureau.
    for (final id in [?depenseAModifier, ?depenseAArchiverPoste]) {
      final d = await (bureau.db.select(bureau.db.expenses)..where((t) => t.id.equals(id))).getSingleOrNull();
      lignesLocales['expenses|$id'] = {'label': d?.label, 'is_active': d?.isActive};
    }
  }

  /// Ticket S-T12 — ce que la réinitialisation du web a laissé : sur chaque poste (lignes d'activité, saisies en
  /// attente, avertissement), au serveur (lignes d'activité), et le refus de l'envoi d'un poste sans la marque.
  final apresReinitialisation = <String, ({int activite, Map<String, int> enAttente, List<String> avertissements})>{};
  Map<String, dynamic> serveurReinitialise = {};
  int? statutEnvoiSansMarque;
  String? venteAvantReinitialisation;

  /// Statut de la première synchronisation de chaque poste après la réinitialisation (ses jetons sont révoqués avec
  /// elle, 15.54 : 401 attendu, puis reconnexion).
  final statutsApresReinitialisation = <String, int?>{};

  /// Ticket 15.50 (avec 15.54) — la réinitialisation vide les données d'activité ET révoque les jetons des postes :
  /// chacun se voit refuser sa session (401), se reconnecte, et son premier tirage applique la marque (purge locale)
  /// avant tout envoi. Un envoi qui ne porte pas la marque est refusé (409) : il ressusciterait des données effacées.
  Future<void> _reinitialisation() async {
    // Une vente de la caisse 1 que personne n'a encore envoyée au moment de la réinitialisation.
    caisse1.connectivite.enLigne = false;
    venteAvantReinitialisation = await _vente(caisse1, 'Fumier compost', 1, 1500);
    caisse1.connectivite.enLigne = true;

    final r = await _serveur(['reinitialiser']);
    evenement('Web : réinitialisation des données (Paramètres, 15.50) — marque ${r['data_reset_at']}');

    for (final p in postes) {
      try {
        await p.moteur.synchroniser();
        statutsApresReinitialisation[p.nom] = 200;
      } on EchecSynchronisation catch (e) {
        statutsApresReinitialisation[p.nom] = e.statut;
      }
    }
    evenement('Après la réinitialisation, première synchronisation : $statutsApresReinitialisation (jetons révoqués, 15.54)');

    for (final p in postes) {
      // Nouvelle session, sans synchronisation automatique : la première synchronisation est celle de l'essai.
      await _connecter(p);
      if (p == caisse1) {
        // Un envoi qui ne porte pas la marque (poste qui ne l'a pas tirée) : refusé, rien n'est écrit.
        try {
          await caisse1.client.post<dynamic>('/api/sync/push', data: {
            'device_id': caisse1.nom,
            'sales': [{'id': venteAvantReinitialisation}],
          });
          statutEnvoiSansMarque = 200;
        } on DioException catch (e) {
          statutEnvoiSansMarque = e.response?.statusCode;
        }
        evenement('poste-caisse-1 : envoi sans la marque de réinitialisation → $statutEnvoiSansMarque');
      }
      SyncOutcome? issue;
      for (var i = 0; i < 10 && issue == null; i++) {
        if (i > 0) await Future<void>.delayed(const Duration(seconds: 7));
        issue = await p.synchroniser('après la réinitialisation');
      }
      var activite = 0;
      for (final t in p.db.allTables) {
        if (!AppDatabase.tablesDActivite.contains(t.actualTableName)) continue;
        activite += (await p.db.customSelect('SELECT COUNT(*) AS n FROM ${t.actualTableName}').getSingle()).read<int>('n');
      }
      apresReinitialisation[p.nom] = (activite: activite, enAttente: await p.enAttente(), avertissements: issue?.avertissements ?? const []);
      journaliser('${p.nom} après la réinitialisation : $activite ligne(s) d\'activité, en attente ${await p.enAttente()}, '
          'avertissements ${issue?.avertissements}');
    }
    // Un second tour : rien de ce que les postes renverraient ne doit ressusciter au serveur.
    for (final p in postes) {
      await _jusquAAboutir(p, 'après la réinitialisation, second tour');
    }
    serveurReinitialise = await _serveur(['etat-reinitialise']);
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

    // Ticket U13 — « Recettes et Dépenses » : chaque poste qui ouvre les rapports a le total et les lignes du web.
    expect(paieWeb, isNotNull, reason: 'la paie du web n\'a pas été réglée');
    expect(depenseArchiveeWeb, isNotNull, reason: 'aucune dépense des postes n\'a pu être archivée au web');
    expect(
      [for (final p in postes) if ((recettesDepenses[p.nom] ?? const []).isEmpty && recettesDepenses.containsKey(p.nom)) p.nom],
      containsAll([bureau.nom, compta.nom]),
      reason: 'Recettes et Dépenses comparé au web pour le bureau et la comptabilité : ${{
        for (final e in recettesDepenses.entries) e.key: e.value,
      }}',
    );
    for (final p in postes) {
      expect(recettesDepenses[p.nom] ?? const [], isEmpty,
          reason: '${p.nom} : « Recettes et Dépenses » différent du web : ${recettesDepenses[p.nom]}');
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

    // Ticket S-T10 — l'inventaire compté au bureau pendant les ventes du web et de la caisse 1 : le stock final est le
    // comptage moins la vente postérieure, au serveur ET sur chaque poste (recalé au tirage).
    final compte = inventaireCompte;
    expect(compte, isNotNull, reason: 'le scénario d\'inventaire S-T10 n\'a pas eu lieu');
    final auServeur = ((stocks[compte!.produit] as Map?)?['stock'] as num?)?.toDouble();
    expect(auServeur, compte.attendu,
        reason: 'S-T10 : ${compte.nom} — stock final au serveur $auServeur, attendu ${compte.attendu} '
            '(comptage − 1 vendu après) : une vente comptée deux fois, ou l\'inventaire perdu');
    final postesFaux = {
      for (final MapEntry(:key, :value) in stocksComptesAuPoste.entries)
        if (value != compte.attendu) key: value,
    };
    expect(postesFaux, isEmpty, reason: 'S-T10 : ${compte.nom} — postes non recalés sur le serveur : $postesFaux');

    // ── Ticket S-T12 ────────────────────────────────────────────────────────────────────────────────────────────
    _verifierS12(stocks);

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

  /// Ticket S-T12 — les invariants ajoutés : chaque scénario a eu lieu, et le serveur tient ce que les postes ont saisi.
  void _verifierS12(Map<String, dynamic> stocks) {
    // Chaque scénario a eu lieu (un geste refusé au poste le ferait taire sans faire échouer le reste).
    final manquants = [
      if (!retourFait) 'retour fournisseur',
      if (!remboursementFait) 'remboursement fournisseur',
      if (reglements < 2) 'deux règlements fournisseurs ($reglements)',
      if (produitFusionPoste == null || produitFusionWeb == null || produitFusionAchat == null) 'produit créé au poste et au web',
      if (imputationCreance == null) 'imputation sur une créance descendue',
      if (imputationMemeEnvoi == null) 'imputation sur la vente à crédit du même envoi',
      if (pimentVenduHorsLigne == 0) 'vente de piment hors ligne avant le comptage',
      if (inventaireWeb == null) 'achat avant l\'inventaire du web',
      if (cycle1 == null || cycle2 == null) 'cycles de reproduction',
      if (infirmerie == null || intervention == null || soinAArchiver == null) 'infirmerie, calendrier, soin archivé',
      if (rationPoste == null || provende == null || rappelSoins == null) 'Paramètres Élevage au poste',
      if (reproducteur == null) 'reproducteur nominatif enregistré, modifié puis sorti au poste (BS3)',
      if (!identifiantRefuse) 'changement d\'identifiant du reproducteur refusé au poste (BS-Q13)',
      if (bandeC == null || bandeD == null || ficheNaissance == null || ficheAchat == null)
        'bandes créées au poste (ESSAI-C, ESSAI-D) et entrées de sujets modifiée et archivée (BS1, BS2)',
      if (!saisiElevage.containsKey('expenses|$depenseAModifier') || !saisiElevage.containsKey('expenses|$depenseAArchiverPoste'))
        'dépense modifiée et dépense archivée au poste (U14)',
      if (!sessionsRefusees.containsKey(caisse1.nom) || !sessionsRefusees.containsKey(compta.nom)) 'sessions refusées',
    ];
    expect(manquants, isEmpty, reason: 'scénarios S-T12 qui n\'ont pas eu lieu (geste refusé au poste ? voir le journal) : $manquants');

    // Les deux côtés de chaque flux ont bougé d'autant (au centime) : trésorerie dans les DEUX livres, créances, dettes,
    // avances, créances sur fournisseurs.
    final concordance = (etatServeur['concordance'] as Map).cast<String, dynamic>();
    final discordances = <String>[
      for (final MapEntry(key: code, value: v) in (concordance['tresorerie'] as Map).cast<String, dynamic>().entries)
        if (((v as Map)['comptes'] as num) != (v['classe5'] as num))
          'trésorerie $code : soldes des comptes ${v['comptes']} / classe 5 ${v['classe5']}',
      for (final cle in ['creances_clients', 'dettes_fournisseurs', 'avances', 'creances_fournisseurs'])
        if (((concordance[cle] as Map)['metier'] as num) != ((concordance[cle] as Map)['livre'] as num))
          '$cle : tables ${(concordance[cle] as Map)['metier']} / grand livre ${(concordance[cle] as Map)['livre']}',
    ];
    expect(discordances, isEmpty, reason: 'les tables métier et le grand livre ont divergé pendant l\'essai : $discordances');

    final depenses = (etatServeur['depenses'] as Map).cast<String, dynamic>();
    expect(depenses, isNotEmpty, reason: 'aucune dépense saisie');
    final malComptees = {for (final MapEntry(:key, :value) in depenses.entries) if (value != 1) key: value};
    expect(malComptees, isEmpty, reason: 'dépenses comptabilisées zéro ou plusieurs fois : $malComptees');

    // Avances : utilisé = somme des imputations reçues ; et chacune des deux imputations a bien été appliquée.
    final avances = (etatServeur['avances'] as Map).cast<String, dynamic>();
    final fausses = [
      for (final MapEntry(:key, :value) in avances.entries)
        if (value == null || (value as Map)['utilise'] != value['imputations']) '$key : $value',
    ];
    expect(fausses, isEmpty, reason: 'solde d\'avance faux (utilisé ≠ imputations) : $fausses');
    for (final i in [?imputationCreance, ?imputationMemeEnvoi]) {
      expect((avances[i.avance] as Map?)?['utilise'], i.montant, reason: 'avance ${i.avance} : ${i.montant} F imputés au poste');
    }

    expect((etatServeur['retours'] as Map).values.every((n) => (n as num) > 0), isTrue, reason: 'retour fournisseur sans ligne au serveur');
    final doublons = (etatServeur['doublons'] as Map).cast<String, dynamic>();
    expect(doublons['produits_meme_cle'], isEmpty, reason: 'le même produit existe plusieurs fois : fusion S-T5 en défaut');

    // S-T12 — l'achat fait avant l'inventaire du web et arrivé après lui n'entre pas une seconde fois.
    final web = inventaireWeb!;
    final auServeur = ((stocks[web.produit] as Map?)?['stock'] as num?)?.toDouble();
    expect(auServeur, web.attendu, reason: 'S-T12 : ${web.nom} — stock final au serveur $auServeur, attendu ${web.attendu} '
        '(le comptage du web, qui contenait déjà l\'achat du bureau)');
    final postesFaux = {for (final MapEntry(:key, :value) in stocksInventaireWebAuPoste.entries) if (value != web.attendu) key: value};
    expect(postesFaux, isEmpty, reason: 'S-T12 : ${web.nom} — postes non recalés : $postesFaux');

    // L'état final de chaque ligne saisie à l'élevage (cycle, infirmerie, calendrier, soin archivé, barèmes) est celui
    // du poste, au serveur.
    final lignes = (etatServeur['lignes'] as Map).cast<String, dynamic>();
    bool egal(Object? a, Object? b) => switch ((a, b)) {
      (bool x, num n) => (x ? 1 : 0) == n,
      (bool x, bool y) => x == y,
      (num x, num y) => (x - y).abs() < 0.001,
      (num x, String y) => (x - (num.tryParse(y) ?? double.nan)).abs() < 0.001,
      _ => '$a' == '$b',
    };
    final ecarts = <String>[];
    saisiElevage.forEach((cle, saisi) {
      final [table, id] = cle.split('|');
      final serveur = ((lignes[table] as Map?)?[id] as Map?)?.cast<String, dynamic>();
      final local = lignesLocales[cle];
      saisi.forEach((colonne, valeur) {
        if (!egal(valeur, serveur?[colonne])) ecarts.add('$table $id $colonne : saisi « $valeur », serveur « ${serveur?[colonne]} »');
        if (!egal(valeur, local?[colonne])) ecarts.add('$table $id $colonne : saisi « $valeur », poste « ${local?[colonne]} »');
      });
    });
    if (rappelSoins != null && (lignes['company_settings'] as Map)['rappel_soins_jours'] != rappelSoins) {
      ecarts.add('rappel des soins : poste $rappelSoins, serveur ${(lignes['company_settings'] as Map)['rappel_soins_jours']}');
    }
    expect(saisiElevage, isNotEmpty, reason: 'aucune saisie de l\'élevage relevée');
    expect(ecarts, isEmpty, reason: 'saisies de l\'élevage perdues (au serveur ou au poste) : $ecarts');

    // Trois journées hors ligne, puis le retour : envoi par lots de 50 au plus (H13b), tirage en plusieurs pages (S-T4).
    final c2 = caisse2.perturbateur;
    expect(c2.pagesMax, greaterThanOrEqualTo(2), reason: 'poste-caisse-2 : le tirage de retour n\'a servi qu\'une page');
    expect(c2.lignesParEnvoi.where((n) => n > 0).length, greaterThanOrEqualTo(2), reason: 'poste-caisse-2 : un seul envoi au retour (H13b non exercé)');
    expect(c2.lignesParEnvoi.where((n) => n > SyncEngine.tailleLot), isEmpty, reason: 'un envoi de plus de ${SyncEngine.tailleLot} lignes');

    // Session refusée (CFG-1 / S3) : la synchronisation automatique s'est arrêtée ; la reconnexion l'a reprise, et
    // rien n'est resté en attente (vérifié pour tous les postes plus haut).
    sessionsRefusees.forEach((poste, r) {
      expect(r.suspendue, isTrue, reason: '$poste : synchronisation automatique NON suspendue après le refus de session (S-T1)');
      expect(r.tentatives, 0, reason: '$poste : la synchronisation automatique a encore tenté ${r.tentatives} fois après le refus');
    });

    // Ticket S-T6 — la demande du web : servie, et le poste synchronisé dans les 30 s (plus le tirage).
    expect(demandeServie, isTrue, reason: 'S-T6 : la demande de synchronisation n\'a pas été lue par le poste');
    expect(delaiDemande, isNotNull, reason: 'S-T6 : la vente du web n\'est jamais arrivée sur le poste après la demande');
    expect(delaiDemande!.inSeconds, lessThanOrEqualTo(35), reason: 'S-T6 : arrivée après ${delaiDemande!.inSeconds} s');

    // Ticket 15.50 — réinitialisation au web : envoi sans la marque refusé, chaque poste purgé, rien ne ressuscite.
    expect(statutsApresReinitialisation.values.toSet(), {401},
        reason: '15.54 : les jetons des postes ne sont pas révoqués par la réinitialisation : $statutsApresReinitialisation');
    expect(statutEnvoiSansMarque, 409, reason: '15.50 : l\'envoi d\'un poste sans la marque de réinitialisation est accepté');
    apresReinitialisation.forEach((poste, r) {
      expect(r.activite, 0, reason: '$poste : ${r.activite} ligne(s) d\'activité gardée(s) après la réinitialisation');
      expect(r.enAttente, isEmpty, reason: '$poste : saisies encore en attente après la réinitialisation : ${r.enAttente}');
    });
    expect(apresReinitialisation[caisse1.nom]!.avertissements.join(' '), contains('pas encore été envoyée'),
        reason: 'la caisse 1 perd une vente non envoyée sans être prévenue');
    expect(serveurReinitialise['restantes'], isEmpty,
        reason: '15.50 : données d\'activité au serveur après la réinitialisation : ${serveurReinitialise['restantes']}');
  }

  // ── Rapport ─────────────────────────────────────────────────────────────────────────────────────────────────
  String rapport() {
    final b = StringBuffer()
      ..writeln('ESSAI À PLUSIEURS POSTES — ticket S-T9 (méthode TATACORA)')
      ..writeln('Graine : $graine   Journées : $jours   Base : $base   Serveur : $adresse')
      ..writeln('Fuseau des postes : $fuseau (S-T11 ; serveur : Africa/Porto-Novo)')
      ..writeln('Rejouer : ESSAI_FUSEAUX=$fuseau agrierp_flutter/outils/essai_multipostes.sh $graine')
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
      if (recettesDepenses.containsKey(p.nom)) {
        final e = recettesDepenses[p.nom]!;
        b.writeln('    Recettes et Dépenses (U13) : ${e.isEmpty ? 'identique au web' : 'ÉCARTS $e'}');
      }
    }
    b.writeln();
    if (recettesDepensesWeb.isNotEmpty) {
      final w = recettesDepensesWeb;
      b.writeln('RECETTES ET DÉPENSES DU WEB (U13), du ${w['du']} au ${w['au']} : recettes ${w['recettes']}, '
          'dépenses ${w['depenses']} (dont ${(w['lignes_depenses'] as List).where((l) => '${(l as Map)['libelle']}'.startsWith('Paie — ')).length} '
          'ligne(s) de paie), solde ${w['solde']} ; paie réglée au web : $paieWeb ; dépense archivée au web : $depenseArchiveeWeb');
      b.writeln();
    }
    final compte = inventaireCompte;
    if (compte != null) {
      b.writeln('INVENTAIRE COMPTÉ (S-T10, S-T12) : ${compte.nom}, attendu ${compte.attendu} '
          '(dont $pimentVenduHorsLigne sac(s) vendus hors ligne avant le comptage) ; '
          'serveur ${((etatServeur['stocks'] as Map?)?[compte.produit] as Map?)?['stock']} ; postes $stocksComptesAuPoste');
    }
    final web = inventaireWeb;
    if (web != null) {
      b.writeln('INVENTAIRE DU WEB APRÈS UN ACHAT HORS LIGNE (S-T12) : ${web.nom}, attendu ${web.attendu} ; '
          'serveur ${((etatServeur['stocks'] as Map?)?[web.produit] as Map?)?['stock']} ; postes $stocksInventaireWebAuPoste');
    }
    final c2 = _postesOuVide().isEmpty ? null : caisse2.perturbateur;
    b
      ..writeln('INTERBLOCAGES DE LA CAISSE WEB REJOUÉS PAR LE SERVEUR (S-T13) : ${interblocagesWeb.length} $interblocagesWeb')
      ..writeln('SESSIONS REFUSÉES (S-T1) : $sessionsRefusees')
      ..writeln('RETOUR DE poste-caisse-2 : pages au plus ${c2?.pagesMax}, lignes par envoi ${c2?.lignesParEnvoi}')
      ..writeln('DEMANDE DU WEB (S-T6) : délai $delaiDemande, servie $demandeServie, $tentativesDemande synchronisation(s)')
      ..writeln('RÉINITIALISATION (15.50) : premières synchronisations $statutsApresReinitialisation ; '
          'envoi sans marque → $statutEnvoiSansMarque ; postes $apresReinitialisation ; '
          'serveur ${serveurReinitialise['restantes']}')
      ..writeln();
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
