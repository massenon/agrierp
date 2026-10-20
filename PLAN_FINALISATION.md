# PLAN DE FINALISATION — AgriERP

**Ferme École OLOUWACHEGOUN · état au 19/10/2026 · monorepo `massenon/agrierp`**

Ce plan ordonne ce qui reste à faire pour livrer un poste Windows **100 % autonome hors ligne**, fidèle à l'application web. Il s'appuie sur :
- les règles de [`DOCTRINE_PORTAGE.md`](DOCTRINE_PORTAGE.md) ;
- le journal des tickets `agrierp_laravel/README_SPRINT0.md` (tickets web jusqu'à 15.42, poste jusqu'à F0.95) ;
- `agrierp_flutter/AUDIT_FIDELISATION.md`.

> Convention : ✅ fait · 🔧 à faire · ❓ décision client requise avant de coder. Un ticket = une session, terminé seulement quand les tests sont verts des deux côtés et que le ticket est consigné dans `README_SPRINT0.md`.

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
- **Reste à vérifier.** La fiche Escargots n'a pas de test dédié (module `helico` à activer dans le test) ; ticket A1-bis.

### A2 ❓ Bandes « issues d'une bande » comptées deux fois

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

### A5 🔧 Autorisation des fiches journalières

- Les cinq méthodes `saveDay()` des fiches web n'appellent pas `$this->authorize('manage-elevage')`, contrairement à la règle du projet (« première ligne de toute méthode mutante »).
- Ajouter l'appel et un test par fiche, après vérification que chaque rôle qui saisit des fiches a bien `manage-elevage`.

### A6 ✅ Compilation avec le Flutter stable actuel

