import 'package:agrierp/core/comptabilite/exercice_choisi.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/pdf_recu.dart';
import 'package:agrierp/core/localisation/localisation_poste.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/ventes/historique_ventes_onglet.dart';
import 'package:agrierp/features/ventes/historique_ventes_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket AV2 — ONGLET « HISTORIQUE DES VENTES » DU POSTE, IDENTIQUE AU BLADE (`historique-ventes.blade.php`,
/// `Livewire\Ventes\HistoriqueVentes`). Audit ligne à ligne : `docs/AUDIT_FIDELITE_ECRANS.md` § 11.
///
/// ⚠️⚠️ CE QUE CES TESTS PROTÈGENT : les règles du web, reproduites à l'identique — cartes sur la PÉRIODE (ventes validées,
/// panier moyen arrondi et « 0 FCFA » sans vente, encours des créances ouvertes de TOUTES les périodes), tableau borné à
/// l'EXERCICE affiché (la période n'y filtre rien), recherche sur l'identifiant COMPLET ou le nom du client, statut « En
/// attente » jugé sur le MODE (crédit) et la pastille sur le RESTE DÛ, « Payé » = total − reste, ligne annulée estompée,
/// tiroir de détail, annulation (demande : le serveur réintègre le stock), ticket PDF produit par le serveur.
/// Les chiffres attendus sont des littéraux calculés à la main.
class _ClientVentes extends ClientVentes {
  _ClientVentes(this.reponse) : super(Dio());

  final Future<PdfRecu> Function(String id) reponse;
  final List<String> demandes = [];

  @override
  Future<PdfRecu> pdf(String venteId) {
    demandes.add(venteId);
    return reponse(venteId);
  }
}

