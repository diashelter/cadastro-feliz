# Stack NestJS com Transactional Outbox checks

Build: none - a NestJS não existe antes da mudança; o type check dela roda dentro de `make test-nest` (`tsc --noEmit` antes do Vitest, como `make test-frontend`), provado por C22
Run nest: `make test-nest`
Run infra: `bash tests/infra/run.sh`
Run contract: `bash tests/infra/run.sh registration:nest outbox:nest`
Plan: `.specs/features/nestjs-stack/plan.md`

50 checks in 8 slices · 8 one-way doors · 0 open, of which 0 block

## Checks

### S1 - Stack no ar e `GET /health`

**C1** - `make up-nest` num clone limpo deixa só `api`, `worker` e `redis` em `cadastro-feliz-nest`, todos `healthy`, com a outra stack derrubada; rodar de novo mantém os 3 IDs (AC 1)
Proof: run infra | PASS NS1 up-nest on clean clone

**C2** - Só a `api` publica porta, a 8080 da máquina, e `api` e `worker` usam a mesma imagem (AC 2)
Proof: run infra | PASS NS2 nest published ports and shared image

**C3** - `GET /health` com tudo no ar responde `200` com o corpo exato, `Content-Type: application/json` e `Cache-Control: no-store`, sem mudar `users` nem `users_outbox` (AC 3)
Proof: run infra | PASS NS3 health ok with real dependencies

**C4** - Com `postgres`, `redis-limiter` ou os dois parados, `/health` responde `503` em menos de 3 s, com `fail` em cada check que falhou e os mesmos headers, e a `api` continua `healthy` (AC 4)
Proof: run infra | PASS NS4 health 503 when dependencies stop

**C5** - Com `postgres` ou `redis-limiter` pausado, `/health` responde `503` em menos de 3 s (AC 5)
Proof: run infra | PASS NS5 health gives up on paused dependency

**C6** - Um check que falha deixa o motivo no log da `api`, e o corpo só tem `status` e `checks`, com valores `ok` e `fail` (AC 6)
Proof: run infra | PASS NS6 failed check is logged not returned

**C7** - A `api` responde só a `GET /health`, `POST /users` e `OPTIONS /users`; `/api/health` dá `404`, e `/nada` e `/` dão `404` JSON (AC 7)
Proof: run infra | PASS NS7 api routes are health and users

**C8** - `make up-nest` sobre um banco migrado deixa `pg_dump --schema-only` idêntico, arquivo inteiro, e `apis/nestjs` não tem migration do TypeORM (AC 8)
Proof: run infra | PASS NS8 schema untouched by the stack

**C9** - Com o `redis` da stack parado, `/health` dá `200` e `POST /users` dá `201`; com ele de volta, o `worker` fica `healthy` em até 60 s, com o mesmo ID e `RestartCount` `0` (AC 9)
Proof: run infra | PASS NS9 stack queue down keeps the api up

**C10** - Enquanto a `api` atende `/health` e `POST /users`, `CLIENT LIST` do `redis` da stack não tem cliente do IP da `api` (AC 10)
Proof: run infra | PASS NS10 api never connects to the stack queue

**C11** - `make up-nest` sai com erro quando `src/main.ts` não inicia e quando a porta 8080 está ocupada (AC 11)
Proof: run infra | PASS NS11 up-nest fails when the api does not boot
Proof: run infra | PASS NS12 up-nest fails on taken port 8080

**C12** - `make up-laravel` e `make down` com a NestJS no ar não deixam container nem volume de `cadastro-feliz-nest` (AC 12)
Proof: run infra | PASS NS13 nest leaves on switch and down

**C13** - Um corpo JSON válido que não é objeto responde `422` com o corpo de RG4, sem consultar o banco nem contar tentativa (AC 13)
Proof: run infra | PASS NS14 non-object json answers 422

### S2 - Edição, dependências e testes unitários

