# Container do frontend (.specs/features/frontend-container). Carregado por run.sh
# depois de stack.sh, cujo fake_stack é usado em FE22 e FE23.

FE=cadastro-feliz-shared-frontend-1
FE_IMAGE=cadastro-feliz-shared-frontend
WATCH_PID=

fe_id() { docker ps -aq --no-trunc --filter "name=^$FE\$"; }
fe_image() { docker image inspect -f '{{.Id}}' "$FE_IMAGE" 2>/dev/null; }
page() { curl -s --max-time 60 "localhost:3000$1"; }
status_of() { curl -s -o /dev/null --max-time 60 -w '%{http_code}' "localhost:3000$1"; }

# wait_for <segundos> <comando...>: repete o comando a cada segundo até ele passar.
wait_for() {
  local secs="$1" i; shift
  for ((i = 0; i < secs; i++)); do "$@" && return 0; sleep 1; done
  "$@"
}

page_has() { page "$1" | grep -qF "$2"; }
status_is() { [ "$(status_of "$1")" = "$2" ]; }
fe_healthy() { [ "$(health "$FE")" = healthy ]; }
four_healthy() { shared_healthy && fe_healthy; }

# O watch roda em um grupo de processos próprio (set -m), para o SIGINT chegar ao
# make e ao docker compose juntos, como o Ctrl+C de um terminal.
start_watch() {
  set -m
  make --no-print-directory -C "$WORK" watch-frontend > "$WORK/watch.log" 2>&1 &
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

page_file="$WORK/frontend/src/app/page.tsx"

# --- S1 - Frontend no ar com make up-shared ---

t_fe1_skeleton() {
  destroy_environment
  rm -f "$WORK/.env"
  mkq up-shared || { note "make up-shared saiu com erro"; return 1; }
  four_healthy || { note "frontend: $(health "$FE")"; return 1; }
  status_is / 200 || { note "GET / respondeu $(status_of /)"; return 1; }
  page_has / 'Cadastro Feliz' || { note "sem Cadastro Feliz"; return 1; }
  page_has / 'localhost:8080' || { note "sem localhost:8080"; return 1; }
}
check "FE1 up-shared serves skeleton" t_fe1_skeleton

t_fe2_rerun() {
  local before after img_before img_after
  before="$(project_containers cadastro-feliz-shared | sort)"
  [ "$(echo "$before" | grep -c .)" -eq 4 ] || { note "esperava 4 containers: $before"; return 1; }
  img_before="$(fe_image)"
  mkq up-shared || return 1
  after="$(project_containers cadastro-feliz-shared | sort)"
  img_after="$(fe_image)"
  [ "$before" = "$after" ] || { note "containers mudaram"; return 1; }
  [ -n "$img_before" ] && [ "$img_before" = "$img_after" ] || { note "imagem mudou"; return 1; }
}
check "FE2 up-shared rerun keeps frontend" t_fe2_rerun

t_fe3_current_code() {
  local ok=0
  sed -i 's/Cadastro Feliz/Cadastro Probe/' "$page_file"
  mkq up-shared || { note "make up-shared saiu com erro"; ok=1; }
  page_has / 'Cadastro Probe' || { note "sem Cadastro Probe"; ok=1; }
  page_has / 'Cadastro Feliz' && { note "ainda mostra Cadastro Feliz"; ok=1; }
  sed -i 's/Cadastro Probe/Cadastro Feliz/' "$page_file"
  return $ok
}
check "FE3 up-shared serves current code" t_fe3_current_code

t_fe4_api_url() {
  local img_before img_after ok=0
  mkq up-shared || return 1
  img_before="$(fe_image)"
  sed -i 's#^NEXT_PUBLIC_API_URL=.*#NEXT_PUBLIC_API_URL=http://localhost:9090#' "$WORK/.env"
  mkq up-shared || { note "make up-shared saiu com erro"; ok=1; }
  img_after="$(fe_image)"
  page_has / 'localhost:9090' || { note "sem localhost:9090"; ok=1; }
  page_has / 'localhost:8080' && { note "ainda mostra localhost:8080"; ok=1; }
  [ "$img_before" = "$img_after" ] || { note "a imagem foi reconstruída"; ok=1; }
  cp "$WORK/.env.example" "$WORK/.env"
  return $ok
}
check "FE4 api url read at start" t_fe4_api_url

t_fe6_base_image() {
  grep -qx 'FROM node:26.13.0-alpine' "$WORK/frontend/Dockerfile"
}
check "FE6 frontend base image" t_fe6_base_image

t_fe8_build_failure() {
  local lock="$WORK/frontend/package-lock.json" rc ok=0
  cp "$lock" "$WORK/lock.bak"
  echo '{' > "$lock"
  destroy_environment
  mk up-shared >/dev/null 2>&1
  rc=$?
  [ "$rc" -ne 0 ] || { note "make up-shared saiu com 0"; ok=1; }
  shared_healthy || ok=1
  cp "$WORK/lock.bak" "$lock"
  return $ok
}
check "FE8 frontend build failure keeps shared" t_fe8_build_failure

t_fe9_compile_error() {
  local ok=0
  cp "$page_file" "$WORK/page.bak"
  echo 'export default function Home() { return <main>' > "$page_file"
  mkq up-shared || { note "make up-shared saiu com erro"; ok=1; }
  status_is / 500 || { note "GET / respondeu $(status_of /)"; ok=1; }
  sleep 20
  fe_healthy || { note "frontend: $(health "$FE")"; ok=1; }
  cp "$WORK/page.bak" "$page_file"
  return $ok
}
check "FE9 compile error keeps frontend healthy" t_fe9_compile_error

t_fe10_next_dev_as_node() {
  mkq up-shared || return 1
  [ "$(docker exec "$FE" id -u)" = 1000 ] || { note "uid: $(docker exec "$FE" id -u)"; return 1; }
  docker inspect -f '{{join .Config.Cmd " "}}' "$FE" | grep -qF 'next dev' \
    || { note "comando: $(docker inspect -f '{{join .Config.Cmd " "}}' "$FE")"; return 1; }
}
check "FE10 frontend runs next dev as node" t_fe10_next_dev_as_node

t_fe11_exact_versions() {
  local f="$WORK/frontend/package.json"
  grep -qF '"next": "16.4.5"' "$f" || return 1
  grep -qF '"react": "19.3.1"' "$f" || return 1
  grep -qF '"react-dom": "19.3.1"' "$f" || return 1
  # Só dependencies e devDependencies têm valores de versão neste arquivo.
  ! grep -qE '": "[~^]' "$f" || { note "versão com faixa: $(grep -E '": "[~^]' "$f")"; return 1; }
}
check "FE11 exact dependency versions" t_fe11_exact_versions

t_fe12_ignores() {
  git -C "$REPO" check-ignore -q frontend/node_modules/x || { note "node_modules não ignorado"; return 1; }
  git -C "$REPO" check-ignore -q frontend/.next/x || { note ".next não ignorado"; return 1; }
  [ ! -e "$REPO/frontend/.env" ] || { note "frontend/.env existe"; return 1; }
}
check "FE12 frontend ignores and no env" t_fe12_ignores

# --- S2 - Edição pelo make watch-frontend ---

t_fe13_watch_start() {
  local ok=0
  destroy_environment
  rm -f "$WORK/.env"
  sed -i 's/Cadastro Feliz/Cadastro Watch/' "$page_file"
  start_watch
  wait_for 300 watch_ready || { note "watch não ficou pronto: $(tail -5 "$WORK/watch.log")"; return 1; }
  [ -f "$WORK/.env" ] || { note ".env ausente"; ok=1; }
  network_exists || { note "rede ausente"; ok=1; }
  fe_healthy || { note "frontend: $(health "$FE")"; ok=1; }
  page_has / 'Cadastro Watch' || { note "sem a edição"; ok=1; }
  watch_alive || { note "o watch saiu"; ok=1; }
  return $ok
}
check "FE13 watch starts frontend with current code" t_fe13_watch_start

t_fe14_watch_edit() {
  local before
  watch_alive || return 1
  before="$(fe_id)"
  sed -i 's/Cadastro Watch/Cadastro Sync/' "$page_file"
  wait_for 10 page_has / 'Cadastro Sync' || { note "edição não chegou em 10 s"; return 1; }
  [ "$(fe_id)" = "$before" ] || { note "container recriado"; return 1; }
}
check "FE14 watch syncs edit" t_fe14_watch_edit

t_fe15_watch_create_delete() {
  local dir="$WORK/frontend/src/app/probe"
  watch_alive || return 1
  mkdir -p "$dir"
  printf 'export default function Probe() {\n  return <p>probe</p>;\n}\n' > "$dir/page.tsx"
  wait_for 10 status_is /probe 200 || { note "criação: GET /probe $(status_of /probe)"; return 1; }
  rm -rf "$dir"
  wait_for 10 status_is /probe 404 || { note "remoção: GET /probe $(status_of /probe)"; return 1; }
}
check "FE15 watch syncs create and delete" t_fe15_watch_create_delete

# fe16 <arquivo> <mudança>: muda o arquivo com o watch ativo e espera um container novo.
fe_rebuilt_from() { local id; id="$(fe_id)"; [ -n "$id" ] && [ "$id" != "$1" ] && fe_healthy && status_is / 200; }
t_fe16_rebuild() {
  local file="$WORK/frontend/$1" before
  watch_alive || return 1
  before="$(fe_id)"
  case "$1" in
    package.json) sed -i 's/"private": true,/"private": true, "description": "probe",/' "$file" ;;
    package-lock.json) echo >> "$file" ;;
    next.config.ts) echo '// probe' >> "$file" ;;
  esac
  wait_for 120 fe_rebuilt_from "$before" || { note "$1: sem container novo em 120 s"; return 1; }
}
check "FE16 watch rebuilds on package.json" t_fe16_rebuild package.json
check "FE16 watch rebuilds on package-lock.json" t_fe16_rebuild package-lock.json
check "FE16 watch rebuilds on next.config.ts" t_fe16_rebuild next.config.ts

