# RAPPORT D'EMPLACEMENT — le bon libellé au bon endroit (phase 1A)

Généré par `outils/emplacement.py` à partir de `build/audit/rendu_onglets.json` (banc `test/rendu_onglets_test.dart`, ticket AF1.2). **Le poste est rendu en widgets, pas lu dans le source.**

> ⚠️ **Base vide.** Le rendu est relevé sans donnée : un en-tête de tableau ou un champ de modale que l'écran ne dessine qu'avec des lignes tombe en « source seul », jamais en « absent ». Ce rapport prouve qu'un libellé est au bon (ou au mauvais) endroit **quand il est rendu** ; il ne prouve pas qu'un libellé non rendu est affiché ailleurs en situation réelle.

## 1. Synthèse par écran et par onglet

| Écran › onglet (prototype → poste) | Libellés | ici | ailleurs | source seul | absent | Cartes proto / poste | Inversions d'ordre |
|---|---|---|---|---|---|---|---|
| tableau-de-bord › dashboard → (par défaut) | 31 | 28 | 0 | 0 | 3 | 8 / 8 | 0 |
| elevage-dashboard › dash-tab-synthese → Synthèse Globale | 17 | 16 | 0 | 0 | 1 | 4 / 4 | 0 |
| elevage-dashboard › dash-tab-gmq → GMQ & Croissance | 18 | 18 | 0 | 0 | 0 | 4 / 4 | 0 |
| elevage-dashboard › dash-tab-bilan → Bilan Technico-Économique | 12 | 6 | 0 | 0 | 6 | 4 / 0 ✘ | 0 |
| elevage-dashboard › dash-tab-sanitaire → Analyse Sanitaire | 16 | 7 | 2 | 0 | 7 | 0 / 3 ✘ | 0 |
| elevage-dashboard › dash-tab-prevision → Prévision de Croissance | 17 | 8 | 0 | 0 | 9 | 3 / 0 ✘ | 0 |
| suivi-reproduction › panel-lapins → Lapins | 24 | 22 | 0 | 0 | 2 | 4 / 4 | 0 |
| suivi-reproduction › panel-volailles → Volailles | 21 | 12 | 2 | 0 | 7 | 4 / 4 | 0 |
| suivi-reproduction › panel-porcs → Porcs | 22 | 20 | 0 | 0 | 2 | 4 / 4 | 0 |
| suivi-reproduction › panel-escargots → Escargots | 29 | 11 | 3 | 6 | 9 | 4 / 4 | 0 |
| soins-vaccins-hub › vms-registre → Registre Vétérinaire | 37 | 22 | 1 | 8 | 6 | 4 / 4 | 0 |
| soins-vaccins-hub › vms-calendrier → Calendrier Vétérinaire | 15 | 6 | 0 | 1 | 8 | 0 / 0 | 0 |
| soins-vaccins-hub › vms-suivi → Suivi Sanitaire | 27 | 6 | 4 | 2 | 15 | 5 / 0 ✘ | 0 |
| parametres-elevage › panel-rationnement → Fiche de Rationnement (g/j) | 11 | 9 | 0 | 0 | 2 | 0 / 0 | 0 |
| parametres-elevage › panel-prophylaxie → Calendriers de Prophylaxie | 16 | 14 | 0 | 0 | 2 | 0 / 0 | 0 |
| parametres-elevage › panel-provende → Types de Provende | 12 | 10 | 0 | 0 | 2 | 0 / 0 | 0 |
| parametres-elevage › panel-numerotation → Numérotation Bandes & Sujets | 34 | 6 | 8 | 5 | 15 | 0 / 0 | 0 |
| creances-clients › liste-clients → Liste des Clients | 37 | 17 | 0 | 0 | 20 | 3 / 3 | 0 |
| creances-clients › suivi-dettes → Suivi des Dettes | 24 | 15 | 0 | 0 | 9 | 4 / 4 | 0 |
| creances-clients › relances-clients → Relances Clients | 20 | 15 | 0 | 0 | 5 | 4 / 4 | 0 |
| creances-clients › historique-avances → Historique Avances | 32 | 15 | 0 | 0 | 17 | 3 / 3 | 0 |
| gestion-stocks › stock-tab-tableau → Tableau & Valorisation | 20 | 18 | 0 | 0 | 2 | 4 / 4 | 0 |
| gestion-stocks › stock-tab-mouvements → Journal des Mouvements | 16 | 15 | 0 | 0 | 1 | 4 / 4 | 0 |
| gestion-stocks › stock-tab-ajustements → Ajustement / Correction | 32 | 17 | 2 | 0 | 13 | 4 / 4 | 0 |
| catalogue-produits › catalogue-view → Voir le Catalogue | 24 | 9 | 2 | 3 | 10 | 0 / 0 | 0 |
| catalogue-produits › seuils-alerte → Seuils d'Alerte | 21 | 11 | 0 | 0 | 10 | 2 / 2 | 0 |
| ventes-devis › pos-interface → Enregistrer Vente | 44 | 13 | 1 | 0 | 30 | 0 / 0 | 0 |
| ventes-devis › devis → Devis Prestations | 41 | 6 | 4 | 0 | 31 | 4 / 0 ✘ | 0 |
| ventes-devis › historique-ventes → Historique des Ventes | 37 | 24 | 0 | 0 | 13 | 4 / 4 | 0 |
| ventes-devis › retours-avoirs → Retours et Avoirs | 34 | 7 | 6 | 0 | 21 | 4 / 0 ✘ | 0 |
| parametres-hub › roles-permissions → Rôles & Permissions | 51 | 35 | 1 | 0 | 15 | 4 / 4 | 0 |
| parametres-hub › parametres → Données de l'Entreprise | 21 | 9 | 1 | 7 | 4 | 0 / 0 | 0 |
| parametres-hub › modules-actifs → Modules Actifs | 7 | 7 | 0 | 0 | 0 | 0 / 0 | 0 |
| parametres-hub › gestion-utilisateurs → Gestion Utilisateurs | 26 | 17 | 0 | 0 | 9 | 2 / 2 | 0 |
| parametres-hub › modes-paiement → Modes de Paiement | 29 | 18 | 0 | 0 | 11 | 3 / 3 | 0 |
| parametres-hub › audit-logs → Audit Logs | 22 | 14 | 0 | 0 | 8 | 2 / 2 | 0 |
| rapports-exports › rapport-recettes-depenses → Recettes et Dépenses | 20 | 20 | 0 | 0 | 0 | 3 / 3 | 0 |
| rapports-exports › rapport-tresorerie → État de Trésorerie | 17 | 17 | 0 | 0 | 0 | 0 / 0 | 0 |
| rapports-exports › rapport-creances → Créances Clients | 16 | 16 | 0 | 0 | 0 | 0 / 0 | 0 |
| rapports-exports › rapport-dettes → Dettes Fournisseurs | 16 | 16 | 0 | 0 | 0 | 0 / 0 | 0 |
| rapports-exports › rapport-elevage-synth → Rapport Élevage | 58 | 37 | 0 | 20 | 1 | 4 / 4 | 0 |
| rapports-exports › rapport-stocks-synth → Rapport de Stocks | 16 | 16 | 0 | 0 | 0 | 0 / 0 | 0 |
| administration › gestion-courriers → Gestion des Courriers | 26 | 13 | 1 | 0 | 12 | 3 / 3 ✘ | 0 |
| administration › archivage-documents → Archivage des Documents | 24 | 12 | 0 | 0 | 12 | 2 / 3 ✘ | 0 |
| administration › documents-administratifs → Documents Administratifs | 24 | 12 | 0 | 0 | 12 | 2 / 3 ✘ | 0 |
| personnel-stages › registre-employes → Registre Employés | 27 | 16 | 1 | 1 | 9 | 2 / 2 | 0 |
| personnel-stages › registre-stagiaires → Registre Stagiaires | 31 | 17 | 1 | 1 | 12 | 4 / 4 | 0 |
| personnel-stages › feuille-pointage → Feuille de Pointage | 29 | 20 | 0 | 3 | 6 | 3 / 4 ✘ | 0 |
| personnel-stages › gestion-paie → Gestion de la Paie | 22 | 19 | 0 | 0 | 3 | 4 / 4 | 0 |
| personnel-stages › rh-attestations → Attestations | 24 | 8 | 0 | 0 | 16 | 0 / 0 | 0 |
| fournisseurs › ajouter-fournisseur → Ajouter Fournisseur | 25 | 12 | 0 | 0 | 13 | 2 / 2 | 0 |
| fournisseurs › fiches-fournisseurs → Fiches Fournisseurs | 33 | 13 | 0 | 0 | 20 | 2 / 2 | 0 |
| fournisseurs › dettes-fournisseurs → Dettes Fournisseurs | 26 | 10 | 0 | 0 | 16 | 3 / 3 ✘ | 0 |
| achats-commandes › enregistrer-achat → Enregistrer un Achat | 33 | 28 | 0 | 0 | 5 | 0 / 0 | 0 |
| achats-commandes › liste-achats → Liste d'Achats | 35 | 17 | 0 | 0 | 18 | 4 / 4 | 0 |
| achats-commandes › bons-commande → Bons de Commande | 34 | 15 | 6 | 0 | 13 | 0 / 0 | 0 |
| comptabilite-hub › (accueil) → (par défaut) | 5 | 1 | 0 | 0 | 4 | 4 / 4 ✘ | 0 |
| comptabilite-hub › plan-comptable → planComptable | 19 | 9 | 0 | 0 | 10 | 2 / 2 | 0 |
| comptabilite-hub › journal-comptable → journal | 25 | 12 | 0 | 0 | 13 | 3 / 3 | 0 |
| comptabilite-hub › grand-livre → grandLivre | 12 | 11 | 0 | 0 | 1 | 3 / 3 | 0 |
| comptabilite-hub › balance-generale → balance | 12 | 11 | 0 | 0 | 1 | 2 / 2 | 0 |
| comptabilite-hub › etats-financiers → etatsFinanciers | 20 | 3 | 1 | 0 | 16 | 0 / 0 | 0 |
| comptabilite-hub › cloture-exercice → cloture | 26 | 1 | 1 | 0 | 24 | 3 / 0 ✘ | 0 |
| comptabilite-hub › comptabilite-analytique → analytique | 9 | 1 | 0 | 0 | 8 | 4 / 0 ✘ | 0 |
| comptabilite-hub › declaration-tva → tva | 16 | 3 | 1 | 0 | 12 | 2 / 0 ✘ | 0 |
| comptabilite-hub › rapprochement-bancaire → rapprochement | 17 | 1 | 7 | 0 | 9 | 3 / 0 ✘ | 0 |

