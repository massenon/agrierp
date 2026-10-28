import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:agrierp/features/comptabilite/immobilisations_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket CP-3 — LE REGISTRE DES IMMOBILISATIONS S'ÉCRIT AU POSTE (`Comptabilite\Immobilisations` : enregistrer, modifier,
/// sortir, passer la dotation).
///
/// Le poste écrit le BIEN (`pending`) et la DEMANDE de dotation ; le serveur (`ImmobilisationService`) capitalise, dote
/// (681 / 281) et rend les écritures. Les montants affichés sont ceux du modèle web (parité exécutée dans
/// `immobilisations_parite_php_test.dart`).
class _Serveur extends Interceptor {
  final List<Map<String, dynamic>> envois = [];
  final refus = <String, String>{};
  Map<String, dynamic> tirage = {'server_time': '2026-10-28T12:00:00Z'};

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
                  'accepted': [for (final e in value) if (e is Map && !refus.containsKey(e['id'])) e['id']],
                  'rejected': [for (final e in value) if (e is Map && refus.containsKey(e['id'])) {'id': e['id'], 'reason': refus[e['id']]}],
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
  late ImmobilisationsRepository depot;

  final aujourdhui = DateTime(2026, 10, 28, 10);

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  Future<void> plan(String code, String libelle, int classe) => db.into(db.chartOfAccounts).insert(
    ChartOfAccountsCompanion.insert(id: uuid('c$code'), code: code, label: libelle, accountClass: Value(classe)),
  );

