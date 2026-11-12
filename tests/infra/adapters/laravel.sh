# Adaptador da stack Laravel para os casos de contrato de tests/infra (decisão 23 de
# docs/decisions.md). Carregado por run.sh antes de registration.sh e outbox.sh, e por
# laravel-outbox.sh. Só define funções e nomes: nada roda ao ser carregado.
#
# As funções descrevem papéis, não containers. Aqui o relay é o `scheduler`, o worker é o
# `horizon` e a fila é o `redis` da stack.

RG_NG=cadastro-feliz-laravel-nginx-1
RG_FPM=cadastro-feliz-laravel-php-fpm-1
RG_HZ=cadastro-feliz-laravel-horizon-1
RG_RD=cadastro-feliz-laravel-redis-1
RG_SC=cadastro-feliz-laravel-scheduler-1

# Só as chaves da fila e as falhas do Horizon: um FLUSHALL logo depois de o horizon subir
# apaga o registro dos supervisores, e o master fica sem processar nada, ainda healthy.
stack_reset_queue() {
  docker exec "$RG_RD" redis-cli DEL queues:registration-emails queues:registration-emails:reserved \
    queues:registration-emails:delayed queues:registration-emails:notify >/dev/null
  curl -s -X DELETE --max-time 10 localhost:8080/horizon/api/jobs/failed >/dev/null
  return 0
}

stack_worker_stop() { docker stop "$RG_HZ" >/dev/null; }
stack_worker_start() { docker start "$RG_HZ" >/dev/null; rg_wait_for 90 rg_healthy "$RG_HZ"; }

stack_relay_stop() { docker stop "$RG_SC" >/dev/null; }
stack_relay_start() { docker start "$RG_SC" >/dev/null; rg_wait_for 90 rg_healthy "$RG_SC"; }

stack_queue_stop() { docker stop "$RG_RD" >/dev/null; }
# Volta quando o redis responde; o horizon e o scheduler se reconectam sozinhos.
stack_queue_start() { docker start "$RG_RD" >/dev/null; rg_wait_for 60 rg_healthy "$RG_RD"; }
stack_queue_freeze() { docker pause "$RG_RD" >/dev/null; }
stack_queue_unfreeze() { docker unpause "$RG_RD" >/dev/null; }

# Depois de make down-laravel: só a fila, vazia, sem relay nem worker.
stack_queue_up_alone() {
  (cd "$WORK" && docker compose --env-file .env -f apis/laravel/docker-compose.yml up --detach --wait redis) >/dev/null 2>&1
}

stack_queue_length() { docker exec "$RG_RD" redis-cli LLEN queues:registration-emails; }
stack_queued_messages() { docker exec "$RG_RD" redis-cli LRANGE queues:registration-emails 0 -1; }

# O próprio INFO abre uma conexão, e o healthcheck do redis abre outra a cada 5 s.
stack_queue_connections() {
  docker exec "$RG_RD" redis-cli INFO stats | tr -d '\r' | sed -n 's/^total_connections_received://p'
}

stack_jobs_created() { curl -s --max-time 10 localhost:8080/horizon/api/stats | jq -r '.recentJobs'; }
stack_failed_jobs() { curl -s --max-time 10 localhost:8080/horizon/api/jobs/failed | jq -r '.jobs | length'; }

# Publica uma mensagem na fila sem passar pelo relay.
stack_dispatch() {
  docker exec "$RG_HZ" php artisan tinker --execute "dispatch(new \\Modules\\Users\\Jobs\\SendWelcomeEmailJob('$1'));" >/dev/null
}

# As linhas de erro do log da API desde <ts>. Em duas etapas: com pipefail, um grep que
# sai antes daria SIGPIPE no docker logs.
stack_api_errors_since() {
  local logs
  logs="$(docker logs --since "$1" "$RG_FPM" 2>&1)"
  grep -F '.ERROR' <<< "$logs"
  return 0
}
stack_worker_logs_since() { docker logs --since "$1" "$RG_HZ" 2>&1; }

stack_relay_container() { echo "$RG_SC"; }

stack_lua_dir() { echo "$WORK/apis/laravel/app-modules/users/resources/lua"; }

# POST /users de dentro da rede: outro IP, o do php-fpm, chega ao mesmo nginx.
stack_post_from_other_ip() {
  docker exec -e BODY="$1" "$RG_FPM" php -r '
    $ctx = stream_context_create(["http" => ["method" => "POST", "ignore_errors" => true,
      "header" => "Content-Type: application/json\r\n", "content" => getenv("BODY")]]);
    @file_get_contents("http://nginx/users", false, $ctx);
    echo explode(" ", http_get_last_response_headers()[0])[1];'
}

# Fila, relay e worker saudáveis.
stack_wait_ready() {
  rg_wait_for 60 rg_healthy "$RG_RD" && rg_wait_for 90 rg_healthy "$RG_SC" && rg_wait_for 90 rg_healthy "$RG_HZ"
}
