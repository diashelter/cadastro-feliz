# S4 - Documentação alinhada. Carregado por run.sh; não usa o Docker.

# Texto de uma seção "## <título>" até a próxima "## ".
section() { awk -v h="$2" '$0 ~ "^## "h {on=1; next} on && /^## /{exit} on' "$1"; }

t_c26_decision() {
  local f="$WORK/docs/decisions.md" body
  grep -qE '^\| \[15\]\(#15-[^)]*\) \| golang-migrate como ferramenta de migrations \| Proposta \|$' "$f" \
    || { note "índice sem a decisão 15 Proposta"; return 1; }
  body="$(section "$f" '15\. golang-migrate como ferramenta de migrations$')"
  [ -n "$body" ] || { note "seção 15 ausente"; return 1; }
  local term
  for term in 'NNNN_<nome>.up.sql' 'BEGIN;' 'COMMIT;' 'dirty' 'force'; do
    grep -qF "$term" <<< "$body" || { note "decisão 15 sem '$term'"; return 1; }
  done
}
check "C26 decision 15 recorded" t_c26_decision

t_c27_existing_files() {
  local f ok=0 hits
  for f in "$WORK/README.md" "$WORK/docs/infrastructure.md"; do
    # Uma frase por linha; acusa a frase que cita um dos arquivos e diz que ele
    # não existe, que não há, ou que é planejado.
    hits="$(tr '\n' ' ' < "$f" | sed -E 's/([.!?]) +/\1\n/g; s/#/\n/g' \
      | grep -E '(Makefile|docker-compose\.yml|\.env\.example|arquivos Compose|arquivos Docker)' \
      | grep -E '(não existe\b|não existem\b|não há|planejad)')"
    if [ -n "$hits" ]; then
      note "$(basename "$f") ainda diz que o arquivo não existe: $hits"; ok=1
    fi
  done
  local make_section target
  make_section="$(section "$WORK/docs/infrastructure.md" 'Makefile$')"
  for target in 'make up-shared' 'make migrate' 'make logs-shared' 'make test-infra'; do
    grep -qF "\`$target\`" <<< "$make_section" || { note "Makefile sem $target"; ok=1; }
  done
  return $ok
}
check "C27 docs describe existing files" t_c27_existing_files

t_c28_database_docs() {
  local body term
  body="$(section "$WORK/docs/database.md" 'Migrations$')"
  for term in 'golang-migrate' 'NNNN_<nome>.up.sql' 'force'; do
    grep -qF "$term" <<< "$body" || { note "database.md › Migrations sem '$term'"; return 1; }
  done
}
check "C28 database docs name the tool" t_c28_database_docs

# Container do frontend (.specs/features/frontend-container) - S5.

# Frases do arquivo, uma por linha.
sentences() { tr '\n' ' ' < "$1" | sed -E 's/([.!?]) +/\1\n/g; s/#/\n/g'; }

t_fe24_decision() {
  local f="$WORK/docs/decisions.md" body term
  grep -qE '^\| \[16\]\(#16-[^)]*\) \| Frontend em `next dev` com o código copiado pelo Compose Watch \| Definida \|$' "$f" \
    || { note "índice sem a decisão 16 Definida"; return 1; }
  body="$(section "$f" '16\. Frontend em `next dev` com o código copiado pelo Compose Watch$')"
  [ -n "$body" ] || { note "seção 16 ausente"; return 1; }
  for term in 'next dev' 'Compose Watch' 'bind mount' 'Turbopack'; do
    grep -qF "$term" <<< "$body" || { note "decisão 16 sem '$term'"; return 1; }
  done
}
check "FE24 decision 16 recorded" t_fe24_decision

t_fe25_infrastructure() {
  local f="$WORK/docs/infrastructure.md" hits make_section row ok=0 term
  hits="$(sentences "$f" | grep -F 'frontend' | grep -E '(não existe\b|não existem\b)')"
  [ -z "$hits" ] || { note "infrastructure.md diz que o frontend não existe: $hits"; ok=1; }
  make_section="$(section "$f" 'Makefile$')"
  for term in 'make watch-frontend' 'make frontend-npm'; do
    grep -qF "\`$term" <<< "$make_section" || { note "Makefile sem $term"; ok=1; }
  done
  row="$(grep -F '| `make migrate` |' <<< "$make_section")"
  for term in postgres redis-limiter mailpit; do
    grep -qF "$term" <<< "$row" || { note "linha do make migrate sem $term"; ok=1; }
  done
  grep -qF 'node:26.13.0-alpine' <<< "$(awk '/^### Versões fixadas/{on=1; next} on && /^##/{exit} on' "$f")" \
    || { note "Versões fixadas sem node:26.13.0-alpine"; ok=1; }
  return $ok
}
check "FE25 infrastructure docs describe frontend" t_fe25_infrastructure

