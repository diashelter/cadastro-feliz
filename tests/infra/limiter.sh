# Limite por IP (.specs/features/registration-ip-limit) - S1. Carregado por run.sh.
#
# Os scripts vêm de docs/api-contract.md › Limite por IP, que é o que as stacks
# copiam: testar uma cópia provaria outra coisa. Rodam por EVAL no redis-limiter.

CONTRACT="$WORK/docs/api-contract.md"
SCRIPTS="$WORK/ip-scripts"

# Texto de uma seção "## <título>" até a próxima "## ".
ip_section() { awk '/^## Limite por IP$/{on=1; next} on && /^## /{exit} on' "$CONTRACT"; }

# Grava os blocos lua da seção em $SCRIPTS/1.lua (reserva) e $SCRIPTS/2.lua (devolução).
extract_scripts() {
  rm -rf "$SCRIPTS"; mkdir -p "$SCRIPTS"
  ip_section | awk -v dir="$SCRIPTS" '
    /^```lua$/ { n++; on=1; next }
    on && /^```$/ { on=0; next }
    on { print > (dir "/" n ".lua") }'
  local count
  count="$(find "$SCRIPTS" -name '*.lua' | wc -l)"
  [ "$count" -eq 2 ] || { note "› Limite por IP tem $count blocos lua, esperado 2"; return 1; }
}

KEY=registration:ip:test
reserve() { redis_q EVAL "$(cat "$SCRIPTS/1.lua")" 1 "${1:-$KEY}" 20 3600; }
release() { redis_q EVAL "$(cat "$SCRIPTS/2.lua")" 1 "${1:-$KEY}"; }
ttl_in_window() {
  local ttl
  ttl="$(redis_q TTL "${1:-$KEY}")"
  [ "$ttl" -ge 1 ] && [ "$ttl" -le 3600 ] || { note "TTL $ttl fora de [1, 3600]"; return 1; }
}

limiter_ready=0
if mkq migrate && extract_scripts; then limiter_ready=1; else note "redis-limiter ou scripts indisponíveis"; fi

t_ip5_reserve_limit() {
  [ "$limiter_ready" -eq 1 ] || return 1
  redis_q DEL "$KEY" >/dev/null
  local i out
  for i in $(seq 1 20); do
    mapfile -t out < <(reserve)
    [ "${out[0]}" = 1 ] || { note "reserva $i retornou ${out[0]}"; return 1; }
    [ "${out[1]}" -ge 1 ] && [ "${out[1]}" -le 3600 ] || { note "reserva $i com TTL ${out[1]}"; return 1; }
  done
  mapfile -t out < <(reserve)
  [ "${out[0]}" = 0 ] || { note "21ª reserva retornou ${out[0]}"; return 1; }
  [ "${out[1]}" -ge 1 ] && [ "${out[1]}" -le 3600 ] || { note "21ª reserva com TTL ${out[1]}"; return 1; }
  [ "$(redis_q GET "$KEY")" = 20 ] || { note "valor $(redis_q GET "$KEY"), esperado 20"; return 1; }

  # A cota vem de ARGV[1]: com 3, aceita 3 e recusa a 4ª.
  redis_q DEL "$KEY" >/dev/null
  for i in 1 2 3; do
    mapfile -t out < <(redis_q EVAL "$(cat "$SCRIPTS/1.lua")" 1 "$KEY" 3 60)
    [ "${out[0]}" = 1 ] || { note "cota 3: reserva $i retornou ${out[0]}"; return 1; }
  done
  mapfile -t out < <(redis_q EVAL "$(cat "$SCRIPTS/1.lua")" 1 "$KEY" 3 60)
  [ "${out[0]}" = 0 ] || { note "cota 3: 4ª reserva retornou ${out[0]}"; return 1; }
  [ "$(redis_q GET "$KEY")" = 3 ] || { note "cota 3: valor $(redis_q GET "$KEY")"; return 1; }

  # Janela fixa: reservas depois da primeira não renovam a expiração.
  redis_q DEL "$KEY" >/dev/null
  reserve >/dev/null
  redis_q EXPIRE "$KEY" 1000 >/dev/null
  for i in 1 2 3; do reserve >/dev/null; done
  local ttl
  ttl="$(redis_q TTL "$KEY")"
  [ "$ttl" -ge 990 ] && [ "$ttl" -le 1000 ] || { note "reservas renovaram a janela: TTL $ttl"; return 1; }

  # No último meio segundo o TTL do Redis é 0; os segundos retornados valem pelo menos 1.
  redis_q SET "$KEY" 20 PX 300 >/dev/null
  mapfile -t out < <(reserve)
  [ "${out[0]}" = 0 ] && [ "${out[1]}" -ge 1 ] || { note "fim da janela, recusa: ${out[*]}"; return 1; }
  redis_q SET "$KEY" 5 PX 300 >/dev/null
  mapfile -t out < <(reserve)
  [ "${out[0]}" = 1 ] && [ "${out[1]}" -ge 1 ] || { note "fim da janela, aceite: ${out[*]}"; return 1; }
}
check "IP5 reserve accepts 20 and refuses the 21st" t_ip5_reserve_limit

