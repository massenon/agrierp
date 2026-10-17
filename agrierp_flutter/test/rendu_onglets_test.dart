import 'dart:convert';
import 'dart:io';

import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/widgets/carte_kpi.dart';
import 'package:agrierp/features/achats/achats_commandes_screen.dart';
import 'package:agrierp/features/achats/achats_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_repository.dart';
import 'package:agrierp/features/achats/fournisseurs_screen.dart';
import 'package:agrierp/features/administration/administration_repository.dart';
import 'package:agrierp/features/administration/administration_screen.dart';
import 'package:agrierp/features/clients/clients_creances_repository.dart';
import 'package:agrierp/features/clients/clients_creances_screen.dart';
import 'package:agrierp/features/comptabilite/comptabilite_repository.dart';
import 'package:agrierp/features/comptabilite/comptabilite_screen.dart';
import 'package:agrierp/features/elevage/dashboard_elevage_repository.dart';
import 'package:agrierp/features/elevage/dashboard_elevage_screen.dart';
import 'package:agrierp/features/elevage/parametres_elevage_repository.dart';
import 'package:agrierp/features/elevage/parametres_elevage_screen.dart';
import 'package:agrierp/features/elevage/soins_repository.dart';
import 'package:agrierp/features/elevage/soins_vaccins_repository.dart';
import 'package:agrierp/features/elevage/soins_vaccins_screen.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_repository.dart';
import 'package:agrierp/features/elevage/suivi_reproduction_screen.dart';
import 'package:agrierp/features/parametres/parametres_generaux_repository.dart';
import 'package:agrierp/features/parametres/parametres_generaux_screen.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_repository.dart';
import 'package:agrierp/features/pilotage/tableau_de_bord_screen.dart';
import 'package:agrierp/features/rapports/rapports_exports_screen.dart';
import 'package:agrierp/features/rapports/rapports_repository.dart';
import 'package:agrierp/features/rh/personnel_repository.dart';
import 'package:agrierp/features/rh/personnel_stages_screen.dart';
import 'package:agrierp/features/stocks/catalogue_produits_screen.dart';
import 'package:agrierp/features/stocks/gestion_stocks_screen.dart';
import 'package:agrierp/features/stocks/stocks_repository.dart';
import 'package:agrierp/features/ventes/caisse_repository.dart';
import 'package:agrierp/features/ventes/ventes_devis_repository.dart';
import 'package:agrierp/features/ventes/ventes_devis_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket AF1.2 — RELEVÉ DE RENDU PAR ONGLET (phase 1A de AUDIT_FIDELISATION.md).
///
/// ⚠️⚠️ **CE N'EST PAS UN TEST DE NON-RÉGRESSION : C'EST UN INSTRUMENT.** Il monte
/// chaque écran à onglets sur une base VIDE, ouvre chaque onglet, et écrit dans
/// `build/audit/rendu_onglets.json` ce que l'arbre de widgets AFFICHE vraiment :
/// les textes dans leur ordre d'apparition, les libellés de champ, les cartes
/// d'indicateur. `outils/emplacement.py` le confronte ensuite au prototype,
/// panneau par panneau.
///
/// Il vérifie donc ce que `fidelite_libelles_test.dart` ne peut pas — que le
/// libellé est dans le BON onglet — et ce que l'audit n° 1 déclarait ne pas
/// mesurer (« présence, pas emplacement »).
///
/// ⚠️ **NE S'EXÉCUTE QUE SUR DEMANDE** : `AUDIT_RENDU=1 flutter test
/// test/rendu_onglets_test.dart`. Sans la variable il se marque IGNORÉ — il
/// n'asserte rien et écrit un fichier, il n'a rien à faire dans la suite.
///
/// ⚠️ **LIMITE ASSUMÉE : BASE VIDE.** Ce qu'un écran ne montre qu'avec des
/// lignes (en-têtes de tableau rendus par ligne, contenu de modale) n'apparaît
/// pas ici. Le comparateur le range à part (« non rendu à vide ») au lieu de
/// l'appeler absent — l'audit de présence par littéraux (phase 0) dit si le mot
/// existe dans le source.
void main() {
  final actif = Platform.environment['AUDIT_RENDU'] == '1';
  final skip = actif ? null : 'relevé sur demande : AUDIT_RENDU=1';

  late AppDatabase db;
  const poste = 'poste-audit';

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  final resultat = <String, Object>{};

  // ⚠️ LES DÉBORDEMENTS DE MISE EN PAGE SONT UN RÉSULTAT. Flutter les lève comme
  // des exceptions que le banc de test fait échouer en fin d'épreuve ; ici on les
  // collecte avec l'écran et l'onglet où ils se produisent (phase 1D : alignement).
  var ou = '';
  final alertes = <Map<String, String>>[];

  Map<String, Object> relever(WidgetTester t) {
    final textes = <String>[];
    for (final w in t.widgetList<Text>(find.byType(Text))) {
      final s = (w.data ?? w.textSpan?.toPlainText() ?? '').trim();
      if (s.isNotEmpty) textes.add(s);
    }
    final champs = <String>[];
    for (final w in t.widgetList<InputDecorator>(find.byType(InputDecorator))) {
      final d = w.decoration;
      final s = (d.labelText ?? d.hintText ?? '').trim();
      if (s.isNotEmpty) champs.add(s);
    }
    final cartes = [
      for (final c in t.widgetList<CarteKpi>(find.byType(CarteKpi)))
        {'libelle': c.libelle, 'valeur': c.valeur},
    ];
    return {'textes': textes, 'champs': champs, 'cartes': cartes};
  }

  /// Les clés d'onglet suivent la convention `onglet-<préfixe>-<titre>` ; on les
  /// prend dans l'ordre d'apparition de l'arbre, qui est l'ordre de la barre.
  List<String> clesOnglets(WidgetTester t, String prefixe) {
    final cles = <String>[];
    for (final w in t.allWidgets) {
      final k = w.key;
      if (k is ValueKey<String> && k.value.startsWith(prefixe)) {
        if (!cles.contains(k.value)) cles.add(k.value);
      }
    }
    return cles;
  }

  Future<void> monter(WidgetTester t, Widget ecran) async {
    t.view.physicalSize = const Size(1280, 3200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: ecran));
    await t.pumpAndSettle();
  }

  /// Monte l'écran, relève le panneau par défaut, puis chaque onglet.
  Future<void> parcourir(
    WidgetTester t,
    String nom,
    String prefixe,
    Widget ecran,
  ) async {
    ou = nom;
    await monter(t, ecran);
    final panneaux = <String, Object>{};
    final cles = clesOnglets(t, prefixe);
    panneaux['(par défaut)'] = relever(t);
    for (final cle in cles) {
      final f = find.byKey(Key(cle));
      if (f.evaluate().isEmpty) continue;
      ou = '$nom › ${cle.substring(prefixe.length)}';
      await t.ensureVisible(f.first);
      await t.tap(f.first);
      await t.pumpAndSettle();
      panneaux[cle.substring(prefixe.length)] = relever(t);
    }
    resultat[nom] = {
      'prefixe': prefixe,
      'onglets': cles.map((c) => c.substring(prefixe.length)).toList(),
      'panneaux': panneaux,
    };
  }

  testWidgets('relevé de rendu des écrans à onglets', (t) async {
    final ancien = FlutterError.onError;
    FlutterError.onError = (d) {
      final lignes = d.exceptionAsString().split('\n');
      alertes.add({'ou': ou, 'message': lignes.first});
    };

    final soins = SoinsRepository(database: db, deviceId: poste);
    final stocks = StocksRepository(database: db, deviceId: poste);
    final caisse = CaisseRepository(database: db, deviceId: poste);

    final ecrans = <String, (String, Widget)>{
      'tableau-de-bord': (
        'onglet-tx-',
        TableauDeBordScreen(depot: TableauDeBordRepository(database: db)),
      ),
      'elevage-dashboard': (
        'onglet-',
        DashboardElevageScreen(
          depot: DashboardElevageRepository(database: db, soins: soins),
        ),
      ),
      'suivi-reproduction': (
        'onglet-repro-',
        SuiviReproductionScreen(
          depot: SuiviReproductionRepository(database: db, deviceId: poste),
        ),
      ),
      'soins-vaccins-hub': (
        'onglet-vms-',
        SoinsVaccinsScreen(
          depot: SoinsVaccinsRepository(database: db, soins: soins),
          soins: soins,
        ),
      ),
      'parametres-elevage': (
        'onglet-parametres-',
        ParametresElevageScreen(
          depot: ParametresElevageRepository(database: db),
        ),
      ),
      'creances-clients': (
        'onglet-clients-',
        ClientsCreancesScreen(
          depot: ClientsCreancesRepository(
            database: db,
            deviceId: 'poste-test',
          ),
        ),
      ),
      'gestion-stocks': ('onglet-stocks-', GestionStocksScreen(depot: stocks)),
      'catalogue-produits': (
        'onglet-catalogue-',
        CatalogueProduitsScreen(depot: stocks),
      ),
      'ventes-devis': (
        'onglet-ventes-',
        VentesDevisScreen(
          depot: VentesDevisRepository(database: db),
          caisse: caisse,
        ),
      ),
      'parametres-hub': (
        'onglet-parametres-generaux-',
        ParametresGenerauxScreen(
          depot: ParametresGenerauxRepository(database: db),
        ),
      ),
      'rapports-exports': (
        'onglet-rapports-',
        RapportsExportsScreen(depot: RapportsRepository(database: db)),
      ),
      'administration': (
        'onglet-administration-',
        AdministrationScreen(depot: AdministrationRepository(database: db)),
      ),
      'personnel-stages': (
        'onglet-personnel-',
        PersonnelStagesScreen(
          depot: PersonnelRepository(database: db, identifiantPoste: poste),
        ),
      ),
      'fournisseurs': (
        'onglet-fournisseurs-',
        FournisseursScreen(depot: FournisseursRepository(database: db)),
      ),
      'achats-commandes': (
        'onglet-achats-',
        AchatsCommandesScreen(
          depot: AchatsRepository(database: db, identifiantPoste: poste),
        ),
      ),
    };

    for (final e in ecrans.entries) {
      // Un écran qui ne se monte pas à vide est un résultat, pas un arrêt.
      try {
        await parcourir(t, e.key, e.value.$1, e.value.$2);
      } catch (erreur) {
        resultat[e.key] = {'erreur': erreur.toString().split('\n').first};
      }
      await t.pumpWidget(const SizedBox());
    }

    // Comptabilité : un hub de CARTES, pas d'onglets.
    ou = 'comptabilite-hub';
    try {
      await monter(
        t,
        ComptabiliteScreen(depot: ComptabiliteRepository(database: db)),
      );
      final panneaux = <String, Object>{'(par défaut)': relever(t)};
      final cartes = <String>[];
      for (final w in t.allWidgets) {
        final k = w.key;
        if (k is ValueKey<String> && k.value.startsWith('carte-')) {
          if (!cartes.contains(k.value)) cartes.add(k.value);
        }
      }
      for (final cle in cartes) {
        await t.tap(find.byKey(Key(cle)).first);
        await t.pumpAndSettle();
        panneaux[cle.substring('carte-'.length)] = relever(t);
        final retour = find.byKey(const Key('retour-hub'));
        if (retour.evaluate().isNotEmpty) {
          await t.tap(retour.first);
          await t.pumpAndSettle();
        }
      }
      resultat['comptabilite-hub'] = {
        'prefixe': 'carte-',
        'onglets': cartes.map((c) => c.substring('carte-'.length)).toList(),
        'panneaux': panneaux,
      };
    } catch (erreur) {
      resultat['comptabilite-hub'] = {'erreur': erreur.toString()};
    }

    FlutterError.onError = ancien;
    resultat['(alertes de rendu)'] = alertes;

    final sortie = File('build/audit/rendu_onglets.json');
    sortie.parent.createSync(recursive: true);
    sortie.writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(resultat),
    );
  }, skip: skip != null);
}
