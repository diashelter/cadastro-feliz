# Casos internos da stack Laravel (decisão 23): o redis da fila, o painel e as falhas do
# Horizon, o scheduler, o comando outbox:relay, a configuração e a estrutura dos módulos.
# Os casos de contrato, que valem para toda stack, ficam em registration.sh e outbox.sh.
# Carregado por run.sh. Roda contra PostgreSQL, Redis, Horizon e Mailpit de verdade.

SUITE_STACK=laravel
# shellcheck source=/dev/null
source "$TESTS/adapters/laravel.sh"
# shellcheck source=/dev/null
source "$TESTS/registration-helpers.sh"

OB_LV="$WORK/apis/laravel"
OB_PG="$(container postgres)"

# Depois de parar o scheduler e o horizon, os dois voltam mesmo que o teste falhe.
ob_start_workers() {
  docker start "$RG_SC" "$RG_HZ" >/dev/null
  rg_wait_for 90 rg_healthy "$RG_SC"
  rg_wait_for 90 rg_healthy "$RG_HZ"
}

ob_relay() { docker exec "$RG_FPM" php artisan outbox:relay 2>&1; }

t_lo0_up() {
  mkq up-laravel || { note "make up-laravel saiu com erro"; return 1; }
}
check "LO0 stack up for the laravel internal tests" t_lo0_up

# --- Horizon e a fila ---

t_rg22_queue_redis() {
  local ok=0
  [ "$(docker inspect -f '{{.Config.Image}}' "$RG_RD")" = redis:8.10.3-alpine ] || { note "imagem do redis"; ok=1; }
  [ "$(docker exec "$RG_RD" redis-cli CONFIG GET maxmemory-policy | tail -1)" = noeviction ] || { note "maxmemory-policy"; ok=1; }
  [ -z "$(docker exec "$RG_RD" redis-cli CONFIG GET save | tail -1)" ] || { note "save não está vazio"; ok=1; }
  [ "$(docker exec "$RG_RD" redis-cli CONFIG GET appendonly | tail -1)" = no ] || { note "appendonly"; ok=1; }
  return $ok
}
check "RG22 queue redis config" t_rg22_queue_redis

t_rg24_retries() {
  local ok=0
  rg_with_queued_job
  [ "$(jq -r '.maxTries' <<< "$QUEUED")" = 1 ] || { note "maxTries: $(jq -r '.maxTries' <<< "$QUEUED")"; ok=1; }
  [ "$(jq -r '.backoff' <<< "$QUEUED")" = null ] || { note "backoff: $(jq -r '.backoff' <<< "$QUEUED")"; ok=1; }
  return $ok
}
check "RG24 job has no native retries" t_rg24_retries

t_rg27_watch_updates_worker() {
  local before i started ok=0 view="$WORK/apis/laravel/app-modules/outbox/resources/views/welcome-text.blade.php" saved found=1 pid
  saved="$(cat "$view")"
  rg_reset
  before="$(docker ps -aq --no-trunc --filter "name=^$RG_FPM\$")"
  set -m
  make --no-print-directory -C "$WORK" watch-laravel > "$WORK/watch.log" 2>&1 &
  pid=$!
  set +m
  rg_wait_for 300 grep -q 'Watch enabled' "$WORK/watch.log" || { note "watch não ficou pronto: $(tail -3 "$WORK/watch.log")"; ok=1; }
  printf 'Texto novo vindo do watch.\n' >> "$view"
  started=$SECONDS
  i=0
  while [ $((SECONDS - started)) -le 60 ]; do
    i=$((i + 1))
    sleep 5
    rg_register "w$i@example.com" >/dev/null
    rg_wait_for 8 rg_mail_arrived "w$i@example.com" \
      && grep -qF 'Texto novo vindo do watch.' <<< "$(rg_mail_field "w$i@example.com" '.Text')" && { found=0; break; }
  done
  [ "$found" = 0 ] && [ $((SECONDS - started)) -le 60 ] || { note "texto novo não saiu em 60 s: $((SECONDS - started)) s"; ok=1; }
  [ "$(docker ps -aq --no-trunc --filter "name=^$RG_FPM\$")" = "$before" ] || { note "php-fpm mudou"; ok=1; }
  kill -INT -- "-$pid" 2>/dev/null
  rg_wait_for 30 bash -c "! kill -0 $pid 2>/dev/null"
  printf '%s\n' "$saved" > "$view"
  mkq up-laravel
  return $ok
}
check "RG27 watch updates the worker" t_rg27_watch_updates_worker

