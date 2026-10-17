/// Ticket F0.95 — EFFECTIF PAR CATÉGORIE (lapins et porcs) : UNIQUE version Dart de la règle du
/// serveur `App\Services\EffectifParCategorieService` (tickets Laravel 15.39 à 15.42).
///
/// ⚠️⚠️ AUCUNE RÈGLE ZOOTECHNIQUE N'EST DÉCIDÉE ICI : chaque formule, chaque borne, chaque motif est
/// recopié du service PHP, et `test/effectif_par_categorie_test.dart` EXÉCUTE le vrai PHP sur une
/// grille générée pour le prouver. Une formule « équivalente » réécrite ailleurs divergerait sans
/// erreur — c'est exactement ainsi que le poste et le web ont déjà affiché deux effectifs.
///
/// Emplacements génériques (14.11 / 14.12), comme les colonnes du serveur : `repro` = Reproducteur ;
/// `sevre` = Jeune (lapins) / Porcelet (porcs) ; `jeune` = Lapin de Chair (lapins) / Porc Marchand
/// (porcs). Ce sont des noms de COLONNES, pas des libellés d'écran (glossaire 15.36).
///
/// FORMULES (chaque catégorie bornée à 0 ; v = dernière fiche ANTÉRIEURE de la même bande, un jour
/// sauté est franchi ; p = passage de stade) :
///   LAPINS  R = max(0, Rv − mR − dR)
///           J = max(0, Jv + achat + né − mJ − dJ − p)      (achat de lapins → Jeune)
///           C = max(0, Cv − vente − mC − dC + p)           (vente → Chair, QC2)
///   PORCS   R = max(0, Rv + achat − mR − dR)               (achat de porcs → Reproducteur, D11)
///           P = max(0, Pv + né − mP − dP − p)
///           M = max(0, Mv − vente − mM − dM + p)           (vente → Marchand, QC2)
///
/// Décisions client appliquées telles que le serveur les applique : D3 (passage = TRANSFERT, refusé
/// au-delà de la catégorie source APRÈS ses autres mouvements du jour), D4 (départ = effectif au
/// DÉBUT du jour, somme = effectif total de départ), D8 (somme ≠ total = avertissement, jamais un
/// blocage), D11.
///
/// ⚠️⚠️ `null` = INCONNU, propagé en null, JAMAIS lu comme 0 : une entrée inconnue rend inconnues les
/// seules catégories qu'elle touche, et l'inconnu se propage aux jours suivants. L'écran affichera
/// « — ». Toutes les fonctions de ce fichier sont PURES : aucun accès à la base.
///
/// Non portés (le serveur ne les utilise que pour son rapport à blanc, jamais pour écrire) :
/// `teteImplicite` (D6) et `rapportABlanc`.
library;

import 'dart:math' as math;

/// Trois effectifs par catégorie (veille, départ ou résultat). `null` = inconnu.
class EffectifCategories {
  const EffectifCategories({this.repro, this.sevre, this.jeune});

  final int? repro;
  final int? sevre;
  final int? jeune;

  /// Les trois catégories sont connues.
  bool get complet => repro != null && sevre != null && jeune != null;

  @override
  bool operator ==(Object other) =>
      other is EffectifCategories &&
      other.repro == repro &&
      other.sevre == sevre &&
      other.jeune == jeune;

  @override
  int get hashCode => Object.hash(repro, sevre, jeune);

  @override
  String toString() => 'EffectifCategories($repro, $sevre, $jeune)';
}

/// Mouvements d'UNE journée. `null` = inconnu (non ventilé), jamais 0.
class MouvementsJour {
  const MouvementsJour({
    this.achat,
    this.ne,
    this.vente,
    this.mortRepro,
    this.mortSevre,
    this.mortJeune,
    this.donRepro,
    this.donSevre,
    this.donJeune,
    this.passage,
  });

  final int? achat;
  final int? ne;
  final int? vente;
  final int? mortRepro;
  final int? mortSevre;
  final int? mortJeune;
  final int? donRepro;
  final int? donSevre;
  final int? donJeune;
  final int? passage;
}

