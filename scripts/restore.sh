#!/bin/sh
###############################################################################
#  Restauration d'une base Odoo — accepte TOUS les formats courants.
#
#  Usage :
#      /scripts/restore.sh <fichier> [base_cible] [--filestore <chemin>] [--keep]
#
#  Formats reconnus, détectés sur le CONTENU et non sur l'extension :
#
#    .tar.gz / .tar.gz.enc   archive produite par backup.sh (dump + filestore)
#    .zip                    sauvegarde au format Odoo (dump.sql + filestore/)
#    .sql                    dump SQL en clair  (pg_dump -Fp)   <- votre cas
#    .sql.gz                 idem, compressé gzip
#    .dump / .backup         dump binaire       (pg_dump -Fc)
#
#  Exemples :
#      /scripts/restore.sh /backups/dump.sql jed
#      /scripts/restore.sh /backups/dump.sql jed --filestore /backups/filestore
#      /scripts/restore.sh /backups/jed__jed__20261006-0200.tar.gz
#
#  ATTENTION : la base cible est SUPPRIMÉE puis recréée.
#  Arrêtez Odoo avant (`make stop-odoo`) : une connexion active bloque le DROP.
###############################################################################
set -eu

log()  { printf '[restore] %s\n' "$*"; }
die()  { printf '[restore] ERREUR : %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ arguments
SRC=""; TARGET_DB=""; FILESTORE_SRC=""; KEEP_AUTOMATION=0
while [ $# -gt 0 ]; do
  case "$1" in
    --filestore) FILESTORE_SRC="${2:?--filestore attend un chemin}"; shift 2 ;;
    --keep)      KEEP_AUTOMATION=1; shift ;;
    -h|--help)   sed -n '2,25p' "$0"; exit 0 ;;
    -*)          die "option inconnue : $1" ;;
    *)           if [ -z "${SRC}" ]; then SRC="$1"; else TARGET_DB="$1"; fi; shift ;;
  esac
done

[ -n "${SRC}" ]  || die "usage : restore.sh <fichier> [base_cible] [--filestore <chemin>]"
[ -f "${SRC}" ]  || die "fichier introuvable : ${SRC}"

FILESTORE_DIR="${FILESTORE_DIR:-/filestore/filestore}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  log "installation de $2"
  apk add --no-cache "$2" >/dev/null 2>&1 || die "$1 est absent et n'a pas pu être installé"
}

# ------------------------------------------------- 1. déchiffrement éventuel
case "${SRC}" in
  *.enc)
    [ -n "${BACKUP_ENC_PASSPHRASE:-}" ] || die "BACKUP_ENC_PASSPHRASE requis pour un .enc"
    need openssl openssl
    log "déchiffrement"
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
      -pass "pass:${BACKUP_ENC_PASSPHRASE}" -in "${SRC}" -out "${WORK}/clear.bin"
    SRC="${WORK}/clear.bin"
    ;;
esac

# ------------------------------------------------- 2. identification du format
#  `file` n'est pas garanti présent : on lit les octets de tête nous-mêmes.
magic="$(dd if="${SRC}" bs=5 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"

KIND=""
case "${magic}" in
  1f8b*)  KIND="gzip" ;;                       # .gz : tar.gz OU sql.gz
  504b03*) KIND="zip" ;;                       # PK\x03\x04
  5047444d*) KIND="pgcustom" ;;                # "PGDMP"
esac
[ -n "${KIND}" ] || KIND="sql"                 # tout le reste : SQL en clair

DUMP=""; FILESTORE_IN=""; SOURCE_DB=""

case "${KIND}" in
  gzip)
    # tar ou pas ? Un fichier tar porte « ustar » à l'offset 257. Se fier au
    # code retour de `tar -tzf` ne suffit pas : certaines implémentations
    # acceptent sans broncher un gzip qui n'est pas une archive.
    inner="$(gunzip -c "${SRC}" 2>/dev/null | dd bs=1 skip=257 count=5 2>/dev/null || true)"
    if [ "${inner}" = "ustar" ]; then
      log "format : archive tar.gz (backup.sh)"
      tar -xzf "${SRC}" -C "${WORK}"
      [ -f "${WORK}/manifest.txt" ] && { log "manifeste :"; cat "${WORK}/manifest.txt"; }
      SOURCE_DB="$(sed -n 's/^database=//p' "${WORK}/manifest.txt" 2>/dev/null || true)"
      DUMP="$(find "${WORK}" -maxdepth 2 -name 'dump.sql' | head -1)"
      [ -n "${DUMP}" ] || die "pas de dump.sql dans l'archive"
      FILESTORE_IN="$(find "${WORK}" -maxdepth 2 -type d -name 'filestore' | head -1)"
    else
      log "format : dump SQL compressé (.sql.gz)"
      gunzip -c "${SRC}" > "${WORK}/dump.sql"
      DUMP="${WORK}/dump.sql"
    fi
    ;;
  zip)
    log "format : sauvegarde Odoo (.zip)"
    need unzip unzip
    unzip -q "${SRC}" -d "${WORK}/z"
    DUMP="$(find "${WORK}/z" -maxdepth 2 -name 'dump.sql' | head -1)"
    [ -n "${DUMP}" ] || die "pas de dump.sql dans le zip"
    FILESTORE_IN="$(find "${WORK}/z" -maxdepth 2 -type d -name 'filestore' | head -1)"
    ;;
  pgcustom)
    log "format : dump binaire pg_dump -Fc (restauré via pg_restore)"
    DUMP="${SRC}"
    ;;
  sql)
    log "format : dump SQL en clair"
    DUMP="${SRC}"
    ;;
