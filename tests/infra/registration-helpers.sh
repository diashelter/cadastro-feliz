# Ajudantes de registration.sh e limitations.sh, que também rodam sozinhos, como no CI.

RG_NG=cadastro-feliz-laravel-nginx-1
RG_FPM=cadastro-feliz-laravel-php-fpm-1
RG_HZ=cadastro-feliz-laravel-horizon-1
RG_RD=cadastro-feliz-laravel-redis-1
RG_WATCH_PID=

rg_wait_for() {
  local secs="$1" i; shift
  for ((i = 0; i < secs; i++)); do "$@" && return 0; sleep 1; done
  "$@"
}
rg_healthy() { [ "$(health "$1")" = healthy ]; }
rg_shared_back() { rg_wait_for 60 shared_healthy; }

# Banco, contadores e caixa de e-mail vazios: cada teste parte do mesmo estado.
rg_reset() {
  psql_q 'truncate users cascade' >/dev/null
  redis_q FLUSHALL >/dev/null
  docker exec "$RG_RD" redis-cli FLUSHALL >/dev/null
  curl -s -X DELETE --max-time 10 localhost:8025/api/v1/messages >/dev/null
  curl -s -X DELETE --max-time 10 localhost:8080/horizon/api/jobs/failed >/dev/null
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

# Troca valores no .env da cópia de trabalho e recria o que depende deles.
rg_set_env() {
  local pair
  for pair in "$@"; do
    sed -i "s|^${pair%%=*}=.*|$pair|" "$WORK/.env"
  done
  mkq up-laravel
}
rg_default_env() {
  rg_set_env OUTBOX_MAX_ATTEMPTS=5 OUTBOX_BACKOFF_BASE_SECONDS=30
}