/// Résultat d'UNE journée — miroir de `App\Support\EffectifCategoriesJour`.
///
/// - [sommeDifferente] : vrai si la somme des trois catégories ≠ effectif total (avertissement D8) ;
///   null quand une catégorie ou le total est inconnu.
/// - [refus] : motif français quand le passage dépasse la catégorie source (D3). Les catégories
///   restent calculées avec le passage ramené à la source (aucun sujet créé) : l'appelant qui
///   SAISIT doit bloquer, l'appelant qui RECALCULE du stocké signale seulement.
/// - [passageApplique] : passage réellement transféré (≤ saisi), null si inconnu.
class EffectifCategoriesJour {
  const EffectifCategoriesJour({
    required this.repro,
    required this.sevre,
    required this.jeune,
    required this.sommeDifferente,
    required this.refus,
    required this.passageApplique,
  });

  final int? repro;
  final int? sevre;
  final int? jeune;
  final bool? sommeDifferente;
  final String? refus;
  final int? passageApplique;

  EffectifCategories get categories =>
      EffectifCategories(repro: repro, sevre: sevre, jeune: jeune);

  /// Somme des trois catégories, null si l'une est inconnue.
  int? get somme => (repro == null || sevre == null || jeune == null)
      ? null
      : repro! + sevre! + jeune!;

  bool get estComplet => somme != null;
}

/// Une fiche telle que la chaîne la lit (mouvements stockés, départ, catégories stockées). `jour`
/// est un JOUR (minuit) ; `achat`, `ne`, `vente`, `effectifFinal` sont NOT NULL comme au serveur.
class FicheChaine {
  const FicheChaine({
    required this.id,
    required this.jour,
    required this.effectifFinal,
    this.achat = 0,
    this.ne = 0,
    this.vente = 0,
    this.mortRepro,
    this.mortSevre,
    this.mortJeune,
    this.donRepro,
    this.donSevre,
    this.donJeune,
    this.passage,
    this.departRepro,
    this.departSevre,
    this.departJeune,
    this.catEffRepro,
    this.catEffSevre,
    this.catEffJeune,
  });

  final String id;
  final DateTime jour;
  final int effectifFinal;
  final int achat;
  final int ne;
  final int vente;
  final int? mortRepro;
  final int? mortSevre;
  final int? mortJeune;
  final int? donRepro;
  final int? donSevre;
  final int? donJeune;
  final int? passage;
  final int? departRepro;
  final int? departSevre;
  final int? departJeune;
  final int? catEffRepro;
  final int? catEffSevre;
  final int? catEffJeune;

  /// Départ COMPLET (les trois catégories) : c'est ce qui fait une tête de chaîne.
  bool get departComplet =>
      departRepro != null && departSevre != null && departJeune != null;

  /// Au moins une catégorie de départ renseignée.
  bool get porteUnDepart =>
      departRepro != null || departSevre != null || departJeune != null;

  MouvementsJour get mouvements => MouvementsJour(
    achat: achat,
    ne: ne,
    vente: vente,
    mortRepro: mortRepro,
    mortSevre: mortSevre,
    mortJeune: mortJeune,
    donRepro: donRepro,
    donSevre: donSevre,
    donJeune: donJeune,
    passage: passage,
  );
}

/// Résultat de la simulation d'une chaîne (miroir de `simuler`, mode explicite seulement).
class ResultatChaine {
  const ResultatChaine({
    required this.chaine,
    required this.espece,
    required this.dateTete,
    required this.depart,
    required this.refus,
    required this.avertissements,
    required this.resultats,
  });

  /// Vrai si la bande a une chaîne exploitable (espèce suivie ET départ complet saisi).
  final bool chaine;
  final String? espece;
  final DateTime? dateTete;
  final EffectifCategories? depart;

  /// Départ incohérent (D4) : TOUTE la chaîne est refusée, rien ne doit être écrit.
  final String? refus;
  final List<String> avertissements;

  /// Résultat par identifiant de fiche, pour la tête et toutes les fiches suivantes.
  final Map<String, EffectifCategoriesJour> resultats;
}

