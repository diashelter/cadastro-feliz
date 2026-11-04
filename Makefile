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

STACKS := laravel nest go
STACK_DIR_laravel := apis/laravel
STACK_DIR_nest := apis/nestjs
STACK_DIR_go := apis/golang

stack_file = $(STACK_DIR_$(1))/docker-compose.yml
stack_compose = $(COMPOSE) -f $(call stack_file,$(1))

# Recusa um nome desconhecido ou uma stack sem compose, antes de alterar qualquer coisa.
define require_stack
	@case " $(STACKS) " in *" $(1) "*) ;; *) echo "stack $(1) desconhecida" >&2; exit 1;; esac
	@[ -f "$(call stack_file,$(1))" ] || { echo "stack $(1) ainda não implementada" >&2; exit 1; }
endef

# Derruba uma stack que tem compose, descartando os containers e a fila dela.
define stack_down
	@if [ -f "$(call stack_file,$(1))" ]; then $(call stack_compose,$(1)) down --volumes --remove-orphans; fi

endef

.PHONY: help env network up-shared migrate down status logs-shared reset-limits test-infra

help:
	@echo "Alvos:"
	@echo "  make up-shared          sobe os serviços comuns"
	@echo "  make migrate            aplica as migrations pendentes"
	@echo "  make up-<stack>         sobe uma stack (laravel, nest, go) e derruba as outras"
	@echo "  make down-<stack>       derruba uma stack, mantendo os serviços comuns"
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
	$(SHARED) up --detach $(WAIT) postgres redis-limiter mailpit

migrate: up-shared
	$(SHARED) --profile tools run --rm migrate

up-%:
	$(call require_stack,$*)
	@$(MAKE) --no-print-directory env network
	$(foreach other,$(filter-out $*,$(STACKS)),$(call stack_down,$(other)))
	@$(MAKE) --no-print-directory migrate
	$(call stack_compose,$*) up --detach $(WAIT)

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
