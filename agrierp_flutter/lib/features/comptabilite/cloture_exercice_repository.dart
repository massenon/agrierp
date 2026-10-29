import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/comptabilite/exercice_choisi.dart';
import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import 'comptabilite_repository.dart';
import 'documents_comptabilite.dart';
import 'rapprochement_repository.dart';

/// Une demande de clôture refusée AVANT d'être écrite : le motif, celui du web (mot pour mot).
class RefusCloture implements Exception {
  const RefusCloture(this.motif);

  final String motif;

  @override
  String toString() => motif;
}

/// Solde d'un compte de gestion (classe 6 ou 7) ou de bilan (classes 1 à 5) sur un exercice.
class SoldeCompteCloture {
  const SoldeCompteCloture({required this.compteId, required this.classe, required this.solde});

  final String compteId;
  final int classe;

  /// Débit − crédit, arrondi au centime.
  final double solde;
}

/// Ligne du report à nouveau : le solde de bilan d'un compte, côté débit OU côté crédit.
class LigneANouveau {
  const LigneANouveau({required this.compteId, required this.debit, required this.credit});

  final String compteId;
  final double debit;
  final double credit;
}

/// Ticket CP-4 — LES CALCULS DE LA CLÔTURE, transposition de `App\Services\ClotureExerciceService` (le point de passage du web)
/// et d'`OuvertureExerciceService::refusOuverture`, prouvée par une parité EXÉCUTÉE contre le vrai PHP
/// (`test/cloture_exercice_parite_php_test.dart`).
///
/// ⚠️ Le poste JUGE ICI ce qu'il sait juger (étapes, soldes, équilibre de l'à-nouveau, échéance) pour refuser AVANT d'écrire la
/// demande, avec les messages du web ; le SERVEUR reste le juge et rejoue tout à l'envoi. Les sommes se font en CENTIMES
/// ENTIERS : `SUM(debit) <> SUM(credit)` du SQL compare des décimales exactes, jamais des flottants.
abstract final class CalculCloture {
  static int _centimes(double v) => (v * 100).round();

  /// `round($v, 2)` de PHP.
  static double arrondi(double v) {
    final x = (v * 100).roundToDouble() / 100;
    return x == 0 ? 0 : x;
  }

  /// `{$ecart}` d'une chaîne PHP : un flottant sans zéro inutile (500 et non 500.0).
  static String flottantPhp(double v) {
    final a = arrondi(v);
    return a == a.truncateToDouble() ? a.toInt().toString() : a.toString();
  }

  /// Soldes par compte des écritures de l'exercice [exerciceId], pour les comptes dont la classe est dans [classes] : seuls
  /// ceux dont le débit diffère du crédit (`havingRaw SUM(debit) <> SUM(credit)`).
  static List<SoldeCompteCloture> _soldes({
    required String exerciceId,
    required Set<int> classes,
    required Iterable<AccountingEntry> ecritures,
    required Iterable<AccountingEntryLine> lignes,
    required Iterable<ChartOfAccount> comptes,
  }) {
    final dansExercice = {for (final e in ecritures) if (e.fiscalYearId == exerciceId) e.id};
    final classeDe = {for (final c in comptes) if (c.accountClass != null && classes.contains(c.accountClass)) c.id: c.accountClass!};

    final debits = <String, int>{};
    final credits = <String, int>{};
    for (final l in lignes) {
      if (!dansExercice.contains(l.entryId) || !classeDe.containsKey(l.accountId)) continue;
      debits[l.accountId] = (debits[l.accountId] ?? 0) + _centimes(l.debit);
      credits[l.accountId] = (credits[l.accountId] ?? 0) + _centimes(l.credit);
    }

    return [
      for (final id in debits.keys)
        if (debits[id] != credits[id])
          SoldeCompteCloture(compteId: id, classe: classeDe[id]!, solde: arrondi((debits[id]! - credits[id]!) / 100)),
    ];
  }

