# DOCTRINE DE PORTAGE FIDÈLE (Laravel → Flutter)

**Projet AgriERP — Ferme École OLOUWACHEGOUN (Ikpinlè, Adja-Ouèrè, Bénin)**

Objectif : une fidélité de **100 %** entre l'application web (`agrierp_laravel/`) et le poste Windows hors ligne (`agrierp_flutter/`). Ce document s'applique à **tout** ticket qui touche un écran, un calcul ou une donnée synchronisée. Il complète les `CLAUDE.md` des deux projets, il ne les remplace pas.

> ⚠️ Chaque règle ci-dessous indique son **état réel** dans le code au 17/10/2026. Une règle annoncée mais pas encore appliquée est marquée **CIBLE**. Ne jamais présenter une cible comme acquise.

---

## Article 0 — La vue web est la référence absolue

- **La règle d'or.** Le code Flutter est une **traduction, pas une réinterprétation**. Si un écran existe en version web, le poste reprend exactement sa structure, ses libellés, ses boutons, l'ordre de ses sections et de ses colonnes, et son ergonomie.
- **Hiérarchie des sources, du plus fort au plus faible :**
  1. **La vue Blade / le composant Livewire** pour tout ce qui est visible et pour le comportement. La vue Blade est elle-même une conversion du prototype HTML. Ses écarts au prototype y sont documentés et le poste en **hérite**, il ne les « corrige » pas de son côté.
  2. **Les Actions et Services Laravel** pour les règles métier et les calculs. Chaque règle y a été obtenue contre un défaut réel ; la redériver côté poste réintroduit ce défaut.
  3. **Le prototype HTML et la base documentaire** pour ce que les deux premiers ne montrent pas.

  Si une règle ne figure dans aucune des trois sources, le dire explicitement au lieu de l'inventer.

  ⚠️ **Changement à acter.** Les `CLAUDE.md` des deux projets placent encore le **prototype HTML** en tête pour le visuel. Cette doctrine place la **vue Blade** en tête. Tant que les deux ne sont pas alignés, une divergence Blade ↔ prototype est **signalée au client**, jamais tranchée en silence.
- **Aucune valeur en dur.** Couleurs, tailles, espacements et largeurs viennent du design system centralisé `lib/core/theme/` (`agri_tokens.dart`, `agri_theme.dart`). Ce design system est transposé un pour un de `tailwind.config.js` et mesuré sur l'application web. *État : appliqué. `test/conformite_portage_test.dart` interdit par exemple `fontSize: 12` au lieu de `AgriTypography.xs`.*
- **Documentation des écarts.** Tout écart imposé par la plateforme (bureau ou web) est documenté **dans le widget concerné**, avec un commentaire `⚠️ ÉCART` qui donne la raison. L'écart est aussi enregistré dans `test/cartes_attendues.dart` (`ecartsAssumes` ou `ecartsATraiter`, jamais les deux).

---

## 1. Architecture technique et offline-first (modèle Tatacora)

Contexte : la connexion Internet est instable en zone rurale (Adja-Ouèrè / Ikpinlè). **Le mode hors ligne est le mode de fonctionnement normal, pas une erreur.**

