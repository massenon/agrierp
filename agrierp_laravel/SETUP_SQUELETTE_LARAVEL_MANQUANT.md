# ✅ RÉSOLU — plus besoin de suivre cette procédure

Ce document décrivait une procédure manuelle en 3 étapes. **Elle n'est
plus nécessaire** : tous les fichiers de squelette manquants ont été
créés directement et livrés dans ce zip, clonés depuis le dépôt officiel
`github.com/laravel/laravel` (branche `12.x`) plutôt que reconstruits de
mémoire :

- `artisan` (racine)
- `bootstrap/app.php` (avec `api: __DIR__.'/../routes/api.php'` déjà
  appliqué), `bootstrap/providers.php`, `bootstrap/cache/`
- `public/index.php`, `public/favicon.ico`, `public/robots.txt` — votre
  `public/assets/` réel n'a pas été touché
- Les 10 fichiers `config/*.php` standards — `config/permission.php`
  (déjà livré précédemment) n'a pas été touché
- `storage/` — arborescence complète avec placeholders `.gitignore`
  dans chaque sous-dossier vide pour qu'ils survivent à la compression
- `phpunit.xml`, `.gitignore`, `.editorconfig`

**Gap supplémentaire trouvé pendant cette même vérification** : la
migration Sanctum par défaut (clonée depuis `github.com/laravel/sanctum`
pour vérifier avant de conclure) utilise `morphs('tokenable')` — un
`BIGINT` incompatible avec `users.id`, qui est un UUID dans ce projet.
Une migration corrigée (`uuidMorphs()`) est déjà livrée dans
`database/migrations/2026_03_10_000001_create_personal_access_tokens_table.php`
— **ne lancez jamais**
`php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider"`
pour les migrations sur ce projet, ça écraserait cette correction par la
version par défaut cassée.

Passez directement à `composer install` (`composer.json` déjà corrigé
précédemment pour Laravel 12), puis `.env`, `key:generate`,
`migrate:fresh --seed`, `serve` — plus de fichier de squelette manquant
sur le chemin.

---

## Historique — ce document décrivait initialement ceci (conservé pour référence)

Confirmé en vérifiant directement le contenu du projet livré : aucun
`artisan`, aucun dossier `bootstrap/`, aucun `public/index.php`, et
`config/` ne contient que mon propre `permission.php` — aucun des
fichiers de configuration standards de Laravel (`app.php`,
`database.php`, `session.php`, `filesystems.php`, `mail.php`, `queue.php`,
`cache.php`, `logging.php`...). C'est la cause réelle de "Could not open
input file: artisan" — pas un problème de configuration, le fichier
n'existe simplement pas.

J'ai toujours supposé, sans jamais le dire clairement comme une étape
obligatoire, qu'un squelette Laravel de base existait déjà chez vous
avant d'y fusionner mes fichiers. C'était une supposition, pas une
vérification — et elle était fausse pour votre cas. Voici la procédure
de récupération complète, dans l'ordre exact.

---

## Étape 0 — Corriger `composer.json` (la virgule surnuméraire signalée)

Le fichier que j'ai livré est propre (vérifié à nouveau maintenant,
aucune virgule en trop). Quelque chose s'est produit entre vos deux
tentatives sur votre machine — sans pouvoir inspecter votre fichier
réel, la façon la plus sûre de trancher est de le remplacer entièrement
par ce contenu exact plutôt que de deviner où est la virgule :

```json
{
    "name": "faguez-sarl/agrierp",
    "type": "project",
    "description": "AgriERP — Système de gestion intégrée pour la Ferme École OLOUWACHEGOUN (PAEB / FAGUEZ SARL).",
    "keywords": ["laravel", "livewire", "erp", "agriculture"],
    "license": "proprietary",
    "require": {
        "php": "^8.3",
        "laravel/framework": "^12.0",
        "laravel/reverb": "^1.0",
        "laravel/sanctum": "^4.0",
        "laravel/tinker": "^2.9",
        "livewire/livewire": "^3.5",
        "spatie/laravel-permission": "^7.0",
        "barryvdh/laravel-dompdf": "^3.0",
        "maatwebsite/excel": "^3.1",
        "simplesoftwareio/simple-qrcode": "^4.2"
    },
    "require-dev": {
        "fakerphp/faker": "^1.23",
        "laravel/dusk": "^8.2",
        "laravel/pail": "^1.1",
        "laravel/pint": "^1.13",
        "laravel/sail": "^1.26",
        "mockery/mockery": "^1.6",
        "nunomaduro/collision": "^8.1",
        "phpunit/phpunit": "^11.0.1"
    },
    "autoload": {
        "psr-4": {
            "App\\": "app/",
            "Database\\Factories\\": "database/factories/",
            "Database\\Seeders\\": "database/seeders/"
        }
    },
    "autoload-dev": {
        "psr-4": {
            "Tests\\": "tests/"
        }
    },
    "scripts": {
        "post-autoload-dump": [
            "Illuminate\\Foundation\\ComposerScripts::postAutoloadDump",
            "@php artisan package:discover --ansi"
        ],
        "post-update-cmd": [
            "@php artisan vendor:publish --tag=laravel-assets --ansi --force"
        ],
        "post-root-package-install": [
            "@php -r \"file_exists('.env') || copy('.env.example', '.env');\""
        ],
        "post-create-project-cmd": [
            "@php artisan key:generate --ansi",
            "@php -r \"file_exists('database/database.sqlite') || touch('database/database.sqlite');\"",
            "@php artisan migrate --graceful --ansi"
        ]
    },
    "extra": {
        "laravel": {
            "dont-discover": []
        }
    },
    "config": {
        "optimize-autoloader": true,
        "preferred-install": "dist",
        "sort-packages": true,
        "allow-plugins": {
            "pestphp/pest-plugin": true,
            "php-http/discovery": true
        }
    },
    "minimum-stability": "stable",
    "prefer-stable": true
}
```