void main() {
  late AppDatabase db;
  late HistoriqueVentesRepository depot;

  const oeufs = 'aaaaaaaa-0000-4000-8000-000000000001';
  const vitamines = 'aaaaaaaa-0000-4000-8000-000000000002';
  const solange = 'cccccccc-0000-4000-8000-000000000001';
  const koffi = 'cccccccc-0000-4000-8000-000000000002';

  /// Mercredi 21/10/2026, 10 h au Bénin.
  final maintenant = DateTime(2026, 10, 21, 10);

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  Future<void> vente(
    String cle, {
    required double total,
    double remise = 0,
    String mode = 'especes',
    String statut = 'validee',
    String? client,
    String? nomClient,
    DateTime? quand,
    SyncStatus synchro = SyncStatus.synced,
    int articles = 1,
  }) async {
    final date = quand ?? DateTime(2026, 10, 20, 15, 30);
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: uuid(cle),
        deviceId: 'serveur',
        syncStatus: Value(synchro),
        updatedAt: date,
        customerId: Value(client),
        customerName: Value(nomClient),
        paymentMode: mode,
        subtotal: Value(total + remise),
        discount: Value(remise),
        total: total,
        status: Value(statut),
        soldAt: date,
      ),
    );
    for (var i = 0; i < articles; i++) {
      await db.into(db.saleLines).insert(
        SaleLinesCompanion.insert(
          id: uuid('$cle-ligne-$i'),
          saleId: uuid(cle),
          productId: i.isEven ? oeufs : vitamines,
          qty: i == 0 ? 2.5 : 1,
          unitPrice: total / articles,
          manualTotalAmount: total / articles,
        ),
      );
    }
  }

  Future<void> creance(String cle, {required double montant, double paye = 0, String statut = 'en_cours', String? vente}) =>
      db.into(db.receivables).insert(
        ReceivablesCompanion.insert(
          id: uuid('creance-$cle'),
          customerId: solange,
          saleId: Value(vente == null ? null : uuid(vente)),
          amount: montant,
          amountPaid: Value(paye),
          status: Value(statut),
        ),
      );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = HistoriqueVentesRepository(database: db, horloge: () => maintenant);
    for (final (id, sku, nom, unite) in [
      (oeufs, 'OEUF', "Plaquette d'œufs", 'plaquette'),
      (vitamines, 'VIT', 'Vitamines', 'sachet'),
    ]) {
      await db.into(db.products).insert(
        ProductsCompanion.insert(id: id, sku: sku, name: nom, unit: unite, pricingMode: 'fourchette'),
      );
    }
    await db.into(db.customers).insert(CustomersCompanion.insert(id: solange, name: 'GBAGUIDI Solange'));
    await db.into(db.customers).insert(CustomersCompanion.insert(id: koffi, name: 'ADJOVI Koffi'));
    await db.into(db.customers).insert(
      CustomersCompanion.insert(id: uuid('archive'), name: 'ZANNOU Archivé', isActive: const Value(false)),
    );
  });

  tearDown(() async {
    ToastAgri.toutRetirer();
    HeureBenin.reinitialiser();
    await db.close();
  });

  // ── Le dépôt : cartes, filtres, lignes ──────────────────────────────────────────────────────────────────────────────────

  group('cartes (HistoriqueVentes::getKpisProperty)', () {
    test('⚠️ sans vente : tout à zéro, « 0 FCFA » de panier moyen (le web ne met jamais de tiret)', () async {
      final k = (await depot.charger()).kpis(DateTime(2026, 10), DateTime(2026, 10, 21));

      expect(k.chiffreAffaires, 0);
      expect(k.transactions, 0);
      expect(k.panierMoyen, 0);
      expect(k.encoursCreances, 0);
    });

    test('⚠️⚠️ les ventes VALIDÉES de la période : 32 000 + 48 000 = 80 000 sur 2, panier 40 000 ; l annulée et l hors période comptent pour rien', () async {
      await vente('a', total: 32000, quand: DateTime(2026, 10, 3, 9));
      await vente('b', total: 48000, quand: DateTime(2026, 10, 21, 8));
      await vente('c', total: 99000, statut: 'annulee', quand: DateTime(2026, 10, 10));
      await vente('d', total: 5000, quand: DateTime(2026, 9, 30, 23, 59));
      await vente('e', total: 7000, quand: DateTime(2026, 10, 22));

      final k = (await depot.charger()).kpis(DateTime(2026, 10), DateTime(2026, 10, 21));

      expect(k.chiffreAffaires, 80000);
      expect(k.transactions, 2);
      expect(k.panierMoyen, 40000);
    });

    test('le panier moyen est arrondi à l entier (round() de PHP) : 10 001 / 2 → 5 001', () async {
      await vente('a', total: 5000, quand: DateTime(2026, 10, 3));
      await vente('b', total: 5001, quand: DateTime(2026, 10, 4));

      expect((await depot.charger()).kpis(DateTime(2026, 10), DateTime(2026, 10, 21)).panierMoyen, 5001);
    });

    test('⚠️⚠️ l encours = le RESTE DÛ des créances ouvertes, toutes périodes : (8 000 − 3 000) + 2 000 ; une créance soldée ne compte pas', () async {
      await creance('a', montant: 8000, paye: 3000);
      await creance('b', montant: 2000);
      await creance('c', montant: 9000, paye: 9000, statut: 'soldee');

      expect((await depot.charger()).encoursCreances, 7000);
    });
  });

  group('lignes (getSalesProperty, sans la pagination)', () {
    test('plus récentes d abord, puis identifiant décroissant', () async {
      await vente('a', total: 1000, quand: DateTime(2026, 10, 18, 9));
      await vente('b', total: 2000, quand: DateTime(2026, 10, 20, 9));
      await vente('c', total: 3000, quand: DateTime(2026, 10, 20, 9));

      final l = (await depot.charger()).filtrer();

      expect(l.map((x) => x.vente.total), [3000, 2000, 1000]);
    });

    test('⚠️⚠️ Payé = total − reste ; le reste est celui de la créance de la vente (« Reste » rouge si > 0)', () async {
      await vente('credit', total: 20000, mode: 'credit', client: solange);
      await creance('credit', montant: 20000, paye: 5000, vente: 'credit');
      await vente('especes', total: 8000);

      final l = {for (final x in (await depot.charger()).filtrer()) x.vente.id: x};

      expect(l[uuid('credit')]!.reste, 15000);
      expect(l[uuid('credit')]!.paye, 5000);
      expect(l[uuid('credit')]!.statut, 'En attente');
      expect(l[uuid('especes')]!.reste, 0);
      expect(l[uuid('especes')]!.paye, 8000);
      expect(l[uuid('especes')]!.statut, 'Payée');
    });

    test('une créance soldée (ou absente) : reste 0, vente « Payée » même à crédit — la pastille suit le reste', () async {
      await vente('credit', total: 20000, mode: 'credit', client: solange);
      await creance('credit', montant: 20000, paye: 20000, statut: 'soldee', vente: 'credit');

      final l = (await depot.charger()).filtrer().single;

      expect(l.reste, 0);
      expect(l.statut, 'Payée');
    });

    test('⚠️ une vente ANNULÉE : reste 0, payé 0, statut « Annulée »', () async {
      await vente('a', total: 20000, mode: 'credit', client: solange, statut: 'annulee');
      await creance('a', montant: 20000, vente: 'a');

      final l = (await depot.charger()).filtrer().single;

      expect(l.reste, 0);
      expect(l.paye, 0);
      expect(l.statut, 'Annulée');
      expect(l.annulee, isTrue);
    });

    test('⚠️⚠️ une vente à crédit saisie ICI et pas encore reçue : le serveur ouvrira UNE créance du total (crédit ET client), pas pour les autres modes', () async {
      await vente('avec-client', total: 12000, mode: 'credit', client: solange, synchro: SyncStatus.pending);
      await vente('sans-client', total: 9000, mode: 'credit', synchro: SyncStatus.pending);
      await vente('especes', total: 7000, synchro: SyncStatus.pending);

      final l = {for (final x in (await depot.charger()).filtrer()) x.vente.id: x};

      expect(l[uuid('avec-client')]!.reste, 12000);
      expect(l[uuid('avec-client')]!.envoyee, isFalse);
      expect(l[uuid('sans-client')]!.reste, 0);
      expect(l[uuid('especes')]!.reste, 0);
    });

    test('le client : celui du fichier, sinon le nom servi avec la vente, sinon « Client Anonyme »', () async {
      await vente('a', total: 1000, client: solange, quand: DateTime(2026, 10, 3));
      await vente('b', total: 1000, nomClient: 'KPADE Archivé', quand: DateTime(2026, 10, 4));
      await vente('c', total: 1000, quand: DateTime(2026, 10, 5));

      final l = {for (final x in (await depot.charger()).filtrer()) x.vente.id: x.client};

      expect(l[uuid('a')], 'GBAGUIDI Solange');
      expect(l[uuid('b')], 'KPADE Archivé');
      expect(l[uuid('c')], 'Client Anonyme');
    });

    test('le nombre d articles = le nombre de LIGNES de la vente', () async {
      await vente('a', total: 3000, articles: 3);

      expect((await depot.charger()).filtrer().single.articles, 3);
    });

    group('filtres', () {
      setUp(() async {
        await vente('credit', total: 10000, mode: 'credit', client: solange);
        await vente('mobile', total: 20000, mode: 'mobile_money', client: koffi);
        await vente('anonyme', total: 30000, mode: 'especes');
        await vente('annulee', total: 40000, mode: 'virement', statut: 'annulee', client: solange);
        await vente('avance', total: 50000, mode: 'avance', client: koffi);
      });

      List<int> totaux(InstantaneHistorique i, {String recherche = '', String statut = '', String mode = '', String client = ''}) => [
        for (final l in i.filtrer(recherche: recherche, statut: statut, mode: mode, clientId: client)) l.vente.total.toInt(),
      ]..sort();

      test('⚠️⚠️ « Statut » : Payée = validée hors crédit ; En attente = validée À CRÉDIT (le web juge sur le MODE) ; Annulée', () async {
        final i = await depot.charger();

        expect(totaux(i, statut: 'payee'), [20000, 30000, 50000]);
        expect(totaux(i, statut: 'attente'), [10000]);
        expect(totaux(i, statut: 'annulee'), [40000]);
        expect(totaux(i), [10000, 20000, 30000, 40000, 50000]);
      });

      test('« Mode » : les cinq modes du Blade, dont « Avance »', () async {
        final i = await depot.charger();

        expect(totaux(i, mode: 'especes'), [30000]);
        expect(totaux(i, mode: 'mobile_money'), [20000]);
        expect(totaux(i, mode: 'virement'), [40000]);
        expect(totaux(i, mode: 'credit'), [10000]);
        expect(totaux(i, mode: 'avance'), [50000]);
      });

      test('« Client » : les ventes de ce client', () async {
        final i = await depot.charger();

        expect(totaux(i, client: koffi), [20000, 50000]);
        expect(totaux(i, client: solange), [10000, 40000]);
      });

      test('⚠️⚠️ la recherche porte sur l identifiant COMPLET de la vente OU le nom du client ; « anonyme » ne trouve pas « Client Anonyme »', () async {
        final i = await depot.charger();

        expect(totaux(i, recherche: uuid('mobile').substring(0, 14)), [20000], reason: 'un morceau de l\'identifiant');
        expect(totaux(i, recherche: 'ADJOVI'), [20000, 50000]);
        expect(totaux(i, recherche: 'adjovi koffi'), [20000, 50000], reason: 'insensible à la casse');
        expect(totaux(i, recherche: 'client anon'), isEmpty, reason: 'seul un client rattaché répond');
      });

      test('les filtres se combinent', () async {
        final i = await depot.charger();

        expect(totaux(i, mode: 'mobile_money', client: koffi), [20000]);
        expect(totaux(i, statut: 'payee', client: solange), isEmpty);
      });

      test('« Client : Tous » ne propose que les clients ACTIFS, par ordre alphabétique', () async {
        final i = await depot.charger();

        expect(i.clientsActifs.map((c) => c.name), ['ADJOVI Koffi', 'GBAGUIDI Solange']);
      });
    });

    test('⚠️⚠️ le détail : articles (nom × quantité, montant), client, date, sous-total, remise, total', () async {
      await vente('a', total: 9000, remise: 1000, client: solange, articles: 2);

      final d = (await depot.charger()).detail(uuid('a'))!;

      expect(d.ligne.client, 'GBAGUIDI Solange');
      expect(d.articles.map((a) => (a.nom, a.quantite, a.montant)), [("Plaquette d'œufs", 2.5, 4500.0), ('Vitamines', 1.0, 4500.0)]);
      expect(d.ligne.vente.subtotal, 10000);
      expect(d.ligne.vente.discount, 1000);
      expect(d.ligne.vente.total, 9000);
      expect((await depot.charger()).detail(uuid('inconnue')), isNull);
    });
  });

  group('annulation (cancelSale) : une DEMANDE, le serveur réintègre le stock', () {
    test('la vente passe à annulee et repart ; le stock LOCAL ne bouge pas ; une seconde annulation ne fait rien', () async {
      await vente('a', total: 9000);
      final avant = (await (db.select(db.products)..where((p) => p.id.equals(oeufs))).getSingle()).stockQty;

      expect(await depot.annuler(uuid('a')), isTrue);

      final v = await (db.select(db.sales)..where((s) => s.id.equals(uuid('a')))).getSingle();
      expect(v.status, 'annulee');
      expect(v.syncStatus, SyncStatus.pending);
      expect((await (db.select(db.products)..where((p) => p.id.equals(oeufs))).getSingle()).stockQty, avant);
      expect(await db.select(db.stockAdjustments).get(), isEmpty);
      expect(await depot.annuler(uuid('a')), isFalse);
      expect(await depot.annuler(uuid('inconnue')), isFalse);
    });
  });

  // ── L'écran ────────────────────────────────────────────────────────────────────────────────────────────────────────────

  group('écran', () {
    var nouvelleVente = 0;
    final enregistres = <PdfRecu>[];

    Future<ExerciceChoisi?> exercice({bool clos = false}) async {
      await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          id: uuid('exercice-2026'),
          year: 2026,
          startDate: Value(DateTime(2026)),
          endDate: Value(DateTime(2026, 12, 31)),
          status: Value(clos ? 'cloture' : 'ouvert'),
        ),
      );
      final service = ExerciceChoisi(db, maintenant: () => maintenant);
      await service.charger();
      return service;
    }

    Future<void> monter(
      WidgetTester tester, {
      ExerciceChoisi? exercice,
      bool peutGerer = true,
      bool peutExporter = true,
      HistoriqueVentesRepository? depotInjecte,
      double largeur = 1600,
    }) async {
      tester.view.physicalSize = Size(largeur, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      HeureBenin.horloge = () => maintenant.subtract(HeureBenin.decalage);
      nouvelleVente = 0;
      enregistres.clear();
      final onglet = HistoriqueVentesOnglet(
        depot: depotInjecte ?? depot,
        peutGerer: peutGerer,
        peutExporter: peutExporter,
        onNouvelleVente: () => nouvelleVente++,
        enregistrer: (pdf) async {
          enregistres.add(pdf);
          return r'C:\Users\Caisse\Documents\AgriERP\vente-BBBBBBBB.pdf';
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: LocalisationPoste.locale,
          supportedLocales: LocalisationPoste.locales,
          localizationsDelegates: LocalisationPoste.delegues,
          home: exercice == null
              ? Scaffold(body: onglet)
              : PorteeExerciceChoisi(notifier: exercice, child: Scaffold(body: onglet)),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choisir(WidgetTester tester, String cle, String texte) async {
      await tester.tap(find.byKey(Key(cle)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(texte).last);
      await tester.pumpAndSettle();
    }

    testWidgets("l'en-tête : « Toutes les ventes enregistrées de l'entreprise. » et « Nouvelle Vente » ouvre le hub sur la caisse", (tester) async {
      await monter(tester);

      expect(find.text('Historique des Ventes'), findsOneWidget);
      expect(find.text("Toutes les ventes enregistrées de l'entreprise."), findsOneWidget);
      await tester.tap(find.byKey(const Key('nouvelle-vente')));
      expect(nouvelleVente, 1);
    });

    testWidgets('⚠️⚠️ quatre cartes, libellés du Blade ; valeurs sur la période : CA, transactions, panier moyen, encours', (tester) async {
      await vente('a', total: 32000, quand: DateTime(2026, 10, 3, 9));
      await vente('b', total: 48000, quand: DateTime(2026, 10, 21, 8));
      await vente('c', total: 99000, statut: 'annulee', quand: DateTime(2026, 10, 10));
      await creance('a', montant: 8000, paye: 3000);
      await monter(tester, exercice: await exercice());

      expect(find.byType(CarteKpi), findsNWidgets(cartesAttendues('historique-ventes.html')));
      for (final libelle in ["CHIFFRE D'AFFAIRES", 'TRANSACTIONS', 'PANIER MOYEN', 'ENCOURS CRÉANCES']) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }
      String valeur(String cle) => tester
          .widgetList<Text>(find.descendant(of: find.byKey(Key(cle)), matching: find.byType(Text)))
          .map((t) => t.data)
          .join('|');
      expect(valeur("kpi-Chiffre d'Affaires"), contains('80 000'));
      expect(valeur("kpi-Chiffre d'Affaires"), contains('FCFA'));
      expect(valeur('kpi-Transactions'), contains('2'));
      expect(valeur('kpi-Panier Moyen'), contains('40 000'));
      expect(valeur('kpi-Encours Créances'), contains('5 000'));
      expect(valeur('kpi-Encours Créances'), isNot(contains('8 000')), reason: 'le reste dû, pas le montant facturé');
    });

    testWidgets('⚠️ sans vente : « 0 FCFA » de panier moyen, comme le web', (tester) async {
      await monter(tester);

      final panier = tester.widgetList<Text>(find.descendant(of: find.byKey(const Key('kpi-Panier Moyen')), matching: find.byType(Text))).map((t) => t.data).join('|');
      expect(panier, contains('0'));
      expect(panier, isNot(contains('—')));
    });

    testWidgets('le tableau porte les onze colonnes du Blade, dans son ordre', (tester) async {
      await monter(tester);

      const colonnes = ['FACTURE', 'CLIENT', 'DATE', 'ARTICLES', 'REMISE', 'TOTAL TTC', 'PAYÉ', 'RESTE', 'MODE', 'STATUT', 'ACTIONS'];
      final x = [for (final c in colonnes) tester.getTopLeft(find.text(c)).dx];
      expect([...x]..sort(), x);
      expect(x.toSet().length, colonnes.length);
    });

    testWidgets('sans vente : « Aucune vente pour le moment. »', (tester) async {
      await monter(tester);

      expect(find.text('Aucune vente pour le moment.'), findsOneWidget);
    });

    testWidgets('⚠️⚠️ une ligne : facture, client, date et heure, articles, remise, total TTC, payé, reste, mode, statut', (tester) async {
      await vente('credit', total: 20000, remise: 500, mode: 'credit', client: solange, articles: 2, quand: DateTime(2026, 10, 20, 15, 30));
      await creance('credit', montant: 20000, paye: 5000, vente: 'credit');
      await monter(tester, exercice: await exercice());

      final ligne = find.byKey(const Key('vente-0'));
      expect(find.descendant(of: ligne, matching: find.text(uuid('credit').substring(0, 8).toUpperCase())), findsOneWidget);
      for (final texte in ['GBAGUIDI Solange', '20/10/2026 15:30', '2', '500', '20 000 FCFA', '5 000', '15 000', 'Crédit client', 'En attente']) {
        expect(find.descendant(of: ligne, matching: find.text(texte)), findsOneWidget, reason: texte);
      }
    });

    testWidgets('⚠️ une vente annulée est estompée (opacity-50), sans bouton « Annuler »', (tester) async {
      await vente('a', total: 9000, statut: 'annulee');
      await monter(tester, exercice: await exercice());

      expect(tester.widget<Opacity>(find.ancestor(of: find.byKey(const Key('vente-0')), matching: find.byType(Opacity)).first).opacity, 0.5);
      expect(find.text('Annulée'), findsOneWidget);
      expect(find.byKey(Key('vente-annuler-${uuid('a')}')), findsNothing);
      expect(find.byKey(Key('vente-voir-${uuid('a')}')), findsOneWidget);
    });

    testWidgets('⚠️ ÉCART ASSUMÉ : une vente pas encore reçue du serveur le dit sous sa pastille', (tester) async {
      await vente('a', total: 9000, synchro: SyncStatus.pending);
      await monter(tester, exercice: await exercice());

      expect(tester.widget<Text>(find.byKey(Key('vente-envoi-${uuid('a')}'))).data, 'Non envoyée');
    });

    testWidgets("la liste porte l'exercice AFFICHÉ, pas la période : une vente de septembre y figure, hors des cartes", (tester) async {
      await vente('sept', total: 5000, quand: DateTime(2026, 9, 5));
      await vente('oct', total: 7000, quand: DateTime(2026, 10, 5));
      await vente('2025', total: 9999, quand: DateTime(2025, 12, 30));
      await monter(tester, exercice: await exercice());

      expect(find.byKey(const Key('vente-0')), findsOneWidget);
      expect(find.byKey(const Key('vente-1')), findsOneWidget);
      expect(find.byKey(const Key('vente-2')), findsNothing, reason: '2025 est hors de l\'exercice 2026');
      final ca = tester.widgetList<Text>(find.descendant(of: find.byKey(const Key("kpi-Chiffre d'Affaires")), matching: find.byType(Text))).map((t) => t.data).join('|');
      expect(ca, contains('7 000'), reason: 'la période par défaut est octobre');
    });

    testWidgets('⚠️⚠️ 27 ventes : 25 par page, « 27 lignes dans l\'exercice 2026 — page 1 sur 2 », Suivant', (tester) async {
      for (var i = 0; i < 27; i++) {
        await vente('v${i.toString().padLeft(3, '0')}', total: 1000.0 + i, quand: DateTime(2026, 10, 1, 8, i));
      }
      await monter(tester, exercice: await exercice());

      expect(find.byKey(const Key('vente-24')), findsOneWidget);
      expect(find.byKey(const Key('vente-25')), findsNothing);
      expect(find.text("27 lignes dans l'exercice 2026 — page 1 sur 2"), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('pagination-ventes-suivant')));
      await tester.tap(find.byKey(const Key('pagination-ventes-suivant')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vente-1')), findsOneWidget);
      expect(find.byKey(const Key('vente-2')), findsNothing);
      expect(find.text("27 lignes dans l'exercice 2026 — page 2 sur 2"), findsOneWidget);
    });

    testWidgets('⚠️⚠️ la recherche (« Facture, client... », 300 ms) filtre et ramène à la page 1', (tester) async {
      await vente('a', total: 1000, client: solange, quand: DateTime(2026, 10, 2));
      await vente('b', total: 2000, client: koffi, quand: DateTime(2026, 10, 3));
      await monter(tester, exercice: await exercice());
      expect(find.text('Facture, client...'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('recherche-ventes')), 'adjovi');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('vente-1')), findsOneWidget, reason: 'avant le délai de 300 ms rien ne change');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vente-0')), findsOneWidget);
      expect(find.byKey(const Key('vente-1')), findsNothing);
      expect(find.text('ADJOVI Koffi'), findsWidgets);
    });

    testWidgets('« Statut », « Mode » et « Client » filtrent ; « Réinitialiser » vide les filtres, pas la période', (tester) async {
      await vente('credit', total: 10000, mode: 'credit', client: solange, quand: DateTime(2026, 10, 2));
      await vente('mobile', total: 20000, mode: 'mobile_money', client: koffi, quand: DateTime(2026, 10, 3));
      await vente('annulee', total: 40000, statut: 'annulee', quand: DateTime(2026, 10, 4));
      await monter(tester, exercice: await exercice());

      await choisir(tester, 'filtre-statut', 'En attente');
      expect(find.byKey(const Key('vente-0')), findsOneWidget);
      expect(find.byKey(const Key('vente-1')), findsNothing);
      expect(find.text('Crédit client'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reinitialiser')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vente-2')), findsOneWidget);

      await choisir(tester, 'filtre-mode', 'Mobile Money');
      expect(find.byKey(const Key('vente-1')), findsNothing);
      expect(find.text('Mobile Money'), findsWidgets);

      await tester.tap(find.byKey(const Key('reinitialiser')));
      await tester.pumpAndSettle();
      await choisir(tester, 'filtre-client', 'ADJOVI Koffi');
      expect(find.byKey(const Key('vente-0')), findsOneWidget);
      expect(find.byKey(const Key('vente-1')), findsNothing);
    });

    testWidgets('le filtre de mode propose les cinq modes du Blade, dont « Avance »', (tester) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('filtre-mode')));
      await tester.pumpAndSettle();

      for (final mode in ['Mode : Tous', 'Espèces', 'Mobile Money', 'Virement', 'Crédit client', 'Avance']) {
        expect(find.text(mode), findsWidgets, reason: mode);
      }
    });

    testWidgets('⚠️⚠️ la période : deux champs Date de l\'exercice ; la changer recalcule les cartes, jamais le tableau', (tester) async {
      await vente('a', total: 32000, quand: DateTime(2026, 10, 2, 9));
      await vente('b', total: 48000, quand: DateTime(2026, 10, 15, 8));
      await monter(tester, exercice: await exercice());

      expect(find.text('01/10/2026'), findsOneWidget);
      expect(find.text('21/10/2026'), findsOneWidget);
      String ca() => tester
          .widgetList<Text>(find.descendant(of: find.byKey(const Key("kpi-Chiffre d'Affaires")), matching: find.byType(Text)))
          .map((t) => t.data)
          .join('|');
      expect(ca(), contains('80 000'));

      await tester.tap(find.byKey(const Key('date-debut')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('3')));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('03/10/2026'), findsOneWidget, reason: 'le début de période est choisi dans le calendrier');
      expect(ca(), contains('48 000'), reason: 'la vente du 2 sort de la période');
      expect(find.byKey(const Key('vente-1')), findsOneWidget, reason: 'le tableau ne suit pas la période, mais l\'exercice');
    });

    testWidgets('une fin de période avant le début ramène le début sur elle (début ≤ fin)', (tester) async {
      await vente('a', total: 32000, quand: DateTime(2026, 10, 2, 9));
      await monter(tester, exercice: await exercice());

      await tester.tap(find.byKey(const Key('date-fin')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('1')).first);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('01/10/2026'), findsNWidgets(2));
    });

    testWidgets('« Voir » ouvre le tiroir de détail : référence, client, date, articles, sous-total, remise, total, boutons', (tester) async {
      await vente('a', total: 9000, remise: 1000, client: solange, articles: 2, quand: DateTime(2026, 10, 20, 15, 30));
      await monter(tester, exercice: await exercice());

      await tester.tap(find.byKey(Key('vente-voir-${uuid('a')}')));
      await tester.pumpAndSettle();

      final tiroir = find.byKey(const Key('tiroir-detail'));
      expect(tiroir, findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('tiroir-reference'))).data, uuid('a').substring(0, 8).toUpperCase());
      for (final texte in [
        'Client', 'GBAGUIDI Solange', 'Date', '20/10/2026 15:30', 'ARTICLES',
        "Plaquette d'œufs × 2.5", 'Vitamines × 1', '4 500 FCFA',
        'Sous-total', '10 000 FCFA', 'Remise', '1 000 FCFA', 'Total', '9 000 FCFA',
        'Télécharger PDF', 'Fermer',
      ]) {
        expect(find.descendant(of: tiroir, matching: find.text(texte)), findsWidgets, reason: texte);
      }
    });

    testWidgets('le tiroir se ferme par « Fermer », par le ✕, par le voile et par Échap', (tester) async {
      await vente('a', total: 9000);
      await monter(tester, exercice: await exercice());

      Future<void> ouvrir() async {
        await tester.tap(find.byKey(Key('vente-ref-${uuid('a')}')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('tiroir-detail')), findsOneWidget);
      }

      await ouvrir();
      await tester.tap(find.byKey(const Key('tiroir-fermer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tiroir-detail')), findsNothing);

      await ouvrir();
      await tester.tap(find.byKey(const Key('tiroir-fermer-x')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tiroir-detail')), findsNothing);

      await ouvrir();
      await tester.tapAt(const Offset(100, 300));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tiroir-detail')), findsNothing);

      await ouvrir();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tiroir-detail')), findsNothing);
    });

    testWidgets('⚠️⚠️ « Télécharger PDF » : le ticket du serveur est enregistré, le chemin est dit', (tester) async {
      await vente('a', total: 9000);
      final client = _ClientVentes((_) async => PdfRecu(octets: Uint8List.fromList([1, 2, 3]), fichier: 'vente-BBBBBBBB.pdf'));
      await monter(tester, exercice: await exercice(), depotInjecte: HistoriqueVentesRepository(database: db, client: client));
      await tester.tap(find.byKey(Key('vente-voir-${uuid('a')}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tiroir-pdf')));
      await tester.pumpAndSettle();

      expect(client.demandes, [uuid('a')]);
      expect(enregistres.single.fichier, 'vente-BBBBBBBB.pdf');
      expect(find.textContaining(r'Ticket enregistré : C:\Users\Caisse\Documents\AgriERP\vente-BBBBBBBB.pdf'), findsOneWidget);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('« Télécharger PDF » hors ligne : la phrase du serveur ou du réseau, jamais une exception brute', (tester) async {
      await vente('a', total: 9000);
      final client = _ClientVentes((_) async => throw const EchecTicketVente('Serveur injoignable. Cet export nécessite le réseau : réessayez une fois connecté.'));
      await monter(tester, exercice: await exercice(), depotInjecte: HistoriqueVentesRepository(database: db, client: client));
      await tester.tap(find.byKey(Key('vente-voir-${uuid('a')}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tiroir-pdf')));
      await tester.pumpAndSettle();

      expect(find.text('Serveur injoignable. Cet export nécessite le réseau : réessayez une fois connecté.'), findsOneWidget);
      expect(enregistres, isEmpty);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('sans export-ventes : le ticket est refusé', (tester) async {
      await vente('a', total: 9000);
      final client = _ClientVentes((_) async => throw StateError('ne doit pas être appelé'));
      await monter(tester, exercice: await exercice(), peutExporter: false, depotInjecte: HistoriqueVentesRepository(database: db, client: client));
      await tester.tap(find.byKey(Key('vente-voir-${uuid('a')}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tiroir-pdf')));
      await tester.pumpAndSettle();

      expect(client.demandes, isEmpty);
      expect(find.text("Votre rôle ne permet pas d'exporter le ticket d'une vente."), findsOneWidget);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('⚠️⚠️ « Annuler » : la modale du Blade, puis « Oui, Annuler la Vente » — la vente passe à Annulée, toast d\'avertissement', (tester) async {
      await vente('a', total: 9000);
      await monter(tester, exercice: await exercice());

      await tester.tap(find.byKey(Key('vente-annuler-${uuid('a')}')));
      await tester.pumpAndSettle();

      expect(find.text('Annuler cette vente ?'), findsOneWidget);
      expect(
        find.text('Le stock des produits vendus sera automatiquement réintégré. Cette action est réversible uniquement en recréant une nouvelle vente.'),
        findsOneWidget,
      );
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text('Oui, Annuler la Vente'), findsOneWidget);

      await tester.tap(find.byKey(const Key('annulation-confirmer')));
      await tester.pumpAndSettle();

      final v = await (db.select(db.sales)..where((s) => s.id.equals(uuid('a')))).getSingle();
      expect(v.status, 'annulee');
      expect(v.syncStatus, SyncStatus.pending);
      expect(find.text('Vente annulée — le stock sera réintégré à la synchronisation.'), findsOneWidget);
      expect(find.text('Annulée'), findsOneWidget);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('« Annuler » dans la modale referme sans rien écrire', (tester) async {
      await vente('a', total: 9000);
      await monter(tester, exercice: await exercice());
      await tester.tap(find.byKey(Key('vente-annuler-${uuid('a')}')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(find.text('Annuler cette vente ?'), findsNothing);
      expect((await (db.select(db.sales)..where((s) => s.id.equals(uuid('a')))).getSingle()).status, 'validee');
    });

    testWidgets('sans manage-ventes : « Votre rôle ne permet pas cette action. », rien n\'est écrit', (tester) async {
      await vente('a', total: 9000);
      await monter(tester, exercice: await exercice(), peutGerer: false);
      await tester.tap(find.byKey(Key('vente-annuler-${uuid('a')}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('annulation-confirmer')));
      await tester.pumpAndSettle();

      expect(find.text('Votre rôle ne permet pas cette action.'), findsOneWidget);
      expect((await (db.select(db.sales)..where((s) => s.id.equals(uuid('a')))).getSingle()).status, 'validee');
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('⚠️⚠️ @lectureSeule : exercice clos, « Annuler » est grisé (et « Voir » reste ouvert)', (tester) async {
      await vente('a', total: 9000);
      await monter(tester, exercice: await exercice(clos: true));

      final bouton = tester.widget<IconButton>(find.byKey(Key('vente-annuler-${uuid('a')}')));
      expect(bouton.onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(Key('vente-voir-${uuid('a')}'))).onPressed, isNotNull);
    });
  });
}
