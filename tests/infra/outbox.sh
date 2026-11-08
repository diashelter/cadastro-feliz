# Casos de contrato do outbox (decisão 23): o cadastro grava o evento, o relay publica e o
# worker envia. LM1 a LM3 nasceram como o antes e depois da primeira stack (decisão 21) e hoje afirmam
# o comportamento com outbox. Carregado por run.sh, que escolhe a stack em $SUITE_STACK e
# carrega o adaptador dela antes. Roda contra PostgreSQL, Mailpit e a stack de verdade.

# shellcheck source=/dev/null
source "$TESTS/registration-helpers.sh"

OB_MAILPIT="$(container mailpit)"
OB_PG="$(container postgres)"

ob_queue_empty() { [ "$(stack_queue_length)" = 0 ]; }
ob_quiet_queue() {
  rg_wait_for 30 ob_queue_empty
  sleep 6
}

# Depois de parar o relay e o worker, os dois voltam mesmo que o teste falhe.
ob_start_workers() {
  stack_relay_start
  stack_worker_start
}

t_lm0_up() {
  mkq "up-$SUITE_STACK" || { note "make up-$SUITE_STACK saiu com erro"; return 1; }
}
check "LM0 stack up for the outbox tests" t_lm0_up

# --- S4: as limitações invertidas ---

t_lm1_queue_down() {
  local ok=0 started
  rg_reset
  stack_queue_stop
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  rg_event_is pending ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  started=$SECONDS
  stack_queue_start
  # O prazo de 60 s conta de quando a fila é religada, com a espera dela incluída.
  rg_wait_for "$((60 - (SECONDS - started)))" rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  rg_wait_for 10 rg_event_is processed ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  stack_wait_ready || { note "a stack não voltou a ficar saudável"; ok=1; }
  [ "$(rg_register ana@example.com)" = 409 ] || { note "repetir: $(rg_body)"; ok=1; }
  sleep 5
  [ "$(rg_mail_count ana@example.com)" = 1 ] || { note "mensagens: $(rg_mail_count ana@example.com)"; ok=1; }
  return $ok
}
check "LM1 queue down delays the mail" t_lm1_queue_down

t_lm2_stack_down() {
  local ok=0 before after
  rg_set_env OUTBOX_REPUBLISH_AFTER_SECONDS=5 || { note "make up-$SUITE_STACK saiu com erro"; return 1; }
  rg_reset
  stack_worker_stop
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  rg_wait_for 15 rg_queue_has || { note "o job não chegou à fila"; ok=1; }
  rg_wait_for 15 rg_event_is published ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  mkq "down-$SUITE_STACK" || { note "make down-$SUITE_STACK saiu com erro"; ok=1; }
  rg_event_is published ana@example.com || { note "depois de derrubar: $(rg_event status ana@example.com)"; ok=1; }
  before="$(rg_event published_at ana@example.com)"
  # Só a fila primeiro: ela volta vazia, antes de o relay republicar.
  stack_queue_up_alone
  [ "$(stack_queue_length)" = 0 ] || { note "fila com $(stack_queue_length) mensagens"; ok=1; }
  mkq "up-$SUITE_STACK" || { note "make up-$SUITE_STACK saiu com erro"; ok=1; }
  rg_wait_for 60 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  rg_wait_for 10 rg_event_is processed ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  after="$(rg_event published_at ana@example.com)"
  [ "$after" != "$before" ] || { note "published_at não mudou: $after"; ok=1; }
  sleep 5
  [ "$(rg_mail_count ana@example.com)" = 1 ] || { note "mensagens: $(rg_mail_count ana@example.com)"; ok=1; }
  rg_default_env
  return $ok
}
check "LM2 stack down republishes the event" t_lm2_stack_down

t_lm2b_pending_survives() {
  local ok=0
  rg_reset
  stack_relay_stop
  stack_worker_stop
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  rg_event_is pending ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  mkq "down-$SUITE_STACK" || { note "make down-$SUITE_STACK saiu com erro"; ok=1; }
  mkq "up-$SUITE_STACK" || { note "make up-$SUITE_STACK saiu com erro"; ok=1; }
  rg_wait_for 60 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  return $ok
}
check "LM2B stack down delivers pending events" t_lm2b_pending_survives

