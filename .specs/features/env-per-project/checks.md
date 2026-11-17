# Variáveis de ambiente por projeto checks

Build: none - o repositório não tem build, lint nem type check para composes, `Makefile` e `tests/infra`; os arquivos são carregados por `run.sh`, e um erro de sintaxe derruba as provas abaixo
Run infra: `bash tests/infra/run.sh`
Plan: `.specs/features/env-per-project/plan.md`

18 checks in 4 slices · 2 one-way doors · 0 open, of which 0 block

## Checks

### S1 - `cadastro-feliz-shared` sem arquivo de ambiente

**C1** - Numa cópia sem nenhum `.env`, `make up-shared` sai com `0`, deixa `postgres`, `redis-limiter`, `mailpit` e `frontend` saudáveis, a página mostra `localhost:8080`, e não existe arquivo `.env` em lugar nenhum da cópia (AC 1)
Proof: run infra | PASS EV1 up-shared on a clean copy creates no env file

**C2** - Numa cópia sem nenhum `.env`, `make migrate` sai com `0`, a versão do migrate é a do último arquivo de `database/migrations`, e não existe arquivo `.env` (AC 2)
Proof: run infra | PASS EV2 migrate on a clean copy creates no env file

**C3** - Com `NEXT_PUBLIC_API_URL` trocado para `localhost:9090` no `.env` da raiz, `make up-shared` mostra `localhost:9090`, não mostra `localhost:8080` e mantém a imagem (AC 3)
Proof: run infra | PASS FE4 api url read at start

**C4** - Com o `.env` da raiz contendo `DB_PASSWORD=outra`, `make up-shared` deixa o arquivo byte a byte igual (AC 4)
Proof: run infra | PASS C2 up-shared keeps existing env

**C5** - Com `REGISTRATION_MAX_ATTEMPTS=2` e `OUTBOX_BATCH_SIZE=7` no `.env` da raiz, e depois com o `.env` completo do `.env.example` antigo na raiz, `docker compose config` da Laravel e do NestJS resolve `5` e `100` (AC 5)
Proof: run infra | PASS EV3 root env does not reach the stacks

**C6** - Não há `.env.example` em nenhum diretório, e `git check-ignore` ignora `.env` na raiz, em `apis/laravel` e em `apis/nestjs` (AC 6)
Proof: run infra | PASS EV4 no env example and env ignored in every project

### S2 - `cadastro-feliz-laravel` com padrões próprios

**C7** - Numa cópia sem nenhum `.env`, `make up-laravel` sai com `0`, `GET /health` responde `200`, e não existe arquivo `.env` (AC 7)
Proof: run infra | PASS LV1 up-laravel on clean clone

**C8** - Sem nenhum `.env`, `php-fpm`, `scheduler` e `horizon` têm `APP_ENV=local`, `APP_DEBUG=true`, `APP_KEY` com `base64:` e 32 bytes, `OUTBOX_RETENTION_DAYS=7`, `OUTBOX_ALERT_EMAIL=ops@cadastro-feliz.local` e `CORS_ALLOWED_ORIGIN` com a origem HTTP de `localhost:3000` (AC 8)
Proof: run infra | PASS LV11 laravel containers receive the compose defaults

**C9** - Com `REGISTRATION_MAX_ATTEMPTS=2` em `apis/laravel/.env`, duas tentativas com e-mail já cadastrado respondem `409` e a terceira `429`, e `docker compose config` do NestJS resolve `5` (AC 9)
Proof: run infra | PASS EV5 laravel env override stays in laravel

**C10** - Com `apis/laravel/.env` contendo `PROBE_ONLY_IN_FILE=1` no build, a imagem do `php-fpm` não tem `/var/www/html/.env`, `printenv` do `php-fpm` não tem `PROBE_ONLY_IN_FILE`, e `GET /health` responde `200` (AC 10)
Proof: run infra | PASS EV6 laravel image leaves out the stack env file

### S3 - `cadastro-feliz-nest` com padrões próprios

**C11** - Numa cópia sem nenhum `.env`, `make up-nest` sai com `0`, `GET /health` responde `200`, e não existe arquivo `.env` (AC 11)
Proof: run infra | PASS NS1 up-nest on clean clone

**C12** - Com `OUTBOX_BATCH_SIZE=2` em `apis/nestjs/.env`, o `worker` tem `OUTBOX_BATCH_SIZE=2` e `docker compose config` da Laravel resolve `100` (AC 12)
Proof: run infra | PASS EV7 nest env override stays in nest

**C13** - Com `REGISTRATION_MAX_ATTEMPTS=2` em `apis/laravel/.env`, `make up-nest` deixa a `api` com `REGISTRATION_MAX_ATTEMPTS=5` (AC 13)
Proof: run infra | PASS EV8 laravel env does not reach nest

### S4 - Regras que valem para todo projeto

**C14** - Numa cópia sem nenhum `.env` e com o ambiente do shell limpo, `docker compose config` de cada um dos três composes não avisa variável ausente e não tem valor vazio em `environment`, `ports` e `command` (AC 14)
Proof: run infra | PASS EV9 every compose resolves its variables without env files

