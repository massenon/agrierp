import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/elevage/bilan_technico_economique_repository.dart';
import 'package:agrierp/features/elevage/bilan_technico_economique_vue.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.63 — BILAN TECHNICO-ÉCONOMIQUE (`bilan-technico-economique.html`).
///
/// ⚠️⚠️ **LES CHIFFRES SE RECALCULENT À PART.** Les coûts sont calculés au poste
/// avec les règles de `Livewire\Elevage\BilanTechnicoEconomique` ; chaque total
/// attendu ci-dessous est écrit en toutes lettres (acquisition + provende au
/// prix MOYEN indicatif + soins), jamais relu sur ce que l'écran affiche.
/// Le revenu, lui, vient du serveur : on ne le recalcule pas, on vérifie qu'il
/// est repris tel quel et qu'il n'est jamais inventé.
void main() {
  late AppDatabase db;
  late BilanTechnicoEconomiqueRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  final lotA = uuid('lot-a');
  final lotB = uuid('lot-b');
  const especeAvi = 'espece-aviculture';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = BilanTechnicoEconomiqueRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> lot(
    String id,
    String code, {
    String espece = especeAvi,
    String? codeEspece = 'aviculture',
    int initial = 100,
    double? acquisition = 200000,
    DateTime? date,
    bool actif = true,
  }) => db
      .into(db.livestockLots)
      .insert(
        LivestockLotsCompanion.insert(
          id: id,
          code: code,
          speciesId: espece,
          speciesCode: Value(codeEspece),
          initialQuantity: Value(initial),
          acquisitionCost: Value(acquisition),
          createdDate: Value(date ?? DateTime(2026, 1, 15)),
          isActive: Value(actif),
        ),
      );

  Future<void> provende(
    String cle,
    double? prix, {
    String espece = especeAvi,
    String? libelle,
  }) => db
      .into(db.feedTypes)
      .insert(
        FeedTypesCompanion.insert(
          id: uuid(cle),
          name: 'Provende $cle',
          speciesId: Value(espece),
          speciesLabel: Value(libelle),
          pricePerKg: Value(prix),
        ),
      );

  Future<void> fiche(String cle, String lotId, double? kg, int jour) => db
      .into(db.livestockDailyEntries)
      .insert(
        LivestockDailyEntriesCompanion.insert(
          id: uuid(cle),
          deviceId: 'poste-test',
          updatedAt: DateTime(2026, 7, jour),
          lotId: lotId,
          entryDate: DateTime(2026, 7, jour),
          feedQtyKg: Value(kg),
        ),
      );

  Future<void> soin(String cle, String lotId, double? cout) => db
      .into(db.veterinaryRecords)
      .insert(
        VeterinaryRecordsCompanion.insert(
          id: uuid(cle),
          deviceId: 'poste-test',
          updatedAt: DateTime(2026, 7, 1),
          lotId: lotId,
          actionType: 'Vaccination',
          recordDate: DateTime(2026, 7, 1),
          cost: Value(cout),
        ),
      );

  Future<void> revenu(String lotId, String produit, String libelle, double m) =>
      db
          .into(db.lotRevenues)
          .insert(
            LotRevenuesCompanion.insert(
              lotId: lotId,
              productId: uuid(produit),
              label: libelle,
              amount: m,
            ),
          );

  /// Date le tirage des revenus : sans elle, le poste ne sait pas s'il les a reçus.
  Future<void> revenusTires() => db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: SyncEngine.cleRevenusTires,
          value: DateTime(2026, 7, 28).toUtc().toIso8601String(),
        ),
      );

  Future<void> venteDuPoste(
    String cle,
    String lotId, {
    SyncStatus statut = SyncStatus.pending,
    String etat = 'validee',
  }) async {
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: uuid(cle),
            deviceId: 'poste-test',
            updatedAt: DateTime(2026, 7, 28),
            paymentMode: 'especes',
            total: 5000,
            soldAt: DateTime(2026, 7, 28),
            status: Value(etat),
            syncStatus: Value(statut),
          ),
        );
    await db
        .into(db.saleLines)
        .insert(
          SaleLinesCompanion.insert(
            id: uuid('l-$cle'),
            saleId: uuid(cle),
            productId: uuid('produit-1'),
            lotId: Value(lotId),
            qty: 1,
            unitPrice: 5000,
            manualTotalAmount: 5000,
          ),
        );
  }

  /// Le jeu de référence : toutes les valeurs attendues se déduisent à la main.
  ///
  ///  * acquisition ........................ 200 000
  ///  * provende : 10,5 + 20 = 30,5 kg × prix MOYEN (400 + 500) / 2 = 450
  ///                                         = 13 725
  ///  * soins : 12 000 + (coût inconnu, ignoré) = 12 000
  ///  => coûts connus = 225 725 ; par sujet = 225 725 / 100 = 2 257,25 → 2 257
  ///  * revenus (serveur) : 45 000 + 15 000 = 60 000
  ///  => marge = 60 000 − 225 725 = −165 725
  Future<void> jeuDeReference() async {
    await lot(lotA, 'AVI-2026-001');
    await provende('p1', 400);
    await provende('p2', 500);
    await provende('p3', null); // sans prix : hors de la moyenne
    await provende('autre', 9999, espece: 'espece-porcine'); // autre espèce
    await fiche('f1', lotA, 10.5, 1);
    await fiche('f2', lotA, 20, 2);
    await fiche('f3', lotA, null, 3); // fiche sans provende : ignorée
    await soin('s1', lotA, 12000);
    await soin('s2', lotA, null);
    await revenu(lotA, 'produit-1', 'Ventes — Poulet vif', 45000);
    await revenu(lotA, 'produit-2', 'Ventes — Œufs de table', 15000);
    await revenusTires();
  }

  group('calcul', () {
    test(
      '⚠️⚠️ coûts, revenus, marge et coût par sujet se recalculent à part',
      () async {
        await jeuDeReference();

        final b = (await depot.charger(lotA))!;

        expect(b.couts[0].montant, 200000);
        expect(b.couts[1].montant, 13725);
        expect(b.couts[2].montant, 12000);
        expect(b.couts[3].montant, isNull, reason: "main d'œuvre en attente");
        expect(b.coutTotalConnu, 225725);
        expect(b.revenuTotalConnu, 60000);
        expect(b.margeNette, -165725);
        expect(b.coutParSujet, 2257);
      },
    );

    test(
      'la provende se valorise au prix MOYEN des types de l\'espèce',
      () async {
        await lot(lotA, 'AVI-1');
        await provende('p1', 300);
        await provende('p2', 600); // moyenne 450, et non 300 ni 600
        await fiche('f1', lotA, 100, 1);

        final b = (await depot.charger(lotA))!;

        expect(b.couts[1].montant, 45000);
      },
    );

    test('⚠️ aucun prix de provende : « — », JAMAIS un coût de zéro', () async {
      await lot(lotA, 'AVI-1');
      await provende('p1', null);
      await fiche('f1', lotA, 50, 1);

      final b = (await depot.charger(lotA))!;

      expect(b.couts[1].montant, isNull);
      expect(b.couts[1].motif, contains('ne peut pas être valorisée'));
      // Le total connu n'inclut donc pas un 0 présenté comme un coût réel.
      expect(b.coutTotalConnu, 200000);
    });

    test('⚠️ acquisition non renseignée : « — » et motif, pas zéro', () async {
      await lot(lotA, 'AVI-1', acquisition: null);

      final b = (await depot.charger(lotA))!;

      expect(b.couts[0].montant, isNull);
      expect(b.couts[0].motif, contains('non renseigné'));
    });

    test(
      "la main d'œuvre reste en attente, avec le motif de Laravel",
      () async {
        await lot(lotA, 'AVI-1');

        final b = (await depot.charger(lotA))!;

        expect(b.couts[3].libelle, "Main d'œuvre imputée");
        expect(b.couts[3].montant, isNull);
        expect(b.couts[3].motif, contains("Aucune clé d'imputation"));
      },
    );

    test('coût par sujet : effectif initial nul → « — »', () async {
      await lot(lotA, 'AVI-1', initial: 0);

      expect((await depot.charger(lotA))!.coutParSujet, isNull);
    });

    test('les fiches et les soins d\'une AUTRE bande ne fuient pas', () async {
      await lot(lotA, 'AVI-1');
      await lot(lotB, 'AVI-2');
      await provende('p1', 100);
      await fiche('f1', lotB, 1000, 1);
      await soin('s1', lotB, 99999);

      final b = (await depot.charger(lotA))!;

      expect(b.couts[1].montant, 0);
      expect(b.couts[2].montant, 0);
    });
  });

  group('revenus du serveur', () {
    test('⚠️⚠️ jamais reçus : « — », pas « aucune vente »', () async {
      await lot(lotA, 'AVI-1');

      final b = (await depot.charger(lotA))!;

      expect(b.revenusRecus, isFalse);
      expect(b.revenuTotalConnu, isNull);
      expect(b.margeNette, isNull);
    });

    test('reçus mais vides : un vrai zéro, car le serveur a répondu', () async {
      await lot(lotA, 'AVI-1');
      await revenusTires();

      final b = (await depot.charger(lotA))!;

      expect(b.revenusRecus, isTrue);
      expect(b.revenuTotalConnu, 0);
      expect(b.margeNette, -200000);
    });

    test('les revenus d\'une autre bande ne fuient pas', () async {
      await lot(lotA, 'AVI-1');
      await lot(lotB, 'AVI-2');
      await revenu(lotB, 'produit-1', 'Ventes — Poulet vif', 99000);
      await revenusTires();

      expect((await depot.charger(lotA))!.revenuTotalConnu, 0);
      expect((await depot.charger(lotB))!.revenuTotalConnu, 99000);
    });

    test(
      'ventes du poste en attente : comptées à part, pas dans le revenu',
      () async {
        await lot(lotA, 'AVI-1');
        await revenusTires();
        await venteDuPoste('v1', lotA); // en attente
        await venteDuPoste('v2', lotA, statut: SyncStatus.synced);
        await venteDuPoste('v3', lotA, etat: 'annulee');
        await venteDuPoste('v4', lotB);

        final b = (await depot.charger(lotA))!;

        expect(b.ventesEnAttente, 1);
        expect(
          b.revenuTotalConnu,
          0,
          reason: 'le revenu reste celui du serveur',
        );
      },
    );
  });

  group('sélecteur de bande', () {
    test('seules les bandes actives, les plus récentes d\'abord', () async {
      await lot(lotA, 'ANCIENNE', date: DateTime(2026, 1, 1));
      await lot(lotB, 'RECENTE', date: DateTime(2026, 6, 1));
      await lot(uuid('lot-c'), 'ARCHIVEE', actif: false);

      final bandes = await depot.bandes();

      expect(bandes.map((b) => b.code), ['RECENTE', 'ANCIENNE']);
    });

    test(
      'espèce : libellé du serveur, sinon libellé connu, sinon le code',
      () async {
        await lot(lotA, 'A', espece: 'e1', codeEspece: 'aviculture');
        await provende('p1', 1, espece: 'e1', libelle: 'Volailles de chair');
        await lot(lotB, 'B', espece: 'e2', codeEspece: 'porciculture');
        await lot(uuid('lot-c'), 'C', espece: 'e3', codeEspece: 'x-nouvelle');

        final par = {for (final b in await depot.bandes()) b.code: b.libelle};

        expect(par['A'], 'A (Volailles de chair)');
        expect(par['B'], 'B (Porciculture)');
        expect(par['C'], 'C (x-nouvelle)');
      },
    );
  });

  group('vue', () {
    Future<void> afficher(WidgetTester tester, {Size? taille}) async {
      tester.view.physicalSize = taille ?? const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // ⚠️ `pumpWidget` réutilise l'état d'un widget du même type : on démonte
      // d'abord, sinon un second affichage ne relirait pas la base.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BilanTechnicoEconomiqueVue(depot: depot),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String valeur(WidgetTester tester, String libelle) => tester
        .widget<CarteKpi>(
          find.ancestor(
            of: find.text(libelle.toUpperCase()),
            matching: find.byType(CarteKpi),
          ),
        )
        .valeur;

    testWidgets(
      'titre, sous-titre et quatre cartes dans l\'ordre de la maquette',
      (tester) async {
        await jeuDeReference();
        await afficher(tester);

        expect(find.text('Bilan Technico-Économique de Lot'), findsOneWidget);
        expect(
          find.textContaining('Coûts, revenus et rentabilité réelle par bande'),
          findsOneWidget,
        );
        expect(
          find.byType(CarteKpi),
          findsNWidgets(
            cartesAttenduesPanneau('elevage-dashboard.html', 'dash-tab-bilan'),
          ),
        );
        expect(
          tester
              .widgetList<CarteKpi>(find.byType(CarteKpi))
              .map((c) => c.libelle),
          [
            'Coût Total Connu du Lot',
            'Revenu Total du Lot',
            'Marge Nette',
            'Coût de Revient / Sujet',
          ],
        );
      },
    );

    testWidgets('⚠️⚠️ les valeurs affichées sont celles du recalcul', (
      tester,
    ) async {
      await jeuDeReference();
      await afficher(tester);

      expect(valeur(tester, 'Coût Total Connu du Lot'), '225 725');
      expect(valeur(tester, 'Revenu Total du Lot'), '60 000');
      expect(valeur(tester, 'Marge Nette'), '-165 725');
      expect(valeur(tester, 'Coût de Revient / Sujet'), '2 257');
    });

    testWidgets('une marge négative est en rouge, une positive en vert', (
      tester,
    ) async {
      await jeuDeReference();
      await afficher(tester);

      final negative = tester.widget<CarteKpi>(
        find.ancestor(
          of: find.text('MARGE NETTE'),
          matching: find.byType(CarteKpi),
        ),
      );
      expect(negative.couleurValeur, const Color(0xFFBA1A1A));

      // Revenus portés à 300 000 : la marge devient positive.
      await db.delete(db.lotRevenues).go();
      await revenu(lotA, 'produit-1', 'Ventes — Poulet vif', 300000);
      await afficher(tester);

      final positive = tester.widget<CarteKpi>(
        find.ancestor(
          of: find.text('MARGE NETTE'),
          matching: find.byType(CarteKpi),
        ),
      );
      expect(positive.couleurValeur, const Color(0xFF065F46));
    });

    testWidgets(
      'détail des coûts : quatre lignes dans l\'ordre, et le total connu',
      (tester) async {
        await jeuDeReference();
        await afficher(tester);

        for (final (i, libelle) in [
          'Acquisition initiale',
          'Provende servie (cumul, prix indicatif)',
          'Frais vétérinaires',
          "Main d'œuvre imputée",
        ].indexed) {
          expect(
            find.descendant(
              of: find.byKey(Key('bilan-couts-ligne-$i')),
              matching: find.text(libelle),
            ),
            findsOneWidget,
            reason: libelle,
          );
        }
        expect(find.text('200 000 FCFA'), findsOneWidget);
        expect(find.text('13 725 FCFA'), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('bilan-couts-total'))).data,
          '225 725 FCFA',
        );
        expect(find.textContaining("Aucune clé d'imputation"), findsOneWidget);
      },
    );

    testWidgets(
      'détail des revenus : une ligne par produit, total du serveur',
      (tester) async {
        await jeuDeReference();
        await afficher(tester);

        expect(find.text('Ventes — Poulet vif'), findsOneWidget);
        expect(find.text('Ventes — Œufs de table'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('bilan-revenus-total')))
              .data,
          '60 000 FCFA',
        );
      },
    );

    testWidgets(
      '⚠️⚠️ revenus jamais reçus : « — » partout, jamais « 0 FCFA »',
      (tester) async {
        await lot(lotA, 'AVI-1');
        await afficher(tester);

        expect(valeur(tester, 'Revenu Total du Lot'), '—');
        expect(valeur(tester, 'Marge Nette'), '—');
        expect(
          tester
              .widget<Text>(find.byKey(const Key('bilan-revenus-total')))
              .data,
          '—',
        );
        expect(find.textContaining('pas encore reçus'), findsWidgets);
        expect(
          find.textContaining('Aucune vente encore enregistrée'),
          findsNothing,
        );
      },
    );

    testWidgets('revenus reçus et vides : le message de Laravel', (
      tester,
    ) async {
      await lot(lotA, 'AVI-1');
      await revenusTires();
      await afficher(tester);

      expect(
        find.text('Aucune vente encore enregistrée sur cette bande.'),
        findsOneWidget,
      );
      expect(valeur(tester, 'Revenu Total du Lot'), '0');
    });

    testWidgets(
      '⚠️ aucun verdict « rentable / déficitaire » : un encart à la place',
      (tester) async {
        await jeuDeReference();
        await afficher(tester);

        expect(find.textContaining('Lot rentable'), findsNothing);
        expect(find.textContaining('Lot déficitaire'), findsNothing);
        expect(find.byKey(const Key('bilan-marge-info')), findsOneWidget);
        expect(
          find.textContaining("clé d'imputation aux bandes"),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'l\'encart de méthode dit que les revenus sont ceux du dernier tirage',
      (tester) async {
        await jeuDeReference();
        await afficher(tester);

        expect(find.byKey(const Key('bilan-methode')), findsOneWidget);
        expect(find.textContaining('dernier tirage'), findsWidgets);
      },
    );

    testWidgets('des ventes du poste en attente sont annoncées', (
      tester,
    ) async {
      await jeuDeReference();
      await venteDuPoste('v1', lotA);
      await venteDuPoste('v2', lotA);
      await afficher(tester);

      expect(
        find.textContaining('2 vente(s) de ce poste imputée(s)'),
        findsOneWidget,
      );
    });

    testWidgets('aucune vente en attente : pas d\'encart', (tester) async {
      await jeuDeReference();
      await afficher(tester);

      expect(find.byKey(const Key('bilan-ventes-en-attente')), findsNothing);
    });

    testWidgets('changer de bande change les chiffres', (tester) async {
      await jeuDeReference();
      await lot(
        lotB,
        'AVI-2026-002',
        acquisition: 50000,
        date: DateTime(2026, 6, 1),
      );
      await afficher(tester);

      // La bande la plus récente (AVI-2026-002) est choisie d'emblée.
      expect(valeur(tester, 'Coût Total Connu du Lot'), '50 000');
      expect(valeur(tester, 'Revenu Total du Lot'), '0');

      await tester.tap(find.byKey(const Key('bilan-lot')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('AVI-2026-001').last);
      await tester.pumpAndSettle();

      expect(valeur(tester, 'Coût Total Connu du Lot'), '225 725');
      expect(valeur(tester, 'Revenu Total du Lot'), '60 000');
    });

    testWidgets('aucune bande : le message, sans cartes ni sélecteur', (
      tester,
    ) async {
      await afficher(tester);

      expect(find.text('Aucune bande pour le moment.'), findsOneWidget);
      expect(find.byType(CarteKpi), findsNothing);
      expect(find.byKey(const Key('bilan-lot')), findsNothing);
    });

    testWidgets('lg: deux colonnes de détail ; sous lg: elles s\'empilent', (
      tester,
    ) async {
      await jeuDeReference();

      await afficher(tester, taille: const Size(1600, 2400));
      final c = tester.getRect(find.byKey(const Key('bilan-couts')));
      final r = tester.getRect(find.byKey(const Key('bilan-revenus')));
      expect(c.top, r.top);

      await afficher(tester, taille: const Size(800, 3000));
      final c2 = tester.getRect(find.byKey(const Key('bilan-couts')));
      final r2 = tester.getRect(find.byKey(const Key('bilan-revenus')));
      expect(r2.top, greaterThan(c2.bottom));
    });
  });
}