t_lm3_retries_exhausted() {
  local ok=0
  rg_set_env OUTBOX_MAX_ATTEMPTS=2 OUTBOX_BACKOFF_BASE_SECONDS=1 || { note "make up-$SUITE_STACK saiu com erro"; return 1; }
  rg_reset
  docker stop "$OB_MAILPIT" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  rg_wait_for 60 rg_event_is failed ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  [ "$(rg_event attempts ana@example.com)" = 2 ] || { note "attempts: $(rg_event attempts ana@example.com)"; ok=1; }
  [ -n "$(rg_event last_error ana@example.com)" ] || { note "last_error vazio"; ok=1; }
  [ "$(stack_failed_jobs)" = 0 ] || { note "falhas na fila: $(stack_failed_jobs)"; ok=1; }
  docker start "$OB_MAILPIT" >/dev/null
  rg_shared_back
  sleep 30
  [ "$(rg_mail_count ana@example.com)" = 0 ] || { note "e-mail saiu sozinho: $(rg_mail_count ana@example.com)"; ok=1; }
  rg_event_is failed ana@example.com || { note "depois de 30 s: $(rg_event status ana@example.com)"; ok=1; }
  # O reprocessamento de docs/database.md.
  psql_q "update users_outbox set status = 'pending', attempts = 0, available_at = now() where id = '$(rg_event id ana@example.com)' and status = 'failed'" >/dev/null
  rg_wait_for 60 rg_mail_arrived ana@example.com || { note "reprocessado, o e-mail não chegou"; ok=1; }
  rg_wait_for 10 rg_event_is processed ana@example.com || { note "reprocessado: $(rg_event status ana@example.com)"; ok=1; }
  rg_default_env
  return $ok
}
check "LM3 exhausted retries are recorded and recoverable" t_lm3_retries_exhausted

# --- S1: cadastro e evento na mesma transação ---

t_ob1_pending_event() {
  local ok=0 id row
  rg_reset
  stack_relay_stop
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  id="$(jq -r '.data.id' "$WORK/r.body")"
  row="$(psql_q "select user_id, event_type, status, attempts, published_at is null from users_outbox")"
  [ "$row" = "$id|user.registered|pending|0|t" ] || { note "evento: $row, esperava o usuário $id"; ok=1; }
  stack_relay_start
  return $ok
}
check "OB1 registration writes a pending event" t_ob1_pending_event

t_ob2_payload() {
  local ok=0 payload created
  rg_reset
  [ "$(rg_post '{"name":"  Ana  ","email":"  ANA@Example.COM "}')" = 201 ] || { note "status: $(rg_body)"; return 1; }
  created="$(jq -r '.data.created_at' "$WORK/r.body")"
  payload="$(psql_q 'select payload from users_outbox')"
  [ "$(jq -c 'keys' <<< "$payload")" = '["email","name","occurred_at","user_id"]' ] || { note "chaves: $payload"; ok=1; }
  [ "$(jq -r '.name' <<< "$payload")" = Ana ] || { note "nome: $payload"; ok=1; }
  [ "$(jq -r '.email' <<< "$payload")" = ana@example.com ] || { note "e-mail: $payload"; ok=1; }
  [ "$(jq -r '.user_id' <<< "$payload")" = "$(jq -r '.data.id' "$WORK/r.body")" ] || { note "user_id: $payload"; ok=1; }
  [ "$(jq -r '.occurred_at' <<< "$payload")" = "$created" ] || { note "occurred_at: $payload, created_at: $created"; ok=1; }
  return $ok
}
check "OB2 payload keys and normalization" t_ob2_payload

ob_drop_trigger() {
  psql_q 'drop trigger if exists ob_trigger on users_outbox' >/dev/null
  psql_q 'drop function if exists ob_trigger_fn' >/dev/null
}

