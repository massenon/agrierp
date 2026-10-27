import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/database/sync_columns.dart';
import '../../core/temps/heure_benin.dart';
import 'calcul_paie.dart';

/// Refus d'une saisie RH au poste : les règles du web (`SaisieEmployeAction`, `SaisieStagiaireAction`,
/// `FeuillePointage`), reproduites AVANT d'écrire, mêmes messages. [champs] : message par champ.
class RefusSaisieRh implements Exception {
  const RefusSaisieRh(this.champs);

  final Map<String, String> champs;

  @override
  String toString() => champs.values.join(' ');
}

/// Une ligne de « Gestion de la Paie » pour le mois choisi — les mêmes colonnes que `GestionPaie::getRowsProperty()`.
class LignePaie {
  const LignePaie({
    required this.employe,
    required this.brut,
    required this.joursAbsence,
    required this.retenueAbsence,
    required this.retenueCnss,
    required this.retenueIts,
    required this.net,
    required this.chargesPatronales,
    required this.bulletin,
    required this.demande,
    required this.baremeItsRenseigne,
  });

  final Employee employe;
  final double brut;

  /// `null` pour un bulletin réglé (le web n'affiche plus les jours une fois réglé).
  final int? joursAbsence;
  final double retenueAbsence;
  final double retenueCnss;
  final double retenueIts;
  final double net;
  final double chargesPatronales;

  /// Le bulletin reçu du serveur, `null` tant que la paie n'est pas réglée.
  final Payslip? bulletin;

  /// La demande de règlement faite sur CE poste, `null` sans demande.
  final PayslipRequest? demande;
  final bool baremeItsRenseigne;

  bool get reglee => bulletin != null;

  /// Demande partie ou en attente d'envoi, sans bulletin encore reçu.
  bool get demandeEnCours => bulletin == null && demande != null && demande!.syncStatus != SyncStatus.conflict;

  bool get demandeRefusee => bulletin == null && demande != null && demande!.syncStatus == SyncStatus.conflict;
}

/// Les cartes et les lignes de la paie d'un mois.
class PaieDuMois {
  const PaieDuMois({required this.periode, required this.lignes, required this.baremeItsRenseigne});

  /// `AAAA-MM`.
  final String periode;
  final List<LignePaie> lignes;
  final bool baremeItsRenseigne;

