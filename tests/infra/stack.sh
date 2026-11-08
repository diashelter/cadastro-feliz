# S3 - Troca de stack pelo Makefile. Carregado por run.sh.

# --- Suíte de contrato por stack (.specs/features/contract-suite) ---
# run.sh roda aqui de novo, na cópia de trabalho: sem ambiente cadastro-feliz-*, ele recusa
# antes do Docker ou roda os arquivos substitutos de cs_stub_files.

CS_NO_DOCKER=unix:///cadastro-feliz-sem-docker.sock
CS_RUN="$WORK/tests/infra/run.sh"

# cs_refused <mensagem> <args...>: run.sh sai com 1 e a mensagem, com o Docker inacessível,
# sem criar container, rede ou volume.
cs_refused() {
  local expected="$1" out rc; shift
  out="$(env DOCKER_HOST="$CS_NO_DOCKER" bash "$CS_RUN" "$@" 2>&1)"
  rc=$?
  [ "$rc" = 1 ] && [ "$out" = "$expected" ] || { note "$*: rc=$rc saída: $out"; return 1; }
  any_containers && { note "$*: containers criados"; return 1; }
  network_exists && { note "$*: rede criada"; return 1; }
  [ -z "$(docker volume ls -q --filter name=^cadastro-feliz-)" ] || { note "$*: volume criado"; return 1; }
  return 0
}

t_cs1_list() {
  local out expected
  expected="$(printf '%s\n' docs shared limiter migrate stack frontend test-frontend laravel \
    registration:laravel outbox:laravel laravel-outbox)"
  out="$(env DOCKER_HOST="$CS_NO_DOCKER" bash "$CS_RUN" --list 2>&1)" || { note "saiu com erro: $out"; return 1; }
  [ "$out" = "$expected" ] || { note "lista: $(tr '\n' ' ' <<< "$out")"; return 1; }
}
check "CS1 list prints every entry" t_cs1_list

t_cs2_second_adapter() {
  local out ok=0
  cp "$WORK/tests/infra/adapters/laravel.sh" "$WORK/tests/infra/adapters/nest.sh"
  out="$(env DOCKER_HOST="$CS_NO_DOCKER" bash "$CS_RUN" --list 2>&1 | grep -E '^(registration|outbox):')"
  [ "$out" = "$(printf '%s\n' registration:laravel registration:nest outbox:laravel outbox:nest)" ] \
    || { note "entradas de contrato: $(tr '\n' ' ' <<< "$out")"; ok=1; }
  cmp -s "$CS_RUN" "$REPO/tests/infra/run.sh" || { note "run.sh da cópia mudou"; ok=1; }
  rm -f "$WORK/tests/infra/adapters/nest.sh"
  return $ok
}
check "CS2 a second adapter adds its entries" t_cs2_second_adapter

t_cs5_no_adapter() {
  local ok=0 out
  cs_refused 'stack go sem adaptador em tests/infra/adapters' registration:go || ok=1
  out="$(env STACK=nest DOCKER_HOST="$CS_NO_DOCKER" bash "$CS_RUN" outbox 2>&1)"
  [ "$?" = 1 ] && [ "$out" = 'stack nest sem adaptador em tests/infra/adapters' ] || { note "STACK=nest outbox: $out"; ok=1; }
  cs_refused 'stack rails sem adaptador em tests/infra/adapters' registration:rails || ok=1
  # Só o nome exato do adaptador: o disco do macOS ignora maiúsculas, e um caminho acharia o arquivo.
  cs_refused 'stack Laravel sem adaptador em tests/infra/adapters' registration:Laravel || ok=1
  cs_refused 'stack ../adapters/laravel sem adaptador em tests/infra/adapters' registration:../adapters/laravel || ok=1
  out="$(env STACK=Laravel DOCKER_HOST="$CS_NO_DOCKER" bash "$CS_RUN" registration 2>&1)"
  [ "$?" = 1 ] && [ "$out" = 'stack Laravel sem adaptador em tests/infra/adapters' ] || { note "STACK=Laravel registration: $out"; ok=1; }
  # STACK só vale para arquivo de contrato: docs passa da resolução e para no Docker.
  out="$(env STACK=nest DOCKER_HOST="$CS_NO_DOCKER" bash "$CS_RUN" docs 2>&1)"
  grep -qF 'O Docker não está acessível' <<< "$out" || { note "STACK=nest docs: $out"; ok=1; }
  return $ok
}
check "CS5 stack without adapter is refused before docker" t_cs5_no_adapter

