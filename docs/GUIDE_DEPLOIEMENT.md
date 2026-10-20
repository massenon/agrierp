# Guide — cloner, tester et déployer AgriERP (serveur, poste, cPanel, tâches planifiées)

**Date :** 19/10/2026 · **Pour :** l'éditeur et l'équipe technique de la ferme.
Ce guide complète [`INSTALLATION_LOCALE.md`](INSTALLATION_LOCALE.md) (poste Windows de développement, pas à pas),
[`agrierp_laravel/RUNBOOK_DEPLOIEMENT_CPANEL.md`](../agrierp_laravel/RUNBOOK_DEPLOIEMENT_CPANEL.md) et
[`agrierp_laravel/CHECKLIST_PRE_DEPLOIEMENT.md`](../agrierp_laravel/CHECKLIST_PRE_DEPLOIEMENT.md). En cas de désaccord, **ce guide
fait foi** : il tient compte des tickets du 19/10/2026 (synchronisation S-T1 à S-T11, file d'attente des tâches).

> ⚠️ **Ordre de mise en production : le SERVEUR d'abord, les postes ensuite.** Un poste à jour face à un ancien
> serveur laisserait non comptées certaines ventes de bétail (ticket S-T9).

---

## 1. Cloner

```bash
git clone https://github.com/massenon/agrierp.git
cd agrierp
git checkout main          # ou la branche à tester, ex. claude/sleepy-dijkstra-uvt68t
```

⚠️ L'historique a été réécrit le 17/10/2026 : une copie clonée avant cette date doit être **supprimée et reclonée**.

Trois dossiers : `agrierp_laravel/` (site web + API de synchronisation), `agrierp_flutter/` (poste Windows hors
ligne), `manuel/`.

## 2. Le serveur (Laravel) en local

Prérequis : **PHP 8.3** (extensions `pdo_mysql`, `mbstring`, `openssl`, `intl`, `gd`, `zip`, `fileinfo`, `bcmath`),
Composer 2, Node.js 20, MySQL 8 ou MariaDB 10.11 (`utf8mb4_unicode_ci`).

```bash
cd agrierp_laravel
composer install
npm install
cp .env.example .env               # Windows : copy .env.example .env
php artisan key:generate
# .env : DB_DATABASE=agrierp_db, DB_USERNAME, DB_PASSWORD — base vide créée en utf8mb4_unicode_ci
php artisan migrate:fresh --seed   # rôles, plan comptable, exercice, barèmes, 4 comptes de démonstration
npm run build                      # styles et scripts (sans lui, 10 tests échouent)
php artisan storage:link           # justificatifs et photos
php artisan serve --port=8002      # http://127.0.0.1:8002
```

Comptes de démonstration (mot de passe `AgriERP@2026`) : `admin`, `compta`, `caisse`, `elevage`.
Jeu de démonstration complet (ventes, fiches, stocks…) : `php artisan db:seed --class=DemoDataSeeder`.

### Tester le serveur

```bash
php artisan test --testsuite=Feature          # ~1 850 tests, doit finir sans échec
php artisan test --testsuite=Feature --filter=SyncTiragePagineTest   # un fichier
php artisan dusk                              # parcours navigateur (Chrome + .env.dusk.local, base agrierp_dusk)
```

⚠️ `php artisan test` **sans** `--testsuite=Feature` échoue (pas de dossier `tests/Unit`).
⚠️ Ne jamais pointer `.env.dusk.local` sur `agrierp_db` : Dusk vide la base.

## 3. Le poste (Flutter, Windows)

Prérequis : Flutter stable (Dart ≥ 3.12), Visual Studio 2022 « Développement Desktop en C++ », Inno Setup 6.

```powershell
cd agrierp_flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # après toute modification d'une table Drift
flutter analyze                                            # doit finir par « No issues found! »
flutter test                                               # ~2 500 tests ; 17 se sautent avec leur raison
flutter run -d windows                                     # lance le poste
```

- Les tests de parité exécutent le vrai PHP du serveur : `php` dans le PATH et `composer install` fait dans
  `agrierp_laravel/` (dossier voisin, ou variable `AGRIERP_LARAVEL`).
- Premier démarrage : l'écran de connexion propose l'adresse du serveur ; l'onglet **Paramètres → Appairage** la
  change ensuite (redémarrage nécessaire).

### Tests contre un vrai serveur

```bash
# 1) Le test d'intégration simple (serveur local lancé sur le port 8002)
cd agrierp_laravel && php artisan serve --port=8002
cd agrierp_flutter && flutter test --tags integration test/sync_reel_test.dart

# 2) L'essai à cinq postes avec coupures au hasard (Linux / WSL : MariaDB privé, serveur, postes, arrêt propre)
cd agrierp_flutter && ./outils/essai_multipostes.sh                 # une graine tirée au hasard
./outils/essai_multipostes.sh 42 7 2026                               # trois essais rejouables (graines 42, 7, 2026)
ESSAI_FUSEAUX="Africa/Porto-Novo America/New_York" ./outils/essai_multipostes.sh 42   # postes dans deux fuseaux
```

L'essai (S-T9 à S-T12) joue cinq journées par graine (~3 min) et couvre tout ce qui se synchronise, jusqu'à la
réinitialisation des données au web en fin d'essai ; il échoue au premier invariant faux et laisse un rapport lisible.

### Construire l'installateur

```powershell
cd agrierp_flutter
build_windows.bat                         # production (adresse https://agrierp.fermeolouwachegoun.com)
build_windows.bat --env recette           # recette : même serveur (décision du 19/10/2026), installateur suffixé -recette
build_windows.bat --env dev               # développement (http://127.0.0.1:8002)
build_windows.bat --sans-installateur     # dossier Release seulement
```

Résultat : `agrierp_flutter\installer\Output\AgriERP-Setup-<version>.exe`. Le script refuse une version `-demo`
en production, une version mal formée, l'absence d'Inno Setup ou du runtime VC++.

## 4. Envoyer le serveur sur cPanel

### 4.1 Préparer (sur un poste avec Internet)

```bash
cd agrierp_laravel
composer install --no-dev --optimize-autoloader
npm ci && npm run build                   # produit public/build/ (à envoyer : il n'est pas versionné)
```

Si l'hébergement offre **Git Version Control** et le **Terminal** (SSH), préférez cloner sur le serveur
(§4.2 option A) ; sinon envoyez une archive (option B).

### 4.2 Installer sur l'hébergement

**Option A — Git sur le serveur (recommandé)**

```bash
cd ~
git clone https://github.com/massenon/agrierp.git agrierp_depot
ln -s ~/agrierp_depot/agrierp_laravel ~/agrierp          # le site vit dans ~/agrierp
cd ~/agrierp
composer install --no-dev --optimize-autoloader          # si Composer est disponible ; sinon envoyer vendor/
# envoyer public/build/ construit en §4.1 (Gestionnaire de fichiers ou scp)
```

**Option B — archive** : compresser `agrierp_laravel/` **avec** `vendor/` et `public/build/`, **sans** `.env`,
`storage/logs/*`, `node_modules/`, l'envoyer dans `~/agrierp` et l'extraire. ⚠️ Ne jamais laisser d'archive
(`agrierp.zip`) dans un dossier servi par le web : elle exposerait tout le code.

### 4.3 Racine du domaine

Dans **cPanel → Domaines**, faire pointer `agrierp.fermeolouwachegoun.com` sur **`~/agrierp/public`**.
⚠️ Aujourd'hui la racine pointe sur le dossier du projet (sondé le 15/10) : la protection repose alors sur un
`.htaccess` de secours à la racine du projet, **absent du dépôt** — le corriger est la priorité de sécurité.

### 4.4 Fichier `.env` de production

```dotenv
APP_NAME=AgriERP
APP_ENV=production
APP_DEBUG=false
APP_URL=https://agrierp.fermeolouwachegoun.com
APP_LOCALE=fr
APP_FALLBACK_LOCALE=fr
LOG_LEVEL=warning

DB_CONNECTION=mysql
DB_HOST=localhost
DB_DATABASE=<base cPanel>          # créée dans « Bases de données MySQL », interclassement utf8mb4_unicode_ci
DB_USERNAME=<utilisateur cPanel>
DB_PASSWORD=<mot de passe>

SESSION_DRIVER=database
QUEUE_CONNECTION=database          # voir §5 : un travailleur de file est nécessaire
CACHE_STORE=database
SANCTUM_EXPIRATION=129600          # jetons des postes : 90 jours (minutes)

MAIL_MAILER=smtp                   # les réglages réels se saisissent dans Paramètres → Email (SMTP)
MAIL_FROM_ADDRESS="no-reply@fermeolouwachegoun.com"
```

Le mot de passe SMTP ne va **pas** dans `.env` : il se saisit dans **Paramètres → Email (SMTP)** (chiffré en base).

### 4.5 Première installation

```bash
cd ~/agrierp
php artisan key:generate                       # une seule fois
php artisan migrate --force
php artisan db:seed --force                    # rôles, plan comptable, barèmes, comptes de démonstration
php artisan storage:link
php artisan config:cache && php artisan route:cache && php artisan view:cache
php artisan agrierp:backup                     # vérifie que mysqldump est disponible sur cet hébergement
```

Puis changer **immédiatement** les mots de passe des 4 comptes de démonstration (écran Mon Profil).

### 4.6 Mise à jour (déploiements suivants)

```bash
cd ~/agrierp_depot && git pull                 # ou envoyer la nouvelle archive
cd ~/agrierp
php artisan down
php artisan agrierp:backup                     # sauvegarde AVANT de migrer
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan config:cache && php artisan route:cache && php artisan view:cache
php artisan queue:restart
php artisan up
```

- Envoyer le nouveau `public/build/` si les styles ou scripts ont changé, et **incrémenter `VERSION` dans
  `public/sw.js`** si un fichier mis en cache par le navigateur a changé.
- Puis seulement : distribuer le nouvel installateur des postes.

## 5. Tâches planifiées (cron cPanel)

Dans **cPanel → Tâches cron**, deux entrées (remplacer `UTILISATEUR` et le chemin de PHP 8.3 de l'hébergeur,
souvent `/usr/local/bin/php` ou `/opt/cpanel/ea-php83/root/usr/bin/php`) :

```cron
# 1) Le planificateur Laravel — UNE seule entrée, chaque minute (toutes les tâches de routes/console.php)
* * * * * cd /home/UTILISATEUR/agrierp && /usr/local/bin/php artisan schedule:run >> /dev/null 2>&1

# 2) Le travailleur de file — chaque minute, s'arrête quand la file est vide
* * * * * cd /home/UTILISATEUR/agrierp && /usr/local/bin/php artisan queue:work --stop-when-empty --max-time=55 >> /dev/null 2>&1
```

⚠️ **L'entrée 2 est indispensable** : le rappel de prophylaxie et les alertes de la cloche sont des tâches **mises en
file** (`ShouldQueue`, `QUEUE_CONNECTION=database`). Sans travailleur, elles s'empilent dans la table `jobs` et ne
s'exécutent jamais — sans aucune erreur visible. (Alternative si l'hébergeur interdit la seconde entrée :
`QUEUE_CONNECTION=sync`, les tâches s'exécutent alors dans le planificateur lui-même.)

Ce que déclenche le planificateur (`agrierp_laravel/routes/console.php`) :

| Tâche | Quand (heure du Bénin) |
|---|---|
| Sauvegarde `agrierp:backup` | chaque jour à 02h00 |
| Rappel de prophylaxie du jour | chaque jour à 06h00 |
| Alertes de la cloche (stock, mortalité, soins, reproduction) | chaque jour à 06h05 |
| Nettoyage des sessions expirées | chaque semaine |
| Purge des notifications lues de plus de 90 jours | chaque semaine |
| Purge des tâches échouées de plus de 30 jours | chaque semaine |
| Rappel de télécharger la dernière sauvegarde | chaque lundi à 08h00 |
| Ouverture de l'exercice de l'année `agrierp:ouvrir-exercice` (ticket EX3) | chaque 1er janvier à 00h00 |

Vérifier après installation : `php artisan schedule:list` (liste et prochaines exécutions) et, le lendemain, la
présence d'une sauvegarde et des notifications du matin.

**Exercice comptable (EX3).** Aucune entrée cron de plus : l'ouverture de l'exercice passe par le même
`schedule:run`. Elle se lance aussi à la main, sans risque de doublon (`php artisan agrierp:ouvrir-exercice`).
Si le cron ne tourne pas le 1er janvier, la première saisie datée de la nouvelle année ouvre l'exercice d'elle-même ;
l'exercice peut aussi être ouvert dès le 1er décembre par **Comptabilité › Clôture d'exercice › Ouvrir l'exercice**.
Si l'ouverture est refusée (deux exercices déjà ouverts : l'avant-dernier n'est pas clôturé), l'administrateur reçoit
une notification « Exercice AAAA non ouvert » : toute saisie de l'année est refusée tant qu'il ne l'est pas.

## 6. Essais en production, puis remise à zéro

Décision du 19/10/2026 : la recette se fait **sur le serveur de la ferme**.
1. Mettre le serveur à jour (§4.6), puis installer les postes.
2. Faire les essais (web et postes).
3. **Paramètres → Réinitialisation des données** (administrateur) : vide toute l'activité (ventes, fiches, stocks,
   écritures, trésorerie, bandes…), garde les référentiels, les comptes et l'exercice ; les postes purgent leurs
   données à leur synchronisation suivante (vérifié le 19/10 : 7 390 lignes → 0).
4. Faire synchroniser chaque poste, puis commencer la saisie réelle.

## 7. Vérifications après chaque mise en production

- [ ] `https://agrierp.fermeolouwachegoun.com/.env` répond 403 ou 404.
- [ ] Connexion web ; tableau de bord affiché.
- [ ] Un poste se connecte, « Synchroniser maintenant » réussit, le contrôle de cohérence (écran Synchronisation)
      ne montre aucun écart.
- [ ] Paramètres → Postes & Appairage liste le poste.
- [ ] Paramètres → Email (SMTP) → « Envoyer un e-mail de test » arrive.
- [ ] `php artisan schedule:list` et la table `jobs` vide le lendemain matin.
