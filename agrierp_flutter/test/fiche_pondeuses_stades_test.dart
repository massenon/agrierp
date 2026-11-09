import 'dart:io';
import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/core/sync/sync_engine.dart';
import 'package:agrierp/features/elevage/effectif_par_categorie.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_pondeuses_screen.dart';
import 'package:agrierp/features/elevage/production_oeufs_service.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/elevage/stade_pondeuse.dart';
import 'package:agrierp/features/elevage/transferts_repository.dart';
import 'package:agrierp/features/stocks/produits_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'php_laravel.dart';

/// Ticket VOL-2 (décision client du 05/11/2026) — EFFECTIF PAR STADE CALCULÉ POUR LES VOLAILLES PONDEUSES, transposition au
/// poste de `EffectifParCategorieService` (volailles_ponte), `StadePondeuse` et de la fiche Pondeuses.
///
/// Trois preuves : (1) des JEUX CALCULÉS À LA MAIN (littéraux, jamais produits par le code testé) ; (2) la PARITÉ EXÉCUTÉE
/// avec le vrai PHP du dépôt Laravel ; (3) le dépôt (départ obligatoire, passages, ventes de la caisse rangées par stade,
/// refus aux motifs du web) et l'écran.
///
/// Bande de 100 : départ Poussin ponte 10 / Poussin en croissance 20 / Poulette 30 / Pondeuse 40, rations 30 / 60 / 80 / 110.
///   J1 (05/10) achat 2 (→ Poulette), éclosions 6 (→ Poussin ponte), morts PP1 PC2 PL3 PO4, passages 4 / 5 / 6
///              → PP11 PC17 PL28 PO42   total 98   provende 8 210 g
///   J2 (06/10) ventes PP1 PL2 PO3 (caisse), don PC2, mort PO1, passage 3
///              → PP7 PC18 PL26 PO38     total 89   provende 7 550 g
///   J3 (07/10) vente de 30 poulettes → PL0, total 59, somme 63 ≠ 59
void main() {
  const ponte = EffectifParCategorie.volaillesPonte;

  EffectifCategories e(int? po, int? pc, int? pl, int? pp) =>
      EffectifCategories(repro: po, sevre: pc, jeune: pl, quatre: pp);

  /// [PP, PC, PL, PO] d'un résultat.
  List<int?> stades(EffectifCategoriesJour r) => [r.quatre, r.sevre, r.jeune, r.repro];

  group('jeux calculés à la main — volailles pondeuses', () {
    test('l achat entre dans Poulette, l éclosion dans Poussin ponte', () {
      expect(stades(EffectifParCategorie.calculerJour(ponte, e(0, 0, 10, 0), const MouvementsJour(achat: 4))), [0, 0, 14, 0]);
      expect(stades(EffectifParCategorie.calculerJour(ponte, e(1, 2, 3, 10), const MouvementsJour(ne: 6))), [16, 2, 3, 1]);
    });

    test('trois passages enchaînent les stades, total inchangé', () {
      final r = EffectifParCategorie.calculerJour(
        ponte,
        e(0, 0, 0, 10),
        const MouvementsJour(passage4Sevre: 4, passage: 3, passageJeuneRepro: 2),
      );
      // PP 10−4 = 6 · PC 0+4−3 = 1 · PL 0+3−2 = 1 · PO 2.
      expect(stades(r), [6, 1, 1, 2]);
      expect(r.somme, 10);
      expect(r.refus, isNull);
      expect(r.passagesAppliques, {'passage_4_sevre': 4, 'passage_sevre_jeune': 3, 'passage_jeune_repro': 2});
    });

    test('chaque stade est borné à 0', () {
      final r = EffectifParCategorie.calculerJour(
        ponte,
        e(3, 2, 1, 0),
        const MouvementsJour(venteRepro: 5, mortSevre: 9, donJeune: 4, mort4: 7),
      );
      expect(stades(r), [0, 0, 0, 0]);
    });

    test('un passage supérieur à son stade source est refusé et ramené à la source ; le passage entrant compte', () {
      final r = EffectifParCategorie.calculerJour(ponte, e(0, 0, 0, 10), const MouvementsJour(passage4Sevre: 11));
      expect(
        r.refus,
        "Passage de stade refusé (Poussin ponte (0 à 2 mois) vers Poussin en croissance (2 à 4 mois)) : 11 sujet(s) à faire passer, mais le stade source n'en compte que 10.",
      );
      expect(stades(r), [0, 10, 0, 0]);

      final ok = EffectifParCategorie.calculerJour(ponte, e(0, 0, 0, 5), const MouvementsJour(passage4Sevre: 5, passage: 5));
      expect(ok.refus, isNull);
      expect(stades(ok), [0, 0, 5, 0]);
      final ko = EffectifParCategorie.calculerJour(ponte, e(0, 0, 0, 5), const MouvementsJour(passage4Sevre: 5, passage: 6));
      expect(
        ko.refus,
        contains("(Poussin en croissance (2 à 4 mois) vers Poulette (4 à 5.5 mois)) : 6 sujet(s) à faire passer, mais le stade source n'en compte que 5."),
      );
    });

    test('jamais de stade inconnu : un mouvement ou une veille absents valent 0', () {
      final r = EffectifParCategorie.calculerJour(ponte, const EffectifCategories(), const MouvementsJour());
      expect(stades(r), [0, 0, 0, 0]);
    });

    test('un départ différent de la somme, ou incomplet, est refusé', () {
      expect(
        EffectifParCategorie.verifierDepart(e(40, 20, 30, 9), 100, quatreStades: true),
        "La somme des stades de départ (99) ne correspond pas à l'effectif total au début du jour de départ (100).",
      );
      expect(
        EffectifParCategorie.verifierDepart(e(40, 20, 30, null), 100, quatreStades: true),
        'Effectif de départ incomplet : les quatre stades doivent être renseignés (0 si le stade est vide).',
      );
      expect(EffectifParCategorie.verifierDepart(e(40, 20, 30, 10), 100, quatreStades: true), isNull);
    });

    test('les deux familles de volailles sont distinctes', () {
      expect(EffectifParCategorie.especeDuCode('aviculture', stade: 'ponte'), ponte);
      expect(EffectifParCategorie.especeDuCode('aviculture', stade: 'reproduction'), EffectifParCategorie.volaillesRepro);
      expect(EffectifParCategorie.emplacementsDe(ponte), ['repro', 'sevre', 'jeune', 'quatre']);
      expect(EffectifParCategorie.emplacementsDe(EffectifParCategorie.volaillesRepro), ['repro', 'sevre', 'jeune']);
      expect(EffectifParCategorie.colonne('vente', 'quatre'), 'vente_4');
    });

    test('libellés = ceux du barème, emplacements génériques, clés exactes', () {
      expect(StadePondeuse.libelles.values.toList(), [
        'Poussin ponte (0 à 2 mois)',
        'Poussin en croissance (2 à 4 mois)',
        'Poulette (4 à 5.5 mois)',
        'Pondeuse (6 à 18 mois)',
      ]);
      expect(StadePondeuse.emplacements, {
        'pondeuse': 'repro',
        'poulette': 'jeune',
        'poussin_croissance': 'sevre',
        'poussin_ponte': 'quatre',
      });
      expect(StadePondeuse.cleDuLibelle('Poussin'), isNull);
      expect(StadePondeuse.cleDuLibelle('Reproducteur'), isNull);
    });

    test('produits par défaut d après le nom', () {
      expect(StadePondeuse.devinerDepuisLeNom('Poulette (sujet vif)'), 'poulette');
      expect(StadePondeuse.devinerDepuisLeNom('Poule de réforme'), 'pondeuse');
      expect(StadePondeuse.devinerDepuisLeNom("Poussin d'un jour ponte"), 'poussin_ponte');
      expect(StadePondeuse.devinerDepuisLeNom("Poussin d'un jour"), isNull);
      expect(StadePondeuse.devinerDepuisLeNom('Aliment croissance (poulette) 25kg'), isNull);
    });

    test('proposition du stade : tout l effectif en Pondeuse, les trois autres stades à 0', () {
      expect(
        EffectifParCategorie.departDepuisStade(codeEspece: 'aviculture', stade: 'ponte', totalDebutJour: 100),
        e(100, 0, 0, 0),
      );
    });
  });

  final saut = sautSansPhp();

  group('⚠️⚠️ parité EXÉCUTÉE avec le vrai PHP du serveur', () {
    test('calculerJour(volailles_ponte) : grille de 600 combinaisons, départ et refus compris', () {
      final hasard = Random(2005);
      int? n(int max, {double nul = 0.08}) => hasard.nextDouble() < nul ? null : hasard.nextInt(max + 1);

      final jours = <List<Object?>>[];
      for (var i = 0; i < 600; i++) {
        jours.add([
          {'repro': n(40), 'sevre': n(40), 'jeune': n(40), 'quatre': n(40)},
          {
            'achat': n(9),
            'ne': n(9),
            'vente_repro': n(8),
            'vente_sevre': n(30),
            'vente_jeune': n(12),
            'vente_4': n(12),
            'mort_repro': n(8),
            'mort_sevre': n(12),
            'mort_jeune': n(8),
            'mort_4': n(8),
            'don_repro': n(4),
            'don_sevre': n(5),
            'don_jeune': n(4),
            'don_4': n(4),
            'passage_4_sevre': n(45),
            'passage': n(45),
            'passage_jeune_repro': n(45),
            'transfert_entree_repro': hasard.nextInt(3),
            'transfert_sortie_sevre': hasard.nextInt(3),
            'transfert_entree_4': hasard.nextInt(3),
            'transfert_sortie_4': hasard.nextInt(3),
          },
          hasard.nextInt(4) == 0 ? null : hasard.nextInt(160),
        ]);
      }

      final sortie = executerPhp(
        r'''<?php
require 'vendor/autoload.php';
$e = json_decode(file_get_contents($argv[1]), true);
$s = [];
foreach ($e as $c) {
    $r = App\Services\EffectifParCategorieService::calculerJour('volailles_ponte', $c[0], $c[1], $c[2]);
    $s[] = [$r->quatre, $r->sevre, $r->jeune, $r->repro, $r->sommeDifferente, $r->refus, $r->passageApplique, $r->passagesAppliques];
}
echo json_encode($s);
''',
        jours,
      ) as List;

      var refus = 0;
      for (var i = 0; i < jours.length; i++) {
        final v = jours[i][0] as Map<String, int?>;
        final m = jours[i][1] as Map<String, int?>;
        final r = EffectifParCategorie.calculerJour(
          ponte,
          e(v['repro'], v['sevre'], v['jeune'], v['quatre']),
          MouvementsJour(
            achat: m['achat'],
            ne: m['ne'],
            venteRepro: m['vente_repro'],
            venteSevre: m['vente_sevre'],
            venteJeune: m['vente_jeune'],
            vente4: m['vente_4'],
            mortRepro: m['mort_repro'],
            mortSevre: m['mort_sevre'],
            mortJeune: m['mort_jeune'],
            mort4: m['mort_4'],
            donRepro: m['don_repro'],
            donSevre: m['don_sevre'],
            donJeune: m['don_jeune'],
            don4: m['don_4'],
            passage4Sevre: m['passage_4_sevre'],
            passage: m['passage'],
            passageJeuneRepro: m['passage_jeune_repro'],
            transfertEntreeRepro: m['transfert_entree_repro']!,
            transfertSortieSevre: m['transfert_sortie_sevre']!,
            transfertEntree4: m['transfert_entree_4']!,
            transfertSortie4: m['transfert_sortie_4']!,
          ),
          totalFinal: jours[i][2] as int?,
        );
        expect(
          [...stades(r), r.sommeDifferente, r.refus, r.passageApplique, r.passagesAppliques],
          sortie[i],
          reason: 'combinaison #$i : ${jours[i]}',
        );
        if (r.refus != null) refus++;
      }
      expect(refus, greaterThan(40), reason: 'la grille exerce le refus de passage');
    }, skip: saut);

    test('verifierDepart à quatre stades : mêmes motifs que le PHP', () {
      final hasard = Random(11);
      final cas = <List<Object?>>[
        for (var i = 0; i < 120; i++)
          [
            {
              'repro': hasard.nextInt(9) == 0 ? null : hasard.nextInt(40),
              'sevre': hasard.nextInt(9) == 0 ? null : hasard.nextInt(40),
              'jeune': hasard.nextInt(9) == 0 ? null : hasard.nextInt(40),
              'quatre': hasard.nextInt(9) == 0 ? null : hasard.nextInt(40),
            },
            hasard.nextInt(7) == 0 ? null : 40 + hasard.nextInt(80),
          ],
      ];
      final sortie = executerPhp(
        r'''<?php
require 'vendor/autoload.php';
$e = json_decode(file_get_contents($argv[1]), true);
echo json_encode(array_map(fn ($c) => App\Services\EffectifParCategorieService::verifierDepart($c[0], $c[1]), $e));
''',
        cas,
      ) as List;
      var valides = 0;
      for (var i = 0; i < cas.length; i++) {
        final d = cas[i][0] as Map<String, int?>;
        final r = EffectifParCategorie.verifierDepart(
          e(d['repro'], d['sevre'], d['jeune'], d['quatre']),
          cas[i][1] as int?,
          quatreStades: true,
        );
        expect(r, sortie[i], reason: 'cas #$i : $cas[i]');
        if (r == null) valides++;
      }
      expect(valides, greaterThanOrEqualTo(0));
    }, skip: saut);

    test('stade par défaut d un produit et clé de ration : mêmes réponses que le PHP', () {
      final noms = [
        "Poussin d'un jour", "Poussin d'un jour ponte", 'Poulette (sujet vif)', 'Poule pondeuse', 'Poule de réforme',
        'Poussin en croissance', 'Œufs de table (plateau)', 'Aliment croissance (poulette) 25kg', 'Poulet goliath', '',
        'POULETTE', 'Poussin ponte', 'Médicament poulette', 'Pondeuse réformée',
      ];
      final libelles = [
        'Poussin ponte (0 à 2 mois)', 'poussin en croissance', ' Poulette (4 à 5.5 mois) ', 'Pondeuse (6 à 18 mois)', 'Poussin',
        'Jeune', 'Reproducteur', 'Pondeuse réformée', 'PONDEUSE', 'Poulettes',
      ];
      final sortie = executerPhp(
        r'''<?php
require 'vendor/autoload.php';
$e = json_decode(file_get_contents($argv[1]), true);
echo json_encode([
    array_map(fn ($n) => App\Support\StadePondeuse::devinerDepuisLeNom($n), $e['noms']),
    array_map(fn ($l) => App\Support\StadePondeuse::cleDuLibelle($l), $e['libelles']),
]);
''',
        {'noms': noms, 'libelles': libelles},
      ) as List;
      expect([for (final n in noms) StadePondeuse.devinerDepuisLeNom(n)], sortie[0]);
      expect([for (final l in libelles) StadePondeuse.cleDuLibelle(l)], sortie[1]);
    }, skip: saut);
  });

  // ═══════════════════════════════════════════════════════════════════ dépôt, caisse, produit

  group('dépôt, caisse et produit', () {
    late AppDatabase db;
    late FicheJournaliereRepository depot;
    late CaisseRepository caisse;
    const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
    const especeId = 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee';
    final jour1 = DateTime(2026, 10, 5);
    final jour2 = DateTime(2026, 10, 6);
    final jour3 = DateTime(2026, 10, 7);
    late Product pp;
    late Product pl;
    late Product po;
    late Product sans;
    late Product reproducteur;

    Future<Product> produit(String id, String nom, String? categorie) async {
      await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: id.padRight(36, '0'),
          sku: id,
          name: nom,
          speciesId: const Value(especeId),
          unit: 'u',
          pricingMode: 'fourchette',
          stockQty: const Value(500),
          categorieEffectif: Value(categorie),
        ),
      );
      return (db.select(db.products)..where((t) => t.sku.equals(id))).getSingle();
    }

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
      caisse = CaisseRepository(database: db, deviceId: 'poste-test', maintenant: () => DateTime(2026, 10, 14, 12));
      await db.into(db.livestockSpecies).insert(
        LivestockSpeciesCompanion.insert(id: especeId, code: 'aviculture', label: 'Aviculture'),
      );
      await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          id: 'ffffffff-2026-4000-8000-000000000001',
          year: 2026,
          startDate: Value(DateTime(2026)),
          endDate: Value(DateTime(2026, 12, 31)),
          status: const Value('ouvert'),
        ),
      );
      await db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: bandeId,
          code: 'AVI-PON-01',
          speciesId: especeId,
          speciesCode: const Value('aviculture'),
          stage: const Value('ponte'),
          createdDate: Value(DateTime(2026, 9, 1)),
          initialQuantity: const Value(100),
          currentQuantity: const Value(100),
        ),
      );
      pp = await produit('AVIPP', "Poussin d'un jour (ponte)", 'poussin_ponte');
      pl = await produit('AVIPL', 'Poulette (sujet vif)', 'poulette');
      po = await produit('AVIPO', 'Poule de réforme', 'pondeuse');
      sans = await produit('AVISANS', 'Poulet braisé', null);
      reproducteur = await produit('AVIREPRO', 'Coq reproducteur', 'reproducteur');
    });

    tearDown(() async => db.close());

    VentilationJour jourVentile({
      int mPP = 0, int mPC = 0, int mPL = 0, int mPO = 0,
      int dPP = 0, int dPC = 0, int dPL = 0, int dPO = 0,
      int p1 = 0, int p2 = 0, int p3 = 0,
      EffectifCategories? depart,
    }) => VentilationJour(
      mortRepro: mPO, mortSevre: mPC, mortJeune: mPL, mort4: mPP,
      donRepro: dPO, donSevre: dPC, donJeune: dPL, don4: dPP,
      passage4Sevre: p1, passage: p2, passageJeuneRepro: p3, departSaisi: depart,
    );

    Future<void> enregistrer(DateTime jour, {int achat = 0, int ne = 0, VentilationJour? v}) async {
      final vv = v ?? jourVentile();
      await depot.enregistrer(
        lotId: bandeId, jour: jour, achat: achat, ne: ne, mort: vv.totalMorts, don: vv.totalDons, ventilation: vv,
      );
    }

    Future<LivestockDailyEntry> fiche(DateTime jour) async => (await depot.chargerJour(bandeId, jour))!;

    /// [PP, PC, PL, PO] STOCKÉS.
    List<int?> stocke(LivestockDailyEntry f) => [f.catEff4, f.catEffSevre, f.catEffJeune, f.catEffRepro];

    LignePanier ligne(Product p, int q) => LignePanier(produit: p, quantite: q, montant: 1000.0 * q, lotId: bandeId);

    Future<void> vendre(Product p, int q, DateTime jour) =>
        caisse.enregistrerVente(panier: [ligne(p, q)], modePaiement: 'especes', dateVente: jour);

    Future<void> scenario() async {
      await enregistrer(
        jour1, achat: 2, ne: 6,
        v: jourVentile(mPP: 1, mPC: 2, mPL: 3, mPO: 4, p1: 4, p2: 5, p3: 6, depart: e(40, 20, 30, 10)),
      );
      await vendre(pp, 1, jour2);
      await vendre(pl, 2, jour2);
      await vendre(po, 3, jour2);
      await enregistrer(jour2, v: jourVentile(dPC: 2, mPO: 1, p1: 3));
      await vendre(pl, 30, jour3);
      await enregistrer(jour3);
    }

    test('enregistrement : départ, mouvements ventilés, passages et stades calculés', () async {
      await enregistrer(
        jour1, achat: 2, ne: 6,
        v: jourVentile(mPP: 1, mPC: 2, mPL: 3, mPO: 4, p1: 4, p2: 5, p3: 6, depart: e(40, 20, 30, 10)),
      );

      final f = await fiche(jour1);
      expect([f.catDepartRepro, f.catDepartSevre, f.catDepartJeune, f.catDepart4], [40, 20, 30, 10]);
      expect([f.mortRepro, f.mortSevre, f.mortJeune, f.mort4, f.mort], [4, 2, 3, 1, 10]);
      expect([f.passage4Sevre, f.passageSevreJeune, f.passageJeuneRepro], [4, 5, 6]);
      expect([f.venteRepro, f.venteSevre, f.venteJeune, f.vente4], [0, 0, 0, 0], reason: 'ventes connues à zéro, jamais null');
      expect(f.effectifFinal, 98);
      expect(stocke(f), [11, 17, 28, 42]);
    });

    test('jours suivants : ventes de la caisse par stade, passage, bornes à 0', () async {
      await scenario();

      final f2 = await fiche(jour2);
      expect([f2.vente4, f2.venteJeune, f2.venteRepro, f2.venteSevre, f2.vente], [1, 2, 3, 0, 6]);
      expect(stocke(f2), [7, 18, 26, 38]);
      expect(f2.effectifFinal, 89);
      final f3 = await fiche(jour3);
      expect(stocke(f3), [7, 18, 0, 38]);
      expect(f3.effectifFinal, 59);
      final bande = await (db.select(db.livestockLots)..where((t) => t.id.equals(bandeId))).getSingle();
      expect(bande.currentQuantity, 59);
    });

    test('⚠️ SANS DÉPART : la journée est refusée, avec le motif du web', () async {
      await expectLater(
        enregistrer(jour1, achat: 3),
        throwsA(
          isA<FicheRefusee>().having(
            (x) => x.motif,
            'motif',
            "Saisissez d'abord l'effectif de départ de la bande par stade (Poussin ponte, Poussin en croissance, Poulette, Pondeuse) : la journée ne peut pas être enregistrée sans lui.",
          ),
        ),
      );
      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
    });

    test('départ incohérent refusé ; jour antérieur au départ non saisissable ; passage > source refusé', () async {
      await expectLater(
        enregistrer(jour1, v: jourVentile(depart: e(40, 20, 30, 9))),
        throwsA(isA<FicheRefusee>().having((x) => x.motif, 'motif', contains('(99)'))),
      );
      await expectLater(
        enregistrer(jour1, v: jourVentile(p1: 11, depart: e(40, 20, 30, 10))),
        throwsA(isA<FicheRefusee>().having((x) => x.motif, 'motif', contains("le stade source n'en compte que 10"))),
      );
      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
      await enregistrer(jour2, v: jourVentile(depart: e(40, 20, 30, 10)));
      await expectLater(
        enregistrer(jour1),
        throwsA(
          isA<FicheRefusee>().having(
            (x) => x.motif,
            'motif',
            "Jour antérieur à l'effectif de départ fixé le 06/10/2026 : il n'est pas saisissable.",
          ),
        ),
      );
    });

    test('corriger un jour passé recalcule les jours suivants', () async {
      await scenario();
      await enregistrer(
        jour1, achat: 2, ne: 6,
        v: jourVentile(mPP: 1, mPC: 2, mPL: 3, mPO: 8, p1: 4, p2: 5, p3: 6),
      );

      expect(stocke(await fiche(jour1)), [11, 17, 28, 38]);
      expect(stocke(await fiche(jour2)), [7, 18, 26, 34]);
      expect((await fiche(jour2)).effectifFinal, 85);
    });

    test('caisse : un produit SANS stade, ou une catégorie de reproducteurs, est refusé ; rien n est écrit', () async {
      await enregistrer(jour1, v: jourVentile(depart: e(40, 20, 30, 10)));
      const motif =
          "Vente refusée : le produit « %s » n'a pas de stade d'effectif de pondeuses (Poussin ponte, Poussin en croissance, Poulette ou Pondeuse). Renseignez-le dans « Modifier un produit » avant de le vendre sur une bande de pondeuses.";

      for (final (p, nom) in [(sans, 'Poulet braisé'), (reproducteur, 'Coq reproducteur')]) {
        await expectLater(
          vendre(p, 2, jour2),
          throwsA(isA<VenteRefusee>().having((x) => x.message, 'message', motif.replaceFirst('%s', nom))),
        );
      }
      expect(await db.select(db.sales).get(), isEmpty);
      expect((await (db.select(db.products)..where((t) => t.sku.equals('AVISANS'))).getSingle()).stockQty, 500);
      expect(await depot.chargerJour(bandeId, jour2), isNull);
    });

    test('caisse : une bande sans départ, ou une vente avant le départ, est refusée', () async {
      await expectLater(
        vendre(pl, 1, jour2),
        throwsA(
          isA<VenteRefusee>().having(
            (x) => x.message,
            'message',
            "Vente refusée : l'effectif de départ par stade de la bande AVI-PON-01 n'est pas saisi. Ouvrez la fiche Pondeuses et saisissez-le avant toute vente de cette bande.",
          ),
        ),
      );
      await enregistrer(jour2, v: jourVentile(depart: e(40, 20, 30, 10)));
      await expectLater(
        vendre(pl, 1, jour1),
        throwsA(
          isA<VenteRefusee>().having(
            (x) => x.message,
            'message',
            "Vente refusée : la date de la vente (05/10/2026) précède l'effectif de départ de la bande (fixé le 06/10/2026).",
          ),
        ),
      );
    });

    test('vente antidatée : les fiches suivantes se recalculent', () async {
      await enregistrer(jour2, v: jourVentile(depart: e(40, 20, 30, 10)));
      await enregistrer(jour3);

      await vendre(pl, 2, jour2);

      expect(stocke(await fiche(jour2)), [10, 20, 28, 40]);
      expect(stocke(await fiche(jour3)), [10, 20, 28, 40]);
      expect((await fiche(jour3)).effectifFinal, 98);
    });

    test('journal « Enregistrer des Sujets » : un don est refusé, l entrée avant le départ aussi, un achat va à Poulette', () async {
      await expectLater(
        depot.ecrireEntrees(lotId: bandeId, jour: jour1, achat: 3, ne: 0, don: 0),
        throwsA(isA<FicheRefusee>().having((x) => x.motif, 'motif', contains("n'est pas saisi"))),
      );
      await enregistrer(jour2, v: jourVentile(depart: e(40, 20, 30, 10)));
      await expectLater(
        depot.ecrireEntrees(lotId: bandeId, jour: jour2, achat: 0, ne: 0, don: 4),
        throwsA(isA<FicheRefusee>().having((x) => x.motif, 'motif', contains('se saisissent sur la fiche Pondeuses'))),
      );
      await depot.ecrireEntrees(lotId: bandeId, jour: jour2, achat: 3, ne: 2, don: 0);
      expect(stocke(await fiche(jour2)), [12, 20, 33, 40], reason: 'achat +3 → Poulette ; poussins nés +2 → Poussin ponte');
    });

    test('transferts : le stade (dont le quatrième emplacement) est exigé, et les colonnes `*_4` sont reportées', () async {
      await db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb',
          code: 'AVI-PON-02',
          speciesId: especeId,
          speciesCode: const Value('aviculture'),
          stage: const Value('ponte'),
          createdDate: Value(DateTime(2026, 9, 1)),
          initialQuantity: const Value(0),
          currentQuantity: const Value(0),
        ),
      );
      await enregistrer(jour1, v: jourVentile(depart: e(40, 20, 30, 10)));
      final transferts = TransfertsRepository(database: db, deviceId: 'poste-test');

      await expectLater(
        transferts.creer(
          sourceLotId: bandeId, targetLotId: 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb', jour: jour2, quantite: 3,
        ),
        throwsA(isA<TransfertRefuse>().having((x) => x.motif, 'motif', contains('précisez la catégorie (le stade, pour les pondeuses)'))),
      );
      await transferts.creer(
        sourceLotId: bandeId, targetLotId: 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb', jour: jour2, quantite: 3, categorie: 'quatre',
      );
      final f = await fiche(jour2);
      expect([f.transfertSortie4, f.effectifFinal], [3, 97]);
      expect(stocke(f), [7, 20, 30, 40]);
    });

    test('produit : le stade d un produit de l aviculture se garde ; une valeur inconnue est refusée', () async {
      final depotProduits = ProduitsRepository(database: db);
      await db.into(db.productCategories).insert(
        ProductCategoriesCompanion.insert(id: 'cccccccc-1111-4111-8111-cccccccccccc', label: 'Aviculture'),
      );
      final p = await depotProduits.creer(
        const FormulaireProduit(
          nom: 'Poulette', categorieId: 'cccccccc-1111-4111-8111-cccccccccccc', unite: 'u', mode: 'quote',
          especeId: especeId, categorieEffectif: 'poulette',
        ),
      );
      expect(p.categorieEffectif, 'poulette');
      expect(
        ProduitsRepository.valider(
          const FormulaireProduit(nom: 'X', categorieId: 'c', unite: 'u', mode: 'quote', categorieEffectif: 'canard'),
          creation: true,
        )['categorieEffectif'],
        contains('quatre stades des pondeuses'),
      );
    });

    test('envoi : les colonnes du quatrième emplacement et des passages partent, mort = somme des quatre stades', () async {
      expect(SyncEngine.colonnesStadesPondeuses, [
        'mort_4', 'don_4', 'vente_4', 'cat_depart_4', 'passage_4_sevre', 'passage_jeune_repro',
      ]);
      // Chaque colonne de l'envoi existe au schéma Drift.
      final colonnes = db.livestockDailyEntries.$columns.map((c) => c.name).toSet();
      for (final c in [...SyncEngine.colonnesStadesPondeuses, 'cat_eff_4', 'transfert_entree_4', 'transfert_sortie_4']) {
        expect(colonnes, contains(c));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════ écran

  group('écran Fiche Pondeuses', () {
    late AppDatabase db;
    late FicheJournaliereRepository depot;
    late SoinsRepository soins;
    late ProductionOeufsService production;
    const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
      soins = SoinsRepository(database: db, deviceId: 'poste-test');
      production = ProductionOeufsService(database: db);
      await db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: bandeId,
          code: 'AVI-PON-01',
          speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
          speciesCode: const Value('aviculture'),
          stage: const Value('ponte'),
          createdDate: Value(HeureBenin.maintenant()),
          initialQuantity: const Value(100),
          currentQuantity: const Value(100),
        ),
      );
      for (final (i, (nom, g)) in [
        ('Poussin ponte (0 à 2 mois)', 30.0),
        ('Poussin en croissance (2 à 4 mois)', 60.0),
        ('Poulette (4 à 5.5 mois)', 80.0),
        ('Pondeuse (6 à 18 mois)', 110.0),
        ('Reproducteur', 130.0),
        ('Jeune', 80.0),
        ('Poussin', 30.0),
      ].indexed) {
        await db.into(db.feedRationStandards).insert(
          FeedRationStandardsCompanion.insert(
            id: 'ffffffff-1111-4111-8111-fffffffffff$i',
            speciesCode: 'aviculture',
            stageLabel: nom,
            rationGPerDay: g,
          ),
        );
      }
    });

    tearDown(() async => db.close());

    Future<void> afficher(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: FichePondeusesScreen(depot: depot, soins: soins, production: production)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> saisir(WidgetTester tester, String cle, String valeur) async {
      await tester.enterText(find.byKey(Key('champ-$cle')), valeur);
      await tester.pumpAndSettle();
    }

    String? lire(WidgetTester tester, String cle) => tester.widget<Text>(find.byKey(Key(cle))).data;

    testWidgets('sans départ : la demande de départ tient lieu d effectif, aucun « — » de stade', (tester) async {
      await afficher(tester);

      expect(find.byKey(const Key('depart-requis')), findsOneWidget);
      expect(find.byKey(const Key('ration-depart-requis')), findsOneWidget);
      expect(find.byKey(const Key('ration-effectif-pondeuse')), findsNothing);
      // Les lignes de la fiche Reproducteurs n'apparaissent jamais ici.
      expect(find.text('REPRODUCTEUR'), findsNothing);
      expect(find.text('JEUNE'), findsNothing);
    });

    testWidgets('la proposition du stade n est reprise que sur demande ; le total est celui du barème', (tester) async {
      await afficher(tester);

      await tester.ensureVisible(find.byKey(const Key('depart-proposition')));
      await tester.tap(find.byKey(const Key('depart-proposition')));
      await tester.pumpAndSettle();

      expect(lire(tester, 'ration-effectif-pondeuse'), '100');
      // 100 Pondeuses × 110 g = 11 000 g.
      expect(lire(tester, 'total-provende'), '11000 g (11 Kg)');
    });

    testWidgets('départ saisi : effectifs calculés en direct, provende = somme des quatre stades', (tester) async {
      await afficher(tester);

      await saisir(tester, 'depart-quatre', '10');
      await saisir(tester, 'depart-sevre', '20');
      await saisir(tester, 'depart-jeune', '30');
      await saisir(tester, 'depart-repro', '40');
      // « Achats / Entrées du jour » est un champ local de l'écran Pondeuses (clé suffixée par sa valeur).
      await tester.enterText(find.byKey(const Key('champ-achat-0')), '3');
      await tester.pumpAndSettle();
      await saisir(tester, 'passage-3', '5');

      // Départ 10 / 20 / 30 / 40 + achat 3 (→ Poulette) ; passage Poulette → Pondeuse de 5.
      expect(
        [for (final c in ['poussin_ponte', 'poussin_croissance', 'poulette', 'pondeuse']) lire(tester, 'ration-effectif-$c')],
        ['10', '20', '28', '45'],
      );
      // 10 × 30 + 20 × 60 + 28 × 80 + 45 × 110 = 300 + 1 200 + 2 240 + 4 950 = 8 690.
      expect(lire(tester, 'total-provende'), '8690 g (8.69 Kg)');
    });

    testWidgets('un passage supérieur à son stade source est annoncé, et l enregistrement refusé', (tester) async {
      await afficher(tester);
      await saisir(tester, 'depart-quatre', '10');
      await saisir(tester, 'depart-sevre', '20');
      await saisir(tester, 'depart-jeune', '30');
      await saisir(tester, 'depart-repro', '40');
      await saisir(tester, 'passage-1', '11');

      expect(find.byKey(const Key('refus-passage')), findsOneWidget);
      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();
      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('l enregistrement écrit le départ par stade, puis le verrouille', (tester) async {
      await afficher(tester);
      await saisir(tester, 'depart-quatre', '10');
      await saisir(tester, 'depart-sevre', '20');
      await saisir(tester, 'depart-jeune', '30');
      await saisir(tester, 'depart-repro', '40');

      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();

      final f = await depot.chargerJour(bandeId, HeureBenin.maintenant());
      expect([f?.catDepart4, f?.catDepartSevre, f?.catDepartJeune, f?.catDepartRepro], [10, 20, 30, 40]);
      expect(find.byKey(const Key('depart-requis')), findsNothing);
      expect(find.byKey(const Key('depart-verrouille')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('sans départ, l enregistrement est refusé avec le motif du web, aucun œuf n entre au stock', (tester) async {
      await afficher(tester);
      await tester.enterText(find.byKey(const Key('champ-oeufs-pondus-0')), '90');
      await tester.pumpAndSettle();
      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();

      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
      expect(find.textContaining("Saisissez d'abord l'effectif de départ de la bande par stade"), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  // ═══════════════════════════════════════════════════════════════════ Blade : libellés des stades

  group('Blade de la fiche Pondeuses (la vue est le maître)', () {
    final blade = File('$dossierLaravel/resources/views/livewire/elevage/fiche-pondeuses.blade.php');
    final ecran = File('lib/features/elevage/fiche_pondeuses_screen.dart').readAsStringSync();
    final elements = File('lib/features/elevage/elements_fiche.dart').readAsStringSync();

    test('les quatre libellés du barème, les trois passages et les textes du départ sont dans le Blade ET dans l écran', () {
      if (!blade.existsSync()) {
        markTestSkipped('SAUT : vue Blade absente');
        return;
      }
      final b = blade.readAsStringSync();
      final php = File('$dossierLaravel/app/Support/StadePondeuse.php').readAsStringSync();
      for (final libelle in StadePondeuse.libelles.values) {
        expect(php, contains("'$libelle'"), reason: 'StadePondeuse.php : $libelle');
      }
      for (final t in [
        'Passage du jour (Poussin ponte → Poussin en croissance)',
        'Passage du jour (Poussin en croissance → Poulette)',
        'Passage du jour (Poulette → Pondeuse)',
        'Effectif de départ par stade (obligatoire)',
        'Effectif de départ par stade (verrouillé)',
        "Reprendre la proposition d'après le stade de la bande",
        'Rationnement &amp; Provende Servie par Stade (en Grammes g/j)',
        "Saisissez l'effectif de départ de la bande pour calculer les effectifs par stade et la provende servie.",
        "Cette journée porte des ventes d'avant la mise en place des stades, non ventilées : elle ne peut pas être ré-enregistrée.",
      ]) {
        expect(b, contains(t), reason: 'Blade : $t');
        final cherche = t.replaceAll('&amp;', '&');
        expect(ecran + elements, contains(cherche), reason: 'poste : $t');
      }
      // Jamais les lignes ni les libellés des reproducteurs sur la fiche Pondeuses.
      expect(b, isNot(contains('Pondeuse / Repro')));
      expect(b, isNot(contains('x-ration-volaille')));
      expect(ecran, isNot(contains("'Pondeuse / Repro'")));
    });
  });
}