t_cs6_common_suffix() {
  local ok=0
  cs_refused 'docs não é um arquivo de contrato' docs:laravel || ok=1
  cs_refused 'laravel-outbox não é um arquivo de contrato' laravel-outbox:laravel || ok=1
  cs_refused 'arquivo de teste desconhecido: rails' rails:laravel || ok=1
  return $ok
}
check "CS6 suffix on a common file is refused" t_cs6_common_suffix

t_cs7_adapter_functions() {
  local ok=0 fn missing fake="$WORK/tests/infra/adapters/fake.sh"
  local functions=(stack_reset_queue stack_worker_stop stack_worker_start stack_relay_stop stack_relay_start
    stack_queue_stop stack_queue_start stack_queue_freeze stack_queue_unfreeze stack_queue_up_alone
    stack_queue_length stack_queued_messages stack_queue_connections stack_jobs_created stack_failed_jobs
    stack_dispatch stack_api_errors_since stack_worker_logs_since stack_relay_container stack_lua_dir
    stack_post_from_other_ip stack_wait_ready)
  [ "${#functions[@]}" = 22 ] || { note "lista com ${#functions[@]} funções"; return 1; }
  missing="$(
    # shellcheck source=/dev/null
    source "$WORK/tests/infra/adapters/laravel.sh"
    for fn in "${functions[@]}"; do declare -F "$fn" >/dev/null || echo "$fn"; done
  )"
  [ -z "$missing" ] || { note "adaptador laravel sem: $missing"; ok=1; }
  # O mesmo adaptador sem uma função de cada vez, nas 22.
  for fn in "${functions[@]}"; do
    awk -v fn="$fn" '$0 ~ "^"fn"\\(\\) \\{" {skip=1} skip && /\}/ {skip=0; next} !skip' \
      "$WORK/tests/infra/adapters/laravel.sh" > "$fake"
    if grep -qE "^$fn\(\)" "$fake"; then note "o adaptador falso ainda define $fn"; ok=1; continue; fi
    cs_refused "adaptador fake sem $fn" registration:fake || ok=1
  done
  rm -f "$fake"
  return $ok
}
check "CS7 adapter missing a function is refused" t_cs7_adapter_functions

t_cs8_contract_words() {
  local hits files=(registration.sh outbox.sh registration-helpers.sh)
  hits="$(cd "$WORK/tests/infra" && grep -n -i -E 'laravel|horizon|scheduler|php|artisan|nginx|queues:' "${files[@]}")"
  [ -z "$hits" ] || { note "nomes de stack: $hits"; return 1; }
  # Nem os containers do adaptador da Laravel.
  hits="$(cd "$WORK/tests/infra" && grep -n -E 'RG_(NG|FPM|HZ|RD|SC)([^A-Z_]|$)' "${files[@]}")"
  [ -z "$hits" ] || { note "containers do adaptador: $hits"; return 1; }
}
check "CS8 contract files name no stack" t_cs8_contract_words

# Os ids de cada arquivo, pelas linhas check "<id> ...".
cs_ids() { sed -nE 's/^check "([A-Z]+[0-9]+[A-Z]?) .*/\1/p' "$WORK/tests/infra/$1.sh" | LC_ALL=C sort | tr '\n' ' '; }
cs_sorted() { printf '%s\n' "$@" | LC_ALL=C sort | tr '\n' ' '; }

