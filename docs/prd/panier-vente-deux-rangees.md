# PRD — Panier de vente : « Client » / « Date » séparés, totaux en deux rangées (web et poste)
**Statut :** livré · **Date :** 2026-10-27 · **Surfaces :** web (`pos-interface.blade.php`) et poste (`caisse_screen.dart`) · **Suite du ticket #47**

## 1. Problème
- Au panier, les champs « Client » et « Date de la vente » **se touchent** : la colonne de gauche contient un `select` + le bouton « + » qui ne rétrécissent pas, et débordent sur la colonne de droite.
- Le client avait demandé (ticket #47) de libérer de la hauteur. Les totaux restent empilés sur cinq lignes (Sous-total, Remise, Total à Payer, Mode de Règlement, …) au lieu de **deux rangées**.

## 2. Objectifs
- Un **écart franc** entre « Client » et « Date de la vente ».
- Les totaux sur **deux rangées de deux colonnes** :
  - rangée 1 : **Sous-total** | **Remise (FCFA)** ;
  - rangée 2 : **Total à Payer** | **Mode de Règlement**.
- Même disposition au web et au poste (fidélité absolue, article 5 de la doctrine : le web est le maître).

## 3. Hors périmètre
- Les règles de calcul (remise, total, monnaie), les libellés, les clés de test (`remise`, `total-a-payer`, `mode-reglement`).
- « Montant Reçu » / « Monnaie à Rendre » (déjà sur une rangée de deux).
- **La modale du poste dans l'en-tête :** voir §5.

## 4. Exigences (P0) et critères d'acceptation
- **R1 — Client / Date.** Colonnes `min-w-0`, écart `gap-md` (web) / 16 px (poste).
  - [ ] Aucun chevauchement à 340 px de panier ; la liste des clients se réduit, le bouton « + » reste visible.
- **R2 — Rangée 1.** « Sous-total » (valeur en gras) à gauche, « Remise (FCFA) » (champ pleine colonne, aligné à droite) à droite.
- **R3 — Rangée 2.** « Total à Payer » (valeur 18 px, vert) à gauche, « Mode de Règlement » (liste) à droite, séparées de la rangée 1 par un filet.
  - [ ] Le total grossit sans casser la rangée (poste : mise à l'échelle au besoin).
- **R4 — Gardes.** Web : `PosPanierDeuxRangeesTest` (lit le Blade). Poste : `caisse_screen_test.dart` (« le panier range Sous-total / Remise puis Total / Mode de règlement » : rangées alignées, colonnes séparées, écart Client/Date ≥ 8 px).

## 5. Demande « modale rendue dans l'en-tête, sous la barre latérale — DANS LE POSTE »
**Constat :** le défaut est propre au web (modale rendue dans l'en-tête collant `z-30`, sous la barre latérale `z-50`) ; corrigé le 27/10/2026 (`teleport`, voir `modal-synchronisation-reduit.md`). Le poste n'a **pas** ce défaut : `afficherModale` ouvre la modale sur le navigateur racine (aucun `Navigator` imbriqué dans `lib/`), le voile et la fenêtre couvrent toute la fenêtre, barre latérale comprise.
**Garde ajoutée :** `test/modale_au_dessus_barre_laterale_test.dart` — le voile couvre toute la fenêtre. Si une capture du poste montre pourtant une modale rognée, la joindre : ce serait un autre défaut.

## 6. Questions ouvertes (non bloquantes)
- Faut-il appliquer la même disposition à « Montant Reçu » / « Monnaie à Rendre » ? (déjà en deux colonnes, rien à faire).
