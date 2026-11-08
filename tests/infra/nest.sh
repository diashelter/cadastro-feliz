# Casos internos da stack NestJS (decisão 23): os containers, GET /health, o fluxo de edição, o
# npm, os testes unitários, o relay no worker e as opções do job. Os casos de contrato, que
# valem para toda stack, ficam em registration.sh e outbox.sh. Plano e checks em
# .specs/features/nestjs-stack. Carregado por run.sh. Roda contra PostgreSQL, Redis e Mailpit
# de verdade.

SUITE_STACK=nest
# shellcheck source=/dev/null
source "$TESTS/adapters/nest.sh"
# shellcheck source=/dev/null
source "$TESTS/registration-helpers.sh"

NS="$WORK/apis/nestjs"
NS_IMAGE=cadastro-feliz-nest-api
OB_PG="$(container postgres)"
OB_MAILPIT="$(container mailpit)"
RG4_BODY='{"message":"The given data was invalid.","errors":[{"field":"name","code":"required","message":"The name field is required."},{"field":"email","code":"required","message":"The email field is required."}]}'
NS_WATCH_PID=

ns_id() { docker ps -aq --no-trunc --filter "name=^$1\$"; }
ns_ids() { echo "$(ns_id "$RG_API") $(ns_id "$RG_WK") $(ns_id "$RG_RD")"; }
ns_healthy() {
  local c
  for c in "$RG_API" "$RG_WK" "$RG_RD"; do [ "$(health "$c")" = healthy ] || return 1; done
}
api() { curl -s --max-time 10 "localhost:8080$1"; }
api_status() { curl -s -o /dev/null --max-time 10 -w '%{http_code}' "$@"; }
# A versão de um arquivo para comparar inteira, antes e depois (L-003).
digest() { sha256sum < "$1"; }
save() { cp -p "$1" "$1.nssave"; }
restore() { mv -f "$1.nssave" "$1"; }
# Troca um texto num arquivo sem trocar o inode, que o watch acompanha. Sem `sed -i`.
replace_in() {
  local file="$1" from="$2" to="$3"
  perl -pe "s/\Q$from\E/$to/g" "$file" > "$WORK/replace.tmp" && cat "$WORK/replace.tmp" > "$file"
}
table_digest() { psql_q "select md5(coalesce(string_agg(t::text, ',' order by t::text), '')) from $1 t"; }
# health_within_limit <corpo esperado>: /health responde 503, com esse corpo, em menos de 3 s.
health_within_limit() {
  local expected="$1" out code secs body ok=0
  out="$(curl -s -D "$WORK/limit.headers" -o "$WORK/limit.body" --max-time 10 -w '%{http_code} %{time_total}' localhost:8080/health)"
  code="${out% *}"; secs="${out#* }"; body="$(cat "$WORK/limit.body")"
  [ "$code" = 503 ] || { note "status $code"; ok=1; }
  [ "$body" = "$expected" ] || { note "corpo: $body"; ok=1; }
  rg_under_3s "$secs" || { note "levou ${secs}s"; ok=1; }
  grep -qiE '^content-type: application/json' "$WORK/limit.headers" || { note "503 sem Content-Type JSON"; ok=1; }
  grep -qiE '^cache-control: no-store' < <(tr -d '\r' < "$WORK/limit.headers") || { note "503 sem Cache-Control"; ok=1; }
  return $ok
}
ns_relay_once() { docker exec "$RG_WK" node dist/scripts/relay-once.js 2>&1; }
ns_scheduler() { docker exec "$RG_WK" node dist/scripts/queue-control.js scheduler; }
ns_counter() { stack_jobs_created; }

# --- S1 - Stack no ar e GET /health ---

t_ns1_clean_clone() {
  local ok=0 services ids
  destroy_environment
  fake_stack go apis/golang
  mkq up-go || { note "make up-go saiu com erro"; return 1; }
  mkq up-nest || { note "make up-nest saiu com erro"; return 1; }
  [ -z "$(project_containers cadastro-feliz-go)" ] || { note "a stack go ficou no ar"; ok=1; }
  services="$(docker ps -a --filter label=com.docker.compose.project=cadastro-feliz-nest --format '{{.Label "com.docker.compose.service"}}' | sort | tr '\n' ' ')"
  [ "$services" = 'api redis worker ' ] || { note "serviços: $services"; ok=1; }
  ns_healthy || { note "api $(health "$RG_API"), worker $(health "$RG_WK"), redis $(health "$RG_RD")"; ok=1; }
  ids="$(ns_ids)"
  mkq up-nest || { note "segundo make up-nest saiu com erro"; ok=1; }
  [ "$(ns_ids)" = "$ids" ] || { note "os containers mudaram na segunda subida"; ok=1; }
  rm -rf "$WORK/apis/golang"
  return $ok
}
check "NS1 up-nest on clean clone" t_ns1_clean_clone

t_ns2_ports_and_image() {
  local ok=0 c bound
  for c in "$RG_API" "$RG_WK" "$RG_RD"; do
    bound="$(docker inspect -f '{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{$p}}={{.HostPort}} {{end}}{{end}}' "$c" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')"
    if [ "$c" = "$RG_API" ]; then
      [ "$bound" = '8080/tcp=8080 ' ] || { note "portas da api: '$bound'"; ok=1; }
    else
      [ -z "$bound" ] || { note "$c publica $bound"; ok=1; }
    fi
  done
  [ "$(docker inspect -f '{{.Config.Image}}' "$RG_API")" = "$NS_IMAGE" ] || { note "imagem da api"; ok=1; }
  [ "$(docker inspect -f '{{.Config.Image}}' "$RG_WK")" = "$NS_IMAGE" ] || { note "imagem do worker"; ok=1; }
  [ "$(docker inspect -f '{{.Image}}' "$RG_API")" = "$(docker inspect -f '{{.Image}}' "$RG_WK")" ] || { note "api e worker em imagens diferentes"; ok=1; }
  return $ok
}
check "NS2 nest published ports and shared image" t_ns2_ports_and_image

