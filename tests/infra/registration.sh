# POST /users, Horizon e o e-mail de boas-vindas (.specs/features/laravel-registration-email e laravel-outbox).
# Carregado por run.sh. Roda contra PostgreSQL, Redis, Horizon e Mailpit de verdade.

# shellcheck source=/dev/null
source "$TESTS/registration-helpers.sh"

CONFLICT_BODY='{"message":"The email has already been taken.","errors":[{"field":"email","code":"already_taken","message":"The email has already been taken."}]}'
LIMITED_BODY='{"message":"Too many registration attempts. Try again later.","errors":[]}'
FAILED_BODY='{"message":"Internal server error.","errors":[]}'

t_rg0_up() {
  mkq up-laravel || { note "make up-laravel saiu com erro"; return 1; }
}
check "RG0 stack up for the registration tests" t_rg0_up

# --- POST /users ---

t_rg1_created() {
  local status ok=0
  rg_reset
  status="$(rg_post '{"name":"Ana Souza","email":"ana@example.com"}')"
  [ "$status" = 201 ] || { note "status $status: $(rg_body)"; return 1; }
  jq -e '.data.id | test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")' "$WORK/r.body" >/dev/null || { note "id: $(rg_body)"; ok=1; }
  jq -e '.data.created_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$WORK/r.body" >/dev/null || { note "created_at: $(rg_body)"; ok=1; }
  jq -e '.data.name == "Ana Souza" and .data.email == "ana@example.com" and .message == "User registered successfully."' "$WORK/r.body" >/dev/null || { note "corpo: $(rg_body)"; ok=1; }
  [ "$(jq -c 'keys' "$WORK/r.body")" = '["data","message"]' ] || { note "chaves: $(jq -c 'keys' "$WORK/r.body")"; ok=1; }
  [ "$(jq -c '.data | keys' "$WORK/r.body")" = '["created_at","email","id","name"]' ] || { note "chaves de data: $(jq -c '.data | keys' "$WORK/r.body")"; ok=1; }
  return $ok
}
check "RG1 post users created body" t_rg1_created

t_rg2_normalizes() {
  local status ok=0
  rg_reset
  status="$(rg_post '{"name":"  Ana  ","email":"  ANA@Example.COM "}')"
  [ "$status" = 201 ] || { note "status $status: $(rg_body)"; return 1; }
  [ "$(psql_q 'select name, email from users')" = 'Ana|ana@example.com' ] || { note "users: $(psql_q 'select name, email from users')"; ok=1; }
  [ "$(rg_events)" = 1 ] || { note "users_outbox: $(rg_events)"; ok=1; }
  return $ok
}
check "RG2 post users normalizes and writes one event" t_rg2_normalizes

# Um e-mail válido com exatamente N caracteres: parte local de 64, rótulos de até 60.
rg_long_email() {
  local n="$1" rest domain=''
  rest=$((n - 65 - 4))
  while [ "$rest" -gt 61 ]; do
    domain="$domain$(printf 'b%.0s' $(seq 1 60))."
    rest=$((rest - 61))
  done
  domain="$domain$(printf 'c%.0s' $(seq 1 "$rest")).com"
  printf '%s@%s' "$(printf 'a%.0s' $(seq 1 64))" "$domain"
}

# rg_invalid <corpo> <field> <code> <message>
rg_invalid() {
  local expected status
  expected="$(jq -cn --arg f "$2" --arg c "$3" --arg m "$4" '{message: "The given data was invalid.", errors: [{field: $f, code: $c, message: $m}]}')"
  status="$(rg_post "$1")"
  [ "$status" = 422 ] || { note "$1: status $status"; return 1; }
  [ "$(jq -c . "$WORK/r.body")" = "$expected" ] || { note "${1:0:60}: $(rg_body)"; return 1; }
}

