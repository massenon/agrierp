import 'package:flutter/widgets.dart';

import '../auth/permissions_poste.dart';

/// `href` / `route(...)` du web, au poste : ouvrir un autre écran depuis un composant partagé (le lien « Créer une bande
/// depuis Bandes & Sujets → » des fiches d'élevage, par exemple) sans que chaque écran reçoive un rappel de plus.
///
/// Posé UNE fois par le socle (`main.dart`). Absent (test d'un écran seul) : [maybeOf] rend `null` et l'appelant garde
/// son repli.
class NavigationPoste extends InheritedWidget {
  const NavigationPoste({super.key, required this.ouvrir, required super.child});

  /// Ouvre [EcranPoste] dans le socle (le rôle reste jugé par `GardeEcran`).
  final void Function(EcranPoste ecran) ouvrir;

  static NavigationPoste? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<NavigationPoste>();

  @override
  bool updateShouldNotify(NavigationPoste ancienne) => false;
}
