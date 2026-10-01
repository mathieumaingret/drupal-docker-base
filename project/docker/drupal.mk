#
# Managed by docker-base — overwritten by `make docker-update`, do not edit.
# Included by the project Makefile; project targets live there.
#

# --- Configuration -----------------------------------------------------------
# Recipes rely on bash (read -p, arrays); /bin/sh is dash on Debian/Ubuntu.
SHELL := /bin/bash

DOCKER_BASE_REPO ?= mathieumaingret/drupal-docker-base

# base.yml is managed by docker-base, project.yml is committed by the project,
# local.yml is git-ignored for per-developer tweaks (extra ports, volumes…).
COMPOSE_FILES = docker/compose/base.yml \
                $(wildcard docker/compose/project.yml) \
                $(wildcard docker/compose/local.yml)

# --project-directory . keeps paths and the root .env resolvable from any CWD.
COMPOSE ?= docker compose
DC = $(COMPOSE) --project-directory . $(addprefix -f ,$(COMPOSE_FILES))

PHP  = app
NODE = node

EXEC_PHP  = $(DC) exec --user www-data $(PHP)
EXEC_NODE = $(DC) exec $(NODE)
COMPOSER  = $(EXEC_PHP) composer
DRUSH     = $(EXEC_PHP) vendor/bin/drush

env = $(shell grep -E '^$(1)=' .env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '\r"'"'")

COMPOSE_PROJECT_NAME := $(call env,COMPOSE_PROJECT_NAME)
APP_DIR              := $(or $(call env,APP_DIR),.)
# Paths below are inside the container (project root = /var/www/html).
DUMP_DIR              = _dumps
SITE                  = default
TRAEFIK_NETWORK       = traefik-public

# Capture positional arguments, e.g. `make en module_a module_b`.
ARG  := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
FILE := $(word 2,$(MAKECMDGOALS))

SED_INPLACE = sed -i$(if $(filter Darwin,$(shell uname)), '',)

# Set KEY=VALUE in .env, appending the line when the key is missing.
set_env = if grep -qE '^$(1)=' .env; then $(SED_INPLACE) "s|^$(1)=.*|$(1)=$(2)|" .env; else echo "$(1)=$(2)" >> .env; fi

.DEFAULT_GOAL := help

.PHONY: help check up down restart destroy logs logs-app ps urls \
        shell shell-root shell-node init install pull docker-update \
        drush cr cex cim cst updb update locale uli en pmu site-install dep \
        composer \
        db-export db-import db-port \
        xdebug-on xdebug-off \
        npm \
        phpcs phpcbf phpstan

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} \
		/^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next} \
		/^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""

##@ Container Management

check: ## Check the prerequisites (.env, shared Traefik network)
	@test -f .env || { echo "Missing .env — run 'make init' first."; exit 1; }
	@docker network inspect $(TRAEFIK_NETWORK) >/dev/null 2>&1 || { \
		echo "Docker network '$(TRAEFIK_NETWORK)' not found: start the shared Traefik proxy first"; \
		echo "(or create the network: docker network create $(TRAEFIK_NETWORK))."; exit 1; }
	@SOCK="$(or $(call env,SSH_AUTH_SOCK_HOST),/run/host-services/ssh-auth.sock)"; \
	if [ "$$(uname)" != "Darwin" ] && [ ! -S "$$SOCK" ]; then \
		echo "SSH agent socket '$$SOCK' not found: set SSH_AUTH_SOCK_HOST in .env to your \$$SSH_AUTH_SOCK path."; exit 1; \
	fi

up: check ## Start the containers
	$(DC) up -d --wait
	@$(MAKE) --no-print-directory urls

down: ## Stop the containers
	$(DC) down

restart: ## Restart the containers
	$(DC) restart

pull: check ## Pull the latest images (docker-base patches) and restart
	$(DC) pull
	$(DC) up -d --wait

destroy: ## Stop the containers and DELETE the volumes (DB, Redis, Composer cache)
	@read -p "This deletes the database of $(COMPOSE_PROJECT_NAME). Continue? [y/N] " answer; \
	[ "$$answer" = "y" ] || { echo "Aborted."; exit 1; }
	$(DC) down -v --remove-orphans

logs: ## Tail the logs of all services
	$(DC) logs -f

logs-app: ## Tail the logs of the app container (Apache + PHP)
	$(DC) logs -f $(PHP)

ps: ## List the running containers
	$(DC) ps

urls: ## Print the project URLs
	@echo ""
	@echo "  Application:  https://$(COMPOSE_PROJECT_NAME).dev.localhost"
	@echo "  Mailpit:      https://$(COMPOSE_PROJECT_NAME)-mailpit.dev.localhost"
	@echo "  Adminer:      https://$(COMPOSE_PROJECT_NAME)-adminer.dev.localhost  (profile 'tools')"
	@echo ""

shell: ## Open a bash shell in the app container (as www-data)
	$(EXEC_PHP) bash

shell-root: ## Open a bash shell in the app container (as root)
	$(DC) exec $(PHP) bash

shell-node: ## Open a shell in the Node container
	$(EXEC_NODE) sh

##@ Installation & Setup

