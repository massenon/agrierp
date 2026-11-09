# 03 — STANDARDS DE DÉVELOPPEMENT (web LogiALVIA : Laravel, Livewire, JavaScript, Tailwind)

## USAGE

| Rubrique | Contenu |
|---|---|
| **Quand l'utiliser** | (a) Au démarrage du chantier web, pour poser les outils de qualité (Pint, analyse statique, hooks) ; (b) à chaque ticket, comme liste de contrôle avant de dire « terminé » ; (c) en revue de code : chaque section est une grille d'audit. |
| **Ordre** | Après `01_MASTER_PROMPT.md` et `02_ARCHITECTURE_WEB_ET_STACK.md` ; avant les prompts de modules (`20_MODULES_*`). Complète `31_TESTING_QA.md` (stratégie de tests) et `04_UI_UX_DESIGN_SYSTEM.md` (charte visuelle). |
| **Entrées requises** | `logialvia_web/` créé (voir 02) ; `logialvia/docs/K1_Standards_Code.md` ; `agrierp_laravel/CLAUDE.md` ; `agrierp_laravel/tests/` pour les patrons de tests. |
| **Sorties attendues** | `logialvia_web/pint.json`, configuration d'analyse statique (si accord), `.editorconfig`, un test garde-fou par règle « invisible à l'exécution » (listé en fin de fichier), et un fichier `CONTRIBUTING`-équivalent dans `logialvia_web/CLAUDE.md`. |

---

## PROMPT (à copier)

````markdown
# RÔLE
Tu es le garant des standards de code du web LogiALVIA (Laravel 12 + Livewire 3). Tu appliques ET tu fais respecter
les règles ci-dessous. Tu lis `01_MASTER_PROMPT.md` d'abord. Tout est en français (code métier, tests, commits, messages).

# CONTEXTE
Les règles viennent de défauts RÉELS payés sur LogiAgriERP (`agrierp_laravel/CLAUDE.md`), de `logialvia/docs/K1_Standards_Code.md`
et de `logialvia/docs/A2_STRICT_AVOID.md`. Beaucoup de ces défauts sont INVISIBLES à l'exécution (l'écran s'affiche, mais n'est
pas celui qui a été validé) : pour chacun, un test garde-fou lit les sources.

