import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/features/ventes/facturation_repository.dart';
import 'package:agrierp/features/ventes/facturation_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.47 — FACTURATION & MeCeF (`facturation.html`).
///
/// ⚠️⚠️ **UNE FACTURE EST UNE VENTE.** Il n'existe pas de table `invoices` :
/// `sales.mecef_status` et `sales.mecef_qr_ref` portent la normalisation
/// fiscale auprès de la DGI.
///
/// ⚠️⚠️ **CE QUE CET ÉCRAN A RÉVÉLÉ** : le canal d'envoi hors ligne appliquait
/// les quatre effets d'une vente et **oubliait la transmission MeCeF** que la
/// caisse web fait systématiquement. Toute vente encaissée sans réseau arrivait
/// donc sur le serveur sans QR ni déclaration. Corrigé au ticket 14.80 ; ici on
/// vérifie que l'écran rend la situation VISIBLE, facture par facture.
void main() {
  late AppDatabase db;
  late FacturationRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final aujourdhui = DateTime.now();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = FacturationRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> facture(
    String cle, {
    required double total,
    String? statutMecef,
    String? refMecef,
    String? client,
    DateTime? date,
    bool envoyee = true,
  }) => db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          id: uuid(cle),
          deviceId: envoyee ? 'serveur' : 'poste-test',
          updatedAt: date ?? aujourdhui,
          syncStatus: Value(envoyee ? SyncStatus.synced : SyncStatus.pending),
          customerName: Value(client),
          paymentMode: 'especes',
          total: total,
          mecefStatus: Value(statutMecef),
          mecefQrRef: Value(refMecef),
          soldAt: date ?? aujourdhui,
        ),
      );

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(MaterialApp(home: FacturationScreen(depot: depot)));
    await tester.pumpAndSettle();
  }

  group('dépôt', () {
    /// ⚠️⚠️ LE CŒUR DU TICKET : un statut nul n'est PAS « en attente ».
    test(
      '⚠️⚠️ une facture jamais transmise se distingue d une transmission en cours',
      () async {
        await facture('f1', total: 1000, statutMecef: null);
        await facture('f2', total: 2000, statutMecef: 'en_attente');

        final d = await depot.charger();

        expect(d.compte(StatutMecef.jamais), 1);
        expect(d.compte(StatutMecef.enAttente), 1);
      },
    );

    test('les quatre statuts de la maquette sont reconnus', () {
      expect(StatutMecef.depuis('transmise').libelle, 'Transmise');
      expect(StatutMecef.depuis('en_attente').libelle, 'En attente');
      expect(StatutMecef.depuis('erreur').libelle, 'Erreur MeCeF');
      expect(StatutMecef.depuis(null).libelle, 'Non transmise');
    });

    test('les indicateurs ne comptent que le mois affiché', () async {
      await facture('f1', total: 1000);
      await facture(
        'vieille',
        total: 9000,
        date: DateTime(aujourdhui.year - 1, 3, 12),
      );

      final d = await depot.charger();

      expect(d.duMois.length, 1);
      expect(d.montantDuMois, 1000);
      expect(d.factures.length, 2);
    });

    /// ⚠️ Une vente encore au poste n'a pas pu être transmise : personne n'a
    /// essayé, et c'est un compte à part.
    test('⚠️ les factures pas encore envoyées sont comptées à part', () async {
      await facture('locale', total: 5000, envoyee: false);
      await facture('serveur', total: 5000, statutMecef: 'transmise');

      final d = await depot.charger();

      expect(d.enAttenteDEnvoi, 1);
    });

    test('une vente sans client est nommée « Client de passage »', () async {
      await facture('f1', total: 1000);

      final d = await depot.charger();

      expect(d.factures.single.client, 'Client de passage');
    });
  });

  group('écran', () {
    testWidgets('les six colonnes de la maquette sont là', (tester) async {
      await afficher(tester);

      for (final colonne in [
        'N° FACTURE',
        'CLIENT',
        'DATE',
        'MONTANT TTC',
        'STATUT MECEF',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    /// ⚠️⚠️ **LE NOMBRE DE CARTES, PAS SEULEMENT LEURS LIBELLÉS** (ticket
    /// F0.54). `cartesMaquette` est relevé sur la maquette (`border-l-4`) :
    /// il fait foi sur le nombre, quel que soit le nombre de libellés que le
    /// contrôle voisin énumère.
    testWidgets('⚠️⚠️ l écran rend le nombre de cartes de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      expect(
        find.byType(CarteKpi),
        findsNWidgets(cartesAttendues('facturation.html')),
      );
    });

    testWidgets('les quatre indicateurs de la maquette sont là', (
      tester,
    ) async {
      await afficher(tester);

      for (final kpi in [
        'FACTURES (MOIS)',
        'STATUT "TRANSMISE"',
        'EN ATTENTE',
        'ERREUR MECEF',
      ]) {
        expect(find.text(kpi), findsOneWidget, reason: kpi);
      }
    });

    /// ⚠️⚠️ LA COLONNE QUI REND LE TROU FISCAL VISIBLE.
    testWidgets('⚠️⚠️ une vente pas encore envoyée le dit dans son statut', (
      tester,
    ) async {
      await facture(
        'locale',
        total: 5000,
        envoyee: false,
        client: 'AMOUSSOU Régis',
      );

      await afficher(tester);

      expect(find.text('Vente pas encore envoyée'), findsOneWidget);
      expect(
        find.textContaining('1 facture(s) pas encore envoyée(s)'),
        findsOneWidget,
      );
    });

    testWidgets('une facture transmise porte sa référence MeCeF', (
      tester,
    ) async {
      await facture(
        'f1',
        total: 14646,
        statutMecef: 'transmise',
        refMecef: 'MECEF-9B554B3BBF18',
        client: 'GBAGUIDI Solange',
      );

      await afficher(tester);

      expect(find.text('MECEF-9B554B3BBF18'), findsOneWidget);
      expect(find.text('Transmise'), findsWidgets);
      expect(find.text('14 646'), findsOneWidget);
      expect(find.text('GBAGUIDI Solange'), findsOneWidget);
    });

    /// ⚠️⚠️ AUCUN NUMÉRO DE FACTURE N'EXISTE DANS LE SCHÉMA : la maquette
    /// affiche « FAC-2026-0042 », `sales` n'a pas de colonne pour ça.
    testWidgets('⚠️⚠️ sans référence MeCeF, la colonne porte un tiret', (
      tester,
    ) async {
      await facture('f1', total: 1000, statutMecef: null);

      await afficher(tester);

      expect(find.text('—'), findsWidgets);
      expect(find.textContaining('FAC-'), findsNothing);
    });

    testWidgets('le filtre de statut restreint la liste', (tester) async {
      await facture('ok', total: 1000, statutMecef: 'transmise', refMecef: 'A');
      await facture('ko', total: 2000, statutMecef: 'erreur');

      await afficher(tester);
      expect(find.text('1 000'), findsOneWidget);
      expect(find.text('2 000'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filtre-Erreur MeCeF')));
      await tester.pumpAndSettle();

      expect(find.text('2 000'), findsOneWidget);
      expect(find.text('1 000'), findsNothing);
    });

    /// ⚠️ Le QR n'est pas dessiné : sa référence est affichée, et l'écran dit
    /// pourquoi.
    testWidgets(
      '⚠️ la facture normalisée montre sa référence, pas un faux QR',
      (tester) async {
        await facture(
          'f1',
          total: 5000,
          statutMecef: 'transmise',
          refMecef: 'NIM-20260824-ABCD1234|SIG',
          client: 'AMOUSSOU Régis',
        );

        await afficher(tester);
        await tester.tap(find.byKey(const Key('voir-facture-0')));
        await tester.pumpAndSettle();

        expect(find.text('Facture Normalisee MeCeF'), findsOneWidget);
        // ⚠️ La reference figure DEUX fois : colonne « N° Facture » et modale.
        expect(find.text('NIM-20260824-ABCD1234|SIG'), findsWidgets);
        expect(
          find.textContaining('produit par le dispositif MeCeF'),
          findsOneWidget,
        );
      },
    );

    /// ⚠️⚠️ Le formulaire « Nouvelle Facture » de la maquette créerait une
    /// facture sans article ni stock : le bouton mène à la caisse.
    testWidgets('⚠️⚠️ « Nouvelle Facture » mène à la caisse', (tester) async {
      var ouvert = false;

      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: FacturationScreen(
            depot: depot,
            onOuvrirCaisse: () => ouvert = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nouvelle-facture')));
      await tester.pumpAndSettle();

      expect(ouvert, isTrue);
    });

    testWidgets('l écran dit qui transmet à la DGI', (tester) async {
      await afficher(tester);

      expect(
        find.textContaining(
          'La transmission au dispositif MeCeF est faite '
          'par le serveur',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sans facture, le tableau le dit', (tester) async {
      await afficher(tester);

      expect(find.text('— Aucune facture pour ces critères —'), findsOneWidget);
    });
  });

  group('VC-5 · sans MeCeF', () {
    Future<void> afficherSansMecef(WidgetTester tester, {List<String>? documents}) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await depot.definirMecefActif(false);
      await tester.pumpWidget(
        MaterialApp(
          home: FacturationScreen(
            depot: depot,
            imprimer: (doc, maintenant) async {
              documents?.add(doc.titre);
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    test('le module est désactivé par défaut au poste de l\'application, activé pour les tests, et le serveur le dit', () async {
      expect(await FacturationRepository(database: db, mecefParDefaut: false).mecefActif(), isFalse);
      expect(await depot.mecefActif(), isTrue);
      await depot.definirMecefActif(false);
      expect(await depot.mecefActif(), isFalse);
      await depot.definirMecefActif(true);
      expect(await depot.mecefActif(), isTrue);
    });

    testWidgets('⚠️ la facturation reste utilisable : registre, trois cartes, numéro FV-AAAA-XXXXXX, aucune colonne ni filtre MeCeF', (tester) async {
      await facture('abcdef12', total: 12500, client: 'AMOUSSOU Régis');
      await afficherSansMecef(tester);

      expect(find.text('Facturation'), findsOneWidget);
      expect(find.text('Facturation & MeCeF'), findsNothing);
      expect(find.text('Montant facturé (mois)'.toUpperCase()), findsOneWidget);
      expect(find.text('Clients facturés (mois)'.toUpperCase()), findsOneWidget);
      expect(find.text('Statut MeCeF'.toUpperCase()), findsNothing);
      expect(find.byKey(const Key('filtre-Transmise')), findsNothing);
      expect(find.text('FV-${aujourdhui.year}-ABCDEF'), findsOneWidget);
      expect(find.byKey(const Key('voir-facture-0')), findsNothing);
    });

    testWidgets('« Imprimer la facture » produit le document au poste, hors ligne', (tester) async {
      await facture('abcdef12', total: 12500, client: 'AMOUSSOU Régis');
      final imprimes = <String>[];
      await afficherSansMecef(tester, documents: imprimes);

      await tester.tap(find.byKey(const Key('imprimer-facture-0')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();

      expect(imprimes, ['Facture FV-${aujourdhui.year}-ABCDEF']);
    });

    test('la facture porte lignes, total et la mention du web, avec ou sans référence MeCeF', () async {
      await facture('abcdef12', total: 8000, client: 'GBAGUIDI Solange');
      await db.into(db.products).insert(ProductsCompanion.insert(id: uuid('prod'), sku: 'OEUF', name: 'Oeufs de table', unit: 'plateau', pricingMode: 'fixe'));
      await db.into(db.saleLines).insert(SaleLinesCompanion.insert(id: uuid('ligne'), saleId: uuid('abcdef12'), productId: uuid('prod'), qty: 4, unitPrice: 2000, manualTotalAmount: 8000));

      final doc = (await depot.documentFacture(uuid('abcdef12')))!;
      expect(doc.noteDePied, 'Facture émise sans certification MeCeF.');
      final textes = [for (final l in doc.lignes) if (l is DonneesDocument) l.cellules.join('|') else if (l is TotalDocument) l.cellules.join('|')];
      expect(textes, ['Oeufs de table|4|2 000|8 000', 'Total TTC|||8 000']);

      await (db.update(db.sales)..where((s) => s.id.equals(uuid('abcdef12')))).write(const SalesCompanion(mecefStatus: Value('transmise'), mecefQrRef: Value('REF-9')));
      expect((await depot.documentFacture(uuid('abcdef12')))!.noteDePied, 'Facture normalisée MeCeF — référence : REF-9');
    });
  });
}
