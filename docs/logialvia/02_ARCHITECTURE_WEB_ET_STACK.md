# 02 — ARCHITECTURE À RESPECTER ET STACK TECHNIQUE (web LogiALVIA)

## USAGE

| Rubrique | Contenu |
|---|---|
| **Quand l'utiliser** | Au tout début du chantier web (« W0 : socle serveur ») pour créer `logialvia_web/` ; puis comme référence à chaque fois qu'un ticket ajoute une dépendance, une route, une table, une tâche planifiée ou un réglage d'hébergement. |
| **Ordre** | Après `01_MASTER_PROMPT.md`, avant `03_DEVELOPMENT_STANDARDS.md` et `04_UI_UX_DESIGN_SYSTEM.md`. Les modules (`20_MODULES_*`) supposent ce socle en place. |
| **Entrées requises** | Le dépôt LogiALVIA cloné ; PHP 8.3, Composer 2, Node 20+ ; accès en lecture à `/home/user/agrierp/agrierp_laravel/` (modèle à reproduire, pas à copier aveuglément). Le client a-t-il confirmé l'hébergeur (cPanel ?) et le sous-domaine ? Sinon voir « À DÉFINIR ». |
| **Sorties attendues** | `logialvia_web/` qui démarre (`composer install`, `npm run build`, `php artisan migrate:fresh --seed`, `php artisan test --testsuite=Feature` vert), avec : layout, charte de jetons (voir 04), authentification, rôles, points de passage uniques, route `/api/sync/*` squelette, polices et icônes locales, `.env.production.example`, tâche planifiée unique, `CLAUDE.md` du dossier. Un rapport au format du MASTER PROMPT. |

### Réponse courte (la question du client)

- **Architecture** : Laravel 12 (PHP 8.3) + Livewire 3, **plate et pragmatique** (`app/Livewire/{Module}`, `Actions`, `Services`, `Models`, `Support`) ; PAS de hexagonal/DDD côté web.
- **Navigation rapide « comme Vue/Node »** : `wire:navigate` (Livewire 3, mode SPA-like) + barre de progression + `@persist` ; pas de Vue, pas d'Inertia, pas de Node en production.
- **Poste** : Flutter Windows + Drift/SQLite reste tel quel ; il synchronise avec le web par `/api/sync/*` (jetons Sanctum par poste).
- **Dépendances** : liste fermée à la section 6 ; toute autre demande une justification écrite.

---

## PROMPT (à copier)

````markdown
# RÔLE
Tu es l'architecte-développeur chargé de créer le socle du WEB LogiALVIA (`logialvia_web/`), en reproduisant les
conventions de LogiAgriERP (`/home/user/agrierp/agrierp_laravel/`). Tout est en français. Lis d'abord
`01_MASTER_PROMPT.md` (hiérarchie des sources, interdits, définition de terminé).

# CONTEXTE
LogiALVIA = Flutter seul aujourd'hui (`logialvia_app/`, Windows, Drift, 31 écrans, 6 filières : goliaths, pintades,
lapins, poissons-chats, poulets, pondeuses). Le client crée son web (décision du 07/11/2026). Le web devient
l'autorité de référence ; le poste y est fidèle. LogiAgriERP a déjà payé les pièges ci-dessous : ne les repaie pas.

# TÂCHES (une par session ; arrête-toi à la fin de chacune et rapporte)

T1. SOCLE LARAVEL. `composer create-project laravel/laravel logialvia_web "^12.0"` PUIS lire et reproduire
    `agrierp_laravel/composer.json`, `package.json`, `tailwind.config.js`, `vite.config.js`, `postcss.config.js`,
    `bootstrap/app.php`, `resources/js/app.js`, `resources/views/layouts/app.blade.php`. Piège PAYÉ : AgriERP est né
    d'un « overlay » sur un squelette incomplet ; vérifie que `tests/TestCase.php`, `app/Http/Controllers/Controller.php`,
    `routes/api.php`, `routes/console.php`, `AppServiceProvider` existent réellement. Ne présume rien.
T2. DÉPENDANCES. N'installe QUE la liste de la section 6 (versions épinglées en `^` comme dans le modèle). Pour
    chaque paquet : commande exacte, version résolue, raison. Aucun autre paquet sans accord écrit du client.
T3. MODÈLE DE DONNÉES. Clés UUID partout (`$table->uuid('id')->primary()`), `users.id` compris ;
    `uuidMorphs('model')` dans la migration Spatie ; `config/permission.php` : `column_names.model_morph_key = model_id`.
    JAMAIS `vendor:publish` pour Sanctum ou Spatie. Suppression logique seulement. Colonnes de synchro communes
    (voir 30_DATABASE_ENGINEERING.md).
T4. COUCHES. Crée `app/Livewire/{Module}`, `app/Actions`, `app/Services`, `app/Models`, `app/Support`. N'ajoute PAS
    `app/Domain`, `app/Application`, `app/Infrastructure`. Crée les POINTS DE PASSAGE UNIQUES (section 3) avant tout
    module qui écrit en comptabilité ou en stock.
T5. ROUTES ET DROITS. `routes/web.php` : `Route::get('/x', Composant::class)->name('…')->middleware(['auth','can:view-…'])`
    (jamais la syntaxe contrôleur-tableau pour une page Livewire). Seuls les écrans « profil, tableau de bord,
    notifications, aide » sont `auth` seuls. Les 3 rôles : `admin`, `caissier`, `animalier`. Test de route : toute
    route nommée est soit `auth`+`can:`, soit dans une liste blanche explicite.
