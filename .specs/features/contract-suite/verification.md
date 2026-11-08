# Contract suite verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at 13fb55a (HEAD 64e027e differs from it only in `checks.md`)
**Verifier**: independent sub-agent (author != verifier)

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | `registration.sh` `RG0` to `RG33` (the 30 contract ids), and `stack.sh` `CS9 contract and internal ids are partitioned` | yes - each case, compared with `fd704b8:tests/infra/registration.sh`, asserts the same values; only the mechanism moved to the adapter (RG7 `stack_jobs_created`, RG12 `stack_post_from_other_ip`, RG16 `stack_lua_dir`, RG19 `stack_api_errors_since`), and each adapter function does what the inline code did |
| C2 | `outbox.sh` `LM0` to `OB38` (the 27 contract ids), and `stack.sh` `CS9 contract and internal ids are partitioned` | yes - same values as `fd704b8:tests/infra/outbox.sh`; LM1, OB22 and OB25 now count the 60 s deadline from before the restart and the health wait, slightly stricter, never looser; OB25 renamed as the plan says |
| C3 | `laravel-outbox.sh` `RG22`, `RG24`, `RG27`, `RG28`, `OB9`, `OB11`, `OB13`, `OB14`, `OB19`, `OB20`, `OB21`, `OB26`, `OB39`, `OB40`, `OB41`, and `stack.sh` `CS9 contract and internal ids are partitioned` | yes - bodies identical to `fd704b8` except OB26 dropping `sed -i`; CS9 fixes the exact id set per file, and no internal id appears anywhere in the contract files |
| C4 | `stack.sh` `CS8 contract files name no stack` | yes - case-insensitive grep of the seven words plus the `RG_*` container names |
| C5 | `stack.sh` `CS3 no arguments runs every entry in order`, and the `== registration:laravel` / `== outbox:laravel` lines of the contract run | yes - CS3 compares the whole output, so a header on a common entry would fail it |
| C6 | `stack.sh` `CS4 contract file without suffix uses STACK or laravel` | yes |
| C7 | `stack.sh` `CS5 stack without adapter is refused before docker` | yes on the four plan examples - exact message and exit 1 with an unreachable Docker; see the finding on names that differ only in case |
| C8 | `stack.sh` `CS6 suffix on a common file is refused` | yes |
| C9 | `stack.sh` `CS7 adapter missing a function is refused` | no - proves the refusal for `stack_dispatch` only; dropping any of the other 21 names from `ADAPTER_FUNCTIONS` in `run.sh` fails no test |
| C10 | `stack.sh` `CS1 list prints every entry` | yes - exact list |
| C11 | `stack.sh` `CS2 a second adapter adds its entries` | yes |
| C12 | `stack.sh` `CS3 no arguments runs every entry in order` | yes |
| C13 | `outbox.sh` `LM3 exhausted retries are recorded and recoverable`, `OB17 relay republishes only expired events`, `OB33 send failure schedules a retry` | yes - LM3 cannot reach `failed` with 2 attempts in 60 s unless `.env` changed; OB17 first asserts no republish at 300 s after LM2's change; OB33 asserts 15-30 s and 220-240 s, which fails if `BACKOFF` or `MAX_ATTEMPTS` were not restored |
| C14 | `git diff --quiet fd704b8 -- .github/workflows/ci.yml`, and `stack.sh` `CS1 list prints every entry` | yes |
| C15 | `docs.sh` `CS10 infrastructure describes the contract entries` | yes |
| C16 | `docs.sh` `CS11 decision 23 records the contract suite` | yes |
| C17 | `docs.sh` `CS12 stacks describe the contract suite` | yes |
| C18 | `stack.sh` `CS4 contract file without suffix uses STACK or laravel` | yes |
| C19 | `stack.sh` `CS6 suffix on a common file is refused` | yes - `rails:laravel` |
| C20 | `outbox.sh` `OB24 message before commit ends processed` | no - OB24 passing only shows OB23 succeeded; no failure path runs, and OB22 does leave the queue stopped when it fails mid-way |
| C21 | `stack.sh` `CS5 stack without adapter is refused before docker` | appended by the builder from finding 3, after this verification; not judged by the Verifier |

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| A contract case that fails mid-way can leave the queue stopped for the next case, which C20 claims cannot happen | `outbox.sh:286` and `:288` - after `stack_queue_stop`, a non-201 POST or an event that is not `pending` makes `t_ob22_resumes` `return 1` before `stack_queue_start`, so OB23 and later run with the queue down (same in `fd704b8`, but C20 asserts the opposite and its proof, OB24 PASS, never exercises a failure) | in OB22 record the failure in `ok` and always run `stack_queue_start` and `stack_wait_ready` before returning; prove C20 with a test that greps the contract files for a `return 1` between a stop and its start, or drop the claim | 4d546c6 - OB22 anota a falha e religa a fila antes de retornar; C20 agora provado por CS13, que acusa um `t_<caso>` que retorna com algo parado |
| C9 proves the adapter-vocabulary refusal on 1 of its 22 functions; the Coverage table credits C9 with all 22 | `stack.sh` `t_cs7_adapter_functions` removes only `stack_dispatch`, and its list of 22 checks the Laravel adapter, not `ADAPTER_FUNCTIONS` in `run.sh`; deleting e.g. `stack_wait_ready` from `ADAPTER_FUNCTIONS` keeps CS7 green while a new adapter without it passes `run.sh` and breaks at runtime | in CS7, for each name of the door-1 list, build a copy of the adapter without that function and assert `adaptador fake sem <função>` | 4d546c6 - CS7 tira cada uma das 22 funções, uma de cada vez, e exige `adaptador fake sem <função>`; C9 provado por ela |
| On macOS a stack name that differs from an adapter only in case, or a path to one, passes the AC 7 refusal and reaches Docker | throwaway runs at HEAD with `DOCKER_HOST=unix:///nonexistent`: `run.sh registration:Laravel`, `STACK=Laravel run.sh registration` and `run.sh 'registration:../adapters/laravel'` print `O Docker não está acessível` instead of `stack <nome> sem adaptador em tests/infra/adapters`; with Docker up they would destroy the environment, print `== registration:Laravel` and fail every case on `make up-Laravel`. `run.sh` resolves with `[ -f "$TESTS/adapters/$stack.sh" ]` on a case-insensitive filesystem | accept a stack only when it is an exact line of `adapter_stacks` (the same names `--list` prints), and add `registration:Laravel` to CS5 | 4d546c6 - `run.sh` só aceita o nome exato de uma stack de `--list`; CS5 recusa `registration:Laravel`, `STACK=Laravel` e `registration:../adapters/laravel`; C21 provado por ela |
