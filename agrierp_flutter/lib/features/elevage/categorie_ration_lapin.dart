import '../../core/database/app_database.dart';

/// Ticket F0.92 — CLÉ STABLE des catégories de rationnement des lapins.
///
/// Transposition UNIQUE, au poste, de `App\Support\CategorieRationLapin`
/// (serveur, ticket 15.36). Mêmes règles de reconnaissance, même ordre, mêmes
/// valeurs de secours : la parité est verrouillée par
/// `test/categorie_ration_lapin_test.dart`, sur le jeu de libellés du test
/// serveur `GlossaireFicheLapinsTest`.
///
///   reproducteur  → « Reproducteur »      (secours 120 g/j)
///   jeune         → « Jeune »             (secours 30 g/j)  — ex-« Sevré »
///   chair         → « Lapin de Chair »    (secours 60 g/j)  — ex-« Jeune (engraissement) »
///
/// ⚠️⚠️ **POURQUOI UNE CLÉ.** Le poste rattachait l'effectif de la bande à une
/// ligne du barème par `stageLabel.toLowerCase().contains(stade)`. Après la
/// migration serveur 15.36 (« Jeune Lapin (engraissement) » → « Lapin de
/// Chair »), une bande au stade `engraissement` ne trouvait plus sa ligne :
/// effectif 0, total de provende faux, aucun message.
///
/// ⚠️ **LA CLÉ N'EST PAS STOCKÉE** : elle est DÉDUITE du libellé, ancien OU
/// nouveau (la base de production n'a jamais été lue : elle peut porter l'un
/// ou l'autre). Aucune colonne n'est ajoutée ni renommée — le contrat
/// `/api/sync/pull` (`feed_ration_standards`) est inchangé.
///
/// ⚠️ **ORDRE VOLONTAIRE** : « Jeune Lapin (engraissement) » contient
/// « jeune » ; `chair` est donc testé AVANT `jeune`.
///
/// ⚠️ « jeune » n'est reconnu qu'en ÉGALITÉ STRICTE (comme `$l === 'jeune'`
/// du serveur) : « Jeunes » ou « Jeune porc » ne sont PAS la catégorie Jeune.
abstract final class CategorieRationLapin {
  static const reproducteur = 'reproducteur';
  static const jeune = 'jeune';
  static const chair = 'chair';

  /// Ordre d'affichage du web (`fiche-lapins.blade.php`).
  static const ordre = [reproducteur, jeune, chair];

  /// Libellés affichés — décision client du 14/10/2026.
  static const libelles = {
    reproducteur: 'Reproducteur',
    jeune: 'Jeune',
    chair: 'Lapin de Chair',
  };

  /// Valeurs de secours (g/j) — UNIQUEMENT si le barème ne porte pas la
  /// catégorie (`RATIONS_DE_SECOURS` du serveur).
  static const rationsDeSecours = <String, double>{
    reproducteur: 120,
    jeune: 30,
    chair: 60,
  };

  /// Clé d'un libellé de barème (ancien ou nouveau), ou `null`.
  ///
  /// `Str::lower(Str::ascii(trim(...)))` du serveur, DANS CET ORDRE :
  /// [_trimPhp] d'abord, [_plier] ensuite.
  ///
  /// ⚠️⚠️ **TICKET F0.93 — PAS LE `trim()` DE DART.** Celui de Dart retire
  /// aussi les espaces Unicode (insécable U+00A0, cadratin U+2003…) ; celui de
  /// PHP ne retire que « \x20 \t \n \r \0 \x0B ». «  Jeune » donnait donc
  /// `jeune` au poste (ration du barème) et `null` au serveur (ration de
  /// secours) : deux totaux de provende différents, aucun message. La règle
  /// serveur est la RÉFÉRENCE (figée par le test 15.37) : c'est le poste qui
  /// s'aligne.
  static String? cle(String? libelle) {
    final l = _plier(_trimPhp(libelle ?? ''));

    if (l.isEmpty) return null;

    if (l.contains('reproducteur')) return reproducteur;

    // AVANT `jeune` : l'ancien « Jeune Lapin (engraissement) » contient « jeune ».
    if (l.contains('engraissement') || l.contains('chair')) return chair;

    // « Lapin Sevré », « Sevré » (anciens) ou « Jeune » seul (nouveau).
    if (l.contains('sevre') || l == 'jeune') return jeune;

    return null;
  }

  /// Catégorie qui porte l'effectif d'une bande, d'après son STADE technique
  /// (`livestock_lots.stage` : reproduction, croissance, ponte, engraissement).
  ///
  /// ⚠️ RÈGLE DU POSTE, SANS ÉQUIVALENT SERVEUR : le web saisit l'effectif PAR
  /// CATÉGORIE (`cat_eff_*`), colonnes que le poste ne porte pas. Le poste
  /// affiche donc l'effectif total sur la ligne du stade de la bande. La règle
  /// est la MÊME fonction [cle] appliquée au stade : elle reproduit exactement
  /// l'ancien `stageLabel.contains(stade)` sur les anciens libellés
  /// (`engraissement` → chair ; `reproduction` et `croissance` → aucune
  /// ligne), sans inventer de correspondance nouvelle. Rattacher
  /// `reproduction` à Reproducteur ou `croissance` à Jeune est une décision
  /// client OUVERTE (ticket F0.92).
  static String? cleDuStade(String? stade) => cle(stade);

