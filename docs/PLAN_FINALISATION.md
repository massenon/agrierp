# PLAN DE FINALISATION — LogiAgriERP

**Ferme École OLOUWACHEGOUN · état au 19/10/2026 · monorepo `massenon/agrierp`**

Ce plan ordonne ce qui reste à faire pour livrer un poste Windows **100 % autonome hors ligne**, fidèle à l'application web. Il s'appuie sur :
- les règles de [`DOCTRINE_PORTAGE.md`](DOCTRINE_PORTAGE.md) ;
- le journal des tickets `agrierp_laravel/README_SPRINT0.md` (tickets web jusqu'à 15.42, poste jusqu'à F0.95) ;
- `agrierp_flutter/AUDIT_FIDELISATION.md`.

> Convention : ✅ fait · 🔧 à faire · ❓ décision client requise avant de coder. Un ticket = une session, terminé seulement quand les tests sont verts des deux côtés et que le ticket est consigné dans `README_SPRINT0.md`.

**Passage de nettoyage du 10/11/2026.** Sur 25 lignes portant 🔧 ou ❓, 7 passent en ✅ (preuve citée sur chaque ligne) : A6 (`.fvmrc`), 3.F1 et 3.F2 (F0.96 / F0.97), 3.F6 (A2 à A4), B2 (synchronisation automatique, H13), B4 (absorbé par H2) et le doublon périmé de MP1-Q1. Restent **ouvertes dans le code** (aucune preuve de livraison trouvée au 10/11/2026) : 3.F5 (cascade Escargots / Reproducteurs en parité exécutée PHP ↔ Dart : aucun test dédié aux Escargots), 3.F7 (la mise-bas n'écrit pas `ne`), B3 (historique, filtre par table et export du journal : seule la relance d'un conflit existe), B5 (sauvegarde automatique quotidienne et avant migration, rotation 7 jours : seule la sauvegarde manuelle de 30 jours existe), B6 (continu), Sprint C (clôture de caisse, définition web à valider), D3 (aucun workflow GitHub Actions dans le dépôt), EX9 (archive figée de l'exercice, non construite), MP2 (voir ci-dessous). **Fermés depuis** : 3.F5 ✅ (10/11/2026), 3.F7 ✅ (11/11/2026), B3 ✅ (11/11/2026), D3 ✅ (11/11/2026), DEV2 ✅ (10/11/2026 — `devisRecents` dans `tableau_de_bord_repository.dart`, parité exécutée, mutations prouvées). **Dépendent du client** : essais réels sur Windows (D2, D5), certificat de signature (D4), mise en service simultanée avec l'exploitant (3.F4), décisions sans réponse (3.F3 : D5, D15, D2/D8/D9/D12 ; E3 : charte des en-têtes ; VW-Q1 à VW-Q4).

---

## Point de départ

| Surface | État |
|---|---|
| Web Laravel 12 + Livewire 3 | Sprints 1 à 15 livrés ; 62 routes nommées ; suite Feature verte. En production, la version déployée est celle du ticket 15.4. |
| Poste Flutter Windows | Tous les écrans de la barre latérale du prototype sont portés ; schéma Drift v38 ; environ 2 000 tests ; synchronisation pull/push opérationnelle avec écran **Synchronisation**. |
| Sprint 3 (Élevage) | Livré au ticket 3.14, puis repris par 14.x/15.x (effectif par catégorie, cascade). **Défaut de production corrigé le 17/10/2026, voir A1.** |

---

## Sprint A — Correctifs de production (immédiat)

### A1 ✅ « Effectif Total Vivant » faux après saisie d'une fiche journalière

- **Symptôme.** Après création d'une bande de reproduction puis saisie dans la fiche journalière, le KPI « Effectif Total Vivant » (Gestion des Bandes, Gestion Élevage, Tableau de bord) devenait faux.
- **Cause.** Les fiches web **Reproducteurs, Pondeuses, Escargots** écrivaient `current_quantity` = effectif du jour **édité**. Saisir ou corriger une fiche antérieure à la dernière ramenait donc la bande à ce jour-là, sans recalculer les jours suivants.
  - `EnregistrerSujets` partait de `current_quantity` pour une date passée et faisait `increment()` sans cascade.
  - Le poste (`FicheJournaliereRepository.enregistrer`) avait le même défaut.
  - Les fiches Porcs et Lapins passaient déjà par la cascade (ticket 15.42).
- **Correctif.** Toutes les écritures passent par la **cascade unique** : `RecordSaleOnFicheElevageAction::recalculerEnCascade()` côté web, `FicheJournaliereRepository.recalculerEnCascade()` côté poste. Les jours suivants sont recalculés et la bande prend l'effectif de la **dernière** fiche.
- **Tests.** `tests/Feature/EffectifTotalVivantCascadeTest.php` (4 tests) et un test dans `test/fiche_journaliere_test.dart`. Tous sont **rouges sans le correctif, verts avec** (épreuve de mutation faite).
- **Reste à vérifier.** ~~La fiche Escargots n'a pas de test dédié~~ ✅ livré le 10/11/2026 (A1-bis) : `agrierp_flutter/test/fiche_escargots_cascade_parite_php_test.dart` (voir 3.F5).

### A2 ✅ Bandes « issues d'une bande » comptées deux fois (construit par E1 ; reste à confirmer sur les données réelles)

> **État 09/11/2026 :** le transfert entre bandes (écran dédié, sortie de la source et entrée dans la cible le même jour, `lot_source_id`) et la correction des bandes déjà saisies ont été livrés (ticket E1, web puis poste). Reste, côté exploitant : comparer « Effectif Total Vivant » à un comptage physique (voir « Décisions proposées au client du 09/11/2026 »).

- **Constat probable** (à confirmer avec l'exploitant) :
  1. Les naissances sont saisies dans la fiche de la bande mère (`ne`), qui augmente son effectif.
  2. Une **nouvelle bande** est ensuite créée dans Gestion des Bandes pour la portée ou les sevrés, avec un effectif initial égal à ces mêmes animaux.
  3. Ils sont alors comptés **deux fois** dans « Effectif Total Vivant ».
- **Aucun mécanisme de transfert** entre bandes n'existe aujourd'hui, ni sur le web ni sur le poste.
- **Proposition.** Un mouvement « Transfert vers bande » : sortie de la bande source et entrée dans la bande cible, le même jour, dans une transaction, avec cascade des deux côtés. Il porte un `lot_source_id` sur la bande créée.
- **Décision client avant code :**
  - Le transfert est-il une colonne de la fiche (`transfert_sortie`) ou un écran dédié ?
  - Faut-il corriger les bandes déjà saisies (D6) ?

### A3 ✅ « Don » dans Enregistrer des Sujets — décision client du 17/10/2026

- Le « Don » est une **sortie** (animal donné, non comptabilisé) : la formule le soustrait, c'est voulu.
- Verrouillé par `CorrectionsElevage17OctobreTest::test_un_don_enregistre_est_une_sortie_soustraite_de_l_effectif`.

### A4 ✅ Transformation (abattage) = vente — décision client du 17/10/2026

- `TransformationForm` passe par `RecordSaleOnFicheElevageAction` : les sujets transformés sont une « Vente » de la fiche du jour, avec cascade.
- La sauvegarde de fiche suivante ne l'efface plus.

### A5 ✅ Autorisation des fiches journalières (vérifié le 09/11/2026 : les cinq méthodes `saveDay()` appellent `authorize('manage-elevage')`)

- Les cinq méthodes `saveDay()` des fiches web n'appellent pas `$this->authorize('manage-elevage')`, contrairement à la règle du projet (« première ligne de toute méthode mutante »).
- Ajouter l'appel et un test par fiche, après vérification que chaque rôle qui saisit des fiches a bien `manage-elevage`.

### A6 ✅ Compilation avec le Flutter stable actuel

- `sync_engine.dart` ne compilait pas avec Dart 3.13 (promotion de nullité d'une variable capturée), alors que `pubspec.yaml` autorise ce SDK.
- **Corrigé** par une copie finale locale, sans changement de règle.
- ✅ Figer la version de Flutter du poste de compilation (`.fvmrc` ou mention dans `build_windows.bat`) pour éviter la prochaine dérive. (livré, vérifié le 10/11/2026 : `agrierp_flutter/.fvmrc` versionné (Flutter 3.47.7), contrôle de version dans `build_windows.bat` lignes 129-144, section « Version de Flutter figée » de `agrierp_flutter/CLAUDE.md`, commit 5243603.)

### A7 ✅ Chemins Windows absolus dans les tests du poste

- ✅ Fait le 17/10/2026 : `test/chemins_depot.dart` et `outils/chemins.py` (variable d'environnement, puis monorepo, puis ancien chemin Windows). Suite du poste : 2 010 verts, 16 sautés (maquette absente, A8), 0 rouge.


- 19 fichiers de `agrierp_flutter/test` et `outils/` lisent `C:/laragon/www/agrierp/...` ou `C:/Projects/agrierp_laravel/prototype_html/...`.
- Dans le monorepo, ces chemins n'existent plus. Hors du poste du développeur, `export_comptabilite_test.dart` échoue (3 tests) et d'autres tests se mettent en saut (32 sautés).
- **Proposition :** un seul résolveur de chemins (`test/chemins_depot.dart`) qui pointe sur `../agrierp_laravel/`.

### A8 ✅ Clos le 09/11/2026 : la maquette HTML est retirée du projet (décision du client) ; les tests qui la lisaient sont supprimés ou ne comparent plus qu'au web

- Les `CLAUDE.md`, les outils de fixtures et plusieurs tests s'appuient sur `prototype_html/`, qui n'a pas été importé dans `massenon/agrierp`.
- Sans lui, la fidélité « prototype » n'est plus vérifiable que sur le poste du développeur.
- **Décision du client (09/11/2026) :** « OUI, FAIT, ENLEVER, ON N'A PLUS LA MAQUETTE HTML » : la vue Blade est la seule référence (Doctrine, article 0). Les tests qui ne comparaient qu'à la maquette sont supprimés, ceux qui comparaient aussi au web ne gardent que le web ; `dossierPrototype` et `AGRIERP_PROTOTYPE` sont retirés des tests ; les outils Python qui la lisent sont marqués obsolètes ; les fixtures `*_maquette.g.dart` restent un instantané figé, non régénérable.


### Décisions proposées au client (09/11/2026) — recommandations, **VALIDÉES le 09/11/2026 (« OUI à tout »)** : statut ci-dessous par ligne

Le client a demandé les propositions ; chacune est une RECOMMANDATION (rien n'est tranché à sa place) et se valide par « OUI ».

| Réf. | Question | Proposition recommandée | Pourquoi |
|---|---|---|---|
| A2 | Les bandes « issues d'une bande » sont-elles encore comptées deux fois ? | **Contrôle sur les vraies données** : comparer « Effectif Total Vivant » à un comptage physique sur trois bandes ayant des portées, puis clore. Le code est livré (E1). | Le défaut ne se voit que sur les données de la ferme. |
| DEV-Q2 | Lignes de devis structurées (produits du catalogue, remise par ligne) | **Non pour l'instant** : description libre comme le web. À rouvrir si les prestations deviennent fréquentes. | Un devis de prestation n'est pas un panier de caisse ; le structurer double la logique de la caisse. |
| DEV-Q3 | Impression d'un devis « document client » | **Oui, web d'abord** : A4 avec en-tête de la ferme, mentions légales, durée de validité, bon pour accord ; puis poste par le même générateur de PDF (`ExportOfficiel`) ; numéro attribué par le serveur. | Un devis se remet au client ; l'état « Exporter » n'est pas présentable. |
| CAISSE-1 | Appareil personnel ou d'entreprise : le code PIN suffit-il ? | **Appareil d'entreprise recommandé, PIN suffisant** (4 à 6 chiffres, chiffrement AES-GCM dérivé du PIN, limiteur d'essais). **Appareil personnel toléré** avec un PIN de 6 chiffres et l'effacement des données hors ligne à la déconnexion. | Le PIN protège déjà la clé de chiffrement ; l'appareil personnel est le risque de perte ou de prêt. |
| CAISSE-2 | Reçu provisoire à imprimer ? | **Oui** : « Reçu provisoire » sans numéro de facture légal, avec l'identifiant court du poste (8 premiers caractères de l'UUID de la vente) et la mention « facture n° attribué à la synchronisation ». | Le client repart avec une preuve ; le numéro légal reste attribué par le serveur. |
| CAISSE-3 | Essai sur les vrais appareils | **Un essai d'une journée sur trois appareils** (Android Chrome, iPhone Safari, un PC) : coupure du réseau, cinq ventes, retour du réseau, comparaison avec le serveur (ventes, stock, caisse). Résultats consignés dans `docs/logialvia/46_…`. | Safari et les appareils réels sont les deux zones jamais vérifiées. |
| COMPTA-1 | Droit d'export des ventes (`export-ventes`) pour le comptable | ✅ **LIVRÉ (09/11/2026, DV-34)** — **Oui** : l'accorder au comptable (il lit déjà ventes, clients, créances et avances ; l'export est une lecture). Seeder, migration de données, matrice du poste et test de matrice. | Cohérent avec CONF-4 / CONF-5 ; le poste imprime déjà ces états en local. |

### A9 ✅ Empreinte du plan comptable SYSCOHADA

- Le CSV du client (`database/data/plan-comptable-syscohada-revise.csv`) est en CRLF. Le premier commit l'avait converti en LF, ce qui faisait échouer `ImportPlanSyscohadaTest`.
- Rétabli octet pour octet et protégé par `-text` dans `.gitattributes`.

---

### A10 ✅ Corrections du 17/10/2026 (web, `agrierp_laravel`)

| Point | Correction |
|---|---|
| Glossaire lapins | Reproducteur / Jeune / Sous-mères partout : morts, dons, départ, rationnement, barème (migration `2026_10_17_000001`), « Stade Initial » de la modale Nouvelle bande. L'ancien « Lapin de Chair » (60 g) devient « Jeune » ; l'ancien « Jeune » / « Lapereau » (30 g) devient « Sous-mères ». |
| Passage de stade | Évalué et **gardé**, renommé « Sevrage du jour (Sous-mères → Jeune) ». C'est le seul mouvement qui fait passer les nés (comptés en Sous-mères) dans la catégorie vendue (Jeune). Sans lui, les effectifs par catégorie, donc la provende, dérivent. |
| Rationnement automatique | Le départ par catégorie est **déduit du stade de la bande** (`departDepuisStade`) : provende servie et autonomie calculées sans saisie (Lapins, Porcs). |
| Autonomie alimentaire | Composant unique `x-autonomie-alimentaire`. **Rouge** en rupture, sous 3 jours ou sans produit de provende. N'empêche jamais l'enregistrement. |
| Poids et traitements | « Poids Général (g) » = total pesé (et non la moyenne). « Poids Moyen Constaté » automatique et arrondi (Lapins, Escargots, Reproducteurs). La colonne « Traitements & Prophylaxie » lit le registre vétérinaire. La prophylaxie du jour est raccordée à Pondeuses et Reproducteurs. |
| Archivage | Scope `LivestockLot::vivantes()`. Les KPI élevage, la paie (absences), les rôles (utilisateurs), les acomptes, le coût vétérinaire et le tableau de bord excluent les données archivées. |
| Tiroir Gestion des Bandes | Autonomie alimentaire et suivi sanitaire réels : délai d'attente, infirmerie, mortalité 7 jours, derniers soins. |
| Paramètres | Administrateur « M. Olouchègoun », `contact@fermeolouwachegoun.com`. Le poste pointe par défaut sur `https://agrierp.fermeolouwachegoun.com`. |
| Seeders | Les bandes de démonstration lapins et porcs suivent la chaîne par catégorie (départ déduit, mouvements ventilés, sevrage). Recalcul indépendant : 0 anomalie, « Effectif Total Vivant » = 263 à l'écran comme en base. |

### A11 ✅ Fiches Pondeuses et Escargots à plusieurs bandes

- ✅ Livré au ticket 15.48 (sélecteur de bande web, 17/10/2026).

- Le tableau mensuel réunit **toutes** les bandes, indexées par date : deux bandes saisies le même jour s'écrasent à l'écran.
- `saveDay()` enregistre toujours sur la **première** bande.
- **Proposition :** sélecteur de bande, comme les fiches Lapins et Porcs (ticket 15.41).

### A12 ✅ Poste : glossaire du 17/10/2026 à porter AVANT de déployer le serveur

- ✅ Livré aux tickets F0.96 / F0.97 (17/10/2026).

- La migration `2026_10_17_000001` renomme le barème lapins (« Jeune » = 60 g, « Sous-mères » = 30 g).
- Le poste (`categorie_ration_lapin.dart`) lit encore « Jeune » comme la catégorie à 30 g.
- Les rations d'une bande en engraissement restent justes (repli à 60 g), mais les libellés et `cleDuStade()` doivent suivre. Cela touche plus de 25 tests du poste.
- **À livrer avec F0.96**, en mise en service simultanée (3.F4).

### A13 ✅ Fiches hors lapins : sections présentes d'un seul côté (audit F0.99, 17/10/2026)

Décision client du 17/10/2026 : « les sections doivent exister des deux côtés ». Livré aux tickets 15.56 et 15.57.

| Fiche | Section | Avant | Après |
| --- | --- | --- | --- |
| Pondeuses, Escargots, Reproducteurs | Dons par catégorie (le don sort du stock) | poste seul | web et poste (15.56) |
| Pondeuses | Rationnement par stade, Pesée | poste seul | web et poste, règle commune `RationVolaille` |
| Reproducteurs | Rationnement par stade | poste seul (0 g sans ligne au barème) | web et poste, « — » et la raison sans ligne |
| Porcs | Effectif de départ par catégorie (modifiable, puis verrouillé) | web seul | web et poste |
| Porcs | Verrats / Truies Gestantes / Porcelets / Engraissement | web seul | web et poste |
| Escargots | Naissains / Engraissement / Bordés | web seul | web et poste |
| Tous | Colonnes par catégorie du tableau mensuel | « — » au poste | valeurs synchronisées des deux côtés |
| Tous | Casse des sous-en-têtes du tableau mensuel | MAJUSCULES au poste | casse mixte, comme le web |

- **Reste, signalé :** le web écrit « Porc marchand » / « Porc Marchand » dans `fiche-porcs.blade.php` (invisible, CSS `uppercase`) ; `CategorieRationPorc::LIBELLES` n'est jamais lu.

## Sprint 3 — Finalisation Élevage (web ↔ poste)

| # | Ticket | Statut |
|---|---|---|
| 3.F1 | **F0.96** — fiche Lapins du poste : saisie ventilée (morts et dons par catégorie, passage sevré → jeune), miroir du ticket 15.41 | ✅ Était bloquant : tant qu'il n'était pas livré, une fiche du poste avec morts ou dons sur une bande « à départ » était **refusée** (D7). (livré, vérifié le 10/11/2026 : section « Tickets F0.96 / F0.97 » de `agrierp_laravel/README_SPRINT0.md`, A12 de ce plan, tests `ventilation_categories_test.dart` et `fiche_lapins_glossaire_test.dart`.) |
| 3.F2 | **F0.97** — fiche Porcs du poste : même chose, miroir du ticket 15.42 | ✅ Était bloquant (même motif). (livré, vérifié le 10/11/2026 : mêmes preuves que 3.F1, `fiche_porcs_test.dart` et `fiches_ventilation_sync_test.dart` présents, A12 de ce plan.) |
| 3.F3 | D6 tranchée le 17/10/2026 (bandes déjà saisies : corrigées par la chaîne, départ déduit du stade). Restent D5 (qui déverrouille un départ erroné), D15 (« Porc Marchand » / « Jeune porc »), confirmation de D2/D8/D9/D12 | ❓ |
| 3.F4 | Mise en service **simultanée** du serveur (15.39–15.42) et du poste (F0.95–F0.97) | 🔧 À planifier avec l'exploitant (10/11/2026 : dépend du client ; le code des deux côtés est livré, F0.96 / F0.97 ; la date de mise en service reste à fixer) |
| 3.F5 | Tests de cascade pour Escargots et Reproducteurs en parité exécutée PHP ↔ Dart (`test/php_laravel.dart`) | ✅ (livré le 10/11/2026 : Escargots, `test/fiche_escargots_cascade_parite_php_test.dart`, 16 suites, 281 saisies rejouées dans le vrai `FicheEscargots::saveDay` et le dépôt du poste, jours dans le désordre, ventes de la caisse, exercice clos ; mutations prouvées (cascade retirée, formule d'effectif faussée). Reproducteurs : déjà couverts par VOL-1, `volailles_effectif_test.dart`. Aucun écart web ↔ poste trouvé.) |
| 3.F6 | A2, A3, A4 ci-dessus (transferts, dons reçus, transformation) | ✅ (livré, vérifié le 10/11/2026 : A2, A3 et A4 portent ✅ dans ce plan ; tests du poste `transferts_bandes_test.dart`, `transformation_poste_test.dart`, `transformation_parite_php_test.dart` ; ticket EL-1 dans `agrierp_flutter/CLAUDE.md` ; dons par catégorie web et poste, A13.) |
| 3.F7 | Suivi de reproduction : la mise-bas (`saveMiseBas`) n'alimente aucune fiche. Les nés vivants restent à saisir à la main dans la fiche du jour. Décider si la mise-bas écrit `ne` dans la fiche de la bande. | ✅ (11/11/2026, décision client option A : `saveMiseBas` + `pushReproductionEvents` écrivent `ne` dans `livestock_daily_entries`, `SuiviReproductionMiseBasFicheTest` 9/9) |

---

## Sprint B — Offline-first robuste et synchronisation

| # | Ticket | Statut |
|---|---|---|
| B1 | Écran **Synchronisation** (`lib/features/sync/synchronisation_screen.dart`) | ✅ existe : en attente, conflits avec motif, dernier état, bouton « Synchroniser ». |
| B2 | Synchronisation **déclenchée automatiquement** : au retour du réseau, à intervalle (15 min, configurable dans Paramètres du poste) et à la fermeture de l'application. Jamais bloquante ; hors ligne = état normal, pas une erreur rouge. | ✅ (livré, vérifié le 10/11/2026 : ticket H13 de ce plan, `lib/core/sync/synchronisation_automatique.dart` (retour du réseau, intervalle réglable dans Paramètres, fermeture, réessais) ; `synchronisation_automatique_test.dart` ; intervalle par défaut 5 min depuis S-T3, et non 15.) |
| B3 | Écran Synchronisation : historique des dernières tentatives (date, poussés / tirés / refusés), filtre des conflits par table, relance d'un conflit après correction, export du journal pour le support. | ✅ B3 (11/11/2026) : table `sync_history` (v87, plafonnée à 30 lignes), enregistrement après chaque appel à `synchroniser()` (hors ligne compris), bloc « Dernières tentatives » + bouton « Exporter le journal » dans `synchronisation_screen.dart`, filtre par table sur le bloc des refus (chips filtrantes, visibles si plusieurs tables). Tests : `historique_synchronisation_test.dart` (6/6). |
| B4 | Indicateur permanent dans `BarreSuperieure` : nombre d'enregistrements en attente et âge de la dernière synchronisation réussie. | ✅ absorbé par **H2** (livré, vérifié le 10/11/2026 : ligne H2 de ce plan, ✅ 19/10/2026 ; `synchronisation_barre_test.dart` présent) |
| B5 | Sauvegarde locale de la base Drift (copie datée dans `Documents\LogiAgriERP\sauvegardes`, rotation 7 jours) avant toute migration de schéma et chaque jour. | ✅ |
| B6 | Couches DDD : migrer progressivement les repositories qui renvoient des lignes Drift vers des entités de domaine (Doctrine §1.3), écran par écran et jamais en lot. | 🔧 continu |

---

## Sprint C — Clôture de caisse ❓

> ⚠️ **Fonctionnalité absente du prototype ET de l'application web.** Aucune « clôture de caisse » n'existe aujourd'hui. Par l'article 0 de la doctrine, elle doit être **définie et construite d'abord sur le web**, puis portée. À valider par le client avant tout code.

**Proposition à valider :**

| # | Ticket |
|---|---|
| C1 | Web : écran « Clôture de caisse » (caissier). Ventes du jour par mode de paiement, fond de caisse, montant compté et écart. L'écart passe par une Action dédiée qui génère l'écriture SYSCOHADA (perte ou gain de caisse) via `AccountingEntryService::record()`. |
| C2 | API : table `cash_closures` (UUID), poussée par le poste et **jamais fusionnée** (comme les ventes). |
| C3 | Poste : écran porté à l'identique. La validation de la clôture **déclenche une synchronisation** (B2). Hors ligne, la clôture reste `pending` et l'écran le dit. Une clôture validée verrouille les ventes du jour sur le poste. |
| C4 | Tests : écriture d'écart équilibrée au centime ; synchronisation déclenchée ; clôture hors ligne conservée puis envoyée. |

---

## Sprint D — Build et distribution Windows

| # | Ticket | Statut |
|---|---|---|
| D1 | `agrierp_flutter/build_windows.bat` : enchaîne dépendances, génération Drift, analyse, tests, `flutter build windows --release`, copie du runtime VC++, puis installateur Inno Setup (`installer/agrierp.iss`) → `installer\Output\LogiAgriERP-Setup-<version>.exe` | ✅ écrit le 17/10/2026, **pas encore exécuté sur une machine Windows** |
| D2 | Première exécution réelle sur le poste de compilation ; vérifier l'installation sur un Windows 10 vierge, sans redistribuable VC++ | 🔧 (10/11/2026 : dépend du client, il faut une machine Windows ; aucune trace d'exécution réelle trouvée) |
| D3 | CI GitHub Actions `windows-latest` : analyse, tests, build, installateur publié en artefact à chaque tag `v*` | ✅ (11/11/2026, `.github/workflows/flutter-ci.yml` + `flutter-release.yml`) |
| D4 | Signature du code de l'exécutable (certificat éditeur), pour éviter l'alerte SmartScreen | ❓ achat du certificat (10/11/2026 : dépend du client ; aucune étape de signature dans `installer/agrierp.iss` ni `build_windows.bat`) |
| D5 | Mise à jour du poste : l'installateur réutilise le même `AppId` ; la base locale (profil utilisateur) n'est jamais touchée par une mise à jour ou une désinstallation | ✅ prévu dans `agrierp.iss`, 🔧 à vérifier en réel (10/11/2026 : dépend du client, essai sur Windows ; `AppId` fixe présent ligne 46 de `agrierp.iss`. ⚠️ Depuis DES-1 (27/10/2026) la **désinstallation** supprime la base locale après confirmation : seule la mise à jour la conserve) |

**Cloner et compiler** (sur le poste Windows de compilation) :

```bat
git clone https://github.com/massenon/agrierp.git
cd agrierp\agrierp_flutter
build_windows.bat
```

Prérequis : Flutter stable, Visual Studio 2022 (charge « Développement Desktop en C++ »), Inno Setup 6.

---

## Sprint E — Design system unifié

| # | Ticket |
|---|---|
| E1 | `BaseButton` unique (taille, padding, rayon), mesuré sur la vue web. Migration de tous les boutons d'action, puis garde-fou dans `conformite_portage_test.dart`. |
| E2 | Pagination standard (10 ou 25 lignes). ⚠️ Absente du web : la construire d'abord en composant Blade, puis la porter. |
| E3 | ❓ Charte des en-têtes de tableau. La consigne mentionne un fond `#0f172a` que ni le web ni le prototype n'utilisent : décider sur le web d'abord (voir Doctrine §2). |
| E4 | Contrôle des libellés de cartes KPI sur toutes les pages (faiblesse connue n° 2 du `CLAUDE.md` Flutter). |

---

## Sprint F — Localisation (zéro chaîne en dur)

| # | Ticket |
|---|---|
| F1 | Web : créer `lang/fr/*.php` et migrer les libellés Blade **module par module**, en commençant par Élevage. |
| F2 | Poste : fichiers ARB (`lib/l10n/app_fr.arb`) générés depuis `lang/fr` par un script, pour garantir la parité des clés. |
| F3 | Adapter `fidelite_libelles_test.dart` pour comparer les **clés** et non plus les littéraux. |

Les deux côtés migrent **ensemble**, module par module, sinon la parité est perdue.

---

## Sprint H — Fidélité des écrans clés (audit du 19/10/2026)

Source : [`AUDIT_FIDELITE_ECRANS.md`](AUDIT_FIDELITE_ECRANS.md). Les directives d'ergonomie du client servent de liste de contrôle ; toutes les valeurs viennent du Blade. Un ticket = un écran, garde-fou compris. Le poste s'aligne sur le **Blade**, pas sur la maquette : chaque ticket remplace les comparaisons à la maquette qui ne tiennent plus par une comparaison au Blade.

| # | Ticket | Statut |
|---|---|---|
| H1 | **Châssis du poste** : bouton flottant et panneau « Accès Rapide » (13 entrées, 3 groupes, valeurs de `app.blade.php:219-247`) ; barre latérale qui défile ; valeurs de la barre latérale (288 px, dégradé, « ERP » jaune, sous-titre, séparateur, entrée active jaune, icône 20 / libellé 13) ; menu du compte complet (Paramètres, séparateur, Déconnexion) ; badge de la cloche « 9+ » ; composant toast unique `ToastAgri` (haut droite, 3,5 s, succès / erreur / avertissement) | ✅ 19/10/2026 (Accès Rapide, barre latérale, toasts, menu du compte, titre du web, ruban, recherche globale H1b, icônes Material Symbols Outlined via `SymbolesAgri`) |
| H2 | **Bouton « Synchroniser » dans la barre supérieure + modale, poste** (PRD [`synchronisation-barre-superieure`](prd/synchronisation-barre-superieure.md), absorbe B4) ; `pendingCount()` aligné sur les tables réellement envoyées (8 tables oubliées) ; « dernière synchronisation réussie » | ✅ 19/10/2026 |
| H3 | **Même bouton + modale « État de synchronisation des postes », web** (admin) ; table serveur `journal_synchronisation` (tirages et envois, par poste, compteurs) | ✅ 19/10/2026 |
| H4 | **Gestion Élevage** du poste : repository, 4 KPI, intertitres « Registres par Espèce » et « Accès Rapides — Élevage & Soins », 3 accès rapides manquants, libellés et icônes des cartes, grille, Escargots grisé (et non masqué) | ✅ 19/10/2026 |
| H5 | **Tableau de bord** du poste : Dettes (`payables`), Gestantes (`livestock_reproduction_events`), Résultat Net et Dépenses sur les **achats** comme le web, sous-textes « Mois précédent », alerte « Créance en retard », onglets Achat et Factures, lignes Vente, Activités du jour (`audit_logs`), filtre `status = 'actif'`, mentions périmées retirées | ✅ 19/10/2026 (+ défauts du web corrigés : ventes annulées, retard négatif) |
| H6 | **Dashboard Élevage** du poste : formule du GMQ cumulé et KPI mortalité 7 j en parité exécutée PHP ↔ Dart, filtre `status = 'actif'` et espèces `enabled()`, onglets GMQ et Prévision ramenés aux tableaux du Blade, résumé GMQ par bande, rappels VMS du web | ✅ 19/10/2026 (+ défaut du web corrigé : fenêtre « 7j » à 6 jours) |
| H7 | **Suivi Reproduction** du poste : colonnes et cellules du Blade, statuts, rappel du cycle à 4 étapes, actions Palpation / Mise bas / Clôture (écritures `livestock_reproduction_events` déjà poussées), lien « Saisir le Couvoir du Jour → », modale (mâle facultatif) | ✅ 19/10/2026 (écran, serveur, actions de cycle envoyées par le moteur) |
| H8 | **Soins et vaccins** du poste : registre (6 colonnes, « CODE (Espèce) », archivage), modale Nouveau Soin, messages ; puis infirmerie et calendrier planifié, qui demandent `infirmary_records` et `veterinary_calendar_events` au poste (tables synchronisables, schéma partagé) | ✅ 19/10/2026 |
| H9 | **Paramètres Élevage** du poste : libellés, formats, tris ; bloc « Rappel des soins planifiés » (valeur servie au tirage) | ✅ 19/10/2026 |
| H10 | Garde-fou : un test par écran H4–H9 qui lit les libellés et colonnes **dans le Blade** (et non plus dans la maquette) et les cherche dans l'écran Flutter | ✅ 19/10/2026 (`gestion_elevage_blade_test`, `tableau_de_bord_blade_test`, `dashboard_elevage_blade_test`, `suivi_reproduction_blade_test`, `soins_infirmerie_calendrier_test`, `parametres_elevage_blade_test`) |
| H8b | **D-H8** : infirmerie (`infirmary_records`) et calendrier planifié (`veterinary_calendar_events`) saisis au poste : tables Drift (UUID), tirage et envoi (`manage-elevage`), onglet Suivi Sanitaire complet et « Planifier une Intervention » | ✅ 19/10/2026 (serveur et poste, Drift v41) |
| H9b | **D-H9** : Paramètres Élevage modifiables au poste comme au web — rations, prophylaxie, provendes, numérotation, rappel des soins : envoi accepté pour `manage-elevage`, dernier écrivain gagne, archivage logique | ✅ 19/10/2026 (serveur et poste, Drift v42) |
| H11 | **D-H-maquette** : construire au web les ajouts du poste (courbe et cartes GMQ, filtre d'espèce, horizons de prévision et cartes, filtres et recherche du registre des soins, bandeaux de cycle Volailles / Escargots, « Bandes suivies »…) | ✅ 19/10/2026 (Tableau de bord, Dashboard Élevage, Suivi Reproduction, Soins ; « Importer » / « Exporter PDF » des soins non construits : inertes au poste) |
| H13 | **D-SYNC-2/3** (B2) : synchronisation automatique du poste (retour du réseau, toutes les 15 min, fermeture), réessais 30 s / 2 min / 5 min / 15 min / 1 h pour les échecs réseau | ✅ 19/10/2026 (intervalle réglable dans Paramètres du poste : 5, 15, 30 ou 60 min ; fermeture bornée à 15 s ; une seule tentative à la fois) |
| H13b | **D-SYNC-2** : envoi par lots de 50. ⚠️ Le serveur COUPLE des tables dans un même envoi : une vente et la fiche (bande, jour) qu'elle touche (15.30 : sinon la vente est comptée deux fois), les transferts après leurs fiches (15.46), avances et imputations (15.19). Les lots suivent l'ordre de traitement du serveur et ne séparent jamais un groupe couplé | ✅ 19/10/2026 (fiches, transferts et ventes par journées entières au rang des ventes ; un envoi de 50 lignes au plus part tel quel) |
| H14 | **D-SYNC-4** : vente reçue du poste qui rend un stock négatif → acceptée et signalée (notification à l'administrateur, compteur dans le journal) | ✅ 19/10/2026 |
| SW-1 | **Correction du client du 21/10/2026 — le web fait AUSSI revenir les données vers les postes** (PRD [`synchronisation-barre-superieure`](prd/synchronisation-barre-superieure.md) §11) : audit du tirage (aucun trou de requête ; trous de conception : curseur ignoré du serveur, pas de tirage forcé, demande S-T6 expirant en 1 h) ; table serveur `poste_synchronisations` (curseur et drapeau par poste) ; modale web « Modifications du site depuis son dernier tirage : N » + « Renvoyer vers ce poste / tous les postes » ; le poste honore le drapeau (tirage complet puis acquittement, sans migration Drift) | ✅ 21/10/2026 |

### Décisions du client du 19/10/2026 (soir) — « uniformiser web et poste, pas de divergence »

| Réf. | Décision | Ticket |
|---|---|---|
| D-U1 | « Morts S/Mère » (Suivi Reproduction) = `nes_morts` : **confirmé** | — |
| D-U2 | Objectifs de GMQ : **une seule source, la table `growth_standards`**, au web et au poste (plus de constantes) | U2 |
| D-U3 | Archivage d'un soin : **possible au poste comme au web** (`is_active`, envoi accepté) | U3 |
| D-U4 | Top 5 des produits et ventes porcines : **mêmes chiffres au poste qu'au web** (les lignes de vente et d'achat descendent au poste) | U4 |
| D-U5 | **Tous les messages d'erreur en français**, au web (validation, authentification) et au poste | U5 |
| D-U6 | Infirmerie : **le poste accepte une date future, comme le web** (le serveur l'accepte aussi à l'envoi) | U6 |
| D-U7 | Prix moyen de la provende (bilan) : **même règle au web et au poste** — types ACTIFS seulement (un type archivé n'est plus acheté) | U7 |
| D-U8 | Mobile money dans la répartition Caisse / Banque : **oui, troisième ligne au web et au poste** | ✅ 19/10/2026 |

### Décision du client du 19/10/2026 (nuit) — méthode TATACORA

**D-SYNC-1 confirmée** : le protocole actuel (`/api/sync/pull` + `/api/sync/push`, état de synchronisation porté par chaque ligne) est gardé ; les principes de la méthode TATACORA sont transposés par les tickets S-T1 à S-T9 (`docs/COMPARAISON_METHODE_TATACORA.md`).

| # | Ticket | Statut |
|---|---|---|
| S-T1 | Renvoi d'une 5xx comme un échec réseau ; 401/403 : la synchronisation automatique s'arrête jusqu'à la reconnexion ; 422 / 413 : lot coupé en deux (sans jamais couper une journée couplée) | ✅ 19/10/2026 (+ 429 réessayée) |
| S-T2 | `device_id` envoyé comparé au nom du jeton Sanctum (refus 403 sinon) | ✅ 19/10/2026 |
| S-T3 | Déclencheurs : au démarrage de la session, après un geste important, intervalle par défaut 5 min | ✅ 19/10/2026 (vente, fiche, soin ; agrégation 5 s) |
| S-T4 | Tirage paginé (curseur `updated_at` + `id`) et limité aux tables que le rôle lit | ✅ 19/10/2026 (pages de 1 000 lignes, pièce jamais séparée de ses lignes, curseur avancé après la dernière page ; `PERMISSIONS_DE_TIRAGE` croisée avec les écrans du poste ; poste ancien : réponse complète inchangée) |
| S-T5 | Fusion par clé naturelle des référentiels saisis au poste (clients, fournisseurs, produits) + table de correspondances | ✅ 19/10/2026 (fusion prudente : client et fournisseur sur nom + téléphone ≥ 8 chiffres, produit sur nom + catégorie + unité + filière ; références traduites au serveur en un point unique) |
| S-T6 | Bouton « Synchroniser les postes » au web (demande lue par les postes toutes les 30 s) ; contrôle de cohérence (nombre et total par table et par jour) au web et au poste | ✅ 19/10/2026 (demande expirant après 60 min ; dépenses hors du contrôle : elles ne descendent pas au poste) |
| S-T7 | Garde-fou « un seul écrivain par table » au poste ; `roles` daté quand ses droits changent | ✅ 19/10/2026 (3 écritures parasites corrigées ; exception documentée : `products.stock_qty`) |
| S-T8 | Installateur : refus de la version démo, adresses par environnement | ✅ 19/10/2026 (`.bat` et `.iss` non exécutés ici ; adresse de recette à confirmer) |
| S-T9 | Essai à plusieurs postes contre le vrai serveur, avec coupures au hasard | ✅ 19/10/2026 (MariaDB 10.11, 5 postes, 8 graines vertes ; 5 défauts réels trouvés et corrigés) |
| S-T10 | Inventaire du poste envoyé en QUANTITÉ COMPTÉE datée, l'écart calculé par le serveur sur son grand livre à cet instant (aujourd'hui : écart calculé sur le stock LOCAL, une vente faite ailleurs et pas encore descendue est comptée deux fois) | ✅ 19/10/2026 (Drift v46 ; écart = compté − stock du serveur à l'instant du comptage) |
| S-T11 | Dates servies au poste lues en heure du Bénin quel que soit le réglage de Windows (aujourd'hui : décalage d'un jour sur un poste mal réglé — écarts de cohérence vus sur soins et avances) | ✅ 19/10/2026 (`HeureBenin`, point unique ; essai vert dans 4 fuseaux) |
| S-T12 | Essai à cinq postes étendu : retours et remboursements fournisseurs, imputations, produits créés au poste, dépenses, session refusée (401/403), demande de synchronisation du web, plusieurs jours hors ligne | ✅ 19/10/2026 (6 graines × 2 fuseaux vertes ; 7 défauts corrigés) |
| S-T13 | Caisse du web rejouée sur un interblocage MariaDB comme l'envoi des postes (exige de sortir l'appel MeCeF de la transaction, sinon la facture partirait deux fois) | ✅ 19/10/2026 (`TransactionRejouable`, `FacturationMecefService` ; graine 314 : interblocage réel rejoué) |
| R-1 | « Réinitialisation des données » au poste comme au web (en ligne seulement, saisies en attente signalées, purge locale immédiate) | ✅ 19/10/2026 (mêmes verrous que le web : droit, mode démonstration, mot `REINITIALISER`) |
| DEP-1 | Guide `GUIDE_DEPLOIEMENT.md` (cloner, tester, cPanel, cron) | ✅ 19/10/2026 (⚠️ second cron `queue:work` indispensable : tâches du matin mises en file) |

### Décision du client du 19/10/2026 (nuit) — configurations dans Paramètres, au poste et au web

| Réf. | Décision |
|---|---|
| D-CFG-1 | Web : le mot de passe SMTP saisi dans Paramètres est **chiffré en base** (déjà le cas : `company_settings.smtp_password_encrypted`, cast `encrypted`, jamais servi aux postes — 14.84) |
| D-CFG-2 | Poste : onglet **« Email (SMTP) »** dans Paramètres ; mot de passe dans le coffre du système (`flutter_secure_storage`, l'équivalent sûr du `poste.json` de TATACORA), **jamais en base Drift ni synchronisé** |
| D-CFG-3 | Recette = **le serveur de la ferme** (`https://agrierp.fermeolouwachegoun.com`) ; les données d'essai sont vidées ensuite par « Réinitialisation des données » (Paramètres, 15.50) — vérifiée le 19/10 sur le jeu de démonstration : 7 390 lignes d'activité → 0, référentiels gardés, stocks et trésorerie à 0, marque posée |
| D-CFG-4 | En-têtes du tableau des stocks au poste **accentués comme le Blade** (« DÉSIGNATION », « CATÉGORIE ») |
| D-R1 | Réinitialisation lancée au poste dont la réponse se perd : **accepté** — le poste purge au tirage suivant (règle 15.50) et la perte des saisies non envoyées est annoncée par l'avertissement de synchronisation |
| D-MECEF-1 | ⏸ laissé de côté à la demande du client (21/10/2026) — aucun code touché. *Question d'origine, restée ouverte :* une facture acceptée par le dispositif MeCeF dont la réponse se perd serait déclarée deux fois à la retransmission — seule la future passerelle réelle peut l'empêcher (identifiant de la vente comme clé d'idempotence, ou interrogation avant retransmission). Et : faut-il un bouton de retransmission pour une vente restée « En attente » (aujourd'hui seulement pour « Erreur MeCeF ») ? |

| # | Ticket | Statut |
|---|---|---|
| CFG-1 | Web : onglets dédiés de Paramètres — « Email (SMTP) » (mot de passe chiffré, jamais réaffiché, e-mail de test) et « Postes & Appairage » (postes appairés = jetons nommés, utilisateur, dernier contact, état H3, révoquer un poste) | ✅ 19/10/2026 (saisie SMTP qui existait en double regroupée ; `smtp_from_address`) |
| CFG-2 | Poste : onglets « Email (SMTP) » (hôte, port, sécurité, utilisateur en réglages locaux ; mot de passe au coffre ; e-mail de test) et « Appairage » (adresse du serveur et environnement, identifiant du poste, compte connecté, test de connexion, réappairer) dans Paramètres, à la place de l'écran isolé « Paramètres du poste » | ✅ 19/10/2026 (hub à 8 onglets ; `mailer` ; mot de passe jamais en base, vérifié cellule par cellule) |

| # | Ticket | Statut |
|---|---|---|
| U2 | `growth_standards` tirée au poste (table Drift, absorbeur strict) ; Dashboard Élevage web et poste lisent les objectifs dans cette table, même agrégation par espèce | ✅ 19/10/2026 (barème du stade de chaque bande moyennée, enveloppe min/max ; aucun barème → « — ») |
| U3 | `veterinary_records.is_active` au poste ; archivage envoyé et accepté par le serveur (`manage-elevage`) ; bouton d'archivage au registre du poste comme au web | ✅ 19/10/2026 (Drift v43 ; tous les calculs du poste et deux requêtes du web limités aux soins actifs) |
| U4 | `sale_lines` et `purchase_lines` des ventes et achats tirés au poste ; Top 5, marge et ventes porcines calculés sur toutes les ventes, comme au web | ✅ 19/10/2026 (tirage au curseur, absorbeur strict, resynchronisation unique `lignes_resync_u4`, marge = formule PMP du web, parité exécutée) |
| U8 | Écarts restants relevés par U4 : valorisation de Gestion des stocks au poste (PMP), colonne Catégorie des achats (catégorie produit), carte « Écarts / Retours » (`purchase_returns` tirés), filtre par jour du Tableau 3 de la ponte, ventes refusées hors des KPI | ✅ 19/10/2026 (reste : « Rotation du Stock » et écarts d'inventaire d'autres postes, faute de `stock_movements` au poste) |
| U9 | `stock_movements` tiré au poste (Drift v44, lecture seule) : « Rotation du Stock », « Écarts d'Inventaire » de toute la ferme, Tableau 3 de la ponte identique au web (plateaux, ferme, colonne Lot), tri et pastilles du tableau des stocks du Blade | ✅ 19/10/2026 (Drift v44, parités exécutées : Gestion des stocks entière et Tableau 3 rendu par le Blade) |
| U10 | Derniers écarts relevés par U9 : Gestion des stocks (Exporter PDF, « Ajouter Stock » et sa modale, « Configurer les Seuils d'Alerte », icône Modifier, écart « 0 » de l'onglet Ajustement, icône sablier) ; Rapport élevage (filtre Lot / Souche, libellés des pilules, Tableaux 1 et 2 et KPI sur le Blade) ; Fiche Pondeuses (SRH, TS, OS, Stock Final depuis le grand livre) | ✅ 19/10/2026 (Drift v45 ; ajout de stock rejoué au serveur comme `submitAjouterStock`) |
| U11 | Écarts mineurs relevés par U10 : onglet Ajustement (motif obligatoire au poste seulement, écart nul, toasts, présélection, aide), en-têtes accentués de Gestion des stocks (arbitrage ouvert), nom du PDF, bouton « Filtrer la Période » du Rapport élevage, ordre de deux fiches du même jour, Fiche Pondeuses (tous les jours du mois, « Traitements & Rappels », mise en page du Blade) | ✅ 19/10/2026 |
| U12 | Derniers écrans encore sur la maquette : les 5 autres onglets du hub Rapports (en-tête, boutons réservés à `export-rapports`), fiches Lapins, Porcs, Reproducteurs et Escargots (mise en page du Blade, parité) ; dates du journal d'audit, des notifications et du profil affichées à l'heure du Bénin (S-T11) | ✅ 19/10/2026 (U12a : quatre fiches ; U12b : hub Rapports et dates) |
| U13 | Écarts relevés par U12b : `expenses` et `payslips` tirés au poste (Recettes et Dépenses du poste sans la paie ni les dépenses saisies ailleurs) ; « Échecs (mois) » du web qui compte le même mois des années passées (`whereMonth` seul) ; libellé « Paie — … » (priorité de `??` en PHP) ; cloche : « il y a … » comme au web ; alerte d'autonomie alimentaire levée aussi pour une fiche reçue d'un poste (`RaiseFeedAutonomyAlertAction`) | ✅ 19/10/2026 (Drift v47 ; paie servie à `view-rapports`, net seulement) |
| U14 | Derniers écarts relevés par U13 : écran « Saisie des Dépenses » du poste sur son Blade (recherche, filtre de statut, modifier, archiver) ; cloche : `title` comme au web (le poste affiche `message`) et rafraîchissement toutes les 30 s ; taux d'éclosion du jour sans œuf (question au client) | ✅ 20/10/2026 (`SaisieDepenseAction` web + envoi, Drift v48 ; `OrdreDesVerrous` stock avant fiche ; éclosion sans œuf « — » ; provende par identifiant ; revue U11–U13 : rationnement, Suivi Reproduction, Audit Logs, Centre de notifications ; décisions D-U14-1 à 4 plus bas) |
| U5 | `lang/fr` au web (validation, auth, mots de passe, pagination), `APP_LOCALE=fr` ; poste : localisation française des composants Flutter et chasse aux messages anglais | ✅ 19/10/2026 (lang/fr complet, 225 libellés de champs, pages d'erreur, API JSON ; poste en `fr`, messages d'échec français) |
| U6 | Date d'entrée à l'infirmerie : mêmes règles au web, au poste et à l'envoi | ✅ 19/10/2026 (et date du Nouveau Soin : future acceptée partout) |
| U7 | Prix moyen de provende sur les types actifs, au web comme au poste | ✅ 19/10/2026 (et « — » avec motif sans prix, au web comme au poste) |

### Décisions en attente relevées par U14 (20/10/2026)

| Réf. | Question au client |
|---|---|
| D-U14-1 | ✅ 20/10/2026 : **verrouillée** comme le montant (ticket EX5). La DATE d'une dépense comptabilisée reste modifiable (web et poste) ; l'écriture garde la date d'origine : registre des dépenses et grand livre peuvent se décaler d'une période. La verrouiller comme le montant, le compte de charge et le compte de trésorerie ? |
| D-U14-2 | ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement. *Question d'origine :* Export du journal d'audit au poste : non proposé (le poste ne détient que les 200 dernières lignes ; l'export ne pourrait pas être journalisé au serveur). Le garder au web seul, ou tirer la période entière ? |
| D-U14-3 | ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement. *Question d'origine :* Taux de mortalité sans effectif (fiches du jour, Dashboard Élevage, Tableau de bord) : « 0,0 % » des deux côtés ; appliquer « inconnu = — » comme pour l'éclosion ? |
| D-U14-4 | ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement. *Question d'origine :* Dépense saisie puis archivée au poste avant tout envoi : créée puis archivée au serveur (deux écritures, deux lignes d'audit), pour garder la trace — à confirmer (alternative : effacée du poste, rien n'est envoyé) |

## Sprint EX — Bascule et clôture d'exercice (PRD `docs/prd/exercices-comptables.md`)

### Décisions du client du 20/10/2026
Toutes les propositions du PRD sont retenues : **Q1** N+1 s'ouvre seul le 01/01 (tâche planifiée + filet à la première saisie) et par un bouton dès le 1er décembre ; **Q2** clôture refusée avant l'échéance ; **Q3** fiche d'élevage datée dans un exercice clos refusée ; **Q4** paie de décembre N validée en N+1 : charge au 31/12/N si N est ouvert, refus si N est clos ; **Q5** Bilan et Compte de résultat N / N-1 aussi au poste ; **Q6** archives conservées 10 ans, **sous réserve de confirmation du cabinet FAGUEZ** ; **Q7** reprises d'avant le logiciel = à-nouveau initial au premier jour du premier exercice ; **Q8** Réinitialisation interdite dès qu'un exercice a été clos hors mode démonstration ; **D-U14-1** date d'une dépense comptabilisée verrouillée.

### Lot 1 — en production avant le 15/12/2026 (bloquant au 01/01/2027)

| # | Ticket | Statut |
|---|---|---|
| EX1 | États justes après clôture (R1, défaut C1) : jamais historique + à-nouveau ; Bilan, Compte de résultat, États financiers, Balance, Grand Livre, TAFIRE, Rapprochement au web ; Balance et Grand Livre au poste (parité exécutée) ; à-nouveau initial des reprises (Q7) ; contrôle « ouverture N+1 = clôture N » dans S-T6 | ✅ 20/10/2026 (+ État de trésorerie, dotation aux amortissements, contrôle S-T6 au poste ; voir README_SPRINT0) |
| EX2 | À-nouveaux provisoires (R3, EF3) : ouverture de N+1 calculée tant que N est ouvert, mention « À-nouveaux provisoires », mêmes chiffres après clôture | ✅ 20/10/2026 (web : Bilan, Balance, Grand Livre, États financiers, Rapprochement, PDF ; poste : Balance, Grand Livre) |
| EX3 | Ouverture de N+1 sans clôture de N (R2, EF2, défaut C2) : tâche du 01/01 heure du Bénin, filet à la première saisie, bouton dès le 1er décembre, deux exercices ouverts au plus | ✅ (20/10/2026, `README_SPRINT0.md`) |
| EX4 | Clôture gardée (EF4) : échéance passée, étapes 1 et 2 faites, N-1 clos, à-nouveau équilibré ; à-nouveau verrouillé (ni modifiable ni archivable) | ✅ (20/10/2026, `README_SPRINT0.md`) |
| EX5 | Exercice clos verrouillé au serveur (EF5, EF6, R4) : stock, fiches (Q3), paie (Q4), déplacement d'écriture, date de dépense comptabilisée (D-U14-1) ; plus aucune erreur 500 ; messages R4 en JJ/MM/AAAA | ✅ (20/10/2026, `README_SPRINT0.md`) |
| EX6 | Refus local au poste sur tous les écrans de saisie (EF7), messages du serveur mot pour mot, calendriers bornés | ✅ (20/10/2026, `README_SPRINT0.md`) |

**Questions nées d'EX3–EX5 (au client / au cabinet FAGUEZ) — ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement (21/10/2026)** — détail dans `README_SPRINT0.md` :
- **EX-Q1** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : l'étape 2 ne solde que les classes 6 et 7 ; un compte de classe 8 (HAO) qui porte un solde rend l'à-nouveau déséquilibré, et la clôture est désormais refusée avec son motif (avant : erreur 500). L'étape 2 doit-elle solder aussi la classe 8 ?
- **EX-Q2** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : paie (Q4) — la charge est datée du dernier jour de la période, **sauf** si le règlement a lieu avant (charge au jour du règlement, une seule écriture). Les deux écritures (par le 422) ne sont passées que quand les deux dates diffèrent. À confirmer.
- **EX-Q3** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : au Journal, une écriture ne change plus d'exercice, même entre deux exercices ouverts (EF5 « vers un autre exercice ») : archiver puis ressaisir. À confirmer.
- **EX-Q4** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : au plus deux exercices ouverts (R2) : si N n'est pas clôturé au 31/12/N+1, N+2 ne s'ouvre pas et toute saisie de N+2 est refusée (l'administrateur est prévenu). Est-ce voulu, ou faut-il une marge ?
- **EX-Q5** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : « griser la date d'une dépense comptabilisée comme le montant » — ni le web ni le poste ne grisent le montant : le refus se fait à l'enregistrement, sous « Montant ». La date suit ce comportement ; le grisé relève d'EF10 (lot 2), à construire d'abord au web. → **Fait en EX7** : la date d'une dépense comptabilisée est grisée en modification, au web puis au poste, motif « Dépense déjà comptabilisée : sa date ne peut plus être modifiée. » en info-bulle ; le montant reste refusé à l'enregistrement (non grisé : à décider s'il doit l'être aussi).

**Questions nées d'EX6 (non tranchées)** — détail dans `README_SPRINT0.md` :
- **EX-Q6** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : les **transferts entre bandes** (web et poste) ne sont jugés par aucun exercice au serveur, alors qu'ils écrivent les fiches des deux bandes ; au poste, la fiche du transfert part ensuite à l'envoi et le serveur la refuse si l'exercice est clos (transfert accepté, fiche refusée). Faut-il refuser le transfert lui-même dans un exercice clos (Q3 étendue), d'abord au web ?
- **EX-Q7** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : les calendriers bornés (EF7) ne l'étaient qu'à la caisse ; EX6 a borné au web d'abord (`min`) la Saisie des Dépenses, les Dettes Fournisseurs, le remboursement, les Avances et l'Ajout de stock, puis le poste. Le sélecteur de date des **fiches d'élevage** n'est PAS borné (il sert aussi à consulter un jour passé, EF12) : le refus vient à l'enregistrement. À confirmer.

**Questions nées d'EX7 (non tranchées)** — détail dans `README_SPRINT0.md` :
- **EX-Q8** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : un exercice clos grise les saisies des écrans PILOTÉS (EF9 : Journal, Achats, Dépenses, Stocks, Soins, Transferts, Rapprochement, Historique des ventes) ; la **caisse**, les **fiches d'élevage**, la **paie** et les écrans clients ne lisent pas l'exercice affiché (une vente se date du jour). Faut-il les griser aussi quand 2026 clos est affiché ?
- **EX-Q9** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : les indicateurs « du mois » des écrans pilotés suivent le mois de référence de l'exercice affiché (le mois du jour, ou décembre 2026 lu en 2027) ; ceux qui ne sont pas « du mois » (Liste d'Achats, Historique des ventes au poste, totaux du Journal au poste) restent sur toute la ferme, comme avant. À confirmer.
- **EX-Q10** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : la Déclaration TVA et le Rapport mensuel ne proposent plus que les mois de l'exercice affiché (avant : les 12 derniers mois glissants, à cheval sur deux exercices). À confirmer.
- **EX-Q11** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement — (suite d'EX-Q5) : la date d'une dépense comptabilisée est grisée en modification ; son **montant** ne l'est pas (refus à l'enregistrement, sous « Montant »). Faut-il le griser aussi, d'abord au web ?

**Questions nées d'EX8 — ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement** — détail dans `README_SPRINT0.md` (numérotées EX-Q8 à EX-Q11 sur la branche d'EX8, renumérotées EX-Q12 à EX-Q15 à la fusion avec EX7, dont les EX-Q8 à EX-Q10 gardent leur numéro) :
- **EX-Q12** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : le Bilan et le Compte de résultat écartent l'écriture de solde des comptes de gestion (étape 2, `closing`) et sa contrepartie 131/139 : le résultat d'un exercice dont l'étape 2 est passée reste sur la ligne « Résultat de l'exercice » (avant : au 131, résultat 0) — mêmes totaux. Présentation « avant affectation » à confirmer par le cabinet FAGUEZ.
- **EX-Q13** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : la colonne N-1 présente l'exercice précédent À SA CLÔTURE (Bilan au 31/12/N-1, Compte de résultat de l'année entière), quelle que soit la date d'arrêté de N. Un comparatif « à date égale » (N au 31/01 contre N-1 au 31/01) n'est pas fait. À confirmer.
- **EX-Q14** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : le « Rapport mensuel » et la carte « Recettes du Mois » du hub (`produitsPeriode` / `chargesPeriode`) comptent encore l'écriture de solde : décembre d'un exercice dont l'étape 2 est passée affiche un chiffre d'affaires NÉGATIF (ventes de décembre − ventes de l'année). Relevé, non corrigé (hors du périmètre d'EX8). À corriger comme le Compte de résultat ?
- **EX-Q15** ✅ clos 21/10/2026 — le client les considère terminées : le comportement actuel est retenu, sans changement : au poste, l'onglet « Flux de Trésorerie » et les « Notes Annexes » des États financiers restent sur le web (la décision Q5 ne vise que le Bilan et le Compte de résultat ; les Notes lisent le registre des immobilisations, qui ne descend pas). Les porter aussi ?

### Lot 2 — avant la clôture de 2026 (mars 2027)
| EX7 | Sélecteur d'exercice global web + poste, listes paginées dans l'exercice choisi, lecture seule (EF8–EF10) | ✅ 20/10/2026 (+ EX-Q5 : date d'une dépense comptabilisée grisée ; voir README_SPRINT0) |
| EX8 | Bilan et Compte de résultat N / N-1 au web puis au poste (EF11, Q5) ; fiches d'élevage des mois passés (EF12) | ✅ 20/10/2026 (`README_SPRINT0.md` ; parité exécutée au poste) |
| EX7 + EX8 | Fusion et branchement : le sélecteur d'EX7 pilote les colonnes N / N-1 (web : écran Bilan, onglets et PDF des États financiers ; poste : `etats_comparatifs.dart`) ; bandeau des fiches = celui d'EX7 | ✅ 20/10/2026 (README_SPRINT0, « EX7 + EX8 — fusion et branchement ») |

### Lot 3 — avec la clôture de 2026
| EX9 | Archive figée de l'exercice à la clôture, hors purge des 30 jours, conservée 10 ans (Q6, à confirmer par FAGUEZ) ; Réinitialisation interdite après une vraie clôture (Q8) ; journal d'audit (EF13, EF14) | 🔧 (10/11/2026 : décisions Q6 et Q8 retenues le 20/10/2026 (voir ci-dessus), mais aucune archive figée ni garde de réinitialisation trouvée dans le code : non livré) |

---

## Sprint BS — Bandes & Sujets au poste, avec toutes les actions (demande du client du 21/10/2026)

> Demande : « dans le poste on doit avoir la possibilité de créer Bandes & Sujets avec CRUD, toutes les actions ».

**Constat (lu dans le code, pas supposé).**
- **Le poste n'a AUCUN écran « Bandes & Sujets » ni « Enregistrer des Sujets »** : la carte « Bandes & Sujets » de Gestion Élevage renvoie vers le web (`GestionElevageScreen.messageBandesWeb`), et `gestion-bandes.html` / `enregistrer-sujets.html` sont dans la liste de l'animalier mais sans `EcranPoste`. Ce n'est donc pas « une lecture seule » : les deux écrans sont à porter en entier, lecture comprise, avec leurs actions.
- **Web, bandes** (`GestionBandes`) : Créer (`saveLot`), Lire (liste, tiroir), Modifier (`updateLot` : stade, effectif actuel, statut), Archiver (`archiveLot`, `is_active = false`, confirmation `x-modal-confirm-delete`), droit `manage-elevage` partout, audit `livestock_lot.*`. Pas d'exercice jugé, pas de règle sur l'effectif à l'archivage (le web archive toute bande), restauration seulement par la Corbeille (Administration), absente du poste.
- **Web, sujets** (`EnregistrerSujets`) : seul « Nouveau Sujet » existe. Le docblock retire volontairement Modifier / Archiver (« romprait la cascade ») : c'était avant A1 ; la cascade unique `recalculerEnCascade()` rend maintenant la correction sûre. `newEntry` n'appelle pas `authorize`, l'exercice clos n'est pas jugé (la fiche écrite l'est pourtant à la saisie des fiches, Q3).
- **Serveur** : `livestock_lots` est un référentiel en tirage seul (aucun envoi accepté, aucune table de droit) ; les entrées de sujets sont des colonnes `achat` / `ne` / `don` de `livestock_daily_entries`, déjà acceptées à l'envoi (dernier écrivain gagne, cascade).
- **Poste** : `livestock_lots` n'a ni `sync_status` ni `device_id` ; son absorbeur écrase tout. Les entrées de sujets passent par `FicheJournaliereRepository`.

### BS1 ✅ (21/10/2026) Bandes — créer, modifier, archiver au poste (web d'abord)

**Objectif :** « Bandes & Sujets » au poste, à l'identique du Blade (KPI, filtres, tableau, tiroir, modales Nouvelle Bande / Modifier la Bande, confirmation d'archivage, toasts), saisies hors ligne en file, rejouées au serveur par le même point de passage que le web.
**Décisions client requises :** aucune pour coder (les huit questions BS-Q1 à BS-Q8 ci-dessous se tranchent après). Le poste reprend le web tel qu'il est, défauts compris.

**Web (agrierp_laravel)**
- `app/Actions/SaisieBandeAction.php` (nouveau) : point de passage UNIQUE de création, modification et archivage d'une bande — pour `GestionBandes` et `SyncController::pushLots`. Mêmes règles, mêmes messages.
- Règle nouvelle, web d'abord : une bande dont la date de création tombe dans un exercice CLOS est refusée (`AccountingEntryService::refusExerciceClos`, motif R4, sous « Date de Création » — l'erreur est ajoutée au Blade).
- `GestionBandes` : appelle l'Action ; `newLot` / `saveLot` / `editLot` / `updateLot` / `archiveLot` inchangés pour l'utilisateur. Archiver une bande déjà archivée n'a aucun effet.

**Poste (agrierp_flutter)**
- Drift v49 : `livestock_lots.sync_status` (défaut `synced`), `device_id` (nul), `effectif_corrige` (nul : correction manuelle d'effectif à envoyer) ; palier de migration + `migration_toutes_versions_test`.
- `BandesRepository` (nouveau) : liste, KPI, tiroir, `creer` / `modifier` / `archiver`, refus avant écriture avec les motifs du web, UUID au poste, `pending`, constitution par `TransfertsRepository.creer` (bande d'origine).
- `GestionBandesScreen` (nouveau) ; `EcranPoste.gestionBandes`, carte du hub rendue active, titre, droits (`manage-elevage`), `@lectureSeule`.
- Absorbeur `_absorberBandes` STRICT : une bande `pending` / `conflict` n'est jamais écrasée.

**Synchronisation :** `livestock_lots` devient une table MIXTE (tirée ET saisie). Envoi : `pushLots` (droit `manage-elevage`, refus motivés, idempotent, une bande archivée n'est plus modifiable, l'effectif n'est écrit que sur correction explicite `effectif_corrige`). Avant les fiches et les transferts du même envoi.

**Tests (écrits AVANT, rouges d'abord) :**
- Laravel : `BandesSujetsPosteTest` (création, modification, archivage, droits, rejets motivés, idempotence, exercice clos, bande archivée) ; `BandesSaisieActionTest` (le web passe par la même Action).
- Flutter : `bandes_poste_crud_test.dart` (repository, écran, file de sync, absorbeur), `bandes_blade_test.dart` (libellés lus dans le Blade).
- Épreuve de mutation : retirer le refus d'exercice, l'archivage logique, la protection `pending` de l'absorbeur, le droit.

### BS2 ✅ (21/10/2026) Sujets — nouveau, modifier, archiver (web d'abord, puis poste)

**Objectif :** « Enregistrer des Sujets » au poste avec toutes ses actions ; le web gagne d'abord Modifier et Archiver.
**Décision de modélisation (à confirmer, BS-Q2) :** une ligne du journal = une origine d'une fiche du jour (Naissance → `ne`, Achat → `achat`, Don → `don`). Modifier = changer la quantité (et/ou l'origine, la date) ; Archiver = retirer l'entrée (colonne remise à 0, la ligne quitte le journal, trace à l'audit). Dans les deux cas : cascade unique, et refus si un effectif deviendrait négatif un jour suivant.

**Web**
- `app/Actions/SaisieSujetAction.php` (nouveau) : `ajouter` (le code de `saveEntry`, déplacé), `modifier`, `archiver` ; exercice clos refusé (Q3) ; effectif négatif refusé.
- `EnregistrerSujets` : modale « Modifier le Sujet », confirmation d'archivage, colonne Actions (`manage-elevage` / `archive-elevage`), `authorize` aussi sur `newEntry`, une ligne par origine, audit `livestock_entry.updated` / `.archived`.

**Poste**
- `SujetsEntreesRepository` (nouveau, sur `FicheJournaliereRepository` : une seule écriture de fiche) ; `EnregistrerSujetsScreen` (nouveau) ; `EcranPoste.enregistrerSujets`.

**Synchronisation :** aucune table nouvelle : les fiches partent par `livestock_daily_entries` (déjà accepté, cascade du serveur). Tests de bout en bout : création, modification et archivage d'une entrée envoyés par le poste.

**Tests :** `BandesSujetsPosteTest` (volet sujets), `EnregistrerSujetsActionsTest` (web), `sujets_poste_crud_test.dart`, `sujets_blade_test.dart`, essai multipostes étendu.

**Hors périmètre / risques (BS1 + BS2) :**
- Registre des Reproducteurs (`Animal`, fiche sujet nominative) : le web le crée / modifie / sort, le poste le lit seulement ; non traité ici (BS-Q1).
- Restauration d'une bande : web = Corbeille uniquement ; portée depuis (`BandesRepository.restaurer`) — note corrigée le 27/10/2026 (inventaire § 9).
- Le prototype HTML est absent (A8) : les garde-fous lisent le Blade.

**Questions au client (non tranchées) :**
- **BS-Q1** ✅ *tranché 21/10/2026* : « Sujets » inclut le registre nominatif des reproducteurs (`Animal`) : porté en écriture au poste (ticket BS3 ci-dessous).
- **BS-Q2** : « Archiver un sujet » = retirer l'entrée du journal (quantité remise à 0, tracé à l'audit) : confirmé ? Sinon, quelle trace garder ?
- **BS-Q3** ✅ *tranché 21/10/2026* : une bande qui a un effectif vivant (> 0) ne s'archive pas (« Cette bande compte encore N sujets vivants : archivez-la après avoir sorti ou transféré les sujets restants. ») ; une bande à effectif 0 s'archive. Web (`SaisieBandeAction` + `GestionBandes`), poste et envoi du poste (rejet motivé, `conflict`). Le vidage reste possible : fiche (mort, vente, don), transfert, correction d'effectif d'une bande sans fiche.
- **BS-Q4** ✅ *tranché 21/10/2026* : « Effectif Actuel » de « Modifier la Bande » n'est plus modifiable dès que la bande a des fiches (champ grisé, info-bulle explicative, refus du serveur aussi) ; la correction passe par la fiche (cascade unique). Une bande sans fiche garde l'édition libre.
- **BS-Q5** : l'archivage d'une bande utilise `manage-elevage` au web (le droit `archive-elevage` existe mais n'est lu nulle part). Passer à `archive-elevage` ?
- **BS-Q6** ✅ *tranché 21/10/2026* : une bande datée dans un exercice clos est refusée (déjà livré en BS1) ; tests de non-régression au web, à l'envoi et au poste.
- **BS-Q7** ✅ *tranché 21/10/2026* : restauration d'une bande archivée au poste. Web d'abord : filtre « Bandes archivées » et bouton « Restaurer » (`manage-elevage`, audit `livestock_lot.restored`, refusée si une autre bande en cours porte le même code) dans « Bandes & Sujets » ; puis poste (Drift v50) et envoi (`restauree`, geste explicite).
- **BS-Q8** ✅ *traité par UNI (21/10/2026)* : deux postes créant la même bande hors ligne (même code) : le second envoi est refusé avec le code et la marche à suivre (« renommez-la… »), la bande saisie est gardée sur le poste, se renomme et repart. Voir UNI ci-dessous.

**Livré (21/10/2026)** : voir `agrierp_laravel/README_SPRINT0.md`, entrée « BS1 + BS2 ». Écart au plan : « Enregistrer des Sujets » n'était relié à aucun écran du web ; un bouton « Enregistrer des Sujets » a été ajouté à « Bandes & Sujets » (web puis poste), sinon l'écran du poste était inatteignable. Questions **BS-Q9** : ce bouton est-il voulu (ou un emplacement dans la barre latérale) ? **BS-Q10** : au web, `ucfirst('cloture')` donne « Cloture » (sans accent) dans le PDF des bandes, « Clôturé » à l'écran — à corriger ?

## Sprint ENV — Enveloppe du poste Windows (demandes du client du 21/10/2026)

### ENV1 ✅ (21/10/2026) Nom de l'administrateur, icône, recherche globale, image de connexion, barre des tâches

1. **Compte administrateur** : le seeder web avait DÉJÀ « M. Olouchègoun » (`DemoUsersSeeder`, identifiant `admin`) ; il restait l'ancien nom de démonstration au poste (repli du socle, tableau de bord, jeux d'essai) — remplacé ; test web `AdministrateurPrincipalNomTest` (nom, rôle, mot de passe, connexion par `admin`, base existante renommée sans toucher au mot de passe). Garde-fou poste `nom_admin_principal_test.dart`.
2. **Icône** : `app_icon.ico` multi-tailles généré depuis le logo (`outils/generer_icone.py`), installateur (raccourcis, désinstallation), icônes de fenêtre ; test `icone_application_test.dart`.
3. **Recherche globale** : 32 px → 44 px, la hauteur du web (elle sort des classes : pastille + base `@tailwindcss/forms` de l'input) ; sous `md`, icône seule comme le web. **Question ENV-Q1** ✅ tranché 21/10/2026 (OUI : la boîte grise de la recherche est gardée, comme au web) : le web dessine une boîte grise carrée DANS la pastille ronde (l'input n'a ni `border-0` ni `p-0`) ; reprise telle quelle. Si elle déplaît, la corriger d'abord au web.
4. **Image de connexion** : `image_login.png` copiée du web (`public/assets/images/`), déclarée, voile du Blade, panneau de repli si le fichier manque.
5. **Barre des tâches** : la fenêtre occupe la zone de travail ; boutons Agrandir/Restaurer, glisser et double-clic ajoutés (ils n'existaient pas, malgré la consigne). **ENV-Q2** : taille minimale de fenêtre retenue 640×480 — à confirmer.

**NON vérifié** : tout le comportement Windows (voir `agrierp_laravel/README_SPRINT0.md`, ENV1).

### BS3 ✅ (21/10/2026) Registre nominatif des reproducteurs au poste (BS-Q1 tranché)

**Objectif :** « Sujets » inclut le registre nominatif (`Animal`, `RegistreReproducteurs`, `AnimalDetails`) : le poste l'ÉCRIT (enregistrer, modifier, sortir), à l'identique du web.
**Vérifié d'abord au web :** Créer, Modifier et Sortir existent déjà (`manage-elevage`, audit, aucune cascade d'effectif : identifier n'est pas faire entrer) ; construit au web : point de passage `SaisieReproducteurAction`, bouton « Registre des Reproducteurs » dans « Bandes & Sujets » (l'écran n'était relié à rien), seconde sortie refusée.
**Poste / serveur :** `animals` table mixte (`pushAnimals`), Drift v51, `ReproducteursRepository`, `RegistreReproducteursScreen`, absorbeur strict qui protège `pending` / `conflict`. Détail et mesures : `agrierp_laravel/README_SPRINT0.md`, entrée « Décisions du client du 21/10/2026 ».
**Questions au client — ✅ tranché 21/10/2026 (OUI aux trois), livré web puis poste (voir `agrierp_laravel/README_SPRINT0.md`, entrée « Décisions du client du 21/10/2026 sur le registre des reproducteurs ») :** **BS-Q11** ✅ tranché 21/10/2026 — « Reforme » sans accent au registre : désormais « Réformé », « Vendu », « Mort » (correspondance unique `Animal::LIBELLES_STATUT`, valeur technique inchangée) · **BS-Q12** ✅ tranché 21/10/2026 — espèces du registre : un seul critère, les modules actifs (`LivestockSpecies::enabled()`, celui du tirage), web et poste · **BS-Q13** ✅ tranché 21/10/2026 — l'identifiant d'un sujet enregistré ne change plus (champ grisé, refus serveur y compris à l'envoi du poste).

## Sprint AV — « Retours et Avoirs » et « Historique des Ventes » au poste (demande du client du 21/10/2026)

> Demande : « screen Retours et Avoirs doit être la même chose que celle de la version web » ; « même chose pour le screen Historique des Ventes ». PRD : `docs/prd/avoirs-historique-poste.md` ; audit ligne à ligne : `docs/AUDIT_FIDELITE_ECRANS.md` § 11.

### AV1 ✅ (21/10/2026) Retours et Avoirs au poste (web d'abord)

**Objectif :** l'onglet « Retours et Avoirs » du hub Ventes & Devis, à l'identique du Blade ; le poste enregistre la DEMANDE, le serveur fait les effets (motif F0.74).
**Web :** `AvoirClientService` (point de passage UNIQUE de `RetoursAvoirs::saveReturn()` et de l'envoi du poste) ; refus nouveaux, construits d'abord ici : quantité > « vendu − déjà retourné », montant > « ligne − déjà crédité », vente annulée / inconnue, produit hors vente, date future ou antérieure à la vente, exercice absent ou clos, plan comptable incomplet — rien n'est écrit (une transaction ; fini « retour enregistré SANS écriture »). `CreditNote::generateCreditNoteNumber()` prend l'année du jour du retour.
**Serveur :** famille de tirage paginée `credit_notes` (`view-ventes`) ; `pushCreditNotes` (`manage-ventes`, après les ventes, idempotent par UUID, `traite` une seule fois, date du fait `credit_date`) ; `MotifsRefusPush`.
**Poste :** Drift **v54** (`credit_notes`, table mixte ; palier `from < 54`, le 53 est réservé à la branche « Devis Prestations »), absorbeur STRICT, `_avoirEnJson`, acquittement, relance d'un refus, libellés, purge à la réinitialisation ; `AvoirsRepository` + `RetoursAvoirsOnglet`.

### AV2 ✅ (21/10/2026) Historique des Ventes au poste, identique au Blade

**Objectif :** audit ligne à ligne Blade ↔ Dart (25 écarts, tous corrigés : § 11.1 de l'audit) ; toutes les actions du Blade.
**Web / serveur :** `AnnulerVenteAction` (extraite de `cancelSale()`, partagée avec l'envoi) ; `pushSales` : une vente connue renvoyée `annulee` est annulée une fois (stock réintégré, audit), une vente inconnue annulée avant son premier envoi est reçue puis annulée ; `sales` servi avec `subtotal` et `discount` ; `GET /api/ventes/{id}/pdf` (`export-ventes`, ticket du web).
**Poste :** `HistoriqueVentesOnglet` (extrait du hub) + `HistoriqueVentesRepository` (cartes sur la période, filtres, détail, annulation en demande, `ClientVentes` pour le PDF) ; `ChampDateFiltre` compact pour la période ; pièces communes `elements_ventes.dart`, `GrilleKpi`.

**Tests (écrits d'abord, mutation faite) :** Laravel `AvoirsClientsSyncTest` (30) ; poste `avoirs_poste_test` (35), `avoirs_sync_poste_test`, `avoirs_blade_test`, `avoirs_schema_test`, `avoirs_parite_php_test` (le VRAI `SyncController` reçoit l'envoi du poste), `historique_ventes_poste_test`, `historique_ventes_blade_test`, `migration_toutes_versions_test` (v54). Détail et mesures : `agrierp_laravel/README_SPRINT0.md`, entrée « AV1 + AV2 ».

**Questions au client (non tranchées) :**
- **AV-Q1** L'avoir ne diminue pas la créance d'une vente à crédit (web inchangé). Imputer l'avoir sur la créance ? (recommandé : OUI)
- **AV-Q2** Annuler une vente ne contre-passe ni l'écriture, ni la créance, ni l'encaissement : seul le stock revient (web inchangé depuis 4.4). Contre-passer ? (recommandé : OUI, écriture inverse datée du jour)
- **AV-Q3** Remboursement d'un avoir (D 411 / C trésorerie) : à construire au web d'abord, avec le choix du compte. (recommandé : OUI)
- **AV-Q4** Un retour en exercice clos ou sur plan comptable incomplet est désormais REFUSÉ au web et à l'envoi (avant : enregistré sans écriture). À faire confirmer par le cabinet FAGUEZ.
- **AV-Q5** Export Excel / PDF en masse de l'historique : le web ne l'a pas (le poste retire ses deux boutons inertes). En vouloir un ? (web d'abord)

**NON vérifié :** poste Windows réel (rendu du tiroir, du calendrier, de l'enregistrement du PDF dans Documents\LogiAgriERP) ; navigateur (Dusk) pour les modifications du Blade (aucune : seul le composant a changé) ; une base MySQL / MariaDB peuplée (numérotation `AV-AAAA-NNN` par `MAX(CAST(...))` sous envois simultanés de deux postes : sérialisée par la transaction d'envoi, non éprouvée sur MariaDB) ; l'essai à cinq postes n'a pas été étendu aux retours.

**Reste :** `VentesDevisRepository.charger()` et ses classes `DonneesHistorique` / `LigneHistorique` ne servent plus à rien (laissés pour ne pas heurter la branche `t-devis` ; à supprimer après la fusion).

## Sprint MP — Mise en page du poste (demandes du client)

| Ticket | Contenu | État |
|---|---|---|
| MP1 | Libellés et champs « Date » et « Mois » : marges, espacements, alignements et proportions repris des classes Tailwind du Blade ; un champ partagé par gabarit (`lib/core/widgets/champs_date_agri.dart`, constantes `AgriChamps`) ; 20 écarts corrigés sur 20 écrans (`docs/AUDIT_FIDELITE_ECRANS.md` § 9) ; mesures à 640 / 1024 / 1440 px et garde-fou qui lit les classes du Blade | ✅ 21/10/2026 (`README_SPRINT0.md` ; rendu réel Windows / navigateur NON vérifié) |
| MP2 | Mêmes contrôles pour les libellés et champs VOISINS d'une date dans les modales (texte, liste, nombre : `h-11 px-md text-sm`, libellés `text-[10px] uppercase`), `labelText` flottant de Transferts, « Compte : » du Grand Livre ; construire les champs Date que le poste n'a pas (Historique des ventes, Liste d'Achats, Bilan…) relève de tickets de fonctionnalité | ✅ 11/11/2026 (`lib/core/widgets/champs_formulaire_agri.dart` promu depuis `elevage/` ; re-export + typedef dans `champs_modale_elevage.dart` ; `transferts_bandes_screen.dart` : 6 `InputDecoration(labelText:…)` → `BlocChampFormulaire` ; `comptabilite_screen.dart` : Grand Livre `DropdownButtonFormField` → `cadreChampFormulaire` h-11 ; garde-fou `test/champs_voisins_date_test.dart`) |
| MP1-Q1 | ✅ *tranché 21/10/2026* : `flex-wrap` ajouté à la barre « Bande / Date / Mois » du Blade de la fiche Reproducteurs (retouche web) ; l'écart disparaît, garde-fou `champs_date_mise_en_page_test.dart` et `docs/AUDIT_FIDELITE_ECRANS.md` § 9 mis à jour | ✅ 21/10/2026 |

| MP1-Q1 | ❓ Fiche Reproducteurs : le Blade ne replie pas sa barre « Bande / Date / Mois » (`flex items-center gap-xs` sans `flex-wrap`). Le poste la replie. Ajouter `flex-wrap` au Blade (retouche web) ou garder l'écart ? | ✅ client (livré, vérifié le 10/11/2026 : doublon périmé de la ligne MP1-Q1 ci-dessus, tranchée le 21/10/2026 ; `flex-wrap` présent dans `fiche-reproducteurs.blade.php` ligne 34, garde-fou `champs_date_mise_en_page_test.dart` ligne 444) |

## Sprint MAIL — Domaine des adresses e-mail (décision du client du 21/10/2026)

### MAIL1 ✅ (21/10/2026) Anciennes adresses `@olouwachegoun.bj` converties en `@fermeolouwachegoun.com`, au web et au poste

**Décision (impérative) :** tous les e-mails en `@olouwachegoun.bj` deviennent `@fermeolouwachegoun.com`, AUSSI ceux déjà enregistrés, au web comme au poste, placeholders compris. Le code, les seeders, les tests et les écrans l'étaient depuis le commit `1505a53` ; ce ticket convertit les DONNÉES.

**Web :** migration `2026_10_21_000001_migrer_les_adresses_email_du_domaine` (parcours générique du schéma ; colonnes dont le nom évoque une adresse, `company_settings`, titre et message des notifications ; secrets écartés par leur nom et jamais lus ; `audit_logs` et `journal_synchronisation` exclus, l'historique ne se réécrit pas ; `users.email` unique respecté, un conflit est journalisé et la ligne reste ; compte `admin` : `dg@` devient `contact@fermeolouwachegoun.com` ; `updated_at` rafraîchi sur les seules lignes changées pour que les postes les reprennent). Test `MigrationAdressesEmailTest`.
**Poste :** palier Drift v50 (`_convertirAdressesEmail`, SQL, insensible à la casse) sur `customers`, `suppliers`, `company_settings`, `utilisateurs`, `notifications` (titre, message) et `app_settings` ; `sync_status` et `updated_at` intacts ; aucune table changée (`app_database.g.dart` inchangé). L'e-mail de la session mise en cache au coffre est converti à la lecture (`convertirDomaineEmail`). Test `migration_emails_poste_test.dart`.

**Non vérifié :** migration sur une base réelle peuplée (MySQL/MariaDB de production) ; poste Windows réel (mise à jour d'une base locale existante).
**Laissé tel quel, à confirmer :** le nom de serveur SMTP `smtp.olouwachegoun.bj` éventuellement saisi (pas une adresse : à corriger à la main dans Paramètres → Email (SMTP) si le serveur a changé) ; `support@faguez-sarl.bj` (adresse de l'éditeur, autre organisation) ; les adresses fictives des tests (`@ferme.bj`, `@resto.bj`).

## Sprint DEV — « Devis & Proforma » au poste (demande du client du 21/10/2026)

> **Demande :** « la saisie Devis & Proforma avec son tab panel et son CRUD doit être faite dans le poste », identique au web. PRD : [`docs/prd/devis-poste.md`](prd/devis-poste.md). Périmètre : le seul onglet « Devis Prestations » (modèle `Quote`) du hub « Ventes & Devis ». « Retours et Avoirs » et « Historique des Ventes » : ticket à part.

### DEV1 ✅ (21/10/2026) Devis — créer, modifier, avancer dans le cycle, archiver, exporter, au web puis au poste

**Objectif :** l'onglet « Devis Prestations » du poste reprend `devis.blade.php` / `Devis.php` à 100 %, avec sa table synchronisable.
**Décisions client requises :** aucune pour livrer (propositions recommandées retenues, voir ci-dessous) ; trois questions ouvertes pour la suite (DEV-Q1 à DEV-Q3).

**Web (agrierp_laravel)** — ordre : modèle → Action → Livewire → Blade
- `app/Actions/SaisieDevisAction.php` : point de passage unique (créer, modifier, `changerStatut`, `aligner`, archiver) ; exercice clos refusé (règle `refusExerciceClos`, motif R4), cycle `brouillon → envoyé → accepté | refusé`, devis archivé ou facturé non modifiable, idempotence, audit.
- `Livewire\Ventes\Devis` appelle l'action ; `devis.blade.php` : erreur sous « Date du Devis », « TVA » et « Validité » ; `Quote::STATUTS`.
- Table `quotes` inchangée (déjà UUID : `uuid('id')->primary()`).

**Poste (agrierp_flutter)** — ordre : table Drift (+ build_runner, palier v53) → dépôt → écran
- `Quotes` (SyncColumns : `id` UUID, `device_id`, `sync_status`, `updated_at` ; `quote_number` NULLABLE), `schemaVersion` 52 → **53** (palier `createTable` gardé par `_tableExiste`), `tablesEnvoyees`, `tablesDActivite` (purgée à la réinitialisation).
- `lib/features/ventes/devis_repository.dart` (`DevisRepository`), `lib/features/ventes/devis_onglet.dart` (`DevisOnglet`, modale), `ventes_devis_screen.dart` (branchement), `main.dart` (câblage et droits `manage-ventes` / `export-ventes`).

**Synchronisation :** `quotes` table MIXTE (tirée ET saisie). Tirage : `PERMISSIONS_DE_TIRAGE['quotes'] = ['view-ventes']`, archivés compris. Envoi : `pushQuotes` (`manage-ventes`), après les clients ; numéro `DEV-AAAA-NNN` jamais lu du poste ; `quotes` ajouté à `FusionReferentielsService::REFERENCES` (client fusionné). Poste : `_absorberDevis` STRICT, jamais d'écrasement d'un `pending` / `conflict`, acquittement de la version partie (`_marquerSiInchangee`), `relancer`.

**Décisions tranchées sur les recommandations :**
1. **Numéro attribué par le serveur** (précédent : courriers F0.78). Le poste affiche « — » jusqu'au tirage qui suit l'acquittement.
2. **Exercice clos refusé** (demande explicite du client), construit AU WEB d'abord (le Blade ne le faisait pas) : règle `closSeulement`, un devis ne passe aucune écriture ; vaut pour création, modification (date d'origine et nouvelle), statut et archivage.
3. **Cycle contrôlé** : `facture` n'est atteint par aucun geste d'écran ni de poste (la conversion n'existe pas au web). Un poste qui envoie puis accepte hors ligne envoie l'état final ; le serveur parcourt le cycle pas à pas (`aligner`).
4. **« Convertir en Facture » identique au web** : son toast d'attente, sans effet (DEV-Q1).
5. **Pas de sous-onglets** : le « tab panel » est le hub (4 onglets) ; l'onglet Devis n'en a pas au web.
6. **Pas de pagination ni de filtre d'exercice** : le web liste tous les devis actifs (`->get()`), le poste aussi.

**Tests (écrits d'abord, rouges) :** web `DevisSaisieWebTest` (15) ; serveur `DevisPosteTest` (22 : accepté, rejeté, idempotent, numérotation, cycle, exercice clos, rôles, fusion, tirage) ; poste `devis_poste_test.dart` (65) et garde-fou `devis_blade_test.dart` (14). Gardes existants mis à jour : `perimetre_tirage_test`, `ecrivain_unique_test`, `migration_toutes_versions_test` (v53), `conformite_portage_test`, `ventes_devis_test`, `SyncTiragePagineTest`. Épreuve de mutation : `agrierp_laravel/README_SPRINT0.md`, entrée DEV1.
**Vérification :** `php artisan test --testsuite=Feature`, `flutter analyze`, `flutter test`. Compteurs exacts : `agrierp_laravel/README_SPRINT0.md`.
**Non vérifié / risques :** navigateur (Dusk) et poste Windows réels ; la conversion devis → facture (absente du web) ; l'impression « document client » d'un devis (DEV-Q3).

| Ticket | Contenu | État |
|---|---|---|
| DEV2 | Tableau de bord : l'onglet « Devis » des « Transactions récentes » est encore vide au poste (« Aucun devis récent. ») alors que `quotes` descend désormais ; le lire comme `Dashboard\Index` | ✅ (livré le 10/11/2026 : `devisRecents` dans `tableau_de_bord_repository.dart`, onglet branché dans `tableau_de_bord_screen.dart` ; parité exécutée contre le vrai `Dashboard\Index` sur 8 jeux, mutations prouvées. ✅ DEV2b (10/11/2026) : `quotes` servie à `view-ventes` OU `view-elevage` — l'animalier reçoit les devis comme le web le lui montre ; `SyncController`, `DevisPosteTest`, `perimetre_tirage_test` mis à jour et verts. ⚠️ Écart assumé restant : le web trie par `created_at`, non servi au poste ; le poste trie par `quote_date` puis `updated_at`) |
| DEV-Q1 | ✅ (09/11/2026) Construit : la conversion « devis accepté → facture / vente » existe au web puis au poste (`ConversionDevisFactureTest`, `ConversionDevisWebTest`). *Question d'origine :* Conversion « devis accepté → facture / vente » : absente du web (toast d'attente « module Facturation, Sprint 7 »). Recommandé : la construire d'abord au web (statut `facture`, `converted_sale_id`), puis la porter. Un devis facturé crée-t-il une vente à crédit (créance) ou une vente payée ? | ✅ livré |
| DEV-Q2 | ✅ Lignes de devis structurées : **NON, acté le 09/11/2026 (DV-36)** — description libre comme le web ; à rouvrir si les prestations deviennent fréquentes | ✅ validé 09/11/2026 |
| DEV-Q3 | ✅ **Livré (09/11/2026, DV-35)** : « Imprimer le devis » au web (`Devis::imprimerDevis`, `exports.devis-document`, droit `export-ventes`) puis au poste (`DevisRepository.documentDevis`, mêmes libellés et même ordre, numéro « — » tant que non reçu) ; validité = date + `validity_days` du devis (le web a cette durée : rien d'inventé) ; coordonnées du client (téléphone, ville, IFU) reprises ; `aide_ecrans` régénéré | ✅ validé 09/11/2026 |
## Sprint VL — Verrou local du poste (décision du client du 21/10/2026)

### VL-1 ✅ (21/10/2026) Code PIN, écran de verrouillage à chaque lancement, sans réseau

**Décision (impérative) :** « Verrou local (code PIN ou mot de passe mémorisé localement) : écran de verrouillage à chaque lancement, sans réseau requis. » Retenu : un **code PIN de 4 à 6 chiffres** (jamais le mot de passe, que le poste ne conserve toujours pas). La reprise de session hors ligne est GARDÉE ; le verrou s'ajoute par-dessus.

**Exception de fidélité (doctrine § 5.6) :** fonction **propre au poste**. Le web n'a pas de verrou et n'en reçoit pas : aucun écran du Blade n'est modifié, le poste ajoute un écran avant l'application, l'entrée « Verrouiller » au menu du compte (avant « Déconnexion ») et la carte « Changer le code PIN » à Mon Profil.

**Livré (poste uniquement, aucune migration, schéma Drift inchangé) :**
- `lib/core/auth/verrou_local.dart` : PBKDF2-HMAC-SHA256, 100 000 itérations, sel aléatoire de 16 octets, comparaison à temps constant ; sel et empreinte au coffre, par utilisateur (`agrierp.verrou.<id>`) ; compteur d'échecs persistant ; dès le 5e échec temporisation 30 s, 1 min, 5 min, 15 min, 30 min ; **10 échecs cumulés : accès local refusé, reconnexion EN LIGNE exigée**. Dépendance directe ajoutée : `crypto` (déjà présente en transitive).
- `lib/features/verrou/` : l'écran de verrouillage et celui de définition ont **la présentation de l'écran de connexion** (précision du client : « un écran de connexion à chaque lancement, avec reprise de session sans se connecter au serveur ») : `CadreConnexion`, `ChampConnexion` (identifiant en lecture seule), `BoutonConnexion` extraits de `LoginScreen` et partagés, le secret étant le PIN ; `PorteSession` (chargement, connexion, définition, verrou, application : rien n'est montré avant que l'état soit connu), `EcranVerrou`, `EcranDefinirPin` (saisie + confirmation, obligatoire, sans « Plus tard »), `PavePin` (clavier à l'écran ET clavier physique, Entrée valide, points masqués), `changerPinDepuisProfil`.
- Parcours : connexion en ligne sans PIN → définition ; connexion avec PIN existant → pas de redemande dans cette exécution ; session restaurée + PIN → verrou ; session restaurée sans PIN (poste mis à jour) → définition obligatoire ; « PIN oublié ? Se reconnecter » → confirmation, déconnexion, PIN effacé, retour à la connexion (qui redéfinit le PIN).

**Limites et décisions :**
- **Horloge** : la temporisation se mesure à l'horloge de Windows. Reculer l'horloge ne la raccourcit pas (comptée depuis le dernier essai) ; l'avancer ne fait gagner que des minutes. Le plafond de 10 échecs, lui, ne dépend d'aucune horloge. Un PIN de 4 à 6 chiffres protège d'un passant, pas d'un attaquant maître de la session Windows.
- Verrouiller **démonte** l'application (l'écran de verrouillage la remplace, il ne la recouvre pas) : une saisie en cours est perdue, la synchronisation automatique de l'accueil s'arrête pendant le verrou et repart au déverrouillage.
- **Verrouillage automatique après inactivité : non fait dans VL-1** ; décidé OUI par le client le 21/10/2026 (VL-Q1 ✅ close) et livré par VL-2 ci-dessous.
- Une déconnexion normale (menu du compte) conserve le PIN de l'utilisateur ; « PIN oublié » et les dix échecs l'effacent.
- Tests : `verrou_local_test.dart` (18) et `verrou_ecrans_test.dart` (21), écrits rouges d'abord, 7 mutations tuées. **Non vérifié :** coffre Windows réel (Credential Manager), durée de PBKDF2 sur le poste le plus lent de la ferme.


### VL-2 ✅ (21/10/2026) Verrouillage automatique après inactivité (VL-Q1 close : OUI)

**Décision du client (VL-Q1) :** OUI, poste uniquement. **Exception de fidélité** (doctrine § 5.6, même ligne que VL-1) : le web n'a ni verrou ni inactivité. Aucune migration Drift, aucune synchronisation.

**Livré :**
- `lib/core/auth/verrou_inactivite.dart` : `ReglageInactivite` (durée en minutes par utilisateur, au coffre sous `agrierp.inactivite.<id>` ; choix **Jamais / 1 / 5 / 15 / 30 min ; défaut 5 min — décision consignée** ; valeur illisible ou coffre inaccessible = 5 min), `VerrouInactivite` (minuteur, `Timer` donc pilotable par `FakeAsync`, fabrique injectable), `SurveillanceInactivite` (un `Listener` — clic, déplacement, survol, molette/défilement — et un `HardwareKeyboard` globaux).
- Posé UNE fois, dans `MaterialApp.builder` de `main.dart` (au-dessus du navigateur : une interaction dans une fenêtre modale compte). Armé par `PorteSession` à l'ouverture de l'application, désarmé dès qu'elle la quitte : **jamais pendant la connexion, la définition du PIN ni l'écran de verrouillage** (il ne se re-verrouille donc pas). À l'échéance le PIN est relu : **sans PIN, pas de verrou**.
- À l'échéance : fenêtres modales fermées (elles recouvriraient l'écran de verrouillage), application démontée, écran de verrouillage ; PIN requis, sans réseau (même chemin que « Verrouiller »).
- Mon Profil : rubrique « Verrouillage automatique » (liste déroulante) sous « Changer le code PIN » ; le choix s'applique aussitôt.

**Décisions :**
- **Synchronisation en cours** (`SyncEngine.enCours`) : le verrou n'interrompt JAMAIS un tirage ou un envoi ; il attend sa fin (revérification toutes les 10 s). ⚠️ **Limite :** une fois verrouillé, l'application est démontée (comme décidé pour VL-1) et la synchronisation AUTOMATIQUE (minuterie, réseau, gestes) s'arrête avec le socle d'accueil ; elle repart au déverrouillage. La laisser tourner exigerait de sortir `SynchronisationAutomatique` du socle (son `onTermine` rafraîchit l'écran) : non fait, à décider (ticket éventuel).
- **Saisie non enregistrée** : le projet n'a qu'un brouillon persistant, celui de « Contactez l'Éditeur » ; il est désormais possédé par la coque (`_AgriErpAppState`), donc **il survit au verrouillage** (et est vidé à la déconnexion et à « PIN oublié », pour qu'un autre utilisateur ne le retrouve pas). Les formulaires modaux n'ont pas de brouillon : s'il y en a un d'ouvert à l'échéance, le verrou est **reporté d'une minute, une seule fois** (toute interaction rend son report), puis la fenêtre est fermée et la saisie non enregistrée est perdue — choix : un poste laissé seul ne reste pas ouvert indéfiniment pour un formulaire oublié.
- Tests : `verrou_inactivite_test.dart` (15) et `verrou_inactivite_ecrans_test.dart` (8), écrits rouges d'abord ; 8 mutations tuées (défaut, interaction sans effet, PIN non relu, minuteur non désarmé, report, durée, « Jamais », synchro en cours). **Non vérifié :** comportement sur Windows réel (événements souris sous RDP/écran tactile), reprise d'une saisie non enregistrée de modale (perdue).

## Sprint VW — Verrou de session sur le web (demande du client du 26/10/2026, PRD `docs/prd/verrou-web.md`)

> « Il faut appliquer aussi le module de verrou session sur le web. » **Cette décision lève l'exception de la doctrine § 5.6** : le verrou est désormais présent des DEUX côtés, avec un mécanisme propre à chacun (web : mot de passe du compte vérifié par le serveur ; poste : PIN local, sans réseau). Le web est construit d'abord (maître) ; le poste ne change que ses libellés communs.

**Décisions client requises :** aucune bloquante. VW-Q1 (défaut 5 min pour tous), VW-Q2 (plafond imposé), VW-Q3 (réglage partagé web/poste), VW-Q4 : voir le PRD § 9, propositions retenues en attendant.

### VW1 ✅ (26/10/2026) — Web, serveur : état, middleware, déverrouillage
**Objectif :** un verrou effectif côté serveur, valable même si le navigateur est manipulé.
**Web :** migration `users.verrouillage_minutes` (smallint, défaut 5) · `VerrouSessionService` (durées, libellés, verrouiller, déverrouiller, limiteur de la connexion, 10 échecs = déconnexion, cookie de rappel) · middleware `SessionVerrouillee` (groupe `web`) · routes `POST /verrouiller`, `POST /deverrouiller`, `GET /verrouillage`.
**Tests (rouges d'abord) :** `VerrouSessionMiddlewareTest`, `VerrouSessionDeverrouillageTest`, `VerrouSessionAuditTest`. **Mutation :** retirer le test de l'état ; seuil 10 → 11 ; ne pas vérifier le hash.

### VW2 ✅ (26/10/2026) — Web, navigateur : surcouche, minuterie, menu
**Web :** composant `x-verrou-session` (surcouche plein écran à la présentation de la connexion), `resources/js/verrou.js` + `verrou-logique.js` (minuterie partagée entre onglets par `localStorage`, requêtes Livewire en vol, 423 → surcouche), entrée « Verrouiller » du menu du compte, page `/verrouillage` (composant `Auth\EcranVerrouillage`).
**Tests :** `VerrouSessionBladeTest`, `tests/Js/verrou-logique.test.mjs`.

### VW3 ✅ (26/10/2026) — Web : réglage dans Mon Profil
**Web :** carte « Verrouillage automatique » (liste Jamais / 1 / 5 / 15 / 30 minutes), `MonProfil::updatedVerrouillageMinutes`. **Tests :** `VerrouSessionReglageTest`, `VerrouSessionLivewireTest`.

### VW4 ✅ (26/10/2026) — Journal d'audit
**Web :** libellés `session.*` dans `AuditLog` ; **poste :** `libelles_audit.dart` régénéré par `outils/libelles_audit.py`.

### VW5 ✅ (26/10/2026) — Poste : un seul jeu de textes
**Poste :** libellé de la phrase d'aide de « Verrouillage automatique » et sous-titre de l'écran alignés sur le Blade ; `chassis_web_test.dart` attend « Verrouiller » dans le menu web ; garde-fou `verrou_parite_web_test.dart` (libellés lus dans le Blade, durées lues dans `VerrouSessionService`). Aucune migration Drift.

### VW6 ✅ (26/10/2026) — Documentation
PRD, doctrine § 5.6 (exception levée), `CLAUDE.md` Laravel et Flutter, `README_SPRINT0.md`.

**Statut :** VW1 à VW6 ✅ (26/10/2026, branche `t-verrouweb`). **Non vérifié :** navigateur réel (minuterie, `storage` entre onglets, hook Livewire 423) ; `flutter analyze` / `flutter test` (Flutter absent de l'environnement de la session). Questions VW-Q1 à VW-Q4 : ❓ client (propositions appliquées).

**Doctrine :** § 5.6 reformulée (voir `docs/DOCTRINE_PORTAGE.md`) ; les lignes VL-1 et VL-2 ci-dessus restent vraies pour le *mécanisme* du poste, mais leur mention « le web n'a ni verrou ni inactivité » est périmée depuis le ticket VW.

## Sprint DEP — Saisie des Dépenses à plusieurs lignes (demande du client du 21/10/2026, PRD `docs/prd/depenses-multilignes.md`)

> « Faut revoir le mode de fonctionnement actuel de la Saisie des Dépenses. » Une dépense = un en-tête + N lignes (libellé, compte de charge, montant). Web d'abord, poste ensuite. Questions client DEP-Q1 à DEP-Q8 : voir le PRD § 9 (décisions déjà prises sur recommandation).

### DEP1 ✅ (21/10/2026) Web : schéma, modèle, Action (point de passage unique)
**Objectif :** `expense_lines`, colonnes d'en-tête, conversion des anciennes dépenses, création atomique (en-tête + lignes + écriture + trésorerie), immuabilité, contre-passation par lecture de l'écriture d'origine.
**Web :** migrations (`expense_lines` ; colonnes `payment_mode`, `cost_center_id`, `supplier_id`, `beneficiary`, `created_by`, `category` nullable) puis conversion 1 en-tête = 1 ligne (UUID v5, 628 en repli, journalisée) · `ExpenseLine`, `Expense::lines()` · `SaisieDepenseAction` · `RecordExpenseAccountingEntryAction` (débit par compte, crédit trésorerie).
**Tests (rouges d'abord) :** `DepensesMultilignesTest`, `MigrationDepensesEnLignesTest`. **Mutation :** retirer l'écriture de la transaction ; retirer le regroupement par compte ; retirer l'immuabilité.

### DEP2 ✅ (21/10/2026) Web : modale à lignes dynamiques
`SaisieDepenses` + `saisie-depenses.blade.php` : modale, lignes, total en direct, tableau à détail déplié, filtre « Pièce ». Test `DepensesMultilignesLivewireTest`.

### DEP3 ✅ (21/10/2026) Contrat `/api/sync`
Tirage : `lines`, nouvelles colonnes, `cost_centers`, `chart_of_accounts` pour `view-achats`. Poussoir : absorbeur strict, ancien payload plat converti en 1 ligne, idempotence. Test `SyncDepensesMultilignesTest` ; adaptation des tests de synchronisation existants. **Le serveur est déployé AVANT les postes.**

### DEP4 ✅ (21/10/2026) Poste : Drift v56, dépôt, moteur de synchronisation
Tables `ExpenseLines` et `CostCenters`, colonnes de `Expenses` (dont `ecriture_refus`), palier `from < 56` (transformation locale), `DepensesRepository` (transaction unique, mêmes validations), `SyncEngine` (envoi/absorption des lignes, refus affiché). **Numéro de schéma 56 sur cette branche ; la fusion renumérotera si l'un des paliers 53 (devis), 54 (avoirs) ou 55 (unicité) manque.** Tests `depenses_multilignes_test`, migration v56, cohérence de schéma Laravel ↔ Drift.

### DEP5 ✅ (21/10/2026) Poste : écran et parité
`saisie_depenses_screen.dart` : modale à lignes dynamiques, tableau à détail, mêmes libellés ; garde-fou de parité Blade ↔ Dart. Tests `depenses_multilignes_ecran_test`, `depenses_multilignes_parite_test`.

**Livré le 21/10/2026** (détail, mutations et mesures : `agrierp_laravel/README_SPRINT0.md`, entrée « Ticket DEP1 à DEP5 ») : suite Laravel 2 250 verts, poste 3 191 verts / 17 sautés, `flutter analyze` propre. **Questions client DEP-Q2, Q4 à DEP-Q8 : à confirmer** (PRD § 9) ; DEP-Q1 et DEP-Q3 closes (OUI, § 11). **Numéro de schéma Drift 56 propre à la branche `t-depenses`** : la fusion renumérotera si l'un des paliers 53 (devis), 54 (avoirs) ou 55 (unicité) manque. Non vérifié : base MySQL peuplée, poste Windows réel, Dusk, essai à cinq postes contre le serveur réel.
### DEP6 ✅ (26/10/2026) Centre de coût obligatoire (DEP-Q1 : OUI du client)
Web (modale « Centre de Coût * », message sous le champ), absorbeur strict, poste ancien accepté au centre « Général » (créé par migration et semoir), existant rangé sous « Général » sans réécrire une pièce. Tests `DepenseCentreCoutObligatoireTest`. PRD § 11.1.

### DEP7 ✅ (26/10/2026) Dépense à crédit = dette fournisseur (DEP-Q3 : OUI du client)
`DetteFournisseurService` partagé avec les achats à crédit ; « Règlement * » (Payée comptant / À crédit) ; D charges / C 401 ; `payables.expense_id` ; règlement ⇒ `payee` ; archivage sans règlement ⇒ contre-passation de la charge et de la dette, refusé après règlement (DEP-Q9). Tests `DepenseFournisseurCreditTest`, `…LivewireTest`, `SyncDepenseFournisseurCreditTest`. PRD § 11.2.

### DEP8 ✅ (26/10/2026) Poste : Drift v59, dépôt, modale, absorbeur
`on_credit`, trésorerie nullable (table reconstruite), centre « Général » local ; dépôt et modale identiques au web ; envoi avec `on_credit`. Tests `depenses_a_credit_test`, migration toutes versions. **Numéro 59** (57 devis, 58 archives, 60 modules actifs ailleurs).

### DEP9 ✅ (26/10/2026) Parité Blade ↔ Dart et cohérence de schéma
`depenses_a_credit_parite_test` (libellés, ordre, messages, `libelleReglement` exécuté contre PHP), `SchemaDepensesPosteTest`. **Questions client DEP-Q9 à DEP-Q11 : à confirmer** (PRD § 11.3). Risque : migrer les postes avant d'ouvrir « À crédit ».

## Sprint UNI — Unicité des codes et libellés (demande du client du 21/10/2026 : « que faire pour éviter cela à la longue ? »)

### UNI ✅ (21/10/2026) Codes de bande et libellés de catégorie uniques à la source, sans toucher à l'existant

**Constat.** Le code d'une bande avait un index `unique` exact en base et la validation `unique:` du web, mais : (1) comparaison sensible aux espaces (`AVI-2026-01 ` passait), (2) refus sans le code ni la marche à suivre (« La valeur du champ code existe déjà »), (3) les catégories de produits n'avaient aucune contrainte (libellé libre), (4) aucune détection des doublons déjà présents, (5) la bande refusée à l'envoi ne pouvait pas être renommée (le code était immuable). **Rien n'est supprimé ni renommé automatiquement.**

**Décisions.**
- **Clé de comparaison** `CleUnicite::cle()` (web) / `cleUnicite()` (poste) : casse, accents, espaces autour et doublés ignorés. Comparée en PHP / Dart (volume d'une ferme), pas en SQL (SQLite et MySQL ne s'accordent ni sur les accents ni sur les espaces).
- **Portée : TOUTES les bandes, archivées comprises.** Une bande archivée garde son code, ses fiches et ses ventes ; redonner son code à une nouvelle bande referait deux lignes de même clé dans les rapports. (La restauration BS-Q7 garde son propre refus.)
- **Message** (web, poste, serveur) : « Le code « X » est déjà utilisé par une autre bande (en cours ou archivée) : choisissez un autre code. » ; à l'envoi, le serveur ajoute : « Votre bande est conservée sur ce poste : renommez-la (Élevage > Bandes & Sujets, bouton « Modifier ») puis synchronisez de nouveau. »
- **Renommer = seul assouplissement du code immuable.** Sans lui, « le client renommera lui-même » était impossible. Le code d'une bande se corrige UNIQUEMENT quand il est partagé avec une autre bande (ou, au poste, quand le serveur l'a refusé « déjà utilisé »), vers un code libre ; audit `livestock_lot.renamed`. Un code unique reste immuable (message dédié). Un doublon antérieur ne bloque ni l'archivage, ni la restauration, ni le changement de stade de la bande qui garde son code.
- **Index unique** (migration `2026_10_21_000002_garantir_l_unicite_des_codes_et_libelles`) : `livestock_lots.code` l'avait déjà (exact) ; la migration le rétablit s'il manque et ajoute `product_categories.label`, **seulement si aucun doublon** (même clé que la règle). S'il y en a : `Log::warning` (table, valeurs) et pas d'index ; relancer `php artisan migrate` après correction. Aucune donnée touchée.
- **Catégories de produits** : `ProductCategory` refuse un libellé déjà porté (actives ou non). Aucun écran ne crée de catégorie (créées par le seeder, référentiel tiré par le poste) : le garde-fou protège toute voie future ; les catégories en double déjà présentes ne sont que **détectées** (commande), le poste ne peut pas les renommer (référentiel en lecture seule).
- **Détection** : `php artisan agrierp:doublons` (lecture seule, code de sortie 0) liste bandes et catégories en double, identifiants, lignes liées (fiches, ventes, transferts, sujets ; produits). Alerte **non bloquante** : bandeau « N doublon(s) de code détecté(s) — à renommer » en tête de « Bandes & Sujets », **web ET poste** (article 5 : web d'abord), que le poste voit y compris sur les bandes tirées du serveur. Choisi plutôt qu'une notification : la cloche est alimentée par le serveur, qui ne voit pas les bandes encore hors ligne d'un poste.
- **Poste** : refus AVANT l'écriture, sous le champ « Code Unique de la Bande » (bandes archivées et tirées du serveur comprises) ; code rangé sans espaces ; proposition du prochain code libre (inchangée, désormais sur la même clé) ; refus du serveur affiché mot pour mot sous le code (« Refusée »), la bande saisie est GARDÉE ; « Modifier » ouvre le champ code des bandes à renommer ; la bande repart en file sous le même UUID, le refus périmé est levé.
- **Audit des autres entités** (code / libellé servant de clé) : `livestock_species.code`, `products.sku` (généré), `chart_of_accounts.code`, `fixed_assets.code`, `animals.identifier` : déjà `unique` en base, exacts (insensibles à la casse sous MySQL ; non revérifiés ici). **Corrigé** : clé de ligne `gantt-<code bande>` de Soins & Vaccins (même « Duplicate keys found » que le tableau de bord d'élevage) via l'aide commune `suffixe_doublon.dart`. **Laissé** : noms de clients, fournisseurs, produits (homonymes légitimes, aucune clé de widget dessus) ; unicité de l'identifiant d'un sujet à rendre insensible aux espaces (`Rule::unique` exact) ; catégories de dépenses et autres listes libres non auditées une à une.

**Contrat modifié** (`agrierp_laravel/README_SPRINT0.md`) : `POST /api/sync/push` `livestock_lots` — motif de rejet « code déjà utilisé » avec marche à suivre ; code partagé renommable (même `id`, nouveau `code`).

**Tests (rouges d'abord, mutations tuées).** Web `UniciteCodesTest` (clé, création : pris / casse / espaces / archivée / libre, règle gardant son propre code, point de passage, absorbeur : rejet, casse et espaces, deux postes, rejeu du même UUID, doublon antérieur, renommage ; catégories ; migration avec et sans doublons ; commande ; bandeau) ; poste `unicite_codes_poste_test` (formulaire, proposition, bandes tirées du serveur comptées, renommage, refus du serveur de bout en bout, bandeau, champ code) + `soins_vaccins_test` (Gantt). Mutations tuées : clé exacte (5 rouges), migration sans contrôle de doublons, message d'envoi, garde du point de passage, immuabilité du code non partagé, clé poste sans espaces (8 rouges), reconnaissance du refus, levée du conflit, suffixe du Gantt.
**Mesures (compteurs exacts).** Laravel `--testsuite=Feature` : **2 203 verts** (24 237 assertions ; avec `.env`, `npm run build` et `storage:link`, comme l'exige `CLAUDE.md`) ; poste `flutter analyze` propre, **3 120 verts, 17 sautés** (`flutter test --concurrency=3`).
**Schéma Drift : inchangé** (v52 ; ni 53 ni 54 ni 55 pris).
**Non vérifié :** migration sur une base MySQL réelle peuplée (collation, doublons réels) ; poste Windows réel ; rendu navigateur (Dusk) du bandeau et du champ code.



## Sprint ARC — Corbeille : voir, restaurer, supprimer définitivement (demande du client du 21/10/2026, PRD `docs/prd/archives.md`)

> Demande : « page/screen (web et poste) pour afficher les enregistrements archivés (supprimés) et permettre de les RESTAURER et/ou de les SUPPRIMER DÉFINITIVEMENT ». Le nom du projet est conservé : « Corbeille » (ex-onglet « Restauration » de Paramètres).

### ARC1 ✅ Web : liste de 20 types, recherche/type/période, restauration sous règles, suppression en deux temps
`CorbeilleService` (point de passage UNIQUE page + envoi), `Livewire\Parametres\Corbeille`, journal `corbeille_operations`, `AuditLog corbeille.restored|deleted`. **Défauts trouvés** : une dépense archivée se « restaurait » sans rejouer la contre-passation ni la trésorerie (désormais INTERDIT) ; titres « — » des provendes et absences ; aucun contrôle d'exercice clos ni de code pris ; quatre types absents.
### ARC2 ✅ Contrat `/api/sync` : clé de tirage `corbeille` (page 1, `manage-parametres`), clé d'envoi `corbeille_demandes` (traitée en dernier, idempotente par UUID).
### ARC3 ✅ Poste : Drift **v58** (`corbeille_elements` instantané, `corbeille_demandes` mixte), absorbeur strict, envoi, relance. Bug trouvé par les tests : la garde « rien à envoyer » ignorait la nouvelle table.
### ARC4 ✅ Poste : onglet « Corbeille » de Paramètres Général (même place qu'au web), parité lue par `corbeille_blade_test.dart`.
### ARC5 ✅ Docs (PRD, plan, audit § 12, README_SPRINT0, CLAUDE.md).
### ARC6 ✅ (26/10/2026) « Archivé par » — décision client ARC-Q2 = OUI. Web d'abord : migration `audit_logs.entity_type/entity_id` (nullables, index, rejouable), `AuditLog::record()` accepte l'entité visée (4e paramètre facultatif), tous les chemins d'archivage la renseignent (dont l'envoi du poste : auteur = utilisateur du jeton), colonne « Archivé par » (« — » si inconnu). Poste : `archive_par` dans le tirage `corbeille`, Drift **v63** (61 ventes et 62 rappels réservés), colonne identique. Tests `CorbeilleArchiveParTest` (Laravel) et `corbeille_*_test` (poste).

**Questions au client :** ARC-Q2 close (OUI) ; les autres suivent la recommandation (déjà le comportement livré) ; ARC-Q1 restauration d'une dépense avec re-comptabilisation (recommandé : NON pour l'instant) · ARC-Q2 savoir QUI a archivé (✅ OUI, construit : ARC6) · ARC-Q3 suppression d'un devis/courrier (NON : trou de numérotation) · ARC-Q4 délai avant suppression définitive (NON) · ARC-Q5 écritures contre-passées en consultation (NON) · ARC-Q6 ligne supprimée restée archivée sur les postes tiers (OUI, acceptable).

## Sprint MOD — « Modules Actifs » : activer / désactiver au poste (bug rapporté par le client, 21/10/2026)

### MOD1 ✅ (21/10/2026) Interrupteurs des espèces au poste, envoyés au serveur, jamais écrasés par le tirage

**Bug rapporté.** « En poste, je n'arrive pas à activer / désactiver les Modules Actifs. »

**Cause racine (trois défauts cumulés, aucun ne levait d'erreur).**
1. **Écran** : l'interrupteur du poste n'était qu'une `Icon` (`toggle_on` / `toggle_off`) sans gestionnaire de clic ; la carte disait même « le réglage lui-même se fait sur la surface web ». Aucune condition (droits, hors ligne, exercice) ne le désactivait : il n'existait simplement pas.
2. **Écriture et envoi** : `modules_config` n'était qu'un référentiel descendant, sans `sync_status` ni clé d'envoi ; le serveur comptait tout envoi dans `referentiels_ignored`.
3. **Tirage** : `_absorberModules` supprimait puis réinsérait toute la table à chaque tirage. Même corrigés (1) et (2), une bascule non encore acquittée serait « revenue » toute seule à l'ancienne valeur au cycle suivant.
Le web, lui, n'avait pas de défaut (`ModulesActifs::toggleModule()` écrit `modules_config.is_enabled`, `updated_by`, journal `module.toggled`, toast « Modification appliquée avec succès. ») ; il ne contrôlait ni « au moins un module » ni la comptabilité, et le poste non plus.

**Correction.**
- **Web** : `ModuleConfig::definir()` devient le point d'écriture unique (web et poste, même audit) ; `RecordModulesConfigFromDeviceAction` + clé d'envoi `modules_config` dans `SyncController::push` (droit `manage-modules`, refus par ligne avec motif, espèce inconnue ou valeur illisible refusées, valeur EXPLICITE et non bascule : un envoi rejoué ne rebascule pas), retirée des référentiels ignorés.
- **Poste** : Drift **v60** (`modules_config.sync_status`, `updated_at` ; 57 à 59 réservés, `from < 60` les enjambe) ; interrupteur cliquable (`bascule-module-<code>`), écriture `pending` immédiate, toast du web, icônes rafraîchies ; envoi, acquittement sous le code de l'espèce, refus → conflit avec motif, relance ; absorbeur protecteur (une ligne `pending` / `conflict` n'est jamais écrasée, même pour une espèce absente du tirage) ; compteur « en attente » de la synchronisation. Les écrans d'élevage (cartes de Gestion Élevage, onglets de Suivi Reproduction, Dashboard Élevage, sélecteurs de bande, Registre) relisent `modules_config` à l'ouverture : l'effet est immédiat.
- **Fidélité au Blade (maître)** : sous-titres « Fiches, VMS, catalogue POS liés à cette filière », pastille FUTUR et carte d'information en bleu `info-blue`, mention sans renvoi au web.

**Tests (rouges d'abord, mutations tuées).** `agrierp_laravel/tests/Feature/SyncModulesActifsPosteTest.php` (7) ; `agrierp_flutter/test/modules_actifs_poste_test.dart` : écran (clic, icônes, toast, première bascule sans ligne), dépôt (actives, aucun « au moins un », comptabilité intacte), moteur (envoi, acquittement, refus, bascule refaite pendant l'envoi, tirage périmé, tirage web → poste), parité Blade ↔ Dart (textes, descriptions, espèces, icônes, message), **aller-retour contre le vrai `SyncController` PHP** (poste → serveur → bascule web par le vrai composant Livewire → tirage → poste, et refus du rôle sans `manage-modules`). Mutations : absorbeur sans protection (5 rouges), bascule non marquée `pending` (8 rouges).

**Décision à confirmer par le client.** Seul l'administrateur (`manage-modules`) peut basculer un module, au poste comme au web ; un autre compte voit sa bascule refusée avec son motif (jamais perdue).
**Non vérifié :** poste Windows réel ; essai à plusieurs postes (`outils/essai_multipostes.sh`, MariaDB).

## Sprint POP — « Rappels du jour » : fenêtre à l'ouverture du web et du poste (demande du client du 26/10/2026, PRD `docs/prd/popup-rappels.md`)

> « Quand on ouvre chaque fois le poste ou le web, la notification popup doit se déclencher pour afficher les rappels VMS, soins et vaccinations. » Web maître, poste identique. **Aucune migration Drift** (le palier 62 reste libre).

### POP1 ✅ (26/10/2026) Web : `RappelsDuJourService` (règle R-RAPPELS-01), composant `Shared\RappelsDuJour`, ouverture à la connexion et une fois par session de navigateur, « Ne plus afficher aujourd'hui »
### POP2 ✅ (26/10/2026) Poste : `RappelsDuJourRepository` (calcul local, mêmes sources et même tri), préférence du jour au coffre, fenêtre
### POP3 ✅ (26/10/2026) Poste : déclenchement par `PorteSession` (lancement et connexion, pas les déverrouillages), droits, silence sur erreur
### POP4 ✅ (26/10/2026) Parité Blade ↔ Dart des libellés, parité exécutée contre le PHP du serveur, docs (AUDIT, CLAUDE.md)

**Questions au client (non tranchées) :** POP-Q1 infirmerie sans date prévue (recommandé : pas de rappel) · POP-Q2 « vaccin à renouveler » = barème prophylactique · POP-Q3 fenêtre à chaque déverrouillage (recommandé : non) · POP-Q4 rémanences hors horizon N · POP-Q5 cloche et espèces désactivées.

## Sprint VTE — « Je n'arrive pas à enregistrer de ventes » (bug client en production, 26/10/2026)

### VTE-1 ✅ (26/10/2026) Le client à la caisse du poste : comptant toujours possible, crédit avec client connu, client créable à la volée, aucun échec silencieux

**Cause racine (poste).** `agrierp_flutter/lib/features/ventes/caisse_screen.dart` figeait la caisse dans un état d'avant F0.55 : le champ « Client » était un `TextField(enabled: false)` (« Client Anonyme », « Fichier client non synchronisé sur ce poste ») et « Crédit / À terme » avait été retiré de la liste des règlements (écarts assumés n° 1 et 2 du docblock, écrits quand la table `customers` ne faisait pas partie du contrat). Depuis F0.55 le poste lit, crée et envoie ses clients : ces deux écarts n'avaient plus de raison d'être, mais restaient. Conséquences : aucune vente à un client nommé ni à crédit (restaurants, revendeurs, à 30 jours) n'était possible au poste ; tout le chiffre « à terme » devait se saisir au web. Et le défaut qui fait dire « rien ne se passe » : `_valider()` ne rattrapait que `VenteRefusee` — toute autre erreur (base verrouillée, disque plein, donnée inattendue) remontait à Flutter sans un mot à l'écran.
**Ce qui n'était PAS la cause (mesuré, tests verts avant correction).** Exercice de saisie / N+1 (la vente du jour ne subit aucun garde), unicité des codes de bande (la caisse ne lit pas le code), dépenses multi-lignes / centre de coût, Drift v53–v60 (migrations comparées à un schéma neuf par `migration_toutes_versions_test`), verrou PIN, GrilleKpi, rémanence, stock insuffisant (alerte seule), bande obligatoire (message dit pourquoi). Vente comptant sans client, avec et sans bande : acceptée par le VRAI `SyncController` (banc `ventes_sans_client_parite_php_test`).
**Cause racine (web et serveur).** Une vente à crédit (ou « Déduire de l'avance ») SANS client passait : l'écriture débitait 411 mais `Receivable` n'était créée que `if ($sale->customer_id)` — une créance envers personne, sans aucun message (`PosInterface::validateSale`, `SyncController::pushSales`). Et un `customer_id` inconnu du serveur rejetait la vente avec le texte générique « ne correspond à aucun enregistrement connu du serveur ».

**Règle construite (web = maître, poste et serveur alignés).**
- Comptant : toujours possible, sans client (« Client Anonyme »), ou avec un client choisi même pas encore synchronisé (créé au poste, ou pas encore tiré). Le client part AVANT la vente dans l'envoi (`customers` précède `sales` dans `SyncEngine.ordreDuServeur` comme au serveur).
- Crédit : exige un client connu de ce poste. Refus motivé AVANT tout effet, panier conservé, message sous le champ ET en bandeau, texte identique au web : « Une vente à crédit exige un client : choisissez-le dans la liste ou créez-le avec le bouton « + ». » Le bouton « + » crée le client à la volée (nom, téléphone comme `saveNewClient()`), par l'unique écrivain du fichier client (`ClientsCreancesRepository`), en attente d'envoi.
- « Déduire de l'avance » : web et serveur exigent aussi un client ; reste retiré de la liste du poste (le web ne passe aucune écriture pour ce mode ; l'imputation d'une avance est un geste à part, F0.73).
- Serveur, client inconnu : la vente n'est PAS rattachée au comptoir en silence (cela fausserait la traçabilité de l'acheteur, base d'un rappel sanitaire) et n'emporte pas l'envoi : refus motivé de CETTE vente, lisible (« Client inconnu du serveur : … Envoyez d'abord le client, puis relancez la vente. »), vente en `conflict` à l'écran Synchronisation, RELANÇABLE (`_relancerVente`). Crédit/avance sans client reçu d'un poste ancien : « Une vente à crédit exige un client. », refus de cette vente seule.
- Aucun échec silencieux : toute erreur inattendue à la validation s'affiche (« Vente NON enregistrée : … Le panier est conservé »), le bouton se libère.

**Tests (rouges d'abord, mutations tuées).** Laravel `VenteSansClientTest` (8). Poste `vente_client_poste_test` (14 : dépôt et écran), `ventes_sans_client_parite_php_test` (5 : VRAI `SyncController`, client créé au poste dans le même envoi, client inconnu, poste ancien). Mutations : règle du crédit retirée au dépôt (3 rouges), `catch` générique retiré (1 rouge), règle serveur (rouge avant correction).
**Non vérifié.** Poste Windows réel ; MariaDB réelle ; la cause racine n'a pas pu être reproduite sur la base de production du client : elle est établie par lecture du code (champ désactivé, mode retiré) et par l'impossibilité, avant correction, de saisir un client ou un crédit au poste. **Reste à confirmer avec le client** : « Déduire de l'avance » au poste (VTE-Q1), plafond de crédit refusé à la caisse (le web ne le contrôle pas non plus, VTE-Q2).

## Sprint RH — CRUD RH au poste : Registre Employés, Registre Stagiaires, Feuille de Pointage, Gestion de la Paie (demande du client du 27/10/2026, PRD `docs/prd/rh-crud-poste.md`)

**Pourquoi le poste n'avait pas ce CRUD.** Au ticket F0.55, `employees` et `internships` avaient été classés RÉFÉRENTIELS (« le serveur gagne, tout envoi ignoré », `referentiels_ignored`) : le poste ne pouvait qu'en lire une copie. La feuille de pointage ne savait que CRÉER un pointage du jour ; la paie était à « — » sur ses quatre cartes et six colonnes (doctrine F0.55 : « le poste ne calcule pas une paie »). Le web, lui, écrivait tout. Article 5 de la doctrine : la vue Blade est le maître, le poste reprend la logique à 100 %.

### RH-1 ✅ (27/10/2026) Registre Employés : créer, modifier, archiver au poste
Serveur : `App\Actions\SaisieEmployeAction` (point de passage unique de `Livewire\RH\RegistreEmployes` ET de `SyncController::pushEmployees`, `manage-rh`) ; mêmes règles (prénom, nom, fonction, date d'embauche, salaire ≥ 0, statut `actif|conge|suspendu`), un employé archivé ne se modifie plus (« Cet employé est archivé : il ne peut plus être modifié. »), ligne identique acquittée sans écriture, audit. Tirage : tous les employés avec `is_active` et `updated_at`. Poste : `employees` devient MIXTE (Drift **v67**, `SyncColumns`, `is_active`), `_absorberEmployes` STRICT (n'écrase jamais `pending`/`conflict`), modale « Nouvel Employé » / « Modifier » / « Archiver » (`PersonnelRepository.enregistrerEmploye` / `archiverEmploye`).

### RH-2 ✅ (27/10/2026) Registre Stagiaires : inscription, frais réglés, absences
Serveur : `SaisieStagiaireAction` (`pushInternships`, `pushInternshipAbsences`) ; nouvelle clé de tirage `internship_absences` (`view-rh`). Poste : `internships` MIXTE, nouvelle table `internship_absences` (noter / archiver une absence, modale « Absences »), modale « Nouveau Stagiaire » avec « Frais réglés ».

### RH-3 ✅ (27/10/2026) Feuille de Pointage : date, modification, archivage
Serveur : `pushAttendance` accepte `is_active` (archivage, audit `attendance.archived`) ; le tirage sert les pointages archivés (60 jours) avec `is_active`. Poste : modale avec « Date * » (≤ aujourd'hui), « Heure d'arrivée * » (`HH:mm`), « Modifier », « Archiver » ; un pointage archivé ne compte plus (cartes, absences de la paie). Mutation : inverser `is_active` dans l'absorbeur fait rougir `personnel_crud_test`.

### RH-4 ✅ (27/10/2026) Gestion de la Paie : calcul local identique au web, « Valider le règlement » = une DEMANDE
Serveur : `App\Services\ReglementPaieService` (point de passage unique de `GestionPaie::validerReglement` ET de `pushPayslipRequests`) : bulletin + trésorerie + écriture (`RecordPayrollAccountingEntryAction`) + audit dans UNE transaction, exercice clos / employé archivé refusés AVANT d'écrire (motif « Règlement refusé : … »), idempotent (bulletin déjà passé = acquitté). Tirage : `income_tax_brackets` (`view-rh`), `company_settings` + cinq taux de paie, `payslips` avec ses colonnes RH pour `view-rh` seulement. Poste : `CalculPaie` (`lib/features/rh/calcul_paie.dart`) = transposition de `PayrollCalculationService`, **parité EXÉCUTÉE contre le vrai PHP** (`test/paie_parite_php_test.dart`, exemple du PRD + 20 cas) ; quatre cartes calculées comme `getKpisProperty()` ; neuf colonnes de la maquette (Ret. ITS et charges patronales en info-bulle du net) ; `payslip_requests` (demande sans montant, `conflict` motivé et relançable) ; bulletin reçu = « Réglé » avec SES montants. Correction trouvée par les tests : l'exemple « à la main » du PRD donnait 23 704,62 de charges patronales (21,4 % du dû) — le PHP somme les quatre parts ARRONDIES : 23 704,61 ; et la garde « rien à envoyer » du moteur ignorait les quatre nouvelles tables (même piège qu'ARC3).

**Tests.** Laravel : `SyncRhCrudTest` (12), `SyncPaieDemandeTest` (7), `SyncPointageTest` (10) — suite Feature 2 659 verts. Poste : `personnel_crud_test` (dépôt, envoi, acquit, refus, purge), `paie_parite_php_test`, `personnel_stages_test` réécrit, `migration_toutes_versions_test` (67), `perimetre_tirage_test`, garde-fous de libellés (`plafondManquesMasques` 197 → 189 : les libellés de modale sont portés).
**Non vérifié.** Poste Windows réel ; MariaDB réelle.

### RH-Q1 / RH-Q2 / RH-Q3 ✅ (27/10/2026) Décisions du client appliquées
- **RH-Q1 = OUI** : filtre « Archivé » au web (`RegistreEmployes::getEmployeesProperty`, option du Blade, ligne « Archivé » en « Lecture seule ») puis au poste (`DonneesPersonnel.employesArchives` / `employesFiltres`, liste `employes-filtre`, clé `employe-lecture-seule-$i`). Tests : `SyncRhCrudTest::test_le_filtre_archive…`, `personnel_stages_test` « RH-Q1 », `personnel_crud_test` « RH-Q1 ».
- **RH-Q2 = déjà validé** : note retirée de `PayrollCalculationService`.
- **RH-Q3 = NE PAS LIMITER** : `attendance_records` passe de la page 1 bornée à 60 jours à une FAMILLE PAGINÉE (`famillesPaginees`, curseur `updated_at`, `id`, `enJson` avec le jour en `Y-m-d`), servie en entier ; le poste compte les absences de tout mois (`SyncPointageTest::test_a_pointing_older_than_sixty_days…`, `personnel_crud_test` « RH-Q3 »).

## Sprint CRUD-P — « Le poste doit avoir toutes les fonctions actives » (demande du client du 27/10/2026, inventaire `docs/INVENTAIRE_LECTURE_SEULE_POSTE.md`)

### UT-1 ✅ (27/10/2026) Gestion des Utilisateurs au poste : créer, modifier, archiver, réactiver (même logique que le web)
Constat du client : « le poste ne crée pas les utilisateurs or normalement il le devrait ». Web d'abord : `App\Actions\SaisieUtilisateurAction` (point de passage unique de `GestionUtilisateurs::saveUser/archiveUser/reactivateUser` ET de `SyncController::pushUsers`, droit `manage-users`) : règles du web (identifiant 3–50 sans arobase, unicité, rôle existant, `Password::defaults()` 14.65), effets (rôle, jetons révoqués à l'archivage, audit `user.*`), messages ; le propre compte de l'auteur ne s'archive pas ; `users` sort de `referentiels_ignored` ; le tirage sert `updated_at`, jamais le mot de passe. Poste : Drift **v68** (`utilisateurs` MIXTE par reconstruction `_utilisateursMixtes`), absorbeur STRICT (`_fusionnerMixte`), **mot de passe au COFFRE du système** (`flutter_secure_storage`, clé `agrierp.utilisateur.mdp.<id>`) jusqu'à l'acquit — jamais en base, part UNE fois ; `ParametresGenerauxRepository.enregistrerUtilisateur` / `archiverUtilisateur` / `reactiverUtilisateur` (règles et messages de `lang/fr/validation.php`) ; onglet « Gestion Utilisateurs » : « Nouvel Utilisateur », modale du Blade (Nom complet, Nom d'utilisateur, Email, Rôle, Mot de passe / Nouveau mot de passe), « Modifier », « Archiver » (confirmation) / « Réactiver », pastilles « Pas encore envoyé » / « Refusé ». Tests : `SyncUtilisateursTest` (14), `utilisateurs_poste_test` (dépôt, moteur, écran), garde-fous (`migration_toutes_versions` 68, `compteur_attente` 38, `ecrivain_unique`, `fidelite_libelles` : exemptions « création de compte réservée au web » levées, plafond 189 → 177).
**Non porté (en ligne, ticket PA-1)** : « Déconnecter Toutes les Sessions ». **Non vérifié** : poste Windows réel (coffre `flutter_secure_storage` sur Windows : même mécanisme que le PIN VL-1).

### PA-1…PA-8 et CP-5 ✅ (28/10/2026)
Réglages par requêtes génériques `settings_requests` ({id, kind, payload}; kinds entreprise, bareme_its, mode_paiement, role, sms) rejouées par des services uniques partagés avec Livewire (BaremeItsService, EntrepriseService, ModesPaiementService, RoleService, SmsConfigService). Secrets SMS dans le coffre système (jamais en base, jamais tirés). PA-1/5/6 et le test SMS sont en ligne (`AdministrationEnLigneController`). CP-5 : import de relevé idempotent (`import_id`), lettrage et rapprochement au poste, parité PHP. Limites : logo/favicon (PA-3) et export PDF du rapprochement non portés. Non vérifié sur Windows : ouverture d'URL, sélecteur de fichier, téléversement, dossier de téléchargement des sauvegardes.

### AUT-1 à AUT-4 ✅ (28/10/2026) — « le poste doit rester pleinement autonome du web »
- **AUT-1** : l'export PDF du rapprochement bancaire se construit au poste (`DocumentsComptabilite.rapprochement`, mêmes mots que `exports.rapprochement-bancaire`).
- **AUT-2** : logo et favicon (PA-3) gardés sur le poste (`FichiersEntreprise`, dossier `entreprise/`), envoyés avec la demande `entreprise` (`logoB64`, `faviconB64`, limites du web 2 Mo / 500 Ko, rangés par `EntrepriseService::fichiersDepuisBase64`) et téléchargés quand le chemin servi par le web change (`GET /api/sync/company-file/{logo|favicon}`). Les PDF du poste emploient le logo choisi (PNG ou JPEG).
- **AUT-3** : le SMS disparaît (web d'abord : `Integrations`, `SmsService`, `SmsConfigService`, kind `sms`, test SMS supprimés). Canaux de relance : WhatsApp, e-mail, **appel** (`tel:`), courrier (migration `2026_10_28_000004`, Drift **v78** `customer_reminders.already_sent`). L'e-mail part du SMTP du poste (`EnvoiEmail`) AVANT l'écriture de la relance (refus = aucune trace) ; le serveur reçoit `already_sent` et ne renvoie rien.
- **AUT-4** : `AdministrationLocale` remplace `AdministrationEnLigne` : sauvegarde complète (`VACUUM INTO`, 30 jours), export de module en JSON, import d'un module depuis une sauvegarde complète (lignes reprises `pending`), restauration complète installée au lancement suivant (`agrierp.restauration`), déconnexion des autres comptes du poste (PIN et réglages effacés au coffre), fiche « Ce poste » (saisies en attente, refus, dernière synchro). Les routes `/api/parametres/*` de `AdministrationEnLigneController` restent côté web.

### Tickets restants (ordre proposé, voir l'inventaire § 10)
VC-1 encaisser une créance + relance (`receivables`, `customer_reminders`) · AC-1 bons de commande · ST-1 archiver un produit · ST-2 seuils d'alerte · CP-1 plan comptable · CP-2 journal manuel · PA-3 données de l'entreprise · PA-4 modes de paiement (comptes, virement) · VC-2 relances · VC-3 profil client · PA-2 rôles & permissions · PA-7 barème ITS · AC-2 « + fournisseur / + produit » dans l'achat · AC-3 justificatifs synchronisés · AC-4 actions des dettes · ~~VC-4 modifier / archiver une avance~~ ✅ · VC-5 relance MeCeF (en ligne) · ~~CP-4 clôture d'exercice~~ ✅ · ~~EL-1 transformation~~ ✅ (voir plus bas).

## DES-1 ✅ (27/10/2026) La désinstallation supprime la base locale (décision du client)

Diagnostic du client : « la désinstallation implique la suppression de la base ». Jusqu'ici `agrierp.iss` laissait la base dans le profil Windows (une réinstallation retrouvait les saisies non envoyées ; c'est aussi l'ancienne base qui bloquait l'ouverture avant la correction de la migration du 27/10). Désormais : `[UninstallDelete] filesandordirs` sur `{userappdata}\bj.olouwachegoun\agrierp` (base, `demarrage.log`, justificatifs locaux) et `InitializeUninstall` qui annonce la perte des saisies HORS LIGNE non synchronisées et demande confirmation (« Non » annule la désinstallation). Une mise à jour ne touche à rien. Non touché : le coffre du système (PIN, mots de passe de comptes en attente), inoffensif orphelin. Test : `environnement_test` « DES-1 ». **Non vérifié** : exécution réelle sur Windows (Inno Setup absent ici) — à essayer : désinstaller, vérifier la disparition du dossier, réinstaller, poste neuf.

### VC-1 ✅ (28/10/2026) Encaisser une créance client au poste (« Enregistrer un Recouvrement »)
Web d'abord : `App\Services\CustomerSettlementService::encaisser()` devient le point de passage unique de `SuiviDettes::confirmPayment`, `ProfileClient::confirmRegularisation` (deux copies qui avaient divergé) ET de `SyncController::pushReceivablePayments` : créance (une créance précise, ou le solde du client en FIFO), trésorerie (deux livres), écriture D 5xx / C 411 et audit dans UNE transaction ; seule la PART IMPUTÉE entre en caisse (la fiche client encaissait jusqu'ici le montant saisi en entier : trop-perçu fantôme) ; créance soldée → `status = soldee` ; exercice clos refusé avec son motif, rien d'écrit. Table `receivable_payments` (idempotence par l'UUID du poste, comme `supplier_payments`), droit `manage-ventes`, traitée après ventes, avances et imputations. Poste : Drift **v69** (`receivable_payments`, envoyée jamais tirée), `ClientsCreancesRepository.encaisserCreance` (refus reproduits avant d'écrire, soldes NETS des encaissements ET des imputations en attente), moteur (envoi, acquit, `conflict` relançable), modale `recouvrement_modale.dart` (« Enregistrer un Recouvrement », « Valider le Règlement », aperçu « Nouveau Solde Dû »), bouton « Ajouter un Recouvrement » (en-tête, choix de la créance) et icône par ligne. Tests : `SyncEncaissementCreanceTest` (9), `encaissement_creance_test` (9) ; garde-fous (compteur 39, écrivain unique, migration 69, périmètre, libellés 177 → 173). **Non vérifié** : poste Windows réel. **Non porté (VC-2/VC-3)** : « Relancer » et le règlement global FIFO de la fiche client.

### VC-2 ✅ (28/10/2026) Relances clients au poste (e-mail, WhatsApp, SMS, relance rapide)
Web d'abord : `App\Services\RelanceClientService` (`relancer`, `journaliser`) devient le point de passage unique de `RelancesClients` (mail, SMS, journal WhatsApp/courrier), `SuiviDettes::sendReminder` ET de `SyncController::pushCustomerReminders` (clé `customer_reminders`, droit `manage-ventes`). Une relance est un FAIT : le poste écrit `customer_reminders` (Drift **v70**, table mixte `SyncColumns`, `pending` puis acquittée) ; le serveur envoie le mail ou le SMS et journalise. WhatsApp ouvre `wa.me` côté poste (`ouvreur_url.dart`) et écrit la trace. Les trois modèles de message sont ceux du web et modifiables pour l'envoi en cours. Fusion de référentiels : `customer_reminders.customer_id` ; réinitialisation classée. Tests : `SyncRelancesClientsTest` (Laravel), `relances_poste_test.dart`, gardes `compteur_attente_test` (40 tables envoyées), `ecrivain_unique_test`, `migration_toutes_versions_test` (v70).

### VC-3 ✅ (28/10/2026) Profil Client au poste
Sous-page « Profil Client » (`profil_client_page.dart`, bouton œil de la liste des clients, « Retour ») : initiales, nom, téléphone, « Solde Global Dû » (somme des soldes NETS), barre de limite de crédit, « Modifier la fiche », « Enregistrer un règlement » (solde GLOBAL, imputé aux plus anciennes créances d'abord : `encaisserSolde`, même modale que VC-1 en mode global), « Envoyer une relance rapide » (WhatsApp, sans créance visée), et quatre onglets Ventes · Créances (« Régler ») · Avances & Acomptes · Relances. Aucun nouveau schéma : réutilise `receivable_payments` et `customer_reminders`. Tests : `profil_client_test.dart` (8).

### AC-1 ✅ (28/10/2026) Bons de commande au poste (« Générer le Bon », « Valider la réception », impression)
Web d'abord : `App\Actions\SaisieBonCommandeAction` (saisie, idempotente par UUID du poste) et `App\Services\ReceptionBonCommandeService` (réception : lignes du BON, prix estimé devenu prix réel, dette entière, écriture D 601 + 445 / C 401, bon `recu`) deviennent les points de passage uniques de `BonsCommande` ET du push (`pushPurchaseOrders`, droit `manage-achats`, avant les achats). Le poste n'écrit jamais le statut du bon : la RÉCEPTION est un ACHAT relié au bon (`purchase_order_id`, crédit, aucun règlement) que `pushPurchases` rejoue par le service ; un bon déjà reçu rejette CETTE réception avec son motif. Drift **v71** : `purchase_orders` MIXTE (reconstruction), `purchase_order_lines` (lignes tirées DANS l'entrée `purchase_orders`), `purchases.purchase_order_id`. Écran d'après le Blade : formulaire (fournisseur, livraison attendue, produit proposé au prix minimal, quantité entière, P.U. estimé), panier, total estimé, rappel Stocks, tableau « Bons de commande émis » (statuts du Blade, « Réception en attente », motifs de refus), impression du bon, modale « Valider la réception ». Tests : `SyncBonsCommandeTest` (Laravel), `bons_commande_poste_test.dart`.

### AC-2 ✅ (28/10/2026) « + fournisseur » et « + produit » dans l'achat
Boutons du Blade (`person_add`, `add_box`) et leurs deux modales (« Nouveau Fournisseur » : raison sociale, téléphone ; « Nouveau Produit » : nom, catégorie, unité « u », tarification à compléter au Catalogue), écrites EN LOCAL par les dépôts propriétaires, puis la fiche créée est sélectionnée. ⚠️ Le serveur exige une catégorie de fournisseur à l'envoi : le web (qui n'en posait pas) et le poste posent « Autre ». Tests : `achats_creation_rapide_test.dart`, `SyncBonsCommandeTest::test_les_creations_a_la_volee…`.

### AC-3 ✅ (28/10/2026) Justificatifs synchronisés
Le web ne reliait pas le justificatif d'un achat à l'achat et n'affichait ceux des dépenses nulle part. Web d'abord : `purchases.receipt_path`, `App\Services\JustificatifService` (rattache, remplace, lit sur le disque privé), route authentifiée `justificatifs.show` (`view-achats`), icône « pièce justificative » dans « Liste d'Achats » et « Saisie des Dépenses », formats jpg/png/pdf, 5 Mo. Synchronisation : `POST /api/sync/receipts` (multipart `table`, `id`, `file`; droit `manage-achats`; idempotent, un renvoi remplace) appelé par le moteur APRÈS l'acquittement de l'enregistrement ; Drift **v72** `receipt_sent` (achats et dépenses) ; refus définitif (422) et fichier disparu signalés sans réessai, 404 et pannes réessayés. Le poste joint désormais un fichier à l'achat (cadre « Associer une photo du reçu »). Le poste ne LIT pas encore les pièces déposées au web. Tests : `JustificatifsSynchronisesTest`, `justificatifs_poste_test.dart`.

### AC-4 ✅ (28/10/2026) Colonne « Actions » de « Dettes Fournisseurs »
Le web n'avait pas de colonne Actions et le poste une icône inerte. Web d'abord : « Régler » par ligne (absent d'une dette soldée), qui ouvre la modale sur le fournisseur de la ligne ; même bouton au poste. Tests : `DettesFournisseursActionsTest`, `fournisseurs_test.dart`.

### ST-1 ✅ (28/10/2026) Archiver un produit au poste
Web d'abord : `ProductCatalogService::archiver` (inactif, trace `product.archived`, idempotent) devient le point de passage de `CatalogueProduits::archive` ET de l'envoi du poste : `pushProducts` accepte `is_active` (règle propre à l'envoi) et, sur `false`, met la fiche à jour puis l'archive ; `true` ne réactive jamais. Poste : `ProduitsRepository.archiver` (fiche `pending`, rien d'effacé, stock et prix intacts), `is_active` dans l'envoi de la fiche, icônes « modifier / archiver » sur la carte ET la liste, modale « Confirmer l'archivage » du Blade. Tests : `ApiProduitsTest` (3 nouveaux), `produits_archive_seuil_test.dart`.

### ST-2 ✅ (28/10/2026) Seuils d'alerte au poste
Le crayon inerte de l'onglet « Seuils d'Alerte » ouvre « Configurer un Seuil » (« Seuil d'Alerte * », entier de 0 ou plus, mêmes refus que `SeuilsAlerte::saveThreshold`) ; `ProduitsRepository.definirSeuil` écrit `alert_threshold` (fiche `pending`), le serveur l'applique par la modification d'un produit. Aucun changement de schéma.

### CP-1 ✅ (28/10/2026) Plan comptable au poste (Nouveau Compte, Modifier, Archiver)
Web d'abord : `App\Services\PlanComptableService` (créer, modifier, archiver ; numéro unique, intitulé, classe 1 à 9, archivage refusé si une écriture cite le compte) devient le point de passage de `Comptabilite\PlanComptable` ET de `SyncController::pushChartOfAccounts` (clé `chart_of_accounts`, droit `manage-comptabilite`, traitée AVANT les dépenses). Drift **v73** : `chart_of_accounts` MIXTE (reconstruction `_planComptableMixte`, défauts « serveur / synced » pour que tout ce qui descend reste acquitté) + `is_active` ; absorbeur strict (un compte local `pending` / `conflict` n'est ni écrasé ni retiré, un identifiant servi deux fois refuse tout le tirage). Écran : « Nouveau Compte », colonne « Classe » en toutes lettres (« 6 - Charges », aussi dans le PDF du plan, comme le web), icônes modifier / archiver, modales du Blade, motif du web quand le compte est utilisé. Les sélecteurs de comptes de charge et la recherche globale ne proposent plus un compte archivé. Tests : `SyncPlanComptableTest` (Laravel), `plan_comptable_poste_test.dart`.

### CP-2 ✅ (28/10/2026) Écriture manuelle (« Saisie d'Écriture ») au poste
Web d'abord : `App\Actions\SaisieEcritureManuelleAction` (créer, modifier, archiver ; débit ≠ crédit, mois non clôturé, écriture non verrouillée, exercice ouvert, via `AccountingEntryService`) devient le point de passage de `JournalComptable` ET de `SyncController::pushManualEntryRequests` (clé `manual_entry_requests`, droit `manage-comptabilite`, après le plan comptable). ⚠️ Le poste n'écrit JAMAIS une écriture : il écrit la DEMANDE (Drift **v74**, `manual_entry_requests`, mixte, envoyée) ; le serveur la joue avec les refus du web, attribue `OD-AAAA-NNNN` et l'écriture redescend au tirage de confirmation ; l'UUID de la demande est le `source_id` de l'écriture créée (rejeu sans doublon). Écran : « Saisie d'Écriture » / « Modifier l'Écriture » (modale du Blade), icônes modifier / archiver, cadenas d'une écriture verrouillée, liste des demandes « en attente d'envoi » ou « refusées » avec leur motif, mention « la saisie reste sur le web » retirée. ⚠️ Écart de sûreté assumé : le web laisse « modifier » une écriture à plus de deux lignes (il la réduirait à deux) ; le poste ne retouche que les écritures à un débit et un crédit. Tests : `SyncEcrituresManuellesTest`, `ecritures_manuelles_poste_test.dart`.

### EL-1 ✅ (28/10/2026) Transformation : reliée au menu web, puis portée au poste (décision client : « OUI »)
Web d'abord : la route `/transformation` (`elevage.transformation`, `view-elevage`) n'était reliée nulle part ; l'entrée « Transformation » (`restaurant`, `wire:navigate`, sous `@can('view-elevage')`) rejoint le groupe « PRODUCTION ÉLEVAGE & SOINS » de `layouts/app.blade.php`, après « Soins et vaccins ». La règle de `TransformationForm::validateTransformation()` devient `App\Actions\SaisieTransformationAction` (point de passage unique, partagé avec `SyncController::pushTransformations`) : mêmes verrous (`OrdreDesVerrous::stock`), même vente sur la fiche du jour (`RecordSaleOnFicheElevageAction`), même `AdjustStockAction`, même audit `transformation.recorded` ; l'effectif est relu SOUS VERROU ; un exercice clos qui couvre le jour saisi (ou le jour même, où entre le stock) refuse la transformation sous la date (motif R4) — règle nouvelle au web, qui ne la jugeait pas. Idempotence par l'UUID du poste (`$t->id = $uuid`) : un identifiant connu est acquitté sans rien rejouer. Envoi : clé `transformations` (droit `manage-elevage`, après les fiches et les transferts) ; tirage : `transformations` (`view-elevage`, famille paginée, jour servi en `Y-m-d`). Les motifs de refus sont ceux de `lang/fr/validation.php` et de l'action. Garde : `SyncTransformationsTest` ; `OrdreDesVerrousTest` lit désormais l'action.
Poste : Drift **v79** (`transformations`, mixte : saisie au poste ET tirée ; absorbeur STRICT qui n'écrase jamais une ligne `pending` / `conflict` ; une bande ou un produit inconnu n'est pas un refus, c'est un historique), `TransformationRepository` (UN SEUL écrivain ; refus AVANT d'écrire, mots pour mots ceux du web ; **le poste n'écrit que le fait** — jamais l'effectif, la fiche ni le stock, que le serveur rejoue et que le tirage de confirmation rapporte ; l'effectif proposé déduit seulement les sujets des transformations de ce poste pas encore parties), `SyncEngine` (envoi, acquittement, relance du conflit, tirage de confirmation), écran `transformation_screen.dart` fidèle au Blade (en-tête, trois cartes dont « Valeur Stock Produit Fini » en attente, formulaire à 55 %, « Impact Automatique Prévisualisé » à 45 %, historique des 20 dernières), entrée de menu et rôle (`transformation.html`, déjà dans la liste de l'animalier de `RBAC_PAGE_MAP`). Tests : `transformation_poste_test` (dépôt, moteur, écran, libellés lus dans le Blade), `transformation_parite_php_test` (parité exécutée des refus contre le vrai PHP, mutation vérifiée) et les gardes mises à jour (`compteur_attente`, `ecrivain_unique`, `perimetre_tirage`, `conformite_portage`, `migration_toutes_versions`, `barre_laterale`, `permissions_poste`, `chassis_web`).

### VC-4 ✅ (28/10/2026) Modifier et archiver une avance client au poste (« Historique des Avances »)
Décision du client : « OUI LE POSTE DOIT LE FAIRE » — les décisions D4/D5 du ticket 15.19 (« le poste ne modifie ni n'archive une avance ») sont REVUES. Web d'abord : `CustomerAdvanceService::modifier` / `archiver` existaient déjà et servent la page ; ajout de `appliquerDuPoste()` (ligne CONNUE : modification client / montant / date avec les mêmes refus que `modifier()`, ou archivage `is_active: false` avec ceux d'`archiver()` ; ligne identique ou avance déjà archivée = acquittement sans écriture ; jamais de réactivation ; contrôle sous verrou), appelé par `SyncController::pushCustomerAdvances` (id connu = modification/archivage, inconnu = réception comme avant ; `treasury_account_id` devient facultatif pour une ligne connue ; archiver une ligne inconnue est refusé sans la créer). `modifier()` refuse désormais une avance archivée (« Cette avance est archivée : elle ne peut plus être modifiée. »). `lang/fr/validation.php` : attribut `advanceDate` → « date ».
Poste : aucune colonne nouvelle (`is_active` existait ; pas de palier Drift, `schemaVersion` reste 79). `ClientsCreancesRepository.modifierAvance` / `archiverAvance` (refus AVANT d'écrire, mêmes motifs que le web, rangés par champ dans `SaisieAvanceRefusee` ; **figée = entamée (`amount_used` servi OU imputation en attente) ou comptabilisée (compte de trésorerie)** ; le reste à imputer est NET des imputations en attente ; saisie identique non réécrite ; la ligne repasse en `pending`), `_avanceEnJson` envoie `is_active`, relance du conflit déjà câblée. Écran : crayon « Modifier » (modale « Modifier l'Avance » : Client, Montant grisé avec sa note, Date bornée par l'exercice ouvert ; toasts « Avance modifiée avec succès. » / erreur du service), « Imputer », « Archiver » (« Confirmer l'archivage » au texte du web ; toast d'avertissement « Avance archivée avec succès. »). Une avance archivée n'est plus listée. Colonne « Actions » élargie.
Tests : `SyncAvancesModifierArchiverTest` (Laravel, 11), `avances_modifier_archiver_poste_test.dart` (dépôt, moteur, écran), `avances_modifier_archiver_parite_php_test.dart` (le vrai service PHP et le dépôt du poste, mêmes cas, mêmes messages sous les mêmes champs).
Limite assumée : une toute nouvelle avance (compte de trésorerie posé) est figée dès sa saisie, comme au web ; le web ne refuse pas une modification en exercice clos (la date d'une avance comptabilisée est de toute façon figée), le poste non plus.

### CP-4 ✅ (28/10/2026) Clôture d'exercice au poste (périodes, exercice, ouverture)
Décision du client : « OUI LE POSTE DOIT LE FAIRE » — la règle « fiscal_years jamais synchronisée » est REVUE : désormais **demandes rejouées par le serveur ; jamais d'écriture directe de `fiscal_years` ni de `periodic_closures` par le poste**. Web d'abord : `App\Services\ClotureExerciceService` est le point de passage unique de `Comptabilite\ClotureExercice` (clôturer / déclôturer un mois, étape 1, solde des comptes de gestion, clôture, réouverture, ouverture de N+1) et de `Parametres\AssistantDemarrage::ouvrirExercice` (premier exercice), ET de `SyncController::pushFiscalClosureRequests` (clé `fiscal_closure_requests`, `{id, kind, payload}`, jouée APRÈS tout le reste de l'envoi). Droits comme au web : `close-fiscal-year` (mois, étapes, clôture, ouverture de N+1), `manage-modules` (déclôture, réouverture : administrateur), `manage-comptabilite` (premier exercice). Idempotence par l'UUID de la demande (table serveur `fiscal_closure_requests`, seules les demandes ACCEPTÉES y sont consignées : une clôture renvoyée après une réouverture ne reclôture pas). Mêmes gardes et mêmes motifs que le web (échéance, N-1 clos, étape 1, étape 2, à-nouveau équilibré, balance du mois, mois déjà clos, exercice absent/clos, N+1 dès le 1er décembre, jamais trois exercices ouverts). « Rien à solder » rejoué = succès. Le tirage sert `fiscal_years` (+ `step1_confirmed_at`, `closed_at`) et `periodic_closures` (`view-comptabilite`). Poste : Drift **v80** (`fiscal_closure_requests`, `periodic_closures`, deux colonnes de `fiscal_years`), `ClotureExerciceRepository` (UN SEUL écrivain, refuse avant d'écrire avec les messages du web ; `CalculCloture` = transposition prouvée par une parité EXÉCUTÉE contre le vrai service PHP), envoi dans l'ordre d'insertion (`rowid` : `updated_at` n'a que la seconde), acquittement → tirage de confirmation, conflit relançable ; écran `cloture_exercice_page.dart` fidèle au Blade (onglets, sélecteur de mois, historique, assistant en trois étapes, quatre modales, Exporter PDF, Lettrage Bancaire) ; l'étape « Exercice comptable » du premier démarrage propose « Ouvrir l'exercice AAAA ». Tests : `SyncClotureExerciceTest` (Laravel), `cloture_exercice_poste_test.dart`, `cloture_exercice_parite_php_test.dart`.
Limites assumées : le poste voit l'état du SERVEUR (étape 1 « confirmée » seulement après synchronisation ; ses demandes en attente sont listées et comptées dans les gardes locales) ; une écriture déséquilibrée (tirage incomplet) ne bloque pas la clôture d'un mois au poste, le serveur juge . **Non vérifié** : poste Windows réel.

### CP-3 ✅ (28/10/2026) Immobilisations au poste (registre, sortie, dotation)
Web d'abord : `App\Services\ImmobilisationService` (enregistrer + capitalisation par `RecordAssetAcquisitionEntryAction`, modifier avec la valeur figée d'un bien comptabilisé, sortir par cession ou réforme, passer la dotation par `RecordDepreciationEntryAction`) devient le point de passage de `Comptabilite\Immobilisations` ET de `SyncController::pushFixedAssets` / `pushDepreciationRequests` (clés `fixed_assets` et `depreciation_requests`, droit `manage-comptabilite`, après le plan comptable ; pull `fixed_assets`, droit `view-comptabilite`). La ligne entière du bien part ; le serveur distingue création (avec `counterpart` : vide = reprise d'antériorité, `credit`, ou le compte de trésorerie qui paie), modification, sortie et archivage ; un bien archivé ou déjà sorti n'est plus rouvert par le poste. La dotation ne porte que la date d'arrêté : le serveur recalcule l'écart contre le grand livre, la rejouer ne double rien. Drift **v75** : `fixed_assets` mixte (défauts « serveur / synced » comme `chart_of_accounts`) et `depreciation_requests`. ⚠️ **Le « prorata mensuel » du web est fractionnaire** : `Carbon::diffInMonths` rend depuis Carbon 3 des mois à virgule (31/01 → 28/02 = 0,903 mois, pas 1) ; le poste reproduit cette arithmétique (`CalculAmortissement`), prouvée par une parité EXÉCUTÉE contre le vrai `FixedAsset` sur 95 cas, fins de mois et années bissextiles compris (`immobilisations_parite_php_test.dart`, mutation vérifiée). Écran : carte « Immobilisations » du hub (que le web avait déjà), filtres date d'arrêté / nature / statut, quatre cartes (« Dotation à Comptabiliser » = tiret tant que le poste n'a reçu aucune écriture), mention « hors comptabilité », bandeau « Dotation aux amortissements en attente », ventilation, registre à onze colonnes, modales « Nouvelle Immobilisation », « Modifier l\'Immobilisation », « Sortie d\'Immobilisation », messages de `lang/fr`. Le web n'archive pas un bien : le poste non plus. Tests : `SyncImmobilisationsTest` (Laravel), `immobilisations_poste_test.dart`. **Non vérifié** : poste Windows réel.


## Assistant de démarrage : conservé, module DÉSACTIVÉ par défaut, et titre « Facturation » (29/10/2026)
- Décision du client : l'assistant de démarrage est GARDÉ (web et poste) comme un module, éteint par défaut, allumé depuis Paramètres > Modules Actifs (carte « Assistant de démarrage », web et poste). Le module est une ligne de `modules_config` de code `assistant_demarrage` (`ModuleConfig::ASSISTANT_DEMARRAGE`) : même écriture, même envoi du poste (`RecordModulesConfigFromDeviceAction`, droit `manage-modules`), même tirage que les espèces ; l'absence de ligne vaut « éteint » (les espèces, elles, sont actives par défaut). Web : `AssistantDemarrage::mount` exige le module ; poste : `PremierDemarrageRepository.afficherAssistant()` = poste neuf ET module allumé.
- Un poste vraiment neuf lit le module au serveur à la connexion (`GET /api/auth/me`, clé `assistant_demarrage_actif`) ; hors ligne, sa copie locale décide (éteint par défaut).
- Service serveur `ouvrirPremierExercice`, demande `ouvrir_exercice` et colonne `onboarding_completed_at` conservés.
- La barre de titre et le menu du poste disent « Facturation » tant que MeCeF est désactivé, « Facturation & MeCeF » sinon (`SocleAccueilTitres.titre(..., mecefActif:)`), comme le web.

## MDP-1 ✅ (29/10/2026) Réinitialisation du mot de passe par l'administrateur (décision du client : plus d'e-mail)
Décision du client : abandon de la réinitialisation automatique par e-mail (« Mot de passe oublié ? »). **Supprimé** (web d'abord) : `Login::sendResetLink`/`forgotEmail`, la fenêtre, `Livewire\Auth\ResetPassword` + vue + route `password.reset` (et son exemption de `SessionVerrouillee`), les tests de la page ; au poste, le bouton et `_DialogueMotDePasseOublie`. Remplacé, au web ET au poste, par le texte non cliquable « Contactez l'administrateur ». Le « PIN oublié ? » du verrou ne change pas.
**Geste administrateur** (point de passage unique `SaisieUtilisateurAction::reinitialiserMotDePasse`, partagé avec `pushUsers`, clé `users`, `reset_password: true`, droit `manage-users`) : mot de passe temporaire (`Password::defaults()`), `users.must_change_password` (migration Laravel `2026_10_29_000001` + Drift **v81** `utilisateurs`), jetons Sanctum révoqués, sessions web fermées, audit `user.password_reset` (jamais le mot de passe) ; refus de son propre compte et d'un compte archivé (message commun, serveur ET écran). Hors ligne au poste : le temporaire attend au coffre comme UT-1 (+ marqueur), part à la synchro.
**Changement forcé** : web, middleware `ChangementMotDePasseObligatoire` (groupe `web`, après le verrou) vers `/changer-mot-de-passe` ; poste, `POST /api/auth/login` rend `must_change_password` et `PorteSession` affiche `EcranChangementMotDePasseObligatoire` avant le PIN et l'accueil ; l'API refuse tout en 403 sauf `auth/password`, `auth/me`, `auth/logout`. Le changement réussi (`ChangerMotDePasseAction`) lève le drapeau.
**Code de secours de l'administrateur** : `php artisan agrierp:code-secours` et `agrierp:reinitialiser-admin {identifiant}` (table UUID `recovery_codes`, empreinte seule, usage unique, 5 échecs = blocage 15 min, nouveau code à chaque usage) ; procédure « à imprimer et ranger au coffre » dans [`CODE_SECOURS_ADMIN.md`](CODE_SECOURS_ADMIN.md).
Tests : Laravel `ReinitialisationMotDePasseAdminTest`, `ChangementMotDePasseObligatoireTest`, `SyncReinitialisationMotDePasseTest`, `CodeSecoursAdminTest`, `ConnexionSansReinitialisationParEmailTest` ; Flutter `reinitialisation_mot_de_passe_test.dart`, `migration_toutes_versions_test.dart` (palier 81).
**Limites assumées** : un compte créé hors ligne puis réinitialisé avant son premier envoi reçoit le temporaire à la création ; le geste de l'administrateur du poste est SANS effet immédiat côté serveur (jetons et sessions du compte tombent au prochain envoi) ; le premier code de secours n'est pas généré automatiquement (à faire à l'installation) ; la modification ordinaire d'un compte avec un mot de passe saisi (UT-1) ne pose pas le drapeau. Le manuel d'utilisation (`manuel/src`) est mis à jour en texte seulement (captures à refaire).


## AIDE-1 ✅ (29/10/2026) Bouton flottant d'aide, aide par écran, assistant relançable, visite guidée (web + poste)

Décision du client : seulement quand le module « Assistant de démarrage » est ALLUMÉ (éteint par défaut), un bouton `help` à droite de tous les écrans (au-dessus d'« Accès rapide », 12 px d'écart) ouvre un panneau : « Aide de cet écran », « Relancer l'assistant de démarrage », « Visite guidée ».

- **Source unique des textes** : `agrierp_laravel/lang/fr/aide_ecrans.php` (clé = chemin de la route ; 55 écrans web, repli générique pour une route non listée, visite en 4 étapes, libellés du panneau, `poste_seul` pour Synchronisation et Paramètres du poste). Le poste est produit par `php agrierp_flutter/outils/generer_aide_ecrans.php` (`lib/core/aide/aide_ecrans.dart`) ; garde exécutée `test/aide_ecrans_parite_test.dart`.
- **Choix** : le repli générique ne masque pas un oubli : `AideFlottanteTest` EXIGE une entrée par route authentifiée (et aucune entrée orpheline).
- **Relance au web** : `Parametres\AssistantDemarrage` est monté par le layout (plus par le seul tableau de bord ; `auto` vrai seulement sur le tableau de bord) et écoute `relancer-assistant` ; rien n'est écrit (`onboarding_completed_at` jamais remis à vide). « Terminer » après relance ne réécrit plus la date de fin. Ligne réservée à `manage-parametres`.
- **Relance au poste** : `PremierDemarrageScreen(relance: true)` poussé par-dessus le socle (titre « Assistant de démarrage », bouton « Fermer ») — le dépôt le permet sur un poste en service, aucune modale parallèle.
- **Visite** : Alpine maison (`resources/js/aide.js`, logique pure `aide-logique.js`), repères `data-aide="aide|topbar|contenu|menu"` ; au poste, VRAI voile percé sur les éléments du socle par `GlobalKey` (`PlacementVisite`, transposition de la logique JS). Élément absent ou hors champ (menu replié, tiroir mobile fermé) : étape sans trou.
- **Poste** : le module est relu après chaque tirage et quand la carte de Paramètres bascule (`surAssistantBascule`).
- **Non vérifié** : rendu navigateur réel (placement du trou, tiroir, focus), rendu Windows réel.

## Attestations : signature du Directeur et date modifiable (29/10/2026)
- Signataire UNIQUE (palier court) : signature et cachet du Directeur (`resources/attestation/images/signature-directeur.png`, copie `agrierp_flutter/assets/attestation/`), nom et fonction CENTRÉS en bas de page, au web (`exports/attestation.blade.php`) et au poste (`pdf_attestation.dart`, `_signataireUnique`). Trois signataires : disposition inchangée, sans signature imprimée.
- « Date de l'attestation » (après « ATTAN - ÉWÉ, le ») : champ du web (`Livewire\RH\Attestations::$dateAttestation`, API `date_attestation`) et du poste (`att-date-attestation`) ; vide = date du jour. Le numéro et la durée restent ceux de la date réelle.


## VOL-1 ✅ (05/11/2026) Volailles Reproducteurs — effectif par catégorie CALCULÉ (web d'abord, puis poste, Drift v82)

Décision du client (04/11/2026) : même principe que les lapins et les porcs (15.39 à 15.42). Détail technique : `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md` (sections VOL-1).

| Point | Décision / livraison |
|---|---|
| Catégories | **Reproducteur / Jeune / Poussin** — « Jeune » (ex-« Poulet ») partout : morts, dons, ventes, départ, rationnement, stade de la bande. Jamais « Jeune à maturité ». Emplacements de synchronisation inchangés : `*_repro`, `*_jeune`, `*_sevre` (= Poussin). |
| Formules | R = Rv − vente − mort − don ; J = Jv + achat − vente − mort − don + p ; P = Pv + éclosions − vente − mort − don − p ; chaque catégorie bornée à 0 ; passage Poussin → Jeune refusé au-delà de la source. |
| Aucune catégorie « inconnue » | Départ SAISI obligatoire avant toute journée (somme = effectif au début du jour). Sans départ : la fiche le demande et refuse d'enregistrer, la caisse et le push refusent avec un motif français. Jours antérieurs au départ non saisissables. |
| Bandes existantes | Aucune réécriture : le départ se demande à la première ouverture de la fiche (proposition d'après le stade, reprise d'un geste). Une journée portant des ventes d'avant VOL-1 (non ventilées) ne peut pas porter le départ : le saisir un autre jour. |
| Ventes par catégorie | `vente_repro/sevre/jeune` ; `vente` = somme ; catégorie = celle du PRODUIT (`products.categorie_effectif`, éditable dans « Ajouter/Modifier un produit », posée par défaut d'après le nom). Produit sans catégorie sur une bande à chaîne : vente refusée. |
| Rationnement | Lignes « Reproducteur » 130, « Jeune » 80, « Poussin » 30 g/j au barème de l'aviculture. ✅ **VALEURS CONFIRMÉES PAR LE CLIENT le 05/11/2026 (modifiables : Paramètres Élevage). Ancien libellé : VALEURS PROVISOIRES À CONFIRMER AVEC LE CLIENT** (modifiables dans Paramètres Élevage). Pondeuses non touchées. |
| Mise en service | Serveur ET poste ensemble (comme 3.F4) : un ancien poste voit ses fiches de volailles refusées (« ventilation incomplète », « départ requis »). |

**Glossaire des volailles** : Reproducteur (`repro`, 130 g/j) · Jeune (`jeune`, 80 g/j, ex-« Poulet ») · Poussin (`sevre`, 30 g/j). Stades de bande de l'aviculture : Reproducteur (`reproduction`) · Poussin (`croissance`) · Jeune (`engraissement`) · Ponte (`ponte`, Pondeuses).

**Écart assumé avec la maquette** : `fiche-volailles-reproducteurs.html` dit « Repro » / « Poulet » et un rationnement « par stade » ; le client a décidé « Jeune » et un rationnement par catégorie. Gardé par `test/volailles_effectif_test.dart` (saut si la maquette est absente).

**Ticket « Pondeuses par stade »** : fait par VOL-2 (ci-dessous). Restes de VOL-1 reportés : demande du départ à la création d'une bande (non faite, voir VOL-2) ; refus « départ requis » de la transformation au poste ; valeurs de ration provisoires.

**Non vérifié** : rendu navigateur et Windows réels ; mise en service sur une VRAIE base (migration des produits par le nom : relire la liste, un produit non reconnu reste sans catégorie) ; suites complètes Laravel et Flutter (seuls des tests ciblés ont été lancés).


## VOL-2 ✅ (05/11/2026) Volailles Pondeuses — effectif par STADE CALCULÉ (web d'abord, puis poste, Drift v83)

Décision du client (05/11/2026) : même principe que VOL-1 pour la fiche Pondeuses. Détail technique : `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md` (sections VOL-2).

| Point | Décision / livraison |
|---|---|
| Stades | **Poussin ponte / Poussin en croissance / Poulette / Pondeuse**, libellés EXACTS du barème (avec leur tranche d'âge), partout : morts, dons, ventes, départ, passages, rationnement. |
| Chaîne de passage | Poussin ponte → Poussin en croissance → Poulette → Pondeuse : trois passages saisissables (`passage_4_sevre`, `passage_sevre_jeune`, `passage_jeune_repro`), refusés au-delà de leur stade source (D3). |
| Formules | PP = PPv + éclosions − v − m − d − p1 ; PC = PCv − v − m − d + p1 − p2 ; PL = PLv + **achat** − v − m − d + p2 − p3 ; PO = POv − v − m − d + p3 ; chaque stade borné à 0, jamais « inconnu ». Achats → Poulette, éclosions → Poussin ponte. |
| Emplacements génériques | Pondeuse `repro`, Poulette `jeune`, Poussin en croissance `sevre`, **Poussin ponte `quatre` = colonnes `*_4`** (`cat_eff_4` existait déjà). Aucun nom de clé existant renommé : des colonnes AJOUTÉES (palier Drift 83). |
| Départ | Obligatoire par stade (somme = effectif au début du jour), demandé à la première ouverture de la fiche d'une bande sans départ, proposition « tout en Pondeuse » reprise d'un geste ; push refusé sans départ. Aucune réécriture des bandes existantes. |
| Ventes par stade | `vente_repro/sevre/jeune/4`, stade = celui du PRODUIT (`products.categorie_effectif`, 7 valeurs au total, défaut d'après le nom) ; produit sans stade (ou d'une autre famille) refusé avec motif. Transformation : sujets sortis de la Pondeuse par défaut. |
| Œufs | Récolte, casse, stock, vente d'œufs : inchangés. |
| Rationnement | 4 lignes (effectif calculé × ration du barème, 30 / 60 / 80 / 110 g/j), total arrondi comme PHP, alerte d'autonomie sur la somme. `RationVolaille` (web et poste) retiré. |
| Mise en service | Serveur ET poste ensemble : un ancien poste voit les fiches de sa bande de pondeuses refusées (« départ requis », « ventilation incomplète »). |

**Glossaire des volailles — les DEUX fiches** : *Reproducteurs* (stades de bande Reproducteur `reproduction`, Poussin `croissance`, Jeune `engraissement`) : Reproducteur (`repro`) · Jeune (`jeune`) · Poussin (`sevre`) ; *Pondeuses* (stade de bande Ponte `ponte`) : Pondeuse (`repro`, 110 g/j) · Poulette (`jeune`, 80 g/j) · Poussin en croissance (`sevre`, 60 g/j) · Poussin ponte (`quatre`, 30 g/j). Une catégorie ou un stade n'existe que dans SA famille (`volailles_repro` / `volailles_ponte`).

**Restes** : (1) demande du départ à la création d'une bande, pour les deux fiches (non faite : le départ est demandé à l'ouverture de la fiche) ; (2) refus « départ requis » de la transformation au poste ; (3) rapport à blanc / commande de migration des bandes existantes ; (4) rations de la fiche Reproducteurs encore PROVISOIRES (130 / 80 / 30) ; (5) une bande de poulettes ou de poussins de ponte est de stade `ponte` : sa proposition de départ dit « tout en Pondeuse », l'éleveur la corrige ; (6) un produit « Poussin d'un jour » reste une catégorie de reproducteurs : créer un produit distinct pour la fiche Pondeuses.

**Non vérifié** : rendu navigateur et Windows réels ; mise en service sur une VRAIE base (la migration `…000005` change l'énumération `livestock_transfers.categorie` : essayée sous SQLite seulement, pas sous MySQL/MariaDB) ; suites complètes Laravel et Flutter (seuls des tests ciblés ont été lancés).


**VOL-2 — décisions du client du 05/11/2026** : (1) rations 130 / 80 / 30 g/j confirmées, CRUD par Paramètres Élevage (web + poste) ; (2) demande du départ à la création d'une bande : non faite, le départ reste demandé à l'ouverture de la fiche ; (3) produit « Poussin d'un jour (ponte) » créé (semoir + migration `…000007`) ; (4) migrations VOL-1/VOL-2 jouées sur MariaDB 10.11 : `migrate:fresh --seed`, rollback de 3 paliers puis re-migration, enum `livestock_transfers.categorie` = repro/sevre/jeune/quatre. Rendu navigateur / Windows : toujours non vérifié.

## MECEF-1 ✅ (07/11/2026) e-MECeF en ligne, mode boîtier paramétrable, facture normalisée verrouillée (web d'abord, puis poste, Drift v84)

Décisions du client (07/11/2026) : la ferme a un compte e-MECeF (API en ligne de la DGI, sans boîtier) ; d'autres structures utilisent un boîtier (Eltrade CC300) et la ferme en achètera un : les deux modes se paramètrent. Une facture normalisée n'est plus modifiable ni annulable : toute correction passe par un avoir lié à la facture d'origine.

| Point | Livraison |
|---|---|
| Mode | `desactive` (défaut) / `emecef` (transmission par le SERVEUR) / `boitier` (squelette : « Mode boîtier : transmission par le poste non encore disponible. », rien transmis). Paramètres > Données de l'Entreprise, web ET poste (demande `entreprise`). `mecef_actif` dérivé ; `config/mecef.php` = valeur par défaut (phpunit l'allume : passerelle de démonstration). |
| Jeton JWT | Secret : chiffré, masqué, jamais servi au poste (seulement `mecef_jeton_configure`), jamais journalisé ; saisi au web seulement. |
| `EmecefGateway` | `POST /invoice` puis `PUT /invoice/{uid}/confirm`, un seul essai de création, `uid` gardé, reprise par confirmation seule, états en attente / normalisée / refusée / expirée, motifs français, jamais d'exception qui bloque la vente. Constructeur unique `MecefFactureBuilder`. |
| Intégrité | Vente normalisée verrouillée (modèle, lignes, annulation, web + poste, même message) ; correction par avoir `FA` (`reference` = uid d'origine) transmis par le même mécanisme. |
| Facture PDF | QR de la DGI + code MeCeF/DGI, NIM, compteurs, date et heure, web et poste ; rien d'inventé sans normalisation. |
| Poste | Drift v84 (colonnes `mecef_*` de `sales` et `credit_notes`, tirées, jamais écrites) ; Facturation : statuts Normalisée / En attente / Refusée / Expirée + motif ; lecture seule de la facture normalisée. |

**MECEF-2 (boîtier par le poste) : ✅ CONSTRUIT SANS L'APPAREIL (09/11/2026) / ⚠️ ESSAI RÉEL À FAIRE.** Décision du client : « faut lancer le chantier, faut pas attendre le boîtier ». Option A retenue (charge portée en Dart, parité PHP exécutée : `charge_boitier_parite_php_test.dart`) ; client HTTP localhost (succès SEULEMENT si `qr_code` non vide, 400 → motif français, 503 → « Boîtier injoignable » sans erreur rouge) ; transmission par le poste en mode `boitier` (états En attente / Normalisée / Refusée, marque d'incertitude, jamais deux transmissions d'une vente, reprise au retour du boîtier) ; résultat envoyé au serveur (bloc `mecef`, validé, jamais par-dessus une facture normalisée) ; indicateur d'état (Paramètres › Facturation normalisée, caisse). **NON VÉRIFIÉ AVEC UN VRAI BOÎTIER** (faux pilote seulement) ni sous Windows ; **avoir par le poste NON branché** ; libellé « Boîtier MeCeF (à venir) » gardé jusqu'à l'essai. Checklist du premier essai : `docs/logialvia/41_MECEF_EMECEF.md` § 3.3.

**Non vérifié** : AUCUN appel réel à la DGI (ni jeton ni IFU) — chemins, noms de champs, détection de l'expiration et reprise par confirmation seule d'après un paquet non officiel, non confirmés par la documentation DGI (injoignable) ; arrondis des prix unitaires non entiers ; confirmation d'une facture déjà confirmée ; MySQL/MariaDB réel (migration `mecef_status` enum → texte essayée sous SQLite seulement) ; rendu Windows réel du QR du PDF du poste ; suites complètes.
**Restes / décisions à prendre** : numérotation propre de la facture normalisée ; ~~IFU et AIB du client (absents de la base)~~ ✅ MECEF-3 ; ~~frais de livraison hors facture DGI~~ ✅ MECEF-3 ; avoirs du poste : pas d'écran de statut d'avoir ; clés `transmise` / `erreur` conservées (renommer en `normalisee` / `refusee` demande une migration des données, des tests et du poste).

## MECEF-3 ✅ (07/11/2026) prix entiers, choix « facture simple / normalisée », livraison incluse, formulaire e-MECeF (Drift v85)

Demande du client du 07/11/2026. (Le ticket « MECEF-2 » est le mode boîtier par le poste : construit sans l'appareil, essai réel à faire.)

| Point | Livraison |
|---|---|
| A. Pas de prix décimal | `MecefFactureBuilder` : montants ENTIERS (prix, prix d'origine, règlement), UNE fonction d'arrondi ; remise au plus fort reste ; écart d'arrondi absorbé par la plus grande ligne (déterministe, refus au-delà du nombre de lignes) ; prix × quantité = montant de la ligne, sinon quantité 1 avec la quantité réelle au libellé. `MecefEntiersTest`. |
| B. Choix à la vente | `sales.facture_type/client_ifu/client_nom_facture/aib_taux/mecef_aib_montant`, `customers.ifu` ; `ChoixFactureService` (web ET poste, parité exécutée) ; simple = JAMAIS transmise ; normalisée : fenêtre `x-modal` / `ModaleAgri` (IFU facultatif, nom obligatoire, AIB 5 % défaut) ; Facturation, PDF web et poste. |
| C. Livraison incluse | `sales.delivery_in_total` (nouvelles ventes seulement) ; total = produits + livraison ; D contrepartie du total, C 701, C 7071 (repli 701), C 443 ; TVA au taux de la ligne principale ; ligne « Frais de livraison » B/A. |
| D. Formulaire e-MECeF | Onglet « Facturation normalisée (e-MECeF) » (web et poste), `MecefReglageService`, jeton masqué (Remplacer / Effacer), deux préréglages d'adresse, « Tester la configuration » (`GET /info/status`, lecture seule). |

**Parcours du premier essai réel** (au web) : 1. Paramètres > Facturation normalisée (e-MECeF) ; 2. choisir « e-MECeF (en ligne) », saisir l'IFU (13 chiffres) ; 3. choisir « Environnement d'essai (DGI) » (l'adresse par défaut), coller le jeton du compte e-MECeF de l'IFU (portail de la DGI), Enregistrer ; 4. « Tester la configuration » : attendre « Configuration valide » ; 5. Ventes > Caisse : un produit au panier, « Type de Facture » = « Facture normalisée », la fenêtre s'ouvre : nom et prénom (IFU si le client en a un, AIB 5 %), Valider, « Valider la Vente » ; 6. Facturation : la ligne passe « Normalisée » (QR, code MeCeF/DGI, NIM, compteurs) ; si elle reste « En attente », le motif français est sous la pastille et « Retransmettre » existe ; 7. Imprimer la facture PDF : QR, IFU, nom, AIB. Au poste : mêmes choix (la transmission part à la synchronisation).

**Décisions non évidentes** : AIB = champ `aib` `B`/`A`/omis, montant calculé par la DGI jamais par nous, règlement sans AIB (paquet non officiel) ; IFU vide = client sans IFU (champ omis) ; une facture issue d'un devis est simple ; anciennes ventes : `normalisee` si déjà normalisées, sinon `simple` ; l'URL par défaut est l'ESSAI (MECEF-1 l'avait nommée « production »).

**Non vérifié** : AUCUN appel réel à la DGI ; `GET /info/status`, ses champs de réponse, le champ `aib` (A/B) et l'AIB hors du total envoyé viennent d'un paquet non officiel ; les deux adresses (essai / production) ne sont confirmées par aucune documentation DGI ; Dusk (modale de la caisse) et MariaDB réel non lancés.
**Décision à prendre** : la Déclaration de TVA ne retient que les ventes normalisées (règle M14) : les factures simples n'y figurent pas — à confirmer avec le cabinet FAGUEZ.


## PWA-1 ✅ (08/11/2026) — la caisse hors ligne du navigateur (PWA utilisable hors ligne, synchronisation à la reconnexion)

**Décision du client (08/11/2026) : « ON DÉMARRE LA CONSTRUCTION ».** Elle LÈVE le refus d'origine de `agrierp_laravel/CLAUDE.md` (« cette PWA ne fait pas travailler LogiAgriERP hors ligne ») pour un **périmètre minimal : la caisse**. Conception suivie : `docs/logialvia/40_PWA_HORS_LIGNE.md` (inchangé). Doctrine et pièces : `agrierp_laravel/CLAUDE.md`, sections « PWA » et « PWA-1 ».

| Point | Livraison |
|---|---|
| Périmètre | Ventes de caisse (produits du catalogue, panier, quantité entière + montant global, remise, mode de règlement espèces / Mobile Money / virement / crédit, facture simple ou normalisée avec nom, IFU, AIB) ; consultation du catalogue et des clients copiés ; verrou/PIN ; indicateur « Hors ligne / En attente (N) / Synchronisé / Refus (N) / Reconnexion requise » |
| Appairage | Page « Mode hors ligne » (menu de profil, `manage-ventes`) : `POST /api/auth/login` avec `device_name = pwa-<uuid>` APRÈS la connexion web ; jeton chiffré par le PIN (PBKDF2 600 000 + AES-GCM) ; révocable dans « Postes & Appairage » ; purge à la déconnexion |
| Stockage | IndexedDB `agrierp_hors_ligne` v2 (migration testée v1 → v2), file `pending/synced/conflict`, journal des refus, quota géré (la vente n'est PAS enregistrée si le stockage refuse), nettoyage des `synced` de plus de 30 jours |
| Service worker | `agrierp-v6` : enveloppe statique précachée, deux pages HTML statiques nommées, aucun POST, aucun HTML authentifié, purge par message `PURGER`, Background Sync = réveil d'un onglet seulement (repli : `online` + sondage `/up`, premier plan, 5 min, bouton) |
| Synchronisation | Protocole du poste inchangé : pull paginé puis push par lots, `server_time`, idempotence par UUID, accusé avant `synced`, refus motivés, 401/403 = suspension, réessais 30 s à 1 h ; vente normalisée = « demandée — en attente », transmise par le serveur |
| Preuves | 73 essais `node --test` (dont parité exécutée contre le PHP), `PwaHorsLigneTest` (13), `PwaEtPolicesLocalesTest` (20), essai Playwright de bout en bout (14 étapes), 3 mutations détectées |

**Ce que le MVP ne couvre pas (dit au client)** : voir « Limites connues » de `CLAUDE.md` — purge possible d'IndexedDB par le navigateur (détectée, non récupérable), pas de Background Sync sur iOS/Safari ni Firefox (aucun essai iPhone), un seul onglet qui écrit, tant que l'appareil est verrouillé rien ne part, durée hors ligne bornée par le jeton (90 jours) et par la fraîcheur des prix (avertissement dès 3 jours), le catalogue incrémental ne retire pas un produit supprimé au bureau.

**Décisions client en attente** : (1) seuil de péremption des prix au-delà duquel REFUSER la vente hors ligne (aujourd'hui : avertissement seul, 3 jours) ; (2) appareil personnel ou d'entreprise, PIN suffisant ? ; (3) reçu provisoire à imprimer (aujourd'hui : aucun, le numéro de facture est attribué par le serveur à la synchronisation) ; (4) essai sur les vrais appareils de la ferme (Android, iPhone).

### Phases suivantes (non construites)

| Phase | Contenu | Prérequis |
|---|---|---|
| PWA-1b | ✅ (10/11/2026) — caisse complète : livraison facturée ✅, vente sur avance ✅, client créé hors ligne ✅, produits rattachés à une espèce (bande source, rémanence tirée, refus du web, effet sur la fiche du jour) ✅ | Voir la section « PWA-1b » ci-dessous |
| PWA-3 | ✅ COMPLET (09/11/2026) — repris sur décision du client (« Reprendre la fiche lapins », puis « une fiche à la fois ») : fiches LAPINS, PORCS, ESCARGOTS, VOLAILLES REPRODUCTEURS et VOLAILLES PONDEUSES livrées hors ligne dans le navigateur (écran du mois, saisie d'un jour, file d'envoi, autonomie, provende, prophylaxie du jour), chacune prouvée contre le vrai composant Livewire. **État final exact** : le stock d'œufs jour par jour (SRH / TS / OS / stock final) est calculé par le serveur et n'est PAS reproduit hors ligne (« — ») ; l'incrémentation du stock d'œufs se fait au serveur à l'envoi ; export PDF en ligne seulement ; non vérifié sur iPhone/Safari. Auparavant ⏸️ SUSPENDU (remplacé par le poste web Flutter) | Voir la section « PWA-3 » ci-dessous |
| PWA-4 | Consultation hors ligne élargie (stock, créances, historique des ventes) | Tables lues en lecture seule, chiffrées |
| PWA-5 | Comptabilité / paie hors ligne | Probablement jamais : reste au poste Windows (règle « la vue Blade est le maître », deux clients à tenir en parité) |
| PWA-6 | Essai multipostes avec un navigateur participant (`SyncEssaiMultipostesTest`), essai iOS/Safari documenté (A12 de la spécification) | Appareils du client |

## IMPORT-1 ✅ (08/11/2026) Importation en masse par tableur xlsx — Stocks, Clients, Fournisseurs (web d'abord, puis poste, aucun palier Drift)
Décision du client : « ON DÉMARRE LA CONSTRUCTION », « très important », écran dédié au poste et au web. Conception : guide logialvia bloc 21 / fichier 28. Détail : sections IMPORT-1 de `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md`.
- **Fait** : `App\Services\Import\*` (orchestrateur + un service par module, lecture et validation ligne par ligne, aperçu, confirmation, rapport xlsx, journal `import_batches`), modèles xlsx versionnés à télécharger, écran Livewire `/importation-masse` (six étapes, groupe ADMINISTRATION du menu), écran du poste fidèle, parité exécutée contre le vrai PHP, tests et contrôle par mutation.
- **Décisions** : création SEULE (jamais d'écrasement) ; idempotence par clé naturelle (`FusionReferentielsService`) + UUID v5 déterministe ; produit déjà au catalogue IGNORÉ sans stock ajouté ; stock initial par `AdjustStockAction` (web) / règle existante du poste (serveur écrit le mouvement) ; ligne par ligne, pas de « tout ou rien » ; fournisseurs sans e-mail ; modèle du poste généré hors ligne sans listes déroulantes natives.
- **Reste à décider avec le client** (questions Q-IMP du guide) : taille maximale (5 Mo / 5 000 lignes retenus provisoirement), option « tout ou rien », conservation du rapport (aujourd'hui au journal serveur), date d'ouverture du stock initial (aujourd'hui : jour de l'import), intrants distincts des produits vendables (LogiAgriERP n'a qu'une table `products`).
### IMPORT-2 à IMPORT-5 ✅ (09/11/2026) — construits (web d'abord, puis poste, aucun palier Drift)
Ordre du client : « Lance IMPORT-2 à 5 ». Mêmes six étapes, mêmes libellés, création SEULE, UUID v5, ligne par ligne, parité exécutée contre le vrai PHP. Détail : sections IMPORT-2 à IMPORT-5 de `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md` ; conception : `docs/logialvia/48_PLAN_IMPORT_MASSE_PHASES.md` (statut : construit).
| Phase | Clé retenue | Point de passage | Droit | Clé de ligne |
|---|---|---|---|---|
| IMPORT-2 ✅ | `employes` | `SaisieEmployeAction::creer` ; poste `PersonnelRepository.enregistrerEmploye` | `manage-rh` | nom + prénom + date d'embauche (AAAA-MM-JJ), employés ACTIFS ; salaire JAMAIS au rapport |
| IMPORT-3 ✅ | `plan_comptable` | `PlanComptableService::creer` ; poste `ComptabiliteRepository.creerCompte` | `manage-comptabilite` | numéro de compte (sans espace, minuscules) ; tout le plan, archivés compris ; la règle `unique` devient « ignoré » |
| IMPORT-4 ✅ | `rations` | NOUVEAU `RationStandardService::creer` (les règles vivaient en dur dans `ParametresElevage::saveRation`, qui les lit maintenant) ; poste `ParametresElevageRepository.enregistrerRation` | `manage-elevage` | espèce + libellé de stade normalisé ; rations ACTIVES |
| IMPORT-5 ✅ | (aucun module) | CSV de repli : `LecteurCsv` ; poste `_lireCsv` | celui du module | — |
- **IMPORT-5 : choix retenu et justification.** Le plan (48) ne nomme aucun module pour IMPORT-5 : sa ligne liste trois pistes « à décider » (journal d'import au poste, mise à jour en masse, CSV de repli). Retenu : le **CSV de repli**, le choix le plus sûr : il ne change que la LECTURE du fichier (même tableau « ligne → colonne → texte », donc mêmes règles, mêmes motifs, mêmes droits, création seule inchangée), sans table, sans palier Drift, sans donnée gardée. Écartés : la **mise à jour en masse** contredit la décision « création SEULE, jamais d'écrasement » (décision du client à reprendre) ; le **journal d'import au poste** exige un stockage (table ou clés `app_settings`) et pose la question de ce qu'on conserve (salaires, lignes refusées) : à décider avec le client. Le glisser-déposer est déjà fait (CONF-2).
- **Limites** : le paquet `excel` du poste n'a pas de listes déroulantes natives (feuille « Listes » + refus à l'aperçu) ; le CSV n'a ni feuille « Modele » (ni module ni version contrôlés : les en-têtes exacts font foi) ni formats de cellule (un zéro initial ou une date réécrite par le tableur est refusé à l'aperçu) ; encodage reconnu : UTF-8 (BOM ou non) puis Windows-1252 ; séparateurs `;`, `,`, tabulation. Aucun de ces modules n'écrit dans un exercice : l'exercice clos ne les bloque pas (seul le stock initial des Stocks y est soumis). Écart découvert et NON corrigé (IMPORT-1) : la validation d'e-mail du poste est une approximation de la règle `email` de Laravel (une adresse comme `a"b@x.test` passe au poste, est refusée au serveur, qui revalide à la synchronisation). **NON vérifié : avec un vrai Excel (fichiers essayés avec PhpSpreadsheet et le paquet `excel`), sous Windows, glisser-déposer au navigateur.**

## CONF-1 ✅ (08/11/2026) Logo et favicon réellement utilisés, téléversement sûr, droits à l'ouverture, relance sans SMTP, repli `.env` e-MECeF (web d'abord, puis poste, aucun palier Drift)
Décision du client : « FAUT CORRIGER » les défauts relevés dans `docs/logialvia/42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md`. Détail : sections CONF-1 de `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md`.
- **Fait** : `IdentiteVisuelle` (point de passage unique : logo, favicon, type MIME déduit du fichier, cache-busting, repli) utilisé par les layouts, la barre latérale, la connexion et l'en-tête des PDF serveur ; téléversement ICO/PNG (favicon) et PNG/JPG/WEBP (logo) jugé sur l'en-tête, tout validé avant d'écrire, ancien fichier effacé, suppression avec confirmation, glisser-déposer câblé, mêmes messages au web, à l'API et au poste ; `abort_unless` à l'ouverture de tous les onglets sensibles du hub Paramètres ; relance e-mail refusée sans SMTP réel (web et poste) ; repli `SGMEF_*` de `.env` pour e-MECeF (jeton jamais affiché) ; poste : logo choisi dans la barre latérale et la connexion, suppression, mêmes règles.
- **Laissé volontairement** : l'attestation (visuel mesuré sur le modèle du client), le précache du service worker et les icônes de la PWA.
- **Non construit** : interface web, file d'attente, préfixe de route et polling du paquet e-MECeF (`SGMEF_WEB_INTERFACE_ENABLED`, `SGMEF_QUEUE_*`, `SGMEF_ROUTE_PREFIX`, `SGMEF_POLLING_SECONDS`) ; limiteur sortant `SGMEF_RATE_LIMIT_PER_MINUTE` ; glisser-déposer au poste (paquet `desktop_drop`) ; favicon dans l'interface du poste (pas d'onglet).
- **Non vérifié** : glisser-déposer dans un vrai navigateur (directives contrôlées dans la vue, pas de Dusk) ; rendu réel du logo dans un PDF DomPDF ouvert à l'œil ; ICO dans les navigateurs ; fenêtre réelle Windows.

## CONF-2 ✅ (08/11/2026) Le tracteur ne change jamais ; logo de la ferme par défaut ; glisser-déposer et aperçu ICO au poste ; spécimens `presentation/` (web et poste, aucun palier Drift)
Décisions du client (08/11/2026) : (A) le logo « LogiAgriERP / FERME OLOUWACHEGOUN » avec l'icône de TRACTEUR reste FIXE sur la connexion, la barre latérale et l'écran de verrouillage, web ET poste — CONF-1 est annulé sur ces trois emplacements ; le logo choisi dans les réglages ne sert qu'aux DOCUMENTS (factures, PDF serveur, PDF du poste) et au FAVICON ; (B) sans choix, documents et favicon prennent le logo officiel de la Ferme École OLOUWACHEGOUN, en PNG et en ICO ; (C) glisser-déposer au poste ; (D) aperçu de l'ICO dessiné ; (E) spécimens de présentation ; (F) docs. Détail : sections CONF-2 de `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md`.
- **Fait** : composant `x-logo-entreprise` et widget `LogoEntreprise` SUPPRIMÉS (plus aucun usage) ; gardes qui lisent les sources (Laravel `IdentiteVisuelleTest`, Flutter `fichiers_entreprise_test`) ; `IdentiteVisuelle` : repli logo = `logo_ferme_ecole_officiel.png`, repli favicon = `favicon.ico` (`image/x-icon`) + `favicon-32.png` générés par `outils/generer_favicon_ferme.py` ; paquet `desktop_drop` 0.8.4 (`ZoneDepot`, source injectable) câblé sur « Données de l'Entreprise » (logo, favicon) et sur l'étape de dépôt de l'« Importation en masse » ; aperçu de l'ICO par le paquet `image` 4.3.0 (déclaré, déjà au verrou) ; dossier `presentation/` régénérable par `php presentation/generer.php` ; `ChargeBoitierEltrade` (traduction `MecefFactureBuilder` → schéma `bill.spec.json`).
- **Non vérifié** : glisser-déposer RÉEL sur Windows (le plugin natif n'a jamais tourné ici, seuls les widgets et une source simulée sont testés) ; compilation Windows avec `desktop_drop` (seul `flutter analyze` et les tests sont passés) ; ICO dans les navigateurs ; JSON du ticket d'essai jamais envoyé à un vrai boîtier.

## CONF-3 ✅ (08/11/2026) Droits à l'ouverture (suite), prix périmés de la caisse hors ligne, libellés des modes de règlement, DV-16 à DV-22 (web d'abord, puis poste, aucun palier Drift)
Décision du client : « propose tes recommandations, je vais suivre » : DV-16 à DV-22 adoptées (`docs/logialvia/16_DECISIONS_VALIDEES.md`), à confirmer sur le terrain. Détail : sections CONF-3 de `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md`.
- **Fait** : garde d'ouverture `abort_unless(Gate::allows(…), 403)` sur `RolesPermissions` (`manage-users`), `ModesPaiement` (`manage-comptabilite`), `AuditLogs` (`view-parametres`), `Corbeille` (`manage-parametres`), mutation prouvée ; caisse hors ligne : bandeau dès 3 jours, confirmation avant chaque vente dès 7 jours, jamais de refus (âge sur le dernier tirage réussi, décalage serveur compris) ; `App\Support\ModePaiement` / `ModePaiement` du poste (facture web et PDF du poste, historique des ventes, détail de facturation), parité exécutée ; `presentation/` régénéré ; registre DV-16 à DV-22 et renvois.
- **À ouvrir (non construit)** : (1) périmètre du comptable de DV-20 dans `RolesAndPermissionsSeeder` (lecture ventes/achats, `view-facturation`, `manage-facturation` = retransmettre et avoir, SANS annuler une vente : séparer les deux gestes) — **FERMÉ par CONF-4** (droit fin `correct-invoices` plutôt que `manage-facturation`) ; (2) droit délégué « stock » si une personne tient le stock ; (3) indicateur « délai de livraison constaté » par fournisseur (DV-18) ; (4) PHASE 0 de la PWA tous modules (DV-16, 3 jours, preuve dans Chrome) ; (5) protocole d'observation des 3 premiers lots d'incubation (DV-17) : à suivre sur le terrain.
- **Non vérifié** : confirmation « prix périmés » sur une vraie tablette ; Safari/iPhone (jamais essayé) ; vérification de la phase 0 PWA.

## CONF-4 ✅ (08/11/2026) Périmètre du comptable de DV-20 dans LogiAgriERP : lecture ventes / achats / stocks, avoirs et retransmission, SANS caisse ni annulation (web d'abord, puis poste, aucun palier Drift)
Décision du client : « OUI, le même périmètre dans LogiAgriERP ». Ferme l'écart « le seeder ne donne pas au comptable le périmètre de DV-20 » noté par CONF-3. Détail : sections CONF-4 de `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md`.
- **Fait** : droit fin `correct-invoices` (pas de 5ᵉ rôle) et Gates `avoir-client` (`manage-ventes` OU `correct-invoices` : avoir, « traité », retransmission de l'avoir) et `retransmettre-facture` (`manage-facturation` OU `correct-invoices`) ; caisse (refusée dès `mount()`), annulation d'une vente, devis, conversion en facture : `manage-ventes` seul ; hub Ventes & Devis sans l'onglet de la caisse pour le comptable ; seeder (comptable : `view-ventes`, `view-achats`, `view-stocks`, `view-facturation`, `correct-invoices`) et **migration neuve idempotente** `2026_11_08_000002_accorder_perimetre_comptable_conf4` (bases déjà déployées) ; API : `credit_notes` sous `avoir-client`, annulation de vente du comptable refusée avec un motif français ; poste : `PermissionsPoste` (droits + carte : le comptable voit Ventes & Devis en lecture, Retours et Avoirs, Facturation, Achats, Fournisseurs, Dépenses, Stocks, Catalogue ; pas la caisse), `RefusDroit` sur les écritures d'achats, catalogue en consultation, annulation masquée.
- **Tests** : Laravel `ComptablePerimetreTest` (19) + mutations ; Flutter `permissions_poste_test`, `perimetre_tirage_test`, `ventes_devis_test`, `refus_droit_comptable_test` et les tests corrigés de l'ancien périmètre.
- **À ouvrir (non construit)** : (1) « Clients et Créances » au poste pour le comptable (gardes par droit sur relances, encaissements, avances) ; (2) `comptabilite-hub.html` toujours absent de la carte du comptable au poste (incohérence antérieure de `RBAC_PAGE_MAP`) ; (3) `export-ventes` (ticket PDF) non donné au comptable : à confirmer avec le client ; (4) droit délégué « stock » (DV-20) toujours à construire si une personne tient le stock.
- **Non vérifié** : parcours réel d'un comptable sur un navigateur et sur le poste Windows (tests Livewire, API et widgets seulement) ; migration sur une vraie base MariaDB de production.

## CONF-5 ✅ (08/11/2026) Trois écarts de CONF-4 : Clients et Créances en lecture (comptable), hub Comptabilité au poste (comptable), `view-facturation` du caissier (web d'abord, puis poste, aucun palier Drift)
Décision du client : « lance le reste ». **Ferme les trois écarts de CONF-4** (Clients et Créances au poste, `comptabilite-hub.html` dans la carte du comptable, caissier sans `view-facturation`). Détail : sections CONF-5 de `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md`.
- **Fait** : `authorize('manage-ventes')` en première ligne de chaque méthode qui écrit ou ouvre une modale d'écriture de Clients et Créances (les trois relances de `RelancesClients` n'en avaient AUCUNE) + boutons sous `@can` ; poste : `peutGerer` + `RefusDroit` sur chaque geste, boutons masqués, `creances-clients.html` et `comptabilite-hub.html` ouverts au comptable (`RBAC_PAGE_MAP` étendu, dit dans le code) ; `view-facturation` au caissier (seeder + migration `2026_11_08_000005_accorder_view_facturation_caissier_conf5`), bouton de retransmission sous `@can('retransmettre-facture')`.
- **Tests** : Laravel `ComptableCreancesLectureTest` (5), `CaissierFacturationLectureTest` (9), `ComptablePerimetreTest` corrigé ; Flutter `clients_creances_lecture_test` (9), `permissions_poste_test` ; mutations prouvées (voir les deux CLAUDE.md).
- **À ouvrir** : `export-ventes` du comptable (PDF de clients, créances, avances : 403 au web, impression locale au poste) ; droit délégué « stock » (DV-20).
- **Non vérifié** : parcours réel d'un comptable / d'un caissier sur un navigateur et sur le poste Windows ; migration sur une vraie base MariaDB de production.

## RELEVES-1 ✅ (08/11/2026) Onglet « Relevés de terrain » (CRUD lié au Dashboard élevage), règle « À valider → Validé » (web d'abord, puis poste, Drift v86)
Décision du client (08/11/2026) : « je suis ta proposition : créer un onglet avec un CRUD (tableau) lié au Dashboard Élevage, avec par défaut ta proposition ; tout statut « À valider » avec une modale de mise à jour du bouton « Valider » ; en enregistrant, on ne doit plus avoir « À valider » ». Décisions DV-23 et DV-24 (`docs/logialvia/16_DECISIONS_VALIDEES.md`). Détail : sections RELEVES-1 de `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md`.
- **Fait** : table `field_survey_entries` (migration `2026_11_08_000003`, semis idempotent « À valider » par migration ET `ReleveTerrainSeeder`) ; `ReleveTerrainService` (point de passage unique web + `SyncController`, clé `field_survey_entries`, droits `view-elevage` / `manage-elevage`, audit `releve.saved` / `releve.valide` / `releve.archived`) ; onglet « Relevés de terrain » (trois familles, `x-datatable`, deux modales événementielles : saisie et « Valider ») ; calculs (durée observée, taux de fertilité et d'éclosion, délai constaté sur les 5 derniers bons, règle critique / alerte) ; bloc de cinq cartes du Dashboard Élevage ; seuil CRITIQUE de l'alerte d'autonomie lu de la règle ; poste : Drift v86, `ReleveTerrainRepository` (un seul écrivain), onglet fidèle au Blade, absorbeur STRICT, cartes du Dashboard.
- **Inventaire des statuts « à valider / provisoire » (grep app, resources, lang, database, lib)** : un seul VRAI champ de statut existait à porter, la nouvelle table. Autres mentions, SANS champ de statut : barème ITS « Première configuration — à valider avant toute paie réelle » (état déduit de la première édition : enregistrer vaut validation, déjà conforme) ; rations de volailles « provisoires » (VOL-1 : constantes `RATIONS_PROVISOIRES`, valeurs CONFIRMÉES le 05/11/2026) ; exercice « Provisoire » et à-nouveaux provisoires (états CALCULÉS levés par la clôture de l'exercice précédent) ; « décision à confirmer » (commentaires de code). **Rien d'autre à implémenter ; tout futur statut suivra DV-24.**
- **Tests** : Laravel `ReleveTerrainTest` (16, mutation prouvée : retirer le passage à « Validé » à l'enregistrement fait rougir 3 tests) ; Flutter `releve_terrain_poste_test`, `releve_terrain_blade_test`, `releve_terrain_parite_php_test` (calculs, refus, délais, règle, synthèse comparés au vrai PHP), `migration_toutes_versions_test` (palier 86).
- **À ouvrir (non construit)** : repères d'incubateur et rappels automatiques de DV-11 (champs 7, 10 à 13) ; module d'incubation (cycles, mirages) ; au poste de l'animalier le délai constaté n'est pas calculable (les bons de commande ne lui sont pas servis) : la règle reste aux valeurs de départ ; archive des relevés dans la Corbeille ; sélecteur de date natif au poste (champ texte AAAA-MM-JJ).
- **Non vérifié** : parcours réel sur navigateur et sur le poste Windows ; migration sur une vraie base MariaDB de production ; Dusk.


## PWA-2 — le poste Flutter compilé pour le web (PWA tous modules), phase 1 : SOCLE (08/11/2026)

Décision du client (« Lance le reste », après la phase 0 : `docs/logialvia/45_…`). ⚠️ Le libellé « PWA-2 » de la table de PWA-1 (caisse complète) est renommé **PWA-1b** : PWA-2 désigne désormais le poste web.

**Fait (socle)** : cible `agrierp_flutter/web/` versionnée (index statique, manifeste `/poste/`, icônes du logo, `sqlite3.wasm` et `drift_worker.js`) ; ouverture de la base par import conditionnel (natif INCHANGÉ) ; interfaces d'E/S (téléchargement, dossier, SMTP, sauvegardes, justificatifs, logo, ouvreur d'URL, adresse du serveur, identifiant `poste-web-xxxxxxxx`) ; service worker propre `poste_sw.js` (précache versionné de l'enveloppe, jamais d'API ni de HTML authentifié) ; hébergement Laravel `public/poste/` (MIME wasm, `no-cache`, aucun COOP/COEP) ; `outils/construire_poste_web.sh` ; preuve Chromium `outils/e2e_poste_web.mjs` : **rechargement hors ligne OUI**, saisie hors ligne puis synchronisation unique OUI, données conservées après fermeture OUI.

**Reste de la phase 1** : (1) instruire la synchronisation incrémentale lente (134 s, page 1 appliquée en ≈ 90 s) et l'anomalie du fil principal sous « Rappels du jour » ; (2) synchronisation à l'ouverture / au retour de focus / à la reconnexion (la minuterie de 5 min est bridée en onglet d'arrière-plan) ; (3) justificatifs : décider du stockage en base (octets) ; sauvegarde complète : export d'octets ; glisser-déposer (`SourceDepotNative`), `exit(0)`, boutons de fenêtre Windows de la barre supérieure ; (4) `flutter_secure_storage` ^10 et build `--wasm` (revalidation Windows) ; (5) vente de caisse du poste jouée hors ligne ; (6) mise à jour contrôlée du service worker (message « nouvelle version », `SKIP_WAITING`) ; (7) CI : build web + garde « aucune URL externe » ; (8) plusieurs onglets (un seul écrivain) ; (9) Apache réel (`curl -I /poste/sqlite3.wasm`, `Cache-Control`) ; (10) clavier tactile et saisie du PIN sur tablette.

**Phase 2 (après recette de la phase 1)** : pilotes Stocks, Fournisseurs, Ventes & Devis en recette sur Chrome Android, Edge, **Safari iPad / iPhone (critère d'arrêt n°2 de l'étude 44 : jamais essayé)**, éviction du stockage, quota, appareils réels. Phase 3 : les autres modules par lots, comme leur port Windows.

### PWA-2b — suite de la phase 1 (09/11/2026, après « Oui » du client)

**Fait** (détail et fichiers : `agrierp_flutter/CLAUDE.md`, « PWA-2b ») : (1) cause de la synchro incrémentale lente MESURÉE et corrigée — un `await insert` par compte du plan comptable (73 s sur 95,6 s de page 1) → une rafale `batch` ; **avant / après dans Chromium : plan comptable 73 s → 0,09 s, page 1 95,6 s → ≈ 22 s (session neuve, rendu logiciel) / 0,7 s (régime établi), reconnexion → synchronisé 134 s → 1,5 s** ; garde de performance en nombre d'instructions ; (2) synchro automatique au navigateur (ouverture, `online`, retour de focus avec anti-rebond de 30 s, jamais en parallèle) ; (3) tableau de bord relu seul à la fin d'un tirage (web et natif) ; (4) sauvegarde complète téléchargée (JSON de toutes les tables, aller-retour prouvé) ; (5) justificatifs en IndexedDB, envoyés par `/api/sync/receipts` ; (6) vente de caisse jouée hors ligne dans Chromium puis synchronisée (une vente, stock −1, trésorerie +25 000, rien de doublé) ; (7) garde-fous Windows (tests `en_tete_accept_json`, `garde_imports_web`) ; (8) mise à jour contrôlée du service worker (bandeau, preuve Chromium) et verrou `navigator.locks` entre onglets.
**Reste** : restauration de sauvegarde au web (refusée, motif français) ; latence par instruction des ≈ 60 absorbeurs sous fil principal saturé (≈ 22 s en rendu logiciel) ; deux vrais onglets concurrents ; Safari iPhone / iPad, Firefox, Edge, appareil réel, Apache ; build Windows non rejoué (pas de Windows ici : résolution `drift_flutter` / SDK Dart ≥ 3.13 à confirmer) ; `--wasm` ; phase 2 (pilotes Stocks, Fournisseurs, Ventes) inchangée.

### PWA-2c — fin de la phase 1 (09/11/2026, après « Oui » du client)

**Fait** (détail et fichiers : `agrierp_flutter/CLAUDE.md`, « PWA-2c ») : (1) **écritures des absorbeurs regroupées** — tirage incrémental à charge faible de 68 tables : **228 → 134 instructions** (une seule transaction par page au lieu d'un point de sauvegarde par absorbeur : −82 messages ; marques de resynchronisation en une lecture ; fusions pures sans rien exécuter pour une charge vide ; `IN (...)` + une rafale `batch` pour fiches journalières, pointages, ventes, achats, journal) ; dans Chromium le tirage initial qui ne se terminait pas en plusieurs minutes (912 fiches × 3 instructions) passe à 0,46 s pour les fiches et ≈ 11,4 s d'absorption pour les 7 pages ; reconnexion → synchronisé 1,0 à 1,5 s (inchangé) ; garde : second cas de `absorption_performance_test` ; (2) **deux vrais onglets** Chromium (`outils/e2e_poste_deux_onglets.mjs`) : base partagée par le worker SQLite partagé, verrou `navigator.locks` (une synchro à la fois, aucun chevauchement, l'autre onglet attend), saisie de A visible dans B, deux saisies simultanées ni perdues ni doublées, mise à jour du service worker à deux onglets (l'autre onglet est PRÉVENU, jamais rechargé de force) ; (3) **restauration de sauvegarde au web** : fichier JSON complet, état sûr (aucune ligne `pending` / `conflict`), contrôle strict (schéma, tables, colonnes), une transaction, confirmation « RESTAURER », rechargement ; mutation prouvée ; (4) **sondage léger** `/up` (3 s, jamais en cache) avant la synchro au retour en ligne / de focus, échec = hors ligne sans erreur ; indicateur « Hors ligne / En attente (N) / Synchronisé » à la barre supérieure du poste web.
**Suite PWA-2c (fait)** : les huit absorbeurs lents (Créances, Prophylaxie, Sujets, Rations, Relevés, Revenus de bande, Transformations, Calendrier vétérinaire) sont en rafales `batch` : **224 → 156 instructions** (borne < 165, mutation prouvée), 0,3–2,4 s → ≤ 0,17 s dans Chromium, tirage complet 26–33 s → 20–22 s.
**Suite 2 (fait)** : les neuf dernières tables (Fiches, Clients, Avances, Fournisseurs, Courriers, Documents, Archives, Entreprise, Journal) en rafales : **209 → 164 instructions** (borne < 175, mutation prouvée), 0,3–0,45 s → ≤ 0,17 s dans Chromium.
**Reste** : Fiches journalières et Journal ≈ 0,43 s au premier tirage (gros volumes), Modules / Rôles / Dépenses ≈ 0,3 s ; Safari iPhone / iPad, Firefox, Edge, appareil réel, Apache ; build Windows non rejoué (pas de Windows ici) ; `--wasm` ; phase 2 (pilotes Stocks, Fournisseurs, Ventes) inchangée.

## PWA-1b ✅ (09 et 10/11/2026) — la caisse complète du navigateur : livraison facturée, vente sur avance, client créé hors ligne, sujets vivants sur bande source
⚠️ NOMS : « PWA-2 » désigne le poste Flutter web (livré en PWA-2, 2b, 2c). La « caisse hors ligne complète » de la table de PWA-1 s'appelle **PWA-1b** (et non PWA-2) ; la ligne de la table « Phases suivantes » porte ce nom. Ordre du client : « Lance PWA-2 et PWA-3 » = PWA-1b puis PWA-3.
Décisions CAISSE-1/2/3 du plan : NON validées par le client ; aucune n'est bâtie (ni appareil/PIN renforcé, ni reçu provisoire, ni refus au-delà du seuil de prix). **Mise à jour (09/11/2026)** : CAISSE-1 ✅ COMPLET — volet animalier (DV-31 : un animalier seul active le mode hors ligne et saisit ses fiches ; Gate unique `utiliser-mode-hors-ligne` = `manage-ventes` OU `manage-elevage` ; l'écran de la PWA suit les droits du compte : caisse = `manage-ventes`, fiches = `view-elevage`, écriture = `manage-elevage`) et type d'appareil (DV-32 : « entreprise » par défaut, PIN de 4 à 6 chiffres ; « personnel », PIN de 6 chiffres obligatoire et tout effacé à la déconnexion). CAISSE-2 ✅ (DV-33 : reçu provisoire imprimable d'une vente hors ligne, sans numéro légal, mention « Facture n° attribué à la synchronisation. »). `sw.js` v20. CAISSE-3 (refus au-delà du seuil de prix) reste côté client.
- **Livraison facturée** (modale « Livraison » de la caisse web, mêmes libellés) : frais entiers (demi-unité vers le haut, jamais négatifs) ajoutés au total ; les autres modes (gratuite, client, incluse) n'ajoutent rien. Le SERVEUR (`SyncController::pushSales`) accepte désormais `delivery_mode`, `delivery_fee`, `delivery_address`, `delivery_contact` (validés, 255 caractères), RECALCULE `delivery_fee` (seulement pour « facturée ») et `delivery_in_total`, et exige un total qui inclut les frais. Le poste Flutter n'envoie pas ces clés : comportement inchangé.
- **Vente sur avance** : mode « Déduire de l'avance » (libellé du web), client exigé avec la phrase de la caisse web. Comme au web, la vente est enregistrée avec le mode `avance` ; l'imputation de l'avance à une vente reste l'écran des avances (la caisse web n'impute rien à la vente).
- **Client créé hors ligne** : bouton « + » (nom obligatoire ≤ 150, téléphone ≤ 30, IFU de 13 chiffres facultatif — l'IFU est une extension du « + » du web, qui ne demande que nom et téléphone) ; fiche chiffrée par le PIN (`referentiels`, table `clients_a_envoyer`, aucun changement de schéma IndexedDB) ; envoyée AVANT les ventes (`customers`), idempotente par UUID ; le serveur peut la FUSIONNER avec une fiche connue (`merged`) : les ventes en file passent à l'identifiant du serveur ; refus motivé gardé et journalisé, jamais renvoyé en boucle.
- **Produits rattachés à une espèce (10/11/2026) ✅** : tirage (sous les droits de lecture du compte, tout chiffré par le PIN) des bandes (`livestock_lots`), des fiches journalières (`livestock_daily_entries`, familles paginées accumulées sur toutes les pages) et des rémanences (`veterinary_withdrawal_periods`, remplacées à chaque tirage) ; « Bande Source * » obligatoire pour un sujet vivant (phrase du web), bandes proposées = même espèce, actives, non vides, avec leur effectif ; bande sous rémanence refusée à l'ajout et à la validation (phrases du web) ; volailles : refus avant l'enregistrement avec les motifs EXACTS du serveur (départ non saisi, vente avant le départ, produit sans catégorie / sans stade d'une autre famille) ; la vente en attente est REJOUÉE au-dessus de la copie tirée (bande et fiche du jour mises à jour comme le serveur le fera, jamais écrites dans la copie tirée) ; un second tirage suit l'accusé des ventes (l'effectif de la bande ne « remonte » pas). Le serveur rejoue et reste juge (`RecordSaleOnFicheElevageAction`). Le message « se vend en ligne » est retiré. Jour = jour du Bénin (UTC+1).
- Preuves de ce volet : `chaine-effectif.js` (port de `RecordSaleOnFicheElevageAction::execute` / `refusDesLignes` / `recalculerEnCascade`, `LivestockDailyEntry`, `EffectifParCategorieService::recalculerChaine` explicite, `etatPourJour`, `refusDuPassage`) avec PARITÉ EXÉCUTÉE contre le vrai PHP sur 600 scénarios (base SQLite en mémoire, migrations réelles) et 10 mutations détectées ; `tests/Js/elevage-hors-ligne.test.mjs` (8) ; essai Chromium : bande à 38 sur l'appareil avant l'envoi, fiche du jour et bande à 38 au serveur après la synchronisation, rien ne remonte au tirage.
- Preuves : parité EXÉCUTÉE contre le vrai PHP (frais retenus et total égaux à `PosInterface` sur 320 cas, total accepté par `verifierCoherenceDuTotal`, validation d'un client égale à `CustomerCatalogService` + `MotifsRefusPush`, phrases et motifs), 12 essais de comportement (`tests/Js/caisse-complete.test.mjs`), `PwaCaisseCompleteTest` (6), essai Chromium `tests/Js/e2e/caisse-complete.e2e.mjs` (10 étapes : « + » hors ligne, avance, livraison facturée, client avant sa vente, fusion) ; les 15 étapes de `hors-ligne.e2e.mjs` restent vertes. `sw.js` : VERSION `agrierp-v8`.
- **Non vérifié** : Safari / iPhone, appareils réels, plusieurs onglets simultanés avec client en file.

## PWA-3 ✅ COMPLET (09/11/2026) — REPRIS sur décision du client (« Reprendre la fiche lapins ») : fiches LAPINS (É1 à É5), PORCS, ESCARGOTS, VOLAILLES REPRODUCTEURS et VOLAILLES PONDEUSES COMPLÈTES

> **FICHE VOLAILLES REPRODUCTEURS ✅ (09/11/2026)** : première des deux familles de volailles (VOL-1). Hors vue commune lapins / porcs : module propre `fiche-volailles.js` (saisie : trois catégories Reproducteur / Jeune / Poussin aux emplacements `repro` / `jeune` / `sevre`, **départ OBLIGATOIRE** avant toute journée — proposé d'après le stade par un bouton, jamais prérempli — puis verrouillé, ventes par catégorie en LECTURE SEULE (posées par la caisse), passage Poussin → Jeune, couvoir : œufs couvés = `ponte_total`, poussins nés = `ne`, morts et dons par catégorie avec un total déjà enregistré conservé, rationnement `CategorieVolaille::tableauReproducteurs` (égalité STRICTE du libellé, 130 / 80 / 30 g de secours), autonomie `aviculture`, prophylaxie du jour, pesée en g avec GMQ ; refus dans l'ORDRE du PHP : bande, exercice clos, date, jour avant le départ, départ refusé ou manquant, passage, répartition, ventes non ventilées) et famille `REPRODUCTEURS_F` (aviculture HORS stade `ponte`, sélecteur « Bande / Lot Concerné » avec stade et effectif, 4 KPI avec légendes, tableau du mois PROPRE : Couvoir / Morts (total) / Effectif Final / Taux Mort % / Poids Général, sans colonne de traitements). Envoi : `ficheEnJson` ajoute les ventes par catégorie à 0 (chaque vente se range ensuite dans sa catégorie, une fois). Bouton « Fiches Reproducteurs ». Preuves : `fiche-reproducteurs.test.mjs` (garde Blade / PHP / `CategorieVolaille`, ordre des contrôles compris), parités contre le vrai `FicheReproducteurs` (mois : 120 scénarios de cette famille ; saisie et aperçu 600 dont ration et autonomie ; envoi sur le vrai `POST /api/sync/push` 400 ; prophylaxie un tiers des 600), mutations toutes détectées, e2e `FICHE_FAMILLE=reproducteurs node tests/Js/e2e/fiche-lapins-saisie.e2e.mjs` (10 étapes : départ proposé, refus du départ faux, rechargement hors ligne, prophylaxie, retour réseau, exercice clos). `sw.js` : `agrierp-v17`. **Fiche PONDEUSES : voir le bloc suivant.**

> **FICHE VOLAILLES PONDEUSES ✅ (09/11/2026)** : seconde famille de volailles (VOL-2), PWA-3 est donc COMPLET. Module propre `fiche-pondeuses.js` (saisie : QUATRE stades Poussin ponte / Poussin en croissance / Poulette / Pondeuse aux libellés exacts du barème, emplacements `quatre` / `sevre` / `jeune` / `repro` ; **départ obligatoire à quatre stades** proposé par un bouton (tout l'effectif en Pondeuse) puis verrouillé ; ventes par stade en LECTURE SEULE (posées par la caisse) ; **trois passages** `passage_4_sevre`, `passage_sevre_jeune`, `passage_jeune_repro` ; œufs récoltés (`ponte_total`) et cassés (`ponte_casses`), commercialisables, taux de ponte, plateaux nets de 30 ; morts et dons par stade avec un total déjà enregistré conservé ; rationnement `StadePondeuse::tableau` (tranche d'âge ignorée, égalité stricte, repli 30 / 60 / 80 / 110) ; autonomie et prophylaxie du jour `aviculture` ; refus dans l'ORDRE du PHP) et famille `PONDEUSES_F` (aviculture stade `ponte`, 4 KPI : effectif, taux de ponte moyen, stock de plateaux, taux de mortalité ; tableau du mois propre : cheptel / ponte / stock d'œufs / traitements). `ficheEnJson` envoie `mort_4`, `don_4`, `passage_4_sevre`, `passage_jeune_repro`, `cat_depart_4`, `ponte_casses`, `vente_4` à 0 et la somme des morts / dons à quatre stades. Bouton « Fiches Pondeuses ». **Stock d'œufs — ce que le navigateur fait et ne fait pas** : le KPI « Stock Plateaux » et la ligne « Incrémentation Automatique du Stock » lisent le produit « Œufs » (premier par nom contenant « oeufs », comme `EggStockLedgerService::eggProduct`) du DERNIER TIRAGE des produits (limite : valeur du dernier tirage, absente si le produit n'a pas été tiré) ; les plateaux nets du jour sont un calcul pur ; **l'incrémentation du stock** (`RecordEggProductionStockAction`) est faite par le SERVEUR à l'envoi, à la création d'une fiche seulement (règle de `pushDailyEntries`) ; **SRH / TS / OS / stock final** (grand livre des mouvements) ne sont PAS calculés hors ligne : le tableau et la saisie affichent « — » et le disent. Le web n'a pas de poids moyen estimé (GMQ) sur cette fiche : la PWA non plus. Preuves : `fiche-pondeuses.test.mjs` (garde qui lit `fiche-pondeuses.blade.php`, `FichePondeuses.php`, `StadePondeuse`, `EggStockLedgerService`), parités exécutées contre le vrai `FichePondeuses` (mois : 100 scénarios de cette famille sur 500 ; saisie et aperçu 600 dont ration, autonomie, produit œufs, plateaux ; envoi sur le vrai `POST /api/sync/push` 400 ; prophylaxie un quart des 600), mutations toutes détectées, e2e `FICHE_FAMILLE=pondeuses node tests/Js/e2e/fiche-lapins-saisie.e2e.mjs` (10 étapes). `sw.js` : `agrierp-v18`.

> **FICHE ESCARGOTS ✅ (09/11/2026, un tour)** : PAS la vue commune. `FicheEscargots.php` et son Blade n'ont ni effectif par catégorie calculé, ni départ, ni passage, ni rationnement calculé, ni **prophylaxie du jour, ni autonomie alimentaire** (le Blade ne porte que deux blocs « sera alimenté … dès sa mise en œuvre » : rationnement et hygrométrie) : la PWA n'en invente donc aucun. Famille `ESCARGOTS_F` dans `fiche-familles.js` (écran du mois : 4 KPI dont taux d'éclosion `—` sans œufs, colonnes Naissains / Engraiss. / Bordés, poids en g) et module propre `fiche-escargots.js` (saisie : œufs pondus = `ponte_total`, naissains nés = `ne`, morts et dons saisis PAR catégorie (Reproducteur (Bordé), Engraissement, Naissain) mais seule leur SOMME est enregistrée, un total déjà enregistré sans répartition est conservé et signalé, trois effectifs saisis, pesée en g avec GMQ, refus : droit, aucune bande, exercice clos). **Module `helico` activé requis** (`modules_config`, désormais tiré en entier à chaque tirage) : sinon « Module Héliciculture non activé ». Envoi : mêmes états que les lapins ; `ponte_total` ajouté à la charge (`ficheEnJson`), aucune colonne de répartition. Bouton « Fiches Escargots ». Preuves : `fiche-escargots.test.mjs` (garde qui lit Blade, PHP et `module-pending`, y compris ce que le web n'a PAS), parités exécutées contre le vrai `FicheEscargots` (mois : 120 scénarios escargots, module activé / désactivé / absent ; saisie et aperçu 400 ; envoi sur le vrai `POST /api/sync/push` 300), 15 mutations propres aux escargots détectées, e2e `FICHE_FAMILLE=escargots node tests/Js/e2e/fiche-lapins-saisie.e2e.mjs` (8 étapes). `sw.js` : `agrierp-v16`.

> **FICHE PORCS ✅ (09/11/2026, un seul tour)** : les modules des lapins sont GÉNÉRALISÉS par famille (`fiche-familles.js` : espèce, libellés, ordre des champs et des colonnes, unité du poids, KPI, provende) au lieu d'être copiés ; `modeleFiche`, `rendreFiche`, `chargerJour`, `calculsSaisie`, `enregistrerJour`, `rendreFormulaire`, `protocoleDuJour`, `validerTraitements` prennent la famille (lapins par défaut, tests des lapins inchangés et verts). Ce qui DIFFÈRE des lapins, lu dans `FichePorcs.php` et `fiche-porcs.blade.php` : espèce `porciculture` et calcul `PORCS` (l'achat va au reproducteur) ; KPI « Truies / Verrats / Porcelets sous Mère » ; colonnes du mois dans l'ordre Truies Gest., Verrats, Porcelets, Engraiss. ; **poids en Kg** (saisie, affichage, GMQ, tableau à une décimale ; colonne toujours en grammes, ×1000 à l'enregistrement) ; clé de ration `CategorieRationPorc` (Reproducteur 2 000 g, Porcelet 300 g, Porc Marchand 600 g de secours ; ration du reproducteur aussi en Kg) ; tableau de provende dans l'ordre Porcelet, Porc Marchand, Reproducteur ; départ dans l'ordre Reproducteur, Porcelet, Porc Marchand ; libellés (« Passage de stade », « Suivi Clinique & Prophylaxie », « Observations ») ; filière « porcine ». Deux boutons dans la caisse : « Fiches Lapins » et « Fiches Porcs ». Envoi, prophylaxie, autonomie, déconnexion : la mécanique commune (éléments gardés par bande). Preuves : `fiche-porcs.test.mjs` (garde qui lit `FichePorcs.php`, le Blade et `CategorieRationPorc`), parités exécutées contre le vrai `FichePorcs` (écran du mois 240 scénarios dont la moitié de porcs, saisie et aperçu 600, envoi 400, prophylaxie 600, provende, autonomie), 10 mutations propres aux porcs détectées, e2e `FICHE_FAMILLE=porcs node tests/Js/e2e/fiche-lapins-saisie.e2e.mjs` (10 étapes). `sw.js` : `agrierp-v15`.

> **Limites levées + prophylaxie (09/11/2026)** : (1a) « Déconnecter cet appareil » (caisse et menu du web) compte les ventes, les fiches d'élevage, les soins vétérinaires et les clients créés hors ligne non envoyés : leurs listes sont chiffrées, seul leur NOMBRE est gardé en clair (`meta.autres_en_attente`, `compterTout`) ; abandon = saisir le nombre exact d'éléments. (1b) Seuil critique « constaté » : tirage de `purchase_orders` (`view-achats`) et de `purchases` réduits à `purchase_order_id` / `purchase_date` ; **le tirage des achats porte maintenant `purchase_order_id`** (clé ajoutée à `SyncController`, garde `SyncAchatsBonRecuTest` ; bénéfice aussi au poste Flutter, qui l'absorbe déjà) ; `delaisFournisseurs` / `seuilCritique` portent `ReleveTerrainService` (5 derniers bons « Aliments », délai bon → réception), parité exécutée (`parite-delais.test.mjs`, 300 scénarios, 6 mutations) ; sans `view-achats` la phrase « à confirmer en ligne » reste. (2) PROPHYLAXIE DU JOUR : `fiche-lapins-prophylaxie.js` (`protocoleDuJour` = `ProtocoleDuJourService` : jour de cycle depuis la mise en lot ou la dernière saillie, traitements dus, calendaires ; `validerTraitements` = `ValidateProphylaxisTreatmentsAction` + `AvecProphylaxieDuJour`) ; la validation crée un soin `pending` chiffré PAR traitement (`soins_a_envoyer`), joué localement avec sa rémanence (la bande n'est plus vendable hors ligne), envoyé clé `veterinary_records` (colonnes de `_soinEnJson`, après les fiches, avant les ventes ; le serveur crée la période de rémanence), états `pending` / `synced` / `conflict` + motif + reprise ou abandon ; champ « Observations » repris (il alimente `symptomes` du soin). `livestock_reproduction_events` tiré (famille paginée). Preuves : `parite-prophylaxie.test.mjs` (400 scénarios contre le vrai composant : protocole, refus, messages, soins, rémanences ; 7 mutations), `fiche-lapins-prophylaxie.test.mjs` (garde qui lit PHP et Blade), `fiche-envoi-synchro.test.mjs`, e2e `fiche-lapins-saisie` (10 étapes : valider hors ligne, retour réseau, soin et rémanence au serveur, rien en double). `sw.js` : `agrierp-v14`. Ordre des traitements de même jour de cycle : tri binaire (SQLite) ; MySQL (collation ci) peut ordonner autrement deux noms ne différant que par la casse.

> **É4 ✅ (09/11/2026)** : la FILE D'ENVOI des fiches lapins — `ficheEnJson` (mêmes colonnes que `_ficheEnJson` du poste ; jamais `effectif_final` ni `cat_eff_*` ; `vente` à 0 car chaque vente incrémente la fiche une seule fois, règle S-T9), `envoyerFiches` de `synchro.js` (clé `livestock_daily_entries` de `pushDailyEntries`, AVANT les ventes, après les clients). États dans `fiches_a_envoyer` : `pending` → `synced` à l'accusé seulement (la copie locale reste rejouée jusqu'à un tirage commencé plus de 5 s après l'accusé : l'effectif ne « remonte » pas), refus → `conflict` avec le motif français du serveur, journalisé, jamais renvoyé en boucle ; boutons « Renvoyer » (reprise manuelle) et « Abandonner cette saisie » sur la fiche ; tirage de confirmation après l'envoi. **Aucun changement serveur.** Preuves : `tests/Js/parite-fiche-envoi.test.mjs` + `parite/executer-fiche-envoi.php` (220 scénarios sur le VRAI `POST /api/sync/push` : fiches et cascade du serveur = celles du navigateur, second envoi sans effet, exercice clos refusé avec la phrase du web, doublon jamais dupliqué), `tests/Js/fiche-envoi-synchro.test.mjs` (machine d'états, ordre, mutations prouvées), e2e `fiche-lapins-saisie.e2e.mjs` (9 étapes).

> **É5 en partie ✅ (09/11/2026)** : (a) AUTONOMIE ALIMENTAIRE — `fiche-lapins-calculs.js` (`produitProvende`, `stockEnKg`, `seuilCritique`, `evaluerAutonomie`), le tableau « Rationnement & Provende » et les cinq états de `x-autonomie-alimentaire` (mêmes phrases) dans la fiche ; tirage de `field_survey_entries` (règle de terrain : seuil 3 j par défaut, `critique_jours` d'une règle) ; parité contre le vrai `AutonomieAlimentaireService` (`parite-autonomie.test.mjs`, 640 scénarios dont les cas limites). ⚠️ Règle de terrain VALIDÉE en mode « constaté » : le serveur prend le plus long délai des 5 derniers bons de commande reçus, que la PWA ne tire pas : l'écran dit « Seuil critique constaté sur les bons de commande : à confirmer en ligne. » (jamais une valeur inventée). Le stock est celui du dernier tirage (les ventes en attente ne le décrémentent pas ici, le serveur applique sa règle). (c) PARITÉ de la fiche : l'aperçu de la saisie (effectif, taux, catégories, avertissements, GMQ, provende, AUTONOMIE) est comparé au vrai composant sur 420 scénarios. (d) e2e hors ligne → saisie → en ligne → serveur identique (étapes 5 à 9 de `fiche-lapins-saisie.e2e.mjs`). **(b) NON FAIT — prophylaxie du jour validable hors ligne** : demande `ProtocoleDuJourService` (jour de cycle, calendaires non évalués, traitements dus), `ValidateProphylaxisTreatmentsAction` (soins `veterinary_records`, rémanences) et l'envoi des soins ; à faire en un tour dédié. `sw.js` : `agrierp-v13`. Autres restes : « Déconnecter cet appareil » ne compte pas encore les fiches en attente (comme les clients créés hors ligne) ; champ « Observations » non repris (jamais enregistré par `saveDay`).

> **É3 ✅ (09/11/2026)** : la SAISIE d'un jour de la fiche lapins hors ligne — `resources/js/hors-ligne/fiche-lapins-saisie.js` (transposition de `loadDay` / `saveDay` / `categoriesJour` : achats, nés, morts et dons par catégorie, sevrage, départ proposé d'après le stade puis verrouillé, effectifs M/F/Jeunes/S-mères, pesée et GMQ, avertissements et refus du web mot pour mot) câblée dans `fiche-lapins-ecran.js` / `caisse-app.js`. Ventes en lecture seule (venues de la caisse) ; droit `manage-elevage` (rôles admin et animalier) sinon lecture seule ; exercice clos refusé ; aucun refus n'écrit. La fiche est gardée chiffrée (`fiches_a_envoyer`, UUID du navigateur, `pending`), rejouée AVANT les ventes en attente ; la chaîne des jours suivants est recalculée par `chaine-effectif.js`. **L'ENVOI au serveur n'est PAS fait (É4)** : l'écran dit « Enregistrée sur cet appareil — en attente d'envoi. ». Preuves : `tests/Js/fiche-lapins-saisie.test.mjs` (garde qui LIT le PHP et le Blade), `tests/Js/parite-fiche-saisie.test.mjs` + `tests/Js/parite/executer-fiche-saisie.php` (420 scénarios contre le vrai `FicheLapins::saveDay` : saisie rechargée, aperçu, refus, fiches et cascade, effectif de la bande), `tests/Js/e2e/fiche-lapins-saisie.e2e.mjs`. Écarts : champ « Observations » (jamais enregistré par `saveDay`), prophylaxie du jour et autonomie alimentaire (É5), signalement D6 de l'ancienne répartition implicite non repris ; effets de stock faits par le serveur à l'envoi. `sw.js` : `agrierp-v12`.

> **Reprise (09/11/2026)** : le client a explicitement choisi de reprendre la fiche lapins (la suspension ci-dessous reste l'historique). **É2 ✅ livrée** : `resources/js/hors-ligne/fiche-lapins-ecran.js` (modèle `modeleFiche` + rendu DOM) câblé dans `caisse-app.js` / `caisse-hors-ligne.html` (bouton « Fiches Lapins » du bandeau, affiché seulement si le serveur sert les fiches) : en-tête, 4 KPI, sélecteurs bande / date / mois, bandeau de lecture seule d'un exercice clos, transferts du jour, tableau de 31 jours et cartes sous 640 px ; lecture seule, aucune saisie. Preuves : `tests/Js/fiche-lapins-ecran.test.mjs` (garde qui LIT le Blade, 5 essais, 5 mutations détectées), `tests/Js/parite-fiche-ecran.test.mjs` + `tests/Js/parite/executer-fiche-mois.php` (160 scénarios, ~4 900 jours égaux au vrai composant `FicheLapins` : KPI, taux, poids, traitements, mois, bandeau, transferts ; 3 mutations détectées), étape 14 de `tests/Js/e2e/caisse-complete.e2e.mjs` (ouverture hors ligne). Écart assumé : l'export PDF n'existe pas hors ligne (bouton grisé, « Export PDF disponible en ligne seulement. » — message propre à la PWA, le Blade n'en a pas). `sw.js` : `agrierp-v11`.

> **Décision du client (09/11/2026, « OUI ») : PWA-3 est CLOS dans ce plan.** Les fiches d'élevage hors ligne dans un navigateur sont déjà couvertes par le poste Flutter compilé pour le web (PWA-2, 2b, 2c : toutes les fiches, mêmes règles que le poste Windows) ; refaire la fiche lapins (Blade de 390 lignes, `FicheLapins.php` de 814 lignes, cinq traits, trois services) en JavaScript doublerait cette capacité pour un coût élevé. **Conservé** : `effectif-categories.js`, `chaine-effectif.js`, `fiche-lapins-calculs.js`, le tirage des bandes, fiches, rémanences, barèmes, prophylaxie, soins, transferts, provendes et exercices (tous prouvés contre le vrai PHP). **Reprise possible** si le client le demande, UNE ÉTAPE À LA FOIS : É2 écran, É3 saisie, É4 file d'envoi, É5 alerte d'autonomie + parité de la fiche + essai Chromium. Le détail ci-dessous est l'état exact au moment de la suspension.

(état au 11/2026 :) fiche LAPINS : É1 atteinte et complète ; É2 à É5 NON atteintes ; AUCUNE fiche livrée
Périmètre étroit demandé : la fiche lapins seule, par étapes. **Dernière étape COMPLÈTE : É1.** Aucune fiche n'est livrée (ni écran, ni saisie, ni file d'envoi) : le client a interdit toute fiche approximative.
**Livré et prouvé (socle, 10/11) :** `effectif-categories.js` (calcul d'une journée, départ, stade) et `chaine-effectif.js` (chaîne d'une bande : cascade d'effectif, catégories, `etatPourJour`, `refusDuPassage`, vente sur la fiche du jour) ; tirage des bandes, fiches et rémanences ; parités exécutées contre le vrai PHP (1 200 jours, 400 départs, 600 scénarios de chaîne).
**É1 ✅ (11/11) — tirage complémentaire sous `view-elevage`** : barèmes de rationnement (`feed_ration_standards`), prophylaxie (`prophylaxis_schedule_standards`), soins (`veterinary_records`, paginé), transferts (`livestock_transfers`, paginé), types de provende (`feed_types`), exercices (`fiscal_years`, lecture seule) ; chiffrés par le PIN, hors cache du service worker, lignes invalides refusées, les tables servies en entier (barèmes, prophylaxie, provendes, exercices) REMPLACÉES à chaque tirage (un barème corrigé au bureau ne se fusionne pas avec l'ancien). 2 essais + 2 mutations. `sw.js` VERSION `agrierp-v10`.
**Un morceau d'É3/É5 déjà prouvé : la provende du jour** (`fiche-lapins-calculs.js` : clé stable de rationnement `CategorieRationLapin`, ration × effectif par catégorie, total g et kg, catégorie inconnue = « — », valeurs de secours) ; parité exécutée contre le vrai `CategorieRationLapin` et le vrai `FicheLapins::getProvendeCalculationProperty` (400 jeux) ; 5 mutations détectées (`tests/Js/parite-fiche-lapins.test.mjs`).
**Reste à faire pour la fiche lapins (état exact)** — le Blade (390 lignes) et `FicheLapins.php` (814) font la fiche entière, plus 5 traits et 3 services : 
- **É2 ✅ (09/11/2026, voir ci-dessus)** — cahier d'origine : l'écran (en-tête, 4 KPI — effectif total, géniteurs M/F, naissances du mois, taux de mortalité —, sélecteurs bande / date / mois passé avec le bandeau de lecture seule d'un exercice clos (`AvecMoisDeFiche`, `AvecSoinsDuMois`), transferts du jour, tableau mensuel de 31 jours et cartes mobiles, export PDF) ; test de garde qui lit libellés, ordre des colonnes et messages dans le Blade.
- **É3 ✅ (09/11/2026, voir ci-dessus)** — cahier d'origine : la saisie (achats, nés, morts et dons par catégorie Reproducteur / Jeune / Sous-mères avec − / +, sevrage du jour, effectif de départ déduit puis verrouillé, effectifs M/F/Jeunes/S-mères, pesée et poids moyen / GMQ, observations), avertissements et refus (somme ≠ total, morts > veille, départ incohérent, passage refusé, fiche ancienne non ventilée) ; parité de la saisie entière ; jour du Bénin ; exercice clos refusé ; droit `manage-elevage`.
- **É4 ✅ (voir ci-dessus)** — cahier d'origine : file d'envoi `livestock_daily_entries` (UUID du navigateur, `pending` / `conflict`, reprise, motif renvoyé) avec la règle de `SyncController::pushDailyEntries`, recalcul de la chaîne des jours suivants après chaque saisie.
- **É5** : alerte d'autonomie alimentaire (`AutonomieAlimentaireService` : stock de provende en kg, `ReleveTerrainService::seuilCritiqueJours()` : demande de tirer le produit de provende et le seuil), prophylaxie du jour validable (`ProtocoleDuJourService`, soins), parité de la fiche entière, essai Chromium « saisie hors ligne → retour réseau → fiche au serveur, effectif identique », aide d'écran.
**Puis** escargots, porcs, volailles reproducteurs et pondeuses : livrés (voir les blocs « FICHE … » ci-dessus ; PWA-3 est ✅ COMPLET).

