# Transactional Outbox de `users` na stack Laravel checks

Build: none - o repositório não tem build, lint nem type check além do que as provas exercem; a imagem e o boot do Laravel são provados por LV1
Run laravel: `make test-laravel`
Run infra: `bash tests/infra/run.sh`
Plan: `.specs/features/laravel-outbox/plan.md`

56 checks in 5 slices · 10 one-way doors · 0 open, of which 0 block

## Checks

### S1 - Cadastro e evento na mesma transação

**C1** - Um `201` com o `scheduler` parado deixa uma linha em `users_outbox` com `user_id` igual a `data.id`, `event_type` `user.registered`, `status` `pending`, `attempts` `0` e `published_at` nulo (AC 1)
Proof: run infra | PASS OB1 registration writes a pending event

**C2** - O `payload` tem exatamente `user_id`, `name`, `email` e `occurred_at`, normalizados, com `occurred_at` igual a `data.created_at` (AC 2)
Proof: run infra | PASS OB2 payload keys and normalization

**C3** - E-mail repetido, inclusive com outra caixa, responde `409` com o corpo de hoje, sem linha nova nas duas tabelas e sem mudar a cota (AC 3)
Proof: run infra | PASS RG7 repeated email conflicts
Proof: run infra | PASS RG14 conflict does not consume quota

**C4** - Uma falha forçada no banco no `INSERT` de `users_outbox` responde `500` com o corpo exato, sem a linha em `users` e sem mudar a cota (AC 4)
Proof: run infra | PASS OB4 outbox insert failure rolls back the user

**C5** - Com o `redis` da stack parado ou pausado, a API responde `201` em menos de 3 s, com o usuário, o evento `pending`, nenhuma linha de erro no log do `php-fpm` e a cota uma unidade acima (AC 5)
Proof: run infra | PASS RG19 queue down still answers 201
Proof: run infra | PASS OB5 frozen queue still answers 201

**C6** - Com `scheduler` e `horizon` parados, um `201` não muda `total_connections_received` do `redis` da stack (AC 6)
Proof: run infra | PASS OB6 registration never connects to the queue

**C7** - 50 cadastros paralelos do mesmo IP dão 20 `201`, 30 `429`, 20 linhas em `users` e 20 em `users_outbox` (AC 7)
Proof: run infra | PASS RG15 ip quota holds in parallel

**C8** - Com o `postgres` parado e a cota livre, a API responde `500` com o corpo de hoje, em menos de 3 s, sem mudar a cota (AC 8)
Proof: run infra | PASS RG18 database down answers 500 and releases

**C9** - `WelcomeEmailPublisher` não existe, e o teste do `201` afirma que nenhum job foi publicado (AC 9)
Proof: run infra | PASS OB9 publisher class is gone
Proof: run laravel | ✓ it answers 201 and publishes no job

**C10** - `composer.lock` tem `modules/outbox` de `app-modules/outbox`, e `vendor/modules/outbox` existe no `php-fpm` (AC 10)
Proof: run infra | PASS LV49 modular locked with local modules
Proof: run infra | PASS LV50 modules layout
Proof: run infra | PASS LV51 image resolves local modules

**C11** - O código de `app-modules/outbox` não referencia `Modules\Users` (AC 11)
Proof: run infra | PASS OB11 outbox module does not reference users

### S2 - Relay e `scheduler`

**C12** - Em clone limpo, os únicos containers do projeto são `nginx`, `php-fpm`, `scheduler`, `horizon` e `redis`, todos `healthy`, e subir de novo mantém os 5 IDs (AC 12)
Proof: run infra | PASS LV1 up-laravel on clean clone
Proof: run infra | PASS LV2 up-laravel rerun keeps containers

**C13** - O `scheduler` usa a imagem `cadastro-feliz-laravel-php-fpm`, sem porta publicada, e `schedule:list` mostra `outbox:relay` a cada segundo (AC 13)
Proof: run infra | PASS LV4 laravel published ports
Proof: run infra | PASS OB13 scheduler image and schedule list

**C14** - `config:show outbox` no `scheduler` mostra 100, 300, 5 e 30 com o `.env` padrão (AC 14)
Proof: run infra | PASS OB14 outbox config defaults in the scheduler

**C15** - Com o `horizon` parado, em até 10 s o evento fica `published`, com `published_at`, e a fila tem uma mensagem (AC 15)
Proof: run infra | PASS OB15 relay publishes a pending event

**C16** - Um evento `pending` com `available_at` 1 hora no futuro continua `pending` depois de 5 s, sem mensagem na fila (AC 16)
Proof: run infra | PASS OB16 relay skips a future event

**C17** - Com republicação de 5 s, um evento `published` há 10 s é republicado, com `published_at` renovado e `attempts` igual; com 300 s, não é (AC 17)
Proof: run infra | PASS OB17 relay republishes only expired events