t_fe17_watch_interrupt() {
  local before
  watch_alive || return 1
  before="$(fe_id)"
  kill -INT -- "-$WATCH_PID"
  wait_for 30 watch_gone || { note "o watch não saiu"; stop_watch; return 1; }
  WATCH_PID=
  sleep 5
  [ "$(fe_id)" = "$before" ] || { note "container mudou"; return 1; }
  [ "$(docker inspect -f '{{.State.Status}}' "$FE")" = running ] || { note "container parado"; return 1; }
  status_is / 200 || { note "GET / respondeu $(status_of /)"; return 1; }
}
check "FE17 watch interrupt keeps frontend" t_fe17_watch_interrupt
stop_watch

# --- S3 - Dependências por make frontend-npm ---

new_workdir
destroy_environment

t_fe19_npm_without_args() {
  local out rc
  out="$(mk frontend-npm 2>&1)"
  rc=$?
  [ "$rc" -ne 0 ] || { note "saiu com 0"; return 1; }
  grep -qF 'uso: make frontend-npm ARGS="<comando npm>"' <<< "$out" || { note "saída: $out"; return 1; }
  any_containers && { note "containers criados"; return 1; }
  return 0
}
check "FE19 frontend-npm refuses without args" t_fe19_npm_without_args

t_fe18_npm_exact() {
  local f="$WORK/frontend/package.json" lock="$WORK/frontend/package-lock.json" odd
  mkq frontend-npm ARGS="install is-number@7.0.0" || { note "install is-number saiu com erro"; return 1; }
  grep -qF '"is-number": "7.0.0"' "$f" || { note "package.json sem is-number 7.0.0"; return 1; }
  grep -A3 -F '"node_modules/is-number": {' "$lock" | grep -qF '"version": "7.0.0"' \
    || { note "lock sem node_modules/is-number 7.0.0"; return 1; }
  mkq frontend-npm ARGS="install is-odd" || { note "install is-odd saiu com erro"; return 1; }
  odd="$(grep -F '"is-odd":' "$f")"
  grep -qE '"is-odd": "[0-9]' <<< "$odd" || { note "is-odd gravado como: $odd"; return 1; }
  [ ! -e "$WORK/frontend/node_modules" ] || { note "frontend/node_modules existe"; return 1; }
  [ -O "$f" ] || { note "package.json não pertence a $(id -u)"; return 1; }
}
check "FE18 frontend-npm writes exact versions only" t_fe18_npm_exact

