# make test-frontend (.specs/features/registration-form) - S2. Carregado por run.sh.

RF=cadastro-feliz-shared-frontend-1
RF_OUT="$WORK/test-frontend.log"
RF_PROBE_TEST="$WORK/frontend/src/probe.test.ts"
RF_PROBE_TYPE="$WORK/frontend/src/probe-type.ts"

# Roda make test-frontend guardando a saída; devolve o código de saída do make.
rf_run() { mk test-frontend > "$RF_OUT" 2>&1; }
rf_out_has() { grep -qF -- "$1" "$RF_OUT"; }
rf_id() { docker ps -aq --no-trunc --filter "name=^$RF\$"; }
rf_state() { docker inspect -f '{{.State.Status}}' "$RF" 2>/dev/null; }
rf_status() { curl -s -o /dev/null --max-time 60 -w '%{http_code}' localhost:3000/; }

write_failing_test() {
  cat > "$RF_PROBE_TEST" <<'TS'
import { expect, it } from "vitest";

it("probe fails on purpose", () => {
  expect(1).toBe(2);
});
TS
}

# --- sem Docker ---

t_rf23_exact() {
  local f="$WORK/frontend/package.json" dep version ok=0
  for dep in vitest @vitejs/plugin-react jsdom @testing-library/react @testing-library/dom @testing-library/user-event; do
    version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("devDependencies", {}).get(sys.argv[2], ""))' "$f" "$dep")"
    [ -n "$version" ] || { note "$dep fora de devDependencies"; ok=1; continue; }
    case "$version" in
      '^'*|'~'*) note "$dep com faixa $version"; ok=1 ;;
    esac
  done
  return $ok
}
check "RF23 test dependencies are exact" t_rf23_exact

t_rf24_help() {
  mk help | grep -qF 'make test-frontend' || { note "make help sem make test-frontend"; return 1; }
}
check "RF24 help lists test-frontend" t_rf24_help

# --- com Docker ---

t_rf18_clean_clone() {
  destroy_environment
  rm -f "$WORK/.env"
  rf_run || { note "make test-frontend saiu com erro"; tail -20 "$RF_OUT" >&2; return 1; }
  rf_out_has 'Test Files' || { note "o Vitest não rodou"; return 1; }
  grep -E 'Test Files .* passed' "$RF_OUT" | grep -qv failed || { note "o Vitest não passou"; return 1; }
  [ ! -e "$WORK/frontend/node_modules" ] || { note "frontend/node_modules apareceu na máquina"; return 1; }
}
check "RF18 test-frontend passes on a clean clone" t_rf18_clean_clone

t_rf28_leaves_nothing() {
  destroy_environment
  rf_run || { note "make test-frontend saiu com erro"; return 1; }
  any_containers && { note "sobrou container cadastro-feliz-*"; return 1; }
  network_exists && { note "sobrou a rede $NETWORK"; return 1; }
  [ -z "$(docker volume ls -q --filter name=^cadastro-feliz-)" ] || { note "sobrou volume cadastro-feliz-*"; return 1; }
}
check "RF28 test-frontend leaves no environment behind" t_rf28_leaves_nothing

t_rf22_current_code() {
  rf_run || { note "make test-frontend não estava verde antes"; return 1; }
  write_failing_test
  local ok=0
  rf_run && { note "um teste novo que falha não fez o alvo falhar"; ok=1; }
  rm -f "$RF_PROBE_TEST"
  return $ok
}
check "RF22 test-frontend uses the current code" t_rf22_current_code

t_rf19_failing_test() {
  write_failing_test
  local ok=0
  rf_run && { note "make test-frontend saiu com 0"; ok=1; }
  rf_out_has 'probe fails on purpose' || { note "a saída não mostra o teste que falhou"; ok=1; }
  rm -f "$RF_PROBE_TEST"
  return $ok
}
check "RF19 test-frontend fails on a failing test" t_rf19_failing_test

t_rf20_type_error() {
  printf 'const value: number = "texto";\nexport default value;\n' > "$RF_PROBE_TYPE"
  local ok=0
  rf_run && { note "make test-frontend saiu com 0"; ok=1; }
  rf_out_has 'error TS' || { note "a saída não mostra error TS"; ok=1; }
  rf_out_has 'Test Files' && { note "o Vitest rodou mesmo com erro de tipo"; ok=1; }
  rm -f "$RF_PROBE_TYPE"
  return $ok
}
check "RF20 test-frontend stops on a type error" t_rf20_type_error

t_rf21_keeps_frontend() {
  mkq up-shared || { note "make up-shared saiu com erro"; return 1; }
  local before
  before="$(rf_id)"
  [ -n "$before" ] || { note "frontend não está no ar"; return 1; }
  rf_run || { note "make test-frontend saiu com erro"; return 1; }
  [ "$(rf_id)" = "$before" ] || { note "o container do frontend mudou de ID"; return 1; }
  [ "$(rf_state)" = running ] || { note "frontend em $(rf_state)"; return 1; }
  [ "$(rf_status)" = 200 ] || { note "GET / respondeu $(rf_status)"; return 1; }
}
check "RF21 test-frontend leaves frontend running" t_rf21_keeps_frontend
