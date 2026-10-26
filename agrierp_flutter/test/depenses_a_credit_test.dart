import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/achats/depenses_repository.dart';
import 'package:agrierp/features/achats/saisie_depenses_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'depenses_aide.dart';

/// Tickets DEP6 et DEP7 (PRD `docs/prd/depenses-multilignes.md`, § 11 — décisions du client du 21/10/2026) au POSTE :
///
///  * DEP6 — le centre de coût est OBLIGATOIRE à la saisie (message sous le champ) ;
///  * DEP7 — dès qu'un fournisseur est choisi, « Règlement * » : « Payée comptant » ou « À crédit (dette fournisseur) ». À
///    crédit : ni mode ni compte de trésorerie, la dépense naît `en_attente` et part avec `on_credit` ; la pièce (D charges /
///    C 401) et la dette sont passées PAR LE SERVEUR ; la dette redescend avec `payables` (écran « Dettes Fournisseurs »,
///    inchangé) et son règlement fait passer la dépense à `payee` ;
///  * le palier Drift v59 : `on_credit` et trésorerie NULLABLE (table reconstruite sans perdre une ligne), centre « Général »
///    posé aux dépenses locales qui n'en avaient pas.
class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-19T12:00:00Z'};
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
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [for (final e in value) if (e is Map && e['id'] is String) e['id']],
                  'rejected': [],
                },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

const _caisse = 'cccccccc-0000-4000-8000-000000000531';
const _agriBenin = 'ffffffff-0000-4000-8000-0000000000a1';
String _uuid(String graine) => graine.padRight(36, '0');

