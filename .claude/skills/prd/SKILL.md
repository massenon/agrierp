---
name: prd
description: Rédige le PRD (document d'exigences produit) d'une fonctionnalité AgriERP, en français, avant tout code. À utiliser quand on demande un PRD, un cahier des charges, une spécification ou « définir » une fonctionnalité (ex. clôture de caisse, transfert entre bandes, synchronisation automatique).
---

# PRD AgriERP

Produit un fichier `docs/prd/<slug>.md` à la racine du monorepo. Tout est en français.

## Avant d'écrire

1. Lire `docs/DOCTRINE_PORTAGE.md` et `docs/PLAN_FINALISATION.md` (la fonctionnalité y a peut-être déjà un ticket).
2. Chercher la fonctionnalité dans les trois sources, dans l'ordre :
   - la vue Blade et le composant Livewire (`agrierp_laravel/resources/views/livewire/`, `app/Livewire/`) ;
   - les Actions et Services (`app/Actions/`, `app/Services/`) ;
   - `README_SPRINT0.md` (`grep` sur les mots-clés) et `agrierp_flutter/AUDIT_FIDELISATION.md`.
3. Si elle n'existe **ni sur le web ni dans le prototype**, le PRD le dit en tête : la fonctionnalité se construit **d'abord sur le web**, puis se porte sur le poste (Doctrine, article 0).

## Plan du document

```markdown
# PRD — <Nom>
**Statut :** brouillon · **Date :** <AAAA-MM-JJ> · **Ticket(s) :** <ref. PLAN_FINALISATION>

## 1. Problème
Ce qui se passe aujourd'hui sur la ferme, avec un exemple chiffré réel.

## 2. Existant
Ce que le web, le poste et le prototype font déjà (fichiers et lignes cités). « Rien » est une réponse valable.

## 3. Utilisateurs et rôles
Parmi les 4 rôles réels (admin, comptable, caissier, animalier) : qui voit, qui modifie. Permissions `view-*` / `manage-*`.

## 4. Exigences fonctionnelles
Liste numérotée EF1, EF2… Chaque exigence est testable.

## 5. Règles métier et calculs
Formules exactes, avec un jeu d'exemple calculé À LA MAIN (il deviendra le test).
Effets comptables (écriture SYSCOHADA via `AccountingEntryService::record()`), effets stock (`AdjustStockAction`), effets effectifs (cascade unique).

## 6. Hors ligne et synchronisation
Table(s) concernée(s), clé UUID créée sur le poste, règle de conflit (le serveur gagne / dernier écrivain gagne / jamais fusionné / rejoué), comportement sans réseau.

## 7. Interface
Écran web d'abord (composants partagés : `x-datatable`, `x-modal`, `x-kpi-card`), puis portage poste (`CarteKpi`, `ModaleAgri`). Libellés exacts.

## 8. Hors périmètre

## 9. Questions ouvertes pour le client
Chaque question avec la proposition recommandée. Ne jamais trancher à la place du client.

## 10. Critères d'acceptation
Tests nommés (Feature Laravel, tests Flutter), épreuve de mutation incluse.
```

## Règles

- Ne jamais inventer une règle métier : si elle n'est dans aucune source, la mettre en question ouverte (§9).
- Données inconnues = `'—'`, jamais `0`.
- Un PRD ne contient pas de code d'implémentation ; le découpage en tickets relève du skill `plan`.
