# Variáveis de ambiente por projeto checks

Build: none - o repositório não tem build nem lint para composes e `Makefile`; os type checks de frontend e NestJS rodam dentro de `make test-frontend` e `make test-nest` (C18)
Plan: `.specs/features/env-per-project/plan.md`

20 checks in 5 slices · 2 one-way doors · 0 open, of which 0 block

Sem suíte de infraestrutura (decisão 30): o que só aparece com os containers no ar é provado por uma visita registrada em `**Walked:**`, e o que os arquivos decidem é provado por um comando que roda sobre eles, sem subir nada.

## Checks

### S1 - `cadastro-feliz-shared` sem arquivo de ambiente

**C1** - Numa cópia sem nenhum `.env`, `make up-shared` sai com `0`, deixa `postgres`, `redis-limiter`, `mailpit` e `frontend` saudáveis, a página mostra `localhost:8080`, e não existe arquivo `.env` em lugar nenhum da cópia (AC 1)
Proof: walk - numa cópia limpa do `HEAD`, rodar `make up-shared` e procurar `.env` na cópia

**C2** - Numa cópia sem nenhum `.env`, `make migrate` sai com `0`, a versão do migrate é a do último arquivo de `database/migrations`, e não existe arquivo `.env` (AC 2)
Proof: walk - na mesma cópia, `make migrate` e a versão em `schema_migrations`

**C3** - Com `NEXT_PUBLIC_API_URL` trocado para `localhost:9090` no `.env` da raiz, `make up-shared` mostra `localhost:9090`, não mostra `localhost:8080` e mantém a imagem (AC 3)
Proof: walk - `.env` da raiz com a porta 9090, `make up-shared`, a página e o id da imagem

**C4** - Com o `.env` da raiz contendo `DB_PASSWORD=outra`, `make up-shared` deixa o arquivo byte a byte igual (AC 4)
Proof: walk - `.env` da raiz com `DB_PASSWORD=outra`, `make up-shared` e `cmp` com a cópia de antes

**C5** - Com `REGISTRATION_MAX_ATTEMPTS=2` e `OUTBOX_BATCH_SIZE=7` no `.env` da raiz, e depois com o `.env.example` antigo e completo mais esses dois valores, o Compose, chamado da raiz e sem `--env-file`, como o `Makefile` o chama, resolve `5` e `100` nas duas stacks, e os serviços comuns continuam resolvendo `NEXT_PUBLIC_API_URL` (AC 5)
Proof: `! grep -qE '^[^#]*--env-file' Makefile && d=$(mktemp -d) && git archive HEAD | tar -x -C "$d" && git show c844baf:.env.example > "$d/old.env" && cd "$d" && printf 'REGISTRATION_MAX_ATTEMPTS=2\nOUTBOX_BATCH_SIZE=7\n' > .env && [ "$(docker compose -f apis/laravel/docker-compose.yml config --format json | jq -r '.services["php-fpm"].environment | "\(.REGISTRATION_MAX_ATTEMPTS) \(.OUTBOX_BATCH_SIZE)"')" = "5 100" ] && [ "$(docker compose -f apis/nestjs/docker-compose.yml config --format json | jq -r '.services.worker.environment | "\(.REGISTRATION_MAX_ATTEMPTS) \(.OUTBOX_BATCH_SIZE)"')" = "5 100" ] && { cat old.env; printf 'REGISTRATION_MAX_ATTEMPTS=2\nOUTBOX_BATCH_SIZE=7\n'; } > .env && [ "$(docker compose -f apis/laravel/docker-compose.yml config --format json | jq -r '.services["php-fpm"].environment | "\(.REGISTRATION_MAX_ATTEMPTS) \(.OUTBOX_BATCH_SIZE)"')" = "5 100" ] && [ "$(docker compose -f apis/nestjs/docker-compose.yml config --format json | jq -r '.services.worker.environment | "\(.REGISTRATION_MAX_ATTEMPTS) \(.OUTBOX_BATCH_SIZE)"')" = "5 100" ] && [ "$(docker compose -f docker-compose.yml config --format json | jq -r '.services.frontend.environment.NEXT_PUBLIC_API_URL')" = "http://localhost:8080" ]`

