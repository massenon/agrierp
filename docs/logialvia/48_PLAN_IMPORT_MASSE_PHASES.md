# 48 — Plan : importation en masse par tableur xlsx, phases IMPORT-2 et suivantes

> **USAGE**
>
> - **Quand l'utiliser.** Quand le client demande d'importer un module de plus que Stocks, Clients et Fournisseurs (les trois construits par IMPORT-1) : employés, plan comptable, barème de rationnement. Ce fichier est le plan de CHAQUE phase suivante, avec ses clés, ses droits, ses points de passage, ses règles de parité et ses prompts.
> - **Ordre.** Bloc 21 du guide (`GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md`) et `28_MODULE_RAPPORTS_EXPORTS_IMPORTS.md` (conception) → sections IMPORT-1 de `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md` (ce qui est LIVRÉ) → **ce plan** → `31_TESTING_QA.md` (T2 mutation, T3 parité). Une phase = une session, WEB D'ABORD puis le poste.
> - **Entrées requises.** IMPORT-1 livré (orchestrateur, `ModuleImport`, modèles xlsx versionnés, écran, parité) ; la réponse du client aux questions du § 4 ; le point de passage UNIQUE de chaque module (liste § 2).
> - **Sorties.** Par phase : une classe `ModuleImport`, une ligne de `ImportMasseService::REGISTRE`, un modèle xlsx versionné (`Modele_<Module>_v1.xlsx`) avec son empreinte, l'entrée d'écran, la transposition Dart (un seul écrivain par table), la parité exécutée, les mutations.
> - **Rien d'inventé.** Faits tirés de `agrierp_laravel/app/Services/Import/*` (relus), `docs/PLAN_FINALISATION.md` (section IMPORT-1 et table « Phases suivantes »), `agrierp_flutter/CLAUDE.md` (« IMPORT-1 »). Tout ce qui n'y figure pas est marqué « À DÉCIDER ».
> - **Interdits permanents.** Un module n'AJOUTE aucune règle métier ; jamais d'`INSERT` direct ni de `stock_qty` écrit à la main ; jamais d'écrasement d'une ligne existante (création SEULE) ; jamais de droit omis ; ne jamais commiter ; ne jamais `pkill`.

## 1. Ce qui existe (IMPORT-1, 08/11/2026) — à reprendre, pas à refaire

