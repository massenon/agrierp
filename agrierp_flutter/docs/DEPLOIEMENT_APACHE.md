# Déploiement Apache — Poste Web Flutter (PWA)

**LogiAgriERP · Ferme École OLOUWACHEGOUN · ticket PWA-2-fin · 11/11/2026**

Ce document décrit la configuration Apache minimale pour servir la Progressive Web App Flutter
(`flutter build web --release`) avec les en-têtes de cache optimaux et les en-têtes de sécurité
requis par les navigateurs modernes.

> ⚠️ Ne contient aucun secret, aucun mot de passe, aucune clé API.
> Le fichier `.env` Laravel ne doit jamais être versionné (règle monorepo).

---

## Contenu du build

Après `flutter build web --release`, le dossier `build/web/` contient :

| Fichier / dossier | Rôle |
|---|---|
| `index.html` | Point d'entrée unique de la SPA |
| `main.dart.js` | Code Dart compilé (JavaScript) |
| `flutter_bootstrap.js` | Amorçage du moteur Flutter |
| `flutter_service_worker.js` | Service Worker (cache offline) |
| `assets/` | Polices, images, manifeste Drift |
| `canvaskit/` | Moteur de rendu (CanvasKit WASM) |
| `manifest.json` | Manifeste PWA |
| `favicon.png` | Icône |

Tous ces fichiers sont **embarqués localement** : aucune ressource n'est chargée depuis un CDN
externe (garde vérifiée par le workflow `.github/workflows/flutter-web-ci.yml`).

---

## Configuration `.htaccess` recommandée

Copier ce fichier à la racine du dossier servi par Apache (là où se trouve `index.html`) :

```apache
# ──────────────────────────────────────────────────────────────────────────────
# LogiAgriERP — poste web Flutter (PWA)
# Cache-Control optimisé pour Flutter build --release
# ──────────────────────────────────────────────────────────────────────────────

# Activer le moteur de réécriture (nécessaire pour la SPA)
<IfModule mod_rewrite.c>
    RewriteEngine On

    # Rediriger vers HTTPS
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

    # Toutes les routes inconnues → index.html (SPA Flutter)
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule ^ /index.html [L]
</IfModule>

# ──────────────────────────────────────────────────────────────────────────────
# Cache-Control : immutable pour les assets versionnés
#
# Flutter build --release ajoute un hash de contenu dans le nom des fichiers
# (ex. main.dart.js?v=abc123 ou flutter_service_worker.js?v=…). Ces fichiers
# ne changent jamais à URL identique : on peut les marquer `immutable`.
#
# ⚠️ index.html et flutter_service_worker.js sont toujours rechargés (no-cache)
# car ils portent les références vers les assets versionnés.
# ──────────────────────────────────────────────────────────────────────────────
<IfModule mod_headers.c>
    # index.html et service worker : toujours revérifier
    <FilesMatch "^(index\.html|flutter_service_worker\.js|manifest\.json)$">
        Header set Cache-Control "no-cache, no-store, must-revalidate"
        Header set Pragma "no-cache"
        Header set Expires "0"
    </FilesMatch>

    # Assets Flutter (JS, WASM, fonts, images) : immutable 1 an
    # Sûr car Flutter intègre un hash dans le nom ou l'URL de requête.
    <FilesMatch "\.(js|wasm|ttf|otf|woff|woff2|png|jpg|jpeg|svg|ico|json)$">
        Header set Cache-Control "public, max-age=31536000, immutable"
    </FilesMatch>

    # ──────────────────────────────────────────────────────────────────────────
    # En-têtes de sécurité requis par SharedArrayBuffer (WASM multi-thread)
    # Nécessaires uniquement si --wasm est activé (voir workflow flutter-web-ci).
    # ──────────────────────────────────────────────────────────────────────────
    # Header set Cross-Origin-Embedder-Policy "require-corp"
    # Header set Cross-Origin-Opener-Policy "same-origin"

    # En-têtes de sécurité généraux
    Header set X-Content-Type-Options "nosniff"
    Header set X-Frame-Options "SAMEORIGIN"
    Header set Referrer-Policy "strict-origin-when-cross-origin"
</IfModule>

# ──────────────────────────────────────────────────────────────────────────────
# Types MIME — ajouter wasm si mod_mime est activé
# ──────────────────────────────────────────────────────────────────────────────
<IfModule mod_mime.c>
    AddType application/wasm .wasm
    AddType font/woff2 .woff2
</IfModule>

# ──────────────────────────────────────────────────────────────────────────────
# Compression gzip / brotli
# ──────────────────────────────────────────────────────────────────────────────
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/css application/javascript application/json
    # Ne pas compresser les fichiers déjà compressés ou binaires
    SetEnvIfNoCase Request_URI \.(?:gif|jpg|jpeg|png|wasm)$ no-gzip
</IfModule>
```

---

## Vérification après déploiement

```bash
# Vérifier l'en-tête Cache-Control sur un asset JS
curl -I https://agrierp.fermeolouwachegoun.com/main.dart.js \
  | grep -i cache-control
# Attendu : Cache-Control: public, max-age=31536000, immutable

# Vérifier que index.html n'est pas mis en cache
curl -I https://agrierp.fermeolouwachegoun.com/ \
  | grep -i cache-control
# Attendu : Cache-Control: no-cache, no-store, must-revalidate
```

---

## Activation de WebAssembly (option, désactivée par défaut)

Le workflow CI compile en JavaScript standard (`flutter build web --release`).
Pour activer WASM (`--wasm`) :

1. Vérifier que la version Dart dans `.fvmrc` est ≥ 3.3 (3.47.7 → Dart 3.13.5 : ✓).
2. Activer `wasm-opt` sur le serveur de build (paquet `binaryen`).
3. Décommenter `--wasm` dans `.github/workflows/flutter-web-ci.yml`.
4. Décommenter les en-têtes `Cross-Origin-Embedder-Policy` et `Cross-Origin-Opener-Policy`
   dans le `.htaccess` ci-dessus (requis par `SharedArrayBuffer`).
5. Vérifier la compatibilité avec Safari (support WASM threads partiel jusqu'en 2025).

---

## Prérequis Apache

| Module | Rôle |
|---|---|
| `mod_rewrite` | Routage SPA (toutes les routes → index.html) |
| `mod_headers` | Cache-Control, en-têtes de sécurité |
| `mod_mime` | Type MIME `.wasm` |
| `mod_deflate` | Compression gzip (optionnel mais recommandé) |

Activer les modules manquants :

```bash
sudo a2enmod rewrite headers mime deflate
sudo systemctl reload apache2
```