**C6** - Não há `.env.example` versionado em nenhum diretório, e o git ignora `.env` na raiz, em `apis/laravel` e em `apis/nestjs` (AC 6)
Proof: `! git ls-files | grep -qE '(^|/)[.]env[.]example$' && for p in .env apis/laravel/.env apis/nestjs/.env; do git check-ignore -q "$p" || exit 1; done`

### S2 - `cadastro-feliz-laravel` com padrões próprios

**C7** - Numa cópia sem nenhum `.env`, `make up-laravel` sai com `0`, `GET /health` responde `200`, e não existe arquivo `.env` (AC 7)
Proof: walk - na cópia limpa, `make up-laravel`, `GET /health` e procurar `.env`

**C8** - Sem nenhum `.env`, `php-fpm`, `scheduler` e `horizon` têm `APP_ENV=local`, `APP_DEBUG=true`, `APP_KEY` com `base64:` e 32 bytes, `OUTBOX_RETENTION_DAYS=7`, `OUTBOX_ALERT_EMAIL=ops@cadastro-feliz.local` e `CORS_ALLOWED_ORIGIN` com a origem HTTP de `localhost:3000` (AC 8)
Proof: walk - `printenv` nos três containers da cópia limpa

**C9** - Com `REGISTRATION_MAX_ATTEMPTS=2` em `apis/laravel/.env`, duas tentativas com e-mail já cadastrado respondem `409` e a terceira `429`, e o Compose resolve `5` para o NestJS (AC 9)
Proof: walk - `apis/laravel/.env` com o limite 2, `make up-laravel`, três `POST /users` com um e-mail já cadastrado, e `docker compose config` do NestJS

**C10** - Com `apis/laravel/.env` contendo `PROBE_ONLY_IN_FILE=1` no build, a imagem do `php-fpm` não tem `/var/www/html/.env`, o `php-fpm` não recebe `PROBE_ONLY_IN_FILE`, e `GET /health` responde `200` (AC 10)
Proof: walk - `apis/laravel/.env` com a variável de sonda, `make up-laravel`, o arquivo e o ambiente do `php-fpm` e `GET /health`

### S3 - `cadastro-feliz-nest` com padrões próprios

**C11** - Numa cópia sem nenhum `.env`, `make up-nest` sai com `0`, `GET /health` responde `200`, e não existe arquivo `.env` (AC 11)
Proof: walk - na cópia limpa, `make up-nest`, `GET /health` e procurar `.env`

**C12** - Com `OUTBOX_BATCH_SIZE=2` em `apis/nestjs/.env`, o `worker` tem `OUTBOX_BATCH_SIZE=2` e o Compose resolve `100` para a Laravel (AC 12)
Proof: walk - `apis/nestjs/.env` com o lote 2, `make up-nest`, `printenv` no `worker` e `docker compose config` da Laravel

**C13** - Com `REGISTRATION_MAX_ATTEMPTS=2` em `apis/laravel/.env`, `make up-nest` deixa a `api` com `REGISTRATION_MAX_ATTEMPTS=5` (AC 13)
Proof: walk - `apis/laravel/.env` com o limite 2, `make up-nest` e `printenv` na `api`

### S4 - Regras que valem para todo projeto

**C14** - Nos três composes, toda interpolação tem a forma de variável com padrão não vazio, e o Compose, num shell sem variáveis exportadas e sem `.env`, não avisa variável ausente (AC 14)
Proof: `for f in docker-compose.yml apis/laravel/docker-compose.yml apis/nestjs/docker-compose.yml; do ! sed -e 's/[$][$]//g' -e '/^ *#/d' "$f" | grep -oE '[$][{][^}]*[}]|[$][A-Za-z_][A-Za-z0-9_]*' | grep -vxE '[$][{][A-Za-z_][A-Za-z0-9_]*:-[^}]+[}]' || exit 1; ! (d=$(mktemp -d) && cp "$f" "$d/c.yml" && env -i PATH="$PATH" HOME="$HOME" docker compose -f "$d/c.yml" --profile '*' config -q 2>&1) | grep -qi 'not set' || exit 1; done`