**C14** - Com `make watch-nest`, a edição de um arquivo da `api` vale na requisição seguinte em até 30 s, com o mesmo ID da `api` (AC 14)
Proof: run infra | PASS NS15 watch updates the api

**C15** - Com `make watch-nest`, a edição do texto do e-mail vale no próximo cadastro em até 60 s, com o mesmo ID do `worker` (AC 15)
Proof: run infra | PASS NS16 watch updates the worker

**C16** - Com `make watch-nest`, mudar `package.json`, `package-lock.json` ou `Dockerfile` recria `api` e `worker` com IDs novos, na mesma imagem nova e `healthy`, em até 180 s (AC 16)
Proof: run infra | PASS NS17 watch rebuilds on package.json
Proof: run infra | PASS NS17 watch rebuilds on package-lock.json
Proof: run infra | PASS NS17 watch rebuilds on Dockerfile

**C17** - `make nest-npm` sem `ARGS` sai com código diferente de `0`, imprime `uso: make nest-npm ARGS="<comando npm>"` e não muda nenhum container (AC 17)
Proof: run infra | PASS NS18 nest-npm requires args

**C18** - `make nest-npm ARGS="install <pacote>"` por um usuário não root muda só `package.json` e `package-lock.json`, com o dono de quem chamou, sem `node_modules`, e mantém os IDs da stack no ar (AC 18)
Proof: run infra | PASS NS19 nest-npm writes only json and lock

**C19** - Um comando do npm que falha faz `make nest-npm` sair com erro, com os dois arquivos iguais aos de antes, inteiros (AC 19)
Proof: run infra | PASS NS20 nest-npm propagates npm failure

**C20** - `dependencies` e `devDependencies` de `apis/nestjs/package.json` têm só versões `X.Y.Z`, e o `Dockerfile` parte de `node:26.13.0-alpine` (AC 20)
Proof: run infra | PASS NS21 nest versions are exact

**C21** - `make test-nest` sem ambiente no ar sai com `0`, sem PostgreSQL nem Redis, e com a stack no ar mantém os IDs dos containers (AC 21)
Proof: run infra | PASS NS22 test-nest passes without dependencies
Proof: run infra | PASS NS23 test-nest keeps running stack

**C22** - Um teste do Vitest que falha faz `make test-nest` sair com código diferente de `0` (AC 22)
Proof: run infra | PASS NS24 test-nest fails on failing test

**C23** - O Vitest cobre, sem banco nem Redis, a espera de 30, 60, 120 e 240 s, as opções do job, o `Message-ID`, o escape do nome no HTML e o `422` de JSON malformado (AC 23)
Proof: run nest | ✓ retry delay > doubles from the base for attempts 0 to 3
Proof: run nest | ✓ welcome job > is added with one attempt and no backoff
Proof: run nest | ✓ welcome mail > message id derives from the event
Proof: run nest | ✓ welcome mail > escapes the name in html
Proof: run nest | ✓ validation errors > malformed json answers the contract 422

### S3 - A NestJS passa a suíte de contrato

**C24** - `registration:nest` imprime `PASS` nos 30 ids de contrato de `registration.sh` (AC 24)
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

**C25** - `outbox:nest` imprime `PASS` nos 27 ids de contrato de `outbox.sh` (AC 25)
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

**C26** - `registration.sh`, `outbox.sh` e `registration-helpers.sh` ficam iguais aos de `5d4f5e7` (AC 26)
Proof: `git diff --quiet 5d4f5e7 -- tests/infra/registration.sh tests/infra/outbox.sh tests/infra/registration-helpers.sh`

**C27** - O adaptador `nest` define as 22 funções, e `stack_worker_stop` deixa o relay publicando: um cadastro fica `published` em até 10 s, com uma mensagem esperando em `registration-emails` (AC 27)
Proof: run infra | PASS NS25 worker pause keeps the relay publishing

### S4 - Relay no `worker`

