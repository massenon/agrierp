import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';

/// Statuts de pointage, tels que la maquette les nomme.
enum StatutPointage {
  present('present', 'Présent'),
  retard('retard', 'Retard'),
  absent('absent', 'Absent'),
  conge('conge', 'Congé'),
  maladie('maladie', 'Maladie');

  const StatutPointage(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutPointage depuis(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => present);
}

/// Une ligne de « Feuille de Pointage ».
class LignePointage {
  const LignePointage({
    required this.pointage,
    required this.employe,
    required this.envoye,
  });

  final AttendanceRecord pointage;
  final Employee? employe;

  /// ⚠️ Un pointage non envoyé n'existe que sur ce poste — et la paie du mois
  /// se calcule dessus.
  final bool envoye;

  StatutPointage get statut => StatutPointage.depuis(pointage.status);

  String get nom => employe == null
      ? 'Employé inconnu'
      : '${employe!.firstName} ${employe!.lastName}';
}

class DonneesPersonnel {
  const DonneesPersonnel({
    required this.employes,
    required this.stagiaires,
    required this.pointages,
    required this.jour,
    this.attestationsEmises,
  });

  final List<Employee> employes;
  final List<Internship> stagiaires;
  final List<LignePointage> pointages;
  final DateTime jour;

  List<LignePointage> get duJour => pointages
      .where(
        (p) =>
            p.pointage.attendanceDate.year == jour.year &&
            p.pointage.attendanceDate.month == jour.month &&
            p.pointage.attendanceDate.day == jour.day,
      )
      .toList();

  /// ⚠️ **UN RETARD EST UNE PRÉSENCE.** La règle vient du serveur
  /// (`FeuillePointage::getKpisProperty`) : compter les retards à part des
  /// présents ferait deux effectifs différents pour la même équipe.
  int get presents => duJour
      .where(
        (p) =>
            p.statut == StatutPointage.present ||
            p.statut == StatutPointage.retard,
      )
      .length;

  int get absents =>
      duJour.where((p) => p.statut == StatutPointage.absent).length;

  int get retards =>
      duJour.where((p) => p.statut == StatutPointage.retard).length;

  int get enAttenteDEnvoi => pointages.where((p) => !p.envoye).length;

  /// Employés qui n'ont pas encore de pointage aujourd'hui.
  List<Employee> nonPointes() {
    final pointes = duJour.map((p) => p.pointage.employeeId).toSet();
    return employes.where((e) => !pointes.contains(e.id)).toList();
  }

  /// ⚠️ **TOUJOURS `null`** : la paie se calcule sur le serveur — retenues
  /// CNSS, barème ITS, bulletins. Le poste ne reçoit ni `payslips` ni le
  /// barème, et recomposer un net à payer localement produirait un chiffre
  /// que la ferme ne retrouverait sur aucun bulletin.
  double? get masseSalariale => null;

  // ── Cartes de `registre-employes.html` (ticket F0.55) ─────────────────────

  /// « Employés actifs » de la maquette.
  ///
  /// ⚠️⚠️ **`is_active` ET `status` SONT DEUX CHOSES, ET LA MAQUETTE NE DIT PAS
  /// LAQUELLE ELLE COMPTE.** Le serveur ne sert que les employés
  /// `is_active = true` — sous contrat — et joint pour chacun un `status`
  /// (`actif` · `conge` · `suspendu`), qui dit son état du jour.
  ///
  /// Le compte retenu est celui de la table reçue, donc les employés **sous
  /// contrat** : un salarié en congé reste un employé de la ferme, et l'exclure
  /// ferait fondre l'effectif chaque fois que quelqu'un s'absente. Qui est là
  /// AUJOURD'HUI est déjà dit, et mieux, par « Présents » sur la feuille de
  /// pointage.
  ///
  /// ⚠️ **ARBITRAGE OUVERT** si le commanditaire lit « actifs » au sens de
  /// `status = actif` : le chiffre changerait, et la donnée permet les deux.
  int get employesActifs => employes.length;

