import 'dart:io';

import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:agrierp/core/database/app_database.dart';
import 'package:agrierp/core/theme/agri_theme.dart';
import 'package:agrierp/core/widgets/barre_superieure.dart';
import 'package:agrierp/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chemins_depot.dart';
import 'coque_poste.dart';

/// Ticket H1 — CHÂSSIS DU POSTE ALIGNÉ SUR `layouts/app.blade.php` (le maître) : menu du compte, titre de la barre
/// supérieure, ruban de la barre repliée. Les libellés sont LUS dans le Blade et dans les composants Livewire : un
/// renommage au web fait rougir ce test.
void main() {
  final layout = File('$dossierLaravel/resources/views/layouts/app.blade.php');
  final sansLaravel = layout.existsSync() ? false : 'dépôt Laravel absent ($dossierLaravel)';

  test('le menu du compte a les entrées du web, dans l ordre', () async {
    final blade = layout.readAsStringSync();
    final menu = blade.substring(blade.indexOf('id="dd-profile"'), blade.indexOf('</form>', blade.indexOf('id="dd-profile"')));
    final libelles = RegExp(r'</span>([^<]+)</(?:a|button)>')
        .allMatches(menu)
        .map((m) => m.group(1)!.replaceAll('&amp;', '&').trim())
        .toList();
    // Ticket VW : « Verrouiller » (verrou de session web) entre Paramètres et le séparateur de Déconnexion.
    expect(libelles, ['Mon Profil', 'Aide & À Propos', "Contactez l'Éditeur", 'Paramètres', 'Verrouiller', 'Déconnexion']);
  }, skip: sansLaravel);

  testWidgets('menu du compte : Paramètres puis, sous un séparateur, Déconnexion qui prévient le socle', (t) async {
    var deconnexions = 0;
    // Ticket ENV1 : la pastille de recherche a la largeur du web (`w-64`, 256 px). La police de test (Ahem, un em par
    // lettre) élargit le nom du compte au double d'Inter : à 800 px la barre déborde, ce qui n'arrive pas en vrai.
    t.view.physicalSize = const Size(1100, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarreSuperieure(
            groupe: '',
            ecran: 'Tableau de Bord',
            enAttente: 0,
            onBasculerMenu: () {},
            nomUtilisateur: 'M. Olouchègoun',
            onMonProfil: () {},
            onAide: () {},
            onContact: () {},
            onParametres: () {},
            onDeconnexion: () => deconnexions++,
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('menu-compte')));
    await t.pumpAndSettle();

    final ordre = [
      for (final cle in ['profil', 'aide', 'contact', 'parametres', 'deconnexion'])
        t.getTopLeft(find.byKey(Key('menu-compte-$cle'))).dy,
    ];
    expect(ordre, [...ordre]..sort());
    expect(find.byType(PopupMenuDivider), findsOneWidget);

    await t.tap(find.byKey(const Key('menu-compte-deconnexion')));
    await t.pumpAndSettle();
    expect(deconnexions, 1);
  });

  test('la barre dit « Facturation » quand MeCeF est désactivé, comme le web', () {
    expect(SocleAccueilTitres.titre(EcranPoste.facturation), 'Facturation');
    expect(SocleAccueilTitres.titre(EcranPoste.facturation, mecefActif: true), 'Facturation & MeCeF');
    expect(SocleAccueilTitres.titre(EcranPoste.comptabilite), 'Comptabilité');
  });

  test('le titre de la barre est celui que le web affiche pour chaque écran', () {
    final routes = File('$dossierLaravel/routes/web.php').readAsStringSync();
    String titreWeb(String chemin) {
      final m = RegExp("Route::get\\('${RegExp.escape(chemin)}',\\s*\\\\?([\\w\\\\]+)::class").firstMatch(routes)!;
      final fichier = '$dossierLaravel/app/${m.group(1)!.replaceFirst(RegExp(r'^\\?App\\'), '').replaceAll(r'\', '/')}.php';
      final source = File(fichier).readAsStringSync();
      // Le `$title` passé au layout par `render()` (le dernier du fichier : les premiers peuvent être des cartes).
      // VC-5 : le titre de la facturation suit le module (`$this->mecefActif ? 'Facturation & MeCeF' : 'Facturation'`) : c'est
      // la forme module ACTIVÉ qui est comparée.
      final titres = RegExp(r"'title' => (?:\$this->mecefActif \? )?'((?:[^'\\]|\\.)*)'(?: : '[^']*')?\]").allMatches(source).toList();
      return titres.isEmpty ? 'Ferme École Olouwachegoun' : titres.last.group(1)!.replaceAll(r"\'", "'");
    }

    const chemins = <EcranPoste, String>{
      EcranPoste.tableauDeBord: '/dashboard',
      EcranPoste.gestionElevage: '/gestion-elevage',
      EcranPoste.dashboardElevage: '/elevage-dashboard',
      EcranPoste.suiviReproduction: '/suivi-reproduction',
      EcranPoste.soinsEtVaccins: '/soins-vaccins-hub',
      EcranPoste.transformation: '/transformation',
      EcranPoste.parametresElevage: '/parametres-elevage',
      EcranPoste.ficheElevage: '/fiche-lapins',
      EcranPoste.fichePondeuses: '/fiche-volailles-pondeuses',
      EcranPoste.ficheReproducteurs: '/fiche-volailles-reproducteurs',
      EcranPoste.fichePorcs: '/fiche-porcs',
      EcranPoste.ficheEscargots: '/fiche-escargots',
      EcranPoste.transfertsBandes: '/transferts-bandes',
      EcranPoste.gestionBandes: '/gestion-bandes',
      EcranPoste.enregistrerSujets: '/enregistrer-sujets',
      EcranPoste.ventesEtDevis: '/ventes-devis',
      EcranPoste.clientsEtCreances: '/creances-clients',
      EcranPoste.achatsEtCommandes: '/achats-commandes',
      EcranPoste.fournisseurs: '/fournisseurs',
      EcranPoste.saisieDepenses: '/saisie-depenses',
      EcranPoste.gestionStocks: '/gestion-stocks',
      EcranPoste.catalogueProduits: '/catalogue-produits',
      EcranPoste.facturation: '/facturation',
      EcranPoste.personnelEtStages: '/personnel-stages',
      EcranPoste.administrationEtDocument: '/administration',
      EcranPoste.comptabilite: '/comptabilite-hub',
      EcranPoste.parametresGeneraux: '/parametres-hub',
      EcranPoste.rapportsEtExports: '/rapports-exports',
      EcranPoste.monProfil: '/mon-profil',
      EcranPoste.notifications: '/notifications',
      EcranPoste.aideEtAPropos: '/aide-a-propos',
      EcranPoste.contactEditeur: '/contact-editeur',
    };
    final ecarts = <String>[
      for (final MapEntry(key: e, value: chemin) in chemins.entries)
        if (SocleAccueilTitres.titre(e, mecefActif: true) != titreWeb(chemin)) '${e.name} : poste « ${SocleAccueilTitres.titre(e, mecefActif: true)} », web « ${titreWeb(chemin)} »',
    ];
    expect(ecarts, isEmpty);
  }, skip: sansLaravel);

  testWidgets('barre repliée : le ruban du web, six raccourcis et « Réafficher le menu »', (t) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: AgriTheme.light, home: coqueDeTest(db)));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('ruban-replie')), findsNothing);
    await t.tap(find.byKey(const Key('bascule-menu')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('barre-laterale')), findsNothing);
    expect(find.byKey(const Key('ruban-replie')), findsOneWidget);

    final blade = layout.readAsStringSync();
    final ruban = blade.substring(blade.indexOf('x-show="sidebarDesktopHidden"'), blade.indexOf('Réafficher le menu'));
    final titresBlade = RegExp(r'<a (?:wire:navigate )?href="[^"]+" title="([^"]+)"').allMatches(ruban).map((m) => m.group(1)).toList();
    final infobulles = t.widgetList<IconButton>(find.descendant(of: find.byKey(const Key('ruban-replie')), matching: find.byType(IconButton))).map((b) => b.tooltip).toList();
    expect(infobulles, [...titresBlade, 'Réafficher le menu']);

    await t.tap(find.byKey(Key('ruban-${EcranPoste.comptabilite.name}')));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('fil-ariane'))).data, 'Comptabilité');

    await t.tap(find.byKey(const Key('ruban-reafficher')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('barre-laterale')), findsOneWidget);
  }, skip: sansLaravel != false);
}
