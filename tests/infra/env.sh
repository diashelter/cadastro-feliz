# Variáveis de ambiente por projeto (decisão 29): cada projeto Compose tem os padrões das próprias
# variáveis, nenhum `make` cria arquivo de ambiente, e o .env opcional ao lado de um compose
# sobrescreve só aquele projeto. Plano e checks em .specs/features/env-per-project. Carregado por
# run.sh.

EV_FE="$(container frontend)"
EV_FPM=cadastro-feliz-laravel-php-fpm-1
EV_NEST_API=cadastro-feliz-nest-api-1
EV_NEST_WORKER=cadastro-feliz-nest-worker-1
EV_LARAVEL=apis/laravel/docker-compose.yml
EV_NEST=apis/nestjs/docker-compose.yml

ev_page() { curl -s --max-time 30 localhost:3000/; }
ev_health() { curl -s -o /dev/null --max-time 10 -w '%{http_code}' localhost:8080/health; }
ev_register() {
  curl -s -o /dev/null --max-time 10 -w '%{http_code}' -X POST localhost:8080/users \
    -H 'Content-Type: application/json' -H 'Accept: application/json' -d "{\"name\":\"Ana\",\"email\":\"$1\"}"
}

# O .env.example que existia antes da decisão 29, com dois valores trocados: um .env antigo e
# completo na raiz de quem já clonou.
ev_old_root_env() {
  cat <<'ENV'
API_PORT=8080
NEXT_PUBLIC_API_URL=http://localhost:8080
CORS_ALLOWED_ORIGIN=http://localhost:3000
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=cadastro_feliz
DB_USERNAME=cadastro_feliz
DB_PASSWORD=cadastro_feliz
LIMITER_REDIS_HOST=redis-limiter
LIMITER_REDIS_PORT=6379
SMTP_HOST=mailpit
SMTP_PORT=1025
MAIL_FROM=no-reply@cadastro-feliz.local
REGISTRATION_MAX_ATTEMPTS=2
REGISTRATION_ATTEMPT_WINDOW_SECONDS=900
REGISTRATION_MAX_PER_IP=20
REGISTRATION_IP_WINDOW_SECONDS=3600
OUTBOX_BATCH_SIZE=7
OUTBOX_REPUBLISH_AFTER_SECONDS=300
OUTBOX_MAX_ATTEMPTS=5
OUTBOX_BACKOFF_BASE_SECONDS=30
REDIS_HOST=redis
REDIS_PORT=6379
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672/
APP_KEY=base64:nweRuAMF1T21Cb0MaIsckAFyVgQ6b7XYR8y/unbAdyc=
APP_ENV=local
APP_DEBUG=true
ENV
}

# ev_stacks_resolve <tentativas> <lote>: as duas stacks resolvem os valores dados.
ev_stacks_resolve() {
  local ok=0 v
  v="$(compose_env "$EV_LARAVEL" php-fpm REGISTRATION_MAX_ATTEMPTS)"; [ "$v" = "$1" ] || { note "laravel REGISTRATION_MAX_ATTEMPTS=$v"; ok=1; }
  v="$(compose_env "$EV_LARAVEL" php-fpm OUTBOX_BATCH_SIZE)"; [ "$v" = "$2" ] || { note "laravel OUTBOX_BATCH_SIZE=$v"; ok=1; }
  v="$(compose_env "$EV_NEST" api REGISTRATION_MAX_ATTEMPTS)"; [ "$v" = "$1" ] || { note "nest REGISTRATION_MAX_ATTEMPTS=$v"; ok=1; }
  v="$(compose_env "$EV_NEST" worker OUTBOX_BATCH_SIZE)"; [ "$v" = "$2" ] || { note "nest OUTBOX_BATCH_SIZE=$v"; ok=1; }
  return $ok
}

# --- S4 e S1, sem subir containers ---

t_ev4_no_example() {
  local ok=0 found
  found="$(find "$WORK" -name .env.example -not -path '*/node_modules/*' -not -path '*/vendor/*')"
  [ -z "$found" ] || { note "na cópia: $found"; ok=1; }
  found="$(git -C "$REPO" ls-files | grep -E '(^|/)\.env\.example$')"
  [ -z "$found" ] || { note "versionado: $found"; ok=1; }
  for p in .env apis/laravel/.env apis/nestjs/.env; do
    git -C "$REPO" check-ignore -q "$p" || { note "$p não é ignorado"; ok=1; }
  done
  return $ok
}
check "EV4 no env example and env ignored in every project" t_ev4_no_example

