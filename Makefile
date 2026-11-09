# Referência: docs/infrastructure.md › Makefile.
#
# Cada stack é um nome curto ligado a um diretório; o projeto Compose dela é
# cadastro-feliz-<nome>, definido no `name:` do próprio compose. Para acrescentar
# uma stack, basta criar apis/<dir>/docker-compose.yml.

SHELL := /bin/bash
.DEFAULT_GOAL := help

NETWORK := cadastro-feliz-net
COMPOSE := docker compose --env-file .env
SHARED := $(COMPOSE) -f docker-compose.yml
WAIT := --wait --wait-timeout 180

# Os serviços de que o migrate e as stacks dependem. O frontend fica fora, para
# uma falha dele nunca impedir o migrate nem uma stack de subir.
BACKING := postgres redis-limiter mailpit

STACKS := laravel nest go
STACK_DIR_laravel := apis/laravel
STACK_DIR_nest := apis/nestjs
STACK_DIR_go := apis/golang

stack_file = $(STACK_DIR_$(1))/docker-compose.yml
stack_compose = $(COMPOSE) -f $(call stack_file,$(1))
LARAVEL := $(call stack_compose,laravel)
NEST := $(call stack_compose,nest)

# Recusa um nome desconhecido ou uma stack sem compose, antes de alterar qualquer coisa.
define require_stack
	@case " $(STACKS) " in *" $(1) "*) ;; *) echo "stack $(1) desconhecida" >&2; exit 1;; esac
	@[ -f "$(call stack_file,$(1))" ] || { echo "stack $(1) ainda não implementada" >&2; exit 1; }
endef

# Derruba uma stack que tem compose, descartando os containers e a fila dela.
define stack_down
	@if [ -f "$(call stack_file,$(1))" ]; then $(call stack_compose,$(1)) down --volumes --remove-orphans; fi

endef

.PHONY: help env network up-shared migrate watch-frontend frontend-npm test-frontend laravel-composer test-laravel nest-npm test-nest down status logs-shared reset-limits test-infra

help:
	@echo "Alvos:"
	@echo "  make up-shared          sobe os serviços comuns, o frontend incluído"
	@echo "  make migrate            aplica as migrations pendentes"
	@echo "  make watch-frontend     sincroniza as edições de frontend/src com o container"
	@echo "  make frontend-npm       roda o npm do frontend: make frontend-npm ARGS=\"install <pacote>\""
	@echo "  make test-frontend      checa os tipos e roda os testes do frontend"
	@echo "  make up-<stack>         sobe uma stack (laravel, nest, go) e derruba as outras"
	@echo "  make down-<stack>       derruba uma stack, mantendo os serviços comuns"
	@echo "  make watch-<stack>      sobe uma stack e sincroniza as edições do código com ela"
	@echo "  make laravel-composer   roda o composer da stack Laravel: make laravel-composer ARGS=\"require <pacote>\""
	@echo "  make test-laravel       roda os testes da stack Laravel"
	@echo "  make nest-npm           roda o npm da stack NestJS: make nest-npm ARGS=\"install <pacote>\""
	@echo "  make test-nest          checa os tipos e roda os testes da stack NestJS"
	@echo "  make down               derruba tudo, menos o volume do PostgreSQL"
	@echo "  make status             lista os containers do projeto"
	@echo "  make logs-shared        acompanha os logs dos serviços comuns"
	@echo "  make logs-<stack>       acompanha os logs de uma stack"
	@echo "  make reset-limits       limpa os contadores de tentativas"
	@echo "  make test-infra         testa a infraestrutura (destrói o ambiente local)"

env:
	@[ -f .env ] || cp .env.example .env

network:
	@docker network inspect $(NETWORK) >/dev/null 2>&1 || docker network create $(NETWORK) >/dev/null

up-shared: env network
	$(SHARED) up --detach $(WAIT) $(BACKING)
	$(SHARED) up --detach --build $(WAIT) frontend

migrate: env network
	$(SHARED) up --detach $(WAIT) $(BACKING)
	$(SHARED) --profile tools run --rm migrate

# Em primeiro plano. Ctrl+C encerra só a sincronização; o container continua no ar.
watch-frontend: env network
	$(SHARED) up --detach --build $(WAIT) frontend
	$(SHARED) watch --no-up frontend

# O npm roda num container descartável, com o usuário de quem chama o make, e só
# grava package.json e package-lock.json: node_modules nunca vai para a máquina.
frontend-npm:
	@[ -n "$(strip $(ARGS))" ] || { echo 'uso: make frontend-npm ARGS="<comando npm>"' >&2; exit 1; }
	@$(MAKE) --no-print-directory env network
	$(SHARED) run --rm --no-deps --user "$$(id -u):$$(id -g)" \
		--env HOME=/tmp --env npm_config_package_lock_only=true \
		--volume "$(CURDIR)/frontend:/app" frontend npm $(ARGS)