t_rg3_validation() {
  local ok=0 long_name name_255 mail='ana@example.com'
  rg_reset
  long_name="$(printf 'a%.0s' $(seq 1 256))"
  name_255="$(printf 'a%.0s' $(seq 1 255))"
  local name_required='The name field is required.' email_required='The email field is required.' invalid='The email must be a valid email address.'
  rg_invalid "{\"email\":\"$mail\"}" name required "$name_required" || ok=1
  rg_invalid "{\"name\":\"\",\"email\":\"$mail\"}" name required "$name_required" || ok=1
  rg_invalid "{\"name\":\"   \",\"email\":\"$mail\"}" name required "$name_required" || ok=1
  rg_invalid "{\"name\":123,\"email\":\"$mail\"}" name required "$name_required" || ok=1
  rg_invalid "{\"name\":\"$long_name\",\"email\":\"$mail\"}" name too_long 'The name must not exceed 255 characters.' || ok=1
  rg_invalid '{"name":"Ana"}' email required "$email_required" || ok=1
  rg_invalid '{"name":"Ana","email":""}' email required "$email_required" || ok=1
  rg_invalid '{"name":"Ana","email":123}' email required "$email_required" || ok=1
  rg_invalid '{"name":"Ana","email":"não-é-email"}' email invalid_format "$invalid" || ok=1
  rg_invalid '{"name":"Ana","email":"ana@"}' email invalid_format "$invalid" || ok=1
  rg_invalid "{\"name\":\"Ana\",\"email\":\"$(rg_long_email 255)\"}" email too_long 'The email must not exceed 254 characters.' || ok=1
  [ "$(rg_register "$mail" "$name_255")" = 201 ] || { note "nome com 255: $(rg_body)"; ok=1; }
  [ "$(rg_register "$(rg_long_email 254)")" = 201 ] || { note "e-mail com 254: $(rg_body)"; ok=1; }
  return $ok
}
check "RG3 post users validation table" t_rg3_validation

t_rg4_malformed() {
  local status expected
  expected='{"message":"The given data was invalid.","errors":[{"field":"name","code":"required","message":"The name field is required."},{"field":"email","code":"required","message":"The email field is required."}]}'
  status="$(rg_post '{"name": ')"
  [ "$status" = 422 ] || { note "status $status"; return 1; }
  [ "$(jq -c . "$WORK/r.body")" = "$expected" ] || { note "corpo: $(rg_body)"; return 1; }
}
check "RG4 post users malformed json" t_rg4_malformed

t_rg5_invalid_touches_nothing() {
  local ok=0
  rg_reset
  [ "$(rg_post '{"name":"","email":"ana@example.com"}')" = 422 ] || { note "status: $(rg_body)"; ok=1; }
  [ "$(rg_users)" = 0 ] || { note "users tem linhas"; ok=1; }
  [ "$(redis_q DBSIZE)" = 0 ] || { note "redis-limiter tem chaves"; ok=1; }
  return $ok
}
check "RG5 invalid body touches nothing" t_rg5_invalid_touches_nothing

t_rg6_extra_fields() {
  rg_reset
  [ "$(rg_post '{"name":"Ana","email":"ana@example.com","role":"admin","id":"x"}')" = 201 ] || { note "status: $(rg_body)"; return 1; }
  [ "$(jq -c '.data | keys' "$WORK/r.body")" = '["created_at","email","id","name"]' ] || { note "corpo: $(rg_body)"; return 1; }
}
check "RG6 extra fields are ignored" t_rg6_extra_fields

t_rg7_conflict() {
  local ok=0 jobs_before
  rg_reset
  rg_register ana@example.com >/dev/null
  rg_wait_for 30 rg_mail_arrived ana@example.com
  jobs_before="$(curl -s localhost:8080/horizon/api/stats | jq -r '.recentJobs')"
  [ "$(rg_register ANA@EXAMPLE.COM)" = 409 ] || { note "status: $(rg_body)"; ok=1; }
  [ "$(rg_body)" = "$CONFLICT_BODY" ] || { note "corpo: $(rg_body)"; ok=1; }
  [ "$(rg_users)" = 1 ] || { note "users: $(rg_users)"; ok=1; }
  [ "$(rg_events)" = 1 ] || { note "users_outbox: $(rg_events)"; ok=1; }
  sleep 3
  [ "$(curl -s localhost:8080/horizon/api/stats | jq -r '.recentJobs')" = "$jobs_before" ] || { note "job novo depois do 409"; ok=1; }
  return $ok
}
check "RG7 repeated email conflicts" t_rg7_conflict

