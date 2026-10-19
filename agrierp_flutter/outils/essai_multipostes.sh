#!/usr/bin/env bash
# Ticket S-T9 — ESSAI À PLUSIEURS POSTES CONTRE LE VRAI SERVEUR, AVEC COUPURES AU HASARD (méthode TATACORA).
#
# Ce que fait ce script, de bout en bout, sans toucher à rien d'existant :
#   1. une base DÉDIÉE et jetable : un serveur MariaDB/MySQL privé (dossier de données temporaire, port libre, socket
#      privé), base `agrierp_essai` en utf8mb4_unicode_ci comme la production. Sans `mariadbd`/`mysqld` installé, il
#      se replie sur un fichier SQLite temporaire ET LE DIT (les tris, collations, contraintes d'unicité et
#      interblocages de MySQL ne sont alors PAS éprouvés). ⚠️ En SQLite, le contrôle de cohérence montre des écarts
#      d'un centime sur `stock_movements` : SQLite ne borne pas `decimal(12,2)` (0,871 gardé, que MySQL arrondit à
#      0,87 à l'écriture), le serveur somme les valeurs brutes et le poste celles qu'on lui sert. Artefact de la base
#      d'essai, pas de la production ;
#   2. `php artisan migrate:fresh --seed`, puis le jeu de démonstration (`db:seed --class=DemoDataSeeder` : cinq mois
#      d'activité, pour que le tirage paginé de S-T4 ait de vraies pages à servir) ;
#   3. `php artisan serve --no-reload` sur un port libre, avec PHP_CLI_SERVER_WORKERS=4 (les cinq postes parlent EN
#      MÊME TEMPS au serveur, comme à la ferme) ;
#   4. `flutter test test/essai_multipostes_test.dart` (tag `integration`), une fois par graine ;
#   5. arrêt propre : le groupe de processus du serveur (⚠️ tuer `php artisan serve` seul laisse son enfant `php -S`
#      tenir le port), puis MariaDB, puis le dossier temporaire. Le rapport et les journaux sont gardés.
#
# ⚠️⚠️ AUCUN `.env` N'EST LU NI MODIFIÉ POUR LA BASE : tout passe par des variables d'environnement (DB_CONNECTION,
# DB_HOST, DB_PORT, DB_DATABASE…), qui l'emportent sur le `.env` éventuel du dépôt Laravel. Aucune base existante
# n'est ouverte.
#
# Usage (depuis n'importe où) :
#   agrierp_flutter/outils/essai_multipostes.sh                 # une graine tirée au hasard
#   agrierp_flutter/outils/essai_multipostes.sh 42 7 2026       # trois essais, graines 42, 7 et 2026
#   ESSAI_BASE=sqlite agrierp_flutter/outils/essai_multipostes.sh 42   # forcer SQLite
#   ESSAI_FUSEAUX="UTC America/New_York Asia/Tokyo" agrierp_flutter/outils/essai_multipostes.sh 42 7
#                                      # ticket S-T11 : chaque graine rejouée avec les postes dans chacun de ces fuseaux
#
# Variables utiles : AGRIERP_LARAVEL (dossier Laravel ; défaut : ../agrierp_laravel du monorepo), ESSAI_BASE
# (`mysql` par défaut, `sqlite`), ESSAI_SORTIE (dossier des rapports ; défaut : un dossier temporaire hors dépôt),
# ESSAI_JOURS (journées simulées, défaut 4), ESSAI_FUSEAUX (ticket S-T11 : fuseau(x) horaire(s) des POSTES, séparés par
# des espaces ; défaut `Africa/Porto-Novo`). Flutter doit être dans le PATH (`/opt/flutter/bin`).
#
# ⚠️ Ticket S-T11 — le SERVEUR reste toujours à l'heure du Bénin (APP_TIMEZONE) ; c'est le processus des postes
# (`flutter test`, variable TZ) qui prend le fuseau demandé, comme un Windows mal réglé. Les cinq postes d'un essai
# vivent dans le MÊME processus Dart, donc dans le même fuseau : pour éprouver plusieurs fuseaux, la graine est
# rejouée une fois par fuseau (base remise à neuf à chaque fois).
#
# Sortie : pour chaque graine, `rapport-<graine>.txt` (journal des coupures, compteurs, invariants) dans le dossier
# de sortie, dont le chemin est affiché à la fin. Code de retour non nul si un essai échoue.

