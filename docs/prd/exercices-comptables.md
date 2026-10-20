# PRD — Bascule et clôture d'exercice, navigation N / N-1 / N+1 (web et poste)
**Statut :** brouillon · **Date :** 2026-10-20 · **Ticket(s) :** à créer (skill `plan`, préfixe EX) ; reprend la question client Q4 « historique des exercices antérieurs » (`agrierp_flutter/AUDIT_FIDELISATION.md:1020`) et D-U14-1 (`PLAN_FINALISATION.md`)

> **Construit d'abord sur le web** (Doctrine, article 0 et article 5), puis porté au poste à l'identique. La clôture elle-même reste au web seulement (`DOCTRINE_PORTAGE.md:36` : « clôture d'exercice = jamais synchronisée ») ; le poste **affiche** l'état des exercices, **refuse** les saisies dans un exercice clos et **consulte** N-1.
>
> ⚠️ **Échéance ferme : 01/01/2027.** Sans le lot 1 (§ 11), toute vente, dépense, achat et paie est bloqué dès le 1er janvier (défaut C2 ci-dessous).

## 1. Problème

Le client demande deux choses : vérifier qu'au passage de N à N+1, **toutes les données des modules restent enregistrées et consultables** au web et au poste ; et pouvoir **naviguer entre les exercices** (N, N-1, N+1) comme dans un PGI, avec un exercice clos en lecture seule, deux exercices ouverts en même temps au début de l'année, et des états comparatifs N / N-1.

**Vérification faite le 20/10/2026.** Un test Feature jetable a rejoué une vraie année : en 2026, saisie au Journal, vente en caisse, dépense, achat, ajout de stock, fiche d'élevage et paie de mai ; puis une saisie le 10/01/2027 ; puis la clôture de 2026 le 15/03/2027 par le vrai parcours Livewire (étapes 1, 2 et 3). Une lecture complète du poste et de `SyncController` a complété ce test. Résultat :

- ✅ **Aucune donnée n'est perdue.** La clôture ne supprime ni n'archive rien : elle touche seulement `accounting_entries.is_locked` et `fiscal_years`. Les volumes de 2026 sont identiques avant et après. Les données de 2026 restent visibles au web dans l'Historique des ventes, les Dépenses, les Achats, les Mouvements de stock, le Journal (avec cadenas), le Grand Livre, la Paie (05/2026) et le Rapport Élevage. Au poste, aucune purge ne dépend de l'année : ventes, achats, dépenses, paie, fiches, mouvements et journal descendent en entier.
- ❌ **C1 — Après la clôture, les soldes de bilan sont comptés deux fois.**
  - **Mesuré :** la caisse vaut réellement 901 592 F, mais le Bilan, les États financiers et la Balance « exercice 2027 » affichent **1 803 184 F**.
  - **Pourquoi l'écran ne le signale pas :** le Bilan reste « équilibré » (actif = passif), parce que l'erreur est la même des deux côtés.
  - **Cause :** les états cumulent toutes les écritures depuis l'origine, **et en plus** l'écriture d'à-nouveau du 01/01/N+1 (`FinancialReportService.php:148, 387, 566-571`). Le TAFIRE est touché aussi.
  - **Au poste :** il applique la même règle (`comptabilite_repository.dart:365-392`), donc subit le même doublement.
- ❌ **C2 — L'exercice N+1 n'existe qu'une fois N clôturé.**
  - **Mesuré :** le 10/01/2027, une vente en caisse et une dépense échouent sur une **erreur 500** (`NoOpenFiscalYearException` non captée), et rien n'est enregistré.
  - **Pourquoi :** aucune tâche ne crée l'exercice au 1er janvier (`routes/console.php`). L'assistant de démarrage, qui sait l'ouvrir, disparaît une fois la mise en route terminée (`AssistantDemarrage.php:30-34`).
  - **Conséquence à la ferme :** clôturer en mars, après le bilan, est la pratique normale. Elle bloquerait donc la caisse de janvier à mars.
- ❌ **Un exercice clos n'est pas en lecture seule.**
  - **Le serveur refuse :** une vente, un achat, une écriture manuelle ou une dépense datés dans un exercice clos. La dépense est refusée par une erreur 500.
  - **Le serveur accepte quand même :**
    - un ajout de stock daté du 20/12/2026 ;
    - une fiche d'élevage du 22/12/2026, au web comme envoyée par le poste ;
    - la paie de 11/2026, dont l'écriture est datée du 15/03/2027 ;
    - le déplacement au Journal d'une écriture 2027 au 15/12/2026, alors que `fiscal_year_id` reste 2027 ;
    - le passage d'une dépense comptabilisée au 01/02/2027, alors que son écriture reste au 10/06/2026 ;
    - l'archivage de l'à-nouveau 2027.
  - **À l'écran,** seul le Journal remplace les boutons par un cadenas. Partout ailleurs, les boutons « Modifier » restent actifs.
- ❌ **Il n'y a ni navigation N / N-1 ni comparatif.**
  - Aucun sélecteur d'exercice n'existe, ni au web ni au poste. Le seul est le « ‹ année › » de l'écran Clôture.
  - La Balance et les États financiers sont figés sur l'exercice ouvert le plus récent (`BalanceGenerale.php:47-76`, `EtatsFinanciers.php:55-76`, poste `comptabilite_repository.dart:303-304`) : une fois 2027 ouvert, **2026 ne s'affiche plus**.
  - Aucune colonne N-1.
  - Plusieurs listes sont plafonnées sans filtre de date :
    - au web : Journal 100, Ventes 100, Stocks 100, Soins 50 ;
    - au poste : Soins 50, Transferts 100.
    - Avec le volume, l'année N y devient invisible.
- ❌ **La conservation n'est pas assurée.** Les sauvegardes quotidiennes sont gardées **30 jours**, puis tout le dossier est vidé (`GenerateDatabaseBackup.php:36, 79-91`). Il n'y a pas d'archive figée de l'exercice à la clôture.

## 2. Existant

| Sujet | Web | Poste |
|---|---|---|
| Modèle | `fiscal_years` : `id` UUID, `year` unique, `start_date`, `end_date`, `status` (`ouvert`/`cloture`), `closed_at`, `closed_by`, `step1_confirmed_at`. `FiscalYear::current()` = exercice ouvert le plus récent (`FiscalYear.php:43-46`) | Table `FiscalYears` (`app_database.dart:812-823`) : `id`, `year`, dates, `status` ; remplacée à chaque tirage (`sync_engine.dart:2205-2230`) |
| Création d'un exercice | Seeder ; clôture de N (`ClotureExercice.php:410-417`) ; assistant de démarrage (`AssistantDemarrage.php:44-68`) | Jamais (lecture seule) |
| Clôture | 3 étapes (`ClotureExercice.php`) : 1 = simple confirmation (l.327-338) ; 2 = solde des classes 6-7 au 131/139 le 31/12 (l.340-395) ; 3 = crée N+1, écrit l'à-nouveau `ran` au 01/01/N+1 avec les classes 1-5, verrouille N, passe N à `cloture` (l.397-464). **Aucun garde** à l'étape 3 (échéance, étapes 1-2, N-1 clos) ni try/catch | Carte « Clôture » non embarquée, motif affiché (`comptabilite_screen.dart:75-79`) |
| Réouverture (15.53) | `ReopenFiscalYearAction` : contre-passation `ran_reversal`, déverrouillage, refus si N+1 est clos ; `manage-modules` | — |
| Clôture mensuelle | `PeriodicClosure::isDateLocked` (Journal, vente datée) | Ne descend pas ; non jugée au poste (`caisse_repository.dart:101-103`) |
| Refus « exercice clos » | `AccountingEntryService::exerciceOuvertPour` (l.62-77) → `NoOpenFiscalYearException` / `ClosedFiscalYearException`. Captées : achats, avances, retours, immobilisations, `SyncController`. **Non captées :** dépenses, vente du jour en caisse, paie, ajustement de stock, clôture | Refus local **à la caisse seulement** (`caisse_repository.dart:87-142`, messages de `VerifySaleDateAction` mot pour mot). Ailleurs, le refus du serveur passe la ligne en `conflict` avec son motif |
| Messages | `ClosedFiscalYearException` : « Aucun exercice ouvert ne couvre la date 2026-01-05… » (date ISO, ne dit pas « clos ») ; `NoOpenFiscalYearException` : « Aucun exercice comptable ouvert… », alors que des exercices ouverts existent | Reçus tels quels, sauf pour les ventes |
| États | Balance : mois ou exercice **courant** ; Bilan : date d'arrêté libre ; Grand Livre : période libre ; États financiers : exercice courant ; Journal : 100 dernières écritures | Balance : mois ou exercice ouvert ; Grand Livre : période libre ; Journal : tout, sans période. États financiers non embarqués |
| Sauvegarde | `agrierp:backup` chaque jour à 02:00, rétention 30 jours ; export par module (`SauvegardeService`) | — |
| Tests | `ClotureExerciceTest`, `ReouvertureExerciceTest`, `ClotturePeriodiqueTest`, `SyncVenteDateeSocleTest`, `SyncEcrituresDateCreationTest`… **Aucun test d'état (Balance, Bilan, Grand Livre) sur N+1 après clôture** | `caisse_vente_datee_test.dart`, `balance_poste_test.dart`. **Aucun test de bascule N → N+1** |

Le prototype HTML (`cloture-exercice.html`, 5/27 au poste selon `AUDIT_FIDELISATION.md:364-377`) n'a pas de sélecteur d'exercice global.

## 3. Utilisateurs et rôles

| Rôle | Choisir l'exercice affiché | Ouvrir N+1 / clôturer N | Rouvrir N | Saisir dans un exercice ouvert | Saisir dans un exercice clos |
|---|---|---|---|---|---|
| admin | ✅ | ✅ (`close-fiscal-year`) | ✅ (`manage-modules`) | ✅ | ❌ jamais |
| comptable | ✅ | ✅ (`close-fiscal-year`) | ❌ | ✅ (comptabilité) | ❌ |
| caissier | ✅ (ses écrans) | ❌ | ❌ | ✅ (ventes) | ❌ |
| animalier | ✅ (ses écrans) | ❌ | ❌ | ✅ (élevage) | ❌ (voir Q3) |

Aucune permission nouvelle : la navigation suit les `view-*` existantes et l'ouverture de N+1 suit `close-fiscal-year`.

**Récits d'usage, par ordre de priorité**

1. Le 2 janvier, je suis caissier et je vends en caisse sans qu'un comptable ait clôturé l'année précédente, pour que la ferme ne s'arrête pas en attendant le bilan.
2. En février, je suis comptable et je passe dans l'exercice N encore ouvert les écritures d'inventaire (amortissements, provisions). Je veux voir les à-nouveaux de N+1 se mettre à jour d'eux-mêmes, pour ne pas les recalculer à la main.
3. Je suis administrateur et je veux qu'après la clôture le Bilan, la Balance et le Grand Livre de N+1 partent exactement des soldes de fin de N, pour présenter des comptes justes au cabinet.
4. Je suis comptable et je veux choisir « Exercice 2026 » en haut de l'écran, au web comme au poste, pour consulter la Balance, le Grand Livre ou les ventes de 2026 une fois en 2027.
5. Je suis comptable et je veux un Bilan et un Compte de résultat en deux colonnes N / N-1, pour voir l'évolution de la ferme.
6. Je suis n'importe quel utilisateur et je veux que, dans un exercice clos, chaque bouton de saisie soit grisé avec son motif, pour ne pas découvrir le refus après coup.
7. Je suis administrateur et je veux une archive figée de chaque exercice clos, conservée au-delà de 30 jours, pour répondre à un contrôle fiscal.

## 4. Exigences fonctionnelles

### P0 — sans elles, la bascule n'est pas sûre (lot 1, avant le 01/01/2027)
- **EF1 — Des états justes après la clôture (C1).** Une écriture n'est jamais comptée deux fois : le solde d'ouverture d'un exercice vient **soit** de l'à-nouveau **soit** de l'historique, jamais des deux (règle R1, § 5). Sont concernés au web : Bilan, Compte de résultat, États financiers, Balance, Grand Livre, TAFIRE, Rapprochement. Au poste : Balance et Grand Livre, avec une parité exécutée sur le PHP.
- **EF2 — Exercice N+1 ouvert sans attendre la clôture de N (C2).** N+1 existe au plus tard le 01/01/N+1 à 00:00, heure du Bénin, sans action humaine (règle R2). Un bouton « Ouvrir l'exercice N+1 » est aussi offert au porteur de `close-fiscal-year` à partir du 1er décembre de N. Deux exercices au plus sont ouverts en même temps (N et N+1).
- **EF3 — À-nouveaux provisoires.** Tant que N est ouvert, l'ouverture de N+1 est **calculée** à partir de N et marquée « À-nouveaux provisoires » sur chaque état. Elle suit toute écriture passée ensuite en N (règle R3). À la clôture, l'écriture d'à-nouveau définitive remplace le calcul **sans changer aucun chiffre**.
- **EF4 — Clôture gardée.** L'étape 3 est refusée, avec un message en français, quand :
  - l'échéance de N n'est pas passée ;
  - l'étape 1 ou l'étape 2 n'est pas faite ;
  - N-1 est encore ouvert ;
  - l'à-nouveau calculé est déséquilibré (aujourd'hui une erreur 500).

  Après la clôture, l'à-nouveau de N+1 est verrouillé : ni modifiable ni archivable au Journal (défaut É3).