t_fe26_readme() {
  local f="$WORK/README.md" hits body shared_line stack_line ok=0 term
  hits="$(sentences "$f" | grep -iF 'frontend' | grep -F 'em design')"
  [ -z "$hits" ] || { note "README diz que o frontend está em design: $hits"; ok=1; }
  body="$(section "$f" 'Como vai funcionar$')"
  # Só as linhas de comando, não a prosa que cita os alvos.
  shared_line="$(grep -nx 'make up-shared' <<< "$body" | head -1 | cut -d: -f1)"
  stack_line="$(grep -nxE 'make up-(laravel|nest|go)' <<< "$body" | head -1 | cut -d: -f1)"
  [ -n "$shared_line" ] && [ -n "$stack_line" ] && [ "$shared_line" -lt "$stack_line" ] \
    || { note "make up-shared não vem antes da primeira stack"; ok=1; }
  for term in 'make watch-frontend' 'make frontend-npm'; do
    grep -qF "$term" <<< "$body" || { note "Como vai funcionar sem $term"; ok=1; }
  done
  return $ok
}
check "FE26 readme describes frontend" t_fe26_readme

t_fe27_stacks() {
  local body term
  body="$(section "$WORK/docs/stacks.md" 'Frontend$')"
  for term in 'next dev' 'make watch-frontend' 'make frontend-npm'; do
    grep -qF "$term" <<< "$body" || { note "stacks.md › Frontend sem '$term'"; return 1; }
  done
}
check "FE27 stacks docs describe frontend" t_fe27_stacks

# Limite por IP (.specs/features/registration-ip-limit) - S1 e S2.

CONTRACT_DOC="$WORK/docs/api-contract.md"

# Linhas de uma seção "### <título>" até o próximo "##" de qualquer nível.
subsection() { awk -v h="$2" '$0 ~ "^### "h {on=1; next} on && /^##/{exit} on' "$1"; }
# Primeiro bloco mermaid de um texto.
mermaid_of() { awk '/^```mermaid$/{on=1; next} on && /^```$/{exit} on'; }
# Número da primeira linha que contém o texto, ou vazio.
line_of() { grep -nF -- "$2" <<< "$1" | head -1 | cut -d: -f1; }
ascending() {
  local prev=0 n
  for n in "$@"; do
    [ -n "$n" ] && [ "$n" -gt "$prev" ] || return 1
    prev="$n"
  done
}

t_ip1_quota() {
  local body ok=0 term consumes returns
  body="$(section "$CONTRACT_DOC" 'Limite por IP$')"
  [ -n "$body" ] || { note "api-contract.md sem ## Limite por IP"; return 1; }
  # Cada valor na própria linha da tabela.
  row_has() {
    local label="$1" row term; shift
    row="$(grep -F "| $label |" <<< "$body" | head -1)"
    for term in "$@"; do
      grep -qF -- "$term" <<< "$row" || { note "linha '$label' sem '$term': $row"; return 1; }
    done
  }
  row_has 'Identidade contada' 'IP do cliente' || ok=1
  grep -F '| Identidade contada |' <<< "$body" | grep -qF 'e-mail' && { note "identidade cita e-mail"; ok=1; }
  row_has 'Chave' '`registration:ip:{sha256(ip)}`' || ok=1
  row_has 'Cota' '20' 'REGISTRATION_MAX_PER_IP' || ok=1
  row_has 'Janela' 'Fixa' 'primeira reserva' '3600' 'REGISTRATION_IP_WINDOW_SECONDS' || ok=1
  consumes="$(grep -F '| O que consome a cota |' <<< "$body")"
  grep -qF '`201`' <<< "$consumes" && ! grep -qE '`(409|422|429|500)`' <<< "$consumes" \
    || { note "consumo da cota não é só o 201: $consumes"; ok=1; }
  returns="$(grep -F '| O que devolve a reserva |' <<< "$body")"
  grep -qF '`409`' <<< "$returns" && grep -qF '`500`' <<< "$returns" \
    || { note "devolução sem 409 e 500: $returns"; ok=1; }
  return $ok
}
check "IP1 contract describes ip quota" t_ip1_quota