T6. NAVIGATION SANS RECHARGEMENT. Applique la section 4 (wire:navigate, persist, progression, pièges).
T7. FRONT LOCAL. Applique la section 7 (polices, icônes, jetons). `npm run build` ne doit référencer aucune URL externe.
T8. SÉCURITÉ ET HÉBERGEMENT. Applique les sections 8 et 9 (limiteurs, en-têtes, sessions, .htaccess, cron, .env).
T9. SYNCHRO (squelette). `routes/api.php` : `POST /api/auth/login` (throttle 5/min), puis groupe `auth:sanctum` :
    `/api/auth/logout`, `/api/auth/me`, `GET /api/sync/pull?since=…`, `POST /api/sync/push` ; contrôleur mince,
    toute la logique dans Actions/Services (même appelées depuis les composants Livewire). Détail : 43_APPAIRAGE_…
    et `agrierp_laravel/CLAUDE.md` « Offline sync ».
T10. DOCUMENTATION. Écris `logialvia_web/CLAUDE.md` (miroir de `agrierp_laravel/CLAUDE.md` : commandes, couches,
    points de passage, pièges) et marque « À DÉFINIR AVEC LE CLIENT » tout ce que les sources ne tranchent pas.

# CONTRAINTES
- Aucun CDN ni Google Fonts. Aucun secret versionné. Aucune dépendance hors liste. Aucune règle métier inventée.
- Le poste n'est pas modifié dans ces tâches.

# CRITÈRES D'ACCEPTATION (vérifiables)
- `php artisan test --testsuite=Feature` passe (précise `--testsuite=Feature` : un `phpunit.xml` qui déclare une suite
  `Unit` inexistante fait échouer `php artisan test` seul).
- `php artisan route:list` : chaque route de page porte `auth` ; chaque route métier porte `can:`.
- `grep -rn "Alpine.start\|import Alpine" resources/js` : aucun résultat.
- `grep -rln "fonts.googleapis\|fonts.gstatic\|cdn.jsdelivr\|unpkg.com\|cdnjs" resources public` : aucune balise ;
  test automatisé (équivalent de `PwaEtPolicesLocalesTest`) qui l'impose.
- Toutes les clés primaires des migrations métier sont des UUID (grep `autoIncrement\|->id()` : rien).
- `public/.htaccess` sert `.webmanifest` en `application/manifest+json`.
- Un seul cron cPanel (`schedule:run`), toutes les tâches dans `routes/console.php`.

# INTERDITS
Hexagonal/DDD ; contrôleurs pour des pages Livewire ; modale par `@if` ; classes Tailwind dynamiques ; seconde
instance d'Alpine ; `wire:poll` sans raison écrite ; `vendor:publish` Sanctum/Spatie ; logique métier dans Blade ;
iframe pour un hub ; Reverb/WebSocket sans besoin validé.
````

---

## 1. Principes d'architecture (réels, vérifiés sur AgriERP)

Source : `agrierp_laravel/CLAUDE.md`, sections « Layering » et « Single points of passage ».

| Couche | Rôle | Règle |
|---|---|---|
| `app/Livewire/{Module}/` | Orchestre : validation, état de page, `authorize()`, événements | AgriERP : 97 composants groupés par module (Elevage, Ventes, Achats, Stocks, Comptabilite, RH, Facturation, Rapports, Parametres, Administration, Shared…). Aucune formule de calcul. |
| `app/Actions/` | Effet de bord unique : « cet événement métier produit aussi son écriture / son mouvement de stock / sa mise à jour de fiche » | Appelées par Livewire ET par le contrôleur de synchro. Nom = verbe métier (`SaisieBandeAction`, `RecordSaleAccountingEntryAction`). |
| `app/Services/` | Calcul multi-étapes, rapports, PDF, sauvegarde, corbeille | Pur autant que possible : testable sans HTTP. Ex. `EffectifParCategorieService` (effectif calculé). |
| `app/Models/` | Eloquent seulement | UUID, casts, relations, scopes. Pas de logique de workflow. |
| `app/Support/` | Constantes, énumérations, utilitaires purs | Ex. `ExerciceChoisi`, `StadePondeuse`, `MessagesErreurFr`. |
| `app/Http/Controllers/Api/` | Mince : valide, appelle une Action/Service, formate | `SyncController`, `AuthController`. |

Pas de `app/Domain`, `app/Application`, `app/Infrastructure` : la structure Clean/DDD en trois couches de
`logialvia_app/lib/<module>/{data,domain,presentation}` est une contrainte Flutter, elle ne se transpose pas au web.

### Points de passage uniques (à créer EN PREMIER ; chemins modèles vérifiés)

