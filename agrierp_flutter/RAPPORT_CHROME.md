# RAPPORT CHROME — barre latérale (1B) et barre supérieure (1C)

Généré par `outils/audit_chrome.py` (ticket AF1.1). Sources : `prototype_html/assets/js/sidebar.js`, l'en-tête `<header>` des pages (identique sur 97 pages), `common.js` §8 ; côté poste `lib/main.dart` (`_BarreLaterale.arborescence`), `lib/core/widgets/barre_superieure.dart`, `lib/core/auth/permissions_poste.dart`.

> ⚠️ **Mesuré** = extrait des deux sources et comparé par programme. **Relevé** = valeur lue dans le source, jamais vue à l'écran : aucun rendu n'a été comparé (phase 1D, à faire avec un navigateur et le poste lancé). Gravité : *bloquant* = une tâche de l'utilisateur est impossible ; *majeur* = un élément du prototype manque ou diffère structurellement ; *mineur* = écart de style.

## 1B.1 Groupes et entrées (mesuré)

| | Prototype | Poste |
|---|---|---|
| groupes | 10 | 10 (+ `POSTE`, hors maquette, dit) |
| entrées | 19 | 19 |
| ordre des groupes | — | identique |

| Groupe | Entrée | Icône proto | Icône poste | Page → écran | Verdict |
|---|---|---|---|---|---|
| PILOTAGE | Tableau de Bord | dashboard | dashboard | dashboard.html | ✔ |
| PRODUCTION ÉLEVAGE & SOINS | Gestion Élevage | pets | pets | gestion-elevage.html | ✔ |
| PRODUCTION ÉLEVAGE & SOINS | Dashboard Élevage | dashboard | dashboard | elevage-dashboard.html | ✔ |
| PRODUCTION ÉLEVAGE & SOINS | Suivi Reproduction | favorite | favorite | suivi-reproduction.html | ✔ |
| PRODUCTION ÉLEVAGE & SOINS | Soins et vaccins | vaccines | vaccines | soins-vaccins-hub.html | ✔ |
| PRODUCTION ÉLEVAGE & SOINS | Paramètres Élevage | tune | tune | parametres-elevage.html | ✔ |
| VENTES FERME | Ventes & Devis | point_of_sale | point_of_sale | ventes-devis.html | ✔ |
| VENTES FERME | Clients et Créances | payments | payments | creances-clients.html | ✔ |
| ACHATS & CHARGES | Achats & Commandes | local_shipping | local_shipping | achats-commandes.html | ✔ |
| ACHATS & CHARGES | Fournisseurs | contact_page | contact_page | fournisseurs.html | ✔ |
| ACHATS & CHARGES | Saisie Dépenses | receipt | receipt | saisie-depenses.html | ✔ |
| STOCKS & PRODUITS | Gestion Stocks | inventory_2 | inventory_2 | gestion-stocks.html | ✔ |
| STOCKS & PRODUITS | Catalogue Produits | category | category | catalogue-produits.html | ✔ |
| FACTURATION | Facturation & MeCeF | receipt_long | receipt_long | facturation.html | ✔ |
| RESSOURCES HUMAINES | Personnel & Stages | badge | badge | personnel-stages.html | ✔ |
| ADMINISTRATION | Administration & Document | folder_shared | folder_shared | administration.html | ✔ |
| COMPTABILITÉ & ADMIN | Comptabilité | account_balance | account_balance | comptabilite-hub.html | ✔ |
| COMPTABILITÉ & ADMIN | Paramètres Général | settings | settings | parametres-hub.html | ✔ |
| EDITIONS | Rapports & Exports | picture_as_pdf | picture_as_pdf | rapports-exports.html | ✔ |

**19 entrées conformes, 0 écarts.**

## 1B.2 Visibilité par rôle (mesuré)

Le prototype masque un GROUPE entier selon `data-role-group`. Le poste rend TOUS les groupes à tous les rôles et **estompe** les entrées que `PermissionsPoste` refuse (`embarque = ecrans.contains(ecran)`, `main.dart`) — décision du client consignée dans le docblock de `arborescence`.

| Rôle | Groupes visibles (prototype) | Entrées visibles au prototype mais REFUSÉES par `RBAC_PAGE_MAP` | Entrées masquées au prototype mais AUTORISÉES |
|---|---|---|---|
| admin | 10 / 10 | — | — |
| caissier | 3 / 10 | — | — |
| animalier | 2 / 10 | Suivi Reproduction, Paramètres Élevage | — |
| comptable | 3 / 10 | Comptabilité, Paramètres Général | — |