# TÂCHES
1. Installe et configure l'outillage : `laravel/pint` avec `pint.json` (préréglage `laravel`), `.editorconfig`
   (UTF-8, LF, 4 espaces PHP/Blade, 2 espaces JS/CSS), et — SEULEMENT après accord du client — `larastan/larastan` (niveau
   à définir ; LogiAgriERP n'en a pas). Ajoute un script `composer qualite` = `pint --test` + tests Feature.
2. Écris les tests garde-fous listés à la section 10 ; chacun doit ÉCHOUER si on réintroduit le défaut (prouve-le en le réintroduisant
   une fois, puis en l'annulant).
3. Audite le code existant du web contre chaque section (1 à 9) ; produis la liste des écarts (fichier:ligne, règle, correctif).
4. Corrige les écarts de ton périmètre ; signale les autres.

# CONTRAINTES
- Conventions = celles des sections ci-dessous, sans variante locale.
- Aucune dépendance hors liste de `02_ARCHITECTURE_WEB_ET_STACK.md`.
- Jamais de commit/push sans demande. Messages de commit en français.

# CRITÈRES D'ACCEPTATION
- `./vendor/bin/pint --test` : zéro fichier à corriger.
- `php artisan test --testsuite=Feature` : vert, avec les gardes-fous de la section 10.
- `grep -rn "{!!" resources/views` : uniquement des cas justifiés par un commentaire (HTML généré par le serveur, jamais saisi).
- `grep -rLn "authorize(" app/Livewire` listé par composant mutant : aucun composant mutant sans `authorize()` (test `AutorisationsMethodesMutantesTest`
  d'LogiAgriERP comme modèle).

# INTERDITS
Reformater en masse du code non concerné ; renommer des classes hors ticket ; introduire des règles de style personnelles.
````

---

## 1. Nommage

Règle générale : **français** pour tout ce qui est métier (classes, méthodes, propriétés, variables, tests, vues), conformément au code
réel de logialvia (`CalculFicheJournaliere`, `enregistrerJour`) et à LogiAgriERP (`SaisieBandeAction`, `EffectifParCategorieService`).
Les mots techniques du framework restent en anglais (`mount`, `render`, `boot`). Ne pas mélanger deux langues dans une même couche
(constat de `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` §0, contradiction 1 : A1 §5 disait « anglais », le code est en français : suivre le code).

| Élément | Convention | Exemple |
|---|---|---|
| Classe | `PascalCase`, verbe métier pour Action, nom pour Service/Modèle | `SaisieBandeAction`, `EffectifParCategorieService`, `LotElevage` |
| Méthode / variable | `camelCase`, verbe métier | `enregistrerJour()`, `calculerEffectifJour()` (jamais `insertRow()`) |
| Composant Livewire | `app/Livewire/{Module}/{NomComposant}.php` ; vue `resources/views/livewire/{module}/{nom-composant}.blade.php` (kebab-case) | `Elevage/FicheEspece.php` / `elevage/fiche-espece.blade.php` |
| Table | pluriel `snake_case`, anglais ou français SELON le schéma partagé (figé dans `30_DATABASE_ENGINEERING.md`) ; JAMAIS deux conventions dans le même schéma | à trancher une fois (Q-DB) |
| Clé primaire | `id` UUID ; clé étrangère `{table_singulier}_id` | `lot_id` |
| Route | URL `kebab-case` française ; nom `module.page` | `/gestion-elevage` -> `elevage.gestion` |
| Permission | `view-{module}` / `manage-{module}` ; droits transverses `close-fiscal-year`, `manage-users`, `manage-modules`, `export-*` | `manage-elevage` |
| Action d'audit | `entite.evenement` en anglais technique minuscule, libellé français dans `ACTION_LABELS` | `sale.created` |
| Événement navigateur | `kebab-case` | `open-modal`, `close-modal`, `toast` |
| Marqueurs | `// ECART_DELIBERE:` (raison obligatoire), `// TODO(dette):` (description du correctif) | — |
| Règle métier | l'identifiant `BR-XXX-NNN` de `logialvia/docs/B6_Regles_Metier.md` au-dessus du code | `// BR-ELV-001` |

Un nom décrit l'action métier, pas l'implémentation : `enregistrerVente()`, pas `insertRowVentes()` (A2 §11).

## 2. Laravel (PHP 8.3)

1. **Couches** : voir 02, section 1. Un composant Livewire orchestre ; un calcul vit dans un Service ; un effet de bord multi-tables vit dans une Action.
   Un modèle n'appelle jamais un service.
2. **Routes de pages** : `Route::get('/x', Composant::class)->name('module.page')->middleware(['auth', 'can:view-module']);` Jamais la syntaxe
   tableau-contrôleur pour une page Livewire. Les 5 écrans `auth`-seuls (tableau de bord, profil, aide, contact, notifications) + routes de verrouillage
   sont une LISTE BLANCHE testée.
3. **Transactions** : toute opération qui écrit plusieurs tables s'exécute dans `DB::transaction()` ; une écriture refusée par un point de passage
   (ex. écriture comptable déséquilibrée) annule tout. L'appel à la passerelle MeCeF se fait APRÈS la transaction.
4. **Verrous** : verrouiller les lignes `products` à modifier par id croissant (`OrdreDesVerrous::stock`) avant toute fiche ; relire sous `lockForUpdate()`
   un compteur que deux requêtes peuvent incrémenter (sinon deux envois lisent 5 et écrivent 6 tous les deux).
5. **Montants** : entiers en FCFA (pas de décimales), jamais de `float` pour de l'argent ; contrôle « total = somme des lignes » avant écriture.
6. **Dates** : fuseau `Africa/Porto-Novo` ; une date de pièce est une date calendaire (pas un instant UTC) ; l'exercice se résout par COUVERTURE de date,
   pas par « le dernier ouvert ». Le poste envoie `since` en UTC : le ramener à l'heure du serveur avant comparaison.
7. **Suppression logique** : `is_active` / `status` ; aucun `delete()` sur donnée comptable/zootechnique ; un nouveau chemin d'archivage appelle
   `AuditLog::record(..., $modele)` ET ajoute sa clé à `AuditLog::ACTIONS_ARCHIVAGE` (sinon la Corbeille ne sait pas « qui a archivé »).
8. **Migrations** : jamais éditer une migration déjà déployée (en créer une nouvelle) ; UUID ; index sur toute clé étrangère et colonne de recherche ;
   `down()` réellement inverse. Lire en entier toute migration tierce avant de la publier (Sanctum, Spatie : interdit de publier).
9. **Eloquent** : `with()` pour éviter le N+1 ; pas de requête dans une boucle de vue ; pas de `DB::raw` avec valeur utilisateur ; casts `encrypted`
   pour les secrets. Pas d'usage de `#[Computed]` dans LogiAgriERP : ne pas le présumer, et ne pas l'introduire sans décision d'équipe.
10. **Erreurs** : messages d'erreur utilisateur en français, jamais un `SQLSTATE` affiché (cas réel : le POS web montrait `SQLSTATE 1062` et perdait la vente).
    Une collision d'unicité se relit sous verrou au lieu d'échouer.
11. **Configuration** : jamais `env()` hors `config/*.php` ; réglages éditables par le client en base (jamais en dur : « Poste settings — never hard-code
    them again »).
12. **Journaux** : jamais de mot de passe, de jeton, de PIN, ni de secret MeCeF dans un log ou un `AuditLog`.

## 3. Livewire 3

1. **Pleine page** : `#[Layout('layouts.app')]` ; la vue du composant a UNE seule balise racine `<div>` (fragment, jamais un document HTML).
2. **État d'onglet** : `#[Url] public string $tab = 'defaut';` (lien partageable) ; composant `<x-tab-page>`.
3. **Hubs** = composants imbriqués (`<livewire:module.composant />`), jamais d'iframe ; un écran absent = `<x-module-pending>`.
4. **Autorisation** : `$this->authorize('manage-…');` **PREMIÈRE ligne de TOUTE méthode publique qui écrit** (LogiAgriERP : 166 sites). Aussi dans `mount()` si la
   page est sensible. Une propriété publique est modifiable par le client : jamais de `public $prix` lu sans revalidation ; verrouiller (`#[Locked]`) les
   identifiants qui ne doivent pas changer côté navigateur.
5. **Validation** : règles dans `rules()` ou `#[Validate]`, messages dans `lang/fr/validation.php` ; `$this->validate()` avant toute écriture ; messages
   « sous le champ concerné » (`@error`), jamais d'envoi silencieux d'un formulaire invalide avec des valeurs par défaut.
6. **Modales événementielles** : `$this->dispatch('open-modal', name: 'modal-creer-lot')`, reçue par `x-on:open-modal.window` dans `components/modal.blade.php` ; fermeture
   `dispatch('close-modal', name: …)`. `@if($showModal)` est INTERDIT (la modale détruite perd son état et sa transition). `teleport` pour une modale posée dans un
   conteneur qui crée son empilement (en-tête collant z-30 sous la barre latérale z-50).
7. **Toasts** : `$this->dispatch('toast', message: '…', type: 'success'|'warning'|'error');` capté par `components/toast-container.blade.php`. Pas de relais
   `Livewire.on('toast')` en plus (il doublait les messages : supprimé d'LogiAgriERP le 26/10/2026).
8. **Rafraîchissement** : événements Livewire entre composants (`$this->dispatch('lot-modifie')`, `#[On('lot-modifie')]`) ; `wire:poll` seulement avec raison écrite (02, §4).
9. **Performance** : pas de collection complète en propriété publique (elle est sérialisée à chaque requête) : propriété = identifiants/filtres, données lues dans `render()` ;
   pagination `WithPagination` avec UN nom de page par liste (`<x-pagination>`) ; `lazy` pour les blocs lourds ; `wire:key` stable dans toute boucle (sinon perte de focus).
10. **Zéro logique dans Blade** : une vue formate et boucle ; aucun calcul métier, aucune requête, aucune condition d'autorisation métier (les `@can` ne servent qu'au confort
    d'affichage). Les directives personnalisées (ex. `@lectureSeule`) vivent dans `AppServiceProvider`.
11. **Composants partagés d'abord** (`resources/views/components/`) : `datatable`, `modal`, `modal-confirm-delete`, `kpi-card`, `kpi-accordion`, `nav-card`, `tab-page`,
    `sidebar-link`, `pagination`, `module-pending`, `flash-toast`, `toast-container` (modèles : `agrierp_laravel/resources/views/components/`). Écrire une variante
    avant d'avoir cherché celle qui existe est un défaut.
12. **Cas d'erreur** : toute action qui échoue produit un toast d'erreur ; aucune exception brute à l'écran ; états vides informatifs avec bouton de création si pertinent.
13. **Retour visuel obligatoire** : toute sauvegarde réussie = toast de succès ; toute action destructive = modale de confirmation (G2 §1 et §2).

## 4. Blade, accessibilité de balisage, classes Tailwind

1. **Classes statiques**. Jamais `"border-l-{$color}"` : le scanner JIT de Tailwind ne voit que des chaînes littérales complètes. Utiliser un tableau de correspondance
   de chaînes COMPLÈTES (modèles : `components/kpi-card.blade.php`, `components/modal.blade.php`, `components/toast-container.blade.php`). Une classe dynamique disparaît du
   build sans aucune erreur.
2. **Jetons uniquement** (voir 04) : couleurs, espacements (`p-md`, `gap-sm`…), rayons, ombres ; aucune valeur hexadécimale ni `style="color:…"` dans une vue ; un nouveau jeton
   s'ajoute à `tailwind.config.js` après accord, jamais en local.
3. **`data-label` sur CHAQUE `<td>`** d'un `<x-datatable>` : sans lui, la vue mobile en cartes perd ses libellés (test garde-fou à écrire).
4. **Tailles** : `text-xs` = 13,6 px (surcharge `font-size: 0.85rem !important` dans `app.css` : la reprendre à l'identique ; ne JAMAIS la « corriger » en 12 px). Tailles arbitraires
   (`text-[10px]`, `text-[12px]`) autorisées UNIQUEMENT pour les cas répertoriés dans 04 (libellés de KPI, en-têtes de tableau).
5. **Échappement** : `{{ }}` partout ; `{!! !!}` jamais sur une donnée saisie.
6. **Accessibilité de base** (détail en 04, §10) : tout bouton icône-seule a `title` ET `aria-label` ; une modale porte `role="dialog"` `aria-modal="true"` ; un onglet
   expose `aria-selected` ; le focus clavier reste visible (jamais `outline-none` sans alternative) ; un `<label>` par champ.
7. **Un seul chemin pour une même action** : si deux écrans offrent « Ajouter un produit », ils ouvrent la MÊME modale / appellent la MÊME Action (G2 §9).

## 5. JavaScript (Alpine via Livewire, modules ES)

1. `resources/js/app.js` n'importe PAS Alpine et n'appelle JAMAIS `Alpine.start()`. Les plugins se branchent sur `alpine:init`. Livewire 3 embarque et démarre son Alpine ;
   une 2e instance casse `$wire` (« Detected multiple instances of Alpine running »). Test garde-fou : lecture de `app.js` (modèle : `agrierp_laravel/tests/Feature/PwaEtPolicesLocalesTest.php`
   pour le style de garde, et un équivalent à écrire pour Alpine).
2. Interactions simples en `x-data`/`x-show`/`x-on:click` DANS le composant Blade ; pas de fonctions globales (`window.openSidebar()`) ; pas de jQuery.
3. Logique pure (minuteries, décisions) dans des modules `.js` SANS dépendance DOM (`verrou-logique.js`), testés par `node --test` (`tests/Js/*.test.mjs`) ; la partie DOM les importe.
4. Écouteurs sur `window`/`document` posés UNE fois (module chargé une fois) ; ce qu'une page ajoute se détache à `livewire:navigate` / `Alpine.cleanup` (sinon fuite à chaque navigation).
5. Aucun `<script>` inline dans les vues de composants (constat d'LogiAgriERP : aucun) ; le seul script d'en-tête est marqué `data-navigate-once`.
6. Stockage navigateur : `localStorage` seulement pour des préférences d'interface (barre latérale repliée) ; jamais de donnée métier ni de jeton.
7. Réseau : aucune requête `fetch` vers un domaine externe ; aucune ressource externe (voir 02, §7).
8. Les tests Feature `Livewire::test()` n'exécutent AUCUN JavaScript : tout comportement qui vit dans le navigateur (Alpine, z-index, `wire:navigate`, `@persist`, modales) exige un test Dusk ou un essai réel.

## 6. Tailwind / CSS

1. Tailwind 3.4 par PostCSS + Vite ; `content` couvre `resources/views/**/*.blade.php`, `app/Livewire/**/*.php`, `app/View/Components/**/*.php`, la pagination du framework, `storage/framework/views/*.php`.
2. `resources/css/app.css` : `@tailwind base/components/utilities`, `@font-face` locales, classes de composants partagées (`.kpi-card`, `table.rtable`, `.submenu`, `.toast-in`, `.sidebar-gradient`), `@media print`.
   Toute classe `app.css` déclarée APRÈS `@tailwind utilities` pour l'emporter à spécificité égale (cas `.kpi-card` / `border`).
3. Une classe de composant existe en UN endroit (`app.css` ou composant Blade) ; la recopier à la main finit par diverger (cartes KPI : 13 copies dont 2 divergentes au poste).
4. Responsive : points de rupture Tailwind par défaut (640/768/1024/1280) ; table `rtable` à 640 px EXACTEMENT ; barre latérale à `lg` (1024). Détail et réconciliation : 04, §6.
5. Impression : `@media print` masque barre latérale, en-tête, barre mobile et `.no-print`.

## 7. Validation et messages

- Messages français centralisés : `lang/fr/validation.php`, `lang/fr/auth.php`, `lang/fr/passwords.php`, `lang/fr/pagination.php`, `lang/fr.json` ; `APP_LOCALE=fr`, `APP_FALLBACK_LOCALE=fr`.
- Erreurs HTTP en français : vues `resources/views/errors/` (401, 403, 404, 419, 429, 500, 503, `4xx`, `5xx`, `layout`) ; réponses JSON de l'API traduites par `MessagesErreurFr::traduireJson`.
- Boîte « page expirée » de Livewire (anglaise, codée en dur) remplacée par un hook (`Livewire.hook('request')`) : voir `agrierp_laravel/resources/js/app.js`.
- Un champ numérique vide n'est pas `0` : `ChampNumeriqueVide` normalise (« — » ou refus), jamais une valeur par défaut silencieuse.
- Montant : entier FCFA ; format d'affichage `fr-FR` (séparateur de milliers espace insécable) ; jamais `$` ni `€`.
- Règles dépendant de l'exercice : une date dans un exercice CLÔTURÉ est refusée avec le MOTIF (même libellé au web et au poste).

## 8. Sécurité (checklist de revue)

| Contrôle | Règle |
|---|---|
| RBAC deux niveaux | route `auth`+`can:` ET `authorize()` en 1re ligne ; menu masqué = cosmétique ; tests d'accès par rôle (autorisé/refusé) |
| Pas de logique dans Blade | un calcul ou une requête en vue = défaut |
| Mots de passe | `Password::defaults()` ; hachage serveur (Bcrypt par défaut) ; jamais affiché, loggué ni envoyé ; réinitialisation par l'administrateur seulement ; changement obligatoire au 1er accès |
| Secrets | `.env` hors Git ; cast `encrypted` pour SMTP/MeCeF en base ; jamais dans la doc ni les tests |
| Audit | `AuditLog::record($action, $module, $userId = null, $entite = null)` pour toute action sensible (connexion, droits, clôture, archivage, restauration, réinitialisation) ; clé technique stable, libellé français dans `ACTION_LABELS` |
| Limiteurs | connexion et déverrouillage : `RateLimiter` ; API : `throttle:` (voir 02, §8) |
| Données sensibles | aucune donnée client/salariale dans les journaux ; export soumis à un droit `export-*` |
| Dépendances | `composer audit` et `npm audit` avant chaque déploiement ; aucune dépendance hors liste |
| Fichiers | jamais d'exécution d'un fichier téléversé ; type et taille validés ; stockage hors dépôt |
| Synchro | jetons Sanctum par poste, révocables ; un 401 renvoie le poste à l'appairage ; jamais de mot de passe en base du poste |

## 9. Notifications : toasts et cloche

- **Toast** (feedback immédiat) : `dispatch('toast', message:, type:)`, 3 types `success` / `warning` / `error`, disparition à 3500 ms, empilés en haut à droite (z-[200]).
  Les toasts « flash » posés en session sont lus APRÈS la navigation (`livewire:navigated`). Le conteneur est `@persist`.
- **Cloche** (notifications persistées) : composant `livewire/shared/notification-bell` ; table `notifications` ; alertes générées par `AlertesElevageService` via une tâche planifiée
  (stock sous seuil, mortalité anormale, soins planifiés à venir/en retard, échecs de reproduction : règles et seuils à reprendre de `15_REGLES_METIER.md`, pas d'LogiAgriERP) ;
  compteur de non lues ; lien « Voir tout » vers `/notifications` (`wire:navigate`). Détail : `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`.
- **Rappels du jour** : fenêtre ouverte au plus une fois par jour et par session de navigateur (`sessionStorage`), jamais à chaque navigation.
- Aucune notification n'est « décorative » : un toast de succès n'est émis qu'APRÈS l'écriture réelle.

## 10. Git, tests, qualité, revue

**Git**. Messages de commit en français, à l'impératif, une ligne de résumé (≤ 72 caractères) puis un corps qui dit POURQUOI ; un sujet par commit ; référence du ticket en tête
(`EL-3 : …`). **Une seule branche de travail** à la fois ; **pas de PR sans demande** ; pas de `push` sans demande ; jamais de `--force`, `reset --hard` ni `--no-verify`. Rien de
secret ni de volumineux versionné : aucun `*.sql`, `*.zip`, `.env` (l'export `database/agrierp_db.sql` d'LogiAgriERP contenait des hash de mots de passe : retiré de l'historique le 17/10/2026).
Attribution des commits : celle que l'environnement impose (voir le rappel de session).

**Tests** (détail : `31_TESTING_QA.md`).
- `php artisan test --testsuite=Feature` (JAMAIS `php artisan test` seul si `phpunit.xml` déclare une suite `Unit` vide) ; `RefreshDatabase`, sqlite `:memory:`.
- Un test Feature Livewire (`Livewire::test(Composant::class)`) par action : autorisation (refusée au rôle sans droit), validation, écriture réelle en base, toast, événement.
- **Tests de parité** : un calcul porté du poste (ou inversement) est confronté au VRAI code de l'autre côté (modèle : `agrierp_flutter/test/php_laravel.dart` et les `*_parite_php_test.dart`) ;
  sans PHP/dépôt, ils se SAUTENT avec leur raison, jamais verts à vide.
- **Chiffres** : jamais vérifiés à la lecture ; un recalcul indépendant (ex. `CoherenceFormulesElevageTest`, `BalanceGeneraleTest`) ; cas limites historiques (stock 0, mortalité = effectif, vente > stock).
- **Dusk** : parcours navigateur (connexion, POS, déconnexion, barre latérale par rôle, responsive à 3 largeurs, console sans erreur) ; base dédiée `.env.dusk.local` JAMAIS pointée sur la base de développement.
- **JS pur** : `node --test tests/Js`.
- **Gardes-fous de sources (lisent le code)** à écrire dès le départ : (1) pas de CDN/Google Fonts ; (2) pas d'`Alpine.start()` ; (3) toute `<td>` d'un datatable a `data-label` ; (4) toute carte KPI utilise
  `<x-kpi-card>`/`.kpi-card` ; (5) aucune classe Tailwind dynamique ; (6) toute méthode mutante a `authorize(` ; (7) toute route métier a `can:` ; (8) aucune couleur hexadécimale hors `tailwind.config.js` et `app.css` ;
  (9) toute migration métier a une clé UUID ; (10) tout chemin d'archivage appelle `AuditLog::record` et figure dans `ACTIONS_ARCHIVAGE` ; (11) libellés de chaque écran présents (`fidelite_libelles`, voir 04, §9).

**Qualité**. Pint à zéro avant chaque livraison ; analyse statique **non installée dans LogiAgriERP** (aucun `phpstan`/`larastan`) : la proposer au client (nouvelle dépendance) plutôt que de la supposer ;
pas de `dd()`, `dump()`, `var_dump()`, `console.log()`, `print` laissés ; pas de code mort ; fichier ≤ ~300 lignes recommandées par composant (au-delà : extraire un Service ou un sous-composant) ;
duplication de plus de 5 lignes entre deux fichiers : extraire (A2 §12). La dette se marque `// TODO(dette):` avec le correctif attendu ; un `grep` périodique sur `TODO(dette)` donne la dette réelle.

**Revue**. Avant de dire « terminé » : (1) cases du MASTER PROMPT cochées ; (2) `git diff --stat` ne contient que le périmètre du ticket ; (3) aucun secret ; (4) chaque règle métier porte son `BR-…` ; (5) rapport au format du MASTER PROMPT.
Le relecteur vérifie en priorité les défauts invisibles : autorisation manquante, point de passage contourné, classe Tailwind dynamique, 2e Alpine, `0` à la place de « — », libellé anglais, `@if` de modale.

## 11. Pièges déjà payés (à ne pas repayer) — références

| Piège | Source |
|---|---|
| Alpine chargé deux fois | `agrierp_laravel/resources/js/app.js` (ticket 14.19) |
| 41 routes sur 42 protégées par `auth` seul | `agrierp_laravel/CLAUDE.md`, « RBAC » (ticket 13.1) |
| Classes Tailwind dynamiques perdues | `agrierp_laravel/CLAUDE.md`, « Livewire / Blade conventions » |
| Google Fonts bloquant le chargement quand le lien tombe | `agrierp_laravel/CLAUDE.md`, « Fonts are local » |
| `.htaccess` absent : 404 sur toutes les URL en production | `agrierp_laravel/CLAUDE.md`, « .htaccess » |
| `.webmanifest` servi en `text/plain` | idem |
| Police PDF sans Unicode : « — » imprimé en carré barré | `agrierp_flutter/CLAUDE.md`, « Flutter-specific traps » (pour DomPDF, charger une police Unicode et tester les glyphes) |
| Toast en double (relais + natif) | `agrierp_laravel/resources/js/app.js` (commentaire du 26/10/2026) |
| `0` pour une valeur inconnue | `agrierp_flutter/CLAUDE.md`, « Missing data is '—', never 0 » |
| Tests Feature aveugles au JavaScript | `agrierp_laravel/resources/js/app.js` (ticket 14.18) |
| Garde-fou qui passait sur des COMMENTAIRES | `agrierp_flutter/CLAUDE.md`, « fidelite_libelles… `chainesDe` » |
| `LIKE` sensible aux accents côté poste (œ) | `agrierp_flutter/CLAUDE.md` (comparer sur un libellé normalisé) |
| Drift : `&` vs `.and()` selon la version | guide de portage §0, contradiction 8 |

## 12. À DÉFINIR AVEC LE CLIENT

1. **Analyse statique** (Larastan) : accord pour l'ajouter (nouvelle dépendance de développement) et niveau visé ?
2. **Langue des noms de tables/colonnes** du schéma partagé : français (comme les entités Dart de logialvia) ou anglais (comme LogiAgriERP) ? À figer UNE fois dans `30_DATABASE_ENGINEERING.md` avant la première migration.
3. **Format des messages de commit** : le client veut-il un préfixe de ticket (`EL-3 :`) ? (Proposition, non issue des sources.)
