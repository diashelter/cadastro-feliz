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