set -u

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POSTE="$(cd "$ICI/.." && pwd)"
LARAVEL="${AGRIERP_LARAVEL:-$(cd "$POSTE/../agrierp_laravel" 2>/dev/null && pwd)}"
BASE="${ESSAI_BASE:-mysql}"
SORTIE="${ESSAI_SORTIE:-$(mktemp -d "${TMPDIR:-/tmp}/agrierp-essai-sortie.XXXXXX")}"
TRAVAIL="$(mktemp -d "${TMPDIR:-/tmp}/agrierp-essai.XXXXXX")"
mkdir -p "$SORTIE"

if [ "$#" -gt 0 ]; then
  GRAINES=("$@")
else
  GRAINES=("$(( (RANDOM << 15) | RANDOM ))")
fi

if [ -z "$LARAVEL" ] || [ ! -f "$LARAVEL/artisan" ]; then
  echo "Dossier Laravel introuvable (AGRIERP_LARAVEL=$LARAVEL)." >&2
  exit 2
fi
if [ ! -f "$LARAVEL/vendor/autoload.php" ]; then
  echo "Dépendances Laravel absentes : composer install dans $LARAVEL." >&2
  exit 2
fi

PID_SERVEUR=""
PID_MYSQL=""

port_libre() {
  php -r '$s = stream_socket_server("tcp://127.0.0.1:0"); echo explode(":", stream_socket_get_name($s, false))[1];'
}

arreter() {
  if [ -n "$PID_SERVEUR" ]; then
    # Le serveur a été lancé dans son propre groupe (setsid) : `artisan serve` ET ses enfants `php -S`.
    kill -TERM -- "-$PID_SERVEUR" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 -- "-$PID_SERVEUR" 2>/dev/null || break
      sleep 0.3
    done
    kill -KILL -- "-$PID_SERVEUR" 2>/dev/null
    PID_SERVEUR=""
  fi
  if [ -n "$PID_MYSQL" ]; then
    "$CLIENT_ADMIN" --no-defaults --socket="$TRAVAIL/mysqld.sock" -uroot shutdown 2>/dev/null \
      || kill -TERM "$PID_MYSQL" 2>/dev/null
    for _ in $(seq 1 30); do
      kill -0 "$PID_MYSQL" 2>/dev/null || break
      sleep 0.3
    done
    PID_MYSQL=""
  fi
  rm -rf "$TRAVAIL"
}
trap arreter EXIT
trap 'exit 130' INT TERM

# ── 1. Base dédiée ───────────────────────────────────────────────────────────────────────────────────────────────
SERVEUR_MYSQL="$(command -v mariadbd || command -v mysqld || true)"
CLIENT_MYSQL="$(command -v mariadb || command -v mysql || true)"
CLIENT_ADMIN="$(command -v mariadb-admin || command -v mysqladmin || true)"
INSTALLEUR="$(command -v mariadb-install-db || command -v mysql_install_db || true)"

if [ "$BASE" = "mysql" ] && { [ -z "$SERVEUR_MYSQL" ] || [ -z "$CLIENT_MYSQL" ] || [ -z "$INSTALLEUR" ]; }; then
  echo "⚠️  MariaDB/MySQL introuvable : repli sur SQLite. Les points propres à MySQL NE SONT PAS éprouvés." >&2
  BASE="sqlite"
fi