t_ip2_example() {
  local body expected
  body="$(section "$CONTRACT_DOC" 'Limite por IP$')"
  expected="registration:ip:$(printf '%s' '203.0.113.10' | sha256sum | cut -d' ' -f1)"
  [ "$expected" = registration:ip:631f08140b24b7274d12df3c37a1a80ce5876dafd7007d772e0114fddf88b682 ] \
    || { note "sha256 de 203.0.113.10 difere do plano: $expected"; return 1; }
  grep -E '203\.0\.113\.10' <<< "$body" | grep -qF "\`$expected\`" \
    || { note "› Limite por IP sem o exemplo 203.0.113.10 -> $expected"; return 1; }
}
check "IP2 ip key example matches sha256" t_ip2_example

t_ip3_order() {
  local body chart list ok=0
  body="$(subsection "$CONTRACT_DOC" 'Ordem de processamento$')"
  chart="$(mermaid_of <<< "$body")"
  ascending "$(line_of "$chart" 'Corpo válido')" "$(line_of "$chart" 'Conta a tentativa')" \
      "$(line_of "$chart" 'Reserva')" "$(line_of "$chart" 'Transação')" \
    || { note "fluxograma fora da ordem validar, contar, reservar, transação"; ok=1; }
  grep -F 'Devolve' <<< "$chart" | grep -qF '409' || { note "fluxograma sem devolução antes do 409"; ok=1; }
  grep -F 'Devolve' <<< "$chart" | grep -qF '500' || { note "fluxograma sem devolução antes do 500"; ok=1; }
  list="$(grep -E '^[0-9]+\. ' <<< "$body")"
  ascending "$(line_of "$list" 'Validar')" "$(line_of "$list" 'Contar a tentativa')" \
      "$(line_of "$list" 'Reservar')" "$(line_of "$list" 'Gravar')" \
    || { note "lista fora da ordem validar, contar, reservar, gravar"; ok=1; }
  grep -iF 'devolve' <<< "$list" | grep -F '409' | grep -qF '500' \
    || { note "lista sem devolução em 409 e 500"; ok=1; }
  return $ok
}
check "IP3 processing order reserves before transaction" t_ip3_order

t_ip4_responses() {
  local body row
  # › Respostas com as subseções ####, até o próximo ## ou ###.
  body="$(awk '/^### Respostas$/{on=1; next} on && /^#{2,3} /{exit} on' "$CONTRACT_DOC")"
  row="$(grep -F '| `429 Too Many Requests` |' <<< "$body")"
  grep -qF 'par IP + e-mail' <<< "$row" && grep -qF 'cota do IP' <<< "$row" \
    || { note "linha do 429 sem as duas causas: $row"; return 1; }
  grep -qF 'janela que recusou' <<< "$body" || { note "› Respostas sem 'janela que recusou'"; return 1; }
  sentences <(printf '%s\n' "$body") | grep -F 'corpo' | grep -qF 'mesmo' \
    || { note "› Respostas não diz que o 429 tem o mesmo corpo nos dois casos"; return 1; }
}
check "IP4 responses name both 429 causes" t_ip4_responses

t_ip12_limitations() {
  local body ok=0
  body="$(section "$CONTRACT_DOC" 'Limitações conhecidas$')"
  grep -qF 'Sem limite só por IP' <<< "$body" && { note "limitação 'Sem limite só por IP' ainda presente"; ok=1; }
  grep -F 'mesmo IP' <<< "$body" | grep -F '20' | grep -F 'cota' | grep -qF 'por hora' \
    || { note "limitações sem a cota dividida por quem tem o mesmo IP"; ok=1; }
  grep -iF 'devolução' <<< "$body" | grep -F 'falha' | grep -qF 'unidade' \
    || { note "limitações sem a devolução que falha"; ok=1; }
  return $ok
}
check "IP12 limitations describe ip quota" t_ip12_limitations

