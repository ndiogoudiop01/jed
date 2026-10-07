###############################################################################
#  Image du sidecar de sauvegarde.
#
#  Les scripts sont COPIÉS dans l'image plutôt que montés depuis l'hôte, pour
#  la même raison que le proxy nginx : sur Coolify/Dokploy le montage
#  « ./scripts:/scripts » pointe vers un chemin inexistant, que Docker crée en
#  dossier VIDE. Le conteneur démarre alors « normalement » puis meurt en
#  boucle sur « /scripts/backup-cron.sh: not found » — panne silencieuse, la
#  pire espèce pour des sauvegardes.
###############################################################################
ARG POSTGRES_VERSION=16
FROM postgres:${POSTGRES_VERSION}-alpine

# openssl : chiffrement AES-256 des archives  ·  tzdata : heure de Dakar
RUN apk add --no-cache openssl tzdata zip unzip

COPY . /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/bin/sh", "/scripts/backup-cron.sh"]
