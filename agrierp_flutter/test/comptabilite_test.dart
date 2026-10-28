import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/immobilisations_repository.dart';
import 'package:agrierp/features/comptabilite/rapprochement_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cartes_attendues.dart';

/// Ticket F0.50 — COMPTABILITÉ (`comptabilite-hub.html`).
///
/// ⚠️⚠️ **LES ÉTATS LISENT LE JOURNAL, JAMAIS DES TABLES MÉTIER DISJOINTES.**
/// Grand Livre et Balance sont calculés à partir des écritures reçues — pas des
/// ventes et des achats du poste, qui donneraient une SECONDE comptabilité pour
/// la même ferme.
///
/// ⚠️⚠️ **UN DÉSÉQUILIBRE AU POSTE N'EST PAS UNE ERREUR COMPTABLE** : le
/// serveur garantit `SUM(debit) = SUM(credit)` avant de comptabiliser. Une
/// écriture déséquilibrée ici signale un TIRAGE INCOMPLET.
void main() {
  late AppDatabase db;
  late ComptabiliteRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ComptabiliteRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> compte(String cle, String code, String libelle, int classe) => db
      .into(db.chartOfAccounts)
      .insert(
        ChartOfAccountsCompanion.insert(
          id: uuid(cle),
          code: code,
          label: libelle,
          accountClass: Value(classe),
        ),
      );

  Future<void> exercice({String statut = 'ouvert', int annee = 2026}) => db
      .into(db.fiscalYears)
      .insert(
        FiscalYearsCompanion.insert(
          id: uuid('ex'),
          year: annee,
          startDate: Value(DateTime(annee, 1, 1)),
          endDate: Value(DateTime(annee, 12, 31)),
          status: Value(statut),
        ),
      );

  Future<void> ecriture(
    String cle, {
    required DateTime date,
    String reference = 'Vente au comptoir',
    String source = 'sale',
  }) => db
      .into(db.accountingEntries)
      .insert(
        AccountingEntriesCompanion.insert(
          id: uuid(cle),
          fiscalYearId: Value(uuid('ex')),
          entryDate: date,
          reference: Value(reference),
          sourceType: Value(source),
        ),
      );

  Future<void> ligne(
    String cle, {
    required String cleEcriture,
    required String cleCompte,
    double debit = 0,
    double credit = 0,
  }) => db
      .into(db.accountingEntryLines)
      .insert(
        AccountingEntryLinesCompanion.insert(
          id: uuid(cle),
          entryId: uuid(cleEcriture),
          accountId: uuid(cleCompte),
          debit: Value(debit),
          credit: Value(credit),
        ),
      );

  /// Une écriture équilibrée : caisse au débit, vente au crédit.
  Future<void> vente(
    String cle, {
    required DateTime date,
    required double montant,
  }) async {
    await ecriture(cle, date: date);
    await ligne('${cle}d', cleEcriture: cle, cleCompte: 'c531', debit: montant);
    await ligne(
      '${cle}c',
      cleEcriture: cle,
      cleCompte: 'c701',
      credit: montant,
    );
  }

  /// Une écriture équilibrée en sens inverse : caisse au CRÉDIT.
  ///
  /// ⚠️ Elle sert à séparer un SOLDE d'un cumul de mouvements : la caisse est
  /// alors mouvementée dans les deux sens, et les deux notions divergent.
  Future<void> depense(
    String cle, {
    required DateTime date,
    required double montant,
  }) async {
    await ecriture(cle, date: date, reference: 'Achat provende');
    await ligne(
      '${cle}c',
      cleEcriture: cle,
      cleCompte: 'c531',
      credit: montant,
    );
    await ligne('${cle}d', cleEcriture: cle, cleCompte: 'c701', debit: montant);
  }

  Future<void> planMinimal() async {
    await compte('c531', '531', 'Caisse', 5);
    await compte('c701', '701', 'Ventes de produits', 7);
    await exercice();
  }

  Future<void> afficher(WidgetTester tester, {DateTime? maintenant}) async {
    tester.view.physicalSize = const Size(1700, 2200);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: ComptabiliteScreen(
          depot: depot,
          depotImmobilisations: ImmobilisationsRepository(database: db),
          depotRapprochement: RapprochementRepository(database: db),
          maintenant: maintenant == null ? DateTime.now : () => maintenant,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester, PageComptable page) async {
    await tester.tap(find.byKey(Key('carte-${page.name}')));
    await tester.pumpAndSettle();
  }

  group('dépôt', () {
    /// ⚠️⚠️ LE SOLDE PROGRESSIF SUIT L'ORDRE DES DATES, pas l'ordre d'arrivée.
    test('⚠️⚠️ le grand livre cumule dans l ordre des dates', () async {
      await planMinimal();
      // Insérées à l'envers, comme deux tirages successifs les rapporteraient.
      await vente('v2', date: DateTime(2026, 3, 10), montant: 5000);
      await vente('v1', date: DateTime(2026, 1, 5), montant: 12000);

      final d = await depot.charger();
      final livre = d.grandLivre(uuid('c531'));

      expect(livre.map((m) => m.ecriture.entryDate), [
        DateTime(2026, 1, 5),
        DateTime(2026, 3, 10),
      ]);
      expect(livre.map((m) => m.soldeProgressif), [12000, 17000]);
    });

    test('la balance cumule débits et crédits par compte', () async {
      await planMinimal();
      await vente('v1', date: DateTime(2026, 1, 5), montant: 12000);
      await vente('v2', date: DateTime(2026, 3, 10), montant: 5000);

      final d = await depot.charger();
      // Ticket F0.86 : la balance a une PÉRIODE ; l'exercice 2026 entier couvre les deux ventes.
      final balance = d
          .balanceGenerale(
            debut: DateTime(2026, 1, 1),
            fin: DateTime(2026, 12, 31),
          )
          .lignes;

      expect(balance.length, 2);
      expect(balance.first.code, '531');
      expect(balance.first.mouvementsDebit, 17000);
      expect(balance.last.code, '701');
      expect(balance.last.mouvementsCredit, 17000);
    });

    /// ⚠️ Un compte sans mouvement n'encombre pas la balance.
    test(
      '⚠️ les comptes sans mouvement ne figurent pas à la balance',
      () async {
        await planMinimal();
        await compte('c601', '601', 'Achats', 6);
        await vente('v1', date: DateTime(2026, 1, 5), montant: 1000);

        final d = await depot.charger();

        expect(
          d
              .balanceGenerale(
                debut: DateTime(2026, 1, 1),
                fin: DateTime(2026, 12, 31),
              )
              .lignes
              .map((l) => l.code),
          ['531', '701'],
        );
      },
    );

    /// ⚠️⚠️ LE CŒUR DU TICKET : un déséquilibre signale un tirage incomplet.
    test(
      '⚠️⚠️ une écriture sans toutes ses lignes est dite incomplète',
      () async {
        await planMinimal();
        await ecriture('boiteuse', date: DateTime(2026, 5, 2));
        await ligne(
          'l1',
          cleEcriture: 'boiteuse',
          cleCompte: 'c531',
          debit: 9000,
        );

        final d = await depot.charger();

        expect(d.ecrituresIncompletes, 1);
        expect(d.journal.single.equilibree, isFalse);
      },
    );

    test('une écriture équilibrée ne compte pas comme incomplète', () async {
      await planMinimal();
      await vente('v1', date: DateTime(2026, 1, 5), montant: 1000);

      final d = await depot.charger();

      expect(d.ecrituresIncompletes, 0);
      expect(d.totalDebit, d.totalCredit);
    });

    test('l exercice ouvert est reconnu', () async {
      await exercice(statut: 'ouvert', annee: 2026);

      final d = await depot.charger();

      expect(d.exerciceOuvert?.year, 2026);
    });

    test('les comptes débités et crédités sont nommés par leur code', () async {
      await planMinimal();
      await vente('v1', date: DateTime(2026, 1, 5), montant: 1000);

      final d = await depot.charger();

      expect(d.journal.single.comptesDebites, '531');
      expect(d.journal.single.comptesCredites, '701');
    });
  });

  group('cartes de la maquette (ticket F0.55)', () {
    /// ⚠️⚠️ **UN SOLDE N'EST PAS UN CUMUL DE MOUVEMENTS.** La balance totalise
    /// les SOLDES : un compte est débiteur OU créditeur, jamais les deux.
    /// Additionner la colonne des débits donnerait le total des mouvements —
    /// bien plus grand, tout aussi équilibré, et faux sous ce libellé.
    test('⚠️⚠️ la balance totalise des soldes, pas des mouvements', () async {
      await planMinimal();
      await vente('v1', date: DateTime(2026, 1, 5), montant: 12000);
      await vente('v2', date: DateTime(2026, 3, 10), montant: 5000);

      final d = await depot.charger();
      final b = d.balanceGenerale(
        debut: DateTime(2026, 1, 1),
        fin: DateTime(2026, 12, 31),
      );

      // 531 est débiteur de 17 000, 701 créditeur de 17 000.
      expect(b.totalFinalDebit, 17000);
      expect(b.totalFinalCredit, 17000);

      // Les mouvements, eux, valent aussi 17 000 de chaque côté ici : le
      // contrôle ci-dessous sépare les deux notions sur un compte MOUVEMENTÉ
      // dans les deux sens.
      expect(d.totalDebit, 17000);
    });

    /// ⚠️ Un compte mouvementé dans les deux sens : son solde n'est pas la
    /// somme de ses mouvements.
    test('⚠️ un compte débité puis crédité ne compte que son solde', () async {
      await planMinimal();
      await vente('v1', date: DateTime(2026, 1, 5), montant: 12000);
      await depense('d1', date: DateTime(2026, 2, 8), montant: 5000);

      final d = await depot.charger();
      final b = d.balanceGenerale(
        debut: DateTime(2026, 1, 1),
        fin: DateTime(2026, 12, 31),
      );

      // La caisse a été débitée de 12 000 puis créditée de 5 000 : solde 7 000.
      expect(b.totalFinalDebit, 7000);
      // Ses mouvements, eux, gardent les deux sens.
      expect(b.totalMouvementsDebit, 17000);
      // Ses MOUVEMENTS, eux, totalisent 17 000 au débit.
      expect(d.totalDebit, 17000);
    });

    /// ⚠️ Le mois se compare avec l'année — sans quoi le même mois de l'an
    /// passé entrerait dans le compte.
    test(
      '⚠️ les écritures du mois excluent le même mois de l année passée',
      () async {
        await planMinimal();
        await vente('v1', date: DateTime(2026, 5, 4), montant: 1000);
        await vente('v2', date: DateTime(2025, 5, 4), montant: 1000);

        final d = await depot.charger();

        expect(d.ecrituresDuMois(DateTime(2026, 5, 20)), 1);
      },
    );

    test('« Comptes actifs » et « Exercice » suivent le tirage', () async {
      await planMinimal();

      final d = await depot.charger();

      expect(d.comptesActifs, 2);
      expect(d.anneeExerciceOuvert, 2026);
    });

    /// ⚠️⚠️ Un compte SANS aucune écriture n'a pas un solde d'ouverture de 0 : le poste ne sait rien
    /// de lui (ticket F0.85 : l'ouverture se calcule désormais sur les écritures reçues, comme le
    /// serveur, et reste « inconnue » quand il n'y en a pas).
    test(
      '⚠️⚠️ le solde d ouverture est inconnu, pas nul, sans écriture',
      () async {
        await planMinimal();

        final d = await depot.charger();
        final g = d.grandLivreCompte(uuid('c531'), debut: DateTime(2026, 3, 1));

        expect(g.sansEcriture, isTrue);
        expect(g.soldeOuverture, isNull);
        expect(g.soldeFinal, isNull);
      },
    );
  });

  group('écran', () {
    /// ⚠️⚠️ NEUF CARTES, PAS DES ONGLETS : ce hub navigue par cartes.
    testWidgets(
      '⚠️⚠️ les neuf cartes du hub sont là, dans l ordre de la maquette',
      (tester) async {
        await afficher(tester);

        for (final page in PageComptable.values) {
          if (page == PageComptable.hub) continue;
          expect(find.text(page.libelle), findsOneWidget, reason: page.libelle);
        }
      },
    );

    /// ⚠️⚠️ **LE NOMBRE DE CARTES, PAGE PAR PAGE** (ticket F0.54). Ce hub-ci
    /// n'a pas d'onglets mais des CARTES DE NAVIGATION : chaque page s'ouvre
    /// depuis le hub et se referme par « Retour ». Le contrôle suit donc le
    /// même chemin que l'utilisateur.
    ///
    /// ⚠️ Le hub lui-même n'est pas relevé : `comptabilite-hub.html` n'a pas
    /// été passé à l'extracteur de structure. Seules ses quatre pages portées
    /// le sont.
    testWidgets('⚠️⚠️ chaque page rend le nombre de cartes de la maquette', (
      tester,
    ) async {
      await planMinimal();

      const pages = <PageComptable, String>{
        PageComptable.planComptable: 'plan-comptable.html',
        PageComptable.journal: 'journal-comptable.html',
        PageComptable.grandLivre: 'grand-livre.html',
        PageComptable.balance: 'balance-generale.html',
      };

      await afficher(tester);

      for (final page in pages.keys) {
        await ouvrir(tester, page);

        expect(
          find.byType(CarteKpi),
          findsNWidgets(cartesAttendues(pages[page]!)),
          reason: page.libelle,
        );

        // ⚠️ ON REVIENT PAR LE BOUTON DE L'ÉCRAN, pas en le reconstruisant :
        // `pumpWidget` réutilise l'état d'un widget de même type, si bien
        // qu'un second `afficher` laisse l'écran sur la page déjà ouverte —
        // et la carte suivante devient introuvable.
        await tester.tap(find.byKey(const Key('retour-hub')));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('le plan comptable porte les quatre colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, PageComptable.planComptable);

      for (final colonne in ['N° COMPTE', 'INTITULÉ', 'CLASSE', 'ACTIONS']) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('un compte descendu est affiché avec sa classe', (
      tester,
    ) async {
      await planMinimal();

      await afficher(tester);
      await ouvrir(tester, PageComptable.planComptable);

      expect(find.text('531'), findsOneWidget);
      expect(find.text('Caisse'), findsOneWidget);
    });

    testWidgets('le journal porte les sept colonnes de la maquette', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, PageComptable.journal);

      for (final colonne in [
        'N° PIÈCE',
        'DATE',
        'LIBELLÉ',
        'DÉBIT',
        'CRÉDIT',
        'MONTANT',
        'ACTIONS',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('une écriture reçue est affichée avec ses comptes', (
      tester,
    ) async {
      await planMinimal();
      await vente('v1', date: DateTime(2026, 1, 5), montant: 12000);

      await afficher(tester);
      await ouvrir(tester, PageComptable.journal);

      expect(find.text('Vente au comptoir'), findsOneWidget);
      expect(find.text('531'), findsOneWidget);
      expect(find.text('701'), findsOneWidget);

      // ⚠️ CHERCHÉ DANS LA LIGNE, PAS SUR L'ÉCRAN. Depuis le ticket F0.55, les
      // cartes de la maquette affichent les mêmes totaux au-dessus du tableau :
      // un `find.text` global compterait trois occurrences du même montant.
      expect(
        find.descendant(
          of: find.byKey(const Key('ligne-0')),
          matching: find.text('12 000'),
        ),
        findsOneWidget,
      );
    });

    /// Ticket CP-2 — la saisie manuelle est PORTÉE (en demande, jouée par le serveur) : le bouton du Blade est là et l'ancienne
    /// mention « la saisie reste sur le web » a disparu.
    testWidgets('⚠️⚠️ le journal offre « Saisie d\'Écriture » et ne renvoie plus au web', (
      tester,
    ) async {
      await afficher(tester);
      await ouvrir(tester, PageComptable.journal);

      expect(find.byKey(const Key('journal-saisie-ecriture')), findsOneWidget);
      expect(find.textContaining("Une écriture naît d'une opération"), findsNothing);
    });

    testWidgets('le grand livre porte les six colonnes de la maquette', (
      tester,
    ) async {
      await planMinimal();

      await afficher(tester);
      await ouvrir(tester, PageComptable.grandLivre);

      for (final colonne in [
        'DATE',
        'N° PIÈCE',
        'LIBELLÉ',
        'DÉBIT',
        'CRÉDIT',
        'SOLDE PROGRESSIF',
      ]) {
        expect(find.text(colonne), findsOneWidget, reason: colonne);
      }
    });

    testWidgets('le grand livre montre le solde progressif du compte choisi', (
      tester,
    ) async {
      await planMinimal();
      // ⚠️ Ticket F0.85 : le Grand Livre s'ouvre sur la période « du premier du mois à aujourd'hui »,
      // comme le web. Les deux pièces sont donc du même mois, et l'horloge du poste est injectée.
      await vente('v1', date: DateTime(2026, 3, 5), montant: 12000);
      await vente('v2', date: DateTime(2026, 3, 10), montant: 5000);

      await afficher(tester, maintenant: DateTime(2026, 3, 20));
      await ouvrir(tester, PageComptable.grandLivre);

      // ⚠️ Même raison : le solde progressif se lit dans la ligne, pas sur
      // l'écran — les cartes du Grand Livre portent des totaux voisins.
      expect(
        find.descendant(
          // ⚠️ DEUXIÈME ligne : le solde progressif cumule 12 000 puis
          // 17 000. Le contrôle global d'origine ne disait pas sur quelle
          // ligne il tombait.
          of: find.byKey(const Key('ligne-1')),
          matching: find.text('17 000'),
        ),
        findsOneWidget,
      );
    });

    /// ⚠️⚠️ **HUIT COLONNES SOUS TROIS GROUPES, PAS SEPT À PLAT.** La maquette
    /// coiffe « Solde Ouverture », « Mouvements Période » et « Solde Final »
    /// (`colspan=2`) d'une seconde rangée Débit/Crédit, et garde « N° Compte »
    /// et « Libellé » sur toute la hauteur (`rowspan=2`). Porté à plat, le
    /// rapprochement débit/crédit d'un solde devenait impossible à lire —
    /// trouvé au ticket F0.50 en apprenant à l'outil de structure à lire les
    /// en-têtes à deux niveaux.
    testWidgets(
      '⚠️⚠️ la balance porte ses trois groupes et ses huit colonnes',
      (tester) async {
        await afficher(tester);
        await ouvrir(tester, PageComptable.balance);

        for (final groupe in [
          'N° COMPTE',
          'LIBELLÉ',
          'SOLDE OUVERTURE',
          'MOUVEMENTS PÉRIODE',
          'SOLDE FINAL',
        ]) {
          expect(find.text(groupe), findsOneWidget, reason: groupe);
        }

        // Trois groupes, chacun coiffant un Débit et un Crédit.
        expect(find.text('DÉBIT'), findsNWidgets(3));
        expect(find.text('CRÉDIT'), findsNWidgets(3));
      },
    );

    /// ⚠️⚠️ Ticket F0.86 : REMPLACE le test F0.50 « les soldes d'ouverture portent un tiret motivé ».
    /// Sa prémisse (« l'exercice précédent ne descend pas ») est fausse depuis 15.29 : le tirage ne
    /// filtre pas par exercice. L'ouverture est donc CALCULÉE, comme le serveur.
    testWidgets('⚠️⚠️ le solde d ouverture est calculé sur le journal reçu', (
      tester,
    ) async {
      await planMinimal();
      await vente('v1', date: DateTime(2026, 1, 5), montant: 1000);

      await afficher(tester, maintenant: DateTime(2026, 3, 15));
      await ouvrir(tester, PageComptable.balance);

      // Mars 2026 : la vente de janvier est une OUVERTURE de 1 000 au débit de la caisse.
      expect(
        tester.widget<Text>(find.byKey(const Key('bal-0-0'))).data,
        '1 000',
      );
      expect(
        find.textContaining("supposent l'exercice précédent"),
        findsNothing,
      );
    });

    /// ⚠️⚠️ TROIS PAGES RESTENT SUR LE WEB, chacune avec SA raison (quatre avant CP-5, cinq avant EX8 : les États Financiers sont
    /// embarqués).
    testWidgets('⚠️⚠️ chaque page non embarquée porte son propre motif', (
      tester,
    ) async {
      await afficher(tester);
      // Sur le hub, seules ces pages disent « Consultation sur la surface web » (plus les États Financiers).
      expect(
        find.text('Consultation sur la surface web'),
        findsNWidgets(_ComptabiliteMotifs.attendus.length),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('carte-etatsFinanciers')),
          matching: find.text('Consultation sur la surface web'),
        ),
        findsNothing,
      );

      for (final entree in _ComptabiliteMotifs.attendus.entries) {
        await ouvrir(tester, entree.key);
        expect(
          find.textContaining(entree.value),
          findsOneWidget,
          reason: entree.key.libelle,
        );
        await tester.tap(find.byKey(const Key('retour-hub')));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('sans écriture, le journal le dit', (tester) async {
      await afficher(tester);
      await ouvrir(tester, PageComptable.journal);

      expect(find.text('— Aucune écriture synchronisée —'), findsOneWidget);
    });
  });
}

/// Les quatre motifs attendus, un par page non embarquée — chacun DIFFÉRENT. Ticket EX8 (décision Q5) : les États
/// Financiers sont embarqués (`comparatif_n_moins_un_parite_test.dart`).
class _ComptabiliteMotifs {
  static const attendus = <PageComptable, String>{
    PageComptable.cloture: "hors du contrat de synchronisation",
    PageComptable.analytique: 'centres de coût',
    PageComptable.tva: 'pièce fiscale',
    // Ticket CP-5 : le rapprochement bancaire est embarqué (page `RapprochementPage`).
  };
}