init: ## Full project initialisation (first run)
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		HASH_SALT=$$(openssl rand -base64 55 | tr -d '\n=+/'); \
		$(SED_INPLACE) \
			-e "s|^HASH_SALT=.*|HASH_SALT=$$HASH_SALT|" \
			-e "s|^USER_ID=.*|USER_ID=$$(id -u)|" \
			-e "s|^GROUP_ID=.*|GROUP_ID=$$(id -g)|" .env; \
		echo ".env created (HASH_SALT, USER_ID, GROUP_ID filled in)."; \
		echo "Review COMPOSE_PROJECT_NAME and MYSQL_PREFIX, then run 'make init' again."; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory check
	$(DC) up -d --wait
	@$(MAKE) --no-print-directory install
	@echo ""
	@echo "=== Project initialized ==="
	@echo "Next steps: make db-import <dump.sql[.gz]> && make update"
	@$(MAKE) --no-print-directory urls

# Double-colon rule: the project Makefile adds its own steps (npm install…)
# with another `install::` rule, without overriding this one.
install:: ## Install the dependencies (Composer, plus the project's own steps)
	$(COMPOSER) install

docker-update: ## Update the docker-base managed files and images (usage: make docker-update [v=1.3.0])
	curl -fsSL "https://raw.githubusercontent.com/$(DOCKER_BASE_REPO)/$(if $(v),v$(v),main)/install.sh" | bash -s -- $(v)
	@echo "Review the changes (git diff), then run 'make pull'."

##@ Drupal

drush: ## Run a Drush command (usage: make drush status, or make drush c='cr')
	$(DRUSH) $(or $(c),$(ARG))

cr: ## Clear Drupal caches
	$(DRUSH) cr

cex: ## Export configuration
	$(DRUSH) cex --yes

cst: ## Show the configuration status (DB vs config/sync)
	$(DRUSH) config:status

cim: ## Import configuration
	$(DRUSH) cim --yes
	$(DRUSH) cr

updb: ## Run database updates
	$(DRUSH) updb --yes

update: ## Update the local site after a pull (composer install, drush deploy, translations)
	$(COMPOSER) install
	$(DRUSH) deploy --yes
	@$(MAKE) --no-print-directory locale

locale: ## Check and import the interface translations
	$(DRUSH) locale:check
	$(DRUSH) locale:update
	$(DRUSH) cr

uli: ## Generate a one-time login link (usage: make uli uid=1)
	$(DRUSH) user:login --uid=$(or $(uid),1)

en: ## Enable modules (usage: make en module_a module_b)
	$(DRUSH) pm:install --yes $(ARG)

pmu: ## Uninstall modules (usage: make pmu module_a module_b)
	$(DRUSH) pm:uninstall --yes $(ARG)

site-install: ## Install a fresh site (usage: make site-install [profile=standard] [existing=1] to install from config/sync)
	$(DRUSH) site:install $(or $(profile),standard) $(if $(existing),--existing-config) --yes

dep: ## Run Deployer with the host SSH agent (usage: make dep deploy stage=draft)
	$(EXEC_PHP) vendor/bin/dep $(ARG) $(if $(stage),stage=$(stage))

##@ Composer

composer: ## Run a Composer command (usage: make composer require drupal/foo)
	$(COMPOSER) $(or $(c),$(ARG))

##@ Database

db-export: ## Export the database to $(DUMP_DIR)/
	$(EXEC_PHP) bash -c "mkdir -p $(DUMP_DIR) && vendor/bin/drush sql-dump --gzip > $(DUMP_DIR)/dump-$$(date +%Y%m%d-%H%M%S).sql.gz"
	@echo "Database exported to $(APP_DIR)/$(DUMP_DIR)/"

db-import: ## Import a SQL dump, replacing the current DB (usage: make db-import dump.sql[.gz])
	@FILE="$(FILE)"; \
	if [ -z "$$FILE" ]; then echo "Usage: make db-import <dump.sql[.gz]>"; exit 1; fi; \
	if [ ! -f "$$FILE" ]; then echo "Error: file not found: $$FILE"; exit 1; fi; \
	echo "Dropping existing tables..."; \
	$(DRUSH) sql-drop --yes; \
	echo "Importing $$FILE..."; \
	case "$$FILE" in \
		*.gz) gunzip -c "$$FILE" | $(DC) exec -T --user www-data $(PHP) vendor/bin/drush sql-cli ;; \
		*)    $(DC) exec -T --user www-data $(PHP) vendor/bin/drush sql-cli < "$$FILE" ;; \
	esac; \
	$(DRUSH) cr; \
	echo "Database import completed."

db-port: ## Show the host port to reach MariaDB from a local client
	@$(DC) port db 3306

##@ Debug

xdebug-on: ## Enable Xdebug (mode debug, triggered by the browser extension)
	@$(call set_env,XDEBUG_MODE,debug)
	$(DC) up -d --wait $(PHP)
	@echo "Xdebug enabled — PhpStorm server name: $(COMPOSE_PROJECT_NAME)"

xdebug-off: ## Disable Xdebug
	@$(call set_env,XDEBUG_MODE,off)
	$(DC) up -d --wait $(PHP)

##@ Frontend

# Frontend workflows (theme build, dev server…) are project-specific: define
# them in the project Makefile, using $(EXEC_NODE).
npm: ## Run an npm command from the project root (usage: make npm run build)
	$(EXEC_NODE) npm $(or $(c),$(ARG))

##@ Quality & Tools

phpcs: ## Run PHP CodeSniffer
	$(EXEC_PHP) vendor/bin/phpcs $(ARG)

phpcbf: ## Run PHP Code Beautifier and Fixer
	$(EXEC_PHP) vendor/bin/phpcbf $(ARG)

phpstan: ## Run PHPStan static analysis
	$(EXEC_PHP) vendor/bin/phpstan $(ARG)

# Lets positional arguments (e.g. `make en foo bar`) through without Make
# treating them as targets. Must stay at the end and out of .PHONY.
$(ARG):
	@:
