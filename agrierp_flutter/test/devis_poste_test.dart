import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/document_officiel.dart';
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

/// Ticket DEV — « DEVIS & PROFORMA » AU POSTE (onglet « Devis Prestations » du hub Ventes & Devis).
///
/// Le maître est le web (`Livewire\Ventes\Devis`, `SaisieDevisAction`) ; le garde-fou de fidélité des libellés est
/// `devis_blade_test.dart`. Ici : le dépôt (CRUD, numéro absent, KPI, cycle de vie, exercice clos, messages du web),
/// le moteur de synchronisation (absorbeur STRICT, saisie jamais écrasée, envoi sans numéro, acquittement) et l'écran
/// (création, modification, statut, archivage, conversion, filtres, export).
///
/// Horloge figée au mercredi 21/10/2026 10:00 (heure du Bénin). Valeurs attendues écrites à la main.
const _clos = "L'exercice 2025 est clôturé : aucune saisie ne peut être datée du 20/12/2025.";

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

/// Serveur feint : sert [tirage], garde chaque envoi, l'acquitte ou le refuse ([refus] : id → motif).
class _Serveur extends Interceptor {
  Map<String, dynamic> tirage = {'server_time': '2026-10-21T09:00:00Z'};
  final Map<String, String> refus = {};
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
                  'accepted': [
                    for (final e in value)
                      if (e is Map && e['id'] is String && !refus.containsKey(e['id'])) e['id'],
                  ],
                  'rejected': [
                    for (final e in value)
                      if (e is Map && refus.containsKey(e['id'])) {'id': e['id'], 'reason': refus[e['id']]},
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

void main() {
  late AppDatabase db;
  late DevisRepository depot;

  final client = _uuid('client-amoussou');
  final autre = _uuid('client-kpadonou');

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

  Future<void> devisServeur(
    String cle, {
    String? numero = 'DEV-2026-001',
    String clientId = '',
    String description = '2 cages galvanisées 6 compartiments',
    double montant = 150000,
    double tva = 18,
    int validite = 15,
    DateTime? date,
    String statut = 'brouillon',
    bool actif = true,
    SyncStatus synchro = SyncStatus.synced,
    String? note,
  }) => db
      .into(db.quotes)
      .insert(
        QuotesCompanion.insert(
          id: _uuid(cle),
          deviceId: 'serveur',
          syncStatus: Value(synchro),
          updatedAt: DateTime(2026, 10, 20),
          quoteNumber: Value(numero),
          customerId: clientId.isEmpty ? client : clientId,
          articlesDescription: description,
          amount: montant,
          tvaRate: Value(tva),
          validityDays: Value(validite),
          quoteDate: date ?? DateTime(2026, 10, 20),
          note: Value(note),
          status: Value(statut),
          isActive: Value(actif),
        ),
      );

  Future<Quote> lire(String cle) => (db.select(db.quotes)..where((t) => t.id.equals(_uuid(cle)))).getSingle();

  Future<Map<String, String>> refus(Future<Object?> Function() geste) async {
    try {
      await geste();
    } on DevisRefuse catch (e) {
      return e.erreurs;
    }
    return const {};
  }

  Future<Quote> creer({
    String? clientId,
    String articles = '2 cages galvanisées 6 compartiments sur mesure',
    String montant = '150000',
    String tva = '18',
    String validite = '15',
    DateTime? date,
    String note = '',
  }) => depot.enregistrer(
    clientId: clientId ?? client,
    articles: articles,
    montant: montant,
    tva: tva,
    validite: validite,
    date: date ?? DateTime(2026, 10, 21),
    note: note,
  );

  setUp(() async {
    HeureBenin.horloge = () => DateTime.utc(2026, 10, 21, 9);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = DevisRepository(database: db, deviceId: 'poste-test');
    for (final (id, nom) in [(client, 'AMOUSSOU Régis'), (autre, 'KPADONOU Eric')]) {
      await db.into(db.customers).insert(CustomersCompanion.insert(id: id, name: nom));
    }
  });

  tearDown(() async {
    HeureBenin.reinitialiser();
    ToastAgri.toutRetirer();
    await db.close();
  });

  // ── Le dépôt : les règles du web, appliquées au poste ──────────────────────────────────────────────────────────────

  group('dépôt — création', () {
    test('un devis valide est enregistré en attente d envoi, brouillon, actif, SANS numéro', () async {
      final d = await creer();

      expect(d.id, hasLength(36));
      expect(d.syncStatus, SyncStatus.pending);
      expect(d.deviceId, 'poste-test');
      expect(d.quoteNumber, isNull, reason: 'le serveur l attribue : le poste ne l invente jamais');
      expect(d.status, 'brouillon');
      expect(d.isActive, isTrue);
      expect([d.amount, d.tvaRate, d.validityDays], [150000, 18, 15]);
      expect(d.quoteDate, DateTime(2026, 10, 21));
    });

    test('⚠️ chaque champ reçoit le message du web (`lang/fr/validation.php`, noms de champ du web)', () async {
      expect(
        await refus(() => depot.enregistrer(clientId: null, articles: '  ', montant: '', tva: '', validite: '', date: null)),
        {
          'client': 'Le champ client est obligatoire.',
          'articles': 'Le champ description des articles est obligatoire.',
          'montant': 'Le champ montant est obligatoire.',
          'tva': 'Le champ taux de TVA est obligatoire.',
          'validite': 'Le champ durée de validité (jours) est obligatoire.',
          'date': 'Le champ date du devis est obligatoire.',
        },
      );
      expect((await refus(() => creer(montant: 'cent')))['montant'], 'Le champ montant doit être un nombre.');
      expect((await refus(() => creer(montant: '-5')))['montant'], 'Le champ montant doit être au moins égal à 0.');
      expect((await refus(() => creer(tva: '101')))['tva'], 'Le champ taux de TVA ne doit pas dépasser 100.');
      expect((await refus(() => creer(validite: '1,5')))['validite'], 'Le champ durée de validité (jours) doit être un nombre entier.');
      expect((await refus(() => creer(validite: '0')))['validite'], 'Le champ durée de validité (jours) doit être au moins égal à 1.');
      expect(
        (await refus(() => creer(articles: 'x' * 2001)))['articles'],
        'Le champ description des articles ne doit pas dépasser 2000 caractères.',
      );
      expect(
        (await refus(() => creer(clientId: _uuid('inconnu'))))['client'],
        "La valeur sélectionnée pour le champ client n'existe pas.",
      );
      expect(await db.select(db.quotes).get(), isEmpty, reason: 'rien n est écrit sur un refus');
    });

    test('un montant de 0 est admis (`min:0`), la virgule décimale aussi', () async {
      expect((await creer(montant: '0')).amount, 0);
      expect((await creer(montant: '1250,5')).amount, 1250.5);
    });

    test('⚠️ un devis daté dans un exercice CLOS est refusé sous « Date du Devis », rien n est écrit', () async {
      await exercice(2025, 'cloture');
      await exercice(2026, 'ouvert');

      expect(await refus(() => creer(date: DateTime(2025, 12, 20))), {'date': _clos});
      expect(await db.select(db.quotes).get(), isEmpty);
      // Un exercice ouvert l'accepte.
      expect((await creer(date: DateTime(2026, 3, 1))).quoteDate, DateTime(2026, 3, 1));
    });

    test('aucun exercice connu au poste : aucun blocage (le serveur jugera)', () async {
      expect((await creer(date: DateTime(2025, 12, 20))).quoteDate, DateTime(2025, 12, 20));
    });
  });

  group('dépôt — modification', () {
    test('garde le numéro et le statut, repasse en attente, efface l ancien refus', () async {
      await devisServeur('d1', statut: 'envoye');
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'quotes:${_uuid('d1')}', sourceTable: 'quotes', recordId: _uuid('d1'), reason: 'ancien', detectedAt: DateTime(2026, 10, 20),
        ),
      );

      final d = await depot.enregistrer(
        clientId: autre,
        articles: 'Enclos',
        montant: '200000',
        tva: '0',
        validite: '30',
        date: DateTime(2026, 10, 20),
        note: 'Remise accordée',
        idEnModification: _uuid('d1'),
      );

      expect(d.quoteNumber, 'DEV-2026-001');
      expect(d.status, 'envoye');
      expect(d.syncStatus, SyncStatus.pending);
      expect([d.customerId, d.articlesDescription, d.amount, d.tvaRate, d.validityDays, d.note], [autre, 'Enclos', 200000, 0, 30, 'Remise accordée']);
      expect(await db.select(db.syncConflicts).get(), isEmpty);
    });

    test('une modification identique n écrit rien (le devis reste acquitté)', () async {
      await devisServeur('d1', montant: 150000, note: null);

      await depot.enregistrer(
        clientId: client,
        articles: '2 cages galvanisées 6 compartiments',
        montant: '150000',
        tva: '18',
        validite: '15',
        date: DateTime(2026, 10, 20),
        idEnModification: _uuid('d1'),
      );

      expect((await lire('d1')).syncStatus, SyncStatus.synced);
    });

    test('⚠️ un devis archivé ou facturé ne se modifie plus (messages du web, sous « devis »)', () async {
      await devisServeur('a1', actif: false, numero: 'DEV-2026-002');
      await devisServeur('f1', statut: 'facture', numero: 'DEV-2026-003');

      Future<Map<String, String>> modifier(String cle) => refus(
        () => depot.enregistrer(
          clientId: client, articles: 'x', montant: '1', tva: '0', validite: '1', date: DateTime(2026, 10, 20), idEnModification: _uuid(cle),
        ),
      );

      expect(await modifier('a1'), {'devis': 'Ce devis est archivé : il ne peut plus être modifié.'});
      expect(await modifier('f1'), {'devis': 'Ce devis est facturé : il ne peut plus être modifié.'});
      expect((await lire('f1')).amount, 150000);
    });

    test('⚠️ le devis d un exercice clos est en lecture seule, et ne passe pas dans un exercice clos', () async {
      await exercice(2025, 'cloture');
      await exercice(2026, 'ouvert');
      await devisServeur('vieux', date: DateTime(2025, 12, 20), numero: 'DEV-2025-001');
      await devisServeur('recent', numero: 'DEV-2026-004');

      Future<Map<String, String>> modifier(String cle, DateTime date) => refus(
        () => depot.enregistrer(
          clientId: client, articles: 'x', montant: '2', tva: '0', validite: '1', date: date, idEnModification: _uuid(cle),
        ),
      );

      expect(await modifier('vieux', DateTime(2025, 12, 20)), {'date': _clos});
      expect(await modifier('recent', DateTime(2025, 12, 20)), {'date': _clos});
      expect((await lire('vieux')).amount, 150000);
    });
  });

