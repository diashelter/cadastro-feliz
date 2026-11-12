# Limpeza e aviso de falhas de `users_outbox` na stack Laravel checks

Build: none - o repositório não tem build, lint nem type check além do que as provas exercem; a imagem e o boot do Laravel são provados por `make test-laravel` e pelo run infra
Run laravel: `make test-laravel`
Run infra: `bash tests/infra/run.sh docs migrate stack frontend outbox:laravel outbox:nest laravel-outbox`
Plan: `.specs/features/laravel-outbox-maintenance/plan.md`

24 checks in 3 slices · 2 one-way doors · 0 open, of which 0 block

## Checks

### S1 - `outbox:purge`

**C1** - `outbox:purge` apaga os `processed` com `processed_at` há 8 dias e há 7 dias e 1 min, mantém os de 6 dias e de 6 dias, 23 h e 59 min, imprime `2 event(s) purged.` e sai com `0` (AC 1)
Proof: run infra | PASS OM1 purge deletes processed events past retention

**C2** - `outbox:purge` mantém `pending`, `published` e `failed` criados há 30 dias, e o usuário cujo único evento foi apagado continua em `users` (AC 2)
Proof: run infra | PASS OM2 purge keeps other statuses and users

**C3** - Sem nada vencido, `outbox:purge` imprime `0 event(s) purged.`, sai com `0` e `users_outbox` fica igual (AC 3)
Proof: run infra | PASS OM3 purge with nothing due changes nothing
Proof: run laravel | ✓ it prints the purged count

**C4** - Com o `postgres` parado, `outbox:purge` sai com `1` e registra `outbox purge failed`; com o banco de volta, as linhas são as mesmas (AC 4)
Proof: run infra | PASS OM4 purge failure exits 1 and keeps rows
Proof: run laravel | ✓ it exits 1 and logs when the purge fails

**C5** - Com `OUTBOX_RETENTION_DAYS=1`, `outbox:purge` apaga o `processed` de 2 dias e mantém o de 12 h (AC 5)
Proof: run infra | PASS OM5 purge follows the retention days

**C6** - `schedule:list` no `scheduler` lista `outbox:purge` com `0 3 * * *` e `outbox:notify-failed` com `*/5 * * * *`, e `config('app.timezone')` é `UTC` (AC 6, AC 14)
Proof: run infra | PASS OM6 scheduler lists the maintenance commands

### S2 - `outbox:notify-failed`

**C7** - Com dois `failed` sem marca, Ana antes de Bia, `outbox:notify-failed` envia um e-mail a `ops@cadastro-feliz.local`, de `MAIL_FROM`, com o assunto `Cadastro Feliz: 2 evento(s) sem envio`, a linha de Ana antes da de Bia e o fecho de door 2, preenche `failure_notified_at` nos dois, imprime `2 failed event(s) notified.` e sai com `0` (AC 7)
Proof: run infra | PASS OM7 digest lists failed events and marks them
Proof: run laravel | ✓ it renders the digest subject, lines and footer
Proof: run laravel | ✓ it sends one digest and marks the listed events

**C8** - Com todo `failed` já marcado, `outbox:notify-failed` não envia e-mail, imprime `0 failed event(s) notified.` e sai com `0` (AC 8)
Proof: run infra | PASS OM8 second run sends no digest
Proof: run laravel | ✓ it sends and marks nothing when no event awaits notice

**C9** - Um `failed` avisado ontem, um `processed`, um `pending` e um `published` não geram e-mail nem mudam `failure_notified_at` (AC 9)
Proof: run infra | PASS OM9 digest skips other statuses and notified events

**C10** - Com o Mailpit parado, `outbox:notify-failed` sai com `1`, registra `outbox failed-events notification failed` e deixa `failure_notified_at` nula; com o Mailpit de volta, a execução seguinte envia um e-mail com o mesmo evento (AC 10)
Proof: run infra | PASS OM10 smtp down marks nothing and the next run sends
Proof: run laravel | ✓ it marks nothing when the digest fails
Proof: run laravel | ✓ it exits 1 and logs when the notification fails

