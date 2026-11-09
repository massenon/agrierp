import 'verrou_onglets_native.dart' if (dart.library.js_interop) 'verrou_onglets_web.dart';

/// PWA-2b — PLUSIEURS ONGLETS sur la même base : UNE SEULE synchronisation à la fois, tous onglets confondus.
///
/// Deux onglets du poste partagent la même base IndexedDB ; deux synchronisations entremêlées écriraient deux fois le curseur et
/// acquitteraient deux fois les mêmes lignes. `navigator.locks` (verrou exclusif `agrierp-synchro`, libéré à la fermeture de
/// l'onglet) fait attendre le second onglet. Natif (Windows) : l'action s'exécute TELLE QUELLE, sans verrou (une seule
/// instance du poste, `ecrivain_unique`) — comportement inchangé.
Future<T> sousVerrouEntreOnglets<T>(Future<T> Function() action) => verrouEntreOngletsPlateforme<T>(action);
