# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

The **Flutter Desktop client** of AgriERP — Ferme École OLOUWACHEGOUN (Ikpinlè, Benin). Windows, offline-first, synchronised with the Laravel web surface over `/api/sync/*`.

**All code comments, UI labels, test names and prose are in French.** Keep it that way.

| Structure | Role |
|---|---|
| **PAEB** — Projet d'Appui à l'Entrepreneuriat au Bénin | Maîtrise d'ouvrage |
| **Cabinet FAGUEZ SARL** | Accompagnement des PME (validates *regulatory* figures: tax scales, social charge rates) |
| **Dr MASSENON Rhodes**, Docteur en Génie Logiciel et IA | Éditeur du logiciel |

Three codebases, one product:

| Codebase | Path | Role |
|---|---|---|
| HTML prototype + knowledge base | `C:\Projects\agrierp_laravel\` | **visual and behavioural source of truth** for both clients |
| Laravel 12 + Livewire 3 web app | `C:\laragon\www\agrierp` | server, business rules, sync API |
| **This Flutter client** | `C:\Projects\agrierp_flutter` | offline-first Windows desktop |

⚠️ **`prototype_html/` and `docs/` here are EMPTY and must stay empty.** The prototype is read from the Laravel repo. Copying it would create a second source of truth that silently drifts — the exact failure mode that once let `README_SPRINT0.md` diverge by ~2400 lines and hide six unbuilt tickets.

⚠️ Not a git repository. There is no history to consult; the ticket log is the history.

## Read these before touching anything

| File | Why |
|---|---|
| `C:\Projects\agrierp_laravel\HISTORIQUE_SESSIONS_CLAUDE.md` | narrative of every session, **including which older conclusions turned out false** — ten minutes, read it first |
| `C:\Projects\agrierp_laravel\README_SPRINT0.md` | the append-only ticket log; `F0.x` = this repo, `14.x`/`15.x` = Laravel. **Search it before re-deciding anything** — most traps are already written up |
| `C:\Projects\agrierp_laravel\agrierp-flutter.skill` (zip) | `references/regles-metier-critiques.md` inside carries ~60 rules extracted from real defects, most of which **raised no error** — only the figures were wrong |
| `C:\laragon\www\agrierp\CLAUDE.md` | authoritative on everything server-side |

⚠️ `README_SPRINT0.md` exists in **two copies that must stay byte-identical** — `C:\Projects\agrierp_laravel\` and `C:\laragon\www\agrierp\`. Hash both before appending, never compare by eye.

The four costliest business rules:

1. **Every financial operation produces its accounting entry** — 12 flows, including the **loss** (inventory discrepancy), forgotten for eight sprints on the Laravel side.
2. **Treasury is kept in two books that must agree** (account balances and class-5 ledger). Trap hit three times.
3. **Employee deductions ≠ employer charges.**
4. **A displayed limitation is a DATED sentence** — re-read every pending marker at the end of each sprint.

## Commands

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after ANY change to a Drift table
flutter analyze                    # must end with "No issues found!" — non-negotiable before a ticket is done
flutter test                       # ~1 983 tests (after F0.95); use --concurrency=2 if memory is short
flutter test test/caisse_test.dart                       # one file
flutter test test/caisse_test.dart --plain-name "…"      # one test, by its (French) name
flutter build windows --release    # → build\windows\x64\runner\Release\agrierp.exe
```

### Tests that need the real server

`dart_test.yaml` declares an `integration` tag. Those tests (`test/sync_reel_test.dart`) require `php artisan serve --port=8002` in `C:\laragon\www\agrierp`; **without it they mark themselves SKIPPED, never failed** — a permanent red offline ends up ignored for good.

#### Essai à plusieurs postes (ticket S-T9, méthode TATACORA)

```bash
agrierp_flutter/outils/essai_multipostes.sh 42 7 2026     # une graine par essai ; sans argument, une graine au hasard (~3 min chacune)
ESSAI_BASE=sqlite agrierp_flutter/outils/essai_multipostes.sh 42   # sans MariaDB (le script le dit)
ESSAI_FUSEAUX="UTC America/New_York Asia/Tokyo" agrierp_flutter/outils/essai_multipostes.sh 42   # S-T11 : postes dans d'autres fuseaux
```

