# PRD — Navigation de page en page SANS rechargement (web)
**Statut :** brouillon à valider · **Date :** 2026-10-27 · **Surface :** web (le poste Flutter est déjà une application à écran unique : non concerné)

## 1. Question posée
« Comment passer de page Blade en page, naviguer de page en page sans rechargement ? »

## 2. Réponse courte
Le projet est déjà en **Livewire 3.8** (`livewire/livewire` v3.8.4) : la solution est **`wire:navigate`**, pas AJAX maison, ni Inertia, ni Vue. Chaque écran est déjà un composant Livewire pleine page (`Route::get('/x', Component::class)` + `#[Layout('layouts.app')]`). Livewire intercepte le clic sur un lien, récupère la page voisine en arrière-plan, **remplace le `<body>`**, met à jour le titre et l'URL (historique du navigateur compris), sans recharger le JavaScript ni les feuilles de style. Une barre de progression s'affiche en haut pendant le chargement.

Il est **déjà utilisé une seule fois** (`assistant-demarrage.blade.php`, lien d'étape) : tout le reste de l'application recharge la page entière.

Ce que cela ne fait PAS : ce n'est pas une SPA complète. Chaque navigation fait toujours **une requête serveur** (la page voisine est rendue par PHP) ; on économise le rechargement du navigateur (scripts, styles, polices, clignotement blanc, perte d'état de l'interface), pas l'aller-retour réseau.

## 2 bis. Pourquoi ce n'est pas « ajouter l'attribut partout »
Trois mécanismes du projet reposent sur le rechargement complet. Les ignorer produirait des défauts **sans message d'erreur** :

| Mécanisme actuel | Ce que fait `wire:navigate` | Traitement requis |
|---|---|---|
| **Verrou de session** (`components/verrou-session.blade.php`, `resources/js/verrou.js`) : surcouche + minuterie d'inactivité, posée dans le `<body>`, HORS de `#app-racine` | Le `<body>` est remplacé : la surcouche est détruite puis recréée, son état Alpine (verrouillé, minuterie) repart de zéro à chaque clic | `@persist('verrou')` autour de `<x-verrou-session>` : l'élément et son état survivent. Les écouteurs `window`/`document` de `verrou.js` sont posés une seule fois (module chargé une fois) : **à vérifier**, pas à supposer. |
| **Barre latérale** (`layouts/app.blade.php`, `request()->is()` calculé côté serveur) | Re-rendue à chaque page : l'état d'ouverture (`x-data`) est recréé, la position de défilement du menu est perdue | NE PAS la persister en phase 1 : un élément persisté n'est pas re-rendu, donc **l'entrée active resterait celle de la page précédente**. Lire l'état replié dans `localStorage` (déjà fait : `agrierp_sidebar_hidden`) et restaurer le défilement via `livewire:navigated`. Phase 2 : persister et calculer l'entrée active côté Alpine. |
| **Scripts de l'en-tête** (`beforeinstallprompt`, enregistrement du service worker, `layouts/app.blade.php` l. 16-37) | Les scripts de l'en-tête sont réévalués à chaque navigation : écouteurs en double | Marquer ce `<script>` `data-navigate-once`. |
| **Rappels du jour** (POP1) : `ouvrir($dejaVuSession, $masqueLe)` appelé à l'affichage | Le composant est remonté à chaque page : un aller-retour serveur de plus par navigation | `sessionStorage` empêche déjà la réouverture ; mettre le composant dans `@persist` ou n'appeler `ouvrir` qu'une fois par session de navigateur. |
| **Notifications toast / bandeau flash / installation PWA** | État Alpine perdu entre deux pages (un toast émis juste avant la navigation disparaît) | `@persist` pour `<x-toast-container />` ; les toasts « flash » posés en session sont lus APRÈS la navigation (`livewire:navigated`). |

Constat favorable, mesuré : **aucun `<script>` inline** dans `resources/views/livewire/` ni dans `resources/views/components/`, et aucun `DOMContentLoaded` ; seuls `app.js` / `verrou.js` écoutent `livewire:init`, qui n'est émis **qu'une fois** (pas à chaque navigation). Les composants Alpine (`x-data`) se ré-initialisent seuls après chaque swap.

## 3. Objectifs
- Passer d'un écran à l'autre depuis la **barre latérale, l'Accès Rapide, la barre mobile du bas et les cartes de navigation** sans rechargement complet : plus de flash blanc, polices et styles non rechargés, barre de progression visible.
- **Aucun changement de comportement métier** : mêmes droits (`can:view-…`), mêmes URL, mêmes titres, bouton « Retour » du navigateur correct.
- **Le verrou de session continue de fonctionner** : verrouillage par inactivité pendant et après des navigations, déverrouillage, déconnexion à 10 échecs.

## 4. Hors périmètre
- Le poste Flutter (déjà sans rechargement).
- Les liens qui DOIVENT recharger : `a[download]`, exports PDF/Excel, `target="_blank"`, connexion / déconnexion, pages publiques, tout lien vers un fichier (`/storage/…`).
- Un vrai mode hors ligne du navigateur : la PWA reste volontairement étroite (`CLAUDE.md`, « This PWA does not make AgriERP work offline »).
- Inertia / Vue / React : aucun gain ici, une réécriture des 97 composants.

## 5. Exigences et critères d'acceptation

### P0 — socle
- **R1. Lien de navigation = `wire:navigate`** sur : `components/sidebar-link.blade.php`, les liens de l'Accès Rapide et de la barre mobile (`layouts/app.blade.php`), `nav-card`, `tab-page` quand ses onglets sont des pages, les cartes d'accès des hubs.
  - [ ] Cliquer une entrée de la barre latérale ne recharge pas la page (le `window` de la page précédente reste en vie : une variable posée en console survit à la navigation).
  - [ ] L'URL, le titre de l'onglet et l'entrée active de la barre latérale correspondent à la page affichée ; « Retour » et « Avancer » du navigateur fonctionnent.
  - [ ] Les liens d'export, de téléchargement et `target="_blank"` n'ont PAS `wire:navigate`.
- **R2. Éléments persistants** (`@persist`) : surcouche de verrouillage, conteneur de toasts, invitation PWA. La barre latérale n'est PAS persistée en phase 1 (entrée active).
  - [ ] Verrouiller, naviguer (la surcouche reste), déverrouiller : la page affichée est celle de la dernière navigation, saisie Livewire non enregistrée comprise.
  - [ ] La minuterie d'inactivité n'est pas réinitialisée par une navigation seule (une navigation est une activité : elle la **remet** à zéro, comme un clic) et n'est pas dupliquée (un seul verrouillage, pas deux).
- **R3. Scripts de l'en-tête réévalués** : le script PWA reçoit `data-navigate-once`.
  - [ ] Après 5 navigations, `beforeinstallprompt` n'a qu'un écouteur.
- **R4. Barre de progression** : activée (défaut Livewire), couleur de la charte (`#052e16`/émeraude) ; publier `config/livewire.php` (`navigate.show_progress_bar`, `progress_bar_color`) — l'avertissement « jamais `vendor:publish` » du projet vise Sanctum et Spatie, pas Livewire.

### P0 — sécurité et erreurs (cas qui ne doivent jamais « marcher en silence »)
- **R5. Session expirée / compte désactivé** : la requête de navigation reçoit une redirection vers `/login` ; `wire:navigate` la suit ; la page de connexion s'affiche entièrement (rechargement complet accepté ici).
  - [ ] Test Dusk : session supprimée côté serveur, clic sur une entrée → écran de connexion, pas une page blanche ni un message technique.
- **R6. Session verrouillée (HTTP 423 / redirection `/verrouillage`)** : un clic de navigation sous verrou ne doit rien montrer de la page cible.
  - [ ] Surcouche active : les clics sont inertes (déjà le cas) ; si la requête part quand même, la réponse 423 ouvre la surcouche, pas une fenêtre d'erreur.
- **R7. Droits** : `can:view-…` refuse (403) → la page 403 s'affiche par rechargement complet ; **jamais** le contenu d'une page interdite, même une fraction de seconde.
  - [ ] `SidebarRbacNavigationTest` (Dusk) passe sans modification de ses attentes.
- **R8. Réseau coupé pendant une navigation** : retour automatique de Livewire au chargement classique ; le service worker sert alors `offline.html` (comportement actuel). 
  - [ ] Test manuel : couper le réseau, cliquer ; la page « hors ligne » s'affiche, pas un écran figé.

### P1 — confort
- **R9. Préchargement au survol** (`wire:navigate.hover`) sur la barre latérale : la page se charge ~200 ms plus tôt. À mesurer avant de généraliser (charge serveur : une requête par survol).
- **R10. Positionnement du défilement** du menu latéral conservé (`livewire:navigated`).

## 6. Risques et vérifications nécessaires AVANT de livrer
1. **Suite Dusk** (9 parcours) : jamais lancée dans cet environnement ; tout ce qui touche Alpine, z-index ou superpositions exige un run réel (règle du projet). Les tests Feature (`Livewire::test()`) **ne voient aucun de ces défauts** : ils exécutent le serveur sans JavaScript.
2. **Composants à état dans le `<body>` du layout** : `x-pwa-install`, `x-toast-container`, `x-flash-toast`, `livewire:shared.bandeau-exercice`, `livewire:shared.rappels-du-jour`, notifications de l'en-tête (cloche) — chacun doit être classé « persisté » ou « re-rendu » et testé.
3. **Pages à JavaScript propre** (graphiques, `Chart`, sélecteurs de date, `window.print`) : à parcourir page par page ; un script qui suppose « la page vient d'être chargée » ne se relance pas.
4. **Fuites mémoire** : un `addEventListener` sur `window`/`document` posé par une page s'accumule à chaque navigation (cas du script PWA, R3). Recenser et rattacher à `livewire:navigate` / `Alpine.cleanup`.
5. **Version des ressources** : après un déploiement, une page chargée avant mise à jour qui navigue vers une page servie par le nouveau code → Livewire détecte le changement d'actifs Vite (`data-navigate-track`) et force un rechargement complet : comportement attendu, à ne pas contrarier.

## 7. Plan proposé (un ticket par étape, une étape = un déploiement)
- **NAV-1** — Socle : `@persist`, `data-navigate-once`, config Livewire, `wire:navigate` sur la barre latérale SEULE + test Dusk dédié (clic, URL, titre, Retour, entrée active, verrou).
- **NAV-2** — Accès Rapide, barre mobile, cartes de navigation, onglets des hubs ; recensement des scripts de page (risque 3 et 4).
- **NAV-3** — Persistance de la barre latérale (entrée active calculée côté Alpine) et préchargement au survol ; mesure avant/après.

## 8. Questions ouvertes
- **N-Q1.** Le client accepte-t-il que le **premier affichage** reste un chargement complet (connexion → tableau de bord) ? C'est inévitable.
- **N-Q2.** Faut-il garder une saisie Livewire non enregistrée quand l'utilisateur change de page ? Aujourd'hui elle est perdue (rechargement) ; avec `wire:navigate` elle l'est toujours, **sauf si** la page est persistée. Décision proposée : rien ne change (une confirmation « modifications non enregistrées » est un autre ticket).
- **N-Q3.** Mesure de gain attendue : à relever sur la machine de la ferme (connexion intermittente) avant NAV-2 ; si le gain est faible, s'arrêter à NAV-1.
