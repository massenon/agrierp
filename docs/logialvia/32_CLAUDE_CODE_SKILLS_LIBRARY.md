# 32 — CLAUDE CODE SKILLS LIBRARY : prompts spécialisés pour générer chaque partie de LogiALVIA

> **USAGE**
> - **Quand l'utiliser** : à chaque ticket du web LogiALVIA (Laravel 12 + Livewire 3) et de son poste Flutter. On choisit le skill `SK-nn` qui correspond à la pièce à fabriquer, on le copie dans Claude Code (ou on l'installe comme vrai skill, section 1), on renseigne les « Entrées ».
> - **Ordre conseillé d'un ticket** (rythme du projet : un ticket = une session ; migration → modèle → Action/Service → composant Livewire → vue Blade ; puis poste) : SK-22 (PRD) → SK-23 (plan) → SK-01 (migration) → SK-02 (modèle) → SK-03 (Action) → SK-04/05/06/07/08 (écran) → SK-13 (tests) → SK-14/15 (parité, garde-fou) → SK-16/17/18/19/20 (poste et synchro) → SK-32 (revue de design) → SK-33 (audit sécurité).
> - **Entrées** : le fichier de module `20_MODULES_*.md`, les règles `15_REGLES_METIER.md`, le schéma `30_DATABASE_ENGINEERING.md`, les tests `31_TESTING_QA.md`, le design `04_UI_UX_DESIGN_SYSTEM.md`, les normes `03_DEVELOPMENT_STANDARDS.md`, l'architecture `02_ARCHITECTURE_WEB_ET_STACK.md`, le guide `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` (à lire, pas à réécrire).
> - **Sorties** : code, tests, documentation de ticket (le journal unique du projet).
> - **Règle d'or** : aucune règle métier inventée. Ce que les sources ne disent pas est marqué **« À DÉFINIR AVEC LE CLIENT »** avec une question. Les skills de filière (pisciculture, pintades, goliaths) en portent explicitement.
> - **Fichiers frères** : `README.md`, `01_MASTER_PROMPT.md`, `02_…`, `03_…`, `04_…`, `10_BRS…`–`15_REGLES_METIER`, `20_MODULES_*`, `30_DATABASE_ENGINEERING.md`, `31_TESTING_QA.md`, `40_PWA_HORS_LIGNE.md`, `41_MECEF_EMECEF.md`, `42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md`, `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`.

---

## Sommaire

1. Transformer un prompt en vrai skill `.claude/skills/<nom>/SKILL.md`
2. Contraintes communes à TOUS les skills
3. Chemins de référence (vérifiés)
4. Index des 36 skills
5. Les skills (SK-01 à SK-36)
6. Trois exemples complets de SKILL.md prêts à déposer
7. Questions ouvertes

---

## 1. Transformer un prompt en vrai skill

Les deux skills existants du dépôt, `/home/user/agrierp/.claude/skills/prd/SKILL.md` et `.claude/skills/plan/SKILL.md`, donnent le format. À reproduire.

**Arborescence** (dans le dépôt LogiALVIA, versionnée) :

```
.claude/skills/
  <nom-du-skill>/
    SKILL.md            # obligatoire
    references.md       # facultatif : chemins de référence longs, jeux de cas
    modele/             # facultatif : gabarits de fichiers à copier
```

**Front-matter** (obligatoire, entre deux lignes `---`) :

```yaml
---
name: logialvia-migration-domaine
description: <une à trois phrases, en français : CE QUE le skill produit + QUAND l'utiliser, avec les mots que l'utilisateur emploiera>
---
```

- `name` : minuscules, chiffres et tirets, identique au nom du dossier. Préfixe `logialvia-` pour éviter les collisions avec les skills génériques (`plan`, `prd` existent déjà : les réutiliser pour SK-22 et SK-23, ne pas les dupliquer).
- `description` : c'est elle qui déclenche le skill. Elle contient les verbes et les noms que l'on dira (« migration », « table », « schéma », « fiche journalière »). Une description vague = un skill jamais appelé.
- Corps : titre, « Avant d'écrire » (lectures obligatoires), « Étapes » numérotées, « Sorties », « Critères d'acceptation » vérifiables, « Interdits ». Tout en français.

**Règles de passage prompt → skill** :
1. Un skill = une pièce du projet (une migration, une Action, un écran). Pas de skill « fais tout ».
2. Les chemins de référence vont dans le skill (ou `references.md`) : un skill sans chemin réel hallucine.
3. Les critères d'acceptation sont des commandes ou des `grep` exécutables, pas des intentions.
4. Les « interdits » sont ceux de la section 2, répétés (un skill ne lit pas ce fichier).
5. Tester le skill : le lancer sur un cas dont on connaît la bonne réponse (le ticket précédent) et comparer.
6. Le skill vit dans le dépôt, il évolue par commit comme le code ; ne pas copier les skills dans deux endroits (dérive silencieuse, déjà payée sur le journal de tickets).
7. Appel : `/logialvia-migration-domaine` ou demande en langage naturel qui reprend les mots de la `description`.

## 2. Contraintes communes à TOUS les skills (à ne jamais omettre)

1. **Tout est en français** : prose, libellés, messages d'erreur, commentaires, noms de tests, messages de commit.
2. **Un ticket = une session.** Annoncer le plan (migrations, Actions, structure du composant) avant d'écrire. Ne jamais convertir plusieurs écrans d'un coup sans vérification intermédiaire.
3. **UUID partout** ; montants entiers FCFA ; dates en heure du Bénin (`Africa/Porto-Novo`) ; colonnes de synchro `device_id`, `sync_status`, `updated_at` ; suppression logique (`30_DATABASE_ENGINEERING.md` §1 et §3).
4. **Point de passage unique** : toute règle qui écrit vit dans UNE Action ou UN Service, appelée par l'écran web ET par la synchronisation ; le poste la reprend avec une **parité exécutée**. Jamais deux copies.
5. **La vue Blade est le maître** (doctrine article 0) : le poste reprend structure, composants, retours et logique à 100 %. Un critère absent du web se construit d'abord sur le web.
6. **Schéma partagé** : toute table synchronisable modifiée côté Laravel l'est côté Drift (`app_database.dart`, `dart run build_runner build`) et inversement. `app_database.g.dart` n'est jamais édité à la main.
7. **Le test qui aurait attrapé le défaut** ; un chiffre se vérifie par recalcul indépendant, jamais en le lisant ; chaque test a sa preuve de mutation (`31_TESTING_QA.md` T2).
8. **Rapport honnête** : toujours une section « NON vérifié ».
9. **Interdits transverses** : inventer une règle métier ; `increments()` ; `float`/`decimal` pour de l'argent ; `DELETE` physique sur du comptable/zootechnique/commercial ; secret dans une colonne synchronisable ; export `*.sql`, archive `*.zip` ou `.env` versionné ; `pkill` ; committer ou pousser sans demande ; éditer `app_database.g.dart` ; test vert à vide.

## 3. Chemins de référence (vérifiés par `ls`)

