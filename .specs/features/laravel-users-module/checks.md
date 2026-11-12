# Módulo único `users` e `DB::transaction` na stack Laravel checks

Build: none - o repositório não tem build, lint nem type check além do que as provas exercem; a imagem e o boot do Laravel são provados por `make test-laravel` e por LV1
Run laravel: `make test-laravel`
Run infra: `bash tests/infra/run.sh docs laravel registration:laravel outbox:laravel laravel-outbox stack-switch`
Plan: `.specs/features/laravel-users-module/plan.md`

19 checks in 5 slices · 4 one-way doors · 0 open, of which 0 block

## Checks

### S1 - Um módulo `users`

**C1** - `app-modules/notifications` não existe, `composer.json` não exige `modules/notifications`, e `composer.lock` não tem `modules/notifications` nem `modules/outbox` e tem `modules/users` e `modules/health` vindos de `app-modules` (AC 1)
Proof: run laravel | ✓ it has a single users module
Proof: run infra | PASS LV49 modular locked with local modules
Proof: run infra | PASS LV50 modules layout
Proof: run infra | PASS LV51 image resolves local modules

**C2** - Nenhum arquivo PHP de `app-modules` ou `tests` contém `Modules\Notifications` ou `notifications::` (AC 2)
Proof: run laravel | ✓ it references no notifications module
Proof: run infra | PASS OB11 laravel has no notifications module

**C3** - `Modules\Users\Jobs\SendWelcomeEmailJob`, `Modules\Users\Mail\WelcomeMail` e `Modules\Users\UseCases\SendWelcomeEmail` existem; `OutboxConsumers`, `NotificationsServiceProvider` e `UnknownOutboxConsumer` não existem em `apis/laravel` (AC 3)
Proof: run laravel | ✓ it keeps the welcome email in users

**C4** - `SendWelcomeEmailJob` tem `tries` `1`, sem `backoff`; `WelcomeMail` tem o `Message-ID` `<event_id>@cadastro-feliz.local`, as views `users::welcome` e `users::welcome-text`, e o HTML para `Ana` contém `Olá, Ana!` (AC 4)
Proof: run laravel | ✓ it runs once with no native backoff
Proof: run laravel | ✓ it derives the message id from the event
Proof: run laravel | ✓ it renders the users views

**C5** - `SendWelcomeEmail` não envia nem escreve para `processed` e `failed`; envia e marca `processed` para `pending` e `published`; registra a falha com `boom` quando o envio lança; avisa `outbox event not found` para um id inexistente (AC 5)
Proof: run laravel | ✓ it skips terminal events
Proof: run laravel | ✓ it sends the welcome mail and marks the event processed
Proof: run laravel | ✓ it records the send failure and does not mark processed
Proof: run laravel | ✓ it warns and sends nothing for a missing event

### S2 - Transação pela facade `DB`

**C6** - Nenhum arquivo PHP de `app` ou `app-modules/*/src` contém `ConnectionInterface`, e os construtores de `RegisterUser` e `RelayOutboxEvents` não recebem conexão de banco (AC 6)
Proof: run laravel | ✓ it injects no database connection

**C7** - `RegisterUser` grava `users` e depois `users_outbox` dentro do callback de uma única `DB::transaction`, e nada quando o callback não roda (AC 7)
Proof: run laravel | ✓ it writes the user and the event inside one transaction
Proof: run laravel | ✓ it writes nothing when the transaction does not run

**C8** - Uma exceção ao gravar o evento sai do callback de `DB::transaction`, e a cota é devolvida uma vez (AC 8)
Proof: run laravel | ✓ it rethrows an event failure and releases the quota once

**C9** - Nenhum repositório de `app-modules/*/src/Repositories` contém `transaction(` ou `beginTransaction` (AC 9)
Proof: run laravel | ✓ it opens no transaction in repositories

**C10** - `POST /users` com um cadastro válido responde `201` sem publicar job, em Pest sem PostgreSQL (AC 10)
Proof: run laravel | ✓ it answers 201 and publishes no job

### S3 - Relay escolhe o job pelo tipo

**C11** - `RelayOutboxEvents` trava o lote, publica cada evento e marca `published`, nessa ordem, dentro de uma única `DB::transaction`; com 2 eventos, 2 publicações e uma marcação com os 2 ids; com lote vazio, nada (AC 11)
Proof: run laravel | ✓ it locks, publishes and marks the batch inside one transaction
Proof: run laravel | ✓ it publishes and marks nothing for an empty batch

**C12** - Para um evento `user.registered` com id `e1`, o relay publica um `Modules\Users\Jobs\SendWelcomeEmailJob` com `eventId` `e1` (AC 12)
Proof: run laravel | ✓ it publishes the welcome email job for user registered

**C13** - Um `event_type` fora de `OutboxEventType` no lote lança uma exceção com o tipo, antes de qualquer publicação e sem marcar `published`, inclusive quando é o 3º de 3 (AC 13)
Proof: run laravel | ✓ it publishes nothing when an event type is unknown

