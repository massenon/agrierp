import '../../core/database/app_database.dart';

/// Tickets EX1 / EX2 — RÈGLES R1 ET R3 DU PRD `docs/prd/exercices-comptables.md` § 5, au poste.
///
/// Reproduction de `FinancialReportService::exerciceDe / ouvertureExercice / soldes / controleAnouveaux` (Laravel),
/// prouvée par une parité EXÉCUTÉE contre le PHP (`test/bascule_exercice_parite_test.dart`) :
///
///  - **R1** — solde d'un compte à une date D de l'exercice F : classes 1 à 5 = ouverture de F + mouvements de F
///    jusqu'à D ; classes 6 et au-delà = mouvements de F seulement. ⚠️ JAMAIS l'historique de F-1 ET l'à-nouveau de F
///    (défaut C1 : la caisse de 901 592 F affichée 1 803 184 F après la clôture) ;
///  - **ouverture de F** : à-nouveau (`ran`, net de `ran_reversal`) si l'exercice précédent est clos, ou à-nouveau
///    initial du premier exercice (Q7) ; sinon **R3** — clôture CALCULÉE de l'exercice précédent (classes 1 à 5) et
///    une ligne « Résultat de l'exercice N (provisoire) » au 131 (bénéfice) ou au 139 (perte) ; premier exercice sans
///    à-nouveau : écritures datées avant lui (vide en pratique) ;
///  - les écritures d'à-nouveau ne sont JAMAIS des mouvements d'une période : elles sont l'ouverture.
///
/// Toutes les bornes sont des JOURS CALENDAIRES (AAAAMMJJ), comme `whereDate` du serveur.
///
/// ⚠️ Écart assumé : un compte que le poste ne connaît pas (absent du plan reçu) n'a pas de classe ; il est traité
/// comme un compte de bilan (reporté), jamais perdu. Au serveur, la jointure sur le plan donne toujours sa classe.
class SoldesExercice {
  SoldesExercice({
    required List<FiscalYear> exercices,
    required List<AccountingEntry> ecritures,
    required Map<String, List<AccountingEntryLine>> lignesParEcriture,
    required List<ChartOfAccount> plan,
  }) : _exercices = [
         for (final e in exercices)
           if (e.startDate != null && e.endDate != null) e,
       ]..sort((a, b) => jour(a.startDate!).compareTo(jour(b.startDate!))),
       _plan = {for (final c in plan) c.id: c},
       _codeVersId = {for (final c in plan) c.code: c.id},
       _ecritures = [
         for (final e in ecritures)
           (
             jour: jour(e.entryDate),
             aNouveau: sourcesANouveau.contains(e.sourceType),
             soldeGestion: sourcesSoldeGestion.contains(e.sourceType),
             lignes: lignesParEcriture[e.id] ?? const <AccountingEntryLine>[],
           ),
       ];

  /// `FinancialReportService::SOURCES_A_NOUVEAU`.
  static const sourcesANouveau = {'ran', 'ran_reversal'};

  /// Ticket EX8 — `FinancialReportService::SOURCES_SOLDE_GESTION` : l'écriture de solde des comptes de gestion (étape 2
  /// de la clôture, au 31/12) que le Bilan et le Compte de résultat écartent, ses deux côtés ensemble.
  static const sourcesSoldeGestion = {'closing'};

  /// `FinancialReportService::libelleResultatProvisoire`.
  static String libelleResultatProvisoire(int annee) =>
      "Résultat de l'exercice $annee (provisoire)";

  final List<FiscalYear> _exercices;
  final Map<String, ChartOfAccount> _plan;
  final Map<String, String> _codeVersId;
  final List<
    ({int jour, bool aNouveau, bool soldeGestion, List<AccountingEntryLine> lignes})
  >
  _ecritures;
  final Map<int, OuvertureExercice> _ouvertures = {};

