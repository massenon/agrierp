# 49 — Check-list : renommer le produit et changer le domaine des adresses (modèle : AgriERP → LogiAgriERP, `olouwachegoun.bj` → `fermeolouwachegoun.com`)

> **USAGE**
>
> - **Quand l'utiliser.** (1) Le jour où LogiALVIA reçoit son nom définitif ou un nouveau domaine d'adresses (le dossier `docs/logialvia/` sert à le construire : ne JAMAIS y recopier « LogiAgriERP »). (2) Pour rejouer ou auditer le renommage d'LogiAgriERP.
> - **Ordre.** `16_DECISIONS_VALIDEES.md` (DV-25 à DV-30 : ce qui est décidé) → **cette check-list, dans l'ordre des sections** → `04_UI_UX_DESIGN_SYSTEM.md` § 14 (captures) → `31_TESTING_QA.md` (suites complètes) → GUIDE bloc 24.
> - **Entrées requises.** Le nouveau nom (graphie exacte, majuscules comprises), le nouveau domaine, la décision du client sur la couleur / la graphie de marque (« ERP » en jaune `#FFD55F` pour LogiAgriERP).
> - **Sorties.** Un dépôt où le nom AFFICHÉ est partout le nouveau, où les identifiants TECHNIQUES n'ont pas bougé, où les adresses déjà en base sont migrées, où aucune capture ne montre l'ancien nom.
> - **Rien d'inventé.** Les constantes citées sont relues dans `agrierp_flutter/installer/agrierp.iss`, `agrierp_flutter/windows/runner/Runner.rc`, `agrierp_flutter/lib/core/systeme/dossier_documents.dart`, `agrierp_laravel/database/migrations/2026_10_21_000001_…`, `agrierp_laravel/.env.example` ; l'historique du renommage vient des commits `bb830f8`, `37c5e6b`, `67308f7`, `0df92a7`, `8e967b0`, `109c13f` (mots de leurs messages). Ce que le dépôt ne documente pas est marqué « à la main » ou « non vérifié ».
> - **Interdits permanents.** Un remplacement global sans l'expression sûre du § 3 ; toucher `AppId`, `CompanyName`, `ProductName` ; renommer une variable d'environnement ou une clé de configuration ; commiter ; `pkill`.

## 1. Deux familles : nom AFFICHÉ et identifiants TECHNIQUES

| Famille | Exemples (LogiAgriERP) | Règle |
|---|---|---|
| **Nom affiché** (le client le voit) | libellés web et poste, titres, `<title>` et manifestes (`web/manifest.json`, `public/manifest.webmanifest` : « LogiAgriERP »), `APP_NAME` des `.env.example`, `AppName` / `AppVerName` / `DefaultDirName` / `DefaultGroupName` de l'installateur, nom de l'installateur (`LogiAgriERP-Setup-<version>`), titre de la fenêtre Windows (`main.cpp`), manuel, README, documents PDF, e-mails, `Documents\LogiAgriERP` | RENOMMER |
| **Identifiants techniques** (le client ne les voit pas, les changer CASSE des installations) | **`AppId={{69B3D13F-4283-4B8E-ABD1-456845FC5182}`** de `agrierp.iss` (« même AppId pour tous les environnements : un seul LogiAgriERP par poste Windows » : le changer fait installer un SECOND logiciel à côté du premier, sans mise à jour) ; **`CompanyName` (« OLOUWACHEGOUN ») et `ProductName` (« agrierp ») de `Runner.rc`** | **GARDER** |
| **Autres identifiants techniques** | paquet Dart `agrierp` (`package:agrierp/…`), exécutable `agrierp.exe`, dossiers `agrierp_laravel/` et `agrierp_flutter/`, installateur `agrierp.iss`, base IndexedDB `agrierp` et `agrierp_justificatifs`, commande `php artisan agrierp:doublons`, variables `AGRIERP_LARAVEL`, `AGRIERP_PROTOTYPE`, `AGRIERP_ESSAI_*` (majuscules), nom de base `agrierp_db`, version du service worker `agrierp-v7` | GARDER (un renommage de dossier ou de paquet est un autre chantier, jamais couplé au renommage de marque) |

