import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'verrou_local.dart';

/// Ticket VL-2 — durée d'inactivité avant le verrouillage automatique, CHOISIE PAR CHAQUE UTILISATEUR de ce poste.
///
/// ⚠️ **VERROU PRÉSENT DES DEUX CÔTÉS** (ticket VW, 26/10/2026 : le web a le sien, réglé dans son Mon Profil par
/// `users.verrouillage_minutes`). Mêmes choix, même défaut, mêmes libellés (garde-fou `verrou_parite_web_test.dart`).
/// Le réglage reste ICI : aucune synchronisation, aucune table (pas de migration Drift) ; il est rangé au coffre du
/// système sous `agrierp.inactivite.<id utilisateur>`, à côté du PIN qu'il accompagne.
///
/// Valeur en minutes ; `0` = « Jamais ». Défaut : **5 minutes** (décision consignée, plan VL-2).
class ReglageInactivite {
  ReglageInactivite({FlutterSecureStorage? coffre}) : _coffre = coffre ?? const FlutterSecureStorage();

  /// Choix proposés dans Mon profil : Jamais, 1, 5, 15, 30 minutes.
  static const choix = [0, 1, 5, 15, 30];
  static const parDefaut = 5;

  final FlutterSecureStorage _coffre;

  static String _cle(String id) => 'agrierp.inactivite.$id';

  /// Libellé d'un choix, tel qu'affiché.
  static String libelle(int minutes) => switch (minutes) {
    0 => 'Jamais',
    1 => '1 minute',
    _ => '$minutes minutes',
  };

  /// Durée de cet utilisateur ; [parDefaut] si rien n'est enregistré, si la valeur est illisible ou hors choix, ou si
  /// le coffre est inaccessible (mieux vaut verrouiller à 5 min que ne jamais verrouiller par accident).
  Future<int> lire(String idUtilisateur) async {
    try {
      final brut = await _coffre.read(key: _cle(idUtilisateur));
      final minutes = int.tryParse(brut ?? '');
      return minutes != null && choix.contains(minutes) ? minutes : parDefaut;
    } on Object {
      return parDefaut;
    }
  }

  /// Enregistre la durée. Lève [ArgumentError] si elle n'est pas l'un des [choix].
  Future<void> ecrire(String idUtilisateur, int minutes) {
    if (!choix.contains(minutes)) {
      throw ArgumentError('Durée d\'inactivité inconnue : $minutes.');
    }
    return _coffre.write(key: _cle(idUtilisateur), value: '$minutes');
  }
}

/// Ticket VL-2 — le minuteur d'inactivité : se réarme à chaque interaction, appelle [verrouiller] à l'échéance.
///
/// ⚠️ **ARMÉ SEULEMENT QUAND L'APPLICATION EST OUVERTE** (`PorteSession` l'arme à l'ouverture, le désarme dès qu'elle
/// la quitte) : jamais pendant la connexion, la définition du PIN ni l'écran de verrouillage, qui ne se
/// re-verrouille donc pas. À l'échéance, le PIN est relu : sans PIN défini, on ne verrouille pas.
///
/// ⚠️ **RIEN N'EST INTERROMPU NI PERDU EN SILENCE.**
///  - une synchronisation ou un envoi en cours ([synchroEnCours]) n'est pas coupé : on attend sa fin
///    ([delaiSynchro] entre deux vérifications) ;
///  - un formulaire modal ouvert ([modaleOuverte]) peut contenir une saisie non enregistrée, que le démontage
///    perdrait : le verrou est REPORTÉ D'UNE MINUTE, une seule fois ; toute interaction rend son report. Passé ce
///    délai, on verrouille : un poste laissé seul ne doit pas rester ouvert pour un formulaire oublié. Les
///    brouillons que le projet possède déjà (« Contactez l'Éditeur ») sont portés par la coque, hors de
///    l'application démontée : ils survivent au verrouillage.
///
/// Testable : la minuterie est une [Timer] (zone de `FakeAsync`), ou une fabrique injectée.
class VerrouInactivite {
  VerrouInactivite({
    required this.reglage,
    required this.verrou,
    Timer Function(Duration, void Function())? minuterie,
  }) : _minuterie = minuterie ?? Timer.new;

  /// Report accordé (une fois) quand un formulaire modal est ouvert.
  static const delaiReport = Duration(minutes: 1);