# Constrói a imagem com o código atual e roda os testes num container descartável:
# o container do frontend em execução não é recriado nem parado. A rede só existe
# durante o alvo quando ele a criou, para não deixar ambiente para trás.
test-frontend: env
	@created=0; \
	if ! docker network inspect $(NETWORK) >/dev/null 2>&1; then \
		docker network create $(NETWORK) >/dev/null && created=1; \
	fi; \
	$(SHARED) build frontend && $(SHARED) run --rm --no-deps frontend npm test; \
	status=$$?; \
	if [ $$created = 1 ]; then docker network rm $(NETWORK) >/dev/null; fi; \
	exit $$status

up-%:
	$(call require_stack,$*)
	@$(MAKE) --no-print-directory env network
	$(foreach other,$(filter-out $*,$(STACKS)),$(call stack_down,$(other)))
	@$(MAKE) --no-print-directory migrate
	$(call stack_compose,$*) up --detach --build $(WAIT)

# Em primeiro plano, depois de subir a stack como `make up-<stack>`. Ctrl+C encerra só
# a sincronização; os containers continuam no ar. `watch-frontend` tem alvo próprio.
watch-%:
	$(call require_stack,$*)
	@$(MAKE) --no-print-directory up-$*
	$(call stack_compose,$*) watch --no-up

# O composer roda num container descartável, com o usuário de quem chama o make, sobre
# uma cópia de apis/laravel: vendor e bootstrap/cache nunca vão para a máquina, e só
# composer.json e composer.lock voltam, quando o composer termina sem erro.
laravel-composer:
	@[ -n "$(strip $(ARGS))" ] || { echo 'uso: make laravel-composer ARGS="<comando composer>"' >&2; exit 1; }
	$(call require_stack,laravel)
	@$(MAKE) --no-print-directory env network
	$(LARAVEL) run --rm --no-deps --user "$$(id -u):$$(id -g)" --env HOME=/tmp composer \
		sh -c 'cp -R /src/. /tmp/app && cd /tmp/app && composer "$$@" && cp composer.json composer.lock /src/' \
		composer $(ARGS)

# Como test-frontend: constrói a imagem com o código atual e roda os testes num
# container descartável, sem dependências e sem tocar no php-fpm em execução.
test-laravel: env
	$(call require_stack,laravel)
	@created=0; \
	if ! docker network inspect $(NETWORK) >/dev/null 2>&1; then \
		docker network create $(NETWORK) >/dev/null && created=1; \
	fi; \
	$(LARAVEL) build php-fpm && $(LARAVEL) run --rm --no-deps php-fpm php artisan test; \
	status=$$?; \
	if [ $$created = 1 ]; then docker network rm $(NETWORK) >/dev/null; fi; \
	exit $$status

# Como frontend-npm: o npm roda num container descartável, sem dependências instaladas, com o
# usuário de quem chama o make, e só grava package.json e package-lock.json: node_modules
# nunca vai para a máquina.
nest-npm:
	@[ -n "$(strip $(ARGS))" ] || { echo 'uso: make nest-npm ARGS="<comando npm>"' >&2; exit 1; }
	$(call require_stack,nest)
	@$(MAKE) --no-print-directory env network
	$(NEST) run --rm --no-deps --user "$$(id -u):$$(id -g)" \
		--env HOME=/tmp --env npm_config_package_lock_only=true npm npm $(ARGS)

# Como test-laravel: constrói a imagem com o código atual e roda o type check e o Vitest num
# container descartável, sem dependências e sem tocar na api e no worker em execução.
test-nest: env
	$(call require_stack,nest)
	@created=0; \
	if ! docker network inspect $(NETWORK) >/dev/null 2>&1; then \
		docker network create $(NETWORK) >/dev/null && created=1; \
	fi; \
	$(NEST) build api && $(NEST) run --rm --no-deps api npm test; \
	status=$$?; \
	if [ $$created = 1 ]; then docker network rm $(NETWORK) >/dev/null; fi; \
	exit $$status

down-%:
	$(call require_stack,$*)
	$(call stack_compose,$*) down --volumes --remove-orphans

down: env
	$(foreach stack,$(STACKS),$(call stack_down,$(stack)))
	$(SHARED) --profile tools down --remove-orphans
	@if docker network inspect $(NETWORK) >/dev/null 2>&1; then docker network rm $(NETWORK) >/dev/null; fi

status:
	@docker ps --all --filter name=^cadastro-feliz- --format 'table {{.Names}}\t{{.State}}\t{{.Status}}\t{{.Ports}}'

logs-shared: env
	$(SHARED) logs --follow

logs-%:
	$(call require_stack,$*)
	$(call stack_compose,$*) logs --follow

reset-limits: env
	$(SHARED) exec -T redis-limiter redis-cli FLUSHALL

test-infra:
	@bash tests/infra/run.sh