t_rg8_parallel_same_email() {
  local statuses
  rg_reset
  statuses="$(printf '%s\n' 1 2 | xargs -P 2 -I{} curl -s -o /dev/null --max-time 10 -w '%{http_code}\n' -X POST localhost:8080/users \
    -H 'Content-Type: application/json' -d '{"name":"Ana","email":"ana@example.com"}' | sort | tr '\n' ' ')"
  [ "$statuses" = '201 409 ' ] || { note "status: $statuses"; return 1; }
  [ "$(rg_users)" = 1 ] || { note "users: $(rg_users)"; return 1; }
}
check "RG8 parallel same email" t_rg8_parallel_same_email

t_rg9_attempt_limit() {
  local i got='' retry ok=0
  rg_reset
  for i in 1 2 3 4 5 6; do got="$got$(rg_register ana@example.com) "; done
  [ "$got" = '201 409 409 409 409 429 ' ] || { note "sequência: $got"; ok=1; }
  retry="$(rg_header Retry-After)"
  [ "$retry" -ge 1 ] 2>/dev/null && [ "$retry" -le 900 ] || { note "Retry-After: '$retry'"; ok=1; }
  [ "$(rg_body)" = "$LIMITED_BODY" ] || { note "corpo: $(rg_body)"; ok=1; }
  return $ok
}
check "RG9 attempt limit sequence" t_rg9_attempt_limit

t_rg10_limit_without_database() {
  local i status
  rg_reset
  for i in 1 2 3 4 5; do rg_register ana@example.com >/dev/null; done
  docker stop "$(container postgres)" >/dev/null
  status="$(rg_register ana@example.com)"
  docker start "$(container postgres)" >/dev/null
  rg_shared_back
  [ "$status" = 429 ] || { note "status $status: $(rg_body)"; return 1; }
}
check "RG10 attempt limit never reads the database" t_rg10_limit_without_database

t_rg11_forwarded_for() {
  local i status
  rg_reset
  for i in 1 2 3 4 5 6; do
    status="$(rg_post '{"name":"Ana","email":"ana@example.com"}' -H "X-Forwarded-For: 198.51.100.$i")"
  done
  [ "$status" = 429 ] || { note "6ª tentativa: $status"; return 1; }
}
check "RG11 forwarded for is ignored" t_rg11_forwarded_for

t_rg12_per_ip_and_email() {
  local i status
  rg_reset
  for i in 1 2 3 4 5 6; do rg_register ana@example.com >/dev/null; done
  # De dentro da rede: outro IP, o do php-fpm, chega ao mesmo nginx.
  status="$(docker exec "$RG_FPM" php -r '
    $ctx = stream_context_create(["http" => ["method" => "POST", "ignore_errors" => true,
      "header" => "Content-Type: application/json\r\n", "content" => "{\"name\":\"Ana\",\"email\":\"ana@example.com\"}"]]);
    @file_get_contents("http://nginx/users", false, $ctx);
    echo explode(" ", http_get_last_response_headers()[0])[1];')"
  [ "$status" = 409 ] || { note "de outro IP: $status"; return 1; }
}
check "RG12 limit is per ip and email" t_rg12_per_ip_and_email

t_rg13_ip_quota() {
  local i got=0 status
  rg_reset
  for i in $(seq 1 20); do
    [ "$(rg_register "user$i@example.com")" = 201 ] && got=$((got + 1))
  done
  [ "$got" = 20 ] || { note "201: $got"; return 1; }
  status="$(rg_register user21@example.com)"
  [ "$status" = 429 ] || { note "21º: $status"; return 1; }
  [ "$(rg_body)" = "$LIMITED_BODY" ] || { note "corpo: $(rg_body)"; return 1; }
  [ "$(rg_users)" = 20 ] || { note "users: $(rg_users)"; return 1; }
}
check "RG13 ip quota" t_rg13_ip_quota