t_cs9_partition() {
  local ok=0 expected
  expected="$(cs_sorted RG0 RG1 RG2 RG3 RG4 RG5 RG6 RG7 RG8 RG9 RG10 RG11 RG12 RG13 RG14 RG15 RG16 RG17 RG18 \
    RG19 RG20 RG21 RG23 RG25 RG26 RG29 RG30 RG31 RG32 RG33)"
  [ "$(cs_ids registration)" = "$expected" ] || { note "registration: $(cs_ids registration)"; ok=1; }
  expected="$(cs_sorted LM0 LM1 LM2 LM2B LM3 OB1 OB2 OB4 OB5 OB6 OB15 OB16 OB17 OB18 OB22 OB23 OB24 OB25 \
    OB27 OB28 OB29 OB31 OB32 OB33 OB36 OB37 OB38)"
  [ "$(cs_ids outbox)" = "$expected" ] || { note "outbox: $(cs_ids outbox)"; ok=1; }
  expected="$(cs_sorted LO0 RG22 RG24 RG27 RG28 OB9 OB11 OB13 OB14 OB19 OB20 OB21 OB26 OB39 OB40 OB41)"
  [ "$(cs_ids laravel-outbox)" = "$expected" ] || { note "laravel-outbox: $(cs_ids laravel-outbox)"; ok=1; }
  return $ok
}
check "CS9 contract and internal ids are partitioned" t_cs9_partition

# Um caso de contrato que para ou congela algo nunca retorna antes de religar: o caso seguinte
# precisa da stack inteira. Lê cada t_<caso>() em ordem, linha a linha.
t_cs13_cases_restore() {
  local hits
  hits="$(cd "$WORK/tests/infra" && awk '
    function pending(  k, s) { s = ""; for (k in pend) if (pend[k]) s = s " " k; return s }
    /^t_[a-z0-9_]+\(\) \{/ { fn = $1; sub(/\(\).*/, "", fn); infn = 1; split("", pend); next }
    infn && /^\}/ { if (pending() != "") print FILENAME ": " fn " termina com" pending() " parado"; infn = 0; next }
    !infn { next }
    {
      line = $0
      if (line ~ /stack_queue_start/) pend["fila"] = 0
      if (line ~ /stack_queue_unfreeze/) pend["fila congelada"] = 0
      if (line ~ /stack_worker_start|ob_start_workers/) pend["worker"] = 0
      if (line ~ /stack_relay_start|ob_start_workers/) pend["relay"] = 0
      if (line ~ /mkq "up-|rg_set_env|rg_default_env/) { pend["fila"] = 0; pend["fila congelada"] = 0; pend["worker"] = 0; pend["relay"] = 0 }
      while (match(line, /docker (start|unpause) [^>|;]*/)) {
        args = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
        for (k in pend) if (index(args, k)) pend[k] = 0
      }
      line = $0
      if (line ~ /return ([0-9]|\$ok)|return *(;|$|\})/ && pending() != "") print FILENAME ":" FNR ": " fn " retorna com" pending() " parado"
      if (line ~ /stack_queue_stop/) pend["fila"] = 1
      if (line ~ /stack_queue_freeze/) pend["fila congelada"] = 1
      if (line ~ /stack_worker_stop/) pend["worker"] = 1
      if (line ~ /stack_relay_stop/) pend["relay"] = 1
      while (match(line, /docker (stop|pause) "[^"]*"/)) {
        t = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
        sub(/docker (stop|pause) /, "", t); pend[t] = 1
      }
    }' registration.sh outbox.sh)"
  [ -z "$hits" ] || { note "$hits"; return 1; }
}
check "CS13 contract cases restart what they stop" t_cs13_cases_restore