t_rg28_horizon_panel() {
  local headers ok=0
  headers="$(curl -s -D - -o "$WORK/horizon.html" --max-time 10 localhost:8080/horizon | tr -d '\r')"
  grep -qE '^HTTP/[0-9.]+ 200' <<< "$headers" || { note "status: $(head -1 <<< "$headers")"; ok=1; }
  grep -qiE '^content-type: text/html' <<< "$headers" || { note "sem Content-Type HTML"; ok=1; }
  grep -qE '(src|href)="/' "$WORK/horizon.html" && { note "painel depende de arquivo estático"; ok=1; }
  rg_stats_running() { [ "$(curl -s --max-time 10 localhost:8080/horizon/api/stats | jq -r '.status')" = running ]; }
  rg_wait_for 30 rg_stats_running || { note "stats: $(curl -s localhost:8080/horizon/api/stats)"; ok=1; }
  return $ok
}
check "RG28 horizon panel answers" t_rg28_horizon_panel

# --- Outbox: estrutura, scheduler e relay ---

t_ob9_publisher_gone() {
  [ ! -e "$OB_LV/app-modules/users/src/Services/WelcomeEmailPublisher.php" ] || { note "o arquivo existe"; return 1; }
  if grep -rqF WelcomeEmailPublisher "$OB_LV/app-modules" "$OB_LV/app" "$OB_LV/config" "$OB_LV/routes"; then
    note "ainda há referência a WelcomeEmailPublisher"; return 1
  fi
}
check "OB9 publisher class is gone" t_ob9_publisher_gone

t_ob11_one_way() {
  [ -d "$OB_LV/app-modules/outbox/src" ] || { note "sem o módulo outbox"; return 1; }
  if grep -rqE 'Modules\\+Users' "$OB_LV/app-modules/outbox"; then
    note "outbox referencia Modules\\Users"; return 1
  fi
}
check "OB11 outbox module does not reference users" t_ob11_one_way

t_ob13_scheduler() {
  local ok=0 list
  [ "$(docker inspect -f '{{.Config.Image}}' "$RG_SC")" = cadastro-feliz-laravel-php-fpm ] || { note "imagem do scheduler"; ok=1; }
  [ -z "$(docker port "$RG_SC")" ] || { note "scheduler publica: $(docker port "$RG_SC")"; ok=1; }
  list="$(docker exec "$RG_SC" php artisan schedule:list --no-ansi)"
  grep -F 'outbox:relay' <<< "$list" | grep -qF '* * * * * 1s' || { note "schedule:list: $list"; ok=1; }
  return $ok
}
check "OB13 scheduler image and schedule list" t_ob13_scheduler

t_ob14_config() {
  local ok=0 out pair
  out="$(docker exec "$RG_SC" php artisan config:show outbox --no-ansi)"
  for pair in 'batch_size 100' 'republish_after 300' 'max_attempts 5' 'backoff_base 30'; do
    grep -qE "^ *${pair% *} \.+ ${pair#* } *\$" <<< "$out" || { note "sem $pair: $out"; ok=1; }
  done
  return $ok
}
check "OB14 outbox config defaults in the scheduler" t_ob14_config

