// GÉNÉRÉ par `php outils/generer_aide_ecrans.php` depuis agrierp_laravel/lang/fr/aide_ecrans.php — NE PAS ÉDITER À LA MAIN.
//
// Ticket AIDE-1 — TEXTES D'AIDE DU POSTE : les mêmes, mot pour mot, que ceux du web (source unique côté web). Le panneau du
// bouton flottant d'aide (`core/widgets/aide_flottante.dart`) les lit ici. `test/aide_ecrans_parite_test.dart` exécute le
// vrai PHP du web et compare : un texte modifié d'un seul côté fait rougir ce test.
import '../auth/permissions_poste.dart';

/// L'aide courte d'un écran : son titre et 3 à 5 puces.
class AideEcran {
  const AideEcran({required this.titre, required this.puces});

  final String titre;
  final List<String> puces;
}

/// Une étape de la visite guidée.
class EtapeVisite {
  const EtapeVisite({required this.titre, required this.texte});

  final String titre;
  final String texte;
}

class AideEcrans {
  AideEcrans._();

  /// Écran du poste → chemin de la route web dont il reprend l'aide (`lang/fr/aide_ecrans.php`, clé `ecrans`).
  static const cheminsWeb = <EcranPoste, String>{
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
    EcranPoste.ficheSujet: '/sujets/{animal}',
    EcranPoste.registreReproducteurs: '/registre-reproducteurs',
    EcranPoste.caisse: '/ventes-devis',
  };

