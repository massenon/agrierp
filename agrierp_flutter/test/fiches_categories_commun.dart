// Ticket U12a — parité exécutée commune des fiches Lapins et Porcs (même Blade à l'espèce près) : jeu de données à
// chaîne et sans chaîne, extraction PHP du formulaire du jour, comparaison avec l'écran du poste.
import 'package:agrierp/features/elevage/elements_fiche.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fiches_especes_commun.dart';

/// Fiches Lapins et Porcs : deux bandes — A (engraissement) SANS chaîne, dont une fiche ancienne porte des effectifs
/// de catégorie saisis à la main (D6) et d'autres des morts NON ventilés ; B (reproduction) AVEC chaîne (départ mixte
/// sur sa première fiche, tous ses mouvements ventilés, passages de stade) ; une fiche le 20/10 pour chacune ; un
/// produit de provende rattaché à l'espèce et un barème partiel (le reste en rations de secours).
JeuFiches jeuCategories({
  required String codeEspece,
  required String prefixe,
  required int graine,
  required Map<String, Object?> provende,
  required List<(String, double)> rations,
  List<Map<String, Object?>> typesAliment = const [],
}) {
  final hasard = Hasard(graine);
  final bandes = [
    {'id': uuidDe('bande-$prefixe-a-'), 'code': '$prefixe-A', 'stade': 'engraissement', 'initial': 200, 'courant': 190},
    {'id': uuidDe('bande-$prefixe-b-'), 'code': '$prefixe-B', 'stade': 'reproduction', 'initial': 300, 'courant': 280},
  ];
  final produits = [
    provende,
    {'id': uuidDe('produit-1-'), 'nom': 'Ivermectine 1 %', 'stock': 0},
  ];
  final fiches = <Map<String, Object?>>[];
  for (var b = 0; b < bandes.length; b++) {
    var premiere = true;
    for (final (mois, j) in [for (var d = 24; d <= 30; d++) (9, d), for (var d = 2; d <= 31; d++) (10, d)]) {
      // Le 20/10 (aujourd'hui) a toujours sa fiche : le formulaire du jour se compare.
      if (!(mois == 10 && j == 20) && hasard(10) < 4) continue;
      final morts = [hasard(4), hasard(3), hasard(3)];
      final dons = [hasard(2), hasard(2), hasard(2)];
      final ventile = b == 1 || hasard(3) != 0;
      fiches.add({
        'id': uuidDe('fiche-$b-$mois-$j-'),
        'bande': b,
        'date': jourDe(mois, j),
        'achat': hasard(3),
        'ne': hasard(12),
        'mort': morts.reduce((a, c) => a + c),
        'vente': hasard(4),
        'don': dons.reduce((a, c) => a + c),
        'effectif': 150 + hasard(150),
        'eff_m': hasard(5) == 0 ? null : hasard(20),
        'eff_f': hasard(5) == 0 ? null : hasard(60),
        'eff_sevres': hasard(5) == 0 ? null : hasard(90),
        'eff_smeres': hasard(5) == 0 ? null : hasard(40),
        'poids': hasard(3) == 0 ? null : 800 + hasard(3000),
        'traitement': hasard(6) == 0 ? 1 : null,
        'symptomes': [null, '', '0', 'Diarrhée', 'RAS'][hasard(5)],
        if (ventile) ...{
          'mort_repro': morts[0],
          'mort_sevre': morts[1],
          'mort_jeune': morts[2],
          'don_repro': dons[0],
          'don_sevre': dons[1],
          'don_jeune': dons[2],
          'passage': b == 1 ? hasard(3) : 0,
        },
        // B : départ mixte sur la première fiche (somme = effectif initial, aucune fiche avant).
        if (b == 1 && premiere) ...{'depart_repro': 100, 'depart_sevre': 120, 'depart_jeune': 80},
        // A : une fiche ancienne aux effectifs de catégorie saisis à la main (D6).
        if (b == 0 && premiere) ...{'cat_repro': 10, 'cat_sevre': 40, 'cat_jeune': 150},
      });
      premiere = false;
    }
  }
  return JeuFiches(
    codeEspece: codeEspece,
    bandes: bandes,
    produits: produits,
    fiches: fiches,
    soins: JeuFiches.soinsAuHasard(hasard, 2),
    typesAliment: typesAliment,
    rations: rations,
  );
}

/// La cascade du dépôt depuis la première fiche de chaque bande — la même que celle que le script PHP joue
/// (`RecordSaleOnFicheElevageAction::recalculerEnCascade`) : effectifs des jours suivants, catégories de la chaîne.
Future<void> cascaderTout(JeuFiches jeu, FicheJournaliereRepository depot) async {
  for (var b = 0; b < jeu.bandes.length; b++) {
    final dates = [for (final f in jeu.fiches) if (f['bande'] == b) f['date']! as String]..sort();
    if (dates.isNotEmpty) await depot.recalculerEnCascade(jeu.bandes[b]['id']! as String, DateTime.parse(dates.first));
  }
}

