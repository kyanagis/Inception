SHELL := /bin/sh
COMPOSE := docker --host unix:///var/run/docker.sock compose --env-file srcs/.env -f srcs/docker-compose.yml
export LOGIN
.DEFAULT_GOAL := all
.NOTPARALLEL:
.PHONY: all host-setup configure preflight doctor setup config build bonus-build up bonus down stop start restart status logs check audit test bonus-test backup-now backup-list backup-verify clean fclean re help

all: up

host-setup:
	@./srcs/tools/host-setup.sh "$$LOGIN"

configure:
	@./srcs/tools/configure.sh "$$LOGIN"

preflight:
	@./srcs/tools/preflight.sh

doctor: preflight
	@printf '%s\n' 'Host prerequisites and persistent-storage contract are valid.'

setup: preflight
	@./srcs/tools/setup.sh

config:
	@$(COMPOSE) --profile bonus config --quiet

build: setup
	$(COMPOSE) build mariadb wordpress nginx

bonus-build: setup
	$(COMPOSE) --profile bonus build

up: setup
	WP_REDIS_DISABLED=1 $(COMPOSE) up --detach --build --remove-orphans --wait --wait-timeout 180
	$(COMPOSE) --profile bonus stop redis ftp static-site adminer backup

bonus: setup
	WP_REDIS_DISABLED=0 $(COMPOSE) --profile bonus up --detach --build --remove-orphans --wait --wait-timeout 180

down: preflight
	$(COMPOSE) --profile bonus down --remove-orphans

stop: preflight
	$(COMPOSE) --profile bonus stop

start restart: setup
	@set -eu; container_id=$$($(COMPOSE) ps --all --quiet wordpress); \
	 test -n "$$container_id" || { printf '%s\n' 'No existing stack; run make up or make bonus first.' >&2; exit 1; }; \
	 saved_env=$$(docker --host unix:///var/run/docker.sock inspect --format '{{json .Config.Env}}' "$$container_id"); \
	 if printf '%s' "$$saved_env" | jq -e 'index("WP_REDIS_DISABLED=0") != null' >/dev/null; then \
	   $(COMPOSE) --profile bonus $@ $(if $(filter start,$@),--wait --wait-timeout 180,); \
	 else $(COMPOSE) $@ $(if $(filter start,$@),--wait --wait-timeout 180,); fi

status: preflight
	$(COMPOSE) --profile bonus ps

logs: preflight
	$(COMPOSE) --profile bonus logs --follow --tail=100

check:
	@./srcs/tools/check.sh

audit:
	@sh ./srcs/tools/security-audit.sh

test: setup
	@./srcs/tools/check.sh
	@./srcs/tools/smoke-test.sh

bonus-test: setup
	@./srcs/tools/check.sh
	@sh ./srcs/tools/bonus-smoke-test.sh

backup-now: preflight
	$(COMPOSE) --profile bonus exec -T backup /usr/local/bin/backup-now

backup-list: preflight
	$(COMPOSE) --profile bonus exec -T backup /usr/local/bin/backup-manifest list /backups

backup-verify: preflight
	@backup=$${BACKUP:?Usage: make backup-verify BACKUP=YYYYMMDDTHHMMSSZ-XXXXXXXXXX}; \
	$(COMPOSE) --profile bonus exec -T backup /usr/local/bin/backup-manifest verify "/backups/$$backup"

clean: down

fclean: preflight
	@printf '%s\n' 'Removing project containers, images and persistent volume data.'
	$(COMPOSE) --profile bonus down --volumes --rmi all --remove-orphans

re: fclean
	$(MAKE) all

help:
	@printf '%s\n' \
	'Published OVA first use:' \
	'  inception-setup login' \
	'  inception-evaluate --prepare' \
	'' \
	'Generic dedicated Debian VM first use:' \
	'  make configure LOGIN=login' \
	'  make host-setup LOGIN=login' \
	'  make' \
	'' \
	'Mandatory: build, up, test, stop, start, restart, status, logs, down' \
	'Bonus: bonus-build, bonus, bonus-test, backup-now, backup-list, backup-verify BACKUP=<name>' \
	'Validation: check (static), audit (threat hypotheses), doctor (host), config, test / bonus-test' \
	'Destructive: fclean deletes project containers, images, and named-volume data; re rebuilds from empty state.'
