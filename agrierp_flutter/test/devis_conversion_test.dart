import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/ventes/devis_onglet.dart';
import 'package:agrierp/features/ventes/devis_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket DEV3 — « CONVERTIR EN FACTURE » AU POSTE (DEV-Q1 close, PRD `docs/prd/devis-poste.md` § 11).
///
/// Le web (`ConvertirDevisEnFactureAction`, `Livewire\Ventes\Devis::convertToInvoice`) est maître ; le poste hors ligne
/// écrit la DEMANDE (`conversion_requested_at`, devis figé), l'envoie (`quote_conversions`), reçoit la facture à
/// l'acquittement (`invoices` : lien et numéro, que le serveur seul calcule) et affiche l'état. Le garde-fou de parité
/// des messages et des conditions est `devis_blade_test.dart`.
///
/// Horloge figée au mercredi 21/10/2026 10:00 (heure du Bénin). Valeurs attendues écrites à la main.
String _uuid(String cle) {
  final hex = cle.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  final h = hex.padRight(32, '0').substring(0, 32);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-8${h.substring(17, 20)}-${h.substring(20, 32)}';
}

class _Connectivite implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// Serveur feint : sert [tirage] ; à l'envoi, acquitte chaque ligne sauf celles de [refus] (id → motif), et rend pour
/// chaque demande de conversion acceptée la facture de [factures] (devis → (sale_id, invoice_number)).
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-21T09:00:00Z'};
  final Map<String, String> refus = {};
  final Map<String, (String, String)> factures = {};

  /// `false` : un serveur antérieur à DEV3 — il ignore `quote_conversions`.
  bool connaitLaConversion = true;
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
              if (value is List && (connaitLaConversion || key != 'quote_conversions'))
                key: {
                  'accepted': [
                    for (final e in value)
                      if (e is Map && e['id'] is String && !refus.containsKey('$key:${e['id']}')) e['id'],
                  ],
                  'rejected': [
                    for (final e in value)
                      if (e is Map && refus.containsKey('$key:${e['id']}')) {'id': e['id'], 'reason': refus['$key:${e['id']}']},
                  ],
                  if (key == 'quote_conversions')
                    'invoices': {
                      for (final e in value)
                        if (e is Map && factures.containsKey(e['id']) && !refus.containsKey('$key:${e['id']}'))
                          e['id']: {'sale_id': factures[e['id']]!.$1, 'invoice_number': factures[e['id']]!.$2},
                    },
                },
          },
        ),
      );
      return;
    }
    handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: tirage));
  }
}

void main() {
  late AppDatabase db;
  late DevisRepository depot;

  final client = _uuid('client-amoussou');
  final vente = _uuid('vente-facture');

  Future<void> exercice(int annee, String statut) => db
      .into(db.fiscalYears)
      .insert(
        FiscalYearsCompanion.insert(
          id: _uuid('ex$annee'),
          year: annee,
          startDate: Value(DateTime(annee)),
          endDate: Value(DateTime(annee, 12, 31)),
          status: Value(statut),
        ),
      );

  Future<void> devis(
    String cle, {
    String statut = 'accepte',
    bool actif = true,
    DateTime? date,
    double tva = 18,
    SyncStatus synchro = SyncStatus.synced,
    DateTime? demande,
    String? facture,
    String? numeroFacture,
    String numero = 'DEV-2026-001',
    String? clientId,
  }) => db
      .into(db.quotes)
      .insert(
        QuotesCompanion.insert(
          id: _uuid(cle),
          deviceId: 'serveur',
          syncStatus: Value(synchro),
          updatedAt: DateTime(2026, 10, 20),
          quoteNumber: Value(numero),
          customerId: clientId ?? client,
          articlesDescription: '2 cages galvanisées 6 compartiments',
          amount: 150000,
          tvaRate: Value(tva),
          quoteDate: date ?? DateTime(2026, 10, 20),
          status: Value(statut),
          isActive: Value(actif),
          conversionRequestedAt: Value(demande),
          convertedSaleId: Value(facture),
          invoiceNumber: Value(numeroFacture),
        ),
      );

  Future<Quote> lire(String cle) => (db.select(db.quotes)..where((t) => t.id.equals(_uuid(cle)))).getSingle();

  Future<String?> motif(Future<Object?> Function() geste) async {
    try {
      await geste();
    } on DevisRefuse catch (e) {
      return e.motif;
    }
    return null;
  }

  setUp(() async {
    HeureBenin.horloge = () => DateTime.utc(2026, 10, 21, 9);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = DevisRepository(database: db, deviceId: 'poste-test');
    await db.into(db.customers).insert(CustomersCompanion.insert(id: client, name: 'AMOUSSOU Régis'));
  });

  tearDown(() async {
    HeureBenin.reinitialiser();
    ToastAgri.toutRetirer();
    await db.close();
  });

  // ── Le dépôt : la demande, ses refus, le gel du devis ──────────────────────────────────────────────────────────────

  group('dépôt — demander la conversion', () {
    test('⚠️ un devis accepté : la demande est écrite (instant du clic, heure du Bénin), le devis reste accepté et repart en pending', () async {
      await devis('a');

      final r = await depot.demanderConversion(_uuid('a'));

      expect(r.deja, isFalse);
      final d = await lire('a');
      expect([d.status, d.syncStatus, d.conversionRequestedAt, d.convertedSaleId, d.invoiceNumber], [
        'accepte', SyncStatus.pending, DateTime(2026, 10, 21, 10), null, null,
      ], reason: 'le serveur crée la facture : le poste n\'invente ni le lien ni le numéro');
      expect(d.updatedAt.toUtc(), DateTime.utc(2026, 10, 21, 9));
    });

    test('un devis déjà converti : rien n\'est écrit, `deja`', () async {
      await devis('f', statut: 'facture', facture: vente, numeroFacture: 'FV-2026-ABC123');

      final r = await depot.demanderConversion(_uuid('f'));

      expect([r.deja, r.devis.invoiceNumber], [true, 'FV-2026-ABC123']);
      expect((await lire('f')).conversionRequestedAt, isNull);
    });

    test('une demande déjà ouverte est refusée (une seule demande par devis)', () async {
      await devis('a');
      await depot.demanderConversion(_uuid('a'));

      expect(await motif(() => depot.demanderConversion(_uuid('a'))), DevisRepository.messageConversionDemandee);
    });

    for (final (nom, statut, libelle) in [('brouillon', 'brouillon', 'Brouillon'), ('envoyé', 'envoye', 'Envoyé'), ('refusé', 'refuse', 'Refusé')]) {
      test('⚠️ seul un devis accepté est convertible : $nom → « Seul un devis accepté peut être converti en facture : celui-ci est « $libelle ». »', () async {
        await devis('x', statut: statut);

        expect(await motif(() => depot.demanderConversion(_uuid('x'))), 'Seul un devis accepté peut être converti en facture : celui-ci est « $libelle ».');
        expect((await lire('x')).conversionRequestedAt, isNull);
      });
    }

    test('un devis archivé, inconnu', () async {
      await devis('r', actif: false);

      expect(await motif(() => depot.demanderConversion(_uuid('r'))), 'Ce devis est archivé : il ne peut pas être converti en facture.');
      expect(await motif(() => depot.demanderConversion(_uuid('inconnu'))), 'Devis introuvable sur ce poste.');
    });

    test('⚠️ client archivé, client inconnu du poste : les motifs du serveur', () async {
      await devis('a');
      await (db.update(db.customers)..where((t) => t.id.equals(client))).write(const CustomersCompanion(isActive: Value(false)));
      expect(await motif(() => depot.demanderConversion(_uuid('a'))), 'Le client « AMOUSSOU Régis » est archivé : réactivez-le avant de facturer ce devis.');

      await devis('b', clientId: _uuid('client-fantome'), numero: 'DEV-2026-002');
      expect(await motif(() => depot.demanderConversion(_uuid('b'))), "Ce devis n'a pas de client : une facture à crédit en exige un.");
      expect((await lire('a')).conversionRequestedAt, isNull);
    });

    test('⚠️ un devis d\'un exercice clos est en lecture seule : refusé avec le motif R4 ; la date de la facture est jugée comme une vente', () async {
      await exercice(2025, 'cloture');
      await exercice(2026, 'ouvert');
      await devis('c', date: DateTime(2025, 12, 20));
      expect(
        await motif(() => depot.demanderConversion(_uuid('c'))),
        "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.",
      );

      // Le poste est réglé au 20/12/2025 (exercice clos) : la FACTURE serait datée de ce jour-là.
      await devis('d', date: DateTime(2026, 1, 10), numero: 'DEV-2026-002');
      HeureBenin.horloge = () => DateTime.utc(2025, 12, 20, 9);
      expect(
        await motif(() => depot.demanderConversion(_uuid('d'))),
        "Facture refusée : l'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.",
      );
      expect((await lire('d')).conversionRequestedAt, isNull);
    });
  });

  group('dépôt — le devis est figé tant que la demande est ouverte', () {
    test('⚠️ modifier, avancer, archiver : refusés avec le motif de la demande ouverte', () async {
      await devis('a');
      await depot.demanderConversion(_uuid('a'));

      expect(
        await motif(
          () => depot.enregistrer(
            clientId: client, articles: 'Autre', montant: '1', tva: '0', validite: '15', date: DateTime(2026, 10, 20), idEnModification: _uuid('a'),
          ),
        ),
        DevisRepository.messageConversionDemandee,
      );
      expect(await motif(() => depot.changerStatut(_uuid('a'), 'refuse')), DevisRepository.messageConversionDemandee);
      expect(await motif(() => depot.archiver(_uuid('a'))), DevisRepository.messageConversionDemandee);
      expect((await lire('a')).isActive, isTrue);
    });

    test('un devis facturé ne se modifie plus (message du web) et ne change pas de statut', () async {
      await devis('f', statut: 'facture', facture: vente, numeroFacture: 'FV-2026-ABC123');

      expect(
        await motif(
          () => depot.enregistrer(
            clientId: client, articles: 'Autre', montant: '1', tva: '0', validite: '15', date: DateTime(2026, 10, 20), idEnModification: _uuid('f'),
          ),
        ),
        'Ce devis est facturé : il ne peut plus être modifié.',
      );
      expect(await motif(() => depot.changerStatut(_uuid('f'), 'accepte')), 'Changement de statut interdit : un devis « Facturé » ne peut pas passer à « Accepté ».');
    });

    test('annuler la demande : seulement une demande REFUSÉE ; le devis redevient libre', () async {
      await devis('a');
      await depot.demanderConversion(_uuid('a'));
      expect(await depot.annulerConversion(_uuid('a')), isFalse, reason: 'en attente d\'envoi : elle part à la prochaine synchronisation');

      await (db.update(db.quotes)..where((t) => t.id.equals(_uuid('a')))).write(const QuotesCompanion(syncStatus: Value(SyncStatus.conflict)));
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'quote_conversions:${_uuid('a')}', sourceTable: 'quote_conversions', recordId: _uuid('a'), reason: 'Refus', detectedAt: DateTime(2026, 10, 21),
        ),
      );
      expect(await depot.annulerConversion(_uuid('a')), isTrue);

      final d = await lire('a');
      expect([d.conversionRequestedAt, d.syncStatus, d.status], [null, SyncStatus.pending, 'accepte']);
      expect(await db.select(db.syncConflicts).get(), isEmpty);
      expect(await motif(() => depot.changerStatut(_uuid('a'), 'refuse')), 'Changement de statut interdit : un devis « Accepté » ne peut pas passer à « Refusé ».',
          reason: 'libre : c\'est le cycle qui parle de nouveau, plus la demande');
    });

    test('la liste : « demande ouverte » et « demande refusée » (motif de quote_conversions, mot pour mot)', () async {
      await devis('a');
      await depot.demanderConversion(_uuid('a'));
      var l = (await depot.charger()).lignes.single;
      expect([l.conversionDemandee, l.conversionRefusee, l.motifRefus], [true, false, null]);

      await (db.update(db.quotes)..where((t) => t.id.equals(_uuid('a')))).write(const QuotesCompanion(syncStatus: Value(SyncStatus.conflict)));
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'quote_conversions:${_uuid('a')}', sourceTable: 'quote_conversions', recordId: _uuid('a'),
          reason: 'Plan comptable incomplet : le compte 701 (Ventes de produits) est introuvable.', detectedAt: DateTime(2026, 10, 21),
        ),
      );
      l = (await depot.charger()).lignes.single;
      expect([l.conversionRefusee, l.motifRefus], [true, 'Plan comptable incomplet : le compte 701 (Ventes de produits) est introuvable.']);
    });

    test('un devis facturé n\'est plus « actif » aux cartes : ni Devis Actifs, ni Valeur Totale', () async {
      await devis('a', statut: 'accepte');
      await devis('f', statut: 'facture', facture: vente, numeroFacture: 'FV-2026-ABC123', numero: 'DEV-2026-002');

      final k = (await depot.charger()).kpis;

      expect([k.devisActifs, k.valeurTotale], [1, 150000]);
    });
  });

  // ── Le moteur : la demande part, la facture revient ────────────────────────────────────────────────────────────────

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
        maintenant: () => DateTime(2026, 10, 21, 10),
      );
    });

    test('⚠️ l\'envoi porte le devis ET sa demande ({id, requested_at}) ; sans demande, aucune clé quote_conversions', () async {
      await devis('a');
      await devis('b', numero: 'DEV-2026-002', statut: 'brouillon', synchro: SyncStatus.pending);
      await depot.demanderConversion(_uuid('a'));

      await moteur.synchroniser();

      final corps = serveur.envois.single;
      expect((corps['quotes'] as List).map((q) => (q as Map)['id']), unorderedEquals([_uuid('a'), _uuid('b')]));
      expect(corps['quote_conversions'], [
        {'id': _uuid('a'), 'requested_at': '2026-10-21 10:00:00'},
      ]);

      serveur.envois.clear();
      await devis('c', numero: 'DEV-2026-003', statut: 'brouillon', synchro: SyncStatus.pending);
      await moteur.synchroniser();
      expect(serveur.envois.single.containsKey('quote_conversions'), isFalse);
    });

    test('⚠️⚠️ la facture revient à l\'acquittement : statut facturé, lien, numéro du SERVEUR, demande fermée, synced', () async {
      await devis('a');
      await depot.demanderConversion(_uuid('a'));
      serveur.factures[_uuid('a')] = (vente, 'FV-2026-ABC123');

      await moteur.synchroniser();

      final d = await lire('a');
      expect([d.status, d.convertedSaleId, d.invoiceNumber, d.conversionRequestedAt, d.syncStatus], [
        'facture', vente, 'FV-2026-ABC123', null, SyncStatus.synced,
      ]);
      expect(await db.select(db.syncConflicts).get(), isEmpty);
      // Ce qui est dit à l'écran : la ligne, ni demandée ni refusée.
      final l = (await depot.charger()).lignes.single;
      expect([l.conversionDemandee, l.devis.invoiceNumber], [false, 'FV-2026-ABC123']);
    });

    test('⚠️ un serveur antérieur à DEV3 (aucune réponse pour la demande) : le devis RESTE en attente avec sa demande, rien n\'est perdu', () async {
      await devis('a');
      await depot.demanderConversion(_uuid('a'));
      serveur.connaitLaConversion = false;

      await moteur.synchroniser();

      final d = await lire('a');
      expect([d.syncStatus, d.conversionRequestedAt != null, d.status, d.convertedSaleId], [SyncStatus.pending, true, 'accepte', null]);
    });

    test('⚠️ une demande REFUSÉE : conflit avec le motif mot pour mot (conflit « quote_conversions »), le devis reste figé ; relancer la remet en file', () async {
      await devis('a');
      await depot.demanderConversion(_uuid('a'));
      const refus = 'Le client « AMOUSSOU Régis » est archivé : réactivez-le avant de facturer ce devis.';
      serveur.refus['quote_conversions:${_uuid('a')}'] = refus;

      await moteur.synchroniser();

      var d = await lire('a');
      expect([d.syncStatus, d.status, d.conversionRequestedAt != null, d.convertedSaleId], [SyncStatus.conflict, 'accepte', true, null]);
      final conflit = (await db.select(db.syncConflicts).get()).single;
      expect([conflit.sourceTable, conflit.recordId, conflit.reason], ['quote_conversions', _uuid('a'), refus]);
      final l = (await depot.charger()).lignes.single;
      expect([l.conversionRefusee, l.motifRefus], [true, refus]);

      await moteur.relancer(conflit);
      d = await lire('a');
      expect(d.syncStatus, SyncStatus.pending);
    });

    test('⚠️ un refus de la demande ne perd pas le devis ; l\'envoi suivant, accepté, ferme la demande', () async {
      await devis('a');
      await depot.demanderConversion(_uuid('a'));
      serveur.refus['quote_conversions:${_uuid('a')}'] = 'Refus';
      await moteur.synchroniser();
      serveur.refus.clear();
      serveur.factures[_uuid('a')] = (vente, 'FV-2026-ABC123');
      await moteur.relancer((await db.select(db.syncConflicts).get()).single);

      await moteur.synchroniser();

      final d = await lire('a');
      expect([d.status, d.syncStatus, d.invoiceNumber], ['facture', SyncStatus.synced, 'FV-2026-ABC123']);
      expect(await db.select(db.syncConflicts).get(), isEmpty, reason: 'un refus périmé ne survit pas à l\'acceptation');
    });

    test('le tirage apporte le lien et le numéro de facture d\'un devis converti au web ou sur un autre poste', () async {
      serveur.tirage = {
        'server_time': '2026-10-21T09:00:00Z',
        'quotes': [_json('w1', statut: 'facture', facture: vente, numeroFacture: 'FV-2026-ABC123')],
      };

      await moteur.synchroniser();

      final d = await lire('w1');
      expect([d.status, d.convertedSaleId, d.invoiceNumber, d.conversionRequestedAt], ['facture', vente, 'FV-2026-ABC123', null]);
    });

    test('un serveur antérieur (clés absentes) ou un devis non converti (null) : pas de lien, pas de numéro', () async {
      serveur.tirage = {
        'server_time': '2026-10-21T09:00:00Z',
        'quotes': [
          // Serveur antérieur à DEV3 : les deux clés sont absentes.
          Map<String, dynamic>.of(_json('w1'))..remove('converted_sale_id')..remove('invoice_number'),
          // Devis non converti : les deux clés valent null.
          _json('w2'),
        ],
      };

      await moteur.synchroniser();

      expect([(await lire('w1')).convertedSaleId, (await lire('w2')).invoiceNumber], [null, null]);
    });

    for (final (nom, fautif) in <(String, Map<String, dynamic>)>[
      ('lien qui n\'est pas un texte', {..._json('w2'), 'converted_sale_id': 42}),
      ('numéro de facture qui n\'est pas un texte', {..._json('w2'), 'invoice_number': 7}),
    ]) {
      test('⚠️⚠️ STRICT — $nom : toute la page est refusée, rien n\'est écrit', () async {
        serveur.tirage = {
          'server_time': '2026-10-21T09:00:00Z',
          'quotes': [_json('w1'), fautif],
        };

        await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));

        expect(await db.select(db.quotes).get(), isEmpty);
      });
    }

    test('⚠️ un devis local pending ou conflict avec demande n\'est JAMAIS écrasé par le tirage (même facturé au serveur)', () async {
      await devis('a', synchro: SyncStatus.conflict, demande: DateTime(2026, 10, 21, 10));
      serveur.tirage = {
        'server_time': '2026-10-21T09:00:00Z',
        'quotes': [_json('a', statut: 'facture', facture: vente, numeroFacture: 'FV-2026-ABC123')],
      };

      await moteur.synchroniser();

      final d = await lire('a');
      expect([d.status, d.convertedSaleId, d.conversionRequestedAt != null], ['accepte', null, true]);
    });

    test('l\'ordre du serveur : la demande de conversion suit les devis', () {
      final ordre = SyncEngine.ordreDuServeur;
      expect(ordre.indexOf('quote_conversions'), ordre.indexOf('quotes') + 1);
    });

    test('⚠️ les lots : la demande part dans le lot du devis ou après lui, jamais avant ; les factures de chaque lot sont réunies', () {
      final envoi = <String, dynamic>{
        'device_id': 'poste-test',
        'quotes': [
          for (var i = 0; i < 60; i++) {'id': 'q$i'},
        ],
        'quote_conversions': [
          {'id': 'q0'},
          {'id': 'q59'},
        ],
      };

      final lots = SyncEngine.decouperEnLots(envoi);

      expect(lots.length, greaterThan(1));
      final dernierLotDeDevis = lots.lastIndexWhere((l) => l.containsKey('quotes'));
      final premierLotDeDemande = lots.indexWhere((l) => l.containsKey('quote_conversions'));
      expect(premierLotDeDemande, greaterThanOrEqualTo(lots.indexWhere((l) => (l['quotes'] as List?)?.any((q) => (q as Map)['id'] == 'q0') ?? false)));
      expect(lots[dernierLotDeDevis]['quotes'], contains(predicate((q) => q is Map && q['id'] == 'q59')));

      final fusion = <String, dynamic>{};
      SyncEngine.fusionnerReponse(fusion, {
        'quote_conversions': {'accepted': ['q0'], 'rejected': [], 'invoices': {'q0': {'sale_id': 's0', 'invoice_number': 'FV-2026-000000'}}},
      });
      SyncEngine.fusionnerReponse(fusion, {
        'quote_conversions': {'accepted': ['q59'], 'rejected': [], 'invoices': {'q59': {'sale_id': 's59', 'invoice_number': 'FV-2026-005959'}}},
      });
      expect((fusion['quote_conversions'] as Map)['accepted'], ['q0', 'q59']);
      expect(((fusion['quote_conversions'] as Map)['invoices'] as Map).keys, ['q0', 'q59']);
    });
  });

  // ── L'écran ────────────────────────────────────────────────────────────────────────────────────────────────────────

  group('écran — Convertir en Facture', () {
    var ouvertures = 0;

    void cas(String nom, Future<void> Function(WidgetTester tester) corps) => testWidgets(nom, (tester) async {
      await corps(tester);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle();
    });

    Future<void> afficher(
      WidgetTester tester, {
      bool peutGerer = true,
      bool peutConvertir = true,
      bool peutVoirFacturation = true,
    }) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ouvertures = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DevisOnglet(
              depot: depot,
              peutGerer: peutGerer,
              peutConvertir: peutConvertir,
              peutVoirFacturation: peutVoirFacturation,
              surVoirFacturation: () => ouvertures++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder cle(String action, String id) => find.byKey(Key('devis-$action-${_uuid(id)}'));

    cas('⚠️ le bouton « Convertir en Facture » : devis accepté ET manage-ventes ET manage-facturation, comme au web', (tester) async {
      await devis('a');
      await devis('e', statut: 'envoye', numero: 'DEV-2026-002');
      await afficher(tester);
      expect([cle('convertir', 'a'), cle('convertir', 'e')].map((f) => f.evaluate().length), [1, 0]);

      await afficher(tester, peutConvertir: false);
      expect(cle('convertir', 'a'), findsNothing, reason: 'sans manage-facturation (le caissier) : pas de bouton, comme au web');

      await afficher(tester, peutGerer: false);
      expect(cle('convertir', 'a'), findsNothing, reason: 'sans manage-ventes : pas de bouton');
    });

    cas('⚠️ au clic : la demande est écrite, toast de la demande, badge « Conversion demandée », le bouton disparaît', (tester) async {
      await devis('a');
      await afficher(tester);

      await tester.tap(cle('convertir', 'a'));
      await tester.pumpAndSettle();

      expect(find.text(DevisRepository.toastConversionDemandee), findsOneWidget);
      expect(find.text('Conversion demandée'), findsOneWidget);
      expect(cle('convertir', 'a'), findsNothing);
      final d = await lire('a');
      expect([d.status, d.syncStatus, d.conversionRequestedAt], ['accepte', SyncStatus.pending, DateTime(2026, 10, 21, 10)]);
      // Figé : modifier est refusé avec le motif de la demande.
      await tester.tap(cle('archiver', 'a'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('archivage-devis-confirmer')));
      await tester.pumpAndSettle();
      expect(find.text(DevisRepository.messageConversionDemandee), findsOneWidget);
    });

    cas('⚠️ un refus local (client archivé) : toast d\'erreur avec le motif du serveur, rien n\'est écrit', (tester) async {
      await devis('a');
      await (db.update(db.customers)..where((t) => t.id.equals(client))).write(const CustomersCompanion(isActive: Value(false)));
      await afficher(tester);

      await tester.tap(cle('convertir', 'a'));
      await tester.pumpAndSettle();

      expect(find.text('Le client « AMOUSSOU Régis » est archivé : réactivez-le avant de facturer ce devis.'), findsOneWidget);
      expect((await lire('a')).conversionRequestedAt, isNull);
    });

    cas('un devis facturé : badge « Facturé », numéro de facture sous le badge, « Voir la facture » (view-facturation) qui ouvre Facturation', (tester) async {
      await devis('f', statut: 'facture', facture: vente, numeroFacture: 'FV-2026-ABC123');
      await afficher(tester);

      expect(find.text('Facturé'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(Key('devis-facture-${_uuid('f')}'))).data, 'FV-2026-ABC123');
      expect(cle('convertir', 'f'), findsNothing);
      await tester.tap(cle('voir-facture', 'f'));
      await tester.pumpAndSettle();
      expect(ouvertures, 1);

      await afficher(tester, peutVoirFacturation: false);
      expect(cle('voir-facture', 'f'), findsNothing, reason: 'sans view-facturation : pas de lien');
    });

    cas('⚠️ une demande REFUSÉE : « Conversion refusée » + motif mot pour mot ; « Annuler la demande » libère le devis', (tester) async {
      const refus = 'Plan comptable incomplet : le compte 701 (Ventes de produits) est introuvable. Complétez le plan comptable puis relancez la conversion.';
      await devis('a', synchro: SyncStatus.conflict, demande: DateTime(2026, 10, 21, 10));
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'quote_conversions:${_uuid('a')}', sourceTable: 'quote_conversions', recordId: _uuid('a'), reason: refus, detectedAt: DateTime(2026, 10, 21),
        ),
      );
      await afficher(tester);

      expect(find.text('Conversion refusée'), findsOneWidget);
      expect(find.text(refus), findsOneWidget);

      await tester.tap(cle('annuler-conversion', 'a'));
      await tester.pumpAndSettle();

      expect(find.text(DevisRepository.toastConversionAnnulee), findsOneWidget);
      expect(find.text('Conversion refusée'), findsNothing);
      expect(cle('convertir', 'a'), findsOneWidget, reason: 'le devis est accepté et libre : on peut le convertir de nouveau');
    });
  });
}

Map<String, dynamic> _json(String cle, {String statut = 'accepte', String? facture, String? numeroFacture}) => {
  'id': _uuid(cle),
  'quote_number': 'DEV-2026-001',
  'customer_id': _uuid('client-amoussou'),
  'articles_description': '2 cages galvanisées',
  'amount': 150000,
  'tva_rate': 18,
  'validity_days': 15,
  'quote_date': '2026-10-20',
  'note': null,
  'status': statut,
  'is_active': true,
  'converted_sale_id': facture,
  'invoice_number': numeroFacture,
  'updated_at': '2026-10-20T10:00:00+01:00',
};
