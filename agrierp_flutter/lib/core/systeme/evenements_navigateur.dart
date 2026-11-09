import 'evenements_navigateur_native.dart'
    if (dart.library.js_interop) 'evenements_navigateur_web.dart';

/// PWA-2b — ce que le navigateur signale et que le poste natif ne signale pas.
enum EvenementNavigateur {
  /// Événement `online` de la fenêtre : le réseau est revenu.
  retourEnLigne,

  /// `visibilitychange` vers « visible » : l'onglet reprend le focus (retour d'un autre onglet, d'une autre application).
  ongletVisible,
}

/// Flux des événements du navigateur. ⚠️ Natif (Windows, référence) : flux VIDE, aucun comportement ajouté — le seul
/// fichier qui touche à `package:web` est `evenements_navigateur_web.dart`, choisi par `dart.library.js_interop`.
Stream<EvenementNavigateur> evenementsDuNavigateur() => evenementsNavigateurPlateforme();