t_ip13_env() {
  local block rules ok=0 pair
  block="$(awk '/^# Regras de negócio$/{on=1; next} on && (/^$/ || /^#/){exit} on' "$WORK/.env.example")"
  rules="$(awk '/^### Regras de negócio$/{on=1; next} on && /^##/{exit} on' "$WORK/docs/infrastructure.md")"
  for pair in REGISTRATION_MAX_PER_IP=20 REGISTRATION_IP_WINDOW_SECONDS=3600; do
    grep -qxF "$pair" <<< "$block" || { note ".env.example › Regras de negócio sem $pair"; ok=1; }
    grep -qF "| \`${pair%%=*}\` | \`${pair#*=}\` |" <<< "$rules" \
      || { note "infrastructure.md › Regras de negócio sem $pair"; ok=1; }
  done
  return $ok
}
check "IP13 env vars documented and exemplified" t_ip13_env

t_ip14_scenarios() {
  local body s12 s13 numbers ok=0
  body="$(section "$WORK/docs/architecture.md" 'Cenários para validar a implementação$')"
  s12="$(grep -E '^12\. ' <<< "$body")"
  s13="$(grep -E '^13\. ' <<< "$body")"
  for term in '20 e-mails' '(201)' '429 no 21º' 'sem gravar nada' '409 sem consumir cota'; do
    grep -qF "$term" <<< "$s12" || { note "cenário 12 sem '$term'"; ok=1; }
  done
  grep -qF '50' <<< "$s13" && grep -qF 'exatamente 20' <<< "$s13" && grep -qF '201' <<< "$s13" \
    || { note "cenário 13 sem 50 paralelos e exatamente 20 201: $s13"; ok=1; }
  numbers="$(grep -oE '^[0-9]+\.' <<< "$body" | tr -d .)"
  [ "$numbers" = "$(seq 1 "$(grep -c . <<< "$numbers")")" ] \
    || { note "cenários fora de ordem: $(tr '\n' ' ' <<< "$numbers")"; ok=1; }
  return $ok
}
check "IP14 scenarios 12 and 13 in order" t_ip14_scenarios

t_ip15_decision() {
  local f="$WORK/docs/decisions.md" body term
  grep -qE '^\| \[17\]\(#17-[^)]*\) \| Cota de cadastros concluídos por IP \| Definida \|$' "$f" \
    || { note "índice sem a decisão 17 Definida"; return 1; }
  body="$(section "$f" '17\. Cota de cadastros concluídos por IP$')"
  [ -n "$body" ] || { note "seção 17 ausente"; return 1; }
  for term in 'REGISTRATION_MAX_PER_IP' '201' 'devolve'; do
    grep -qF "$term" <<< "$body" || { note "decisão 17 sem '$term'"; return 1; }
  done
}
check "IP15 decision 17 recorded" t_ip15_decision

t_ip16_readme() {
  local f="$WORK/README.md" row limits ok=0
  row="$(section "$f" 'API$' | grep -F '| `429` |')"
  grep -qF '20 cadastros' <<< "$row" && grep -qF 'por IP' <<< "$row" && grep -qF 'hora' <<< "$row" \
    || { note "linha 429 do README sem 20 cadastros por IP por hora: $row"; ok=1; }
  limits="$(section "$f" 'Limites conhecidos$')"
  grep -F 'mesmo IP' <<< "$limits" | grep -qF '20' \
    || { note "README › Limites conhecidos sem a cota dividida"; ok=1; }
  return $ok
}
check "IP16 readme describes ip quota" t_ip16_readme

t_ip17_frontend_429() {
  section "$CONTRACT_DOC" 'Comportamento do frontend$' \
    | grep -E '^\| 429 \|' | grep -qF 'Muitas tentativas de cadastro. Tente novamente em {minutos} minutos.' \
    || { note "Comportamento do frontend sem o texto genérico do 429"; return 1; }
}
check "IP17 frontend 429 text is generic" t_ip17_frontend_429

# Formulário de cadastro (.specs/features/registration-form) - S3.

t_rf25_contract() {
  local body ok=0
  body="$(section "$CONTRACT_DOC" 'Comportamento do frontend$')"
  grep -qF 'não valida' <<< "$body" || { note "Comportamento do frontend sem 'não valida'"; ok=1; }
  grep -F '201' <<< "$body" | grep -qF 'qualquer corpo' || { note "sem 201 com qualquer corpo"; ok=1; }
  grep -F '409' <<< "$body" | grep -F '422' | grep -F '`name`' | grep -F '`email`' | grep -qF '500' \
    || { note "sem 409 ou 422 sem item de name ou email -> texto do 500"; ok=1; }
  grep -F 'arredondad' <<< "$body" | grep -qF 'para cima' || { note "sem a regra dos minutos"; ok=1; }
  grep -qE '(^|[^0-9])1 minuto([^s]|$)' <<< "$body" || { note "sem '1 minuto' no singular"; ok=1; }
  grep -qF 'Muitas tentativas de cadastro. Tente novamente mais tarde.' <<< "$body" \
    || { note "sem o texto do 429 sem Retry-After"; ok=1; }
  return $ok
}
check "RF25 contract describes form rules" t_rf25_contract

