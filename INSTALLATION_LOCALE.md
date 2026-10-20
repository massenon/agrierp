# Cloner AgriERP en local et le faire tourner (Windows)

Ce guide part d'un poste Windows vierge et aboutit à quatre résultats vérifiables : le site web servi en local, la suite de tests Laravel verte, le poste Flutter lancé contre ce site, et l'installateur `AgriERP-Setup-<version>.exe`.

> ⚠️ **L'historique Git a été réécrit le 17/10/2026** (retrait de `database/agrierp_db.sql`, qui contenait des hash de mots de passe et des jetons). **Toute copie clonée avant cette date doit être supprimée et reclonée.** Un `git pull` sur une ancienne copie réintroduirait les anciens commits.

---

## 1. Prérequis

| Outil | Version | Rôle |
| --- | --- | --- |
| Git | récent | cloner le dépôt |
| [Laragon](https://laragon.org) (ou PHP + MySQL séparés) | **PHP 8.3**, MySQL 8 | application web |
| Composer | 2.x | dépendances PHP |
| Node.js | 20 LTS | construction des styles (`npm run build`) |
| Flutter SDK | stable, Dart ≥ 3.12.2 | poste Windows |
| Visual Studio 2022 | charge « Développement Desktop en C++ » | compilation Windows du poste |
| [Inno Setup 6](https://jrsoftware.org/isdl.php) | 6.x | installateur `.exe` |

⚠️ Laragon livre parfois PHP 8.1 par défaut : AgriERP exige **8.3**. Vérifier avec `php -v` dans le terminal de Laragon.

## 2. Cloner

```powershell
cd C:\Projects
git clone https://github.com/massenon/agrierp.git
cd agrierp
git checkout main                      # ou la branche de travail à tester
```

Le dépôt contient trois dossiers : `agrierp_laravel/` (site web et API de synchronisation), `agrierp_flutter/` (poste Windows hors ligne) et `manuel/`.

## 3. Application web (`agrierp_laravel/`)

```powershell
cd agrierp_laravel
composer install
npm install
copy .env.example .env
php artisan key:generate
```

Dans `.env`, renseigner la base MySQL (`DB_DATABASE=agrierp_db`, `DB_USERNAME`, `DB_PASSWORD`) et créer cette base vide (`utf8mb4_unicode_ci`) dans Laragon. Puis :

```powershell
php artisan migrate:fresh --seed       # base reconstruite : rôles, plan comptable, exercice, barèmes, comptes de démonstration
npm run build                          # manifeste Vite (sans lui, 10 tests échouent)
php artisan storage:link               # justificatifs et photos (sans lui, des tests échouent)
php artisan serve --port=8002          # http://127.0.0.1:8002
```

Comptes de démonstration (mot de passe `AgriERP@2026`) : `admin`, `compta`, `caisse`, `elevage`.

Au premier passage de l'administrateur sur le tableau de bord, l'**assistant de démarrage** liste ce qui manque encore (exercice ouvert, trésorerie, modules…). Il ne bloque rien.

### Vérifier

```powershell
php artisan test --testsuite=Feature   # doit finir sans échec
```

⚠️ `php artisan test` **sans** `--testsuite=Feature` échoue : la suite `tests/Unit` n'existe pas.

## 4. Poste Windows (`agrierp_flutter/`)

```powershell
cd ..\agrierp_flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze                        # doit finir par « No issues found! »
flutter test                           # environ 2 040 tests ; 16 se sautent sans la maquette HTML
flutter run -d windows                 # lance le poste
```

- Les tests qui comparent le poste au serveur trouvent `agrierp_laravel/` tout seuls (dossier voisin). Pour pointer ailleurs : variable `AGRIERP_LARAVEL` (et `AGRIERP_PROTOTYPE` pour la maquette).
- Ces tests de parité exécutent le vrai PHP du serveur : ils exigent `php` dans le PATH et `composer install` fait dans `agrierp_laravel/`, sinon ils se sautent avec leur raison.

**Premier démarrage du poste :** l'écran de connexion d'un poste neuf affiche l'adresse du serveur (`https://agrierp.fermeolouwachegoun.com` par défaut) et permet de la changer, par exemple en `http://127.0.0.1:8002` pour le site local. Après la connexion, l'écran « Premier démarrage du poste » lance la première synchronisation.

## 5. Installateur Windows

```powershell
cd agrierp_flutter
build_windows.bat                      # analyse + tests + compilation + installateur
build_windows.bat --sans-tests         # déconseillé avant une livraison
build_windows.bat --sans-installateur  # dossier Release seulement, sans Inno Setup
```

Le script **échoue** (code de sortie 1) si la version de `pubspec.yaml` n'est pas de la forme `x.y.z+n`, si une DLL du runtime Visual C++ manque dans `System32`, si Inno Setup est absent (sauf `--sans-installateur`), ou si l'installateur n'a pas été produit.

Résultat : `agrierp_flutter\installer\Output\AgriERP-Setup-1.0.0.exe`.

### À vérifier sur la machine de compilation (le script n'a jamais été exécuté hors Windows)

1. Le script finit par `=== Termine : installer\Output\AgriERP-Setup-<version>.exe ===`.
2. Sur une machine **neuve** (sans Visual Studio ni Flutter), l'installateur s'installe et `agrierp.exe` démarre. S'il ne démarre pas, il manque une DLL du runtime : le signaler.
3. La désinstallation ne supprime pas la base locale (elle vit dans le profil Windows de l'utilisateur, pas dans `Program Files`).

## 6. Travailler sur le dépôt

- **Tout en français** : libellés, commentaires, noms de tests, messages de commit.
- Lire avant toute modification : `CLAUDE.md` (racine et projet), [`DOCTRINE_PORTAGE.md`](DOCTRINE_PORTAGE.md) (fidélité web ↔ poste, article 5), [`PLAN_FINALISATION.md`](PLAN_FINALISATION.md).
- Une table synchronisable modifiée côté Laravel l'est aussi côté Flutter (`app_database.dart`, puis `build_runner`).
- Jamais de `*.sql`, `*.zip` ni `.env` dans un commit (`.gitignore` les bloque).
- Chaque ticket est consigné dans `agrierp_laravel/README_SPRINT0.md`, y compris ce qui n'a **pas** été vérifié.

## 7. Maintenance utile

```powershell
php artisan agrierp:vider-sessions        # déconnecte tout le monde (web et postes) ; --force sans confirmation
php artisan schedule:run                  # tâches planifiées (sauvegarde, rappels, alertes) — en production : une seule tâche cron par minute
```