  /// Jour calendaire comparable (AAAAMMJJ).
  static int jour(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static int _veille(int j) {
    final d = DateTime(j ~/ 10000, j ~/ 100 % 100, j % 100 - 1);
    return jour(d);
  }

  static double arrondi(double v) => (v * 100).roundToDouble() / 100;

  /// L'écriture est-elle un à-nouveau (`ran` / `ran_reversal`) ?
  static bool estANouveau(AccountingEntry e) =>
      sourcesANouveau.contains(e.sourceType);

  /// `exerciceDe` : l'exercice enregistré qui couvre [j], sinon l'année civile (non enregistrée).
  ExerciceComptable exerciceDe(int j) {
    for (final e in _exercices) {
      if (jour(e.startDate!) <= j && jour(e.endDate!) >= j) {
        return ExerciceComptable(
          annee: e.year,
          debut: jour(e.startDate!),
          fin: jour(e.endDate!),
          statut: e.status,
          reel: true,
        );
      }
    }
    final annee = j ~/ 10000;
    return ExerciceComptable(
      annee: annee,
      debut: annee * 10000 + 101,
      fin: annee * 10000 + 1231,
      statut: null,
      reel: false,
    );
  }

  bool _existeAvant(int debut) =>
      _exercices.any((e) => jour(e.startDate!) < debut);

  /// Ouverture de l'exercice qui contient [date] (`ouvertureExercice`).
  OuvertureExercice ouvertureDe(DateTime date) =>
      _ouverture(exerciceDe(jour(date)));

  OuvertureExercice _ouverture(ExerciceComptable exercice) {
    final deja = _ouvertures[exercice.debut];
    if (deja != null) return deja;

    final veille = _veille(exercice.debut);
    final precedent = _existeAvant(exercice.debut) ? exerciceDe(veille) : null;

    late String mode;
    late Map<String, SoldeCompte> comptes;
    LigneResultat? provisoire;

    if (precedent == null) {
      final anouveau = exercice.reel
          ? _cumuls(exercice.debut, exercice.fin, aNouveau: true)
          : const <String, ({double debit, double credit})>{};
      if (anouveau.isNotEmpty) {
        mode = 'anouveau';
        comptes = _nets(anouveau);
      } else {
        mode = 'historique';
        final calcul = _clotureDepuis({}, _cumuls(null, veille, aNouveau: false));
        final d = exercice.debut;
        comptes = _fusionner(
          calcul.comptes,
          _ligneResultat(
            calcul.resultat,
            exercice.annee - 1,
            'Résultat antérieur au ${(d % 100).toString().padLeft(2, '0')}/'
            '${(d ~/ 100 % 100).toString().padLeft(2, '0')}/${d ~/ 10000}',
          ),
        );
      }
    } else if (precedent.statut == 'cloture') {
      mode = 'anouveau';
      comptes = _nets(_cumuls(exercice.debut, exercice.fin, aNouveau: true));
    } else {
      mode = 'provisoire';
      final calcul = _clotureCalculee(precedent);
      comptes = calcul.comptes;
      provisoire = _ligneResultat(
        calcul.resultat,
        precedent.annee,
        libelleResultatProvisoire(precedent.annee),
      );
    }

    final retenus = comptes.entries.where((e) => e.value.net.abs() >= 0.005).toList()
      ..sort((a, b) => a.value.code.compareTo(b.value.code));

    return _ouvertures[exercice.debut] = OuvertureExercice(
      annee: exercice.annee,
      mode: mode,
      precedent: precedent?.annee,
      comptes: {for (final e in retenus) e.key: e.value},
      resultatProvisoire: provisoire,
    );
  }

  ({Map<String, SoldeCompte> comptes, double resultat}) _clotureCalculee(
    ExerciceComptable exercice,
  ) {
    final o = _ouverture(exercice);
    return _clotureDepuis(
      _fusionner(o.comptes, o.resultatProvisoire),
      _cumuls(exercice.debut, exercice.fin, aNouveau: false),
    );
  }

  ({Map<String, SoldeCompte> comptes, double resultat}) _clotureDepuis(
    Map<String, SoldeCompte> depart,
    Map<String, ({double debit, double credit})> mouvements,
  ) {
    final comptes = Map<String, SoldeCompte>.of(depart);
    var resultat = 0.0;
    for (final e in mouvements.entries) {
      final net = e.value.debit - e.value.credit;
      final meta = _meta(e.key);
      if (meta.estBilan) {
        final avant = comptes[e.key];
        comptes[e.key] = meta.avecNet(arrondi((avant?.net ?? 0) + net));
      } else {
        resultat -= net; // produits (crédit) − charges (débit)
      }
    }
    return (comptes: comptes, resultat: arrondi(resultat));
  }

  LigneResultat? _ligneResultat(double resultat, int annee, String libelle) {
    if (resultat.abs() < 0.005) return null;
    final code = resultat > 0 ? '131' : '139';
    return LigneResultat(
      annee: annee,
      compteId: _codeVersId[code],
      code: code,
      libelle: libelle,
      net: arrondi(-resultat),
    );
  }

  static Map<String, SoldeCompte> _fusionner(
    Map<String, SoldeCompte> comptes,
    LigneResultat? ligne,
  ) {
    if (ligne == null) return comptes;
    final id = ligne.compteId ?? 'resultat-${ligne.code}';
    final avant = comptes[id];
    return {
      ...comptes,
      id: SoldeCompte(
        code: avant?.code ?? ligne.code,
        libelle: avant?.libelle ?? ligne.libelle,
        classe: avant?.classe ?? 1,
        net: arrondi((avant?.net ?? 0) + ligne.net),
      ),
    };
  }

  Map<String, SoldeCompte> _nets(
    Map<String, ({double debit, double credit})> cumuls,
  ) => {
    for (final e in cumuls.entries)
      e.key: _meta(e.key).avecNet(arrondi(e.value.debit - e.value.credit)),
  };

  SoldeCompte _meta(String compteId) {
    final c = _plan[compteId];
    return SoldeCompte(
      code: c?.code ?? '—',
      libelle: c?.label ?? 'Compte absent du plan reçu au poste',
      classe: c?.accountClass,
      net: 0,
    );
  }

  /// Cumuls débit / crédit par compte, jours [du] (inclus, `null` = depuis l'origine) à [au] (inclus) ;
  /// [aNouveau] vrai : les seuls à-nouveaux, faux : tout le reste ; [horsSoldeGestion] vrai (ticket EX8) : sans
  /// l'écriture de solde des comptes de gestion.
  Map<String, ({double debit, double credit})> cumuls(
    int? du,
    int au, {
    required bool aNouveau,
    bool horsSoldeGestion = false,
  }) => _cumuls(du, au, aNouveau: aNouveau, horsSoldeGestion: horsSoldeGestion);

  Map<String, ({double debit, double credit})> _cumuls(
    int? du,
    int au, {
    required bool aNouveau,
    bool horsSoldeGestion = false,
  }) {
    final cumuls = <String, ({double debit, double credit})>{};
    for (final e in _ecritures) {
      if (e.aNouveau != aNouveau) continue;
      if (horsSoldeGestion && e.soldeGestion) continue;
      if (e.jour > au || (du != null && e.jour < du)) continue;
      for (final l in e.lignes) {
        final avant = cumuls[l.accountId];
        cumuls[l.accountId] = (
          debit: (avant?.debit ?? 0) + l.debit,
          credit: (avant?.credit ?? 0) + l.credit,
        );
      }
    }
    return cumuls;
  }

  /// `soldes($date, $inclus, $horsSoldeGestion)` : soldes R1 à [date] ; [inclus] faux = à l'ouverture de la journée ;
  /// [horsSoldeGestion] vrai (ticket EX8 : Bilan et Compte de résultat) : sans l'écriture de solde des comptes de
  /// gestion de l'exercice.
  SoldesR1 soldes(
    DateTime date, {
    bool inclus = true,
    bool horsSoldeGestion = false,
  }) {
    final j = jour(date);
    final exercice = exerciceDe(j);
    final ouverture = _ouverture(exercice);
    final fin = inclus ? j : _veille(j);

    final comptes = Map<String, SoldeCompte>.of(ouverture.comptes);
    if (fin >= exercice.debut) {
      for (final e in _cumuls(
        exercice.debut,
        fin,
        aNouveau: false,
        horsSoldeGestion: horsSoldeGestion,
      ).entries) {
        final avant = comptes[e.key] ?? _meta(e.key);
        comptes[e.key] = avant.avecNet(
          arrondi(avant.net + e.value.debit - e.value.credit),
        );
      }
    }
    return SoldesR1(ouverture: ouverture, comptes: comptes);
  }

  /// `controleAnouveaux` : pour chaque exercice qui a un précédent, ouverture de N+1 = clôture de N (classes 1 à 5).
  List<ControleAnouveau> controleAnouveaux() {
    final resultat = <ControleAnouveau>[];
    for (final enregistre in _exercices) {
      final debut = jour(enregistre.startDate!);
      if (!_existeAvant(debut)) continue;
      final exercice = exerciceDe(debut);
      final precedent = exerciceDe(_veille(debut));

      final calcul = _clotureCalculee(precedent);
      final attendu = _fusionner(
        calcul.comptes,
        _ligneResultat(
          calcul.resultat,
          precedent.annee,
          libelleResultatProvisoire(precedent.annee),
        ),
      );
      final o = _ouverture(exercice);
      final obtenu = _fusionner(o.comptes, o.resultatProvisoire);

      final ecarts = <EcartAnouveau>[];
      for (final id in {...attendu.keys, ...obtenu.keys}) {
        final meta = attendu[id] ?? obtenu[id]!;
        if (!meta.estBilan) continue;
        final cloture = arrondi(attendu[id]?.net ?? 0);
        final ouvert = arrondi(obtenu[id]?.net ?? 0);
        if ((cloture - ouvert).abs() >= 0.01) {
          ecarts.add(
            EcartAnouveau(
              code: meta.code,
              libelle: meta.libelle,
              cloture: cloture,
              ouverture: ouvert,
            ),
          );
        }
      }
      ecarts.sort((a, b) => a.code.compareTo(b.code));
      resultat.add(
        ControleAnouveau(
          exercice: exercice.annee,
          precedent: precedent.annee,
          statutPrecedent: precedent.statut,
          ecarts: ecarts,
        ),
      );
    }
    return resultat;
  }
}

/// Un exercice : enregistré ([reel]) ou année civile non enregistrée (traitée comme ouverte).
class ExerciceComptable {
  const ExerciceComptable({
    required this.annee,
    required this.debut,
    required this.fin,
    required this.statut,
    required this.reel,
  });