t_rf26_decision() {
  local f="$WORK/docs/decisions.md" body term
  grep -qE '^\| \[18\]\(#18-[^)]*\) \| Formulário sem validação no navegador \| Definida \|$' "$f" \
    || { note "índice sem a decisão 18 Definida"; return 1; }
  body="$(section "$f" '18\. Formulário sem validação no navegador$')"
  [ -n "$body" ] || { note "seção 18 ausente"; return 1; }
  for term in '422' 'cenário 3'; do
    grep -qF "$term" <<< "$body" || { note "decisão 18 sem '$term'"; return 1; }
  done
}
check "RF26 decision 18 recorded" t_rf26_decision

t_rf27_docs() {
  local body ok=0
  body="$(section "$WORK/docs/stacks.md" 'Frontend$')"
  grep -qF 'só o esqueleto' <<< "$body" && { note "stacks.md › Frontend ainda diz que só existe o esqueleto"; ok=1; }
  grep -qF 'make test-frontend' <<< "$body" || { note "stacks.md › Frontend sem make test-frontend"; ok=1; }
  # Sem pipe para o grep -q: com pipefail, o awk sem leitor (SIGPIPE) faria falhar.
  grep -qF '`make test-frontend`' <<< "$(section "$WORK/docs/infrastructure.md" 'Makefile$')" \
    || { note "infrastructure.md › Makefile sem make test-frontend"; ok=1; }
  sentences "$WORK/README.md" | grep -iF 'frontend' | grep -qF 'esqueleto' \
    && { note "README ainda descreve o frontend como esqueleto"; ok=1; }
  section "$WORK/README.md" 'Como vai funcionar$' | grep -qx 'make test-frontend' \
    || { note "README › Como vai funcionar sem make test-frontend"; ok=1; }
  return $ok
}
check "RF27 docs describe the form and test-frontend" t_rf27_docs

# Base da API Laravel (.specs/features/laravel-api-base) - S5 e o CI.

t_lv35_decision() {
  local f="$WORK/docs/decisions.md" body term
  grep -qE '^\| \[19\]\(#19-[^)]*\) \| `GET /health` comum às três stacks \| Definida \|$' "$f" \
    || { note "índice sem a decisão 19 Definida"; return 1; }
  body="$(section "$f" '19\. `GET /health` comum às três stacks$')"
  [ -n "$body" ] || { note "seção 19 ausente"; return 1; }
  for term in '`200`' '`503`' '`database`' '`limiter`' '3 s'; do
    grep -qF "$term" <<< "$body" || { note "decisão 19 sem '$term'"; return 1; }
  done
}
check "LV35 decision 19 recorded" t_lv35_decision

t_lv36_decision() {
  local f="$WORK/docs/decisions.md" body term
  grep -qE '^\| \[20\]\(#20-[^)]*\) \| Código da stack Laravel copiado pelo Compose Watch \| Definida \|$' "$f" \
    || { note "índice sem a decisão 20 Definida"; return 1; }
  body="$(section "$f" '20\. Código da stack Laravel copiado pelo Compose Watch$')"
  [ -n "$body" ] || { note "seção 20 ausente"; return 1; }
  for term in 'bind mount' 'vendor/' 'make watch-laravel' 'make laravel-composer'; do
    grep -qF "$term" <<< "$body" || { note "decisão 20 sem '$term'"; return 1; }
  done
}
check "LV36 decision 20 recorded" t_lv36_decision

t_lv37_contract_health() {
  local body status term ok=0
  body="$(section "$CONTRACT_DOC" '`GET /health`$')"
  [ -n "$body" ] || { note "api-contract.md sem a seção GET /health"; return 1; }
  for term in '{"status":"ok","checks":{"database":"ok","limiter":"ok"}}' \
    '{"status":"fail","checks":{"database":"ok","limiter":"fail"}}' '`503`' 'Cache-Control: no-store' '3 s'; do
    grep -qF -- "$term" <<< "$body" || { note "seção GET /health sem '$term'"; ok=1; }
  done
  status="$(grep -m1 -F '> **Status:**' "$CONTRACT_DOC")"
  grep -qF 'Laravel' <<< "$status" && grep -qF 'GET /health' <<< "$status" \
    || { note "status do contrato não cita a Laravel com GET /health"; ok=1; }
  return $ok
}
check "LV37 contract describes health" t_lv37_contract_health