  /// `soldesDeGestion` : solde de chaque compte de classe 6/7 de l'exercice.
  static List<SoldeCompteCloture> soldesDeGestion(
    FiscalYear? exercice, {
    required Iterable<AccountingEntry> ecritures,
    required Iterable<AccountingEntryLine> lignes,
    required Iterable<ChartOfAccount> comptes,
  }) => exercice == null
      ? const []
      : _soldes(exerciceId: exercice.id, classes: {6, 7}, ecritures: ecritures, lignes: lignes, comptes: comptes);

  /// `indicateurs` : résultat provisoire (produits − charges) et nombre de comptes de gestion à solder.
  static ({double resultat, int comptesASolder}) indicateurs(List<SoldeCompteCloture> soldes) {
    var charges = 0.0;
    var produits = 0.0;
    for (final s in soldes) {
      if (s.classe == 6) charges += s.solde;
      if (s.classe == 7) produits += -s.solde;
    }
    return (resultat: arrondi(produits - charges), comptesASolder: soldes.length);
  }

  /// `lignesDAnouveau` : soldes de bilan (classes 1 à 5) tels que l'à-nouveau de N+1 les reportera.
  static List<LigneANouveau> lignesDAnouveau(
    FiscalYear exercice, {
    required Iterable<AccountingEntry> ecritures,
    required Iterable<AccountingEntryLine> lignes,
    required Iterable<ChartOfAccount> comptes,
  }) {
    final sortie = <LigneANouveau>[];
    for (final s in _soldes(exerciceId: exercice.id, classes: {1, 2, 3, 4, 5}, ecritures: ecritures, lignes: lignes, comptes: comptes)) {
      if (s.solde > 0) {
        sortie.add(LigneANouveau(compteId: s.compteId, debit: s.solde, credit: 0));
      } else if (s.solde < 0) {
        sortie.add(LigneANouveau(compteId: s.compteId, debit: 0, credit: s.solde.abs()));
      }
    }
    return sortie;
  }

  static String _f(double m) => '${DocumentsComptabilite.montant(m)} F';

  static String jourFr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';

  /// `motifRefusCloture` — pourquoi l'étape 3 est refusée, ou `null` si la clôture est admise. Dans l'ordre : échéance passée,
  /// exercice précédent clos, étape 1 confirmée, étape 2 faite, à-nouveau équilibré.
  ///
  /// [etape1Demandee] / [etape2Demandee] : une demande de l'étape est déjà en attente d'envoi — le serveur les jouera avant la
  /// clôture, dans l'ordre. L'à-nouveau n'est alors pas jugé ici (l'écriture de solde n'est pas encore au journal du poste).
  static String? motifRefusCloture(
    FiscalYear? exercice, {
    required DateTime maintenant,
    required List<FiscalYear> exercices,
    required Iterable<AccountingEntry> ecritures,
    required Iterable<AccountingEntryLine> lignes,
    required Iterable<ChartOfAccount> comptes,
    bool etape1Demandee = false,
    bool etape2Demandee = false,
  }) {
    if (exercice == null || exercice.status != 'ouvert') {
      return 'Cet exercice ne peut pas être clôturé (déjà clos ou introuvable).';
    }

    final fin = exercice.endDate ?? DateTime(exercice.year, 12, 31);
    final echeance = DateTime(fin.year, fin.month, fin.day, 23, 59, 59, 999, 999);
    if (!maintenant.isAfter(echeance)) {
      final lendemain = DateTime(fin.year, fin.month, fin.day + 1);
      return "L'exercice ${exercice.year} ne peut être clôturé qu'après son échéance du ${jourFr(fin)}, à partir du ${jourFr(lendemain)}.";
    }

    final precedent = exercices.where((e) => e.year == exercice.year - 1).firstOrNull;
    if (precedent != null && precedent.status == 'ouvert') {
      return "L'exercice ${precedent.year} est encore ouvert : clôturez-le avant l'exercice ${exercice.year}.";
    }

    if (exercice.step1ConfirmedAt == null && !etape1Demandee) {
      return "Étape 1 non confirmée : marquez les travaux d'inventaire de ${exercice.year} comme terminés avant de clôturer.";
    }

    final aSolder = etape2Demandee ? 0 : soldesDeGestion(exercice, ecritures: ecritures, lignes: lignes, comptes: comptes).length;
    if (aSolder > 0) {
      return 'Étape 2 non faite : $aSolder compte(s) de charges ou de produits de ${exercice.year} restent à solder. '
          'Lancez « Calculer et Solder » avant de clôturer.';
    }

    if (!etape2Demandee) {
      final anouveau = lignesDAnouveau(exercice, ecritures: ecritures, lignes: lignes, comptes: comptes);
      final debit = arrondi(anouveau.fold(0.0, (s, l) => s + l.debit));
      final credit = arrondi(anouveau.fold(0.0, (s, l) => s + l.credit));
      if ((debit - credit).abs() >= 0.01) {
        return "L'à-nouveau de l'exercice ${exercice.year + 1} serait déséquilibré (débit ${_f(debit)}, crédit ${_f(credit)}) : "
            'les comptes de bilan de ${exercice.year} ne s\'équilibrent pas. Corrigez l\'écart au Journal Comptable avant de clôturer.';
      }
    }

    return null;
  }

