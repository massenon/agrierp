import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show Listenable;

import 'sync_engine.dart';

/// Ticket H13 (décisions D-SYNC-3 et B2 du 19/10/2026) — synchronisation déclenchée sans geste de l'utilisateur.
///
/// Les déclencheurs :
///  - l'**ouverture de la session** (`demarrer(aussitot: true)`, ticket S-T3) ;
///  - le **retour du réseau** (passage de « aucune liaison » à une liaison) ;
///  - l'**intervalle** (5 min par défaut depuis S-T3, réglable dans Paramètres du poste) ;
///  - un **geste important** ([gestes] : vente à la caisse, fiche journalière, soin — S-T3), après un délai
///    d'agrégation ([delaiAgregation]) : dix ventes en une minute font une ou deux synchronisations, pas dix ;
///  - la **fermeture** de l'application ([avantFermeture]).
///
/// ⚠️ **LES RÉESSAIS NE CONCERNENT QUE LES ÉCHECS RÉESSAYABLES** ([estReessayable] : échec réseau et, depuis
/// S-T1, erreur 5xx du serveur — un bogue serveur se corrige sans le poste) : 30 s, 2 min, 5 min, 15 min, puis
/// 1 h. Un refus du serveur — enregistrement rejeté, 4xx — n'est pas réessayé : il reste en « Refusés »
/// jusqu'à correction (D-SYNC-3). Réessayer un refus toutes les 30 s ne le corrigerait pas, et martèlerait le
/// serveur.
///
/// ⚠️⚠️ **401 / 403 : LA SYNCHRONISATION AUTOMATIQUE S'ARRÊTE** ([suspendue], ticket S-T1) jusqu'à une nouvelle
/// connexion. Une session expirée ou un compte désactivé ne se répare pas en retentant ; chaque tentative serait
/// un refus de plus au journal du serveur. Les saisies `pending` restent sur le poste ; « Synchroniser
/// maintenant » reste possible et dit pourquoi (message d'[EchecSynchronisation]). Une instance vit le temps
/// d'UNE session (`SocleAccueil` la crée à l'ouverture, l'arrête au démontage) : la reconnexion en crée une
/// neuve, qui synchronise aussitôt.
///
/// ⚠️ **HORS LIGNE N'EST PAS UN ÉCHEC.** Un [SyncOutcome.horsLigne] ne programme aucun réessai : c'est le
/// retour du réseau qui relancera. Les erreurs ne s'affichent jamais ici (aucune erreur rouge sans geste de
/// l'utilisateur) ; la barre supérieure se relit par [onTermine], et un refus se voit à son badge rouge.
///
/// ⚠️ **JAMAIS DEUX SYNCHRONISATIONS EN MÊME TEMPS** : [SyncEngine.synchroniser] rend la tentative en cours
/// à un second appelant (bouton « Synchroniser maintenant » pendant un déclenchement automatique).
class SynchronisationAutomatique {
  SynchronisationAutomatique({
    required Future<SyncOutcome> Function() synchroniser,
    required Stream<List<ConnectivityResult>> changementsReseau,
    this.intervalle = intervalleParDefaut,
    this.onTermine,
    this.gestes,
    this.delaiAgregation = delaiAgregationParDefaut,
  }) : // Paramètres NOMMÉS : Dart interdit `this._synchroniser` (voir `SyncEngine`).
       // ignore: prefer_initializing_formals
       _synchroniser = synchroniser,
       // ignore: prefer_initializing_formals
       _changementsReseau = changementsReseau;

  /// Ticket S-T3 — 5 min, comme la note TATACORA (15 min jusqu'ici).
  static const intervalleParDefaut = Duration(minutes: 5);

  /// Ticket S-T3 — délai entre un geste important et la synchronisation qu'il déclenche : les gestes de ce
  /// délai partent ensemble.
  static const delaiAgregationParDefaut = Duration(seconds: 5);

