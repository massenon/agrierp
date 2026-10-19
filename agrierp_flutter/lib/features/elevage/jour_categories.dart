import '../../core/database/app_database.dart';
import '../stocks/pmp_service.dart';
import 'categorie_ration_lapin.dart';
import 'categorie_ration_porc.dart';
import 'effectif_par_categorie.dart';

/// D6 — `EffectifParCategorieService::teteImplicite()` : la DERNIÈRE fiche de la bande dont les trois effectifs de
/// catégorie ont été saisis à la main (`cat_eff_*`), signalée, jamais reprise comme départ.
class TeteImplicite {
  const TeteImplicite({required this.jour, required this.categories});

  final DateTime jour;
  final EffectifCategories categories;

  static TeteImplicite? de(String lotId, List<LivestockDailyEntry> fiches) {
    LivestockDailyEntry? derniere;
    for (final f in fiches) {
      if (f.lotId != lotId || f.catEffRepro == null || f.catEffSevre == null || f.catEffJeune == null) continue;
      if (derniere == null || f.entryDate.isAfter(derniere.entryDate)) derniere = f;
    }
    if (derniere == null) return null;
    return TeteImplicite(
      jour: derniere.entryDate,
      categories: EffectifCategories(
        repro: derniere.catEffRepro,
        sevre: derniere.catEffSevre,
        jeune: derniere.catEffJeune,
      ),
    );
  }
}

/// `getCategoriesJourProperty()` des fiches Lapins et Porcs du web (tickets 15.41 / 15.42), le résultat que la vue
/// lit : mode de la chaîne, effectifs du jour (`null` = inconnu, « — »), motif, refus du passage, avertissements
/// datés, départ requis / verrouillé, tête implicite (D6).
class CategoriesJour {
  const CategoriesJour({
    this.mode = 'sans_chaine',
    this.repro,
    this.sevre,
    this.jeune,
    this.motif,
    this.refusPassage,
    this.avertissements = const [],
    this.departRequis = false,
    this.departDate,
    this.depart,
    this.ancien,
  });

  final String mode;
  final int? repro;
  final int? sevre;
  final int? jeune;
  final String? motif;
  final String? refusPassage;
  final List<String> avertissements;
  final bool departRequis;
  final DateTime? departDate;
  final EffectifCategories? depart;
  final TeteImplicite? ancien;

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// `calculerCategoriesJour()` du web, instruction pour instruction. [etat] : `etatPourJour` de la bande au jour
  /// choisi (`null` sans bande) ; [departSaisi] : les trois champs « Effectif de départ » (pré-remplis depuis le
  /// stade, corrigeables) ; [effectifFinal] : `effectifFinalCalc`, pour l'avertissement « somme ≠ total » (D8).
  static CategoriesJour calculer({
    required String espece,
    required EtatJour? etat,
    required EffectifCategories departSaisi,
    required int effectifPrecedent,
    required MouvementsJour mouvements,
    required int effectifFinal,
    required DateTime jour,
    required TeteImplicite? ancien,
  }) {
    if (etat == null) return const CategoriesJour();
    var veille = etat.veille;
    var motif = etat.refus;
    var departRequis = false;
    TeteImplicite? signale;

    CategoriesJour sortie({String? m}) => CategoriesJour(
      mode: etat.mode,
      motif: m,
      departRequis: departRequis,
      departDate: etat.departDate,
      depart: etat.depart,
      ancien: signale,
    );

    if (etat.mode == 'sans_chaine') {
      departRequis = true;
      signale = ancien; // D6 : signalé, jamais écrit
      final saisis = [departSaisi.repro, departSaisi.sevre, departSaisi.jeune];
      if (saisis.contains(null)) {
        // Départ à saisir : catégories inconnues. Saisie PARTIELLE : le motif « incomplet » est dit.
        return sortie(
          m: saisis.any((v) => v != null)
              ? EffectifParCategorie.verifierDepart(departSaisi, effectifPrecedent)
              : motif,
        );
      }
      motif = EffectifParCategorie.verifierDepart(departSaisi, effectifPrecedent);
      if (motif != null) return sortie(m: motif);
      veille = departSaisi; // aperçu : le départ saisi est l'effectif au DÉBUT du jour (D4)
    }

    if (veille == null) return sortie(m: motif); // avant le départ (D12) ou départ stocké refusé

    final r = EffectifParCategorie.calculerJour(espece, veille, mouvements, totalFinal: effectifFinal);
    return CategoriesJour(
      mode: etat.mode,
      repro: r.repro,
      sevre: r.sevre,
      jeune: r.jeune,
      motif: motif,
      refusPassage: r.refus,
      avertissements: [
        // D8 : avertissement DATÉ (hors maquette, assumé), jamais un blocage.
        if (r.sommeDifferente == true)
          'Avertissement (hors maquette) — fiche du ${_date(jour)} : la somme des catégories (${r.somme}) diffère '
              "de l'effectif total ($effectifFinal). Un effectif de catégorie ne descend jamais sous 0 : vérifiez "
              'les ventes, morts et dons saisis.',
      ],
      departRequis: departRequis,
      departDate: etat.departDate,
      depart: etat.depart,
      ancien: signale,
    );
  }
}

