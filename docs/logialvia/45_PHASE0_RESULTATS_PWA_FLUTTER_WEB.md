# 45 — Phase 0 : preuve d'exécution du poste Flutter compilé pour le web, dans Chromium

Date : 08/11/2026. Suite de l'étude 44 et de la décision DV-16 (le client a validé la Phase 0 = une preuve dans Chrome avant tout engagement). Tout a été fait dans des COPIES jetables sous `/tmp` (supprimées à la fin) ; seuls ce document et `docs/logialvia/img/phase0/` sont ajoutés au dépôt. Flutter 3.47.7 / Dart 3.13.5, Chromium + Playwright (Node 22) préinstallés, `deviceScaleFactor: 1`, locale `fr-FR`, fuseau `Africa/Porto-Novo`.

## 1. Verdict

**GO CONDITIONNEL pour la Phase 1.** Pour la première fois, le poste tourne dans un navigateur : démarrage, schéma v85, connexion réelle, tirage complet (≈ 8 600 lignes), trois écrans pilotes avec des données réelles, saisie hors ligne puis synchronisation exacte (une seule fois), persistance après fermeture. Aucun critère d'arrêt n'est atteint avec le stockage IndexedDB. MAIS :

1. **Bloquant n°1 : l'application ne se recharge pas sans réseau** (`net::ERR_INTERNET_DISCONNECTED`, page blanche). Aucun service worker (le `flutter_service_worker.js` de 3.47 fait 784 octets et se désinscrit ; `getRegistrations()` renvoie `[]`). Sans service worker propre, ce n'est pas une PWA hors ligne : on ne peut qu'utiliser l'application déjà ouverte.
2. **OPFS : critère d'arrêt n°1 atteint dans ce mode.** Dès que la page est servie avec COOP/COEP (isolation inter-origines), drift passe en `opfsLocks` et l'application de la 1re page du tirage prend ≈ 110 s (contre ≈ 3 s en IndexedDB). Phase 1 = rester en IndexedDB partagé (comportement par défaut), sans en-têtes COOP/COEP, jusqu'à comprendre ce ralentissement.
3. Non prouvé et non testable ici : Safari/iOS (critère d'arrêt n°2), vrai réseau mobile, appareil réel, durée de vie du stockage, plusieurs onglets.

## 2. Méthode et commandes

```bash
export PATH=/opt/flutter/bin:$PATH
# Poste : copie sans build/, .dart_tool/, windows/, installer/
rsync -a --exclude build --exclude .dart_tool --exclude windows --exclude installer agrierp_flutter/ /tmp/p0_web/
cd /tmp/p0_web && flutter create --platforms=web .
#  - app_database.dart : _openConnection() -> driftDatabase(name:'agrierp', web: DriftWebOptions(sqlite3Wasm: 'sqlite3.wasm', driftWorker: 'drift_worker.js'))
#  - flutter pub add drift_flutter (0.3.1) ; flutter_secure_storage ^10.0.0 (le pub add a aussi fait passer drift 2.34.3 -> 2.35.3)
#  - web/sqlite3.wasm : release sqlite3-3.5.2 de simolus3/sqlite3.dart (téléchargée, 748 686 o, passée par le proxy sans problème)
#  - web/drift_worker.js : copié du cache pub (drift-2.35.3/drift_worker.js) : la release GitHub de drift était bloquée (403)
#  - parametres_poste.dart : adresseServeur() = Uri.base.origin sur le web (voir §3)
flutter build web --release --base-href /poste/ --no-web-resources-cdn   # 85 à 107 s, build/web = 51 Mo
```

Serveur réel : copie de `agrierp_laravel` SANS `vendor` (lien symbolique en lecture), sans `.env`, base SQLite temporaire `/tmp/p0.sqlite` posée par variables d'environnement (`DB_CONNECTION=sqlite DB_DATABASE=/tmp/p0.sqlite APP_KEY=...`), `php artisan migrate:fresh --seed --force`, `db:seed --class=DemoDataSeeder` (367 ventes, 495 écritures, 828 pointages, 36 dépenses…), puis `PHP_CLI_SERVER_WORKERS=4 php -S 127.0.0.1:8765 -t public` avec le build dans `public/poste/` (même origine : pas de CORS). Un second serveur Node (port 8766) servait le même dossier en Brotli, avec `Cache-Control` long sur les ressources lourdes, et relayait `/api` vers PHP : il sert aux mesures réseau (`php -S` ne compresse pas) et au test COOP/COEP.

Pilotage : Playwright, `launchPersistentContext` (profil réutilisé pour les fermetures/réouvertures). Flutter dessine dans un canvas : j'ai activé l'arbre de sémantique (clic sur `flt-semantics-placeholder`) pour lire les textes et cliquer par libellé, et des clics à coordonnées fixes pour les formulaires. Réseau simulé par CDP `Network.emulateNetworkConditions`.

## 3. Ce qu'il a fallu changer dans la copie (et rien d'autre)

| Changement | Pourquoi |
|---|---|
| `driftDatabase` + `sqlite3.wasm` + `drift_worker.js` | seule cause des 3 926 erreurs de compilation (étude 44) |
| `--no-web-resources-cdn` | par défaut Flutter charge `canvaskit.js` depuis `www.gstatic.com` : sans accès Internet, écran vide (`Failed to fetch dynamically imported module`). Un poste utilisé à la ferme doit embarquer CanvasKit : OBLIGATOIRE dans la CI |
| Adresse du serveur = `Uri.base.origin` sur le web | l'adresse par défaut du poste est la production ; sur le web, l'origine de la page est la bonne valeur par défaut. La saisie de l'adresse n'existe pas à l'écran de connexion |
| `flutter_secure_storage ^10` | uniquement pour le build `--wasm`, qui n'a PAS été tenté (voir §8) ; la compilation JS a réussi aussi avec lui |

**Aucun stub `dart:io` n'a été nécessaire pour démarrer** : `DossierDonnees`, `FenetrePoste`, `AdministrationLocale.appliquerRestaurationEnAttente()` ne bloquent pas le démarrage web. Ce que cela ne dit pas : les ~13 fichiers d'E/S (étude 44 §2) n'ont pas été exercés, sauf l'export de Gestion Stocks (§6). `device_name` : rien à fournir, le poste tire seul `poste-<8 hex>` (`ParametresPoste.identifiant()`), conservé ensuite.

La copie du poste date de 08:42 ; entre-temps le dépôt a bougé (plusieurs fichiers de `lib/` diffèrent de la copie) : les résultats valent pour cet instantané.

## 4. Mesures (Chromium headless, logiciel de rendu WebGL, machine sandbox)

| Mesure | Résultat |
|---|---|
| Compilation | 3 builds JS réussis (85–107 s), 51 Mo ; `main.dart.js` 8,57 Mo (Brotli 1,99), `canvaskit.wasm` 7,28 Mo (2,63), `sqlite3.wasm` 0,75 Mo (0,34), `drift_worker.js` 0,36 Mo (0,10) |
| (a) Premier écran (connexion), démarrage à froid | 2,3 s sur `php -S` sans compression (14,3 Mo transférés, 10 requêtes) ; 2,9 s en Brotli (3,95 Mo) |
| Idem en réseau simulé, à froid | Fast 4G (9 Mbit/s, 170 ms) : 6,8 s ; Slow 4G Lighthouse (1,6 Mbit/s, 150 ms) : **22,7 s** |
| Idem, démarrage « chaud » (cache HTTP) | sans limite 1,0 s ; Fast 4G 1,5 s ; Slow 4G **1,2 s** (0 octet transféré) |
| (b) Migration locale schéma v85 | créée au premier démarrage dans le navigateur, **0 erreur console** (seul message : choix du stockage). Le numéro de version n'a pas été lu directement (pas d'accès à la base) : la preuve est indirecte (tous les écrans lisent/écrivent, le tirage de 60+ tables s'applique) |
| (c) Connexion `POST /api/auth/login` | 200 en 294 ms ; jeton Sanctum conservé |
| (c) Tirage complet `/api/sync/pull` (IndexedDB) | 7 pages, **5,7 s** de la 1re à la dernière requête, application terminée < 6 s ; 9 604 entrées de tableaux (≈ 8 640 lignes réelles, hors listes de méta-données `tables_servies`/`accounting_entry_ids`) ; 3,1 Mo de JSON ; plus grosses tables : stock_movements 2 084, chart_of_accounts 1 337, accounting_entry_lines 1 309, livestock_daily_entries 911, attendance_records 828, sale_lines 728, accounting_entries 495, sales 367 |
| Volume du stockage après tirage | 2,6 Mo (IndexedDB) ; 1,5 Mo après la seule migration ; quota annoncé 162 Go |
| Mémoire (tas JS) | 55 à 100 Mo selon l'écran |
| Définition du PIN + déverrouillage | ≈ 4 s (PIN confirmé) ; déverrouillage 1,6 s |
| (d) Ouverture d'un écran déjà chargé | Gestion Stocks 0,8–1,0 s, Fournisseurs 0,4–0,5 s, Ventes & Devis 0,7 s (5 ouvertures consécutives) |

Anomalie non élucidée : quand la fenêtre « Rappels du jour » est encore ouverte, l'écran ouvert dessous est resté en roue de chargement 6 à 16 s avec le fil principal à 100 % (une fois > 16 s sur Gestion Stocks) ; non reproduit une fois la fenêtre fermée. À instruire en Phase 1 (probable travail Dart en boucle sur le fil principal).

## 5. Données réelles affichées (captures, `deviceScaleFactor: 1`)

- Gestion Stocks : valorisation 2 012 778 FCFA, 13 références en alerte, tableau des produits avec PMP : `/tmp/pw/d2_stocks.png` (copie : `docs/logialvia/img/phase0/phase0_gestion_stocks.png`).
- Fournisseurs : 6 fournisseurs actifs (SODIVET Bénin, Provenderie du Plateau…) = les 6 du serveur : `/tmp/pw/d3_fournisseurs.png` (copie : `img/phase0/phase0_fournisseurs.png`).
- Ventes & Devis : tuiles produits avec stocks locaux : `/tmp/pw/d4_ventes.png` (copie : `img/phase0/phase0_ventes_devis.png`).
- Tableau de bord : 312 têtes, résultat net, alertes critiques ; fenêtre « Rappels du jour » alimentée par les bandes réelles : `/tmp/pw/y.png`.
- Saisie hors ligne : `/tmp/pw/e4_saisie_hors_ligne.png` (copie : `img/phase0/phase0_saisie_hors_ligne.png`).

La fidélité visuelle web ↔ poste n'a pas été auditée ; le rendu est celui du poste Windows (interface large, conçue pour bureau).

## 6. Hors ligne, persistance, synchronisation

| Essai | Constat |
|---|---|
| (e) `setOffline(true)`, création d'un fournisseur par l'interface (nom, téléphone, catégorie) | Fonctionne : enregistré, visible dans la liste, 1 appel API échoué en tout |
| (e) Rechargement de la page hors ligne | **ÉCHEC : `net::ERR_INTERNET_DISCONNECTED`, page blanche**, 0 `flutter-view`. Bloquant n°1 |
| (f) Fermeture complète du navigateur puis réouverture (même profil, en ligne) | Session et code PIN conservés, base locale intacte, **le fournisseur créé hors ligne est toujours là** |
| (e) Retour en ligne | La synchronisation automatique a envoyé `POST /api/sync/push` (200) sans action ; le serveur contient **exactement 1** « Fournisseur Hors Ligne P0 » ; un clic manuel sur « Synchroniser » n'a rien renvoyé (pas de doublon) |
| Export (Gestion Stocks → Exporter) | Produit un PDF téléchargé par blob : le chemin `printing`/`pdf` fonctionne sur le web sans modification |
| (g) Migration depuis une base d'une version antérieure | **Non essayée** (il faut un build web antérieur ; sans objet tant qu'aucune base web n'existe en production) |
| Locale du navigateur | Une erreur `Incorrect locale information provided` est apparue une fois (2e compilation, locale `en-US`) ; non reproduite sur la 3e compilation en `en-US` ni en `fr-FR`. À surveiller |

## 7. Stockage : IndexedDB contre OPFS

| Mode | Déclencheur | Tirage |
|---|---|---|
| `sharedIndexedDb` (défaut ici) | page sans COOP/COEP : `SharedArrayBuffer` indisponible | 5,7 s, 2,6 Mo, aucun problème |
| `opfsLocks` | page servie avec `Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy: require-corp` | page 1 appliquée en ≈ 110 s, page 2 en ≈ 40 s, pages 3 à 7 en 2 s : ≈ 150 s au total ; sur un profil neuf, la page 1 n'était toujours pas appliquée après 25 s |

Chromium ne gère pas les Workers dédiés dans un SharedWorker (`dedicatedWorkersInSharedWorkers` manquant) : même isolé, drift n'obtient pas le meilleur mode OPFS. Cause du ralentissement non établie (verrous OPFS, écritures synchrones sur le disque du bac à sable, environnement : non départagés). Conséquence pratique : ne PAS activer COOP/COEP en Phase 1, et ne pas compter sur OPFS.

## 8. Confrontation aux critères d'arrêt de l'étude 44

| Critère | Résultat |
|---|---|
| 1. Migration v85 ou synchro > 60 s, ou en échec | IndexedDB : non atteint (migration sans erreur, tirage 5,7 s). OPFS : ATTEINT (≈ 150 s). Décision : IndexedDB |
| 2. Safari/iOS perd des données ou refuse OPFS | **NON TESTABLE ici** (Chromium seul). À faire sur iPad/iPhone réels avant d'annoncer l'iOS |
| 3. Premier chargement > 15 s en 4G après cache | Non atteint : 1,2–1,5 s, mais grâce au cache HTTP (donc inutile hors ligne : voir bloquant n°1). À froid en Slow 4G : 22,7 s (hors critère, mais à annoncer : 4 Mo Brotli, ≈ 8 Mo sans compression) |
| 4. Phase 2 > 150 % de l'estimation | Sans objet à ce stade |
| 5. Perte de données | Aucune observée (fermeture/réouverture, hors ligne puis synchro) |

## 9. Travaux du socle déduits de ce qui a été vu (Phase 1) et estimation révisée

| Travail | Jours-homme |
|---|---|
| Service worker propre sous `/poste/` : précache versionné (`main.dart.js`, `canvaskit`, `sqlite3.wasm`, `drift_worker.js`, assets, polices), rechargement hors ligne, mise à jour contrôlée ; test Playwright hors ligne | 5 à 7 |
| Hébergement Laravel `public/poste/`, Brotli, `Cache-Control`, build CI avec `--no-web-resources-cdn`, garde-fou « aucune URL externe » | 3 à 4 |
| Écran/réglage de connexion web (adresse = origine, identifiant de poste, déconnexion), saisie du PIN et clavier tactile | 2 à 3 |
| Fichiers/dossiers : interface `dart:io` / octets + téléchargement, 13 fichiers (export tableur, justificatifs, sauvegarde/restauration, SMTP via route Laravel) — NON exercé en Phase 0 | 8 à 12 |
| Anomalie fil principal sous la fenêtre « Rappels du jour », profilage des écrans lourds (Stocks) | 2 à 3 |
| Stockage : conserver IndexedDB, instruire OPFS (`opfsLocks`) en parallèle sans bloquer | 2 à 3 |
| Tests navigateur (Playwright : tirage, saisie hors ligne, synchro, persistance), garde-fou de fidélité en CI | 4 à 6 |
| Sous-total Phase 1 | ≈ 26 à 38 (étude 44 : 10 j pour le « socle » seul ; le reste de la ligne y figurait en phases 2 et 3) |

Estimation globale révisée : **≈ 42 à 65 j-h** (étude 44 : 35 à 60). Le chiffre monte surtout à cause du service worker hors ligne (absent, donc à construire et à tester sur plusieurs navigateurs) et de la validation de stockage, pas de la compilation ni de la synchronisation, qui se sont révélées saines.

## 10. Limites et ce qui n'est PAS prouvé

- Safari/iPhone/iPad (éviction du stockage, refus d'OPFS), Firefox, Edge : non testés.
- Aucun vrai réseau mobile : la « 4G » est simulée par CDP (latence et débit du transport seulement) ; aucun appareil réel (tactile, clavier virtuel, mémoire d'un téléphone). Rendu logiciel (SwiftShader) : les temps de dessin ne représentent pas un GPU.
- Durée de vie du stockage (éviction par le navigateur, nettoyage), quota réel sur appareil, sauvegarde de la base côté web : non traités.
- Plusieurs onglets sur la même base : non testé (le verrou « un seul écrivain » reste à vérifier).
- Un seul jeu de données (démonstration, cinq mois) ; base serveur SQLite, pas MySQL (écarts d'arrondi connus du script d'essai multipostes).
- Build `--wasm` non tenté (temps et disque) ; `flutter_secure_storage ^10` non revalidé sur Windows.
- Les écrans, saisies et formulaires hors des trois pilotes (et hors fournisseur) n'ont pas été parcourus ; la vente de caisse hors ligne n'a pas été jouée (fournisseur choisi : formulaire plus court).
- Les clics à coordonnées fixes sont fragiles ; une saisie rapide a perdu des caractères sous charge (mot de passe tronqué) dans un essai : artefact du pilotage, à ne pas confondre avec un défaut produit sans nouvel essai.
- Aucun fichier du dépôt n'a été modifié, hors ce document et `docs/logialvia/img/phase0/` (4 captures, 150 à 220 Ko). Rien n'a été commité.
