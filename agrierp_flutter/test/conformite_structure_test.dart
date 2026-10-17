import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'structure_maquette.g.dart';

/// Ticket F0.49 — LA STRUCTURE DES ÉCRANS, VÉRIFIÉE COLONNE PAR COLONNE.
///
/// ⚠️⚠️ **CE QUE LE CONTRÔLE DE VOCABULAIRE NE VOIT PAS.** `fidelite_libelles`
/// (F0.42) vérifie que chaque MOT du prototype existe quelque part dans
/// l'écran. Un tableau dont les colonnes sont dans le DÉSORDRE, ou dont une
/// colonne du milieu manque, le passe sans broncher — chaque mot pris
/// séparément est bien là.
///
/// Ce contrôle-ci lit la SUITE ORDONNÉE des `<th>` de chaque tableau du
/// prototype et la confronte aux listes `colonnes:` déclarées par l'écran
/// porté. Une colonne déplacée, ajoutée ou oubliée le fait échouer.
///
/// ⚠️ **IL LIT LE CODE, PAS L'ARBRE RENDU** — comme son aîné. Il prouve que
/// l'écran DÉCLARE la bonne suite de colonnes, pas qu'elle s'affiche : les
/// tests de rendu s'en chargent, écran par écran.
void main() {
  /// Page du prototype → fichier Dart qui la porte.
  const portages = <String, String>{
    // Les six pages du hub Rapports & Exports (ticket F0.52).
    'rapport-recettes-depenses.html':
        'lib/features/rapports/rapports_exports_screen.dart',
    'rapport-tresorerie.html':
        'lib/features/rapports/rapports_exports_screen.dart',
    'rapport-creances.html':
        'lib/features/rapports/rapports_exports_screen.dart',
    'rapport-dettes.html': 'lib/features/rapports/rapports_exports_screen.dart',
    'rapport-elevage-synth.html':
        'lib/features/rapports/rapports_exports_screen.dart',
    'rapport-stocks-synth.html':
        'lib/features/rapports/rapports_exports_screen.dart',
    'gestion-stocks.html': 'lib/features/stocks/gestion_stocks_screen.dart',
    'catalogue-view.html': 'lib/features/stocks/catalogue_produits_screen.dart',
    'seuils-alerte.html': 'lib/features/stocks/catalogue_produits_screen.dart',
    'historique-ventes.html': 'lib/features/ventes/ventes_devis_screen.dart',
    'suivi-reproduction.html':
        'lib/features/elevage/suivi_reproduction_screen.dart',
    'vms-registre.html': 'lib/features/elevage/soins_vaccins_screen.dart',
    'vms-calendrier.html': 'lib/features/elevage/soins_vaccins_screen.dart',
    'elevage-dashboard.html':
        'lib/features/elevage/dashboard_elevage_screen.dart',
    'parametres-elevage.html':
        'lib/features/elevage/parametres_elevage_screen.dart',
    'liste-clients.html': 'lib/features/clients/clients_creances_screen.dart',
    'suivi-dettes.html': 'lib/features/clients/clients_creances_screen.dart',
    'historique-avances.html':
        'lib/features/clients/clients_creances_screen.dart',
    'enregistrer-achat.html':
        'lib/features/achats/achats_commandes_screen.dart',
    'liste-achats.html': 'lib/features/achats/achats_commandes_screen.dart',
    'bons-commande.html': 'lib/features/achats/achats_commandes_screen.dart',
    'ajouter-fournisseur.html': 'lib/features/achats/fournisseurs_screen.dart',
    'fiches-fournisseurs.html': 'lib/features/achats/fournisseurs_screen.dart',
    'dettes-fournisseurs.html': 'lib/features/achats/fournisseurs_screen.dart',
    'facturation.html': 'lib/features/ventes/facturation_screen.dart',
    'registre-employes.html': 'lib/features/rh/personnel_stages_screen.dart',
    'registre-stagiaires.html': 'lib/features/rh/personnel_stages_screen.dart',
    'feuille-pointage.html': 'lib/features/rh/personnel_stages_screen.dart',
    'gestion-paie.html': 'lib/features/rh/personnel_stages_screen.dart',
    'plan-comptable.html': 'lib/features/comptabilite/comptabilite_screen.dart',
    'journal-comptable.html':
        'lib/features/comptabilite/comptabilite_screen.dart',
    'grand-livre.html': 'lib/features/comptabilite/comptabilite_screen.dart',
    'balance-generale.html':
        'lib/features/comptabilite/comptabilite_screen.dart',
    'gestion-courriers.html':
        'lib/features/administration/administration_screen.dart',
    'archivage-documents.html':
        'lib/features/administration/administration_screen.dart',
    'documents-administratifs.html':
        'lib/features/administration/administration_screen.dart',
    'roles-permissions.html':
        'lib/features/parametres/parametres_generaux_screen.dart',
    'gestion-utilisateurs.html':
        'lib/features/parametres/parametres_generaux_screen.dart',
    'audit-logs.html':
        'lib/features/parametres/parametres_generaux_screen.dart',
    // Mon Profil (ticket F0.57).
    'mon-profil.html': 'lib/features/profil/mon_profil_screen.dart',
    // Centre de Notifications (ticket F0.59).
    'notifications.html':
        'lib/features/notifications/notifications_screen.dart',
  };

  /// ⚠️⚠️ **CHAQUE TABLEAU NON PORTÉ PORTE SA RAISON.** Un tableau du prototype
  /// que l'écran ne rend pas est un écart : soit il est justifié et il figure
  /// ici avec son motif, soit c'est une dérive et le test échoue.
  ///
  /// La clé est la PREMIÈRE colonne du tableau concerné — c'est ce qui
  /// l'identifie sans ambiguïté dans sa page.
  const tableauxNonPortes = <String, String>{
    // Modales de saisie : le panier d'un achat et celui d'un bon de commande
    // partagent la même en-tête dans la maquette ; le poste ne rend que celle
    // de l'achat, la saisie d'un bon restant sur le web (ticket F0.45).
    'Produit': 'saisie de bon de commande réservée au web',
    // Détail d'une vente : module non embarqué (ticket F0.37).
    'Désignation': 'détail de vente non embarqué au poste',
    // ⚠️ TROIS EXEMPTIONS ÉCRITES D'AVANCE ONT ÉTÉ RETIRÉES ICI : « Bande /
    // Espèce », « Jour de Cycle » et « Semaine » ne correspondaient à aucun
    // tableau du prototype — je les avais posées par anticipation, sans
    // vérifier. C'est le garde-fou des exemptions orphelines, en bas de ce
    // fichier, qui les a signalées.

    // ⚠️ LES DEUX PANNEAUX VOLAILLES ET ESCARGOTS de Suivi Reproduction sont
    //    rendus EN RÉSUMÉ, pas en second formulaire : la donnée se saisit sur
    //    la fiche d'espèce (exemption déjà posée au ticket F0.42, ici pour la
    //    structure).
    'Code Incubation': 'onglet rendu en résumé, pas en tableau',
    'Parc / Fosse': 'onglet rendu en résumé, pas en tableau',

    // ⚠️ LE GANTT DU CALENDRIER VÉTÉRINAIRE porte une colonne par jour de la
    //    semaine de démonstration : ce sont des DONNÉES figées, pas une
    //    structure. Le poste rend la même information en frise calculée.
    'Lot / Bande': 'Gantt à colonnes datées, rendu en frise calculée',

    // ⚠️ « Maladies les Plus Fréquentes — 2026 vs 2025 » compare deux années :
    //    l'historique de l'an dernier ne descend pas au poste (F0.33).
    'Maladie / Symptôme': "historique de l'an dernier non synchronisé",

    // ⚠️⚠️ LA COLONNE DE SÉLECTION MULTIPLE (`<th></th>` en tête de tableau)
    //    n'est pas portée : elle ne sert qu'à la suppression en masse, et les
    //    deux référentiels concernés — clients, fournisseurs — sont en lecture
    //    seule au poste. Une case à cocher qui ne mène à rien serait pire
    //    qu'absente.
    '(sans libelle)': 'sélection multiple sans objet sur un référentiel',

    // ⚠️⚠️ LES SAUVEGARDES DE LA BASE NE DESCENDENT PAS AU POSTE : ce sont des
    //    fichiers `.sql` de plusieurs dizaines de méga-octets, produits et
    //    gardés sur le serveur. Le tableau qui les liste n'aurait au poste
    //    aucune ligne à montrer — et son bouton de téléchargement, rien à
    //    télécharger.
    'Fichier': 'sauvegardes produites et gardées sur le serveur',
  };

  /// Colonnes déclarées par un écran, sous ses DEUX formes.
  ///
  /// ⚠️⚠️ **LES ÉCRANS N'ONT PAS TOUS LE MÊME GABARIT DE TABLEAU**, et c'est
  /// ce contrôle qui l'a révélé. Les premiers portés (Stocks, Ventes, Élevage)
  /// écrivent leurs en-têtes une par une —
  /// `Text('CODE', style: _enteteColonne)` — tandis que les suivants déclarent
  /// une liste `colonnes: const [('Code', 3), …]`. Ne lire que la seconde
  /// forme aurait fait passer les premiers écrans pour dépourvus de tableau,
  /// c'est-à-dire pour conformes.
  List<List<String>> colonnesDeclarees(String chemin) {
    final code = File(chemin).readAsStringSync();
    final suites = <List<String>>[];

    // Forme 1 — la liste déclarée.
    for (final bloc in RegExp(
      r'colonnes:\s*const\s*\[(.*?)\],',
      dotAll: true,
    ).allMatches(code)) {
      var libelles = RegExp(r'''\(\s*'([^']*)'|\(\s*"([^"]*)"''')
          .allMatches(bloc.group(1)!)
          // ⚠️ UNE EN-TÊTE VIDE EST UNE COLONNE : la maquette ferme
          // plusieurs tableaux par un `<th></th>` — la colonne du bouton
          // d'action. L'écarter ferait compter quatre colonnes pour cinq.
          .map((m) => m.group(1) ?? m.group(2) ?? '')
          .map((l) => l.isEmpty ? '(sans libelle)' : l)
          .toList();

      // ⚠️ QUATRIEME FORME — une liste PLATE de libelles, sans le poids de
      // colonne : `colonnes: const ['Bande', 'N° Lapine', …]`. Le tableau des
      // lapines l'emploie. Ne pas la lire ferait passer pour absents les
      // quatre tableaux de Suivi Reproduction.
      if (libelles.isEmpty) {
        libelles = RegExp(r'''\s*'([^']*)'|\s*"([^"]*)"''')
            .allMatches(bloc.group(1)!)
            .map((m) => m.group(1) ?? m.group(2) ?? '')
            .where((l) => l.isNotEmpty)
            .toList();
      }

      if (libelles.isNotEmpty) suites.add(libelles);
    }

    // Forme 5 — une CONSTANTE de colonnes, déclarée à part.
    //
    // ⚠️ La Balance Générale rend un en-tête à DEUX niveaux : ses colonnes
    // feuilles sont donc déclarées à plat dans une constante, que le tableau
    // groupé consomme. Sans cette forme, le seul tableau à en-tête groupé du
    // projet passerait pour absent.
    for (final bloc in RegExp(
      r'colonnes\w*\s*=\s*<\(String, int\)>\[(.*?)\];',
      dotAll: true,
    ).allMatches(code)) {
      final libelles = RegExp(r'''\(\s*'([^']*)'|\(\s*"([^"]*)"''')
          .allMatches(bloc.group(1)!)
          .map((m) => m.group(1) ?? m.group(2) ?? '')
          .map((l) => l.isEmpty ? '(sans libelle)' : l)
          .toList();

      if (libelles.isNotEmpty) suites.add(libelles);
    }

    // Forme 3 — la liste parcourue sur place :
    // `for (final (libelle, flex) in const [('N° Facture', 3), …])`.
    for (final bloc in RegExp(
      r'for \(final \(libelle, flex\) in const \[(.*?)\]\)',
      dotAll: true,
    ).allMatches(code)) {
      final libelles = RegExp(r'''\(\s*'([^']*)'|\(\s*"([^"]*)"''')
          .allMatches(bloc.group(1)!)
          // ⚠️ UNE EN-TÊTE VIDE EST UNE COLONNE : la maquette ferme
          // plusieurs tableaux par un `<th></th>` — la colonne du bouton
          // d'action. L'écarter ferait compter quatre colonnes pour cinq.
          .map((m) => m.group(1) ?? m.group(2) ?? '')
          .map((l) => l.isEmpty ? '(sans libelle)' : l)
          .toList();

      if (libelles.isNotEmpty) suites.add(libelles);
    }

    // Forme 2 — les en-têtes écrites une par une. Elles se suivent dans la
    // `Row` d'en-tête : une coupure de plus de 1500 caractères entre deux
    // signifie qu'on a changé de tableau.
    // ⚠️ LES DEUX FORMES DE CITATION : `Text('DATE', …)` et
    // `Text("TYPE D'ACTION", …)` — un en-tete qui porte une apostrophe est
    // ecrit entre guillemets doubles, et ne pas le lire ferait passer son
    // tableau pour absent.
    final entetes = RegExp(
      r'''Text\(\s*'([^']*)'\s*,[^)]*style:\s*_entete\w*|Text\(\s*"([^"]*)"\s*,[^)]*style:\s*_entete\w*''',
    ).allMatches(code).toList();

    var courante = <String>[];
    var finPrecedente = -1;

    for (final entete in entetes) {
      if (finPrecedente >= 0 && entete.start - finPrecedente > 1500) {
        if (courante.isNotEmpty) suites.add(courante);
        courante = <String>[];
      }
      courante.add(entete.group(1) ?? entete.group(2) ?? '');
      finPrecedente = entete.end;
    }
    if (courante.isNotEmpty) suites.add(courante);

    return suites;
  }

  /// Deux libellés se comparent sans accent ni casse : la maquette écrit
  /// « Designation » ici et « Désignation » là, et cet écart-là est déjà suivi
  /// par l'arbitrage client ouvert sur les huit `<th>` de `gestion-stocks`.
  String normaliser(String libelle) {
    const accents = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };

    var texte = libelle.toLowerCase().trim();
    accents.forEach((a, s) => texte = texte.replaceAll(a, s));
    return texte.replaceAll(RegExp(r'\s+'), ' ');
  }

  for (final entree in portages.entries) {
    final page = entree.key;
    final attendus = tableauxMaquette[page];

    if (attendus == null) continue;

    test('⚠️ la structure des tableaux de $page est respectée', () {
      final declarees = colonnesDeclarees(
        entree.value,
      ).map((s) => s.map(normaliser).toList()).toList();

      final manquants = <String>[];

      for (final attendu in attendus) {
        final premiere = attendu.first;
        if (tableauxNonPortes.containsKey(premiere)) continue;

        final cible = attendu.map(normaliser).toList();

        final trouve = declarees.any((d) {
          if (d.length != cible.length) return false;
          for (var i = 0; i < d.length; i++) {
            if (d[i] != cible[i]) return false;
          }
          return true;
        });

        if (!trouve) {
          manquants.add(attendu.join(' | '));
        }
      }

      expect(
        manquants,
        isEmpty,
        reason:
            'Ces tableaux de $page ne se retrouvent pas, dans cet ordre et '
            "avec ce nombre de colonnes, dans l'écran qui les porte. Soit une "
            'colonne a été déplacée, ajoutée ou oubliée — soit le tableau '
            "n'est pas porté, et il doit rejoindre `tableauxNonPortes` AVEC "
            'SA RAISON.',
      );
    });
  }

  /// ⚠️ Une exemption qui ne correspond plus à aucun tableau laisse croire
  /// qu'un écart est couvert alors qu'il a disparu — ou pire, qu'un tableau
  /// est absent alors qu'il est revenu.
  test('⚠️ aucune exemption de tableau ne survit à son tableau', () {
    final premieres = <String>{
      for (final tableaux in tableauxMaquette.values)
        for (final colonnes in tableaux) colonnes.first,
    };

    final orphelines = tableauxNonPortes.keys
        .where((e) => !premieres.contains(e))
        .toList();

    expect(orphelines, isEmpty);
  });
}
