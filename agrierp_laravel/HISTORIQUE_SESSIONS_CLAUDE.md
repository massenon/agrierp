# Historique des sessions Claude Code — AgriERP

> **À quoi sert ce document.** Il raconte, dans l'ordre, tout ce qui a été fait
> avec Claude Code sur AgriERP depuis la commande `/init` : ce qui a été
> demandé, ce qui a été réellement trouvé, **quelles hypothèses se sont
> révélées fausses**, et ce qui reste ouvert.
>
> Ce n'est pas un doublon de `README_SPRINT0.md`. Celui-là est le journal
> ticket par ticket, exhaustif et append-only. Celui-ci est le **fil narratif**
> destiné à une nouvelle session qui reprend le projet après une coupure :
> à lire en premier, en dix minutes, avant de toucher quoi que ce soit.
>
> Période couverte : **20 → 24 août 2026**. Tickets **15.1 à 15.8**.

---

## 0. La carte des lieux

Trois dépôts, à ne jamais confondre.

| Dépôt | Chemin | Contenu |
|---|---|---|
| **Application** | `C:\laragon\www\agrierp` | Le vrai Laravel 12 + Livewire 3. C'est là que tourne le logiciel. |
| **Prototype + docs** | `C:\Projects\agrierp_laravel` | Le prototype HTML (97 écrans), la base documentaire (60 fichiers), **et le manuel PDF** |
| **Poste Flutter** | ailleurs | Client bureau hors-ligne (Drift/SQLite), dialogue par `/api/sync/*` |

⚠️ **Le dossier `agrierp_laravel` ne contient aucun Laravel**, malgré son nom.
C'est le premier piège du projet.

Chaque dépôt a son propre `CLAUDE.md`. Celui de l'application fait autorité
sur tout ce qui touche au code.

### Qui est qui

| Structure | Rôle |
|---|---|
| **PAEB** — Projet d'Appui à l'Entrepreneuriat au Bénin | Maîtrise d'ouvrage |
| **Cabinet FAGUEZ SARL** | Accompagnement des PME |
| **Dr MASSENON Rhodes**, Docteur en Génie Logiciel et IA | Éditeur du logiciel |

Contact éditeur : `rarhodes06@gmail.com`, `contact@massenonrhodes.com`,
+229 01 51 33 50 40 / 01 97 31 24 37.

---

## 1. Session `/init` — lire l'application réelle

**Demande** : lire `C:\laragon\www\agrierp` et produire un `CLAUDE.md`.

**Fait** : exploration complète du dépôt Laravel, puis rédaction de
`C:\laragon\www\agrierp\CLAUDE.md`.

### ⚠️ Cinq idées reçues démenties par le code

Le `CLAUDE.md` du dépôt de documentation décrivait une application qui
n'existe pas. Vérifié fichier par fichier :

| Ce qui était écrit | Ce qui est vrai |
|---|---|
| « Clean Architecture obligatoire : `app/Domain`, `app/Application`, `app/Infrastructure` » | **Aucun de ces dossiers n'existe.** L'organisation est plate : `app/Actions/`, `app/Services/`, `app/Models/`, `app/Livewire/{Module}/` |
| « Réutiliser `agri-pagination.blade.php` » | **Ce composant n'existe nulle part** |
| « `#[Computed]` est utilisé » | **Zéro occurrence** dans tout le code |
| « Patron hub-iframe » | Vrai du prototype seulement. Le Laravel compose des **composants Livewire imbriqués**, jamais d'iframe |
| « Colonnes `device_id` / `sync_status` sur les tables synchronisables » | Absentes de `sales`. La sûreté hors-ligne vient des **clés UUID partout** + des règles différenciées de `SyncController` |

**Découverte opérationnelle importante** : `php artisan test` **sans argument
échoue**. `phpunit.xml` déclare une suite `tests/Unit` qui n'a jamais existé.
Toujours passer `--testsuite=Feature`.