Le script fait tout, sans jamais lire ni modifier un `.env` ni ouvrir une base existante : MariaDB/MySQL privé dans un dossier temporaire (port et socket propres, base `agrierp_essai` en `utf8mb4_unicode_ci`), `migrate:fresh --seed` puis `DemoDataSeeder` (cinq mois d'activité : de vraies pages de tirage), `php artisan serve --no-reload` avec 4 processus (`PHP_CLI_SERVER_WORKERS`), le test `test/essai_multipostes_test.dart` à l'heure du Bénin (`TZ`), puis l'arrêt du **groupe** de processus du serveur (tuer `artisan serve` seul laisse `php -S` tenir le port) et de MariaDB. Rapports (`rapport-<graine>.txt` : journal des coupures et des envois, compteurs, invariants, état du serveur) et journaux dans un dossier temporaire hors dépôt, affiché à la fin.

- Cinq postes réels (bases Drift en mémoire, `SyncEngine` et `SynchronisationAutomatique` réels, connexion `POST /api/auth/login` avec jeton nommé d'après le poste) : bureau (admin), deux comptoirs (caisse), élevage (animalier), comptabilité (comptable). Quatre journées de gestes par les VRAIS dépôts ; la deuxième caisse est hors ligne une journée. Au web, pendant ce temps, par les vrais composants Livewire (`outils/essai_multipostes_serveur.php`) : deux bandes, une vente à la caisse web, une ration modifiée.
- Coupures (`_Perturbateur`, une suite aléatoire par poste, graine journalisée) : requête perdue, **réponse perdue après traitement**, délai dépassé, 500, 413 d'un mandataire au-delà de 14 000 octets (6 000 avant S-T12 : une journée couplée, indivisible, de 20 ventes d'un comptoir dépassait déjà la limite et partait en refus « envoi trop volumineux »). Puis réseau parfait jusqu'à ce que plus rien ne soit `pending`.
- ⚠️ **Le test écrit sur le serveur** : il exige `AGRIERP_ESSAI_URL` (posée par le script) et se marque SAUTÉ sinon — jamais contre le serveur de développement par accident.
- ⚠️ Le rejeu d'une graine est fidèle pour les coupures de chaque poste ; l'entrelacement des cinq postes au serveur dépend de l'horloge (c'est ce qui a fait sortir les interblocages MariaDB).
- Défauts trouvés et corrigés (S-T9) : voir `test/synchronisation_multipostes_test.dart` et `agrierp_laravel/tests/Feature/SyncEssaiMultipostesTest.php`.
- S-T10 : le bureau, hors ligne, fait l'inventaire du piment pendant que le web puis la caisse 1 en vendent ; invariant : stock final = comptage − vente postérieure, au serveur et sur chaque poste.
- S-T11 : `ESSAI_FUSEAUX` rejoue chaque graine avec le processus des postes dans chaque fuseau (le serveur reste à l'heure du Bénin). Les cinq postes d'un essai partagent un processus, donc un fuseau.
- Défauts trouvés et corrigés (S-T12) : une saillie et sa palpation saisies hors ligne avant tout envoi perdaient la palpation (créée sans ses étapes, puis écrasée au poste par le tirage) — `SyncReproductionTest` ; le stock initial d'un produit créé (web ou poste) n'entrait pas au grand livre — `ApiProduitsTest` ; le curseur `since` envoyé en UTC était lu à l'heure murale du serveur (chaque tirage resservait l'heure écoulée : 6 pages au lieu d'une) — `SyncCurseurFuseauTest` ; deux caisses vendant dans la même bande le même jour, envois simultanés sur une fiche déjà connue : la `vente` était lue sans verrou et une vente comptait zéro fois (MariaDB seulement) — garde-fou dans `SyncEssaiMultipostesTest`, preuve par l'essai (graine 7) ; la fiche (bande, jour) créée au même instant par un envoi et par une vente (web ou poste) : la seconde insertion heurtait l'unicité (`SQLSTATE 1062`, vente du web perdue, envoi en 500) — `SyncEssaiMultipostesTest` (graine 314) ; deux comptoirs créant la même fiche au même instant : la relecture de fusion (S-T9) lisait l'instantané de sa transaction et refusait la fiche « en double » — relue sous verrou (graine 5) ; une vente ou un achat fait AVANT un comptage et arrivé APRÈS lui était compté en plus, et l'achat du poste était daté de sa réception — `SyncInventaireRegularisationTest`, `test/achat_instant_envoi_test.dart`.
- Défauts décrits, non corrigés (S-T12) : la caisse du web (`PosInterface::validateSale`) n'est pas rejouée sur un interblocage MariaDB (l'envoi des postes l'est, S-T9) — l'aide de l'essai revalide comme la caissière et le dit au rapport ; la rejouer au serveur exige de sortir MeCeF de la transaction. Une journée couplée (fiches + ventes du jour d'un poste) est indivisible : plus grosse que la limite du mandataire de l'hébergement, ses ventes partent en refus « envoi trop volumineux » — limite à vérifier en production (`post_max_size`, ModSecurity).
- S-T12 : l'essai couvre TOUT ce qui se synchronise, en **cinq journées au moins** (`ESSAI_JOURS`, défaut 5 ; ~3 min par graine) : achats à crédit, règlements, retours et remboursements fournisseurs, imputations d'avances (dont une sur la vente à crédit du MÊME envoi, écrite directement en table : aucun dépôt ne l'offre, F0.73), produits créés au poste (le même créé au web : fusion S-T5), dépenses, Paramètres Élevage, infirmerie, calendrier, archivage d'un soin, étapes d'un cycle (saillie et palpation dans le même envoi) ; appairage révoqué (caisse 1) et compte désactivé (comptabilité) au web → 401, synchronisation automatique suspendue, reconnexion (le limiteur de connexion, 5 par minute, est respecté) ; la caisse 2 hors ligne trois journées puis de retour (lots de 50, tirage en pages de 40 imposées par `taille`) ; une vente et un achat faits AVANT un inventaire et arrivés APRÈS lui ; la demande du web (S-T6, ~30 s d'attente) ; la réinitialisation au web en fin d'essai (jetons révoqués → reconnexion, envoi sans la marque → 409, purge de chaque poste, rien ne ressuscite). Invariants ajoutés : trésorerie dans les deux livres par code de compte, créances, dettes, avances et créances fournisseurs (tables = grand livre, en écart depuis l'instantané), dépenses comptabilisées une fois, état final de chaque saisie de l'élevage identique au serveur.

