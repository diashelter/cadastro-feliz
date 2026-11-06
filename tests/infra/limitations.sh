# As limitações do fluxo sem outbox (decisão 21 de docs/decisions.md). Estes testes afirmam
# o que acontece hoje, inclusive a perda do e-mail, e passam enquanto ela existir. A rodada
# do outbox os inverte, e essa inversão é a prova da correção. Carregado por run.sh.

# shellcheck source=/dev/null
source "$TESTS/registration-helpers.sh"

# rg_lost <e-mail>: o usuário existe e, passada a janela, nenhuma mensagem saiu para ele.
rg_lost() {
  local ok=0
  sleep 30
  rg_user_exists "$1" || { note "usuário não está em users"; ok=1; }
  [ "$(rg_mail_count "$1")" = 0 ] || { note "o e-mail chegou: $(rg_mail_count "$1")"; ok=1; }
  return $ok
}

t_lm0_up() {
  mkq up-laravel || { note "make up-laravel saiu com erro"; return 1; }
}
check "LM0 stack up for the limitation tests" t_lm0_up

t_lm1_queue_down() {
  local ok=0
  rg_reset
  docker stop "$RG_RD" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  docker start "$RG_RD" >/dev/null
  rg_wait_for 60 rg_healthy "$RG_RD"
  rg_wait_for 90 rg_healthy "$RG_HZ" || { note "horizon: $(health "$RG_HZ")"; ok=1; }
  rg_lost ana@example.com || ok=1
  [ "$(rg_register ana@example.com)" = 409 ] || { note "repetir: $(rg_body)"; ok=1; }
  sleep 5
  [ "$(rg_mail_count ana@example.com)" = 0 ] || { note "repetir gerou e-mail"; ok=1; }
  return $ok
}
check "LM1 queue down loses the mail" t_lm1_queue_down

t_lm2_stack_down() {
  local ok=0
  rg_reset
  docker stop "$RG_HZ" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  [ "$(docker exec "$RG_RD" redis-cli LLEN queues:registration-emails)" = 1 ] || { note "o job não estava na fila"; ok=1; }
  mkq down-laravel || { note "make down-laravel saiu com erro"; ok=1; }
  mkq up-laravel || { note "make up-laravel saiu com erro"; ok=1; }
  rg_wait_for 90 rg_healthy "$RG_HZ" || { note "horizon: $(health "$RG_HZ")"; ok=1; }
  rg_lost ana@example.com || ok=1
  return $ok
}
check "LM2 stack down loses the queued job" t_lm2_stack_down

t_lm3_retries_exhausted() {
  local ok=0 tables
  rg_set_env OUTBOX_MAX_ATTEMPTS=2 OUTBOX_BACKOFF_BASE_SECONDS=1 || { note "make up-laravel saiu com erro"; return 1; }
  rg_reset
  docker stop "$(container mailpit)" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "status: $(rg_body)"; ok=1; }
  lm_failed() { [ "$(curl -s --max-time 10 localhost:8080/horizon/api/jobs/failed | jq -r '.jobs | length')" -ge 1 ]; }
  rg_wait_for 60 lm_failed || { note "o job não falhou: $(curl -s localhost:8080/horizon/api/jobs/failed | head -c 300)"; ok=1; }
  curl -s --max-time 10 localhost:8080/horizon/api/jobs/failed | jq -r '.jobs[0].name' | grep -qF SendWelcomeEmailJob \
    || { note "falha sem SendWelcomeEmailJob"; ok=1; }
  docker start "$(container mailpit)" >/dev/null
  rg_shared_back
  rg_lost ana@example.com || ok=1
  # A falha só existe no Horizon: o PostgreSQL não guarda nada dela.
  tables="$(psql_q "select tablename from pg_tables where schemaname = 'public' order by 1" | tr '\n' ' ')"
  [ "$tables" = 'schema_migrations users users_outbox ' ] || { note "tabelas: $tables"; ok=1; }
  [ "$(psql_q 'select count(*) from users_outbox')" = 0 ] || { note "users_outbox tem linhas"; ok=1; }
  rg_default_env
  return $ok
}
check "LM3 exhausted retries lose the mail" t_lm3_retries_exhausted