**C28** - Depois de `make up-nest`, o `redis` da stack tem o agendador `outbox-relay` com intervalo de 1000 ms (AC 28)
Proof: run infra | PASS NS26 relay scheduler runs every second

**C29** - Com `OUTBOX_BATCH_SIZE=2` e 3 eventos prontos, a primeira execução publica exatamente os 2 de `created_at` mais antigo, e o terceiro sai numa execução seguinte (AC 29)
Proof: run infra | PASS NS27 relay batch size and order

**C30** - Um evento travado por outra transação não é esperado nem publicado, e os demais saem em até 10 s (AC 30)
Proof: run infra | PASS NS28 relay skips locked rows

**C31** - Uma publicação recusada no lote, com o contador de ids de `registration-emails` corrompido, deixa todos os eventos `pending`, com `published_at` nulo, e `outbox relay failed` no log do `worker`, que continua `healthy` (AC 31)
Proof: run infra | PASS NS29 relay failure keeps the batch pending

**C32** - Com o `redis` da stack pausado, em até 3 s o `worker` não tem transação aberta e um `UPDATE` com `lock_timeout` de 1 s conclui, em pelo menos duas sondagens; despausado, o e-mail chega em até 60 s sem reinício (AC 32)
Proof: run infra | PASS NS30 frozen queue releases the batch

**C33** - Um `worker` recém-iniciado publica um evento pronto em até 10 s (AC 33)
Proof: run infra | PASS NS31 worker publishes right after it starts

**C34** - Com o container `worker` parado, o evento de um `201` continua `pending` depois de 5 s, e o e-mail chega em até 60 s depois que ele volta (AC 34)
Proof: run infra | PASS NS32 stopped worker leaves events pending

### S5 - Envio a partir do evento

**C35** - O job publicado tem `data` exatamente `{"event_id":"<id>"}`, `attempts` `1`, nenhum `backoff` e id diferente do `event_id` (AC 35)
Proof: run infra | PASS NS33 job carries only the event id with one attempt

**C36** - Republicar um evento cujo job anterior ainda existe cria um job novo, e o contador de ids de `registration-emails` sobe (AC 36)
Proof: run infra | PASS NS34 republish creates a new job

**C37** - Um `worker` morto durante o envio não roda o job de novo: o evento continua `published`, com `attempts` igual; depois da republicação, o Mailpit tem exatamente uma mensagem, com o `Message-ID` do evento (AC 37)
Proof: run infra | PASS NS35 killed worker does not rerun the job

**C38** - Durante um envio para o Mailpit pausado, o `PTTL` da trava do job fica entre 5000 e 30000 ms, e a falha é gravada entre 5 e 10 s depois do início do envio (AC 38)
Proof: run infra | PASS NS36 job lock outlasts the smtp timeout

### S6 - Troca entre Laravel e NestJS

**C39** - Com o `worker` da NestJS parado, o evento `pending` de um `201` é publicado pela Laravel depois de `make up-laravel`, com exatamente uma mensagem em até 60 s (AC 39)
Proof: run infra | PASS SW1 nest pending event leaves through laravel

**C40** - Com o `horizon` parado, o evento `published` pela Laravel é republicado pela NestJS depois de `make up-nest`, com exatamente uma mensagem em até 60 s, com o `Message-ID` do evento (AC 40)
Proof: run infra | PASS SW2 laravel published event leaves through nest

**C41** - Um par IP e e-mail com `429` numa stack continua com `429` e `Retry-After` na outra, nos dois sentidos (AC 41)
Proof: run infra | PASS SW3 attempt limit follows nest to laravel
Proof: run infra | PASS SW4 attempt limit follows laravel to nest

### S7 - Suíte e CI

**C42** - `run.sh --list` imprime as 15 entradas, na ordem do AC 42 (AC 42)
Proof: run infra | PASS CS1 list prints every entry

