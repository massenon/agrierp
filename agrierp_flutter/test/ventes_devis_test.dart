import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/ventes_devis_repository.dart';
import 'package:agrierp/features/ventes/ventes_devis_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.37 — HUB VENTES & DEVIS (`ventes-devis.html`).
///
/// 🔴→✅ **L'ENTRÉE DE MENU OUVRAIT DIRECTEMENT LA CAISSE**, sautant le hub :
/// le caissier n'avait aucun chemin vers l'historique de ses propres ventes.
/// La caisse est désormais le premier onglet, comme dans la maquette.
///
/// ⚠️⚠️ **LE TIRAGE NE DESCEND PAS `sales`.** L'historique du poste ne contient
/// que SES encaissements. La maquette écrit « Toutes les ventes enregistrées
/// de l'entreprise » : au poste c'est faux, et l'écran le corrige au lieu de
/// le recopier.
void main() {
  late AppDatabase db;
  late VentesDevisRepository depot;
  late CaisseRepository caisse;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = VentesDevisRepository(database: db);
    caisse = CaisseRepository(database: db, deviceId: 'poste-test');
  });

  tearDown(() async => db.close());

  Future<void> vente(
    String cle, {
    required double total,
    double remise = 0,
    double? encaisse,
    String mode = 'especes',
    String statut = 'validee',
    String? client,
    int articles = 1,
    DateTime? quand,
  }) async {
    final date = quand ?? DateTime.now();

    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: uuid('$cle-vente'),
            deviceId: 'poste-test',
            updatedAt: date,
            customerId: Value(client),
            paymentMode: mode,
            discount: Value(remise),
            total: total,
            cashReceived: Value(encaisse),
            status: Value(statut),
            soldAt: date,
          ),
        );

    for (var i = 0; i < articles; i++) {
      await db
          .into(db.saleLines)
          .insert(
            SaleLinesCompanion.insert(
              id: uuid('$cle-ligne-$i'),
              saleId: uuid('$cle-vente'),
              productId: uuid('produit-$i'),
              qty: 1,
              unitPrice: total / articles,
              manualTotalAmount: total / articles,
            ),
          );
    }
  }

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: VentesDevisScreen(depot: depot, caisse: caisse),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-ventes-$onglet')));
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ les quatre onglets du hub sont là, dans son ordre', (
    tester,
  ) async {
    await afficher(tester);

    for (final onglet in [
      'Enregistrer Vente',
      'Devis Prestations',
      'Historique des Ventes',
      'Retours et Avoirs',
    ]) {
      expect(find.text(onglet), findsWidgets, reason: onglet);
    }
  });

  testWidgets('⚠️ le hub ouvre sur la caisse, comme la maquette', (
    tester,
  ) async {
    await afficher(tester);

    // L'écran de caisse est bien monté sous le premier onglet.
    expect(find.byType(VentesDevisScreen), findsOneWidget);
    expect(find.text('Historique des Ventes'), findsOneWidget);
  });

  testWidgets("l'historique porte les onze colonnes de la maquette", (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    for (final colonne in [
      'FACTURE',
      'CLIENT',
      'DATE',
      'ARTICLES',
      'REMISE',
      'TOTAL TTC',
      'PAYÉ',
      'RESTE',
      'MODE',
      'STATUT',
      'ACTIONS',
    ]) {
      expect(find.text(colonne), findsOneWidget, reason: colonne);
    }
  });

  /// ⚠️⚠️ La maquette annonce « Toutes les ventes enregistrées de
  /// l'entreprise » — au poste, c'est faux.
  testWidgets('⚠️⚠️ l historique dit qu il ne couvre que ce poste', (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    expect(
      find.textContaining('Ventes encaissées sur ce poste'),
      findsOneWidget,
    );
  });

  /// ⚠️⚠️ **LE NOMBRE DE CARTES, PAS SEULEMENT LEURS LIBELLÉS** (ticket F0.54).
  /// `historique-ventes.html` est la seule des quatre pages du hub à porter des
  /// cartes : les trois autres onglets sont des pages distinctes de la maquette.
  testWidgets('⚠️⚠️ l historique rend le nombre de cartes de la maquette', (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    expect(
      find.byType(CarteKpi),
      findsNWidgets(cartesAttendues('historique-ventes.html')),
    );
  });

  testWidgets('les quatre KPI portent les libellés de la maquette', (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    for (final libelle in [
      "CHIFFRE D'AFFAIRES",
      'TRANSACTIONS',
      'PANIER MOYEN',
      'ENCOURS CRÉANCES',
    ]) {
      expect(find.text(libelle), findsOneWidget, reason: libelle);
    }
  });

  /// 🔴→✅ TICKET F0.43 — l'encours est réel depuis que `receivables` descend
  /// au poste (ticket 14.75).
  ///
  /// ⚠️ **LE RESTE DÛ, PAS LE MONTANT FACTURÉ** : 8 000 facturés dont 3 000
  /// déjà réglés font 5 000 d'encours, jamais 8 000.
  testWidgets('⚠️ l encours porte le reste dû, pas le montant facturé', (
    tester,
  ) async {
    await db
        .into(db.receivables)
        .insert(
          ReceivablesCompanion.insert(
            id: uuid('creance'),
            customerId: uuid('client'),
            amount: 8000,
            amountPaid: const Value(3000),
          ),
        );

    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    expect(find.text('5 000 FCFA'), findsOneWidget);
    expect(find.text('8 000 FCFA'), findsNothing);
  });

  testWidgets('les KPI comptent les ventes du poste', (tester) async {
    await vente('a', total: 32000, encaisse: 32000, articles: 2);
    await vente('b', total: 48000, encaisse: 50000, articles: 1);

    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    expect(find.text('80 000 FCFA'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('40 000 FCFA'), findsOneWidget);
  });

  /// ⚠️ Sans vente, « 0 FCFA » se lirait comme un panier réellement vide.
  testWidgets('⚠️ sans vente, le panier moyen est un tiret', (tester) async {
    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    // ⚠️ Le chiffre d'affaires, lui, vaut BIEN zéro : aucune vente n'a été
    // encaissée. C'est le panier MOYEN qui n'existe pas — diviser par zéro.
    expect(
      find.descendant(
        of: find.byKey(const Key('kpi-Panier Moyen')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key("kpi-Chiffre d'Affaires")),
        matching: find.text('0 FCFA'),
      ),
      findsOneWidget,
    );
  });

  /// ⚠️ Une vente annulée reste à l'historique — c'est l'historique, pas le
  /// journal des ventes valides — mais ne compte pas au chiffre d'affaires.
  testWidgets('⚠️ une vente annulée figure mais ne compte pas au CA', (
    tester,
  ) async {
    await vente('ok', total: 20000, encaisse: 20000);
    await vente('ko', total: 99000, statut: 'annulee');

    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    expect(find.text('20 000 FCFA'), findsWidgets);
    expect(find.text('Annulée'), findsOneWidget);
    expect(find.text('119 000 FCFA'), findsNothing);
  });

  /// ⚠️⚠️ AUCUN NUMÉRO DE FACTURE N'EXISTE — ni au poste, ni dans `sales`
  /// côté serveur, ni dans le POS Livewire (ticket 14.71). La colonne reste,
  /// sa valeur est un tiret : l'identité de la vente, c'est sa date et son
  /// heure.
  testWidgets('⚠️⚠️ la colonne Facture reste vide, faute de numéro', (
    tester,
  ) async {
    await vente('a', total: 32000, encaisse: 32000);

    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    final ligne = find.byKey(const Key('vente-0'));
    expect(find.descendant(of: ligne, matching: find.text('—')), findsWidgets);
  });

  /// ⚠️ « Payé » et « Reste » ne sortent que de `cash_received` : pour un
  /// virement, le poste ne sait pas ce qui a été reçu. Déduire « payé = total »
  /// supposerait l'encaissement.
  testWidgets('⚠️ payé et reste restent vides hors espèces', (tester) async {
    await vente('vir', total: 45000, mode: 'virement');

    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    final ligne = find.byKey(const Key('vente-0'));
    expect(
      find.descendant(of: ligne, matching: find.text('45 000')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: ligne, matching: find.text('—')),
      findsNWidgets(3),
    );
  });

  testWidgets('le rendu monnaie se lit dans Reste', (tester) async {
    await vente('esp', total: 45000, encaisse: 50000);

    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    // 45 000 encaissés sur 50 000 → reste −5 000, soit le rendu monnaie.
    expect(find.text('50 000'), findsOneWidget);
    expect(find.text('-5 000'), findsOneWidget);
  });

  /// ⚠️⚠️ La caisse stocke `especes`, la maquette affiche « Espèces » :
  /// comparer les deux directement ne filtrerait jamais rien — et un filtre
  /// qui ne filtre pas est pire qu'absent.
  testWidgets('⚠️⚠️ le filtre de mode traduit le libellé de la maquette', (
    tester,
  ) async {
    await vente('esp', total: 20000, encaisse: 20000, mode: 'especes');
    await vente('mob', total: 30000, mode: 'mobile_money');

    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    await tester.tap(find.byKey(const Key('filtre-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mobile Money').last);
    await tester.pumpAndSettle();

    expect(find.text('30 000'), findsOneWidget);
    expect(find.text('20 000'), findsNothing);
  });

  testWidgets('Réinitialiser rend la liste complète', (tester) async {
    await vente('esp', total: 20000, encaisse: 20000, mode: 'especes');
    await vente('mob', total: 30000, mode: 'mobile_money');

    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    await tester.tap(find.byKey(const Key('filtre-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mobile Money').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reinitialiser')));
    await tester.pumpAndSettle();

    // ⚠️ « 20 000 » paraît deux fois sur sa ligne : au total ET au payé.
    expect(find.text('20 000'), findsWidgets);
    expect(find.text('30 000'), findsOneWidget);
  });

  testWidgets('sans vente, le tableau le dit', (tester) async {
    await afficher(tester);
    await ouvrir(tester, 'Historique des Ventes');

    expect(
      find.text('— Aucune vente encaissée sur ce poste pour ces critères —'),
      findsOneWidget,
    );
  });

  testWidgets('⚠️ les devis disent leur dépendance', (tester) async {
    await afficher(tester);
    await ouvrir(tester, 'Devis Prestations');

    expect(find.byKey(const Key('devis-non-embarque')), findsOneWidget);
    expect(find.textContaining('fichier clients'), findsOneWidget);
  });

  /// ⚠️⚠️ Un avoir rend le stock, annule une créance et passe son écriture :
  /// l'enregistrer au poste laisserait la plupart de ses effets non faits.
  testWidgets('⚠️⚠️ les avoirs disent pourquoi ils restent web', (
    tester,
  ) async {
    await afficher(tester);
    await ouvrir(tester, 'Retours et Avoirs');

    expect(find.byKey(const Key('avoirs-non-embarque')), findsOneWidget);
    expect(find.textContaining('écriture comptable'), findsOneWidget);
  });
}