- **EF5 — Exercice clos = rien ne s'y écrit, au serveur.** Toute saisie, modification ou archivage **datés** dans un exercice clos est refusé, au web comme à l'envoi du poste, avec le même message (règle R4). Sont aussi couverts les trous constatés :
  - l'ajout et l'ajustement de stock ;
  - les fiches d'élevage (selon Q3) ;
  - la paie (selon Q4) ;
  - le changement de date d'une écriture au Journal vers un autre exercice, ou vers un exercice clos ;
  - le changement de date d'une dépense comptabilisée (selon D-U14-1).
- **EF6 — Plus aucune erreur 500 liée aux exercices.** Toute `NoOpenFiscalYearException` ou `ClosedFiscalYearException` devient, au web, un message sous le champ ou un toast. Sont visés : dépenses, caisse (vente du jour comprise), paie, stock, clôture. Les deux messages sont réécrits en français clair, avec la date au format JJ/MM/AAAA (R4).
- **EF7 — Refus local au poste, sur tous les écrans de saisie.** Le contrôle qui existe à la caisse (`refusDeDate`) est étendu aux achats, dépenses, avances, règlements, retours, remboursements, inventaires et ajouts de stock, et aux fiches selon Q3. Les messages sont ceux du serveur, mot pour mot. Le calendrier de chaque saisie est borné aux exercices ouverts connus.

