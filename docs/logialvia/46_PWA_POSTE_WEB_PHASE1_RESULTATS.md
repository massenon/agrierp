# 46 — Poste web (PWA-2) : résultats de la phase 1 (PWA-2, PWA-2b, PWA-2c)

> **USAGE**
>
> - **Quand l'utiliser.** (1) Pour dire au client, chiffres à l'appui, ce que le poste compilé pour le navigateur fait et ne fait pas aujourd'hui. (2) Avant de construire la même chose pour LogiALVIA (étape « PWA » du guide, bloc 22 de `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md`) : ce fichier est la liste des pièges déjà payés et des preuves à rejouer.
> - **Ordre.** `44_ETUDE_FAISABILITE_PWA_FLUTTER_WEB.md` (étude) → `45_PHASE0_RESULTATS_PWA_FLUTTER_WEB.md` (preuve de phase 0) → **ce fichier** (phase 1, réalisée) → `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md` (§ 2.5 : déclencheurs au navigateur) et `31_TESTING_QA.md` (§ 3.2 et 3.3 : tests d'instructions SQL, e2e Chromium). Le plan reste `docs/PLAN_FINALISATION.md` (PWA-2, PWA-2b, PWA-2c).
> - **Entrées requises.** Le poste Flutter de LogiAgriERP (`agrierp_flutter/`, sections « PWA-2 », « PWA-2b », « PWA-2c » de son `CLAUDE.md`), le serveur Laravel (`agrierp_laravel/CLAUDE.md`, section « PWA-2 »), Node 22 + Playwright + Chromium pour les preuves.
> - **Sorties.** Un poste `flutter build web` servi sous `/poste/` par le MÊME serveur que l'API, avec son service worker propre, sa base IndexedDB, ses tests de non-régression Windows et ses e2e Chromium.
> - **Rien d'inventé.** Tout fait vient de `agrierp_flutter/CLAUDE.md`, `agrierp_laravel/CLAUDE.md`, `docs/PLAN_FINALISATION.md`, du fichier 45 et du code. Les mesures sont celles d'un bac à sable (Chromium sans fenêtre, rendu logiciel SwiftShader, `php -S`, SQLite) : elles montrent des ORDRES de grandeur et des RAPPORTS, pas des durées d'usage sur une tablette de la ferme.
> - **Règles dures de la phase 1 (inchangées de bout en bout).** Le poste Windows reste la référence (imports conditionnels, point de garde unique `PlateformePoste.navigateur`, les tests VM ne changent pas) ; absorbeurs STRICTS (jamais d'écrasement d'une ligne `pending` / `conflict`) ; aucun HTML authentifié ni donnée utilisateur dans le cache du service worker ; base IndexedDB SANS en-têtes COOP/COEP ; `app_database.g.dart` jamais à la main ; aucun secret.

## 1. Verdict de la phase 1

Le poste tourne dans Chromium comme application installable : démarrage, connexion, PIN, tirage complet, saisie hors ligne (fournisseur ET vente de caisse), rechargement de la page SANS réseau, reconnexion avec synchronisation automatique, sauvegarde complète en JSON, justificatifs, mise à jour contrôlée du service worker, deux vrais onglets concurrents.

**Ce qui n'est PAS prouvé** (à dire tel quel) : Safari / iPhone / iPad, Firefox, Edge, appareil réel (tactile, clavier virtuel, mémoire), Apache (essais sous `php -S` seulement : `curl -I /poste/sqlite3.wasm` à faire au déploiement), build `--wasm`, build Windows après les changements (pas de Windows ici : résolution de `drift_flutter` / `sqlcipher_flutter_libs` par CMake, SDK Dart ≥ 3.13 à confirmer), phase 2 (pilotes Stocks, Fournisseurs, Ventes & Devis en recette sur appareils réels) et phase 3 (autres modules).

## 2. Ce que la phase 1 a construit, par ticket

### 2.1 PWA-2 — le socle (08/11/2026, aucun palier Drift)

| Pièce | Rôle (source : `agrierp_flutter/CLAUDE.md`, « PWA-2 ») |
|---|---|
| `web/` | `index.html` STATIQUE (titre « LogiAgriERP », écran d'attente sans donnée), `manifest.json` (`scope` et `start_url` `/poste/`, standalone), `flutter_bootstrap.js` (NOTRE gabarit : enregistre `poste_sw.js`, jamais le service worker de Flutter qui se désinscrit), `poste_sw.js`, `sqlite3.wasm` (748 686 o) et `drift_worker.js` — VERSIONNÉS ; `outils/recuperer_wasm_web.sh` les met à jour après une montée de `drift` / `sqlite3` |
| `lib/core/database/ouverture_base*.dart` | `ouvrirConnexionPoste()` : natif = EXACTEMENT l'ancienne ouverture (`NativeDatabase.createInBackground`) ; web = `driftDatabase` (IndexedDB). `app_database.dart` n'importe plus `dart:io` ni `drift/native.dart` : ne JAMAIS les y remettre (c'est ce qui casse la compilation web : `dart:ffi`) |
| `lib/core/systeme/plateforme_poste.dart` | `PlateformePoste.navigateur` (= `kIsWeb`, forçable en test) : point UNIQUE des gardes ; `livreurNavigateur` (téléchargement, remplaçable en test) |
| `fichiers_poste*.dart`, `ouvreur_url_plateforme_*.dart` | `livrerFichier(nom, octets)` : natif = `Documents\LogiAgriERP\<nom>` (inchangé) ; web = téléchargement par blob ; sélecteur de fichier = des OCTETS, jamais un chemin |
| Serveur | `public/poste/` (ignoré par git), `.htaccess` : `AddType application/wasm .wasm`, `Cache-Control: no-cache` sur `/poste/`, `poste_sw.js` en `no-store` avec `Service-Worker-Allowed: /poste/`, **AUCUN COOP/COEP** (gardé par `PostePwa2Test`) |
| Construire | `agrierp_flutter/outils/construire_poste_web.sh` : `flutter build web --release --no-web-resources-cdn --base-href /poste/` (le drapeau CDN est OBLIGATOIRE : sans lui CanvasKit vient de gstatic.com), puis `outils/generer_sw_poste.py` (liste de précache + `VERSION` = SHA-256 de l'enveloppe), puis copie vers `agrierp_laravel/public/poste/` |

Service worker du poste (`poste_sw.js`, portée `/poste/`) : précache de l'ENVELOPPE statique seulement, « cache d'abord, réseau en repli », jamais `cache.put` sur une requête hors liste, jamais un non-GET ni un en-tête `Authorization`, jamais `/api/`, `/livewire/`, `/login`, `/logout`, `/sanctum/`, `/storage/` ; purge des caches d'autres versions ; pas de `skipWaiting` automatique. Les données vivent dans IndexedDB (drift), jamais dans le Cache API.

### 2.2 PWA-2b — synchronisation, sauvegarde, justificatifs, mise à jour (09/11/2026, aucun palier Drift)

1. **Cause de la synchronisation incrémentale lente, MESURÉE** (instrumentation temporaire, retirée) : un `await insert` PAR COMPTE du plan comptable (1 337 comptes, servis en entier à chaque tirage) = 73,3 s sur 95,6 s de page 1. Au navigateur chaque instruction attendue est un message vers le worker SQLite (≈ 55 ms ; en VM la même boucle coûte 114 ms : ce n'est pas un algorithme O(n²), c'est un coût par instruction). Correction : une rafale `batch`. **Avant / après (Chromium)** : plan comptable 73 s → 0,09 s ; page 1 incrémentale 95,6 s → ≈ 22 s (session neuve, modale ouverte, rendu logiciel) et 0,7 s en régime établi ; reconnexion → tout synchronisé **134 s → 1,5 s**. Le tirage initial (7 pages, 8 640 lignes) ≈ 6 s.
2. **Synchronisation automatique au navigateur** : ouverture, `online` (jamais retenu), retour de focus (anti-rebond de 30 s), jamais pendant une synchro en cours — voir `43_…` § 2.5.
3. **Tableau de bord qui se rafraîchit seul** à la fin d'un tirage (relecture silencieuse, web et natif).
4. **Sauvegarde complète au web** : JSON de toutes les tables (`schema_version`, blobs en `{"__b64"}`), `agrierp_<date>_complete.json`. Choix : `VACUUM INTO` écrit dans le système de fichiers IndexedDB du worker, illisible en octets par la page ; le vidage par `SELECT` est fiable mais N'EST PAS un `.sqlite`.
5. **Justificatifs au web** : octets (≤ 2 Mo ; le serveur accepte 5 Mo) dans IndexedDB `agrierp_justificatifs` ; colonne `receipt_local_path` = `navigateur:<clé>/<nom>` (schéma inchangé) ; envoyés par `POST /api/sync/receipts`.
6. **Vente de caisse hors ligne dans Chromium** (`outils/e2e_poste_web.mjs`) : une vente, stock 6 → 5, Caisse Principale +25 000, un mouvement de stock, un second « synchroniser » ne double rien ; mesures : démarrage 5,1 s, tirage 17,8 s, rechargement hors ligne 3,7 s, reconnexion → synchronisé 1,5 s.
7. **Garde-fous Windows** : `.metadata` garde l'entrée `windows` ; seuls `drift_flutter` et `web` ajoutés au `pubspec` ; `Accept: application/json` (`test/en_tete_accept_json_test.dart` joue le vrai adaptateur `dart:io`) ; `test/garde_imports_web_test.dart` (aucun `dart:html` / `dart:js_interop` / `package:web` hors `*_web.dart`, aucun `dart:io` / `dart:ffi` / `drift/native` dans un `_web` ni dans `app_database.dart`, chaque import conditionnel a ses deux fichiers).
8. **Mise à jour contrôlée du service worker** : nouvelle `VERSION` installée puis EN ATTENTE ; bandeau DOM « Nouvelle version disponible — Recharger / Plus tard » ; seul « Recharger » envoie `SKIP_WAITING` puis recharge ; réinterrogation à chaque retour de focus et toutes les heures. Preuve : `outils/e2e_poste_mise_a_jour.mjs`.

### 2.3 PWA-2c — regroupement des écritures, deux onglets, restauration, sondage (09/11/2026, aucun palier Drift)

**A. Regroupement des écritures des absorbeurs (mesuré par un test d'instructions SQL)** — `test/absorption_performance_test.dart` (voir `31_TESTING_QA.md` § 3.2).

| Cas | Avant | Après |
|---|---|---|
| Tirage incrémental de 68 tables à charge faible (charges vides) | 228 instructions | 134 |
| Huit tables à petite charge (8 lignes chacune : créances, prophylaxie, sujets, rations, relevés, revenus de bande, transformations, calendrier vétérinaire) | 224 | 156 |
| Neuf tables à petite charge (fiches, clients, avances, fournisseurs, courriers, documents, archives, entreprise, journal) | 209 | 164 |

Moyens : UNE transaction par page (les absorbeurs n'ouvrent plus de point de sauvegarde : −82 messages ; suppose qu'aucun absorbeur n'attrape l'erreur d'un autre) ; les douze marques de resynchronisation en une lecture `IN (...)` ; charge vide = rien à exécuter pour les fusions pures (⚠️ jamais pour un référentiel REMPLACÉ à chaque tirage : une liste vide y veut dire « plus rien ») ; lectures par `IN (...)` en tranches de 500 puis UNE rafale `batch` ; par table, ≈ 3 à 4 instructions au lieu d'une à trois PAR LIGNE. Sémantique stricte inchangée, prouvée par les tests de tirage existants et par `sync_reel_test` (serveur `php -S`, vrai tirage).

Chromium (instrumentation temporaire de chaque absorbeur, retirée) : sans le regroupement des fiches, la page 1 du tirage initial ne se terminait pas en plusieurs minutes (912 fiches × 3 instructions) ; après : fiches 0,46 s, absorption des 7 pages ≈ 11,4 s cumulées ; **reconnexion → synchronisé 1,0 à 1,5 s** (inchangé : le gain est sur le tirage initial et sur le nombre d'instructions). Huit tables lentes : Transformations 1,5 s → 0,09 s, Calendrier 0,77 s → 0,09 s, Créances 0,65–2,36 s → ≤ 0,1 s, Prophylaxie 0,46–1,64 s → ≤ 0,15 s, Rations 0,47–1,2 s → ≤ 0,17 s, Relevés 0,3–1,1 s → ≤ 0,16 s, Sujets 0,5–1,4 s → ≤ 0,15 s, Revenus de bande 0,3–1,0 s → ≤ 0,15 s ; tirage complet 26–33 s → 16–22 s. Neuf tables : Avances 0,30 s → ≤ 0,16 s, Fournisseurs 0,45 → ≤ 0,17, Courriers 0,43 → ≤ 0,15, Documents 0,38 → ≤ 0,16, Archives 0,40 → ≤ 0,17, Entreprise 0,37 → ≤ 0,16, Clients 0,32 → 0,06. **Reste le plus lent** : au premier tirage Fiches journalières ≈ 0,43 s et Journal ≈ 0,43 s (gros volumes) ; Modules, Rôles, Dépenses ≈ 0,25 à 0,34 s ; tout le reste ≤ 0,2 s. La mesure « avant » du tirage initial vient d'un essai jamais terminé (le HEAD d'avant n'a pas été rejoué sur cette machine).

**B. Deux VRAIS onglets** (`outils/e2e_poste_deux_onglets.mjs` : UN contexte Chromium à profil persistant, DEUX pages sur `/poste/`) : (i) drift choisit `WasmStorageImplementation.sharedIndexedDb` : les deux onglets partagent UN worker SQLite, donc UNE base ; B lit les 312 têtes tirées par A ; (ii) `online` émis dans les deux onglets au même instant : 2 requêtes de synchro, **aucun chevauchement**, verrou `agrierp-synchro` jamais tenu deux fois et vu EN ATTENTE par l'autre ; (iii) saisie de A visible dans B après rechargement, une ligne au serveur ; (iv) deux saisies simultanées (même table) : visibles, ni perdues ni doublées, au poste comme au serveur ; (v) mise à jour du service worker à deux onglets : bandeau dans les deux, aucun rechargé ; « Recharger » dans A active la version pour le navigateur entier ; B est PRÉVENU (le bandeau périmé de B est REMPLACÉ par « La version a changé dans un autre onglet — Recharger », jamais de rechargement forcé ; la première installation ne le déclenche pas) et ses données sont intactes. Décision : PAS d'« onglet maître » (le worker partagé sérialise les écritures, le verrou sérialise les synchronisations). Limite : Chromium seulement (Firefox / Safari retombent sur un worker dédié ou un autre stockage : à rejouer).

**C. Restauration d'une sauvegarde au web** (`RestaurationSauvegarde.restaurer`, bouton « Restaurer depuis un fichier » de l'onglet Sauvegardes ; décision DV-28 de `16_DECISIONS_VALIDEES.md`) : état sûr exigé (AUCUNE ligne `pending` / `conflict` : « Des saisies ne sont pas encore envoyées… Synchronisez d'abord ») ; contrôle STRICT avant toute écriture, refus TOTAL (JSON illisible, format étranger, `schema_version` absent ou PLUS RÉCENT que l'application, table ou colonne inconnue, ligne qui n'est pas un objet) ; UNE transaction (`defer_foreign_keys`), toutes les tables vidées puis remplies sauf l'identité de CE poste (`poste.identifiant`, `poste.adresse_serveur`) ; confirmation `ModaleRestauration` (mot « RESTAURER ») jouée APRÈS un contrôle sans écriture ; puis rechargement. Une sauvegarde d'un schéma plus ANCIEN est acceptée si toutes ses tables et colonnes sont connues (valeurs par défaut aux colonnes ajoutées depuis) ; sinon la transaction échoue, rien ne change. Tests : `test/restauration_sauvegarde_test.dart` (aller-retour, chaque refus, tout ou rien, modale) ; mutation prouvée : le contrôle « pending » retiré fait rougir 4 tests. Le natif garde son mécanisme (restauration installée au lancement).

**D. Sondage léger au retour en ligne** (`SyncEngine.serveurJoignable()`) et indicateur « Hors ligne / En attente (N) / Synchronisé » : voir `43_…` § 2.5.

**E. Vérifications finales de la phase 1** : `flutter analyze` propre ; suite Flutter complète `flutter test --concurrency=2` (4 276 verts, 18 sautés, 0 rouge à la dernière passe) ; filtre Laravel `Pwa|Sw|Poste` : 420 verts ; e2e Chromium `e2e_poste_web.mjs`, `e2e_poste_mise_a_jour.mjs`, `e2e_poste_deux_onglets.mjs` verts (sur build propre). Outils : `E2E_BASE_PRETE=<base sqlite semée dans le dossier temporaire>` (la graine de démonstration prend ≈ 30 s) et `E2E_DEBUG=1` (console du navigateur).

## 3. Leçons à reprendre pour LogiALVIA

1. **Le coût au navigateur est par INSTRUCTION, pas par ligne** : ≈ 55 ms l'aller-retour vers le worker SQLite (davantage quand le fil principal est saturé par le rendu logiciel). Écrire en `batch`, lire par `IN (...)` (tranches de 500), UNE transaction par page ; voir `30_DATABASE_ENGINEERING.md` § 7.4.
2. **Mesurer en nombre d'instructions, pas en durée** : la durée d'une VM ne montre pas le défaut (114 ms contre 73 s). Un `QueryInterceptor` compte ce qui atteint le moteur ; borne large + mutation (`31_TESTING_QA.md` § 3.2).
3. **IndexedDB, pas OPFS** : avec COOP/COEP, drift passe en OPFS (≈ 150 s au tirage contre ≈ 6 s) ; aucun de ces en-têtes, nulle part (fichier 45 § 7 ; garde `PostePwa2Test`).
4. **Un seul service worker, à portée étroite** : celui du poste (`/poste/`), jamais celui de Flutter (stub de 784 octets qui se désinscrit) ; aucune page authentifiée ni donnée dans le cache.
5. **Les clics à coordonnées fixes sont fragiles** (Flutter dessine dans un canvas) ; l'arbre de sémantique (`flt-semantics-placeholder`) sert à LIRE les textes ; l'unicité d'une ligne se prouve par COMPARAISON avec une ligne connue pour être unique, jamais par un compte absolu (l'arbre répète les libellés).
6. **Un défaut silencieux se lit dans la console** : la cause d'un échec de synchronisation automatique est écrite par `debugPrint`, jamais à l'écran (hors ligne n'est pas une erreur).

## 4. Limites et NON vérifié (à répéter)

Safari / iOS (critère d'arrêt n° 2 de l'étude 44 : jamais essayé), Firefox, Edge ; appareil réel et réseau mobile réel ; Apache ; durée de vie du stockage, éviction, quota ; build `--wasm` (échec connu avec `flutter_secure_storage_web` 1.2.1 ; passer à ^10 exige une revalidation Windows, NON faite) ; build Windows après ces changements ; un seul jeu de données (démonstration, cinq mois) sur SQLite, pas MySQL ; Chromium sans fenêtre n'émet pas `visibilitychange` (émis à la main dans l'e2e) ; boutons de fenêtre Windows visibles dans le navigateur, glisser-déposer (`SourceDepotNative`) et `exit(0)` de l'écran de panne non traités.

## 5. Textes de suivi déplacés du fichier 45 (aucun chiffre perdu)

Les trois sections ci-dessous (« Suite : PWA-2 », « Suite : PWA-2b », « Suite : PWA-2c ») figuraient en fin de `45_PHASE0_RESULTATS_PWA_FLUTTER_WEB.md`. Elles sont reprises ici telles quelles ; le fichier 45 reste la preuve de la PHASE 0 et renvoie ici.

### Suite : PWA-2 (phase 1, socle) — voir la section « PWA-2 » de `agrierp_flutter/CLAUDE.md`

**Verdict : le bloquant n°1 est LEVÉ. Rechargement de la page HORS LIGNE : OUI** (`context.setOffline(true)` + `reload`, puis navigateur fermé et rouvert sans réseau) — l'application se recharge depuis le service worker `poste_sw.js` (portée `/poste/`) et affiche ses données locales. Script : `agrierp_flutter/outils/e2e_poste_web.mjs` (Chromium headless, `deviceScaleFactor` 1, serveur `php -S` + SQLite temporaire + `DemoDataSeeder`, build servi sous `/poste/` par le MÊME serveur).

| Mesure (sandbox, rendu logiciel) | Résultat |
|---|---|
| Démarrage à froid (écran de connexion) | ≈ 5,0 s |
| Connexion + PIN + tirage complet (7 pages) | ≈ 19,4 s (dont 8 s d'attentes du script) ; effectif 312 affiché |
| Rechargement hors ligne (reload, verrou PIN compris) | ≈ 3,8 s |
| Réouverture du navigateur, en ligne / SANS réseau | ≈ 4,2 s / ≈ 4,3 s, session, PIN et données conservés |
| Service worker | portée `/poste/`, 42 fichiers précachés (28,3 Mo listés ; Chromium annonce 51,7 Mo de « caches », écart non élucidé), aucun `/api`, `/livewire`, `/login` dans le cache, un seul cache (purge des anciens) |
| IndexedDB | 2,6 Mo après le tirage, 4,7 Mo après une synchronisation incrémentale et une saisie |
| Saisie hors ligne puis reconnexion | fournisseur créé hors ligne (liste locale : 7), absent du serveur ; après « Synchroniser maintenant » : `POST /api/sync/push` 200, **une seule ligne** côté serveur, une synchro de plus ne la duplique pas |

**Points ouverts mesurés** : (1) la synchronisation incrémentale après reconnexion a duré **134 s** (2 pages `pull?since=` : la page 1 a été appliquée en ≈ 90 s, contre 6 s pour le tirage initial complet) — cause non élucidée (application de pages existantes en IndexedDB, fil principal ?) : à instruire en priorité en phase 1 ; (2) la synchronisation automatique n'a pas envoyé le fournisseur en 30 s (elle est sur minuterie de 5 min) : l'essai a utilisé le bouton ; (3) le tableau de bord affiché pendant le tirage ne se rafraîchit pas seul ; (4) la vente de caisse du poste n'a PAS été jouée ; (5) Safari/iPhone, appareil réel, Apache (essai sous `php -S` seulement) : non vérifiés. Captures : `docs/logialvia/img/pwa2/`.

### Suite : PWA-2b (phase 1, suite) — voir la section « PWA-2b » de `agrierp_flutter/CLAUDE.md`

Le point ouvert n°1 est ÉLUCIDÉ : les 134 s venaient d'un `await insert` par compte du plan comptable (1 337 lignes servies en entier à chaque tirage) — ≈ 55 ms par instruction au navigateur, 73 s sur 95,6 s de page 1 — plus une latence par instruction amplifiée par la saturation du fil principal (peinture logicielle). Corrigé par une rafale `batch` : reconnexion → synchronisé en **1,5 s** dans Chromium. Les points 2 (synchro automatique : `online`, focus), 3 (tableau de bord relu seul) et 4 (vente de caisse hors ligne : une vente, stock −1, trésorerie +25 000 côté serveur, rien de doublé) sont traités ; sauvegarde complète en JSON, justificatifs en IndexedDB, mise à jour contrôlée du service worker et verrou entre onglets sont faits. Non vérifiés : Safari / iOS, deux onglets réellement concurrents, build Windows.

### Suite : PWA-2c (fin de la phase 1) — voir la section « PWA-2c » de `agrierp_flutter/CLAUDE.md`

Les écritures des absorbeurs sont regroupées (tirage incrémental de 68 tables : 228 → 134 instructions ; une transaction par page ; fiches journalières, pointages, ventes, achats et journal en rafales `batch`) ; deux vrais onglets Chromium sont éprouvés (drift partage UN worker SQLite en `sharedIndexedDb`, verrou `navigator.locks`, saisies simultanées, mise à jour du service worker à deux onglets) ; la restauration de la sauvegarde JSON est permise au web dans un état sûr ; un sondage léger `/up` précède la synchronisation au retour en ligne. Reste : Safari / Firefox / Edge / appareil réel, build Windows, `--wasm`, phase 2.

Suite PWA-2c : les huit absorbeurs encore lents sont regroupés en rafales (224 → 156 instructions sur huit tables à petite charge ; 0,3–2,4 s → ≤ 0,17 s dans Chromium ; tirage complet 26–33 s → 20–22 s ; reconnexion → synchronisé 1,5 s). Reste 0,3–0,5 s sur Fiches, Clients, Avances, Fournisseurs, Courriers, Documents, Archives, Entreprise, Journal.

Suite 2 PWA-2c : les neuf dernières tables écrites ligne à ligne (Fiches, Clients, Avances, Fournisseurs, Courriers, Documents, Archives, Entreprise, Journal) sont regroupées (209 → 164 instructions ; 0,3–0,45 s → ≤ 0,17 s dans Chromium ; reconnexion → synchronisé 1,5 s). Reste ≈ 0,43 s au premier tirage pour Fiches et Journal (volumes), ≈ 0,3 s pour Modules, Rôles, Dépenses.