  /// Aide de chaque écran du poste.
  static const parEcran = <EcranPoste, AideEcran>{
    EcranPoste.tableauDeBord: AideEcran(
      titre: 'Tableau de Bord',
      puces: [
        'Résume la ferme du mois : chiffre d\'affaires, trésorerie, dépenses, résultat net, créances, dettes, stock critique et effectif des animaux.',
        '« Enregistrer une Vente » ouvre la caisse ; « Élevage » ouvre la gestion de l\'élevage.',
        'Sous les cartes : le graphique des 6 derniers mois, les alertes critiques, les transactions récentes et le top 5 des produits.',
        'La liste « Choisir un état / rapport » ouvre l\'état voulu dans Rapports & Exports.',
      ],
    ),
    EcranPoste.gestionElevage: AideEcran(
      titre: 'Gestion Élevage',
      puces: [
        'Point d\'entrée de l\'élevage : les cartes donnent l\'effectif total vivant, les bandes actives, les alertes de stock d\'aliment et le taux de mortalité du mois.',
        '« Registres par Espèce » ouvre la fiche journalière de chaque espèce, et « Bandes & Sujets » la liste des bandes.',
        '« Accès Rapides » mène au suivi de reproduction, aux soins et vaccins, au dashboard élevage et aux transferts entre bandes.',
      ],
    ),
    EcranPoste.dashboardElevage: AideEcran(
      titre: 'Dashboard Élevage',
      puces: [
        'Tableau de bord de l\'élevage en cinq onglets : synthèse globale, GMQ et croissance, rentabilité, analyse sanitaire et prévision de croissance.',
        'Les cartes de la synthèse donnent l\'effectif total vivant, l\'autonomie en aliment, le GMQ moyen et la mortalité cumulée sur 7 jours.',
        'Le GMQ (gain moyen quotidien) est le nombre de grammes pris par jour entre deux pesées.',
        'La synthèse affiche aussi les rappels de soins et vaccins à venir.',
      ],
    ),
    EcranPoste.suiviReproduction: AideEcran(
      titre: 'Suivi Reproduction',
      puces: [
        'Suit les saillies, les mises bas et les éclosions : reproductrices gestantes, échéances à venir et résultats du mois.',
        '« Déclarer une Saillie » ouvre le formulaire ; le tableau donne la date de saillie, le mâle et la mise bas attendue.',
        'Sur une ligne en attente, « + » et « − » enregistrent le résultat positif ou négatif de la palpation (retour de chaleur pour les porcs) ; « Saisir Mise Bas » puis « Clôturer (Sevrage) » terminent le cycle.',
        'Les cartes du haut signalent les palpations ou échéances dues et les alertes de réforme ou de pertes.',
      ],
    ),
    EcranPoste.soinsEtVaccins: AideEcran(
      titre: 'Soins et Vaccins',
      puces: [
        'Trois onglets : « Registre Vétérinaire » (soins donnés), « Calendrier Vétérinaire » (interventions planifiées) et « Suivi Sanitaire » (infirmerie).',
        '« Nouveau Soin » enregistre un soin avec sa date, sa bande, son produit et sa dose.',
        'Dans le calendrier, « Planifier une Intervention » prévoit un vaccin ou un traitement.',
        'À l\'infirmerie, on déclare une guérison (réintégration de l\'animal) ou un décès.',
      ],
    ),
    EcranPoste.transformation: AideEcran(
      titre: 'Bon d\'Abattage & Transformation',
      puces: [
        'Enregistre l\'abattage de sujets d\'une bande et le produit fini obtenu (par exemple de la viande).',
        'Choisissez la bande, le nombre de sujets à abattre, le produit fini et la quantité produite, puis « Valider la Transformation ».',
        'Le nombre de sujets retire l\'effectif de la bande et la quantité produite entre au stock du produit fini.',
        'L\'historique en bas liste les transformations passées avec leur statut.',
      ],
    ),
    EcranPoste.parametresElevage: AideEcran(
      titre: 'Paramètres Élevage',
      puces: [
        'Quatre référentiels de l\'élevage : fiche de rationnement, calendriers de prophylaxie, types de provende et numérotation des bandes et sujets.',
        'La fiche de rationnement donne la ration en g par tête et par jour selon l\'espèce et le stade.',
        'Le calendrier de prophylaxie liste, par espèce, les traitements prévus à chaque échéance.',
        'Ces réglages alimentent les fiches journalières : une modification s\'applique à toute la ferme.',
      ],
    ),
    EcranPoste.ficheElevage: AideEcran(
      titre: 'Fiches Lapins',
      puces: [
        'Fiche de suivi mensuel du cheptel de lapins : on saisit un jour à la fois, puis « Enregistrer ce Jour ».',
        'Choisissez la bande (s\'il y en a plusieurs) et la date ; l\'effectif final du jour est calculé automatiquement à partir de la veille.',
        'Saisissez les achats, naissances, morts, ventes et dons, la provende servie, le poids et les traitements.',
        'Les cartes du haut donnent l\'effectif vivant, les géniteurs, les naissances du mois et le taux de mortalité ; « Exporter PDF » imprime la fiche.',
      ],
    ),
    EcranPoste.fichePondeuses: AideEcran(
      titre: 'Fiches Pondeuses',
      puces: [
        'Saisie journalière de la ponte et du cheptel des pondeuses, un jour à la fois, puis « Enregistrer ce Jour ».',
        'Cheptel : effectif de début, morts et effectif de fin ; ponte : total d\'œufs récoltés (OR), œufs cassés (OF) et commercialisables (OR-OF), taux de ponte.',
        'Le stock d\'œufs et de plateaux de 30 est suivi jour après jour.',
        'Les cartes du haut donnent les pondeuses vivantes, le taux de ponte moyen, le stock de plateaux et le taux de mortalité.',
      ],
    ),
    EcranPoste.ficheReproducteurs: AideEcran(
      titre: 'Fiches Volailles Reproducteurs',
      puces: [
        'Saisie journalière du couvoir et du suivi des volailles de chair : reproducteurs, poussins et Goliath.',
        'Couvoir : œufs couvés et poussins nés, d\'où le taux d\'éclosion ; cheptel : morts, effectif final, poids.',
        'On saisit un jour à la fois, puis « Enregistrer ce Jour » ; « Exporter PDF » imprime la fiche.',
        'Les cartes du haut donnent l\'effectif vivant, le taux d\'éclosion, les poussins nés et le taux de mortalité.',
      ],
    ),
    EcranPoste.fichePorcs: AideEcran(
      titre: 'Fiches Porcs',
      puces: [
        'Fiche de suivi du cheptel porcin par stade physiologique : on saisit un jour à la fois, puis « Enregistrer ce Jour ».',
        'Les effectifs finaux du jour sont calculés automatiquement à partir de la veille, des naissances, des morts, des ventes et des dons.',
        'Saisissez aussi la provende servie, le poids et les traitements de prophylaxie.',
        'Les cartes du haut donnent l\'effectif vivant, les truies gestantes et verrats, les porcelets sous mère et le taux de mortalité.',
      ],
    ),
    EcranPoste.ficheEscargots: AideEcran(
      titre: 'Fiches Escargots',
      puces: [
        'Fiche de suivi de l\'élevage d\'escargots (héliciculture) : naissains, engraissement et bordés.',
        'On saisit un jour à la fois (achats, naissains nés, morts, ventes, dons, poids), puis « Enregistrer ce Jour ».',
        'Les cartes du haut donnent l\'effectif vivant, les naissains nés du mois, le taux d\'éclosion et le taux de mortalité.',
        'Ce module est désactivé par défaut : un administrateur l\'active dans Paramètres, onglet Modules Actifs.',
      ],
    ),
    EcranPoste.transfertsBandes: AideEcran(
      titre: 'Transferts entre Bandes',
      puces: [
        'Déplace des sujets d\'une bande source vers une bande cible : « Nouveau Transfert ».',
        'Le tableau garde la date, les deux bandes, le nombre de sujets, la catégorie, le type, le motif et le statut de chaque transfert.',
        'Les cartes du haut comptent les transferts du mois, les sujets transférés et les bandes à vérifier.',
        'Les bandes peut-être issues d\'une autre, sans origine renseignée, sont listées ; « Rattacher à sa bande d\'origine » les relie.',
      ],
    ),
    EcranPoste.gestionBandes: AideEcran(
      titre: 'Bandes & Sujets',
      puces: [
        'Liste les bandes d\'élevage avec leur espèce, leur stade, leur effectif initial et actuel, leur mortalité et leur statut.',
        '« Nouvelle Bande » crée une bande ; le crayon la modifie, la corbeille l\'archive et l\'icône de restauration la ramène.',
        'Les cartes du haut comptent les bandes actives, celles en reproduction, l\'effectif total vivant et les alertes sanitaires.',
        'L\'effectif actuel suit la dernière fiche journalière de la bande.',
      ],
    ),
    EcranPoste.enregistrerSujets: AideEcran(
      titre: 'Enregistrer des Sujets',
      puces: [
        'Journal des entrées de sujets dans une bande : naissance, achat ou don.',
        '« Nouveau Sujet » enregistre une entrée avec sa date, sa bande, son origine et sa quantité.',
        'Les cartes du haut comptent les naissances et les acquisitions du mois et l\'effectif total.',
        'Le crayon corrige une entrée ; l\'icône d\'archivage la retire.',
      ],
    ),
    EcranPoste.ventesEtDevis: AideEcran(
      titre: 'Ventes & Devis',
      puces: [
        'Quatre onglets : « Enregistrer Vente » (la caisse), « Devis Prestations », « Historique des Ventes » et « Retours et Avoirs ».',
        'À la caisse, ajoutez les produits au panier, choisissez le client puis « Valider la Vente » ; le client peut être créé sur place.',
        'Un devis passe de brouillon à envoyé, puis accepté ou refusé, et peut être converti en facture.',
        'Dans l\'historique, on consulte une vente ou on l\'annule ; un retour crée un avoir.',
      ],
    ),
    EcranPoste.clientsEtCreances: AideEcran(
      titre: 'Créances Clients',
      puces: [
        'Quatre onglets : « Liste des Clients », « Suivi des Dettes », « Relances Clients » et « Historique Avances ».',
        'Le suivi des dettes liste les factures impayées avec leur échéance et le solde restant ; l\'icône carte enregistre un règlement.',
        'Pour une relance, choisissez le niveau (rappel amiable, rappel ferme, mise en demeure) puis le modèle de message.',
        'Une avance est un acompte reçu d\'un client ; « Imputer » l\'applique à une dette.',
      ],
    ),
    EcranPoste.achatsEtCommandes: AideEcran(
      titre: 'Achats & Commandes',
      puces: [
        'Trois onglets : « Enregistrer un Achat », « Liste d\'Achats » et « Bons de Commande ».',
        'Pour un achat, choisissez le fournisseur, ajoutez les lignes au bon d\'achat, puis « Enregistrer l\'Achat » ; fournisseur et produit peuvent être créés sur place.',
        'La liste d\'achats montre le montant payé, le total et la dette ; elle permet un retour fournisseur et un remboursement.',
        'Un bon de commande émis se réceptionne avec « Valider la réception ».',
      ],
    ),
    EcranPoste.fournisseurs: AideEcran(
      titre: 'Fournisseurs',
      puces: [
        'Trois onglets : « Ajouter Fournisseur », « Fiches Fournisseurs » et « Dettes Fournisseurs ».',
        '« Nouveau Fournisseur » crée une fiche ; le crayon la modifie ; l\'icône d\'archivage la retire.',
        'Les fiches donnent le total des achats de l\'année et la dernière commande ; l\'œil ouvre le profil du fournisseur.',
        'Les dettes listent le montant dû, l\'échéance et le statut ; « Enregistrer un Règlement » paie une dette.',
      ],
    ),
    EcranPoste.saisieDepenses: AideEcran(
      titre: 'Saisie des Dépenses',
      puces: [
        'Enregistre les dépenses de la ferme : « Nouvelle Dépense » ouvre le formulaire.',
        'Une dépense peut avoir plusieurs lignes, chacune avec son compte de charge et son montant ; le total est la somme des lignes.',
        'Les cartes du haut donnent les dépenses du mois, les charges fixes et les charges variables.',
        'Une dépense déjà comptabilisée ne se corrige pas : on l\'archive, puis on en saisit une nouvelle.',
      ],
    ),
    EcranPoste.gestionStocks: AideEcran(
      titre: 'Gestion des Stocks',
      puces: [
        'Trois onglets : « Tableau & Valorisation » (stock, prix moyen et valeur de chaque produit), « Journal des Mouvements » et « Ajustement / Correction ».',
        'Les cartes du haut donnent la valeur du stock, les alertes de seuil, la rotation et les écarts d\'inventaire.',
        '« Ajouter Stock » enregistre une entrée de stock ; « Ajustement / Correction » corrige un stock après un comptage.',
        'Chaque mouvement garde sa date, sa référence, son motif et sa quantité dans le journal.',
      ],
    ),
    EcranPoste.catalogueProduits: AideEcran(
      titre: 'Catalogue Produits',
      puces: [
        'Liste tous les produits de la ferme (SKU, désignation, catégorie, stock, tarif), en cartes ou en tableau.',
        'Filtrez par catégorie avec les boutons du haut ; la recherche trouve un produit par son nom.',
        '« Nouveau Produit » ouvre la fiche de création ; le crayon d\'une ligne modifie le produit ; l\'icône d\'archivage le retire de la liste.',
        'Les quantités en stock se règlent dans Gestion Stocks ; les seuils d\'alerte dans Seuils d\'Alerte.',
      ],
    ),
    EcranPoste.facturation: AideEcran(
      titre: 'Facturation',
      puces: [
        'Registre des factures de vente : numéro, client, date, montant TTC et statut.',
        'L\'icône d\'impression produit la facture en PDF.',
        'Quand le module MeCeF est activé, la page ajoute le statut de transmission, la facture normalisée et la retransmission.',
        'Les cartes du haut comptent les factures du mois et le montant facturé.',
      ],
    ),
    EcranPoste.personnelEtStages: AideEcran(
      titre: 'Personnel & Stages',
      puces: [
        'Cinq onglets : « Registre Employés », « Registre Stagiaires », « Feuille de Pointage », « Gestion de la Paie » et « Attestations ».',
        'Les registres gardent les fiches : « Nouvel Employé » ou « Nouveau Stagiaire » en crée une, le crayon la modifie.',
        'La feuille de pointage enregistre l\'arrivée et le départ de chaque employé, jour par jour.',
        'La paie calcule le net à payer de chaque bulletin ; « Valider le règlement » enregistre le paiement.',
      ],
    ),
    EcranPoste.administrationEtDocument: AideEcran(
      titre: 'Administration & Documents',
      puces: [
        'Trois onglets : « Gestion des Courriers », « Archivage des Documents » et « Documents Administratifs ».',
        'Les courriers reçus et envoyés se notent avec une référence, un objet, la partie concernée et une date.',
        'L\'archivage garde les documents avec leur date d\'expiration ; une carte compte ceux qui expirent sous 30 jours.',
        'Dans chaque onglet, le bouton principal en haut crée une entrée.',
      ],
    ),
    EcranPoste.comptabilite: AideEcran(
      titre: 'Comptabilité',
      puces: [
        'Point d\'entrée de la comptabilité : total de l\'actif, recettes du mois, marge nette analytique et trésorerie disponible.',
        'Les cartes de navigation ouvrent chaque état : plan comptable, journal, grand livre, balance, balance âgée, bilan, états financiers, TVA, rapprochement bancaire, immobilisations, analytique et clôture.',
        'Toutes les écritures viennent des ventes, achats, dépenses et paies ; les écritures manuelles se saisissent dans le Journal.',
      ],
    ),
    EcranPoste.parametresGeneraux: AideEcran(
      titre: 'Paramètres',
      puces: [
        'Onze onglets : rôles et permissions, données de l\'entreprise, e-mail (SMTP), modules actifs, utilisateurs, postes et appairage, modes de paiement, audit, corbeille, réinitialisation et sauvegardes.',
        '« Modules Actifs » allume ou éteint les espèces d\'élevage et l\'assistant de démarrage.',
        '« Gestion Utilisateurs » crée les comptes et attribue un rôle à chacun.',
        '« Corbeille » restaure ce qui a été archivé ; « Audit Logs » garde la trace des actions.',
      ],
    ),
    EcranPoste.rapportsEtExports: AideEcran(
      titre: 'Rapports & Exports',
      puces: [
        'Six états en onglets : recettes et dépenses, trésorerie, créances clients, dettes fournisseurs, élevage et stocks.',
        'Choisissez d\'abord la période (de, au) : tous les onglets la suivent.',
        '« Exporter PDF » et « Exporter Excel » sortent l\'onglet affiché, pour les comptes qui ont ce droit.',
      ],
    ),
    EcranPoste.monProfil: AideEcran(
      titre: 'Mon Profil',
      puces: [
        'Montre votre identité (nom, e-mail, rôle) et les informations de votre session : dernière connexion, adresse IP, statut du compte.',
        '« Modifier le Mot de Passe » : saisissez l\'ancien, puis le nouveau deux fois.',
        '« Verrouillage automatique » règle le délai d\'inactivité avant que l\'application se verrouille.',
        'Le journal d\'audit en bas liste vos 10 dernières actions.',
      ],
    ),
    EcranPoste.notifications: AideEcran(
      titre: 'Centre de Notifications',
      puces: [
        'Rassemble les alertes de la ferme avec leur date, leur catégorie, leur gravité et leur statut.',
        'Les cartes du haut comptent les notifications non lues, les critiques et le total sur 30 jours.',
        'Cherchez un message, filtrez par catégorie (Élevage, Stocks, Finance, RH) ou par statut (lue, non lue).',
        'Dans la colonne Actions : marquer comme lue, résoudre ou supprimer une notification.',
      ],
    ),
    EcranPoste.aideEtAPropos: AideEcran(
      titre: 'Aide & À Propos',
      puces: [
        'Présente les modules du logiciel et répond aux questions fréquentes.',
        'Dans la foire aux questions, cliquez sur une question pour déplier sa réponse.',
        'Un problème précis ? « Contactez l\'Éditeur » est dans le menu du compte, en haut à droite.',
      ],
    ),
    EcranPoste.contactEditeur: AideEcran(
      titre: 'Contactez l\'Éditeur',
      puces: [
        'Deux formulaires : « Envoyer un Message » pour une question, « Signaler un Bug » pour un défaut constaté.',
        'Décrivez ce que vous faisiez et ce que vous attendiez : l\'éditeur pourra reproduire le cas.',
        'Les coordonnées de l\'éditeur figurent sur la même page.',
      ],
    ),
    EcranPoste.ficheSujet: AideEcran(
      titre: 'Fiche Sujet',
      puces: [
        'Fiche d\'un reproducteur : identification et QR code du sujet.',
        'Plus bas, son historique : soins reçus, saillies et mises bas, et ses mouvements.',
        '« Exporter PDF » imprime la fiche.',
      ],
    ),
    EcranPoste.registreReproducteurs: AideEcran(
      titre: 'Registre des Reproducteurs',
      puces: [
        'Registre nominatif des reproducteurs : identifiant, espèce, sexe, race, bande, cage et statut.',
        '« Enregistrer un Reproducteur » ajoute un sujet ; le crayon le modifie ; l\'icône de sortie enregistre son départ.',
        'L\'icône « Consulter la fiche » ouvre la fiche détaillée du sujet.',
        'Les cartes du haut comptent les reproducteurs enregistrés, présents, femelles et mâles.',
      ],
    ),
    EcranPoste.caisse: AideEcran(
      titre: 'Ventes & Devis',
      puces: [
        'Quatre onglets : « Enregistrer Vente » (la caisse), « Devis Prestations », « Historique des Ventes » et « Retours et Avoirs ».',
        'À la caisse, ajoutez les produits au panier, choisissez le client puis « Valider la Vente » ; le client peut être créé sur place.',
        'Un devis passe de brouillon à envoyé, puis accepté ou refusé, et peut être converti en facture.',
        'Dans l\'historique, on consulte une vente ou on l\'annule ; un retour crée un avoir.',
      ],
    ),
    EcranPoste.synchronisation: AideEcran(
      titre: 'Synchronisation',
      puces: [
        'Ce poste travaille hors ligne : les saisies restent ici jusqu\'à leur envoi.',
        'Le compteur « En attente d\'envoi » dit combien de saisies attendent ; « Synchroniser » lance l\'envoi et la réception.',
        'Les refus du serveur sont listés avec leur motif ; « Remettre en file » renvoie les saisies une fois la cause corrigée.',
        '« Contrôle de cohérence » compare ce poste au serveur (il faut être en ligne).',
      ],
    ),
    EcranPoste.parametres: AideEcran(
      titre: 'Paramètres du poste',
      puces: [
        'Ouvre Paramètres sur l\'onglet « Appairage » : adresse du serveur, identifiant de ce poste et état de son jeton.',
        '« Tester la connexion » vérifie que le serveur répond ; « Réappairer » refait l\'appairage du poste.',
        'Une nouvelle adresse de serveur n\'est effective qu\'au redémarrage du poste.',
        'Réservé à l\'administrateur.',
      ],
    ),
  };