  /// `OuvertureExerciceService::refusOuverture($annee, BOUTON)` — pourquoi l'exercice [annee] ne peut pas s'ouvrir par le bouton
  /// aujourd'hui, ou `null`. Le bouton est offert dès le 1er décembre de l'année précédente.
  static String? refusOuvertureParBouton(int annee, {required DateTime maintenant, required List<FiscalYear> exercices}) {
    if (exercices.any((e) => e.year == annee)) return "L'exercice $annee existe déjà.";

    final precedent = exercices.where((e) => e.year == annee - 1).firstOrNull;
    if (precedent == null) {
      return "L'exercice $annee ne peut s'ouvrir qu'à la suite de l'exercice ${annee - 1}, qui n'existe pas.";
    }

    final premierJour = DateTime(annee - 1, 12, 1);
    if (maintenant.isBefore(premierJour)) {
      return "L'exercice $annee ne peut s'ouvrir qu'à partir du ${jourFr(premierJour)}.";
    }

    final ouverts = [for (final e in exercices) if (e.status == 'ouvert') e.year]..sort();
    if (ouverts.length >= 2) {
      return 'Deux exercices sont déjà ouverts (${ouverts.join(' et ')}) : clôturez l\'exercice ${ouverts.first} avant d\'ouvrir $annee.';
    }

    return null;
  }
}

/// Une demande de clôture pas encore jouée par le serveur : en attente d'envoi, ou refusée avec son motif.
class DemandeCloture {
  const DemandeCloture({required this.demande, this.motifRefus});

  final FiscalClosureRequest demande;
  final String? motifRefus;

  bool get refusee => demande.syncStatus == SyncStatus.conflict;

  Map<String, dynamic> get contenu => jsonDecode(demande.payload) as Map<String, dynamic>;

  /// Ce que la demande veut faire, en clair (liste « Demandes de clôture »).
  String get libelle {
    final c = contenu;
    final annee = c['year'];
    final mois = c['period'] is String && (c['period'] as String).length == 7 ? _libelleMois(c['period'] as String) : null;
    return switch (demande.kind) {
      'cloturer_periode' => 'Clôture du mois de ${mois ?? c['period']}',
      'decloturer_periode' => 'Déclôture du mois de ${mois ?? c['period']}',
      'confirmer_etape1' => "Étape 1 de la clôture de l'exercice $annee : travaux d'inventaire terminés",
      'solder_comptes_gestion' => "Étape 2 de la clôture de l'exercice $annee : solde des comptes de gestion",
      'cloturer_exercice' => "Clôture de l'exercice $annee",
      'rouvrir_exercice' => "Réouverture de l'exercice $annee",
      'ouvrir_exercice_suivant' || 'ouvrir_exercice' => "Ouverture de l'exercice $annee",
      _ => demande.kind,
    };
  }

  static String _libelleMois(String periode) =>
      EtatExercice.libelleMois(DateTime(int.parse(periode.substring(0, 4)), int.parse(periode.substring(5, 7))));
}

