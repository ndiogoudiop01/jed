; ---------------------------------------------------------------------------
;  FICHIER GÉNÉRÉ AUTOMATIQUEMENT — NE PAS ÉDITER DANS LE CONTENEUR
;  Source : config/odoo.conf.tpl  +  variables du fichier .env
;  Régénéré à chaque démarrage par entrypoint.sh
; ---------------------------------------------------------------------------
[options]

; --- Sécurité ---------------------------------------------------------------
admin_passwd        = ${ODOO_MASTER_PASSWORD}
list_db             = ${LIST_DB}
dbfilter            = ${DB_FILTER}
proxy_mode          = True

; --- Base de données --------------------------------------------------------
db_host             = ${DB_HOST}
db_port             = ${DB_PORT}
db_user             = ${DB_USER}
db_password         = ${DB_PASSWORD}
db_name             = ${DB_NAME}
db_maxconn          = ${DB_MAXCONN}
db_template         = template0

; --- Chemins ----------------------------------------------------------------
addons_path         = ${ADDONS_PATH}
data_dir            = /var/lib/odoo

; --- Réseau -----------------------------------------------------------------
http_interface      = 0.0.0.0
http_port           = 8069
gevent_port         = 8072

; --- Performance ------------------------------------------------------------
workers             = ${ODOO_WORKERS}
max_cron_threads    = ${ODOO_MAX_CRON_THREADS}
limit_memory_soft   = ${LIMIT_MEMORY_SOFT}
limit_memory_hard   = ${LIMIT_MEMORY_HARD}
limit_request       = ${LIMIT_REQUEST}
limit_time_cpu      = ${LIMIT_TIME_CPU}
limit_time_real     = ${LIMIT_TIME_REAL}
limit_time_real_cron = ${LIMIT_TIME_REAL_CRON}

; --- Divers -----------------------------------------------------------------
server_wide_modules = ${SERVER_WIDE_MODULES}
without_demo        = ${WITHOUT_DEMO}
log_level           = ${ODOO_LOG_LEVEL}
log_handler         = ${ODOO_LOG_HANDLER}
logfile             = None
csv_internal_sep    = ,