t_lv38_infrastructure() {
  local f="$WORK/docs/infrastructure.md" make_section versions ci stack_vars compose_row term ok=0
  make_section="$(section "$f" 'Makefile$')"
  for term in 'make watch-laravel' 'make laravel-composer' 'make test-laravel'; do
    grep -qF "\`$term" <<< "$make_section" || { note "Makefile sem $term"; ok=1; }
  done
  grep -F '| `make up-laravel` |' <<< "$make_section" | grep -qF 'reconstru' \
    || { note "linha do make up-laravel não diz que reconstrói"; ok=1; }
  versions="$(awk '/^### Versões fixadas/{on=1; next} on && /^##/{exit} on' "$f")"
  for term in nginx:1.30.6-alpine php:8.5.12-fpm-alpine composer:2.11.1; do
    grep -qF "$term" <<< "$versions" || { note "Versões fixadas sem $term"; ok=1; }
  done
  compose_row="$(grep -F '| `apis/laravel/docker-compose.yml` |' "$f")"
  grep -qF '`nginx`' <<< "$compose_row" && grep -qF '`php-fpm`' <<< "$compose_row" \
    || { note "linha do compose da Laravel: $compose_row"; ok=1; }
  ci="$(section "$f" 'Integração contínua$')"
  grep -qF 'make test-laravel' <<< "$ci" || { note "Integração contínua sem make test-laravel"; ok=1; }
  stack_vars="$(awk '/^### Específicas de stack/{on=1; next} on && /^##/{exit} on' "$f")"
  for term in APP_KEY APP_ENV APP_DEBUG; do
    grep -qE "^\| \`$term\` \|" <<< "$stack_vars" || { note "Específicas de stack sem $term"; ok=1; }
  done
  return $ok
}
check "LV38 infrastructure docs describe laravel" t_lv38_infrastructure

t_lv39_readme() {
  local f="$WORK/README.md" hits body addresses ok=0
  hits="$(sentences "$f" | grep -F 'três stacks' | grep -F 'em design')"
  [ -z "$hits" ] || { note "README diz que as três stacks estão em design: $hits"; ok=1; }
  body="$(section "$f" 'Como vai funcionar$')"
  grep -qx 'make watch-laravel' <<< "$body" || { note "Como vai funcionar sem make watch-laravel"; ok=1; }
  grep -qE '^make laravel-composer ARGS=' <<< "$body" || { note "Como vai funcionar sem make laravel-composer"; ok=1; }
  grep -qx 'make test-laravel' <<< "$body" || { note "Como vai funcionar sem make test-laravel"; ok=1; }
  addresses="$(subsection "$f" 'Endereços$')"
  grep -qF 'http://localhost:8080/health' <<< "$addresses" || { note "Endereços sem /health"; ok=1; }
  return $ok
}
check "LV39 readme describes laravel base" t_lv39_readme

t_lv40_stacks() {
  local body row service term ok=0
  body="$(section "$WORK/docs/stacks.md" 'Laravel$')"
  for service in nginx php-fpm; do
    row="$(grep -E "^\| \`$service\` \|" <<< "$body" | head -1)"
    grep -qF 'Existe' <<< "$row" || { note "linha de $service: $row"; ok=1; }
  done
  for service in scheduler horizon redis; do
    row="$(grep -E "^\| \`$service\` \|" <<< "$body" | head -1)"
    grep -qF 'Chega com o outbox' <<< "$row" || { note "linha de $service: $row"; ok=1; }
  done
  for term in 'GET /health' 'make watch-laravel' 'make laravel-composer'; do
    grep -qF "$term" <<< "$body" || { note "stacks.md › Laravel sem '$term'"; ok=1; }
  done
  return $ok
}
check "LV40 stacks docs describe laravel base" t_lv40_stacks

t_lv41_help() {
  local out term
  out="$(make --no-print-directory -C "$WORK" help)"
  for term in 'make watch-<stack>' 'make laravel-composer' 'make test-laravel'; do
    grep -qF "$term" <<< "$out" || { note "make help sem $term"; return 1; }
  done
}
check "LV41 help lists laravel targets" t_lv41_help
