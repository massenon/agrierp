# 04 — CHARTE ET CONFORMITÉ DU DESIGN (UI/UX du web LogiALVIA)

## USAGE

| Rubrique | Contenu |
|---|---|
| **Quand l'utiliser** | (a) Une fois, au socle (« W0 ») : créer `tailwind.config.js`, `app.css`, le layout et les composants partagés AVEC les jetons de LogiALVIA ; (b) à chaque écran web : tenir la charte et passer l'audit final de ce fichier ; (c) à chaque changement de jeton : mettre à jour web ET poste ensemble. |
| **Ordre** | Après `01_MASTER_PROMPT.md` et `02_ARCHITECTURE_WEB_ET_STACK.md` ; en parallèle de `03_DEVELOPMENT_STANDARDS.md`. Les modules (`20_MODULES_*`) y renvoient pour tout ce qui est visuel. |
| **Entrées requises** | `logialvia/docs/01_DESIGN_SYSTEM.md`, `06_COMPOSANTS_REUTILISABLES.md`, `E4`–`E9`, `G1`, `G2`, `K2` ; le code du poste `logialvia/logialvia_app/lib/core/{theme,widgets}` ; les composants web modèles d'LogiAgriERP ; si disponible, le prototype HTML de LogiALVIA (hors du dépôt cloné : à demander au client, jamais reconstruit de mémoire). |
| **Sorties attendues** | `logialvia_web/tailwind.config.js` (15 couleurs de LogiALVIA, espacements, rayons, police), `resources/css/app.css`, composants Blade partagés, garde-fous de conformité (section 11), fiche de recette visuelle signée par écran (section 12), rapport d'audit (PROMPT B). |

### Réponse courte : quelle conformité de design

Le web LogiALVIA reprend la **charte de LogiALVIA (marine `#1F3864` + or `#B58B2A`, police Roboto)**, PAS le vert/Inter d'LogiAgriERP : LogiAgriERP fournit les *patrons de composants et de preuve*, jamais ses couleurs. Chaque conteneur, ligne, colonne, espacement, alignement, animation et hiérarchie visuelle est **identique au poste**, prouvé par des jetons partagés, des gardes qui lisent les sources, des captures de référence et la check-list K2.

---

## PROMPT A (à copier) — Mettre en place la charte et les composants

````markdown
# RÔLE
Tu es le responsable du design system du web LogiALVIA (Laravel 12 + Livewire 3 + Tailwind 3.4). Tout est en français.
Lis d'abord `01_MASTER_PROMPT.md`, puis ce fichier en entier.

# CONTEXTE
Le poste Flutter LogiALVIA est la référence visuelle existante (31 écrans validés par la Gérante). Le web doit lui être
VISUELLEMENT IDENTIQUE : mêmes jetons, mêmes composants, même hiérarchie. Le design d'LogiAgriERP est un MODÈLE DE MÉTHODE
(`agrierp_laravel/tailwind.config.js`, `resources/css/app.css`, `resources/views/components/`,
`agrierp_flutter/lib/core/theme/agri_tokens.dart`), pas une source de valeurs.

# TÂCHES
1. Crée `logialvia_web/tailwind.config.js` avec EXACTEMENT les 15 couleurs, les espacements xs/sm/md/lg/xl et le rayon de la
   section 2, 4 et 5 de ce fichier. Une couleur absente de `logialvia/docs/01_DESIGN_SYSTEM.md` n'existe pas : si un besoin
   apparaît (ex. or lisible sur blanc), c'est une QUESTION au client (section 13), pas une valeur ajoutée.
2. Crée `resources/css/app.css` : `@font-face` Roboto locale (variable, `font-weight: 100 900`), Material Symbols local,
   `.text-xs { font-size: 0.85rem !important; }`, `.sidebar-gradient`, `table.rtable` (≤ 640 px), `.kpi-accordion` (< 768 px),
   `.toast-in`, `@media print`. Déclare les classes de composant APRÈS `@tailwind utilities`.
3. Crée les composants Blade partagés (section 7) : `layouts/app`, `layouts/guest`, `datatable`, `modal` (+ confirmations),
   `kpi-card`, `kpi-accordion`, `tab-page`, `toast-container`, `nav-card`, `sidebar-link`, `status-badge`, `form-field`,
   `pagination`, `module-pending`. Chacun avec classes Tailwind STATIQUES (tableaux de correspondance).
4. Écris les gardes-fous de la section 11 (ils lisent les sources) et fais-les passer au vert.
5. Produis la page de référence `/design-systeme` (réservée à `admin`, absente en production si le client le demande) qui affiche
   tous les composants dans tous leurs états : sert de cible de captures.
6. Rapporte au format du MASTER PROMPT, avec la liste des valeurs « à confirmer sur le prototype » restées ouvertes.

# CONTRAINTES
- Aucune couleur, taille ou espacement en dur dans une vue. Aucun CDN, aucune police externe.
- `text-xs` = 13,6 px. Ne jamais l'écrire 12 px.
- Décisions de mise en page sur la largeur de la FENÊTRE (media queries), jamais d'un conteneur.
- Ne copie pas une valeur d'LogiAgriERP quand LogiALVIA en a une propre (ex. en-têtes de tableau 12 px chez LogiALVIA, 10 px chez LogiAgriERP).

# CRITÈRES D'ACCEPTATION
- Un test lit `tailwind.config.js` et `logialvia_app/lib/core/theme/app_colors.dart` et vérifie 15/15 couleurs identiques.
- `grep -rn "#[0-9A-Fa-f]\{6\}" resources/views` ne renvoie rien (hors commentaires).
- La page `/design-systeme` s'affiche à 1440, 1280, 1024, 768 et 390 px sans défilement horizontal de la page.
- Chaque `<td>` d'un `x-datatable` porte `data-label`.

# INTERDITS
Couleur d'LogiAgriERP dans une vue LogiALVIA ; `text-[12px]` à la place de `text-xs` pour du corps de tableau ; modale par `@if` ;
classe Tailwind dynamique ; seconde instance d'Alpine ; animation non listée en section 8.
````

---

## 1. Principe de conformité et sources visuelles

Règle du client : **« chaque conteneur, ligne, colonne, espacement, alignement, animation et hiérarchie visuelle reste IDENTIQUE au poste. »**