| Mécanisme | Point d'entrée UNIQUE | Invariant | Modèle AgriERP |
|---|---|---|---|
| Écriture comptable | `AccountingEntryService::record()` / `recordManual()` | débit = crédit au centime, vérifié AVANT écriture ; date dans un exercice OUVERT (par couverture de date) ; saisie manuelle à 2 lignes : comptes distincts | `agrierp_laravel/app/Services/AccountingEntryService.php` |
| Stock produit | `AdjustStockAction::execute()` | le mouvement `stock_movements` s'écrit dans le même appel | `agrierp_laravel/app/Actions/AdjustStockAction.php` |
| Facture normalisée | passerelle `MecefGatewayInterface` résolue par `MecefGatewayFactory`, appelée via `FacturationMecefService` APRÈS la transaction | une vente `normalisée` transmise n'est JAMAIS retransmise et est verrouillée ; un seul constructeur de charge utile | `agrierp_laravel/app/Services/Mecef/` (voir `41_MECEF_EMECEF.md`) |
| Règles de mot de passe | `Password::defaults()` dans `AppServiceProvider::boot()` | `uncompromised()` volontairement absent (appel d'API distante : bloquerait la création de compte si le lien de la ferme tombe) | `agrierp_laravel/app/Providers/AppServiceProvider.php` |
| Exercice affiché | `ExerciceChoisi` (affichage) ; `FiscalYear::current()` sert à écrire/décider, jamais à afficher | | `agrierp_laravel/app/Support/ExerciceChoisi.php` |
| Archivage | `CorbeilleService` + `AuditLog::record()` (action listée dans `ACTIONS_ARCHIVAGE`) | un chemin d'archivage sans audit n'apparaît pas dans la Corbeille | `agrierp_laravel/app/Services/CorbeilleService.php`, `agrierp_laravel/app/Models/AuditLog.php` |
| Ordre de verrous | `OrdreDesVerrous::stock` : verrouiller les lignes `products` par id croissant AVANT toute fiche/lot | évite les interblocages entre deux envois simultanés | `agrierp_laravel/app/Support/OrdreDesVerrous.php` |

Tout flux financier (vente, achat, dépense, paie, avoir, amortissement, règlement, virement, écart d'inventaire)
produit son écriture via une Action dédiée ; les rapports lisent `accounting_entries` / `accounting_entry_lines`, jamais
des tables métier recalculées à part. La trésorerie a deux livres (table `treasury_accounts` + comptes de classe 5) :
tout mouvement d'argent met les deux à jour. Le plan comptable de LogiALVIA est à confirmer
(`logialvia/docs/F6_Module_Comptabilite.md` mentionne SYSCOHADA : À DÉFINIR AVEC LE CLIENT si un plan autre est voulu).

### Modèle de données (UUID, synchronisation)

- Clés primaires UUID, `users.id` inclus (clients hors ligne qui écrivent en parallèle : l'auto-incrément entre en collision).
  Conséquence : migration Spatie avec `uuidMorphs('model')`, `config/permission.php` `model_morph_key = model_id`.
- Suppression logique (`is_active` / `status`). `CorbeilleService` liste et restaure ; les écritures comptables en sont exclues
  par construction (on les contre-passe).
- Montant d'une ligne de vente = `manual_total_amount` (source de vérité) ; `unit_price` dérivé pour l'affichage.
  Règle d'AgriERP : à confirmer pour LogiALVIA dans `logialvia/docs/F4_Module_Ventes_Clients.md` (le POS du poste « demande le
  montant » : K2 A.1) avant de reproduire quoi que ce soit.
- Le schéma est PARTAGÉ : une table synchronisable modifiée au web l'est aussi dans `logialvia_app/lib/core/database/app_database.dart`
  (puis `dart run build_runner build`) ; `app_database.g.dart` n'est jamais édité à la main.

### Droits : deux niveaux, toujours

Niveau 1 : `->middleware(['auth', 'can:view-elevage'])` sur la route. Niveau 2 : `$this->authorize('manage-elevage');` première
ligne de TOUTE méthode mutante. `@hasanyrole` dans le menu est cosmétique. Permissions `view-{module}` / `manage-{module}` +
droits transverses (`close-fiscal-year`, `manage-users`, `manage-modules`, `export-*`). Rôles de LogiALVIA : trois
(`admin`, `caissier`, `animalier`) d'après `logialvia/docs/I1_Matrice_RBAC.md`. Aucun `Gate::before` admin : une permission non
semée est inaccessible à tous. Tests de référence : `agrierp_laravel/tests/Feature/AuditRbacRoutesTest.php`,
`AuditToutesLesRoutesTest.php`, `AutorisationsMethodesMutantesTest.php`.

---

## 2. Schéma d'ensemble : web <-> poste <-> synchronisation

```
                          NAVIGATEUR (bureau, tablette, mobile)
                 Livewire 3 + Alpine (embarqué) + Tailwind compilé + Material Symbols local
                       wire:navigate (pages) | wire:model.live.debounce | @persist
                                          |  HTTPS
                                          v
+----------------------------- logialvia_web (Laravel 12, PHP 8.3) -----------------------------+
|  routes/web.php  --auth--> can:view-* --> app/Livewire/{Module}  (authorize('manage-*') 1re ligne)|
|                                                |                                               |
|                                                v                                               |
|                    app/Actions  <---->  app/Services   (calculs, rapports, PDF)                |
|                       |   |                                                                    |
|     +-----------------+   +--------------------+                                               |
|     v                                          v                                               |
|  AccountingEntryService::record()      AdjustStockAction::execute()     (points de passage)    |
|     \______________________  MySQL/MariaDB utf8mb4, clés UUID, suppression logique  ___________/|
|                                                                                                |
|  routes/api.php  --auth:sanctum, throttle--> SyncController (pull paginé / push transactionnel)|
|  routes/console.php --> schedule:run (1 cron cPanel/minute) : sauvegarde, alertes, rappels     |
+------------------------------------------------^-----------------------------------------------+
                                                 |  HTTPS, jeton Sanctum PAR POSTE (+ PIN local)
                       GET /api/sync/pull?since=…   |   POST /api/sync/push
                                                 v
+------------------------- logialvia_app (Flutter Windows, hors ligne) ---------------------------+
|  Drift/SQLite local (clés UUID après migration) <-> moteur de synchro <-> écrans (31)            |
|  Référentiels : le serveur gagne. Fiches : dernier écrivain. Ventes : jamais fusionnées.        |
|  Mouvements de stock : rejoués par AdjustStockAction côté serveur. Clôture : DEMANDE rejouée.   |
+------------------------------------------------------------------------------------------------+
Règle : le poste ne contourne jamais un point de passage ; il envoie des FAITS ou des DEMANDES, le serveur recalcule.
```

Règles de réconciliation reprises d'AgriERP (à confirmer pour LogiALVIA par `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md` et
`GUIDE_PORTAGE…`, blocs 15 et 16) : référentiels = le serveur gagne ; fiches journalières = dernier écrivain par `id`, colonne
`vente` jamais prise du poste ; ventes = jamais fusionnées ; mouvements de stock = rejoués ; tout le `push` = une transaction
rejouée 3 fois sur interblocage ; `pull` paginé par curseur `(updated_at, id)`. Détail et pièges : `agrierp_laravel/CLAUDE.md`
« Offline sync » et `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md`.

---

## 3. Arbre de dossiers cible du dépôt LogiALVIA (monorepo)

Tout chemin ci-dessous marqué (à créer) n'existe pas encore ; `logialvia_app/` et `docs/` existent.

```
logialvia/                              dépôt massenon/logialvia (monorepo cible)
├── CLAUDE.md                           (à créer) miroir du CLAUDE.md racine d'AgriERP
├── .claude/skills/{prd,plan}/SKILL.md  (à créer) copies adaptées des skills d'AgriERP
├── docs/                               existe (A1…K4, F1…F9, B1…B6) + docs/logialvia/ ou ce dossier de prompts
│   ├── DOCTRINE_PORTAGE.md             (à créer) adaptée de docs/DOCTRINE_PORTAGE.md d'AgriERP
│   ├── PLAN_FINALISATION.md            (à créer) tickets restants et décisions client en attente
│   └── prd/                            (à créer) un PRD par ticket
├── logialvia_app/                      existe : Flutter Windows (lib/<module>/{data,domain,presentation}, core/)
│   └── lib/core/database/app_database.dart   schéma Drift ; app_database.g.dart GÉNÉRÉ, jamais édité
└── logialvia_web/                      (à créer) Laravel 12 + Livewire 3
    ├── app/
    │   ├── Actions/                    effets de bord uniques (comptabilité, stock, fiches)
    │   ├── Http/{Controllers/Api,Middleware}/   SyncController, AuthController, SessionVerrouillee…
    │   ├── Jobs/                       rappels, alertes (planifiés)
    │   ├── Livewire/{Pilotage,Elevage,Commercial,Approvisionnement,Comptabilite,Rapports,Administration,Profil,Auth,Shared}/
    │   ├── Models/                     Eloquent UUID
    │   ├── Providers/AppServiceProvider.php   Password::defaults(), directives Blade
    │   ├── Services/                   AccountingEntryService, calculs, PDF, sauvegarde, corbeille
    │   └── Support/                    ExerciceChoisi, MessagesErreurFr, énumérations
    ├── bootstrap/app.php               middleware, routing, rendu des erreurs en français
    ├── config/                         permission.php (model_morph_key), sanctum.php, livewire.php (publié), mecef.php…
    ├── database/{migrations,seeders,factories}/   UUID ; RolesAndPermissionsSeeder (3 rôles)
    ├── lang/{fr/validation.php, fr.json}          messages français ; APP_LOCALE=fr
    ├── public/{.htaccess,assets/{fonts,icons,images},manifest.webmanifest,sw.js,offline.html,build/}
    ├── resources/{css/app.css,js/app.js,views/{layouts,components,livewire/{module}/…,errors}}
    ├── routes/{web.php,api.php,console.php}
    ├── tests/{Feature,Browser,Js}/     Feature (RefreshDatabase, sqlite :memory:), Dusk, node --test
    ├── .env.example  .env.production.example  (aucun .env versionné)
    ├── composer.json  package.json  tailwind.config.js  postcss.config.js  vite.config.js  phpunit.xml
    └── CLAUDE.md                       (à créer) commandes, couches, pièges du web LogiALVIA
```

Modèle réel correspondant : `agrierp_laravel/` (`app/`, `bootstrap/`, `config/`, `database/`, `lang/`, `public/`, `resources/`,
`routes/`, `tests/{Feature,Browser,Js}`), vérifié par `ls`.

---

## 4. Navigation rapide sans rechargement complet (« comme Vue/Node »)

Réponse : **`wire:navigate`**, fourni par Livewire 3.8 (AgriERP : `livewire/livewire` v3.8.4). Livewire intercepte le clic,
charge la page voisine en arrière-plan, remplace le `<body>`, met à jour titre et URL (historique compris), SANS recharger
scripts, feuilles de style ni polices. Ce n'est PAS une SPA : chaque navigation fait une requête serveur (page rendue en PHP) ;
on économise le rechargement du navigateur (clignotement blanc, perte d'état), pas l'aller-retour réseau. Ni Vue, ni Inertia, ni
Node en production : une réécriture de tous les composants pour aucun gain. Étude complète et plan par tickets :
`docs/prd/navigation-sans-rechargement.md` (AgriERP) ; état réel : `wire:navigate` est déjà posé sur `components/sidebar-link.blade.php`,
`components/nav-card.blade.php`, l'Accès Rapide et la barre mobile de `resources/views/layouts/app.blade.php`, mais AUCUN `@persist`
n'existe encore (vérifié par grep) : c'est un acquis à ne pas présumer.

### Règles à appliquer (par ordre de priorité)

1. **`wire:navigate` sur tout lien de page interne** : barre latérale, Accès Rapide, barre mobile, cartes de hub (`nav-card`),
   onglets qui sont des pages. **Jamais** sur : `a[download]`, exports PDF/tableur, `target="_blank"`, connexion/déconnexion,
   pages publiques, liens vers `/storage/…`.
2. **`wire:navigate.hover`** sur la barre latérale seulement (précharge au survol, ~200 ms de gain) ; mesurer avant de généraliser :
   une requête serveur par survol.
3. **Barre de progression** : activée par défaut ; publier `config/livewire.php` (`navigate.show_progress_bar` = true,
   `progress_bar_color` = couleur primaire de la charte LogiALVIA, voir 04). Publier la configuration de Livewire est permis : l'interdit
   de `vendor:publish` ne vise que Sanctum et Spatie.
4. **`@persist('nom')`** pour ce qui doit survivre au remplacement du `<body>` : conteneur de toasts, surcouche de verrouillage de
   session, invitation d'installation PWA, éventuellement le lecteur/mini-panneau persistant. Piège : un élément persisté n'est
   PAS re-rendu, donc **la barre latérale (entrée active calculée côté serveur) ne se persiste pas** tant que l'entrée active n'est
   pas calculée côté Alpine ; on restaure seulement son défilement (`livewire:navigated`) et son état replié (`localStorage`).
5. **Scripts de l'en-tête** réévalués à chaque navigation : poser `data-navigate-once` sur le `<script>` d'installation PWA ; sinon
   les écouteurs `beforeinstallprompt` s'accumulent. Tout `addEventListener` sur `window`/`document` fait par une page doit être
   rattaché à `livewire:navigate` / nettoyé (`Alpine.cleanup`).
6. **Pas de 2e instance d'Alpine** : `resources/js/app.js` n'importe pas Alpine et n'appelle jamais `Alpine.start()` ; les plugins
   (`@alpinejs/collapse`) se branchent par `document.addEventListener('alpine:init', () => window.Alpine.plugin(collapse))`. Symptôme
   d'une 2e instance : « Detected multiple instances of Alpine running », `$wire is not defined`, formulaires qui ne partent plus,
   alors que les tests `Livewire::test()` passent (ils n'exécutent aucun JavaScript).
7. **Hubs = composants imbriqués**, jamais d'iframe : `<livewire:elevage.fiche-espece espece="pondeuses" />` dans le hub. Un écran
   non encore construit affiche `<x-module-pending>`, jamais une route fantôme.
8. **Recherche en direct** : `wire:model.live.debounce.300ms` (unique, dans `x-datatable`) ; ne réimplémente pas par écran.
9. **Chargement différé** : `lazy` (attribut `#[Lazy]` + `placeholder()`) pour les cartes lourdes d'un tableau de bord (graphiques,
   KPI agrégés), avec un squelette de la taille finale (pas de saut de mise en page) ; ne PAS mettre en `lazy` un composant dont
   dépend une modale ou une autorisation.
10. **`wire:loading`** : `wire:loading.class="opacity-50"` sur les corps de tableau, `wire:loading.attr="disabled"` sur les boutons
    d'enregistrement (anti double-clic = anti double écriture).
11. **`wire:poll`** : seulement avec une raison écrite (compteur de notifications de la cloche, état de synchronisation). Toujours
    `wire:poll.30s` ou plus lent, `.visible` pour ne pas interroger un onglet caché ; jamais sur un formulaire de saisie.
12. **Session expirée (419)** : remplacer la boîte anglaise de Livewire (« This page has expired… ») par un rechargement ou un message français,
    via `Livewire.hook('request', ({ fail }) => …)` (déjà fait dans `agrierp_laravel/resources/js/app.js`).
13. **Cas d'erreur à ne jamais laisser « marcher en silence »** : redirection `/login` suivie proprement ; session verrouillée (423) :
    la surcouche s'ouvre, aucune page cible ne s'affiche ; droits refusés (403) : page 403 complète, jamais le contenu même une
    fraction de seconde ; réseau coupé : retour au chargement classique et `offline.html`.
14. **Version des ressources** : après un déploiement, Livewire détecte le changement des fichiers Vite et force un rechargement
    complet : comportement voulu, à ne pas contrarier.

Preuve : un test navigateur (Dusk) vérifie qu'une variable posée sur `window` survit à un clic de la barre latérale, que l'URL, le
titre et l'entrée active correspondent, que « Retour » fonctionne, et que le verrou de session survit (voir 31_TESTING_QA.md).

---

## 5. Configuration réelle à reproduire (fichiers modèles)

| Fichier modèle | À reprendre | Adapter pour LogiALVIA |
|---|---|---|
| `agrierp_laravel/bootstrap/app.php` | `withRouting(web, api, commands, health: '/up')` ; groupe `web` : `SessionVerrouillee`, `ChangementMotDePasseObligatoire` ; rendu d'erreurs JSON en français (`MessagesErreurFr::traduireJson`) ; déconnexion sur 419 sans page d'erreur | noms, messages |
| `agrierp_laravel/resources/js/app.js` | plugin collapse par `alpine:init` ; hook 419 ; pas d'`Alpine.start()` | couleur de progression |
| `agrierp_laravel/vite.config.js` | `laravel-vite-plugin`, entrées `resources/css/app.css` + `resources/js/app.js`, `refresh: true` | — |
| `agrierp_laravel/postcss.config.js` | `tailwindcss`, `autoprefixer` | — |
| `agrierp_laravel/tailwind.config.js` | `content` (vues, `app/Livewire`, `app/View/Components`, pagination, `storage/framework/views`), jetons, `@tailwindcss/forms` | JETONS DE LOGIALVIA (voir 04) : navy/or, pas le vert d'AgriERP |
| `agrierp_laravel/resources/views/layouts/app.blade.php` | `<html lang="fr">`, preload des polices locales, manifeste, `@vite`, barre latérale `fixed lg:static`, barre du haut `h-16`, barre mobile `h-16`, Accès Rapide | libellés, menu, jeux d'icônes |
| `agrierp_laravel/config/permission.php` | `model_morph_key = model_id` | — |

Tailwind : version **3.4** (3.4.17 dans `package.json`), pas la 4 : la configuration en `tailwind.config.js` et les jetons `spacing.md` etc.
en dépendent. Une migration vers Tailwind 4 est un ticket à part, jamais un effet de bord.

Session / file / cache : `SESSION_DRIVER=database`, `QUEUE_CONNECTION=database`, `CACHE_STORE=database` (hébergement mutualisé, aucun Redis).
`SESSION_LIFETIME=480`. En production : `SESSION_SECURE_COOKIE=true`. `BROADCAST_CONNECTION=reverb` figure dans `.env.example` d'AgriERP
et `laravel/reverb` dans son `composer.json` MAIS aucune infrastructure Reverb n'est câblée (`app/Jobs/DailyProphylaxyReminderJob.php`
le dit) : **ne pas installer Reverb dans LogiALVIA** sans besoin validé ; `BROADCAST_CONNECTION=log`.

---

## 6. Dépendances à installer (liste fermée) — versions réellement résolues dans AgriERP

### Composer (`logialvia_web/composer.json`)

| Paquet | Contrainte | Version résolue dans `agrierp_laravel/composer.lock` | Usage réel vérifié | Décision pour LogiALVIA |
|---|---|---|---|---|
| `php` | `^8.3` | — | — | obligatoire (hébergeur : PHP 8.3 exigé) |
| `laravel/framework` | `^12.0` | v12.65.0 | socle | obligatoire |
| `livewire/livewire` | `^3.5` | v3.8.4 | composants, `wire:navigate` | obligatoire |
| `laravel/sanctum` | `^4.0` | v4.3.3 | jetons par poste (`User`, `PostesAppairage`) | obligatoire (synchro) — NE PAS `vendor:publish` |
| `spatie/laravel-permission` | `^7.0` | 7.4.2 | rôles/permissions (`User`, `Role`, `Permission`) | obligatoire avec `uuidMorphs` — NE PAS `vendor:publish` |
| `barryvdh/laravel-dompdf` | `^3.0` | v3.1.2 (dompdf 3.1.6) | PDF (`PdfExportService`, attestations, GL, plan comptable) | obligatoire (polices PDF Unicode : voir 03) |
| `simplesoftwareio/simple-qrcode` | `^4.2` | 4.2.0 | QR (fiche animal, facture normalisée) | conditionnel : seulement si fiche sujet / facture MeCeF QR (41_MECEF_EMECEF) |
| `maatwebsite/excel` | `^3.1` | 3.1.69 (+ `phpoffice/phpspreadsheet` 1.30.6) | déclaré dans `composer.json` d'AgriERP (en DOUBLE) mais aucun `use Maatwebsite` dans `app/` : les exports sont des PDF et des flux `streamDownload` | conditionnel : à n'installer que pour l'export/import tableur (guide, blocs 7 et 21) ; déclarer UNE seule fois |
| `laravel/tinker` | `^2.9` | v2.11.1 | dev/diagnostic | dev seulement en pratique |
| `laravel/reverb` | `^1.0` | v1.11.0 | NON câblé | NE PAS installer |

Dev : `laravel/dusk` (`^8.2`, v8.6.0, parcours navigateur), `laravel/pint` (`^1.13`, v1.30.5), `phpunit/phpunit` (`^11.0.1`, 11.5.56),
`mockery/mockery`, `fakerphp/faker`, `nunomaduro/collision`, `laravel/pail`. Analyse statique : AgriERP n'en a PAS (aucun
`phpstan`/`larastan` dans son `composer.json` : vérifié). Ajouter `larastan/larastan` (niveau à définir) est une proposition
nouvelle, à valider (voir 03, « Qualité »). `laravel/sail` : inutile (Laragon/cPanel).