**C43** - Os alvos `*-nest` não recusam com `stack nest ainda não implementada`, e os de `go` continuam recusando (AC 43)
Proof: run infra | PASS C16 missing stack refused
Proof: run infra | PASS C16B nest targets are implemented

**C44** - O CI tem um job que roda `make test-nest` depois de baixar o Compose fixado e conferir o checksum (AC 44)
Proof: run infra | PASS NS37 ci runs test-nest and the nest suites

**C45** - `make test-frontend`, `make test-laravel`, `make test-nest` e `bash tests/infra/run.sh` saem com `0` (AC 45)
Proof: make test-frontend
Proof: make test-laravel
Proof: make test-nest
Proof: run infra | test-infra: todos os testes passaram

### S8 - Documentação alinhada

**C46** - O README diz que a NestJS implementa o outbox com `api`, `worker` e `redis`, não diz que ela está em design, e a árvore mostra `nestjs/` sem `# planejado` (AC 46)
Proof: run infra | PASS ND1 readme describes the nest stack

**C47** - `docs/stacks.md` diz que a NestJS existe, e a árvore de › NestJS lista os arquivos de `apis/nestjs` (AC 47)
Proof: run infra | PASS ND2 stacks describe the nest stack

**C48** - `docs/infrastructure.md` lista `cadastro-feliz-nest` com os 3 serviços, `make nest-npm`, `make test-nest`, o job do CI e as 4 entradas novas da suíte (AC 48)
Proof: run infra | PASS ND3 infrastructure describes the nest stack

**C49** - O status de `docs/architecture.md`, `docs/database.md` e `docs/api-contract.md` diz que Laravel e NestJS implementam o outbox, sem dizer que a NestJS ainda não o implementa (AC 49)
Proof: run infra | PASS ND4 status lines name the nest stack

**C50** - `docs/decisions.md` tem as decisões 24 e 25 no índice e numa seção cada, e a 23 diz que o adaptador `nest` pausa as filas (AC 50)
Proof: run infra | PASS ND5 decisions record typeorm vitest and the nest adapter

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| doors do plano (8) | 1 projeto Compose C1 · C2 · C9 · 2 fronteira de módulos C10 · C24 (OB6) · 3 TypeORM C8 · C50 · 4 filas e limites C28 · C35 · C36 · C37 · C38 · 5 conexões C9 · C10 · C32 · 6 adaptador C27 · C24 · C25 · 7 dependências e testes C20 · C21 · C23 · C50 · 8 arquivos de prova C26 · C42 | - |
| transições do ciclo (10) | `[*]`→`pending` C25 (OB1) · `pending`→`published` C25 (OB15) · `published`→`published` C25 (OB17) · `published`→`processed` C25 (OB27) · `published`→`pending` C25 (OB33) · `published`→`failed` C25 (LM3) · `pending`→`processed` C25 (OB24) · `pending`→`pending` C25 (OB23) · `pending`→`failed` C25 (OB31) · `failed`→`pending` C25 (LM3) | - |
| prontidão do relay (6) | `pending` vencido C25 (OB15) · `pending` futuro C25 (OB16) · `published` expirado C25 (OB17) · terminal C25 (OB18) · travado C30 · além do lote C29 | - |
| respostas de `GET /health` (2) | `200` C3 · C9 · `503` C4 · C5 | - |
| respostas de `POST /users` (6) | `201` C24 (RG1) · C9 · `409` C24 (RG7) · `422` C24 (RG3, RG4) · C13 · `429` C24 (RG9) · `500` C24 (RG17, RG18) · C25 (OB4) · preflight `204` C24 (RG20) | - |
| exemplos do JSON que não é objeto, AC 13 (4) | `[]` C13 · `null` C13 · `"x"` C13 · `1` C13 | - |
| exemplos da espera, AC 23 (4) | `0`→30 s C23 · `1`→60 s C23 · `2`→120 s C23 · `3`→240 s C23 | - |
| serviços do projeto (3) | `api` C1 · `worker` C1 · `redis` C1 | - |
| dependências que param (6) | `postgres` C4 · C5 · `redis-limiter` C4 · C5 · `redis` da stack parado C9 · pausado C32 · Mailpit C37 · C38 · container `worker` C34 · C37 | - |
| arquivos que reconstroem no watch (3) | `package.json` C16 · `package-lock.json` C16 · `Dockerfile` C16 | - |
| montagens que iniciam a NestJS (3) | `main.ts` da `api` C1 · C11 · `worker.ts` C1 · C33 · container de teste C21 | - |
| adaptador `nest` (2) | as 22 funções de `ADAPTER_FUNCTIONS` definidas, pela recusa de `run.sh` que CS7 prova nome a nome, C27 · usadas pelos casos de contrato C24 · C25 | - |
| sentidos da troca (4) | evento NestJS→Laravel C39 · evento Laravel→NestJS C40 · `429` NestJS→Laravel C41 · `429` Laravel→NestJS C41 | - |
| alvos `*-nest` (4) | `up-nest` C1 · `watch-nest` C14 · `logs-nest` C43 · `down-nest` C43 | - |
| docs (7 lugares) | `README.md` C46 · `docs/stacks.md` C47 · `docs/infrastructure.md` C48 · `docs/architecture.md` C49 · `docs/database.md` C49 · `docs/api-contract.md` C49 · `docs/decisions.md` C50 | - |