t_ob4_rollback() {
  local ok=0 before status
  rg_reset
  rg_register primeiro@example.com >/dev/null
  before="$(rg_quota_value)"
  psql_q "create function ob_trigger_fn() returns trigger language plpgsql as \$\$ begin raise exception 'forced'; end \$\$" >/dev/null
  psql_q 'create trigger ob_trigger before insert on users_outbox for each row execute function ob_trigger_fn()' >/dev/null
  status="$(rg_register ana@example.com)"
  ob_drop_trigger
  [ "$status" = 500 ] || { note "status $status: $(rg_body)"; ok=1; }
  [ "$(rg_body)" = '{"message":"Internal server error.","errors":[]}' ] || { note "corpo: $(rg_body)"; ok=1; }
  rg_user_exists ana@example.com && { note "usuário ficou gravado"; ok=1; }
  [ "$(rg_quota_value)" = "$before" ] || { note "cota: antes $before, depois $(rg_quota_value)"; ok=1; }
  return $ok
}
check "OB4 outbox insert failure rolls back the user" t_ob4_rollback

t_ob5_frozen_queue() {
  local out code secs since errors before after pending ok=0
  rg_reset
  rg_register ana@example.com >/dev/null
  before="$(rg_quota_value)"
  # --since tem resolução de segundo: a espera deixa de fora o log do teste anterior.
  sleep 1
  since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  stack_queue_freeze
  out="$(rg_timed_post '{"name":"Bia","email":"bia@example.com"}')"
  code="${out% *}"; secs="${out#* }"
  after="$(rg_quota_value)"
  pending="$(rg_event status bia@example.com)"
  errors="$(stack_api_errors_since "$since")"
  stack_queue_unfreeze
  [ "$code" = 201 ] || { note "status $code: $(rg_body)"; ok=1; }
  rg_under_3s "$secs" || { note "levou ${secs}s"; ok=1; }
  rg_user_exists bia@example.com || { note "usuário não foi gravado"; ok=1; }
  [ "$pending" = pending ] || { note "evento: $pending"; ok=1; }
  [ -n "$errors" ] && { note "erro no log da API: $errors"; ok=1; }
  [ "$after" = "$((before + 1))" ] || { note "cota: antes $before, depois $after"; ok=1; }
  stack_wait_ready
  return $ok
}
check "OB5 frozen queue still answers 201" t_ob5_frozen_queue

# Ler o contador abre uma conexão, e o healthcheck da fila pode abrir outras de tempos em
# tempos. Uma conexão da API apareceria em toda rodada, então basta uma rodada com só a leitura.
t_ob6_no_connection() {
  local ok=1 i before after
  rg_reset
  stack_relay_stop
  stack_worker_stop
  for i in 1 2 3 4 5; do
    before="$(stack_queue_connections)"
    [ "$(rg_register "c$i@example.com")" = 201 ] || { note "status: $(rg_body)"; break; }
    after="$(stack_queue_connections)"
    if [ "$after" = "$((before + 1))" ]; then ok=0; break; fi
    note "conexões: antes $before, depois $after"
    sleep 1
  done
  ob_start_workers
  return $ok
}
check "OB6 registration never connects to the queue" t_ob6_no_connection

# --- S2: relay ---

t_ob15_publishes() {
  local ok=0
  rg_reset
  stack_worker_stop
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  rg_wait_for 10 rg_event_is published ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  [ "$(rg_event 'published_at is not null' ana@example.com)" = t ] || { note "sem published_at"; ok=1; }
  [ "$(stack_queue_length)" = 1 ] || { note "fila: $(stack_queue_length)"; ok=1; }
  stack_worker_start
  return $ok
}
check "OB15 relay publishes a pending event" t_ob15_publishes

t_ob16_future() {
  local ok=0
  rg_reset
  stack_worker_stop
  ob_seed futuro@example.com pending '' 3600 >/dev/null
  sleep 5
  rg_event_is pending futuro@example.com || { note "evento: $(rg_event status futuro@example.com)"; ok=1; }
  [ "$(stack_queue_length)" = 0 ] || { note "fila: $(stack_queue_length)"; ok=1; }
  stack_worker_start
  return $ok
}
check "OB16 relay skips a future event" t_ob16_future

