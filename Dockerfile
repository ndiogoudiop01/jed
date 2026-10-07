# syntax=docker/dockerfile:1
###############################################################################
#  Image du client — couche MINCE au-dessus de l'image de base Odoo.
#
#  L'image de base (Odoo + Enterprise issus de vos dépôts privés, wkhtmltopdf,
#  dépendances Python) est construite à part, une fois par version :
#      ./base-images/build.sh 19.0 enterprise --push
#
#  Ici on n'ajoute que ce qui appartient au client : ses dépendances Python,
#  ses modules, sa configuration. Build : ~30 secondes.
###############################################################################
# Pas de valeur par défaut utilisable : ce Dockerfile n'est JAMAIS construit seul.
# Il l'est par docker-compose.yml, qui passe ODOO_BASE_IMAGE depuis le .env (ou
# depuis les variables de Coolify/Dokploy). Si vous voyez ce nom dans une erreur,
# c'est que la ressource a été créée en type « Dockerfile » au lieu de
# « Docker Compose » — voir docs/COOLIFY.md.
ARG ODOO_BASE_IMAGE=DEFINISSEZ-ODOO_BASE_IMAGE-DANS-LES-VARIABLES
FROM ${ODOO_BASE_IMAGE}

USER root

# --- Dépendances Python spécifiques à ce client ------------------------------
COPY requirements.txt /tmp/requirements.txt
RUN set -eux; \
    if [ -s /tmp/requirements.txt ] && grep -qvE '^\s*(#|$)' /tmp/requirements.txt; then \
        pip install --no-cache-dir -r /tmp/requirements.txt; \
    else \
        echo "aucune dépendance Python supplémentaire"; \
    fi; \
    rm -f /tmp/requirements.txt

# --- Code du client -----------------------------------------------------------
COPY --chown=odoo:odoo addons-custom /mnt/addons-custom
COPY --chown=odoo:odoo addons-oca    /mnt/addons-oca

# --- Configuration et scripts -------------------------------------------------
COPY config/odoo.conf.tpl   /etc/odoo/odoo.conf.tpl
COPY entrypoint.sh          /usr/local/bin/odoo-entrypoint
COPY scripts/healthcheck.sh /usr/local/bin/odoo-healthcheck

RUN set -eux; \
    chmod +x /usr/local/bin/odoo-entrypoint /usr/local/bin/odoo-healthcheck; \
    mkdir -p /var/lib/odoo /var/log/odoo /etc/odoo; \
    chown -R odoo:odoo /var/lib/odoo /var/log/odoo /etc/odoo /mnt

USER odoo

EXPOSE 8069 8072 5678

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD /usr/local/bin/odoo-healthcheck

ENTRYPOINT ["/usr/local/bin/odoo-entrypoint"]
CMD ["odoo"]