  group('dépôt — cycle de vie et archivage', () {
    test('brouillon → envoyé → accepté : un pas à la fois, en attente d envoi', () async {
      await devisServeur('d1');

      expect(await depot.changerStatut(_uuid('d1'), 'envoye'), isTrue);
      expect((await lire('d1')).status, 'envoye');
      expect((await lire('d1')).syncStatus, SyncStatus.pending);
      expect(await depot.changerStatut(_uuid('d1'), 'accepte'), isTrue);
      expect((await lire('d1')).status, 'accepte');
    });

    test('un devis envoyé peut être refusé', () async {
      await devisServeur('d1', statut: 'envoye');
      await depot.changerStatut(_uuid('d1'), 'refuse');
      expect((await lire('d1')).status, 'refuse');
    });

    test('⚠️ un changement de statut interdit est refusé avec le motif du web, rien n est écrit', () async {
      await devisServeur('b', statut: 'brouillon', numero: 'DEV-2026-005');
      await devisServeur('a', statut: 'accepte', numero: 'DEV-2026-006');

      expect(
        await refus(() => depot.changerStatut(_uuid('b'), 'accepte')),
        {'devis': 'Changement de statut interdit : un devis « Brouillon » ne peut pas passer à « Accepté ».'},
      );
      expect(
        await refus(() => depot.changerStatut(_uuid('a'), 'refuse')),
        {'devis': 'Changement de statut interdit : un devis « Accepté » ne peut pas passer à « Refusé ».'},
      );
      expect(
        await refus(() => depot.changerStatut(_uuid('a'), 'envoye')),
        {'devis': 'Changement de statut interdit : un devis « Accepté » ne peut pas passer à « Envoyé ».'},
      );
      expect(
        await refus(() => depot.changerStatut(_uuid('a'), 'facture')),
        {'devis': 'Changement de statut interdit : un devis « Accepté » ne peut pas passer à « Facturé ».'},
      );
      expect([(await lire('b')).status, (await lire('a')).status], ['brouillon', 'accepte']);
      expect([(await lire('b')).syncStatus, (await lire('a')).syncStatus], [SyncStatus.synced, SyncStatus.synced]);
    });

    test('le même statut redemandé ne fait rien', () async {
      await devisServeur('d1', statut: 'envoye');

      expect(await depot.changerStatut(_uuid('d1'), 'envoye'), isFalse);
      expect((await lire('d1')).syncStatus, SyncStatus.synced);
    });

    test('⚠️ un devis d un exercice clos ne change plus de statut ni ne s archive', () async {
      await exercice(2025, 'cloture');
      await devisServeur('vieux', date: DateTime(2025, 12, 20));

      expect(await refus(() => depot.changerStatut(_uuid('vieux'), 'envoye')), {'devis': _clos});
      expect(await refus(() => depot.archiver(_uuid('vieux'))), {'devis': _clos});
      expect(((await lire('vieux')).status, (await lire('vieux')).isActive), ('brouillon', true));
    });

    test('archiver est logique, part à l envoi ; un second archivage ne fait rien', () async {
      await devisServeur('d1');

      expect(await depot.archiver(_uuid('d1')), isTrue);
      final d = await lire('d1');
      expect([d.isActive, d.syncStatus], [false, SyncStatus.pending]);
      expect(await depot.archiver(_uuid('d1')), isFalse);
      expect(await db.select(db.quotes).get(), hasLength(1), reason: 'la ligne est gardée');
    });

    test('un devis archivé ne change plus de statut (message du web)', () async {
      await devisServeur('d1', actif: false);
      expect(await refus(() => depot.changerStatut(_uuid('d1'), 'envoye')), {'devis': DevisRepository.messageArchive});
    });
  });

