# AgriERP — monorepo

Système de gestion intégrée de la **Ferme École OLOUWACHEGOUN** (Ikpinlè, Bénin) — PAEB / Cabinet FAGUEZ SARL.

Ce dépôt regroupe les deux clients du produit, la base de référence et le manuel d'utilisation.

| Dossier | Contenu |
|---|---|
| [`agrierp_laravel/`](agrierp_laravel/) | Application web Laravel 12 + Livewire 3 (PHP 8.3, MySQL) : serveur, règles métier, API de synchronisation `/api/sync/*` |
| [`agrierp_flutter/`](agrierp_flutter/) | Client Windows Flutter, *offline-first* (Drift / SQLite), synchronisé avec l'application Laravel |
| [`manuel/`](manuel/) | Manuel d'utilisation (sources HTML, captures d'écran, génération PDF) |

Chaque projet a son propre `CLAUDE.md` qui décrit son architecture, ses conventions et ses pièges : lisez-le avant d'y toucher.

## Démarrage rapide

Guide complet pas à pas (Windows, clonage, tests, installateur) : [`INSTALLATION_LOCALE.md`](INSTALLATION_LOCALE.md).

### Application web — `agrierp_laravel/`

```bash
cd agrierp_laravel
composer install
npm install
cp .env.example .env
php artisan key:generate
php artisan migrate:fresh --seed     # base agrierp_db, utf8mb4_unicode_ci
npm run build                        # ou : npm run dev
php artisan serve --port=8002
```

Tests :

```bash
php artisan test --testsuite=Feature   # toujours préciser la suite : tests/Unit n'existe pas
cp .env.dusk.example .env.dusk.local  # puis renseigner APP_KEY et DB_PASSWORD
php artisan dusk                       # parcours navigateur, base dédiée agrierp_dusk
```

### Client bureau — `agrierp_flutter/`

```bash
cd agrierp_flutter
flutter pub get
dart run build_runner build          # régénère app_database.g.dart après un changement de schéma
flutter analyze
flutter test
flutter run -d windows
build_windows.bat                    # Windows : build release + installateur AgriERP-Setup-<version>.exe
```

### Base de données

Aucun export SQL n'est versionné (retiré de l'historique le 17/10/2026 : il contenait des hash de mots de passe et
des jetons). La base se reconstruit depuis les migrations et les seeders :

```bash
cd agrierp_laravel && php artisan migrate:fresh --seed
```

### Manuel — `manuel/`

`manuel/build.py` assemble `src/part*.html` et imprime le PDF via Chrome.

## Conventions

- [`DOCTRINE_PORTAGE.md`](DOCTRINE_PORTAGE.md) : règles de fidélité Laravel → Flutter et d'architecture hors ligne.
- [`PLAN_FINALISATION.md`](PLAN_FINALISATION.md) : tickets restants, par sprint, et décisions client en attente.

- Toute la prose, les libellés d'interface, les commentaires et la documentation sont **en français**.
- Le prototype HTML reste la source de vérité visuelle et comportementale des deux clients (voir les `CLAUDE.md` des projets).
- Les fins de ligne sont normalisées en LF dans le dépôt (voir `.gitattributes`).