**Ce qu'il faut retenir** : sur ce projet, la documentation ancienne n'est pas
fiable sur le code. Vérifier avant de citer.

---

## 2. Le manuel d'utilisation (ticket 15.3)

**Demande** : un manuel d'utilisation du logiciel, en PDF, « très propre »,
avec captures annotées, flèches, numérotation, encadrés à icônes.

**Décisions prises avec le client** : manuel **complet** (tous les modules),
pour un lecteur **débutant complet**, **avec** les règles métier invisibles à
l'écran expliquées en encadrés.

### La méthode, qui vaut d'être conservée

Rien n'a été rédigé de mémoire.

1. **Captures réelles** — Chrome piloté par script contre l'application
   lancée, sur la vraie base (383 ventes, 27 produits, 8 bandes). 122 puis
   166 captures : écrans, onglets, fenêtres modales, zones sous la ligne de
   flottaison.
2. **Libellés extraits du DOM**, jamais retapés. C'est ce qui garantit que
   les noms de boutons et de champs cités sont exacts.
3. **Flèches positionnées au pixel** — le `getBoundingClientRect()` réel de
   chaque élément visé a été relevé pendant la capture, puis converti en
   pourcentages.
4. **Vérification du rendu** — pages du PDF re-rendues en image et relues.

### Ce que la relecture a corrigé

- Le tableau du menu latéral **inventait des sections** (« Personnel »,
  « Rapports », « Comptabilité & finance »). Les dix vraies sections ont été
  relevées dans `layouts/app.blade.php`.
- **Quatre captures d'onglets montraient un autre écran** : le clic par
  libellé atteignait un lien du menu latéral avant l'onglet visé. Recapturées
  avec un clic restreint à la zone de contenu.
- Une **page presque vide** (un paragraphe orphelin) et une **collision** dans
  le pied de couverture, vues seulement en relisant les pages rendues.

### Décisions de contenu

- **Annexe E liste les quatre comptes de démonstration sans leur mot de
  passe**, remis séparément par l'administrateur. Un manuel qui circule dans
  la ferme n'est pas le bon support pour un identifiant. Validé par le client.
- La **section 11.3 « Qui fait quoi »** donne au lecteur la règle : *un écran
  qui se comporte mal relève de l'éditeur ; un chiffre réglementaire à valider
  relève du cabinet d'accompagnement*.

**État** : 92 pages, 56 figures, 170 signets. Sources dans `manuel/`,
reconstruction par `py build.py`. **Ne jamais éditer le PDF à la main.**

---

## 3. La mise en ligne (ticket 15.1) — le moment le plus important

**Signalement du client** : « le site est en ligne, la racine affiche un index
off, et toute URL renvoie 404 ».

### Le diagnostic, mené par requêtes HTTP réelles

| Requête | Réponse | Lecture |
|---|---|---|
| `/` | 200 | **Listing de répertoire Apache**, pas l'application |
| `/login` | 404 | 404 **du serveur**, pas de Laravel |
| `/public/index.php/login` | 200 | **L'application fonctionne parfaitement** |
| `/public/login` | 404 | **Aucune réécriture d'URL** |

**Deux défauts indépendants**, souvent confondus :

1. **La racine du document pointait sur la racine du projet**, pas sur
   `public/`. Défaut de configuration chez l'hébergeur.
2. **`public/.htaccess` n'existait pas dans le projet.** Vérifié :
   `find . -name .htaccess` ne retournait **aucun** fichier. Défaut de code.

⚠️ **Pourquoi personne ne l'avait vu** : le développement se fait par
`php artisan serve`, dont le routeur interne **ne lit jamais `.htaccess`**.
Le défaut ne pouvait apparaître qu'au premier vrai serveur Apache. Même
famille d'angle mort que `tests/TestCase.php` (14.1) et
`app/Http/Controllers/Controller.php` (Sprint 12) : le projet ayant été livré
en overlay, des fichiers « toujours présents » ne l'étaient pas.

