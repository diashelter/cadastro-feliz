# S3 - Troca de stack pelo Makefile. Carregado por run.sh.


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