Hiérarchie des sources VISUELLES (la plus forte d'abord) :
1. Le **prototype HTML** de LogiALVIA (31 pages ; non présent dans le dépôt cloné : à demander). Il a servi de maître au poste (`logialvia/docs/A1_MASTER_PROMPT.md`).
2. Le **poste** : `logialvia/logialvia_app/lib/core/theme/` (`app_colors.dart`, `app_spacing.dart`, `app_radius.dart`, `app_shadows.dart`, `app_typography.dart`, `app_breakpoints.dart`) et
   `logialvia/logialvia_app/lib/core/widgets/` (`app_button.dart`, `app_modal.dart`, `app_toast.dart`, `kpi_card.dart`, `carte_kpi_lisere.dart`, `champ_saisie_nombre.dart`, `shell/app_sidebar.dart`, `shell/app_top_bar.dart`, `shell/acces_rapide.dart`).
3. Les docs : `logialvia/docs/01_DESIGN_SYSTEM.md`, `06_COMPOSANTS_REUTILISABLES.md`, `E4_DataTables_Complet.md`, `E5_Modales_CRUD.md`, `E6_Formulaires.md`, `E7_Dashboards_KPI.md`, `E8_Responsive.md`, `E9_Impression_PDF.md`, `G1`, `G2`, `K2`.
4. **Une fois le web d'un écran validé, il devient le maître et le poste lui est fidèle** (doctrine, article 0) : la charte ci-dessous s'applique alors dans les DEUX sens.

Modèle de méthode (pas de valeurs) : `agrierp_laravel/tailwind.config.js`, `agrierp_laravel/resources/css/app.css`, `agrierp_laravel/resources/views/components/{datatable,modal,kpi-card,kpi-accordion,tab-page,nav-card,sidebar-link,toast-container,pagination}.blade.php`, `agrierp_flutter/lib/core/theme/agri_tokens.dart`.

---

## 2. Jetons de couleur (15, source : `logialvia/docs/01_DESIGN_SYSTEM.md`, `app_colors.dart`)

| Jeton Tailwind | Hex | Usage réel | Contraste mesuré |
|---|---|---|---|
| `brand-navy` | `#1F3864` | primaire : boutons d'action, en-têtes, texte de marque, début du dégradé de la barre latérale | 11,62:1 sur blanc |
| `brand-navy-dark` | `#152847` | survol/actif du primaire, fin du dégradé de la barre latérale | 14,72:1 (blanc dessus) |
| `brand-gold` | `#B58B2A` | accent secondaire (avicole, volaille, terre) ; icône d'entrée active et pastille du menu ; KPI « à traiter » | **3,14:1 sur blanc (ÉCHEC pour du texte < 18,66 px gras)** ; 3,70:1 sur navy |
| `brand-gold-light` | `#D4A94D` | survol/surbrillance de l'or | 5,30:1 sur navy ; 6,72:1 sur navy-dark |
| `surface-bg` | `#F2F2F2` | fond général de l'application | — |
| `surface-card` | `#FFFFFF` | cartes, modales, tableaux | — |
| `surface-zebra` | `#F7F7F8` | lignes alternées, en-tête de tableau, survol de lignes de menu | — |
| `outline-variant` | `#D8DCE3` | bordures fines (1 px), séparateurs | — |
| `outline` | `#6B7280` | texte secondaire, icônes inactives, en-têtes de tableau, libellés de KPI | 4,83:1 sur blanc ; **4,32:1 sur `surface-bg` (sous 4,5)** ; 4,52:1 sur zebra |
| `on-surface` | `#1A1D23` | texte principal | 15,08:1 sur `surface-bg` |
| `error-deep` | `#B33A3A` | alertes, stock critique, suppression, bouton danger, cloche, toast d'erreur | 5,86:1 sur blanc ; 4,80:1 sur `error-container` |
| `error-container` | `#FBE3E3` | fond des badges/bannières d'erreur | — |
| `success-deep` | `#3A7D44` | confirmations, « OK », « Payée », toast de succès | 5,00:1 sur blanc ; **4,24:1 sur `success-container` (sous 4,5)** |
| `success-container` | `#E1F0E3` | fond des badges/bannières de succès | — |
| `info-blue` | `#2563EB` | information neutre (ex. Mobile Money), KPI d'effectif | 5,17:1 sur blanc |

Le blanc (`white`, `#FFFFFF`) et le noir à opacité (`bg-black/50` pour les voiles, `bg-black/40` pour le recouvrement du menu mobile, `white/90`, `white/50`, `white/10`) viennent de Tailwind et sont autorisés ; aucune autre couleur n'existe. **`surface-card` et `white` sont la même couleur** ; garder les deux noms comme au poste.

**Bordure sémantique gauche des KPI (4 px)** — `logialvia/docs/E7_Dashboards_KPI.md` §4 : information neutre = `info-blue` ; alerte/à traiter = `brand-gold` ; positif/confirmé = `success-deep` ; négatif/critique = `error-deep`.

**Mesures qui demandent une décision du client (jamais corrigées en silence)** — calculées par ce dossier, ratio WCAG 2.x :
- `brand-gold` sur blanc 3,14:1 : texte or sur fond clair illisible en petit (le même défaut que le « ERP » jaune d'LogiAgriERP, ticket 15.7, 1,41:1, a obligé à créer `brand-maize-ink`). Règle provisoire : **l'or n'est jamais une couleur de texte sur fond clair** (icône ≥ 24 px ou bordure seulement) ; texte or uniquement sur navy/navy-dark (`brand-gold-light` : 5,3:1).
- `outline` sur `surface-bg` 4,32:1 : texte secondaire en dessous de 4,5 sur le fond gris de page ; sur carte blanche 4,83:1. Règle provisoire : le texte `outline` se pose sur `surface-card`/zebra, pas sur le fond de page.
- `success-deep` sur `success-container` 4,24:1 : badge « Payée » juste sous le seuil.
Ces trois points sont à soumettre au client (section 13, Q-DS-2) ; un jeton « or lisible sur blanc » n'est PAS inventé ici.

**Correspondance de PORTAGE d'LogiAgriERP vers LogiALVIA : par RÔLE, jamais par remplacement de nom.** LogiAgriERP : `brand-forest` `#052e16`, `brand-forest-dark` `#00210D`, `brand-emerald` `#065F46`, `accent-yellow` `#FFD55F`, `error-red` `#DC2626`, `error-deep` `#BA1A1A`, `error-bg` `#FFDAD6`, `surface-bg` `#F8F9FA`, `surface-zebra` `#F3F4F5`, `outline-variant` `#BEC9C2`, `outline` `#6F7973`, `on-surface` `#191C1D` (14 couleurs, plus des alias dans `tailwind.config.js`).

| Rôle visuel | LogiAgriERP | LogiALVIA |
|---|---|---|
| Bouton primaire / lien actif / puce de marque | `brand-emerald` (survol `brand-forest`) | `brand-navy` (survol `brand-navy-dark`) |
| Dégradé de la barre latérale (180°) | `brand-forest` -> `brand-forest-dark` | `brand-navy` -> `brand-navy-dark` (`linear-gradient(180deg,#1F3864,#152847)`) |
| Accent (entrée active, hover d'icône du rail) | `accent-yellow` | `brand-gold` (texte : `brand-gold-light`) |
| Erreur / suppression | `error-red` (toast), `error-deep` (champ invalide) | `error-deep` pour les deux ; fond `error-container` |
| Succès | `brand-emerald` (toast, KPI) | `success-deep` (toast, KPI) ; fond `success-container` |
| Information | `info-blue` | `info-blue` |

Une recherche/remplacement mécanique `brand-emerald` -> `brand-navy` est INTERDITE : `brand-emerald` sert à la fois de primaire et de « succès » dans LogiAgriERP, deux rôles que LogiALVIA sépare.

---

## 3. Typographie

**Police** : Roboto, **variable**, servie en LOCAL (`logialvia/logialvia_app/assets/fonts/Roboto-Variable.ttf` côté poste ; le web convertit en `.woff2` par sous-ensembles `latin`/`latin-ext`, `@font-face` `font-weight: 100 900`, `font-display: swap`, preload de `latin`). Pile de repli : `Roboto, Calibri, ui-sans-serif, system-ui` (celle du prototype). JAMAIS de CDN. Graisses réellement employées : 400, 600 (`font-semibold`), 700, 800 ; **aucun 500 ni 300** (`logialvia/docs/01_DESIGN_SYSTEM.md` §2) : ne pas en ajouter. (LogiAgriERP, lui, sert Inter ; le client doit trancher si les deux produits ne se ressemblent plus : Q-DS-1.)

**Échelle en px réels** (racine 16 px ; `text-xs` surchargé) :

| Classe | Taille | Interligne | Usage dans LogiALVIA (sources) |
|---|---|---|---|
| `text-[9px]`–`text-[11px]` | 9–11 px | hérité (1,5) | badges, notes ; **message d'erreur de champ 11 px** (`.invalid-feedback`) |
| `text-[12px]` | 12 px | hérité | **en-têtes de tableau** (202 relevés sur 205), **libellés de champ** (capitales grasses, couleur navy, 147 emplois), **intitulés de KPI** (capitales grasses, couleur outline, 86 emplois), pied d'en-tête de menu |
| **`text-xs`** | **13,6 px** (`0.85rem !important`, `app.css`) | 16 px | **corps de tableau (`<td>`)**, boutons, champs de formulaire, texte le plus courant ; la classe la plus employée du prototype (1 381 emplois) |
| `text-sm` | 14 px | 20 px | texte de modale, champs, texte courant |
| `text-[15px]` | 15 px | — | **libellé d'entrée de la barre latérale au poste** (`shell/app_sidebar.dart`, 700 si active sinon 400) ; LogiAgriERP fixe 14 px à la demande du client (`components/sidebar-link.blade.php`) : valeur de LogiALVIA à confirmer sur son prototype (`sidebar.js`) |
| `text-base` | 16 px | 24 px | titres de section |
| `text-lg` | 18 px | 28 px | titre de modale ; titre de la marque dans la barre latérale (800) |
| `text-xl`/`text-2xl` | 20/24 px | — | titre de page ; **valeur de KPI : 24 px / 800** (`md:text-2xl`) |

**Pièges mesurés (déjà payés)** : (1) `text-xs` n'est PAS 12 px : la surcharge est globale (35 pages sur 41 chargent `common.css`) ; un portage l'avait appliquée à 3 écrans seulement et rendu tout le reste 12 % trop petit. (2) Les cellules de tableau (13,6) sont PLUS GRANDES que les en-têtes (12) : ne pas les égaliser. (3) `label` = 12 px sans `letter-spacing` (le prototype n'en demande nulle part ; `tracking-wider` seulement sur le sous-titre « ALLMANY ET COMPAGNIE », 12 px, `0.6` d'espacement, blanc à 50 %). (4) Trois pages du prototype (`cycle-couveuse`, `cloture-exercice`, `comptabilite-analytique`) n'ont aucune taille sur leurs cellules (16 px hérités) : écart du prototype, aligné sur 13,6 px ; garder ce choix (`ECART_DELIBERE`). (5) Champ de formulaire : hauteur `h-11` = **44 px** (`ChampSaisieNombre.hauteurStandard`), barres de filtres : `h-10` = 40 px, sur demande de la Gérante pour la saisie journalière.

---

## 4. Grille, marges, espacements

**Espacements nommés** (5 noms, valeurs EXACTES de `tailwind.config.js` de LogiALVIA ; source `logialvia/docs/01_DESIGN_SYSTEM.md` §3) :

| Nom | px | Exemple d'usage |
|---|---|---|
| `xs` | 4 | écart libellé/champ (`mb-xs`), espace icône/texte serré |
| `sm` | 8 | `gap-sm` entre contrôles, `py-sm` d'une cellule, padding d'un badge |
| `md` | 16 | marge de contenu mobile (`p-md`), padding de carte/KPI, `gap-md` des grilles |
| `lg` | 24 | marge de contenu bureau (`lg:p-lg`), marge horizontale de la barre du haut, padding de modale ≥ 640 px |
| `xl` | 32 | espacement de grandes sections |

LogiAgriERP ajoute `2xl: 48 px` ; LogiALVIA n'en a pas dans ses sources : ne pas le créer sans besoin prouvé. Les noms remplacent l'échelle numérique de Tailwind pour les espacements nommés (`p-md` = 16 px), tandis que l'échelle numérique (`px-3`, `py-1.5`) reste disponible mais NE DOIT PAS servir pour reproduire une mesure du poste (utiliser le nom).

**Grille de page** (mesurée sur le gabarit d'LogiAgriERP, à CONFIRMER pour LogiALVIA sur `sidebar.js`/`dashboard.html`) :
- Coque : `flex h-screen w-full overflow-hidden` ; barre latérale `w-72` = **288 px** (identique au poste LogiALVIA : `AppSidebar.largeur = 288`) ; zone principale `flex-1`.
- Barre du haut : `h-16` = **64 px**, `px-md lg:px-lg` (16 puis 24 px), fond blanc, bordure basse `outline-variant`, `sticky top-0 z-30`.
- Contenu : `p-md lg:p-lg` (16 puis 24 px), fond `surface-bg`, défilement vertical interne ; en dessous de `lg` : `pb-56` (224 px) pour dégager barre mobile et boutons flottants.
- Grilles : KPI `grid-cols-2 md:grid-cols-4 gap-md` (LogiAgriERP ; `xl:grid-cols-4` au prototype de LogiALVIA, `E7_Dashboards_KPI.md` §2 : à lire sur la page, c'est le défaut n° 1 de responsive du projet jumeau) ; blocs `grid-cols-1 lg:grid-cols-12 gap-md` ; cartes de hub `grid-cols-1 md:grid-cols-2/3 gap-md`.
- Largeur de contenu : pas de `max-w` global (le contenu occupe la zone). Une modale a son propre `max-w`.

---

## 5. Rayons, ombres, hiérarchie visuelle

**Rayons** : `rounded-lg` = **8 px** (cartes, modales, champs, boutons rectangulaires) ; `rounded-full` (pilule) pour badges et boutons d'action principale ; `rounded` = 4 px (cas rares). LogiALVIA n'a pas de `xl` (12 px) dans ses sources.

**Ombres** (Tailwind) : `shadow-sm` (cartes au repos, en-tête) `0 1px 2px 0 rgb(0 0 0 / 0.05)` ; `shadow-md` (cartes au survol) `0 4px 6px -1px rgb(0 0 0 / .1), 0 2px 4px -2px rgb(0 0 0 / .1)` ; `shadow-lg` (toasts, bouton flottant) ; `shadow-xl` (modales) `0 20px 25px -5px rgb(0 0 0 / .1), 0 8px 10px -6px rgb(0 0 0 / .1)`. Le web emploie les valeurs EXACTES de Tailwind. **Écart constaté** : `logialvia_app/lib/core/theme/app_shadows.dart` approxime `shadow-xl` (une seule ombre : flou 20, décalage 8, alpha 0,15, au lieu des deux couches de Tailwind) et `shadow-2xl` (`xxl`, carte de connexion seulement : flou 50, décalage 25, alpha 0,25) ; LogiAgriERP, lui, transpose les valeurs réelles (`agri_tokens.dart`, classe `AgriShadows`). À aligner (le web fait foi une fois validé) : ticket de parité visuelle, pas de correction silencieuse.

**Hiérarchie visuelle** (G2 §10, à garder sur les 31 écrans) : action principale = bouton plein `brand-navy` (texte blanc, survol `brand-navy-dark`), action secondaire = bouton à contour (`border outline-variant`, texte `outline`, survol `surface-zebra`), action destructive = plein `error-deep` (survol rouge plus sombre). La couleur primaire n'est JAMAIS utilisée pour une action secondaire ni l'inverse. Primaire à DROITE, secondaire à GAUCHE dans une modale ; l'action principale d'une section est en haut à droite (G2 §5). Titre d'écran 22–24 px/800 ; titre de section 16 px/700 ; libellés 12 px capitales ; données 13,6 px.

---

## 6. Responsive : 4 classes d'écran

**Faits réconciliés** (tous vérifiés dans les sources) :
- Tailwind par défaut : `sm` 640, `md` 768, `lg` 1024, `xl` 1280 (media queries `min-width`, donc sur la **fenêtre**, jamais sur un conteneur).
- Tableaux d'LogiAgriERP : `@media (max-width: 640px)` (`table.rtable`, `app.css`) -> **≤ 640 px inclus** : lignes empilées en cartes ; `kTableStackBreakpoint = 640` du poste (`agri_tokens.dart`) est défini mais **n'est utilisé par aucun fichier de `agrierp_flutter/lib`** (grep) : au poste l'empilement n'existe pas encore.
- Barre latérale : visible à partir de `lg` (1024) — `fixed lg:static`, `-translate-x-full lg:translate-x-0` ; barre mobile du bas `lg:hidden` ; bouton menu `lg:hidden`.
- KPI : accordéon replié jusqu'à 767 px, 4 colonnes et toujours visible à partir de `md` (768) (`.kpi-mobile-collapsed`).
- Fenêtre du poste : **LogiAgriERP** initiale 1280×720 (`agrierp_flutter/windows/runner/main.cpp`), **minimale 640×480** (`win32_window.cpp`, `kMinLogicalWidth/Height`) ; **LogiALVIA** initiale 1440×900, **minimale 1024×700** (`logialvia_app/lib/main.dart`). Le « 1280×720 » n'est donc le MINIMUM d'aucun des deux postes : c'est la taille de départ d'LogiAgriERP.
- Contenu réel : fenêtre − barre latérale (288) − marges (2 × 24) : à 1280 -> 944 px ; à 1024 -> 688 px.

**Les quatre classes** (décision de ce dossier, à valider : Q-DS-3) :

| Classe | Largeur de fenêtre | Repères réels | Tailwind |
|---|---|---|---|
| **Desktop** | ≥ 1280 px | taille de lancement du poste (1440×900 LogiALVIA, 1280×720 LogiAgriERP) ; contenu ≥ 944 px | `xl:` et au-delà |
| **Laptop** | 1024 – 1279 px | minimum du poste LogiALVIA (1024×700) ; barre latérale visible ; contenu 688–943 px | `lg:` sans `xl:` |
| **Tablet** | 641 – 1023 px | barre latérale en tiroir ; barre mobile du bas ; tableaux encore en colonnes ; KPI 4 colonnes dès 768 | `sm:`/`md:` sans `lg:` |
| **Mobile** | ≤ 640 px | tableaux en cartes ; KPI 2 colonnes en accordéon ; tiroir ; barre du bas | par défaut, sans préfixe |

Recouvrement d'un pixel connu : à **640 px exactement**, `sm:` s'applique ET les tableaux sont en cartes (max-width inclusif). Ne pas « corriger » : tester à 640 et 641 (voir section 12).

**Comportement de chaque composant par classe** (le poste ne reproduit que Desktop et Laptop tant que la fenêtre ≥ 1024 ; Tablet/Mobile sont des classes WEB sans équivalent poste, d'où l'obligation de les tester en navigateur) :

| Composant | Desktop ≥ 1280 | Laptop 1024–1279 | Tablet 641–1023 | Mobile ≤ 640 |
|---|---|---|---|---|
| Barre latérale (288 px) | statique, repliable par un bouton (état dans `localStorage`) | idem | tiroir `fixed` + recouvrement `bg-black/40` (z-40/z-50), ouvert par le bouton menu | idem Tablet |
| Barre du haut (64 px) | marge 24 ; fil d'Ariane visible `sm:` ; nom d'utilisateur visible `md:` | idem | marge 16 ; bouton menu ; nom masqué < 768 | marge 16 ; fil d'Ariane masqué (< 640) |
| Rail d'icônes droit (`w-16`) | visible (`lg:flex`) | visible | masqué | masqué |
| Barre du bas (64 px) | masquée | masquée | visible (`lg:hidden`) | visible |
| Contenu | `p-lg` | `p-lg` | `p-md`, `pb-56` | `p-md`, `pb-56` |
| Grille KPI | 4 colonnes, toujours visible (lg/xl: voir §4) | 4 colonnes | 4 colonnes dès 768 ; accordéon + 2 colonnes en dessous | accordéon replié par défaut, 2 colonnes |
| DataTable | colonnes + défilement horizontal interne si besoin | idem | colonnes (≥ 641) | cartes empilées, chaque `<td>` précédé de son `data-label` (10 px capitales `outline`) |
| Modale | `max-w-*` centrée, `p-lg` | idem | idem | `p-md`, quasi pleine largeur (`p-md` du voile), hauteur ≤ 85 dvh, défilement interne |
| Onglets (`tab-page`) | une ligne ; retour à la ligne (`flex-wrap`) si trop d'onglets | idem | idem | idem (jamais de défilement horizontal caché) |
| Formulaires | grille 2–3 colonnes | 2 colonnes | 1–2 colonnes | 1 colonne |
| Hub de cartes | 3 colonnes | 3 colonnes | 2 colonnes | 1 colonne |
| Toast | haut droite, `min-w-[260px]` | idem | idem | idem, largeur écran − 32 px |
| Cloche / Accès rapide | panneau `w-72`, `max-w-[85vw]` | idem | idem | idem |
| Impression | masque barre latérale, en-tête, barre du bas, `.no-print` | idem | idem | idem |

**Aucun défilement horizontal CACHÉ de la page** à aucune largeur (test Dusk de référence : `agrierp_laravel/tests/Browser/ResponsiveTest.php`, viewports bureau/tablette 768/mobile 375).

---

## 7. Composants (spécification)

Références : poste `logialvia_app/lib/core/widgets/` ; web modèles `agrierp_laravel/resources/views/components/`.

- **DataTable `<x-datatable>`** : carte blanche `rounded-lg border border-outline-variant shadow-sm overflow-hidden` ; zone de recherche en tête (`p-md`, bordure basse, champ pilule `bg-surface-zebra border rounded-full px-md py-xs max-w-xs`, icône `search` 16 px, `wire:model.live.debounce.300ms`) ; `<table class="rtable w-full text-left">` ; **en-tête `bg-surface-zebra`, `th px-md py-sm text-[12px] font-bold uppercase text-outline`** (12 px chez LogiALVIA ; LogiAgriERP : 10) ; corps `text-xs` 13,6 px, cellules `px-md py-sm`, lignes alternées zebra ; **chaque `<td>` a `data-label`** ; colonne Actions : boutons icône Modifier/Supprimer (`IconActionButton`) avec `title` + `aria-label` ; `wire:loading.class="opacity-50"` sur le corps ; état vide : message + bouton de création ; pied : « Affichage de X à Y sur Z entrées » + pagination (`E4_DataTables_Complet.md` §1). Une recherche unique : jamais ré-implémentée par écran.
- **Modale `<x-modal name="…">`** : voile `fixed inset-0 bg-black/50 z-[110] flex items-center justify-center p-md` ; panneau `bg-white rounded-lg shadow-xl w-full p-md sm:p-lg max-h-[85vh] max-h-[85dvh] overflow-y-auto` ; largeurs `max-w-sm` 384 / `md` 448 / `lg` 512 / `3xl` 768 / `5xl` 1024 px ; titre 18 px/700 navy + croix de fermeture à droite ; pied : `Annuler` (contour) à gauche, action principale (plein) à droite, séparateur au-dessus ; Échap et clic extérieur ferment ; ouverture par événement `open-modal` (jamais `@if`). `teleport` sous `<body>` si posée dans un conteneur empilé. **À confirmer** : `AppModal.maxWidth` du poste vaut 480 par défaut — pas une largeur Tailwind : relever le `max-w-*` réel de chaque modale du prototype.
- **Formulaires** : libellé 12 px/700 capitales navy, `*` si requis, `mb-xs` ; champ `h-11` (44 px), `rounded-lg`, bordure `outline-variant`, texte `text-xs`/`text-sm`, focus `ring-2` couleur primaire, fond blanc ; invalide : bordure `error-deep` + fond rouge très pâle + message 11 px `error-deep` sous le champ (`.is-invalid` / `.invalid-feedback`) ; aucun envoi silencieux d'un formulaire invalide ; calculs en direct à chaque frappe (G2 §6) ; champs numériques via un composant unique (`ChampSaisieNombre` au poste).
- **KPI `<x-kpi-card>`** : `bg-white rounded-lg border border-outline-variant shadow-sm`, `p-md`, **liseré gauche 4 px** de couleur sémantique ; libellé 12 px/700 capitales `outline` ; valeur `text-lg md:text-2xl font-extrabold` (24 px/800 en bureau) ; légende 11 px `outline` ; icône 18 px à droite ; **une carte est toujours présente** : valeur inconnue = « — » avec légende du motif, jamais `0` (Q-AFF-1). Hauteur uniforme sur tout le web ET le poste : LogiAgriERP a figé `min-height: 112px` (`.kpi-card`) à la demande de son client ; pour LogiALVIA aucune valeur n'est dans les sources : À DÉFINIR (Q-DS-4). Une seule implémentation (`CarteKpi` au poste est née en 13 copies dont 2 divergentes).
- **Accordéon KPI** : < 768 px replié, `max-height` 0 -> 900 px, `transition: max-height .3s ease, opacity .2s ease`, chevron qui tourne de 180° (`.2s`), `aria-expanded`.
- **Onglets `<x-tab-page>`** : barre `flex items-center gap-xs border-b border-outline-variant bg-white px-md py-xs flex-wrap` ; onglet `px-md py-2 text-xs font-bold border-b-2 rounded-t-lg` + icône 18 px ; actif = texte et bordure primaires, inactif = `outline` ; état dans `#[Url] public string $tab` ; `aria-selected` exposé.
- **Boutons** (`AppButton`) : hauteur 40 px (`h-10`) ; variantes `primary` (plein navy), `outline`, `danger` (plein `error-deep`) ; coins `rounded-lg`, ou pilule (`rounded-full`) pour les actions principales de page ; icône 18 px + 6 px d'écart ; `transition-all` au survol seulement.
- **Badge de statut** : pilule `rounded-full px-sm py-[2px] text-[11px] font-bold` ; tons `success` (`success-container`/`success-deep`), `error`, `info` (`info-blue` à 10 %), `neutre` (`outline-variant` à 30 %/`outline`).
- **Toasts** : conteneur `fixed top-4 right-4 z-[200] flex flex-col gap-sm pointer-events-none` (**haut droite** : au poste le bas droit est pris par l'Accès Rapide et la Visite guidée, et le web d'LogiAgriERP le fait déjà) ; carte `min-w-[260px] px-md py-sm rounded-lg shadow-lg border`, texte `text-sm font-semibold`, icône 20 px (`check_circle`, `error`, `warning`) ; 3 types (succès `success-deep`, erreur `error-deep`, avertissement `brand-gold` avec texte navy) ; disparition à **3 500 ms** ; entrée `toastIn` .3 s (glissé de 20 px) ; `@persist`.
- **Cloche** : icône `notifications` `outline`, pastille de compteur `error-deep`, panneau déroulant listant les dernières alertes, pied « Voir tout » (`wire:navigate`).
- **Barre du haut** : 64 px ; gauche : bouton menu (< lg), bouton replier la barre (lg), fil d'Ariane `text-xs outline` ; droite : sélecteur d'exercice si le module existe, cloche, menu utilisateur (icône `account_circle`, nom, `expand_more`, entrées « Mon profil », « Aide », « Paramètres » en `text-xs`, `px-md py-sm`, survol zebra).
- **Barre latérale** : 288 px, dégradé navy -> navy-dark, en-tête de marque (icône 26 px or, titre 18 px/800 blanc, sous-titre 12 px blanc 50 %), groupes d'entrées filtrés PAR RÔLE (menu masqué = cosmétique, jamais une autorisation), entrée `px-sm py-xs rounded-lg gap-sm`, icône 20 px, libellé 15 px au poste (14 chez LogiAgriERP : à confirmer), active : fond `white/10`, libellé blanc 700, icône or ; défilement interne fin (5 px, pouce `#284f33` chez LogiAgriERP : couleur de défilement de LogiALVIA À DÉFINIR) ; sous-menus : `max-height` 0 -> 600 px, `.3s ease` ; pied : nom et rôle.
- **Hub de cartes `<x-nav-card>`** : lien blanc `rounded-lg border border-outline-variant shadow-sm p-md flex items-center gap-md` ; **icône** dans un carré `w-12 h-12 rounded-lg bg-primaire/10` (icône 24 px primaire) ; **titre** `text-sm font-bold` primaire ; **description** `text-[11px] outline` ; **chevron** `chevron_right` `outline` à droite ; survol : bordure primaire, `shadow-md`, chevron qui glisse de 4 px (`group-hover:translate-x-1`) ; `transition-all`. À CONFIRMER : le dépôt LogiALVIA n'a pas d'équivalent « hub » identifié hors du Dashboard Élevage ; confronter au prototype avant de créer un hub.
- **Accès Rapide** : bouton rond 48 px (`w-12 h-12 rounded-full`) fixe, panneau latéral droit `w-72 max-w-[85vw]` (288 px, identique au poste), voile `bg-black/40` (z-[65]), panneau z-[70], glissement `transition-transform duration-300`.
- **Offcanvas de détail** (Historique des ventes, `OffcanvasPanel`) et **bandeaux** (exercice en lecture seule) : mêmes jetons, voile `bg-black/40`.
- **États** : chargement (`wire:loading`, `opacity-50`, boutons `disabled`), vide (message + action), erreur (toast), lecture seule (boutons de saisie grisés avec leur motif).

---

## 8. Animations et transitions AUTORISÉES (liste fermée)

| Où | Propriété | Durée / courbe |
|---|---|---|
| Sous-menu de la barre latérale | `max-height`, `opacity` | .3 s / .2 s `ease` |
| Chevron de menu | `transform` (rotate 90°) | .2 s `ease` |
| Accordéon KPI | `max-height`, `opacity` ; chevron 180° | .3 s / .2 s `ease` ; .2 s |
| Tiroir mobile, panneau Accès rapide | `transform` | `duration-300` |
| Toast | `toastIn` (opacité 0 -> 1, `translateX` 20 -> 0), sortie `opacity`/`transform` | .3 s `ease-out` ; disparition auto à 3 500 ms |
| Boutons, cartes de navigation, lignes de menu | couleurs, ombre, `translate-x-1` du chevron | `transition-colors` / `transition-all` (150 ms Tailwind par défaut) |
| Navigation de page | barre de progression de `wire:navigate` | couleur primaire (02, §4) |
| Chargement | `opacity-50` sur le corps de tableau | sans durée imposée |
Toute autre animation (rebond, parallaxe, fondu d'écran, skeleton animé non prévu) est INTERDITE tant qu'elle n'existe pas au poste : le poste est la référence. Respecter `prefers-reduced-motion` : réduire les durées à 0 pour tout ce qui précède, sauf la barre de progression.

## 9. Icônes

Material Symbols **Outlined** uniquement, jamais Rounded/Sharp ; noms IDENTIQUES entre web (`<span class="material-symbols-outlined">point_of_sale</span>`) et poste (`Symbols.point_of_sale`, package `material_symbols_icons`) ; réglages `FILL 0, wght 400, GRAD 0, opsz 24` ; taille par défaut 24 px, 20 px dans le menu et les toasts, 18 px dans les onglets et KPI, 16 px dans les champs de recherche. Police web LOCALE en sous-ensemble (voir 02, §7). Une icône ajoutée doit exister dans le sous-ensemble régénéré. Icônes de filière déjà définies : `pets` (Goliaths), `egg` (marque), `set_meal` (poissons) — liste réelle à lire dans `ConfigurationsEspeces` (champ `icone`), jamais devinée.

## 10. Accessibilité de base

- **Contrastes** : texte courant ≥ 4,5:1 (mesures et trois cas limites en §2) ; texte ≥ 24 px ou 18,66 px gras ≥ 3:1 ; icônes et bordures porteuses de sens ≥ 3:1. L'information ne repose jamais sur la couleur seule (badge : texte ET couleur).
- **Focus** : visible partout (`focus:ring-2` primaire) ; jamais `outline-none` sans équivalent ; ordre de tabulation = ordre visuel ; Échap ferme modale/panneau ; focus renvoyé au déclencheur.
- **Cibles tactiles** : ≥ 44×44 px sur Tablet/Mobile (champ `h-11` = 44 px ; barre du bas 64 px ; boutons icône avec zone cliquable de 44 px même si l'icône fait 18–20 px).
- **Sémantique** : `aria-label` + `title` sur tout bouton icône seule ; `role="dialog"` `aria-modal="true"` `aria-labelledby` sur les modales ; `aria-selected` sur les onglets ; `aria-expanded` sur accordéons et menus ; `<label for>` par champ ; erreurs liées au champ (`aria-describedby`) ; `lang="fr"`.
- **Texte** : redimensionnable à 200 % sans perte d'information ; aucune taille sous 9 px.
- Équivalent poste : `Semantics` sur modales, onglets et boutons icône (G2 §8).

---

## 11. Règle de CONFORMITÉ web ↔ poste : méthode de preuve

Principe : un défaut de conformité est **invisible à l'exécution** (l'écran s'affiche, mais n'est pas celui qui a été validé) ; on le rend visible en comparant des SOURCES et des CAPTURES.

1. **Jetons partagés** : un test lit `logialvia_web/tailwind.config.js` et `logialvia_app/lib/core/theme/{app_colors,app_spacing,app_radius,app_typography}.dart` et exige l'égalité valeur par valeur (15/15 couleurs, 5/5 espacements, rayons, tailles). Modèle : `agrierp_flutter/outils/audit_jetons.py` (il écrit `agrierp_flutter/RAPPORT_JETONS.md`, qui conclut « 14 / 14 couleurs identiques ») et `logialvia/logialvia_app/test/core/echelle_typographique_test.dart`.
2. **Gardes qui lisent les sources** (jamais le rendu) : (a) aucune couleur hexadécimale ni taille en dur hors jetons ; (b) `text-xs` n'est pas redéfini à 12 px ; (c) pas de `constraints`/largeur de conteneur pour choisir une mise en page (équivalent web : pas de `container queries` non listées) ; (d) une seule implémentation de la carte KPI, de la modale, du datatable ; (e) chaque `<td>` a `data-label` ; (f) aucune classe Tailwind dynamique. Modèles : `agrierp_flutter/test/conformite_portage_test.dart`, `agrierp_laravel/tests/Feature/CartesKpiUniformesTest.php`, `ContrasteMarqueTest.php`.
3. **Tests de libellés `fidelite_libelles`** : chaque libellé du prototype existe dans une CHAÎNE littérale de la vue (pas dans un commentaire : `chainesDe` ; un garde qui validait des commentaires passait sur des « explications d'absence »). Deux listes d'exemption : globale (mots vraiment partout) et par page. Modèle : `agrierp_flutter/test/fidelite_libelles_test.dart`.
4. **Tests `conformite_structure`** : séquence ORDONNÉE des `<th>` de chaque table et nombre de cartes KPI par page ET par panneau d'onglet, contre des fixtures extraites du prototype. Un en-tête à deux niveaux (`colspan`/`rowspan`) se compte en colonnes feuilles. Modèles : `agrierp_flutter/test/conformite_structure_test.dart`, `agrierp_flutter/outils/structure.py`. Les écarts assumés vont dans une carte `ecartsAssumes` avec leur raison ; un écart non corrigé dans `ecartsATraiter`, et un test interdit qu'une page soit dans les deux.
5. **Captures de référence** : pour chaque écran, captures du prototype ET du web (Dusk `screenshot`) à 1440, 1280, 1024, 768 et 390 px, comparées côte à côte ; les captures de référence sont versionnées dans `tests/Browser/screenshots/` (dossier existant chez LogiAgriERP). Tolérance : 0 différence de couleur ou de position perceptible, au pixel d'anti-aliasing près (K2). Modèle d'outillage : `agrierp_flutter/outils/captures.py`, `audit_chrome.py`, `emplacement.py`.
6. **Mesure typographique outillée** : un script relève la taille effective des `th`, `td`, libellés (`audit_typographie.py` et `apparier_typographie.py`, cités par `logialvia/docs/K2_Checklist_Recette_Visuelle.md` et `01_DESIGN_SYSTEM.md` mais ABSENTS de `logialvia/logialvia_app/outils/` du dépôt cloné : à récupérer ou à réécrire ; ils ne comptent que les tailles posées explicitement et refusent de résoudre l'héritage au-delà d'un niveau) ; les 376 cellules non résolues se lisent à la main.
7. **Responsive prouvé** : test Dusk à 1440/1280/1024/768/390, aucun défilement horizontal caché (`agrierp_laravel/tests/Browser/ResponsiveTest.php`).
8. **Accessibilité** : test de contraste (modèle `ContrasteMarqueTest.php`), balisage `aria-*` des composants.
9. **Une divergence** se classe : *défaut* (à corriger), *écart assumé* (`ECART_DELIBERE:` + raison + entrée dans la carte des écarts) ou *question client*. Jamais « petit détail ».

## 12. Check-list de recette visuelle, écran par écran (dérivée de `logialvia/docs/K2_Checklist_Recette_Visuelle.md`)

À cocher pour CHAQUE écran avant « Recetté » ; un écran non recetté n'est jamais présenté comme terminé.

Structure
- [ ] Même structure de page et même ordre des sections que le prototype ; aucune section réordonnée.
- [ ] Nombre et ordre des colonnes de chaque table (compter, ne jamais estimer) ; `data-label` sur chaque cellule.
- [ ] Nombre de cartes KPI par page et par panneau ; liseré gauche de la bonne couleur sémantique ; « — » si non calculable.
- [ ] Onglets : nombre, clés, libellés, icônes identiques ; état dans l'URL.
- [ ] Espacements = noms `xs/sm/md/lg/xl` uniquement ; conteneurs = `rounded-lg`/`shadow-*` des jetons ; hiérarchie typographique des jetons (12 px / 13,6 px / 14 px / 24 px).
- [ ] Position des boutons : primaire à droite, secondaire à gauche (modale) ; CTA principal en haut à droite de la section ; icônes Material Symbols de mêmes noms.
- [ ] Modales : une par action, largeur `max-w-*` du prototype, titre, croix, pied conforme ; suppression toujours par modale d'avertissement.
- [ ] Animations : seulement celles de la section 8.
- [ ] Bouton Imprimer/PDF présent où le prototype le prévoit.
Comportement
- [ ] Aucun bouton décoratif (succès affiché = écriture réelle) ; chaque action donne un toast de succès ou d'erreur.
- [ ] Validation sous le champ, aucun envoi silencieux ; calculs en direct à la frappe.
- [ ] États vide / chargement / erreur / lecture seule informatifs.
- [ ] Droits : écran inaccessible ou limité pour au moins 2 rôles testés (admin, caissier, animalier).
Responsive (tester à 1440, 1280, 1024, 768, 641, 640, 390)
- [ ] Desktop/Laptop : barre latérale 288 px, KPI en 4 colonnes, contenu sans coupure.
- [ ] Tablet : tiroir + barre du bas, tableaux en colonnes à 641 px, KPI 4 colonnes dès 768.
- [ ] Mobile : tableaux en cartes à 640 px avec libellés, KPI en accordéon, modale lisible, aucun défilement horizontal de la page.
Technique et accessibilité
- [ ] Tests de libellés/structure à jour ; garde-fous verts ; aucune couleur en dur ; `text-xs` = 13,6 px.
- [ ] Contrastes mesurés ; focus visible ; cibles ≥ 44 px (tactile) ; `aria-*` sur modales/onglets/boutons icône.
Confrontation directe
- [ ] Captures web et prototype côte à côte aux 5 largeurs : 0 différence de couleur ou de position perceptible.
- [ ] Écarts classés (défaut / écart assumé / question) ; signature : date, auteur, version de l'écran.

---

## PROMPT B (à copier) — Audit de conformité de design (à lancer sur UN écran)

````markdown
# RÔLE
Tu es auditeur de conformité de design du web LogiALVIA. Tu ne modifies RIEN : tu mesures, compares et rapportes. Tout est en français.
Lis `04_UI_UX_DESIGN_SYSTEM.md` en entier, puis `01_MASTER_PROMPT.md` (règle : rien d'inventé).

# ENTRÉES
- Écran à auditer : <NOM, ex. « Fiche Goliaths »> ; route web : <URL> ; composant : <app/Livewire/…> ; vue : <resources/views/…>.
- Référence : fichier du prototype <ex. fiche-goliaths.html> (à demander s'il n'est pas dans le dépôt : NE PAS le reconstruire) ET écran du poste
  <logialvia_app/lib/…/…_screen.dart> ; données de l'écran dans le web (jeu de démonstration réaliste, jamais de données inventées présentées comme réelles).

# TÂCHES (dans l'ordre)
1. Lis la source de référence en entier (HTML du prototype, écran Dart) ET la vue Blade + le composant Livewire. Note les chemins et lignes.
2. STRUCTURE : liste ordonnée des sections, onglets, KPI (nombre, couleur de liseré), tables (colonnes feuilles dans l'ordre), boutons (position, variante),
   modales (nom, largeur, pied). Compare au prototype ET au poste : tableau « élément · prototype · poste · web · verdict ».
3. JETONS : relève toute couleur, taille, espacement, rayon, ombre ÉCRITS EN DUR dans la vue ; vérifie `text-xs` = 13,6 px, en-têtes de table 12 px, libellés 12 px,
   champs `h-11`, KPI 24 px/800 ; vérifie les 15 couleurs de `tailwind.config.js` contre `app_colors.dart`.
4. COMPOSANTS : l'écran utilise-t-il `x-datatable`, `x-modal`, `x-kpi-card`, `x-tab-page`, `x-nav-card` partagés (aucune copie locale) ? Chaque `<td>` a-t-il `data-label` ?
   Modales événementielles (aucun `@if`) ? Classes Tailwind statiques ?
5. RESPONSIVE : ouvre l'écran (Dusk ou navigateur réel) à 1440, 1280, 1024, 768, 641, 640 et 390 px ; capture chaque largeur ; vérifie comportement par classe (section 6),
   absence de défilement horizontal de la page, tableaux en cartes ≤ 640, KPI en accordéon < 768, barre latérale/tiroir à 1024.
6. COMPORTEMENT : chaque bouton écrit-il réellement ? toast de succès/erreur ? suppression par modale ? validation sous le champ ? états vide/chargement/erreur/lecture seule ?
   droits testés pour 2 rôles.
7. ANIMATIONS : seules celles de la section 8 ? `prefers-reduced-motion` respecté ?
8. ACCESSIBILITÉ : contrastes mesurés (formule WCAG), focus visible, cibles ≥ 44 px en tactile, `aria-*`/`title` sur boutons icône, modales, onglets.
9. PREUVE : indique quels gardes-fous (jetons, `fidelite_libelles`, `conformite_structure`, cartes KPI) couvrent l'écran et lesquels manquent ; exécute-les et colle leur résultat réel.

# CONTRAINTES
- Aucune modification de code. Aucune valeur inventée : une mesure impossible = « non mesurée, raison ».
- Une divergence = défaut, écart assumé (avec raison citée) ou question client ; jamais « détail ».
- Les couleurs/tailles d'LogiAgriERP ne sont pas une référence pour LogiALVIA.

# SORTIE ATTENDUE (format imposé)
1. En-tête : écran, version du code (hash ou date), largeurs testées, sources lues (chemins).
2. Tableau de conformité par section (Structure / Jetons / Composants / Responsive / Comportement / Animations / Accessibilité) : verdict CONFORME / ÉCART ASSUMÉ / DÉFAUT / NON MESURÉ.
3. Liste des DÉFAUTS : numéro, fichier:ligne, valeur observée, valeur attendue (source citée), gravité (bloquant / majeur / mineur), correctif proposé.
4. Captures : chemins des fichiers (web et référence) par largeur.
5. Résultat des gardes-fous exécutés.
6. Questions à poser au client (numérotées, précises).
7. Verdict final : « Recetté » uniquement si zéro défaut bloquant ou majeur et toutes les cases de la section 12 cochées ; sinon « Non recetté » avec la liste de ce qui manque.

# CRITÈRES D'ACCEPTATION DE L'AUDIT
- Chaque verdict cite une source (fichier:ligne) ; chaque mesure indique sa méthode.
- Les 7 largeurs ont été testées ou la raison est écrite.
- Aucune phrase du type « semble conforme » : seulement des constats mesurés.

# INTERDITS
Corriger le code ; juger « à l'œil » sans mesure ; fermer un défaut sans preuve ; se fonder sur `Livewire::test()` pour une conclusion sur le rendu navigateur.
````

---

## 13. À DÉFINIR AVEC LE CLIENT (la section 14, après, fixe les règles des captures)

- **Q-DS-1 Police** : Roboto (celle du poste, retenue ici pour la conformité) ou Inter (LogiAgriERP) ? Changer implique de changer le poste aussi.
- **Q-DS-2 Contrastes** : accepte-t-il (a) un jeton « or lisible sur fond clair » dérivé de `#B58B2A` (valeur à fixer ensemble ; elle n'est PAS inventée ici), (b) de réserver `outline` aux fonds blancs, (c) un texte `success-deep` plus sombre sur `success-container` ?
- **Q-DS-3 Classes d'écran** : valide-t-il Desktop ≥ 1280, Laptop 1024–1279, Tablet 641–1023, Mobile ≤ 640 ? Le web doit-il être pleinement utilisable en Tablet/Mobile (caisse sur tablette ?) alors que le poste ne l'est pas (fenêtre minimale 1024×700) ?
- **Q-DS-4 Hauteur des cartes KPI** : LogiAgriERP a figé 112 px à la demande de son client ; LogiALVIA le veut-il (valeur à fixer, web ET poste) ?
- **Q-DS-5 Barre latérale** : libellé d'entrée 15 px (poste LogiALVIA) ou 14 px (LogiAgriERP, à la demande du client le 07/11/2026) ? Couleur de la barre de défilement ?
- **Q-DS-6 Ombres** : aligner `app_shadows.dart` (`xl` et `xxl` sont des approximations à une couche) sur les valeurs exactes de Tailwind utilisées par le web ?
- **Q-DS-7 Modales** : largeur de chaque modale (le poste utilise 480 par défaut, valeur hors échelle Tailwind) : à relever sur le prototype.
- **Q-DS-8 Mode sombre, rail d'icônes droit, hubs de cartes** : existent-ils dans le prototype de LogiALVIA ? (sources du dépôt cloné muettes ; ne pas les créer par imitation d'LogiAgriERP.)
- **Prototype HTML** : fournir sa copie (31 pages) : sans elle, la source visuelle de premier niveau manque et plusieurs valeurs ci-dessus restent « à confirmer ».

## 14. Captures d'écran (manuel, README, aperçu social, spécimens) : règles de confidentialité et de fidélité

Règles tirées de ce qui a été fait dans LogiAgriERP (commits du 09/11/2026, décisions DV-25 et DV-30 de `16_DECISIONS_VALIDEES.md`) ; à appliquer telles quelles pour LogiALVIA. Le renommage lui-même est décrit par `49_CHECKLIST_RENOMMAGE_PRODUIT.md`.

1. **Aucune donnée personnelle** dans une image publiée (manuel, README, aperçu social, site) : le NOM et l'adresse E-MAIL de l'administrateur sont **floutés** — barre haute, barre latérale, accueil, profil, gestion des utilisateurs, journal d'audit. Aucun numéro de téléphone, IFU réel ni jeton ne figure sur une capture : les spécimens de `presentation/` sont FICTIFS (IFU `9999999999999`, `8888888888888`, filigrane « SPÉCIMEN », QR à ne pas scanner).
2. **Copie non floutée gardée en dépôt PRIVÉ** (`manuel/originaux_non_floutes/`, avec son `LISEZMOI.md` : « Ne jamais publier ce dossier ») pour régénérer le manuel en usage interne. Elle est tenue à jour comme les images floutées (nom du produit, domaine).
3. **Nom du produit et domaine À JOUR** sur chaque image : `LogiAgriERP` (jamais l'ancien `AgriERP`), adresses en `fermeolouwachegoun.com`. Après tout renommage, TOUTES les captures sont revues, pas seulement les textes du code.
4. **« ERP » en jaune `#FFD55F`** (couleur `accent-yellow`) : « LogiAgri » en blanc sur le vert, « ERP » en jaune de la marque ; le **tracteur** de la barre latérale et de la connexion est FIXE. Ce jaune est un usage de MARQUE sur fond foncé (sur fond blanc il est illisible : voir § 2, `brand-maize-ink`).
5. **Retouche d'une capture existante, sans refaire la prise de vue** (méthode employée ; AUCUN script n'est versionné dans le dépôt : elle est à refaire avec l'outil du moment) : (a) **lire le texte** de la zone à changer (reconnaissance de caractères) pour retrouver son emplacement, sa taille et sa couleur ; (b) effacer la zone par un aplat de la couleur de fond relevée sur l'image ; (c) **re-rendre le nouveau texte avec la MÊME police — Inter** (la police du web et du poste de LogiAgriERP : `agrierp_laravel/public/assets/fonts/Inter-latin.woff2`, `tailwind.config.js` `sans: ['Inter', 'sans-serif']`), même corps, même graisse, même couleur, même alignement ; (d) refaire le flou des zones personnelles APRÈS la retouche. Une police voisine ou un corps décalé se voit : comparer côte à côte à l'original.
6. **Contrôle automatique après retouche** : relire par reconnaissance de caractères TOUTES les images (`manuel/img`, `manuel/jpg`, `docs/images/`, `presentation/apercus`) et chercher l'ancien nom, l'ancien domaine, le nom et l'e-mail de l'administrateur ; zéro occurrence. (Contrôle à refaire à la main si l'outil manque : aucune garantie sinon.)
7. **Dimensions** : l'image d'aperçu social du dépôt fait 1280 × 640 (`docs/images/social-preview.png`) ; les captures du README sont dans `docs/images/` ; celles du manuel en PNG (`manuel/img`) et JPG (`manuel/jpg`), pilotées par `manuel/ecrans.json` et `manuel/reperes.json`, assemblées par `manuel/build.py`.
8. **Pour LogiALVIA** : charte marine `#1F3864` / or `#B58B2A` et police Roboto (§ 2 et § 3), pas le vert / jaune ni Inter d'LogiAgriERP ; le nom du produit se décide avec le client (DV-25). Ne jamais recopier une capture d'LogiAgriERP dans un document de LogiALVIA.