**C14** - `outbox:relay` sai com `1` e registra `outbox relay failed` quando o caso de uso lança, e imprime `<N> event(s) published.` com `0` quando não (AC 14)
Proof: run laravel | ✓ it exits 1 and logs when the relay fails
Proof: run laravel | ✓ it prints the published count
Proof: run infra | PASS OB19 relay batch output and order
Proof: run infra | PASS OB21 relay failure keeps events and logs

### S4 - Comportamento igual, provado

**C15** - `make test-laravel` sai com `0`, sem PostgreSQL nem Redis (AC 15)
Proof: run laravel | Tests: passed

**C16** - O subconjunto Laravel de `tests/infra` sai com `0`, com os mesmos ids de antes, e só os quatro arquivos de `tests/infra` que leem módulo, classe ou caminho mudaram (AC 16)
Proof: run infra | test-infra: todos os testes passaram
Proof: `test "$(git diff --name-only 75bc72a HEAD -- tests/infra | tr '\n' ' ')" = "tests/infra/adapters/laravel.sh tests/infra/docs.sh tests/infra/laravel-outbox.sh tests/infra/laravel.sh "`

**C17** - OB11 falha se `app-modules/notifications` existir ou se algum arquivo de `app-modules` referenciar `Modules\Notifications` (AC 17)
Proof: run infra | PASS OB11 laravel has no notifications module

### S5 - Documentação alinhada

**C18** - docs/stacks.md › Laravel mostra em `users/` `src/Jobs/SendWelcomeEmailJob.php`, `src/Mail/WelcomeMail.php` e `src/UseCases/SendWelcomeEmail.php`, sem `notifications/`, `OutboxConsumers` nem `NotificationsServiceProvider`, e diz que `users` é dono de `users_outbox`, roda o relay e envia o e-mail, e que cada caso de uso abre a transação com `DB::transaction` (AC 18)
Proof: run infra | PASS LV40 stacks docs describe laravel stack

**C19** - docs/decisions.md tem a decisão 26 `Módulo único da stack Laravel` no índice e numa seção com **Substitui**, motivos, alternativas descartadas (`users` + `notifications`; `ConnectionInterface` injetada) e custos (AC 19)
Proof: run infra | PASS LV53 decision 26 records the single laravel module

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| exemplos de AC 5 (5) | `processed` C5 · `failed` C5 · `pending` com envio ok C5 · envio lançando `boom` C5 · id inexistente C5 | - |
| exemplos de AC 7 (2) | callback não executado C7 · callback executado, na ordem C7 | - |
| exemplos de AC 11 (2) | lote de 2 C11 · lote vazio C11 | - |
| exemplos de AC 13 (2) | lote só com `user.deleted` C13 · 3º de 3 `user.deleted` C13 | - |
| casos de `OutboxEventType` no `match` (1) | `UserRegistered` C12 | - |
| saídas de `outbox:relay` (2) | `0` com a contagem C14 · `1` com o log C14 | - |
| classes que saem, AC 3 (3) | `OutboxConsumers` C3 · `NotificationsServiceProvider` C3 · `UnknownOutboxConsumer` C3 | - |
| casos de uso que abrem transação (2) | `RegisterUser` C6, C7 · `RelayOutboxEvents` C6, C11 | - |
| doors de Landing (4) | 1 módulos C1, C2, C3 · 2 job na fila C4, C12 · 3 transação nos casos de uso C6, C7, C9, C11 · 4 job pelo tipo C12, C13 | - |
| leitores de Changes underneath (9) | `stack_dispatch` C16 · `laravel-outbox.sh` RG27 e OB11 C16, C17 · `laravel.sh` LV49 a LV51 C1 · `docs.sh` LV40 C18 · `docs.sh` LV53 C19 · Pest de `users` C15 · `composer.json`/`composer.lock` C1 · docs/stacks.md C18 · docs/decisions.md C19 | - |

## Swept

- validation: n/a - nenhuma entrada nova; a validação de `POST /users` continua provada no Pest e no run infra (C15, C16)
- failure modes: C8, C13, C14
- idempotency: C5 - a mensagem repetida de um evento terminal não envia nem escreve
- authorization: n/a - nenhuma rota muda
- concurrency: C11 - trava, publicação e marcação na mesma transação; existing - OB20 e RG15 no run infra (C16)
- data lifecycle: n/a - o schema e os dados não mudam
- dependency failure: C5 - falha de SMTP; existing - OB21 no run infra (C14)
- state transitions: C5; existing - o ciclo de status de docs/database.md, provado no run infra (C16)
- observability: C14 - `outbox relay failed`; C5 - `outbox event not found`

## Handoff

- **Settled mid-build:** none
- **Dispatched:** none
- **Boundary:** nenhuma check fechada
- **Abandoned:** none