t_ip6_parallel() {
  [ "$limiter_ready" -eq 1 ] || return 1
  redis_q DEL "$KEY" >/dev/null
  local out="$WORK/parallel" i
  rm -rf "$out"; mkdir -p "$out"
  for i in $(seq 1 50); do
    reserve > "$out/$i" 2>&1 &
  done
  wait
  local accepted
  accepted="$(for i in $(seq 1 50); do head -n1 "$out/$i"; done | grep -cx 1)"
  [ "$accepted" -eq 20 ] || { note "$accepted reservas aceitas, esperado 20"; return 1; }
  [ "$(redis_q GET "$KEY")" = 20 ] || { note "valor $(redis_q GET "$KEY"), esperado 20"; return 1; }
}
check "IP6 parallel reserves accept exactly 20" t_ip6_parallel

t_ip7_release() {
  [ "$limiter_ready" -eq 1 ] || return 1
  redis_q DEL "$KEY" >/dev/null
  local i
  for i in $(seq 1 20); do reserve >/dev/null; done
  # Um TTL arbitrário distingue a expiração mantida de uma renovada para 3600.
  redis_q EXPIRE "$KEY" 1000 >/dev/null
  release >/dev/null
  [ "$(redis_q GET "$KEY")" = 19 ] || { note "valor $(redis_q GET "$KEY"), esperado 19"; return 1; }
  local ttl
  ttl="$(redis_q TTL "$KEY")"
  [ "$ttl" -ge 990 ] && [ "$ttl" -le 1000 ] || { note "devolução mudou o TTL para $ttl"; return 1; }
}
check "IP7 release decrements and keeps ttl" t_ip7_release

t_ip8_release_absent() {
  [ "$limiter_ready" -eq 1 ] || return 1
  local never=registration:ip:never
  redis_q DEL "$never" >/dev/null
  release "$never" >/dev/null
  [ "$(redis_q EXISTS "$never")" = 0 ] || { note "devolução criou a chave nunca usada"; return 1; }
  # Reserva com janela de 1 s; depois que ela expira, a devolução não recria a chave.
  local expired=registration:ip:expired
  redis_q DEL "$expired" >/dev/null
  redis_q EVAL "$(cat "$SCRIPTS/1.lua")" 1 "$expired" 20 1 >/dev/null
  local i
  for i in $(seq 1 30); do
    [ "$(redis_q EXISTS "$expired")" = 0 ] && break
    sleep 0.2
  done
  [ "$(redis_q EXISTS "$expired")" = 0 ] || { note "a chave de janela de 1 s não expirou"; return 1; }
  release "$expired" >/dev/null
  [ "$(redis_q EXISTS "$expired")" = 0 ] || { note "devolução recriou a chave expirada"; return 1; }
}
check "IP8 release never creates the key" t_ip8_release_absent

t_ip9_release_zero() {
  [ "$limiter_ready" -eq 1 ] || return 1
  redis_q DEL "$KEY" >/dev/null
  reserve >/dev/null
  release >/dev/null
  [ "$(redis_q GET "$KEY")" = 0 ] || { note "valor $(redis_q GET "$KEY"), esperado 0"; return 1; }
  release >/dev/null
  [ "$(redis_q GET "$KEY")" = 0 ] || { note "devolução em 0 deixou $(redis_q GET "$KEY")"; return 1; }
}
check "IP9 release never goes negative" t_ip9_release_zero

t_ip10_refused_ttl() {
  [ "$limiter_ready" -eq 1 ] || return 1
  redis_q DEL "$KEY" >/dev/null
  local i out
  for i in $(seq 1 20); do reserve >/dev/null; done
  # Encurta a janela para distinguir o TTL da chave de um valor fixo como 3600.
  redis_q EXPIRE "$KEY" 1234 >/dev/null
  mapfile -t out < <(reserve)
  [ "${out[0]}" = 0 ] || { note "reserva acima da cota retornou ${out[0]}"; return 1; }
  [ "${out[1]}" -ge 1230 ] && [ "${out[1]}" -le 1234 ] \
    || { note "TTL retornado ${out[1]}, esperado o da chave, entre 1230 e 1234"; return 1; }
  ip_section | grep -F '**Decisão:**' | grep -F 'segundos restantes' | grep -qF 'Retry-After' \
    || { note "a Decisão do script não usa os segundos restantes no Retry-After"; return 1; }
}
check "IP10 refused reserve returns key ttl" t_ip10_refused_ttl

t_ip11_always_ttl() {
  [ "$limiter_ready" -eq 1 ] || return 1
  redis_q DEL "$KEY" >/dev/null
  reserve >/dev/null
  redis_q EXPIRE "$KEY" 1000 >/dev/null
  release >/dev/null; reserve >/dev/null
  ttl_in_window || { note "depois de reserva, devolução, reserva"; return 1; }
  # Com o uso em 0, a reserva seguinte recomeça a janela.
  [ "$(redis_q TTL "$KEY")" -ge 3590 ] || { note "a janela não recomeçou: TTL $(redis_q TTL "$KEY")"; return 1; }
  redis_q DEL "$KEY" >/dev/null
  local i
  for i in $(seq 1 20); do reserve >/dev/null; done
  for i in $(seq 1 20); do release >/dev/null; done
  reserve >/dev/null
  ttl_in_window || { note "depois de 20 reservas, 20 devoluções e 1 reserva"; return 1; }
}
check "IP11 key always has a ttl" t_ip11_always_ttl
