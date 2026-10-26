import 'dart:collection';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;

import '../database/app_database.dart';
import '../database/sync_columns.dart';
import '../temps/heure_benin.dart';
import 'fusion_referentiels.dart';
import 'perimetre_tirage.dart';

/// Ticket S3 — refus du serveur, avec un message que l'écran affiche tel quel.
class EchecSynchronisation implements Exception {
  const EchecSynchronisation(this.message, {this.statut});

  final String message;

  /// Ticket S-T1 — statut HTTP du refus (`null` : inconnu). La synchronisation automatique s'arrête sur un
  /// 401 / 403 ([estSessionRefusee]) jusqu'à une nouvelle connexion.
  final int? statut;

  /// Ticket S-T1 — session expirée (401) ou accès refusé (403) : retenter sans se reconnecter ne servirait à
  /// rien, et chaque tentative refusée serait une ligne de plus au journal du serveur.
  bool get estSessionRefusee => statut == 401 || statut == 403;

  /// Message pour un statut HTTP de refus ; `null` pour toute autre erreur (relancée telle quelle).
  static String? motifHttp(int? statut, Object? corps) {
    final serveur = corps is Map && corps['message'] is String
        ? corps['message'] as String
        : null;
    return switch (statut) {
      401 =>
        'Session expirée : reconnectez-vous. Vos saisies en attente sont conservées sur ce poste.',
      403 =>
        serveur ??
            'Accès refusé par le serveur : votre compte est désactivé ou n\'a pas les droits nécessaires.',
      429 =>
        'Trop de synchronisations rapprochées : réessayez dans une minute.',
      // Ticket 15.50 — envoi d'un poste qui n'a pas encore appliqué la réinitialisation du serveur.
      409 =>
        serveur ??
            'Envoi refusé : les données du serveur ont été réinitialisées. Synchronisez de nouveau.',
      _ => null,
    };
  }

  @override
  String toString() => message;
}

/// Résultat d'une synchronisation, rendu à l'écran tel quel.
///
/// ⚠️ LES REJETS SONT PORTÉS JUSQU'À L'UTILISATEUR. Le serveur répond table
/// par table avec les identifiants acceptés ET rejetés (avec motif) plutôt
/// qu'un « 200 OK » muet — précisément pour qu'un rejet ne disparaisse pas en
/// silence. Les avaler ici annulerait cette précaution : l'éleveur croirait
/// sa fiche envoyée alors qu'elle a été refusée.
class SyncOutcome {
  const SyncOutcome({
    required this.tire,
    required this.accepte,
    required this.rejete,
    this.motifs = const [],
    this.avertissements = const [],
    this.horsLigne = false,
  });

  const SyncOutcome.horsLigne()
    : tire = 0,
      accepte = 0,
      rejete = 0,
      motifs = const [],
      avertissements = const [],
      horsLigne = true;

  final int tire;
  final int accepte;
  final int rejete;
  final List<String> motifs;

  /// Ce que le tirage a constaté SANS refuser (ticket F0.84-bis) : journal à confirmer ou incomplet.
  /// Jamais un succès muet : l'écran le montre.
  final List<String> avertissements;
  final bool horsLigne;
}

/// Moteur de synchronisation — moitié cliente.
///
/// La moitié serveur existe déjà (`POST /api/auth/login`, `GET /api/sync/pull`,
/// `POST /api/sync/push`, jeton Sanctum nommé par appareil).
///
/// ⚠️ **PULL AVANT PUSH, TOUJOURS.** Pousser d'abord ferait travailler le
/// serveur sur des référentiels que l'appareil n'a pas encore reçus : une
/// vente portant un produit créé ailleurs serait rejetée pour « produit
/// inconnu » alors qu'il existe. Tirer d'abord rend ce rejet impossible.
///
/// ⚠️ **RIEN N'EST MARQUÉ `synced` AVANT L'ACCUSÉ DU SERVEUR.** Marquer à
/// l'envoi ferait disparaître de la file un enregistrement perdu en route :
/// l'appareil le croirait synchronisé et il n'existerait nulle part.
class SyncEngine {
  SyncEngine({
    required AppDatabase database,
    required Dio client,
    required String deviceId,
    Connectivity? connectivity,
    DateTime Function()? maintenant,
  }) : // `prefer_initializing_formals` suggère `this._client` : Dart
       // l'interdit sur un paramètre NOMMÉ privé. L'affectation explicite
       // est donc la seule forme possible ici.
       // ignore: prefer_initializing_formals
       _client = client,
       // ignore: prefer_initializing_formals
       _deviceId = deviceId,
       _db = database,
       _connectivity = connectivity ?? Connectivity(),
       _maintenant = maintenant ?? DateTime.now;

  final AppDatabase _db;
  final Dio _client;
  final String _deviceId;
  final Connectivity _connectivity;

  /// Horloge du poste — injectable pour les tests (F0.90). Elle date la RÉCEPTION d'une vente
  /// tirée du serveur (voir [_absorberVentes]).
  final DateTime Function() _maintenant;

  String get deviceId => _deviceId;

  Future<bool> estEnLigne() async {
    final etats = await _connectivity.checkConnectivity();
    return etats.any((e) => e != ConnectivityResult.none);
  }

