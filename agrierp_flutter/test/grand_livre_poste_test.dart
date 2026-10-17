import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:agrierp/features/comptabilite/nature_compte.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'chemins_depot.dart';

/// Ticket F0.85 — GRAND LIVRE DU POSTE (item 9, ticket T2 ; serveur : 15.29).
///
/// Le serveur Laravel fait foi (`FinancialReportService::grandLivre`) ; le poste le REPRODUIT en
/// local. Avant ce ticket, le Grand Livre du poste :
///  1. cumulait TOUJOURS `débit − crédit`, faux pour tout compte créditeur (401, 701, 419, 101…) ;
///  2. n'avait ni période, ni solde d'ouverture, ni recherche, ni compte par défaut 531 ;
///  3. triait par date seule : deux pièces du même jour pouvaient s'inverser ;
///  4. montrait le type de source sous « N° Pièce » et la référence entière sous « Libellé ».
///
/// ⚠️⚠️ Les chiffres ci-dessous sont des LITTÉRAUX calculés À LA MAIN sur un jeu d'écritures écrit à la
/// main (voir `jeu`), jamais obtenus en appelant le code testé. Le détail du calcul est donné en
/// commentaire, ligne à ligne.
void main() {
  late AppDatabase db;
  late ComptabiliteRepository depot;

  String uuid(String graine) => graine.padRight(36, '0').substring(0, 36);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    depot = ComptabiliteRepository(database: db);
  });

  tearDown(() async => db.close());

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

  /// Une écriture à DEUX lignes : [debit] au débit, [credit] au crédit, même [montant].
  Future<void> ecriture(
    String cle, {
    required DateTime date,
    required String? reference,
    required String debit,
    required String credit,
    required double montant,
    DateTime? creeLe,
  }) async {
    await db
        .into(db.accountingEntries)
        .insert(
          AccountingEntriesCompanion.insert(
            id: uuid(cle),
            entryDate: date,
            reference: Value(reference),
            createdAt: Value(creeLe),
          ),
        );
    await db
        .into(db.accountingEntryLines)
        .insert(
          AccountingEntryLinesCompanion.insert(
            id: uuid('${cle}d'),
            entryId: uuid(cle),
            accountId: uuid('c$debit'),
            debit: Value(montant),
          ),
        );
    await db
        .into(db.accountingEntryLines)
        .insert(
          AccountingEntryLinesCompanion.insert(
            id: uuid('${cle}c'),
            entryId: uuid(cle),
            accountId: uuid('c$credit'),
            credit: Value(montant),
          ),
        );
  }

  /// Le jeu d'écritures, ÉCRIT À LA MAIN. Insérées volontairement à l'envers de l'ordre de création
  /// pour les trois pièces du 2 mars : l'ordre d'insertion ne doit jamais décider.
  ///
  /// | clé | date       | créée le (2 mars)  | référence                          | débit | crédit | montant |
  /// | e01 | 2026-01-10 |                    | OD-2026-0001 — Capital initial     | 531   | 101    | 100 000 |
  /// | e02 | 2026-02-15 |                    | OD-2026-0002 — Achat aliment       | 601   | 401    |  40 000 |
  /// | e03 | 2026-02-28 |                    | OD-2026-0009 — Vente veille        | 531   | 701    |   3 000 |
  /// | e04 | 2026-03-01 |                    | OD-2026-0006 — Vente début de mois | 531   | 701    |   2 000 |
  /// | e05 | 2026-03-02 | 10:00:01           | OD-2026-0004 — Règlement fournisseur | 401 | 531    |  15 000 |
  /// | e06 | 2026-03-02 | 10:00:05           | OD-2026-0003 — Vente comptant      | 531   | 701    |  25 000 |
  /// | e07 | 2026-03-02 | 10:00:05 (= e06)   | OD-2026-0007 — Frais divers        | 601   | 531    |     500 |
  /// | e08 | 2026-03-10 |                    | OD-2026-0008 — TVA                 | 4456  | 4457   |   1 800 |
  /// | e09 | 2026-03-12 |                    | OD-2026-0010 — Dotation            | 681   | 281    |     600 |
  /// | e10 | 2026-03-20 |                    | OD-2026-0005 — Avance fournisseur  | 409   | 531    |   5 000 |
  /// | e11 | 2026-03-31 |                    | OD-2026-0011 — Vente fin de mois   | 531   | 701    |   1 000 |
  /// | e12 | 2026-04-01 |                    | OD-2026-0012 — Vente après période | 531  | 701    |   7 000 |
  Future<void> jeu() async {
    for (final (code, libelle, classe) in [
      ('531', 'Caisse', 5),
      ('101', 'Capital', 1),
      ('601', 'Achats', 6),
      ('401', 'Fournisseurs', 4),
      ('701', 'Ventes', 7),
      ('4456', 'TVA récupérable', 4),
      ('4457', 'TVA collectée', 4),
      ('681', 'Dotations', 6),
      ('281', 'Amortissements', 2),
      ('409', 'Fournisseurs débiteurs', 4),
      ('411', 'Clients', 4),
    ]) {
      await compte(code, libelle, classe);
    }

    final deux = DateTime(2026, 3, 2);
    await ecriture(
      'e07',
      date: deux,
      reference: 'OD-2026-0007 — Frais divers',
      debit: '601',
      credit: '531',
      montant: 500,
      creeLe: DateTime(2026, 3, 2, 10, 0, 5),
    );
    await ecriture(
      'e06',
      date: deux,
      reference: 'OD-2026-0003 — Vente comptant',
      debit: '531',
      credit: '701',
      montant: 25000,
      creeLe: DateTime(2026, 3, 2, 10, 0, 5),
    );
    await ecriture(
      'e05',
      date: deux,
      reference: 'OD-2026-0004 — Règlement fournisseur',
      debit: '401',
      credit: '531',
      montant: 15000,
      creeLe: DateTime(2026, 3, 2, 10, 0, 1),
    );
    await ecriture(
      'e12',
      date: DateTime(2026, 4, 1),
      reference: 'OD-2026-0012 — Vente après période',
      debit: '531',
      credit: '701',
      montant: 7000,
    );
    await ecriture(
      'e11',
      date: DateTime(2026, 3, 31),
      reference: 'OD-2026-0011 — Vente fin de mois',
      debit: '531',
      credit: '701',
      montant: 1000,
    );
    await ecriture(
      'e10',
      date: DateTime(2026, 3, 20),
      reference: 'OD-2026-0005 — Avance fournisseur',
      debit: '409',
      credit: '531',
      montant: 5000,
    );
    await ecriture(
      'e09',
      date: DateTime(2026, 3, 12),
      reference: 'OD-2026-0010 — Dotation',
      debit: '681',
      credit: '281',
      montant: 600,
    );
    await ecriture(
      'e08',
      date: DateTime(2026, 3, 10),
      reference: 'OD-2026-0008 — TVA',
      debit: '4456',
      credit: '4457',
      montant: 1800,
    );
    await ecriture(
      'e04',
      date: DateTime(2026, 3, 1),
      reference: 'OD-2026-0006 — Vente début de mois',
      debit: '531',
      credit: '701',
      montant: 2000,
    );
    await ecriture(
      'e03',
      date: DateTime(2026, 2, 28),
      reference: 'OD-2026-0009 — Vente veille',
      debit: '531',
      credit: '701',
      montant: 3000,
    );
    await ecriture(
      'e02',
      date: DateTime(2026, 2, 15),
      reference: 'OD-2026-0002 — Achat aliment',
      debit: '601',
      credit: '401',
      montant: 40000,
    );
    await ecriture(
      'e01',
      date: DateTime(2026, 1, 10),
      reference: 'OD-2026-0001 — Capital initial',
      debit: '531',
      credit: '101',
      montant: 100000,
    );
  }

  final debutMars = DateTime(2026, 3, 1);
  final finMars = DateTime(2026, 3, 31);

  Future<GrandLivreCompte> livre(
    String code, {
    DateTime? debut,
    DateTime? fin,
    String recherche = '',
  }) async {
    final d = await depot.charger();
    return d.grandLivreCompte(
      uuid('c$code'),
      debut: debut,
      fin: fin,
      recherche: recherche,
    );
  }

  List<double> soldes(GrandLivreCompte g) =>
      g.mouvements.map((m) => m.soldeProgressif).toList();

  group('défaut 1 : le solde suit la NATURE du compte', () {
    test(
      '⚠️⚠️ 531 (débiteur) : ouverture 103 000, lignes dans l ordre du serveur',
      () async {
        await jeu();
        final g = await livre('531', debut: debutMars, fin: finMars);

        // Ouverture = e01 (100 000) + e03 (3 000), débit − crédit : 103 000.
        expect(g.estDebitrice, isTrue);
        expect(g.soldeOuverture, 103000);
        // 03-01 e04 +2 000 → 105 000 ; 03-02 e05 −15 000 → 90 000 ; e06 +25 000 → 115 000 ;
        // e07 −500 → 114 500 ; 03-20 e10 −5 000 → 109 500 ; 03-31 e11 +1 000 → 110 500.
        expect(soldes(g), [105000, 90000, 115000, 114500, 109500, 110500]);
        expect(g.mouvements.map((m) => m.piece), [
          'OD-2026-0006',
          'OD-2026-0004',
          'OD-2026-0003',
          'OD-2026-0007',
          'OD-2026-0005',
          'OD-2026-0011',
        ]);
        // Débits : 2 000 + 25 000 + 1 000. Crédits : 15 000 + 500 + 5 000.
        expect(g.totalDebit, 28000);
        expect(g.totalCredit, 20500);
        expect(g.soldeFinal, 110500);
        // Contrôle de cohérence indépendant : ouverture + débits − crédits = final.
        expect(103000 + 28000 - 20500, 110500);
      },
    );

    test('⚠️⚠️ 701 (créditeur) : le solde est crédit − débit', () async {
      await jeu();
      final g = await livre('701', debut: debutMars, fin: finMars);

      // Ouverture = e03 : crédit 3 000. Lignes : e04 +2 000 → 5 000 ; e06 +25 000 → 30 000 ;
      // e11 +1 000 → 31 000. (Ancien code : −2 000, −27 000, −28 000 : le signe inverse.)
      expect(g.estDebitrice, isFalse);
      expect(g.soldeOuverture, 3000);
      expect(soldes(g), [5000, 30000, 31000]);
      expect(g.totalDebit, 0);
      expect(g.totalCredit, 28000);
      expect(g.soldeFinal, 31000);
    });

    test('⚠️⚠️ 401 (créditeur) : dette de 40 000 réglée de 15 000', () async {
      await jeu();
      final g = await livre('401', debut: debutMars, fin: finMars);

      // Ouverture = e02 : crédit 40 000. Ligne : e05 débit 15 000 → 25 000.
      expect(g.soldeOuverture, 40000);
      expect(soldes(g), [25000]);
      expect(g.totalDebit, 15000);
      expect(g.totalCredit, 0);
      expect(g.soldeFinal, 25000);
    });

    test(
      '⚠️ 101 (créditeur) sans mouvement dans la période : ouverture = final',
      () async {
        await jeu();
        final g = await livre('101', debut: debutMars, fin: finMars);

        expect(g.estDebitrice, isFalse);
        expect(g.soldeOuverture, 100000);
        expect(g.mouvements, isEmpty);
        // Le compte a des écritures AILLEURS : les totaux de la période sont de vrais zéros.
        expect(g.sansEcriture, isFalse);
        expect(g.totalDebit, 0);
        expect(g.totalCredit, 0);
        expect(g.soldeFinal, 100000);
      },
    );

    test(
      '⚠️ natures particulières : 409, 4456 débiteurs ; 4457, 281 créditeurs',
      () async {
        await jeu();

        final f409 = await livre('409', debut: debutMars, fin: finMars);
        expect(f409.estDebitrice, isTrue);
        expect(f409.soldeOuverture, 0);
        expect(soldes(f409), [5000]);

        final f4456 = await livre('4456', debut: debutMars, fin: finMars);
        expect(f4456.estDebitrice, isTrue);
        expect(soldes(f4456), [1800]);

        final f4457 = await livre('4457', debut: debutMars, fin: finMars);
        expect(f4457.estDebitrice, isFalse);
        expect(soldes(f4457), [1800]);

        final f281 = await livre('281', debut: debutMars, fin: finMars);
        expect(f281.estDebitrice, isFalse);
        expect(soldes(f281), [600]);

        final f601 = await livre('601', debut: debutMars, fin: finMars);
        expect(f601.estDebitrice, isTrue);
        expect(f601.soldeOuverture, 40000);
        expect(soldes(f601), [40500]);
      },
    );
  });

  group('défaut 2 : période, ouverture, recherche', () {
    test('⚠️⚠️ les bornes : début EXCLU de l ouverture, fin INCLUSE', () async {
      await jeu();

      // Période du 2 au 2 mars : e04 (1er mars) passe dans l'ouverture ; e10 (20 mars) sort.
      final g = await livre(
        '531',
        debut: DateTime(2026, 3, 2),
        fin: DateTime(2026, 3, 2),
      );
      expect(g.soldeOuverture, 105000); // 100 000 + 3 000 + 2 000
      expect(soldes(g), [90000, 115000, 114500]);

      // Fin le 30 mars : la pièce du 31 est hors période ; celle du 20 reste.
      final h = await livre(
        '531',
        debut: debutMars,
        fin: DateTime(2026, 3, 30),
      );
      expect(soldes(h), [105000, 90000, 115000, 114500, 109500]);
      expect(h.soldeFinal, 109500);
    });

    test(
      'une pièce datée du jour de début n entre PAS dans l ouverture',
      () async {
        await jeu();
        final g = await livre('701', debut: debutMars, fin: finMars);

        // e04 (1er mars, 2 000) est une ligne de la période, pas de l'ouverture (3 000 seulement).
        expect(g.soldeOuverture, 3000);
        expect(g.mouvements.first.ecriture.id, uuid('e04'));
      },
    );

    test(
      'début après fin : aucune ligne, ouverture calculée avant le début',
      () async {
        await jeu();
        final g = await livre('531', debut: finMars, fin: debutMars);

        expect(g.mouvements, isEmpty);
        // Avant le 31 mars : tout sauf e11 et e12 → 100 000 + 3 000 + 2 000 − 15 000 + 25 000 − 500 − 5 000.
        expect(g.soldeOuverture, 109500);
        expect(g.soldeFinal, 109500);
      },
    );

    test(
      'sans bornes : tout le journal, ouverture nulle (rien avant)',
      () async {
        await jeu();
        final g = await livre('531');

        expect(g.soldeOuverture, 0);
        expect(g.mouvements, hasLength(9));
        // 110 500 + e12 (7 000).
        expect(g.soldeFinal, 117500);
      },
    );

    test(
      '⚠️ recherche : insensible à la casse et aux accents, sur la référence',
      () async {
        await jeu();

        final vente = await livre(
          '531',
          debut: debutMars,
          fin: finMars,
          recherche: 'VENTE',
        );
        // Lignes e04, e06, e11. ⚠️ Le solde progressif part de l'ouverture et ne compte QUE les lignes
        // filtrées, comme le serveur : 103 000 + 2 000 + 25 000 + 1 000.
        expect(soldes(vente), [105000, 130000, 131000]);
        expect(vente.totalDebit, 28000);
        expect(vente.totalCredit, 0);
        expect(vente.soldeFinal, 131000);

        final accent = await livre(
          '531',
          debut: debutMars,
          fin: finMars,
          recherche: 'reglement',
        );
        expect(soldes(accent), [88000]); // 103 000 − 15 000
        expect(accent.mouvements.single.piece, 'OD-2026-0004');

        final piece = await livre(
          '531',
          debut: debutMars,
          fin: finMars,
          recherche: 'od-2026-0011',
        );
        expect(piece.mouvements.single.libelle, 'Vente fin de mois');

        final rien = await livre(
          '531',
          debut: debutMars,
          fin: finMars,
          recherche: 'introuvable',
        );
        expect(rien.mouvements, isEmpty);
        // L'ouverture ne dépend PAS de la recherche.
        expect(rien.soldeOuverture, 103000);
        expect(rien.soldeFinal, 103000);
      },
    );

    test(
      'une référence absente ne correspond à aucune recherche non vide',
      () async {
        await compte('531', 'Caisse', 5);
        await compte('701', 'Ventes', 7);
        await ecriture(
          'x1',
          date: DateTime(2026, 3, 5),
          reference: null,
          debit: '531',
          credit: '701',
          montant: 100,
        );

        expect(
          (await livre('531', debut: debutMars, fin: finMars)).mouvements,
          hasLength(1),
        );
        expect(
          (await livre(
            '531',
            debut: debutMars,
            fin: finMars,
            recherche: 'a',
          )).mouvements,
          isEmpty,
        );
      },
    );
  });

  group('défaut 3 : le tri départage les pièces du même jour', () {
    test(
      '⚠️⚠️ date, puis création, puis identifiant — jamais l ordre d insertion',
      () async {
        await jeu();
        final g = await livre(
          '531',
          debut: DateTime(2026, 3, 2),
          fin: DateTime(2026, 3, 2),
        );

        // e05 (créée 10:00:01) AVANT e06 (10:00:05). e06 et e07 ont le MÊME instant : l'identifiant
        // départage (e06 < e07). Insérées dans l'ordre e07, e06, e05.
        expect(g.mouvements.map((m) => m.ecriture.id), [
          uuid('e05'),
          uuid('e06'),
          uuid('e07'),
        ]);
        expect(soldes(g), [90000, 115000, 114500]);
      },
    );

    test(
      'une création inconnue passe APRÈS une création connue du même jour',
      () async {
        await compte('531', 'Caisse', 5);
        await compte('701', 'Ventes', 7);
        final jour = DateTime(2026, 3, 5);
        await ecriture(
          'a1',
          date: jour,
          reference: 'A',
          debit: '531',
          credit: '701',
          montant: 10,
        );
        await ecriture(
          'b1',
          date: jour,
          reference: 'B',
          debit: '531',
          credit: '701',
          montant: 20,
          creeLe: DateTime(2026, 3, 5, 9),
        );

        final g = await livre('531', debut: debutMars, fin: finMars);
        expect(g.mouvements.map((m) => m.ecriture.id), [
          uuid('b1'),
          uuid('a1'),
        ]);
      },
    );

    /// ⚠️ Le jeu principal ne suffit pas : il y crée e05 avant e06 ET e05 a le plus petit identifiant.
    /// Ici l'ordre de création est l'INVERSE de l'ordre des identifiants (« zz » créée avant « aa »).
    test(
      '⚠️⚠️ la création prime sur l identifiant quand ils s opposent',
      () async {
        await compte('531', 'Caisse', 5);
        await compte('701', 'Ventes', 7);
        final jour = DateTime(2026, 3, 5);
        await ecriture(
          'aa',
          date: jour,
          reference: 'créée en second',
          debit: '531',
          credit: '701',
          montant: 500,
          creeLe: DateTime(2026, 3, 5, 10),
        );
        await ecriture(
          'zz',
          date: jour,
          reference: 'créée en premier',
          debit: '531',
          credit: '701',
          montant: 1000,
          creeLe: DateTime(2026, 3, 5, 9),
        );

        final g = await livre('531', debut: debutMars, fin: finMars);
        expect(g.mouvements.map((m) => m.ecriture.id), [
          uuid('zz'),
          uuid('aa'),
        ]);
        expect(soldes(g), [1000, 1500]);
      },
    );

    test('une date d un autre jour prime sur la création', () async {
      await compte('531', 'Caisse', 5);
      await compte('701', 'Ventes', 7);
      await ecriture(
        'tard',
        date: DateTime(2026, 3, 9),
        reference: 'tard',
        debit: '531',
        credit: '701',
        montant: 1,
        creeLe: DateTime(2026, 3, 1),
      );
      await ecriture(
        'tot',
        date: DateTime(2026, 3, 3),
        reference: 'tôt',
        debit: '531',
        credit: '701',
        montant: 1,
        creeLe: DateTime(2026, 3, 30),
      );

      final g = await livre('531', debut: debutMars, fin: finMars);
      expect(g.mouvements.map((m) => m.ecriture.id), [
        uuid('tot'),
        uuid('tard'),
      ]);
    });
  });

  group('« — » et non 0 quand le poste ne sait pas', () {
    test(
      '⚠️⚠️ un compte sans aucune écriture est SANS ÉCRITURE, pas à zéro',
      () async {
        await jeu();
        final g = await livre('411', debut: debutMars, fin: finMars);

        expect(g.sansEcriture, isTrue);
        expect(g.soldeOuverture, isNull);
        expect(g.soldeFinal, isNull);
        expect(g.mouvements, isEmpty);
      },
    );

    test(
      '⚠️⚠️ un journal incomplet rend l ouverture et le final inconnus',
      () async {
        await jeu();
        // Une écriture à qui il manque sa ligne crédit : tirage incomplet.
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: uuid('boiteuse'),
                entryDate: DateTime(2026, 2, 1),
                reference: const Value('OD-2026-0099 — Boiteuse'),
              ),
            );
        await db
            .into(db.accountingEntryLines)
            .insert(
              AccountingEntryLinesCompanion.insert(
                id: uuid('boiteuse1'),
                entryId: uuid('boiteuse'),
                accountId: uuid('c531'),
                debit: const Value(9999),
              ),
            );

        final g = await livre('531', debut: debutMars, fin: finMars);
        expect(g.journalIncomplet, isTrue);
        expect(g.soldeOuverture, isNull);
        expect(g.soldeFinal, isNull);
        // Les lignes de la période, elles, restent affichées.
        expect(g.mouvements, hasLength(6));
      },
    );
  });

  group('compte par défaut', () {
    test(
      '⚠️ 531 quand il existe, même si un autre compte porte des écritures',
      () async {
        await jeu();
        final d = await depot.charger();
        expect(d.compteGrandLivreParDefaut!.code, '531');
      },
    );

    test('à défaut de 531, le premier code du plan (comme le serveur)', () async {
      await compte('701', 'Ventes', 7);
      await compte('101', 'Capital', 1);
      await compte('401', 'Fournisseurs', 4);
      await ecriture(
        'z',
        date: DateTime(2026, 3, 5),
        reference: 'Z',
        debit: '401',
        credit: '701',
        montant: 5,
      );

      final d = await depot.charger();
      // ⚠️ « 101 » n'a aucune écriture : le serveur ouvre quand même sur le plus petit code.
      expect(d.compteGrandLivreParDefaut!.code, '101');
    });

    test('plan vide : pas de compte', () async {
      final d = await depot.charger();
      expect(d.compteGrandLivreParDefaut, isNull);
    });
  });

  group('N° Pièce et Libellé : la référence se coupe au premier « — »', () {
    MouvementCompte avec(String? reference) => MouvementCompte(
      ecriture: AccountingEntry(
        id: uuid('p'),
        entryDate: DateTime(2026, 3, 1),
        reference: reference,
        isLocked: false,
      ),
      ligne: AccountingEntryLine(
        id: uuid('l'),
        entryId: uuid('p'),
        accountId: uuid('a'),
        debit: 1,
        credit: 0,
      ),
      soldeProgressif: 1,
    );

    test('découpe, rogne, et ne coupe qu une fois', () {
      expect(avec('OD-2026-0003 — Vente comptant').piece, 'OD-2026-0003');
      expect(avec('OD-2026-0003 — Vente comptant').libelle, 'Vente comptant');
      expect(avec('A — B — C').piece, 'A');
      expect(avec('A — B — C').libelle, 'B — C');
      expect(avec('  A  —  B  ').piece, 'A');
      expect(avec('  A  —  B  ').libelle, 'B');
    });

    test('sans séparateur : tout est le numéro, le libellé est vide', () {
      expect(avec('Vente au comptoir').piece, 'Vente au comptoir');
      expect(avec('Vente au comptoir').libelle, '');
    });

    test('référence absente : deux champs vides', () {
      expect(avec(null).piece, '');
      expect(avec(null).libelle, '');
    });
  });

  group('écran', () {
    final mars20 = DateTime(2026, 3, 20);

    Future<void> afficher(WidgetTester tester, {DateTime? maintenant}) async {
      tester.view.physicalSize = const Size(1700, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ComptabiliteScreen(
            depot: depot,
            maintenant: () => maintenant ?? mars20,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('carte-grandLivre')));
      await tester.pumpAndSettle();
    }

    Finder dans(String cle, String texte) =>
        find.descendant(of: find.byKey(Key(cle)), matching: find.text(texte));

    testWidgets(
      '⚠️⚠️ ouvre sur 531, du premier du mois à aujourd hui, quatre cartes',
      (tester) async {
        await jeu();
        await afficher(tester);

        // Période par défaut : 01/03/2026 → 20/03/2026 (jour inclus).
        expect(dans('gl-date-debut', '01/03/2026'), findsOneWidget);
        expect(dans('gl-date-fin', '20/03/2026'), findsOneWidget);

        expect(find.byType(CarteKpi), findsNWidgets(4));
        // Ouverture 103 000 ; débits 2 000 + 25 000 = 27 000 ; crédits 15 000 + 500 + 5 000 = 20 500 ;
        // final 109 500 (le 31 mars est hors période).
        expect(dans('kpi-livre-ouverture', '103 000'), findsOneWidget);
        expect(dans('kpi-livre-debit', '27 000'), findsOneWidget);
        expect(dans('kpi-livre-credit', '20 500'), findsOneWidget);
        expect(dans('kpi-livre-final', '109 500'), findsOneWidget);
        expect(find.text("Solde d'Ouverture".toUpperCase()), findsOneWidget);
        expect(find.text('Solde Final'.toUpperCase()), findsOneWidget);
      },
    );

    testWidgets(
      '⚠️ N° Pièce et Libellé séparés, solde sur la ligne, tiret pour le zéro',
      (tester) async {
        await jeu();
        await afficher(tester);

        // Première ligne : e04, 01/03/2026, OD-2026-0006 / Vente début de mois, débit 2 000, solde 105 000.
        Finder l0(String t) => find.descendant(
          of: find.byKey(const Key('ligne-0')),
          matching: find.text(t),
        );
        expect(l0('01/03/2026'), findsOneWidget);
        expect(l0('OD-2026-0006'), findsOneWidget);
        expect(l0('Vente début de mois'), findsOneWidget);
        expect(l0('2 000'), findsOneWidget);
        expect(
          l0('—'),
          findsOneWidget,
          reason: 'crédit nul = tiret, comme la maquette',
        );
        expect(l0('105 000'), findsOneWidget);

        // Deuxième ligne : e05 (créé avant e06), crédit 15 000, solde 90 000.
        Finder l1(String t) => find.descendant(
          of: find.byKey(const Key('ligne-1')),
          matching: find.text(t),
        );
        expect(l1('OD-2026-0004'), findsOneWidget);
        expect(l1('90 000'), findsOneWidget);
      },
    );

    testWidgets('⚠️⚠️ choisir 701 : solde créditeur sur l écran', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('compte-grand-livre')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('701 — Ventes').last);
      await tester.pumpAndSettle();

      // Période 1er → 20 mars : ouverture 3 000 ; e04 +2 000 ; e06 +25 000 → 30 000.
      expect(dans('kpi-livre-ouverture', '3 000'), findsOneWidget);
      expect(dans('kpi-livre-final', '30 000'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('ligne-1')),
          matching: find.text('30 000'),
        ),
        findsOneWidget,
      );
    });

    // ── Ticket F0.86-bis : un solde NÉGATIF qui s'arrondit à zéro s'écrit « 0 », jamais « -0 » ──────
    // Le Grand Livre partage le `_montant` de la Balance (solde final, solde progressif, ouverture).
    // Référence : `number_format(-0.4, 0, ',', ' ')` = « 0 », `(-0.6)` = « -1 », `(-12345.6)` =
    // « -12 346 » (PHP 8.3.30, mesuré).

    /// 531 et 701 seuls ; le 1er mars, 531 reçoit [entree] au débit ; le 5 mars, [sortie] au crédit.
    /// Deux écritures ÉQUILIBRÉES : le journal est complet, les soldes sont connus.
    Future<void> caisseNegative(double entree, double sortie) async {
      await compte('531', 'Caisse', 5);
      await compte('701', 'Ventes', 7);
      if (entree > 0) {
        await ecriture(
          'n1',
          date: DateTime(2026, 3, 1),
          reference: 'OD-2026-0101 — Entrée',
          debit: '531',
          credit: '701',
          montant: entree,
        );
      }
      await ecriture(
        'n2',
        date: DateTime(2026, 3, 5),
        reference: 'OD-2026-0102 — Sortie',
        debit: '701',
        credit: '531',
        montant: sortie,
      );
    }

    Finder ligne(int i, String t) => find.descendant(
      of: find.byKey(Key('ligne-$i')),
      matching: find.text(t),
    );

    testWidgets(
      '⚠️⚠️ F0.86-bis : solde de -0,4 → « 0 » sur la carte ET la ligne, jamais « -0 »',
      (tester) async {
        // 531 : +1 000 puis -1 000,40 → solde progressif 1 000 puis -0,40 ; final -0,40.
        await caisseNegative(1000, 1000.4);
        await afficher(tester);

        expect(ligne(0, '1 000'), findsWidgets);
        expect(ligne(1, '0'), findsOneWidget);
        expect(dans('kpi-livre-final', '0'), findsOneWidget);
        expect(find.text('-0'), findsNothing);
      },
    );

    testWidgets('⚠️ F0.86-bis : solde de -0,6 → « -1 » (le signe reste)', (
      tester,
    ) async {
      await caisseNegative(1000, 1000.6);
      await afficher(tester);

      expect(ligne(1, '-1'), findsOneWidget);
      expect(dans('kpi-livre-final', '-1'), findsOneWidget);
    });

    testWidgets(
      'F0.86-bis : le format des milliers des négatifs est inchangé (« -12 346 »)',
      (tester) async {
        await caisseNegative(0, 12345.6);
        await afficher(tester);

        expect(ligne(0, '-12 346'), findsOneWidget);
        expect(dans('kpi-livre-final', '-12 346'), findsOneWidget);
        expect(dans('kpi-livre-credit', '12 346'), findsOneWidget);
      },
    );

    testWidgets('la recherche filtre les lignes et pas l ouverture', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);

      await tester.enterText(
        find.byKey(const Key('gl-recherche')),
        'reglement',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ligne-0')), findsOneWidget);
      expect(find.byKey(const Key('ligne-1')), findsNothing);
      expect(dans('kpi-livre-ouverture', '103 000'), findsOneWidget);
      expect(dans('kpi-livre-final', '88 000'), findsOneWidget);
    });

    testWidgets('⚠️ aucune ligne : le message de la maquette', (tester) async {
      await jeu();
      await afficher(tester);

      await tester.enterText(find.byKey(const Key('gl-recherche')), 'zzz');
      await tester.pumpAndSettle();

      expect(
        find.text('Aucune écriture ne correspond à ces critères.'),
        findsOneWidget,
      );
      // Les totaux de période d'un compte qui a des écritures AILLEURS sont de vrais zéros.
      expect(dans('kpi-livre-debit', '0'), findsOneWidget);
      expect(dans('kpi-livre-final', '103 000'), findsOneWidget);
    });

    testWidgets(
      '⚠️⚠️ un compte sans écriture : quatre tirets motivés, jamais 0',
      (tester) async {
        await jeu();
        await afficher(tester);

        await tester.tap(find.byKey(const Key('compte-grand-livre')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('411 — Clients').last);
        await tester.pumpAndSettle();

        for (final cle in [
          'kpi-livre-ouverture',
          'kpi-livre-debit',
          'kpi-livre-credit',
          'kpi-livre-final',
        ]) {
          expect(dans(cle, '—'), findsOneWidget, reason: cle);
          expect(dans(cle, '0'), findsNothing, reason: cle);
        }
        expect(
          find.textContaining('Aucune écriture sur ce compte'),
          findsWidgets,
        );
      },
    );

    testWidgets('⚠️ la date de fin se choisit au calendrier et recalcule', (
      tester,
    ) async {
      await jeu();
      await afficher(tester);

      await tester.tap(find.byKey(const Key('gl-date-fin')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('31')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(dans('gl-date-fin', '31/03/2026'), findsOneWidget);
      // Avec le 31 mars : final 110 500.
      expect(dans('kpi-livre-final', '110 500'), findsOneWidget);
    });

    testWidgets(
      '⚠️ journal incomplet : ouverture et final en tiret, avec la raison',
      (tester) async {
        await jeu();
        await db
            .into(db.accountingEntries)
            .insert(
              AccountingEntriesCompanion.insert(
                id: uuid('boiteuse'),
                entryDate: DateTime(2026, 2, 1),
                reference: const Value('OD-2026-0099 — Boiteuse'),
              ),
            );
        await db
            .into(db.accountingEntryLines)
            .insert(
              AccountingEntryLinesCompanion.insert(
                id: uuid('boiteuse1'),
                entryId: uuid('boiteuse'),
                accountId: uuid('c531'),
                debit: const Value(9999),
              ),
            );
        await afficher(tester);

        expect(dans('kpi-livre-ouverture', '—'), findsOneWidget);
        expect(dans('kpi-livre-final', '—'), findsOneWidget);
        expect(find.textContaining('Journal incomplet'), findsWidgets);
        // Les lignes de la période sont affichées quand même.
        expect(find.byKey(const Key('ligne-0')), findsOneWidget);
      },
    );

    testWidgets('les colonnes de la maquette, dans l ordre', (tester) async {
      await jeu();
      await afficher(tester);

      final titres = [
        'DATE',
        'N° PIÈCE',
        'LIBELLÉ',
        'DÉBIT',
        'CRÉDIT',
        'SOLDE PROGRESSIF',
      ];
      final x = [for (final t in titres) tester.getTopLeft(find.text(t)).dx];
      for (var i = 1; i < x.length; i++) {
        expect(x[i], greaterThan(x[i - 1]), reason: titres[i]);
      }
    });

    // ── Fidélité à la maquette ET à la page web (lues dans le dépôt Laravel, jamais copiées) ──────

    final maquette = File(
      '$dossierPrototype/grand-livre.html',
    );
    final vueWeb = File(
      '$dossierLaravel/resources/views/livewire/comptabilite/grand-livre.blade.php',
    );
    final sautMaquette = maquette.existsSync() && vueWeb.existsSync()
        ? null
        : 'SAUT : maquette ou vue web absente';

    List<String> trouver(String source, RegExp motif) => [
      for (final m in motif.allMatches(source)) m.group(1)!.trim(),
    ];

    testWidgets(
      '⚠️⚠️ les quatre cartes : les libellés de la maquette ET de la page web, dans l ordre',
      (tester) async {
        final cartesMaquette = trouver(
          maquette.readAsStringSync(),
          RegExp(
            r'<span class="text-\[10px\] text-outline font-bold uppercase block">([^<]+)</span>',
          ),
        );
        final cartesWeb = trouver(
          vueWeb.readAsStringSync(),
          RegExp(r'<x-kpi-card label="([^"]+)"'),
        );
        expect(cartesMaquette, [
          "Solde d'Ouverture",
          'Total Débit Période',
          'Total Crédit Période',
          'Solde Final',
        ]);
        expect(cartesWeb, cartesMaquette);

        await jeu();
        await afficher(tester);

        final x = [
          for (final c in cartesMaquette)
            tester.getTopLeft(find.text(c.toUpperCase())).dx,
        ];
        for (var i = 1; i < x.length; i++) {
          expect(x[i], greaterThan(x[i - 1]), reason: cartesMaquette[i]);
        }
      },
      skip: sautMaquette != null,
    );

    testWidgets(
      '⚠️⚠️ les colonnes <th> de la maquette, dans l ordre, et la page web identique',
      (tester) async {
        final entetes = trouver(
          maquette.readAsStringSync(),
          RegExp(r'<th class="[^"]*">([^<]+)</th>'),
        );
        expect(entetes, [
          'Date',
          'N° Pièce',
          'Libellé',
          'Débit',
          'Crédit',
          'Solde Progressif',
        ]);
        expect(
          trouver(
            vueWeb.readAsStringSync(),
            RegExp(r'<th class="[^"]*">([^<]+)</th>'),
          ),
          entetes,
        );

        await jeu();
        await afficher(tester);

        final x = [
          for (final e in entetes)
            tester.getTopLeft(find.text(e.toUpperCase())).dx,
        ];
        for (var i = 1; i < x.length; i++) {
          expect(x[i], greaterThan(x[i - 1]), reason: entetes[i]);
        }
      },
      skip: sautMaquette != null,
    );

    testWidgets(
      '⚠️ sous-titre, recherche, état vide et plan vide : les textes de la maquette et de la page web',
      (tester) async {
        final html = maquette.readAsStringSync();
        final blade = vueWeb.readAsStringSync();

        const sousTitre =
            "Écritures chronologiques d'un compte, avec solde progressif.";
        const recherche = 'Rechercher un libellé, une pièce...';
        const vide = 'Aucune écriture ne correspond à ces critères.';
        const planVide = 'Aucun compte au plan comptable';

        for (final texte in [sousTitre, recherche, vide]) {
          expect(html, contains(texte), reason: 'maquette : $texte');
          expect(blade, contains(texte), reason: 'page web : $texte');
        }
        expect(blade, contains(planVide));

        // Plan vide : le texte de la page web, aucune carte à zéro.
        await afficher(tester);
        expect(find.text(sousTitre), findsOneWidget);
        expect(find.text(recherche), findsOneWidget);
        expect(find.text(planVide), findsOneWidget);
        for (final cle in [
          'kpi-livre-ouverture',
          'kpi-livre-debit',
          'kpi-livre-credit',
          'kpi-livre-final',
        ]) {
          expect(dans(cle, '—'), findsOneWidget, reason: cle);
        }
      },
      skip: sautMaquette != null,
    );

    test(
      '⚠️ le bouton « Exporter PDF » de la maquette est porté (ticket F0.87, ancien écart T4)',
      () {
        // Jusqu'au ticket F0.87 ce test verrouillait l'ABSENCE du bouton (écart connu, T4). Le bouton
        // est arrivé : l'exemption de `fidelite_libelles_test.dart` a disparu avec lui, et le
        // comportement est éprouvé par `export_comptabilite_test.dart`.
        final source = File(
          'lib/features/comptabilite/comptabilite_screen.dart',
        ).readAsStringSync();
        expect(source.contains("'Exporter PDF'"), isTrue);
        expect(source.contains("'exporter-pdf-grand-livre'"), isTrue);
        expect(
          maquette.existsSync() ? maquette.readAsStringSync() : 'Exporter PDF',
          contains('Exporter PDF'),
        );
      },
    );
  });

  group('parité avec la règle du serveur', () {
        final source = File(
      '$dossierLaravel/app/Services/FinancialReportService.php',
    );
    final csv = File(
      '$dossierLaravel/database/data/plan-comptable-syscohada-revise.csv',
    );

    String? php() {
      for (final candidat in ['php', 'php.exe']) {
        try {
          final r = Process.runSync(candidat, ['-v']);
          if (r.exitCode == 0) return candidat;
        } catch (_) {}
      }
      final base = Directory('C:/laragon/bin/php');
      if (base.existsSync()) {
        for (final d in base.listSync().whereType<Directory>()) {
          final exe = File('${d.path}/php.exe');
          if (exe.existsSync()) return exe.path;
        }
      }
      return null;
    }

    final executable = php();
    final saut = !source.existsSync() || !csv.existsSync() || executable == null
        ? 'SAUT : dépôt Laravel ou PHP absent '
              '(${source.existsSync()}, ${csv.existsSync()}, $executable)'
        : null;

    /// Appelle la VRAIE règle du serveur, `FinancialReportService::natureDebitrice`, sur chaque
    /// couple (code, classe) donné. Rien n'est recopié dans ce test : la vérité est exécutée.
    List<bool> reponseDuServeur(List<(String, int)> couples) {
      final entree =
          File(
            '${Directory.systemTemp.path}/nature_${DateTime.now().microsecondsSinceEpoch}.json',
          )..writeAsStringSync(
            jsonEncode([
              for (final (c, k) in couples) [c, k],
            ]),
          );
      try {
        final r = Process.runSync(executable!, [
          '-r',
          "require 'vendor/autoload.php'; "
              r"$e = json_decode(file_get_contents($argv[1]), true); "
              r"$s = []; foreach ($e as $p) { "
              r"$s[] = App\Services\FinancialReportService::natureDebitrice((string) $p[0], (int) $p[1]); } "
              r"echo json_encode($s);",
          entree.path,
        ], workingDirectory: dossierLaravel);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        return (jsonDecode(r.stdout as String) as List).cast<bool>();
      } finally {
        entree.deleteSync();
      }
    }

    test(
      '⚠️⚠️ les 1 332 comptes du plan officiel : la même nature que le serveur',
      () {
        final codes = csv
            .readAsLinesSync()
            .skip(1)
            .map((l) => l.replaceAll('\uFEFF', '').split(';').first.trim())
            .where((c) => c.isNotEmpty)
            .toList();
        expect(codes.length, greaterThan(1300));

        final couples = [for (final c in codes) (c, int.parse(c[0]))];
        final serveur = reponseDuServeur(couples);

        for (var i = 0; i < couples.length; i++) {
          expect(
            natureDebitrice(couples[i].$1, couples[i].$2),
            serveur[i],
            reason: 'compte ${couples[i].$1} (classe ${couples[i].$2})',
          );
        }
      },
      skip: saut,
    );

    test(
      '⚠️ les cinq comptes de la ferme absents du CSV, et les classes décalées',
      () {
        final couples = <(String, int)>[
          for (final c in ['313', '521101', '521201', '606', '657'])
            (c, int.parse(c[0])),
          // Classe en contradiction avec le code : la règle lit la CLASSE, pas le premier chiffre.
          for (final c in [
            '139',
            '281',
            '391',
            '409',
            '4457',
            '419',
            '4456',
            '445',
            '59',
            '701',
          ])
            for (var k = 0; k <= 9; k++) (c, k),
        ];
        final serveur = reponseDuServeur(couples);

        for (var i = 0; i < couples.length; i++) {
          expect(
            natureDebitrice(couples[i].$1, couples[i].$2),
            serveur[i],
            reason: 'compte ${couples[i].$1} (classe ${couples[i].$2})',
          );
        }
      },
      skip: saut,
    );

    test('⚠️ un échantillon pseudo-aléatoire de codes et de classes', () {
      // Graine fixe : déterministe, mais couvre des combinaisons que personne n'a pensé à écrire.
      var graine = 20261010;
      int suivant(int n) {
        graine = (graine * 1103515245 + 12345) & 0x7fffffff;
        return graine % n;
      }

      const prefixes = [
        '139',
        '28',
        '29',
        '39',
        '409',
        '445',
        '4457',
        '4456',
        '41',
        '419',
        '59',
        '7',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '8',
        '9',
        '43',
        '44',
        '40',
      ];
      final couples = <(String, int)>[
        for (var i = 0; i < 1500; i++)
          (
            prefixes[suivant(prefixes.length)] +
                List.generate(suivant(4), (_) => suivant(10)).join(),
            suivant(10),
          ),
      ];
      final serveur = reponseDuServeur(couples);

      for (var i = 0; i < couples.length; i++) {
        expect(
          natureDebitrice(couples[i].$1, couples[i].$2),
          serveur[i],
          reason: 'compte ${couples[i].$1} (classe ${couples[i].$2})',
        );
      }
    }, skip: saut);

    test(
      'le corps de la règle du serveur n a pas changé depuis la recopie',
      () {
        // Garde-fou LÉGER, indépendant de PHP : si le serveur réécrit sa règle, ce test le dit même
        // sur un poste de développement sans PHP. Il ne remplace pas la parité exécutée ci-dessus.
        final texte = source.readAsStringSync();
        final debut = texte.indexOf('public static function natureDebitrice');
        final fin = texte.indexOf('/** Lignes actives d\'un compte donné');
        expect(debut, greaterThan(0));
        expect(fin, greaterThan(debut));
        final corps = texte
            .substring(debut, fin)
            .replaceAll(RegExp(r'\s+'), ' ');

        for (final fragment in [
          "1 => \$commencePar('139')",
          "2 => ! \$commencePar('28', '29')",
          "3 => ! \$commencePar('39')",
          "\$commencePar('409')",
          "(\$commencePar('445') && ! \$commencePar('4457'))",
          "(\$commencePar('41') && ! \$commencePar('419'))",
          "5 => ! \$commencePar('59')",
          '7 => false',
          'default => true',
        ]) {
          expect(corps, contains(fragment), reason: fragment);
        }
      },
      skip: !source.existsSync() ? 'SAUT : dépôt Laravel absent' : null,
    );
  });

  group('caractérisation de la règle serveur', () {
    /// ⚠️⚠️ **À DÉCIDER PAR LE CABINET FAGUEZ — CE TEST NE VALIDE RIEN.**
    ///
    /// La règle du serveur est PAR CLASSE ; elle donne un sens discutable à plusieurs comptes du plan
    /// importé (ticket 15.27). Le poste la reproduit FIDÈLEMENT, sans la corriger : la règle
    /// comptable n'existe ni dans le prototype ni dans Laravel, et la trancher ici serait inventer.
    /// Ce test rend le comportement VISIBLE : il tombe le jour où le serveur — ou le poste — change,
    /// et il doit alors être mis à jour AVEC la décision du cabinet, pas avant.
    ///
    /// Valeurs = ce que la règle renvoie aujourd'hui (`true` = traité comme débiteur) :
    ///  - 109 / 129 / 1291 (classe 1) : traités comme créditeurs — alors que « apporteurs, capital
    ///    souscrit non appelé », « report à nouveau débiteur » et « perte nette à reporter » portent
    ///    un solde débiteur ;
    ///  - 47x / 48x (classe 4) : créditeurs — alors que « débiteurs et créditeurs divers » et « créances
    ///    HAO » ont des sous-comptes à solde débiteur ;
    ///  - 56 (classe 5) : débiteur — alors que « banques, crédits de trésorerie » est une dette ;
    ///  - 82 / 84 / 86 / 88 (classe 8) : débiteurs par défaut — alors que ce sont des produits HAO ;
    ///  - ⚠️ 119 / 609 / 619 / 629, cités par le ticket 15.27, N'EXISTENT PAS dans le fichier importé
    ///    (constaté au ticket F0.85) : ils ne figurent donc pas ici.
    test(
      '⚠️⚠️ à décider par le cabinet : comptes dont le sens par classe est discutable',
      () {
        const attendu = <String, bool>{
          '109': false,
          '129': false,
          '1291': false,
          '471': false,
          '472': false,
          '478': false,
          '481': false,
          '485': false,
          '561': true,
          '564': true,
          '82': true,
          '84': true,
          '86': true,
          '88': true,
        };

        attendu.forEach((code, debiteur) {
          expect(
            natureDebitrice(code, int.parse(code[0])),
            debiteur,
            reason:
                'compte $code : la règle du serveur, reproduite SANS correction',
          );
        });
      },
    );

    test(
      '⚠️ ces comptes existent bien au plan importé (sinon la liste est périmée)',
      () {
        final csv = File(
          '$dossierLaravel/database/data/plan-comptable-syscohada-revise.csv',
        );
        if (!csv.existsSync()) {
          // ignore: avoid_print
          print('SAUT : CSV du plan absent (${csv.path})');
          return;
        }
        final codes = csv
            .readAsLinesSync()
            .skip(1)
            .map((l) => l.replaceAll('\uFEFF', '').split(';').first.trim())
            .toSet();

        for (final c in [
          '109',
          '129',
          '1291',
          '471',
          '472',
          '478',
          '481',
          '485',
          '561',
          '564',
          '82',
          '84',
          '86',
          '88',
        ]) {
          expect(codes, contains(c), reason: 'compte $c');
        }
      },
    );
  });
}
