#!/usr/bin/env bash
# Testes da infraestrutura comum contra o Docker local.
#
# Destroem e recriam o ambiente cadastro-feliz-*, por isso recusam rodar quando
# ele já existe. Cada teste imprime "PASS <id> <nome>" ou "FAIL <id> <nome>".
#
# Os testes rodam em uma cópia do repositório, em um diretório temporário, para
# não criar .env nem compose de stack na cópia de trabalho.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS="$REPO/tests/infra"

NETWORK=cadastro-feliz-net
PG_VOLUME=cadastro-feliz-shared_postgres-data
PORT_BLOCKER=cf-test-port-blocker

# Arquivos de teste, na ordem em que rodam. O CI monta a matriz a partir desta lista.
FILES=(docs.sh shared.sh migrate.sh stack.sh frontend.sh test-frontend.sh laravel.sh registration.sh outbox.sh laravel-outbox.sh nest.sh stack-switch.sh env.sh)

# Arquivos de contrato: valem para toda stack e rodam uma vez por adaptador de
# tests/infra/adapters, como a entrada <arquivo>:<stack> (decisão 23 de docs/decisions.md).
CONTRACT=(registration outbox)

# O vocabulário que todo adaptador define. Os casos de contrato só agem sobre a stack por ele.
ADAPTER_FUNCTIONS=(
  stack_reset_queue
  stack_worker_stop stack_worker_start
  stack_relay_stop stack_relay_start
  stack_queue_stop stack_queue_start stack_queue_freeze stack_queue_unfreeze stack_queue_up_alone
  stack_queue_length stack_queued_messages stack_queue_connections stack_jobs_created stack_failed_jobs
  stack_dispatch
  stack_api_errors_since stack_worker_logs_since
  stack_relay_container
  stack_post_from_other_ip
  stack_wait_ready
)

is_contract() {
  local c
  for c in "${CONTRACT[@]}"; do [ "$c" = "$1" ] && return 0; done
  return 1
}