### 🛑 La fuite de secrets

`agrierp.zip` (72 Mo) était à la racine servie, **téléchargeable publiquement**.
Contenu vérifié dans l'archive locale correspondante :

```
.env                 680 octets   ← identifiants MySQL + APP_KEY
.env.dusk.local     1072 octets
```

Le `.env` du serveur était bien bloqué (403) — **mais pas l'archive qui le
contient**. `storage/logs/laravel.log` était également téléchargeable, et la
racine affichait la liste cliquable de `app/`, `config/`, `database/`,
`routes/`, `vendor/`.

### Corrigé

- `public/.htaccess` — fichier canonique Laravel 12.
- `.htaccess` de racine — filet de sécurité **explicitement documenté comme
  tel** dans son propre en-tête : coupe le listing, refuse les fichiers
  sensibles, renvoie tout dans `public/`.

⚠️ Un défaut a été rattrapé dans ce filet avant livraison : `storage` figurait
d'abord dans la liste des dossiers bloqués, ce qui aurait cassé l'affichage des
**photos de reçus** (`public/storage` est un lien symbolique). Retiré.

---

## 4. L'éditeur du logiciel (tickets 15.2, 15.7, 15.8)

Trois passes successives, parce que la première était incomplète — et c'est
instructif.

1. **15.2** — le client demande que l'éditeur soit **Dr MASSENON Rhodes**.
   Remplacement de « FAGUEZ SARL » partout où l'éditeur était nommé.
   Une occurrence a été **volontairement conservée et signalée** :
   `bareme-its.blade.php` disait « Faites-le confirmer par le Cabinet FAGUEZ ».
   Signalée comme un possible oubli, avec demande d'arbitrage.

2. **15.7** — le client précise : **Cabinet FAGUEZ est le cabinet qui
   accompagne les PME dans le cadre du PAEB**. L'arbitrage est clos : la
   mention du barème était **correcte depuis le début**. Un barème fiscal est
   validé par le cabinet, jamais par l'auteur du code.
   PAEB et FAGUEZ sont rétablis dans le manuel, aux côtés de l'éditeur.

3. **15.8** — même harmonisation dans l'application, à la demande du client :
   connexion, pages publiques, Aide & À Propos, plus un bloc
   **« Qui contacter ? »** sur l'écran de contact.

### ⚠️ La leçon

Le ticket 15.2 avait **effacé le cabinet des pieds de page** sans que personne
ne s'en aperçoive pendant deux tickets. Un crédit manquant ne casse rien,
n'émet aucune erreur, et ne se voit que si quelqu'un lit attentivement un pied
de page. D'où `tests/Feature/CreditsProjetTest.php`, qui verrouille les trois
noms sur cinq écrans.

---

## 5. PWA et polices locales (ticket 15.4)

**Demande** : sortir Google Fonts, et rendre l'application installable avec une
invitation réductible en bas à gauche.

### Les polices

Les deux layouts chargeaient Inter depuis `fonts.googleapis.com`. Sur une ferme
dont la liaison tombe, chaque chargement attendait un serveur injoignable avant
d'abandonner.

⚠️ **Découverte qui a changé la mise en œuvre** : l'intention était de
télécharger cinq fichiers, un par graisse. Vérification faite auprès de l'API
Google — `wght@400;500;600;700;800` et `wght@100..900` renvoient **exactement
la même URL**. Inter est une police **variable**.

**Résultat : 2 fichiers au lieu de 10.** `Inter-latin.woff2` (48 Ko) toujours,
`Inter-latin-ext.woff2` (85 Ko) seulement si la page en a besoin.

Le `@font-face` déclare `font-weight: 100 900`. Déclarer `400` ferait
**synthétiser** le gras par le navigateur, et les titres 700/800 seraient
déformés.

### Le PWA