**C11** - Com `OUTBOX_BATCH_SIZE=2` e três `failed`, o primeiro e-mail lista os dois mais antigos, o segundo o terceiro, e a terceira execução não envia nada (AC 11)
Proof: run infra | PASS OM11 batch size limits each digest

**C12** - Um reprocessamento que zera a marca e volta o evento a `pending`, confirmado depois da leitura e antes da marca, deixa o evento `pending` com `failure_notified_at` nula, e o e-mail enviado o lista (AC 12)
Proof: run infra | PASS OM12 event reprocessed mid-run stays unmarked

**C13** - O SQL da seção `Reprocessar um evento em failed` de docs/database.md, lido do documento, deixa um evento avisado `pending`, com `attempts` `0` e `failure_notified_at` nula; de volta a `failed`, a execução seguinte o lista (AC 13)
Proof: run infra | PASS OM13 documented reprocess clears the notice

**C14** - `php-fpm`, `scheduler` e `horizon` têm `OUTBOX_ALERT_EMAIL=ops@cadastro-feliz.local` e `OUTBOX_RETENTION_DAYS=7` no ambiente, e `.env.example` traz as duas com esses valores (AC 15)
Proof: run infra | PASS OM15 containers receive the maintenance variables

### S3 - Coluna `failure_notified_at` e registro

**C15** - Num banco vazio, `make migrate` deixa `failure_notified_at` como `timestamp with time zone`, nula e sem padrão, e `schema_migrations` em `2 f` (AC 16)
Proof: run infra | PASS C11 migrate on empty database
Proof: run infra | PASS OM16 migration 0002 adds failure_notified_at

**C16** - Num banco na versão 1 com uma linha em `users_outbox`, `make migrate` mantém a linha, com `failure_notified_at` nula, e rodar de novo não muda o schema (AC 17)
Proof: run infra | PASS OM17 migration 0002 keeps existing events
Proof: run infra | PASS C12 migrate rerun changes nothing

**C17** - Desfazer a `0002` remove só `failure_notified_at`, mantendo as linhas e as demais colunas de `users_outbox` (AC 18)
Proof: run infra | PASS OM18 migration 0002 down drops only the column

**C18** - `0002_add_failure_notified_at_to_users_outbox.up.sql` começa com `BEGIN;` e termina com `COMMIT;`, e o bloco de `## Schema` de docs/database.md continua igual ao corpo da `0001` (AC 19)
Proof: run infra | PASS OM19 migration 0002 file is wrapped in a transaction
Proof: run infra | PASS C10 migration 0001 equals docs schema

**C19** - docs/decisions.md tem a decisão 27 no índice e numa seção que cita `failure_notified_at`, o resumo ao operador, a limpeza diária e o aviso como evento descartado (AC 20)
Proof: run infra | PASS OM20 decision 27 recorded

**C20** - docs/database.md mostra `failure_notified_at` no erDiagram, traz o SQL de reprocessamento de door 1, cita `OUTBOX_RETENTION_DAYS` e não contém `Esta POC não faz limpeza` (AC 21)
Proof: run infra | PASS OM21 database docs describe retention and notice

**C21** - README › Limites conhecidos cita o resumo por e-mail e o reprocessamento manual de `failed`, e docs/infrastructure.md lista `OUTBOX_ALERT_EMAIL` com `ops@cadastro-feliz.local` e `OUTBOX_RETENTION_DAYS` com `7` (AC 22)
Proof: run infra | PASS OM22 readme and infrastructure docs describe the notice

### Leitores que mudam

**C22** - O OB13 continua achando o relay a cada segundo em `schedule:list` com as entradas novas; as sondas de migration falha passam a `0003_probe`: `make migrate` com ela sai com erro e marca `3 t`, e `make up-go` com ela não sobe a stack; o frontend quebrado não impede `make migrate`, com a versão `2 f` (Changes underneath)
Proof: run infra | PASS C14 failed migration rolls back and marks dirty
Proof: run infra | PASS C20 up-stack stops when migrate fails
Proof: run infra | PASS FE22 broken frontend does not block migrate or stack
Proof: run infra | PASS C13 migrate starts shared services
Proof: run infra | PASS C15 migrations down drop both tables
Proof: run infra | PASS OB13 scheduler image and schedule list

