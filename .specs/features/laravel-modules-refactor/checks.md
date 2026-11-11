# Módulos da stack Laravel por contexto checks

Build: none - o repositório não tem build, lint nem type check além do que as provas exercem; a imagem e o boot do Laravel são provados por `make test-laravel` e por LV1
Run laravel: `make test-laravel`
Run infra: `bash tests/infra/run.sh docs laravel registration:laravel outbox:laravel laravel-outbox stack-switch`
Plan: `.specs/features/laravel-modules-refactor/plan.md`

22 checks in 6 slices · 5 one-way doors · 0 open, of which 0 block

## Checks

### S1 - Status e eventos com nome

**C1** - `OutboxStatus` tem exatamente `pending`, `published`, `processed` e `failed`, e `isTerminal()` é verdadeiro só para `processed` e `failed` (AC 1)
Proof: run laravel | ✓ it lists the statuses and which are terminal

**C2** - `OutboxEventType` tem exatamente um caso, `UserRegistered`, com o valor `user.registered` (AC 2)
Proof: run laravel | ✓ it has only the user registered event type

**C3** - Nenhum arquivo de `app-modules/*/src`, fora dos dois enums, contém `pending`, `published`, `processed`, `failed` ou `user.registered` entre aspas (AC 3)
Proof: run laravel | ✓ it keeps status and event literals inside the enums

**C4** - `TERMINAL_STATUSES` não existe, e `UserOutboxEvent` devolve `status` como `OutboxStatus` e `event_type` como `OutboxEventType` (AC 4)
Proof: run laravel | ✓ it casts the outbox row to the enums

### S2 - Cadastro como caso de uso

**C5** - `RegisterUser` grava `users` e depois `users_outbox` dentro do callback de uma única `transaction()` da conexão injetada, e nada sem o callback (AC 5)
Proof: run laravel | ✓ it writes the user and the event inside one transaction
Proof: run laravel | ✓ it writes nothing when the transaction does not run

**C6** - Uma exceção ao gravar o evento sai do callback de `transaction()`, e a cota é devolvida uma vez (AC 6)
Proof: run laravel | ✓ it rethrows an event failure and releases the quota once

**C7** - Nenhum repositório de `app-modules/*/src/Repositories` contém `transaction(` ou `beginTransaction` (AC 7)
Proof: run laravel | ✓ it opens no transaction in repositories

**C8** - `src/Actions` e `RegisterUserAction` não existem, e `POST /users` passa por `RegisterUser` (AC 8)
Proof: run laravel | ✓ it has no actions
Proof: run laravel | ✓ it answers 201 through the register user use case

### S3 - Relay como caso de uso

**C9** - `RelayOutboxEvents` trava o lote, publica cada evento e marca `published`, nessa ordem, dentro de uma única `transaction()`; com 2 eventos, 2 publicações e uma marcação com os 2 ids; com lote vazio, nada (AC 9)
Proof: run laravel | ✓ it locks, publishes and marks the batch inside one transaction
Proof: run laravel | ✓ it publishes and marks nothing for an empty batch

**C10** - Um tipo sem consumidor no lote lança `UnknownOutboxConsumer` com o tipo, antes de qualquer publicação e sem marcar `published`, inclusive quando é o 3º de 3 (AC 10)
Proof: run laravel | ✓ it publishes nothing when an event type has no consumer

**C11** - `outbox:relay` sai com `1` e registra `outbox relay failed` quando o caso de uso lança, e imprime `<N> event(s) published.` com `0` quando não (AC 11)
Proof: run laravel | ✓ it exits 1 and logs when the relay fails
Proof: run laravel | ✓ it prints the published count
Proof: run infra | PASS OB19 relay batch output and order
Proof: run infra | PASS OB21 relay failure keeps events and logs

**C12** - Com a aplicação de pé, `OutboxConsumers` devolve para `user.registered` um `Modules\Notifications\Jobs\SendWelcomeEmailJob` com o `eventId` (AC 12)
Proof: run laravel | ✓ it maps user registered to the welcome email job

**C13** - O código de `app-modules/users` não referencia `Modules\Notifications` (AC 13)
Proof: run infra | PASS OB11 users module does not reference notifications

### S4 - E-mail no módulo `notifications`

