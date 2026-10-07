#!/bin/sh
###############################################################################
#  make-odoo-zip.sh — emballe un dump.sql au format attendu par le
#  gestionnaire de bases d'Odoo (/web/database/manager).
#
#  POURQUOI : le formulaire « Restore Database » n'accepte que DEUX choses :
#    · un .zip au format Odoo  -> dump.sql [+ filestore/] [+ manifest.json]
#    · un dump BINAIRE pg_dump -Fc
#  Un dump.sql en clair est envoyé à `pg_restore`, qui ne sait pas lire du SQL
#  texte : Odoo répond alors « Couldn't restore database », sans plus de détail.
#  Ce script transforme votre dump.sql en zip acceptable.
#
#  Usage :
#      /scripts/make-odoo-zip.sh <dump.sql> <sortie.zip> [version] [filestore_dir]
#
#  Exemples :
#      /scripts/make-odoo-zip.sh /backups/dump.sql /backups/jed.zip 17.0
#      /scripts/make-odoo-zip.sh /backups/dump.sql /backups/jed.zip 17.0 /backups/filestore
###############################################################################
set -eu

log() { printf '[zip] %s\n' "$*"; }
die() { printf '[zip] ERREUR : %s\n' "$*" >&2; exit 1; }

DUMP="${1:?usage: make-odoo-zip.sh <dump.sql> <sortie.zip> [version] [filestore_dir]}"
OUT="${2:?chemin du zip de sortie manquant}"
VERSION="${3:-${ODOO_VERSION:-17.0}}"
FILESTORE="${4:-}"

[ -f "${DUMP}" ] || die "dump introuvable : ${DUMP}"

command -v zip >/dev/null 2>&1 || apk add --no-cache zip >/dev/null 2>&1 \
  || die "la commande zip est absente et n'a pas pu être installée"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

cp "${DUMP}" "${WORK}/dump.sql"

# manifest.json : Odoo ne l'exige pas pour restaurer, mais il documente la
# version et évite les mauvaises surprises lors d'une relecture ultérieure.
MAJOR="$(printf '%s' "${VERSION}" | cut -d. -f1)"
cat > "${WORK}/manifest.json" <<JSON
{
  "odoo_dump": "1",
  "version": "${VERSION}",
  "version_info": [${MAJOR}, 0, 0, "final", 0, ""],
  "major_version": "${VERSION}",
  "pg_version": "16",
  "modules": {}
}
JSON

if [ -n "${FILESTORE}" ]; then
  [ -d "${FILESTORE}" ] || die "filestore introuvable : ${FILESTORE}"
  mkdir -p "${WORK}/filestore"
  cp -a "${FILESTORE}/." "${WORK}/filestore/"
  log "filestore inclus"
else
  log "sans filestore — les pièces jointes et images seront absentes"
fi

rm -f "${OUT}"
( cd "${WORK}" && zip -q -r -0 "${OUT}" dump.sql manifest.json \
    $([ -d filestore ] && echo filestore) )

log "créé : ${OUT}  ($(du -h "${OUT}" | cut -f1))"
log "à téléverser dans /web/database/manager -> Restore Database"
log "rappel : LIST_DB doit être à True le temps de l'opération"
