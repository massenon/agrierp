import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/identifiant_ligne_depense.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'depenses_aide.dart';
import 'php_laravel.dart';

/// Ticket DEP4 (PRD `docs/prd/depenses-multilignes.md`) — UNE DÉPENSE, PLUSIEURS LIGNES au poste : la migration Drift
/// v56 (chaque ancienne dépense devient 1 en-tête + 1 ligne), le contrat de synchronisation (la dépense part AVEC ses
/// lignes ; ses lignes descendent avec elle ; le refus de la pièce se copie sur la dépense) et la parité de l'identifiant
/// de ligne convertie avec le serveur.
///
/// ⚠️ Numéro 56 sur cette branche (53 devis, 54 avoirs, 55 unicité réservés ailleurs) : la fusion renumérotera si un
/// palier manque.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Serveur feint : sert [tirage], répond à l'envoi par [reponse] (tout accepté par défaut) et garde chaque corps.
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-19T12:00:00Z'};
  Map<String, dynamic> Function(Map<String, dynamic> corps)? reponse;

  final List<Object?> demandes = [];
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('push')) {
      final corps = options.data as Map<String, dynamic>;
      envois.add(corps);
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: reponse != null
              ? reponse!(corps)
              : {
                  for (final MapEntry(:key, :value) in corps.entries)
                    if (value is List)
                      key: {
                        'accepted': [
                          for (final e in value)
                            if (e is Map && e['id'] is String) e['id'],
                        ],
                        'rejected': [],
                      },
                },
        ),
      );
      return;
    }
    demandes.add(options.queryParameters['since']);
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

const _caisse = 'cccccccc-0000-4000-8000-000000000531';
const _banque = 'cccccccc-0000-4000-8000-000000000521';
String _uuid(String graine) => graine.padRight(36, '0');

