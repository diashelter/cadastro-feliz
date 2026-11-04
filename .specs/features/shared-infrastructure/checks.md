# Infraestrutura dos serviços comuns checks

Build: none - o repositório não tem build, lint nem type check; o compose e o Makefile são exercidos pelas provas
Run infra: `make test-infra`
Plan: `.specs/features/shared-infrastructure/plan.md`

29 checks in 4 slices · 4 one-way doors · 0 open, of which 0 block

## Checks

### S1 - Serviços comuns saudáveis

**C1** - `make up-shared` em clone limpo cria `.env` idêntico a `.env.example`, cria `cadastro-feliz-net`, deixa `postgres`, `redis-limiter` e `mailpit` `healthy` e sai com `0` (AC 1)
Proof: run infra | PASS C1 up-shared clean clone

**C2** - Com `.env` contendo `DB_PASSWORD=outra`, `make up-shared` mantém `outra` (AC 2)
Proof: run infra | PASS C2 up-shared keeps existing env

**C3** - Segundo `make up-shared` com tudo no ar mantém os três IDs de container e sai com `0` (AC 3)
Proof: run infra | PASS C3 up-shared rerun keeps containers

**C4** - `psql` em `localhost:5432` como `cadastro_feliz`/`cadastro_feliz` no banco `cadastro_feliz` responde `select 1` (AC 4)
Proof: run infra | PASS C4 postgres login from host

**C5** - As portas publicadas na máquina pelo projeto `cadastro-feliz-shared` são exatamente {5432, 8025}, e `redis-limiter:6379` e `mailpit:1025` respondem de dentro de `cadastro-feliz-net` (AC 5)
Proof: run infra | PASS C5 published ports and network ports

**C6** - `CONFIG GET` no `redis-limiter` devolve `maxmemory` `33554432`, `maxmemory-policy` `volatile-ttl`, `save` vazio e `appendonly` `no` (AC 6)
Proof: run infra | PASS C6 redis-limiter config

**C7** - As imagens do compose comum são exatamente `postgres:18.6-alpine`, `redis:8.10.3-alpine`, `axllent/mailpit:v1.33.0` e `migrate/migrate:v4.20.1` (AC 7)
Proof: run infra | PASS C7 pinned images

**C8** - Com a porta `8025`, e depois a `5432`, ocupada por outro container, `make up-shared` sai com código diferente de zero (AC 8)
Proof: run infra | PASS C8 up-shared fails on taken port 8025
Proof: run infra | PASS C8 up-shared fails on taken port 5432

**C9** - `.env.example` tem as 22 variáveis de `docs/infrastructure.md` › Variáveis de ambiente, cada uma com o padrão da tabela (AC 9)
Proof: run infra | PASS C9 env example matches docs

### S2 - Schema aplicado pelo migrate

**C10** - `0001_create_users_and_users_outbox.up.sql` é `BEGIN;`, o bloco SQL de `docs/database.md` › Schema sem alteração e `COMMIT;` (AC 10)
Proof: run infra | PASS C10 migration 0001 equals docs schema

**C11** - `make migrate` em banco vazio cria as 4 constraints nomeadas, a FK `users_outbox.user_id -> users.id` e os 3 índices, grava versão `1` com `dirty = false` e sai com `0` (AC 11)
Proof: run infra | PASS C11 migrate on empty database

**C12** - Segundo `make migrate` sai com `0`, mantém a versão `1` e o `pg_dump --schema-only` fica idêntico (AC 12)
Proof: run infra | PASS C12 migrate rerun changes nothing

**C13** - Com os comuns fora do ar, `make migrate` os sobe saudáveis, aplica a versão `1` e sai com `0` (AC 13)
Proof: run infra | PASS C13 migrate starts shared services

**C14** - Com uma `0002` que cria `probe` e depois falha, `make migrate` sai com código diferente de zero, `probe` não existe e `schema_migrations` tem versão `2` com `dirty = true` (AC 14)
Proof: run infra | PASS C14 failed migration rolls back and marks dirty

**C15** - `migrate down 1` remove `users_outbox` e `users` (AC 15)
Proof: run infra | PASS C15 migration 0001 down drops both tables

### S3 - Troca de stack pelo Makefile

**C16** - Para cada um de `up-`, `down-` e `logs-` com `laravel`, `nest` e `go` sem compose, o `make` imprime `stack <nome> ainda não implementada`, sai com código diferente de zero, a rede continua ausente e nenhum container existe (AC 16)
Proof: run infra | PASS C16 missing stack refused

**C17** - `make up-rails`, `make down-rails` e `make logs-rails` imprimem `stack rails desconhecida`, saem com código diferente de zero e não alteram nada (AC 17)
Proof: run infra | PASS C17 unknown stack refused

**C18** - Sem a rede, `make up-go` com um compose de stack cujo container só fica `healthy` se `users` já existe sai com `0`, cria a rede e deixa a stack `healthy` (AC 18)
Proof: run infra | PASS C18 up-stack runs shared and migrate first

**C19** - Com `nest` no ar, `make up-go` não deixa nenhum container de `cadastro-feliz-nest` e deixa `cadastro-feliz-go` no ar (AC 19)
Proof: run infra | PASS C19 up-stack takes other stacks down

**C20** - Com uma migration quebrada, `make up-go` sai com código diferente de zero e não existe nenhum container de `cadastro-feliz-go` (AC 20)
Proof: run infra | PASS C20 up-stack stops when migrate fails

**C21** - `make down-go` remove containers e volume da stack e mantém os comuns no ar, a chave do `redis-limiter` e a linha em `users` (AC 21)
Proof: run infra | PASS C21 down-stack keeps shared data

