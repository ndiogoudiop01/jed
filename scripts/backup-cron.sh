#!/bin/sh
###############################################################################
#  Sidecar de sauvegarde : dort jusqu'à BACKUP_HOUR puis lance backup.sh.
#  Pas de crond à configurer, pas de cron sur l'hôte : tout est dans la stack.
###############################################################################
set -eu

log() { printf '[backup-cron] %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

BACKUP_ENABLED="${BACKUP_ENABLED:-true}"
BACKUP_HOUR="${BACKUP_HOUR:-2}"

if [ "${BACKUP_ENABLED}" != "true" ]; then
  log "sauvegardes désactivées (BACKUP_ENABLED=${BACKUP_ENABLED}) — le conteneur reste inactif"
  while true; do sleep 3600; done
fi

log "sauvegarde quotidienne planifiée à ${BACKUP_HOUR}h00 (${TZ:-UTC})"

while true; do
  now_h=$(date '+%-H')
  now_m=$(date '+%-M')
  now_s=$(date '+%-S')

  target=$(( BACKUP_HOUR * 3600 ))
  current=$(( now_h * 3600 + now_m * 60 + now_s ))
  delta=$(( target - current ))
  [ "${delta}" -le 0 ] && delta=$(( delta + 86400 ))

  log "prochaine sauvegarde dans ${delta}s"
  sleep "${delta}"

  log "démarrage de la sauvegarde"
  if /bin/sh /scripts/backup.sh; then
    log "sauvegarde terminée avec succès"
  else
    log "ÉCHEC de la sauvegarde (code $?)"
  fi
  sleep 60   # évite un double déclenchement dans la même minute
done
