# 40 — PWA, application utilisable hors ligne (LogiALVIA)

> **USAGE**
>
> - **Quand l'utiliser.** Quand le client de LogiALVIA confirme qu'il veut une application **dans le navigateur** (ordinateur, tablette, téléphone) qui continue de prendre des ventes et des fiches journalières quand la liaison tombe, puis se synchronise toute seule au retour du réseau. Ne PAS lancer ce prompt avant les « Entrées requises » ci-dessous : une PWA hors ligne n'est pas un chantier de départ, c'est une extension du socle.
> - **Ordre.** Après (1) le socle web Laravel + Livewire de LogiALVIA (`02_ARCHITECTURE_WEB_ET_STACK.md`), (2) l'appairage et la synchronisation du poste fonctionnels contre le vrai serveur (`43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`, étapes S0 à S5), (3) la décision écrite du client sur les questions de la section 8. Avant : lire cette page seule pour décider, jamais pour coder.
> - **Entrées requises.** Réponses aux questions de la section 8 ; `/api/sync/pull` et `/api/sync/push` de LogiALVIA verts (essai multipostes passé) ; liste des tables de caisse et de fiches journalières déjà synchronisables (UUID, `sync_status`) ; le guide `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` (blocs 15, 16 et 20, dont ce fichier est la version « prompt »).
> - **Sorties.** Une PWA installable ; une file d'envoi IndexedDB ; un service worker étroit ; un client JavaScript de caisse et de fiche ; des tests (mode avion simulé, Playwright) ; une extension de `PwaEtPolicesLocalesTest` ; un paragraphe « PWA » mis à jour dans le `CLAUDE.md` du web de LogiALVIA.
> - **Pièges de lecture.** Ce fichier **ne contredit pas** le guide (bloc 20) : il le détaille. Tout ce qui suit la section 1 est **À CONCEVOIR** : rien n'en est construit ni éprouvé, ni dans LogiAgriERP ni dans LogiALVIA.
> - **Voir aussi.** `01_MASTER_PROMPT.md`, `02_ARCHITECTURE_WEB_ET_STACK.md`, `03_DEVELOPMENT_STANDARDS.md`, `04_UI_UX_DESIGN_SYSTEM.md`, `31_TESTING_QA.md`, `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`, **`44_ETUDE_FAISABILITE_PWA_FLUTTER_WEB.md`, `45_PHASE0_RESULTATS_PWA_FLUTTER_WEB.md` et `46_PWA_POSTE_WEB_PHASE1_RESULTATS.md`** (la voie C, essayée puis réalisée dans LogiAgriERP).
> - **Mise à jour du 09/11/2026 (statut seulement).** La **voie C de la section 2** (poste Flutter compilé pour le navigateur, Drift sur IndexedDB ; appelée « voie B » dans le titre de l'étude 44) a été ÉTUDIÉE (44), PROUVÉE dans Chromium (45) puis RÉALISÉE en phase 1 dans LogiAgriERP (46) : poste web servi sous `/poste/`, rechargement hors ligne, saisie hors ligne (dont la vente de caisse), synchronisation à la reconnexion, deux onglets, restauration de sauvegarde. Les phrases « rien n'est construit ni éprouvé » de ce fichier valent pour la voie B (PWA JavaScript) et pour LogiALVIA ; elles ne valent plus pour la voie C dans LogiAgriERP. Limites de la voie C : Safari, Firefox, Edge, appareil réel, Apache et build Windows non vérifiés (46, § 4).

---

## 1. La vérité sur LogiAgriERP (à rappeler au client, factuellement)

Le client croyait que LogiAgriERP « fait une PWA qui travaille hors connexion puis se synchronise ». **C'est faux.** Vérifié dans le dépôt le 07/11/2026 :

| Constat | Preuve (chemin réel) |
|---|---|
| Le PWA d'LogiAgriERP est **installable**, rien de plus | `agrierp_laravel/public/manifest.webmanifest` (`display: standalone`, `start_url: /dashboard`, 4 icônes, 3 raccourcis) ; `agrierp_laravel/public/offline.html` ; `agrierp_laravel/resources/views/components/pwa-install.blade.php` |
| Le service worker est **volontairement étroit**, 3 règles de sûreté écrites en tête du fichier | `agrierp_laravel/public/sw.js` (`VERSION = 'agrierp-v5'`) : (1) seules les requêtes `GET` sont interceptées ; (2) aucune page HTML authentifiée n'est stockée (les navigations passent par le réseau et ne retombent sur `offline.html` qu'en cas d'échec réel) ; (3) seuls les fichiers statiques (`/build/`, `/assets/fonts/`, `/assets/icons/`, `/assets/images/`) sont mis en cache ; exclus : `/livewire/`, `/api/`, `/login`, `/logout`, `/reset-password`, `/broadcasting/`, `/storage/` |
| La position est **écrite** | `agrierp_laravel/CLAUDE.md`, section « PWA » : « This PWA does not make LogiAgriERP work offline, and that is not a gap : disconnected work is the dedicated client's job, via `/api/sync/*`. A browser cache pretending to take sales offline would create two sources of truth. » |
| Aucune brique hors ligne dans le navigateur | aucune occurrence de `indexedDB`, `SyncManager`, `registration.sync` dans `agrierp_laravel/resources` ni `agrierp_laravel/public` ; seul `navigator.serviceWorker.register('/sw.js')` dans les deux layouts |
| Garde-fou | `agrierp_laravel/tests/Feature/PwaEtPolicesLocalesTest.php` (11 tests : manifeste, icônes, fichiers précachés existants, `sw.js` ignore tout sauf `GET` et exclut `/livewire/`, fenêtre d'installation en bas à gauche, polices locales). ⚠️ La règle « aucun HTML authentifié » est dans le code de `sw.js` mais n'est pas assertée mot pour mot par ce test : à corriger dans LogiALVIA. |
| Le travail hors ligne d'LogiAgriERP = le **poste Windows** | `agrierp_flutter/` (Drift/SQLite, moteur `agrierp_flutter/lib/core/sync/sync_engine.dart`) ; `agrierp_flutter/pubspec.yaml` ne déclare aucune cible web |

**Phrase à dire au client :** « LogiAgriERP vous permet d'installer le site comme une application et affiche une page d'attente si le réseau tombe ; il ne permet PAS de vendre sans réseau dans le navigateur. Pour vendre sans réseau, il a un logiciel Windows séparé. Pour LogiALVIA, vous voulez mieux : voici ce que ça coûte et comment le faire sans créer deux vérités. »

### 1.1 Le refus d'origine, et comment le lever

LogiAgriERP a refusé le hors ligne navigateur pour cinq raisons (guide bloc 20). Pour chacune, la parade de LogiALVIA :

| Raison du refus | Comment la lever sans recréer deux sources de vérité |
|---|---|
| 1. **Deux sources de vérité** (règles de stock, de numérotation, de conflit à tenir deux fois ; `docs/DOCTRINE_PORTAGE.md` : on ne redérive jamais une règle côté client) | La PWA n'a **aucun moteur métier** : elle écrit des **FAITS** (une vente survenue, une fiche saisie) dans une file, avec la **même enveloppe JSON que le poste**, vers les **mêmes** `/api/sync/pull|push`. Le serveur rejoue chaque fait par **son point de passage unique** (le même code que l'écran web). Pas de stock, de numéro ni de comptabilité calculés dans le navigateur. Les rares calculs d'affichage (total d'une vente) sont dans UN module JavaScript prouvé égal au PHP par un test de parité exécuté (voir 5.4). |
| 2. **HTML authentifié en cache** (un cache de navigateur n'est pas cloisonné par utilisateur) | Règle 2 de `sw.js` **conservée mot pour mot** et **assertée** par un test (section 4). La coque hors ligne est une page **statique sans donnée** ; les données vivent en IndexedDB, chiffrées, et se purgent à la déconnexion. |
| 3. **Session partagée sur un poste commun** (caisse = comptoir partagé) | Une seule session par profil de navigateur ; verrou/PIN ; purge à la déconnexion ; refus de se déconnecter avec des saisies non envoyées sans choix explicite. Si la caisse est partagée entre plusieurs personnes sur le même appareil, **ne pas faire de PWA** : choisir le poste Windows. |
| 4. **Livewire** pilote tout par des `POST` qui supposent le serveur | La saisie hors ligne n'utilise **pas** Livewire : c'est un petit client JavaScript dédié (écran de caisse réduit, fiche réduite), servi à côté. Livewire reste intact en ligne. |
| 5. Le besoin hors ligne était déjà couvert | À réévaluer avec le client (section 8) : la PWA ne se justifie que pour des appareils où le poste Windows ne va pas (tablette, téléphone, ordinateur d'un autre lieu). |

---

## 2. Comparaison honnête des voies et recommandation

| | **A. Poste Windows existant** (Flutter + Drift/SQLite) | **B. PWA JavaScript** (IndexedDB + service worker) | **C. Flutter Web (ou Windows) + Drift WASM** |
|---|---|---|---|
| Ce que c'est pour LogiALVIA | `logialvia_app/` tel quel, auquel on ajoute appairage + synchronisation (blocs 15, 16) | Un second client, écrit en JavaScript, à côté de Livewire | Le même code Flutter recompilé pour le navigateur (`logialvia_app/web/` existe, mais est le gabarit Flutter) |
| Hors ligne durable | **Oui, solide** (fichier SQLite sur disque, jamais purgé par un navigateur) | **Moyen** : IndexedDB peut être purgé par le navigateur (site peu visité, pression de stockage, mode privé) ; `navigator.storage.persist()` atténue sans garantir | **Moyen** : Drift WASM stocke dans OPFS ou IndexedDB selon le navigateur ; mêmes risques de purge |
| Coût | **Déjà payé** (moins la synchro) | **XL** (> 10 jours après le socle) : client de caisse et de fiche, file, Background Sync + replis, chiffrement, purge, tests multi-navigateurs | **L à XL** et **incertain** : voir ci-dessous |
| Réutilisation | tout | le protocole seulement | protocole + moteur + écrans |
| Parité avec le web (doctrine : web = maître) | déjà prouvée par garde-fous | à prouver à la main pour un second client | héritée du poste, mais ajoute une **troisième** interface (Blade, Flutter Windows, Flutter Web) |
| Installation | installateur Windows | aucune (ajout à l'écran d'accueil) | aucune |
| iPhone/iPad | non | oui, avec limites (5.6) | oui, mêmes limites de stockage |
| Risque principal | un seul PC par poste | perte de saisies non envoyées ; parité à tenir | compatibilité du code actuel avec le web |

**Points factuels sur l'état de `logialvia_app/` (relus) pour la voie C** : base Drift native (`logialvia_app/lib/core/database/app_database.dart`, paquets `sqlite3_flutter_libs` et `sqlite3`, voir `logialvia_app/pubspec.yaml`) ; cinq fichiers importent `dart:io` (`app_database.dart`, `reprise_dossier_precedent.dart`, `service_sauvegarde.dart`, `service_restauration.dart`, `onglet_sauvegardes.dart`), qu'il faudrait isoler pour une compilation web ; `path_provider` et `flutter_secure_storage` sont des dépendances (leur comportement web est différent : stockage navigateur). **Aucune compilation web n'a été essayée** : ne rien promettre. Les contraintes de Drift sur le web (binaire `sqlite3.wasm`, worker, certaines options exigeant des en-têtes `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy`) sont à relire dans la documentation de Drift de la version retenue AVANT tout engagement : c'est une vérification à faire, pas un fait acquis ici.

### Recommandation

1. **Par défaut : garder le poste Windows comme client hors ligne** (c'est ce qu'LogiAgriERP fait et prouve), et faire de la PWA un client **« consultation + saisie simple EN LIGNE »**, avec le service worker étroit d'LogiAgriERP (statique seulement, page d'attente).
2. **Si le client veut vraiment le hors ligne dans le navigateur** (tablette ou téléphone en boutique, ordinateur sans installation) : **voie B, périmètre minimal** (section 3), après les réponses de la section 8. C'est la voie la plus chère mais la seule qui n'impose pas de recompiler tout LogiALVIA.
3. **Voie C : seulement après un essai de compilation web de `logialvia_app/`** (une demi-journée, jetable) et un essai Drift WASM sur les navigateurs du client. Sans cet essai : non.
4. **Jamais les deux B et C.** Et si le besoin est « quelques ventes quand le réseau tombe » : la caisse du poste Windows suffit.

---

## 3. Périmètre minimal (le seul raisonnable)

**Écrit hors ligne (faits) :**
- **Ventes de caisse** : panier, quantités, remise, mode de paiement, client existant ou « client de passage » ; chaque vente reçoit un **UUID côté client** (`crypto.randomUUID()`) et un **numéro de reçu PROVISOIRE** (`PROV-<8 premiers caractères de l'UUID>`), jamais définitif.
- **Fiches journalières d'élevage** (effectif calculé, mortalité, provende, production) — selon les tables et règles de `20_MODULES_*` et `15_REGLES_METIER.md` ; le client n'en saisit que les entrées, le serveur calcule les dérivés.

**Lu hors ligne (copie réduite, tirée à la connexion) :** produits vendables avec prix, clients, modes de paiement, bandes vivantes et catégories nécessaires à la fiche, barèmes de ration (lecture). Rien d'autre.

**Choix « facture simple / normalisée » :** la PWA écrit le choix et les champs (type, IFU, nom, AIB) dans la vente, comme le poste ; **la transmission MeCeF part à la synchronisation, par le serveur** (`41_MECEF_EMECEF.md`). Hors ligne : « Facture normalisée demandée — en attente », jamais de QR.

**Ce qu'on NE fait PAS hors ligne :** comptabilité et écritures manuelles, clôtures et exercices, paie, gestion des utilisateurs et des rôles, modification du plan comptable, des barèmes ou des référentiels, remise à zéro, sauvegardes, normalisation e-MECeF, avoirs sur une facture normalisée, rapports qui dépendent de données non tirées, « marquer lue / supprimer » une notification (la cloche est une copie tirée du serveur : ces gestes exigent le réseau, comme au poste).

---

## 4. PROMPT — Concevoir et construire la PWA hors ligne de LogiALVIA

~~~~text
RÔLE
Tu es l'ingénieur front-end/PWA et l'ingénieur de synchronisation de LogiALVIA (web Laravel 12 + Livewire 3, mêmes conventions que LogiAgriERP). Tu construis un client hors ligne dans le navigateur qui parle le MÊME protocole de synchronisation que le poste Windows, sans créer de seconde source de vérité. Tout en français (prose, libellés, commentaires, noms de tests, messages de commit). Ne commite et ne pousse que sur demande expresse.

CONTEXTE (rien à inventer)
- Lis d'abord : le CLAUDE.md de LogiALVIA (web), docs/DOCTRINE_PORTAGE.md (équivalent), docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md d'LogiAgriERP (/home/user/agrierp/docs/), et le guide /home/user/agrierp/docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md blocs 15, 16 et 20.
- Référence LogiAgriERP (lecture seule) : /home/user/agrierp/agrierp_laravel/public/sw.js, public/manifest.webmanifest, public/offline.html, resources/views/components/pwa-install.blade.php, tests/Feature/PwaEtPolicesLocalesTest.php ; protocole : app/Http/Controllers/Api/SyncController.php (pull, push), routes/api.php ; moteur du poste : /home/user/agrierp/agrierp_flutter/lib/core/sync/sync_engine.dart et synchronisation_automatique.dart ; verrou : agrierp_flutter/lib/core/auth/verrou_local.dart ; essai multipostes : agrierp_laravel/tests/Feature/SyncEssaiMultipostesTest.php.
- Décisions déjà prises par le client (à recopier en tête de ton CLAUDE.md « PWA », avec leurs dates) : appareils visés = <À REMPLIR, section 8>, durée maximale hors ligne = <À REMPLIR>, volumes = <À REMPLIR>.
- Si une de ces réponses manque : ARRÊTE-TOI et pose la question. Ne choisis pas.

TÂCHES (dans l'ordre ; une tâche = un commit ; chaque tâche finit vert avant la suivante)

T1 — Décision écrite. Crée docs/PWA_DECISION.md dans le web : voie retenue (B), périmètre minimal (ventes de caisse, fiches journalières, lecture de référentiels réduits), interdits hors ligne, limite de durée, appareils. Aucune ligne de code avant.

T2 — Service worker (public/sw.js), reprise du service worker d'LogiAgriERP et SEULEMENT élargi comme suit :
 a) Garde les trois règles de sûreté en tête de fichier, mot pour mot : (1) seules les requêtes GET sont interceptées (`if (request.method !== 'GET') return;`) ; (2) aucune page HTML authentifiée n'est JAMAIS stockée : les navigations passent par le réseau et ne retombent sur /offline.html qu'en échec réel ; (3) seuls des fichiers statiques sont mis en cache.
 b) Stratégies de cache PRÉCISES, une par famille d'URL :
    - /build/* (fichiers empreints) et /assets/fonts|icons|images/* : cache d'abord, mise à jour au changement de VERSION ;
    - /offline.html, /manifest.webmanifest et la COQUE HORS LIGNE (nouvelle page statique /caisse-hors-ligne.html et son JavaScript, sans aucune donnée métier, sans cookie, sans jeton) : précachées à l'installation ;
    - navigations (mode `navigate`) : RÉSEAU D'ABORD, repli sur /offline.html ; exception : la route de la coque /caisse-hors-ligne.html se sert du cache (elle est statique) ;
    - JAMAIS en cache, jamais interceptés : /livewire/, /api/, /login, /logout, /reset-password, /broadcasting/, /storage/ et toute requête avec en-tête Authorization ;
    - aucune stratégie « stale-while-revalidate » sur du HTML ni sur du JSON.
 c) Versionnage : constante VERSION incrémentée à CHAQUE déploiement qui change un fichier mis en cache ; `activate` supprime tous les caches dont le nom ne commence pas par la VERSION courante ; `skipWaiting` + `clients.claim` seulement si la coque tolère le changement de version en cours de saisie, sinon message « Mise à jour disponible » (voir T7).
 d) Purge à la déconnexion : le service worker écoute un message `{type:'PURGER'}` et supprime TOUS ses caches ; la page de déconnexion l'envoie (voir T6).
 e) Background Sync : enregistre l'étiquette `sync-file-envoi` à chaque ajout dans la file (`registration.sync.register`). À l'événement `sync`, le service worker NE fait PAS lui-même l'envoi (il n'a ni la clé de chiffrement ni le jeton) : il réveille un client ouvert par `postMessage({type:'SYNCHRONISER'})`, ou, s'aucun client n'est ouvert, ne fait rien (le jeton est chiffré par un secret que seul l'utilisateur détient ; l'envoi attendra la prochaine ouverture). Repli OBLIGATOIRE quand Background Sync n'existe pas (Safari, iOS, Firefox) : envoi déclenché par l'événement `online`, par le retour au premier plan (`visibilitychange`), par une minuterie (5 minutes par défaut, réglable) et par le bouton « Synchroniser maintenant ».
 
T3 — Stockage local (IndexedDB, jamais localStorage ni cache HTTP pour des données).
 Nom de base `logialvia_hors_ligne`, schéma versionné (`DB_VERSION` entier) avec migration à chaque version ; refus d'ouvrir une base d'une version plus récente que l'application, et refus d'ENVOYER une file écrite par une version incompatible (message français).
 Magasins : `file_envoi` (clé `id` = UUID, champs : `table`, `payload` chiffré, `sync_status` ∈ pending|synced|conflict, `motif` français éventuel, `cree_le`, `tentatives`), `referentiels` (copie réduite chiffrée, avec `tire_le`), `meta` (curseur `server_time`, `data_reset_at`, `device_id`, `tables_servies`, dernier envoi, dernière réception).
 Demande `navigator.storage.persist()` à l'installation ET à la première saisie ; affiche le résultat (accordé ou non) dans l'état de synchronisation. Interdit : prétendre que « c'est sauvegardé » ; le texte dit « enregistré sur cet appareil, pas encore envoyé ».
 Compteur : nombre de saisies `pending` + `conflict`, toujours visible (voir T8).

T4 — Appairage de l'appareil (même mécanisme que le poste, bloc 15). L'appareil est un POSTE :
 - il se connecte par POST /api/auth/login {identifiant, password, device_name} avec device_name = « navigateur-<UUID tiré UNE fois> » (jamais le nom du navigateur) ;
 - le jeton Sanctum (90 jours) est gardé CHIFFRÉ en IndexedDB (voir T5) ; le mot de passe n'est jamais conservé, jamais journalisé ; jamais de jeton en clair dans localStorage/sessionStorage ;
 - le `device_id` envoyé à /api/sync/push est le nom du jeton courant (le serveur refuse sinon : 403) ;
 - une réponse 401/403 SUSPEND la synchronisation automatique (les saisies pending RESTENT, « Synchroniser maintenant » reste possible et dit pourquoi) ; l'administrateur voit et révoque l'appareil dans l'onglet « Postes appairés » (aucune modification serveur : un appareil navigateur est un poste de plus).
 - première connexion : EN LIGNE obligatoirement (message clair hors ligne).

T5 — Chiffrement au repos, verrou et PIN.
 - Clé AES-GCM dérivée par PBKDF2 (WebCrypto, 600 000 itérations ou plus, sel aléatoire stocké) d'un PIN de 4 à 6 chiffres choisi à l'appairage ; la clé n'est JAMAIS stockée, elle vit en mémoire de l'onglet ; chaque enregistrement chiffré porte son propre IV.
 - Écran de verrou à chaque ouverture et après inactivité (textes et durées COMMUNS au web et au poste : docs/DOCTRINE_PORTAGE.md §5.6 — « Application verrouillée », « DÉVERROUILLER », Jamais / 1 / 5 / 15 / 30 minutes, défaut 5) ; 10 échecs = effacement de la clé et reconnexion EN LIGNE exigée (les saisies chiffrées non envoyées deviennent illisibles : l'écran le DIT avant le 10e essai).
 - Limite à dire à l'écran et dans le manuel : un PIN de 4 à 6 chiffres résiste mal à une attaque hors ligne sur une base copiée ; c'est une protection contre le curieux, pas contre un attaquant équipé.
 - Une seule session par profil de navigateur : deux onglets = un seul « maître » (verrou via `navigator.locks` ou BroadcastChannel) ; l'autre onglet est en lecture seule avec le message « Cet appareil est déjà ouvert dans un autre onglet ».

T6 — Déconnexion = purge.
 Déconnexion : (1) si des saisies sont pending/conflict, REFUSE tant que l'utilisateur n'a pas choisi explicitement « Envoyer d'abord » (synchronise, puis se déconnecte) ou « Abandonner ces N saisies » (confirmation à saisie du chiffre N) ; (2) puis supprime la base IndexedDB, le jeton, la clé, envoie `PURGER` au service worker, vide les caches, appelle POST /api/auth/logout et la déconnexion web.

T7 — Mise à jour de l'application sans perte.
 Nouvelle version du service worker : bannière « Mise à jour disponible — enregistrer puis recharger » ; jamais de rechargement forcé pendant une saisie ; si DB_VERSION change : migration avant toute lecture ; si la migration échoue : la file n'est PAS supprimée, l'écran propose « Exporter les saisies non envoyées » (fichier JSON chiffré) et prévient l'administrateur.

T8 — Indicateur d'état (barre du haut, même bouton « Synchroniser » que le poste, bloc 17 du guide) : trois états, jamais deux couleurs pour le même sens :
 « Hors ligne » (gris, ce n'est pas une erreur) · « N en attente d'envoi » (ambre) · « Synchronisé » avec l'heure du SERVEUR (`server_time` du dernier tirage, jamais l'horloge de l'appareil) · « N refusés — voir le détail » (rouge, avec les motifs français du serveur, geste « Remettre en file » / « Abandonner »). Libellés copiés de la modale du poste (agrierp_flutter/lib/core/sync/modale_synchronisation.dart : « En attente d'envoi », « Refusés par le serveur », « Dernière synchronisation réussie », « Dernière réception », « Dernier envoi », « Synchroniser maintenant »). Toasts : « Synchronisation terminée : N reçu(s), N envoyé(s). » ; « Serveur injoignable — les saisies restent sur cet appareil et partiront à la prochaine synchronisation. »

T9 — Protocole de synchronisation (le MÊME que le poste ; interdiction d'en inventer un second).
 - Ordre : TIRER d'abord (GET /api/sync/pull?since=…&page=…, pagination par `page` et `curseur_page`, curseur = `server_time` rendu par le SERVEUR, n'avance qu'à la DERNIÈRE page, jamais l'horloge de l'appareil), PUIS ENVOYER (POST /api/sync/push). Jamais deux synchronisations en même temps (verrou `navigator.locks`).
 - `tables_servies` : si une table s'ajoute, repartir d'un tirage complet (sans `since`).
 - Absorption stricte : une page tirée s'écrit en UNE transaction IndexedDB ; une ligne incohérente est REFUSÉE (message), jamais lissée ; une copie de référentiel n'écrase jamais une saisie pending/conflict.
 - Envoi : lots de taille limitée (le mandataire peut répondre 413 : réduire le lot), tables dans l'ordre des dépendances, UUID du client = clé d'idempotence : renvoyer une vente que le serveur connaît n'est PAS une erreur ; marquer `synced` SEULEMENT après l'accusé ; un refus devient `conflict` avec son motif français ; une réponse perdue après traitement est un cas normal (on renvoie, le serveur ignore).
 - Marque de remise à zéro : chaque envoi porte `data_reset_at` connu ; un 409 purge les saisies d'avant la remise à zéro et le dit.
 - Conflits par nature de donnée (aucune règle propre au navigateur) : référentiels = le serveur gagne ; fiche journalière = dernier écrivain par UUID ; vente = jamais fusionnée, chaque vente est un fait ; stock = le serveur rejoue ; numéros de pièces = attribués par le serveur (le numéro provisoire est remplacé au tirage suivant ; l'écran garde le lien UUID ↔ numéro définitif).
 - Réessais sur échec réseau ou 5xx : 30 s, 2 min, 5 min, 15 min, 1 h ; un refus 4xx n'est PAS réessayé ; 401/403 suspend.
 - Cadences serveur à respecter (agrierp_laravel/routes/api.php) : pull 120/min, push 30/min (même clé pour tous les appareils d'un compte) ; ne jamais interroger plus souvent.
 - Reconnexion : événement `online` → synchronisation automatique (tirage puis envoi) après 2 s de réseau stable (anti-rebond).

T10 — Interface hors ligne : coque statique + client JavaScript de caisse et de fiche réduites (pas Livewire). Chaque écran copie la structure et les libellés de la vue Blade correspondante (la vue Blade est le maître) ; un test lit la vue Blade et compare les libellés (modèle : agrierp_flutter/test/email_smtp_blade_test.dart).

T11 — Manifeste et installabilité : reprendre public/manifest.webmanifest d'LogiAgriERP (display standalone, start_url, scope, theme_color, icônes 192/512 `any` + `maskable`, raccourcis « Enregistrer une vente » et « Fiches d'élevage ») ; type MIME `application/manifest+json` servi (AddType dans public/.htaccess : sans cela le navigateur l'ignore EN SILENCE) ; `sw.js` en `no-cache` ; icônes dérivées du logo/favicon OFFICIEL de LogiALVIA ; invitation d'installation en BAS À GAUCHE (le bas droit est pris par les toasts, z-index 200).

T12 — Tests (section 6) puis documentation : section « PWA » du CLAUDE.md web, paragraphe « Limites connues » (sections 5.6 et 7), mise à jour du manuel.

CONTRAINTES (à ne jamais assouplir)
1. Aucun HTML authentifié dans un cache, jamais. Aucun POST intercepté, jamais. /api/, /livewire/, /storage/ jamais en cache.
2. Aucune règle métier réécrite : le navigateur écrit des FAITS ; le serveur décide, numérote, écrit. Les seuls calculs côté navigateur (total de ligne, remise, total de vente) vivent dans UN module (`resources/js/hors-ligne/calculs-caisse.js`) prouvé égal au PHP par un test de parité EXÉCUTÉ (voir 5.4).
3. Aucun jeton, mot de passe, PIN ni clé en clair dans localStorage, sessionStorage, cache, journal, URL ou message d'erreur.
4. Un seul protocole : /api/sync/pull|push. Aucune route serveur nouvelle pour la PWA sans décision écrite du client.
5. Aucune dépendance externe chargée à l'exécution (polices et scripts locaux, comme LogiAgriERP) ; versions de bibliothèques figées.
6. Les montants sont des entiers FCFA ; les quantités décimales sont des chaînes ou des entiers en millièmes, jamais des flottants binaires cumulés.
7. Hors ligne n'est jamais présenté comme une erreur rouge.

INTERDITS
- Étendre le périmètre (comptabilité, clôtures, paie, utilisateurs, plan comptable, MeCeF en direct) sans nouvelle décision écrite.
- Mettre une page Livewire ou un JSON authentifié en cache « pour aller plus vite ».
- Utiliser `localStorage` pour la file ou le jeton.
- Compter sur Background Sync seul. Croire qu'IndexedDB est durable.
- Écrire un second protocole, un second format de vente, un second numéro définitif.
- Affaiblir PwaEtPolicesLocalesTest : on l'étend.
- Faire un `pkill`, commiter ou pousser sans demande.

CRITÈRES D'ACCEPTATION (chacun vérifiable)
A1. `sw.js` : un test lit le fichier et prouve la présence des trois règles de sûreté ET l'exclusion des sept chemins ; un test d'exécution (Playwright) prouve qu'après déconnexion aucun cache ne contient de réponse HTML d'une page protégée (parcours de `caches.keys()` → `cache.keys()`).
A2. Mode avion : en ligne, tirage initial OK ; réseau coupé (`context.setOffline(true)`) ; 3 ventes + 1 fiche saisies ; compteur « 4 en attente d'envoi » ; réseau rétabli ; en moins de 30 s l'état passe à « Synchronisé », le serveur contient exactement 3 ventes et 1 fiche.
A3. Idempotence : la même file envoyée deux fois (réponse du premier envoi bloquée avant d'arriver) donne UNE vente côté serveur par UUID, et la file finit `synced`.
A4. Refus : une vente refusée par le serveur (ex. produit archivé) devient `conflict` avec le motif français, visible, relançable ou abandonnable ; jamais perdue en silence.
A5. 401 : jeton révoqué par l'administrateur → synchronisation automatique suspendue, saisies conservées, message clair ; réappairage → reprise.
A6. Déconnexion avec saisies pending : refusée sans choix explicite ; après « Abandonner » : IndexedDB, caches, jeton et clé effacés (vérifié par Playwright).
A7. Stockage purgé par le navigateur (simulation : suppression de la base pendant que l'application est fermée) : au rouvrir, l'application le DIT (« Les saisies non envoyées de cet appareil ont disparu : N ventes perdues possibles ») au lieu de repartir sans rien dire.
A8. Deux onglets : un seul écrit ; l'autre est en lecture seule avec son message.
A9. Version : un cache d'une ancienne VERSION est purgé à l'activation ; une file d'un `DB_VERSION` plus ancien migre sans perte ; une file d'un `DB_VERSION` plus récent est refusée avec message.
A10. Parité : `tests/Js/calculs-caisse.test.mjs` (même grille de cas que le PHP) rouge si le JavaScript et le PHP divergent.
A11. `PwaEtPolicesLocalesTest` étendu, jamais affaibli ; suite Feature verte ; tout est en français.
A12. Safari/iOS (si visé) : essai manuel documenté — pas de Background Sync, repli par `online` + premier plan vérifiés ; limites de stockage notées.

PIÈGES DÉJÀ PAYÉS (par LogiAgriERP, à connaître)
- manifeste servi en `text/plain` par Apache → application non installable sans aucune erreur visible (`AddType` dans .htaccess).
- service worker changé sans changer VERSION → les postes gardent l'ancien fichier sur disque.
- cache HTML d'un tableau de bord réapparu après déconnexion sur un poste partagé.
- POST Livewire interceptés → formulaires cassés.
- curseur lu à l'horloge de l'appareil ou à l'heure murale du serveur (au lieu de `server_time` UTC) → trous dans le tirage.
- une table oubliée dans la liste « à envoyer » : elle ne part jamais, sans erreur (garde : compteur_attente_test.dart ; à reproduire : la liste des magasins envoyés prouvée égale à celle du compteur).
- marquer `synced` à l'envoi au lieu de l'accusé.
- un envoi trop gros pour le mandataire (413).

RAPPORT FINAL attendu : liste des fichiers créés/modifiés, résultats des tests (nombre vert/rouge/sauté avec raison), les écarts assumés, ce qui n'a PAS été essayé (navigateurs non testés), les questions restées ouvertes.
~~~~

---

## 5. Détails de conception (référence pour le prompt)

### 5.1 Pourquoi pas de cache HTTP pour les données
Le cache d'un navigateur n'est pas cloisonné par utilisateur et ne sait pas expirer à la déconnexion. Les données vont en IndexedDB, chiffrées, sous la clé de l'utilisateur. Le service worker ne voit **jamais** de donnée métier.

### 5.2 La file d'envoi, enregistrement type (illustration, le schéma exact vient des tables de LogiALVIA)
`{ id: <UUID>, table: 'sales', payload: <chiffré>, sync_status: 'pending', cree_le: <instant de SAISIE, ISO 8601>, tentatives: 0 }`. Les colonnes communes sont celles du poste : `id` (UUID), `device_id`, `sync_status`, `updated_at` (instant de saisie). Les tables d'envoi, leur ordre et leur droit d'écriture sont ceux du tableau S0 de `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`.

### 5.3 Reconnexion
`online` n'est qu'un indice (il peut mentir) : la preuve est un appel réel au serveur. Séquence : `online` → attente 2 s → tirage → envoi → mise à jour de l'état. Échec réseau → réessais 30 s / 2 min / 5 min / 15 min / 1 h.

### 5.4 Parité du calcul d'affichage
Même méthode que le poste : le test lit le PHP de référence, exécute le JavaScript sur la même grille (`tests/Js/*.test.mjs` existe déjà côté LogiAgriERP : `agrierp_laravel/tests/Js/verrou-logique.test.mjs`, lancé par `node`), et exige l'égalité. Une divergence = test rouge, jamais « ça arrondit pareil à peu près ».

### 5.5 Durée hors ligne
Le jeton expire à 90 jours (`agrierp_laravel/config/sanctum.php`, `SANCTUM_EXPIRATION`) ; les référentiels vieillissent (prix) ; annoncer à l'écran « Dernier tirage : il y a N jours » et, au-delà d'un seuil décidé avec le client, **refuser la vente hors ligne** plutôt que vendre à un prix périmé (décision client).

### 5.6 Installabilité, appareil par appareil (limites)
| Plateforme | Installation | Limites à dire |
|---|---|---|
| Chrome / Edge (Windows, macOS, Linux, Android) | invite `beforeinstallprompt` ; manifeste + service worker + HTTPS exigés | Background Sync disponible (Chromium) mais pas garanti ; stockage purgeable |
| Android | « Ajouter à l'écran d'accueil » / installation | idem ; économiseurs de batterie qui retardent la synchronisation |
| Firefox | pas d'installation de PWA sur ordinateur ; usage en onglet | pas de Background Sync |
| Safari / iOS / iPadOS | pas de `beforeinstallprompt` : afficher les instructions manuelles Partager ➔ Sur l'écran d'accueil (comme `pwa-install.blade.php` d'LogiAgriERP) | **pas de Background Sync** ; stockage d'un site peu utilisé potentiellement purgé par le système ; comportements propres aux PWA installées à vérifier sur un vrai appareil avant tout engagement |
HTTPS est obligatoire en production (hors `localhost`). Ces points sont des limites générales de plateforme, à reconfirmer à la date du chantier ; aucun essai iPhone n'a été fait dans ce dépôt.

---

## 6. Tests

### 6.1 Outils
- **Playwright** et Chromium sont présents sur la machine de rédaction : Playwright en module Node global (`/opt/node22/lib/node_modules/playwright`), Chromium sous `/opt/pw-browsers` (`chromium-1194`, `chromium_headless_shell-1194`). Le dépôt d'LogiAgriERP a aussi **Laravel Dusk** (`agrierp_laravel/tests/Browser/*`, `DuskTestCase.php`, chromedriver global). Dusk est bien pour les parcours Livewire ; **pour le mode avion, Playwright est plus simple** (`context.setOffline(true)`, `page.route` pour perdre une réponse, `context.serviceWorkers()`, inspection d'IndexedDB et des caches par `page.evaluate`). Choix recommandé : Playwright pour la PWA, Dusk pour le reste, un seul des deux par scénario.
- Serveur de test : `php artisan serve` sur base `migrate:fresh --seed` ; `npm run build` et `php artisan storage:link` obligatoires (sinon des tests échouent pour des raisons d'environnement).

### 6.2 Scénarios obligatoires (mode avion simulé)
1. Tirage initial en ligne, puis coupure, 3 ventes + 1 fiche, retour réseau, une seule vente par UUID au serveur.
2. Réponse perdue : `page.route('**/api/sync/push', r => r.abort())` APRÈS traitement serveur (utiliser un proxy de test qui laisse passer la requête puis coupe la réponse) → renvoi → pas de doublon.
3. 500 puis 413 puis réseau parfait : la file finit `synced` (modèle : `agrierp_flutter/test/essai_multipostes_test.dart`).
4. Jeton révoqué (401) : suspension, puis réappairage.
5. Purge à la déconnexion et refus avec `pending`.
6. Aucun HTML authentifié dans les caches après déconnexion ; aucun jeton lisible dans `localStorage`/`sessionStorage`/`caches`.
7. Deux onglets ; base supprimée ; version de schéma plus récente/plus ancienne ; ancienne VERSION de cache.
8. Chiffrement : le contenu brut des enregistrements d'IndexedDB ne contient aucun nom de produit ni montant en clair.
9. Un « poste navigateur » devient un participant de plus de l'essai multipostes serveur (`SyncEssaiMultipostesTest`) : mêmes invariants (trésorerie, stock, dettes égaux partout).

