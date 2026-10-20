import '../../core/database/app_database.dart';
import 'nature_compte.dart';
import 'soldes_exercice.dart';

/// Référence découpée comme le serveur (`explode('—', $reference, 2)`, chaque morceau rogné) :
/// « N° Pièce » avant le premier « — » (toute la référence s'il n'y en a pas), « Libellé » après
/// (vide s'il n'y en a pas). Le schéma n'a PAS de colonne libellé : la référence porte
/// « OD-2026-0001 — Libellé » dans un seul champ texte (convention du ticket 10.4).
///
/// ⚠️ UNE SEULE DÉFINITION pour le Grand Livre (F0.85) et le Journal (F0.87) : la page web et les
/// deux gabarits PDF du serveur (`exports.journal-comptable`, `exports.grand-livre`) coupent ainsi.
(String, String) decouperReference(String? reference) {
  final brute = reference ?? '';
  final i = brute.indexOf('—');
  if (i < 0) return (brute.trim(), '');
  return (brute.substring(0, i).trim(), brute.substring(i + 1).trim());
}

/// Une écriture du journal, avec ses lignes.
class LigneJournal {
  const LigneJournal({
    required this.ecriture,
    required this.lignes,
    required this.comptes,
  });

  final AccountingEntry ecriture;
  final List<AccountingEntryLine> lignes;
  final Map<String, ChartOfAccount> comptes;

  double get totalDebit => lignes.fold<double>(0, (t, l) => t + l.debit);
  double get totalCredit => lignes.fold<double>(0, (t, l) => t + l.credit);

  /// ⚠️⚠️ **`SUM(debit) = SUM(credit)` EST GARANTI PAR LE SERVEUR** avant
  /// comptabilisation. Un déséquilibre affiché au poste ne signale donc PAS
  /// une erreur comptable, mais un **tirage incomplet** — des lignes qui ne
  /// sont pas encore descendues. Le dire ainsi évite qu'un comptable cherche
  /// une faute qui n'existe pas.
  bool get equilibree => (totalDebit - totalCredit).abs() < 0.01;

  /// « N° Pièce » du journal — ⚠️ la RÉFÉRENCE avant le premier « — » (page web
  /// `journal-comptable.blade.php`), jamais le type de source (`sale`, `purchase`…) que l'écran
  /// montrait sous cet en-tête jusqu'au ticket F0.87.
  String get piece => decouperReference(ecriture.reference).$1;

  /// « Libellé » du journal — la référence après le premier « — ».
  String get libelle => decouperReference(ecriture.reference).$2;

  /// Comptes débités puis crédités, dans l'ordre où la maquette les montre.
  String get comptesDebites => _codes((l) => l.debit > 0);
  String get comptesCredites => _codes((l) => l.credit > 0);

  String _codes(bool Function(AccountingEntryLine) filtre) {
    final codes = lignes
        .where(filtre)
        .map((l) => comptes[l.accountId]?.code ?? '—')
        .toSet()
        .toList();

    return codes.isEmpty ? '—' : codes.join(', ');
  }
}

/// Une ligne du Grand Livre — un mouvement sur UN compte, avec son solde
/// progressif.
class MouvementCompte {
  const MouvementCompte({
    required this.ecriture,
    required this.ligne,
    required this.soldeProgressif,
  });

  final AccountingEntry ecriture;
  final AccountingEntryLine ligne;

  /// ⚠️ **LE SOLDE SE CUMULE DANS L'ORDRE DES DATES**, jamais dans l'ordre
  /// d'arrivée des écritures : deux tirages successifs rapportent les pièces
  /// dans le désordre, et un solde progressif calculé sur cet ordre-là ne
  /// voudrait rien dire.
  final double soldeProgressif;

  /// Référence découpée comme `FinancialReportService::grandLivre` ([decouperReference]).
  (String, String) get _morceaux => decouperReference(ecriture.reference);

  /// « N° Pièce » : ce qui précède le premier « — » (toute la référence s'il n'y en a pas).
  String get piece => _morceaux.$1;