  group('dépôt — liste, filtres et KPI', () {
    Future<void> jeu() async {
      await devisServeur('b', numero: 'DEV-2026-001', statut: 'brouillon', montant: 1000, date: DateTime(2026, 10, 18));
      await devisServeur('e', numero: 'DEV-2026-002', statut: 'envoye', montant: 2000, clientId: autre, date: DateTime(2026, 10, 19));
      await devisServeur('a', numero: 'DEV-2026-003', statut: 'accepte', montant: 3000, date: DateTime(2026, 10, 20));
      await devisServeur('r', numero: 'DEV-2026-004', statut: 'refuse', montant: 500, date: DateTime(2026, 10, 17));
      await devisServeur('arch', numero: 'DEV-2026-005', statut: 'accepte', montant: 9999, actif: false);
      await devisServeur('sept', numero: 'DEV-2026-006', statut: 'accepte', montant: 7777, date: DateTime(2026, 9, 30));
    }

    test('⚠️ les quatre KPI sont ceux du web (calculés à la main)', () async {
      await jeu();

      final k = (await depot.charger()).kpis;

      // Actifs brouillon + envoyé + accepté : 1000 + 2000 + 3000 + 7777 = 13 777 (4 devis) ; octobre : 1 accepté et 1 refusé
      // → 1 / 2 = 50 % ; envoyés : 1.
      expect([k.devisActifs, k.valeurTotale, k.tauxConversion, k.enAttenteDeRelance], [4, 13777, 50, 1]);
    });

    test('sans devis : 0 devis, 0 FCFA, 0 %, 0 relance', () async {
      final k = (await depot.charger()).kpis;
      expect([k.devisActifs, k.valeurTotale, k.tauxConversion, k.enAttenteDeRelance], [0, 0, 0, 0]);
    });

    test('le taux est arrondi comme PHP : 2 acceptés sur 3 jugés = 67 %', () async {
      await devisServeur('a1', statut: 'accepte');
      await devisServeur('a2', statut: 'accepte', numero: 'DEV-2026-002');
      await devisServeur('r1', statut: 'refuse', numero: 'DEV-2026-003');
      expect((await depot.charger()).kpis.tauxConversion, 67);
    });

    test('la liste : actifs seulement, par date décroissante ; client inconnu = « — » côté écran', () async {
      await jeu();

      final lignes = (await depot.charger()).lignes;

      expect([for (final l in lignes) l.devis.quoteNumber], ['DEV-2026-003', 'DEV-2026-002', 'DEV-2026-001', 'DEV-2026-004', 'DEV-2026-006']);
      expect(lignes.first.client, 'AMOUSSOU Régis');
      expect(lignes.first.valideJusqua, DateTime(2026, 11, 4), reason: '20/10/2026 + 15 jours');
    });

    test('filtres : statut, client, recherche (n° ou client, sans casse ni accents ; « 0 » ne filtre pas)', () async {
      await jeu();
      Future<List<String?>> numeros({String recherche = '', String statut = '', String clientId = ''}) async => [
        for (final l in (await depot.charger(recherche: recherche, statut: statut, clientId: clientId)).lignes) l.devis.quoteNumber,
      ];

      expect(await numeros(statut: 'envoye'), ['DEV-2026-002']);
      expect(await numeros(clientId: autre), ['DEV-2026-002']);
      expect(await numeros(recherche: 'kpado'), ['DEV-2026-002']);
      expect(await numeros(recherche: 'dev-2026-001'), ['DEV-2026-001']);
      expect(await numeros(recherche: 'AMOUSSOU'), hasLength(4));
      expect(await numeros(recherche: '0'), hasLength(5), reason: '`when("0")` est faux au web : pas de filtre');
      expect(await numeros(recherche: 'zzz'), isEmpty);
    });

    test('une saisie refusée reste listée avec son motif, mais ne compte pas aux KPI', () async {
      await devisServeur('c1', synchro: SyncStatus.conflict, actif: false, montant: 5000);
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'quotes:${_uuid('c1')}', sourceTable: 'quotes', recordId: _uuid('c1'), reason: 'Refus du serveur', detectedAt: DateTime(2026, 10, 21),
        ),
      );

      final d = await depot.charger();

      expect(d.lignes.single.motifRefus, 'Refus du serveur');
      expect(d.kpis.devisActifs, 0);
      expect(d.kpis.valeurTotale, 0);
    });

