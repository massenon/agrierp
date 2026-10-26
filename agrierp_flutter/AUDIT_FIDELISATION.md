# AUDIT DE FIDÉLISATION — poste Flutter vs prototype HTML

Date de l'audit : 3 oct. 2026 · Périmètre : 96 pages du prototype
(`C:\Projects\agrierp_laravel\prototype_html`, hors `index`, `landing-page`,
`welcome`, `logout`, `comptabilite-hub_1`, `fiche-volailles-pondeuses_old`).

> Ce fichier est un document d'audit et un plan. Il ne remplace pas le journal
> `README_SPRINT0.md` : chaque ticket du plan s'y ajoute à son tour, dans les
> DEUX copies (hachées avant ajout, jamais comparées à l'œil).
> ⚠️ Le dépôt n'est pas versionné (pas de git) : ce fichier est la seule trace.

> **MISE À JOUR 8 oct. 2026 — phases 0 et 1 exécutées.** L'annexe A ci-dessous est
> **remplacée** par `RAPPORT_FIDELITE_2.md` (reproductible : `py outils/audit_fidelite.py`).
> Nouveaux rapports : `RAPPORT_EMPLACEMENT.md` (1A), `RAPPORT_CHROME.md` (1B/1C),
> `RAPPORT_JETONS.md` et `RAPPORT_VISUEL.md` (1D). Outils : `outils/association_ecrans.py`,
> `audit_fidelite.py`, `emplacement.py`, `audit_chrome.py`, `audit_jetons.py`, `captures.py` ;
> bancs `test/rendu_onglets_test.dart` et `test/capture_ecrans_test.dart` (sur demande : `AUDIT_RENDU=1`).

---

## 1. Résultat de l'audit n° 1 (présence des libellés)

**Méthode.** Pour chaque page : titres (`h2`/`h3`), boutons, en-têtes de
colonnes, étiquettes de champs, libellés de cartes d'indicateur, onglets et
tableaux sont extraits du HTML (scripts et chrome retirés, via
`outils/inventaire.py` et `outils/structure.py`), puis cherchés dans les
**littéraux de chaîne** du code Dart (commentaires exclus, accents ignorés —
arbitrage d'accentuation déjà ouvert au ticket F0.51). Script :
`outils/audit_fidelite.py`.

| Élément | Retrouvés | Taux |
|---|---|---|
| Onglets | 47 / 47 | 100 % |
| Colonnes de tableau | 538 / 623 | 86 % |
| Cartes (libellé) | 134 / 215 | 62 % |
| Tableaux (ordre des colonnes) | 63 / 107 | 59 % |
| Libellés de champs | 237 / 435 | 55 % |
| Titres | 120 / 317 | 38 % |
| Boutons | 212 / 570 | 37 % |
| **Global** | **1 351 / 2 314** | **58,4 %** |

Seules **16 pages sur 96** sont retrouvées à 100 %.

**Présence d'écran (comptage de pages).** 77 des 96 pages ont un écran Flutter ;
12 de plus sont absorbées dans un écran existant (onglet ou section) ; 3 sont
volontairement laissées au web (`etats-financiers`, `declaration-tva`,
`rapprochement-bancaire`) ; **4 sont absentes** : `mon-profil`, `notifications`,
`aide-a-propos`, `contact-editeur`.

⚠️ **Lecture correcte.** Avoir un écran ne veut pas dire être fidèle : le taux de
présence d'écran (~93-96 %) et le taux de fidélité de contenu (58 %) mesurent deux
choses différentes. Les tests de fidélité existants sont verts parce qu'ils
s'appuient sur des listes d'exemptions par page ; un test vert ne prouve pas
qu'un écran est complet.

### Limites de l'audit n° 1 (à lever par le plan ci-dessous)

- **Présence, pas emplacement** : il vérifie qu'un libellé existe dans les
  fichiers de l'écran. Il ne vérifie pas qu'il est dans le bon onglet, la bonne
  grille, la bonne carte ni au bon endroit.
- **33 pages sans écran identifié** : elles sont comparées à l'ensemble du code,
  ce qui est plus généreux. Certaines, comme les 5 fiches d'espèce,
  `ventes-devis` et `pos-interface`, ont un écran, mais il n'était pas associé.
- **Non mesurés** : la barre latérale, la barre supérieure, l'alignement, l'ordre
  des cartes et la cohérence visuelle.
- **Faux négatifs possibles** : un libellé reformulé, ou construit
  dynamiquement, compte comme absent.

---

## 2. Écarts prioritaires relevés

| Gravité | Pages | Constat |
|---|---|---|
| Écran inexistant | `aide-a-propos`, `contact-editeur`, `mon-profil` | aucun écran dédié |
| Écran inexistant | `notifications` (0/12) | seule la cloche de la barre supérieure existe |
| Contenu quasi absent | `bilan-technico-economique` (0/7) | onglet présent, contenu non conforme |
| Contenu très partiel | `rh-attestations` (3/19), `animal-details` (8/49), `tableau-stocks`, `ajustements-stock`, `mouvement-stock` (20-32 %) | l'écran existe, pas ses sections |
| Hors poste par décision | `etats-financiers`, `declaration-tva`, `rapprochement-bancaire`, `cloture-exercice`, `comptabilite-analytique` | motifs affichés dans le hub ; arbitrage client à confirmer |
| À associer puis mesurer | 33 pages sans écran identifié (fiches d'espèce, `ventes-devis`, `pos-interface`, `devis`, `gestion-bandes`, `transformation`, `retours-avoirs`, `vms-suivi`, …) | score non fiable tant que l'écran n'est pas associé |

Le détail page par page figure en **annexe A**.

---

## 3. PLAN DE FINALISATION — implémentation et fidélisation complètes

Règles du projet qui s'appliquent à CHAQUE phase (CLAUDE.md) :
- **Un ticket = une session.** Annoncer le plan avant d'écrire du code ; ne jamais
  convertir plusieurs écrans d'un coup sans vérification intermédiaire.
- Hiérarchie des sources, jamais inversée : (1) prototype HTML = visuel,
  structure, comportement ; (2) implémentation Laravel = règles métier et calculs ;
  (3) base de connaissances = le reste. Ce qui n'est dans aucun des trois est
  signalé, jamais inventé.
- Donnée absente = `'—'` + légende, jamais `0`.
- « Fait » = `flutter analyze` propre, `flutter test` vert, ticket ajouté aux DEUX
  copies de `README_SPRINT0.md` avec ses constats RÉELS, y compris ce qui n'a pas
  été vérifié.
- Écrire le test qui aurait attrapé le défaut.
- Contradictions connues (nombre de rôles, comptage d'écrans, inconnue RBAC) :
  les signaler, ne pas les trancher.

### Phase 0 — Fiabiliser l'instrument de mesure

Objectif : un taux fiable avant de corriger quoi que ce soit.

1. **Associer les 33 pages sans écran** à leur(s) fichier(s) Dart. Source de
   vérité : l'enum `EcranPoste` (`lib/core/auth/permissions_poste.dart`) et les
   `_ongletX` des hubs. Compléter la table `EXTRA` de
   `outils/audit_fidelite.py` (ou, mieux, la déduire de l'enum).
2. **Lister les exemptions** de `test/fidelite_libelles_test.dart`
   (`exemptions`, `exemptionsParPage`) : pour chacune, classer
   *(a) divergence assumée et motivée*, *(b) fonctionnalité non portée*,
   *(c) oubli*. Seules (a) restent des exemptions ; (b) devient un ticket ;
   (c) est corrigée.
3. **Traiter les faux négatifs** : repérer les libellés construits
   dynamiquement ou reformulés, et les ajouter en équivalences documentées plutôt
   que de les laisser faire baisser le taux.
4. **Séparer trois taux** dans le rapport : *fidélité stricte* (libellé trouvé,
   sans exemption), *fidélité assumée* (exemptions motivées comptées) et
   *non portée* (fonctionnalité absente).
5. Produire un second rapport et ne garder que celui-là comme référence.

Critère de sortie : 96 pages associées, chaque absence classée (a)/(b)/(c).

### Phase 1 — Mesurer ce que l'audit n° 1 ne voyait pas

#### 1A. Emplacement (onglet / grille / carte / section)
Objectif : « le bon libellé au bon endroit ».
- Étendre `outils/structure.py` pour émettre, **par panneau d'onglet** : les
  titres de section, les cartes (ordre + libellé de chacune, pas seulement leur
  nombre — faiblesse n° 2 du CLAUDE.md), les grilles (nombre de colonnes selon
  `grid-cols-*`), les tableaux (ordre des `<th>`), les boutons par barre d'actions.
- Côté Flutter, ne pas relire le source : **rendre l'écran en test de widget** et
  relever les widgets par onglet (clés `Key`, `CarteKpi`, `ModaleAgri`,
  `DataTable`), puis comparer à l'extraction. Un test par page.
- Vérifier aussi l'**ordre** des cartes et des sections, pas seulement leur
  présence (un ordre inversé passe aujourd'hui sans bruit).
- Ajouter un contrôle des libellés de cartes (`<span>` dans une carte
  `border-l-4 border-l-<couleur>`).

#### 1B. Barre latérale (`assets/js/sidebar.js` vs `_BarreLaterale.arborescence`)
- Comparer, groupe par groupe et **dans l'ordre** : intitulé de chaque groupe,
  intitulé de chaque entrée, icône, sous-entrées, état actif, comportement
  repliable, largeur, couleur de fond et de survol (jetons `AgriTokens`).
- Vérifier l'entrée → écran (`EcranPoste`), et le masquage par rôle
  (`RBAC_PAGE_MAP`) pour les 4 rôles du mapping.
- ⚠️ `brand-maize` n'existe pas dans le config Tailwind : utiliser
  `accentYellow` (#FFD55F).

#### 1C. Barre supérieure (`common.js`, en-tête partagé)
- Éléments : titre de page / fil d'Ariane, recherche, cloche et son menu de
  notifications, profil, déconnexion, boutons minimiser/fermer (fenêtre sans
  cadre). Ordre, espacement, icônes, libellés.
- Exclusions assumées : le sélecteur de rôle de démonstration,
  `testerPopupAlertesStock`, `testerPopupProphylaxie`.

#### 1D. Alignement et cohérence visuelle
- **Captures comparées** : prototype ouvert dans Chrome, poste Flutter lancé en
  1280×720 et 1920×1080, même état de données (données de démonstration
  figées). Comparer écran par écran, onglet par onglet.
- Critères mesurables : espacements (`AgriSpacing`), tailles de texte
  (`AgriTypography.xs` = 13,6 px, pas 12), rayons, ombres, couleurs (14 jetons,
  pas plus), bascule responsive à 640 px, largeur utile ~980 px dans une fenêtre
  de 1280 px, hauteur de ligne de tableau, empilement mobile avec `data-label`.
- Tests de gabarit : `golden` Flutter pour les écrans stables, et contrôle de
  source par `conformite_portage_test.dart` pour les règles qui ne se voient pas
  au rendu (`AgriBreakpoints`, `CarteKpi`, `ModaleAgri`).
- Contrôle visuel manuel final sur chaque écran par une personne.

Critère de sortie 1A-1D : un rapport par écran avec écarts classés
**bloquant / majeur / mineur**, chacun avec la ligne du prototype et le fichier
Dart concerné.

### Phase 2 — Combler les écrans absents (4 tickets)

Un ticket chacun, dans cet ordre :
1. `mon-profil` — profil, changement de mot de passe (3 champs), journal d'audit
   des 10 dernières actions (Date/Heure, Action, Module, IP).
2. `notifications` — Centre de Notifications : résumé des alertes, gravité,
   liste ; brancher la cloche de la barre supérieure.
3. `aide-a-propos` — modules du logiciel, foire aux questions, mentions des
   trois structures (PAEB, Cabinet FAGUEZ SARL, Dr MASSENON Rhodes).
4. `contact-editeur` — formulaire, signaler un bug (⚠️ canal d'envoi hors ligne
   à définir : file d'attente de synchronisation, ou message « à envoyer en
   ligne »).

Pour chacun : RBAC (entrée dans `EcranPoste`, **pas d'invention** : si la page est
absente de `RBAC_PAGE_MAP`, le dire et demander l'arbitrage), carte d'indicateurs
via `test/cartes_attendues.dart`, fixtures via `outils/fixtures.py`, repository
séparé de l'écran.

### Phase 3 — Compléter les écrans partiels (par ordre de gravité)

Chaque ligne est un ticket distinct, avec avant/après du score de l'audit :

1. `bilan-technico-economique` (0/7) — onglet du dashboard élevage ; règles
   Laravel pour les coûts et revenus par lot.
2. `rh-attestations` (3/19) — modèles, génération, personnalisation ; dépend de
   la chaîne PDF (`ExportOfficiel`). ⚠️ Aucune table d'attestations ne descend au
   poste : décider (synchroniser la table ou garder le tiret `'—'`).
3. `animal-details` (8/49) — fiche sujet : identification, QR code, historique.
4. Stocks : ~~`tableau-stocks`, `mouvement-stock`, `ajustements-stock`~~ —
   **RETIRÉS DU PLAN (ticket F0.66) : code mort**, aucun lien entrant, fusionnés dans
   `gestion-stocks.html` que le poste porte déjà (`outils/pages_orphelines.py`). Reste
   `ajouter-produit`. ⚠️ Les ajustements sont rejoués par le serveur : jamais
   appliqués tels quels côté poste.
   (Même correction pour `rapport-recettes` et `rapport-depenses`, orphelins,
   comptés à tort dans `rapports-exports`.)
5. ~~`prevision-croissance`, `analyse-croissance`~~ — **FAITS (ticket F0.68)**.
   `suivi-sanitaire-analyse` **BLOQUÉ** : maladies, historique annuel et alertes du jour
   n'existent pas côté serveur — décision client (table des maladies côté Laravel ?).
6. `profile-fournisseur`, `fiches-fournisseurs`, `dettes-fournisseurs`.
   **1re partie FAITE (ticket F0.69)** : le règlement fournisseur s'enregistre au poste
   (en attente, le serveur impute/décaisse/comptabilise). Reste : écran
   `profile-fournisseur` **FAIT (ticket F0.70)**, fiche fournisseur créer/modifier/archiver
   **FAITE (ticket F0.71)**. **ITEM 6 TERMINÉ**, sauf l'import de fournisseurs : Laravel n'en
   a aucun — décision client.
7. `liste-clients`, `historique-avances`, `liste-achats`, `ajouter-fournisseur`.
   **EN COURS.** `ajouter-fournisseur` : fait (F0.71). `liste-clients` : **FAITE (ticket
   F0.72)** — fiche écrite au poste, sélection / archivage en masse, filtres ; import, export
   et PDF non portés. Reste : `historique-avances` (nouvelle avance, imputation d'un acompte :
   écritures comptables à rejouer côté serveur) et `liste-achats` (remboursement, retour
   fournisseur, annulation).
8. Documents : `documents-administratifs`, `archivage-documents`,
   `gestion-courriers`. ⚠️ Divergence ouverte : cartes comptant des documents
   ÉMIS là où la maquette compte des MODÈLES disponibles → client.
9. Comptabilité : `plan-comptable`, `journal-comptable`, `grand-livre`,
   `balance-generale`. Rappel : toute opération financière produit son écriture ;
   la trésorerie vit en deux livres qui doivent concorder.
10. Reste des pages sous 60 %, dans l'ordre croissant du rapport (annexe A).

Règle de sortie d'un ticket : le score de la page monte, les exemptions
retirées sont retirées du test, **aucune** exemption n'est ajoutée sans motif écrit.

### Phase 4 — Pages laissées au web : décision client

À soumettre au client, une page à la fois, avec la raison technique :
`etats-financiers`, `declaration-tva`, `rapprochement-bancaire`,
`cloture-exercice`, `comptabilite-analytique`.
- Si **maintenues au web** : le motif affiché doit rester juste et daté
  (« une limitation affichée est une phrase DATÉE »).
- Si **à porter** : un ticket par page, règles SYSCOHADA lues dans le code
  Laravel, jamais recomposées au poste.

### Phase 5 — Arbitrages client en attente (ne pas trancher seul)

1. 7 rôles (CDC) / 6 (enum) / 5 (matrice) / 4 (`RBAC_PAGE_MAP`) ; rôle inconnu
   non restreint.
2. Six écrans dans la maquette mais dans aucune liste RBAC (`suivi-reproduction`,
   `parametres-elevage`, `saisie-depenses`, `gestion-stocks`, `achats-commandes`,
   `fournisseurs`).
3. `comptabilite-hub.html` absent des listes, y compris celle du comptable.
4. Cartes de `documents-administratifs` (émis vs modèles).
5. Nombre d'écrans cité : 94, 97 ou 99 selon les documents.

### Phase 6 — Garde-fous permanents

- Intégrer `outils/audit_fidelite.py` à la routine de fin de sprint ; un taux
  par page, publié dans le ticket.
- Test qui échoue si une page du prototype n'est ni associée à un écran, ni
  classée « laissée au web », ni « hors périmètre ».
- Test d'ordre des cartes et des sections (Phase 1A) et de la barre latérale
  (Phase 1B) ; reprise du hash des deux copies de `README_SPRINT0.md`.
- Relecture de **tous** les marqueurs « limitation » à chaque fin de sprint.

### Jalons et critères d'acceptation globaux

| Jalon | Critère |
|---|---|
| J0 (Phase 0) | 96 pages associées ; chaque exemption classée (a)/(b)/(c) |
| J1 (Phase 1) | rapports emplacement + barre latérale + barre supérieure + visuel, écarts classés |
| J2 (Phase 2) | 4 écrans absents livrés, `analyze` propre, tests verts |
| J3 (Phase 3) | toute page ≥ 90 % en fidélité stricte, ou écart motivé et validé |
| J4 (Phases 4-5) | décisions client consignées |
| Final | fidélité stricte ≥ 95 % ; sidebar et topbar identiques au prototype ; 0 écart « bloquant » ; contrôle visuel signé écran par écran |

### Ce qui reste à ne PAS considérer comme vérifié, même à la fin

Les chiffres métier (soldes, totaux de stock, effectifs) ne se vérifient pas en
lisant : écrire un recalcul indépendant et le comparer à l'affichage. Les tests
d'intégration avec le serveur (`sync_reel_test.dart`) sont ignorés sans
`php artisan serve --port=8002`.

---

## Annexe A — Rapport page par page (audit n° 1)

Format : `page — retrouvés/total (%) — écran associé`, puis les éléments absents
(12 premiers par catégorie).



## achats-commandes.html — 6/6 (100 %) — écran: AUCUN

## administration.html — 6/6 (100 %) — écran: AUCUN

## aide-a-propos.html — 0/10 (0 %) — écran: AUCUN
- **titres** 0/3 — absents: Aide & À Propos · Modules du Logiciel · Foire Aux Questions
- **boutons** 0/7 — absents: Comment enregistrer une nouvelle vente ? · Comment créer une nouvelle bande d'élevage ? · Comment fonctionne l'alerte de stock d'aliment ? · Comment générer une attestation de travail ou de stage ? · Comment activer ou désactiver un module (ex. Escargots) ? · Comment clôturer un exercice comptable ? · Comment masquer la barre latérale pour plus d'espace de travail ?

## ajouter-fournisseur.html — 10/23 (43 %) — écran: lib/features/achats/fournisseurs_screen.dart
- **titres** 1/4 — absents: Nouveau Fournisseur · Modifier — Fournisseurs — Ajout · Confirmer l'archivage
- **boutons** 0/7 — absents: Nouveau Fournisseur · Indicateurs de performance · + Nouveau Fournisseur · Annuler · Enregistrer · Mettre à jour · Archiver
- **etiquettes** 1/4 — absents: Nom du fournisseur * · Téléphone * · Adresse

## ajouter-produit.html — 7/23 (30 %) — écran: lib/features/stocks/catalogue_produits_screen.dart, lib/features/stocks/gestion_stocks_screen.dart
- **titres** 1/4 — absents: Ajouter un Produit · Modifier — Ajouter un Produit · Confirmer l'archivage
- **boutons** 1/7 — absents: Indicateurs de performance · + Nouveau Produit · Annuler · Enregistrer · Mettre à jour · Archiver
- **colonnes** 4/5 — absents: Prix Unitaire
- **etiquettes** 1/4 — absents: Nom du produit * · Prix unitaire (FCFA) * · Description
- **cartes** 0/2 — absents: Références catalogue · Nouveaux (mois)
- **tableaux_manquants** 0/1 — absents: ['Produit', 'Catégorie', 'Prix Unitaire', 'Statut']

## ajustements-stock.html — 5/25 (20 %) — écran: lib/features/stocks/gestion_stocks_screen.dart
- **titres** 0/4 — absents: Ajustements de Stock · Nouvel Ajustement · Modifier — Ajustements de Stock · Confirmer l'archivage
- **boutons** 0/7 — absents: Nouvel Ajustement · Indicateurs de performance · + Nouvel Ajustement · Annuler · Enregistrer · Mettre à jour · Archiver
- **colonnes** 4/6 — absents: Qté Système · Qté Physique
- **etiquettes** 1/4 — absents: Produit concerné * · Quantité système * · Quantité physique constatée *
- **cartes** 0/3 — absents: Ajustements (mois) · Pertes constatées · Gains d'inventaire
- **tableaux_manquants** 0/1 — absents: ['Date', 'Produit', 'Qté Système', 'Qté Physique']

## analyse-croissance.html — 13/15 (87 %) — écran: lib/features/elevage/dashboard_elevage_screen.dart
- **titres** 0/2 — absents: Analyse des Croissances — GMQ · Évolution du GMQ — LOT-LAP-2026-06 (Cuniculture, 8 dernières semaines)

## animal-details.html — 8/49 (16 %) — écran: lib/features/elevage/fiche_lapins_screen.dart
- **titres** 0/6 — absents: Sujet #LAP-2026-0143 · Identification · QR Code Sujet · Liaison avec les Autres Modules · Courbe de Croissance · Déclarer un Mouvement
- **boutons** 2/13 — absents: Exporter PDF · Déclarer un Mouvement · Historique · Alimentation · Vaccins · Reproduction · Production · Mouvements · Documents · Ajouter un Document · Annuler
- **colonnes** 5/19 — absents: Action · Impact Automatique · Type d'Opération · Opérateur · Quantité · Coût · Traitement / Vaccin · Dose · Vétérinaire · Date Saillie · Mise Bas Prévue (J+31) · Vivants
- **etiquettes** 1/2 — absents: Type de Mouvement *
- **cartes** 0/3 — absents: Consommation du Mois · Coût Alimentaire (Mois) · Ration Journalière Moyenne
- **tableaux_manquants** 0/6 — absents: ['Action', 'Impact Automatique'] · ['Date', "Type d'Opération", 'Détail', 'Opérateur'] · ['Date', 'Aliment', 'Quantité', 'Coût'] · ['Date', 'Traitement / Vaccin', 'Dose', 'Vétérinaire'] · ['Date Saillie', 'Mâle', 'Mise Bas Prévue (J+31)', 'Nés'] · ['Date', 'Type', 'Détail']

## archivage-documents.html — 10/22 (45 %) — écran: lib/features/administration/administration_screen.dart
- **titres** 1/3 — absents: Archiver un Document · Confirmer l'archivage
- **boutons** 0/7 — absents: Exporter PDF · Archiver un Document · Indicateurs de performance · + Archiver un Document · Annuler · Enregistrer · Archiver
- **etiquettes** 1/3 — absents: Nom du document * · Date d'expiration
- **cartes** 1/2 — absents: Expirant sous 30j

## audit-logs.html — 9/17 (53 %) — écran: lib/features/parametres/parametres_generaux_screen.dart
- **titres** 1/2 — absents: Exporter le Journal
- **boutons** 0/5 — absents: Exporter le Journal · Indicateurs de performance · + Exporter le Journal · Annuler · Enregistrer
- **etiquettes** 0/2 — absents: Période à exporter * · Format d'export *

## balance-generale.html — 12/13 (92 %) — écran: lib/features/comptabilite/comptabilite_screen.dart
- **boutons** 0/1 — absents: Exporter PDF

## bilan-technico-economique.html — 0/7 (0 %) — écran: lib/features/elevage/dashboard_elevage_screen.dart
- **titres** 0/3 — absents: Bilan Technico-Économique de Lot · Détail des Coûts · Détail des Revenus
- **cartes** 0/4 — absents: Coût Total du Lot · Revenu Total du Lot · Marge Nette · Coût de Revient / Sujet

## bons-commande.html — 19/33 (58 %) — écran: lib/features/achats/achats_commandes_screen.dart
- **titres** 2/6 — absents: Bons de commande émis · Nouveau Fournisseur · Nouveau Produit · Valider la réception
- **boutons** 2/7 — absents: Ajouter au bon de commande · Générer le Bon · Annuler · Confirmer la Réception · Exporter le Bon (PDF)
- **etiquettes** 3/7 — absents: Date de Livraison Attendue · Produit / Article d'Approvisionnement · P.U Estimé (FCFA) · Raison sociale *
- **tableaux_manquants** 1/2 — absents: ['Produit', 'Qté', 'P.U', 'Total']

## catalogue-produits.html — 4/4 (100 %) — écran: AUCUN

## catalogue-view.html — 13/23 (57 %) — écran: lib/features/stocks/catalogue_produits_screen.dart
- **boutons** 2/10 — absents: Cuniculture · Aviculture · Porciculture · Maraîchage · Transformation · Équipements · Annuler · Enregistrer
- **etiquettes** 2/4 — absents: Mode de tarification * · Fourchette de Prix (FCFA) — laisser vide si Sur devis

## cloture-exercice.html — 5/27 (19 %) — écran: AUCUN
- **titres** 0/6 — absents: Bascule & Clôture d'Exercice Comptable · Historique des Clôtures Périodiques · Assistant de Clôture d'Exercice (2026 → 2027) · Clôturer l'Exercice 2026 ? · Clôturer ce Mois ? · Déclôturer ce Mois ?
- **boutons** 3/12 — absents: Clôture Annuelle · Clôturer le Mois Sélectionné · Déclôturer (exceptionnel) · Marquer comme terminé · Calculer et Solder · Clôturer l'Exercice 2026 · Confirmer la Clôture · Confirmer la Clôture du Mois · Confirmer le Déblocage
- **colonnes** 2/4 — absents: Date de Clôture · Action (Admin)
- **etiquettes** 0/1 — absents: Mois à clôturer :
- **cartes** 0/3 — absents: Résultat Provisoire · Comptes de Gestion à Solder · Lettrage Bancaire
- **tableaux_manquants** 0/1 — absents: ['Mois', 'Date de Clôture', 'Statut', 'Action (Admin)']

## comptabilite-analytique.html — 3/9 (33 %) — écran: AUCUN
- **titres** 1/3 — absents: Chiffre d'Affaires vs Coûts Directs par Espèce · Top 3 Charges (Espèce Sélectionnée)
- **cartes** 0/4 — absents: Chiffre d'Affaires Analytique · Charges Directes · Marge Brute Opérationnelle · Taux de Rentabilité

## comptabilite-hub.html — 1/5 (20 %) — écran: AUCUN
- **cartes** 0/4 — absents: Total Actif (Bilan) · Trésorerie Totale · Marge Nette (Analytique) · Résultat de l'Exercice

## contact-editeur.html — 2/11 (18 %) — écran: AUCUN
- **titres** 0/1 — absents: Contactez l'Éditeur
- **boutons** 0/4 — absents: Envoyer un Message · Signaler un Bug · Envoyer le Message · Signaler le Bug
- **etiquettes** 2/6 — absents: Module Concerné * · Description du Problème * · Étapes pour Reproduire · Capture d'Écran (optionnel)

## creances-clients.html — 8/8 (100 %) — écran: AUCUN

## dashboard.html — 28/32 (88 %) — écran: lib/features/pilotage/tableau_de_bord_screen.dart
- **titres** 9/11 — absents: Bienvenue, Manager Olouwachegoun 👋 · Rappel de Prophylaxie du Jour
- **boutons** 6/8 — absents: Indicateurs de performance · Fermer

## declaration-tva.html — 4/18 (22 %) — écran: lib/features/comptabilite/comptabilite_screen.dart
- **titres** 1/3 — absents: TVA Collectée — Ventes Assujetties · TVA Déductible — Achats Assujettis
- **boutons** 0/1 — absents: Générer la Déclaration PDF
- **colonnes** 3/9 — absents: N° Facture · Client · Montant HT · Montant TTC · Référence · Fournisseur
- **etiquettes** 0/1 — absents: Période de déclaration :
- **cartes** 0/2 — absents: TVA Collectée (4431) · TVA Déductible (4452)
- **tableaux_manquants** 0/2 — absents: ['N° Facture', 'Client', 'Date', 'Taux'] · ['Référence', 'Fournisseur', 'Date', 'Taux']

## dettes-fournisseurs.html — 8/24 (33 %) — écran: lib/features/achats/fournisseurs_screen.dart
- **titres** 1/4 — absents: Enregistrer un Règlement · Modifier — Dettes Fournisseurs · Confirmer l'archivage
- **boutons** 0/8 — absents: Exporter PDF · Enregistrer un Règlement · Indicateurs de performance · + Enregistrer un Règlement · Annuler · Enregistrer · Mettre à jour · Archiver
- **etiquettes** 1/3 — absents: Montant réglé (FCFA) * · Date de règlement *
- **cartes** 0/3 — absents: Dettes totales · En retard · Fournisseurs concernés

## devis.html — 13/45 (29 %) — écran: AUCUN
- **titres** 0/5 — absents: Devis & Proforma · Détail du Devis · Importer des Devis · Nouveau Devis · Confirmer l'Archivage
- **boutons** 6/18 — absents: Nouveau Devis · DEV-2026-018 · DEV-2026-017 · DEV-2026-016 · DEV-2026-015 · DEV-2026-014 · Convertir en Facture de Vente · Imprimer · Télécharger proforma_template.xlsx · Enregistrer le Devis · Oui, Archiver Définitivement · Télécharger PDF
- **colonnes** 6/9 — absents: N° Devis · Validité · Montant HT
- **etiquettes** 1/6 — absents: Articles / Prestations (désignation, quantité, P.U) * · Montant HT (FCFA) * · Taux de TVA · Validité (jours) · Note / Conditions particulières
- **cartes** 0/4 — absents: Devis Actifs · Valeur Totale · Taux de Conversion · En Attente de Relance
- **tableaux_manquants** 0/3 — absents: ['N° Devis', 'Client', 'Date', 'Validité'] · ['Désignation', 'Montant HT'] · ['Désignation', 'Montant HT']

## documents-administratifs.html — 10/22 (45 %) — écran: lib/features/administration/administration_screen.dart
- **titres** 1/3 — absents: Générer un Document · Confirmer l'archivage
- **boutons** 0/7 — absents: Exporter PDF · Générer un Document · Indicateurs de performance · + Générer un Document · Annuler · Enregistrer · Archiver
- **etiquettes** 2/3 — absents: Type de document *
- **cartes** 0/2 — absents: Modèles disponibles · Générés (mois)

## elevage-dashboard.html — 33/58 (57 %) — écran: lib/features/elevage/dashboard_elevage_screen.dart
- **titres** 9/17 — absents: Évolution du GMQ — LOT-LAP-2026-06 (Cuniculture, 8 dernières semaines) · Détail des Coûts · Détail des Revenus · Alertes Sanitaires du Jour · Maladies les Plus Fréquentes — 2026 vs 2025 · Répartition Saisonnière des Cas (2026) · Courbe de Croissance — Historique et Projection · Rappel de Prophylaxie du Jour
- **boutons** 5/7 — absents: Indicateurs de performance · Fermer
- **colonnes** 9/13 — absents: Maladie / Symptôme · Cas 2025 · Cas 2026 · Période de Sensibilité
- **etiquettes** 1/4 — absents: Poids Actuel Constaté (g) · GMQ Observé (g/jour) · Horizon de Projection
- **cartes** 8/15 — absents: Coût Total du Lot · Revenu Total du Lot · Marge Nette · Coût de Revient / Sujet · Poids Projeté · Poids Cible de Commercialisation · Date Estimée d'Atteinte de la Cible
- **tableaux_manquants** 1/2 — absents: ['Maladie / Symptôme', 'Espèce', 'Cas 2025', 'Cas 2026']

## enregistrer-achat.html — 26/32 (81 %) — écran: lib/features/achats/achats_commandes_screen.dart
- **titres** 2/4 — absents: Nouveau Fournisseur · Nouveau Produit
- **boutons** 3/4 — absents: Annuler
- **etiquettes** 10/12 — absents: Raison sociale * · Telephone *
- **tableaux_manquants** 1/2 — absents: ['Designation', 'Qte', 'P.U', 'Total']

## enregistrer-sujets.html — 16/25 (64 %) — écran: AUCUN
- **titres** 0/4 — absents: Enregistrer des Sujets · Nouveau Sujet · Modifier — Enregistrer des Sujets · Confirmer l'archivage
- **boutons** 4/7 — absents: Nouveau Sujet · + Nouveau Sujet · Mettre à jour
- **cartes** 1/3 — absents: Naissances (mois) · Acquisitions (mois)

## etats-financiers.html — 4/22 (18 %) — écran: lib/features/comptabilite/comptabilite_screen.dart
- **titres** 1/10 — absents: Actif (Emplois) · Passif (Ressources) · Compte de Résultat — Structure en Cascade SYSCOHADA · Tableau des Flux de Trésorerie (TAFIRE simplifié) · Note 1 — Méthodes Comptables · Note 2 — Immobilisations · Note 3 — Stocks · Note 4 — Créances et Dettes · Note 5 — Engagements Hors Bilan
- **boutons** 2/5 — absents: Exporter PDF (Onglet Actif) · Flux de Trésorerie · Notes Annexes
- **colonnes** 1/5 — absents: Nature · Valeur Brute · Amort. Cumulés · Valeur Nette
- **tableaux_manquants** 0/2 — absents: ['Nature', 'Valeur Brute', 'Amort. Cumulés', 'Valeur Nette'] · ['Nature', 'Montant']

## facturation.html — 15/26 (58 %) — écran: lib/features/ventes/facturation_screen.dart
- **titres** 3/5 — absents: Modifier — Facturation & MeCeF · Confirmer l'archivage
- **boutons** 2/8 — absents: Indicateurs de performance · + Nouvelle Facture · Annuler · Enregistrer · Mettre à jour · Archiver
- **etiquettes** 1/3 — absents: Montant HT (FCFA) * · Taux de TVA *
- **cartes** 2/3 — absents: Statut "Transmise" (simulation)

## feuille-pointage.html — 19/25 (76 %) — écran: lib/features/rh/personnel_stages_screen.dart, lib/features/rh/personnel_repository.dart
- **titres** 2/3 — absents: Confirmer l'archivage
- **boutons** 3/7 — absents: Exporter PDF · Indicateurs de performance · + Enregistrer un Pointage · Archiver
- **cartes** 2/3 — absents: Présents (jour)

## fiche-escargots.html — 44/50 (88 %) — écran: AUCUN
- **titres** 1/3 — absents: Saisie Journalière Cheptel & Bacs de Ponte — Jour 15 (15/07/2026) · Rappel Entretien & Hygrométrie — Jour X
- **etiquettes** 13/17 — absents: Poids Moyen Constatéd · Fosse F1 (Naissains) · Parc P2 (Engraissement) · Escargotière E3 (Bordés)

## fiche-lapins.html — 42/48 (88 %) — écran: AUCUN
- **titres** 1/3 — absents: Saisie Journalière du Cheptel — Jour 15 (15/07/2026) · Rappel Prophylaxie — Jour X
- **etiquettes** 12/16 — absents: Cage C1 (Bande B1) · Cage C2 (Bande B1) · Cage C5 (Bande B2) · Cage C12 (Bande B1)

## fiche-porcs.html — 43/48 (90 %) — écran: AUCUN
- **titres** 1/3 — absents: Saisie Journalière du Cheptel Porcin — Jour 15 (15/07/2026) · Rappel Prophylaxie Porcine — Jour X
- **etiquettes** 11/14 — absents: Logette L1 (Engraissement) · Maternité M2 (Truies) · Bâtiment E3 (Jeunes porcs)

## fiche-volailles-pondeuses.html — 44/53 (83 %) — écran: AUCUN
- **titres** 0/3 — absents: Fiches Pondeuses - Aviculture Ponte · Saisie Journalière Ponte & Cheptel — Jour 15 (15/07/2026) · Rappel Prophylaxie — Jour X
- **colonnes** 20/21 — absents: Date / Jour
- **etiquettes** 15/19 — absents: Poids Moyen Constatéd · Bâtiment P1 (Pondeuses) · Parc B2 (Poulettes) · Bâtiment Démarrage D1
- **tableaux_manquants** 1/2 — absents: ['Date / Jour', 'Eff. Début', 'Morts', 'Taux Mort %']

## fiche-volailles-reproducteurs.html — 41/48 (85 %) — écran: AUCUN
- **titres** 0/3 — absents: Fiches Volailles - Reproducteurs, Poussins & Goliath · Saisie Journalière Couvoir & Suivi Chair — Jour 15 (15/07/2026) · Rappel Prophylaxie Avicole — Jour X
- **etiquettes** 13/17 — absents: Poids Moyen Constatéd · Parc R1 (Reproducteurs) · Poussinière D1 · Bâtiment G2 (Goliath/Chair)

## fiche-volailles.html — 36/60 (60 %) — écran: AUCUN
- **titres** 1/4 — absents: Fiches Volailles - Aviculture · Tableau 2 — Mouvements, Traitements et Provendes · Fiche Journalière — Volailles
- **boutons** 5/10 — absents: Ajouter Fiche Journalière · Exporter la Fiche · Enregistrer la Fiche Hebdomadaire · Suivant — Déclarer les Sorties · Traitement du Jour
- **etiquettes** 5/19 — absents: Quantité Provendes restantes (Poussins) · Quantité Provendes restantes (Reproducteurs) · Produits à Acheter · Observations et Recommandations de l'Animalier · Date du Relevé · Bande / Bâtiment · Cause présumée (si mortalité) · Quantité Servie (Kg) * · Taille de l'Échantillon · Type de soin · Médicament utilisé · Dose par sujet
- **cartes** 2/4 — absents: Effectif Volailles · Indice de Consommation

## fiches-fournisseurs.html — 10/31 (32 %) — écran: lib/features/achats/fournisseurs_screen.dart
- **titres** 1/6 — absents: Nouveau Fournisseur · Modifier — Fiches Fournisseurs · Confirmer l'archivage · Importer des Fournisseurs · Destruction de fiches fournisseurs
- **boutons** 0/14 — absents: Exporter PDF · Importer · Nouveau Fournisseur · Supprimer la selection · Indicateurs de performance · + Nouveau Fournisseur · Annuler · Enregistrer · Mettre à jour · Archiver · Parcourir les fichiers · Telecharger le modele supplier_sample.xlsx
- **etiquettes** 1/2 — absents: Nom du fournisseur *
- **tableaux_manquants** 0/1 — absents: ['(sans libelle)', 'Nom', 'Catégorie', 'Total Achats (Année)']

## fournisseurs.html — 6/6 (100 %) — écran: AUCUN

## gestion-bandes.html — 16/41 (39 %) — écran: AUCUN
- **titres** 2/5 — absents: Nouvelle Bande · Modifier la Bande · Confirmer la Clôture
- **boutons** 3/10 — absents: Nouvelle Bande · Saisir la Distribution du Jour · Transformer · Clôturer la Bande · Créer la Bande · Enregistrer les Modifications · Oui, Supprimer Définitivement
- **colonnes** 5/9 — absents: Code Bande · Date Création · Eff. Initial · Eff. Actuel
- **etiquettes** 4/12 — absents: Code Unique de la Bande * · Stade Initial · Quantité Initiale (Effectif) * · Coût d'Acquisition (FCFA) · Enregistrer chaque sujet avec un numéro individuel · Préfixe de Numérotation · Code Unique de la Bande · Effectif Actuel *
- **cartes** 2/4 — absents: Bandes Actives · Alertes Sanitaires
- **tableaux_manquants** 0/1 — absents: ['Code Bande', 'Espèce', 'Stade', 'Date Création']

## gestion-courriers.html — 12/24 (50 %) — écran: lib/features/administration/administration_screen.dart
- **titres** 1/3 — absents: Nouveau Courrier · Confirmer l'archivage
- **boutons** 0/7 — absents: Exporter PDF · Nouveau Courrier · Indicateurs de performance · + Nouveau Courrier · Annuler · Enregistrer · Archiver
- **etiquettes** 3/4 — absents: Expéditeur / Destinataire *
- **cartes** 1/3 — absents: Reçus (mois) · Envoyés (mois)

## gestion-elevage.html — 2/7 (29 %) — écran: AUCUN
- **titres** 1/3 — absents: Registres par Espèce · Accès Rapides — Élevage & Soins
- **cartes** 1/4 — absents: Bandes Actives · Alertes Stock Aliment · Taux Mortalité (mois)

## gestion-paie.html — 15/18 (83 %) — écran: lib/features/rh/personnel_stages_screen.dart
- **boutons** 0/3 — absents: Exporter · Indicateurs de performance · Télécharger le Bulletin PDF

## gestion-stocks.html — 37/51 (73 %) — écran: lib/features/stocks/gestion_stocks_screen.dart
- **titres** 2/6 — absents: Ajouter Stock · Importer un Inventaire · Modifier le Produit · Confirmer la Suppression ?
- **boutons** 6/13 — absents: Recalculer PMP · Ajouter Stock · Annuler · Enregistrer · Telecharger inventory_template.xlsx · Fermer · Oui, Supprimer définitivement
- **etiquettes** 9/12 — absents: Date du Nouveau Stock * · Quantité Ajoutée * · PMP (FCFA) *

## gestion-utilisateurs.html — 12/21 (57 %) — écran: lib/features/parametres/parametres_generaux_screen.dart
- **titres** 1/3 — absents: Nouvel Utilisateur · Confirmer l'archivage
- **boutons** 1/7 — absents: Exporter PDF · Nouvel Utilisateur · Indicateurs de performance · + Nouvel Utilisateur · Annuler · Enregistrer
- **etiquettes** 2/3 — absents: Nom complet *

## grand-livre.html — 12/13 (92 %) — écran: lib/features/comptabilite/comptabilite_screen.dart
- **boutons** 0/1 — absents: Exporter PDF

## historique-avances.html — 12/29 (41 %) — écran: lib/features/clients/clients_creances_screen.dart
- **titres** 1/4 — absents: Importer des Avances · Nouvel Acompte · Imputer un Acompte
- **boutons** 0/10 — absents: Exporter · Importer · Nouvelle Avance · Indicateurs de performance · Télécharger advances_template.xlsx · Fermer · Annuler · Enregistrer et Délivrer le Reçu · Affecter · Valider l'Imputation
- **etiquettes** 1/5 — absents: Motif / Commande réservée * · Montant de l'Acompte (FCFA) * · Mode de Paiement · Choix Facture de Vente

> **Annotation F0.73 (09/10/2026)** — mesure de `py outils/audit_fidelite.py` : historique-avances **11/28 (39,3 %) → 23/28 (82,1 %)** en strict ; global **1 267 → 1 281 / 2 099**. Livrés : Nouvelle Avance / Nouvel Acompte, Imputer un Acompte (Affecter, Choix Facture de Vente, Valider l'Imputation), Exporter, reçu non numéroté « Reçu du poste », envoi/acquittement/conflit/relance, absorbeurs `avances`/`créances` par fusion (plus de « tout effacer »), tirage de confirmation après acquittement. Restent non portés avec motif écrit par page : Importer, Importer des Avances, Télécharger advances_template.xlsx (D10). Quinze exemptions GLOBALES retirées ; « Client * » masquait facturation.html (écart antérieur, désormais exempté par page et à examiner). Non fait : imputation vers une vente à crédit non encore synchronisée (`sale_id`, colonne prête), filtres de la maquette, visibilité des boutons par rôle (RBAC), « Voir » inerte. Ticket complet dans `README_SPRINT0.md`.

## historique-ventes.html — 21/36 (58 %) — écran: lib/features/ventes/ventes_devis_screen.dart
- **titres** 1/3 — absents: Détail de la Vente · Annuler la Vente
- **boutons** 3/10 — absents: Exporter · Imprimer · Relancer · Télécharger PDF · Fermer · Annuler · Émettre l'Avoir
- **colonnes** 12/15 — absents: Désignation · Qté · P.U
- **etiquettes** 0/1 — absents: MOTIF DU RETOUR / DE L'ANNULATION
- **tableaux_manquants** 1/3 — absents: ['Désignation', 'Qté', 'P.U', 'Total'] · ['Désignation', 'Qté', 'P.U', 'Total']

## journal-comptable.html — 13/26 (50 %) — écran: lib/features/comptabilite/comptabilite_screen.dart
- **titres** 1/3 — absents: Saisie d'Écriture · Confirmer l'archivage
- **boutons** 0/7 — absents: Exporter PDF · Saisie d'Écriture · Indicateurs de performance · + Saisie d'Écriture · Annuler · Enregistrer · Archiver
- **etiquettes** 1/5 — absents: Date de l'écriture * · Compte à débiter * · Compte à créditer * · Montant (FCFA) *

## liste-achats.html — 15/37 (41 %) — écran: lib/features/achats/achats_commandes_screen.dart
- **titres** 1/5 — absents: Détail de l'Achat · Ajouter un Remboursement · Importer des Achats · Retour Fournisseur
- **boutons** 1/15 — absents: Exporter PDF · Importer · Ajouter Remboursement · Indicateurs de performance · ACH-2026-101 · ACH-2026-100 · ACH-2026-099 · ACH-2026-098 · Imprimer · Retour Fournisseur · Annuler · Télécharger purchase_sample.xlsx
- **etiquettes** 1/5 — absents: Montant Remboursé (FCFA) * · Date du Remboursement * · Compte de Trésorerie · MOTIF DE L'ANNULATION / RETOUR

> **Annotation F0.75 (09/10/2026)** — mesure de `py outils/audit_fidelite.py` : liste-achats **14/36 (38,9 %) → 17/36 (47,2 %)** en strict. Livrés : « Détail de l'Achat » (modale), « Exporter PDF », « Imprimer » (via `ExportOfficiel`, effets injectés). Restent non portés, motifs inchangés et vrais : Importer / Importer des Achats / Télécharger purchase_sample.xlsx (D10), Ajouter (un) Remboursement / Retour Fournisseur / Confirmer le Retour / leurs champs (contre-passation, ticket 15.19 puis F0.7x), boutons ACH-2026-xxx (démonstration, jamais portés). Les exemptions GLOBALES « Exporter PDF » / « Imprimer » (motif périmé « chaîne d'édition non embarquée ») masquaient 18 pages : migrées en exemptions par page, motif « écran qui n'appelle pas la chaîne d'édition (F0.52) ».

> **Annotation F0.74 (09/10/2026)** — `py outils/audit_fidelite.py` : liste-achats **17/36 (47,2 %) → 27/36 (75,0 %)** en strict ; global 1 281 → 1 291 / 2 099. Livrés : « Retour Fournisseur » (modale, bouton de ligne et du détail), « Confirmer le Retour », « MOTIF DE L'ANNULATION / RETOUR », « Ajouter Remboursement », « Ajouter un Remboursement » et ses champs. Neuf exemptions GLOBALES « contre-passation réservée au web » retirées. Restent non portés, motifs vrais : Importer / Importer des Achats / Télécharger purchase_sample.xlsx (D10), ACH-2026-xxx (démonstration), « Indicateurs de performance » (accordéon mobile).

## liste-clients.html — 13/34 (38 %) — écran: lib/features/clients/clients_creances_screen.dart
- **titres** 1/6 — absents: Nouveau Client · Importer des Clients · Exporter les Clients · Détruire la fiche client · Détruire les fiches clients
- **boutons** 0/13 — absents: PDF · Exporter · Importer · Nouveau Client · Indicateurs de performance · Supprimer la sélection · Annuler · Enregistrer · Parcourir les fichiers · Télécharger le modèle client_sample.xlsx · Fermer · Télécharger clients.xlsx
- **etiquettes** 2/4 — absents: Nom complet * · Adresse email
- **tableaux_manquants** 0/1 — absents: ['(sans libelle)', 'Nom', 'Téléphone', 'Ville']

## login.html — 9/10 (90 %) — écran: lib/features/auth/login_screen.dart
- **boutons** 4/5 — absents: Envoyer le lien de réinitialisation

## modes-paiement.html — 12/23 (52 %) — écran: lib/features/parametres/parametres_generaux_screen.dart
- **titres** 5/6 — absents: Ajouter une Ligne Mobile Money
- **boutons** 2/5 — absents: Ajouter une Ligne Mobile Money · Annuler · Enregistrer
- **etiquettes** 2/9 — absents: Titulaire du Compte · RIB * · IBAN * · Sous-compte Auxiliaire · Numero de Telephone * · Titulaire de la Ligne · Numero de Serie SIM

## modules-actifs.html — 1/1 (100 %) — écran: lib/features/parametres/parametres_generaux_screen.dart

## mon-profil.html — 5/11 (45 %) — écran: AUCUN
- **titres** 0/2 — absents: Mon Profil · Journal d'Audit — 10 Dernières Actions
- **boutons** 0/1 — absents: Mettre à jour le mot de passe
- **etiquettes** 0/3 — absents: Ancien mot de passe * · Nouveau mot de passe * · Confirmer le nouveau mot de passe *

## mouvement-stock.html — 8/25 (32 %) — écran: lib/features/stocks/gestion_stocks_screen.dart
- **titres** 0/4 — absents: Mouvements de Stock · Nouveau Mouvement · Modifier — Mouvements de Stock · Confirmer l'archivage
- **boutons** 0/7 — absents: Nouveau Mouvement · Indicateurs de performance · + Nouveau Mouvement · Annuler · Enregistrer · Mettre à jour · Archiver
- **colonnes** 5/6 — absents: Statut
- **etiquettes** 3/4 — absents: Type de mouvement *
- **cartes** 0/3 — absents: Entrées (mois) · Sorties (mois) · Valeur stock
- **tableaux_manquants** 0/1 — absents: ['Date', 'Produit', 'Type', 'Quantité']

## notifications.html — 0/12 (0 %) — écran: lib/core/widgets/barre_superieure.dart
- **titres** 0/1 — absents: Centre de Notifications
- **boutons** 0/1 — absents: Résumé des alertes
- **colonnes** 0/6 — absents: Date / Heure · Catégorie · Message · Gravité · Statut · Actions
- **cartes** 0/3 — absents: Non Lues · Critiques · Total (30 jours)
- **tableaux_manquants** 0/1 — absents: ['Date / Heure', 'Catégorie', 'Message', 'Gravité']

## parametres-elevage.html — 45/64 (70 %) — écran: lib/features/elevage/parametres_elevage_screen.dart, lib/features/elevage/parametres_elevage_repository.dart
- **titres** 5/8 — absents: Saisir une Ration · Échéance de Prophylaxie · Confirmer la Suppression ?
- **boutons** 7/15 — absents: Exporter PDF · Ajouter une Ration · Ajouter une Échéance · Ajouter un Type · Enregistrer Tous les Formats de Numérotation · Annuler · Enregistrer · Oui, Supprimer définitivement
- **etiquettes** 13/21 — absents: Lapines Reproductrices ($R_1..R_n$) · Mâles Saillisseurs ($M_1..M_n$) · Truies Reproductrices ($T_1..T_n$) · Verrats Reproducteurs ($V_1..V_n$) · Ration Normative (en Grammes g/tête/jour) * · Jour / Âge * · Dose * · Délai de Rémanence (Jours d'attente)

## parametres-hub.html — 12/12 (100 %) — écran: AUCUN

## parametres.html — 11/15 (73 %) — écran: lib/features/parametres/parametres_generaux_screen.dart
- **boutons** 0/2 — absents: Envoyer un e-mail de test · Enregistrer les Modifications
- **etiquettes** 10/12 — absents: Serveur SMTP · Utilisateur SMTP

## personnel-stages.html — 10/10 (100 %) — écran: AUCUN

## plan-comptable.html — 10/20 (50 %) — écran: lib/features/comptabilite/comptabilite_screen.dart
- **titres** 1/3 — absents: Nouveau Compte · Confirmer l'archivage
- **boutons** 0/7 — absents: Exporter PDF · Nouveau Compte · Indicateurs de performance · + Nouveau Compte · Annuler · Enregistrer · Archiver
- **etiquettes** 2/3 — absents: Numéro de compte *

## pos-interface.html — 30/41 (73 %) — écran: AUCUN
- **titres** 5/7 — absents: Nouveau Client · Choisir le compte
- **boutons** 12/19 — absents: Ajouter Produit Ferme · Livraison concernée ✓ · Produits finis · Maraîchage · Équipements · Télécharger la Facture · Télécharger PDF
- **etiquettes** 8/10 — absents: Livraison concernée (cages, sujets volumineux) · Nom complet *

## prevision-croissance.html — 2/9 (22 %) — écran: lib/features/elevage/dashboard_elevage_screen.dart
- **titres** 1/2 — absents: Courbe de Croissance — Historique et Projection
- **etiquettes** 1/4 — absents: Poids Actuel Constaté (g) · GMQ Observé (g/jour) · Horizon de Projection
- **cartes** 0/3 — absents: Poids Projeté · Poids Cible de Commercialisation · Date Estimée d'Atteinte de la Cible

## profile-client.html — 16/28 (57 %) — écran: AUCUN
- **titres** 0/2 — absents: Profil Client · Enregistrer un Reglement
- **boutons** 3/10 — absents: Modifier la fiche · Enregistrer un reglement · Envoyer une relance rapide · Avances & Acomptes · Regler · + Enregistrer une nouvelle avance · Valider le Reglement
- **colonnes** 10/11 — absents: Anciennete
- **etiquettes** 1/2 — absents: Montant du Reglement (FCFA)
- **tableaux_manquants** 2/3 — absents: ['Facture', 'Echeance', 'Anciennete', 'Solde Du']

## profile-fournisseur.html — 6/20 (30 %) — écran: lib/features/achats/fournisseurs_screen.dart
- **titres** 0/2 — absents: Profil Fournisseur · Enregistrer un Reglement
- **boutons** 2/6 — absents: Modifier la fiche · Enregistrer un reglement · Commandes · Valider le Reglement
- **colonnes** 4/8 — absents: Reference · BC N · Emission · Livraison
- **etiquettes** 0/2 — absents: Montant du Reglement (FCFA) · Compte de Tresorerie
- **tableaux_manquants** 0/2 — absents: ['Reference', 'Date', 'Categorie', 'Montant'] · ['BC N', 'Emission', 'Livraison', 'Montant']

## rapport-bilan.html — 0/4 (0 %) — écran: AUCUN
- **titres** 0/3 — absents: Bilan Simplifié de l'Entreprise · Actif (Emplois) · Passif (Ressources)
- **boutons** 0/1 — absents: Générer PDF

## rapport-creances.html — 8/8 (100 %) — écran: lib/features/rapports/rapports_exports_screen.dart

## rapport-depenses.html — 9/19 (47 %) — écran: lib/features/rapports/rapports_exports_screen.dart
- **titres** 1/4 — absents: État des Dépenses · Modifier — État des Dépenses · Confirmer l'archivage
- **boutons** 2/6 — absents: + Filtrer la Période · Enregistrer · Mettre à jour · Archiver
- **colonnes** 3/5 — absents: Achats Intrants · Charges Salariales
- **tableaux_manquants** 0/1 — absents: ['Période', 'Achats Intrants', 'Charges Salariales', 'Total']

## rapport-dettes.html — 8/8 (100 %) — écran: lib/features/rapports/rapports_exports_screen.dart

## rapport-elevage-synth.html — 51/52 (98 %) — écran: lib/features/rapports/rapports_exports_screen.dart
- **boutons** 7/8 — absents: Indicateurs Zootechniques (Replier / Déplier)

## rapport-mensuel.html — 9/14 (64 %) — écran: AUCUN
- **titres** 1/2 — absents: Rapport Mensuel de Synthèse
- **boutons** 3/4 — absents: + Filtrer la Période
- **colonnes** 2/4 — absents: Juillet · Juin
- **tableaux_manquants** 0/1 — absents: ['Indicateur', 'Juillet', 'Juin', 'Actions']

## rapport-recettes-depenses.html — 13/13 (100 %) — écran: lib/features/rapports/rapports_exports_screen.dart

## rapport-recettes.html — 10/19 (53 %) — écran: lib/features/rapports/rapports_exports_screen.dart
- **titres** 2/4 — absents: Modifier — État des Recettes · Confirmer l'archivage
- **boutons** 2/6 — absents: + Filtrer la Période · Enregistrer · Mettre à jour · Archiver
- **colonnes** 3/5 — absents: Ventes POS · Avances Clients
- **tableaux_manquants** 0/1 — absents: ['Période', 'Ventes POS', 'Avances Clients', 'Total']

## rapport-stocks-synth.html — 8/8 (100 %) — écran: lib/features/rapports/rapports_exports_screen.dart

## rapport-tresorerie.html — 9/9 (100 %) — écran: lib/features/rapports/rapports_exports_screen.dart

## rapports-exports.html — 15/15 (100 %) — écran: lib/features/rapports/rapports_exports_screen.dart

## rapprochement-bancaire.html — 8/20 (40 %) — écran: lib/features/comptabilite/comptabilite_screen.dart
- **titres** 1/4 — absents: Grand Livre (Compte 521) · Relevé Bancaire Importé · Historique des Rapprochements Clôturés
- **boutons** 0/2 — absents: Importer un Relevé (CSV) · Exporter PDF
- **colonnes** 6/7 — absents: Statut
- **cartes** 0/3 — absents: Solde Livre (Grand Livre) · Solde Relevé Bancaire · Opérations en Instance
- **tableaux_manquants** 0/3 — absents: ['Date', 'Libellé', 'Montant', 'Statut'] · ['Date', 'Libellé', 'Montant', 'Statut'] · ['Période', 'Compte', 'Solde Final', 'Statut']

## registre-employes.html — 14/23 (61 %) — écran: lib/features/rh/personnel_stages_screen.dart
- **titres** 1/3 — absents: Nouvel Employé · Confirmer l'archivage
- **boutons** 2/7 — absents: Exporter PDF · Nouvel Employé · Indicateurs de performance · + Nouvel Employé · Archiver
- **etiquettes** 2/4 — absents: Nom complet * · Salaire (FCFA) *

## registre-stagiaires.html — 15/27 (56 %) — écran: lib/features/rh/personnel_stages_screen.dart
- **titres** 1/4 — absents: Nouveau Stagiaire · Absences / Abandon · Attestation de Stage
- **boutons** 2/5 — absents: Nouveau Stagiaire · Indicateurs de performance · Télécharger l'Attestation PDF
- **etiquettes** 1/7 — absents: Nom complet * · Date de début · Date de fin · Frais de stage (FCFA) · Date de l'absence · Motif

## relances-clients.html — 11/16 (69 %) — écran: lib/features/clients/clients_creances_screen.dart
- **boutons** 4/9 — absents: Indicateurs de performance · Relancer WhatsApp · Relancer par Mail · Exporter Courrier · Sauvegarder Modèle

## retours-avoirs.html — 14/31 (45 %) — écran: AUCUN
- **titres** 2/3 — absents: Nouveau Retour — Assistant en 5 étapes
- **boutons** 2/4 — absents: Nouveau Retour · Exporter l'Avoir (PDF)
- **etiquettes** 0/10 — absents: Numéro de la facture d'origine · Sélection des articles à retourner · Lapin vivant (vendu : 5) · Œufs de table (vendu : 8 plateaux) · Motif du retour · Inspection sanitaire (animaux vivants) · Réintégration Animal sain — hausse du stock d'élevage, rattaché au lot d'origine. · Quarantaine Risque sanitaire mineur — isolement en infirmerie d'élevage. · Réforme / Perte Non réintégrable — enregistré en mortalité/perte du cheptel. · Récapitulatif & Validation
- **cartes** 0/4 — absents: Retours du mois · Montant Avoirs · Produits Retournés · Taux de Retour

## rh-attestations.html — 3/19 (16 %) — écran: lib/features/rh/personnel_stages_screen.dart
- **boutons** 0/6 — absents: Generer une Attestation · Personnaliser les Modeles · Employe Permanent · Stagiaire en Formation · Generer l'Attestation · Enregistrer ce Modele
- **etiquettes** 2/12 — absents: Nom de la personne * · Type de Contrat · Date de Debut · Date de Fin · Note d'Evaluation (optionnel) · Texte du certificat · Filigrane logo (centre) · Signature numerisee DG · Cachet humide (scan) · Format

## roles-permissions.html — 31/47 (66 %) — écran: lib/features/parametres/parametres_generaux_screen.dart
- **titres** 3/6 — absents: Nouveau Role · Modifier le Rôle · Supprimer ce Rôle ?
- **boutons** 1/7 — absents: Exporter PDF · Nouveau Role · Annuler · Enregistrer · Enregistrer les Modifications · Supprimer Définitivement
- **colonnes** 12/14 — absents: Fichier · Taille
- **etiquettes** 10/14 — absents: Nom du role * · Modules autorises · Nom du rôle * · Modules autorisés
- **tableaux_manquants** 1/2 — absents: ['Fichier', 'Date', 'Taille', 'Actions']

## saisie-depenses.html — 22/25 (88 %) — écran: AUCUN
- **titres** 2/4 — absents: Détail de la Dépense · Confirmer l'Archivage
- **boutons** 4/5 — absents: Oui, Archiver Définitivement

## seuils-alerte.html — 10/20 (50 %) — écran: lib/features/stocks/catalogue_produits_screen.dart
- **titres** 1/3 — absents: Configurer un Seuil · Confirmer l'archivage
- **boutons** 0/7 — absents: Exporter PDF · Configurer un Seuil · Indicateurs de performance · + Configurer un Seuil · Annuler · Enregistrer · Archiver
- **etiquettes** 1/2 — absents: Nouveau seuil minimum *

## soins-vaccins-hub.html — 6/6 (100 %) — écran: AUCUN

## suivi-dettes.html — 12/21 (57 %) — écran: lib/features/clients/clients_creances_screen.dart
- **titres** 1/2 — absents: Enregistrer un Règlement
- **boutons** 0/5 — absents: Ajouter un Recouvrement · Indicateurs de performance · Exporter PDF · Annuler · Valider le Décaissement
- **etiquettes** 0/3 — absents: Montant du Règlement (FCFA) · Compte Débité · Nouveau Solde Dû

## suivi-reproduction.html — 58/106 (55 %) — écran: lib/features/elevage/suivi_reproduction_screen.dart
- **titres** 7/14 — absents: Enregistrer la Mise Bas — — · Lancer un Lot d'Incubation (Couvoir) · Placer un Bac de Ponte (Héliciculture) · Modifier la Fiche Lapine · Modifier le Lot d'Incubation · Modifier la Fiche Truie · Modifier le Bac de Ponte
- **boutons** 8/19 — absents: Indicateurs de Reproduction & Éclosion (Replier / Déplier) · Saisir Sevrage · Lancer un Lot d'Incubation · Saisir Mise Bas · Déclarer un Bac de Ponte · Enregistrer le Résultat · Enregistrer la Mise Bas · Enregistrer le Sevrage · Lancer l'Incubation · Enregistrer le Bac de Ponte · Enregistrer les Modifications
- **colonnes** 24/34 — absents: Code Incubation · Bande Reproducteurs · Date Incubation (J0) · Taux Éclosion (%) · Parc / Bâtiment · Parc / Fosse · Code Bac Ponte · Date Placement · Œufs Pondus (terre) · Éclosion Attendue (J+25)
- **etiquettes** 9/27 — absents: N° Lapine ($R_1..R_n$) * · Résultat de Palpation (J+14) · Total Petits Nés · Nés Vivants · Sevrés Mâles · Sevrés Femelles · Poids Général des Lapereaux Sevrés (g) · Total Porcelets Nés Vivants · Code Lot Incubation * · Bande Reproducteurs * · Date Incubation (J0) * · Œufs Couvés (Mise en couvoir) *
- **tableaux_manquants** 2/4 — absents: ['Code Incubation', 'Bande Reproducteurs', 'Date Incubation (J0)', 'Éclosion Attendue (J+21)'] · ['Parc / Fosse', 'Code Bac Ponte', 'Date Placement', 'Œufs Pondus (terre)']

## suivi-sanitaire-analyse.html — 3/11 (27 %) — écran: lib/features/elevage/dashboard_elevage_screen.dart
- **titres** 1/4 — absents: Alertes Sanitaires du Jour · Maladies les Plus Fréquentes — 2026 vs 2025 · Répartition Saisonnière des Cas (2026)
- **colonnes** 2/6 — absents: Maladie / Symptôme · Cas 2025 · Cas 2026 · Période de Sensibilité
- **tableaux_manquants** 0/1 — absents: ['Maladie / Symptôme', 'Espèce', 'Cas 2025', 'Cas 2026']

## tableau-stocks.html — 5/25 (20 %) — écran: lib/features/stocks/gestion_stocks_screen.dart
- **titres** 0/4 — absents: Tableau des Stocks · Ajouter un Produit · Modifier — Tableau des Stocks · Confirmer l'archivage
- **boutons** 0/7 — absents: Ajouter un Produit · Indicateurs de performance · + Ajouter un Produit · Annuler · Enregistrer · Mettre à jour · Archiver
- **colonnes** 4/6 — absents: Seuil Min. · Statut
- **etiquettes** 1/4 — absents: Nom du produit * · Quantité initiale * · Seuil minimum *
- **cartes** 0/3 — absents: Références suivies · Valeur totale · Sous seuil critique
- **tableaux_manquants** 0/1 — absents: ['Produit', 'Catégorie', 'Quantité', 'Seuil Min.']

## transformation.html — 5/20 (25 %) — écran: AUCUN
- **titres** 0/2 — absents: Bon d'Abattage & Transformation · Historique des Transformations
- **boutons** 1/2 — absents: Valider la Transformation
- **colonnes** 3/6 — absents: Sujets Abattus · Produit Fini · Qté Produite
- **etiquettes** 1/6 — absents: Lot / Bande d'Élevage * · Nombre de Sujets à Abattre * · Produit Fini Cible * · Quantité Produite (Unités / Kg) · Date de Transaction
- **cartes** 0/3 — absents: Transformations (mois) · Sujets Transformés · Valeur Stock Produit Fini
- **tableaux_manquants** 0/1 — absents: ['Date', 'Bande Source', 'Sujets Abattus', 'Produit Fini']

## ventes-devis.html — 8/8 (100 %) — écran: AUCUN

## vms-calendrier.html — 4/13 (31 %) — écran: lib/features/elevage/soins_vaccins_screen.dart
- **titres** 1/3 — absents: Détail de l'Intervention · Planifier une Intervention
- **boutons** 1/5 — absents: Planifier une Intervention · Confirmer Administration · Fermer · Planifier
- **etiquettes** 1/3 — absents: Type de Tâche * · Date Planifiée *
- **tableaux_manquants** 0/1 — absents: ['Lot / Bande', '19/7', '20/7', '21/7']

## vms-registre.html — 29/35 (83 %) — écran: lib/features/elevage/soins_vaccins_screen.dart
- **titres** 2/4 — absents: Dossier Clinique · Importer des Soins (CSV/Excel)
- **boutons** 6/10 — absents: Tester Rémanence · Résumé sanitaire · Imprimer · Modifier

## vms-suivi.html — 13/25 (52 %) — écran: AUCUN
- **titres** 1/3 — absents: Déclarer le Décès ? · Nouvelle Entrée Infirmerie
- **boutons** 3/6 — absents: Nouvelle Entrée Infirmerie · KPIs de l'Infirmerie · Confirmer le Décès
- **colonnes** 5/6 — absents: Lot / Sujet
- **etiquettes** 3/4 — absents: Lot / Sujet *
- **cartes** 1/5 — absents: Guéris (mois) · Sous Traitement · Décès (mois) · Taux d'Infirmerie
- **tableaux_manquants** 0/1 — absents: ["Date d'entrée", 'Lot / Sujet', 'Motif', "Niveau d'isolement"]
## Décisions d'architecture prises au ticket F0.72 (lead engineer, à confirmer par le client)

1. **Téléphone client facultatif** : le serveur l'accepte vide ; Laravel gagne sur les règles métier.
2. **« Détruire » = archiver** : aucune suppression définitive, aucun mot de passe inventé.
3. **Statut « Inactif » non porté** : aucune règle de « dernière activité » côté serveur.

## Agents du projet (`.claude/agents/`)

- `portage-ecran` : exécute un ticket de la Phase 3 de bout en bout.
- `planificateur-phase3` : découpe les items 7 à 10 (lecture seule).
- `suivi-rigoureux` : audit indépendant après chaque ticket (lecture seule, verdict chiffré).

## Décisions lead pour l'item 7 (historique-avances, liste-achats) — à confirmer par le client / le cabinet FAGUEZ

Autonomie accordée par le client (session F0.72). Aucune règle n'est inventée : chaque décision suit Laravel ou la recommandation du plan, et le point comptable est signalé « à valider cabinet ».

- D1 Ouvrir les comptes 419 (avances et acomptes reçus) et 409 (fournisseurs débiteurs) au plan comptable : OUI. **À valider cabinet.**
- D2 Une nouvelle avance entre en trésorerie (compte choisi) + écriture Débit trésorerie / Crédit 419 : OUI. Corrige un défaut web (l'argent d'un acompte n'entrait ni en caisse ni au journal).
- D3 Imputation d'un acompte : Débit 419 / Crédit 411, sans trésorerie : OUI.
- D4 Montant d'une avance non modifiable une fois entamée ou comptabilisée : OUI (le poste ne porte pas « Modifier »).
- D5 Archivage d'une avance refusé tant que le reste > 0 : OUI (contredit le web actuel, signalé).
- D6 Retour fournisseur = annulation complète de l'achat (Laravel + maquette) ; le partiel est un autre ticket.
- D7 Retour : contre-passation de l'écriture d'achat, part non payée de la dette annulée, part déjà payée = créance fournisseur (409). **À valider cabinet.**
- D8 Remboursement fournisseur plafonné à la créance fournisseur ouverte.
- D9 Références d'achat : pas inventées (tirets), comme F0.70.
- D10 Import xlsx / modèles à télécharger : retirés de la cible de fidélité (Laravel n'en a pas).
- D11 Droits : le SERVEUR exige `manage-ventes` (avances) et `manage-achats` (retours, remboursements). Visibilité des boutons par rôle : NON tranchée (RBAC).
- D12 Reçu d'acompte : non numéroté, mention « Reçu du poste », tant qu'aucune numérotation n'existe.

**F0.75 FAIT (09/10/2026)** — détail d'achat, Imprimer, Exporter PDF ; lecture seule, aucun changement serveur.
Ordre : F0.75 (détail d'achat, Imprimer, Exporter PDF — sans impact comptable) → 15.19 → F0.73 → 15.20 → F0.74 → F0.76.
Défauts web relevés par le plan (non encore corrigés) : `newAdvance`, `editAdvance`, `submitRefund`, `confirmReturnPurchase` sans `authorize` ; retour fournisseur non idempotent (double décrément possible) ; remboursement qui crédite la trésorerie sans écriture ; absorbeurs `avances`/`créances` du poste qui effaceraient une saisie en attente.

**15.19 FAIT (09/10/2026, Laravel uniquement)** — D1, D2, D3, D4, D5, D11 appliquées côté serveur ; ticket complet dans `README_SPRINT0.md`. Suite Feature : 693 verts (lancée avec `APP_TIMEZONE=UTC`, fenêtre 00:00–01:00). Pour F0.73 :
- `POST /api/sync/push` accepte `customer_advances[]` (`id`, `customer_id`, `treasury_account_id` obligatoire, `amount`, `advance_date`, `payment_mode` = `especes|mobile_money|virement|cheque`, `motif`) puis `advance_imputations[]` (`id`, `customer_advance_id`, `receivable_id` **ou `sale_id`**, `amount`, `imputation_date`), droit `manage-ventes`, `device_id` à la racine. Réponse `accepted` / `rejected` (`id` + `reason`) par table ; un renvoi est acquitté sans effet. Le poste n'envoie que le FAIT : plafond, trésorerie (deux livres), écritures D 5xx/C 419 et D 419/C 411 sont faits par le serveur.
- `customer_advances` n'est plus dans `referentiels_ignored` (cinquième exception) ; le tirage sert `treasury_account_id`, `payment_mode`, `motif`, `device_id` en plus des colonnes d'avant. `advance_imputations` ne descend pas.
- Une vente à crédit poussée crée désormais sa créance côté serveur (`receivables.sale_id`) : le poste peut imputer par `sale_id` une avance sur la créance d'une vente du même paquet. L'absorbeur `receivables` du poste devra fusionner sans écraser une imputation en attente.
- **À valider par le cabinet FAGUEZ** : compte 419 et les deux écritures. Le compte 409 n'est PAS encore ouvert (réservé au ticket sur les retours fournisseur).
- Constats ouverts côté serveur (README, ticket 15.19) : aucune route de remboursement d'avance (une avance avec reste et sans créance est inarchivable, D5) ; « Déduire de l'avance » de la caisse n'est branché sur rien ; numéros d'écriture dupliqués (`generateReference`) ; motif facultatif au serveur alors que la maquette le marque obligatoire.
- Restent des défauts web du plan non traités ici : `submitRefund`, `confirmReturnPurchase` (15.20).

**F0.73 FAIT (09/10/2026, Flutter, schéma v31)** — avances et imputations au poste, local d'abord ; contrat 15.19 respecté. Écarts relevés : le serveur sert les créances « dues OU modifiées depuis since » ; motif obligatoire au poste, facultatif au serveur ; MTN/Moov = `mobile_money`. Suite : 15.20 → F0.74 → F0.76.

**15.20a FAIT (09/10/2026, Laravel uniquement)** — (A) numéros d'écriture : `generateReference()` rend un gabarit, `AccountingEntryService::record()` attribue le numéro dans sa transaction depuis un compteur par exercice (`accounting_reference_sequences`) ; plus de doublon ni de trou, format `OD-AAAA-NNNN — libellé` inchangé pour les exports. Doublons déjà passés : commande de détection en lecture seule `php artisan comptabilite:doublons-references` (base locale vide, production à mesurer) ; leur renumérotation reste une décision du client et du cabinet. (B) `notifications.created_at` et `audit_logs.created_at` sont désormais écrits dans le fuseau de l'application (la déduplication de l'alerte d'autonomie cassait entre 00:00 et 01:00 heure du Bénin). Suite Feature : 710 verts, sans `APP_TIMEZONE=UTC`. Aucun impact sur le contrat `/api/sync/*`, hormis des `created_at` de notifications désormais à l'heure du Bénin. Détail et non-vérifié (MySQL, concurrence réelle) dans `README_SPRINT0.md`.

**15.20b FAIT (09/10/2026, Laravel uniquement)** — numéros d'écriture : le numéro suivant = max(compteur, plus grand numéro existant du journal et de l'exercice, lu au début de la référence) + 1 à CHAQUE attribution (une écriture manuelle passée après l'amorçage ne provoque plus de doublon) ; index non unique sur `accounting_entries.reference`. `accounting_reference_sequences` entre dans le module de sauvegarde « comptabilité » (avant `fiscal_years`) : exportée, vidée et restaurée avec les écritures (avant, sa clé étrangère faisait échouer le vidage de `fiscal_years`). Suite Feature : 717 verts. Aucun impact sur `/api/sync/*`. Non vérifié : MySQL, concurrence réelle. Détail dans `README_SPRINT0.md`.

**15.20 FAIT (09/10/2026, Laravel uniquement)** — D6, D7, D8, D11 appliquées côté serveur (retour fournisseur = annulation complète ; contre-passation ; compte 409 ; remboursement plafonné) ; ticket complet dans `README_SPRINT0.md`. Suite Feature : 770 verts, configuration par défaut. **À valider par le cabinet FAGUEZ** : compte 409, contre-passation, écriture Débit trésorerie / Crédit 409. Contrat pour F0.74 :
- Droit serveur : `manage-achats`. `device_id` à la racine de `POST /api/sync/push`. Le poste n'envoie que le FAIT ; il ne calcule ni stock, ni dette, ni créance, ni plafond.
- `purchase_returns[]` : `id` (uuid du retour, généré une fois), `purchase_id`, `reason` (obligatoire, ≤ 500), `return_date` (≤ aujourd'hui, pas antérieure à l'achat). Annulation COMPLÈTE : ni ligne ni quantité.
- `supplier_refunds[]` : `id` (uuid), `supplier_id`, `treasury_account_id` (obligatoire), `amount` (≥ 1), `refund_date`. Un montant supérieur à la créance ouverte est accepté mais plafonné par le serveur.
- Ordre de traitement serveur : achats → règlements fournisseurs → retours → remboursements → … → `stock_adjustments`. Le poste envoie l'achat AVANT (ou avec) son retour (sinon « Achat introuvable »).
- Réponse : `purchase_returns` et `supplier_refunds` → `accepted` (ids) / `rejected` (`id` + `reason`) ; un renvoi du même `id` est acquitté sans effet. Motifs : rôle sans `manage-achats` ; champ invalide ; achat introuvable ; « déjà été retourné » ; « Stock insuffisant … » ; exercice clos/absent ; « n'a pas d'écriture comptable » (achat de bon de commande ou antérieur à 14.24 : non retournable) ; compte 401/409 absent ; date future / antérieure à l'achat ; remboursement : « aucune créance ouverte », fournisseur / compte introuvable, « Écriture impossible ».
- **Jamais de `stock_adjustments` pour un retour** : le serveur décrémente ; une sortie désignant un retour (`reference_type` = `purchase_return`, ou `client_ref` = id de retour / d'achat retourné) est rejetée avec motif.
- Tirage : `purchases[].returned_at` (ISO ou null) et `purchases[].supplier_credit` (part payée devenue créance) ; `has_debt` passe à `false` pour un achat retourné et sa dette ne descend plus ; nouvelle clé `supplier_credits[]` (`supplier_id`, `supplier_name`, `open_credit`), sans filtre `since`, seulement les fournisseurs > 0. Les tables `purchase_returns` et `supplier_refunds` ne descendent pas.
- Absorbeur `purchases` du poste : fusionner `returned_at` / `supplier_credit` sans écraser un retour `pending` ; un achat `returned_at` non nul ne propose plus « Retour ».
- Constats ouverts côté serveur (README, ticket 15.20) : la réception d'un bon de commande ne passe aucune écriture (ces achats ne sont donc pas retournables) ; la dette annulée voit son `amount` ramené à `amount_paid` ; un remboursement hors retour n'a plus de voie (changement de comportement web à valider) ; KPI « Dépenses totales » inchangé.

**F0.74 FAIT (09/10/2026, Flutter, schéma v32)** — retour fournisseur et remboursement fournisseur au poste, local d'abord ; contrat 15.20 respecté. Le poste n'écrit que le fait (jamais de `stock_adjustments`, ni stock, ni trésorerie, ni dette, ni écriture). liste-achats 17/36 → 27/36 ; Flutter 1 143 → 1 189 verts ; Laravel 770 verts (inchangé). Écarts relevés : « Dépenses Totales » somme encore les achats retournés (le serveur gagne, légende au poste) ; « Écarts / Retours » compte des achats (le serveur : des lignes) ; 🔴 « Dettes en Cours » du poste est faux pour un achat reçu du serveur (`amount_paid` ne descend pas) — non corrigé. Détail et non-vérifié (vrai serveur, vraie base v31, résidu de créance nette si le tirage de confirmation échoue) dans `README_SPRINT0.md`. Suite : F0.76.


**15.21 FAIT (09/10/2026, Laravel uniquement, aucun code Flutter)** — (A) grand livre : le sens naturel des comptes de classe 4 était faux pour **409** (créance), **445** (TVA récupérable) et **419** (avances reçues, dette), ainsi que 281 et 139 ; règle unique `FinancialReportService::natureDebitrice`, nature décidée compte par compte (propositions à valider par le cabinet FAGUEZ ; ambigus listés : 4457, 4456, 73…). Bilan et Balance inchangés (non-régression testée). (B) la réception d'un bon de commande passe désormais par `RecordPurchaseAction` : une écriture (Débit 601 + 445 / Crédit 401) datée du jour de la RÉCEPTION, idempotente, dans la transaction du stock et de la dette ; exercice clos/absent ou compte manquant = refus sans résidu. **Effet pour le poste / F0.74** : un achat reçu APRÈS ce ticket redevient retournable ; les achats reçus AVANT restent refusés (« n'a pas d'écriture comptable ») et NE SONT PAS régularisés (décision cabinet) — liste en lecture seule : `php artisan comptabilite:achats-sans-ecriture` (base locale : 0, elle est vide ; production : inconnu). Le contrat `/api/sync/*` est inchangé. Reste côté poste, hors ticket : 🔴 « Dettes en Cours » faux pour un achat reçu du serveur (`amount_paid` ne descend pas). Suite Feature : 785 verts. Détail et non-vérifié (MySQL, concurrence, Bilan sur données réelles) dans `README_SPRINT0.md`.

**15.22 FAIT (09/10/2026, Laravel, aucun code Flutter)** — tout achat exige son écriture comptable, par tous les chemins (achat direct, réception de bon, achat rejoué d'un poste) ; compte manquant ou exercice clos/absent = refus sans résidu ; total nul refusé ; `EnregistrerAchat` n'a plus d'erreur 500 ; `pushPurchases` rejette avec motif au lieu de faire tomber l'envoi. Suite Feature : 801 verts. **À arbitrer client / cabinet** : le refus du total nul (dons, échantillons ?) est une prudence, pas une règle de Laravel. Non vérifié : MySQL, navigateur. Audit indépendant (`suivi-rigoureux`) NON fait.

**F0.77 FAIT (09/10/2026, Flutter, schéma v32)** — 🔴 « Dettes en Cours » corrigé (reste dû lu sur la dette servie ; « — » si aucune dette servie, jamais 0) ; `soldeDu` de la liste clients net des imputations en attente ; un achat refusé au push (15.22) devient visible (« Refusé par le serveur » + motif), « Relancer » fonctionne pour les achats, l'écran Synchronisation dit « Achat ». « Exporter » de `historique-avances` : déjà branché par F0.73, F0.76 n'a donc pas lieu d'être. Flutter 1 200 verts + 4 ignorés. Ouvert : le serveur ne sert pas `amount_paid` dans `purchases` ; un achat refusé compte encore dans « Dépenses Totales » et le badge « en attente » ; `expenses` et `attendance_records` sans entrée dans `relancer()`. Audit indépendant NON fait.

## Clôture de l'item 7 (09/10/2026)

État : liste-clients, historique-avances, liste-achats et ajouter-fournisseur portés ; tickets F0.71–F0.77 et 15.18–15.22. Mesures : Flutter 1 200 verts + 4 ignorés, `flutter analyze` propre, Laravel Feature 801 verts. Audits indépendants : CONFORMES pour F0.75, 15.19, F0.73, 15.20a, 15.20, F0.74 ; INCOMPLET pour 15.21 (scénarios prouvés, 14 mutations non rejouées) ; NON faits pour 15.22 et F0.77.

À arbitrer par le client / le cabinet FAGUEZ (rien n'a été tranché à leur place) : comptes 419 et 409 et leurs écritures ; renumérotation des doublons passés ; régularisation des achats reçus sans écriture ; montant de la dette annulée ; remboursement hors retour ; « Dépenses Totales » avec ou sans achats retournés ; total nul d'un achat ; visibilité des boutons par rôle (RBAC) ; contradictions inchangées (rôles 7/6/5/4, écrans 94/97/99, `comptabilite-hub.html` absent de `RBAC_PAGE_MAP`, cartes de documents-administratifs).
À mesurer en production : `php artisan comptabilite:doublons-references` et `php artisan comptabilite:achats-sans-ecriture`.
Suite : items 8 (documents-administratifs, archivage-documents, gestion-courriers), 9 (plan comptable, journal, grand livre, balance), 10 (pages sous 60 %).

## Plan de l'item 8 (09/10/2026, planificateur en lecture seule ; rien d'exécuté)

Constat : les trois pages sont en consultation pure au poste ; le serveur ne reçoit rien (`mails`, `administrative_documents`, `archived_documents` sont dans `referentiels_ignored`) ; les trois absorbeurs font `delete().go()` puis réinsèrent (ils effaceraient toute saisie en attente) ; la logique métier est dans les composants Livewire, sans service partagé ni test Feature. Aucune pièce jointe n'existe dans la maquette ni dans Laravel (pas de champ fichier à porter). Scores : archivage 9/21, documents 9/21, courriers 11/23 (strict, `RAPPORT_FIDELITE_2.md`, peut être en retard).

Défauts Laravel relevés (lecture de code ou `php -r`, non reproduits sur le modèle réel) :
- `ArchivedDocument::getStatusAttribute()` : `diffInDays` signé (Carbon 3.13.2) → toute échéance future est « Bientôt expiré ». Fausse la carte « Expirant sous 30j ».
- `Correspondence::generateReference()` : non atomique, et `substr(-3)` casse après 999 courriers (doublon).
- Faux positif de la fidélité : les trois pages partagent un fichier Dart, « En attente » de Documents satisfait la carte « En attente » de courriers.

Décisions provisoires du lead (appliquées en l'absence de réponse du client, à confirmer) :
- Q8.1/Q8.2 documents-administratifs : « Modèles disponibles » = « — » avec légende (aucune source honnête), « Générés (mois) » calculé comme le web, « En attente » en ajout assumé. Rien d'inventé.
- Q8.3 : libellé de la maquette « Générer un Document », comportement du registre web (aucun fichier généré). Risque de promesse trompeuse signalé.
- Q8.4 : listes de Type et de Catégorie de Laravel (contrat serveur).
- Q8.5 : carte « En attente » des courriers = « — » (aucun statut de courrier en base ; on n'en invente pas).
- Q8.6 : le défaut Carbon est un bug, corrigé sans attendre (seuil 30 j) ; la scission « Expirés » / « À renouveler » du poste reste, seuil de « À renouveler » à confirmer (60 j actuel).
- Q8.7 : export PDF des trois pages par `ExportOfficiel` (ticket séparé).
- Q8.8 RBAC : NON tranché. Seul `admin` a `manage-administration` ; appliqué tel quel.

Tickets, dans l'ordre (un ticket = une session) : 8.1 gestion-courriers (pose le gabarit : service partagé, push, absorbeur par fusion, référence atomique ; référence « — » au poste jusqu'à l'acquittement) → 8.2 archivage-documents (corrige le bug Carbon) → 8.3 documents-administratifs (cartes, libellés ; sort la page de `ecartsATraiter`) → 8.4 export PDF des trois pages. Les prompts détaillés sont dans le rapport du planificateur, à ressaisir à chaque lancement.
**15.23 + F0.78 FAITS (09/10/2026) — ticket 8.1 gestion-courriers.** Serveur : service partagé `CourrierService`, `pushMails`, référence robuste au-delà de 999, tirage avec `is_active` et `updated_at` ; Feature 825 verts. Poste (Drift v33) : courriers saisis/modifiés/archivés en local d'abord, absorbeur par fusion, rejet visible, relance ; Flutter 1 243 verts + 4 ignorés ; fidélité de la page 11/23 → 21/23 strict (reste « Exporter PDF », ticket 8.4, et l'accordéon mobile). Ouvert : `pendingCount` ignore encore produits, fournisseurs, clients, avances, imputations, retours, remboursements ; l'absorbeur suppose un tirage complet des actifs ; pastilles « À envoyer » / « Refusé » et date bornée 2000–2100 = choix du poste ; visibilité Modifier/Archiver par rôle non tranchée. Non vérifié : push réel, MySQL, visuel. Audit indépendant : CONFORME AVEC RÉSERVES (10 mutations rejouées sur copie, toutes tuées) ; défaut trouvé et corrigé en **F0.78-bis** (Drift v34, `known_by_server`) : créer puis archiver hors ligne produisait un conflit permanent invisible ; l'archivage refusé reste maintenant visible (« Archivage refusé » + motif) ; acquittement des courriers comparé à la version envoyée. Flutter 1 254 verts + 4 ignorés. Ouvert : réponse serveur perdue puis archivage avant acquittement (le courrier réapparaît actif) ; pas de geste de résolution d'un archivage refusé hors écran Synchronisation ; acquittement par id seul resté tel quel pour les autres tables (correction propre = version par ligne) ; correction F0.78-bis non auditée.

**15.24 + F0.79 FAITS (09/10/2026) — ticket 8.2 archivage-documents.** Serveur : défaut Carbon corrigé (règle unique `ArchivedDocument::statutPour`, seuil 30 j, jours calendaires), `ArchiveDocumentService`, `pushArchivedDocuments` ; Feature 858 verts. Poste (Drift v35) : archives en local d'abord, absorbeur par fusion, `known_by_server`, retrait refusé visible ; Flutter 1 335 verts + 4 ignorés ; fidélité de la page 10/21 → 19/21 strict (reste « Exporter PDF », ticket 8.4, et l'accordéon mobile). Décisions du lead : +31 j = Valide (la maquette décale d'un jour), échéance aujourd'hui = Expiré, carte « Expirés » gardée (écart assumé), catégories de Laravel, date d'archivage ajoutée à la modale, catégorie ≤ 100 car. (colonne serveur `string(100)` sans `max` côté validation : trou serveur à fermer). Écart de méthode : les tests rouges n'ont pas précédé le code côté poste (prouvés après coup par mutation). Ouvert : `modifierCourrier` ne purge peut-être pas l'entrée `sync_conflicts` d'un courrier corrigé (corrigé pour les archives, courriers non vérifiés) ; absorbeur strict : une ligne héritée invalide refuse tout le tirage. Audit indépendant : CONFORME AVEC RÉSERVES (Carbon recalculé sur 108 cas sans écart ; 15 mutations Flutter + 12 Laravel rejouées sur copie, toutes tuées). Trois défauts de motifs de refus périmés (`sync_conflicts`) trouvés et corrigés en **F0.79-bis** : `modifierCourrier`, `_acquitter` (purge à l'acceptation, toutes tables, par table:id), `retirerArchive`/`archiverCourrier` d'un enregistrement en conflit. Flutter 1 345 verts + 4 ignorés. Non vérifié : purge testée sur courriers, archives et clients seulement ; correction pendant l'envoi d'une ligne déjà refusée ; F0.79-bis non auditée ; dernier écrivain gagne (pas de version par ligne) ; fuseau multi-postes ; push réel.

**15.25 + F0.80 FAITS (09/10/2026) — ticket 8.3 documents-administratifs.** Serveur : `DocumentAdministratifService`, `pushAdministrativeDocuments`, helper unique `veutRetirer()` pour `is_active` des TROIS tables (false/0/"0" = retrait ; valeur absurde = refus avec motif ; change aussi le comportement de mails et archives pour 0/"0") ; Feature 894 verts. Poste (Drift v36) : même gabarit que courriers/archives avec toutes les leçons (known_by_server, purge des refus, acquittement comparé), tests rouges d'abord (65 rouges sur 73), 98 mutations annoncées tuées ; Flutter 1 419 verts + 4 ignorés ; fidélité de la page 10/21 → 19/21 strict ; global 1 321/2 099 (62,9 %). La divergence de cartes de documents-administratifs (point 1 de « Known weaknesses ») est RÉSOLUE par décision provisoire du lead : « Modèles disponibles » = « — » (aucune source), « Générés (mois) » calculé, « En attente » ajout assumé ; la page quitte `ecartsATraiter` (vide) ; CLAUDE.md mis à jour. Décisions du lead à confirmer : bouton « Générer un Document » qui n'écrit qu'une ligne de registre (légende « ne produit aucun fichier » ajoutée), modale avec titre et statut (absents de la maquette, exigés/portés par le serveur), type plafonné à 100 au poste. Ouvert : trou serveur `type`/`category` sans `max:100` (500 sous MySQL strict) ; exemptions globales périmées dans `fidelite_libelles_test.dart` masquant de la couverture (à nettoyer) ; `pendingCount` incomplet ; code mort `vide:` de `_tableau`. Audit indépendant : CONFORME AVEC RÉSERVES (veutRetirer rejoué sur les 3 tables ; 17/17 mutations Flutter et 9/10 Laravel rejouées ; « Générés (mois) » recalculé à la main, sans écart). Suites : **15.26** (Laravel, Feature 1 029 verts) — tests `is_active` 1/"1", `max:100` sur `category` et `type`, clés de push non tableau (500 → `cles_invalides`), commentaire périmé, Corbeille examinée (restauration vue du poste) ; **F0.81** (Flutter, 1 421 verts + 4 ignorés) — 14 exemptions globales périmées retirées (18 contrôles réactivés, tous verts), garde-fou « aucune exemption globale entièrement périmée » + plafond chiffré de 268 manques masqués (ne peut que baisser), 18 entrées migrées par page avec motif daté, code mort `vide:` retiré, score strict inchangé 1 321/2 099. Écart à ARBITRER : `feuille-pointage.html` attend un champ « Date * » dans la modale de pointage, l'écran ne le porte pas. Dette restante : 268 couples (page, libellé) masqués par des exemptions globales (dont « Indicateurs de performance » 24 pages, « Annuler » 15, « Enregistrer » 11, « Fermer » 9) ; 7 anciennes tables de `/sync/push` répondent encore 500 sur une ligne non-objet (ticket Laravel dédié à ouvrir, elles portent des opérations comptables) ; F0.81 et 15.26 non audités.

Non vérifié par le planificateur : aucun test exécuté, `HISTORIQUE_SESSIONS_CLAUDE.md` et le skill non lus en entier, titres de PDF de deux pages non lus, état des boutons Modifier/Archiver au poste non relu.

**15.26 + F0.81 + F0.82 FAITS (09/10/2026) — clôture du ticket 8.3 et ticket 8.4 (export PDF).** 15.26 : durcissement du push d'administration (`max:100`, clés non tableau écartées et signalées en `cles_invalides`) ; F0.81 : 14 exemptions globales périmées retirées, 18 migrées par page, deux garde-fous (plafond `plafondManquesMasques` = 268, ne peut que baisser). F0.82 : « Exporter PDF » des trois pages (`documents_administration.dart`, `ExportOfficiel` avec `polices`, pied des trois structures), lignes exportées = lignes actives affichées, « — » pour une donnée absente ou une référence de courrier non attribuée. Mesuré par moi : `flutter analyze` propre, 1 439 tests verts + 4 ignorés, README identiques (`97C8BC87…`), ticket présent une fois. Fidélité stricte globale 1 321 → 1 324 / 2 099 (63,1 %). Le plafond reste à 268 (les trois exemptions retirées étaient par page). Décisions à valider par le client : liste vide = message sans document ; lignes actives non encore acquittées exportées avec mention en pied (ajout du poste, absent de la maquette).
Non vérifié : aucune impression ni écriture réelle, rendu visuel du PDF non regardé, recherche/filtre/pagination de la maquette non portés (l'export reprend toute la liste), exécutable release non reconstruit, fuseau non exercé. 43 mutations annoncées tuées par l'agent, non rejouées par moi. Audit indépendant de F0.81/F0.82 : à lancer.

**Audit indépendant de F0.81 + F0.82 (09/10/2026) : CONFORME AVEC RÉSERVES, aucun défaut bloquant.** Titres, colonnes et ordre conformes aux trois fonctions de la maquette ; polices passées ; 6 mutations F0.81 tuées ; 12 mutations F0.82 tuées sur 15. Réserves : (a) `_exporter` ne capture pas une exception de l'éditeur (erreur asynchrone sans message) ; (b) trois mutations survivantes : jour même / frontière 30-31 j de `statutArchive`, `trim` de `_texte` (espaces seuls), pied « lignes saisies sur ce poste » avec une ligne active en `conflict` ; (c) formulation « lignes = affichées » inexacte, car l'export exclut les lignes inactives en conflit pourtant affichées. Corrections confiées au ticket F0.82-bis. Non vérifié par l'auditeur : impression et rendu réels, 43 mutations de l'agent non rejouées, plafond compensable (un ajout et un retrait simultanés d'exemptions globales laissent 268).

**F0.82-bis FAIT (09/10/2026) — réserves de l'audit corrigées.** Exception de l'éditeur capturée (message « L'édition du document a échoué. Réessayez ou vérifiez l'imprimante. », nouveau et générique), verrous de test pour le jour même et les frontières +30/+31 j (à 23 h 30), les valeurs en espaces seuls et le pied de page avec une ligne active en `conflict` ; 9 mutations tuées, fichiers restaurés par empreinte. Mesuré par moi : analyse propre, 1 446 verts + 4 ignorés, README identiques (`81806CD5…`), en-tête présent une fois.

**Clôture de l'item 8 (09/10/2026).** Livrés : 8.1 courriers, 8.2 archives, 8.3 documents administratifs, 8.4 export PDF des trois pages. Restent ouverts : décisions client (libellés, cartes, listes de catégories, seuil +31 j, pied de page du poste, liste vide, RBAC `manage-administration`), message d'échec d'export non détaillé, impression et rendu PDF jamais vus, F0.82-bis et 15.26 sans audit indépendant, 7 anciennes tables de `/sync/push` qui répondent 500 à une ligne non objet, 268 couples masqués par des exemptions globales. Items 9 (comptabilité) et 10 (pages < 60 %) non démarrés.

**Item 9, phase A FAITE (10/10/2026) — 15.27 + F0.83 : import du plan SYSCOHADA révisé (insertion seule).** Source imposée par le client : `C:\Projects\plan-comptable-syscohada-revise.csv.txt` (1 332 comptes, copie octet pour octet dans le dépôt Laravel, SHA-256 `4103f4ef…`). Import de 1 301 comptes (31 des 36 comptes de la ferme y figurent déjà, 5 absents : 313, 521101, 521201, 606, 657) ; aucun compte existant modifié. Poste : reçoit par synchronisation, aucune copie embarquée. Mesuré par moi : Laravel Feature 1 052 verts (1 029 + 23), `flutter analyze` propre, 1 454 verts + 4 ignorés, README identiques (`31BB53F2…`), `docs/` et `prototype_html/` vides. Décision client : les 12 comptes de sens différent seront REMAPPÉS vers les comptes officiels (phase B), table à valider par le cabinet FAGUEZ (`mapping_plan.md`, `risques.md`, scratchpad).
Corrections minimales faites : Rapprochement bancaire et Immobilisations gardent leurs comptes d'avant import (provisoire : pas de bien sur une nouvelle nature du CSV), Plan Comptable web paginé par 200, tri de la recherche globale, Grand Livre du poste ouvert sur le premier compte mouvementé, `label` élargi de 150 à 255 (à confirmer).
À faire corriger par le cabinet : libellés 54, 66, 603 (phrases de note) et une trentaine avec notes « (1) ». Ouvert : `natureDebitrice` fausse pour 109, 119, 129, 47x, 48x, 56, 82… (règle comptable absente du prototype et de Laravel, non inventée) ; sélecteurs de saisie manuelle à 1 337 comptes ; phase B.
Non vérifié : production, performance (pull de 1 337 lignes, sélecteurs), rendu visuel, tirage réel `sync_reel_test`, PDF du plan, aucun audit indépendant ; 22 + 7 mutations annoncées tuées, non rejouées par moi.

**Audit indépendant de la phase A (10/10/2026) : CONFORME AVEC RÉSERVES, aucun bloquant.** 1 301 comptes créés, 36 comptes de la ferme inchangés, idempotence, absorbeur strict confirmés ; 24 mutations, 19 tuées. Réserves traitées par **15.27-bis** (libellé ≤ 255 validé avant écriture, garde-fou `NatureComptesTiersTest` rétabli via `ChartOfAccountsSeeder::comptesDeLaFerme()`, ligne vide verrouillée, tri des parents, ordre du seeder, largeur de colonne). Mesuré par moi : Laravel Feature 1 060 verts, analyze propre, Flutter 1 454 + 4 ignorés, README identiques (`ACA9417E…`).
**OUVERT A2 (décision du cabinet FAGUEZ, phase B)** : `ModesPaiement` crée une banque au code par défaut `521` (désormais « BANQUES LOCALES », regroupement) et un Mobile Money au `5212` (désormais « Banque Y ») ; les Actions de comptabilisation posteraient sur un compte de regroupement ou fictif pour toute NOUVELLE ligne de trésorerie. Caractérisé par un test, non corrigé. Ferme actuelle (531/521101/521201) non touchée.

**Item 9, T1 FAIT (10/10/2026) — 15.28 + F0.84 : écritures comptables du poste.** Défaut CONFIRMÉ par tests rouges : une écriture archivée (ou supprimée physiquement) restait au poste ; une écriture modifiée gardait ses anciennes lignes (montants doublés dans Journal, Grand Livre, Balance). Défaut aggravant trouvé : `updateManual` ne touchait pas `updated_at` quand ni date ni référence ne changeaient, l'écriture n'était pas servie au tirage `since` (`touch()` ajouté). Contrat : nouvelle clé de pull `accounting_entry_ids` (ids de toutes les écritures actives, sans filtre `since`), une écriture servie arrive avec toutes ses lignes courantes, le poste remplace les siennes (`_absorberJournal`, une transaction, strict) ; ancien serveur sans la clé = aucune purge. Schéma Drift inchangé (v36). Mesuré par moi : Laravel Feature 1 071 verts, analyze propre, Flutter 1 479 + 4 ignorés, README identiques (`070FCC6F…`). 22 mutations annoncées (21 tuées, survivante : découpage par paquets de 500), non rejouées par moi.
Non vérifié : tirage réel `sync_reel_test`, MySQL, production (le site en ligne n'a pas 15.28 : pas de purge contre lui), performance, rendu, atomicité sur panne réelle. Ouvert : course d'horloge générale du protocole (`server_time` tronqué à la seconde, filtre `updated_at > since`) ; aucun écran de restauration d'écriture. Aucun audit indépendant. Reste à faire : T2 grand livre (nature du compte), T3 balance, T4 exports PDF, T5/T6 selon Q1–Q3, T7.

**Audit indépendant de T1 (10/10/2026) : CONFORME AVEC RÉSERVES, aucun bloquant nominal.** Défaut reproduit puis corrigé (calcul indépendant à la main concordant). Réserves traitées par **15.28-bis + F0.84-bis** : import de module « comptabilité » (écritures réimportées désormais servies : `updated_at` = instant de l'import pour ces deux tables), id actif absent au poste (relance unique sans `since`, sinon journal marqué incomplet et avertissement affiché), liste vide (pas de purge au premier tirage, purge à la seconde annonce identique ; limite : un serveur durablement vide finit par vider le poste), tests des mutations survivantes, volume (33 000 écritures, paquets de 5 000 côté serveur), resynchronisation unique du journal pour les postes déjà doublés (`journal_resync_f084bis`), refus de NaN/Infinity et des identifiants non UUID. Mesuré par moi : Laravel Feature 1 078 verts, analyze propre, Flutter 1 500 + 4 ignorés, README identiques (`2E2E9824…`). 30 mutations annoncées tuées, non rejouées par moi.
**À DÉCIDER (règle comptable absente du prototype et de Laravel)** : un montant de ligne NÉGATIF est accepté par l'absorbeur, non figé par un test. Ouvert : un journal refusé durablement bloque les 14 absorbeurs suivants ; la course d'horloge générale du protocole ; limite ~65 000 placeholders MySQL côté poste non applicable. Non vérifié : MySQL, `sync_reel_test`, production, rendu, tirage de confirmation compté comme second tirage vide, aucun nouvel audit indépendant.

**Item 9, T2 FAIT (11/10/2026) — 15.29 + F0.85 : Grand Livre du poste.** Nature débitrice/créditrice du compte reprise fidèlement de `FinancialReportService::natureDebitrice` (test de parité qui exécute le vrai PHP sur les 1 332 codes ; non corrigée pour les comptes importés douteux 109, 129, 1291, 471, 472, 478, 481, 485, 561, 564, 82, 84, 86, 88), solde d'ouverture calculé comme Laravel (« — » avec raison si le compte n'a pas d'écriture ou si le journal est incomplet), compte par défaut 531 puis plus petit code, période par défaut 1er du mois → aujourd'hui, schéma Drift **v37** (`accounting_entries.created_at` nullable, servi par le serveur, départage l'ordre). « Exporter PDF » du grand livre NON fait (T4). Mesuré par moi (12/10/2026) : `flutter analyze` propre, Laravel Feature 1 087 verts (13 580 assertions), Flutter 1 552 verts + 4 ignorés, aucun `flutter_tester` resté actif, README identiques (`B90E64CF…`). 43 mutations annoncées par l'agent, non rejouées par moi ; tests de synchronisation écrits après le code.
Non vérifié : MySQL, production, `sync_reel_test`, rendu réel, `flutter build windows`, performance, fuseau (Windows vs `Africa/Porto-Novo` ; serveur sans `APP_TIMEZONE` = UTC). Aucun audit indépendant de T2 (ni de 15.27-bis, 15.28-bis/F0.84-bis) : à lancer.

**Audit indépendant de T2 (12/10/2026) : CONFORME AVEC RÉSERVES, aucun bloquant.** `natureDebitrice` relue ligne à ligne contre `nature_compte.dart` : identiques. Recalcul à la main sur un jeu propre à l'auditeur (411 : ouverture 7 500,25 ; soldes 7 700,35 → 8 401,01 ; 419 sans écriture = quatre « — », jamais 0) concordant avec l'écran. 15 mutations rejouées sur copie, 15 tuées par assertion. Dépôts non modifiés (empreintes identiques). **À CORRIGER (défaut réel, non documenté au ticket)** : la migration v37 plante sur une base en v19 (`duplicate column name: created_at`), car le palier v20 crée `accounting_entries` avec le schéma courant qui contient déjà la colonne ; même défaut déjà présent avant v19 (`mails`/`isActive`, v33). Remarques : sélecteur de dates `showDatePicker` Material (voile `black54`, pas `afficherModale`), `trim()` de la recherche non comparé au serveur. Non vérifié par l'auditeur : suites complètes, 8 mutations serveur, « 30 rouges sur 37 », MySQL, rendu, fuseau.

**F0.85-bis FAIT (12/10/2026) — migrations Drift depuis toutes les versions.** Défaut plus large que signalé : 23 colonnes sur 29 `addColumn` rejouaient une colonne déjà créée par un `createTable` antérieur ; 19 versions de départ sur 36 (v1 à v19) plantaient. Correctif : `_ajouterColonneSiAbsente` (29 appels, un seul `m.addColumn(` restant), schéma final inchangé (v37). Nouveau `test/migration_toutes_versions_test.dart` (38 tests : v1 à v36 comparées au schéma d'une base neuve + garde-fous). 3 mutations tuées, annoncées par l'agent, non rejouées par moi. Mesuré par moi : analyze propre, Flutter 1 590 verts + 4 ignorés, aucun `flutter_tester` actif, README identiques (`4A782EA7…`), en-tête une fois, `app_database.dart` `57E05391…`, `docs/`/`prototype_html/` vides. Non vérifié : vraie base ancienne d'un poste, conservation des données sur les 36 chemins, contraintes CHECK, migration interrompue, `flutter build windows`. Aucun audit indépendant de F0.85-bis.

**Item 9, T3 FAIT (12/10/2026) — F0.86 : Balance Générale du poste.** Défauts de l'ancienne balance (33 tests rouges sur 35 avant code) : pas de période (cumul de tout le journal), ouverture toujours « — » avec une mention fausse depuis 15.29, carte « Écart », bandeau « Balance Déséquilibrée », ligne TOTAUX et sous-titre absents, zéros mal rendus (la maquette et le web écrivent « — »). Livré : calcul repris de `FinancialReportService::balanceGenerale` (ouverture nette sur une colonne, mouvements bruts, solde final net placé selon son signe, compte retiré si ouverture nulle et aucun mouvement, tri de chaînes, arrondi au centime, équilibre si écart < 0,01), périodes « mois » / « exercice » comme le web, cumul « avant le début » partagé avec l'ouverture du Grand Livre, `nature_compte.dart` volontairement non utilisé (le serveur ne s'en sert pas ici), 3 `CarteKpi` (écart assumé : la carte Écart de la maquette n'a pas de liseré), tableau à deux niveaux (8 colonnes feuilles). Laravel : aucun code, un test de parité (`BalanceJeuDuPosteTest`, 5 tests). Mesuré par moi : analyze propre, Laravel Feature 1 092 verts (13 599 assertions), Flutter 1 626 verts + 4 ignorés, aucun `flutter_tester` actif, README identiques (`76607C98…`), en-tête une fois, `docs/`/`prototype_html/` vides. 23 + 2 mutations annoncées tuées, non rejouées par moi. Export PDF = T4.
**À DÉCIDER (client)** : journal vide (poste « — », serveur « 0 F ») ; journal incomplet (ouverture, solde final et écart « — », pas de bandeau) ; compte absent du plan reçu (gardé en fin, code « — » ; le serveur le trie à son code) ; seuil d'écart (maquette < 1 F, Laravel < 0,01 : Laravel appliqué) ; teinte de la carte Écart (variante de `CarteKpi` non créée) ; exercice ouvert sans dates au poste.
Non vérifié : rendu réel, `flutter build windows`, `sync_reel_test`, MySQL (parité sqlite seulement), fuseau autour de minuit le dernier jour du mois, performance, rang de la ligne « compte absent ». Aucun audit indépendant de F0.86.

**Audit indépendant de T3 (12/10/2026) : CONFORME AVEC RÉSERVES, aucun bloquant.** `balanceGenerale` relue ligne à ligne (Laravel l.385-457 / poste l.371-443) : correspondance totale. Jeu propre à l'auditeur (année bissextile, bornes à 23:59:59 et 00:00, codes 1/10/101/4111, compte à zéro avec mouvements, journal vide/incomplet) : 8 tests poste verts ET même jeu rejoué sur le vrai service PHP concordant (13 assertions) ; « — » jamais 0. 23 mutations rejouées sur copie, 23 tuées ; M13 survit sans le test ajouté (récit exact). Grand Livre non régressé. **À CORRIGER (mineur)** : écart négatif de valeur absolue < 0,5 F affiché « -0 F » au poste, « 0 F » au web. Remarques : arrondi au demi-centime différent de PHP (`1.005`), non atteignable avec des montants à 2 décimales ; écart positif < 0,5 F affiché « 0 F » en rouge avec bandeau (parité avec le web, trompeur) ; libellé d'un exercice sans dates (cas impossible côté serveur). La section « balance-generale.html — 12/13 » (l.345) est la mesure historique de la phase 1, non mise à jour (le 11/12 actuel est dans le rapport de fidélité). Non vérifié par l'auditeur : suite Flutter complète, 2 mutations serveur, « 33 rouges sur 35 », MySQL, fuseau, rendu.

**F0.86-bis FAIT (12/10/2026) — montant arrondi à zéro sans signe.** 14 des 15 formateurs de montants affichaient « -0 » pour -0,4 (PHP `number_format` : « 0 ») ; correctif identique `x.round() < 0`, 3 tests Balance/Grand Livre + `montant_signe_test.dart` (garde-fou sur le source). 8 mutations annoncées tuées, non rejouées par moi. Mesuré par moi : README `A794C020…` identiques, 15 occurrences du correctif, analyze propre ; le total Flutter n'a été mesuré qu'avec F0.87 (1 669 = 1 636 + 33, cohérent). **Hors périmètre, à ouvrir** : `toStringAsFixed(0)` produit aussi « -0 » (GMQ, grammages des fiches d'élevage). **À DÉCIDER** : écart positif < 0,5 F affiché « 0 F » en rouge avec bandeau (parité web, trompeur) ou afficher les centimes.

**Item 9, T4 FAIT (12/10/2026) — F0.87 : « Exporter PDF » des quatre pages comptables.** Journal, Grand Livre, Balance, Plan : constructeurs purs (`documents_comptabilite.dart`) alimentés par les objets affichés et les mêmes formateurs que l'écran (aucun recalcul), période exportée = période affichée, « — » jamais 0, polices Roboto (0 glyphe manquant), pied des trois structures via `EditeursRapports`, exception de l'éditeur capturée. Défaut corrigé au passage : « N° Pièce » du Journal affichait le type de source (`sale`), `decouperReference` unique pour Journal et Grand Livre. Les 4 exemptions « Exporter PDF » retirées ; `plafondManquesMasques` inchangé à 268 ; fidélité stricte 1 325 → 1 332 / 2 099 (+4 réels, +3 faux positifs sur `cloture-exercice`, `comptabilite-analytique`, `rapprochement-bancaire`). Mesuré par moi : analyze propre, **Flutter 1 669 verts + 4 ignorés**, aucun `flutter_tester` actif, README identiques (`70D148B8…`), en-tête une fois, `docs/`/`prototype_html/` vides ; Laravel non touché (1 092 au dernier relevé, non relancé). 29 mutations annoncées tuées (1 survivante initiale M28 corrigée), non rejouées par moi.
**À DÉCIDER (client)** : lignes « Solde d'ouverture » / « Totaux de la période » (Grand Livre) et TOTAUX + mention d'écart (Balance) reprises du web, absentes de la maquette ; libellés maquette retenus contre le web (« Solde », « Ouv. D ») ; dates du sous-titre en JJ/MM/AAAA ; écriture incomplète écrite « 700 (incomplète) » ; document sans ligne non édité (le web éditerait un Grand Livre à ouverture connue sans mouvement) ; Excel sur ces pages. Écarts signalés non corrigés : colonnes Débit/Crédit du Journal (tous les codes vs premier compte), colonne Classe du Plan (« 4 » vs « 4 - Tiers »), pas de limite à 100 lignes, carte « Écritures (mois) » sur `DateTime.now()`.
Non vérifié : impression et rendu réels (aucun appel à `Printing.layoutPdf`), pagination de ~1 337 comptes ou d'un gros journal, largeur des 8 colonnes, texte du flux PDF non relu, place du bouton en petite largeur, `flutter build windows`, `sync_reel_test`, performance. Un premier lot de tests s'est arrêté (« did not complete » sur `fidelite_libelles_test`), cause non établie. Aucun audit indépendant de F0.86-bis ni de F0.87.

**Audit indépendant de F0.86-bis + F0.87 (12/10/2026) : CONFORME AVEC RÉSERVES, aucun bloquant.** Titres, sous-titres et colonnes des 4 PDF conformes aux `exportXxxPDF` de la maquette ; écarts déclarés exacts ; jeu propre à l'auditeur (décimales, écriture à 3 lignes, référence contenant « — », compte sans écriture, écriture incomplète) : chaque cellule du PDF = cellule de l'écran, valeurs confirmées contre PHP 8.3.30 (`number_format`) ; texte réel de 5 PDF extrait par `pdftotext` (« — », « ’ », « É » présents, pied des trois structures). 18/29 mutations F0.87 et 6/8 de F0.86-bis rejouées sur copie, toutes tuées (M28 comprise) ; `audit_fidelite` 1 332/2 099 reproduit octet pour octet, plafond 268 exact ; dépôts inchangés (179 fichiers lib/test par empreinte). **À CORRIGER (mineur, trous de test)** : P1 `montantOuTiret` `> 0` → `>= 0.5` survit (un montant de 0,4 F afficherait « — » au lieu de « 0 ») ; P2 nombre d'écritures incomplètes figé à « 1 » dans la note de pied survit (aucun test à 2). Remarques : 16e formateur `saisie_depenses_screen.dart` l.592 (`_montantFormate`, sans `abs()`) hors garde-fou, et signe en dur `'-${montant(...)} FCFA'` (`rapports_repository.dart` l.253) → « -0 FCFA » pour 0,4 F (théorique : dépenses positives) ; empreintes finales de `balance_poste_test` (`1dcef312…`) et `grand_livre_poste_test` (`132ee3c3…`) non consignées par F0.87 ; `solde`/`total` de la Balance dupliqués écran/document (cohérence tenue par les tests écran = PDF) ; `trim()` Dart retire l'espace insécable, pas celui de PHP ; le texte du PDF SE RELIT (`pdftotext`) : le contrôle automatique est possible. Non vérifié : suite complète, 11/29 et 2/8 mutations, rendu, impression, MySQL.

**F0.87-bis FAIT (12/10/2026) — trous de test de l'audit.** Aucun code de production modifié ; `export_comptabilite_test.dart` passe de 33 à 43 tests : montant de 0,4 F → « 0 » (écran, document, PDF relu), deux écritures incomplètes (note « 2 écriture(s) »), et un lecteur du TEXTE des flux PDF (zlib de `dart:io` + table de caractères des polices, sans nouvelle dépendance, calé sur `pdf` 3.12.0) qui vérifie titre, sous-titre, colonnes, lignes dans l'ordre et note de pied. 10 mutations annoncées tuées (dont les 2 survivantes de l'audit ; M4 en partie par plantage), non rejouées par moi. Mesuré par moi : analyze propre, **Flutter 1 679 verts + 4 ignorés**, aucun `flutter_tester` actif, README identiques (`B4BD151C…`), en-tête une fois, test `D9402636…`. Empreintes de `balance_poste_test` (`1dcef312…`) et `grand_livre_poste_test` (`132ee3c3…`) consignées. Constat non testé : une écriture incomplète reçue au seul crédit s'imprimerait « 0 (incomplète) ». Non vérifié : position du texte sur la page, documents de plusieurs pages, rendu et impression réels, montée de version du moteur PDF. Fin de l'item 9 hors décisions client : restent T5/T6 (Q1–Q3) et T7.

**ARBITRAGES CLIENT (12/10/2026), première série.** Q1 plan comptable : **modifiable au poste, création ET modification** (choix le plus risqué ; la recommandation était lecture seule : à traiter par un ticket T5 dédié, avec règles de conflit de code/libellé/nature et impact sur les écritures existantes). Q2 écritures manuelles hors ligne : **création, modification ET archivage** (la recommandation était création seule ; dernier écrivain gagne, conflits visibles). Q3 droits : **comptable et admin** (contradiction `comptabilite-hub.html` absent de `RBAC_PAGE_MAP` signalée, non résolue). Montant négatif : **règle du serveur d'abord** — formulaire web `JournalComptable::save` : `amount` requis, numérique, `min:1`, deux comptes différents et existants, date requise, libellé ≤ 255, ability `manage-comptabilite` ; une écriture manuelle = UNE ligne débit + UNE ligne crédit du même montant ; `AccountingEntryService::create` ne contrôle que l'équilibre (< 0,01) et pas le signe des lignes. **Deuxième série (13/10/2026) :** montant de ligne négatif reçu = **ACCEPTÉ** (l'absorbeur ne le refuse pas ; à verrouiller par un test, sans refus) ; modes de paiement 521/5212 (A2) = **attendre le cabinet FAGUEZ**, aucun changement ; petit écart de balance (< 0,5 F) = **afficher les centimes** (écart assumé vs web, à faire : ticket F0.88) ; PDF comptables = **libellés alignés sur le web** (« Solde Progressif », « Ouv. Débit », sous-titres « État au … » du web ; à faire dans F0.88). Le formulaire de SAISIE du poste (T6) reprend la structure du web (une ligne débit + une ligne crédit, comptes différents et existants, libellé ≤ 255, date requise) ; le minimum de 1 F à la saisie n'a pas été tranché explicitement : à confirmer à T6.

**F0.88 FAIT (13/10/2026) — arbitrages client : écart avec centimes, libellés des PDF alignés sur le web.** `DocumentsComptabilite.montantEcart` (écart nul « 0 » ; sinon francs groupés, virgule, deux centimes : « -0,40 », « 1 500,00 » ; signe lu sur les centimes arrondis, jamais « -0 ») sur la carte « Écart » et la mention du PDF de la balance ; seuil d'équilibre inchangé (< 0,01) ; autres montants au franc ; écart assumé vs web documenté dans `cartes_attendues.dart`. PDF alignés sur le web (lecture des 4 `exports/*.blade.php`) : sous-titres « État au JJ/MM/AAAA » (plan, journal), « Solde Progressif » (grand livre), « Ouv. Débit » … « Final Crédit » et mention « Balance déséquilibrée — écart de X FCFA. … » (balance) ; écrans inchangés (maquette) ; test de colonnes scindé PDF/web et écran/maquette. Mesuré par moi : analyze propre, **Flutter 1 689 verts + 4 ignorés**, aucun `flutter_tester` actif, README identiques (`818DF073…`), en-tête une fois, `documents_comptabilite.dart` `AEA58E47…`, `docs/`/`prototype_html/` vides ; Laravel non touché (1 092 au dernier relevé). 18 mutations annoncées tuées, non rejouées par moi ; `audit_fidelite` 1 332/2 099 et plafond 268 inchangés selon l'agent.
Ouvert : unité « FCFA » (mention PDF) vs « F » (carte) ; toujours deux décimales pour un écart non nul ; non alignés (contenus de cellules) : classe du plan, colonnes Débit/Crédit du journal, suffixe « FCFA » du journal et de l'ouverture du Grand Livre, états vides du web ; en-tête web « Période : … · Généré le … » non comparé. Fragilité : le nouveau test lit des chemins absolus vers `C:/laragon/www/agrierp` (échoue sans le dépôt Laravel, sans saut explicite). Non vérifié : rendu, impression, largeur de « Final Crédit », `flutter build windows`, `sync_reel_test`. Aucun audit indépendant de F0.88.

**DEMANDES CLIENT du 14/10/2026 (web ET poste) — état des lieux en lecture seule, aucun code.** (A) champ « Date » dans « Vente à la Pièce » (ventes antérieures) ; (B) « TERMINER » le marqueur prophylaxie (« Prévu : Sprint 3, ticket 3.11 », web seul : `module-pending.blade.php` dans les 5 fiches) ; (C) Rationnement & Provende : effectif automatique depuis la Saisie Journalière du Cheptel et champs number calculés désactivés dans les fiches lapins/poules/porcs/escargots ; (D) fiche-lapins « Sevrés » → « Jeune » et glossaire de la colonne « Catégorie » du tableau de rationnement.
Défauts trouvés (lecture, non reproduits) : `SyncController::pushSales` ne rattrape que `ValidationException` (exercice clos/absent → 500 en boucle) ; mois clos non contrôlé pour une vente ; rapports/TVA/historique/rémanence web datés sur `created_at` et non `sold_at` ; aucune cascade de recalcul des fiches ; soupçon de double comptage fiche+vente (à prouver) ; le poste n'absorbe PAS `livestock_daily_entries` (bloquant pour C) ; le poste affiche « 0 » au lieu de « — » sur les lignes de rationnement hors stade ; le ticket 3.11 est FAIT, la reconnexion du moteur aux fiches web n'a jamais été ouverte (marqueur périmé) ; motif « reproduction indéterminable » du poste périmé (`saillie_date` absorbée) ; « Jeune » désigne déjà l'engraissement 60 g (lapins) et « Jeune porc » : doublon à éviter ; rations web retrouvées par sous-chaîne avec valeurs de secours en dur (renommage = retombée silencieuse).
Découpage proposé (13 tickets) : Laravel 15.29→15.36, poste F0.89→F0.93, D avant C. Décisions QA1–QA9, QB1–QB4, QC1–QC8, QD1–QD5 : voir la session du 14/10/2026.

**DÉCISIONS CLIENT du 14/10/2026 (recommandations acceptées).** T6 : option 1 — écritures SAISIES À LA MAIN modifiables/archivables comme sur le web ; écritures AUTOMATIQUES non modifiables au poste, corrigées par contre-passation (défaut du web = ticket Laravel séparé). Ventes datées : un seul champ « Date de la vente » au PANIER (pas dans la modale) ; refus d'une date sans exercice ouvert ou dans un mois clôturé avec message clair (mois clôturé à faire confirmer par le cabinet FAGUEZ) ; fiches déjà saisies après la date : recalcul en cascade côté serveur ; rémanence : enregistrer et signaler. Champs : calculés = grisés, non focalisables, saisis = actifs ; effectif automatique qui se recalcule en direct à la saisie (comportement `oninput` de la maquette). Prophylaxie : câbler le moteur sur les fiches web (lapins, porcs d'abord) et retirer le marqueur. Passage de stade : champ saisi. Renommage : affichage et clé stable, jamais les colonnes de synchronisation. Numérotation : le plan proposait 15.29 pour le socle des ventes, mais 15.29 est déjà pris (T2) : les tickets Laravel suivants sont 15.30 et suivants.

**15.30 FAIT (14/10/2026) — Laravel : socle des ventes datées.** Quatre défauts reproduits par tests rouges puis corrigés : (1) `pushSales` : exercice clos/absent = REJET motivé en français ligne par ligne (avant : 500 pour tout l'envoi, renvoi en boucle) ; (2) mois clôturé refusé au push et au POS web (point unique `VerifySaleDateAction` → `PeriodicClosure::isDateLocked()`, même méthode que le Journal) ; (3) rémanence jugée sur `sold_at ?? created_at` et mouvement de stock daté sur `sold_at` (vente enregistrée, rémanence signalée) ; (4) double comptage fiche + vente PROUVÉ (`vente = 12` pour 6 + 6 dans un même envoi), corrigé en écartant les fiches acceptées dans le même envoi. Mesuré par moi : **Laravel Feature 1 117 verts (13 716 assertions)**, 2 dépréciations connues, README identiques (`0A3B946C…`), en-tête une fois, empreintes `SyncController` `CFD103B5`, `VerifySaleDateAction` `BCBDE6B0`, `PosInterface` `086CEE39`. 16 mutations annoncées tuées, non rejouées par moi. Flutter non touché.
**Contrat `/sync/push`** : aucun champ ne change ; `sales.rejected[].reason` peut contenir de nouveaux motifs (date future, mois clôturé, aucun exercice ne couvre la date, exercice clos) : le poste doit les montrer en `conflict` sans boucle (à vérifier à F0.89). **Choix de l'agent à confirmer** : borne `start_date <= date de la vente` ajoutée à la rémanence (initiative non demandée) ; propriété publique `$dateVente` (vide par défaut) dans `PosInterface` ; le garde de clôture ne joue que si une date est fournie (une vente « du jour » n'est pas bloquée par la clôture du mois courant). Limites : MySQL, production, MeCeF, mois clôturé non confirmé par le cabinet, `sync_reel_test`, double comptage possible si fiche et vente partent dans deux envois différents. Aucun audit indépendant de 15.30.

**15.31 FAIT (14/10/2026) — Laravel : ventes datées, rapports et cascade des fiches.** La règle « date effective = `sold_at ?? created_at` » est centralisée dans `Sale` (expression `COALESCE`, accesseur `date_effective`, scopes `soldBetween`, `soldSince`, `soldBetweenInstants`, `orderByEffectiveDate`) et appliquée au tableau de bord, à l'historique, aux retours, à recettes/dépenses, à la TVA (test : même mois que l'écriture), à la facturation, à la fiche client, au ticket et à l'ordre du tirage. Cascade : `recalculerEnCascade` dans `RecordSaleOnFicheElevageAction` (fiches postérieures recalculées par `computeEffectifFinal`, `current_quantity` = dernière fiche, idempotent, transactionnel, borné à 0 ; exemple testé 49/47/50 + vente de 6 à J-2 → 43/41/44, bande à 44). Mesuré par moi : **Laravel Feature 1 148 verts (13 809 assertions)**, README identiques (`6863DDAF…`), en-tête une fois, empreintes `Sale` `E6137C9B`, `RecordSaleOnFicheElevageAction` `BF0F0F92`, `VatDeclarationService` `5508B12D`, `SyncController` `443DB819`. 22 mutations annoncées tuées, non rejouées par moi. Flutter non touché.
**Contrat `/sync/*`** inchangé en forme ; deux effets côté poste : l'ordre des factures du tirage suit la date effective, et les fiches recalculées redescendent avec un `effectif_final` corrigé (le poste doit accepter que le serveur réécrive l'effectif de fiches qu'il possède, avec l'absorbeur de F0.92). **Ouvert** : `Receivable.created_at` (taux de recouvrement de `SuiviDettes`) à arbitrer ; colonnes `effectif_m/f/sevres`/`cat_eff_*` non recalculées par la cascade ; une fiche poussée sur un jour antérieur ne déclenche pas la cascade (seule une vente le fait) ; aucun index sur l'expression `COALESCE` (impact non mesuré) ; double exécution directe de `execute()` ajoute la vente deux fois (comme avant). Non vérifié : MySQL, vues Blade de facturation/fiche client/ticket (lecture seule), poste réel, `sync_reel_test`. Aucun audit indépendant de 15.31.

**15.32 FAIT (14/10/2026) — Laravel : champ « Date de la vente » au panier du POS web.** Un seul `<input type="date">` sous le sélecteur Client (écart assumé vs `pos-interface.html`, documenté dans la vue, `$dateVente` et le README) ; défaut aujourd'hui, `max` = aujourd'hui sans dépasser l'exercice ouvert, `min` = début du plus ancien exercice ouvert (bornes indicatives, le serveur rejuge) ; refus (date future, aucun exercice, exercice clos, mois clôturé, date invalide) affichés sous le champ puis à la validation, messages de `VerifySaleDateAction` ; vente du jour strictement inchangée (`sold_at = now()`) ; vente antérieure : jour choisi + heure courante, écriture, stock, caisse, créance (J-3 + 30 j), fiche + cascade et ticket suivent cette date ; rémanence : enregistrée et signalée (jamais refusée) pour un jour antérieur, blocage dur conservé pour la vente du jour. Mesuré par moi : **Laravel Feature 1 170 verts (13 885 assertions)**, README identiques (`88820F26…`), en-tête une fois, `PosInterface` `B470891B`. 20 mutations annoncées dont 19 tuées, 1 survivante (M15 : retirer l'`addError` de `validateSale` ne casse aucun test — limite du banc Livewire) ; tests écrits après le code, non rouges d'abord. Flutter non touché.
**À DÉCIDER (QA6, non tranché)** : seule l'ability `manage-ventes` est utilisée → tout détenteur (caissier, admin) peut antidater, et antidater contourne le blocage de rémanence du jour (la notification admin est le seul garde-fou). Non vérifié : rendu navigateur et sélecteur natif, Dusk (`PosSaleTest`, `VeterinaryWithdrawalBlockTest` non rejoués), MySQL, page restée ouverte après minuit (la date d'ouverture devient une « vente antérieure »), vente du jour sans exercice ouvert (exception comptable non rattrapée, inchangé), mois clôturé non confirmé par le cabinet, MeCeF. Aucun audit indépendant de 15.32.

**F0.89 FAIT (14/10/2026) — poste : « Date de la vente » à la caisse.** Champ « DATE DE LA VENTE » au panier (écart assumé vs `pos-interface.html`, verrouillé dans `caisse_conformite_test.dart`), même calendrier que le Grand Livre, borne basse = début du plus ancien exercice ouvert local, borne haute = aujourd'hui ; `updatedAt` (instant de saisie) séparé de `soldAt` (jour choisi + heure courante, heure locale sans `toUtc()`) ; vente du jour strictement inchangée ; refus locaux (date future, aucun exercice ne couvre, exercice clos) avec les messages du serveur mot pour mot ; mois clôturé jugé par le serveur seul ; vente reportée sur la fiche du JOUR DE LA VENTE puis fiches suivantes recalculées (jeu 15.31 : 49/47/50 + vente de 6 → 43/41/44, bande à 44) ; fiches envoyées triées par jour ; « Relancer » une vente refusée remet aussi en file la fiche de son jour de vente (sinon double comptage 12 au lieu de 6, prouvé). Mesuré par moi : analyze propre, **Flutter 1 721 verts + 4 ignorés**, aucun `flutter_tester` actif, README identiques (`7C8BB85E…`), en-tête une fois, `docs/`/`prototype_html/` vides ; Laravel non touché (1 170 au dernier relevé). 30 mutations annoncées tuées (M21 corrigée), non rejouées par moi ; fidélité stricte 1 332/2 099 et plafond 268 inchangés selon l'agent.
**À OUVRIR** : (1) défaut antérieur MESURÉ : deux lignes du même produit dans un panier → stock local 19 au lieu de 17 (le serveur compte juste) ; (2) une vente refusée garde ses effets locaux (stock, fiche) alors que sa fiche acceptée compte des sujets vendus côté serveur ; (3) le serveur juge aussi la vente du jour du poste (le poste envoie toujours la date), pas le web ; (4) le poste ne tire pas les fiches (absorbeur = F0.92) : vente antérieure sur un jour déjà saisi sur le web = fiche du poste en conflit ; (5) le serveur ramène chaque fiche à 0 minimum, le poste seulement la bande ; (6) `FicheJournaliereRepository.enregistrer` écrit dans la bande l'effectif du jour saisi même s'il existe des fiches plus récentes ; (7) le poste passe en conflit tout identifiant rejeté, même non envoyé ; (8) course théorique : fiches lues avant ventes ; (9) texte d'aide du web parlant de « créance » alors que le poste ne vend pas à crédit. **À DÉCIDER** : QA6 qui peut antidater (aucune restriction ajoutée) ; vente refusée : annuler localement ou laisser en conflit jusqu'à relance ; borne haute du calendrier sans limite à la fin de l'exercice ouvert ; mois clôturé à confirmer par le cabinet. Non vérifié : rendu (calendrier en anglais, pas de localisation française), `flutter build windows`, `sync_reel_test` (serveur de test écrit à la main, motifs recopiés), fuseau (tests figés UTC+1), minuit avec caisse ouverte. Aucun audit indépendant de F0.89.

**Audit indépendant de la chaîne « ventes datées » — F0.88, 15.30, 15.31, 15.32, F0.89 (14/10/2026) : CONFORME AVEC RÉSERVES, aucun bloquant.** Reproduit avec les jeux de l'auditeur : vente à crédit J-3 (écriture 11/10, créance échue 10/11, stock 80→76, fiche 46, bande 46) ; cascade 49/47/50 + vente de 6 → 43/41/44 (bande 44) et jeu propre 53/48/45 ; exercice clos/absent/mois clôturé rejetés ligne par ligne sans bloquer les autres ventes (une vente créée, stock 79, une écriture) ; double comptage fiche+vente = 6 (pas 12) ; relance avec la fiche = 6, sans la fiche = 12 (ancien défaut reproduit) ; TVA et écriture dans le même mois (30/09 23:30) au push comme au POS web ; poste : `soldAt` 11/10, `updatedAt` 14/10 (jamais antidaté), `sold_at` en heure locale, `updated_at` en UTC, AUCUNE écriture/créance/trésorerie au poste, cascade 53/48/45, motifs locaux identiques mot pour mot au serveur ; aucune vente encore datée sur `created_at` (restes : avoirs, créances `SuiviDettes` déclarées, paie, audit). 20/20 mutations Flutter et 17/18 Laravel tuées (survivante L15 = M15 déjà déclarée) sur COPIES ; dépôts inchangés (empreintes).
**À CORRIGER (non déclarés)** : **D1** — une date future poussée par le poste est rejetée EN ANGLAIS (`SyncController` ~l.2369 : la règle `before_or_equal:now` s'exécute avant `VerifySaleDateAction` ; pas de dossier `lang/` alors que `APP_LOCALE=fr`) : « The sold at field must be a date before or equal to now. », idem pour une vente du jour si l'horloge du poste avance de 3 minutes ; le contrat de 15.30 (« la date du … est dans le futur ») est faux au push ; le test serveur ne vérifie pas le motif. **D2** — « Relancer » une vente remet en file la fiche synced telle que le poste la détient ; le serveur applique « dernier écrivain gagne » sans condition : une correction faite entre-temps sur le web (2 morts) est écrasée (`MORT_APRES_RELANCE=0`). Remarques : `_absorberVentes` met `updatedAt = sold_at` sur les ventes tirées (horodatage antidaté sans effet aujourd'hui) ; empreinte de `FlagSaleUnderWithdrawalAction` (`b1eff879` → `d950b668`) non listée par 15.31 ; le serveur simulé de F0.89 utilise un motif de mois clôturé inventé. Non vérifié : suites complètes, MySQL, production, Dusk, rendu, `sync_reel_test` (boucle poste↔serveur jamais exercée de bout en bout), fuseau ≠ UTC+1, minuit caisse ouverte, impression des PDF.

**15.33 FAIT (14/10/2026) — Laravel : motifs de refus du push en français (défaut D1).** 19 handlers de `/api/sync/push` (ventes, fiches, reproduction, achats, produits, fournisseurs, clients, courriers, documents archivés/administratifs, avances, imputations, règlements/retours/remboursements fournisseur, pointage, dépenses, soins, ajustements de stock) renvoyaient les messages anglais par défaut ; nouveau `app/Support/MotifsRefusPush.php` (20 règles, libellés de champs, `motif()` qui rapporte TOUTES les erreurs au lieu d'une suivie de « (and N more errors) »). Horloge : rejet franc, AUCUNE tolérance (le dépôt n'en a pas à reprendre ; en inventer une = règle métier sans le client) — une vente du jour poussée avec une horloge avancée de 3 minutes est refusée avec un motif français. Contrat `/sync/*` : inchangé (seul le texte de `rejected[].reason`). Mesuré par moi : **Laravel Feature 1 194 verts (14 007 assertions)**, README identiques (`1486539C…`), en-tête une fois, `MotifsRefusPush.php` et `SyncMotifsRefusFrancaisTest.php` présents, `docs/`/`prototype_html/` vides. 16/17 mutations annoncées tuées (survivante : libellé `sold_at` dans `attributs()`, mutant équivalent), non rejouées par moi. Flutter non touché. **Ouvert** : le motif de date future du push (« Vente refusée : la date de la vente (2026-10-20 09:00:00) est dans le futur. », date non reformatée) diffère du texte de `VerifySaleDateAction` que le poste recopie ; `catch (\Throwable)` de `pushStockAdjustments` renvoie encore un message brut (« No query results for model… ») ; la validation du `pull` (`since`) garde son 422 anglais ; un champ absent de `attributs()` s'affiche sous son nom technique ; tolérance d'horloge à arbitrer si le cas se présente sur le terrain. Non vérifié : `sync_reel_test`. Aucun audit indépendant de 15.33.

**F0.90 FAIT (14/10/2026) — poste : correctifs issus de l'audit des ventes datées.** (D2) « Relancer » une vente ne remet plus en file que la vente (`_relancerVente`) ; la fiche du jour de la vente, si le poste la tient pour synchronisée, part réduite à `{id, lot_id, entry_date}` (`_fichesDIdentite`, `_ficheIdentiteEnJson`) : sur le modèle du serveur, la correction web est gardée (mort 2) et la vente compte une fois (6, pas 12) ; une fiche en attente part en entier, une fiche en conflit ne part pas. (B1) stock décrémenté sur sa valeur réelle en base (`stock_qty − q`) et non sur la copie prise à la mise au panier : 20 → 17 (avant 19), poulets 3 + 2 → 45, stock passé à 30 puis vente de 2 → 28 (avant 18). (B2) `_absorberVentes` : le `pull` ne sert ni `updated_at` ni `created_at` pour les ventes ; une vente connue garde son horodatage de saisie, une vente inconnue prend l'heure de réception (paramètre `maintenant` ajouté à `SyncEngine`). Mesuré par moi : analyze propre, **Flutter 1 734 verts + 4 ignorés**, aucun `flutter_tester` de ce dépôt actif, README identiques (`8913B64F…`), en-tête une fois, empreintes `sync_engine` `F067C883`, `caisse_repository` `DE9436CC`, test `938D5F8D`, `docs/`/`prototype_html/` vides ; Laravel non touché (1 194). 16 mutations annoncées tuées, non rejouées par moi.
**Limites / ouvert** : D2 repose sur la LECTURE du code serveur et sur un modèle de test écrit à la main (comportement implicite d'Eloquent « n'écrire que les champs envoyés » non verrouillé par un test Laravel) ; si la fiche avait disparu du serveur, une fiche vide serait créée et ferait sauter la vente (0 au lieu de 6), non testé. **Ticket Laravel à arbitrer (15.34)** : version 1 — `pushDailyEntries` refuse une fiche sans colonne de saisie dont l'`id` est inconnu (au lieu de créer une fiche vide) ; version 2 — le serveur mémorise `(sale_id, lot_id, jour, qty)` d'une vente refusée dont la fiche est acceptée, le poste n'envoie alors plus de fiche réduite. Constats : la fiche réduite acceptée est comptée dans les « acceptés » du compte rendu ; `_absorberVentes` écrit `deviceId = 'serveur'` sur une vente saisie au poste (origine perdue) ; `production_oeufs_service.dart` met à jour le stock depuis une copie du produit (comme B1, non mesuré) ; les ventes absorbées avant ce ticket gardent leur horodatage antidaté ; course de F0.89 (fiches lues avant ventes) inchangée ; écart de texte du motif de date future (poste « la date du JJ/MM/AAAA », push « la date de la vente (AAAA-MM-JJ HH:MM:SS) »). Non vérifié : vrai serveur (`sync_reel_test`), MySQL, `flutter build windows`, rendu, fuseau ≠ UTC+1. Aucun audit indépendant de F0.90.

**15.34 FAIT (14/10/2026) — Laravel : garde-fou contre la fiche vide au push (version minimale du ticket proposé après F0.90).** `pushDailyEntries` refuse une fiche d'`id` inconnu qui ne porte AUCUNE colonne de saisie (`porteUneColonneDeSaisie` : `$fillable` hors `lot_id`, `entry_date`, `effectif_final` ; critère = clé présente, une fiche à zéro reste une saisie réelle) avec le motif `MotifsRefusPush::ficheReduiteInconnue()` : « Fiche refusée : elle ne porte aucune donnée de saisie et son identifiant est inconnu du serveur (fiche supprimée ou base restaurée). Ressaisissez la fiche du jour. » ; la vente du même envoi est alors comptée normalement (fiche `vente = 6`, bande 44, une fiche, une vente) ; un `id` connu n'écrit rien (verrouillé par test, il ne l'était pas). Mesuré par moi : **Laravel Feature 1 204 verts (14 058 assertions)**, README identiques (`46E2BEE1…`), en-tête une fois, test présent, `docs/`/`prototype_html/` vides. 12 mutations annoncées tuées, non rejouées par moi. Poste non touché : `_acquitter` traite déjà tout rejet en `conflict` avec son motif (lu par l'agent). Contrat inchangé hors ce motif. **Ouvert** : version robuste (mémoire des ventes refusées) non faite ; l'agent n'a pas vérifié de bout en bout que la fiche réduite renvoyée à la relance (F0.90) est refusée proprement quand l'id est inconnu (elle le sera tant qu'elle n'est pas ressaisie : voulu, non testé côté poste) ; 5 tests sur 10 étaient verts à vide (garde-fous), le « 0 au lieu de 6 » lui-même n'a pas été observé ; une fiche d'`id` connu dont `lot_id`/`entry_date` diffèrent les réécrit (comportement existant de `fill`). Non vérifié : `sync_reel_test`, MySQL. Aucun audit indépendant de 15.34.

**15.35 FAIT (14/10/2026) — Laravel : moteur de prophylaxie câblé sur les fiches web Lapins et Porcs (lecture (a) de « TERMINER »).** Règle du jour de cycle extraite dans `ProtocoleDuJourService` (+ `ProtocoleDuJour`) utilisée par le job ET les fiches ; section « Traitements & Prophylaxie » fonctionnelle (états Libre / « N Prévu(s) » / Validé-Effectué / Indéterminé ; bande en reproduction sans saillie = Indéterminé ; entrées « Le 1er du mois » non évaluées et annoncées comme telles) ; validation par `ValidateProphylaxisTreatmentsAction` → `RecordVeterinaryCareAction` (rémanence et blocage de vente créés AU CLIC de validation ; double validation = un seul soin ; id hors protocole ignoré) ; marqueur « ticket 3.11 » retiré des fiches Lapins et Porcs (vérifié par moi : 0 occurrence) ; pondeuses/reproducteurs/escargots inchangés, marqueur réécrit « à planifier » (pour les escargots il portait en réalité sur l'hygrométrie, aucune table n'existe). Mesuré par moi : **Laravel Feature 1 242 verts (14 230 assertions)**, README identiques (`50BA8465…`), en-tête une fois, nouveaux fichiers présents, `docs/`/`prototype_html/` vides. 28 mutations annoncées dont 27 tuées (survivante équivalente : `round()` du jour de cycle), non rejouées par moi. Contrat `/sync/*` inchangé. Flutter non touché.
**DÉFAUTS TROUVÉS** : (1) le job `DailyProphylaxyReminderJob` NE NOTIFIAIT JAMAIS les traitements à jour unique (`diffInDays(now()) + 1` renvoie un flottant sous Carbon 3.13, 5,25 à 06 h 00 pour un J5) — corrigé en jours calendaires entiers, donc **COMPORTEMENT DU JOB CHANGÉ : des rappels jusqu'ici non émis partiront au prochain passage de 06 h 00 (le client doit être prévenu)** ; aucun test du job n'existait (6 écrits) ; (2) `ProphylaxisScheduleStandard::$fillable` omettait `cycle_day_start`/`cycle_day_end` (ignorés sans erreur) — ajoutés.
**À DÉCIDER** : `ParametresElevage::saveProphy()` ne renseigne pas `cycle_day_start`/`cycle_day_end` : toute entrée créée par le client est INERTE pour le moteur (seulement comptée dans la note), et modifier un libellé laisse des bornes périodées — interpréter le libellé = inventer une règle ; garde ajoutée au web refusant de valider un traitement pour un jour FUTUR (le poste ne l'a pas) ; fiche web sur la première bande active sans sélecteur (le poste en a un) ; pas de référence explicite soin→barème (`veterinary_records` n'a pas de colonne ; ajouter = changer le contrat de synchronisation, ticket séparé) ; raccordement des 3 autres fiches et calendrier Gantt `veterinary_calendar_events` = tickets séparés ; entrées « Le 1er du mois » et barème héliciculture inchangés. Non vérifié : rendu navigateur, Dusk, classes Tailwind du composant (`npm run build` non relancé), MySQL (`lockForUpdate` sans effet en test, idempotence prouvée séquentiellement seulement), fuseaux, enregistrement du champ « Observations » par `saveDay()`. Aucun audit indépendant de 15.35.

**F0.91 FAIT (14/10/2026) — poste : prophylaxie alignée sur le service serveur (15.35).** Une bande en reproduction a maintenant un jour de cycle CALCULÉ (J1 = dernière saillie connue de la bande, `_derniereSaillie`, qui exclut les saillies `conflict` et compte les `pending`) ; sans saillie connue : « Indéterminé » avec motif corrigé ; jours calendaires entiers (`SoinsRepository.joursCalendairesEntre`, écart entre deux minuits UTC) ; traitements dus triés par jour de début puis nom ; soins du jour reconnus sur le jour calendaire (comme `whereDate`) ; docblocks et commentaires périmés corrigés (fiche lapins, reproducteurs, tableau de bord élevage). Nouveau `protocole_du_jour_parite_test.dart` (23 tests, jeu du serveur recopié à la main : Anti-stress J2–J4, Anti-coccidien J5 avec 5 jours de rémanence, « Le 1er du mois » jamais dû ; saillies 01/10 et 12/10 → J3 le 14/10). Mesuré par moi : analyze propre, **Flutter 1 759 verts + 4 ignorés**, aucun `flutter_tester` actif, README identiques (`634543D0…`), en-tête une fois, `soins_repository.dart` `1C3039B9`, `docs/`/`prototype_html/` vides ; Laravel non touché (1 242 au dernier relevé). 20 mutations annoncées dont 19 tuées (survivante M09 : écart en heure locale au lieu d'UTC, équivalent sans heure d'été), non rejouées par moi.
**Défauts trouvés** : (1) une bande en reproduction était TOUJOURS « Indéterminé » (motif périmé depuis 14.72) : les 5 fiches, le calendrier Soins & Vaccins et les rappels VMS ne lui ont jamais proposé de traitement ; (2) un soin daté avec une heure n'était pas reconnu → traitement « à valider » et risque de double administration ; (3) tri sur le libellé de période (« J10 » avant « J2 ») ; (4) changement d'heure local faisait perdre un jour ; le défaut de flottant du serveur (15.35) était ABSENT du poste.
**Écarts web/poste signalés, non corrigés** : jour futur (web refuse, poste accepte) ; « N Prévu(s) » (web) vs « Prévus » (poste, maquette) ; sélecteur de bande (poste) vs première bande active (web). **Constats ouverts** : barème désactivé sur le web reste dû au poste indéfiniment (le tirage ne sert que les actifs, `_absorberProphylaxie` ne supprime jamais, pas de colonne `is_active` locale) et un soin archivé reste compté « déjà administré » — LU dans le code, non reproduit par un test ; jour antérieur à une nouvelle saillie → J ≤ 0 (règle serveur recopiée telle quelle) ; tri par nom de traitement par codes de caractères vs MySQL ; poste réglé hors UTC+1 décale les dates (`_date()` convertit en heure locale) ; `add(Duration(days: n))` du tableau de bord élevage et de Soins & Vaccins faux d'une heure lors d'un changement d'heure. **À DÉCIDER** : garde « jour futur » ; exclure une saillie `conflict` / compter une `pending` (choix de l'agent) ; règle pour un jour antérieur à la dernière saillie ; décisions de 15.35 (bornes de cycle dans Paramètres > Élevage, « Le 1er du mois », référence soin→barème, raccordement des 3 autres fiches). Non vérifié : rendu, `flutter build windows`, `sync_reel_test`, parité croisée poste/serveur sur la même base (jeu recopié à la main), fuseau avec heure d'été, calendrier Soins & Vaccins et rappels VMS avec une bande en reproduction (même méthode, non testés à part). Aucun audit indépendant de F0.91.

**15.36 FAIT (14/10/2026) — Laravel : glossaire de la fiche lapins.** Validé par le client : Reproducteur 120 g / Jeune 30 g (ex-« Sevré ») / Lapin de Chair 60 g (ex-« Jeune (engraissement) ») ; champ et en-tête mensuel « Sevrés » → « Jeunes » (distinct de « S/Mères ») ; porcs, escargots, volailles inchangés. Clé stable `reproducteur`/`jeune`/`chair` (`App\Support\CategorieRationLapin`, tolérante aux anciens ET nouveaux libellés ; `chair` testé avant `jeune`), valeurs de secours 120/30/60 conservées, utilisées seulement si la catégorie est absente du barème ; pas de colonne `category_key` (changerait la forme de `/sync/pull`) ; migration `2026_10_14_000001_renomme_libelles_bareme_lapins` (cuniculture seule, ration jamais touchée, idempotente, `down()` inverse) ; seeder aligné ; colonnes de synchro intactes (`cat_eff_sevre` = Jeune, `cat_eff_jeune` = Lapin de Chair, `effectif_sevres` = « Jeunes »). Mesuré par moi : **Laravel Feature 1 260 verts (14 312 assertions)**, README identiques (`93782203…`), en-tête une fois, nouveaux fichiers présents, plus aucun « Sevré(s) » dans la vue `fiche-lapins`, `docs/`/`prototype_html/` vides. 23 mutations annoncées tuées, non rejouées par moi.
**INCIDENT à lire** : un script PHP de l'agent (regex en échec) a ÉCRASÉ `app/Livewire/Elevage/FicheLapins.php` (fichier vide, dépôt non versionné), reconstitué depuis `agrierp2.zip` (19/08/2026, 20 849 octets) puis réappliqué : modifications 15.35 puis 15.36. **Vérifié par moi** : 4 copies du scratchpad datées du 19/08 au 10/10 (`z0`, `audit27`, `lv`, `audit28\lv`) ont toutes la même empreinte `63DA5E04…` ; le fichier n'a donc pas changé entre août et le 10/10 ; la comparaison ligne à ligne avec cette version ne montre QUE des changements documentés (trait `AvecProphylaxieDuJour`, remise à zéro du cochage dans `loadDay`, docblock 15.35, clés stables 15.36). Reste non vérifiable : une modification non documentée entre le 10/10 et le début de 15.35 (aucun ticket 15.30–15.34 n'est annoncé sur ce fichier). Leçon : toute campagne de mutations/édition scriptée doit sauvegarder le fichier AVANT (SHA-256 + copie) ; le dépôt n'est pas versionné.
**🔴 POSTE À ADAPTER (F0.92)** : `fiche_lapins_screen.dart` (~l.906) rattache l'effectif de la bande à la ligne du barème par `stageLabel.toLowerCase().contains(stade)` ; une bande au stade `engraissement` ne correspondra plus à « Lapin de Chair » après la migration → effectif 0 et total de provende faussé au poste ; libellés « Sevrés » du poste (l.480 et 545) à aligner. **Contrat `/sync/*`** : forme inchangée, la VALEUR de `stage_label` change pour 2 lignes de cuniculture (le poste verra « Jeune » et « Lapin de Chair »). **Décisions ouvertes** : rapport de synthèse Élevage (écran, PDF, CSV `ElevageSynth.php` l.179) garde « Sevrés » (mélange les espèces ; la maquette dit « Sevrés M / F » ; un test verrouille le choix) ; bloc Dons : web « Lapin » vs maquette « Lapin de Chair » (non aligné, autre table) ; « Lapereau » inchangé ; Paramètres Élevage affiche l'ancien libellé tant que la migration n'a pas été jouée en production. Non vérifié : rendu, MySQL, base de production jamais lue (libellés réels inconnus), poste non lancé, `sync_reel_test`. Aucun audit indépendant de 15.36.

**F0.92 FAIT (14/10/2026) — poste : glossaire de la fiche lapins et clé stable des catégories.** Nouveau `lib/features/elevage/categorie_ration_lapin.dart` (UNIQUE version Dart de la règle serveur `CategorieRationLapin` : minuscules, accents retirés, `reproducteur` d'abord puis `chair` puis `jeune` en égalité stricte ; `ration()` = première ligne de la catégorie sinon secours 120/30/60 ; `cleDuStade()` reproduit l'ancien rattachement : `engraissement` → « Lapin de Chair », les autres stades aucune ligne, rien d'inventé). Fiche lapins du poste : trois lignes fixes Reproducteur / Jeune / Lapin de Chair, colonne « Catégorie », titre « … PAR CATÉGORIE … », colonne mensuelle « Jeunes » (« S/Mères » inchangé) ; **défaut urgent corrigé** : avec les libellés « Jeune » / « Lapin de Chair » une bande à l'engraissement de 40 sujets affiche 40 × 70 = 2 800 g (avant la correction : effectif 0) ; une ligne hors du stade de la bande affiche « — » (effectif et provende), le total « — » si aucune ligne ne porte l'effectif, un effectif réellement nul reste « 0 » ; une catégorie en double dans le barème ne compte l'effectif qu'une fois ; `fiche_sujet_screen.dart` : motif de l'onglet Alimentation aligné sur le web 15.36. Aucun renommage de stockage (le poste ne porte ni `effectif_sevres` ni `cat_eff_*` ; schéma inchangé). Mesuré par moi : analyze propre, **Flutter 1 808 verts + 4 ignorés** (1 759 + 34 + 15), aucun `flutter_tester` actif, README identiques (`965B226B…`), en-tête une fois, empreintes `categorie_ration_lapin` `0F9FE9C7`, `fiche_lapins_screen` `ED343EFF`, `fiche_sujet_screen` `6116F598`, `docs/`/`prototype_html/` vides ; Laravel non touché (1 260). 20 mutations annoncées tuées (sauvegarde + SHA-256 avant chaque campagne ; réserve : l'ordre vertical des trois lignes n'est tué que par le test de la constante `ordre`), non rejouées par moi. Fidélité stricte 1 332 → **1 330 / 2 099** (« Espèce » et « Sevrés » de `fiche-lapins.html` perdus = décision client), `RAPPORT_FIDELITE_2.md`/`audit_fidelite.json` régénérés, plafond 268 inchangé, aucune exemption ajoutée.
**Constats / à décider** : `fiche-lapins.html` n'est dans AUCUNE fixture de fidélité (ni `fidelite_libelles_test` ni `conformite_structure_test` ; l'ajouter ferait monter le plafond 268 → ticket dédié) ; le web utilise les rations archivées (`FicheLapins::getRationStandardsProperty` ne filtre pas `is_active`) alors que `/sync/pull` ne sert que les actives : écart serveur/poste à traiter côté Laravel ; doublon de catégorie : « première ligne » = ordre de base (non spécifié) au web, ordre alphabétique du libellé au poste ; le poste n'a pas de champ « Jeunes » à l'Effectif Final du Jour (tickets suivants) ; bande en `reproduction`/`croissance` = trois « — » (avant : « 0 g », tout aussi inconnu) : rattacher `reproduction` → Reproducteur et `croissance` → Jeune ? (la fiche porcs le fait, la règle n'est écrite nulle part pour les lapins) ; barème vide : « Rationnement indisponible » conservé au poste vs secours 120/30/60 au web ; rapport de synthèse « Sevrés M/F », bloc Dons, « Lapereau » (reprises de 15.36). Non vérifié : rendu, `sync_reel_test`, aucun pull réel après la migration 15.36 (renommage simulé), base de production jamais lue, parité Dart/PHP sur jeu recopié à la main. Aucun audit indépendant de F0.92.

**Audit indépendant des chaînes prophylaxie (15.35, F0.91) et glossaire lapins (15.36, F0.92) + 15.33, 15.34, F0.90 (14/10/2026) : CONFORME AVEC RÉSERVES, aucun bloquant.** Rejoué avec les jeux de l'auditeur : formule de flottant (5,25 à 06 h) et service = J5 ; job lancé deux fois à 06 h = une seule notification ; bande en reproduction saillies 12/10 et 01/10 insérées dans le désordre = J3 ; afficher la fiche n'écrit rien ; 3 validations = 1 soin, 1 période (fin 19/10) ; rations 10/20/30 × 150/40/70 = **4 400 g** sur 4 jeux de libellés (serveur) et bande à l'engraissement de 40 = 2 800 g (poste) ; migration 15.36 idempotente, `down()` inverse, doublon géré, porcs et rations intacts ; 14 enregistrements invalides poussés, aucun motif en anglais ; 15.34/F0.90 confirmés sur le VRAI serveur (correction web conservée, vente comptée une fois, stock 50 → 46). **Parité EXÉCUTÉE Dart/PHP sur 52 libellés : 50 concordent, 2 divergent** (`" Jeune"` et `"Jeune "` : `trim()` de Dart retire les espaces Unicode, celui de PHP non → le web prendrait le secours, le poste la valeur du barème). Incident `FicheLapins.php` : fichier actuel relu en entier, diff contre la version d'avant 15.35 (`63da5e04`) = trait, clé stable, remise à zéro du cochage, docblocks seulement ; intégration symétrique de `FichePorcs.php` ; pondeuses/reproducteurs/escargots identiques à la copie du 10/10 ; la version 15.35 (`DEAFE84E`) est irrécupérable. **Correction de ma note précédente** : `z0` et `z2` ont été extraits de l'archive le 14/10 à 08:14 PENDANT l'incident, donc ne sont pas des témoins indépendants ; les témoins indépendants sont `agrierp`/`laravel_copie` (08/10), `lv` (09/10), `audit27` (10/10 10:10) et `audit28\lv` (10/10 16:56) ; la conclusion tient. Dépôts inchangés (666 fichiers Laravel, 201 fichiers Flutter par empreinte). Mutations sur copies : 14/15 Flutter tuées, 7/14 Laravel par les tests des tickets (+2 par ceux de l'auditeur), survivantes : 3 équivalentes (L02, L03, L05) et 3 vraies lacunes (L06, L09, L11).
**À CORRIGER** : (1) le journal 15.36 (README, ligne 21117) écrit « 10×150 + 20×40 + 30×70 = 3 800 g » : le total exact est **4 400 g** (le test, lui, est juste) ; (2) le journal F0.92 écrit « schéma v36 inchangé » : `schemaVersion` est 37 ; (3) garde-fou de 15.33 trop étroit : sans le message `exists`, 5 handlers (fiches, ventes, pointages, achats, règlements fournisseurs) renverraient « The selected … » sans qu'aucun test le voie (L12) — le code est correct, mais c'est le refus le plus courant (produit ou bande inconnus) ; (4) égalité stricte « jeune » non verrouillée côté serveur (L06 `str_starts_with` survit : ni « Jeunes » ni « Jeune porc » dans `GlossaireFicheLapinsTest`) ; (5) migration 15.36 : `down()` et avancée de `updated_at` non testés (L08, L09) ; (6) L11 : retirer `vente` des colonnes de saisie survit à tous les tests ; (7) divergence Unicode de la parité. **Remarques** : fins de ligne CRLF → LF sur 4 vues de fiche (sans effet fonctionnel) ; poste : `_validerTraitements` ne relit pas `_validationEnCours` (seule la désactivation du bouton protège d'un double soin ; le serveur recalcule sous verrou) ; entrée du barème avec `cycle_day_start` renseigné et `cycle_day_end` nul ni due ni comptée, sans message, des deux côtés ; **cas de bout en bout de 15.34** (fiche disparue du serveur) : après le refus, la relance renvoie la fiche COMPLÈTE d'id E qui heurte l'unicité (bande, jour) de la fiche créée par la vente et repart en `conflict` — la consigne « Ressaisissez » ne sort pas forcément le poste de cette boucle (non testé) ; `_absorberVentes` : le repli `?? DateTime.now()` n'utilise pas l'horloge injectée `_maintenant`. Non vérifié par l'auditeur : suites complètes, MySQL, `sync_reel_test`, rendu, heure d'été, production, parité du jour de cycle sur une base commune.

**15.37 FAIT (14/10/2026) — Laravel : réserves de l'audit 15.33–15.36 (tests et journal, aucun comportement de production modifié).** 25 tests ajoutés : L12 (13 cas d'UUID valide mais inconnu — fiches/bande, ventes/produit/bande, pointages/employé, achats/fournisseur/compte/produit, règlements fournisseur, dépenses, soins, reproduction, ajustements — + 1 test d'avance pour un client inconnu : ce handler n'a pas de règle `exists`, il passe par le service), L06 (« Jeunes », « Jeune porc », « Jeune. », « Jeune lapin » → AUCUNE clé, jamais jeune ; la consigne disait « chair », le code renvoie null, le test fige le code), L08/L09 (`down()` rétablit les libellés, aller-retour sans perte, `updated_at` avance sur les lignes renommées seulement), L11 (`vente` seul = saisie ; `lot_id`/`entry_date` seuls non), parité Unicode (la règle PHP n'est PAS changée : «  Jeune » → null documenté). Entrée de journal « Corrections de journal » : 15.36 ligne 21117 « 3 800 g » faux → 1 500 + 800 + 2 100 = **4 400 g** ; F0.92 ligne 21156 « schéma v36 inchangé » faux → `schemaVersion = 37`. Mesuré par moi : **Laravel Feature 1 285 verts (14 467 assertions)**, README identiques (`174CE2CC…`), en-tête une fois, `FicheLapins.php` toujours `9D5DC73C` (production inchangée), `docs/`/`prototype_html/` vides. 9 mutations annoncées tuées, non rejouées par moi. Fins de ligne CRLF/LF : les 4 vues restent en LF (128 vues LF contre 29 CRLF dans le dépôt).
**DÉFAUT PRÉEXISTANT TROUVÉ, NON CORRIGÉ** : une fiche élevage poussée avec `"vente": null` provoque une erreur 500 (`NOT NULL constraint failed: livestock_daily_entries.vente`) — la validation `nullable` laisse passer le null ; les autres colonnes de saisie nullable ont vraisemblablement le même chemin (non vérifié) ; le poste envoie-t-il un null ? non vérifié. → ticket Laravel dédié. Non vérifié : production, `exists` sous MySQL, autres tables du push sans cas d'UUID inconnu, alignement Dart/PHP (ticket poste suivant). Aucun audit indépendant de 15.37.

**15.38 FAIT (14/10/2026) — Laravel : valeurs `null` dans le push (fin des 500).** Mesure par tests rouges (14 échecs sur 17) : fiches élevage — exactement 4 colonnes `nullable` en validation mais NOT NULL DEFAULT 0 en base : `achat`, `ne`, `mort`, `vente` (`don` est nullable en base, donc sans défaut) ; ventes — `discount` null = 500, `subtotal` et `lines.*.unit_price` = 500 aussi quand la clé est omise. Décision sans règle métier inventée : fiche : null sur ces 4 colonnes traité comme CLÉ ABSENTE (fiche neuve = défaut 0, fiche existante = colonne non réécrite) ; une fiche d'id inconnu qui ne porte que ces null est refusée par le motif 15.34 ; vente : `discount` null = aucune remise, `subtotal` et `lines.*.unit_price` deviennent `required` (refus motivé en français de cette seule vente, les autres de l'envoi passent). Code : `sansNullSurColonnesNotNull()` et `FICHE_COLONNES_NOT_NULL` dans `SyncController`. Mesuré par moi : **Laravel Feature 1 302 verts (14 583 assertions)**, README identiques (`2199D1C4…`, valeur que j'ai mesurée ; le rapport de l'agent en cite une avec un caractère hexadécimal différent, erreur de transcription), en-tête une fois, `SyncValeursNullTest.php` présent (17 tests, 116 assertions), `docs/`/`prototype_html/` vides. 12 mutations annoncées dont 11 tuées (survivante équivalente : garde `is_array` du helper), non rejouées par moi. Contrat `/sync/*` : clés et formes inchangées, seulement de nouveaux motifs ou une acceptation là où il y avait un 500. Poste (lecture seule) : il n'envoie jamais null pour ces colonnes (colonnes Drift entières non nullables, défaut 0 ; `_venteEnJson` en `real()` non nullable).
**Listé, NON corrigé** : sur `sales`, `delivery_fee`, `status`, `mecef_status` à null = 500 mesuré ; sur `sale_lines`, `is_manual_price` à null = 500 mesuré (colonnes non validées passées telles quelles à `fill()`) ; `SupplierCatalogService::creer()` crée un fournisseur ARCHIVÉ quand `is_active` vaut null (`(bool) null`, lu dans le code, non reproduit). Non sondé : enums invalides (`payment_mode`, `vente_sexe`, `gravite`), clés étrangères inexistantes de la fiche (`feed_product_id`, `treatment_product_id`), élément non tableau dans une liste. Non vérifié : MySQL (sous MySQL non strict un null dans une colonne NOT NULL peut être converti en 0 sans erreur : le défaut y serait silencieux ; le mode SQL de la production n'a pas été consulté). Aucun audit indépendant de 15.38.

**F0.93 FAIT (14/10/2026) — poste : réserves de l'audit (parité Unicode, horloge injectée, double validation).** (1) **La consigne littérale (« trim ASCII seul ») aurait créé une NOUVELLE divergence** : l'agent a exécuté la vraie règle PHP `CategorieRationLapin::cle` : après `trim()` (" \t\n\r\0\x0B"), `Str::ascii` transforme en espace ou supprime encore de nombreux caractères (U+00A0, U+1680, U+2000–U+200B, U+2028/2029, U+202F, U+205F, U+3000 → espace ; contrôles C0, U+007F, U+0080–U+009F, U+180E, U+200C–U+200F, U+2060, U+FEFF supprimés ; U+0010 et U+0013 conservés ; `\f` supprimé alors que `trim()` PHP ne le retire pas). `_trimPhp` + `_plier` reproduisent ce traitement MESURÉ : 644 libellés générés par PHP (92 caractères blancs/contrôle × 7 positions) → **0 écart après correction, 310 avec l'ancienne règle** ; règle serveur INCHANGÉE ; `cleDuStade` délègue à `cle`. (2) `_absorberVentes` : `?? _maintenant()` (2 tests à horloge figée). (3) `SoinsRepository.validerTraitementsDuJour` : protocole recalculé DANS UNE TRANSACTION Drift, seuls les traitements dus, non administrés et cochés sont écrits, écriture extraite en `_inserer` ; les 5 fiches (lapins, porcs, escargots, pondeuses, reproducteurs) y délèguent et relisent `_validationEnCours` ; deux appels en rafale (`Future.wait`) = 1 soin, 1 rémanence. Mesuré par moi : analyze propre, **Flutter 1 866 verts + 4 ignorés** (1 808 + 40 parité + 2 ventes + 16 idempotence), aucun `flutter_tester` actif, README identiques (`B5CB126C…`), en-tête une fois, `docs/`/`prototype_html/` vides ; Laravel non touché (1 302). 13 mutations annoncées tuées (M9 « validation hors transaction » tuée par les deux tests en rafale : c'est la transaction qui protège ; M13 corrigée), non rejouées par moi.
**Ouvert** : lettres d'autres écritures — `Str::ascii` translittère (le « е » cyrillique, « ß ») : « Jеune » avec un е cyrillique donne `jeune` au serveur et `null` au poste (proposition : normaliser le libellé à la saisie, côté web) ; une dizaine d'autres replis `DateTime.now()` de `sync_engine.dart` n'utilisent pas l'horloge injectée (rémanence, `updated_at`, pointages, achats, soins, état) ; sélecteur de bande et garde « jour futur » hors périmètre. Non vérifié : double clic réel (aucun test de widget), deux postes validant hors ligne (deux UUID, comportement de `/sync/push` non mesuré), sérialisation des transactions Drift sur `createInBackground` (base en mémoire seulement), U+00AD et invisibles hors de la liste des 92, copie manuelle des cas serveur (rien ne relit `GlossaireFicheLapinsTest.php`), MySQL, `sync_reel_test`. Aucun audit indépendant de F0.93.

**F0.94 FAIT (14/10/2026) — poste : les fiches journalières du cheptel descendent enfin au poste (`_absorberFichesJournalieres`).** Avant : `livestock_daily_entries` servi par `/sync/pull` mais sans aucun absorbeur — les journées saisies sur le web et les fiches recalculées en cascade (15.31) ne descendaient jamais. Absorbeur appelé après `_absorberBandes` : fusion par id, jamais de suppression (tirage incrémental n'efface rien) ; `pending`/`conflict` jamais écrasées ; fiche `synced` = version serveur (cascade 49/47/50 + vente de 6 → 43/41/44) ; `current_quantity` de la bande jamais écrit ; refus strict de TOUT le lot avec rollback et curseur bloqué (clé non liste, non-objet, id/bande non UUID, bande inconnue, date illisible/avec heure, nombre négatif/fractionnaire/NaN/infini, colonne obligatoire absente, id ou (bande, jour) en double) ; nombres servis en chaîne acceptés (MySQL) ; `don` nul → 0. Même bande+jour sous autre id : fiche locale conservée quel que soit son statut + avertissement daté ; au push le serveur la refuse (unicité) → `conflict` avec son motif ; une fois la fiche web absorbée, la saisie du poste la reprend sous le même id. Resynchronisation unique (`fiches_resync_f094`, écrite après tous les absorbeurs). **Garde-fou général** : les 46 clés de `/sync/pull` sont chacune absorbée ou ignorée avec raison (seule : `server_time`) ; test de cohérence avec `SyncController::pull` (sauté avec raison si le dépôt Laravel est absent) ; il était rouge avant le ticket. Mesuré par moi : analyze propre, **Flutter 1 910 verts + 4 ignorés** (1 866 + 44), aucun `flutter_tester` actif, README identiques (`D08D3E0D…`), en-tête une fois, `sync_engine.dart` `82013E79`, `fiches_tirage_test.dart` présent, `docs/`/`prototype_html/` vides ; Laravel non touché (1 302). 25 mutations annoncées dont 24 tuées (survivante M20 : transaction retirée, jugée équivalente par l'agent), non rejouées par moi. Schéma Drift v37 inchangé.
**Colonnes serveur NON portées** : `effectif_m/f/sevres/smeres`, `cat_eff_repro/sevre/jeune/4` (tickets suivants), `feed_product_id`, `treatment_product_id`, `treatment_dose`, `symptomes`, `vente_sexe`, `vente_montant`. **À DÉCIDER** : (1) fiche du poste déjà en conflit face à la fiche web du même jour : « Relancer » refusé à nouveau, aucun geste pour adopter la version serveur — bouton « Prendre la version du serveur » proposé, mais il supprime une saisie → au client ; (2) copie `synced` sous un autre id (fiche disparue du serveur puis ressaisie sur le web) : conservée et signalée, jamais remplacée (choix de l'agent, à confirmer) ; (3) l'avertissement de collision n'apparaît que dans le bandeau éphémère du bouton Synchroniser, pas dans l'écran Synchronisation ; (4) un lot refusé bloque le tirage des tables suivantes à chaque synchronisation tant que le serveur sert la ligne fautive (même faiblesse que le journal, point A.3 de la réévaluation) ; (5) les fiches `pending` suivantes gardent leur effectif calculé localement après absorption d'un `effectif_final` corrigé (le serveur recalcule au push). **Incident d'outillage** : l'agent a lancé `py -c` (interdit) : seul un script du scratchpad a été cassé, corrigé ; empreinte du dépôt vérifiée. Non vérifié : vrai serveur (`sync_reel_test`, sérialisation `toArray()` simulée d'après la lecture du code), MySQL, production (une seule fiche réelle incohérente bloquerait le tirage — non mesuré), coût du tirage complet unique sur une vraie ferme, rendu de l'avertissement et de l'écran Synchronisation (aucun test de widget), comportement de `fill()` côté serveur pour les colonnes non portées (lu, pas testé), fuseaux autres que UTC+1. Aucun audit indépendant de F0.94.

**DÉCISIONS CLIENT du 14/10/2026 (effectif automatique par catégorie).** QC1 règles de ventilation de la maquette fiche par fiche, telles qu'écrites ; QC2 ventes imputées comme la maquette (engraissement/chair) tant qu'aucun lien produit→catégorie n'existe ; QC3 passage de stade = champ SAISI « Passage de stade » (un fait, pas un effectif) ; QC4 bande sans historique = effectif de départ de chaque catégorie saisi UNE FOIS puis verrouillé (règle 14.11) ; QC5 effectifs M/F/Sevrés/S-Mères (et équivalents porcs/escargots) RESTENT SAISIS ; QC6 portée = LAPINS ET PORCS d'abord (barèmes volailles et escargots absents du serveur, à fournir par le client) ; QC7 champs calculés grisés et non focalisables, champs saisis actifs ; effectif recalculé EN DIRECT à la saisie (comportement `oninput` de la maquette). Ordre : Laravel (service d'effectif par catégorie + validation `cat_eff_*` au push + colonnes de saisie) puis poste (Drift v38, envoi, écran).

**PLAN « effectif automatique par catégorie » (lapins + porcs) — 14/10/2026, plan en lecture seule.** Recommandation retenue : **persister les MOUVEMENTS par catégorie** (morts et dons par catégorie, passage, achats, nés) avec un **départ unique**, et laisser le serveur recalculer `cat_eff_*` comme valeur dérivée (comme `effectif_final`) ; garder seulement `cat_eff_*` par jour (état actuel du web) ne permet ni de recharger la ventilation (la ligne 204 du poste reporte le total des morts sur « Reproducteur ») ni de recalculer en cascade après saisie rétroactive ou vente antidatée. **Formules** (chaque catégorie bornée à 0 ; v = dernière fiche ANTÉRIEURE de la même bande ; p = passage) — LAPINS : R = max(0, R_v − mR − dR) ; J = max(0, J_v + achat + né − mJ − dJ − p) ; C = max(0, C_v − vente − mC − dC + p) ; PORCS : R = max(0, R_v + achat − mR − dR) ; P = max(0, P_v + né − mP − dP − p) ; M = max(0, M_v − vente − mM − dM + p) ; total inchangé E = max(0, E_v + achat + né − (mort + vente + don)). **Jeu calculé à la main (lapins, départ R10/J20/C30, rations 120/30/60)** : J1 (achat 2, nés 5, mort J1) → 10/26/30 total 66, provende 3 780 g ; J2 (vente 4, morts R1 et C2, don J1) → 9/25/24 total 58, 3 270 g ; J3 (vente 30, mort J2) → 9/23/0 total 26 mais SOMME DES CATÉGORIES 32 ≠ 26 (plancher), 1 770 g. Porcs (départ R10/P24/M86, rations 2 000/300/600) : 86 900 / 81 300 / 78 000 g. **Défauts du web LUS, non reproduits** : (a) `loadDay()` d'un jour existant ne remet pas à jour les compteurs de morts/dons (réenregistrer réécrit `mort`/`don` avec des valeurs périmées) ; (b) changer la date (`wire:model.live`) n'appelle pas `loadDay` ; (c) `getPreviousEffectifProperty` cherche la veille sur TOUTES les bandes de l'espèce alors que `saveDay` écrit sur `lots->first()` ; le web porcs IGNORE les achats dans le Reproducteur alors que la maquette les compte ; le push reprend les `cat_eff_*` du client sans validation et ne lance aucune cascade ; la cascade 15.31 ne recalcule que `effectif_final`. **Tickets prévus** : 15.39 (Laravel : service + schéma), 15.40 (Laravel : push), 15.41 (fiche web lapins), 15.42 (fiche web porcs), F0.95 (poste : Drift v38, absorbeur, service Dart avec parité EXÉCUTÉE contre PHP, resynchronisation unique `fiches_resync_f095`), F0.96 (poste lapins), F0.97 (poste porcs), puis audit indépendant.
**DÉCISIONS CLIENT du 15/10/2026** : **D3** passage de stade = TRANSFERT entre catégories (lapins Jeune → Lapin de Chair, porcs Porcelet → Porc Marchand), total inchangé, refus si le nombre dépasse l'effectif de la catégorie source ; **D4** effectif de départ = effectif au DÉBUT du jour de saisie (les mouvements du jour s'appliquent ensuite), la somme des catégories doit égaler l'effectif total de départ sinon refus ; **D7** un ancien poste qui envoie des morts/dons non ventilés sur une bande déjà ventilée est REFUSÉ avec un motif clair en français (mettre en service Laravel et poste le MÊME jour) ; **D11** un achat de porcs gonfle le Reproducteur comme la maquette (corrigeable plus tard par un champ de destination). Restent à trancher (recommandations de l'agent, non bloquantes, appliquées par défaut si vous ne dites rien) : D2 « Lapereau » (Morts/Dons) = « Jeune » (rationnement) ; D5 qui peut déverrouiller un départ erroné (RBAC, non tranché) ; D6 bandes déjà saisies sur le web : la dernière fiche aux 3 `cat_eff_*` renseignés sert de départ implicite verrouillé ; D8 avertissement daté quand somme ≠ total ; D9 morts supérieurs à la veille = plancher + avertissement ; D12 jours antérieurs au départ affichés « — » ; D15 libellé porcs « Porc Marchand » (maquette) ou « Jeune porc » (barème) ; D16 porter `effectif_m/f/sevres/smeres` au poste dès la v38.

**15.39 FAIT (15/10/2026) — Laravel : service d'effectif par catégorie + schéma (sans interface, sans push, sans poste).** Migration `2026_10_15_000001` : 10 colonnes `unsignedInteger` NULLABLE sans défaut sur `livestock_daily_entries` (`mort_repro/sevre/jeune`, `don_repro/sevre/jeune`, `passage_sevre_jeune`, `cat_depart_repro/sevre/jeune`), idempotente, `down()` n'enlève que ces colonnes, ajoutées au `$fillable`. `EffectifParCategorieService` (+ `EffectifCategoriesJour`) : `calculerJour` et `verifierDepart` PURS (lapins et porcs), formules du plan, D3 (passage = transfert), D4 (départ au début du jour, somme = total sinon refus), D8 (indicateur somme ≠ total, pas un blocage), D11, null jamais lu comme 0 ; `recalculerChaine($lotId)` idempotente (0 écriture au second passage, `updated_at` inchangé) et transactionnelle, ne touche ni aux mouvements ni à `effectif_final` ; sans départ complet ou autre espèce = pas de chaîne, rien d'écrit ; départ incohérent = toute la chaîne refusée. `RecordSaleOnFicheElevageAction::recalculerEnCascade` appelle la chaîne dans la même transaction (fiche `firstOrCreate` sur bande à chaîne : mouvements ventilés à 0 puis catégories) ; SANS chaîne comportement INCHANGÉ (les 14 tests de 15.31 passent tels quels). Rapport à blanc `elevage:effectif-categories-rapport` (lecture seule ; la tête implicite D6 n'est calculée que pour le rapport, jamais écrite). Mesuré par moi : **Laravel Feature 1 360 verts (15 090 assertions)**, README identiques (`D1B5F74D…`), en-tête une fois, 6 nouveaux fichiers présents, `docs/`/`prototype_html/` vides. 33 mutations annoncées tuées, non rejouées par moi ; service comparé à une réécriture indépendante sur 200 combinaisons.
**⚠️ POUR 15.40** : (1) l'ajout au `$fillable` ouvre le push : `pushDailyEntries` fait `fill()` sur tout ce que le client envoie, donc ces 10 clés seraient écrites SANS validation (ni borne ≥ 0, ni type) ; le poste actuel ne les envoie pas ; (2) `porteUneColonneDeSaisie` lit aussi le `$fillable` : une fiche réduite portant l'une de ces clés compterait « avec saisie » ; (3) une fiche poussée sans ventilation sur une bande à chaîne rend ses catégories inconnues : le push doit la refuser (D7) ou la laisser inconnue ; (4) pull : 10 clés `null` de plus sur chaque fiche (testé sur le vrai endpoint), l'absorbeur F0.94 les ignore (lu, poste non exécuté) ; aucune bande actuelle n'a de départ saisi. **À confirmer** : « catégorie source » du refus D3 = source après ses autres mouvements du jour (l'autre lecture : source de la veille) ; passage excessif dans une fiche déjà stockée (vente antidatée) : ramené à la source et signalé dans `avertissements`, saisie conservée, la vente n'est pas cassée ; départ incohérent stocké : aucune catégorie calculée pour la bande, la vente reste enregistrée (où afficher le motif : 15.41/15.42) ; qui écrit la tête implicite D6 et avec quel contrôle D4 (non tranché) ; défauts web (a)(b)(c) non traités ici (15.41/15.42). Non vérifié : MySQL (`dropColumn` du `down()`, `lockForUpdate` sans effet sous SQLite), production (le rapport à blanc n'a tourné que sur des données de test : à lancer sur les bandes réelles avant 15.41/15.42), rendu, Dusk, poste, `sync_reel_test`, volume (`recalculerChaine` relit toutes les fiches de la bande à chaque vente, ~365 par an, non mesuré), concurrence de deux ventes simultanées. Aucun audit indépendant de 15.39.

**15.40 FAIT (15/10/2026) — Laravel : push des fiches, ventilation par catégorie (reprise après coupure de session).** Le premier agent a été coupé par la limite de session (code et test écrits, ni mutations ni journal) ; j'ai vérifié l'état réel avant de le reprendre (journal intact à `D1B5F74D…`, fichiers modifiés listés par date), puis il a terminé. `pushDailyEntries` : 10 colonnes `integer|min:0|nullable` SANS plafond (motif français, la fiche entière refusée, les autres de l'envoi passent ; null = clé absente) ; si une clé de ventilation est présente les trois sont exigées et `mort`/`don` = somme des trois (comparé à l'état fusionné) ; **D7** : sur une bande à chaîne `mort`/`don` > 0 sans ventilation REFUSÉ (« ancien poste », mise à jour nécessaire), un total à zéro accepté (catégories à 0), sans chaîne inchangé ; **D4** : `cat_depart_*` seulement sur une bande SANS chaîne, somme = effectif au début du jour, sinon « effectif de départ déjà fixé le JJ/MM/AAAA » (seul le renvoi identique de la fiche de départ passe) ; refusé pour les espèces autres que lapins et porcs (règle ajoutée par l'agent) ; `cat_eff_*` et `effectif_final` envoyés par le client NON écrits sur une bande à chaîne ; les `cat_eff_*` ne comptent plus comme saisie pour `porteUneColonneDeSaisie` (une fiche réduite d'id inconnu qui ne porte qu'un `cat_eff_*` est désormais refusée, sur TOUTES les bandes) ; **D3** : passage supérieur à la source refusé (source après les autres mouvements du jour) ; fiches traitées par (bande, jour), réponse dans l'ordre d'envoi, UNE cascade par bande en fin de lot depuis le plus ancien jour accepté (totaux, catégories, `current_quantity`), renvoi identique sans changement d'`updated_at` ; la fiche réduite F0.90 n'est pas affectée. **Changement de comportement annoncé : le push lance désormais la cascade pour TOUTES les bandes (ferme le point ouvert de 15.31) et met à jour `current_quantity`, ce qu'il ne faisait jamais.** Mesuré par moi : **Laravel Feature 1 419 verts (15 496 assertions)** (1 360 + 59), 10 min 08 s sous charge d'autres processus PHP, README identiques (`ECDFC46E…`), en-tête une fois, empreintes `SyncController` `A75E87F1`, `MotifsRefusPush` `A795D32F`, `EffectifParCategorieService` `5AC7A9E2`, `RecordSaleOnFicheElevageAction` `EE06CF68`, `SyncFichesVentilationTest` `31CB3EC7` (59 tests, 406 assertions), `docs/`/`prototype_html/` vides. 30 mutations annoncées + 2 rejouées après renforcement (2 tests trop faibles renforcés : `assertEquals` confondait `null` et `0`, cas d'un départ identique renvoyé sur une fiche qui n'est pas la tête) ; 2 survivantes équivalentes (ne pas neutraliser les `cat_eff_*` sur bande à chaîne, la cascade les réécrit ; prendre le dernier départ au lieu du premier, un seul départ complet possible), non rejouées par moi.
**Contrat `/sync/push`** : forme inchangée, 10 clés acceptées en plus ; nouveaux motifs : négatif/non entier, ventilation incomplète, total ≠ somme, D7, départ incomplet/somme fausse/déjà fixé/espèce non suivie, passage trop grand. **Poste actuel** : aucun nouveau rejet tant qu'aucune bande n'a de départ (toutes aujourd'hui) ; verra les `effectif_final` corrigés et `current_quantity` mis à jour au pull suivant une fiche poussée sur un jour antérieur ; dès qu'une bande aura un départ ses fiches avec morts/dons seront refusées jusqu'à mise à jour du poste → **poste et serveur en service LE MÊME JOUR**. **À DÉCIDER** : (1) AUCUN plafond sur les 10 colonnes : sous MySQL une valeur > 4 294 967 295 donne une erreur 500 pour tout l'envoi (déjà le cas pour `achat` et `mort`) — un `max` de capacité sur toutes est recommandé ; (2) source D3 : après les autres mouvements du jour (retenu) ou la veille ; (3) sans chaîne les `cat_eff_*` du client restent écrits (seule saisie par catégorie du poste actuel et du web) ; (4) une fiche poussée avant la tête peut rendre le départ stocké incohérent : le service refuse alors toute la chaîne, rien n'est écrit, AUCUN motif ne remonte au poste alors que la fiche est acceptée ; (5) D5 : un départ posé est verrouillé côté push, qui peut le corriger n'est pas tranché. Non vérifié : MySQL, concurrence (deux postes poussant la même bande), production, volume, poste Flutter et `sync_reel_test`, Dusk. Aucun audit indépendant de 15.40.

**15.41 FAIT (16/10/2026) — Laravel : fiche web LAPINS, effectif automatique par catégorie.** Effectifs Reproducteur / Jeune / Lapin de Chair CALCULÉS, grisés (`disabled`) et recalculés EN DIRECT via `EffectifParCategorieService::calculerJour` (aucune formule recopiée dans la vue) ; mouvements par catégorie (`mort_*`, `don_*`, `passage_sevre_jeune`) persistés ET rechargés ; départ en 3 champs (effectif au DÉBUT du jour, somme = total) saisi UNE fois puis verrouillé (D5 non tranché : aucun déverrouillage) ; bande sans chaîne = « — » et `cat_eff_*`/`feed_qty_kg` restent null, jamais 0 ; D6 : les `cat_eff_*` anciens saisis à la main ne sont pas touchés par un réenregistrement et AUCUN départ n'est copié automatiquement ; D8 avertissement quand somme ≠ total ; D9 plancher + avertissement (contrôlé sur le total des morts, pas catégorie par catégorie) ; D12 « — » avant le départ ; D2 « Lapereau » = « Jeune » ; rationnement par catégorie avec clé stable conservée ; autonomie alimentaire « — » et aucune alerte si une catégorie est inconnue. **Défauts du web corrigés** : (a) compteurs de morts/dons périmés au rechargement d'un jour ; (b) changer la date ne rechargeait pas le formulaire (étendu : un jour d'un AUTRE MOIS ne se chargeait pas non plus) ; (c) la veille et les requêtes portent maintenant sur LA bande de la fiche (`bandeDeLaFiche()` dans `AvecProphylaxieDuJour`, défaut `lots->first()` ; fiche porcs inchangée) ; découverte : Livewire met chaque propriété calculée en cache pour toute la requête → après `saveDay` l'écran montrait l'état d'avant (corrigé par `purgerCalculs()`). **Changement de comportement annoncé : `saveDay` appelle désormais la cascade pour TOUTES les bandes (`current_quantity` = dernière fiche ; avant : effectif du jour édité même antérieur) ; `mount()` charge le jour courant s'il est déjà saisi.** Modification d'un fichier de 15.40 : `EffectifParCategorieService` `5AC7A9E2` → `5B3969D0` (ajout PUREMENT ADDITIF de `etatPourJour()` en lecture seule : modes sans_chaine/avant_depart/refus/chaine ; aucune fonction existante modifiée). Mesuré par moi : **Laravel Feature 1 478 verts (15 970 assertions)** (1 419 + 59), **3 dépréciations PHPUnit au lieu des 2 connues, la troisième n'est PAS identifiée**, README identiques (`A85CEB68…`), en-tête une fois, empreintes `FicheLapins` `4AA0CD89`, vue `67466F4C`, `AvecProphylaxieDuJour` `7475A3B5`, `FicheLapinsEffectifAutomatiqueTest` `214F28BB` (58 tests), 7 fichiers touchés sans caractère de contrôle, `php -l` OK, fichiers de 15.40 inchangés, `docs/`/`prototype_html/` vides. Jeu de la maquette vérifié à l'écran ET en base (R10/J20/C30 → 10/26/30 total 66, 3 780 g ; 9/25/24 total 58, 3 270 g ; 9/23/0 total 26 somme 32 avec avertissement, 1 770 g). 42 mutations définies, 39 tuées, 3 survivantes (M17 et M27 équivalentes, M18 sans objet) + 15 rejouées sur le code final avec restauration SHA-256 vérifiée — non rejouées par moi.
**À DÉCIDER / OUVERT** : D5 (déverrouillage d'un départ erroné) ; D6 (migration des bandes déjà saisies, après `elevage:effectif-categories-rapport` sur les vraies bandes) ; confirmation client de D2, D8, D9, D12 ; textes d'avertissement (de l'agent) à valider ; une fiche ancienne non ventilée oblige à ventiler ses morts/dons avant réenregistrement (refus si le total ventilé est 0) ; passage de stade : champ saisi hors maquette, libellé « (hors maquette) ». **Entorse de méthode** : l'agent a utilisé des scripts (Python, `sed`) malgré la consigne d'édition ciblée ; ils ont corrompu son propre test (`\b` perdu → caractères backspace), corrigé ; un script Python a retiré un mémo de `FicheLapins.php` ; mon contrôle d'octets des 7 fichiers est propre. Un premier passage complet avait échoué (`IconesEmbarqueesTest` : l'icône `flag` du bloc Départ n'est pas embarquée, remplacée par `edit_note`). Non vérifié : rendu navigateur et JavaScript Livewire (le « en direct » réel, le focus et l'apparence des champs `disabled` ne sont pas vus), Dusk, MySQL, production, envoi du poste vers cette fiche. Aucun audit indépendant de 15.41.

**15.42 FAIT (16/10/2026) — Laravel : fiche web PORCS, effectif automatique par catégorie (miroir de 15.41).** Reproducteur / Porcelet / Porc Marchand calculés par `EffectifParCategorieService::calculerJour(PORCS, …)`, `disabled` (ids de la maquette `cat-eff-repro`, `cat-eff-porcelet`, `cat-eff-jeune`), recalcul en direct sans formule dans la vue ; **les ACHATS comptent maintenant dans le Reproducteur (D11) — défaut du web corrigé** (il les ignorait) ; passage de stade = champ saisi « Porcelet → Porc Marchand » (hors maquette, dit à l'écran), refusé s'il dépasse le Porcelet après ses autres mouvements du jour ; mouvements par catégorie persistés et rechargés ; changement de date → `loadDay` (y compris autre mois) ; veille, vente du jour, jour chargé, tableau mensuel, prophylaxie et enregistrement portent sur LA bande de la fiche (`bandeDeLaFiche()`) ; bande sans chaîne = « — » partout, plus aucun pourcentage de démonstration, départ en 3 champs verrouillé après enregistrement ; enregistrement = service + chaîne + cascade dans une transaction ; D8/D9/D12 comme 15.41. **Le piège du rapprochement par fragment de libellé existait AUSSI chez les porcs, en pire** (`str_contains` sensible à la casse sur 'Porcelet', 'Jeune', 'reproducteur' avec secours 300/600/2000 : un libellé « Reproducteur » ou « Porc Marchand » retombait en silence sur la constante) → `App\Support\CategorieRationPorc` (clés `reproducteur`/`porcelet`/`marchand`, casse et accents indifférents) ; D15 : le barème « Jeune porc » n'est PAS renommé, l'écart avec « Porc Marchand » (maquette) est signalé dans la vue et verrouillé par un test. Mesuré par moi : **Laravel Feature 1 570 verts (16 787 assertions)** (1 478 + 92 : 63 dans le nouveau fichier, `RationnementPorcsTest` de 7 à 36 tests), 3 dépréciations PHPUnit, README identiques (`485CA0B0…`), en-tête une fois, empreintes `FichePorcs` `C0EB739A`, vue `EE15F879`, `CategorieRationPorc` `4F905E18`, `FichePorcsEffectifAutomatiqueTest` `1689E9A5`, 6 fichiers sans caractère de contrôle, `php -l` OK, fichiers de 15.40/15.41 INCHANGÉS (`FicheLapins` `4AA0CD89`, service `5B3969D0`, trait `7475A3B5`, cascade `EE06CF68`, `SyncController` `A75E87F1`), `docs/`/`prototype_html/` vides. Jeu vérifié à l'écran ET en base (R10/P24/M86 → J1 13/31/86 total 130, 86 900 g ; J2 12/31/80 total 123, 81 300 g ; J3 12/30/75 total 117, 78 000 g ; J4 plancher 12/0/75 total 77 somme 87 avec avertissement, `current_quantity` 77) + recomputation indépendante sur 25 combinaisons. 27 mutations annoncées, 26 tuées du premier coup, M22 (tableau mensuel sur toutes les bandes) tuée après renfort, 0 survivante finale — non rejouées par moi.
**Les 3 dépréciations PHPUnit sont IDENTIFIÉES** : `@dataProvider` en commentaire de doc, déprécié en PHPUnit 11 — `CoherenceFormulesElevageTest::test_the_weighed_total_survives_the_round_trip`, `CreditsProjetTest::test_les_pages_publiques_creditent_les_trois_structures`, `FicheLapinsEffectifAutomatiqueTest::test_chaque_mouvement_met_a_jour_les_categories_en_direct` (la troisième ajoutée par 15.41) → passer à l'attribut `#[DataProvider]` (petit ticket, non fait). **À signaler** : `FichePorcs.php` et sa vue étaient en CRLF, réécrits en entier donc passés en LF ; changement de comportement : `saveDay` lance la cascade pour toutes les bandes, le tableau mensuel et l'export PDF portent sur la bande choisie. Méthode : aucun script ni regex n'a modifié du code ou des tests (seul un exécutant de mutations) ; une commande `python3` sans code lancée par erreur, sans effet. **Ouvert** : D15 ; D5 ; D6 (le rapport à blanc n'a pas été lancé sur les bandes porcines de la ferme) ; confirmation client de D2/D8/D9/D12 ; libellés des blocs Morts et Dons de la fiche porcs (« Reproducteur (Truie/Verrat) », « Porc marchand / Engraiss. ») non alignés sur la maquette ; doublon de catégorie dans le barème : première ligne retenue ; parité Dart/PHP de `CategorieRationPorc` non exécutée (le poste garde sa règle de rapprochement : F0.97). Non vérifié : rendu navigateur et JavaScript Livewire, Dusk, MySQL, production, envoi du poste vers cette fiche. Aucun audit indépendant de 15.42.

**F0.95 FAIT (16/10/2026) — poste : socle de l'effectif automatique par catégorie (lapins et porcs, SANS écran).** Reprise après coupure de session : j'ai vérifié l'état réel avant de reprendre l'agent (journal intact à `485CA0B0…`, schéma déjà en v38, 7 fichiers écrits, `sync_engine.dart` encore à l'empreinte de F0.94) ; l'agent a relu son état contre ses sauvegardes et n'a rien refait. **Schéma Drift v38** : 18 colonnes nullables sans défaut (null = inconnu, jamais 0) — `mort_*`, `don_*`, `passage_sevre_jeune`, `cat_depart_*`, `cat_eff_repro/sevre/jeune`, `cat_eff_4` (nom explicite : la conversion automatique aurait donné `cat_eff4`) et `effectif_m/f/sevres/smeres` (D16) — via `_ajouterColonneSiAbsente`, migration vérifiée depuis chaque version v1 à v37. **Service Dart pur** `effectif_par_categorie.dart` (miroir du service PHP : `calculerJour`, `verifierDepart`, `effectifFinal` borné à 0, `simulerChaine`, `etatPourJour`, `refusDuPassage`). **Absorbeur strict** : clé absente = garde la valeur locale, null explicite = « inconnu » ; valeur négative/fractionnaire/NaN/infinie = refus de tout le lot ; `pending`/`conflict` jamais écrasées. **Envoi** : ne part PLUS jamais `effectif_final` (il partait jusqu'ici, le serveur l'ignorait) ni `cat_eff_*` ; `mort`/`don` = somme de la ventilation quand elle est complète ; `cat_depart_*` seulement sur la fiche tête de chaîne ; fiche réduite F0.90 inchangée. **Cascade locale UNIQUE** `FicheJournaliereRepository.recalculerEnCascade` utilisée par la caisse (cascade propre à la caisse supprimée, un test lit la source pour l'empêcher de revenir ; **chaque fiche bornée à 0 comme le serveur : referme le point ouvert (5) de F0.89**). Resynchronisation unique `fiches_resync_f095` écrite après tous les absorbeurs. Mesuré par moi : `flutter analyze` propre, **Flutter 1 983 verts + 4 ignorés** (1 910 + 73 : migration +1, service 26, cascade 15, synchronisation 31), aucun `flutter_tester` actif, README identiques (`3A470617…`), en-tête une fois, 12 fichiers touchés sans caractère de contrôle, schéma 38, `docs/`/`prototype_html/` vides ; Laravel non touché (516 fichiers identiques par empreinte selon l'agent ; suite non relancée, 1 570 au dernier relevé). **Parité EXÉCUTÉE contre le vrai PHP, 0 écart** (annoncée par l'agent, non rejouée par moi) : `calculerJour` 640 combinaisons, `verifierDepart` 160, chaîne/état/refus de passage 160 bandes avec Laravel démarré sur SQLite en mémoire, cascade complète 120 bandes ; les 4 motifs de refus (D7, D4 déjà fixé, total ≠ somme, passage trop grand) comparés mot pour mot au vrai `MotifsRefusPush` ; sauté avec raison si PHP/Laravel absents. Jeux à la main verts (lapins 10/26/30, 9/25/24, 9/23/0 ; vente antidatée de 6 par la caisse → Chair 24/18/0, totaux 60/52/20, bande 20 ; jour sauté 9/26/26 ; porcs 13/31/86, 12/31/80, 12/30/75, J4 12/0/75 ; passage de 8 → 10/12/38 ; passage de 25 sur une source de 20 refusé). 28 mutations annoncées toutes tuées (aucune par erreur de compilation), non rejouées par moi.
**Initiatives de l'agent À VALIDER** : (1) quand le formulaire actuel (qui ne saisit que des totaux) change un total qui contredit une ventilation descendue du web, cette ventilation devient inconnue (null) — sinon l'envoi aurait expédié l'ancienne somme à la place du total saisi, sans message (mutation M25) ; (2) `fiches_resync_f095` n'est marquée faite que si le serveur sert déjà la ventilation (règle de F0.85) : face à un serveur antérieur à 15.39 le tirage reste complet à chaque synchronisation ; deux tests existants ajustés (modèle de serveur de `fiches_tirage_test.dart` sert les 10 clés à null ; `journal_tirage_test.dart` « schéma ≥ 37 »). **⚠️ BLOQUANT DE MISE EN SERVICE** : tant que F0.96 et F0.97 ne sont pas livrés, le poste reste un « ancien poste » au sens de D7 : dès qu'une bande aura un départ posé sur le web, toute fiche du poste avec des morts ou des dons sur cette bande sera REFUSÉE (conflit visible) → NE POSER AUCUN DÉPART en production avant ces deux écrans. **Réserve de méthode** : « tests rouges d'abord » non tenu partout — le service a été écrit avant son test (preuve : parité exécutée + 11 mutations), les tests de synchronisation n'étaient rouges qu'à la compilation (preuve : mutations M17 à M28) ; seuls la migration et la cascade ont été réellement rouges avant le code. `cascade_categories_test.dart` importe le générateur de scénarios depuis `effectif_par_categorie_test.dart` (un fichier d'aide séparé serait plus propre). Non vérifié : vrai serveur de bout en bout (`sync_reel_test` non lancé, push simulé par un modèle écrit à la main), MySQL, production, volume, rendu, `flutter build windows`, `audit_fidelite.py` (aucun écran touché). Aucun audit indépendant de F0.95. **Ouvert** : D5, D6, D15, confirmation de D2/D8/D9/D12, calendrier F0.96/F0.97.

## Réévaluation des dettes techniques et des à-faire (12/10/2026)

**État vérifié aujourd'hui** : README identiques (`2E2E9824…`, dernier ticket F0.84-bis) ; `flutter analyze` propre ; Flutter 1 552 verts + 4 ignorés ; Laravel Feature 1 087 verts. L'écart avec les derniers chiffres consignés (1 500 / 1 078) vient du ticket T2 (F0.85, grand livre) INTERROMPU par la limite d'usage de l'API : code et tests présents (nouveau schéma Drift v37, `nature_compte.dart`, 52 + 9 tests), mais NI journalisé dans les README, NI audité, mutations inachevées. Il ne compte pas comme livré.

### A. Défauts de justesse connus (priorité haute)
1. T2 interrompu : état à valider (mutations, intégrité de fichiers restaurés), journaliser, auditer.
2. Journal : un montant de ligne NÉGATIF est accepté (règle comptable à décider).
3. Journal : un serveur durablement vide finit par vider le poste après deux tirages ; un journal refusé durablement bloque les 14 absorbeurs suivants.
4. Course d'horloge du protocole : `server_time` tronqué à la seconde et filtre `updated_at > since` ; une modification dans la même seconde peut ne jamais être servie (toutes tables ; relance de rattrapage pour le seul journal).
5. Les 7 anciennes tables de `/sync/push` (livestock_daily_entries, sales, veterinary_records, expenses, livestock_reproduction_events, purchases, attendance_records) répondent 500 à une ligne non objet : ticket Laravel à ouvrir (elles portent des opérations comptables).
6. `pendingCount` ignore products, suppliers, customers, advances, imputations, returns, refunds.
7. Les absorbeurs supposent un tirage complet de lignes actives ; un tirage incrémental effacerait à tort (documenté, non corrigé hors journal).
8. Dernier-écrivain-gagne (pas de version par ligne), y compris le poste qui renvoie son statut local et peut rétrograder un document signé sur le web.
9. « Réponse perdue puis retrait local » : le document réapparaît actif. Pas de geste de résolution d'une archive refusée hors écran Synchronisation.
10. `expenses` et `attendance_records` sans entrée dans `relancer()` ; « Dépenses Totales » compte encore les achats refusés/retournés ; le serveur ne sert pas `amount_paid` dans `purchases`.
11. Plan comptable : `natureDebitrice` (copie fidèle au poste) est PAR CLASSE, discutable pour 109, 119, 129, 47x, 48x, 56x, 82/84/86/88 : sans effet tant qu'aucune écriture n'y est passée.
12. Phase A : sélecteurs Immobilisations et Rapprochement bancaire gelés sur les comptes d'avant l'import (on ne peut pas enregistrer un bien sur une nouvelle nature du plan officiel) ; sélecteurs de saisie manuelle à 1 337 comptes ; recherche globale : défaut de précédence `OR` (un compte archivé peut remonter).

### B. Décisions client / cabinet FAGUEZ (rien n'a été tranché à leur place)
- Phase B du plan SYSCOHADA : table de remappage (17 comptes à changer de code, dont 531 → 571 net ; 12 de sens différent ; 5 absents du CSV : 313, 521101, 521201, 606, 657) ; libellés corrompus 54, 66, 603 et une trentaine avec notes ; élargissement de `label` à 255 ; A2 : codes par défaut 521/5212 de `ModesPaiement` désormais regroupement/fictif.
- Comptes 419/409 et leurs écritures ; renumérotation des doublons passés ; achats reçus sans écriture ; montant de la dette annulée ; remboursement hors retour ; « Dépenses Totales » avec/sans achats retournés ; total nul d'un achat.
- Item 8 : libellés, cartes, listes de catégories, seuil +31 j, pied de page du poste, liste vide à l'export, « Générer un Document » (registre seulement).
- Item 9 : Q1 plan comptable modifiable au poste (recommandation NON), Q2 saisie d'écritures manuelles hors ligne (création seule, OUI recommandé), Q3 qui peut les saisir (`comptabilite-hub.html` dans aucune liste RBAC), Q4 historique des exercices antérieurs, Q5 comptes 409/419, Q7 libellés non classés.
- RBAC : visibilité des boutons par rôle ; contradictions inchangées (rôles 7/6/5/4, écrans 94/97/99). `feuille-pointage.html` : champ « Date * » du modal de pointage absent de l'écran (porter ou assumer).

### C. Vérifications jamais faites (valent pour tous les tickets récents)
Production (volumes, comptages `comptabilite:doublons-references` et `comptabilite:achats-sans-ecriture`, migrations non exécutées, le site en ligne n'a pas 15.28) ; MySQL réel (tous les tests serveur sont sqlite) ; tirage réel `sync_reel_test` (tag integration) ; `flutter build windows` / exécutable release ; rendu visuel et impression réelle des PDF ; performance (pull de 1 337 comptes, listes montées en entier au poste, sélecteurs de 1 337 options) ; fuseau (jour local du poste vs fuseau serveur) ; atomicité sur panne réelle.

### D. Qualité des garde-fous
- 268 couples (page, libellé) masqués par des exemptions globales (plafond `plafondManquesMasques` = 268, ne peut que baisser ; une compensation ajout/retrait ne se voit pas) ; cartes : libellés vérifiés seulement sur 3 pages ; fixtures du prototype non régénérables ; faux positifs de fidélité entre pages partageant un fichier Dart.
- Audits indépendants non faits : 15.22, F0.77, F0.78-bis, F0.79-bis, 15.26, F0.81 (partiellement couvert par l'audit de F0.82), 15.21 (14 mutations non rejouées), F0.84-bis/15.28-bis, T2. Mutations annoncées par les implémenteurs jamais rejouées par moi.
- Tests dépendant de chemins absolus (`C:/laragon/www/agrierp/...`, saut explicite sinon) ; un test de date du jour à la bascule de minuit.

### E. Reste à faire (ordre proposé)
T2 (valider et clore) → audit T2 → T3 balance (période, ouverture/mouvements/final, carte Écart) → T4 exports PDF des 4 pages → T5/T6 selon Q1–Q3 → T7 requalification des exemptions → phase B du plan (après cabinet) → item 10 (pages sous 60 %) → ticket Laravel sur les 7 tables à 500 → mise à jour de `CLAUDE.md` « Working state » (1 552+ tests, schéma v37, Laravel 1 087+) à la clôture de T2.

**DEP6–DEP9 (26/10/2026) — saisie-depenses.html : centre de coût obligatoire et dépense à crédit.** Modale du poste = Blade : « Centre de Coût * » (« -- Sélectionner -- », message sous le champ), « Règlement * » (Payée comptant / À crédit (dette fournisseur)) après « Fournisseur », ni mode ni compte à crédit, aide `data-aide-credit`, colonne Mode « À crédit », détail « Règlement : … ». Garde-fou : `depenses_a_credit_parite_test.dart` (libellés, ordre, messages, `libelleReglement` exécuté contre PHP). Drift v59. Écrans « Dettes Fournisseurs » inchangés.

