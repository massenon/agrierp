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

  ⚠️ L'application web n'a **pas** de composant de pagination aujourd'hui (voir `agrierp_laravel/CLAUDE.md`). La pagination standard est donc une **CIBLE commune aux deux surfaces**.
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
