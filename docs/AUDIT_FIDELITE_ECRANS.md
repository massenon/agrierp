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
  - onglet Devis ✅ (la table `quotes` existe au poste depuis le ticket DEV, 21/10/2026 : le Tableau de bord ne la lit pas encore, ticket DEV-2) ;
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

---

## 9. Date et Mois — mise en page (ticket MP1, 21/10/2026)

**Demande du client :** « dans le poste, revoir la position des libellés et champs Date et Mois ; il faut contrôler les marges, espacements, alignements et proportions. »

**Maître :** les Blade (`resources/views/livewire/**` et `components/mois-de-fiche.blade.php`). Toutes les valeurs ci-dessous sont **lues** dans les classes Tailwind ; `tailwind.config.js` ÉTEND l'échelle d'espacement (`xs` 4, `sm` 8, `md` 16, `lg` 24, `xl` 32) sans remplacer l'échelle par défaut : `h-9` = 36, `h-10` = 40, `h-11` = 44, `w-8` = 32, `py-1.5` = 6. `text-xs` = 13,6 px, interligne 16 (surcharge de `common.css`) ; `text-sm` = 14 px, interligne 20 ; `text-[10px]` hérite l'interligne 1,5 du préflight.

### 9.1 Les cinq gabarits de champ Date du Blade

| Gabarit | Où | Classes lues dans le Blade | Libellé |
|---|---|---|---|
| **Fiche** (`h-9`) | en-tête des 5 fiches journalières (Lapins, Porcs, Pondeuses, Reproducteurs, Escargots) | `h-9 px-md border border-outline-variant rounded-lg text-xs font-bold text-brand-forest bg-surface-zebra`, dans `flex items-center gap-xs flex-wrap` | **à côté, avant** : `text-xs text-outline font-semibold` « Date : » ; `gap-xs` |
| **Mois** | `components/mois-de-fiche.blade.php` | boîte `flex items-center h-9 border rounded-lg bg-surface-zebra overflow-hidden` ; flèches `w-8 h-9`, icône `text-[18px]` ; mois `px-sm text-xs font-bold text-brand-forest` | « Mois : » `text-xs text-outline font-semibold`, enfant PROPRE du `flex-wrap gap-xs` |
| **Filtre** (`py-2` / `py-1.5`) | Rapports, Liste d'Achats, Bilan, Historique des ventes, Tableau de bord, Compta analytique… | `text-xs border border-outline-variant rounded-lg px-sm py-2 bg-white` (34 px) ; variante `py-1.5` (30 px) | aucun libellé : le mot « au » (`text-xs text-outline`) sépare début et fin ; `gap-sm` ou `gap-xs` selon le conteneur |
| **Sans bordure** | Grand Livre, Rapprochement | `text-xs font-bold text-brand-forest border-0 bg-transparent p-1` dans `flex items-center gap-xs bg-surface-zebra rounded-lg px-sm py-1` | « au » |
| **Formulaire** (`h-11`) | modales et « Nouvelle Dépense » (~25 champs) ; caisse en `h-10 text-xs bg-white` | `w-full h-11 px-md border rounded-lg text-sm` (+ `is-invalid` : bord `#BA1A1A`, fond `#FFF5F5`) | **au-dessus** : `block text-[10px] text-brand-forest font-bold uppercase mb-xs` ; erreur `.invalid-feedback` 11 px, `mt: 2px` ; paires `grid grid-cols-2 gap-sm` |

### 9.2 Table des écarts (avant correction)

