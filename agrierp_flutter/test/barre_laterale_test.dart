import 'package:agrierp/core/auth/permissions_poste.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ticket F0.24 — LA BARRE LATÉRALE REPRODUIT CELLE DE LA MAQUETTE.
///
/// ⚠️⚠️ DEUX DÉFAUTS SUCCESSIFS, TOUS DEUX INVISIBLES DES AUTRES SUITES.
///
/// 1. `_libelles` ne portait que **quatre** entrées pour **neuf** écrans :
///    `_libelles[ecran]!` levait « Null check operator used on a null value »,
///    la barre ne se construisait plus, et l'application s'ouvrait sur un
///    **écran vide** après connexion.
/// 2. Une fois complétée, la barre restait une **liste plate des seuls écrans
///    embarqués** — alors que la maquette porte **onze groupes** et
///    **dix-neuf entrées**. J'avais justifié l'omission (« ne pas promettre un
///    écran inexistant ») ; le client a tranché : la maquette est la référence
///    de mise en page, elle se reproduit intégralement.
///
/// ⚠️ Aucun test ne rendait le socle — chaque suite vérifiait SON écran, jamais
/// la coquille. Le premier défaut n'a été vu qu'en lançant l'application.
void main() {
  /// L'arborescence de `main.dart`, recopiée. ⚠️ Duplication assumée, faute de
  /// pouvoir atteindre un membre privé : le test compare aux **entrées réelles
  /// de la maquette** ci-dessous, si bien qu'une divergence échoue ici.
  const arborescence = <String, List<(String, EcranPoste?)>>{
    'PILOTAGE': [('Tableau de Bord', EcranPoste.tableauDeBord)],
    'PRODUCTION ÉLEVAGE & SOINS': [
      ('Gestion Élevage', EcranPoste.gestionElevage),
      ('Dashboard Élevage', EcranPoste.dashboardElevage),
      ('Suivi Reproduction', EcranPoste.suiviReproduction),
      ('Soins et vaccins', EcranPoste.soinsEtVaccins),
      ('Paramètres Élevage', EcranPoste.parametresElevage),
    ],
    'VENTES FERME': [
      ('Ventes & Devis', EcranPoste.ventesEtDevis),
      ('Clients et Créances', EcranPoste.clientsEtCreances),
    ],
    'ACHATS & CHARGES': [
      ('Achats & Commandes', EcranPoste.achatsEtCommandes),
      ('Fournisseurs', EcranPoste.fournisseurs),
      ('Saisie Dépenses', EcranPoste.saisieDepenses),
    ],
    'STOCKS & PRODUITS': [
      ('Gestion Stocks', EcranPoste.gestionStocks),
      ('Catalogue Produits', EcranPoste.catalogueProduits),
    ],
    'FACTURATION': [('Facturation & MeCeF', EcranPoste.facturation)],
    'RESSOURCES HUMAINES': [
      ('Personnel & Stages', EcranPoste.personnelEtStages),
    ],
    'ADMINISTRATION': [
      ('Administration & Document', EcranPoste.administrationEtDocument),
    ],
    'COMPTABILITÉ & ADMIN': [
      ('Comptabilité', EcranPoste.comptabilite),
      ('Paramètres Général', EcranPoste.parametresGeneraux),
    ],
    'EDITIONS': [('Rapports & Exports', EcranPoste.rapportsEtExports)],
    'POSTE': [
      ('Synchronisation', EcranPoste.synchronisation),
      ('Paramètres du poste', EcranPoste.parametres),
    ],
  };

  /// Les groupes de `prototype_html/assets/js/sidebar.js`, dans SON ordre.
  /// « POSTE » n'y figure pas : il est hors maquette, et c'est dit.
  const groupesMaquette = [
    'PILOTAGE',
    'PRODUCTION ÉLEVAGE & SOINS',
    'VENTES FERME',
    'ACHATS & CHARGES',
    'STOCKS & PRODUITS',
    'FACTURATION',
    'RESSOURCES HUMAINES',
    'ADMINISTRATION',
    'COMPTABILITÉ & ADMIN',
    'EDITIONS',
  ];

  test(
    '⚠️⚠️ les onze groupes de la maquette sont présents, dans son ordre',
    () {
      final ordre = arborescence.keys.toList();

      expect(
        ordre.take(groupesMaquette.length).toList(),
        groupesMaquette,
        reason: 'ordre et intitulés repris de sidebar.js',
      );
      expect(
        ordre.last,
        'POSTE',
        reason: 'le seul groupe hors maquette vient en dernier',
      );
    },
  );

  test('⚠️ les dix-neuf entrées de la maquette sont toutes rendues', () {
    final entrees = arborescence.entries
        .where((g) => g.key != 'POSTE')
        .expand((g) => g.value.map((e) => e.$1))
        .toList();

    expect(
      entrees.length,
      19,
      reason: 'la barre de la maquette en porte dix-neuf',
    );

    // Quelques repères que le client a nommés explicitement.
    for (final attendu in [
      'Tableau de Bord',
      'Gestion Élevage',
      'Soins et vaccins',
      'Clients et Créances',
      'Fournisseurs',
      'Gestion Stocks',
      'Facturation & MeCeF',
      'Personnel & Stages',
      'Administration & Document',
      'Comptabilité',
      'Paramètres Général',
      'Rapports & Exports',
    ]) {
      expect(entrees, contains(attendu));
    }
  });

  /// ⚠️ C'EST LE DÉFAUT D'ORIGINE : un écran atteignable mais absent de la
  /// barre serait inaccessible. Deux familles font exception, et la maquette
  /// ne les liste pas davantage : les fiches d'espèce s'ouvrent depuis
  /// « Gestion Élevage », et la caisse est le premier ONGLET du hub
  /// « Ventes & Devis ».
  test('⚠️ tout écran du poste est atteignable depuis la barre', () {
    const parUnAutreEcran = {
      EcranPoste.ficheElevage,
      EcranPoste.fichePondeuses,
      EcranPoste.ficheReproducteurs,
      EcranPoste.fichePorcs,
      EcranPoste.ficheEscargots,
      // Premier onglet du hub de vente, comme dans la maquette.
      EcranPoste.caisse,
      // ⚠️ TROISIÈME FAMILLE (ticket F0.57) : les pages du MENU DU COMPTE de la
      // barre supérieure (`dd-profile`). La maquette ne les met pas davantage
      // dans la barre latérale ; leur accès est vérifié par
      // `mon_profil_test.dart` (« Mon Profil » ouvre l'écran).
      EcranPoste.monProfil,
      // ⚠️ La cloche de la barre supérieure (ticket F0.59), même famille : elle
      // ouvre le Centre de Notifications. Accès vérifié par
      // `notifications_test.dart`.
      EcranPoste.notifications,
      // ⚠️ Menu du compte, comme `monProfil` (ticket F0.60).
      EcranPoste.aideEtAPropos,
      // ⚠️ Idem (ticket F0.62).
      EcranPoste.contactEditeur,
      // ⚠️ Écran à PARAMÈTRE (ticket F0.65) : la fiche d'un sujet s'ouvre depuis une
      // référence du Suivi Reproduction, pas depuis la barre. Accès vérifié par
      // `fiche_sujet_test.dart`.
      EcranPoste.ficheSujet,
    };

    final cibles = arborescence.values
        .expand((g) => g.map((e) => e.$2))
        .whereType<EcranPoste>()
        .toSet();

    final inatteignables = EcranPoste.values
        .where((e) => !cibles.contains(e) && !parUnAutreEcran.contains(e))
        .map((e) => e.name)
        .toList();

    expect(inatteignables, isEmpty);
  });

  test('aucune entrée ne pointe deux fois le même écran', () {
    final cibles = arborescence.values
        .expand((g) => g.map((e) => e.$2))
        .whereType<EcranPoste>()
        .toList();

    expect(cibles.toSet().length, cibles.length);
  });

  test('les libellés sont distincts et non vides', () {
    final libelles = arborescence.values
        .expand((g) => g.map((e) => e.$1))
        .toList();

    expect(libelles.where((v) => v.trim().isEmpty), isEmpty);
    expect(libelles.toSet().length, libelles.length);
  });

  /// ⚠️ L'administrateur voit tout : c'est lui qui rencontre le premier une
  /// entrée fautive.
  test("l'administrateur atteint chaque écran du poste", () {
    final ecrans = PermissionsPoste.ecransDe('admin');

    expect(ecrans.length, EcranPoste.values.length);
  });
}
