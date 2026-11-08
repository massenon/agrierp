import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/features/ventes/choix_facture.dart';
import 'package:agrierp/features/ventes/facturation_repository.dart';
import 'package:agrierp/features/ventes/facturation_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MECEF-3 — l'écran Facturation et la facture PDF du poste : le statut MeCeF ne concerne que les factures NORMALISÉES (les
/// simples affichent « Facture simple », filtre « Facture simple »), la facture imprime IFU, nom du client et AIB quand elle est
/// normalisée, la mention « Facture simple — non normalisée DGI » sinon ; les frais de livraison inclus sont une ligne du total.
void main() {
  late AppDatabase db;
  late FacturationRepository depot;
  final aujourdhui = DateTime.now();

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FacturationRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> vente(
    String cle, {
    String? type,
    String? statut,
    double total = 10000,
    String? ifu,
    String? nom,
    String? aib,
    double? aibMontant,
    double livraison = 0,
    bool livraisonIncluse = false,
    bool envoyee = true,
  }) => db.into(db.sales).insert(
    SalesCompanion.insert(
      id: uuid(cle), deviceId: envoyee ? 'serveur' : 'poste-test', updatedAt: aujourdhui,
      syncStatus: Value(envoyee ? SyncStatus.synced : SyncStatus.pending), customerName: const Value('GBAGUIDI Solange'),
      paymentMode: 'especes', total: total, soldAt: aujourdhui,
      factureType: Value(type), mecefStatus: Value(statut), clientIfu: Value(ifu), clientNomFacture: Value(nom), aibTaux: Value(aib),
      mecefAibMontant: Value(aibMontant), deliveryFee: Value(livraison), deliveryInTotal: Value(livraisonIncluse),
    ),
  );

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: FacturationScreen(depot: depot)));
    await tester.pumpAndSettle();
  }

  group('dépôt', () {
    test('simple par défaut (vente d\'avant le choix comprise) ; normalisée par choix ou parce que déjà normalisée', () async {
      await vente('sansChoix');
      await vente('simple', type: 'simple');
      await vente('demandee', type: 'normalisee', statut: 'en_attente');
      await vente('ancienne', statut: 'transmise');
      final d = await depot.charger();
      final par = {for (final f in d.factures) f.vente.id.substring(0, 6): f};

      expect([par['sansCh']!.simple, par['simple']!.simple, par['demand']!.declaree, par['ancien']!.declaree], [true, true, true, true]);
    });

    test('⚠️ les indicateurs de statut ne comptent QUE les normalisées', () async {
      await vente('simple', type: 'simple', statut: 'en_attente');
      await vente('demandee', type: 'normalisee', statut: 'en_attente');
      await vente('refusee', type: 'normalisee', statut: 'erreur');
      final d = await depot.charger();

      expect([d.compte(StatutMecef.enAttente), d.compte(StatutMecef.erreur), d.duMois.length], [1, 1, 3]);
    });
  });

  group('écran', () {
    testWidgets('⚠️ « Facture simple » : pastille, filtre « Facture simple », pas de statut MeCeF', (tester) async {
      await vente('simple', type: 'simple', total: 1111);
      await vente('demandee', type: 'normalisee', statut: 'en_attente', total: 2222);
      await afficher(tester);

      expect(find.text('Facture simple'), findsNWidgets(2), reason: 'la pastille de la ligne, et le filtre');
      expect(find.byKey(const Key('filtre-Facture simple')), findsOneWidget);

      await tester.tap(find.byKey(const Key('filtre-Facture simple')));
      await tester.pumpAndSettle();
      expect(find.text('1 111'), findsOneWidget);
      expect(find.text('2 222'), findsNothing);

      await tester.tap(find.byKey(const Key('filtre-En attente')));
      await tester.pumpAndSettle();
      expect(find.text('2 222'), findsOneWidget);
      expect(find.text('1 111'), findsNothing, reason: 'les statuts MeCeF ne portent que sur les normalisées');
    });

    testWidgets('l\'ordre des filtres est celui du web (Tous, Facture simple, puis les statuts)', (tester) async {
      await afficher(tester);
      final x = ['Tous les statuts', 'Facture simple', 'Normalisée', 'En attente', 'Refusée', 'Expirée']
          .map((f) => tester.getTopLeft(find.byKey(Key('filtre-$f'))).dx)
          .toList();
      expect(x, [...x]..sort());
    });

    testWidgets('une normalisée demandée, pas encore envoyée : « demandée — en attente » jusqu\'au tirage', (tester) async {
      await vente('locale', type: 'normalisee', envoyee: false);
      await afficher(tester);

      expect(find.text(ChoixFacture.mentionEnAttente), findsOneWidget);
    });
  });

  group('facture PDF', () {
    Future<DocumentOfficiel> doc(String cle) async => (await depot.documentFacture(uuid(cle)))!;

    String sousTitre(DocumentOfficiel d) => d.sousTitre;

    test('⚠️ normalisée : nom, IFU et AIB du client (montant calculé par la DGI) ; simple : la mention et rien d\'autre', () async {
      await vente('norm', type: 'normalisee', statut: 'transmise', ifu: '3202601234567', nom: 'KPOGNON Séraphin', aib: '5%', aibMontant: 590);
      await db.update(db.sales).write(const SalesCompanion(mecefQrRef: Value('F;ED01;CODE;ifu;date'), mecefCode: Value('CODE-DGI')));
      await vente('simple', type: 'simple');

      final n = await doc('norm');
      expect(sousTitre(n), contains('Client : KPOGNON Séraphin'));
      expect(sousTitre(n), contains('IFU du client : 3202601234567'));
      expect(sousTitre(n), contains('AIB : 5 % (montant calculé par la DGI : 590 FCFA)'));
      expect(n.mentions, contains('Code MeCeF/DGI : CODE-DGI'));
      expect(n.codeQr, isNotNull);

      final s = await doc('simple');
      expect(s.noteDePied, ChoixFacture.mentionSimple);
      expect(sousTitre(s), isNot(contains('IFU')));
      expect(sousTitre(s), isNot(contains('AIB')));
      expect(s.codeQr, isNull);
      // CONF-3 (DV-22) : le mode de règlement est un LIBELLÉ, jamais la clé stockée.
      expect(sousTitre(s), contains('Mode de règlement : '));
      expect(sousTitre(s), isNot(contains('especes')));
    });

    test('un client sans IFU : pas de ligne IFU ; AIB « Aucun (N/A) » dit tel quel', () async {
      await vente('norm', type: 'normalisee', statut: 'en_attente', nom: 'Madame ADJOVI', aib: 'N/A');

      final d = await doc('norm');
      expect(sousTitre(d), contains('Client : Madame ADJOVI'));
      expect(sousTitre(d), isNot(contains('IFU du client')));
      expect(sousTitre(d), contains('AIB : Aucun (N/A)'));
      expect(d.noteDePied, ChoixFacture.mentionEnAttente);
    });

    test('⚠️ frais de livraison inclus : une ligne comprise dans le total ; hors total (anciennes ventes) : aucune ligne', () async {
      await db.into(db.products).insert(ProductsCompanion.insert(id: uuid('prod'), sku: 'OEUF', name: 'Oeufs', unit: 'u', pricingMode: 'fixe'));
      for (final (cle, incluse, total) in [('incl', true, 14300.0), ('hors', false, 11800.0)]) {
        await vente(cle, type: 'simple', total: total, livraison: 2500, livraisonIncluse: incluse);
        await db.into(db.saleLines).insert(SaleLinesCompanion.insert(
          id: uuid('l$cle'), saleId: uuid(cle), productId: uuid('prod'), qty: 2, unitPrice: 5900, manualTotalAmount: 11800,
        ));
      }

      String ligne(DocumentOfficiel d) => [for (final l in d.lignes) if (l is DonneesDocument) l.cellules.join('|') else if (l is TotalDocument) l.cellules.join('|')].join(' ; ');

      expect(ligne(await doc('incl')), 'Oeufs|2|5 900|11 800 ; Frais de livraison|1|2 500|2 500 ; Total TTC|||14 300');
      expect(ligne(await doc('hors')), 'Oeufs|2|5 900|11 800 ; Total TTC|||11 800');
    });
  });
}
