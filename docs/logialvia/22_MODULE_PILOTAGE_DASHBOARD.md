# 22 — MODULE PILOTAGE (Tableau de bord, Dashboard Élevage, coquille de navigation, notifications, rappels du jour)

## USAGE

- **Quand l'utiliser** : pour construire les 2 tableaux de bord et la coquille commune (barre latérale, barre du haut, recherche, cloche, rappels) ; au jalon W5 (coquille et barre du haut) puis W6e (tableaux de bord, une fois les modules alimentant les KPI construits). Un KPI dont le module source n'existe pas affiche « — » (jamais 0).
- **Ordre** : `20_MODULES_INDEX` → `25_` (stocks) → `24_` (ventes) → `23_` (élevage) → `26_` (comptabilité) → **`22_`** ; en parallèle `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md` (modale de synchronisation, alertes).
- **Entrées** : `logialvia/docs/F2_Module_Pilotage.md`, `E7_Dashboards_KPI.md`, `G1_Interactions_Dynamiques.md`, `07_NAVIGATION_ROUTAGE.md`, `docs/logialvia/GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` blocs 3, 4, 6, 17, 18 ; code `logialvia_app/lib/pilotage/presentation/viewmodels/alertes_view_model.dart`, `logialvia_app/lib/core/router/navigation_model.dart`, `logialvia_app/lib/core/widgets/shell/app_top_bar.dart` ; AgriERP : `agrierp_laravel/app/Services/AlertesElevageService.php`, `agrierp_laravel/app/Services/RappelsDuJourService.php`, `agrierp_laravel/app/Livewire/Shared/RappelsDuJour.php`, `docs/prd/popup-rappels.md`, `docs/prd/synchronisation-barre-superieure.md`, `docs/prd/navigation-sans-rechargement.md` ; libellés `logialvia/docs/manuel/libelles/{01-tableau-de-bord,02-dashboard-elevage}.json`.
- **Sorties** : composants `Dashboard\Principal`, `Elevage\DashboardElevage`, `Shared\{BarreHaut,Cloche,RappelsDuJour,RechercheGlobale}`, services d'agrégation, tests.
- **Chemins** : `logialvia/…` = `/home/user/massenon/logialvia/…` ; sans préfixe = `/home/user/agrierp`.

---

## 1. Objectif

Donner à la Direction « des chiffres fiables au premier coup d'œil » (B2 §2) et à chaque rôle un point d'entrée adapté ; consolider effectifs, mortalité et ventes de toutes les filières sans recalcul manuel (BR-004) ; ne jamais afficher un zéro qui se lirait comme un vrai zéro métier.

## 2. Écrans

| Route | Écran | Rôles | Droit web | Surface |
|---|---|---|---|---|
| `/dashboard` | Tableau de bord | A C N | auth seule | Web + Poste (calcul local hors ligne) |
| `/elevage/dashboard` | Dashboard Élevage | A N | view-elevage | Web + Poste |
| (coquille) | Barre latérale, barre du haut, recherche, cloche, rappels | tous | auth | Web + Poste |

## 3. Tableau de bord — 7 sections, ordre strict

1. **En-tête** : « Bienvenue, <nom> 👋 » (20 px bold navy) ; « Rapport généré le JJ/MM/AAAA à HH:MM · ALLMANY ET COMPAGNIE » ; boutons pilule « Enregistrer une Vente » → `/ventes` (primaire), « Dashboard Élevage » → `/elevage/dashboard` (secondaire).
2. **Filtre de période** : deux champs date (« du » … « au ») qui filtrent réellement. Le sélecteur de 6 états + export PDF du prototype est retiré (le prototype ne produisait aucun PDF ; la génération relève de `28_`).
3. **8 KPI** (grille `grid-cols-2 xl:grid-cols-4`, basculement à 1280 px de FENÊTRE ; 2 rangées de 4 sur desktop) :