### 6.3 Ce qui n'est PAS testable ici
Safari/iOS réels, purge du stockage par pression système, économiseurs de batterie Android : essai manuel documenté sur appareils du client.

---

## 7. Risques

| Risque | Gravité | Parade |
|---|---|---|
| Le navigateur purge IndexedDB : **perte de ventes non envoyées** | haute | `storage.persist()`, compteur permanent, synchronisation fréquente, message explicite à la réouverture, durée hors ligne courte |
| Conflits de numérotation | moyenne | numéro provisoire, remplacé au tirage ; lien UUID ↔ numéro définitif |
| Secrets en clair sur un navigateur partagé | haute | chiffrement + PIN + purge ; interdire l'usage sur appareil partagé |
| Deux clients à garder en parité | haute | libellés lus dans les vues Blade, calculs prouvés par parité exécutée, périmètre minimal |
| Safari/iOS sans Background Sync | moyenne | replis `online` + premier plan + minuterie |
| Données de la ferme sur des téléphones personnels | haute | décision client, PIN, purge à distance par révocation du jeton |
| Vente à un prix périmé | moyenne | durée hors ligne bornée (5.5) |

---

## 8. Questions au client (à poser AVANT tout code)

1. **Quels appareils** : PC de la caisse (alors le poste Windows suffit-il ?), tablette, téléphone ? **Android seul ou aussi iPhone** (iOS : pas de Background Sync) ?
2. **Combien de temps** travaille-t-on hors connexion : quelques heures, une journée, des jours ? (borne du prix périmé, du jeton à 90 jours)
3. **Quels volumes** : ventes par jour, fiches par jour, nombre de produits et de clients à copier sur l'appareil ?
4. **Quelle perte est tolérable** si le navigateur vide son stockage ? (si « aucune » : ne pas faire de PWA)
5. La caisse est-elle **partagée** entre plusieurs personnes sur le même appareil ? (si oui : poste Windows)
6. Qui **rapproche** un reçu au numéro provisoire du numéro définitif ? Faut-il imprimer un reçu provisoire ?
7. L'appareil est-il **personnel** ou à l'entreprise ? Un PIN suffit-il comme protection ?
8. Faut-il aussi **consulter** (stock, clients) hors ligne, ou seulement saisir ?
9. Le **poste Windows ne suffit-il pas** ? (réponse la moins chère)
10. Facture normalisée hors ligne : acceptez-vous « demandée — en attente » jusqu'à la synchronisation (`41_MECEF_EMECEF.md`) ?