    test('les clients proposés sont les actifs, par nom', () async {
      await db.into(db.customers).insert(CustomersCompanion.insert(id: _uuid('archive'), name: 'ABOKI', isActive: const Value(false)));
      expect([for (final c in (await depot.charger()).clients) c.name], ['AMOUSSOU Régis', 'KPADONOU Eric']);
    });
  });

  group('document « Exporter »', () {
    test('mêmes colonnes, titre, sous-titre et nom de fichier que le PDF du web', () async {
      await devisServeur('b', numero: 'DEV-2026-001', montant: 1234567);
      await devisServeur('p', numero: null, synchro: SyncStatus.pending, statut: 'envoye');

      final doc = DevisRepository.documentPdf((await depot.charger()).lignes, DateTime(2026, 10, 21));

      expect(doc.titre, 'Devis & Proforma');
      expect(doc.sousTitre, 'État au 21/10/2026');
      expect(doc.entetes, ['N° Devis', 'Client', 'Date', 'Montant', 'Statut']);
      expect(DocumentOfficiel.nomPdf(doc, DateTime(2026, 10, 21)), 'devis-2026-10-21.pdf');
      final lignes = [for (final l in doc.lignes) (l as DonneesDocument).cellules];
      expect(lignes, [
        ['DEV-2026-001', 'AMOUSSOU Régis', '20/10/2026', '1 234 567 FCFA', 'Brouillon'],
        ['—', 'AMOUSSOU Régis', '20/10/2026', '150 000 FCFA', 'Envoyé'],
      ]);
      expect(doc.noteDePied, contains('1 devis saisi(s) sur ce poste'));
    });

    test('aucun devis : la ligne du web « Aucun devis ne correspond aux filtres actifs. »', () {
      final doc = DevisRepository.documentPdf(const [], DateTime(2026, 10, 21));
      expect((doc.lignes.single as DonneesDocument).cellules.first, 'Aucun devis ne correspond aux filtres actifs.');
    });
  });

  // ── Le moteur de synchronisation ───────────────────────────────────────────────────────────────────────────────────

  group('synchronisation', () {
    late _Serveur serveur;
    late SyncEngine moteur;

    Map<String, dynamic> json(
      String cle, {
      Object? id,
      Object? numero = 'DEV-2026-001',
      Object? client,
      Object? description = '2 cages galvanisées',
      Object? montant = 150000,
      Object? tva = 18,
      Object? validite = 15,
      Object? date = '2026-10-20',
      Object? note,
      Object? statut = 'brouillon',
      Object? actif = true,
    }) => {
      'id': id ?? _uuid(cle),
      'quote_number': numero,
      'customer_id': client ?? autre,
      'articles_description': description,
      'amount': montant,
      'tva_rate': tva,
      'validity_days': validite,
      'quote_date': date,
      'note': note,
      'status': statut,
      'is_active': actif,
      'updated_at': '2026-10-20T10:00:00+01:00',
    };

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

    test('un devis du web descend avec son numéro, sa date au jour métier, acquitté', () async {
      serveur.tirage = {
        'server_time': '2026-10-21T09:00:00Z',
        'quotes': [json('w1', note: 'Remise accordée', statut: 'envoye')],
      };

      await moteur.synchroniser();

      final d = await lire('w1');
      expect(
        [d.quoteNumber, d.customerId, d.articlesDescription, d.amount, d.tvaRate, d.validityDays, d.quoteDate, d.note, d.status, d.isActive, d.syncStatus, d.deviceId],
        ['DEV-2026-001', autre, '2 cages galvanisées', 150000, 18, 15, DateTime(2026, 10, 20), 'Remise accordée', 'envoye', true, SyncStatus.synced, 'serveur'],
      );
    });

    test('un devis archivé au web descend archivé ; la mise à jour d un devis acquitté garde son device_id', () async {
      await devisServeur('p1', numero: null, statut: 'brouillon', note: null);
      await (db.update(db.quotes)..where((t) => t.id.equals(_uuid('p1')))).write(const QuotesCompanion(deviceId: Value('poste-origine')));
      serveur.tirage = {
        'server_time': '2026-10-21T09:00:00Z',
        'quotes': [json('p1', numero: 'DEV-2026-007', actif: false, statut: 'accepte')],
      };

      await moteur.synchroniser();

      final d = await lire('p1');
      expect([d.quoteNumber, d.isActive, d.status, d.deviceId], ['DEV-2026-007', false, 'accepte', 'poste-origine']);
    });

    for (final statut in [SyncStatus.pending, SyncStatus.conflict]) {
      test('⚠️⚠️ un devis local ${statut.name} n est JAMAIS écrasé par le tirage', () async {
        await devisServeur('l1', numero: null, montant: 9000, synchro: statut, statut: 'envoye');
        serveur.tirage = {
          'server_time': '2026-10-21T09:00:00Z',
          'quotes': [json('l1', montant: 1, actif: false, statut: 'refuse')],
        };

        await moteur.synchroniser();

        final d = await lire('l1');
        expect([d.amount, d.isActive, d.status, d.quoteNumber], [9000, true, 'envoye', null]);
      });
    }

    test('clé absente (compte sans view-ventes, serveur antérieur) : rien n est touché', () async {
      await devisServeur('p1');
      await moteur.synchroniser();
      expect(await db.select(db.quotes).get(), hasLength(1));
    });

    for (final (cas, fautif) in <(String, Map<String, dynamic>)>[
      ('identifiant invalide', json('x', id: 'court')),
      ('servi deux fois', json('w1')),
      ('date illisible', json('w2', date: 'hier')),
      ('date absente', json('w2', date: null)),
      ('numéro qui n est pas un texte', json('w2', numero: 42)),
      ('client absent', json('w2', client: '')),
      ('description absente', json('w2', description: null)),
      ('montant absent', json('w2', montant: null)),
      ('montant illisible', json('w2', montant: 'cent')),
      ('montant négatif', json('w2', montant: -5)),
      ('TVA hors de 0 à 100', json('w2', tva: 120)),
      ('validité nulle', json('w2', validite: 0)),
      ('validité fractionnaire', json('w2', validite: 1.5)),
      ('statut inconnu', json('w2', statut: 'annule')),
      ('statut absent', json('w2', statut: null)),
      ('archivage illisible', json('w2', actif: 'peut-être')),
    ]) {
      test('⚠️⚠️ STRICT — $cas : toute la page est refusée, rien n est écrit, le curseur ne bouge pas', () async {
        await db.noterEtatDeSynchronisation(tire: DateTime.utc(2026, 10, 1));
        final curseur = (await db.etatDeSynchronisation())?.lastPulledAt;
        serveur.tirage = {
          'server_time': '2026-10-21T09:00:00Z',
          'quotes': [json('w1'), fautif],
        };

        await expectLater(moteur.synchroniser(), throwsA(isA<FormatException>()));

        expect(await db.select(db.quotes).get(), isEmpty);
        expect((await db.etatDeSynchronisation())?.lastPulledAt, curseur);
      });
    }

    test('⚠️ l envoi porte le devis SANS numéro, avec ses champs, son statut et son archivage ; acquitté il devient synced', () async {
      final d = await creer(note: 'Remise accordée');
      await depot.changerStatut(d.id, 'envoye');

      await moteur.synchroniser();

      final envoi = (serveur.envois.single['quotes'] as List).single as Map<String, dynamic>;
      expect(envoi.containsKey('quote_number'), isFalse, reason: 'le serveur attribue le numéro');
      expect(envoi, {
        'id': d.id,
        'customer_id': client,
        'articles_description': '2 cages galvanisées 6 compartiments sur mesure',
        'amount': 150000.0,
        'tva_rate': 18.0,
        'validity_days': 15,
        'quote_date': '2026-10-21',
        'note': 'Remise accordée',
        'status': 'envoye',
        'is_active': true,
        'device_id': 'poste-test',
      });
      expect((await (db.select(db.quotes)..where((t) => t.id.equals(d.id))).getSingle()).syncStatus, SyncStatus.synced);
    });

    test('un devis archivé au poste part avec is_active=false', () async {
      await devisServeur('d1', numero: 'DEV-2026-001');
      await depot.archiver(_uuid('d1'));

      await moteur.synchroniser();

      expect(((serveur.envois.single['quotes'] as List).single as Map)['is_active'], false);
    });

    test('⚠️ un devis refusé par le serveur passe en conflit avec le motif, mot pour mot, et se relance', () async {
      final d = await creer();
      serveur.refus[d.id] = "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 21/10/2026.";

      await moteur.synchroniser();

      final apres = await (db.select(db.quotes)..where((t) => t.id.equals(d.id))).getSingle();
      expect(apres.syncStatus, SyncStatus.conflict);
      final lignes = (await depot.charger()).lignes;
      expect(lignes.single.motifRefus, "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 21/10/2026.");

      final conflit = (await db.select(db.syncConflicts).get()).single;
      await moteur.relancer(conflit);
      expect((await (db.select(db.quotes)..where((t) => t.id.equals(d.id))).getSingle()).syncStatus, SyncStatus.pending);
    });

    test('⚠️ un devis modifié PENDANT l envoi de sa version précédente reste pending et repart', () async {
      final d = await creer();
      // La saisie continue pendant l'envoi : à l'accusé, le devis n'est plus celui qui est parti.
      final autreMoteur = SyncEngine(
        database: db,
        client: Dio()..interceptors.add(_ServeurModifiant(db, d.id)),
        deviceId: 'poste-test',
        connectivity: _Connectivite(),
        maintenant: () => DateTime(2026, 10, 21, 10),
      );

      await autreMoteur.synchroniser();

      final apres = await (db.select(db.quotes)..where((t) => t.id.equals(d.id))).getSingle();
      expect([apres.syncStatus, apres.amount], [SyncStatus.pending, 1]);
    });

    test('le compteur « en attente » compte les devis', () async {
      await creer();
      expect(await db.pendingCount(), 1);
    });
  });

  // ── L'écran ────────────────────────────────────────────────────────────────────────────────────────────────────────

  group('écran « Devis & Proforma »', () {
    final espion = <(DocumentOfficiel, DateTime)>[];

    /// `testWidgets` qui retire les toasts à la fin (leur minuterie de 3,5 s ne doit pas survivre à l'arbre).
    void cas(String nom, Future<void> Function(WidgetTester tester) corps) => testWidgets(nom, (tester) async {
      await corps(tester);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle();
    });

    Future<void> afficher(WidgetTester tester, {bool peutGerer = true, bool peutExporter = true}) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      espion.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DevisOnglet(
              depot: depot,
              peutGerer: peutGerer,
              peutExporter: peutExporter,
              imprimer: (document, maintenant) async {
                espion.add((document, maintenant));
                return null;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    cas('sans devis : l état vide du web et des KPI à 0', (tester) async {
      await afficher(tester);

      expect(find.text('Devis & Proforma'), findsOneWidget);
      // Les deux boutons de l'en-tête portent le libellé du Blade (et non, ailleurs, le titre de la modale).
      expect(find.descendant(of: find.byKey(const Key('devis-nouveau')), matching: find.text('Nouveau Devis')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('devis-exporter')), matching: find.text('Exporter')), findsOneWidget);
      expect(find.byKey(const Key('devis-vide')), findsOneWidget);
      expect(find.text('Aucun devis pour le moment.'), findsOneWidget);
      expect(find.text('0 FCFA'), findsOneWidget);
      expect(find.text('0 %'), findsOneWidget);
    });

    cas('⚠️ créer un devis : modale, champs, toast du web, ligne SANS numéro (« — »), « À envoyer »', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('devis-nouveau')));
      await tester.pumpAndSettle();
      expect(find.text('Nouveau Devis'), findsWidgets);
      await tester.enterText(find.byKey(const Key('devis-articles')), '2 cages galvanisées 6 compartiments sur mesure');
      await tester.enterText(find.byKey(const Key('devis-montant')), '150000');
      await tester.tap(find.byKey(const Key('devis-liste-client')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AMOUSSOU Régis').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('devis-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.text('Devis créé avec succès.'), findsOneWidget);
      final d = (await db.select(db.quotes).get()).single;
      expect([d.status, d.amount, d.tvaRate, d.validityDays], ['brouillon', 150000, 18, 15]);
      expect(find.text('—'), findsWidgets);
      expect(find.byKey(Key('devis-etat-${d.id}')), findsOneWidget);
      expect(find.text('150 000 FCFA'), findsWidgets);
      // KPI : 1 devis actif, 150 000 FCFA.
      expect(find.text('1'), findsWidgets);
    });

    cas('⚠️ un formulaire vide montre chaque erreur sous son champ, avec les messages du web', (tester) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('devis-nouveau')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('devis-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('devis-erreur-client')), findsOneWidget);
      expect(find.text('Le champ client est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ description des articles est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ montant est obligatoire.'), findsOneWidget);
      expect(await db.select(db.quotes).get(), isEmpty);
    });

    cas('⚠️ un exercice clos : le motif R4 sous « Date du Devis », la modale reste ouverte', (tester) async {
      await exercice(2025, 'cloture');
      // Le jour du poste est le 20/12/2025 : la date proposée par défaut tombe dans l'exercice clos.
      HeureBenin.horloge = () => DateTime.utc(2025, 12, 20, 9);
      await afficher(tester);

      await tester.tap(find.byKey(const Key('devis-nouveau')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('devis-articles')), 'Cages');
      await tester.enterText(find.byKey(const Key('devis-montant')), '1000');
      await tester.tap(find.byKey(const Key('devis-liste-client')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AMOUSSOU Régis').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('devis-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('devis-erreur-date')), findsOneWidget);
      expect(find.text(_clos), findsOneWidget);
      expect(await db.select(db.quotes).get(), isEmpty);
    });

    cas('modifier un devis : « Modifier le Devis », champs remplis, toast du web, numéro gardé', (tester) async {
      await devisServeur('d1', statut: 'envoye');
      await afficher(tester);

      await tester.tap(find.byKey(Key('devis-modifier-${_uuid('d1')}')));
      await tester.pumpAndSettle();
      expect(find.text('Modifier le Devis'), findsWidgets);
      expect(tester.widget<TextField>(find.byKey(const Key('devis-montant'))).controller!.text, '150000');
      await tester.enterText(find.byKey(const Key('devis-montant')), '200000');
      await tester.tap(find.byKey(const Key('devis-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.text('Devis modifié avec succès.'), findsOneWidget);
      final d = await lire('d1');
      expect([d.quoteNumber, d.status, d.amount], ['DEV-2026-001', 'envoye', 200000]);
      expect(find.text('200 000 FCFA'), findsWidgets);
    });

    cas('⚠️ les icônes d action suivent le statut : brouillon → envoyer ; envoyé → accepter/refuser ; accepté → convertir', (tester) async {
      await devisServeur('b', numero: 'DEV-2026-001', statut: 'brouillon', date: DateTime(2026, 10, 20));
      await devisServeur('e', numero: 'DEV-2026-002', statut: 'envoye', date: DateTime(2026, 10, 19));
      await devisServeur('a', numero: 'DEV-2026-003', statut: 'accepte', date: DateTime(2026, 10, 18));
      await devisServeur('r', numero: 'DEV-2026-004', statut: 'refuse', date: DateTime(2026, 10, 17));
      await afficher(tester);

      Finder cle(String action, String id) => find.byKey(Key('devis-$action-${_uuid(id)}'));
      expect([cle('envoyer', 'b'), cle('accepter', 'b'), cle('refuser', 'b'), cle('convertir', 'b')].map((f) => f.evaluate().length), [1, 0, 0, 0]);
      expect([cle('envoyer', 'e'), cle('accepter', 'e'), cle('refuser', 'e'), cle('convertir', 'e')].map((f) => f.evaluate().length), [0, 1, 1, 0]);
      expect([cle('envoyer', 'a'), cle('accepter', 'a'), cle('refuser', 'a'), cle('convertir', 'a')].map((f) => f.evaluate().length), [0, 0, 0, 1]);
      expect([cle('envoyer', 'r'), cle('accepter', 'r'), cle('refuser', 'r'), cle('convertir', 'r')].map((f) => f.evaluate().length), [0, 0, 0, 0]);
      for (final id in ['b', 'e', 'a', 'r']) {
        expect(cle('modifier', id), findsOneWidget);
        expect(cle('archiver', id), findsOneWidget);
      }
    });

    cas('le cycle : envoyer → toast, accepter → toast, refuser → toast d avertissement', (tester) async {
      await devisServeur('b', numero: 'DEV-2026-001', statut: 'brouillon', date: DateTime(2026, 10, 20));
      await devisServeur('e', numero: 'DEV-2026-002', statut: 'envoye', date: DateTime(2026, 10, 19));
      await afficher(tester);

      await tester.tap(find.byKey(Key('devis-envoyer-${_uuid('b')}')));
      await tester.pumpAndSettle();
      expect(find.text('Devis marqué comme envoyé.'), findsOneWidget);
      expect((await lire('b')).status, 'envoye');
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('devis-accepter-${_uuid('e')}')));
      await tester.pumpAndSettle();
      expect(find.text('Devis marqué comme accepté.'), findsOneWidget);
      expect((await lire('e')).status, 'accepte');
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('devis-refuser-${_uuid('b')}')));
      await tester.pumpAndSettle();
      expect(find.text('Devis marqué comme refusé.'), findsOneWidget);
      expect((await lire('b')).status, 'refuse');
    });

    cas('⚠️ convertir en facture : le message d attente du web, le statut ne change pas', (tester) async {
      await devisServeur('a', statut: 'accepte');
      await afficher(tester);

      await tester.tap(find.byKey(Key('devis-convertir-${_uuid('a')}')));
      await tester.pumpAndSettle();

      expect(find.text('La conversion en facture réelle arrive avec le module Facturation (Sprint 7).'), findsOneWidget);
      expect((await lire('a')).status, 'accepte');
    });

    cas('⚠️ archiver : confirmation « Confirmer l archivage », toast d avertissement, ligne retirée de la liste', (tester) async {
      await devisServeur('d1');
      await afficher(tester);

      await tester.tap(find.byKey(Key('devis-archiver-${_uuid('d1')}')));
      await tester.pumpAndSettle();
      expect(find.text("Confirmer l'archivage"), findsOneWidget);
      expect(find.textContaining('DEV-2026-001 sera marqué(e) comme archivé(e) (statut inactif).'), findsOneWidget);
      await tester.tap(find.byKey(const Key('archivage-devis-confirmer')));
      await tester.pumpAndSettle();

      expect(find.text('Devis archivé avec succès.'), findsOneWidget);
      expect((await lire('d1')).isActive, isFalse);
      expect(find.byKey(const Key('devis-vide')), findsOneWidget);
    });

    cas('annuler l archivage ne change rien', (tester) async {
      await devisServeur('d1');
      await afficher(tester);

      await tester.tap(find.byKey(Key('devis-archiver-${_uuid('d1')}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect((await lire('d1')).isActive, isTrue);
    });

    cas('les filtres « Statut : Tous » et « Client : Tous » et la recherche (300 ms)', (tester) async {
      await devisServeur('b', numero: 'DEV-2026-001', statut: 'brouillon', date: DateTime(2026, 10, 20));
      await devisServeur('e', numero: 'DEV-2026-002', statut: 'envoye', clientId: autre, date: DateTime(2026, 10, 19));
      await afficher(tester);
      expect(find.byKey(const Key('devis-ligne-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('devis-filtre-statut')));
      await tester.pumpAndSettle();
      expect(find.text('Statut : Tous'), findsWidgets);
      await tester.tap(find.text('Envoyé').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('devis-ligne-1')), findsNothing);
      expect(find.text('DEV-2026-002'), findsOneWidget);

      await tester.tap(find.byKey(const Key('devis-filtre-statut')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Statut : Tous').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('devis-filtre-client')));
      await tester.pumpAndSettle();
      expect(find.text('Client : Tous'), findsWidgets);
      await tester.tap(find.text('AMOUSSOU Régis').last);
      await tester.pumpAndSettle();
      expect(find.text('DEV-2026-001'), findsOneWidget);
      expect(find.text('DEV-2026-002'), findsNothing);

      await tester.enterText(find.byKey(const Key('devis-recherche')), 'zzz');
      await tester.pump(DevisOnglet.delaiRecherche + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('devis-vide')), findsOneWidget);
    });

    cas('« Exporter » édite le document des devis AFFICHÉS', (tester) async {
      await devisServeur('b', numero: 'DEV-2026-001');
      await afficher(tester);

      await tester.tap(find.byKey(const Key('devis-exporter')));
      await tester.pumpAndSettle();

      expect(espion, hasLength(1));
      expect(espion.single.$1.titre, 'Devis & Proforma');
      expect((espion.single.$1.lignes.single as DonneesDocument).cellules.first, 'DEV-2026-001');
    });

    cas('⚠️ droits : sans manage-ventes ni export-ventes, ni « Nouveau Devis », ni écriture, ni « Exporter »', (tester) async {
      await devisServeur('e', statut: 'envoye');
      await afficher(tester, peutGerer: false, peutExporter: false);

      expect(find.byKey(const Key('devis-nouveau')), findsNothing);
      expect(find.byKey(const Key('devis-exporter')), findsNothing);
      for (final action in ['envoyer', 'accepter', 'refuser', 'modifier', 'archiver']) {
        expect(find.byKey(Key('devis-$action-${_uuid('e')}')), findsNothing, reason: action);
      }
      expect(find.text('DEV-2026-001'), findsOneWidget, reason: 'la lecture reste ouverte');
    });

    cas('un refus du dépôt sur un changement de statut est un toast d erreur, comme au web', (tester) async {
      await exercice(2025, 'cloture');
      await devisServeur('vieux', date: DateTime(2025, 12, 20));
      await afficher(tester);

      await tester.tap(find.byKey(Key('devis-envoyer-${_uuid('vieux')}')));
      await tester.pumpAndSettle();

      expect(find.text(_clos), findsOneWidget);
      expect((await lire('vieux')).status, 'brouillon');
    });
  });
}

/// Serveur feint qui, à la réception d'un envoi, MODIFIE le devis parti (la saisie continue pendant l'envoi) puis
/// l'acquitte : la version partie n'est plus celle du poste.
class _ServeurModifiant extends Interceptor {
  _ServeurModifiant(this.db, this.id);

  final AppDatabase db;
  final String id;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.path.contains('push')) {
      await (db.update(db.quotes)..where((t) => t.id.equals(id))).write(
        QuotesCompanion(updatedAt: Value(DateTime(2030)), amount: const Value(1)),
      );
      final corps = options.data as Map<String, dynamic>;
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            for (final MapEntry(:key, :value) in corps.entries)
              if (value is List)
                key: {
                  'accepted': [for (final e in value) if (e is Map) e['id']],
                  'rejected': [],
                },
          },
        ),
      );
      return;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: {'server_time': '2026-10-21T09:00:00Z'}),
    );
  }
}