/// Une ligne du tableau « Rationnement » : ration du barème (g/j, `(int)` du web), effectif de la catégorie (`null` =
/// inconnu), provende (`null` = inconnue).
class LigneProvende {
  const LigneProvende({required this.cle, required this.ration, required this.effectif});

  final String cle;
  final int ration;
  final int? effectif;

  int? get totalG => effectif == null ? null : effectif! * ration;
}

/// `getProvendeCalculationProperty()` des fiches Lapins et Porcs : trois lignes dans l'ordre du Blade (Lapins :
/// Reproducteur, Jeune, Sous-mères ; Porcs : Porcelet, Porc Marchand, Reproducteur), total INCONNU dès qu'une ligne
/// l'est — jamais une provende partielle présentée comme complète.
class Provende {
  const Provende(this.lignes);

  final List<LigneProvende> lignes;

  int? get totalG => lignes.any((l) => l.totalG == null) ? null : lignes.fold<int>(0, (t, l) => t + l.totalG!);

  /// `round($total / 1000, 2)`.
  double? get totalKg => totalG == null ? null : PmpService.arrondi(totalG! / 1000, 2);

  /// Pied du tableau : « — » ou « N g (X Kg) », le kilo affiché tel quel par PHP (« 2.85 », « 3 »).
  String get totalAffiche =>
      totalG == null ? '—' : '$totalG g (${PmpService.flottant(totalKg!)} Kg)';

  static Provende calculer({
    required String espece,
    required List<FeedRationStandard> rations,
    required CategoriesJour categories,
  }) {
    int? effectif(String emplacement) => switch (emplacement) {
      'repro' => categories.repro,
      'sevre' => categories.sevre,
      _ => categories.jeune,
    };
    if (espece == EffectifParCategorie.lapins) {
      // Colonnes de synchro : `cat_eff_sevre` = Sous-mères, `cat_eff_jeune` = Jeune (17/10/2026).
      LigneProvende l(String cle, String emplacement) => LigneProvende(
        cle: cle,
        ration: CategorieRationLapin.ration(rations, cle).truncate(),
        effectif: effectif(emplacement),
      );
      return Provende([
        l(CategorieRationLapin.reproducteur, 'repro'),
        l(CategorieRationLapin.chair, 'jeune'),
        l(CategorieRationLapin.sousMeres, 'sevre'),
      ]);
    }
    // `cat_eff_sevre` = Porcelet, `cat_eff_jeune` = Porc Marchand.
    LigneProvende l(String cle, String emplacement) => LigneProvende(
      cle: cle,
      ration: CategorieRationPorc.ration(rations, cle).truncate(),
      effectif: effectif(emplacement),
    );
    return Provende([
      l(CategorieRationPorc.porcelet, 'sevre'),
      l(CategorieRationPorc.marchand, 'jeune'),
      l(CategorieRationPorc.reproducteur, 'repro'),
    ]);
  }
}

