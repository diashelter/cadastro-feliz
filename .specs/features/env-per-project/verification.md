# Variáveis de ambiente por projeto verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at ed063a4
**Verifier**: independent sub-agent (author != verifier)

Lido em `b098389` (de `ed063a4` para cá só muda o `## Handoff` de `checks.md`; a visita é de `e3f6dc2`, que difere do `HEAD` só em `.specs`). Cada prova de comando foi rodada de novo num clone descartável em `scratchpad`, com uma quebra de propósito por vez; nada do tree real foi editado e nenhum container foi subido.

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | walk - `make up-shared` na cópia limpa de `e3f6dc2` (`**Walked:**` C1) | sim - saída `0`, os quatro serviços `healthy`, `localhost:8080` na página e nenhum `.env` |
| C2 | walk - `make migrate` e `schema_migrations` (`**Walked:**` C2) | sim - `2\|f`, igual a `0002`, a última de `database/migrations` |
| C3 | walk - `.env` da raiz com a porta 9090 e `make up-shared` (`**Walked:**` C3) | sim - `localhost:9090`, sem `localhost:8080`, a mesma imagem |
| C4 | walk - `.env` da raiz com `DB_PASSWORD=outra`, `make up-shared` e `cmp` (`**Walked:**` C4) | sim |
| C5 | comando `d=$(mktemp -d) && git archive HEAD \| tar ... docker compose -f "$d/apis/laravel/docker-compose.yml" config ...` | não - o `.env` da cópia não fica no diretório de onde o comando roda, como o da raiz fica para o `make`, e a prova não passa pelo `Makefile`: com `COMPOSE := docker compose --env-file .env` de volta no `Makefile` a prova sai `0`, e `make up-laravel` resolveria `2 7` |
| C6 | comando `! git ls-files \| grep -qE '(^\|/)[.]env[.]example$' && ... git check-ignore -q` | sim - falha com `apis/nestjs/.env.example`, sem a linha `.env` e com `/.env` no `.gitignore` |
| C7 | walk - `make up-laravel`, `GET /health` e procura de `.env` (`**Walked:**` C7) | sim |
| C8 | walk - `printenv` em `php-fpm`, `scheduler` e `horizon` (`**Walked:**` C8) | sim - conferido também por `docker compose config` no `HEAD`: os três com `local`, `true`, `7`, `ops@cadastro-feliz.local`, `http://localhost:3000` e `APP_KEY` de 32 bytes, o mesmo do `.env.example` antigo |
| C9 | walk - `apis/laravel/.env` com limite 2, três `POST /users` e `config` do NestJS (`**Walked:**` C9) | sim - `409 409 429` e `5` |
| C10 | walk - `apis/laravel/.env` com `PROBE_ONLY_IN_FILE=1`, `make up-laravel` (`**Walked:**` C10) | sim - sem `/var/www/html/.env`, sem a variável, `/health` `200` |
| C11 | walk - `make up-nest`, `GET /health` e procura de `.env` (`**Walked:**` C11) | sim |
| C12 | walk - `apis/nestjs/.env` com lote 2, `printenv` no `worker` e `config` da Laravel (`**Walked:**` C12) | sim |
| C13 | walk - `apis/laravel/.env` com limite 2, `make up-nest` e `printenv` na `api` (`**Walked:**` C13) | sim |
| C14 | comando `for f in docker-compose.yml ...; do ! sed ... \| grep -vxE '[$][{]...:-[^}]+[}]' ...; env -i ... config -q ...` | sim - falha com `${API_PORT}`, `${DB_HOST-postgres}`, `${APP_DEBUG:-}` e `$MAIL_FROM` |
| C15 | comando `tr -d '\140' < docs/infrastructure.md \| awk ... '/^### Regras de negócio/' ... grep -qF "\${$name:-$val}"` | não, em parte - pega padrão divergente (`:-6`, `:-36000`, `OUTBOX_RETENTION_DAYS:-8`) e a variável ausente, mas tira da coluna Projetos da documentação quais composes têm de declarar cada regra: sem `OUTBOX_BACKOFF_BASE_SECONDS` no compose do NestJS e sem `nest` na linha da documentação, sai `0` (e C16 também) |
| C16 | comando `for f in ...; do p=$(sed -nE 's/^name: cadastro-feliz-//p' "$f"); ... grep -qw "$p" ...` | não, em parte - pega `DB_PASSWORD` `outra`, projeto faltando (`DB_HOST` sem `shared`), variável nova sem linha e linha sem compose; mas não pega um projeto a mais: `APP_DEBUG` com `laravel`, `nest` na documentação sai `0` |
| C17 | comando `grep -qE '^[\|] \[29\]' docs/decisions.md && ... ! grep -nE '[.]env[.]example\|única fonte\|...'` | sim, com ressalva - pega `.env.example` no README e design sem nota; "única fonte" é uma lista de frases (`Todas as variáveis ficam no .env da raiz` em docs/stacks.md passa); lidos à mão, os três documentos estão certos no `HEAD` |
| C18 | comando `[ ! -e tests/infra ] && ... ! make -n test-infra ... jobs = "frontend,laravel,nest"` | sim - falha com alvo `test-infra`, job `infra` a mais e `apis/nestjs/src/scripts` versionado |
| C19 | comando `grep -qE '^[\|] \[30\]' docs/decisions.md && ... ! grep -rqE ... 'tests/infra\|test-infra\|run[.]sh' ...` | sim - falha com `tests/infra` em `page.test.tsx`, `make test-infra` em docs/architecture.md e a 23 sem "Substituída" |
| C20 | `make test-laravel`, `make test-nest`, `make test-frontend` | sim - `proofs.md` com 61, 21 e 26 testes, saída `0` |

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| Nada que roda a cada rodada prova que o `.env` da raiz não chega às stacks pelo `make`; a door 1 ("o `Makefile` chama `docker compose` sem `--env-file`") não tem prova de comando | C5 grava o `.env` em `$d/.env` e roda o Compose de outro diretório, sem o `Makefile`; num clone com `COMPOSE := docker compose --env-file .env` C5 sai `0`, e `docker compose --env-file .env -f apis/laravel/docker-compose.yml config` (o que `make -n up-laravel` imprime) dá `REGISTRATION_MAX_ATTEMPTS=2`, `OUTBOX_BATCH_SIZE=7`; as visitas com `.env` na raiz (C3, C4) só rodam `make up-shared` | em C5, rodar o `config` de dentro de `$d` com o comando que o `Makefile` monta (por exemplo, extraindo de `make -s -n up-laravel` o comando do Compose) e acrescentar `! grep -q -- '--env-file' Makefile` | `6149445` - C5 começa com `! grep -qE '^[^#]*--env-file' Makefile` e roda o Compose de dentro da cópia, como o `Makefile`; com `--env-file .env` de volta no `Makefile`, C5 sai `1` |
| C15 deixa a documentação decidir quais composes têm de declarar cada regra, e o critério fixa a lista | AC 15 exige os quatro `REGISTRATION_*` e `OUTBOX_BATCH_SIZE`, `OUTBOX_REPUBLISH_AFTER_SECONDS`, `OUTBOX_MAX_ATTEMPTS`, `OUTBOX_BACKOFF_BASE_SECONDS` nos dois composes; tirando `OUTBOX_BACKOFF_BASE_SECONDS` do compose do NestJS e `nest` da linha em docs/infrastructure.md, C15 e C16 saem `0` | em C15, conferir essas oito nos dois composes por nome fixo, além da coluna Projetos | `6149445` - C15 confere as oito por nome fixo nos dois composes; sem `OUTBOX_BACKOFF_BASE_SECONDS` no NestJS, C15 sai `1` |
| C16 confere a coluna Projetos só num sentido: um projeto que não declara a variável pode estar listado | AC 16 pede "os projetos que a declaram"; com `APP_DEBUG` como `laravel`, `nest` em docs/infrastructure.md, C16 sai `0` | em C16, comparar o conjunto da coluna Projetos de cada linha (fora `go`) com o conjunto de composes que interpolam a variável | `6149445` - C16 compara o conjunto da coluna Projetos com o dos composes que declaram cada variável; com `APP_DEBUG` em `laravel`, `nest`, C16 sai `1` |

Exemplos próprios, no `HEAD`, que seguraram: `.env` da raiz com `API_PORT=9999` e `APP_ENV=production`, Compose chamado da raiz como o `make` chama → Laravel com porta `8080`, `APP_ENV=local` e `5 100`, NestJS com `8080` e `5` (AC 5); `apis/laravel/.env` com `REGISTRATION_MAX_ATTEMPTS=` vazio e `OUTBOX_BATCH_SIZE=0` → Laravel com `5` (o `:-` trata vazio como ausente) e `0`, NestJS com `5 100` (AC 9/12); padrões `:-36000` e `OUTBOX_RETENTION_DAYS:-8` → C15 falha (AC 15); variável nova `FOO_NEW` no compose do NestJS sem linha na documentação → C16 falha (AC 16). Todos os padrões dos composes são iguais aos valores do `.env.example` de `c844baf`, menos `RABBITMQ_URL`, que é da stack Go.