⚠️ **Le prototype porte deux représentations des droits qui ne coïncident pas** : la barre (`data-role-group`, par groupe) et `RBAC_PAGE_MAP` (par page). Un rôle voit des entrées que la carte lui refuse, et inversement. Ce n'est pas un défaut du poste : c'est une contradiction du prototype, à consigner avec les arbitrages de la phase 5 — **non tranchée ici**.

## 1B.3 Éléments de `sidebar.js` autres que la liste (mesuré par recherche dans le source Dart)

| Élément du prototype | Présent au poste | Gravité |
|---|---|---|
| En-tête « Agri**ERP** » (ERP en `accent-yellow`) + sous-titre « Ferme École Olouwachegoun » | **non** — le poste écrit 'AgriERP' d'une seule couleur, sans sous-titre | mineur |
| Bouton « Synchroniser » jaune en pied de barre | oui | — |
| Bloc utilisateur (nom + rôle en capitales) | oui | — |
| Menu flottant droit (`right-floating-menu`, barre repliée) | **non** — barre repliée : le poste ne propose pas les 6 raccourcis | majeur |
| Bouton rond « Accès rapide Élevage & Modules » + panneau de 10 raccourcis | **non** — aucun accès rapide aux fiches d'espèce hors « Gestion Élevage » | majeur |
| Bouton rond « Visite guidée de cette page » (`startTourGuide`) | **non** — absent, non documenté | majeur |

## 1B.4 Dimensions et style (relevé — non rendu)

| Propriété | Prototype (Tailwind → px) | Poste (source Dart) | Gravité |
|---|---|---|---|
| largeur de la barre | `w-72` = 288 | 240 | majeur |
| taille du libellé d'entrée | `text-[13px]` = 13 | AgriTypography.xs = 13.6 | mineur |
| icône d'entrée | `text-[20px]` = 20 | 18 | mineur |
| titre de groupe | `text-[10px]` gras, `tracking-wider`, blanc/40 | fontSize 10, gras, letterSpacing 0.8, white38 | mineur |
| couleur du libellé | `text-white/90` | white (100 %) | mineur |
| padding d'entrée | `px-sm py-xs` | horizontal md, vertical 9 | mineur |
| survol | `hover:bg-white/10` | InkWell sans fond de survol | mineur |

## 1C. Barre supérieure

### 1C.1 Fil d'Ariane, page par page (mesuré)

Le prototype écrit « Groupe > Page » (casse normale) dans l'en-tête de chaque page ; le poste l'écrit `$groupe > $ecran` avec `groupe` pris tel quel dans `arborescence` — **en capitales**.