t_ns3_health_ok() {
  local ok=0 users events code
  rg_reset
  # Um evento terminal: o relay nunca o seleciona, então só o /health poderia mudá-lo.
  ob_seed ana@example.com processed >/dev/null
  users="$(table_digest users)"; events="$(table_digest users_outbox)"
  code="$(curl -s -D "$WORK/h.headers" -o "$WORK/h.body" --max-time 10 -w '%{http_code}' localhost:8080/health)"
  [ "$code" = 200 ] || { note "status $code"; ok=1; }
  [ "$(cat "$WORK/h.body")" = '{"status":"ok","checks":{"database":"ok","limiter":"ok"}}' ] || { note "corpo: $(cat "$WORK/h.body")"; ok=1; }
  tr -d '\r' < "$WORK/h.headers" | grep -qiE '^content-type: application/json' || { note "sem Content-Type JSON"; ok=1; }
  tr -d '\r' < "$WORK/h.headers" | grep -qix 'cache-control: no-store' || { note "sem Cache-Control: no-store"; ok=1; }
  [ "$(table_digest users)" = "$users" ] || { note "users mudou"; ok=1; }
  [ "$(table_digest users_outbox)" = "$events" ] || { note "users_outbox mudou"; ok=1; }
  return $ok
}
check "NS3 health ok with real dependencies" t_ns3_health_ok

t_ns4_health_stopped() {
  local ok=0
  docker stop "$(container redis-limiter)" >/dev/null
  health_within_limit '{"status":"fail","checks":{"database":"ok","limiter":"fail"}}' || { note "só o limiter parado"; ok=1; }
  docker stop "$OB_PG" >/dev/null
  health_within_limit '{"status":"fail","checks":{"database":"fail","limiter":"fail"}}' || { note "os dois parados"; ok=1; }
  docker start "$(container redis-limiter)" >/dev/null
  rg_wait_for 30 rg_healthy "$(container redis-limiter)"
  health_within_limit '{"status":"fail","checks":{"database":"fail","limiter":"ok"}}' || { note "só o postgres parado"; ok=1; }
  sleep 6
  rg_healthy "$RG_API" || { note "api ficou $(health "$RG_API")"; ok=1; }
  docker start "$OB_PG" >/dev/null
  rg_shared_back
  rg_wait_for 30 bash -c '[ "$(curl -s -o /dev/null -w "%{http_code}" localhost:8080/health)" = 200 ]' || { note "/health não voltou a 200"; ok=1; }
  return $ok
}
check "NS4 health 503 when dependencies stop" t_ns4_health_stopped

t_ns5_health_paused() {
  local ok=0
  docker pause "$OB_PG" >/dev/null
  health_within_limit '{"status":"fail","checks":{"database":"fail","limiter":"ok"}}' || { note "postgres pausado"; ok=1; }
  docker unpause "$OB_PG" >/dev/null
  docker pause "$(container redis-limiter)" >/dev/null
  health_within_limit '{"status":"fail","checks":{"database":"ok","limiter":"fail"}}' || { note "limiter pausado"; ok=1; }
  docker unpause "$(container redis-limiter)" >/dev/null
  rg_shared_back
  rg_wait_for 30 bash -c '[ "$(curl -s -o /dev/null -w "%{http_code}" localhost:8080/health)" = 200 ]' || { note "/health não voltou a 200"; ok=1; }
  return $ok
}
check "NS5 health gives up on paused dependency" t_ns5_health_paused

t_ns6_logged_not_returned() {
  local ok=0 since logs body
  sleep 1
  since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  docker stop "$(container redis-limiter)" >/dev/null
  body="$(api /health)"
  docker start "$(container redis-limiter)" >/dev/null
  rg_shared_back
  [ "$(jq -c 'keys' <<< "$body")" = '["checks","status"]' ] || { note "chaves: $body"; ok=1; }
  [ "$(jq -c '.checks | keys' <<< "$body")" = '["database","limiter"]' ] || { note "checks: $body"; ok=1; }
  [ "$(jq -r '[.status, .checks[]] | map(select(. != "ok" and . != "fail")) | length' <<< "$body")" = 0 ] || { note "valor fora de ok e fail: $body"; ok=1; }
  logs="$(docker logs --since "$since" "$RG_API" 2>&1)"
  grep -F 'health check limiter failed' <<< "$logs" | grep -qwF ERROR || { note "log sem o motivo: $(tail -3 <<< "$logs")"; ok=1; }
  return $ok
}
check "NS6 failed check is logged not returned" t_ns6_logged_not_returned

t_ns7_routes() {
  local ok=0 origin path headers
  rg_reset
  origin="$(grep '^CORS_ALLOWED_ORIGIN=' "$WORK/.env" | cut -d= -f2-)"
  [ "$(api_status localhost:8080/health)" = 200 ] || { note "GET /health"; ok=1; }
  [ "$(rg_register ana@example.com)" = 201 ] || { note "POST /users: $(rg_body)"; ok=1; }
  [ "$(api_status -X OPTIONS localhost:8080/users -H "Origin: $origin" -H 'Access-Control-Request-Method: POST')" = 204 ] || { note "OPTIONS /users"; ok=1; }
  for path in 'GET /users' 'PUT /users' 'DELETE /users' 'POST /health' 'GET /api/health' 'POST /api/users'; do
    [ "$(api_status -X "${path% *}" "localhost:8080${path#* }" -H 'Content-Type: application/json' -d '{}')" = 404 ] || { note "$path não respondeu 404"; ok=1; }
  done
  [ "$(api_status -X OPTIONS localhost:8080/health -H "Origin: $origin" -H 'Access-Control-Request-Method: GET')" = 404 ] || { note "OPTIONS /health não respondeu 404"; ok=1; }
  for path in /nada /; do
    headers="$(curl -s -D - -o /dev/null --max-time 10 -H 'Accept:' "localhost:8080$path" | tr -d '\r')"
    grep -qE '^HTTP/[0-9.]+ 404' <<< "$headers" || { note "$path: $(head -1 <<< "$headers")"; ok=1; }
    grep -qiE '^content-type: application/json' <<< "$headers" || { note "$path sem Content-Type JSON"; ok=1; }
  done
  return $ok
}
check "NS7 api routes are health and users" t_ns7_routes

t_ns8_schema_untouched() {
  local ok=0
  # O pg_dump 18 abre e fecha o dump com \restrict e \unrestrict e um token novo a cada vez.
  schema() { docker exec "$OB_PG" pg_dump -U cadastro_feliz -d cadastro_feliz --schema-only | grep -vE '^\\(un)?restrict ' > "$1"; }
  mkq down-nest || { note "make down-nest saiu com erro"; return 1; }
  schema "$WORK/schema.before"
  mkq up-nest || { note "make up-nest saiu com erro"; return 1; }
  rg_reset
  [ "$(rg_register ana@example.com)" = 201 ] || { note "cadastro: $(rg_body)"; ok=1; }
  rg_wait_for 30 rg_event_is processed ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  schema "$WORK/schema.after"
  cmp -s "$WORK/schema.before" "$WORK/schema.after" || { note "schema mudou: $(diff "$WORK/schema.before" "$WORK/schema.after" | head -5)"; ok=1; }
  [ -z "$(find "$NS" -path "$NS/node_modules" -prune -o -iname '*migration*' -print)" ] || { note "migration em apis/nestjs"; ok=1; }
  grep -qF 'synchronize: false' "$NS/src/database.ts" || { note "synchronize não está desligado"; ok=1; }
  grep -rqE 'synchronize: *true|migrationsRun: *true' "$NS/src" && { note "sincronização ligada em src"; ok=1; }
  return $ok
}
check "NS8 schema untouched by the stack" t_ns8_schema_untouched

t_ns9_queue_down() {
  local ok=0 wk
  rg_reset
  wk="$(ns_id "$RG_WK")"
  stack_queue_stop
  [ "$(api_status localhost:8080/health)" = 200 ] || { note "/health com o redis parado: $(api /health)"; ok=1; }
  [ "$(rg_register ana@example.com)" = 201 ] || { note "POST /users com o redis parado: $(rg_body)"; ok=1; }
  stack_queue_start
  rg_wait_for 60 rg_healthy "$RG_WK" || { note "worker ficou $(health "$RG_WK")"; ok=1; }
  [ "$(ns_id "$RG_WK")" = "$wk" ] || { note "worker recriado"; ok=1; }
  [ "$(docker inspect -f '{{.RestartCount}}' "$RG_WK")" = 0 ] || { note "worker reiniciou"; ok=1; }
  rg_wait_for 60 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  return $ok
}
check "NS9 stack queue down keeps the api up" t_ns9_queue_down

t_ns10_api_never_connects() {
  local ok=0 ip clients
  rg_reset
  ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$RG_API")"
  [ -n "$ip" ] || { note "sem o IP da api"; return 1; }
  api /health >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "cadastro: $(rg_body)"; ok=1; }
  api /health >/dev/null
  clients="$(docker exec "$RG_RD" redis-cli CLIENT LIST)"
  [ -n "$clients" ] || { note "CLIENT LIST vazio"; ok=1; }
  grep -qF "addr=$ip:" <<< "$clients" && { note "cliente da api no redis da stack"; ok=1; }
  return $ok
}
check "NS10 api never connects to the stack queue" t_ns10_api_never_connects

t_ns11_boot_failure() {
  local ok=0 rc file="$NS/src/main.ts"
  destroy_environment
  save "$file"
  printf "\nthrow new Error('boot failure forced by NS11');\n" >> "$file"
  mkq up-nest
  rc=$?
  [ "$rc" -ne 0 ] || { note "make up-nest saiu com 0"; ok=1; }
  [ "$(health "$RG_API")" != healthy ] || { note "api healthy"; ok=1; }
  restore "$file"
  return $ok
}
check "NS11 up-nest fails when the api does not boot" t_ns11_boot_failure

t_ns12_taken_port() {
  local rc
  destroy_environment
  docker run -d --name "$PORT_BLOCKER" -p 8080:6379 redis:8.10.3-alpine >/dev/null || return 1
  mkq up-nest
  rc=$?
  destroy_environment
  [ "$rc" -ne 0 ]
}
check "NS12 up-nest fails on taken port 8080" t_ns12_taken_port

t_ns13_switch_and_down() {
  local ok=0
  mkq up-nest || { note "make up-nest saiu com erro"; return 1; }
  mkq up-laravel || { note "make up-laravel saiu com erro"; ok=1; }
  [ -z "$(project_containers cadastro-feliz-nest)" ] || { note "containers da NestJS depois de up-laravel"; ok=1; }
  mkq up-nest || { note "make up-nest saiu com erro"; ok=1; }
  [ -z "$(project_containers cadastro-feliz-laravel)" ] || { note "containers da Laravel depois de up-nest"; ok=1; }
  mkq down || { note "make down saiu com erro"; ok=1; }
  [ -z "$(project_containers cadastro-feliz-nest)" ] || { note "containers da NestJS depois de make down"; ok=1; }
  [ -z "$(docker volume ls -q --filter label=com.docker.compose.project=cadastro-feliz-nest)" ] || { note "volume da NestJS depois de make down"; ok=1; }
  mkq up-nest || { note "make up-nest saiu com erro"; ok=1; }
  return $ok
}
check "NS13 nest leaves on switch and down" t_ns13_switch_and_down

t_ns14_non_object_json() {
  local ok=0 body status
  rg_reset
  # Com o banco parado, uma consulta responderia 500: o 422 prova que o banco não foi lido.
  docker stop "$OB_PG" >/dev/null
  for body in '[]' 'null' '"x"' '1'; do
    status="$(rg_post "$body")"
    [ "$status" = 422 ] || { note "$body: status $status"; ok=1; }
    [ "$(jq -c . "$WORK/r.body")" = "$RG4_BODY" ] || { note "$body: $(rg_body)"; ok=1; }
  done
  docker start "$OB_PG" >/dev/null
  rg_shared_back
  [ -z "$(redis_q --scan --pattern 'registration:*')" ] || { note "tentativa contada"; ok=1; }
  [ "$(rg_users)" = 0 ] || { note "users tem linhas"; ok=1; }
  return $ok
}
check "NS14 non-object json answers 422" t_ns14_non_object_json

# --- S2 - Edição, dependências e testes unitários ---

# O watch roda em um grupo de processos próprio (set -m), para o SIGINT chegar ao make e ao
# docker compose juntos, como o Ctrl+C de um terminal.
ns_watch_start() {
  set -m
  make --no-print-directory -C "$WORK" watch-nest > "$WORK/watch-nest.log" 2>&1 &
  NS_WATCH_PID=$!
  set +m
  rg_wait_for 300 grep -q 'Watch enabled' "$WORK/watch-nest.log"
}
ns_watch_alive() { [ -n "$NS_WATCH_PID" ] && kill -0 "$NS_WATCH_PID" 2>/dev/null; }
ns_watch_stop() {
  ns_watch_alive || return 0
  kill -INT -- "-$NS_WATCH_PID" 2>/dev/null
  rg_wait_for 30 bash -c "! kill -0 $NS_WATCH_PID 2>/dev/null"
  kill -KILL -- "-$NS_WATCH_PID" 2>/dev/null
  NS_WATCH_PID=
  return 0
}

t_ns15_watch_api() {
  local ok=0 before started file="$NS/src/modules/users/users.controller.ts"
  ns_watch_start || { note "watch não ficou pronto: $(tail -3 "$WORK/watch-nest.log")"; return 1; }
  rg_reset
  before="$(ns_id "$RG_API")"
  save "$file"
  started=$SECONDS
  replace_in "$file" 'User registered successfully.' 'User registered by the watch.'
  ns_new_message() { rg_reset >/dev/null; rg_register "w$RANDOM@example.com" >/dev/null; jq -e '.message == "User registered by the watch."' "$WORK/r.body" >/dev/null; }
  rg_wait_for 30 ns_new_message || { note "a api não usou o código novo: $(rg_body)"; ok=1; }
  [ $((SECONDS - started)) -le 30 ] || { note "levou $((SECONDS - started)) s"; ok=1; }
  [ "$(ns_id "$RG_API")" = "$before" ] || { note "api recriada"; ok=1; }
  cat "$file.nssave" > "$file"; rm -f "$file.nssave"
  ns_old_message() { rg_register "o$RANDOM@example.com" >/dev/null; jq -e '.message == "User registered successfully."' "$WORK/r.body" >/dev/null; }
  rg_wait_for 60 ns_old_message
  return $ok
}
check "NS15 watch updates the api" t_ns15_watch_api

t_ns16_watch_worker() {
  local ok=0 before started file="$NS/src/modules/mail/welcome-mail.ts"
  ns_watch_alive || { note "watch fora do ar"; return 1; }
  before="$(ns_id "$RG_WK")"
  save "$file"
  started=$SECONDS
  replace_in "$file" 'Não é preciso fazer mais nada.' 'Texto novo do watch.'
  ns_new_text() {
    local mail="t$RANDOM@example.com"
    rg_reset >/dev/null
    rg_register "$mail" >/dev/null
    rg_wait_for 10 rg_mail_arrived "$mail" || { NS_LAST_TEXT="nenhum e-mail para $mail"; return 1; }
    NS_LAST_TEXT="$(rg_mail_field "$mail" '.Text')"
    grep -qF 'Texto novo do watch.' <<< "$NS_LAST_TEXT"
  }
  rg_wait_for 6 ns_new_text || { note "o worker não usou o código novo: $(tr '\n' ' ' <<< "$NS_LAST_TEXT" | cut -c1-160)"; note "worker: $(docker logs --since 90s "$RG_WK" 2>&1 | grep -E 'Starting Nest|error|ERROR' | tail -4 | tr '\n' '|')"; ok=1; }
  [ $((SECONDS - started)) -le 60 ] || { note "levou $((SECONDS - started)) s"; ok=1; }
  [ "$(ns_id "$RG_WK")" = "$before" ] || { note "worker recriado"; ok=1; }
  cat "$file.nssave" > "$file"; rm -f "$file.nssave"
  return $ok
}
check "NS16 watch updates the worker" t_ns16_watch_worker

ns_rebuilt() {
  local api wk
  api="$(ns_id "$RG_API")"; wk="$(ns_id "$RG_WK")"
  [ -n "$api" ] && [ "$api" != "$1" ] && [ -n "$wk" ] && [ "$wk" != "$2" ] && ns_healthy
}

# ns_rebuild_on <nome> <arquivo> <comando que muda o arquivo>
ns_rebuild_on() {
  local name="$1" file="$2" api wk image started ok=0; shift 2
  ns_watch_alive || { note "watch fora do ar"; return 1; }
  api="$(ns_id "$RG_API")"; wk="$(ns_id "$RG_WK")"
  image="$(docker inspect -f '{{.Image}}' "$RG_API")"
  save "$file"
  started=$SECONDS
  "$@"
  rg_wait_for 180 ns_rebuilt "$api" "$wk" || { note "$name: api $(health "$RG_API"), worker $(health "$RG_WK")"; ok=1; }
  [ $((SECONDS - started)) -le 180 ] || { note "$name: levou $((SECONDS - started)) s"; ok=1; }
  [ "$(docker inspect -f '{{.Image}}' "$RG_API")" != "$image" ] || { note "$name: a imagem não mudou"; ok=1; }
  [ "$(docker inspect -f '{{.Image}}' "$RG_WK")" = "$(docker inspect -f '{{.Image}}' "$RG_API")" ] || { note "$name: worker em outra imagem"; ok=1; }
  api="$(ns_id "$RG_API")"; wk="$(ns_id "$RG_WK")"
  restore "$file"
  rg_wait_for 180 ns_rebuilt "$api" "$wk"
  return $ok
}
ns_change_description() { jq '.description = "probe"' "$NS/package.json.nssave" > "$NS/package.json"; }
ns_touch_lock() { printf '\n' >> "$NS/package-lock.json"; }
# Um comentário gera a mesma imagem; um LABEL no último estágio gera outra.
ns_touch_dockerfile() { printf 'LABEL probe=rebuild\n' >> "$NS/Dockerfile"; }

check "NS17 watch rebuilds on package.json" ns_rebuild_on package.json "$NS/package.json" ns_change_description
check "NS17 watch rebuilds on package-lock.json" ns_rebuild_on package-lock.json "$NS/package-lock.json" ns_touch_lock
check "NS17 watch rebuilds on Dockerfile" ns_rebuild_on Dockerfile "$NS/Dockerfile" ns_touch_dockerfile
ns_watch_stop

t_ns18_npm_requires_args() {
  local out rc before
  before="$(docker ps -aq | sort)"
  out="$(mk nest-npm 2>&1)"
  rc=$?
  [ "$rc" -ne 0 ] || { note "saiu com 0"; return 1; }
  grep -qxF 'uso: make nest-npm ARGS="<comando npm>"' <<< "$out" || { note "saída: $out"; return 1; }
  [ "$(docker ps -aq | sort)" = "$before" ] || { note "containers mudaram"; return 1; }
}
check "NS18 nest-npm requires args" t_ns18_npm_requires_args

t_ns19_npm_writes_json_and_lock() {
  local json="$NS/package.json" lock="$NS/package-lock.json" uid ok=0 cache ids
  # Tudo em apis/nestjs, menos os dois arquivos que podem mudar e as cópias de save.
  others() { (cd "$NS" && find . -type f ! -name package.json ! -name package-lock.json ! -name '*.nssave' -exec sha256sum {} + | sort -k2); }
  ids="$(ns_ids)"
  save "$json"; save "$lock"
  cache="$(others)"
  # Como root, o dono dos arquivos não diria nada: o make roda como outro uid, com acesso ao
  # socket do Docker, sobre uma cópia que pertence a ele (L-006).
  uid="$(id -u)"
  if [ "$uid" -eq 0 ]; then
    uid=4321
    mkdir -p "$WORK/.home"
    chown -R "$uid:$uid" "$WORK"
    caller() {
      setpriv --reuid="$uid" --regid="$uid" --groups="$(stat -c %g /var/run/docker.sock)" \
        env HOME="$WORK/.home" make --no-print-directory -C "$WORK" "$@" >/dev/null 2>&1
    }
  else
    caller() { mkq "$@"; }
  fi
  caller nest-npm ARGS="install is-number@7.0.0" || { note "install saiu com erro"; return 1; }
  [ "$(others)" = "$cache" ] || { note "outro arquivo mudou em apis/nestjs"; ok=1; }
  [ "$(jq -r '.dependencies["is-number"] // empty' "$json")" = 7.0.0 ] || { note "package.json sem is-number 7.0.0 em dependencies"; ok=1; }
  [ "$(jq -r '.packages["node_modules/is-number"].version // empty' "$lock")" = 7.0.0 ] || { note "package-lock.json sem is-number 7.0.0"; ok=1; }
  [ ! -e "$NS/node_modules" ] || { note "apis/nestjs/node_modules existe"; ok=1; }
  [ "$(stat -c %u "$json")" = "$uid" ] || { note "dono de package.json: $(stat -c %u "$json"), esperado $uid"; ok=1; }
  [ "$(stat -c %u "$lock")" = "$uid" ] || { note "dono de package-lock.json: $(stat -c %u "$lock"), esperado $uid"; ok=1; }
  [ "$(ns_ids)" = "$ids" ] || { note "containers da stack mudaram"; ok=1; }
  restore "$json"; restore "$lock"
  [ "$(id -u)" -eq 0 ] && chown -R 0:0 "$WORK"
  return $ok
}
check "NS19 nest-npm writes only json and lock" t_ns19_npm_writes_json_and_lock

t_ns20_npm_failure() {
  local json="$NS/package.json" lock="$NS/package-lock.json" before_json before_lock rc
  before_json="$(digest "$json")"; before_lock="$(digest "$lock")"
  mkq nest-npm ARGS="install pacote-que-nao-existe-cadastro-feliz@1.0.0"
  rc=$?
  [ "$rc" -ne 0 ] || { note "saiu com 0"; return 1; }
  [ "$(digest "$json")" = "$before_json" ] || { note "package.json mudou"; return 1; }
  [ "$(digest "$lock")" = "$before_lock" ] || { note "package-lock.json mudou"; return 1; }
}
check "NS20 nest-npm propagates npm failure" t_ns20_npm_failure

t_ns21_exact_versions() {
  local ok=0 loose
  loose="$(jq -r '(.dependencies // {}), (.devDependencies // {}) | to_entries[] | select(.value | test("^[0-9]+\\.[0-9]+\\.[0-9]+$") | not) | "\(.key)@\(.value)"' "$NS/package.json")"
  [ -z "$loose" ] || { note "versões não exatas: $loose"; ok=1; }
  [ "$(jq '(.dependencies | length) + (.devDependencies | length)' "$NS/package.json")" -gt 0 ] || { note "sem dependências"; ok=1; }
  [ "$(grep -m1 '^FROM ' "$NS/Dockerfile")" = 'FROM node:26.13.0-alpine AS base' ] || { note "FROM: $(grep -m1 '^FROM ' "$NS/Dockerfile")"; ok=1; }
  [ "$(grep -m1 '^FROM ' "$WORK/frontend/Dockerfile")" = 'FROM node:26.13.0-alpine' ] || { note "o frontend usa outra imagem"; ok=1; }
  return $ok
}
check "NS21 nest versions are exact" t_ns21_exact_versions

t_ns22_test_clean() {
  destroy_environment
  mkq test-nest || { note "make test-nest saiu com erro"; return 1; }
  any_containers && { note "sobrou container"; return 1; }
  network_exists && { note "sobrou a rede"; return 1; }
  return 0
}
check "NS22 test-nest passes without dependencies" t_ns22_test_clean

t_ns23_test_keeps_stack() {
  local ids
  mkq up-nest || { note "make up-nest saiu com erro"; return 1; }
  ids="$(ns_ids)"
  mkq test-nest || { note "make test-nest saiu com erro"; return 1; }
  [ "$(ns_ids)" = "$ids" ] || { note "containers mudaram"; return 1; }
  [ "$(api_status localhost:8080/health)" = 200 ]
}
check "NS23 test-nest keeps running stack" t_ns23_test_keeps_stack

t_ns24_test_fails() {
  local out rc f="$NS/src/probe-fail.spec.ts"
  printf "import { expect, it } from 'vitest';\n\nit('probe fails on purpose', () => {\n  expect(true).toBe(false);\n});\n" > "$f"
  out="$(mk test-nest 2>&1)"
  rc=$?
  rm -f "$f"
  [ "$rc" -ne 0 ] || { note "make test-nest saiu com 0"; return 1; }
  grep -qF 'probe fails on purpose' <<< "$out" || { note "saída sem o nome do teste"; return 1; }
}
check "NS24 test-nest fails on failing test" t_ns24_test_fails

# --- S3 e S4 - O adaptador e o relay no worker ---

t_ns25_worker_pause() {
  local ok=0
  rg_reset
  stack_worker_stop
  [ "$(rg_register ana@example.com)" = 201 ] || { note "cadastro: $(rg_body)"; ok=1; }
  rg_wait_for 10 rg_event_is published ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  [ "$(stack_queue_length)" -ge 1 ] || { note "nenhuma mensagem esperando"; ok=1; }
  sleep 3
  rg_mail_arrived ana@example.com && { note "o e-mail saiu com o worker pausado"; ok=1; }
  stack_worker_start
  rg_wait_for 30 rg_mail_arrived ana@example.com || { note "o e-mail não chegou depois de retomar"; ok=1; }
  return $ok
}
check "NS25 worker pause keeps the relay publishing" t_ns25_worker_pause

t_ns26_scheduler() {
  local out
  out="$(ns_scheduler)" || { note "queue-control falhou: $out"; return 1; }
  jq -e '.key == "outbox-relay" and .every == 1000' <<< "$out" >/dev/null || { note "agendador: $out"; return 1; }
}
check "NS26 relay scheduler runs every second" t_ns26_scheduler

t_ns27_batch() {
  local ok=0 oldest second newest published i
  rg_set_env OUTBOX_BATCH_SIZE=2 || { note "a stack não voltou com o lote de 2"; return 1; }
  stack_wait_ready
  rg_reset
  stack_worker_stop
  stack_relay_stop
  newest="$(ob_seed c@example.com pending '' 0 10)"
  oldest="$(ob_seed a@example.com pending '' 0 30)"
  second="$(ob_seed b@example.com pending '' 0 20)"
  stack_relay_start
  for ((i = 0; i < 100; i++)); do
    published="$(psql_q "select id from users_outbox where status = 'published' order by id")"
    [ -n "$published" ] && break
    sleep 0.1
  done
  [ "$published" = "$(printf '%s\n' "$oldest" "$second" | sort)" ] || { note "primeira execução publicou: $(tr '\n' ' ' <<< "$published")"; ok=1; }
  [ "$(psql_q "select status from users_outbox where id = '$newest'")" = pending ] || { note "o terceiro saiu na primeira execução"; ok=1; }
  ns_third() { [ "$(psql_q "select status from users_outbox where id = '$newest'")" = published ]; }
  rg_wait_for 10 ns_third || { note "o terceiro não saiu depois"; ok=1; }
  stack_worker_start
  rg_default_env
  stack_wait_ready
  return $ok
}
check "NS27 relay batch size and order" t_ns27_batch

t_ns28_skip_locked() {
  local ok=0 locked free pid started
  rg_reset
  stack_worker_stop
  stack_relay_stop
  locked="$(ob_seed travado@example.com pending '' 0 30)"
  free="$(ob_seed livre@example.com)"
  docker exec "$OB_PG" psql -U cadastro_feliz -d cadastro_feliz -c \
    "begin; select id from users_outbox where id = '$locked' for update; select pg_sleep(12); commit;" >/dev/null 2>&1 &
  pid=$!
  sleep 1
  started=$SECONDS
  stack_relay_start
  ns_free() { [ "$(psql_q "select status from users_outbox where id = '$free'")" = published ]; }
  rg_wait_for 10 ns_free || { note "o livre não saiu"; ok=1; }
  [ $((SECONDS - started)) -le 10 ] || { note "levou $((SECONDS - started)) s"; ok=1; }
  [ "$(psql_q "select status from users_outbox where id = '$locked'")" = pending ] || { note "o travado foi publicado"; ok=1; }
  wait "$pid"
  ns_locked() { [ "$(psql_q "select status from users_outbox where id = '$locked'")" = published ]; }
  rg_wait_for 10 ns_locked || { note "o travado não saiu depois da trava"; ok=1; }
  stack_worker_start
  return $ok
}
check "NS28 relay skips locked rows" t_ns28_skip_locked

t_ns29_relay_failure() {
  local ok=0 since a b
  rg_reset
  stack_worker_stop
  stack_relay_stop
  a="$(ob_seed a@example.com pending '' 0 20)"
  b="$(ob_seed b@example.com pending '' 0 10)"
  # O contador de ids de registration-emails deixa de ser um número: toda publicação nesta fila
  # falha, e a fila outbox-relay, que dispara o relay, continua funcionando.
  docker exec "$RG_RD" redis-cli SET bull:registration-emails:id not-a-number >/dev/null
  sleep 1
  since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  stack_relay_start
  ns_failed_logged() { local logs; logs="$(docker logs --since "$since" "$RG_WK" 2>&1)"; grep -qF 'outbox relay failed' <<< "$logs"; }
  rg_wait_for 20 ns_failed_logged || { note "log do worker sem a falha: $(docker logs --since "$since" "$RG_WK" 2>&1 | tail -3)"; ok=1; }
  [ "$(psql_q "select string_agg(status || ':' || (published_at is null)::text, ',' order by created_at) from users_outbox")" = 'pending:true,pending:true' ] \
    || { note "eventos: $(psql_q "select string_agg(status, ',') from users_outbox")"; ok=1; }
  sleep 6
  rg_healthy "$RG_WK" || { note "worker ficou $(health "$RG_WK")"; ok=1; }
  docker exec "$RG_RD" redis-cli DEL bull:registration-emails:id >/dev/null
  stack_worker_start
  rg_wait_for 60 rg_mail_arrived b@example.com || { note "os eventos não saíram depois da falha"; ok=1; }
  return $ok
}
check "NS29 relay failure keeps the batch pending" t_ns29_relay_failure

t_ns30_frozen_queue() {
  local ok=0 pid probes=0 i open opened resumed
  rg_reset
  # O relay para antes de o evento existir, ou ele sairia antes de a fila travar.
  stack_relay_stop
  ob_seed ana@example.com >/dev/null
  stack_queue_freeze
  # Uma execução do relay abre o lote com a fila travada: ela precisa desfazê-lo em até 3 s.
  ns_relay_once > "$WORK/relay-once.out" &
  pid=$!
  ns_open() { open="$(psql_q "select count(*) from pg_stat_activity where state like 'idle in transaction%'")"; [ "$open" -gt 0 ]; }
  for ((i = 0; i < 200; i++)); do ns_open && break; sleep 0.05; done
  [ "$open" -gt 0 ] || { note "o relay não abriu o lote"; ok=1; }
  opened="$EPOCHREALTIME"
  for ((i = 0; i < 60; i++)); do ns_open || break; sleep 0.05; done
  awk -v a="$opened" -v b="$EPOCHREALTIME" 'BEGIN { exit !(b - a <= 3) }' || { note "a transação ficou aberta mais de 3 s"; ok=1; }
  for i in $(seq 1 4); do
    probes=$((probes + 1))
    ns_open && { note "transação aberta: $open"; ok=1; }
    docker exec "$OB_PG" psql -U cadastro_feliz -d cadastro_feliz -v ON_ERROR_STOP=1 -c \
      "set lock_timeout = '1s'; update users_outbox set last_error = last_error where payload->>'email' = 'ana@example.com'" >/dev/null 2>&1 \
      || { note "o UPDATE esperou uma trava"; ok=1; }
    sleep 0.5
  done
  [ "$probes" -ge 2 ] || { note "só $probes sondas"; ok=1; }
  wait "$pid"
  grep -qF 'outbox relay failed' "$WORK/relay-once.out" || { note "relay: $(cat "$WORK/relay-once.out")"; ok=1; }
  rg_event_is pending ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  stack_queue_unfreeze
  resumed=$SECONDS
  stack_relay_start
  rg_wait_for 60 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  [ $((SECONDS - resumed)) -le 60 ] || { note "levou $((SECONDS - resumed)) s"; ok=1; }
  [ "$(docker inspect -f '{{.RestartCount}}' "$RG_WK")" = 0 ] || { note "worker reiniciou"; ok=1; }
  return $ok
}
check "NS30 frozen queue releases the batch" t_ns30_frozen_queue

t_ns31_worker_start() {
  local ok=0 started
  rg_reset
  docker stop "$RG_WK" >/dev/null
  ob_seed ana@example.com >/dev/null
  started=$SECONDS
  docker start "$RG_WK" >/dev/null
  ns_left_pending() { case "$(rg_event status ana@example.com)" in published | processed) return 0 ;; esac; return 1; }
  rg_wait_for 10 ns_left_pending || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  [ $((SECONDS - started)) -le 10 ] || { note "levou $((SECONDS - started)) s"; ok=1; }
  rg_wait_for 90 rg_healthy "$RG_WK"
  return $ok
}
check "NS31 worker publishes right after it starts" t_ns31_worker_start