  /// Première ligne du barème relevant de la catégorie, ou `null`.
  ///
  /// ⚠️ LA PREMIÈRE SEULEMENT (`$rations->first(...)` du serveur) : si le
  /// barème porte deux lignes d'une même catégorie (ancien et nouveau
  /// libellé), l'effectif de la bande ne doit pas être compté deux fois.
  static FeedRationStandard? ligne(
    List<FeedRationStandard> rations,
    String cleCategorie,
  ) {
    for (final r in rations) {
      if (cle(r.stageLabel) == cleCategorie) return r;
    }
    return null;
  }

  /// Ration (g/j) d'une catégorie : celle du barème si elle existe, sinon la
  /// valeur de secours.
  static double ration(List<FeedRationStandard> rations, String cleCategorie) =>
      ligne(rations, cleCategorie)?.rationGPerDay ??
      rationsDeSecours[cleCategorie]!;

  /// Caractères que `trim()` de PHP retire au bord, et AUCUN autre
  /// (« " \t\n\r\0\x0B" », documentation PHP).
  static const _bordsPhp = <int>{0x20, 0x09, 0x0A, 0x0D, 0x00, 0x0B};

  /// `trim()` de PHP : retire au bord les SEULS [_bordsPhp].
  static String _trimPhp(String texte) {
    var debut = 0;
    var fin = texte.length;
    while (debut < fin && _bordsPhp.contains(texte.codeUnitAt(debut))) {
      debut++;
    }
    while (fin > debut && _bordsPhp.contains(texte.codeUnitAt(fin - 1))) {
      fin--;
    }
    return texte.substring(debut, fin);
  }

  /// Ce que `Str::ascii` fait des espaces et caractères de contrôle — MESURÉ
  /// le 14/10/2026 en exécutant la règle du serveur sur chacun d'eux (ticket
  /// F0.93), et non déduit de la documentation :
  ///  - deviennent une ESPACE SIMPLE (qui reste dans le libellé : «  Jeune »
  ///    n'est donc pas « jeune ») : `\t \n \r`, U+00A0, U+1680, U+2000–U+200B,
  ///    U+2028, U+2029, U+202F, U+205F, U+3000 ;
  ///  - sont SUPPRIMÉS : les autres contrôles C0 (dont `\f`, que `trim()` PHP
  ///    ne retire pas) SAUF U+0010 et U+0013, conservés tels quels ; U+007F ;
  ///    les contrôles C1 U+0080–U+009F ; U+180E ; U+200C–U+200F ; U+2060 ;
  ///    U+FEFF.
  /// ⚠️ La translittération des LETTRES d'autres écritures par `Str::ascii`
  /// n'est PAS reproduite (seuls les accents français le sont) : voir le
  /// ticket F0.93, « ce qui n'a pas été vérifié ».
  static bool _devientEspace(int r) =>
      r == 0x09 ||
      r == 0x0A ||
      r == 0x0D ||
      r == 0xA0 ||
      r == 0x1680 ||
      (r >= 0x2000 && r <= 0x200B) ||
      r == 0x2028 ||
      r == 0x2029 ||
      r == 0x202F ||
      r == 0x205F ||
      r == 0x3000;

  static bool _estSupprime(int r) =>
      (r < 0x20 && r != 0x10 && r != 0x13 && !_devientEspace(r)) ||
      (r >= 0x7F && r <= 0x9F) ||
      r == 0x180E ||
      (r >= 0x200C && r <= 0x200F) ||
      r == 0x2060 ||
      r == 0xFEFF;

  /// Minuscules sans accents (équivalent de `Str::lower(Str::ascii(...))`
  /// pour le français, et pour les espaces et contrôles mesurés ci-dessus).
  static String _plier(String texte) {
    final sb = StringBuffer();
    for (final r in texte.runes) {
      if (_estSupprime(r)) continue;
      sb.writeCharCode(_devientEspace(r) ? 0x20 : r);
    }
    return _plierLettres(sb.toString());
  }

  /// Minuscules sans accents (lettres françaises).
  static String _plierLettres(String texte) {
    const accents = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ÿ': 'y',
    };
    final sb = StringBuffer();
    for (final c in texte.toLowerCase().split('')) {
      if (c == 'œ') {
        sb.write('oe');
      } else if (c == 'æ') {
        sb.write('ae');
      } else {
        sb.write(accents[c] ?? c);
      }
    }
    return sb.toString();
  }
}