Manifeste, service worker, page hors-ligne, six icônes dérivées du favicon
officiel de la ferme (les versions *maskable* gardent 20 % de marge, sinon
Android rogne le logo dans un cercle et coupe le texte).

⚠️ **Le service worker est volontairement étroit.** Trois règles écrites en tête
de `sw.js` :

1. **Seuls les `GET`** sont interceptés — Livewire pilote tout par `POST`.
2. **Aucune page HTML authentifiée n'est stockée** — un cache navigateur n'est
   pas cloisonné par utilisateur ; un tableau de bord pourrait réapparaître
   après déconnexion sur le poste partagé du comptoir.
3. **Seuls les fichiers statiques** sont mis en cache.

**Ce PWA ne rend pas AgriERP utilisable hors ligne, et ce n'est pas un
manque** : le travail déconnecté est le rôle du poste dédié. Un cache qui
prétendrait encaisser des ventes créerait deux sources de vérité.

**La fenêtre est en bas à gauche.** Pas à droite : les toasts y sont, en
z-index 200, et le ticket 14.28 avait déjà corrigé des toasts interceptant les
clics du bouton « Valider la Vente ».

**iOS n'a pas `beforeinstallprompt`** — cette branche affiche la marche à
suivre manuelle plutôt qu'un bouton mort.

### ⚠️ Le piège de production anticipé

**Apache ne connaît pas l'extension `.webmanifest`** : il la sert en
`text/plain`, le navigateur ignore le manifeste **en silence**, et
l'application cesse d'être installable sans aucune erreur. Invisible en local,
`artisan serve` renvoyant le bon type. D'où `AddType application/manifest+json`
dans `public/.htaccess`.

---

## 6. Optimisation Lighthouse (tickets 15.5, 15.6)

Menés par une autre session. Durées de cache dans `public/.htaccess`, et
allègement de la fonte Material Symbols de **3,87 Mo à 37 Ko** par
sous-ensemble. `sw.js` passé en `agrierp-v2` — nécessaire, car les postes déjà
venus portaient l'ancienne fonte dans `agrierp-v1-statique` et auraient
continué à la lire depuis leur disque.

---

## 7. Contrôle visuel final (24 août)

Serveur relancé le temps du contrôle. Les deux écrans sont conformes, mais
le coup d'œil a trouvé ce que les tests ne voyaient pas : le pied de connexion
coupait « Édité par Dr / **MASSENON Rhodes** ». Corrigé par espaces
insécables.

⚠️ **Cette correction a fait échouer mon propre test** — et c'était le test qui
avait tort : il cherchait littéralement `MASSENON Rhodes` dans un HTML
contenant désormais `&nbsp;`. Le nom était bel et bien affiché. Le test
**normalise** maintenant les entités avant comparaison : il compare le sens,
pas les octets.

---

## 8. État du déploiement au 24 août 2026

Sondé de l'extérieur, pas supposé.

| Geste (ticket 15.1) | État |
|---|---|
| Supprimer `agrierp.zip` | ⚠️ **invérifiable depuis l'extérieur** |
| Uploader les deux `.htaccess` | ✅ fait, fonctionnel |
| Racine du document → `public/` | ❌ **pas fait** |
| Changer mot de passe MySQL + `APP_KEY` | ❓ inconnu |

**Sur le zip** : `/agrierp.zip` renvoie 404, mais **ce n'est pas une preuve de
suppression** — le `.htaccess` de racine redirige tout dans `public/`, donc un
fichier resté à la racine devient injoignable qu'il existe ou non. **À vérifier
sur le disque.**

**Sur la racine du document** : preuve que ce n'est pas fait —
`/public/robots.txt` répond 206. Sous une racine correcte, ce chemin
deviendrait `public/public/robots.txt` → 404. Le site tient donc **uniquement**
grâce au `.htaccess` ; un redéploiement qui l'écrase remet tout à nu.

### ⚠️ Le site en ligne fait tourner le code du ticket 15.4

