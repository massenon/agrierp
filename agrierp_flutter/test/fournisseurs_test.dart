import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_screen.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Serveur de synchronisation feint : sert un tirage vide, note les envois.
class _ServeurSync extends Interceptor {
  _ServeurSync(this.reponsePush, {this.tirageExtra = const {}});

  final Map<String, dynamic> reponsePush;
  final Map<String, dynamic> tirageExtra;
  final List<Map<String, dynamic>> envois = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final push = options.path.contains('push');
    if (push) envois.add(Map<String, dynamic>.from(options.data as Map));
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: push
            ? reponsePush
            : {
                'server_time': '2026-10-08T12:00:00.000Z',
                'product_categories': <dynamic>[],
                'products': <dynamic>[],
                'livestock_lots': <dynamic>[],
                ...tirageExtra,
              },
      ),
    );
  }
}

class _ConnectiviteFeinte implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// Ticket F0.46 — HUB FOURNISSEURS (`fournisseurs.html`).
///
/// ⚠️⚠️ **LES DEUX TABLES SONT EN LECTURE SEULE, POUR DEUX RAISONS
/// DIFFÉRENTES.** `suppliers` est un référentiel : une fiche créée au poste
/// serait effacée au tirage suivant. Une dette se solde par un RÈGLEMENT, qui
/// décaisse un compte et passe une écriture SYSCOHADA — deux effets que le
/// poste ne sait pas rejouer.
void main() {
  late AppDatabase db;
  late FournisseursRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final aujourdhui = HeureBenin.maintenant();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FournisseursRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> fournisseur(
    String cle,
    String nom, {
    String? categorie,
    String? tel,
  }) => db
      .into(db.suppliers)
      .insert(
        SuppliersCompanion.insert(
          id: uuid(cle),
          name: nom,
          category: Value(categorie),
          phone: Value(tel),
        ),
      );

  Future<void> achat(
    String cle, {
    required String cleFournisseur,
    required double total,
    DateTime? date,
    bool enAttente = false,
  }) => db
      .into(db.purchases)
      .insert(
        PurchasesCompanion.insert(
          id: uuid(cle),
          deviceId: enAttente ? 'poste-test' : 'serveur',
          updatedAt: date ?? aujourdhui,
          syncStatus: Value(enAttente ? SyncStatus.pending : SyncStatus.synced),
          supplierId: uuid(cleFournisseur),
          paymentMode: 'especes',
          total: total,
          purchaseDate: date ?? aujourdhui,
        ),
      );

  Future<void> dette(
    String cle, {
    required String cleFournisseur,
    required double montant,
    double regle = 0,
    int? echeanceIlYA,
    String nom = 'Quincaillerie ADJOVI',
  }) => db
      .into(db.payables)
      .insert(
        PayablesCompanion.insert(
          id: uuid(cle),
          supplierId: uuid(cleFournisseur),
          supplierName: Value(nom),
          amount: montant,
          amountPaid: Value(regle),
          dueDate: Value(
            echeanceIlYA == null
                ? null
                : DateTime(
                    aujourdhui.year,
                    aujourdhui.month,
                    aujourdhui.day - echeanceIlYA,
                  ),
          ),
          status: const Value('en_cours'),
        ),
      );

  Future<void> compte(String cle, String libelle) => db
      .into(db.treasuryAccounts)
      .insert(TreasuryAccountsCompanion.insert(id: uuid(cle), label: libelle));

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(home: FournisseursScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-fournisseurs-$onglet')));
    await tester.pumpAndSettle();
  }

  group('règlement', () {
    test(
      '⚠️ enregistré en attente, sans toucher ni dette ni trésorerie',
      () async {
        await fournisseur('f1', 'Quincaillerie ADJOVI');
        await dette('d1', cleFournisseur: 'f1', montant: 100000);
        await compte('c1', 'Caisse Physique');
        await db
            .into(db.treasuryAccounts)
            .insertOnConflictUpdate(
              TreasuryAccountsCompanion.insert(
                id: uuid('c1'),
                label: 'Caisse Physique',
                balance: const Value(500000),
              ),
            );

        final r = await depot.enregistrerReglement(
          fournisseurId: uuid('f1'),
          montant: 30000,
          compteId: uuid('c1'),
          date: aujourdhui,
        );

        expect(r.syncStatus, SyncStatus.pending);
        expect(r.id, hasLength(36));
        // Le serveur seul impute et décaisse.
        expect((await db.select(db.payables).getSingle()).amountPaid, 0);
        expect(
          (await db.select(db.treasuryAccounts).getSingle()).balance,
          500000,
        );
      },
    );

    test('⚠️ deux règlements ne peuvent pas dépasser le dû cumulé', () async {
      await fournisseur('f1', 'Quincaillerie ADJOVI');
      await dette('d1', cleFournisseur: 'f1', montant: 100000);
      await compte('c1', 'Caisse Physique');

      await depot.enregistrerReglement(
        fournisseurId: uuid('f1'),
        montant: 70000,
        compteId: uuid('c1'),
        date: aujourdhui,
      );

      // Reste 30 000 : 40 000 est refusé, 30 000 passe.
      expect(
        () => depot.enregistrerReglement(
          fournisseurId: uuid('f1'),
          montant: 40000,
          compteId: uuid('c1'),
          date: aujourdhui,
        ),
        throwsA(isA<ReglementRefuse>()),
      );
      await depot.enregistrerReglement(
        fournisseurId: uuid('f1'),
        montant: 30000,
        compteId: uuid('c1'),
        date: aujourdhui,
      );
      expect(await depot.du(uuid('f1')), 0);
    });

    test(
      'refus : montant nul, fournisseur sans dette, compte inconnu',
      () async {
        await fournisseur('f1', 'A');
        await fournisseur('f2', 'B');
        await dette('d1', cleFournisseur: 'f1', montant: 1000);
        await compte('c1', 'Caisse');

        Future<void> essai(String f, double m, String c) =>
            depot.enregistrerReglement(
              fournisseurId: uuid(f),
              montant: m,
              compteId: uuid(c),
              date: aujourdhui,
            );

        await expectLater(
          essai('f1', 0, 'c1'),
          throwsA(isA<ReglementRefuse>()),
        );
        await expectLater(
          essai('f2', 100, 'c1'),
          throwsA(isA<ReglementRefuse>()),
        );
        await expectLater(
          essai('f1', 100, 'zz'),
          throwsA(isA<ReglementRefuse>()),
        );
        expect(await db.select(db.supplierPayments).get(), isEmpty);
      },
    );
  });

  group('fiche fournisseur : dépôt et synchronisation', () {
    SyncEngine moteur(_ServeurSync serveur) => SyncEngine(
      database: db,
      client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
        ..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _ConnectiviteFeinte(),
    );

    const fiche = FormulaireFournisseur(
      nom: 'Quincaillerie ADJOVI',
      categorie: 'Matériel',
      telephone: '+229 96 00 00 00',
      adresse: 'Cotonou',
    );

    test('règles : nom, catégorie et téléphone obligatoires', () {
      expect(FournisseursRepository.validerFiche(fiche), isEmpty);
      expect(
        FournisseursRepository.validerFiche(
          const FormulaireFournisseur(nom: ' ', categorie: '', telephone: ''),
        ).keys,
        containsAll(['nom', 'categorie', 'telephone']),
      );
    });

    test(
      '⚠️ créée en attente, UUID du poste, e-mail intact à la modification',
      () async {
        final f = await depot.creerFournisseur(fiche);
        expect(f.id, hasLength(36));
        expect(f.syncStatus, SyncStatus.pending);
        expect(f.isActive, isTrue);

        await (db.update(db.suppliers)..where((x) => x.id.equals(f.id))).write(
          const SuppliersCompanion(email: Value('x@y.bj')),
        );
        final m = await depot.modifierFournisseur(
          f.id,
          const FormulaireFournisseur(
            nom: 'Autre nom',
            categorie: 'Autre',
            telephone: '1',
          ),
        );
        expect(m.name, 'Autre nom');
        expect(m.address, isNull);
        expect(m.email, 'x@y.bj');
      },
    );

    test('⚠️ envoyée sans e-mail, acquittée sur réponse', () async {
      final f = await depot.creerFournisseur(fiche);
      final serveur = _ServeurSync({
        'suppliers': {
          'accepted': [f.id],
          'rejected': [],
        },
      });

      await moteur(serveur).synchroniser();

      final envoye = (serveur.envois.single['suppliers'] as List).single as Map;
      expect(envoye, {
        'id': f.id,
        'name': 'Quincaillerie ADJOVI',
        'category': 'Matériel',
        'phone': '+229 96 00 00 00',
        'address': 'Cotonou',
        'is_active': true,
      });
      expect(
        (await db.select(db.suppliers).getSingle()).syncStatus,
        SyncStatus.synced,
      );
    });

    test(
      '⚠️ refusée par le serveur : conflit, jamais réputée envoyée',
      () async {
        final f = await depot.creerFournisseur(fiche);
        final serveur = _ServeurSync({
          'suppliers': {
            'accepted': [],
            'rejected': [
              {'id': f.id, 'reason': 'Votre rôle ne permet pas.'},
            ],
          },
        });

        await moteur(serveur).synchroniser();

        expect(
          (await db.select(db.suppliers).getSingle()).syncStatus,
          SyncStatus.conflict,
        );
      },
    );

    test("⚠️ le tirage n'efface NI n'écrase une fiche en attente", () async {
      final enAttente = await depot.creerFournisseur(fiche);
      await fournisseur('f9', 'Ancien nom');
      // Un fournisseur synchronisé que le serveur n'a plus (archivé ailleurs).
      await fournisseur('f8', 'Disparu du serveur');

      await moteur(
        _ServeurSync(
          const {},
          tirageExtra: {
            'suppliers': [
              // La version du serveur de la fiche en attente : IGNORÉE.
              {'id': enAttente.id, 'name': 'Version serveur'},
              {'id': uuid('f9'), 'name': 'Nouveau nom'},
            ],
          },
        ),
      ).synchroniser();

      final noms = {
        for (final x in await db.select(db.suppliers).get()) x.id: x.name,
      };
      expect(
        noms[enAttente.id],
        'Quincaillerie ADJOVI',
        reason: 'saisie gardée',
      );
      expect(
        noms[uuid('f9')],
        'Nouveau nom',
        reason: 'synchronisée : remplacée',
      );
      expect(
        noms.containsKey(uuid('f8')),
        isFalse,
        reason: 'absente du serveur',
      );
    });

    test('un archivé n\'est plus proposé, mais ses dettes restent', () async {
      final f = await depot.creerFournisseur(fiche);
      await dette('d1', cleFournisseur: 'x', montant: 5000);
      await (db.update(
        db.payables,
      )).write(PayablesCompanion(supplierId: Value(f.id)));

      await depot.archiverFournisseur(f.id);

      final d = await depot.charger();
      expect(d.fournisseurs, isEmpty);
      expect(d.dettes, hasLength(1));
      await expectLater(
        depot.enregistrerReglement(
          fournisseurId: f.id,
          montant: 100,
          compteId: 'x',
          date: HeureBenin.maintenant(),
        ),
        throwsA(isA<ReglementRefuse>()),
      );
    });
  });

  group('synchronisation du règlement', () {
    SyncEngine moteur(_ServeurSync serveur) => SyncEngine(
      database: db,
      client: Dio(BaseOptions(baseUrl: 'http://serveur-feint'))
        ..interceptors.add(serveur),
      deviceId: 'poste-test',
      connectivity: _ConnectiviteFeinte(),
    );

    Future<ReglementFournisseur> saisir() async {
      await fournisseur('f1', 'Quincaillerie ADJOVI');
      await dette('d1', cleFournisseur: 'f1', montant: 100000);
      await compte('c1', 'Caisse Physique');
      return depot.enregistrerReglement(
        fournisseurId: uuid('f1'),
        montant: 30000,
        compteId: uuid('c1'),
        date: DateTime(2026, 10, 8),
      );
    }

    test('⚠️ part sans imputation ni solde, acquitté sur réponse', () async {
      final r = await saisir();
      final serveur = _ServeurSync({
        'supplier_payments': {
          'accepted': [r.id],
          'rejected': [],
        },
      });

      await moteur(serveur).synchroniser();

      final envoye =
          (serveur.envois.single['supplier_payments'] as List).single as Map;
      expect(envoye, {
        'id': r.id,
        'supplier_id': uuid('f1'),
        'treasury_account_id': uuid('c1'),
        'amount': 30000.0,
        'payment_date': '2026-10-08',
      });
      expect(
        (await db.select(db.supplierPayments).getSingle()).syncStatus,
        SyncStatus.synced,
      );
    });

    test('⚠️ refusé par le serveur : conflit, jamais réputé envoyé', () async {
      final r = await saisir();
      final serveur = _ServeurSync({
        'supplier_payments': {
          'accepted': [],
          'rejected': [
            {'id': r.id, 'reason': 'Aucune dette ouverte.'},
          ],
        },
      });

      await moteur(serveur).synchroniser();

      expect(
        (await db.select(db.supplierPayments).getSingle()).syncStatus,
        SyncStatus.conflict,
      );
      // Un refus ne repart pas tout seul au tour suivant.
      await moteur(serveur).synchroniser();
      expect(
        serveur.envois.where((e) => e.containsKey('supplier_payments')),
        hasLength(1),
      );
    });
  });

  group('dépôt', () {
    /// ⚠️⚠️ LE CŒUR DU TICKET : le montant dû se calcule.
    test('⚠️⚠️ l ardoise porte le reste dû, pas le montant facturé', () async {
      await fournisseur('f1', 'Quincaillerie ADJOVI');
      await dette('d1', cleFournisseur: 'f1', montant: 312000, regle: 156000);

      final d = await depot.charger();

      expect(d.ardoiseTotale, 156000);
      expect(d.dettes.single.montantDu, 156000);
    });

    test('⚠️ le retard se compte depuis l échéance', () async {
      await fournisseur('f1', 'Quincaillerie ADJOVI');
      await dette(
        'echue',
        cleFournisseur: 'f1',
        montant: 5000,
        echeanceIlYA: 30,
      );
      await dette(
        'terme',
        cleFournisseur: 'f1',
        montant: 4000,
        echeanceIlYA: -10,
      );

      final d = await depot.charger();
      final jour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);

      expect(d.echues(jour), 1);
    });

    /// ⚠️ Le total ne compte QUE l'année civile en cours.
    test('⚠️ le total des achats se limite à l année en cours', () async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achat('a1', cleFournisseur: 'f1', total: 100000);
      await achat(
        'vieux',
        cleFournisseur: 'f1',
        total: 500000,
        date: DateTime(aujourdhui.year - 1, 6, 12),
      );

      final d = await depot.charger();

      expect(d.fournisseurs.single.totalAchatsAnnee, 100000);
    });

    /// ⚠️⚠️ UN ACHAT EN ATTENTE COMPTE AUSSI : il est réel, même si la ferme
    /// ne le connaît pas encore.
    test('⚠️⚠️ un achat non synchronisé entre dans le total', () async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achat('a1', cleFournisseur: 'f1', total: 40000, enAttente: true);

      final d = await depot.charger();

      expect(d.fournisseurs.single.totalAchatsAnnee, 40000);
    });

    test('la dernière commande est la plus récente', () async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achat(
        'ancien',
        cleFournisseur: 'f1',
        total: 1000,
        date: DateTime(aujourdhui.year, 1, 5),
      );
      await achat(
        'recent',
        cleFournisseur: 'f1',
        total: 2000,
        date: DateTime(aujourdhui.year, 3, 20),
      );

      final d = await depot.charger();

      expect(
        d.fournisseurs.single.derniereCommande,
        DateTime(aujourdhui.year, 3, 20),
      );
    });

    /// ⚠️ Le serveur ne sert que les fournisseurs actifs : le poste ne peut
    /// pas compter les archivés.
    test('⚠️ le nombre d archivés est nul, faute de donnée', () async {
      final d = await depot.charger();

      expect(d.archives, isNull);
    });
  });

  group('cartes de la maquette (ticket F0.55)', () {
    /// ⚠️ Le serveur ne sert QUE les fournisseurs actifs et ne descend même pas
    /// la colonne : tout ce que le poste détient est actif par construction.
    test('« Fournisseurs actifs » compte le référentiel reçu', () async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await fournisseur('f2', 'Agro-Intrants SARL');

      final d = await depot.charger();

      expect(d.fournisseursActifs, 2);
    });

    /// ⚠️⚠️ **LE PIÈGE DU MOIS SANS L'ANNÉE.** Comparer le seul numéro de mois
    /// ferait entrer les achats de juillet DERNIER dans le juillet courant : un
    /// volume mensuel qui double une fois l'an, sans rien signaler.
    test(
      '⚠️⚠️ le volume du mois exclut le même mois de l année passée',
      () async {
        await fournisseur('f1', 'Provenderie du Plateau');

        await achat('a1', cleFournisseur: 'f1', total: 185000);
        await achat(
          'a2',
          cleFournisseur: 'f1',
          total: 999000,
          date: DateTime(aujourdhui.year - 1, aujourdhui.month, aujourdhui.day),
        );

        final d = await depot.charger();

        expect(d.volumeAchatDuMois, 185000);
      },
    );

    test('le volume du mois exclut un autre mois de la même année', () async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achat('a1', cleFournisseur: 'f1', total: 185000);

      // Un mois qui n'est jamais celui d'aujourd'hui.
      final autreMois = aujourdhui.month == 1 ? 2 : 1;
      await achat(
        'a2',
        cleFournisseur: 'f1',
        total: 42000,
        date: DateTime(aujourdhui.year, autreMois, 15),
      );

      final d = await depot.charger();

      expect(d.volumeAchatDuMois, 185000);
    });

    /// ⚠️ Un achat saisi ici et pas encore parti compte : il est réel, même si
    /// la ferme ne le connaît pas encore.
    test(
      '⚠️ un achat encore en attente d envoi compte dans le volume',
      () async {
        await fournisseur('f1', 'Provenderie du Plateau');
        await achat('a1', cleFournisseur: 'f1', total: 60000, enAttente: true);

        final d = await depot.charger();

        expect(d.volumeAchatDuMois, 60000);
      },
    );

    /// ⚠️⚠️ **`created_at` NE VOYAGE PAS.** Le tirage sert six colonnes, sans
    /// date de création : le poste ne peut pas savoir lequel est nouveau.
    test('⚠️⚠️ « Nouveaux (mois) » est inconnu, pas nul', () async {
      await fournisseur('f1', 'Provenderie du Plateau');

      final d = await depot.charger();

      expect(d.nouveauxDuMois, isNull);
    });

    testWidgets('l onglet Ajouter porte ses deux cartes', (tester) async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await fournisseur('f2', 'Agro-Intrants SARL');

      await afficher(tester);

      expect(find.text('FOURNISSEURS ACTIFS'), findsOneWidget);
      expect(find.text('NOUVEAUX (MOIS)'), findsOneWidget);

      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-ajouter-actifs')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      // ⚠️ Un tiret, jamais un zéro — et cherché DANS sa carte : l'écran en
      // porte d'autres, et un `find.text('—')` global passerait au vert même
      // si celle-ci affichait « 0 ».
      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-ajouter-nouveaux')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('l onglet Fiches porte son volume du mois', (tester) async {
      await fournisseur('f1', 'Provenderie du Plateau');
      await achat('a1', cleFournisseur: 'f1', total: 608000);

      await afficher(tester);
      await ouvrir(tester, 'Fiches Fournisseurs');

      expect(find.text("VOLUME D'ACHAT (MOIS)"), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('kpi-fiches-volume')),
          matching: find.text('608 000'),
        ),
        findsOneWidget,
      );
    });
  });

  group('écran', () {
    /// ⚠️⚠️ **LE NOMBRE DE CARTES, ONGLET PAR ONGLET** (ticket F0.54). Chaque
    /// onglet du hub est une page distincte de la maquette : le contrôle se fait
    /// donc page par page, sans arbitrage sur la répartition.
    testWidgets('⚠️⚠️ chaque onglet rend le nombre de cartes de sa page', (
      tester,
    ) async {
      await afficher(tester);

      const pages = <String, String>{
        'Ajouter Fournisseur': 'ajouter-fournisseur.html',
        'Fiches Fournisseurs': 'fiches-fournisseurs.html',
        'Dettes Fournisseurs': 'dettes-fournisseurs.html',
      };

      for (final onglet in pages.keys) {
        await ouvrir(tester, onglet);
        expect(
          find.byType(CarteKpi),
          findsNWidgets(cartesAttendues(pages[onglet]!)),
          reason: onglet,
        );
      }
    });

    testWidgets('⚠️ les trois onglets du hub sont là, dans son ordre', (
      tester,
    ) async {
      await afficher(tester);

      for (final onglet in [
        'Ajouter Fournisseur',
        'Fiches Fournisseurs',
        'Dettes Fournisseurs',
      ]) {
        expect(find.text(onglet), findsWidgets, reason: onglet);
      }
    });

    testWidgets('l onglet d ajout porte les cinq colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      for (final colonne in [
        'NOM',
        'CONTACT',
        'CATÉGORIE',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('⚠️ « Nouveau Fournisseur » écrit une fiche en attente', (
      tester,
    ) async {
      await afficher(tester);

      await tester.tap(find.byKey(const Key('nouveau-fournisseur')));
      await tester.pumpAndSettle();

      // Champs obligatoires : rien n'est écrit tant qu'ils manquent.
      await tester.tap(find.byKey(const Key('fiche-enregistrer')));
      await tester.pumpAndSettle();
      expect(await db.select(db.suppliers).get(), isEmpty);
      expect(find.text('Ce champ est obligatoire.'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('fiche-nom')),
        'Provenderie du Plateau',
      );
      await tester.enterText(
        find.byKey(const Key('fiche-telephone')),
        '+229 97 12 34 56',
      );
      await tester.tap(find.byKey(const Key('fiche-categorie')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aliments').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fiche-enregistrer')));
      await tester.pumpAndSettle();

      final f = await db.select(db.suppliers).getSingle();
      expect(f.name, 'Provenderie du Plateau');
      expect(f.category, 'Aliments');
      expect(f.syncStatus, SyncStatus.pending);
      expect(f.isActive, isTrue);
      // La liste le montre tout de suite, marqué « En attente ».
      expect(find.byKey(Key('fiche-en-attente-${f.id}')), findsOneWidget);
    });

    testWidgets('⚠️ archiver cache la fiche sans rien supprimer', (
      tester,
    ) async {
      await fournisseur('f1', 'Quincaillerie ADJOVI');

      await afficher(tester);
      await tester.tap(find.byKey(Key('archiver-fiche-${uuid('f1')}')));
      await tester.pumpAndSettle();

      expect(find.text("Confirmer l'archivage"), findsOneWidget);
      await tester.tap(find.byKey(const Key('archivage-confirmer')));
      await tester.pumpAndSettle();

      final f = await db.select(db.suppliers).getSingle();
      expect(f.isActive, isFalse);
      expect(f.syncStatus, SyncStatus.pending);
      expect(find.text('Quincaillerie ADJOVI'), findsNothing);
    });

    testWidgets('un fournisseur descendu est nommé avec son contact', (
      tester,
    ) async {
      await fournisseur(
        'f1',
        'Provenderie du Plateau',
        categorie: 'Aliments',
        tel: '+22997000000',
      );

      await afficher(tester);

      expect(find.text('Provenderie du Plateau'), findsOneWidget);
      expect(find.text('+22997000000'), findsOneWidget);
      expect(find.text('Aliments'), findsOneWidget);
      expect(find.text('Actif'), findsOneWidget);
    });

    testWidgets('les fiches portent les six colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Fiches Fournisseurs');

      for (final colonne in [
        'NOM',
        'CATÉGORIE',
        'TOTAL ACHATS (ANNÉE)',
        'DERNIÈRE COMMANDE',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('la fiche montre le total de l année et la dernière commande', (
      tester,
    ) async {
      await fournisseur('f1', 'Provenderie du Plateau', categorie: 'Aliments');
      await achat(
        'a1',
        cleFournisseur: 'f1',
        total: 185000,
        date: DateTime(aujourdhui.year, 7, 14),
      );

      await afficher(tester);
      await ouvrir(tester, 'Fiches Fournisseurs');

      expect(find.text('185 000'), findsOneWidget);
      expect(find.text('14/07/${aujourdhui.year}'), findsOneWidget);
    });

    testWidgets('les dettes portent les cinq colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Dettes Fournisseurs');

      for (final colonne in [
        'FOURNISSEUR',
        'MONTANT DÛ',
        'ÉCHÉANCE',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    /// Ticket AC-4 — la colonne « Actions » n'est plus inerte : « Régler » ouvre la modale sur le fournisseur de la ligne
    /// (`openPaymentModal($supplierId)` du web) ; une dette soldée n'offre rien.
    testWidgets('⚠️ « Régler » ouvre la modale sur le fournisseur de la ligne ; une dette soldée n\'a pas d\'action', (
      tester,
    ) async {
      await fournisseur('f1', 'Quincaillerie ADJOVI');
      await fournisseur('f2', 'Provenderie du Plateau');
      await dette('d1', cleFournisseur: 'f1', montant: 100000, regle: 40000);
      await dette('d2', cleFournisseur: 'f2', montant: 50000, regle: 50000, nom: 'Provenderie du Plateau');
      await compte('c1', 'Caisse Physique');

      await afficher(tester);
      await ouvrir(tester, 'Dettes Fournisseurs');

      expect(find.byKey(const Key('regler-dette-0')), findsOneWidget);
      expect(find.byKey(const Key('regler-dette-1')), findsNothing, reason: 'dette soldée : rien à régler');

      await tester.tap(find.byKey(const Key('regler-dette-0')));
      await tester.pumpAndSettle();

      expect(find.text('Enregistrer un Règlement'), findsOneWidget);
      expect(
        tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('reglement-fournisseur'))).initialValue,
        uuid('f1'),
        reason: 'le fournisseur de la ligne est déjà choisi',
      );
    });

    /// ⚠️⚠️ 312 000 facturés, 156 000 réglés : la colonne montre 156 000.
    testWidgets('⚠️⚠️ la dette affiche le reste dû, jamais le total facturé', (
      tester,
    ) async {
      await fournisseur('f1', 'Quincaillerie ADJOVI');
      await dette(
        'd1',
        cleFournisseur: 'f1',
        montant: 312000,
        regle: 156000,
        echeanceIlYA: 30,
      );

      await afficher(tester);
      await ouvrir(tester, 'Dettes Fournisseurs');

      expect(find.text('156 000'), findsWidgets);
      expect(find.text('312 000'), findsNothing);
      expect(find.textContaining('(+30 j)'), findsOneWidget);
    });

    /// ⚠️⚠️ Le poste n'impute ni ne décaisse : il note le règlement, le serveur
    /// rejoue. Et il déduit en attendant, pour ne pas inviter à payer deux fois.
    testWidgets(
      '⚠️⚠️ un règlement saisi est en attente et déduit de l\'ardoise',
      (tester) async {
        await fournisseur('f1', 'Quincaillerie ADJOVI');
        await dette('d1', cleFournisseur: 'f1', montant: 100000, regle: 40000);
        await compte('c1', 'Caisse Physique');

        await afficher(tester);
        await ouvrir(tester, 'Dettes Fournisseurs');

        await tester.tap(find.byKey(const Key('enregistrer-reglement')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('reglement-fournisseur')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Quincaillerie ADJOVI').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('reglement-montant')),
          '25000',
        );
        await tester.tap(find.byKey(const Key('reglement-compte')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Caisse Physique').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reglement-enregistrer')));
        await tester.pumpAndSettle();

        final r = await db.select(db.supplierPayments).getSingle();
        expect(r.amount, 25000);
        expect(r.syncStatus, SyncStatus.pending);

        // Dû : 100 000 − 40 000 = 60 000 ; moins 25 000 en attente = 35 000.
        expect(find.text('35 000'), findsWidgets);
        expect(find.textContaining('Règlements en attente'), findsOneWidget);
      },
    );

    testWidgets('⚠️ un montant au-dessus du dû est refusé dans la modale', (
      tester,
    ) async {
      await fournisseur('f1', 'Quincaillerie ADJOVI');
      await dette('d1', cleFournisseur: 'f1', montant: 50000);
      await compte('c1', 'Caisse Physique');

      await afficher(tester);
      await ouvrir(tester, 'Dettes Fournisseurs');
      await tester.tap(find.byKey(const Key('enregistrer-reglement')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reglement-fournisseur')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quincaillerie ADJOVI').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('reglement-montant')),
        '80000',
      );
      await tester.tap(find.byKey(const Key('reglement-compte')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caisse Physique').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reglement-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reglement-erreur')), findsOneWidget);
      expect(find.textContaining('dépasse ce qui reste dû'), findsOneWidget);
      expect(await db.select(db.supplierPayments).get(), isEmpty);
    });

    testWidgets('sans donnée, chaque tableau le dit', (tester) async {
      await afficher(tester);
      expect(find.text('— Aucun fournisseur synchronisé —'), findsOneWidget);

      await ouvrir(tester, 'Dettes Fournisseurs');
      expect(
        find.text('— Aucune dette fournisseur en cours —'),
        findsOneWidget,
      );
    });
  });
}