void main() {
  late AppDatabase db;
  late DepensesRepository depot;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = DepensesRepository(database: db, deviceId: 'poste-test', auteurId: () => 'uuuuuuuu-0000-4000-8000-000000000001');
    await semerPlanDeCharge(db);
    await db.into(db.treasuryAccounts).insert(
      TreasuryAccountsCompanion.insert(id: _caisse, label: 'Caisse Physique', accountCode: const Value('531'), type: const Value('caisse'), balance: const Value(500000)),
    );
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(id: _agriBenin, name: 'Agri-Bénin'));
  });

  tearDown(() async => db.close());

  const ligne = LigneSaisie(libelle: 'Provende ponte', compteChargeId: compte601, montant: '45000');

  Future<Expense> aCredit({String? centre = centreGeneral}) => depot.enregistrer(
    date: DateTime(2026, 6, 15),
    modePaiement: null,
    compteTresorerieId: null,
    centreCoutId: centre,
    fournisseurId: _agriBenin,
    aCredit: true,
    lignes: const [ligne, LigneSaisie(libelle: 'Vermifuge', compteChargeId: compte602, montant: '15000')],
  );

  // ── Le dépôt ────────────────────────────────────────────────────────────────────────────────────────────────────

  group('dépôt', () {
    test('⚠️⚠️ DEP7 — à crédit : `on_credit`, `en_attente`, AUCUNE trésorerie ni mode ; le solde du poste ne bouge pas', () async {
      final d = await aCredit();

      expect(d.onCredit, isTrue);
      expect(d.status, 'en_attente', reason: 'jusqu\'au règlement de la dette');
      expect(d.treasuryAccountId, isNull);
      expect(d.paymentMode, isNull);
      expect(d.supplierId, _agriBenin);
      expect(d.costCenterId, centreGeneral);
      expect(d.amount, 60000);
      expect(d.syncStatus, SyncStatus.pending);
      expect(d.accountingEntryId, isNull, reason: 'la pièce (D charges / C 401) est passée par le serveur');
      final compte = await (db.select(db.treasuryAccounts)..where((t) => t.id.equals(_caisse))).getSingle();
      expect(compte.balance, 500000);
    });

    test('payée comptant chez un fournisseur : comme avant (trésorerie, `payee`, pas de crédit) ; sans fournisseur, jamais de crédit', () async {
      final comptant = await depot.enregistrer(
        date: DateTime(2026, 6, 15),
        modePaiement: 'caisse',
        compteTresorerieId: _caisse,
        centreCoutId: centreGeneral,
        fournisseurId: _agriBenin,
        lignes: const [ligne],
      );
      expect((comptant.onCredit, comptant.status, comptant.treasuryAccountId, comptant.paymentMode), (false, 'payee', _caisse, 'caisse'));

      // « À crédit » sans fournisseur : refus (la modale réinitialise le choix quand le fournisseur est retiré).
      try {
        await depot.enregistrer(
          date: DateTime(2026, 6, 15),
          modePaiement: null,
          compteTresorerieId: null,
          centreCoutId: centreGeneral,
          aCredit: true,
          lignes: const [ligne],
        );
        fail('refus attendu');
      } on DepenseRefusee catch (e) {
        expect(e.erreurs, {'fournisseur': DepensesRepository.messageCreditSansFournisseur});
      }
    });

    test('⚠️ DEP6 — sans centre de coût : refus sous le champ, rien n\'est écrit', () async {
      try {
        await aCredit(centre: null);
        fail('refus attendu');
      } on DepenseRefusee catch (e) {
        expect(e.erreurs, {'centre': DepensesRepository.messageCentreObligatoire});
      }
      expect(await db.select(db.expenses).get(), isEmpty);
      expect(await db.select(db.expenseLines).get(), isEmpty);
    });

    test('une reprise de l\'ancien (sans pièce) ne passe pas à crédit : ni pièce rétroactive ni dette', () async {
      final d = await depot.enregistrer(
        date: DateTime(2026, 6, 15),
        modePaiement: 'caisse',
        compteTresorerieId: _caisse,
        centreCoutId: centreGeneral,
        lignes: const [ligne],
      );

      try {
        await depot.enregistrer(
          date: DateTime(2026, 6, 15),
          modePaiement: null,
          compteTresorerieId: null,
          centreCoutId: centreGeneral,
          fournisseurId: _agriBenin,
          aCredit: true,
          idEnModification: d.id,
          lignes: const [ligne],
        );
        fail('refus attendu');
      } on DepenseRefusee catch (e) {
        expect(e.erreurs, {'formulaire': DepensesRepository.messageCreditSansPiece});
      }
      expect((await (db.select(db.expenses)..where((t) => t.id.equals(d.id))).getSingle()).onCredit, isFalse);
    });

    test('le règlement du détail déplié et le toast d\'archivage sont ceux du web', () {
      expect(DepensesRepository.libelleReglement(aCredit: false, statut: 'payee'), 'Payée comptant');
      expect(DepensesRepository.libelleReglement(aCredit: true, statut: 'en_attente'), 'À crédit — en attente');
      expect(DepensesRepository.libelleReglement(aCredit: true, statut: 'payee'), 'À crédit — réglée');
      expect(DepensesRepository.reglements, {'comptant': 'Payée comptant', 'credit': 'À crédit (dette fournisseur)'});
    });
  });

  // ── La synchronisation ──────────────────────────────────────────────────────────────────────────────────────────

  group('synchronisation', () {
    late _Serveur serveur;
    late SyncEngine moteur;

    setUp(() {
      serveur = _Serveur();
      moteur = SyncEngine(
        database: db,
        client: Dio()..interceptors.add(serveur),
        deviceId: 'poste-test',
        connectivity: _Connectivite(),
        maintenant: () => DateTime(2026, 10, 19, 14),
      );
    });

    Map<String, dynamic> credit(String id, {Object? onCredit = true, Object? tresorerie, String statut = 'en_attente'}) => {
      'id': id,
      'expense_date': '2026-06-15',
      'label': 'Provende ponte (+1 autre)',
      'category': '601 - Aliments',
      'amount': 60000,
      'treasury_account_id': tresorerie,
      'is_active': true,
      'status': statut,
      'accounting_entry_id': _uuid('e1'),
      'payment_mode': null,
      'cost_center_id': centreGeneral,
      'supplier_id': _agriBenin,
      'beneficiary': null,
      'created_by': null,
      'on_credit': onCredit,
      'updated_at': '2026-06-15T10:00:00+01:00',
    };

    test('⚠️⚠️ DEP7 — la dépense à crédit part avec `on_credit`, sans trésorerie ; la comptant porte `on_credit: false` et son compte', () async {
      final d = await aCredit();
      await depot.enregistrer(
        date: DateTime(2026, 6, 16),
        modePaiement: 'caisse',
        compteTresorerieId: _caisse,
        centreCoutId: centreGeneral,
        lignes: const [ligne],
      );

      await moteur.synchroniser();

      final envoyees = (serveur.envois.single['expenses'] as List).cast<Map<String, dynamic>>();
      final credit = envoyees.firstWhere((e) => e['id'] == d.id);
      expect(credit['on_credit'], isTrue);
      expect(credit['treasury_account_id'], isNull, reason: 'aucune trésorerie : le serveur crédite le 401 et ouvre la dette');
      expect(credit['supplier_id'], _agriBenin);
      expect(credit['cost_center_id'], centreGeneral);
      expect(credit['amount'], 60000.0);
      final comptant = envoyees.firstWhere((e) => e['id'] != d.id);
      expect(comptant['on_credit'], isFalse, reason: 'la clé dit au serveur que ce poste connaît le centre obligatoire');
      expect(comptant['treasury_account_id'], _caisse);
      expect(comptant['cost_center_id'], centreGeneral);
    });

    test('⚠️ une dépense à crédit ne part JAMAIS avec une trésorerie, même si la ligne locale en porte une', () async {
      final d = await aCredit();
      await (db.update(db.expenses)..where((t) => t.id.equals(d.id))).write(const ExpensesCompanion(treasuryAccountId: Value(_caisse)));

      await moteur.synchroniser();

      final envoyee = (serveur.envois.single['expenses'] as List).single as Map<String, dynamic>;
      expect(envoyee['treasury_account_id'], isNull);
    });

    test('⚠️ une dépense SANS ligne part à plat, sans `on_credit` : le serveur la prend pour celle d\'un poste ancien (centre « Général »)', () async {
      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: _uuid('p1'), deviceId: 'poste-test', updatedAt: DateTime(2026, 6, 12), expenseDate: DateTime(2026, 6, 12),
          label: 'Gasoil', category: '605 - Énergie', amount: 5000, treasuryAccountId: const Value(_caisse),
        ),
      );

      await moteur.synchroniser();

      final envoyee = (serveur.envois.single['expenses'] as List).single as Map<String, dynamic>;
      expect(envoyee.containsKey('on_credit'), isFalse);
      expect(envoyee.containsKey('cost_center_id'), isFalse);
    });

    test('⚠️⚠️ le tirage dépose la dépense à crédit sans trésorerie ; la dette soldée la passe à `payee` (le tirage suivant)', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'expenses': [credit(_uuid('c1'))],
        'expense_lines': [
          {'id': _uuid('l1'), 'expense_id': _uuid('c1'), 'position': 0, 'label': 'Provende ponte', 'charge_account_id': compte601, 'amount': 45000},
          {'id': _uuid('l2'), 'expense_id': _uuid('c1'), 'position': 1, 'label': 'Vermifuge', 'charge_account_id': compte602, 'amount': 15000},
        ],
      };
      await moteur.synchroniser();

      var d = (await db.select(db.expenses).get()).single;
      expect((d.onCredit, d.status, d.treasuryAccountId, d.supplierId, d.syncStatus), (true, 'en_attente', null, _agriBenin, SyncStatus.synced));
      final liste = (await depot.depenses()).single;
      expect(liste.fournisseur, 'Agri-Bénin');
      expect(liste.tresorerie, isNull);

      // La dette a été réglée (au web ou à un autre poste) : le serveur sert la dépense `payee`.
      serveur.tirage = {
        'server_time': '2026-10-20T12:00:00Z',
        'expenses': [credit(_uuid('c1'), statut: 'payee')],
        'expense_lines': [
          {'id': _uuid('l1'), 'expense_id': _uuid('c1'), 'position': 0, 'label': 'Provende ponte', 'charge_account_id': compte601, 'amount': 45000},
          {'id': _uuid('l2'), 'expense_id': _uuid('c1'), 'position': 1, 'label': 'Vermifuge', 'charge_account_id': compte602, 'amount': 15000},
        ],
      };
      await moteur.synchroniser();
      d = (await db.select(db.expenses).get()).single;
      expect((d.onCredit, d.status), (true, 'payee'));
    });

    test('⚠️ absorbeur strict : `on_credit` illisible refuse la page entière ; une dépense COMPTANT sans trésorerie reste refusée', () async {
      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'expenses': [credit(_uuid('c1'), onCredit: 'oui')],
      };
      await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));
      expect(await db.select(db.expenses).get(), isEmpty, reason: 'rien n\'est écrit');

      serveur.tirage = {
        'server_time': '2026-10-19T12:00:00Z',
        'expenses': [credit(_uuid('c2'), onCredit: false, tresorerie: null, statut: 'payee')],
      };
      await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));
      expect(await db.select(db.expenses).get(), isEmpty, reason: 'payée comptant : la trésorerie est obligatoire');
    });
  });

  // ── Le palier Drift v59 ─────────────────────────────────────────────────────────────────────────────────────────

  group('migration Drift v59', () {
    late Directory dossier;
    var n = 0;

    setUpAll(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      dossier = Directory.systemTemp.createTempSync('agrierp_dep59_');
    });
    tearDownAll(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      try {
        dossier.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// Une base en forme v58 : `expenses` SANS `on_credit` et à trésorerie OBLIGATOIRE (« NOT NULL »), garnie par [donnees].
    Future<AppDatabase> baseV58(void Function(dynamic raw) donnees) async {
      final fichier = File('${dossier.path}/v58_${n++}.sqlite');
      final neuve = AppDatabase.forTesting(NativeDatabase(fichier));
      await neuve.customSelect('SELECT 1').get();
      await neuve.close();
      return AppDatabase.forTesting(
        NativeDatabase(
          fichier,
          setup: (raw) {
            final ddl = raw.select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'expenses'").first['sql'] as String;
            var ancien = ddl.replaceAll(RegExp(r'"on_credit" INTEGER[^,]*CHECK \("on_credit" IN \(0, 1\)\),\s*'), '');
            ancien = ancien.replaceFirstMapped(RegExp(r'("?treasury_account_id"?\s+TEXT)\s+NULL'), (m) => '${m[1]} NOT NULL');
            if (!ancien.contains('NOT NULL') || ancien.contains('on_credit')) {
              throw StateError('DDL de v58 mal reconstruite : $ancien');
            }
            raw.execute('DROP TABLE "expenses"');
            raw.execute(ancien);
            raw.execute('PRAGMA user_version = 58');
            donnees(raw);
          },
        ),
      );
    }

    void depense(dynamic raw, String id, {String? centre, String statut = 'synced', String? ecriture}) {
      raw.execute(
        'INSERT INTO expenses (id, device_id, sync_status, updated_at, expense_date, label, category, amount, '
        'treasury_account_id, is_active, status, accounting_entry_id, cost_center_id) VALUES '
        "('$id', 'poste-test', '$statut', 1760000000, 1760000000, 'Dépense $id', '601 - Aliments', 8000, "
        "'$_caisse', 1, 'payee', ${ecriture == null ? 'NULL' : "'$ecriture'"}, ${centre == null ? 'NULL' : "'$centre'"})",
      );
    }

    const a = 'aaaaaaaa-0000-4000-8000-0000000000a1';
    const b = 'aaaaaaaa-0000-4000-8000-0000000000a2';
    const c = 'aaaaaaaa-0000-4000-8000-0000000000a3';
    const autreCentre = 'ce000000-0000-4000-8000-000000000009';

    test('⚠️⚠️ la table est RECONSTRUITE (trésorerie nullable, `on_credit` faux) sans perdre une ligne ni toucher envoi, pièce, instant', () async {
      final base = await baseV58((raw) {
        depense(raw, a, ecriture: 'eeeeeeee-0000-4000-8000-0000000000a1');
        depense(raw, b, statut: 'pending');
        depense(raw, c, statut: 'conflict');
      });
      addTearDown(base.close);

      final lignes = {for (final d in await base.select(base.expenses).get()) d.id: d};
      expect(lignes, hasLength(3), reason: 'aucune dépense perdue');
      expect([for (final d in lignes.values) d.onCredit], [false, false, false], reason: 'toute dépense existante est payée comptant');
      expect((lignes[a]!.syncStatus, lignes[a]!.accountingEntryId), (SyncStatus.synced, 'eeeeeeee-0000-4000-8000-0000000000a1'));
      expect(lignes[b]!.syncStatus, SyncStatus.pending, reason: 'une saisie en attente le reste');
      expect(lignes[c]!.syncStatus, SyncStatus.conflict);
      expect(lignes[a]!.updatedAt, lignes[b]!.updatedAt, reason: '`updated_at` ne bouge pas');
      expect(lignes[a]!.treasuryAccountId, _caisse);
      expect(base.schemaVersion, 59);

      final tresorerie = (await base.customSelect('PRAGMA table_info("expenses")').get())
          .firstWhere((l) => l.read<String>('name') == 'treasury_account_id');
      expect(tresorerie.read<int>('notnull'), 0, reason: 'une dépense à crédit n\'a aucune trésorerie');
      // Et elle s'écrit sans trésorerie.
      await base.into(base.expenses).insert(
        ExpensesCompanion.insert(
          id: _uuid('nouveau'), deviceId: 'poste-test', updatedAt: DateTime(2026, 10, 20), expenseDate: DateTime(2026, 10, 20),
          label: 'À crédit', category: '', amount: 1, onCredit: const Value(true),
        ),
      );
      expect((await base.select(base.expenses).get()), hasLength(4));
    });

    test('⚠️ DEP6 — une dépense locale sans centre reçoit « Général » SI ce poste le connaît ; celles qui ont un centre le gardent', () async {
      final base = await baseV58((raw) {
        raw.execute("INSERT INTO cost_centers (id, label, type, is_active) VALUES ('$centreGeneral', 'Général', 'filiere', 1)");
        raw.execute("INSERT INTO cost_centers (id, label, type, is_active) VALUES ('$autreCentre', 'Cuniculture', 'filiere', 1)");
        depense(raw, a);
        depense(raw, b, centre: autreCentre);
      });
      addTearDown(base.close);

      final lignes = {for (final d in await base.select(base.expenses).get()) d.id: d};
      expect(lignes[a]!.costCenterId, centreGeneral);
      expect(lignes[b]!.costCenterId, autreCentre, reason: 'un centre choisi n\'est jamais remplacé');
      expect(lignes[a]!.syncStatus, SyncStatus.synced, reason: 'ni l\'envoi ni l\'instant ne bougent');
    });

    test('sans « Général » connu au poste : aucun centre inventé (le serveur l\'affecte à l\'envoi, DEP6)', () async {
      final base = await baseV58((raw) => depense(raw, a));
      addTearDown(base.close);

      expect((await base.select(base.expenses).get()).single.costCenterId, isNull);
    });
  });

  // ── L'écran ─────────────────────────────────────────────────────────────────────────────────────────────────────

  group('écran', () {
    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: SaisieDepensesScreen(depot: depot)));
      await tester.pumpAndSettle();
    }

    Future<void> choisir(WidgetTester tester, String cle, String texte) async {
      await tester.tap(find.byKey(Key(cle)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(texte).last);
      await tester.pumpAndSettle();
    }

    Future<void> ouvrir(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('bouton-nouvelle-depense')));
      await tester.pumpAndSettle();
    }

    Future<void> remplir(WidgetTester tester) async {
      await tester.enterText(find.byKey(const Key('champ-ligne.0.libelle')), 'Provende ponte');
      await choisir(tester, 'liste-ligne-0-compte', '601 - Achats de marchandises');
      await tester.enterText(find.byKey(const Key('champ-ligne.0.montant')), '25000');
      await tester.pumpAndSettle();
    }

    Future<void> enregistrer(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.tap(find.byKey(const Key('bouton-enregistrer-depense')));
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️ « Centre de Coût * » obligatoire : l\'astérisque, « -- Sélectionner -- », le message sous le champ', (tester) async {
      await afficher(tester);
      await ouvrir(tester);

      expect(find.text('CENTRE DE COÛT *'), findsOneWidget);
      expect(find.text('-- Aucun --'), findsOneWidget, reason: 'seul « Fournisseur » garde « Aucun » : le centre n\'est plus facultatif');
      await choisir(tester, 'liste-compte', 'Caisse Physique (500 000 FCFA)');
      await remplir(tester);
      await enregistrer(tester);

      expect(find.text(DepensesRepository.messageCentreObligatoire), findsOneWidget);
      expect(await db.select(db.expenses).get(), isEmpty);

      await choisir(tester, 'liste-centre', 'Général');
      await enregistrer(tester);
      expect((await db.select(db.expenses).get()).single.costCenterId, centreGeneral);
      await tester.pump(ToastAgri.duree);
      await tester.pumpAndSettle();
    });

    testWidgets('⚠️⚠️ « Règlement * » n\'apparaît qu\'avec un fournisseur ; à crédit : ni mode ni compte, l\'aide, puis l\'enregistrement', (tester) async {
      await afficher(tester);
      await ouvrir(tester);

      expect(find.text('RÈGLEMENT *'), findsNothing);
      expect(find.text('MODE DE PAIEMENT *'), findsOneWidget);

      await choisir(tester, 'liste-fournisseur', 'Agri-Bénin');
      expect(find.text('RÈGLEMENT *'), findsOneWidget);
      expect(find.text('Payée comptant'), findsOneWidget, reason: 'par défaut');
      expect(find.text('MODE DE PAIEMENT *'), findsOneWidget, reason: 'comptant : la trésorerie reste demandée');

      await choisir(tester, 'liste-reglement', 'À crédit (dette fournisseur)');
      expect(find.text('MODE DE PAIEMENT *'), findsNothing);
      expect(find.text('COMPTE DE TRÉSORERIE DÉBITÉ *'), findsNothing);
      expect(find.byKey(const Key('depense-aide-credit')), findsOneWidget);

      // Retirer le fournisseur ramène au comptant (pas de crédit sans fournisseur).
      await choisir(tester, 'liste-fournisseur', '-- Aucun --');
      expect(find.text('RÈGLEMENT *'), findsNothing);
      expect(find.text('MODE DE PAIEMENT *'), findsOneWidget);
      await choisir(tester, 'liste-fournisseur', 'Agri-Bénin');
      await choisir(tester, 'liste-reglement', 'À crédit (dette fournisseur)');

      await choisir(tester, 'liste-centre', 'Général');
      await remplir(tester);
      await enregistrer(tester);

      expect(find.text('Dépense enregistrée avec succès.'), findsOneWidget);
      final d = (await db.select(db.expenses).get()).single;
      expect((d.onCredit, d.status, d.treasuryAccountId, d.paymentMode, d.supplierId, d.syncStatus),
          (true, 'en_attente', null, null, _agriBenin, SyncStatus.pending));
      expect(find.text('À crédit'), findsOneWidget, reason: 'colonne « Mode » du tableau');
      await tester.tap(find.byKey(const Key('depense-deplier-0')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('depense-detail-resume-0'))).data,
        'Trésorerie : — · Centre de coût : Général · Fournisseur : Agri-Bénin · Bénéficiaire : — · Règlement : À crédit — en attente · Saisie par : —',
      );
      await tester.pump(ToastAgri.duree);
      await tester.pumpAndSettle();
    });

    testWidgets('archiver une dépense à crédit : le toast du web dit que la dette est annulée', (tester) async {
      final d = await aCredit();
      await afficher(tester);

      await tester.tap(find.byKey(Key('depense-archiver-${d.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('archivage-depense-confirmer')));
      await tester.pumpAndSettle();

      expect(find.text(DepensesRepository.toastArchiveeACredit), findsOneWidget);
      expect((await (db.select(db.expenses)..where((t) => t.id.equals(d.id))).getSingle()).isActive, isFalse);
      await tester.pump(ToastAgri.duree);
      await tester.pumpAndSettle();
    });
  });
}
