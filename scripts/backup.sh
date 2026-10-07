#!/bin/sh
###############################################################################
#  Sauvegarde complète d'un client : base(s) PostgreSQL + filestore Odoo.
#
#  Produit un fichier par base :
#      /backups/<slug>__<base>__<AAAAMMJJ-HHMM>.tar.gz
#  contenant :
#      dump.sql            (pg_dump format plain, restaurable partout)
#      filestore/          (pièces jointes Odoo)
#      manifest.txt        (version Odoo, date, taille, empreinte)
#
#  Chiffrement optionnel : si BACKUP_ENC_PASSPHRASE est défini, l'archive est
#  chiffrée en AES-256 (openssl) et suffixée .enc
#
#  Usage :
#      docker compose exec backup /bin/sh /scripts/backup.sh          # toutes les bases
#      docker compose exec backup /bin/sh /scripts/backup.sh ma_base  # une seule base
###############################################################################
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"
FILESTORE_DIR="${FILESTORE_DIR:-/filestore/filestore}"
CLIENT_SLUG="${CLIENT_SLUG:-odoo}"
RETENTION="${BACKUP_RETENTION_DAYS:-14}"
STAMP="$(date '+%Y%m%d-%H%M')"

log() { printf '[backup] %s\n' "$*"; }

mkdir -p "${BACKUP_DIR}"

# --- Liste des bases à sauvegarder -------------------------------------------
if [ "$#" -ge 1 ]; then
  DATABASES="$*"
else
  DATABASES="$(psql -tAc \
    "SELECT datname FROM pg_database
      WHERE datistemplate = false AND datname NOT IN ('postgres')" postgres)"
fi

if [ -z "${DATABASES}" ]; then
  log "aucune base à sauvegarder"
  exit 0
fi

# --- Sauvegarde --------------------------------------------------------------
for DB in ${DATABASES}; do
  log "base « ${DB} » ..."
  WORK="$(mktemp -d)"
  trap 'rm -rf "${WORK}"' EXIT

  pg_dump --no-owner --no-privileges --format=plain --file="${WORK}/dump.sql" "${DB}"

  mkdir -p "${WORK}/filestore"
  if [ -d "${FILESTORE_DIR}/${DB}" ]; then
    cp -a "${FILESTORE_DIR}/${DB}" "${WORK}/filestore/${DB}"
    FS_SIZE="$(du -sh "${WORK}/filestore" | cut -f1)"
  else
    log "  (pas de filestore pour ${DB})"
    FS_SIZE="0"
  fi

  {
    echo "client=${CLIENT_SLUG}"
    echo "database=${DB}"
    echo "date=$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "postgres=$(psql -tAc 'SHOW server_version' postgres | tr -d ' ')"
    echo "dump_bytes=$(wc -c < "${WORK}/dump.sql")"
    echo "filestore_size=${FS_SIZE}"
  } > "${WORK}/manifest.txt"

  ARCHIVE="${BACKUP_DIR}/${CLIENT_SLUG}__${DB}__${STAMP}.tar.gz"
  tar -czf "${ARCHIVE}" -C "${WORK}" dump.sql filestore manifest.txt

  if [ -n "${BACKUP_ENC_PASSPHRASE:-}" ]; then
    command -v openssl >/dev/null 2>&1 || apk add --no-cache openssl >/dev/null 2>&1 || true
    if command -v openssl >/dev/null 2>&1; then
      openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
        -pass "pass:${BACKUP_ENC_PASSPHRASE}" \
        -in "${ARCHIVE}" -out "${ARCHIVE}.enc"
      rm -f "${ARCHIVE}"
      ARCHIVE="${ARCHIVE}.enc"
    else
      log "  ATTENTION : openssl indisponible, archive NON chiffrée"
    fi
  fi

  log "  -> ${ARCHIVE} ($(du -sh "${ARCHIVE}" | cut -f1))"

  rm -rf "${WORK}"
  trap - EXIT
done

# --- Purge des anciennes archives --------------------------------------------
log "purge des sauvegardes de plus de ${RETENTION} jours"
find "${BACKUP_DIR}" -maxdepth 1 -name "${CLIENT_SLUG}__*" -type f \
     -mtime "+${RETENTION}" -print -delete || true

log "terminé"