**C14** - `modules/notifications` existe em `app-modules/notifications`, com o namespace `Modules\Notifications\`; `app-modules/outbox` e `modules/outbox` não existem (AC 14)
Proof: run infra | PASS LV49 modular locked with local modules
Proof: run infra | PASS LV50 modules layout
Proof: run infra | PASS LV51 image resolves local modules
Proof: run laravel | ✓ it has no outbox module

**C15** - `app-modules/notifications/src` não contém `users_outbox`, `DB::`, `ConnectionInterface` nem `transaction(` (AC 15)
Proof: run laravel | ✓ it keeps notifications away from users_outbox and transactions

**C16** - `SendWelcomeEmail` não envia nem escreve para `processed` e `failed`; envia e marca `processed` para `pending` e `published`; registra a falha com a mensagem quando o envio lança; avisa `outbox event not found` para um id inexistente (AC 16)
Proof: run laravel | ✓ it skips terminal events
Proof: run laravel | ✓ it sends the welcome mail and marks the event processed
Proof: run laravel | ✓ it records the send failure and does not mark processed
Proof: run laravel | ✓ it warns and sends nothing for a missing event

**C17** - `SendWelcomeEmailJob` tem `tries` `1`, sem `backoff`; `WelcomeMail` tem o `Message-ID` `<event_id>@cadastro-feliz.local` e as views `notifications::welcome` e `notifications::welcome-text` (AC 17)
Proof: run laravel | ✓ it runs once with no native backoff
Proof: run laravel | ✓ it derives the message id from the event
Proof: run laravel | ✓ it renders the notifications views

**C18** - `RetryPolicy` dá 30, 60, 120 e 240 s para `attempts` anterior de `0` a `3` com base 30, e 2 s para `0` com base 2 (AC 18)
Proof: run laravel | ✓ it waits base times two to the previous attempts

### S5 - Comportamento igual, provado

**C19** - `make test-laravel` sai com `0`, sem PostgreSQL nem Redis (AC 19)
Proof: run laravel | Tests: passed

**C20** - O subconjunto Laravel de `tests/infra` sai com `0`, com os mesmos ids de antes (AC 20)
Proof: run infra | test-infra: todos os testes passaram

### S6 - Documentação alinhada

**C21** - docs/stacks.md › Laravel mostra `notifications/` e, em `users/`, `src/UseCases/`, `src/Enums/` e `src/Console/Commands/RelayOutboxCommand.php`, sem `outbox/` como módulo, `src/Actions` nem `RegisterUserAction`, e o item de módulos diz quem é dono de quê e a direção da dependência (AC 21)
Proof: run infra | PASS LV40 stacks docs describe laravel stack

**C22** - docs/decisions.md tem a decisão 26 no índice e numa seção com motivos, alternativas descartadas e custos (AC 22)
Proof: run infra | PASS LV53 decision 26 records the laravel modules

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| `OutboxStatus` e `isTerminal()` (4) | `pending` C1 · `published` C1 · `processed` C1 · `failed` C1 | - |
| literais proibidos fora dos enums, AC 3 (5) | `pending` C3 · `published` C3 · `processed` C3 · `failed` C3 · `user.registered` C3 | - |
| exemplos de AC 5 (2) | callback não executado C5 · callback executado, na ordem C5 | - |
| exemplos de AC 9 (2) | lote de 2 C9 · lote vazio C9 | - |
| exemplos de AC 10 (2) | tipo único sem consumidor C10 · 3º de 3 sem consumidor C10 | - |
| exemplos de AC 16 (5) | `processed` C16 · `failed` C16 · `pending` com envio ok C16 · `published` com envio lançando C16 · id inexistente C16 | - |
| saídas de `outbox:relay` (2) | `0` com a contagem C11 · `1` com o log C11 | - |
| doors de Landing (5) | 1 módulos C13, C14, C15 · 2 job na fila C12, C17 · 3 registro de consumidores C10, C12 · 4 casos de uso C5, C7, C8, C9 · 5 enums C1, C2, C3, C4 | - |
| startup config: registro de `user.registered` (2 assemblies) | harness do Pest C12 · stack no ar (`scheduler` e `horizon`) C20 | - |
| leitores de Changes underneath (8) | `stack_dispatch` C20 · `laravel-outbox.sh` C13, C20 · LV40 C21 · LV49 a LV51 C14 · Pest de `users` e `notifications` C19 · `composer.json`/`composer.lock` C14 · docs/stacks.md C21 · docs/decisions.md C22 | - |

## Swept

- validation: n/a - nenhuma entrada nova; a validação de `POST /users` continua provada no Pest e no RG do run infra (C19, C20)
- failure modes: C6, C10, C11
- idempotency: C16 - a mensagem repetida de um evento terminal não envia nem escreve
- authorization: n/a - nenhuma rota muda
- concurrency: C9 - trava, publicação e marcação na mesma transação; existing - OB20 e RG15 no run infra (C20)
- data lifecycle: n/a - o schema e os dados não mudam
- dependency failure: C16 - falha de SMTP; existing - OB21 no run infra (C11)
- state transitions: C1, C16
- observability: C11 - `outbox relay failed`; C16 - `outbox event not found`

## Handoff

- **Settled mid-build:** apagar o volume `cadastro-feliz-shared_postgres-data` e a rede para o run infra - user: "Pode apagar" (2026-11-10)
- **Dispatched:** Verifier at `77089e9` (2026-11-10) - returned, FAIL com 5 achados; 2 a 5 fechados em `3ab6f3b`
- **Boundary:** nenhuma check fechada. Código, testes Pest, testes de infra (OB11, LV40, LV49 a LV51, LV53, `stack_dispatch`) e docs escritos e sem commit, no branch `feat/laravel-modules-refactor`; `php -l` limpo. Falta: `make laravel-composer` para trocar `modules/outbox` por `modules/notifications` no `composer.lock`, depois `make test-laravel`, o run infra e `check_proofs.py`. Em `3ab6f3b`, `proofs.md` tem 35 provas verdes e só a C20 vermelha: LV7, LV24 e LV27 usam `stat -c` e `sed -i` do GNU, ausentes no macOS, em trechos que esta mudança não toca (log completo da rodada de `77089e9`: só essas três falhas). O achado 1 do Verifier fica aberto até a C20 rodar num ambiente com as ferramentas GNU (CI ubuntu ou `brew install coreutils gnu-sed`)
- **Abandoned:** os nomes de teste de C1 e C6, longos demais: com o tempo ao lado, o Pest os corta em ~66 colunas e a linha da prova não casaria; as linhas de prova foram encurtadas junto, sem mudar as afirmações