### P1 — navigation et lecture seule (lot 2)
- **EF8 — Sélecteur d'exercice global.**
  - **Emplacement :** dans la barre supérieure, au web et au poste : « Exercice 2027 ▾ ».
  - **Contenu :** la liste de tous les exercices, chacun avec son statut (« Ouvert », « Ouvert — à-nouveaux provisoires », « Clôturé »).
  - **Choix mémorisé :** dans la session au web, dans les paramètres locaux au poste.
  - **Par défaut :** l'exercice qui contient la date du jour.
- **EF9 — Ce que le sélecteur pilote.**
  - **Les états comptables :** Journal, Grand Livre, Balance, Bilan, Compte de résultat, États financiers et TVA. Leurs périodes sont bornées à l'exercice choisi, et l'option « Exercice complet » s'applique à **cet** exercice et non au dernier ouvert.
  - **La période par défaut des écrans de modules :** Historique des ventes, Facturation, Achats, Dépenses, Mouvements de stock, Soins, Transferts et Rapports. Les listes plafonnées (100, 50) deviennent paginées dans l'exercice choisi, pour que l'année N reste entièrement consultable en N+1.
- **EF10 — Mode lecture seule.** Quand l'exercice choisi est clos :
  - un bandeau dit « Exercice 2026 clôturé — lecture seule » ;
  - les boutons Nouveau, Modifier, Archiver et Enregistrer sont grisés, avec ce motif en info-bulle ;
  - la consultation, les exports et l'impression restent ouverts.

  Il s'agit d'un confort : la garantie, c'est EF5.
