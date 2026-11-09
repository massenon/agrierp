#!/usr/bin/env bash
# PWA-2 — (re)récupère `sqlite3.wasm` et `drift_worker.js` dans web/, aux versions de pubspec.lock.
#
# Ces deux fichiers sont VERSIONNÉS (≈ 1,1 Mo) ; ce script ne sert qu'à les mettre à jour après une montée de `drift` ou de
# `sqlite3` dans pubspec.lock. Le module wasm vient des releases de simolus3/sqlite3.dart ; le worker, du paquet drift du cache pub.
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ICI"

version() { awk -v p="  $1:" '$0==p {t=1} t && /version:/ {gsub(/"/,"",$2); print $2; exit}' pubspec.lock; }
SQLITE3="$(version sqlite3)"
DRIFT="$(version drift)"
echo "sqlite3 $SQLITE3, drift $DRIFT (pubspec.lock)"

curl -fsSL -o web/sqlite3.wasm "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$SQLITE3/sqlite3.wasm"

PUB="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/drift-$DRIFT/drift_worker.js"
[ -f "$PUB" ] || { echo "drift_worker.js introuvable : lancer d'abord « flutter pub get »." >&2; exit 1; }
cp "$PUB" web/drift_worker.js

ls -l web/sqlite3.wasm web/drift_worker.js
