<?php

/**
 * Ticket AIDE-1 — SOURCE UNIQUE DES TEXTES D'AIDE (web ET poste).
 *
 * Le bouton flottant d'aide (module « Assistant de démarrage » allumé) ouvre un panneau qui lit CE fichier :
 *  - `ecrans`     : l'aide courte de chaque écran, clé = CHEMIN DE LA ROUTE tel que Laravel le déclare
 *                   (`/dashboard`, `/clients/{customer}/profil`…), valeurs `titre` + `puces` (3 à 5) ;
 *  - `poste_seul` : écrans du poste sans route web (Synchronisation, Paramètres du poste) — lus par le poste seul ;
 *  - `defaut`     : l'aide d'une route absente de `ecrans` (jamais de panneau vide) ;
 *  - `visite`     : la visite guidée, 4 étapes (titre + texte) et ses libellés ;
 *  - `panneau`    : les libellés du panneau.
 *
 * ⚠️ Le poste reprend ces textes MOT POUR MOT (`agrierp_flutter/lib/core/aide/aide_ecrans.dart`, produit par
 * `php agrierp_flutter/outils/generer_aide_ecrans.php`). `agrierp_flutter/test/aide_ecrans_parite_test.dart`
 * exécute ce fichier et compare : modifier un texte ici sans régénérer le poste fait rougir ce test.
 *
 * Règles de rédaction : français, phrases courtes, rien qui ne soit visible à l'écran (n'inventer aucune fonction) ;
 * en cas de doute sur une règle métier, rester générique. Pas de `$` dans un texte (chaînes entre guillemets).
 */
