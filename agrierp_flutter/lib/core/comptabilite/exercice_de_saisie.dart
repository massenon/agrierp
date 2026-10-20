import '../database/app_database.dart';
import '../temps/heure_benin.dart';

/// Ticket EX6 (EF7 du PRD `docs/prd/exercices-comptables.md`) — LE POINT DE PASSAGE UNIQUE DU POSTE pour la question
/// « cette saisie peut-elle être datée de ce jour ? ». La caisse (`CaisseRepository.refusDeDate`) et chaque dépôt de
/// saisie (achats, retours, remboursements, règlements fournisseurs, avances, imputations, dépenses, ajouts de stock,
/// inventaires, fiches d'élevage) l'interrogent AVANT d'écrire quoi que ce soit.
///
/// Le serveur a deux règles (ticket EX5), et le poste les recopie telles quelles :
///  - [RegleExercice.ecriture] = `AccountingEntryService::exerciceOuvertPour()` : la saisie produit une écriture
///    comptable (vente, achat, retour, règlement, remboursement, avance, imputation, dépense créée, perte
///    d'inventaire). Aucun exercice ne couvre le jour → refus, SAUF si le filet R2 l'ouvrirait ; l'exercice qui le
///    couvre est clos → refus.
///  - [RegleExercice.closSeulement] = `AccountingEntryService::refusExerciceClos()` : la saisie ne produit pas
///    forcément d'écriture (ajout de stock, inventaire en excédent, fiche d'élevage — décision Q3 —, modification ou
///    archivage d'une dépense). Seul un exercice CLOS qui couvre le jour la refuse ; un jour qu'aucun exercice ne
///    couvre est accepté, comme au serveur.
///
/// Messages : ceux du serveur, MOT POUR MOT (règle R4) — `NoOpenFiscalYearException::message()` et
/// `ClosedFiscalYearException::message()`. `test/refus_exercice_clos_test.dart` les compare au PHP exécuté.
///
/// ⚠️ **AUCUN EXERCICE CONNU AU POSTE = AUCUN BLOCAGE** (règle de la caisse depuis F0.89) : un poste qui n'a pas encore
/// tiré `fiscal_years` ne doit pas arrêter la ferme ; le serveur jugera à l'envoi (refus motivé, la ligne passe alors
/// en `conflict` avec ce même motif).
///
/// ⚠️ **LE FILET R2 EST RECOPIÉ** (`OuvertureExerciceService::refusOuverture(…, FILET)`) : un poste hors ligne le
/// 1er janvier ne connaît pas encore N+1 ; une saisie datée de N+1 alors que N est l'exercice ouvert le plus récent
/// est ACCEPTÉE ici, parce que le serveur créera N+1 en la recevant.
///
/// ⚠️ Le poste ne tranche jamais un exercice (clôture, ouverture : `docs/DOCTRINE_PORTAGE.md`, § 1.6) : il ne fait que
/// refuser avant d'écrire ce que le serveur refuserait. Le serveur re-juge tout à l'envoi.
enum RegleExercice {
  /// `AccountingEntryService::exerciceOuvertPour()` — exercice absent (sans filet) ou clos : refus.
  ecriture,

  /// `AccountingEntryService::refusExerciceClos()` — exercice clos seulement.
  closSeulement,
}

/// Refus d'une saisie pour cause d'exercice, avec le motif R4 du serveur. Chaque écran le place comme sa vue Blade
/// (sous le champ « Date », sous un autre champ, ou en toast).
class RefusExercice implements Exception {
  const RefusExercice(this.motif);

  final String motif;

  @override
  String toString() => motif;
}

class ExerciceDeSaisie {
  ExerciceDeSaisie(AppDatabase database, {DateTime Function()? maintenant})
    : _db = database,
      _maintenant = maintenant ?? HeureBenin.maintenant;

  final AppDatabase _db;
  final DateTime Function() _maintenant;

  /// Le motif R4 qui refuse une saisie datée de [jour] selon [regle], ou `null` si elle est acceptée.
  Future<String?> refus(
    DateTime jour, {
    RegleExercice regle = RegleExercice.ecriture,
  }) async => juger(
    await _db.select(_db.fiscalYears).get(),
    jour,
    regle: regle,
    aujourdhui: _maintenant(),
  );

  /// [refus], levé en [RefusExercice] : à appeler AVANT toute écriture.
  Future<void> refuser(
    DateTime jour, {
    RegleExercice regle = RegleExercice.ecriture,
  }) async {
    final motif = await refus(jour, regle: regle);
    if (motif != null) throw RefusExercice(motif);
  }

  /// Borne BASSE du calendrier d'une saisie — indicative, [refus] reste le juge et le serveur re-juge tout :
  ///  - [RegleExercice.ecriture] : début du plus ancien exercice OUVERT connu (comme `PosInterface::getDateMinProperty`
  ///    et la caisse du poste) ;
  ///  - [RegleExercice.closSeulement] : lendemain de la fin du plus récent exercice CLOS connu (un jour qu'aucun
  ///    exercice ne couvre reste admis, comme au serveur).
  ///
  /// `null` : aucune borne connue (aucun exercice au poste, ou aucun de l'état voulu).
  Future<DateTime?> premierJour({
    RegleExercice regle = RegleExercice.ecriture,
  }) async => premierJourDe(
    await _db.select(_db.fiscalYears).get(),
    regle: regle,
  );