### Regenerating the prototype fixtures

`test/inventaire_maquette.g.dart` and `test/structure_maquette.g.dart` are **generated from the prototype**, not hand-written. To add the pages a new screen ports:

```powershell
py outils/fixtures.py rapport-tresorerie.html rapport-creances.html …
```

It extracts, formats, inserts and runs `dart format`. ⚠️ It **appends only** — see weakness 3 above. `outils/inventaire.py` and `outils/structure.py` remain usable on their own to *inspect* a page (they print JSON to stdout).

All three read from `C:/Projects/agrierp_laravel/prototype_html`, and strip `<script>` blocks and the shared chrome (`aside`/`nav`/`header`) first — rows built in JavaScript are demo data, not labels, and a check that fails on noise ends up ignored.

⚠️ **Escape `$` when emitting Dart string literals.** The mockup writes « Lapines Reproductrices ($R_1..R_n$) »; Dart reads that as interpolation and refuses to parse. Invisible when reading the HTML, fatal at generation.

## Source-of-truth hierarchy — never invert it

1. **The HTML prototype** wins on anything visual, structural or behavioural. Read the source file in full before converting a screen — never reconstruct from memory.
2. **The Laravel implementation** wins on business rules and calculations. A rule was fought for there, usually against a real defect; re-deriving it here re-introduces the defect.
3. **The knowledge-base docs** supply what neither shows.

If something is in none of the three, say so explicitly rather than inventing a business rule.

## Layout

```
lib/
  core/
    auth/        permissions_poste.dart (EcranPoste enum + RBAC map), garde_ecran.dart, auth_service.dart
    config/      parametres_poste.dart      — deviceId + server address, read BEFORE runApp
    database/    app_database.dart (schema v38) + .g.dart, sync_columns.dart
    export/      document_officiel.dart (PDF), export_tableur.dart (xlsx) — pure builders
    fenetre/     fenetre_poste.dart         — MethodChannel `agrierp/fenetre` (frameless window)
    sync/        sync_engine.dart (~1800 l), sync_button.dart
    theme/       agri_tokens.dart, agri_theme.dart
    widgets/     modale_agri.dart, carte_kpi.dart, tableau_mensuel.dart, barre_superieure.dart
  features/<module>/   <ecran>_screen.dart + <ecran>_repository.dart
  main.dart      — sidebar tree, screen routing, Dio client, sync engine wiring
```

