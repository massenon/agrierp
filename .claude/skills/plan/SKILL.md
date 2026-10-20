---
name: plan
description: Établit le plan d'implémentation d'un ticket AgriERP (web Laravel et/ou poste Flutter) avant d'écrire du code, ou met à jour docs/PLAN_FINALISATION.md. À utiliser quand on demande un plan, un découpage en tickets, « comment on s'y prend », ou avant tout ticket qui touche un écran, un calcul ou une donnée synchronisée.
---

# Plan de ticket AgriERP

Un ticket = une session. Le plan est annoncé **avant** tout code et validé par l'utilisateur quand il touche le schéma, la comptabilité ou une décision client.

## Étapes

1. **Situer le ticket** dans `docs/PLAN_FINALISATION.md` (le créer s'il manque, avec son statut 🔧 / ❓).
2. **Lire en entier**, sans reconstruire de mémoire :
   - le composant Livewire et la vue Blade concernés ;
   - les Actions/Services qu'ils appellent ;
   - l'écran et le repository Flutter correspondants (`lib/features/<module>/`) ;
   - les entrées de `README_SPRINT0.md` sur ce sujet (`grep`).
3. **Lister les points de passage uniques** touchés (`agrierp_laravel/CLAUDE.md`) : `AccountingEntryService::record()`, `AdjustStockAction`, cascade des effectifs (`RecordSaleOnFicheElevageAction::recalculerEnCascade` / `FicheJournaliereRepository.recalculerEnCascade`), `SyncController`. Ne jamais les contourner.
4. **Écrire le plan** dans la réponse, sous cette forme :

```markdown
### Ticket <ref> — <titre>
**Objectif :** une phrase.
**Décisions client requises :** aucune / liste (bloquant ?).

**Web (agrierp_laravel)** — ordre : migration → modèle → Action/Service → Livewire → Blade
- fichier : changement

**Poste (agrierp_flutter)** — ordre : table Drift (+ build_runner, palier de migration) → repository → écran
- fichier : changement

**Synchronisation :** table, règle de conflit, impact sur `/api/sync/pull|push`.

**Tests (écrits AVANT le correctif, rouges d'abord) :**
- Laravel : `tests/Feature/<Nom>Test.php` — cas et valeurs attendues calculées à la main
- Flutter : `test/<nom>_test.dart` — idem, parité PHP si un calcul est porté
- Épreuve de mutation : quelle ligne retirer pour voir le test rougir

**Vérification :** `php artisan test --testsuite=Feature`, `flutter analyze`, `flutter test`.
**Hors périmètre / risques :**
```

5. Après livraison : consigner le ticket dans `README_SPRINT0.md` (avec ce qui n'a **pas** été vérifié) et mettre à jour son statut dans `docs/PLAN_FINALISATION.md`.

## Règles

- Ne jamais convertir plusieurs écrans d'un coup sans vérification intermédiaire.
- Une fonctionnalité absente du web se planifie **web d'abord**, poste ensuite.
- Signaler toute contradiction entre sources au lieu de la résoudre en silence.