t_ob17_republish() {
  local ok=0 before after
  rg_reset
  stack_worker_stop
  # Com 300 s, publicado há 10 s não expirou.
  ob_seed recente@example.com published 10 >/dev/null
  before="$(rg_event published_at recente@example.com)"
  sleep 5
  [ "$(rg_event published_at recente@example.com)" = "$before" ] || { note "republicou com 300 s"; ok=1; }
  [ "$(stack_queue_length)" = 0 ] || { note "fila com 300 s: $(stack_queue_length)"; ok=1; }
  # Com 5 s, expirou.
  rg_set_env OUTBOX_REPUBLISH_AFTER_SECONDS=5 || { note "make up-$SUITE_STACK saiu com erro"; ok=1; }
  stack_worker_stop
  rg_reset
  ob_seed antigo@example.com published 10 >/dev/null
  before="$(rg_event published_at antigo@example.com)"
  rg_wait_for 10 rg_queue_has || { note "não republicou com 5 s"; ok=1; }
  after="$(rg_event published_at antigo@example.com)"
  [ "$after" != "$before" ] || { note "published_at não mudou"; ok=1; }
  [ "$(rg_event attempts antigo@example.com)" = 0 ] || { note "attempts: $(rg_event attempts antigo@example.com)"; ok=1; }
  rg_default_env
  return $ok
}
check "OB17 relay republishes only expired events" t_ob17_republish

t_ob18_terminal() {
  local ok=0
  rg_reset
  stack_worker_stop
  ob_seed feito@example.com processed 3600 >/dev/null
  ob_seed falho@example.com failed 3600 >/dev/null
  sleep 5
  [ "$(stack_queue_length)" = 0 ] || { note "fila: $(stack_queue_length)"; ok=1; }
  rg_event_is processed feito@example.com || { note "processed mudou"; ok=1; }
  rg_event_is failed falho@example.com || { note "failed mudou"; ok=1; }
  stack_worker_start
  return $ok
}
check "OB18 relay never selects terminal events" t_ob18_terminal

t_ob22_resumes() {
  local relay sc started ok=0
  rg_reset
  relay="$(stack_relay_container)"
  sc="$(docker inspect -f '{{.Id}}' "$relay")"
  stack_queue_stop
  # Uma falha com a fila parada só é anotada: a fila volta antes de o caso retornar.
  if [ "$(rg_register ana@example.com)" != 201 ]; then
    note "status: $(rg_body)"; ok=1
  else
    sleep 3
    rg_event_is pending ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  fi
  started=$SECONDS
  stack_queue_start
  if [ "$ok" = 0 ]; then
    rg_wait_for "$((60 - (SECONDS - started)))" rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
    [ "$(docker inspect -f '{{.Id}}' "$relay")" = "$sc" ] || { note "relay recriado"; ok=1; }
    [ "$(docker inspect -f '{{.RestartCount}}' "$relay")" = 0 ] || { note "relay reiniciou"; ok=1; }
  fi
  stack_wait_ready
  return $ok
}
check "OB22 relay resumes when the queue returns" t_ob22_resumes

t_ob23_rollback_after_publish() {
  local ok=0
  rg_reset
  stack_worker_stop
  psql_q "create function ob_trigger_fn() returns trigger language plpgsql as \$\$ begin raise exception 'forced'; end \$\$" >/dev/null
  psql_q "create trigger ob_trigger before update on users_outbox for each row when (new.status = 'published') execute function ob_trigger_fn()" >/dev/null
  ob_seed um@example.com >/dev/null
  ob_seed dois@example.com >/dev/null
  rg_wait_for 15 rg_queue_has 4 || { note "fila: $(stack_queue_length)"; ok=1; }
  rg_event_is pending um@example.com || { note "um: $(rg_event status um@example.com)"; ok=1; }
  rg_event_is pending dois@example.com || { note "dois: $(rg_event status dois@example.com)"; ok=1; }
  ob_drop_trigger
  stack_worker_start
  rg_wait_for 60 rg_mail_arrived um@example.com || { note "um não chegou"; ok=1; }
  rg_wait_for 60 rg_mail_arrived dois@example.com || { note "dois não chegou"; ok=1; }
  ob_quiet_queue
  [ "$(rg_mail_count um@example.com)" = 1 ] || { note "um: $(rg_mail_count um@example.com) mensagens"; ok=1; }
  [ "$(rg_mail_count dois@example.com)" = 1 ] || { note "dois: $(rg_mail_count dois@example.com) mensagens"; ok=1; }
  return $ok
}
check "OB23 relay rollback after publish sends once" t_ob23_rollback_after_publish