t_ob19_batch() {
  local ok=0 out
  rg_set_env OUTBOX_BATCH_SIZE=2 || { note "make up-laravel saiu com erro"; return 1; }
  docker stop "$RG_SC" "$RG_HZ" >/dev/null
  rg_reset
  ob_seed novo@example.com pending '' 0 10 >/dev/null
  ob_seed velho@example.com pending '' 0 30 >/dev/null
  ob_seed medio@example.com pending '' 0 20 >/dev/null
  out="$(ob_relay)" || { note "saiu com erro: $out"; ok=1; }
  [ "$out" = '2 event(s) published.' ] || { note "saída: $out"; ok=1; }
  rg_event_is published velho@example.com || { note "velho: $(rg_event status velho@example.com)"; ok=1; }
  rg_event_is published medio@example.com || { note "medio: $(rg_event status medio@example.com)"; ok=1; }
  rg_event_is pending novo@example.com || { note "novo: $(rg_event status novo@example.com)"; ok=1; }
  rg_reset
  out="$(ob_relay)" || { note "vazio saiu com erro: $out"; ok=1; }
  [ "$out" = '0 event(s) published.' ] || { note "saída sem eventos: $out"; ok=1; }
  rg_default_env
  return $ok
}
check "OB19 relay batch output and order" t_ob19_batch

t_ob20_skip_locked() {
  local ok=0 locked free out started elapsed pid
  docker stop "$RG_SC" "$RG_HZ" >/dev/null
  rg_reset
  locked="$(ob_seed travado@example.com pending '' 0 30)"
  free="$(ob_seed livre@example.com)"
  docker exec "$OB_PG" psql -U cadastro_feliz -d cadastro_feliz -c \
    "begin; select id from users_outbox where id = '$locked' for update; select pg_sleep(8); commit;" >/dev/null 2>&1 &
  pid=$!
  sleep 1
  started="$(date +%s)"
  out="$(ob_relay)" || { note "saiu com erro: $out"; ok=1; }
  elapsed="$(($(date +%s) - started))"
  [ "$out" = '1 event(s) published.' ] || { note "saída: $out"; ok=1; }
  [ "$elapsed" -lt 5 ] || { note "esperou a trava: ${elapsed}s"; ok=1; }
  [ "$(psql_q "select status from users_outbox where id = '$free'")" = published ] || { note "livre não publicado"; ok=1; }
  wait "$pid"
  [ "$(psql_q "select status from users_outbox where id = '$locked'")" = pending ] || { note "travado publicado"; ok=1; }
  ob_start_workers
  return $ok
}
check "OB20 relay skips locked rows" t_ob20_skip_locked

t_ob21_failure() {
  local ok=0 since rc logged
  rg_reset
  docker stop "$RG_HZ" "$RG_RD" >/dev/null
  since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ob_seed ana@example.com >/dev/null
  docker exec "$RG_SC" php artisan outbox:relay >/dev/null 2>&1
  rc=$?
  [ "$rc" = 1 ] || { note "saída do comando: $rc"; ok=1; }
  # Em duas etapas: com pipefail, o grep -q que sai antes daria SIGPIPE no docker logs.
  ob_logged() { local logs; logs="$(docker logs --since "$since" "$RG_SC" 2>&1)"; grep -qF 'outbox relay failed' <<< "$logs"; }
  rg_wait_for 20 ob_logged || { note "docker logs do scheduler sem a falha: $(docker logs --since "$since" "$RG_SC" 2>&1 | tail -5)"; ok=1; }
  [ "$(rg_event status ana@example.com)" = pending ] || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  [ "$(rg_event 'published_at is null' ana@example.com)" = t ] || { note "published_at preenchido"; ok=1; }
  sleep 6
  rg_healthy "$RG_SC" || { note "scheduler: $(health "$RG_SC")"; ok=1; }
  docker start "$RG_RD" "$RG_HZ" >/dev/null
  rg_wait_for 60 rg_healthy "$RG_RD"
  rg_wait_for 90 rg_healthy "$RG_HZ"
  return $ok
}
check "OB21 relay failure keeps events and logs" t_ob21_failure