**Total : 1594 libellés — 890 au bon endroit (55.8 %), 56 dans un autre onglet, 57 dans le source seulement, 591 absents.**

« absent » se recoupe avec le rapport de présence (`RAPPORT_FIDELITE_2.md`) ; « source seul » est ce que le banc à vide ne peut pas voir (modales, lignes de tableau).

## 2. Libellés rendus dans le mauvais onglet

- **elevage-dashboard › Analyse Sanitaire** — « Espèce » (colonnes) est rendu dans « Synthèse Globale », pas ici
- **elevage-dashboard › Analyse Sanitaire** — « Évolution » (colonnes) est rendu dans « GMQ & Croissance », pas ici
- **suivi-reproduction › Volailles** — « Statut » (colonnes) est rendu dans « Lapins », pas ici
- **suivi-reproduction › Volailles** — « Action » (colonnes) est rendu dans « Lapins », pas ici
- **suivi-reproduction › Escargots** — « Statut » (colonnes) est rendu dans « Lapins », pas ici
- **suivi-reproduction › Escargots** — « Action » (colonnes) est rendu dans « Lapins », pas ici
- **suivi-reproduction › Escargots** — « Résultat Palpation » (titres) est rendu dans « Lapins », pas ici
- **soins-vaccins-hub › Registre Vétérinaire** — « Lot / Bande * » (etiquettes) est rendu dans « Calendrier Vétérinaire », pas ici
- **soins-vaccins-hub › Suivi Sanitaire** — « Exporter PDF » (boutons) est rendu dans « Registre Vétérinaire », pas ici
- **soins-vaccins-hub › Suivi Sanitaire** — « En Quarantaine » (cartes) est rendu dans « Registre Vétérinaire », pas ici
- **soins-vaccins-hub › Suivi Sanitaire** — « Statut » (colonnes) est rendu dans « Registre Vétérinaire », pas ici
- **soins-vaccins-hub › Suivi Sanitaire** — « Actions » (colonnes) est rendu dans « Registre Vétérinaire », pas ici
- **parametres-elevage › Numérotation Bandes & Sujets** — « Stade Physiologique / Tranche d'Âge * » (etiquettes) est rendu dans « Fiche de Rationnement (g/j) », pas ici
- **parametres-elevage › Numérotation Bandes & Sujets** — « Traitement Prévu * » (etiquettes) est rendu dans « Calendriers de Prophylaxie », pas ici
- **parametres-elevage › Numérotation Bandes & Sujets** — « Produit Conseillé * » (etiquettes) est rendu dans « Calendriers de Prophylaxie », pas ici
- **parametres-elevage › Numérotation Bandes & Sujets** — « Type de Provende » (titres) est rendu dans « Types de Provende », pas ici
- **parametres-elevage › Numérotation Bandes & Sujets** — « Nom du Type d'Aliment * » (etiquettes) est rendu dans « Types de Provende », pas ici
- **parametres-elevage › Numérotation Bandes & Sujets** — « Espèce Cible * » (etiquettes) est rendu dans « Types de Provende », pas ici
- **parametres-elevage › Numérotation Bandes & Sujets** — « Poids Sac Standard (Kg) * » (etiquettes) est rendu dans « Types de Provende », pas ici
- **parametres-elevage › Numérotation Bandes & Sujets** — « Prix Indicatif (FCFA / Kg) * » (etiquettes) est rendu dans « Types de Provende », pas ici
- **gestion-stocks › Ajustement / Correction** — « Désignation * » (etiquettes) est rendu dans « Tableau & Valorisation », pas ici
- **gestion-stocks › Ajustement / Correction** — « Catégorie * » (etiquettes) est rendu dans « Tableau & Valorisation », pas ici
- **catalogue-produits › Voir le Catalogue** — « Stock » (colonnes) est rendu dans « Seuils d'Alerte », pas ici
- **catalogue-produits › Voir le Catalogue** — « Actions » (colonnes) est rendu dans « Seuils d'Alerte », pas ici
- **ventes-devis › Enregistrer Vente** — « Tous » (boutons) est rendu dans « Historique des Ventes », pas ici
- **ventes-devis › Devis Prestations** — « Date » (colonnes) est rendu dans « Historique des Ventes », pas ici
- **ventes-devis › Devis Prestations** — « Montant » (colonnes) est rendu dans « Enregistrer Vente », pas ici
- **ventes-devis › Devis Prestations** — « Statut » (colonnes) est rendu dans « Historique des Ventes », pas ici
- **ventes-devis › Devis Prestations** — « Actions » (colonnes) est rendu dans « Historique des Ventes », pas ici
- **ventes-devis › Retours et Avoirs** — « Facture » (colonnes) est rendu dans « Historique des Ventes », pas ici
- **ventes-devis › Retours et Avoirs** — « Client » (colonnes) est rendu dans « Enregistrer Vente », pas ici
- **ventes-devis › Retours et Avoirs** — « Date » (colonnes) est rendu dans « Historique des Ventes », pas ici
- **ventes-devis › Retours et Avoirs** — « Montant » (colonnes) est rendu dans « Enregistrer Vente », pas ici
- **ventes-devis › Retours et Avoirs** — « Statut » (colonnes) est rendu dans « Historique des Ventes », pas ici
- **ventes-devis › Retours et Avoirs** — « Actions » (colonnes) est rendu dans « Historique des Ventes », pas ici
- **parametres-hub › Rôles & Permissions** — « Date » (colonnes) est rendu dans « Audit Logs », pas ici
- **parametres-hub › Données de l'Entreprise** — « Sécurité » (etiquettes) est rendu dans « Audit Logs », pas ici
- **administration › Gestion des Courriers** — « En attente » (cartes) est rendu dans « Documents Administratifs », pas ici
- **personnel-stages › Registre Employés** — « Enregistrer » (boutons) est rendu dans « Feuille de Pointage », pas ici
- **personnel-stages › Registre Stagiaires** — « Enregistrer » (boutons) est rendu dans « Feuille de Pointage », pas ici
- **achats-commandes › Bons de Commande** — « Quantité » (etiquettes) est rendu dans « Enregistrer un Achat », pas ici
- **achats-commandes › Bons de Commande** — « Produit » (colonnes) est rendu dans « Enregistrer un Achat », pas ici
- **achats-commandes › Bons de Commande** — « Qté » (colonnes) est rendu dans « Enregistrer un Achat », pas ici
- **achats-commandes › Bons de Commande** — « P.U » (colonnes) est rendu dans « Enregistrer un Achat », pas ici
- **achats-commandes › Bons de Commande** — « Total » (colonnes) est rendu dans « Enregistrer un Achat », pas ici
- **achats-commandes › Bons de Commande** — « Désignation * » (etiquettes) est rendu dans « Enregistrer un Achat », pas ici
- **comptabilite-hub › etatsFinanciers** — « Montant » (colonnes) est rendu dans « journal », pas ici
- **comptabilite-hub › cloture** — « Mois » (colonnes) est rendu dans « journal », pas ici
- **comptabilite-hub › tva** — « Date » (colonnes) est rendu dans « journal », pas ici
- **comptabilite-hub › rapprochement** — « Compte : » (etiquettes) est rendu dans « planComptable », pas ici
- **comptabilite-hub › rapprochement** — « Date » (colonnes) est rendu dans « journal », pas ici
- **comptabilite-hub › rapprochement** — « Libellé » (colonnes) est rendu dans « journal », pas ici
- **comptabilite-hub › rapprochement** — « Montant » (colonnes) est rendu dans « journal », pas ici
- **comptabilite-hub › rapprochement** — « Période » (colonnes) est rendu dans « grandLivre », pas ici
- **comptabilite-hub › rapprochement** — « Compte » (colonnes) est rendu dans « planComptable », pas ici
- **comptabilite-hub › rapprochement** — « Solde Final » (colonnes) est rendu dans « balance », pas ici

