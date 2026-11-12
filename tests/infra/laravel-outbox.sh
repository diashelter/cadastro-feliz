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
  local before i started ok=0 view="$WORK/apis/laravel/app-modules/users/resources/views/welcome-text.blade.php" saved found=1 pid
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

t_ob11_single_module() {
  [ -d "$OB_LV/app-modules/users/src" ] || { note "sem o módulo users"; return 1; }
  [ ! -e "$OB_LV/app-modules/notifications" ] || { note "o módulo notifications ainda existe"; return 1; }
  if grep -rqE 'Modules\\+Notifications' "$OB_LV/app-modules"; then
    note "app-modules referencia Modules\\Notifications"; return 1
  fi
}
check "OB11 laravel has no notifications module" t_ob11_single_module

t_ob13_scheduler() {
  local ok=0 list
  [ "$(docker inspect -f '{{.Config.Image}}' "$RG_SC")" = cadastro-feliz-laravel-php-fpm ] || { note "imagem do scheduler"; ok=1; }
  [ -z "$(docker port "$RG_SC")" ] || { note "scheduler publica: $(docker port "$RG_SC")"; ok=1; }
  # Os espaços entre os campos variam com as outras entradas da lista, que alinham as colunas.
  list="$(docker exec "$RG_SC" php artisan schedule:list --no-ansi | tr -s ' ')"
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
  local ok=0 before pid saved file="$OB_LV/app-modules/users/src/Console/Commands/RelayOutboxCommand.php"
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

# --- Limpeza e aviso de falhas (.specs/features/laravel-outbox-maintenance) ---
# O scheduler fica parado durante cada caso: o resumo agendado a cada 5 min marcaria os
# eventos semeados antes do comando que o caso roda.

OM_OPS=ops@cadastro-feliz.local
DAY=86400

om_scheduler_stop() { docker stop "$RG_SC" >/dev/null; }
om_scheduler_start() { docker start "$RG_SC" >/dev/null; rg_wait_for 90 rg_healthy "$RG_SC"; }
om_purge() { docker exec "$RG_FPM" php artisan outbox:purge 2>&1; }
om_notify() { docker exec "$RG_FPM" php artisan outbox:notify-failed 2>&1; }

# om_seed <e-mail> <status> [segundos desde created_at]: imprime o id do evento.
om_seed() { ob_seed "$1" "$2" "" 0 "${3:-0}"; }
om_processed() {
  local id
  id="$(om_seed "$1" processed)"
  psql_q "update users_outbox set processed_at = now() - make_interval(secs => $2) where id = '$id'" >/dev/null
  echo "$id"
}
# om_failed <e-mail> [segundos desde created_at] [segundos desde failure_notified_at]
om_failed() {
  local id notified=null
  id="$(om_seed "$1" failed "${2:-0}")"
  [ -n "${3:-}" ] && notified="now() - make_interval(secs => $3)"
  psql_q "update users_outbox set attempts = 5, last_error = 'Connection refused', failure_notified_at = $notified where id = '$id'" >/dev/null
  echo "$id"
}
om_left() { psql_q "select string_agg(payload->>'email', ' ' order by payload->>'email') from users_outbox"; }
om_ops_count() { rg_mail_count "$OM_OPS"; }
om_ops_text() { rg_mail_field "$OM_OPS" '.Text' | tr -d '\r'; }
om_line() { printf -- '- %s · %s · 5 tentativa(s) · Connection refused' "$1" "$2"; }

t_om1_purge_boundary() {
  local ok=0 out rc
  rg_reset
  om_scheduler_stop
  om_processed d8@example.com $((8 * DAY)) >/dev/null
  om_processed d7m1@example.com $((7 * DAY + 60)) >/dev/null
  om_processed d6h23@example.com $((7 * DAY - 60)) >/dev/null
  om_processed d6@example.com $((6 * DAY)) >/dev/null
  out="$(om_purge)"; rc=$?
  [ "$rc" = 0 ] || { note "saída do comando: $rc"; ok=1; }
  [ "$out" = '2 event(s) purged.' ] || { note "saída: $out"; ok=1; }
  [ "$(om_left)" = 'd6@example.com d6h23@example.com' ] || { note "restaram: $(om_left)"; ok=1; }
  om_scheduler_start
  return $ok
}
check "OM1 purge deletes processed events past retention" t_om1_purge_boundary

t_om2_purge_keeps() {
  local ok=0 out
  rg_reset
  om_scheduler_stop
  om_seed pending@example.com pending $((30 * DAY)) >/dev/null
  ob_seed published@example.com published $((30 * DAY)) 0 $((30 * DAY)) >/dev/null
  om_failed failed@example.com $((30 * DAY)) >/dev/null
  om_processed old@example.com $((8 * DAY)) >/dev/null
  out="$(om_purge)"
  [ "$out" = '1 event(s) purged.' ] || { note "saída: $out"; ok=1; }
  [ "$(om_left)" = 'failed@example.com pending@example.com published@example.com' ] || { note "restaram: $(om_left)"; ok=1; }
  rg_user_exists old@example.com || { note "o usuário do evento apagado sumiu"; ok=1; }
  [ "$(psql_q 'select count(*) from users')" = 4 ] || { note "usuários: $(psql_q 'select count(*) from users')"; ok=1; }
  om_scheduler_start
  return $ok
}
check "OM2 purge keeps other statuses and users" t_om2_purge_keeps

t_om3_purge_nothing() {
  local ok=0 out rc before
  rg_reset
  om_scheduler_stop
  om_processed recent@example.com "$DAY" >/dev/null
  om_failed failed@example.com $((30 * DAY)) >/dev/null
  before="$(psql_q 'select id, status, processed_at from users_outbox order by id')"
  out="$(om_purge)"; rc=$?
  [ "$rc" = 0 ] || { note "saída do comando: $rc"; ok=1; }
  [ "$out" = '0 event(s) purged.' ] || { note "saída: $out"; ok=1; }
  [ "$(psql_q 'select id, status, processed_at from users_outbox order by id')" = "$before" ] || { note "users_outbox mudou"; ok=1; }
  om_scheduler_start
  return $ok
}
check "OM3 purge with nothing due changes nothing" t_om3_purge_nothing

t_om4_purge_db_down() {
  local ok=0 out rc
  rg_reset
  om_scheduler_stop
  om_processed old@example.com $((8 * DAY)) >/dev/null
  docker stop "$OB_PG" >/dev/null
  out="$(om_purge)"; rc=$?
  docker start "$OB_PG" >/dev/null
  rg_shared_back
  [ "$rc" = 1 ] || { note "saída do comando: $rc"; ok=1; }
  grep -qF 'outbox purge failed' <<< "$out" || { note "sem o log: $out"; ok=1; }
  [ "$(om_left)" = 'old@example.com' ] || { note "restaram: $(om_left)"; ok=1; }
  om_scheduler_start
  return $ok
}
check "OM4 purge failure exits 1 and keeps rows" t_om4_purge_db_down

t_om5_retention_days() {
  local ok=0 out
  rg_set_env OUTBOX_RETENTION_DAYS=1 || { note "make up-laravel saiu com erro"; return 1; }
  rg_reset
  om_scheduler_stop
  om_processed two-days@example.com $((2 * DAY)) >/dev/null
  om_processed half-day@example.com $((DAY / 2)) >/dev/null
  out="$(om_purge)"
  [ "$out" = '1 event(s) purged.' ] || { note "saída: $out"; ok=1; }
  [ "$(om_left)" = 'half-day@example.com' ] || { note "restaram: $(om_left)"; ok=1; }
  rg_set_env OUTBOX_RETENTION_DAYS=7 || { note "make up-laravel saiu com erro"; ok=1; }
  rg_wait_for 90 rg_healthy "$RG_SC"
  return $ok
}
check "OM5 purge follows the retention days" t_om5_retention_days

t_om6_schedule() {
  local ok=0 list tz
  list="$(docker exec "$RG_SC" php artisan schedule:list --no-ansi 2>&1 | tr -s ' ')"
  grep -qE '^ ?0 3 \* \* \* php artisan outbox:purge ' <<< "$list" || { note "sem outbox:purge às 03:00: $list"; ok=1; }
  grep -qE '^ ?\*/5 \* \* \* \* php artisan outbox:notify-failed ' <<< "$list" || { note "sem outbox:notify-failed a cada 5 min: $list"; ok=1; }
  tz="$(docker exec "$RG_SC" php artisan tinker --execute "echo config('app.timezone');")"
  [ "$tz" = UTC ] || { note "timezone: $tz"; ok=1; }
  return $ok
}
check "OM6 scheduler lists the maintenance commands" t_om6_schedule

t_om7_digest() {
  local ok=0 out rc ana bia text
  rg_reset
  om_scheduler_stop
  ana="$(om_failed ana@example.com 20)"
  bia="$(om_failed bia@example.com 10)"
  out="$(om_notify)"; rc=$?
  [ "$rc" = 0 ] || { note "saída do comando: $rc"; ok=1; }
  [ "$out" = '2 failed event(s) notified.' ] || { note "saída: $out"; ok=1; }
  rg_wait_for 10 rg_mail_arrived "$OM_OPS"
  [ "$(om_ops_count)" = 1 ] || { note "e-mails ao operador: $(om_ops_count)"; ok=1; }
  [ "$(rg_mail_field "$OM_OPS" '.Subject')" = 'Cadastro Feliz: 2 evento(s) sem envio' ] || { note "assunto: $(rg_mail_field "$OM_OPS" '.Subject')"; ok=1; }
  [ "$(rg_mail_field "$OM_OPS" '.From.Address')" = no-reply@cadastro-feliz.local ] || { note "remetente: $(rg_mail_field "$OM_OPS" '.From.Address')"; ok=1; }
  text="$(om_ops_text)"
  [ "$(grep -F -e "$(om_line "$ana" ana@example.com)" -e "$(om_line "$bia" bia@example.com)" <<< "$text")" \
    = "$(printf '%s\n%s' "$(om_line "$ana" ana@example.com)" "$(om_line "$bia" bia@example.com)")" ] \
    || { note "linhas: $text"; ok=1; }
  grep -qxF 'Para reenviar, use o reprocessamento manual de docs/database.md, seção "Reprocessar um evento em failed".' <<< "$text" \
    || { note "sem o fecho: $text"; ok=1; }
  [ "$(psql_q 'select count(*) from users_outbox where failure_notified_at is not null')" = 2 ] || { note "marcados: $(psql_q 'select count(*) from users_outbox where failure_notified_at is not null')"; ok=1; }
  om_scheduler_start
  return $ok
}
check "OM7 digest lists failed events and marks them" t_om7_digest

t_om8_second_run() {
  local ok=0 out rc
  rg_reset
  om_scheduler_stop
  om_failed ana@example.com >/dev/null
  om_notify >/dev/null
  rg_wait_for 10 rg_mail_arrived "$OM_OPS"
  out="$(om_notify)"; rc=$?
  [ "$rc" = 0 ] || { note "saída do comando: $rc"; ok=1; }
  [ "$out" = '0 failed event(s) notified.' ] || { note "saída: $out"; ok=1; }
  sleep 2
  [ "$(om_ops_count)" = 1 ] || { note "e-mails ao operador: $(om_ops_count)"; ok=1; }
  om_scheduler_start
  return $ok
}
check "OM8 second run sends no digest" t_om8_second_run

t_om9_skips() {
  local ok=0 out before
  rg_reset
  om_scheduler_stop
  om_failed notified@example.com 0 "$DAY" >/dev/null
  om_processed processed@example.com 60 >/dev/null
  om_seed pending@example.com pending >/dev/null
  ob_seed published@example.com published 10 >/dev/null
  before="$(psql_q 'select id, coalesce(failure_notified_at::text, $$null$$) from users_outbox order by id')"
  out="$(om_notify)"
  [ "$out" = '0 failed event(s) notified.' ] || { note "saída: $out"; ok=1; }
  sleep 2
  [ "$(om_ops_count)" = 0 ] || { note "e-mails ao operador: $(om_ops_count)"; ok=1; }
  [ "$(psql_q 'select id, coalesce(failure_notified_at::text, $$null$$) from users_outbox order by id')" = "$before" ] \
    || { note "failure_notified_at mudou"; ok=1; }
  om_scheduler_start
  return $ok
}
check "OM9 digest skips other statuses and notified events" t_om9_skips

t_om10_smtp_down() {
  local ok=0 out rc id mailpit
  mailpit="$(container mailpit)"
  rg_reset
  om_scheduler_stop
  id="$(om_failed ana@example.com)"
  docker stop "$mailpit" >/dev/null
  out="$(om_notify)"; rc=$?
  [ "$rc" = 1 ] || { note "saída do comando: $rc"; ok=1; }
  grep -qF 'outbox failed-events notification failed' <<< "$out" || { note "sem o log: $out"; ok=1; }
  [ "$(rg_event 'failure_notified_at is null' ana@example.com)" = t ] || { note "marcado com o SMTP fora"; ok=1; }
  docker start "$mailpit" >/dev/null
  rg_shared_back
  out="$(om_notify)"
  [ "$out" = '1 failed event(s) notified.' ] || { note "depois: $out"; ok=1; }
  rg_wait_for 10 rg_mail_arrived "$OM_OPS"
  grep -qxF -e "$(om_line "$id" ana@example.com)" <<< "$(om_ops_text)" || { note "o resumo não lista o evento: $(om_ops_text)"; ok=1; }
  [ "$(rg_event 'failure_notified_at is null' ana@example.com)" = f ] || { note "não marcado depois do envio"; ok=1; }
  om_scheduler_start
  return $ok
}
check "OM10 smtp down marks nothing and the next run sends" t_om10_smtp_down

t_om11_batch() {
  local ok=0 first second third text
  rg_set_env OUTBOX_BATCH_SIZE=2 || { note "make up-laravel saiu com erro"; return 1; }
  rg_reset
  om_scheduler_stop
  first="$(om_failed first@example.com 30)"
  second="$(om_failed second@example.com 20)"
  third="$(om_failed third@example.com 10)"
  [ "$(om_notify)" = '2 failed event(s) notified.' ] || { note "1ª execução"; ok=1; }
  rg_wait_for 10 rg_mail_arrived "$OM_OPS"
  text="$(om_ops_text)"
  grep -qF "$first" <<< "$text" && grep -qF "$second" <<< "$text" && ! grep -qF "$third" <<< "$text" || { note "1º resumo: $text"; ok=1; }
  [ "$(om_notify)" = '1 failed event(s) notified.' ] || { note "2ª execução"; ok=1; }
  rg_wait_for 10 bash -c "[ \"\$(curl -s -G localhost:8025/api/v1/search --data-urlencode 'query=to:\"$OM_OPS\"' | jq -r .messages_count)\" = 2 ]"
  text="$(om_ops_text)"
  grep -qF "$third" <<< "$text" && ! grep -qF "$first" <<< "$text" || { note "2º resumo: $text"; ok=1; }
  [ "$(om_notify)" = '0 failed event(s) notified.' ] || { note "3ª execução"; ok=1; }
  sleep 2
  [ "$(om_ops_count)" = 2 ] || { note "e-mails ao operador: $(om_ops_count)"; ok=1; }
  rg_default_env
  rg_wait_for 90 rg_healthy "$RG_SC"
  return $ok
}
check "OM11 batch size limits each digest" t_om11_batch

t_om12_reprocessed_mid_run() {
  local ok=0 id out pid
  rg_reset
  om_scheduler_stop
  id="$(om_failed ana@example.com)"
  # O reprocessamento trava a linha antes da leitura e só confirma depois do envio do resumo:
  # a leitura vê o evento ainda failed, e a marca espera o COMMIT.
  docker exec "$OB_PG" psql -U cadastro_feliz -d cadastro_feliz -q -c "begin;
    update users_outbox set status = 'pending', attempts = 0, available_at = now(), failure_notified_at = null
      where id = '$id' and status = 'failed';
    select pg_sleep(6);
    commit;" >/dev/null &
  pid=$!
  sleep 1
  out="$(om_notify)"
  wait "$pid"
  [ "$out" = '1 failed event(s) notified.' ] || { note "saída: $out"; ok=1; }
  rg_wait_for 10 rg_mail_arrived "$OM_OPS"
  grep -qxF -e "$(om_line "$id" ana@example.com)" <<< "$(om_ops_text)" || { note "o resumo não lista o evento: $(om_ops_text)"; ok=1; }
  [ "$(rg_event "status || ' ' || (failure_notified_at is null)" ana@example.com)" = 'pending true' ] \
    || { note "evento: $(rg_event "status || ' ' || (failure_notified_at is null)" ana@example.com)"; ok=1; }
  om_scheduler_start
  return $ok
}
check "OM12 event reprocessed mid-run stays unmarked" t_om12_reprocessed_mid_run

t_om13_documented_reprocess() {
  local ok=0 id sql
  rg_reset
  om_scheduler_stop
  id="$(om_failed ana@example.com 0 "$DAY")"
  sql="$(awk '/^### Reprocessar um evento em `failed`/{on=1; next} on && /^```sql$/{grab=1; next} grab && /^```$/{exit} grab' "$WORK/docs/database.md")"
  [ -n "$sql" ] || { note "SQL de reprocessamento não encontrado em docs/database.md"; return 1; }
  psql_q "${sql//\$1/'$id'}" >/dev/null || { note "o SQL do documento falhou: $sql"; ok=1; }
  [ "$(rg_event "status || ' ' || attempts || ' ' || (failure_notified_at is null)" ana@example.com)" = 'pending 0 true' ] \
    || { note "reprocessado: $(rg_event "status || ' ' || attempts || ' ' || (failure_notified_at is null)" ana@example.com)"; ok=1; }
  psql_q "update users_outbox set status = 'failed', attempts = 5 where id = '$id'" >/dev/null
  [ "$(om_notify)" = '1 failed event(s) notified.' ] || { note "o evento não voltou ao resumo"; ok=1; }
  rg_wait_for 10 rg_mail_arrived "$OM_OPS"
  grep -qxF -e "$(om_line "$id" ana@example.com)" <<< "$(om_ops_text)" || { note "o resumo não lista o evento: $(om_ops_text)"; ok=1; }
  om_scheduler_start
  return $ok
}
check "OM13 documented reprocess clears the notice" t_om13_documented_reprocess

t_om15_variables() {
  local ok=0 c env
  for c in "$RG_FPM" "$RG_SC" "$RG_HZ"; do
    env="$(docker exec "$c" printenv)"
    grep -qx 'OUTBOX_ALERT_EMAIL=ops@cadastro-feliz.local' <<< "$env" || { note "$c sem OUTBOX_ALERT_EMAIL"; ok=1; }
    grep -qx 'OUTBOX_RETENTION_DAYS=7' <<< "$env" || { note "$c sem OUTBOX_RETENTION_DAYS"; ok=1; }
  done
  grep -qx 'OUTBOX_ALERT_EMAIL=ops@cadastro-feliz.local' "$WORK/.env.example" || { note ".env.example sem OUTBOX_ALERT_EMAIL"; ok=1; }
  grep -qx 'OUTBOX_RETENTION_DAYS=7' "$WORK/.env.example" || { note ".env.example sem OUTBOX_RETENTION_DAYS"; ok=1; }
  return $ok
}
check "OM15 containers receive the maintenance variables" t_om15_variables

t_om23_compose_defaults() {
  local ok=0 env cfg
  env="$WORK/om23.env"
  grep -vE '^OUTBOX_(RETENTION_DAYS|ALERT_EMAIL)=' "$WORK/.env.example" > "$env"
  cfg="$(docker compose --env-file "$env" -f "$WORK/apis/laravel/docker-compose.yml" config --format json 2>/dev/null)" \
    || { note "docker compose config falhou"; return 1; }
  for s in php-fpm scheduler horizon; do
    [ "$(jq -r --arg s "$s" '.services[$s].environment.OUTBOX_RETENTION_DAYS' <<< "$cfg")" = 7 ] || { note "$s: retenção"; ok=1; }
    [ "$(jq -r --arg s "$s" '.services[$s].environment.OUTBOX_ALERT_EMAIL' <<< "$cfg")" = ops@cadastro-feliz.local ] || { note "$s: alerta"; ok=1; }
  done
  rm -f "$env"
  return $ok
}
check "OM23 compose defaults the maintenance variables" t_om23_compose_defaults
