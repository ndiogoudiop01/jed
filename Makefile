###############################################################################
#  Makefile client — toutes les opérations courantes en une commande.
#  Tapez simplement `make` pour voir la liste.
###############################################################################
SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE      := docker compose
DEV_FILES    := -f docker-compose.yml -f docker-compose.dev.yml
ENV_FILE     := .env

# Charge quelques variables du .env pour l'affichage et les commandes.
# On NE fait PAS `export` : docker compose lit lui-même le .env, et exporter
# ces variables ici écraserait ses valeurs (commentaires de fin de ligne inclus).
-include $(ENV_FILE)
CLIENT_SLUG      := $(strip $(CLIENT_SLUG))
ODOO_VERSION     := $(strip $(ODOO_VERSION))
DB_NAME          := $(strip $(DB_NAME))
DB_USER          := $(strip $(DB_USER))
TRAEFIK_NETWORK  := $(strip $(TRAEFIK_NETWORK))
DOMAIN           := $(strip $(DOMAIN))
HTTP_PORT        := $(strip $(HTTP_PORT))
PROXY_PORT       := $(strip $(PROXY_PORT))
PG_PORT          := $(strip $(PG_PORT))
DEBUGPY_PORT     := $(strip $(DEBUGPY_PORT))

BLUE  := \033[0;34m
GREEN := \033[0;32m
YELL  := \033[0;33m
RED   := \033[0;31m
NC    := \033[0m

## ----------------------------------------------------------------- Aide
help: ## Affiche cette aide
	@printf "$(BLUE)Client : $(GREEN)$(CLIENT_SLUG)$(NC)  |  Odoo $(GREEN)$(ODOO_VERSION)$(NC)\n\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(firstword $(MAKEFILE_LIST)) \
	 | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-18s$(NC) %s\n", $$1, $$2}'
	@printf "\n  Exemples : make dev  |  make logs  |  make upgrade M=sale  |  make backup\n\n"

## ------------------------------------------------------- Cycle de vie (prod)
up: check-env ensure-network ## Démarre la stack (mode production)
	$(COMPOSE) up -d --build
	@$(MAKE) --no-print-directory status

down: ## Arrête la stack (les données sont conservées)
	$(COMPOSE) down

restart: ## Redémarre uniquement Odoo
	$(COMPOSE) restart odoo

rebuild: ## Reconstruit l'image Odoo et redémarre
	$(COMPOSE) build --pull odoo && $(COMPOSE) up -d odoo

stop-odoo: ## Arrête Odoo seul (utile avant un restore)
	$(COMPOSE) stop odoo

## -------------------------------------------------------- Cycle de vie (dev)
dev: check-env ensure-network ## Démarre en mode développement (hot-reload + ports exposés)
	$(COMPOSE) $(DEV_FILES) up -d --build
	@printf "$(GREEN)Odoo (direct)  : $(NC)http://localhost:$(HTTP_PORT)\n"
	@printf "$(GREEN)Odoo (nginx)   : $(NC)http://localhost:$(PROXY_PORT)\n"
	@printf "$(GREEN)PostgreSQL     : $(NC)localhost:$(PG_PORT)\n"

dev-down: ## Arrête la stack de développement
	$(COMPOSE) $(DEV_FILES) down

debug: check-env ensure-network ## Démarre en dev AVEC debugpy (attend le débogueur VSCode)
	ODOO_DEBUGPY=1 ODOO_DEBUGPY_WAIT=1 $(COMPOSE) $(DEV_FILES) up -d --build
	@printf "$(YELL)Odoo attend le débogueur sur le port $(DEBUGPY_PORT) — lancez « Odoo: attach » dans VSCode$(NC)\n"

## -------------------------------------------------------------- Observation
logs: ## Suit les logs Odoo (Ctrl-C pour quitter)
	$(COMPOSE) logs -f --tail=200 odoo

logs-all: ## Suit les logs de tous les services
	$(COMPOSE) logs -f --tail=100

status: ## État des conteneurs et santé
	@$(COMPOSE) ps
	@printf "\n$(BLUE)Santé Odoo :$(NC) "
	@$(COMPOSE) exec -T odoo /usr/local/bin/odoo-healthcheck 2>/dev/null || printf "$(RED)indisponible$(NC)\n"

top: ## Consommation CPU / RAM des conteneurs
	docker stats --no-stream $$($(COMPOSE) ps -q)

## ---------------------------------------------------------------- Exploitation
shell: ## Shell bash dans le conteneur Odoo
	$(COMPOSE) exec odoo bash

odoo-shell: ## Shell Python Odoo (env, self, ...) sur la base DB
	$(COMPOSE) exec odoo odoo shell --config=/etc/odoo/odoo.conf -d $(or $(DB),$(DB_NAME)) --no-http

psql: ## Console PostgreSQL sur la base DB
	$(COMPOSE) exec db psql -U $(DB_USER) -d $(or $(DB),$(DB_NAME))

install: ## Installe un module : make install M=mon_module
	@[ -n "$(M)" ] || (printf "$(RED)Précisez M=nom_module$(NC)\n" && exit 1)
	$(COMPOSE) exec odoo odoo --config=/etc/odoo/odoo.conf \
		-d $(or $(DB),$(DB_NAME)) -i $(M) --stop-after-init --no-http
	$(MAKE) --no-print-directory restart

upgrade: ## Met à jour un module : make upgrade M=mon_module (M=all pour tout)
	@[ -n "$(M)" ] || (printf "$(RED)Précisez M=nom_module$(NC)\n" && exit 1)
	$(COMPOSE) exec odoo odoo --config=/etc/odoo/odoo.conf \
		-d $(or $(DB),$(DB_NAME)) -u $(M) --stop-after-init --no-http
	$(MAKE) --no-print-directory restart

test: ## Lance les tests d'un module : make test M=mon_module
	@[ -n "$(M)" ] || (printf "$(RED)Précisez M=nom_module$(NC)\n" && exit 1)
	$(COMPOSE) exec odoo odoo --config=/etc/odoo/odoo.conf \
		-d $(or $(DB),$(DB_NAME))_test -i $(M) --test-enable \
		--log-level=test --stop-after-init --no-http

## ----------------------------------------------------------------- Sauvegardes
backup: ## Sauvegarde immédiate (base + filestore)
	$(COMPOSE) exec -T backup /bin/sh /scripts/backup.sh $(DB)

backups: ## Liste les sauvegardes disponibles
	@$(COMPOSE) exec -T backup ls -lh /backups || true

restore: ## Restaure : make restore FILE=/backups/x.(sql|sql.gz|zip|tar.gz) [DB=base] [FS=/backups/filestore]
	@[ -n "$(FILE)" ] || (printf "$(RED)Précisez FILE=/backups/...$(NC)\n" && exit 1)
	$(MAKE) --no-print-directory stop-odoo
	$(COMPOSE) exec -T backup /bin/sh /scripts/restore.sh $(FILE) $(DB) \
	    $(if $(FS),--filestore $(FS),) $(if $(KEEP),--keep,)
	$(COMPOSE) start odoo

odoo-zip: ## Emballe un dump.sql pour le gestionnaire web : make odoo-zip FILE=/backups/dump.sql OUT=/backups/x.zip [FS=...]
	@[ -n "$(FILE)" ] && [ -n "$(OUT)" ] || \
	  (printf "$(RED)Usage : make odoo-zip FILE=/backups/dump.sql OUT=/backups/base.zip [FS=/backups/filestore]$(NC)\n" && exit 1)
	$(COMPOSE) exec -T backup /bin/sh /scripts/make-odoo-zip.sh $(FILE) $(OUT) $(ODOO_VERSION) $(FS)

backup-pull: ## Copie les sauvegardes du volume vers ./backups-local/
	@mkdir -p backups-local
	docker cp $$($(COMPOSE) ps -q backup):/backups/. backups-local/
	@printf "$(GREEN)Sauvegardes copiées dans ./backups-local/$(NC)\n"

## ------------------------------------------------------------------- Sources
submodules: ## Initialise / met à jour les dépôts OCA (submodules git)
	@git submodule update --init --recursive --depth 1 2>/dev/null || true
	@printf "$(GREEN)Submodules OCA à jour$(NC)\n"

## --------------------------------------------------------------------- Divers
check-env: ## Vérifie que le .env est présent et complet
	@[ -f $(ENV_FILE) ] || (printf "$(RED)Fichier .env manquant. Copiez .env.example et complétez-le.$(NC)\n" && exit 1)
	@for v in CLIENT_SLUG ODOO_VERSION DB_PASSWORD ODOO_MASTER_PASSWORD; do \
		grep -qE "^$$v=.+" $(ENV_FILE) || { printf "$(RED)Variable $$v absente ou vide dans .env$(NC)\n"; exit 1; }; \
	done
	@printf "$(GREEN).env valide$(NC)\n"

ensure-network: ## Crée le réseau du reverse-proxy s'il n'existe pas encore
	@docker network inspect $(or $(TRAEFIK_NETWORK),traefik) >/dev/null 2>&1 \
	 || { printf "$(YELL)création du réseau $(or $(TRAEFIK_NETWORK),traefik)$(NC)\n"; \
	      docker network create $(or $(TRAEFIK_NETWORK),traefik) >/dev/null; }

pull-base: ## Récupère la dernière image de base Odoo du registre
	@grep -E '^ODOO_BASE_IMAGE=' $(ENV_FILE) | cut -d= -f2- | sed 's/[[:space:]]*#.*$$//' | xargs docker pull

config: ## Affiche la configuration docker compose résolue (débogage)
	$(COMPOSE) config

clean: ## Supprime la stack ET SES DONNÉES (irréversible)
	@printf "$(RED)Cela supprimera la base et le filestore de $(CLIENT_SLUG). Tapez le nom du client pour confirmer : $(NC)"
	@read ans && [ "$$ans" = "$(CLIENT_SLUG)" ] || (printf "Annulé\n" && exit 1)
	$(COMPOSE) down -v

.PHONY: help up down restart rebuild stop-odoo dev dev-down debug logs logs-all \
        status top shell odoo-shell psql install upgrade test backup backups \
        restore backup-pull submodules ensure-network pull-base check-env config clean