  /// Ticket S-T6 — le serveur demande-t-il une synchronisation à ce poste (bouton « Demander la synchronisation des
  /// postes » du web) ? La lecture marque la demande servie au serveur : elle ne sert qu'une fois.
  ///
  /// ⚠️ NE LÈVE JAMAIS : hors ligne, serveur injoignable, session expirée ou réponse inattendue rendent `false`. Cette
  /// question est posée toutes les 30 s sans geste de l'utilisateur ; une erreur rouge à chaque fois apprendrait à
  /// ignorer les alertes (`SynchronisationAutomatique`).
  ///
  /// Ticket SW-1 — la même réponse porte le drapeau « resynchronisation demandée » (« Renvoyer vers ce poste » du web) :
  /// le poste le note ([resynchronisationServeur]) et rend `true` pour que la synchronisation parte aussitôt, qui
  /// repart d'un tirage complet puis acquitte (voir [_tirer]).
  Future<bool> demandeDuServeur() async {
    try {
      final reponse = await _client.get<Map<String, dynamic>>('/api/sync/demande');
      final donnees = reponse.data;
      if (donnees?['resynchronisation'] == true) {
        resynchronisationServeur.value = true;
        return true;
      }
      return donnees?['demande'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Ticket SW-1 (correction du client du 21/10/2026) — « Resynchronisation demandée par le serveur » : vrai de la
  /// lecture du drapeau (ping de 30 s ou tirage) jusqu'à son acquittement par le serveur. La modale
  /// « Synchronisation » l'écoute. Mémoire seule : le drapeau vit au serveur, aucune colonne locale (pas de migration).
  final ValueNotifier<bool> resynchronisationServeur = ValueNotifier<bool>(false);

  /// Ticket SW-1 — instant (ISO 8601, tel que le serveur l'a rendu) de la demande de resynchronisation que le tirage en
  /// cours doit honorer ; `null` : aucune. Renvoyé tel quel à l'acquittement.
  String? _resyncAHonorer;

  /// Ticket SW-1 — acquitte la resynchronisation honorée : le drapeau tombe au serveur. Ne lève JAMAIS : la
  /// resynchronisation a eu lieu, un échec ici (réseau, drapeau plus récent) laisse le drapeau levé et le prochain
  /// tirage la refera — au pire un tirage complet de trop, jamais une donnée manquante.
  Future<void> _acquitterResynchronisation(String demandeeLe) async {
    try {
      final reponse = await _client.post<Map<String, dynamic>>(
        '/api/sync/resynchronisation/acquittement',
        data: {'demandee_le': demandeeLe},
      );
      if (reponse.data?['acquittee'] == true) {
        if (_resyncAHonorer == demandeeLe) _resyncAHonorer = null;
        resynchronisationServeur.value = false;
      }
    } catch (_) {
      // Silencieux par construction : voir ci-dessus.
    }
  }

  /// Ticket S-T6 — comptes du serveur par table et par jour depuis [depuis] (`AAAA-MM-JJ`), pour le contrôle de
  /// cohérence de l'écran Synchronisation. Lève en cas d'échec : c'est un geste de l'utilisateur, qui doit savoir
  /// que le contrôle n'a pas pu se faire.
  Future<Map<String, dynamic>> coherenceDuServeur(String depuis) async {
    final reponse = await _client.get<Map<String, dynamic>>(
      '/api/sync/coherence',
      queryParameters: {'depuis': depuis},
    );
    return reponse.data ?? const <String, dynamic>{};
  }

  /// Ticket 15.50 — APPLIQUE UNE RÉINITIALISATION DU SERVEUR À CE POSTE : purge des données d'activité
  /// ([AppDatabase.purgerDonneesDActivite] : tables d'activité, stock et trésorerie à 0, curseur effacé) puis
  /// marque [marque] notée, celle que l'envoi renvoie et que le tirage compare. Rend le nombre de saisies
  /// non envoyées perdues. Un seul mécanisme : le tirage qui découvre une marque inconnue (15.50) et la
  /// réinitialisation lancée depuis ce poste (R-1, [reinitialiserDepuisCePoste]) passent par ici.
  Future<int> appliquerReinitialisation(String marque) async {
    final perdus = await _db.purgerDonneesDActivite();
    await _ecrireReglage(cleReinitialisation, marque);
    return perdus;
  }

  /// Ticket R-1 — RÉINITIALISATION LANCÉE DEPUIS CE POSTE (Paramètres > Réinitialisation).
  ///
  /// [reinitialiserLeServeur] appelle le serveur et rend la marque `data_reset_at` qu'il vient de poser. Après
  /// son succès seulement, la purge est IMMÉDIATE ([appliquerReinitialisation], sans attendre le tirage suivant).
  /// Échec : l'exception remonte et RIEN n'est purgé. Rend le nombre de saisies non envoyées perdues.
  ///
  /// ⚠️⚠️ AUCUNE SYNCHRONISATION NE S'INTERCALE. La tentative en cours est attendue d'abord ; pendant l'opération,
  /// [synchroniser] (synchronisation automatique, bouton, ou l'appelant juste après) reçoit une tentative qui
  /// attend sa fin puis tire sur la base purgée — sans `since`, le curseur ayant été effacé. Un tirage entremêlé
  /// réabsorberait après la purge des pages servies avant la réinitialisation, et noterait leur curseur.
  /// Si l'appel au serveur échoue alors que le serveur a pourtant réinitialisé (réponse perdue), cette tentative
  /// découvre la nouvelle marque au tirage et purge par la règle 15.50.
  Future<int> reinitialiserDepuisCePoste(Future<String> Function() reinitialiserLeServeur) async {
    for (var enCours = _tentativeEnCours; enCours != null; enCours = _tentativeEnCours) {
      try {
        await enCours;
      } catch (_) {
        // L'échec de la tentative précédente a été rendu à son propre appelant.
      }
    }
    final operation = (() async => appliquerReinitialisation(await reinitialiserLeServeur()))();
    final suivante = operation
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) => _synchroniserUneFois())
        .whenComplete(() => _tentativeEnCours = null);
    // Personne ne l'attend peut-être (échec de l'appel au serveur) : son échec éventuel n'est pas « non traité ».
    suivante.ignore();
    _tentativeEnCours = suivante;
    return operation;
  }

  /// Ticket H13 — la tentative en cours. Un second appelant (bouton « Synchroniser maintenant » pendant une
  /// synchronisation automatique) reçoit la MÊME tentative : deux tirages entremêlés écriraient deux fois le
  /// curseur, et deux envois simultanés acquitteraient deux fois les mêmes lignes.
  Future<SyncOutcome>? _tentativeEnCours;

  /// Ticket VL-2 — une synchronisation (tirage ou envoi) est-elle en cours ? Le verrouillage automatique par
  /// inactivité attend sa fin au lieu de l'interrompre.
  bool get enCours => _tentativeEnCours != null;

  Future<SyncOutcome> synchroniser() => _tentativeEnCours ??=
      _synchroniserUneFois().whenComplete(() => _tentativeEnCours = null);

  Future<SyncOutcome> _synchroniserUneFois() async {
    if (!await estEnLigne()) {
      // ⚠️ HORS LIGNE N'EST PAS UNE ERREUR. C'est le mode de fonctionnement
      // NORMAL de cette ferme : le réseau est intermittent à Ikpinlè. Un
      // message d'erreur rouge à chaque tentative apprendrait à l'utilisateur
      // à ignorer les alertes — y compris les vraies.
      return const SyncOutcome.horsLigne();
    }

    _avertissements.clear();
    final int tire0;
    final int accepte;
    final int rejete;
    final List<String> motifs;
    final int saisiesDeStockAvant;
    try {
      tire0 = await _tirer();
      saisiesDeStockAvant = await _saisiesDeStockEnAttente();
      (accepte, rejete, motifs) = await _pousser();
    } on DioException catch (e) {
      // ⚠️ TICKET S3 — UN REFUS DU SERVEUR EST NOMMÉ. Session expirée, compte désactivé ou débit dépassé
      // s'affichaient comme une erreur technique brute (« DioException [bad response] … ») : l'utilisateur
      // ne savait pas qu'il lui suffisait de se reconnecter. Les saisies en attente restent conservées.
      final motif = EchecSynchronisation.motifHttp(
        e.response?.statusCode,
        e.response?.data,
      );
      if (motif != null) {
        throw EchecSynchronisation(motif, statut: e.response?.statusCode);
      }
      rethrow;
    }
    var tire = tire0;

    // ⚠️ TIRAGE DE CONFIRMATION (ticket F0.73). Le poste tire AVANT de pousser : une
    // avance ou une imputation que le serveur vient d'accepter a modifié, côté serveur,
    // `amount_used` et `amount_paid` — que le poste affiche encore dans leur état
    // d'avant. Sans ce second tirage, une imputation acquittée cesse d'être « en attente »
    // (donc d'être déduite à l'écran) sans que le solde servi l'ait absorbée : le solde
    // REMONTERAIT jusqu'à la synchronisation suivante, et l'utilisateur pourrait imputer
    // une deuxième fois ce qui l'est déjà. Un échec réseau ici n'annule rien : tout est
    // déjà acquitté.
    // F0.78 : même tirage pour un courrier accepté — sans lui, sa référence resterait « — »
    // jusqu'à la synchronisation suivante.
    // F0.79 : et pour un document archivé accepté — le tirage de confirmation montre ce que
    // le serveur a réellement retenu (le poste n'invente aucune valeur côté serveur).
    // F0.80 : et pour un document administratif accepté — même raison.
    // U9 : et pour un ajustement d'inventaire acquitté — il n'est plus projeté par `JournalStocks`, et sans ce
    // tirage son mouvement manquerait aux « Écarts d'Inventaire » jusqu'à la synchronisation suivante. (Ventes,
    // achats et fiches : leur mouvement descend au tirage suivant ; voir `JournalStocks`.)
    if (_financiersAcquittes > 0 ||
        _ventesDeBetailAcquittees > 0 ||
        _courriersAcquittes > 0 ||
        _archivesAcquittees > 0 ||
        _documentsAcquittes > 0 ||
        await _saisiesDeStockEnAttente() < saisiesDeStockAvant) {
      try {
        tire += await _tirer();
      } on DioException {
        // L'affichage reste celui du tirage précédent jusqu'à la prochaine synchronisation.
      }
    }

    // Ticket H2 — la liaison a abouti (refus compris) : « Dernière synchronisation réussie » prend l'heure
    // du SERVEUR, celle du tirage qui vient d'avoir lieu (`server_time`), jamais l'horloge du poste.
    final etat = await _db.etatDeSynchronisation();
    if (etat?.lastPulledAt != null) {
      await _db.noterEtatDeSynchronisation(reussi: etat!.lastPulledAt);
    }

    return SyncOutcome(
      tire: tire,
      accepte: accepte,
      rejete: rejete,
      motifs: motifs,
      avertissements: List.of(_avertissements),
    );
  }

  /// Ticket U9 — ajustements d'inventaire EN ATTENTE (`stock_adjustments`) : leur nombre baisse quand l'envoi en
  /// acquitte (ou en refuse), et le tirage de confirmation rapporte alors le mouvement que le serveur a créé.
  Future<int> _saisiesDeStockEnAttente() async {
    final ligne = await _db
        .customSelect(
          "SELECT COUNT(*) AS n FROM stock_adjustments WHERE sync_status = 'pending'",
        )
        .getSingle();
    return ligne.read<int>('n');
  }

  /// Avances, imputations, retours et remboursements fournisseurs acceptés par le dernier
  /// envoi (voir [synchroniser]) : tous modifient, côté serveur, un état que le poste affiche
  /// (`amount_used`, `returned_at`, créance ouverte) et que seul un second tirage rapporte.
  int _financiersAcquittes = 0;

  /// Ticket S-T9 — ventes de bétail (une ligne au moins porte une bande) acceptées par le dernier envoi : le serveur
  /// les a inscrites sur la fiche du jour, que le poste n'a pas renvoyée si elle était déjà synchronisée
  /// (`FicheJournaliereRepository.repercuterVente`). Le tirage de confirmation rapporte la fiche du serveur.
  int _ventesDeBetailAcquittees = 0;

  /// Courriers acceptés par le dernier envoi : la référence `CR-AAAA-NNN` que le serveur
  /// vient d'attribuer ne descend qu'au tirage suivant (F0.78).
  int _courriersAcquittes = 0;

  /// Documents archivés acceptés par le dernier envoi (F0.79) : déclenchent le tirage de
  /// confirmation.
  int _archivesAcquittees = 0;

  /// Documents administratifs acceptés par le dernier envoi (F0.80) : déclenchent le tirage de
  /// confirmation.
  int _documentsAcquittes = 0;

  /// Réglages (table `app_settings`, sans changement de schéma) du journal comptable — F0.84-bis.
  ///
  ///  - [cleJournalResync] : la resynchronisation UNIQUE du journal a été faite. Absente = le
  ///    premier tirage après la mise à jour redemande TOUT le journal (sans `since`) : un poste
  ///    corrompu avant F0.84 (lignes doublées sur une écriture ancienne, jamais retouchée) n'est
  ///    pas guéri par la purge, et le tirage incrémental ne la servira jamais.
  ///  - [cleJournalIncomplet] : le dernier tirage complet n'a pas pu rapporter toutes les écritures
  ///    annoncées actives. Présente = le prochain tirage est de nouveau complet (borné : 2 requêtes).
  ///  - [cleJournalVidageAttendu] : le serveur a annoncé UNE fois « aucune écriture active » alors
  ///    que le poste en contient. Présente = la prochaine annonce vide sera crue et purgera.
  ///  - [cleJournalResyncCreation] (F0.85) : la resynchronisation UNIQUE qui rapporte l'instant de
  ///    CRÉATION des écritures déjà présentes (colonne `created_at`, ajoutée au schéma v37). Il sert
  ///    au Grand Livre à départager deux pièces du même jour comme le serveur. ⚠️ Le réglage n'est
  ///    écrit que si le serveur SERT cette date : face à un serveur qui ne la sert pas encore (ticket
  ///    15.29 non déployé), le tirage reste complet à chaque synchronisation tant que cela dure —
  ///    sans quoi la date ne serait plus jamais rapportée une fois le serveur mis à jour.
  ///  - [cleFichesResync] (F0.94) : la resynchronisation UNIQUE des fiches journalières. Avant
  ///    F0.94 le poste n'absorbait pas `livestock_daily_entries` ; un poste déjà en service a un
  ///    curseur, et le tirage incrémental ne servirait JAMAIS les fiches modifiées avant lui (tout
  ///    l'historique saisi sur le web). Absente = le prochain tirage est complet, une fois.
  static const cleFichesResync = 'fiches_resync_f094';

  /// F0.95 — resynchronisation UNIQUE des fiches après le passage au schéma v38 : les fiches
  /// `synced` absorbées en v37 n'ont pas les colonnes d'effectif par catégorie, et le curseur est
  /// passé (le tirage incrémental ne les resservirait jamais). ⚠️ Écrite APRÈS tous les
  /// absorbeurs, et SEULEMENT si le serveur sert la ventilation (15.39) : face à un serveur pas
  /// encore à jour, le tirage reste complet à chaque synchronisation tant que cela dure (même
  /// règle que [cleJournalResyncCreation]) — sinon les colonnes ne descendraient jamais.
  static const cleFichesResyncCategories = 'fiches_resync_f095';

  /// Ticket U4 (D-U4) — resynchronisation UNIQUE des lignes de vente et d'achat. Avant U4 le serveur ne
  /// servait pas `sale_lines` / `purchase_lines` ; un poste déjà en service a un curseur, et le tirage
  /// incrémental ne resservirait JAMAIS les ventes et achats antérieurs — donc jamais leurs lignes (le Top 5
  /// et sa marge resteraient faux pour tout l'historique). ⚠️ Écrite APRÈS tous les absorbeurs, et SEULEMENT
  /// si le serveur sert les lignes des pièces qu'il sert : face à un serveur antérieur à U4 (ventes ou achats
  /// servis sans leurs lignes), le tirage reste complet tant que cela dure — même règle que
  /// [cleFichesResyncCategories].
  static const cleLignesResync = 'lignes_resync_u4';

  /// Ticket U8 — resynchronisation UNIQUE des lignes de retour fournisseur (`purchase_returns`). Avant U8 le
  /// serveur ne les servait pas ; un poste déjà en service a un curseur, et le tirage incrémental ne resservirait
  /// JAMAIS les achats retournés avant lui (« Écarts / Retours » compterait faux pour tout l'historique). Même
  /// règle que [cleLignesResync] : écrite après tous les absorbeurs, et seulement si le serveur sert les retours
  /// des achats qu'il sert.
  static const cleRetoursResync = 'retours_resync_u8';

  /// Ticket U9 — resynchronisation UNIQUE du grand livre des stocks (`stock_movements`). Avant U9 le serveur ne le
  /// servait pas ; un poste déjà en service a un curseur, et le tirage incrémental ne resservirait JAMAIS les
  /// mouvements antérieurs (rotation, écarts d'inventaire et soldes d'œufs faux pour tout l'historique). Même règle
  /// que [cleLignesResync] : écrite après tous les absorbeurs, et seulement si les produits servis l'ont été avec
  /// leur grand livre (un serveur qui sert `products` sans `stock_movements` est antérieur à U9).
  static const cleMouvementsResync = 'mouvements_resync_u9';

  /// Ticket U13 — resynchronisation UNIQUE des dépenses et de la paie. Avant U13 le serveur ne servait ni `expenses`
  /// ni `payslips` ; un poste déjà en service a un curseur, et le tirage incrémental ne resservirait JAMAIS les
  /// dépenses saisies au web ou sur un autre poste avant lui, ni la paie déjà réglée, ni l'archivage, fait au web, des
  /// dépenses que CE poste a déjà acquittées (« Recettes et Dépenses » resterait faux pour tout l'historique). Même
  /// règle que [cleMouvementsResync] : écrite après tous les absorbeurs, et seulement si le serveur sert les dépenses
  /// (un serveur qui sert `products` sans `expenses`, sans paginer, est antérieur à U13). ⚠️ Un poste déjà paginé dont
  /// le compte reçoit désormais ces tables repart aussi d'un tirage complet par la règle du périmètre (S-T4) ; cette
  /// clé couvre le poste dont le périmètre est inconnu (dernier tirage non paginé).
  static const cleDepensesResync = 'depenses_resync_u13';

  /// Ticket U14 — resynchronisation UNIQUE des dépenses après le passage au schéma v48 : les dépenses `synced` absorbées
  /// avant n'ont ni `status` (badge et filtre « Statut » du Blade) ni `accounting_entry_id` (une dépense comptabilisée ne
  /// change plus de montant, de compte de charge ni de compte de trésorerie), et le curseur est passé. Écrite après tous
  /// les absorbeurs, et seulement si les dépenses servies portent ces deux clés (serveur postérieur à U14).
  static const cleDepensesResyncU14 = 'depenses_resync_u14';

  /// Ticket DEP4 — resynchronisation UNIQUE des dépenses après le passage au schéma v56 : les dépenses `synced` absorbées
  /// avant n'ont pas leurs LIGNES (et le plan local peut manquer pour la conversion locale) ; le curseur est passé.
  /// Écrite après tous les absorbeurs, et seulement si le serveur sert les lignes (`expense_lines`) — ou ne sert pas les
  /// dépenses du tout (rien à resynchroniser). Un serveur qui sert les dépenses SANS leurs lignes est antérieur à DEP3 :
  /// le tirage reste complet tant que cela dure (même règle que U9).
  static const cleDepensesResyncDep1 = 'depenses_resync_dep1';

  /// Vrai si le dernier tirage a servi au moins une dépense SANS `status` (serveur antérieur à U14) — renseigné par
  /// [_absorberDepenses].
  bool _depensesSansStatut = false;

  /// Les dix colonnes de ventilation du serveur (migration `2026_10_15_000001`, 15.39).
  static const colonnesVentilation = [
    'mort_repro',
    'mort_sevre',
    'mort_jeune',
    'don_repro',
    'don_sevre',
    'don_jeune',
    'passage_sevre_jeune',
    'cat_depart_repro',
    'cat_depart_sevre',
    'cat_depart_jeune',
  ];

  /// Vrai si le dernier tirage a servi au moins une fiche SANS ces colonnes (serveur antérieur à
  /// 15.39) — renseigné par [_absorberFichesJournalieres].
  bool _fichesSansVentilation = false;

  /// Ticket U10 — resynchronisation UNIQUE des fiches après le passage au schéma v45 : les fiches `synced` absorbées
  /// avant n'ont ni `vente_sexe`, ni `vente_montant`, ni le traitement, la dose et les symptômes (Tableau 2 et « CA
  /// Ventes du Lot » du Rapport Élevage), et le curseur est passé. Même règle que [cleFichesResyncCategories] :
  /// écrite après tous les absorbeurs, et seulement si les fiches servies portent ces colonnes.
  static const cleFichesResyncU10 = 'fiches_resync_u10';

  /// Les cinq colonnes de la fiche reçues pour le Rapport Élevage (ticket U10).
  static const colonnesRapportElevage = [
    'vente_sexe',
    'vente_montant',
    'treatment_product_id',
    'treatment_dose',
    'symptomes',
  ];

  /// Vrai si le dernier tirage a servi au moins une fiche SANS [colonnesRapportElevage].
  bool _fichesSansColonnesRapport = false;
  /// Ticket 15.50 — instant de la dernière réinitialisation du serveur que CE poste a appliquée
  /// (purge faite). Renvoyé à chaque envoi : le serveur refuse (409) celui d'un poste qui ne l'a pas.
  static const cleReinitialisation = 'donnees_reinitialisees_le';
  static const cleJournalResync = 'journal_resync_f084bis';
  static const cleJournalResyncCreation = 'journal_resync_f085';
  static const cleJournalIncomplet = 'journal_incomplet';
  static const cleJournalVidageAttendu = 'journal_vidage_attendu';

  /// Ce que la synchronisation en cours a constaté sans refuser (voir [SyncOutcome.avertissements]).
  final List<String> _avertissements = [];

  /// Écritures annoncées actives par le dernier tirage et toujours absentes du poste après
  /// absorption (renseigné par [_absorberJournal]).
  int _journalManquants = 0;

  /// Vrai si le dernier tirage a servi au moins une écriture SANS la clé `created_at` (serveur
  /// antérieur au ticket 15.29) — renseigné par [_absorberJournal].
  bool _journalSansDateCreation = false;

  Future<String?> _lireReglage(String cle) async {
    final ligne = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(cle))).getSingleOrNull();
    return ligne?.value;
  }

  Future<void> _ecrireReglage(String cle, String valeur) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: cle, value: valeur),
      );

  Future<void> _effacerReglage(String cle) =>
      (_db.delete(_db.appSettings)..where((t) => t.key.equals(cle))).go();

  /// Récupère du serveur tout ce qui a changé depuis le dernier tirage.
  ///
  /// [complet] : tirage SANS `since`. Il sert (1) à la resynchronisation unique du journal,
  /// (2) à la relance unique quand le serveur annonce des écritures actives que le poste n'a
  /// pas, (3) au tirage qui suit un journal resté incomplet, (4) au tirage qui suit un
  /// changement de périmètre (ticket S-T4, voir [PerimetreTirage]).
  ///
  /// 🔴→✅ TICKET S-T4 (méthode TATACORA) — TIRAGE PAGINÉ. Un poste resté longtemps hors ligne
  /// recevait tout en UNE réponse (délai de réception de 30 s, mémoire). Le poste demande la page 1
  /// (`page=1`), puis chaque page suivante avec le jeton que le serveur lui rend (`page_suivante`),
  /// jusqu'à `page_suivante: null` :
  ///  - ⚠️⚠️ CHAQUE PAGE EST ABSORBÉE DANS UNE TRANSACTION : un absorbeur strict qui refuse une
  ///    ligne annule TOUTE la page, jamais une moitié ;
  ///  - ⚠️⚠️ LE CURSEUR N'AVANCE QU'APRÈS LA DERNIÈRE PAGE (`server_time` n'y vient qu'elle). Un
  ///    échec au milieu (réseau, refus) laisse le curseur précédent : le tirage suivant repart de
  ///    lui, et ce que les pages déjà absorbées ont écrit revient, remplacé par identifiant (rien de
  ///    perdu, aucun doublon) ;
  ///  - une pièce descend toujours AVEC ses lignes, dans la même page (le serveur ne la coupe pas) ;
  ///  - les resynchronisations uniques (F0.84-bis à U10) gardent leur logique : leur réglage n'est
  ///    écrit qu'après la dernière page ;
  ///  - un serveur antérieur à S-T4 ignore `page` et répond en une fois (sans `page_suivante`) :
  ///    cette réponse est la seule page.
  Future<int> _tirer({bool complet = false}) async {
    // ⚠️ Lecture TOLÉRANTE : voir `etatDeSynchronisation` (table dupliquée).
    final etat = await _db.etatDeSynchronisation();

    final resyncFaite = await _lireReglage(cleJournalResync) != null;
    final resyncCreationFaite =
        await _lireReglage(cleJournalResyncCreation) != null;
    final etaitIncomplet = await _lireReglage(cleJournalIncomplet) != null;
    final resyncFichesFaite = await _lireReglage(cleFichesResync) != null;
    final resyncCategoriesFaite =
        await _lireReglage(cleFichesResyncCategories) != null;
    final resyncLignesFaite = await _lireReglage(cleLignesResync) != null;
    final resyncRetoursFaite = await _lireReglage(cleRetoursResync) != null;
    final resyncMouvementsFaite =
        await _lireReglage(cleMouvementsResync) != null;
    final resyncFichesU10Faite =
        await _lireReglage(cleFichesResyncU10) != null;
    final resyncDepensesFaite =
        await _lireReglage(cleDepensesResync) != null;
    final resyncDepensesU14Faite =
        await _lireReglage(cleDepensesResyncU14) != null;
    final resyncDepensesDep1Faite =
        await _lireReglage(cleDepensesResyncDep1) != null;
    final toutRedemander =
        complet ||
        !resyncFaite ||
        !resyncCreationFaite ||
        etaitIncomplet ||
        !resyncFichesFaite ||
        !resyncCategoriesFaite ||
        !resyncLignesFaite ||
        !resyncRetoursFaite ||
        !resyncMouvementsFaite ||
        !resyncFichesU10Faite ||
        !resyncDepensesFaite ||
        !resyncDepensesU14Faite ||
        !resyncDepensesDep1Faite;
    final since = !toutRedemander && etat?.lastPulledAt != null
        ? etat!.lastPulledAt!.toUtc().toIso8601String()
        : null;

    var recus = 0;
    _journalManquants = 0;
    _journalSansDateCreation = false;
    _fichesSansVentilation = false;
    _fichesSansColonnesRapport = false;
    _depensesSansStatut = false;

    // Ticket S-T4 — ce que les pages ont apporté : clés vues (contrôles « serveur antérieur à… »), périmètre (tables
    // servies à TOUTES les pages), dernière page (curseur).
    var corps = const <String, dynamic>{};
    final cles = <String>{};
    Set<String>? perimetre;
    var pagine = false;
    String? jeton;

    for (var page = 1; ; page++) {
      final reponse = await _client.get<Map<String, dynamic>>(
        '/api/sync/pull',
        queryParameters: {
          'since': ?since,
          'page': page,
          'curseur_page': ?jeton,
        },
      );

      corps = reponse.data ?? const <String, dynamic>{};
      pagine = corps.containsKey('page_suivante');
      final servies = PerimetreTirage.depuisReponse(corps);

      if (page == 1) {
        // 🔴→✅ Ticket SW-1 — LE SERVEUR DEMANDE UNE RESYNCHRONISATION (« Renvoyer vers ce poste » au web : le portable a
        // servi de base pendant la panne de ce poste, qui doit récupérer ce qui y a été saisi). Rien n'est absorbé de
        // cette page : le tirage repart, COMPLET (sans `since`), une fois ; l'acquittement suit son dernier curseur.
        final demandee = corps['resynchronisation_demandee_le'];
        if (demandee is String && demandee.isNotEmpty) {
          _resyncAHonorer = demandee;
          resynchronisationServeur.value = true;
          if (!toutRedemander) return _tirer(complet: true);
        }

        // 🔴→✅ Ticket 15.50 — LE SERVEUR A ÉTÉ RÉINITIALISÉ depuis la dernière purge de ce poste : ses
        // données d'activité sont effacées AVANT toute absorption et AVANT tout envoi (le tirage précède
        // toujours l'envoi). Sinon le poste garderait des bandes et des ventes disparues du serveur, et les
        // renverrait. La marque est notée aussitôt : la relance complète ci-dessous ne purge pas deux fois.
        final reinitialisation = corps['data_reset_at'];
        if (reinitialisation is String &&
            reinitialisation != await _lireReglage(cleReinitialisation)) {
          final perdus = await appliquerReinitialisation(reinitialisation);
          final le = HeureBenin.depuisInstant(DateTime.parse(reinitialisation));
          final date =
              '${le.day.toString().padLeft(2, '0')}/${le.month.toString().padLeft(2, '0')}/${le.year}';
          // Un poste neuf (jamais tiré, rien en attente) n'avait rien : aucun avertissement à lui faire lire.
          if (perdus > 0 || etat?.lastPulledAt != null) {
            _avertissements.add(
              'Les données du serveur ont été réinitialisées le $date : celles de ce poste ont été '
              'effacées${perdus > 0 ? ', dont $perdus saisie(s) qui n\'avai(en)t pas encore été envoyée(s)' : ''}.',
            );
          }
          // Un tirage incrémental ne resservirait pas l'existant : tout redemander, une fois.
          if (!toutRedemander) return _tirer(complet: true);
        }

        // Ticket S-T4 — RÈGLE DU CHANGEMENT DE RÔLE (voir [PerimetreTirage]) : une table servie maintenant et pas
        // au tirage précédent n'a jamais été tirée jusqu'au curseur. Rien n'est absorbé de cette page : le tirage
        // repart, complet, une fois (sans `since`, la règle ne se redéclenche pas).
        if (since != null &&
            servies != null &&
            PerimetreTirage.elargi(await PerimetreTirage.lire(_db), servies)) {
          return _tirer(complet: true);
        }
      }

      if (servies != null) {
        perimetre = perimetre == null ? servies : perimetre.intersection(servies);
      }
      cles.addAll(corps.keys);

      final aAbsorber = corps;
      await _db.transaction(() async {
        recus += await _absorberPage(aAbsorber);
      });

      final suivante = corps['page_suivante'];
      if (!pagine || suivante == null) break;
      // Un jeton vide, ou le même que celui qui vient d'être servi, ferait tourner le tirage sans fin.
      if (suivante is! String || suivante.isEmpty || suivante == jeton) {
        throw const FormatException(
          'Tirage refusé : jeton de la page suivante illisible.',
        );
      }
      jeton = suivante;
    }

    // ⚠️ F0.84-bis : le serveur annonce des écritures actives que le poste n'a pas (cas réel :
    // créée entre la requête et `server_time`, donc plus jamais servie par `since`). UNE relance,
    // sans `since` — jamais une boucle. La relance note elle-même le curseur.
    if (_journalManquants > 0 && !complet) {
      return recus + await _tirer(complet: true);
    }
    if (_journalManquants > 0) {
      await _ecrireReglage(cleJournalIncomplet, '1');
      _avertissements.add(
        'Journal comptable incomplet : $_journalManquants écriture(s) annoncée(s) '
        'par le serveur manquent encore sur ce poste. Les états peuvent être faux ; '
        'la prochaine synchronisation redemandera tout le journal.',
      );
    } else if (etaitIncomplet) {
      await _effacerReglage(cleJournalIncomplet);
    }
    if (!resyncFaite) {
      await _ecrireReglage(cleJournalResync, '1');
    }
    // F0.85 : la date de création n'est « rapportée » que si le serveur la sert.
    if (!resyncCreationFaite && !_journalSansDateCreation) {
      await _ecrireReglage(cleJournalResyncCreation, '1');
    }
    // F0.94 : écrit seulement ICI, après TOUS les absorbeurs — un lot de fiches refusé lève une
    // `FormatException` plus haut, et la resynchronisation sera retentée au tirage suivant.
    if (!resyncFichesFaite) {
      await _ecrireReglage(cleFichesResync, '1');
    }
    // F0.95 : même place, et seulement si le serveur sert la ventilation par catégorie.
    if (!resyncCategoriesFaite && !_fichesSansVentilation) {
      await _ecrireReglage(cleFichesResyncCategories, '1');
    }
    // U10 : même place, et seulement si les fiches servies portent les colonnes du Rapport Élevage.
    if (!resyncFichesU10Faite && !_fichesSansColonnesRapport) {
      await _ecrireReglage(cleFichesResyncU10, '1');
    }
    // U14 : même place, et seulement si les dépenses servies portent leur statut et leur écriture.
    if (!resyncDepensesU14Faite && !_depensesSansStatut) {
      await _ecrireReglage(cleDepensesResyncU14, '1');
    }
    // DEP4 : même place, et seulement si le serveur sert les lignes des dépenses (ou ne sert pas les dépenses).
    if (!resyncDepensesDep1Faite &&
        (cles.contains('expense_lines') || !cles.contains('expenses'))) {
      await _ecrireReglage(cleDepensesResyncDep1, '1');
    }
    // U4, U8, U9 : « serveur antérieur » se lit à une pièce servie SANS ses lignes (ou des produits sans leur
    // grand livre). ⚠️ Ticket S-T4 — un serveur qui PAGINE est postérieur à U10 : la question ne se pose plus, et
    // une table simplement NON SERVIE à ce compte (le grand livre des stocks n'est pas servi au caissier) ne doit
    // pas laisser croire à un serveur ancien — la resynchronisation unique resterait sinon à refaire à chaque tirage.
    // U4 : même place, et seulement si les ventes et achats servis l'ont été avec leurs lignes.
    final lignesNonServies =
        !pagine &&
        ((cles.contains('sales') && !cles.contains('sale_lines')) ||
            (cles.contains('purchases') && !cles.contains('purchase_lines')));
    if (!resyncLignesFaite && !lignesNonServies) {
      await _ecrireReglage(cleLignesResync, '1');
    }
    // U8 : même place, et seulement si les achats servis l'ont été avec leurs retours.
    if (!resyncRetoursFaite &&
        !(!pagine &&
            cles.contains('purchases') &&
            !cles.contains('purchase_returns'))) {
      await _ecrireReglage(cleRetoursResync, '1');
    }

    // U9 : même place, et seulement si le serveur sert le grand livre des stocks. Un serveur qui sert les produits
    // SANS leur grand livre est antérieur à U9 : le tirage reste complet tant que cela dure (même règle que U4 pour
    // les pièces servies sans leurs lignes).
    if (!resyncMouvementsFaite &&
        !(!pagine &&
            cles.contains('products') &&
            !cles.contains('stock_movements'))) {
      await _ecrireReglage(cleMouvementsResync, '1');
    }

    // U13 : même place, et seulement si le serveur sert les dépenses. Un serveur qui sert les produits SANS les
    // dépenses (réponse non paginée) est antérieur à U13 : le tirage reste complet tant que cela dure.
    if (!resyncDepensesFaite &&
        !(!pagine &&
            cles.contains('products') &&
            !cles.contains('expenses'))) {
      await _ecrireReglage(cleDepensesResync, '1');
    }

    // Ticket S-T4 — le périmètre de CE tirage, gardé pour le suivant. Une réponse non paginée (serveur antérieur)
    // a servi toutes les tables : périmètre inconnu, rien à resynchroniser au prochain élargissement.
    if (pagine && perimetre != null) {
      await PerimetreTirage.ecrire(_db, perimetre);
    } else if (!pagine) {
      await PerimetreTirage.effacer(_db);
    }

    // ⚠️ L'HORODATAGE VIENT DU SERVEUR (`server_time`), jamais de l'appareil.
    // Une tablette dont l'horloge retarde redemanderait sans cesse les mêmes
    // changements ; une qui avance en sauterait définitivement.
    // Ticket S-T4 : `server_time` n'est servi qu'à la DERNIÈRE page — celle que `corps` tient ici.
    final horlogeServeur = corps['server_time'];
    if (horlogeServeur is String) {
      await _db.noterEtatDeSynchronisation(
        tire: DateTime.parse(horlogeServeur),
      );
    }

    // Ticket SW-1 — le tirage COMPLET que le serveur avait demandé est fini et son curseur noté : acquittement.
    final aAcquitter = _resyncAHonorer;
    if (aAcquitter != null && since == null) {
      await _acquitterResynchronisation(aAcquitter);
    }

    return recus;
  }

  /// Ticket S-T4 — une page du tirage, absorbée table par table dans l'ordre des dépendances (l'appelant
  /// l'enveloppe dans UNE transaction). Une clé ABSENTE (table non servie à ce compte, ou pas sur cette page) ne
  /// touche à rien : chaque absorbeur l'ignore.
  Future<int> _absorberPage(Map<String, dynamic> corps) async {
    var recus = 0;

    recus += await _absorberCategories(corps['product_categories']);
    recus += await _absorberProduits(corps['products']);
    recus += await _absorberBandes(corps['livestock_lots']);
    // F0.94 — APRÈS les bandes : une bande créée sur le web arrive avec ses fiches dans le même
    // tirage, et une fiche d'une bande inconnue est refusée.
    recus += await _absorberFichesJournalieres(
      corps['livestock_daily_entries'],
    );
    // Ticket 15.46 — APRÈS les bandes : un transfert d'une bande inconnue est refusé.
    recus += await _absorberTransferts(corps['livestock_transfers']);
    // Ticket H8b — APRÈS les bandes : une entrée ou une intervention d'une bande inconnue est refusée.
    recus += await _absorberInfirmerie(corps['infirmary_records']);
    recus += await _absorberCalendrierVeterinaire(
      corps['veterinary_calendar_events'],
    );
    recus += await _absorberRations(corps['feed_ration_standards']);
    // Ticket U2 (D-U2) — objectifs de GMQ, seule source des cartes du Dashboard Élevage.
    recus += await _absorberObjectifsCroissance(corps['growth_standards']);
    recus += await _absorberRemanences(corps['veterinary_withdrawal_periods']);
    recus += await _absorberProphylaxie(
      corps['prophylaxis_schedule_standards'],
    );
    recus += await _absorberSoins(corps['veterinary_records']);
    recus += await _absorberReproduction(
      corps['livestock_reproduction_events'],
    );
    recus += await _absorberClients(corps['customers']);
    recus += await _absorberCreances(corps['receivables']);
    recus += await _absorberAvances(corps['customer_advances']);
    recus += await _absorberRelances(corps['customer_reminders']);
    recus += await _absorberProvendes(corps['feed_types']);
    recus += await _absorberNumerotation(corps['elevage_numbering']);
    recus += await _absorberFournisseurs(corps['suppliers']);
    recus += await _absorberBonsCommande(corps['purchase_orders']);
    recus += await _absorberAchats(corps['purchases']);
    // Ticket U4 (D-U4) — APRÈS les achats : une ligne d'un achat non servi est refusée.
    recus += await _absorberLignesDAchat(
      corps['purchases'],
      corps['purchase_lines'],
    );
    // Ticket U8 — APRÈS les achats : une ligne de retour d'un achat non servi est refusée.
    recus += await _absorberRetoursDAchat(
      corps['purchases'],
      corps['purchase_returns'],
    );
    recus += await _absorberCreancesFournisseurs(corps['supplier_credits']);
    recus += await _absorberDettes(corps['payables']);
    recus += await _absorberVentes(corps['sales']);
    // Ticket U4 (D-U4) — APRÈS les ventes : une ligne d'une vente non servie est refusée.
    recus += await _absorberLignesDeVente(
      corps['sales'],
      corps['sale_lines'],
    );
    // Tickets AV1 / AV2 — APRÈS les ventes et les produits : l'avoir d'une vente ou d'un produit inconnu du poste est refusé.
    recus += await _absorberAvoirs(corps['credit_notes']);
    // Ticket U9 — APRÈS les produits : un mouvement d'un produit inconnu du poste est refusé.
    recus += await _absorberMouvementsStock(corps['stock_movements']);
    recus += await _absorberEmployes(corps['employees']);
    recus += await _absorberStagiaires(corps['internships']);
    recus += await _absorberPointages(corps['attendance_records']);
    recus += await _absorberCourriers(corps['mails']);
    // Ticket DEV — devis du serveur (table mixte : les saisies du poste en attente ne sont jamais écrasées).
    recus += await _absorberDevis(corps['quotes']);
    recus += await _absorberDocuments(corps['administrative_documents']);
    recus += await _absorberArchives(corps['archived_documents']);
    recus += await _absorberPlanComptable(corps['chart_of_accounts']);
    recus += await _absorberExercices(corps['fiscal_years']);
    recus += await _absorberJournal(
      corps['accounting_entries'],
      corps['accounting_entry_ids'],
      corps['accounting_entry_lines'],
    );
    recus += await _absorberEntreprise(corps['company_settings']);
    recus += await _absorberModules(corps['modules_config']);
    recus += await _absorberRoles(corps['roles']);
    recus += await _absorberUtilisateurs(corps['users']);
    recus += await _absorberAudit(corps['audit_logs']);
    recus += await _absorberNotifications(corps['notifications']);
    recus += await _absorberRevenusDeBande(corps['lot_revenues']);
    recus += await _absorberSujets(corps['animals']);
    recus += await _absorberEspeces(corps['livestock_species']);
    recus += await _absorberModelesAttestation(corps['attestation_templates']);
    recus += await _absorberCompteursAttestation(corps['attestation_counts']);
    recus += await _absorberComptesTresorerie(corps['treasury_accounts']);
    recus += await _absorberCategoriesDepense(corps['expense_categories']);
    // Ticket U13 — dépenses du serveur (table mixte) et paie réglée (lecture seule).
    // Ticket DEP4 — centres de coût (référentiel), puis les dépenses AVEC leurs lignes (`expense_lines`, au curseur de leur
    // dépense : jamais une ligne sans son en-tête).
    recus += await _absorberCentresDeCout(corps['cost_centers']);
    recus += await _absorberDepenses(corps['expenses'], corps['expense_lines']);
    recus += await _absorberPaie(corps['payslips']);

    return recus;
  }

  Future<int> _absorberCategories(Object? brut) async {
    final lignes = _lignes(brut);

    await _db.batch((b) {
      for (final l in lignes) {
        final ligne = ProductCategoriesCompanion.insert(
          id: l['id'] as String,
          label: (l['label'] ?? '') as String,
          isActive: Value(_bool(l['is_active'])),
          updatedAt: Value(_instantTechnique(l['updated_at'])),
        );
        // Le serveur fait autorite sur les referentiels : l'existant local est
        // remplace, jamais fusionne champ par champ.
        b.insert(
          _db.productCategories,
          ligne,
          onConflict: DoUpdate((_) => ligne),
        );
      }
    });

    return lignes.length;
  }

  Future<int> _absorberProduits(Object? brut) async {
    final lignes = _lignes(brut);

    // ⚠️⚠️ UN PRODUIT `pending` OU `conflict` N'EST PAS ÉCRASÉ PAR LE TIRAGE : il
    // n'existe (ou n'a changé) que sur ce poste, et l'effacer perdrait la saisie.
    // Un produit refusé (`conflict`) attend la décision de l'utilisateur.
    final protegees = {
      for (final p in await (_db.select(
        _db.products,
      )..where((t) => t.syncStatus.equalsValue(SyncStatus.synced).not())).get())
        p.id,
    };

    await _db.batch((b) {
      for (final l in lignes) {
        if (protegees.contains(l['id'])) continue;
        final ligne = produitDepuisJson(l);
        b.insert(_db.products, ligne, onConflict: DoUpdate((_) => ligne));
      }
    });

    return lignes.length;
  }

  /// Un produit tel que le serveur le décrit, prêt à être écrit.
  ///
  /// ⚠️ **PUBLIC ET PARTAGÉ** : le tirage et le formulaire « Ajouter un Produit »
  /// inscrivent un produit à partir de la MÊME lecture. Deux lectures parallèles
  /// d'un même JSON finissent par diverger (une colonne ajoutée à l'une seulement).
  static ProductsCompanion produitDepuisJson(Map<String, dynamic> l) =>
      ProductsCompanion.insert(
        id: l['id'] as String,
        sku: (l['sku'] ?? '') as String,
        name: (l['name'] ?? '') as String,
        categoryId: Value(l['category_id'] as String?),
        speciesId: Value(l['species_id'] as String?),
        unit: (l['unit'] ?? 'u') as String,
        pricingMode: (l['pricing_mode'] ?? 'fixe') as String,
        priceMin: Value(_reel(l['price_min'])),
        priceMax: Value(_reel(l['price_max'])),
        tvaRate: Value(_reel(l['tva_rate']) ?? 0),
        stockQty: Value(_reel(l['stock_qty']) ?? 0),
        alertThreshold: Value(_reel(l['alert_threshold'])),
        description: Value(l['description'] as String?),
        syncStatus: const Value(SyncStatus.synced),
        isActive: Value(_bool(l['is_active'])),
        updatedAt: Value(_instantTechnique(l['updated_at'])),
      );

  /// Bandes du serveur — table MIXTE depuis le ticket BS1 (tirée ET saisie au poste).
  ///
  /// ⚠️⚠️ **STRICT, COMME [_absorberDepenses]** : identifiant absent ou servi deux fois, code absent, effectif illisible
  /// ou négatif, date de création ou `is_active` illisibles → [FormatException] : rien n'est écrit, la page est annulée,
  /// le curseur n'avance pas. Lisser — un effectif illisible devenu 0 — ferait compter une bande vide.
  ///
  /// ⚠️⚠️ **UNE BANDE LOCALE `pending` OU `conflict` N'EST JAMAIS ÉCRASÉE** (créée, modifiée ou archivée ici, pas
  /// encore acquittée, ou refusée et en attente de correction) : le tirage précède toujours l'envoi. Une bande acquittée
  /// (`synced`) prend la dernière version du serveur (cascade des fiches, modification ou archivage au web).
  ///
  /// Les clés facultatives absentes (serveur antérieur) laissent la valeur locale.
  Future<int> _absorberBandes(Object? brut) async {
    if (brut == null) return 0;

    const quoi = 'Bande';
    final lignes = _lignesStrictes(brut, quoi);
    if (lignes.isEmpty) return 0;

    final vus = <String>{};
    final recues = <LivestockLotsCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, quoi);
      final code = _texteStrict(l['code'], '$quoi $id : code');
      final espece = _texteStrict(l['species_id'], '$quoi $id : espèce');
      if (code == null || code.isEmpty || espece == null || espece.isEmpty) {
        throw FormatException('$quoi $id refusée : code ou espèce absent.');
      }
      final initial = _entierPositifStrict(l['initial_quantity'], '$quoi $id : effectif initial');
      final courant = _entierPositifStrict(l['current_quantity'], '$quoi $id : effectif actuel');
      final creee = l['created_date'];
      if (creee != null && _date(creee) == null) {
        throw FormatException('$quoi $id refusée : date de création illisible ($creee).');
      }
      final cout = _nombreStrict(l['acquisition_cost'], '$quoi $id : coût d\'acquisition');
      final actif = _actifStrict(l, '$quoi $id');

      recues.add(
        LivestockLotsCompanion.insert(
          id: id,
          code: code,
          speciesId: espece,
          speciesCode: Value(_texteStrict(l['species_code'], '$quoi $id : code espèce')),
          stage: Value(_texteStrict(l['stage'], '$quoi $id : stade')),
          initialQuantity: Value(initial ?? 0),
          currentQuantity: Value(courant ?? 0),
          createdDate: Value(_date(creee)),
          acquisitionCost: Value(cout),
          productId: Value(_texteStrict(l['product_id'], '$quoi $id : produit')),
          status: Value(_texteStrict(l['status'], '$quoi $id : statut')),
          isActive: Value(actif),
          updatedAt: Value(_instantTechnique(l['updated_at'])),
          syncStatus: const Value(SyncStatus.synced),
          // Ticket 15.46 — bande d'origine ; clé absente (serveur antérieur) = valeur locale gardée.
          lotSourceId: l.containsKey('lot_source_id')
              ? Value(_texteStrict(l['lot_source_id'], '$quoi $id : bande d\'origine'))
              : const Value.absent(),
        ),
      );
    }

    await _db.transaction(() async {
      final locales = {
        for (final b in await (_db.select(_db.livestockLots)..where((t) => t.id.isIn(vus))).get()) b.id: b.syncStatus,
      };
      for (final b in recues) {
        final statut = locales[b.id.value];
        if (statut != null && statut != SyncStatus.synced) continue;
        await _db.into(_db.livestockLots).insert(
          b,
          // Une bande acquittée garde sa correction d'effectif vide (rien à envoyer) : on ne l'écrit pas.
          onConflict: DoUpdate((_) => b.copyWith(effectifCorrige: const Value.absent())),
        );
      }
    });

    return recues.length;
  }

  /// Ticket 15.46 — transferts entre bandes, FUSIONNÉS par identifiant. Un transfert `pending` ou en
  /// `conflict` (créé ou annulé sur ce poste, pas encore acquitté) n'est jamais écrasé. Strict : un élément
  /// illisible ou une bande inconnue refuse le lot entier (le curseur n'avance pas).
  Future<int> _absorberTransferts(Object? brut) async {
    if (brut == null) return 0;
    final lignes = _lignes(brut);
    if (lignes.isEmpty) return 0;

    final transferts = <LivestockTransfersCompanion>[];
    for (final l in lignes) {
      final id = l['id'];
      final source = l['source_lot_id'];
      final cible = l['target_lot_id'];
      final date = _date(l['transfer_date']);
      final quantite = _entier(l['quantity']);
      if (id is! String ||
          source is! String ||
          cible is! String ||
          date == null ||
          quantite == null ||
          quantite < 1) {
        throw FormatException(
          'Transfert $id refusé : élément incomplet ou illisible.',
        );
      }
      final categorie = l['categorie'];
      if (categorie != null &&
          !const ['repro', 'sevre', 'jeune'].contains(categorie)) {
        throw FormatException(
          'Transfert $id refusé : catégorie inconnue ($categorie).',
        );
      }
      transferts.add(
        LivestockTransfersCompanion.insert(
          id: id,
          deviceId: 'serveur',
          sourceLotId: source,
          targetLotId: cible,
          transferDate: DateTime(date.year, date.month, date.day),
          quantity: quantite,
          categorie: Value(categorie as String?),
          constitution: Value(_bool(l['constitution'])),
          motif: Value(l['motif'] as String?),
          isActive: Value(_bool(l['is_active'])),
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: _instantTechnique(l['updated_at']) ?? _maintenant(),
        ),
      );
    }

    await _db.transaction(() async {
      final connues = {
        for (final b in await _db.select(_db.livestockLots).get()) b.id,
      };
      for (final t in transferts) {
        if (!connues.contains(t.sourceLotId.value) ||
            !connues.contains(t.targetLotId.value)) {
          throw FormatException(
            'Transfert ${t.id.value} refusé : bande inconnue du poste.',
          );
        }
        final locale = await (_db.select(
          _db.livestockTransfers,
        )..where((x) => x.id.equals(t.id.value))).getSingleOrNull();
        if (locale != null && locale.syncStatus != SyncStatus.synced) continue;
        await _db
            .into(_db.livestockTransfers)
            .insert(t, onConflict: DoUpdate((_) => t));
      }
    });

    return transferts.length;
  }

  /// Ticket H8b (D-H8) — ENTRÉES D'INFIRMERIE du serveur, FUSIONNÉES par identifiant.
  ///
  /// ⚠️⚠️ **STRICT**, comme [_absorberTransferts] : une entrée `pending` ou en `conflict` (créée, réintégrée
  /// ou déclarée décédée sur ce poste, pas encore acquittée) n'est JAMAIS écrasée — un upsert aveugle
  /// effacerait une réintégration saisie hors ligne. Un élément illisible (identifiant, bande, motif, date),
  /// un statut hors de l'enum du serveur (`en_cours`, `reintegre`, `deces`) ou une bande inconnue du poste
  /// refuse le lot entier ([FormatException], rien n'est écrit, le curseur n'avance pas).
  Future<int> _absorberInfirmerie(Object? brut) async {
    if (brut == null) return 0;
    final lignes = _lignes(brut);
    if (lignes.isEmpty) return 0;

    const statuts = ['en_cours', 'reintegre', 'deces'];
    final entrees = <InfirmaryRecordsCompanion>[];
    for (final l in lignes) {
      final id = l['id'];
      final lot = l['lot_id'];
      final motif = l['motif'];
      final date = _date(l['entry_date']);
      final statut = l['status'] ?? 'en_cours';
      final sujet = l['sujet_ref'];
      final isolement = l['isolation_level'];
      if (id is! String ||
          lot is! String ||
          motif is! String ||
          date == null ||
          (sujet != null && sujet is! String) ||
          (isolement != null && isolement is! String)) {
        throw FormatException(
          'Entrée d\'infirmerie $id refusée : élément incomplet ou illisible.',
        );
      }
      if (!statuts.contains(statut)) {
        throw FormatException(
          'Entrée d\'infirmerie $id refusée : statut inconnu ($statut).',
        );
      }
      entrees.add(
        InfirmaryRecordsCompanion.insert(
          id: id,
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: _instantTechnique(l['updated_at']) ?? _maintenant(),
          lotId: lot,
          sujetRef: Value(sujet as String?),
          motif: motif,
          isolationLevel: Value(isolement as String?),
          entryDate: DateTime(date.year, date.month, date.day),
          status: Value(statut as String),
        ),
      );
    }

    await _db.transaction(() async {
      final connues = {
        for (final b in await _db.select(_db.livestockLots).get()) b.id,
      };
      for (final e in entrees) {
        if (!connues.contains(e.lotId.value)) {
          throw FormatException(
            'Entrée d\'infirmerie ${e.id.value} refusée : bande inconnue du poste.',
          );
        }
        final locale = await (_db.select(
          _db.infirmaryRecords,
        )..where((x) => x.id.equals(e.id.value))).getSingleOrNull();
        if (locale != null && locale.syncStatus != SyncStatus.synced) continue;
        await _db
            .into(_db.infirmaryRecords)
            .insert(e, onConflict: DoUpdate((_) => e));
      }
    });

    return entrees.length;
  }

  /// Ticket H8b (D-H8) — INTERVENTIONS PLANIFIÉES du calendrier vétérinaire, FUSIONNÉES par identifiant.
  ///
  /// ⚠️⚠️ **STRICT**, même règle que [_absorberInfirmerie] : une intervention planifiée ou confirmée sur ce
  /// poste (`pending`, `conflict`) n'est jamais écrasée ; statut hors de l'enum du serveur (`planned`, `done`,
  /// `late`, `inprogress`), élément illisible ou bande inconnue → [FormatException], rien n'est écrit.
  Future<int> _absorberCalendrierVeterinaire(Object? brut) async {
    if (brut == null) return 0;
    final lignes = _lignes(brut);
    if (lignes.isEmpty) return 0;

    const statuts = ['planned', 'done', 'late', 'inprogress'];
    final evenements = <VeterinaryCalendarEventsCompanion>[];
    for (final l in lignes) {
      final id = l['id'];
      final lot = l['lot_id'];
      final tache = l['task_type'];
      final date = _date(l['scheduled_date']);
      final statut = l['status'] ?? 'planned';
      if (id is! String || lot is! String || tache is! String || date == null) {
        throw FormatException(
          'Intervention planifiée $id refusée : élément incomplet ou illisible.',
        );
      }
      if (!statuts.contains(statut)) {
        throw FormatException(
          'Intervention planifiée $id refusée : statut inconnu ($statut).',
        );
      }
      evenements.add(
        VeterinaryCalendarEventsCompanion.insert(
          id: id,
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: _instantTechnique(l['updated_at']) ?? _maintenant(),
          lotId: lot,
          taskType: tache,
          scheduledDate: DateTime(date.year, date.month, date.day),
          status: Value(statut as String),
        ),
      );
    }

    await _db.transaction(() async {
      final connues = {
        for (final b in await _db.select(_db.livestockLots).get()) b.id,
      };
      for (final e in evenements) {
        if (!connues.contains(e.lotId.value)) {
          throw FormatException(
            'Intervention planifiée ${e.id.value} refusée : bande inconnue du poste.',
          );
        }
        final locale = await (_db.select(
          _db.veterinaryCalendarEvents,
        )..where((x) => x.id.equals(e.id.value))).getSingleOrNull();
        if (locale != null && locale.syncStatus != SyncStatus.synced) continue;
        await _db
            .into(_db.veterinaryCalendarEvents)
            .insert(e, onConflict: DoUpdate((_) => e));
      }
    });

    return evenements.length;
  }

  /// Fiches journalières du cheptel — FUSIONNÉES par identifiant (ticket F0.94).
  ///
  /// ⚠️⚠️ AVANT CE TICKET, AUCUN ABSORBEUR : `/sync/pull` sert `livestock_daily_entries` (filtre
  /// `updated_at > since`) et le poste ignorait la clé. Les journées saisies sur le web ne
  /// descendaient jamais, ni les fiches que le serveur recalcule en cascade après une vente
  /// antérieure (15.31). Aucune erreur : la clé était simplement lue par personne.
  ///
  /// Règles :
  ///  - **fusion, jamais suppression** : le tirage est incrémental, une fiche absente de la
  ///    réponse n'a simplement pas changé ;
  ///  - une fiche locale `pending` ou `conflict` n'est **ni écrasée ni supprimée** (elle n'existe,
  ///    ou n'a changé, que sur ce poste : le serveur arbitrera à l'envoi) ;
  ///  - une fiche `synced` prend la version du serveur, `effectif_final` compris (le serveur le
  ///    recalcule toujours ; le poste ne le reprend pas à son compte) ;
  ///  - ⚠️ MÊME BANDE, MÊME JOUR, AUTRE IDENTIFIANT (le poste a créé SA fiche avant d'avoir reçu
  ///    celle du web) : la fiche locale est CONSERVÉE, la version du serveur n'est pas écrite (la
  ///    contrainte locale `UNIQUE (lot_id, entry_date)` l'interdit, et supprimer la locale perdrait
  ///    la saisie) ; un avertissement le dit. À l'envoi, le serveur refuse la fiche du poste
  ///    (contrainte unique de `pushDailyEntries`) : elle passe en `conflict` avec son motif ;
  ///  - l'effectif courant de la bande (`livestock_lots.current_quantity`) n'est JAMAIS touché :
  ///    c'est le serveur qui le sert, par `_absorberBandes`.
  ///
  /// ⚠️ **STRICT** : identifiant ou bande non UUID, bande inconnue du poste, jour illisible ou
  /// impossible (format attendu `Y-m-d`, celui du cast `date:Y-m-d` du modèle), nombre négatif,
  /// fractionnaire, NaN ou infini, colonne obligatoire absente, horodatage illisible, doublon
  /// d'identifiant ou de (bande, jour) dans la réponse → [FormatException] et AUCUNE fiche écrite
  /// (transaction annulée) ; le curseur n'avance pas. Un nombre absent n'est jamais lu comme 0 —
  /// sauf `don`, nullable au serveur et non nullable au poste (le serveur le compte lui-même
  /// `don ?? 0`).
  ///
  /// F0.95 (schéma v38) — PORTÉES : les dix colonnes de ventilation (`mort_*`, `don_*`,
  /// `passage_sevre_jeune`, `cat_depart_*`), les catégories dérivées `cat_eff_repro/sevre/jeune`
  /// et `cat_eff_4`, la ventilation par sexe `effectif_m/f/sevres/smeres`. Clé ABSENTE (serveur
  /// pas à jour) = valeur locale gardée ; NULL explicite = inconnu. Une fiche `synced` prend les
  /// `effectif_final` et `cat_eff_*` recalculés par la cascade du serveur.
  ///
  /// Ticket U10 (schéma v45) — REÇUES, jamais envoyées : `vente_sexe`, `vente_montant`, `treatment_product_id`,
  /// `treatment_dose`, `symptomes` (Tableau 2 et « CA Ventes du Lot » du Rapport Élevage). Même règle de clé absente.
  ///
  /// ⚠️ COLONNE DU SERVEUR TOUJOURS NON PORTÉE : `feed_product_id`. Le poste n'envoie aucune de ces six colonnes :
  /// `fill()` du serveur ne réécrit que les clés reçues, elles y restent intactes.
  Future<int> _absorberFichesJournalieres(Object? brut) async {
    if (brut == null) return 0;
    if (brut is! List) {
      throw const FormatException(
        'Fiches refusées : « livestock_daily_entries » n\'est pas une liste.',
      );
    }

    final formeUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    final formeJour = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
    final formeEntier = RegExp(r'^-?\d+$');

    int? entier(
      Map<String, dynamic> l,
      String cle,
      String id, {
      required bool requis,
    }) {
      final v = l[cle];
      if (v == null) {
        if (requis) {
          throw FormatException('Fiche $id refusée : « $cle » absent.');
        }
        return null;
      }
      int? n;
      if (v is int) {
        n = v;
      } else if (v is double && v.isFinite && v == v.truncateToDouble()) {
        n = v.toInt();
      } else if (v is String && formeEntier.hasMatch(v)) {
        n = int.tryParse(v);
      }
      if (n == null) {
        throw FormatException('Fiche $id refusée : « $cle » illisible ($v).');
      }
      if (n < 0) {
        throw FormatException('Fiche $id refusée : « $cle » négatif ($v).');
      }
      return n;
    }

    /// ⚠️⚠️ F0.95 — CLÉ ABSENTE ≠ NULL EXPLICITE. Absente : serveur antérieur à la colonne, la
    /// valeur locale est GARDÉE (`Value.absent`). Présente et nulle : le serveur dit « inconnu »,
    /// la valeur locale est remplacée par null. Présente : entier ≥ 0 strict (même lecture que
    /// les autres compteurs ; négatif, fractionnaire, NaN, infini ou illisible = lot refusé).
    Value<int?> optionnel(Map<String, dynamic> l, String cle, String id) =>
        l.containsKey(cle)
        ? Value(entier(l, cle, id, requis: false))
        : const Value.absent();

    /// Ticket 15.46 — colonne dérivée NOT NULL : absente = valeur locale gardée, nulle = 0.
    Value<int> derive(Map<String, dynamic> l, String cle, String id) =>
        l.containsKey(cle)
        ? Value(entier(l, cle, id, requis: false) ?? 0)
        : const Value.absent();

    double? reel(Map<String, dynamic> l, String cle, String id) {
      final v = l[cle];
      if (v == null) return null;
      final x = v is num
          ? v.toDouble()
          : v is String
          ? double.tryParse(v)
          : null;
      if (x == null || !x.isFinite) {
        throw FormatException('Fiche $id refusée : « $cle » illisible ($v).');
      }
      if (x < 0) {
        throw FormatException('Fiche $id refusée : « $cle » négatif ($v).');
      }
      return x;
    }

    /// Ticket U10 — texte reçu : clé absente = valeur locale gardée ; nul = inconnu ; sinon une CHAÎNE (et, s'il
    /// y a lieu, une des [valeurs] permises ou de la [forme] attendue), sans quoi le lot est refusé.
    Value<String?> texteOptionnel(
      Map<String, dynamic> l,
      String cle,
      String id, {
      Set<String>? valeurs,
      RegExp? forme,
    }) {
      if (!l.containsKey(cle)) return const Value.absent();
      final v = l[cle];
      if (v == null) return const Value(null);
      if (v is! String ||
          (valeurs != null && !valeurs.contains(v)) ||
          (forme != null && !forme.hasMatch(v))) {
        throw FormatException('Fiche $id refusée : « $cle » illisible ($v).');
      }
      return Value(v);
    }

    // ── Validation complète AVANT toute écriture en base ────────────────────
    final ids = <String>{};
    final jours = <String>{};
    final fiches = <LivestockDailyEntriesCompanion>[];
    for (final e in brut) {
      if (e is! Map) {
        throw const FormatException(
          'Fiches refusées : un élément n\'est pas un objet.',
        );
      }
      final l = e.map((c, v) => MapEntry(c.toString(), v));

      final id = l['id'];
      if (id is! String || !formeUuid.hasMatch(id)) {
        throw FormatException('Fiche refusée : identifiant invalide ($id).');
      }
      if (!ids.add(id)) {
        throw FormatException('Fiche $id refusée : servie deux fois.');
      }
      final lot = l['lot_id'];
      if (lot is! String || !formeUuid.hasMatch(lot)) {
        throw FormatException('Fiche $id refusée : bande invalide ($lot).');
      }

      final jourBrut = l['entry_date'];
      final m = jourBrut is String ? formeJour.firstMatch(jourBrut) : null;
      DateTime? jour;
      if (m != null) {
        final (a, mo, j) = (
          int.parse(m[1]!),
          int.parse(m[2]!),
          int.parse(m[3]!),
        );
        final d = DateTime(a, mo, j);
        if (d.year == a && d.month == mo && d.day == j) jour = d;
      }
      if (jour == null) {
        throw FormatException(
          'Fiche $id refusée : jour illisible ($jourBrut).',
        );
      }
      if (!jours.add('$lot|${_jour(jour)}')) {
        throw FormatException(
          'Fiche $id refusée : deux fiches servies pour la même bande le ${_jour(jour)}.',
        );
      }

      final horodatageBrut = l['updated_at'];
      DateTime? horodatage;
      if (horodatageBrut != null) {
        horodatage = horodatageBrut is String ? _instantTechnique(horodatageBrut) : null;
        if (horodatage == null) {
          throw FormatException(
            'Fiche $id refusée : horodatage illisible ($horodatageBrut).',
          );
        }
      }

      fiches.add(
        LivestockDailyEntriesCompanion(
          id: Value(id),
          lotId: Value(lot),
          entryDate: Value(jour),
          updatedAt: Value.absentIfNull(horodatage),
          achat: Value(entier(l, 'achat', id, requis: true)!),
          ne: Value(entier(l, 'ne', id, requis: true)!),
          mort: Value(entier(l, 'mort', id, requis: true)!),
          vente: Value(entier(l, 'vente', id, requis: true)!),
          don: Value(entier(l, 'don', id, requis: false) ?? 0),
          effectifFinal: Value(entier(l, 'effectif_final', id, requis: true)!),
          ponteTotal: Value(entier(l, 'ponte_total', id, requis: false)),
          ponteCasses: Value(entier(l, 'ponte_casses', id, requis: false)),
          feedQtyKg: Value(reel(l, 'feed_qty_kg', id)),
          weightSampleAvgG: Value(reel(l, 'weight_sample_avg_g', id)),
          // F0.95 — effectif par catégorie et ventilation par sexe (voir `optionnel`).
          mortRepro: optionnel(l, 'mort_repro', id),
          mortSevre: optionnel(l, 'mort_sevre', id),
          mortJeune: optionnel(l, 'mort_jeune', id),
          donRepro: optionnel(l, 'don_repro', id),
          donSevre: optionnel(l, 'don_sevre', id),
          donJeune: optionnel(l, 'don_jeune', id),
          passageSevreJeune: optionnel(l, 'passage_sevre_jeune', id),
          catDepartRepro: optionnel(l, 'cat_depart_repro', id),
          catDepartSevre: optionnel(l, 'cat_depart_sevre', id),
          catDepartJeune: optionnel(l, 'cat_depart_jeune', id),
          catEffRepro: optionnel(l, 'cat_eff_repro', id),
          catEffSevre: optionnel(l, 'cat_eff_sevre', id),
          catEffJeune: optionnel(l, 'cat_eff_jeune', id),
          catEff4: optionnel(l, 'cat_eff_4', id),
          effectifM: optionnel(l, 'effectif_m', id),
          effectifF: optionnel(l, 'effectif_f', id),
          effectifSevres: optionnel(l, 'effectif_sevres', id),
          effectifSmeres: optionnel(l, 'effectif_smeres', id),
          // Ticket U10 — colonnes du Rapport Élevage, reçues seulement (clé absente = valeur locale gardée).
          venteSexe: texteOptionnel(
            l,
            'vente_sexe',
            id,
            valeurs: const {'M', 'F', 'Mixte'},
          ),
          venteMontant: l.containsKey('vente_montant')
              ? Value(reel(l, 'vente_montant', id))
              : const Value.absent(),
          treatmentProductId: texteOptionnel(
            l,
            'treatment_product_id',
            id,
            forme: formeUuid,
          ),
          treatmentDose: texteOptionnel(l, 'treatment_dose', id),
          symptomes: texteOptionnel(l, 'symptomes', id),
          // Ticket 15.46 — transferts entre bandes, dérivés au serveur (NOT NULL à 0).
          transfertEntree: derive(l, 'transfert_entree', id),
          transfertSortie: derive(l, 'transfert_sortie', id),
          transfertEntreeRepro: derive(l, 'transfert_entree_repro', id),
          transfertEntreeSevre: derive(l, 'transfert_entree_sevre', id),
          transfertEntreeJeune: derive(l, 'transfert_entree_jeune', id),
          transfertSortieRepro: derive(l, 'transfert_sortie_repro', id),
          transfertSortieSevre: derive(l, 'transfert_sortie_sevre', id),
          transfertSortieJeune: derive(l, 'transfert_sortie_jeune', id),
        ),
      );
      // F0.95 — un serveur antérieur à 15.39 ne sert pas la ventilation : la resynchronisation
      // unique `fiches_resync_f095` ne doit alors PAS être marquée faite (voir `_tirer`).
      if (!colonnesVentilation.every(l.containsKey)) {
        _fichesSansVentilation = true;
      }
      if (!colonnesRapportElevage.every(l.containsKey)) {
        _fichesSansColonnesRapport = true;
      }
    }

    if (fiches.isEmpty) return 0;

    // ── Application, en une transaction ─────────────────────────────────────
    final avertissements = <String>[];
    await _db.transaction(() async {
      final codes = <String, String>{};
      final bandes = {for (final f in fiches) f.lotId.value}.toList();
      for (final morceau in _morceaux(bandes)) {
        for (final b in await (_db.select(
          _db.livestockLots,
        )..where((t) => t.id.isIn(morceau))).get()) {
          codes[b.id] = b.code;
        }
      }
      for (final f in fiches) {
        if (!codes.containsKey(f.lotId.value)) {
          throw FormatException(
            'Fiche ${f.id.value} refusée : bande inconnue du poste (${f.lotId.value}).',
          );
        }
      }

      for (final f in fiches) {
        final locale = await (_db.select(
          _db.livestockDailyEntries,
        )..where((t) => t.id.equals(f.id.value))).getSingleOrNull();

        // ⚠️⚠️ `pending` / `conflict` : intouchable (n'existe, ou n'a changé, que sur ce poste).
        if (locale != null && locale.syncStatus != SyncStatus.synced) continue;

        final occupante =
            await (_db.select(_db.livestockDailyEntries)..where(
                  (t) => Expression.and([
                    t.lotId.equals(f.lotId.value),
                    t.entryDate.equals(f.entryDate.value),
                  ]),
                ))
                .getSingleOrNull();
        if (occupante != null && occupante.id != f.id.value) {
          avertissements.add(
            _avertissementFicheEnDouble(
              occupante,
              codes[f.lotId.value] ?? f.lotId.value,
            ),
          );
          continue;
        }

        final ligne = f.copyWith(
          deviceId: Value(locale?.deviceId ?? 'serveur'),
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: Value(
            f.updatedAt.present
                ? f.updatedAt.value
                : locale?.updatedAt ?? _maintenant(),
          ),
        );
        await _db
            .into(_db.livestockDailyEntries)
            .insert(ligne, onConflict: DoUpdate((_) => ligne));
      }
    });

    _avertissements.addAll(avertissements);
    return fiches.length;
  }

  /// Avertissement d'une fiche servie que le poste ne peut pas écrire : (bande, jour) est déjà
  /// occupé localement par une AUTRE fiche, qui est conservée.
  static String _avertissementFicheEnDouble(
    LivestockDailyEntry locale,
    String bande,
  ) {
    final d = locale.entryDate;
    final jour =
        '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
    final suite = switch (locale.syncStatus) {
      SyncStatus.pending =>
        'La saisie de ce poste est conservée ; à l\'envoi, le serveur la refusera '
            '(une seule fiche par bande et par jour) : comparez les deux avant de trancher.',
      SyncStatus.conflict =>
        'La fiche refusée de ce poste est conservée : comparez les deux avant de trancher.',
      SyncStatus.synced =>
        'La copie de ce poste (une autre fiche, déjà synchronisée) est conservée, jamais '
            'supprimée par un tirage : écart à examiner.',
    };
    return 'Fiche du $jour (bande $bande) : le serveur en détient une autre, saisie ailleurs. '
        '$suite';
  }

  // ── Ticket H9b (D-H9) — PARAMÈTRES ÉLEVAGE : barèmes reçus ET envoyés ─────────────────────────────────
  //
  // ⚠️⚠️ **STRICTS, COMME [_absorberInfirmerie]** : une ligne incohérente (identifiant absent ou de mauvaise
  // longueur, champ obligatoire manquant, nombre illisible, ligne servie deux fois) refuse le LOT entier
  // ([FormatException], rien n'est écrit, le curseur n'avance pas). Lisser — un grammage illisible devenu 0 —
  // ferait calculer une provende nulle sans que rien ne le signale.
  //
  // ⚠️⚠️ **UNE SAISIE LOCALE N'EST JAMAIS ÉCRASÉE** : une ligne `pending` (créée, modifiée ou archivée sur ce
  // poste, pas encore acquittée) ou `conflict` (refusée, en attente de correction) garde sa valeur locale ;
  // le tirage précède toujours l'envoi. Sinon : dernière valeur du serveur, `synced`.
  //
  // ⚠️ **LE SERVEUR SERT L'ENSEMBLE ACTIF COMPLET** (sans filtre `since`, `where is_active`) : une ligne
  // `synced` qu'il ne sert plus a été ARCHIVÉE ailleurs (web, autre poste) — elle est archivée ici aussi
  // (`is_active = false`), jamais effacée, comme au serveur. Une réponse SANS la clé (serveur ancien) laisse
  // tout intact.

  /// Lignes d'un barème : une LISTE de MAPS, sinon le lot est refusé.
  static List<Map<String, dynamic>> _lignesStrictes(
    Object? brut,
    String bareme,
  ) {
    if (brut is! List) {
      throw FormatException('$bareme refusé : la clé n\'est pas une liste.');
    }
    return [
      for (final l in brut)
        if (l is Map)
          l.map((c, v) => MapEntry(c.toString(), v))
        else
          throw FormatException('$bareme refusé : élément illisible ($l).'),
    ];
  }

  /// Nombre strict : absent → `null`, illisible → [FormatException].
  static double? _nombreStrict(Object? v, String quoi) {
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (n == null) throw FormatException('$quoi illisible ($v).');
    return n;
  }

  /// Texte strict : absent → `null`, autre chose qu'un texte → [FormatException].
  static String? _texteStrict(Object? v, String quoi) {
    if (v == null) return null;
    if (v is! String) throw FormatException('$quoi illisible ($v).');
    return v;
  }

  /// `is_active` servi (le tirage ne sert que des lignes actives) ; absent = actif.
  static bool _actifStrict(Map<String, dynamic> l, String quoi) {
    if (!l.containsKey('is_active')) return true;
    final v = l['is_active'];
    if (v == true || v == 1 || v == '1') return true;
    if (v == false || v == 0 || v == '0') return false;
    throw FormatException('$quoi : « is_active » illisible ($v).');
  }

  /// Identifiant strict d'une ligne de barème (UUID de 36 caractères, jamais servi deux fois).
  static String _identifiantStrict(
    Map<String, dynamic> l,
    Set<String> vus,
    String bareme,
  ) {
    final id = l['id'];
    if (id is! String || id.length != 36) {
      throw FormatException('$bareme refusé : identifiant invalide ($id).');
    }
    if (!vus.add(id)) {
      throw FormatException('$bareme $id refusé : servi deux fois.');
    }
    return id;
  }

  /// Fusion commune aux trois barèmes : les lignes servies remplacent les `synced`, les `pending`/`conflict`
  /// sont protégées, les `synced` absentes de l'ensemble actif servi sont archivées.
  Future<void> _fusionnerBareme<T extends Table, D>({
    required TableInfo<T, D> table,
    required List<Insertable<D>> recues,
    required List<String> idsServis,
    required String Function(D) idDe,
    required SyncStatus Function(D) statutDe,
    required Expression<bool> Function(T) synceeHorsServis,
    required Insertable<D> archivage,
  }) async {
    await _db.transaction(() async {
      final protegees = {
        for (final l in await _db.select(table).get())
          if (statutDe(l) != SyncStatus.synced) idDe(l),
      };
      for (var i = 0; i < recues.length; i++) {
        if (protegees.contains(idsServis[i])) continue;
        await _db
            .into(table)
            .insert(recues[i], onConflict: DoUpdate((_) => recues[i]));
      }
      await (_db.update(
        table,
      )..where((t) => synceeHorsServis(t))).write(archivage);
    });
  }

  /// Catalogue des types de provende — ensemble actif complet, FUSIONNÉ (ticket H9b).
  ///
  /// ⚠️ Avant H9b la table était vidée puis réécrite : un type créé au poste et pas encore acquitté aurait
  /// disparu au tirage suivant. Le libellé de l'espèce voyage avec le type (le poste n'a pas de table des
  /// espèces désactivées).
  Future<int> _absorberProvendes(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignesStrictes(brut, 'Type de provende');
    final vus = <String>{};
    final recues = <FeedTypesCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, 'Type de provende');
      final nom = l['name'];
      if (nom is! String || nom.isEmpty) {
        throw FormatException('Type de provende $id refusé : nom absent.');
      }
      recues.add(
        FeedTypesCompanion.insert(
          id: id,
          name: nom,
          speciesId: Value(_texteStrict(l['species_id'], 'Type $id : espèce')),
          speciesCode: Value(
            _texteStrict(l['species_code'], 'Type $id : code espèce'),
          ),
          speciesLabel: Value(
            _texteStrict(l['species_label'], 'Type $id : libellé espèce'),
          ),
          standardBagWeightKg: Value(
            _nombreStrict(l['standard_bag_weight_kg'], 'Type $id : poids du sac'),
          ),
          pricePerKg: Value(
            _nombreStrict(l['price_per_kg'], 'Type $id : prix au kilo'),
          ),
          isActive: Value(_actifStrict(l, 'Type $id')),
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: const Value(null),
        ),
      );
    }

    final servis = [for (final r in recues) r.id.value];
    await _fusionnerBareme(
      table: _db.feedTypes,
      recues: recues,
      idsServis: servis,
      idDe: (FeedType t) => t.id,
      statutDe: (FeedType t) => t.syncStatus,
      synceeHorsServis: ($FeedTypesTable t) => Expression.and([
        t.syncStatus.equalsValue(SyncStatus.synced),
        t.id.isNotIn(servis),
      ]),
      archivage: const FeedTypesCompanion(isActive: Value(false)),
    );

    return recues.length;
  }

  /// Préfixes de numérotation — un OBJET, pas une collection.
  ///
  /// ⚠️ **LE SERVEUR SERT UNE TABLE SINGLETON.** La charge est une map de
  /// préfixes, pas une liste de lignes : la passer à `_lignes()` comme les
  /// autres tables ne donnerait rien. Elle est écrite sous une clé fixe pour
  /// qu'un second tirage remplace la ligne au lieu d'en empiler une autre.
  ///
  /// Ticket H9b — STRICTE (un format qui n'est pas un texte refuse la ligne) et PROTÉGÉE (des formats
  /// enregistrés au poste et pas encore acquittés ne sont pas écrasés).
  Future<int> _absorberNumerotation(Object? brut) async {
    if (brut == null) return 0;
    if (brut is! Map) {
      throw FormatException('Numérotation refusée : objet attendu ($brut).');
    }

    final l = brut.map((c, v) => MapEntry(c.toString(), v));
    String? format(String cle) => _texteStrict(l[cle], 'Numérotation : $cle');

    final ligne = ElevageNumberingSettingsCompanion.insert(
      id: const Value('unique'),
      bandeFormat: Value(format('bande_format')),
      lapinePrefix: Value(format('lapine_prefix')),
      malePrefix: Value(format('male_prefix')),
      truiePrefix: Value(format('truie_prefix')),
      verratPrefix: Value(format('verrat_prefix')),
      porteePrefix: Value(format('portee_prefix')),
      volaillePrefix: Value(format('volaille_prefix')),
      parcPrefix: Value(format('parc_prefix')),
      escargotPrefix: Value(format('escargot_prefix')),
      syncStatus: const Value(SyncStatus.synced),
      updatedAt: const Value(null),
    );

    await _db.transaction(() async {
      final locale = await (_db.select(
        _db.elevageNumberingSettings,
      )..where((t) => t.id.equals('unique'))).getSingleOrNull();
      if (locale != null && locale.syncStatus != SyncStatus.synced) return;
      await _db
          .into(_db.elevageNumberingSettings)
          .insert(ligne, onConflict: DoUpdate((_) => ligne));
    });

    return 1;
  }

  /// Rations normatives — ensemble actif complet, FUSIONNÉ (ticket H9b).
  ///
  /// ⚠️ Une réponse SANS la clé laisse les rations locales intactes plutôt que
  /// de les effacer : un serveur plus ancien qui ne les sert pas encore ne doit
  /// pas vider le référentiel d'un poste déjà à jour.
  ///
  /// 🔴→✅ Avant H9b, une ration ARCHIVÉE sur le web (ticket 14.55 : elle ne descend plus) restait active sur
  /// le poste pour toujours — l'absorbeur ne faisait qu'ajouter. Elle s'archive désormais ici aussi.
  Future<int> _absorberRations(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignesStrictes(brut, 'Ration');
    final vus = <String>{};
    final recues = <FeedRationStandardsCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, 'Ration');
      final espece = l['species_code'];
      final stade = l['stage_label'];
      final grammes = _nombreStrict(l['ration_g_per_day'], 'Ration $id : grammage');
      if (espece is! String || espece.isEmpty || stade is! String || grammes == null) {
        throw FormatException('Ration $id refusée : élément incomplet ou illisible.');
      }
      recues.add(
        FeedRationStandardsCompanion.insert(
          id: id,
          speciesCode: espece,
          stageLabel: stade,
          rationGPerDay: grammes,
          isActive: Value(_actifStrict(l, 'Ration $id')),
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: const Value(null),
        ),
      );
    }

    final servis = [for (final r in recues) r.id.value];
    await _fusionnerBareme(
      table: _db.feedRationStandards,
      recues: recues,
      idsServis: servis,
      idDe: (FeedRationStandard r) => r.id,
      statutDe: (FeedRationStandard r) => r.syncStatus,
      synceeHorsServis: ($FeedRationStandardsTable t) => Expression.and([
        t.syncStatus.equalsValue(SyncStatus.synced),
        t.id.isNotIn(servis),
      ]),
      archivage: const FeedRationStandardsCompanion(isActive: Value(false)),
    );

    return recues.length;
  }

  /// Ticket U2 (décision client D-U2 du 19/10/2026) — OBJECTIFS DE GMQ (`growth_standards`) : référentiel en
  /// LECTURE SEULE, servi complet à chaque tirage, dont l'ENSEMBLE est remplacé (le poste ne l'écrit jamais : rien
  /// de local à protéger).
  ///
  /// ⚠️⚠️ **STRICT**, comme les barèmes de H9b : identifiant invalide ou servi deux fois, espèce ou stade absents,
  /// objectif absent, illisible, fractionnaire ou négatif (`unsignedInteger` au serveur) → [FormatException] : RIEN
  /// n'est écrit (le barème précédent reste), le curseur n'avance pas. Lisser — un objectif illisible devenu 0 —
  /// afficherait « Objectif : 0-20 g/j » sur le Dashboard Élevage sans que rien ne le signale.
  ///
  /// Une réponse SANS la clé (serveur antérieur à U2) ne touche à rien ; une liste VIDE est une réponse : aucun
  /// barème, les cartes disent « Objectif : — ».
  Future<int> _absorberObjectifsCroissance(Object? brut) async {
    if (brut == null) return 0;

    const quoi = 'Objectif de croissance';
    final lignes = _lignesStrictes(brut, quoi);
    final vus = <String>{};
    final recus = <GrowthStandardsCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, quoi);
      final espece = _texteStrict(l['species_code'], '$quoi $id : espèce');
      final stade = _texteStrict(l['stage_label'], '$quoi $id : stade');
      final minimum = _entierPositifStrict(
        l['gmq_min_g_per_day'],
        '$quoi $id : minimum',
      );
      final maximum = _entierPositifStrict(
        l['gmq_max_g_per_day'],
        '$quoi $id : maximum',
      );
      if (espece == null ||
          espece.isEmpty ||
          stade == null ||
          stade.isEmpty ||
          minimum == null ||
          maximum == null) {
        throw FormatException(
          '$quoi $id refusé : élément incomplet ou illisible.',
        );
      }
      recus.add(
        GrowthStandardsCompanion.insert(
          id: id,
          speciesCode: espece,
          stageLabel: stade,
          gmqMinGPerDay: minimum,
          gmqMaxGPerDay: maximum,
        ),
      );
    }

    await _db.transaction(() async {
      await _db.delete(_db.growthStandards).go();
      for (final r in recus) {
        await _db.into(_db.growthStandards).insert(r);
      }
    });

    return recus.length;
  }

  /// Entier positif strict (Ticket U2) : absent → `null` ; illisible, fractionnaire ou négatif →
  /// [FormatException].
  static int? _entierPositifStrict(Object? v, String quoi) {
    if (v == null) return null;
    final n = v is num ? v : num.tryParse(v.toString());
    if (n == null || n != n.truncate() || n < 0) {
      throw FormatException('$quoi illisible ($v).');
    }
    return n.toInt();
  }

  /// Calendrier prophylactique — ensemble actif complet, FUSIONNÉ (ticket H9b).
  ///
  /// ⚠️ Les bornes de cycle ABSENTES restent NULLES, JAMAIS ZÉRO : le serveur les laisse vides pour les
  /// entrées calendaires (« Le 1er du mois ») dont la base de calcul n'est pas le jour de cycle. Les remplacer
  /// par 0 les rendrait dues au premier jour de chaque bande. `created_at` sert au tri du web (H9).
  Future<int> _absorberProphylaxie(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignesStrictes(brut, 'Échéance de prophylaxie');
    final vus = <String>{};
    final recues = <ProphylaxisScheduleStandardsCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, 'Échéance de prophylaxie');
      final espece = l['species_code'];
      final periode = l['period_label'];
      final traitement = l['treatment'];
      if (espece is! String ||
          espece.isEmpty ||
          periode is! String ||
          traitement is! String) {
        throw FormatException(
          'Échéance de prophylaxie $id refusée : élément incomplet ou illisible.',
        );
      }
      int? entier(String cle) {
        final n = _nombreStrict(l[cle], 'Échéance $id : $cle');
        if (n != null && n != n.roundToDouble()) {
          throw FormatException('Échéance $id : $cle non entier ($n).');
        }
        return n?.round();
      }

      final creation = l['created_at'];
      final creee = creation == null ? null : _instantTechnique(creation);
      if (creation != null && creee == null) {
        throw FormatException('Échéance $id : created_at illisible ($creation).');
      }

      recues.add(
        ProphylaxisScheduleStandardsCompanion.insert(
          id: id,
          speciesCode: espece,
          periodLabel: periode,
          cycleDayStart: Value(entier('cycle_day_start')),
          cycleDayEnd: Value(entier('cycle_day_end')),
          treatment: traitement,
          productRecommended: Value(
            _texteStrict(l['product_recommended'], 'Échéance $id : produit'),
          ),
          dosage: Value(_texteStrict(l['dosage'], 'Échéance $id : posologie')),
          withdrawalDays: Value(entier('withdrawal_days') ?? 0),
          createdAt: Value(creee),
          isActive: Value(_actifStrict(l, 'Échéance $id')),
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: const Value(null),
        ),
      );
    }

    final servis = [for (final r in recues) r.id.value];
    await _fusionnerBareme(
      table: _db.prophylaxisScheduleStandards,
      recues: recues,
      idsServis: servis,
      idDe: (ProphylaxisScheduleStandard p) => p.id,
      statutDe: (ProphylaxisScheduleStandard p) => p.syncStatus,
      synceeHorsServis: ($ProphylaxisScheduleStandardsTable t) => Expression.and([
        t.syncStatus.equalsValue(SyncStatus.synced),
        t.id.isNotIn(servis),
      ]),
      archivage: const ProphylaxisScheduleStandardsCompanion(
        isActive: Value(false),
      ),
    );

    return recues.length;
  }

  /// Périodes de rémanence vétérinaire encore actives.
  ///
  /// ⚠️ LA TABLE LOCALE EST REMPLACÉE, PAS COMPLÉTÉE. Le serveur n'envoie que
  /// les périodes ENCORE actives : conserver les anciennes bloquerait
  /// indéfiniment des bandes dont le délai d'attente est passé, et l'éleveur
  /// finirait par contourner l'alerte — y compris quand elle est vraie.
  ///
  /// ⚠️ Une réponse SANS la clé laisse l'existant intact plutôt que de tout
  /// effacer : un serveur plus ancien ne doit pas lever un blocage sanitaire.
  Future<int> _absorberRemanences(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.veterinaryWithdrawalPeriods).go();

      for (final l in lignes) {
        await _db
            .into(_db.veterinaryWithdrawalPeriods)
            .insert(
              VeterinaryWithdrawalPeriodsCompanion.insert(
                id: l['id'] as String,
                lotId: (l['lot_id'] ?? '') as String,
                productUsed: Value(l['product_used'] as String?),
                endDate: _date(l['end_date']) ?? HeureBenin.aujourdhui(),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Cycle de reproduction par femelle nommée — reçu, jamais envoyé.
  ///
  /// ⚠️ **FUSION, PAS REMPLACEMENT.** Contrairement aux référentiels, le
  /// serveur ne sert PAS toute la table à chaque tirage : il descend les
  /// cycles `en_cours` plus l'historique modifié depuis le dernier tirage.
  /// Vider la table avant d'insérer effacerait donc tout l'historique clos dès
  /// le premier tirage incrémental — l'écran perdrait ses mises bas passées
  /// sans que rien ne le signale.
  Future<int> _absorberReproduction(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    // ⚠️⚠️ LES DECLARATIONS EN ATTENTE SONT PRESERVEES. Une saillie declaree
    // au poste et pas encore acquittee n'existe pas encore cote serveur : la
    // remplacer par le tirage l'effacerait purement et simplement, et
    // l'animalier n'aurait aucun moyen de le savoir.
    final enAttente = await (_db.select(
      _db.livestockReproductionEvents,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();
    final protegees = enAttente.map((e) => e.id).toSet();

    await _db.batch((b) {
      for (final l in lignes) {
        if (protegees.contains(l['id'])) continue;

        b.insert(
          _db.livestockReproductionEvents,
          LivestockReproductionEventsCompanion.insert(
            id: l['id'] as String,
            // ⚠️ UNE LIGNE TIREE N'A ETE ECRITE PAR AUCUN POSTE, et ne doit
            // jamais repartir a l'envoi — meme convention que le registre
            // veterinaire.
            deviceId: (l['device_id'] ?? 'serveur') as String,
            syncStatus: const Value(SyncStatus.synced),
            lotId: (l['lot_id'] ?? '') as String,
            motherRef: (l['mother_ref'] ?? '') as String,
            sireRef: Value(l['sire_ref'] as String?),
            saillieDate: Value(_date(l['saillie_date'])),
            palpationDate: Value(_date(l['palpation_date'])),
            miseBasDateExpected: Value(_date(l['mise_bas_date_expected'])),
            miseBasDateActual: Value(_date(l['mise_bas_date_actual'])),
            sevrageDateExpected: Value(_date(l['sevrage_date_expected'])),
            nesVivants: Value(_entier(l['nes_vivants'])),
            nesMorts: Value(_entier(l['nes_morts'])),
            status: Value((l['status'] ?? 'en_cours') as String),
            updatedAt: _instantTechnique(l['updated_at']) ?? DateTime.now(),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });

    return lignes.length;
  }

  /// Fichier clients — fusionné par identifiant à chaque tirage.
  ///
  /// ⚠️⚠️ **FUSION, PAS REMPLACEMENT** (ticket F0.72). Le serveur ne sert que les clients
  /// MODIFIÉS depuis `since` : l'ancien « tout effacer puis réinsérer » ne laissait, dès le
  /// deuxième tirage, que le delta — la caisse perdait ses clients sans qu'aucune erreur ne
  /// le dise. Un client archivé descend avec `is_active = false` (le serveur ne filtre pas) :
  /// la fusion le désactive, les écrans ne proposent que les actifs.
  ///
  /// ⚠️ Une fiche `pending` ou `conflict` n'existe (ou n'a changé) que sur ce poste : le
  /// tirage ne l'écrase jamais.
  Future<int> _absorberClients(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      final protegees = {
        for (final c
            in await (_db.select(_db.customers)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          c.id,
      };

      for (final l in lignes) {
        if (protegees.contains(l['id'])) continue;

        await _db
            .into(_db.customers)
            .insertOnConflictUpdate(
              CustomersCompanion.insert(
                id: l['id'] as String,
                name: (l['name'] ?? '') as String,
                phone: Value(l['phone'] as String?),
                email: Value(l['email'] as String?),
                city: Value(l['city'] as String?),
                creditLimit: Value(_reel(l['credit_limit']) ?? 0),
                isActive: Value(_bool(l['is_active'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Créances encore dues — FUSIONNÉES par identifiant (ticket F0.73).
  ///
  /// ⚠️⚠️ **« TOUT EFFACER PUIS RÉINSÉRER » EST RETIRÉ.** Une imputation d'acompte se
  /// désigne par l'identifiant de sa créance : la table doit rester stable d'un tirage à
  /// l'autre, et une saisie du poste ne doit jamais perdre sa cible entre deux lignes
  /// d'une même transaction. La fusion met la ligne à jour (le serveur est maître de
  /// `amount_paid`), puis supprime ce que le serveur n'a PLUS servi.
  ///
  /// ⚠️ **LE SERVEUR SERT CE QUI RESTE DÛ SANS FILTRE `since`, plus ce qui a changé depuis
  /// `since`.** Une créance soldée entre deux tirages arrive donc UNE fois (soldée, parce
  /// qu'elle a changé), puis cesse d'être servie : elle est alors supprimée. La laisser
  /// à l'encours du poste ferait relancer un débiteur pour une facture déjà payée.
  Future<int> _absorberCreances(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      for (final l in lignes) {
        await _db
            .into(_db.receivables)
            .insertOnConflictUpdate(
              ReceivablesCompanion.insert(
                id: l['id'] as String,
                customerId: (l['customer_id'] ?? '') as String,
                saleId: Value(l['sale_id'] as String?),
                amount: _reel(l['amount']) ?? 0,
                amountPaid: Value(_reel(l['amount_paid']) ?? 0),
                dueDate: Value(_date(l['due_date'])),
                status: Value((l['status'] ?? 'en_cours') as String),
              ),
            );
      }

      final servies = [for (final l in lignes) l['id'] as String];
      await (_db.delete(
        _db.receivables,
      )..where((t) => t.id.isIn(servies).not())).go();
    });

    return lignes.length;
  }

  /// Avances versées par les clients — FUSIONNÉES par identifiant (ticket F0.73).
  ///
  /// ⚠️⚠️ **UNE AVANCE `pending` OU `conflict` N'EST NI ÉCRASÉE NI EFFACÉE** : elle
  /// n'existe (ou n'a changé) que sur ce poste. L'ancien « tout effacer puis réinsérer »
  /// aurait fait disparaître une saisie d'acompte au prochain tirage, sans un mot.
  ///
  /// ⚠️ **LE SERVEUR SERT LES AVANCES ACTIVES SANS FILTRE `since`** (`SyncController`) :
  /// une avance `synced` absente du tirage a donc été archivée côté serveur — elle est
  /// supprimée. `amount_used` vient toujours du serveur, jamais du poste.
  Future<int> _absorberAvances(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      final protegees = {
        for (final a
            in await (_db.select(_db.customerAdvances)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          a.id,
      };

      for (final l in lignes) {
        if (protegees.contains(l['id'])) continue;

        await _db
            .into(_db.customerAdvances)
            .insertOnConflictUpdate(
              CustomerAdvancesCompanion.insert(
                id: l['id'] as String,
                customerId: (l['customer_id'] ?? '') as String,
                amount: _reel(l['amount']) ?? 0,
                amountUsed: Value(_reel(l['amount_used']) ?? 0),
                advanceDate: Value(_date(l['advance_date'])),
                isActive: Value(_bool(l['is_active'])),
                treasuryAccountId: Value(l['treasury_account_id'] as String?),
                paymentMode: Value(l['payment_mode'] as String?),
                motif: Value(l['motif'] as String?),
                deviceId: Value(l['device_id'] as String?),
                syncStatus: const Value(SyncStatus.synced),
              ),
            );
      }

      final servies = [for (final l in lignes) l['id'] as String];
      await (_db.delete(_db.customerAdvances)..where(
            (t) => Expression.and([
              t.syncStatus.equalsValue(SyncStatus.synced),
              t.id.isIn(servies).not(),
            ]),
          ))
          .go();
    });

    return lignes.length;
  }

  /// Fournisseurs — référentiel remplacé à chaque tirage.
  ///
  /// ⚠️ **REMPLACEMENT COMPLET.** Un fournisseur archivé côté serveur disparaît
  /// du tirage : le garder proposerait à l'acheteur un partenaire que le
  /// serveur refuserait à l'envoi, sans qu'il comprenne pourquoi.
  Future<int> _absorberFournisseurs(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      // ⚠️⚠️ UNE FICHE `pending` OU `conflict` N'EST NI EFFACÉE NI ÉCRASÉE : elle n'existe
      // (ou n'a changé) que sur ce poste. Seules les fiches synchronisées sont remplacées
      // par le tirage — l'ensemble, comme avant.
      final protegees = {
        for (final f
            in await (_db.select(_db.suppliers)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          f.id,
      };

      await (_db.delete(
        _db.suppliers,
      )..where((t) => t.syncStatus.equalsValue(SyncStatus.synced))).go();

      for (final l in lignes) {
        if (protegees.contains(l['id'])) continue;

        await _db
            .into(_db.suppliers)
            .insert(
              SuppliersCompanion.insert(
                id: l['id'] as String,
                name: (l['name'] ?? '') as String,
                category: Value(l['category'] as String?),
                phone: Value(l['phone'] as String?),
                email: Value(l['email'] as String?),
                address: Value(l['address'] as String?),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Plan comptable — référentiel remplacé à chaque tirage.
  Future<int> _absorberPlanComptable(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.chartOfAccounts).go();

      for (final l in lignes) {
        await _db
            .into(_db.chartOfAccounts)
            .insert(
              ChartOfAccountsCompanion.insert(
                id: l['id'] as String,
                code: (l['code'] ?? '') as String,
                label: (l['label'] ?? '') as String,
                accountClass: Value(_entier(l['class'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Exercices comptables — référentiel remplacé à chaque tirage.
  Future<int> _absorberExercices(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.fiscalYears).go();

      for (final l in lignes) {
        await _db
            .into(_db.fiscalYears)
            .insert(
              FiscalYearsCompanion.insert(
                id: l['id'] as String,
                year: _entier(l['year']) ?? 0,
                startDate: Value(_date(l['start_date'])),
                endDate: Value(_date(l['end_date'])),
                status: Value(l['status'] as String?),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Journal comptable : écritures, identifiants des écritures actives, lignes — en UNE transaction.
  ///
  /// ⚠️⚠️ **TICKET F0.84 (serveur 15.28) — LE JOURNAL DU POSTE SE CORRIGE.** Avant, la fusion ne
  /// supprimait jamais rien : une écriture ARCHIVÉE sur le web restait au poste pour toujours, et une
  /// écriture MODIFIÉE (lignes supprimées puis recréées avec de nouveaux identifiants) gardait ses
  /// anciennes lignes en plus des nouvelles — montants doublés, sans aucune erreur.
  ///
  /// Contrat du tirage :
  ///  - `accounting_entries` : les écritures ACTIVES nouvelles ou modifiées depuis `since` ;
  ///  - `accounting_entry_lines` : TOUTES les lignes courantes de ces écritures (jamais une partie) ;
  ///  - `accounting_entry_ids` : les identifiants de TOUTES les écritures actives, SANS filtre `since`.
  ///
  /// Conséquences ici : (1) les lignes d'une écriture servie sont REMPLACÉES, jamais fusionnées ;
  /// (2) ce qui ne figure plus dans `accounting_entry_ids` est retiré, avec ses lignes. Rien ne suppose
  /// un tirage complet : un tirage incrémental suffit.
  ///
  /// ⚠️ **ANCIEN SERVEUR** : si `accounting_entry_ids` est ABSENT (`null`), aucune purge n'est faite —
  /// le poste ne peut pas savoir ce qui a disparu, et supposer « liste vide » viderait le journal.
  /// Limite documentée : une écriture archivée sur un tel serveur reste au poste.
  ///
  /// ⚠️ **TICKET F0.84-bis (suites de l'audit de F0.84)** :
  ///  - écriture annoncée active mais absente après absorption → `_journalManquants`, et [_tirer]
  ///    redemande UNE fois tout le journal (sans `since`), sinon le dit (`journal_incomplet`) ;
  ///  - liste des actives VIDE alors que le poste contient des écritures → pas de purge au premier
  ///    tirage, confirmée par une seconde annonce vide (`journal_vidage_attendu`) ;
  ///  - identifiants = vrais UUID ; montants NaN / ±Infinity refusés ;
  ///  - ⚠️ montant NÉGATIF : NON tranché (règle comptable à décider par le cabinet, voir le ticket).
  ///
  /// ⚠️ **LECTURE SEULE, DONC RIEN À PROTÉGER** : ces deux tables n'ont pas de `sync_status` et aucun
  /// dépôt ne les écrit (un test le verrouille). Aucune ligne `pending`/`conflict` n'existe à épargner.
  ///
  /// ⚠️ **STRICT** : toute entrée incohérente lève une [FormatException] AVANT la première écriture
  /// (identifiant invalide, doublon, date illisible, montant absent ou illisible, ligne dont l'écriture
  /// n'est pas servie, écriture servie mais absente des actives). Le curseur n'avance pas ; le prochain
  /// tirage repart du même point. Un montant absent n'est jamais lu comme 0, une date illisible jamais
  /// remplacée par « aujourd'hui ».
  Future<int> _absorberJournal(
    Object? ecrituresBrut,
    Object? idsActifsBrut,
    Object? lignesBrut,
  ) async {
    if (ecrituresBrut == null && lignesBrut == null && idsActifsBrut == null) {
      return 0;
    }

    List<Map<String, dynamic>> liste(Object? brut, String cle) {
      if (brut == null) return const [];
      if (brut is! List) {
        throw FormatException(
          'Journal refusé : « $cle » n\'est pas une liste.',
        );
      }
      return [
        for (final e in brut)
          if (e is Map)
            e.map((c, v) => MapEntry(c.toString(), v))
          else
            throw FormatException(
              'Journal refusé : « $cle » contient un élément qui n\'est pas un objet.',
            ),
      ];
    }

    // F0.84-bis : un vrai UUID (8-4-4-4-12 hexadécimal), plus seulement « 36 caractères ».
    final formeUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );

    String identifiant(Object? v, String contexte) {
      if (v is! String || !formeUuid.hasMatch(v)) {
        throw FormatException(
          'Journal refusé : identifiant invalide ($contexte : $v).',
        );
      }
      return v;
    }

    final ecritures = liste(ecrituresBrut, 'accounting_entries');
    final lignes = liste(lignesBrut, 'accounting_entry_lines');

    // ── Validation complète AVANT toute écriture en base ────────────────────
    final servies = <String>{};
    final entetes = <AccountingEntriesCompanion>[];
    for (final l in ecritures) {
      final id = identifiant(l['id'], 'écriture');
      if (!servies.add(id)) {
        throw FormatException(
          'Journal refusé : écriture $id servie deux fois.',
        );
      }
      final dateBrute = l['entry_date'];
      final date = dateBrute is String ? _date(dateBrute) : null;
      if (date == null) {
        throw FormatException(
          'Journal refusé : écriture $id, date illisible ($dateBrute).',
        );
      }
      // F0.85 : instant de CRÉATION (ticket 15.29), pour départager deux pièces du même jour au Grand
      // Livre. Absent = serveur plus ancien : on le dit au moteur (la resynchronisation n'est alors pas
      // marquée faite) mais on n'écrase JAMAIS une date déjà connue. Présent mais illisible = refus
      // (jamais « maintenant »).
      DateTime? creeLe;
      if (!l.containsKey('created_at')) {
        _journalSansDateCreation = true;
      } else if (l['created_at'] != null) {
        final brute = l['created_at'];
        creeLe = brute is String ? _instantTechnique(brute) : null;
        if (creeLe == null) {
          throw FormatException(
            'Journal refusé : écriture $id, date de création illisible ($brute).',
          );
        }
      }
      entetes.add(
        AccountingEntriesCompanion.insert(
          id: id,
          fiscalYearId: Value(l['fiscal_year_id'] as String?),
          entryDate: date,
          reference: Value(l['reference'] as String?),
          sourceType: Value(l['source_type'] as String?),
          isLocked: Value(_bool(l['is_locked'])),
          createdAt: Value.absentIfNull(creeLe),
        ),
      );
    }

    final idsLignes = <String>{};
    final corps = <AccountingEntryLinesCompanion>[];
    for (final l in lignes) {
      final id = identifiant(l['id'], 'ligne');
      if (!idsLignes.add(id)) {
        throw FormatException('Journal refusé : ligne $id servie deux fois.');
      }
      final ecriture = identifiant(l['entry_id'], 'écriture de la ligne $id');
      if (!servies.contains(ecriture)) {
        throw FormatException(
          'Journal refusé : la ligne $id dépend de l\'écriture $ecriture, que ce tirage ne sert pas.',
        );
      }
      final compte = identifiant(l['account_id'], 'compte de la ligne $id');
      final debit = _reel(l['debit']);
      final credit = _reel(l['credit']);
      // F0.84-bis : NaN et ±Infinity sont refusés (`double.tryParse` les accepte, SQLite les range).
      // ⚠️ Un montant NÉGATIF n'est PAS tranché ici : règle comptable à décider (voir ticket).
      if (debit == null ||
          credit == null ||
          !debit.isFinite ||
          !credit.isFinite) {
        throw FormatException(
          'Journal refusé : ligne $id, montant absent ou illisible '
          '(débit ${l['debit']}, crédit ${l['credit']}).',
        );
      }
      corps.add(
        AccountingEntryLinesCompanion.insert(
          id: id,
          entryId: ecriture,
          accountId: compte,
          costCenterId: Value(l['cost_center_id'] as String?),
          debit: Value(debit),
          credit: Value(credit),
        ),
      );
    }

    Set<String>? actives;
    if (idsActifsBrut != null) {
      if (idsActifsBrut is! List) {
        throw const FormatException(
          'Journal refusé : « accounting_entry_ids » n\'est pas une liste.',
        );
      }
      actives = {
        for (final v in idsActifsBrut) identifiant(v, 'écriture active'),
      };
      final absentes = servies.difference(actives);
      if (absentes.isNotEmpty) {
        throw FormatException(
          'Journal refusé : écriture servie mais absente des écritures actives '
          '(${absentes.first}).',
        );
      }
    }

    // ⚠️ Copie FINALE : la variable `actives`, capturée par la transaction, n'est pas promue
    // en non-nulle par le compilateur Dart 3.13 (le build Windows échouait sur un SDK stable
    // récent). Aucune règle changée : même valeur, même test de nullité.
    final annoncees = actives;

    // ── Application, en une transaction ─────────────────────────────────────
    String? avertissementVidage;
    await _db.transaction(() async {
      for (final e in entetes) {
        await _db
            .into(_db.accountingEntries)
            .insert(e, onConflict: DoUpdate((_) => e));
      }

      // Les lignes d'une écriture servie sont REMPLACÉES : `updateManual` les recrée avec de
      // nouveaux identifiants, les anciennes ne sont plus servies — et ne doivent plus compter.
      for (final morceau in _morceaux(servies.toList())) {
        await (_db.delete(
          _db.accountingEntryLines,
        )..where((l) => l.entryId.isIn(morceau))).go();
      }
      for (final c in corps) {
        await _db.into(_db.accountingEntryLines).insert(c);
      }

      if (annoncees != null) {
        final locales = [
          for (final e in await _db.select(_db.accountingEntries).get()) e.id,
        ];

        // F0.84-bis — écritures annoncées actives et toujours absentes du poste : l'appelant relance
        // UNE fois le journal complet (voir `_tirer`).
        final presentes = locales.toSet();
        _journalManquants = annoncees.difference(presentes).length;

        // ⚠️⚠️ F0.84-bis — UNE LISTE VIDE N'EST PAS CRUE AU PREMIER TIRAGE. Un 200 avec
        // `accounting_entry_ids: []` peut venir d'un serveur branché sur une base vide ; l'avaler
        // viderait tout le journal local, qui ne se reconstruirait jamais. La réinitialisation
        // LÉGITIME produit la même réponse : la purge est donc repoussée d'un tirage et confirmée
        // par une seconde annonce vide. Aucune règle comptable : seule la prudence sur une
        // suppression irréversible.
        var purger = true;
        if (annoncees.isEmpty && locales.isNotEmpty) {
          if (await _lireReglage(cleJournalVidageAttendu) == null) {
            purger = false;
            await _ecrireReglage(cleJournalVidageAttendu, '1');
            avertissementVidage =
                'Le serveur annonce un journal comptable vide alors que ce poste '
                'contient ${locales.length} écriture(s) : rien n\'est supprimé pour '
                'l\'instant. Si le journal a réellement été réinitialisé, il sera vidé '
                'ici à la prochaine synchronisation.';
          } else {
            await _effacerReglage(cleJournalVidageAttendu);
          }
        } else {
          await _effacerReglage(cleJournalVidageAttendu);
        }
        if (!purger) return;

        final retirees = [
          for (final id in locales)
            if (!annoncees.contains(id)) id,
        ];
        for (final morceau in _morceaux(retirees)) {
          await (_db.delete(
            _db.accountingEntryLines,
          )..where((l) => l.entryId.isIn(morceau))).go();
          await (_db.delete(
            _db.accountingEntries,
          )..where((e) => e.id.isIn(morceau))).go();
        }

        // Lignes orphelines (écriture absente) : jamais conservées, elles fausseraient les états.
        final restantes = {
          for (final e in await _db.select(_db.accountingEntries).get()) e.id,
        };
        final orphelines = {
          for (final l in await _db.select(_db.accountingEntryLines).get())
            if (!restantes.contains(l.entryId)) l.entryId,
        };
        for (final morceau in _morceaux(orphelines.toList())) {
          await (_db.delete(
            _db.accountingEntryLines,
          )..where((l) => l.entryId.isIn(morceau))).go();
        }
      }
    });

    if (avertissementVidage != null) _avertissements.add(avertissementVidage!);

    return ecritures.length + lignes.length;
  }

  /// Découpe une liste d'identifiants pour rester sous la limite de variables de SQLite.
  static Iterable<List<String>> _morceaux(
    List<String> ids, [
    int taille = 500,
  ]) sync* {
    for (var i = 0; i < ids.length; i += taille) {
      yield ids.sublist(i, i + taille > ids.length ? ids.length : i + taille);
    }
  }

  /// Identité de la ferme — un OBJET, pas une collection.
  ///
  /// ⚠️⚠️ **LE SERVEUR NE SERT AUCUN SECRET**, et le poste n'a donc aucune
  /// colonne où en ranger : mots de passe SMTP et jetons SMS restent sur le
  /// serveur, même chiffrés. Un poste volé ne donne pas la boîte mail de la
  /// ferme.
  ///
  /// Ticket H9b (D-H9) — le DÉLAI DU RAPPEL DES SOINS (`rappel_soins_jours`, 0 à 30) descend avec l'identité.
  /// ⚠️⚠️ **STRICT** : une valeur qui n'est pas un entier de 0 à 30 refuse la ligne entière
  /// ([FormatException], rien n'est écrit). ⚠️ Un délai réglé sur ce poste et pas encore acquitté (`pending`,
  /// `conflict`) n'est JAMAIS écrasé ; l'identité de la ferme, elle, se met à jour. Clé absente (serveur
  /// antérieur à H9b) : le délai local est laissé tel quel.
  Future<int> _absorberEntreprise(Object? brut) async {
    if (brut is! Map) return 0;

    final l = brut.map((c, v) => MapEntry(c.toString(), v));

    final delaiServi = l.containsKey('rappel_soins_jours');
    final delai = l['rappel_soins_jours'];
    if (delaiServi &&
        delai != null &&
        (delai is! int || delai < 0 || delai > 30)) {
      throw FormatException(
        'Paramètres de l\'entreprise refusés : délai du rappel des soins illisible ($delai).',
      );
    }

    await _db.transaction(() async {
      final locale = await (_db.select(
        _db.companySettings,
      )..where((t) => t.id.equals('unique'))).getSingleOrNull();
      final protege =
          locale != null && locale.syncStatus != SyncStatus.synced;

      final ligne = CompanySettingsCompanion.insert(
        id: const Value('unique'),
        companyName: Value(l['company_name'] as String?),
        promoterName: Value(l['promoter_name'] as String?),
        address: Value(l['address'] as String?),
        phone: Value(l['phone'] as String?),
        email: Value(l['email'] as String?),
        ifu: Value(l['ifu'] as String?),
        rccm: Value(l['rccm'] as String?),
        tvaEnabled: Value(_bool(l['tva_enabled'])),
        tvaDefaultRate: Value(_reel(l['tva_default_rate'])),
        rappelSoinsJours: delaiServi && !protege
            ? Value(delai as int?)
            : const Value.absent(),
        syncStatus: delaiServi && !protege
            ? const Value(SyncStatus.synced)
            : const Value.absent(),
      );

      await _db
          .into(_db.companySettings)
          .insert(ligne, onConflict: DoUpdate((_) => ligne));
    });

    return 1;
  }

  /// Modules d'espèce — référentiel remplacé à chaque tirage.
  ///
  /// ⚠️⚠️ **C'EST CE QUI DÉCIDE DES ESPÈCES VISIBLES.** Une ferme qui éteint
  /// l'héliciculture ne doit plus voir la fiche Escargots : la maquette masque
  /// les blocs `data-module`, le poste filtre ses cartes d'espèce.
  Future<int> _absorberModules(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      // ⚠️⚠️ TICKET MOD1 — UNE BASCULE FAITE SUR CE POSTE ET PAS ENCORE ACQUITTÉE N'EST JAMAIS ÉCRASÉE. Le référentiel
      // était remplacé en bloc à chaque tirage : le serveur, qui n'avait pas encore reçu la bascule, renvoyait
      // l'ancienne valeur et le module « revenait » tout seul à son état d'avant. Les lignes `pending` / `conflict`
      // sont mises de côté, gardent leur valeur locale et leur statut ; les autres sont remplacées comme avant.
      final locales = await _db.select(_db.modulesConfig).get();
      final enAttente = {
        for (final m in locales)
          if (m.syncStatus != SyncStatus.synced) m.speciesCode: m,
      };

      await _db.delete(_db.modulesConfig).go();

      final vus = <String>{};
      for (final l in lignes) {
        final code = (l['species_code'] ?? '') as String;
        final locale = enAttente[code];
        vus.add(code);
        await _db
            .into(_db.modulesConfig)
            .insert(
              ModulesConfigCompanion.insert(
                id: l['id'] as String,
                speciesCode: code,
                isEnabled: Value(locale != null ? locale.isEnabled : _bool(l['is_enabled'])),
                syncStatus: Value(locale?.syncStatus ?? SyncStatus.synced),
                updatedAt: Value(locale?.updatedAt),
              ),
            );
      }

      // Une bascule en attente pour une espèce que le serveur ne liste pas (poste qui n'a jamais tiré cette ligne) reste.
      for (final locale in enAttente.values) {
        if (!vus.contains(locale.speciesCode)) {
          await _db.into(_db.modulesConfig).insert(locale);
        }
      }
    });

    return lignes.length;
  }

  /// Rôles applicatifs — référentiel remplacé à chaque tirage.
  Future<int> _absorberRoles(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.rolesApplicatifs).go();

      for (final l in lignes) {
        final permissions = l['permissions'];

        await _db
            .into(_db.rolesApplicatifs)
            .insert(
              RolesApplicatifsCompanion.insert(
                id: (l['id'] ?? '').toString(),
                name: (l['name'] ?? '') as String,
                permissions: Value(
                  permissions is List ? permissions.join(', ') : null,
                ),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Utilisateurs — référentiel remplacé à chaque tirage.
  Future<int> _absorberUtilisateurs(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.utilisateurs).go();

      for (final l in lignes) {
        await _db
            .into(_db.utilisateurs)
            .insert(
              UtilisateursCompanion.insert(
                id: l['id'] as String,
                name: (l['name'] ?? '') as String,
                username: Value(l['username'] as String?),
                email: Value(l['email'] as String?),
                role: Value(l['role'] as String?),
                isActive: Value(_bool(l['is_active'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Journal d'audit — les deux cents dernières actions (U14 : la liste du web), remplacées à chaque tirage.
  Future<int> _absorberAudit(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.auditLogs).go();

      for (final l in lignes) {
        await _db
            .into(_db.auditLogs)
            .insert(
              AuditLogsCompanion.insert(
                id: l['id'] as String,
                userName: Value(l['user_name'] as String?),
                action: (l['action'] ?? '') as String,
                module: Value(l['module'] as String?),
                ipAddress: Value(l['ip_address'] as String?),
                createdAt: Value(_instantTechnique(l['created_at'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Notifications de l'utilisateur du jeton — l'ENSEMBLE est remplacé à chaque
  /// tirage (ticket F0.59).
  ///
  /// ⚠️ **PAS DE TIRAGE INCRÉMENTAL** : « lue » et « supprimée » changent sans
  /// toucher à `created_at`, un `since` ne les verrait jamais. Le serveur envoie
  /// donc les 200 dernières visibles, et le poste remplace tout — une
  /// notification supprimée ailleurs disparaît ainsi d'ici.
  ///
  /// ⚠️ **ABSORBEUR STRICT** : une ligne sans identifiant ou sans message est
  /// REFUSÉE (l'exception remonte), jamais comblée par un texte inventé.
  Future<int> _absorberNotifications(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.notifications).go();

      for (final l in lignes) {
        await _db
            .into(_db.notifications)
            .insert(
              NotificationsCompanion.insert(
                id: l['id'] as String,
                type: (l['type'] ?? 'system') as String,
                category: Value((l['category'] ?? 'Système') as String),
                severity: Value((l['severity'] ?? 'info') as String),
                title: (l['title'] ?? '') as String,
                message: l['message'] as String,
                linkUrl: Value(l['link_url'] as String?),
                isRead: Value(_bool(l['is_read'])),
                createdAt: Value(_instantTechnique(l['created_at'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Revenus par bande — l'ENSEMBLE est remplacé à chaque tirage (ticket F0.63).
  ///
  /// ⚠️ **UN TIRAGE SANS CE BLOC NE VIDE RIEN** (`brut == null`) : un serveur plus
  /// ancien n'envoie pas `lot_revenues`, et effacer les revenus connus sur ce
  /// silence les ferait disparaître.
  ///
  /// ⚠️ **UNE LISTE VIDE EST UNE RÉPONSE** : « aucune vente imputée à une bande ».
  /// La date de ce tirage est donc gardée À PART (`lot_revenues_tire_le`) : sans
  /// elle, le poste ne distinguerait pas « aucune vente » de « revenus jamais
  /// reçus », et afficherait « aucune vente » juste après une mise à jour, avant
  /// la première synchronisation.
  Future<int> _absorberRevenusDeBande(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.lotRevenues).go();

      for (final l in lignes) {
        await _db
            .into(_db.lotRevenues)
            .insert(
              LotRevenuesCompanion.insert(
                lotId: l['lot_id'] as String,
                productId: l['product_id'] as String,
                label: (l['label'] ?? '') as String,
                amount: _reel(l['amount']) ?? 0,
              ),
            );
      }

      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: cleRevenusTires,
              value: DateTime.now().toUtc().toIso8601String(),
            ),
          );
    });

    return lignes.length;
  }

  /// Clé de `app_settings` datant le dernier tirage des revenus par bande.
  static const cleRevenusTires = 'lot_revenues_tire_le';

  /// Espèces d'élevage actives — l'ENSEMBLE est remplacé à chaque tirage (F0.67).
  ///
  /// ⚠️ Un tirage sans ce bloc ne vide rien (serveur plus ancien). Une liste VIDE
  /// est une réponse : aucun module d'espèce n'est actif.
  Future<int> _absorberEspeces(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.livestockSpecies).go();

      for (final l in lignes) {
        await _db
            .into(_db.livestockSpecies)
            .insert(
              LivestockSpeciesCompanion.insert(
                id: l['id'] as String,
                code: l['code'] as String,
                label: l['label'] as String,
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Sujets suivis individuellement — l'ENSEMBLE est remplacé à chaque tirage (ticket F0.65).
  ///
  /// ⚠️ Un tirage sans ce bloc ne vide rien (serveur plus ancien). Absorbeur STRICT (ticket BS3, comme
  /// [_absorberBandes]) : identifiant absent ou servi deux fois, identifiant lisible vide, `is_active` illisible →
  /// [FormatException] : rien n'est écrit, la page est annulée, le curseur n'avance pas. Un sujet sans identifiant lisible
  /// ne se retrouverait ni par son QR ni par la référence d'une saillie.
  ///
  /// ⚠️⚠️ **UN SUJET LOCAL `pending` OU `conflict` N'EST JAMAIS ÉCRASÉ NI SUPPRIMÉ** (enregistré, modifié ou sorti ici, pas
  /// encore acquitté, ou refusé et en attente de correction) : le tirage précède toujours l'envoi. Les sujets acquittés
  /// (`synced`) sont remplacés par l'ensemble servi : un sujet absent du tirage disparaît, un sujet servi prend la dernière
  /// version du serveur.
  Future<int> _absorberSujets(Object? brut) async {
    if (brut == null) return 0;

    const quoi = 'Sujet';
    final lignes = _lignesStrictes(brut, quoi);

    final vus = <String>{};
    final recues = <AnimalsCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, quoi);
      final identifiant = _texteStrict(l['identifier'], '$quoi $id : identifiant');
      if (identifiant == null || identifiant.isEmpty) {
        throw FormatException('$quoi $id refusé : identifiant lisible absent.');
      }
      recues.add(
        AnimalsCompanion.insert(
          id: id,
          identifier: identifiant,
          speciesId: Value(_texteStrict(l['species_id'], '$quoi $id : espèce')),
          speciesLabel: Value(_texteStrict(l['species_label'], '$quoi $id : libellé d\'espèce')),
          lotId: Value(_texteStrict(l['lot_id'], '$quoi $id : bande')),
          lotCode: Value(_texteStrict(l['lot_code'], '$quoi $id : code de bande')),
          category: Value(_texteStrict(l['category'], '$quoi $id : catégorie') ?? 'reproducteur'),
          sex: Value(_texteStrict(l['sex'], '$quoi $id : sexe') ?? 'F'),
          breed: Value(_texteStrict(l['breed'], '$quoi $id : race')),
          birthDate: Value(_date(l['birth_date'])),
          entryDate: Value(_date(l['entry_date'])),
          origin: Value(_texteStrict(l['origin'], '$quoi $id : origine')),
          cage: Value(_texteStrict(l['cage'], '$quoi $id : cage')),
          status: Value(_texteStrict(l['status'], '$quoi $id : statut') ?? 'actif'),
          exitDate: Value(_date(l['exit_date'])),
          exitReason: Value(_texteStrict(l['exit_reason'], '$quoi $id : motif de sortie')),
          isActive: Value(_actifStrict(l, '$quoi $id')),
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
    }

    await _db.transaction(() async {
      // Les acquittés sont remplacés par l'ensemble servi ; les `pending` / `conflict` restent tels quels.
      await (_db.delete(_db.animals)..where((t) => t.syncStatus.equalsValue(SyncStatus.synced))).go();
      final gardes = {
        for (final a in await _db.select(_db.animals).get()) a.id,
      };
      for (final a in recues) {
        if (gardes.contains(a.id.value)) continue;
        await _db.into(_db.animals).insert(a);
      }
    });

    return lignes.length;
  }

  /// Modèles d'attestation — l'ENSEMBLE est remplacé à chaque tirage (F0.64).
  ///
  /// ⚠️ Un tirage sans ce bloc ne vide rien (serveur plus ancien). Absorbeur
  /// STRICT : un modèle sans identifiant ou sans texte est refusé, jamais comblé
  /// par un texte inventé — un modèle fait foi sur un document officiel.
  Future<int> _absorberModelesAttestation(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.attestationTemplates).go();

      for (final l in lignes) {
        await _db
            .into(_db.attestationTemplates)
            .insert(
              AttestationTemplatesCompanion.insert(
                id: l['id'] as String,
                type: l['type'] as String,
                bodyText: l['body_text'] as String,
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Nombre d'attestations émises, par type — ⚠️ UN DÉCOMPTE D'AUDIT DU SERVEUR.
  ///
  /// Le poste ne détient que les deux cents dernières lignes d'audit de la ferme : il
  /// ne peut pas recompter. Le serveur compte sur l'historique entier ; le poste
  /// garde ce nombre tel quel, dans `app_settings`.
  Future<int> _absorberCompteursAttestation(Object? brut) async {
    if (brut is! Map) return 0;

    var n = 0;
    for (final type in ['employe', 'stagiaire']) {
      final valeur = _entier(brut[type]);
      if (valeur == null) continue;

      await _db
          .into(_db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: cleAttestationsEmises(type),
              value: '$valeur',
            ),
          );
      n++;
    }
    return n;
  }

  /// Clé de `app_settings` portant le nombre d'attestations émises d'un type.
  static String cleAttestationsEmises(String type) =>
      'attestations_emises_$type';

  /// Courriers — FUSIONNÉS par identifiant (ticket F0.78).
  ///
  /// ⚠️⚠️ **« TOUT EFFACER PUIS RÉINSÉRER » EST RETIRÉ** : il aurait fait disparaître, au
  /// tirage suivant, un courrier saisi au poste et pas encore acquitté. Un courrier
  /// `pending` ou `conflict` n'est NI écrasé NI effacé : il n'existe (ou n'a changé) que
  /// sur ce poste.
  ///
  /// ⚠️ **LE SERVEUR SERT TOUS LES COURRIERS ACTIFS À CHAQUE TIRAGE**, plus les archivés
  /// dont `updated_at > since` (avec `is_active = false`). Donc : un archivé qui descend
  /// est retiré du poste ; un courrier `synced` absent du tirage a été archivé plus tôt
  /// (ou n'existe plus) — il est retiré aussi. La référence `CR-AAAA-NNN` vient toujours
  /// du serveur.
  ///
  /// ⚠️ **STRICT** : une ligne sans identifiant, sans objet, de type inconnu ou de date
  /// illisible est REFUSÉE (la transaction entière est annulée) — jamais comblée.
  Future<int> _absorberCourriers(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      final protegees = {
        for (final m
            in await (_db.select(_db.mails)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          m.id,
      };

      final servis = <String>{};

      for (final l in lignes) {
        final id = l['id'];
        final type = l['type'];
        final objet = l['subject'];

        if (id is! String || id.length != 36) {
          throw FormatException(
            'Courrier refusé : identifiant invalide ($id).',
          );
        }
        if (type != 'entrant' && type != 'sortant') {
          throw FormatException('Courrier $id refusé : type inconnu ($type).');
        }
        if (objet is! String || objet.trim().isEmpty) {
          throw FormatException('Courrier $id refusé : objet absent.');
        }
        final dateBrute = l['mail_date'];
        final date = _date(dateBrute);
        if (dateBrute != null && date == null) {
          throw FormatException(
            'Courrier $id refusé : date illisible ($dateBrute).',
          );
        }

        servis.add(id);
        if (protegees.contains(id)) continue;

        // Archivé côté serveur : il quitte la liste du poste (rien n'y est supprimé là-bas).
        if (l.containsKey('is_active') && !_bool(l['is_active'])) {
          await (_db.delete(_db.mails)..where((t) => t.id.equals(id))).go();
          continue;
        }

        await _db
            .into(_db.mails)
            .insertOnConflictUpdate(
              MailsCompanion.insert(
                id: id,
                reference: Value(l['reference'] as String?),
                type: type as String,
                subject: objet,
                party: Value(l['party'] as String?),
                mailDate: Value(date),
                isActive: const Value(true),
                syncStatus: const Value(SyncStatus.synced),
                knownByServer: const Value(true),
              ),
            );
      }

      // Une ligne synchronisée que le serveur n'a PAS servie n'est plus un courrier actif.
      await (_db.delete(_db.mails)..where(
            (t) => Expression.and([
              t.syncStatus.equalsValue(SyncStatus.synced),
              t.id.isIn(servis).not(),
            ]),
          ))
          .go();
    });

    return lignes.length;
  }

  /// Documents administratifs — FUSIONNÉS par identifiant (ticket F0.80), comme les courriers
  /// et les documents archivés.
  ///
  /// ⚠️⚠️ **« TOUT EFFACER PUIS RÉINSÉRER » EST RETIRÉ** : il aurait fait disparaître, au
  /// tirage suivant, un document saisi au poste et pas encore acquitté, et fait réapparaître un
  /// document retiré sur le web. Une ligne `pending` ou `conflict` n'est NI écrasée NI
  /// effacée : elle n'existe (ou n'a changé) que sur ce poste.
  ///
  /// ⚠️ **LE SERVEUR SERT TOUS LES DOCUMENTS ACTIFS À CHAQUE TIRAGE**, plus les retirés dont
  /// `updated_at > since` (avec `is_active = false`). Donc : un retiré qui descend est
  /// supprimé du poste ; une ligne `synced` absente du tirage a été retirée plus tôt (ou
  /// n'existe plus) — supprimée aussi.
  ///
  /// ⚠️ **STRICT** : identifiant ≠ 36 caractères, titre / type / bénéficiaire absents ou
  /// vides, date absente ou illisible, statut hors {signe, en_attente} → REFUSÉ (la transaction
  /// entière est annulée), jamais comblé. Un type hors de la liste proposée (texte libre) est
  /// conservé tel quel.
  Future<int> _absorberDocuments(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      final protegees = {
        for (final d
            in await (_db.select(_db.administrativeDocuments)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          d.id,
      };

      final servis = <String>{};

      for (final l in lignes) {
        final id = l['id'];
        final titre = l['title'];
        final type = l['type'];
        final beneficiaire = l['beneficiary'];
        final statut = l['status'];

        if (id is! String || id.length != 36) {
          throw FormatException(
            'Document administratif refusé : identifiant invalide ($id).',
          );
        }
        if (titre is! String || titre.trim().isEmpty) {
          throw FormatException(
            'Document administratif $id refusé : titre absent.',
          );
        }
        if (type is! String || type.trim().isEmpty) {
          throw FormatException(
            'Document administratif $id refusé : type absent.',
          );
        }
        if (beneficiaire is! String || beneficiaire.trim().isEmpty) {
          throw FormatException(
            'Document administratif $id refusé : bénéficiaire absent.',
          );
        }
        final dateBrute = l['doc_date'];
        final date = _date(dateBrute);
        if (date == null) {
          throw FormatException(
            'Document administratif $id refusé : date illisible ($dateBrute).',
          );
        }
        if (statut != 'signe' && statut != 'en_attente') {
          throw FormatException(
            'Document administratif $id refusé : statut inconnu ($statut).',
          );
        }

        servis.add(id);
        if (protegees.contains(id)) continue;

        // Retiré côté serveur : il quitte la liste du poste (rien n'y est supprimé là-bas).
        if (l.containsKey('is_active') && !_bool(l['is_active'])) {
          await (_db.delete(
            _db.administrativeDocuments,
          )..where((t) => t.id.equals(id))).go();
          continue;
        }

        await _db
            .into(_db.administrativeDocuments)
            .insertOnConflictUpdate(
              AdministrativeDocumentsCompanion.insert(
                id: id,
                title: titre,
                type: Value(type),
                beneficiary: Value(beneficiaire),
                docDate: Value(date),
                status: Value(statut as String),
                isActive: const Value(true),
                syncStatus: const Value(SyncStatus.synced),
                knownByServer: const Value(true),
              ),
            );
      }

      // Une ligne synchronisée que le serveur n'a PAS servie n'est plus un document actif.
      await (_db.delete(_db.administrativeDocuments)..where(
            (t) => Expression.and([
              t.syncStatus.equalsValue(SyncStatus.synced),
              t.id.isIn(servis).not(),
            ]),
          ))
          .go();
    });

    return lignes.length;
  }

  /// Documents archivés — FUSIONNÉS par identifiant (ticket F0.79), comme les courriers.
  ///
  /// ⚠️⚠️ **« TOUT EFFACER PUIS RÉINSÉRER » EST RETIRÉ** : il aurait fait disparaître, au
  /// tirage suivant, un document saisi au poste et pas encore acquitté. Une ligne
  /// `pending` ou `conflict` n'est NI écrasée NI effacée : elle n'existe (ou n'a changé) que
  /// sur ce poste.
  ///
  /// ⚠️ **LE SERVEUR SERT TOUS LES DOCUMENTS ACTIFS À CHAQUE TIRAGE**, plus les retirés dont
  /// `updated_at > since` (avec `is_active = false`). Donc : un retiré qui descend est
  /// supprimé du poste ; une ligne `synced` absente du tirage a été retirée plus tôt (ou n'existe
  /// plus) — supprimée aussi. Aucun statut n'est servi : il se calcule au poste.
  ///
  /// ⚠️ **STRICT** : identifiant ≠ 36 caractères, titre ou catégorie absents ou vides, date
  /// d'archivage absente ou illisible, échéance illisible → REFUSÉ (la transaction entière
  /// est annulée), jamais comblé.
  Future<int> _absorberArchives(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      final protegees = {
        for (final a
            in await (_db.select(_db.archivedDocuments)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.synced).not(),
                ))
                .get())
          a.id,
      };

      final servis = <String>{};

      for (final l in lignes) {
        final id = l['id'];
        final titre = l['title'];
        final categorie = l['category'];

        if (id is! String || id.length != 36) {
          throw FormatException(
            'Document archivé refusé : identifiant invalide ($id).',
          );
        }
        if (titre is! String || titre.trim().isEmpty) {
          throw FormatException('Document archivé $id refusé : titre absent.');
        }
        if (categorie is! String || categorie.trim().isEmpty) {
          throw FormatException(
            'Document archivé $id refusé : catégorie absente.',
          );
        }
        final archiveBrute = l['archived_date'];
        final archive = _date(archiveBrute);
        if (archive == null) {
          throw FormatException(
            'Document archivé $id refusé : date d\'archivage illisible ($archiveBrute).',
          );
        }
        final echeanceBrute = l['expiry_date'];
        final echeance = _date(echeanceBrute);
        if (echeanceBrute != null && echeance == null) {
          throw FormatException(
            'Document archivé $id refusé : échéance illisible ($echeanceBrute).',
          );
        }

        servis.add(id);
        if (protegees.contains(id)) continue;

        // Retiré côté serveur : il quitte la liste du poste (rien n'y est supprimé là-bas).
        if (l.containsKey('is_active') && !_bool(l['is_active'])) {
          await (_db.delete(
            _db.archivedDocuments,
          )..where((t) => t.id.equals(id))).go();
          continue;
        }

        await _db
            .into(_db.archivedDocuments)
            .insertOnConflictUpdate(
              ArchivedDocumentsCompanion.insert(
                id: id,
                title: titre,
                category: Value(categorie),
                archivedDate: Value(archive),
                expiryDate: Value(echeance),
                isActive: const Value(true),
                syncStatus: const Value(SyncStatus.synced),
                knownByServer: const Value(true),
              ),
            );
      }

      // Une ligne synchronisée que le serveur n'a PAS servie n'est plus un document actif.
      await (_db.delete(_db.archivedDocuments)..where(
            (t) => Expression.and([
              t.syncStatus.equalsValue(SyncStatus.synced),
              t.id.isIn(servis).not(),
            ]),
          ))
          .go();
    });

    return lignes.length;
  }

  /// Employés — référentiel remplacé à chaque tirage.
  ///
  /// ⚠️ Un employé archivé côté serveur disparaît du tirage : le garder ferait
  /// pointer quelqu'un qui a quitté la ferme, et le pointage serait rejeté à
  /// l'envoi sans que le chef d'équipe comprenne.
  Future<int> _absorberEmployes(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.employees).go();

      for (final l in lignes) {
        await _db
            .into(_db.employees)
            .insert(
              EmployeesCompanion.insert(
                id: l['id'] as String,
                firstName: (l['first_name'] ?? '') as String,
                lastName: (l['last_name'] ?? '') as String,
                position: Value(l['position'] as String?),
                baseSalary: Value(_reel(l['base_salary'])),
                hireDate: Value(_date(l['hire_date'])),
                status: Value(l['status'] as String?),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Stagiaires — référentiel remplacé à chaque tirage.
  Future<int> _absorberStagiaires(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.internships).go();

      for (final l in lignes) {
        await _db
            .into(_db.internships)
            .insert(
              InternshipsCompanion.insert(
                id: l['id'] as String,
                firstName: (l['first_name'] ?? '') as String,
                lastName: (l['last_name'] ?? '') as String,
                school: Value(l['school'] as String?),
                startDate: Value(_date(l['start_date'])),
                endDate: Value(_date(l['end_date'])),
                monthlyFee: Value(_reel(l['monthly_fee'])),
                feePaid: Value(_bool(l['fee_paid'])),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Pointages — fusion, et un pointage `pending` reste intouchable.
  ///
  /// ⚠️⚠️ **CE QUI N'EST PAS PARTI N'EST PAS ÉCRASÉ.** Le pointage de ce matin
  /// n'existe que sur ce poste : l'effacer perdrait la seule trace de la
  /// présence, et la paie du mois se calcule dessus.
  Future<int> _absorberPointages(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    for (final l in lignes) {
      final id = l['id'] as String;

      final local = await (_db.select(
        _db.attendanceRecords,
      )..where((t) => t.id.equals(id))).getSingleOrNull();

      if (local != null && local.syncStatus != SyncStatus.synced) continue;

      final jour = _date(l['attendance_date']) ?? HeureBenin.aujourdhui();

      final ligne = AttendanceRecordsCompanion.insert(
        id: id,
        deviceId: 'serveur',
        updatedAt: jour,
        syncStatus: const Value(SyncStatus.synced),
        employeeId: (l['employee_id'] ?? '') as String,
        attendanceDate: jour,
        checkIn: Value(l['check_in'] as String?),
        checkOut: Value(l['check_out'] as String?),
        status: (l['status'] ?? 'present') as String,
      );

      await _db
          .into(_db.attendanceRecords)
          .insert(ligne, onConflict: DoUpdate((_) => ligne));
    }

    return lignes.length;
  }

  /// Factures — c'est-à-dire les VENTES de toute la ferme.
  ///
  /// ⚠️⚠️ **FUSION, JAMAIS UN REMPLACEMENT — ET UNE VENTE `pending` EST
  /// INTOUCHABLE.** Elle n'existe que sur ce poste : encaissée au comptoir il y
  /// a dix minutes, pas encore envoyée. L'écraser perdrait la recette ET la
  /// sortie de stock qui l'accompagne.
  ///
  /// ⚠️ **LE STATUT MeCeF PEUT CHANGER SANS QUE LA VENTE CHANGE** : une
  /// retransmission réussie depuis le web touche `updated_at`, la facture
  /// redescend donc avec son nouveau statut. C'est la seule façon pour le poste
  /// d'apprendre qu'une transmission en erreur a été rattrapée.
  Future<int> _absorberVentes(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    for (final l in lignes) {
      final id = l['id'] as String;

      final locale = await (_db.select(
        _db.sales,
      )..where((t) => t.id.equals(id))).getSingleOrNull();

      if (locale != null && locale.syncStatus != SyncStatus.synced) continue;

      // TICKET F0.93 (réserve 2 de l'audit indépendant) : le repli lit l'horloge INJECTÉE,
      // comme `horodatage` ci-dessous — jamais `DateTime.now()`, invisible à un test figé.
      final vendueLe = _date(l['sold_at']) ?? HeureBenin.depuisInstant(_maintenant());

      // 🔴→✅ TICKET F0.90 (remarque B2 de l'audit) — `updatedAt` N'EST PLUS `sold_at`. Règle du
      // poste : `updatedAt` = instant de la SAISIE (ou, pour ce qui vient d'ailleurs, de la
      // RÉCEPTION), jamais le jour de la vente : une vente antidatée au 11 et saisie le 14 aurait
      // reçu un horodatage du 11. Le serveur ne sert NI `updated_at` NI `created_at` de la vente
      // (lu : `SyncController::pull`, bloc `$factures`) ; le poste n'invente donc rien :
      //  - vente déjà connue (saisie sur CE poste, ou déjà reçue) : son `updatedAt` est GARDÉ —
      //    un changement de statut MeCeF ne change pas l'instant où la vente a été saisie ;
      //  - vente inconnue : instant de la RÉCEPTION (horloge du poste).
      // Sans effet sur l'arbitrage aujourd'hui (une vente acquittée ne repart jamais) ; c'est la
      // valeur qui ne peut pas mentir le jour où elle servira.
      final horodatage = locale?.updatedAt ?? _maintenant();

      final ligne = SalesCompanion.insert(
        id: id,
        deviceId: 'serveur',
        updatedAt: horodatage,
        syncStatus: const Value(SyncStatus.synced),
        customerId: Value(l['customer_id'] as String?),
        customerName: Value(l['customer_name'] as String?),
        paymentMode: (l['payment_mode'] ?? 'especes') as String,
        // Ticket AV2 — sous-total et remise servis (colonne « Remise » et détail d'une vente de l'historique). Absents
        // (serveur antérieur) : la remise reste 0 et le sous-total le total, comme avant.
        subtotal: Value(_reel(l['subtotal']) ?? _reel(l['total']) ?? 0),
        discount: Value(_reel(l['discount']) ?? 0),
        total: _reel(l['total']) ?? 0,
        status: Value((l['status'] ?? 'validee') as String),
        mecefStatus: Value(l['mecef_status'] as String?),
        mecefQrRef: Value(l['mecef_qr_ref'] as String?),
        soldAt: vendueLe,
      );

      await _db
          .into(_db.sales)
          .insert(ligne, onConflict: DoUpdate((_) => ligne));
    }

    return lignes.length;
  }

  /// Ticket U4 (D-U4) — LIGNES DES VENTES servies par le tirage (`sale_lines`).
  ///
  /// Sans elles, le Top 5 des produits et les « Ventes (mois) » porcines du Tableau de bord ne comptaient que
  /// les ventes saisies SUR CE POSTE, quand le web les compte toutes. Règles, communes à
  /// [_absorberLignesDAchat] (voir [_remplacerLignesDePieces]) :
  ///  - ⚠️⚠️ une vente `pending` ou en `conflict` sur ce poste n'a JAMAIS ses lignes touchées : ce sont celles
  ///    de la saisie, qui repartiront avec elle à l'envoi ;
  ///  - les lignes d'une vente `synced` servie sont REMPLACÉES par celles du serveur (il sert TOUTES les lignes
  ///    de chaque vente servie) : une ligne retirée au web disparaît ici aussi ;
  ///  - STRICT : élément illisible, ligne d'une vente non servie par ce tirage (fuite) ou produit inconnu du
  ///    poste → [FormatException], rien n'est écrit, le curseur n'avance pas ;
  ///  - `manual_total_amount` est la source de vérité du montant ; `unit_price` est gardé tel que servi.
  /// Clé absente (serveur antérieur à U4) : rien n'est touché.
  Future<int> _absorberLignesDeVente(Object? brutPieces, Object? brut) =>
      _remplacerLignesDePieces<SaleLinesCompanion>(
        quoi: 'Ligne de vente',
        brutPieces: brutPieces,
        brut: brut,
        cle: 'sale_id',
        protegees: () async => {
          for (final v in await (_db.select(
            _db.sales,
          )..where((t) => t.syncStatus.equalsValue(SyncStatus.synced).not())).get())
            v.id,
        },
        lire: (l, id, piece, produit) {
          final qte = _reel(l['qty']);
          final prix = _reel(l['unit_price']);
          final montant = _reel(l['manual_total_amount']);
          final lot = l['lot_id'];
          if (qte == null ||
              prix == null ||
              montant == null ||
              (lot != null && lot is! String)) {
            return null;
          }
          return SaleLinesCompanion.insert(
            id: id,
            saleId: piece,
            productId: produit,
            lotId: Value(lot as String?),
            qty: qte,
            unitPrice: prix,
            manualTotalAmount: montant,
          );
        },
        remplacer: (pieces, lignes) async {
          await (_db.delete(
            _db.saleLines,
          )..where((t) => t.saleId.isIn(pieces))).go();
          await _db.batch((b) => b.insertAll(_db.saleLines, lignes));
        },
      );

  /// Ticket U4 (D-U4) — LIGNES DES ACHATS servies par le tirage (`purchase_lines`). Mêmes règles que
  /// [_absorberLignesDeVente] : un achat `pending` ou en `conflict` garde ses lignes (elles partent avec lui à
  /// l'envoi). Elles rendent le PMP calculable au poste (`Product::computePmp()` : TOUTES les lignes d'achat).
  Future<int> _absorberLignesDAchat(Object? brutPieces, Object? brut) =>
      _remplacerLignesDePieces<PurchaseLinesCompanion>(
        quoi: "Ligne d'achat",
        brutPieces: brutPieces,
        brut: brut,
        cle: 'purchase_id',
        protegees: () async => {
          for (final a in await (_db.select(
            _db.purchases,
          )..where((t) => t.syncStatus.equalsValue(SyncStatus.synced).not())).get())
            a.id,
        },
        lire: (l, id, piece, produit) {
          final qte = _reel(l['qty']);
          final prix = _reel(l['unit_price']);
          final nom = l['product_name'];
          if (qte == null || prix == null || (nom != null && nom is! String)) {
            return null;
          }
          return PurchaseLinesCompanion.insert(
            id: id,
            purchaseId: piece,
            productId: produit,
            productName: Value(nom as String?),
            qty: qte,
            unitPrice: prix,
          );
        },
        remplacer: (pieces, lignes) async {
          await (_db.delete(
            _db.purchaseLines,
          )..where((t) => t.purchaseId.isIn(pieces))).go();
          await _db.batch((b) => b.insertAll(_db.purchaseLines, lignes));
        },
      );

  /// Ticket U9 — GRAND LIVRE DES STOCKS (`stock_movements`) servi par le tirage.
  ///
  /// Journal écrit par le serveur SEUL (`AdjustStockAction`) : au poste, une table en LECTURE SEULE que rien
  /// n'écrit ni n'envoie — il n'y a donc aucune saisie locale à protéger. Tout au premier tirage, puis au curseur
  /// avec un recouvrement de deux minutes (voir `SyncController::pull`) : un mouvement déjà reçu est REMPLACÉ par
  /// identifiant, jamais dupliqué.
  ///
  /// ⚠️⚠️ **STRICT** : élément illisible, identifiant invalide ou servi deux fois, produit inconnu du poste, type
  /// hors `entree`/`sortie`/`ajustement`, quantité absente, illisible ou négative, motif de référence absent,
  /// référence ou motif qui n'est pas un texte, date illisible → [FormatException] : RIEN n'est écrit, le curseur
  /// n'avance pas. Lisser — une quantité illisible devenue 0, un type inconnu lu comme une entrée — fausserait en
  /// silence la rotation, les écarts d'inventaire et le stock d'œufs de la ferme.
  ///
  /// Clé absente (serveur antérieur à U9) : rien n'est touché. Les saisies EN ATTENTE du poste n'y sont jamais
  /// écrites : `JournalStocks` les ajoute à la lecture, et les retire dès que leur mouvement est redescendu.
  Future<int> _absorberMouvementsStock(Object? brut) async {
    if (brut == null) return 0;

    const quoi = 'Mouvement de stock';
    final lignes = _lignesStrictes(brut, quoi);
    if (lignes.isEmpty) return 0;

    final produits = {
      for (final p in await _db.select(_db.products).get()) p.id,
    };
    const types = {'entree', 'sortie', 'ajustement'};
    final vus = <String>{};
    final recus = <StockMovementsCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, quoi);
      final produit = l['product_id'];
      final type = l['type'];
      final quantite = _nombreStrict(l['quantity'], '$quoi $id : quantité');
      final referenceType = _texteStrict(
        l['reference_type'],
        '$quoi $id : type de référence',
      );
      final referenceId = _texteStrict(
        l['reference_id'],
        '$quoi $id : référence',
      );
      final motif = _texteStrict(l['reason'], '$quoi $id : motif');
      final date = l['movement_date'] is String
          ? HeureBenin.lire(l['movement_date'])
          : null;
      if (produit is! String || !produits.contains(produit)) {
        throw FormatException(
          "$quoi $id refusé : produit inconnu du poste ($produit).",
        );
      }
      if (type is! String || !types.contains(type)) {
        throw FormatException('$quoi $id refusé : type illisible ($type).');
      }
      if (quantite == null || quantite < 0) {
        throw FormatException(
          '$quoi $id refusé : quantité absente ou négative ($quantite).',
        );
      }
      if (referenceType == null || referenceType.isEmpty) {
        throw FormatException('$quoi $id refusé : type de référence absent.');
      }
      if (date == null) {
        throw FormatException(
          '$quoi $id refusé : date illisible (${l['movement_date']}).',
        );
      }
      recus.add(
        StockMovementsCompanion.insert(
          id: id,
          productId: produit,
          type: type,
          quantity: quantite,
          referenceType: referenceType,
          referenceId: Value(referenceId),
          reason: Value(motif),
          // ⚠️ Heure MURALE du serveur, lue telle quelle (jamais `toLocal()` : le jour du web doit rester le jour).
          movementDate: date,
        ),
      );
    }

    await _db.batch(
      (b) => b.insertAll(
        _db.stockMovements,
        recus,
        mode: InsertMode.insertOrReplace,
      ),
    );

    return recus.length;
  }

  /// Ticket U8 — LIGNES DE RETOUR FOURNISSEUR servies par le tirage (`purchase_returns`).
  ///
  /// Le web compte, à la carte « Écarts / Retours », les LIGNES de retour (`PurchaseReturn::count()` : une ligne
  /// par ligne d'achat retournée) ; le poste comptait des achats. Le serveur sert TOUTES les lignes de retour de
  /// chaque achat servi, au même curseur que lui, et aucune d'un achat non servi.
  ///
  /// ⚠️⚠️ **LA TABLE DU POSTE MÊLE DEUX CHOSES, DISTINGUÉES PAR `device_id`.** Une DEMANDE saisie ici (F0.74 : une
  /// ligne par retour, `id` = identifiant du retour, `device_id` = le poste) et les LIGNES servies par le serveur
  /// (`id` = celui de la ligne serveur, `device_id` = `serveur`, `synced`). Règles :
  ///  - ⚠️⚠️ une demande `pending` ou en `conflict` n'est JAMAIS touchée : ni effacée, ni écrasée (elle repartira,
  ///    ou attend sa relance) ;
  ///  - pour chaque achat servi, les lignes `synced` du poste (lignes serveur précédentes, demande ACQUITTÉE) sont
  ///    REMPLACÉES par celles du serveur : la demande acquittée devient les lignes que le serveur a créées ;
  ///  - un achat `pending` ou en `conflict` sur ce poste n'a rien de touché (le serveur ne le connaît pas) ;
  ///  - STRICT : élément illisible, ligne servie deux fois, ligne d'un achat non servi par ce tirage, identifiant
  ///    d'une demande locale `pending`/`conflict`, date illisible → [FormatException], rien n'est écrit, le
  ///    curseur n'avance pas.
  /// Clé absente (serveur antérieur à U8) : rien n'est touché.
  Future<int> _absorberRetoursDAchat(Object? brutPieces, Object? brut) async {
    if (brut == null) return 0;
    final lignes = _lignes(brut);
    final servis = {
      for (final p in _lignes(brutPieces))
        if (p['id'] is String) p['id'] as String,
    };
    if (servis.isEmpty && lignes.isEmpty) return 0;

    final locales = await _db.select(_db.purchaseReturns).get();
    final demandesEnCours = {
      for (final r in locales)
        if (r.syncStatus != SyncStatus.synced) r.id,
    };

    final parAchat = <String, List<PurchaseReturnsCompanion>>{
      for (final a in servis) a: [],
    };
    final vues = <String>{};
    for (final l in lignes) {
      final id = l['id'];
      final achat = l['purchase_id'];
      final motif = l['reason'];
      final date = _date(l['return_date']);
      if (id is! String ||
          id.length != 36 ||
          achat is! String ||
          (motif != null && motif is! String)) {
        throw FormatException(
          'Ligne de retour $id refusée : élément incomplet ou illisible.',
        );
      }
      if (!vues.add(id)) {
        throw FormatException('Ligne de retour $id refusée : servie deux fois.');
      }
      if (!servis.contains(achat)) {
        throw FormatException(
          "Ligne de retour $id refusée : son achat ($achat) n'est pas servi par ce tirage.",
        );
      }
      if (demandesEnCours.contains(id)) {
        throw FormatException(
          "Ligne de retour $id refusée : elle porte l'identifiant d'une demande de retour "
          'du poste encore en attente ou refusée.',
        );
      }
      if (date == null) {
        throw FormatException(
          'Ligne de retour $id refusée : date du retour illisible.',
        );
      }
      parAchat[achat]!.add(
        PurchaseReturnsCompanion.insert(
          id: id,
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: date,
          purchaseId: achat,
          reason: (motif as String?) ?? '',
          returnDate: date,
        ),
      );
    }

    await _db.transaction(() async {
      // ⚠️ Un achat que le poste tient `pending` ou en `conflict` n'est pas celui du serveur : rien n'y est touché.
      final achatsLocaux = {
        for (final a in await (_db.select(
          _db.purchases,
        )..where((t) => t.syncStatus.equalsValue(SyncStatus.synced).not())).get())
          a.id,
      };
      final remplaces = [
        for (final a in parAchat.keys)
          if (!achatsLocaux.contains(a)) a,
      ];
      if (remplaces.isEmpty) return;
      // ⚠️⚠️ Seules les lignes `synced` sont remplacées : une demande `pending` ou en `conflict` reste.
      await (_db.delete(_db.purchaseReturns)..where(
            (t) =>
                t.purchaseId.isIn(remplaces) &
                t.syncStatus.equalsValue(SyncStatus.synced),
          ))
          .go();
      await _db.batch(
        (b) => b.insertAll(
          _db.purchaseReturns,
          [for (final a in remplaces) ...parAchat[a]!],
          mode: InsertMode.insertOrReplace,
        ),
      );
    });

    return lignes.length;
  }

  /// Corps commun de [_absorberLignesDeVente] et [_absorberLignesDAchat] : valide TOUT avant d'écrire, puis
  /// remplace, dans une transaction, les lignes des pièces servies que le poste tient `synced`.
  Future<int> _remplacerLignesDePieces<T>({
    required String quoi,
    required Object? brutPieces,
    required Object? brut,
    required String cle,
    required Future<Set<String>> Function() protegees,
    required T? Function(
      Map<String, dynamic> l,
      String id,
      String piece,
      String produit,
    )
    lire,
    required Future<void> Function(List<String> pieces, List<T> lignes)
    remplacer,
  }) async {
    if (brut == null) return 0;
    final lignes = _lignes(brut);
    final servies = {
      for (final p in _lignes(brutPieces))
        if (p['id'] is String) p['id'] as String,
    };
    if (servies.isEmpty && lignes.isEmpty) return 0;

    final produits = {
      for (final p in await _db.select(_db.products).get()) p.id,
    };
    final parPiece = <String, List<T>>{for (final p in servies) p: []};
    final vues = <String>{};
    for (final l in lignes) {
      final id = l['id'];
      final piece = l[cle];
      final produit = l['product_id'];
      if (id is! String ||
          id.length != 36 ||
          piece is! String ||
          produit is! String) {
        throw FormatException(
          '$quoi $id refusée : élément incomplet ou illisible.',
        );
      }
      if (!vues.add(id)) {
        throw FormatException('$quoi $id refusée : servie deux fois.');
      }
      if (!servies.contains(piece)) {
        throw FormatException(
          "$quoi $id refusée : sa pièce ($piece) n'est pas servie par ce tirage.",
        );
      }
      if (!produits.contains(produit)) {
        throw FormatException(
          '$quoi $id refusée : produit inconnu du poste ($produit).',
        );
      }
      final ligne = lire(l, id, piece, produit);
      if (ligne == null) {
        throw FormatException(
          '$quoi $id refusée : quantité, prix ou montant illisible.',
        );
      }
      parPiece[piece]!.add(ligne);
    }

    await _db.transaction(() async {
      // ⚠️⚠️ Une pièce `pending` ou en `conflict` sur CE poste garde ses lignes : jamais écrasées.
      final aProteger = await protegees();
      final remplacees = [
        for (final p in parPiece.keys)
          if (!aProteger.contains(p)) p,
      ];
      if (remplacees.isEmpty) return;
      await remplacer(remplacees, [
        for (final p in remplacees) ...parPiece[p]!,
      ]);
    });

    return lignes.length;
  }

  /// Dettes fournisseurs encore dues — référentiel remplacé à chaque tirage.
  ///
  /// ⚠️⚠️ **REMPLACEMENT COMPLET, ET C'EST VOULU.** Le serveur ne sert que ce
  /// qui reste dû : une dette réglée entre deux tirages DISPARAÎT de la charge.
  /// La fusionner la laisserait éternellement à l'ardoise du poste — et la
  /// ferme croirait devoir une somme déjà payée.
  Future<int> _absorberDettes(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.payables).go();

      for (final l in lignes) {
        await _db
            .into(_db.payables)
            .insert(
              PayablesCompanion.insert(
                id: l['id'] as String,
                supplierId: (l['supplier_id'] ?? '') as String,
                supplierName: Value(l['supplier_name'] as String?),
                purchaseId: Value(l['purchase_id'] as String?),
                amount: _reel(l['amount']) ?? 0,
                amountPaid: Value(_reel(l['amount_paid']) ?? 0),
                dueDate: Value(_date(l['due_date'])),
                status: Value(l['status'] as String?),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Bons de commande — référentiel remplacé à chaque tirage.
  Future<int> _absorberBonsCommande(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.purchaseOrders).go();

      for (final l in lignes) {
        await _db
            .into(_db.purchaseOrders)
            .insert(
              PurchaseOrdersCompanion.insert(
                id: l['id'] as String,
                supplierId: Value(l['supplier_id'] as String?),
                supplierName: Value(l['supplier_name'] as String?),
                expectedDeliveryDate: Value(_date(l['expected_delivery_date'])),
                status: Value(l['status'] as String?),
                createdAt: Value(_date(l['created_at'])),
                estimatedTotal: Value(_reel(l['estimated_total']) ?? 0),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Achats — fusion, et JAMAIS un remplacement.
  ///
  /// ⚠️⚠️ **UN ACHAT `pending` NE DOIT PAS ÊTRE ÉCRASÉ PAR LE TIRAGE.** Il
  /// n'existe que sur ce poste : une livraison reçue ce matin, pas encore
  /// envoyée. L'effacer perdrait la saisie ET la marchandise entrée en stock —
  /// c'est la règle déjà posée pour les cycles de reproduction (F0.35).
  ///
  /// Ticket U4 (D-U4) — les lignes descendent à part, avec leur pièce : voir
  /// [_absorberLignesDAchat]. Celles d'un achat local non acquitté restent intactes.
  Future<int> _absorberAchats(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    for (final l in lignes) {
      final id = l['id'] as String;

      final local = await (_db.select(
        _db.purchases,
      )..where((t) => t.id.equals(id))).getSingleOrNull();

      if (local != null && local.syncStatus != SyncStatus.synced) continue;

      final ligne = PurchasesCompanion.insert(
        id: id,
        deviceId: 'serveur',
        updatedAt: _date(l['purchase_date']) ?? DateTime.now(),
        syncStatus: const Value(SyncStatus.synced),
        supplierId: (l['supplier_id'] ?? '') as String,
        supplierName: Value(l['supplier_name'] as String?),
        supplierCategory: Value(l['supplier_category'] as String?),
        paymentMode: (l['payment_mode'] ?? 'especes') as String,
        total: _reel(l['total']) ?? 0,
        hasDebt: Value(_bool(l['has_debt'])),
        purchaseDate: _date(l['purchase_date']) ?? HeureBenin.aujourdhui(),
        // ⚠️ TICKET F0.74 — LE RETOUR EST SERVI PAR LE SERVEUR ET REMPLACE L'ÉTAT LOCAL.
        // `returned_at` et `supplier_credit` ne s'écrivent JAMAIS au poste. Une clé
        // ABSENTE (serveur plus ancien) laisse la colonne telle quelle ; une clé présente
        // mais nulle dit « pas retourné ».
        returnedAt: l.containsKey('returned_at')
            ? Value(_date(l['returned_at']))
            : const Value.absent(),
        supplierCredit: l.containsKey('supplier_credit')
            ? Value(_reel(l['supplier_credit']))
            : const Value.absent(),
      );

      await _db
          .into(_db.purchases)
          .insert(ligne, onConflict: DoUpdate((_) => ligne));
    }

    return lignes.length;
  }

  /// Créance OUVERTE par fournisseur (`supplier_credits`, ticket F0.74) — remplacée en
  /// entier à chaque tirage.
  ///
  /// ⚠️ **LE SERVEUR LA SERT SANS FILTRE `since`, ET SEULEMENT POUR LES FOURNISSEURS > 0** :
  /// un fournisseur absent du tirage n'a plus de créance (tout est remboursé). Une liste
  /// VIDE vide donc la table ; une clé ABSENTE (serveur plus ancien) ne touche à rien. La
  /// table n'a aucune écriture locale : rien de `pending` à protéger (les remboursements en
  /// attente vivent dans `supplier_refunds` et se déduisent à la lecture).
  Future<int> _absorberCreancesFournisseurs(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.supplierCredits).go();

      for (final l in lignes) {
        await _db
            .into(_db.supplierCredits)
            .insertOnConflictUpdate(
              SupplierCreditsCompanion.insert(
                supplierId: l['supplier_id'] as String,
                supplierName: Value(l['supplier_name'] as String?),
                openCredit: _reel(l['open_credit']) ?? 0,
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Relances déjà envoyées — référentiel remplacé à chaque tirage.
  ///
  /// ⚠️⚠️ **CE QUE LEUR ABSENCE COÛTAIT** : une file de relance où le débiteur
  /// contacté ce matin par WhatsApp est présenté exactement comme le voisin que
  /// personne n'a jamais appelé. Le poste faisait rappeler deux fois — la faute
  /// la plus visible pour un client, et la seule qu'il raconte.
  Future<int> _absorberRelances(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.customerReminders).go();

      for (final l in lignes) {
        await _db
            .into(_db.customerReminders)
            .insert(
              CustomerRemindersCompanion.insert(
                id: l['id'] as String,
                customerId: (l['customer_id'] ?? '') as String,
                receivableId: Value(l['receivable_id'] as String?),
                channel: (l['channel'] ?? 'courrier') as String,
                reminderDate: Value(_date(l['reminder_date'])),
                message: Value(l['message'] as String?),
              ),
            );
      }
    });

    return lignes.length;
  }

  /// Protocole prophylactique : référentiel remplacé à chaque tirage.
  /// Comptes de tresorerie — qui peut payer une depense.
  ///
  /// ⚠️ REMPLACEMENT COMPLET, PAS UNE FUSION. Un compte cloture cote serveur
  /// disparait du tirage : le garder proposerait un payeur qui n'existe plus,
  /// et la depense serait rejetee a l'envoi sans que l'animalier comprenne.
  Future<int> _absorberComptesTresorerie(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);

    await _db.transaction(() async {
      await _db.delete(_db.treasuryAccounts).go();
      await _db.batch((b) {
        for (final l in lignes) {
          b.insert(
            _db.treasuryAccounts,
            TreasuryAccountsCompanion.insert(
              id: l['id'] as String,
              label: (l['label'] ?? '') as String,
              accountCode: Value(l['account_code'] as String?),
              type: Value(l['type'] as String?),
              balance: Value(_reel(l['balance']) ?? 0),
            ),
          );
        }
      });
    });

    return lignes.length;
  }

  /// Comptes de charge proposes a la saisie.
  ///
  /// ⚠️ MEME RAISON : la liste vit cote serveur (`Expense::CATEGORIES`) et un
  /// compte retire doit disparaitre du poste, sinon la depense part vers une
  /// imputation refusee.
  Future<int> _absorberCategoriesDepense(Object? brut) async {
    if (brut is! List) return 0;

    final libelles = brut.whereType<String>().toList();

    await _db.transaction(() async {
      await _db.delete(_db.expenseCategories).go();
      await _db.batch((b) {
        for (final libelle in libelles) {
          b.insert(
            _db.expenseCategories,
            ExpenseCategoriesCompanion.insert(label: libelle),
          );
        }
      });
    });

    return libelles.length;
  }

  /// 🔴→✅ Ticket U13 — LES DÉPENSES DU SERVEUR DESCENDENT AU POSTE, avec leur archivage.
  ///
  /// `expenses` n'était au poste qu'une table de SAISIE, jamais tirée : le rapport « Recettes et Dépenses » ne voyait
  /// ni les dépenses saisies au web ou sur un autre poste, et une dépense de CE poste archivée ensuite au web y comptait
  /// encore. Le serveur sert désormais, au curseur (`updated_at`), toute dépense créée, modifiée ou archivée — tout
  /// l'historique, archivées comprises, au tirage complet (un poste en service doit apprendre l'archivage de ses
  /// propres dépenses déjà acquittées).
  ///
  /// ⚠️⚠️ **STRICT**, comme [_absorberInfirmerie] : élément illisible, identifiant invalide ou servi deux fois, date,
  /// libellé, compte de charge, montant (absent, illisible ou négatif), compte payeur ou `is_active` illisibles →
  /// [FormatException] : rien n'est écrit, la page est annulée, le curseur n'avance pas. Lisser — un montant illisible
  /// devenu 0 — fausserait le total du rapport sans que rien ne le dise.
  ///
  /// ⚠️⚠️ **UNE DÉPENSE LOCALE `pending` OU `conflict` N'EST JAMAIS ÉCRASÉE** (saisie ici, pas encore acquittée, ou
  /// refusée et en attente de correction) : le tirage précède toujours l'envoi. Une dépense acquittée (`synced`) prend
  /// la dernière version du serveur (modification ou archivage au web) et garde son `device_id` d'origine.
  /// Clé absente (serveur antérieur à U13, ou table non servie) : rien n'est touché.
  Future<int> _absorberDepenses(Object? brut, [Object? lignesBrutes]) async {
    if (brut == null) return 0;

    const quoi = 'Dépense';
    final lignes = _lignesStrictes(brut, quoi);
    if (lignes.isEmpty) return 0;

    final vus = <String>{};
    final recues = <ExpensesCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, quoi);
      final date = l['expense_date'] is String
          ? HeureBenin.lire(l['expense_date'])
          : null;
      final libelle = _texteStrict(l['label'], '$quoi $id : libellé');
      final categorie = _texteStrict(l['category'], '$quoi $id : compte de charge');
      final montant = _nombreStrict(l['amount'], '$quoi $id : montant');
      final compte = _texteStrict(
        l['treasury_account_id'],
        '$quoi $id : compte de trésorerie',
      );
      final actif = _actifStrict(l, '$quoi $id');
      // Ticket U14 — `status` (`payee` / `en_attente`) et `accounting_entry_id` (nul ou un identifiant). Absent : serveur
      // antérieur à U14 (défauts du schéma, resynchronisation unique quand il les servira). Présent et illisible : refus.
      final statut = l['status'];
      if (!l.containsKey('status')) {
        _depensesSansStatut = true;
      } else if (statut != 'payee' && statut != 'en_attente') {
        throw FormatException('$quoi $id refusée : statut illisible ($statut).');
      }
      final ecriture = l['accounting_entry_id'];
      if (ecriture != null && (ecriture is! String || ecriture.isEmpty)) {
        throw FormatException('$quoi $id refusée : écriture comptable illisible ($ecriture).');
      }
      if (date == null) {
        throw FormatException(
          '$quoi $id refusée : date illisible (${l['expense_date']}).',
        );
      }
      if (libelle == null || compte == null || compte.isEmpty) {
        throw FormatException(
          '$quoi $id refusée : libellé ou compte de trésorerie absent.',
        );
      }
      // Ticket DEP4 — la « catégorie » n'est plus qu'une valeur de compatibilité (compte de la première ligne) : un
      // serveur migré peut la servir vide pour une dépense sans compte connu ; le COMPTE vit sur la ligne.
      if (categorie == null && !l.containsKey('payment_mode')) {
        throw FormatException(
          '$quoi $id refusée : compte de charge absent.',
        );
      }
      if (montant == null || montant < 0) {
        throw FormatException(
          '$quoi $id refusée : montant absent ou négatif ($montant).',
        );
      }
      // Ticket DEP4 — l'en-tête enrichi : mode, centre de coût, fournisseur, bénéficiaire, auteur (tous facultatifs ;
      // présent et illisible : refus). Absent : serveur antérieur à DEP3 (rien n'est touché).
      final mode = _texteStrict(l['payment_mode'], '$quoi $id : mode de paiement');
      final centre = _texteStrict(l['cost_center_id'], '$quoi $id : centre de coût');
      final fournisseur = _texteStrict(l['supplier_id'], '$quoi $id : fournisseur');
      final beneficiaire = _texteStrict(l['beneficiary'], '$quoi $id : bénéficiaire');
      final auteur = _texteStrict(l['created_by'], '$quoi $id : auteur');
      recues.add(
        ExpensesCompanion.insert(
          id: id,
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: _instantTechnique(l['updated_at']) ?? _maintenant(),
          // Une DATE pure, au jour du Bénin (minuit, heure murale) : celle que le web compare (`whereDate`).
          expenseDate: DateTime(date.year, date.month, date.day),
          label: libelle,
          category: categorie ?? '',
          amount: montant,
          treasuryAccountId: compte,
          isActive: Value(actif),
          status: statut is String ? Value(statut) : const Value.absent(),
          accountingEntryId: l.containsKey('accounting_entry_id')
              ? Value(ecriture as String?)
              : const Value.absent(),
          paymentMode: l.containsKey('payment_mode') ? Value(mode) : const Value.absent(),
          costCenterId: l.containsKey('cost_center_id') ? Value(centre) : const Value.absent(),
          supplierId: l.containsKey('supplier_id') ? Value(fournisseur) : const Value.absent(),
          beneficiary: l.containsKey('beneficiary') ? Value(beneficiaire) : const Value.absent(),
          createdBy: l.containsKey('created_by') ? Value(auteur) : const Value.absent(),
          // Un tirage ne dit jamais « refusée » : la saisie acquittée n'a plus de refus de pièce.
          ecritureRefus: const Value(null),
        ),
      );
    }

    // Ticket DEP4 — les lignes servies, STRICTES : liste de maps, identifiant unique, dépense servie dans CE tirage,
    // libellé, compte de charge, rang et montant lisibles. Clé absente (serveur antérieur à DEP3) : rien n'est touché.
    final lignesParDepense = <String, List<ExpenseLinesCompanion>>{};
    if (lignesBrutes != null) {
      const quoiLigne = 'Ligne de dépense';
      final vuesLignes = <String>{};
      for (final l in _lignesStrictes(lignesBrutes, quoiLigne)) {
        final id = _identifiantStrict(l, vuesLignes, quoiLigne);
        final depense = _texteStrict(l['expense_id'], '$quoiLigne $id : dépense');
        final libelle = _texteStrict(l['label'], '$quoiLigne $id : libellé');
        final compte = _texteStrict(l['charge_account_id'], '$quoiLigne $id : compte de charge');
        final montant = _nombreStrict(l['amount'], '$quoiLigne $id : montant');
        final rang = _nombreStrict(l['position'], '$quoiLigne $id : rang');
        if (depense == null || !vus.contains(depense)) {
          throw FormatException('$quoiLigne $id refusée : sa dépense n\'est pas servie avec elle ($depense).');
        }
        if (libelle == null || compte == null || compte.isEmpty) {
          throw FormatException('$quoiLigne $id refusée : libellé ou compte de charge absent.');
        }
        if (montant == null || montant < 0) {
          throw FormatException('$quoiLigne $id refusée : montant absent ou négatif ($montant).');
        }
        lignesParDepense.putIfAbsent(depense, () => []).add(
          ExpenseLinesCompanion.insert(
            id: id,
            expenseId: depense,
            position: Value(rang?.round() ?? 0),
            label: libelle,
            chargeAccountId: compte,
            amount: montant,
          ),
        );
      }
    }

    await _db.transaction(() async {
      final locales = {
        for (final d in await (_db.select(
          _db.expenses,
        )..where((t) => t.id.isIn(vus))).get())
          d.id: d.syncStatus,
      };
      for (final d in recues) {
        final statut = locales[d.id.value];
        if (statut != null && statut != SyncStatus.synced) continue;
        // Une dépense acquittée de CE poste garde son `device_id` (l'origine de la saisie).
        await _db
            .into(_db.expenses)
            .insert(
              d,
              onConflict: DoUpdate(
                (_) => d.copyWith(deviceId: const Value.absent()),
              ),
            );
        // Les lignes servies REMPLACENT celles que le poste tient : une ligne retirée ici disparaît là-bas.
        if (lignesBrutes != null) {
          await (_db.delete(_db.expenseLines)..where((l) => l.expenseId.equals(d.id.value))).go();
          for (final ligne in lignesParDepense[d.id.value] ?? const <ExpenseLinesCompanion>[]) {
            await _db.into(_db.expenseLines).insert(ligne, mode: InsertMode.insertOrReplace);
          }
        }
      }
    });

    return recues.length;
  }

  /// Ticket DEP4 — centres de coût (filières) servis par le serveur : référentiel, LE SERVEUR GAGNE (jamais écrit au
  /// poste). Strict : un élément illisible refuse le lot. Clé absente (compte sans `view-achats` / `view-comptabilite`,
  /// ou serveur antérieur) : rien n'est touché.
  Future<int> _absorberCentresDeCout(Object? brut) async {
    if (brut == null) return 0;

    const quoi = 'Centre de coût';
    final lignes = _lignesStrictes(brut, quoi);
    final vus = <String>{};
    final recus = <CostCentersCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, quoi);
      final libelle = _texteStrict(l['label'], '$quoi $id : libellé');
      final type = _texteStrict(l['type'], '$quoi $id : type');
      if (libelle == null || type == null) {
        throw FormatException('$quoi $id refusé : libellé ou type absent.');
      }
      recus.add(
        CostCentersCompanion.insert(
          id: id,
          label: libelle,
          type: type,
          parentSpeciesId: Value(_texteStrict(l['parent_species_id'], '$quoi $id : espèce')),
          isActive: Value(_actifStrict(l, '$quoi $id')),
        ),
      );
    }

    await _db.transaction(() async {
      await _db.delete(_db.costCenters).go();
      await _db.batch((b) => b.insertAll(_db.costCenters, recus));
    });

    return recus.length;
  }

  /// 🔴→✅ Tickets AV1 / AV2 — LES AVOIRS CLIENTS DESCENDENT AU POSTE (écran « Retours et Avoirs »).
  ///
  /// Table MIXTE (comme les dépenses) : le poste y saisit des demandes de retour (`pending`) et y lit les avoirs du web et
  /// des autres postes. Le serveur attribue le numéro `AV-AAAA-NNN` : une demande acquittée le reçoit ici, au tirage qui
  /// suit.
  ///
  /// ⚠️⚠️ **UNE DEMANDE LOCALE `pending` OU `conflict` N'EST JAMAIS ÉCRASÉE** (saisie ici, pas encore acquittée, ou refusée
  /// et en attente de correction) : le tirage précède toujours l'envoi. Un avoir acquitté (`synced`) prend la dernière
  /// version du serveur (numéro, statut « traité » posé au web) et garde son `device_id` d'origine.
  ///
  /// ⚠️⚠️ **STRICT** : identifiant invalide ou servi deux fois, vente ou produit inconnu du poste, montant absent ou
  /// négatif, quantité négative, décision ou statut illisible, date illisible → [FormatException], rien n'est écrit, le
  /// curseur n'avance pas. Clé absente (serveur antérieur, ou table non servie à ce compte) : rien n'est touché.
  Future<int> _absorberAvoirs(Object? brut) async {
    if (brut == null) return 0;

    const quoi = 'Avoir client';
    final lignes = _lignesStrictes(brut, quoi);
    if (lignes.isEmpty) return 0;

    final ventes = {for (final v in await _db.select(_db.sales).get()) v.id};
    final produits = {for (final p in await _db.select(_db.products).get()) p.id};
    final vus = <String>{};
    final recus = <CreditNotesCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, quoi);
      final vente = l['sale_id'];
      final produit = l['product_id'];
      final numero = _texteStrict(l['credit_note_number'], '$quoi $id : numéro');
      final quantite = _nombreStrict(l['qty'], '$quoi $id : quantité');
      final montant = _nombreStrict(l['amount'], '$quoi $id : montant');
      final motif = _texteStrict(l['reason'], '$quoi $id : motif');
      final decision = l['decision'];
      final notes = _texteStrict(l['inspection_notes'], '$quoi $id : notes d\'inspection');
      final statut = l['status'];
      final date = l['created_at'] is String ? HeureBenin.lire(l['created_at']) : null;
      if (vente is! String || !ventes.contains(vente)) {
        throw FormatException('$quoi $id refusé : vente inconnue du poste ($vente).');
      }
      if (produit is! String || !produits.contains(produit)) {
        throw FormatException('$quoi $id refusé : produit inconnu du poste ($produit).');
      }
      if (montant == null || montant < 0) {
        throw FormatException('$quoi $id refusé : montant absent ou négatif ($montant).');
      }
      if (quantite != null && quantite < 0) {
        throw FormatException('$quoi $id refusé : quantité négative ($quantite).');
      }
      if (decision != null && decision != 'reintegre' && decision != 'reforme') {
        throw FormatException('$quoi $id refusé : décision illisible ($decision).');
      }
      if (statut != 'en_attente' && statut != 'traite') {
        throw FormatException('$quoi $id refusé : statut illisible ($statut).');
      }
      if (date == null) {
        throw FormatException('$quoi $id refusé : date illisible (${l['created_at']}).');
      }
      recus.add(
        CreditNotesCompanion.insert(
          id: id,
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: _instantTechnique(l['updated_at']) ?? _maintenant(),
          saleId: vente,
          productId: produit,
          creditNoteNumber: Value(numero),
          qty: Value(quantite),
          amount: montant,
          reason: Value(motif),
          decision: Value(decision as String?),
          inspectionNotes: Value(notes),
          status: Value(statut as String),
          // Heure MURALE du serveur, lue telle quelle : le jour du web doit rester le jour.
          createdAt: date,
        ),
      );
    }

    await _db.transaction(() async {
      final locales = {
        for (final a in await (_db.select(
          _db.creditNotes,
        )..where((t) => t.id.isIn(vus))).get())
          a.id: a.syncStatus,
      };
      for (final a in recus) {
        final statut = locales[a.id.value];
        if (statut != null && statut != SyncStatus.synced) continue;
        // Un avoir acquitté de CE poste garde son `device_id` (l'origine de la saisie).
        await _db
            .into(_db.creditNotes)
            .insert(a, onConflict: DoUpdate((_) => a.copyWith(deviceId: const Value.absent())));
      }
    });

    return recus.length;
  }

  /// 🔴→✅ Ticket DEV — LES DEVIS DU SERVEUR DESCENDENT AU POSTE (table mixte : saisis ici ET tirés).
  ///
  /// Le serveur sert tout devis créé, modifié, avancé dans son cycle ou archivé au web ou sur un autre poste, au curseur
  /// (`updated_at`), archivés compris (`is_active`) : le numéro `DEV-AAAA-NNN` (que le poste n'invente jamais), le client,
  /// la description, le montant HT, la TVA, la validité, la date, la note et le statut.
  ///
  /// ⚠️⚠️ **STRICT**, comme [_absorberDepenses] : élément illisible, identifiant invalide ou servi deux fois, numéro,
  /// client, description, montant (absent, illisible ou négatif), TVA, validité, date, statut ou `is_active` illisibles →
  /// [FormatException] : rien n'est écrit, la page est annulée, le curseur n'avance pas. Lisser — un montant illisible
  /// devenu 0 — fausserait « Valeur Totale » sans que rien ne le dise.
  ///
  /// ⚠️⚠️ **UN DEVIS LOCAL `pending` OU `conflict` N'EST JAMAIS ÉCRASÉ** (saisi ou avancé ici, pas encore acquitté, ou refusé
  /// et en attente de correction) : le tirage précède toujours l'envoi. Un devis acquitté (`synced`) prend la dernière
  /// version du serveur et garde son `device_id` d'origine. Clé absente (table non servie à ce compte, serveur antérieur à
  /// DEV) : rien n'est touché.
  Future<int> _absorberDevis(Object? brut) async {
    if (brut == null) return 0;

    const quoi = 'Devis';
    final lignes = _lignesStrictes(brut, quoi);
    if (lignes.isEmpty) return 0;

    final vus = <String>{};
    final recus = <QuotesCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, quoi);
      final numero = _texteStrict(l['quote_number'], '$quoi $id : numéro');
      final client = _texteStrict(l['customer_id'], '$quoi $id : client');
      final description = _texteStrict(
        l['articles_description'],
        '$quoi $id : description',
      );
      final montant = _nombreStrict(l['amount'], '$quoi $id : montant');
      final tva = _nombreStrict(l['tva_rate'], '$quoi $id : TVA');
      final validite = _nombreStrict(l['validity_days'], '$quoi $id : validité');
      final date = l['quote_date'] is String ? HeureBenin.lire(l['quote_date']) : null;
      final remarque = _texteStrict(l['note'], '$quoi $id : note');
      // Ticket DEV3 — le lien vers la facture et son numéro : `null` (ou clés absentes d'un serveur antérieur) tant que le
      // devis n'est pas converti ; un texte sinon, jamais autre chose.
      final factureId = _texteStrict(l['converted_sale_id'], '$quoi $id : facture');
      final factureNumero = _texteStrict(l['invoice_number'], '$quoi $id : numéro de facture');
      final statut = l['status'];
      final actif = _actifStrict(l, '$quoi $id');
      if (date == null) {
        throw FormatException('$quoi $id refusé : date illisible (${l['quote_date']}).');
      }
      if (client == null || client.isEmpty || description == null) {
        throw FormatException('$quoi $id refusé : client ou description absent.');
      }
      if (montant == null || montant < 0) {
        throw FormatException('$quoi $id refusé : montant absent ou négatif ($montant).');
      }
      if (tva == null || tva < 0 || tva > 100) {
        throw FormatException('$quoi $id refusé : TVA absente ou hors de 0 à 100 ($tva).');
      }
      if (validite == null || validite < 1 || validite != validite.roundToDouble()) {
        throw FormatException('$quoi $id refusé : validité absente ou illisible ($validite).');
      }
      if (statut is! String || !const ['brouillon', 'envoye', 'accepte', 'refuse', 'facture'].contains(statut)) {
        throw FormatException('$quoi $id refusé : statut illisible ($statut).');
      }
      recus.add(
        QuotesCompanion.insert(
          id: id,
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: _instantTechnique(l['updated_at']) ?? _maintenant(),
          quoteNumber: Value(numero),
          customerId: client,
          articlesDescription: description,
          amount: montant,
          tvaRate: Value(tva),
          validityDays: Value(validite.round()),
          // Une DATE pure, au jour du Bénin (minuit, heure murale) : celle que le web compare (`whereMonth`).
          quoteDate: DateTime(date.year, date.month, date.day),
          note: Value(remarque),
          status: Value(statut),
          isActive: Value(actif),
          convertedSaleId: Value(factureId),
          invoiceNumber: Value(factureNumero),
        ),
      );
    }

    await _db.transaction(() async {
      final locales = {
        for (final d in await (_db.select(
          _db.quotes,
        )..where((t) => t.id.isIn(vus))).get())
          d.id: d.syncStatus,
      };
      for (final d in recus) {
        final statut = locales[d.id.value];
        if (statut != null && statut != SyncStatus.synced) continue;
        // Un devis acquitté de CE poste garde son `device_id` (l'origine de la saisie).
        await _db
            .into(_db.quotes)
            .insert(
              d,
              onConflict: DoUpdate(
                (_) => d.copyWith(deviceId: const Value.absent()),
              ),
            );
      }
    });

    return recus.length;
  }

  /// 🔴→✅ Ticket U13 — LA PAIE RÉGLÉE DESCEND AU POSTE (lecture seule), pour le rapport « Recettes et Dépenses ».
  ///
  /// Le serveur ne sert que ce que `RecettesDepenses::depensesRows()` lit : l'instant du règlement (`created_at`, heure
  /// murale du serveur), le nom de l'employé et le net versé — rien d'autre sur la paie (S3). Servie au curseur ; un
  /// bulletin ne se modifie ni ne s'archive au web (il disparaît seulement à la réinitialisation, purgée ici à part).
  ///
  /// ⚠️⚠️ **STRICT** : identifiant invalide ou servi deux fois, net absent, illisible ou négatif, instant illisible,
  /// nom qui n'est pas un texte → [FormatException], rien n'est écrit. Aucune écriture locale à protéger : la table ne
  /// s'écrit jamais au poste.
  Future<int> _absorberPaie(Object? brut) async {
    if (brut == null) return 0;

    const quoi = 'Bulletin de paie';
    final lignes = _lignesStrictes(brut, quoi);
    if (lignes.isEmpty) return 0;

    final vus = <String>{};
    final recus = <PayslipsCompanion>[];
    for (final l in lignes) {
      final id = _identifiantStrict(l, vus, quoi);
      final net = _nombreStrict(l['net_salary'], '$quoi $id : net versé');
      final nom = _texteStrict(l['employee_name'], '$quoi $id : employé');
      final instant = l['created_at'] is String
          ? HeureBenin.lire(l['created_at'])
          : null;
      if (net == null || net < 0) {
        throw FormatException(
          '$quoi $id refusé : net versé absent ou négatif ($net).',
        );
      }
      if (instant == null) {
        throw FormatException(
          '$quoi $id refusé : date de règlement illisible (${l['created_at']}).',
        );
      }
      recus.add(
        PayslipsCompanion.insert(
          id: id,
          employeeName: Value(nom),
          netSalary: net,
          // ⚠️ Heure MURALE du serveur, lue telle quelle : le jour du web (`toDateString()`) doit rester le jour.
          createdAt: instant,
        ),
      );
    }

    await _db.batch(
      (b) => b.insertAll(_db.payslips, recus, mode: InsertMode.insertOrReplace),
    );

    return recus.length;
  }

  /// Registre des soins déjà administrés.
  ///
  /// ⚠️ CE QUI VIENT DU SERVEUR EST MARQUÉ `synced` : le renvoyer le ferait
  /// rejouer par l'Action serveur, qui recréerait une période de rémanence —
  /// la bande serait bloquée deux fois plus longtemps qu'elle ne doit l'être.
  ///
  /// ⚠️ `withdrawalDays` RESTE À ZÉRO pour un soin reçu : le délai a déjà été
  /// consommé par le serveur au moment de sa création, il n'est pas une donnée
  /// du registre.
  ///
  /// Ticket U3 (décision client D-U3 du 19/10/2026) — `is_active` DESCEND : un soin archivé au web (ou sur un
  /// autre poste) est servi au tirage incrémental avec `is_active = false` et quitte ici le registre et les
  /// calculs. Absent (serveur antérieur à U3) : actif ; illisible : [FormatException], rien n'est écrit.
  /// ⚠️⚠️ **UNE LIGNE LOCALE `pending` OU `conflict` N'EST JAMAIS ÉCRASÉE** (soin saisi ou archivé ici, pas encore
  /// acquitté) : l'upsert aveugle d'avant aurait annulé un archivage fait hors ligne — le tirage précède toujours
  /// l'envoi.
  Future<int> _absorberSoins(Object? brut) async {
    if (brut == null) return 0;

    final lignes = _lignes(brut);
    final actifs = [
      for (final l in lignes) _actifStrict(l, 'Soin ${l['id']}'),
    ];
    final protegees = {
      for (final s in await (_db.select(
        _db.veterinaryRecords,
      )..where((t) => t.syncStatus.equalsValue(SyncStatus.synced).not())).get())
        s.id,
    };

    await _db.batch((b) {
      for (final (i, l) in lignes.indexed) {
        if (protegees.contains(l['id'])) continue;
        final ligne = VeterinaryRecordsCompanion.insert(
          id: l['id'] as String,
          deviceId: (l['device_id'] ?? 'serveur') as String,
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: _instantTechnique(l['updated_at']) ?? DateTime.now(),
          lotId: (l['lot_id'] ?? '') as String,
          actionType: (l['action_type'] ?? '') as String,
          productUsed: Value(l['product_used'] as String?),
          dose: Value(l['dose'] as String?),
          vetName: Value(l['vet_name'] as String?),
          symptomes: Value(l['symptomes'] as String?),
          cost: Value(_reel(l['cost'])),
          recordDate: _date(l['record_date']) ?? HeureBenin.aujourdhui(),
          isActive: Value(actifs[i]),
        );
        b.insert(
          _db.veterinaryRecords,
          ligne,
          onConflict: DoUpdate((_) => ligne),
        );
      }
    });

    return lignes.length;
  }

  /// Envoie la file d'attente et n'acquitte QUE ce que le serveur a accepté.
  Future<(int, int, List<String>)> _pousser() async {
    // ⚠️ F0.89 — LES FICHES PARTENT DANS L'ORDRE DES JOURS. Le serveur recalcule l'effectif de
    // chaque fiche reçue à partir de la veille QU'IL CONNAÎT, dans l'ordre du tableau : une vente
    // antérieure crée sa fiche APRÈS celle du jour (ordre d'insertion inverse), et l'envoyer en
    // premier ferait partir le jour suivant d'une veille périmée.
    final fiches =
        await (_db.select(_db.livestockDailyEntries)
              ..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))
              ..orderBy([
                (t) => OrderingTerm(expression: t.entryDate),
                (t) => OrderingTerm(expression: t.lotId),
              ]))
            .get();

    // Ticket BS1 — bandes créées, modifiées ou archivées au poste : le serveur les rejoue (`SaisieBandeAction`) AVANT
    // les fiches et les transferts du même envoi (la fiche d'une bande créée à l'instant).
    final bandes = await (_db.select(
      _db.livestockLots,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    // Ticket BS3 — reproducteurs nominatifs enregistrés, modifiés ou sortis au poste (`SaisieReproducteurAction`).
    final sujets = await (_db.select(
      _db.animals,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final ventes = await (_db.select(
      _db.sales,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final ajustements = await (_db.select(
      _db.stockAdjustments,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final soins = await (_db.select(
      _db.veterinaryRecords,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final depenses = await (_db.select(
      _db.expenses,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    // Ticket DEV — devis saisis, avancés ou archivés au poste.
    final devis = await (_db.select(
      _db.quotes,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final saillies = await (_db.select(
      _db.livestockReproductionEvents,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final achats = await (_db.select(
      _db.purchases,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final pointages = await (_db.select(
      _db.attendanceRecords,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final produits = await (_db.select(
      _db.products,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final fournisseurs = await (_db.select(
      _db.suppliers,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final reglements = await (_db.select(
      _db.supplierPayments,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final clients = await (_db.select(
      _db.customers,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final courriers = await (_db.select(
      _db.mails,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final archives = await (_db.select(
      _db.archivedDocuments,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final documents = await (_db.select(
      _db.administrativeDocuments,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final avances = await (_db.select(
      _db.customerAdvances,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final imputations = await (_db.select(
      _db.advanceImputations,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final retours = await (_db.select(
      _db.purchaseReturns,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final remboursements = await (_db.select(
      _db.supplierRefunds,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    // Tickets AV1 / AV2 — demandes de retour client et « marquer comme traité » : le serveur fait les effets.
    final avoirs = await (_db.select(
      _db.creditNotes,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    // Ticket 15.46 — transferts créés ou annulés au poste : le serveur les rejoue.
    final transferts = await (_db.select(
      _db.livestockTransfers,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    // Ticket H8b — infirmerie et interventions planifiées saisies au poste.
    final infirmerie = await (_db.select(
      _db.infirmaryRecords,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final interventions = await (_db.select(
      _db.veterinaryCalendarEvents,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    // Ticket H9b (D-H9) — Paramètres Élevage modifiés au poste (`RecordParametresElevageFromDeviceAction`).
    final rations = await (_db.select(
      _db.feedRationStandards,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final echeances = await (_db.select(
      _db.prophylaxisScheduleStandards,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final provendes = await (_db.select(
      _db.feedTypes,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final numerotations = await (_db.select(
      _db.elevageNumberingSettings,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    final entreprise = await (_db.select(
      _db.companySettings,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    // Ticket MOD1 — modules actifs basculés au poste (`RecordModulesConfigFromDeviceAction`, droit `manage-modules`).
    final modules = await (_db.select(
      _db.modulesConfig,
    )..where((t) => t.syncStatus.equalsValue(SyncStatus.pending))).get();

    _financiersAcquittes = 0;
    _ventesDeBetailAcquittees = 0;
    _courriersAcquittes = 0;
    _archivesAcquittees = 0;
    _documentsAcquittes = 0;

    if (fiches.isEmpty &&
        bandes.isEmpty &&
        sujets.isEmpty &&
        transferts.isEmpty &&
        infirmerie.isEmpty &&
        interventions.isEmpty &&
        rations.isEmpty &&
        echeances.isEmpty &&
        provendes.isEmpty &&
        numerotations.isEmpty &&
        entreprise.isEmpty &&
        modules.isEmpty &&
        courriers.isEmpty &&
        archives.isEmpty &&
        documents.isEmpty &&
        retours.isEmpty &&
        remboursements.isEmpty &&
        avoirs.isEmpty &&
        avances.isEmpty &&
        imputations.isEmpty &&
        produits.isEmpty &&
        reglements.isEmpty &&
        fournisseurs.isEmpty &&
        clients.isEmpty &&
        ventes.isEmpty &&
        ajustements.isEmpty &&
        soins.isEmpty &&
        depenses.isEmpty &&
        devis.isEmpty &&
        saillies.isEmpty &&
        achats.isEmpty &&
        pointages.isEmpty) {
      return (0, 0, <String>[]);
    }

    final lignesDAchat = <String, List<PurchaseLine>>{};
    for (final a in achats) {
      lignesDAchat[a.id] = await (_db.select(
        _db.purchaseLines,
      )..where((t) => t.purchaseId.equals(a.id))).get();
    }

    final lignesDeVente = <String, List<SaleLine>>{};
    for (final v in ventes) {
      lignesDeVente[v.id] = await (_db.select(
        _db.saleLines,
      )..where((t) => t.saleId.equals(v.id))).get();
    }

    // Ticket DEP4 — les lignes de chaque dépense en attente, dans l'ordre : elles partent DANS le document de l'en-tête.
    final lignesDeDepense = <String, List<ExpenseLine>>{};
    for (final d in depenses) {
      lignesDeDepense[d.id] =
          await (_db.select(_db.expenseLines)
                ..where((l) => l.expenseId.equals(d.id))
                ..orderBy([(l) => OrderingTerm(expression: l.position), (l) => OrderingTerm(expression: l.id)]))
              .get();
    }

    // ⚠️ F0.90 — fiches COMPLÈTES (modifiées au poste) et fiches D'IDENTITÉ (ventes en file dont la
    // fiche est déjà synchronisée) partent ensemble, triées par jour puis bande comme ci-dessus.
    // Une fiche `pending` n'est jamais aussi « d'identité » (filtre `synced`) : pas de doublon.
    final identites = await _fichesDIdentite(ventes, lignesDeVente);
    final fichesEnvoyees =
        [
          for (final f in fiches) (f, false),
          for (final f in identites) (f, true),
        ]..sort((a, b) {
          final jour = a.$1.entryDate.compareTo(b.$1.entryDate);
          return jour != 0 ? jour : a.$1.lotId.compareTo(b.$1.lotId);
        });

    // ⚠️ F0.95 — LE DÉPART NE PART QU'AVEC LA FICHE TÊTE DE CHAÎNE (D4) : la première fiche locale
    // de la bande au départ COMPLET. Un départ resté sur une fiche postérieure (le serveur l'ignore
    // et le signale) ferait refuser, à l'envoi, une simple correction de cette fiche (« effectif
    // de départ déjà fixé »).
    final tetes = <String>{};
    for (final lot in {for (final f in fiches) f.lotId}) {
      final tete =
          await (_db.select(_db.livestockDailyEntries)
                ..where(
                  (t) => Expression.and([
                    t.lotId.equals(lot),
                    t.catDepartRepro.isNotNull(),
                    t.catDepartSevre.isNotNull(),
                    t.catDepartJeune.isNotNull(),
                  ]),
                )
                ..orderBy([(t) => OrderingTerm(expression: t.entryDate)])
                ..limit(1))
              .getSingleOrNull();
      if (tete != null) tetes.add(tete.id);
    }

    final (corps, echecDeLot, pileDeLot) = await _envoyerParLots({
        'device_id': _deviceId,
        // Ticket 15.50 — la réinitialisation que ce poste a appliquée (absente : aucune).
        'data_reset_at': ?await _lireReglage(cleReinitialisation),
        // Ticket BS1 — traitées par le serveur AVANT les fiches (voir `ordreDuServeur`).
        'livestock_lots': bandes.map(_bandeEnJson).toList(),
        // Ticket BS3 — traités par le serveur APRÈS leurs bandes (le sujet d'une bande créée à l'instant).
        'animals': sujets.map(_sujetEnJson).toList(),
        'livestock_daily_entries': [
          for (final (f, identite) in fichesEnvoyees)
            identite
                ? _ficheIdentiteEnJson(f)
                : _ficheEnJson(f, tete: tetes.contains(f.id)),
        ],
        // Ticket 15.46 — traités par le serveur APRÈS les fiches du même envoi.
        'livestock_transfers': transferts.map(_transfertEnJson).toList(),
        // Ticket H8b — `pushInfirmerie` / `pushCalendrierVeterinaire` (manage-elevage).
        'infirmary_records': infirmerie.map(_infirmerieEnJson).toList(),
        'veterinary_calendar_events': interventions
            .map(_interventionEnJson)
            .toList(),
        // Ticket H9b — clés et formats de `RecordParametresElevageFromDeviceAction` (droit `manage-elevage`).
        // ⚠️ Une clé VIDE n'est pas envoyée : le serveur répondrait par une liste vide, sans objet.
        if (rations.isNotEmpty)
          'feed_ration_standards': rations.map(_rationEnJson).toList(),
        if (echeances.isNotEmpty)
          'prophylaxis_schedule_standards': echeances
              .map(_echeanceEnJson)
              .toList(),
        if (provendes.isNotEmpty)
          'feed_types': provendes.map(_provendeEnJson).toList(),
        if (numerotations.isNotEmpty)
          'elevage_numbering': numerotations.map(_numerotationEnJson).toList(),
        if (entreprise.isNotEmpty)
          'company_settings': entreprise.map(_rappelSoinsEnJson).toList(),
        // Ticket MOD1 — UNE LIGNE PAR ESPÈCE, valeur explicite (jamais une bascule) ; acquittée sous le code de l'espèce.
        if (modules.isNotEmpty)
          'modules_config': modules.map(_moduleEnJson).toList(),
        'sales': ventes
            .map((v) => _venteEnJson(v, lignesDeVente[v.id] ?? const []))
            .toList(),
        // Ticket AV1 — le serveur traite les retours APRÈS les ventes du même envoi. ⚠️ JAMAIS de `stock_adjustments` ni
        // d'écriture pour un avoir : le serveur réintègre le stock et passe l'écriture inverse (`AvoirClientService`).
        'credit_notes': avoirs.map(_avoirEnJson).toList(),
        'stock_adjustments': ajustements.map(_ajustementEnJson).toList(),
        'veterinary_records': soins.map(_soinEnJson).toList(),
        'expenses': depenses.map((d) => _depenseEnJson(d, lignesDeDepense[d.id] ?? const [])).toList(),
        // Ticket DEV — `pushQuotes` (manage-ventes) : le numéro `DEV-AAAA-NNN` ne part JAMAIS, le serveur l'attribue.
        'quotes': devis.map(_devisEnJson).toList(),
        // Ticket DEV3 — la DEMANDE de conversion (`pushQuoteConversions`, après `quotes`) : l'UUID du devis et l'instant
        // du clic, heure du Bénin comme `sold_at`. Le serveur crée la facture, la numérote et en rend le lien.
        if (devis.any((d) => d.conversionRequestedAt != null && d.convertedSaleId == null))
          'quote_conversions': [
            for (final d in devis)
              if (d.conversionRequestedAt != null && d.convertedSaleId == null)
                {'id': d.id, 'requested_at': _instant(d.conversionRequestedAt!)},
          ],
        'livestock_reproduction_events': saillies.map(_saillieEnJson).toList(),
        'purchases': achats
            .map((a) => _achatEnJson(a, lignesDAchat[a.id] ?? const []))
            .toList(),
        'attendance_records': pointages.map(_pointageEnJson).toList(),
        'products': produits.map(_produitEnJson).toList(),
        'supplier_payments': reglements.map(_reglementEnJson).toList(),
        // ⚠️ TICKET F0.74 — le serveur traite : achats → règlements → RETOURS →
        // REMBOURSEMENTS → … → ajustements de stock, quel que soit l'ordre des clés. Un
        // retour part dans le MÊME envoi que son achat (ou après lui) ; ⚠️ JAMAIS de
        // `stock_adjustments` pour un retour : le serveur décrémente et rejette toute
        // sortie qui le désigne.
        'purchase_returns': retours.map(_retourEnJson).toList(),
        'supplier_refunds': remboursements.map(_remboursementEnJson).toList(),
        'suppliers': fournisseurs.map(_fournisseurEnJson).toList(),
        'customers': clients.map(_clientEnJson).toList(),
        // ⚠️ F0.78 — la référence `CR-AAAA-NNN` ne part JAMAIS : le serveur l'attribue.
        'mails': courriers.map(_courrierEnJson).toList(),
        // ⚠️ F0.79 — retirer = {id, is_active:false} seulement ; aucun statut ne part.
        'archived_documents': archives.map(_archiveEnJson).toList(),
        // ⚠️ F0.80 — retirer = {id, is_active:false} seulement.
        'administrative_documents': documents.map(_documentEnJson).toList(),
        // ⚠️ Le serveur traite les avances AVANT les imputations (une imputation peut
        // viser l'avance du même envoi) : l'ordre des clés n'y change rien, mais
        // les deux voyagent ensemble dans le même paquet, jamais séparés.
        'customer_advances': avances.map(_avanceEnJson).toList(),
        'advance_imputations': imputations.map(_imputationEnJson).toList(),
      });

    var accepte = 0;
    var rejete = 0;
    final motifs = <String>[];

    // 🔴→✅ TICKET S-T9 — N'ACQUITTE QUE LA VERSION PARTIE (même règle que les courriers, l'infirmerie et les
    // barèmes). Mesuré par l'essai à plusieurs postes : l'animalier corrige sa fiche (un mort de plus) PENDANT
    // l'envoi de la version précédente ; l'accusé de cette version marquait la fiche `synced`, et la correction
    // ne partait jamais — sans erreur, le serveur gardait un mort de moins. La fiche est comparée telle qu'elle est
    // partie (sa SAISIE, pas `updated_at`, stocké à la seconde) : changée entre-temps, elle reste `pending` et
    // repart. Une vente répercutée entre-temps ne compte pas : le serveur ne reprend plus la vente d'une fiche qu'il
    // connaît, la vente l'y inscrit elle-même (sinon la fiche du comptoir repartirait avec des morts périmés). Les
    // fiches d'identité (F0.90) sont déjà `synced` : rien à marquer.
    final fichesParties = {
      for (final (f, identite) in fichesEnvoyees)
        if (!identite) f.id: _saisieDeFiche(f, tete: tetes.contains(f.id)),
    };
    accepte += await _acquitter(
      'livestock_daily_entries',
      corps['livestock_daily_entries'],
      (ids, statut) async {
        for (final id in ids) {
          final partie = fichesParties[id];
          if (partie == null) continue;
          final actuelle = await (_db.select(
            _db.livestockDailyEntries,
          )..where((t) => t.id.equals(id))).getSingleOrNull();
          if (actuelle == null ||
              actuelle.syncStatus != SyncStatus.pending ||
              _saisieDeFiche(actuelle, tete: tetes.contains(id)) != partie) {
            continue;
          }
          await (_db.update(_db.livestockDailyEntries)..where((t) => t.id.equals(id)))
              .write(LivestockDailyEntriesCompanion(syncStatus: Value(statut)));
        }
      },
      motifs,
      (n) => rejete += n,
    );

    // Ticket BS1 — n'acquitte que la VERSION partie (instant de saisie inchangé, voir [_marquerSiInchangee]) : une bande
    // corrigée PENDANT l'envoi de sa version précédente reste `pending` et repart. La correction d'effectif partie est
    // vidée à l'acquittement (sinon elle repartirait avec une bande modifiée plus tard).
    accepte += await _acquitter(
      'livestock_lots',
      corps['livestock_lots'],
      (ids, statut) => _marquerSiInchangee(
        [for (final b in bandes) (b.id, b.updatedAt)],
        ids,
        (id, saisie) =>
            (_db.update(_db.livestockLots)..where(
                  (t) => Expression.and([
                    t.id.equals(id),
                    saisie == null ? t.updatedAt.isNull() : t.updatedAt.equals(saisie),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(
                  LivestockLotsCompanion(
                    syncStatus: Value(statut),
                    effectifCorrige: statut == SyncStatus.synced ? const Value(null) : const Value.absent(),
                    restauree: statut == SyncStatus.synced ? const Value(false) : const Value.absent(),
                  ),
                ),
      ),
      motifs,
      (n) => rejete += n,
    );

    // Ticket BS3 — n'acquitte que la VERSION partie (instant de saisie inchangé) : un sujet corrigé PENDANT l'envoi de sa
    // version précédente reste `pending` et repart.
    accepte += await _acquitter(
      'animals',
      corps['animals'],
      (ids, statut) => _marquerSiInchangee(
        [for (final a in sujets) (a.id, a.updatedAt)],
        ids,
        (id, saisie) =>
            (_db.update(_db.animals)..where(
                  (t) => Expression.and([
                    t.id.equals(id),
                    saisie == null ? t.updatedAt.isNull() : t.updatedAt.equals(saisie),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(AnimalsCompanion(syncStatus: Value(statut))),
      ),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'livestock_transfers',
      corps['livestock_transfers'],
      (ids, statut) =>
          (_db.update(_db.livestockTransfers)..where((t) => t.id.isIn(ids)))
              .write(LivestockTransfersCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    // Ticket H8b — n'acquitte que la VERSION partie (voir [_marquerParStatut]).
    accepte += await _acquitter(
      'infirmary_records',
      corps['infirmary_records'],
      (ids, statut) => _marquerParStatut(
        [for (final e in infirmerie) (e.id, e.status)],
        ids,
        statut,
        (id, statutMetier) =>
            (_db.update(_db.infirmaryRecords)..where(
                  (t) => Expression.and([
                    t.id.equals(id),
                    t.status.equals(statutMetier),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(InfirmaryRecordsCompanion(syncStatus: Value(statut))),
      ),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'veterinary_calendar_events',
      corps['veterinary_calendar_events'],
      (ids, statut) => _marquerParStatut(
        [for (final e in interventions) (e.id, e.status)],
        ids,
        statut,
        (id, statutMetier) =>
            (_db.update(_db.veterinaryCalendarEvents)..where(
                  (t) => Expression.and([
                    t.id.equals(id),
                    t.status.equals(statutMetier),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(
                  VeterinaryCalendarEventsCompanion(syncStatus: Value(statut)),
                ),
      ),
      motifs,
      (n) => rejete += n,
    );

    // Ticket H9b — n'acquitte que la VERSION partie (instant de saisie inchangé, voir [_marquerSiInchangee]).
    accepte += await _acquitter(
      'feed_ration_standards',
      corps['feed_ration_standards'],
      (ids, statut) => _marquerSiInchangee(
        [for (final r in rations) (r.id, r.updatedAt)],
        ids,
        (id, saisie) =>
            (_db.update(_db.feedRationStandards)..where(
                  (t) => Expression.and([
                    t.id.equals(id),
                    saisie == null
                        ? t.updatedAt.isNull()
                        : t.updatedAt.equals(saisie),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(FeedRationStandardsCompanion(syncStatus: Value(statut))),
      ),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'prophylaxis_schedule_standards',
      corps['prophylaxis_schedule_standards'],
      (ids, statut) => _marquerSiInchangee(
        [for (final e in echeances) (e.id, e.updatedAt)],
        ids,
        (id, saisie) =>
            (_db.update(_db.prophylaxisScheduleStandards)..where(
                  (t) => Expression.and([
                    t.id.equals(id),
                    saisie == null
                        ? t.updatedAt.isNull()
                        : t.updatedAt.equals(saisie),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(
                  ProphylaxisScheduleStandardsCompanion(
                    syncStatus: Value(statut),
                  ),
                ),
      ),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'feed_types',
      corps['feed_types'],
      (ids, statut) => _marquerSiInchangee(
        [for (final p in provendes) (p.id, p.updatedAt)],
        ids,
        (id, saisie) =>
            (_db.update(_db.feedTypes)..where(
                  (t) => Expression.and([
                    t.id.equals(id),
                    saisie == null
                        ? t.updatedAt.isNull()
                        : t.updatedAt.equals(saisie),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(FeedTypesCompanion(syncStatus: Value(statut))),
      ),
      motifs,
      (n) => rejete += n,
    );

    // ⚠️ Lignes UNIQUES : le serveur acquitte sous le nom de la clé (`elevage_numbering`, `company_settings`),
    // l'identifiant envoyé avec la ligne — la ligne locale porte la clé fixe `unique`.
    accepte += await _acquitter(
      'elevage_numbering',
      corps['elevage_numbering'],
      (ids, statut) => _marquerSiInchangee(
        [
          for (final n in numerotations)
            (ParametresElevageCles.numerotation, n.updatedAt),
        ],
        ids,
        (_, saisie) =>
            (_db.update(_db.elevageNumberingSettings)..where(
                  (t) => Expression.and([
                    saisie == null
                        ? t.updatedAt.isNull()
                        : t.updatedAt.equals(saisie),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(
                  ElevageNumberingSettingsCompanion(syncStatus: Value(statut)),
                ),
      ),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'company_settings',
      corps['company_settings'],
      (ids, statut) => _marquerSiInchangee(
        [for (final e in entreprise) (ParametresElevageCles.rappelSoins, e.updatedAt)],
        ids,
        (_, saisie) =>
            (_db.update(_db.companySettings)..where(
                  (t) => Expression.and([
                    saisie == null
                        ? t.updatedAt.isNull()
                        : t.updatedAt.equals(saisie),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(CompanySettingsCompanion(syncStatus: Value(statut))),
      ),
      motifs,
      (n) => rejete += n,
    );

    // Ticket MOD1 — l'identifiant d'une ligne est le CODE de l'espèce, comme au serveur.
    accepte += await _acquitter(
      'modules_config',
      corps['modules_config'],
      (ids, statut) => _marquerSiInchangee(
        [for (final m in modules) (m.speciesCode, m.updatedAt)],
        ids,
        (code, saisie) =>
            (_db.update(_db.modulesConfig)..where(
                  (t) => Expression.and([
                    t.speciesCode.equals(code),
                    saisie == null
                        ? t.updatedAt.isNull()
                        : t.updatedAt.equals(saisie),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(ModulesConfigCompanion(syncStatus: Value(statut))),
      ),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'sales',
      corps['sales'],
      (ids, statut) async {
        await (_db.update(_db.sales)..where((t) => t.id.isIn(ids)))
            .write(SalesCompanion(syncStatus: Value(statut)));
        if (statut == SyncStatus.synced) {
          _ventesDeBetailAcquittees += ids
              .where((id) => (lignesDeVente[id] ?? const <SaleLine>[]).any((l) => l.lotId != null))
              .length;
        }
      },
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'livestock_reproduction_events',
      corps['livestock_reproduction_events'],
      (ids, statut) =>
          (_db.update(
            _db.livestockReproductionEvents,
          )..where((t) => t.id.isIn(ids))).write(
            LivestockReproductionEventsCompanion(syncStatus: Value(statut)),
          ),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'attendance_records',
      corps['attendance_records'],
      (ids, statut) =>
          (_db.update(_db.attendanceRecords)..where((t) => t.id.isIn(ids)))
              .write(AttendanceRecordsCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'purchases',
      corps['purchases'],
      (ids, statut) => (_db.update(_db.purchases)..where((t) => t.id.isIn(ids)))
          .write(PurchasesCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'stock_adjustments',
      corps['stock_adjustments'],
      (ids, statut) =>
          (_db.update(_db.stockAdjustments)..where((t) => t.id.isIn(ids)))
              .write(StockAdjustmentsCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'credit_notes',
      corps['credit_notes'],
      (ids, statut) => (_db.update(_db.creditNotes)..where((t) => t.id.isIn(ids)))
          .write(CreditNotesCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'expenses',
      corps['expenses'],
      (ids, statut) async {
        // Ticket DEP4 — un acquittement efface le refus de la pièce ; un refus le COPIE sur la dépense
        // (`ecriture_refus`, mot pour mot : le conflit vient d'être écrit par [_acquitter]).
        await (_db.update(_db.expenses)..where((t) => t.id.isIn(ids))).write(
          ExpensesCompanion(
            syncStatus: Value(statut),
            ecritureRefus: statut == SyncStatus.synced ? const Value(null) : const Value.absent(),
          ),
        );
        if (statut == SyncStatus.conflict) {
          for (final id in ids) {
            final conflit = await (_db.select(_db.syncConflicts)
                  ..where((c) => c.id.equals('expenses:$id')))
                .getSingleOrNull();
            if (conflit == null) continue;
            await (_db.update(_db.expenses)..where((t) => t.id.equals(id))).write(
              ExpensesCompanion(ecritureRefus: Value(conflit.reason)),
            );
          }
        }
      },
      motifs,
      (n) => rejete += n,
    );

    // Ticket DEV — n'acquitte que la VERSION partie (instant de saisie inchangé, voir [_marquerSiInchangee]) : un devis
    // avancé dans son cycle ou archivé PENDANT l'envoi de sa version précédente reste `pending` et repart.
    // Ticket DEV3 — un devis qui porte une DEMANDE DE CONVERSION n'est acquitté que par la réponse de cette demande
    // (`quote_conversions`, ci-dessous) : l'accusé de sa saisie le marquerait `synced` avant que la facture existe, et une
    // demande sans réponse (serveur antérieur à DEV3) serait perdue.
    final enConversion = {
      for (final d in devis)
        if (d.conversionRequestedAt != null && d.convertedSaleId == null) d.id,
    };
    accepte += await _acquitter(
      'quotes',
      corps['quotes'],
      (ids, statut) => _marquerSiInchangee(
        [for (final d in devis) (d.id, d.updatedAt)],
        statut == SyncStatus.synced ? [for (final id in ids) if (!enConversion.contains(id)) id] : ids,
        (id, saisie) =>
            (_db.update(_db.quotes)..where(
                  (t) => Expression.and([
                    t.id.equals(id),
                    t.updatedAt.equals(saisie!),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(QuotesCompanion(syncStatus: Value(statut))),
      ),
      motifs,
      (n) => rejete += n,
    );

    // Ticket DEV3 — la DEMANDE de conversion : acceptée (ou déjà exécutée : renvoi), le devis devient `facture` et prend le
    // lien et le numéro que le serveur rend (`invoices`) ; refusée, il passe en `conflict` avec le motif du serveur mot pour
    // mot (SyncConflict `quote_conversions:<id>`) et attend « Annuler la demande » ou une relance. Une demande n'est jamais
    // partie sans que son devis soit `pending` : rien d'autre à comparer.
    final factures = corps['quote_conversions'] is Map && (corps['quote_conversions'] as Map)['invoices'] is Map
        ? Map<String, dynamic>.from((corps['quote_conversions'] as Map)['invoices'] as Map)
        : const <String, dynamic>{};
    accepte += await _acquitter(
      'quote_conversions',
      corps['quote_conversions'],
      (ids, statut) async {
        for (final id in ids) {
          final facture = factures[id];
          await (_db.update(_db.quotes)..where(
                (t) => Expression.and([
                  t.id.equals(id),
                  Expression.or([
                    t.syncStatus.equalsValue(SyncStatus.pending),
                    t.syncStatus.equalsValue(SyncStatus.conflict),
                  ]),
                ]),
              ))
              .write(
                statut == SyncStatus.synced
                    ? QuotesCompanion(
                        syncStatus: const Value(SyncStatus.synced),
                        status: const Value('facture'),
                        conversionRequestedAt: const Value(null),
                        convertedSaleId: Value(facture is Map ? facture['sale_id']?.toString() : null),
                        invoiceNumber: Value(facture is Map ? facture['invoice_number']?.toString() : null),
                      )
                    : QuotesCompanion(syncStatus: Value(statut)),
              );
        }
      },
      motifs,
      (n) => rejete += n,
    );

    // Ticket U3 — n'acquitte que la VERSION partie (instant de saisie inchangé, voir [_marquerSiInchangee]) : un
    // soin archivé PENDANT l'envoi de sa création reste `pending`, et son archivage part au prochain envoi.
    accepte += await _acquitter(
      'veterinary_records',
      corps['veterinary_records'],
      (ids, statut) => _marquerSiInchangee(
        [for (final s in soins) (s.id, s.updatedAt)],
        ids,
        (id, saisie) =>
            (_db.update(_db.veterinaryRecords)..where(
                  (t) => Expression.and([
                    t.id.equals(id),
                    t.updatedAt.equals(saisie!),
                    t.syncStatus.equalsValue(SyncStatus.pending),
                  ]),
                ))
                .write(VeterinaryRecordsCompanion(syncStatus: Value(statut))),
      ),
      motifs,
      (n) => rejete += n,
    );

    // ⚠️ SEUL RÉFÉRENTIEL OÙ LE POSTE ÉCRIT (F0.67) : le serveur valide et engendre
    // le SKU définitif, qui revient au tirage suivant.
    accepte += await _acquitter(
      'products',
      corps['products'],
      (ids, statut) => (_db.update(_db.products)..where((t) => t.id.isIn(ids)))
          .write(ProductsCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'suppliers',
      corps['suppliers'],
      (ids, statut) => (_db.update(_db.suppliers)..where((t) => t.id.isIn(ids)))
          .write(SuppliersCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    accepte += await _acquitter(
      'customers',
      corps['customers'],
      (ids, statut) => (_db.update(_db.customers)..where((t) => t.id.isIn(ids)))
          .write(CustomersCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    // ⚠️⚠️ TICKET S-T5 — LE POSTE APPREND L'IDENTIFIANT DU SERVEUR. Un produit, un fournisseur ou un client créé ici
    // que le serveur connaissait déjà (même clé naturelle) est acquitté ET rendu dans `merged` : l'identifiant local
    // est remplacé partout (fiche et références, une transaction), APRÈS son acquittement ci-dessus.
    await FusionReferentiels(_db).appliquerReponse(corps);

    // ⚠️ Un courrier accepté n'a pas encore sa référence : elle descend au tirage de
    // confirmation (voir [synchroniser]).
    final courriersAcceptes = await _acquitter(
      'mails',
      corps['mails'],
      (ids, statut) => _marquerCourriers(courriers, ids, statut),
      motifs,
      (n) => rejete += n,
    );
    accepte += courriersAcceptes;
    _courriersAcquittes = courriersAcceptes;

    final archivesAcceptees = await _acquitter(
      'archived_documents',
      corps['archived_documents'],
      (ids, statut) => _marquerArchives(archives, ids, statut),
      motifs,
      (n) => rejete += n,
    );
    accepte += archivesAcceptees;
    _archivesAcquittees = archivesAcceptees;

    final documentsAcceptes = await _acquitter(
      'administrative_documents',
      corps['administrative_documents'],
      (ids, statut) => _marquerDocuments(documents, ids, statut),
      motifs,
      (n) => rejete += n,
    );
    accepte += documentsAcceptes;
    _documentsAcquittes = documentsAcceptes;

    accepte += await _acquitter(
      'supplier_payments',
      corps['supplier_payments'],
      (ids, statut) =>
          (_db.update(_db.supplierPayments)..where((t) => t.id.isIn(ids)))
              .write(SupplierPaymentsCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    final avancesAcceptees = await _acquitter(
      'customer_advances',
      corps['customer_advances'],
      (ids, statut) =>
          (_db.update(_db.customerAdvances)..where((t) => t.id.isIn(ids)))
              .write(CustomerAdvancesCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    final imputationsAcceptees = await _acquitter(
      'advance_imputations',
      corps['advance_imputations'],
      (ids, statut) =>
          (_db.update(_db.advanceImputations)..where((t) => t.id.isIn(ids)))
              .write(AdvanceImputationsCompanion(syncStatus: Value(statut))),
      motifs,
      (n) => rejete += n,
    );

    // ⚠️ Retours et remboursements : le serveur ne renvoie un `id` en `accepted` qu'une fois
    // le stock, la dette, la trésorerie et l'écriture passés dans UNE transaction.
    final retoursAcceptes = await _acquitter(
      'purchase_returns',
      corps['purchase_returns'],
      (ids, statut) =>
          (_db.update(_db.purchaseReturns)..where((t) => t.id.isIn(ids))).write(
            PurchaseReturnsCompanion(syncStatus: Value(statut)),
          ),
      motifs,
      (n) => rejete += n,
    );

    final remboursementsAcceptes = await _acquitter(
      'supplier_refunds',
      corps['supplier_refunds'],
      (ids, statut) =>
          (_db.update(_db.supplierRefunds)..where((t) => t.id.isIn(ids))).write(
            SupplierRefundsCompanion(syncStatus: Value(statut)),
          ),
      motifs,
      (n) => rejete += n,
    );

    accepte +=
        avancesAcceptees +
        imputationsAcceptees +
        retoursAcceptes +
        remboursementsAcceptes;
    _financiersAcquittes =
        avancesAcceptees +
        imputationsAcceptees +
        retoursAcceptes +
        remboursementsAcceptes;

    // Ticket H13b — un lot a échoué après d'autres : ce qui a été accusé vient d'être acquitté, l'échec remonte
    // (réessai réseau, message de refus) et le reste repartira à la prochaine synchronisation.
    if (echecDeLot != null) Error.throwWithStackTrace(echecDeLot, pileDeLot!);

    await _db.noterEtatDeSynchronisation(envoye: DateTime.now());

    return (accepte, rejete, motifs);
  }

  /// Ticket H13b (D-SYNC-2) — au plus [tailleLot] enregistrements par requête.
  static const tailleLot = 50;

  /// Ordre de traitement de `SyncController::push`, table par table. Les lots partent dans cet ordre : ce
  /// qu'une table attend d'une autre (un fournisseur avant son achat, un achat avant son retour, une vente
  /// avant son imputation) est déjà écrit sur le serveur quand elle arrive.
  static const ordreDuServeur = [
    'feed_ration_standards',
    'prophylaxis_schedule_standards',
    'feed_types',
    'elevage_numbering',
    'company_settings',
    // Ticket MOD1 — modules actifs (`modules_config`), juste après les paramètres d'élevage, comme au serveur.
    'modules_config',
    'suppliers',
    'customers',
    // Ticket DEV — APRÈS les clients : un devis du même envoi peut viser le client créé (ou fusionné) à l'instant.
    'quotes',
    // Ticket DEV3 — la DEMANDE de conversion d'un devis, juste après les devis (le devis du même envoi existe alors déjà).
    'quote_conversions',
    'mails',
    'archived_documents',
    'administrative_documents',
    'customer_advances',
    'products',
    // Ticket BS1 — la bande avant ses fiches et ses transferts.
    'livestock_lots',
    // Ticket BS3 — les reproducteurs après leur bande (celle créée à l'instant dans le même envoi).
    'animals',
    'livestock_daily_entries',
    'livestock_transfers',
    'expenses',
    'purchases',
    'supplier_payments',
    'purchase_returns',
    'supplier_refunds',
    'attendance_records',
    'sales',
    // Ticket AV1 — après les ventes (un retour peut viser la vente du même envoi), avant les imputations.
    'credit_notes',
    'advance_imputations',
    'livestock_reproduction_events',
    'infirmary_records',
    'veterinary_calendar_events',
    'stock_adjustments',
    'veterinary_records',
  ];

  /// ⚠️⚠️ **TABLES COUPLÉES DANS UN MÊME ENVOI, JAMAIS SÉPARÉES PAR JOUR.** Le serveur passe aux ventes les
  /// fiches (bande, jour) ACCEPTÉES dans la même requête (15.30) : la fiche du poste porte déjà la vente, il
  /// ne l'y rajoute pas. Une fiche partie dans un lot ANTÉRIEUR à sa vente ferait compter la vente deux fois
  /// (2N, effectif de la bande faux de N) — sans aucune erreur. Les transferts du jour suivent ses fiches
  /// (15.46). Ces trois tables partent donc par JOURNÉES ENTIÈRES (fiches, transferts, ventes du jour), au
  /// rang des ventes ; une journée de plus de [tailleLot] lignes part seule.
  static const _couplees = [
    ('livestock_daily_entries', 'entry_date'),
    ('livestock_transfers', 'transfer_date'),
    ('sales', 'sold_at'),
  ];

  /// Découpe [envoi] en lots ordonnés (voir [ordreDuServeur], [_couplees]). Un envoi de [tailleLot] lignes
  /// au plus part TEL QUEL, en une requête : rien ne change pour le cas courant.
  @visibleForTesting
  static List<Map<String, dynamic>> decouperEnLots(Map<String, dynamic> envoi) {
    final lignes = envoi.values.whereType<List>().fold<int>(0, (n, l) => n + l.length);
    if (lignes <= tailleLot) return [envoi];

    final (entete, unites) = _unitesDe(envoi);
    final lots = <Map<String, dynamic>>[];
    var courant = <(String, Object?)>[];
    void fermer() {
      if (courant.isEmpty) return;
      lots.add(_assembler(entete, courant));
      courant = [];
    }

    for (final unite in unites) {
      if (courant.isNotEmpty && courant.length + unite.length > tailleLot) fermer();
      courant.addAll(unite);
    }
    fermer();
    return lots;
  }

  /// En-tête (clés qui ne sont pas des listes : `device_id`, `data_reset_at`) et UNITÉS INDIVISIBLES de [envoi],
  /// dans l'ordre du serveur : une ligne, ou une JOURNÉE couplée entière (fiches, transferts et ventes du jour,
  /// voir [_couplees]). Ni [decouperEnLots] ni [envoyerEnIsolant] ne coupent jamais une unité.
  static (Map<String, dynamic>, List<List<(String, Object?)>>) _unitesDe(
    Map<String, dynamic> envoi,
  ) {
    final entete = {
      for (final e in envoi.entries)
        if (e.value is! List) e.key: e.value,
    };
    final unites = <List<(String, Object?)>>[];
    final couplees = {for (final (t, _) in _couplees) t};
    final tables = [
      ...ordreDuServeur,
      // Une table que cette liste ne connaît pas encore part en dernier plutôt que de se perdre.
      for (final k in envoi.keys)
        if (envoi[k] is List && !ordreDuServeur.contains(k)) k,
    ];
    for (final table in tables) {
      if (table == 'sales') {
        final parJour = SplayTreeMap<String, List<(String, Object?)>>();
        for (final (t, cle) in _couplees) {
          for (final ligne in (envoi[t] as List?) ?? const []) {
            final date = ligne is Map ? ligne[cle]?.toString() ?? '' : '';
            parJour
                .putIfAbsent(date.length >= 10 ? date.substring(0, 10) : date, () => [])
                .add((t, ligne));
          }
        }
        unites.addAll(parJour.values);
        continue;
      }
      if (couplees.contains(table)) continue;
      for (final ligne in (envoi[table] as List?) ?? const []) {
        unites.add([(table, ligne)]);
      }
    }
    return (entete, unites);
  }

  /// Un lot : l'en-tête, puis chaque ligne sous sa table (une table vide ne part pas).
  static Map<String, dynamic> _assembler(
    Map<String, dynamic> entete,
    Iterable<(String, Object?)> lignes,
  ) {
    final lot = Map<String, dynamic>.of(entete);
    for (final (t, ligne) in lignes) {
      (lot.putIfAbsent(t, () => <Object?>[]) as List).add(ligne);
    }
    return lot;
  }

  /// Réponses des lots fusionnées table par table (acceptés et refusés mis bout à bout, compteurs additionnés),
  /// pour l'acquittement habituel. ⚠️ Un lot en échec n'efface pas les précédents : leurs accusés sont rendus
  /// avec l'erreur, pour être acquittés AVANT qu'elle remonte — sinon le poste renverrait ce que le serveur a
  /// déjà écrit.
  Future<(Map<String, dynamic>, Object?, StackTrace?)> _envoyerParLots(
    Map<String, dynamic> envoi,
  ) async {
    final fusion = <String, dynamic>{};
    var recu = false;
    for (final lot in decouperEnLots(envoi)) {
      try {
        await envoyerEnIsolant(
          lot,
          (l) async =>
              (await _client.post<Map<String, dynamic>>('/api/sync/push', data: l)).data ??
              const <String, dynamic>{},
          (reponse) {
            recu = true;
            fusionnerReponse(fusion, reponse);
          },
        );
      } catch (e, pile) {
        if (!recu) rethrow;
        return (fusion, e, pile);
      }
    }
    return (fusion, null, null);
  }

  /// ⚠️⚠️ Ticket S-T1 — UNE 422 OU UNE 413 SUR UN LOT ENTIER COUPE LE LOT EN DEUX, récursivement, jusqu'à isoler
  /// la ou les unités fautives. Un refus ligne à ligne arrive en 200 avec `rejected` : ce cas-là ne passe pas ici.
  /// Une 422 / 413 de LOT ENTIER (requête invalide dans son ensemble, corps trop gros pour le serveur) refusait
  /// jusqu'ici les 49 lignes saines avec la fautive, à chaque tentative, sans jamais dire laquelle.
  ///
  /// [poster] envoie un lot et rend la réponse ; [recevoir] reçoit chaque réponse dans l'ordre d'envoi, y compris
  /// le refus fabriqué ici ([refusDUnite]) pour une unité isolée qui provoque encore la 422 / 413 : elle passe en
  /// `conflict` avec un motif français, et l'utilisateur la corrige puis la remet en file, comme tout refus.
  ///
  /// ⚠️⚠️ **LA COUPE NE PASSE JAMAIS AU MILIEU D'UNE JOURNÉE COUPLÉE** ([_unitesDe]) : une vente séparée de la
  /// fiche de son jour serait comptée deux fois (15.30). Une journée couplée qui provoque seule la 422 passe
  /// ENTIÈRE en `conflict`. Toute autre erreur (réseau, 5xx, 401, 403…) remonte telle quelle.
  @visibleForTesting
  static Future<void> envoyerEnIsolant(
    Map<String, dynamic> lot,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> lot) poster,
    void Function(Map<String, dynamic> reponse) recevoir,
  ) async {
    final Map<String, dynamic> reponse;
    try {
      reponse = await poster(lot);
    } on DioException catch (e) {
      final statut = e.response?.statusCode;
      if (statut != 422 && statut != 413) rethrow;
      final (entete, unites) = _unitesDe(lot);
      if (unites.isEmpty) rethrow;
      if (unites.length == 1) {
        recevoir(refusDUnite(unites.single, statut!, e.response?.data));
        return;
      }
      final milieu = unites.length ~/ 2;
      await envoyerEnIsolant(
        _assembler(entete, unites.take(milieu).expand((u) => u)),
        poster,
        recevoir,
      );
      await envoyerEnIsolant(
        _assembler(entete, unites.skip(milieu).expand((u) => u)),
        poster,
        recevoir,
      );
      return;
    }
    recevoir(reponse);
  }

  /// Ticket S-T1 — réponse fabriquée pour une unité isolée que le serveur refuse encore en 422 / 413 : chaque
  /// ligne est rendue en `rejected` sous sa table, avec « Refusée par le serveur : requête invalide (422) » (ou
  /// « envoi trop volumineux (413) ») suivi du message du serveur s'il en donne un.
  @visibleForTesting
  static Map<String, dynamic> refusDUnite(
    List<(String, Object?)> unite,
    int statut,
    Object? corps,
  ) {
    final message = corps is Map && corps['message'] is String
        ? (corps['message'] as String).trim()
        : '';
    final cause = statut == 413
        ? 'Refusée par le serveur : envoi trop volumineux (413)'
        : 'Refusée par le serveur : requête invalide (422)';
    final motif = message.isEmpty ? '$cause.' : '$cause — $message';
    final reponse = <String, dynamic>{};
    for (final (table, ligne) in unite) {
      final cible =
          reponse.putIfAbsent(
                table,
                () => <String, dynamic>{'accepted': <Object?>[], 'rejected': <Object?>[]},
              )
              as Map<String, dynamic>;
      (cible['rejected'] as List).add({
        'id': ligne is Map ? ligne['id']?.toString() : null,
        'reason': motif,
      });
    }
    return reponse;
  }

  @visibleForTesting
  static void fusionnerReponse(Map<String, dynamic> fusion, Map<String, dynamic> reponse) {
    for (final MapEntry(:key, :value) in reponse.entries) {
      final deja = fusion[key];
      if (value is Map && (value.containsKey('accepted') || value.containsKey('rejected'))) {
        final cible = deja is Map
            ? deja
            : fusion[key] = <String, dynamic>{'accepted': <Object?>[], 'rejected': <Object?>[]};
        for (final cote in const ['accepted', 'rejected']) {
          (cible[cote] as List).addAll((value[cote] as List?) ?? const []);
        }
        // Ticket S-T5 — fusions par clé naturelle (`products`, `suppliers`, `customers`), mises bout à bout.
        if (value['merged'] is List) {
          (cible.putIfAbsent('merged', () => <Object?>[]) as List).addAll(value['merged'] as List);
        }
        // Ticket DEV3 — les factures rendues aux demandes de conversion (devis → { sale_id, invoice_number }), réunies.
        if (value['invoices'] is Map) {
          final factures = cible.putIfAbsent('invoices', () => <String, dynamic>{}) as Map<String, dynamic>;
          for (final f in (value['invoices'] as Map).entries) {
            factures[f.key.toString()] = f.value;
          }
        }
      } else if (value is num && deja is num) {
        fusion[key] = deja + value;
      } else if (value is List && deja is List) {
        fusion[key] = [...deja, ...value];
      } else {
        fusion[key] = value;
      }
    }
  }

  /// Ticket H8b — acquitte ou refuse des lignes dont seul le STATUT MÉTIER change après création (infirmerie :
  /// `en_cours` → `reintegre`/`deces` ; intervention : `planned` → `done`). [envoyes] = (id, statut métier) de
  /// ce qui est PARTI.
  ///
  /// ⚠️⚠️ **LE STATUT DE SYNCHRONISATION NE CHANGE QUE SI LA LIGNE EST ENCORE CELLE QUI EST PARTIE** (même
  /// règle que [_marquerCourriers]) : une entrée réintégrée PENDANT l'envoi de sa création serait sinon marquée
  /// `synced` sur l'accusé de l'ancienne version, et la réintégration ne partirait jamais.
  Future<void> _marquerParStatut(
    List<(String, String)> envoyes,
    List<String> ids,
    SyncStatus statut,
    Future<void> Function(String id, String statutMetier) marquer,
  ) async {
    for (final (id, statutMetier) in envoyes) {
      if (ids.contains(id)) await marquer(id, statutMetier);
    }
  }

  /// Ticket H9b — acquitte ou refuse des Paramètres Élevage. [envoyes] = (identifiant, instant de saisie) de ce
  /// qui est PARTI.
  ///
  /// ⚠️⚠️ **LE STATUT NE CHANGE QUE SI LA LIGNE EST ENCORE CELLE QUI EST PARTIE** (même règle que
  /// [_marquerCourriers] et [_marquerParStatut]) : une ration corrigée PENDANT l'envoi garde un instant de
  /// saisie plus récent, reste `pending` et repart au prochain envoi — sinon l'accusé de l'ancienne version la
  /// marquerait `synced` et la correction ne partirait jamais.
  Future<void> _marquerSiInchangee(
    List<(String, DateTime?)> envoyes,
    List<String> ids,
    Future<void> Function(String id, DateTime? saisie) marquer,
  ) async {
    for (final (id, saisie) in envoyes) {
      if (ids.contains(id)) await marquer(id, saisie);
    }
  }

  /// Acquitte ou refuse des courriers ([envoyes] = ce qui est PARTI, tel quel).
  ///
  /// ⚠️⚠️ **LE STATUT NE CHANGE QUE SI LA LIGNE EST ENCORE CELLE QUI EST PARTIE** (F0.78-bis).
  /// Le poste reste utilisable pendant l'envoi : un courrier corrigé entre-temps serait sinon
  /// marqué `synced` sur l'accusé de son ANCIENNE version, et la correction ne partirait
  /// jamais. Si la ligne a changé, elle reste `pending` (elle repart au prochain envoi).
  ///
  /// ⚠️ Un courrier ACCEPTÉ est en revanche toujours « connu du serveur », quelle que soit
  /// la version : c'est ce qui autorisera plus tard son archivage.
  Future<void> _marquerCourriers(
    List<Mail> envoyes,
    List<String> ids,
    SyncStatus statut,
  ) async {
    if (statut == SyncStatus.synced) {
      await (_db.update(_db.mails)..where((t) => t.id.isIn(ids))).write(
        const MailsCompanion(knownByServer: Value(true)),
      );
    }

    for (final m in envoyes.where((m) => ids.contains(m.id))) {
      await (_db.update(_db.mails)..where(
            (t) => Expression.and([
              t.id.equals(m.id),
              t.type.equals(m.type),
              t.subject.equals(m.subject),
              m.party == null ? t.party.isNull() : t.party.equals(m.party!),
              m.mailDate == null
                  ? t.mailDate.isNull()
                  : t.mailDate.equals(m.mailDate!),
              t.isActive.equals(m.isActive),
              t.syncStatus.equalsValue(SyncStatus.pending),
            ]),
          ))
          .write(MailsCompanion(syncStatus: Value(statut)));
    }
  }

  /// Acquitte ou refuse des documents archivés ([envoyes] = ce qui est PARTI, tel quel).
  ///
  /// ⚠️⚠️ **LE STATUT NE CHANGE QUE SI LA LIGNE EST ENCORE CELLE QUI EST PARTIE** (même règle
  /// que [_marquerCourriers]) : un document corrigé ou retiré pendant l'envoi reste `pending`
  /// et repart. Un document ACCEPTÉ est en revanche toujours « connu du serveur ».
  Future<void> _marquerArchives(
    List<ArchivedDocument> envoyes,
    List<String> ids,
    SyncStatus statut,
  ) async {
    if (statut == SyncStatus.synced) {
      await (_db.update(_db.archivedDocuments)..where((t) => t.id.isIn(ids)))
          .write(const ArchivedDocumentsCompanion(knownByServer: Value(true)));
    }

    for (final a in envoyes.where((a) => ids.contains(a.id))) {
      await (_db.update(_db.archivedDocuments)..where(
            (t) => Expression.and([
              t.id.equals(a.id),
              t.title.equals(a.title),
              a.category == null
                  ? t.category.isNull()
                  : t.category.equals(a.category!),
              a.archivedDate == null
                  ? t.archivedDate.isNull()
                  : t.archivedDate.equals(a.archivedDate!),
              a.expiryDate == null
                  ? t.expiryDate.isNull()
                  : t.expiryDate.equals(a.expiryDate!),
              t.isActive.equals(a.isActive),
              t.syncStatus.equalsValue(SyncStatus.pending),
            ]),
          ))
          .write(ArchivedDocumentsCompanion(syncStatus: Value(statut)));
    }
  }

  /// Acquitte ou refuse des documents administratifs ([envoyes] = ce qui est PARTI, tel quel).
  ///
  /// ⚠️⚠️ **LE STATUT NE CHANGE QUE SI LA LIGNE EST ENCORE CELLE QUI EST PARTIE** (même règle
  /// que [_marquerCourriers] et [_marquerArchives]) : un document corrigé ou retiré pendant
  /// l'envoi reste `pending` et repart. Un document ACCEPTÉ est en revanche toujours « connu
  /// du serveur ».
  Future<void> _marquerDocuments(
    List<AdministrativeDocument> envoyes,
    List<String> ids,
    SyncStatus statut,
  ) async {
    if (statut == SyncStatus.synced) {
      await (_db.update(
        _db.administrativeDocuments,
      )..where((t) => t.id.isIn(ids))).write(
        const AdministrativeDocumentsCompanion(knownByServer: Value(true)),
      );
    }

    for (final d in envoyes.where((d) => ids.contains(d.id))) {
      await (_db.update(_db.administrativeDocuments)..where(
            (t) => Expression.and([
              t.id.equals(d.id),
              t.title.equals(d.title),
              d.type == null ? t.type.isNull() : t.type.equals(d.type!),
              d.beneficiary == null
                  ? t.beneficiary.isNull()
                  : t.beneficiary.equals(d.beneficiary!),
              d.docDate == null
                  ? t.docDate.isNull()
                  : t.docDate.equals(d.docDate!),
              d.status == null ? t.status.isNull() : t.status.equals(d.status!),
              t.isActive.equals(d.isActive),
              t.syncStatus.equalsValue(SyncStatus.pending),
            ]),
          ))
          .write(AdministrativeDocumentsCompanion(syncStatus: Value(statut)));
    }
  }

  /// Marque `synced` les identifiants acceptés, `conflict` les refusés.
  ///
  /// ⚠️ **UN REFUS N'EST NI PERDU NI RÉPUTÉ ENVOYÉ.** L'enregistrement reste
  /// sur le poste et continue de compter comme « en attente » — mais il passe
  /// en `conflict` et sort des envois automatiques.
  ///
  /// ⚠️ **POURQUOI LE SORTIR DES ENVOIS.** Laissé `pending`, il repartait à
  /// chaque synchronisation et se faisait refuser à chaque fois : une boucle
  /// silencieuse, coûteuse en réseau, que personne ne pouvait diagnostiquer
  /// puisque le motif disparaissait avec le bandeau. Il faut une correction —
  /// souvent côté serveur — puis une relance explicite.
  Future<int> _acquitter(
    String table,
    Object? resultat,
    Future<void> Function(List<String> ids, SyncStatus statut) marquer,
    List<String> motifs,
    void Function(int) compterRejets,
  ) async {
    if (resultat is! Map) return 0;

    final acceptes =
        (resultat['accepted'] as List?)?.cast<String>() ?? const [];
    if (acceptes.isNotEmpty) {
      await marquer(acceptes, SyncStatus.synced);

      // ⚠️ F0.79-bis — UN REFUS PÉRIMÉ NE SURVIT PAS À L'ACCEPTATION. Seuls les refus de ces
      // identifiants-là, dans CETTE table, sont purgés (clé `table:id`) : un refus d'un autre
      // enregistrement ne bouge pas. Une ligne n'est envoyée qu'en `pending` ; un refus encore
      // ouvert à ce moment-là est donc celui d'une version antérieure, déjà dépassée. Les rejets
      // du même envoi sont traités PLUS BAS : leur refus tout neuf n'est pas touché.
      await (_db.delete(
            _db.syncConflicts,
          )..where((c) => c.id.isIn([for (final id in acceptes) '$table:$id'])))
          .go();
    }

    final rejets = (resultat['rejected'] as List?) ?? const [];
    compterRejets(rejets.length);

    final refuses = <String>[];

    for (final r in rejets) {
      if (r is! Map) continue;

      final motif = r['reason']?.toString() ?? 'Refus sans motif communiqué.';
      motifs.add(motif);

      // 🔴→✅ Ticket S-T10 (trouvé par l'essai à plusieurs postes) — `stock_adjustments` ne rendait que
      // `client_ref` dans ses refus : l'inventaire refusé restait `pending`, renvoyé à chaque synchronisation, et
      // son motif n'arrivait jamais à l'écran. Le serveur rend désormais aussi `id` ; un serveur ancien, non.
      final id = (r['id'] ?? r['client_ref'])?.toString();
      if (id == null) continue;

      refuses.add(id);

      // Le motif est conservé MOT POUR MOT : c'est le serveur qui sait
      // pourquoi il refuse, et le reformuler ferait perdre l'information dont
      // le responsable a besoin pour corriger.
      await _db
          .into(_db.syncConflicts)
          .insertOnConflictUpdate(
            SyncConflictsCompanion.insert(
              id: '$table:$id',
              sourceTable: table,
              recordId: id,
              reason: motif,
              detectedAt: DateTime.now(),
            ),
          );
    }

    if (refuses.isNotEmpty) {
      await marquer(refuses, SyncStatus.conflict);
    }

    return acceptes.length;
  }

  /// Remet en file un enregistrement refusé, une fois sa cause corrigée.
  ///
  /// ⚠️ RELANCE EXPLICITE, jamais automatique : sans correction, le serveur
  /// refuserait de nouveau et la boucle reprendrait.
  Future<void> relancer(SyncConflict conflit) async {
    final compagnon = switch (conflit.sourceTable) {
      // Ticket BS1 — une bande refusée (code déjà pris, exercice clos…) se corrige puis se relance.
      'livestock_lots' =>
        () =>
            (_db.update(_db.livestockLots)..where((t) => t.id.equals(conflit.recordId))).write(
              const LivestockLotsCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      // Ticket BS3 — un reproducteur refusé (identifiant déjà pris, date…) se corrige puis se relance.
      'animals' =>
        () =>
            (_db.update(_db.animals)..where((t) => t.id.equals(conflit.recordId))).write(
              const AnimalsCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      'livestock_daily_entries' =>
        () =>
            (_db.update(
              _db.livestockDailyEntries,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const LivestockDailyEntriesCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'sales' => () => _relancerVente(conflit.recordId),
      'veterinary_records' =>
        () =>
            (_db.update(
              _db.veterinaryRecords,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const VeterinaryRecordsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'stock_adjustments' =>
        () =>
            (_db.update(
              _db.stockAdjustments,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const StockAdjustmentsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'suppliers' =>
        () =>
            (_db.update(
              _db.suppliers,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const SuppliersCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      'customers' =>
        () =>
            (_db.update(
              _db.customers,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const CustomersCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      // Ticket DEV — un devis refusé (exercice clos, statut interdit, client inconnu…) se corrige puis se relance.
      // Ticket DEV3 — une demande de conversion refusée (client archivé, plan incomplet, exercice clos…) se relance de même.
      'quotes' || 'quote_conversions' =>
        () =>
            (_db.update(_db.quotes)..where((t) => t.id.equals(conflit.recordId))).write(
              const QuotesCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      'mails' =>
        () =>
            (_db.update(
              _db.mails,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const MailsCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      'archived_documents' =>
        () =>
            (_db.update(
              _db.archivedDocuments,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const ArchivedDocumentsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'administrative_documents' =>
        () =>
            (_db.update(
              _db.administrativeDocuments,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const AdministrativeDocumentsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'customer_advances' =>
        () =>
            (_db.update(
              _db.customerAdvances,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const CustomerAdvancesCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'advance_imputations' =>
        () =>
            (_db.update(
              _db.advanceImputations,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const AdvanceImputationsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'supplier_payments' =>
        () =>
            (_db.update(
              _db.supplierPayments,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const SupplierPaymentsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      // ⚠️ F0.77 : sans cette entrée, « Relancer » d'un achat refusé (compte absent du
      // plan, total nul) ne faisait RIEN — le bouton s'affichait, l'achat restait en
      // `conflict` pour toujours.
      'purchases' =>
        () =>
            (_db.update(
              _db.purchases,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const PurchasesCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      // Tickets AV1 / AV2 — sans cette entrée, « Relancer » un retour client refusé ne ferait rien (défaut F0.77).
      'credit_notes' =>
        () =>
            (_db.update(
              _db.creditNotes,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const CreditNotesCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      'purchase_returns' =>
        () =>
            (_db.update(
              _db.purchaseReturns,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const PurchaseReturnsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'supplier_refunds' =>
        () =>
            (_db.update(
              _db.supplierRefunds,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const SupplierRefundsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'products' =>
        () =>
            (_db.update(
              _db.products,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const ProductsCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      'livestock_reproduction_events' =>
        () =>
            (_db.update(
              _db.livestockReproductionEvents,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const LivestockReproductionEventsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      // Ticket H8b — sans ces entrées, « Relancer » une entrée d'infirmerie ou une intervention refusée ne
      // ferait rien (même défaut que celui des achats, F0.77).
      'infirmary_records' =>
        () =>
            (_db.update(
              _db.infirmaryRecords,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const InfirmaryRecordsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'veterinary_calendar_events' =>
        () =>
            (_db.update(
              _db.veterinaryCalendarEvents,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const VeterinaryCalendarEventsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      // Ticket H9b — Paramètres Élevage refusés : « Relancer » les remet en file, comme les autres tables.
      'feed_ration_standards' =>
        () =>
            (_db.update(
              _db.feedRationStandards,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const FeedRationStandardsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'prophylaxis_schedule_standards' =>
        () =>
            (_db.update(
              _db.prophylaxisScheduleStandards,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const ProphylaxisScheduleStandardsCompanion(
                syncStatus: Value(SyncStatus.pending),
              ),
            ),
      'feed_types' =>
        () =>
            (_db.update(
              _db.feedTypes,
            )..where((t) => t.id.equals(conflit.recordId))).write(
              const FeedTypesCompanion(syncStatus: Value(SyncStatus.pending)),
            ),
      // Lignes uniques : le refus porte le nom de la clé, la ligne locale est `unique`.
      'elevage_numbering' =>
        () =>
            (_db.update(_db.elevageNumberingSettings)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.conflict),
                ))
                .write(
                  const ElevageNumberingSettingsCompanion(
                    syncStatus: Value(SyncStatus.pending),
                  ),
                ),
      'company_settings' =>
        () =>
            (_db.update(_db.companySettings)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.conflict),
                ))
                .write(
                  const CompanySettingsCompanion(
                    syncStatus: Value(SyncStatus.pending),
                  ),
                ),
      // Ticket MOD1 — le refus porte le code de l'espèce : la ligne locale en conflit repart en file.
      'modules_config' =>
        () =>
            (_db.update(_db.modulesConfig)..where(
                  (t) => t.syncStatus.equalsValue(SyncStatus.conflict),
                ))
                .write(
                  const ModulesConfigCompanion(
                    syncStatus: Value(SyncStatus.pending),
                  ),
                ),
      _ => null,
    };

    if (compagnon == null) return;

    await compagnon();
    await (_db.delete(
      _db.syncConflicts,
    )..where((t) => t.id.equals(conflit.id))).go();
  }

  /// Relance d'une vente refusée : la vente SEULE repart en file.
  ///
  /// 🔴→✅ TICKET F0.90 (défaut D2 de l'audit) — LA FICHE NE REPART PLUS EN ENTIER. F0.89 remettait
  /// en file la fiche `synced` du jour de la vente pour éviter le double comptage (2N), mais
  /// renvoyait ainsi la fiche TELLE QUE LE POSTE LA DÉTIENT : le serveur applique « dernier
  /// écrivain gagne » (`pushDailyEntries`, `fill` de toutes les colonnes reçues), et une correction
  /// faite entre-temps sur le web (2 morts au lieu d'1) était écrasée. Le double comptage est
  /// désormais évité par la FICHE D'IDENTITÉ que [_fichesDIdentite] joint à l'envoi.
  Future<void> _relancerVente(String venteId) async {
    await (_db.update(_db.sales)..where((t) => t.id.equals(venteId))).write(
      const SalesCompanion(syncStatus: Value(SyncStatus.pending)),
    );
  }

  /// 🔴→✅ TICKET F0.90 — FICHES D'IDENTITÉ : `{id, lot_id, entry_date}` et RIEN D'AUTRE.
  ///
  /// ⚠️⚠️ LE PROBLÈME. Le serveur (15.30) n'ajoute pas une vente à une fiche (bande, jour) ACCEPTÉE
  /// dans le MÊME envoi : il la sait déjà portée par la fiche du poste. Une vente REFUSÉE (mois
  /// clôturé…) laisse au serveur une fiche acceptée qui porte déjà ses N têtes ; relancer la vente
  /// seule ferait 2N. Renvoyer la fiche ENTIÈRE (F0.89) l'évitait, mais écrasait toute correction
  /// web de cette fiche.
  ///
  /// ✅ LA MESURE. Pour chaque vente en file, la fiche (bande, JOUR DE LA VENTE) que le poste tient
  /// pour `synced` part réduite à son identité. Lu dans `SyncController` (Laravel, 15.33) :
  ///  - `pushDailyEntries` retrouve la fiche par `id` et fait `fill(except id, effectif_final)` :
  ///    Eloquent n'écrit QUE les clés présentes — achat, nés, morts, vente, dons stockés au
  ///    serveur (donc la correction web) restent intacts ; `effectif_final` est recalculé à partir
  ///    d'eux, jamais repris du poste ;
  ///  - la fiche est ACCEPTÉE : `fichesAcceptees` l'inscrit, et `RecordSaleOnFicheElevageAction`
  ///    n'ajoute pas la vente une seconde fois (sa cascade, elle, tourne quand même).
  ///
  /// ⚠️ POURQUOI C'EST SÛR, ET JUSQU'OÙ. Une fiche `synced` au poste a été ACCEPTÉE par le serveur
  /// avec la vente déjà comptée (la caisse inscrit la vente dans la fiche et la remet en file dans
  /// la même transaction) : la valeur serveur porte donc la vente. Aucune page du serveur ne
  /// SUPPRIME une fiche (lu : seuls des `updateOrCreate` par (bande, jour), qui gardent l'`id`).
  /// Limite connue : si la fiche avait disparu du serveur (restauration, intervention en base),
  /// la fiche d'identité y créerait une fiche vide qui exempterait la vente (0 au lieu de N) —
  /// d'où le ticket serveur proposé (F0.90) : refuser une fiche d'identité inconnue.
  ///
  /// Une fiche `pending` part déjà ENTIÈRE (c'est une modification du poste) ; une fiche en
  /// `conflict` attend sa propre relance (le serveur ajoute alors la vente à SA fiche, ce qui est
  /// juste). Une vente sans bande n'appelle aucune fiche.
  Future<List<LivestockDailyEntry>> _fichesDIdentite(
    List<Sale> ventes,
    Map<String, List<SaleLine>> lignesDeVente,
  ) async {
    final retenues = <String, LivestockDailyEntry>{};

    for (final v in ventes) {
      final jour = DateTime(v.soldAt.year, v.soldAt.month, v.soldAt.day);
      final lots = {
        for (final l in lignesDeVente[v.id] ?? const <SaleLine>[])
          if (l.lotId != null) l.lotId!,
      };

      for (final lot in lots) {
        final fiche =
            await (_db.select(_db.livestockDailyEntries)..where(
                  (t) => Expression.and([
                    t.lotId.equals(lot),
                    t.entryDate.equals(jour),
                    t.syncStatus.equalsValue(SyncStatus.synced),
                  ]),
                ))
                .getSingleOrNull();
        if (fiche != null) retenues[fiche.id] = fiche;
      }
    }

    return retenues.values.toList();
  }

  /// Refus encore ouverts, le plus récent d'abord.
  Future<List<SyncConflict>> conflits() {
    return (_db.select(_db.syncConflicts)..orderBy([
          (t) =>
              OrderingTerm(expression: t.detectedAt, mode: OrderingMode.desc),
        ]))
        .get();
  }

  /// Fiche fournisseur créée, modifiée ou archivée au poste.
  ///
  /// ⚠️ **L'E-MAIL NE PART PAS** : le formulaire n'a pas ce champ, et un poste qui ne
  /// l'envoie pas ne doit pas effacer celui du serveur.
  Map<String, dynamic> _fournisseurEnJson(Supplier f) => {
    'id': f.id,
    'name': f.name,
    'category': f.category,
    'phone': f.phone,
    'address': f.address,
    'is_active': f.isActive,
  };

  /// Fiche client créée, modifiée ou archivée au poste.
  ///
  /// ⚠️ **LE PLAFOND DE CRÉDIT NE PART PAS** : le poste ne le saisit pas, et ne doit pas
  /// pouvoir le relever.
  Map<String, dynamic> _clientEnJson(Customer c) => {
    'id': c.id,
    'name': c.name,
    'phone': c.phone,
    'email': c.email,
    'city': c.city,
    'is_active': c.isActive,
  };

  /// Courrier saisi, modifié ou archivé au poste.
  ///
  /// ⚠️ **ARCHIVER = `{id, is_active: false}` SEULEMENT** (contrat 15.23) : les autres
  /// champs ne sont pas lus. ⚠️ **LA RÉFÉRENCE NE PART JAMAIS** : le serveur l'attribue.
  Map<String, dynamic> _courrierEnJson(Mail m) => m.isActive
      ? {
          'id': m.id,
          'type': m.type,
          'subject': m.subject,
          'party': m.party,
          'mail_date': m.mailDate == null ? null : _jour(m.mailDate!),
          'is_active': true,
        }
      : {'id': m.id, 'is_active': false};

  /// Document archivé saisi, modifié ou retiré au poste.
  ///
  /// ⚠️ **RETIRER = `{id, is_active: false}` SEULEMENT** (contrat 15.24) : les autres champs
  /// ne sont pas lus. ⚠️ **AUCUN STATUT NE PART** : il se déduit de l'échéance, des deux côtés.
  Map<String, dynamic> _archiveEnJson(ArchivedDocument a) => a.isActive
      ? {
          'id': a.id,
          'title': a.title,
          'category': a.category,
          'archived_date': a.archivedDate == null
              ? null
              : _jour(a.archivedDate!),
          'expiry_date': a.expiryDate == null ? null : _jour(a.expiryDate!),
          'is_active': true,
        }
      : {'id': a.id, 'is_active': false};

  /// Document administratif saisi, modifié ou retiré au poste.
  ///
  /// ⚠️ **RETIRER = `{id, is_active: false}` SEULEMENT** (contrat 15.25) : les autres champs
  /// ne sont pas lus. Le statut part tel quel (`signe` | `en_attente`) ; absent, le serveur
  /// conserverait l'existant — le poste ne l'omet donc que si la colonne est vide.
  Map<String, dynamic> _documentEnJson(AdministrativeDocument d) => d.isActive
      ? {
          'id': d.id,
          'title': d.title,
          'type': d.type,
          'beneficiary': d.beneficiary,
          'doc_date': d.docDate == null ? null : _jour(d.docDate!),
          if (d.status != null) 'status': d.status,
          'is_active': true,
        }
      : {'id': d.id, 'is_active': false};

  /// Avance reçue au poste : « tant, de ce client, dans ce compte, ce jour ». Ni solde de
  /// trésorerie ni écriture ne partent — le serveur entre l'argent dans les DEUX livres
  /// et passe D 5xx / C 419. `amount_used` ne part jamais. `device_id` voyage à la racine.
  Map<String, dynamic> _avanceEnJson(CustomerAdvance a) => {
    'id': a.id,
    'customer_id': a.customerId,
    'treasury_account_id': a.treasuryAccountId,
    'amount': a.amount,
    'advance_date': a.advanceDate == null ? null : _jour(a.advanceDate!),
    'payment_mode': a.paymentMode,
    'motif': a.motif,
  };

  /// Imputation : « tant de cette avance sur cette créance ». Ni plafond, ni reste, ni
  /// `amount_paid` : le serveur les recalcule. La créance se désigne par `receivable_id`
  /// OU `sale_id` — la clé absente n'est pas envoyée.
  Map<String, dynamic> _imputationEnJson(ImputationAvance i) => {
    'id': i.id,
    'customer_advance_id': i.customerAdvanceId,
    if (i.receivableId != null) 'receivable_id': i.receivableId,
    if (i.saleId != null) 'sale_id': i.saleId,
    'amount': i.amount,
    'imputation_date': _jour(i.imputationDate),
  };

  /// Règlement fournisseur : ni imputation ni solde ne partent, seulement le fait.
  Map<String, dynamic> _reglementEnJson(ReglementFournisseur r) => {
    'id': r.id,
    'supplier_id': r.supplierId,
    'treasury_account_id': r.treasuryAccountId,
    'amount': r.amount,
    'payment_date': _jour(r.paymentDate),
  };

  /// Retour fournisseur demandé au poste : « cet achat est retourné, pour ce motif, tel
  /// jour ». Ni ligne, ni quantité, ni stock, ni dette : l'annulation est COMPLÈTE et le
  /// serveur choisit les lignes. `device_id` voyage à la racine.
  Map<String, dynamic> _retourEnJson(RetourFournisseur r) => {
    'id': r.id,
    'purchase_id': r.purchaseId,
    'reason': r.reason,
    'return_date': _jour(r.returnDate),
  };

  /// Remboursement reçu d'un fournisseur : « tant, de celui-ci, sur ce compte ». Le plafond
  /// et les deux livres de trésorerie sont l'affaire du serveur.
  Map<String, dynamic> _remboursementEnJson(RemboursementFournisseur r) => {
    'id': r.id,
    'supplier_id': r.supplierId,
    'treasury_account_id': r.treasuryAccountId,
    'amount': r.amount,
    'refund_date': _jour(r.refundDate),
  };

  /// Produit créé ou modifié au poste.
  ///
  /// ⚠️ **LA QUANTITÉ PART TELLE QUELLE ET LE SERVEUR NE L'UTILISE QU'À LA CRÉATION** :
  /// en modification il l'ignore (un stock se corrige par un ajustement). Le SKU
  /// envoyé est provisoire — le serveur engendre le définitif.
  Map<String, dynamic> _produitEnJson(Product p) => {
    'id': p.id,
    'sku': p.sku,
    'name': p.name,
    'description': p.description,
    'category_id': p.categoryId,
    'species_id': p.speciesId,
    'unit': p.unit,
    'pricing_mode': p.pricingMode,
    'price_min': p.priceMin,
    'price_max': p.priceMax,
    'tva_rate': p.tvaRate,
    'stock_qty': p.stockQty,
    'alert_threshold': p.alertThreshold ?? 0,
    'updated_at': p.updatedAt?.toUtc().toIso8601String(),
  };

  /// Fiche modifiée au poste : le FAIT saisi, jamais un dérivé.
  ///
  /// 🔴→✅ TICKET F0.95 (contrat 15.40) :
  ///  - ⚠️⚠️ `effectif_final` et `cat_eff_*` NE PARTENT JAMAIS : ce sont des valeurs DÉRIVÉES que
  ///    le serveur recalcule (il ignore `effectif_final` et neutralise les `cat_eff_*` d'une
  ///    bande à chaîne ; SANS chaîne il les ÉCRIRAIT, et la copie locale, peut-être périmée,
  ///    écraserait une saisie web). `cat_eff_4` non plus ;
  ///  - les mouvements par catégorie (`mort_*`, `don_*`) et le passage partent quand ils sont
  ///    CONNUS ; une valeur inconnue (null) n'est pas envoyée (le serveur traite null comme une
  ///    clé absente : elle n'efface rien) ;
  ///  - `mort` = somme des `mort_*` et `don` = somme des `don_*` quand la ventilation est complète
  ///    (le serveur refuse sinon « ventilation incohérente ») ;
  ///  - `cat_depart_*` seulement sur la fiche TÊTE de chaîne ([tete]) ;
  ///  - `effectif_m/f/sevres/smeres` (SAISIS, QC5) seulement s'ils sont connus.
  Map<String, dynamic> _ficheEnJson(
    LivestockDailyEntry f, {
    required bool tete,
  }) {
    int? somme(int? a, int? b, int? c) =>
        (a == null || b == null || c == null) ? null : a + b + c;
    final connus = <String, int?>{
      'mort_repro': f.mortRepro,
      'mort_sevre': f.mortSevre,
      'mort_jeune': f.mortJeune,
      'don_repro': f.donRepro,
      'don_sevre': f.donSevre,
      'don_jeune': f.donJeune,
      'passage_sevre_jeune': f.passageSevreJeune,
      if (tete) ...{
        'cat_depart_repro': f.catDepartRepro,
        'cat_depart_sevre': f.catDepartSevre,
        'cat_depart_jeune': f.catDepartJeune,
      },
      'effectif_m': f.effectifM,
      'effectif_f': f.effectifF,
      'effectif_sevres': f.effectifSevres,
      'effectif_smeres': f.effectifSmeres,
    };
    return {
      'id': f.id,
      'lot_id': f.lotId,
      'entry_date': _jour(f.entryDate),
      'achat': f.achat,
      'ne': f.ne,
      'mort': somme(f.mortRepro, f.mortSevre, f.mortJeune) ?? f.mort,
      'vente': f.vente,
      'don': somme(f.donRepro, f.donSevre, f.donJeune) ?? f.don,
      'ponte_total': f.ponteTotal,
      'ponte_casses': f.ponteCasses,
      'feed_qty_kg': f.feedQtyKg,
      'weight_sample_avg_g': f.weightSampleAvgG,
      for (final MapEntry(:key, :value) in connus.entries)
        key: ?value,
      'device_id': f.deviceId,
      'updated_at': f.updatedAt.toUtc().toIso8601String(),
    };
  }

  /// Ticket S-T9 — la SAISIE d'une fiche telle qu'elle part, sans la vente (que les ventes inscrivent au serveur) ni
  /// l'horodatage et le poste : deux versions de même saisie ont la même empreinte.
  String _saisieDeFiche(LivestockDailyEntry f, {required bool tete}) => jsonEncode(
    _ficheEnJson(f, tete: tete)..removeWhere((cle, _) => const {'vente', 'updated_at', 'device_id'}.contains(cle)),
  );

  /// F0.90 — fiche réduite à son IDENTITÉ (voir [_fichesDIdentite]). `lot_id` et `entry_date`
  /// sont exigés par le validateur du serveur ; AUCUNE autre clé : chacune écraserait la valeur
  /// serveur (`fill`), et c'est précisément ce qu'on évite.
  Map<String, dynamic> _ficheIdentiteEnJson(LivestockDailyEntry f) => {
    'id': f.id,
    'lot_id': f.lotId,
    'entry_date': _jour(f.entryDate),
  };

  /// ⚠️⚠️ LE POSTE ENVOIE UNE INTENTION, PAS UN RESULTAT. Ni le stock, ni la
  /// caisse, ni la dette, ni l'ecriture ne sont calcules ici : le serveur les
  /// rejoue tous les cinq a la reception (`RecordPurchaseAction`). Recalculer
  /// un PMP localement ferait diverger deux valorisations de stock.
  ///
  /// ⚠️ `purchase_date` VIENT DU POSTE : une livraison recue mardi et
  /// synchronisee jeudi appartient a mardi — meme regle que `sold_at` pour les
  /// ventes (ticket 14.71).
  Map<String, dynamic> _achatEnJson(Purchase a, List<PurchaseLine> lignes) => {
    'id': a.id,
    'supplier_id': a.supplierId,
    'payment_mode': a.paymentMode,
    'treasury_account_id': a.treasuryAccountId,
    'amount_paid': a.amountPaid,
    'purchase_date': _jour(a.purchaseDate),
    // 🔴→✅ Ticket S-T12 — l'INSTANT de l'achat (heure du Bénin ramenée en UTC), comme `sold_at` pour une vente : le
    // serveur date l'entrée en stock de l'achat, plus de sa réception. Sans lui, un achat fait AVANT un comptage et
    // arrivé APRÈS lui entrait une seconde fois dans des rayons qui le contenaient déjà.
    'purchased_at': HeureBenin.versInstant(a.purchaseDate).toIso8601String(),
    'lines': [
      for (final l in lignes)
        {'product_id': l.productId, 'qty': l.qty, 'unit_price': l.unitPrice},
    ],
  };

  /// ⚠️ LE JOUR PART EN 'Y-m-d', jamais en instant : le serveur cherche le
  /// pointage par le couple (employe, JOUR), et un decalage horaire le ferait
  /// porter sur la veille.
  Map<String, dynamic> _pointageEnJson(AttendanceRecord p) => {
    'id': p.id,
    'employee_id': p.employeeId,
    'attendance_date': _jour(p.attendanceDate),
    'check_in': p.checkIn,
    'check_out': p.checkOut,
    'status': p.status,
  };

  /// Ticket 15.46 — transfert entre bandes tel que le serveur le rejoue (`TransferBetweenLotsAction`).
  /// Ticket BS1 — bande telle que `SyncController::pushLots` la valide (snake_case). ⚠️ L'EFFECTIF N'Y FIGURE PAS : il
  /// est celui des fiches (cascade du serveur). Seule une CORRECTION explicite de l'exploitant (« Modifier la Bande »)
  /// part, sous `effectif_corrige`. Le code, l'espèce, l'effectif initial et la date de création ne se modifient pas :
  /// ils ne servent qu'à la création.
  Map<String, dynamic> _bandeEnJson(LivestockLot b) => {
    'id': b.id,
    'code': b.code,
    'species_id': b.speciesId,
    'stage': b.stage,
    'created_date': b.createdDate == null ? null : _jour(b.createdDate!),
    'initial_quantity': b.initialQuantity,
    'acquisition_cost': b.acquisitionCost,
    'product_id': b.productId,
    'status': b.status,
    'is_active': b.isActive,
    if (b.effectifCorrige != null) 'effectif_corrige': b.effectifCorrige,
    // BS-Q7 : le geste explicite de restauration (le serveur ne restaure JAMAIS sur le seul `is_active: true`).
    if (b.restauree) 'restauree': true,
    'device_id': _deviceId,
  };

  /// Ticket BS3 — reproducteur tel que `SyncController::pushAnimals` le valide (snake_case). La catégorie reste
  /// « reproducteur » (seul suivi nominatif) ; l'effectif d'une bande n'y figure JAMAIS (aucune cascade).
  Map<String, dynamic> _sujetEnJson(Sujet a) => {
    'id': a.id,
    'identifier': a.identifier,
    'species_id': a.speciesId,
    'lot_id': a.lotId,
    'category': a.category,
    'sex': a.sex,
    'breed': a.breed,
    'birth_date': a.birthDate == null ? null : _jour(a.birthDate!),
    'entry_date': a.entryDate == null ? null : _jour(a.entryDate!),
    'origin': a.origin,
    'cage': a.cage,
    'status': a.status,
    'exit_date': a.exitDate == null ? null : _jour(a.exitDate!),
    'exit_reason': a.exitReason,
    'is_active': a.isActive,
    'device_id': _deviceId,
  };

  Map<String, dynamic> _transfertEnJson(LivestockTransfer t) => {
    'id': t.id,
    'source_lot_id': t.sourceLotId,
    'target_lot_id': t.targetLotId,
    'transfer_date': _jour(t.transferDate),
    'quantity': t.quantity,
    'categorie': t.categorie,
    'constitution': t.constitution,
    'motif': t.motif,
    'is_active': t.isActive,
    'device_id': t.deviceId,
    'updated_at': t.updatedAt.toUtc().toIso8601String(),
  };

  /// Ticket H8b — entrée d'infirmerie telle que `SyncController::pushInfirmerie` la valide (snake_case).
  /// Pour une entrée déjà connue du serveur, seul `status` est relu (dernier écrivain gagne).
  Map<String, dynamic> _infirmerieEnJson(InfirmaryRecord e) => {
    'id': e.id,
    'lot_id': e.lotId,
    'sujet_ref': e.sujetRef,
    'motif': e.motif,
    'isolation_level': e.isolationLevel,
    'entry_date': _jour(e.entryDate),
    'status': e.status,
    'device_id': e.deviceId,
    'updated_at': e.updatedAt.toUtc().toIso8601String(),
  };

  /// Ticket H8b — intervention planifiée telle que `SyncController::pushCalendrierVeterinaire` la valide.
  Map<String, dynamic> _interventionEnJson(VeterinaryCalendarEvent e) => {
    'id': e.id,
    'lot_id': e.lotId,
    'task_type': e.taskType,
    'scheduled_date': _jour(e.scheduledDate),
    'status': e.status,
    'device_id': e.deviceId,
    'updated_at': e.updatedAt.toUtc().toIso8601String(),
  };

  /// Ticket H9b — ration telle que `RecordParametresElevageFromDeviceAction::ration()` la valide :
  /// `ration_g_per_day` ENTIER (`integer|min:1`), `is_active = false` = archivage.
  static Map<String, dynamic> _rationEnJson(FeedRationStandard r) => {
    'id': r.id,
    'species_code': r.speciesCode,
    'stage_label': r.stageLabel,
    'ration_g_per_day': r.rationGPerDay.round(),
    'is_active': r.isActive,
  };

  /// Ticket H9b — échéance de prophylaxie (`prophylaxie()` de l'Action). Les bornes de cycle ne partent pas :
  /// le serveur ne les lit pas (le web ne les saisit pas non plus).
  static Map<String, dynamic> _echeanceEnJson(ProphylaxisScheduleStandard e) => {
    'id': e.id,
    'species_code': e.speciesCode,
    'period_label': e.periodLabel,
    'treatment': e.treatment,
    'product_recommended': e.productRecommended,
    'dosage': e.dosage,
    'withdrawal_days': e.withdrawalDays,
    'is_active': e.isActive,
  };

  /// Ticket H9b — type de provende (`provende()` de l'Action) : l'espèce part par son IDENTIFIANT
  /// (`exists:livestock_species,id`), jamais par son libellé.
  static Map<String, dynamic> _provendeEnJson(FeedType p) => {
    'id': p.id,
    'name': p.name,
    'species_id': p.speciesId,
    'standard_bag_weight_kg': p.standardBagWeightKg,
    'price_per_kg': p.pricePerKg,
    'is_active': p.isActive,
  };

  /// Ticket H9b — les neuf formats (`numerotation()` de l'Action). L'`id` n'est lu par aucune règle : il
  /// sert au serveur à nommer la ligne dans un REFUS (`rejected[].id`), sans quoi le refus n'aurait pas de
  /// destinataire au poste.
  static Map<String, dynamic> _numerotationEnJson(ElevageNumberingSetting n) =>
      {
        'id': ParametresElevageCles.numerotation,
        'bande_format': n.bandeFormat,
        'lapine_prefix': n.lapinePrefix,
        'male_prefix': n.malePrefix,
        'truie_prefix': n.truiePrefix,
        'verrat_prefix': n.verratPrefix,
        'portee_prefix': n.porteePrefix,
        'volaille_prefix': n.volaillePrefix,
        'parc_prefix': n.parcPrefix,
        'escargot_prefix': n.escargotPrefix,
      };

  /// Ticket H9b — `{rappel_soins_jours}`, SEUL champ de l'entreprise accepté par ce canal (`rappelSoins()`).
  /// ⚠️ Aucune donnée d'identité ne part : elle reste un référentiel du serveur.
  static Map<String, dynamic> _rappelSoinsEnJson(CompanySetting e) => {
    'id': ParametresElevageCles.rappelSoins,
    'rappel_soins_jours': e.rappelSoinsJours,
  };

  /// Ticket MOD1 — `{id, species_code, is_enabled}` : la VALEUR choisie, pas une bascule (`RecordModulesConfigFromDeviceAction`).
  static Map<String, dynamic> _moduleEnJson(ModulesConfigData m) => {
    'id': m.speciesCode,
    'species_code': m.speciesCode,
    'is_enabled': m.isEnabled,
  };

  Map<String, dynamic> _venteEnJson(Sale v, List<SaleLine> lignes) => {
    'id': v.id,
    'customer_id': v.customerId,
    'payment_mode': v.paymentMode,
    'subtotal': v.subtotal,
    'discount': v.discount,
    'total': v.total,
    'cash_received': v.cashReceived,
    'change_due': v.changeDue,
    'status': v.status,
    // 🔴→✅ TICKET 14.71 / F0.31 — L'HEURE REELLE DU COMPTOIR.
    //
    // ⚠️⚠️ ELLE N'ETAIT PAS ENVOYEE, et le serveur n'avait meme pas de
    // colonne ou la mettre : il datait la vente de sa RECEPTION. Une vente
    // encaissee hors ligne le 28/07 et remontee le 02/08 passait donc son
    // ecriture SYSCOHADA en aout et sortait les tetes de la fiche du 02/08.
    // C'est le defaut le plus couteux qu'un poste hors ligne puisse avoir :
    // il ne se voit que sur les postes qui restent longtemps deconnectes,
    // c'est-a-dire exactement ceux pour lesquels le mode hors ligne existe.
    //
    // ⚠️ ENVOYEE EN HEURE LOCALE, SANS CONVERSION UTC, comme
    // `expense_date` : le serveur tourne desormais en Africa/Porto-Novo
    // (meme ticket). Convertir en UTC decalerait d'une heure et ferait
    // basculer de jour toute vente d'avant 01h00 — le defaut que ce
    // ticket corrige, reintroduit par l'autre bout.
    'sold_at': _instant(v.soldAt),
    'device_id': v.deviceId,
    'updated_at': v.updatedAt.toUtc().toIso8601String(),
    'lines': lignes
        .map(
          (l) => {
            'product_id': l.productId,
            'lot_id': l.lotId,
            'qty': l.qty,
            'unit_price': l.unitPrice,
            'manual_total_amount': l.manualTotalAmount,
          },
        )
        .toList(),
  };

  /// Saillie declaree au poste.
  ///
  /// ⚠️ **SEULS LES CINQ CHAMPS DE LA DECLARATION PARTENT.** Statut, dates
  /// d'echeance et resultats de mise bas sont calcules ou saisis cote serveur :
  /// les envoyer laisserait croire que le poste peut les corriger, alors que
  /// ce canal n'ouvre que la CREATION.
  Map<String, dynamic> _saillieEnJson(LivestockReproductionEvent e) => {
    'id': e.id,
    'lot_id': e.lotId,
    'mother_ref': e.motherRef,
    'sire_ref': e.sireRef,
    'saillie_date': e.saillieDate == null ? null : _jour(e.saillieDate!),
    // Ticket H7 — étapes du cycle saisies au poste, appliquées par le serveur à un cycle déjà connu (seules les
    // valeurs renseignées : un `null` n'efface rien côté serveur).
    'palpation_date': e.palpationDate == null ? null : _jour(e.palpationDate!),
    'mise_bas_date_actual': e.miseBasDateActual == null ? null : _jour(e.miseBasDateActual!),
    'nes_vivants': e.nesVivants,
    'nes_morts': e.nesMorts,
    'status': e.status,
    'device_id': e.deviceId,
  };

  /// 🔴→✅ Ticket DEP4 — la dépense part AVEC SES LIGNES dans le même document (`lines` : `id`, `label`,
  /// `charge_account_id`, `amount`) et son TOTAL (`amount`, que le serveur contrôle contre la somme des lignes) ; le
  /// serveur la rejoue par `SaisieDepenseAction` et passe SA pièce. Montants entiers.
  ///
  /// ⚠️ UNE DÉPENSE SANS LIGNE (poste qui n'a pas pu convertir la sienne à la migration, plan local absent) part À PLAT
  /// (`label`, `category`, `amount`) : le serveur, déployé avant les postes, la convertit en UNE ligne.
  Map<String, dynamic> _depenseEnJson(Expense d, List<ExpenseLine> lignes) => {
    'id': d.id,
    'expense_date': _jour(d.expenseDate),
    'treasury_account_id': d.treasuryAccountId,
    if (lignes.isEmpty) ...{
      'label': d.label,
      'category': d.category,
      'amount': d.amount,
    } else ...{
      'payment_mode': d.paymentMode,
      'cost_center_id': d.costCenterId,
      'supplier_id': d.supplierId,
      'beneficiary': d.beneficiary,
      'amount': d.amount,
      'lines': [
        for (final l in lignes)
          {
            'id': l.id,
            'label': l.label,
            'charge_account_id': l.chargeAccountId,
            'amount': l.amount == l.amount.roundToDouble() ? l.amount.round() : l.amount,
          },
      ],
    },
    // Ticket U14 — archivage fait au poste (`DepensesRepository.archiver`), rejoué par le serveur comme
    // `archiveExpense()` du web. Une modification part avec les champs de la ligne (dernier écrivain gagne).
    'is_active': d.isActive,
    'device_id': d.deviceId,
  };

  /// Tickets AV1 / AV2 — la DEMANDE de retour : ce que le serveur lit dans `pushCreditNotes`. ⚠️ Ni numéro (`AV-AAAA-NNN`,
  /// attribué par le serveur) ni écriture ni stock. `credit_date` = le jour du FAIT, en heure murale du Bénin sans
  /// conversion UTC (même règle que `sold_at`) ; `status` = `traite` pour « Marquer comme traité » (une seule fois côté
  /// serveur).
  Map<String, dynamic> _avoirEnJson(AvoirClient a) => {
    'id': a.id,
    'sale_id': a.saleId,
    'product_id': a.productId,
    'qty': a.qty,
    'amount': a.amount,
    'reason': a.reason,
    'decision': a.decision,
    'inspection_notes': a.inspectionNotes,
    'status': a.status,
    'credit_date': _instant(a.createdAt),
    'device_id': a.deviceId,
  };

  /// Ticket DEV — un devis tel qu'il est (le FAIT) : `pushQuotes` le rejoue par `SaisieDevisAction`. ⚠️ Le numéro
  /// `DEV-AAAA-NNN` ne part JAMAIS (le serveur l'attribue, le poste le reçoit au tirage) ; un devis archivé repart entier
  /// (`is_active: false`) ; `status` avance d'un cycle que le serveur parcourt pas à pas.
  Map<String, dynamic> _devisEnJson(Quote d) => {
    'id': d.id,
    'customer_id': d.customerId,
    'articles_description': d.articlesDescription,
    'amount': d.amount,
    'tva_rate': d.tvaRate,
    'validity_days': d.validityDays,
    'quote_date': _jour(d.quoteDate),
    'note': d.note,
    'status': d.status,
    'is_active': d.isActive,
    'device_id': d.deviceId,
  };

  Map<String, dynamic> _soinEnJson(VeterinaryRecord s) => {
    'id': s.id,
    'lot_id': s.lotId,
    'action_type': s.actionType,
    'product_used': s.productUsed,
    'dose': s.dose,
    'vet_name': s.vetName,
    'symptomes': s.symptomes,
    'cost': s.cost,
    'record_date': _jour(s.recordDate),
    // ⚠️ Le délai part avec le soin : c'est lui qui déclenche la création
    // de la période de rémanence côté serveur. L'omettre laisserait la
    // bande vendable malgré le traitement.
    'withdrawal_days': s.withdrawalDays,
    // Ticket U3 — archivage au poste : le serveur archive un soin connu, ou crée archivé un soin saisi puis
    // archivé hors ligne (`pushVeterinaryRecords`).
    'is_active': s.isActive,
    'device_id': s.deviceId,
    'updated_at': s.updatedAt.toUtc().toIso8601String(),
  };

  /// ⚠️⚠️ **`client_ref` EST LA CLÉ DE L'ACCUSÉ DE RÉCEPTION** (ticket
  /// 14.74). Sans elle, le serveur acquittait avec le `product_id` : le poste
  /// ne se reconnaissait pas dans la réponse, laissait l'ajustement en attente
  /// et le RENVOYAIT à chaque tirage — chaque renvoi rejouant le décrément de
  /// stock et une nouvelle écriture de perte.
  Map<String, dynamic> _ajustementEnJson(StockAdjustment a) => {
    'id': a.id,
    'client_ref': a.id,
    'product_id': a.productId,
    'type': a.type,
    'quantity': a.quantity,
    'reference_type': a.referenceType,
    'reason': a.reason,
    // Ticket U10 — le JOUR du mouvement (`Y-m-d`, heure murale) : le serveur date un « Ajout Manuel » de ce jour,
    // comme le web (`Carbon::parse($addDate)`) ; il ne le lit pas pour un écart d'inventaire (rejoué à réception).
    'movement_date': _jour(a.movementDate),
    'device_id': a.deviceId,
    'updated_at': a.updatedAt.toUtc().toIso8601String(),
    // 🔴→✅ Ticket S-T10 — inventaire : la QUANTITÉ COMPTÉE et l'INSTANT du comptage (UTC, avec son fuseau : le
    // serveur le ramène à son heure, S-T11). Le serveur calcule l'écart contre son grand livre à cet instant ;
    // `type` + `quantity` (écart LOCAL) ne servent plus qu'à un serveur ancien, qui ignore ces deux clés.
    if (a.countedQuantity != null) ...{
      'counted_quantity': a.countedQuantity,
      'counted_at': HeureBenin.versInstant(a.movementDate).toIso8601String(),
    },
  };

  static List<Map<String, dynamic>> _lignes(Object? brut) =>
      (brut as List?)?.cast<Map<String, dynamic>>() ?? const [];

  static bool _bool(Object? v) => v == true || v == 1 || v == '1';

  static double? _reel(Object? v) =>
      v == null ? null : double.tryParse(v.toString());

  static int? _entier(Object? v) =>
      v == null ? null : int.tryParse(v.toString().split('.').first);

  /// Une date MÉTIER servie, en heure murale du Bénin (ticket S-T11, [HeureBenin.lire]).
  ///
  /// ⚠️⚠️ Une colonne DATE pure (`entry_date`, `record_date`) arrive en `2026-08-17` et se lit telle quelle. Mais une
  /// date qu'Eloquent sérialise en instant — `due_date` d'une créance, `advance_date` d'une avance, servies
  /// `2026-04-01T23:00:00Z` depuis un serveur en Africa/Porto-Novo — se lirait **la veille** gardée en UTC (F0.x),
  /// et encore la veille ramenée par `toLocal()` sur un Windows réglé en UTC ou à New York (S-T11 : écarts du
  /// contrôle de cohérence sur les soins et les avances, vus par l'essai S-T9). Elle est donc ramenée à l'heure
  /// du BÉNIN, jamais à celle de Windows.
  static DateTime? _date(Object? v) => HeureBenin.lire(v);

  /// Un INSTANT technique servi (`updated_at`, `created_at` du journal) : gardé comme instant — il ne sert qu'à
  /// ordonner ou départager, jamais à dire un jour métier.
  static DateTime? _instantTechnique(Object? v) => HeureBenin.lireInstant(v);

  /// Format `Y-m-d` attendu par le serveur pour une DATE pure.
  ///
  /// ⚠️ Envoyer un ISO complet ferait comparer `2026-08-17T00:00:00` à une
  /// colonne DATE : la comparaison en chaîne échoue selon le pilote, et la
  /// fiche du jour serait dupliquée au lieu d'être mise à jour.
  /// Horodatage LOCAL `Y-m-d H:i:s`, sans fuseau — voir `_venteEnJson`.
  static String _instant(DateTime d) =>
      '${_jour(d)} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';

  static String _jour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Ticket H9b — identifiants sous lesquels le serveur acquitte (ou refuse) les deux LIGNES UNIQUES des
/// Paramètres Élevage (`RecordParametresElevageFromDeviceAction::numerotation()` rend `elevage_numbering`,
/// `rappelSoins()` rend `company_settings`). Le poste les envoie aussi comme `id` de la ligne : un refus a
/// ainsi un destinataire.
abstract final class ParametresElevageCles {
  static const numerotation = 'elevage_numbering';
  static const rappelSoins = 'company_settings';
}