| Sujet | Chemin |
|---|---|
| Skills du dépôt | `/home/user/agrierp/.claude/skills/prd/SKILL.md`, `.claude/skills/plan/SKILL.md` |
| Doctrine et plan | `/home/user/agrierp/docs/DOCTRINE_PORTAGE.md`, `docs/PLAN_FINALISATION.md`, `docs/AUDIT_FIDELITE_ECRANS.md`, `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md`, `docs/COMPARAISON_METHODE_TATACORA.md`, `docs/prd/` |
| Migrations AgriERP | `/home/user/agrierp/agrierp_laravel/database/migrations/` |
| Modèles / Actions / Services | `agrierp_laravel/app/Models/`, `app/Actions/` (ex. `AdjustStockAction.php`, `AnnulerVenteAction.php`, `RecordSaleAccountingEntryAction.php`), `app/Services/` (ex. `AccountingEntryService.php`, `EffectifParCategorieService.php`, `RappelsDuJourService.php`, `PdfExportService.php`, `ImportModuleService.php`, `BankReconciliationService.php`, `SauvegardeService.php`, `TransactionRejouable.php`), `app/Support/` (ex. `MessagesErreurFr.php`, `MotifsRefusPush.php`, `DatesValidationFr.php`) |
| Composants Livewire | `agrierp_laravel/app/Livewire/{Elevage,Ventes,Comptabilite,Parametres,Facturation,Shared,Stocks,Achats,RH,Rapports,Dashboard,Auth,Profil,Notifications,PublicPages}/` ; hubs : `Comptabilite/ComptabiliteHub.php`, `Ventes/VentesDevisHub.php`, `Ventes/CreancesClientsHub.php`, `Parametres/ParametresHub.php`, `Elevage/SoinsVaccinsHub.php` |
| Composants Blade | `agrierp_laravel/resources/views/components/` : `datatable`, `modal`, `modal-confirm-delete`, `modal-confirm-hard-delete`, `modal-confirm-permanent-delete`, `kpi-card`, `kpi-accordion`, `tab-page`, `pagination`, `toast-container`, `flash-toast`, `pwa-install`, `verrou-session`, `aide-flottante`, `autonomie-alimentaire`, `prophylaxie-du-jour`, `cycle-reminder` |
| Exports PDF | `agrierp_laravel/resources/views/exports/*.blade.php` ; `app/Services/PdfExportService.php` (`render(view, data, title, period, orientation)`) ; poste : `agrierp_flutter/lib/core/export/{document_officiel,export_tableur,pdf_attestation,pdf_recu}.dart` |
| Import / export tableur | web : bouton « Excel » = CSV (`app/Livewire/Rapports/`), `maatwebsite/excel` déclaré dans `composer.json` ; import relevé : `BankReconciliationService::importCsv` ; **import xlsx de données métier : n'existe pas dans AgriERP (À CONCEVOIR, GUIDE bloc 21)** |
| Synchronisation (serveur) | `agrierp_laravel/app/Http/Controllers/Api/SyncController.php` (routes `/api/sync/pull`, `/api/sync/push` dans `routes/api.php`) ; `app/Services/{JournalSynchronisationService,DemandeSynchronisationService,CoherenceSynchronisationService,ResynchronisationPostesService,FusionReferentielsService}.php` ; `app/Livewire/Shared/EtatSynchronisationPostes.php` ; `app/Livewire/Parametres/PostesAppairage.php` |
| Synchronisation (poste) | `agrierp_flutter/lib/core/sync/{sync_engine,synchronisation_automatique,modale_synchronisation,perimetre_tirage,fusion_referentiels,agregats_coherence,gestes_importants}.dart` ; `lib/core/database/sync_columns.dart`, `app_database.dart` ; `lib/features/sync/synchronisation_screen.dart` |
| Écrans / dépôts Drift du poste | `agrierp_flutter/lib/features/{elevage,ventes,stocks,achats,comptabilite,parametres,rh,clients,notifications,pilotage,verrou,sync,…}/` ; widgets partagés `lib/core/widgets/{modale_agri,carte_kpi,grille_kpi,pagination_agri,toast_agri,champs_date_agri,selecteur_exercice,bandeau_exercice}.dart` |
| Rappels du jour | web : `app/Services/RappelsDuJourService.php`, `app/Livewire/Shared/RappelsDuJour.php`, `ProtocoleDuJourService.php`, `AlertesElevageService.php` ; poste : `lib/features/elevage/rappels_du_jour_{repository,modale,ouverture}.dart` |
| Alertes / notifications | `app/Jobs/DailyElevageAlertsJob.php`, `DailyProphylaxyReminderJob.php`, `app/Livewire/Shared/NotificationBell.php`, `app/Livewire/Notifications/Index.php`, `app/Actions/RaiseFeedAutonomyAlertAction.php`, `app/Services/AlerteAutonomieFicheService.php` |
| Rationnement | `app/Support/{StadePondeuse,CategorieVolaille,CategorieRationLapin,CategorieRationPorc}.php`, `app/Services/AutonomieAlimentaireService.php`, `app/Models/FeedRationStandard.php`, `database/seeders/FeedRationStandardsSeeder.php` ; poste : `lib/features/elevage/{stade_pondeuse,categorie_ration_lapin,categorie_volaille}.dart` |
| MeCeF | `agrierp_laravel/app/Services/Mecef/` (`FacturationMecefService`, `MecefFactureBuilder`, `MecefGatewayFactory`, `EmecefGateway`, `BoitierMecefGateway`, `FakeMecefGateway`, `MecefReglageService`, `ChoixFactureService`, `MecefAvoirGatewayInterface`) ; `config/mecef.php` ; `app/Livewire/Facturation/Facturation.php`, `app/Livewire/Parametres/FacturationEmecef.php` ; `app/Services/AvoirClientService.php` ; tests `tests/Feature/AvoirMecefTest.php`, `ModuleMecefDesactiveTest.php` |
| PWA | `agrierp_laravel/public/{sw.js,manifest.webmanifest,offline.html}`, `resources/views/components/pwa-install.blade.php` |
| Réglages SMTP / logo / favicon / entreprise | `app/Livewire/Parametres/{EmailSmtp,DonneesEntreprise,FacturationEmecef}.php`, `app/Services/EntrepriseService.php`, migration `2026_02_20_000001_create_company_settings_table.php` |
| Build Windows | `/home/user/agrierp/agrierp_flutter/build_windows.bat` ; `.fvmrc` (version de Flutter) |
| Tests et outils | `agrierp_laravel/tests/{Feature,Browser,Js}/`, `agrierp_flutter/test/`, `agrierp_flutter/outils/` (voir `31_TESTING_QA.md` §2) |
| Sources de logialvia | `/home/user/massenon/logialvia/logialvia_app/lib/` (domaines `administration`, `approvisionnement`, `commercial`, `comptabilite`, `elevage`, `pilotage`, `rapports`, `core`), `/home/user/massenon/logialvia/docs/` |
| Configuration des filières | `/home/user/massenon/logialvia/logialvia_app/lib/elevage/domain/entities/configuration_espece.dart` |

## 4. Index des 36 skills

| ID | Nom du skill | Pièce produite |
|---|---|---|
| SK-01 | `logialvia-migration-domaine` | migrations d'un domaine |
| SK-02 | `logialvia-modele-eloquent` | modèle Eloquent |
| SK-03 | `logialvia-action-point-unique` | Action / Service point de passage unique |
| SK-04 | `logialvia-page-livewire` | composant Livewire de page |
| SK-05 | `logialvia-hub-onglets` | hub à onglets |
| SK-06 | `logialvia-datatable` | DataTable |
| SK-07 | `logialvia-modale-crud` | modale CRUD |
| SK-08 | `logialvia-formulaire-validation-fr` | formulaire à validation française |
| SK-09 | `logialvia-kpi-dashboard` | KPI et tableau de bord |
| SK-10 | `logialvia-export-pdf` | export PDF |
| SK-11 | `logialvia-export-xlsx` | export xlsx |
| SK-12 | `logialvia-import-xlsx` | import xlsx en masse |
| SK-13 | `logialvia-tests-feature` | jeu de tests Feature |
| SK-14 | `logialvia-test-parite` | test de parité web ↔ poste |
| SK-15 | `logialvia-garde-fou-source` | garde-fou de source |
| SK-16 | `logialvia-ecran-flutter-drift` | écran Flutter + dépôt Drift |
| SK-17 | `logialvia-absorbeur-synchro` | absorbeur strict de synchronisation |
| SK-18 | `logialvia-push-idempotent` | push idempotent |
| SK-19 | `logialvia-modale-synchronisation` | modale de synchronisation |
| SK-20 | `logialvia-alerte-notification` | alerte / notification |
| SK-21 | `logialvia-rappel-vms` | rappel VMS (« Rappels du jour ») |
| SK-22 | `prd` (existant) / `logialvia-prd` | PRD |
| SK-23 | `plan` (existant) / `logialvia-plan` | plan de ticket |
| SK-24 | `logialvia-fiche-journaliere` | fiche journalière d'une filière (variantes pisciculture / pintades / goliaths) |
| SK-25 | `logialvia-rationnement` | rationnement |
| SK-26 | `logialvia-facture-emecef` | facture normalisée e-MECeF |
| SK-27 | `logialvia-avoir` | avoir |
| SK-28 | `logialvia-pwa-hors-ligne` | PWA hors ligne |
| SK-29 | `logialvia-reglages-smtp-logo-favicon` | réglages SMTP / logo / favicon |
| SK-30 | `logialvia-appairage-poste` | appairage d'un poste |
| SK-31 | `logialvia-build-windows` | build Windows |
| SK-32 | `logialvia-revue-design` | revue de conformité de design |
| SK-33 | `logialvia-audit-securite` | audit de sécurité |
| SK-34 | `logialvia-migration-donnees-uuid` | migration des données de logialvia vers UUID |
| SK-35 | `logialvia-seeder-reference` | seeder de données de référence |
| SK-36 | `logialvia-mutation-test` | preuve par mutation |

## 5. Les skills

Format de chaque fiche : **Déclencheur · Entrées · Étapes · Sorties · Critères d'acceptation · Interdits · Références.** Les contraintes de la section 2 s'appliquent à tous ; les « Interdits » ci-dessous s'y ajoutent.

---

### SK-01 — Migration d'un domaine (`logialvia-migration-domaine`)
- **Déclencheur** : « crée les tables de <domaine> », « migration », « schéma de <module> ».
- **Entrées** : nom du domaine ; liste des tables ; `30_DATABASE_ENGINEERING.md` (ERD et dictionnaire du domaine) ; tables Drift de logialvia du domaine.
- **Étapes** : (1) lire l'ERD et le dictionnaire du domaine ; (2) annoncer le plan (ordre de dépendance, §8.1 de `30`) ; (3) une migration par table, docblock français (ticket, pourquoi, source) ; (4) `uuid('id')->primary()`, `foreignUuid()->constrained()` avec action explicite ; (5) montants `unsignedBigInteger`, quantités `decimal(10,2)`, jours `date` ; (6) colonnes de synchro si synchronisable ; (7) uniques, index, CHECK gardées par le pilote ; (8) idempotence `hasTable`/`hasColumn` ; (9) test de schéma ; (10) tables Drift jumelles + `schemaVersion` + `build_runner`.
- **Sorties** : migrations, test `<Domaine>SchemaTest.php`, tables Drift, mise à jour du dictionnaire.
- **Critères** : `php artisan migrate:fresh --seed` passe (SQLite) ; `grep -rnE "increments\(|bigIncrements\(|->id\(\)" database/migrations` vide ; chaque table est au dictionnaire ; « NON vérifié sur MariaDB » ou sortie de `outils/essai_multipostes.sh` si `->change()`/enum.
- **Interdits** : modifier une migration livrée ; `enum` pour une liste qui grandit ; `->change()` sans répéter nullité et défaut ; FK vers une table créée plus tard.
- **Références** : `30_DATABASE_ENGINEERING.md` ; `database/migrations/2026_02_10_000001_create_livestock_lots_table.php`, `2026_10_23_000001_create_corbeille_operations_table.php`, `2026_02_28_000003_add_retard_to_attendance_records_status_enum.php`.

