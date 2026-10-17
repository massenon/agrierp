# CLAUDE.md

Ce fichier guide Claude Code (claude.ai/code) à la racine du monorepo AgriERP.

## Structure

| Dossier | Rôle | Guide détaillé |
|---|---|---|
| `agrierp_laravel/` | Application web Laravel 12 + Livewire 3, API de synchronisation | `agrierp_laravel/CLAUDE.md` |
| `agrierp_flutter/` | Client Windows Flutter offline-first (Drift / SQLite) | `agrierp_flutter/CLAUDE.md` |
| `database/` | Export SQL de référence `agrierp_db` | — |
| `manuel/` | Manuel d'utilisation (HTML → PDF) | — |

**Avant toute modification dans un projet, lire son `CLAUDE.md`.** Ces fichiers ont été écrits quand chaque projet vivait dans son propre dossier Windows (`C:\laragon\www\agrierp`, `C:\Projects\agrierp_flutter`) : leurs chemins absolus correspondent désormais à `agrierp_laravel/` et `agrierp_flutter/` de ce dépôt.

## Règles transverses

- **Tout est en français** : prose, libellés, commentaires, noms de tests, messages de commit.
- Le schéma est partagé : une table synchronisable modifiée côté Laravel (migrations) doit l'être aussi côté Flutter (`lib/core/database/app_database.dart`, puis `dart run build_runner build`), et inversement. Les clés primaires des tables synchronisables sont des UUID, jamais des entiers auto-incrémentés.
- `agrierp_flutter/lib/core/database/app_database.g.dart` est généré : ne jamais l'éditer à la main.
- `database/agrierp_db.sql` est un export de référence, pas une migration : ne pas l'éditer à la main.

## Commandes

```bash
# Laravel
cd agrierp_laravel && php artisan test --testsuite=Feature

# Flutter
cd agrierp_flutter && flutter analyze && flutter test
```