t_ob40_frozen_queue_relay() {
  local ok=0 rc started elapsed resumed
  rg_reset
  docker pause "$RG_RD" >/dev/null
  ob_seed ana@example.com >/dev/null
  started=$SECONDS
  docker exec "$RG_SC" php artisan outbox:relay >/dev/null 2>&1
  rc=$?
  elapsed=$((SECONDS - started))
  [ "$rc" = 1 ] || { note "saída do comando: $rc"; ok=1; }
  [ "$elapsed" -lt 3 ] || { note "levou ${elapsed}s"; ok=1; }
  rg_event_is pending ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  [ "$(rg_event 'published_at is null' ana@example.com)" = t ] || { note "published_at preenchido"; ok=1; }
  docker unpause "$RG_RD" >/dev/null
  resumed=$SECONDS
  rg_wait_for 60 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  [ $((SECONDS - resumed)) -le 60 ] || { note "levou $((SECONDS - resumed)) s"; ok=1; }
  rg_wait_for 90 rg_healthy "$RG_HZ"
  return $ok
}
check "OB40 frozen queue fails the relay fast" t_ob40_frozen_queue_relay

# Longe da virada do minuto: só o schedule:work, sem o schedule:run inicial, não dispararia.
t_ob41_scheduler_start() {
  local ok=0 started
  rg_reset
  docker stop "$RG_HZ" >/dev/null
  started=$SECONDS
  docker stop "$RG_SC" >/dev/null
  [ $((SECONDS - started)) -lt 8 ] || { note "docker stop levou $((SECONDS - started)) s"; ok=1; }
  ob_seed ana@example.com >/dev/null
  until [ "$(date +%-S)" -ge 5 ] && [ "$(date +%-S)" -le 30 ]; do sleep 1; done
  docker start "$RG_SC" >/dev/null
  rg_wait_for 10 rg_event_is published ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  docker start "$RG_HZ" >/dev/null
  rg_wait_for 90 rg_healthy "$RG_SC"
  rg_wait_for 90 rg_healthy "$RG_HZ"
  return $ok
}
check "OB41 scheduler publishes right after it starts" t_ob41_scheduler_start

t_ob26_watch_relay() {
  local ok=0 before pid saved file="$OB_LV/app-modules/outbox/src/Console/Commands/RelayOutboxCommand.php"
  saved="$(cat "$file")"
  rg_reset
  before="$(docker inspect -f '{{.Id}}' "$RG_SC")"
  set -m
  make --no-print-directory -C "$WORK" watch-laravel > "$WORK/watch-relay.log" 2>&1 &
  pid=$!
  set +m
  rg_wait_for 300 grep -q 'Watch enabled' "$WORK/watch-relay.log" || { note "watch não ficou pronto: $(tail -3 "$WORK/watch-relay.log")"; ok=1; }
  # Sem `sed -i`, que no macOS espera um sufixo; o cat mantém o arquivo que o watch acompanha.
  sed 's/event(s) published\./event(s) relayed./' "$file" > "$WORK/relay.new" && cat "$WORK/relay.new" > "$file"
  ob_new_text() { local out; out="$(docker exec "$RG_SC" php artisan outbox:relay 2>&1)"; grep -qF 'event(s) relayed.' <<< "$out"; }
  rg_wait_for 15 ob_new_text || { note "o texto novo não chegou ao scheduler"; ok=1; }
  [ "$(docker inspect -f '{{.Id}}' "$RG_SC")" = "$before" ] || { note "scheduler recriado"; ok=1; }
  kill -INT -- "-$pid" 2>/dev/null
  rg_wait_for 30 bash -c "! kill -0 $pid 2>/dev/null"
  printf '%s\n' "$saved" > "$file"
  mkq up-laravel
  return $ok
}
check "OB26 watch updates the relay" t_ob26_watch_relay

t_ob39_time_limits() {
  local values
  values="$(docker exec "$RG_HZ" php artisan tinker --execute "echo implode(' ', [config('mail.mailers.smtp.timeout'), config('horizon.defaults.supervisor-registration.timeout'), config('queue.connections.redis.retry_after'), config('outbox.republish_after')]);")"
  [ "$values" = '5 60 90 300' ] || { note "valores: $values"; return 1; }
}
check "OB39 time limits keep their order" t_ob39_time_limits
