import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// État de la fenêtre native, tel que le côté Windows le rapporte.
///
/// [zone] est la **zone de travail** du moniteur qui porte la fenêtre — l'écran moins la barre des tâches de
/// Windows, quel que soit son côté ou sa taille — en pixels physiques. Le Dart ne la calcule jamais : il la lit.
@immutable
class EtatFenetre {
  const EtatFenetre({required this.agrandie, this.zone});

  /// Vrai quand la fenêtre occupe la zone de travail (et non sa taille de restauration).
  final bool agrandie;

  /// Zone de travail du moniteur, ou `null` si le natif ne l'a pas donnée.
  final Rect? zone;

  /// Lit la réponse du canal. Une réponse qui n'est pas le dictionnaire attendu rend `null` : mieux vaut ignorer
  /// un état illisible qu'inventer une géométrie.
  static EtatFenetre? depuis(Object? reponse) {
    if (reponse is! Map) return null;
    final agrandie = reponse['agrandie'];
    if (agrandie is! bool) return null;
    final x = reponse['x'];
    final y = reponse['y'];
    final largeur = reponse['largeur'];
    final hauteur = reponse['hauteur'];
    final zone = (x is num && y is num && largeur is num && hauteur is num)
        ? Rect.fromLTWH(x.toDouble(), y.toDouble(), largeur.toDouble(), hauteur.toDouble())
        : null;
    return EtatFenetre(agrandie: agrandie, zone: zone);
  }
}

/// Commandes de la fenêtre native.
///
/// ⚠️⚠️ **POURQUOI CE PONT EXISTE.** La fenêtre du poste est affichée **sans
/// cadre système** (`WS_POPUP`) : elle n'a donc plus ni barre de titre ni les
/// trois boutons réduire / agrandir / fermer. Sans remplacement, l'utilisateur
/// serait **enfermé dans l'application** — il ne pourrait ni la réduire pour
/// consulter autre chose, ni la quitter, ni la déplacer.
///
/// Ces commandes sont donc rendues par la barre supérieure de l'application
/// elle-même. Le canal est volontairement minimal : cinq méthodes, aucune
/// dépendance externe à récupérer sur un poste hors ligne.
///
/// ⚠️⚠️ **« AGRANDIR » = LA ZONE DE TRAVAIL, JAMAIS LE MONITEUR ENTIER.**
/// Une fenêtre `WS_POPUP` « maximisée » par le système couvre tout l'écran et
/// masque la barre des tâches de Windows (défaut constaté chez le client). C'est
/// le côté natif (`win32_window.cpp`) qui cale la fenêtre sur `rcWork` ; le Dart
/// ne fait que demander la bascule et relire l'état. Il ne calcule aucune
/// géométrie : la barre des tâches peut être à gauche, en haut, masquée
/// automatiquement, la zone vient toujours du système.
class FenetrePoste {
  const FenetrePoste._();

  static const _canal = MethodChannel('agrierp/fenetre');

  /// La fenêtre est-elle agrandie ? Elle s'ouvre agrandie (zone de travail). La barre supérieure écoute cette
  /// valeur pour choisir entre « Agrandir » et « Restaurer ».
  static final ValueNotifier<bool> agrandie = ValueNotifier<bool>(true);

  /// Remet l'état d'origine : les tests partagent ce singleton.
  @visibleForTesting
  static void reinitialiserPourTest() => agrandie.value = true;

  /// Réduit la fenêtre dans la barre des tâches.
  static Future<void> reduire() => _appeler<void>('reduire');

  /// Ferme l'application.
  static Future<void> fermer() => _appeler<void>('fermer');

  /// Démarre le déplacement de la fenêtre à la souris (glisser la barre supérieure). Sans effet quand la fenêtre
  /// est agrandie : elle occupe alors toute la zone de travail.
  static Future<void> deplacer() => _appeler<void>('deplacer');

  /// Relit l'état et la zone de travail au natif. `null` : pas de natif (tests, aperçu).
  static Future<EtatFenetre?> etat() async => _publier(await _appeler<Object?>('etat'));

  /// Agrandit la fenêtre sur la zone de travail si elle est restaurée, la restaure sinon. Rend le nouvel état
  /// (`null` sans natif : rien ne change).
  static Future<EtatFenetre?> basculerAgrandissement() async =>
      _publier(await _appeler<Object?>('basculerAgrandissement'));

  static EtatFenetre? _publier(Object? reponse) {
    final etat = EtatFenetre.depuis(reponse);
    if (etat != null) agrandie.value = etat.agrandie;
    return etat;
  }

  /// ⚠️ UN ÉCHEC DE CANAL NE DOIT PAS FAIRE PLANTER L'ÉCRAN. En test widget,
  /// aucune implémentation native n'est branchée : l'appel lèverait une
  /// `MissingPluginException` et ferait échouer un test qui ne porte pas sur
  /// la fenêtre. Le geste est alors sans effet, ce qui est le comportement
  /// juste — il n'y a pas de fenêtre native à commander.
  static Future<T?> _appeler<T>(String methode) async {
    try {
      return await _canal.invokeMethod<T>(methode);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
