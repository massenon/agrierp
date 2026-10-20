import 'dart:io';

import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_tokens.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/core/widgets/toast_agri.dart';
import 'package:agrierp/features/elevage/gestion_elevage_repository.dart';
import 'package:agrierp/features/elevage/gestion_elevage_screen.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'package:agrierp/core/theme/symboles_agri.dart';

/// Ticket H4 — GESTION ÉLEVAGE DU POSTE ALIGNÉ SUR LE BLADE.
///
/// Maître : `app/Livewire/Elevage/GestionElevage.php` et `resources/views/livewire/elevage/gestion-elevage.blade.php`
/// (+ `components/kpi-card.blade.php`, `components/nav-card.blade.php`).
///
/// 🔴 Avant (audit du 19/10/2026, § 3) : aucun KPI, aucun intertitre, une seule colonne, titres et descriptions des
/// cartes recopiés de la maquette, « Bandes & Sujets » et trois accès rapides absents, Escargots MASQUÉ quand le web le
/// GRISE. Les libellés ci-dessous sont LUS DANS LE BLADE : un renommage au web fait rougir ce test.
void main() {
  late AppDatabase db;

  /// Jour figé du calcul « du mois » — le web prend `now()`.
  final maintenant = DateTime(2026, 10, 19, 14, 30);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async {
    ToastAgri.toutRetirer();
    await db.close();
  });

  final blade = File('$dossierLaravel/resources/views/livewire/elevage/gestion-elevage.blade.php');
  final kpiBlade = File('$dossierLaravel/resources/views/components/kpi-card.blade.php');
  // `testWidgets` ne prend qu'un booléen : la raison du saut est le Blade introuvable (ticket A7, `AGRIERP_LARAVEL`).
  final sansLaravel = !blade.existsSync();

  String lireBlade() => blade.readAsStringSync();
  String decoder(String s) => s.replaceAll('&amp;', '&').trim();

  /// Cible de chaque `href` du Blade au poste ; `null` = aucun écran au poste (« Bandes & Sujets »).
  const cibles = <String, EcranPoste?>{
    '/gestion-bandes': null,
    '/fiche-lapins': EcranPoste.ficheElevage,
    '/fiche-volailles-pondeuses': EcranPoste.fichePondeuses,
    '/fiche-volailles-reproducteurs': EcranPoste.ficheReproducteurs,
    '/fiche-porcs': EcranPoste.fichePorcs,
    "{{ route('elevage.fiche-escargots') }}": EcranPoste.ficheEscargots,
    '/suivi-reproduction': EcranPoste.suiviReproduction,
    '/soins-vaccins-hub': EcranPoste.soinsEtVaccins,
    '/elevage-dashboard': EcranPoste.dashboardElevage,
    '/transferts-bandes': EcranPoste.transfertsBandes,
  };

  /// Nom Material Symbols du Blade → icône du poste.
  const icones = <String, IconData>{
    'pets': SymbolesAgri.pets,
    'layers': SymbolesAgri.layers,
    'warning': SymbolesAgri.warning,
    'monitor_heart': SymbolesAgri.monitor_heart,
    'cruelty_free': SymbolesAgri.cruelty_free,
    'egg': SymbolesAgri.egg,
    'bug_report': SymbolesAgri.bug_report,
    'favorite': SymbolesAgri.favorite,
    'vaccines': SymbolesAgri.vaccines,
    'dashboard': SymbolesAgri.dashboard,
    'swap_horiz': SymbolesAgri.swap_horiz,
  };

  /// Couleurs de `kpi-card.blade.php` : `$variants[$color]` → (liseré, icône).
  const variantes = <String, (Color, Color)>{
    'emerald': (AgriColors.brandEmerald, AgriColors.brandEmerald),
    'maize': (AgriColors.accentYellow, AgriColors.brandForest),
    'red': (AgriColors.errorRed, AgriColors.errorRed),
    'blue': (AgriColors.infoBlue, AgriColors.infoBlue),
  };

  /// Cartes `<x-nav-card>` du Blade, dans l'ordre : (href, icône, titre, description littérale).
  List<(String, String, String, String)> cartesBlade() {
    final motif = RegExp(r'<x-nav-card href="([^"]+)" icon="(\w+)" title="([^"]+)" (:?)description="([^"]+)"');
    return [
      for (final m in motif.allMatches(lireBlade()))
        (
          m.group(1)!,
          m.group(2)!,
          decoder(m.group(3)!),
          // `:description="$this->bandesActives.' bande(s) …'"` : seule la partie littérale est lue.
          m.group(4) == ':' ? RegExp(r"'([^']+)'").firstMatch(m.group(5)!)!.group(1)! : decoder(m.group(5)!),
        ),
    ];
  }

  // ── Jeu de données fait à la main ────────────────────────────────────────────────────────────────────────────────
  const bandeA = 'aaaaaaaa-0000-4000-8000-000000000001'; // active, 50 têtes
  const bandeB = 'bbbbbbbb-0000-4000-8000-000000000002'; // CLÔTURÉE, 30 têtes : jamais comptée
  const bandeC = 'cccccccc-0000-4000-8000-000000000003'; // archivée (is_active = false), 20 têtes : jamais comptée
  const bandeD = 'dddddddd-0000-4000-8000-000000000004'; // active, 19 têtes, aucune fiche avant le mois

  Future<void> bande(String id, String code, {required String statut, required bool active, required int initial, required int courant}) =>
      db.into(db.livestockLots).insert(
        LivestockLotsCompanion.insert(
          id: id,
          code: code,
          speciesId: 'espece-lapins',
          status: Value(statut),
          isActive: Value(active),
          initialQuantity: Value(initial),
          currentQuantity: Value(courant),
        ),
      );

  var n = 0;
  Future<void> fiche(String lot, DateTime jour, {required int mort, required int effectifFinal}) {
    n++;
    return db.into(db.livestockDailyEntries).insert(
      LivestockDailyEntriesCompanion.insert(
        id: 'eeeeeeee-0000-4000-8000-${n.toString().padLeft(12, '0')}',
        deviceId: 'poste-test',
        updatedAt: jour,
        lotId: lot,
        entryDate: jour,
        mort: Value(mort),
        effectifFinal: Value(effectifFinal),
      ),
    );
  }

  /// Taux attendu, calculé à la main sur les fiches d'OCTOBRE des bandes VIVANTES (A et D) :
  ///
  /// | Fiche            | Morts | `previousEffectif()`                                   |
  /// |------------------|-------|--------------------------------------------------------|
  /// | A 01/10          | 2     | 58 — `effectif_final` de la fiche du 30/09 (veille)    |
  /// | A 02/10          | 1     | 56 — `effectif_final` de la fiche du 01/10             |
  /// | D 05/10          | 1     | 20 — aucune fiche antérieure : `initial_quantity`      |
  ///
  /// Σ morts = 4 ; Σ effectifs de départ = 58 + 56 + 20 = 134 ; 4 / 134 × 100 = 2,985… → **2,99 %**.
  ///
  /// Hors calcul : la fiche A du 30/09 (5 morts, mois précédent), la fiche A du 01/11 (mois suivant), les fiches de B
  /// (clôturée, 10 morts) et de C (archivée, 7 morts). Effectif Total Vivant = 50 + 19 = **69** ; Bandes Actives = **2**.
  Future<void> jeuALaMain() async {
    await bande(bandeA, 'LAP-A', statut: 'actif', active: true, initial: 60, courant: 50);
    await bande(bandeB, 'LAP-B', statut: 'cloture', active: true, initial: 40, courant: 30);
    await bande(bandeC, 'LAP-C', statut: 'actif', active: false, initial: 25, courant: 20);
    await bande(bandeD, 'LAP-D', statut: 'actif', active: true, initial: 20, courant: 19);

    await fiche(bandeA, DateTime(2026, 9, 30), mort: 5, effectifFinal: 58);
    await fiche(bandeA, DateTime(2026, 10, 1), mort: 2, effectifFinal: 56);
    await fiche(bandeA, DateTime(2026, 10, 2), mort: 1, effectifFinal: 55);
    await fiche(bandeA, DateTime(2026, 11, 1), mort: 9, effectifFinal: 46);
    await fiche(bandeD, DateTime(2026, 10, 5), mort: 1, effectifFinal: 19);
    await fiche(bandeB, DateTime(2026, 10, 3), mort: 10, effectifFinal: 30);
    await fiche(bandeC, DateTime(2026, 10, 4), mort: 7, effectifFinal: 20);
  }

  Future<void> helico({required bool actif}) => db.into(db.modulesConfig).insert(
    ModulesConfigCompanion.insert(id: 'ffffffff-0000-4000-8000-000000000001', speciesCode: 'helico', isEnabled: Value(actif)),
  );

  GestionElevageRepository depot() => GestionElevageRepository(database: db, horloge: () => maintenant);

  Future<void> monter(WidgetTester t, {Size taille = const Size(1400, 2000), void Function(EcranPoste)? onOuvrir}) async {
    t.view.physicalSize = taille;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: GestionElevageScreen(onOuvrir: onOuvrir ?? (_) {}, depot: depot()),
      ),
    );
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
  }

  // ── (a) Libellés lus dans le Blade ───────────────────────────────────────────────────────────────────────────────
  group('(a) libellés du Blade', () {
    testWidgets('sous-titre, intertitres, KPI (libellé, icône, couleur, sous-texte) lus dans le Blade', (t) async {
      final source = lireBlade();
      await t.runAsync(jeuALaMain);
      await monter(t);

      final sousTitre = RegExp(r'<p class="text-xs text-outline mt-xs">([^<]+)</p>').firstMatch(source)!.group(1)!;
      expect(find.text(decoder(sousTitre)), findsOneWidget);

      // `uppercase` du Blade : le texte du DOM garde sa casse, l'écran l'affiche en capitales.
      final intertitres = [for (final m in RegExp(r'<h3[^>]*>([^<]+)</h3>').allMatches(source)) decoder(m.group(1)!)];
      expect(intertitres, ['Registres par Espèce', 'Accès Rapides — Élevage & Soins']);
      for (final i in intertitres) {
        expect(find.text(i.toUpperCase()), findsOneWidget, reason: 'intertitre « $i »');
      }

      final kpis = RegExp(r'<x-kpi-card label="([^"]+)"\s+icon="(\w+)"\s+color="(\w+)"').allMatches(source).toList();
      expect(kpis, hasLength(4));
      final cartes = t.widgetList<CarteKpi>(find.byType(CarteKpi)).toList();
      expect([for (final c in cartes) c.libelle], [for (final m in kpis) m.group(1)!], reason: 'mêmes KPI, même ordre');
      for (var i = 0; i < kpis.length; i++) {
        final (lisere, icone) = variantes[kpis[i].group(3)!]!;
        expect(cartes[i].icone, icones[kpis[i].group(2)!], reason: kpis[i].group(1));
        expect(cartes[i].couleurLisere, lisere, reason: kpis[i].group(1));
        expect(cartes[i].couleurIcone, icone, reason: kpis[i].group(1));
      }

      // Sous-textes : `caption` littéraux, branche « avec données » du taux, et KPI en attente.
      final legendes = [for (final m in RegExp(r' caption="([^"]+)"').allMatches(source)) m.group(1)!];
      expect(legendes, hasLength(2));
      final seuil = RegExp(r"\? '(Seuil normal[^']+)'").firstMatch(source)!.group(1)!;
      final depuis = RegExp(r'pending-since="([^"]+)"').firstMatch(source)!.group(1)!;
      final attente = RegExp(r'(Disponible après) \{\{').firstMatch(kpiBlade.readAsStringSync())!.group(1)!;
      expect([for (final c in cartes) c.legende], [...legendes, '$attente $depuis', seuil]);
      expect(cartes[2].valeur, '—', reason: 'KPI en attente : « — », jamais 0');
    }, skip: sansLaravel);

    testWidgets('cartes « Registres par Espèce » et « Accès Rapides » : icône, titre et description du Blade', (t) async {
      final cartes = cartesBlade();
      expect(cartes, hasLength(10), reason: '6 registres (Escargots actif) + 4 accès rapides');
      await t.runAsync(() async {
        await jeuALaMain();
        await helico(actif: true);
      });
      await monter(t);

      for (final (href, icone, titre, description) in cartes) {
        expect(cibles.containsKey(href), isTrue, reason: 'cible inconnue pour $href');
        final cible = cibles[href];
        final carte = find.byKey(Key(cible == null ? 'carte-bandes-sujets' : 'carte-${cible.name}'));
        expect(carte, findsOneWidget, reason: titre);
        expect(find.descendant(of: carte, matching: find.text(titre)), findsOneWidget, reason: titre);
        // « Bandes & Sujets » : le nombre de bandes vivantes précède la partie littérale du Blade.
        final texte = cible == null ? '2$description' : description;
        expect(find.descendant(of: carte, matching: find.text(texte)), findsOneWidget, reason: titre);
        expect(find.descendant(of: carte, matching: find.byIcon(icones[icone]!)), findsOneWidget, reason: titre);
      }
    }, skip: sansLaravel);

    testWidgets('Escargots GRISÉ (et non masqué) quand l héliciculture est désactivée, texte du Blade', (t) async {
      final description = RegExp(r'>Fiches Escargots</p>\s*<p class="text-\[11px\] text-outline">([^<]+)</p>')
          .firstMatch(lireBlade())!
          .group(1)!;
      await t.runAsync(() => helico(actif: false));
      await monter(t);

      final carte = find.byKey(Key('carte-${EcranPoste.ficheEscargots.name}'));
      expect(carte, findsOneWidget);
      expect(find.descendant(of: carte, matching: find.text('Fiches Escargots')), findsOneWidget);
      expect(find.descendant(of: carte, matching: find.text(decoder(description))), findsOneWidget);
      // Grisé : icône `text-outline`, et non émeraude.
      final icone = t.widget<Icon>(find.descendant(of: carte, matching: find.byIcon(SymbolesAgri.bug_report)));
      expect(icone.color, AgriColors.outline);
      // Les autres espèces restent : le Blade ne conditionne QUE l'héliciculture.
      for (final ecran in [EcranPoste.ficheElevage, EcranPoste.fichePondeuses, EcranPoste.ficheReproducteurs, EcranPoste.fichePorcs]) {
        expect(find.byKey(Key('carte-${ecran.name}')), findsOneWidget, reason: ecran.name);
      }
    }, skip: sansLaravel);

    testWidgets('grille 1 / 2 / 3 colonnes selon la largeur de l ÉCRAN (`grid-cols-1 sm:grid-cols-2 lg:grid-cols-3`)', (t) async {
      for (final (largeur, colonnes) in [(600.0, 1), (800.0, 2), (1300.0, 3)]) {
        await monter(t, taille: Size(largeur, 4000));
        final abscisses = {
          for (final e in [EcranPoste.ficheElevage, EcranPoste.fichePondeuses, EcranPoste.ficheReproducteurs])
            t.getTopLeft(find.byKey(Key('carte-${e.name}'))).dx.round(),
          t.getTopLeft(find.byKey(const Key('carte-bandes-sujets'))).dx.round(),
        };
        expect(abscisses, hasLength(colonnes), reason: 'largeur $largeur');
      }
    });
  });

  // ── (b) KPI calculés ─────────────────────────────────────────────────────────────────────────────────────────────
  group('(b) KPI calculés comme `GestionElevage.php`', () {
    test('jeu fait à la main : 69 têtes, 2 bandes, 2,99 % (voir le tableau de `jeuALaMain`)', () async {
      await jeuALaMain();
      final k = await depot().charger();

      expect(k.effectifTotal, 69, reason: '50 + 19 : la bande clôturée (30) et l archivée (20) ne comptent pas');
      expect(k.bandesActives, 2);
      expect(k.tauxMortaliteMois, 2.99);
      expect(GestionElevageRepository.formaterTaux(k.tauxMortaliteMois), '2,99 %');
    });

    test('aucune bande vivante ou aucune fiche du mois : « — », jamais 0', () async {
      var k = await depot().charger();
      expect(k.tauxMortaliteMois, isNull);
      expect(GestionElevageRepository.formaterTaux(k.tauxMortaliteMois), '—');

      await bande(bandeA, 'LAP-A', statut: 'actif', active: true, initial: 60, courant: 50);
      await fiche(bandeA, DateTime(2026, 9, 30), mort: 5, effectifFinal: 58);
      k = await depot().charger();
      expect(k.tauxMortaliteMois, isNull, reason: 'seule une fiche de septembre existe');
    });

    test('`number_format(…, 0, \',\', \' \')` et `number_format(…, 2, \',\', \' \')`', () {
      expect(GestionElevageRepository.formaterEntier(0), '0');
      expect(GestionElevageRepository.formaterEntier(1234567), '1 234 567');
      expect(GestionElevageRepository.formaterTaux(12.5), '12,50 %');
      expect(GestionElevageRepository.formaterTaux(1234.5), '1 234,50 %');
    });

    test('`ModuleConfig::isEnabled(\'helico\')` : ligne absente = désactivé, comme au web', () async {
      expect((await depot().charger()).helicoActif, isFalse);
      await helico(actif: true);
      expect((await depot().charger()).helicoActif, isTrue);
    });

    testWidgets('l écran affiche les valeurs et les sous-textes du calcul', (t) async {
      await t.runAsync(jeuALaMain);
      await monter(t);
      final cartes = t.widgetList<CarteKpi>(find.byType(CarteKpi)).toList();
      expect([for (final c in cartes) c.valeur], ['69', '2', '—', '2,99 %']);
    });

    testWidgets('sans fiche du mois : taux « — » et sous-texte de l absence', (t) async {
      await monter(t);
      final taux = t.widgetList<CarteKpi>(find.byType(CarteKpi)).last;
      expect(taux.valeur, '—');
      expect(taux.legende, 'Aucune fiche journalière saisie ce mois-ci');
    });
  });

  // ── (c) Navigation ───────────────────────────────────────────────────────────────────────────────────────────────
  group('(c) navigation', () {
    testWidgets('chaque Accès Rapide ouvre son écran', (t) async {
      final ouverts = <EcranPoste>[];
      await monter(t, onOuvrir: ouverts.add);
      final attendus = [EcranPoste.suiviReproduction, EcranPoste.soinsEtVaccins, EcranPoste.dashboardElevage, EcranPoste.transfertsBandes];
      for (final e in attendus) {
        await t.tap(find.byKey(Key('carte-${e.name}')));
        await t.pump();
      }
      expect(ouverts, attendus);
    });

    testWidgets('chaque registre ouvre sa fiche, Escargots grisé compris (le lien du web reste actif)', (t) async {
      final ouverts = <EcranPoste>[];
      await monter(t, onOuvrir: ouverts.add);
      final attendus = [
        EcranPoste.ficheElevage,
        EcranPoste.fichePondeuses,
        EcranPoste.ficheReproducteurs,
        EcranPoste.fichePorcs,
        EcranPoste.ficheEscargots,
      ];
      for (final e in attendus) {
        await t.tap(find.byKey(Key('carte-${e.name}')));
        await t.pump();
      }
      expect(ouverts, attendus);
    });

    testWidgets('« Bandes & Sujets » : aucun écran au poste, un avertissement renvoie à l application web', (t) async {
      final ouverts = <EcranPoste>[];
      await monter(t, onOuvrir: ouverts.add);
      await t.tap(find.byKey(const Key('carte-bandes-sujets')));
      await t.pump();

      expect(ouverts, isEmpty);
      expect(find.text(GestionElevageScreen.messageBandesWeb), findsOneWidget);
      expect(find.byIcon(SymbolesAgri.warning), findsWidgets);
      // Le toast se retire seul après 3,5 s, comme au web.
      await t.pump(ToastAgri.duree);
      expect(find.text(GestionElevageScreen.messageBandesWeb), findsNothing);
    });
  });
}