esac

# ------------------------------------------------- 3. base cible
if [ -z "${TARGET_DB}" ]; then
  TARGET_DB="${SOURCE_DB:-${DB_NAME:-}}"
fi
[ -n "${TARGET_DB}" ] || die "base cible inconnue : passez-la en 2e argument
         exemple :  /scripts/restore.sh /backups/dump.sql jed"

log "base cible : ${TARGET_DB}"

# ------------------------------------------------- 4. recréation de la base
psql -v ON_ERROR_STOP=1 -q -d postgres <<SQL
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
 WHERE datname = '${TARGET_DB}' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS "${TARGET_DB}";
CREATE DATABASE "${TARGET_DB}" TEMPLATE template0 ENCODING 'UTF8';
SQL
log "base recréée (vide)"

# ------------------------------------------------- 5. chargement du dump
if [ "${KIND}" = "pgcustom" ]; then
  pg_restore --no-owner --no-privileges --exit-on-error -d "${TARGET_DB}" "${DUMP}"
else
  # --no-psqlrc et ON_ERROR_STOP : on veut un échec franc, pas une base à moitié
  # chargée. Les dumps Odoo contiennent des ALTER OWNER inoffensifs ici, car
  # l'utilisateur qui restaure est propriétaire de la base.
  psql -v ON_ERROR_STOP=1 -q -d "${TARGET_DB}" -f "${DUMP}" >/dev/null
fi
log "dump chargé"

# ------------------------------------------------- 6. filestore
[ -n "${FILESTORE_SRC}" ] && FILESTORE_IN="${FILESTORE_SRC}"

if [ -n "${FILESTORE_IN}" ] && [ -d "${FILESTORE_IN}" ]; then
  # le dossier fourni peut être « filestore/ » (contenant <base>/) ou
  # directement le contenu d'une base.
  SUB=""
  if [ -n "${SOURCE_DB}" ] && [ -d "${FILESTORE_IN}/${SOURCE_DB}" ]; then
    SUB="${FILESTORE_IN}/${SOURCE_DB}"
  else
    first="$(find "${FILESTORE_IN}" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if [ -n "${first}" ] && [ -d "${first}" ] && \
       find "${first}" -mindepth 1 -maxdepth 1 -type d -name '??' | head -1 | grep -q .; then
      SUB="${first}"            # .../filestore/<base>/ab/...
    else
      SUB="${FILESTORE_IN}"     # déjà le contenu d'une base
    fi
  fi

  if mkdir -p "${FILESTORE_DIR}" 2>/dev/null; then
    rm -rf "${FILESTORE_DIR:?}/${TARGET_DB}"
    cp -a "${SUB}" "${FILESTORE_DIR}/${TARGET_DB}"
    log "filestore restauré dans ${FILESTORE_DIR}/${TARGET_DB}"
  else
    log "ATTENTION : ${FILESTORE_DIR} non accessible en écriture ici."
    log "            Les pièces jointes seront absentes. Relancez depuis le"
    log "            conteneur odoo :  make restore FILE=... "
  fi
else
  log "aucun filestore fourni — les pièces jointes et images seront absentes"
  log "            (passez --filestore <chemin> si vous l'avez)"
fi

# ------------------------------------------------- 7. neutralisation
#  Une base restaurée ailleurs que sur son instance d'origine ne doit PAS
#  envoyer de mails ni exécuter les crons de production.
if [ "${KEEP_AUTOMATION}" -eq 0 ] && [ "${TARGET_DB}" != "${SOURCE_DB}" ]; then
  log "neutralisation : crons et serveurs de mail sortants désactivés"
  psql -q -d "${TARGET_DB}" <<'SQL' >/dev/null 2>&1 || true
UPDATE ir_cron SET active = false;
UPDATE ir_mail_server SET active = false;
DELETE FROM ir_config_parameter WHERE key = 'database.enterprise_code';
DELETE FROM ir_config_parameter WHERE key = 'database.uuid';
SQL
  log "            (--keep pour conserver les automatismes)"
fi

# ------------------------------------------------- 8. contrôle
NB="$(psql -tAq -d "${TARGET_DB}" -c \
     "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null || echo 0)"
log "tables présentes dans ${TARGET_DB} : ${NB}"
[ "${NB}" -gt 50 ] || log "ATTENTION : très peu de tables, le dump était-il complet ?"

log "terminé — redémarrez Odoo (make restart), puis lancez une mise à jour :"
log "          make upgrade M=all   (recommandé après toute restauration)"