| # | KPI (libellé exact) | Accent | Icône | Source | Formule / règle |
|---|---|---|---|---|---|
| 1 | CHIFFRE D'AFFAIRES | navy | `trending_up` | lignes de vente non annulées de la période | Σ `qte × pu` ; ventilé Avicole / Commerce Annexe d'après `PRODUITS_VENDABLES.cat` |
| 2 | TRÉSORERIE | info-blue | `account_balance_wallet` | grand livre | solde du compte 531 (voir contradiction P-1) |
| 3 | DÉPENSES | gold | `shopping_cart` | achats + dépenses saisies | Σ de la période |
| 4 | RÉSULTAT NET | success-deep | `savings` | comptabilité | produits classe 7 − charges classe 6 (UNE source : RM-CPT-04) ; le prototype disait CA − Dépenses |
| 5 | SOLDES RESTANT DUS | error-deep | `request_quote` | ventes en Avance non annulées | Σ (total − paye) (RM-VTE-02) |
| 6 | STOCK CRITIQUE | error-deep | `warning` | intrants | COUNT(stock ≤ seuil) (RM-STK-02) ; cas Maïs 18/25 → 1 |
| 7 | EFFECTIF CHEPTEL | navy | `pets` | fiches | Σ effectif du DERNIER jour saisi de chaque filière ACTIVE |
| 8 | CYCLES COUVEUSE EN COURS | gold | `egg` | couvoir | COUNT(statut = « En Incubation ») |