- **EF11 — Comparatif N / N-1 au web.** Le Bilan et le Compte de résultat affichent deux colonnes juxtaposées : « Exercice N » et « Exercice N-1 ». La colonne N-1 montre « — » quand N-1 n'existe pas, jamais 0. Le poste reprend ces états si Q5 est tranchée en ce sens.
- **EF12 — Fiches d'élevage d'un mois passé.** Les fiches web et poste permettent de consulter un mois antérieur de l'exercice choisi, en lecture seule si l'exercice est clos. Aujourd'hui, seul le mois courant est accessible (`FichePondeuses.php:177`, `mois_fiche.dart:209-238`).

### P2 — conservation (lot 3)
- **EF13 — Archive d'exercice.** À la clôture, le serveur produit une archive figée de N. Elle contient le Journal, le Grand Livre, la Balance, le Bilan et le Compte de résultat en PDF et en CSV, et une sauvegarde complète de la base à la date de clôture. Cette archive est **exclue de la purge de 30 jours**, conservée selon Q6, et téléchargeable depuis l'écran Clôture.
- **EF14 — Journal d'audit.** L'ouverture de N+1, la clôture, la réouverture, la création de l'archive et chaque refus pour exercice clos laissent une ligne d'audit, avec son libellé en français et sa copie au poste (`outils/libelles_audit.py`).

