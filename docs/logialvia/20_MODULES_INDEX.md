# 20 — INDEX DES MODULES : carte des modules, des 37 routes, des onglets, des rôles, des dépendances, ordre de construction

## USAGE

- **Quand l'utiliser** : en premier, avant tout fichier de module `21_` à `29_`. Il répond à : quel écran existe, sous quelle route, pour quel rôle, avec quels droits web `view-`/`manage-`, quels onglets, de quoi dépend-il, dans quel ordre le construire. Chaque ligne renvoie au fichier de module qui détaille composants, formulaires, calculs, hors ligne et synchronisation.
- **Ordre** : `10`–`15` (spécification) → **`20_MODULES_INDEX`** → modules dans l'ordre de la section 6 ; pile : `02_ARCHITECTURE_WEB_ET_STACK.md` ; base : `30_DATABASE_ENGINEERING.md` ; tests : `31_TESTING_QA.md` ; skills : `32_CLAUDE_CODE_SKILLS_LIBRARY.md`.
- **Entrées** : `logialvia/docs/03_INVENTAIRE_31_ECRANS.md`, `07_NAVIGATION_ROUTAGE.md`, `I1_Matrice_RBAC.md`, `I2_Gestion_Modules_Actifs.md`, `logialvia_app/lib/core/router/{app_router,permission_service,navigation_model}.dart` (CODE : fait foi sur les routes réelles), `logialvia/docs/manuel/libelles/*.json` (libellés exacts des écrans), `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` §1, `agrierp_laravel/database/seeders/RolesAndPermissionsSeeder.php`.
- **Sorties** : ce fichier à jour ; toute route ajoutée y figure AVANT d'être codée (une route sans ligne ici ne se code pas).
- **Chemins** : `logialvia/…` = `/home/user/massenon/logialvia/…` (lecture seule) ; sans préfixe = `/home/user/agrierp`.

---

## 1. PROMPT — « Mets à jour la carte des modules de LogiALVIA »

> **Rôle.** Architecte produit/logiciel chargé de la cohérence entre le web (Laravel + Livewire), le poste (Flutter) et la documentation.
> **Contexte.** Le poste compte 37 routes (3 publiques + 34 authentifiées, relevées dans `app_router.dart`) pour « 31 écrans » du prototype : +6 écrans nés pendant le portage (`/elevage/mirages`, `/inventaire`, `/factures-mecef`, `/comptabilite/grand-livre`, `/comptabilite/balance`, `/comptabilite/etats-financiers`). Le web reprend ces routes à l'identique.
> **Tâches.** (1) Recompte les routes du poste (`grep "'/" logialvia_app/lib/core/router/app_router.dart`) et rapproche-les du tableau §3 ; ajoute toute route nouvelle ; (2) vérifie rôle et droit de chaque ligne contre `permission_service.dart` (le code fait foi, pas I1) ; (3) tiens à jour dépendances et ordre (§6) ; (4) signale les écarts doc/code (§4).
> **Contraintes.** Une route = une ligne ; libellés de menu = ceux de `navigation_model.dart` ; modules activables par `moduleId` (`pisciculture`, `aviculture_classique`, `cuniculture`, `mecef`…) ; Goliaths et Pintades toujours actifs ; aucune route sans `can:` côté web ET sans masquage côté poste.
> **Critères d'acceptation.** (a) 37 lignes de routes ; (b) chaque route a rôle(s), `view-…`, module actif éventuel, fichier de module, dépendances ; (c) chaque écran à onglets liste ses onglets avec leurs libellés exacts ; (d) l'ordre de construction respecte les dépendances (aucun module avant son prérequis) ; (e) tous les chemins cités existent.
> **Interdits.** Inventer une route ; laisser un écran « à venir » sans l'écrire en `module-pending` ; donner un droit « admin » par défaut à une permission non semée (il n'y a pas de `Gate::before`).

---

## 2. Conventions de droits

**Permissions web** (modèle `agrierp_laravel/database/seeders/RolesAndPermissionsSeeder.php`, adapté) : `view-<m>` (voir), `manage-<m>` (écrire), plus `archive-elevage`, `export-<m>`, `close-fiscal-year`, `manage-users`, `manage-modules`. Modules : `elevage`, `ventes`, `achats`, `stocks`, `facturation`, `comptabilite`, `rapports`, `parametres` (+ `rh` si accepté, Q-RH-1). **Deux niveaux obligatoires** : route `->middleware(['auth','can:view-<m>'])` ET `$this->authorize('manage-<m>')` en première ligne de chaque méthode mutante ; le masquage de menu est cosmétique. Au poste : `PermissionService.estAutorise(role, route)` + `ModulesActifsProvider.estActif`, alimenté par la matrice du serveur.

## 3. Rôles et matrice RBAC (3 rôles — écart avec les 4 d'AgriERP)