t_ns32_stopped_worker() {
  local ok=0 started
  rg_reset
  docker stop "$RG_WK" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "cadastro: $(rg_body)"; ok=1; }
  sleep 5
  rg_event_is pending ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  started=$SECONDS
  docker start "$RG_WK" >/dev/null
  rg_wait_for 60 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  [ $((SECONDS - started)) -le 60 ] || { note "levou $((SECONDS - started)) s"; ok=1; }
  rg_wait_for 90 rg_healthy "$RG_WK"
  return $ok
}
check "NS32 stopped worker leaves events pending" t_ns32_stopped_worker

# --- S5 - Envio a partir do evento ---

t_ns33_job_shape() {
  local ok=0 id event data opts
  rg_reset
  stack_worker_stop
  [ "$(rg_register ana@example.com)" = 201 ] || { note "cadastro: $(rg_body)"; ok=1; }
  rg_wait_for 15 rg_queue_has || { note "fila vazia"; stack_worker_start; return 1; }
  id="$(ns_waiting_ids | head -1)"
  event="$(rg_event id ana@example.com)"
  data="$(docker exec "$RG_RD" redis-cli HGET "bull:registration-emails:$id" data)"
  opts="$(docker exec "$RG_RD" redis-cli HGET "bull:registration-emails:$id" opts)"
  [ "$(jq -c . <<< "$data")" = "{\"event_id\":\"$event\"}" ] || { note "data: $data"; ok=1; }
  jq -e '.attempts == 1' <<< "$opts" >/dev/null || { note "attempts: $opts"; ok=1; }
  jq -e 'has("backoff") | not' <<< "$opts" >/dev/null || { note "backoff: $opts"; ok=1; }
  [ "$id" != "$event" ] || { note "o id do job é o do evento"; ok=1; }
  stack_worker_start
  rg_wait_for 30 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  return $ok
}
check "NS33 job carries only the event id with one attempt" t_ns33_job_shape