## 5. Règles métier et calculs

**R1 — Solde d'un compte à une date D de l'exercice F.**
- **Comptes des classes 1 à 5 :** solde = ouverture de F + mouvements de F du 1er jour de F jusqu'à D.
- **Comptes des classes 6 et 7 :** solde = mouvements de F seulement. Leur ouverture vaut toujours 0.
- **Ouverture de F :**
  - si l'exercice précédent est clos, elle vient de l'écriture d'à-nouveau de F (`source_type = ran`, nette de `ran_reversal`) ;
  - sinon, elle est calculée selon R3 ;
  - sans exercice précédent, elle vient de l'historique antérieur au premier jour de F (reprises d'avant le logiciel ; voir Q7).
- **Interdit :** additionner l'historique de F-1 et l'à-nouveau de F.

**Exemple calculé à la main (il deviendra le test).** Caisse = 531, banque = 521101.

| Date | Écriture | Débit | Crédit |
|---|---|---|---|
| 02/01/2026 | Apport | 521101 : 1 000 000 | 101 : 1 000 000 |
| 10/03/2026 | Vente comptant | 531 : 300 000 | 701 : 300 000 |
| 15/04/2026 | Énergie payée en caisse | 605 : 100 000 | 531 : 100 000 |
| 31/12/2026 | Étape 2 (solde 6-7) | 701 : 300 000 | 605 : 100 000 ; 131 : 200 000 |
| 01/01/2027 | À-nouveau (étape 3) | 521101 : 1 000 000 ; 531 : 200 000 | 101 : 1 000 000 ; 131 : 200 000 |
| 15/01/2027 | Vente comptant | 531 : 50 000 | 701 : 50 000 |

Bilan au 31/01/2027, exercice 2027 :

| Compte | Attendu | Affiché aujourd'hui (défaut C1) |
|---|---|---|
| Caisse 531 | **250 000** (200 000 + 50 000) | 450 000 (200 000 + 200 000 + 50 000) |
| Banque 521101 | **1 000 000** | 2 000 000 |
| Total actif | **1 250 000** | 2 450 000 |
| Capital 101 | **1 000 000** | 2 000 000 |
| Résultat 2026 (131) | **200 000** | 400 000 |
| Résultat 2027 en cours | **50 000** | 50 000 |
| Total passif | **1 250 000** | 2 450 000 — l'équilibre masque l'erreur |

Contrôle permanent : pour tout compte des classes 1 à 5, **ouverture de N+1 = solde de clôture de N**. Le contrôle de cohérence S-T6 vérifie déjà d'autres invariants ; celui-ci y est ajouté.