if [ "$BASE" = "mysql" ]; then
  PORT_MYSQL="$(port_libre)"
  "$INSTALLEUR" --no-defaults --datadir="$TRAVAIL/donnees" --user="$(id -un)" \
    --auth-root-authentication-method=normal >"$TRAVAIL/installation.log" 2>&1 \
    || { cat "$TRAVAIL/installation.log" >&2; echo "Initialisation de MariaDB impossible." >&2; exit 2; }
  setsid "$SERVEUR_MYSQL" --no-defaults --datadir="$TRAVAIL/donnees" --socket="$TRAVAIL/mysqld.sock" \
    --port="$PORT_MYSQL" --bind-address=127.0.0.1 --user="$(id -un)" --pid-file="$TRAVAIL/mysqld.pid" \
    --log-error="$SORTIE/mariadb.log" --skip-name-resolve >/dev/null 2>&1 &
  PID_MYSQL=$!
  for _ in $(seq 1 60); do
    "$CLIENT_ADMIN" --no-defaults --socket="$TRAVAIL/mysqld.sock" -uroot ping >/dev/null 2>&1 && break
    sleep 0.5
  done
  "$CLIENT_MYSQL" --no-defaults --socket="$TRAVAIL/mysqld.sock" -uroot -e "
    CREATE DATABASE agrierp_essai CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER 'essai'@'127.0.0.1' IDENTIFIED BY 'essai';
    GRANT ALL ON agrierp_essai.* TO 'essai'@'127.0.0.1';" \
    || { echo "Création de la base d'essai impossible." >&2; exit 2; }
  VERSION_BASE="$("$CLIENT_MYSQL" --no-defaults --socket="$TRAVAIL/mysqld.sock" -uroot -N -e 'SELECT VERSION()')"
  export DB_CONNECTION=mysql DB_HOST=127.0.0.1 DB_PORT="$PORT_MYSQL" DB_DATABASE=agrierp_essai \
    DB_USERNAME=essai DB_PASSWORD=essai
else
  touch "$TRAVAIL/essai.sqlite"
  VERSION_BASE="SQLite $(php -r 'echo (new PDO("sqlite::memory:"))->query("select sqlite_version()")->fetchColumn();')"
  export DB_CONNECTION=sqlite DB_DATABASE="$TRAVAIL/essai.sqlite"
  unset DB_HOST DB_PORT DB_USERNAME DB_PASSWORD
fi

# Application : une clé propre à l'essai, journaux sur la sortie d'erreur du serveur (pas dans storage/logs du dépôt),
# file d'attente synchrone, courriels au journal. Le reste vient du `.env` s'il existe (jamais modifié).
export APP_KEY="base64:$(php -r 'echo base64_encode(random_bytes(32));')"
export APP_ENV=local APP_DEBUG=true APP_TIMEZONE=Africa/Porto-Novo APP_LOCALE=fr
export LOG_CHANNEL=stderr LOG_LEVEL=warning QUEUE_CONNECTION=sync MAIL_MAILER=log BROADCAST_CONNECTION=log
export CACHE_STORE=database SESSION_DRIVER=array

echo "Base de l'essai : $DB_CONNECTION ($VERSION_BASE)"
echo "Rapports        : $SORTIE"

# ── 2. Migration, jeu de démonstration ───────────────────────────────────────────────────────────────────────────
preparer_base() {
  (cd "$LARAVEL" && php artisan migrate:fresh --seed --force >"$SORTIE/migration.log" 2>&1 \
    && php artisan db:seed --class=DemoDataSeeder --force >>"$SORTIE/migration.log" 2>&1) \
    || { tail -30 "$SORTIE/migration.log" >&2; echo "Migration de la base d'essai en échec." >&2; return 1; }
}

# ── 3. Serveur ───────────────────────────────────────────────────────────────────────────────────────────────────
demarrer_serveur() {
  PORT_HTTP="$(port_libre)"
  # `exec setsid` : le processus d'arrière-plan EST `artisan serve`, chef de son propre groupe — `kill -- -PID`
  # atteint alors aussi les `php -S` qu'il lance.
  (cd "$LARAVEL" && PHP_CLI_SERVER_WORKERS=4 exec setsid php artisan serve --host=127.0.0.1 --port="$PORT_HTTP" \
    --no-reload >>"$SORTIE/serveur.log" 2>&1) &
  PID_SERVEUR=$!
  for _ in $(seq 1 60); do
    curl -s -o /dev/null "http://127.0.0.1:$PORT_HTTP/up" && return 0
    sleep 0.5
  done
  echo "Le serveur ne répond pas sur le port $PORT_HTTP." >&2
  return 1
}