t_ns34_republish_new_job() {
  local ok=0 first
  rg_set_env OUTBOX_REPUBLISH_AFTER_SECONDS=5 || { note "a stack não voltou"; return 1; }
  stack_wait_ready
  rg_reset
  stack_worker_stop
  [ "$(rg_register ana@example.com)" = 201 ] || { note "cadastro: $(rg_body)"; ok=1; }
  rg_wait_for 15 rg_queue_has || { note "fila vazia"; ok=1; }
  first="$(ns_counter)"
  rg_wait_for 20 rg_queue_has 2 || { note "a republicação não criou job novo: $(stack_queue_length) na fila"; ok=1; }
  [ "$(ns_counter)" -gt "$first" ] || { note "contador: $first e depois $(ns_counter)"; ok=1; }
  stack_worker_start
  rg_wait_for 30 rg_mail_arrived ana@example.com || { note "o e-mail não chegou"; ok=1; }
  rg_default_env
  stack_wait_ready
  return $ok
}
check "NS34 republish creates a new job" t_ns34_republish_new_job

t_ns35_killed_worker() {
  local ok=0 id
  rg_set_env OUTBOX_REPUBLISH_AFTER_SECONDS=5 || { note "a stack não voltou"; return 1; }
  stack_wait_ready
  rg_reset
  docker pause "$OB_MAILPIT" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "cadastro: $(rg_body)"; ok=1; }
  ns_sending() { [ -n "$(docker exec "$RG_RD" redis-cli --scan --pattern 'bull:registration-emails:*:lock')" ]; }
  rg_wait_for 15 ns_sending || { note "o envio não começou"; ok=1; }
  docker kill "$RG_WK" >/dev/null
  docker unpause "$OB_MAILPIT" >/dev/null
  rg_event_is published ana@example.com || { note "evento: $(rg_event status ana@example.com)"; ok=1; }
  [ "$(rg_event attempts ana@example.com)" = 0 ] || { note "attempts: $(rg_event attempts ana@example.com)"; ok=1; }
  docker start "$RG_WK" >/dev/null
  rg_wait_for 60 rg_mail_arrived ana@example.com || { note "o e-mail não chegou depois da republicação"; ok=1; }
  # O lock do job morto vence em até 30 s, e a verificação de jobs parados roda a cada 30 s: um
  # job que voltasse pela fila mandaria a segunda mensagem dentro desta espera.
  sleep 70
  [ "$(rg_mail_count ana@example.com)" = 1 ] || { note "mensagens: $(rg_mail_count ana@example.com)"; ok=1; }
  id="$(rg_event id ana@example.com)"
  [ "$(rg_mail_field ana@example.com '.MessageID')" = "$id@cadastro-feliz.local" ] || { note "Message-ID: $(rg_mail_field ana@example.com '.MessageID')"; ok=1; }
  [ "$(rg_event attempts ana@example.com)" = 0 ] || { note "attempts no fim: $(rg_event attempts ana@example.com)"; ok=1; }
  rg_default_env
  stack_wait_ready
  return $ok
}
check "NS35 killed worker does not rerun the job" t_ns35_killed_worker

