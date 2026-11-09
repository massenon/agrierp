# 44 — Étude de faisabilité : PWA hors ligne = poste Flutter compilé pour le web (voie B)

> **Statut (09/11/2026) : étude réalisée — voir `45_PHASE0_RESULTATS_PWA_FLUTTER_WEB.md` (preuve de phase 0) et `46_PWA_POSTE_WEB_PHASE1_RESULTATS.md` (phase 1 réalisée, mesures avant / après).** Le texte de l'étude ci-dessous est conservé tel qu'écrit le 07/11/2026.

Date : 07/11/2026. Étude SANS livraison : tout a été fait dans une copie jetable (`/tmp/flutter_web_spike`, supprimée), aucun fichier du dépôt modifié hors ce document. Flutter 3.47.7 / Dart 3.13.5.

## 1. Ce qui a été réellement compilé

| Essai | Commande | Résultat |
|---|---|---|
| 1. Poste tel quel + `flutter create --platforms=web` | `flutter build web --release` | ÉCHEC : 3 926 erreurs (80 s) |
| 2. Après remplacement de la seule connexion Drift | idem | RÉUSSI (95 s), `build/web` 50 Mo |
| 3. Idem en `--wasm` | `--wasm` | ÉCHEC : 49 erreurs, toutes dans `flutter_secure_storage_web 1.2.1` (`dart:html`, `dart:js`) |
| 4. + `flutter_secure_storage ^10` | `--wasm` | RÉUSSI (295 s), `main.dart.wasm` 7,3 Mo (2,5 Mo gzip) |

Les 3 926 erreurs de l'essai 1 ont UNE seule cause : `package:drift/native.dart` -> `sqlite3/ffi` -> `dart:ffi` (2 104 « Type not found », 1 419 « isn't a type », 139 « Only JS interop members may be external », 114 « Undefined name », 95 « Couldn't find Native », 9 « dart:ffi is not available », reste = allocateurs ffi). 100 % dans `sqlite3-3.5.2` et `ffi-2.2.0`, aucune dans le code agrierp. Seul `lib/core/database/app_database.dart` est concerné (fonction `_openConnection`, 10 lignes remplacées par `driftDatabase(...)` de `drift_flutter`).

Correctifs faits dans la copie : (a) `_openConnection` -> `drift_flutter` avec `sqlite3.wasm` et `drift_worker.js` ; (b) `flutter pub add drift_flutter` ; (c) `flutter_secure_storage` 9 -> 10 (pour le wasm seulement). Rien d'autre. `flutter analyze lib` : 3 avertissements (imports devenus inutiles).

ATTENTION : « compile » n'est PAS « fonctionne ». Dart accepte `import 'dart:io'` sur dart2js : File, Directory, `getApplicationSupportDirectory`, `Process`, sockets SMTP compilent et échouent AU RUNTIME. Le build wasm passe aussi, `dart:io` y étant stubé.

## 2. Fichiers touchés (runtime)