  final int annee;
  final int debut;
  final int fin;
  final String? statut;
  final bool reel;
}

/// Solde NET (débit − crédit) d'un compte.
class SoldeCompte {
  const SoldeCompte({
    required this.code,
    required this.libelle,
    required this.classe,
    required this.net,
  });

  final String code;
  final String libelle;

  /// `null` : compte absent du plan reçu (traité comme un compte de bilan).
  final int? classe;
  final double net;

  /// Classes 1 à 5 (reportées d'un exercice à l'autre).
  bool get estBilan => classe == null || (classe! >= 1 && classe! <= 5);

  SoldeCompte avecNet(double n) =>
      SoldeCompte(code: code, libelle: libelle, classe: classe, net: n);
}

/// Ligne « Résultat de l'exercice N (provisoire) » (R3) : `net` < 0 = bénéfice, au crédit du 131.
class LigneResultat {
  const LigneResultat({
    required this.annee,
    required this.compteId,
    required this.code,
    required this.libelle,
    required this.net,
  });

  final int annee;
  final String? compteId;
  final String code;
  final String libelle;
  final double net;
}

/// `ouvertureExercice()` du serveur.
class OuvertureExercice {
  const OuvertureExercice({
    required this.annee,
    required this.mode,
    required this.precedent,
    required this.comptes,
    required this.resultatProvisoire,
  });