1. **Base locale Drift / SQLite.** Toutes les lectures se font **exclusivement** depuis la base locale. Le poste fonctionne en « zéro réseau » par défaut ; le réseau ne sert qu'à synchroniser. *État : appliqué (schéma Drift v38).*
2. **UUID côté client.** Chaque identifiant (vente, animal, client, fiche) naît **sur le poste**, au moment de la création, et n'est jamais régénéré par le serveur. C'est ce qui rend la synchronisation idempotente : un envoi répété ne crée pas de doublon. Les clés primaires ne sont **jamais** des entiers auto-incrémentés. *État : appliqué des deux côtés.*
3. **Séparation des couches.** Un repository n'expose **jamais** un modèle Drift à la présentation : il expose une entité de domaine pure. Toute l'arithmétique métier vit dans le repository (ou dans un service partagé), jamais dans un widget. *État : **CIBLE partielle**. La règle « un écran = un `_screen.dart` + un `_repository.dart` » est appliquée ; plusieurs repositories renvoient encore des lignes Drift (`LivestockDailyEntry`, `Product`…). À migrer écran par écran, sans réécriture globale.*
4. **Moteur comptable local.** Tout mouvement d'argent (vente, achat, dépense, paie, avoir, avance) produit sa pièce comptable SYSCOHADA **dans la même transaction locale**, ou est envoyé comme **fait** (`pending`) que le serveur rejoue dans son unique point de passage (`AccountingEntryService::record()`). Une pièce ne doit jamais être calculée deux fois de deux façons. *État : modèle « fait + rejeu serveur » depuis F0.55 pour clients, avances, retours et avoirs fournisseurs.*
5. **Cascade unique des effectifs.** Toute écriture sur une fiche journalière passe par la cascade unique : `RecordSaleOnFicheElevageAction::recalculerEnCascade()` côté web, `FicheJournaliereRepository.recalculerEnCascade()` côté poste. La bande prend l'effectif de la **dernière** fiche, jamais celui du jour édité. *État : appliqué sur les cinq fiches web, sur `EnregistrerSujets` et dans le repository du poste depuis le correctif « Effectif Total Vivant » (17/10/2026).*
6. **Règles de synchronisation différenciées.** Pas de « dernier écrivain gagne » global : référentiels = le serveur gagne ; fiches = dernier écrivain gagne ; ventes = jamais fusionnées ; mouvements de stock = rejoués ; clôture d'exercice = jamais synchronisée. Un refus du serveur devient un `conflict` visible à l'écran **Synchronisation**, jamais un retour silencieux en `pending`.

---

## 2. Design system et respect visuel

