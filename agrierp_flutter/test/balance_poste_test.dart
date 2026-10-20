import 'dart:io';
import 'dart:math';

import 'package:agrierp/core/comptabilite/exercice_choisi.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chemins_depot.dart';

/// Ticket F0.86 — BALANCE GÉNÉRALE DU POSTE (item 9, ticket T3).
///
/// Le serveur Laravel fait foi (`FinancialReportService::balanceGenerale` et le composant
/// `Livewire\Comptabilite\BalanceGenerale`) ; `balance-generale.html` fait foi sur le visuel. Avant
/// ce ticket, la Balance du poste :
///  1. cumulait TOUT le journal reçu, sans période ni sélecteur ;
///  2. affichait l'ouverture en « — » partout (« l'exercice précédent ne descend pas » : faux depuis
///     15.29, le tirage ne filtre pas par exercice) ;
///  3. n'avait ni carte « Écart (doit être 0) », ni bandeau « Balance Déséquilibrée », ni ligne
///     TOTAUX ;
///  4. écrivait un débit nul comme une case VIDE et un solde final nul comme « 0 » (la maquette et la
///     page web écrivent « — »).
///
/// ⚠️⚠️ Les chiffres ci-dessous sont des LITTÉRAUX calculés À LA MAIN (détail en commentaire), jamais
/// obtenus en appelant le code testé ; ils sont confrontés au VRAI service PHP par
/// `tests/Feature/BalanceJeuDuPosteTest.php` (même jeu). Une RECOMPUTATION INDÉPENDANTE, écrite ici en
/// centimes entiers sur les données brutes, est en outre comparée au dépôt ET à l'écran, sur ce jeu et
/// sur un jeu pseudo-aléatoire.
void main() {
  late AppDatabase db;
  late ComptabiliteRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ComptabiliteRepository(database: db);
  });

  tearDown(() async => db.close());

  /// Les lignes écrites en base, gardées À PLAT pour la recomputation indépendante.
  final brut = <({DateTime jour, String code, int debitCts, int creditCts})>[];
  setUp(brut.clear);

  Future<void> compte(String code, String libelle, int classe) => db
      .into(db.chartOfAccounts)
      .insert(
        ChartOfAccountsCompanion.insert(
          id: uuid('c$code'),
          code: code,
          label: libelle,
          accountClass: Value(classe),
        ),
      );

  Future<void> exercice({
    required int annee,
    required DateTime debut,
    required DateTime fin,
    String statut = 'ouvert',
  }) => db
      .into(db.fiscalYears)
      .insert(
        FiscalYearsCompanion.insert(
          id: uuid('ex$annee'),
          year: annee,
          startDate: Value(debut),
          endDate: Value(fin),
          status: Value(statut),
        ),
      );

  /// Une ligne brute ; [debit] / [credit] en francs (centimes possibles).
  Future<void> ligne(
    String cle,
    String cleEcriture,
    DateTime jour,
    String code, {
    double debit = 0,
    double credit = 0,
  }) async {
    await db
        .into(db.accountingEntryLines)
        .insert(
          AccountingEntryLinesCompanion.insert(
            id: uuid(cle),
            entryId: uuid(cleEcriture),
            accountId: uuid('c$code'),
            debit: Value(debit),
            credit: Value(credit),
          ),
        );
    brut.add((
      jour: jour,
      code: code,
      debitCts: (debit * 100).round(),
      creditCts: (credit * 100).round(),
    ));
  }

  /// Une écriture à DEUX lignes, équilibrée.
  Future<void> ecriture(
    String cle,
    DateTime date,
    String debit,
    String credit,
    double montant,
  ) async {
    await db
        .into(db.accountingEntries)
        .insert(
          AccountingEntriesCompanion.insert(
            id: uuid(cle),
            entryDate: date,
            reference: Value('OD — $cle'),
          ),
        );
    await ligne('${cle}d', cle, date, debit, debit: montant);
    await ligne('${cle}c', cle, date, credit, credit: montant);
  }

  /// Le jeu, ÉCRIT À LA MAIN, inséré dans le désordre. Période de référence : MARS 2026.
  ///
  /// | clé | date       | débit | crédit | montant    | rôle dans le test                          |
  /// | e01 | 2026-01-10 | 531   | 101    | 100 000    | ouverture                                  |
  /// | e02 | 2026-02-15 | 601   | 401    |  40 000    | ouverture                                  |
  /// | e03 | 2026-02-28 | 531   | 701    |   3 000    | VEILLE du début : ouverture                |
  /// | e04 | 2026-03-01 | 531   | 701    |   2 000    | JOUR du début : période, pas ouverture     |
  /// | e05 | 2026-03-02 | 401   | 531    |  15 000    | même compte débité/crédité dans la période |
  /// | e06 | 2026-03-10 | 411   | 701    |  10 000,40 | centimes                                   |
  /// | e07 | 2026-03-15 | 531   | 411    |   4 000,15 | centimes ; 411 mouvementé dans les 2 sens  |
  /// | e08 | 2026-03-31 | 531   | 701    |   1 000    | JOUR de fin : inclus                       |
  /// | e09 | 2026-04-01 | 531   | 701    |   7 000    | LENDEMAIN : ni période ni ouverture        |
  /// | e10 | 2026-04-02 | 681   | 281    |     600    | comptes mouvementés APRÈS : hors balance   |
  /// | e11 | 2026-02-01 | 521   | 531    |   8 000    | 521 : ouverture débit 8 000 …              |
  /// | e12 | 2026-02-20 | 531   | 521    |   8 000    | … et crédit 8 000 : net 0, hors balance    |
  /// | e13 | 2026-03-20 | 601   | 5212   |   2 500    | 5212 (débiteur par nature) CRÉDITEUR       |
  /// | e14 | 2026-03-25 | 585   | 531    |   3 000    | 585 : débit 3 000 …                        |
  /// | e15 | 2026-03-26 | 531   | 585    |   3 000    | … crédit 3 000 : solde final nul, MAIS listé |
  Future<void> jeu() async {
    for (final (code, libelle, classe) in [
      ('531', 'Caisse', 5),
      ('101', 'Capital', 1),
      ('601', 'Achats', 6),
      ('401', 'Fournisseurs', 4),
      ('701', 'Ventes', 7),
      ('411', 'Clients', 4),
      ('521', 'Banque', 5),
      ('5212', 'Mobile Money', 5),
      ('585', 'Virements de fonds', 5),
      ('681', 'Dotations', 6),
      ('281', 'Amortissements', 2),
      ('419', 'Clients créditeurs', 4),
    ]) {
      await compte(code, libelle, classe);
    }
    await exercice(
      annee: 2026,
      debut: DateTime(2026, 1, 1),
      fin: DateTime(2026, 12, 31),
    );

    await ecriture('e15', DateTime(2026, 3, 26), '531', '585', 3000);
    await ecriture('e09', DateTime(2026, 4, 1), '531', '701', 7000);
    await ecriture('e01', DateTime(2026, 1, 10), '531', '101', 100000);
    await ecriture('e13', DateTime(2026, 3, 20), '601', '5212', 2500);
    await ecriture('e04', DateTime(2026, 3, 1), '531', '701', 2000);
    await ecriture('e02', DateTime(2026, 2, 15), '601', '401', 40000);
    await ecriture('e12', DateTime(2026, 2, 20), '531', '521', 8000);
    await ecriture('e06', DateTime(2026, 3, 10), '411', '701', 10000.40);
    await ecriture('e10', DateTime(2026, 4, 2), '681', '281', 600);
    await ecriture('e03', DateTime(2026, 2, 28), '531', '701', 3000);
    await ecriture('e07', DateTime(2026, 3, 15), '531', '411', 4000.15);
    await ecriture('e11', DateTime(2026, 2, 1), '521', '531', 8000);
    await ecriture('e05', DateTime(2026, 3, 2), '401', '531', 15000);
    await ecriture('e14', DateTime(2026, 3, 25), '585', '531', 3000);
    await ecriture('e08', DateTime(2026, 3, 31), '531', '701', 1000);
  }

  final debutMars = DateTime(2026, 3, 1);
  final finMars = DateTime(2026, 3, 31);

  Future<BalanceGenerale> balance(DateTime debut, DateTime fin) async {
    final d = await depot.charger();
    return d.balanceGenerale(debut: debut, fin: fin);
  }

  /// Les six montants d'une ligne, dans l'ordre des colonnes.
  List<double> six(LigneBalance l) => [
    l.ouvertureDebit,
    l.ouvertureCredit,
    l.mouvementsDebit,
    l.mouvementsCredit,
    l.finalDebit,
    l.finalCredit,
  ];

  List<double> totaux(BalanceGenerale b) => [
    b.totalOuvertureDebit,
    b.totalOuvertureCredit,
    b.totalMouvementsDebit,
    b.totalMouvementsCredit,
    b.totalFinalDebit,
    b.totalFinalCredit,
  ];

  // ── Recomputation INDÉPENDANTE (centimes entiers, données brutes, aucun appel au code testé) ──

  int jourDe(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// Règle relue dans `FinancialReportService::balanceGenerale`, réécrite autrement : en centimes
  /// entiers, sur les lignes brutes, codes connus seulement.
  ///
  /// Tickets EX1 / EX2 — l'ouverture suit R1 (PRD `docs/prd/exercices-comptables.md` § 5), réécrite ici pour les
  /// jeux de ce fichier (exercices CIVILS ; seul 2026 est enregistré, ouvert, sans à-nouveau) :
  ///  - année ≤ 2026 (aucun exercice enregistré avant) : historique antérieur au 01/01, classes 1 à 5 ; son
  ///    résultat (classes 6+) porté au 131 (bénéfice) ou 139 (perte), FUSIONNÉ (pas une ligne provisoire) ;
  ///  - année 2027 (précédent 2026 ouvert) : R3 — clôture calculée de 2026 (son ouverture + ses mouvements,
  ///    classes 1 à 5), et son résultat sur une ligne PROVISOIRE à part (131 / 139) ;
  ///  - puis, dans l'exercice, les mouvements du 01/01 à la veille du début (toutes classes).
  ({List<(String, List<int>)> lignes, List<int> totaux}) recalcul(
    DateTime debut,
    DateTime fin,
  ) {
    final d = jourDe(debut);
    final f = jourDe(fin);
    bool bilan(String code) => int.parse(code[0]) <= 5;

    Map<String, int> nets(int? du, int au) {
      final r = <String, int>{};
      for (final l in brut) {
        final j = jourDe(l.jour);
        if (j > au || (du != null && j < du)) continue;
        r[l.code] = (r[l.code] ?? 0) + l.debitCts - l.creditCts;
      }
      return r;
    }

    /// (comptes de bilan, résultat reporté à part) — résultat en « produits − charges ».
    (Map<String, int>, int) cloture(Map<String, int> depart, Map<String, int> m) {
      final c = Map<String, int>.of(depart);
      var resultat = 0;
      m.forEach((code, n) {
        if (bilan(code)) {
          c[code] = (c[code] ?? 0) + n;
        } else {
          resultat -= n;
        }
      });
      return (c, resultat);
    }

    String compteResultat(int r) => r > 0 ? '131' : '139';

    ({Map<String, int> comptes, int provisoire}) ouverture(int annee) {
      if (annee <= 2026) {
        final (c, r) = cloture({}, nets(null, (annee - 1) * 10000 + 1231));
        if (r != 0) c[compteResultat(r)] = (c[compteResultat(r)] ?? 0) - r;
        return (comptes: c, provisoire: 0);
      }
      final o = ouverture(annee - 1);
      final depart = Map<String, int>.of(o.comptes);
      if (o.provisoire != 0) {
        final code = o.provisoire < 0 ? '131' : '139';
        depart[code] = (depart[code] ?? 0) + o.provisoire;
      }
      final (c, r) = cloture(
        depart,
        nets((annee - 1) * 10000 + 101, (annee - 1) * 10000 + 1231),
      );
      return (comptes: c, provisoire: -r);
    }

    final annee = d ~/ 10000;
    final o = ouverture(annee);
    final ouv = Map<String, int>.of(o.comptes);
    nets(annee * 10000 + 101, d - 1).forEach((code, n) {
      ouv[code] = (ouv[code] ?? 0) + n;
    });
    // `d - 1` sur un 1er du mois tombe sur un « jour 0 » : aucune écriture n'y est datée, la borne reste juste.

    final perD = <String, int>{};
    final perC = <String, int>{};
    for (final l in brut) {
      final j = jourDe(l.jour);
      if (j >= d && j <= f) {
        perD[l.code] = (perD[l.code] ?? 0) + l.debitCts;
        perC[l.code] = (perC[l.code] ?? 0) + l.creditCts;
      }
    }

    // La ligne provisoire suit le compte réel du même numéro (aucun 131 / 139 au plan de ces jeux).
    final codes = {...ouv.keys, ...perD.keys}.toList()..sort();
    final entrees = <(String, int, int, int)>[
      for (final c in codes) (c, ouv[c] ?? 0, perD[c] ?? 0, perC[c] ?? 0),
    ];
    if (o.provisoire != 0) {
      final code = o.provisoire < 0 ? '131' : '139';
      var i = entrees.indexWhere((e) => e.$1.compareTo(code) > 0);
      if (i < 0) i = entrees.length;
      entrees.insert(i, (code, o.provisoire, 0, 0));
    }

    final lignes = <(String, List<int>)>[];
    final t = List<int>.filled(6, 0);
    for (final (c, net, pd, pc) in entrees) {
      if (net == 0 && pd == 0 && pc == 0) continue;
      final od = net > 0 ? net : 0;
      final oc = net < 0 ? -net : 0;
      final fn = od + pd - oc - pc;
      final v = [od, oc, pd, pc, fn > 0 ? fn : 0, fn < 0 ? -fn : 0];
      lignes.add((c, v));
      for (var i = 0; i < 6; i++) {
        t[i] += v[i];
      }
    }
    return (lignes: lignes, totaux: t);
  }

  List<int> enCentimes(List<double> v) => [
    for (final x in v) (x * 100).round(),
  ];

  /// Format d'affichage réécrit indépendamment : `number_format($x, 0, ',', ' ')`.
  String formatCts(int cts) {
    final entier = (cts / 100).round();
    final s = entier.abs().toString();
    final g = s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
    return entier < 0 ? '-$g' : g;
  }

  /// Format de l'ÉCART réécrit indépendamment (ticket F0.88, arbitrage client du 13/10/2026) :
  /// « 0 » s'il est nul au centime, sinon francs groupés par trois (espace), virgule, deux
  /// centimes ; signe de l'écart (débits − crédits) porté seulement s'il est non nul.
  String formatEcartCts(int cts) {
    if (cts == 0) return '0';
    final francs = (cts.abs() ~/ 100).toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ' ',
    );
    final reste = (cts.abs() % 100).toString().padLeft(2, '0');
    return '${cts < 0 ? '-' : ''}$francs,$reste';
  }

  // ═══════════════════════════════════════════════════════════════════════════════════════════

  group('défaut 1 : la règle du serveur, sur MARS 2026', () {
    test(
      '⚠️⚠️ les comptes, dans l ordre des codes (comparaison de chaînes)',
      () async {
        await jeu();
        final b = await balance(debutMars, finMars);

        // 521 : ouverture nette 0, aucun mouvement → hors balance ; 681 / 281 : mouvementés APRÈS la
        // période → hors balance ; 419 : jamais mouvementé. « 5212 » < « 531 » : tri de CHAÎNES, comme
        // `strcmp` du serveur.
        expect(b.lignes.map((l) => l.code), [
          '101',
          '401',
          '411',
          '5212',
          '531',
          '585',
          '601',
          '701',
        ]);
      },
    );

    test('⚠️⚠️ chaque ligne : ouverture NETTE, mouvements BRUTS, final NET', () async {
      await jeu();
      final b = await balance(debutMars, finMars);
      final parCode = {for (final l in b.lignes) l.code: six(l)};

      // 101 : ouverture crédit 100 000 (e01) ; aucun mouvement ; final crédit 100 000.
      expect(parCode['101'], [0, 100000, 0, 0, 0, 100000]);
      // 401 : ouverture crédit 40 000 (e02) ; débit 15 000 (e05) ; final 15 000 − 40 000 = crédit 25 000.
      expect(parCode['401'], [0, 40000, 15000, 0, 0, 25000]);
      // 411 : débit 10 000,40 (e06), crédit 4 000,15 (e07) ; final débit 6 000,25.
      expect(parCode['411'], [0, 0, 10000.40, 4000.15, 6000.25, 0]);
      // 5212 : crédit 2 500 (e13) ; débiteur PAR NATURE mais CRÉDITEUR de fait : placé au crédit.
      expect(parCode['5212'], [0, 0, 0, 2500, 0, 2500]);
      // 531 : ouverture = 100 000 + 3 000 + 8 000 − 8 000 = 103 000 débit (e01, e03, e12, e11) ;
      // période débit 2 000 + 4 000,15 + 1 000 + 3 000 = 10 000,15 (e04, e07, e08, e15),
      // crédit 15 000 + 3 000 = 18 000 (e05, e14) ; final 103 000 + 10 000,15 − 18 000 = 95 000,15.
      expect(parCode['531'], [103000, 0, 10000.15, 18000, 95000.15, 0]);
      // 585 : débit 3 000 et crédit 3 000 dans la période ; final nul, MAIS listé (mouvementé).
      expect(parCode['585'], [0, 0, 3000, 3000, 0, 0]);
      // 601 : ouverture débit 40 000 (e02) ; débit 2 500 (e13) ; final débit 42 500.
      expect(parCode['601'], [40000, 0, 2500, 0, 42500, 0]);
      // 701 : ouverture crédit 3 000 (e03) ; crédit 2 000 + 10 000,40 + 1 000 = 13 000,40 ;
      // final crédit 16 000,40. e09 (1er avril) n'entre nulle part.
      expect(parCode['701'], [0, 3000, 0, 13000.40, 0, 16000.40]);
    });

    test('⚠️⚠️ les six totaux et l écart', () async {
      await jeu();
      final b = await balance(debutMars, finMars);

      // Ouverture : 103 000 + 40 000 = 143 000 au débit ; 100 000 + 40 000 + 3 000 au crédit.
      // Mouvements : 15 000 + 10 000,40 + 10 000,15 + 3 000 + 2 500 = 40 500,55 au débit ;
      //              4 000,15 + 2 500 + 18 000 + 3 000 + 13 000,40 = 40 500,55 au crédit.
      // Final : 6 000,25 + 95 000,15 + 42 500 = 143 500,40 ; 100 000 + 25 000 + 2 500 + 16 000,40.
      expect(totaux(b), [
        143000,
        143000,
        40500.55,
        40500.55,
        143500.40,
        143500.40,
      ]);
      expect(b.ecart, 0);
      expect(b.equilibree, isTrue);
      expect(b.connue, isTrue);
    });

    test(
      '⚠️⚠️ « Total Débits (Soldes Finaux) » est un total de SOLDES, jamais de mouvements',
      () async {
        await jeu();
        final b = await balance(debutMars, finMars);

        expect(b.totalFinalDebit, 143500.40);
        expect(b.totalFinalDebit, isNot(b.totalMouvementsDebit));
      },
    );
  });

  group('défaut 1 : les bornes de la période', () {
    test(
      '⚠️⚠️ le JOUR du début est dans la période, pas dans l ouverture',
      () async {
        await jeu();
        // Période réduite au seul 1er mars : seule e04 (2 000) est dans la période.
        final b = await balance(DateTime(2026, 3, 1), DateTime(2026, 3, 1));
        final caisse = b.lignes.firstWhere((l) => l.code == '531');

        expect(caisse.ouvertureDebit, 103000);
        expect(caisse.mouvementsDebit, 2000);
      },
    );

    test('⚠️⚠️ la VEILLE du début est dans l ouverture', () async {
      await jeu();
      final b = await balance(DateTime(2026, 2, 28), DateTime(2026, 2, 28));
      final ventes = b.lignes.firstWhere((l) => l.code == '701');

      // Seule e03 (28 février) est dans la période ; rien avant pour 701.
      expect(six(ventes), [0, 0, 0, 3000, 0, 3000]);
    });

    test('⚠️⚠️ le JOUR de fin est inclus, le lendemain ignoré partout', () async {
      await jeu();
      final b = await balance(DateTime(2026, 3, 31), DateTime(2026, 3, 31));
      final ventes = b.lignes.firstWhere((l) => l.code == '701');

      // e08 (31 mars) dans la période ; e09 (1er avril) ni dans la période ni dans l'ouverture.
      expect(ventes.mouvementsCredit, 1000);
      expect(ventes.ouvertureCredit, 3000 + 2000 + 10000.40);
    });

    test('les heures n entrent jamais en jeu (jours calendaires)', () async {
      await jeu();
      final b = await balance(
        DateTime(2026, 3, 1, 23, 59),
        DateTime(2026, 3, 31, 0, 1),
      );

      expect(b.totalMouvementsDebit, 40500.55);
    });
  });

  group('défaut 1 : les deux périodes du sélecteur', () {
    test(
      '⚠️⚠️ « mois » : du 1er au DERNIER jour du mois (pas à aujourd hui)',
      () {
        final b = DonneesComptabilite.bornesBalance(PeriodeBalance.mois, EtatExercice(exercices: const [], memorise: null, aujourdhui: DateTime(2026, 3, 15, 10)));

        expect(b.debut, DateTime(2026, 3, 1));
        expect(b.fin, DateTime(2026, 3, 31));
      },
    );

    test('« mois » de février d une année bissextile', () {
      final b = DonneesComptabilite.bornesBalance(PeriodeBalance.mois, EtatExercice(exercices: const [], memorise: null, aujourdhui: DateTime(2028, 2, 3)));

      expect(b.fin, DateTime(2028, 2, 29));
    });

    test('⚠️⚠️ « exercice » : les dates de l exercice OUVERT', () async {
      await exercice(
        annee: 2025,
        debut: DateTime(2025, 1, 1),
        fin: DateTime(2025, 12, 31),
        statut: 'cloture',
      );
      await exercice(
        annee: 2026,
        debut: DateTime(2025, 7, 1),
        fin: DateTime(2026, 6, 30),
      );
      final d = await depot.charger();
      final b = DonneesComptabilite.bornesBalance(PeriodeBalance.exercice, EtatExercice(exercices: d.exercices, memorise: null, aujourdhui: DateTime(2026, 3, 15)));

      expect(b.debut, DateTime(2025, 7, 1));
      expect(b.fin, DateTime(2026, 6, 30));
      expect(
        DonneesComptabilite.libellePeriodeBalance(PeriodeBalance.exercice, EtatExercice(exercices: d.exercices, memorise: null, aujourdhui: DateTime(2026, 3, 15))),
        'Exercice 2026',
      );
    });

    test(
      '« exercice » sans exercice ouvert : l année civile (comme le serveur)',
      () {
        final b = DonneesComptabilite.bornesBalance(PeriodeBalance.exercice, EtatExercice(exercices: const [], memorise: null, aujourdhui: DateTime(2026, 3, 15)));

        expect(b.debut, DateTime(2026, 1, 1));
        expect(b.fin, DateTime(2026, 12, 31));
        expect(
          DonneesComptabilite.libellePeriodeBalance(PeriodeBalance.exercice, EtatExercice(exercices: const [], memorise: null, aujourdhui: DateTime(2026, 3, 15))),
          'Exercice 2026',
        );
      },
    );

    test('le libellé du mois : « Mars 2026 (période courante) »', () {
      expect(
        DonneesComptabilite.libellePeriodeBalance(PeriodeBalance.mois, EtatExercice(exercices: const [], memorise: null, aujourdhui: DateTime(2026, 3, 15))),
        'Mars 2026 (période courante)',
      );
      expect(
        DonneesComptabilite.libellePeriodeBalance(PeriodeBalance.mois, EtatExercice(exercices: const [], memorise: null, aujourdhui: DateTime(2026, 8, 2))),
        'Août 2026 (période courante)',
      );
    });

    test(
      '⚠️⚠️ exercice 2026 entier : tout est mouvement, rien n est ouverture',
      () async {
        await jeu();
        final b = await balance(DateTime(2026, 1, 1), DateTime(2026, 12, 31));
        final parCode = {for (final l in b.lignes) l.code: six(l)};

        // 521 : 8 000 au débit et au crédit DANS la période : listé, final nul.
        expect(parCode['521'], [0, 0, 8000, 8000, 0, 0]);
        // 681 / 281 : e10 (2 avril) est dans l'exercice.
        expect(parCode['681'], [0, 0, 600, 0, 600, 0]);
        expect(parCode['281'], [0, 0, 0, 600, 0, 600]);
        // 531 : débit 100 000 + 3 000 + 2 000 + 4 000,15 + 1 000 + 7 000 + 8 000 + 3 000 = 128 000,15 ;
        // crédit 15 000 + 8 000 + 3 000 = 26 000 ; final 102 000,15.
        expect(parCode['531'], [0, 0, 128000.15, 26000, 102000.15, 0]);
        // Somme de tous les montants du jeu, de chaque côté : 207 100,55.
        // Finals débiteurs : 411 6 000,25 + 531 102 000,15 + 601 42 500 + 681 600 = 151 100,40 ;
        // créditeurs : 101 100 000 + 401 25 000 + 5212 2 500 + 281 600 + 701 23 000,40 = 151 100,40.
        expect(totaux(b), [0, 0, 207100.55, 207100.55, 151100.40, 151100.40]);
        expect(b.lignes.map((l) => l.code), [
          '101',
          '281',
          '401',
          '411',
          '521',
          '5212',
          '531',
          '585',
          '601',
          '681',
          '701',
        ]);
      },
    );
  });

  group('recomputation indépendante', () {
    void comparer(BalanceGenerale b, DateTime debut, DateTime fin) {
      final r = recalcul(debut, fin);
      expect(
        b.lignes.map((l) => l.code).toList(),
        r.lignes.map((l) => l.$1).toList(),
      );
      for (var i = 0; i < r.lignes.length; i++) {
        expect(
          enCentimes(six(b.lignes[i])),
          r.lignes[i].$2,
          reason: r.lignes[i].$1,
        );
      }
      expect(enCentimes(totaux(b)), r.totaux);
      expect((b.ecart * 100).round(), r.totaux[4] - r.totaux[5]);
    }

    test('⚠️⚠️ le jeu écrit à la main, sur cinq périodes', () async {
      await jeu();
      final d = await depot.charger();
      for (final (debut, fin) in [
        (debutMars, finMars),
        (DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
        (DateTime(2026, 2, 1), DateTime(2026, 2, 28)),
        (DateTime(2026, 4, 1), DateTime(2026, 4, 30)),
        (DateTime(2027, 1, 1), DateTime(2027, 1, 31)),
      ]) {
        comparer(d.balanceGenerale(debut: debut, fin: fin), debut, fin);
      }
    });

    test(
      '⚠️⚠️ un jeu pseudo-aléatoire de 120 écritures (graine fixe)',
      () async {
        final codes = [
          '101',
          '401',
          '411',
          '521',
          '5212',
          '531',
          '585',
          '601',
          '701',
          '28',
        ];
        for (final c in codes) {
          await compte(c, 'Compte $c', int.parse(c[0]));
        }
        final alea = Random(20261012);
        for (var n = 0; n < 120; n++) {
          final jour = DateTime(
            2025,
            11,
            1,
          ).add(Duration(days: alea.nextInt(240)));
          final cle = 'r${n.toString().padLeft(3, '0')}';
          await db
              .into(db.accountingEntries)
              .insert(
                AccountingEntriesCompanion.insert(
                  id: uuid(cle),
                  entryDate: jour,
                ),
              );
          // 2 ou 3 lignes, équilibrées au centime.
          final montant = alea.nextInt(5000000) + 1;
          final a = codes[alea.nextInt(codes.length)];
          final b = codes[alea.nextInt(codes.length)];
          if (alea.nextBool()) {
            await ligne('${cle}a', cle, jour, a, debit: montant / 100);
            await ligne('${cle}b', cle, jour, b, credit: montant / 100);
          } else {
            final part = alea.nextInt(montant);
            final c = codes[alea.nextInt(codes.length)];
            await ligne('${cle}a', cle, jour, a, debit: montant / 100);
            await ligne('${cle}b', cle, jour, b, credit: part / 100);
            await ligne(
              '${cle}c',
              cle,
              jour,
              c,
              credit: (montant - part) / 100,
            );
          }
        }
        final d = await depot.charger();
        expect(d.ecrituresIncompletes, 0);
        for (final (debut, fin) in [
          (DateTime(2026, 3, 1), DateTime(2026, 3, 31)),
          (DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
          (DateTime(2025, 12, 1), DateTime(2025, 12, 31)),
          (DateTime(2026, 2, 14), DateTime(2026, 2, 14)),
        ]) {
          comparer(d.balanceGenerale(debut: debut, fin: fin), debut, fin);
        }
      },
    );
  });

  group('« — » et non 0 quand le poste ne sait pas', () {
    test('⚠️⚠️ journal vide : la balance est INCONNUE, pas nulle', () async {
      await compte('531', 'Caisse', 5);
      final b = await balance(debutMars, finMars);

      expect(b.journalVide, isTrue);
      expect(b.connue, isFalse);
      expect(b.lignes, isEmpty);
    });

    test(
      '⚠️⚠️ journal incomplet (écriture déséquilibrée) : la balance n est pas affirmée',
      () async {
        await jeu();
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: uuid('boiteuse'),
                entryDate: DateTime(2025, 6, 1),
              ),
            );
        await ligne(
          'bl1',
          'boiteuse',
          DateTime(2025, 6, 1),
          '531',
          debit: 9000,
        );
        final b = await balance(debutMars, finMars);

        expect(b.journalIncomplet, isTrue);
        expect(b.connue, isFalse);
      },
    );

    test(
      'un journal non vide sans rien dans la période : connue, vide, totaux à 0',
      () async {
        await jeu();
        final b = await balance(DateTime(2025, 1, 1), DateTime(2025, 1, 31));

        expect(b.connue, isTrue);
        expect(b.lignes, isEmpty);
        expect(totaux(b), [0, 0, 0, 0, 0, 0]);
      },
    );

    test(
      '⚠️⚠️ une ligne sur un compte ABSENT du plan reçu reste dans la balance (code « — »)',
      () async {
        await jeu();
        // Compte archivé côté serveur : le plan ne descend que les comptes actifs, mais le serveur
        // garde ses lignes dans la balance (jointure sans filtre d'activité).
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: uuid('orph'),
                entryDate: DateTime(2026, 3, 5),
              ),
            );
        await ligne('o1', 'orph', DateTime(2026, 3, 5), '531', debit: 700);
        await ligne('o2', 'orph', DateTime(2026, 3, 5), '999', credit: 700);
        final b = await balance(debutMars, finMars);

        final orpheline = b.lignes.last;
        expect(orpheline.compte, isNull);
        expect(orpheline.code, '—');
        expect(six(orpheline), [0, 0, 0, 700, 0, 700]);
        // Les totaux restent équilibrés : la ligne n'est pas perdue en route.
        expect(b.equilibree, isTrue);
        expect(b.totalFinalCredit, 143500.40 + 700);
      },
    );

    test('⚠️⚠️ l écart se mesure au centime : 0,01 = déséquilibre', () async {
      await compte('531', 'Caisse', 5);
      await compte('701', 'Ventes', 7);
      // Deux écritures écartées chacune de 0,006 (sous le seuil « incomplète » de 0,01) : la caisse
      // cumule 200,012 → 200,01 au centime ; les ventes 200,00. Écart 0,01 : NON équilibrée (le
      // serveur exige |écart| < 0,01 ; la maquette tolérait < 1, Laravel fait foi).
      for (final cle in ['x1', 'x2']) {
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: uuid(cle),
                entryDate: DateTime(2026, 3, 5),
              ),
            );
        await ligne(
          '${cle}d',
          cle,
          DateTime(2026, 3, 5),
          '531',
          debit: 100.006,
        );
        await ligne('${cle}c', cle, DateTime(2026, 3, 5), '701', credit: 100);
      }
      final b = await balance(debutMars, finMars);

      expect(b.connue, isTrue);
      expect(b.ecart, 0.01);
      expect(b.equilibree, isFalse);
    });
  });

  test(
    '⚠️⚠️ l écart porte sur les SOLDES FINAUX : un déséquilibre d ouverture le fait voir',
    () async {
      await compte('531', 'Caisse', 5);
      await compte('701', 'Ventes', 7);
      // Février : deux écritures écartées de 0,006 chacune (non « incomplètes ») → ouverture de mars
      // 531 = 200,012 → 200,01 débit ; 701 = 200 crédit. Mars : une écriture ÉQUILIBRÉE de 50.
      // Mouvements de la période équilibrés (50 / 50), finals 250,01 / 250 : écart 0,01.
      // (Mutation M13 du ticket F0.86 : un écart calculé sur les mouvements y voyait 0.)
      for (final cle in ['f1', 'f2']) {
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: uuid(cle),
                entryDate: DateTime(2026, 2, 10),
              ),
            );
        await ligne(
          '${cle}d',
          cle,
          DateTime(2026, 2, 10),
          '531',
          debit: 100.006,
        );
        await ligne('${cle}c', cle, DateTime(2026, 2, 10), '701', credit: 100);
      }
      await ecriture('m1', DateTime(2026, 3, 5), '531', '701', 50);
      final b = await balance(debutMars, finMars);

      expect(b.totalMouvementsDebit, b.totalMouvementsCredit);
      expect(totaux(b), [200.01, 200, 50, 50, 250.01, 250]);
      expect(b.ecart, 0.01);
      expect(b.equilibree, isFalse);
    },
  );

  // ═══════════════════════════════════════════════════════════════════════════════════════════

  group('écran', () {
    final mars15 = DateTime(2026, 3, 15);

    Future<void> afficher(WidgetTester tester, {DateTime? maintenant}) async {
      tester.view.physicalSize = const Size(1700, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ComptabiliteScreen(
            depot: depot,
            maintenant: () => maintenant ?? mars15,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('carte-balance')));
      await tester.pumpAndSettle();
    }

    Finder dans(String cle, String texte) =>
        find.descendant(of: find.byKey(Key(cle)), matching: find.text(texte));

    String texteDe(String cle) =>
        (find.byKey(Key(cle)).evaluate().single.widget as Text).data!;

    Future<void> choisir(WidgetTester tester, String option) async {
      await tester.tap(find.byKey(const Key('balance-periode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    testWidgets(
      '⚠️⚠️ ouvre sur le MOIS courant, trois cartes, totaux et écart à 0',
      (tester) async {
        await jeu();
        await afficher(tester);

        expect(find.text('Mars 2026 (période courante)'), findsOneWidget);
        expect(find.byType(CarteKpi), findsNWidgets(3));
        expect(dans('kpi-balance-debits', '143 500'), findsOneWidget);
        expect(dans('kpi-balance-credits', '143 500'), findsOneWidget);
        expect(dans('kpi-balance-ecart', '0'), findsOneWidget);
        expect(find.byKey(const Key('bal-alerte-desequilibre')), findsNothing);
      },
    );

    testWidgets(
      '⚠️⚠️ les cellules : « — » pour un zéro, montants arrondis au franc',
      (tester) async {
        await jeu();
        await afficher(tester);

        // Ligne 4 = 531 (ordre : 101, 401, 411, 5212, 531…).
        expect(texteDe('bal-4-code'), '531');
        expect(
          [for (var c = 0; c < 6; c++) texteDe('bal-4-$c')],
          ['103 000', '—', '10 000', '18 000', '95 000', '—'],
        );
        // 585 : final nul des deux côtés → deux tirets, jamais « 0 ».
        expect(texteDe('bal-5-code'), '585');
        expect(
          [for (var c = 0; c < 6; c++) texteDe('bal-5-$c')],
          ['—', '—', '3 000', '3 000', '—', '—'],
        );
      },
    );

    testWidgets(
      '⚠️⚠️ l écran égale la recomputation indépendante (mois puis exercice)',
      (tester) async {
        await jeu();
        await afficher(tester);

        void verifier(DateTime debut, DateTime fin) {
          final r = recalcul(debut, fin);
          for (var i = 0; i < r.lignes.length; i++) {
            expect(texteDe('bal-$i-code'), r.lignes[i].$1);
            for (var c = 0; c < 6; c++) {
              final v = r.lignes[i].$2[c];
              expect(
                texteDe('bal-$i-$c'),
                v > 0 ? formatCts(v) : '—',
                reason: '${r.lignes[i].$1} colonne $c',
              );
            }
          }
          expect(find.byKey(Key('bal-${r.lignes.length}-code')), findsNothing);
          for (var c = 0; c < 6; c++) {
            expect(texteDe('bal-total-$c'), formatCts(r.totaux[c]));
          }
          expect(
            dans('kpi-balance-debits', formatCts(r.totaux[4])),
            findsOneWidget,
          );
          expect(
            dans('kpi-balance-credits', formatCts(r.totaux[5])),
            findsOneWidget,
          );
          expect(
            dans(
              'kpi-balance-ecart',
              formatEcartCts(r.totaux[4] - r.totaux[5]),
            ),
            findsOneWidget,
          );
        }

        verifier(debutMars, finMars);
        await choisir(tester, 'Exercice 2026');
        verifier(DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      },
    );

    testWidgets(
      '⚠️⚠️ journal vide : cartes « — » avec leur raison, jamais « 0 »',
      (tester) async {
        await compte('531', 'Caisse', 5);
        await afficher(tester);

        for (final cle in [
          'kpi-balance-debits',
          'kpi-balance-credits',
          'kpi-balance-ecart',
        ]) {
          expect(dans(cle, '—'), findsOneWidget, reason: cle);
          expect(dans(cle, '0'), findsNothing, reason: cle);
          expect(
            dans(cle, 'Aucune écriture reçue au poste'),
            findsOneWidget,
            reason: cle,
          );
        }
        expect(
          find.text('Aucun compte mouvementé sur cette période.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('bal-total-0')), findsNothing);
      },
    );

    testWidgets(
      '⚠️⚠️ journal incomplet : ouverture, final, cartes et écart en « — », pas de bandeau',
      (tester) async {
        await jeu();
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: uuid('boiteuse'),
                entryDate: DateTime(2025, 6, 1),
              ),
            );
        await ligne(
          'bl1',
          'boiteuse',
          DateTime(2025, 6, 1),
          '531',
          debit: 9000,
        );
        await afficher(tester);

        expect(dans('kpi-balance-ecart', '—'), findsOneWidget);
        expect(dans('kpi-balance-debits', '—'), findsOneWidget);
        expect(find.byKey(const Key('bal-alerte-desequilibre')), findsNothing);
        expect(find.textContaining('Journal incomplet'), findsWidgets);
        // 531 : ouverture et final inconnus ; les mouvements de la période, eux, sont montrés.
        expect(texteDe('bal-4-code'), '531');
        expect(
          [for (var c = 0; c < 6; c++) texteDe('bal-4-$c')],
          ['—', '—', '10 000', '18 000', '—', '—'],
        );
        expect(texteDe('bal-total-0'), '—');
        expect(texteDe('bal-total-2'), '40 501');
      },
    );

    testWidgets('⚠️⚠️ déséquilibre de 0,01 : écart rouge et bandeau de la maquette', (
      tester,
    ) async {
      await compte('531', 'Caisse', 5);
      await compte('701', 'Ventes', 7);
      for (final cle in ['x1', 'x2']) {
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: uuid(cle),
                entryDate: DateTime(2026, 3, 5),
              ),
            );
        await ligne(
          '${cle}d',
          cle,
          DateTime(2026, 3, 5),
          '531',
          debit: 100.006,
        );
        await ligne('${cle}c', cle, DateTime(2026, 3, 5), '701', credit: 100);
      }
      await afficher(tester);

      expect(find.byKey(const Key('bal-alerte-desequilibre')), findsOneWidget);
      expect(find.text('Balance Déséquilibrée'), findsOneWidget);
      expect(
        find.text(
          "Une anomalie de saisie doit être corrigée avant toute clôture (périodique ou annuelle) de l'exercice.",
        ),
        findsOneWidget,
      );
      // `text-error-deep` sur la valeur, carte rouge (`border-error-red/30`) : liseré rouge.
      final carte = tester.widget<CarteKpi>(
        find.byKey(const Key('kpi-balance-ecart')),
      );
      expect(carte.couleurValeur, AgriColors.errorDeep);
      expect(carte.couleurLisere, AgriColors.errorRed);
      // F0.88 (arbitrage client du 13/10/2026) : l'écart non nul s'écrit AVEC ses centimes. Le web
      // écrirait « 0 » (`number_format(0.01, 0)`) en rouge : écart ASSUMÉ, le « 0 » rouge trompait.
      expect(dans('kpi-balance-ecart', '0,01'), findsOneWidget);
      expect(dans('kpi-balance-ecart', '0'), findsNothing);
    });

    // ── Ticket F0.86-bis : un écart NÉGATIF qui s'arrondit à zéro s'écrit « 0 », jamais « -0 » ─────
    //
    // `number_format(-0.4, 0, ',', ' ')` (PHP 8.3.30, mesuré) rend « 0 » ; `-0.5` et `-0.6` rendent
    // « -1 ». Le `_montant` du poste testait le signe sur la valeur BRUTE (`valeur < 0`) et non sur
    // la valeur ARRONDIE : -0,4 sortait « -0 ».

    /// [n] écritures « 531 au débit 100 / 701 au crédit 100,009 » : chacune n'est déséquilibrée que de
    /// 0,009 (< 0,01, donc PAS « incomplète »), le cumul fait l'écart. Clés 101..(100+n) : jamais
    /// deux graines dont l'une est le préfixe de l'autre (`uuid` complète par des « 0 »).
    Future<void> ecartNegatif(int n) async {
      await compte('531', 'Caisse', 5);
      await compte('701', 'Ventes', 7);
      for (var i = 101; i <= 100 + n; i++) {
        final cle = 'x$i';
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: uuid(cle),
                entryDate: DateTime(2026, 3, 5),
              ),
            );
        await ligne('${cle}d', cle, DateTime(2026, 3, 5), '531', debit: 100);
        await ligne(
          '${cle}c',
          cle,
          DateTime(2026, 3, 5),
          '701',
          credit: 100.009,
        );
      }
    }

    testWidgets(
      '⚠️⚠️ F0.86-bis / F0.88 : écart de -0,4 → « -0,40 » ou « -0,41 » (jamais « 0 » ni « -0 »), rouge, bandeau',
      (tester) async {
        // 45 × 0,009 = 0,405 : crédits 4 500,40 ou 4 500,41 au centime (demi-centime, selon le
        // flottant), débits 4 500 → écart -0,40 ou -0,41. Avant F0.88 : « 0 » (parité web).
        // Arbitrage client du 13/10/2026 : les centimes d'un écart non nul sont affichés.
        await ecartNegatif(45);
        await afficher(tester);

        final b = (await tester.runAsync(() => balance(debutMars, finMars)))!;
        expect(b.connue, isTrue, reason: 'journal NI vide NI incomplet');
        expect(b.ecart, lessThan(-0.39));
        expect(b.ecart, greaterThan(-0.42));

        final affiche = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(const Key('kpi-balance-ecart')),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data)
            .where((t) => t == '-0,40' || t == '-0,41');
        expect(affiche, hasLength(1));
        expect(affiche.single, formatEcartCts((b.ecart * 100).round()));
        expect(dans('kpi-balance-ecart', '0'), findsNothing);
        expect(dans('kpi-balance-ecart', '-0'), findsNothing);
        expect(find.text('-0'), findsNothing);
        // Les autres montants gardent l'arrondi au franc : « 4 500 » des deux côtés.
        expect(dans('kpi-balance-debits', '4 500'), findsOneWidget);
        expect(dans('kpi-balance-credits', '4 500'), findsOneWidget);
        // ⚠️ SEUIL INCHANGÉ (Laravel, |écart| < 0,01) : déséquilibre = rouge + bandeau.
        final carte = tester.widget<CarteKpi>(
          find.byKey(const Key('kpi-balance-ecart')),
        );
        expect(carte.couleurValeur, AgriColors.errorDeep);
        expect(
          find.byKey(const Key('bal-alerte-desequilibre')),
          findsOneWidget,
        );
      },
    );

    testWidgets('⚠️ F0.86-bis / F0.88 : écart de -0,6 → « -0,60 » (le signe reste)', (
      tester,
    ) async {
      // 67 × 0,009 = 0,603 : crédits 6 700,60 au centime, débits 6 700 → écart -0,60. Avant F0.88 :
      // « -1 » (arrondi au franc du web) ; depuis l'arbitrage client : « -0,60 ».
      await ecartNegatif(67);
      await afficher(tester);

      expect(dans('kpi-balance-ecart', '-0,60'), findsOneWidget);
      expect(dans('kpi-balance-ecart', '-1'), findsNothing);
      expect(dans('kpi-balance-debits', '6 700'), findsOneWidget);
      expect(dans('kpi-balance-credits', '6 701'), findsOneWidget);
      // Recomputation indépendante en ENTIERS (millièmes de franc) : 67 × 100 009 = 6 700 603
      // millièmes → 670 060 centimes au crédit ; 670 000 au débit → écart -60 centimes.
      // (`recalcul` arrondit chaque LIGNE au centime et ne modélise pas ce cas sous le centime.)
      const creditCts = (67 * 100009 + 5) ~/ 10;
      expect(creditCts, 670060);
      expect(formatEcartCts(670000 - creditCts), '-0,60');
    });

    testWidgets(
      '⚠️⚠️ F0.88 : écart de -0,40 exact (44 écritures) → « -0,40 », bandeau ; seuil 0,01 inchangé',
      (tester) async {
        // 44 × 0,009 = 0,396 : 44 × 100 009 = 4 400 396 millièmes → 440 040 centimes au crédit,
        // 440 000 au débit → écart -40 centimes (aucun demi-centime en jeu).
        await ecartNegatif(44);
        await afficher(tester);

        expect((44 * 100009 + 5) ~/ 10, 440040);
        expect(dans('kpi-balance-ecart', formatEcartCts(-40)), findsOneWidget);
        expect(formatEcartCts(-40), '-0,40');
        expect(
          find.byKey(const Key('bal-alerte-desequilibre')),
          findsOneWidget,
        );
        expect(dans('kpi-balance-debits', '4 400'), findsOneWidget);
        expect(dans('kpi-balance-credits', '4 400'), findsOneWidget);
      },
    );

    testWidgets(
      'F0.88 : un écart NUL reste « 0 » (pas « 0,00 »), vert, sans bandeau',
      (tester) async {
        await jeu();
        await afficher(tester);

        expect(dans('kpi-balance-ecart', '0'), findsOneWidget);
        expect(dans('kpi-balance-ecart', '0,00'), findsNothing);
        expect(dans('kpi-balance-ecart', '-0,00'), findsNothing);
        expect(find.byKey(const Key('bal-alerte-desequilibre')), findsNothing);
      },
    );

    testWidgets('la couleur de l écart suit l équilibre (vert)', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);
      final equilibree = tester.widget<CarteKpi>(
        find.byKey(const Key('kpi-balance-ecart')),
      );
      expect(equilibree.couleurValeur, AgriColors.brandEmerald);
      expect(equilibree.couleurLisere, AgriColors.brandEmerald);
    });

    testWidgets(
      '⚠️⚠️ changer de période recalcule (exercice puis retour au mois)',
      (tester) async {
        await jeu();
        await afficher(tester);
        expect(texteDe('bal-total-2'), '40 501');

        await choisir(tester, 'Exercice 2026');
        expect(texteDe('bal-total-2'), '207 101');
        expect(texteDe('bal-total-0'), '0');

        await choisir(tester, 'Mars 2026 (période courante)');
        expect(texteDe('bal-total-2'), '40 501');
      },
    );

    testWidgets(
      '⚠️ le mois courant va jusqu au DERNIER jour, pas à aujourd hui',
      (tester) async {
        await jeu();
        // Le 15 mars : e08 (31 mars) est quand même dans « Mars 2026 ».
        await afficher(tester, maintenant: DateTime(2026, 3, 15));
        expect(texteDe('bal-7-code'), '701');
        expect(texteDe('bal-7-3'), '13 000');
      },
    );

    testWidgets('l ancienne mention « exercice précédent » a disparu', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);
      expect(
        find.textContaining("supposent l'exercice précédent"),
        findsNothing,
      );
    });

    // ── Fidélité à la maquette ET à la page web (lues dans les dépôts, jamais copiées) ───────────

    final maquette = File(
      '$dossierPrototype/balance-generale.html',
    );
    final vueWeb = File(
      '$dossierLaravel/resources/views/livewire/comptabilite/balance-generale.blade.php',
    );
    final sautMaquette = maquette.existsSync() && vueWeb.existsSync()
        ? null
        : 'SAUT : maquette ou vue web absente';

    List<String> trouver(String source, RegExp motif) => [
      for (final m in motif.allMatches(source)) m.group(1)!.trim(),
    ];

    testWidgets(
      '⚠️⚠️ les trois cartes : libellés de la maquette ET de la page web, dans l ordre',
      (tester) async {
        final motif = RegExp(
          r'<span class="text-\[10px\] text-outline font-bold uppercase block">([^<]+)</span>',
        );
        final cartesMaquette = trouver(maquette.readAsStringSync(), motif);
        final cartesWeb = trouver(vueWeb.readAsStringSync(), motif);
        expect(cartesMaquette, [
          'Total Débits (Soldes Finaux)',
          'Total Crédits (Soldes Finaux)',
          'Écart (doit être 0)',
        ]);
        expect(cartesWeb, cartesMaquette);

        await jeu();
        await afficher(tester);
        final rendues = tester
            .widgetList<CarteKpi>(find.byType(CarteKpi))
            .map((c) => c.libelle)
            .toList();
        expect(rendues, cartesMaquette);
      },
      skip: sautMaquette != null,
    );

    testWidgets(
      'sous-titre, « Période : », bandeau et état vide : le texte de la maquette / page web',
      (tester) async {
        final source = maquette.readAsStringSync();
        const sousTitre =
            "Synthèse des soldes de tous les comptes utilisés — vérification de l'équilibre avant clôture.";
        expect(source, contains(sousTitre));
        expect(source, contains('Période :'));
        expect(
          vueWeb.readAsStringSync(),
          contains('Aucun compte mouvementé sur cette période.'),
        );

        await jeu();
        await afficher(tester);
        expect(find.text(sousTitre), findsOneWidget);
        expect(find.text('Période :'), findsOneWidget);
      },
      skip: sautMaquette != null,
    );

    testWidgets('la ligne TOTAUX de la maquette', (tester) async {
      await jeu();
      await afficher(tester);
      expect(find.text('TOTAUX'), findsOneWidget);
      expect(
        [for (var c = 0; c < 6; c++) texteDe('bal-total-$c')],
        ['143 000', '143 000', '40 501', '40 501', '143 500', '143 500'],
      );
    });

    // Jusqu'au ticket F0.87, ce test verrouillait l'absence du bouton (T4 hors du ticket F0.86).
    testWidgets('« Exporter PDF » est porté (ticket F0.87)', (tester) async {
      await jeu();
      await afficher(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('exporter-pdf-balance')),
          matching: find.text('Exporter PDF'),
        ),
        findsOneWidget,
      );
    });
  });
}
