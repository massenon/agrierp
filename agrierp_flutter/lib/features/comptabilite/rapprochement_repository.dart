import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import 'comptabilite_repository.dart';
import 'soldes_exercice.dart';

/// Une ligne du rapprochement : écriture du livre ou ligne de relevé, pointée ou non.
class LigneRapprochement {
  LigneRapprochement({required this.id, required this.date, required this.libelle, required this.montant});

  final String id;
  final DateTime date;
  final String libelle;
  final double montant;
  bool pointee = false;
}

/// Résultat de `BankReconciliationService::reconcile`, champ pour champ.
class Rapprochement {
  const Rapprochement({
    required this.livre,
    required this.releve,
    required this.ouverture,
    required this.soldeLivre,
    required this.soldeReleve,
    required this.enInstance,
    required this.nouveauNonSaisi,
    required this.ecart,
  });

  final List<LigneRapprochement> livre;
  final List<LigneRapprochement> releve;
  final double ouverture;
  final double soldeLivre;
  final double soldeReleve;
  final double enInstance;
  final double nouveauNonSaisi;
  final double ecart;

  bool get equilibre => ecart.abs() < 0.01;
}

/// Ticket CP-5 — RAPPROCHEMENT BANCAIRE au poste (`Livewire\Comptabilite\RapprochementBancaire`). UN SEUL ÉCRIVAIN de
/// `bank_statement_imports`.
///
/// Le rapprochement se CALCULE au poste, transposition de `BankReconciliationService::reconcile` (solde du livre à l'ouverture
/// par la règle R1, lettrage glouton au même montant à 5 jours près, chaque ligne appariée une seule fois), prouvée par une
/// parité exécutée. L'import d'un relevé est une DEMANDE : le serveur lit le CSV et les lignes redescendent au tirage.
class RapprochementRepository {
  RapprochementRepository({required this.database, this.deviceId = 'poste', Uuid? uuid, this.horloge}) : _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final String deviceId;
  final Uuid _uuid;
  final DateTime Function()? horloge;

  /// `BankReconciliationService::TOLERANCE_JOURS`.
  static const toleranceJours = 5;

  /// Taille maximale d'un relevé (`max:2048` Ko du Blade).
  static const tailleMaxOctets = 2048 * 1024;