**One screen = one `_screen.dart` + one `_repository.dart`.** The repository holds every query and computation; the screen renders. Business arithmetic inside a widget is neither reviewable nor testable in isolation. `production_oeufs_service.dart` is the one service — shared arithmetic used by more than one screen.

`main.dart` is not a thin bootstrap: it carries `_BarreLaterale.arborescence`, the **complete** sidebar tree of the prototype (`assets/js/sidebar.js`), group by group, in order.

## Working state (after ticket F0.95, 16 Oct 2026)

- **1 983 Flutter tests green** (4 skipped, integration tests without the server), `flutter analyze` clean, Drift schema **v38**, Laravel Feature suite 1 570 green. The absorber count is no longer quoted here: the guardrail test checks that every declared absorber is called. Windows release builds with `printing_plugin.dll` + `pdfium.dll` (as of F0.55; not rebuilt since).
- Since F0.55 the poste is **local-first for customers, advances, purchase returns and supplier refunds**: it writes only the FACT as `pending`, the server replays accounting/treasury/stock, and a rejection becomes `conflict` with its reason. The fidelity audit log is `AUDIT_FIDELISATION.md` (items 7 and 8 closed on 9 Oct 2026; item 9 in progress — phase A, T1–T4 done; T5/T6 wait for client answers Q1–Q3, T7 next; item 10 open).
- The paragraphs below describing F0.55 are kept for their traps; figures in them (test count, schema, table count) are historical.
- Sidebar: **every entry of the prototype is rendered**, and **none is greyed any more** — every screen of the mockup's sidebar is now embedded.
- **The poste produces documents.** `lib/core/export/` carries `ExportOfficiel` (PDF, a one-for-one transposition of `assets/js/pdf-export.js`) and `ExportTableur` (xlsx). Both are **pure builders**; the side effects (print dialog, file write) live in `EditeursRapports` and are injected, so screens stay testable without a printer or a disk.
  - ⚠️ **The Excel export goes BEYOND the mockup** — the prototype's six "Excel" buttons only raise a "prévue pour une prochaine itération" toast. It is a client-approved addition, documented as such in `ExportTableur`. Do not mistake it later for porting drift.
  - ⚠️ **The PDF footer credits the THREE structures**, where `pdf-export.js` names only two — it predates tickets 15.7/15.8. Rule 2 of the hierarchy applies: on a business rule, Laravel wins over the mockup.
- **Export buttons on other screens are still inert** (Soins & Vaccins, Ventes & Devis). The chain now exists; wiring them is a separate ticket.

Known weaknesses, deliberately deferred rather than patched in passing (they touch every ported screen and deserve their own ticket):

1. ~~One mockup divergence is left~~ — **RESOLVED / ASSUMED at F0.80** (provisional lead decision, to be confirmed by the client). `documents-administratifs` now shows the mockup's two cards with its labels (« Modèles disponibles » = `'—'`, no catalogue exists anywhere; « Générés (mois) » = ACTIVE documents dated in the current month, the web's calculation) plus « En attente » (signature) as an ASSUMED extra card. The page left `ecartsATraiter` for `ecartsAssumes` in `test/cartes_attendues.dart`; `ecartsATraiter` is now empty.
2. **Card LABELS are checked by nothing — except on three pages.** `inventaire.py` collects `h2`/`h3`/`button`/`th`/`label`; card labels live in `<span>`. The count check (F0.54) sees cards appear and disappear but never what they say. Since F0.78–F0.80, `courriers_poste_test.dart`, `archives_poste_test.dart` and `documents_poste_test.dart` each read the mockup's card labels (a regexp on the `<span>`) and compare them with the screen; every other page is still unchecked.
3. **The fixtures cannot be fully regenerated.** `outils/fixtures.py` appends new pages; a full regeneration of the 39 pages already present yields a *different* result (77 field labels in the file, 118 when regenerated). They were assembled ticket by ticket with unreproducible manual adjustments. Reconciling them means re-examining every exemption.
4. **`comptabilite-hub.html` is in no role's `RBAC_PAGE_MAP` list** — including the accountant's, which names `journal-comptable.html` but never the hub. Applied as-is, the accountant cannot reach the screen holding their own journal. Client arbitration.