### SK-02 — Modèle Eloquent (`logialvia-modele-eloquent`)
- **Déclencheur** : « modèle pour <table> ».
- **Entrées** : migration de la table ; relations du dictionnaire.
- **Étapes** : `HasUuids` ; `$fillable` explicite (jamais `sync_status`, `device_id`, secret, `must_change_password`) ; casts (`encrypted` pour les secrets, `date`, `boolean`, entiers) ; relations avec le bon type de suppression ; portées (`actifs()`, `pourExercice()`) ; accesseurs de présentation en français seulement si l'écran les réutilise ; aucune règle métier dans le modèle (elle va en Action).
- **Sorties** : `app/Models/<Nom>.php` ; test de relations et de casts.
- **Critères** : le modèle ne peut pas écrire un montant non entier ; `Model::create` sans `id` produit un UUID ; un secret est chiffré en base (lecture brute ≠ clair).
- **Interdits** : logique métier ; `$guarded = []` ; accesseur qui arrondit un montant.
- **Références** : `agrierp_laravel/app/Models/{Sale,Product,LivestockLot,CompanySetting,User}.php`.

### SK-03 — Action / Service, point de passage unique (`logialvia-action-point-unique`)
- **Déclencheur** : « règle <R> qui écrit », « enregistrer <X> », « calculer <Y> ».
- **Entrées** : règle (id dans `15_REGLES_METIER.md`) ; jeu de cas calculé à la main ; tables touchées.
- **Étapes** : (1) chercher si une Action/Service existe déjà (`grep` dans `app/Actions`, `app/Services`) : l'APPELER, ne rien recopier ; (2) sinon créer UNE classe : entrée validée, `DB::transaction`, refus motivés (messages exacts en français, fournis par `MessagesErreurFr`/`MotifsRefusPush`), audit (`AuditLog::record`) ; (3) idempotence par UUID fourni par l'appelant ; (4) appelée par l'écran Livewire ET par `SyncController` ; (5) transaction rejouable sur interblocage (`TransactionRejouable`) ; (6) tests : valeur, refus, droit, idempotence ; (7) annoncer la parité à porter côté poste (SK-14).
- **Sorties** : `app/Actions/<Verbe><Objet>Action.php` ou `app/Services/<Objet>Service.php` ; tests ; note de parité.
- **Critères** : un seul chemin d'écriture (le garde-fou SK-15 « pas d'écriture hors Action » vert) ; rejouer deux fois = un seul effet ; les valeurs de la section 4.2 de `31` sortent.
- **Interdits** : règle copiée dans le composant Livewire ou le contrôleur ; appel réseau (MeCeF, e-mail) DANS la transaction (la facture partirait deux fois si rejouée) ; `DELETE` physique.
- **Références** : `app/Actions/{AdjustStockAction,AnnulerVenteAction,RecordSaleAccountingEntryAction}.php`, `app/Services/{AccountingEntryService,TransactionRejouable,CustomerAdvanceService}.php`.

### SK-04 — Composant Livewire de page (`logialvia-page-livewire`)
- **Déclencheur** : « écran <X> », « page <X> ».
- **Entrées** : fiche de module `20_MODULES_*` ; maquette ou vue maître ; droit RBAC ; classe d'écran (`31` §9).
- **Étapes** : (1) route avec middleware `can:` ; (2) composant `app/Livewire/<Domaine>/<Nom>.php` : chaque méthode qui écrit commence par `authorize()` ; (3) lecture paginée (`WithPagination`) ; (4) écriture déléguée à l'Action (SK-03) ; (5) vue Blade `resources/views/livewire/<domaine>/<nom>.blade.php` avec les composants partagés (`x-datatable`, `x-modal`, `x-kpi-card`) ; (6) toasts via `flash-toast` ; (7) aucun `@if` conditionnel qui monte/démonte une modale (motif modale Alpine : toujours présente, ouverte par état) ; (8) tests SK-13.
- **Sorties** : route, composant, vue, test.
- **Critères** : garde-fou d'autorisation vert ; rendu sans erreur pour 2 rôles ; aucune requête N+1 (relations chargées) ; si Alpine/modale : parcours Dusk.
- **Interdits** : règle métier dans le composant ; liste non paginée ; texte en anglais.
- **Références** : `app/Livewire/Ventes/HistoriqueVentes.php`, `app/Livewire/Elevage/GestionBandes.php`, `tests/Feature/AutorisationsMethodesMutantesTest.php`.

### SK-05 — Hub à onglets (`logialvia-hub-onglets`)
- **Déclencheur** : « hub », « écran à onglets ».
- **Entrées** : liste des onglets, droit de chacun.
- **Étapes** : composant hub qui monte UN sous-composant par onglet via `x-tab-page` ; onglet actif en propriété (`#[Url]` si on veut le lien profond) ; un onglet sans droit n'est pas rendu ; chaque onglet est un composant indépendant (SK-04) ; côté poste : `TabController`, pas de routes séparées.
- **Sorties** : hub + sous-composants + test d'onglets.
- **Critères** : changer d'onglet ne perd pas une saisie non enregistrée sans avertissement ; accessibilité des onglets (rôles ARIA) ; l'onglet absent n'est pas « grisé en silence ».
- **Interdits** : onglets = pages séparées ; une grosse vue de 2 000 lignes.
- **Références** : `app/Livewire/Comptabilite/ComptabiliteHub.php`, `Ventes/VentesDevisHub.php`, `Parametres/ParametresHub.php`, `resources/views/components/tab-page.blade.php`.

