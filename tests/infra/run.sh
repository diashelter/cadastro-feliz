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

for f in docs.sh shared.sh migrate.sh stack.sh; do
  [ -f "$TESTS/$f" ] || continue
  new_workdir
  destroy_environment
  # shellcheck source=/dev/null
  source "$TESTS/$f"
done

if [ "$FAILED" -ne 0 ]; then
  echo "test-infra: falhou" >&2
  exit 1
fi
echo "test-infra: todos os testes passaram"