/// Le lettrage bancaire de l'exercice (`BankReconciliationService::tauxDeLettrage`).
class LettrageExercice {
  const LettrageExercice({required this.taux, required this.lignes, required this.lettrees, required this.comptesSansReleve});

  /// `null` : aucun relevé importé sur l'exercice — jamais 100 %.
  final int? taux;
  final int lignes;
  final int lettrees;
  final int comptesSansReleve;
}

/// Tout ce que l'écran « Clôture d'exercice » lit, pris une fois.
class DonneesCloture {
  DonneesCloture({
    required this.exercices,
    required this.clotures,
    required this.demandes,
    required this.compta,
    required this.comptes,
    required this.maintenant,
  });

  /// Du plus récent au plus ancien.
  final List<FiscalYear> exercices;

  /// Une ligne par mois clôturé (déclôtures comprises), le plus récent d'abord.
  final List<PeriodicClosure> clotures;

  /// En attente d'envoi ou refusées, les plus récentes d'abord.
  final List<DemandeCloture> demandes;

  final DonneesComptabilite compta;
  final List<ChartOfAccount> comptes;
  final DateTime maintenant;

  FiscalYear? exercice(int annee) => exercices.where((e) => e.year == annee).firstOrNull;

  /// `mount()` : le plus ANCIEN exercice encore ouvert (EX3), sinon l'année du jour.
  int get anneeInitiale {
    final ouverts = [for (final e in exercices) if (e.status == 'ouvert') e.year]..sort();
    return ouverts.isEmpty ? maintenant.year : ouverts.first;
  }

  Iterable<AccountingEntry> get _ecritures => [for (final e in compta.journal) e.ecriture];

  Iterable<AccountingEntryLine> get _lignes => compta.lignesParEcriture.values.expand((l) => l);

  /// Une demande de ce [genre] pas encore jouée ni refusée, pour l'exercice [annee] ou le mois [periode] ou la clôture [clotureId].
  DemandeCloture? demandeEnAttente(String genre, {int? annee, String? periode, String? clotureId}) {
    for (final d in demandes) {
      if (d.refusee || d.demande.kind != genre) continue;
      final c = d.contenu;
      if (annee != null && c['year'] != annee) continue;
      if (periode != null && c['period'] != periode) continue;
      if (clotureId != null && c['closure_id'] != clotureId) continue;
      return d;
    }
    return null;
  }

  List<SoldeCompteCloture> soldesDeGestion(FiscalYear? exercice) =>
      CalculCloture.soldesDeGestion(exercice, ecritures: _ecritures, lignes: _lignes, comptes: comptes);

  ({double resultat, int comptesASolder}) indicateurs(FiscalYear? exercice) => CalculCloture.indicateurs(soldesDeGestion(exercice));

  /// Le motif qui grise « Clôturer l'Exercice N », ou `null` (`motifRefusCloture`, EX4).
  String? motifRefusCloture(FiscalYear? exercice) {
    if (exercice != null && demandeEnAttente('cloturer_exercice', annee: exercice.year) != null) {
      return "Une demande de clôture de l'exercice ${exercice.year} est déjà en attente d'envoi : synchronisez le poste.";
    }

    return CalculCloture.motifRefusCloture(
      exercice,
      maintenant: maintenant,
      exercices: exercices,
      ecritures: _ecritures,
      lignes: _lignes,
      comptes: comptes,
      etape1Demandee: exercice != null && demandeEnAttente('confirmer_etape1', annee: exercice.year) != null,
      etape2Demandee: exercice != null && demandeEnAttente('solder_comptes_gestion', annee: exercice.year) != null,
    );
  }

  /// `getPeutOuvrirSuivantProperty` : N ouvert et N+1 ouvrable par le bouton.
  bool peutOuvrirSuivant(FiscalYear? exercice) =>
      exercice != null &&
      exercice.status == 'ouvert' &&
      CalculCloture.refusOuvertureParBouton(exercice.year + 1, maintenant: maintenant, exercices: exercices) == null;