/// État de la chaîne pour UN jour (miroir de `etatPourJour`, ticket 15.41).
class EtatJour {
  const EtatJour({
    required this.mode,
    this.departDate,
    this.depart,
    this.veille,
    this.refus,
  });

  /// `sans_chaine` | `avant_depart` | `refus` | `chaine` (mêmes codes que le serveur).
  final String mode;
  final DateTime? departDate;
  final EffectifCategories? depart;
  final EffectifCategories? veille;
  final String? refus;
}

abstract final class EffectifParCategorie {
  static const lapins = 'lapins';
  static const porcs = 'porcs';

  /// Code d'espèce du serveur → espèce prise en charge (`ESPECES` du service PHP).
  static const especes = {'cuniculture': lapins, 'porciculture': porcs};

  /// Mouvements ventilés « connus à zéro » d'une fiche créée par une vente sur une bande à chaîne
  /// (`MOUVEMENTS_CONNUS_A_ZERO`) — clés des colonnes du serveur.
  static const mouvementsConnusAZero = {
    'mort_repro': 0,
    'mort_sevre': 0,
    'mort_jeune': 0,
    'don_repro': 0,
    'don_sevre': 0,
    'don_jeune': 0,
    'passage_sevre_jeune': 0,
  };

  /// Espèce suivie pour un code d'espèce de bande, null sinon (`especeDuLot`).
  static String? especeDuCode(String? code) => especes[code];

  /// Effectif total de fin de journée — `LivestockDailyEntry::computeEffectifFinal` (14.63) :
  /// `max(0, veille + achat + nés − (morts + ventes + dons))`.
  static int effectifFinal({
    required int precedent,
    required int achat,
    required int ne,
    required int mort,
    required int vente,
    required int don,
  }) => math.max(0, precedent + achat + ne - (mort + vente + don));

  /// Effectifs par catégorie d'UNE journée (`calculerJour`).
  ///
  /// [veille] : catégories à la veille (ou départ, D4). [totalFinal] : effectif total de fin de
  /// journée, pour l'indicateur « somme ≠ total ».
  static EffectifCategoriesJour calculerJour(
    String espece,
    EffectifCategories veille,
    MouvementsJour m, {
    int? totalFinal,
  }) {
    if (espece != lapins && espece != porcs) {
      throw ArgumentError('Espèce non prise en charge : $espece.');
    }
    final estLapins = espece == lapins;

    // Reproducteur : ne change jamais de stade. Les achats de porcs lui reviennent (D11).
    final repro = _appliquer(
      veille.repro,
      estLapins ? const [] : [m.achat],
      [m.mortRepro, m.donRepro],
    );

    // Catégorie « sevre » (Jeune / Porcelet), avant passage : les lapins achetés y entrent, les nés aussi.
    final avant = _brut(
      veille.sevre,
      estLapins ? [m.achat, m.ne] : [m.ne],
      [m.mortSevre, m.donSevre],
    );

    final passage = m.passage;
    String? refus;
    int? passageApplique;
    if (passage == null) {
      passageApplique = null;
    } else {
      passageApplique = passage;
      if (avant != null && passage > math.max(0, avant)) {
        final source = math.max(0, avant);
        passageApplique = source;
        refus =
            'Passage de stade refusé : $passage sujet(s) à faire passer, mais la catégorie '
            "source n'en compte que $source.";
      }
    }

    final sevre = (avant == null || passageApplique == null)
        ? null
        : math.max(0, avant - passageApplique);
    final jeune = _appliquer(
      veille.jeune,
      [passageApplique],
      [m.vente, m.mortJeune, m.donJeune],
    );

    bool? sommeDifferente;
    if (repro != null && sevre != null && jeune != null && totalFinal != null) {
      sommeDifferente = (repro + sevre + jeune) != totalFinal;
    }

    return EffectifCategoriesJour(
      repro: repro,
      sevre: sevre,
      jeune: jeune,
      sommeDifferente: sommeDifferente,
      refus: refus,
      passageApplique: passageApplique,
    );
  }