| # | Écran du poste | Blade (maître) | Poste (avant) | Correction |
|---|---|---|---|---|
| E1 | 4 fiches (`EnTeteSaisieFiche`) : Lapins, Porcs, Reproducteurs, Escargots | « Mois : » et sa boîte sont deux enfants du `flex-wrap gap-xs` | « Mois : » collé à sa boîte dans un `Row` : le groupe se replie en bloc, jamais séparé | libellé et boîte aplatis dans la barre (`BarreChoixFiche`) |
| E2 | idem | `flex-wrap gap-xs` : écart de 4 px entre les lignes de repli | `Wrap(spacing: xs)` sans `runSpacing` : 0 px entre deux lignes | `runSpacing: AgriSpacing.xs` |
| E3 | idem | `<input type="date">` : texte + indicateur de calendrier du navigateur à droite (le champ fait ~ 135 px) | texte seul (~ 110 px) : proportions Date / Mois / Bande différentes | indicateur `calendar_today` 16 px à droite du texte (`ChampDateFiche`) |
| E4 | idem | libellé `text-xs` : interligne 16 | interligne du moteur (non fixé) : 1 px de décalage vertical possible avec le champ de 36 px | `StylesChampsAgri.etiquetteEnLigne` fixe l'interligne à `xsInterligne` |
| E5 | Fiche Pondeuses | même en-tête que les quatre autres | **copie** de l'en-tête (`_enTeteSaisie`, `_cadreSelection`, `_etiquetteEnLigne`) avec `36` et `FontWeight.w600` en dur | utilise `EnTeteSaisieFiche` : une seule implémentation |
| E6 | `MoisDeFiche` | `h-9`, `w-8`, `text-[18px]` | `36`, `32`, `18` en dur | `AgriChamps.hauteurCompacte` / `largeurFleche` / `iconeFleche` |
| E7 | Rapports & Exports (Du / Au) | `<input>` `px-sm py-2 text-xs bg-white` : 34 px de haut, texte seul, pas d'icône | `OutlinedButton.icon` : hauteur 40 + marges du thème, icône `event` ajoutée (absente du web), forme et teinte du thème Material | `ChampDateFiltre` (34 px, bordure `outlineVariant`, `rounded-lg`) |
| E8 | Rapports & Exports | trois enfants plats (`champ`, « au », `champ`) puis `ml-auto` dans `flex-wrap gap-sm` | début / « au » / fin regroupés dans un `Wrap` interne sans `runSpacing` | `Wrap` plat, `spacing` et `runSpacing` = `sm` |
| E9 | Tableau de bord (période) | `py-1.5` (6) | `vertical: 6` en dur ; pas d'indicateur de calendrier ; fond et trait propres | `ChampDateFiltre(compact: true, desactive: true)` |
| E10 | Tableau de bord | `flex-col sm:flex-row` : ligne dès **640 px** | bascule sur `AgriBreakpoints.large` (**1024 px**) : entre 640 et 1023 px, les dates et le choix d'état s'empilent alors que le web les aligne | `AgriBreakpoints.petit` (`sm:`) |
| E11 | Tableau de bord | `<select … flex-1 sm:w-56>` : 224 px dès `sm:`, sinon il remplit la ligne | 224 px seulement à partir de 1024 px, 180 px en dessous | 224 px dès `sm:`, `Expanded` en dessous |
| E12 | Grand Livre | `p-1` (4) dans `px-sm py-1` ; icône de calendrier native | `all(xs)` correct mais `vertical: 4` en dur, pas d'indicateur, pas de clé de zone | `ChampDateSansBordure` ; zone `gl-periode` à `sm` / `margeVerticaleConteneur` |
| E13 | Courriers, Documents administratifs, Archivage (3 dates : Date, Date d'archivage, Échéance) | `w-full h-11 px-md border rounded-lg text-sm` | `OutlinedButton` : forme en pilule, bord et teinte du thème, hauteur du thème, texte à gauche par `Align` | `ChampDateFormulaire` (44 px, `rounded-lg`) |
| E14 | Achats : Remboursement ; Fournisseurs : Règlement | idem + libellé `text-[10px] font-bold uppercase text-brand-forest mb-xs` | `OutlinedButton` ; le libellé du Règlement est en `xs` gras SANS majuscules, ni vert forêt, ni `mb-xs` | `ChampDateFormulaire` (libellé et champ ensemble) |
| E15 | Stocks (Date du Nouveau Stock) ; Soins (Date du Soin, Date Prévue) ; Suivi Reproduction (Date de Saillie) | `h-11` fixe | `InputDecorator` : `vertical: 12` en dur + interligne du moteur : hauteur ≈ 43,5 px qui varie avec le thème | `ChampDateFormulaire` : 44 px exactement |
| E16 | Transferts entre bandes (Date du Transfert) | libellé au-dessus (`mb-xs`), champ `h-11`, grisé (`bg-surface-zebra text-outline`) en constitution | libellé flottant DANS le cadre (`labelText`), casse « normale » | `ChampDateFormulaire(desactive: constitution)` |
| E17 | Saisie des Dépenses | `h-11`, erreur `.invalid-feedback` (11 px, `mt: 2px`) | déjà fidèle en valeurs, mais **dupliquée** : `44`, `11` et `2` en dur, `_cadre` local, pas d'indicateur de calendrier | `ChampDateFormulaire` (mêmes valeurs, source unique) | ⚠️ DEP5 (21/10/2026) : le champ vit désormais dans la modale « Nouvelle Dépense » (`ModaleDepense`) ; mêmes valeurs, mesures de `champs_date_mise_en_page_test.dart` prises modale ouverte.
| E18 | Caisse (Date de la vente) | `h-10 px-md text-xs bg-white`, texte normal, erreur 11 px `mt: 2px` | hauteur 34 (`vertical: sm`), texte en gras vert forêt, erreur 10 px à `xs` | `ChampDateFormulaire(variante: caisse)` : 40 px, texte `xs` normal |
| E19 | Attestations (Début / Fin) | `grid grid-cols-2 gap-sm`, `h-11`, libellé `text-[10px]` | libellé conforme ; champ `TextField` à `vertical: 14` en dur et bouton calendrier à zone de toucher de 48 px : **48 px de haut au lieu de 44** (mesuré, rouge avant correction) | hauteur `h-11` exacte (marges calculées sur l'interligne de `text-sm`, zone de toucher réduite) ; saisie au clavier conservée (concession du poste) |
| E20 | Archivage des documents (Date d'archivage / Date d'expiration) | `grid grid-cols-2 gap-sm` : les deux champs **côte à côte**, libellés « Date d'archivage * » et « Date d'expiration » | empilés l'un sous l'autre, libellé sans l'astérisque | `Row` de deux `Expanded` à `gap-sm` ; bouton « Effacer » (ajout du poste) rangé dans le champ |

**Écrans avec un champ Date au Blade et sans champ au poste** (hors périmètre : le champ n'existe pas, il se construit par un ticket de fonctionnalité) : Liste d'Achats (filtre) — ⚠️ « Historique des ventes » est porté depuis AV2 (§ 11, `ChampDateFiltre` compact), Bilan, Comptabilité analytique, Rapprochement bancaire, Balance âgée, Immobilisations, Journal comptable (saisie), Devis, Avances, Bons de commande, Feuille de pointage, Registre des stagiaires et des employés, Enregistrer des sujets, Registre des reproducteurs, Transformation. Les champs « Jour / Âge » de Paramètres Élevage sont des nombres, pas des dates.

**Concession du poste, assumée :** le calendrier s'ouvre dans le `showDatePicker` de Flutter, pas dans le sélecteur natif du navigateur ; l'indicateur dessiné à droite du texte (16 px) en tient lieu.

**Écarts relevés et NON corrigés (décision documentée) :**

- *Fiche Reproducteurs :* ✅ **écart disparu (MP1-Q1, tranché le 21/10/2026)** — le Blade écrivait la barre `flex items-center gap-xs` sans `flex-wrap` ; `flex-wrap` y est ajouté (retouche web), comme aux quatre autres fiches. Le poste replie la barre dans les cinq cas ; le garde-fou `champs_date_mise_en_page_test.dart` exige désormais `flex-wrap` sur les cinq Blades.
- *Rapports & Exports :* `ml-auto` aligne les boutons d'export à DROITE même quand ils passent seuls à la ligne ; le poste les laisse à gauche dans ce cas (`WrapAlignment.spaceBetween` ne sait pas aligner un enfant seul). Visible seulement sous ~ 700 px de largeur de contenu.
- *Police :* le banc de test dessine en police Ahem (toutes les chaînes y sont deux fois plus larges qu'en Inter) ; les mesures de largeur d'un champ sont donc des mesures de STRUCTURE (marges, hauteurs, alignements), pas de largeur réelle.

**Hors périmètre, relevé :** dans les modales de Transferts, de Suivi Reproduction et de Courriers, les champs VOISINS de la date (texte, listes) ont encore le gabarit Material (`labelText` flottant ou `xs`) ; leur reprise est un ticket à part (MP2). Même chose pour les libellés voisins des modales Courriers, Documents, Archivage, Remboursement et Règlement : écrits en `xs` gras sans majuscules, alors que le Blade a `text-[10px] uppercase text-brand-forest` — seul le libellé du champ Date est désormais conforme, il se détache donc de ses voisins jusqu'à MP2.

### 9.3 Garde-fous (`test/champs_date_mise_en_page_test.dart`)

1. **mesures** à 640, 1024 et 1440 px (et 360 px pour l'en-tête des fiches) : libellé à `mb-xs` au-dessus du champ, champs de même hauteur et de même ordonnée sur une même ligne, libellés en ligne centrés sur leur champ à `gap-xs`, flèches du Mois de 32 × 36 px, aucun débordement ;
2. **écrans** : Rapports, Tableau de bord (640 / 700 / 1024), Grand Livre, Saisie des Dépenses ;
3. **épreuve de mutation** (faite, puis annulée) : marge libellé → champ `xs` → `sm` (4 rouges), `hauteurFormulaire` 44 → 40 (2 rouges), `runSpacing` de la barre des fiches retiré (2 rouges), `margeVerticaleCompacte` 6 → 5 (2 rouges) ;
4. **lecture du Blade** : les classes de chaque `<input type="date">` sont lues et comparées à `AgriChamps` / `AgriSpacing` ; un gabarit nouveau au Blade rougit le test (« à auditer ») ; tout écran du poste qui appelle `showDatePicker` doit passer par un champ partagé (`lib/core/widgets/champs_date_agri.dart`).

---

## 10. Ventes & Devis — onglet « Devis Prestations » (ticket DEV, 21/10/2026)

**Écart « Devis » SOLDÉ.** Avant : carte « non embarqué » (`devis-non-embarque`), aucune table `quotes`, aucun dépôt, `SyncController` n'en parlait pas. Après : l'onglet reprend `devis.blade.php` / `Devis.php` à l'identique ; PRD `docs/prd/devis-poste.md`. Le garde-fou `test/devis_blade_test.dart` LIT le Blade, le composant, `SaisieDevisAction`, `Quote`, le hub, l'export PDF et `lang/fr/validation.php` : un libellé, une colonne, un statut, une icône, un message ou une règle changés au web fait rougir le poste.

| Élément du Blade | Verdict | Détail |
|---|---|---|
| En-tête (icône `request_quote`, « Devis & Proforma », sous-titre) | ✅ | titre 24 px à partir de `lg`, 20 px en dessous |
| Boutons « Exporter » (`export-ventes`) et « Nouveau Devis » (`manage-ventes`) | ✅ | « Exporter » édite les devis AFFICHÉS (`DevisRepository.documentPdf`, mêmes colonnes que `exports/devis.blade.php`, `devis-AAAA-MM-JJ.pdf`) ; le web montre « Nouveau Devis » à tous et refuse au serveur, le poste ne le montre pas à qui n'a pas `manage-ventes` |
| Quatre cartes : Devis Actifs, Valeur Totale, Taux de Conversion, En Attente de Relance | ✅ | libellés, icônes et couleurs lus du Blade ; formules du composant (statuts actifs, mois du jour, arrondi PHP) |
| Accordéon « Indicateurs de performance » | ⚠️ assumé | `md:hidden` au web : le poste est un écran de bureau, cartes toujours déployées |
| Barre « N° devis, client... », « Statut : Tous », « Client : Tous » | ✅ | recherche 300 ms, sans casse ni accents (collation du serveur) |
| Tableau : 7 colonnes, badges, « Aucun devis pour le moment. » | ✅ | « — » en N° Devis tant que le serveur n'a pas attribué le numéro (client inconnu : « — ») |
| Icônes d'action selon le statut (`send`, `check_circle`, `cancel`, `receipt_long`, `edit`, `delete`) | ✅ | mêmes infobulles, mêmes conditions |
| Modale `modal-create-devis` (`max-width="md"`) | ✅ | 7 champs, `ChampDateFormulaire` pour « Date du Devis », erreurs sous les champs avec les messages de `lang/fr/validation.php` |
| `x-modal-confirm-delete` | ✅ | « Confirmer l'archivage », « Archiver » en `error-red` |
| Toasts | ✅ | mot pour mot (lus du composant) |
| « Convertir en Facture » | ✅ identique | le web n'implémente pas la conversion : son message d'attente est repris (question DEV-Q1) |
| ➕ « À envoyer » / « Refusé » + motif du serveur sous le numéro | ➕ | file d'envoi du poste, le web n'en a pas |
| ➕ Écarts corrigés AU WEB d'abord (article 5) | ➕ | exercice clos refusé ; cycle de statut contrôlé ; devis archivé ou facturé non modifiable ; erreur sous « Date du Devis », « TVA » et « Validité » (le Blade n'affichait aucune erreur de ces champs) |
## 11. Historique des Ventes et Retours et Avoirs (tickets AV1 / AV2, 21/10/2026)

**Méthode.** Lecture ligne à ligne de `historique-ventes.blade.php` + `HistoriqueVentes.php` et de `retours-avoirs.blade.php` + `RetoursAvoirs.php` contre le Dart du poste. L'écran avait été porté depuis la MAQUETTE (`historique-ventes.html`) et ses garde-fous comparaient à la maquette : la page sort de `fidelite_libelles_test` / `conformite_structure_test` (le Blade fait foi, comme H7) et est verrouillée par `historique_ventes_blade_test.dart`. Onglets extraits du hub : `historique_ventes_onglet.dart`, `retours_avoirs_onglet.dart`.

### 11.1 Historique des Ventes — écarts trouvés, tous corrigés

| # | Blade (maître) | Poste avant | Poste après |
|---|---|---|---|
| H1 | Sous-titre « Toutes les ventes enregistrées de l'entreprise. » | « Ventes encaissées sur ce poste… » (FAUX depuis que `sales` descend) | texte du Blade |
| H2 | Bouton « Nouvelle Vente » (pilule émeraude, `add_circle`) | absent | présent, ouvre le hub sur « Enregistrer Vente » |
| H3 | Période : deux `<input type="date">` bornés à l'exercice (`px-sm py-1.5`), défaut = début du mois → aujourd'hui dans l'exercice | absente | `ChampDateFiltre` compact ×2, `periodeParDefaut` / `bornerPeriode`, calendrier borné |
| H4 | Cartes sur la PÉRIODE (ventes validées) | sur toutes les ventes du poste | sur la période |
| H5 | Cartes : icônes `payments` / `receipt` / `shopping_cart` / `request_quote`, unité « FCFA » en petit, grille 2 → 4 colonnes dès `md:` (768 px) | sans icône, unité collée, 4 colonnes dès `lg:` (1 024 px), hauteur fixe | icônes, `unite`, `GrilleKpi` (`md:`, hauteur du contenu) |
| H6 | Panier moyen `0` sans vente | « — » | « 0 FCFA » (c'est un calcul du web, pas une donnée inconnue) |
| H7 | Recherche « Facture, client... » (id complet ou nom du client, 300 ms) | absente | présente, mêmes règles |
| H8 | « Statut » = Payée (validée hors crédit) / En attente (validée à CRÉDIT) / Annulée | comparait la colonne `status` à `validee` / `en_attente` : « En attente » ne trouvait jamais rien | règles du web |
| H9 | « Mode » : cinq modes dont « Avance » | quatre, sans « Avance » | cinq |
| H10 | « Client » : liste des clients actifs | filtre inerte grisé (« customers ne descend pas » — faux depuis 14.75) | actif, par ordre alphabétique |
| H11 | « Réinitialiser » (`restart_alt`) vide recherche + 3 listes | sans icône, ne vidait que 2 listes | fidèle |
| H12 | Pas de boutons « Excel / PDF » | deux boutons inertes | retirés |
| H13 | Facture = `strtoupper(substr(id, 0, 8))` | « — » (« aucun numéro n'existe » : faux, c'est ce que le web affiche) | idem web |
| H14 | Client = nom (ou « Client Anonyme ») | « Client non synchronisé » | nom (fichier clients, sinon nom servi avec la vente) |
| H15 | Remise = `discount` | toujours 0 (`discount` ne descendait pas) | `subtotal` et `discount` servis et absorbés |
| H16 | Payé = total − reste ; Reste = solde de la créance de la vente ; reste > 0 en rouge gras | issus de `cash_received` (« — » hors espèces) | règle du web ; vente à crédit pas encore reçue : le reste est le total (le serveur ouvrira la créance) |
| H17 | Mode = libellé (« Espèces ») | valeur brute (`especes`) | libellé |
| H18 | Pastille : Annulée / En attente (reste > 0) / Payée | statut brut | règle du web, couleurs du Blade |
| H19 | Ligne annulée à `opacity-50` ; client en gras forêt ; facture `font-mono` émeraude ; colonnes numériques à droite | non | fidèle |
| H20 | Actions : « Voir » + « Annuler » (sauf vente annulée ; `@lectureSeule`) | une icône PDF inerte | deux boutons de 26 px (`p-1`), « Annuler » grisé en lecture seule ou sans `manage-ventes` |
| H21 | Détail : tiroir `w-96` (référence mono, Client, Date, Articles, Sous-total, Remise, Total, « Télécharger PDF », « Fermer », Échap, voile) | absent | présent |
| H22 | Modale « Annuler cette vente ? » (pastille `warning`, texte, « Annuler » / « Oui, Annuler la Vente ») | absente | présente (gabarit `x-modal`, pas `ModaleConfirmation`) |
| H23 | Tri : date effective puis identifiant décroissants | date seule | idem web |
| H24 | État vide « Aucune vente pour le moment. » | « — Aucune vente encaissée sur ce poste pour ces critères — » | texte du Blade |
| H25 | Pagination 25 / page dans l'exercice | idem, mais sans clé de page ramenée à 1 par un filtre | page 1 à chaque changement de filtre |

### 11.2 Retours et Avoirs — construit à l'identique

Neuf colonnes, quatre cartes (`border-l-info-blue` / `accent-yellow` / `brand-emerald` / `error-red`, icônes `assignment_return` / `payments` / `inventory_2` / `percent`), cinq sections de modale, états vides, toasts (`Retour enregistré — produit réintégré au stock.`, `… réformé, aucun impact stock.`, `Avoir marqué comme traité.`), messages de validation (`lang/fr/validation.php`, lus par le garde-fou) et refus du serveur (`AvoirClientService`, lus par le garde-fou).

### 11.3 ÉCARTS ASSUMÉS (hors ligne : le poste enregistre la demande, le serveur fait les effets)

| Écart | Raison | Garde-fou |
|---|---|---|
| Numéro d'un avoir non reçu : « — » | `AV-AAAA-NNN` est attribué par le serveur seul (séquence annuelle) | `avoirs_poste_test` |
| « Non envoyé » (avoir) / « Non envoyée » (vente) sous la pastille ; refus du serveur dit mot pour mot | la demande n'existe pas encore côté ferme | idem |
| Toast du retour : « Retour enregistré sur ce poste — le stock sera réintégré à la synchronisation. Avoir comptabilisé (débit 701 / crédit 411) par le serveur. » | le web dit « réintégré » parce qu'il le fait à l'instant | `avoirs_blade_test` |
| Toast d'annulation : « Vente annulée — le stock sera réintégré à la synchronisation. » | idem | `historique_ventes_blade_test` |
| « Télécharger PDF » exige le réseau et ENREGISTRE le fichier (Documents\AgriERP) au lieu de le télécharger | le ticket est produit par le serveur ; pas de navigateur au poste | `historique_ventes_poste_test` |
| « Annuler » grisé sans `manage-ventes` | le web laisse le bouton et refuse (403) à l'envoi ; au poste un bouton qui échouerait à la synchronisation tromperait | `historique_ventes_poste_test` |
| Calendrier Flutter au lieu du `<input type="date">` natif | plateforme (voir § 9) | `champs_date_mise_en_page_test` |
| Sous 640 px, défilement horizontal au lieu des cartes `rtable` | fenêtre de bureau (≥ 640 × 480) | — |

### 11.4 Défauts du WEB trouvés et corrigés d'abord (le poste les aurait hérités)

Quantité retournée > vendue (50 sur 10), montant > ligne, retour d'une vente annulée, produit hors vente, exercice clos (« enregistré SANS écriture » ou stock bougé puis 500), plan comptable incomplet : tous refusés avant d'écrire, une transaction. **Non corrigés, signalés au client** (ne se décident pas à sa place) : l'avoir ne diminue pas la créance de la vente ; annuler une vente ne contre-passe ni l'écriture ni la créance (AV-Q1, AV-Q2 dans `docs/PLAN_FINALISATION.md`).