/// Complément PHP du rendu : le FORMULAIRE du jour de la bande (effectif final, taux, départ, rationnement tel
/// qu'affiché, autonomie alimentaire, encadrés d'information dans l'ordre).
const formulaireCategoriesPhp = r'''
if (! function_exists('texteSansIcones')) {
    // Le texte affiché : sans les noms d'icônes Material Symbols (ligatures « warning », « lock »…).
    function texteSansIcones($noeud): string {
        $t = '';
        foreach ((new DOMXPath($noeud->ownerDocument))->query(".//text()[not(ancestor::span[contains(@class, 'material-symbols')])]", $noeud) as $n) {
            $t .= $n->nodeValue;
        }
        return trim(preg_replace('/\s+/u', ' ', $t));
    }
}
$i = $composant->instance();
$cat = $i->categoriesJour;
$rations = [];
foreach ($x->query("//table[.//th[contains(., 'Provende Servie')]]/tbody/tr") as $tr) {
    $c = [];
    foreach ($tr->getElementsByTagName('td') as $td) {
        $entree = $td->getElementsByTagName('input');
        $c[] = $entree->length > 0 ? trim($entree->item(0)->getAttribute('value')) : texteDe($td);
    }
    $rations[] = $c;
}
$total = $x->query("//table[.//th[contains(., 'Provende Servie')]]/tfoot//td[last()]");
$autonomie = $x->query("//form//div[contains(@class, 'rounded-lg') and contains(., 'Autonomie alimentaire')][not(.//div[contains(@class, 'rounded-lg') and contains(., 'Autonomie alimentaire')])]");
$encadres = [];
foreach ($x->query("//form//div[@role or contains(., 'Cette bande porte déjà')][not(.//div[@role or contains(., 'Cette bande porte déjà')])]") as $d) {
    $t = texteSansIcones($d);
    if (! str_contains($t, 'Autonomie alimentaire') && ! str_contains($t, 'Transferts entre bandes')) {
        $encadres[] = $t;
    }
}
$s['formulaire'] = [
    'effectif_final' => (string) $i->effectifFinalCalc,
    'taux' => number_format($i->mortalityRateCalc, 1, ',', ' ').' %',
    'mode' => $cat['mode'],
    'depart_requis' => $cat['depart_requis'],
    'depart' => [$i->departRepro, $i->departSevre, $i->departJeune],
    'rations' => $rations,
    'total' => $total->length > 0 ? texteDe($total->item(0)) : null,
    'autonomie' => $autonomie->length > 0 ? texteSansIcones($autonomie->item(0)) : null,
    'encadres' => $encadres,
];
''';

/// Le texte d'un sous-arbre du poste, dans l'ordre de lecture, blancs réduits (comme `textContent` du web).
String texteDuPoste(WidgetTester tester, Finder racine) {
  final morceaux = <String>[];
  for (final t in tester.widgetList<Text>(find.descendant(of: racine, matching: find.byType(Text)))) {
    morceaux.add(t.data ?? t.textSpan!.toPlainText());
  }
  return morceaux.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _texte(WidgetTester tester, String cle) => tester.widget<Text>(find.byKey(Key(cle))).data!;

/// Le formulaire du jour affiché par l'écran du poste = celui que rend le VRAI composant web ([web] :
/// `formulaire` de [formulaireCategoriesPhp]). [clesRation] : clés des lignes du rationnement dans l'ordre du Blade ;
/// [emplacementsDepart] : ordre des trois champs du départ au Blade (`repro`, `sevre`, `jeune`).
void verifierFormulaire(
  WidgetTester tester,
  Map<String, dynamic> web, {
  required List<String> clesRation,
  required String bande,
}) {
  final f = (web['formulaire'] as Map).cast<String, dynamic>();
  expect(_texte(tester, 'effectif-final'), f['effectif_final'], reason: '$bande — effectif final');
  expect(_texte(tester, 'taux-mortalite-jour'), f['taux'], reason: '$bande — taux de mortalité du jour');
  final lignes = [for (final l in f['rations'] as List) (l as List).cast<String>()];
  expect(lignes, hasLength(clesRation.length));
  for (var i = 0; i < clesRation.length; i++) {
    final c = clesRation[i];
    expect(
      [
        _texte(tester, 'ration-libelle-$c'),
        _texte(tester, 'ration-effectif-$c'),
        _texte(tester, 'ration-normative-$c'),
        _texte(tester, 'ration-provende-$c'),
      ],
      lignes[i],
      reason: '$bande — rationnement, ligne $c',
    );
  }
  expect(_texte(tester, 'total-provende'), f['total'], reason: '$bande — total provende');
  expect(texteDuPoste(tester, find.byKey(const Key('autonomie-alimentaire'))), f['autonomie'], reason: '$bande — autonomie');
  expect(
    [for (final e in tester.widgetList<EncadreFiche>(find.byType(EncadreFiche))) e.texte.replaceAll(RegExp(r'\s+'), ' ')],
    (f['encadres'] as List).cast<String>(),
    reason: '$bande — encadrés',
  );
  expect(find.byKey(const Key('depart-modifiable')).evaluate().isNotEmpty, f['depart_requis'], reason: '$bande — départ requis');
}

/// Les trois champs du départ affichés (ordre `repro`, `sevre`, `jeune`) = `departRepro/Sevre/Jeune` du web.
void verifierDepart(WidgetTester tester, Map<String, dynamic> web, String bande) {
  final f = (web['formulaire'] as Map).cast<String, dynamic>();
  if (f['depart_requis'] != true) return;
  final attendu = [for (final v in f['depart'] as List) v == null ? '' : '$v'];
  final affiche = [
    for (final c in ['repro', 'sevre', 'jeune'])
      tester
          .widget<TextField>(find.descendant(of: find.byKey(Key('depart-$c')), matching: find.byType(TextField)))
          .controller!
          .text,
  ];
  expect(affiche, attendu, reason: '$bande — départ pré-rempli');
}
