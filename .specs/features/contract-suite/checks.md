# Suíte de contrato por stack checks

Build: none - o repositório não tem build, lint nem type check para `tests/infra`; os arquivos são carregados por `run.sh`, e um erro de sintaxe derruba as provas abaixo
Run stack: `bash tests/infra/run.sh stack docs`
Run contract: `bash tests/infra/run.sh registration outbox laravel-outbox`
Plan: `.specs/features/contract-suite/plan.md`

20 checks in 3 slices · 3 one-way doors · 0 open, of which 0 block

## Checks

### S1 - Os casos de contrato rodam contra a stack escolhida

**C1** - `registration` contra a Laravel passa RG0 a RG21, RG23, RG25, RG26 e RG29 a RG33, com os nomes de hoje (AC 1)
Proof: run contract | PASS RG0 stack up for the registration tests
Proof: run contract | PASS RG1 post users created body
Proof: run contract | PASS RG2 post users normalizes and writes one event
Proof: run contract | PASS RG3 post users validation table
Proof: run contract | PASS RG4 post users malformed json
Proof: run contract | PASS RG5 invalid body touches nothing
Proof: run contract | PASS RG6 extra fields are ignored
Proof: run contract | PASS RG7 repeated email conflicts
Proof: run contract | PASS RG8 parallel same email
Proof: run contract | PASS RG9 attempt limit sequence
Proof: run contract | PASS RG10 attempt limit never reads the database
Proof: run contract | PASS RG11 forwarded for is ignored
Proof: run contract | PASS RG12 limit is per ip and email
Proof: run contract | PASS RG13 ip quota
Proof: run contract | PASS RG14 conflict does not consume quota
Proof: run contract | PASS RG15 ip quota holds in parallel
Proof: run contract | PASS RG16 lua scripts match the contract
Proof: run contract | PASS RG17 limiter down answers 500
Proof: run contract | PASS RG18 database down answers 500 and releases
Proof: run contract | PASS RG19 queue down still answers 201
Proof: run contract | PASS RG20 cors preflight
Proof: run contract | PASS RG21 cors response headers
Proof: run contract | PASS RG23 job carries only the event id
Proof: run contract | PASS RG25 worker survives queue restart
Proof: run contract | PASS RG26 mail arrives after smtp returns
Proof: run contract | PASS RG29 welcome mail arrives
Proof: run contract | PASS RG30 welcome mail text
Proof: run contract | PASS RG31 welcome mail has no external resources
Proof: run contract | PASS RG32 welcome mail escapes the name
Proof: run contract | PASS RG33 conflict sends no mail
Proof: run stack | PASS CS9 contract and internal ids are partitioned

**C2** - `outbox` contra a Laravel passa LM0, LM1, LM2, LM2B, LM3, OB1, OB2, OB4, OB5, OB6, OB15 a OB18, OB22 a OB25, OB27 a OB29, OB31 a OB33 e OB36 a OB38, com os nomes de hoje, exceto OB25, renomeado `events wait for the relay` (AC 2)
Proof: run contract | PASS LM0 stack up for the outbox tests
Proof: run contract | PASS LM1 queue down delays the mail
Proof: run contract | PASS LM2 stack down republishes the event
Proof: run contract | PASS LM2B stack down delivers pending events
Proof: run contract | PASS LM3 exhausted retries are recorded and recoverable
Proof: run contract | PASS OB1 registration writes a pending event
Proof: run contract | PASS OB2 payload keys and normalization
Proof: run contract | PASS OB4 outbox insert failure rolls back the user
Proof: run contract | PASS OB5 frozen queue still answers 201
Proof: run contract | PASS OB6 registration never connects to the queue
Proof: run contract | PASS OB15 relay publishes a pending event
Proof: run contract | PASS OB16 relay skips a future event
Proof: run contract | PASS OB17 relay republishes only expired events
Proof: run contract | PASS OB18 relay never selects terminal events
Proof: run contract | PASS OB22 relay resumes when the queue returns
Proof: run contract | PASS OB23 relay rollback after publish sends once
Proof: run contract | PASS OB24 message before commit ends processed
Proof: run contract | PASS OB25 events wait for the relay
Proof: run contract | PASS OB27 processed event and mail
Proof: run contract | PASS OB28 mail uses the payload name
Proof: run contract | PASS OB29 message id derives from the event
Proof: run contract | PASS OB31 terminal event message sends nothing
Proof: run contract | PASS OB32 missing event is ignored
Proof: run contract | PASS OB33 send failure schedules a retry
Proof: run contract | PASS OB36 frozen smtp counts as a failure
Proof: run contract | PASS OB37 worker holds no transaction during send
Proof: run contract | PASS OB38 database down keeps the event published
Proof: run stack | PASS CS9 contract and internal ids are partitioned