## 3. Cartes d'indicateur : libellé et ordre (faiblesse n° 2 de CLAUDE.md)

Le contrôle de comptage (F0.54) voit les cartes apparaître et disparaître mais jamais ce qu'elles disent. Ici, libellé contre libellé, dans l'ordre.

### 3.1 Même nombre de cartes, libellés différents — INVISIBLES au contrôle de comptage

Le compte est juste, donc F0.54 se tait. Ce sont les seuls écarts de cette section que rien ne pouvait voir avant ce rapport.

#### administration › Gestion des Courriers

| # | Prototype | Poste |
|---|---|---|
| 1 | Reçus (mois) | Courriers (mois) |
| 2 | Envoyés (mois) | Reçus |
| 3 | En attente | Envoyés |

#### fournisseurs › Dettes Fournisseurs

| # | Prototype | Poste |
|---|---|---|
| 1 | Dettes totales | Ardoise Totale |
| 2 | En retard | Dettes Échues |
| 3 | Fournisseurs concernés | Fournisseurs |

#### comptabilite-hub › (par défaut)

| # | Prototype | Poste |
|---|---|---|
| 1 | Total Actif (Bilan) | Écritures reçues |
| 2 | Trésorerie Totale | Total Débit |
| 3 | Marge Nette (Analytique) | Total Crédit |
| 4 | Résultat de l'Exercice | Écritures incomplètes |