  /// « Nouveaux (année) » — embauches de l'année civile en cours.
  ///
  /// ⚠️ Calculable ici, contrairement aux « Nouveaux (mois) » des fournisseurs :
  /// `hire_date` fait partie des sept colonnes servies, là où le référentiel
  /// fournisseur ne descend aucune date.
  int get nouveauxEmployesDeLAnnee => employes
      .where((e) => e.hireDate != null && e.hireDate!.year == jour.year)
      .length;

  // ── Cartes de `registre-stagiaires.html` (ticket F0.55) ───────────────────

  DateTime get _jourSeul => DateTime(jour.year, jour.month, jour.day);

  /// « Stagiaires Actifs » — stage commencé et non terminé au [jour].
  ///
  /// ⚠️ **UN STAGE SANS DATE DE FIN EST EN COURS**, pas terminé : `endDate` est
  /// `nullable` et une convention peut rester ouverte. Le traiter comme échu
  /// ferait disparaître le stagiaire du compte le jour même de son arrivée.
  int get stagiairesActifs => stagiaires.where((s) {
    final debut = s.startDate;
    if (debut == null || debut.isAfter(_jourSeul)) return false;
    final fin = s.endDate;
    return fin == null || !fin.isBefore(_jourSeul);
  }).length;

  /// « Frais Collectés » — frais de stage déjà réglés.
  double get fraisCollectes => stagiaires
      .where((s) => s.feePaid)
      .fold<double>(0, (t, s) => t + (s.monthlyFee ?? 0));

  /// « Frais en Attente » — frais de stage non encore réglés.
  ///
  /// ⚠️ **LES DEUX SE LISENT SUR LE MÊME `monthlyFee`**, séparés par `feePaid` :
  /// leur somme redonne le total dû par la promotion. C'est voulu, et c'est ce
  /// que la maquette montre.
  double get fraisEnAttente => stagiaires
      .where((s) => !s.feePaid)
      .fold<double>(0, (t, s) => t + (s.monthlyFee ?? 0));

  /// « Attestations émises » — le DÉCOMPTE DU SERVEUR (ticket F0.64).
  ///
  /// ⚠️⚠️ **PAS UN COMPTE FAIT AU POSTE** : Laravel n'a pas de table
  /// d'attestations émises, seulement des lignes d'audit
  /// `attestation.generated.stagiaire`, et le poste n'en détient que les cent
  /// dernières de TOUTE la ferme. Le serveur compte sur l'historique entier et
  /// envoie le nombre.
  ///
  /// ⚠️ **`null` TANT QU'IL N'A JAMAIS ÉTÉ REÇU** : « 0 » dirait qu'aucune
  /// attestation n'a été délivrée, alors que le poste n'en sait rien. Le tiret
  /// reste la réponse honnête avant la première synchronisation.
  final int? attestationsEmises;

  // ── Cartes de `gestion-paie.html` (ticket F0.55) ──────────────────────────
  //
  // ⚠️⚠️ **LES QUATRE SONT INCONNUES AU POSTE, ET AUCUNE NE DOIT ÊTRE
  // APPROCHÉE.** La paie se calcule sur le serveur : retenues CNSS, barème ITS,
  // bulletins. Le poste reçoit le salaire de BASE de chaque employé, et rien
  // d'autre.
  //
  // La tentation serait d'afficher la somme des salaires de base comme « masse
  // salariale ». Ce serait faux de deux façons : elle ignore primes et heures,
  // et surtout elle **exclut les charges patronales**, qui font partie du coût
  // et pas de la rémunération. La règle du projet est explicite —
  // **cotisations salariales et charges patronales ne se confondent pas** — et
  // un chiffre qui les mélange ou en oublie une moitié ne se retrouve sur
  // aucun bulletin.

  /// « Bulletins émis » — aucune table `payslips` ne descend au poste.
  int? get bulletinsEmis => null;

  /// « Charges Sociales (CNSS) » — calculées par le serveur, jamais ici.
  ///
  /// ⚠️ Le taux et l'assiette vivent dans les paramètres de l'entreprise, et
  /// la part PATRONALE ne se déduit pas de la part salariale.
  double? get chargesSociales => null;

