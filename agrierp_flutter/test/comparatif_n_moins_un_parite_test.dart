import 'dart:io';
import 'dart:math';

import 'package:agrierp/core/comptabilite/exercice_choisi.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:agrierp/features/comptabilite/etats_comparatifs.dart';
import 'package:agrierp/features/comptabilite/soldes_exercice.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket EX8 (EF11, décision Q5 du client du 20/10/2026) — BILAN ET COMPTE DE RÉSULTAT N / N-1 AU POSTE.
///
/// 1. **Parité EXÉCUTÉE des chiffres** : `FinancialReportService::bilanComparatif` / `compteResultatComparatif` du
///    serveur et [EtatsComparatifs] du poste, sur l'exemple du PRD § 5 + l'exemple R3 (dotation de 30 000 passée en
///    2026 le 20/02/2027) + 40 écritures pseudo-aléatoires, à cinq dates d'arrêté, AVANT la clôture de 2026
///    (à-nouveaux provisoires) et APRÈS (vrai assistant de clôture, étapes 1, 2 et 3 : l'écriture de solde `closing`
///    existe — elle doit être écartée des deux côtés).
/// 2. **Parité exécutée de l'ÉCRAN et du PDF** : les lignes RENDUES par le composant Livewire `EtatsFinanciers`
///    (onglets Bilan et Compte de Résultat, sans puis avec l'exercice en paramètre) et par le gabarit PDF du web,
///    cellule par cellule (libellés et montants mis en forme), = celles que le poste affiche et imprime.
/// 3. **Littéraux calculés à la main** sur l'exemple du § 5 (une parité entre deux implémentations fausses de la même
///    façon ne protégerait rien) : Bilan 2027 / 2026, Compte de résultat 2026 = 200 000 malgré l'écriture de solde,
///    « — » sans N-1.
/// 4. **Garde-fou de fidélité** : chaque libellé de l'écran du poste est dans `etats-financiers.blade.php`.
void main() {
  // ── Le jeu (celui de `bascule_exercice_parite_test.dart`, autre graine) ─────────────────────────────────────────
  final ecritures = <Map<String, Object>>[
    {'date': '2026-01-02', 'debit': '521101', 'credit': '101', 'montant': 1000000, 'libelle': 'Apport'},
    {'date': '2026-03-10', 'debit': '531', 'credit': '701', 'montant': 300000, 'libelle': 'Vente comptant'},
    {'date': '2026-04-15', 'debit': '605', 'credit': '531', 'montant': 100000, 'libelle': 'Énergie payée en caisse'},
    {'date': '2027-01-15', 'debit': '531', 'credit': '701', 'montant': 50000, 'libelle': 'Vente comptant'},
  ];
  final alea = Random(20271021);
  final codes = ['101', '401', '411', '521101', '531', '601', '605', '661', '681', '701', '771'];
  final jours = <String>{};
  while (jours.length < 40) {
    final d = DateTime(2026, 1, 3).add(Duration(days: alea.nextInt(540)));
    if ((d.month == 12 && d.day == 31) || (d.month == 1 && d.day == 1)) continue;
    if (d.isAfter(DateTime(2027, 6, 29))) continue;
    final cle = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (ecritures.any((e) => e['date'] == cle)) continue;
    jours.add(cle);
  }
  for (final j in jours.toList()..sort()) {
    final a = codes[alea.nextInt(codes.length)];
    var b = codes[alea.nextInt(codes.length)];
    if (b == a) b = codes[(codes.indexOf(a) + 1) % codes.length];
    // ⚠️ Montants en francs entiers (le FCFA n'a pas de centimes) : sur SQLite, des centimes sur de nombreux comptes
    // de gestion laissent un résidu flottant dans `SUM(debit) <> SUM(credit)` de l'étape 2, et la clôture du test se
    // refuse (« Étape 2 non faite ») — artefact de la base en mémoire (MySQL : `decimal`), sans rapport avec EX8.
    ecritures.add({'date': j, 'debit': a, 'credit': b, 'montant': alea.nextInt(40000) + 1, 'libelle': 'Pièce $j'});
  }
  const dates = ['2026-03-31', '2026-12-31', '2027-01-31', '2027-02-20', '2027-06-30'];
  final maintenants = {'provisoire': DateTime(2027, 2, 20, 12), 'definitif': DateTime(2027, 3, 15, 12)};

  Map<String, dynamic>? serveur;
  setUpAll(() {
    if (sautSansPhp() != null) return;
    serveur =
        executerPhp('<?php\n$amorceApplication\n$_script', {'ecritures': ecritures, 'dates': dates}, application: true)
            as Map<String, dynamic>;
  });

  /// Range dans une base Drift NEUVE ce que le serveur a servi (exercices, plan, journal actif).
  Future<AppDatabase> basePoste(Map<String, dynamic> photo) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    for (final e in photo['exercices'] as List) {
      await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          id: e['id'] as String,
          year: e['year'] as int,
          startDate: Value(DateTime.parse(e['start_date'] as String)),
          endDate: Value(DateTime.parse(e['end_date'] as String)),
          status: Value(e['status'] as String),
        ),
      );
    }
    for (final c in photo['plan'] as List) {
      await db.into(db.chartOfAccounts).insert(
        ChartOfAccountsCompanion.insert(
          id: c['id'] as String,
          code: c['code'] as String,
          label: c['label'] as String,
          accountClass: Value(c['class'] as int),
        ),
      );
    }
    for (final e in photo['journal'] as List) {
      await db.into(db.accountingEntries).insert(
        AccountingEntriesCompanion.insert(
          id: e['id'] as String,
          fiscalYearId: Value(e['fiscal_year_id'] as String?),
          entryDate: DateTime.parse(e['entry_date'] as String),
          reference: Value(e['reference'] as String?),
          sourceType: Value(e['source_type'] as String?),
          isLocked: Value(e['is_locked'] as bool),
          createdAt: Value(DateTime.parse(e['created_at'] as String)),
        ),
      );
      for (final l in e['lines'] as List) {
        await db.into(db.accountingEntryLines).insert(
          AccountingEntryLinesCompanion.insert(
            id: l['id'] as String,
            entryId: e['id'] as String,
            accountId: l['account_id'] as String,
            debit: Value((l['debit'] as num).toDouble()),
            credit: Value((l['credit'] as num).toDouble()),
          ),
        );
      }
    }
    return db;
  }

  double? n(Object? v) => v == null ? null : (v as num).toDouble();
  List<List<String>> lignesDe(Object? v) => [for (final l in v as List) (l as List).cast<String>()];

  /// Les lignes d'un document du poste, comme le web les rend (`textContent` de chaque cellule).
  List<List<String>> lignesDocument(DocumentOfficiel d) => [
    for (final l in d.lignes)
      switch (l) {
        BandeDocument(:final libelle) => [libelle],
        DonneesDocument(:final cellules) => cellules,
        TotalDocument(:final cellules) => cellules,
        EnteteDocument(:final cellules) => cellules,
      },
  ];

  List<String> enteteEcran(ColonneExercice n, ColonneExercice? n1) => [
    '',
    '${EtatsComparatifs.enteteN}|${EtatsComparatifs.sousTitre(n)}',
    '${EtatsComparatifs.enteteN1}|${EtatsComparatifs.sousTitre(n1)}',
  ];

  Future<void> comparer(String phase) async {
    final photo = serveur![phase] as Map<String, dynamic>;
    final sources = {for (final e in photo['journal'] as List) e['source_type']};
    if (phase == 'definitif') {
      expect(sources, containsAll(['ran', 'closing']), reason: 'l écriture de solde et l à-nouveau existent');
    } else {
      expect(sources.contains('closing'), isFalse);
    }
    final db = await basePoste(photo);
    addTearDown(db.close);
    final d = await ComptabiliteRepository(database: db).charger();
    expect(d.ecrituresIncompletes, 0);

    // 1. Les chiffres, à chaque date d'arrêté.
    final comparatifs = photo['comparatifs'] as Map<String, dynamic>;
    for (final date in dates) {
      final attendu = comparatifs[date] as Map<String, dynamic>;
      final raison = '$phase — $date';
      final b = d.bilanComparatif(DateTime.parse(date));
      final wb = attendu['bilan'] as Map<String, dynamic>;
      expect(b.exerciceN.annee, (wb['exercice_n'] as Map)['annee'], reason: raison);
      final wn1 = wb['exercice_n1'] as Map?;
      expect(b.exerciceN1?.annee, wn1?['annee'], reason: raison);
      expect(b.exerciceN1 == null ? null : EtatsComparatifs.sousTitre(b.exerciceN1), wn1 == null ? null : '${wn1['annee']} — au ${(wn1['arrete'] as String).split('-').reversed.join('/')}');
      for (final rubrique in BilanEtat.rubriques) {
        expect(
          [for (final l in b.lignes[rubrique]!) [l.code, l.libelle, l.provisoire, l.n, l.n1]],
          [
            for (final l in (wb['lignes'] as Map)[rubrique] as List)
              [l['code'], l['label'], l['provisoire'], n(l['n']), n(l['n1'])],
          ],
          reason: '$raison — $rubrique',
        );
      }
      for (final (colonne, etat) in [('n', b.n), ('n1', b.n1)]) {
        final w = wb[colonne] as Map?;
        expect(etat == null, w == null, reason: '$raison — $colonne');
        if (etat == null) continue;
        expect(
          [etat.totalImmo, etat.totalCirculant, etat.totalTresorerie, etat.totalActif, etat.totalCapitaux,
            etat.resultat, etat.totalDettes, etat.totalPassif, etat.equilibre, etat.ouverture.provisoire],
          [n(w!['total_immo']), n(w['total_circulant']), n(w['total_tresorerie']), n(w['total_actif']),
            n(w['total_capitaux']), n(w['resultat']), n(w['total_dettes']), n(w['total_passif']), w['is_balanced'],
            (w['ouverture'] as Map)['provisoire']],
          reason: '$raison — totaux $colonne',
        );
      }
      final r = d.compteResultatComparatif(DateTime.parse(date));
      final wr = attendu['resultat'] as Map<String, dynamic>;
      for (final (colonne, etat) in [('n', r.n), ('n1', r.n1)]) {
        final w = wr[colonne] as Map?;
        expect(etat == null, w == null, reason: '$raison — CR $colonne');
        if (etat == null) continue;
        for (final (_, cle, _, _) in EtatsComparatifs.cascadePdf) {
          expect(etat.valeur(cle), n(w![cle]), reason: '$raison — CR $colonne $cle');
        }
      }
    }

    // 2. L'écran et le PDF, sans puis avec l'exercice en paramètre.
    final maintenant = maintenants[phase]!;
    for (final rendu in photo['rendus'] as List) {
      final w = rendu as Map<String, dynamic>;
      final exercice = w['exercice'] as int?;
      final raison = '$phase — exercice ${exercice ?? 'par défaut'}';
      // Fusion EX7 + EX8 : l'exercice affiché (`ExerciceChoisi`), le paramètre étant un choix.
      final etat = EtatExercice(exercices: d.exercices, memorise: exercice, aujourdhui: maintenant);
      final arrete = d.arreteEtatsFinanciers(etat);
      final situation = EtatsComparatifs.situation(arrete, d.anneeEtatsFinanciers(etat));
      expect(situation, w['situation'], reason: raison);
      final b = d.bilanComparatif(arrete);
      final r = d.compteResultatComparatif(arrete);
      final tables = (w['ecran_bilan'] as List).map(lignesDe).toList();
      expect(tables, hasLength(2), reason: raison);
      expect(tables[0], [enteteEcran(b.exerciceN, b.exerciceN1), for (final l in EtatsComparatifs.tableauActif(b)) l.cellules], reason: '$raison — Actif');
      expect(tables[1], [enteteEcran(b.exerciceN, b.exerciceN1), for (final l in EtatsComparatifs.tableauPassif(b)) l.cellules], reason: '$raison — Passif');
      final tableR = (w['ecran_resultat'] as List).map(lignesDe).toList();
      expect(tableR, [
        [enteteEcran(r.exerciceN, r.exerciceN1), for (final l in EtatsComparatifs.tableauResultat(r)) l.cellules],
      ], reason: '$raison — Compte de Résultat');

      final pdfs = (w['pdf'] as List).cast<Map<String, dynamic>>();
      final documents = [
        EtatsComparatifs.documentBilan(b, situation: situation),
        EtatsComparatifs.documentResultat(r, situation: situation, provisoire: b.n.ouverture.provisoire),
      ];
      for (var i = 0; i < 2; i++) {
        expect(documents[i].titre, pdfs[i]['titre'], reason: raison);
        expect(documents[i].sousTitre, pdfs[i]['periode'], reason: raison);
        final lignes = lignesDe(pdfs[i]['lignes']);
        expect(lignes.first, documents[i].entetes, reason: '$raison — en-têtes du PDF');
        expect(lignes.skip(1).toList(), lignesDocument(documents[i]), reason: '$raison — lignes du PDF ${documents[i].titre}');
        expect(DocumentOfficiel.nomPdf(documents[i], maintenant), pdfs[i]['fichier'], reason: raison);
      }
    }
  }

  test(
    'parité exécutée EX8 — avant la clôture de 2026 : Bilan et Compte de résultat N / N-1, écran et PDF',
    () => comparer('provisoire'),
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'parité exécutée EX8 — après la clôture de 2026 (écriture de solde écartée) : écran et PDF',
    () => comparer('definitif'),
    skip: sautSansPhp(),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test('parité exécutée EX8 — en-têtes, montants, « — » et date d arrêté = `ComparatifNMoinsUn` du web', () async {
    final libelles = serveur!['libelles'] as Map<String, dynamic>;
    expect([EtatsComparatifs.enteteN, EtatsComparatifs.enteteN1, EtatsComparatifs.sansExercice], [
      libelles['entete_n'],
      libelles['entete_n1'],
      libelles['sans_exercice'],
    ]);
    final echantillons = libelles['montants'] as List;
    for (final e in echantillons) {
      expect(EtatsComparatifs.montant(n((e as List)[0])), e[1], reason: 'montant(${e[0]})');
    }
    expect(EtatsComparatifs.sousTitre(null), libelles['sous_titre_absent']);
    expect(
      EtatsComparatifs.sousTitre(ColonneExercice(annee: 2027, arrete: DateTime(2027, 1, 31))),
      libelles['sous_titre'],
    );

    // `arreteDeLExercice` : exercice passé, en cours, à venir, absent — au 15/03/2027 après la clôture.
    final photo = serveur!['definitif'] as Map<String, dynamic>;
    final db = await basePoste(photo);
    addTearDown(db.close);
    final d = await ComptabiliteRepository(database: db).charger();
    final arretes = photo['arretes'] as Map<String, dynamic>;
    for (final annee in [2025, 2026, 2027, 2028]) {
      final a = EtatsComparatifs.arreteDeLExercice(d.exercices, annee, maintenants['definitif']!);
      expect(
        '${a.year}-${a.month.toString().padLeft(2, '0')}-${a.day.toString().padLeft(2, '0')}',
        arretes['$annee'],
        reason: '$annee',
      );
    }
  }, skip: sautSansPhp());

  // ── Littéraux calculés à la main (§ 5 seul) ───────────────────────────────────────────────────────────────────

  test('EX8 — § 5 à la main : Bilan 2027 / 2026, Compte de résultat 2026 = 200 000 malgré l écriture de solde', () async {
    for (final phase in ['provisoire', 'definitif']) {
      final photo = (serveur![phase] as Map<String, dynamic>)['exemple'] as Map<String, dynamic>;
      final db = await basePoste(photo);
      final d = await ComptabiliteRepository(database: db).charger();
      if (phase == 'definitif') {
        expect(d.journal.where((e) => e.ecriture.sourceType == 'closing'), hasLength(1));
      }
      final b = d.bilanComparatif(DateTime(2027, 1, 31));
      LigneComparee ligne(String rubrique, String code) =>
          b.lignes[rubrique]!.singleWhere((l) => l.code == code && !l.provisoire);
      expect([ligne('tresorerie', '531').n, ligne('tresorerie', '531').n1], [250000, 200000], reason: phase);
      expect([ligne('tresorerie', '521101').n, ligne('tresorerie', '521101').n1], [1000000, 1000000], reason: phase);
      expect([b.n.totalActif, b.n1!.totalActif], [1250000, 1200000], reason: phase);
      expect([b.n.resultat, b.n1!.resultat], [50000, 200000], reason: '$phase : le vrai résultat de 2026');
      expect([b.n.totalPassif, b.n1!.totalPassif], [1250000, 1200000], reason: phase);
      final r = d.compteResultatComparatif(DateTime(2027, 1, 31));
      expect([r.n1!.ventes, r.n1!.achats, r.n1!.margeCommerciale, r.n1!.resultatNet], [300000, 100000, 200000, 200000],
          reason: phase);
      expect([r.n.ventes, r.n.resultatNet], [50000, 50000], reason: phase);
      // Seul (sans comparatif), le Compte de résultat de 2026 lu au 31/12 : 200 000, même après l'étape 2.
      expect(EtatsComparatifs.compteResultat(d.soldesExercice, DateTime(2026, 12, 31)).resultatNet, 200000, reason: phase);

      // Sans exercice N-1 (2026 est le premier) : « — », jamais 0.
      final premier = d.bilanComparatif(DateTime(2026, 6, 30));
      expect(premier.exerciceN1, isNull);
      expect(premier.n1, isNull);
      for (final l in [...EtatsComparatifs.tableauActif(premier), ...EtatsComparatifs.tableauPassif(premier)]) {
        if (l.genre != GenreLigneEtat.titre) expect(l.n1, '—', reason: '$phase — ${l.libelle}');
      }
      for (final l in EtatsComparatifs.tableauResultat(d.compteResultatComparatif(DateTime(2026, 6, 30)))) {
        expect(l.n1, '—', reason: '$phase — ${l.libelle}');
      }
      await db.close();
    }
  }, skip: sautSansPhp());

  // ── L'écran du poste ──────────────────────────────────────────────────────────────────────────────────────────

  testWidgets('EX8 — l écran : carte « États Financiers » embarquée, Bilan et Compte de Résultat en deux colonnes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1700, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final photo = (serveur!['definitif'] as Map<String, dynamic>)['exemple'] as Map<String, dynamic>;
    final db = await basePoste(photo);
    final imprimes = <DocumentOfficiel>[];
    Future<void> afficher({int? exercice}) async {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(exercice),
          home: ComptabiliteScreen(
            depot: ComptabiliteRepository(database: db),
            maintenant: () => DateTime(2027, 3, 15, 12),
            exercice: exercice,
            imprimer: (doc, _) async {
              imprimes.add(doc);
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('carte-etatsFinanciers')));
      await tester.pumpAndSettle();
    }

    await afficher();
    expect(find.text('États Financiers'), findsWidgets);
    expect(find.text('Situation au 15/03/2027 — Exercice 2027'), findsOneWidget);
    expect(find.text('Bilan Équilibré'), findsOneWidget);
    expect(find.text('EXERCICE N'), findsNWidgets(2));
    expect(find.text('EXERCICE N-1'), findsNWidgets(2));
    expect(find.text('2026 — au 31/12/2026'), findsNWidgets(2));
    final actif = EtatsComparatifs.tableauActif(
      (await ComptabiliteRepository(database: db).charger()).bilanComparatif(DateTime(2027, 3, 15)),
    );
    final total = actif.length - 1;
    expect(tester.widget<Text>(find.byKey(Key('etat-actif-$total-n'))).data, '1 250 000 F');
    expect(tester.widget<Text>(find.byKey(Key('etat-actif-$total-n1'))).data, '1 200 000 F');

    await tester.tap(find.byKey(const Key('exporter-pdf-etats')));
    await tester.pumpAndSettle();
    expect(imprimes.single.titre, 'États Financiers — Bilan');
    expect(imprimes.single.entetes.last, 'Exercice N-1 (2026 — au 31/12/2026)');

    await tester.tap(find.byKey(const Key('onglet-etats-resultat')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('etat-resultat-10-n'))).data, '50 000 F');
    expect(tester.widget<Text>(find.byKey(const Key('etat-resultat-10-n1'))).data, '200 000 F');
    expect(find.text(EtatsComparatifs.noteResultat), findsOneWidget);

    await tester.tap(find.byKey(const Key('onglet-etats-tafire')));
    await tester.pumpAndSettle();
    expect(find.text(ComptabiliteScreen.motifsOngletsWeb['tafire']!), findsOneWidget);

    // L'exercice en paramètre : 2026 arrêté à sa clôture, pas d'exercice N-1 (« — »).
    await afficher(exercice: 2026);
    expect(find.text('Situation au 31/12/2026 — Exercice 2026'), findsOneWidget);
    expect(find.text('Aucun exercice antérieur'), findsNWidgets(2));
    expect(tester.widget<Text>(find.byKey(Key('etat-actif-$total-n'))).data, '1 200 000 F');
    expect(tester.widget<Text>(find.byKey(Key('etat-actif-$total-n1'))).data, '—');
    await tester.pumpWidget(const SizedBox());
    await db.close();
  }, skip: sautSansPhp() != null);

  testWidgets('fusion EX7 + EX8 — le sélecteur pilote les deux colonnes : écran du poste = composant web (parité exécutée)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1700, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final photo = serveur!['definitif'] as Map<String, dynamic>;
    final db = await basePoste(photo);
    final maintenant = maintenants['definitif']!;
    // Le socle du poste : le service de l'exercice affiché (mémorisé dans `app_settings`), sa portée, et le paramètre
    // d'EX8 que `main.dart` passe à l'écran (`exercice: _exercice.etat?.annee`), écran reconstruit au changement.
    final service = ExerciceChoisi(db, maintenant: () => maintenant);
    for (final rendu in (photo['selecteur'] as List).cast<Map<String, dynamic>>()) {
      final annee = rendu['annee'] as int;
      expect(await service.choisir(annee), isTrue);
      await tester.pumpWidget(
        PorteeExerciceChoisi(
          notifier: service,
          child: MaterialApp(
            key: ValueKey('exercice-${service.etat?.annee}'),
            home: ComptabiliteScreen(
              depot: ComptabiliteRepository(database: db),
              maintenant: () => maintenant,
              exercice: service.etat?.annee,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('carte-etatsFinanciers')));
      await tester.pumpAndSettle();
      final raison = 'exercice $annee choisi au sélecteur';
      expect(tester.widget<Text>(find.byKey(const Key('etat-situation'))).data, rendu['situation'], reason: raison);

      // Chaque montant AFFICHÉ (colonnes N et N-1) = la cellule rendue par le composant Livewire.
      void colonnes(String cle, List<List<String>> lignesWeb) {
        expect(lignesWeb.first.sublist(1), [
          '${EtatsComparatifs.enteteN}|${tester.widget<Text>(find.text(lignesWeb.first[1].split('|')[1]).first).data}',
          '${EtatsComparatifs.enteteN1}|${tester.widget<Text>(find.text(lignesWeb.first[2].split('|')[1]).first).data}',
        ], reason: '$raison — en-têtes $cle');
        var compares = 0;
        for (var i = 0; i < lignesWeb.length - 1; i++) {
          final web = lignesWeb[i + 1];
          if (web.length < 3) continue;   // titre de section
          expect(tester.widget<Text>(find.byKey(Key('$cle-$i-n'))).data, web[1], reason: '$raison — $cle ligne $i N');
          expect(tester.widget<Text>(find.byKey(Key('$cle-$i-n1'))).data, web[2], reason: '$raison — $cle ligne $i N-1');
          compares++;
        }
        expect(compares, greaterThan(3), reason: '$raison — $cle');
      }

      final bilan = (rendu['ecran_bilan'] as List).map(lignesDe).toList();
      colonnes('etat-actif', bilan[0]);
      colonnes('etat-passif', bilan[1]);
      if (annee == 2026) {
        expect(find.text('Aucun exercice antérieur'), findsNWidgets(2), reason: 'N-1 de 2026 : aucun');
        expect(tester.widget<Text>(find.byKey(Key('etat-actif-${bilan[0].length - 2}-n1'))).data, '—');
      } else {
        expect(find.text('2026 — au 31/12/2026'), findsNWidgets(2), reason: 'N-1 de 2027 : 2026 à sa clôture');
      }
      await tester.tap(find.byKey(const Key('onglet-etats-resultat')));
      await tester.pumpAndSettle();
      colonnes('etat-resultat', (rendu['ecran_resultat'] as List).map(lignesDe).single);
    }
    await tester.pumpWidget(const SizedBox());
    await db.close();
  }, skip: sautSansPhp() != null);

  testWidgets('EX8 — sans écriture reçue, les États Financiers le disent au lieu d afficher des zéros', (tester) async {
    tester.view.physicalSize = const Size(1700, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      MaterialApp(home: ComptabiliteScreen(depot: ComptabiliteRepository(database: db), maintenant: () => DateTime(2027, 3, 15))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('carte-etatsFinanciers')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucune écriture reçue au poste'), findsOneWidget);
    expect(find.byKey(const Key('etat-actif')), findsNothing);
  });

  // ── Garde-fou de fidélité des libellés ──────────────────────────────────────────────────────────────────────────

  test('EX8 — chaque libellé de l écran du poste est dans `etats-financiers.blade.php`', () {
    final fichier = File('$dossierLaravel/resources/views/livewire/comptabilite/etats-financiers.blade.php');
    if (!fichier.existsSync()) {
      markTestSkipped('SAUT : vue Blade absente');
      return;
    }
    final blade = fichier.readAsStringSync().replaceAll('&amp;', '&');
    final c = BilanComparatif(
      exerciceN: ColonneExercice(annee: 2027, arrete: DateTime(2027, 1, 31)),
      exerciceN1: null,
      n: _bilanVide(),
      n1: null,
      lignes: {for (final r in BilanEtat.rubriques) r: const []},
    );
    final libelles = {
      'États Financiers',
      'Bilan, Compte de Résultat, Tableau des Flux de Trésorerie et Notes Annexes — conformité SYSCOHADA.',
      'Exporter PDF (Onglet Actif)',
      for (final (_, l) in ComptabiliteScreen.ongletsEtats) l,
      'Actif (Emplois)',
      'Passif (Ressources)',
      'Compte de Résultat — Structure en Cascade SYSCOHADA',
      'Bilan Équilibré',
      EtatsComparatifs.noteResultat,
      for (final l in [...EtatsComparatifs.tableauActif(c), ...EtatsComparatifs.tableauPassif(c)]) l.libelle,
      for (final l in EtatsComparatifs.tableauResultat(
        CompteResultatComparatif(exerciceN: c.exerciceN, exerciceN1: null, n: _resultatVide(), n1: null),
      ))
        l.libelle,
    };
    for (final l in libelles) {
      expect(blade, contains(l), reason: 'libellé du poste absent du Blade : $l');
    }
    // Et le gabarit PDF du web porte les libellés du document du poste.
    final pdf = File('$dossierLaravel/resources/views/exports/etats-financiers.blade.php').readAsStringSync().replaceAll('&amp;', '&');
    for (final l in [
      for (final ligne in EtatsComparatifs.documentBilan(c, situation: '').lignes)
        if (ligne is BandeDocument) ligne.libelle else if (ligne is TotalDocument) ligne.cellules.first,
      for (final (libelle, _, _, _) in EtatsComparatifs.cascadePdf) libelle,
    ]) {
      expect(pdf, contains(l), reason: 'libellé du PDF du poste absent du gabarit web : $l');
    }
  });
}

BilanEtat _bilanVide() => BilanEtat(
  immo: const [],
  stocks: const [],
  creances: const [],
  tresorerie: const [],
  capitaux: const [],
  dettes: const [],
  totalImmo: 0,
  totalCirculant: 0,
  totalTresorerie: 0,
  totalActif: 0,
  totalCapitaux: 0,
  resultat: 0,
  totalDettes: 0,
  totalPassif: 0,
  ouverture: const OuvertureExercice(annee: 2027, mode: 'anouveau', precedent: null, comptes: {}, resultatProvisoire: null),
);

CompteResultatEtat _resultatVide() => const CompteResultatEtat(
  ventes: 0,
  achats: 0,
  margeCommerciale: 0,
  chargesPersonnel: 0,
  ebe: 0,
  dotations: 0,
  resultatExploitation: 0,
  resultatFinancier: 0,
  rao: 0,
  autresCharges: 0,
  resultatNet: 0,
);

/// Construit l'exemple du § 5 (et, à part, le jeu complet) dans Laravel (SQLite en mémoire) par
/// `AccountingEntryService::record()` ; rend comparatifs, écran et PDF AVANT puis APRÈS la clôture de 2026 par le vrai
/// assistant (étapes 1, 2, 3 le 15/03/2027).
const _script = r'''
$entree = json_decode(file_get_contents($argv[1]), true);
use App\Models\{AccountingEntry, ChartOfAccount, FiscalYear, User};
use App\Services\{AccountingEntryService, FinancialReportService, PdfExportService};
use App\Support\ComparatifNMoinsUn;
use App\Livewire\Comptabilite\EtatsFinanciers;
use Illuminate\Support\Facades\Artisan;
use Livewire\Livewire;

Artisan::call('db:seed', ['--class' => Database\Seeders\RolesAndPermissionsSeeder::class, '--force' => true]);
$comptable = User::create(['name' => 'Comptable', 'username' => 'compta', 'email' => 'compta@fermeolouwachegoun.com',
    'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
$comptable->assignRole('comptable');
Illuminate\Support\Facades\Auth::login($comptable);

class EspionPdf extends PdfExportService {
    public array $rendus = [];
    public function render(string $view, array $data, string $title, string $period, string $orientation = 'landscape'): Barryvdh\DomPDF\PDF {
        $this->rendus[] = ['html' => view($view, $data)->render(), 'titre' => $title, 'periode' => $period];
        return parent::render($view, $data, $title, $period, $orientation);
    }
}

function construire(array $ecritures, bool $dotation): void {
    foreach (AccountingEntry::all() as $e) { $e->lines()->delete(); $e->delete(); }
    ChartOfAccount::query()->delete();
    FiscalYear::query()->delete();
    Carbon\Carbon::setTestNow('2027-02-20 09:00:00');
    FiscalYear::create(['year' => 2026, 'start_date' => '2026-01-01', 'end_date' => '2026-12-31', 'status' => 'ouvert']);
    FiscalYear::create(['year' => 2027, 'start_date' => '2027-01-01', 'end_date' => '2027-12-31', 'status' => 'ouvert']);
    $plan = [];
    foreach ([['101', 'Capital social', 1], ['131', 'Résultat net : bénéfice', 1], ['139', 'Résultat net : perte', 1],
              ['2841', 'Amortissements du matériel', 2], ['401', 'Fournisseurs', 4], ['411', 'Clients', 4],
              ['521101', 'Banque principale', 5], ['531', 'Caisse', 5], ['601', 'Achats', 6],
              ['605', 'Autres achats (énergie)', 6], ['661', 'Rémunérations', 6], ['681', 'Dotations aux amortissements', 6],
              ['701', 'Ventes de produits', 7], ['771', 'Intérêts de prêts', 7]] as [$code, $libelle, $classe]) {
        $plan[$code] = ChartOfAccount::create(['code' => $code, 'label' => $libelle, 'class' => $classe, 'is_active' => true])->id;
    }
    $ecrire = function (string $date, string $d, string $c, float $m, string $libelle) use ($plan) {
        app(AccountingEntryService::class)->record(
            lines: [['account_id' => $plan[$d], 'debit' => $m, 'credit' => 0], ['account_id' => $plan[$c], 'debit' => 0, 'credit' => $m]],
            entryDate: $date, reference: 'OD-'.$date.' — '.$libelle, sourceType: 'manual');
    };
    foreach ($ecritures as $i => $e) {
        Carbon\Carbon::setTestNow(Carbon\Carbon::parse('2027-02-20 09:00:00')->addSeconds($i));
        $ecrire($e['date'], $e['debit'], $e['credit'], (float) $e['montant'], $e['libelle']);
    }
    if ($dotation) {
        Carbon\Carbon::setTestNow('2027-02-20 10:00:00');
        $ecrire('2026-12-31', '681', '2841', 30000, 'Dotation 2026');
    }
}

function journal(): array {
    return [
        'exercices' => FiscalYear::orderBy('year')->get()->map(fn ($f) => ['id' => $f->id, 'year' => (int) $f->year,
            'start_date' => $f->start_date->format('Y-m-d'), 'end_date' => $f->end_date->format('Y-m-d'), 'status' => $f->status])->all(),
        'plan' => ChartOfAccount::orderBy('code')->get()->map(fn ($c) => ['id' => $c->id, 'code' => $c->code, 'label' => $c->label, 'class' => (int) $c->class])->all(),
        'journal' => AccountingEntry::with('lines')->where('is_active', true)->get()->map(fn ($e) => [
            'id' => $e->id, 'fiscal_year_id' => $e->fiscal_year_id, 'entry_date' => $e->entry_date->format('Y-m-d'),
            'reference' => $e->reference, 'source_type' => $e->source_type, 'is_locked' => (bool) $e->is_locked,
            'created_at' => $e->created_at->toIso8601String(),
            'lines' => $e->lines->map(fn ($l) => ['id' => $l->id, 'account_id' => $l->account_id, 'debit' => (float) $l->debit, 'credit' => (float) $l->credit])->all(),
        ])->all(),
    ];
}

/** Lignes des tableaux d'un HTML : cellules `td` (texte), `th` (texte direct | texte des enfants). */
function tableaux(string $html, string $chemin = '//table'): array {
    $doc = new DOMDocument();
    @$doc->loadHTML('<?xml encoding="utf-8"?>'.$html);
    $x = new DOMXPath($doc);
    $norme = fn (string $t) => trim(preg_replace('/\s+/u', ' ', $t));
    $tables = [];
    foreach ($x->query($chemin) as $table) {
        $lignes = [];
        foreach ($x->query('.//tr', $table) as $tr) {
            $cellules = [];
            foreach ($tr->childNodes as $cellule) {
                if (! in_array($cellule->nodeName, ['td', 'th'], true)) {
                    continue;
                }
                if ($cellule->nodeName === 'th' && $x->query('./span', $cellule)->length > 0) {
                    $morceaux = [];
                    foreach ($cellule->childNodes as $enfant) {
                        $t = $norme($enfant->textContent);
                        if ($t !== '') {
                            $morceaux[] = $t;
                        }
                    }
                    $cellules[] = implode('|', $morceaux);
                } else {
                    $cellules[] = $norme($cellule->textContent);
                }
            }
            $lignes[] = $cellules;
        }
        $tables[] = $lignes;
    }
    return $tables;
}

function photo(array $entree, string $maintenant): array {
    $p = journal();
    $s = new FinancialReportService();
    $p['comparatifs'] = [];
    foreach ($entree['dates'] as $date) {
        $p['comparatifs'][$date] = [
            'bilan' => (new FinancialReportService())->bilanComparatif($date),
            'resultat' => (new FinancialReportService())->compteResultatComparatif($date),
        ];
    }
    Carbon\Carbon::setTestNow($maintenant);
    $p['rendus'] = [];
    foreach ([null, 2026, 2027] as $exercice) {
        $parametres = $exercice === null ? [] : ['exercice' => $exercice];
        if ($exercice === null) {
            session()->forget(\App\Support\ExerciceChoisi::CLE_SESSION);   // fusion EX7 + EX8 : sans choix en session
        }
        $ecran = Livewire::test(EtatsFinanciers::class, $parametres);
        $situation = $ecran->instance()->situationLabel;
        $bilan = tableaux($ecran->html());
        $resultat = tableaux($ecran->call('switchTab', 'resultat')->html());
        $espion = new EspionPdf();
        app()->instance(PdfExportService::class, $espion);
        Livewire::test(EtatsFinanciers::class, $parametres)->call('exportEtatActifPdf')->call('switchTab', 'resultat')->call('exportEtatActifPdf');
        $pdf = [];
        foreach ($espion->rendus as $i => $r) {
            $lignes = tableaux($r['html'], "//table[contains(@class, 'data-table')]")[0];
            $pdf[] = ['titre' => $r['titre'], 'periode' => $r['periode'], 'lignes' => $lignes,
                'fichier' => 'etats-financiers-'.($i === 0 ? 'bilan' : 'resultat').'-'.now()->format('Y-m-d').'.pdf'];
        }
        app()->forgetInstance(PdfExportService::class);
        $p['rendus'][] = ['exercice' => $exercice, 'situation' => $situation, 'ecran_bilan' => $bilan, 'ecran_resultat' => $resultat, 'pdf' => $pdf];
    }
    // Fusion EX7 + EX8 : l'exercice choisi AU SÉLECTEUR de la barre (session), sans paramètre — les deux colonnes
    // suivent (N = l'exercice choisi, N-1 = son précédent à sa clôture).
    $p['selecteur'] = [];
    foreach ([2026, 2027] as $annee) {
        Livewire::test(App\Livewire\Shared\SelecteurExercice::class)->call('choisir', $annee);
        $ecran = Livewire::test(EtatsFinanciers::class);
        $p['selecteur'][] = ['annee' => $annee, 'situation' => $ecran->instance()->situationLabel,
            'ecran_bilan' => tableaux($ecran->html()), 'ecran_resultat' => tableaux($ecran->call('switchTab', 'resultat')->html())];
    }
    session()->forget(App\Support\ExerciceChoisi::CLE_SESSION);
    $p['arretes'] = [];
    foreach ([2025, 2026, 2027, 2028] as $annee) {
        $p['arretes'][(string) $annee] = $s->arreteDeLExercice($annee);
    }
    return $p;
}

function cloturer2026(): void {
    Carbon\Carbon::setTestNow('2027-03-15 10:00:00');
    $c = Livewire::test(App\Livewire\Comptabilite\ClotureExercice::class)
        ->set('selectedYear', '2026')->call('confirmStep1')->call('soldeComptesGestion');
    $etape2 = json_encode($c->effects['dispatches'] ?? null, JSON_UNESCAPED_UNICODE);
    $c->call('confirmCloture');
    if (FiscalYear::where('year', 2026)->value('status') !== 'cloture') {
        fwrite(STDERR, 'La clôture de 2026 n a pas abouti : '.$c->instance()->motifRefusCloture(FiscalYear::where('year', 2026)->first()).' '.$etape2);
        exit(4);
    }
}

$sortie = [];
construire(array_slice($entree['ecritures'], 0, 4), false);
$exempleAvant = journal();
cloturer2026();
$exempleApres = journal();

construire($entree['ecritures'], true);
$sortie['provisoire'] = photo($entree, '2027-02-20 12:00:00') + ['exemple' => $exempleAvant];
cloturer2026();
$sortie['definitif'] = photo($entree, '2027-03-15 12:00:00') + ['exemple' => $exempleApres];

$sortie['libelles'] = [
    'entete_n' => ComparatifNMoinsUn::ENTETE_N,
    'entete_n1' => ComparatifNMoinsUn::ENTETE_N1,
    'sans_exercice' => ComparatifNMoinsUn::SANS_EXERCICE,
    'montants' => array_map(fn ($v) => [$v, ComparatifNMoinsUn::montant($v)], [null, 0.0, -0.0, -0.4, 0.5, -0.5, 1234567.5, -1500.49, 999.5, 1000000000.0]),
    'sous_titre_absent' => ComparatifNMoinsUn::sousTitre(null),
    'sous_titre' => ComparatifNMoinsUn::sousTitre(['annee' => 2027, 'arrete' => '2027-01-31']),
];
echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION);
''';