Règle : KPI non calculable (module source absent ou coût inconnu) = valeur « — », ligne de détail « Disponible avec le module Comptabilité » (ou équivalent), bande d'accent gris ; jamais « 0 FCFA ». KPI toujours affichés (E7 §1).
4. **Courbe + Alertes critiques** (`lg:col-span-8` / `lg:col-span-4`) : courbe « CA vs Dépenses — 6 derniers mois » (CA navy plein, Dépenses `error-deep` pointillé `5,4`) sur données réelles ; panneau « Alertes Critiques » : intrants et produits sous seuil, éclosion imminente, soldes restant dus, soins en retard, anniversaire client demain ; chaque alerte est un lien vers l'écran concerné (jamais un lien mort) ; **cloche et panneau dérivent d'UNE source** (`AlertesViewModel` au poste ; `AlertesElevageService` au web).
5. **Cartes de recensement** (`md:grid-cols-3`) : une par filière ACTIVE + Couveuse ; carte cliquable vers la fiche ; Effectif = effectif du dernier jour ; « Matures » = catégorie 3 ; « Goliathaux » / « Pintadaux » = catégorie 2 ; Mortalité = mortalité du mois ÷ effectif de début de mois × 100 (RM-ELV-08) ; taux d'éclosion moyen sans éclosion = « — ».
6. **Statistiques de Ventes + Transactions Récentes** (`lg:grid-cols-2`) : Revenu semaine / Dépenses semaine, histogramme des 6 derniers jours ; Transactions Récentes en 3 onglets « Vente », « Achat », « Dépenses » (seul « Vente » avait une source dans le prototype : états explicites « Le module Achats & Commandes n'est pas encore disponible », jamais de lignes inventées — au web tous trois sont réels).
7. **Activités du Jour + Meilleures Ventes du Mois** : fil d'activité = `audit_logs` (source unique, pas de table dédiée) ; tableau « Meilleures Ventes du Mois » : Produit / Qté / CA / Activité, trié par CA décroissant, zébré.

**Fenêtre « Rappels du jour »** (poste et web) : règle RM-PRO-02 ; ouverte une fois par session (lancement après le PIN, chaque connexion, JAMAIS un déverrouillage), « Ne plus afficher aujourd'hui » (par utilisateur, jour `AAAA-MM-JJ`), jamais vide, jamais bloquante (erreur avalée), rôle sans droit d'élevage = pas de fenêtre. Libellés : « Marquer fait » (passe réellement le soin à « Effectué »), « Planifier », « Plus tard » ; bannière type « 7 échéance(s) de prophylaxie non planifiée(s) sur 2 filière(s), dont 7 en retard. » (libellé réel du poste).

## 4. Dashboard Élevage — 4 sections

1. En-tête + bouton « Exporter PDF » (réel, via `28_`).
2. Cartes par filière (`md:grid-cols-3`) : carte réelle (`data-module-full-card`) si la filière est active ; sinon carte d'APERÇU (fond `surface-zebra`, bordure en tirets, cadenas, « Filière X disponible — non activée pour le moment. », lien « Activer depuis Paramètres → ») ; les 3 filières activables sont inactives par défaut (aperçus au premier lancement).
3. Graphique GMQ + « Rappels Vétérinaires à Venir » : le GMQ suppose un poids (colonne « PESÉE TOTALE DU LOT (G) » sur les fiches) ; **aucune formule de GMQ n'est documentée dans les sources lues** → **À DÉFINIR AVEC LE CLIENT (Q-PIL-2)** : définition (gain de poids moyen par sujet et par jour ?), fréquence de pesée, filières concernées.
4. Alertes Sanitaires du Jour + Bilan Économique Élevage : « REVENUS ÉLEVAGE » = ventes Avicole du Dashboard principal ; « COÛTS ÉLEVAGE » = intrants provende + vétérinaire de la période ; « MARGE NETTE ÉLEVAGE » = Revenus − Coûts, « — » tant que les coûts manquent (jamais réduite au revenu seul). Exemple d'alerte réel : « Stock de Maïs sous le seuil critique — impact direct sur le rationnement des filières. »

## 5. Coquille commune

**Barre latérale** (8 groupes, F2 / `navigation_model.dart`) : PILOTAGE ; ÉLEVAGE & COUVEUSE (Cycle Couveuse, Statistiques des Mirages, fiches Goliaths, Pintades, Poissons-Chats*, Lapins*, Poulets/Pondeuses*, Dashboard Élevage, Paramètres Élevage, Soins & Calendrier) ; VENTES & CLIENTS (Ventes, Clients et Créances, Inventaire, Facturation MeCeF**) ; ACHATS & FOURNISSEURS ; STOCKS & CATALOGUE ; COMPTABILITÉ ; PARAMÈTRES ; ÉDITIONS. \* masquées tant que leur module n'est pas actif ; \*\* module `mecef`. Filtrée par rôle ET module actif ; état replié mémorisé (`PREFERENCES_POSTE`) ; routes d'écrans non construits = `module-pending` nommant le document, jamais un lien mort.
**Barre du haut** : bouton de repli de la barre latérale, fil d'Ariane, **recherche globale** (Ctrl+K, anti-rebond 150 ms ; index dérivé de la navigation, filtré par rôle et module actif), **cloche de notifications**, **sélecteur d'exercice** (RM-CPT-07 ; bandeau de lecture seule), **modale de synchronisation** (`43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`, `docs/prd/synchronisation-barre-superieure.md` ; remplace le badge « 3 en attente » du prototype, qui était un indicateur mensonger), menu profil (Mon Profil, Aide, Contact, Déconnexion). Non reproduits : sélecteur de rôle RBAC et boutons « Démonstration — forcer l'affichage… » (outils de test du prototype).
**Boutons de fenêtre** (poste) : Réduire / Agrandir / Fermer dans la barre du haut (guide bloc 3).

## 6. Notifications et alertes (mécanismes — guide bloc 18)

| Mécanisme | Qui calcule / quand |
|---|---|
| Cloche web (`notifications`, visibles du rôle) | le SERVEUR écrit, la cloche lit à chaque rendu |
| Alertes quotidiennes 06:05 (Africa/Porto-Novo) : stock sous seuil (admin ; critique à stock ≤ 0 chez AgriERP), mortalité anormale (animalier ; seuil À DÉFINIR, Q-ALR-2), soins à venir/en retard (RM-PRO-02), éclosions imminentes | planifié serveur ; une notification par objet et par jour |
| Prophylaxie du jour 06:00 | planifié serveur, `ProtocoleDuJourService` (règle unique) |
| Autonomie de provende | événementiel à l'enregistrement d'une fiche, jamais bloquant (RM-ELV-10) |
| Stock négatif après synchronisation ; vente sous délai d'attente | événementiel à la réception d'une vente du poste (le serveur accepte et signale) |
| Ouverture de l'exercice | 1er janvier 00:00 |
| Entretien | purge hebdomadaire des notifications lues > 90 jours ; sauvegarde 02:00 ; rappel hebdomadaire de téléchargement (lundi 08:00) |
| Cloche du poste | copie du serveur relue toutes les 30 s depuis la base LOCALE ; le poste n'émet AUCUNE notification ; « marquer lue »/« supprimer » exigent le réseau |
| « Alertes critiques » du poste | recalculées LOCALEMENT, hors ligne, mêmes règles que le serveur (stock critique 5 articles au plus ; mortalité ≥ seuil) |

## 7. États vides et erreurs

KPI sans donnée : « — » ; liste d'alertes vide : « Aucune alerte critique. » ; fil d'activité vide : « Aucune activité aujourd'hui. » ; module source non construit : `module-pending`. Une erreur de la fenêtre « Rappels du jour » est avalée (journalisée), elle ne bloque rien.

## 8. Contradictions et questions

- **P-1** Le KPI « Trésorerie » vaut le solde du compte 531 (F2) alors que l'« État de Trésorerie » (F7) additionne Caisse Espèces et Mobile Money (531 + 512 chez logialvia) : **Q-PIL-1** : la trésorerie du tableau de bord inclut-elle le Mobile Money ?
- **P-2** Résultat net : CA − Dépenses (prototype F2) contre classes 7 − 6 (BR-CPT-005) : retenir BR-CPT-005.
- **Q-PIL-2** GMQ (voir §4). **Q-ALR-2** seuil de mortalité. **Q-ALR-3** horizon des rappels.

## 9. Critères d'acceptation

- [ ] Les 8 KPI portent les libellés exacts ; un KPI sans source affiche « — » + sa mention.
- [ ] KPI 6 vaut 1 avec le jeu d'essai (Maïs 18 kg, seuil 25) calculé par requête sur les données semées, pas recopié.
- [ ] Grille KPI : 4 colonnes à ≥ 1280 px de FENÊTRE ; 2 en dessous (test sur la largeur de fenêtre).
- [ ] Alertes critiques et cloche = même source (une seule liste).
- [ ] Rappels : jamais vides, jamais au déverrouillage, « Ne plus afficher aujourd'hui » l'emporte.
- [ ] Recherche Ctrl+K : aucun résultat vers un écran interdit ou un module inactif.
- [ ] Dashboard Élevage : filière inactive → carte d'aperçu ; activation → carte réelle.
- [ ] Effectifs de démonstration : Goliath 31 matures, Pintade 28 matures, jamais une autre valeur.

## 10. Tests

Feature : `TableauDeBordKpiTest` (cas à la main), `AlertesUneSeuleSourceTest`, `RappelsDuJourOuvertureTest` (modèles `agrierp_laravel/tests/Feature/RappelsDuJourTest.php`, `…/ProtocoleDuJourServiceTest.php`), `RechercheGlobaleFiltreeTest`, `DashboardElevageApercuTest`. Poste : `logialvia_app/test/pilotage/stock_critique_test.dart` (existant), gardes de libellés (KPI lus dans la vue web : modèle `agrierp_flutter/test/rappels_du_jour_blade_test.dart`), test de largeur de fenêtre.

## 11. PROMPT de construction du module

> Construis le module **Pilotage** d'après ce fichier, APRÈS les modules qui alimentent ses KPI (`20_MODULES_INDEX.md` §6). Lis `20_` §7, `F2`, `E7`, guide blocs 6, 17, 18. Ordre : **(1) migration** `notifications` (UUID, type, lien, rôle visible, lue, un enregistrement par objet et par jour : clé `type + link_url + jour`), préférences de rappel (`rappel_soins_jours` 0–30 défaut 3, masquage par utilisateur et par jour) ; **(2) modèles** ; **(3) Services** `TableauDeBordService` (UN service qui calcule chaque KPI, jamais deux copies), `AlertesElevageService` (stock, mortalité, soins, éclosions), `RappelsDuJourService` ; planificateur `routes/console.php` (06:00 et 06:05, fuseau `Africa/Porto-Novo`) ; **(4) composants Livewire** `Dashboard\Principal`, `Elevage\DashboardElevage`, `Shared\Cloche`, `Shared\RappelsDuJour`, `Shared\RechercheGlobale`, `Shared\BarreHaut` ; **(5) vues** avec `x-kpi-card`, `x-datatable`, grille `xl` ; **(6) poste** : table Drift `notifications` (copie remplacée au tirage), calcul LOCAL des alertes critiques, ouverture des rappels par la porte de session (une fois par session), cloche relue toutes les 30 s ; **(7) tests** du §10. **Interdits** : `wire:poll` non justifié, KPI à 0 par défaut, deux listes d'alertes, notification émise par le poste, `DateTime.now()` pour un jour métier, valeur de démonstration divergente (31/28).