  /// Contrôle du départ saisi (D4, `verifierDepart`) : motif du refus, ou null si valide.
  static String? verifierDepart(EffectifCategories depart, int? totalDepart) {
    final r = depart.repro;
    final s = depart.sevre;
    final j = depart.jeune;

    if (r == null || s == null || j == null) {
      return 'Effectif de départ incomplet : les trois catégories doivent être renseignées '
          '(0 si la catégorie est vide).';
    }
    if (totalDepart == null) {
      return 'Effectif total de départ inconnu : la somme des catégories ($r + $s + $j) ne '
          'peut pas être contrôlée.';
    }
    if (r + s + j != totalDepart) {
      final somme = r + s + j;
      return 'La somme des catégories de départ ($somme) ne correspond pas à '
          "l'effectif total au début du jour de départ ($totalDepart).";
    }
    return null;
  }

  /// Veille + entrées − sorties, SANS plancher (null si une entrée est inconnue).
  static int? _brut(int? base, List<int?> plus, List<int?> moins) {
    if (base == null || plus.contains(null) || moins.contains(null)) {
      return null;
    }
    return base +
        plus.fold<int>(0, (t, x) => t + x!) -
        moins.fold<int>(0, (t, x) => t + x!);
  }

  /// Idem, borné à 0.
  static int? _appliquer(int? base, List<int?> plus, List<int?> moins) {
    final brut = _brut(base, plus, moins);
    return brut == null ? null : math.max(0, brut);
  }

  /// Fiches d'une bande triées par jour (l'unicité (bande, jour) exclut les égalités).
  static List<FicheChaine> _trier(List<FicheChaine> fiches) =>
      [...fiches]..sort((a, b) => a.jour.compareTo(b.jour));

