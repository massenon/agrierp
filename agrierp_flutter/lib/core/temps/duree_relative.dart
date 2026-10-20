import 'heure_benin.dart';

/// Ticket U13 — « IL Y A … » DE LA CLOCHE, COMME AU WEB (`$notif->created_at->diffForHumans()`, Carbon 3, locale
/// `fr`, application en `Africa/Porto-Novo`).
///
/// La cloche du web dit « il y a 5 minutes », celle du poste disait « 19/10/2026 - 11:55 ». Le rendu est désormais le
/// même, règle pour règle, prouvé par `test/duree_relative_test.dart` (parité exécutée avec le vrai Carbon du serveur
/// sur une série d'écarts : secondes, minutes, heures, jours, semaines, mois, années, fins de mois, années bissextiles,
/// instants à venir) :
///
///  1. **L'écart est CALENDAIRE**, celui de `DateTime::diff` de PHP (timelib), calculé sur les heures MURALES du Bénin
///     des deux instants (le serveur compare `created_at` et `now()` dans son fuseau, sans heure d'été) : différence
///     champ par champ (années, mois, jours, heures, minutes, secondes, microsecondes), retenues des secondes, minutes
///     et heures, puis des JOURS sur la longueur des mois — en remontant depuis le mois précédant le plus récent des
///     deux instants quand la notification est passée, depuis le mois du plus ancien quand elle est à venir (horloge
///     du poste en retard). Ainsi du 31 janvier au 1er mars : « 4 semaines » (29 jours), et non « 1 mois ».
///  2. **Une seule unité** (`parts = 1`), la plus grande non nulle, TRONQUÉE : années, mois, semaines (jours ÷ 7),
///     jours restants, heures, minutes, secondes. Rien de non nul : « 0 seconde ».
///  3. **Formulations françaises de Carbon** : « an / ans », « mois », « semaine(s) », « jour(s) », « heure(s) »,
///     « minute(s) », « seconde(s) » ; le singulier vaut pour 0 et 1 (règle du français) ; « il y a … » pour le passé
///     (et l'instant même), « dans … » pour un instant à venir.
abstract final class DureeRelative {
  /// « il y a 5 minutes » : [instant] vu depuis [maintenant] (deux INSTANTS ; [maintenant] par défaut l'horloge du
  /// poste, [HeureBenin.horloge]).
  static String depuis(DateTime instant, {DateTime? maintenant}) {
    final a = _murale(instant);
    final b = _murale(maintenant ?? HeureBenin.horloge());

    // `created_at->diff(now)` : à venir (`invert`) quand l'instant est APRÈS maintenant.
    final aVenir = _comparer(a, b) > 0;
    final un = aVenir ? b : a;
    final deux = aVenir ? a : b;

    var us = deux.us - un.us;
    var s = deux.s - un.s;
    var i = deux.i - un.i;
    var h = deux.h - un.h;
    var d = deux.d - un.d;
    var m = deux.m - un.m;
    var y = deux.y - un.y;

    // Retenues (timelib `timelib_do_rel_normalize`).
    while (us < 0) {
      us += 1000000;
      s--;
    }
    while (s < 0) {
      s += 60;
      i--;
    }
    while (i < 0) {
      i += 60;
      h--;
    }
    while (h < 0) {
      h += 24;
      d--;
    }
    while (m < 0) {
      m += 12;
      y--;
    }

    // Retenue des jours sur la longueur des mois.
    if (!aVenir) {
      // Passé : les mois qui PRÉCÈDENT le plus récent, en remontant.
      var annee = deux.y;
      var mois = deux.m - 1;
      while (d < 0) {
        if (mois < 1) {
          mois += 12;
          annee--;
        }
        d += _joursDuMois(annee, mois);
        m--;
        mois--;
      }
    } else {
      // À venir : le mois du plus ancien, puis les suivants.
      var annee = un.y;
      var mois = un.m;
      while (d < 0) {
        if (mois > 12) {
          mois -= 12;
          annee++;
        }
        d += _joursDuMois(annee, mois);
        m--;
        mois++;
      }
    }
    while (m < 0) {
      m += 12;
      y--;
    }

    final unites = <(int, String, String)>[
      (y, 'an', 'ans'),
      (m, 'mois', 'mois'),
      (d ~/ 7, 'semaine', 'semaines'),
      (d % 7, 'jour', 'jours'),
      (h, 'heure', 'heures'),
      (i, 'minute', 'minutes'),
      (s, 'seconde', 'secondes'),
    ];
    var texte = '0 seconde';
    for (final (n, singulier, pluriel) in unites) {
      if (n > 0) {
        texte = '$n ${n > 1 ? pluriel : singulier}';
        break;
      }
    }

    return aVenir ? 'dans $texte' : 'il y a $texte';
  }

  /// Champs de l'horloge du Bénin (UTC+1, sans heure d'été) d'un instant — lus sur un `DateTime` UTC décalé, jamais
  /// sur l'heure locale de Windows (son heure d'été déplacerait les heures).
  static ({int y, int m, int d, int h, int i, int s, int us}) _murale(DateTime instant) {
    final u = instant.toUtc().add(HeureBenin.decalage);
    return (
      y: u.year,
      m: u.month,
      d: u.day,
      h: u.hour,
      i: u.minute,
      s: u.second,
      us: u.millisecond * 1000 + u.microsecond,
    );
  }

  static int _comparer(
    ({int y, int m, int d, int h, int i, int s, int us}) a,
    ({int y, int m, int d, int h, int i, int s, int us}) b,
  ) {
    for (final (x, z) in [
      (a.y, b.y),
      (a.m, b.m),
      (a.d, b.d),
      (a.h, b.h),
      (a.i, b.i),
      (a.s, b.s),
      (a.us, b.us),
    ]) {
      if (x != z) return x.compareTo(z);
    }
    return 0;
  }

  static int _joursDuMois(int annee, int mois) => DateTime.utc(annee, mois + 1, 0).day;
}