# Troca cada arquivo de FILES por um substituto que só diz que rodou, e com qual stack.
cs_stub_files() {
  local name
  for name in docs shared limiter migrate stack frontend test-frontend laravel laravel-outbox; do
    printf 'echo "ran %s"\n' "$name" > "$WORK/tests/infra/$name.sh"
  done
  for name in registration outbox; do
    printf 'echo "ran %s $SUITE_STACK"\n' "$name" > "$WORK/tests/infra/$name.sh"
  done
}

# cs_run <args...>: roda run.sh com os substitutos e imprime só as linhas deles e os cabeçalhos.
cs_run() { bash "$CS_RUN" "$@" 2>/dev/null | grep -E '^(ran |== )'; }

t_cs3_all_entries() {
  local out expected
  cs_stub_files
  expected="$(printf '%s\n' 'ran docs' 'ran shared' 'ran limiter' 'ran migrate' 'ran stack' 'ran frontend' \
    'ran test-frontend' 'ran laravel' '== registration:laravel' 'ran registration laravel' \
    '== outbox:laravel' 'ran outbox laravel' 'ran laravel-outbox')"
  out="$(unset STACK; cs_run)"
  [ "$out" = "$expected" ] || { note "sem argumentos: $(tr '\n' '|' <<< "$out")"; return 1; }
}

t_cs4_default_stack() {
  local ok=0 out
  out="$(unset STACK; cs_run registration)"
  [ "$out" = "$(printf '%s\n' '== registration:laravel' 'ran registration laravel')" ] || { note "sem STACK: $out"; ok=1; }
  out="$(export STACK=laravel; cs_run outbox)"
  [ "$out" = "$(printf '%s\n' '== outbox:laravel' 'ran outbox laravel')" ] || { note "STACK=laravel: $out"; ok=1; }
  out="$(export STACK=; cs_run registration)"
  [ "$out" = "$(printf '%s\n' '== registration:laravel' 'ran registration laravel')" ] || { note "STACK vazio: $out"; ok=1; }
  return $ok
}

check "CS3 no arguments runs every entry in order" t_cs3_all_entries
check "CS4 contract file without suffix uses STACK or laravel" t_cs4_default_stack


t_c16_missing_stack() {
  local target stack out rc ok=0
  # A Laravel tem compose desde a base da API (.specs/features/laravel-api-base).
  for target in up down logs watch; do
    for stack in nest go; do
      out="$(timeout 20 make --no-print-directory -C "$WORK" "$target-$stack" 2>&1)"
      rc=$?
      if [ "$rc" -eq 0 ] || ! grep -qF "stack $stack ainda não implementada" <<< "$out"; then
        note "$target-$stack: rc=$rc saída: $out"; ok=1
      fi
    done
  done
  network_exists && { note "rede criada"; ok=1; }
  any_containers && { note "containers criados"; ok=1; }
  return $ok
}
check "C16 missing stack refused" t_c16_missing_stack

t_c17_unknown_stack() {
  local target out rc ok=0
  for target in up down logs; do
    out="$(timeout 20 make --no-print-directory -C "$WORK" "$target-rails" 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ] || ! grep -qF "stack rails desconhecida" <<< "$out"; then
      note "$target-rails: rc=$rc saída: $out"; ok=1
    fi
  done
  network_exists && { note "rede criada"; ok=1; }
  any_containers && { note "containers criados"; ok=1; }
  return $ok
}
check "C17 unknown stack refused" t_c17_unknown_stack

fake_stack go apis/golang
fake_stack nest apis/nestjs

t_c18_up_stack() {
  network_exists && return 1
  mk up-go >/dev/null 2>&1 || { note "make up-go saiu com erro"; return 1; }
  network_exists || { note "rede ausente"; return 1; }
  shared_healthy || return 1
  [ "$(health cadastro-feliz-go-api-1)" = healthy ] || { note "stack go não está healthy"; return 1; }
}
check "C18 up-stack runs shared and migrate first" t_c18_up_stack