  /// Délais entre deux réessais après un échec RÉSEAU ou une 5xx (S-T1) ; au-delà du dernier, on reste à 1 h.
  static const reessais = [
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  /// Durée maximale de la synchronisation de fermeture : l'utilisateur qui quitte n'attend pas un serveur
  /// injoignable au-delà.
  static const delaiFermeture = Duration(seconds: 15);

  final Future<SyncOutcome> Function() _synchroniser;
  final Stream<List<ConnectivityResult>> _changementsReseau;
  final Duration intervalle;

  /// Appelé après chaque tentative automatique aboutie (refus compris) : la barre et le Centre se relisent.
  final void Function()? onTermine;

  /// Ticket S-T3 — point unique des gestes importants (`GestesImportants`), écouté de [demarrer] à [arreter].
  /// Les dépôts le signalent sans rien savoir du moteur.
  final Listenable? gestes;
  final Duration delaiAgregation;

  StreamSubscription<List<ConnectivityResult>>? _abonnement;
  Timer? _minuterie;
  Timer? _reessai;
  Timer? _agregation;
  bool? _enLigne;
  bool _enCours = false;

  /// Un geste est arrivé pendant une tentative : il en relance une à la fin de celle-ci (ses lignes ont pu
  /// être lues avant d'exister).
  bool _gesteEnAttente = false;

  /// Ticket S-T1 — vrai après un 401 / 403 : plus aucune tentative automatique jusqu'à la fin de la session.
  bool get suspendue => _suspendue;
  bool _suspendue = false;

  /// Nombre d'échecs réseau consécutifs ; remis à zéro par une tentative aboutie.
  int get echecsConsecutifs => _echecs;
  int _echecs = 0;

  /// Délai du réessai programmé, `null` s'il n'y en a pas.
  Duration? get reessaiProgramme => _reessai?.isActive == true ? _delaiReessai : null;
  Duration? _delaiReessai;

  bool get demarree => _minuterie != null;

  /// [aussitot] (ticket S-T3) : une première tentative tout de suite — l'ouverture de la session.
  void demarrer({bool aussitot = false}) {
    if (demarree) return;
    _minuterie = Timer.periodic(intervalle, (_) {
      // Un réessai est programmé : l'intervalle ne le court-circuite pas (sinon le palier d'une heure
      // redeviendrait cinq minutes).
      if (_reessai?.isActive == true) return;
      declencher();
    });
    _abonnement = _changementsReseau.listen((etats) {
      final enLigne = etats.any((e) => e != ConnectivityResult.none);
      final retour = enLigne && _enLigne == false;
      _enLigne = enLigne;
      if (retour) declencher();
    });
    gestes?.addListener(_surGeste);
    if (aussitot) declencher();
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
    _reessai?.cancel();
    _reessai = null;
    _agregation?.cancel();
    _agregation = null;
    gestes?.removeListener(_surGeste);
    _abonnement?.cancel();
    _abonnement = null;
  }

  /// Ticket S-T3 — un geste important : une synchronisation après [delaiAgregation], qui emporte aussi les
  /// gestes suivants du même délai. Un réessai programmé n'est pas court-circuité (le serveur vient d'échouer :
  /// c'est le réessai qui emportera la saisie) ; une tentative en cours en relance une à sa fin.
  void _surGeste() {
    if (_suspendue || !demarree || _agregation?.isActive == true) return;
    _agregation = Timer(delaiAgregation, () {
      if (_reessai?.isActive == true) return;
      if (_enCours) {
        _gesteEnAttente = true;
        return;
      }
      declencher();
    });
  }

  /// Une tentative automatique. Ne lève jamais : un échec réessayable ([estReessayable]) programme le réessai
  /// suivant, un 401 / 403 arrête la synchronisation automatique ([suspendue]), tout autre échec attend le
  /// prochain déclencheur.
  Future<void> declencher() async {
    if (_enCours || _suspendue) return;
    _enCours = true;
    _reessai?.cancel();
    _reessai = null;
    try {
      final resultat = await _synchroniser();
      if (!resultat.horsLigne) _echecs = 0;
      onTermine?.call();
    } catch (e) {
      if (e is EchecSynchronisation && e.estSessionRefusee) {
        _suspendre();
      } else if (estReessayable(e)) {
        _programmerReessai();
      } else {
        _echecs = 0;
      }
    } finally {
      _enCours = false;
      if (_gesteEnAttente) {
        _gesteEnAttente = false;
        _surGeste();
      }
    }
  }

  /// Ticket S-T1 — 401 / 403 : plus rien ne part automatiquement pendant cette session.
  void _suspendre() {
    _suspendue = true;
    _echecs = 0;
    _reessai?.cancel();
    _reessai = null;
    _agregation?.cancel();
    _agregation = null;
    _gesteEnAttente = false;
  }

  void _programmerReessai() {
    final delai = reessais[_echecs < reessais.length ? _echecs : reessais.length - 1];
    _echecs++;
    if (!demarree) return;
    _delaiReessai = delai;
    _reessai = Timer(delai, declencher);
  }

  /// Synchronisation de fermeture, bornée à [delai]. Rend `true` si elle a abouti à temps (refus compris).
  /// Un échec ou un dépassement ne bloque pas la fermeture : les saisies restent sur le poste.
  Future<bool> avantFermeture({Duration delai = delaiFermeture}) async {
    try {
      final resultat = await _synchroniser().timeout(delai);
      return !resultat.horsLigne;
    } catch (_) {
      return false;
    }
  }

  /// Ticket S-T1 — échec à RÉESSAYER plus tard : un échec de liaison ([estEchecReseau]), une erreur 5xx du
  /// serveur (bogue ou panne du serveur, qui se corrige sans le poste), ou une 429 (débit dépassé — notamment
  /// après l'isolement d'une ligne fautive, qui coûte une douzaine de requêtes : elle passe d'elle-même). Un
  /// refus (autre 4xx, ou motif dans `rejected`) ne l'est pas.
  static bool estReessayable(Object erreur) {
    if (estEchecReseau(erreur)) return true;
    final statut = switch (erreur) {
      DioException(type: DioExceptionType.badResponse, :final response) => response?.statusCode,
      EchecSynchronisation(:final statut) => statut,
      _ => null,
    };
    return statut != null && (statut == 429 || (statut >= 500 && statut <= 599));
  }

  /// Échec de LIAISON (serveur injoignable, délai dépassé), par opposition à un refus du serveur.
  static bool estEchecReseau(Object erreur) {
    if (erreur is SocketException || erreur is TimeoutException) return true;
    if (erreur is! DioException) return false;
    return switch (erreur.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => true,
      DioExceptionType.unknown => erreur.error is SocketException,
      _ => false,
    };
  }
}