  Future<void> bienServeur(String id, String code,
      {String compte = '244', double valeur = 1200000, double residuelle = 0, int duree = 5, bool capitalise = true, DateTime? acquisition, String statut = 'en_service', DateTime? sortie}) =>
      db.into(db.fixedAssets).insert(
        FixedAssetsCompanion.insert(
          id: uuid(id), code: code, label: 'Bien $code', accountCode: compte,
          acquisitionDate: acquisition ?? DateTime(2025, 10, 28), acquisitionValue: valeur, durationYears: duree,
          residualValue: Value(residuelle), isCapitalized: Value(capitalise), status: Value(statut), disposalDate: Value(sortie),
        ),
      );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serveur = _Serveur();
    moteur = SyncEngine(
      database: db,
      client: Dio()..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _Connectivite(),
      maintenant: () => DateTime(2026, 10, 28, 14),
    );
    depot = ImmobilisationsRepository(database: db, deviceId: 'poste-test', horloge: () => aujourdhui);
    await db.into(db.fiscalYears).insert(
      FiscalYearsCompanion.insert(id: uuid('ex26'), year: 2026, startDate: Value(DateTime(2026, 1, 1)), endDate: Value(DateTime(2026, 12, 31)), status: const Value('ouvert')),
    );
    await plan('221', 'Bâtiments et constructions', 2);
    await plan('244', 'Matériel et mobilier', 2);
    await plan('241', 'Matériel et outillage industriel', 2);
    await plan('281', 'Amortissements des immobilisations', 2);
    await plan('681', 'Dotations aux amortissements', 6);
    await plan('401', 'Fournisseurs', 4);
    await db.into(db.treasuryAccounts).insert(TreasuryAccountsCompanion.insert(id: uuid('t531'), label: 'Caisse Principale', accountCode: const Value('531')));
  });
  tearDown(() async => db.close());

  Future<FixedAsset> bien(String id) => (db.select(db.fixedAssets)..where((b) => b.id.equals(id))).getSingle();

  Future<Map<String, String>> refus(Future<void> Function() geste) async {
    try {
      await geste();
    } on SaisieImmobilisationRefusee catch (e) {
      return e.erreurs;
    }
    fail('accepté');
  }

  Future<FixedAsset> creerBroyeur({String code = 'IMM-001', String contrepartie = ''}) => depot.creer(
    code: code, libelle: 'Broyeur à provende', nature: '244', dateAcquisition: DateTime(2026, 4, 28),
    valeur: '620000', residuelle: '0', duree: '5', contrepartie: contrepartie,
  );

  group('dépôt', () {
    test('⚠️ un bien créé est pending, d\'origine ce poste, JAMAIS capitalisé au poste, avec sa contrepartie', () async {
      final b = await creerBroyeur(contrepartie: 'credit');

      expect((b.syncStatus, b.deviceId, b.status, b.isActive), (SyncStatus.pending, 'poste-test', 'en_service', true));
      expect(b.isCapitalized, isFalse, reason: 'seul le serveur écrit l\'acquisition au grand livre');
      expect(b.counterpart, 'credit');
      expect((b.code, b.accountCode, b.acquisitionValue, b.durationYears), ('IMM-001', '244', 620000, 5));
    });

    test('⚠️⚠️ les refus du web sont reproduits AVANT d\'écrire, avec les messages de lang/fr', () async {
      await bienServeur('b1', 'IMM-001');
      var e = await refus(() => depot.creer(code: 'IMM-001', libelle: 'x', nature: '244', dateAcquisition: DateTime(2026, 1, 1), valeur: '1000', residuelle: '0', duree: '5'));
      expect(e['code'], 'La valeur du champ code est déjà utilisée.');

      e = await refus(() => depot.creer(code: '', libelle: '', nature: '', dateAcquisition: null, valeur: '', residuelle: '', duree: ''));
      expect(e, {
        'code': 'Le champ code est obligatoire.',
        'label': 'Le champ libellé est obligatoire.',
        'accountCode': 'Le champ nature est obligatoire.',
        'acquisitionDate': "Le champ date d'acquisition est obligatoire.",
        'acquisitionValue': "Le champ valeur d'acquisition est obligatoire.",
        'residualValue': 'Le champ valeur résiduelle est obligatoire.',
        'durationYears': "Le champ durée d'amortissement est obligatoire.",
      });

      e = await refus(() => depot.creer(code: 'A', libelle: 'x', nature: '601', dateAcquisition: DateTime(2026, 12, 31), valeur: '0', residuelle: '5000', duree: '51'));
      expect(e['accountCode'], "La valeur sélectionnée pour le champ nature n'est pas valide.");
      expect(e['acquisitionDate'], "Le champ date d'acquisition doit être une date antérieure ou égale à aujourd'hui.");
      expect(e['acquisitionValue'], "Le champ valeur d'acquisition doit être au moins égal à 1.");
      expect(e['durationYears'], "Le champ durée d'amortissement ne doit pas dépasser 50.");

      e = await refus(() => depot.creer(code: 'B', libelle: 'x', nature: '244', dateAcquisition: DateTime(2026, 1, 1), valeur: '1000', residuelle: '1000', duree: '2.5'));
      expect(e['residualValue'], 'Le champ valeur résiduelle doit être inférieur à 1000.');
      expect(e['durationYears'], "Le champ durée d'amortissement doit être un nombre entier.");

      expect((await db.select(db.fixedAssets).get()).length, 1, reason: 'rien n\'a été écrit');
    });

    test('la nature doit être une des natures de la ferme (221, 241, 244) ou déjà portée par un bien — jamais un compte 28x', () async {
      await plan('2815', 'Amortissement matériel', 2);
      await plan('231', 'Bâtiments en cours', 2);
      final natures = (await depot.natures()).map((n) => n.code);
      expect(natures, ['221', '241', '244']);
      expect((await refus(() => depot.creer(code: 'A', libelle: 'x', nature: '2815', dateAcquisition: DateTime(2026, 1, 1), valeur: '1000', residuelle: '0', duree: '5')))['accountCode'], isNotNull);

      await bienServeur('b1', 'IMM-900', compte: '231');
      expect((await depot.natures()).map((n) => n.code), ['221', '231', '241', '244']);
    });

    test('⚠️ la valeur d\'un bien comptabilisé est figée (motif du web), un bien non comptabilisé se modifie', () async {
      await bienServeur('b1', 'IMM-001', valeur: 620000);
      var e = await refus(() => depot.modifier(uuid('b1'), code: 'IMM-001', libelle: 'x', nature: '244', dateAcquisition: DateTime(2025, 10, 28), valeur: '900000', residuelle: '0', duree: '5'));
      expect(e['acquisitionValue'], ImmobilisationsRepository.motifValeurFigee);

      final b = await depot.modifier(uuid('b1'), code: 'IMM-001', libelle: 'Broyeur à marteaux', nature: '244', dateAcquisition: DateTime(2025, 10, 28), valeur: '620000', residuelle: '0', duree: '8');
      expect((b.label, b.durationYears, b.syncStatus), ('Broyeur à marteaux', 8, SyncStatus.pending));

      await bienServeur('b2', 'IMM-002', capitalise: false, valeur: 100000);
      final c = await depot.modifier(uuid('b2'), code: 'IMM-002', libelle: 'x', nature: '244', dateAcquisition: DateTime(2025, 10, 28), valeur: '150000', residuelle: '0', duree: '5');
      expect(c.acquisitionValue, 150000);
    });

    test('⚠️ la sortie ne supprime rien : statut, date et motif ; refusée avant l\'acquisition ; une fois seulement', () async {
      await bienServeur('b1', 'IMM-001', acquisition: DateTime(2025, 10, 28));
      var e = await refus(() => depot.sortir(uuid('b1'), date: DateTime(2025, 1, 1), statut: 'cede', motif: 'Vendu'));
      expect(e['cessionDate'], "La date de sortie ne peut pas précéder l'acquisition.");
      e = await refus(() => depot.sortir(uuid('b1'), date: null, statut: 'autre', motif: ''));
      expect(e.keys, containsAll(['cessionDate', 'cessionStatus', 'cessionReason']));

      final b = await depot.sortir(uuid('b1'), date: DateTime(2026, 3, 20), statut: 'cede', motif: ' Vendu à un éleveur ');
      expect((b.status, b.disposalReason, b.syncStatus), ('cede', 'Vendu à un éleveur', SyncStatus.pending));
      expect((await depot.charger()).biens, hasLength(1), reason: 'le bien reste au registre');
      await expectLater(depot.sortir(uuid('b1'), date: DateTime(2026, 4, 1), statut: 'reforme', motif: 'x'), throwsA(isA<SaisieImmobilisationRefusee>()));
    });

    test('⚠️⚠️ ventilation, cartes et « à doter » : brut − amortissement, hors compta, solde de 281 lu au journal', () async {
      // 620 000 sur 5 ans, un an plein => 124 000 ; un second bien hors comptabilité (reprise) : 300 000 sur 3 ans, un an => 100 000.
      await bienServeur('b1', 'IMM-001', valeur: 620000);
      await bienServeur('b2', 'IMM-002', compte: '221', valeur: 300000, duree: 3, capitalise: false);

      var d = await depot.charger();
      final arrete = DateTime(2026, 10, 28);
      final v = ImmobilisationsRepository.ventilation(d, arrete);
      expect([for (final l in v) (l.code, l.libelle, l.nombre, l.brut, l.amortissement, l.net, l.horsCompta)], [
        ('221', 'Bâtiments et constructions', 1, 300000.0, 100000.0, 200000.0, 300000.0),
        ('244', 'Matériel et mobilier', 1, 620000.0, 124000.0, 496000.0, 0.0),
      ]);
      var k = ImmobilisationsRepository.kpis(d, arrete);
      expect((k.brut, k.amortissement, k.net, k.horsCompta), (920000.0, 224000.0, 696000.0, 300000.0));
      expect(k.aDoter, isNull, reason: 'aucune écriture reçue : le solde de 281 est inconnu, jamais 0');

      // Une dotation de 24 000 déjà passée au crédit de 281 : reste 124 000 − 24 000 = 100 000 (seul le bien capitalisé compte).
      await db.into(db.accountingEntries).insert(AccountingEntriesCompanion.insert(id: uuid('e1'), fiscalYearId: Value(uuid('ex26')), entryDate: DateTime(2026, 6, 30)));
      await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: uuid('l1'), entryId: uuid('e1'), accountId: uuid('c681'), debit: const Value(24000)));
      await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: uuid('l2'), entryId: uuid('e1'), accountId: uuid('c281'), credit: const Value(24000)));
      d = await depot.charger();
      k = ImmobilisationsRepository.kpis(d, arrete);
      expect(k.aDoter, 100000);
      expect(ImmobilisationsRepository.montantADoter(d, DateTime(2025, 10, 1)), 0, reason: 'jamais négatif');
    });

    test('⚠️ « Passer la Dotation » écrit une DEMANDE (la date seule), refusée si exercice clos ou rien à doter, jamais doublée', () async {
      await bienServeur('b1', 'IMM-001', valeur: 620000);
      await db.into(db.accountingEntries).insert(AccountingEntriesCompanion.insert(id: uuid('e1'), fiscalYearId: Value(uuid('ex26')), entryDate: DateTime(2026, 1, 5)));
      await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: uuid('l1'), entryId: uuid('e1'), accountId: uuid('c531'.padRight(4, '0')), debit: const Value(1)));

      final d1 = await depot.passerDotation(DateTime(2026, 10, 28));
      final d2 = await depot.passerDotation(DateTime(2026, 10, 28));
      expect(d2.id, d1.id, reason: 'une demande en attente pour ce jour n\'est pas doublée');
      expect((d1.syncStatus, d1.dateArrete), (SyncStatus.pending, DateTime(2026, 10, 28)));
      expect((await db.select(db.depreciationRequests).get()).length, 1);

      final e = await refus(() async => depot.passerDotation(DateTime(2027, 3, 1)));
      expect(e['formulaire'], isNotNull, reason: 'aucun exercice ne couvre 2027');
    });
  });

  group('moteur', () {
    test('⚠️⚠️ l\'envoi porte la ligne entière et la contrepartie ; la dotation ne porte que la date', () async {
      final b = await creerBroyeur(contrepartie: uuid('t531'));
      await bienServeur('b2', 'IMM-002');
      await (db.update(db.fixedAssets)..where((x) => x.id.equals(uuid('b2')))).write(const FixedAssetsCompanion(syncStatus: Value(SyncStatus.synced)));
      await db.into(db.depreciationRequests).insert(DepreciationRequestsCompanion.insert(id: uuid('d1'), deviceId: 'poste-test', updatedAt: DateTime(2026, 10, 28), dateArrete: DateTime(2026, 10, 28)));

      await moteur.synchroniser();

      final envoi = serveur.envois.single;
      expect((envoi['fixed_assets'] as List), [
        {
          'id': b.id, 'code': 'IMM-001', 'label': 'Broyeur à provende', 'account_code': '244', 'acquisition_date': '2026-04-28',
          'acquisition_value': 620000.0, 'residual_value': 0.0, 'duration_years': 5, 'status': 'en_service', 'disposal_date': null,
          'disposal_reason': null, 'is_active': true, 'counterpart': uuid('t531'),
        },
      ]);
      expect(envoi['depreciation_requests'], [
        {'id': uuid('d1'), 'date_arrete': '2026-10-28'},
      ]);
      expect((await bien(b.id)).syncStatus, SyncStatus.synced);
      expect((await db.select(db.depreciationRequests).get()).single.syncStatus, SyncStatus.synced);
    });

    test('un refus du serveur devient conflict avec son motif, visible au registre, et se relance', () async {
      final b = await creerBroyeur();
      serveur.refus[b.id] = 'La valeur du champ code est déjà utilisée.';

      await moteur.synchroniser();

      expect((await bien(b.id)).syncStatus, SyncStatus.conflict);
      final conflit = (await db.select(db.syncConflicts).get()).firstWhere((x) => x.sourceTable == 'fixed_assets');
      expect(conflit.reason, contains('déjà utilisée'));
      expect((await depot.charger()).refus['fixed_assets:${b.id}'], contains('déjà utilisée'));
      await moteur.relancer(conflit);
      expect((await bien(b.id)).syncStatus, SyncStatus.pending);
    });

    test('⚠️ le tirage remplace les biens acquittés (capitalisés par le serveur), jamais un bien local non acquitté', () async {
      final local = await creerBroyeur();
      await (db.update(db.fixedAssets)..where((x) => x.id.equals(local.id))).write(const FixedAssetsCompanion(syncStatus: Value(SyncStatus.conflict)));
      await bienServeur('b1', 'IMM-010', capitalise: false);
      serveur.tirage = {
        'server_time': '2026-10-28T13:00:00Z',
        'fixed_assets': [
          {
            'id': uuid('b1'), 'code': 'IMM-010', 'label': 'Cage galvanisée', 'account_code': '241', 'acquisition_date': '2025-10-28',
            'acquisition_value': 1200000, 'residual_value': 0, 'duration_years': 5, 'status': 'en_service', 'disposal_date': null,
            'disposal_reason': null, 'is_capitalized': true, 'is_active': true,
          },
          {
            'id': local.id, 'code': 'IMM-001', 'label': 'Écrasé ?', 'account_code': '244', 'acquisition_date': '2026-04-28',
            'acquisition_value': 1, 'residual_value': 0, 'duration_years': 1, 'status': 'cede', 'disposal_date': '2026-05-01',
            'disposal_reason': 'x', 'is_capitalized': true, 'is_active': true,
          },
        ],
      };

      await moteur.synchroniser();

      final b1 = await bien(uuid('b1'));
      expect((b1.label, b1.isCapitalized, b1.syncStatus), ('Cage galvanisée', true, SyncStatus.synced));
      final l = await bien(local.id);
      expect((l.label, l.syncStatus), ('Broyeur à provende', SyncStatus.conflict), reason: 'jamais écrasé tant qu\'il n\'est pas acquitté');
    });
  });

  group('écran', () {
    Future<void> afficher(WidgetTester tester, {bool journal = true}) async {
      tester.view.physicalSize = const Size(1800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(ToastAgri.toutRetirer);
      await tester.pumpWidget(
        MaterialApp(
          home: ComptabiliteScreen(
            depot: ComptabiliteRepository(database: db, deviceId: 'poste-test'),
            depotImmobilisations: depot,
            maintenant: () => aujourdhui,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('carte-immobilisations')));
      await tester.pumpAndSettle();
    }

    Future<void> ecriture281() async {
      await db.into(db.accountingEntries).insert(AccountingEntriesCompanion.insert(id: uuid('e1'), fiscalYearId: Value(uuid('ex26')), entryDate: DateTime(2026, 1, 5)));
      await db.into(db.accountingEntryLines).insert(AccountingEntryLinesCompanion.insert(id: uuid('l1'), entryId: uuid('e1'), accountId: uuid('c401'), credit: const Value(1)));
    }

    testWidgets('⚠️ la page rend les libellés du Blade : cartes, ventilation, registre à onze colonnes, actions', (tester) async {
      await bienServeur('b1', 'IMM-001', valeur: 620000);
      await bienServeur('b2', 'IMM-002', compte: '221', valeur: 300000, duree: 3, capitalise: false);
      await ecriture281();
      await afficher(tester);

      // Cartes et en-têtes de colonne s'écrivent en capitales (`uppercase` du Blade) : on compare sans la casse.
      expect(find.text('Nouvelle Immobilisation'), findsOneWidget);
      for (final t in ["Date d'arrêté", 'Nature', 'Statut', 'Amortissements Cumulés', 'Valeur Nette Comptable', 'Dotation à Comptabiliser']) {
        expect(find.text(t.toUpperCase()), findsWidgets, reason: t);
      }
      for (final t in ['Immobilisations', "Ventilation par Nature d'Actif", 'TOTAL IMMOBILISATIONS', 'Registre Détaillé']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      for (final c in ['Code', 'Désignation', 'Acquisition', 'Durée', 'Annuité', 'Cumul Amort.', 'V.N.C.', 'Comptabilisé', 'Statut', 'Actions']) {
        expect(find.text(c.toUpperCase()), findsWidgets, reason: c);
      }
      expect(find.text('920 000 F'), findsOneWidget);
      expect(find.text('−224 000 F'), findsOneWidget);
      expect(find.text('696 000 F'), findsOneWidget);
      expect(find.text('124 000 F'), findsOneWidget, reason: 'amortissement du seul bien capitalisé, rien passé au crédit de 281 à ce jour');
      expect(find.textContaining('300 000 FCFA hors comptabilité'), findsOneWidget);
      expect(find.text('Dotation aux amortissements en attente'), findsOneWidget);
    });

    testWidgets('⚠️ sans écriture reçue, « Dotation à Comptabiliser » est un tiret, jamais 0, et aucun bandeau', (tester) async {
      await bienServeur('b1', 'IMM-001');
      await afficher(tester);

      expect(find.descendant(of: find.byKey(const Key('kpi-immo-a-doter')), matching: find.text('—')), findsOneWidget);
      expect(find.byKey(const Key('immo-bandeau-dotation')), findsNothing);
    });

    testWidgets('⚠️⚠️ « Nouvelle Immobilisation » : refus sous les champs (messages du web), puis le bien est écrit et affiché', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('immo-nouvelle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('immo-enregistrer')));
      await tester.pumpAndSettle();
      expect(find.text('Le champ code est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ nature est obligatoire.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('immo-code')), 'IMM-077');
      await tester.enterText(find.byKey(const Key('immo-libelle')), 'Couveuse');
      await tester.enterText(find.byKey(const Key('immo-valeur')), '480000');
      await tester.enterText(find.byKey(const Key('immo-duree')), '4');
      await tester.tap(find.byKey(const Key('immo-nature')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('244 — Matériel et mobilier').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('immo-contrepartie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('À crédit — dette fournisseur (401)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('immo-enregistrer')));
      await tester.pumpAndSettle();

      final b = (await db.select(db.fixedAssets).get()).single;
      expect((b.code, b.accountCode, b.acquisitionValue, b.counterpart, b.syncStatus, b.isCapitalized), ('IMM-077', '244', 480000, 'credit', SyncStatus.pending, false));
      expect(find.text('Couveuse'), findsOneWidget);
      expect(find.text('En attente de synchronisation'), findsOneWidget);
    });

    testWidgets('« Sortie d\'Immobilisation » : le bien reste au registre sous « Tous statuts » avec « Cédée … »', (tester) async {
      await bienServeur('b1', 'IMM-001');
      await afficher(tester);

      await tester.tap(find.byKey(Key('immo-sortie-${uuid('b1')}')));
      await tester.pumpAndSettle();
      expect(find.text("Sortie d'Immobilisation"), findsOneWidget);
      await tester.tap(find.byKey(const Key('sortie-confirmer')));
      await tester.pumpAndSettle();
      expect(find.text('Le champ motif est obligatoire.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('sortie-motif')), 'Vendu à un éleveur voisin');
      await tester.tap(find.byKey(const Key('sortie-confirmer')));
      await tester.pumpAndSettle();

      final b = await bien(uuid('b1'));
      expect((b.status, b.disposalReason, b.syncStatus), ('cede', 'Vendu à un éleveur voisin', SyncStatus.pending));
      expect(find.text('Aucune immobilisation enregistrée pour ce filtre.'), findsOneWidget, reason: 'filtre « En service » par défaut');

      await tester.tap(find.byKey(const Key('immo-filtre-statut')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tous statuts').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Cédée 28/10/2026'), findsOneWidget);
    });

    testWidgets('« Passer la Dotation » écrit la demande et le bandeau le dit', (tester) async {
      await bienServeur('b1', 'IMM-001', valeur: 620000);
      await ecriture281();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('immo-passer-dotation')));
      await tester.pumpAndSettle();

      final d = (await db.select(db.depreciationRequests).get()).single;
      expect((d.syncStatus, d.dateArrete), (SyncStatus.pending, DateTime(2026, 10, 28)));
      expect(find.byKey(const Key('immo-dotation-demandee')), findsOneWidget);
    });
  });
}