## Swept

- validation: C13, C24 (RG3 a RG6) - o `ValidationPipe` e o filtro de exceções nunca deixam escapar o `400` do Nest
- failure modes: C11, C24 (OB4), C31, C32, C37
- idempotency: C25 (OB23, OB31), C36, C37 - mensagem repetida não reenvia evento terminal; a duplicata depois do envio é a limitação *at-least-once* aceita, com o mesmo `Message-ID`
- authorization: existing - cadastro público com os limites de RG9 e RG13; o relay e o consumidor não têm caller externo, e a NestJS não tem painel
- concurrency: C24 (RG8, RG15), C25 (OB24, OB37), C30
- data lifecycle: C8, C25 (LM2, LM2B), C39, C40 - os eventos sobrevivem à stack e à troca; não há backfill nem limpeza
- dependency failure: C4, C5, C9, C24 (RG17, RG18, RG19), C32, C34
- state transitions: C25 (ciclo inteiro, ver Coverage), C37
- observability: C6, C31, C25 (OB32) - motivo do `/health` no log, falha do relay no log do `worker`, falha de envio em `last_error`

## Handoff

- **Settled mid-build:** AC 17 passa a exigir código diferente de `0`, porque o make devolve `2` quando uma receita falha - user: "Código diferente de 0 (Recomendado)". AC 31 força a falha corrompendo o contador de ids de `registration-emails`, porque `CONFIG SET maxmemory` pararia também a fila `outbox-relay`, e o relay nem rodaria - user: "Contador corrompido (Recomendado)"
- **Dispatched:** none
- **Boundary:** none closed
- **Abandoned:** BullMQ 6, TypeORM 1 e TypeScript 7, as versões mais novas: mudaram APIs depois do que dá para conferir aqui; ficaram BullMQ 5.81.5, TypeORM 0.3.31 e TypeScript 6.0.3, com Nest 12.4.0 (peers conferidos no npm)
- **Ambiente da prova:** `tests/infra` exige bash 4 e ferramentas GNU, e o macOS daqui tem bash 3.2 sem os adaptadores da rodada anterior. As provas rodam num Docker-in-Docker descartável (`docker:29.0.4-dind`, com bash 5, coreutils, util-linux e Compose 2.40.3), com o repositório montado em `/repo`; o script fica fora do repositório. O dind roda com o armazenamento clássico `overlay2`, como o runner do CI: com o armazenamento do containerd, padrão do Docker 29, um build todo em cache gera outra imagem e recria os containers, o que fazia NS1 e o frontend falharem só ali