## Étape 1 — Récupérer le squelette Laravel manquant (artisan, bootstrap/, public/, config/)

Dans un dossier **temporaire séparé** (pas `C:\laragon\www\agrierp`, pour
ne rien écraser) :

```powershell
cd C:\laragon\www
composer create-project laravel/laravel:^12.0 agrierp-squelette-temp
```

Cela télécharge un vrai projet Laravel 12 complet et vierge. Une fois
terminé, copiez **uniquement** ces éléments depuis
`agrierp-squelette-temp` vers `agrierp` :

| Depuis le squelette temporaire | Vers `agrierp` | Écraser ? |
|---|---|---|
| `artisan` | racine | Oui (fichier absent chez vous) |
| `bootstrap/app.php` | `bootstrap/app.php` | Oui, **puis** réappliquer la modification `api:` de `SETUP_API_SANCTUM.md` (voir plus bas) |
| `bootstrap/providers.php` | `bootstrap/providers.php` | Oui |
| `bootstrap/cache/` (dossier vide) | `bootstrap/cache/` | Oui |
| `public/index.php`, `public/.htaccess`, `public/robots.txt` | `public/` | Oui — ne touchez PAS à `public/assets/` (le vôtre, réel) |
| `config/*.php` **sauf** `config/permission.php` | `config/` | Oui pour tous les autres — **gardez `config/permission.php` déjà livré**, ne le remplacez pas |
| `phpunit.xml` | racine | Oui (absent chez vous) |
| `.gitignore` | racine | Oui si vous utilisez Git |
| `resources/css/app.css`, `resources/js/app.js`, `resources/js/bootstrap.js` | `resources/` | Oui si absents chez vous (vérifiez d'abord — Vite en a besoin) |

Une fois copié, supprimez `agrierp-squelette-temp` — il a servi son
usage.

### Puis réappliquer l'étape API dans `bootstrap/app.php`
Le `bootstrap/app.php` fraîchement copié ne connaît pas encore
`routes/api.php` — reprenez l'Étape 1 de `SETUP_API_SANCTUM.md` (ajouter
`api: __DIR__.'/../routes/api.php'` au bloc `withRouting()`).

## Étape 2 — Relancer `composer install` proprement

```powershell
cd C:\laragon\www\agrierp
composer clear-cache
composer install
```

`composer clear-cache` avant de relancer : votre première tentative a
laissé un fichier temporaire à moitié écrit
(`tmp-d70931a...zip`) suite à l'erreur Pint — repartir d'un cache propre
évite de retomber sur ce même fichier corrompu.

### Sur l'erreur Pint elle-même ("Permission denied")
Un antivirus (Windows Defender ou autre) verrouille fréquemment les
fichiers `.zip` temporaires de Composer pendant leur écriture sur
Windows — cause la plus probable, pas un vrai problème de droits
utilisateur. Si `composer clear-cache` + nouvelle tentative ne suffit
pas :
- Ouvrez PowerShell **en tant qu'administrateur** pour cette seule commande.
- Ou ajoutez temporairement `C:\Users\<vous>\AppData\Local\Composer`
  et `C:\laragon\www\agrierp\vendor` aux exclusions de votre antivirus
  le temps de l'installation.

## Étape 3 — Reprendre la suite normalement

```powershell
copy .env.example .env
php artisan key:generate
php artisan migrate:fresh --seed
php artisan serve
```

(`copy`, pas `cp` — PowerShell a un alias `cp` qui fonctionne pour un
fichier simple comme celui-ci, donc votre commande précédente était en
fait correcte ; ce n'était pas la cause du blocage.)
