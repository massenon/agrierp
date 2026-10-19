# Audit de fidélité web ↔ poste — écrans clés (19/10/2026)

**Référence :** la vue Blade est le maître (Doctrine, articles 0 et 5). Les directives d'ergonomie transmises par le client le 19/10/2026 (barre latérale, Accès Rapide, Tableau de bord, Gestion Élevage, Dashboard Élevage, Suivi Reproduction, Soins, Paramètres Élevage, synchronisation) servent de **liste de contrôle** ; toutes les **valeurs** (couleurs, tailles, libellés, colonnes) sont prises dans le Blade.

**Méthode :** pour chaque écran, lecture intégrale du composant Livewire, de sa vue Blade et des composants inclus, puis de l'écran Flutter et de son repository. Chaque élément est classé :

- ✅ conforme ;
- ⚠️ divergent ;
- ❌ absent au poste ;
- ➕ absent au web (ajout du poste, à construire d'abord au web ou à retirer).

**Constat transversal :** la plupart des écrans du poste ont été portés depuis la **maquette HTML**, pas depuis le Blade, et leurs garde-fous (`fidelite_libelles_test`, `conformite_structure_test`) comparent le code à la maquette. Là où le Blade a simplifié ou réécrit la maquette, le poste diverge du maître sans qu'aucun test ne le signale.

---

## Valeurs de la liste de contrôle contredites par le Blade

Ces valeurs ne sont **pas** appliquées : le Blade fait foi.

| Directive | Blade (maître) |
|---|---|
| Barre latérale 260 px, fond `#0E2A1D`, actif `#1A3F2F` blanc | `w-72` (288 px), dégradé `#052e16 → #00210d` (`sidebar-gradient`), actif `bg-white/10` **texte et icône jaunes** (`text-accent-yellow`) |
| Titres de section 11 px `#7A9A8B` | `text-[10px] text-white/40 font-bold uppercase tracking-wider` |
| Libellés 14 px, icônes `Icons.*_rounded` | libellés 13 px, icônes Material Symbols **Outlined** 20 px |
| Bouton flottant `#0E2A1D`, 24 px des bords | `bg-brand-emerald` (#065f46), 48 px, `bottom:88px right:16px`, icône `apps` |
| Panneau Accès Rapide 320 px, en-tête `#0E2A1D`, icône dorée | `w-72` (288 px) `max-w-[85vw]`, en-tête `bg-brand-forest`, icône `apps` `text-brand-maize` |
| En-têtes de tableau fond marine `#0F172A` | en-têtes clairs (décision E3 toujours ouverte) |
| Barre supérieure : initiales « MO » dans un avatar | `account_circle` + nom ; les initiales ne sont pas utilisées |
| Toasts « fond vert / rouge » en bas | `top-4 right-4`, 3,5 s, succès émeraude, erreur `error-red`, avertissement jaune |

---

## 1. Châssis commun (`layouts/app.blade.php`)

### 1.1 Barre latérale

| Élément | Verdict | Détail |
|---|---|---|
| 10 sections et 19 entrées : ordre, libellés, noms d'icônes | ✅ | `main.dart:945-1023` |
| Défilement | ❌ | `Column` + `Spacer()` sans `SingleChildScrollView` (`main.dart:1118-1151`) : la barre déborde sur un petit écran et le bouton Synchroniser devient inatteignable (déjà relevé dans `RAPPORT_VISUEL.md:11`) |
| Largeur | ⚠️ | 240 au lieu de 288 |
| Fond | ⚠️ | uni au lieu du dégradé |
| « Agri**ERP** » | ⚠️ | « ERP » devrait être jaune, `extrabold` 18 px |
| Sous-titre « Ferme École Olouwachegoun » | ❌ | |
| Séparateur `border-white/10` sous l'en-tête | ❌ | |
| Lien | ⚠️ | icône 18 au lieu de 20 ; libellé 13,6 au lieu de 13 ; padding différent |
| Entrée active | ⚠️ | blanche au lieu de jaune ; fond 0,14 au lieu de 0,10 |
| Filtrage par rôle | ⚠️ | le web **masque** les sections non autorisées ; le poste les estompe et affiche au clic un message faux (« vit sur l'application web ») |
| Bloc utilisateur | ⚠️ | bordure haute absente ; rôle affiché en libellé et non en nom technique |
| Ruban replié (6 raccourcis + « Réafficher le menu ») | ❌ | |
| Section « POSTE » (Synchronisation, Paramètres du poste) | ➕ | assumé : concepts propres au poste |
| Rendu des icônes | ⚠️ | Material Icons **pleines** au lieu de Material Symbols **Outlined**, sur tout le châssis |

### 1.2 Barre supérieure

| Élément | Verdict | Détail |
|---|---|---|
| Hauteur et padding | ⚠️ | 56 / 16 au lieu de 64 / 24 |
| Bouton de repli | ⚠️ | icône toujours `menu_open` 22 au web |
| Titre | ⚠️ | le web affiche le `$title` du composant (« Élevage > Fiches Lapins ») ; le poste affiche « GROUPE > écran » |
| Recherche globale | ⚠️ | désactivée au poste, avec l'indication « Recherche (application web) » ; le web a « Recherche globale ERP… (Ctrl+K) », la recherche en direct et le clavier |
| Cloche | ⚠️ | plafond 99+ au lieu de 9+ ; pas de halo `animate-ping` ; pas de « Marquer comme lue » ; pas de rafraîchissement toutes les 30 s |
| Menu du compte | ❌ | entrées « Paramètres », séparateur, « Déconnexion » absentes |
| Pastille « Sync · N en attente » | ➕ | non cliquable |
| Boutons de fenêtre | ➕ | assumé : fenêtre sans cadre |

### 1.3 Bouton flottant et panneau « Accès Rapide » — ❌ absent au poste

Le web (`app.blade.php:219-247`) affiche un bouton `apps` (48 px, émeraude, `bottom:88px right:16px`) qui ouvre un tiroir droit de 288 px, avec un voile `bg-black/40`. L'en-tête est sur fond `brand-forest`, avec l'icône `apps` en maïs, le titre « Accès Rapide » et un bouton ✕.

Le tiroir contient 13 entrées, en 3 groupes séparés par une ligne :

| Groupe | Entrées |
|---|---|
| 1 | Fiche Lapins, Fiche Pondeuses, Fiche Volailles Reproducteurs, Fiche Porcs, Fiche Escargots |
| 2 | Suivi Reproduction, Calendrier Soins & Vaccins |
| 3 | Ventes & Devis, Gestion Stocks, Tableau de Bord, Saisie Dépenses, Comptabilité, Rapports et Exports |

**Les 13 cibles existent au poste** (`EcranPoste`). Le web n'applique aucun filtre de rôle au panneau : c'est la route qui refuse. Au poste, `GardeEcran` jouera ce rôle.

Le second bouton flottant, « Visite guidée » (`help`, bleu), est **inerte au web** : ne pas le porter tant qu'il ne fait rien.

### 1.4 Toasts — ⚠️

| Web (`toast-container`) | Poste |
|---|---|
| En haut à droite, empilables, 3,5 s | SnackBar Material par défaut, en bas, sans composant commun |
| Icône 20 px, `text-sm font-semibold` | aucune icône |
| Succès émeraude `check_circle` | fond par défaut |
| Erreur `error-red` `error` | `errorDeep` (#BA1A1A) ou fond par défaut |
| Avertissement jaune `warning` | absent |

---

## 2. Tableau de bord (`Dashboard/Index.php`)

**Conforme :** la structure (sections, titres, libellés et icônes des 8 KPI, 5 onglets, colonnes du Top 5). **Divergent :** les règles de calcul et les contenus.

### Valeurs « — » au poste alors que la donnée y est

| Élément | Source au poste |
|---|---|
| Dettes Fournisseurs | `payables` descend depuis 14.79 ; le motif « Table non synchronisée » est faux |
| Gestantes (Lapins, Porcs) | `livestock_reproduction_events` |
| Résultat Net | le web calcule CA − achats |
| Marge du Top 5 | le web utilise le PMP |

### Calculs et contenus divergents

- **Source des dépenses.** Le web prend les **achats** (`Purchase.total`) pour le KPI Dépenses, la courbe et les statistiques ; le poste prend les charges (`expenses`). Or `purchases` est disponible au poste.
- **Période.** Le web est calé sur le mois courant, avec la période « Du / au » désactivée ; au poste, la période est active et pilote les données.
- **Sous-textes manquants au poste :** « Mois précédent : X F (±y %) », « Marge nette : X % », pourcentages des tuiles Revenu et Dépenses.
- **Mentions périmées au poste :** « Ce poste uniquement » (les ventes de toute la ferme descendent depuis 14.80) et « Ventes et dépenses saisies sur ce poste ».
- **Alertes critiques :**
  - « Créance en retard — {client} ({n} jours) » ❌ ;
  - plafond de 6 alertes ❌ ;
  - liens ❌ ;
  - libellés et formule de mortalité ⚠️.
- **Transactions récentes :**
  - onglets Achat et Factures marqués « non embarqués » alors que `purchases` et `sales.mecef_status` sont au poste ;
  - onglet Devis ❌ (pas de table `quotes`) ;
  - lignes Vente : « ID8 · client » et jaune si crédit, au web.
- **Activités du jour :** le web lit `audit_logs` (auteur, module) ; le poste reconstitue ses propres libellés.
- **Sélecteur d'état :** le web propose 8 options qui naviguent, et active le bouton PDF ; le poste est inerte.
- **Périmètre des bandes :** le web filtre `status = 'actif'` en plus de `is_active` (Effectif, Lots actifs, Marchands) ; le poste ne filtre que `isActive`.
- **Formats :** virgule décimale, séparateur de milliers, seuil de mortalité `> 5` (le poste utilise `≥ 5`).

---

## 3. Gestion Élevage (`GestionElevage.php`)

| Élément | Verdict | Détail |
|---|---|---|
| 4 KPI (Effectif Total Vivant, Bandes Actives, Alertes Stock Aliment, Taux Mortalité (mois)) | ❌ | aucun repository au poste |
| Intertitre « Registres par Espèce » | ❌ | |
| Grille 1 / 2 / 3 colonnes | ⚠️ | une seule colonne au poste |
| Carte « Bandes & Sujets » | ❌ | aucun écran gestion-bandes au poste |
| Cartes Fiches | ⚠️ | icônes, descriptions, titre « Fiches Volailles » ; Escargots grisé au web si le module est désactivé, masqué au poste |
| Intertitre « Accès Rapides — Élevage & Soins » | ❌ | |
| Accès rapides Suivi Reproduction, Soins et Vaccins, Dashboard Élevage | ❌ | les trois écrans existent pourtant au poste |
| Accès rapide Transferts entre Bandes | ✅ | carte présente, mais mal placée |
| Sous-titre | ⚠️ | « Vue d'ensemble du cheptel et accès rapide aux registres de chaque espèce. » |

---

## 4. Dashboard Élevage (`DashboardElevage.php`)

**Conforme :** les 5 onglets (libellés, ordre, style), les 4 cartes de Rentabilité, la régression linéaire.

### Formules divergentes

- **GMQ.** Le web calcule un GMQ cumulé, de la première à la dernière pesée (`GrowthAnalysisService::gmqCumule`), avec 1 décimale et `null` sur 0 jour. Le poste prend les deux dernières pesées avec `max(1, jours)`.
- **KPI Mortalité.** Le web l'intitule « Cumulée (7j) » et calcule sur 7 jours, avec le dénominateur `previousEffectif()`, au format « 2,5 % ». Le poste l'intitule « (mois) » et calcule sur le mois.
- **Périmètre des bandes.** Le poste ne filtre pas `status = 'actif'` : les bandes clôturées entrent dans l'effectif, le GMQ et les prévisions.
- **Espèces.** Le web affiche les espèces `enabled()` ; le poste en code quatre en dur (`ModulesConfig` n'est pas lue).
- **Analyse sanitaire.** Le web compte les soins des bandes actives et `is_active` ; le poste compte tous les soins. La morbidité (`infirmary_records` en cours ÷ effectif) est toujours « — » au poste.

### Structure divergente

- **Synthèse.**
  - « GMQ par Bande — Résumé » ❌, remplacé par une courbe ➕.
  - « Rappels VMS à venir » : le web n'a qu'un texte et un lien ; le poste affiche une liste ➕.
  - Cartes par filière : 3 lignes au web, 4 au poste.
- **GMQ & Croissance.** 6 colonnes au web (Bande · Filière · Poids Initial (g) · Poids Actuel (g) · Jours · GMQ (g/jour)), avec « Pesées insuffisantes » ; le poste en a 8, et ajoute des cartes, un filtre et une courbe ➕.
- **Prévision.** Tableau web : Bande · Poids Actuel (g) · Tendance (g/j) · Projection à 30 jours (g), avec la ligne « Historique insuffisant (3 pesées minimum requises) ». Ce tableau est ❌ au poste, remplacé par un sélecteur, des horizons et 3 cartes ➕.
- **Rentabilité, détails :**
  - acquisition absente : le web affiche « En attente » ;
  - provende sans prix : « 0 FCFA » au web, « — » au poste ;
  - légende du coût par sujet ;
  - lien de l'état vide ;
  - frais vétérinaires sans le filtre `is_active`.

---

## 5. Suivi Reproduction (`SuiviReproduction.php`)

**Conforme :** les onglets, les calculs des KPI (gestantes, palpations dues, mises bas), le résumé du couvoir, la modale de saillie (titre et boutons).

| Élément | Verdict | Détail |
|---|---|---|
| Actions de cycle | ❌ | Palpation / Retour chaleur + et −, « Saisir Mise Bas » et sa modale, « Clôturer (Sevrage) » ; inertes au poste |
| Lien « Saisir le Couvoir du Jour → » | ❌ | |
| Colonnes | ⚠️ | 9 au web (Bande, N° Lapine, Date Saillie, Mâle N°, Palpation, Mise Bas Attendue, Nés (Vivants), Statut, Action) ; 12 au poste pour les lapins, 10 pour les porcs |
| Contenu des cellules | ⚠️ | palpation, mise bas réelle, « X (Y morts) » |
| Statuts | ⚠️ | « Réforme / Échec », « Cycle Clôturé » |
| Rappel du cycle | ⚠️ | Lapins : 4 étapes au web, avec flèches ; « Boîte à nid J+28 » ➕ |
| Sous-titres et titres | ⚠️ | Volailles et Escargots ; « (mois) » sur le 3ᵉ KPI ; icônes des KPI ; ordre KPI / onglets |
| Modale de saillie | ⚠️ | n° du mâle **facultatif** au web ; option « -- Sélectionner -- » |
| États vides, message de succès | ⚠️ | |

---

## 6. Soins et vaccins (`SoinsVaccinsHub.php`)

**Conforme :** les onglets, le titre, le sous-titre et le bouton du registre, la légende du calendrier, les règles de rémanence.

| Élément | Verdict | Détail |
|---|---|---|
| Onglet Suivi Sanitaire (infirmerie) | ❌ | `infirmary_records` n'existe pas au poste : KPI « Animaux en quarantaine » « — », 4 KPI, tableau, modale, actions Réintégrer / Décès |
| Calendrier | ⚠️ | le web lit `veterinary_calendar_events` (absente au poste), le poste calcule à partir du protocole |
| Calendrier, fonctions | ❌ | « Planifier une Intervention » et sa modale ; confirmation d'administration au clic |
| Calendrier, fenêtre | ⚠️ | J → J+13 au web, J−3 → J+10 au poste |
| KPI « Vaccinations planifiées » | ⚠️ | règle différente |
| Archivage d'un soin | ❌ | `is_active` absent au poste ; limite de 50 lignes |
| Registre | ⚠️ | 6 colonnes au web (« Statut » ➕ au poste) ; cellule « CODE (Espèce) » |
| Coût | ⚠️ | « 12 500 FCFA » au web |
| Modale Nouveau Soin | ⚠️ | largeur sm ; aide et couleur rouge de la rémanence ; exemples ; zone de texte pour les symptômes |
| Messages | ⚠️ | « Soin enregistré — bande bloquée à la vente pendant N jour(s). » |
| Filtres et recherche ; Importer et Exporter PDF (inertes) | ➕ | |

---

## 7. Paramètres Élevage (`ParametresElevage.php`)

Le poste reproduit les 4 onglets, mais **en lecture seule par choix** : les référentiels sont imposés par le serveur.

| Élément | Verdict | Détail |
|---|---|---|
| Boutons Ajouter, Modifier, Supprimer, Enregistrer | ❌ | assumé « référentiel serveur » ; à arbitrer, voir H8 |
| Bloc « Rappel des soins planifiés » (15.52) | ❌ | `rappel_soins_jours` n'est pas servi au tirage |
| Libellés | ⚠️ | colonne « Ration (g/tête/jour) » ; sous-titres avec texte en plus ; préfixes avec « (R1..Rn) » ; « Aperçu » ➕ |
| Formats | ⚠️ | « 25 Kg », « 250 FCFA » ; couleur de la ration ; tris |

---

## 8. Synchronisation

### Poste

- Le moteur est complet, mais **aucun déclenchement automatique** n'existe (B2).
- Un bouton « Synchroniser » existe en pied de barre latérale, mais il devient inatteignable quand la barre déborde.
- La barre supérieure n'a qu'une pastille non cliquable.
- Aucun horodatage « dernier succès ».
- ⚠️ **Défaut réel :** `AppDatabase.pendingCount()` omet 8 tables pourtant envoyées (products, suppliers, customers, supplier_payments, customer_advances, advance_imputations, purchase_returns, supplier_refunds). Un article ou un client créé hors ligne n'apparaît pas « en attente ».
- `synchronisation_screen.dart` n'a pas de libellé pour plusieurs tables : le nom technique s'affiche.

### Serveur

- Seule trace par poste : `personal_access_tokens.name` (= identifiant du poste) et `last_used_at`.
- Un envoi produit une ligne `api.sync_push` dans `audit_logs`, sans poste ni compteurs ; un tirage n'est pas journalisé.
- **Aucune page web ne montre l'état des postes.**

### Décision antérieure contredite

`README_SPRINT0.md:107` et `:9667`, ainsi que `agrierp_laravel/CLAUDE.md`, excluaient tout bouton « Synchroniser » du web, parce qu'il serait « un décor sans mécanisme ». Le client demande le 19/10/2026 un bouton et une modale **des deux côtés**. Le PRD `docs/prd/synchronisation-barre-superieure.md` donne au web un rôle réel, sans décor : l'**état de synchronisation des postes**.

### Directive « synchronisation » contre l'existant

| Directive | Existant | Décision |
|---|---|---|
| Route unique `POST /api/v1/sync` | `GET /api/sync/pull` + `POST /api/sync/push` | ❓ D-SYNC-1 |
| Table outbox `operations_sync_local` + `uuid_operation` + table de déduplication 30 j | colonne `sync_status` par table, idempotence par l'UUID de l'enregistrement | ❓ D-SYNC-1 |
| Lots de 50 | un seul envoi contenant toute la file | ❓ D-SYNC-2 |
| Réessais exponentiels, synchronisation automatique | aucun (B2 🔧) | ❓ D-SYNC-3 |
| Synchronisation à la clôture de caisse | la clôture n'existe pas (Sprint C ❓) | dépend de C |
| Vente acceptée malgré une rupture, signalée dans `anomalies_synchronisation` | acceptée **en silence**, stock négatif possible | ❓ D-SYNC-4 |
| Le poste crée ou modifie des articles hors ligne | **existe déjà** (`manage-stocks`) | — |
| Jeton dans `flutter_secure_storage` | **existe déjà** | — |
| Appairage dans Paramètres Général > Synchronisation (admin) | pas d'appairage : chaque utilisateur se connecte, le jeton porte le nom du poste | ❓ D-SYNC-5 |