t_ev9_compose_defaults() {
  local ok=0 c missing out raw
  [ -z "$(env_files)" ] || { note "há .env na cópia: $(env_files)"; return 1; }
  for c in "${COMPOSES[@]}"; do
    missing="$(env_missing_defaults "$c")"
    [ -z "$missing" ] || { note "sem padrão: $missing"; ok=1; }
    # Shell limpo: uma variável exportada por quem roda os testes não cobre um padrão ausente.
    out="$(cd "$WORK" && env -i PATH="$PATH" HOME="$HOME" ${DOCKER_HOST:+DOCKER_HOST="$DOCKER_HOST"} \
      docker compose -f "$c" --profile '*' config --format json 2>"$WORK/ev9.err")" \
      || { note "$c: config falhou: $(cat "$WORK/ev9.err")"; ok=1; continue; }
    ! grep -qi 'variable is not set' "$WORK/ev9.err" || { note "$c: $(cat "$WORK/ev9.err")"; ok=1; }
    [ "$(jq '[.services[] | (.environment // {} | to_entries[] | .value), (.ports // [] | .[] | .published)] | map(select(. == null or . == "")) | length' <<< "$out")" = 0 ] \
      || { note "$c: valor vazio em environment ou ports"; ok=1; }
    # No command, só um vazio que veio de uma interpolação: o `--save ""` do redis é literal.
    raw="$(cd "$WORK" && docker compose -f "$c" --profile '*' config --no-interpolate --format json 2>/dev/null)"
    [ "$(jq -n --argjson r "$raw" --argjson o "$out" '[$o.services | to_entries[] | .key as $s
        | (.value.command // []) | to_entries[] | select(.value == "")
        | select((($r.services[$s].command // [])[.key] // "") | tostring | test("\\$"))] | length')" = 0 ] \
      || { note "$c: valor vazio em command"; ok=1; }
  done
  rm -f "$WORK/ev9.err"
  return $ok
}
check "EV9 every compose resolves its variables without env files" t_ev9_compose_defaults

t_ev10_missing_default_named() {
  local ok=0 f="$WORK/$EV_NEST" saved="$WORK/ev10.yml" out
  cp "$f" "$saved"
  sed 's/\${OUTBOX_BATCH_SIZE:-100}/${OUTBOX_BATCH_SIZE}/' "$saved" > "$f"
  out="$(env_missing_defaults "$EV_NEST")"
  [ "$out" = "$EV_NEST OUTBOX_BATCH_SIZE" ] || { note "sem o export: '$out'"; ok=1; }
  out="$(OUTBOX_BATCH_SIZE=100 env_missing_defaults "$EV_NEST")"
  [ "$out" = "$EV_NEST OUTBOX_BATCH_SIZE" ] || { note "com o export: '$out'"; ok=1; }
  cp "$saved" "$f" && rm -f "$saved"
  for c in "${COMPOSES[@]}"; do
    out="$(env_missing_defaults "$c")"
    [ -z "$out" ] || { note "compose real: $out"; ok=1; }
  done
  return $ok
}
check "EV10 a variable without default is named" t_ev10_missing_default_named

t_ev3_root_env_isolated() {
  local ok=0
  env_set . REGISTRATION_MAX_ATTEMPTS=2 OUTBOX_BATCH_SIZE=7
  ev_stacks_resolve 5 100 || { note "com o .env parcial na raiz"; ok=1; }
  ev_old_root_env > "$WORK/.env"
  ev_stacks_resolve 5 100 || { note "com o .env antigo e completo na raiz"; ok=1; }
  [ "$(compose_env docker-compose.yml frontend NEXT_PUBLIC_API_URL)" = http://localhost:8080 ] || { note "shared não leu o .env antigo"; ok=1; }
  rm -f "$WORK/.env"
  return $ok
}
check "EV3 root env does not reach the stacks" t_ev3_root_env_isolated

# --- S1 - cadastro-feliz-shared ---

t_ev1_up_shared() {
  local ok=0
  destroy_environment
  [ -z "$(env_files)" ] || { note "há .env na cópia: $(env_files)"; return 1; }
  mkq up-shared || { note "make up-shared saiu com erro"; return 1; }
  shared_healthy || ok=1
  [ "$(health "$EV_FE")" = healthy ] || { note "frontend: $(health "$EV_FE")"; ok=1; }
  ev_page | grep -qF 'localhost:8080' || { note "a página não mostra localhost:8080"; ok=1; }
  [ -z "$(env_files)" ] || { note "make criou: $(env_files)"; ok=1; }
  return $ok
}
check "EV1 up-shared on a clean copy creates no env file" t_ev1_up_shared

t_ev2_migrate() {
  local ok=0 last
  destroy_environment
  mkq migrate || { note "make migrate saiu com erro"; return 1; }
  last="$(find "$WORK/database/migrations" -name '*.up.sql' | sed -E 's#.*/0*([0-9]+)_.*#\1#' | sort -n | tail -1)"
  [ "$(psql_q 'select version, dirty from schema_migrations')" = "$last|f" ] \
    || { note "versão: $(psql_q 'select version, dirty from schema_migrations'), esperada $last|f"; ok=1; }
  [ -z "$(env_files)" ] || { note "make criou: $(env_files)"; ok=1; }
  return $ok
}
check "EV2 migrate on a clean copy creates no env file" t_ev2_migrate

# --- S2 - cadastro-feliz-laravel ---

t_ev5_laravel_override() {
  local ok=0 codes v
  mkq up-laravel || { note "make up-laravel saiu com erro"; return 1; }
  psql_q 'truncate users cascade' >/dev/null
  redis_q FLUSHALL >/dev/null
  [ "$(ev_register ana@example.com)" = 201 ] || { note "o cadastro de Ana falhou"; return 1; }
  redis_q FLUSHALL >/dev/null
  env_set apis/laravel REGISTRATION_MAX_ATTEMPTS=2
  mkq up-laravel || { note "make up-laravel com o .env da stack saiu com erro"; rm -f "$WORK/apis/laravel/.env"; return 1; }
  codes="$(ev_register ana@example.com) $(ev_register ana@example.com) $(ev_register ana@example.com)"
  [ "$codes" = '409 409 429' ] || { note "respostas: $codes"; ok=1; }
  v="$(compose_env "$EV_NEST" api REGISTRATION_MAX_ATTEMPTS)"
  [ "$v" = 5 ] || { note "nest REGISTRATION_MAX_ATTEMPTS=$v"; ok=1; }
  rm -f "$WORK/apis/laravel/.env"
  redis_q FLUSHALL >/dev/null
  mkq up-laravel || { note "a stack não voltou aos padrões"; ok=1; }
  return $ok
}
check "EV5 laravel env override stays in laravel" t_ev5_laravel_override

t_ev6_laravel_image() {
  local ok=0
  env_set apis/laravel PROBE_ONLY_IN_FILE=1
  # Com o arquivo na pasta, o build passa por ele: se não estivesse no .dockerignore, o COPY
  # mudaria e o arquivo entraria na imagem.
  mkq up-laravel || { note "make up-laravel saiu com erro"; ok=1; }
  docker exec "$EV_FPM" test ! -e /var/www/html/.env || { note "a imagem tem /var/www/html/.env"; ok=1; }
  [ -z "$(docker exec "$EV_FPM" printenv PROBE_ONLY_IN_FILE)" ] || { note "o php-fpm recebeu PROBE_ONLY_IN_FILE"; ok=1; }
  [ "$(ev_health)" = 200 ] || { note "GET /health respondeu $(ev_health)"; ok=1; }
  rm -f "$WORK/apis/laravel/.env"
  return $ok
}
check "EV6 laravel image leaves out the stack env file" t_ev6_laravel_image

# --- S3 - cadastro-feliz-nest ---

t_ev7_nest_override() {
  local ok=0 v
  env_set apis/nestjs OUTBOX_BATCH_SIZE=2
  mkq up-nest || { note "make up-nest saiu com erro"; rm -f "$WORK/apis/nestjs/.env"; return 1; }
  v="$(docker exec "$EV_NEST_WORKER" printenv OUTBOX_BATCH_SIZE)"
  [ "$v" = 2 ] || { note "worker OUTBOX_BATCH_SIZE=$v"; ok=1; }
  v="$(compose_env "$EV_LARAVEL" php-fpm OUTBOX_BATCH_SIZE)"
  [ "$v" = 100 ] || { note "laravel OUTBOX_BATCH_SIZE=$v"; ok=1; }
  rm -f "$WORK/apis/nestjs/.env"
  return $ok
}
check "EV7 nest env override stays in nest" t_ev7_nest_override

t_ev8_laravel_env_not_in_nest() {
  local ok=0 v
  env_set apis/laravel REGISTRATION_MAX_ATTEMPTS=2
  mkq up-nest || { note "make up-nest saiu com erro"; ok=1; }
  v="$(docker exec "$EV_NEST_API" printenv REGISTRATION_MAX_ATTEMPTS)"
  [ "$v" = 5 ] || { note "api REGISTRATION_MAX_ATTEMPTS=$v"; ok=1; }
  rm -f "$WORK/apis/laravel/.env"
  return $ok
}
check "EV8 laravel env does not reach nest" t_ev8_laravel_env_not_in_nest