### SK-06 — DataTable (`logialvia-datatable`)
- **Déclencheur** : « tableau », « liste », « DataTable ».
- **Entrées** : colonnes, tris, filtres, actions de ligne (dans l'ordre de la vue maître).
- **Étapes** : (1) requête paginée triée sur colonne indexée + départage par `id` ; (2) recherche et filtres en propriétés Livewire (`wire:model.live.debounce`) ; (3) composant `x-datatable` ; (4) état vide avec texte ; (5) actions de ligne gardées par `@can` ; (6) archivage (jamais suppression) avec modale (SK-07).
- **Sorties** : section de vue + méthode de requête + test (tri, filtre, page 2, état vide).
- **Critères** : 25 lignes max par page ; `EXPLAIN` utilise un index ; total affiché = `COUNT` indépendant.
- **Interdits** : charger toute la table ; calculer un total en PHP sur toutes les lignes ; trier sur une colonne non indexée d'une grosse table.
- **Références** : `resources/views/components/datatable.blade.php`, `pagination.blade.php`.

### SK-07 — Modale CRUD (`logialvia-modale-crud`)
- **Déclencheur** : « modale de création/édition/archivage ».
- **Entrées** : champs, règles, texte d'avertissement.
- **Étapes** : composant `x-modal` toujours rendu et ouvert par état (jamais `@if` qui la démonte) ; boutons Réduire/Agrandir/Fermer selon le GUIDE bloc 3 ; primaire à droite ; fermeture réinitialise erreurs ; archivage par `x-modal-confirm-delete` ; suppression définitive par `x-modal-confirm-permanent-delete` avec le mot `SUPPRIMER` (seulement référentiels non référencés) ; toast de succès APRÈS écriture réussie seulement.
- **Sorties** : vue + méthodes `ouvrir…`, `enregistrer`, `archiver` + test Feature + parcours Dusk si Alpine.
- **Critères** : ouvrir/fermer/ouvrir ne duplique pas l'instance Alpine ; Échap et clic extérieur selon le design ; focus piégé.
- **Interdits** : succès affiché sans persistance ; modale montée par `@if` ; double instance Alpine.
- **Références** : `resources/views/components/{modal,modal-confirm-delete,modal-confirm-hard-delete,modal-confirm-permanent-delete}.blade.php` ; poste : `lib/core/widgets/modale_agri.dart`.

### SK-08 — Formulaire avec validation française (`logialvia-formulaire-validation-fr`)
- **Déclencheur** : « formulaire », « validation », « message d'erreur ».
- **Entrées** : champs, bornes, règles croisées.
- **Étapes** : règles `Rule`/`rules()` ; messages et noms d'attribut en français (`MessagesErreurFr`) ; erreurs affichées sous le champ ; dates en `jj/mm/aaaa` (`DatesValidationFr`) ; champ numérique vide ≠ 0 (`ChampNumeriqueVide`) ; montants entiers : refuser une décimale avec message clair ; mêmes mots côté poste (parité de libellé) ; test par règle (valeur limite, refus, message exact).
- **Sorties** : `rules()`, `messages()`, test.
- **Critères** : chaque message de refus est testé mot pour mot ; le poste affiche le même.
- **Interdits** : message anglais ; erreur générique « invalide » ; valider seulement en JavaScript.
- **Références** : `app/Support/{MessagesErreurFr,DatesValidationFr,ChampNumeriqueVide}.php`.

### SK-09 — KPI et tableau de bord (`logialvia-kpi-dashboard`)
- **Déclencheur** : « tableau de bord », « KPI », « indicateur ».
- **Entrées** : liste des indicateurs, formule, source SQL.
- **Étapes** : agrégats SQL (`SUM`/`COUNT` groupés) ; `x-kpi-card` / `x-kpi-accordion` ; texte d'état quand aucune donnée (jamais une carte vide) ; filtre de période partagé ; chaque indicateur a un recalcul indépendant dans un test ; côté poste `carte_kpi.dart`/`grille_kpi.dart`.
- **Sorties** : composant, requêtes, test de valeurs.
- **Critères** : valeur affichée = recalcul SQL séparé ; aucune somme en PHP sur toute une table ; temps de rendu mesuré sur `DemoDataSeeder`.
- **Interdits** : KPI sans formule documentée ; couleur ad hoc hors design system.
- **Références** : `app/Livewire/Dashboard/`, `app/Livewire/Elevage/DashboardElevage.php`, `resources/views/components/kpi-card.blade.php`.

### SK-10 — Export PDF (`logialvia-export-pdf`)
- **Déclencheur** : « imprimer », « PDF », « facture/rapport en PDF ».
- **Entrées** : document, orientation, structure (bandes, en-tête, totaux).
- **Étapes** : vue `resources/views/exports/<nom>.blade.php` ; `PdfExportService::render(view, data, title, period, orientation)` ; logo et nom d'entreprise lus de `company_settings` ; police Unicode (« — », « ’ » ne doivent pas sortir en carré) ; poste : `DocumentOfficiel` + `ExportOfficiel.construire`, `chargerPolices()` obligatoire ; test : extraire le texte du PDF et comparer aux valeurs de l'écran.
- **Sorties** : vue d'export, appel dans le composant, test PDF web, test PDF poste.
- **Critères** : texte du PDF = valeurs de l'écran (recalcul) ; aucun glyphe manquant ; pied de page conforme.
- **Interdits** : montant reformaté ; police par défaut sans Unicode.
- **Références** : `app/Services/PdfExportService.php`, `resources/views/exports/`, `agrierp_flutter/lib/core/export/document_officiel.dart`, test `agrierp_flutter/test/liste_achats_detail_test.dart` (compte les glyphes manquants, cité au GUIDE bloc 7).

### SK-11 — Export xlsx (`logialvia-export-xlsx`)
- **Déclencheur** : « Excel », « export tableur ».
- **Entrées** : tableau source (le même `DocumentOfficiel`/jeu de lignes que le PDF) ; droit `export-rapports`.
- **Étapes** : builder pur (aucune E/S) à partir de la structure du PDF ; cellules = texte tel qu'affiché, **aucun montant reformaté** ; nom d'onglet ≤ 31 caractères sans `: \ / ? * [ ]` ; web : `maatwebsite/excel` (déjà au `composer.json`) ; ⚠️ **dans AgriERP le bouton « Excel » du web produit un CSV, et l'export xlsx est un ajout du poste au-delà de la maquette** : décider avec le client (question Q-SK1) avant de promettre du xlsx au web ; poste : paquet `excel`, `export_tableur.dart`.
- **Sorties** : builder, bouton gardé par le droit, test (relire le fichier, comparer aux valeurs).
- **Critères** : relecture du xlsx = valeurs de l'écran ; nom d'onglet conforme ; droit refusé = pas d'export.
- **Interdits** : copie du PDF en tableur ; formule Excel injectée depuis une donnée utilisateur (préfixer `'` toute cellule commençant par `= + - @`).
- **Références** : `agrierp_flutter/lib/core/export/export_tableur.dart`, `app/Livewire/Rapports/RapportsExportsHub.php`, test `agrierp_flutter/test/rapports_exports_test.dart`.

### SK-12 — Import xlsx en masse (`logialvia-import-xlsx`)
- **Déclencheur** : « importer un fichier Excel », « import en masse ».
- **Entrées** : table cible, colonnes attendues, droit.
- **Étapes** : ⚠️ **cette fonction n'existe pas dans AgriERP (À CONCEVOIR) : PRD d'abord (SK-22)**. Principes à reprendre des imports existants : liste blanche de colonnes et de table (jamais déduite du fichier) ; valeurs liées, jamais d'exécution du contenu ; aperçu avant écriture avec lignes rejetées comptées et montrées ; **idempotence par `import_id`** (un import déjà joué n'est pas rejoué) ; taille maximale (message français) ; passage par l'Action de la table (SK-03), pas d'insertion directe ; transaction unique ; rapport (créées, ignorées, refusées + motif).
- **Sorties** : PRD, service d'import, écran avec aperçu, tests (fichier valide, ligne invalide, rejeu, fichier trop gros, colonne inconnue).
- **Critères** : un fichier rejoué n'écrit rien de plus ; aucune ligne invalide n'est écrite en silence ; totaux du rapport = recomptage.
- **Interdits** : exécuter du SQL ou une formule du fichier ; accepter une colonne non listée ; importer sans aperçu.
- **Références** : `app/Services/BankReconciliationService.php` (`importCsv`, `import_id`), `app/Services/ImportModuleService.php`, tests `tests/Feature/ImportModuleTest.php`, `RapprochementBancaireTest.php`.

### SK-13 — Jeu de tests Feature (`logialvia-tests-feature`)
- **Déclencheur** : « écris les tests de <module> ».
- **Entrées** : module, règles, jeux de `31` §4.2.
- **Étapes** : appliquer le prompt **T1** de `31_TESTING_QA.md` : test de valeur (calculé à la main), de refus (message exact), de droit (rôle de lecture), d'idempotence ; données par les vraies Actions ; recalcul indépendant pour tout chiffre affiché ; compléter la matrice exigence → test.
- **Sorties** : `tests/Feature/<Module>Test.php`.
- **Critères** : `php artisan test --testsuite=Feature --filter=<Module>` vert ; preuve de mutation (SK-36).
- **Interdits** : valeur attendue copiée de la sortie du code ; test qui ne peut pas échouer.
- **Références** : `31_TESTING_QA.md` §4 et §14 ; `tests/Feature/FicheLapinsEffectifAutomatiqueTest.php`.

### SK-14 — Test de parité web ↔ poste (`logialvia-test-parite`)
- **Déclencheur** : « parité », « le poste doit faire comme le web ».
- **Entrées** : règle et son Action serveur.
- **Étapes** : prompt **T3** de `31` : le poste fabrique l'envoi avec ses vrais dépôts et `SyncEngine` ; le PHP réel (SQLite mémoire, migrations réelles, rôle du seeder) le traite et sert son tirage que le poste absorbe ; comparer valeurs, messages de refus, statuts ; garde-fou qui lit le Blade pour les libellés ; se SAUTER avec sa raison sans PHP.
- **Sorties** : `test/<regle>_parite_php_test.dart`.
- **Critères** : modifier un libellé, un format de date ou un statut d'un seul côté rougit le test (à prouver).
- **Interdits** : recopier la règle dans le test ; vert à vide.
- **Références** : `agrierp_flutter/test/avoirs_parite_php_test.dart`, `php_laravel.dart`, `rappels_du_jour_parite_php_test.dart`, `verrou_parite_web_test.dart`.

### SK-15 — Garde-fou de source (`logialvia-garde-fou-source`)
- **Déclencheur** : « garde-fou », « verrouiller une convention », « un test qui lit le code ».
- **Entrées** : la convention à verrouiller ; le défaut silencieux qu'elle évite.
- **Étapes** : (1) écrire la convention en une phrase vérifiable ; (2) test qui parcourt les fichiers (`glob`, regex) ; (3) liste d'exclusions **nominative, commentée** ; (4) message d'échec français nommant fichier et ligne ; (5) prouver la mutation : introduire une violation, voir rouge, annuler.
- **Sorties** : `tests/Feature/<Convention>Test.php` ou `test/<convention>_test.dart`.
- **Critères** : vert sur le code sain, rouge sur un exemple cassé.
- **Interdits** : exclusion par motif large ; garde-fou sans message utile.
- **Références** : `tests/Feature/AutorisationsMethodesMutantesTest.php`, `AuditToutesLesRoutesTest.php`, `agrierp_flutter/test/avoirs_schema_test.dart`.

### SK-16 — Écran Flutter + dépôt Drift (`logialvia-ecran-flutter-drift`)
- **Déclencheur** : « porte l'écran <X> sur le poste ».
- **Entrées** : vue Blade maître ; Action serveur ; tables Drift.
- **Étapes** : (1) lire la vue Blade en entier (jamais de mémoire) ; (2) table Drift jumelle (`TextColumn id`, colonnes de synchro) puis `build_runner` ; (3) dépôt `lib/features/<domaine>/<x>_repository.dart` qui applique AVANT d'écrire les mêmes règles et les mêmes motifs que l'Action (messages mot pour mot) ; ligne repassée `pending` ; (4) écran fidèle (composants partagés `modale_agri`, `carte_kpi`, `pagination_agri`) ; (5) tests : dépôt, écran, parité (SK-14), garde-fou de libellés.
- **Sorties** : table, dépôt, écran, tests, migration Drift (`schemaVersion` + `if (from < N)`).
- **Critères** : `flutter analyze && flutter test` verts ; parité exécutée verte ; migration testée depuis la version précédente.
- **Interdits** : comportement absent du Blade ; calcul dans le widget ; édition de `app_database.g.dart`.
- **Références** : `agrierp_flutter/lib/features/elevage/{fiche_lapins_screen,fiche_journaliere_repository}.dart`, `lib/core/database/{app_database,sync_columns}.dart`.

### SK-17 — Absorbeur strict de synchronisation (`logialvia-absorbeur-synchro`)
- **Déclencheur** : « tirage », « absorber les données du serveur ».
- **Entrées** : table synchronisée, clé de curseur.
- **Étapes** : le poste absorbe par UUID (`insertOnConflictUpdate`) ; **ne touche jamais une ligne `pending` ou `conflict`** ; ignore ce qu'il ne connaît pas sans planter (version de schéma plus récente) ; curseur `updated_at` + `id`, page 1 d'abord, pagination ; fuseau du Bénin ; validation stricte du format reçu (date, montant entier, UUID) : une ligne invalide est comptée et journalisée, pas absorbée à moitié.
- **Sorties** : méthode d'absorption + tests (ligne pending intacte, ligne inconnue, format invalide, rejeu).
- **Critères** : absorber deux fois = même base ; une ligne `pending` survit à un tirage qui la contredit.
- **Interdits** : écraser une saisie locale ; supposer qu'un champ existe.
- **Références** : `agrierp_flutter/lib/core/sync/sync_engine.dart`, `perimetre_tirage.dart` ; `tests/Feature/SyncCurseurTirageTest.php`, `SyncCurseurFuseauTest.php`.