# O worker pode dormir 3 s com a fila vazia, então o atraso é maior que os 3 s do critério:
# assim a mensagem sempre chega antes do COMMIT.
t_ob24_before_commit() {
  local ok=0 seen=1 i
  rg_reset
  psql_q "create function ob_trigger_fn() returns trigger language plpgsql as \$\$ begin perform pg_sleep(8); return new; end \$\$" >/dev/null
  psql_q "create trigger ob_trigger before update on users_outbox for each row when (new.status = 'published') execute function ob_trigger_fn()" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  for i in $(seq 1 16); do
    if rg_mail_arrived ana@example.com && rg_event_is pending ana@example.com; then seen=0; break; fi
    sleep 0.5
  done
  [ "$seen" = 0 ] || { note "o e-mail não saiu antes do COMMIT: $(rg_event status ana@example.com)"; ok=1; }
  rg_wait_for 30 rg_event_is processed ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  ob_drop_trigger
  [ "$(rg_mail_count ana@example.com)" = 1 ] || { note "mensagens: $(rg_mail_count ana@example.com)"; ok=1; }
  [ "$(rg_event 'processed_at is not null' ana@example.com)" = t ] || { note "sem processed_at"; ok=1; }
  return $ok
}
check "OB24 message before commit ends processed" t_ob24_before_commit

t_ob25_waits_relay() {
  local ok=0 started
  rg_reset
  stack_relay_stop
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  sleep 3
  rg_event_is pending ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  [ "$(rg_mail_count ana@example.com)" = 0 ] || { note "saiu sem o relay"; ok=1; }
  started=$SECONDS
  stack_relay_start
  rg_wait_for "$((60 - (SECONDS - started)))" rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  return $ok
}
check "OB25 events wait for the relay" t_ob25_waits_relay

# --- S3: worker sobre o evento ---

t_ob27_processed() {
  local ok=0
  rg_reset
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  rg_wait_for 30 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  rg_wait_for 10 rg_event_is processed ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  [ "$(rg_event 'processed_at is not null' ana@example.com)" = t ] || { note "sem processed_at"; ok=1; }
  [ "$(rg_event 'last_error is null' ana@example.com)" = t ] || { note "last_error preenchido"; ok=1; }
  [ "$(rg_mail_count ana@example.com)" = 1 ] || { note "mensagens: $(rg_mail_count ana@example.com)"; ok=1; }
  [ "$(rg_mail_field ana@example.com '.To[0].Address')" = ana@example.com ] || { note "destinatário: $(rg_mail_field ana@example.com '.To[0].Address')"; ok=1; }
  return $ok
}
check "OB27 processed event and mail" t_ob27_processed

t_ob28_payload_name() {
  local ok=0 text
  rg_reset
  stack_worker_stop
  [ "$(rg_register ana@example.com 'Nome Original')" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  psql_q "update users set name = 'Nome Trocado' where email = 'ana@example.com'" >/dev/null
  stack_worker_start
  rg_wait_for 30 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  text="$(rg_mail_field ana@example.com '.Text')"
  grep -qF 'Olá, Nome Original!' <<< "$text" || { note "texto: $text"; ok=1; }
  grep -qF 'Nome Trocado' <<< "$text" && { note "usou o nome de users"; ok=1; }
  return $ok
}
check "OB28 mail uses the payload name" t_ob28_payload_name

t_ob29_message_id() {
  local id
  rg_reset
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; return 1; }
  rg_wait_for 30 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; return 1; }
  id="$(rg_event id ana@example.com)"
  [ "$(rg_mail_field ana@example.com '.MessageID')" = "$id@cadastro-feliz.local" ] \
    || { note "MessageID: $(rg_mail_field ana@example.com '.MessageID'), evento: $id"; return 1; }
}
check "OB29 message id derives from the event" t_ob29_message_id