**R2 — Création de N+1.**
- Elle a lieu le 01/01/N+1 à 00:00, heure du Bénin, par la tâche planifiée, ou plus tôt par le bouton d'EF2.
- **Filet de sécurité :** si la tâche n'a pas tourné (cron absent), N+1 est créé à la première saisie datée de N+1, avant tout refus. Cela n'arrive que si N est l'exercice ouvert le plus récent et que la date tombe dans l'année qui suit.
- **Dates :** du 01/01 au 31/12 (exercice civil, comme aujourd'hui).
- **Refus :** N+2 n'est jamais créé tant que N est ouvert.
- Ni la clôture ni l'assistant de démarrage ne recréent un exercice qui existe déjà (`firstOrCreate`).

**R3 — À-nouveaux provisoires (N+1 ouvert, N ouvert).**
- **Calcul :** l'ouverture de N+1 pour un compte des classes 1 à 5 = son solde au 31/12/N, mouvements de N compris jusqu'à cet instant.
- **Résultat provisoire :** le résultat de N (classes 7 − 6) apparaît sur une ligne « Résultat de l'exercice N (provisoire) », au 131 s'il est positif, au 139 sinon. C'est ce que fera l'étape 2.
- **Rien n'est écrit au journal** tant que N n'est pas clos.

*Exemple.* Le 20/02/2027, avec 2026 encore ouvert, le comptable passe en 2026 une dotation de 30 000 (681 au débit, 2841 au crédit). L'ouverture provisoire de 2027 devient alors 2841 = 30 000 au crédit, et le résultat 2026 provisoire passe de 200 000 à 170 000. À la clôture de 2026, l'à-nouveau écrit 2841 = 30 000 et 131 = 170 000, mêmes chiffres. Le Bilan 2027 ne bouge pas.

**R4 — Exercice d'une saisie et messages.** Une saisie appartient à l'exercice qui contient **la date de l'événement** : date de vente, d'achat, de dépense, de comptage ou de fiche. Pour la paie, voir Q4. Messages, identiques au web et au poste :
- aucun exercice ne couvre la date : « Aucun exercice comptable ne couvre le 10/01/2027. Ouvrez l'exercice 2027 (Comptabilité › Clôture d'exercice). »
- l'exercice est clos : « L'exercice 2026 est clôturé : aucune saisie ne peut être datée du 20/12/2026. »

Les ventes gardent leur préfixe actuel « Vente refusée : » (`VerifySaleDateAction`).

