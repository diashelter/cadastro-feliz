# Troca entre as stacks Laravel e NestJS (cenário 6 de docs/architecture.md), nos dois sentidos:
# o evento deixado por uma stack sai pela outra. O contador de tentativas é de cada stack
# (decisão 28), então o limite não acompanha a troca. Precisa das duas stacks, então não é um arquivo de contrato, e age nelas pelo nome dos
# containers, sem carregar os adaptadores, cujas funções têm o mesmo nome. Plano e checks em
# .specs/features/nestjs-stack. Carregado por run.sh.

# shellcheck source=/dev/null
source "$TESTS/registration-helpers.sh"

SW_NEST_WORKER=cadastro-feliz-nest-worker-1
SW_HORIZON=cadastro-feliz-laravel-horizon-1

# Banco, contadores e caixa de e-mail vazios. As filas são descartadas a cada troca de stack.
sw_reset() {
  psql_q 'truncate users cascade' >/dev/null
  redis_q FLUSHALL >/dev/null
  curl -s -X DELETE --max-time 10 localhost:8025/api/v1/messages >/dev/null
  return 0
}

# sw_env <chave=valor>: troca um valor do .env da cópia de trabalho, sem subir nada.
sw_env() { sed "s|^${1%%=*}=.*|$1|" "$WORK/.env" > "$WORK/.env.new" && mv "$WORK/.env.new" "$WORK/.env"; }

# sw_exactly_one <e-mail>: uma mensagem chega em até 60 s e nenhuma outra nos 10 s seguintes.
sw_exactly_one() {
  local started=$SECONDS
  rg_wait_for 60 rg_mail_arrived "$1" || { note "o e-mail não chegou"; return 1; }
  [ $((SECONDS - started)) -le 60 ] || { note "levou $((SECONDS - started)) s"; return 1; }
  sleep 10
  [ "$(rg_mail_count "$1")" = 1 ] || { note "mensagens: $(rg_mail_count "$1")"; return 1; }
}

t_sw1_nest_to_laravel() {
  local ok=0
  mkq up-nest || { note "make up-nest saiu com erro"; return 1; }
  sw_reset
  docker stop "$SW_NEST_WORKER" >/dev/null
  [ "$(rg_register ana@example.com)" = 201 ] || { note "cadastro: $(rg_body)"; ok=1; }
  sleep 3
  rg_event_is pending ana@example.com || { note "evento na NestJS: $(rg_event status ana@example.com)"; ok=1; }
  mkq up-laravel || { note "make up-laravel saiu com erro"; return 1; }
  [ -z "$(project_containers cadastro-feliz-nest)" ] || { note "a NestJS ficou no ar"; ok=1; }
  sw_exactly_one ana@example.com || ok=1
  rg_event_is processed ana@example.com || { note "evento no fim: $(rg_event status ana@example.com)"; ok=1; }
  return $ok
}
check "SW1 nest pending event leaves through laravel" t_sw1_nest_to_laravel

t_sw2_laravel_to_nest() {
  local ok=0 id
  mkq up-laravel || { note "make up-laravel saiu com erro"; return 1; }
  sw_reset
  docker stop "$SW_HORIZON" >/dev/null
  [ "$(rg_register bia@example.com)" = 201 ] || { note "cadastro: $(rg_body)"; ok=1; }
  rg_wait_for 10 rg_event_is published bia@example.com || { note "evento na Laravel: $(rg_event status bia@example.com)"; ok=1; }
  sw_env OUTBOX_REPUBLISH_AFTER_SECONDS=5
  mkq up-nest || { note "make up-nest saiu com erro"; ok=1; }
  sw_exactly_one bia@example.com || ok=1
  id="$(rg_event id bia@example.com)"
  [ "$(rg_mail_field bia@example.com '.MessageID')" = "$id@cadastro-feliz.local" ] || { note "Message-ID: $(rg_mail_field bia@example.com '.MessageID')"; ok=1; }
  sw_env OUTBOX_REPUBLISH_AFTER_SECONDS=300
  return $ok
}
check "SW2 laravel published event leaves through nest" t_sw2_laravel_to_nest