| Page | Fil du prototype | Fil du poste | Verdict |
|---|---|---|---|
| dashboard.html | Tableau de Bord | PILOTAGE > Tableau de Bord | ✘ texte |
| gestion-elevage.html | Élevage & Soins > Gestion Élevage | PRODUCTION ÉLEVAGE & SOINS > Gestion Élevage | ✘ texte |
| elevage-dashboard.html | Élevage & Soins > Dashboard Élevage | PRODUCTION ÉLEVAGE & SOINS > Dashboard Élevage | ✘ texte |
| suivi-reproduction.html | Élevage & Soins > Suivi Reproduction | PRODUCTION ÉLEVAGE & SOINS > Suivi Reproduction | ✘ texte |
| soins-vaccins-hub.html | Élevage & Soins > Soins et Vaccins | PRODUCTION ÉLEVAGE & SOINS > Soins et vaccins | ✘ texte |
| parametres-elevage.html | Élevage & Soins > Paramètres Élevage | PRODUCTION ÉLEVAGE & SOINS > Paramètres Élevage | ✘ texte |
| ventes-devis.html | Ventes Ferme > Ventes & Devis | VENTES FERME > Ventes & Devis | ✘ casse |
| creances-clients.html | Ventes Ferme > Créances Clients | VENTES FERME > Clients et Créances | ✘ texte |
| achats-commandes.html | Achats & Charges > Achats & Commandes | ACHATS & CHARGES > Achats & Commandes | ✘ casse |
| fournisseurs.html | Achats & Charges > Fournisseurs | ACHATS & CHARGES > Fournisseurs | ✘ casse |
| saisie-depenses.html | Achats & Charges > Saisie Dépenses | ACHATS & CHARGES > Saisie Dépenses | ✘ casse |
| gestion-stocks.html | Stocks & Produits > Gestion des Stocks | STOCKS & PRODUITS > Gestion Stocks | ✘ texte |
| catalogue-produits.html | Stocks & Produits > Catalogue Produits | STOCKS & PRODUITS > Catalogue Produits | ✘ casse |
| facturation.html | Facturation | FACTURATION > Facturation & MeCeF | ✘ texte |
| personnel-stages.html | Ressources Humaines > Personnel & Stages | RESSOURCES HUMAINES > Personnel & Stages | ✘ casse |
| administration.html | Administration | ADMINISTRATION > Administration & Document | ✘ texte |
| comptabilite-hub.html | Comptabilité | COMPTABILITÉ & ADMIN > Comptabilité | ✘ texte |
| parametres-hub.html | Comptabilité & Admin > Paramètres | COMPTABILITÉ & ADMIN > Paramètres Général | ✘ texte |
| rapports-exports.html | Éditions > Rapports & Exports | EDITIONS > Rapports & Exports | ✘ texte |
| fiche-lapins.html | Production Elevage & Soins > Fiches Lapins | PRODUCTION ÉLEVAGE & SOINS > Fiches Lapins | ✘ texte |
| fiche-volailles-pondeuses.html | Élevage & Soins > Fiches Pondeuses | PRODUCTION ÉLEVAGE & SOINS > Fiches Pondeuses | ✘ texte |
| fiche-volailles-reproducteurs.html | Élevage & Soins > Fiches Volailles — Reproducteurs | PRODUCTION ÉLEVAGE & SOINS > Fiches Reproducteurs | ✘ texte |
| fiche-porcs.html | Élevage & Soins > Fiches Porcs | PRODUCTION ÉLEVAGE & SOINS > Fiches Porcs | ✘ texte |
| fiche-escargots.html | Élevage & Soins > Fiches Escargots | PRODUCTION ÉLEVAGE & SOINS > Fiches Escargots | ✘ texte |

**24 fils sur 24 différents : 6 par la seule casse, 18 par le texte.**

⚠️ **Le prototype se contredit** : le groupe « PRODUCTION ÉLEVAGE & SOINS » est écrit « Production Elevage & Soins » / « Élevage & Soins » selon les pages. Aucune graphie du poste ne peut être fidèle à toutes — **arbitrage client**, non tranché ici.

### 1C.2 Éléments de l'en-tête (relevé + recherche dans le source)

| Élément du prototype | Poste | Statut | Gravité |
|---|---|---|---|
| Hauteur `h-16` = 64 | height: 56 | écart | mineur |
| Bascule du menu `menu_open` 22 px, `text-outline` | IconButton 20 px, brandForest | écart de style | mineur |
| Recherche « Recherche globale ERP… » `w-64`, active | 220 px, **désactivée**, « Recherche (application web) » | assumé (docblock : la recherche parcourt des écrans que le poste n'a pas) | — |
| Pastille « Sync » jaune, icône qui tourne, toujours « Sync » | verte au repos, jaune « Sync · n en attente » sinon | assumé en partie : ajoute le compteur d'attente (utile) mais change la couleur au repos | mineur |
| Sélecteur de rôle, boutons de test des popups | absents | exclus par CLAUDE.md (widgets de démonstration) | — |
| Cloche + badge rouge animé « 3 » | cloche sans badge (aucun compteur : notifications côté serveur) | assumé (docblock) | — |
| Menu déroulant de notifications (Toutes / Non lues, 4 lignes, « Voir toutes les notifications ») | aucun : un SnackBar renvoie au web | ÉCART — dépend du ticket `notifications` (phase 2) | majeur |
| Menu profil « Administrateur ▾ » : Mon Profil · Aide & À Propos · Contactez l'Éditeur · Paramètres · Déconnexion | ABSENT (le nom d'utilisateur est en pied de barre latérale) | ÉCART — voir 1C.3 | bloquant |
| Commandes de fenêtre (réduire / fermer) | présentes | ajout assumé (fenêtre sans cadre) | — |

### 1C.3 La déconnexion n'est branchée à rien

