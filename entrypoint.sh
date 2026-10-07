#!/usr/bin/env bash
###############################################################################
#  Entrypoint Odoo
#  1. attend que PostgreSQL réponde
#  2. génère /etc/odoo/odoo.conf à partir du template + variables du .env
#  3. lance Odoo (ou la commande passée en argument)
#
#  Aucune valeur n'est codée en dur ici : tout vient du .env.
###############################################################################
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*" >&2; }

# ---------------------------------------------------------------- 1. defaults
: "${DB_HOST:=db}"
: "${DB_PORT:=5432}"
: "${DB_USER:=odoo}"
: "${DB_PASSWORD:?DB_PASSWORD manquant dans le .env}"
: "${DB_NAME:=false}"
: "${DB_FILTER:=.*}"
: "${DB_MAXCONN:=64}"
: "${LIST_DB:=False}"
: "${ODOO_MASTER_PASSWORD:?ODOO_MASTER_PASSWORD manquant dans le .env}"
: "${ODOO_WORKERS:=2}"
: "${ODOO_MAX_CRON_THREADS:=1}"
: "${ODOO_LOG_LEVEL:=info}"
: "${ODOO_LOG_HANDLER:=:INFO}"
: "${WITHOUT_DEMO:=all}"
: "${LIMIT_MEMORY_SOFT:=2147483648}"
: "${LIMIT_MEMORY_HARD:=2684354560}"
: "${LIMIT_TIME_CPU:=600}"
: "${LIMIT_TIME_REAL:=1200}"
: "${LIMIT_TIME_REAL_CRON:=0}"
: "${LIMIT_REQUEST:=8192}"
: "${SERVER_WIDE_MODULES:=base,web}"
: "${ODOO_DEBUGPY:=0}"
: "${ODOO_DEBUGPY_WAIT:=0}"
: "${ODOO_EXTRA_ARGS:=}"

# --- addons_path -------------------------------------------------------------
# Ordre : enterprise > core > OCA > custom  (le dernier gagne en cas d'homonyme).
#
# Le core peut exposer SES addons à deux endroits selon la provenance :
#   odoo/addons/  -> le module « base » (clone git comme archive Sources)
#   addons/       -> les modules standard
# On prend tous ceux qui contiennent réellement des modules.
: "${ODOO_HOME:=/opt/odoo}"
: "${ODOO_ENTERPRISE_ADDONS:=/opt/odoo-enterprise}"

