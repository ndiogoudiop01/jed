#!/usr/bin/env bash
###############################################################################
#  Healthcheck du conteneur Odoo.
#  Utilisé par Docker (HEALTHCHECK), par Coolify et par `make status`.
#
#  Vérifie :
#    1. le port HTTP 8069 répond (endpoint /web/health si dispo, sinon /web/login)
#    2. la base PostgreSQL est joignable
###############################################################################
set -uo pipefail

HTTP_OK=0

# 1) HTTP -------------------------------------------------------------------
if curl -fsS --max-time 8 "http://127.0.0.1:8069/web/health" >/dev/null 2>&1; then
  HTTP_OK=1
elif curl -fsS --max-time 8 -o /dev/null "http://127.0.0.1:8069/web/login" 2>/dev/null; then
  HTTP_OK=1
fi

if [ "${HTTP_OK}" -ne 1 ]; then
  echo "unhealthy: HTTP 8069 ne répond pas" >&2
  exit 1
fi

# 2) PostgreSQL --------------------------------------------------------------
# -d postgres : évite « FATAL: database "<user>" does not exist » dans le
# journal de PostgreSQL à chaque passage de la sonde.
if ! PGPASSWORD="${DB_PASSWORD:-}" pg_isready \
      -h "${DB_HOST:-db}" -p "${DB_PORT:-5432}" -U "${DB_USER:-odoo}" \
      -d postgres -q; then
  echo "unhealthy: PostgreSQL injoignable" >&2
  exit 1
fi

echo "healthy"
exit 0