**C15** - Os dois composes de stack declaram os quatro `REGISTRATION_*` e os quatro `OUTBOX_*` comuns, e o padrão de cada uma das 10 regras de negócio de docs/infrastructure.md está, com o mesmo valor, no compose de cada stack que a documentação lista para ela (AC 15)
Proof: `for n in REGISTRATION_MAX_ATTEMPTS REGISTRATION_ATTEMPT_WINDOW_SECONDS REGISTRATION_MAX_PER_IP REGISTRATION_IP_WINDOW_SECONDS OUTBOX_BATCH_SIZE OUTBOX_REPUBLISH_AFTER_SECONDS OUTBOX_MAX_ATTEMPTS OUTBOX_BACKOFF_BASE_SECONDS; do for f in apis/laravel/docker-compose.yml apis/nestjs/docker-compose.yml; do grep -qF "\${$n:-" "$f" || exit 1; done; done && tr -d '\140' < docs/infrastructure.md | awk -F' *[|] *' '/^### Regras de negócio/{on=1;next} on&&/^##/{exit} on&&$2~/^[A-Z_]+$/{print $2, $3, $4}' | { n=0; while read -r name val projects; do n=$((n+1)); for p in laravel nest; do d=$p; [ "$p" = nest ] && d=nestjs; case "$projects" in *"$p"*) grep -qF "\${$name:-$val}" "apis/$d/docker-compose.yml" || exit 1;; esac; done; done; [ "$n" = 10 ]; }`

**C16** - Cada variável interpolada por um compose aparece numa linha só de docs/infrastructure.md › Variáveis de ambiente, com o mesmo padrão (exceto `APP_KEY`, descrito em texto), e a coluna Projetos lista exatamente os composes que a declaram; e cada variável da documentação, exceto as de `go`, é declarada por algum compose (AC 16)
Proof: `for f in docker-compose.yml apis/laravel/docker-compose.yml apis/nestjs/docker-compose.yml; do p=$(sed -nE 's/^name: cadastro-feliz-//p' "$f"); sed -e '/^ *#/d' "$f" | grep -oE '[$][{][A-Z_]+:-[^}]+[}]' | sort -u | sed -E 's/^[$][{]([A-Z_]+):-(.*)[}]$/\1 \2/' | while read -r n v; do row=$(tr -d '\140' < docs/infrastructure.md | grep -E "^[|] $n [|]"); [ "$(printf '%s\n' "$row" | grep -c .)" = 1 ] || exit 1; [ "$n" = APP_KEY ] || printf '%s\n' "$row" | grep -qF "| $n | $v |" || exit 1; printf '%s\n' "$row" | awk -F' *[|] *' '{print $4}' | grep -qw "$p" || exit 1; done || exit 1; done && tr -d '\140' < docs/infrastructure.md | awk -F' *[|] *' '/^## Variáveis de ambiente/{on=1;next} on&&/^## /{exit} on&&$2~/^[A-Z_]+$/&&$4!="go"{print $2}' | while read -r n; do cat docker-compose.yml apis/laravel/docker-compose.yml apis/nestjs/docker-compose.yml | grep -qF "\${$n:-" || exit 1; done && tr -d '\140' < docs/infrastructure.md | awk -F' *[|] *' '/^## Variáveis de ambiente/{on=1;next} on&&/^## /{exit} on&&$2~/^[A-Z_]+$/&&$4!="go"{print $2, $4}' | while read -r n cols; do want=$(printf '%s' "$cols" | tr -d ' ' | tr ',' '\n' | sort | paste -sd, -); got=$(for p in shared:docker-compose.yml laravel:apis/laravel/docker-compose.yml nest:apis/nestjs/docker-compose.yml; do grep -qF "\${$n:-" "${p#*:}" && echo "${p%%:*}"; done | sort | paste -sd, -); [ "$want" = "$got" ] || exit 1; done`

**C17** - docs/decisions.md tem a decisão 29 no índice e na seção, com `--env-file`; os três designs substituídos têm nota que aponta para ela; docs/infrastructure.md, docs/stacks.md e README não citam `.env.example` nem dizem que o `.env` da raiz é a única fonte (AC 17)
Proof: `grep -qE '^[|] \[29\]' docs/decisions.md && awk '/^## 29\./{on=1;next} /^## 30\./{on=0} on' docs/decisions.md | grep -qF -- '--env-file' && for d in shared-infrastructure frontend-container laravel-api-base; do grep -q 'decisão 29' ".design/$d.md" || exit 1; done && ! grep -nE '[.]env[.]example|única fonte|vêm do .[.]env. da raiz|só do .[.]env. da raiz|Cria .[.]env.' docs/infrastructure.md docs/stacks.md README.md`