`AuthService.deconnecter()` existe (`lib/core/auth/auth_service.dart:153`) et est testé (`test/auth_service_test.dart:261`), mais **aucun écran ne l'appelle** — vérifié par recherche dans `lib/`. Sur un poste partagé par le caissier et l'animalier, la seule façon de changer d'utilisateur est de fermer l'application. Le menu profil du prototype porte ce lien ; son absence est donc plus qu'un écart de présentation.

⚠️ À confirmer par un essai sur le poste lancé : je n'ai fait que lire le source.

## Synthèse des écarts

| Gravité | Zone | Constat | Source |
|---|---|---|---|
| bloquant | barre supérieure | Menu profil « Administrateur ▾ » : Mon Profil · Aide & À Propos · Contactez l'Éditeur · Paramètres · Déconnexion → ABSENT (le nom d'utilisateur est en pied de barre latérale) | header ↔ barre_superieure.dart |
| majeur | barre latérale / RBAC | Le poste ne MASQUE aucun groupe selon le rôle (il estompe). CLAUDE.md dit « the sidebar hides forbidden entries » : le code dit l'inverse (décision client du docblock). À reconfirmer — la phrase de CLAUDE.md est fausse ou périmée. | main.dart `arborescence` docblock ; CLAUDE.md § RBAC |
| majeur | barre latérale | Menu flottant droit (`right-floating-menu`, barre repliée) — barre repliée : le poste ne propose pas les 6 raccourcis | sidebar.js |
| majeur | barre latérale | Bouton rond « Accès rapide Élevage & Modules » + panneau de 10 raccourcis — aucun accès rapide aux fiches d'espèce hors « Gestion Élevage » | sidebar.js |
| majeur | barre latérale | Bouton rond « Visite guidée de cette page » (`startTourGuide`) — absent, non documenté | sidebar.js |
| majeur | barre latérale | largeur de la barre : prototype `w-72` = 288, poste 240 | sidebar.js ↔ main.dart |
| majeur | barre supérieure | Fil d'Ariane : 18 pages sur 24 portent un TEXTE différent du prototype (« Élevage & Soins » ≠ « PRODUCTION ÉLEVAGE & SOINS », libellés de page renommés, groupe absent sur Facturation / Administration / Comptabilité). Cause : le poste dérive le fil de la barre latérale (`_situation`, main.dart), or le prototype ne l'écrit pas depuis la barre. | en-tête <header> des pages ↔ main.dart `_situation` |
| majeur | barre supérieure | Menu déroulant de notifications (Toutes / Non lues, 4 lignes, « Voir toutes les notifications ») → aucun : un SnackBar renvoie au web | header ↔ barre_superieure.dart |
| mineur | barre latérale | En-tête « Agri**ERP** » (ERP en `accent-yellow`) + sous-titre « Ferme École Olouwachegoun » — le poste écrit 'AgriERP' d'une seule couleur, sans sous-titre | sidebar.js |
| mineur | barre latérale | taille du libellé d'entrée : prototype `text-[13px]` = 13, poste AgriTypography.xs = 13.6 | sidebar.js ↔ main.dart |
| mineur | barre latérale | icône d'entrée : prototype `text-[20px]` = 20, poste 18 | sidebar.js ↔ main.dart |
| mineur | barre latérale | titre de groupe : prototype `text-[10px]` gras, `tracking-wider`, blanc/40, poste fontSize 10, gras, letterSpacing 0.8, white38 | sidebar.js ↔ main.dart |
| mineur | barre latérale | couleur du libellé : prototype `text-white/90`, poste white (100 %) | sidebar.js ↔ main.dart |
| mineur | barre latérale | padding d'entrée : prototype `px-sm py-xs`, poste horizontal md, vertical 9 | sidebar.js ↔ main.dart |
| mineur | barre latérale | survol : prototype `hover:bg-white/10`, poste InkWell sans fond de survol | sidebar.js ↔ main.dart |
| mineur | barre supérieure | Fil d'Ariane : 6 pages ne diffèrent que par la casse | idem |
| mineur | barre supérieure | Hauteur `h-16` = 64 → height: 56 | header ↔ barre_superieure.dart |
| mineur | barre supérieure | Bascule du menu `menu_open` 22 px, `text-outline` → IconButton 20 px, brandForest | header ↔ barre_superieure.dart |
| mineur | barre supérieure | Pastille « Sync » jaune, icône qui tourne, toujours « Sync » → verte au repos, jaune « Sync · n en attente » sinon | header ↔ barre_superieure.dart |

**1 bloquant · 7 majeur · 11 mineur.**
