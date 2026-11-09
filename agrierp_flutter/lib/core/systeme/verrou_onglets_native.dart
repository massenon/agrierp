/// Natif : aucun verrou, l'action s'exécute telle quelle.
Future<T> verrouEntreOngletsPlateforme<T>(Future<T> Function() action) => action();
