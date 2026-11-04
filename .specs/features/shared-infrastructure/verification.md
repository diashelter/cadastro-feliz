# Infraestrutura dos serviços comuns verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at 67153a6
**Verifier**: independent sub-agent (author != verifier)

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | `tests/infra/shared.sh` `t_c1_clean_clone` | yes - starts with no `.env`, network or volume; asserts exit 0, `cmp` with `.env.example`, network present and the three `cadastro-feliz-shared-*-1` containers `healthy` |
| C2 | `tests/infra/shared.sh` `t_c2_keeps_env` | yes for the claim (`DB_PASSWORD=outra` survives); looser than AC 2, which fixes the whole file as unchanged |
| C3 | `tests/infra/shared.sh` `t_c3_rerun` | yes - exactly 3 IDs before, same sorted IDs after, exit code checked |
| C4 | `tests/infra/shared.sh` `t_c4_login` | yes - `psql` on host network to `localhost:5432` with the fixed user, password and database, expects `1` |
| C5 | `tests/infra/shared.sh` `t_c5_ports` | yes - host ports of the project's containers equal `5432,8025`; `redis-limiter:6379` PONG and `mailpit:1025` reachable from `cadastro-feliz-net` |
| C6 | `tests/infra/shared.sh` `t_c6_redis_config` | yes - `CONFIG GET` equals `33554432`, `volatile-ttl`, empty, `no` |
| C7 | `tests/infra/shared.sh` `t_c7_images` | yes - `config --images` over all profiles equals the four pinned tags exactly |
| C8 | `tests/infra/shared.sh` `t_c8_taken_port` (8025 and 5432) | yes - blocker container on each port, asserts non-zero exit |
| C9 | `tests/infra/shared.sh` `t_c9_env_example` | yes - parses the docs tables, requires 22 rows, each `VAR=default` an exact line of `.env.example` |
| C10 | `tests/infra/migrate.sh` `t_c10_migration_file` | yes - first/last non-blank lines `BEGIN;`/`COMMIT;`, body string-equal to the `## Schema` sql block (which the diff did not touch) |
| C11 | `tests/infra/migrate.sh` `t_c11_empty_database` | yes - runs from no containers and no volume; 4 constraints, FK by column, 3 indexes, `1 f`, exit 0 |
| C12 | `tests/infra/migrate.sh` `t_c12_rerun` | yes - exit 0, `1 f`, `pg_dump --schema-only` identical |
| C13 | `tests/infra/migrate.sh` `t_c13_starts_shared` | no - `make down` keeps the postgres volume, so `1 f` from C11 is already there; passes when `make migrate` applies nothing |
| C14 | `tests/infra/migrate.sh` `t_c14_failed_migration` | yes - non-zero exit, `probe` absent, `2 t` |
| C15 | `tests/infra/migrate.sh` `t_c15_down` | yes - after `migrate down 1` neither `users_outbox` nor `users` exists |
| C16 | `tests/infra/stack.sh` `t_c16_missing_stack` | yes - all 9 target x stack pairs: non-zero exit and message; network absent and no container afterwards |
| C17 | `tests/infra/stack.sh` `t_c17_unknown_stack` | yes - `up-`, `down-`, `logs-rails`: non-zero exit, message, nothing created |
| C18 | `tests/infra/stack.sh` `t_c18_up_stack` | yes - fake stack only turns healthy after reading `users`, so order is proven; network created, shared healthy |
| C19 | `tests/infra/stack.sh` `t_c19_switch` | yes - no `cadastro-feliz-nest` container after `up-go` (and the reverse), target stack healthy |
| C20 | `tests/infra/stack.sh` `t_c20_failed_migrate` | yes - broken 0002, non-zero exit, no `cadastro-feliz-go` container |
| C21 | `tests/infra/stack.sh` `t_c21_down_stack` | yes - stack containers and `queue-data` volume gone; shared healthy, limiter key and `users` row kept |
| C22 | `tests/infra/stack.sh` `t_c22_down` | yes - no `cadastro-feliz-*` container, no network, postgres volume kept; row survives, key gone after `up-shared` |
| C23 | `tests/infra/shared.sh` `t_c23_reset_limits` | yes - key present before, exit 0, `DBSIZE` `0` |
| C24 | `tests/infra/shared.sh` `t_c24_status` | yes for the claim (each shared container with `running`); looser than AC 24, which covers every `cadastro-feliz-*` project - runs before any stack exists |
| C25 | `tests/infra/shared.sh` `t_c25_logs` | yes for the claim (line shown); looser than AC 25 - does not assert the logs are followed |
| C26 | `tests/infra/docs.sh` `t_c26_decision` | yes - index row with `Proposta`, section has format, `BEGIN;`, `COMMIT;`, `dirty`, `force` |
| C27 | `tests/infra/docs.sh` `t_c27_existing_files` | yes - no sentence names the files with a negation; the four targets listed under `## Makefile` |
| C28 | `tests/infra/docs.sh` `t_c28_database_docs` | yes - `## Migrations` has `golang-migrate`, `NNNN_<nome>.up.sql`, `force` |
| C29 | `tests/infra/stack.sh` `t_c29_status_stack` | yes - appended after the Verifier round to close the C24 finding; asserts `cadastro-feliz-go-api-1` and `postgres` `running` with the stack up |

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| C13 passes even when `make migrate` with the shared services down applies nothing | `tests/infra/migrate.sh:53-59` - `make down` keeps `cadastro-feliz-shared_postgres-data`, so `1 f` written by C11 is still there; at HEAD with the `migrate` recipe replaced by `true`, the test's steps (down, no containers, migrate exit 0, healthy, `1 f`) all pass | after `make down` also `docker volume rm cadastro-feliz-shared_postgres-data` (or assert `users` absent before), so `make migrate` must start the services on an empty database and apply 0001 |  `4473a0c` - volume removed after `make down`; C13 killed the `true` mutant |
| C25 does not hold "acompanhar" (`--follow`) from AC 25 | `tests/infra/shared.sh:180-185` - only greps the output; at HEAD with `logs --follow` changed to `logs`, `timeout 15 make logs-shared` exits 0 at once and still prints `database system is ready to accept connections` | also assert the exit code is `124`, i.e. the command was still following when `timeout` stopped it |  `4473a0c` - asserts exit `124`; C25 killed the `logs` without `--follow` mutant |
| C2 asserts one line where AC 2 fixes the whole `.env` as unchanged | `tests/infra/shared.sh:205-209` - `grep -qx 'DB_PASSWORD=outra'`; a Makefile that appended or rewrote other lines of `.env` would pass | copy `.env` before `make up-shared` and `cmp` it after |  `4473a0c` - `cmp` of the whole `.env` before and after; C2 |
| C24 proves `make status` on the shared project only; AC 24 says every container of the `cadastro-feliz-*` projects | `tests/infra/shared.sh:188-194` runs in `shared.sh`, before any stack exists; a `status` filtered to `label=com.docker.compose.project=cadastro-feliz-shared` would pass | in `stack.sh`, with the fake `go` stack up, assert `make status` shows `cadastro-feliz-go-api-1` with `running` |  `4473a0c` - appended C29, run in `stack.sh` with the `go` stack up |