  /// « Libellé » : ce qui suit le premier « — » (vide s'il n'y en a pas).
  String get libelle => _morceaux.$2;
}

/// Le Grand Livre d'UN compte sur une période — l'équivalent poste du tableau que renvoie
/// `FinancialReportService::grandLivre`.
///
/// ⚠️ Un montant `null` veut dire « le poste ne sait pas » et s'affiche « — », jamais « 0 » :
///  - [sansEcriture] : le compte n'a AUCUNE ligne d'écriture sur ce poste ;
///  - [journalIncomplet] : au moins une écriture est déséquilibrée (tirage incomplet) — l'ouverture et
///    le solde final dépendent de TOUTES les lignes antérieures, donc ne sont plus fiables. Les
///    lignes de la période, elles, sont montrées telles que reçues.
class GrandLivreCompte {
  const GrandLivreCompte({
    required this.compte,
    required this.estDebitrice,
    required this.sansEcriture,
    required this.journalIncomplet,
    required this.soldeOuverture,
    required this.mouvements,
    required this.totalDebit,
    required this.totalCredit,
    required this.soldeFinal,
    this.ouverture,
  });

  final ChartOfAccount? compte;
  final bool estDebitrice;
  final bool sansEcriture;
  final bool journalIncomplet;
  final double? soldeOuverture;
  final List<MouvementCompte> mouvements;
  final double totalDebit;
  final double totalCredit;
  final double? soldeFinal;

  /// Tickets EX1 / EX2 — ouverture de l'exercice de la période (`ouverture` du serveur) : « À-nouveaux
  /// provisoires » quand l'exercice précédent est encore ouvert. `null` : aucun compte choisi.
  final OuvertureExercice? ouverture;
}

/// Les deux périodes du sélecteur de `balance-generale.html` (`bal-periode-select`) — mêmes valeurs
/// que le composant web (`BalanceGenerale::$periode` : `mois` / `exercice`).
enum PeriodeBalance { mois, exercice }

/// Une ligne de la Balance Générale — l'équivalent poste d'une entrée de `rows` de
/// `FinancialReportService::balanceGenerale`.
///
/// ⚠️ Les six montants sont positifs ou nuls ; un montant nul s'AFFICHE « — » (maquette et page web :
/// `> 0 ? montant : '—'`).
class LigneBalance {
  const LigneBalance({
    required this.compteId,
    required this.compte,
    required this.ouvertureDebit,
    required this.ouvertureCredit,
    required this.mouvementsDebit,
    required this.mouvementsCredit,
    required this.finalDebit,
    required this.finalCredit,
    this.resultatProvisoire,
    this.resultatHorsPlan,
  });

  final String compteId;

  /// `null` : le compte porte des lignes mais n'est PAS dans le plan reçu par le poste (compte archivé
  /// côté serveur : le plan ne descend que les comptes actifs, alors que la balance du serveur garde
  /// leurs lignes — sa jointure sur `chart_of_accounts` ne filtre pas l'activité).
  final ChartOfAccount? compte;

  final double ouvertureDebit;
  final double ouvertureCredit;
  final double mouvementsDebit;
  final double mouvementsCredit;
  final double finalDebit;
  final double finalCredit;

  /// Ticket EX2 — ligne « Résultat de l'exercice N (provisoire) » (R3) : une ligne à part, au 131 ou au 139,
  /// comme la balance du serveur (`provisoire` vrai). `null` pour une ligne de compte.
  final LigneResultat? resultatProvisoire;

  bool get provisoire => resultatProvisoire != null;

  /// Résultat reporté sur un 131 / 139 ABSENT du plan (clé `resultat-131` du serveur) : le serveur connaît son
  /// numéro et son libellé (`ligneResultat`), le poste aussi.
  final SoldeCompte? resultatHorsPlan;

  /// Numéro du compte, « — » si le poste ne le connaît pas.
  String get code =>
      resultatProvisoire?.code ?? compte?.code ?? resultatHorsPlan?.code ?? '—';