  /// [premierJour] pour une liste d'exercices donnée (sans base).
  static DateTime? premierJourDe(
    List<FiscalYear> exercices, {
    RegleExercice regle = RegleExercice.ecriture,
  }) {
    DateTime? borne;
    for (final e in exercices) {
      switch (regle) {
        case RegleExercice.ecriture:
          final debut = e.startDate;
          if (e.status != 'ouvert' || debut == null) continue;
          final d = _minuit(debut);
          if (borne == null || d.isBefore(borne)) borne = d;
        case RegleExercice.closSeulement:
          final fin = e.endDate;
          if (e.status == 'ouvert' || fin == null) continue;
          final lendemain = HeureBenin.plusJours(_minuit(fin), 1);
          if (borne == null || lendemain.isAfter(borne)) borne = lendemain;
      }
    }
    return borne;
  }

  /// Bornes d'un `showDatePicker` de saisie : la borne d'exercice [premier] (sinon [repli], celle de l'écran), jamais
  /// après [dernier] ; et le jour [initial] ramené entre les deux (`showDatePicker` refuse un jour initial hors bornes).
  static ({DateTime premier, DateTime initial}) calendrier({
    required DateTime? premier,
    required DateTime repli,
    required DateTime dernier,
    required DateTime initial,
  }) {
    final fin = _minuit(dernier);
    var debut = _minuit(premier ?? repli);
    if (debut.isAfter(fin)) debut = fin;
    final jour = _minuit(initial);
    return (
      premier: debut,
      initial: jour.isBefore(debut) ? debut : (jour.isAfter(fin) ? fin : jour),
    );
  }

  /// LA RÈGLE, sans base : les exercices connus au poste, le jour de la saisie, la règle, et aujourd'hui (filet R2).
  static String? juger(
    List<FiscalYear> exercices,
    DateTime jour, {
    required RegleExercice regle,
    required DateTime aujourdhui,
  }) {
    // Aucun exercice connu : le poste ne sait rien, il ne bloque rien (le serveur jugera).
    if (exercices.isEmpty) return null;

    final j = _minuit(jour);
    final couvrants = [
      for (final e in exercices)
        if (e.startDate != null &&
            e.endDate != null &&
            !_minuit(e.startDate!).isAfter(j) &&
            !_minuit(e.endDate!).isBefore(j))
          e,
    ];

    if (couvrants.isEmpty) {
      // `refusExerciceClos` : un jour qu'aucun exercice ne couvre n'est pas refusé.
      if (regle == RegleExercice.closSeulement) return null;
      // `exerciceOuvertPour` : le filet R2 joue AVANT tout refus.
      if (filetOuvrirait(j.year, exercices, aujourdhui)) return null;
      return messageAucunExercice(j);
    }

    // Exercices qui se chevauchent (anomalie) : le serveur prend « le premier » sans ordre défini ; le poste accepte
    // dès qu'un exercice OUVERT couvre le jour (le serveur tranchera).
    if (!couvrants.any((e) => e.status == 'ouvert')) {
      return messageExerciceClos(couvrants.first.year, j);
    }

    return null;
  }

  /// Copie de `OuvertureExerciceService::refusOuverture($annee, FILET)` (serveur, ticket EX3) : l'exercice de [annee]
  /// n'existe pas, celui de l'année précédente existe et est OUVERT, le 1er janvier de [annee] est atteint (heure du
  /// Bénin), et moins de deux exercices sont ouverts.
  static bool filetOuvrirait(
    int annee,
    List<FiscalYear> exercices,
    DateTime aujourdhui,
  ) {
    if (exercices.any((e) => e.year == annee)) return false;
    final precedent = exercices.where((e) => e.year == annee - 1);
    if (precedent.isEmpty || precedent.first.status != 'ouvert') return false;
    if (_minuit(aujourdhui).isBefore(DateTime(annee))) return false;
    return exercices.where((e) => e.status == 'ouvert').length < 2;
  }

  /// `NoOpenFiscalYearException::message()` — mot pour mot.
  static String messageAucunExercice(DateTime jour) =>
      'Aucun exercice comptable ne couvre le ${jourFr(jour)}. '
      "Ouvrez l'exercice ${jour.year} (Comptabilité › Clôture d'exercice).";

  /// `ClosedFiscalYearException::message()` — mot pour mot.
  static String messageExerciceClos(int annee, DateTime jour) =>
      "L'exercice $annee est clôturé : aucune saisie ne peut être datée du ${jourFr(jour)}.";

  /// `VerifySaleDateAction::prefixe()` : « Vente refusée : » + le motif R4, première lettre en minuscule.
  static String prefixeVente(String motif) => motif.isEmpty
      ? 'Vente refusée : '
      : 'Vente refusée : ${motif[0].toLowerCase()}${motif.substring(1)}';

  /// `format('d/m/Y')` de Carbon.
  static String jourFr(DateTime jour) =>
      '${jour.day.toString().padLeft(2, '0')}/'
      '${jour.month.toString().padLeft(2, '0')}/${jour.year}';

  static DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);
}