  /// Écrans du poste sans route web (clé `poste_seul`).
  static const posteSeul = <EcranPoste>{
    EcranPoste.synchronisation,
    EcranPoste.parametres,
  };

  /// Aide d'un écran absent de [parEcran] : jamais de panneau vide.
  static const parDefaut = AideEcran(
    titre: 'Aide',
    puces: [
      'Cet écran fait partie de LogiAgriERP : le titre en haut de la page vous dit où vous êtes.',
      'Les cartes du haut donnent les chiffres clés ; les tableaux et les onglets détaillent le reste.',
      'Pour changer d\'écran, utilisez le menu de navigation ou la recherche en haut de la page.',
    ],
  );

  static AideEcran pour(EcranPoste ecran) => parEcran[ecran] ?? parDefaut;

  /// Libellés du panneau (clé `panneau`).
  static const panneau = <String, String>{
    'bouton': 'Aide et visite guidée',
    'titre': 'Aide et visite guidée',
    'ecran': 'Aide de cet écran',
    'relancer': 'Relancer l\'assistant de démarrage',
    'relancer_detail': 'Revoir les étapes de mise en route de la ferme.',
    'visite': 'Visite guidée',
    'visite_detail': 'Découvrir l\'application en 4 étapes.',
    'fermer': 'Fermer',
  };