---

## 9. Pièges (si la voie est ouverte)

Mettre `/api/` ou `/livewire/` dans un cache ; intercepter un `POST` ; stocker un jeton en clair dans `localStorage` ; oublier la purge à la déconnexion ; compter sur Background Sync partout ; croire qu'IndexedDB est durable ; oublier le versionnage du schéma ; inventer un second protocole de synchronisation ; réécrire une règle de stock ou de numérotation dans le navigateur ; afficher « synchronisé » avec l'horloge de l'appareil.

---

## 10. Contrôle de ce fichier

Chemins cités vérifiés par `ls` à la rédaction (07/11/2026) : `agrierp_laravel/public/sw.js`, `manifest.webmanifest`, `offline.html`, `agrierp_laravel/resources/views/components/pwa-install.blade.php`, `agrierp_laravel/tests/Feature/PwaEtPolicesLocalesTest.php`, `agrierp_laravel/config/sanctum.php`, `agrierp_laravel/tests/Js/verrou-logique.test.mjs`, `agrierp_flutter/lib/core/sync/modale_synchronisation.dart`, `agrierp_flutter/test/essai_multipostes_test.dart`, `/opt/pw-browsers/chromium-1194`. **Non vérifiés (n'existent pas encore, à créer)** : `docs/PWA_DECISION.md`, `public/caisse-hors-ligne.html`, `resources/js/hors-ligne/calculs-caisse.js`, `tests/Js/calculs-caisse.test.mjs` (noms proposés). Aucun essai de compilation web de `logialvia_app/` n'a été fait.