  double get masseSalariale => lignes.fold(0, (t, l) => t + l.brut);
  int get bulletinsEmis => lignes.where((l) => l.reglee).length;
  double get chargesCnss => lignes.fold(0, (t, l) => t + l.retenueCnss);
  int get enAttente => lignes.where((l) => !l.reglee).length;
}

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
    this.absencesStagiaires = const [],
  });

  final List<Employee> employes;
  final List<Internship> stagiaires;
  final List<LignePointage> pointages;
  final DateTime jour;

  /// Ticket RH-2 — absences ACTIVES de tous les stagiaires, les plus récentes d'abord.
  final List<InternshipAbsence> absencesStagiaires;

  List<InternshipAbsence> absencesDe(String stagiaireId) =>
      absencesStagiaires.where((a) => a.internshipId == stagiaireId).toList();

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

  // Les cartes de `gestion-paie.html` sont calculées par [PersonnelRepository.paie] (ticket RH-4), comme au web.
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
    // Ticket RH-1 / RH-3 — les archivés ne sont pas listés (comme le web : `where('is_active', true)`).
    final employes = await (database.select(database.employees)..where((t) => t.isActive.equals(true))).get();
    final stagiaires = await database.select(database.internships).get();
    final pointages = await (database.select(database.attendanceRecords)..where((t) => t.isActive.equals(true))).get();
    final absences = await (database.select(database.internshipAbsences)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.absenceDate)]))
        .get();
    final emises =
        await (database.select(database.appSettings)..where(
              (r) =>
                  r.key.equals(SyncEngine.cleAttestationsEmises('stagiaire')),
            ))
            .getSingleOrNull();

    final parId = {for (final e in employes) e.id: e};

    return DonneesPersonnel(
      attestationsEmises: emises == null ? null : int.tryParse(emises.value),
      absencesStagiaires: absences,
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

    // Ticket RH-3 — règles du web (`FeuillePointage::savePointage`, `pushAttendance`) : jour ≤ aujourd'hui, heures « HH:mm ».
    final erreurs = <String, String>{};
    final aujourdhui = HeureBenin.aujourdhui();
    if (jourSeul.isAfter(DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day))) {
      erreurs['date'] = 'La date de pointage doit être antérieure ou égale à aujourd\'hui.';
    }
    for (final (champ, valeur) in [('arrivee', arrivee), ('depart', depart)]) {
      if (valeur != null && !RegExp(r'^\d{2}:\d{2}(:\d{2})?$').hasMatch(valeur)) {
        erreurs[champ] = 'Le champ ${champ == 'arrivee' ? "heure d'arrivée" : 'heure de départ'} doit être au format HH:mm.';
      }
    }
    if (erreurs.isNotEmpty) throw RefusSaisieRh(erreurs);

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
      // Repointer réactive un pointage archivé (le web fait de même : `is_active => true`).
      isActive: const Value(true),
    );

    await database
        .into(database.attendanceRecords)
        .insert(ligne, onConflict: DoUpdate((_) => ligne));

    return id;
  }

  /// Ticket RH-3 — archive un pointage (`FeuillePointage::archiveRecord`) : la ligne reste, `is_active` faux, renvoyée.
  Future<void> archiverPointage(String id) async {
    await (database.update(database.attendanceRecords)..where((t) => t.id.equals(id))).write(
      AttendanceRecordsCompanion(
        isActive: const Value(false),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(DateTime.now()),
        deviceId: Value(identifiantPoste),
      ),
    );
  }

  // ── Ticket RH-1 : employés ──────────────────────────────────────────────────

  /// Fonctions proposées par la modale du web (`registre-employes.blade.php`).
  static const fonctions = ["Chef d'élevage", 'Comptable', 'Gardien', 'Vendeuse POS', 'Ouvrier agricole'];

  /// `actif` · `conge` · `suspendu`, libellés du web.
  static const statutsEmploye = {'actif': 'Actif', 'conge': 'Congé', 'suspendu': 'Suspendu'};

  /// Crée ou modifie un employé LOCALEMENT (`pending`), avec les règles de `SaisieEmployeAction::regles()`.
  /// Un employé archivé ne se modifie plus (message du web). Rend l'identifiant.
  Future<String> enregistrerEmploye({
    String? id,
    required String prenom,
    required String nom,
    required String fonction,
    required DateTime? embauche,
    double? salaire,
    required String statut,
  }) async {
    final erreurs = <String, String>{};
    if (prenom.trim().isEmpty) erreurs['prenom'] = 'Le champ prénom est obligatoire.';
    if (prenom.trim().length > 100) erreurs['prenom'] = 'Le champ prénom ne peut pas dépasser 100 caractères.';
    if (nom.trim().isEmpty) erreurs['nom'] = 'Le champ nom est obligatoire.';
    if (nom.trim().length > 100) erreurs['nom'] = 'Le champ nom ne peut pas dépasser 100 caractères.';
    if (fonction.trim().isEmpty) erreurs['fonction'] = 'Le champ fonction est obligatoire.';
    if (embauche == null) erreurs['embauche'] = "Le champ date d'embauche est obligatoire.";
    if (salaire != null && salaire < 0) erreurs['salaire'] = 'Le champ salaire de base doit être supérieur ou égal à 0.';
    if (!statutsEmploye.containsKey(statut)) erreurs['statut'] = 'Le statut sélectionné est invalide.';
    if (erreurs.isNotEmpty) throw RefusSaisieRh(erreurs);

    if (id != null) {
      final existant = await (database.select(database.employees)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existant != null && !existant.isActive) {
        throw const RefusSaisieRh({'employe': 'Cet employé est archivé : il ne peut plus être modifié.'});
      }
    }

    final identifiant = id ?? _uuid.v4();
    final ligne = EmployeesCompanion.insert(
      id: identifiant,
      deviceId: identifiantPoste,
      syncStatus: const Value(SyncStatus.pending),
      updatedAt: DateTime.now(),
      firstName: prenom.trim(),
      lastName: nom.trim(),
      position: Value(fonction.trim()),
      baseSalary: Value(salaire),
      hireDate: Value(DateTime(embauche!.year, embauche.month, embauche.day)),
      status: Value(statut),
      isActive: const Value(true),
    );
    await database.into(database.employees).insert(ligne, onConflict: DoUpdate((_) => ligne));

    return identifiant;
  }

  /// Archive un employé (`RegistreEmployes::archiveEmployee`) : `is_active` faux, renvoyé ; un second archivage ne fait rien.
  Future<void> archiverEmploye(String id) async {
    final existant = await (database.select(database.employees)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existant == null || !existant.isActive) return;
    await (database.update(database.employees)..where((t) => t.id.equals(id))).write(
      EmployeesCompanion(
        isActive: const Value(false),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(DateTime.now()),
        deviceId: Value(identifiantPoste),
      ),
    );
  }

  // ── Ticket RH-2 : stagiaires et absences ────────────────────────────────────

  /// Crée ou modifie un stagiaire LOCALEMENT (`pending`), règles de `SaisieStagiaireAction::regles()`. Rend l'identifiant.
  Future<String> enregistrerStagiaire({
    String? id,
    required String prenom,
    required String nom,
    required String etablissement,
    required DateTime? debut,
    DateTime? fin,
    double? frais,
    bool fraisRegles = false,
  }) async {
    final erreurs = <String, String>{};
    if (prenom.trim().isEmpty) erreurs['prenom'] = 'Le champ prénom est obligatoire.';
    if (nom.trim().isEmpty) erreurs['nom'] = 'Le champ nom est obligatoire.';
    if (etablissement.trim().isEmpty) erreurs['etablissement'] = 'Le champ établissement est obligatoire.';
    if (etablissement.trim().length > 150) erreurs['etablissement'] = 'Le champ établissement ne peut pas dépasser 150 caractères.';
    if (debut == null) erreurs['debut'] = 'Le champ date de début est obligatoire.';
    if (debut != null && fin != null && fin.isBefore(debut)) {
      erreurs['fin'] = 'Le champ date de fin doit être une date postérieure ou égale à date de début.';
    }
    if (frais != null && frais < 0) erreurs['frais'] = 'Le champ frais de stage doit être supérieur ou égal à 0.';
    if (erreurs.isNotEmpty) throw RefusSaisieRh(erreurs);

    final identifiant = id ?? _uuid.v4();
    final existant = id == null ? null : await (database.select(database.internships)..where((t) => t.id.equals(id))).getSingleOrNull();
    final ligne = InternshipsCompanion.insert(
      id: identifiant,
      deviceId: identifiantPoste,
      syncStatus: const Value(SyncStatus.pending),
      updatedAt: DateTime.now(),
      firstName: prenom.trim(),
      lastName: nom.trim(),
      school: Value(etablissement.trim()),
      startDate: Value(DateTime(debut!.year, debut.month, debut.day)),
      endDate: Value(fin == null ? null : DateTime(fin.year, fin.month, fin.day)),
      monthlyFee: Value(frais),
      feePaid: Value(fraisRegles),
      // L'identité ATT-1 (naissance, civilité) n'est pas dans cette modale (web non plus) : conservée telle quelle.
      birthDate: Value(existant?.birthDate),
      birthPlace: Value(existant?.birthPlace),
      civilite: Value(existant?.civilite ?? 'M.'),
    );
    await database.into(database.internships).insert(ligne, onConflict: DoUpdate((_) => ligne));

    return identifiant;
  }

  /// Note une absence (`RegistreStagiaires::saveAbsence`) : date requise, motif facultatif (≤ 255). Rend l'identifiant.
  Future<String> noterAbsence({required String stagiaireId, required DateTime? jour, String motif = ''}) async {
    final erreurs = <String, String>{};
    if (jour == null) erreurs['date'] = 'Le champ date est obligatoire.';
    if (motif.trim().length > 255) erreurs['motif'] = 'Le champ motif ne peut pas dépasser 255 caractères.';
    if (erreurs.isNotEmpty) throw RefusSaisieRh(erreurs);

    final id = _uuid.v4();
    await database.into(database.internshipAbsences).insert(
      InternshipAbsencesCompanion.insert(
        id: id,
        deviceId: identifiantPoste,
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: DateTime.now(),
        internshipId: stagiaireId,
        absenceDate: DateTime(jour!.year, jour.month, jour.day),
        reason: Value(motif.trim().isEmpty ? null : motif.trim()),
        isActive: const Value(true),
      ),
    );

    return id;
  }

  /// Archive une absence (`RegistreStagiaires::deleteAbsence`, 14.55 : jamais effacée).
  Future<void> archiverAbsence(String id) async {
    await (database.update(database.internshipAbsences)..where((t) => t.id.equals(id))).write(
      InternshipAbsencesCompanion(
        isActive: const Value(false),
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: Value(DateTime.now()),
        deviceId: Value(identifiantPoste),
      ),
    );
  }

  // ── Ticket RH-4 : paie ──────────────────────────────────────────────────────

  /// `AAAA-MM` d'une date.
  static String periodeDe(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Le barème ITS reçu (tranches actives, planchers croissants).
  Future<List<TrancheIts>> baremeIts() async => [
    for (final t in await (database.select(database.incomeTaxBrackets)..orderBy([(t) => OrderingTerm.asc(t.fromAmount)])).get())
      TrancheIts(plancher: t.fromAmount, plafond: t.toAmount, taux: t.rate),
  ];

  /// Les taux de paie reçus (`company_settings`), défauts du web tant que rien n'a été tiré.
  Future<TauxPaie> tauxPaie() async {
    final e = await database.select(database.companySettings).getSingleOrNull();
    if (e == null) return TauxPaie.defaut;

    return TauxPaie(
      cnssSalarie: e.cnssEmployeeRate,
      vps: e.vpsRate,
      cnssPatronalePension: e.cnssEmployerPensionRate,
      cnssPatronaleFamille: e.cnssEmployerFamilyRate,
      cnssPatronaleRisque: e.cnssEmployerRiskRate,
    );
  }

  /// Jours d'absence RETENUS sur une période : pointages `absent` ACTIFS du mois (`ReglementPaieService::joursAbsence`).
  Future<int> joursAbsence(String employeId, String periode) async {
    final annee = int.parse(periode.substring(0, 4));
    final mois = int.parse(periode.substring(5, 7));
    final lignes = await (database.select(database.attendanceRecords)..where(
          (t) => t.employeeId.equals(employeId) & t.status.equals('absent') & t.isActive.equals(true),
        ))
        .get();

    return lignes.where((p) => p.attendanceDate.year == annee && p.attendanceDate.month == mois).length;
  }

  /// La paie d'un mois, ligne par employé actif — `GestionPaie::getRowsProperty()` : un bulletin reçu l'emporte (ses
  /// montants), sinon le calcul local (`CalculPaie`, même formule que le serveur).
  Future<PaieDuMois> paie(String periode) async {
    final employes = await (database.select(database.employees)..where((t) => t.isActive.equals(true))).get()
      ..sort((a, b) => a.lastName.compareTo(b.lastName));
    final bareme = await baremeIts();
    final taux = await tauxPaie();
    final annee = int.parse(periode.substring(0, 4));
    final mois = int.parse(periode.substring(5, 7));
    final bulletins = {
      for (final b in await database.select(database.payslips).get())
        if (b.employeeId != null && b.periodMonth != null && b.periodMonth!.year == annee && b.periodMonth!.month == mois)
          b.employeeId!: b,
    };
    final demandes = {
      for (final d in await (database.select(database.payslipRequests)..where((t) => t.periodMonth.equals(periode))).get())
        d.employeeId: d,
    };

    final lignes = <LignePaie>[];
    for (final e in employes) {
      final bulletin = bulletins[e.id];
      if (bulletin != null) {
        lignes.add(LignePaie(
          employe: e,
          brut: bulletin.grossSalary ?? 0,
          joursAbsence: null,
          retenueAbsence: bulletin.absenceDeduction ?? 0,
          retenueCnss: bulletin.cnssDeduction ?? 0,
          retenueIts: bulletin.itsDeduction ?? 0,
          net: bulletin.netSalary,
          chargesPatronales: bulletin.chargesPatronales ?? 0,
          bulletin: bulletin,
          demande: demandes[e.id],
          baremeItsRenseigne: true,
        ));
        continue;
      }
      final jours = await joursAbsence(e.id, periode);
      final calcul = CalculPaie.calculer(e.baseSalary ?? 0, jours, bareme: bareme, taux: taux);
      lignes.add(LignePaie(
        employe: e,
        brut: calcul.brut,
        joursAbsence: jours,
        retenueAbsence: calcul.retenueAbsence,
        retenueCnss: calcul.cnssSalariale,
        retenueIts: calcul.its,
        net: calcul.net,
        chargesPatronales: calcul.totalChargesPatronales,
        bulletin: null,
        demande: demandes[e.id],
        baremeItsRenseigne: calcul.baremeItsRenseigne,
      ));
    }

    return PaieDuMois(periode: periode, lignes: lignes, baremeItsRenseigne: bareme.isNotEmpty);
  }

  /// « Valider le règlement » au poste : une DEMANDE (`pending`), réglée par le serveur. Une demande déjà en file pour
  /// (employé, période) n'est pas doublée ; une demande refusée est relancée.
  Future<String> demanderReglement({required String employeId, required String periode}) async {
    final existante = await (database.select(database.payslipRequests)..where(
          (t) => t.employeeId.equals(employeId) & t.periodMonth.equals(periode),
        ))
        .getSingleOrNull();
    if (existante != null) {
      if (existante.syncStatus == SyncStatus.conflict) {
        await (database.update(database.payslipRequests)..where((t) => t.id.equals(existante.id)))
            .write(const PayslipRequestsCompanion(syncStatus: Value(SyncStatus.pending)));
      }
      return existante.id;
    }

    final id = _uuid.v4();
    await database.into(database.payslipRequests).insert(
      PayslipRequestsCompanion.insert(
        id: id,
        deviceId: identifiantPoste,
        syncStatus: const Value(SyncStatus.pending),
        updatedAt: DateTime.now(),
        employeeId: employeId,
        periodMonth: periode,
        requestedAt: HeureBenin.versInstant(HeureBenin.maintenant()),
      ),
    );

    return id;
  }
}