t_rg14_conflict_keeps_quota() {
  local before
  rg_reset
  rg_register ana@example.com >/dev/null
  before="$(rg_quota_value)"
  [ "$before" = 1 ] || { note "cota depois do 201: $before"; return 1; }
  [ "$(rg_register ana@example.com)" = 409 ] || { note "status: $(rg_body)"; return 1; }
  [ "$(rg_quota_value)" = "$before" ] || { note "cota depois do 409: $(rg_quota_value)"; return 1; }
}
check "RG14 conflict does not consume quota" t_rg14_conflict_keeps_quota

t_rg15_parallel_quota() {
  local statuses created limited
  rg_reset
  statuses="$(seq 1 50 | xargs -P 25 -I{} curl -s -o /dev/null --max-time 30 -w '%{http_code}\n' -X POST localhost:8080/users \
    -H 'Content-Type: application/json' -d '{"name":"Ana","email":"p{}@example.com"}')"
  created="$(grep -c '^201$' <<< "$statuses")"
  limited="$(grep -c '^429$' <<< "$statuses")"
  [ "$created" = 20 ] && [ "$limited" = 30 ] || { note "201: $created, 429: $limited, todos: $(sort <<< "$statuses" | uniq -c | tr '\n' ' ')"; return 1; }
  [ "$(rg_users)" = 20 ] || { note "users: $(rg_users)"; return 1; }
  [ "$(rg_events)" = 20 ] || { note "users_outbox: $(rg_events)"; return 1; }
}
check "RG15 ip quota holds in parallel" t_rg15_parallel_quota

t_rg16_lua_scripts() {
  local n=0 name ok=0 tmp="$WORK/lua"
  mkdir -p "$tmp"
  awk -v dir="$tmp" '/^```lua$/{n++; on=1; next} /^```$/{on=0; next} on{print > (dir "/" n ".lua")}' "$WORK/docs/api-contract.md"
  for name in attempts reserve release; do
    n=$((n + 1))
    cmp -s "$tmp/$n.lua" "$WORK/apis/laravel/app-modules/users/resources/lua/$name.lua" \
      || { note "$name.lua difere do bloco $n do contrato"; ok=1; }
  done
  return $ok
}
check "RG16 lua scripts match the contract" t_rg16_lua_scripts

t_rg17_limiter_down() {
  local out code secs body ok=0
  rg_reset
  docker stop "$(container redis-limiter)" >/dev/null
  out="$(rg_timed_post '{"name":"Ana","email":"ana@example.com"}')"
  code="${out% *}"; secs="${out#* }"; body="$(rg_body)"
  docker start "$(container redis-limiter)" >/dev/null
  rg_shared_back
  [ "$code" = 500 ] || { note "status $code"; ok=1; }
  [ "$body" = "$FAILED_BODY" ] || { note "corpo: $body"; ok=1; }
  rg_under_3s "$secs" || { note "levou ${secs}s"; ok=1; }
  [ "$(rg_users)" = 0 ] || { note "users tem linhas"; ok=1; }
  return $ok
}
check "RG17 limiter down answers 500" t_rg17_limiter_down

t_rg18_database_down() {
  local out code secs body before after ok=0
  rg_reset
  rg_register ana@example.com >/dev/null
  before="$(rg_quota_value)"
  docker stop "$(container postgres)" >/dev/null
  out="$(rg_timed_post '{"name":"Bia","email":"bia@example.com"}')"
  code="${out% *}"; secs="${out#* }"; body="$(rg_body)"
  after="$(rg_quota_value)"
  docker start "$(container postgres)" >/dev/null
  rg_shared_back
  [ "$code" = 500 ] || { note "status $code"; ok=1; }
  [ "$body" = "$FAILED_BODY" ] || { note "corpo: $body"; ok=1; }
  rg_under_3s "$secs" || { note "levou ${secs}s"; ok=1; }
  [ "$after" = "$before" ] || { note "cota: antes $before, depois $after"; ok=1; }
  grep -qx 'APP_DEBUG=true' "$WORK/.env" || { note ".env sem APP_DEBUG=true"; ok=1; }
  return $ok
}
check "RG18 database down answers 500 and releases" t_rg18_database_down