  static String _jourFr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Calcule la chaîne EN MÉMOIRE (miroir de `simuler` sans départ implicite, utilisé par
  /// `recalculerChaine`) : tête = première fiche au départ COMPLET ; total de départ = effectif
  /// final de la fiche précédente, sinon l'effectif initial de la bande ; départ incohérent =
  /// refus de toute la chaîne ; un départ saisi après la tête est ignoré et signalé ; un passage
  /// excessif est ramené à la source et signalé (saisie conservée).
  static ResultatChaine simulerChaine({
    required String? espece,
    required List<FicheChaine> fiches,
    required int initialQuantity,
  }) {
    if (espece == null) {
      return const ResultatChaine(
        chaine: false,
        espece: null,
        dateTete: null,
        depart: null,
        refus: null,
        avertissements: [],
        resultats: {},
      );
    }

    final triees = _trier(fiches);
    final indexTete = triees.indexWhere((f) => f.departComplet);
    if (indexTete < 0) {
      return ResultatChaine(
        chaine: false,
        espece: espece,
        dateTete: null,
        depart: null,
        refus: null,
        avertissements: const [],
        resultats: const {},
      );
    }

    final tete = triees[indexTete];
    final depart = EffectifCategories(
      repro: tete.departRepro,
      sevre: tete.departSevre,
      jeune: tete.departJeune,
    );
    final totalDepart = indexTete > 0
        ? triees[indexTete - 1].effectifFinal
        : initialQuantity;

    final refus = verifierDepart(depart, totalDepart);
    if (refus != null) {
      return ResultatChaine(
        chaine: true,
        espece: espece,
        dateTete: tete.jour,
        depart: depart,
        refus: refus,
        avertissements: const [],
        resultats: const {},
      );
    }

    final avertissements = <String>[];
    final resultats = <String, EffectifCategoriesJour>{};
    var veille = depart;
    final suite = triees.sublist(indexTete);
    for (var i = 0; i < suite.length; i++) {
      final f = suite[i];
      if (i > 0 && f.porteUnDepart) {
        avertissements.add(
          'Fiche du ${_jourFr(f.jour)} : un départ y est saisi alors que la chaîne démarre '
          'déjà le ${_jourFr(tete.jour)} ; il est ignoré.',
        );
      }
      final r = calculerJour(
        espece,
        veille,
        f.mouvements,
        totalFinal: f.effectifFinal,
      );
      if (r.refus != null) {
        avertissements.add(
          'Fiche du ${_jourFr(f.jour)} : ${r.refus} Passage ramené à la catégorie source '
          'pour le calcul (saisie conservée).',
        );
      }
      resultats[f.id] = r;
      veille = r.categories;
    }

    return ResultatChaine(
      chaine: true,
      espece: espece,
      dateTete: tete.jour,
      depart: depart,
      refus: null,
      avertissements: avertissements,
      resultats: resultats,
    );
  }

  /// État de la chaîne pour [jour] (miroir de `etatPourJour`, lecture seule) : tout ce qu'il faut
  /// pour calculer ce jour avec [calculerJour]. `veille` = départ si le jour EST la tête (D4),
  /// sinon les catégories STOCKÉES de la dernière fiche strictement antérieure (un jour sauté est
  /// franchi) ; une catégorie stockée à null reste inconnue.
  static EtatJour etatPourJour({
    required String? espece,
    required List<FicheChaine> fiches,
    required int initialQuantity,
    required DateTime jour,
  }) {
    if (espece == null) return const EtatJour(mode: 'sans_chaine');

    final triees = _trier(fiches);
    final indexTete = triees.indexWhere((f) => f.departComplet);
    if (indexTete < 0) return const EtatJour(mode: 'sans_chaine');

    final tete = triees[indexTete];
    final depart = EffectifCategories(
      repro: tete.departRepro,
      sevre: tete.departSevre,
      jeune: tete.departJeune,
    );
    final j = DateTime(jour.year, jour.month, jour.day);

    if (j.isBefore(tete.jour)) {
      return EtatJour(
        mode: 'avant_depart',
        departDate: tete.jour,
        depart: depart,
      );
    }

    final totalDepart = indexTete > 0
        ? triees[indexTete - 1].effectifFinal
        : initialQuantity;
    final refus = verifierDepart(depart, totalDepart);
    if (refus != null) {
      return EtatJour(
        mode: 'refus',
        departDate: tete.jour,
        depart: depart,
        refus: refus,
      );
    }

    if (j == tete.jour) {
      return EtatJour(
        mode: 'chaine',
        departDate: tete.jour,
        depart: depart,
        veille: depart,
      );
    }

    FicheChaine? precedente;
    for (final f in triees) {
      if (f.jour.isBefore(j) && !f.jour.isBefore(tete.jour)) precedente = f;
    }
    return EtatJour(
      mode: 'chaine',
      departDate: tete.jour,
      depart: depart,
      veille: EffectifCategories(
        repro: precedente?.catEffRepro,
        sevre: precedente?.catEffSevre,
        jeune: precedente?.catEffJeune,
      ),
    );
  }

  /// D3 au moment de l'ENVOI ou de la SAISIE (miroir de `refusDuPassage`) : le passage de la fiche
  /// [proposee] dépasse-t-il sa catégorie source ? Simulation de la chaîne depuis le départ et les
  /// mouvements STOCKÉS des autres fiches (jamais leurs catégories stockées), la proposée à sa
  /// date. Rend le motif, ou null (pas de chaîne, fiche avant la tête, passage valide).
  static String? refusDuPassage({
    required String? espece,
    required List<FicheChaine> autres,
    required FicheChaine proposee,
  }) {
    if (espece == null) return null;

    final triees = _trier([
      for (final f in autres)
        if (f.id != proposee.id) f,
      proposee,
    ]);
    final indexTete = triees.indexWhere((f) => f.departComplet);
    if (indexTete < 0) return null;

    final tete = triees[indexTete];
    var veille = EffectifCategories(
      repro: tete.departRepro,
      sevre: tete.departSevre,
      jeune: tete.departJeune,
    );
    for (final f in triees.sublist(indexTete)) {
      final r = calculerJour(espece, veille, f.mouvements);
      if (f.id == proposee.id) return r.refus;
      veille = r.categories;
    }
    return null;
  }
}
