import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/rh/personnel_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tickets RH-1 à RH-4 — LE CRUD RH DU POSTE (PRD `docs/prd/rh-crud-poste.md`).
///
/// Employés, stagiaires, absences de stagiaire, pointages (modification, archivage) et demandes de règlement de paie
/// s'écrivent au poste, hors ligne, en `pending` ; le tirage ne les écrase jamais ; l'envoi part sous les clés que le
/// serveur rejoue (`SaisieEmployeAction`, `SaisieStagiaireAction`, `pushAttendance`, `ReglementPaieService`) ; un refus
/// devient `conflict` et se relance. Les absorbeurs restent STRICTS.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-27T12:00:00Z'};
  final List<Map<String, dynamic>> envois = [];

  /// Identifiants refusés à l'envoi (motif unique), par table.
  final refus = <String, Map<String, String>>{};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [
                    for (final e in value)
                      if (e is Map && e['id'] is String && !(refus[key]?.containsKey(e['id']) ?? false)) e['id'],
                  ],
                  'rejected': [
                    for (final e in value)
                      if (e is Map && e['id'] is String && (refus[key]?.containsKey(e['id']) ?? false))
                        {'id': e['id'], 'reason': refus[key]![e['id']]},
                  ],
                },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SyncEngine moteur;
  late PersonnelRepository depot;

  String uuid(String graine) => graine.padRight(36, '0');

  Map<String, dynamic> employeJson(String id, {Object? nom = 'TOSSOU', Object? actif = true, Object? salaire = 45000}) => {
    'id': id, 'first_name': 'Ange', 'last_name': nom, 'position': 'Ouvrier agricole', 'base_salary': salaire,
    'hire_date': '2026-10-01', 'status': 'actif', 'is_active': actif, 'updated_at': '2026-10-20T08:00:00+01:00',
  };

  Map<String, dynamic> stagiaireJson(String id, {Object? nom = 'ADJOVI'}) => {
    'id': id, 'first_name': 'Félicité', 'last_name': nom, 'school': 'Lycée agricole de Sékou', 'start_date': '2026-02-01',
    'end_date': '2026-05-31', 'monthly_fee': 25000, 'fee_paid': false, 'civilite': 'Mme',
  };

  Map<String, dynamic> absenceJson(String id, String stagiaire, {Object? actif = true, Object? jour = '2026-03-02'}) =>
      {'id': id, 'internship_id': stagiaire, 'absence_date': jour, 'reason': 'Maladie', 'is_active': actif};

  Map<String, dynamic> pointageJson(String id, String employe, {Object? actif = true, String statut = 'absent', String jour = '2026-10-05'}) =>
      {'id': id, 'employee_id': employe, 'attendance_date': jour, 'check_in': null, 'check_out': null, 'status': statut, 'is_active': actif};

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 27, 14),
    );
    depot = PersonnelRepository(database: db, identifiantPoste: 'poste-test');
  });
  tearDown(() async => db.close());

  Future<Employee> employe(String id) => (db.select(db.employees)..where((t) => t.id.equals(id))).getSingle();

  group('employés (RH-1)', () {
    test('⚠️⚠️ créé au poste : pending, identifiant tiré ici, listé, pointable', () async {
      final id = await depot.enregistrerEmploye(prenom: ' Ange ', nom: 'TOSSOU', fonction: 'Ouvrier agricole', embauche: DateTime(2026, 10, 1), salaire: 45000, statut: 'actif');

      final e = await employe(id);
      expect(id, hasLength(36));
      expect(e.syncStatus, SyncStatus.pending);
      expect(e.deviceId, 'poste-test');
      expect(e.firstName, 'Ange');
      expect(e.isActive, isTrue);
      expect((await depot.charger()).employes.single.id, id);
    });

    test('les règles du web, AVANT d\'écrire : nom, fonction, embauche obligatoires ; salaire ≥ 0 ; statut connu', () async {
      Future<Map<String, String>> refus(Future<void> Function() g) async {
        try {
          await g();
        } on RefusSaisieRh catch (e) {
          return e.champs;
        }
        return {};
      }

      expect(await refus(() => depot.enregistrerEmploye(prenom: '', nom: '', fonction: '', embauche: null, statut: 'parti')), {
        'prenom': 'Le champ prénom est obligatoire.',
        'nom': 'Le champ nom est obligatoire.',
        'fonction': 'Le champ fonction est obligatoire.',
        'embauche': "Le champ date d'embauche est obligatoire.",
        'statut': 'Le statut sélectionné est invalide.',
      });
      expect((await refus(() => depot.enregistrerEmploye(prenom: 'A', nom: 'B', fonction: 'C', embauche: DateTime(2026), salaire: -1, statut: 'actif'))).keys, ['salaire']);
      expect(await db.select(db.employees).get(), isEmpty);
    });

    test('modifié : la ligne entière repart ; archivé : is_active faux, repart ; un second archivage ne fait rien', () async {
      final id = await depot.enregistrerEmploye(prenom: 'Ange', nom: 'TOSSOU', fonction: 'Gardien', embauche: DateTime(2026, 10, 1), statut: 'actif');
      await (db.update(db.employees)..where((t) => t.id.equals(id))).write(const EmployeesCompanion(syncStatus: Value(SyncStatus.synced)));

      await depot.enregistrerEmploye(id: id, prenom: 'Ange', nom: 'TOSSOU', fonction: 'Gardien', embauche: DateTime(2026, 10, 1), salaire: 50000, statut: 'conge');
      var e = await employe(id);
      expect(e.syncStatus, SyncStatus.pending);
      expect(e.baseSalary, 50000);
      expect(e.status, 'conge');

      await (db.update(db.employees)..where((t) => t.id.equals(id))).write(const EmployeesCompanion(syncStatus: Value(SyncStatus.synced)));
      await depot.archiverEmploye(id);
      e = await employe(id);
      expect(e.isActive, isFalse);
      expect(e.syncStatus, SyncStatus.pending);
      expect((await depot.charger()).employes, isEmpty, reason: 'archivé : plus listé, plus pointable');

      await (db.update(db.employees)..where((t) => t.id.equals(id))).write(const EmployeesCompanion(syncStatus: Value(SyncStatus.synced)));
      await depot.archiverEmploye(id);
      expect((await employe(id)).syncStatus, SyncStatus.synced, reason: 'rien n\'est réécrit');
    });

    /// RH-Q1 — les archivés sont listés à part (filtre « Archivé »), jamais parmi les actifs ni dans les cartes.
    test('RH-Q1 — les employés archivés se lisent par le filtre « archive », à part des actifs', () async {
      final actif = await depot.enregistrerEmploye(prenom: 'Koffi', nom: 'ADJOVI', fonction: 'Gardien', embauche: DateTime(2026, 10, 1), statut: 'conge');
      final archive = await depot.enregistrerEmploye(prenom: 'Aline', nom: 'DOSSOU', fonction: 'Gardien', embauche: DateTime(2026, 10, 1), statut: 'actif');
      await depot.archiverEmploye(archive);

      final d = await depot.charger();
      expect(d.employes.map((e) => e.id), [actif]);
      expect(d.employesArchives.map((e) => e.id), [archive]);
      expect(d.employesFiltres('').map((e) => e.id), [actif]);
      expect(d.employesFiltres('conge').map((e) => e.id), [actif]);
      expect(d.employesFiltres('actif'), isEmpty, reason: 'l\'archivé était « actif » : il ne compte plus nulle part');
      expect(d.employesFiltres('archive').map((e) => e.id), [archive]);
      expect(d.employesActifs, 1);
    });

    test('⚠️ un employé archivé ne se modifie plus (message du web)', () async {
      final id = await depot.enregistrerEmploye(prenom: 'Ange', nom: 'TOSSOU', fonction: 'Gardien', embauche: DateTime(2026, 10, 1), statut: 'actif');
      await depot.archiverEmploye(id);

      await expectLater(
        depot.enregistrerEmploye(id: id, prenom: 'Ange', nom: 'TOSSOU', fonction: 'Gardien', embauche: DateTime(2026, 10, 1), statut: 'actif'),
        throwsA(isA<RefusSaisieRh>().having((e) => e.champs['employe'], 'employe', contains('archivé'))),
      );
    });

    test('⚠️⚠️ l\'envoi part sous les clés de `pushEmployees`, est acquitté ; un refus devient conflict et se relance', () async {
      final id = await depot.enregistrerEmploye(prenom: 'Ange', nom: 'TOSSOU', fonction: 'Gardien', embauche: DateTime(2026, 10, 1), salaire: 45000, statut: 'actif');
      serveur.tirage = {'server_time': '2026-10-27T12:00:00Z'};

      await moteur.synchroniser();

      final envoye = (serveur.envois.single['employees'] as List).single as Map;
      expect(envoye, {
        'id': id, 'first_name': 'Ange', 'last_name': 'TOSSOU', 'position': 'Gardien', 'hire_date': '2026-10-01',
        'base_salary': 45000.0, 'status': 'actif', 'is_active': true, 'device_id': 'poste-test',
      });
      expect((await employe(id)).syncStatus, SyncStatus.synced);

      // Modifié puis refusé par le serveur (employé archivé au web entre-temps) : conflit avec le motif, relançable.
      await depot.enregistrerEmploye(id: id, prenom: 'Ange', nom: 'TOSSOU', fonction: 'Gardien', embauche: DateTime(2026, 10, 1), salaire: 60000, statut: 'actif');
      serveur.refus['employees'] = {id: 'Cet employé est archivé : il ne peut plus être modifié.'};
      final r = await moteur.synchroniser();
      expect(r.rejete, 1);
      expect((await employe(id)).syncStatus, SyncStatus.conflict);
      final conflit = (await db.select(db.syncConflicts).get()).single;
      expect(conflit.sourceTable, 'employees');
      expect(conflit.reason, contains('archivé'));

      await moteur.relancer(conflit);
      expect((await employe(id)).syncStatus, SyncStatus.pending);
    });

    test('⚠️⚠️ le tirage fusionne : un employé pending/conflict n\'est JAMAIS écrasé ; un archivé au web cesse d\'être listé', () async {
      final local = await depot.enregistrerEmploye(prenom: 'Ange', nom: 'LOCAL', fonction: 'Gardien', embauche: DateTime(2026, 10, 1), statut: 'actif');
      serveur.tirage = {
        'server_time': '2026-10-27T12:00:00Z',
        'employees': [employeJson(local, nom: 'ÉCRASÉ'), employeJson(uuid('e2'), nom: 'ARCHIVÉ', actif: false), employeJson(uuid('e3'), nom: 'SERVEUR')],
      };
      // Le serveur « refuse » l'envoi de la ligne locale pour qu'elle reste pending au tirage de confirmation.
      serveur.refus['employees'] = {local: 'non'};

      await moteur.synchroniser();

      expect((await employe(local)).lastName, 'LOCAL');
      expect((await employe(uuid('e2'))).isActive, isFalse);
      expect((await employe(uuid('e3'))).deviceId, 'serveur');
      expect((await depot.charger()).employes.map((e) => e.lastName), ['LOCAL', 'SERVEUR']);
    });

    for (final (cas, fautif) in <(String, Map<String, dynamic>)>[
      ('identifiant invalide', employeJson('court')),
      ('servi deux fois', employeJson(uuid('e1'))),
      ('nom absent', employeJson(uuid('e2'), nom: null)),
      ('nom qui n\'est pas un texte', employeJson(uuid('e2'), nom: 12)),
    ]) {
      test('⚠️⚠️ STRICT — $cas : rien n\'est écrit', () async {
        serveur.tirage = {'server_time': '2026-10-27T12:00:00Z', 'employees': [employeJson(uuid('e1')), fautif]};

        await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));

        expect(await db.select(db.employees).get(), isEmpty);
      });
    }
  });

  group('stagiaires et absences (RH-2)', () {
    test('créé puis modifié au poste ; une fin avant le début est refusée ; l\'identité ATT-1 est conservée', () async {
      final id = await depot.enregistrerStagiaire(prenom: 'Félicité', nom: 'ADJOVI', etablissement: 'Sékou', debut: DateTime(2026, 2, 1), fin: DateTime(2026, 5, 31), frais: 25000);
      await (db.update(db.internships)..where((t) => t.id.equals(id))).write(const InternshipsCompanion(birthPlace: Value('Pobè'), civilite: Value('Mme'), syncStatus: Value(SyncStatus.synced)));

      await expectLater(
        depot.enregistrerStagiaire(id: id, prenom: 'Félicité', nom: 'ADJOVI', etablissement: 'Sékou', debut: DateTime(2026, 2, 1), fin: DateTime(2026, 1, 1)),
        throwsA(isA<RefusSaisieRh>().having((e) => e.champs.keys, 'champs', ['fin'])),
      );

      await depot.enregistrerStagiaire(id: id, prenom: 'Félicité', nom: 'ADJOVI', etablissement: 'Sékou', debut: DateTime(2026, 2, 1), fraisRegles: true);
      final s = await (db.select(db.internships)..where((t) => t.id.equals(id))).getSingle();
      expect(s.feePaid, isTrue);
      expect(s.endDate, isNull);
      expect(s.syncStatus, SyncStatus.pending);
      expect(s.birthPlace, 'Pobè', reason: 'la modale ne touche pas à l\'identité ATT-1');
      expect(s.civilite, 'Mme');
    });

    test('⚠️⚠️ absence notée puis archivée : pending, listée active seulement ; l\'envoi part avec le stagiaire, dans l\'ordre du serveur', () async {
      final s = await depot.enregistrerStagiaire(prenom: 'Félicité', nom: 'ADJOVI', etablissement: 'Sékou', debut: DateTime(2026, 2, 1));
      final a1 = await depot.noterAbsence(stagiaireId: s, jour: DateTime(2026, 3, 2), motif: ' Maladie ');
      final a2 = await depot.noterAbsence(stagiaireId: s, jour: DateTime(2026, 3, 3));
      await expectLater(depot.noterAbsence(stagiaireId: s, jour: null), throwsA(isA<RefusSaisieRh>()));

      await depot.archiverAbsence(a2);
      final d = await depot.charger();
      expect(d.absencesDe(s).map((a) => a.id), [a1]);
      expect(d.absencesDe(s).single.reason, 'Maladie');

      await moteur.synchroniser();
      final envoi = serveur.envois.single;
      expect((envoi['internships'] as List).single['id'], s);
      final absences = (envoi['internship_absences'] as List).cast<Map>();
      expect(absences.map((a) => a['id']), [a1, a2]);
      expect(absences.firstWhere((a) => a['id'] == a2)['is_active'], isFalse);
      expect(absences.first['absence_date'], '2026-03-02');
      expect(SyncEngine.ordreDuServeur.indexOf('internships'), lessThan(SyncEngine.ordreDuServeur.indexOf('internship_absences')));
      expect(SyncEngine.ordreDuServeur.indexOf('employees'), lessThan(SyncEngine.ordreDuServeur.indexOf('attendance_records')));
      expect(SyncEngine.ordreDuServeur.indexOf('attendance_records'), lessThan(SyncEngine.ordreDuServeur.indexOf('payslip_requests')));
      for (final id in [a1, a2]) {
        expect((await (db.select(db.internshipAbsences)..where((t) => t.id.equals(id))).getSingle()).syncStatus, SyncStatus.synced);
      }
    });

    test('le tirage sert les absences (archivées comprises) et le barème ITS ; une absence pending reste intouchable', () async {
      final s = await depot.enregistrerStagiaire(prenom: 'Félicité', nom: 'ADJOVI', etablissement: 'Sékou', debut: DateTime(2026, 2, 1));
      final locale = await depot.noterAbsence(stagiaireId: s, jour: DateTime(2026, 3, 9));
      serveur.refus['internship_absences'] = {locale: 'non'};
      serveur.refus['internships'] = {s: 'non'};
      serveur.tirage = {
        'server_time': '2026-10-27T12:00:00Z',
        'internships': [stagiaireJson(uuid('s9'))],
        'internship_absences': [absenceJson(locale, s, jour: '2026-01-01'), absenceJson(uuid('a2'), uuid('s9')), absenceJson(uuid('a3'), uuid('s9'), actif: false)],
        'income_tax_brackets': [
          {'id': uuid('t1'), 'from_amount': 0, 'to_amount': 60000, 'rate': 0},
          {'id': uuid('t2'), 'from_amount': 60000, 'to_amount': null, 'rate': 10},
        ],
      };

      await moteur.synchroniser();

      final mienne = await (db.select(db.internshipAbsences)..where((t) => t.id.equals(locale))).getSingle();
      expect(mienne.absenceDate, DateTime(2026, 3, 9), reason: 'jamais écrasée');
      expect((await (db.select(db.internshipAbsences)..where((t) => t.id.equals(uuid('a3')))).getSingle()).isActive, isFalse);
      expect((await depot.charger()).absencesDe(uuid('s9')).map((a) => a.id), [uuid('a2')]);
      final bareme = await depot.baremeIts();
      expect(bareme.map((t) => t.taux), [0, 10]);
      expect(bareme.last.plafond, isNull);
    });
  });

  group('pointages (RH-3)', () {
    /// RH-Q3 (décision client du 27/10/2026 : NE PAS LIMITER) — un pointage de plus de 60 jours, reçu du serveur, compte
    /// dans la paie de SON mois : le serveur sert désormais toute la table (famille paginée).
    test('RH-Q3 — un pointage ancien reçu du serveur compte dans la paie de son mois', () async {
      final e = await depot.enregistrerEmploye(prenom: 'Kossi', nom: 'AGBODJI', fonction: 'Gardien', embauche: DateTime(2025, 3, 1), salaire: 100000, statut: 'actif');
      serveur.tirage = {
        'server_time': '2026-10-27T12:00:00Z',
        'attendance_records': [pointageJson(uuid('p-ancien'), e, jour: '2026-06-15'), pointageJson(uuid('p-ancien-2'), e, jour: '2026-06-16')],
      };

      await moteur.synchroniser();

      expect(await depot.joursAbsence(e, '2026-06'), 2);
      expect((await depot.paie('2026-06')).lignes.single.joursAbsence, 2);
      expect(await depot.joursAbsence(e, '2026-10'), 0);
    });

    test('⚠️⚠️ archivé au poste : ne compte plus (cartes, absences de la paie), repart avec is_active faux', () async {
      final e = await depot.enregistrerEmploye(prenom: 'Kossi', nom: 'AGBODJI', fonction: 'Gardien', embauche: DateTime(2025, 3, 1), salaire: 100000, statut: 'actif');
      final p = await depot.pointer(employeId: e, jour: DateTime(2026, 10, 5), statut: StatutPointage.absent);
      expect(await depot.joursAbsence(e, '2026-10'), 1);

      await depot.archiverPointage(p);

      expect(await depot.joursAbsence(e, '2026-10'), 0);
      expect((await depot.charger()).pointages, isEmpty);
      await moteur.synchroniser();
      final envoye = (serveur.envois.single['attendance_records'] as List).single as Map;
      expect(envoye['is_active'], isFalse);
      expect(envoye['attendance_date'], '2026-10-05');
    });

    test('une date future ou une heure illisible sont refusées avant d\'écrire ; repointer réactive', () async {
      final e = await depot.enregistrerEmploye(prenom: 'Kossi', nom: 'AGBODJI', fonction: 'Gardien', embauche: DateTime(2025, 3, 1), statut: 'actif');

      await expectLater(depot.pointer(employeId: e, jour: DateTime(2099, 1, 1), statut: StatutPointage.present), throwsA(isA<RefusSaisieRh>()));
      await expectLater(depot.pointer(employeId: e, jour: DateTime(2026, 10, 5), statut: StatutPointage.present, arrivee: '7h'), throwsA(isA<RefusSaisieRh>()));

      final p = await depot.pointer(employeId: e, jour: DateTime(2026, 10, 5), statut: StatutPointage.absent);
      await depot.archiverPointage(p);
      await depot.pointer(employeId: e, jour: DateTime(2026, 10, 5), statut: StatutPointage.present, arrivee: '07:00');
      final ligne = await (db.select(db.attendanceRecords)..where((t) => t.id.equals(p))).getSingle();
      expect(ligne.isActive, isTrue);
      expect(ligne.status, 'present');
    });

    test('⚠️ le tirage sert is_active : un pointage archivé au web cesse de compter ici', () async {
      final e = await depot.enregistrerEmploye(prenom: 'Kossi', nom: 'AGBODJI', fonction: 'Gardien', embauche: DateTime(2025, 3, 1), statut: 'actif');
      serveur.refus['employees'] = {e: 'non'};
      serveur.tirage = {
        'server_time': '2026-10-27T12:00:00Z',
        'attendance_records': [pointageJson(uuid('p1'), e, actif: false), pointageJson(uuid('p2'), e, jour: '2026-10-06')],
      };

      await moteur.synchroniser();

      expect(await depot.joursAbsence(e, '2026-10'), 1);
      expect((await depot.charger()).pointages.single.pointage.id, uuid('p2'));
    });
  });

  group('paie (RH-4)', () {
    Future<void> baremeEtTaux() async {
      await db.batch((b) => b.insertAll(db.incomeTaxBrackets, [
        IncomeTaxBracketsCompanion.insert(id: uuid('t1'), fromAmount: 0, toAmount: const Value(60000), rate: 0),
        IncomeTaxBracketsCompanion.insert(id: uuid('t2'), fromAmount: 60000, toAmount: const Value(150000), rate: 10),
        IncomeTaxBracketsCompanion.insert(id: uuid('t3'), fromAmount: 150000, toAmount: const Value(null), rate: 15),
      ]));
      await db.into(db.companySettings).insert(const CompanySettingsCompanion(
        id: Value('unique'), cnssEmployeeRate: Value(3.6), vpsRate: Value(4), cnssEmployerPensionRate: Value(6.4),
        cnssEmployerFamilyRate: Value(9), cnssEmployerRiskRate: Value(2),
      ));
    }

    test('⚠️⚠️ les lignes et les cartes du mois : l\'exemple du PRD (120 000, 2 absences actives, 1 archivée)', () async {
      await baremeEtTaux();
      final e = await depot.enregistrerEmploye(prenom: 'Koffi', nom: 'ADJOVI', fonction: 'Gardien', embauche: DateTime(2025, 3, 1), salaire: 120000, statut: 'actif');
      await depot.pointer(employeId: e, jour: DateTime(2026, 10, 5), statut: StatutPointage.absent);
      await depot.pointer(employeId: e, jour: DateTime(2026, 10, 6), statut: StatutPointage.absent);
      final archivee = await depot.pointer(employeId: e, jour: DateTime(2026, 10, 7), statut: StatutPointage.absent);
      await depot.archiverPointage(archivee);
      await depot.pointer(employeId: e, jour: DateTime(2026, 9, 7), statut: StatutPointage.absent);

      final p = await depot.paie('2026-10');
      final l = p.lignes.single;

      expect(l.joursAbsence, 2);
      expect(l.retenueAbsence, 9230.77);
      expect(l.retenueCnss, 3987.69);
      expect(l.retenueIts, 4678.15);
      expect(l.net, 102103.39);
      // Somme des quatre parts ARRONDIES (4 430,77 + 7 089,23 + 9 969,23 + 2 215,38), comme le PHP — pas 21,4 % du dû (…,615).
      expect(l.chargesPatronales, 23704.61);
      expect(l.reglee, isFalse);
      expect(p.masseSalariale, 120000);
      expect(p.chargesCnss, 3987.69);
      expect(p.bulletinsEmis, 0);
      expect(p.enAttente, 1);
      expect(p.baremeItsRenseigne, isTrue);
    });

    test('sans barème ni taux reçus : défauts du web, ITS nul et DIT', () async {
      await depot.enregistrerEmploye(prenom: 'Koffi', nom: 'ADJOVI', fonction: 'Gardien', embauche: DateTime(2025, 3, 1), salaire: 100000, statut: 'actif');

      final p = await depot.paie('2026-10');

      expect(p.baremeItsRenseigne, isFalse);
      expect(p.lignes.single.retenueIts, 0);
      expect(p.lignes.single.retenueCnss, 3600);
      expect(p.lignes.single.net, 96400);
    });

    test('⚠️⚠️ « Valider le règlement » = une DEMANDE sans montant, acquittée ; le bulletin reçu l\'emporte ensuite', () async {
      await baremeEtTaux();
      final e = await depot.enregistrerEmploye(prenom: 'Koffi', nom: 'ADJOVI', fonction: 'Gardien', embauche: DateTime(2025, 3, 1), salaire: 100000, statut: 'actif');

      final id = await depot.demanderReglement(employeId: e, periode: '2026-10');
      expect(await depot.demanderReglement(employeId: e, periode: '2026-10'), id, reason: 'jamais doublée');
      expect((await depot.paie('2026-10')).lignes.single.demandeEnCours, isTrue);

      await moteur.synchroniser();
      final envoye = (serveur.envois.single['payslip_requests'] as List).single as Map;
      expect(envoye.keys.toSet(), {'id', 'employee_id', 'period_month', 'requested_at', 'device_id'});
      expect(envoye['period_month'], '2026-10');
      expect(envoye['requested_at'], endsWith('Z'));
      expect((await db.select(db.payslipRequests).get()).single.syncStatus, SyncStatus.synced);

      // Le bulletin redescend (colonnes RH) : la ligne est « Réglé » avec SES montants.
      serveur.refus['employees'] = {e: 'non'};
      serveur.tirage = {
        'server_time': '2026-10-27T13:00:00Z',
        'payslips': [{
          'id': uuid('b1'), 'employee_name': 'ADJOVI Koffi', 'net_salary': 92760, 'created_at': '2026-10-27 12:30:00',
          'employee_id': e, 'period_month': '2026-10-01', 'gross_salary': 100000, 'absence_deduction': 0, 'cnss_deduction': 3600,
          'its_deduction': 3640, 'charges_patronales': 21400,
        }],
      };
      await moteur.synchroniser();
      final l = (await depot.paie('2026-10')).lignes.single;
      expect(l.reglee, isTrue);
      expect(l.net, 92760);
      expect(l.retenueIts, 3640);
      expect(l.joursAbsence, isNull);
      expect((await depot.paie('2026-10')).bulletinsEmis, 1);
    });

    test('une demande refusée (exercice clos) devient conflict avec son motif, et se relance', () async {
      final e = await depot.enregistrerEmploye(prenom: 'Koffi', nom: 'ADJOVI', fonction: 'Gardien', embauche: DateTime(2025, 3, 1), salaire: 100000, statut: 'actif');
      final id = await depot.demanderReglement(employeId: e, periode: '2026-10');
      serveur.refus['payslip_requests'] = {id: 'Règlement refusé : exercice clos.'};

      await moteur.synchroniser();

      expect((await depot.paie('2026-10')).lignes.single.demandeRefusee, isTrue);
      final conflit = (await db.select(db.syncConflicts).get()).firstWhere((c) => c.sourceTable == 'payslip_requests');
      expect(conflit.reason, contains('exercice clos'));
      await depot.demanderReglement(employeId: e, periode: '2026-10');
      expect((await db.select(db.payslipRequests).get()).single.syncStatus, SyncStatus.pending);
    });

    test('un bulletin servi sans colonnes RH (compte rapports) descend toujours : nom, net, instant', () async {
      serveur.tirage = {
        'server_time': '2026-10-27T13:00:00Z',
        'payslips': [{'id': uuid('b1'), 'employee_name': 'ADJOVI Koffi', 'net_salary': 92760, 'created_at': '2026-10-27 12:30:00'}],
      };

      await moteur.synchroniser();

      final b = (await db.select(db.payslips).get()).single;
      expect(b.netSalary, 92760);
      expect(b.employeeId, isNull);
      expect(b.periodMonth, isNull);
    });
  });

  test('la réinitialisation du serveur purge les absences et les demandes ; garde le barème', () async {
    await db.into(db.incomeTaxBrackets).insert(IncomeTaxBracketsCompanion.insert(id: uuid('t1'), fromAmount: 0, toAmount: const Value(null), rate: 0));
    final s = await depot.enregistrerStagiaire(prenom: 'F', nom: 'A', etablissement: 'S', debut: DateTime(2026, 2, 1));
    await depot.noterAbsence(stagiaireId: s, jour: DateTime(2026, 3, 2));
    final e = await depot.enregistrerEmploye(prenom: 'K', nom: 'A', fonction: 'G', embauche: DateTime(2025, 3, 1), statut: 'actif');
    await depot.demanderReglement(employeId: e, periode: '2026-10');

    expect(AppDatabase.tablesDActivite, containsAll(['internship_absences', 'payslip_requests', 'employees', 'internships']));
    expect(AppDatabase.tablesConservees, contains('income_tax_brackets'));
    expect(AppDatabase.tablesEnvoyees, containsAll(['employees', 'internships', 'internship_absences', 'payslip_requests']));
    final perdus = await db.purgerDonneesDActivite();
    expect(perdus, greaterThanOrEqualTo(4));
    expect(await db.select(db.internshipAbsences).get(), isEmpty);
    expect(await db.select(db.payslipRequests).get(), isEmpty);
    expect(await db.select(db.incomeTaxBrackets).get(), hasLength(1));
  });
}