  static DateTime _jour(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// Comptes de trésorerie du sélecteur : classe 5 actifs, rattachés à un compte de trésorerie, ou déjà mouvementés par une
  /// écriture ou un relevé (`getTreasuryAccountsProperty`).
  Future<List<ChartOfAccount>> comptes() async {
    final rattaches = {for (final t in await database.select(database.treasuryAccounts).get()) if (t.accountCode != null) t.accountCode!};
    final mouvementes = {
      for (final l in await database.select(database.accountingEntryLines).get()) l.accountId,
      for (final r in await database.select(database.bankStatementLines).get()) r.accountId,
    };
    final plan = await (database.select(database.chartOfAccounts)..where((c) => c.accountClass.equals(5) & c.isActive.equals(true))).get();
    return [for (final c in plan) if (rattaches.contains(c.code) || mouvementes.contains(c.id)) c]..sort((a, b) => a.code.compareTo(b.code));
  }

  /// `reconcile($accountId, $start, $end)`.
  Future<Rapprochement> rapprocher(String compteId, DateTime debut, DateTime fin) async {
    final d0 = _jour(debut);
    final d1 = _jour(fin);

    final compta = await ComptabiliteRepository(database: database, deviceId: deviceId).charger();
    final ouverture = SoldesExercice.arrondi(compta.soldesExercice.soldes(debut, inclus: false).netDe(compteId));

    // Un à-nouveau n'est pas une opération à rapprocher : il est déjà dans l'ouverture.
    final livre = <LigneRapprochement>[];
    for (final e in compta.journal) {
      final ec = e.ecriture;
      if (SoldesExercice.estANouveau(ec)) continue;
      final jour = _jour(ec.entryDate);
      if (jour.isBefore(d0) || jour.isAfter(d1)) continue;
      for (final l in e.lignes.where((l) => l.accountId == compteId)) {
        final parts = (ec.reference ?? '').split('—');
        final libelle = (parts.length > 1 ? parts.sublist(1).join('—') : parts.first).trim();
        livre.add(LigneRapprochement(id: l.id, date: jour, libelle: libelle, montant: SoldesExercice.arrondi(l.debit - l.credit)));
      }
    }
    livre.sort((a, b) => a.date.compareTo(b.date));

    final releve = <LigneRapprochement>[];
    for (final r in await (database.select(database.bankStatementLines)..where((x) => x.accountId.equals(compteId))).get()) {
      final jour = _jour(r.statementDate);
      if (jour.isBefore(d0) || jour.isAfter(d1)) continue;
      releve.add(LigneRapprochement(id: r.id, date: jour, libelle: r.label, montant: SoldesExercice.arrondi(r.amount)));
    }
    releve.sort((a, b) => a.date.compareTo(b.date));

    lettrer(livre, releve);

    double somme(Iterable<double> v) => v.fold(0.0, (s, x) => s + x);
    final soldeLivre = SoldesExercice.arrondi(ouverture + somme(livre.map((l) => l.montant)));
    final soldeReleve = SoldesExercice.arrondi(ouverture + somme(releve.map((l) => l.montant)));
    final enInstance = SoldesExercice.arrondi(somme(livre.where((l) => !l.pointee).map((l) => l.montant)));
    final nouveau = SoldesExercice.arrondi(somme(releve.where((l) => !l.pointee).map((l) => l.montant)));
    final projete = SoldesExercice.arrondi(soldeLivre - enInstance + nouveau);

    return Rapprochement(
      livre: livre, releve: releve, ouverture: ouverture, soldeLivre: soldeLivre, soldeReleve: soldeReleve,
      enInstance: enInstance, nouveauNonSaisi: nouveau, ecart: SoldesExercice.arrondi(projete - soldeReleve),
    );
  }

  /// `match` : pour chaque ligne du livre, la ligne de relevé LIBRE de même montant (à 0,01 près) la plus proche en date, dans
  /// la tolérance ; chaque ligne n'est appariée qu'une fois, de sorte qu'un doublon réel ne soit jamais masqué.
  static void lettrer(List<LigneRapprochement> livre, List<LigneRapprochement> releve) {
    for (final l in livre) {
      LigneRapprochement? meilleur;
      int? meilleurEcart;
      for (final r in releve) {
        if (r.pointee || (r.montant - l.montant).abs() >= 0.01) continue;
        final ecart = r.date.difference(l.date).inDays.abs();
        if (ecart > toleranceJours) continue;
        if (meilleurEcart == null || ecart < meilleurEcart) {
          meilleur = r;
          meilleurEcart = ecart;
        }
      }
      if (meilleur != null) {
        l.pointee = true;
        meilleur.pointee = true;
      }
    }
  }

  /// Règles de `importReleve` : un fichier non vide de 2 Mo au plus, un compte choisi. L'illisible est jugé par le SERVEUR, qui
  /// l'ignore ligne à ligne (comme au web).
  Map<String, String> validerImport({required String compteId, required String contenu, required int octets}) {
    final e = <String, String>{};
    if (compteId.isEmpty) e['accountId'] = 'Le champ compte est obligatoire.';
    if (contenu.trim().isEmpty) {
      e['releve'] = 'Le champ relevé est obligatoire.';
    } else if (octets > tailleMaxOctets) {
      e['releve'] = 'Le fichier relevé ne doit pas dépasser 2048 kilo-octets.';
    }
    return e;
  }

  /// Écrit la DEMANDE d'import (`pending`) ; rend son identifiant.
  Future<String> importerReleve({required String compteId, required String contenu, required int octets, String? nomFichier}) async {
    final refus = validerImport(compteId: compteId, contenu: contenu, octets: octets);
    if (refus.isNotEmpty) throw RapprochementRefuse(refus);

    final id = _uuid.v4();
    await database.into(database.bankStatementImports).insert(
      BankStatementImportsCompanion.insert(
        id: id,
        deviceId: deviceId,
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: (horloge ?? HeureBenin.maintenant)(),
        accountId: compteId,
        content: contenu,
        fileName: Value(nomFichier),
      ),
    );
    return id;
  }

  /// Imports pas encore lus par le serveur (en attente) ou refusés, avec le motif.
  Future<List<({BankStatementImport demande, String? motif})>> importsEnAttente() async {
    final refus = {for (final c in await database.select(database.syncConflicts).get()) c.id: c.reason};
    final lignes = await (database.select(database.bankStatementImports)..where((r) => r.syncStatus.equalsValue(SyncStatus.synced).not())).get();
    return [for (final r in lignes) (demande: r, motif: r.syncStatus == SyncStatus.conflict ? refus['bank_statement_imports:${r.id}'] : null)];
  }
}

class RapprochementRefuse implements Exception {
  const RapprochementRefuse(this.erreurs);

  final Map<String, String> erreurs;

  @override
  String toString() => erreurs.values.join(' ');
}
