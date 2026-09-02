SHELL := /bin/sh

COMPOSE := docker compose --env-file srcs/.env -f srcs/docker-compose.yml

.DEFAULT_GOAL := all

.PHONY: all setup configure build up bonus down stop start restart status logs check clean fclean re

all: up

setup:
	@./scripts/setup.sh

configure:
	@test -n "$(LOGIN)" || { echo "Usage: make configure LOGIN=<42-login>" >&2; exit 2; }
	@./scripts/configure.sh "$(LOGIN)"

build: setup
	$(COMPOSE) build

up: setup
	$(COMPOSE) up --detach --build --remove-orphans --wait --wait-timeout 180
	$(COMPOSE) exec -T --user www-data wordpress wp redis disable --path=/var/www/html >/dev/null 2>&1 || true
	$(COMPOSE) --profile bonus stop redis ftp static-site adminer backup

bonus: setup
	$(COMPOSE) --profile bonus up --detach --build --remove-orphans --wait --wait-timeout 180
	$(COMPOSE) exec -T --user www-data wordpress wp plugin activate redis-cache --path=/var/www/html
	$(COMPOSE) exec -T --user www-data wordpress wp redis enable --path=/var/www/html

down:
	@$(COMPOSE) exec -T --user www-data wordpress wp redis disable --path=/var/www/html >/dev/null 2>&1 || true
	$(COMPOSE) --profile bonus down --remove-orphans

stop:
	$(COMPOSE) --profile bonus stop

start:
	$(COMPOSE) --profile bonus start

restart:
	$(COMPOSE) --profile bonus restart

status:
	$(COMPOSE) --profile bonus ps

logs:
	$(COMPOSE) --profile bonus logs --follow --tail=100

check:
	@./scripts/check.sh

clean: down
	@docker image prune --force --filter 'label=com.docker.compose.project=inception'

fclean:
	@$(COMPOSE) exec -T --user www-data wordpress wp redis disable --path=/var/www/html >/dev/null 2>&1 || true
	$(COMPOSE) --profile bonus down --volumes --rmi all --remove-orphans

re: fclean all