**C18** - Eventos `processed` e `failed` com `published_at` antigo nunca são selecionados (AC 18)
Proof: run infra | PASS OB18 relay never selects terminal events

**C19** - Com `OUTBOX_BATCH_SIZE=2` e 3 eventos prontos, o comando imprime `2 event(s) published.`, sai com `0` e publica os 2 mais antigos; sem eventos, imprime `0 event(s) published.` e sai com `0` (AC 19)
Proof: run infra | PASS OB19 relay batch output and order

**C20** - Com um evento travado por outra transação, o relay não espera nem o publica, e publica os demais (AC 20)
Proof: run infra | PASS OB20 relay skips locked rows

**C21** - Com o `redis` parado, o comando sai com `1`, os eventos continuam `pending` com `published_at` nulo, `docker logs` do `scheduler` tem `outbox relay failed`, e o container fica `healthy` (AC 21)
Proof: run infra | PASS OB21 relay failure keeps events and logs

**C22** - Com o `redis` de volta, o e-mail chega em até 60 s, sem reinício manual (AC 22)
Proof: run infra | PASS OB22 relay resumes when the queue returns

**C23** - Com o `UPDATE` do relay falhando depois de publicar, os eventos continuam `pending`, e ao fim da falha cada evento gera exatamente uma mensagem no Mailpit (AC 23)
Proof: run infra | PASS OB23 relay rollback after publish sends once

**C24** - Com o `COMMIT` do relay atrasado 3 s, a mensagem chega antes, e o evento termina `processed`, com uma mensagem no Mailpit (AC 24)
Proof: run infra | PASS OB24 message before commit ends processed

**C25** - Com o `scheduler` parado, o evento fica `pending`, e com ele de volta o e-mail chega em até 60 s (AC 25)
Proof: run infra | PASS OB25 events wait for the scheduler

**C26** - Com o watch, uma edição de `RelayOutboxCommand` chega ao `scheduler` em até 15 s, com o mesmo ID (AC 26)
Proof: run infra | PASS OB26 watch updates the relay
**C56** - Com o watch, uma mudança em `composer.json`, `composer.lock` ou `docker/php` deixa `php-fpm`, `scheduler` e `horizon` recriados, na mesma imagem nova e `healthy`, em até 180 s (AC 56)
Proof: run infra | PASS LV25 watch rebuilds on composer.json
Proof: run infra | PASS LV25 watch rebuilds on composer.lock
Proof: run infra | PASS LV25 watch rebuilds on docker/php

### S3 - Worker sobre o evento

**C27** - Um envio com sucesso deixa o evento `processed`, com `processed_at`, `last_error` nulo e uma mensagem para o e-mail do `payload` em até 30 s (AC 27)
Proof: run infra | PASS OB27 processed event and mail

**C28** - Com o nome em `users` mudado antes do envio, o e-mail usa o nome do `payload` (AC 28)
Proof: run infra | PASS OB28 mail uses the payload name

**C29** - `MessageID` no Mailpit é `<event_id>@cadastro-feliz.local` (AC 29)
Proof: run infra | PASS OB29 message id derives from the event

**C30** - A mensagem na fila tem o `id` do evento, sem nome, e-mail nem `user_id`, com `maxTries` `1` e `backoff` nulo (AC 30)
Proof: run infra | PASS RG23 job carries only the event id
Proof: run infra | PASS RG24 job has no native retries

**C31** - Mensagem de evento `processed` ou `failed` não envia e-mail e não muda `status`, `attempts` nem `processed_at` (AC 31)
Proof: run infra | PASS OB31 terminal event message sends nothing

**C32** - Mensagem de `event_id` inexistente não envia e-mail, registra no log e não aparece em `GET /horizon/api/jobs/failed` (AC 32)
Proof: run infra | PASS OB32 missing event is ignored

**C33** - Uma falha antes do limite volta a `pending`, com `attempts` + 1, `last_error` e espera de cerca de 30 s para `attempts` anterior `0` e 240 s para `3`, fora de `GET /horizon/api/jobs/failed` (AC 33)
Proof: run infra | PASS OB33 send failure schedules a retry

**C34** - A falha na última tentativa deixa `failed`, com `attempts` no limite e `last_error` (AC 34)
Proof: run infra | PASS LM3 exhausted retries are recorded and recoverable

**C35** - O `UPDATE` de reprocessamento de docs/database.md sobre um `failed`, com o SMTP de volta, entrega o e-mail e termina `processed` (AC 35)
Proof: run infra | PASS LM3 exhausted retries are recorded and recoverable