**C15** - Um compose com `${OUTBOX_BATCH_SIZE}` sem padrão faz a verificação falhar com uma linha que nomeia `apis/nestjs/docker-compose.yml` e `OUTBOX_BATCH_SIZE`, também com `OUTBOX_BATCH_SIZE` exportado no shell; os três composes reais passam (AC 15)
Proof: run infra | PASS EV10 a variable without default is named

**C16** - O padrão de cada `REGISTRATION_*` e `OUTBOX_*` dos composes de stack é igual a docs/infrastructure.md › Regras de negócio, e os dois declaram os quatro `REGISTRATION_*` e os quatro `OUTBOX_*` comuns; `REGISTRATION_MAX_ATTEMPTS:-6` na Laravel falha nomeando `cadastro-feliz-laravel` e a variável; o NestJS sem `OUTBOX_RETENTION_DAYS` passa (AC 16)
Proof: run infra | PASS EV11 stack business rule defaults follow the docs

**C17** - docs/infrastructure.md › Variáveis de ambiente lista cada variável interpolada por algum compose, com o mesmo padrão e os projetos que a declaram, e cada variável listada é declarada por algum compose, exceto `RABBITMQ_URL`, de `go`; `DB_PASSWORD` aparece numa linha só com `shared`, `laravel` e `nest`, e um padrão diferente na doc falha (AC 17)
Proof: run infra | PASS EV12 docs list every compose variable with its default

**C18** - docs/decisions.md tem a decisão 29, com índice, a regra de door 1 e o que ela substitui; os três designs substituídos têm nota que aponta para ela; docs/infrastructure.md, docs/stacks.md e README não citam `.env.example` nem dizem que o `.env` da raiz é a única fonte (AC 18)
Proof: run infra | PASS EV13 decision 29 recorded and root env no longer the source

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| door 1 - projetos que sobem sem arquivo de ambiente (3) | `cadastro-feliz-shared` C1 C2 · `cadastro-feliz-laravel` C7 · `cadastro-feliz-nest` C11 | - |
| door 1 - composes com padrão em toda interpolação (3) | raiz C14 · Laravel C14 · NestJS C14, e o caso sem padrão C15 | - |
| door 1 - sobrescrita ao lado do compose (3) | raiz C3 C4 · `apis/laravel` C9 C10 · `apis/nestjs` C12 | - |
| door 1 - isolamento entre projetos (3 sentidos) | raiz -> stacks C5 · Laravel -> NestJS C9 C13 · NestJS -> Laravel C12 | - |
| door 1 - diretórios com `.env` ignorado e sem `.env.example` (3) | raiz C6 · `apis/laravel` C6 · `apis/nestjs` C6 | - |
| door 2 - sobrescrita fora da imagem (1) | `apis/laravel` C10; NestJS e frontend já excluem e não mudam | - |
| AC 5 examples (2) | `.env` parcial C5 · `.env` completo antigo C5 | - |
| AC 9 examples (2) | `409` nas duas primeiras C9 · `429` na terceira C9 | - |
| AC 10 examples (2) | variável só do arquivo C10 · `/health` `200` C10 | - |
| AC 15 examples (2) | sem padrão C15 · sem padrão e exportada no shell C15 | - |
| AC 16 examples (2) | padrão `6` falha C16 · NestJS sem `OUTBOX_RETENTION_DAYS` passa C16 | - |
| AC 17 examples (2) | `DB_PASSWORD` em três projetos, uma linha C17 · padrão divergente falha C17 | - |
| AC 8 containers Laravel, cada um com as 6 variáveis (3) | `php-fpm` C8 · `scheduler` C8 · `horizon` C8 | - |
| docs da decisão 29 (7 arquivos) | decisions.md C18 · shared-infrastructure C18 · frontend-container C18 · laravel-api-base C18 · infrastructure.md C17 C18 · stacks.md C18 · README C18 | - |
| leitores de `.env` em `tests/infra` reescritos (4) | C3 FE4 · C4 C2 · C7 LV1 · C8 LV11; os demais leitores do Changes underneath ficam provados pelo run infra inteiro verde | - |

## Swept

- validation: C14, C15, C16 - a variável sem padrão e o padrão divergente do contrato
- failure modes: C15 - a falha nomeia o compose e a variável
- idempotency: C4 - `make up-shared` repetido não muda um `.env` existente
- authorization: n/a - só ambiente local, sem caller externo
- concurrency: n/a - uma stack ativa por vez (decisão 6), e os alvos rodam em série
- data lifecycle: C5 - um `.env` antigo e completo continua funcionando e não é apagado
- dependency failure: n/a - nenhuma dependência nova; o Compose já interpola padrões
- state transitions: n/a - nenhum estado guardado muda
- observability: C15 - a falha do teste diz qual compose e qual variável

## Handoff

- **Settled mid-build:** none
- **Dispatched:** none
- **Boundary:** none yet
- **Abandoned:** none