return [
    'panneau' => [
        'bouton' => 'Aide et visite guidée',
        'titre' => 'Aide et visite guidée',
        'ecran' => 'Aide de cet écran',
        'relancer' => "Relancer l'assistant de démarrage",
        'relancer_detail' => 'Revoir les étapes de mise en route de la ferme.',
        'visite' => 'Visite guidée',
        'visite_detail' => 'Découvrir l\'application en 4 étapes.',
        'fermer' => 'Fermer',
    ],

    'visite' => [
        'etape_sur' => 'Étape :numero sur :total',
        'passer' => 'Passer',
        'precedent' => 'Précédent',
        'suivant' => 'Suivant',
        'terminer' => 'Terminer',
        'fin_titre' => 'Visite terminée',
        'fin_texte' => "Vous pouvez la reprendre à tout moment depuis le bouton d'aide, en bas à droite.",
        'fin_fermer' => 'Fermer',
        'etapes' => [
            [
                'titre' => 'Bienvenue dans LogiAgriERP',
                'texte' => "Ce bouton d'aide vous suit sur tous les écrans : il explique l'écran affiché, relance l'assistant de démarrage et rouvre cette visite. Quatre étapes, et « Passer » pour la quitter à tout moment.",
            ],
            [
                'titre' => 'La barre du haut',
                'texte' => "Elle reste en haut de chaque écran : recherche, exercice affiché, notifications et menu du compte (Mon Profil, Verrouiller, Déconnexion).",
            ],
            [
                'titre' => 'Lire vos données',
                'texte' => "Au centre, les cartes du haut résument les chiffres clés, les tableaux détaillent les lignes et les onglets changent de sujet. L'aide de cet écran explique ce qu'il faut y lire.",
            ],
            [
                'titre' => 'Le menu de navigation',
                'texte' => "Le menu regroupe les écrans par rubrique, selon votre rôle. « Accès rapide » ouvre les fiches d'élevage et les écrans courants ; le bouton d'aide reste là pour toute question.",
            ],
        ],
    ],

    'defaut' => [
        'titre' => 'Aide',
        'puces' => [
            "Cet écran fait partie de LogiAgriERP : le titre en haut de la page vous dit où vous êtes.",
            "Les cartes du haut donnent les chiffres clés ; les tableaux et les onglets détaillent le reste.",
            "Pour changer d'écran, utilisez le menu de navigation ou la recherche en haut de la page.",
        ],
    ],

    'ecrans' => [
        '/dashboard' => [
            'titre' => 'Tableau de Bord',
            'puces' => [
                "Résume la ferme du mois : chiffre d'affaires, trésorerie, dépenses, résultat net, créances, dettes, stock critique et effectif des animaux.",
                "« Enregistrer une Vente » ouvre la caisse ; « Élevage » ouvre la gestion de l'élevage.",
                "Sous les cartes : le graphique des 6 derniers mois, les alertes critiques, les transactions récentes et le top 5 des produits.",
                "La liste « Choisir un état / rapport » ouvre l'état voulu dans Rapports & Exports.",
            ],
        ],
        '/mon-profil' => [
            'titre' => 'Mon Profil',
            'puces' => [
                "Montre votre identité (nom, e-mail, rôle) et les informations de votre session : dernière connexion, adresse IP, statut du compte.",
                "« Modifier le Mot de Passe » : saisissez l'ancien, puis le nouveau deux fois.",
                "« Verrouillage automatique » règle le délai d'inactivité avant que l'application se verrouille.",
                "Le journal d'audit en bas liste vos 10 dernières actions.",
            ],
        ],
        '/aide-a-propos' => [
            'titre' => 'Aide & À Propos',
            'puces' => [
                "Présente les modules du logiciel et répond aux questions fréquentes.",
                "Dans la foire aux questions, cliquez sur une question pour déplier sa réponse.",
                "Un problème précis ? « Contactez l'Éditeur » est dans le menu du compte, en haut à droite.",
            ],
        ],
        '/contact-editeur' => [
            'titre' => "Contactez l'Éditeur",
            'puces' => [
                "Deux formulaires : « Envoyer un Message » pour une question, « Signaler un Bug » pour un défaut constaté.",
                "Décrivez ce que vous faisiez et ce que vous attendiez : l'éditeur pourra reproduire le cas.",
                "Les coordonnées de l'éditeur figurent sur la même page.",
            ],
        ],
        '/notifications' => [
            'titre' => 'Centre de Notifications',
            'puces' => [
                "Rassemble les alertes de la ferme avec leur date, leur catégorie, leur gravité et leur statut.",
                "Les cartes du haut comptent les notifications non lues, les critiques et le total sur 30 jours.",
                "Cherchez un message, filtrez par catégorie (Élevage, Stocks, Finance, RH) ou par statut (lue, non lue).",
                "Dans la colonne Actions : marquer comme lue, résoudre ou supprimer une notification.",
            ],
        ],

        '/catalogue-produits' => [
            'titre' => 'Catalogue Produits',
            'puces' => [
                "Liste tous les produits de la ferme (SKU, désignation, catégorie, stock, tarif), en cartes ou en tableau.",
                "Filtrez par catégorie avec les boutons du haut ; la recherche trouve un produit par son nom.",
                "« Nouveau Produit » ouvre la fiche de création ; le crayon d'une ligne modifie le produit ; l'icône d'archivage le retire de la liste.",
                "Les quantités en stock se règlent dans Gestion Stocks ; les seuils d'alerte dans Seuils d'Alerte.",
            ],
        ],
        '/produits/ajouter' => [
            'titre' => 'Ajouter un produit',
            'puces' => [
                "Renseignez la fiche du nouveau produit : nom, catégorie, filière d'élevage, unité de comptage, mode et fourchette de prix, stock initial, seuil d'alerte et TVA.",
                "Les champs marqués d'un astérisque sont obligatoires.",
                "Enregistrez pour retrouver le produit dans le Catalogue Produits et dans Gestion Stocks.",
            ],
        ],
        '/produits/{product}/modifier' => [
            'titre' => 'Modifier un produit',
            'puces' => [
                "Corrigez la fiche du produit : nom, catégorie, unité de comptage, prix, seuil d'alerte ou TVA.",
                "Les champs marqués d'un astérisque sont obligatoires.",
                "Le stock ne se corrige pas ici : utilisez « Ajustement / Correction » dans Gestion Stocks.",
            ],
        ],
        '/gestion-stocks' => [
            'titre' => 'Gestion des Stocks',
            'puces' => [
                "Trois onglets : « Tableau & Valorisation » (stock, prix moyen et valeur de chaque produit), « Journal des Mouvements » et « Ajustement / Correction ».",
                "Les cartes du haut donnent la valeur du stock, les alertes de seuil, la rotation et les écarts d'inventaire.",
                "« Ajouter Stock » enregistre une entrée de stock ; « Ajustement / Correction » corrige un stock après un comptage.",
                "Chaque mouvement garde sa date, sa référence, son motif et sa quantité dans le journal.",
            ],
        ],
        '/seuils-alerte' => [
            'titre' => "Seuils d'Alerte",
            'puces' => [
                "Fixe, produit par produit, le niveau de stock sous lequel une alerte est levée.",
                "Les cartes du haut comptent les produits sous seuil et les seuils configurés.",
                "La colonne Statut compare le stock actuel au seuil configuré ; l'icône crayon modifie un seuil.",
                "Le crayon ouvre « Configurer un Seuil » pour fixer ou modifier le seuil du produit.",
            ],
        ],

        '/parametres-elevage' => [
            'titre' => 'Paramètres Élevage',
            'puces' => [
                "Quatre référentiels de l'élevage : fiche de rationnement, calendriers de prophylaxie, types de provende et numérotation des bandes et sujets.",
                "La fiche de rationnement donne la ration en g par tête et par jour selon l'espèce et le stade.",
                "Le calendrier de prophylaxie liste, par espèce, les traitements prévus à chaque échéance.",
                "Ces réglages alimentent les fiches journalières : une modification s'applique à toute la ferme.",
            ],
        ],
        '/gestion-elevage' => [
            'titre' => 'Gestion Élevage',
            'puces' => [
                "Point d'entrée de l'élevage : les cartes donnent l'effectif total vivant, les bandes actives, les alertes de stock d'aliment et le taux de mortalité du mois.",
                "« Registres par Espèce » ouvre la fiche journalière de chaque espèce, et « Bandes & Sujets » la liste des bandes.",
                "« Accès Rapides » mène au suivi de reproduction, aux soins et vaccins, au dashboard élevage et aux transferts entre bandes.",
            ],
        ],
        '/gestion-bandes' => [
            'titre' => 'Bandes & Sujets',
            'puces' => [
                "Liste les bandes d'élevage avec leur espèce, leur stade, leur effectif initial et actuel, leur mortalité et leur statut.",
                "« Nouvelle Bande » crée une bande ; le crayon la modifie, la corbeille l'archive et l'icône de restauration la ramène.",
                "Les cartes du haut comptent les bandes actives, celles en reproduction, l'effectif total vivant et les alertes sanitaires.",
                "L'effectif actuel suit la dernière fiche journalière de la bande.",
            ],
        ],
        '/enregistrer-sujets' => [
            'titre' => 'Enregistrer des Sujets',
            'puces' => [
                "Journal des entrées de sujets dans une bande : naissance, achat ou don.",
                "« Nouveau Sujet » enregistre une entrée avec sa date, sa bande, son origine et sa quantité.",
                "Les cartes du haut comptent les naissances et les acquisitions du mois et l'effectif total.",
                "Le crayon corrige une entrée ; l'icône d'archivage la retire.",
            ],
        ],
        '/fiche-lapins' => [
            'titre' => 'Fiches Lapins',
            'puces' => [
                "Fiche de suivi mensuel du cheptel de lapins : on saisit un jour à la fois, puis « Enregistrer ce Jour ».",
                "Choisissez la bande (s'il y en a plusieurs) et la date ; l'effectif final du jour est calculé automatiquement à partir de la veille.",
                "Saisissez les achats, naissances, morts, ventes et dons, la provende servie, le poids et les traitements.",
                "Les cartes du haut donnent l'effectif vivant, les géniteurs, les naissances du mois et le taux de mortalité ; « Exporter PDF » imprime la fiche.",
            ],
        ],
        '/fiche-volailles-pondeuses' => [
            'titre' => 'Fiches Pondeuses',
            'puces' => [
                "Saisie journalière de la ponte et du cheptel des pondeuses, un jour à la fois, puis « Enregistrer ce Jour ».",
                "Cheptel : effectif de début, morts et effectif de fin ; ponte : total d'œufs récoltés (OR), œufs cassés (OF) et commercialisables (OR-OF), taux de ponte.",
                "Le stock d'œufs et de plateaux de 30 est suivi jour après jour.",
                "Les cartes du haut donnent les pondeuses vivantes, le taux de ponte moyen, le stock de plateaux et le taux de mortalité.",
            ],
        ],
        '/fiche-volailles-reproducteurs' => [
            'titre' => 'Fiches Volailles Reproducteurs',
            'puces' => [
                "Saisie journalière du couvoir et du suivi des volailles de chair : reproducteurs, poussins et Goliath.",
                "Couvoir : œufs couvés et poussins nés, d'où le taux d'éclosion ; cheptel : morts, effectif final, poids.",
                "On saisit un jour à la fois, puis « Enregistrer ce Jour » ; « Exporter PDF » imprime la fiche.",
                "Les cartes du haut donnent l'effectif vivant, le taux d'éclosion, les poussins nés et le taux de mortalité.",
            ],
        ],
        '/fiche-porcs' => [
            'titre' => 'Fiches Porcs',
            'puces' => [
                "Fiche de suivi du cheptel porcin par stade physiologique : on saisit un jour à la fois, puis « Enregistrer ce Jour ».",
                "Les effectifs finaux du jour sont calculés automatiquement à partir de la veille, des naissances, des morts, des ventes et des dons.",
                "Saisissez aussi la provende servie, le poids et les traitements de prophylaxie.",
                "Les cartes du haut donnent l'effectif vivant, les truies gestantes et verrats, les porcelets sous mère et le taux de mortalité.",
            ],
        ],
        '/fiche-escargots' => [
            'titre' => 'Fiches Escargots',
            'puces' => [
                "Fiche de suivi de l'élevage d'escargots (héliciculture) : naissains, engraissement et bordés.",
                "On saisit un jour à la fois (achats, naissains nés, morts, ventes, dons, poids), puis « Enregistrer ce Jour ».",
                "Les cartes du haut donnent l'effectif vivant, les naissains nés du mois, le taux d'éclosion et le taux de mortalité.",
                "Ce module est désactivé par défaut : un administrateur l'active dans Paramètres, onglet Modules Actifs.",
            ],
        ],
        '/suivi-reproduction' => [
            'titre' => 'Suivi Reproduction',
            'puces' => [
                "Suit les saillies, les mises bas et les éclosions : reproductrices gestantes, échéances à venir et résultats du mois.",
                "« Déclarer une Saillie » ouvre le formulaire ; le tableau donne la date de saillie, le mâle et la mise bas attendue.",
                "Sur une ligne en attente, « + » et « − » enregistrent le résultat positif ou négatif de la palpation (retour de chaleur pour les porcs) ; « Saisir Mise Bas » puis « Clôturer (Sevrage) » terminent le cycle.",
                "Les cartes du haut signalent les palpations ou échéances dues et les alertes de réforme ou de pertes.",
            ],
        ],
        '/soins-vaccins-hub' => [
            'titre' => 'Soins et Vaccins',
            'puces' => [
                "Trois onglets : « Registre Vétérinaire » (soins donnés), « Calendrier Vétérinaire » (interventions planifiées) et « Suivi Sanitaire » (infirmerie).",
                "« Nouveau Soin » enregistre un soin avec sa date, sa bande, son produit et sa dose.",
                "Dans le calendrier, « Planifier une Intervention » prévoit un vaccin ou un traitement.",
                "À l'infirmerie, on déclare une guérison (réintégration de l'animal) ou un décès.",
            ],
        ],
        '/transformation' => [
            'titre' => "Bon d'Abattage & Transformation",
            'puces' => [
                "Enregistre l'abattage de sujets d'une bande et le produit fini obtenu (par exemple de la viande).",
                "Choisissez la bande, le nombre de sujets à abattre, le produit fini et la quantité produite, puis « Valider la Transformation ».",
                "Le nombre de sujets retire l'effectif de la bande et la quantité produite entre au stock du produit fini.",
                "L'historique en bas liste les transformations passées avec leur statut.",
            ],
        ],
        '/transferts-bandes' => [
            'titre' => 'Transferts entre Bandes',
            'puces' => [
                "Déplace des sujets d'une bande source vers une bande cible : « Nouveau Transfert ».",
                "Le tableau garde la date, les deux bandes, le nombre de sujets, la catégorie, le type, le motif et le statut de chaque transfert.",
                "Les cartes du haut comptent les transferts du mois, les sujets transférés et les bandes à vérifier.",
                "Les bandes peut-être issues d'une autre, sans origine renseignée, sont listées ; « Rattacher à sa bande d'origine » les relie.",
            ],
        ],
        '/elevage-dashboard' => [
            'titre' => 'Dashboard Élevage',
            'puces' => [
                "Tableau de bord de l'élevage en cinq onglets : synthèse globale, GMQ et croissance, rentabilité, analyse sanitaire et prévision de croissance.",
                "Les cartes de la synthèse donnent l'effectif total vivant, l'autonomie en aliment, le GMQ moyen et la mortalité cumulée sur 7 jours.",
                "Le GMQ (gain moyen quotidien) est le nombre de grammes pris par jour entre deux pesées.",
                "La synthèse affiche aussi les rappels de soins et vaccins à venir.",
            ],
        ],
        '/bilan-technico-economique' => [
            'titre' => 'Rentabilité de Lot',
            'puces' => [
                "Montre les coûts, les revenus et la marge d'une bande, alimentés par les achats, ventes et charges qui lui sont imputés.",
                "Choisissez la bande dans la liste en haut à droite.",
                "Les cartes donnent le coût total connu, le revenu total, la marge nette et le coût de revient par sujet.",
                "Le coût total ne comprend pas la main d'œuvre ; en dessous, le détail des coûts et celui des revenus.",
            ],
        ],
        '/analyse-croissance' => [
            'titre' => 'Analyse des Croissances',
            'puces' => [
                "Compare, pour chaque bande, les deux dernières pesées : poids précédent, poids actuel et jours écoulés.",
                "Le GMQ (g/jour) est le gain de poids moyen par jour entre ces deux pesées.",
                "La colonne « Statut vs Objectif » situe chaque bande par rapport à son objectif de croissance.",
                "« Exporter PDF » imprime le tableau.",
            ],
        ],
        '/registre-reproducteurs' => [
            'titre' => 'Registre des Reproducteurs',
            'puces' => [
                "Registre nominatif des reproducteurs : identifiant, espèce, sexe, race, bande, cage et statut.",
                "« Enregistrer un Reproducteur » ajoute un sujet ; le crayon le modifie ; l'icône de sortie enregistre son départ.",
                "L'icône « Consulter la fiche » ouvre la fiche détaillée du sujet.",
                "Les cartes du haut comptent les reproducteurs enregistrés, présents, femelles et mâles.",
            ],
        ],
        '/sujets/{animal}' => [
            'titre' => 'Fiche Sujet',
            'puces' => [
                "Fiche d'un reproducteur : identification et QR code du sujet.",
                "Plus bas, son historique : soins reçus, saillies et mises bas, et ses mouvements.",
                "« Exporter PDF » imprime la fiche.",
            ],
        ],

        '/ventes-devis' => [
            'titre' => 'Ventes & Devis',
            'puces' => [
                "Quatre onglets : « Enregistrer Vente » (la caisse), « Devis Prestations », « Historique des Ventes » et « Retours et Avoirs ».",
                "À la caisse, ajoutez les produits au panier, choisissez le client puis « Valider la Vente » ; le client peut être créé sur place.",
                "Un devis passe de brouillon à envoyé, puis accepté ou refusé, et peut être converti en facture.",
                "Dans l'historique, on consulte une vente ou on l'annule ; un retour crée un avoir.",
            ],
        ],
        '/creances-clients' => [
            'titre' => 'Créances Clients',
            'puces' => [
                "Quatre onglets : « Liste des Clients », « Suivi des Dettes », « Relances Clients » et « Historique Avances ».",
                "Le suivi des dettes liste les factures impayées avec leur échéance et le solde restant ; l'icône carte enregistre un règlement.",
                "Pour une relance, choisissez le niveau (rappel amiable, rappel ferme, mise en demeure) puis le modèle de message.",
                "Une avance est un acompte reçu d'un client ; « Imputer » l'applique à une dette.",
            ],
        ],
        '/clients/{customer}/profil' => [
            'titre' => 'Profil Client',
            'puces' => [
                "Fiche complète d'un client en quatre onglets : ventes, créances, avances et acomptes, relances.",
                "« Enregistrer un règlement » encaisse un paiement du client ; « Régler » vise une créance précise.",
                "« Envoyer une relance rapide » rappelle au client ce qu'il doit.",
                "La colonne Solde Dû donne ce qui reste à payer sur chaque créance.",
            ],
        ],
        '/achats-commandes' => [
            'titre' => 'Achats & Commandes',
            'puces' => [
                "Trois onglets : « Enregistrer un Achat », « Liste d'Achats » et « Bons de Commande ».",
                "Pour un achat, choisissez le fournisseur, ajoutez les lignes au bon d'achat, puis « Enregistrer l'Achat » ; fournisseur et produit peuvent être créés sur place.",
                "La liste d'achats montre le montant payé, le total et la dette ; elle permet un retour fournisseur et un remboursement.",
                "Un bon de commande émis se réceptionne avec « Valider la réception ».",
            ],
        ],
        '/fournisseurs' => [
            'titre' => 'Fournisseurs',
            'puces' => [
                "Trois onglets : « Ajouter Fournisseur », « Fiches Fournisseurs » et « Dettes Fournisseurs ».",
                "« Nouveau Fournisseur » crée une fiche ; le crayon la modifie ; l'icône d'archivage la retire.",
                "Les fiches donnent le total des achats de l'année et la dernière commande ; l'œil ouvre le profil du fournisseur.",
                "Les dettes listent le montant dû, l'échéance et le statut ; « Enregistrer un Règlement » paie une dette.",
            ],
        ],
        '/fournisseurs/{supplier}/profil' => [
            'titre' => 'Profil Fournisseur',
            'puces' => [
                "Fiche complète d'un fournisseur en trois onglets : achats, dettes et commandes.",
                "« Enregistrer un règlement » paie le fournisseur ; « Régler » vise une dette précise.",
                "La colonne Solde Dû donne ce qui reste à payer.",
            ],
        ],
        '/saisie-depenses' => [
            'titre' => 'Saisie des Dépenses',
            'puces' => [
                "Enregistre les dépenses de la ferme : « Nouvelle Dépense » ouvre le formulaire.",
                "Une dépense peut avoir plusieurs lignes, chacune avec son compte de charge et son montant ; le total est la somme des lignes.",
                "Les cartes du haut donnent les dépenses du mois, les charges fixes et les charges variables.",
                "Une dépense déjà comptabilisée ne se corrige pas : on l'archive, puis on en saisit une nouvelle.",
            ],
        ],
        '/facturation' => [
            'titre' => 'Facturation',
            'puces' => [
                "Registre des factures de vente : numéro, client, date, montant TTC et statut.",
                "L'icône d'impression produit la facture en PDF.",
                "Quand le module MeCeF est activé, la page ajoute le statut de transmission, la facture normalisée et la retransmission.",
                "Les cartes du haut comptent les factures du mois et le montant facturé.",
            ],
        ],

        '/personnel-stages' => [
            'titre' => 'Personnel & Stages',
            'puces' => [
                "Cinq onglets : « Registre Employés », « Registre Stagiaires », « Feuille de Pointage », « Gestion de la Paie » et « Attestations ».",
                "Les registres gardent les fiches : « Nouvel Employé » ou « Nouveau Stagiaire » en crée une, le crayon la modifie.",
                "La feuille de pointage enregistre l'arrivée et le départ de chaque employé, jour par jour.",
                "La paie calcule le net à payer de chaque bulletin ; « Valider le règlement » enregistre le paiement.",
            ],
        ],
        '/administration' => [
            'titre' => 'Administration & Documents',
            'puces' => [
                "Trois onglets : « Gestion des Courriers », « Archivage des Documents » et « Documents Administratifs ».",
                "Les courriers reçus et envoyés se notent avec une référence, un objet, la partie concernée et une date.",
                "L'archivage garde les documents avec leur date d'expiration ; une carte compte ceux qui expirent sous 30 jours.",
                "Dans chaque onglet, le bouton principal en haut crée une entrée.",
            ],
        ],

        '/comptabilite-hub' => [
            'titre' => 'Comptabilité',
            'puces' => [
                "Point d'entrée de la comptabilité : total de l'actif, recettes du mois, marge nette analytique et trésorerie disponible.",
                "Les cartes de navigation ouvrent chaque état : plan comptable, journal, grand livre, balance, balance âgée, bilan, états financiers, TVA, rapprochement bancaire, immobilisations, analytique et clôture.",
                "Toutes les écritures viennent des ventes, achats, dépenses et paies ; les écritures manuelles se saisissent dans le Journal.",
            ],
        ],
        '/plan-comptable' => [
            'titre' => 'Plan Comptable SYSCOHADA',
            'puces' => [
                "Liste les comptes du plan comptable, classés de 1 (ressources) à 9 (hors bilan et analytique).",
                "« Nouveau Compte » ajoute un compte avec son numéro, son intitulé et sa classe ; le crayon le modifie.",
                "L'icône d'archivage retire un compte de la liste ; la recherche filtre la liste.",
            ],
        ],
        '/journal-comptable' => [
            'titre' => 'Journal Comptable',
            'puces' => [
                "Liste les écritures : numéro de pièce, date, libellé, compte débité, compte crédité et montant.",
                "« Saisie d'Écriture » enregistre une écriture manuelle : un compte à débiter, un compte à créditer (différents) et un montant.",
                "Une écriture d'un exercice clôturé est verrouillée : elle ne se modifie plus.",
                "Les cartes du haut donnent le nombre d'écritures du mois et les totaux débit et crédit.",
            ],
        ],
        '/grand-livre' => [
            'titre' => 'Grand Livre',
            'puces' => [
                "Montre toutes les écritures d'un compte sur une période : choisissez le compte, puis les dates.",
                "Chaque ligne donne la date, le numéro de pièce, le libellé, le débit, le crédit et le solde progressif.",
                "Les cartes du haut donnent le solde d'ouverture, les totaux débit et crédit de la période et le solde final.",
            ],
        ],
        '/balance-generale' => [
            'titre' => 'Balance Générale',
            'puces' => [
                "Récapitule tous les comptes : solde d'ouverture, mouvements de la période et solde final.",
                "Choisissez la période : l'exercice entier ou un mois.",
                "Les colonnes sont en débit et en crédit ; « Exporter PDF » imprime la balance.",
            ],
        ],
        '/balance-agee' => [
            'titre' => 'Balance Âgée',
            'puces' => [
                "Classe ce qui est dû par ancienneté : choisissez le volet « Créances clients » ou « Dettes fournisseurs ».",
                "Réglez la date d'arrêté : l'ancienneté se calcule à cette date.",
                "La colonne Total donne ce qui est dû par chaque tiers, toutes anciennetés confondues.",
            ],
        ],
        '/rapport-bilan' => [
            'titre' => 'Bilan',
            'puces' => [
                "Bilan simplifié de l'entreprise à une date : l'actif (emplois) d'un côté, le passif (ressources) de l'autre.",
                "Changez la date pour voir le bilan à un autre moment.",
                "L'actif se lit par classe : immobilisé, circulant (stocks et tiers) et trésorerie.",
            ],
        ],
        '/etats-financiers' => [
            'titre' => 'États Financiers',
            'puces' => [
                "Quatre onglets : « Bilan », « Compte de Résultat », « Flux de Trésorerie » et « Notes Annexes ».",
                "Le bilan compare l'exercice affiché (N) à l'exercice précédent (N-1).",
                "« Exporter PDF (Onglet Actif) » imprime l'onglet affiché.",
            ],
        ],
        '/declaration-tva' => [
            'titre' => 'Déclaration TVA',
            'puces' => [
                "Prépare la déclaration de TVA d'une période : choisissez la période de déclaration.",
                "TVA collectée : les ventes assujetties, facture par facture. TVA déductible : les achats assujettis.",
                "« Générer la Déclaration PDF » produit le document.",
            ],
        ],
        '/rapprochement-bancaire' => [
            'titre' => 'Rapprochement Bancaire',
            'puces' => [
                "Compare le grand livre d'un compte de banque au relevé de la banque.",
                "Choisissez le compte et la période, importez le relevé, puis « Lancer l'import ».",
                "Chaque ligne du relevé importé a un statut de rapprochement.",
            ],
        ],
        '/immobilisations' => [
            'titre' => 'Immobilisations',
            'puces' => [
                "Registre des biens durables de la ferme, avec leur valeur brute, leur amortissement et leur valeur nette comptable.",
                "« Nouvelle Immobilisation » enregistre un bien ; le crayon le modifie ; l'icône de sortie enregistre sa cession ou sa réforme.",
                "« Passer la Dotation » enregistre l'amortissement à une date d'arrêté.",
                "La ventilation par nature d'actif récapitule les biens par compte.",
            ],
        ],
        '/comptabilite-analytique' => [
            'titre' => 'Comptabilité Analytique',
            'puces' => [
                "Compare, filière par filière, le chiffre d'affaires et les charges directes.",
                "Choisissez la période et, si vous voulez, une seule filière.",
                "Les cartes donnent le chiffre d'affaires, les charges directes, la marge brute et le taux de rentabilité.",
                "Le bloc « Top 3 Charges » montre les trois plus grosses charges de la filière choisie.",
            ],
        ],
        '/cloture-exercice' => [
            'titre' => "Clôture d'Exercice",
            'puces' => [
                "Deux clôtures : la clôture périodique, mois par mois (verrouillage léger), puis la clôture annuelle de l'exercice, guidée par un assistant (N vers N+1).",
                "Un mois ne se clôture que si la balance est équilibrée ; un mois clôturé verrouille ses écritures en lecture seule.",
                "Seul l'administrateur peut déclôturer un mois ; l'action est journalisée dans les logs d'audit.",
                "L'assistant annuel passe par les travaux d'inventaire (à saisir dans le Journal Comptable), le solde des comptes de gestion (classes 6 et 7) et la génération des à-nouveaux.",
            ],
        ],

        '/bareme-its' => [
            'titre' => 'Barème IR-PTS / ITS',
            'puces' => [
                "Tranches d'imposition utilisées pour calculer la retenue ITS sur les salaires : de, à et taux (%).",
                "« Ajouter une tranche » en ajoute une, la corbeille la retire ; « Enregistrer le barème » valide le tout.",
                "La simulation calcule les retenues d'un salaire brut mensuel d'essai avec le barème affiché.",
            ],
        ],
        '/rapport-mensuel' => [
            'titre' => 'Rapport Mensuel de Synthèse',
            'puces' => [
                "Compare, indicateur par indicateur, le mois courant et le mois précédent, avec la variation.",
                "Le rapport est généré à partir des données réelles : il se lit ici, il ne se modifie pas.",
                "« Exporter PDF » imprime le rapport.",
            ],
        ],
        '/rapports-exports' => [
            'titre' => 'Rapports & Exports',
            'puces' => [
                "Six états en onglets : recettes et dépenses, trésorerie, créances clients, dettes fournisseurs, élevage et stocks.",
                "Choisissez d'abord la période (de, au) : tous les onglets la suivent.",
                "« Exporter PDF » et « Exporter Excel » sortent l'onglet affiché, pour les comptes qui ont ce droit.",
            ],
        ],
        '/parametres-hub' => [
            'titre' => 'Paramètres',
            'puces' => [
                "Onze onglets : rôles et permissions, données de l'entreprise, e-mail (SMTP), modules actifs, utilisateurs, postes et appairage, modes de paiement, audit, corbeille, réinitialisation et sauvegardes.",
                "« Modules Actifs » allume ou éteint les espèces d'élevage et l'assistant de démarrage.",
                "« Gestion Utilisateurs » crée les comptes et attribue un rôle à chacun.",
                "« Corbeille » restaure ce qui a été archivé ; « Audit Logs » garde la trace des actions.",
            ],
        ],
    ],

    /*
     * Écrans du poste SANS route web : le web ne les lit pas, le poste oui (clé = nom de l'`EcranPoste`).
     */
    'poste_seul' => [
        'synchronisation' => [
            'titre' => 'Synchronisation',
            'puces' => [
                "Ce poste travaille hors ligne : les saisies restent ici jusqu'à leur envoi.",
                "Le compteur « En attente d'envoi » dit combien de saisies attendent ; « Synchroniser » lance l'envoi et la réception.",
                "Les refus du serveur sont listés avec leur motif ; « Remettre en file » renvoie les saisies une fois la cause corrigée.",
                "« Contrôle de cohérence » compare ce poste au serveur (il faut être en ligne).",
            ],
        ],
        'parametres' => [
            'titre' => 'Paramètres du poste',
            'puces' => [
                "Ouvre Paramètres sur l'onglet « Appairage » : adresse du serveur, identifiant de ce poste et état de son jeton.",
                "« Tester la connexion » vérifie que le serveur répond ; « Réappairer » refait l'appairage du poste.",
                "Une nouvelle adresse de serveur n'est effective qu'au redémarrage du poste.",
                "Réservé à l'administrateur.",
            ],
        ],
    ],
];
