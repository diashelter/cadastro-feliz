# Base da API Laravel (.specs/features/laravel-api-base), com módulos, Pest e o Horizon
# (.specs/features/laravel-registration-email). Carregado por run.sh, que define o
# fake_stack usado em LV9.

NG=cadastro-feliz-laravel-nginx-1
FPM=cadastro-feliz-laravel-php-fpm-1
HZ=cadastro-feliz-laravel-horizon-1
SC=cadastro-feliz-laravel-scheduler-1
RD=cadastro-feliz-laravel-redis-1
FPM_IMAGE=cadastro-feliz-laravel-php-fpm
LV="$WORK/apis/laravel"
WATCH_PID=

lv_id() { docker ps -aq --no-trunc --filter "name=^$1\$"; }
fpm_image() { docker image inspect -f '{{.Id}}' "$FPM_IMAGE" 2>/dev/null; }
api() { curl -s --max-time 10 "localhost:8080$1"; }
api_status() { curl -s -o /dev/null --max-time 10 -w '%{http_code}' "localhost:8080$1"; }
owner_uid() { stat -c %u "$1"; }

# wait_for <segundos> <comando...>: repete o comando a cada segundo até ele passar.
wait_for() {
  local secs="$1" i; shift
  for ((i = 0; i < secs; i++)); do "$@" && return 0; sleep 1; done
  "$@"
}

lv_healthy() {
  local c
  for c in "$NG" "$FPM" "$HZ" "$RD" "$SC"; do
    [ "$(health "$c")" = healthy ] || return 1
  done
}
status_is() { [ "$(api_status "$1")" = "$2" ]; }
body_is() { [ "$(api "$1")" = "$2" ]; }
# health_within_limit <corpo esperado>: /health responde 503, com esse corpo, em menos de 3 s.
health_within_limit() {
  local expected="$1" out code secs body ok=0
  out="$(curl -s -o "$WORK/limit.body" --max-time 10 -w '%{http_code} %{time_total}' localhost:8080/health)"
  code="${out% *}"; secs="${out#* }"; body="$(cat "$WORK/limit.body")"
  [ "$code" = 503 ] || { note "status $code"; ok=1; }
  [ "$body" = "$expected" ] || { note "corpo: $body"; ok=1; }
  awk -v s="$secs" 'BEGIN { exit !(s < 3) }' || { note "levou ${secs}s"; ok=1; }
  return $ok
}
shared_back() { wait_for 60 shared_healthy; }

# Guarda e devolve um arquivo da cópia de trabalho, para cada teste deixar tudo como achou.
save() { cp -p "$1" "$1.lvsave"; }
restore() { mv -f "$1.lvsave" "$1"; }

routes="$LV/app-modules/health/routes/health-routes.php"
add_probe_route() { printf '\nRoute::get('"'"'/probe'"'"', fn () => '"'"'probe-ok'"'"');\n' >> "$routes"; }

# --- Arquivos do repositório, sem Docker ---

t_lv10_repo_files() {
  local ok=0 p
  git -C "$REPO" check-ignore -q apis/laravel/vendor/autoload.php \
    || { note ".gitignore não ignora apis/laravel/vendor"; ok=1; }
  grep -qxF 'apis/laravel/vendor/' "$WORK/.gitignore" || { note "apis/laravel/vendor/ fora do .gitignore da raiz"; ok=1; }
  for p in .env .env.example database/migrations; do
    [ ! -e "$LV/$p" ] || { note "apis/laravel/$p existe"; ok=1; }
  done
  p="$(find "$LV/app-modules" -type d -path '*/database/migrations')"
  [ -z "$p" ] || { note "módulo com migrations: $p"; ok=1; }
  return $ok
}
check "LV10 no vendor env or migrations in repo" t_lv10_repo_files

t_lv11_env_example() {
  local section key ok=0
  section="$(awk '/^# Específicas de stack/{on=1; next} on && /^# /{exit} on' "$WORK/.env.example")"
  key="$(grep -E '^APP_KEY=base64:' <<< "$section" | head -1 | cut -d: -f2-)"
  [ -n "$key" ] || { note "APP_KEY=base64: ausente em Específicas de stack"; return 1; }
  [ "$(printf '%s' "$key" | base64 -d 2>/dev/null | wc -c)" -eq 32 ] || { note "APP_KEY não decodifica em 32 bytes"; ok=1; }
  grep -qxF 'APP_ENV=local' <<< "$section" || { note "sem APP_ENV=local"; ok=1; }
  grep -qxF 'APP_DEBUG=true' <<< "$section" || { note "sem APP_DEBUG=true"; ok=1; }
  return $ok
}
check "LV11 env example has laravel vars" t_lv11_env_example

t_lv6_framework_locked() {
  local version
  version="$(jq -r '.packages[] | select(.name == "laravel/framework") | .version' "$LV/composer.lock")"
  [ "$version" = v13.40.0 ] || { note "laravel/framework travado em '$version'"; return 1; }
}
check "LV6 framework version locked" t_lv6_framework_locked