# As stacks com adaptador, em ordem alfabética.
adapter_stacks() {
  local f
  for f in "$TESTS"/adapters/*.sh; do [ -f "$f" ] && basename "$f" .sh; done | LC_ALL=C sort
}

# Todas as entradas, na ordem de FILES: um arquivo de contrato vira uma entrada por adaptador.
all_entries() {
  local f name s
  for f in "${FILES[@]}"; do
    name="${f%.sh}"
    if is_contract "$name"; then
      for s in $(adapter_stacks); do echo "$name:$s"; done
    else
      echo "$name"
    fi
  done
}

# `--list` imprime as entradas, uma por linha, sem tocar no Docker.
if [ "${1:-}" = "--list" ]; then
  all_entries
  exit 0
fi

refuse() { echo "$*" >&2; exit 1; }

# O adaptador existe e define todo o vocabulário. Carregado num subshell, sem efeito aqui. A
# stack precisa ser exatamente um dos nomes de --list: num disco que ignora maiúsculas, como o
# do macOS, `Laravel` acharia o arquivo de `laravel`, e `../adapters/laravel` também.
check_adapter() {
  local stack="$1" missing s known=0
  for s in $(adapter_stacks); do [ "$s" = "$stack" ] && known=1; done
  [ "$known" = 1 ] || refuse "stack $stack sem adaptador em tests/infra/adapters"
  missing="$(
    # shellcheck source=/dev/null
    source "$TESTS/adapters/$stack.sh"
    for fn in "${ADAPTER_FUNCTIONS[@]}"; do
      declare -F "$fn" >/dev/null || { echo "$fn"; break; }
    done
  )"
  [ -z "$missing" ] || refuse "adaptador $stack sem $missing"
}

# Sem argumentos, todas as entradas; com argumentos, só as nomeadas, como em
# `bash tests/infra/run.sh docs registration:laravel`. Um arquivo de contrato sem a stack usa
# $STACK, e `laravel` quando ela está vazia. Tudo é conferido antes de tocar no Docker.
ENTRIES=()
if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    name="${arg%%:*}"
    [ -f "$TESTS/$name.sh" ] || refuse "arquivo de teste desconhecido: $name"
    if [ "$arg" != "$name" ]; then
      is_contract "$name" || refuse "$name não é um arquivo de contrato"
      ENTRIES+=("$arg")
    elif is_contract "$name"; then
      ENTRIES+=("$name:${STACK:-laravel}")
    else
      ENTRIES+=("$name")
    fi
  done
else
  while IFS= read -r entry; do ENTRIES+=("$entry"); done < <(all_entries)
fi
for entry in "${ENTRIES[@]}"; do
  [ "$entry" = "${entry%%:*}" ] || check_adapter "${entry#*:}"
done

FAILED=0

pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; FAILED=1; }

# check "<id> <nome>" <comando...>: roda o comando e imprime PASS ou FAIL.
check() {
  local name="$1"; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

note() { echo "  - $*" >&2; }

environment_exists() {
  [ -n "$(docker ps -aq --filter name=^cadastro-feliz-)" ] && return 0
  docker network inspect "$NETWORK" >/dev/null 2>&1 && return 0
  docker volume inspect "$PG_VOLUME" >/dev/null 2>&1 && return 0
  return 1
}

if ! docker info >/dev/null 2>&1; then
  echo "O Docker não está acessível. Inicie o daemon e rode de novo." >&2
  exit 1
fi

if environment_exists; then
  echo "Já existe um ambiente cadastro-feliz-* (containers, rede $NETWORK ou volume $PG_VOLUME)." >&2
  echo "Estes testes o destroem. Rode 'make down' e 'docker volume rm $PG_VOLUME' antes." >&2
  exit 1
fi

WORK="$(mktemp -d)"

new_workdir() {
  rm -rf "$WORK"
  mkdir -p "$WORK"
  (cd "$REPO" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | tar -xf - -C "$WORK"
  rm -f "$WORK/.env"
}

destroy_environment() {
  docker rm -f "$PORT_BLOCKER" >/dev/null 2>&1
  local ids
  ids="$(docker ps -aq --filter name=^cadastro-feliz-)"
  [ -n "$ids" ] && docker rm -f -v $ids >/dev/null 2>&1
  docker volume ls -q --filter name=^cadastro-feliz- | xargs -r docker volume rm >/dev/null 2>&1
  docker network rm "$NETWORK" >/dev/null 2>&1
  return 0
}

cleanup() {
  destroy_environment
  rm -rf "$WORK"
}
trap cleanup EXIT

# Helpers usados pelos arquivos de teste.
mk() { make --no-print-directory -C "$WORK" "$@"; }
mkq() { mk "$@" >/dev/null 2>&1; }
container() { echo "cadastro-feliz-shared-$1-1"; }
psql_q() { docker exec "$(container postgres)" psql -U cadastro_feliz -d cadastro_feliz -tAc "$1"; }
redis_q() { docker exec "$(container redis-limiter)" redis-cli "$@"; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$1" 2>/dev/null; }
project_containers() { docker ps -aq --filter "label=com.docker.compose.project=$1"; }
any_containers() { [ -n "$(docker ps -aq --filter name=^cadastro-feliz-)" ]; }
network_exists() { docker network inspect "$NETWORK" >/dev/null 2>&1; }
shared_healthy() {
  local s
  for s in postgres redis-limiter mailpit; do
    [ "$(health "$(container "$s")")" = healthy ] || { note "$s não está healthy"; return 1; }
  done
}

# Variáveis de cada projeto Compose (decisão 29). Os composes ficam em caminhos relativos a $WORK.
COMPOSES=(docker-compose.yml apis/laravel/docker-compose.yml apis/nestjs/docker-compose.yml)

# env_set <diretório> <chave=valor>...: grava os pares no .env opcional do projeto em
# $WORK/<diretório> (. para a raiz), trocando a linha da chave ou acrescentando-a.
env_set() {
  local f="$WORK/$1/.env" pair; shift
  touch "$f"
  for pair in "$@"; do
    { grep -v "^${pair%%=*}=" "$f"; echo "$pair"; } > "$f.new" && mv "$f.new" "$f" || return 1
  done
}

# env_files: os .env que existem na cópia de trabalho, um por linha.
env_files() { find "$WORK" -name .env -not -path '*/node_modules/*' -not -path '*/vendor/*'; }

# compose_env <compose> <serviço> <variável>: o valor que o Compose resolve, com o .env da pasta
# do compose, se existir.
compose_env() {
  (cd "$WORK" && docker compose -f "$1" --profile '*' config --format json 2>/dev/null) \
    | jq -r --arg s "$2" --arg v "$3" '.services[$s].environment[$v] // empty'
}

# compose_name <compose>: o projeto Compose, do `name:` do arquivo.
compose_name() { sed -nE 's/^name: *//p' "$WORK/$1"; }

# compose_defaults <compose>: uma linha <VARIÁVEL>=<padrão> por variável interpolada com padrão
# não vazio, sem repetir.
compose_defaults() {
  sed -e 's/\$\$//g' -e '/^ *#/d' "$WORK/$1" | grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*:-[^}]+\}' \
    | sed -E 's/^\$\{([A-Za-z0-9_]+):-(.*)\}$/\1=\2/' | sort -u
}