**Effets comptables.** L'étape 2 et l'à-nouveau passent par `AccountingEntryService::record()`, comme aujourd'hui. Seuls changent l'ordre (gardes d'EF4) et la lecture des états (R1). Rien ne change pour les stocks ni pour les effectifs.

## 6. Hors ligne et synchronisation

- **`fiscal_years`** reste servie en entier à chaque tirage, et le poste ne la modifie jamais (refus à l'envoi : `SyncController.php:1899-1901`). La colonne `step1_confirmed_at` n'a pas à descendre. Les autres données nécessaires au poste (statut, dates, à-nouveau `ran`) y sont déjà.
- **Ouverture de N+1 un 1er janvier hors ligne.** Le poste ne connaît pas encore N+1. Il **accepte** alors la saisie du jour, comme la caisse aujourd'hui (`caisse_repository.dart:115-118`), et le serveur la reçoit après avoir créé N+1 (filet de R2). Elle ne sera donc pas refusée.
- **Refus du serveur.** La ligne passe en `conflict` avec le motif R4, comme aujourd'hui, et elle est visible dans « REFUSÉS PAR LE SERVEUR ».
- **Réouverture** (déjà en place) : les écritures horodatées redescendent, et les états du poste se recalculent.
- **Aucune purge par année au poste.** Cela reste ainsi. Les tables à fenêtre (`attendance_records` 60 jours, `audit_logs` et `notifications` 200 lignes, créances et dettes soldées) n'entrent pas dans le périmètre : elles ne servent pas aux états d'un exercice.
- **Parité exécutée.** Les fonctions de R1 et de R3 du poste sont comparées au PHP sur l'exemple du § 5 et sur l'essai à cinq postes.

## 7. Interface

**Web d'abord** (`x-datatable`, `x-modal`, `x-kpi-card`), puis poste (`CarteKpi`, `ModaleAgri`, `ToastAgri`).

- **Sélecteur.** Barre supérieure, à gauche du bouton « Synchroniser ». Libellé « Exercice 2027 ▾ ». Chaque ligne du menu porte un badge : « Ouvert » (vert), « Provisoire » (ambre), « Clôturé » (gris, cadenas `SymbolesAgri`).
- **Bandeau de lecture seule.** En haut du contenu : « Exercice 2026 clôturé — lecture seule. Les saisies se font dans l'exercice 2027. » avec un lien « Passer à 2027 ».
- **Écran Clôture d'exercice.**
  - Bouton « Ouvrir l'exercice 2027 » à partir du 01/12/2026.
  - Étapes 1 à 3 inchangées, chacune grisée avec son motif tant que sa condition n'est pas remplie (EF4).
  - Une fois l'exercice clos, bouton « Télécharger l'archive 2026 » (EF13).
- **États.**
  - Mention « À-nouveaux provisoires » sous le titre tant que N est ouvert.
  - Colonnes « Exercice N » et « Exercice N-1 » au Bilan et au Compte de résultat.
  - L'option « Exercice complet » de la Balance prend le libellé de l'exercice choisi : « Exercice 2026 ».
- **Poste.** Même sélecteur et même bandeau. Le poste n'a ni écran de clôture ni bouton d'ouverture.

## 8. Hors périmètre

- **Affectation du résultat** (compte 12x, réserves, dividendes, décision d'assemblée). Le résultat reste au 131 ou au 139, comme aujourd'hui. Ce sera un PRD séparé si le cabinet le demande.
- **Exercices décalés** (non civils) et plusieurs sociétés : la ferme est une seule entité, en exercice civil.
- **Clôture ou ouverture d'exercice au poste** : la doctrine l'exclut (`DOCTRINE_PORTAGE.md:36`). Le poste affiche et refuse, il ne décide pas.
- **Conservation hors du serveur** (cloud, disque externe automatique) : elle relève de l'hébergement cPanel. Le PRD fournit l'archive téléchargeable ; la copie externe reste une procédure, à documenter dans `GUIDE_DEPLOIEMENT.md`.
- **Tables à fenêtre du poste** (pointages, journal d'audit, notifications) : elles ne servent pas aux états d'un exercice.

## 9. Questions ouvertes pour le client

| # | Question | Proposition recommandée | Bloquante pour |
|---|---|---|---|
| Q1 | N+1 doit-il s'ouvrir **tout seul** le 1er janvier, ou seulement par le bouton du comptable ? | **Tout seul** (tâche + filet de R2) **et** bouton dès le 1er décembre : la caisse ne peut pas dépendre d'un geste oublié | Lot 1 |
| Q2 | Faut-il garder la clôture **possible avant** le 31/12 (cas d'erreur) ? | **Non** : l'étape 3 refusée avant l'échéance, car une clôture anticipée bloque la fin de l'année | Lot 1 |
| Q3 | Une **fiche d'élevage** (effectifs, morts, ponte) datée dans un exercice clos doit-elle être refusée ? Elle ne produit pas d'écriture, mais elle consomme du stock | **Oui, refusée** : le stock consommé de N est figé avec l'inventaire de N | Lot 1 |
| Q4 | Paie de décembre N validée en janvier N+1 : à quelle date passe la charge (661) ? | **Au 31/12/N** si N est ouvert (charge de N) ; le règlement à sa date en N+1. Si N est clos : refus | Lot 1 |
| Q5 | Le poste doit-il afficher le Bilan et le Compte de résultat N / N-1 (aujourd'hui non embarqués) ? C'est la question Q4 de l'audit, encore ouverte | **Oui, en consultation** : c'est la règle « web ↔ poste sans divergence », avec un calcul en parité exécutée | Lot 2 |
| Q6 | Durée de conservation des archives d'exercice ? | **10 ans** (Acte uniforme OHADA relatif au droit comptable), **à faire confirmer par le cabinet FAGUEZ** | Lot 3 |
| Q7 | Les reprises d'avant le logiciel (immobilisations datées avant le premier exercice) servent d'ouverture au premier exercice : faut-il les présenter comme un « à-nouveau initial » ? | **Oui** : une écriture `ran` initiale au premier jour du premier exercice, pour que R1 n'ait qu'un seul cas | Lot 1 |
| Q8 | Après une vraie clôture, la « Réinitialisation des données » (mode démonstration) doit-elle rester possible ? Elle efface aussi les exercices clos | **Non** dès qu'un exercice a été clos hors mode démonstration ; possible pendant les tests de recette | Lot 3 |
| D-U14-1 | La date d'une dépense déjà comptabilisée reste-t-elle modifiable ? | **Non** : verrouillée comme le montant. Sinon la dépense et son écriture changent d'exercice séparément (défaut constaté) | Lot 1 (EF5) |

## 10. Critères d'acceptation

**Laravel (Feature)**
- `BasculeExerciceEtatsTest` reprend l'exemple du § 5 : Bilan, Balance, Grand Livre et États financiers 2027 = 250 000 en caisse et 1 250 000 au total, **avant et après** la clôture de 2026 (mêmes chiffres en provisoire et en définitif). L'ouverture de 2027 est égale à la clôture de 2026 pour chaque compte des classes 1 à 5.
- `AnouveauxProvisoiresTest` reprend l'exemple R3 : la dotation passée en 2026 après l'ouverture de 2027 change l'ouverture provisoire, et la clôture écrit les mêmes montants.
- `OuvertureExerciceAutomatiqueTest` :
  - la tâche du 01/01 crée N+1 ;
  - le filet crée N+1 à la première vente du 02/01 sans cron ;
  - jamais N+2 tant que N est ouvert ;
  - jamais de doublon.
- `ClotureGardeeTest` :
  - un refus par garde d'EF4, avec son message ;
  - l'à-nouveau ne peut être ni modifié ni archivé.
- `ExerciceClosLectureSeuleTest` : un refus par trou constaté (stock, fiche selon Q3, paie selon Q4, déplacement d'écriture, date de dépense comptabilisée), au web **et** à l'envoi du poste, avec le message R4.
- `ErreursExerciceSans500Test` : dépense, vente du jour, paie, stock et clôture renvoient un message, jamais une erreur 500.
- `SelecteurExerciceTest` : Balance « Exercice 2026 » choisie en 2027 ; listes paginées ; boutons grisés dans un exercice clos.
- `ComparatifNMoinsUnTest` : deux colonnes ; « — » sans N-1.

**Poste (Flutter)**
- `bascule_exercice_parite_test.dart` : Balance et Grand Livre du poste égaux au PHP sur l'exemple du § 5 (parité exécutée), provisoire et définitif.
- `refus_exercice_clos_test.dart` : refus local avec le message du serveur, mot pour mot, sur chaque écran d'EF7.
- `selecteur_exercice_test.dart` : choix mémorisé, bandeau, boutons grisés, garde-fou Blade ↔ poste sur les libellés.

**Essai à cinq postes** : une graine qui traverse le 31/12 → 01/01, avec un poste hors ligne le 1er janvier. Invariant : ouverture de N+1 = clôture de N, et aucune ligne refusée à tort.

**Mutations** : retirer la règle « jamais historique + à-nouveau », le filet de R2 ou une garde d'EF4 doit faire rougir au moins un test.

## 11. Mesure du succès et calendrier

**Indicateurs**
- **Dès janvier 2027 :**
  - 0 vente, dépense ou achat refusé pour « aucun exercice » du 01/01 au 31/01/2027 (journal d'audit et `sync_conflicts`) ;
  - 0 erreur 500 liée aux exercices (`storage/logs`).
- **À la clôture de 2026 :** le contrôle « ouverture 2027 = clôture 2026 » est vert pour 100 % des comptes, et les chiffres du Bilan ne bougent pas au passage du provisoire au définitif.
- **Dans le trimestre :** le comptable consulte 2026 en 2027 sans contourner par le Grand Livre en période libre, au web et au poste.

**Lots**

| Lot | Contenu | Échéance |
|---|---|---|
| 1 | EF1 à EF7 (C1, C2, gardes, trous, messages, refus au poste) | **En production avant le 15/12/2026**, pour laisser 2 semaines de recette avant le 01/01/2027 |
| 2 | EF8 à EF12 (sélecteur, lecture seule, comparatif, fiches passées) | Avant la clôture de 2026 (mars 2027) |
| 3 | EF13 et EF14 (archive, audit) | Avec la clôture de 2026 |

**Dépendances**
- La tâche cron `schedule:run` doit tourner en production (`GUIDE_DEPLOIEMENT.md`) ; sinon, seul le filet de R2 joue.
- Les postes sont déployés **après** le serveur, comme pour toute livraison.