**C3** - `laravel-outbox` passa RG22, RG24, RG27, RG28, OB9, OB11, OB13, OB14, OB19, OB20, OB21, OB26, OB39, OB40 e OB41, e nenhum desses ids aparece em `registration.sh` ou `outbox.sh` (AC 3)
Proof: run contract | PASS RG22 queue redis config
Proof: run contract | PASS RG24 job has no native retries
Proof: run contract | PASS RG27 watch updates the worker
Proof: run contract | PASS RG28 horizon panel answers
Proof: run contract | PASS OB9 publisher class is gone
Proof: run contract | PASS OB11 outbox module does not reference users
Proof: run contract | PASS OB13 scheduler image and schedule list
Proof: run contract | PASS OB14 outbox config defaults in the scheduler
Proof: run contract | PASS OB19 relay batch output and order
Proof: run contract | PASS OB20 relay skips locked rows
Proof: run contract | PASS OB21 relay failure keeps events and logs
Proof: run contract | PASS OB26 watch updates the relay
Proof: run contract | PASS OB39 time limits keep their order
Proof: run contract | PASS OB40 frozen queue fails the relay fast
Proof: run contract | PASS OB41 scheduler publishes right after it starts
Proof: run stack | PASS CS9 contract and internal ids are partitioned

**C4** - `registration.sh`, `outbox.sh` e `registration-helpers.sh` não contêm `laravel`, `horizon`, `scheduler`, `php`, `artisan`, `nginx` nem `queues:`, em nenhuma caixa (AC 4)
Proof: run stack | PASS CS8 contract files name no stack

**C5** - Uma entrada de contrato imprime `== <arquivo>:<stack>` antes do primeiro caso, e uma entrada comum não imprime cabeçalho (AC 5)
Proof: run stack | PASS CS3 no arguments runs every entry in order
Proof: run contract | == registration:laravel
Proof: run contract | == outbox:laravel

**C6** - Um arquivo de contrato sem sufixo e sem `STACK` roda como `<arquivo>:laravel`, e `STACK=laravel` dá o mesmo (AC 6)
Proof: run stack | PASS CS4 contract file without suffix uses STACK or laravel

**C7** - `registration:go`, `STACK=nest` com `outbox` e `registration:rails` saem com `1` e `stack <nome> sem adaptador em tests/infra/adapters`, com o Docker inacessível, sem container, rede ou volume; `STACK=nest` com `docs` roda `docs` (AC 7)
Proof: run stack | PASS CS5 stack without adapter is refused before docker

**C8** - `docs:laravel` e `laravel-outbox:laravel` saem com `1` e `<arquivo> não é um arquivo de contrato`, com o Docker inacessível (AC 8)
Proof: run stack | PASS CS6 suffix on a common file is refused

**C9** - Um adaptador sem `stack_dispatch` faz `run.sh` sair com `1` e `adaptador <stack> sem stack_dispatch`, com o Docker inacessível; o adaptador da Laravel define todas as funções do vocabulário (AC 9)
Proof: run stack | PASS CS7 adapter missing a function is refused

**C10** - `run.sh --list` imprime exatamente `docs`, `shared`, `limiter`, `migrate`, `stack`, `frontend`, `test-frontend`, `laravel`, `registration:laravel`, `outbox:laravel`, `laravel-outbox`, uma por linha, com o Docker inacessível (AC 10)
Proof: run stack | PASS CS1 list prints every entry

**C11** - Com uma cópia do adaptador como `adapters/nest.sh`, `--list` imprime `registration:laravel`, `registration:nest`, `outbox:laravel`, `outbox:nest` nessa ordem, sem mudar `run.sh` (AC 11)
Proof: run stack | PASS CS2 a second adapter adds its entries