  /// Intervalle de revérification tant qu'une synchronisation est en cours.
  static const delaiSynchro = Duration(seconds: 10);

  final ReglageInactivite reglage;
  final VerrouLocal verrou;
  final Timer Function(Duration, void Function()) _minuterie;

  /// Une synchronisation ou un envoi est-il en cours ? (branché sur le moteur de synchronisation)
  bool Function() synchroEnCours = () => false;

  /// Un formulaire modal est-il ouvert au-dessus de l'application ? (branché sur le navigateur)
  bool Function() modaleOuverte = () => false;

  String? _id;
  VoidCallback? _verrouiller;
  int _minutes = ReglageInactivite.parDefaut;
  bool _reportFait = false;
  int _generation = 0;
  Timer? _timer;

  /// Durée courante en minutes (`0` : jamais).
  int get minutes => _minutes;

  bool get arme => _id != null;

  /// Arme le minuteur pour cet utilisateur (application ouverte). [verrouiller] remplace l'application par l'écran
  /// de verrouillage.
  Future<void> armer({required String idUtilisateur, required VoidCallback verrouiller}) async {
    final generation = ++_generation;
    _id = idUtilisateur;
    _verrouiller = verrouiller;
    _reportFait = false;
    _timer?.cancel();
    final minutes = await reglage.lire(idUtilisateur);
    // Désarmé ou réarmé pendant la lecture : cet armement est périmé.
    if (generation != _generation) return;
    _minutes = minutes;
    _programmer(_duree);
  }

  /// Désarme : plus aucun verrouillage tant qu'on n'a pas réarmé.
  void desarmer() {
    _generation++;
    _id = null;
    _verrouiller = null;
    _timer?.cancel();
    _timer = null;
  }

  /// Une interaction (pointeur, défilement, clavier) : l'échéance repart de zéro.
  void activite() {
    if (!arme) return;
    _reportFait = false;
    _programmer(_duree);
  }

  /// Change la durée de l'utilisateur armé (Mon profil) : enregistrée, appliquée aussitôt.
  Future<void> regler(int minutes) async {
    final id = _id;
    if (id == null) return;
    await reglage.ecrire(id, minutes);
    if (id != _id) return;
    _minutes = minutes;
    _reportFait = false;
    _programmer(_duree);
  }

  Duration? get _duree => _minutes == 0 ? null : Duration(minutes: _minutes);

  void _programmer(Duration? delai) {
    _timer?.cancel();
    _timer = null;
    if (delai != null && arme) _timer = _minuterie(delai, _echeance);
  }

  Future<void> _echeance() async {
    final generation = _generation;
    final id = _id;
    if (id == null) return;
    if (synchroEnCours()) return _programmer(delaiSynchro);
    if (modaleOuverte() && !_reportFait) {
      _reportFait = true;
      return _programmer(delaiReport);
    }
    // Pas de PIN, pas de verrou (par exemple effacé entre-temps).
    if (!await verrou.estDefini(id)) return;
    if (generation != _generation) return;
    final verrouiller = _verrouiller;
    desarmer();
    verrouiller?.call();
  }
}

/// Ticket VL-2 — l'oreille GLOBALE : posée une seule fois, au-dessus du navigateur (`MaterialApp.builder`), pour que
/// les fenêtres modales (hors de l'écran, dans le `Overlay`) comptent aussi comme des interactions.
///
/// Écoute le pointeur (clic, déplacement, survol), la molette/le défilement et le clavier physique. Ne consomme rien :
/// les événements continuent leur chemin.
class SurveillanceInactivite extends StatefulWidget {
  const SurveillanceInactivite({super.key, required this.controleur, required this.child});

  final VerrouInactivite controleur;
  final Widget child;

  @override
  State<SurveillanceInactivite> createState() => _SurveillanceInactiviteState();
}

class _SurveillanceInactiviteState extends State<SurveillanceInactivite> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_touche);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_touche);
    super.dispose();
  }

  bool _touche(KeyEvent _) {
    widget.controleur.activite();
    return false;
  }

  void _activite(PointerEvent _) => widget.controleur.activite();

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _activite,
    onPointerMove: _activite,
    onPointerHover: _activite,
    onPointerSignal: _activite,
    onPointerPanZoomUpdate: _activite,
    child: widget.child,
  );
}