  String get libelle =>
      resultatProvisoire?.libelle ??
      compte?.label ??
      resultatHorsPlan?.libelle ??
      'Compte absent du plan reçu au poste';
}

/// La Balance Générale d'une période — l'équivalent poste du tableau que renvoie
/// `FinancialReportService::balanceGenerale`.
///
/// ⚠️⚠️ [connue] faux = les soldes (ouverture, final, totaux correspondants, écart) ne peuvent pas être
/// affirmés au poste et s'affichent « — » avec leur raison :
///  - [journalVide] : le poste n'a reçu AUCUNE écriture (le serveur afficherait « 0 F » ; le poste, lui,
///    ne sait pas si la ferme n'a rien comptabilisé ou s'il n'a simplement pas encore synchronisé) ;
///  - [journalIncomplet] : au moins une écriture est déséquilibrée (tirage incomplet) — même règle que le
///    Grand Livre (F0.85). Les mouvements de la période restent montrés tels que reçus.
class BalanceGenerale {
  const BalanceGenerale({
    required this.lignes,
    required this.totalOuvertureDebit,
    required this.totalOuvertureCredit,
    required this.totalMouvementsDebit,
    required this.totalMouvementsCredit,
    required this.totalFinalDebit,
    required this.totalFinalCredit,
    required this.ecart,
    required this.journalVide,
    required this.journalIncomplet,
    this.ouverture,
  });

  final List<LigneBalance> lignes;
  final double totalOuvertureDebit;
  final double totalOuvertureCredit;
  final double totalMouvementsDebit;
  final double totalMouvementsCredit;
  final double totalFinalDebit;
  final double totalFinalCredit;

  /// `round(total_final_debit − total_final_credit, 2)`.
  final double ecart;

  final bool journalVide;
  final bool journalIncomplet;

  /// Tickets EX1 / EX2 — ouverture de l'exercice du début de période (« À-nouveaux provisoires »).
  final OuvertureExercice? ouverture;

  /// `is_balanced` du serveur : `abs($ecart) < 0.01`. ⚠️ La maquette tolérait `< 1` (un franc) ;
  /// Laravel fait foi sur la règle : un centime d'écart est un déséquilibre.
  bool get equilibree => ecart.abs() < 0.01;

  bool get connue => !journalVide && !journalIncomplet;
}

class DonneesComptabilite {
  DonneesComptabilite({
    required this.comptes,
    required this.exercices,
    required this.journal,
    required this.lignesParEcriture,
  });

  /// Tickets EX1 / EX2 — règles R1 et R3 (`FinancialReportService` du serveur), sur le journal reçu.
  late final SoldesExercice soldesExercice = SoldesExercice(
    exercices: exercices,
    ecritures: [for (final e in journal) e.ecriture],
    lignesParEcriture: lignesParEcriture,
    plan: comptes,
  );

  final List<ChartOfAccount> comptes;
  final List<FiscalYear> exercices;
  final List<LigneJournal> journal;
  final Map<String, List<AccountingEntryLine>> lignesParEcriture;

  /// Compte proposé à l'ouverture du Grand Livre : « 531 » s'il est au plan, sinon le PREMIER par code.
  ///
  /// ⚠️ Même règle que `Livewire\Comptabilite\GrandLivre::defaultAccountId` (le prototype ouvre sur
  /// « 531 — Caisse », et le serveur garde cette intention quand le compte existe réellement, avec
  /// repli sur le plus petit code). Ticket F0.85 : il REMPLACE la règle du ticket F0.83 (« premier
  /// compte qui porte une écriture »), un écart au serveur que la doctrine « le serveur fait foi, le
  /// poste le reproduit » ne permet plus. Conséquence assumée par le serveur lui-même : si « 531 »
  /// manque, le repli peut tomber sur un compte de regroupement sans écriture (« 1 »), et l'écran
  /// dit alors qu'il n'a aucune écriture sur ce compte — il ne dit jamais « 0 ».
  ///
  /// `comptes` arrive trié par code (`charger`) : le premier élément est bien le plus petit code.
  ChartOfAccount? get compteGrandLivreParDefaut {
    if (comptes.isEmpty) return null;

    return comptes.where((c) => c.code == '531').firstOrNull ?? comptes.first;
  }

