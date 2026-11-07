# 13 — FRS : exigences fonctionnelles testables de LogiALVIA, module par module

## USAGE

- **Quand l'utiliser** : après le SRS (`12_`), pour dérouler les tests d'un module AVANT de le déclarer terminé ; chaque `FR-` se transforme en test Feature (Laravel), test de parité (Dart ↔ PHP) ou test de widget. Le plan de tests global est dans `31_TESTING_QA.md`.
- **Ordre** : `10` → `11` → `12` → **`13_FRS`** → `14_NFRS` → `15_REGLES_METIER` (les formules) → fichiers de module `21_` à `29_` (détail écran par écran).
- **Entrées** : `logialvia/docs/B4_FRS_Functional_Requirements.md` (FRS-ELV-01…, FRS-VTE-01…, FRS-STK-01…, FRS-CPT-01…, FRS-ADM-01…), F1 à F9, H1, H2, J1, J2, `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md`.
- **Sorties** : ce fichier à jour ; chaque `FR-` porte (id, énoncé, critère de vérification, ancêtre B4 s'il existe, source).
- **Chemins** : `logialvia/…` = `/home/user/massenon/logialvia/…` ; sans préfixe = `/home/user/agrierp`.

---

## 1. PROMPT — « Rédige / mets à jour le FRS de LogiALVIA »

> **Rôle.** Analyste fonctionnel et ingénieur de test senior.
> **Contexte.** B4 contient 25 exigences (FRS-…) écrites pour le poste seul. Le web crée de nouvelles exigences (rôles, synchronisation, MeCeF, import, exercices) et des corrections issues de F1…F9 et du guide.
> **Tâches.** (1) Garde TOUS les FRS-xxx de B4, renumérotés `FR-` avec la colonne « Ancêtre » ; (2) ajoute les exigences issues de F1…F9/H1/H2/J1/J2 et du guide ; (3) pour chaque `FR-` écris un critère de vérification exécutable (entrée → sortie attendue, avec un jeu de cas calculé à la main quand il y a un calcul) ; (4) classe par module ; (5) marque À DÉFINIR ce qu'aucune source ne tranche (pisciculture, pintades, paie…), avec question numérotée.
> **Contraintes.** Un `FR-` = une fonction vérifiable ; les messages exacts (refus, bannières) sont reproduits mot pour mot depuis les sources ; les valeurs numériques sont calculées à la main (jamais produites par le code testé) ; le web est le maître : le critère s'écrit d'abord pour le web, puis « et au poste : identique ».
> **Critères d'acceptation.** (a) ≥ 120 lignes `FR-` ; (b) tout FRS-xxx de B4 y figure (`grep -c` sur 25) ; (c) chaque ligne a un critère avec une valeur ou un message exact ; (d) chaque `FR-` renvoie à une règle `RM-` de `15_REGLES_METIER.md` quand il y a calcul ; (e) aucun `FR-` de pisciculture/pintade ne contient de formule inventée.
> **Interdits.** Écrire un critère « fonctionne correctement » sans valeur ; inventer un seuil ; dupliquer une règle de `15_` au lieu de la référencer ; affaiblir un critère pour qu'un test passe.

---

## 2. Authentification et compte (module `21_`)

| ID | Exigence | Critère de vérification | Ancêtre / source |
|---|---|---|---|
| FR-AUT-01 | Le formulaire de connexion exige identifiant et mot de passe non vides après `trim()`. | Vide → « L'adresse e-mail est obligatoire. » / « Le mot de passe est obligatoire. » + toast « Veuillez renseigner tous les champs requis. » | F1 |
| FR-AUT-02 | Identifiant inconnu ou mot de passe faux donnent le même message avec le compteur. | « Adresse e-mail ou mot de passe incorrect. Veuillez réessayer. (n/5) » dans les deux cas | F1 |
| FR-AUT-03 | Au 5e échec : blocage 15 min, bannière, bouton désactivé, aucun toast. | Bannière « Trop de tentatives de connexion. Accès bloqué pendant 15min. » puis compte à rebours `Mmin Ss` ; à expiration, réactivé, compteur 0 | F1 |
| FR-AUT-04 | Connexion réussie : toast « Connexion réussie — Bienvenue ! », 700 ms, redirection `/dashboard`. | test de parcours | F1 |
| FR-AUT-05 | Chaque échec est écrit dans `security_logs` (`echec_connexion`) sans le mot de passe ; connexion/déconnexion dans `audit_logs`. | requête sur les tables | F1, I3 §6 |
| FR-AUT-06 | « Se souvenir de moi » mémorise l'identifiant seulement ; décocher l'efface ; n'écrit qu'après connexion réussie. | relancer : identifiant prérempli, aucune session | F1 |
| FR-AUT-07 | Aucune modale « Mot de passe oublié » envoyant un e-mail : texte non cliquable « Contactez l'administrateur ». | clé de widget `login-contacter-administrateur` | guide bloc 2 |
| FR-AUT-08 | Compte initial `admin` (idempotent) ; mot de passe initial changé de force à la première connexion. | 2e seeding ne recrée rien ; connexion initiale → écran de changement | F1 ; BR-038 |
| FR-AUT-09 | Mon Profil : nom, identifiant, rôle (lecture seule), changement de mot de passe (ancien requis, nouveau ≠ ancien, confirmation identique, politique). | refus si nouveau = ancien | F9 |
| FR-AUT-10 | Aide & À Propos (version, guide, FAQ) et Contact éditeur sans faux envoi : le formulaire ne simule pas un envoi. | pas de toast de succès sans écriture | F9 ; A1 §2.3 |
| FR-AUT-11 | Mot de passe temporaire : sessions et jetons du compte détruits, `must_change_password=true`, audit `user.password_reset`. | connexion suivante bloquée par l'écran de changement | guide bloc 2 |
| FR-AUT-12 | Rôle `animalier`/`caissier` en URL directe d'un écran interdit : redirection `/dashboard`. | 1 test par (rôle, route) de la matrice | B4 FRS-ADM-01 |

## 3. Pilotage (module `22_`)

| ID | Exigence | Critère | Source |
|---|---|---|---|
| FR-PIL-01 | Tableau de bord : 7 sections dans l'ordre (en-tête, filtre période, 8 KPI, courbe + alertes, recensement, ventes + transactions, activités + meilleures ventes). | ordre des sections | F2 |
| FR-PIL-02 | 8 KPI : CA, Trésorerie (531), Dépenses, Résultat net, Soldes restant dus, Stock critique, Effectif cheptel, Cycles couveuse en cours. | KPI non calculable → « — » + « Disponible avec le module Comptabilité », jamais 0 | F2 |
| FR-PIL-03 | La grille KPI passe de 2 à 4 colonnes à 1280 px de FENÊTRE (`xl`), pas à la largeur du conteneur. | test sur `MediaQuery.sizeOf(...).width` au poste ; breakpoint `xl` au web | F2 |
| FR-PIL-04 | Alertes critiques et cloche dérivent d'UNE source (`AlertesViewModel` au poste ; `AlertesElevageService` au web). | une seule liste | F2 |
| FR-PIL-05 | Taux d'éclosion moyen sans éclosion : « — ». | affichage | F2 |
| FR-PIL-06 | Dashboard Élevage : cartes par filière active ; carte d'aperçu (cadenas, « Filière X disponible — non activée pour le moment. », lien « Activer depuis Paramètres → ») pour une filière inactive. | bascule d'une filière | F2, I2 |
| FR-PIL-07 | Bilan économique élevage : revenus = ventes avicoles ; coûts = provende + vétérinaire ; marge « — » tant que les coûts manquent. | pas de marge = revenu seul | F2 |
| FR-PIL-08 | Barre latérale : 8 groupes filtrés par rôle et par module actif ; recherche globale Ctrl+K (anti-rebond 150 ms) filtrée par rôle et module. | aucun résultat vers un écran interdit | F2 |
| FR-PIL-09 | Fenêtre « Rappels du jour » : une fois par session (lancement après PIN, chaque connexion), jamais au déverrouillage, jamais vide, « Ne plus afficher aujourd'hui ». | scénarios du guide bloc 6 | guide bloc 6 |

## 4. Élevage (module `23_`)

| ID | Exigence | Critère | Ancêtre / source |
|---|---|---|---|
| FR-ELV-01 | La fiche propose Achat, Nés, Ventes (POS, lecture seule), Morts et Dons par catégorie, Poids général, Traitement (case + observation). | tous champs présents | FRS-ELV-01 ; F3 |
| FR-ELV-02 | L'effectif est en lecture seule, jamais saisi. | champ désactivé | FRS-ELV-02 |
| FR-ELV-03 | Achats et Nés alimentent la seule catégorie la plus jeune. | RM-ELV-01 : Achat=5 → seule la catégorie jeune +5 | FRS-ELV-03 |
| FR-ELV-04 | La vente est déduite de la seule catégorie commercialisée (Goliathau, Pintadau, Chair, Poulette, Juvénile, Pondeuse) — PAS de « Mature ». | Vente=3 → seule cette catégorie −3 ; Mature inchangée | FRS-ELV-04 ; F3 « Piège majeur » |
| FR-ELV-05 | Chaque catégorie ne perd que SES morts et dons. | mort sur A seule → B, C inchangées | FRS-ELV-05 |
| FR-ELV-06 | Modifier un jour recalcule en cascade les jours suivants. | modifier le jour 5, jours 6 à 10 recalculés | FRS-ELV-06 |
| FR-ELV-07 | Pondeuses : 4 catégories (Poussin Ponte, Croissance, Poulette, Pondeuse). | tableau de rationnement à 4 lignes | FRS-ELV-07 |
| FR-ELV-08 | SRH(J+1) = Stock final(J), jamais TS(J). | RM-ELV-08 | FRS-ELV-08 |
| FR-ELV-09 | Provende totale = somme des catégories (4 pour Pondeuses). | RM-ELV-09 : 32 050 g | FRS-ELV-09 |
| FR-ELV-10 | « Ventes (POS) » = ventes historiques + ventes réelles de la caisse de l'espèce et de la date. | une vente réelle augmente le compteur | FRS-ELV-10 |
| FR-ELV-11 | Mortalité et Dons sont des compteurs `−/+` (jamais négatifs ni non numériques). | bornes à 0 | F3 |
| FR-ELV-12 | Libellés par filière (Achats / Nés (Couveuse) / Nés (Mise bas) / Nés / Nés / Transferts / Achats / Entrées). « couveuse » seulement chez Goliaths et Pintades. | 8 tests du glossaire | F3 |
| FR-ELV-13 | Vue hebdomadaire : semaines calculées sur la longueur du mois ; semaine sans saisie = tirets ; Σ 4 semaines = total du mois. | mois de 28, 29, 30, 31 jours | F3 |
| FR-ELV-14 | Départ par catégorie obligatoire par bande ; somme = effectif total au début du jour de départ. | messages exacts du guide bloc 1 | guide bloc 1 (D4) — Q-ELV-5 |
| FR-ELV-15 | Passage de stade : refusé au-delà de la source après ses autres mouvements. | RM-ELV-04 | guide bloc 1 (D3) |
| FR-ELV-16 | Ventes ventilées par catégorie d'après le produit (`categorie_effectif`) ; refus AVANT écriture : produit sans catégorie, bande sans départ, vente antérieure au départ, catégorie d'une autre famille. | RM-ELV-05 | guide bloc 1 — Q-ELV-7 |
| FR-ELV-17 | Bandes : créer (exercice non clos), modifier, archiver (refusé si effectif vivant > 0), restaurer (refusé si code pris). | messages exacts BS-Q3/Q4/Q7 | guide bloc 12 |
| FR-ELV-18 | Transfert entre bandes de même espèce : fait daté, jamais annulé ; source suffisante CE JOUR et chaque jour suivant. | RM-ELV-06 | guide bloc 12 |
| FR-ELV-19 | Couvoir : création avec calendrier prévisionnel (mirages J+7, J+14 exacts ; éclosion en fenêtre ± 2 j) ; durée Goliath 21 j, Pintade 28 j. | RM-COU-01 | F3 — Q-PIN-4 |
| FR-ELV-20 | Éclosion : `éclos + perdus ≤ chargés`, taux calculés en direct ; option « Recharger la machine » crée un sous-lot dans la MÊME transaction. | RM-COU-02 | F3 |
| FR-ELV-21 | TER = éclos / (chargés − (clairs J7 + gâtés J14)) ; `null` (« — ») avant l'éclosion et si dénominateur nul ; TER moyen pondéré par œufs retenus. | RM-COU-03/04 | F3 |
| FR-ELV-22 | Alertes de mirage : due tant que la saisie manque ; retards les plus anciens d'abord ; capacité d'incubateur = signal de surcharge, jamais blocage. | scénario du guide F3 | F3 |
| FR-ELV-23 | Calendrier de soins : 3 onglets (Registre, Calendrier des doses, Infirmerie), 4 KPI, Nouveau Soin à 9 champs, type d'action fermé (Vaccination, Traitement curatif, Vermifuge, Vitamines). | champs | F3 |
| FR-ELV-24 | Décès d'infirmerie : choix de catégorie (ou « Déjà saisie sur la fiche — ne rien ajouter ») obligatoire ; report via le MÊME point d'écriture que la fiche (cascade). | bouton inactif sans réponse ; vente du POS préservée | F3 |
| FR-ELV-25 | Prophylaxie par jour de cycle : traitement dû si `jour_debut ≤ J ≤ jour_fin` ; bande en reproduction sans saillie → « indéterminée ». | RM-PRO-01 | guide bloc 6 |
| FR-ELV-26 | Soin planifié → « à venir » dès N jours, « en retard » au-delà de la date ; N = `rappel_soins_jours` (0 à 30, défaut 3). | RM-PRO-02 | guide bloc 6 |
| FR-ELV-27 | Infirmerie sans date prévue → aucun rappel ; délai d'attente listé avec date de fin ; produits d'un animal sous délai non vendables (bannière). | scénario | F3 |
| FR-ELV-28 | Paramètres Élevage : 4 onglets ; barème modifié → recalcul de la provende de la fiche ; barème supprimé → retombe sur la ration de référence, jamais 0 ; préfixe vide refusé. | tests de F3 | F3 |
| FR-ELV-29 | Rationnement : clé par libellé en ÉGALITÉ stricte normalisée (minuscules, sans accents, tranche d'âge ignorée), jamais par sous-chaîne. | RM-ELV-09 | guide bloc 5 |
| FR-ELV-30 | Alerte d'autonomie de provende : jamais bloquante ; une par objet et par jour. | RM-ELV-10 | guide bloc 5 — Q-ALR-1 |
| FR-ELV-31 | Pisciculture : fiche (Alevin, Juvénile, Mature) avec libellés « Achats » / « Nés » ; biomasse, bassin, vente au poids : **À DÉFINIR AVEC LE CLIENT**. | `15_` §7.1 | Q-PIS-1…9 |
| FR-ELV-32 | Pintades : mêmes mécanismes que Goliaths ; stades/durées/rations propres **À DÉFINIR**. | `15_` §7.2 | Q-PIN-1…4 |

## 5. Ventes, clients, facturation (module `24_`)

| ID | Exigence | Critère | Ancêtre / source |
|---|---|---|---|
| FR-VTE-01 | Le POS affiche le stock en temps réel ; badge rouge si `stock ≤ seuil` ; carte grisée à stock 0. | après vente, stock affiché à jour | FRS-VTE-01 ; H1 |
| FR-VTE-02 | Quantité > stock refusée : « Stock insuffisant (X disponible). » | produit à 2, 3e refusée | FRS-VTE-02 |
| FR-VTE-03 | Validation = une transaction : vente + lignes + décrément stock + compteur de la fiche (si animal). | test d'intégration sur la BASE (pas sur la valeur retournée) : ligne vers produit inexistant → rien écrit, stock du produit valide inchangé | FRS-VTE-03 ; F4 |
| FR-VTE-04 | La remise est respectée : total = Σ lignes − remise, jamais recalculé. | RM-VTE-01 | FRS-VTE-04 |
| FR-VTE-05 | Annulation (motif parmi Erreur de saisie / Client non honoré / Produit indisponible / Autre) : stock restitué, compteur de fiche défait. | stock et fiche rétablis ; la vente reste dans l'historique zootechnique du jour | FRS-VTE-05 ; B6 BR-VTE-004 |
| FR-VTE-06 | Historique filtrable par statut (Payée / Avance / Annulée), mode, client ; clic = panneau latéral avec « Imprimer la facture ». | 3 filtres combinés | FRS-VTE-06 |
| FR-VTE-07 | Chaque vente validée donne une facture imprimable (client, date, lignes, total). | contenu contre données | FRS-VTE-07 |
| FR-VTE-08 | Règlement comptant : `paye = total` (pas le montant remis) ; Avance : `paye` = montant reçu. | RM-VTE-02 | F4 |
| FR-VTE-09 | Solde client = Σ (total − paye) des ventes Avance non annulées, recalculé à chaque lecture. | annuler une vente à crédit → solde 0 | F4 |
| FR-VTE-10 | Paiement sur créance : `paye += montant` ; si `paye = total`, statut Payée. | RM-VTE-03 | F4 |
| FR-VTE-11 | Échéance : champ « Payable le » seulement en Avance ; délai par défaut paramétrable (vide = aucune date) ; sans échéance → « Sans échéance », jamais « En retard ». | RM-VTE-04 | F4 ; Q-VTE-1 |
| FR-VTE-12 | Clients : 4 KPI (Clients enregistrés, Solde total restant dû, Soldes anciens > 10 j, Événements CRM 7 j), 3 tableaux ; « Marquer contacté » horodate. | pas de faux envoi | F4 |
| FR-VTE-13 | Catalogue : SKU `PRD-NNN` jamais réécrit ; produit vendu non supprimable (message explicatif) ; coût de revient ≤ tarif, ≥ 0. | RM-STK-04 | F4 |
| FR-VTE-14 | Devis : client, objet, montant > 0, validité entière ≥ 1 (défaut 15) ; cycle brouillon → envoyé → accepté/refusé. | validations | H1 ; `docs/prd/devis-poste.md` |
| FR-VTE-15 | Retours et avoirs : quantité ≤ vendu − déjà retourné ; montant ≤ ligne − déjà crédité ; tout jugé AVANT d'écrire (exercice clos, plan incomplet) ; une seule transaction. | RM-VTE-07 | guide / AgriERP `AvoirClientService` — à valider |
| FR-VTE-16 | Facture simple jamais transmise ; normalisée : nom du client obligatoire, IFU vide ou 13 chiffres, AIB 5 % défaut / 1 % / N/A ; une normalisée n'est plus modifiable ni annulable : « Facture normalisée : corrigez-la par un avoir. » | scénarios bloc 19 | guide bloc 19 |
| FR-VTE-17 | Avoir `FA-AAAA-NNN` désigne la facture d'origine (`origineRef`), ne la modifie jamais. | contre-passation | `facturation_mecef_tables.dart` |
| FR-VTE-18 | Lettre de relance PDF ; sans échéance : « Rappel de Solde ». | contenu | F4, F7 |

## 6. Stocks et achats (module `25_`)

| ID | Exigence | Critère | Source |
|---|---|---|---|
| FR-STK-01 | Produits vendables et intrants sont deux entités distinctes. | deux tables, deux écrans | FRS-STK-01 |
| FR-STK-02 | Stock ≤ seuil → badge « Critique ». | stock = seuil | FRS-STK-02 |
| FR-STK-03 | Toute suppression passe par modale de confirmation avec avertissement d'irréversibilité ; « supprimer » archive (corbeille). | aucun chemin direct | FRS-STK-03 ; F8 |
| FR-STK-04 | Ajustement d'inventaire : stock physique remplace le théorique, écart signé journalisé dans `MOUVEMENTS_INTRANT`. | rouvrir l'écran : valeur persistée | FRS-STK-04 ; F5 |
| FR-STK-05 | Gestion des stocks : 2 tableaux (articles, journal des mouvements), 4 KPI dont « Mouvements (7j) ». | structure | F5 |
| FR-STK-06 | Réception d'une commande : stock +, PMP recalculé, mouvement écrit. | RM-STK-01 : 682 / 68 200 | F5 |
| FR-STK-07 | Fabrication de provende : atomique, composition par défaut 25/10/5/3/2 kg (Maïs/Soja/Coquille/Poudre de poisson/Tourteau de palmiste), alerte dès la saisie, référence commune `FAB-AAAA-NNNN`, quantités signées négatives. | un 3e intrant en dépassement bloque les cinq | F5 |
| FR-STK-08 | Achats : 3 KPI, statuts Commandé/Livré/Partiel ; Fournisseurs : 2 tableaux et 4 KPI miroir des clients. | structure | F5 |
| FR-STK-09 | Valorisation : intrants au PMP, produits finis au coût de revient ; sans coût = « Non valorisé », hors totaux. | RM-STK-03 | F4 |
| FR-STK-10 | Dépense : un en-tête + N lignes, total = Σ lignes, une écriture. | `docs/prd/depenses-multilignes.md` | AgriERP |
| FR-STK-11 | Stock négatif après synchronisation d'une vente hors ligne : signalé (notification), jamais refusé. | notification | guide bloc 18 |

## 7. Comptabilité (module `26_`)

| ID | Exigence | Critère | Ancêtre / source |
|---|---|---|---|
| FR-CPT-01 | Clôture annuelle : verrouille toutes les écritures de l'exercice. | modifier → rejet | FRS-CPT-01 |
| FR-CPT-02 | Clôture : génère le report à nouveau sur N+1 pour chaque compte de bilan à solde non nul, même sens. | RM-CPT-06 | FRS-CPT-02 |
| FR-CPT-03 | Toute vente, achat, dépense génère ses écritures équilibrées. | vente : D Caisse / C Ventes montants égaux | FRS-CPT-03 |
| FR-CPT-04 | Balance : Σ soldes finaux D = Σ soldes finaux C (tolérance 0,01 F) ; écart affiché en rouge ; clôture refusée si ≠ 0. | RM-CPT-03 | B6 BR-CPT-004 |
| FR-CPT-05 | Résultat net : UNE source pour Compte de résultat, compte 13 du bilan, point de départ du TAFIRE. | égalité stricte | B6 BR-CPT-005 |
| FR-CPT-06 | Clôture mensuelle : verrou par mois ; déblocage par admin seul, journalisé ; pas de report à nouveau. | RM-CPT-05 | B6 BR-CPT-006 |
| FR-CPT-07 | Grand Livre : solde progressif, sens selon la nature du compte. | RM-CPT-02 | F6 §2 |
| FR-CPT-08 | Écriture manuelle : équilibrée, débit ≠ crédit (2 lignes), exercice ouvert, mois non clôturé ; numéro `OD-AAAA-NNNN` serveur ; archivage = contre-passation. | RM-CPT-04 | guide bloc 13c — Q-CPT-3 |
| FR-CPT-09 | Plan comptable : créer, modifier (numéro immuable), archiver ; archivage refusé si une écriture cite le compte. | refus | guide bloc 13b ; F6 §10.16 |
| FR-CPT-10 | Exercice : sélecteur global, statuts Ouvert / Provisoire / Clôturé ; une saisie appartient à l'exercice de SA date ; clôturé = lecture seule avec bandeau. | RM-CPT-07 | guide bloc 4 |
| FR-CPT-11 | Clôture gardée : échéance passée, étapes 1 et 2 faites, N-1 clos, à-nouveau équilibré ; confirmation textuelle « CLOTURER ». | refus avec motif | J1 ; guide bloc 11 |
| FR-CPT-12 | Immobilisations : registre, acquisition, sortie (jamais suppression), dotation datée idempotente. | **À DÉFINIR** méthode et durées (Q-CPT-4) | guide bloc 13e |
| FR-CPT-13 | États : Bilan SYSCOHADA (actif, passif), compte de résultat en cascade, TAFIRE, 5 notes annexes. | Actif = Passif | F6 §4 |
| FR-CPT-14 | TVA activable : inactive → aucune ligne 443/445, montants HT ; active → TTC. | RM-TVA-01 | AgriERP `TvaSettingService` — Q-TVA-1 |
| FR-CPT-15 | Déclaration de TVA : seules les ventes réellement transmises (normalisées) sont retenues. | à confirmer avec le cabinet | AgriERP — Q-TVA-1 |
| FR-CPT-16 | Comptabilité analytique : ventilation par axe (`axeAnalytique`) ; charges communes non réparties sans clé validée. | somme des axes + non affecté = total | F6 §7, v19 |

## 8. Rapports, exports, import (module `28_`)

| ID | Exigence | Critère | Source |
|---|---|---|---|
| FR-RPT-01 | 6 onglets (Recettes et Dépenses, Trésorerie, Créances, Dettes, Élevage, Stocks), bouton « Exporter PDF » de l'onglet actif. | PDF = onglet à l'écran | F7 |
| FR-RPT-02 | Seules les classes 6 et 7 comptent dans recettes/dépenses ; Résultat net identique à la comptabilité. | égalité stricte | F7 constat 2 |
| FR-RPT-03 | Rapport Élevage en 3 sous-tableaux (recensement hebdomadaire, mouvements/traitements/ventes, couvoir). | structure | F7 |
| FR-RPT-04 | Rapport de stocks : 3 KPI calculés (jamais figés). | recalcul | F7 |
| FR-RPT-05 | États opérationnels J2 : récapitulatif mensuel par espèce, bilan technico-économique, état des stocks, historique des ventes, analyse clients/créances. | filtres plage de dates, filière, exercice | J2 |
| FR-RPT-06 | Export xlsx unique (`ExportTableur`) ; PDF unique (`DocumentOfficiel`). | un seul générateur | guide bloc 7 |
| FR-IMP-01 | Import en masse par xlsx avec modèle à télécharger (stocks d'abord). | **À CONCEVOIR** : tests du bloc 21 | guide bloc 21 — Q-IMP-1 |

## 9. Paramètres et administration (module `29_`)

| ID | Exigence | Critère | Ancêtre / source |
|---|---|---|---|
| FR-ADM-01 | Un animalier n'accède pas à `/comptabilite`. | redirection | FRS-ADM-01 |
| FR-ADM-02 | Désactiver une filière retire son entrée de la navigation, bloque l'URL directe, conserve les données. | menu + base | FRS-ADM-02 ; I2 |
| FR-ADM-03 | Goliaths et Pintades : toujours actives, affichées `disabled`, jamais basculables. | no-op | I2 |
| FR-ADM-04 | MeCeF activable seulement si IFU (chiffres uniquement) et RCCM renseignés. | refus avec message | B6 BR-ADM-004 |
| FR-ADM-05 | Utilisateurs : liste, créer (nom, identifiant, rôle, mot de passe ≥ 8 + confirmation), modifier, archiver, réactiver ; le dernier admin ne s'archive pas. | un compte créé peut ouvrir une session | F8 |
| FR-ADM-06 | Modes de paiement : Espèces et Mobile Money toujours actifs ; Conditions de paiement (délai par défaut). | non désactivables | F8 onglet 4 |
| FR-ADM-07 | Sauvegarde : générer, exporter, lister, supprimer, restaurer (différée, 4 contrôles). | base précédente conservée | F8 |
| FR-ADM-08 | Corbeille : archiver (qui gère l'écran), restaurer (tous sauf utilisateur et écriture = admin), purger (admin seul) ; restauration refusée si référence réoccupée. | colonne « Archivé par » remplie | F8 |
| FR-ADM-09 | Remise à zéro : double verrou, aperçu chiffré, audit conservé. | RM-ADM-01 | F8 |
| FR-ADM-10 | Logo/favicon : type par signature, ≤ 2 Mo, nom UUID. | refus | I3 §2 |
| FR-ADM-11 | SMTP et e-MECeF : réglage avec « Tester la configuration » (un `GET /info/status`, jamais `POST /invoice`) ; jeton masqué « •••• », « Remplacer », « Effacer ». | jamais servi au poste | guide bloc 19 |
| FR-ADM-12 | Toast en haut à droite, empilés (4 max), croix de fermeture. | rendu | F8 |

## 10. Synchronisation, MeCeF, PWA, alertes (transverses)

| ID | Exigence | Critère | Source |
|---|---|---|---|
| FR-SYN-01 | Appairage : 1re connexion du poste en ligne ; jeton nommé ; PIN local ; révocation → 401 → reconnexion. | scénarios bloc 15 | guide bloc 15 |
| FR-SYN-02 | Pull puis push ; jamais deux synchronisations simultanées. | 2e demande reçoit la tentative en cours | guide bloc 16 |
| FR-SYN-03 | Réponse perdue après traitement : le renvoi de l'UUID ne crée rien. | idempotence | guide bloc 16 |
| FR-SYN-04 | Un refus devient `conflict` avec motif français ; jamais d'échec silencieux. | statut + motif | guide bloc 16 |
| FR-SYN-05 | Modale de synchronisation dans la barre du haut (web ET poste) : états, compteur « à envoyer », demande de synchronisation du web, renvoi complet. | libellés lus dans la vue web | guide bloc 17 |
| FR-NOT-01 | Cloche : le web lit les notifications du rôle ; le poste ne crée AUCUNE notification (copie du serveur) ; « marquer lue » exige le réseau. | refus hors ligne avec une phrase | guide bloc 18 |
| FR-NOT-02 | Tâches serveur : prophylaxie du jour 06:00, alertes 06:05 (fuseau Africa/Porto-Novo), une notification par objet et par jour. | relancer ne réempile rien | guide bloc 18 |
| FR-MEC-01 | e-MECeF côté serveur : une normalisée n'est jamais retransmise ; états En attente / Normalisée / Refusée / Expirée. | `uid` gardé | guide bloc 19 |
| FR-MEC-02 | Montants entiers, groupes de taxe A (0 %) / B (18 %), tout autre taux refusé avec motif ; remise répartie au plus fort reste. | RM-MEC-01 | guide bloc 19 |
| FR-PWA-01 | Installable ; service worker étroit ; page d'attente hors ligne. | aucun HTML authentifié en cache | guide bloc 20 |

## 11. Questions ouvertes

Reprises de `10_BRS_BUSINESS_REQUIREMENTS.md` §6 : Q-ELV-5/7, Q-PIS-1…9, Q-PIN-1…4, Q-CPT-3/4, Q-TVA-1, Q-VTE-1, Q-IMP-1, Q-ALR-1. Aucune nouvelle question propre au FRS.