- `sync_engine.dart` ne compilait pas avec Dart 3.13 (promotion de nullité d'une variable capturée), alors que `pubspec.yaml` autorise ce SDK.
- **Corrigé** par une copie finale locale, sans changement de règle.
- 🔧 Figer la version de Flutter du poste de compilation (`.fvmrc` ou mention dans `build_windows.bat`) pour éviter la prochaine dérive.

### A7 ✅ Chemins Windows absolus dans les tests du poste

- ✅ Fait le 17/10/2026 : `test/chemins_depot.dart` et `outils/chemins.py` (variable d'environnement, puis monorepo, puis ancien chemin Windows). Suite du poste : 2 010 verts, 16 sautés (maquette absente, A8), 0 rouge.


- 19 fichiers de `agrierp_flutter/test` et `outils/` lisent `C:/laragon/www/agrierp/...` ou `C:/Projects/agrierp_laravel/prototype_html/...`.
- Dans le monorepo, ces chemins n'existent plus. Hors du poste du développeur, `export_comptabilite_test.dart` échoue (3 tests) et d'autres tests se mettent en saut (32 sautés).
- **Proposition :** un seul résolveur de chemins (`test/chemins_depot.dart`) qui pointe sur `../agrierp_laravel/`.

### A8 ❓ Le prototype HTML n'est pas dans le monorepo

- Les `CLAUDE.md`, les outils de fixtures et plusieurs tests s'appuient sur `prototype_html/`, qui n'a pas été importé dans `massenon/agrierp`.
- Sans lui, la fidélité « prototype » n'est plus vérifiable que sur le poste du développeur.
- **Décision :** l'ajouter au dépôt (`prototype_html/` à la racine), ou acter que la vue Blade est désormais la seule référence (Doctrine, article 0) et retirer les dépendances au prototype.

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
| 3.F1 | **F0.96** — fiche Lapins du poste : saisie ventilée (morts et dons par catégorie, passage sevré → jeune), miroir du ticket 15.41 | 🔧 Bloquant : tant qu'il n'est pas livré, une fiche du poste avec morts ou dons sur une bande « à départ » est **refusée** (D7). |
| 3.F2 | **F0.97** — fiche Porcs du poste : même chose, miroir du ticket 15.42 | 🔧 Bloquant (même motif) |
| 3.F3 | D6 tranchée le 17/10/2026 (bandes déjà saisies : corrigées par la chaîne, départ déduit du stade). Restent D5 (qui déverrouille un départ erroné), D15 (« Porc Marchand » / « Jeune porc »), confirmation de D2/D8/D9/D12 | ❓ |
| 3.F4 | Mise en service **simultanée** du serveur (15.39–15.42) et du poste (F0.95–F0.97) | 🔧 À planifier avec l'exploitant |
| 3.F5 | Tests de cascade pour Escargots et Reproducteurs en parité exécutée PHP ↔ Dart (`test/php_laravel.dart`) | 🔧 |
| 3.F6 | A2, A3, A4 ci-dessus (transferts, dons reçus, transformation) | ❓ puis 🔧 |
| 3.F7 | Suivi de reproduction : la mise-bas (`saveMiseBas`) n'alimente aucune fiche. Les nés vivants restent à saisir à la main dans la fiche du jour. Décider si la mise-bas écrit `ne` dans la fiche de la bande. | ❓ |

---

## Sprint B — Offline-first robuste et synchronisation

| # | Ticket | Statut |
|---|---|---|
| B1 | Écran **Synchronisation** (`lib/features/sync/synchronisation_screen.dart`) | ✅ existe : en attente, conflits avec motif, dernier état, bouton « Synchroniser ». |
| B2 | Synchronisation **déclenchée automatiquement** : au retour du réseau, à intervalle (15 min, configurable dans Paramètres du poste) et à la fermeture de l'application. Jamais bloquante ; hors ligne = état normal, pas une erreur rouge. | 🔧 |
| B3 | Écran Synchronisation : historique des dernières tentatives (date, poussés / tirés / refusés), filtre des conflits par table, relance d'un conflit après correction, export du journal pour le support. | 🔧 |
| B4 | Indicateur permanent dans `BarreSuperieure` : nombre d'enregistrements en attente et âge de la dernière synchronisation réussie. | 🔧 absorbé par **H2** |
| B5 | Sauvegarde locale de la base Drift (copie datée dans `Documents\AgriERP\sauvegardes`, rotation 7 jours) avant toute migration de schéma et chaque jour. | 🔧 |
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
| D1 | `agrierp_flutter/build_windows.bat` : enchaîne dépendances, génération Drift, analyse, tests, `flutter build windows --release`, copie du runtime VC++, puis installateur Inno Setup (`installer/agrierp.iss`) → `installer\Output\AgriERP-Setup-<version>.exe` | ✅ écrit le 17/10/2026, **pas encore exécuté sur une machine Windows** |
| D2 | Première exécution réelle sur le poste de compilation ; vérifier l'installation sur un Windows 10 vierge, sans redistribuable VC++ | 🔧 |
| D3 | CI GitHub Actions `windows-latest` : analyse, tests, build, installateur publié en artefact à chaque tag `v*` | 🔧 |
| D4 | Signature du code de l'exécutable (certificat éditeur), pour éviter l'alerte SmartScreen | ❓ achat du certificat |
| D5 | Mise à jour du poste : l'installateur réutilise le même `AppId` ; la base locale (profil utilisateur) n'est jamais touchée par une mise à jour ou une désinstallation | ✅ prévu dans `agrierp.iss`, 🔧 à vérifier en réel |

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
| H2 | **Bouton « Synchroniser » dans la barre supérieure + modale, poste** (PRD [`synchronisation-barre-superieure`](docs/prd/synchronisation-barre-superieure.md), absorbe B4) ; `pendingCount()` aligné sur les tables réellement envoyées (8 tables oubliées) ; « dernière synchronisation réussie » | ✅ 19/10/2026 |
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
| D-MECEF-1 | ❓ **À trancher avec le client et la DGI** : une facture acceptée par le dispositif MeCeF dont la réponse se perd serait déclarée deux fois à la retransmission — seule la future passerelle réelle peut l'empêcher (identifiant de la vente comme clé d'idempotence, ou interrogation avant retransmission). Et : faut-il un bouton de retransmission pour une vente restée « En attente » (aujourd'hui seulement pour « Erreur MeCeF ») ? |

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
| D-U14-2 | ❓ Export du journal d'audit au poste : non proposé (le poste ne détient que les 200 dernières lignes ; l'export ne pourrait pas être journalisé au serveur). Le garder au web seul, ou tirer la période entière ? |
| D-U14-3 | ❓ Taux de mortalité sans effectif (fiches du jour, Dashboard Élevage, Tableau de bord) : « 0,0 % » des deux côtés ; appliquer « inconnu = — » comme pour l'éclosion ? |
| D-U14-4 | ❓ Dépense saisie puis archivée au poste avant tout envoi : créée puis archivée au serveur (deux écritures, deux lignes d'audit), pour garder la trace — à confirmer (alternative : effacée du poste, rien n'est envoyé) |

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

**Questions nées d'EX3–EX5 (au client / au cabinet FAGUEZ, non tranchées)** — détail dans `README_SPRINT0.md` :
- **EX-Q1** : l'étape 2 ne solde que les classes 6 et 7 ; un compte de classe 8 (HAO) qui porte un solde rend l'à-nouveau déséquilibré, et la clôture est désormais refusée avec son motif (avant : erreur 500). L'étape 2 doit-elle solder aussi la classe 8 ?
- **EX-Q2** : paie (Q4) — la charge est datée du dernier jour de la période, **sauf** si le règlement a lieu avant (charge au jour du règlement, une seule écriture). Les deux écritures (par le 422) ne sont passées que quand les deux dates diffèrent. À confirmer.
- **EX-Q3** : au Journal, une écriture ne change plus d'exercice, même entre deux exercices ouverts (EF5 « vers un autre exercice ») : archiver puis ressaisir. À confirmer.
- **EX-Q4** : au plus deux exercices ouverts (R2) : si N n'est pas clôturé au 31/12/N+1, N+2 ne s'ouvre pas et toute saisie de N+2 est refusée (l'administrateur est prévenu). Est-ce voulu, ou faut-il une marge ?
- **EX-Q5** : « griser la date d'une dépense comptabilisée comme le montant » — ni le web ni le poste ne grisent le montant : le refus se fait à l'enregistrement, sous « Montant ». La date suit ce comportement ; le grisé relève d'EF10 (lot 2), à construire d'abord au web. → **Fait en EX7** : la date d'une dépense comptabilisée est grisée en modification, au web puis au poste, motif « Dépense déjà comptabilisée : sa date ne peut plus être modifiée. » en info-bulle ; le montant reste refusé à l'enregistrement (non grisé : à décider s'il doit l'être aussi).

**Questions nées d'EX6 (non tranchées)** — détail dans `README_SPRINT0.md` :
- **EX-Q6** : les **transferts entre bandes** (web et poste) ne sont jugés par aucun exercice au serveur, alors qu'ils écrivent les fiches des deux bandes ; au poste, la fiche du transfert part ensuite à l'envoi et le serveur la refuse si l'exercice est clos (transfert accepté, fiche refusée). Faut-il refuser le transfert lui-même dans un exercice clos (Q3 étendue), d'abord au web ?
- **EX-Q7** : les calendriers bornés (EF7) ne l'étaient qu'à la caisse ; EX6 a borné au web d'abord (`min`) la Saisie des Dépenses, les Dettes Fournisseurs, le remboursement, les Avances et l'Ajout de stock, puis le poste. Le sélecteur de date des **fiches d'élevage** n'est PAS borné (il sert aussi à consulter un jour passé, EF12) : le refus vient à l'enregistrement. À confirmer.

**Questions nées d'EX7 (non tranchées)** — détail dans `README_SPRINT0.md` :
- **EX-Q8** : un exercice clos grise les saisies des écrans PILOTÉS (EF9 : Journal, Achats, Dépenses, Stocks, Soins, Transferts, Rapprochement, Historique des ventes) ; la **caisse**, les **fiches d'élevage**, la **paie** et les écrans clients ne lisent pas l'exercice affiché (une vente se date du jour). Faut-il les griser aussi quand 2026 clos est affiché ?
- **EX-Q9** : les indicateurs « du mois » des écrans pilotés suivent le mois de référence de l'exercice affiché (le mois du jour, ou décembre 2026 lu en 2027) ; ceux qui ne sont pas « du mois » (Liste d'Achats, Historique des ventes au poste, totaux du Journal au poste) restent sur toute la ferme, comme avant. À confirmer.
- **EX-Q10** : la Déclaration TVA et le Rapport mensuel ne proposent plus que les mois de l'exercice affiché (avant : les 12 derniers mois glissants, à cheval sur deux exercices). À confirmer.

### Lot 2 — avant la clôture de 2026 (mars 2027)
| EX7 | Sélecteur d'exercice global web + poste, listes paginées dans l'exercice choisi, lecture seule (EF8–EF10) | ✅ 20/10/2026 (+ EX-Q5 : date d'une dépense comptabilisée grisée ; voir README_SPRINT0) |
| EX8 | Bilan et Compte de résultat N / N-1 au web puis au poste (EF11, Q5) ; fiches d'élevage des mois passés (EF12) | 🔧 |

### Lot 3 — avec la clôture de 2026
| EX9 | Archive figée de l'exercice à la clôture, hors purge des 30 jours, conservée 10 ans (Q6, à confirmer par FAGUEZ) ; Réinitialisation interdite après une vraie clôture (Q8) ; journal d'audit (EF13, EF14) | 🔧 |