**C23** - Os casos de contrato de reprocessamento e de evento inexistente continuam passando nas duas stacks com a coluna no banco (Changes underneath)
Proof: run infra | PASS LM3 exhausted retries are recorded and recoverable
Proof: run infra | PASS OB32 missing event is ignored

**C24** - `make test-laravel` sai com `0`, sem PostgreSQL nem Redis
Proof: run laravel | Tests: passed

**C25** - Com `OUTBOX_RETENTION_DAYS` `0` ou negativo, `PurgeProcessedOutboxEvents` recusa sem apagar nada, e o compose entrega `7` e `ops@cadastro-feliz.local` quando o `.env` não traz as variáveis (AC 4, acrescentada no build: um `.env` criado antes desta rodada deixaria a retenção em `0` e a limpeza apagaria todo `processed`)
Proof: run laravel | ✓ it refuses a retention below one day
Proof: run infra | PASS OM23 compose defaults the maintenance variables

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| exemplos de AC 1 (4) | 8 dias C1 · 7 dias e 1 min C1 · 6 dias, 23 h e 59 min C1 · 6 dias C1 | - |
| status que a limpeza mantém (3) | `pending` C2 · `published` C2 · `failed` C2 | - |
| saídas de `outbox:purge` (3) | `<N>` com `0` C1 · `0` vazio C3 · `1` com o log C4 | - |
| saídas de `outbox:notify-failed` (3) | `<N>` com `0` C7 · `0` sem e-mail C8 · `1` com o log C10 | - |
| linhas que o resumo não lista (4) | `failed` marcado C9 · `processed` C9 · `pending` C9 · `published` C9 | - |
| exemplos de AC 11 (3) | 1º e-mail com 2 C11 · 2º com 1 C11 · 3º sem e-mail C11 | - |
| entradas agendadas (2) | `outbox:purge` `0 3 * * *` C6 · `outbox:notify-failed` `*/5 * * * *` C6 | - |
| containers que recebem as variáveis (3) | `php-fpm` C14 · `scheduler` C14 · `horizon` C14 | - |
| doors de Landing (2) | 1 coluna e reprocessamento C13, C15, C16, C17, C18, C20 · 2 aviso ao operador C7, C14, C21 | - |
| leitores de Changes underneath (8) | LM3 C23 · OB32 C23 · C11 a C13 de `migrate.sh` C15, C16, C22 · C14 de `migrate.sh` C22 · C15 de `migrate.sh` C22 · C20 de `stack.sh` C22 · FE22 C22 · NestJS LM3 e OB32 C23 | - |
| documentos (5) | docs/decisions.md C19 · docs/database.md C18, C20 · README C21 · docs/infrastructure.md C21 · `.env.example` C14 | - |

## Swept

- validation: n/a - os comandos não têm opções nem entrada; `OUTBOX_RETENTION_DAYS` e `OUTBOX_ALERT_EMAIL` vêm do `.env` (C5, C14)
- failure modes: C4, C10
- idempotency: C3, C8 - rodar de novo não apaga nem avisa outra vez
- authorization: n/a - nenhuma rota; os comandos só rodam dentro do container
- concurrency: C12 - reprocessamento entre a leitura e a marca; existing - `withoutOverlapping()` como em `outbox:relay`
- data lifecycle: C1, C2, C5, C16, C17
- dependency failure: C4 - banco fora; C10 - SMTP fora
- state transitions: C12, C13 - a marca só fica em `failed` e o reprocessamento a zera
- observability: C4 - `outbox purge failed`; C10 - `outbox failed-events notification failed`

## Handoff

- **Settled mid-build:** none
- **Dispatched:** none
- **Boundary:** nenhuma check fechada
- **Abandoned:** none
