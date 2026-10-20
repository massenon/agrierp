import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_reproducteurs_screen.dart';
import 'package:agrierp/features/elevage/mois_fiche.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fiches_especes_commun.dart';
import 'php_laravel.dart';

/// Ticket U12a — FICHE REPRODUCTEURS : LE BLADE FAIT FOI (doctrine, article 5 ; modèle : fiche Pondeuses, U11).
///
/// 1. **Lu dans le Blade** (`fiche-reproducteurs.blade.php`) : sections dans leur ordre, libellés des champs, cartes
///    et leurs légendes, colonnes du tableau du mois dans l'ordre, note du tableau — tous dans l'écran du poste ; ce
///    que le Blade n'a pas (« Réinitialiser », « Attribution Bâtiments… », « Taille Échantillon ») n'y est plus.
/// 2. **Parité exécutée** : le VRAI composant `FicheReproducteurs` rend le tableau du mois (tous les jours), les
///    quatre cartes et le PDF, sur deux bandes hors ponte (la bande de ponte n'est pas comptée) ; [MoisFiche] doit
///    rendre les MÊMES cellules.
void main() {
  final blade = bladeDe('fiche-reproducteurs');
  const fichiers = ['lib/features/elevage/fiche_reproducteurs_screen.dart', 'lib/features/elevage/elements_fiche.dart'];
  final saut = blade.existsSync() ? null : 'SAUT : vue Blade absente';

  group('lu dans le Blade', () {
    test('⚠️ U12a — les sections du Blade, dans son ordre, sont celles de l écran', () {
      final b = blade.readAsStringSync();
      final e = litterauxDe(fichiers);
      const sections = [
        'Fiches Volailles - Reproducteurs, Poussins &amp; Goliath',
        'Suivi de la reproduction avicole, couvoir, incubation, éclosion, poussins et poulets de chair.',
        'Exporter PDF',
        'Aucune bande active (Reproducteurs/Goliath/Poussins) pour le moment.',
        'Créer une bande depuis Bandes &amp; Sujets →',
        'Saisie Journalière Couvoir &amp; Suivi Chair',
        'Date :',
        'Bande / Lot Concerné',
        'Achats du jour',
        'Workflow Couvoir &amp; Éclosion (Incubation → Poussins Nés)',
        'Morts par catégorie',
        'Dons par catégorie',
        'Effectif Final',
        '= Effectif (J-1) + Achats/Poussins Nés − (Morts + Ventes + Dons)',
        'Taux de Mortalité du Jour (%)',
        'x-ration-volaille',
        'Poids Général Pesé (g)',
        'Traitements &amp; Prophylaxie',
        'Observations',
        'Enregistrer ce Jour',
      ];
      var precedent = -1;
      for (final s in sections) {
        final i = b.indexOf(s, precedent + 1);
        expect(i, greaterThan(precedent), reason: 'ordre du Blade : $s');
        precedent = i;
        if (s == 'x-ration-volaille') continue;
        expect(e, contains(texteBlade(s).toLowerCase()), reason: 'écran : $s');
      }
      // `<x-ration-volaille … ligne-cle="des reproducteurs" />`, et le titre du composant.
      expect(b, contains('ligne-cle="des reproducteurs"'));
      expect(e, contains('des reproducteurs'));
      expect(e, contains('rationnement & provende servie par stade (en grammes g/j)'));
    }, skip: saut);

    test('U12a — chaque libellé de champ du Blade est dans l écran, avec les indices de saisie', () {
      final b = blade.readAsStringSync();
      final e = litterauxDe(fichiers);
      final libelles = etiquettesDe(b);
      expect(libelles, containsAll(['Œufs Couvés (Mis en incubation)', 'Repro', 'Poulet', 'Poussin']));
      for (final l in libelles) {
        attendreLibelle(e, l);
      }
      for (final m in RegExp(r'placeholder="([^"]+)"').allMatches(b)) {
        expect(e, contains(m[1]!.toLowerCase()), reason: 'indice ${m[1]}');
      }
      // L'option du sélecteur : « code (Stade — N têtes) ».
      expect(b, contains('{{ \$lot->code }} ({{ ucfirst(\$lot->stage) }} — {{ \$lot->current_quantity }} têtes)'));
    }, skip: saut);

    test('U12a — cartes et légendes, colonnes du tableau du mois dans l ordre, note : celles du Blade', () {
      final b = blade.readAsStringSync();
      final e = litterauxDe(fichiers);
      final cartes = [
        for (final m in RegExp(r'<x-kpi-card label="([^"]+)".*?caption="([^"]+)"').allMatches(b))
          (m[1]!.replaceAll('&#039;', "'"), m[2]!.replaceAll('&amp;', '&')),
      ];
      expect([for (final c in cartes) c.$1], [
        'Effectif Total Vivant',
        "Taux d'Éclosion Couvoir",
        'Poussins Nés (Éclosion)',
        'Taux de Mortalité',
      ]);
      for (final (libelle, legende) in cartes) {
        expect(e, contains(libelle.toLowerCase()), reason: libelle);
        expect(e, contains(legende.toLowerCase()), reason: legende);
      }
      final colonnes = entetesDe(b);
      expect(colonnes, [
        'Date', 'Couvoir', 'Morts (total)', 'Effectif Final', 'Taux Mort %', 'Poids Général (g)', 'Couvés', 'Nés',
        'Repro+Poulet+Poussin',
      ]);
      for (final c in colonnes) {
        expect(e, contains(c.toLowerCase()), reason: c);
      }
      final note = texteBlade(RegExp(r'<p class="text-\[10px\] text-outline p-sm border-t[^"]*">(.*?)</p>', dotAll: true).firstMatch(b)![1]!);
      expect(e, contains(note.toLowerCase()), reason: note);
      final source = litterauxDe(['lib/features/elevage/fiche_reproducteurs_screen.dart']);
      for (final absent in ['Réinitialiser', 'Attribution Bâtiments', 'Taille Échantillon', 'Traitements & Vaccins Avicoles']) {
        expect(b.toLowerCase(), isNot(contains(absent.toLowerCase())), reason: absent);
        expect(source, isNot(contains(absent.toLowerCase())), reason: absent);
      }
    }, skip: saut);
  });

  /// Deux bandes avicoles hors ponte (reproduction, chair en engraissement) et une bande de PONTE, que la fiche ne
  /// compte pas ; fiches de fin septembre et d'octobre, couvées, pesées.
  JeuFiches jeu() {
    final hasard = Hasard(2028);
    final bandes = [
      {'id': uuidDe('bande-rep-a-'), 'code': 'REP-A', 'stade': 'reproduction', 'initial': 120, 'courant': 112},
      {'id': uuidDe('bande-rep-b-'), 'code': 'GOL-B', 'stade': 'engraissement', 'initial': 500, 'courant': 488},
      {'id': uuidDe('bande-rep-c-'), 'code': 'PON-C', 'stade': 'ponte', 'initial': 300, 'courant': 300},
    ];
    final fiches = <Map<String, Object?>>[];
    for (var b = 0; b < bandes.length; b++) {
      for (final (mois, j) in [for (var d = 24; d <= 30; d++) (9, d), for (var d = 2; d <= 31; d++) (10, d)]) {
        if (hasard(10) < 4) continue;
        fiches.add({
          'id': uuidDe('fiche-$b-$mois-$j-'),
          'bande': b,
          'date': jourDe(mois, j),
          'achat': hasard(3),
          'ne': hasard(40),
          'mort': hasard(5) == 0 ? 0 : hasard(7),
          'vente': hasard(4),
          'don': hasard(3),
          'effectif': hasard(15) == 0 ? 0 : 80 + hasard(450),
          'ponte': hasard(3) == 0 ? null : hasard(60),
          'poids': hasard(3) == 0 ? null : 900 + hasard(1500),
        });
      }
    }
    return JeuFiches(codeEspece: 'aviculture', bandes: bandes, produits: const [], fiches: fiches, soins: const []);
  }

  final maintenant = DateTime(2026, 10, 20, 10);

  test('parité exécutée U12a : tableau du mois, cartes et PDF = ceux du web', () async {
    final j = jeu();
    final web = renduWeb(j, classe: r'App\Livewire\Elevage\FicheReproducteurs', propriete: 'selectedLotId');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await j.inserer(db);
    final depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    final bandes = MoisFiche.bandesDe(EspeceFiche.reproducteurs, await depot.bandesActives());
    expect([for (final b in bandes) b.code], ['GOL-B', 'REP-A'], reason: 'la bande de ponte n est pas de cette fiche');

    for (final bande in bandes) {
      final w = web.firstWhere((w) => w['bande'] == bande.code);
      final d = await MoisFiche.charger(db, espece: EspeceFiche.reproducteurs, bandes: bandes, bande: bande, maintenant: maintenant);
      final lignes = [for (final l in w['lignes'] as List) (l as List).cast<String>()];
      expect(lignes, hasLength(31));
      for (var i = 0; i < 31; i++) {
        expect([d.jours[i].date, ...d.jours[i].cellules(EspeceFiche.reproducteurs)], lignes[i], reason: '${w['bande']} — ligne ${lignes[i][0]}');
      }
      expect(d.indicateurs, (w['cartes'] as List).cast<String>(), reason: '${w['bande']} — cartes');
      expect(d.document.titre, 'Fiche Reproducteurs (Aviculture) — Suivi Mensuel');
      expect(d.document.sousTitre, w['periode']);
      expect([for (final l in d.document.lignes) (l as DonneesDocument).cellules], [
        for (final l in w['pdf'] as List) (l as List).cast<String>(),
      ], reason: '${w['bande']} — PDF');
      expect(DocumentOfficiel.nomPdf(d.document, maintenant), w['fichier']);
    }
    final a = [for (final l in web[0]['lignes'] as List) (l as List).cast<String>()];
    expect(a.where((l) => l[4] == '—'), isNotEmpty, reason: 'un jour sans fiche');
    expect(a.where((l) => l[6] != '—'), isNotEmpty, reason: 'une pesée');
    expect(a.where((l) => l[4] != '—' && l[1] == '—'), isNotEmpty, reason: 'une fiche sans œuf couvé');
  }, skip: sautSansPhp(), timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('l écran affiche les cartes et légendes du web, la bande « code (Stade — N têtes) »', (tester) async {
    final j = jeu();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await j.inserer(db);
    final depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FicheReproducteursScreen(
          depot: depot,
          soins: SoinsRepository(database: db, deviceId: 'poste-test'),
          maintenant: () => maintenant,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bandes = MoisFiche.bandesDe(EspeceFiche.reproducteurs, await depot.bandesActives());
    final attendu = await MoisFiche.charger(
      db,
      espece: EspeceFiche.reproducteurs,
      bandes: bandes,
      bande: bandes.first,
      maintenant: maintenant,
    );
    final libelles = ['Effectif Total Vivant', "Taux d'Éclosion Couvoir", 'Poussins Nés (Éclosion)', 'Taux de Mortalité'];
    for (var i = 0; i < 4; i++) {
      expect(
        find.descendant(of: find.byKey(Key('kpi-${libelles[i]}')), matching: find.text(attendu.indicateurs[i])),
        findsOneWidget,
        reason: libelles[i],
      );
    }
    expect(find.text('Seuil critique < 5%'), findsOneWidget);
    expect(find.text('GOL-B (Engraissement — 488 têtes)'), findsOneWidget);
    expect(find.byKey(const Key('note-ventilation-morts')), findsOneWidget);
    await db.close();
  });
}
