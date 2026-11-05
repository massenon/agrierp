import 'dart:io';
import 'dart:math';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/database/sync_columns.dart';
import 'package:agrierp/core/temps/heure_benin.dart';
import 'package:agrierp/features/elevage/categorie_volaille.dart';
import 'package:agrierp/features/elevage/effectif_par_categorie.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_reproducteurs_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/elevage/sujets_entrees_repository.dart';
import 'package:agrierp/features/stocks/produits_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'fiches_especes_commun.dart' show bladeDe;
import 'php_laravel.dart';

/// Ticket VOL-1 (décision client du 04/11/2026) — EFFECTIF PAR CATÉGORIE CALCULÉ POUR LES VOLAILLES REPRODUCTRICES,
/// transposition au poste de `EffectifParCategorieService` (volailles), `CategorieVolaille` et de la fiche Reproducteurs.
///
/// Trois preuves : (1) des JEUX CALCULÉS À LA MAIN (littéraux, jamais produits par le code testé) ; (2) la PARITÉ
/// EXÉCUTÉE avec le vrai PHP du dépôt Laravel ; (3) le dépôt (départ obligatoire, ventes de la caisse rangées par
/// catégorie, refus aux motifs du web) et l'écran.
///
/// Bande de 100 : départ Reproducteur 20 / Jeune 30 / Poussin 50, rations 130 / 80 / 30 g/j.
///   J1 (05/10) achat 2, éclosions 10, morts R1 + J2 + P3                     → R19  J30  P57   total 106   6 580 g
///   J2 (06/10) ventes R1 + J2 + P4, mort J1, don P2, passage 5               → R18  J32  P46   total 96    6 280 g
///   J3 (07/10) vente P50                                                     → R18  J32  P0    total 46    somme 50
void main() {
  const volailles = EffectifParCategorie.volailles;

  EffectifCategories e(int? r, int? s, int? j) => EffectifCategories(repro: r, sevre: s, jeune: j);
  List<int?> trio(EffectifCategoriesJour r) => [r.repro, r.sevre, r.jeune];

  group('jeux calculés à la main — volailles reproductrices', () {
    test('la vente reproducteur sort des reproducteurs seulement', () {
      final r = EffectifParCategorie.calculerJour(
        volailles,
        e(5, 7, 9),
        const MouvementsJour(venteRepro: 2),
      );
      expect(trio(r), [3, 7, 9]);
    });

    test('l achat entre dans les Jeunes, l éclosion dans les Poussins', () {
      expect(
        trio(EffectifParCategorie.calculerJour(volailles, e(0, 0, 10), const MouvementsJour(achat: 4))),
        [0, 0, 14],
      );
      expect(
        trio(EffectifParCategorie.calculerJour(volailles, e(0, 10, 0), const MouvementsJour(ne: 6))),
        [0, 16, 0],
      );
    });

    test('le passage transfère des Poussins aux Jeunes, total inchangé', () {
      final r = EffectifParCategorie.calculerJour(volailles, e(3, 10, 2), const MouvementsJour(passage: 4));
      expect(trio(r), [3, 6, 6]);
      expect(r.somme, 15);
      expect(r.refus, isNull);
    });

    test('chaque catégorie est bornée à 0', () {
      final r = EffectifParCategorie.calculerJour(
        volailles,
        e(2, 2, 2),
        const MouvementsJour(mortRepro: 5, venteSevre: 9, donJeune: 7),
      );
      expect(trio(r), [0, 0, 0]);
    });

    test('un passage supérieur à la source est refusé et ramené à la source', () {
      final r = EffectifParCategorie.calculerJour(
        volailles,
        e(0, 3, 0),
        const MouvementsJour(mortSevre: 1, passage: 3),
      );
      expect(
        r.refus,
        "Passage de stade refusé : 3 sujet(s) à faire passer, mais la catégorie source n'en compte que 2.",
      );
      expect(r.passageApplique, 2);
      expect(trio(r), [0, 0, 2]);
    });

    test('⚠️ JAMAIS de null : mouvements absents et veille inconnue valent 0', () {
      final r = EffectifParCategorie.calculerJour(volailles, e(null, null, null), const MouvementsJour());
      expect(trio(r), [0, 0, 0]);
      expect(r.estComplet, isTrue);
    });

    test('départ ≠ somme refusé, avec le motif du serveur', () {
      expect(
        EffectifParCategorie.verifierDepart(e(20, 50, 29), 100),
        "La somme des catégories de départ (99) ne correspond pas à l'effectif total au début du jour de départ (100).",
      );
      expect(EffectifParCategorie.verifierDepart(e(20, 50, 30), 100), isNull);
    });

    test('l aviculture « ponte » (Pondeuses) n est pas une volaille reproductrice', () {
      expect(EffectifParCategorie.especeDuCode('aviculture', stade: 'reproduction'), volailles);
      expect(EffectifParCategorie.especeDuCode('aviculture', stade: 'ponte'), isNull);
      expect(EffectifParCategorie.especeDuCode('cuniculture'), EffectifParCategorie.lapins);
    });

    test('libellés : « Jeune », jamais « Poulet » ni « Jeune à maturité »', () {
      expect(CategorieVolaille.libelles.values.toList(), ['Reproducteur', 'Jeune', 'Poussin']);
      expect(CategorieVolaille.emplacements, {'reproducteur': 'repro', 'jeune': 'jeune', 'poussin': 'sevre'});
    });

    test('clés de ration exactes, jamais par sous-chaîne', () {
      expect(CategorieVolaille.cleDuLibelle(' jeune '), CategorieVolaille.jeune);
      expect(CategorieVolaille.cleDuLibelle('Poussin ponte (0 à 2 mois)'), isNull);
      expect(CategorieVolaille.cleDuLibelle('Pondeuse (6 à 18 mois)'), isNull);
      expect(CategorieVolaille.cleDuLibelle('Jeune porc'), isNull);
    });

    test('produits par défaut d après le nom', () {
      expect(CategorieVolaille.devinerDepuisLeNom("Poussin d'un jour"), 'poussin');
      expect(CategorieVolaille.devinerDepuisLeNom('Poulet goliath (sujet vif)'), 'jeune');
      expect(CategorieVolaille.devinerDepuisLeNom('Coq reproducteur'), 'reproducteur');
      expect(CategorieVolaille.devinerDepuisLeNom('Œufs de table (plateau)'), isNull);
      expect(CategorieVolaille.devinerDepuisLeNom('Aliment démarrage (poussin) 25kg'), isNull);
    });
  });

  final saut = sautSansPhp();

  group('⚠️⚠️ parité EXÉCUTÉE avec le vrai PHP du serveur', () {
    test('calculerJour(volailles) : grille de 500 combinaisons générées', () {
      final hasard = Random(4115);
      int? n(int max, {double nul = 0.1}) => hasard.nextDouble() < nul ? null : hasard.nextInt(max + 1);

      final jours = <List<Object?>>[];
      for (var i = 0; i < 500; i++) {
        jours.add([
          {'repro': n(40), 'sevre': n(40), 'jeune': n(40)},
          {
            'achat': n(9),
            'ne': n(9),
            'vente_repro': n(8),
            'vente_sevre': n(30),
            'vente_jeune': n(12),
            'mort_repro': n(8),
            'mort_sevre': n(12),
            'mort_jeune': n(8),
            'don_repro': n(4),
            'don_sevre': n(5),
            'don_jeune': n(4),
            'passage': n(45),
            'transfert_entree_repro': hasard.nextInt(3),
            'transfert_sortie_sevre': hasard.nextInt(3),
          },
          hasard.nextInt(4) == 0 ? null : hasard.nextInt(130),
        ]);
      }

      final sortie = executerPhp(
        r'''<?php
require 'vendor/autoload.php';
$e = json_decode(file_get_contents($argv[1]), true);
$s = [];
foreach ($e as $c) {
    $r = App\Services\EffectifParCategorieService::calculerJour('volailles', $c[0], $c[1], $c[2]);
    $s[] = [$r->repro, $r->sevre, $r->jeune, $r->sommeDifferente, $r->refus, $r->passageApplique];
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
          volailles,
          e(v['repro'], v['sevre'], v['jeune']),
          MouvementsJour(
            achat: m['achat'],
            ne: m['ne'],
            venteRepro: m['vente_repro'],
            venteSevre: m['vente_sevre'],
            venteJeune: m['vente_jeune'],
            mortRepro: m['mort_repro'],
            mortSevre: m['mort_sevre'],
            mortJeune: m['mort_jeune'],
            donRepro: m['don_repro'],
            donSevre: m['don_sevre'],
            donJeune: m['don_jeune'],
            passage: m['passage'],
            transfertEntreeRepro: m['transfert_entree_repro']!,
            transfertSortieSevre: m['transfert_sortie_sevre']!,
          ),
          totalFinal: jours[i][2] as int?,
        );
        expect(
          [r.repro, r.sevre, r.jeune, r.sommeDifferente, r.refus, r.passageApplique],
          sortie[i],
          reason: 'combinaison #$i : ${jours[i]}',
        );
        if (r.refus != null) refus++;
      }
      expect(refus, greaterThan(30), reason: 'la grille exerce le refus de passage');
    }, skip: saut);

    test('tableau de rationnement par catégorie : mêmes lignes, mêmes totaux, mêmes arrondis', () {
      final hasard = Random(77);
      final cas = <Map<String, Object?>>[];
      for (var i = 0; i < 60; i++) {
        cas.add({
          'rations': [
            {'stage_label': 'Pondeuse (6 à 18 mois)', 'ration_g_per_day': 110},
            {'stage_label': 'Poussin ponte (0 à 2 mois)', 'ration_g_per_day': 30},
            if (hasard.nextInt(5) != 0) {'stage_label': 'Reproducteur', 'ration_g_per_day': 60 + hasard.nextInt(120)},
            if (hasard.nextInt(5) != 0) {'stage_label': ' JEUNE ', 'ration_g_per_day': 40 + hasard.nextInt(80)},
            if (hasard.nextInt(5) != 0) {'stage_label': 'Poussin', 'ration_g_per_day': 10 + hasard.nextInt(40)},
          ],
          'effectifs': {
            'repro': hasard.nextInt(9) == 0 ? null : hasard.nextInt(80),
            'sevre': hasard.nextInt(9) == 0 ? null : hasard.nextInt(80),
            'jeune': hasard.nextInt(9) == 0 ? null : hasard.nextInt(80),
          },
        });
      }

      final sortie = executerPhp(
        r'''<?php
require 'vendor/autoload.php';
$e = json_decode(file_get_contents($argv[1]), true);
$s = [];
foreach ($e as $c) {
    $rations = collect(array_map(fn ($r) => (object) $r, $c['rations']));
    $t = App\Support\CategorieVolaille::tableauReproducteurs($rations, $c['effectifs']);
    $s[] = [array_map(fn ($l) => [$l['libelle'], $l['ration'], $l['effectif'], $l['total_g']], $t['lignes']), $t['total_g'], $t['total_kg']];
}
echo json_encode($s);
''',
        cas,
      ) as List;

      for (var i = 0; i < cas.length; i++) {
        final rations = <FeedRationStandard>[
          for (final r in cas[i]['rations'] as List)
            FeedRationStandard(
              syncStatus: SyncStatus.synced,
              id: '$i'.padRight(36, '0'),
              speciesCode: 'aviculture',
              stageLabel: (r as Map)['stage_label'] as String,
              rationGPerDay: (r['ration_g_per_day'] as int).toDouble(),
              isActive: true,
              updatedAt: null,
            ),
        ];
        final t = CategorieVolaille.tableauReproducteurs(rations, (cas[i]['effectifs'] as Map).cast<String, int?>());
        final php = sortie[i] as List;
        expect(
          [for (final l in t.lignes) [l.libelle, l.ration, l.effectif, l.totalG]],
          php[0],
          reason: 'cas #$i',
        );
        expect(t.totalG, php[1], reason: 'cas #$i : total');
        expect(t.totalKg, (php[2] as num?)?.toDouble(), reason: 'cas #$i : kilos');
      }
    }, skip: saut);

    test('catégorie par défaut d un produit et clé de ration : mêmes réponses que le PHP', () {
      final noms = [
        "Poussin d'un jour", 'Poulet goliath (sujet vif)', 'Poulet abattu frais', 'Coq reproducteur',
        'Poule pondeuse réformée', 'Œufs de table (plateau)', 'Aliment démarrage (poussin) 25kg', 'Lapin vif',
        'Jeune en maturité', 'POUSSIN CHAIR', 'Poulets', 'Provende ponte', 'Reproducteur mâle', 'Vaccin poussin', '',
        'Poule', 'Poulet fumé', 'Médicament poulet',
      ];
      final libelles = [
        'Reproducteur', ' jeune ', 'Poussin', 'Poussin ponte (0 à 2 mois)', 'Jeune porc', 'Pondeuse (6 à 18 mois)',
        'JEUNE', 'Reproduct', 'Poussins',
      ];
      final sortie = executerPhp(
        r'''<?php
require 'vendor/autoload.php';
$e = json_decode(file_get_contents($argv[1]), true);
echo json_encode([
    array_map(fn ($n) => App\Support\CategorieVolaille::devinerDepuisLeNom($n), $e['noms']),
    array_map(fn ($l) => App\Support\CategorieVolaille::cleDuLibelle($l), $e['libelles']),
]);
''',
        {'noms': noms, 'libelles': libelles},
      ) as List;
      expect([for (final n in noms) CategorieVolaille.devinerDepuisLeNom(n)], sortie[0]);
      expect([for (final l in libelles) CategorieVolaille.cleDuLibelle(l)], sortie[1]);
    }, skip: saut);
  });

  // ═══════════════════════════════════════════════════════════════════ dépôt, caisse, produit, écran

  group('dépôt, caisse et produit', () {
    late AppDatabase db;
    late FicheJournaliereRepository depot;
    late CaisseRepository caisse;
    const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
    const especeId = 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee';
    final jour1 = DateTime(2026, 10, 5);
    final jour2 = DateTime(2026, 10, 6);
    final jour3 = DateTime(2026, 10, 7);
    late Product poussin;
    late Product jeune;
    late Product repro;
    late Product sans;

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
      caisse = CaisseRepository(
        database: db,
        deviceId: 'poste-test',
        maintenant: () => DateTime(2026, 10, 14, 12),
      );
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
          code: 'AVI-REP-01',
          speciesId: especeId,
          speciesCode: const Value('aviculture'),
          stage: const Value('reproduction'),
          createdDate: Value(DateTime(2026, 9, 1)),
          initialQuantity: const Value(100),
          currentQuantity: const Value(100),
        ),
      );
      poussin = await produit('AVIPOUSSIN', "Poussin d'un jour", 'poussin');
      jeune = await produit('AVIJEUNE', 'Poulet goliath (sujet vif)', 'jeune');
      repro = await produit('AVIREPRO', 'Coq reproducteur', 'reproducteur');
      sans = await produit('AVISANS', 'Poulet braisé', null);
    });

    tearDown(() async => db.close());

    VentilationJour jourVentile({
      int mR = 0, int mJ = 0, int mP = 0, int dR = 0, int dJ = 0, int dP = 0, int passage = 0,
      EffectifCategories? depart,
    }) => VentilationJour(
      mortRepro: mR, mortSevre: mP, mortJeune: mJ, donRepro: dR, donSevre: dP, donJeune: dJ,
      passage: passage, departSaisi: depart,
    );

    Future<void> enregistrer(DateTime jour, {int achat = 0, int ne = 0, VentilationJour? v}) async {
      final vv = v ?? jourVentile();
      await depot.enregistrer(
        lotId: bandeId, jour: jour, achat: achat, ne: ne, mort: vv.totalMorts, don: vv.totalDons, ventilation: vv,
      );
    }

    Future<LivestockDailyEntry> fiche(DateTime jour) async => (await depot.chargerJour(bandeId, jour))!;

    List<int?> stocke(LivestockDailyEntry f) => [f.catEffRepro, f.catEffJeune, f.catEffSevre];

    LignePanier ligne(Product p, int q) => LignePanier(produit: p, quantite: q, montant: 1000.0 * q, lotId: bandeId);

    Future<void> vendre(Product p, int q, DateTime jour) =>
        caisse.enregistrerVente(panier: [ligne(p, q)], modePaiement: 'especes', dateVente: jour);

    Future<void> scenario() async {
      await enregistrer(
        jour1, achat: 2, ne: 10,
        v: jourVentile(mR: 1, mJ: 2, mP: 3, depart: e(20, 50, 30)),
      );
      await vendre(repro, 1, jour2);
      await vendre(jeune, 2, jour2);
      await vendre(poussin, 4, jour2);
      await enregistrer(jour2, v: jourVentile(mJ: 1, dP: 2, passage: 5));
      await vendre(poussin, 50, jour3);
      await enregistrer(jour3);
    }

    test('enregistrement : départ, mouvements ventilés et catégories calculées', () async {
      await enregistrer(
        jour1, achat: 2, ne: 10,
        v: jourVentile(mR: 1, mJ: 2, mP: 3, depart: e(20, 50, 30)),
      );

      final f = await fiche(jour1);
      expect([f.catDepartRepro, f.catDepartJeune, f.catDepartSevre], [20, 30, 50]);
      expect([f.mortRepro, f.mortJeune, f.mortSevre, f.mort], [1, 2, 3, 6]);
      expect([f.venteRepro, f.venteJeune, f.venteSevre], [0, 0, 0], reason: 'ventes connues à zéro, jamais null');
      expect(f.effectifFinal, 106);
      expect(stocke(f), [19, 30, 57]);
    });

    test('jours suivants : ventes de la caisse par catégorie, passage, bornes à 0', () async {
      await scenario();

      final f2 = await fiche(jour2);
      expect([f2.venteRepro, f2.venteJeune, f2.venteSevre, f2.vente], [1, 2, 4, 7]);
      expect(stocke(f2), [18, 32, 46]);
      expect(f2.effectifFinal, 96);
      final f3 = await fiche(jour3);
      expect(stocke(f3), [18, 32, 0]);
      expect(f3.effectifFinal, 46);
      final bande = await (db.select(db.livestockLots)..where((t) => t.id.equals(bandeId))).getSingle();
      expect(bande.currentQuantity, 46);
    });

    test('⚠️ SANS DÉPART : la journée est refusée, avec le motif du web', () async {
      await expectLater(
        enregistrer(jour1, achat: 3),
        throwsA(
          isA<FicheRefusee>().having(
            (x) => x.motif,
            'motif',
            "Saisissez d'abord l'effectif de départ de la bande par catégorie (Reproducteur, Jeune, Poussin) : la journée ne peut pas être enregistrée sans lui.",
          ),
        ),
      );
      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
    });

    test('un départ incohérent est refusé, un jour antérieur au départ n est pas saisissable', () async {
      await expectLater(
        enregistrer(jour1, v: jourVentile(depart: e(20, 50, 29))),
        throwsA(isA<FicheRefusee>().having((x) => x.motif, 'motif', contains('(99)'))),
      );
      await enregistrer(jour2, v: jourVentile(depart: e(20, 50, 30)));
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

    test('un passage supérieur à la source est refusé avant toute écriture', () async {
      await expectLater(
        enregistrer(jour1, ne: 10, v: jourVentile(mP: 3, passage: 100, depart: e(20, 50, 30))),
        throwsA(isA<FicheRefusee>().having((x) => x.motif, 'motif', contains("n'en compte que 57"))),
      );
      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
    });

    test('corriger un jour passé recalcule les jours suivants', () async {
      await scenario();
      await enregistrer(
        jour1, achat: 2, ne: 10,
        v: jourVentile(mR: 4, mJ: 2, mP: 3),
      );

      expect(stocke(await fiche(jour1)), [16, 30, 57]);
      expect(stocke(await fiche(jour2)), [15, 32, 46]);
      expect((await fiche(jour2)).effectifFinal, 93);
      expect(stocke(await fiche(jour3)), [15, 32, 0]);
    });

    test('caisse : un produit SANS catégorie est refusé, rien n est écrit', () async {
      await enregistrer(jour1, v: jourVentile(depart: e(20, 50, 30)));

      await expectLater(
        vendre(sans, 2, jour2),
        throwsA(
          isA<VenteRefusee>().having(
            (x) => x.message,
            'message',
            "Vente refusée : le produit « Poulet braisé » n'a pas de catégorie d'effectif (Reproducteur, Jeune ou Poussin). Renseignez-la dans « Modifier un produit » avant de le vendre sur une bande de volailles reproductrices.",
          ),
        ),
      );
      expect(await db.select(db.sales).get(), isEmpty);
      expect((await (db.select(db.products)..where((t) => t.sku.equals('AVISANS'))).getSingle()).stockQty, 500);
      expect(await depot.chargerJour(bandeId, jour2), isNull);
    });

    test('caisse : une bande sans départ, ou une vente avant le départ, est refusée', () async {
      await expectLater(
        vendre(jeune, 1, jour2),
        throwsA(
          isA<VenteRefusee>().having(
            (x) => x.message,
            'message',
            "Vente refusée : l'effectif de départ par catégorie de la bande AVI-REP-01 n'est pas saisi. Ouvrez la fiche Volailles Reproducteurs et saisissez-le avant toute vente de cette bande.",
          ),
        ),
      );
      await enregistrer(jour2, v: jourVentile(depart: e(20, 50, 30)));
      await expectLater(
        vendre(jeune, 1, jour1),
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
      await enregistrer(jour2, v: jourVentile(depart: e(20, 50, 30)));
      await enregistrer(jour3);

      await vendre(jeune, 2, jour2);

      expect(stocke(await fiche(jour2)), [20, 28, 50]);
      expect(stocke(await fiche(jour3)), [20, 28, 50]);
      expect((await fiche(jour3)).effectifFinal, 98);
    });

    test('journal « Enregistrer des Sujets » : un don est refusé, une entrée avant le départ aussi', () async {
      await expectLater(
        depot.ecrireEntrees(lotId: bandeId, jour: jour1, achat: 3, ne: 0, don: 0),
        throwsA(isA<FicheRefusee>().having((x) => x.motif, 'motif', contains("n'est pas saisi"))),
      );
      await enregistrer(jour2, v: jourVentile(depart: e(20, 50, 30)));
      await expectLater(
        depot.ecrireEntrees(lotId: bandeId, jour: jour2, achat: 0, ne: 0, don: 4),
        throwsA(isA<FicheRefusee>().having((x) => x.motif, 'motif', contains('se saisissent sur la fiche Volailles Reproducteurs'))),
      );
      await depot.ecrireEntrees(lotId: bandeId, jour: jour2, achat: 3, ne: 0, don: 0);
      expect(stocke(await fiche(jour2)), [20, 33, 50]);
    });

    test('journal « Enregistrer des Sujets » (écran) : mêmes refus et mêmes clés d erreur que le web', () async {
      final sujets = SujetsEntreesRepository(database: db, fiches: depot, horloge: () => DateTime(2026, 10, 14, 12));
      FormulaireSujet saisie(String origine, DateTime jour) =>
          FormulaireSujet(speciesId: especeId, lotId: bandeId, origine: origine, quantite: '3', date: jour);

      await expectLater(
        sujets.ajouter(saisie('Achat', jour1)),
        throwsA(isA<SujetRefuse>().having((x) => x.erreurs.keys.single, 'clé', 'entry_date')),
      );
      await enregistrer(jour2, v: jourVentile(depart: e(20, 50, 30)));
      await expectLater(
        sujets.ajouter(saisie('Don', jour2)),
        throwsA(isA<SujetRefuse>().having((x) => x.erreurs.keys.single, 'clé', 'origine')),
      );
      await sujets.ajouter(saisie('Naissance', jour2));
      expect(stocke(await fiche(jour2)), [20, 30, 53], reason: 'les poussins nés (+3) entrent dans les Poussins');
    });

    test('produit : la catégorie d effectif ne se garde que pour l aviculture', () async {
      final depotProduits = ProduitsRepository(database: db);
      await db.into(db.productCategories).insert(
        ProductCategoriesCompanion.insert(id: 'cccccccc-1111-4111-8111-cccccccccccc', label: 'Aviculture'),
      );
      await db.into(db.livestockSpecies).insert(
        LivestockSpeciesCompanion.insert(id: 'dddddddd-1111-4111-8111-dddddddddddd', code: 'cuniculture', label: 'Lapins'),
      );

      Future<Product> creer(String nom, String espece, String categorie) => depotProduits.creer(
        FormulaireProduit(
          nom: nom, categorieId: 'cccccccc-1111-4111-8111-cccccccccccc', unite: 'u', mode: 'quote',
          especeId: espece, categorieEffectif: categorie,
        ),
      );

      final coq = await creer('Coq', especeId, 'reproducteur');
      final lapin = await creer('Lapin', 'dddddddd-1111-4111-8111-dddddddddddd', 'jeune');
      expect(coq.categorieEffectif, 'reproducteur');
      expect(lapin.categorieEffectif, isNull, reason: 'hors aviculture : toujours vide');
      expect(
        ProduitsRepository.valider(
          const FormulaireProduit(nom: 'X', categorieId: 'c', unite: 'u', mode: 'quote', categorieEffectif: 'canard'),
          creation: true,
        )['categorieEffectif'],
        "La catégorie d'effectif doit être Reproducteur, Jeune ou Poussin.",
      );
      final modifie = await depotProduits.modifier(
        coq.id,
        FormulaireProduit(nom: 'Coq', categorieId: 'c', unite: 'u', mode: 'quote', especeId: especeId, categorieEffectif: 'poussin'),
      );
      expect(modifie.categorieEffectif, 'poussin');
    });
  });

  // ═══════════════════════════════════════════════════════════════════ écran

  group('écran Fiche Reproducteurs', () {
    late AppDatabase db;
    late FicheJournaliereRepository depot;
    late SoinsRepository soins;
    const bandeId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
      soins = SoinsRepository(database: db, deviceId: 'poste-test');
      await db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: bandeId,
          code: 'AVI-REP-01',
          speciesId: 'eeeeeeee-1111-4111-8111-eeeeeeeeeeee',
          speciesCode: const Value('aviculture'),
          stage: const Value('reproduction'),
          createdDate: Value(HeureBenin.maintenant()),
          initialQuantity: const Value(100),
          currentQuantity: const Value(100),
        ),
      );
      for (final (i, (nom, g)) in [('Reproducteur', 130.0), ('Jeune', 80.0), ('Poussin', 30.0)].indexed) {
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
      await tester.pumpWidget(MaterialApp(home: FicheReproducteursScreen(depot: depot, soins: soins)));
      await tester.pumpAndSettle();
    }

    Future<void> saisir(WidgetTester tester, String cle, String valeur) async {
      await tester.enterText(find.byKey(Key('champ-$cle')), valeur);
      await tester.pumpAndSettle();
    }

    testWidgets('sans départ : la demande de départ tient lieu d effectif, aucun « — » de catégorie', (tester) async {
      await afficher(tester);

      expect(find.byKey(const Key('depart-requis')), findsOneWidget);
      expect(find.byKey(const Key('ration-depart-requis')), findsOneWidget);
      expect(find.byKey(const Key('ration-effectif-reproducteur')), findsNothing);
      expect(find.text('Poulet'), findsNothing);
      expect(find.textContaining('à maturité'), findsNothing);
    });

    testWidgets('la proposition du stade n est reprise que sur demande', (tester) async {
      await afficher(tester);

      await tester.ensureVisible(find.byKey(const Key('depart-proposition')));
      await tester.tap(find.byKey(const Key('depart-proposition')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ration-effectif-reproducteur')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('ration-effectif-reproducteur'))).data, '100');
      expect(tester.widget<Text>(find.byKey(const Key('total-provende'))).data, '13000 g (13 Kg)');
    });

    testWidgets('départ saisi : effectifs calculés en direct, provende = somme des trois catégories', (tester) async {
      await afficher(tester);

      await saisir(tester, 'depart-repro', '20');
      await saisir(tester, 'depart-jeune', '30');
      await saisir(tester, 'depart-sevre', '50');
      await saisir(tester, 'achat', '3');

      String? lire(String cle) => tester.widget<Text>(find.byKey(Key(cle))).data;
      // Départ 20 / 30 / 50 + achat 3 (→ Jeune).
      expect([lire('ration-effectif-reproducteur'), lire('ration-effectif-jeune'), lire('ration-effectif-poussin')], ['20', '33', '50']);
      // 20 × 130 + 33 × 80 + 50 × 30 = 2 600 + 2 640 + 1 500 = 6 740.
      expect(lire('total-provende'), '6740 g (6.74 Kg)');
    });

    testWidgets('l enregistrement écrit le départ, puis le verrouille', (tester) async {
      await afficher(tester);
      await saisir(tester, 'depart-repro', '20');
      await saisir(tester, 'depart-jeune', '30');
      await saisir(tester, 'depart-sevre', '50');

      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();

      final f = await depot.chargerJour(bandeId, HeureBenin.maintenant());
      expect([f?.catDepartRepro, f?.catDepartJeune, f?.catDepartSevre], [20, 30, 50]);
      expect(find.byKey(const Key('depart-requis')), findsNothing);
      expect(find.byKey(const Key('depart-verrouille')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('sans départ, l enregistrement est refusé avec le motif du web', (tester) async {
      await afficher(tester);
      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton);
      await tester.pumpAndSettle();

      expect(await db.select(db.livestockDailyEntries).get(), isEmpty);
      expect(find.textContaining("Saisissez d'abord l'effectif de départ de la bande"), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  // ═══════════════════════════════════════════════════════════════════ glossaire et écart assumé

  group('glossaire VOL-1 : « Jeune » partout, écart ASSUMÉ vis-à-vis de la maquette (décision client 04/11/2026)', () {
    final ecran = File('lib/features/elevage/fiche_reproducteurs_screen.dart').readAsStringSync();
    final elements = File('lib/features/elevage/elements_fiche.dart').readAsStringSync();
    final blade = bladeDe('fiche-reproducteurs');

    test('l écran et le composant de ration disent Reproducteur / Jeune / Poussin, jamais « Poulet » ni « Repro »', () {
      expect(ecran, contains("('repro', 'Reproducteur'), ('jeune', 'Jeune'), ('sevre', 'Poussin')"));
      expect(ecran, contains('Passage du jour (Poussin → Jeune)'));
      for (final source in [ecran, elements]) {
        expect(source, isNot(contains("'Poulet'")));
        expect(source, isNot(contains("'Repro'")));
        expect(source, isNot(contains('à maturité')));
      }
    });

    test('le Blade du web dit la même chose (la vue est le maître)', () {
      if (!blade.existsSync()) {
        markTestSkipped('SAUT : vue Blade absente');
        return;
      }
      final b = blade.readAsStringSync();
      expect(b, isNot(contains('>Poulet<')));
      expect(b, isNot(contains('>Repro<')));
      expect(b, isNot(contains('à maturité')));
      expect(b, contains('>Jeune<'));
      expect(b, contains('Passage du jour (Poussin → Jeune)'));
    });

    test('la maquette dit encore « Poulet » : l écran suit la décision client, pas la maquette', () {
      final maquette = File('$dossierPrototype/fiche-volailles-reproducteurs.html');
      if (!maquette.existsSync()) {
        markTestSkipped('maquette absente de ce poste de développement');
        return;
      }
      // Si la maquette est alignée un jour, cet écart n'en est plus un : retirer ce test.
      expect(maquette.readAsStringSync(), contains('Poulet'));
    });

    test('⚠️ les clés de synchronisation ne sont PAS renommées : `*_jeune` porte les Jeunes, `*_sevre` les Poussins', () {
      final schema = File('lib/core/database/app_database.dart').readAsStringSync();
      expect(schema, isNot(contains('mortPoulet')));
      expect(schema, contains('IntColumn get venteSevre'));
      expect(CategorieVolaille.emplacement('poussin'), 'sevre');
      expect(CategorieVolaille.emplacement('jeune'), 'jeune');
    });
  });
}