t_rg19_queue_down() {
  local out code secs since logs before after pending ok=0
  rg_reset
  rg_register ana@example.com >/dev/null
  before="$(rg_quota_value)"
  # --since tem resolução de segundo: a espera deixa de fora o log do teste anterior.
  sleep 1
  since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  docker stop "$RG_RD" >/dev/null
  out="$(rg_timed_post '{"name":"Bia","email":"bia@example.com"}')"
  code="${out% *}"; secs="${out#* }"
  after="$(rg_quota_value)"
  pending="$(rg_event status bia@example.com)"
  logs="$(docker logs --since "$since" "$RG_FPM" 2>&1)"
  docker start "$RG_RD" >/dev/null
  rg_wait_for 60 rg_healthy "$RG_RD"
  rg_wait_for 90 rg_healthy "$RG_HZ"
  [ "$code" = 201 ] || { note "status $code: $(rg_body)"; ok=1; }
  rg_under_3s "$secs" || { note "levou ${secs}s"; ok=1; }
  rg_user_exists bia@example.com || { note "usuário não foi gravado"; ok=1; }
  [ "$pending" = pending ] || { note "evento: $pending"; ok=1; }
  grep -qF '.ERROR' <<< "$logs" && { note "erro no log do php-fpm: $logs"; ok=1; }
  [ "$after" = "$((before + 1))" ] || { note "cota: antes $before, depois $after"; ok=1; }
  return $ok
}
check "RG19 queue down still answers 201" t_rg19_queue_down

t_rg20_preflight() {
  local headers origin ok=0
  origin="$(grep '^CORS_ALLOWED_ORIGIN=' "$WORK/.env" | cut -d= -f2-)"
  headers="$(curl -s -D - -o /dev/null --max-time 10 -X OPTIONS localhost:8080/users -H "Origin: $origin" \
    -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type' | tr -d '\r')"
  grep -qE '^HTTP/[0-9.]+ 204' <<< "$headers" || { note "status: $(head -1 <<< "$headers")"; ok=1; }
  grep -qix "access-control-allow-origin: $origin" <<< "$headers" || { note "sem a origem: $headers"; ok=1; }
  grep -iE '^access-control-allow-methods:' <<< "$headers" | grep -qF POST || { note "sem POST: $headers"; ok=1; }
  return $ok
}
check "RG20 cors preflight" t_rg20_preflight

t_rg21_cors_response() {
  local origin ok=0
  rg_reset
  origin="$(grep '^CORS_ALLOWED_ORIGIN=' "$WORK/.env" | cut -d= -f2-)"
  rg_post '{"name":"Ana","email":"ana@example.com"}' -H "Origin: $origin" >/dev/null
  [ "$(rg_header Access-Control-Allow-Origin)" = "$origin" ] || { note "origem: '$(rg_header Access-Control-Allow-Origin)'"; ok=1; }
  rg_header Access-Control-Expose-Headers | grep -qF Retry-After || { note "sem Retry-After em Expose-Headers"; ok=1; }
  rg_post '{"name":"Bia","email":"bia@example.com"}' -H 'Origin: http://evil.test' >/dev/null
  [ -z "$(rg_header Access-Control-Allow-Origin)" ] || { note "outra origem recebeu '$(rg_header Access-Control-Allow-Origin)'"; ok=1; }
  return $ok
}
check "RG21 cors response headers" t_rg21_cors_response

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

# Com o worker parado, o job fica na fila para ser lido.
rg_with_queued_job() {
  rg_reset
  docker stop "$RG_HZ" >/dev/null
  rg_register secreta@example.com 'Nome Secreto' >/dev/null
  rg_wait_for 15 rg_queue_has
  QUEUED="$(docker exec "$RG_RD" redis-cli LRANGE queues:registration-emails 0 -1)"
  QUEUED_USER="$(jq -r '.data.id' "$WORK/r.body")"
  QUEUED_ID="$(rg_event id secreta@example.com)"
  docker start "$RG_HZ" >/dev/null
  rg_wait_for 90 rg_healthy "$RG_HZ"
}