# ── 4. Un essai par graine (base remise à neuf à chaque fois) ────────────────────────────────────────────────────
STATUT=0
export PATH="/opt/flutter/bin:$PATH"
read -r -a FUSEAUX <<<"${ESSAI_FUSEAUX:-Africa/Porto-Novo}"
for GRAINE in "${GRAINES[@]}"; do
for FUSEAU in "${FUSEAUX[@]}"; do
  if [ ! -f "/usr/share/zoneinfo/$FUSEAU" ]; then
    echo "Fuseau inconnu : $FUSEAU" >&2
    STATUT=1
    continue
  fi
  # Suffixe des rapports : la graine seule au fuseau du Bénin (comme avant S-T11), la graine et le fuseau sinon.
  if [ "$FUSEAU" = "Africa/Porto-Novo" ]; then SUFFIXE="$GRAINE"; else SUFFIXE="$GRAINE-${FUSEAU//\//_}"; fi
  echo "── Graine $GRAINE, postes en $FUSEAU ──"
  if [ "$BASE" = "mysql" ]; then
    "$CLIENT_MYSQL" --no-defaults --socket="$TRAVAIL/mysqld.sock" -uroot \
      -e "DROP DATABASE IF EXISTS agrierp_essai; CREATE DATABASE agrierp_essai CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  else
    : >"$TRAVAIL/essai.sqlite"
  fi
  preparer_base || { STATUT=1; continue; }
  demarrer_serveur || { STATUT=1; continue; }

  # Les postes vivent dans le fuseau demandé (S-T11 : un Windows mal réglé) ; le serveur, à l'heure du Bénin.
  (cd "$POSTE" && TZ="$FUSEAU" AGRIERP_ESSAI_URL="http://127.0.0.1:$PORT_HTTP" AGRIERP_ESSAI_GRAINE="$GRAINE" \
    AGRIERP_ESSAI_RAPPORT="$SORTIE/rapport-$SUFFIXE.txt" AGRIERP_ESSAI_BASE="$DB_CONNECTION ($VERSION_BASE)" \
    AGRIERP_ESSAI_JOURS="${ESSAI_JOURS:-4}" AGRIERP_LARAVEL="$LARAVEL" AGRIERP_ESSAI_FUSEAU="$FUSEAU" \
    flutter test test/essai_multipostes_test.dart --tags integration --reporter expanded \
    >"$SORTIE/flutter-$SUFFIXE.log" 2>&1)
  RESULTAT=$?
  tail -5 "$SORTIE/flutter-$SUFFIXE.log"
  if [ "$RESULTAT" -ne 0 ]; then
    STATUT=1
    echo "❌ Graine $GRAINE ($FUSEAU) : échec (voir $SORTIE/flutter-$SUFFIXE.log et $SORTIE/rapport-$SUFFIXE.txt)"
  elif grep -q "Skip:" "$SORTIE/flutter-$SUFFIXE.log"; then
    STATUT=1
    echo "⚠️  Graine $GRAINE ($FUSEAU) : essai SAUTÉ — voir $SORTIE/flutter-$SUFFIXE.log"
  else
    echo "✅ Graine $GRAINE ($FUSEAU) : tous les invariants tiennent ($SORTIE/rapport-$SUFFIXE.txt)"
  fi

  # Le serveur est arrêté entre deux graines : la base est remise à neuf, et le limiteur de connexion (5 / min par
  # adresse) repart de zéro avec elle (cache en base).
  if [ -n "$PID_SERVEUR" ]; then
    kill -TERM -- "-$PID_SERVEUR" 2>/dev/null
    sleep 1
    kill -KILL -- "-$PID_SERVEUR" 2>/dev/null
    PID_SERVEUR=""
  fi
done
done

echo "Rapports et journaux : $SORTIE"
exit "$STATUT"