**C22** - `make down` remove os containers de todos os projetos `cadastro-feliz-*` e a rede, mantém o volume `cadastro-feliz-shared_postgres-data`; depois de `make up-shared` a linha em `users` continua e a chave do `redis-limiter` sumiu (AC 22)
Proof: run infra | PASS C22 down keeps only postgres volume

**C23** - Com `registration:attempts:abc` gravada, `make reset-limits` sai com `0` e deixa `DBSIZE` `0` (AC 23)
Proof: run infra | PASS C23 reset-limits empties limiter

**C24** - `make status` sai com `0` e mostra, para cada container comum, o nome e o estado `running` na mesma linha (AC 24)
Proof: run infra | PASS C24 status lists containers

**C25** - `make logs-shared` mostra `database system is ready to accept connections` (AC 25)
Proof: run infra | PASS C25 logs-shared follows logs

**C29** - Com a stack `go` no ar, `make status` mostra `cadastro-feliz-go-api-1` e o `postgres` comum, cada um com o estado `running` na linha (AC 24)
Proof: run infra | PASS C29 status lists stack containers

### S4 - Documentação alinhada

**C26** - `docs/decisions.md` tem a decisão `15. golang-migrate como ferramenta de migrations`, com origem `Proposta` no índice, `NNNN_<nome>.up.sql`, `BEGIN;`, `COMMIT;`, *dirty* e `force` (AC 26)
Proof: run infra | PASS C26 decision 15 recorded

**C27** - Nenhuma linha de `README.md` ou `docs/infrastructure.md` diz que `Makefile`, `docker-compose.yml` ou `.env.example` não existe ou é planejado, e `docs/infrastructure.md` › Makefile lista `make up-shared`, `make migrate`, `make logs-shared` e `make test-infra` (AC 27)
Proof: run infra | PASS C27 docs describe existing files

**C28** - `docs/database.md` › Migrations cita golang-migrate, `NNNN_<nome>.up.sql` e `force` (AC 28)
Proof: run infra | PASS C28 database docs name the tool

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| serviços comuns de longa duração (3) | `postgres` C1 · `redis-limiter` C1 · `mailpit` C1 | - |
| imagens fixadas (4) | `postgres:18.6-alpine` C7 · `redis:8.10.3-alpine` C7 · `axllent/mailpit:v1.33.0` C7 · `migrate/migrate:v4.20.1` C7 | - |
| portas publicadas (2) | `5432` C5 · `8025` C5 | - |
| portas só na rede (2) | `redis-limiter:6379` C5 · `mailpit:1025` C5 | - |
| porta ocupada, AC 8 (2) | `8025` C8 · `5432` C8 | - |
| configuração do `redis-limiter` (4) | `maxmemory` C6 · `maxmemory-policy` C6 · `save` C6 · `appendonly` C6 | - |
| variáveis de ambiente (22) | C9, table-driven over all 22 parsed from `docs/infrastructure.md` | - |
| objetos do schema (8) | `users_email_unique` C11 · `users_email_lowercase` C11 · `users_outbox_status_valid` C11 · `users_outbox_attempts_positive` C11 · FK `user_id` C11 · `users_outbox_user_id_index` C11 · `users_outbox_pending_index` C11 · `users_outbox_published_index` C11 | - |
| entidades (3) | `users` C11 · `users_outbox` C11 · `schema_migrations` C11, C14 | - |
| recusa de stack sem compose (9) | C16, table-driven over all 9 (`up`/`down`/`logs` × `laravel`/`nest`/`go`) | - |
| recusa de stack desconhecida (3) | `up-rails` C17 · `down-rails` C17 · `logs-rails` C17 | - |
| comandos do Makefile (9) | `up-shared` C1 · `migrate` C11 · `up-<stack>` C18 · `down-<stack>` C21 · `down` C22 · `status` C24, C29 · `logs-shared` C25 · `logs-<stack>` C16 · `reset-limits` C23 · `test-infra` - is the run itself | - |
| ciclo de vida em `make down` (3) | PostgreSQL mantém C22 · contadores descartados C22 · containers removidos C22 | - |
| ciclo de vida em `make down-<stack>` (3) | fila descartada C21 · contadores mantidos C21 · PostgreSQL mantém C21 | - |
| door 1: ferramenta de migrations (4) | formato e `BEGIN;`/`COMMIT;` C10 · `schema_migrations` C11 · falha atômica C14 · down C15 | - |
| door 2: rede externa (2) | criada pelo Makefile C1, C18 · removida por `make down` C22 | - |
| door 3: nome curto -> diretório -> projeto (3) | `nest` -> `apis/nestjs` C19 · `go` -> `apis/golang` C18 · `laravel` -> `apis/laravel` C16 | - |
| door 4: volume do PostgreSQL (1) | sobrevive a `make down` C22 | - |

## Swept

- validation: C16, C17
- failure modes: C14, C20, C8
- idempotency: C3, C12
- authorization: n/a - ambiente local de uma pessoa; a senha do banco é provada por C4
- concurrency: n/a - os comandos são rodados por uma pessoa por vez; `make` não é chamado em paralelo
- data lifecycle: C21, C22
- dependency failure: C13, C20
- state transitions: C14
- observability: C24, C25

## Handoff

- **Settled mid-build:** none
- **Dispatched:** Verifier at `67153a6`, returned (no screens sub-agent: no criterion cites a capture)
- **Boundary:** C1-C25 closed at `ccc1cb8`; C26-C28 closed at `96af70a`
- **Abandoned:** comparar `pg_dump` cru em C12 - o pg_dump 18 sorteia a chave de `\restrict` a cada execução; o teste fixa `--restrict-key`. Grep por linha em C27 - acusava frases corretas ("se ele não existir"); o teste julga por frase
