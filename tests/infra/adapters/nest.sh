# Adaptador da stack NestJS para os casos de contrato de tests/infra (decisão 23 de
# docs/decisions.md). Carregado por run.sh antes de registration.sh e outbox.sh, e por nest.sh.
# Só define funções e nomes: nada roda ao ser carregado.
#
# As funções descrevem papéis, não containers. Aqui o relay e o worker rodam no mesmo container,
# o `worker`, então parar um papel é pausar a fila dele no BullMQ: `outbox-relay` para o relay e
# `registration-emails` para o worker (door 6 de .specs/features/nestjs-stack/plan.md). A fila
# é o `redis` da stack.

RG_API=cadastro-feliz-nest-api-1
RG_WK=cadastro-feliz-nest-worker-1
RG_RD=cadastro-feliz-nest-redis-1

# As ações nomeadas do worker (src/scripts/queue-control.ts), que desistem em 15 s.
ns_queue_control() { docker exec "$RG_WK" node dist/scripts/queue-control.js "$@"; }

# Esvazia registration-emails. Não retoma nenhuma fila: como na Laravel, limpar a fila não
# religa um worker ou um relay parado pelo caso.
stack_reset_queue() {
  ns_queue_control reset >/dev/null 2>&1
  return 0
}

stack_worker_stop() { ns_queue_control pause registration-emails >/dev/null; }
stack_worker_start() { ns_queue_control resume registration-emails >/dev/null; }

stack_relay_stop() { ns_queue_control pause outbox-relay >/dev/null; }
stack_relay_start() { ns_queue_control resume outbox-relay >/dev/null; }

stack_queue_stop() { docker stop "$RG_RD" >/dev/null; }
# Volta quando o redis responde; o worker se reconecta e registra o agendador de novo sozinho.
stack_queue_start() { docker start "$RG_RD" >/dev/null; rg_wait_for 60 rg_healthy "$RG_RD"; }
stack_queue_freeze() { docker pause "$RG_RD" >/dev/null; }
stack_queue_unfreeze() { docker unpause "$RG_RD" >/dev/null; }

# Depois de make down-nest: só a fila, vazia, sem relay nem worker.
stack_queue_up_alone() {
  (cd "$WORK" && docker compose --env-file .env -f apis/nestjs/docker-compose.yml up --detach --wait redis) >/dev/null 2>&1
}

# As mensagens esperando em registration-emails: as da lista de espera e as de uma fila pausada.
# Uma lista vazia sai do redis-cli como uma linha em branco, que não é um id.
ns_waiting_ids() {
  docker exec "$RG_RD" sh -c 'redis-cli LRANGE bull:registration-emails:wait 0 -1; redis-cli LRANGE bull:registration-emails:paused 0 -1' | grep -v '^$'
  return 0
}
stack_queue_length() { ns_waiting_ids | grep -c .; }
stack_queued_messages() {
  local id
  for id in $(ns_waiting_ids); do docker exec "$RG_RD" redis-cli HGET "bull:registration-emails:$id" data; done
}

# O próprio INFO abre uma conexão, e o healthcheck do redis abre outra a cada 5 s.
stack_queue_connections() {
  docker exec "$RG_RD" redis-cli INFO stats | tr -d '\r' | sed -n 's/^total_connections_received://p'
}

# O contador de ids do BullMQ sobe a cada job criado em registration-emails.
stack_jobs_created() {
  local n
  n="$(docker exec "$RG_RD" redis-cli GET bull:registration-emails:id)"
  echo "${n:-0}"
}
stack_failed_jobs() { docker exec "$RG_RD" redis-cli ZCARD bull:registration-emails:failed; }

# Publica uma mensagem na fila sem passar pelo relay.
stack_dispatch() { ns_queue_control dispatch "$1" >/dev/null; }

# As linhas de erro do log da API desde <ts>. Em duas etapas: com pipefail, um grep que
# sai antes daria SIGPIPE no docker logs.
stack_api_errors_since() {
  local logs
  logs="$(docker logs --since "$1" "$RG_API" 2>&1)"
  grep -wF 'ERROR' <<< "$logs"
  return 0
}
stack_worker_logs_since() { docker logs --since "$1" "$RG_WK" 2>&1; }

stack_relay_container() { echo "$RG_WK"; }


# POST /users de dentro da rede: outro IP, o do worker, chega à mesma api.
stack_post_from_other_ip() {
  docker exec -e BODY="$1" "$RG_WK" node -e '
    fetch("http://api:8080/users", { method: "POST", headers: { "Content-Type": "application/json" }, body: process.env.BODY })
      .then((r) => console.log(r.status));'
}

# Fila, worker e api saudáveis.
stack_wait_ready() {
  rg_wait_for 60 rg_healthy "$RG_RD" && rg_wait_for 90 rg_healthy "$RG_WK" && rg_wait_for 90 rg_healthy "$RG_API"
}
