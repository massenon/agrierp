import 'package:flutter/services.dart';

/// Commandes de la fenêtre native.
///
/// ⚠️⚠️ **POURQUOI CE PONT EXISTE.** La fenêtre du poste est affichée **sans
/// cadre système** (`WS_POPUP`) : elle n'a donc plus ni barre de titre ni les
/// trois boutons réduire / agrandir / fermer. Sans remplacement, l'utilisateur
/// serait **enfermé dans l'application** — il ne pourrait ni la réduire pour
/// consulter autre chose, ni la quitter.
///
/// Ces deux commandes sont donc rendues par la barre supérieure de
/// l'application elle-même. Le canal est volontairement minimal : deux
/// méthodes, aucune dépendance externe à récupérer sur un poste hors ligne.
class FenetrePoste {
  const FenetrePoste._();

  static const _canal = MethodChannel('agrierp/fenetre');

  /// Réduit la fenêtre dans la barre des tâches.
  static Future<void> reduire() => _appeler('reduire');

  /// Ferme l'application.
  static Future<void> fermer() => _appeler('fermer');

  /// ⚠️ UN ÉCHEC DE CANAL NE DOIT PAS FAIRE PLANTER L'ÉCRAN. En test widget,
  /// aucune implémentation native n'est branchée : l'appel lèverait une
  /// `MissingPluginException` et ferait échouer un test qui ne porte pas sur
  /// la fenêtre. Le geste est alors sans effet, ce qui est le comportement
  /// juste — il n'y a pas de fenêtre native à commander.
  static Future<void> _appeler(String methode) async {
    try {
      await _canal.invokeMethod<void>(methode);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
