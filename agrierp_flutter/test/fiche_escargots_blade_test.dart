import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/features/elevage/fiche_escargots_screen.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/mois_fiche.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fiches_especes_commun.dart';
import 'php_laravel.dart';

/// Ticket U12a — FICHE ESCARGOTS : LE BLADE FAIT FOI (doctrine, article 5 ; modèle : fiche Pondeuses, U11).
///
/// 1. **Lu dans le Blade** (`fiche-escargots.blade.php`) : sections dans leur ordre, libellés des champs, cartes,
///    colonnes du tableau du mois dans l'ordre, sections « en attente », textes d'aide — tous dans l'écran du poste ;
///    ce que le Blade n'a pas (« Réinitialiser », « Attribution Parcs… », le protocole du jour) n'y est plus.
/// 2. **Parité exécutée** : le VRAI composant `FicheEscargots` rend le tableau du mois (tous les jours,
///    « Traitements & Prophylaxie » compris), les quatre cartes et le PDF, sur deux bandes ; [MoisFiche] doit rendre
///    les MÊMES cellules ; l'écran affiche ces cartes et charge le jour touché.
void main() {
  final blade = bladeDe('fiche-escargots');
  const fichiers = ['lib/features/elevage/fiche_escargots_screen.dart', 'lib/features/elevage/elements_fiche.dart'];
  final saut = blade.existsSync() ? null : 'SAUT : vue Blade absente';

  group('lu dans le Blade', () {
    test('⚠️ U12a — les sections du Blade, dans son ordre, sont celles de l écran', () {
      final b = blade.readAsStringSync();
      final e = litterauxDe(fichiers);
      const sections = [
        'Module Héliciculture non activé',
        "Ce module est disponible mais désactivé par défaut. Un administrateur peut l'activer depuis Paramètres &gt; Modules Actifs.",
        '← Retour à Gestion Élevage',
        'Fiches Escargots - Héliciculture',
        "Suivi mensuel du cheptel d'escargots — ponte en terre, éclosion des naissains et engraissement.",
        'Exporter PDF',
        'Aucune bande active en héliciculture pour le moment.',
        'Créer une bande depuis Bandes &amp; Sujets →',
        'Saisie Journalière du Cheptel',
        'Bande :',
        'Date :',
        'Achats du jour',
        'Workflow Ponte en Terre &amp; Éclosion des Naissains',
        'Morts par catégorie',
        "mort(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.",
        'Dons par catégorie',
        "don(s) déjà enregistré(s) ce jour, sans répartition par catégorie : ils sont conservés tant qu'aucune répartition n'est saisie ci-dessous.",
        'Effectif Final du Jour',
        '= Effectif (J-1) + Achats/Naissains − (Morts + Ventes + Dons)',
        'Taux de Mortalité du Jour (%)',
        '= (Morts du Jour ÷ Effectif J-1) × 100',
        'Rationnement Farine Calcique &amp; Fourrage',
        'Poids Général Pesé (g)',
        'Entretien &amp; Hygrométrie',
        'Observations',
        'Enregistrer ce Jour',
      ];
      var precedent = -1;
      for (final s in sections) {
        final i = b.indexOf(s, precedent + 1);
        expect(i, greaterThan(precedent), reason: 'ordre du Blade : $s');
        precedent = i;
        expect(e, contains(texteBlade(s).toLowerCase()), reason: 'écran : $s');
      }
    }, skip: saut);

    test('U12a — chaque libellé de champ du Blade est dans l écran, avec les indices de saisie', () {
      final b = blade.readAsStringSync();
      final e = litterauxDe(fichiers);
      final libelles = etiquettesDe(b);
      expect(libelles, containsAll(['Œufs Pondus (en terre)', 'Reproducteur (Bordé)', 'Bordés']));
      for (final l in libelles) {
        attendreLibelle(e, l);
      }
      for (final m in RegExp(r'placeholder="([^"]+)"').allMatches(b)) {
        expect(e, contains(m[1]!.toLowerCase()), reason: 'indice ${m[1]}');
      }
    }, skip: saut);

    test('U12a — cartes, colonnes du tableau du mois dans l ordre, sections en attente : celles du Blade', () {
      final b = blade.readAsStringSync();
      final e = litterauxDe(fichiers);
      final cartes = [for (final m in RegExp(r'<x-kpi-card label="([^"]+)"').allMatches(b)) m[1]!.replaceAll('&#039;', "'")];
      expect(cartes, ['Effectif Total Vivant', 'Naissains Nés (mois)', "Taux d'Éclosion Naissains", 'Taux de Mortalité']);
      for (final c in cartes) {
        expect(e, contains(c.toLowerCase()), reason: c);
      }
      final colonnes = entetesDe(b);
      expect(colonnes, [
        'Date', 'Entrées', 'Sorties', 'Effectif Final du Jour', 'Taux Mort %', 'Poids Général (g)',
        'Traitements & Prophylaxie', 'Achat', 'Naissain Né', 'Mort', 'Vente', 'Don', 'Naissains', 'Engraiss.', 'Bordés',
        'Total',
      ]);
      for (final c in colonnes) {
        expect(e, contains(c.toLowerCase()), reason: c);
      }
      for (final m in RegExp(r'<x-module-pending label="([^"]+)" since="([^"]+)"').allMatches(b)) {
        expect(e, contains(m[1]!.toLowerCase()), reason: m[1]);
        expect(e, contains(m[2]!.replaceAll('&#039;', "'").toLowerCase()), reason: m[2]);
      }
      // `components/module-pending.blade.php` : la phrase et « Prévu : ».
      expect(e, contains('sera alimenté en données réelles dès sa mise en œuvre.'));
      // Ce que la maquette avait et que le Blade n'a pas : absent des LITTÉRAUX de l'écran.
      final source = litterauxDe(['lib/features/elevage/fiche_escargots_screen.dart']);
      for (final absent in [
        'Réinitialiser',
        'Attribution Parcs',
        'Soins, Hygrométrie',
        'Pondoirs',
        'Naissains Nés (Éclosion jour)',
        'Traitements & Prophylaxie Automatiques',
      ]) {
        expect(b.toLowerCase(), isNot(contains(absent.toLowerCase())), reason: absent);
        expect(source, isNot(contains(absent.toLowerCase())), reason: absent);
      }
      // Le Blade des escargots n'a pas de protocole du jour : l'écran ne valide aucun traitement.
      expect(b, isNot(contains('x-prophylaxie-du-jour')));
      expect(source, isNot(contains("valider l'administration")));
    }, skip: saut);
  });

  /// Deux bandes d'escargots, fiches de fin septembre et d'octobre (avec des jours sans fiche), pesées, effectifs
  /// saisis parfois inconnus, traitements, symptômes, soins du registre.
  JeuFiches jeu() {
    final hasard = Hasard(2027);
    final bandes = [
      {'id': uuidDe('bande-esc-a-'), 'code': 'ESC-A', 'stade': 'engraissement', 'initial': 900, 'courant': 870},
      {'id': uuidDe('bande-esc-b-'), 'code': 'ESC-B', 'stade': 'reproduction', 'initial': 400, 'courant': 391},
    ];
    final produits = [
      {'id': uuidDe('produit-0-'), 'nom': 'Farine calcique', 'stock': 10},
      {'id': uuidDe('produit-1-'), 'nom': 'Vitamines escargots', 'stock': 0},
    ];
    final fiches = <Map<String, Object?>>[];
    for (var b = 0; b < bandes.length; b++) {
      // ⚠️ Pas de fiche le 1er octobre : sur SQLite, le `whereBetween` du web compare des CHAÎNES et l'exclut ; MySQL
      // (la production) l'inclut — comme le poste.
      for (final (mois, j) in [for (var d = 24; d <= 30; d++) (9, d), for (var d = 2; d <= 31; d++) (10, d)]) {
        if (hasard(10) < 4) continue;
        fiches.add({
          'id': uuidDe('fiche-$b-$mois-$j-'),
          'bande': b,
          'date': jourDe(mois, j),
          'achat': hasard(4),
          'ne': hasard(30),
          'mort': hasard(5) == 0 ? 0 : hasard(9),
          'vente': hasard(5),
          'don': hasard(3),
          'effectif': hasard(15) == 0 ? 0 : 300 + hasard(700),
          'ponte': hasard(4) == 0 ? null : hasard(200),
          'eff_m': hasard(5) == 0 ? null : hasard(300),
          'eff_f': hasard(5) == 0 ? null : hasard(500),
          'eff_sevres': hasard(5) == 0 ? null : hasard(80),
          'poids': hasard(3) == 0 ? null : 5 + hasard(20),
          'traitement': hasard(6) == 0 ? hasard(2) : null,
          'symptomes': [null, '', '0', 'Coquilles molles', 'RAS'][hasard(5)],
        });
      }
    }
    return JeuFiches(
      codeEspece: 'helico',
      bandes: bandes,
      produits: produits,
      fiches: fiches,
      soins: JeuFiches.soinsAuHasard(hasard, 2),
    );
  }

  final maintenant = DateTime(2026, 10, 20, 10);

  test('parité exécutée U12a : tableau du mois, cartes et PDF = ceux du web', () async {
    final j = jeu();
    final web = renduWeb(j, classe: r'App\Livewire\Elevage\FicheEscargots', propriete: 'bandeId');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await j.inserer(db);
    final depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    final bandes = MoisFiche.bandesDe(EspeceFiche.escargots, await depot.bandesActives());
    expect([for (final b in bandes) b.code], ['ESC-A', 'ESC-B']);

    for (var b = 0; b < bandes.length; b++) {
      final w = web[b];
      expect(w['bande'], bandes[b].code);
      final d = await MoisFiche.charger(db, espece: EspeceFiche.escargots, bandes: bandes, bande: bandes[b], maintenant: maintenant);
      final lignes = [for (final l in w['lignes'] as List) (l as List).cast<String>()];
      expect(lignes, hasLength(31), reason: 'tous les jours d octobre');
      expect(d.jours, hasLength(31));
      for (var i = 0; i < 31; i++) {
        expect([d.jours[i].date, ...d.jours[i].cellules(EspeceFiche.escargots)], lignes[i], reason: '${w['bande']} — ligne ${lignes[i][0]}');
      }
      expect(d.indicateurs, (w['cartes'] as List).cast<String>(), reason: '${w['bande']} — cartes');
      expect(d.document.titre, 'Fiche Escargots — Suivi Mensuel');
      expect(d.document.sousTitre, w['periode']);
      expect([for (final l in d.document.lignes) (l as DonneesDocument).cellules], [
        for (final l in w['pdf'] as List) (l as List).cast<String>(),
      ], reason: '${w['bande']} — PDF');
      expect(DocumentOfficiel.nomPdf(d.document, maintenant), w['fichier']);
    }

    // La grille couvre ce qu'elle prétend couvrir.
    final a = [for (final l in web[0]['lignes'] as List) (l as List).cast<String>()];
    expect(a.where((l) => l[1] == '—'), isNotEmpty, reason: 'un jour sans fiche');
    expect(a.where((l) => l[1] != '—' && l[6] == '—'), isNotEmpty, reason: 'un effectif saisi inconnu');
    expect(a.where((l) => l[1] != '—' && l[11] == '—'), isNotEmpty, reason: 'une fiche sans pesée');
    expect(a.where((l) => l[11] != '—'), isNotEmpty, reason: 'une pesée');
    expect(a.where((l) => l[12].contains(', ')), isNotEmpty, reason: 'deux soins le même jour');
  }, skip: sautSansPhp(), timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('l écran affiche les cartes du web et charge le jour touché dans le tableau', (tester) async {
    final j = jeu();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await j.inserer(db);
    final depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: FicheEscargotsScreen(
          depot: depot,
          soins: SoinsRepository(database: db, deviceId: 'poste-test'),
          maintenant: () => maintenant,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final attendu = await MoisFiche.charger(
      db,
      espece: EspeceFiche.escargots,
      bandes: MoisFiche.bandesDe(EspeceFiche.escargots, await depot.bandesActives()),
      bande: (await depot.bandesActives()).first,
      maintenant: maintenant,
    );
    final libelles = ['Effectif Total Vivant', 'Naissains Nés (mois)', "Taux d'Éclosion Naissains", 'Taux de Mortalité'];
    for (var i = 0; i < 4; i++) {
      expect(
        find.descendant(of: find.byKey(Key('kpi-${libelles[i]}')), matching: find.text(attendu.indicateurs[i])),
        findsOneWidget,
        reason: libelles[i],
      );
    }
    expect(find.text('20/10/2026'), findsOneWidget, reason: 'jour du jour');
    expect(find.byKey(const Key('tableau-mois')), findsOneWidget);
    await tester.ensureVisible(find.text('05/10'));
    await tester.tap(find.text('05/10'));
    await tester.pumpAndSettle();
    expect(find.text('05/10/2026'), findsOneWidget, reason: 'le jour touché est chargé');
    await db.close();
  });

  testWidgets('module Héliciculture éteint : la carte du Blade seule, son lien de retour', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    var retour = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FicheEscargotsScreen(
          depot: depot,
          soins: SoinsRepository(database: db, deviceId: 'poste-test'),
          onRetourGestion: () => retour++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Module Héliciculture non activé'), findsOneWidget);
    expect(find.text('Fiches Escargots - Héliciculture'), findsNothing);
    await tester.tap(find.text('← Retour à Gestion Élevage'));
    expect(retour, 1);
    await db.close();
  });
}
