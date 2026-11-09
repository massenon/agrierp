import 'evenements_navigateur.dart';

/// Natif : rien (le retour du réseau vient de `connectivity_plus`, la reprise de focus n'est pas un déclencheur).
Stream<EvenementNavigateur> evenementsNavigateurPlateforme() => const Stream.empty();
