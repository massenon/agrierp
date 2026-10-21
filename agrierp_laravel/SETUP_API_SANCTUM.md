# Activer l'API — 3 étapes locales indispensables

> ✅ **Le squelette Laravel manquant a été créé directement dans ce zip**
> (`artisan`, `bootstrap/`, `public/index.php`, `config/*.php`,
> `storage/`, `phpunit.xml`, `.gitignore`) — cloné depuis
> `github.com/laravel/laravel` (branche `12.x`) pour garantir des
> fichiers réels et à jour. `bootstrap/app.php` a déjà l'enregistrement
> `api:` appliqué. Détails complets dans
> `SETUP_SQUELETTE_LARAVEL_MANQUANT.md` (désormais un historique, plus
> une procédure à suivre).
>
> 🔴 **Gap supplémentaire trouvé en vérifiant la vraie migration Sanctum
> avant de conclure** (clonée depuis `github.com/laravel/sanctum`) : sa
> migration par défaut crée `personal_access_tokens.tokenable_id` en
> `BIGINT`, incompatible avec `users.id` (UUID dans ce projet).
> **Ne lancez PAS**
> `php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider"`
> pour les migrations — une migration déjà corrigée
> (`uuidMorphs()`) est livrée dans `database/migrations/`. Seule
> l'installation du paquet (`composer.json`, déjà fait) reste
> pertinente.
>
> ⚠️ **Mise à jour critique, lue AVANT tout le reste** : `composer.json`
> a été corrigé pour cibler **Laravel 12** (`^12.0`), plus Laravel 11
> (`^11.9`). Laravel 11 est officiellement en fin de vie — plusieurs
> failles de sécurité réelles ne seront jamais corrigées dans cette
> branche (confirmé : "Fixed in 12.61.1+/13.12+ only, not backported to
> 11.x (end of life)"), et Composer les bloque désormais par défaut à
> l'installation. Ce n'est ni votre erreur ni la mienne au moment du
> choix initial — le calendrier a rattrapé le projet en cours de route.
> Laravel 13 existe déjà mais son adoption est encore trop récente
> (`laravel/tinker` ne le supporte pas encore pleinement à ce jour) —
> Laravel 12 est la cible sûre, documentée par Laravel lui-même comme
> une "release de maintenance mineure" avec un minimum de changements
> cassants depuis la 11. `spatie/laravel-permission` a été ajusté en
> conséquence (`^7.0` — sa dernière version 8.x a explicitement
> abandonné le support de Laravel 11, gardé une version de transition
> plutôt que de sauter directement en 8.x).
>
> **Lancez `composer install` (ou `composer update` s'il échoue, aucun
> `composer.lock` n'existe encore) après ce changement.** Si un AUTRE
> paquet bloque (Sanctum, Reverb, DomPDF, Livewire), copiez-collez
> l'erreur exacte — je vérifierai sa compatibilité réelle avec Laravel
> 12 avant de vous proposer un correctif, plutôt que de deviner.

Ce document répond directement à la demande "construire les API" et au
test `php artisan serve` local. Sans ces 3 étapes, **l'API construite
dans ce ticket ne serait jamais atteignable**, silencieusement — pas une
mise en garde théorique, un vrai piège de Laravel 11 qui mérite d'être
signalé clairement plutôt que découvert après coup.

---

## ⚠️ Étape 1 — OBLIGATOIRE : enregistrer `routes/api.php` dans `bootstrap/app.php`

**Depuis Laravel 11, `routes/api.php` n'est PAS chargé automatiquement**
(contrairement à Laravel 10 et versions antérieures) — il faut le
déclarer explicitement. `bootstrap/app.php` n'est pas un fichier livré
dans ce projet (skeleton standard déjà présent chez vous depuis
`laravel new`) — à modifier vous-même.

Ouvrez `bootstrap/app.php` et repérez le bloc `->withRouting(...)`. Il
ressemble probablement à ceci :

```php
->withRouting(
    web: __DIR__.'/../routes/web.php',
    commands: __DIR__.'/../routes/console.php',
    health: '/up',
)
```

Ajoutez la ligne `api:` (ordre indifférent, mais gardez `web` en premier
par convention) :

```php
->withRouting(
    web: __DIR__.'/../routes/web.php',
    api: __DIR__.'/../routes/api.php',
    commands: __DIR__.'/../routes/console.php',
    health: '/up',
)
```

Sans cette ligne, `routes/api.php` (livré dans ce ticket) existe bien
sur le disque mais Laravel ne le charge jamais — toute requête vers
`/api/...` retournerait une 404, silencieusement, sans message d'erreur
explicite qui pointerait vers la vraie cause.

## Étape 2 — Installer et configurer Sanctum

```bash
composer require laravel/sanctum
php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider"
php artisan migrate
```

La dernière commande crée la table `personal_access_tokens` (migration
fournie par le package Sanctum lui-même, jamais à écrire à la main).

## Étape 3 — Vérifier `config/sanctum.php` (généré à l'étape 2)

Pour une app Flutter Desktop qui envoie un jeton Bearer (pas de cookies
de session partagés avec un navigateur), aucune configuration
`stateful` particulière n'est nécessaire — `auth:sanctum` sur les routes
(déjà fait dans `routes/api.php`) suffit à valider le jeton Bearer
directement. Rien à modifier dans `config/sanctum.php` pour ce cas
d'usage.

---

## Test réel une fois les 3 étapes faites

```bash
php artisan serve
```

Puis, dans un autre terminal (ou Postman/Insomnia) :

```bash
curl -X POST http://127.0.0.1:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"dg@fermeolouwachegoun.com","password":"AgriERP@2026","device_name":"test-curl"}'
```

Réponse attendue : un JSON avec `token` (chaîne longue commençant par un
nombre suivi de `|`) et `user`. Copiez ce `token`, puis testez un
endpoint protégé :

```bash
curl http://127.0.0.1:8000/api/auth/me \
  -H "Authorization: Bearer VOTRE_TOKEN_ICI"
```

Réponse attendue : les informations de `dg@fermeolouwachegoun.com`. Si vous
obtenez une 401, le jeton n'est pas transmis correctement. Si vous
obtenez une 404 sur `/api/auth/login` lui-même, l'Étape 1
(`bootstrap/app.php`) n'a pas été faite correctement — c'est la cause la
plus probable.

## Côté Flutter — chemin exact confirmé par la session parallèle

L'URL testée côté Flutter est `http://127.0.0.1:8000/agrierp/api` (sous
un sous-dossier `/agrierp`, pas la racine `/api` utilisée dans les
exemples `curl` ci-dessus qui supposent un `php artisan serve` à la
racine). Si votre configuration réelle utilise ce sous-dossier
(probable en environnement cPanel avec plusieurs projets sur un même
domaine), adaptez `APP_URL` dans `.env` en conséquence et vérifiez que
les requêtes Flutter pointent bien vers le même chemin que celui que
`php artisan serve` expose réellement en local (généralement la racine
en développement local, le sous-dossier seulement en hébergement
partagé cPanel réel — les deux environnements n'ont pas forcément le
même chemin, à garder en tête pour ne pas confondre les deux lors des
tests).
