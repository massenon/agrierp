/// Ticket S-T8 (méthode TATACORA, § 1 « installateur ») — ENVIRONNEMENT DE CONSTRUCTION DU POSTE ET ADRESSE DU
/// SERVEUR PAR DÉFAUT.
///
/// L'environnement est FIGÉ À LA COMPILATION : `flutter build windows --dart-define=AGRIERP_ENV=recette`
/// (`build_windows.bat --env recette`). Sans indication : **production** — un poste livré à la ferme ne doit jamais
/// dépendre d'un oubli de paramètre pour parler au bon serveur.
///
/// L'adresse n'est qu'une valeur DE DÉPART : l'administrateur peut toujours la changer dans Paramètres du poste
/// (`ParametresPoste.definirAdresseServeur`), et la valeur enregistrée l'emporte.
///
/// ⚠️ `build_windows.bat` accepte exactement les [codes] ci-dessous ; `test/environnement_test.dart` lit le script et
/// l'exige. Un code inconnu à la compilation retombe sur la production ([depuisCode]) — le script, lui, le refuse avant.
enum Environnement {
  /// Poste du développeur : `php artisan serve --port=8002` (`APP_URL` du `.env`, `agrierp_laravel/CLAUDE.md`).
  developpement('dev', 'Développement', 'http://127.0.0.1:8002'),

  /// Serveur de recette — décision client du 19/10/2026 : **le serveur de la ferme lui-même**. Les essais se font sur
  /// la production, puis les données d'essai sont vidées par « Réinitialisation des données » (Paramètres, ticket
  /// 15.50) avant la mise en service. ⚠️ Un poste de recette parle donc à la VRAIE base : ce qu'il saisit y reste
  /// jusqu'à la réinitialisation.
  recette('recette', 'Recette', 'https://agrierp.fermeolouwachegoun.com'),

  /// Serveur de la ferme — décision client du 17/10/2026 (« le serveur est hébergé à
  /// https://agrierp.fermeolouwachegoun.com »).
  production('production', 'Production', 'https://agrierp.fermeolouwachegoun.com');

  const Environnement(this.code, this.libelle, this.adresseParDefaut);

  /// Valeur de `--dart-define=AGRIERP_ENV=…` et de `build_windows.bat --env …`.
  final String code;
  final String libelle;
  final String adresseParDefaut;

  /// Codes acceptés, dans l'ordre de l'énumération.
  static List<String> get codes => [for (final e in values) e.code];

  /// Code compilé dans l'exécutable.
  static const codeCompile = String.fromEnvironment('AGRIERP_ENV', defaultValue: 'production');

  /// Environnement de cet exécutable.
  static final Environnement courant = depuisCode(codeCompile);

  /// ⚠️ Un code inconnu retombe sur la PRODUCTION, jamais sur le développement : un poste livré qui viserait
  /// `127.0.0.1` n'enverrait rien nulle part, sans erreur compréhensible.
  static Environnement depuisCode(String code) {
    final propre = code.trim().toLowerCase();
    for (final e in values) {
      if (e.code == propre) return e;
    }
    return production;
  }

  /// Ticket S-T8 — UNE VERSION DÉMO est une version de `pubspec.yaml` dont le numéro porte le suffixe de
  /// pré-version `-demo` (`1.2.0-demo+3`, `1.2.0-demo.2+3`). Elle sert aux démonstrations et ne doit JAMAIS être
  /// construite pour la production (`build_windows.bat` refuse) : un installateur de démonstration remis à la ferme
  /// enverrait ses saisies de démonstration au vrai serveur.
  static bool estVersionDemo(String version) =>
      RegExp(r'^\d+\.\d+\.\d+-demo(?:[.+]|$)', caseSensitive: false).hasMatch(version.trim());

  /// Refus d'une construction : rend le motif, ou `null` si la combinaison est permise. Même règle que le script.
  static String? refusDeConstruction({required String version, required Environnement environnement}) =>
      environnement == production && estVersionDemo(version)
      ? 'Version démo « ${version.trim()} » : construction refusée pour la production.'
      : null;
}