**C36** - Com o Mailpit pausado, `attempts` sobe em até 30 s, com `last_error`, e depois de despausar o e-mail chega (AC 36)
Proof: run infra | PASS OB36 frozen smtp counts as a failure

**C37** - Durante o envio a um Mailpit pausado, `pg_stat_activity` não mostra transação aberta do `horizon`, e um `UPDATE` com `lock_timeout` de 1 s conclui (AC 37)
Proof: run infra | PASS OB37 worker holds no transaction during send

**C38** - Com o `postgres` parado na chegada da mensagem, o evento continua `published`, com `attempts` igual, e o e-mail chega depois da republicação (AC 38)
Proof: run infra | PASS OB38 database down keeps the event published

**C39** - No `horizon`, os valores são 5 do SMTP, 60 do supervisor, 90 do `retry_after` e 300 da republicação, nessa ordem (AC 39)
Proof: run infra | PASS OB39 time limits keep their order

**C40** - Os testes em Pest cobrem, sem banco nem Redis, a espera de `attempts` anterior `0` a `3`, o `tries` `1` e o `Message-ID` de `WelcomeMail` (AC 40)
Proof: run laravel | ✓ it waits base times two to the previous attempts
Proof: run laravel | ✓ it runs once with no native backoff
Proof: run laravel | ✓ it derives the message id from the event

**C41** - Assunto, remetente, textos, escape do nome e o `409` sem e-mail continuam como hoje (AC 41)
Proof: run infra | PASS RG29 welcome mail arrives
Proof: run infra | PASS RG30 welcome mail text
Proof: run infra | PASS RG31 welcome mail has no external resources
Proof: run infra | PASS RG32 welcome mail escapes the name
Proof: run infra | PASS RG33 conflict sends no mail

**C42** - Com o watch, uma edição de `outbox::welcome-text` sai no próximo cadastro em até 60 s, com o `php-fpm` no mesmo ID (AC 42)
Proof: run infra | PASS RG27 watch updates the worker

### S4 - Antes e depois, provado

**C43** - Com o `redis` parado no cadastro e depois religado, o e-mail chega em até 60 s, o evento termina `processed`, e repetir responde `409`, com exatamente uma mensagem (AC 43)
Proof: run infra | PASS LM1 queue down delays the mail

**C44** - Com o `horizon` parado e a stack derrubada, com republicação de 5 s, a fila volta vazia, o evento segue `published`, e o e-mail chega em até 60 s, com exatamente uma mensagem (AC 44)
Proof: run infra | PASS LM2 stack down republishes the event

**C45** - Com `scheduler` e `horizon` parados e a stack derrubada, com os valores padrão, o e-mail chega em até 60 s (AC 45)
Proof: run infra | PASS LM2B stack down delivers pending events

**C46** - Com as tentativas esgotadas, 30 s depois de o Mailpit voltar o evento está `failed`, com `attempts` `2` e `last_error`, sem mensagem; reprocessado, o e-mail chega (AC 46)
Proof: run infra | PASS LM3 exhausted retries are recorded and recoverable

**C47** - Com o Mailpit parado e `attempts` subindo, o e-mail chega quando ele volta antes de esgotar, com o evento `processed` (AC 47)
Proof: run infra | PASS RG26 mail arrives after smtp returns

**C48** - `make test-frontend`, `make test-laravel` e `bash tests/infra/run.sh` saem com `0` (AC 48)
Proof: make test-frontend
Proof: make test-laravel
Proof: run infra | test-infra: todos os testes passaram

### S5 - Documentação alinhada

**C49** - `docs/architecture.md` tem `## Antes e depois do outbox`, com uma linha por caso do design, cada uma com o antes, o agora e a prova, e não tem a seção antiga (AC 49)
Proof: run infra | PASS LM4 before and after is recorded

**C50** - O status de `docs/architecture.md` diz que a stack Laravel implementa o outbox, e › Worker traz `<event_id>@cadastro-feliz.local` (AC 50)
Proof: run infra | PASS OD1 architecture describes the outbox

**C51** - `docs/decisions.md` marca a decisão 21 como **Encerrada**, tira `Suspensa na stack Laravel` da 9 e tem a 22, no índice e numa seção (AC 51)
Proof: run infra | PASS RD1 decision 21 closed and decision 22 recorded

**C52** - `docs/stacks.md` › Laravel diz que `scheduler` existe, cita `SendWelcomeEmailJob`, não cita `SendRegistrationEmailJob`, e a árvore mostra `app-modules/outbox` com `src/Console/Commands/RelayOutboxCommand.php`, sem `WelcomeEmailPublisher` (AC 52)
Proof: run infra | PASS LV40 stacks docs describe laravel stack

**C53** - Os status de `docs/api-contract.md` e `docs/database.md` deixam de dizer que a stack Laravel está sem outbox (AC 53)
Proof: run infra | PASS RD3 contract and database status

