import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/clients/clients_creances_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.43 — HUB CLIENTS ET CRÉANCES (`creances-clients.html`).
///
/// ⚠️⚠️ **TROIS TABLES RÉELLES, AUCUNE NE DESCENDAIT.** `customers` (10
/// lignes), `receivables` (51) et `customer_advances` (4) existent depuis les
/// premiers sprints ; le tirage ne les servait pas. Le hub était impossible à
/// bâtir — et trois écrans déjà livrés portaient un tiret à cause de cette
/// seule absence.
///
/// ⚠️⚠️ **LE RESTE DÛ SE CALCULE** : `amount − amount_paid`. Sommer `amount`
/// compterait deux fois ce qui a déjà été réglé.
void main() {
  late AppDatabase db;
  late ClientsCreancesRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final aujourdhui = DateTime.now();
  DateTime ilYA(int jours) =>
      DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day - jours);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ClientsCreancesRepository(database: db, deviceId: 'poste-test');
  });

  tearDown(() async => db.close());

  Future<void> client(
    String cle,
    String nom, {
    String? ville,
    bool actif = true,
  }) => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: uuid(cle),
          name: nom,
          phone: Value('+2299750${cle.hashCode.abs() % 10000}'),
          city: Value(ville),
          isActive: Value(actif),
        ),
      );

  Future<void> creance(
    String cle,
    String cleClient, {
    required double montant,
    double regle = 0,
    int? echeanceIlYA,
  }) => db
      .into(db.receivables)
      .insert(
        ReceivablesCompanion.insert(
          id: uuid(cle),
          customerId: uuid(cleClient),
          amount: montant,
          amountPaid: Value(regle),
          dueDate: Value(echeanceIlYA == null ? null : ilYA(echeanceIlYA)),
        ),
      );

  Future<void> avance(
    String cle,
    String cleClient, {
    required double montant,
    double utilise = 0,
  }) => db
      .into(db.customerAdvances)
      .insert(
        CustomerAdvancesCompanion.insert(
          id: uuid(cle),
          customerId: uuid(cleClient),
          amount: montant,
          amountUsed: Value(utilise),
          advanceDate: Value(ilYA(10)),
        ),
      );

  /// ⚠️ Une relance se date DANS LE MOIS, jamais « il y a n jours » : au 2 du
  /// mois, « il y a 3 jours » tomberait dans le mois précédent et le test
  /// échouerait deux jours par mois — la pire des variantes de test instable.
  Future<void> relance(
    String cle,
    String cleClient, {
    required int jourDuMois,
    String canal = 'whatsapp',
  }) => db
      .into(db.customerReminders)
      .insert(
        CustomerRemindersCompanion.insert(
          id: uuid(cle),
          customerId: uuid(cleClient),
          channel: canal,
          reminderDate: Value(
            DateTime(aujourdhui.year, aujourdhui.month, jourDuMois),
          ),
        ),
      );

  Future<void> relanceAnneePassee(String cle, String cleClient) => db
      .into(db.customerReminders)
      .insert(
        CustomerRemindersCompanion.insert(
          id: uuid(cle),
          customerId: uuid(cleClient),
          channel: 'sms',
          reminderDate: Value(DateTime(aujourdhui.year - 1, 3, 12)),
        ),
      );

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(home: ClientsCreancesScreen(depot: depot)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, String onglet) async {
    await tester.tap(find.byKey(Key('onglet-clients-$onglet')));
    await tester.pumpAndSettle();
  }

  group('dépôt', () {
    /// ⚠️⚠️ LE CŒUR DU TICKET.
    test('⚠️⚠️ l encours porte le reste dû, pas le montant facturé', () async {
      await client('c1', 'AMOUSSOU Régis');
      await creance('r1', 'c1', montant: 8000, regle: 3000);
      await creance('r2', 'c1', montant: 2000);

      final d = await depot.charger();

      expect(d.encoursGlobal, 7000);
    });

    /// ⚠️ L'âge se compte depuis l'ÉCHÉANCE, jamais depuis l'émission : une
    /// facture payable à 120 jours n'est pas en retard au 90e.
    test('⚠️ le retard se compte depuis l échéance', () async {
      await client('c1', 'AMOUSSOU Régis');
      await creance('echue', 'c1', montant: 5000, echeanceIlYA: 45);
      await creance('terme', 'c1', montant: 4000, echeanceIlYA: -10);

      final d = await depot.charger();
      final jour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);

      expect(d.echusAuDela(jour, ClientsCreancesRepository.seuilEchu), 5000);
      expect(d.creances.where((c) => c.echue(jour)).length, 1);
    });

    test('le solde dû se ventile par client', () async {
      await client('c1', 'AMOUSSOU Régis');
      await client('c2', 'GBAGUIDI Solange');
      await creance('r1', 'c1', montant: 6000, regle: 1000);

      final d = await depot.charger();

      expect(
        d.clients
            .firstWhere((c) => c.client.name.startsWith('AMOUSSOU'))
            .soldeDu,
        5000,
      );
      expect(
        d.clients
            .firstWhere((c) => c.client.name.startsWith('GBAGUIDI'))
            .soldeDu,
        0,
      );
    });

    /// ⚠️ « Total Achats » ne compte que les ventes de CE poste : le tirage ne
    /// descend pas `sales`.
    test('⚠️ le total des achats ne couvre que ce poste', () async {
      await client('c1', 'AMOUSSOU Régis');
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: uuid('v1'),
              deviceId: 'poste-test',
              updatedAt: aujourdhui,
              customerId: Value(uuid('c1')),
              paymentMode: 'especes',
              total: 32000,
              soldAt: aujourdhui,
            ),
          );

      final d = await depot.charger();

      expect(d.clients.single.totalAchats, 32000);
    });

    /// ⚠️ Même règle que le web (`RelancesClients.php` l.117-125) : la plus
    /// vieille créance échue en tête, celles à terme exclues.
    test(
      '⚠️ la file de relance trie par ancienneté et exclut le terme',
      () async {
        await client('c1', 'AMOUSSOU Régis');
        await creance('recente', 'c1', montant: 3000, echeanceIlYA: 5);
        await creance('ancienne', 'c1', montant: 9000, echeanceIlYA: 60);
        await creance('terme', 'c1', montant: 4000, echeanceIlYA: -10);
        await creance(
          'payee',
          'c1',
          montant: 4000,
          regle: 4000,
          echeanceIlYA: 90,
        );

        final d = await depot.charger();
        final file = d.fileDeRelance(
          DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day),
        );

        expect(file.map((l) => l.creance.amount), [9000, 3000]);
      },
    );

    test('une avance entièrement utilisée est soldée', () async {
      await client('c1', 'AMOUSSOU Régis');
      await avance('a1', 'c1', montant: 10000, utilise: 10000);
      await avance('a2', 'c1', montant: 5000, utilise: 1000);

      final d = await depot.charger();

      expect(d.avancesEnCours, 4000);
      expect(d.clientsAvecAvance, 1);
    });
  });

  group('écran', () {
    /// ⚠️⚠️ **LE NOMBRE DE CARTES, ONGLET PAR ONGLET** (ticket F0.54). Chaque
    /// onglet du hub est une page distincte de la maquette : le contrôle se fait
    /// donc page par page, sans arbitrage sur la répartition.
    ///
    /// ⚠️ « Relances Clients » n'y figure pas : `relances-clients.html` n'a
    /// jamais été passée à l'extracteur de structure, elle n'a donc pas de
    /// relevé de cartes. L'onglet reste hors de ce contrôle — dit ici plutôt
    /// que passé sous silence.
    testWidgets('⚠️⚠️ chaque onglet rend le nombre de cartes de sa page', (
      tester,
    ) async {
      await afficher(tester);

      const pages = <String, String>{
        'Liste des Clients': 'liste-clients.html',
        'Suivi des Dettes': 'suivi-dettes.html',
        'Historique Avances': 'historique-avances.html',
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

    testWidgets('⚠️ les quatre onglets du hub sont là, dans son ordre', (
      tester,
    ) async {
      await afficher(tester);

      for (final onglet in [
        'Liste des Clients',
        'Suivi des Dettes',
        'Relances Clients',
        'Historique Avances',
      ]) {
        expect(find.text(onglet), findsWidgets, reason: onglet);
      }
    });

    testWidgets('la liste porte les sept colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);

      for (final colonne in [
        'NOM',
        'TÉLÉPHONE',
        'VILLE',
        'TOTAL ACHATS',
        'SOLDE DÛ',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('le client descendu du serveur est nommé', (tester) async {
      await client('c1', 'AMOUSSOU Régis', ville: 'Ikpinlè');

      await afficher(tester);

      expect(find.text('AMOUSSOU Régis'), findsOneWidget);
      expect(find.text('Ikpinlè'), findsOneWidget);
    });

    /// ⚠️⚠️ `customers` descend sans sa date de création : « 0 nouveau ce
    /// mois-ci » affirmerait qu'aucun client n'a été créé.
    testWidgets('⚠️⚠️ les nouveaux du mois affichent un tiret motivé', (
      tester,
    ) async {
      await afficher(tester);

      expect(find.text('Date de création non synchronisée'), findsOneWidget);
    });

    testWidgets('le suivi des dettes porte les six colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Suivi des Dettes');

      for (final colonne in [
        'DÉBITEUR',
        'FACTURE ASSOCIÉE',
        'ÉCHÉANCE',
        'TOTAL FACTURÉ',
        'SOLDE RESTANT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('⚠️ une créance échue affiche son retard', (tester) async {
      await client('c1', 'AMOUSSOU Régis');
      await creance('r1', 'c1', montant: 5000, echeanceIlYA: 45);

      await afficher(tester);
      await ouvrir(tester, 'Suivi des Dettes');

      expect(find.textContaining('(+45 j)'), findsOneWidget);
    });

    /// ⚠️⚠️ Le serveur ne descend que les créances ENCORE DUES : le poste ne
    /// voit pas le dénominateur d'un taux de recouvrement.
    testWidgets('⚠️⚠️ le taux de recouvrement dit pourquoi il est absent', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Suivi des Dettes');

      expect(find.text('Créances soldées non synchronisées'), findsOneWidget);
    });

    testWidgets('les quatre indicateurs de la maquette sont là', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Relances Clients');

      for (final kpi in [
        'CRÉANCES ÉCHUES',
        'RELANCES EFFECTUÉES',
        'TAUX DE RÉPONSE',
        'MONTANT RECOUVRÉ',
      ]) {
        expect(find.text(kpi), findsOneWidget, reason: kpi);
      }
    });

    /// ⚠️⚠️ LE TICKET 14.76 : la table s'appelait `customer_reminders`, pas
    /// `payment_reminders` — le seul nom cherché la première fois. L'onglet
    /// avait été livré « module non embarqué » sur cette erreur.
    testWidgets(
      '⚠️⚠️ les relances du mois sont comptées, pas tout l historique',
      (tester) async {
        await client('c1', 'AMOUSSOU Régis');
        await relance('re1', 'c1', jourDuMois: 1);
        await relance('re2', 'c1', jourDuMois: 2);
        await relanceAnneePassee('vieille', 'c1');

        await afficher(tester);
        await ouvrir(tester, 'Relances Clients');

        expect(find.text('2'), findsOneWidget);
      },
    );

    testWidgets(
      '⚠️ la file de relance porte le débiteur, son reste dû et son retard',
      (tester) async {
        await client('c1', 'GBAGUIDI Solange');
        await creance(
          'r1',
          'c1',
          montant: 100000,
          regle: 5000,
          echeanceIlYA: 26,
        );

        await afficher(tester);
        await ouvrir(tester, 'Relances Clients');

        expect(find.text('GS'), findsOneWidget);
        expect(find.text('GBAGUIDI Solange'), findsOneWidget);
        expect(find.text('95 000 FCFA'), findsOneWidget);
        expect(find.text(' — 26 jours de retard'), findsOneWidget);
      },
    );

    testWidgets('une créance à terme n entre pas dans la file', (tester) async {
      await client('c1', 'AMOUSSOU Régis');
      await creance('r1', 'c1', montant: 4000, echeanceIlYA: -10);

      await afficher(tester);
      await ouvrir(tester, 'Relances Clients');

      expect(find.text('— Aucune créance échue à relancer —'), findsOneWidget);
    });

    /// ⚠️⚠️ Le serveur ne descend que ce qui reste dû : ni le taux de réponse
    /// ni le montant recouvré n'ont leur dénominateur au poste.
    testWidgets(
      '⚠️⚠️ les deux indicateurs de recouvrement portent leur motif',
      (tester) async {
        await afficher(tester);
        await ouvrir(tester, 'Relances Clients');

        expect(find.text('Créances soldées non synchronisées'), findsOneWidget);
        expect(find.text('Règlements soldés non synchronisés'), findsOneWidget);
      },
    );

    /// ⚠️ Le texte est celui de la maquette, au caractère près.
    testWidgets(
      '⚠️ le modèle affiché est le niveau 2, comme dans la maquette',
      (tester) async {
        await afficher(tester);
        await ouvrir(tester, 'Relances Clients');

        expect(
          find.textContaining('est en retard de paiement depuis le'),
          findsOneWidget,
        );
      },
    );

    testWidgets('changer de niveau change le texte du modèle', (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'Relances Clients');

      await tester.tap(find.byKey(const Key('niveau-relance')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Niveau 3 : Mise en demeure').last);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Nous vous mettons en demeure de régulariser'),
        findsOneWidget,
      );
    });

    /// ⚠️⚠️ Une relance partie du poste ne serait inscrite nulle part : le
    /// client serait rappelé deux fois depuis le web le lendemain.
    testWidgets('⚠️⚠️ l écran dit pourquoi il n envoie pas', (tester) async {
      await afficher(tester);
      await ouvrir(tester, 'Relances Clients');

      expect(
        find.textContaining('Le client serait rappelé deux fois.'),
        findsOneWidget,
      );
    });

    testWidgets('les avances portent les six colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, 'Historique Avances');

      for (final colonne in [
        'CLIENT',
        'MONTANT AVANCE',
        'SOLDE RESTANT',
        'DATE',
        'STATUT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('une avance soldée se distingue d une avance en cours', (
      tester,
    ) async {
      await client('c1', 'AMOUSSOU Régis');
      await avance('a1', 'c1', montant: 10000, utilise: 10000);
      await avance('a2', 'c1', montant: 5000, utilise: 1000);

      await afficher(tester);
      await ouvrir(tester, 'Historique Avances');

      expect(find.text('Soldée'), findsOneWidget);
      expect(find.text('En cours'), findsOneWidget);
    });

    testWidgets('sans client, la liste le dit', (tester) async {
      await afficher(tester);

      expect(find.text('— Aucun client pour ces critères —'), findsOneWidget);
    });
  });
}