| Pièce | Fait (relu dans le code) |
|---|---|
| Orchestrateur | `App\Services\Import\ImportMasseService` : `analyser` (lecture, validation LIGNE PAR LIGNE, AUCUNE écriture : valides / ignorées / refusées, doublons du fichier compris) → `importer` (écriture ligne par ligne, une transaction par ligne, par le point de passage unique du module, chaque ligne REVALIDÉE au moment d'être écrite) → `rapportXlsx`. Droits vérifiés AU SERVEUR à chaque appel (`modulesAutorises`, `moduleAutorise`) ; l'écran masque en plus les modules refusés ; une ligne d'audit `import.masse` par fichier (module, compteurs dans `import_batches`, jamais le contenu) |
| Registre | `ImportMasseService::REGISTRE` : `stocks` → `ImportStocksService`, `clients` → `ImportClientsService`, `fournisseurs` → `ImportFournisseursService`. « Ajouter un module = une classe `ModuleImport` + une ligne du registre » |
| Contrat `ModuleImport` | `cle()`, `libelle()`, `description()`, `icone()`, `permission()` (droit `manage-…`), `moduleAudit()`, `version()` (augmente à tout changement de colonne), `empreinteAttendue()` (SHA-256 des en-têtes, garde `ImportMasseModelesTest`), `colonnes()` (liste de `ColonneImport`), `listes()` (listes déroulantes), `regles()` / `messages()` (CELLES du service métier), `cleLigne()`, `dejaPresente()`, `ecrire()`, `controlePrealable()` ; `idLigne()` = **UUID v5 déterministe** (`Uuid::uuid5(ESPACE_UUID, cle|cleLigne)`, `ESPACE_UUID = b3b0e2c4-6f5e-5b7a-9a4d-2f1c7a1d0e51`, la MÊME constante au poste) |
| Clés naturelles | `FusionReferentielsService::cleNaturelle` est le SEUL juge de « le même » pour `customers`, `suppliers`, `products` (`MODELES`) ; l'index est lu UNE fois par import |
| Modules livrés | Stocks (`manage-stocks`, point de passage `ProductCatalogService::creer`, stock initial par `AdjustStockAction`), Clients (`manage-ventes`, `CustomerCatalogService::creer`), Fournisseurs (`manage-achats`, `SupplierCatalogService::creer`) |
| Poste | écran `importation_screen.dart` + `importation_repository.dart`, `EcranPoste.importationMasse` (règle : au moins un de `manage-stocks` / `manage-ventes` / `manage-achats`) ; modèle xlsx GÉNÉRÉ hors ligne, mêmes feuilles / en-têtes / version que le serveur ; écriture par les dépôts propriétaires (`ProduitsRepository.creer`, `ClientsCreancesRepository.creerClient`, `FournisseursRepository.creerFournisseur` avec le paramètre `id`) ; le rapport est écrit dans `Documents\LogiAgriERP` (ou téléchargé au navigateur) ; glisser-déposer du fichier câblé depuis CONF-2 |
| Parité | `test/importation_parite_php_test.dart` fait fabriquer par le VRAI PHP les fichiers xlsx, les fait ANALYSER par `ImportMasseService`, lit CES fichiers avec le paquet `excel` : état, motif et identifiant de chaque ligne sont comparés ; `importation_parite_web_test` (libellés lus dans le Blade, registre, garde « aucune écriture hors dépôts propriétaires ») ; `importation_poste_test` |
| Décisions | création SEULE ; idempotence par clé naturelle + UUID v5 ; produit déjà au catalogue IGNORÉ sans stock ajouté ; ligne par ligne (pas de « tout ou rien ») ; fournisseurs sans e-mail ; pas de listes déroulantes natives au poste (le paquet `excel` n'a aucune API de validation) : la feuille « Listes » les remplace |

## 2. Les phases suivantes (table du plan, `docs/PLAN_FINALISATION.md`)

| Phase | Module (`cle` proposée) | Point de passage UNIQUE | Droit | Clé de ligne | Règles à reprendre MOT POUR MOT |
|---|---|---|---|---|---|
| **IMPORT-2** | Employés (`employes`) | `SaisieEmployeAction::creer` (web) ; poste : `PersonnelRepository.enregistrerEmploye` | `manage-rh` | nom + prénom + date d'embauche ; dates en AAAA-MM-JJ | `SaisieEmployeAction::regles()` : `first_name` ≤ 100 obligatoire, `last_name` ≤ 100 obligatoire, `position` ≤ 100 obligatoire, `hire_date` date obligatoire, `base_salary` nombre ≥ 0 facultatif, `status` dans `actif` / `conge` / `suspendu` (`STATUTS`) |
| **IMPORT-3** | Plan comptable (`plan_comptable`) : comptes complémentaires | `PlanComptableService::creer` (web) ; poste : `ComptabiliteRepository.creerCompte` | `manage-comptabilite` | code unique | `PlanComptableService::regles()` : `code` obligatoire ≤ 20 et **unique**, `label` obligatoire ≤ 255, `class` entier de 1 à 9 ; l'écran libelle la classe (« 6 - Charges », `libelleClasse`) |
| **IMPORT-4** | Barème de rationnement (`rations`) | écran Paramètres Élevage (`ParametresElevage`) ; poste : `ParametresElevageRepository.enregistrerRation` | `manage-elevage` | filière + libellé EXACT du barème | colonnes de `feed_ration_standards` : `species_code`, `stage_label`, `ration_g_per_day`, `is_active` ; unicité (filière, libellé) |
| **IMPORT-5** | Journal d'import au poste, mise à jour en masse, CSV de repli | À DÉCIDER | À DÉCIDER | — | le glisser-déposer du fichier est déjà fait (CONF-2) : la ligne du plan est antérieure |

⚠️ **Employés** ne sont PAS dans `FusionReferentielsService::MODELES` (`customers`, `suppliers`, `products` seulement) : `dejaPresente()` d'IMPORT-2 doit lire les employés ACTIFS par (nom, prénom, date d'embauche) SOUS UNE CLÉ NORMALISÉE documentée, comme `ficheNaturelle` le fait pour les trois autres ; ce n'est PAS un référentiel fusionné entre postes. À décider : l'archivé (`is_active = false`) compte-t-il comme « déjà présent » ? Le salaire est une donnée sensible : le rapport d'import ne le reproduit jamais (le journal ne garde que les lignes REFUSÉES, motif sans salaire).

## 3. Prompts

### I2-0 — Cadrage d'une phase (à lancer avant CHAQUE phase)

```text
RÔLE : analyste, aucune écriture de code.
CONTEXTE : lis docs/logialvia/48_PLAN_IMPORT_MASSE_PHASES.md (§ 1 et 2), docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md bloc 21, agrierp_laravel/CLAUDE.md et agrierp_flutter/CLAUDE.md (sections IMPORT-1), et les trois services existants (agrierp_laravel/app/Services/Import/Import{Stocks,Clients,Fournisseurs}Service.php) comme MODÈLES.
TÂCHES : pour le module <M> : (1) le point de passage UNIQUE et ses règles (regles(), messages()) ; (2) les colonnes du modèle xlsx (clé, libellé, obligatoire, type, aide, liste) ; (3) la clé naturelle et ce qui compte comme « déjà présente » ; (4) le droit ; (5) ce qui est sensible (n'apparaît jamais au rapport) ; (6) les questions au client (§ 4).
CRITÈRES D'ACCEPTATION : aucune règle inventée : chacune cite sa source (fichier:ligne) ; les écarts sont listés.
INTERDITS : coder ; deviner une règle absente des sources.
```

### I2-1 — Serveur : le module

```text
RÔLE : développeur Laravel (web d'abord : doctrine, la vue est le maître).
CONTEXTE : sortie de I2-0.
TÂCHES : (1) `App\Services\Import\Import<M>Service extends ModuleImport` ; colonnes, listes, `regles()` / `messages()` = CELLES du service métier, mot pour mot ; (2) `cleLigne()` normalisée (casse, espaces, accents : une seule fonction de normalisation) ; (3) `dejaPresente()` ; (4) `ecrire()` appelle UNIQUEMENT le point de passage unique (jamais un `INSERT` direct) ; (5) une ligne de `REGISTRE` ; (6) `version()` = 1 et `empreinteAttendue()` ; (7) l'entrée de l'écran Livewire, masquée sans le droit ; (8) tests : modèle (garde d'empreinte), aperçu, import, idempotence (relire le même fichier = 0 créée), droits, ligne refusée avec le motif du service, doublons du fichier.
CRITÈRES D'ACCEPTATION : T2 : retirer le contrôle de droit, la normalisation de la clé, ou la revalidation avant écriture fait rougir au moins un test.
INTERDITS : écraser une fiche existante ; omettre `AuditLog::record('import.masse', …)` ; commiter.
```

### I2-2 — Poste : transposition fidèle

```text
RÔLE : développeur Flutter (Windows = référence ; imports conditionnels pour le web).
CONTEXTE : I2-1 livré et vert. Modèle : agrierp_flutter/lib/features/importation/importation_repository.dart et test/importation_parite_php_test.dart.
TÂCHES : (1) transposer colonnes, normalisations de cellule, règles et messages du module, clés de ligne et UUID v5 (MÊME espace) ; (2) écrire par le dépôt PROPRIÉTAIRE de la table (jamais directement : un seul écrivain par table), sync_status `pending` ; (3) modèle xlsx généré hors ligne, même version et mêmes en-têtes que le serveur ; (4) parité EXÉCUTÉE : le VRAI PHP fabrique les fichiers (valides, doublons, déjà présentes, erreurs) puis les analyse ; le poste lit CES fichiers sur une base semée des mêmes fiches ; état, motif et identifiant comparés ligne à ligne ; (5) garde de lecture de sources : aucune écriture hors dépôts propriétaires ; (6) permissions : la règle de l'écran inclut le droit du module.
CRITÈRES D'ACCEPTATION : changer un motif ou une normalisation d'un seul côté fait rougir la parité.
INTERDITS : palier Drift (aucune table nouvelle) ; recopier la règle dans le test ; commiter.
```

### I2-3 — Recette et documentation

```text
RÔLE : relecteur adverse. Rejoue les mutations de I2-1 et I2-2, un fichier réel du client (anonymisé), puis met à jour `docs/PLAN_FINALISATION.md` (ligne de la phase), `agrierp_laravel/CLAUDE.md` et `agrierp_flutter/CLAUDE.md` (sections IMPORT-n), `docs/logialvia/28_…` et le bloc 21 du guide.
RAPPORT : fait / non vérifié (Excel lui-même : les fichiers ont été essayés avec PhpSpreadsheet et le paquet `excel`, pas avec Excel).
```

## 4. Questions au client (à poser avant I2-0)

1. Quels modules, dans quel ordre ? (le plan propose employés, plan comptable, barème.)
2. Employés : un employé archivé compte-t-il comme déjà présent ? le salaire de base est-il importé (donnée sensible) ?
3. Plan comptable : importe-t-on seulement des comptes COMPLÉMENTAIRES (le SYSCOHADA de base est semé), avec quel contrôle de classe ?
4. Barème : le libellé de stade doit être EXACT : le client fournira-t-il la liste officielle de ses stades ?
5. Questions Q-IMP restées ouvertes au plan : taille maximale (5 Mo / 5 000 lignes retenus provisoirement), option « tout ou rien », conservation du rapport (aujourd'hui au journal serveur), date d'ouverture du stock initial (aujourd'hui : jour de l'import), intrants distincts des produits vendables.

## 5. Contrôle de ce fichier

- Chaque classe et chaque méthode citée existe (`grep` dans `agrierp_laravel/app/Services/Import/`, `app/Actions/SaisieEmployeAction.php`, `app/Services/PlanComptableService.php`, `agrierp_flutter/lib/features/{rh,comptabilite,elevage,importation}/`).
- Aucune phase n'est promise « faite » : IMPORT-2 à IMPORT-5 ne sont PAS construites (`REGISTRE` n'a que trois entrées).