### SK-18 — Push idempotent (`logialvia-push-idempotent`)
- **Déclencheur** : « envoi du poste », « push », « le poste envoie <X> ».
- **Entrées** : table, clé (UUID créé au poste), droit.
- **Étapes** : clé `<table>` dans `SyncController::push` ; toute la requête dans UNE transaction rejouable (`TransactionRejouable`) ; traitement par l'Action (SK-03) ; idempotence : un UUID déjà traité est acquitté sans nouvelle trace ; refus motivés renvoyés au poste avec leur raison (`MotifsRefusPush`) ; appels externes hors transaction ; droits contrôlés par clé ; fusion des référentiels (`FusionReferentielsService`) avec correspondance d'identifiants ; journal (`JournalSynchronisationService`) ; tests : doublon, interblocage rejoué, refus, droit, coupure au milieu.
- **Sorties** : code serveur, côté poste (`SyncEngine` + dépôt), tests, essai multipostes (T5 de `31`).
- **Critères** : envoyer deux fois ne crée rien ; une requête qui échoue n'écrit rien ; essai multipostes sans doublon ni interblocage non rejoué.
- **Interdits** : insertion directe contournant l'Action ; appel MeCeF/e-mail dans la transaction.
- **Références** : `app/Http/Controllers/Api/SyncController.php`, `app/Services/{TransactionRejouable,FusionReferentielsService,JournalSynchronisationService}.php`, `app/Support/MotifsRefusPush.php`, `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md`.

### SK-19 — Modale de synchronisation (`logialvia-modale-synchronisation`)
- **Déclencheur** : « bouton Synchroniser », « barre supérieure », « état de synchro ».
- **Entrées** : `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`.
- **Étapes** : états (rien à envoyer, en cours, terminé, refusés, hors ligne) ; compteurs tirés/envoyés/refusés ; refus listés avec leur raison exacte ; jamais interrompue par le verrou de session ; synchronisation automatique ; côté web : `EtatSynchronisationPostes`.
- **Sorties** : modale web et poste, tests d'états.
- **Critères** : un refus s'affiche avec la raison du serveur ; la modale ne ment pas (pas de « terminé » avec des `pending`).
- **Interdits** : succès affiché sans acquittement du serveur.
- **Références** : `agrierp_flutter/lib/core/sync/{modale_synchronisation,synchronisation_automatique}.dart`, `lib/features/sync/synchronisation_screen.dart`, `app/Livewire/Shared/EtatSynchronisationPostes.php`.

### SK-20 — Alerte / notification (`logialvia-alerte-notification`)
- **Déclencheur** : « alerte », « notification », « cloche ».
- **Entrées** : règle de déclenchement, destinataires (droit), type.
- **Étapes** : service calculant l'alerte (une alerte par objet et par jour) ; stockage (`notifications`) ; type ajouté **sans `enum` figé** (voir pièges `->change()` de `30` §8.3) ; planification (`routes/console.php`, une seule entrée cron `schedule:run`) ; cloche + page ; l'alerte **n'empêche jamais l'enregistrement** ; tests : déclenchement, doublon du jour, droit.
- **Sorties** : service, job, type, vue, tests.
- **Critères** : une alerte par objet et par jour ; destinataire sans droit = rien.
- **Interdits** : bloquer la saisie ; alerte sans règle sourcée.
- **Références** : `app/Jobs/DailyElevageAlertsJob.php`, `app/Actions/RaiseFeedAutonomyAlertAction.php`, `app/Livewire/Shared/NotificationBell.php`, `routes/console.php`.

