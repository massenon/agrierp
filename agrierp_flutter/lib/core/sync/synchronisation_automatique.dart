import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import 'sync_engine.dart';

/// Ticket H13 (décisions D-SYNC-3 et B2 du 19/10/2026) — synchronisation déclenchée sans geste de l'utilisateur.
///
/// Trois déclencheurs, et trois seulement :
///  - le **retour du réseau** (passage de « aucune liaison » à une liaison) ;
///  - l'**intervalle** (15 min par défaut, réglable dans Paramètres du poste) ;
///  - la **fermeture** de l'application ([avantFermeture]).
///
/// ⚠️ **LES RÉESSAIS NE CONCERNENT QUE LES ÉCHECS RÉSEAU** (30 s, 2 min, 5 min, 15 min, puis 1 h). Un refus
/// du serveur — enregistrement rejeté, session expirée, droits insuffisants — n'est pas réessayé : il reste
/// en « Refusés » jusqu'à correction (D-SYNC-3). Réessayer un refus toutes les 30 s ne le corrigerait pas, et
/// martèlerait le serveur.
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
  }) : // Paramètres NOMMÉS : Dart interdit `this._synchroniser` (voir `SyncEngine`).
       // ignore: prefer_initializing_formals
       _synchroniser = synchroniser,
       // ignore: prefer_initializing_formals
       _changementsReseau = changementsReseau;

  static const intervalleParDefaut = Duration(minutes: 15);

  /// Délais entre deux réessais après un échec RÉSEAU ; au-delà du dernier, on reste à 1 h.
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

  StreamSubscription<List<ConnectivityResult>>? _abonnement;
  Timer? _minuterie;
  Timer? _reessai;
  bool? _enLigne;
  bool _enCours = false;

  /// Nombre d'échecs réseau consécutifs ; remis à zéro par une tentative aboutie.
  int get echecsConsecutifs => _echecs;
  int _echecs = 0;

  /// Délai du réessai programmé, `null` s'il n'y en a pas.
  Duration? get reessaiProgramme => _reessai?.isActive == true ? _delaiReessai : null;
  Duration? _delaiReessai;

  bool get demarree => _minuterie != null;

  void demarrer() {
    if (demarree) return;
    _minuterie = Timer.periodic(intervalle, (_) {
      // Un réessai est programmé : l'intervalle ne le court-circuite pas (sinon le palier d'une heure
      // redeviendrait un quart d'heure).
      if (_reessai?.isActive == true) return;
      declencher();
    });
    _abonnement = _changementsReseau.listen((etats) {
      final enLigne = etats.any((e) => e != ConnectivityResult.none);
      final retour = enLigne && _enLigne == false;
      _enLigne = enLigne;
      if (retour) declencher();
    });
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
    _reessai?.cancel();
    _reessai = null;
    _abonnement?.cancel();
    _abonnement = null;
  }

  /// Une tentative automatique. Ne lève jamais : un échec réseau programme le réessai suivant, tout autre
  /// échec attend le prochain déclencheur.
  Future<void> declencher() async {
    if (_enCours) return;
    _enCours = true;
    _reessai?.cancel();
    _reessai = null;
    try {
      final resultat = await _synchroniser();
      if (!resultat.horsLigne) _echecs = 0;
      onTermine?.call();
    } catch (e) {
      if (estEchecReseau(e)) {
        _programmerReessai();
      } else {
        _echecs = 0;
      }
    } finally {
      _enCours = false;
    }
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