**Écart à signaler** : logialvia = **3 rôles** (`admin` « Administratrice », `caissier` « Agent de Vente », `animalier` « Agent d'Élevage » ; I1 corrigé par K4 §8/§10 ; `logialvia_app/lib/administration/domain/entities/role_utilisateur.dart`) ; AgriERP = **4 rôles** (`admin`, `comptable`, `caissier`, `animalier`). B1/B2/B3 de logialvia citent « Comptable » à tort. Décision : garder 3 ; tout droit comptable → `admin` (Q-ROL-1).

| Permission web | admin | caissier | animalier |
|---|:--:|:--:|:--:|
| `view/manage/archive/export-elevage` | oui | non | oui |
| `view/manage/export-ventes` (caisse, clients, inventaire) | oui | oui | non |
| `view/manage-facturation` (MeCeF, avoirs) | oui | oui | non |
| `view/manage-achats` (achats, fournisseurs, dépenses) | oui | non | non |
| `view/manage-stocks` (stocks, catalogue) | oui | non | non |
| `view/manage-comptabilite`, `close-fiscal-year` | oui | non | non |
| `view/export-rapports` | oui | non | non |
| `view/manage-parametres`, `manage-users`, `manage-modules` | oui | non | non |
| `/parametres/elevage` : rations, prophylaxie, numérotation | oui | non | oui (limité : pas d'activation de filière) |
| `/dashboard`, `/profil`, `/aide`, `/contact` | oui | oui | oui (auth seule) |

**Écarts documentation ↔ code à ne pas « corriger par prudence »** : (1) I1 §2 met Inventaire en « ✅ admin » seulement ; le code (`permission_service.dart`) l'ouvre aussi au caissier (« ARBITRÉ PAR LA GÉRANTE » : il voit coûts de revient et valorisation) ; (2) `/factures-mecef` est ouvert au caissier (la facturation et l'avoir se font au comptoir) ; (3) la description du caissier en I1 §1 dit « consultation Stocks » mais sa liste de routes n'inclut pas `/stocks` : la consultation visée est le badge de stock du POS (Q-ROL-2) ; (4) le menu du caissier ne comporte pas `/catalogue` : le lien produit → catégorie d'effectif (RM-ELV-05) est donc un geste admin.

## 4. Carte des routes (37) — poste existant = web cible

Légende rôles : A admin · C caissier · N animalier. « Surf. » : W web, P poste (P⁻ = lecture seule ou demande). « Module actif » : conditionne menu ET accès direct.

| # | Route | Écran | Fichier | Onglets / sections | Rôles | Droit web | Module actif | Dépend de |
|---|---|---|---|---|---|---|---|---|
| 1 | `/` | Splash | `21_` | séquence de démarrage | public | — | — | — |
| 2 | `/welcome` | Accueil | `21_` | bouton « Se Connecter » | public | — | — | — |
| 3 | `/login` | Connexion | `21_` | — | public | — | — | 1, 2 |
| 4 | `/dashboard` | Tableau de bord | `22_` | 7 sections, 8 KPI | A C N | auth | — | 12–19, 28 |
| 5 | `/elevage/dashboard` | Dashboard Élevage | `22_` | 4 sections | A N | view-elevage | — | 6–11 |
| 6 | `/elevage/goliaths` | Fiche Goliaths | `23_` | grille / hebdomadaire | A N | view-elevage | toujours actif | 11, 14 |
| 7 | `/elevage/pintades` | Fiche Pintades | `23_` | idem | A N | view-elevage | toujours actif | 11, 14 |
| 8 | `/elevage/lapins` | Fiche Lapins | `23_` | idem | A N | view-elevage | `cuniculture` | 11, 14 |
| 9 | `/elevage/poissons-chats` | Fiche Poissons-Chats | `23_` | idem | A N | view-elevage | `pisciculture` | 11, 14 |
| 10 | `/elevage/poulets-pondeuses` | Fiche Poulets / Pondeuses | `23_` | onglets « Poulets », « Pondeuses » | A N | view-elevage | `aviculture_classique` | 11, 14 |
| 11 | `/elevage/couveuse` | Cycle Couveuse | `23_` | machines, lots, historique | A N | view-elevage | — | 6, 7 |
| 12 | `/elevage/mirages` | Statistiques des Mirages | `23_` | 7 indicateurs | A N | view-elevage | — | 11 |
| 13 | `/elevage/soins` | Soins & Calendrier | `23_` | « Registre des Soins », « Calendrier des Doses », « Suivi Infirmerie » | A N | view-elevage | — | 6–10, 14 |
| 14 | `/parametres/elevage` | Paramètres Élevage | `23_` | « Rationnement », « Calendriers Prophylaxie », « Intrants de Provende », « Numérotation Bandes & Sujets » | A N | view-elevage | — | 17 |
| 15 | `/ventes` | Ventes | `24_` | « Enregistrer Vente », « Devis Prestations », « Historique des Ventes », « Retours et Avoirs » | A C | view-ventes | — | 17, 18, 6–10 |
| 16 | `/clients` | Clients et Créances | `24_` | clients, créances, événements CRM | A C | view-ventes | — | 15 |
| 17 | `/inventaire` | Inventaire daté et valorisé | `25_` | Journalier / Hebdomadaire / Mensuel / Plage personnalisée | A C | view-ventes | — | 18, 19 |
| 18 | `/factures-mecef` | Facturation MeCeF | `24_` | filtres À transmettre / Normalisée / Rejetée | A C | view-facturation | `mecef` | 15, 3 |
| 19 | `/achats` | Achats & Commandes | `25_` | panier d'achat, commandes | A | view-achats | — | 20, 21 |
| 20 | `/fournisseurs` | Fournisseurs | `25_` | fournisseurs, dettes | A | view-achats | — | — |
| 21 | `/depenses` | Saisie des Dépenses | `25_` | formulaire + liste | A | view-achats | — | 25 |
| 22 | `/stocks` | Gestion des Stocks | `25_` | articles, journal des mouvements | A | view-stocks | — | — |
| 23 | `/catalogue` | Catalogue & Seuils | `25_` | catalogue, seuils d'alerte | A | view-stocks | — | — |
| 24 | `/comptabilite` | Hub Comptabilité | `26_` | tuiles | A | view-comptabilite | — | 25–31 |
| 25 | `/comptabilite/journal` | Journal Comptable | `26_` | — | A | view-comptabilite | — | plan |
| 26 | `/comptabilite/grand-livre` | Grand Livre | `26_` | — | A | view-comptabilite | — | 25 |
| 27 | `/comptabilite/balance` | Balance Générale | `26_` | — | A | view-comptabilite | — | 25 |
| 28 | `/comptabilite/plan` | Plan Comptable | `26_` | — | A | view-comptabilite | — | — |
| 29 | `/comptabilite/analytique` | Comptabilité Analytique | `26_` | — | A | view-comptabilite | — | 25 |
| 30 | `/comptabilite/etats-financiers` | États Financiers | `26_` | « Bilan », « Compte de Résultat », « Flux de Trésorerie », « Notes Annexes » | A | view-comptabilite | — | 27 |
| 31 | `/comptabilite/bilan` | Bilan de l'Entreprise | `26_` | — | A | view-comptabilite | — | 30 |
| 32 | `/comptabilite/cloture` | Clôture d'Exercice | `26_` | clôture périodique, annuelle | A | view-comptabilite + close-fiscal-year | — | 27 |
| 33 | `/rapports` | Rapports & Exports | `28_` | « Recettes et Dépenses », « État de Trésorerie », « Créances Clients », « Dettes Fournisseurs », « Rapport Élevage », « Rapport de Stocks » | A | view-rapports | — | 25, 15, 6–10 |
| 34 | `/parametres/generaux` | Paramètres Généraux | `29_` | « Modules Actifs », « Données de l'Entreprise », « Gestion Utilisateurs », « Modes de Paiement », « Sauvegardes », « Corbeille », « Données de Test » | A | view-parametres | — | — |
| 35 | `/profil` | Mon Profil | `21_` | mot de passe, métadonnées de session, journal personnel | A C N | auth | — | 3 |
| 36 | `/aide` | Aide & À Propos | `21_` | modules, FAQ | A C N | auth | — | — |
| 37 | `/contact` | Contactez l'Éditeur | `21_` | « Question Générale », « Signaler un Problème » | A C N | auth | — | — |

Entrées de menu (8 groupes, `navigation_model.dart` / F2) : PILOTAGE ; ÉLEVAGE & COUVEUSE ; VENTES & CLIENTS (Ventes, Clients et Créances, Inventaire, Facturation MeCeF) ; ACHATS & FOURNISSEURS (Achats & Commandes, Fournisseurs, Saisie Dépenses) ; STOCKS & CATALOGUE ; COMPTABILITÉ (Comptabilité, Grand Livre, Balance Générale, États Financiers, Bilan) ; PARAMÈTRES ; ÉDITIONS (Rapports). `/comptabilite/journal`, `/plan`, `/analytique`, `/cloture` ne sont atteignables que par les tuiles du hub (comportement du prototype).

**Écrans à ajouter côté web seulement** (n'existent pas dans le poste ; à décider/construire d'abord au web, doctrine art. 5) : modale de synchronisation et état des postes (`43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`), gestion des postes appairés, Centre de notifications, assistant d'importation (`28_`), réglage e-MECeF (`42_CONFIG_MECEF_SMTP_LOGO_FAVICON.md`), verrouillage de session. Écran optionnel : RH & Paie (`27_`, Q-RH-1).

## 5. Onglets internes — la règle d'implémentation

Chaque jeu d'onglets est UN écran (une route), jamais des routes séparées : au poste `TabController` ; au web `#[Url] public string $tab` dans un composant Livewire unique (hubs = composants imbriqués, jamais iframes). Libellés d'onglets mot pour mot (colonne « Onglets » du §4 ; source : `logialvia/docs/manuel/libelles/*.json`).

## 6. Dépendances et ordre de construction

Ordre issu du guide §1 (révisé le 07/11/2026) et du jalonnement W0–W9 (guide 14.3). Un module ne démarre pas avant ses prérequis ; chaque jalon se termine par les tests verts des deux côtés et la liste de ce qui n'est PAS vérifié.

| Rang | Jalon | Contenu | Modules / fichiers |
|---|---|---|---|
| 0 | W0 | Décisions du client (ADR), classement des 37 tables | `12_SRS` §5, `10_BRS` §6 |
| 1 | W1 | Squelette Laravel 12, rôles et droits semés, audit, fuseau, `php artisan test --testsuite=Feature` vert | `02_`, `03_`, `30_` |
| 2 | W2 | Schéma UUID des référentiels (produits, clients, fournisseurs, paramètres) ; palier de migration UUID du poste | `30_DATABASE_ENGINEERING.md` |
| 3 | W3 | Authentification : connexion, jeton nommé, compte désactivé, mot de passe temporaire | `21_` ; `43_` |
| 4 | W4–W5 | Synchronisation minimale puis barre du haut (cloche, sélecteur d'exercice, modale de synchronisation) | `43_` ; `22_` |
| 5 | W6a | Paramètres & administration (utilisateurs, modules actifs, entreprise) | `29_` |
| 6 | W6b | Stocks & achats (produits, intrants, mouvements, PMP) | `25_` |
| 7 | W6c | Clients, fournisseurs, ventes/caisse, créances | `24_` |
| 8 | W6d | Élevage : bandes → fiches → rationnement → soins/prophylaxie → couvoir → rappels | `23_` |
| 9 | W6e | Pilotage : tableaux de bord, notifications | `22_` |
| 10 | W7a | Importation en masse (stocks d'abord) | `28_` |
| 11 | W7b | MeCeF / e-MECeF côté serveur | `24_`, `41_` |
| 12 | W8 | Comptabilité et exercices ; au poste : demandes rejouées par le serveur | `26_` |
| 13 | W6f | Rapports et exports (après la comptabilité : le résultat net doit venir d'une seule source) | `28_` |
| 14 | W9 | Essai multipostes, build et installateur, mise en production serveur puis postes | `31_` ; guide bloc 10 |
| 15 | — | Option : RH & Paie ; PWA hors ligne (seulement sur besoin explicite) | `27_` ; `40_PWA_HORS_LIGNE.md` |

Raison de l'ordre : tout module partagé exige l'identité (UUID), l'appairage et la synchronisation ; la fiche calculée suppose une bande propre ; le rationnement lit l'effectif calculé ; l'import réutilise les points de passage des modules déjà construits ; MeCeF suppose serveur et ventes ; la comptabilité ne s'écrit au poste que par demandes ; le build clôt la chaîne.

## 7. Prompt maître de construction d'un module (à copier ; chaque `2x_` le précise)

> Construis le module <X> du web LogiALVIA d'après `<fichier de module>`. Lis d'abord : `CLAUDE.md` racine, `docs/DOCTRINE_PORTAGE.md`, `03_DEVELOPMENT_STANDARDS.md`, `04_UI_UX_DESIGN_SYSTEM.md`, `15_REGLES_METIER.md` (règles citées). **Ordre strict, un écran à la fois** : (1) migration (UUID, `device_id`, `sync_status` côté poste, `is_active`) ; (2) modèle Eloquent ; (3) Action/Service = UN point de passage par règle, avec `authorize()` ; (4) composant Livewire `app/Livewire/<Module>/…` (`#[Url] $tab`, modales par événement, toasts) ; (5) vue Blade avec composants partagés (`x-datatable`, `x-kpi-card`, `x-modal`, `data-label` sur chaque `<td>`) ; (6) portage au poste : table Drift (même schéma) → dépôt → écran fidèle → tests ; (7) tests : cas à la main de `15_REGLES_METIER.md` en Feature, garde de libellés lue dans la source, parité PHP↔Dart. **Terminé** = `php artisan test --testsuite=Feature` vert, `flutter analyze` sans erreur, `flutter test` vert, règle écrite dans B6 avec son `BR-`, et ce qui n'a PAS été vérifié dit explicitement. **Interdits** : règle recopiée hors du point de passage, `@if($showModal)`, `DELETE` physique, formule inventée pour pisciculture/pintades, bouton qui n'écrit pas.
