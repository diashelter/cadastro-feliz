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
  shared_line="$(grep -nF 'make up-shared' <<< "$body" | head -1 | cut -d: -f1)"
  stack_line="$(grep -nE 'make up-(laravel|nest|go)' <<< "$body" | head -1 | cut -d: -f1)"
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