t_c19_switch() {
  mk up-nest >/dev/null 2>&1 || { note "make up-nest saiu com erro"; return 1; }
  [ -z "$(project_containers cadastro-feliz-go)" ] || { note "go ficou no ar ao subir nest"; return 1; }
  [ "$(health cadastro-feliz-nest-api-1)" = healthy ] || return 1
  mk up-go >/dev/null 2>&1 || { note "make up-go saiu com erro"; return 1; }
  [ -z "$(project_containers cadastro-feliz-nest)" ] || { note "nest ficou no ar"; return 1; }
  [ "$(health cadastro-feliz-go-api-1)" = healthy ]
}
check "C19 up-stack takes other stacks down" t_c19_switch

t_c29_status_stack() {
  local out
  out="$(mk status 2>&1)" || return 1
  echo "$out" | grep -E 'cadastro-feliz-go-api-1.*running' >/dev/null || { note "status sem a stack go running"; return 1; }
  echo "$out" | grep -E "$(container postgres).*running" >/dev/null || { note "status sem postgres running"; return 1; }
}
check "C29 status lists stack containers" t_c29_status_stack

t_c21_down_stack() {
  psql_q "insert into users (name, email) values ('Ana Souza', 'ana@example.com')" >/dev/null || return 1
  redis_q SET registration:attempts:abc 1 EX 900 >/dev/null || return 1
  docker volume inspect cadastro-feliz-go_queue-data >/dev/null 2>&1 || { note "volume da stack ausente antes"; return 1; }
  mk down-go >/dev/null 2>&1 || { note "make down-go saiu com erro"; return 1; }
  [ -z "$(project_containers cadastro-feliz-go)" ] || { note "containers da stack restaram"; return 1; }
  docker volume inspect cadastro-feliz-go_queue-data >/dev/null 2>&1 && { note "volume da stack restou"; return 1; }
  shared_healthy || return 1
  [ "$(redis_q EXISTS registration:attempts:abc)" = 1 ] || { note "chave do limiter sumiu"; return 1; }
  [ "$(psql_q "select count(*) from users where email = 'ana@example.com'")" = 1 ] || { note "linha sumiu"; return 1; }
}
check "C21 down-stack keeps shared data" t_c21_down_stack

t_c22_down() {
  mk up-go >/dev/null 2>&1 || return 1
  redis_q SET registration:attempts:abc 1 EX 900 >/dev/null || return 1
  mk down >/dev/null 2>&1 || { note "make down saiu com erro"; return 1; }
  any_containers && { note "containers restaram"; return 1; }
  network_exists && { note "rede restou"; return 1; }
  docker volume inspect "$PG_VOLUME" >/dev/null 2>&1 || { note "volume do postgres sumiu"; return 1; }
  mk up-shared >/dev/null 2>&1 || return 1
  [ "$(psql_q "select count(*) from users where email = 'ana@example.com'")" = 1 ] || { note "linha sumiu"; return 1; }
  [ "$(redis_q EXISTS registration:attempts:abc)" = 0 ] || { note "chave do limiter sobreviveu"; return 1; }
}
check "C22 down keeps only postgres volume" t_c22_down

t_c20_failed_migrate() {
  cat > "$WORK/database/migrations/0002_probe.up.sql" <<'SQL'
BEGIN;

SELECT * FROM table_that_does_not_exist;

COMMIT;
SQL
  echo 'SELECT 1;' > "$WORK/database/migrations/0002_probe.down.sql"
  local rc
  mk up-go >/dev/null 2>&1
  rc=$?
  rm -f "$WORK"/database/migrations/0002_probe.*
  [ "$rc" -ne 0 ] || { note "make up-go saiu com 0"; return 1; }
  [ -z "$(project_containers cadastro-feliz-go)" ] || { note "containers da stack existem"; return 1; }
}
check "C20 up-stack stops when migrate fails" t_c20_failed_migrate