  final int annee;

  /// `anouveau` · `provisoire` · `historique`.
  final String mode;
  final int? precedent;
  final Map<String, SoldeCompte> comptes;
  final LigneResultat? resultatProvisoire;

  /// « À-nouveaux provisoires » : l'exercice précédent est encore ouvert (R3).
  bool get provisoire => mode == 'provisoire';
}

/// `soldes()` du serveur.
class SoldesR1 {
  const SoldesR1({required this.ouverture, required this.comptes});

  final OuvertureExercice ouverture;
  final Map<String, SoldeCompte> comptes;

  LigneResultat? get resultatProvisoire => ouverture.resultatProvisoire;

  /// Solde net d'UN compte, ligne de résultat provisoire comprise si elle est la sienne (`soldeCompte`).
  double netDe(String compteId) {
    var net = comptes[compteId]?.net ?? 0;
    final p = resultatProvisoire;
    if (p != null && p.compteId == compteId) net += p.net;
    return SoldesExercice.arrondi(net);
  }
}

class EcartAnouveau {
  const EcartAnouveau({
    required this.code,
    required this.libelle,
    required this.cloture,
    required this.ouverture,
  });

  final String code;
  final String libelle;
  final double cloture;
  final double ouverture;
}

/// Un exercice et son précédent : l'invariant « ouverture de N+1 = clôture de N », comptes en écart.
class ControleAnouveau {
  const ControleAnouveau({
    required this.exercice,
    required this.precedent,
    required this.statutPrecedent,
    required this.ecarts,
  });

  final int exercice;
  final int precedent;
  final String? statutPrecedent;
  final List<EcartAnouveau> ecarts;
}