void main() {
  late Directory dossier;

  setUpAll(() {
    // Plusieurs instances successives sur des fichiers distincts : VOULU.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dossier = Directory.systemTemp.createTempSync('agrierp_dep_');
  });
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    try {
      dossier.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ── Migration v56 : 1 en-tête + 1 ligne, rien de perdu, aucune pièce touchée ─────────────────────────────────────

  group('migration Drift v56 — chaque ancienne dépense devient 1 en-tête + 1 ligne', () {
    const colonnes = ['payment_mode', 'cost_center_id', 'supplier_id', 'beneficiary', 'created_by', 'ecriture_refus'];
    var n = 0;

    /// Une base en forme v55 (sans lignes, sans centres de coût, sans les colonnes d'en-tête), garnie par [donnees], puis
    /// ouverte par l'application : la migration 55 → 56 s'exécute au premier accès.
    Future<AppDatabase> baseV55(void Function(dynamic raw) donnees) async {
      final fichier = File('${dossier.path}/v55_${n++}.sqlite');
      final neuve = AppDatabase.forTesting(NativeDatabase(fichier));
      await neuve.customSelect('SELECT 1').get();
      await neuve.close();
      return AppDatabase.forTesting(
        NativeDatabase(
          fichier,
          setup: (raw) {
            raw.execute('DROP TABLE "expense_lines"');
            raw.execute('DROP TABLE "cost_centers"');
            for (final c in colonnes) {
              raw.execute('ALTER TABLE "expenses" DROP COLUMN "$c"');
            }
            raw.execute('PRAGMA user_version = 55');
            donnees(raw);
          },
        ),
      );
    }

    void plan(dynamic raw, {bool avec628 = true, bool avec614 = true, bool avec605 = true}) {
      for (final (id, code, classe) in [
        (compte605, '605', 6),
        (compte614, '614', 6),
        (compte628, '628', 6),
        (compte531, '531', 5),
      ]) {
        if (code == '628' && !avec628) continue;
        if (code == '614' && !avec614) continue;
        if (code == '605' && !avec605) continue;
        raw.execute("INSERT INTO chart_of_accounts (id, code, label, account_class) VALUES ('$id', '$code', 'Compte $code', $classe)");
      }
      raw.execute("INSERT INTO treasury_accounts (id, label, account_code, type, balance) VALUES ('$_caisse', 'Caisse', '531', 'caisse', 0)");
      raw.execute("INSERT INTO treasury_accounts (id, label, account_code, type, balance) VALUES ('$_banque', 'Banque', '521', 'banque', 0)");
    }

    void depense(dynamic raw, String id, String libelle, String? categorie, num montant, {
      String statut = 'synced',
      String? ecriture,
      String compte = _caisse,
      bool actif = true,
    }) {
      raw.execute(
        'INSERT INTO expenses (id, device_id, sync_status, updated_at, expense_date, label, category, amount, '
        'treasury_account_id, is_active, status, accounting_entry_id) VALUES '
        "('$id', 'poste-test', '$statut', 1760000000, 1760000000, '$libelle', ${categorie == null ? "''" : "'$categorie'"}, $montant, "
        "'$compte', ${actif ? 1 : 0}, 'payee', ${ecriture == null ? 'NULL' : "'$ecriture'"})",
      );
    }

    const a = 'aaaaaaaa-0000-4000-8000-000000000001';
    const b = 'aaaaaaaa-0000-4000-8000-000000000002';

    test('⚠️⚠️ aucune dépense perdue : libellé, compte déduit de la catégorie, montant ; pièces et envoi intacts', () async {
      final db = await baseV55((raw) {
        plan(raw);
        depense(raw, a, 'Transport marché', '614 - Transports', 8000, ecriture: 'eeeeeeee-0000-4000-8000-000000000001');
        depense(raw, b, 'Réparation toiture', 'Entretien divers', 12500.5, statut: 'pending', compte: _banque);
        depense(raw, 'aaaaaaaa-0000-4000-8000-000000000003', 'Sans catégorie lisible', null, 3000);
        depense(raw, 'aaaaaaaa-0000-4000-8000-000000000004', 'Ancienne archivée', '605 - Énergie', 4000, actif: false);
      });
      addTearDown(db.close);

      final depenses = {for (final d in await db.select(db.expenses).get()) d.id: d};
      final lignes = {for (final l in await db.select(db.expenseLines).get()) l.expenseId: l};
      expect(depenses, hasLength(4), reason: 'aucune dépense perdue');
      expect(lignes, hasLength(4), reason: '1 en-tête = 1 ligne');

      expect((lignes[a]!.label, lignes[a]!.chargeAccountId, lignes[a]!.amount, lignes[a]!.position), ('Transport marché', compte614, 8000.0, 0));
      expect(lignes[b]!.chargeAccountId, compte628, reason: 'sans correspondance : charges diverses (628)');
      expect(lignes[b]!.amount, 12500.5, reason: 'le total historique reste cohérent, décimal compris');
      expect(lignes['aaaaaaaa-0000-4000-8000-000000000003']!.chargeAccountId, compte628, reason: 'catégorie illisible : 628');
      expect(lignes['aaaaaaaa-0000-4000-8000-000000000004']!.chargeAccountId, compte605);
      expect(depenses['aaaaaaaa-0000-4000-8000-000000000004']!.isActive, isFalse);

      // L'identifiant de la ligne est celui du serveur (UUID v5 de la dépense) : la même ligne des deux côtés.
      expect(lignes[a]!.id, '442b7a74-2649-52a8-b222-4c0b3948429d');
      expect(lignes[b]!.id, '5235b1b5-cfe4-58ae-940a-3412d17f572f');

      // En-tête : montant, pièce, état d'envoi et instant de saisie INTACTS ; le mode vient du type du compte payeur.
      expect((depenses[a]!.amount, depenses[a]!.accountingEntryId, depenses[a]!.syncStatus), (8000.0, 'eeeeeeee-0000-4000-8000-000000000001', SyncStatus.synced));
      expect(depenses[b]!.syncStatus, SyncStatus.pending, reason: 'une saisie en attente le reste');
      expect(depenses[b]!.accountingEntryId, isNull);
      expect(depenses[a]!.updatedAt, depenses[b]!.updatedAt, reason: '`updated_at` ne bouge pas');
      expect(depenses[a]!.paymentMode, 'caisse');
      expect(depenses[b]!.paymentMode, 'banque');
      expect(await db.pendingCount(), 1);
    });

    test('un poste sans plan comptable local : aucune dépense perdue, aucune ligne inventée (elle redescendra du serveur)', () async {
      final db = await baseV55((raw) {
        raw.execute("INSERT INTO treasury_accounts (id, label, account_code, type, balance) VALUES ('$_caisse', 'Caisse', '531', 'caisse', 0)");
        depense(raw, a, 'Gasoil', '605 - Énergie', 5000);
      });
      addTearDown(db.close);

      expect(await db.select(db.expenses).get(), hasLength(1));
      expect(await db.select(db.expenseLines).get(), isEmpty);
      // La dépense reste lisible : l'écran fabrique une ligne de repli, et une saisie en attente partirait à plat.
      final liste = await DepensesRepository(database: db, deviceId: 'poste-test').depenses();
      expect([for (final d in liste.single.lignes) (d.libelle, d.montant)], [('Gasoil', 5000.0)]);
    });

    test('une dépense déjà dotée de sa ligne n est pas reconvertie ; la base migrée a toutes les tables et colonnes', () async {
      final db = await baseV55((raw) {
        plan(raw);
        depense(raw, a, 'Gasoil', '605 - Énergie', 5000);
      });
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      expect(await db.select(db.expenseLines).get(), hasLength(1));
      expect(await db.select(db.costCenters).get(), isEmpty);
      final d = (await db.select(db.expenses).get()).single;
      expect((d.paymentMode, d.costCenterId, d.supplierId, d.beneficiary, d.createdBy, d.ecritureRefus), ('caisse', null, null, null, null, null));
      expect(db.schemaVersion, greaterThanOrEqualTo(56), reason: 'palier DEP4 (56) au moins ; les paliers suivants l\'enjambent');
    });
  });

  // ── L'identifiant de la ligne convertie est celui du serveur ──────────────────────────────────────────────────────

  group('parité exécutée avec le serveur', () {
    final saut = sautSansPhp();

    test('⚠️ `idLigneConvertie` = `ExpenseLine::idDeConversion` (UUID v5)', () {
      const ids = [
        'aaaaaaaa-0000-4000-8000-000000000001',
        'aaaaaaaa-0000-4000-8000-000000000002',
        '99999999-9999-4999-8999-999999999999',
        '00000000-0000-4000-8000-000000000000',
        'ffffffff-ffff-4fff-8fff-ffffffffffff',
      ];
      final sortie = executerPhp(
        '<?php\n$amorceApplication\nforeach (json_decode(file_get_contents(\$argv[1]), true) as \$i) { \$o[\$i] = App\\Models\\ExpenseLine::idDeConversion(\$i); } echo json_encode(\$o);',
        ids,
        application: true,
      ) as Map<String, dynamic>;

      for (final id in ids) {
        expect(idLigneConvertie(id), sortie[id], reason: id);
      }
      expect(espaceConversionLigneDepense, 'c5a0e7a2-6f55-4a52-9e0e-3f1f2f6d0a11');
    }, skip: saut);
  });

  // ── Synchronisation ───────────────────────────────────────────────────────────────────────────────────────────────

  group('synchronisation', () {
    late AppDatabase db;
    late _Serveur serveur;
    late SyncEngine moteur;
    late DepensesRepository depot;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      serveur = _Serveur();
      moteur = SyncEngine(
        database: db,
        client: Dio()..interceptors.add(serveur),
        deviceId: 'poste-test',
        connectivity: _Connectivite(),
        maintenant: () => DateTime(2026, 10, 19, 14),
      );
      depot = DepensesRepository(database: db, deviceId: 'poste-test', auteurId: () => 'uuuuuuuu-0000-4000-8000-000000000001');
      await semerPlanDeCharge(db);
      await db.into(db.treasuryAccounts).insert(TreasuryAccountsCompanion.insert(id: _caisse, label: 'Caisse', type: const Value('caisse')));
    });

    tearDown(() async => db.close());

    Future<Expense> trois() => depot.enregistrer(
      date: DateTime(2026, 10, 12),
      modePaiement: 'caisse',
      compteTresorerieId: _caisse,
      lignes: const [
        LigneSaisie(libelle: 'Provende ponte', compteChargeId: compte601, montant: '45000'),
        LigneSaisie(libelle: 'Vermifuge', compteChargeId: compte602, montant: '10000'),
        LigneSaisie(libelle: "Sac d'aliment bis", compteChargeId: compte601, montant: '5000'),
      ],
    );

    Future<Expense> lire(String id) => (db.select(db.expenses)..where((t) => t.id.equals(id))).getSingle();

    Map<String, dynamic> enteteJson(String id, {String libelle = 'Provende ponte (+1 autre)', Object? ecriture, num montant = 60000}) => {
      'id': id,
      'expense_date': '2026-10-12',
      'label': libelle,
      'category': '601 - Aliments',
      'amount': montant,
      'treasury_account_id': _caisse,
      'is_active': true,
      'status': 'payee',
      'accounting_entry_id': ecriture,
      'payment_mode': 'caisse',
      'cost_center_id': null,
      'supplier_id': null,
      'beneficiary': 'M. Dossou',
      'created_by': 'uuuuuuuu-0000-4000-8000-0000000000aa',
      'updated_at': '2026-10-12T10:00:00+01:00',
    };

    Map<String, dynamic> ligneJson(String id, String depense, int rang, String libelle, Object montant, {String compte = compte601}) => {
      'id': id,
      'expense_id': depense,
      'position': rang,
      'label': libelle,
      'charge_account_id': compte,
      'amount': montant,
    };

    test('⚠️⚠️ la dépense part AVEC ses lignes dans le même document, total compris ; le serveur l acquitte', () async {
      final d = await trois();

      await moteur.synchroniser();

      final envoyee = (serveur.envois.single['expenses'] as List).single as Map<String, dynamic>;
      expect(envoyee['id'], d.id);
      expect(envoyee['amount'], 60000.0, reason: 'le total, que le serveur contrôle contre la somme des lignes');
      expect(envoyee['payment_mode'], 'caisse');
      expect(envoyee['treasury_account_id'], _caisse);
      expect(envoyee.containsKey('label'), isFalse, reason: 'plus de document plat');
      expect(envoyee.containsKey('category'), isFalse);
      final lignes = (envoyee['lines'] as List).cast<Map<String, dynamic>>();
      expect([for (final l in lignes) (l['label'], l['charge_account_id'], l['amount'])], [
        ('Provende ponte', compte601, 45000),
        ('Vermifuge', compte602, 10000),
        ("Sac d'aliment bis", compte601, 5000),
      ]);
      expect(lignes.every((l) => (l['id'] as String).length == 36), isTrue, reason: 'UUID créés sur le poste');
      expect((await lire(d.id)).syncStatus, SyncStatus.synced);
    });

    test('une dépense SANS ligne (conversion locale impossible) part à plat : le serveur la convertit', () async {
      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: _uuid('p1'),
          deviceId: 'poste-test',
          updatedAt: DateTime(2026, 10, 12),
          expenseDate: DateTime(2026, 10, 12),
          label: 'Gasoil',
          category: '605 - Énergie',
          amount: 5000,
          treasuryAccountId: _caisse,
        ),
      );

      await moteur.synchroniser();

      final envoyee = (serveur.envois.single['expenses'] as List).single as Map<String, dynamic>;
      expect((envoyee['label'], envoyee['category'], envoyee['amount']), ('Gasoil', '605 - Énergie', 5000.0));
      expect(envoyee.containsKey('lines'), isFalse);
    });

    test('⚠️⚠️ le REFUS DE LA PIÈCE du serveur est copié sur la dépense (mot pour mot), puis effacé à l acquittement', () async {
      const motif = "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 12/10/2026.";
      final d = await trois();
      serveur.reponse = (corps) => {
        'expenses': {'accepted': [], 'rejected': [{'id': d.id, 'reason': motif}]},
      };

      await moteur.synchroniser();

      final refusee = await lire(d.id);
      expect((refusee.syncStatus, refusee.ecritureRefus), (SyncStatus.conflict, motif));
      final liste = (await depot.depenses()).single;
      expect(liste.motifRefus, motif, reason: 'affiché sous la dépense');
      expect(await db.select(db.expenseLines).get(), hasLength(3), reason: 'les lignes restent, la saisie est corrigeable');

      // Corrigée (sans pièce : elle se modifie) : l'ancien refus disparaît, la saisie repart.
      await depot.enregistrer(
        date: DateTime(2026, 10, 13),
        modePaiement: 'caisse',
        compteTresorerieId: _caisse,
        idEnModification: d.id,
        lignes: const [LigneSaisie(libelle: 'Provende ponte', compteChargeId: compte601, montant: '45000')],
      );
      expect((await lire(d.id)).ecritureRefus, isNull);
      expect((await lire(d.id)).syncStatus, SyncStatus.pending);
      serveur.reponse = null;
      await moteur.synchroniser();
      expect((await lire(d.id)).syncStatus, SyncStatus.synced);
      expect((await lire(d.id)).ecritureRefus, isNull);
    });

    test('⚠️ une dépense du serveur descend AVEC ses lignes et son en-tête ; les lignes servies REMPLACENT celles du poste', () async {
      // Le poste connaît déjà la dépense, avec une ancienne ligne.
      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: _uuid('w1'),
          deviceId: 'serveur',
          syncStatus: const Value(SyncStatus.synced),
          updatedAt: DateTime(2026, 10, 1),
          expenseDate: DateTime(2026, 10, 12),
          label: 'Ancienne',
          category: '601 - Aliments',
          amount: 100,
          treasuryAccountId: _caisse,
        ),
      );
      await db.into(db.expenseLines).insert(
        ExpenseLinesCompanion.insert(id: _uuid('ancienne'), expenseId: _uuid('w1'), label: 'Ancienne', chargeAccountId: compte601, amount: 100),
      );
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'expenses': [enteteJson(_uuid('w1'), ecriture: _uuid('e1'))],
        'expense_lines': [
          ligneJson(_uuid('l2'), _uuid('w1'), 1, 'Vermifuge', 15000, compte: compte602),
          ligneJson(_uuid('l1'), _uuid('w1'), 0, 'Provende ponte', 45000),
        ],
      };

      await moteur.synchroniser();

      final d = await lire(_uuid('w1'));
      expect((d.amount, d.label, d.paymentMode, d.beneficiary, d.createdBy, d.accountingEntryId),
          (60000.0, 'Provende ponte (+1 autre)', 'caisse', 'M. Dossou', 'uuuuuuuu-0000-4000-8000-0000000000aa', _uuid('e1')));
      final lignes = await (db.select(db.expenseLines)..orderBy([(l) => OrderingTerm(expression: l.position)])).get();
      expect([for (final l in lignes) (l.id, l.label, l.amount, l.position)], [
        (_uuid('l1'), 'Provende ponte', 45000.0, 0),
        (_uuid('l2'), 'Vermifuge', 15000.0, 1),
      ], reason: 'l ancienne ligne a disparu, l ordre est celui du rang');
    });

    test('⚠️⚠️ une dépense locale `pending` ou `conflict` n est JAMAIS écrasée, lignes comprises', () async {
      final d = await trois();
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'expenses': [enteteJson(d.id, libelle: 'Version du serveur', montant: 1)],
        'expense_lines': [ligneJson(_uuid('l9'), d.id, 0, 'Ligne du serveur', 1)],
      };
      serveur.reponse = (_) => {'expenses': {'accepted': [], 'rejected': [{'id': d.id, 'reason': 'Refus'}]}};

      await moteur.synchroniser();

      expect((await lire(d.id)).label, 'Provende ponte (+2 autres)');
      expect(await db.select(db.expenseLines).get(), hasLength(3));
      expect([for (final l in await db.select(db.expenseLines).get()) l.label], isNot(contains('Ligne du serveur')));
    });

    test('⚠️ clé `expense_lines` absente (serveur antérieur à DEP3) : les lignes du poste ne sont pas touchées ; tirage complet maintenu', () async {
      final d = await trois();
      await (db.update(db.expenses)..where((t) => t.id.equals(d.id))).write(const ExpensesCompanion(syncStatus: Value(SyncStatus.synced)));
      await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'expenses': [enteteJson(d.id, ecriture: _uuid('e1'))],
      };

      await moteur.synchroniser();
      await moteur.synchroniser();

      expect(await db.select(db.expenseLines).get(), hasLength(3), reason: 'rien n est touché');
      expect(serveur.demandes, [null, null], reason: 'tant que le serveur ne sert pas les lignes, le tirage reste complet');
      expect(await (db.select(db.appSettings)..where((t) => t.key.equals(SyncEngine.cleDepensesResyncDep1))).get(), isEmpty,
          reason: 'resynchronisation unique pas encore faite : le tirage reste complet tant que le serveur ne sert pas les lignes');
    });

    test('un serveur qui sert `expense_lines` note la resynchronisation unique : le tirage devient incrémental', () async {
      await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
      for (final cle in [
        SyncEngine.cleJournalResync,
        SyncEngine.cleJournalResyncCreation,
        SyncEngine.cleFichesResync,
        SyncEngine.cleFichesResyncCategories,
        SyncEngine.cleFichesResyncU10,
        SyncEngine.cleLignesResync,
        SyncEngine.cleRetoursResync,
        SyncEngine.cleMouvementsResync,
        SyncEngine.cleDepensesResync,
        SyncEngine.cleDepensesResyncU14,
      ]) {
        await db.into(db.appSettings).insert(AppSettingsCompanion.insert(key: cle, value: '1'));
      }
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'expenses': [enteteJson(_uuid('w1'))],
        'expense_lines': [ligneJson(_uuid('l1'), _uuid('w1'), 0, 'Provende ponte', 60000)],
      };

      await moteur.synchroniser();
      await moteur.synchroniser();

      expect(serveur.demandes.first, isNull, reason: 'sans since, une fois');
      expect(serveur.demandes.last, isNotNull, reason: 'puis incrémental');
    });

    for (final (cas, tirage) in <(String, Map<String, dynamic> Function())>[
      ('ligne d une dépense non servie', () => {'expense_lines': [ligneJson(_uuid('l1'), _uuid('inconnue'), 0, 'X', 1)]}),
      ('ligne servie deux fois', () => {'expense_lines': [ligneJson(_uuid('l1'), _uuid('w1'), 0, 'X', 1), ligneJson(_uuid('l1'), _uuid('w1'), 1, 'Y', 1)]}),
      ('identifiant de ligne invalide', () => {'expense_lines': [ligneJson('court', _uuid('w1'), 0, 'X', 1)]}),
      ('libellé de ligne absent', () => {'expense_lines': [ligneJson(_uuid('l1'), _uuid('w1'), 0, 'X', 1)..['label'] = null]}),
      ('compte de charge de ligne vide', () => {'expense_lines': [ligneJson(_uuid('l1'), _uuid('w1'), 0, 'X', 1, compte: '')]}),
      ('montant de ligne illisible', () => {'expense_lines': [ligneJson(_uuid('l1'), _uuid('w1'), 0, 'X', 'cent')]}),
      ('montant de ligne négatif', () => {'expense_lines': [ligneJson(_uuid('l1'), _uuid('w1'), 0, 'X', -5)]}),
      ('élément qui n est pas une ligne', () => {'expense_lines': ['n importe quoi']}),
      ('clé qui n est pas une liste', () => {'expense_lines': 'oups'}),
    ]) {
      test('⚠️⚠️ STRICT — $cas : toute la page est refusée, rien n est écrit, le curseur ne bouge pas', () async {
        await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
        final curseur = (await db.etatDeSynchronisation())?.lastPulledAt;
        serveur.tirage = {'server_time': '2026-10-19T12:00:00Z', 'expenses': [enteteJson(_uuid('w1'))], ...tirage()};

        await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));

        expect(await db.select(db.expenses).get(), isEmpty);
        expect(await db.select(db.expenseLines).get(), isEmpty);
        expect((await db.etatDeSynchronisation())?.lastPulledAt, curseur);
      });
    }

    test('les centres de coût descendent (référentiel : le serveur gagne), strictement', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'cost_centers': [
          {'id': _uuid('c1'), 'label': 'Cuniculture', 'type': 'filiere', 'parent_species_id': null, 'is_active': true},
          {'id': _uuid('c2'), 'label': 'Aviculture', 'type': 'filiere', 'parent_species_id': null, 'is_active': false},
        ],
      };
      await moteur.synchroniser();
      expect([for (final c in await db.select(db.costCenters).get()) (c.label, c.isActive)], [('Cuniculture', true), ('Aviculture', false)]);
      expect([for (final c in await depot.centresDeCout()) c.label], ['Cuniculture'], reason: 'les actifs seulement, comme le web');

      serveur.tirage = {
        'server_time': '2026-10-19T12:05:00Z',
        'cost_centers': [{'id': _uuid('c1'), 'label': 'Cuniculture', 'type': 'filiere', 'parent_species_id': null, 'is_active': true}],
      };
      await moteur.synchroniser();
      expect(await db.select(db.costCenters).get(), hasLength(1), reason: 'le serveur gagne : un centre retiré disparaît');

      serveur.tirage = {'server_time': '2026-10-19T12:10:00Z', 'cost_centers': [{'id': _uuid('c3'), 'type': 'filiere'}]};
      await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));
      expect(await db.select(db.costCenters).get(), hasLength(1));
    });
  });
}