### npm (`logialvia_web/package.json`, `"type": "module"`)

| Paquet | Contrainte | Rôle |
|---|---|---|
| `vite` | `^5.4.11` | build |
| `laravel-vite-plugin` | `^1.1.1` | intégration Laravel |
| `tailwindcss` | `^3.4.17` | CSS compilé (Tailwind CLI via PostCSS) |
| `postcss`, `autoprefixer` | `^8.4.49`, `^10.4.20` | chaîne CSS |
| `@tailwindcss/forms` | `^0.5.9` | champs de formulaire |
| `alpinejs` | `^3.14.8` | dépendance de TYPE uniquement ; l'instance exécutée est celle de Livewire (ne jamais la démarrer soi-même) |
| `@alpinejs/collapse` | `^3.14.8` | plugin enregistré sur l'instance Livewire |
| `axios` | `^1.7.9` | présent dans le modèle ; à retirer s'il n'est pas utilisé (aucun appel XHR manuel : Livewire suffit) |
| Tests JS | aucun paquet : `node --test tests/Js` (modules `.mjs`, `node:test`) | logique pure (verrou de session) |

Aucune bibliothèque de graphiques, de date, d'UI (pas de Bootstrap/jQuery) n'est installée dans AgriERP. Si un graphique est nécessaire
(courbe de croissance, CA vs dépenses), AgriERP en dessine un composant Blade/SVG (`resources/views/components/courbe-gmq.blade.php`) :
suivre ce précédent avant d'ajouter Chart.js (ajout = accord écrit).

