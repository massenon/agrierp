import 'dart:io';

import 'package:agrierp/core/comptabilite/exercice_choisi.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/export/document_officiel.dart';
import 'package:agrierp/core/widgets/bandeau_exercice.dart';
import 'package:agrierp/features/elevage/elements_fiche.dart';
import 'package:agrierp/features/elevage/fiche_escargots_screen.dart';
import 'package:agrierp/features/elevage/fiche_journaliere_repository.dart';
import 'package:agrierp/features/elevage/fiche_lapins_screen.dart';
import 'package:agrierp/features/elevage/fiche_pondeuses_screen.dart';
import 'package:agrierp/features/elevage/fiche_porcs_screen.dart';
import 'package:agrierp/features/elevage/fiche_reproducteurs_screen.dart';
import 'package:agrierp/features/elevage/mois_fiche.dart';
import 'package:agrierp/features/elevage/production_oeufs_service.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'fiches_categories_commun.dart';
import 'fiches_especes_commun.dart';
import 'php_laravel.dart';

/// Ticket EX8 (EF12, PRD `docs/prd/exercices-comptables.md` § 4) — FICHES D'ÉLEVAGE DES MOIS PASSÉS AU POSTE.
///
/// Le web d'abord (`AvecMoisDeFiche`, `x-mois-de-fiche`, `x-bandeau-lecture-seule`, `FichesMoisPassesTest`), puis le
/// poste identique :
///  1. **Parité exécutée** : le VRAI composant Livewire de chaque fiche (Lapins, Porcs, Reproducteurs, Escargots),
///     après « ‹ » (`moisPrecedent`), rend le tableau de SEPTEMBRE, ses cartes, son PDF (sous-titre, nom de fichier),
///     le libellé du mois et le jour choisi ; le poste ([MoisFiche] sur le jour choisi, [MoisDeFiche]) rend les MÊMES ;
///     « › » (`moisSuivant`) ramène au jour même.
///  2. **Écrans** (les cinq fiches, Pondeuses comprise) : « ‹ » / « › », libellé du mois, date choisie, « › » inerte sur
///     le mois en cours ; un jour d'un exercice CLOS : le bandeau d'EX7 (fusion EX7 + EX8), formulaire inerte,
///     rien n'est écrit.
///  3. **Garde-fou de fidélité** : les libellés du poste sont ceux des composants Blade, et chaque fiche Blade les
///     emploie.
void main() {
  final maintenant = DateTime(2026, 10, 20, 10);

  // ── Les jeux (ceux des tests U12a, mêmes graines) ─────────────────────────────────────────────────────────────
  JeuFiches lapins() => jeuCategories(
    codeEspece: 'cuniculture',
    prefixe: 'LAP',
    graine: 2029,
    provende: {'id': uuidDe('produit-0-'), 'nom': 'Provende lapins', 'stock': 12.5, 'unite': 'sac', 'espece': true},
    typesAliment: [
      {'id': uuidDe('type-0-'), 'nom': 'Granulé lapin', 'sac': 50},
    ],
    rations: const [('Lapin reproducteur', 180), ('Lapin de chair', 120)],
  );
  JeuFiches porcs() => jeuCategories(
    codeEspece: 'porciculture',
    prefixe: 'POR',
    graine: 2030,
    provende: {'id': uuidDe('produit-0-'), 'nom': 'Aliment porc croissance', 'stock': 340.5, 'unite': 'kg', 'espece': true},
    rations: const [('Porcelet', 350), ('Truie / Verrat reproducteur', 2500)],
  );
  JeuFiches avicole(String code, List<Map<String, Object?>> bandes, int graine) {
    final hasard = Hasard(graine);
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
          'eff_m': code == 'helico' && hasard(5) != 0 ? hasard(300) : null,
          'eff_f': code == 'helico' && hasard(5) != 0 ? hasard(500) : null,
          'eff_sevres': code == 'helico' && hasard(5) != 0 ? hasard(80) : null,
          'poids': hasard(3) == 0 ? null : 900 + hasard(1500),
          'symptomes': [null, '', 'RAS'][hasard(3)],
        });
      }
    }
    return JeuFiches(codeEspece: code, bandes: bandes, produits: const [], fiches: fiches, soins: const []);
  }

  JeuFiches reproducteurs() => avicole('aviculture', [
    {'id': uuidDe('bande-rep-a-'), 'code': 'REP-A', 'stade': 'reproduction', 'initial': 120, 'courant': 112},
    {'id': uuidDe('bande-rep-b-'), 'code': 'GOL-B', 'stade': 'engraissement', 'initial': 500, 'courant': 488},
  ], 2028);
  JeuFiches escargots() => avicole('helico', [
    {'id': uuidDe('bande-esc-a-'), 'code': 'ESC-A', 'stade': 'engraissement', 'initial': 900, 'courant': 870},
    {'id': uuidDe('bande-esc-b-'), 'code': 'ESC-B', 'stade': 'reproduction', 'initial': 400, 'courant': 391},
  ], 2027);
  JeuFiches pondeuses() => avicole('aviculture', [
    {'id': uuidDe('bande-pon-a-'), 'code': 'PON-A', 'stade': 'ponte', 'initial': 300, 'courant': 296},
  ], 2031);

  /// Complément PHP du rendu : « ‹ » puis le mois passé tel que le web le rend, puis « › ».
  const moisPassePhp = r'''
$composant->call('moisPrecedent');
$dp = new DOMDocument();
@$dp->loadHTML('<?xml encoding="utf-8"?>'.$composant->html());
$xp = new DOMXPath($dp);
$cartesP = [];
foreach ($xp->query("//span[contains(@class, 'md:text-2xl')]") as $span) {
    $cartesP[] = texteDe($span);
}
$pdfP = new DOMDocument();
@$pdfP->loadHTML('<?xml encoding="utf-8"?>'.view('exports.fiche-elevage', ['entries' => $composant->instance()->monthlyEntries->values()])->render());
$s['passe'] = [
    'lignes' => cellulesDe($xp, "//table[.//th[contains(., 'Taux Mort')]]/tbody/tr"),
    'cartes' => $cartesP,
    'pdf' => cellulesDe(new DOMXPath($pdfP), '//tbody/tr'),
    'mois' => $composant->instance()->libelleMois,
    'jour' => $composant->get('selectedDate'),
    'courant' => $composant->instance()->estMoisCourant,
    'periode' => Carbon\Carbon::parse($composant->get('selectedDate'))->translatedFormat('F Y'),
];
// Le nom du fichier téléchargé : un autre rendu (l'instance d'un appel de téléchargement n'est plus relue), par un
// compte qui a `view-elevage` (`exportFichePdf` l'exige).
if (! App\Models\User::where('username', 'animalier-ex8')->exists()) {
    Illuminate\Support\Facades\Artisan::call('db:seed', ['--class' => Database\Seeders\RolesAndPermissionsSeeder::class, '--force' => true]);
    $animalier = App\Models\User::create(['name' => 'Animalier', 'username' => 'animalier-ex8', 'email' => 'animalier-ex8@olouwachegoun.bj',
        'password' => bcrypt('AgriERP@2026'), 'is_active' => true]);
    $animalier->assignRole('animalier');
    Illuminate\Support\Facades\Auth::login($animalier);
}
$t = Livewire\Livewire::test(@@CLASSE@@::class)->set('@@PROPRIETE@@', $bande->id)->call('moisPrecedent')->call('exportFichePdf');
$s['passe']['fichier'] = data_get($t->effects, 'download.name');
$composant->call('moisSuivant');
$s['retour'] = $composant->get('selectedDate');
$s['courant_retour'] = $composant->instance()->estMoisCourant;
''';

  final especes = <(String, EspeceFiche, String, String, JeuFiches Function(), bool)>[
    ('Lapins', EspeceFiche.lapins, r'App\Livewire\Elevage\FicheLapins', 'bandeId', lapins, true),
    ('Porcs', EspeceFiche.porcs, r'App\Livewire\Elevage\FichePorcs', 'bandeId', porcs, true),
    ('Reproducteurs', EspeceFiche.reproducteurs, r'App\Livewire\Elevage\FicheReproducteurs', 'selectedLotId', reproducteurs, false),
    ('Escargots', EspeceFiche.escargots, r'App\Livewire\Elevage\FicheEscargots', 'bandeId', escargots, false),
  ];

  group('parité exécutée — le mois passé du web = celui du poste', () {
    for (final (nom, espece, classe, propriete, jeu, categories) in especes) {
      test('EX8 — $nom : « ‹ » rend septembre 2026 (tableau, cartes, PDF, libellé), « › » ramène au jour même', () async {
        final j = jeu();
        final extra = moisPassePhp.replaceAll('@@CLASSE@@', classe).replaceAll('@@PROPRIETE@@', propriete);
        final web = renduWeb(j, classe: classe, propriete: propriete, extra: extra, cascade: categories);
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await j.inserer(db);
        final depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
        if (categories) await cascaderTout(j, depot);
        final bandes = MoisFiche.bandesDe(espece, await depot.bandesActives());

        for (final bande in bandes) {
          final w = web.firstWhere((w) => w['bande'] == bande.code);
          final passe = w['passe'] as Map<String, dynamic>;
          final raison = '$nom ${bande.code}';

          // Navigation : mêmes jours choisis, même libellé, même « mois en cours ».
          final jour = MoisDeFiche.precedent(maintenant);
          expect(passe['jour'], '2026-09-01', reason: raison);
          expect([jour.year, jour.month, jour.day], [2026, 9, 1], reason: raison);
          expect(MoisDeFiche.libelle(jour), passe['mois'], reason: raison);
          expect(MoisDeFiche.estMoisCourant(jour, maintenant), passe['courant'], reason: raison);
          final retour = MoisDeFiche.suivant(jour, maintenant)!;
          expect(w['retour'], '2026-10-20', reason: raison);
          expect([retour.year, retour.month, retour.day], [2026, 10, 20], reason: raison);
          expect(MoisDeFiche.estMoisCourant(retour, maintenant), w['courant_retour'], reason: raison);
          expect(MoisDeFiche.suivant(retour, maintenant), isNull, reason: '$raison : jamais au-delà du mois en cours');

          // Le mois de septembre, celui du jour choisi.
          final d = await MoisFiche.charger(db, espece: espece, bandes: bandes, bande: bande, maintenant: jour);
          final lignes = [for (final l in passe['lignes'] as List) (l as List).cast<String>()];
          expect(lignes, hasLength(30), reason: '$raison : septembre a 30 jours');
          expect(lignes.where((l) => l.skip(1).any((c) => c != '—')), isNotEmpty, reason: '$raison : des fiches');
          for (var i = 0; i < 30; i++) {
            expect([d.jours[i].date, ...d.jours[i].cellules(espece)], lignes[i], reason: '$raison — ligne ${lignes[i][0]}');
          }
          expect(d.indicateurs, (passe['cartes'] as List).cast<String>(), reason: '$raison — cartes du mois');
          expect([for (final l in d.document.lignes) (l as DonneesDocument).cellules], [
            for (final l in passe['pdf'] as List) (l as List).cast<String>(),
          ], reason: '$raison — PDF');
          expect(d.document.sousTitre, passe['periode'], reason: raison);
          expect(DocumentOfficiel.nomPdf(d.document, maintenant), passe['fichier'], reason: '$raison : fiche-2026-09.pdf');
        }
      }, skip: sautSansPhp(), timeout: const Timeout(Duration(minutes: 3)));
    }
  });

  // ── Les écrans ──────────────────────────────────────────────────────────────────────────────────────────────────

  Future<AppDatabase> base(JeuFiches j, {bool exercices = false}) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await j.inserer(db);
    if (exercices) {
      await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          id: uuidDe('exercice-2025-'),
          year: 2025,
          startDate: Value(DateTime(2025, 1, 1)),
          endDate: Value(DateTime(2025, 12, 31)),
          status: const Value('cloture'),
        ),
      );
      await db.into(db.fiscalYears).insert(
        FiscalYearsCompanion.insert(
          id: uuidDe('exercice-2026-'),
          year: 2026,
          startDate: Value(DateTime(2026, 1, 1)),
          endDate: Value(DateTime(2026, 12, 31)),
          status: const Value('ouvert'),
        ),
      );
    }
    return db;
  }

  Widget ecran(String nom, AppDatabase db, DateTime quand) {
    final depot = FicheJournaliereRepository(database: db, deviceId: 'poste-test');
    final soins = SoinsRepository(database: db, deviceId: 'poste-test');
    return switch (nom) {
      'Lapins' => FicheLapinsScreen(depot: depot, soins: soins, maintenant: () => quand),
      'Porcs' => FichePorcsScreen(depot: depot, soins: soins, maintenant: () => quand),
      'Reproducteurs' => FicheReproducteursScreen(depot: depot, soins: soins, maintenant: () => quand),
      'Escargots' => FicheEscargotsScreen(depot: depot, soins: soins, maintenant: () => quand),
      _ => FichePondeusesScreen(
        depot: depot,
        soins: soins,
        production: ProductionOeufsService(database: db),
        maintenant: () => quand,
      ),
    };
  }

  final jeux = <String, JeuFiches Function()>{
    'Lapins': lapins,
    'Porcs': porcs,
    'Reproducteurs': reproducteurs,
    'Escargots': escargots,
    'Pondeuses': pondeuses,
  };

  String texte(WidgetTester tester, String cle) => tester.widget<Text>(find.byKey(Key(cle))).data!;

  for (final nom in jeux.keys) {
    testWidgets('EX8 — $nom : « ‹ » / « › », libellé du mois, jour choisi ; « › » inerte sur le mois en cours', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1700, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = await base(jeux[nom]!());
      await tester.pumpWidget(MaterialApp(home: ecran(nom, db, maintenant)));
      await tester.pumpAndSettle();

      expect(texte(tester, 'mois-affiche'), 'Octobre 2026');
      expect(texte(tester, 'date-choisie'), '20/10/2026');
      expect(find.text(MoisDeFiche.etiquette), findsOneWidget);
      await tester.tap(find.byKey(const Key('mois-suivant')));
      await tester.pumpAndSettle();
      expect(texte(tester, 'date-choisie'), '20/10/2026', reason: 'pas de mois à venir');

      await tester.tap(find.byKey(const Key('mois-precedent')));
      await tester.pumpAndSettle();
      expect(texte(tester, 'mois-affiche'), 'Septembre 2026');
      expect(texte(tester, 'date-choisie'), '01/09/2026');
      // Le tableau du mois (écran large) porte les jours de SEPTEMBRE.
      expect(find.text('30/09'), findsWidgets);
      expect(find.text('31/10'), findsNothing);
      expect(find.byKey(const Key('lecture-seule')), findsNothing, reason: 'aucun exercice clos connu');

      await tester.tap(find.byKey(const Key('mois-suivant')));
      await tester.pumpAndSettle();
      expect(texte(tester, 'mois-affiche'), 'Octobre 2026');
      expect(texte(tester, 'date-choisie'), '20/10/2026', reason: 'retour sur le jour même');
      await tester.pumpWidget(const SizedBox());
      await db.close();
    });

    testWidgets('EX8 — $nom : un jour d un exercice clos se consulte en lecture seule, rien n est écrit', (tester) async {
      tester.view.physicalSize = const Size(1700, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = await base(jeux[nom]!(), exercices: true);
      final avant = (await db.select(db.livestockDailyEntries).get()).length;
      await tester.pumpWidget(MaterialApp(home: ecran(nom, db, DateTime(2026, 1, 15, 10))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lecture-seule')), findsNothing);
      expect(find.byKey(const Key('formulaire-lecture-seule')), findsNothing);

      await tester.tap(find.byKey(const Key('mois-precedent')));
      await tester.pumpAndSettle();
      expect(texte(tester, 'mois-affiche'), 'Décembre 2025');
      expect(find.byKey(const Key('lecture-seule')), findsOneWidget);
      // Fusion EX7 + EX8 : le bandeau d'EX7 (`x-bandeau-lecture-seule`), même texte, pour l'exercice du JOUR.
      expect(find.byType(BandeauLectureSeule), findsOneWidget);
      expect(
        find.text("Exercice 2025 clôturé — lecture seule. Les saisies se font dans l'exercice 2026."),
        findsOneWidget,
      );
      expect(find.text('Passer à 2026'), findsOneWidget);
      expect(find.byKey(const Key('formulaire-lecture-seule')), findsOneWidget);
      final bouton = find.byKey(const Key('bouton-enregistrer'));
      await tester.ensureVisible(bouton);
      await tester.tap(bouton, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect((await db.select(db.livestockDailyEntries).get()).length, avant, reason: 'formulaire inerte');

      // « Passer à 2026 » (`passerALExerciceDeSaisie`) : la fiche revient au jour de saisie, formulaire rouvert.
      await tester.tap(find.byKey(const Key('lecture-seule-passer')));
      await tester.pumpAndSettle();
      expect(texte(tester, 'mois-affiche'), 'Janvier 2026');
      expect(texte(tester, 'date-choisie'), '15/01/2026');
      expect(find.byKey(const Key('lecture-seule')), findsNothing);
      expect(find.byKey(const Key('formulaire-lecture-seule')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await db.close();
    });

    testWidgets('fusion EX7 + EX8 — $nom : l exercice du jour AFFICHÉ et clos, le bandeau du haut suffit', (tester) async {
      tester.view.physicalSize = const Size(1700, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = await base(jeux[nom]!(), exercices: true);
      final service = ExerciceChoisi(db, maintenant: () => DateTime(2026, 1, 15, 10));
      expect(await service.choisir(2025), isTrue);
      await tester.pumpWidget(
        PorteeExerciceChoisi(
          notifier: service,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const BandeauExercice(),
                  Expanded(child: ecran(nom, db, DateTime(2026, 1, 15, 10))),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mois-precedent')));
      await tester.pumpAndSettle();
      expect(texte(tester, 'mois-affiche'), 'Décembre 2025');
      const bandeau = "Exercice 2025 clôturé — lecture seule. Les saisies se font dans l'exercice 2026.";
      expect(find.text(bandeau), findsOneWidget, reason: 'une seule fois : celui du haut');
      expect(find.byKey(const Key('bandeau-exercice')), findsOneWidget);
      expect(find.byKey(const Key('lecture-seule')), findsNothing);
      expect(find.byKey(const Key('formulaire-lecture-seule')), findsOneWidget, reason: 'formulaire inerte quand même');
      await tester.pumpWidget(const SizedBox());
      await db.close();
    });
  }

  // ── Garde-fou de fidélité ───────────────────────────────────────────────────────────────────────────────────────

  test('EX8 — libellés du poste = composants Blade, et chaque fiche Blade les emploie', () {
    final composants = Directory('$dossierLaravel/resources/views/components');
    if (!composants.existsSync()) {
      markTestSkipped('SAUT : dépôt Laravel absent');
      return;
    }
    final mois = File('${composants.path}/mois-de-fiche.blade.php').readAsStringSync();
    for (final l in [MoisDeFiche.etiquette, MoisDeFiche.infoPrecedent, MoisDeFiche.infoSuivant]) {
      expect(mois, contains(l), reason: l);
    }
    expect(mois, contains('wire:click="moisPrecedent"'));
    expect(mois, contains('wire:click="moisSuivant"'));
    // Fusion EX7 + EX8 : plus de bandeau propre aux fiches — celui d'EX7, un seul composant des deux côtés.
    expect(File('${composants.path}/fiche-lecture-seule.blade.php').existsSync(), isFalse);
    final lecture = File('${composants.path}/bandeau-lecture-seule.blade.php').readAsStringSync();
    expect(lecture, contains('Passer à {{'));
    for (final f in ['fiche-pondeuses', 'fiche-reproducteurs', 'fiche-lapins', 'fiche-porcs', 'fiche-escargots']) {
      final b = bladeDe(f).readAsStringSync();
      expect(b, contains('<x-mois-de-fiche'), reason: f);
      expect(b, contains(r'<x-bandeau-lecture-seule :bandeau="$this->bandeauLectureSeule" action="passerALExerciceDeSaisie" />'), reason: f);
      expect(b, contains(r'<fieldset @disabled($this->motifLectureSeule)'), reason: f);
      expect(b, isNot(contains('now()->startOfMonth()')), reason: '$f : plus de mois figé sur le mois en cours');
    }
    // Les cinq écrans du poste emploient la navigation et la lecture seule.
    for (final f in [
      'fiche_categories_vue.dart',
      'fiche_reproducteurs_screen.dart',
      'fiche_escargots_screen.dart',
      'fiche_pondeuses_screen.dart',
    ]) {
      final source = File('lib/features/elevage/$f').readAsStringSync();
      expect(source, contains('MoisDeFiche'), reason: f);
      expect(source, contains('LectureSeuleDuJour.charger('), reason: f);
      expect(source, contains('maintenant: _jour,'), reason: '$f : le mois affiché est celui du jour choisi');
    }
  });
}