  /// Bornes de la période de la Balance — reproduction de `Livewire\Comptabilite\BalanceGenerale::periodBounds`.
  ///
  ///  - `mois` : du 1er au DERNIER jour du mois courant (`startOfMonth` → `endOfMonth`) — et non « à
  ///    aujourd'hui » comme le Grand Livre : les deux composants web diffèrent, le poste suit chacun ;
  ///  - `exercice` : les dates de l'exercice OUVERT ([exercice], `FiscalYear::current()`), jamais l'année
  ///    civile supposée ; à défaut d'exercice ouvert, l'année civile courante (repli du serveur).
  ///
  /// ⚠️ Un exercice ouvert SANS dates (colonnes nullables au poste, `NOT NULL` au serveur : ne devrait
  /// pas arriver) suit le repli « pas d'exercice » plutôt que d'inventer des bornes.
  static ({DateTime debut, DateTime fin}) bornesBalance(
    PeriodeBalance periode,
    DateTime maintenant,
    FiscalYear? exercice,
  ) {
    if (periode == PeriodeBalance.exercice) {
      final debut = exercice?.startDate;
      final fin = exercice?.endDate;
      if (debut != null && fin != null) {
        return (
          debut: DateTime(debut.year, debut.month, debut.day),
          fin: DateTime(fin.year, fin.month, fin.day),
        );
      }
      return (
        debut: DateTime(maintenant.year, 1, 1),
        fin: DateTime(maintenant.year, 12, 31),
      );
    }

    return (
      debut: DateTime(maintenant.year, maintenant.month, 1),
      // Jour 0 du mois suivant = dernier jour du mois courant (28, 29, 30 ou 31).
      fin: DateTime(maintenant.year, maintenant.month + 1, 0),
    );
  }

  /// Libellé de l'option — `getPeriodLabelProperty` du composant web : « Mars 2026 (période
  /// courante) » (`ucfirst(translatedFormat('F Y'))`, locale `fr`) ou « Exercice complet — 2026 »
  /// (année de l'exercice ouvert, sinon année courante).
  static String libellePeriodeBalance(
    PeriodeBalance periode,
    DateTime maintenant,
    FiscalYear? exercice,
  ) {
    if (periode == PeriodeBalance.exercice) {
      return 'Exercice complet — ${exercice?.year ?? maintenant.year}';
    }
    return '${_moisFr[maintenant.month - 1]} ${maintenant.year} (période courante)';
  }

