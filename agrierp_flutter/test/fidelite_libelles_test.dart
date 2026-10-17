import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'inventaire_maquette.g.dart';

/// Texte de tous les LITTÉRAUX DE CHAÎNE d'une source Dart.
///
/// ⚠️⚠️ **TICKET F0.53 — CE CONTRÔLE SE CONTENTAIT D'UN COMMENTAIRE.** Il
/// comparait `code.contains(libelle)` sur le fichier ENTIER. Trois choses
/// suffisaient donc à le satisfaire sans qu'aucun écran n'affiche le mot :
///
/// 1. **un commentaire** — et c'est le cas le plus retors, parce que les
///    commentaires en question sont précisément les « ⚠️ ce libellé n'est pas
///    repris parce que… » du projet. Le contrôle passait donc sur les
///    **explications de l'absence**. Mesuré : **13 libellés sur 8 pages** ;
/// 2. **un identifiant** — « Role » passait grâce à `RolesApplicatif`, « Date »
///    grâce à `DateTime`. Mesuré : 2 libellés ;
/// 3. accessoirement, la prose de n'importe quel docblock.
///
/// Autrement dit : on pouvait **retirer un libellé de l'écran, écrire un
/// commentaire disant pourquoi, et le contrôle restait vert**. Ce qu'il
/// mesurait n'était pas la fidélité, c'était la présence du mot quelque part
/// dans un fichier.
///
/// ⚠️ **DEUX LITTÉRAUX ADJACENTS SONT RECOLLÉS.** Le code coupe ses longues
/// phrases en `'…première moitié '` `'seconde moitié…'`, que Dart concatène.
/// Les séparer ici couperait des libellés en deux et ferait échouer le contrôle
/// sur des textes pourtant bien présents.
///
/// ⚠️ **RÉSIDU CONNU** : le contenu d'une interpolation `${…}` reste compté. Un
/// libellé de la maquette ne peut pas être une expression Dart, et la casse
/// sépare `role` de « Role » — le trou est négligeable, il est dit plutôt que
/// tu.
String chainesDe(String source) {
  final tampon = StringBuffer();
  var i = 0;
  var finChainePrecedente = -1;

  bool suite(String motif, int position) => source.startsWith(motif, position);

  while (i < source.length) {
    // Commentaire de ligne — `//` comme `///`.
    if (suite('//', i)) {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }

    // Commentaire de bloc.
    if (suite('/*', i)) {
      i += 2;
      while (i < source.length && !suite('*/', i)) {
        i++;
      }
      i += 2;
      continue;
    }

    // ⚠️ Une chaîne BRUTE (`r'…'`) n'interprète aucune séquence d'échappement.
    final brute =
        source[i] == 'r' &&
        i + 1 < source.length &&
        (source[i + 1] == "'" || source[i + 1] == '"');
    final debutGuillemet = brute ? i + 1 : i;
    final c = source[debutGuillemet];

    if (c != "'" && c != '"') {
      i++;
      continue;
    }

    final triple = suite(c * 3, debutGuillemet);
    final cloture = triple ? c * 3 : c;
    var j = debutGuillemet + cloture.length;
    final contenu = StringBuffer();

    while (j < source.length && !suite(cloture, j)) {
      if (!brute && source[j] == r'\' && j + 1 < source.length) {
        // L'échappement porte sur le caractère suivant : `\'` est une
        // apostrophe, pas une fin de chaîne.
        contenu.write(source[j + 1]);
        j += 2;
        continue;
      }
      contenu.write(source[j]);
      j++;
    }

    // Deux littéraux séparés par la seule mise en page sont adjacents : Dart
    // les concatène, nous aussi. Sinon on pose un séparateur.
    final entreDeux = finChainePrecedente < 0
        ? 'x'
        : source.substring(finChainePrecedente, i);
    if (entreDeux.trim().isNotEmpty) {
      // ⚠️ Un SAUT DE LIGNE, jamais une espace : un libellé de la maquette
      // tient sur une ligne (l'extracteur replie les blancs). Séparer par une
      // espace laisserait deux littéraux sans rapport en former un par
      // accident — « Total » suivi de « Recettes » vaudrait « Total Recettes ».
      tampon.write('\n');
    }

    tampon.write(contenu);
    i = j + cloture.length;
    finChainePrecedente = i;
  }

  return tampon.toString();
}

