#!/usr/bin/env bash
# PWA-PERF — Mesure de performance Lighthouse (usage local uniquement, pas en CI).
#
# Pré-requis : Node.js ≥ 18, lighthouse installé globalement (`npm install -g lighthouse`).
# L'application doit tourner sur APP_URL (par défaut http://127.0.0.1:8002).
#
# Usage :
#   cd agrierp_laravel
#   ./outils/mesure_performance.sh
#   ./outils/mesure_performance.sh http://127.0.0.1:8002/dashboard
#
# Résultats dans : outils/rapports/lighthouse-$(date +%Y%m%d-%H%M%S)/

set -euo pipefail

URL="${1:-http://127.0.0.1:8002}"
RAPPORT_DIR="$(dirname "$0")/rapports/lighthouse-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$RAPPORT_DIR"

echo "=== LogiAgriERP — Mesure Lighthouse ==="
echo "URL cible : $URL"
echo "Rapport   : $RAPPORT_DIR"
echo ""

# Vérifie que lighthouse est disponible.
if ! command -v lighthouse &>/dev/null; then
    echo "❌  Lighthouse introuvable. Installez-le : npm install -g lighthouse"
    exit 1
fi

# Lance Lighthouse sur les trois catégories pertinentes pour une PWA Laravel.
lighthouse "$URL" \
    --output html \
    --output json \
    --output-path "$RAPPORT_DIR/rapport" \
    --only-categories performance,pwa,best-practices \
    --chrome-flags="--headless --no-sandbox --disable-gpu" \
    --quiet

echo ""
echo "✅  Rapport HTML : $RAPPORT_DIR/rapport.report.html"
echo "    Rapport JSON : $RAPPORT_DIR/rapport.report.json"
echo ""

# Extrait et affiche les scores (nécessite jq).
if command -v jq &>/dev/null; then
    JSON="$RAPPORT_DIR/rapport.report.json"
    PERF=$(jq '.categories.performance.score * 100 | round' "$JSON")
    PWA=$(jq '.categories.pwa.score * 100 | round' "$JSON")
    BP=$(jq '.categories["best-practices"].score * 100 | round' "$JSON")
    FCP=$(jq '.audits["first-contentful-paint"].displayValue' "$JSON")
    LCP=$(jq '.audits["largest-contentful-paint"].displayValue' "$JSON")
    TBT=$(jq '.audits["total-blocking-time"].displayValue' "$JSON")

    echo "--- Scores Lighthouse ---"
    echo "  Performance   : ${PERF} / 100"
    echo "  PWA           : ${PWA} / 100"
    echo "  Bonnes pratiques : ${BP} / 100"
    echo ""
    echo "--- Métriques clés ---"
    echo "  FCP (1er affichage)   : $FCP"
    echo "  LCP (affichage principal) : $LCP"
    echo "  TBT (blocage JS)      : $TBT"
    echo ""

    # Alerte si Performance < 70.
    if [ "$PERF" -lt 70 ]; then
        echo "⚠️   Performance < 70 — des améliorations sont nécessaires."
    fi
else
    echo "(Installez jq pour afficher les scores directement dans le terminal.)"
fi
