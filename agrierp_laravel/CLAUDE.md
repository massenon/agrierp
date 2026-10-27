# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

The **real Laravel 12 application** of AgriERP — Ferme École OLOUWACHEGOUN (Ikpinlè, Benin), PAEB / Cabinet FAGUEZ SARL. Laravel 12.65 + Livewire 3 + Alpine + Tailwind CLI, PHP 8.3, MySQL, served under Laragon at `C:\laragon\www\agrierp`.

It is one of **three** codebases in this project:

| Codebase | Location | Role |
|---|---|---|
| This app | `C:\laragon\www\agrierp` | Laravel 12 web ERP |
| Prototype + docs | `C:\Projects\agrierp_laravel` | 97-screen HTML prototype (`prototype_html/`) + 60-file knowledge base (`docs/`) |
| Flutter Desktop | separate | Offline-first POS/élevage client (Drift/SQLite), talks to `/api/sync/*` |

The app was originally delivered as an **overlay** on a hand-assembled Laravel skeleton, not a real `laravel new` install. Several "always present" framework files were in fact missing and had to be created later (`tests/TestCase.php`, `app/Http/Controllers/Controller.php`, `routes/api.php`, `routes/console.php`, `AppServiceProvider`). Assume nothing is present because Laravel normally ships it — check.

**All prose, UI labels, comments, and docs are in French.** Keep it that way.

## Source-of-truth hierarchy — never invert it