  static const _moisFr = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];

  FiscalYear? get exerciceOuvert =>
      exercices.where((e) => e.status == 'ouvert').firstOrNull;

  /// Écritures dont les lignes ne s'équilibrent pas — donc dont le tirage est
  /// incomplet.
  int get ecrituresIncompletes => journal.where((e) => !e.equilibree).length;

  double get totalDebit => journal.fold<double>(0, (t, e) => t + e.totalDebit);

  double get totalCredit =>
      journal.fold<double>(0, (t, e) => t + e.totalCredit);

  // ── Cartes des quatre pages comptables (ticket F0.55) ─────────────────────

  /// « Comptes actifs » de `plan-comptable.html`.
  ///
  /// ⚠️ Le plan descend en entier ; le poste ne reçoit pas de colonne
  /// d'activation. Compter la table est donc exact — et c'est aussi ce que
  /// l'écran affiche déjà ligne à ligne.
  int get comptesActifs => comptes.length;

  /// « Exercice » de `plan-comptable.html` — l'année de l'exercice OUVERT.
  ///
  /// ⚠️ `null` si aucun exercice ouvert n'est descendu : afficher l'année
  /// courante à la place laisserait croire qu'un exercice est ouvert alors que
  /// la ferme peut être en clôture.
  int? get anneeExerciceOuvert => exerciceOuvert?.year;

  /// « Écritures (mois) » de `journal-comptable.html`.
  ///
  /// ⚠️ **LE MOIS SE COMPARE AVEC L'ANNÉE** — même piège que le volume d'achat
  /// mensuel : le seul numéro de mois ferait entrer le même mois de l'an passé.
  int ecrituresDuMois(DateTime jour) => journal
      .where(
        (e) =>
            e.ecriture.entryDate.year == jour.year &&
            e.ecriture.entryDate.month == jour.month,
      )
      .length;

  /// Balance Générale d'une période — reproduction de `FinancialReportService::balanceGenerale`.
  ///
  /// Règles du serveur reproduites (bornes en JOURS CALENDAIRES) :
  ///  - 🔴→✅ ticket EX1 (défaut C1) : ouverture = soldes R1 à l'ouverture de la journée [debut]
  ///    ([SoldesExercice.soldes] : à-nouveau, ou calcul R3 tant que l'exercice précédent est ouvert, + mouvements de
  ///    l'exercice avant [debut] ; classes 6-7 depuis le premier jour de l'exercice) — et non plus tout l'historique,
  ///    auquel l'à-nouveau du 01/01 s'ajoutait : chaque solde de bilan comptait deux fois après une clôture ;
  ///    présentée NETTE dans une seule colonne ;
  ///  - ticket EX2 : la ligne « Résultat de l'exercice N (provisoire) » est une ligne À PART (après le compte réel du
  ///    même numéro quand il a une ouverture ou un mouvement antérieur, avant lui sinon — l'ordre du serveur) ;
  ///  - mouvements = cumuls BRUTS de [debut] à [fin] inclus, à-nouveaux exclus (un compte peut l'être dans les deux
  ///    sens) ;
  ///  - final = (ouverture + mouvements) net, placé selon le SIGNE réel, JAMAIS selon la nature du
  ///    compte (`natureDebitrice` n'est volontairement PAS utilisée : la balance doit révéler un compte
  ///    en anomalie, pas le faire disparaître des deux colonnes) ;
  ///  - compte exclu si ouverture nette nulle ET aucun mouvement (un mouvement débit = crédit le garde) ;
  ///  - tri par code (comparaison de chaînes : « 5212 » avant « 531 ») ; arrondi au centime.
  ///
  /// ⚠️ Écarts connus avec le serveur, documentés au ticket F0.86 : (1) un compte absent du plan reçu
  /// est rendu en fin de tableau, code « — » (le serveur le trie par son code, que le poste ignore) ;
  /// (2) journal vide ou incomplet : voir [BalanceGenerale.connue].
  BalanceGenerale balanceGenerale({
    required DateTime debut,
    required DateTime fin,
  }) {
    final jourDebut = _jour(debut);
    final jourFin = _jour(fin);
    final soldes = soldesExercice.soldes(debut, inclus: false);
    final periode = soldesExercice.cumuls(
      jourDebut,
      jourFin,
      aNouveau: false,
    );
    final parId = {for (final c in comptes) c.id: c};
    final provisoire = soldes.resultatProvisoire;
    const idProvisoire = 'resultat-provisoire';

    // Union du serveur (`$opening + $period`) : soldes d'ouverture, puis la ligne provisoire, puis les comptes
    // mouvementés dans la période seulement ; puis tri STABLE par code (`uasort`).
    final union = [
      ...soldes.comptes.keys,
      if (provisoire != null) idProvisoire,
      for (final id in periode.keys)
        if (!soldes.comptes.containsKey(id)) id,
    ];
    final rang = {for (var i = 0; i < union.length; i++) union[i]: i};
    // Un résultat porté sur un 131 / 139 absent du plan garde le numéro que le serveur lui donne.
    SoldeCompte? horsPlan(String id) =>
        id.startsWith('resultat-') && !parId.containsKey(id)
        ? soldes.comptes[id]
        : null;
    String? codeDe(String id) => id == idProvisoire
        ? provisoire!.code
        : parId[id]?.code ?? horsPlan(id)?.code;
    final ids = union.toList()
      ..sort((a, b) {
        final ca = codeDe(a);
        final cb = codeDe(b);
        if (ca != null && cb != null) {
          final parCode = ca.compareTo(cb);
          if (parCode != 0) return parCode;
          return rang[a]!.compareTo(rang[b]!);
        }
        if (ca != null) return -1;
        if (cb != null) return 1;
        return a.compareTo(b);
      });

    final lignes = <LigneBalance>[];
    var tOuvD = 0.0, tOuvC = 0.0, tMvtD = 0.0, tMvtC = 0.0;
    var tFinD = 0.0, tFinC = 0.0;

    for (final id in ids) {
      final p = periode[id];
      final ouvertureNette = _arrondi(
        id == idProvisoire ? provisoire!.net : soldes.comptes[id]?.net ?? 0,
      );
      final ouvD = ouvertureNette > 0 ? ouvertureNette : 0.0;
      final ouvC = ouvertureNette < 0 ? -ouvertureNette : 0.0;
      final mvtD = _arrondi(p?.debit ?? 0);
      final mvtC = _arrondi(p?.credit ?? 0);
      final finalNet = _arrondi((ouvD + mvtD) - (ouvC + mvtC));
      final finD = finalNet > 0 ? finalNet : 0.0;
      final finC = finalNet < 0 ? -finalNet : 0.0;

      if (ouvertureNette == 0 && mvtD == 0 && mvtC == 0) continue;

      lignes.add(
        LigneBalance(
          compteId: id,
          compte: parId[id],
          ouvertureDebit: ouvD,
          ouvertureCredit: ouvC,
          mouvementsDebit: mvtD,
          mouvementsCredit: mvtC,
          finalDebit: finD,
          finalCredit: finC,
          resultatProvisoire: id == idProvisoire ? provisoire : null,
          resultatHorsPlan: horsPlan(id),
        ),
      );
      tOuvD += ouvD;
      tOuvC += ouvC;
      tMvtD += mvtD;
      tMvtC += mvtC;
      tFinD += finD;
      tFinC += finC;
    }

    return BalanceGenerale(
      lignes: lignes,
      totalOuvertureDebit: _arrondi(tOuvD),
      totalOuvertureCredit: _arrondi(tOuvC),
      totalMouvementsDebit: _arrondi(tMvtD),
      totalMouvementsCredit: _arrondi(tMvtC),
      totalFinalDebit: _arrondi(tFinD),
      totalFinalCredit: _arrondi(tFinC),
      ecart: _arrondi(tFinD - tFinC),
      journalVide: journal.isEmpty,
      journalIncomplet: ecrituresIncompletes > 0,
      ouverture: soldes.ouverture,
    );
  }

  /// Grand Livre d'UN compte — reproduction de `FinancialReportService::grandLivre`.
  ///
  /// [debut] / [fin] : bornes en JOURS CALENDAIRES, inclusives toutes les deux pour les lignes de la
  /// période ; l'ouverture compte tout ce qui est STRICTEMENT avant [debut]. `null` = pas de borne
  /// (pas de borne de début : rien n'est « avant », l'ouverture vaut 0). [recherche] ne porte que sur
  /// les lignes de la période (jamais sur l'ouverture), sur la référence entière, sans tenir compte
  /// de la casse ni des accents.
  ///
  /// Règles du serveur reproduites :
  ///  - 🔴→✅ ticket EX1 (défaut C1) : ouverture = solde R1 du compte à l'ouverture de la journée [debut]
  ///    ([SoldesExercice.soldes], ligne de résultat provisoire comprise si c'est la sienne) ; les écritures
  ///    d'à-nouveau ne sont JAMAIS des lignes de la période (elles sont l'ouverture). Sans [debut], l'ouverture vaut 0
  ///    et toutes les lignes hors à-nouveau sont montrées (le serveur n'a pas ce cas : sa période est toujours bornée) ;
  ///  - solde selon la NATURE du compte ([natureDebitrice]) ;
  ///  - le solde progressif part de l'ouverture et ne cumule QUE les lignes affichées (donc filtrées) ;
  ///  - tri : date, puis création, puis (ajout du poste, voir ci-dessous) identifiants ;
  ///  - arrondi au centime à chaque pas.
  ///
  /// ⚠️ Écarts connus avec le serveur, tous documentés au ticket F0.85 : (1) le serveur ne définit pas
  /// l'ordre de deux pièces créées à la même seconde, le poste les départage par identifiant pour que
  /// l'affichage soit stable ; (2) une création INCONNUE (`null`) passe après une création connue du
  /// même jour ; (3) `LIKE` du serveur interprète `%` et `_` dans la recherche, le poste non ;
  /// (4) la casse et les accents suivent MySQL (`utf8mb4_unicode_ci`), pas sqlite.
  GrandLivreCompte grandLivreCompte(
    String compteId, {
    DateTime? debut,
    DateTime? fin,
    String recherche = '',
  }) {
    final compte = comptes.where((c) => c.id == compteId).firstOrNull;

    if (compte == null) {
      return const GrandLivreCompte(
        compte: null,
        estDebitrice: true,
        sansEcriture: true,
        journalIncomplet: false,
        soldeOuverture: null,
        mouvements: [],
        totalDebit: 0,
        totalCredit: 0,
        soldeFinal: null,
      );
    }

    final estDebitrice = natureDebitrice(compte.code, compte.accountClass);
    final jourDebut = debut == null ? null : _jour(debut);
    final jourFin = fin == null ? null : _jour(fin);

    final lignes = <({AccountingEntry e, AccountingEntryLine l})>[];
    for (final entree in journal) {
      for (final ligne in entree.lignes) {
        if (ligne.accountId == compteId) {
          lignes.add((e: entree.ecriture, l: ligne));
        }
      }
    }

    // Ouverture : les mêmes soldes R1 que la Balance (tickets F0.86, EX1).
    final soldes = debut == null
        ? null
        : soldesExercice.soldes(debut, inclus: false);
    final netAvant = soldes?.netDe(compteId) ?? 0.0;
    final periode = <({AccountingEntry e, AccountingEntryLine l})>[];
    final aChercher = _plier(recherche.trim());

    for (final m in lignes) {
      final jour = _jour(m.e.entryDate);

      // Déjà compté dans l'ouverture : hors des lignes de la période. Un à-nouveau EST l'ouverture.
      if (SoldesExercice.estANouveau(m.e)) continue;
      if (jourDebut != null && jour < jourDebut) continue;
      if (jourFin != null && jour > jourFin) continue;

      if (aChercher.isNotEmpty) {
        final reference = m.e.reference;
        if (reference == null || !_plier(reference).contains(aChercher)) {
          continue;
        }
      }
      periode.add(m);
    }

    periode.sort((a, b) {
      final parJour = _jour(a.e.entryDate).compareTo(_jour(b.e.entryDate));
      if (parJour != 0) return parJour;

      final ca = a.e.createdAt;
      final cb = b.e.createdAt;
      if (ca != null && cb != null) {
        final parCreation = ca.compareTo(cb);
        if (parCreation != 0) return parCreation;
      } else if (ca != null) {
        return -1;
      } else if (cb != null) {
        return 1;
      }

      final parEcriture = a.e.id.compareTo(b.e.id);
      if (parEcriture != 0) return parEcriture;
      return a.l.id.compareTo(b.l.id);
    });

    final ouverture = _arrondi(estDebitrice ? netAvant : -netAvant);

    var solde = ouverture;
    var totalDebit = 0.0;
    var totalCredit = 0.0;
    final mouvements = <MouvementCompte>[];

    for (final m in periode) {
      totalDebit += m.l.debit;
      totalCredit += m.l.credit;
      solde = _arrondi(
        solde +
            (estDebitrice ? m.l.debit - m.l.credit : m.l.credit - m.l.debit),
      );
      mouvements.add(
        MouvementCompte(ecriture: m.e, ligne: m.l, soldeProgressif: solde),
      );
    }

    // Le compte d'un résultat provisoire (R3) n'a souvent aucune ligne : il a pourtant une ouverture connue.
    final sansEcriture = lignes.isEmpty && netAvant == 0;
    final incomplet = ecrituresIncompletes > 0;
    final connu = !sansEcriture && !incomplet;

    return GrandLivreCompte(
      compte: compte,
      estDebitrice: estDebitrice,
      sansEcriture: sansEcriture,
      journalIncomplet: incomplet && !sansEcriture,
      soldeOuverture: connu ? ouverture : null,
      mouvements: mouvements,
      totalDebit: _arrondi(totalDebit),
      totalCredit: _arrondi(totalCredit),
      soldeFinal: connu ? solde : null,
      ouverture: soldes?.ouverture,
    );
  }

  /// Les mouvements d'un compte sur TOUT le journal reçu (ni borne, ni recherche), avec le solde
  /// progressif de sa nature. Raccourci de [grandLivreCompte].
  List<MouvementCompte> grandLivre(String compteId) =>
      grandLivreCompte(compteId).mouvements;

  /// Jour calendaire sous forme d'entier comparable (AAAAMMJJ) : les heures n'entrent jamais en jeu.
  static int _jour(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// `round($x, 2)` du serveur, au demi-centime près (non testé au-delà : les montants en FCFA sont
  /// entiers en pratique).
  static double _arrondi(double v) => (v * 100).roundToDouble() / 100;

  /// Minuscules sans accents, ligature « œ » développée : la comparaison de libellés se fait sur une
  /// forme normalisée en Dart, jamais par `LIKE` de SQLite (insensible à la casse pour l'ASCII
  /// seulement).
  static String _plier(String texte) {
    const accents = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'ã': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'í': 'i',
      'ô': 'o',
      'ö': 'o',
      'ó': 'o',
      'õ': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ú': 'u',
      'ÿ': 'y',
      'ñ': 'n',
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

/// Lectures de `prototype_html/comptabilite-hub.html` et de ses pages.
///
/// ⚠️⚠️ **LES ÉTATS LISENT LE JOURNAL, JAMAIS DES TABLES MÉTIER DISJOINTES.**
/// C'est la règle du projet depuis l'origine. Grand Livre et Balance sont donc
/// calculés ici **à partir des écritures reçues** — pas à partir des ventes et
/// des achats du poste, qui donneraient une seconde comptabilité.
///
/// ⚠️ **AUCUNE ÉCRITURE NE SE SAISIT AU POSTE.** Une écriture naît d'une
/// opération — vente, achat, dépense, ponte, écart d'inventaire — et le serveur
/// la génère lui-même. C'est ce qui garantit qu'aucun mouvement ne pèse sur les
/// comptes sans avoir pesé sur le stock ou la caisse.
class ComptabiliteRepository {
  ComptabiliteRepository({required this.database});

  final AppDatabase database;

  Future<DonneesComptabilite> charger() async {
    final comptes = await database.select(database.chartOfAccounts).get();
    final exercices = await database.select(database.fiscalYears).get();
    final ecritures = await database.select(database.accountingEntries).get();
    final lignes = await database.select(database.accountingEntryLines).get();

    final parCompte = {for (final c in comptes) c.id: c};

    final parEcriture = <String, List<AccountingEntryLine>>{};
    for (final ligne in lignes) {
      parEcriture.putIfAbsent(ligne.entryId, () => []).add(ligne);
    }

    return DonneesComptabilite(
      comptes: comptes.toList()..sort((a, b) => a.code.compareTo(b.code)),
      exercices: exercices.toList()..sort((a, b) => b.year.compareTo(a.year)),
      lignesParEcriture: parEcriture,
      journal:
          (ecritures.toList()
                ..sort((a, b) => b.entryDate.compareTo(a.entryDate)))
              .map(
                (e) => LigneJournal(
                  ecriture: e,
                  lignes: parEcriture[e.id] ?? const [],
                  comptes: parCompte,
                ),
              )
              .toList(),
    );
  }
}