### 3.2 Nombre de cartes différent

Déjà vus par le contrôle de comptage (voir `ecartsAssumes`, `ecartsATraiter`, `ecartsPanneaux`). Ils sont repris ici avec les libellés, que ce contrôle ne montre pas.

#### elevage-dashboard › Bilan Technico-Économique

| # | Prototype | Poste |
|---|---|---|
| 1 | Coût Total du Lot | — |
| 2 | Revenu Total du Lot | — |
| 3 | Marge Nette | — |
| 4 | Coût de Revient / Sujet | — |

#### elevage-dashboard › Analyse Sanitaire

| # | Prototype | Poste |
|---|---|---|
| 1 | — | Traitements du Mois |
| 2 | — | Coût Sanitaire du Mois |
| 3 | — | Traitement le Plus Fréquent |

#### elevage-dashboard › Prévision de Croissance

| # | Prototype | Poste |
|---|---|---|
| 1 | Poids Projeté | — |
| 2 | Poids Cible de Commercialisation | — |
| 3 | Date Estimée d'Atteinte de la Cible | — |

#### soins-vaccins-hub › Suivi Sanitaire

| # | Prototype | Poste |
|---|---|---|
| 1 | En Quarantaine | — |
| 2 | Guéris (mois) | — |
| 3 | Sous Traitement | — |
| 4 | Décès (mois) | — |
| 5 | Taux d'Infirmerie | — |