ob_snapshot() { psql_q "select status, attempts, processed_at, last_error from users_outbox where id = '$1'"; }

t_ob31_terminal_message() {
  local ok=0 id before
  rg_reset
  [ "$(rg_register feito@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  rg_wait_for 30 rg_mail_arrived feito@example.com || { note "o e-mail não chegou"; ok=1; }
  rg_wait_for 10 rg_event_is processed feito@example.com
  id="$(rg_event id feito@example.com)"
  before="$(ob_snapshot "$id")"
  stack_dispatch "$id"
  ob_quiet_queue
  [ "$(ob_snapshot "$id")" = "$before" ] || { note "processed mudou: $(ob_snapshot "$id")"; ok=1; }
  [ "$(rg_mail_count feito@example.com)" = 1 ] || { note "reenviou processed"; ok=1; }
  id="$(ob_seed falho@example.com failed 3600)"
  before="$(ob_snapshot "$id")"
  stack_dispatch "$id"
  ob_quiet_queue
  [ "$(ob_snapshot "$id")" = "$before" ] || { note "failed mudou: $(ob_snapshot "$id")"; ok=1; }
  [ "$(rg_mail_count falho@example.com)" = 0 ] || { note "enviou failed"; ok=1; }
  return $ok
}
check "OB31 terminal event message sends nothing" t_ob31_terminal_message

t_ob32_missing_event() {
  local ok=0 since logs id=00000000-0000-4000-8000-000000000032
  rg_reset
  since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  stack_dispatch "$id"
  ob_quiet_queue
  logs="$(stack_worker_logs_since "$since")"
  grep -F 'outbox event not found' <<< "$logs" | grep -qF "$id" || { note "log do worker sem o evento: $(tail -5 <<< "$logs")"; ok=1; }
  [ "$(stack_failed_jobs)" = 0 ] || { note "falhas na fila: $(stack_failed_jobs)"; ok=1; }
  [ "$(curl -s --max-time 10 localhost:8025/api/v1/messages | jq -r '.total')" = 0 ] || { note "saiu e-mail"; ok=1; }
  return $ok
}
check "OB32 missing event is ignored" t_ob32_missing_event

ob_wait_seconds() { psql_q "select extract(epoch from available_at - now())::int from users_outbox where payload->>'email' = '$1'"; }
ob_between() { [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }

# Com os valores padrão. A base de 30 s dá 30 s na primeira falha, e 240 s depois de 3.
t_ob33_retry() {
  local ok=0 id wait
  rg_reset
  docker stop "$OB_MAILPIT" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  ob_attempts_is() { [ "$(rg_event attempts ana@example.com)" = "$1" ]; }
  rg_wait_for 30 ob_attempts_is 1 || { note "attempts: $(rg_event attempts ana@example.com)"; ok=1; }
  wait="$(ob_wait_seconds ana@example.com)"
  ob_between "$wait" 15 30 || { note "espera depois de 0: ${wait}s"; ok=1; }
  rg_event_is pending ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  [ -n "$(rg_event last_error ana@example.com)" ] || { note "last_error vazio"; ok=1; }
  [ "$(stack_failed_jobs)" = 0 ] || { note "falhas na fila: $(stack_failed_jobs)"; ok=1; }
  id="$(rg_event id ana@example.com)"
  psql_q "update users_outbox set attempts = 3, available_at = now() + interval '1 hour' where id = '$id'" >/dev/null
  stack_dispatch "$id"
  rg_wait_for 30 ob_attempts_is 4 || { note "attempts: $(rg_event attempts ana@example.com)"; ok=1; }
  wait="$(ob_wait_seconds ana@example.com)"
  ob_between "$wait" 220 240 || { note "espera depois de 3: ${wait}s"; ok=1; }
  docker start "$OB_MAILPIT" >/dev/null
  rg_shared_back
  return $ok
}
check "OB33 send failure schedules a retry" t_ob33_retry

t_ob36_frozen_smtp() {
  local ok=0
  rg_set_env OUTBOX_BACKOFF_BASE_SECONDS=2 || { note "make up-$SUITE_STACK saiu com erro"; return 1; }
  rg_reset
  docker pause "$OB_MAILPIT" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  ob_attempted() { [ "$(rg_event attempts ana@example.com)" -ge 1 ]; }
  rg_wait_for 30 ob_attempted || { note "attempts: $(rg_event attempts ana@example.com)"; ok=1; }
  [ -n "$(rg_event last_error ana@example.com)" ] || { note "last_error vazio"; ok=1; }
  docker unpause "$OB_MAILPIT" >/dev/null
  rg_wait_for 60 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  rg_shared_back
  rg_default_env
  return $ok
}
check "OB36 frozen smtp counts as a failure" t_ob36_frozen_smtp

t_ob37_no_transaction() {
  local ok=0 id i open probes=0
  rg_reset
  docker pause "$OB_MAILPIT" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  rg_wait_for 15 rg_event_is published ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  stack_relay_stop
  id="$(rg_event id ana@example.com)"
  for i in $(seq 1 30); do
    [ "$(rg_event attempts ana@example.com)" -ge 1 ] && break
    probes=$((probes + 1))
    open="$(psql_q "select count(*) from pg_stat_activity where state like 'idle in transaction%'")"
    [ "$open" = 0 ] || { note "transação aberta: $open"; ok=1; }
    docker exec "$OB_PG" psql -U cadastro_feliz -d cadastro_feliz -v ON_ERROR_STOP=1 -c \
      "set lock_timeout = '1s'; update users_outbox set last_error = last_error where id = '$id'" >/dev/null 2>&1 \
      || { note "o UPDATE esperou uma trava"; ok=1; }
    sleep 0.5
  done
  [ "$(rg_event attempts ana@example.com)" -ge 1 ] || { note "o envio não terminou"; ok=1; }
  [ "$probes" -ge 2 ] || { note "só $probes sondas durante o envio"; ok=1; }
  docker unpause "$OB_MAILPIT" >/dev/null
  rg_shared_back
  stack_relay_start
  return $ok
}
check "OB37 worker holds no transaction during send" t_ob37_no_transaction

t_ob38_database_down() {
  local ok=0 published_at
  rg_set_env OUTBOX_REPUBLISH_AFTER_SECONDS=10 || { note "make up-$SUITE_STACK saiu com erro"; return 1; }
  rg_reset
  stack_worker_stop
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  rg_wait_for 15 rg_event_is published ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  # Sem o relay, nada republica antes de o evento ser lido, com o banco de volta.
  stack_relay_stop
  published_at="$(rg_event published_at ana@example.com)"
  docker stop "$OB_PG" >/dev/null
  stack_worker_start
  ob_job_failed() { [ "$(stack_failed_jobs)" -ge 1 ]; }
  rg_wait_for 90 ob_job_failed || { note "o job não falhou na fila"; ok=1; }
  docker start "$OB_PG" >/dev/null
  rg_shared_back
  rg_event_is published ana@example.com || { note "com o banco de volta: $(rg_event status ana@example.com)"; ok=1; }
  [ "$(rg_event published_at ana@example.com)" = "$published_at" ] || { note "published_at mudou"; ok=1; }
  [ "$(rg_event attempts ana@example.com)" = 0 ] || { note "attempts: $(rg_event attempts ana@example.com)"; ok=1; }
  [ "$(rg_mail_count ana@example.com)" = 0 ] || { note "saiu com o banco fora"; ok=1; }
  stack_relay_start
  rg_wait_for 90 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  rg_default_env
  return $ok
}
check "OB38 database down keeps the event published" t_ob38_database_down

