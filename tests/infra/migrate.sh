# S2 - Schema aplicado pelo migrate. Carregado por run.sh.

DB_URL="postgres://cadastro_feliz:cadastro_feliz@postgres:5432/cadastro_feliz?sslmode=disable"
migrate_cli() {
  (cd "$WORK" && docker compose --profile tools run --rm -T migrate -path=/migrations -database="$DB_URL" "$@")
}
# Fixa a chave de \restrict, que o pg_dump sorteia a cada execução.
schema_dump() { docker exec "$(container postgres)" pg_dump -U cadastro_feliz -d cadastro_feliz --schema-only --restrict-key=schemadump; }
version_row() { psql_q "select version || ' ' || case when dirty then 't' else 'f' end from schema_migrations"; }
table_exists() { [ "$(psql_q "select to_regclass('public.$1') is not null")" = t ]; }

t_c10_migration_file() {
  local up="$WORK/database/migrations/0001_create_users_and_users_outbox.up.sql"
  local schema body
  schema="$(awk '/^## Schema/{on=1} on && /^```sql$/{grab=1; next} grab && /^```$/{exit} grab' "$WORK/docs/database.md")"
  [ -n "$schema" ] || { note "bloco SQL não encontrado em docs/database.md"; return 1; }
  [ "$(grep -v '^$' "$up" | head -1)" = "BEGIN;" ] || { note "não começa com BEGIN;"; return 1; }
  [ "$(grep -v '^$' "$up" | tail -1)" = "COMMIT;" ] || { note "não termina com COMMIT;"; return 1; }
  # Entre BEGIN; e COMMIT;, ignorando só as linhas em branco das bordas.
  body="$(awk 'f && /^COMMIT;$/{exit} f; /^BEGIN;$/{f=1}' "$up" | awk 'NF{p=1} p' | tac | awk 'NF{p=1} p' | tac)"
  [ "$body" = "$schema" ] \
    || { note "corpo da 0001 difere do schema da documentação"; return 1; }
}
check "C10 migration 0001 equals docs schema" t_c10_migration_file

t_c11_empty_database() {
  mk migrate >/dev/null 2>&1 || { note "make migrate saiu com erro"; return 1; }
  local c
  for c in users_email_unique users_email_lowercase users_outbox_status_valid users_outbox_attempts_positive; do
    [ "$(psql_q "select count(*) from pg_constraint where conname = '$c'")" = 1 ] || { note "falta constraint $c"; return 1; }
  done
  [ "$(psql_q "select count(*) from pg_constraint where contype = 'f'
      and conrelid = 'users_outbox'::regclass and confrelid = 'users'::regclass
      and conkey = array[(select attnum from pg_attribute where attrelid = 'users_outbox'::regclass and attname = 'user_id')]::smallint[]")" = 1 ] \
    || { note "falta FK users_outbox.user_id -> users.id"; return 1; }
  for c in users_outbox_user_id_index users_outbox_pending_index users_outbox_published_index; do
    [ "$(psql_q "select count(*) from pg_indexes where indexname = '$c'")" = 1 ] || { note "falta índice $c"; return 1; }
  done
  [ "$(version_row)" = "1 f" ] || { note "schema_migrations: $(version_row)"; return 1; }
}
check "C11 migrate on empty database" t_c11_empty_database

t_c12_rerun() {
  local before after
  before="$(schema_dump)" || return 1
  mk migrate >/dev/null 2>&1 || return 1
  after="$(schema_dump)" || return 1
  [ "$(version_row)" = "1 f" ] || return 1
  [ "$before" = "$after" ]
}
check "C12 migrate rerun changes nothing" t_c12_rerun

t_c13_starts_shared() {
  mkq down || return 1
  any_containers && { note "containers restaram depois de make down"; return 1; }
  mk migrate >/dev/null 2>&1 || { note "make migrate saiu com erro"; return 1; }
  shared_healthy || return 1
  [ "$(version_row)" = "1 f" ]
}
check "C13 migrate starts shared services" t_c13_starts_shared

t_c15_down() {
  migrate_cli down 1 >/dev/null 2>&1 || { note "migrate down 1 falhou"; return 1; }
  local ok=0
  table_exists users_outbox && ok=1
  table_exists users && ok=1
  mkq migrate || ok=1
  return $ok
}
check "C15 migration 0001 down drops both tables" t_c15_down

t_c14_failed_migration() {
  cat > "$WORK/database/migrations/0002_probe.up.sql" <<'SQL'
BEGIN;

CREATE TABLE probe (id integer);

SELECT * FROM table_that_does_not_exist;

COMMIT;
SQL
  echo 'DROP TABLE IF EXISTS probe;' > "$WORK/database/migrations/0002_probe.down.sql"
  local rc
  mk migrate >/dev/null 2>&1
  rc=$?
  rm -f "$WORK"/database/migrations/0002_probe.*
  [ "$rc" -ne 0 ] || { note "make migrate saiu com 0"; return 1; }
  table_exists probe && { note "probe ficou no banco"; return 1; }
  [ "$(version_row)" = "2 t" ] || { note "schema_migrations: $(version_row)"; return 1; }
}
check "C14 failed migration rolls back and marks dirty" t_c14_failed_migration