  /// Les 12 derniers mois, le mois courant d'abord (`getPeriodesCloturablesProperty`) : `AAAA-MM` → « Octobre 2026 ».
  List<(String, String)> get periodesCloturables => [
    for (var i = 0; i < 12; i++)
      () {
        final mois = DateTime(maintenant.year, maintenant.month - i);
        return ('${mois.year.toString().padLeft(4, '0')}-${mois.month.toString().padLeft(2, '0')}', EtatExercice.libelleMois(mois));
      }(),
  ];

  PeriodicClosure? clotureDe(String periode) => clotures.where((c) => c.period == periode).firstOrNull;

  /// `getPeriodeDejaClotureeProperty` : une clôture du mois qui n'a pas été déclôturée.
  bool periodeDejaCloturee(String periode) => clotures.any((c) => c.period == periode && c.reopenedAt == null);

  /// `getPeriodeBalanceProperty` : la balance du mois (`FinancialReportService::balanceGenerale`). Un journal INCOMPLET
  /// (tirage partiel) ne bloque pas ici : le serveur juge.
  ({bool equilibree, double ecart}) periodeBalance(String periode) {
    final debut = DateTime(int.parse(periode.substring(0, 4)), int.parse(periode.substring(5, 7)));
    final b = compta.balanceGenerale(debut: debut, fin: DateTime(debut.year, debut.month + 1, 0));
    return (equilibree: b.equilibree || b.journalIncomplet, ecart: b.ecart);
  }
}

/// Ticket CP-4 — LA CLÔTURE D'EXERCICE au poste (`Livewire\Comptabilite\ClotureExercice`). UN SEUL ÉCRIVAIN de `fiscal_closure_requests`.
///
/// ⚠️⚠️ **LE POSTE N'ÉCRIT JAMAIS `fiscal_years` NI `periodic_closures`.** Une clôture est destructive et se juge au serveur : chaque
/// geste écrit une DEMANDE (`pending`) que le serveur rejoue par `ClotureExerciceService` (mêmes gardes, mêmes écritures, mêmes
/// motifs) ; l'exercice clos, le report à nouveau et le verrou des mois redescendent au tirage de confirmation. Ce dépôt refuse
/// AVANT d'écrire, avec les messages du web, ce que le poste sait juger localement.
class ClotureExerciceRepository {
  ClotureExerciceRepository({required this.database, this.deviceId = 'poste', Uuid? uuid, this.horloge}) : _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final String deviceId;
  final Uuid _uuid;
  final DateTime Function()? horloge;

  DateTime _maintenant() => (horloge ?? HeureBenin.maintenant)();

  /// L'année civile en cours, à l'heure du Bénin : celle du premier exercice.
  int anneeEnCours() => _maintenant().year;