lock_version() { jq -r --arg n "$1" '(.packages + ."packages-dev")[] | select(.name == $n) | .version' "$LV/composer.lock"; }

t_lv46_pest_locked() {
  local ok=0
  [ "$(lock_version pestphp/pest)" = v5.3.5 ] || { note "pest: $(lock_version pestphp/pest)"; ok=1; }
  [ "$(lock_version pestphp/pest-plugin-laravel)" = v5.0.1 ] || { note "plugin: $(lock_version pestphp/pest-plugin-laravel)"; ok=1; }
  grep -qE '^13\.' <<< "$(lock_version phpunit/phpunit)" || { note "phpunit: $(lock_version phpunit/phpunit)"; ok=1; }
  return $ok
}
check "LV46 pest versions locked" t_lv46_pest_locked

t_lv48_health_tests_pest() {
  local f="$LV/app-modules/health/tests/HealthTest.php" ok=0
  [ -f "$f" ] || { note "sem $f"; return 1; }
  [ "$(grep -cE "^it\('" "$f")" -eq 4 ] || { note "esperava 4 testes it()"; ok=1; }
  grep -qE 'extends +[A-Za-z\\]*TestCase' "$f" && { note "ainda é uma classe do PHPUnit"; ok=1; }
  [ ! -e "$LV/tests/Feature/Health" ] || { note "tests/Feature/Health ainda existe"; ok=1; }
  return $ok
}
check "LV48 health tests are pest in the module" t_lv48_health_tests_pest

t_lv49_modular_locked() {
  local name ok=0
  [ "$(lock_version internachi/modular)" = 3.0.2 ] || { note "modular: $(lock_version internachi/modular)"; ok=1; }
  for name in health notifications users; do
    [ "$(jq -r --arg n "modules/$name" '.packages[] | select(.name == $n) | .dist.url' "$LV/composer.lock")" = "app-modules/$name" ] \
      || { note "modules/$name não vem de app-modules"; ok=1; }
  done
  return $ok
}
check "LV49 modular locked with local modules" t_lv49_modular_locked

t_lv50_modules_layout() {
  local name ok=0
  [ ! -e "$LV/app/Modules" ] || { note "app/Modules existe"; ok=1; }
  [ ! -e "$LV/routes/api.php" ] || { note "routes/api.php existe"; ok=1; }
  for name in health notifications users; do
    [ -f "$LV/app-modules/$name/composer.json" ] || { note "$name sem composer.json"; ok=1; }
    [ -d "$LV/app-modules/$name/src" ] || { note "$name sem src"; ok=1; }
  done
  return $ok
}
check "LV50 modules layout" t_lv50_modules_layout

t_lv34_ci() {
  local job ok=0 install_line sum_line run_line
  job="$(awk '/^  laravel:$/{on=1; print; next} on && /^  [a-z][a-z-]*:$/{exit} on' "$WORK/.github/workflows/ci.yml")"
  [ -n "$job" ] || { note "workflow sem job laravel"; return 1; }
  # O Compose fixado: o download de $COMPOSE_VERSION e a conferência com $COMPOSE_SHA256,
  # as duas antes de make test-laravel.
  install_line="$(grep -nF 'releases/download/$COMPOSE_VERSION/docker-compose-linux-x86_64' <<< "$job" | head -1 | cut -d: -f1)"
  sum_line="$(grep -nF 'echo "$COMPOSE_SHA256  $dir/docker-compose" | sha256sum --check --strict -' <<< "$job" | head -1 | cut -d: -f1)"
  run_line="$(grep -nE '^ +run: make test-laravel$' <<< "$job" | head -1 | cut -d: -f1)"
  [ -n "$install_line" ] && [ -n "$sum_line" ] && [ -n "$run_line" ] \
    && [ "$install_line" -lt "$sum_line" ] && [ "$sum_line" -lt "$run_line" ] \
    || { note "job laravel: download na linha '$install_line', checksum na '$sum_line', make test-laravel na '$run_line'"; ok=1; }
  # Em duas etapas: com pipefail, o grep -q que sai no primeiro acerto daria SIGPIPE no run.sh.
  local list
  list="$(bash "$WORK/tests/infra/run.sh" --list)"
  grep -qx laravel <<< "$list" || { note "run.sh --list sem laravel"; ok=1; }
  return $ok
}
check "LV34 ci runs test-laravel and laravel suite" t_lv34_ci

# --- S4 - make test-laravel sem dependências ---

t_lv31_test_laravel_clean() {
  destroy_environment
  mkq test-laravel || { note "make test-laravel saiu com erro"; return 1; }
  any_containers && { note "sobrou container"; return 1; }
  network_exists && { note "sobrou a rede"; return 1; }
  return 0
}
check "LV31 test-laravel passes without dependencies" t_lv31_test_laravel_clean

# --- S1 - Stack no ar ---

t_lv1_clean_clone() {
  destroy_environment
  rm -f "$WORK/.env"
  mkq up-laravel || { note "make up-laravel saiu com erro"; return 1; }
  lv_healthy || { note "nginx: $(health "$NG"), php-fpm: $(health "$FPM"), horizon: $(health "$HZ"), redis: $(health "$RD"), scheduler: $(health "$SC")"; return 1; }
  [ "$(docker ps -a --filter label=com.docker.compose.project=cadastro-feliz-laravel --format '{{.Names}}' | sort | tr '\n' ' ')" = "$HZ $NG $FPM $RD $SC " ] \
    || { note "containers do projeto: $(docker ps -a --filter label=com.docker.compose.project=cadastro-feliz-laravel --format '{{.Names}}')"; return 1; }
  status_is /health 200 || { note "GET /health respondeu $(api_status /health)"; return 1; }
}
check "LV1 up-laravel on clean clone" t_lv1_clean_clone

t_lv51_image_modules() {
  local name
  for name in health notifications users; do
    docker exec "$FPM" test -e "/var/www/html/vendor/modules/$name/composer.json" || { note "vendor sem modules/$name"; return 1; }
  done
}
check "LV51 image resolves local modules" t_lv51_image_modules

t_lv2_rerun() {
  local before after img_before img_after
  before="$(project_containers cadastro-feliz-laravel | sort)"
  [ "$(echo "$before" | grep -c .)" -eq 5 ] || { note "esperava 5 containers: $before"; return 1; }
  img_before="$(fpm_image)"
  mkq up-laravel || return 1
  after="$(project_containers cadastro-feliz-laravel | sort)"
  img_after="$(fpm_image)"
  [ "$before" = "$after" ] || { note "containers mudaram"; return 1; }
  [ -n "$img_before" ] && [ "$img_before" = "$img_after" ] || { note "imagem mudou"; return 1; }
}
check "LV2 up-laravel rerun keeps containers" t_lv2_rerun

t_lv4_ports() {
  local ports
  ports="$(docker port "$NG" | sed -E 's/.*:([0-9]+)$/\1/' | sort -u | tr '\n' ' ')"
  [ "$ports" = "8080 " ] || { note "nginx publica: '$ports'"; return 1; }
  [ -z "$(docker port "$FPM")" ] || { note "php-fpm publica: $(docker port "$FPM")"; return 1; }
  [ -z "$(docker port "$HZ")" ] || { note "horizon publica: $(docker port "$HZ")"; return 1; }
  [ -z "$(docker port "$SC")" ] || { note "scheduler publica: $(docker port "$SC")"; return 1; }
  [ -z "$(docker port "$RD")" ] || { note "redis publica: $(docker port "$RD")"; return 1; }
}
check "LV4 laravel published ports" t_lv4_ports

t_lv5_images() {
  local ok=0
  [ "$(docker inspect -f '{{.Config.Image}}' "$NG")" = nginx:1.30.6-alpine ] || { note "imagem do nginx"; ok=1; }
  [ "$(docker inspect -f '{{.Config.Image}}' "$FPM")" = "$FPM_IMAGE" ] || { note "imagem do php-fpm"; ok=1; }
  grep -qE '^FROM php:8\.5\.12-fpm-alpine( |$)' "$LV/docker/php/Dockerfile" || { note "Dockerfile sem FROM php:8.5.12-fpm-alpine"; ok=1; }
  docker exec "$FPM" php -m | grep -qx pdo_pgsql || { note "sem pdo_pgsql"; ok=1; }
  docker exec "$FPM" php -m | grep -qx redis || { note "sem redis"; ok=1; }
  [ "$(docker exec "$FPM" php -r 'echo phpversion("redis");')" = 6.3.0 ] || { note "phpredis não é 6.3.0"; ok=1; }
  [ "$(docker inspect -f '{{.Config.Image}}' "$HZ")" = "$FPM_IMAGE" ] || { note "imagem do horizon"; ok=1; }
  [ "$(docker inspect -f '{{.Config.Image}}' "$SC")" = "$FPM_IMAGE" ] || { note "imagem do scheduler"; ok=1; }
  docker exec "$FPM" php -m | grep -qx pcntl || { note "php-fpm sem pcntl"; ok=1; }
  docker exec "$HZ" php -m | grep -qx pcntl || { note "horizon sem pcntl"; ok=1; }
  return $ok
}
check "LV5 laravel images and extensions" t_lv5_images

# --- S2 - GET /health ---

OK_BODY='{"status":"ok","checks":{"database":"ok","limiter":"ok"}}'
LIMITER_FAIL='{"status":"fail","checks":{"database":"ok","limiter":"fail"}}'
DATABASE_FAIL='{"status":"fail","checks":{"database":"fail","limiter":"ok"}}'
BOTH_FAIL='{"status":"fail","checks":{"database":"fail","limiter":"fail"}}'

t_lv13_health_ok() {
  local headers body ok=0
  headers="$(curl -s -D - -o "$WORK/health.body" --max-time 10 localhost:8080/health)"
  body="$(cat "$WORK/health.body")"
  grep -qE '^HTTP/[0-9.]+ 200' <<< "$headers" || { note "status: $(head -1 <<< "$headers")"; ok=1; }
  grep -qiE '^content-type: application/json' <<< "$headers" || { note "sem Content-Type JSON"; ok=1; }
  grep -iE '^cache-control:' <<< "$headers" | grep -qF 'no-store' || { note "Cache-Control sem no-store"; ok=1; }
  grep -qiE '^set-cookie:' <<< "$headers" && { note "resposta tem Set-Cookie"; ok=1; }
  [ "$body" = "$OK_BODY" ] || { note "corpo: $body"; ok=1; }
  return $ok
}
check "LV13 health ok with real dependencies" t_lv13_health_ok

t_lv19_writes_nothing() {
  local before after i
  before="$(redis_q DBSIZE) $(psql_q 'select count(*) from users') $(psql_q 'select count(*) from users_outbox')"
  for i in 1 2 3 4 5; do api /health >/dev/null; done
  after="$(redis_q DBSIZE) $(psql_q 'select count(*) from users') $(psql_q 'select count(*) from users_outbox')"
  [ "$before" = "$after" ] || { note "antes: $before, depois: $after"; return 1; }
}
check "LV19 health writes nothing" t_lv19_writes_nothing

t_lv20_no_up_no_prefix() {
  status_is /up 404 || { note "/up respondeu $(api_status /up)"; return 1; }
  status_is /api/health 404 || { note "/api/health respondeu $(api_status /api/health)"; return 1; }
}
check "LV20 no native up and no api prefix" t_lv20_no_up_no_prefix

t_lv21_json_404() {
  local path headers ok=0
  for path in /nada /; do
    # curl manda `Accept: */*` por padrão; `-H 'Accept:'` tira o header.
    headers="$(curl -s -D - -o /dev/null --max-time 10 -H 'Accept:' "localhost:8080$path")"
    grep -qE '^HTTP/[0-9.]+ 404' <<< "$headers" || { note "$path: $(head -1 <<< "$headers")"; ok=1; }
    grep -qiE '^content-type: application/json' <<< "$headers" || { note "$path sem Content-Type JSON"; ok=1; }
  done
  return $ok
}
check "LV21 unknown route answers json" t_lv21_json_404

t_lv44_routes() {
  local uris ok=0 method
  uris="$(docker exec "$FPM" php artisan route:list --json | jq -c '[.[].uri | select(startswith("horizon") | not)] | sort')"
  [ "$uris" = '["health","users"]' ] || { note "rotas: $uris"; ok=1; }
  for method in GET PUT; do
    [ "$(curl -s -o /dev/null --max-time 10 -X "$method" -w '%{http_code}' localhost:8080/storage/x)" = 404 ] \
      || { note "$method /storage/x não respondeu 404"; ok=1; }
  done
  return $ok
}
check "LV44 api routes are health users and horizon" t_lv44_routes

t_lv45_no_table_defaults() {
  local got expected='["pgsql","array","array","redis","stderr"]'
  # Os valores do php-fpm em execução, com as variáveis do container, sem o phpunit.xml.
  got="$(docker exec -w /var/www/html "$FPM" php -r '
    require "vendor/autoload.php";
    $app = require "bootstrap/app.php";
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    echo json_encode([config("database.default"), config("session.driver"), config("cache.default"),
      config("queue.default"), config("logging.default")]);')"
  [ "$got" = "$expected" ] || { note "database, session, cache, queue, logging: $got"; return 1; }
}
check "LV45 laravel defaults use no table" t_lv45_no_table_defaults

t_lv14_limiter_stopped() {
  local ok=0
  docker stop "$(container redis-limiter)" >/dev/null
  health_within_limit "$LIMITER_FAIL" || ok=1
  sleep 30
  lv_healthy || { note "depois de 30 s: nginx $(health "$NG"), php-fpm $(health "$FPM")"; ok=1; }
  docker start "$(container redis-limiter)" >/dev/null
  shared_back
  return $ok
}
check "LV14 health 503 when limiter stopped" t_lv14_limiter_stopped

t_lv15_postgres_stopped() {
  local ok=0
  docker stop "$(container postgres)" >/dev/null
  health_within_limit "$DATABASE_FAIL" || ok=1
  docker start "$(container postgres)" >/dev/null
  shared_back
  return $ok
}
check "LV15 health 503 when postgres stopped" t_lv15_postgres_stopped

t_lv16_both_stopped() {
  local ok=0
  docker stop "$(container postgres)" "$(container redis-limiter)" >/dev/null
  health_within_limit "$BOTH_FAIL" || ok=1
  docker start "$(container postgres)" "$(container redis-limiter)" >/dev/null
  shared_back
  return $ok
}
check "LV16 health 503 when both stopped" t_lv16_both_stopped

# Como no runner do CI: o nome de um container parado vai para um DNS externo. O endereço
# abaixo não responde, e o limite de 1 s da conexão não cobre a resolução de nomes.
t_lv52_mute_dns() {
  local compose="$LV/docker-compose.yml" ok=0
  save "$compose"
  sed -i 's/^  php-fpm:$/  php-fpm:\n    dns: [10.255.255.1]/' "$compose"
  mkq up-laravel || { note "make up-laravel saiu com erro"; ok=1; }
  docker stop "$(container postgres)" "$(container redis-limiter)" >/dev/null
  health_within_limit "$BOTH_FAIL" || ok=1
  docker start "$(container postgres)" "$(container redis-limiter)" >/dev/null
  shared_back
  restore "$compose"
  mkq up-laravel
  return $ok
}
check "LV52 health within limit when external dns is mute" t_lv52_mute_dns

# paused_health <serviço> <corpo esperado>: pausa o serviço, mede /health e despausa.
paused_health() {
  local service="$1" expected="$2" out code secs body ok=0
  docker pause "$(container "$service")" >/dev/null
  out="$(curl -s -o "$WORK/paused.body" --max-time 10 -w '%{http_code} %{time_total}' localhost:8080/health)"
  docker unpause "$(container "$service")" >/dev/null
  code="${out% *}"; secs="${out#* }"; body="$(cat "$WORK/paused.body")"
  [ "$code" = 503 ] || { note "$service pausado: status $code"; ok=1; }
  [ "$body" = "$expected" ] || { note "$service pausado: corpo $body"; ok=1; }
  awk -v s="$secs" 'BEGIN { exit !(s < 3) }' || { note "$service pausado: ${secs}s"; ok=1; }
  shared_back
  return $ok
}

t_lv17_paused() {
  local ok=0
  paused_health redis-limiter "$LIMITER_FAIL" || ok=1
  paused_health postgres "$DATABASE_FAIL" || ok=1
  return $ok
}
check "LV17 health gives up on paused dependency" t_lv17_paused

# failure_logged <serviço> <check> <corpo esperado>: para o serviço e lê o log do php-fpm.
failure_logged() {
  local service="$1" name="$2" expected="$3" since body logs ok=0
  since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sleep 1
  docker stop "$(container "$service")" >/dev/null
  body="$(api /health)"
  logs="$(docker logs --since "$since" "$FPM" 2>&1)"
  docker start "$(container "$service")" >/dev/null
  [ "$body" = "$expected" ] || { note "$service parado: corpo $body"; ok=1; }
  [ "$(jq -c 'keys' <<< "$body")" = '["checks","status"]' ] || { note "chaves do corpo: $(jq -c 'keys' <<< "$body")"; ok=1; }
  grep -F 'health check' <<< "$logs" | grep -qF "$name" || { note "log do php-fpm sem a falha de $name"; ok=1; }
  shared_back
  return $ok
}

t_lv18_logged() {
  local ok=0
  failure_logged redis-limiter limiter "$LIMITER_FAIL" || ok=1
  failure_logged postgres database "$DATABASE_FAIL" || ok=1
  return $ok
}
check "LV18 failed check is logged not returned" t_lv18_logged

# --- S1 - código atual, falhas de subida ---

t_lv3_current_code() {
  local ok=0
  save "$routes"
  status_is /probe 404 || { note "antes: /probe respondeu $(api_status /probe)"; ok=1; }
  add_probe_route
  mkq up-laravel || { note "make up-laravel saiu com erro"; ok=1; }
  status_is /probe 200 || { note "depois: /probe respondeu $(api_status /probe)"; ok=1; }
  body_is /probe probe-ok || { note "corpo de /probe: $(api /probe)"; ok=1; }
  restore "$routes"
  mkq up-laravel
  return $ok
}
check "LV3 up-laravel serves current code" t_lv3_current_code

# --- S4 - make test-laravel com a stack no ar ---

t_lv33_test_keeps_stack() {
  local before
  before="$(lv_id "$FPM")"
  [ -n "$before" ] || return 1
  mkq test-laravel || { note "make test-laravel saiu com erro"; return 1; }
  [ "$(lv_id "$FPM")" = "$before" ] || { note "php-fpm mudou"; return 1; }
  status_is /health 200
}
check "LV33 test-laravel keeps running stack" t_lv33_test_keeps_stack

# failing_test_reported <arquivo>: um teste it() falho nesse arquivo faz o alvo sair com
# erro e imprimir o nome dele, então o Pest também encontra testes nesse lugar.
failing_test_reported() {
  local f="$1" out rc
  printf "<?php\n\nit('probe fails on purpose', function () {\n    expect(true)->toBeFalse();\n});\n" > "$f"
  out="$(mk test-laravel 2>&1)"
  rc=$?
  rm -f "$f"
  [ "$rc" -ne 0 ] || { note "make test-laravel saiu com 0"; return 1; }
  grep -qF 'probe fails on purpose' <<< "$out" || { note "saída sem o nome do teste"; return 1; }
}

check "LV32 test-laravel fails on failing test" failing_test_reported "$LV/tests/Feature/ProbeFailTest.php"
check "LV47 test-laravel runs module tests" failing_test_reported "$LV/app-modules/health/tests/ProbeFailTest.php"

# --- S3 - make laravel-composer ---

t_lv28_requires_args() {
  local out rc before
  before="$(docker ps -aq | sort)"
  out="$(mk laravel-composer 2>&1)"
  rc=$?
  [ "$rc" -ne 0 ] || { note "saiu com 0"; return 1; }
  grep -qF 'uso: make laravel-composer ARGS="<comando composer>"' <<< "$out" || { note "saída: $out"; return 1; }
  [ "$(docker ps -aq | sort)" = "$before" ] || { note "containers mudaram"; return 1; }
}
check "LV28 laravel-composer requires args" t_lv28_requires_args

t_lv29_composer_keeps_stack() {
  local before
  before="$(lv_id "$FPM")"
  [ -n "$before" ] || return 1
  mkq laravel-composer ARGS="--version" || { note "laravel-composer saiu com erro"; return 1; }
  [ "$(lv_id "$FPM")" = "$before" ] || { note "php-fpm mudou"; return 1; }
  status_is /health 200
}
check "LV29 laravel-composer keeps running stack" t_lv29_composer_keeps_stack

t_lv27_composer_writes_json_and_lock() {
  local json="$LV/composer.json" lock="$LV/composer.lock" uid ok=0 cache others
  # Tudo em apis/laravel, menos os dois arquivos que podem mudar e as cópias de save.
  others() { (cd "$LV" && find . -type f ! -name composer.json ! -name composer.lock ! -name '*.lvsave' -exec sha256sum {} + | sort -k2); }
  save "$json"; save "$lock"
  cache="$(others)"
  # Como root, o dono dos arquivos não diria nada: o make roda como outro uid,
  # com acesso ao socket do Docker, sobre uma cópia que pertence a ele.
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
  caller laravel-composer ARGS="require webmozart/assert:1.11.0" || { note "require saiu com erro"; return 1; }
  [ "$(others)" = "$cache" ] || { note "outro arquivo mudou em apis/laravel"; ok=1; }
  [ "$(jq -r '.require["webmozart/assert"] // empty' "$json")" != "" ] || { note "composer.json sem webmozart/assert em require"; ok=1; }
  [ "$(jq -r '.packages[] | select(.name == "webmozart/assert") | .version' "$lock")" = 1.11.0 ] \
    || { note "composer.lock sem webmozart/assert 1.11.0"; ok=1; }
  [ ! -e "$LV/vendor" ] || { note "apis/laravel/vendor existe"; ok=1; }
  cache="$(ls -A "$LV/bootstrap/cache")"
  [ "$cache" = .gitignore ] || { note "bootstrap/cache tem: $cache"; ok=1; }
  [ "$(owner_uid "$json")" = "$uid" ] || { note "dono de composer.json: $(owner_uid "$json"), esperado $uid"; ok=1; }
  return $ok
}
check "LV27 laravel-composer writes only json and lock" t_lv27_composer_writes_json_and_lock

t_lv30_installs_required() {
  local ok=0
  mkq up-laravel || { note "make up-laravel saiu com erro"; ok=1; }
  docker exec "$FPM" test -d /var/www/html/vendor/webmozart/assert || { note "vendor sem webmozart/assert"; ok=1; }
  restore "$LV/composer.json"; restore "$LV/composer.lock"
  return $ok
}
check "LV30 up-laravel installs required package" t_lv30_installs_required

t_lv43_composer_failure() {
  local lock="$LV/composer.lock" before rc
  before="$(sha256sum < "$lock")"
  mkq laravel-composer ARGS="require pacote/inexistente"
  rc=$?
  [ "$rc" -ne 0 ] || { note "saiu com 0"; return 1; }
  [ "$(sha256sum < "$lock")" = "$before" ] || { note "composer.lock mudou"; return 1; }
}
check "LV43 laravel-composer propagates composer failure" t_lv43_composer_failure

# --- Falhas de build e de subida ---

t_lv42_broken_lock() {
  local lock="$LV/composer.lock" ok=0
  save "$lock"
  printf '{' > "$lock"
  mkq up-laravel && { note "make up-laravel saiu com 0"; ok=1; }
  shared_healthy || { note "comuns não ficaram healthy"; ok=1; }
  mkq test-laravel && { note "make test-laravel saiu com 0"; ok=1; }
  restore "$lock"
  return $ok
}
check "LV42 broken lock fails build commands" t_lv42_broken_lock

# broken_boot <arquivo>: sem stack no ar, um erro de sintaxe no arquivo faz
# `make up-laravel` falhar e o nginx não ficar healthy.
broken_boot() {
  local file="$1" rc ok=0
  destroy_environment
  save "$file"
  sed -i '1a $broken = ;' "$file"
  mkq up-laravel
  rc=$?
  [ "$rc" -ne 0 ] || { note "$(basename "$file") quebrado: make up-laravel saiu com 0"; ok=1; }
  [ "$(health "$NG")" != healthy ] || { note "$(basename "$file") quebrado: nginx healthy"; ok=1; }
  restore "$file"
  return $ok
}

t_lv7_boot_failure() {
  local ok=0
  # Quebra o build: o composer inicializa o Laravel ao gerar o autoload.
  broken_boot "$LV/bootstrap/app.php" || ok=1
  # Quebra só em execução: o LimiterCheck só é carregado na requisição, /health
  # responde 500, e o healthcheck do nginx recusa.
  broken_boot "$LV/app-modules/health/src/Checks/LimiterCheck.php" || ok=1
  return $ok
}
check "LV7 up-laravel fails when laravel does not boot" t_lv7_boot_failure

t_lv8_taken_port() {
  local rc
  destroy_environment
  docker run -d --name "$PORT_BLOCKER" -p 8080:6379 redis:8.10.3-alpine >/dev/null || return 1
  mkq up-laravel
  rc=$?
  destroy_environment
  [ "$rc" -ne 0 ]
}
check "LV8 up-laravel fails on taken port 8080" t_lv8_taken_port

t_lv9_switch_and_down() {
  local ok=0
  mkq up-laravel || { note "make up-laravel saiu com erro"; return 1; }
  fake_stack go apis/golang
  mkq up-go || { note "make up-go saiu com erro"; ok=1; }
  [ -z "$(project_containers cadastro-feliz-laravel)" ] || { note "containers da Laravel depois de up-go"; ok=1; }
  mkq up-laravel || { note "make up-laravel saiu com erro"; ok=1; }
  mkq down-laravel || { note "make down-laravel saiu com erro"; ok=1; }
  [ -z "$(project_containers cadastro-feliz-laravel)" ] || { note "containers da Laravel depois de down"; ok=1; }
  [ -z "$(docker volume ls -q --filter label=com.docker.compose.project=cadastro-feliz-laravel)" ] || { note "volume da Laravel depois de down"; ok=1; }
  shared_healthy || { note "comuns não estão healthy"; ok=1; }
  rm -rf "$WORK/apis/golang"
  return $ok
}
check "LV9 laravel leaves on switch and down" t_lv9_switch_and_down

# --- S3 - make watch-laravel ---

# O watch roda em um grupo de processos próprio (set -m), para o SIGINT chegar ao
# make e ao docker compose juntos, como o Ctrl+C de um terminal.
start_watch() {
  set -m
  make --no-print-directory -C "$WORK" watch-laravel > "$WORK/watch.log" 2>&1 &
  WATCH_PID=$!
  set +m
}
watch_ready() { grep -q 'Watch enabled' "$WORK/watch.log"; }
watch_alive() { [ -n "$WATCH_PID" ] && kill -0 "$WATCH_PID" 2>/dev/null; }
watch_gone() { ! watch_alive; }
stop_watch() {
  watch_alive || return 0
  kill -INT -- "-$WATCH_PID" 2>/dev/null
  wait_for 30 watch_gone
  kill -KILL -- "-$WATCH_PID" 2>/dev/null
  WATCH_PID=
  return 0
}

t_lv23_watch_starts() {
  local ok=0
  destroy_environment
  rm -f "$WORK/.env"
  save "$routes"
  add_probe_route
  start_watch
  wait_for 600 watch_ready || { note "watch não ficou pronto: $(tail -5 "$WORK/watch.log")"; return 1; }
  [ -f "$WORK/.env" ] || { note "sem .env"; ok=1; }
  network_exists || { note "sem a rede"; ok=1; }
  lv_healthy || { note "nginx $(health "$NG"), php-fpm $(health "$FPM"), horizon $(health "$HZ"), redis $(health "$RD"), scheduler $(health "$SC")"; ok=1; }
  status_is /probe 200 || { note "/probe respondeu $(api_status /probe)"; ok=1; }
  watch_alive || { note "watch saiu"; ok=1; }
  return $ok
}
check "LV23 watch-laravel starts stack with current code" t_lv23_watch_starts

t_lv24_watch_syncs() {
  local before ok=0 module_routes="$LV/app-modules/users/routes/users-routes.php"
  before="$(lv_id "$FPM")"
  [ -n "$before" ] && watch_alive || { note "watch fora do ar"; return 1; }
  save "$module_routes"
  mkdir -p "$LV/app/Probe" "$LV/app-modules/users/src/Probe"
  printf '<?php\n\nnamespace App\\Probe;\n\nclass ProbeValue\n{\n    public static function value(): string\n    {\n        return '"'"'app'"'"';\n    }\n}\n' > "$LV/app/Probe/ProbeValue.php"
  printf '<?php\n\nnamespace Modules\\Users\\Probe;\n\nclass ProbeValue\n{\n    public static function value(): string\n    {\n        return '"'"'um'"'"';\n    }\n}\n' > "$LV/app-modules/users/src/Probe/ProbeValue.php"
  printf '<?php\n\nreturn ['"'"'value'"'"' => '"'"'cfg'"'"'];\n' > "$LV/config/probe.php"
  printf '\nRoute::get('"'"'/probe-sync'"'"', fn () => \\Modules\\Users\\Probe\\ProbeValue::value().'"'"'-'"'"'.\\App\\Probe\\ProbeValue::value().'"'"'-'"'"'.config('"'"'probe.value'"'"'));\n' >> "$module_routes"
  wait_for 10 body_is /probe-sync um-app-cfg || { note "/probe-sync: $(api /probe-sync)"; ok=1; }
  sed -i "s/'um'/'dois'/" "$LV/app-modules/users/src/Probe/ProbeValue.php"
  wait_for 10 body_is /probe-sync dois-app-cfg || { note "/probe-sync depois da troca: $(api /probe-sync)"; ok=1; }
  echo probe > "$LV/tests/probe-sync.txt"
  echo probe > "$LV/bootstrap/probe-sync.txt"
  echo probe > "$LV/routes/probe-sync.txt"
  wait_for 10 docker exec "$FPM" test -f /var/www/html/tests/probe-sync.txt || { note "tests não sincronizou"; ok=1; }
  wait_for 10 docker exec "$FPM" test -f /var/www/html/bootstrap/probe-sync.txt || { note "bootstrap não sincronizou"; ok=1; }
  wait_for 10 docker exec "$FPM" test -f /var/www/html/routes/probe-sync.txt || { note "routes não sincronizou"; ok=1; }
  [ "$(lv_id "$FPM")" = "$before" ] || { note "php-fpm reiniciou"; ok=1; }
  rm -rf "$LV/app/Probe" "$LV/app-modules/users/src/Probe" "$LV/config/probe.php" "$LV/tests/probe-sync.txt" "$LV/bootstrap/probe-sync.txt" "$LV/routes/probe-sync.txt"
  restore "$module_routes"
  return $ok
}
check "LV24 watch syncs code without restart" t_lv24_watch_syncs

new_fpm_healthy() { local id; id="$(lv_id "$FPM")"; [ -n "$id" ] && [ "$id" != "$1" ] && lv_healthy && status_is /health 200; }

# rebuild_on <nome> <arquivo> <comando que muda o arquivo>
rebuild_on() {
  local name="$1" file="$2" before hz sc image ok=0; shift 2
  before="$(lv_id "$FPM")"
  hz="$(lv_id "$HZ")"
  sc="$(lv_id "$SC")"
  image="$(docker inspect -f '{{.Image}}' "$FPM")"
  watch_alive || { note "watch fora do ar"; return 1; }
  save "$file"
  "$@"
  wait_for 180 new_fpm_healthy "$before" \
    || { note "$name: php-fpm $(lv_id "$FPM" | cut -c1-12), $(health "$FPM"), horizon $(health "$HZ"), scheduler $(health "$SC")"; ok=1; }
  # O worker e o relay voltam recriados e na imagem nova, não só o php-fpm.
  [ "$(docker inspect -f '{{.Image}}' "$FPM")" != "$image" ] || { note "$name: a imagem não mudou"; ok=1; }
  [ "$(lv_id "$HZ")" != "$hz" ] || { note "$name: horizon não foi recriado"; ok=1; }
  [ "$(lv_id "$SC")" != "$sc" ] || { note "$name: scheduler não foi recriado"; ok=1; }
  [ "$(docker inspect -f '{{.Image}}' "$HZ")" = "$(docker inspect -f '{{.Image}}' "$FPM")" ] || { note "$name: horizon em outra imagem"; ok=1; }
  [ "$(docker inspect -f '{{.Image}}' "$SC")" = "$(docker inspect -f '{{.Image}}' "$FPM")" ] || { note "$name: scheduler em outra imagem"; ok=1; }
  before="$(lv_id "$FPM")"
  restore "$file"
  wait_for 180 new_fpm_healthy "$before"
  return $ok
}
change_description() { jq '.description = "probe"' "$LV/composer.json.lvsave" > "$LV/composer.json"; }
touch_lock() { printf '\n' >> "$LV/composer.lock"; }
# Um comentário gera a mesma imagem; um LABEL no último estágio gera outra.
touch_dockerfile() { printf 'LABEL probe=rebuild\n' >> "$LV/docker/php/Dockerfile"; }

check "LV25 watch rebuilds on composer.json" rebuild_on composer.json "$LV/composer.json" change_description
check "LV25 watch rebuilds on composer.lock" rebuild_on composer.lock "$LV/composer.lock" touch_lock
check "LV25 watch rebuilds on docker/php" rebuild_on docker/php "$LV/docker/php/Dockerfile" touch_dockerfile

t_lv26_interrupt() {
  local ng fpm ok=0
  ng="$(lv_id "$NG")"; fpm="$(lv_id "$FPM")"
  stop_watch
  [ "$(docker inspect -f '{{.State.Status}}' "$NG")" = running ] || { note "nginx não está running"; ok=1; }
  [ "$(docker inspect -f '{{.State.Status}}' "$FPM")" = running ] || { note "php-fpm não está running"; ok=1; }
  [ "$(lv_id "$NG")" = "$ng" ] && [ "$(lv_id "$FPM")" = "$fpm" ] || { note "containers mudaram"; ok=1; }
  status_is /health 200 || { note "/health respondeu $(api_status /health)"; ok=1; }
  restore "$routes"
  return $ok
}
check "LV26 watch interrupt keeps stack" t_lv26_interrupt

stop_watch