### SK-21 — Rappel VMS, fenêtre « Rappels du jour » (`logialvia-rappel-vms`)
- **Déclencheur** : « rappels du jour », « vaccins, médicaments, soins à venir ».
- **Entrées** : horizon N jours ; règles R-SOINS-01 et R-RAPPELS-01 (à lire dans le PRD `docs/prd/popup-rappels.md` d'AgriERP).
- **Étapes** : service unique `RappelsDuJourService` qui APPELLE `AlertesElevageService::soinsAVenir()` et `ProtocoleDuJourService::pourBande()` (ne rien recopier) ; composant `Shared/RappelsDuJour` monté dans le layout sous `@can('view-elevage')`, qui décide **côté serveur** ; le navigateur ne transmet que `sessionStorage` (une fois par session) et `localStorage` (« Ne plus afficher aujourd'hui », par utilisateur) ; réouverture à chaque connexion ; aucune fenêtre vide ; erreur journalisée, silencieuse ; poste : calcul local identique, parité exécutée. ⚠️ « VMS » : la signification exacte de l'acronyme pour LogiALVIA n'est pas dans mes sources : **À DÉFINIR AVEC LE CLIENT (Q-SK2)** ; le skill s'appuie sur le périmètre de « Rappels du jour » (soins, traitements du barème, fins de délai d'attente).
- **Sorties** : service, composant, vue, poste, tests, parité.
- **Critères** : jamais de fenêtre vide ; rôle sans `view-elevage` ne la reçoit pas ; parité Dart ↔ PHP verte.
- **Interdits** : règle dupliquée ; décision côté navigateur.
- **Références** : `app/Services/{RappelsDuJourService,ProtocoleDuJourService,AlertesElevageService}.php`, `app/Livewire/Shared/RappelsDuJour.php`, `agrierp_flutter/lib/features/elevage/rappels_du_jour_*.dart`, `agrierp_flutter/test/rappels_du_jour_parite_php_test.dart`, `tests/Feature/RappelsDuJourTest.php` (cité dans `agrierp_laravel/CLAUDE.md`).

### SK-22 — Rédaction d'un PRD (skill `prd`)
- **Déclencheur** : « PRD », « cahier des charges », « spécification », « définir <fonction> ».
- **Entrées** : fonctionnalité ; les trois sources (vue Blade, Actions/Services, journal).
- **Étapes** : appliquer le skill existant `/home/user/agrierp/.claude/skills/prd/SKILL.md` (le réutiliser tel quel : `/prd`), adapté à LogiALVIA : fichier `docs/prd/<slug>.md` dans le dépôt LogiALVIA ; si la fonction n'existe ni au web ni au poste, le PRD le dit en tête (elle se construit d'abord au web) ; chaque règle chiffrée a un exemple ; ce qui n'est pas défini → « À DÉFINIR AVEC LE CLIENT » + question.
- **Sorties** : `docs/prd/<slug>.md`.
- **Critères** : chaque exigence est testable ; questions ouvertes listées ; aucun chiffre inventé.
- **Interdits** : coder avant validation ; décider une règle à la place du client.
- **Références** : `.claude/skills/prd/SKILL.md`, `docs/prd/`.

### SK-23 — Plan d'un ticket (skill `plan`)
- **Déclencheur** : « plan », « découpage », « comment on s'y prend ».
- **Entrées** : PRD validé.
- **Étapes** : appliquer `/home/user/agrierp/.claude/skills/plan/SKILL.md` (`/plan`) : situer dans `PLAN_FINALISATION.md`, lister migrations, Actions, composants, tests, parité, risques, décisions client en attente ; annoncer avant tout code ; validation utilisateur si schéma, comptabilité ou décision client.
- **Sorties** : mise à jour du plan du projet.
- **Critères** : chaque tâche a son critère d'acceptation et son test ; les décisions client sont séparées.
- **Interdits** : démarrer le code sans annonce ; ticket qui mélange plusieurs écrans.
- **Références** : `.claude/skills/plan/SKILL.md`, `docs/PLAN_FINALISATION.md`.

### SK-24 — Fiche journalière d'une filière (`logialvia-fiche-journaliere`)
- **Déclencheur** : « fiche journalière <filière> », « saisie du jour ».
- **Entrées** : filière (`poissons-chats`, `pintades`, `goliaths`, `lapins`, `poulets`, `pondeuses`) ; `ConfigurationEspece` ; règle d'effectif (GUIDE bloc 1).
- **Étapes** : (1) **un seul composant générique** paramétré par la configuration de la filière (ajouter une filière = configuration, pas écran dupliqué) ; (2) lire `species_categories` (libellés, rations, catégorie jeune, catégorie commercialisée) ; (3) saisie : achats, nés, ventes, mortalité et dons par catégorie ; **effectifs calculés, jamais saisis** ; cascade unique de recalcul des jours suivants ; plancher 0 ; départ obligatoire et refus motivés ; (4) libellés de la filière (« Nés (Couveuse) » / « Nés (Mise bas) » / « Nés ») ; (5) bandeau « Rappel du Cycle » ; (6) rationnement du jour (SK-25) ; (7) tests avec le jeu de `31` §4.2 ; poste : SK-16 + parité SK-14.
- **Variantes** :
  - **Pisciculture (poissons-chats)** : catégories Alevin / Juvénile / Mature, rations 30/60/110, colonne « Nés » (pas de couveuse ; l'empoissonnement se saisit en « Achats »), note de barème non confirmé. **À DÉFINIR AVEC LE CLIENT** : bassins, qualité de l'eau, pesée/échantillonnage, récolte partielle (aucune colonne ni table créée avant réponse).
  - **Pintades** : Poussins / Pintadau / Mature, 30/60/110, « Nés (Couveuse) ». **À DÉFINIR** : durée d'incubation propre.
  - **Goliaths** : Poussins / Goliathau / Mature, 30/60/110 (barème générique réutilisé, non confirmé), seuils de maturité 2 800 g et 120 jours présents dans le code. **À DÉFINIR** : barème validé, définition de « maturité », combinaison des deux seuils.
- **Sorties** : composant/vue, Action d'enregistrement du jour, tests, poste.
- **Critères** : valeurs de `31` §4.2 ; aucun champ d'effectif éditable ; mêmes messages au poste.
- **Interdits** : un composant par filière ; vocabulaire avicole appliqué à toutes les filières ; règle de maturité inventée.
- **Références** : `/home/user/massenon/logialvia/logialvia_app/lib/elevage/domain/entities/configuration_espece.dart`, `docs/05_LOGIQUE_CALCUL_FORMULAIRES.md`, `F3_Module_Production_Elevage.md` ; `agrierp_laravel/app/Services/EffectifParCategorieService.php`, `app/Livewire/Elevage/FicheLapins.php`, `FichePondeuses.php` ; GUIDE bloc 1.

### SK-25 — Rationnement (`logialvia-rationnement`)
- **Déclencheur** : « ration », « provende », « autonomie alimentaire ».
- **Entrées** : barème `feed_ration_standards`, effectifs calculés, stock de provende.
- **Étapes** : tableau par catégorie = effectif calculé × ration (g/j) ; total = somme de TOUTES les catégories ; `total_kg = round(total_g/1000, 2)` ; catégorie inconnue → total `null`, jamais 0 ; clé de ration en **égalité stricte** sur libellé normalisé (jamais par sous-chaîne) ; valeur de repli explicite, jamais un 0 silencieux ; barème éditable (créer, modifier, archiver) ; alerte d'autonomie rouge (rupture, sous 3 jours — seuil à confirmer —, ou sans produit de provende), n'empêche jamais l'enregistrement.
- **Variantes de filière** : pisciculture, pintades, goliaths utilisent **le barème générique 30/60/110, marqué `confirme = false`** ; la note « barème non confirmé » reste visible. **À DÉFINIR AVEC LE CLIENT** : barèmes propres.
- **Sorties** : fonction pure + service + écran Paramètres Élevage + poste + tests.
- **Critères** : jeux de `31` §4.2 (32 050 g pour les pondeuses ; 4 600 g pour les reproducteurs) ; clé « Poussin » ≠ « Poussin ponte ».
- **Interdits** : barème inventé ; total qui ne somme que la catégorie vendue ; alerte bloquante.
- **Références** : `app/Support/StadePondeuse.php`, `app/Services/{AutonomieAlimentaireService,AlerteAutonomieFicheService}.php`, `app/Livewire/Elevage/ParametresElevage.php`, `database/seeders/FeedRationStandardsSeeder.php`, tests `tests/Feature/RationnementPorcsTest.php`, `AlerteAutonomieAlimentaireTest.php`.

### SK-26 — Facture normalisée e-MECeF (`logialvia-facture-emecef`)
- **Déclencheur** : « facture normalisée », « e-MECeF », « MeCeF ».
- **Entrées** : `41_MECEF_EMECEF.md`, `42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md` ; réglages `company_settings.mecef_*`.
- **Étapes** : module **désactivé par défaut** (`config/mecef.php`, `MECEF_ACTIF=false`) : sans module, la facturation reste un registre avec facture PDF ; passerelle derrière une interface (`MecefGatewayInterface`, `EmecefGateway`, `BoitierMecefGateway`, `FakeMecefGateway` pour les tests) ; `FacturationMecefService::facturer()` rend `inactif` sans rien transmettre ; construction du document (`MecefFactureBuilder`) ; groupes de taxe ; **l'appel à la DGI hors de toute transaction base** ; champs rendus (code, NIM, compteur, lien de vérification, date) tous nuls tant que non rendus ; erreur de transmission conservée et retransmission possible ; jeton JWT chiffré, jamais servi au poste ; IFU client (`customers.ifu`) ; choix de facture (`ChoixFactureService`) ; tests avec la passerelle factice.
- **Sorties** : service, builder, écran de réglage, registre, tests, parité poste.
- **Critères** : module inactif = aucune transmission ni alerte ; un rejeu ne transmet pas deux fois ; jeton absent de toute réponse API.
- **Interdits** : appel réseau dans la transaction ; secret en clair ; règle fiscale inventée (le contrat DGI est décrit dans `41`, jamais deviné).
- **Références** : `agrierp_laravel/app/Services/Mecef/`, `config/mecef.php`, `app/Livewire/Facturation/Facturation.php`, `tests/Feature/ModuleMecefDesactiveTest.php`.

### SK-27 — Avoir (`logialvia-avoir`)
- **Déclencheur** : « avoir », « retour client », « annuler une facture normalisée ».
- **Entrées** : vente d'origine, motif, lignes retournées.
- **Étapes** : `AvoirClientService` (Action unique) ; avoir lié à la vente d'origine ; retour limité à ce qui a été vendu et pas déjà retourné ; remise en stock et recalcul de l'effectif **seulement si la règle du module l'impose** (à confirmer) ; écriture comptable de contre-passation (`RecordCreditNoteAccountingEntryAction`) ; si facture normalisée : avoir normalisé (`MecefAvoirGatewayInterface`) hors transaction ; numérotation sans trou ni doublon (compteur sous verrou) ; synchro : push idempotent ; parité poste.
- **Sorties** : Action, écran « Retours & Avoirs », comptabilisation, tests.
- **Critères** : Σ débit = Σ crédit ; second avoir sur la même ligne refusé avec message ; compteur sans trou.
- **Interdits** : modifier ou effacer la vente d'origine ; avoir sans lien.
- **Références** : `app/Services/AvoirClientService.php`, `app/Livewire/Ventes/RetoursAvoirs.php`, `app/Actions/RecordCreditNoteAccountingEntryAction.php`, `tests/Feature/AvoirMecefTest.php`, `AvoirsClientsSyncTest.php`, `agrierp_flutter/test/avoirs_parite_php_test.dart`.

### SK-28 — PWA hors ligne (`logialvia-pwa-hors-ligne`)
- **Déclencheur** : « installable », « hors ligne », « service worker ».
- **Entrées** : `40_PWA_HORS_LIGNE.md`.
- **Étapes** : `manifest.webmanifest` et **`AddType application/manifest+json .webmanifest` dans `.htaccess`** (Apache le sert sinon en `text/plain` et le navigateur l'ignore sans erreur) ; `sw.js` avec `no-cache` et ressources `build/` empreintées en cache long ; page `offline.html` ; composant `pwa-install` ; saisie hors ligne gardée localement puis envoyée par push idempotent à la reconnexion ; contenu servi par un utilisateur jamais mis en cache partagé ; nettoyage du cache à la déconnexion.
- **Sorties** : manifeste, service worker, page hors ligne, bouton d'installation, test Dusk/manuel.
- **Critères** : application installable (audit navigateur) ; coupure réseau = page hors ligne, pas d'erreur brute ; reconnexion = envoi sans doublon.
- **Interdits** : mettre en cache des pages authentifiées d'un autre utilisateur ; promettre le hors ligne complet quand seule la saisie est gardée.
- **Références** : `agrierp_laravel/public/{sw.js,manifest.webmanifest,offline.html}`, `resources/views/components/pwa-install.blade.php`, `agrierp_laravel/public/.htaccess`.

### SK-29 — Réglages SMTP, logo, favicon (`logialvia-reglages-smtp-logo-favicon`)
- **Déclencheur** : « SMTP », « logo », « favicon », « données entreprise ».
- **Entrées** : `42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md`.
- **Étapes** : table singleton `company_settings` ; mot de passe SMTP en `smtp_password_encrypted` (cast `encrypted`), **jamais renvoyé à l'écran** (champ vide = inchangé) ni au poste ; e-mail d'essai ; logo et favicon : validation type et taille, stockage hors `public` direct ou disque `public` avec `storage:link`, chemins en base ; poste : fichiers tirés par un point d'accès dédié ; document PDF et en-tête lisent le logo ; **pas de SMS** (retiré d'AgriERP) ; droit `manage-parametres`.
- **Sorties** : écrans `EmailSmtp`, `DonneesEntreprise`, service, tests.
- **Critères** : lecture brute en base ≠ clair ; réponse API sans secret ; fichier trop gros ou type interdit refusé avec message.
- **Interdits** : secret dans Drift ; SVG non assaini en favicon/logo (script embarqué) : n'accepter que des types listés.
- **Références** : `app/Livewire/Parametres/{EmailSmtp,DonneesEntreprise}.php`, `app/Services/EntrepriseService.php`, migration `2026_02_20_000001_create_company_settings_table.php`.

### SK-30 — Appairage d'un poste (`logialvia-appairage-poste`)
- **Déclencheur** : « appairer », « nouveau poste », « jeton du poste ».
- **Entrées** : `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`.
- **Étapes** : connexion du poste (`POST /api/auth/login`) crée un jeton Sanctum nommé par `device_name` = identifiant du poste ; l'administrateur voit et révoque les postes (`PostesAppairage`) ; `poste_synchronisations` tient l'état ; journal de chaque tirage/envoi ; demande de synchronisation adressée à un poste ou à tous (`DemandeSynchronisationService`) ; révocation = le poste est refusé à son prochain appel, ses lignes `pending` restent sur la machine ; compte archivé ou mot de passe à changer = refus API 403.
- **Sorties** : écran, API, tests.
- **Critères** : jeton révoqué = 401 ; poste visible avec dernière synchro ; aucun jeton en clair en base.
- **Interdits** : jeton sans expiration ni révocation ; mot de passe conservé au poste.
- **Références** : `app/Http/Controllers/Api/AuthController.php`, `app/Livewire/Parametres/PostesAppairage.php`, `app/Services/{DemandeSynchronisationService,JournalSynchronisationService}.php`, migration `2026_03_10_000001_create_personal_access_tokens_table.php`.

### SK-31 — Build Windows (`logialvia-build-windows`)
- **Déclencheur** : « installateur », « build Windows », « livrer le poste ».
- **Entrées** : machine Windows (Flutter, Visual Studio 2022 C++, Inno Setup 6).
- **Étapes** : vérifier la version de Flutter contre `.fvmrc` ; `flutter analyze && flutter test` verts ; `build_windows.bat` (échoue si Inno Setup ou le runtime VC++ manque ; `--sans-installateur` produit le seul dossier Release) ; installer sur une machine propre ; vérifier lancement, base créée, migration Drift depuis la version précédente, sauvegarde/restauration ; consigner la version.
- **Sorties** : installateur, rapport de build.
- **Critères** : lancement sur machine propre ; migration d'une base de la version précédente sans perte.
- **Interdits** : livrer sans test de migration ; dire « testé sur Windows » sans l'avoir fait (poste Windows réel = souvent « NON vérifié » depuis Linux).
- **Références** : `/home/user/agrierp/agrierp_flutter/build_windows.bat`, `.fvmrc`, `docs/GUIDE_DEPLOIEMENT.md`.

### SK-32 — Revue de conformité de design (`logialvia-revue-design`)
- **Déclencheur** : « revue de design », « fidélité », « recette visuelle ».
- **Entrées** : écran, classe d'écran, `04_UI_UX_DESIGN_SYSTEM.md`.
- **Étapes** : appliquer `31_TESTING_QA.md` §9 : liste commune + liste de la classe ; jetons du design system uniquement ; largeurs 1024/1280/1440 (poste) et ~390 px (web) ; capture web/poste côte à côte ; libellés web = poste (garde-fou) ; accessibilité (étiquettes, focus) ; mode sombre si prévu.
- **Sorties** : rapport avec écarts numérotés, captures, corrections.
- **Critères** : zéro écart perceptible de couleur et de position ; aucune valeur en dur.
- **Interdits** : trancher en silence une divergence Blade ↔ maquette (la signaler au client) ; corriger le poste sans corriger d'abord le web.
- **Références** : `docs/DOCTRINE_PORTAGE.md`, `docs/AUDIT_FIDELITE_ECRANS.md`, `/home/user/massenon/logialvia/docs/K2_Checklist_Recette_Visuelle.md`, `agrierp_flutter/outils/{audit_fidelite,captures,audit_jetons}.py`.

### SK-33 — Audit de sécurité (`logialvia-audit-securite`)
- **Déclencheur** : « audit de sécurité », « avant livraison », « RBAC ».
- **Entrées** : `docs/I3_Security_Strict.md` et `I1_Matrice_RBAC.md` de logialvia.
- **Étapes** : (1) toute route a un droit (garde-fou) ; (2) toute méthode Livewire qui écrit commence par `authorize()` ; (3) secrets : chiffrés, jamais dans une réponse ni dans Drift ; (4) mots de passe : politique, limitation de tentatives (5 / 15 min), réinitialisation par l'administrateur, changement forcé, jetons révoqués ; (5) sessions et verrou ; (6) injection : valeurs liées, aucun SQL téléversé exécuté ; (7) XSS : échappement Blade, téléversements validés ; (8) CSRF et en-têtes ; (9) journal d'audit sans secret ; (10) sauvegardes hors dossier public ; (11) comptes démo absents de la production ; (12) dépendances à jour.
- **Sorties** : rapport avec gravité, preuve (test ou `grep`), correction.
- **Critères** : chaque constat est accompagné d'un test qui le verrouille ; section « NON vérifié ».
- **Interdits** : corriger sans test ; masquer un constat.
- **Références** : `tests/Feature/{AuditRbacRoutesTest,AuditToutesLesRoutesTest,AutorisationsMethodesMutantesTest}.php`, `app/Support/PolitiqueMotDePasse.php`, `app/Services/{CodeSecoursService,VerrouSessionService}.php`, `docs/CODE_SECOURS_ADMIN.md`.

### SK-34 — Migration des données de logialvia vers UUID (`logialvia-migration-donnees-uuid`)
- **Déclencheur** : « migrer les données de logialvia », « autoIncrement vers UUID ».
- **Entrées** : `30_DATABASE_ENGINEERING.md` §9 ; `logialvia_app/lib/*/data/tables/` (lecture seule).
- **Étapes** : prompt **P10** de `30` : inventaire (25 colonnes, 22 fichiers), UUID v5 déterministes, recréation de tables en une transaction, correspondances temporaires, montants `REAL` → entiers (**la règle d'arrondi est À DÉFINIR AVEC LE CLIENT : échouer plutôt qu'arrondir**), regroupement des écritures par pièce, `foreign_key_check`, rapport JSON, sauvegarde préalable, tests T4 de `31`.
- **Sorties** : migration Drift v26 → v27, rapport, tests.
- **Critères** : totaux avant/après identiques à l'unité ; rejeu sans effet ; deux postes produisent les mêmes UUID de référentiels.
- **Interdits** : convertir un mot de passe ; modifier le dépôt logialvia ; fusionner des produits homonymes.
- **Références** : `30_DATABASE_ENGINEERING.md` §9.1 à §9.7 ; `agrierp_flutter/test/migration_bases_reelles_test.dart`.

### SK-35 — Seeder de données de référence (`logialvia-seeder-reference`)
- **Déclencheur** : « seeder », « amorçage », « rôles », « plan comptable », « barème ».
- **Entrées** : `30` §10 ; sources (`I1_Matrice_RBAC.md`, `I2_Gestion_Modules_Actifs.md`, `configuration_espece.dart`, `seed_initial.dart`, CSV SYSCOHADA).
- **Étapes** : prompt **P11** de `30` ; idempotent (`updateOrCreate` sur clé naturelle) ; plan comptable par `ImporterPlanSyscohadaService` (dry-run puis réel) ; empreinte vérifiée ; démo séparée (`DemoDataSeeder` refuse la production).
- **Sorties** : seeders + tests de valeurs.
- **Critères** : `migrate:fresh --seed` deux fois = mêmes comptes ; valeurs de ration = celles de `configuration_espece.dart`.
- **Interdits** : un chiffre absent des sources ; un compte démo en production.
- **Références** : `agrierp_laravel/database/seeders/` ; `database/data/plan-comptable-syscohada-revise.csv`.

### SK-36 — Preuve par mutation (`logialvia-mutation-test`)
- **Déclencheur** : « prouve que le test échoue », « mutation », « le test mord-il ? ».
- **Entrées** : tests d'un module.
- **Étapes** : prompt **T2** de `31_TESTING_QA.md` : une mutation à la fois (plancher, comparaison, `authorize()`, ventilation, arrondi, cascade, motif, idempotence, colonne d'un seul côté) ; ROUGE attendu ; annuler ; renforcer tout test resté vert.
- **Sorties** : tableau règle · mutation · résultat.
- **Critères** : 100 % rouges ; code de production inchangé à la fin.
- **Interdits** : laisser une mutation ; supprimer un test rouge.
- **Références** : `31_TESTING_QA.md` §14 (T2) ; `tests/Feature/AutorisationsMethodesMutantesTest.php`.

## 6. Trois exemples complets de SKILL.md prêts à déposer

Chaque bloc ci-dessous est le contenu intégral du fichier indiqué. Les chemins de référence sont ceux du monorepo AgriERP vérifiés ; une fois dans le dépôt LogiALVIA, remplacer le préfixe `/home/user/agrierp/agrierp_laravel/` par la racine du web LogiALVIA lorsqu'un fichier y a été recréé.

### 6.1 `.claude/skills/logialvia-migration-domaine/SKILL.md`

````markdown
---
name: logialvia-migration-domaine
description: Génère les migrations Laravel (clés UUID, montants entiers FCFA, colonnes de synchronisation) et les tables Drift jumelles d'un domaine du web LogiALVIA. À utiliser quand on demande de créer les tables, le schéma ou les migrations d'un domaine (identité, élevage, ventes, stocks/achats, comptabilité, RH, paramètres, synchronisation).
---

# Migrations d'un domaine LogiALVIA

Un domaine = une session. Tout est en français. Ne rien committer.

## Avant d'écrire

1. Lire `docs/logialvia/30_DATABASE_ENGINEERING.md` : sections 1 (principes), 3 (conventions), 5 (dictionnaire), 7 (contraintes), 8 (ordre et pièges MariaDB) et l'ERD du domaine demandé (section 4).
2. Lire les tables Drift de logialvia du domaine (`/home/user/massenon/logialvia/logialvia_app/lib/<domaine>/data/tables/`, lecture seule) et, pour le modèle, les migrations d'AgriERP : `agrierp_laravel/database/migrations/2026_02_10_000001_create_livestock_lots_table.php`, `2026_10_23_000001_create_corbeille_operations_table.php`.
3. Tout ce qui n'est écrit dans aucune source est « À DÉFINIR AVEC LE CLIENT » : ne pas créer la colonne, ajouter la question à la section 14 de `30_DATABASE_ENGINEERING.md`.

## Étapes

1. Annoncer le plan : tables, ordre de dépendance, FK, uniques, index, CHECK.
2. Une migration par table, `AAAA_MM_JJ_NNNNNN_create_<table>_table.php`, docblock français (ticket, pourquoi, source).
3. `uuid('id')->primary()` ; `foreignUuid()->constrained()` avec `restrictOnDelete()`, `cascadeOnDelete()` ou `nullOnDelete()` explicite.
4. Montants : `unsignedBigInteger` (FCFA entier). Quantités : `decimal(10,2)`. Jour : `date`. Instant : `timestamp`. Liste susceptible de grandir : `string` + validation, pas `enum`.
5. Table synchronisable : `device_id` (string 255, nul), `sync_status` (défaut `synced`), `updated_at` indexé, `is_active`. Table propre au serveur : aucune de ces colonnes.
6. Idempotence : `Schema::hasTable` / `hasColumn` ; `down()` réversible ou commenté « irréversible ».
7. `->change()` : répéter nullité, défaut et longueur ; pour un `enum`, `ALTER TABLE ... MODIFY COLUMN` sous MariaDB et `string()->change()` sous SQLite (modèle : `2026_02_28_000003_add_retard_to_attendance_records_status_enum.php`).
8. Modèles Eloquent du domaine (`HasUuids`, `$fillable` sans secret).
9. Tables Drift jumelles dans `lib/core/database/app_database.dart`, `schemaVersion` + 1, bloc `if (from < N)`, puis `dart run build_runner build`.
10. Test `tests/Feature/<Domaine>SchemaTest.php` (SQLite mémoire) : colonnes, uniques, FK refusées, CHECK, absence d'auto-incrément.

## Critères d'acceptation

- `php artisan migrate:fresh --seed` réussit.
- `grep -rnE "increments\(|bigIncrements\(|->id\(\)" database/migrations` ne renvoie rien pour ce domaine.
- Aucune colonne `float`, `double`, `decimal` ou `real` pour de l'argent.
- Chaque table figure au dictionnaire de `30_DATABASE_ENGINEERING.md` (sinon l'y ajouter).
- `php artisan test --testsuite=Feature` vert.
- Rapport final avec une section « NON vérifié » (MariaDB réel, essai multipostes, poste Windows).

## Interdits

Modifier une migration déjà livrée ; FK vers une table créée plus tard ; secret dans une colonne synchronisable ; éditer `app_database.g.dart` ; `DELETE` physique ; inventer une règle ; committer.
````

### 6.2 `.claude/skills/logialvia-fiche-journaliere/SKILL.md`

````markdown
---
name: logialvia-fiche-journaliere
description: Construit la fiche journalière d'une filière d'élevage de LogiALVIA (poissons-chats, pintades, goliaths, lapins, poulets, pondeuses) avec effectifs calculés, rationnement et tests chiffrés. À utiliser quand on demande une fiche journalière, la saisie du jour d'une filière, ou l'ajout d'une filière.
---

# Fiche journalière d'une filière

Un seul composant générique, paramétré par la configuration de la filière : ajouter une filière est une affaire de configuration, jamais de duplication d'écran. Tout est en français.

## Avant d'écrire

1. Lire `/home/user/massenon/logialvia/logialvia_app/lib/elevage/domain/entities/configuration_espece.dart` (catégories, rations, libellés, seuils), puis `docs/05_LOGIQUE_CALCUL_FORMULAIRES.md` et `F3_Module_Production_Elevage.md` de logialvia.
2. Lire `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md`, bloc 1 (règle d'effectif exacte et jeu de cas) sans le réécrire.
3. Modèles AgriERP : `agrierp_laravel/app/Services/EffectifParCategorieService.php`, `app/Livewire/Elevage/FicheLapins.php`, `FichePondeuses.php`, tests `tests/Feature/FicheLapinsEffectifAutomatiqueTest.php`.
4. Vérifier le schéma : `docs/logialvia/30_DATABASE_ENGINEERING.md` §5.4 à §5.6.

## Étapes

1. Annoncer le plan (Action d'enregistrement du jour, fonction de calcul pure, composant, vue, poste).
2. Fonction pure de calcul des effectifs par catégorie (plancher à 0, cascade unique sur les jours suivants). Les formules sont celles du guide, jamais réinventées.
3. Action `Enregistrer…FicheDuJour` : refus motivés (départ obligatoire, passage au-delà de la source), messages exacts, audit, idempotence.
4. Composant Livewire : champs de saisie (achats, nés, ventes, mortalité et dons par catégorie) ; **effectifs affichés, jamais éditables**.
5. Libellés de la filière lus de la configuration (colonne « Nés » selon la filière).
6. Rationnement du jour (skill `logialvia-rationnement`).
7. Poste : écran + dépôt Drift + parité exécutée.
8. Tests : jeu de `31_TESTING_QA.md` §4.2 ; refus ; droit ; recalcul indépendant de l'effectif affiché.

## Variantes de filière

- **Pisciculture (poissons-chats)** : Alevin / Juvénile / Mature, 30 / 60 / 110 g/j, colonne « Nés » (aucune couveuse ; l'empoissonnement se saisit en « Achats »), note de barème non confirmé. À DÉFINIR AVEC LE CLIENT : bassins, qualité de l'eau, pesée/échantillonnage, récolte partielle. Ne créer aucune colonne ni table pour cela avant réponse.
- **Pintades** : Poussins / Pintadau / Mature, 30 / 60 / 110, « Nés (Couveuse) ». À DÉFINIR AVEC LE CLIENT : durée d'incubation propre.
- **Goliaths** : Poussins / Goliathau / Mature, 30 / 60 / 110 (barème générique non confirmé), seuils de maturité 2 800 g et 120 jours présents dans le code. À DÉFINIR AVEC LE CLIENT : barème validé, définition de « maturité », combinaison des deux seuils.

## Critères d'acceptation

- Aucun champ d'effectif éditable (test de rendu).
- Les valeurs du jeu de cas sortent de l'écran ET d'un recalcul indépendant.
- Mêmes messages de refus au poste (parité exécutée).
- `php artisan test --testsuite=Feature` et `flutter analyze && flutter test` verts.
- Une seule vue de fiche pour toutes les filières.

## Interdits

Un composant par filière ; vocabulaire avicole appliqué à toutes les filières ; règle de maturité ou barème inventé ; effectif saisi ; committer.
````

### 6.3 `.claude/skills/logialvia-garde-fou-source/SKILL.md`

````markdown
---
name: logialvia-garde-fou-source
description: Écrit un garde-fou de source, c'est-à-dire un test qui lit le code pour verrouiller une convention dont la violation n'émet aucune erreur (autorisation manquante, auto-incrément, colonne présente d'un seul côté, libellé divergent web/poste), et prouve par mutation qu'il rougit. À utiliser quand on demande un garde-fou, un test qui lit le code, ou de verrouiller une règle de conventions.
---

# Garde-fou de source

Un garde-fou existe parce qu'un défaut silencieux a déjà coûté cher : une méthode ajoutée demain fonctionne parfaitement à l'écran et aucun test de rendu ne la verra. Tout est en français.

## Avant d'écrire

1. Lire `agrierp_laravel/tests/Feature/AutorisationsMethodesMutantesTest.php` (modèle PHP : parcours des fichiers, exclusions nominatives commentées) et `agrierp_flutter/test/avoirs_schema_test.dart` (modèle Dart).
2. Lire `docs/logialvia/31_TESTING_QA.md` §3.1 (garde-fous types) et §14, prompt T2.

## Étapes

1. Écrire la convention en UNE phrase vérifiable et le défaut silencieux qu'elle évite.
2. Écrire le test qui parcourt les fichiers (`glob` + regex) ; il ne dépend d'aucune base.
3. Liste d'exclusions : une entrée par exception, de la forme `fichier::méthode`, chacune commentée avec sa raison. Jamais de motif large.
4. Message d'échec en français : fichier, ligne, règle violée, correction attendue.
5. Preuve de mutation : introduire UNE violation dans une copie de travail, constater ROUGE avec le bon message, annuler, constater VERT.
6. Consigner le garde-fou dans la matrice exigence → test (`docs/logialvia/MATRICE_EXIGENCES_TESTS.md`).

## Critères d'acceptation

- Vert sur le code sain, rouge sur l'exemple cassé, avec message utile.
- Les exclusions sont nominatives et justifiées.
- `php artisan test --testsuite=Feature` (ou `flutter test`) vert ; code de production inchangé hors tests.

## Interdits

Exclusion par motif large ; garde-fou sans preuve de mutation ; garde-fou qui lit un fichier généré (`app_database.g.dart`) ; modifier le code de production pour faire passer le garde-fou sans le corriger réellement ; committer.
````

## 7. Questions ouvertes

| # | Question | Skill concerné |
|---|---|---|
| Q-SK1 | Les exports « Excel » du web doivent-ils produire du xlsx (AgriERP : CSV au web, xlsx seulement au poste) ou du CSV ? | SK-11 |
| Q-SK2 | Que désigne « VMS » dans l'énoncé du projet ? Mes sources décrivent la fenêtre « Rappels du jour » (soins, traitements du barème, délais d'attente) mais pas cet acronyme. | SK-21 |
| Q-SK3 | L'import xlsx en masse est-il voulu, pour quelles tables, avec quels gabarits de colonnes ? (n'existe pas dans AgriERP) | SK-12 |
| Q-SK4 | Pisciculture, pintades, goliaths : bassins, qualité de l'eau, pesées, durée d'incubation, barèmes validés, définition de la maturité (voir `30` §6.2 et §14) | SK-24, SK-25 |
| Q-SK5 | Seuil d'autonomie alimentaire (3 jours chez AgriERP) valable pour LogiALVIA ? | SK-25 |
| Q-SK6 | Une remise en stock accompagne-t-elle un avoir sur un animal vivant ? | SK-27 |
| Q-SK7 | Les skills `prd` et `plan` d'AgriERP sont-ils copiés dans le dépôt LogiALVIA (adaptés) ou partagés ? | SK-22, SK-23 |