| | En ligne | En local |
|---|---|---|
| CSS compilé | `app-D_IdB1ks.css` | `app-bbLxz1pl.css` |
| Service worker | `agrierp-v1` | `agrierp-v2` |
| Police d'icônes | **3 960 036 o** | **37 432 o** |

Les tickets **15.5 à 15.8 ne sont pas déployés**. L'allègement de la fonte
n'est pas en ligne, et le `sw.js` étant resté en `v1`, les postes déjà venus
gardent les 3,9 Mo en cache.

À téléverser : `public/build/`, `public/assets/fonts/`, `public/sw.js`, les
vues modifiées, puis `php artisan view:clear`.

---

## 9. Ce qui reste ouvert

1. **Vérifier sur le disque** que `agrierp.zip` est supprimé du serveur.
2. **Racine du document → `public/`** (cPanel → Domaines).
3. **Changer le mot de passe MySQL** et régénérer `APP_KEY` si celle du
   serveur est identique à celle de l'archive.
   Coût mesuré : trois colonnes chiffrées à ressaisir dans *Paramètres →
   Données de l'Entreprise* — `smtp_password_encrypted`,
   `twilio_auth_token_encrypted`, `vonage_api_secret_encrypted`. Aucune autre
   donnée chiffrée dans l'application (recherche explicite de `Crypt::` et
   `encryptString` : zéro résultat).
4. **Déployer les tickets 15.5 à 15.8.**
5. Supprimer `node_modules/` et `tests/` du serveur.
6. **Ajouter au manuel la section « installer l'application »** — le PWA
   existe mais n'est pas documenté au chapitre 1.

---

## 10. Pièges d'environnement, à connaître avant de perdre du temps

- **L'Apache local tourne en PHP 8.1.10**, le projet exige ^8.3. `agrierp.test`
  renvoie donc **500** — préexistant, sans rapport avec ce que vous venez de
  changer. Développer sur `php artisan serve --port=8002`.
- **Tuer `php artisan serve` ne libère pas le port** : il lance un enfant
  `php -S 127.0.0.1:8002` qui survit à son parent.
- **Livewire a besoin d'un instant pour s'hydrater** avant qu'une connexion
  scriptée fonctionne. Un `sendKeys` trop tôt soumet des identifiants vides et
  reste silencieusement sur `/login`. Attendre, puis vérifier que l'URL a
  changé.
- **La connexion web est limitée à 5 tentatives / 15 min** par identifiant+IP.
  Des connexions scriptées répétées peuvent vous bloquer.
- **Cliquer par libellé** : exclure d'abord `aside` et `header`. Un onglet
  nommé « Créances » ou « Commandes » existe aussi dans le menu latéral, et le
  clic part ailleurs sans rien signaler.
- **Les heredocs bash contenant du Python accentué** échouent régulièrement
  sur cette machine. Écrire le script dans un fichier, puis l'exécuter.

---

## 11. Conventions de travail à respecter

- **Tout est en français** : prose, libellés, commentaires, journaux.
- **`README_SPRINT0.md` existe en deux exemplaires** qui doivent rester
  **identiques au bit près** — ici et dans l'application. Comparer les
  empreintes avant et après chaque ajout, jamais à l'œil.
- **Un ticket = une session.** Annoncer le plan avant d'écrire du code.
- **Écrire le test qui aurait attrapé le défaut.** Les deux tests nés de ces
  sessions — `PwaEtPolicesLocalesTest` et `CreditsProjetTest` — verrouillent
  précisément des défauts qui **n'émettent aucune erreur** : un manifeste sans
  icône 192, un crédit disparu d'un pied de page.
- **Dire ce qui n'a pas été vérifié.** Plusieurs entrées de
  `README_SPRINT0.md` portent une réserve explicite ; c'est une pratique du
  projet, pas une faiblesse.

---

*Document tenu à jour à chaque session. Dernière mise à jour : 24 août 2026,
après le ticket 15.8.*