`dart:io` importé dans 16 fichiers de `lib/` (sur 214) ; ffi : aucun dans `lib` ; `Platform.` : 1 (`ouvreur_url.dart`) ; `MethodChannel` : 1 (`fenetre_poste.dart`, inoffensif : `PlatformException` rattrapée, à vérifier) ; `win32` : aucun. Sites qui CASSERONT au runtime (nombre d'usages File/Directory/path_provider) : `administration_locale.dart` 12 (sauvegardes, VACUUM INTO, restauration), `export_tableur.dart` 7, `fichiers_entreprise.dart` 6, `envoi_email_test.dart` 5 (SMTP : impossible depuis un navigateur), `importation_screen.dart` 4, `ouvreur_url.dart` 3, `justificatif_local.dart` 3, `pdf_recu.dart` 3, `synchronisation_automatique.dart` 2, `dossier_donnees.dart` 2, `demarrage_poste.dart` 1 (journal de démarrage), `sync_engine.dart` 1, `reglages_ferme_ui.dart` 1, `rapprochement_page.dart` 1. Soit ~13 fichiers à réécrire derrière une interface (imports conditionnels / octets en mémoire + téléchargement navigateur). `DossierDonnees.courant()` est sur le chemin de démarrage : à neutraliser en premier.

## 3. Points durs

- **Drift web** : `sqlite3.wasm` + `drift_worker.js` à servir (non téléchargés ici : pas d'accès, à ajouter dans `web/`). Stockage OPFS (worker partagé/dédié, Chrome/Edge/Firefox récents, Safari 17+ avec limites) sinon IndexedDB (plus lent, repli). Mêmes migrations Drift `schemaVersion` 85 et `PRAGMA user_version` : ils s'exécutent sur le même SQLite, donc `_reconcilierSchema` et les `PRAGMA table_info` devraient passer, NON PROUVÉ (aucun navigateur ici). `VACUUM INTO` : supporté par SQLite wasm, mais écrit un fichier : la sauvegarde devient « exporter la base en octets » puis téléchargement ; la restauration, un import d'octets. Les tests de base (203 fichiers sur 256 utilisent `NativeDatabase.memory`) restent en VM.
- **Coffre** : `flutter_secure_storage` web = WebCrypto AES-GCM avec clé dérivée stockée dans le navigateur (localStorage/IndexedDB) : protège de la lecture « à plat », pas d'un script injecté (XSS) ni d'un utilisateur du même profil. Niveau équivalent au coffre AES-GCM de la PWA-1 (même modèle de menace), pas supérieur ; la base SQLite OPFS elle-même est EN CLAIR dans le navigateur (comme `agrierp.sqlite` sur Windows, mais sans protection de session OS). Le PIN PBKDF2 (`crypto`, Dart pur) fonctionne ; sa lenteur en JS est à mesurer.
- **Service worker** : Flutter 3.47 ne génère plus de cache : `flutter_service_worker.js` obtenu = 784 octets, un stub qui se DÉSINSCRIT. Il n'y a donc aucun cache de l'enveloppe fournie : il faut écrire notre propre SW (précache de `main.dart.js|wasm`, `canvaskit`, assets, `sqlite3.wasm`, worker), sous une portée dédiée (ex. `/poste/`) pour ne pas heurter `public/sw.js`. La règle « aucun HTML authentifié en cache » est respectée si `index.html` est statique (c'est le cas : shell Flutter, aucune donnée). Les données vivent en OPFS, pas dans le Cache API.
- **Hébergement** : `flutter build web --base-href /poste/` servi par Laravel (`public/poste/`) même origine : pas de CORS, jeton Sanctum inchangé. Premier chargement : `build/web` 50 Mo non compressés ; `main.dart.js` 8,5 Mo (2,3 Mo gzip) + `canvaskit.wasm` 7,3 Mo (2,9 Mo gzip) + assets 4,9 Mo ; wasm : `main.dart.wasm` 2,5 Mo gzip + `skwasm` 1,5 Mo gzip : ~6 à 8 Mo gzip au premier chargement, puis en cache. Wasm GC exige Chrome 119+/Firefox 120+/Safari 18.2+, repli JS automatique. Brotli à activer.
- **PDF / impression** : `pdf` (Dart pur) OK ; `printing` a un support web (`Printing.layoutPdf` ouvre l'impression/PDF du navigateur) : OK, à valider visuellement (polices Roboto embarquées). **Tableur** : `excel` (Dart pur) OK mais `export_tableur.dart` écrit un fichier -> à remplacer par téléchargement d'octets. **Fichiers/justificatifs** : `file_picker` web renvoie des octets, pas de chemin : les justificatifs copiés dans un dossier de la ferme (`justificatif_local`, `fichiers_entreprise`) doivent passer en base (blob) ou OPFS. **SMTP** (`mailer`) : impossible (sockets) : l'envoi de test e-mail doit passer par une route Laravel. `ouvreur_url` : `url_launcher`.
- **Synchro automatique / Timer** : 18 usages de Timer ; un onglet en arrière-plan est bridé (≥ 1 s, puis 1 min en Chrome après 5 min). Pas de synchro en arrière-plan fiable : « synchroniser à l'ouverture et au retour de focus ». Plusieurs onglets ouverts sur la même base OPFS : verrou à prévoir (drift gère un worker partagé, mais deux onglets avec garde « un seul écrivain » à tester). `device_name` : `auth_service` ; à fournir par saisie/UUID navigateur (pas de nom de machine).
- **Tests** : `flutter test --platform chrome` est impossible (pas de navigateur ici ; `dart:ffi` et `NativeDatabase.memory` partout). Restent testables en VM : tous les tests de repositories, de calcul, de garde-fous de fidélité (~256 fichiers, ~4 000 tests) tant que le code partagé garde son implémentation native en VM ; il faut donc GARDER la connexion native pour les tests (interface `OuvreurBase`). Non testables : OPFS, worker, SW, impression, déploiement : à couvrir par quelques tests navigateur (Playwright, à installer plus tard) et recette manuelle.

## 4. Comparaison A (réécriture JS) / B (Flutter web)

| Critère | A : JS ×13 modules | B : Flutter web |
|---|---|---|
| Effort | ~ 250 à 400 j-h (poste ≈ 214 fichiers, 85 paliers de schéma, ~4 000 tests à re-porter) | ~ 35 à 60 j-h : socle web 8 à 12, 13 fichiers E/S 8 à 12, SW + hébergement + CI 5 à 8, validation navigateurs/données 8 à 12, pilotes et corrections 10 à 15 (ordre de grandeur, non mesuré en navigateur) |
| Fidélité « identique au poste » | Faible à moyenne, deux implémentations qui dérivent | Identique par construction (même code, mêmes écrans, mêmes règles) |
| Maintenance | Trois bases de code (Blade, Dart, JS) | Deux (Blade, Dart) |
| Téléchargement | Léger (quelques centaines de Ko par module) | 6 à 8 Mo gzip au premier chargement |
| Mobile/tablette | Bon (DOM responsive) | Interface conçue pour Windows ; tablette correcte, téléphone médiocre ; saisie, accessibilité (lecteurs d'écran) et sélection de texte limitées (rendu canvas) |
| Sécurité au repos | Coffre AES-GCM PWA-1 | Équivalent ; base SQLite non chiffrée en OPFS dans les deux cas |
| Risque principal | Dérive, délai | OPFS/Safari, quotas de stockage navigateur, performances de démarrage, E/S fichiers |

## 5. Recommandation et phasage

Recommandation : B, avec sortie anticipée. Jamais A pour les 13 modules.
- **Phase 0 (3 j)** : `sqlite3.wasm` + worker dans la copie, premier démarrage dans Chrome ; PREUVE : migration v1->v85 sur base vide, `_reconcilierSchema`, une synchro `/api/sync/pull` complète, mesure du temps de démarrage et du volume OPFS.
- **Phase 1 (10 j)** : socle : interface fichiers/dossiers, `DossierDonnees` web, coffre, SW propre sous `/poste/`, hébergement Laravel, CI de build web.
- **Phase 2 (15 j)** : 3 pilotes : Gestion Stocks, Fournisseurs, Ventes & Devis (PDF, tableur, justificatifs inclus), recette sur Chrome Android, Safari iPad, Edge.
- **Phase 3** : les 10 autres modules par lots, comme leur port Windows.
Critères d'arrêt : (1) migration v85 ou synchro complète échoue ou dépasse 60 s sur le matériel visé ; (2) Safari/iOS perd des données (éviction OPFS) ou refuse OPFS : abandon pour iOS ; (3) premier chargement > 15 s en 3G/4G terrain après cache ; (4) la phase 2 dépasse 150 % de l'estimation ; (5) incident de perte de données en pilote.

## 6. Non vérifié

Aucun navigateur disponible : aucune exécution réelle (démarrage, OPFS, migrations, synchro, PDF, impression, SW). `sqlite3.wasm`/`drift_worker.js` non téléchargés. `flutter_secure_storage` 10 non testé sur Windows (changements d'API possibles : il faut le revalider sur le poste ; sinon, rester en 9 pour Windows et ne passer qu'en 10 pour le web impossible, un seul pubspec). Les estimations en jours-homme sont des ordres de grandeur. Tests : rien exécuté. Copie supprimée.