---

## 7. Front-end local : polices, icônes, jetons

- **Aucun CDN, aucun Google Fonts, aucune requête externe au chargement** (hors ligne partiel, connexion de ferme instable). Test
  automatisé de référence : `agrierp_laravel/tests/Feature/PwaEtPolicesLocalesTest.php` (11 tests) ; il ignore les COMMENTAIRES Blade
  (les docblocks citent `fonts.googleapis.com` pour expliquer l'interdit) et refuse les balises `<link>`/`<script>` externes.
- **Police de texte** : variable `.woff2`, un fichier par sous-ensemble (`latin` toujours, `latin-ext` seulement si un caractère de la
  plage apparaît, via `unicode-range`), `@font-face` avec `font-weight: 100 900` (déclarer `400` ferait synthétiser un faux gras et
  déformerait les titres), `font-display: swap`, `<link rel="preload" as="font" crossorigin>`. AgriERP : `Inter-latin.woff2` 48 Ko +
  `Inter-latin-ext.woff2` 85 Ko dans `public/assets/fonts/`. **LogiALVIA : le poste embarque ROBOTO variable** (`logialvia/logialvia_app/assets/fonts/Roboto-Variable.ttf`,
  famille `Roboto`), pas Inter. Pour la conformité web <-> poste, le web doit servir Roboto (conversion `.ttf` -> `.woff2` en sous-ensembles
  `latin`/`latin-ext`, licence OFL-1.1 pour la variable, voir `logialvia/logialvia_app/assets/fonts/LICENSE-Roboto-variable-OFL-1.1.txt`).
  Garder Inter n'est qu'un choix du client qui impose de changer le poste aussi : À DÉFINIR AVEC LE CLIENT (Q-DS-1, voir 04).
- **Icônes** : Material Symbols Outlined, police locale **sous-ensemble** (AgriERP : 37 Ko au lieu de 3,87 Mo), classe
  `.material-symbols-outlined` avec `font-variation-settings: 'FILL' 0, 'wght' 400, 'GRAD' 0, 'opsz' 24` (réglages par défaut du poste via
  `material_symbols_icons`) ; `font-display: block` (pas de lettre « nue » en attendant la police). Générer le sous-ensemble à partir de la liste
  RÉELLE des noms d'icônes utilisés (`grep -o "material-symbols-outlined[^<]*<"` + noms passés en propriétés `icon=`) ; ajouter une icône = régénérer.
- **Jetons** : uniquement dans `tailwind.config.js` (couleurs, `spacing` xs=4, sm=8, md=16, lg=24, xl=32 px, rayons, famille de police) ; aucune
  couleur inline dans une vue. Valeurs exactes et usage : `04_UI_UX_DESIGN_SYSTEM.md`.
- **Mode sombre** : présent dans `app.css` d'AgriERP (`body.dark-mode`) ; le poste de LogiALVIA n'en a pas dans les sources lues : ne PAS le créer
  (À DÉFINIR AVEC LE CLIENT si souhaité).

---

## 8. Sécurité de base

| Sujet | Règle | Source / état réel |
|---|---|---|
| Limiteurs | Connexion web : 5 tentatives / 15 min par identifiant+IP (`RateLimiter` dans `Livewire\Auth\Login`) ; API : `throttle:5,1` login, `30,1` écritures, `60,1`, `120,1,sync-pull` pour le tirage | `agrierp_laravel/routes/api.php`, `app/Livewire/Auth/Login.php` |
| Sessions | Pilote `database`, durée glissante 480 min, cookie `secure` en production, verrou d'inactivité côté navigateur + serveur (`SessionVerrouillee`, 10 échecs = déconnexion) | `app/Http/Middleware/SessionVerrouillee.php`, `resources/js/verrou.js` |
| CSRF | Actif (formulaires Livewire) ; `419` géré en français | `bootstrap/app.php`, `resources/js/app.js` |
| Mots de passe | `Password::defaults()` ; changement obligatoire à la première connexion ; l'administrateur réinitialise (aucun envoi par e-mail) ; jamais en base du poste (le poste garde un jeton et un PIN) | `ChangementMotDePasseObligatoire`, guide de portage §0 (contradiction 6) |
| Secrets | `.env` hors Git ; secrets de paramétrage (SMTP, MeCeF) chiffrés en base ; jamais dans les journaux | 42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md |
| CSP / en-têtes | **AgriERP n'en a AUCUN** (grep `Content-Security-Policy`/`X-Frame` dans `app/` et `public/.htaccess` : rien). Proposition (nouvelle, à valider) : `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: strict-origin-when-cross-origin`, et une CSP en mode « report-only » d'abord (Alpine/Livewire exigent `unsafe-eval` ou la build CSP d'Alpine ; tester avant d'imposer). | À DÉFINIR AVEC LE CLIENT / à tester |
| Uploads | Disque `public` via `storage:link` ; aucun fichier exécutable ; lien `/storage` NON bloqué par le `.htaccess` racine | `agrierp_laravel/htaccess` |
| Audit | Toute action sensible : `AuditLog::record('sale.created', 'ventes', …)` ; échecs de connexion comptés sur l'action technique `login.failed` (jamais sur sa traduction) | `app/Models/AuditLog.php` |
| Données | Aucun export de base, archive ni `.env` versionné ; la base se reconstruit par `php artisan migrate:fresh --seed` | `CLAUDE.md` racine |

## 9. Hébergement, déploiement, tâches planifiées

- **Cible présumée : hébergement mutualisé cPanel** (AgriERP : `RUNBOOK_DEPLOIEMENT_CPANEL.md`, `CHECKLIST_PRE_DEPLOIEMENT.md`,
  `docs/GUIDE_DEPLOIEMENT.md`). Pour LogiALVIA : À DÉFINIR AVEC LE CLIENT (hébergeur, sous-domaine, version de PHP, accès SSH/Composer, base MySQL).
- **Racine du document = `public/`.** `.htaccess` de `public/` : réécriture Laravel canonique + `AddType application/manifest+json .webmanifest`
  (Apache ne connaît pas l'extension : le manifeste serait servi en `text/plain` et ignoré SANS erreur) + `no-cache` sur `sw.js` + cache long
  immuable sur `build/`. `.htaccess` à la racine du projet = filet de sécurité UNIQUEMENT (interdit le listing, refuse les fichiers sensibles,
  réécrit vers `public/`) ; `storage` y est volontairement absent de la liste de blocage. `php artisan serve` ne lit jamais `.htaccess` :
  l'absence de ces deux fichiers a fait renvoyer 404 sur toutes les URL au premier déploiement d'AgriERP.
- **`.env.production.example`** (modèle : `agrierp_laravel/.env.production.example`) : `APP_ENV=production`, `APP_DEBUG=false`, `APP_TIMEZONE=Africa/Porto-Novo`
  (le Bénin : confirmer pour Natitingou, même fuseau), `APP_LOCALE=fr`, `APP_FALLBACK_LOCALE=fr`, `APP_FAKER_LOCALE=fr_FR`, `LOG_LEVEL=warning`,
  MySQL `utf8mb4_unicode_ci` avec utilisateur sans droits d'administration, `SESSION_DRIVER=database`, `SESSION_SECURE_COOKIE=true`,
  `QUEUE_CONNECTION=database`, `CACHE_STORE=database`, SMTP (`MAIL_MAILER=smtp`, port 587, TLS), `MECEF_ACTIF=false`. Toutes les valeurs sensibles
  en `<…>`, jamais une vraie.
- **Tâches planifiées** : UN seul cron cPanel, `* * * * * cd /home/UTILISATEUR/logialvia_web && php artisan schedule:run >> /dev/null 2>&1` ; toutes
  les tâches dans `routes/console.php` (`Schedule::command(...)` / `Schedule::job(...)->onOneServer()`). Modèles d'AgriERP : sauvegarde quotidienne
  02:00, rappel de prophylaxie 06:00, alertes de la cloche 06:05, ouverture de l'exercice le 1er janvier 00:00, purge/GC hebdomadaires, rappel de
  téléchargement de sauvegarde. Fuseau `Africa/Porto-Novo`. Ne JAMAIS créer un cron par tâche.
- **Files** : AgriERP n'a aucun `ShouldQueue` réel (`RUNBOOK_DEPLOIEMENT_CPANEL.md` §1). Ne pas déclarer de `queue:work` sans job réel. Si des jobs
  deviennent nécessaires (envoi massif d'e-mails), ajouter alors UN cron `queue:work --stop-when-empty` avec accord du client.
- **Cache** : `php artisan config:cache route:cache view:cache` au déploiement ; `storage:link` ; `npm run build` AVANT l'envoi (le serveur n'a pas Node) ;
  incrémenter `VERSION` de `public/sw.js` à chaque déploiement qui change un fichier mis en cache.
- **PWA étroite** (voir 40_PWA_HORS_LIGNE.md) : `sw.js` n'intercepte que `GET` ; aucune page authentifiée n'est mise en cache ; seulement des fichiers
  statiques ; `/livewire/`, `/api/`, `/login`, `/logout`, `/storage/` exclus. Elle ne rend PAS le web utilisable hors ligne : c'est le rôle du poste.

## 10. Sources d'information consultées (chemins vérifiés par `ls`)

`agrierp_laravel/composer.json`, `composer.lock`, `package.json`, `tailwind.config.js`, `vite.config.js`, `postcss.config.js`, `bootstrap/app.php`,
`resources/js/app.js`, `resources/views/layouts/app.blade.php`, `routes/api.php`, `routes/console.php`, `.env.example`, `.env.production.example`,
`RUNBOOK_DEPLOIEMENT_CPANEL.md`, `CLAUDE.md` ; `docs/prd/navigation-sans-rechargement.md`, `docs/GUIDE_DEPLOIEMENT.md`,
`docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md` ; `logialvia/docs/I1_Matrice_RBAC.md`, `logialvia/logialvia_app/pubspec.yaml`,
`logialvia/logialvia_app/assets/fonts/`.

## 11. À DÉFINIR AVEC LE CLIENT (questions précises)

1. **Hébergement** : cPanel mutualisé, VPS ou autre ? Sous-domaine (ex. `logialvia.<domaine>`) ? PHP 8.3 disponible ? Accès SSH pour `composer install` ? (Conséquence : mode de déploiement et cron.)
2. **Police** (Q-DS-1) : Roboto (identité du poste, par défaut) ou Inter (modèle AgriERP) ? Changer implique de changer aussi le poste.
3. **Plan comptable** : SYSCOHADA (mentionné par F6) confirmé ? Plan fourni par le client ou jeu par défaut ?
4. **Mode sombre** : voulu ? (le poste n'en a pas dans les sources lues.)
5. **PWA hors ligne** et **import xlsx** : le client les croit présents dans LogiAgriERP ; ils n'y sont pas (guide, E15). Les veut-il réellement pour LogiALVIA ?
6. **En-têtes de sécurité / CSP** : accord pour une CSP en mode rapport d'abord ?