**C12** - `run.sh` sem argumentos roda cada entrada de `--list` na ordem, com a stack de cada entrada de contrato (AC 12)
Proof: run stack | PASS CS3 no arguments runs every entry in order

**C13** - `rg_set_env` muda o `.env` da cópia de trabalho e recria a stack escolhida, e `rg_default_env` volta os quatro `OUTBOX_*` padrão: LM3 só chega a `failed` com 2 tentativas, OB17 só republica com 5 s, e OB33, que roda depois deles, mede a espera padrão de 30 s (AC 13)
Proof: run contract | PASS LM3 exhausted retries are recorded and recoverable
Proof: run contract | PASS OB17 relay republishes only expired events
Proof: run contract | PASS OB33 send failure schedules a retry

### S2 - CI e documentos descrevem a suíte

**C14** - `.github/workflows/ci.yml` não muda nesta feature, e a matriz que ele lê de `--list` traz `registration:laravel` e `outbox:laravel` (AC 14)
Proof: `git diff --quiet fd704b8 -- .github/workflows/ci.yml`
Proof: run stack | PASS CS1 list prints every entry

**C15** - Em docs/infrastructure.md, a linha de `make test-infra` mostra `bash tests/infra/run.sh registration:laravel`, e a seção de CI diz que um arquivo de contrato roda uma vez por adaptador em `tests/infra/adapters` (AC 15)
Proof: run stack | PASS CS10 infrastructure describes the contract entries

**C16** - docs/decisions.md tem a linha `| [23](#23-suíte-de-contrato-por-stack) | Suíte de contrato por stack | Definida |`, e a seção 23 cita o adaptador, os ids iguais e a matriz de duas dimensões descartada (AC 16)
Proof: run stack | PASS CS11 decision 23 records the contract suite

**C17** - docs/stacks.md › Testes previstos em cada stack diz que toda stack é aceita pelos casos de contrato de `tests/infra` pelo próprio adaptador, e que os casos internos ficam num arquivo da stack (AC 17)
Proof: run stack | PASS CS12 stacks describe the contract suite

### S3 - Varredura

**C18** - Uma entrada de contrato com `STACK` vazio, como `STACK=` com `registration`, roda como `registration:laravel` em vez de recusar uma stack sem nome (validation)
Proof: run stack | PASS CS4 contract file without suffix uses STACK or laravel

**C19** - Um argumento desconhecido continua recusado com `arquivo de teste desconhecido: <nome>`, inclusive com sufixo, como `rails:laravel` (validation)
Proof: run stack | PASS CS6 suffix on a common file is refused