t_rg23_only_id() {
  local ok=0
  rg_with_queued_job
  [ -n "$QUEUED" ] || { note "fila vazia"; return 1; }
  [ -n "$QUEUED_ID" ] || { note "evento sem id"; return 1; }
  grep -qF "$QUEUED_ID" <<< "$QUEUED" || { note "job sem o id do evento"; ok=1; }
  grep -qF "$QUEUED_USER" <<< "$QUEUED" && { note "job com o id do usuário"; ok=1; }
  grep -qF 'secreta@example.com' <<< "$QUEUED" && { note "job com o e-mail"; ok=1; }
  grep -qF 'Nome Secreto' <<< "$QUEUED" && { note "job com o nome"; ok=1; }
  return $ok
}
check "RG23 job carries only the event id" t_rg23_only_id

t_rg24_retries() {
  local ok=0
  rg_with_queued_job
  [ "$(jq -r '.maxTries' <<< "$QUEUED")" = 1 ] || { note "maxTries: $(jq -r '.maxTries' <<< "$QUEUED")"; ok=1; }
  [ "$(jq -r '.backoff' <<< "$QUEUED")" = null ] || { note "backoff: $(jq -r '.backoff' <<< "$QUEUED")"; ok=1; }
  return $ok
}
check "RG24 job has no native retries" t_rg24_retries

t_rg25_queue_restart() {
  rg_reset
  docker stop "$RG_RD" >/dev/null
  docker start "$RG_RD" >/dev/null
  rg_wait_for 60 rg_healthy "$RG_RD" || { note "redis não voltou"; return 1; }
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; return 1; }
  rg_wait_for 60 rg_mail_arrived ana@example.com || { note "e-mail não chegou; horizon: $(health "$RG_HZ")"; return 1; }
}
check "RG25 worker survives queue restart" t_rg25_queue_restart

t_rg26_smtp_returns() {
  local ok=0
  rg_set_env OUTBOX_MAX_ATTEMPTS=5 OUTBOX_BACKOFF_BASE_SECONDS=2 || { note "make up-laravel saiu com erro"; return 1; }
  rg_reset
  docker stop "$(container mailpit)" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  rg_attempts_rose() { [ "$(rg_event attempts ana@example.com)" -ge 1 ]; }
  rg_wait_for 30 rg_attempts_rose || { note "attempts: $(rg_event attempts ana@example.com)"; ok=1; }
  [ "$(rg_event status ana@example.com)" != failed ] || { note "esgotou antes de o SMTP voltar"; ok=1; }
  docker start "$(container mailpit)" >/dev/null
  rg_shared_back
  rg_wait_for 60 rg_mail_arrived ana@example.com || { note "e-mail não chegou"; ok=1; }
  rg_wait_for 10 rg_event_is processed ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  rg_default_env
  return $ok
}
check "RG26 mail arrives after smtp returns" t_rg26_smtp_returns