  /// Libellés de la visite guidée (clé `visite`, hors étapes).
  static const libellesVisite = <String, String>{
    'etape_sur': 'Étape :numero sur :total',
    'passer': 'Passer',
    'precedent': 'Précédent',
    'suivant': 'Suivant',
    'terminer': 'Terminer',
    'fin_titre': 'Visite terminée',
    'fin_texte':
        'Vous pouvez la reprendre à tout moment depuis le bouton d\'aide, en bas à droite.',
    'fin_fermer': 'Fermer',
  };

  /// Les 4 étapes de la visite guidée.
  static const etapesVisite = <EtapeVisite>[
    EtapeVisite(
      titre: 'Bienvenue dans LogiAgriERP',
      texte:
          'Ce bouton d\'aide vous suit sur tous les écrans : il explique l\'écran affiché, relance l\'assistant de démarrage et rouvre cette visite. Quatre étapes, et « Passer » pour la quitter à tout moment.',
    ),
    EtapeVisite(
      titre: 'La barre du haut',
      texte:
          'Elle reste en haut de chaque écran : recherche, exercice affiché, notifications et menu du compte (Mon Profil, Verrouiller, Déconnexion).',
    ),
    EtapeVisite(
      titre: 'Lire vos données',
      texte:
          'Au centre, les cartes du haut résument les chiffres clés, les tableaux détaillent les lignes et les onglets changent de sujet. L\'aide de cet écran explique ce qu\'il faut y lire.',
    ),
    EtapeVisite(
      titre: 'Le menu de navigation',
      texte:
          'Le menu regroupe les écrans par rubrique, selon votre rôle. « Accès rapide » ouvre les fiches d\'élevage et les écrans courants ; le bouton d\'aide reste là pour toute question.',
    ),
  ];
}
