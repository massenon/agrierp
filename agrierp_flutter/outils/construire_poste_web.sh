#!/usr/bin/env bash
# PWA-2 — construit le poste pour le web et le dépose dans agrierp_laravel/public/poste/ (dossier IGNORÉ par git).
#
# Usage : agrierp_flutter/outils/construire_poste_web.sh [--sans-copie]
# Prérequis : Flutter (version de .fvmrc), python3. `sqlite3.wasm` et `drift_worker.js` sont versionnés dans web/ ;
# s'ils manquent : outils/recuperer_wasm_web.sh.
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LARAVEL="${AGRIERP_LARAVEL:-$ICI/../agrierp_laravel}"
cd "$ICI"

for f in web/sqlite3.wasm web/drift_worker.js; do
  [ -f "$f" ] || { echo "Manquant : $f (lancer outils/recuperer_wasm_web.sh)" >&2; exit 1; }
done

# ⚠️ --no-web-resources-cdn : OBLIGATOIRE. Sans lui, CanvasKit se charge depuis www.gstatic.com : écran vide sans Internet.
# ⚠️ --base-href /poste/ : l'application est servie sous /poste/ par Laravel (même origine que l'API).
flutter build web --release --no-web-resources-cdn --base-href /poste/

# Précache et version du service worker propre au poste (poste_sw.js, portée /poste/).
python3 outils/generer_sw_poste.py build/web

# Garde-fou « aucune URL externe pour le moteur » : le build doit porter useLocalCanvasKit:true (--no-web-resources-cdn).
# (Le code du chargeur garde l'adresse gstatic en repli ; seul ce drapeau compte. fonts.gstatic.com/s/ de main.dart.js n'est
# qu'une police de secours chargée à la demande : hors ligne, elle échoue sans casser l'application.)
if ! grep -q '"useLocalCanvasKit":true' build/web/flutter_bootstrap.js; then
  echo "useLocalCanvasKit absent du build : --no-web-resources-cdn n'a pas été appliqué." >&2
  exit 1
fi

if [ "${1:-}" = "--sans-copie" ]; then
  echo "Build prêt dans $ICI/build/web (copie ignorée)."
  exit 0
fi

CIBLE="$LARAVEL/public/poste"
rm -rf "$CIBLE"
mkdir -p "$CIBLE"
cp -r build/web/. "$CIBLE/"
echo "Poste web déposé dans $CIBLE (servi sous /poste/)."