#### ventes-devis › Devis Prestations

| # | Prototype | Poste |
|---|---|---|
| 1 | Devis Actifs | — |
| 2 | Valeur Totale | — |
| 3 | Taux de Conversion | — |
| 4 | En Attente de Relance | — |

#### ventes-devis › Retours et Avoirs

| # | Prototype | Poste |
|---|---|---|
| 1 | Retours du mois | — |
| 2 | Montant Avoirs | — |
| 3 | Produits Retournés | — |
| 4 | Taux de Retour | — |

#### administration › Archivage des Documents *(page déjà citée dans `cartes_attendues.dart`)*

| # | Prototype | Poste |
|---|---|---|
| 2 | Expirant sous 30j | Expirés |
| 3 | — | À renouveler |

#### administration › Documents Administratifs *(page déjà citée dans `cartes_attendues.dart`)*

| # | Prototype | Poste |
|---|---|---|
| 1 | Modèles disponibles | Documents |
| 2 | Générés (mois) | Signés |
| 3 | — | En attente |

#### personnel-stages › Feuille de Pointage *(page déjà citée dans `cartes_attendues.dart`)*

| # | Prototype | Poste |
|---|---|---|
| 1 | Présents (jour) | Présents |
| 4 | — | À pointer |

#### comptabilite-hub › cloture