## Sync Engine — the server half already exists

```
POST /api/auth/login    Sanctum token named per device
GET  /api/sync/pull     ?since=<ISO>  → 33 referential / history tables
POST /api/sync/push     livestock_daily_entries, sales, stock_adjustments, veterinary_records,
                        expenses, livestock_reproduction_events, purchases, attendance_records
```

Per-table server rules the client must respect:

- **Referentials (`products`, `product_categories`, …)** — the server always wins. Any push on them is **explicitly ignored** and reported in `referentiels_ignored`. Do not make them locally editable.
- **`livestock_daily_entries`** — last writer wins, upsert on the client UUID.
- **`sales`** — never updated. A repeated push of an already-synced sale is a **silent success**, not an error: the client may safely re-send what it never got an acknowledgement for.
- **`stock_adjustments`** — never applied as-is. The server replays them through its own adjust-stock action, recomputing from the product's real state. A blindly-applied offline delta would double-decrement undetectably.
  - ⚠️ **S-T10 : un inventaire envoie la QUANTITÉ COMPTÉE et l'INSTANT du comptage** (`counted_quantity`, `counted_at` en UTC), en plus de l'écart local (affichage, serveur ancien). Le serveur calcule l'écart contre son grand livre à cet instant (`InventaireAuComptageService`) ; le poste se recale au tirage de confirmation.
  - ⚠️ **S-T12 : un achat envoie son INSTANT** (`purchased_at`, UTC), comme une vente `sold_at` : le serveur date l'entrée en stock de l'achat, et un mouvement antérieur à un comptage qui arrive après lui est neutralisé par une régularisation d'inventaire (aucun calcul au poste : il se recale au tirage).

### Dates — ticket S-T11 (`lib/core/temps/heure_benin.dart`, point de passage unique)