### S5 - Só testes da aplicação

**C18** - O repositório não tem `tests/infra` nem `apis/nestjs/src/scripts`, `make test-infra` sai com erro, `Makefile` e CI não citam a suíte, e o CI tem só os jobs `frontend`, `laravel` e `nest`, com `make test-frontend`, `make test-laravel` e `make test-nest` (AC 18)
Proof: `[ ! -e tests/infra ] && [ -z "$(git ls-files tests/infra apis/nestjs/src/scripts)" ] && ! make -n test-infra >/dev/null 2>&1 && ! grep -qE 'tests/infra|test-infra|run[.]sh' Makefile .github/workflows/ci.yml && [ "$(awk '/^jobs:/{on=1;next} on&&/^  [a-z_-]+:$/' .github/workflows/ci.yml | tr -d ' :' | paste -sd, -)" = "frontend,laravel,nest" ] && [ "$(grep -cE '^      - name: make test-(frontend|laravel|nest)$' .github/workflows/ci.yml)" = 3 ]`

**C19** - docs/decisions.md tem a decisão 30 no índice e na seção, a decisão 23 está marcada como substituída, e README, docs/infrastructure.md, docs/stacks.md, docs/api-contract.md, docs/architecture.md e o código das stacks e do frontend não citam `tests/infra`, `make test-infra` nem `run.sh` (AC 19)
Proof: `grep -qE '^[|] \[30\]' docs/decisions.md && grep -q '^## 30\. ' docs/decisions.md && awk '/^## 23\./{on=1;next} on&&/^## /{exit} on' docs/decisions.md | grep -q 'Substituída' && ! grep -rqE --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.next 'tests/infra|test-infra|run[.]sh' README.md docs/infrastructure.md docs/stacks.md docs/api-contract.md docs/architecture.md apis frontend`

**C20** - `make test-laravel`, `make test-nest` e `make test-frontend` saem com `0` (AC 20)
Proof: `make test-laravel`
Proof: `make test-nest`
Proof: `make test-frontend`

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| door 1 - projetos que sobem sem arquivo de ambiente (3) | `cadastro-feliz-shared` C1 C2 · `cadastro-feliz-laravel` C7 · `cadastro-feliz-nest` C11 | - |
| door 1 - composes com padrão em toda interpolação (3) | raiz C14 · Laravel C14 · NestJS C14 | - |
| door 1 - sobrescrita ao lado do compose (3) | raiz C3 C4 · `apis/laravel` C9 C10 · `apis/nestjs` C12 | - |
| door 1 - isolamento entre projetos (3) | raiz para as stacks C5 · Laravel para NestJS C9 C13 · NestJS para Laravel C12 | - |
| door 1 - diretórios com `.env` ignorado e sem `.env.example` (3) | raiz C6 · `apis/laravel` C6 · `apis/nestjs` C6 | - |
| door 2 - sobrescrita fora da imagem (1) | `apis/laravel` C10; NestJS e frontend já excluem e não mudam | - |
| AC 5 examples (2) | `.env` parcial C5 · `.env.example` antigo e completo C5 | - |
| AC 9 examples (2) | `409` nas duas primeiras C9 · `429` na terceira C9 | - |
| AC 10 examples (2) | variável só do arquivo C10 · `/health` `200` C10 | - |
| AC 15 examples (2) | padrão `6` diverge C15 · NestJS sem `OUTBOX_RETENTION_DAYS` coerente C15 | - |
| AC 16 examples (2) | `DB_PASSWORD` numa linha com três projetos C16 · padrão divergente C16 | - |
| AC 8 containers Laravel, cada um com as 6 variáveis (3) | `php-fpm` C8 · `scheduler` C8 · `horizon` C8 | - |
| docs da decisão 29 (7) | decisions.md C17 · shared-infrastructure C17 · frontend-container C17 · laravel-api-base C17 · infrastructure.md C16 C17 · stacks.md C17 · README C17 | - |
| docs e código da decisão 30 (8) | decisions.md C19 · README C19 · infrastructure.md C19 · stacks.md C19 · api-contract.md C19 · architecture.md C19 · `apis` C19 · `frontend` C19 | - |
| testes da aplicação (3) | `make test-laravel` C20 · `make test-nest` C20 · `make test-frontend` C20 | - |