| # | Prototype | Poste |
|---|---|---|
| 1 | Résultat Provisoire | — |
| 2 | Comptes de Gestion à Solder | — |
| 3 | Lettrage Bancaire | — |

#### comptabilite-hub › analytique

| # | Prototype | Poste |
|---|---|---|
| 1 | Chiffre d'Affaires Analytique | — |
| 2 | Charges Directes | — |
| 3 | Marge Brute Opérationnelle | — |
| 4 | Taux de Rentabilité | — |

#### comptabilite-hub › tva

| # | Prototype | Poste |
|---|---|---|
| 1 | TVA Collectée (4431) | — |
| 2 | TVA Déductible (4452) | — |

#### comptabilite-hub › rapprochement

| # | Prototype | Poste |
|---|---|---|
| 1 | Solde Livre (Grand Livre) | — |
| 2 | Solde Relevé Bancaire | — |
| 3 | Opérations en Instance | — |

## 4. Ordre des éléments

Pour chaque onglet, les titres, cartes et colonnes rendus sont comparés à l'ordre du document du prototype, catégorie par catégorie, sur les seules correspondances EXACTES (l'inclusion de mots courts fabriquait de fausses inversions). Une inversion = deux éléments rendus dans l'ordre contraire.

Aucune inversion détectée.

## 5. Débordements de mise en page relevés au rendu (1280 px)

Levés par Flutter pendant le rendu à vide (`RenderFlex overflowed`) — visibles à l'écran comme une bande jaune et noire en mode debug.

- **elevage-dashboard** — A RenderFlex overflowed by 43 pixels on the right.
- **soins-vaccins-hub** — A RenderFlex overflowed by 5.2 pixels on the bottom.
- **gestion-stocks** — A RenderFlex overflowed by 1.2 pixels on the bottom.
- **gestion-stocks** — A RenderFlex overflowed by 1.2 pixels on the bottom.

## 6. Écrans que le banc n'a pas couverts

Fiches d'espèce (5), Gestion Élevage, Saisie Dépenses, Facturation, Caisse, Synchronisation, Paramètres du poste : sans onglets au sens de la convention de clés, ils demandent un banc dédié (une fiche = une saisie journalière + un tableau mensuel). **Non mesurés** — ne pas les croire conformes au motif qu'ils n'apparaissent pas ici.

## Synthèse

**0 bloquant · 76 majeur · 3 mineur.**