⚠️ **Pourquoi `CompanyName` / `ProductName` ne se touchent pas.** Le dossier des données du poste (`%APPDATA%\OLOUWACHEGOUN\donnees`, point de passage unique `DossierDonnees.courant()`) en DÉRIVE ; l'installateur le désigne en dur (`[UninstallDelete]` : `{userappdata}\OLOUWACHEGOUN\donnees`). Changer `CompanyName` fait chercher la base locale ailleurs : **le poste perd sa base locale** (saisies non synchronisées comprises) au premier lancement après mise à jour.

## 2. Inventaire AVANT de remplacer (lecture seule)

1. `grep -rIn "AgriERP"` (casse exacte) sur tout le dépôt hors `.git`, `vendor`, `node_modules`, `build`, `.dart_tool` : classer chaque occurrence en « nom affiché » ou « identifiant ».
2. Chercher aussi les formes cassées : `Agri ERP`, `agri-erp`, `AGRIERP` (les variables d'environnement en majuscules DOIVENT rester).
3. Lister les textes DANS les images (captures, aperçu social, PDF de spécimens) : le `grep` ne les voit pas (§ 7).
4. Lister les e-mails et domaines : `grep -rIn "olouwachegoun.bj"` (toutes formes : sans « @ », `www.`, majuscules, `lang/`, JS, `public/`, `resources/`, `manuel/`, `assets/`, `installer/`).

## 3. Expression régulière SÛRE (jamais un « Logi » doublé)

Le piège : remplacer `AgriERP` par `LogiAgriERP` partout, y compris dans une chaîne DÉJÀ renommée, donne un nom où « Logi » est doublé ; relancer le remplacement deux fois aussi. Règle :

- Motif : **`(?<![A-Za-z])AgriERP`** (un « AgriERP » qui n'est pas déjà précédé d'une lettre) → `LogiAgriERP`. Idempotent : relancé, il ne trouve plus rien.
- NE PAS utiliser une classe insensible à la casse : `agrierp` (minuscules) est un identifiant (§ 1).
- Appliquer par FICHIER de texte (`*.php`, `*.blade.php`, `*.dart`, `*.md`, `*.html`, `*.json`, `*.iss`, `*.rc`, `*.yaml`, `*.js`), JAMAIS aux binaires (images, PDF, polices, `*.sqlite`) ni à `vendor/` / `node_modules/` / `build/` / `.dart_tool/`.
- Relire les cas de graphie : « Logi » + « Agri » + « ERP » en trois couleurs dans l'interface (le texte du code reste `LogiAgriERP`, la couleur est dans la mise en forme : « LogiAgri » blanc puis « ERP » jaune, `agrierp_flutter/lib/main.dart`).
- **Contrôle de sortie obligatoire** : `grep -rIPn "Logi(?=Logi)"` (un « Logi » suivi d'un autre « Logi ») = 0 occurrence ; `grep -rIPn "(?<![A-Za-z])AgriERP"` = seulement l'historique voulu (ce fichier, `README_SPRINT0.md`, `HISTORIQUE_SESSIONS_CLAUDE.md`, commentaires de migration). Dans `docs/logialvia/` il ne reste QUE les citations volontaires de l'ancien nom (ce fichier, DV-29 de `16`, bloc 24 du guide : l'expression de remplacement et `Documents\AgriERP`).
- Les tests qui comparent des libellés lus dans le Blade (`*_blade_test`, `verrou_parite_web_test`) doivent rester verts SANS changer leur logique : si l'un rougit, c'est un libellé renommé d'un seul côté.

## 4. Migration des adresses e-mail déjà en base (modèle : MAIL1, 21/10/2026)

Le code, les seeders, les tests et les écrans changent par le § 3 ; les DONNÉES, non. Décision MAIL1 (DV-26) : tout `@olouwachegoun.bj` devient `@fermeolouwachegoun.com`, AUSSI ceux déjà enregistrés.

1. **Web** : migration `2026_10_21_000001_migrer_les_adresses_email_du_domaine` — idempotente, `down()` vide, parcours générique du schéma (colonnes texte dont le nom évoque une adresse), `company_settings`, titre et message des `notifications` ; **secrets écartés par leur NOM avant toute lecture** (`smtp_password_encrypted` jamais lu) ; `audit_logs` et `journal_synchronisation` EXCLUS (l'historique ne se réécrit pas) ; `users.email` unique : si la nouvelle adresse est prise, la ligne reste et un `Log::warning` le dit (à reprendre à la main) ; `updated_at` rafraîchi sur les seules lignes changées pour que les postes les reprennent. Compte `admin` : `dg@` devient `contact@fermeolouwachegoun.com`.
2. **Poste** : palier Drift **v50** (`_convertirAdressesEmail`, SQL insensible à la casse) sur `customers`, `suppliers`, `company_settings`, `utilisateurs`, `notifications`, `app_settings` ; `sync_status` et `updated_at` INTACTS ; l'e-mail de la session au coffre est converti à la LECTURE (`convertirDomaineEmail`). ⚠️ Un nouveau changement de domaine = un NOUVEAU palier Drift et une NOUVELLE migration (ne jamais éditer l'ancienne).
3. **Tests à écrire d'abord** (modèle : `MigrationAdressesEmailTest`, `migration_emails_poste_test.dart`) avec leurs MUTATIONS (contrôle d'unicité retiré, exclusion de `audit_logs` retirée, filtre des secrets retiré, `updated_at` retiré, palier désactivé).
4. **Laissé tel quel, à reprendre à la main** : nom de serveur SMTP saisi avec l'ancien domaine (Paramètres › Email) ; adresse d'une autre organisation (`support@faguez-sarl.bj`) ; adresses fictives des tests (`@ferme.bj`, `@resto.bj`).
5. **Non vérifié** pour MAIL1 : base RÉELLE peuplée (MySQL / MariaDB de production), poste Windows réel (mise à jour d'une base locale).

## 5. Reprise de l'ancien dossier `Documents\<AncienNom>` (modèle : DV-29)

1. `lib/core/systeme/dossier_documents.dart` : constantes `nomDossierDocuments` / `ancienNomDossierDocuments` ; `dossierDocumentsPoste()` reprend l'ancien dossier avant d'écrire : ancien seul → RENOMMÉ ; les deux présents → chaque élément de l'ancien est déplacé SAUF s'il porte déjà le même nom dans le nouveau (**jamais d'écrasement** ; l'élément en collision reste dans l'ancien, supprimé seulement s'il est devenu vide) ; une panne de disque n'empêche JAMAIS d'exporter.
2. Tous les écrivains passent par ce point de passage unique (`livrerFichier`, `ExportTableur`…) : aucun `getApplicationDocumentsDirectory()` ailleurs.
3. Installateur (`agrierp.iss`) : à la désinstallation, sauvegarde automatique proposée de `Documents\<Nouveau>` ET de `Documents\<Ancien>` (`archives-et-exports-ancien-dossier`), puis suppression des deux ; une MISE À JOUR (même `AppId`) ne touche jamais aux données.
4. Test : `test/dossier_documents_test.dart` (renommage, fusion sans écrasement, panne). **Non vérifié** : un vrai Windows ; l'installateur n'a jamais été compilé ici.

## 6. Secrets et variables : ce qui ne se renomme PAS

1. **`SGMEF_*`** (`SGMEF_API_URL`, `SGMEF_TOKEN`, `SGMEF_DEFAULT_IFU`, `SGMEF_DEFAULT_OPERATOR_NAME`, `SGMEF_DEFAULT_OPERATOR_ID`, `SGMEF_HTTP_TIMEOUT`, `SGMEF_CONNECT_TIMEOUT`, `SGMEF_VERIFY_SSL`) : noms fixés par le repli de `config/mecef.php` ; le jeton n'est jamais affiché ni versionné.
2. **`.env` réels** : jamais lus, jamais modifiés, jamais versionnés. Seuls `.env.example` et `.env.production.example` changent (`APP_NAME=LogiAgriERP`) ; **sur un serveur déjà installé, `APP_NAME` se change À LA MAIN** (le dépôt ne peut pas le faire). Noms `DB_*`, `APP_KEY`, `MAIL_*` : inchangés.
3. Secrets du poste (coffre du système : PIN, mots de passe en attente, `flutter_secure_storage`) : clés `agrierp.verrou.<id>`, `agrierp.inactivite.<id>`, `agrierp.rappels.masque.<id>` GARDÉES (les renommer ferait perdre les PIN).
4. Aucun secret dans une capture ni dans un message de commit.

## 7. Captures, README, aperçu social (voir `04_UI_UX_DESIGN_SYSTEM.md` § 14)

Retoucher TOUTES les images qui montrent l'ancien nom ou l'ancien domaine : `manuel/img`, `manuel/jpg`, `manuel/originaux_non_floutes/` (copie privée, à jour aussi), `docs/images/` (README), `docs/images/social-preview.png` (1280 × 640), spécimens `presentation/` (régénérés par `php presentation/generer.php`, SQLite EN MÉMOIRE, aucun appel réseau). Nom et e-mail de l'administrateur flouté ; « ERP » en jaune `#FFD55F` ; retouche par lecture du texte puis re-rendu avec la même police Inter ; relecture automatique de toutes les images (zéro ancien nom).

## 8. Contrôles de fin

1. `flutter analyze` propre ; suite Flutter COMPLÈTE `flutter test --concurrency=2` (UNE passe) ; `php artisan test --testsuite=Feature` (avec `npm run build` et `php artisan storage:link`, sinon des échecs d'environnement) ; filtre `--filter="Pwa|Sw|Poste"`.
2. `grep -rIPn "Logi(?=Logi)"` : zéro occurrence ; l'ancien nom seulement dans l'historique voulu ; l'ancien domaine seulement dans les migrations et leurs tests.
3. Lecture automatique des textes de toutes les images (§ 7) : zéro ancien nom, zéro ancien domaine, zéro nom / e-mail d'administrateur lisible.
4. Installateur : `AppId` et `CompanyName` / `ProductName` inchangés (`git diff` des deux fichiers ne montre aucune de ces lignes).
5. Service worker : `VERSION` de `sw.js` (portée `/`) augmentée si ses fichiers précachés changent ; le poste web régénère sa propre `VERSION` au build.

## 9. Ce qui reste À LA MAIN (jamais fait par un remplacement)

- `APP_NAME` des `.env` déjà installés ; nom de serveur SMTP saisi en base ; adresse e-mail d'expéditeur saisie à l'écran.
- Compte e-MECeF, IFU, jeton : saisis par l'administrateur, jamais touchés.
- Raccourcis et entrée « Applications » des postes Windows déjà installés (le nom affiché change à la mise à jour ; non vérifié sur un vrai Windows).
- Noms de domaine, certificats, DNS, boîtes aux lettres : hors dépôt.
- Dossier de dépôt et noms `agrierp_*` : renommage éventuel = autre chantier (§ 1, dernière ligne).
- Pour LogiALVIA : choisir le nom ET la graphie de marque (la couleur d'« ERP » est propre à LogiAgriERP ; la charte de LogiALVIA est marine `#1F3864` / or `#B58B2A`).
