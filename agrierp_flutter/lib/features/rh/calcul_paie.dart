import 'dart:math' as math;

/// Une tranche du barème ITS (`income_tax_brackets`) : plancher, plafond (`null` : sans plafond), taux en %.
class TrancheIts {
  const TrancheIts({required this.plancher, required this.plafond, required this.taux});

  final double plancher;
  final double? plafond;
  final double taux;
}

/// Les taux de paie de l'entreprise (`company_settings`) ; `null` = le défaut du web.
class TauxPaie {
  const TauxPaie({
    this.cnssSalarie,
    this.vps,
    this.cnssPatronalePension,
    this.cnssPatronaleFamille,
    this.cnssPatronaleRisque,
  });

  final double? cnssSalarie;
  final double? vps;
  final double? cnssPatronalePension;
  final double? cnssPatronaleFamille;
  final double? cnssPatronaleRisque;

  static const defaut = TauxPaie();
}

/// Le résultat du calcul d'une paie — mêmes clés que `PayrollCalculationService::calculer()` du serveur.
class Paie {
  const Paie({
    required this.brut,
    required this.retenueAbsence,
    required this.salaireDu,
    required this.cnssSalariale,
    required this.netImposable,
    required this.its,
    required this.net,
    required this.vps,
    required this.cnssPatronalePension,
    required this.cnssPatronaleFamille,
    required this.cnssPatronaleRisque,
    required this.totalChargesPatronales,
    required this.coutEmployeur,
    required this.baremeItsRenseigne,
  });

  final double brut;
  final double retenueAbsence;
  final double salaireDu;
  final double cnssSalariale;
  final double netImposable;
  final double its;
  final double net;
  final double vps;
  final double cnssPatronalePension;
  final double cnssPatronaleFamille;
  final double cnssPatronaleRisque;
  final double totalChargesPatronales;
  final double coutEmployeur;

  /// Faux : aucune tranche reçue — l'ITS est nul faute de barème, pas parce que le salaire est sous le seuil.
  final bool baremeItsRenseigne;

  Map<String, Object> versJson() => {
    'brut': brut,
    'retenue_absence': retenueAbsence,
    'salaire_du': salaireDu,
    'cnss_salariale': cnssSalariale,
    'net_imposable': netImposable,
    'its': its,
    'net': net,
    'vps': vps,
    'cnss_patronale_pension': cnssPatronalePension,
    'cnss_patronale_famille': cnssPatronaleFamille,
    'cnss_patronale_risque': cnssPatronaleRisque,
    'total_charges_patronales': totalChargesPatronales,
    'cout_employeur': coutEmployeur,
    'bareme_its_renseigne': baremeItsRenseigne,
  };
}

/// Ticket RH-4 — CALCUL DE PAIE AU POSTE, transposition de `App\Services\PayrollCalculationService` (droit béninois).
///
/// ⚠️⚠️ **MÊME FORMULE QUE LE SERVEUR, PROUVÉE PAR `test/paie_parite_php_test.dart`** (exécution du vrai PHP) : un net
/// « vu au poste » qui différerait du bulletin serait le pire des deux mondes. Le poste AFFICHE ce calcul (onglet
/// « Gestion de la Paie ») ; le règlement, lui, reste une DEMANDE réglée par le serveur (`ReglementPaieService`), qui
/// recalcule : rien de ce qui est calculé ici n'est envoyé.
///
/// Retenues (prélevées SUR le salarié) : CNSS salariale, ITS progressif sur le net imposable (salaire dû − CNSS).
/// Charges patronales (payées EN PLUS, hors du net) : VPS, CNSS pensions, prestations familiales, risques.
class CalculPaie {
  const CalculPaie._();

  /// Jours ouvrés du mois retenus par le web (`$joursOuvres = 26`).
  static const joursOuvres = 26;

  static const tauxCnssSalarieDefaut = 3.6;
  static const tauxVpsDefaut = 4.0;
  static const tauxCnssPensionDefaut = 6.4;
  static const tauxCnssFamilleDefaut = 9.0;
  static const tauxCnssRisqueDefaut = 2.0;

  /// `round($x, 2)` de PHP : arrondi commercial à 2 décimales (le demi s'éloigne de zéro).
  static double arrondir(double x) {
    final v = (x.abs() * 100 + 0.5).floorToDouble() / 100;
    return x < 0 ? -v : v;
  }

  static Paie calculer(
    double brut,
    int joursAbsence, {
    required List<TrancheIts> bareme,
    TauxPaie taux = TauxPaie.defaut,
    int joursOuvres = joursOuvres,
  }) {
    brut = arrondir(brut);

    // L'absence réduit le salaire réellement dû : elle n'a pas de contrepartie, elle diminue la base de tout le reste.
    final retenueAbsence = joursOuvres > 0 ? arrondir(brut / joursOuvres * math.max(0, joursAbsence)) : 0.0;
    final salaireDu = arrondir(math.max(0, brut - retenueAbsence));

    final cnssSalariale = arrondir(salaireDu * (taux.cnssSalarie ?? tauxCnssSalarieDefaut) / 100);

    // ⚠️ Assiette de l'ITS : le salaire dû MOINS la cotisation sociale salariale — le net imposable, jamais le brut.
    final netImposable = arrondir(math.max(0, salaireDu - cnssSalariale));
    final its = impotProgressif(netImposable, bareme);
    final net = arrondir(netImposable - its);

    final vps = arrondir(salaireDu * (taux.vps ?? tauxVpsDefaut) / 100);
    final pension = arrondir(salaireDu * (taux.cnssPatronalePension ?? tauxCnssPensionDefaut) / 100);
    final famille = arrondir(salaireDu * (taux.cnssPatronaleFamille ?? tauxCnssFamilleDefaut) / 100);
    final risque = arrondir(salaireDu * (taux.cnssPatronaleRisque ?? tauxCnssRisqueDefaut) / 100);
    final chargesPatronales = arrondir(vps + pension + famille + risque);

    return Paie(
      brut: brut,
      retenueAbsence: retenueAbsence,
      salaireDu: salaireDu,
      cnssSalariale: cnssSalariale,
      netImposable: netImposable,
      its: its,
      net: net,
      vps: vps,
      cnssPatronalePension: pension,
      cnssPatronaleFamille: famille,
      cnssPatronaleRisque: risque,
      totalChargesPatronales: chargesPatronales,
      coutEmployeur: arrondir(salaireDu + chargesPatronales),
      baremeItsRenseigne: bareme.isNotEmpty,
    );
  }

  /// Impôt progressif PAR TRANCHES : chaque tranche n'est taxée que sur sa propre portion. Les tranches sont lues dans
  /// l'ordre des planchers croissants, comme le serveur (`orderBy('from_amount')`).
  static double impotProgressif(double netImposable, List<TrancheIts> bareme) {
    if (netImposable <= 0 || bareme.isEmpty) return 0.0;

    final tranches = List.of(bareme)..sort((a, b) => a.plancher.compareTo(b.plancher));
    var impot = 0.0;
    for (final t in tranches) {
      final plafond = t.plafond ?? double.infinity;
      if (netImposable <= t.plancher) break;
      final portion = math.min(netImposable, plafond) - t.plancher;
      if (portion > 0) impot += portion * t.taux / 100;
    }

    return arrondir(impot);
  }
}