t_ns36_lock_outlasts_smtp() {
  local ok=0 lock="" pttl job started failed elapsed i
  rg_reset
  docker pause "$OB_MAILPIT" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "cadastro: $(rg_body)"; ok=1; }
  for ((i = 0; i < 300; i++)); do
    lock="$(docker exec "$RG_RD" redis-cli --scan --pattern 'bull:registration-emails:*:lock' | head -1)"
    [ -n "$lock" ] && break
    sleep 0.05
  done
  [ -n "$lock" ] || { note "o envio não começou"; docker unpause "$OB_MAILPIT" >/dev/null; return 1; }
  pttl="$(docker exec "$RG_RD" redis-cli PTTL "$lock")"
  [ "$pttl" -gt 5000 ] && [ "$pttl" -le 30000 ] || { note "PTTL da trava: $pttl"; ok=1; }
  job="${lock%:lock}"
  # O início do envio é o processedOn do job; a falha, o available_at gravado menos a espera de 30 s.
  started="$(docker exec "$RG_RD" redis-cli HGET "$job" processedOn)"
  ns_failed() { [ "$(rg_event attempts ana@example.com)" -ge 1 ]; }
  rg_wait_for 15 ns_failed || { note "a falha não foi gravada"; ok=1; }
  failed="$(rg_event "round(extract(epoch from available_at - interval '30 seconds') * 1000)" ana@example.com)"
  elapsed="$(awk -v a="$started" -v b="$failed" 'BEGIN { printf "%.3f", (b - a) / 1000 }')"
  awk -v e="$elapsed" 'BEGIN { exit !(e >= 5 && e <= 10) }' || { note "a falha veio em ${elapsed}s"; ok=1; }
  docker unpause "$OB_MAILPIT" >/dev/null
  rg_shared_back
  return $ok
}
check "NS36 job lock outlasts the smtp timeout" t_ns36_lock_outlasts_smtp

