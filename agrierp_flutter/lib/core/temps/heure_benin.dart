/// Ticket S-T11 — L'HEURE DU BÉNIN AU POSTE, QUEL QUE SOIT LE RÉGLAGE DE WINDOWS. Point de passage UNIQUE.
///
/// ## Le défaut
///
/// Le serveur tourne en `Africa/Porto-Novo` (ticket 14.71) et sert ses dates sous trois formes : un JOUR pur
/// (`2026-10-19`), une heure MURALE sans fuseau (`2026-10-19 10:30:00`, grand livre des stocks) et un INSTANT avec
/// fuseau (`2026-10-18T23:00:00.000000Z` pour une date Eloquent, `2026-10-19T10:30:00+01:00` pour une vente). Le
/// poste lisait ces instants par `DateTime.parse(...).toLocal()` : sur un Windows réglé sur un autre fuseau que celui
/// du Bénin, le 19 octobre à minuit au Bénin (23 h UTC la veille) devenait le 18 — un soin, une avance, une échéance
/// glissaient d'un jour, et le contrôle de cohérence (S-T6) criait à l'écart (constaté par l'essai S-T9). De même,
/// `DateTime.now()` donnait l'heure de Windows : une vente faite à 00 h 30 au Bénin sur un poste réglé en UTC était
/// datée de la veille.
///
/// ## La règle
///
///  - **Le JOUR métier est toujours le jour à l'heure du Bénin.** Une date métier (jour d'une vente, d'une fiche,
///    d'un soin, d'une avance ; « aujourd'hui » ; fenêtres « du mois ») est tenue au poste en HEURE MURALE DU BÉNIN :
///    un `DateTime` local dont les champs (année, mois, jour, heure…) sont ceux de l'horloge du Bénin. C'est déjà la
///    forme d'un jour pur servi (`DateTime.parse('2026-10-19')`) et celle qu'attend le serveur à l'envoi (`Y-m-d`,
///    `Y-m-d H:i:s` sans fuseau, lus en `Africa/Porto-Novo`) : elle ne dépend plus du réglage de Windows.
///  - **Les instants techniques restent des instants** (UTC à l'envoi) : `updated_at`, `server_time`, curseurs de
///    tirage, journal des synchronisations. Ils ne servent jamais à calculer un jour métier sans passer par
///    [depuisInstant].
///
/// ## Pourquoi un décalage fixe, sans le paquet `timezone`
///
/// Le Bénin vit à UTC+1 toute l'année : pas d'heure d'été (`Africa/Porto-Novo` n'a connu aucun changement d'heure
/// depuis 1934, base IANA). Un décalage fixe d'une heure est donc exact, sans base de fuseaux à embarquer ni à tenir
/// à jour. ⚠️ Si le pays adoptait un jour une heure d'été, c'est ICI, et seulement ici, qu'il faudrait la porter.
///
/// ⚠️ Limite connue : une heure murale du Bénin qui tombe dans le « trou » d'un passage à l'heure d'été du fuseau de
/// Windows (par exemple 02 h 30 un dimanche de mars sur un poste réglé sur New York) n'existe pas en heure locale et
/// se décale d'une heure à l'écriture en base. Les minuits (jours purs) n'y tombent pas pour les fuseaux usuels.
abstract final class HeureBenin {
  /// UTC+1, toute l'année.
  static const decalage = Duration(hours: 1);

  /// Horloge système — remplaçable par les tests (rendre l'instant voulu, en UTC de préférence).
  static DateTime Function() horloge = DateTime.now;

  /// Remet l'horloge système (à appeler dans `tearDown` après l'avoir remplacée).
  static void reinitialiser() => horloge = DateTime.now;

  /// L'heure MURALE du Bénin correspondant à [instant] (un vrai instant : UTC, ou heure locale de Windows), rendue
  /// comme un `DateTime` local portant les champs de l'horloge du Bénin.
  static DateTime depuisInstant(DateTime instant) {
    final u = instant.toUtc().add(decalage);
    return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second, u.millisecond, u.microsecond);
  }

  /// L'instant (UTC) que désigne l'heure murale du Bénin [murale] — l'inverse de [depuisInstant].
  static DateTime versInstant(DateTime murale) => DateTime.utc(
    murale.year,
    murale.month,
    murale.day,
    murale.hour,
    murale.minute,
    murale.second,
    murale.millisecond,
    murale.microsecond,
  ).subtract(decalage);

  /// Maintenant, à l'heure murale du Bénin.
  static DateTime maintenant() => depuisInstant(horloge());

  /// Aujourd'hui au Bénin, à minuit (heure murale).
  static DateTime aujourdhui() => jour(maintenant());

  /// Le jour (minuit) d'une heure murale.
  static DateTime jour(DateTime murale) => DateTime(murale.year, murale.month, murale.day);

  /// [murale] décalée de [jours] jours DU CALENDRIER (heure du jour gardée).
  ///
  /// ⚠️ Jamais `add(Duration(days: n))` sur une date métier : une `Duration` compte des heures, et sur un Windows réglé
  /// sur un fuseau à heure d'été (New York, Paris…) le passage à l'heure d'hiver donne 23 h la VEILLE — l'échéance
  /// d'une mise bas affichée un jour trop tôt (constaté sous `TZ=America/New_York`).
  static DateTime plusJours(DateTime murale, int jours) => DateTime(
    murale.year,
    murale.month,
    murale.day + jours,
    murale.hour,
    murale.minute,
    murale.second,
    murale.millisecond,
    murale.microsecond,
  );

  /// `AAAA-MM-JJ` d'une heure murale du Bénin.
  static String cleJour(DateTime murale) =>
      '${murale.year.toString().padLeft(4, '0')}-${murale.month.toString().padLeft(2, '0')}-'
      '${murale.day.toString().padLeft(2, '0')}';

  /// Vrai si la chaîne porte un fuseau (`Z` ou `±hh:mm`) : c'est alors un INSTANT, pas une heure murale.
  static bool porteUnFuseau(String brut) => RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(brut.trim());

  /// Une date MÉTIER servie par le serveur, en heure murale du Bénin.
  ///
  ///  - jour pur (`2026-10-19`) ou heure murale sans fuseau (`2026-10-19 10:30:00`) : déjà l'heure du serveur, donc du
  ///    Bénin — lue telle quelle ;
  ///  - instant avec fuseau (`…Z`, `…+01:00`) : converti en heure du Bénin, JAMAIS en heure de Windows.
  ///
  /// `null` si [brut] est absent ou illisible.
  static DateTime? lire(Object? brut) {
    if (brut == null) return null;
    final texte = brut.toString();
    final lu = DateTime.tryParse(texte);
    if (lu == null) return null;
    return porteUnFuseau(texte) || lu.isUtc ? depuisInstant(lu) : lu;
  }

  /// Un INSTANT technique servi (`updated_at`, `server_time`…) : gardé comme instant (heure locale de Windows, qui
  /// désigne le même moment). Jamais utilisé pour calculer un jour métier sans [depuisInstant].
  static DateTime? lireInstant(Object? brut) =>
      brut == null ? null : DateTime.tryParse(brut.toString())?.toLocal();
}