t_fe21_new_dependency() {
  mkq up-shared || { note "make up-shared saiu com erro"; return 1; }
  docker exec "$FE" test -d /app/node_modules/is-number
}
check "FE21 up-shared installs new dependency" t_fe21_new_dependency

t_fe20_npm_keeps_frontend() {
  local before
  before="$(fe_id)"
  [ -n "$before" ] || return 1
  mkq frontend-npm ARGS="--version" || { note "frontend-npm saiu com erro"; return 1; }
  [ "$(fe_id)" = "$before" ] || { note "container mudou"; return 1; }
  status_is / 200
}
check "FE20 frontend-npm leaves frontend running" t_fe20_npm_keeps_frontend

# --- S4 - Frontend fora do caminho do migrate e das stacks ---

new_workdir
destroy_environment

no_frontend() { [ -z "$(fe_id)" ]; }

t_fe22_broken_frontend() {
  local ok=0
  echo '{' > "$WORK/frontend/package-lock.json"
  mkq migrate || { note "make migrate saiu com erro"; ok=1; }
  [ "$(psql_q 'select version, dirty from schema_migrations')" = '1|f' ] || { note "versão 1 ausente"; ok=1; }
  fake_stack go apis/golang
  mkq up-go || { note "make up-go saiu com erro"; ok=1; }
  [ "$(health cadastro-feliz-go-api-1)" = healthy ] || { note "stack: $(health cadastro-feliz-go-api-1)"; ok=1; }
  return $ok
}
check "FE22 broken frontend does not block migrate or stack" t_fe22_broken_frontend

new_workdir
destroy_environment

t_fe23_no_frontend() {
  mkq migrate || { note "make migrate saiu com erro"; return 1; }
  no_frontend || { note "frontend existe depois do migrate"; return 1; }
  fake_stack go apis/golang
  mkq up-go || { note "make up-go saiu com erro"; return 1; }
  no_frontend || { note "frontend existe depois do up-go"; return 1; }
}
check "FE23 migrate and stack do not start frontend" t_fe23_no_frontend

t_fe28_help() {
  local out
  out="$(mk help)"
  grep -qF 'make watch-frontend' <<< "$out" && grep -qF 'make frontend-npm' <<< "$out"
}
check "FE28 help lists frontend targets" t_fe28_help