- **Composants uniques.** Une seule implémentation par composant partagé : `CarteKpi`, `ModaleAgri` / `ModaleConfirmation` (ouvertes par `afficherModale`), `TableauMensuel`, `BarreSuperieure`. Ne jamais créer de variante locale.
- **Boutons d'action uniformes** (`+ Enregistrer`, `Exporter`, `Filtrer`…) : même hauteur, même padding, mêmes coins arrondis dans tous les modules, via un composant `BaseButton` unique. *État : **CIBLE**. `BaseButton` n'existe pas encore ; les boutons sont stylés écran par écran à partir des jetons. Ticket dédié au plan de finalisation.*
- **Tableaux et listes.** Les en-têtes de tableau reprennent la charte de la **vue web** de référence, avec une pagination standardisée (10 ou 25 lignes par page). Le point de rupture responsive est **640 px exactement** ; en dessous, chaque cellule porte son propre libellé (`data-label`).

  ⚠️ **À ARBITRER.** La consigne initiale demandait des en-têtes « fond sombre `#0f172a`, texte blanc ». Ni l'application web ni le prototype n'utilisent cette couleur : les en-têtes web sont clairs (`text-outline`, bordure basse `border-outline-variant`). Appliquer `#0f172a` sur le poste violerait l'article 0. Si un en-tête sombre est voulu, il doit d'abord être décidé et appliqué **sur le web**, puis porté.

  ⚠️ Ticket EX7 (20/10/2026) : le composant partagé existe des deux côtés — `<x-pagination>` au web, `PaginationAgri` au poste (25 lignes, « 27 lignes dans l'exercice 2026 — page 1 sur 2 », Précédent / Suivant, libellés vérifiés par `selecteur_exercice_test.dart`). Il est appliqué aux listes de l'EF9 (Journal, ventes, factures, achats, dépenses, mouvements de stock, soins, infirmerie, transferts) ; les autres listes restent à paginer (**CIBLE**).
- **Modales unifiées.** Même design, même voile (`bg-black/50`), même ✕ et même pied de modale partout. Jamais de dialogue natif du système (`alert()`, `confirm()`, `AlertDialog` brut, `showDialog` sans `afficherModale`). *État : appliqué et verrouillé par `conformite_portage_test.dart`.*
- **Donnée inconnue = `'—'`, jamais `0`.** Un zéro se lit comme une mesure ; un tiret dit « ce poste ne sait pas ».

---

## 3. Qualité et garde-fous

- **Test de mutation.** Chaque test unitaire ou de widget critique doit être éprouvé : si l'on retire la logique métier du code, le test doit passer **au rouge**. Un test qui reste vert sans la règle ne protège rien. Les valeurs attendues sont des **littéraux calculés à la main**, jamais produits par le code testé.
- **Parité exécutée.** Pour un calcul porté (effectifs, comptabilité, paie), le test compare le résultat Dart au résultat PHP réel (`test/php_laravel.dart`) quand c'est possible.
- **Conformité lue dans le code source.** `conformite_portage_test.dart`, `fidelite_libelles_test.dart` et `conformite_structure_test.dart` lisent le code et les fixtures du prototype. Les écarts qu'ils verrouillent sont **invisibles à l'exécution**. Ne jamais les affaiblir pour faire passer un écran.
- **Zéro chaîne en dur.** Tous les textes affichés passent par un système de localisation, avec parité entre `lang/fr/` (Laravel) et les fichiers l10n du poste.

  ⚠️ **CIBLE, non appliquée aujourd'hui des deux côtés.** `agrierp_laravel/lang/` n'existe pas : les libellés sont écrits en français directement dans les vues Blade. Le poste n'a pas de fichiers l10n (`intl` est présent, sans ARB). Les tests de fidélité comparent donc des **littéraux** des deux côtés. Passer à la localisation est un chantier transverse planifié (`PLAN_FINALISATION.md`, sprint F). Il doit migrer le web et le poste **ensemble**, sinon la parité se perd.
- **Définition de « terminé ».**
  - **Côté poste :** `flutter analyze` sans erreur et `flutter test` vert.
  - **Côté web :** `php artisan test --testsuite=Feature` vert.
  - **Dans les deux cas :** le ticket est consigné, avec ce qui n'a **pas** été vérifié.

---

## 4. Rythme de travail

1. **Un ticket = une session.** Annoncer le plan avant d'écrire du code.
2. **Ordre par écran :**
   - **Web :** migration → modèle → Action/Service → composant Livewire → vue Blade.
   - **Poste :** table Drift → repository → écran → tests.
3. Lire la vue Blade et le composant Livewire **en entier** avant de porter un écran ; ne jamais reconstruire de mémoire.
4. Écrire le test qui aurait attrapé le défaut **avant** de le corriger.
5. Ne jamais convertir des écrans en lot sans vérification intermédiaire.

---

## 5. Directive de fidélité absolue (adoptée le 17/10/2026)

Objectif : **parité de 100 %** entre la vue Blade (maître) et l'écran Flutter : ergonomie, fonctionnalité, logique métier. Cette directive **précise** les articles 0 à 3 ; elle ne change pas l'architecture (couches, cascade unique, synchronisation différenciée, points de passage uniques du serveur). Quand un critère n'existe pas encore **sur le web**, il est d'abord construit sur le web, puis porté : le poste n'invente jamais un comportement que la vue Blade n'a pas (article 0).

### 5.1 Structure et agencement

| Critère | Exigence | État au 17/10/2026 |
| --- | --- | --- |
| Architecture de page | Même ordre des sections, même tableau de bord, même barre latérale, même barre supérieure | Appliqué : `_BarreLaterale.arborescence` reprend `sidebar.js` groupe par groupe ; ordre des sections vérifié par `conformite_structure_test.dart` |
| Barre supérieure | Logo, recherche globale, sélecteurs, indicateur de caisse, cloche avec panneau interactif, menu de profil (avatar à initiales, rôle, menu déroulant aux mêmes entrées) | Partiel : recherche (`recherche-globale`), indicateur Sync, cloche à panneau présents dans `BarreSuperieure` ; parité des entrées du menu de profil **à auditer** écran par écran |
| Barre latérale | Groupes, séparateurs, icônes conformes, filtrage RBAC dynamique | Appliqué : `PermissionsPoste` = `RBAC_PAGE_MAP` verbatim, masquage + `GardeEcran` |
| Géométrie | Mêmes marges, `gap-*`, positions des logos et titres ; échelle typographique effective (Inter, `xs` = 13,6 px) | Appliqué via `agri_tokens.dart`, verrouillé par `conformite_portage_test.dart` |

### 5.2 Composants et formulaires

| Critère | Exigence | État |
| --- | --- | --- |
| Cartes et grilles | Même disposition des KPI, grilles et résumés | Appliqué : `CarteKpi` unique, nombre de cartes vérifié par `cartes_attendues.dart` |
| Champs et modales | Même placement des champs, listes, formulaires et modales | Appliqué : `ModaleAgri` / `afficherModale` |
| Listes avec recherche | Liste déroulante avec barre de recherche intégrée pour les listes longues (articles, clients) | **CIBLE COMMUNE** : aucune des deux surfaces ne l'a (pas de composant web). À construire d'abord en composant Blade partagé, puis en un widget Flutter unique |
| Recherche, filtres, tris | Au même endroit que dans la vue Blade | Appliqué écran par écran (`x-datatable` porte la recherche côté web) |
| Tableaux | Mêmes colonnes, en-têtes, cellules d'actions (voir, modifier, archiver), pagination 10/25 | Colonnes et en-têtes : appliqué (`conformite_structure_test.dart`). Pagination : composant commun depuis EX7 (`x-pagination` / `PaginationAgri`), appliqué aux listes de l'exercice ; **CIBLE** pour les autres (voir § 2) |

### 5.3 Interactivité et retours

| Critère | Exigence | État |
| --- | --- | --- |
| Onglets | Actif sur fond sombre, inactif sur fond clair, comme la vue web | À aligner sur les classes réelles de `tab-page.blade.php` ; le web n'a pas de helper `Onglets::classes()` : s'il est voulu, il naît côté web |
| Modales | Largeurs adaptées, ✕ ou bouton dédié, jamais de dialogue natif | Appliqué et verrouillé |
| Toasts | Mêmes moments, mêmes couleurs : vert succès, rouge erreur, ambre avertissement | Appliqué côté web (`toast-container.blade.php`) ; poste : `SnackBar` aux couleurs des jetons, moments **à auditer** |
| États vides | Même icône, même texte exact que la vue | Appliqué là où `fidelite_libelles_test.dart` couvre la page ; à étendre |

### 5.4 Logique métier et intégrité

1. **Zéro invention de calcul.** Toute formule portée (reste dû, TVA, CUMP, amortissement, effectifs) produit **exactement** le résultat du Service Laravel, prouvé par un test croisé PHP ↔ Dart (`test/php_laravel.dart`, parité exécutée). *État : appliqué pour les effectifs par catégorie, la nature des comptes, le glossaire lapins (7 452 libellés, 0 écart) ; à étendre à chaque formule portée.*
2. **Parité des refus.** Un refus du serveur (exception, 422, 409) est affiché avec **le message exact du domaine** (`MotifsRefusPush`, `message` de la réponse), jamais un message générique. *État : appliqué pour les conflits de synchronisation et `EchecSynchronisation` ; un refus local (ex. D3) reprend le libellé du serveur.*
3. **Hors ligne d'abord, transaction unique.** Toute écriture (vente, dépense, mouvement) est enregistrée dans Drift **dans une seule transaction** ; la file `pending` envoie les **pièces sources brutes** ; le serveur reste seul maître de la comptabilité globale. *État : appliqué (modèle « fait + rejeu serveur », § 1.4).*

### 5.5 Comment l'appliquer sans casser l'architecture

- Un écart constaté devient un **ticket** (plan de finalisation), pas une retouche au passage.
- L'ordre reste celui du § 4 : web d'abord si le critère manque sur le web, poste ensuite.
- Chaque critère appliqué reçoit son **garde-fou** (test lu dans le code ou test croisé), sinon il n'est pas « appliqué ».