## Swept

- validation: C14, C15, C16 - a variável sem padrão e o padrão divergente do contrato
- failure modes: n/a - a infraestrutura não tem testes (decisão 30); um compose quebrado aparece ao subir o projeto
- idempotency: C4 - `make up-shared` repetido não muda um `.env` existente
- authorization: n/a - só ambiente local, sem caller externo
- concurrency: n/a - uma stack ativa por vez (decisão 6), e os alvos rodam em série
- data lifecycle: C5 - um `.env` antigo e completo continua funcionando e não é apagado
- dependency failure: n/a - nenhuma dependência nova; o Compose já interpola padrões
- state transitions: n/a - nenhum estado guardado muda
- observability: n/a - nenhuma saída nova

## Handoff

- **Settled mid-build:** a suíte de infraestrutura sai - user: "Não deveria haver um make test-infra. Eu não preciso de testar a infra localmente. Eu vou subir ela e se ela não subir vou ter uma falha. Remova testes desnecessários para infra estrutura e deixe somente os testes da aplicação. Atualize as documentações."; a suíte de contrato também sai - user: "Remover tests/infra inteiro"
- **Dispatched:** Verifier at `b098389` (proofs.md at `ed063a4`) - returned, FAIL with 3 findings
- **Boundary:** none yet
- **Walked:** em 2026-11-16, num worktree limpo de `e3f6dc2`, sem nenhum `.env` e sem ambiente no ar; quem desenvolve chega a cada estado pelos mesmos alvos do `Makefile`. C1: `make up-shared` saiu com `0`, `postgres`, `redis-limiter`, `mailpit` e `frontend` `healthy`, a página com `localhost:8080`, nenhum `.env` na cópia. C2: `make migrate` saiu com `0`, `schema_migrations` em `2|f`, igual à última migration (`0002`), nenhum `.env`. C7: `make up-laravel` saiu com `0`, `GET /health` `200`, nenhum `.env`. C8: `php-fpm`, `scheduler` e `horizon` com `APP_ENV=local`, `APP_DEBUG=true`, `APP_KEY` de 32 bytes, `OUTBOX_RETENTION_DAYS=7`, `OUTBOX_ALERT_EMAIL=ops@cadastro-feliz.local` e `CORS_ALLOWED_ORIGIN` em `localhost:3000`. C9: Ana cadastrada (`201`), contadores limpos, `apis/laravel/.env` com `REGISTRATION_MAX_ATTEMPTS=2`, `make up-laravel`, três `POST /users` com o mesmo e-mail: `409 409 429`; `docker compose config` do NestJS em `5`. C10: `apis/laravel/.env` com `PROBE_ONLY_IN_FILE=1`, `make up-laravel` saiu com `0`, sem `/var/www/html/.env` no `php-fpm`, sem `PROBE_ONLY_IN_FILE` no ambiente, `GET /health` `200`. C11: `make up-nest` saiu com `0`, `GET /health` `200`, nenhum `.env`. C12: `apis/nestjs/.env` com `OUTBOX_BATCH_SIZE=2`, `make up-nest`, `worker` com `2`, `docker compose config` da Laravel em `100`. C13: `apis/laravel/.env` com `REGISTRATION_MAX_ATTEMPTS=2`, `make up-nest`, `api` com `5`. C3: `.env` da raiz com `NEXT_PUBLIC_API_URL` na porta 9090, `make up-shared`, a página com `localhost:9090` e sem `localhost:8080`, a mesma imagem do `frontend`. C4: `.env` da raiz com `DB_PASSWORD=outra`, `make up-shared` saiu com `0`, o arquivo igual byte a byte. No fim, `make down` e o volume removido: nenhum container nem volume `cadastro-feliz-*` ficou
- **Abandoned:** `tests/infra/env.sh` (EV1 a EV13) e os ajustes dos leitores de `.env` em `tests/infra`, escritos e verdes em `docs` e `env` neste Mac, removidos com a suíte pela decisão 30; a suíte completa não rodava neste Mac (bash 3.2, `stat` e `sed` do BSD)