  /// « En Attente de Paiement » — dépend d'un statut de bulletin.
  int? get bulletinsEnAttente => null;
}

/// Lectures et écritures de `prototype_html/personnel-stages.html`.
///
/// ⚠️⚠️ **LE POINTAGE EST L'ACTE DE TERRAIN PAR EXCELLENCE** : il se fait à 7 h
/// à la ferme, là où le réseau n'est pas. C'est le seul des cinq onglets que le
/// poste écrit.
///
/// ⚠️⚠️ **L'IDENTITÉ D'UN POINTAGE EST LE COUPLE (EMPLOYÉ, JOUR)**, pas son
/// UUID : le serveur porte `unique(employee_id, attendance_date)`. Le dépôt
/// applique la même règle localement — repointer quelqu'un le même jour corrige
/// son pointage au lieu d'en créer un second.
class PersonnelRepository {
  PersonnelRepository({required this.database, required this.identifiantPoste});

  final AppDatabase database;
  final String identifiantPoste;

  static const _uuid = Uuid();

  Future<DonneesPersonnel> charger({DateTime? jour}) async {
    final employes = await database.select(database.employees).get();
    final stagiaires = await database.select(database.internships).get();
    final pointages = await database.select(database.attendanceRecords).get();
    final emises =
        await (database.select(database.appSettings)..where(
              (r) =>
                  r.key.equals(SyncEngine.cleAttestationsEmises('stagiaire')),
            ))
            .getSingleOrNull();

    final parId = {for (final e in employes) e.id: e};

    return DonneesPersonnel(
      attestationsEmises: emises == null ? null : int.tryParse(emises.value),
      jour: jour ?? HeureBenin.maintenant(),
      employes: employes.toList()
        ..sort((a, b) => a.lastName.compareTo(b.lastName)),
      stagiaires: stagiaires.toList()
        ..sort(
          (a, b) => (b.startDate ?? DateTime(1970)).compareTo(
            a.startDate ?? DateTime(1970),
          ),
        ),
      pointages:
          (pointages.toList()
                ..sort((a, b) => b.attendanceDate.compareTo(a.attendanceDate)))
              .map(
                (p) => LignePointage(
                  pointage: p,
                  employe: parId[p.employeeId],
                  envoye: p.syncStatus == SyncStatus.synced,
                ),
              )
              .toList(),
    );
  }

  /// Enregistre un pointage LOCALEMENT, en attente d'envoi.
  ///
  /// ⚠️⚠️ **UN SEUL POINTAGE PAR EMPLOYÉ ET PAR JOUR.** Si la personne est déjà
  /// pointée ce jour-là, la ligne est CORRIGÉE — jamais doublée. Le serveur
  /// applique la même règle à la réception ; l'appliquer aussi ici évite qu'un
  /// chef d'équipe croie avoir créé deux lignes.
  Future<String> pointer({
    required String employeId,
    required DateTime jour,
    required StatutPointage statut,
    String? arrivee,
    String? depart,
  }) async {
    final jourSeul = DateTime(jour.year, jour.month, jour.day);

    final existant =
        await (database.select(database.attendanceRecords)..where(
              (t) =>
                  t.employeeId.equals(employeId) &
                  t.attendanceDate.equals(jourSeul),
            ))
            .getSingleOrNull();

    final id = existant?.id ?? _uuid.v4();

    final ligne = AttendanceRecordsCompanion.insert(
      id: id,
      deviceId: identifiantPoste,
      updatedAt: DateTime.now(),
      // ⚠️ Corrigé au poste = à renvoyer, même si la ligne venait du serveur.
      syncStatus: const Value(SyncStatus.pending),
      employeeId: employeId,
      attendanceDate: jourSeul,
      checkIn: Value(arrivee),
      checkOut: Value(depart),
      status: statut.code,
    );

    await database
        .into(database.attendanceRecords)
        .insert(ligne, onConflict: DoUpdate((_) => ligne));

    return id;
  }
}