# env_missing_defaults <compose>: imprime "<compose> <VARIÁVEL>" para cada variável interpolada
# sem padrão não vazio no próprio compose. Lê o arquivo, então uma variável exportada no shell
# não esconde a falta.
env_missing_defaults() {
  local ref name
  sed -e 's/\$\$//g' -e '/^ *#/d' "$WORK/$1" \
    | grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*' | sort -u \
    | while IFS= read -r ref; do
        name="$(sed -E 's/^\$\{?([A-Za-z_][A-Za-z0-9_]*).*/\1/' <<< "$ref")"
        grep -qE '^\$\{[A-Za-z_][A-Za-z0-9_]*:-[^}]+\}$' <<< "$ref" || echo "$1 $name"
      done | sort -u
}

# Compose de uma stack falsa, usado por stack.sh e frontend.sh. Fica aqui porque
# cada arquivo também roda sozinho, como no CI. O container só fica healthy depois
# de ler a tabela users, então ele só sobe saudável se os comuns e o migrate rodaram antes.
fake_stack() {
  local name="$1" dir="$2"
  mkdir -p "$WORK/$dir"
  cat > "$WORK/$dir/docker-compose.yml" <<YAML
name: cadastro-feliz-$name

services:
  api:
    image: postgres:18.6-alpine
    entrypoint:
      - sh
      - -c
      - psql "postgresql://cadastro_feliz:cadastro_feliz@postgres:5432/cadastro_feliz" -tAc 'select count(*) from users' && touch /tmp/ready && exec sleep infinity
    healthcheck:
      test: ["CMD", "test", "-f", "/tmp/ready"]
      interval: 1s
      retries: 30
    volumes:
      - queue-data:/queue

volumes:
  queue-data:

networks:
  default:
    name: cadastro-feliz-net
    external: true
YAML
}

# Uma entrada de contrato carrega o adaptador da stack, em $SUITE_STACK, antes do arquivo.
for entry in "${ENTRIES[@]}"; do
  name="${entry%%:*}"
  new_workdir
  destroy_environment
  if [ "$entry" != "$name" ]; then
    SUITE_STACK="${entry#*:}"
    echo "== $entry"
    # shellcheck source=/dev/null
    source "$TESTS/adapters/$SUITE_STACK.sh"
  fi
  # shellcheck source=/dev/null
  source "$TESTS/$name.sh"
done

if [ "$FAILED" -ne 0 ]; then
  echo "test-infra: falhou" >&2
  exit 1
fi
echo "test-infra: todos os testes passaram"