- **Le jour métier est toujours le jour à l'heure du Bénin** (UTC+1 toute l'année, sans heure d'été : décalage fixe, pas de paquet `timezone`). Une date métier est tenue en HEURE MURALE du Bénin : `HeureBenin.maintenant()` / `aujourdhui()` au lieu de `DateTime.now()`, `HeureBenin.lire()` pour une date servie (un instant ISO `Z` / `+01:00` est ramené à l'heure du Bénin, jamais par `toLocal()`), `HeureBenin.plusJours()` au lieu de `add(Duration(days: n))` (sur un Windows à heure d'été, on tomberait à 23 h la veille).
- **Les instants techniques restent des instants** : `updatedAt` (écrit `HeureBenin.versInstant(heureMurale)` quand il vient d'une horloge métier), `server_time`, horodatages de synchronisation ; affichés par `HeureBenin.depuisInstant`.
- `test/heure_benin_test.dart` doit passer dans tout fuseau (`TZ=America/New_York flutter test …` : `flutter test` respecte `TZ`).

Client-side invariants, each paid for once:

- ⚠️ **UUIDs are generated client-side and never regenerated by the server.** `id` is deliberately not mass-assignable server-side; it is assigned explicitly.
- ⚠️ **Pull before push, always.** Pushing first makes the server work on referentials the device has not yet received — a sale carrying a product created elsewhere would be rejected as "unknown product" when it exists.
- ⚠️ **Nothing is marked `synced` before the server acknowledges it.** Marking on send makes a record lost in transit vanish from the queue: the device believes it synchronised and it exists nowhere.
- ⚠️ **`SyncStatus.conflict` exists beyond the CDC's `pending|synced`** — a server rejection returned to `pending` would be retried forever in silence.
- ⚠️ **The pull cursor comes from the server (`server_time`)**, never from the device clock. A slow clock re-requests the same changes forever; a fast one skips them permanently.
- ⚠️ **Le tirage est paginé (S-T4)** : `_tirer` suit `page_suivante`, absorbe CHAQUE page dans une transaction (`_absorberPage`) et n'avance le curseur qu'après la dernière. Le serveur ne sert que les tables que le compte lit ; `PerimetreTirage` les garde, et une table AJOUTÉE à cet ensemble (rôle, droits ou utilisateur changés) impose un tirage complet, une fois. Une table qui n'est plus servie n'est jamais vidée.
- ⚠️ **U13 — `expenses` est une table MIXTE** (saisie au poste ET tirée, archivage `is_active` compris : `_absorberDepenses` n'écrase jamais une dépense `pending`/`conflict`) et `payslips` descend en lecture seule (comptes `view-rapports`) : « Recettes et Dépenses » a la matière du web (parité exécutée, `rapports_parite_test.dart`). La cloche dit « il y a … » comme Carbon (`DureeRelative`, `duree_relative_test.dart`).
- ⚠️ **`updatedAt` is the instant of ENTRY, not of sending.** A device offline for three days would otherwise stamp everything at reconnection and beat more recent entries made elsewhere.
- ⚠️ **Rejections are carried all the way to the user.** The server answers table by table with accepted AND rejected ids with reasons, precisely so a rejection does not disappear silently.
- ⚠️ **Offline is not an error** — it is this farm's normal operating mode. A red error on every attempt teaches the user to ignore alerts, including real ones.

⚠️⚠️ **The absorbers stay STRICT: an inconsistent referential is REFUSED, not smoothed over.** Ticket F0.51 caught a real *server* defect this way — Spatie's `Role` model casts its key to int, so four roles arrived carrying `id = 1`. A `DoUpdate` would have merged them into one permission-less role, silently. A guardrail test now checks that every declared absorber is actually called: an absorber written but never invoked is a table that never comes down, and nothing says so.

## Design tokens — `lib/core/theme/agri_tokens.dart`

Transposed one-for-one from `prototype_html/assets/js/tailwind-config.js`. **14 colours, no more.** `brand-maize` does not exist in the config even though `sidebar.js` references it — that is a real prototype bug; use `accentYellow` (#FFD55F) everywhere.

Spacing names match the Tailwind classes (`p-md` → `AgriSpacing.md`), so converting a screen needs no arbitration. Responsive table breakpoint: **640 px exactly**; below it each row stacks and every cell carries its own label (the HTML's `data-label`).

⚠️ **`AgriTypography.xs` is 13.6 px, not Tailwind's 12** — `assets/css/common.css` overrides `text-xs` to `0.85rem !important`. It is the most-used size in the prototype (3 569 occurrences), so it is the most visible error a port can make; it had been written as 12 px in 224 places.

### Counting indicator cards

Every screen test asserts its card count against the mockup, via `test/cartes_attendues.dart` (never `cartesMaquette[page]!` directly). Three maps, and the distinction matters:

- `ecartsAssumes` — "we decided to diverge, here is why".
- `ecartsATraiter` — "the screen does not do what the mockup asks, and it is not fixed". A test forbids a page from appearing in both; merging them would launder a defect into a decision. F0.55 emptied all but one entry; F0.80 emptied the last (`documents-administratifs`, moved to `ecartsAssumes` with its reason). The map stays as the place to park the next real gap.

⚠️ **A card the poste cannot compute is rendered with `'—'` and a legend saying why, never omitted and never `0`.** Eight of the 28 cards ported in F0.55 are dashes. `0` on "Attestations émises" would claim none was issued; the poste simply does not know. This is also why all four `gestion-paie` cards are dashes — summing base salaries would ignore bonuses and, worse, **exclude employer charges**.
- `ecartsPanneaux` — per tab-panel, keyed `page.html#panel`.

⚠️ **Never check the total for a page whose tabs live in one HTML file.** On `elevage-dashboard` the total was 11 vs 15, which read as "four missing"; per panel it was **−4, −3 and +3 on three different tabs**, nearly cancelling. `structure.py` emits `cartesParPanneau` for those pages.

⚠️ **A card is `border-l-4 border-l-<colour>`**, not bare `border-l-4` — `bons-commande.html` uses the latter for a field group, and counting it demanded an indicator that does not exist.

⚠️ `pumpWidget` reuses the state of a same-type widget: to leave a sub-page, tap the screen's own Retour button rather than calling the render helper again.

## Porting doctrine — enforced by `test/conformite_portage_test.dart`

⚠️⚠️ **These tests read the SOURCE CODE, and that is deliberate.** The gaps they lock are **invisible at runtime**: the screen renders, it is simply not the one the client validated. No render test catches them, nor does the analyzer. Each had already been committed across fourteen files before being spotted.

| Rule | Instead of |
|---|---|
| Layout decides on the **screen** width — `AgriBreakpoints`, which reads `MediaQuery` | `constraints.maxWidth > …` — the content area is ~980 px inside a 1280 px window, so it silently picks the wrong layout |
| `CarteKpi` for indicator cards | `Container(width: 4, color: …)` in a stretched Row — `border-l-4` **posts, it does not stretch**; it throws "BoxConstraints forces an infinite height" in a scrolling column (hit twice: F0.32, F0.39) |
| `ModaleAgri` / `ModaleConfirmation`, opened through `afficherModale` | `AlertDialog` (wrong margins, no ✕, no footer rule) or a bare `showDialog` (Material's `black54` scrim instead of the prototype's `bg-black/50`) |
| `AgriTypography.xs` | `fontSize: 12 / 12.5 / 13` — none of the three exists in the prototype |

Plus: **one implementation of `CarteKpi`, ever** (it lived in thirteen copies, two already divergent), and **every declared `_absorberX` must actually be called**.

Two more checks work from the other end, against fixtures extracted from the prototype:

- `fidelite_libelles_test.dart` (F0.42, hardened in F0.53) — every label of the page exists somewhere in the ported screen. It finds the words nobody thought to look for.
  - ⚠️⚠️ **It matches against STRING LITERALS only** (`chainesDe`). It used to match the whole source file, so a **comment** satisfied it — and the comments in question were the project's own "⚠️ this label is not ported because…" notes. The guard was passing on *explanations of absence*. `chainesDe` has its own 8 tests; do not weaken it.
  - **Two exemption lists.** `exemptions` is global — use it only for labels that genuinely appear everywhere (`ModaleAgri`'s buttons). Everything else goes in `exemptionsParPage`. ⚠️ Exempting a common word globally silently removes coverage elsewhere: exempting "Date" for one table cost **17 real checks on 14 other pages** before it was caught.
- `conformite_structure_test.dart` (F0.49) — the **ordered** sequence of `<th>` per table, which the vocabulary check cannot see: reordered or missing middle columns pass it word by word.

⚠️ A two-level `<thead>` (Balance Générale: three `colspan=2` groups over Débit/Crédit, plus two `rowspan=2` columns) has **8 real columns, not 11**. `colonnes_feuilles()` in `outils/structure.py` flattens it; do not re-concatenate the rows.

## RBAC — two levels, and a contradiction you must not resolve

`PermissionsPoste` transposes `RBAC_PAGE_MAP` from the prototype's `common.js` **verbatim**. Add a screen by mapping it to its prototype file; do not reinterpret the map.

- **Two levels, always.** The sidebar hides forbidden entries AND `GardeEcran` refuses on the screen itself. Menu hiding is not authorization — an unreachable screen reached anyway would be fully functional.
- **Never open on a forbidden screen.** The first accessible screen for the role is chosen at startup; a single default greets the cashier with a full-page refusal and reads as a broken app.
- ⚠️⚠️ **An unknown role is NOT restricted** — the prototype does exactly this (`if (allowedPages)`: no entry, no check), and behavioural fidelity requires it. But the CDC announces 7 roles where the map implements 4. **CLIENT ARBITRATION REQUIRED.** Resolving it here would decide a security question on the client's behalf.
- **Six screens are in the mockup but in none of the four lists** (`suivi-reproduction`, `parametres-elevage`, `saisie-depenses`, `gestion-stocks`, `achats-commandes`, `fournisseurs`): applied as-is, only `admin` reaches them. Documented per enum entry, each with its own arbitration note. Nothing is invented — the restriction follows from the map.
- The two off-mockup screens have their rule decided: **Synchronisation is open to every role** (reserving it would trap the cashier's sales on the machine), **Paramètres du poste is admin-only** (changing the server address cuts the farm off).

## Known contradictions — flag, do not silently resolve

Resolving one arbitrarily is a regression, not a cleanup.

- **RBAC role count**: 7 in the CDC, 6 in the `roles` enum, 5 in the mockup's permission matrix, 4 in `RBAC_PAGE_MAP`. The client screen shows what the **server applies** (4) and says so on screen.
- **Screen count** quoted as 94, 97 and 99 across documents.
- A single prototype file can carry two incompatible taxonomies between its own sections. Document the divergence, propose a reasoned choice, label it a prototype gap.

Demo widgets of the prototype are correctly **excluded**, not overlooked: the top-bar role switcher, `testerPopupAlertesStock`, `testerPopupProphylaxie`.

## The desktop window

The window is created **frameless** (`WS_POPUP`, `windows/runner/win32_window.cpp`) and maximised — so it has no system minimise/close buttons. `BarreSuperieure` renders them at the right edge, through the `agrierp/fenetre` MethodChannel. ⚠️ A channel failure must not crash the screen: in widget tests there is no native side.

⚠️ Maximisation happens **after** the window is shown, not in `main.cpp`: the window is created hidden, and the frame-size call used to run afterwards and drag it back to 1280×720.

## Poste settings — never hard-code them again

`deviceId` and the server address live in `app_settings` (Drift) and are read by `ParametresPoste` **before `runApp`** — the Dio client and the sync engine are built from them.

- **`deviceId` is drawn once and never regenerated.** It was the constant `'poste-dev'` in four places until F0.8 — every installation would have shared it, making two farm posts indistinguishable and every conflict unexplainable.
- **The server address is normalised on save** (trailing slash removed — it produces `//api/sync/pull`; missing scheme added — the HTTP client otherwise fails on an unhelpful error).
- The HTTP client is built at startup, so a changed address needs a restart — and the screen **says so**, otherwise it reads as a network failure.
- **One shared Dio client.** It carries the `Authorization` header once the session opens; a second client for sync would go out tokenless and get a 401 — all the more baffling because login itself succeeded.

## Flutter-specific traps already paid for

- **PDF : `ExportOfficiel.construire` DOIT recevoir `polices` (`chargerPolices()`).** La police par défaut du moteur PDF (Helvetica) n'a pas Unicode : « — » et « ’ » sortent en CARRÉ BARRÉ, sans erreur (un avertissement de journal seulement) — pied des trois structures, adresse de la ferme, tirets des valeurs inconnues. Roboto est embarquée (`assets/fonts/`, Apache 2.0). Corrigé au ticket F0.75 ; `test/liste_achats_detail_test.dart` lit les flux du PDF et compte les glyphes manquants.

- **`LIKE` on SQLite is case-insensitive for ASCII ONLY.** Resolving an entity by label (« **Œ**ufs de table » searched as `%œufs%`) works on MySQL and silently returns nothing on Drift. Compare on a label normalised in Dart.
- **"Duplicate keys found" stops the paint of the whole screen** — no analyzer warning, no compile error. Third occurrence on this project: two identical keys in one column. Give each entry its own key.
- **Never reintroduce `open.overrideFor(OperatingSystem.windows, …)`** — it has already broken a build; `NativeDatabase.createInBackground()` alone is enough.
- Drift 2.x: `&` is not defined on `Expression<bool>` (use `.and()`), and `DoUpdate.withExcluded` needs an `Insertable`, not the raw row.
- **A failed login recorded offline carries the timestamp of the ATTEMPT**, never of the synchronisation — otherwise a whole brute-force campaign appears in one second in the audit log. Failed logins are counted on `login.failed`, the **technical** action name: never make a security alert depend on a translation.
- **Widget tests: reset the view size**, it survives the test that set it, and the next screen renders in the previous one's window. A tab bar that scrolls horizontally needs `ensureVisible` — a tap outside the frame hits nothing **without failing**, and the next assertion blames the wrong culprit.
- **Missing data is `'—'`, never `0`.** A zero reads as a measurement ("nothing happened on the farm") where a dash reads as "this post does not know". Applies to opening balances, 24 h counters and monthly tables alike.

## Working rhythm

**One ticket = one session.** Announce the plan before writing code. Never batch-convert screens without intermediate verification.

Done means: `flutter analyze` clean, `flutter test` green, and the ticket appended to **both** copies of `README_SPRINT0.md` with its **real findings** — including what was *not* verified. Several entries carry an explicit reservation; that is a project practice, not a weakness.

**Write the test that would have caught the defect.** Every guardrail that exists locks a defect that emits no error at all.

Numeric data (accounting balances, stock totals, headcounts) is **never** verified by reading — write an independent recomputation and compare it against what the screen displays.