**C20** - Um caso de contrato que para o worker, o relay ou a fila e falha no meio devolve a stack ao ar antes do caso seguinte, como hoje: OB23, que para o worker, é seguido por OB24, que precisa dele (failure modes)
Proof: run contract | PASS OB24 message before commit ends processed

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| casos de contrato de `registration` (30) | RG0 C1 · RG1 C1 · RG2 C1 · RG3 C1 · RG4 C1 · RG5 C1 · RG6 C1 · RG7 C1 · RG8 C1 · RG9 C1 · RG10 C1 · RG11 C1 · RG12 C1 · RG13 C1 · RG14 C1 · RG15 C1 · RG16 C1 · RG17 C1 · RG18 C1 · RG19 C1 · RG20 C1 · RG21 C1 · RG23 C1 · RG25 C1 · RG26 C1 · RG29 C1 · RG30 C1 · RG31 C1 · RG32 C1 · RG33 C1 | - |
| casos de contrato de `outbox` (27) | LM0 C2 · LM1 C2 · LM2 C2 · LM2B C2 · LM3 C2 · OB1 C2 · OB2 C2 · OB4 C2 · OB5 C2 · OB6 C2 · OB15 C2 · OB16 C2 · OB17 C2 · OB18 C2 · OB22 C2 · OB23 C2 · OB24 C2 · OB25 C2 · OB27 C2 · OB28 C2 · OB29 C2 · OB31 C2 · OB32 C2 · OB33 C2 · OB36 C2 · OB37 C2 · OB38 C2 | - |
| casos internos da Laravel (15) | RG22 C3 · RG24 C3 · RG27 C3 · RG28 C3 · OB9 C3 · OB11 C3 · OB13 C3 · OB14 C3 · OB19 C3 · OB20 C3 · OB21 C3 · OB26 C3 · OB39 C3 · OB40 C3 · OB41 C3 | - |
| palavras proibidas nos arquivos de contrato (7) | `laravel` C4 · `horizon` C4 · `scheduler` C4 · `php` C4 · `artisan` C4 · `nginx` C4 · `queues:` C4 | - |
| vocabulário do adaptador, door 1 (22) | `stack_reset_queue` C9 · `stack_worker_stop` C9 · `stack_worker_start` C9 · `stack_relay_stop` C9 · `stack_relay_start` C9 · `stack_queue_stop` C9 · `stack_queue_start` C9 · `stack_queue_freeze` C9 · `stack_queue_unfreeze` C9 · `stack_queue_up_alone` C9 · `stack_queue_length` C9 · `stack_queued_messages` C9 · `stack_queue_connections` C9 · `stack_jobs_created` C9 · `stack_failed_jobs` C9 · `stack_dispatch` C9 · `stack_api_errors_since` C9 · `stack_worker_logs_since` C9 · `stack_relay_container` C9 · `stack_lua_dir` C9 · `stack_post_from_other_ip` C9 · `stack_wait_ready` C9 | - |
| formato das entradas, door 2 (3) | `<arquivo>` C10 · `<arquivo>:<stack>` C10, C11 · ordem por stack C11 | - |
| ids iguais, door 3 (2) | id sem a stack C1, C2 · cabeçalho `== <arquivo>:<stack>` C5 | - |
| recusas de `run.sh`, AC 7 a AC 9 (8) | `registration:go` C7 · `STACK=nest` + `outbox` C7 · `registration:rails` C7 · `STACK=nest` + `docs` roda C7 · `docs:laravel` C8 · `laravel-outbox:laravel` C8 · sem `stack_dispatch` C9 · todas as funções C9 | - |
| escolha da stack, AC 6 (3 exemplos) | sem `STACK` C6 · `STACK=laravel` C6 · `STACK=` vazio C18 | - |
| documentos (3) | docs/infrastructure.md C15 · docs/decisions.md C16 · docs/stacks.md C17 | - |

## Swept

- validation: C7, C8, C9, C18, C19
- failure modes: C20; existing - cada caso de hoje já devolve o serviço que parou antes de retornar, e os casos movidos mantêm isso
- idempotency: n/a - `run.sh` recria o ambiente a cada entrada, como hoje
- authorization: n/a - nenhuma rota ou permissão muda
- concurrency: existing - RG8, RG15 e OB20 continuam provando as corridas; `run.sh` roda as entradas uma de cada vez, como hoje
- data lifecycle: existing - `destroy_environment` antes de cada entrada e no `trap` de saída, sem mudança
- dependency failure: C7, C8, C9 recusam antes do Docker; existing - a recusa de Docker inacessível e de ambiente existente continua
- state transitions: n/a - nenhum estado persistido muda
- observability: C5, o cabeçalho de cada entrada de contrato diz contra qual stack os ids rodaram

## Handoff

- **Settled mid-build:** OB25 muda só o nome, para `events wait for the relay`, porque o AC 4 proíbe `scheduler` nos arquivos de contrato - user: "Renomear para relay (Recommended)"
- **Dispatched:** Verifier at `13fb55a` (proofs 97 pass, 0 fail)
- **Boundary:** C1-C20 closed at `13fb55a`
- **Abandoned:** none
- **Note:** a primeira rodada do `check_proofs.py`, em 08517fe, deu 89 pass e 9 fail: LM2, LM3, OB17, OB19 e OB38 porque `rg_set_env` usava `sed -i`, que no macOS espera um sufixo e não mudava o `.env`, e OB26 pelo mesmo `sed -i`. As duas trocas viraram `sed` com arquivo temporário. C16 e C17 de `stack.sh` só passam no macOS com um `timeout` no `PATH`, que o GNU coreutils dá no CI; as provas locais rodam com um substituto em Perl fora do repositório
