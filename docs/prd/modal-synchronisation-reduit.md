# PRD — Modale de Synchronisation (web) : fin du rognage par la barre latérale, format réduit
**Statut :** livré · **Date :** 2026-10-27 · **Surface :** web (le poste n'est pas concerné) · **Suite du ticket #35**

## 1. Problème
Depuis l'agrandissement du ticket #35 (`max-w-5xl`), la modale « Synchronisation » est **rognée à gauche par la barre latérale** : le titre, le début des textes et la colonne « Poste » sont masqués. Deux causes :
- **Cause technique :** la modale est rendue dans l'en-tête (`sticky z-30`), qui crée son propre empilement ; son `z-[110]` ne vaut qu'à l'intérieur de l'en-tête, donc la barre latérale (`z-50`) passe au-dessus.
- **Cause de taille :** la modale est devenue plus large que la zone de contenu, et les deux paragraphes d'introduction (≈ 90 mots) la rendent haute.

## 2. Objectifs
- La modale est **entièrement visible**, centrée sur la fenêtre, voile sombre sur tout l'écran, barre latérale comprise.
- La modale est **plus étroite** (`max-w-3xl`, 768 px) et **plus courte** (introduction ≈ 55 mots, espacement réduit).

## 3. Hors périmètre
- Les autres modales (aucune n'est dans l'en-tête) : le comportement par défaut de `<x-modal>` ne change pas.
- La modale du poste (`ModaleAgri`) : elle n'a pas ce défaut.
- Le contenu du tableau et les gestes (« Demander… », « Renvoyer… », « Actualiser »).

## 4. Exigences (P0) et critères d'acceptation
- **R1.** `<x-modal>` accepte `teleport` (défaut `false`) ; vrai, la modale est déplacée sous `<body>`.
  - [ ] Ouverte depuis l'en-tête, la modale n'est plus recouverte par la barre latérale (largeur 1280 px et plus).
  - [ ] La touche Échap, le clic à l'extérieur, ✕ et « Fermer » ferment toujours la modale.
- **R2.** La modale « Synchronisation » utilise `teleport` et la largeur `xl`.
  - [ ] Les actions Livewire (`demander`, `renvoyer`, « Actualiser ») fonctionnent depuis la modale déplacée.
- **R3.** Textes d'introduction raccourcis, mêmes termes métier : « Demander la synchronisation », « Renvoyer vers ce poste », « tirage complet », « 30 secondes ».
  - [ ] `EtatSynchronisationPostesTest` et `ResynchronisationPostesTest` restent verts ; la parité de libellés du poste (`resynchronisation_serveur_test.dart`) reste verte.

## 5. Questions ouvertes (non bloquantes)
- Faut-il généraliser `teleport` à toutes les modales ? **Non pour l'instant** : 160 emplacements, aucun défaut constaté ailleurs.
