import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/features/elevage/categorie_ration_lapin.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:agrierp/features/elevage/mois_fiche.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fiches_categories_commun.dart';
import 'fiches_especes_commun.dart';
import 'php_laravel.dart';

/// Ticket U12a — FICHE LAPINS : LE BLADE FAIT FOI (doctrine, article 5 ; modèle : fiche Pondeuses, U11).
///
/// 1. **Lu dans le Blade** (`fiche-lapins.blade.php`) : sections dans leur ordre, libellés des champs, cartes,
///    colonnes du tableau du mois dans l'ordre, encadrés (D6, départ, motifs), autonomie alimentaire — tous dans
///    l'écran du poste (`fiche_lapins_screen.dart` + la vue commune `fiche_categories_vue.dart`) ; ce que le Blade n'a
///    pas (« Réinitialiser », « Attribution Cages… », « Alimenté par la caisse ») n'y est plus.
/// 2. **Parité exécutée** : le VRAI composant `FicheLapins` rend, sur deux bandes (sans chaîne avec D6, avec chaîne),
///    le tableau du mois, les cartes, le PDF et le FORMULAIRE du jour (effectif final, taux, départ pré-rempli,
///    rationnement par catégorie, autonomie alimentaire, encadrés) ; le poste doit rendre les MÊMES valeurs.
void main() {
  final blade = bladeDe('fiche-lapins');
  const fichiers = [
    'lib/features/elevage/fiche_lapins_screen.dart',
    'lib/features/elevage/fiche_categories_vue.dart',
    // BS1 : le composant d'autonomie est partagé avec le tiroir de « Bandes & Sujets » (un seul composant, comme au web).
    'lib/features/elevage/autonomie_alimentaire_carte.dart',
    'lib/features/elevage/elements_fiche.dart',
  ];
  final saut = blade.existsSync() ? null : 'SAUT : vue Blade absente';

  group('lu dans le Blade', () {
    test('⚠️ U12a — les sections du Blade, dans son ordre, sont celles de l écran', () {
      final b = blade.readAsStringSync();
      final e = litterauxDe(fichiers);
      const sections = [
        'Fiches Lapins - Cuniculture',
        'Fiche de suivi mensuel du cheptel — transcription fidèle du registre de la ferme.',
        'Exporter PDF',
        'Aucune bande active en cuniculture pour le moment.',
        'Créer une bande depuis Bandes &amp; Sujets →',
        'Saisie Journalière du Cheptel',
        'Bande :',
        'Date :',
        'Cette bande porte déjà des effectifs par catégorie saisis à la main (fiche du',
        "Ils ne sont pas repris comme effectif de départ : l'effectif de départ ci-dessous est déduit du stade de la bande, corrigez-le si besoin avant d'enregistrer.",
        'Achats du jour',
        'Nés (Mise bas)',
        'Morts par catégorie',
        'Dons par catégorie',
        'Sevrage du jour (Sous-mères → Jeune)',
        'Effectif de départ par catégorie (déduit du stade de la bande)',
        'Effectif au DÉBUT du jour, avant les mouvements du jour, pré-rempli automatiquement depuis le stade de la bande.',
        'Corrigez-le seulement pour une bande mixte ; il est verrouillé au premier enregistrement.',
        'Effectif de départ par catégorie (verrouillé)',
        'Effectif de départ fixé le',
        "Jour antérieur à l'effectif de départ fixé le",
        'Fiche ancienne non ventilée par catégorie :',
        "non ventilé(s) y sont enregistrés. Ventilez-les ci-dessus avant d'enregistrer.",
        'Effectif Mâles',
        'Effectif Final du Jour (Calculé dynamique)',
        '= Effectif (J-1) + Achats/Nés − (Morts + Ventes + Dons)',
        'Taux de Mortalité du Jour (%)',
        'Rationnement &amp; Provende Servie par Catégorie (en Grammes g/j)',
        'TOTAL PROVENDE SERVIE DU JOUR (CUMUL EN GRAMMES)',
        'x-autonomie-alimentaire',
        'Poids Général Pesé (g)',
        'Taille Échantillon',
        'Poids Moyen Constaté',
        'Traitements &amp; Prophylaxie',
        'Observations / Notes Additionnelles',
        'Enregistrer ce Jour',
      ];
      var precedent = -1;
      for (final s in sections) {
        final i = b.indexOf(s, precedent + 1);
        expect(i, greaterThan(precedent), reason: 'ordre du Blade : $s');
        precedent = i;
        if (s == 'x-autonomie-alimentaire') continue;
        expect(e, contains(texteBlade(s).toLowerCase()), reason: 'écran : $s');
      }
    }, skip: saut);

    test('U12a — chaque libellé de champ du Blade est dans l écran, avec les indices de saisie', () {
      final b = blade.readAsStringSync();
      final e = litterauxDe(fichiers);
      final libelles = etiquettesDe(b);
      expect(libelles, containsAll(['Sous-mères', 'Effectif Femelles', 'S/Mères', 'Ventes (POS, réel)']));
      for (final l in libelles) {
        attendreLibelle(e, l);
      }
      for (final m in RegExp(r'placeholder="([^"]+)"').allMatches(b)) {
        expect(e, contains(m[1]!.toLowerCase()), reason: 'indice ${m[1]}');
      }
    }, skip: saut);

    test('U12a — cartes, colonnes du tableau du mois dans l ordre, rationnement, autonomie : ceux du Blade', () {
      final b = blade.readAsStringSync();
      final e = litterauxDe(fichiers);
      final cartes = [for (final m in RegExp(r'<x-kpi-card label="([^"]+)"').allMatches(b)) m[1]!];
      expect(cartes, ['Effectif Total Vivant', 'Géniteurs (M/F)', 'Naissances du Mois', 'Taux de Mortalité']);
      for (final c in cartes) {
        expect(e, contains(c.toLowerCase()), reason: c);
      }
      final colonnes = entetesDe(b);
      expect(colonnes, [
        'Date', 'Entrées', 'Sorties', 'Effectif Final du Jour', 'Taux Mort %', 'Poids Général (g)',
        'Traitements & Prophylaxie', 'Achat', 'Né', 'Mort', 'Vente', 'Don', 'M', 'F', 'Jeunes', 'S/Mères', 'Total',
      ]);
      for (final c in colonnes) {
        expect(e, contains(c.toLowerCase()), reason: c);
      }
      // Rationnement : en-têtes, puis les trois lignes dans l'ordre du Blade.
      expect(entetesDe(b, apres: '<thead class="bg-surface-zebra text-outline'), [
        'Catégorie', 'Effectif', 'Ration Normative', 'Provende Servie (g)',
      ]);
      final lignes = RegExp(r'<td class="px-md py-xs font-bold text-brand-forest">([^<]+)</td>').allMatches(b).map((m) => m[1]).toList();
      expect(lignes, ['Reproducteur', 'Jeune', 'Sous-mères']);
      expect(lignes, [for (final c in FicheLapinsScreen.config.libellesRation.values) c]);
      expect(b, contains('filiere="cuniculture"'));
      expect(FicheLapinsScreen.config.filiere, 'cuniculture');
      // `components/autonomie-alimentaire.blade.php` : ses cinq états, mot pour mot.
      final composant = bladeDe('../../components/autonomie-alimentaire').readAsStringSync();
      for (final t in [
        'Autonomie alimentaire : aucun stock de provende suivi',
        "n'existe en catalogue avec un stock suivi : créez-le et approvisionnez-vous. La fiche s'enregistre quand même.",
        'Autonomie alimentaire : rupture de stock',
        "Kg) : approvisionnez-vous. La fiche s'enregistre quand même.",
        'Commander Stock',
        "Kg en stock) — la consommation du jour est inconnue tant que les effectifs par catégorie le sont.",
        'Alerte critique - Autonomie alimentaire',
        'jours de consommation théorique du cheptel actif ! Approvisionnez-vous.',
        'Kg en stock).',
      ]) {
        expect(composant, contains(t), reason: 'composant : $t');
        expect(e, contains(t.toLowerCase()), reason: 'écran : $t');
      }
      final source = litterauxDe(fichiers.take(2).toList());
      for (final absent in ['Réinitialiser', 'Attribution Cages', 'Alimenté par la caisse', 'Journée enregistrée sur ce poste']) {
        expect(b.toLowerCase(), isNot(contains(absent.toLowerCase())), reason: absent);
        expect(source, isNot(contains(absent.toLowerCase())), reason: absent);
      }
    }, skip: saut);
  });

  JeuFiches jeu() => jeuCategories(
    codeEspece: 'cuniculture',
    prefixe: 'LAP',
    graine: 2029,
    provende: {'id': uuidDe('produit-0-'), 'nom': 'Provende lapins', 'stock': 12.5, 'unite': 'sac', 'espece': true},
    typesAliment: [
      {'id': uuidDe('type-0-'), 'nom': 'Granulé lapin', 'sac': 50},
    ],
    // Barème partiel : Reproducteur et Jeune au barème, Sous-mères en ration de secours (30 g/j).
    rations: const [('Reproducteur', 140), ('Jeune', 65)],
  );

  final maintenant = DateTime(2026, 10, 20, 10);
  Map<String, dynamic>? webMemo;
  List<Map<String, dynamic>> web() {
    final r = renduWeb(
      jeu(),
      classe: r'App\Livewire\Elevage\FicheLapins',
      propriete: 'bandeId',
      extra: formulaireCategoriesPhp,
      cascade: true,
    );
    webMemo = {'r': r};
    return r;
  }

  Future<(AppDatabase, FicheJournaliereRepository)> poste() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final j = jeu();
    await j.inserer(db);
    final depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    await cascaderTout(j, depot);
    return (db, depot);
  }

  test('parité exécutée U12a : tableau du mois, cartes et PDF = ceux du web', () async {
    final w = web();
    final (db, depot) = await poste();
    addTearDown(db.close);
    final bandes = MoisFiche.bandesDe(EspeceFiche.lapins, await depot.bandesActives());
    for (var b = 0; b < bandes.length; b++) {
      expect(w[b]['bande'], bandes[b].code);
      final d = await MoisFiche.charger(db, espece: EspeceFiche.lapins, bandes: bandes, bande: bandes[b], maintenant: maintenant);
      final lignes = [for (final l in w[b]['lignes'] as List) (l as List).cast<String>()];
      expect(lignes, hasLength(31));
      for (var i = 0; i < 31; i++) {
        expect([d.jours[i].date, ...d.jours[i].cellules(EspeceFiche.lapins)], lignes[i], reason: '${bandes[b].code} — ligne ${lignes[i][0]}');
      }
      expect(d.indicateurs, (w[b]['cartes'] as List).cast<String>(), reason: '${bandes[b].code} — cartes');
      expect(d.document.titre, 'Fiche Lapins — Suivi Mensuel');
      expect(d.document.sousTitre, w[b]['periode']);
      expect([for (final l in d.document.lignes) (l as DonneesDocument).cellules], [
        for (final l in w[b]['pdf'] as List) (l as List).cast<String>(),
      ], reason: '${bandes[b].code} — PDF');
      expect(DocumentOfficiel.nomPdf(d.document, maintenant), w[b]['fichier']);
    }
    // La grille couvre ce qu'elle prétend couvrir : bande sans chaîne avec D6 (départ requis), bande à chaîne.
    final fa = (w[0]['formulaire'] as Map).cast<String, dynamic>();
    final fb = (w[1]['formulaire'] as Map).cast<String, dynamic>();
    expect(fa['depart_requis'], isTrue);
    expect((fa['encadres'] as List).first, startsWith('Cette bande porte déjà'));
    expect(fb['mode'], 'chaine');
    expect(fb['autonomie'], contains('jours'));
  }, skip: sautSansPhp(), timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('parité exécutée U12a : le formulaire du jour de chaque bande = celui du web', (tester) async {
    if (sautSansPhp() != null) return;
    final w = webMemo?['r'] as List<Map<String, dynamic>>? ?? web();
    final (db, depot) = await tester.runAsync(poste) as (AppDatabase, FicheJournaliereRepository);
    tester.view.physicalSize = const Size(1440, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FicheLapinsScreen(
          depot: depot,
          soins: SoinsRepository(database: db, deviceId: 'poste-test'),
          maintenant: () => maintenant,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cles = [CategorieRationLapin.reproducteur, CategorieRationLapin.chair, CategorieRationLapin.sousMeres];
    verifierFormulaire(tester, w[0], clesRation: cles, bande: 'LAP-A');
    verifierDepart(tester, w[0], 'LAP-A');

    // Seconde bande, par le sélecteur « Bande : ».
    await tester.tap(find.byKey(const Key('bande-fiche')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LAP-B').last);
    await tester.pumpAndSettle();
    verifierFormulaire(tester, w[1], clesRation: cles, bande: 'LAP-B');
    expect(find.byKey(const Key('depart-verrouille')), findsOneWidget);
    await db.close();
  });
}
