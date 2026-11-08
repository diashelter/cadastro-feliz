# Ajudantes de registration.sh e outbox.sh, que também rodam sozinhos, como no CI. A stack
# é $SUITE_STACK, e tudo que é dela passa pelas funções stack_* do adaptador carregado por
# run.sh (tests/infra/adapters/<stack>.sh).

RG_WATCH_PID=

rg_wait_for() {
  local secs="$1" i; shift
  for ((i = 0; i < secs; i++)); do "$@" && return 0; sleep 1; done
  "$@"
}
rg_healthy() { [ "$(health "$1")" = healthy ]; }
rg_shared_back() { rg_wait_for 60 shared_healthy; }

# Banco, contadores, fila e caixa de e-mail vazios: cada teste parte do mesmo estado.
rg_reset() {
  psql_q 'truncate users cascade' >/dev/null
  redis_q FLUSHALL >/dev/null
  stack_reset_queue
  curl -s -X DELETE --max-time 10 localhost:8025/api/v1/messages >/dev/null
  return 0
}

rg_json() { jq -cn --arg name "$1" --arg email "$2" '{name: $name, email: $email}'; }

# rg_post <corpo> [args do curl]: guarda headers e corpo em $WORK e imprime o status.
rg_post() {
  local body="$1"; shift
  curl -s -D "$WORK/r.headers" -o "$WORK/r.body" --max-time 10 -w '%{http_code}' -X POST localhost:8080/users \
    -H 'Content-Type: application/json' -H 'Accept: application/json' "$@" -d "$body"
}
rg_register() { rg_post "$(rg_json "${2:-Ana Souza}" "$1")"; }
rg_body() { cat "$WORK/r.body"; }
rg_header() { grep -i "^$1:" "$WORK/r.headers" | head -1 | cut -d: -f2- | tr -d ' \r'; }

# rg_timed_post <corpo>: imprime "<status> <segundos>".
rg_timed_post() {
  curl -s -D "$WORK/r.headers" -o "$WORK/r.body" --max-time 10 -w '%{http_code} %{time_total}' -X POST localhost:8080/users \
    -H 'Content-Type: application/json' -H 'Accept: application/json' -d "$1"
}
rg_under_3s() { awk -v s="$1" 'BEGIN { exit !(s < 3) }'; }

rg_users() { psql_q 'select count(*) from users'; }
rg_events() { psql_q 'select count(*) from users_outbox'; }
# rg_event <coluna> <e-mail>: o valor de uma coluna do evento de um e-mail.
rg_event() { psql_q "select $1 from users_outbox where payload->>'email' = '$2'"; }
rg_event_is() { [ "$(rg_event status "$2")" = "$1" ]; }
rg_queue_has() { [ "$(stack_queue_length)" -ge "${1:-1}" ]; }
rg_user_exists() { [ "$(psql_q "select count(*) from users where email = '$1'")" = 1 ]; }
rg_quota_value() {
  local key
  key="$(redis_q --scan --pattern 'registration:ip:*' | head -1)"
  [ -n "$key" ] && redis_q GET "$key"
}

rg_mail_count() {
  curl -s -G --max-time 10 localhost:8025/api/v1/search --data-urlencode "query=to:\"$1\"" | jq -r '.messages_count'
}
rg_mail_arrived() { [ "$(rg_mail_count "$1")" -ge 1 ]; }
rg_mail_id() {
  curl -s -G --max-time 10 localhost:8025/api/v1/search --data-urlencode "query=to:\"$1\"" | jq -r '.messages[0].ID'
}
rg_mail_field() { curl -s --max-time 10 "localhost:8025/api/v1/message/$(rg_mail_id "$1")" | jq -r "$2"; }

# ob_seed <e-mail> [status] [segundos desde published_at] [segundos até available_at] [segundos desde created_at]:
# grava usuário e evento direto no banco e imprime o id do evento.
ob_seed() {
  local email="$1" status="${2:-pending}" published="${3:-}" available="${4:-0}" created="${5:-0}"
  local published_at=null
  [ -n "$published" ] && published_at="now() - make_interval(secs => $published)"
  psql_q "with u as (insert into users (name, email) values ('Ana Souza', '$email') returning id, created_at),
    e as (insert into users_outbox (user_id, event_type, payload, status, published_at, available_at, created_at)
      select id, 'user.registered',
        jsonb_build_object('user_id', id, 'name', 'Ana Souza', 'email', '$email',
          'occurred_at', to_char(created_at at time zone 'utc', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')),
        '$status', $published_at, now() + make_interval(secs => $available), now() - make_interval(secs => $created)
      from u returning id)
    select id from e"
}

# Troca valores no .env da cópia de trabalho e recria a stack, com o que depende deles. Sem
# `sed -i`, que no macOS espera um sufixo e deixaria o .env como estava.
rg_set_env() {
  local pair
  for pair in "$@"; do
    sed "s|^${pair%%=*}=.*|$pair|" "$WORK/.env" > "$WORK/.env.new" && mv "$WORK/.env.new" "$WORK/.env" || return 1
  done
  mkq "up-$SUITE_STACK"
}
rg_default_env() {
  rg_set_env OUTBOX_MAX_ATTEMPTS=5 OUTBOX_BACKOFF_BASE_SECONDS=30 OUTBOX_REPUBLISH_AFTER_SECONDS=300 OUTBOX_BATCH_SIZE=100
}

# Com o worker parado, a mensagem fica na fila para ser lida.
rg_with_queued_job() {
  rg_reset
  stack_worker_stop
  rg_register secreta@example.com 'Nome Secreto' >/dev/null
  rg_wait_for 15 rg_queue_has
  QUEUED="$(stack_queued_messages)"
  QUEUED_USER="$(jq -r '.data.id' "$WORK/r.body")"
  QUEUED_ID="$(rg_event id secreta@example.com)"
  stack_worker_start
}