t_rg27_watch_updates_worker() {
  local before i ok=0 view="$WORK/apis/laravel/app-modules/outbox/resources/views/welcome-text.blade.php" saved found=1 pid
  saved="$(cat "$view")"
  rg_reset
  before="$(docker ps -aq --no-trunc --filter "name=^$RG_FPM\$")"
  set -m
  make --no-print-directory -C "$WORK" watch-laravel > "$WORK/watch.log" 2>&1 &
  pid=$!
  set +m
  rg_wait_for 300 grep -q 'Watch enabled' "$WORK/watch.log" || { note "watch não ficou pronto: $(tail -3 "$WORK/watch.log")"; ok=1; }
  printf 'Texto novo vindo do watch.\n' >> "$view"
  for i in $(seq 1 12); do
    sleep 5
    rg_register "w$i@example.com" >/dev/null
    rg_wait_for 8 rg_mail_arrived "w$i@example.com" \
      && rg_mail_field "w$i@example.com" '.Text' | grep -qF 'Texto novo vindo do watch.' && { found=0; break; }
  done
  [ "$found" = 0 ] || { note "texto novo não saiu em 60 s"; ok=1; }
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

# --- E-mail de boas-vindas ---

t_rg29_mail_arrives() {
  local ok=0
  rg_reset
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; return 1; }
  rg_wait_for 30 rg_mail_arrived ana@example.com || { note "e-mail não chegou"; return 1; }
  [ "$(rg_mail_count ana@example.com)" = 1 ] || { note "mensagens: $(rg_mail_count ana@example.com)"; ok=1; }
  [ "$(rg_mail_field ana@example.com '.From.Address')" = no-reply@cadastro-feliz.local ] || { note "remetente: $(rg_mail_field ana@example.com '.From.Address')"; ok=1; }
  [ "$(rg_mail_field ana@example.com '.Subject')" = 'Boas-vindas ao Cadastro Feliz!' ] || { note "assunto: $(rg_mail_field ana@example.com '.Subject')"; ok=1; }
  return $ok
}
check "RG29 welcome mail arrives" t_rg29_mail_arrives

t_rg30_mail_text() {
  local text html line ok=0
  rg_reset
  rg_register ana@example.com 'Ana Souza' >/dev/null
  rg_wait_for 30 rg_mail_arrived ana@example.com || { note "e-mail não chegou"; return 1; }
  text="$(rg_mail_field ana@example.com '.Text')"
  html="$(rg_mail_field ana@example.com '.HTML')"
  for line in 'Olá, Ana Souza!' 'Que bom ter você por aqui. Seu cadastro no Cadastro Feliz foi concluído com sucesso.' \
    'Não é preciso fazer mais nada.' 'Um abraço,' 'Equipe Cadastro Feliz'; do
    grep -qF "$line" <<< "$text" || { note "texto sem '$line'"; ok=1; }
    grep -qF "$line" <<< "$html" || { note "HTML sem '$line'"; ok=1; }
  done
  return $ok
}
check "RG30 welcome mail text" t_rg30_mail_text

t_rg31_mail_resources() {
  local html ok=0
  rg_reset
  rg_register ana@example.com >/dev/null
  rg_wait_for 30 rg_mail_arrived ana@example.com || { note "e-mail não chegou"; return 1; }
  html="$(rg_mail_field ana@example.com '.HTML')"
  grep -qiF '<img' <<< "$html" && { note "HTML com <img"; ok=1; }
  grep -qiF '<script' <<< "$html" && { note "HTML com <script"; ok=1; }
  grep -qiE 'https?://' <<< "$html" && { note "HTML com endereço externo"; ok=1; }
  return $ok
}
check "RG31 welcome mail has no external resources" t_rg31_mail_resources

t_rg32_mail_escapes() {
  local html
  rg_reset
  rg_register ana@example.com 'Ana <b>Souza</b>' >/dev/null
  rg_wait_for 30 rg_mail_arrived ana@example.com || { note "e-mail não chegou"; return 1; }
  html="$(rg_mail_field ana@example.com '.HTML')"
  grep -qF 'Ana &lt;b&gt;Souza&lt;/b&gt;' <<< "$html" || { note "nome não escapado"; return 1; }
  grep -qF 'Ana <b>Souza' <<< "$html" && { note "nome interpretado"; return 1; }
  return 0
}
check "RG32 welcome mail escapes the name" t_rg32_mail_escapes

t_rg33_conflict_no_mail() {
  rg_reset
  rg_register ana@example.com >/dev/null
  rg_wait_for 30 rg_mail_arrived ana@example.com || { note "e-mail não chegou"; return 1; }
  [ "$(rg_register ana@example.com)" = 409 ] || { note "status: $(rg_body)"; return 1; }
  sleep 10
  [ "$(rg_mail_count ana@example.com)" = 1 ] || { note "mensagens: $(rg_mail_count ana@example.com)"; return 1; }
}
check "RG33 conflict sends no mail" t_rg33_conflict_no_mail