/// `AutonomieAlimentaireService::evaluer()` du web : combien de jours le stock de provende de la filière couvre-t-il
/// la provende du jour affiché ? L'autonomie INFORME, elle ne bloque jamais l'enregistrement.
class AutonomieAlimentaire {
  const AutonomieAlimentaire._({
    required this.disponible,
    this.produit,
    this.stockKg,
    this.jours,
    this.inconnu = false,
    this.critique = false,
    this.rupture = false,
  });

  /// `SEUIL_CRITIQUE_JOURS`.
  static const seuilCritiqueJours = 3.0;

  final bool disponible;
  final Product? produit;
  final double? stockKg;
  final double? jours;
  final bool inconnu;
  final bool critique;
  final bool rupture;

  /// `produitProvende($code)` : un produit rattaché à l'espèce de la filière dont le nom contient « provende » ou
  /// « aliment », le premier par identifiant (`orderBy('id')->first()`).
  ///
  /// 🔴→✅ Ticket U14 — PLUS D'APPROXIMATION (U12a) : le web n'avait pas d'ordre (`first()` seul), il a désormais
  /// `orderBy('id')`, la règle que le poste supposait ; et `LIKE` se compare sous la collation du serveur
  /// (`utf8mb4_unicode_ci` : ni casse NI ACCENTS — « ALIMÉNT lapin » est un aliment) par [cleCommeLeServeur], là où le
  /// poste ne retirait que la casse. Parité exécutée : `test/provende_autonomie_parite_test.dart`.
  static Product? produitProvende(
    String codeEspece,
    List<Product> produits,
    List<EspeceElevage> especes,
  ) {
    final ids = {for (final e in especes) if (e.code == codeEspece) e.id};
    bool provende(String nom) {
      final cle = cleCommeLeServeur(nom);
      return cle.contains('provende') || cle.contains('aliment');
    }

    final candidats = [
      for (final p in produits)
        if (p.speciesId != null && ids.contains(p.speciesId) && provende(p.name)) p,
    ]..sort((a, b) => a.id.compareTo(b.id));
    return candidats.isEmpty ? null : candidats.first;
  }

  /// `Product::stockEnKg()` : un produit vendu au SAC est converti au poids du sac (`feed_types`, premier par
  /// identifiant — `orderBy('id')` au web depuis U14 ; 25 Kg à défaut), arrondi au centième ; sinon la quantité telle
  /// quelle.
  static double stockEnKg(Product produit, List<FeedType> typesAliment) {
    if (produit.unit != 'sac') return produit.stockQty;
    final tries = [...typesAliment]..sort((a, b) => a.id.compareTo(b.id));
    final poids = tries.isEmpty ? null : tries.first.standardBagWeightKg;
    return PmpService.arrondi(produit.stockQty * (poids == null || poids == 0 ? 25 : poids), 2);
  }

  static AutonomieAlimentaire evaluer(Product? produit, double? stockKg, double? consommationKgJour) {
    if (produit == null || stockKg == null) return const AutonomieAlimentaire._(disponible: false);
    final rupture = stockKg <= 0;
    if (consommationKgJour == null) {
      return AutonomieAlimentaire._(
        disponible: true,
        produit: produit,
        stockKg: stockKg,
        inconnu: true,
        critique: rupture,
        rupture: rupture,
      );
    }
    final jours = consommationKgJour > 0 ? PmpService.arrondi(stockKg / consommationKgJour, 1) : 99.0;
    return AutonomieAlimentaire._(
      disponible: true,
      produit: produit,
      stockKg: stockKg,
      jours: jours,
      critique: rupture || jours <= seuilCritiqueJours,
      rupture: rupture,
    );
  }
}