/// Ticket F0.42 — LE VOCABULAIRE DE LA MAQUETTE, VÉRIFIÉ MOT À MOT.
///
/// ⚠️⚠️ **LES TESTS D'ÉCRAN NE VÉRIFIENT QUE LES MOTS QU'ILS CONNAISSENT.**
/// Chaque écran porté a sa liste de libellés attendus — écrite à la main, au
/// moment du portage, par la même personne qui venait de les taper. Un mot
/// oublié n'y figure pas ; un mot reformulé y figure sous sa forme reformulée.
/// Le contrôle et l'erreur ont la même source.
///
/// Ce test-ci part de l'AUTRE bout : l'inventaire est **extrait du prototype**
/// (`outils/inventaire.py`), et confronté au code de l'écran. Il a trouvé, dès
/// sa première exécution :
///   • le titre « Gestion **des** Stocks », rendu « Gestion Stocks » — le
///     libellé de l'entrée de menu employé pour titrer la page ;
///   • **quatre colonnes manquantes** sur douze au tableau des lapines, et
///     **deux** sur dix chez les truies ;
///   • quatre en-têtes accentués que la maquette n'accentue pas.
///
/// ⚠️ **CE CONTRÔLE LIT LE CODE, PAS L'ARBRE RENDU.** Il prouve qu'un mot du
/// prototype existe quelque part dans l'écran, pas qu'il est affiché — les
/// tests de rendu s'en chargent. Sa force est ailleurs : il voit les mots que
/// personne n'a pensé à chercher.
void main() {
  /// Page du prototype → écrans Flutter qui la portent.
  const portages = <String, List<String>>{
    // Le hub Rapports & Exports et ses six pages (ticket F0.52).
    'rapports-exports.html': [
      'lib/features/rapports/rapports_exports_screen.dart',
    ],
    'rapport-recettes-depenses.html': [
      'lib/features/rapports/rapports_exports_screen.dart',
    ],
    'rapport-tresorerie.html': [
      'lib/features/rapports/rapports_exports_screen.dart',
    ],
    'rapport-creances.html': [
      'lib/features/rapports/rapports_exports_screen.dart',
    ],
    'rapport-dettes.html': [
      'lib/features/rapports/rapports_exports_screen.dart',
    ],
    'rapport-elevage-synth.html': [
      'lib/features/rapports/rapports_exports_screen.dart',
    ],
    'rapport-stocks-synth.html': [
      'lib/features/rapports/rapports_exports_screen.dart',
    ],
    'gestion-stocks.html': ['lib/features/stocks/gestion_stocks_screen.dart'],
    'catalogue-view.html': [
      'lib/features/stocks/catalogue_produits_screen.dart',
      'lib/features/stocks/ajouter_produit_screen.dart',
    ],
    'seuils-alerte.html': [
      'lib/features/stocks/catalogue_produits_screen.dart',
    ],
    'historique-ventes.html': ['lib/features/ventes/ventes_devis_screen.dart'],
    'suivi-reproduction.html': [
      'lib/features/elevage/suivi_reproduction_screen.dart',
    ],
    'vms-registre.html': ['lib/features/elevage/soins_vaccins_screen.dart'],
    'vms-calendrier.html': ['lib/features/elevage/soins_vaccins_screen.dart'],
    'elevage-dashboard.html': [
      'lib/features/elevage/dashboard_elevage_screen.dart',
    ],
    'dashboard.html': ['lib/features/pilotage/tableau_de_bord_screen.dart'],
    // Mon Profil (ticket F0.57).
    'mon-profil.html': ['lib/features/profil/mon_profil_screen.dart'],
    // Bilan Technico-Économique, onglet du Dashboard Élevage (ticket F0.63).
    'bilan-technico-economique.html': [
      'lib/features/elevage/bilan_technico_economique_vue.dart',
      'lib/features/elevage/bilan_technico_economique_repository.dart',
    ],
    // Fiche Sujet (ticket F0.65).
    'animal-details.html': [
      'lib/features/elevage/fiche_sujet_screen.dart',
      'lib/features/elevage/sujets_repository.dart',
    ],
    // Contactez l'Éditeur (ticket F0.62).
    'contact-editeur.html': [
      'lib/features/contact/contact_editeur_screen.dart',
      'lib/features/contact/contact_editeur_repository.dart',
    ],
    // Aide & À Propos (ticket F0.60).
    'aide-a-propos.html': [
      'lib/features/aide/aide_a_propos_screen.dart',
      'lib/features/aide/aide_a_propos_repository.dart',
    ],
    // Centre de Notifications (ticket F0.59).
    'notifications.html': [
      'lib/features/notifications/notifications_screen.dart',
    ],
    // Les six onglets du hub Paramètres Général (ticket F0.51).
    'roles-permissions.html': [
      'lib/features/parametres/parametres_generaux_screen.dart',
    ],
    'parametres.html': [
      'lib/features/parametres/parametres_generaux_screen.dart',
    ],
    'modules-actifs.html': [
      'lib/features/parametres/parametres_generaux_screen.dart',
    ],
    'gestion-utilisateurs.html': [
      'lib/features/parametres/parametres_generaux_screen.dart',
    ],
    'modes-paiement.html': [
      'lib/features/parametres/parametres_generaux_screen.dart',
    ],
    'audit-logs.html': [
      'lib/features/parametres/parametres_generaux_screen.dart',
    ],
    // Les quatre pages comptables portées (ticket F0.50).
    'plan-comptable.html': [
      'lib/features/comptabilite/comptabilite_screen.dart',
    ],
    'journal-comptable.html': [
      'lib/features/comptabilite/comptabilite_screen.dart',
    ],
    'grand-livre.html': ['lib/features/comptabilite/comptabilite_screen.dart'],
    'balance-generale.html': [
      'lib/features/comptabilite/comptabilite_screen.dart',
    ],
    // Les trois onglets du hub Administration & Document (ticket F0.49).
    'gestion-courriers.html': [
      'lib/features/administration/administration_screen.dart',
      // F0.78 : la modale « Nouveau Courrier » et « Confirmer l'archivage ».
      'lib/features/administration/courrier_modales.dart',
    ],
    'archivage-documents.html': [
      'lib/features/administration/administration_screen.dart',
      // F0.79 : la modale « Archiver un Document » et « Confirmer l'archivage ».
      'lib/features/administration/archive_modales.dart',
    ],
    'documents-administratifs.html': [
      'lib/features/administration/administration_screen.dart',
      // F0.80 : la modale « Générer un Document » et « Confirmer l'archivage ».
      'lib/features/administration/document_modales.dart',
    ],
    // Les cinq onglets du hub Personnel & Stages (ticket F0.48).
    'registre-employes.html': ['lib/features/rh/personnel_stages_screen.dart'],
    'registre-stagiaires.html': [
      'lib/features/rh/personnel_stages_screen.dart',
    ],
    'feuille-pointage.html': [
      'lib/features/rh/personnel_stages_screen.dart',
      'lib/features/rh/personnel_repository.dart',
    ],
    'gestion-paie.html': ['lib/features/rh/personnel_stages_screen.dart'],
    'rh-attestations.html': [
      'lib/features/rh/personnel_stages_screen.dart',
      'lib/features/rh/attestations_vue.dart',
      'lib/features/rh/attestations_repository.dart',
    ],
    // Profil Fournisseur (ticket F0.70).
    'profile-fournisseur.html': [
      'lib/features/achats/profil_fournisseur_screen.dart',
      'lib/features/achats/fournisseurs_repository.dart',
    ],
    // Ajouter / Modifier un Produit (ticket F0.67).
    'ajouter-produit.html': [
      'lib/features/stocks/ajouter_produit_screen.dart',
      'lib/features/stocks/produits_repository.dart',
    ],
    // Facturation & MeCeF (ticket F0.47).
    'facturation.html': ['lib/features/ventes/facturation_screen.dart'],
    // Les trois onglets du hub Fournisseurs (ticket F0.46).
    'ajouter-fournisseur.html': [
      'lib/features/achats/fournisseurs_screen.dart',
      'lib/features/achats/fiche_fournisseur_modales.dart',
    ],
    'fiches-fournisseurs.html': [
      'lib/features/achats/fournisseurs_screen.dart',
      'lib/features/achats/fiche_fournisseur_modales.dart',
    ],
    'dettes-fournisseurs.html': [
      'lib/features/achats/fournisseurs_screen.dart',
    ],
    // Les trois onglets du hub Achats & Commandes (ticket F0.45).
    'enregistrer-achat.html': [
      'lib/features/achats/achats_commandes_screen.dart',
    ],
    'liste-achats.html': [
      'lib/features/achats/achats_commandes_screen.dart',
      'lib/features/achats/achats_modales.dart',
    ],
    'bons-commande.html': ['lib/features/achats/achats_commandes_screen.dart'],
    'parametres-elevage.html': [
      'lib/features/elevage/parametres_elevage_screen.dart',
      'lib/features/elevage/parametres_elevage_repository.dart',
    ],
    // Les quatre onglets du hub Clients et Créances (ticket F0.43).
    'liste-clients.html': [
      'lib/features/clients/clients_creances_screen.dart',
      'lib/features/clients/fiche_client_modales.dart',
    ],
    'suivi-dettes.html': ['lib/features/clients/clients_creances_screen.dart'],
    'relances-clients.html': [
      'lib/features/clients/clients_creances_screen.dart',
    ],
    'historique-avances.html': [
      'lib/features/clients/clients_creances_screen.dart',
      'lib/features/clients/avances_modales.dart',
    ],
  };

  /// ⚠️⚠️ **CHAQUE ABSENCE PORTE SA RAISON.** Un libellé du prototype qui
  /// n'existe pas dans l'écran est un écart : soit il est justifié et il
  /// figure ici, soit c'est une dérive et le test échoue. Une liste
  /// d'exemptions sans motif ne serait qu'un moyen de faire taire le contrôle.
  const exemptions = <String, String>{
    // ── Référentiels : le serveur ignore tout envoi les concernant. Créer ou
    //    modifier un produit au poste donnerait une saisie effacée au tirage
    //    suivant (ticket F0.39). ⚠️ Depuis F0.67, créer et modifier un produit
    //    PASSE PAR LE SERVEUR (en ligne) : « Nouveau Produit » et « Modifier le
    //    Produit » sont portés. Restent en lecture seule : archivage, seuils.
    'Ajouter Stock': 'référentiel en lecture seule au poste',
    'Confirmer la Suppression ?': 'référentiel en lecture seule au poste',
    'Oui, Supprimer définitivement': 'référentiel en lecture seule au poste',
    'Configurer un Seuil': 'référentiel en lecture seule au poste',
    '+ Configurer un Seuil': 'référentiel en lecture seule au poste',

    // ── Import / export : ni sélecteur de fichier, ni analyseur de tableur,
    //    ni chaîne d'édition PDF au poste.
    'Importer un Inventaire': 'import de fichier non embarqué',
    'Telecharger inventory_template.xlsx': 'import de fichier non embarqué',
    'Importer des Soins (CSV/Excel)': 'import de fichier non embarqué',
    'Télécharger PDF': "chaîne d'édition non embarquée",

    // ── Correction d'un cycle de reproduction : le poste ne DÉCLARE que la
    //    saillie ; palpation, mise bas et sevrage corrigent un cycle que le
    //    serveur a pu faire évoluer (ticket F0.35).
    'Modifier la Fiche Lapine': 'correction de cycle réservée au web',
    'Modifier la Fiche Truie': 'correction de cycle réservée au web',
    "Modifier le Lot d'Incubation": 'correction de cycle réservée au web',
    'Modifier le Bac de Ponte': 'correction de cycle réservée au web',
    'Saisir Sevrage': 'correction de cycle réservée au web',
    'Saisir Mise Bas': 'correction de cycle réservée au web',
    'Enregistrer le Résultat': 'correction de cycle réservée au web',
    'Enregistrer la Mise Bas': 'correction de cycle réservée au web',
    'Enregistrer le Sevrage': 'correction de cycle réservée au web',
    'Enregistrer les Modifications': 'correction de cycle réservée au web',
    // ⚠️ Le titre porte un emplacement de nom de truie (« — ») que la
    //    maquette remplit en JavaScript.
    'Enregistrer la Mise Bas — —': 'correction de cycle réservée au web',

    // ── Panneaux Volailles et Escargots : rendus en RÉSUMÉ, jamais en second
    //    formulaire — la donnée se saisit sur la fiche d'espèce (F0.34).
    "Lancer un Lot d'Incubation": 'saisie faite sur la fiche espèce',
    "Lancer un Lot d'Incubation (Couvoir)": 'saisie faite sur la fiche espèce',
    "Lancer l'Incubation": 'saisie faite sur la fiche espèce',
    'Déclarer un Bac de Ponte': 'saisie faite sur la fiche espèce',
    'Placer un Bac de Ponte (Héliciculture)':
        'saisie faite sur la fiche espèce',
    'Enregistrer le Bac de Ponte': 'saisie faite sur la fiche espèce',
    'Code Incubation': 'onglet rendu en résumé',
    'Bande Reproducteurs': 'onglet rendu en résumé',
    'Date Incubation (J0)': 'onglet rendu en résumé',
    'Éclosion Attendue (J+21)': 'onglet rendu en résumé',
    'Taux Éclosion (%)': 'onglet rendu en résumé',
    'Code Bac Ponte': 'onglet rendu en résumé',
    'Date Placement': 'onglet rendu en résumé',
    'Œufs Pondus (terre)': 'onglet rendu en résumé',
    'Éclosion Attendue (J+25)': 'onglet rendu en résumé',
    'Parc / Bâtiment': 'référentiel des emplacements absent du schéma',
    'Parc / Fosse': 'référentiel des emplacements absent du schéma',

    // ── Accordéon des KPI : repli propre au mobile ; le poste est un écran de
    //    bureau, où le panneau est toujours déplié.
    'Indicateurs de performance': 'accordéon mobile sans objet au poste',
    'Indicateurs de Reproduction & Éclosion (Replier / Déplier)':
        'accordéon mobile sans objet au poste',
    'Résumé sanitaire': 'accordéon mobile sans objet au poste',

    // ── Modules non embarqués, déjà annoncés à l'écran (tickets F0.33, F0.37).
    'Détail de la Vente': 'module non embarqué au poste',
    'Annuler la Vente': 'module non embarqué au poste',
    "Émettre l'Avoir": 'module non embarqué au poste',
    'Relancer': 'module non embarqué au poste',
    'Détail des Coûts': 'bilan technico-économique non embarqué',
    'Détail des Revenus': 'bilan technico-économique non embarqué',
    'Dossier Clinique': 'infirmerie non synchronisée',
    'Alertes Sanitaires du Jour': 'infirmerie non synchronisée',
    'Maladies les Plus Fréquentes — 2026 vs 2025':
        "historique de l'an dernier non synchronisé",
    'Cas 2025': "historique de l'an dernier non synchronisé",
    'Cas 2026': "historique de l'an dernier non synchronisé",
    'Maladie / Symptôme': 'taxonomie des maladies absente du schéma',
    'Période de Sensibilité': 'taxonomie des maladies absente du schéma',
    'Répartition Saisonnière des Cas (2026)':
        'taxonomie des maladies absente du schéma',

    // ── Titres paramétrés : l'écran les compose avec la donnée réelle, la
    //    maquette les fige sur son jeu de démonstration.
    'Bienvenue, Manager Olouwachegoun 👋':
        "composé avec le nom de l'utilisateur",
    'Évolution du GMQ — LOT-LAP-2026-06 (Cuniculture, 8 dernières semaines)':
        'composé avec la bande réellement suivie',

    // ── Modales de rappel : déclenchées par le calendrier prophylactique, que
    //    l'onglet Calendrier rend déjà (ticket F0.36).
    'Rappel de Prophylaxie du Jour': 'rendu par le Calendrier Vétérinaire',
    "Détail de l'Intervention": 'rendu par le Calendrier Vétérinaire',
    'Planifier une Intervention':
        'calendrier calculé depuis le protocole, non saisi',
    // ⚠️ Confirmer l'administration d'un soin, c'est l'écrire au registre —
    //    ce que fait la modale « Nouveau Soin » de l'onglet précédent.
    'Confirmer Administration': 'porté par la modale Nouveau Soin',

    // ── Colonnes et libellés du détail d'une vente, non embarqué.
    'Qté': 'module non embarqué au poste',
    'P.U': 'module non embarqué au poste',
    'Désignation': 'module non embarqué au poste',
    'Modifier': 'référentiel en lecture seule au poste',

    // ── Hub Clients et Créances (ticket F0.43) : les fiches clients s'écrivent
    //    au poste depuis F0.72 ; les exemptions globales qui les couvraient
    //    ont été retirées (elles masquaient d'autres pages) — chaque page garde
    //    la sienne, voir `exemptionsParPage`.

    // ── Un règlement décaisse ET passe son écriture SYSCOHADA : il ne peut
    //    pas se faire hors ligne sans canal d'envoi, et `receivables` n'en a
    //    pas. Encaisser reste une opération de la surface web.
    'Ajouter un Recouvrement': 'encaissement non embarqué au poste',
    'Valider le Décaissement': 'encaissement non embarqué au poste',
    'Montant du Règlement (FCFA)': 'encaissement non embarqué au poste',
    'Compte Débité': 'encaissement non embarqué au poste',
    'Nouveau Solde Dû': 'encaissement non embarqué au poste',

    // ── Envoyer une relance suppose le réseau ET le canal mail du serveur ;
    //    surtout, `customer_reminders` est en lecture seule : une relance
    //    partie du poste ne serait inscrite nulle part, et le client serait
    //    rappelé une seconde fois depuis le web le lendemain. Le motif est
    //    affiché à l'écran, pas seulement ici.
    'Relancer WhatsApp': 'envoi impossible hors ligne et non traçable au poste',
    'Relancer par Mail': 'envoi impossible hors ligne et non traçable au poste',
    'Exporter Courrier': "chaîne d'édition non embarquée",
    // ⚠️ Aucune table de modèles n'existe — le web le documente aussi : son
    //    propre bouton n'y persiste rien. Un bouton qui annonce « sauvegardé »
    //    sans rien enregistrer est un mensonge d'interface.
    'Sauvegarder Modèle': 'aucune table de modèles dans le schéma',

    // ── Imports et exports : chaîne de fichiers non embarquée au poste.
    'Importer des Clients': "chaîne d'import non embarquée",
    'Exporter les Clients': "chaîne d'édition non embarquée",
    'Parcourir les fichiers': "chaîne d'import non embarquée",
    'Télécharger le modèle client_sample.xlsx': "chaîne d'import non embarquée",
    'Télécharger clients.xlsx': "chaîne d'édition non embarquée",
    'PDF': "chaîne d'édition non embarquée",

    // ── Paramètres Élevage (ticket F0.44) : les quatre onglets sont des
    //    référentiels du serveur, qui ignore tout envoi les concernant. Une
    //    ration corrigée au poste disparaîtrait au tirage suivant, sans un mot.
    'Saisir une Ration': 'référentiel en lecture seule au poste',
    'Ajouter une Ration': 'référentiel en lecture seule au poste',
    'Échéance de Prophylaxie': 'référentiel en lecture seule au poste',
    'Ajouter une Échéance': 'référentiel en lecture seule au poste',
    'Type de Provende': 'référentiel en lecture seule au poste',
    'Ajouter un Type': 'référentiel en lecture seule au poste',
    'Enregistrer Tous les Formats de Numérotation':
        'référentiel en lecture seule au poste',
    'Espèce *': 'référentiel en lecture seule au poste',
    "Stade Physiologique / Tranche d'Âge *":
        'référentiel en lecture seule au poste',
    'Ration Normative (en Grammes g/tête/jour) *':
        'référentiel en lecture seule au poste',
    'Jour / Âge *': 'référentiel en lecture seule au poste',
    'Traitement Prévu *': 'référentiel en lecture seule au poste',
    'Produit Conseillé *': 'référentiel en lecture seule au poste',
    'Dose *': 'référentiel en lecture seule au poste',
    "Délai de Rémanence (Jours d'attente)":
        'référentiel en lecture seule au poste',
    "Nom du Type d'Aliment *": 'référentiel en lecture seule au poste',
    'Espèce Cible *': 'référentiel en lecture seule au poste',
    'Poids Sac Standard (Kg) *': 'référentiel en lecture seule au poste',
    'Prix Indicatif (FCFA / Kg) *': 'référentiel en lecture seule au poste',

    // ⚠️⚠️ NOTATION LaTeX LAISSÉE DANS LA MAQUETTE — « Lapines
    //    Reproductrices (\$R_1..R_n\$) ». Les `\$…\$` sont un artefact
    //    d'écriture, pas un libellé : tels quels, ils s'afficheraient à
    //    l'éleveur. L'écran rend « (R1..Rn) ». C'est le SEUL cas de ce ticket
    //    où le poste ne recopie pas le mot à mot de la maquette, et il est
    //    signalé comme un défaut du prototype.
    //    **ARBITRAGE CLIENT** : corriger les quatre libellés du prototype ?
    r'Lapines Reproductrices ($R_1..R_n$)':
        'notation LaTeX du prototype, rendue lisible',
    r'Mâles Saillisseurs ($M_1..M_n$)':
        'notation LaTeX du prototype, rendue lisible',
    r'Truies Reproductrices ($T_1..T_n$)':
        'notation LaTeX du prototype, rendue lisible',
    r'Verrats Reproducteurs ($V_1..V_n$)':
        'notation LaTeX du prototype, rendue lisible',
    // ── Hub Achats & Commandes (ticket F0.45).
    //
    // Créer un fournisseur ou un produit depuis le poste : le serveur ignore
    // tout envoi sur ces deux référentiels, la saisie serait effacée au tirage
    // suivant sans un mot.
    'Raison sociale *': 'référentiel en lecture seule au poste',
    'Telephone *': 'référentiel en lecture seule au poste',
    'Designation *': 'référentiel en lecture seule au poste',
    'Désignation *': 'référentiel en lecture seule au poste',

    // ── Ticket F0.74 — RETOURS ET REMBOURSEMENTS FOURNISSEURS PORTÉS.
    //    Neuf exemptions GLOBALES « contre-passation réservée au web » (dont les mots
    //    courants « Fournisseur * », « Compte de Trésorerie », « Retour Fournisseur »)
    //    sont retirées : fausses depuis ce ticket, et elles masquaient les autres pages.
    //    Les libellés d'import, eux, restent exemptés PAR PAGE (voir `exemptionsParPage`,
    //    `liste-achats.html`) : décision D10.
    'Importer des Achats':
        "import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'achats",
    'Télécharger purchase_sample.xlsx':
        "import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'achats",

    // ⚠️ VALEURS DE DÉMONSTRATION, PAS DES LIBELLÉS. La maquette écrit ses
    //    références d'achat en dur dans des `<button>` ; l'extracteur les
    //    relève comme des mots de vocabulaire. Aucune référence d'achat
    //    n'existe d'ailleurs dans le schéma — voir `_reference()`.
    'ACH-2026-101': 'valeur de démonstration de la maquette',
    'ACH-2026-100': 'valeur de démonstration de la maquette',
    'ACH-2026-099': 'valeur de démonstration de la maquette',
    'ACH-2026-098': 'valeur de démonstration de la maquette',

    // ⚠️⚠️ SAISIR UN BON DE COMMANDE ENGAGE LA FERME auprès d'un fournisseur,
    //    et le serveur sert les bons en LECTURE SEULE : un bon saisi au poste
    //    serait effacé au tirage suivant — après que le fournisseur ait été
    //    appelé. Le poste les affiche, il ne les crée pas.
    'Bons de commande émis': 'bons servis en lecture seule au poste',
    'Ajouter au bon de commande': 'bons servis en lecture seule au poste',
    'Générer le Bon': 'bons servis en lecture seule au poste',
    'Date de Livraison Attendue': 'bons servis en lecture seule au poste',
    "Produit / Article d'Approvisionnement":
        'bons servis en lecture seule au poste',
    'Quantité': 'bons servis en lecture seule au poste',
    'P.U Estimé (FCFA)': 'bons servis en lecture seule au poste',
    'Valider la réception': 'réception de commande réservée au web',
    'Confirmer la Réception': 'réception de commande réservée au web',
    'Exporter le Bon (PDF)': "chaîne d'édition non embarquée",

    // ── Hub Fournisseurs (ticket F0.46, révisé F0.71). Depuis F0.71 une fiche se
    //    crée, se modifie et s'archive AU POSTE (en attente d'envoi) : les
    //    exemptions « référentiel en lecture seule » de ces libellés étaient
    //    devenues fausses et masquaient les pages voisines. Retirées du global.
    'Importer des Fournisseurs': "chaîne d'import non embarquée",
    'Telecharger le modele supplier_sample.xlsx':
        "chaîne d'import non embarquée",

    // ⚠️ F0.69 : le règlement fournisseur EXISTE au poste (en attente d'envoi).
    //    Ne reste que le titre de gabarit « Modifier — … ».
    'Modifier — Dettes Fournisseurs':
        'titre de gabarit : la dette est générée par un achat, elle ne se modifie pas',
    // ── Facturation & MeCeF (ticket F0.47).
    //
    // ⚠️⚠️ LE FORMULAIRE « NOUVELLE FACTURE » DE LA MAQUETTE (Client +
    //    Montant HT + TVA, SANS ARTICLE) produirait une facture déconnectée
    //    de toute vente et de tout stock. La surface web a tranché en
    //    redirigeant vers la caisse (ticket 7.1) ; le poste applique la même
    //    règle, son bouton ouvre la caisse.
    'Montant HT (FCFA) *': 'facture créée à la caisse, jamais ici',
    'Taux de TVA *': 'facture créée à la caisse, jamais ici',
    '+ Nouvelle Facture': 'facture créée à la caisse, jamais ici',
    // ⚠️ Modifier une facture déjà transmise à la DGI romprait l'intégrité
    //    fiscale : le web ne le fait pas non plus.
    'Modifier — Facturation & MeCeF': 'intégrité fiscale — jamais modifiable',
    // ── Hub Personnel & Stages (ticket F0.48). Les registres sont des
    //    référentiels du serveur : embaucher, corriger un salaire ou
    //    archiver une fiche depuis le poste donnerait une saisie effacée au
    //    tirage suivant.
    'Nouvel Employé': 'référentiel en lecture seule au poste',
    '+ Nouvel Employé': 'référentiel en lecture seule au poste',
    'Fonction *': 'référentiel en lecture seule au poste',
    "Date d'embauche *": 'référentiel en lecture seule au poste',
    'Salaire (FCFA) *': 'référentiel en lecture seule au poste',
    'Nouveau Stagiaire': 'référentiel en lecture seule au poste',
    "Établissement d'origine *": 'référentiel en lecture seule au poste',
    'Date de début': 'référentiel en lecture seule au poste',
    'Date de fin': 'référentiel en lecture seule au poste',
    'Frais de stage (FCFA)': 'référentiel en lecture seule au poste',

    // ⚠️⚠️ LES ABSENCES D'UN STAGIAIRE vivent dans `internship_absences`,
    //    que le poste ne reçoit pas — et la feuille de pointage ne les couvre
    //    pas : `attendance_records.employee_id` pointe sur `employees`, et un
    //    stagiaire n'est pas un employé dans le schéma.
    'Absences / Abandon': 'absences de stagiaire non embarquées',
    "Date de l'absence": 'absences de stagiaire non embarquées',
    'Motif': 'absences de stagiaire non embarquées',

    // ⚠️ LE BOUTON DE LA MODALE DE POINTAGE porte le libellé court de la
    //    maquette (« Enregistrer un Pointage ») ; la variante préfixée « + »
    //    est celle du bouton flottant mobile, sans objet sur un écran de
    //    bureau.
    '+ Enregistrer un Pointage': 'bouton flottant mobile sans objet au poste',

    // ⚠️⚠️ LA PAIE SE CALCULE SUR LE SERVEUR : barème ITS, retenues CNSS
    //    et bulletins (`payslips`) n'existent pas au poste. Un net à payer
    //    recomposé ici donnerait à l'employé un chiffre que son bulletin ne
    //    confirmerait pas — et c'est son salaire.
    'Télécharger le Bulletin PDF': 'paie et bulletins calculés sur le web',

    // ── Attestations : LES EXEMPTIONS GLOBALES « chaîne d'édition non embarquée »
    //    SONT RETIRÉES (ticket F0.64). Elles étaient périmées : la chaîne existe,
    //    côté serveur, et le poste la pilote. Les rares écarts restants sont
    //    déclarés PAR PAGE, sous `rh-attestations.html`, avec leur vraie raison.
    // ── Hub Administration & Document (ticket F0.49). Les trois onglets
    //    sont en consultation pure : enregistrer un courrier, archiver une
    //    piece ou generer un document supposent la PIECE JOINTE, l'en-tete
    //    officielle et la signature — trois choses que le poste n'a pas.
    // F0.80 : « Générer un Document », « + Générer un Document », « Type de document * » et
    // « Bénéficiaire * » ne sont PLUS exemptés — l'écran les porte, le test les exige. (« Date
    // * » reste exempté globalement, hérité des courriers : voir le test dédié de
    // `documents_poste_test.dart`.)
    // ── Comptabilite (ticket F0.50).
    //
    // ⚠️⚠️ AUCUNE ECRITURE NE SE SAISIT AU POSTE, et ce n'est pas un
    //    manque. Une ecriture nait d'une OPERATION — vente, achat, depense,
    //    ponte, ecart d'inventaire — et le serveur la genere lui-meme. C'est
    //    ce qui garantit qu'aucun mouvement ne pese sur les comptes sans
    //    avoir pese sur le stock ou la caisse. Une saisie manuelle au poste
    //    romprait ce lien.
    "Saisie d'Écriture": 'ecriture generee par une operation, jamais saisie',
    "+ Saisie d'Écriture": 'ecriture generee par une operation, jamais saisie',
    "Date de l'écriture *": 'ecriture generee par une operation, jamais saisie',
    'Compte à débiter *': 'ecriture generee par une operation, jamais saisie',
    'Compte à créditer *': 'ecriture generee par une operation, jamais saisie',
    'Montant (FCFA) *': 'ecriture generee par une operation, jamais saisie',
    'Libellé *': 'ecriture generee par une operation, jamais saisie',

    // ⚠️ Le plan comptable est un referentiel du serveur.
    'Nouveau Compte': 'référentiel en lecture seule au poste',
    '+ Nouveau Compte': 'référentiel en lecture seule au poste',
    'Numéro de compte *': 'référentiel en lecture seule au poste',
    'Intitulé *': 'référentiel en lecture seule au poste',
    'Classe *': 'référentiel en lecture seule au poste',
    // ── Hub Paramètres Général (ticket F0.51).
    //
    // ⚠️⚠️ LA MAQUETTE N'ACCENTUE PAS TOUJOURS SES TITRES ni ses en-têtes.
    //    L'écart est le même que celui déjà relevé sur `gestion-stocks`, et il
    //    fait l'objet d'un ARBITRAGE CLIENT ouvert : le poste écrit le
    //    français correct, la maquette garde sa graphie. Corriger la maquette
    //    ici, sans mandat, serait décider à la place du client.
    'Roles & Permissions': "titre non accentué dans la maquette (arbitrage)",
    "Matrice des Droits d'Acces":
        "titre non accentué dans la maquette (arbitrage)",
    'Elevage & Soins': "en-tête non accentué dans la maquette (arbitrage)",
    'Comptabilite': "en-tête non accentué dans la maquette (arbitrage)",
    'Mobile Money - Multi-Operateurs (5212)':
        "titre non accentué dans la maquette (arbitrage)",
    'Resume des comptes de tresorerie':
        "titre non accentué dans la maquette (arbitrage)",

    // ⚠️⚠️ LES SAUVEGARDES DE LA BASE RESTENT SUR LE SERVEUR : des fichiers
    //    `.sql` de plusieurs dizaines de méga-octets, produits par une tâche
    //    planifiée. Le poste n'a ni les fichiers, ni le droit d'en déclencher
    //    un — et un bouton qui ne sauvegarde rien serait pire qu'absent.
    'Sauvegardes de la Base de Donnees':
        'sauvegardes produites et gardées sur le serveur',
    'Generer une Sauvegarde': 'sauvegardes produites et gardées sur le serveur',
    'Fichier': 'sauvegardes produites et gardées sur le serveur',
    'Taille': 'sauvegardes produites et gardées sur le serveur',

    // ⚠️⚠️ UN RÔLE SE DÉFINIT SUR LE SERVEUR, JAMAIS AU POSTE. Créer ou
    //    modifier un rôle depuis une machine hors ligne changerait les droits
    //    de toute la ferme, et le tirage suivant écraserait la modification
    //    sans la signaler — `roles` est un référentiel remplacé.
    'Nouveau Role': 'définition des rôles réservée au web',
    'Nom du role *': 'définition des rôles réservée au web',
    'Modules autorises': 'définition des rôles réservée au web',
    'Elevage': 'définition des rôles réservée au web',
    'Modifier le Rôle': 'définition des rôles réservée au web',
    'Nom du rôle *': 'définition des rôles réservée au web',
    'Modules autorisés': 'définition des rôles réservée au web',
    'Supprimer ce Rôle ?': 'définition des rôles réservée au web',
    'Supprimer Définitivement': 'définition des rôles réservée au web',

    // ⚠️⚠️ NI MOT DE PASSE NI JETON NE DESCENDENT AU POSTE, et un compte ne
    //    s'y crée donc pas : il faudrait choisir un mot de passe, c'est-à-dire
    //    le faire transiter et le stocker sur la machine la plus exposée du
    //    dispositif.
    'Nouvel Utilisateur': "création de compte réservée au web",
    '+ Nouvel Utilisateur': "création de compte réservée au web",
    'Email *': "création de compte réservée au web",
    'Rôle *': "création de compte réservée au web",

    // ⚠️⚠️ LE SERVEUR SMTP PORTE UN MOT DE PASSE. Le descendre ferait d'un
    //    poste volé une clé d'accès à la boîte mail de la ferme :
    //    `smtp_password_encrypted` reste sur le serveur, et le poste n'a même
    //    pas de colonne où le ranger.
    'Serveur SMTP': "configuration technique gardée sur le serveur",
    'Port': "configuration technique gardée sur le serveur",
    'Utilisateur SMTP': "configuration technique gardée sur le serveur",
    'Envoyer un e-mail de test':
        "configuration technique gardée sur le serveur",

    // ⚠️ L'ASTÉRISQUE MARQUE UNE SAISIE OBLIGATOIRE : le poste affiche ces
    //    deux champs en lecture seule, l'identité de la ferme se modifiant sur
    //    le web. Le libellé nu — « Raison Sociale », « Identifiant Fiscal
    //    Unique (IFU) » — est bien présent à l'écran.
    'Raison Sociale *': 'identité de la ferme en lecture seule au poste',
    'Identifiant Fiscal Unique (IFU) *':
        'identité de la ferme en lecture seule au poste',

    // ⚠️⚠️ OUVRIR UN COMPTE DE TRÉSORERIE, C'EST OUVRIR UN COMPTE DU PLAN
    //    SYSCOHADA — pas cocher une case. RIB, IBAN et numéros de ligne ne
    //    descendent pas davantage : ce sont les coordonnées bancaires de la
    //    ferme, et le poste n'a aucun besoin de les porter pour afficher un
    //    solde.
    'Ajouter un Compte Bancaire': 'ouverture de compte réservée au web',
    'Ajouter une Ligne Mobile Money': 'ouverture de compte réservée au web',
    'Banque *': 'ouverture de compte réservée au web',
    'Titulaire du Compte': 'coordonnées bancaires non descendues au poste',
    'RIB *': 'coordonnées bancaires non descendues au poste',
    'IBAN *': 'coordonnées bancaires non descendues au poste',
    'Sous-compte Auxiliaire': 'ouverture de compte réservée au web',
    'Operateur *': 'ouverture de compte réservée au web',
    'Numero de Telephone *': 'coordonnées bancaires non descendues au poste',
    'Titulaire de la Ligne': 'coordonnées bancaires non descendues au poste',
    'Numero de Serie SIM': 'coordonnées bancaires non descendues au poste',

    // ⚠️ L'export du journal d'audit produit un PDF ou un CSV : aucune chaîne
    //    d'édition n'est embarquée au poste, et la trace complète vit de
    //    toute façon sur le serveur.
    'Exporter le Journal': "chaîne d'édition non embarquée",
    '+ Exporter le Journal': "chaîne d'édition non embarquée",
    'Période à exporter *': "chaîne d'édition non embarquée",
    // ⚠️ **CES DEUX MOTIFS ONT CHANGÉ DE SENS AU TICKET F0.52.** La chaîne
    // d'édition EXISTE désormais (`ExportOfficiel`, `ExportTableur`) : ce
    // n'est plus « non embarquée ». Ce sont les ÉCRANS concernés qui ne
    // l'appellent pas — leurs boutons restent inertes, décision de leurs
    // propres tickets. Les recâbler dépasse le portage de Rapports & Exports
    // et mérite son ticket.
    "Format d'export *": "écran qui n'appelle pas la chaîne d'édition (F0.52)",
    // ── Boutons génériques des modales, portés par `ModaleAgri`.
    'Annuler': 'porté par BoutonModaleSecondaire',
    'Enregistrer': 'porté par BoutonModalePrimaire',
    'Fermer': 'porté par BoutonModaleSecondaire',
    // ── Ticket F0.52 — Rapports & Exports.
    // ⚠️ **AFFORDANCE DE PETIT ÉCRAN, PAS UN CONTENU.** Ce bouton est
    // `md:hidden` dans la maquette : il ne s'affiche QUE sous 768 px, pour
    // replier les quatre cartes d'indicateur sur un téléphone. La fenêtre du
    // poste est ouverte sans cadre et maximisée sur le PC de la ferme — le
    // repli n'y a aucun sens, et les quatre cartes y tiennent. Même
    // traitement que la navigation basse et la recherche mobile, écartées
    // pour la même raison.
    'Indicateurs Zootechniques (Replier / Déplier)':
        'accordéon `md:hidden` — affordance mobile, fenêtre du poste maximisée',
  };

  /// Exemptions PROPRES À UNE PAGE — ticket F0.53.
  ///
  /// ⚠️⚠️ **POURQUOI CETTE SECONDE LISTE EXISTE.** [exemptions] est GLOBALE :
  /// une entrée y vaut pour les 46 pages. C'est juste pour « Annuler » ou
  /// « Enregistrer », que `ModaleAgri` porte partout. C'est faux dès que le
  /// libellé est un mot courant.
  ///
  /// Le cas a été mesuré au moment même de sa création : exempter « Date »
  /// globalement, pour la seule colonne du tableau des sauvegardes de
  /// `roles-permissions.html`, **retirait le contrôle de « Date » sur QUATORZE
  /// autres pages** — dont l'historique des ventes, le journal comptable, le
  /// grand livre et trois rapports, où la colonne est bel et bien affichée.
  /// Dix-sept contrôles réels auraient disparu **en silence**, et le fichier
  /// aurait affiché un motif parfaitement raisonnable.
  ///
  /// ⚠️ Une exemption n'est donc globale que si elle vaut VRAIMENT partout.
  /// Dans le doute, elle va ici.
  const exemptionsParPage = <String, Map<String, String>>{
    // ── Ticket F0.73 — les exemptions GLOBALES de l'écran Historique Avances
    //    (« Nouvelle Avance », « Imputer un Acompte », « Affecter », « Client * »,
    //    « Mode de Paiement »…) disaient « encaissement non embarqué » : fausses depuis
    //    ce ticket, retirées. « Client * » masquait aussi facturation.html, « Mode de
    //    Paiement » enregistrer-achat.html, « Exporter » et « Importer » cinq pages.
    //    Ne restent que les trois libellés d'import, par page, avec le motif vrai.
    'historique-avances.html': {
      'Importer':
          "import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'avances",
      'Importer des Avances':
          "import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'avances",
      'Télécharger advances_template.xlsx':
          "import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'avances",
    },
    'liste-achats.html': {
      'Importer':
          "import xlsx/csv non porté : décision D10, le serveur (Laravel) n'a aucun import d'achats",
    },
    'gestion-paie.html': {
      'Exporter': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
    },
    // ── Ticket F0.75 — « Exporter PDF » / « Imprimer » : les exemptions
    //    GLOBALES « chaîne d'édition non embarquée » étaient fausses depuis
    //    F0.52 ET masquaient dix-huit pages ; chaque page garde la sienne, avec
    //    le motif vrai : le bouton existe dans la maquette, l'écran n'appelle
    //    pas encore ExportOfficiel.
    'seuils-alerte.html': {
      "Confirmer l'archivage":
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Archiver':
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Exporter PDF': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
    },
    'historique-ventes.html': {
      "Exporter": "écran qui n'appelle pas la chaîne d'édition (F0.52)",
      'Imprimer': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
    },
    'plan-comptable.html': {
      "Confirmer l'archivage":
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Archiver':
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
    },
    'journal-comptable.html': {
      "Confirmer l'archivage":
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Archiver':
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
    },
    // grand-livre.html et balance-generale.html : plus d'exemption, « Exporter PDF » porté (F0.87).
    'feuille-pointage.html': {
      'Date *':
          "ÉCART À ARBITRER (F0.81, 09/10/2026) : la maquette attend « Date * » dans la modale de pointage, l'écran ne le porte pas ; écran non modifié, décision client",
      "Confirmer l'archivage":
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Archiver':
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Exporter PDF': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
    },
    'parametres-elevage.html': {
      'Exporter PDF': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
    },
    // ── Ticket F0.65 — Fiche Sujet. Les écarts sont ceux de la page web (ticket
    //    Laravel 14.16), qui a construit l'écran « après arbitrage explicite du
    //    client » en écartant ce qui n'a aucune source réelle.
    'animal-details.html': {
      'Sujet #LAP-2026-0143':
          "valeur de démonstration (l'identifiant est celui du sujet)",
      // Matrice de liaison inter-modules : un texte de maquette sans aucune donnée.
      'Liaison avec les Autres Modules':
          'matrice sans donnée, non reprise par la page web',
      'Impact Automatique': 'matrice sans donnée, non reprise par la page web',
      // « Déclarer un Mouvement » : la page web n'offre aucune déclaration, les
      // mouvements affichés sont ceux réellement saisis (entrée, sortie).
      'Déclarer un Mouvement':
          'aucun mouvement ne se déclare : seuls les saisis sont listés',
      'Type de Mouvement *':
          'aucun mouvement ne se déclare : seuls les saisis sont listés',
      // Onglets sans source réelle : ils affichent leur motif, pas ces éléments.
      'Courbe de Croissance':
          'onglet Production sans source par sujet (motif affiché)',
      'Coût': 'onglet Alimentation sans source par sujet (motif affiché)',
      'Ajouter un Document':
          'onglet Documents sans table de pièces jointes (motif affiché)',
      // Colonnes que la page web reformule : l'historique n'enregistre pas
      // d'opérateur, les soins sont ceux de la BANDE (Action · Produit · Dose), la
      // reproduction se lit Saillie · Rôle · Mise Bas · Nés Vivants · Nés Morts.
      "Type d'Opération": 'colonne reformulée « Type » par la page web',
      'Opérateur': "aucun opérateur n'est enregistré sur l'historique",
      'Traitement / Vaccin':
          'colonne reformulée « Action » : soins de la bande',
      'Vétérinaire': 'colonne absente : le soin de bande ne la porte pas',
      'Date Saillie': 'colonne reformulée « Saillie » par la page web',
      'Mise Bas Prévue (J+31)':
          'colonne reformulée « Mise Bas » (date réelle) par la page web',
    },

    // ── Ticket F0.64 — le registre des stagiaires ne génère pas d'attestation
    'registre-stagiaires.html': {
      // F0.72 : exemption globale « Nom complet * » retirée ; motif d'origine conservé,
      // à réexaminer avec l'écran Stagiaires.
      'Nom complet *': 'référentiel en lecture seule au poste',
      // La génération se fait depuis l'onglet « Attestations » du hub, où elle
      // est portée ; le registre, lui, reste une consultation.
      'Attestation de Stage': "génération faite depuis l'onglet Attestations",
      "Télécharger l'Attestation PDF":
          "génération faite depuis l'onglet Attestations",
    },

    // ── Ticket F0.69 — le règlement CLIENT n'est toujours pas embarqué : l'exemption
    //    globale « Enregistrer un Règlement » masquait la page fournisseurs, qui
    //    le porte désormais. Retirée du global, gardée ici où elle est vraie.
    'suivi-dettes.html': {
      'Exporter PDF': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
      'Enregistrer un Règlement': 'encaissement non embarqué au poste',
    },

    // ── Ticket F0.71 — Fiche fournisseur écrite au poste ───────────────────
    'ajouter-fournisseur.html': {
      '+ Nouveau Fournisseur':
          'doublon du bouton « Nouveau Fournisseur » : le « + » est une icône',
    },
    'fiches-fournisseurs.html': {
      "Importer": "chaîne d'import non embarquée",
      'Exporter PDF': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
      '+ Nouveau Fournisseur':
          'doublon du bouton « Nouveau Fournisseur » : le « + » est une icône',
      'Modifier — Fiches Fournisseurs':
          'titre de gabarit : la modale de modification est la même que celle '
          "d'« Ajouter Fournisseur »",
      // ⚠️ SUPPRESSION DÉFINITIVE NON DISPONIBLE : archiver (is_active = false)
      // ne détruit rien, et le serveur ne propose pas la suppression par l'API.
      'Supprimer la selection':
          'suppression définitive non disponible au poste : archiver suffit',
      'Destruction de fiches fournisseurs':
          'suppression définitive non disponible au poste : archiver suffit',
      'Confirmer la suppression':
          'suppression définitive non disponible au poste : archiver suffit',
    },

    // ── Ticket F0.72 — « Nom complet * » n'est plus exempté partout : ces deux pages
    //    gardent le motif d'origine, à réexaminer avec leur écran.
    'gestion-utilisateurs.html': {
      "Confirmer l'archivage":
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Archiver':
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Exporter PDF': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
      'Nom complet *': 'référentiel en lecture seule au poste',
    },
    'registre-employes.html': {
      "Confirmer l'archivage":
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Archiver':
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Exporter PDF': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
      'Nom complet *': 'référentiel en lecture seule au poste',
    },

    // ── Ticket F0.72 — fiche client : la maquette dit « Détruire » avec mot de passe
    //    administrateur ; le web archive (is_active = false), le poste suit le web.
    'liste-clients.html': {
      "Importer": "chaîne d'import non embarquée",
      'Détruire la fiche client':
          'suppression définitive non disponible : le web archive, le poste aussi',
      'Détruire les fiches clients':
          'suppression définitive non disponible : le web archive, le poste aussi',
      'Confirmer la suppression':
          'suppression définitive non disponible : le web archive, le poste aussi',
      'Téléphone *':
          "libellé de modale : le web n'exige pas le téléphone, le poste suit le web",
    },

    // ── Ticket F0.71 — exemptions globales retirées : chaque page garde la sienne.
    'facturation.html': {
      "Confirmer l'archivage":
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Archiver':
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      // « Client * » : absent de l'écran, MASQUÉ jusqu'ici par l'exemption globale
      // « encaissement non embarqué » (retirée en F0.73). Écart antérieur révélé,
      // non traité ici : à examiner avec l'écran Facturation.
      'Client *':
          "libellé non repris par l'écran, masqué jusqu'ici par une exemption "
          'globale devenue fausse (F0.73) — à examiner',
      'Mettre à jour': 'référentiel en lecture seule au poste',
    },
    'dettes-fournisseurs.html': {
      "Confirmer l'archivage":
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Exporter PDF': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
      'Mettre à jour':
          'une dette est générée par un achat : elle ne se modifie pas',
    },

    // ── Ticket F0.70 — Profil Fournisseur ──────────────────────────────────
    'profile-fournisseur.html': {
      // ⚠️ LE PROTOTYPE N'ACCENTUE AUCUN MOT DE CETTE PAGE ; la page web les
      // rétablit et le poste l'imite.
      'Enregistrer un Reglement': 'libellé non accentué dans la maquette',
      'Reference': 'libellé non accentué dans la maquette',
      'Categorie': 'libellé non accentué dans la maquette',
      'Emission': 'libellé non accentué dans la maquette',
      'Enregistrer un reglement': 'libellé non accentué dans la maquette',
      'Valider le Reglement': 'libellé non accentué dans la maquette',
      'Montant du Reglement (FCFA)': 'libellé non accentué dans la maquette',
      'Compte de Tresorerie': 'libellé non accentué dans la maquette',
    },

    // ── Ticket F0.67 — Ajouter / Modifier un Produit ───────────────────────
    'ajouter-produit.html': {
      "Confirmer l'archivage":
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Archiver':
          "absent de l'écran, constaté au ticket F0.81 (09/10/2026) ; migré de l'exemption globale « référentiel en lecture seule au poste » sans requalification page par page",
      'Mettre à jour':
          'modification : le poste porte « Enregistrer les modifications »',
      'Modifier — Ajouter un Produit':
          'titre de gabarit : Laravel et le poste disent « Modifier le Produit »',
      'Prix Unitaire':
          'écart assumé : le gabarit du prototype porte UN prix, la règle '
          'métier est Fourchette / Sur devis (comme catalogue-view.html)',
      'Prix unitaire (FCFA) *':
          'écart assumé : le gabarit du prototype porte UN prix, la règle '
          'métier est Fourchette / Sur devis (comme catalogue-view.html)',
      // ⚠️ La page du prototype embarque une LISTE de produits : elle existe déjà
      // au Catalogue (même écran, mêmes lignes). La redessiner ici ferait deux
      // listes qui dérivent.
      'Statut': 'liste de produits embarquée : elle vit au Catalogue Produits',
      'Actions': 'liste de produits embarquée : elle vit au Catalogue Produits',
      '+ Nouveau Produit':
          'bouton de la liste embarquée : il vit au Catalogue Produits',
      'Nouveau Produit':
          'bouton de la liste embarquée : il vit au Catalogue Produits',
    },

    // ── Ticket F0.64 — Attestations de Travail & de Stage ──────────────────
    'rh-attestations.html': {
      // ⚠️ LE PROTOTYPE N'ACCENTUE AUCUN MOT DE CETTE PAGE (« Generer »,
      // « Modeles », « Debut »). La page web les rétablit et le poste l'imite :
      // un écran français sans accents n'est pas un écran validé, c'est une
      // faute de saisie du prototype.
      'Generer une Attestation': 'libellé non accentué dans la maquette',
      "Generer l'Attestation": 'libellé non accentué dans la maquette',
      'Personnaliser les Modeles': 'libellé non accentué dans la maquette',
      'Enregistrer ce Modele': 'libellé non accentué dans la maquette',
      'Employe Permanent': 'libellé non accentué dans la maquette',
      'Date de Debut': 'libellé non accentué dans la maquette',
      "Note d'Evaluation (optionnel)": 'libellé non accentué dans la maquette',
      // ⚠️ OPTIONS DE MISE EN PAGE QUE LE PDF DU SERVEUR N'APPLIQUE PAS. La table
      // `attestation_templates` porte les colonnes, mais `exports.attestation`
      // n'en lit aucune et la page web ne les propose pas : des cases qui ne
      // changent rien seraient des promesses fausses.
      'Filigrane logo (centre)': "option que le PDF du serveur n'applique pas",
      'En-tete officielle': "option que le PDF du serveur n'applique pas",
      'Signature numerisee DG': "option que le PDF du serveur n'applique pas",
      'Cachet humide (scan)': "option que le PDF du serveur n'applique pas",
    },

    // ── Ticket F0.59 — Centre de Notifications ─────────────────────────────
    'notifications.html': {
      // Bouton `md:hidden` qui replie les cartes sur un écran de téléphone. Le
      // poste est une fenêtre de bureau, jamais sous 768 px : le panneau
      // repliable n'a pas d'objet, les trois cartes sont toujours visibles.
      'Résumé des alertes': 'panneau repliable des petits écrans (md:hidden)',
    },
    // ── Ticket F0.53 — LES QUINZE QUE LE CONTRÔLE LAISSAIT PASSER ──────────
    //
    // ⚠️⚠️ **AUCUN ÉCRAN N'ÉTAIT EN CAUSE : LES QUINZE ÉTAIENT DÉJÀ DÉCIDÉS,
    // ET DÉJÀ EXPLIQUÉS EN COMMENTAIRE.** Ce sont ces commentaires qui
    // faisaient passer le contrôle — il lisait le fichier entier. Chaque motif
    // ci-dessous est REPRIS du commentaire qui le masquait, pas inventé après
    // coup.
    //
    // La leçon vaut d'être notée : une décision expliquée en commentaire mais
    // absente d'une liste d'exemptions **ressemble** à une décision consignée.
    // Elle ne l'est pas — elle est seulement invisible, et elle rend le
    // contrôle complaisant sur ce point précis.
    'bons-commande.html': {
      'Nouveau Fournisseur':
          'création à la volée non portée ici : elle se fait dans Fournisseurs',
      // « Un bon engage la ferme auprès d'un fournisseur : le serveur le sert
      // en LECTURE SEULE et ignore tout envoi le concernant. »
      'Bon de Commande': 'saisie non portée — bon servi en lecture seule',
      "Saisie d'un Bon de Commande":
          'saisie non portée — bon servi en lecture seule',
      // ⚠️ F0.67 : l'exemption globale « référentiel en lecture seule » est
      // retirée — créer un produit EXISTE désormais, au Catalogue. Ce
      // formulaire-ci n'offre pas la création à la volée.
      'Nouveau Produit':
          'création à la volée non portée ici : elle se fait au Catalogue Produits',
    },

    // ⚠️ SEUL CAS DES QUINZE OÙ LE POSTE S'ÉCARTE VOLONTAIREMENT DE LA
    // MAQUETTE. Celle-ci code six familles EN DUR et **oublie « Aliments » et
    // « Médicaments »**, qui existent au catalogue : neuf produits, dont toute
    // la provende, seraient restés hors de tout filtre. Le poste liste donc
    // les catégories RÉELLES, servies par le tirage.
    'catalogue-view.html': {
      'Cuniculture': 'filtre alimenté par les catégories réelles, non figé',
      'Aviculture': 'filtre alimenté par les catégories réelles, non figé',
      'Porciculture': 'filtre alimenté par les catégories réelles, non figé',
      'Maraîchage': 'filtre alimenté par les catégories réelles, non figé',
      'Transformation': 'filtre alimenté par les catégories réelles, non figé',
      'Équipements': 'filtre alimenté par les catégories réelles, non figé',
    },

    'enregistrer-achat.html': {
      'Nouveau Fournisseur':
          'création à la volée non portée ici : elle se fait dans Fournisseurs',
      // « Le poste n'a ni sélecteur de fichier ni canal d'envoi de pièce
      // jointe. Promettre le champ ferait croire la photo du reçu
      // enregistrée. »
      'Piece Justificative': 'ni sélecteur de fichier ni canal de pièce jointe',
      'Nouveau Produit':
          'création à la volée non portée ici : elle se fait au Catalogue Produits',
    },

    'gestion-stocks.html': {
      // « Il n'y a rien à recalculer au poste » : le PMP est tenu par le
      // serveur.
      'Recalculer PMP': 'le PMP est calculé par le serveur, pas au poste',
      'Modifier le Produit':
          'la modification se fait au Catalogue Produits, pas depuis ce hub',
    },

    'parametres.html': {
      // « NI MOT DE PASSE NI JETON NE DESCENDENT. »
      'Mot de Passe': 'aucun secret ne descend au poste',
    },

    'vms-calendrier.html': {
      // « Le calendrier du poste est CALCULÉ depuis le protocole
      // prophylactique servi par le serveur. »
      'Planifier': 'calendrier calculé depuis le protocole, non saisi',
    },

    'vms-registre.html': {
      'Imprimer': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
      // Widget de démonstration explicitement marqué comme tel dans la
      // maquette ; il crée un blocage sanitaire fictif.
      'Tester Rémanence': 'widget de démonstration de la maquette, exclu',
    },

    // Les deux seuls des quinze masqués par un IDENTIFIANT, non par un
    // commentaire.
    'roles-permissions.html': {
      'Exporter PDF': "écran qui n'appelle pas la chaîne d'édition (F0.52)",
      // ⚠️ La maquette n'accentue pas cet en-tête, l'écran écrit « Rôle ».
      // C'est l'arbitrage d'accentuation déjà ouvert au ticket F0.51 ; celle-ci
      // avait échappé, `RolesApplicatif` contenant « Role ».
      'Role':
          "en-tête non accentué dans la maquette, accentué à l'écran "
          '(arbitrage ouvert)',
      // ⚠️ Colonne du tableau « Sauvegardes de la Base de Données »
      // (Fichier · Date · Taille · Actions), non porté : ce sont des fichiers
      // `.sql` de plusieurs dizaines de Mo, produits et gardés sur le serveur.
      // Masquée jusqu'ici par `DateTime`.
      'Date': 'colonne du tableau des sauvegardes, non porté',
    },
  };

  /// Dette chiffrée : voir le test « ne monte pas ». Valeur cible après F0.81.
  const plafondManquesMasques = 268;

  for (final entree in portages.entries) {
    final page = entree.key;

    test('⚠️ le vocabulaire de $page ne dérive pas', () {
      // ⚠️⚠️ **LES LITTÉRAUX DE CHAÎNE, PAS LE FICHIER ENTIER** (ticket F0.53).
      // Comparer sur le fichier laissait un commentaire — ou un nom de classe —
      // tenir lieu de libellé affiché.
      final code = entree.value
          .map((c) => chainesDe(File(c).readAsStringSync()))
          .join('\n');

      final derives = <String>[];

      for (final libelle in inventaireMaquette[page]!) {
        if (exemptions.containsKey(libelle)) continue;
        if (exemptionsParPage[page]?.containsKey(libelle) ?? false) {
          continue;
        }
        // Les en-têtes de colonnes sont rendus en capitales par `uppercase`.
        if (code.contains(libelle) || code.contains(libelle.toUpperCase())) {
          continue;
        }
        derives.add(libelle);
      }

      expect(
        derives,
        isEmpty,
        reason:
            'Ces libellés existent dans $page et nulle part dans l\'écran. '
            'Soit ils ont dérivé et il faut les rétablir, soit leur absence '
            'est justifiée et elle doit rejoindre la liste des exemptions '
            'AVEC SA RAISON.',
      );
    });
  }

  /// ⚠️⚠️ **LE CONTRÔLE REPOSE DÉSORMAIS SUR CE LECTEUR, IL DOIT DONC ÊTRE
  /// CONTRÔLÉ LUI-MÊME.** Un lecteur trop permissif rendrait la suite entière
  /// complaisante — sans qu'aucun test ne rougisse. Un lecteur trop strict
  /// ferait échouer des écrans conformes, et l'on ajouterait des exemptions
  /// pour un défaut qui n'existe pas. Les deux dérives sont silencieuses.
  group('lecteur de littéraux', () {
    test('⚠️⚠️ un commentaire n est pas un libellé', () {
      expect(chainesDe('// Recalculer PMP'), isNot(contains('Recalculer PMP')));
      expect(
        chainesDe('/// Recalculer PMP'),
        isNot(contains('Recalculer PMP')),
      );
      expect(
        chainesDe('/* Recalculer PMP */'),
        isNot(contains('Recalculer PMP')),
      );
      // Le commentaire qui SUIT du code est écarté lui aussi.
      expect(
        chainesDe('var x = 1; // Recalculer PMP'),
        isNot(contains('Recalculer PMP')),
      );
    });

    test('⚠️⚠️ un identifiant n est pas un libellé', () {
      expect(chainesDe('class RolesApplicatif {}'), isNot(contains('Role')));
      expect(chainesDe('DateTime.now();'), isNot(contains('Date')));
    });

    test('un littéral est retenu, guillemets simples comme doubles', () {
      expect(chainesDe("Text('Solde Net')"), contains('Solde Net'));
      expect(chainesDe('Text("Solde Net")'), contains('Solde Net'));
    });

    /// ⚠️ Le code coupe ses longues phrases en littéraux successifs, que Dart
    /// concatène. Les séparer couperait un libellé en deux.
    test('⚠️ deux littéraux adjacents sont recollés', () {
      expect(
        chainesDe("const t = 'État des ' 'Recettes et Dépenses';"),
        contains('État des Recettes et Dépenses'),
      );
    });

    /// ⚠️ …mais deux littéraux SANS RAPPORT ne doivent pas en former un
    /// troisième : c'est ce qu'une espace en séparateur aurait produit.
    test('⚠️ deux littéraux sans rapport n en forment pas un troisième', () {
      expect(
        chainesDe("f('Total', 'Recettes')"),
        isNot(contains('Total Recettes')),
      );
    });

    test('une apostrophe échappée ne ferme pas la chaîne', () {
      expect(
        chainesDe(r"const t = 'Saisie d\'un Bon';"),
        contains("Saisie d'un Bon"),
      );
    });

    /// ⚠️ `//` DANS UNE CHAÎNE N'EST PAS UN COMMENTAIRE. Confondre les deux
    /// tronquerait toute adresse et tout chemin — et, au-delà, la fin de la
    /// ligne où ils apparaissent.
    test('⚠️ un // dans une chaîne n ouvre pas un commentaire', () {
      expect(
        chainesDe("const a = 'http://x'; const b = 'Solde Net';"),
        contains('Solde Net'),
      );
    });

    test('les chaînes brutes et triples sont lues', () {
      expect(
        chainesDe(r"const t = r'C:\Documents';"),
        contains(r'C:\Documents'),
      );
      expect(
        chainesDe("""const t = '''Rapport Élevage''';"""),
        contains('Rapport Élevage'),
      );
    });
  });

  /// ⚠️ Une exemption qui ne correspond plus à rien laisse croire qu'un écart
  /// est couvert alors qu'il a disparu — ou pire, qu'un mot est absent alors
  /// qu'il est revenu.
  test('⚠️ aucune exemption ne survit à son libellé', () {
    final tous = inventaireMaquette.values.expand((l) => l).toSet();
    final orphelines = exemptions.keys.where((e) => !tous.contains(e)).toList();

    expect(
      orphelines,
      isEmpty,
      reason: 'Exemptions sans libellé correspondant dans l\'inventaire.',
    );
  });

  /// ⚠️⚠️ **UNE EXEMPTION PAR PAGE SE PÉRIME DE DEUX FAÇONS**, et les deux
  /// laissent croire qu'un écart est couvert alors qu'il ne l'est plus : la
  /// page peut disparaître du portage, ou le libellé de son inventaire.
  test(
    '⚠️⚠️ aucune exemption par page ne survit à sa page ni à son libellé',
    () {
      final orphelines = <String>[];

      for (final page in exemptionsParPage.keys) {
        final inventaire = inventaireMaquette[page];
        if (inventaire == null) {
          orphelines.add('$page (page absente de l\'inventaire)');
          continue;
        }
        for (final libelle in exemptionsParPage[page]!.keys) {
          if (!inventaire.contains(libelle)) {
            orphelines.add('$page › $libelle');
          }
        }
      }

      expect(orphelines, isEmpty);
    },
  );

  /// ⚠️⚠️ **UNE EXEMPTION QUI NE SERT PLUS DOIT DISPARAÎTRE.** Si l'écran
  /// affiche enfin le libellé, l'exemption devient un mensonge tranquille :
  /// elle dit « nous avons décidé de ne pas le porter » d'un mot désormais
  /// porté. Sans ce contrôle, les deux motifs « chaîne d'édition non
  /// embarquée » du ticket F0.52 seraient restés faux sans que rien ne le dise.
  test(
    '⚠️⚠️ aucune exemption par page ne masque un libellé pourtant présent',
    () {
      final inutiles = <String>[];

      for (final page in exemptionsParPage.keys) {
        final fichiers = portages[page];
        if (fichiers == null) continue;

        final code = fichiers
            .map((c) => chainesDe(File(c).readAsStringSync()))
            .join('\n');

        for (final libelle in exemptionsParPage[page]!.keys) {
          if (code.contains(libelle) || code.contains(libelle.toUpperCase())) {
            inutiles.add('$page › $libelle');
          }
        }
      }

      expect(
        inutiles,
        isEmpty,
        reason:
            'Ces libellés sont bel et bien dans l\'écran : leur exemption ne '
            'décrit plus rien et doit être retirée.',
      );
    },
  );

  /// Pour une exemption GLOBALE : les pages portées dont l'inventaire contient le libellé,
  /// réparties entre celles où l'écran l'affiche (littéral Dart) et celles où il manque.
  ({List<String> presentes, List<String> absentes}) repartition(
    String libelle,
  ) {
    final presentes = <String>[];
    final absentes = <String>[];
    for (final page in portages.keys) {
      if (!inventaireMaquette[page]!.contains(libelle)) continue;
      final code = portages[page]!
          .map((c) => chainesDe(File(c).readAsStringSync()))
          .join('\n');
      if (code.contains(libelle) || code.contains(libelle.toUpperCase())) {
        presentes.add(page);
      } else {
        absentes.add(page);
      }
    }
    return (presentes: presentes, absentes: absentes);
  }

  /// ⚠️⚠️ **TICKET F0.81 — LE GARDE-FOU SYMÉTRIQUE DE CELUI DES EXEMPTIONS PAR PAGE.**
  /// Une exemption GLOBALE dont le libellé est affiché sur TOUTES les pages portées qui le
  /// contiennent ne masque plus rien : elle dit « nous avons décidé de ne pas le porter »
  /// d'un mot que l'écran porte. Mesuré à l'audit de F0.80 : 14 entrées dans ce cas,
  /// masquant 18 contrôles, sans qu'aucun test ne le dise.
  test('⚠️⚠️ aucune exemption GLOBALE n\'est entièrement périmée', () {
    final perimees = <String>[];
    for (final libelle in exemptions.keys) {
      final r = repartition(libelle);
      if (r.absentes.isEmpty && r.presentes.isNotEmpty) {
        perimees.add('$libelle (affiché sur ${r.presentes.join(', ')})');
      }
    }

    expect(
      perimees,
      isEmpty,
      reason:
          'Ces exemptions globales ne masquent plus aucun manque : à retirer.',
    );
  });

  /// ⚠️⚠️ **UNE EXEMPTION GLOBALE QUI MASQUE UN MANQUE RÉEL EST UNE EXEMPTION PAR PAGE MAL
  /// RANGÉE** (règle du projet : une exemption n'est globale que si elle vaut vraiment
  /// partout). Mesuré au ticket F0.81 : après migration de « Date * », « Confirmer
  /// l'archivage » et « Archiver », il reste [plafondManquesMasques] couples (page, libellé)
  /// où une exemption globale masque une absence réelle — dette CHIFFRÉE, à résorber.
  /// Ce plafond ne peut que BAISSER : le laisser monter, c'est laisser un trou grandir en
  /// silence ; le voir baisser sans le rabaisser ici, c'est perdre le gain.
  test(
    '⚠️⚠️ le nombre de manques réels masqués par une exemption GLOBALE ne monte pas',
    () {
      final parLibelle = <String, int>{};
      var total = 0;
      for (final libelle in exemptions.keys) {
        final n = repartition(libelle).absentes.length;
        if (n == 0) continue;
        parLibelle[libelle] = n;
        total += n;
      }

      final gros = parLibelle.entries.where((e) => e.value > 1).toList()
        ..sort((x, y) => y.value.compareTo(x.value));
      expect(
        total,
        plafondManquesMasques,
        reason:
            'Couples (page, libellé) masqués par une exemption globale : $total ; '
            'attendu exactement $plafondManquesMasques (mettre à jour le plafond SEULEMENT '
            'à la baisse). Plus lourds : ${gros.take(8).map((e) => "${e.key}=${e.value}").join(", ")}.',
      );
    },
  );
}