# --- S7 - CI ---

t_ns37_ci() {
  local job ok=0 install_line sum_line run_line list
  job="$(awk '/^  nest:$/{on=1; print; next} on && /^  [a-z][a-z-]*:$/{exit} on' "$WORK/.github/workflows/ci.yml")"
  [ -n "$job" ] || { note "workflow sem job nest"; return 1; }
  install_line="$(grep -nF 'releases/download/$COMPOSE_VERSION/docker-compose-linux-x86_64' <<< "$job" | head -1 | cut -d: -f1)"
  sum_line="$(grep -nF 'echo "$COMPOSE_SHA256  $dir/docker-compose" | sha256sum --check --strict -' <<< "$job" | head -1 | cut -d: -f1)"
  run_line="$(grep -nE '^ +run: make test-nest$' <<< "$job" | head -1 | cut -d: -f1)"
  [ -n "$install_line" ] && [ -n "$sum_line" ] && [ -n "$run_line" ] \
    && [ "$install_line" -lt "$sum_line" ] && [ "$sum_line" -lt "$run_line" ] \
    || { note "job nest: download na linha '$install_line', checksum na '$sum_line', make test-nest na '$run_line'"; ok=1; }
  list="$(bash "$WORK/tests/infra/run.sh" --list)"
  for entry in registration:nest outbox:nest nest stack-switch; do
    grep -qx "$entry" <<< "$list" || { note "run.sh --list sem $entry"; ok=1; }
  done
  return $ok
}
check "NS37 ci runs test-nest and the nest suites" t_ns37_ci