**C54** - `docs/infrastructure.md` › Arquivos Compose lista `scheduler` na stack Laravel (AC 54)
Proof: run infra | PASS RD4 infrastructure docs list the queue and the scheduler

**C55** - O `README.md` não tem `por enquanto sem o outbox` nem `E-mail perdido na stack Laravel`, diz que a stack implementa o outbox e cita o reprocessamento manual de `failed` em › Limites conhecidos (AC 55)
Proof: run infra | PASS RD5 readme states the outbox

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| doors do plano (10) | 1 `payload` C1 · C2 · 2 ciclo e retentativas C33 · C34 · C35 · 3 job C30 · C40 · 4 `Message-ID` C29 · C40 · 5 módulo C10 · C11 · 6 `scheduler` C12 · C13 · C21 · C26 · 7 limites C36 · C39 · 8 prova e registro C43 · C44 · C46 · C49 · C51 · 9 início do `scheduler` C25 · C45 · 10 rebuild do watch C56 | - |
| transições do ciclo (10) | `[*]`→`pending` C1 · `pending`→`published` C15 · `published`→`published` C17 · `published`→`processed` C27 · `published`→`pending` C33 · `published`→`failed` C34 · `pending`→`processed` C24 · `pending`→`pending` C23 · `pending`→`failed` C31 · `failed`→`pending` C35 | - |
| prontidão do relay (4) | `pending` vencido C15 · `pending` futuro C16 · `published` expirado C17 · terminal C18 | - |
| exemplos da espera, AC 33 (2) | `0`→30 s C33 · `3`→240 s C33 | - |
| exemplos da republicação, AC 17 (2) | 5 s C17 · 300 s C17 | - |
| respostas de `POST /users` afetadas (3) | `201` C1 · C5 · `409` C3 · `500` C4 · C8 | - |
| serviços do projeto (5) | `nginx` C12 · `php-fpm` C12 · `scheduler` C12 · `horizon` C12 · `redis` C12 | - |
| dependências que param (5) | `redis` C5 · C21 · C22 · `postgres` C8 · C38 · Mailpit parado C46 · C47 · Mailpit pausado C36 · C37 · `scheduler` C25 | - |
| startup config do Laravel (4 montagens) | `php-fpm` C10 · `scheduler` C13 · C14 · `horizon` C39 · container de teste C48 | - |
| casos do antes e depois (5) | fila parada C43 · stack derrubada C44 · SMTP esgotado C46 · SMTP de volta C47 · queda entre as escritas C4 | - |
| docs (7 lugares) | `docs/architecture.md` C49 · C50 · `docs/decisions.md` C51 · `docs/stacks.md` C52 · `docs/api-contract.md` C53 · `docs/database.md` C53 · `docs/infrastructure.md` C54 · `README.md` C55 | - |

## Swept

- validation: existing - RG3, RG4 e RG5; a validação de `POST /users` não muda e continua sem gravar evento
- failure modes: C4, C21, C23, C33, C34, C36, C38
- idempotency: C23, C31, C43 - mensagens repetidas não reenviam e-mail de evento terminal; a duplicata depois do envio é a limitação *at-least-once* aceita, identificável por C29
- authorization: existing - cadastro público com limites (RG9, RG13) e painel só em `local` (`denies the horizon panel outside local`); o relay não tem caller externo
- concurrency: C7, C20, C24
- data lifecycle: C2, C44, C45 - os eventos sobrevivem à stack; não há backfill nem limpeza, como em Out of scope
- dependency failure: C5, C6, C8, C21, C22, C25, C36, C38
- state transitions: C1, C15, C17, C18, C24, C27, C31, C33, C34, C35
- observability: C21, C32, C33, C34 - falha do relay no log do `scheduler`; falha de envio em `last_error`

## Handoff

- **Settled mid-build:** none
- **Dispatched:** none
- **Boundary:** C1-C56 closed at `9dd582d`
- **Abandoned:** o `scheduler` só com `schedule:work`, trocado na door 9, porque ele dispara apenas na virada do minuto. OB24 atrasa o `COMMIT` em 8 s, mais que os 3 s do critério, porque o worker pode dormir 3 s com a fila vazia e a mensagem precisa chegar antes do `COMMIT`.
- **Ambiente da prova:** Docker real no macOS, onde `tests/infra` depende de ferramentas GNU e do bash 4. As provas rodam com adaptadores fora do repositório para `sed -i`, `sed 1a`, `stat -c`, `timeout`, `tac`, `paste` e `mapfile`. O CI, em Linux, não precisa deles e ainda não rodou este branch, porque não houve push.
- **Walked:** not applicable - nenhuma tela muda; o formulário é coberto pelos testes existentes
