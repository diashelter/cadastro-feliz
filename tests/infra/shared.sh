# S1 - Serviços comuns saudáveis. Carregado por run.sh.

t_c9_env_example() {
  # Lê as tabelas de docs/infrastructure.md › Variáveis de ambiente.
  local docs="$WORK/docs/infrastructure.md" example="$WORK/.env.example"
  local expected
  expected="$(awk '/^## Variáveis de ambiente/{on=1; next} /^## /{on=0} on' "$docs" \
    | sed -nE 's/^\| `([A-Z_]+)` \| `([^`]*)` \|.*/\1=\2/p')"
  local count
  count="$(printf '%s\n' "$expected" | grep -c .)"
  [ "$count" -eq 26 ] || { note "docs listam $count variáveis, esperado 26"; return 1; }
  local line ok=0
  while IFS= read -r line; do
    grep -qxF "$line" "$example" || { note "falta em .env.example: $line"; ok=1; }
  done <<< "$expected"
  return $ok
}
check "C9 env example matches docs" t_c9_env_example

t_c1_clean_clone() {
  [ ! -e "$WORK/.env" ] || return 1
  network_exists && return 1
  mkq up-shared || { note "make up-shared saiu com erro"; return 1; }
  cmp -s "$WORK/.env" "$WORK/.env.example" || { note ".env difere de .env.example"; return 1; }
  network_exists || { note "rede ausente"; return 1; }
  shared_healthy
}
check "C1 up-shared clean clone" t_c1_clean_clone

t_c7_images() {
  local got expected
  got="$(cd "$WORK" && docker compose --profile '*' config --images | sort)"
  expected="$(printf '%s\n' axllent/mailpit:v1.33.0 cadastro-feliz-shared-frontend migrate/migrate:v4.20.1 postgres:18.6-alpine redis:8.10.3-alpine | sort)"
  [ "$got" = "$expected" ] || { note "imagens: $(echo $got)"; return 1; }
}
check "C7 pinned images" t_c7_images

t_c3_rerun() {
  local before after
  before="$(project_containers cadastro-feliz-shared | sort)"
  [ "$(echo "$before" | grep -c .)" -eq 4 ] || { note "esperava 4 containers: $before"; return 1; }
  mk up-shared >/dev/null 2>&1 || return 1
  after="$(project_containers cadastro-feliz-shared | sort)"
  [ "$before" = "$after" ]
}
check "C3 up-shared rerun keeps containers" t_c3_rerun

t_c4_login() {
  docker run --rm --network host postgres:18.6-alpine \
    psql "postgresql://cadastro_feliz:cadastro_feliz@localhost:5432/cadastro_feliz" -tAc 'select 1' 2>/dev/null \
    | grep -qx 1
}
check "C4 postgres login from host" t_c4_login

t_c5_ports() {
  local ports
  ports="$(for id in $(project_containers cadastro-feliz-shared); do
    docker inspect -f '{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{.HostPort}}{{"\n"}}{{end}}{{end}}' "$id"
  done | grep . | sort -u | paste -sd,)"
  [ "$ports" = "3000,5432,8025" ] || { note "portas publicadas: $ports"; return 1; }
  docker run --rm --network "$NETWORK" redis:8.10.3-alpine redis-cli -h redis-limiter -p 6379 ping 2>/dev/null \
    | grep -qx PONG || { note "redis-limiter:6379 não respondeu na rede"; return 1; }
  docker run --rm --network "$NETWORK" redis:8.10.3-alpine nc -z -w 3 mailpit 1025 \
    || { note "mailpit:1025 não respondeu na rede"; return 1; }
}
check "C5 published ports and network ports" t_c5_ports

t_c6_redis_config() {
  [ "$(redis_q CONFIG GET maxmemory | sed -n 2p)" = 33554432 ] || return 1
  [ "$(redis_q CONFIG GET maxmemory-policy | sed -n 2p)" = volatile-ttl ] || return 1
  [ "$(redis_q CONFIG GET save | sed -n 2p)" = "" ] || return 1
  [ "$(redis_q CONFIG GET appendonly | sed -n 2p)" = no ] || return 1
}
check "C6 redis-limiter config" t_c6_redis_config

t_c25_logs() {
  # O alvo acompanha os logs sem sair; o timeout o encerra.
  local out rc
  out="$(timeout 15 make --no-print-directory -C "$WORK" logs-shared 2>&1)"
  rc=$?
  [ "$rc" -eq 124 ] || { note "logs-shared saiu sozinho (rc=$rc), sem acompanhar"; return 1; }
  grep -q 'database system is ready to accept connections' <<< "$out"
}
check "C25 logs-shared follows logs" t_c25_logs

t_c24_status() {
  local out s
  out="$(mk status 2>&1)" || return 1
  for s in postgres redis-limiter mailpit; do
    echo "$out" | grep -E "$(container "$s").*running" >/dev/null || { note "status sem $s running"; return 1; }
  done
}
check "C24 status lists containers" t_c24_status

t_c23_reset_limits() {
  redis_q SET registration:attempts:abc 1 EX 900 >/dev/null || return 1
  [ "$(redis_q EXISTS registration:attempts:abc)" = 1 ] || return 1
  mk reset-limits >/dev/null 2>&1 || return 1
  [ "$(redis_q DBSIZE)" = 0 ]
}
check "C23 reset-limits empties limiter" t_c23_reset_limits

t_c2_keeps_env() {
  sed -i 's/^DB_PASSWORD=.*/DB_PASSWORD=outra/' "$WORK/.env"
  local before="$WORK/.env.before"
  cp "$WORK/.env" "$before"
  mk up-shared >/dev/null 2>&1 || return 1
  grep -qx 'DB_PASSWORD=outra' "$WORK/.env" || return 1
  cmp -s "$before" "$WORK/.env" || { note ".env mudou"; return 1; }
}
check "C2 up-shared keeps existing env" t_c2_keeps_env

t_c8_taken_port() {
  local port="$1" rc
  destroy_environment
  rm -f "$WORK/.env"
  docker run -d --name "$PORT_BLOCKER" -p "$port:6379" redis:8.10.3-alpine >/dev/null || return 1
  mk up-shared >/dev/null 2>&1
  rc=$?
  destroy_environment
  [ "$rc" -ne 0 ]
}
check "C8 up-shared fails on taken port 8025" t_c8_taken_port 8025
check "C8 up-shared fails on taken port 5432" t_c8_taken_port 5432
check "C8 up-shared fails on taken port 3000" t_c8_taken_port 3000