# un dossier « d'addons » contient directement des modules (*/__manifest__.py)
holds_modules() { compgen -G "$1/*/__manifest__.py" >/dev/null 2>&1; }
has_content()   { [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null | grep -v '^\.gitkeep$')" ]; }

CORE_HINT="${ODOO_CORE_ADDONS:-}"
CORE_DIRS=()
for candidate in ${CORE_HINT//,/ } \
                 "${ODOO_HOME}/addons" \
                 "${ODOO_HOME}/odoo/addons" \
                 /usr/lib/python3/dist-packages/odoo/addons; do
  [ -n "${candidate}" ] || continue
  # chemin relatif hérité de l'image de base -> le rendre absolu
  case "${candidate}" in /*) ;; *) candidate="${ODOO_HOME}/${candidate}" ;; esac
  # dédoublonnage
  skip=0
  for already in "${CORE_DIRS[@]-}"; do [ "${already}" = "${candidate}" ] && skip=1; done
  [ "${skip}" -eq 1 ] && continue
  holds_modules "${candidate}" && CORE_DIRS+=("${candidate}")
done

if [ "${#CORE_DIRS[@]}" -eq 0 ]; then
  log "ERREUR : aucun dossier d'addons du core trouvé sous ${ODOO_HOME}"
  log "         l'image de base est-elle correcte ? voir docs/BASE-IMAGES.md"
  exit 1
fi

ADDONS_DIRS=()
has_content "${ODOO_ENTERPRISE_ADDONS}" && ADDONS_DIRS+=("${ODOO_ENTERPRISE_ADDONS}")
ADDONS_DIRS+=("${CORE_DIRS[@]}")

# addons-oca/ contient soit des modules à plat, soit un dossier par dépôt OCA.
holds_modules /mnt/addons-oca && ADDONS_DIRS+=("/mnt/addons-oca")
if [ -d /mnt/addons-oca ]; then
  for repo in /mnt/addons-oca/*/; do
    [ -d "${repo}" ] || continue
    holds_modules "${repo%/}" && ADDONS_DIRS+=("${repo%/}")
  done
fi

has_content /mnt/addons-custom && ADDONS_DIRS+=("/mnt/addons-custom")

ADDONS_PATH="$(IFS=,; echo "${ADDONS_DIRS[*]}")"
export ADDONS_PATH

# ------------------------------------------------------- 2. attente PostgreSQL
log "attente de PostgreSQL sur ${DB_HOST}:${DB_PORT} ..."
for i in $(seq 1 60); do
  # -d postgres : sans base explicite, libpq utilise le nom d'UTILISATEUR comme
  # nom de base. La sonde réussit quand même, mais PostgreSQL journalise
  # « FATAL: database "odoo" does not exist » à chaque appel — bruit inutile.
  if PGPASSWORD="${DB_PASSWORD}" pg_isready -h "${DB_HOST}" -p "${DB_PORT}" \
       -U "${DB_USER}" -d postgres -q; then
    log "PostgreSQL est prêt (tentative ${i})"
    break
  fi
  if [ "${i}" -eq 60 ]; then
    log "ERREUR : PostgreSQL injoignable après 60 tentatives"
    exit 1
  fi
  sleep 2
done

# ------------------------------------------------------ 3. génération odoo.conf
export DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME DB_FILTER DB_MAXCONN LIST_DB \
       ODOO_MASTER_PASSWORD ODOO_WORKERS ODOO_MAX_CRON_THREADS ODOO_LOG_LEVEL \
       ODOO_LOG_HANDLER WITHOUT_DEMO LIMIT_MEMORY_SOFT LIMIT_MEMORY_HARD \
       LIMIT_TIME_CPU LIMIT_TIME_REAL LIMIT_TIME_REAL_CRON LIMIT_REQUEST \
       SERVER_WIDE_MODULES

envsubst < /etc/odoo/odoo.conf.tpl > /etc/odoo/odoo.conf
chmod 640 /etc/odoo/odoo.conf
log "odoo.conf généré (addons_path=${ADDONS_PATH})"

# ------------------------------------------------------------------ 4. lancement
if [ "$#" -eq 0 ] || [ "$1" = "odoo" ]; then
  shift || true
  # shellcheck disable=SC2206
  EXTRA=( ${ODOO_EXTRA_ARGS} )
  if [ "${ODOO_DEBUGPY}" = "1" ]; then
    # debugpy doit lancer le SCRIPT python d'Odoo, pas le wrapper shell `odoo`.
    ODOO_BIN=""
    for candidate in "${ODOO_HOME:-/opt/odoo}/odoo-bin" /usr/bin/odoo /usr/local/bin/odoo-bin; do
      [ -f "${candidate}" ] && head -1 "${candidate}" | grep -q python && { ODOO_BIN="${candidate}"; break; }
    done
    if [ -z "${ODOO_BIN}" ]; then
      log "ATTENTION : odoo-bin introuvable, démarrage sans debugpy"
    else
      PY="$(command -v python3)"
      WAIT_FLAG=()
      [ "${ODOO_DEBUGPY_WAIT}" = "1" ] && WAIT_FLAG=(--wait-for-client)
      log "démarrage avec debugpy sur 0.0.0.0:5678 (${ODOO_BIN}) ${WAIT_FLAG[*]-}"
      exec "${PY}" -m debugpy --listen 0.0.0.0:5678 "${WAIT_FLAG[@]}" \
           "${ODOO_BIN}" --config=/etc/odoo/odoo.conf "${EXTRA[@]}" "$@"
    fi
  fi
  exec odoo --config=/etc/odoo/odoo.conf "${EXTRA[@]}" "$@"
fi

# Toute autre commande (bash, psql, odoo shell, scripts...) est exécutée telle quelle.
exec "$@"