1. **The HTML prototype** (`C:\Projects\agrierp_laravel\prototype_html\`) wins on anything visual, structural, or behavioural. Read the source file in full before converting a screen — never reconstruct from memory.
2. **The knowledge-base docs** (`docs/` in the prototype repo, plus the root-level `*.md` here) supply business logic, schema, and calculation rules not visible in the HTML.
3. **Existing code is not presumed correct** — check it against 1 and 2 before reusing it as reference.

If a rule is in neither the prototype nor a doc, say so explicitly rather than inventing it.

## Commands

```powershell
composer install
npm install
copy .env.example .env
php artisan key:generate
php artisan migrate:fresh --seed     # DB agrierp_db, utf8mb4_unicode_ci
npm run build                        # or: npm run dev
php artisan serve --port=8002        # APP_URL in .env is 127.0.0.1:8002
```

### Tests

```powershell
php artisan test --testsuite=Feature            # 73 files, 514 tests — the working entry point
php artisan test --testsuite=Feature --filter=EncaissementVenteTest
php artisan dusk                                # 9 browser journeys
php artisan dusk --filter=PosSaleTest
```

- **`php artisan test` with no argument FAILS**: `phpunit.xml` declares a `tests/Unit` suite that does not exist (no unit tests were ever written). Always pass `--testsuite=Feature`.
- Feature tests use `RefreshDatabase` against **sqlite `:memory:`** (set in `phpunit.xml`) — they never touch MySQL.
- Dusk uses `DatabaseMigrations` (i.e. `migrate:fresh`) and loads **`.env.dusk.local`** (not versioned — copy it from `.env.dusk.example` and fill in `APP_KEY` and `DB_PASSWORD`), which points at `agrierp_dusk`. Never repoint that file at `agrierp_db` — it would destroy the dev database. Dusk needs the app actually served on `127.0.0.1:8002` and Chrome installed.
- Feature tests run through `Livewire::test()`, i.e. **server-side only, zero JavaScript**. A whole class of bugs (double Alpine instance, `$wire is not defined`, toast overlays intercepting clicks) is invisible to them and only Dusk catches it. Any change touching Alpine, z-index, or overlay stacking needs a Dusk run.

### Verification discipline

`php -l` validates raw PHP but **not** Blade directives — a `.blade.php` that lints clean proves nothing about compilation. Use `php artisan route:list` to confirm named routes resolve. Numeric output (accounting balances, stock totals, headcounts) is **never** verified by reading: write an independent recomputation and compare against what the screen displays.

## Architecture

### Layering (this is NOT hexagonal/Clean Architecture)

Flat and pragmatic — `app/Actions/`, `app/Services/`, `app/Models/`, `app/Livewire/{Module}/`. There is **no** `app/Domain`, `app/Application`, or `app/Infrastructure`; don't create them.

- **`app/Livewire/{Module}/`** (97 components) orchestrates: validation, page state, `authorize()`, dispatching events. Grouped by business module (Elevage, Ventes, Achats, Stocks, Comptabilite, RH, Facturation, Rapports, Parametres, Administration, …).
- **`app/Actions/`** (18) — single-purpose side effects, mostly "this business event must also produce its accounting entry / stock movement / fiche update". Called from Livewire components *and* from `SyncController`.
- **`app/Services/`** (17) — multi-step computation and reporting (financial reports, payroll, aged balance, VAT, bank reconciliation, growth analysis, PDF, backup, trash).
- **`app/Models/`** (60) — Eloquent only.

### Single points of passage (the load-bearing rule of this codebase)

Each shared mechanism has exactly one entry point. Bypassing one silently breaks an invariant that only surfaces months later in a report.

| Mechanism | Sole entry point | Invariant |
|---|---|---|
| Any accounting entry | `AccountingEntryService::record()` / `recordManual()` | `SUM(debit) == SUM(credit)` to the centime, checked **before** any write; entry date must fall inside an **open** `fiscal_year` (resolved by date coverage, not "latest open"); manual 2-line entries additionally require debit account ≠ credit account |
| Any change to `products.stock_qty` | `AdjustStockAction::execute()` | The `stock_movements` row is written in the same call — never one without the other |
| MeCeF invoicing | `MecefGatewayInterface` (bound to `FakeMecefGateway` in `AppServiceProvider`) | Swapping in a real gateway is a one-line binding change |
| Password rules | `Password::defaults()` in `AppServiceProvider::boot()` | `uncompromised()` deliberately absent — it calls a remote API and would block account creation when the farm's link drops |

Every financial operation (sale, purchase, expense, payroll, credit note, depreciation, asset acquisition, settlement, treasury transfer, inventory variance) auto-generates its SYSCOHADA entry via a dedicated Action. Reports read from `accounting_entries` / `accounting_entry_lines`, never recomputed from disjoint business tables.

Treasury is kept in **two books** — the `treasury_accounts` table (dashboard KPI) and class-5 ledger accounts (Bilan, bank reconciliation). Anything that moves cash must move both, or they diverge from the first transaction.

### Data model conventions

- **Every primary key is a UUID** (`$table->uuid('id')->primary()`), including `users.id`. This is deliberate: offline Flutter clients write concurrently, and auto-increment integers would collide. Consequence — the Spatie Permission migration uses `uuidMorphs('model')` and `config/permission.php` sets `column_names.model_morph_key = model_id`. **Never** run `vendor:publish` for Sanctum or Spatie migrations: it overwrites `uuidMorphs()` with the default `morphs()`, silently incompatible with UUID `users.id`. Read any third-party migration in full before publishing it.
- **Deletion is logical archival only** (`is_active = false` / a `status` enum). Physical `DELETE` on accounting or zootechnical records is prohibited. `CorbeilleService` lists and restores archived rows across 16 screens — but **accounting entries are excluded from it by design**: an entry is reversed (contre-passée), never restored, or the Bilan stops balancing.
- **`sale_lines.manual_total_amount` is the source of truth for a line amount.** `unit_price` is derived for display (`manual_total_amount / qty`), never the reverse. Sales go through an editable global-amount confirmation, not an automatic price × quantity.

### RBAC — exactly 4 roles, enforced at two levels

`admin`, `comptable`, `caissier`, `animalier` (`RolesAndPermissionsSeeder`). Permissions are `view-{module}` / `manage-{module}` plus `close-fiscal-year`, `manage-users`, `manage-modules`, `export-*`, `archive-elevage`.

Both levels are required on every business screen:

```php
Route::get('/gestion-elevage', \App\Livewire\Elevage\GestionElevage::class)
    ->name('elevage.gestion')
    ->middleware(['auth', 'can:view-elevage']);
```

…and `$this->authorize('manage-elevage');` as the **first line of every mutating method** (166 call sites today). Menu hiding via `@hasanyrole` in `layouts/app.blade.php` is cosmetic, not authorization — ticket 13.1 found 41 of 42 routes protected by `auth` alone, reachable by direct URL from any logged-in account.

Only 5 screens are legitimately `auth`-only: `/dashboard`, `/mon-profil`, `/aide-a-propos`, `/contact-editeur`, `/notifications` (plus, since sprint VW, the three session-lock routes `POST /verrouiller`, `POST /deverrouiller`, `GET /verrouillage`). There is no `Gate::before` admin bypass — a permission that isn't seeded is inaccessible to everyone, including admin.

### Livewire / Blade conventions

- **Full-page routes**: `Route::get('/x', Component::class)` — never controller array syntax. Layout via `#[Layout('layouts.app')]`; the component view is a single root `<div>` fragment, never a full HTML document. Tab state uses `#[Url] public string $tab`.
- **Hubs are nested Livewire components, never iframes.** The prototype loads hub tabs as iframes; the Laravel conversion composes `<livewire:ventes.pos-interface>` inside the hub. Screens not yet built show `<x-module-pending>`, never a placeholder route.
- **Modals are event-driven**: `$this->dispatch('open-modal', name: 'modal-create-fournisseur')`, caught by `x-on:open-modal.window` in `components/modal.blade.php`. A `@if($showModal)` wrapper is forbidden.
- **Toasts**: `$this->dispatch('toast', message: '…', type: 'success'|'warning'|'error')` → `components/toast-container.blade.php`.
- **Reuse the shared components in `resources/views/components/`** before writing a variant: `datatable`, `modal`, `modal-confirm-delete`, `modal-confirm-hard-delete`, `modal-confirm-permanent-delete`, `kpi-card`, `kpi-accordion`, `nav-card`, `tab-page`, `sidebar-link`, `cycle-reminder`, `vente-piece-modal`, `module-pending`, `flash-toast`, `pagination` (ticket EX7: the shared footer of a list paginated inside the displayed fiscal year — `App\Support\ExerciceChoisi::PAR_PAGE`, `WithPagination` with one page name per list; the poste copy is `PaginationAgri`). Note: **there is no `#[Computed]` usage anywhere** — don't assume it exists. The fiscal year being DISPLAYED is read only through `App\Support\ExerciceChoisi` (EX7); `FiscalYear::current()` serves writing/deciding, never display. A data-entry button gets `@lectureSeule` right after `<button` (greyed with its reason when the displayed year is closed — comfort only, the server refusal stays the guarantee). The read-only banner of a closed year is ONE component, `x-bandeau-lecture-seule` (EX7 + EX8 merge): the top-of-content banner of the displayed year (`Shared\BandeauExercice`) and the banner of a livestock sheet whose CHOSEN DAY lies in a closed year (`Concerns\AvecMoisDeFiche`) — same text (`ExerciceChoisi::bandeauDe`); the poste copy is `BandeauLectureSeule`. The Bilan / États financiers N / N-1 columns follow the displayed year: their `exercice` parameter is a choice through `ExerciceChoisi::choisir()`, and the cut-off date has one rule, `ExerciceChoisi::arreteDe()`.
- **`x-datatable`** owns live search (`wire:model.live.debounce.300ms`) in one place — never re-implement per screen. Responsive breakpoint is **640px exactly** (`table.rtable` in `resources/css/app.css`), and every `<td>` requires `data-label="…"` or the mobile card view loses its labels.
- **Tailwind classes must be static strings.** Build lookup arrays (see `modal.blade.php`, `toast-container.blade.php`) — dynamically concatenated class names are not seen by the Tailwind CLI scanner and silently vanish from the build.
- **Alpine is started by Livewire 3.** `resources/js/app.js` must not `import Alpine` / `Alpine.start()` — a second instance breaks `$wire` everywhere in the browser.
- **Colour tokens live only in `tailwind.config.js`**, mirrored from the prototype's `assets/js/tailwind-config.js`. `brand-maize` is an explicit alias of `accent-yellow` (`#FFD55F`) because the prototype's `sidebar.js` references a class its own config never defined. Any new token found in a prototype file is added here, never inlined in a Blade view.

### Offline sync (Flutter ↔ Laravel)

`routes/api.php`: `POST /api/auth/login` (throttled 5/min), then Sanctum-guarded `/api/auth/logout`, `/api/auth/me`, `GET /api/sync/pull?since=…`, `POST /api/sync/push`. Depuis le ticket S-T4, le tirage est **paginé** quand le poste envoie `page` (`page=1`, puis `curseur_page=<jeton>`) : tables entières à la page 1, tables d'historique découpées par pièce (jamais une ligne sans sa pièce) au curseur (`updated_at`, `id`), `server_time` à la dernière page seulement, et seules les tables que le compte lit (`SyncController::PERMISSIONS_DE_TIRAGE`, croisée avec les écrans du poste par `agrierp_flutter/test/perimetre_tirage_test.dart`). Sans `page` : la réponse complète et non filtrée d'avant (postes anciens). S-T12 : `since` (envoyé en UTC par le poste) est ramené à l'heure du serveur avant toute comparaison (`curseurDuPoste`) — lu comme une heure murale, il reculait d'une heure et chaque tirage incrémental resservait l'heure écoulée. U13 : `expenses` (de base, archivées comprises, `is_active`) et `payslips` (`view-rapports` seulement, et seulement les colonnes de « Recettes et Dépenses » : nom, net, instant du règlement — protection S3) descendent au tirage paginé ; une fiche Lapins / Porcs acceptée d'un poste lève l'alerte d'autonomie alimentaire comme `saveDay()` (`AlerteAutonomieFicheService`, après la transaction de l'envoi). Conflict resolution in `SyncController` is **differentiated by data nature**, never a blanket last-writer-wins:

| Data | Rule |
|---|---|
| Reference data (products, categories, ration standards) | Server always wins — pull only; pushes silently ignored but logged |
| Daily élevage sheets | Last writer wins (upsert by id) on the breeder columns. S-T9: the `vente` column of a sheet the server already knows is **never** taken from the device — each sale increments it once (15.30 exemption only for a sheet created by the same request, from which a rejected sale is removed); a device sheet on a (lot, day) already held under another id is **merged** (`merged`) when one of the two carries only the sale or both carry the same entry, refused otherwise |
| POS sales | Never merged — each offline sale is inserted as an independent transaction |
| The whole push | S-T9: one DB transaction (`traiterEnvoi`), retried 3 times on a deadlock — a request that fails writes nothing (MariaDB deadlocks between two counters used to leave the sheet written without its sales). S-T12 : a counter incremented by a sale (`vente` of the sheet) is re-read `lockForUpdate()` first — two simultaneous pushes otherwise both read 5 and wrote 6 ; the (lot, day) sheet a sale creates may be created at the same instant by another push : the unique violation re-reads it under lock (`ficheDuJour`) instead of failing (the web POS used to show `SQLSTATE 1062` and lose the sale) ; same for the S-T9 merge of two sheets created at the same instant (a plain re-read sees the transaction's snapshot, where the other sheet does not exist yet) |
| Stock movements | Never accepted as-is — replayed through `AdjustStockAction` for full server recomputation. S-T10 : un inventaire du poste porte `counted_quantity` + `counted_at` ; l'écart est calculé par `InventaireAuComptageService` contre le grand livre à l'instant du comptage (règle du web), daté de cet instant ; comptage dépassé par un inventaire plus récent ou sans écart : acquitté sans mouvement. Sans ces clés (poste ancien) : l'écart envoyé, comme avant. S-T12 : un mouvement daté AVANT un comptage déjà enregistré (vente d'une caisse restée hors ligne, achat du poste daté par `purchased_at`, vente antidatée au web) est gardé à sa date et neutralisé après le comptage par une régularisation `inventaire` datée de lui (`InventaireAuComptageService::compenserMouvementAnterieur`, appelé par `AdjustStockAction` — donc au web aussi) ; la perte 657 du comptage suit son écart recalculé. Le stock initial d'un produit créé entre par un mouvement « Stock initial » |
| Expenses | U14 : created, MODIFIED or ARCHIVED from a device through `SaisieDepenseAction` — the single point of passage of `SaisieDepenses` too. **DEP1–DEP3 : one expense = one header (`expenses`) + N lines (`expense_lines`, UUID)**; the total is the SUM of the lines (`expenses.amount`, never typed), `expenses.label` is their summary. Creation = header + lines + ONE entry (one debit per charge account, one credit of the treasury) + treasury decrement in ONE transaction (entry refused ⇒ nothing written). An accounted expense is IMMUTABLE (corrected by archival = exact reversal of the original entry, then a new entry); an expense WITHOUT entry (legacy) stays editable and never receives a retroactive entry. The device sends the document WITH its lines; strict absorber (`SaisieDepenseAction::valider`: charge account of class 6, integer amounts > 0, total = sum, closed year refused); a FLAT payload of a not-yet-migrated device is accepted and converted to ONE line (the server is deployed BEFORE the devices); a known identical row is acknowledged without replay |
| Expenses | U14 : created, MODIFIED or ARCHIVED from a device through `SaisieDepenseAction` — the single point of passage of `SaisieDepenses` too (same rules: an accounted expense keeps its amount, charge account and treasury account; an archived one is not modified; a second archival does nothing). A known identical row is acknowledged without replay |
| Quotes | Ticket DEV : « Devis & Proforma » created, advanced (`brouillon → envoyé → accepté ou refusé`) or archived from a device through `SaisieDevisAction` — the single point of passage of `Livewire\Ventes\Devis` too. The `DEV-AAAA-NNN` number is NEVER read from the device (server-assigned, returned at the next pull) ; a quote dated in a CLOSED fiscal year is read-only (R4 motive) ; an archived or invoiced quote is not modified ; a forbidden status change is refused with its motive ; the same row replayed is acknowledged without write. `quotes` is pulled to `view-ventes` accounts (archived included) |
| Customer returns (AV1/AV2) | A device sends a DEMAND in `credit_notes` (`manage-ventes`, after `sales`): `pushCreditNotes` → `AvoirClientService` (the sole entry point, shared with `RetoursAvoirs::saveReturn()`) numbers it (`AV-YYYY-NNN`, year of the return day), re-adds the stock if « réintégré », posts the inverse entry (D 701 / D 443 / C 411) dated the RETURN day, in ONE transaction; refuses quantity > sold − already returned, amount > line − already credited, cancelled/unknown sale, product off the sale, future or pre-sale date, closed/absent fiscal year, incomplete chart (nothing written). Idempotent by the device UUID; a known note resent as `traite` is marked treated once. A known sale resent as `annulee` is cancelled once (`AnnulerVenteAction`: stock back, status, audit); an unknown sale sent cancelled is received then cancelled. `credit_notes` is pulled (paginated family, `view-ventes`) |
| Corbeille (ARC) | **"Archivé par" (ARC-Q2):** `audit_logs.entity_type/entity_id` (nullable) name the archived record; every archive path calls `AuditLog::record($action, $module, null, $model)` and its action key is listed in `AuditLog::ACTIONS_ARCHIVAGE` (a new archive path MUST do both — `CorbeilleArchiveParTest` proves it per type); the Corbeille reads the latest archive audit, shows "—" when unknown. `CorbeilleService` is the sole entry point of the web page AND of the device demands. Pull `corbeille` (snapshot of archived items with what the server allows and why; page 1; `manage-parametres` only), push `corbeille_demandes` (restaurer / supprimer, processed LAST, idempotent by device UUID via `corbeille_operations`). Expenses, cancelled sales and cancelled transfers are never restorable; hard delete only for unreferenced products/suppliers/customers/employees and referentials, word `SUPPRIMER`. |
| Lock order | U14 : `OrdreDesVerrous::stock` — the `products` rows a transaction will move, by ascending id, BEFORE any daily sheet or lot (device push, web POS, the five sheets, Transformation). Never write a sheet before locking the stock it moves |
| Fiscal year closure | Never synced — the API refuses it in any form |

The controller demonstrates each rule on a representative subset of tables, not all ~60. Extending to a new table follows the same block pattern.

### Verrou de session web (sprint VW, 26/10/2026)

Demande du client : « appliquer aussi le module de verrou session sur le web ». PRD : `docs/prd/verrou-web.md`. Le verrou est présent **des deux côtés** (le poste a le sien depuis VL-1/VL-2) ; le web est le maître, le poste s'aligne sur ses textes.

- **Effectif côté serveur, pas une surcouche.** L'état `session_locked` vit dans la session Laravel. Le middleware `App\Http\Middleware\SessionVerrouillee` (groupe `web`, ajouté dans `bootstrap/app.php`) refuse toute requête tant qu'il est posé : page → redirection vers `/verrouillage` (la page demandée est mémorisée pour le retour), requête JavaScript / Livewire (`POST /livewire/update`) / JSON → **423** `{verrouille: true}`. Exempts : `session.verrou`, `session.deverrouiller`, `session.verrouiller`, `logout`, pages publiques, `/up`, fichiers JavaScript de Livewire. L'API du poste (Sanctum) n'a pas de session : jamais concernée. **Ne jamais retirer le middleware du groupe `web`** : `VerrouSessionMiddlewareTest::test_le_middleware_est_dans_le_groupe_web` le garde.
- **Un seul point de passage : `App\Services\VerrouSessionService`** (durées `DUREES = [0, 1, 5, 15, 30]`, défaut 5, libellés, `verrouiller()`, `deverrouiller()`). Le secret est le **mot de passe du compte**, vérifié ici (`Hash::check`), avec le limiteur de la connexion (`Login::MAX_TENTATIVES` = 5, `Login::DUREE_BLOCAGE` = 900 s, clé `deverrouillage|<id>|<ip>`), puis **10 échecs cumulés dans la session = déconnexion complète** (compteur `session_lock_failures`, remis à zéro par un succès seulement). Cookie « se souvenir de moi » : retiré au verrouillage, rétabli au déverrouillage (sinon supprimer le cookie de session rouvrirait une session déverrouillée).
- **Routes** (`auth` seul, comme `/mon-profil`) : `POST /verrouiller`, `POST /deverrouiller` (JSON : 200 / 422 / 429 / 401 `deconnecte`), `GET /verrouillage` (`Livewire\Auth\EcranVerrouillage`). Audit : `session.verrouillee`, `session.deverrouillee`, `session.deverrouillage_echec`, `session.deconnexion_apres_echecs` ; jamais le mot de passe.
- **Navigateur** : `components/verrou-session.blade.php` (surcouche plein écran à la présentation de la connexion, posée dans `layouts/app.blade.php` HORS de `#app-racine`, absente de `guest`) + `resources/js/verrou.js` (minuterie d'inactivité partagée entre onglets par `localStorage`, vérifiée sur l'horloge toutes les 5 s) + `verrou-logique.js` (logique pure, testée par `node --test tests/Js`). La surcouche **ne démonte pas la page** : une saisie Livewire non enregistrée survit au déverrouillage ; un 423 reçu par Livewire fait apparaître la surcouche au lieu d'une fenêtre d'erreur. Pas de verrouillage pendant une requête Livewire en vol (exports et PDF passent par Livewire) ni 60 s après un clic sur `a[download]` / `[data-verrou-suspendre]`. Limites assumées : un rechargement perd la saisie non enregistrée ; ce qui était déjà affiché reste dans la mémoire du navigateur (le serveur, lui, refuse tout ce qui est nouveau).
- **Réglage** : `users.verrouillage_minutes` (défaut 5, 0 = Jamais), carte « Verrouillage automatique » de Mon Profil (`MonProfil::updatedVerrouillageMinutes`), lue par `User::delaiVerrouillage()` (valeur inconnue = 5). Hors `$fillable`, **jamais** dans les colonnes de `users` que `SyncController` donne au poste.
- **`SESSION_LIFETIME` reste indépendante** (glissante, renouvelée à chaque requête, dont le déverrouillage). Session verrouillée qui expire : le déverrouillage répond 401/419 et la page renvoie à la connexion.
- **Textes communs avec le poste** (ne jamais en changer un seul côté ; `test/verrou_parite_web_test.dart` lit ce Blade) : « Verrouiller » (icône `lock`), « Application verrouillée », « NOM D'UTILISATEUR », « DÉVERROUILLER », « Verrouillage automatique », Jamais / 1 minute / N minutes, « Trop d'essais. Réessayez dans … », « Trop d'échecs : … ».
- **Environnement de test** : `phpunit` lancé depuis un worktree dont `vendor` est un lien global charge le code du dépôt principal ; copier `vendor/composer` et lier le reste, et lancer `php vendor/phpunit/phpunit/phpunit` ne suffit pas non plus (il charge l'autoload du dépôt principal) : un lanceur de deux lignes (`require vendor/autoload.php; (new PHPUnit\TextUI\Application)->run($argv)`) règle le cas.

### Attestations (ATT-1, ATT-2 — 27/10/2026)

PRD : `docs/prd/attestation-fidelite-signataires.md`. **Une seule fabrique côté serveur, `App\Services\AttestationService`** (page web et `POST /api/attestations`). **ATT-3 : le poste produit AUSSI son PDF** (`agrierp_flutter/lib/core/export/pdf_attestation.dart`, même visuel, même règle de signature) ; le serveur reste l'AUTORITÉ DU NUMÉRO et de la TRACE : `POST /api/attestations/emissions` → `AttestationService::emettre()` (idempotent par l'identifiant d'émission du poste, numéro figé dans `attestation_emissions`, ligne d'audit `attestation.generated.*` à l'instant de l'émission). Hors ligne, le poste imprime `N°—/AAAA/FEO/DG` et met l'émission en file.

- **Visuel** : `resources/views/exports/attestation.blade.php`, A4 paysage, **positions absolues en points** mesurées sur le modèle du client ; ressources dans `resources/attestation/` (logo, filigrane, décor extrait du modèle, polices libres — voir son `LISEZMOI.md`). ⚠️ Pièges DomPDF payés : (1) `line-height` est un PLANCHER sous la hauteur de police (Caladea a une boîte très haute : interligne 1,6 em) — `font_height_ratio` 0,86 ramène l'interligne à celui du modèle ; (2) `text-decoration: underline` suit les métriques de la police et COUPE les lettres : soulignement par `border-bottom` sur un `inline-block` ; (3) ne jamais retoucher les métriques d'une police avec fontTools : php-font-lib lit alors un mauvais `cmap` (glyphes faux) ; (4) `storage/fonts` doit exister et être inscriptible (créé par le service).
- **Qui signe = règle du modèle** (`attestation_templates` : `seuil_signature_mois`, `sigN_court/long`, `sigN_titre/nom/fonction`, `appreciation_text/imprimee`), servie au poste par `AttestationTemplate::pourLePoste()`. Positions : **1 = Directeur Général (le promoteur), 2 = Examinateur, 3 = Président du Jury** ; ordre d'impression 2, 3, 1. ≤ seuil mois INCLUS : palier court ; au-delà : long. ⚠️ `forType()` passe TOUTES les valeurs par défaut : une ligne tout juste créée n'a pas relu les défauts de la base (un `null` lirait « personne ne signe »).
- **Texte** : `**gras**` dans le modèle (le nom de la ferme y passe en vert) ; `corps()` rend le texte sans marques (aperçu, tests), `corpsMarque()` + `enHtml()` pour le PDF. Balises ajoutées : `[DE_DUREE]`, `[DATE_*_LONGUE]`, `[CIVILITE_LONGUE]`.
- **Poste** : `AttestationsRepository.palier/requis/formatDuree` sont la transposition PHP, **exécutée contre le serveur** par `test/attestations_parite_php_test.dart`.

### RH au poste (RH-1 à RH-4 — 27/10/2026)

PRD : `docs/prd/rh-crud-poste.md`. **Trois points de passage uniques, partagés par les composants Livewire et `SyncController`** : `App\Actions\SaisieEmployeAction` (`RegistreEmployes` / `pushEmployees`), `App\Actions\SaisieStagiaireAction` (`RegistreStagiaires` / `pushInternships`, `pushInternshipAbsences`) et `App\Services\ReglementPaieService` (`GestionPaie::validerReglement` / `pushPayslipRequests` : bulletin, trésorerie, écriture, audit dans UNE transaction ; exercice clos et employé archivé refusés AVANT d'écrire, `ReglementPaieRefuseException`). Clés d'envoi ajoutées (`manage-rh`, traitées après `customers`, avant les pointages ; `payslip_requests` après `attendance_records`) : `employees`, `internships`, `internship_absences`, `payslip_requests` (une DEMANDE : `employee_id`, `period_month` `AAAA-MM`, `requested_at` ; jamais un montant — le serveur recalcule). `pushAttendance` accepte `is_active`. Tirage : `employees` sert TOUS les employés avec `is_active` ; `internship_absences` et `income_tax_brackets` (`view-rh`) ; `attendance_records` archivés compris ; `company_settings` + les cinq taux de paie ; `payslips` ajoute ses colonnes RH (`employee_id`, `period_month`, brut, retenues, charges patronales) **seulement** au compte `view-rh` (protection S3 maintenue pour `view-rapports`). `employees` / `internships` ne sont plus dans `referentiels_ignored`. Tests : `SyncRhCrudTest`, `SyncPaieDemandeTest`, `SyncPointageTest`. RH-Q1 à RH-Q3 (27/10/2026) : filtre « Archivé » du Registre Employés ; barème ITS validé ; **`attendance_records` est une famille PAGINÉE servie en entier** (plus de borne à 60 jours).

### Utilisateurs au poste (UT-1 — 27/10/2026)

`App\Actions\SaisieUtilisateurAction` est le point de passage unique de `Livewire\Parametres\GestionUtilisateurs` ET de `SyncController::pushUsers` (clé d'envoi `users`, droit `manage-users`, après `employees`) : mêmes règles (`regles($id, $creation)` : identifiant sans arobase, unicité, rôle existant, `Password::defaults()`), mêmes effets (rôle, jetons révoqués à l'archivage, audit), mêmes messages ; le propre compte de l'auteur ne s'archive pas ; un compte connu et identique est acquitté sans écriture ; `password` facultatif à la modification (absent = conservé), jamais journalisé ni servi. Le tirage `users` sert `updated_at`. Tests : `SyncUtilisateursTest`.

### Scheduling

`routes/console.php` holds all 5 scheduled tasks (daily `agrierp:backup` at 02:00, `DailyProphylaxyReminderJob` at 06:00 Africa/Porto-Novo, weekly session GC / notification purge / failed-job prune, weekly backup-download reminder). Production uses **one** cPanel cron entry running `php artisan schedule:run` every minute — never one cron per task.

## Front-end shell: fonts, PWA, .htaccess

Three things live outside the Blade/Livewire layer and are easy to break by accident. `tests/Feature/PwaEtPolicesLocalesTest.php` (11 tests) guards all of them — none of these failures produce a visible error.

### Fonts are local. Never re-add Google Fonts.

`layouts/app.blade.php` and `layouts/guest.blade.php` used to load Inter from `fonts.googleapis.com`. On a farm whose link drops, every page load waited on an unreachable server before falling back to a system font. Inter now ships from `public/assets/fonts/`.

- **Inter is a variable font**: one `.woff2` per subset covers weights 100–900. `Inter-latin.woff2` (48 KB) always loads; `Inter-latin-ext.woff2` (85 KB) only when the page contains a character in that range. Google's API returns the *same* URL for `wght@400;500;600;700;800` and for `wght@100..900` — verified, not assumed.
- The `@font-face` declares `font-weight: 100 900`. Declaring `400` makes the browser **synthesize** bold and distorts every 700/800 heading.
- Material Symbols is also local, subsetted to 37 KB (was 3.87 MB).
- The test ignores Blade **comments**: the docblocks here quote `fonts.googleapis.com` to explain why not to touch it. It is the `<link>` tag that is forbidden, not the mention.

### PWA

| File | Role |
|---|---|
| `public/manifest.webmanifest` | `display: standalone`, theme `#052e16`, 4 icons, 3 shortcuts |
| `public/sw.js` | service worker |
| `public/offline.html` | standalone waiting page |
| `public/assets/icons/` | 6 icons derived from the farm's official favicon |
| `resources/views/components/pwa-install.blade.php` | the install invitation |

**The service worker is deliberately narrow — do not widen it without thinking:**

1. **Only `GET` is intercepted.** Livewire drives the whole app through `POST /livewire/update`; caching those breaks every form.
2. **No authenticated HTML is ever stored.** A browser cache is not partitioned per user — a cached dashboard could reappear after logout on the shared counter machine. Navigations go to the network and fall back to `offline.html` only on real failure.
3. **Only static files are cached.** `/livewire/`, `/api/`, `/login`, `/logout`, `/storage/` are excluded explicitly.

Bump `VERSION` in `sw.js` on every deploy that changes a cached asset — `activate` purges older caches. A machine that already visited keeps serving the old file from disk otherwise.

**This PWA does not make AgriERP work offline, and that is not a gap**: disconnected work is the dedicated client's job, via `/api/sync/*`. A browser cache pretending to take sales offline would create two sources of truth.

The install window sits **bottom-left** (`bottom-md left-md`). Not right: the toast container occupies bottom-right at z-index 200, and ticket 14.28 already fixed toasts intercepting clicks on the POS "Valider la Vente" button. iOS has no `beforeinstallprompt` — that branch shows the manual Share ➔ Add to Home Screen instructions instead of a dead button.

### .htaccess — both files matter

Neither existed before Sprint 15; **that is why every URL 404'd on the first real deployment**. `php artisan serve` has its own router and never reads `.htaccess`, so the gap was invisible in development.

- `public/.htaccess` — canonical Laravel rewrite, plus `AddType application/manifest+json .webmanifest`. **Apache does not know that extension by default**: it serves the manifest as `text/plain`, the browser silently ignores it, and the app stops being installable with no error anywhere. Also `no-cache` on `sw.js` and long immutable cache on fingerprinted `build/` assets.
- `.htaccess` at the project root — a **safety net, not the right configuration**. It disables directory listing, denies sensitive files and rewrites everything into `public/`. It exists only because the hosting document root still points at the project root. Read its header before touching it.

⚠️ `storage` is deliberately **absent** from the root file's `RedirectMatch` block list: `public/storage` is the symlink to uploaded receipts and photos, and blocking `/storage/...` would break their display.

## Who is who on this project

Three structures, three distinct roles. `tests/Feature/CreditsProjetTest.php` keeps all three credited across login, public pages, Aide and Contact.

| Structure | Role |
|---|---|
| **PAEB** — Projet d'Appui à l'Entrepreneuriat au Bénin | Maîtrise d'ouvrage |
| **Cabinet FAGUEZ SARL** | Accompagnement des PME |
| **Dr MASSENON Rhodes**, Docteur en Génie Logiciel et IA | Éditeur du logiciel |

Editor contact: `rarhodes06@gmail.com`, `contact@massenonrhodes.com`, +229 01 51 33 50 40 / 01 97 31 24 37.

⚠️ **`bareme-its.blade.php` names "Cabinet FAGUEZ" on purpose.** It was once flagged as a leftover from renaming the editor. It is not: a tax scale is validated by the accompanying firm, never by the author of the code. A test locks it.

## Deployment state (as of ticket 15.8)

Live at `https://agrierp.fermeolouwachegoun.com`. Probed from outside, not assumed:

- ✅ `.htaccess` deployed and working — `/login` 200, manifest MIME correct.
- ❌ **The document root still points at the project root**, not `public/`. Proof: `/public/robots.txt` answers 206; under a correct root it would 404. Protection currently rests entirely on the root `.htaccess` — lose it in a redeploy and the whole source tree is browsable again.
- ⚠️ `agrierp.zip` (72 MB, **contains `.env`**) answers 404, but that proves nothing: the root `.htaccess` rewrites everything into `public/`, so a file at the project root is unreachable whether or not it exists. **Verify on disk.**
- ⚠️ **The live site runs the ticket-15.4 build.** Live CSS `app-D_IdB1ks.css`, live `sw.js` at `agrierp-v1`, live Material Symbols still 3.96 MB. Tickets 15.5–15.8 are not deployed.

`RUNBOOK_DEPLOIEMENT_CPANEL.md` holds the project's own cPanel procedure.

## The user manual

The client deliverable `Manuel_Utilisation_AgriERP.pdf` (92 pages) is **not built by hand**. Sources live in `C:\Projects\agrierp_laravel\manuel\`:

- `src/part0..6.html` — the content, one file per group of chapters
- `build.py` — assembles, renumbers figures, then calls `imprimer.php`
- `imprimer.php` — prints via Chrome CDP (`Page.printToPDF`), needs chromedriver on port 9515
- `img/` and `jpg/` — 166 real screenshots of the running app

A text correction is one `py build.py` away. Never edit the PDF. The screenshots were captured by driving Chrome against the real database, and the labels quoted in the manual were extracted from the DOM, never retyped.

## Known contradictions — flag, do not silently resolve

Real inconsistencies in the source material; resolving one arbitrarily is a regression.

- **RBAC role count**: the CDC says 7 roles, the `roles` enum 6, the permission matrix 5, and both `RolesAndPermissionsSeeder` here and `RBAC_PAGE_MAP` in the prototype implement **4**. Add new screens to the 4-role model; escalate anything beyond that to the client.
- **Screen count** is quoted as 94, 97, and 99 across documents; 62 named web routes exist today.
- **Prototype-internal contradictions**: a single prototype file can carry two incompatible taxonomies between its own sections (e.g. the Morts/Dons category split vs. the Rationnement table on the same species sheet). Document the divergence and propose a reasoned choice — never pick one silently.
- Open client arbitrations are recorded in `README_SPRINT0.md` under **ARBITRAGE CLIENT**.

## What legitimately changes in HTML → Blade conversion

**Preserved identically**: section order, table column count (count them, never estimate), button positions, exact labels and punctuation, Tailwind spacing tokens, Material Symbols icon names, tab count and keys (verified against the prototype's own switch function — screens use custom names like `switchStockTab`, `switchProfileTab`, `switchClotureTab`).

**Legitimately transformed**: hardcoded JS arrays → real Eloquent queries; client-side search/pagination → server-side; non-persisting client validation → real validation and writes; ID-driven modals → named Livewire events; hub iframes → nested Livewire components.

**Correctly excluded**: explicitly-marked demo widgets (`testerPopupAlertesStock`, `testerPopupProphylaxie`, the test-role switcher, the Flutter-only "Synchroniser" button). Their absence is not an oversight.

The two failure modes are symmetric: losing visual fidelity, or leaving CRUD decorative. Neither is acceptable.

## Working rhythm

One ticket = one session. Never batch-convert screens without intermediate verification. Announce the plan (migrations, Actions, component structure) before writing code. Build order per screen: migration → Eloquent model → Action/Service → Livewire component → Blade view.

`README_SPRINT0.md` is the **append-only delivery log** (~816 KB). Every ticket and audit pass is recorded there with its real findings — including honest statements of what was *not* done and why. Add to it; never start a parallel log.

**`README_SPRINT0.md` exists in two places and must stay byte-identical**: here and at `C:\Projects\agrierp_laravel\README_SPRINT0.md`. Append every ticket to **both**. They had drifted by ~2400 lines, and that gap hid six unbuilt tickets and swallowed ticket 14.25 entirely. Compare hashes of both files before appending, not by eye.

Seeded demo accounts, password `AgriERP@2026` — login accepts the **short username or the e-mail** (ticket 14.50): `admin` (contact@), `compta`, `caisse`, `elevage`, all `@fermeolouwachegoun.com`. The e-mail column stays: it carries password reset.

Root-level `*.md` files are project artifacts, not generic Laravel docs: `RUNBOOK_DEPLOIEMENT_CPANEL.md` (exact deployment commands for this repo), `CHECKLIST_PRE_DEPLOIEMENT.md`, `STRATEGIE_BASCULE_PAPIER_NUMERIQUE.md` (paper → digital cutover, with the data-entry gaps it exposed), `SETUP_API_SANCTUM.md`, `ADDENDUM_FULL_MIGRATIONS_DATABASE_FLUTTER.md` (Drift tables the Flutter side still lacks).

A full narrative of every session since `/init` — what was asked, what was found, which assumptions turned out wrong, what is still open — is in `HISTORIQUE_SESSIONS_CLAUDE.md`, kept identical in this directory and in `C:\Projects\agrierp_laravel\`. **Read it first when resuming after a gap**: several conclusions in the older documentation were contradicted by the real code, and that file records which ones.

## Environment traps that cost time

- **Local Apache runs PHP 8.1.10**; this project needs ^8.3. `agrierp.test` therefore returns **500** — pre-existing, unrelated to whatever you just changed. Develop against `php artisan serve --port=8002`.
- **Killing `php artisan serve` does not free the port.** It spawns a child `php -S 127.0.0.1:8002` that survives its parent. Target the child.
- Livewire needs a moment to hydrate before a scripted login works. A `sendKeys` fired too early submits empty credentials and silently stays on `/login` — wait, then assert the URL actually changed.
- Web login is rate-limited to **5 attempts / 15 min per identifier+IP** (`RateLimiter` in `Livewire\Auth\Login`). Repeated scripted logins can lock you out.
- When driving the UI by clicking on a **text label**, exclude `aside` and `header` first: a tab named "Créances" or "Commandes" also exists in the sidebar, and the click silently navigates elsewhere.

## Fenêtre « Rappels du jour » (tickets POP1 à POP4, 26/10/2026)

`App\Services\RappelsDuJourService` est le **point de passage unique** de la règle R-RAPPELS-01 (PRD `docs/prd/popup-rappels.md`) : il APPELLE `AlertesElevageService::soinsAVenir()` / `joursRappelSoins()` (R-SOINS-01) et `ProtocoleDuJourService::pourBande()` — ne rien recopier. Le poste le reprend en local (`rappels_du_jour_repository.dart`, parité exécutée). `Livewire\Shared\RappelsDuJour` (monté dans `layouts/app.blade.php` sous `@can('view-elevage')`) décide côté serveur : `ouvrir($dejaVuSession, $masqueLe)` ; le navigateur ne fait que transmettre `sessionStorage` (une fois par session de navigateur) et `localStorage` (« Ne plus afficher aujourd'hui », par utilisateur). Un événement `Login` pose `rappels_forcer` (réouverture à chaque connexion). Aucune fenêtre vide, erreur journalisée et silencieuse. Tests : `RappelsDuJourTest`.

