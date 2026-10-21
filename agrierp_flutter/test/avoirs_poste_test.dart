import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/ventes/avoirs_repository.dart';
import 'package:agrierp/features/ventes/retours_avoirs_onglet.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


/// Tickets AV1 — ONGLET « RETOURS ET AVOIRS » DU POSTE (`retours-avoirs.blade.php`, `Livewire\Ventes\RetoursAvoirs`).
///
/// ⚠️⚠️ CE QUE CES TESTS PROTÈGENT. Le poste n'enregistre que la DEMANDE : une ligne `credit_notes` en attente d'envoi, JAMAIS
/// un ajustement de stock ni une écriture (le serveur les fait, `AvoirClientService`). Les refus du serveur (quantité au-delà
/// du vendu moins le déjà retourné, montant au-delà de la ligne moins le déjà crédité, vente annulée, produit hors vente,
/// exercice clos) sont reproduits AVANT d'écrire, avec les mêmes messages. Les chiffres attendus sont des littéraux calculés
/// à la main : vente de 10 plaquettes à 5 900 (59 000) + 4 sachets de vitamines à 5 000 (20 000).
///
/// Écrits AVANT l'écran (rouge d'abord) : épreuve de mutation (retirer un contrôle de `_reglesDeRetour`, la protection
/// `pending`, le statut `traite`) dans le rapport du ticket.
void main() {
  late AppDatabase db;
  late AvoirsRepository depot;

  const oeufs = 'aaaaaaaa-0000-4000-8000-000000000001';
  const vitamines = 'aaaaaaaa-0000-4000-8000-000000000002';
  const client = 'cccccccc-0000-4000-8000-000000000001';
  const vente1 = 'bbbbbbbb-1111-4000-8000-000000000001';
  const vente2 = 'bbbbbbbb-2222-4000-8000-000000000002';

  /// Mercredi 21/10/2026, 10 h au Bénin : le jour du poste de tous les tests.
  final maintenant = DateTime(2026, 10, 21, 10);

  /// Une vente de 10 plaquettes (59 000) et 4 sachets (20 000) : 79 000.
  Future<void> vendre(
    String id,
    DateTime quand, {
    String? client,
    String statut = 'validee',
    SyncStatus synchro = SyncStatus.synced,
  }) async {
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: id,
        deviceId: 'serveur',
        syncStatus: Value(synchro),
        updatedAt: quand,
        customerId: Value(client),
        paymentMode: 'especes',
        subtotal: const Value(79000),
        total: 79000,
        status: Value(statut),
        soldAt: quand,
      ),
    );
    await db.into(db.saleLines).insert(
      SaleLinesCompanion.insert(
        id: '${id.substring(0, 24)}000000000a01',
        saleId: id,
        productId: oeufs,
        qty: 10,
        unitPrice: 5900,
        manualTotalAmount: 59000,
      ),
    );
    await db.into(db.saleLines).insert(
      SaleLinesCompanion.insert(
        id: '${id.substring(0, 24)}000000000a02',
        saleId: id,
        productId: vitamines,
        qty: 4,
        unitPrice: 5000,
        manualTotalAmount: 20000,
      ),
    );
  }

  Future<void> avoir(
    String id, {
    String vente = vente1,
    String produit = oeufs,
    double qty = 2,
    double montant = 11800,
    String decision = 'reintegre',
    String statut = 'en_attente',
    SyncStatus synchro = SyncStatus.synced,
    String? numero = 'AV-2026-001',
    DateTime? le,
  }) => db.into(db.creditNotes).insert(
    CreditNotesCompanion.insert(
      id: id,
      deviceId: synchro == SyncStatus.synced ? 'serveur' : 'poste-test',
      syncStatus: Value(synchro),
      updatedAt: maintenant,
      saleId: vente,
      productId: produit,
      creditNoteNumber: Value(numero),
      qty: Value(qty),
      amount: montant,
      reason: const Value('Plaquette détériorée'),
      decision: Value(decision),
      status: Value(statut),
      createdAt: le ?? DateTime(2026, 10, 21, 9),
    ),
  );

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = AvoirsRepository(database: db, identifiantPoste: 'poste-test', horloge: () => maintenant);

    for (final (id, sku, nom, unite) in [
      (oeufs, 'OEUF', "Plaquette d'œufs", 'plaquette'),
      (vitamines, 'VIT', 'Vitamines', 'sachet'),
    ]) {
      await db.into(db.products).insert(
        ProductsCompanion.insert(id: id, sku: sku, name: nom, unit: unite, pricingMode: 'fourchette'),
      );
    }
    await db.into(db.customers).insert(CustomersCompanion.insert(id: client, name: 'GBAGUIDI Solange'));
    await db.into(db.fiscalYears).insert(
      FiscalYearsCompanion.insert(
        id: 'eeeeeeee-2026-4000-8000-000000000001',
        year: 2026,
        startDate: Value(DateTime(2026)),
        endDate: Value(DateTime(2026, 12, 31)),
        status: const Value('ouvert'),
      ),
    );
    await vendre(vente1, DateTime(2026, 10, 20, 15), client: client);
  });

  tearDown(() async {
    ToastAgri.toutRetirer();
    await db.close();
  });

  // ── Le dépôt : cartes, tableau, refus, écriture ────────────────────────────────────────────────────────────────────────

  group('cartes (RetoursAvoirs::getKpisProperty)', () {
    test('sans avoir : zéros, et un taux de 0,0 sans jamais diviser par zéro', () async {
      await db.delete(db.sales).go();
      final k = (await depot.charger()).kpis;

      expect(k.retoursDuMois, 0);
      expect(k.montantAvoirs, 0);
      expect(k.produitsRetournes, 0);
      expect(k.tauxRetour, 0.0);
    });

    test('les avoirs et les ventes validées DU MOIS : 3 avoirs en octobre, 1 en septembre, 7 ventes validées + 1 annulée', () async {
      await avoir(uuid('a1'), qty: 2.5, montant: 11800);
      await avoir(uuid('a2'), qty: 1, montant: 5900, numero: 'AV-2026-002');
      await avoir(uuid('a3'), qty: 1, montant: 1000, numero: 'AV-2026-003', le: DateTime(2026, 10, 1));
      await avoir(uuid('a4'), qty: 9, montant: 99999, numero: 'AV-2026-004', le: DateTime(2026, 9, 30));
      for (var i = 2; i <= 7; i++) {
        await vendre(uuid('bbbbbbbb-$i'), DateTime(2026, 10, i));
      }
      await vendre(uuid('bbbbbbbb-annulee'), DateTime(2026, 10, 9), statut: 'annulee');
      await vendre(uuid('bbbbbbbb-septembre'), DateTime(2026, 9, 28));

      final k = (await depot.charger()).kpis;

      expect(k.retoursDuMois, 3, reason: 'le mois courant seulement');
      expect(k.montantAvoirs, 18700, reason: '11 800 + 5 900 + 1 000');
      // ⚠️ `(int) sum('qty')` : 2,5 + 1 + 1 = 4,5 → 4 (tronqué, pas arrondi).
      expect(k.produitsRetournes, 4);
      // 7 ventes validées d'octobre (la première + six) : 3 / 7 × 100 = 42,857 → 42,9.
      expect(k.tauxRetour, 42.9);
    });

    test('une demande refusée par le serveur n existe pas côté ferme : elle ne compte pas', () async {
      await avoir(uuid('a1'));
      await avoir(uuid('a2'), numero: null, synchro: SyncStatus.conflict, montant: 5000);

      final k = (await depot.charger()).kpis;

      expect(k.retoursDuMois, 1);
      expect(k.montantAvoirs, 11800);
    });
  });

  group('tableau', () {
    test('les avoirs du plus récent au plus ancien, avec facture, client, numéro et motif', () async {
      await avoir(uuid('a1'), le: DateTime(2026, 10, 19, 9));
      await avoir(uuid('a2'), numero: 'AV-2026-002', le: DateTime(2026, 10, 21, 9), montant: 5900, qty: 1);

      final lignes = (await depot.charger()).lignes;

      expect(lignes.map((l) => l.numero), ['AV-2026-002', 'AV-2026-001']);
      expect(lignes.first.facture, 'BBBBBBBB', reason: 'strtoupper(substr(sale_id, 0, 8))');
      expect(lignes.first.client, 'GBAGUIDI Solange');
    });

    test('⚠️ sans client rattaché : « Client Anonyme », comme le web', () async {
      await vendre(vente2, DateTime(2026, 10, 20, 11));
      await avoir(uuid('a1'), vente: vente2);

      expect((await depot.charger()).lignes.single.client, 'Client Anonyme');
    });

    test('⚠️⚠️ une demande saisie ici n a PAS de numéro : « — », jamais un numéro inventé', () async {
      await avoir(uuid('a1'), numero: null, synchro: SyncStatus.pending);

      final l = (await depot.charger()).lignes.single;

      expect(l.numero, '—');
      expect(l.enAttenteDEnvoi, isTrue);
      expect(l.refusee, isFalse);
    });

    test('un refus du serveur garde son motif, mot pour mot', () async {
      await avoir(uuid('a1'), numero: null, synchro: SyncStatus.conflict);
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'credit_notes:${uuid('a1')}',
          sourceTable: 'credit_notes',
          recordId: uuid('a1'),
          reason: "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 21/10/2026.",
          detectedAt: maintenant,
        ),
      );

      final l = (await depot.charger()).lignes.single;

      expect(l.refusee, isTrue);
      expect(l.motifRefus, "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 21/10/2026.");
    });
  });

  group('« Enregistrer le Retour » : les règles du web, reproduites AVANT d\'écrire', () {
    Future<ResultatRetour> retourner({
      String? vente = vente1,
      String? produit = oeufs,
      double? qty = 2,
      double? montant = 11800,
      String motif = 'Plaquette détériorée',
      String decision = 'reintegre',
      String notes = '',
    }) => depot.enregistrer(
      venteId: vente,
      produitId: produit,
      quantite: qty,
      montant: montant,
      motif: motif,
      decision: decision,
      notes: notes,
    );

    test('⚠️⚠️ écrit UNE demande en attente d envoi : ni stock, ni écriture, ni numéro', () async {
      final stock = (await (db.select(db.products)..where((p) => p.id.equals(oeufs))).getSingle()).stockQty;

      final r = await retourner(notes: ' Contrôle visuel effectué, RAS ');

      expect(r.enregistre, isTrue);
      final a = r.avoir!;
      expect(a.id, hasLength(36));
      expect(a.syncStatus, SyncStatus.pending);
      expect(a.deviceId, 'poste-test');
      expect(a.saleId, vente1);
      expect(a.productId, oeufs);
      expect(a.qty, 2);
      expect(a.amount, 11800);
      expect(a.reason, 'Plaquette détériorée');
      expect(a.decision, 'reintegre');
      expect(a.inspectionNotes, ' Contrôle visuel effectué, RAS ');
      expect(a.status, 'en_attente');
      expect(a.creditNoteNumber, isNull, reason: 'AV-AAAA-NNN est attribué par le serveur seul');
      expect(a.createdAt, maintenant, reason: 'le jour du FAIT, heure du Bénin');

      // JAMAIS d'effet au poste : le serveur réintègre le stock et passe l'écriture.
      expect((await (db.select(db.products)..where((p) => p.id.equals(oeufs))).getSingle()).stockQty, stock);
      expect(await db.select(db.stockAdjustments).get(), isEmpty);
      expect(await db.select(db.accountingEntries).get(), isEmpty);
    });

    test('des notes vides ne sont pas écrites', () async {
      expect((await retourner(notes: '   ')).avoir!.inspectionNotes, isNull);
    });

    test('champs obligatoires : un message par champ, ceux de lang/fr/validation.php, rien n est écrit', () async {
      final r = await retourner(vente: null, produit: null, qty: null, montant: null, motif: ' ');

      expect(r.erreurs, {
        'saleId': 'Le champ vente est obligatoire.',
        'productId': 'Le champ produit est obligatoire.',
        'qty': 'Le champ quantité est obligatoire.',
        'amount': 'Le champ montant est obligatoire.',
        'reason': 'Le champ motif est obligatoire.',
      });
      expect(await db.select(db.creditNotes).get(), isEmpty);
    });

    test('quantité minimale 0,01, montant minimal 0, motif de 255 caractères au plus', () async {
      final r = await retourner(qty: 0, montant: -1, motif: 'x' * 256);

      expect(r.erreurs['qty'], 'Le champ quantité doit être au moins égal à 0.01.');
      expect(r.erreurs['amount'], 'Le champ montant doit être au moins égal à 0.');
      expect(r.erreurs['reason'], 'Le champ motif ne doit pas dépasser 255 caractères.');
      expect((await retourner(motif: 'x' * 255)).enregistre, isTrue, reason: '255 passe');
    });

    test('quantité au-delà du vendu : refusée, avec le détail du serveur', () async {
      final r = await retourner(qty: 11, montant: 100);

      expect(
        r.erreurs['qty'],
        'La quantité retournée dépasse ce qui reste retournable : 10 vendu(s), 0 déjà retourné(s), 10 restant(s).',
      );
      expect(await db.select(db.creditNotes).get(), isEmpty);
    });

    test('⚠️⚠️ le déjà retourné se déduit (demandes en attente comprises) ; tout retourné : message dédié', () async {
      expect((await retourner(qty: 6, montant: 35400)).enregistre, isTrue);

      // 10 vendus − 6 retournés = 4 restants (la demande en attente compte).
      final r = await retourner(qty: 5, montant: 100);
      expect(
        r.erreurs['qty'],
        'La quantité retournée dépasse ce qui reste retournable : 10 vendu(s), 6 déjà retourné(s), 4 restant(s).',
      );

      expect((await retourner(qty: 4, montant: 23600)).enregistre, isTrue);
      expect((await retourner(qty: 1, montant: 100)).erreurs['qty'], 'Ce produit a déjà été retourné en totalité sur cette vente.');
    });

    test('⚠️ un avoir déjà reçu du serveur (synced) compte comme une demande en attente', () async {
      await avoir(uuid('a1'), qty: 8, montant: 47200);

      expect((await retourner(qty: 3, montant: 100)).erreurs['qty'], contains('2 restant(s)'));
    });

    test('⚠️ une demande REFUSÉE par le serveur n existe pas côté ferme : elle ne bloque pas une nouvelle saisie', () async {
      await avoir(uuid('a1'), qty: 10, montant: 59000, numero: null, synchro: SyncStatus.conflict);

      expect((await retourner(qty: 10, montant: 59000)).enregistre, isTrue);
    });

    test('montant au-delà de la ligne moins le déjà crédité', () async {
      expect((await retourner(montant: 59001)).erreurs['amount'], contains('dépasse ce qui reste à créditer'));

      expect((await retourner(montant: 50000)).enregistre, isTrue);
      // Reste à créditer : 59 000 − 50 000 = 9 000.
      final r = await retourner(qty: 1, montant: 9001);
      expect(r.erreurs['amount'], "Le montant de l'avoir dépasse ce qui reste à créditer sur cette ligne : 9 000 FCFA.");
      expect((await retourner(qty: 1, montant: 9000)).enregistre, isTrue);
    });

    test('un produit hors vente, une vente annulée ou inconnue sont refusés sous le bon champ', () async {
      expect((await retourner(produit: uuid('autre'))).erreurs, {'productId': 'Ce produit ne figure pas sur cette vente.'});
      expect((await retourner(vente: uuid('inconnue'))).erreurs, {'saleId': 'Cette vente est inconnue.'});

      await (db.update(db.sales)..where((v) => v.id.equals(vente1))).write(const SalesCompanion(status: Value('annulee')));
      expect(
        (await retourner()).erreurs,
        {'saleId': "Cette vente est annulée : aucun retour n'est possible."},
      );
    });

    test('⚠️⚠️ un exercice clos refuse le retour AVANT d écrire, avec le motif R4 du serveur', () async {
      await (db.update(db.fiscalYears)..where((e) => e.year.equals(2026))).write(const FiscalYearsCompanion(status: Value('cloture')));

      final r = await retourner();

      expect(r.refus, "L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 21/10/2026.");
      expect(r.enregistre, isFalse);
      expect(await db.select(db.creditNotes).get(), isEmpty);
    });

    test('« Marquer comme traité » : statut traité, la demande repart, une seule fois', () async {
      await avoir(uuid('a1'));

      expect(await depot.marquerTraite(uuid('a1')), isTrue);

      final a = await (db.select(db.creditNotes)..where((x) => x.id.equals(uuid('a1')))).getSingle();
      expect(a.status, 'traite');
      expect(a.syncStatus, SyncStatus.pending);
      expect(a.deviceId, 'serveur', reason: 'l\'origine de la ligne ne change pas');

      expect(await depot.marquerTraite(uuid('a1')), isFalse, reason: 'déjà traité : rien ne bouge');
    });
  });

  // ── L'écran ────────────────────────────────────────────────────────────────────────────────────────────────────────────

  group('écran', () {
    Future<void> monter(WidgetTester tester, {bool peutGerer = true}) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      HeureBenin.horloge = () => maintenant.subtract(HeureBenin.decalage);
      addTearDown(HeureBenin.reinitialiser);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RetoursAvoirsOnglet(depot: depot, peutGerer: peutGerer)),
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

    Future<void> ouvrirLeFormulaire(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('nouveau-retour')));
      await tester.pumpAndSettle();
    }

    testWidgets("l'en-tête : titre, sous-titre et « Nouveau Retour » du Blade", (tester) async {
      await monter(tester);

      expect(find.text('Retours et Avoirs'), findsOneWidget);
      expect(
        find.text('Gestion des retours produits, avoirs clients et inspection sanitaire du cheptel retourné.'),
        findsOneWidget,
      );
      expect(find.text('Nouveau Retour'), findsOneWidget);
    });

    testWidgets('⚠️⚠️ quatre cartes, libellés et valeurs du Blade : 1 retour, 11 800 FCFA, 2 produits, 14,3 %', (tester) async {
      await avoir(uuid('a1'));
      for (var i = 2; i <= 7; i++) {
        await vendre(uuid('bbbbbbbb-$i'), DateTime(2026, 10, i));
      }
      await monter(tester);

      expect(find.byType(CarteKpi), findsNWidgets(4));
      for (final libelle in ['RETOURS DU MOIS', 'MONTANT AVOIRS', 'PRODUITS RETOURNÉS', 'TAUX DE RETOUR']) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }
      String valeur(String cle) => tester
          .widgetList<Text>(find.descendant(of: find.byKey(Key(cle)), matching: find.byType(Text)))
          .map((t) => t.data)
          .join('|');
      expect(valeur('kpi-Retours du mois'), contains('1'));
      expect(valeur('kpi-Montant Avoirs'), contains('11 800'));
      expect(valeur('kpi-Montant Avoirs'), contains('FCFA'));
      expect(valeur('kpi-Produits Retournés'), contains('2'));
      // 1 retour / 7 ventes validées d'octobre = 14,285… → « 14,3% » (number_format(…, 1, ',', ' ') + « % »).
      expect(valeur('kpi-Taux de Retour'), contains('14,3%'));
    });

    testWidgets('le tableau porte les neuf colonnes du Blade, dans son ordre', (tester) async {
      await monter(tester);

      for (final colonne in ['AVOIR', 'FACTURE', 'CLIENT', 'DATE', 'MOTIF', 'DÉCISION', 'MONTANT', 'STATUT', 'ACTIONS']) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
      final x = [
        for (final c in ['AVOIR', 'FACTURE', 'CLIENT', 'DATE', 'MOTIF', 'DÉCISION', 'MONTANT', 'STATUT', 'ACTIONS'])
          tester.getTopLeft(find.text(c)).dx,
      ];
      expect([...x]..sort(), x, reason: 'les colonnes vont de gauche à droite dans l\'ordre du Blade');
    });

    testWidgets('sans avoir : « Aucun retour pour le moment. »', (tester) async {
      await monter(tester);

      expect(find.text('Aucun retour pour le moment.'), findsOneWidget);
    });

    testWidgets('une ligne : numéro, facture, client, date, motif, décision, montant, statut, action', (tester) async {
      await avoir(uuid('a1'));
      await avoir(uuid('a2'), numero: 'AV-2026-002', decision: 'reforme', statut: 'traite', montant: 5900, qty: 1, le: DateTime(2026, 10, 15));
      await monter(tester);

      final premiere = find.byKey(const Key('avoir-0'));
      for (final texte in ['AV-2026-001', 'BBBBBBBB', 'GBAGUIDI Solange', '21/10/2026', 'Plaquette détériorée', 'Réintégré', '11 800', 'En attente']) {
        expect(find.descendant(of: premiere, matching: find.text(texte)), findsOneWidget, reason: texte);
      }
      final seconde = find.byKey(const Key('avoir-1'));
      for (final texte in ['AV-2026-002', '15/10/2026', 'Réforme', '5 900', 'Traité']) {
        expect(find.descendant(of: seconde, matching: find.text(texte)), findsOneWidget, reason: texte);
      }
      // Le bouton « Marquer comme traité » n'est proposé qu'à un avoir en attente.
      expect(find.byKey(Key('avoir-traite-${uuid('a1')}')), findsOneWidget);
      expect(find.byKey(Key('avoir-traite-${uuid('a2')}')), findsNothing);
    });

    testWidgets('⚠️ ÉCART ASSUMÉ : une demande non envoyée le dit sous son statut, un refus donne son motif', (tester) async {
      await avoir(uuid('a1'), numero: null, synchro: SyncStatus.pending);
      await avoir(uuid('a2'), numero: null, synchro: SyncStatus.conflict, le: DateTime(2026, 10, 20));
      await db.into(db.syncConflicts).insert(
        SyncConflictsCompanion.insert(
          id: 'credit_notes:${uuid('a2')}',
          sourceTable: 'credit_notes',
          recordId: uuid('a2'),
          reason: 'Retour refusé : plan comptable incomplet (compte 411 absent).',
          detectedAt: maintenant,
        ),
      );
      await monter(tester);

      expect(tester.widget<Text>(find.byKey(Key('avoir-envoi-${uuid('a1')}'))).data, 'Non envoyé');
      expect(
        find.text('Refusé par le serveur : Retour refusé : plan comptable incomplet (compte 411 absent).'),
        findsOneWidget,
      );
      expect(find.text('—'), findsWidgets, reason: 'le numéro d\'une demande non reçue est « — »');
    });

    testWidgets('« Marquer comme traité » : toast du web, statut traité, bouton retiré', (tester) async {
      await avoir(uuid('a1'));
      await monter(tester);

      await tester.tap(find.byKey(Key('avoir-traite-${uuid('a1')}')));
      await tester.pumpAndSettle();

      expect(find.text('Avoir marqué comme traité.'), findsOneWidget);
      expect(find.text('Traité'), findsOneWidget);
      expect(find.byKey(Key('avoir-traite-${uuid('a1')}')), findsNothing);
      final a = await (db.select(db.creditNotes)..where((x) => x.id.equals(uuid('a1')))).getSingle();
      expect(a.syncStatus, SyncStatus.pending);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('sans manage-ventes : le web refuse (authorize), le poste dit « Votre rôle ne permet pas cette action. »', (tester) async {
      await avoir(uuid('a1'));
      await monter(tester, peutGerer: false);

      await tester.tap(find.byKey(Key('avoir-traite-${uuid('a1')}')));
      await tester.pumpAndSettle();

      expect(find.text('Votre rôle ne permet pas cette action.'), findsOneWidget);
      final a = await (db.select(db.creditNotes)..where((x) => x.id.equals(uuid('a1')))).getSingle();
      expect(a.status, 'en_attente', reason: 'rien n\'est écrit sans le droit');
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('⚠️ la modale : seule « 1. Facture Source » au départ, les quatre autres sections viennent avec la vente', (tester) async {
      await monter(tester);
      await ouvrirLeFormulaire(tester);

      expect(find.text('Nouveau Retour'), findsWidgets);
      expect(find.text('1. FACTURE SOURCE'), findsOneWidget);
      for (final section in ['2. ARTICLE RETOURNÉ', '3. MOTIF DU RETOUR', '4. INSPECTION SANITAIRE (SI SUJET VIVANT)', '5. DÉCISION']) {
        expect(find.text(section), findsNothing, reason: section);
      }
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.text('Enregistrer le Retour'), findsOneWidget);

      await choisir(tester, 'retour-vente', 'BBBBBBBB — GBAGUIDI Solange — 79 000 FCFA');

      for (final section in ['2. ARTICLE RETOURNÉ', '3. MOTIF DU RETOUR', '4. INSPECTION SANITAIRE (SI SUJET VIVANT)', '5. DÉCISION', 'QUANTITÉ RETOURNÉE *', "MONTANT DE L'AVOIR (FCFA) *"]) {
        expect(find.text(section), findsOneWidget, reason: section);
      }
      expect(find.text('Réintégrer au stock'), findsOneWidget);
      expect(find.text('Réformer (détruire)'), findsOneWidget);
      expect(
        find.text("Réintégrer ajoute réellement la quantité au stock du produit. Réformer n'a aucun impact sur le stock (traçabilité seule)."),
        findsOneWidget,
      );
    });

    testWidgets("choisir l'article pré-remplit la quantité et le montant (retour total), choisir une autre vente les vide", (tester) async {
      await vendre(vente2, DateTime(2026, 10, 19, 9));
      await monter(tester);
      await ouvrirLeFormulaire(tester);
      await choisir(tester, 'retour-vente', 'BBBBBBBB — GBAGUIDI Solange — 79 000 FCFA');
      await choisir(tester, 'retour-produit', "Plaquette d'œufs (10 plaquette)");

      expect(tester.widget<TextField>(find.byKey(const Key('retour-quantite'))).controller!.text, '10');
      expect(tester.widget<TextField>(find.byKey(const Key('retour-montant'))).controller!.text, '59000');

      await choisir(tester, 'retour-vente', 'BBBBBBBB — Client Anonyme — 79 000 FCFA');

      expect(tester.widget<TextField>(find.byKey(const Key('retour-quantite'))).controller!.text, isEmpty);
      expect(tester.widget<TextField>(find.byKey(const Key('retour-montant'))).controller!.text, isEmpty);
    });

    testWidgets('⚠️⚠️ « Enregistrer le Retour » sans rien : les messages sous les champs, la modale reste ouverte', (tester) async {
      await monter(tester);
      await ouvrirLeFormulaire(tester);

      await tester.tap(find.byKey(const Key('retour-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('retour-erreur-saleId')), findsOneWidget);
      expect(find.text('Le champ vente est obligatoire.'), findsOneWidget);
      expect(find.text('Enregistrer le Retour'), findsOneWidget, reason: 'la modale reste ouverte');
      expect(await db.select(db.creditNotes).get(), isEmpty);
    });

    testWidgets('⚠️⚠️ un retour complet : la demande est écrite, le toast le dit, le tableau la montre « Non envoyé »', (tester) async {
      await monter(tester);
      await ouvrirLeFormulaire(tester);
      await choisir(tester, 'retour-vente', 'BBBBBBBB — GBAGUIDI Solange — 79 000 FCFA');
      await choisir(tester, 'retour-produit', "Plaquette d'œufs (10 plaquette)");
      await tester.enterText(find.byKey(const Key('retour-quantite')), '2');
      await tester.enterText(find.byKey(const Key('retour-montant')), '11800');
      await tester.enterText(find.byKey(const Key('retour-motif')), 'Plaquette détériorée');
      await tester.enterText(find.byKey(const Key('retour-notes')), 'Contrôle visuel effectué, RAS');

      await tester.tap(find.byKey(const Key('retour-enregistrer')));
      await tester.pumpAndSettle();

      final a = (await db.select(db.creditNotes).get()).single;
      expect(a.syncStatus, SyncStatus.pending);
      expect(a.qty, 2);
      expect(a.amount, 11800);
      expect(a.decision, 'reintegre');
      expect(a.inspectionNotes, 'Contrôle visuel effectué, RAS');
      expect(
        find.text(
          'Retour enregistré sur ce poste — le stock sera réintégré à la synchronisation. '
          'Avoir comptabilisé (débit 701 / crédit 411) par le serveur.',
        ),
        findsOneWidget,
      );
      expect(find.text('Non envoyé'), findsOneWidget);
      expect(find.text('Aucun retour pour le moment.'), findsNothing);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle(const Duration(seconds: 8));
    });

    testWidgets('« Réformer (détruire) » : aucun impact stock, et le toast le dit', (tester) async {
      await monter(tester);
      await ouvrirLeFormulaire(tester);
      await choisir(tester, 'retour-vente', 'BBBBBBBB — GBAGUIDI Solange — 79 000 FCFA');
      await choisir(tester, 'retour-produit', 'Vitamines (4 sachet)');
      await tester.enterText(find.byKey(const Key('retour-motif')), 'Mortalité');
      await tester.tap(find.byKey(const Key('retour-decision-reforme')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('retour-enregistrer')));
      await tester.pumpAndSettle();

      expect((await db.select(db.creditNotes).get()).single.decision, 'reforme');
      expect(find.textContaining('produit réformé, aucun impact stock'), findsOneWidget);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle(const Duration(seconds: 8));
    });

    testWidgets('une quantité au-delà du vendu : le message du serveur sous « Quantité Retournée »', (tester) async {
      await monter(tester);
      await ouvrirLeFormulaire(tester);
      await choisir(tester, 'retour-vente', 'BBBBBBBB — GBAGUIDI Solange — 79 000 FCFA');
      await choisir(tester, 'retour-produit', "Plaquette d'œufs (10 plaquette)");
      await tester.enterText(find.byKey(const Key('retour-quantite')), '11');
      await tester.enterText(find.byKey(const Key('retour-motif')), 'Erreur de quantité');

      await tester.tap(find.byKey(const Key('retour-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('retour-erreur-qty')), findsOneWidget);
      expect(find.textContaining('10 vendu(s), 0 déjà retourné(s), 10 restant(s)'), findsOneWidget);
      expect(await db.select(db.creditNotes).get(), isEmpty);
    });

    testWidgets('⚠️⚠️ exercice clos : « Retour refusé : … » en toast d\'erreur, rien n\'est écrit, la modale se ferme', (tester) async {
      await (db.update(db.fiscalYears)..where((e) => e.year.equals(2026))).write(const FiscalYearsCompanion(status: Value('cloture')));
      await monter(tester);
      await ouvrirLeFormulaire(tester);
      await choisir(tester, 'retour-vente', 'BBBBBBBB — GBAGUIDI Solange — 79 000 FCFA');
      await choisir(tester, 'retour-produit', 'Vitamines (4 sachet)');
      await tester.enterText(find.byKey(const Key('retour-motif')), 'Mortalité');

      await tester.tap(find.byKey(const Key('retour-enregistrer')));
      await tester.pumpAndSettle();

      expect(
        find.text("Retour refusé : L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 21/10/2026."),
        findsOneWidget,
      );
      expect(await db.select(db.creditNotes).get(), isEmpty);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle(const Duration(seconds: 8));
    });

    testWidgets('sans manage-ventes : le formulaire ne s\'enregistre pas, « Votre rôle ne permet pas cette action. »', (tester) async {
      await monter(tester, peutGerer: false);
      await ouvrirLeFormulaire(tester);
      await choisir(tester, 'retour-vente', 'BBBBBBBB — GBAGUIDI Solange — 79 000 FCFA');
      await choisir(tester, 'retour-produit', 'Vitamines (4 sachet)');
      await tester.enterText(find.byKey(const Key('retour-motif')), 'Mortalité');

      await tester.tap(find.byKey(const Key('retour-enregistrer')));
      await tester.pumpAndSettle();

      expect(find.text('Votre rôle ne permet pas cette action.'), findsOneWidget);
      expect(await db.select(db.creditNotes).get(), isEmpty);
      ToastAgri.toutRetirer();
      await tester.pumpAndSettle(const Duration(seconds: 8));
    });
  });
}