  Future<DonneesCloture> charger() async {
    final exercices = await database.select(database.fiscalYears).get()
      ..sort((a, b) => b.year.compareTo(a.year));
    final clotures = await (database.select(database.periodicClosures)..orderBy([(c) => OrderingTerm.desc(c.period)])).get();
    final enAttente = await (database.select(database.fiscalClosureRequests)
          ..where((d) => d.syncStatus.equalsValue(SyncStatus.synced).not())
          ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]))
        .get();
    final refus = {for (final c in await database.select(database.syncConflicts).get()) c.id: c.reason};
    final compta = await ComptabiliteRepository(database: database, deviceId: deviceId).charger();
    final comptes = await database.select(database.chartOfAccounts).get();

    return DonneesCloture(
      exercices: exercices,
      clotures: clotures,
      demandes: [
        for (final d in enAttente)
          DemandeCloture(demande: d, motifRefus: d.syncStatus == SyncStatus.conflict ? refus['fiscal_closure_requests:${d.id}'] : null),
      ],
      compta: compta,
      comptes: comptes,
      maintenant: _maintenant(),
    );
  }

  /// Le lettrage bancaire de [exercice] (carte « Lettrage Bancaire », `BankReconciliationService::tauxDeLettrage`) : le
  /// rapprochement de chaque compte qui a un relevé sur l'exercice ; « aucun relevé » rend `taux` nul, jamais 100 %.
  Future<LettrageExercice> lettrage(FiscalYear exercice) async {
    final debut = exercice.startDate ?? DateTime(exercice.year, 1, 1);
    final fin = exercice.endDate ?? DateTime(exercice.year, 12, 31);
    DateTime jour(DateTime d) => DateTime(d.year, d.month, d.day);
    bool dedans(DateTime d) => !jour(d).isBefore(jour(debut)) && !jour(d).isAfter(jour(fin));

    final releves = [for (final r in await database.select(database.bankStatementLines).get()) if (dedans(r.statementDate)) r];
    final comptesAvecReleve = {for (final r in releves) r.accountId};

    final depot = RapprochementRepository(database: database, deviceId: deviceId);
    var lignes = 0;
    var lettrees = 0;
    for (final compte in comptesAvecReleve) {
      final r = await depot.rapprocher(compte, debut, fin);
      for (final l in [...r.livre, ...r.releve]) {
        lignes++;
        if (l.pointee) lettrees++;
      }
    }

    // Comptes de trésorerie (classe 5) mouvementés sur l'exercice dont aucun relevé n'a été importé.
    final classe5 = {for (final c in await database.select(database.chartOfAccounts).get()) if (c.accountClass == 5) c.id};
    final ecrituresDeLaPeriode = {for (final e in await database.select(database.accountingEntries).get()) if (dedans(e.entryDate)) e.id};
    final sansReleve = {
      for (final l in await database.select(database.accountingEntryLines).get())
        if (ecrituresDeLaPeriode.contains(l.entryId) && classe5.contains(l.accountId) && !comptesAvecReleve.contains(l.accountId)) l.accountId,
    };

    return LettrageExercice(
      taux: lignes > 0 ? (100 * lettrees / lignes).round() : null,
      lignes: lignes,
      lettrees: lettrees,
      comptesSansReleve: sansReleve.length,
    );
  }

  // ── Gestes (chacun écrit UNE demande) ──────────────────────────────────────────────────────────────────────────

  Future<String> _demander(String genre, Map<String, Object?> contenu) async {
    final id = _uuid.v4();
    await database.into(database.fiscalClosureRequests).insert(
      FiscalClosureRequestsCompanion.insert(
        id: id,
        deviceId: deviceId,
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: _maintenant(),
        kind: genre,
        payload: jsonEncode(contenu),
      ),
    );
    return id;
  }

  /// Une demande identique déjà en attente n'est pas doublée.
  void _refuserDoublon(DonneesCloture d, String genre, String motif, {int? annee, String? periode, String? clotureId}) {
    if (d.demandeEnAttente(genre, annee: annee, periode: periode, clotureId: clotureId) != null) throw RefusCloture(motif);
  }

  /// « Confirmer la Clôture du Mois » (`cloturerPeriode`) : le mois n'est pas déjà clôturé, sa balance est équilibrée.
  Future<void> cloturerPeriode(String periode) async {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(periode)) throw const RefusCloture('Mois à clôturer illisible (attendu : AAAA-MM).');
    final d = await charger();

    if (d.periodeDejaCloturee(periode)) throw const RefusCloture('Ce mois est déjà clôturé.');
    _refuserDoublon(d, 'cloturer_periode', "Une demande de clôture de ce mois est déjà en attente d'envoi.", periode: periode);

    final balance = d.periodeBalance(periode);
    if (!balance.equilibree) {
      throw RefusCloture("Balance déséquilibrée (écart de ${CalculCloture.flottantPhp(balance.ecart)} FCFA) — corrigez l'écart avant de clôturer ce mois.");
    }

    await _demander('cloturer_periode', {'period': periode});
  }

  /// « Confirmer la Déclôture » (`decloturerPeriode`, administrateur) : la clôture existe et n'est pas déjà levée.
  Future<void> decloturerPeriode(String clotureId) async {
    final d = await charger();
    final c = d.clotures.where((x) => x.id == clotureId).firstOrNull;
    if (c == null || c.reopenedAt != null) throw const RefusCloture("Ce mois n'est pas clôturé.");
    _refuserDoublon(d, 'decloturer_periode', "Une demande de déclôture de ce mois est déjà en attente d'envoi.", clotureId: clotureId);

    await _demander('decloturer_periode', {'closure_id': clotureId, 'period': c.period});
  }

  /// « Marquer comme terminé » (étape 1, `confirmStep1`).
  Future<void> confirmerEtape1(int annee) async {
    final d = await charger();
    final exercice = d.exercice(annee);
    if (exercice == null) throw RefusCloture("Aucun exercice $annee n'existe.");
    if (exercice.status != 'ouvert') throw const RefusCloture('Cet exercice ne peut pas être clôturé (déjà clos ou introuvable).');
    _refuserDoublon(d, 'confirmer_etape1', "Une demande de confirmation de l'étape 1 est déjà en attente d'envoi.", annee: annee);

    await _demander('confirmer_etape1', {'year': annee});
  }

  /// « Calculer et Solder » (étape 2, `soldeComptesGestion`) : des comptes de gestion à solder, le compte 131/139 au plan.
  Future<void> solderComptesGestion(int annee) async {
    final d = await charger();
    final exercice = d.exercice(annee);
    if (exercice == null || d.soldesDeGestion(exercice).isEmpty) {
      throw const RefusCloture('Aucun compte de charges/produits à solder pour cet exercice.');
    }
    _refuserDoublon(d, 'solder_comptes_gestion', "Une demande de solde des comptes de gestion est déjà en attente d'envoi.", annee: annee);

    final resultat = d.indicateurs(exercice).resultat;
    final code = resultat >= 0 ? '131' : '139';
    if (!d.comptes.any((c) => c.code == code)) {
      throw const RefusCloture('Compte 131/139 introuvable dans le plan comptable — créez-le avant de solder.');
    }

    await _demander('solder_comptes_gestion', {'year': annee});
  }

  /// « Confirmer la Clôture » (étape 3, `confirmCloture`) : les gardes de la clôture (EX4).
  Future<void> cloturerExercice(int annee) async {
    final d = await charger();
    final refus = d.motifRefusCloture(d.exercice(annee));
    if (refus != null) throw RefusCloture(refus);

    await _demander('cloturer_exercice', {'year': annee});
  }

  /// « Confirmer la Réouverture » (`rouvrirExercice`, administrateur) : l'exercice est clos et N+1 ne l'est pas.
  Future<void> rouvrirExercice(int annee) async {
    final d = await charger();
    final exercice = d.exercice(annee);
    if (exercice == null) throw RefusCloture("Aucun exercice $annee n'existe.");
    if (exercice.status != 'cloture') throw RefusCloture("L'exercice $annee n'est pas clôturé.");
    final suivant = d.exercice(annee + 1);
    if (suivant?.status == 'cloture') {
      throw RefusCloture("L'exercice ${annee + 1} est clôturé : rouvrez-le d'abord, son report à nouveau dépend de $annee.");
    }
    _refuserDoublon(d, 'rouvrir_exercice', "Une demande de réouverture de l'exercice $annee est déjà en attente d'envoi.", annee: annee);

    await _demander('rouvrir_exercice', {'year': annee});
  }

  /// « Ouvrir l'exercice N+1 » (`ouvrirExerciceSuivant`) : à partir du 1er décembre, N+1 absent, jamais trois exercices ouverts.
  Future<void> ouvrirExerciceSuivant(int annee) async {
    final d = await charger();
    final refus = CalculCloture.refusOuvertureParBouton(annee, maintenant: d.maintenant, exercices: d.exercices);
    if (refus != null) throw RefusCloture(refus);
    _refuserDoublon(d, 'ouvrir_exercice_suivant', "Une demande d'ouverture de l'exercice $annee est déjà en attente d'envoi.", annee: annee);

    await _demander('ouvrir_exercice_suivant', {'year': annee});
  }

  /// Abandonne une demande REFUSÉE (ou en attente) : elle ne part plus, son conflit est levé.
  Future<void> abandonner(String id) async {
    await database.transaction(() async {
      await (database.delete(database.fiscalClosureRequests)..where((t) => t.id.equals(id))).go();
      await (database.delete(database.syncConflicts)..where((c) => c.id.equals('fiscal_closure_requests:$id'))).go();
    });
  }
}
