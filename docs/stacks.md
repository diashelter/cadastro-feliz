# Stacks

> **Status:** em construção. A [stack Laravel](#laravel) existe, com `POST /users`, `GET /health`, o relay e o Horizon. A [stack NestJS](#nestjs) também existe, com `POST /users`, `GET /health`, o relay e o consumidor no `worker`. A stack Go está em design: a estrutura e os containers dela são planejados, e as versões serão fixadas na implementação. O [frontend](#frontend) já existe.

## Visão geral

O mesmo caso de uso é construído três vezes, com o mesmo [contrato de API](api-contract.md) e o mesmo [schema](database.md). Só muda a tecnologia que faz o trabalho.

| Papel | Laravel | NestJS | Go |
|---|---|---|---|
| API | `nginx` + `php-fpm` | `api` | `api` |
| Relay | Comando agendado no `scheduler` | Agendador de jobs do BullMQ no `worker` | Goroutine com ticker no `worker` |
| Fila | Redis | Redis (BullMQ) | RabbitMQ |
| Worker | Horizon | `worker` | `worker` |
| Contador de tentativas | `redis-limiter` (comum) | `redis-limiter` (comum) | `redis-limiter` (comum) |

## Laravel

| Container | Função | Estado |
|---|---|---|
| `nginx` | Publica a API na porta 8080 e encaminha para o `php-fpm` | Existe |
| `php-fpm` | Executa a API | Existe |
| `scheduler` | Roda `schedule:work`, que dispara o relay a cada segundo | Existe |
| `horizon` | Consome a fila `registration-emails` e envia os e-mails | Existe |
| `redis` | Fila do Horizon, com `noeviction` e sem persistência | Existe |

**O que já existe.** A stack roda Laravel 13 sobre PHP 8.5 e tem dois endpoints: [`GET /health`](api-contract.md#get-health) e `POST /users`, com validação, limites, forma única de erro e CORS. Cada cadastro grava em `users` e `users_outbox` na mesma transação, o `scheduler` publica o evento no `redis`, e o `horizon` envia o e-mail.

- **Módulos:** cada módulo é um pacote `modules/<nome>` em `app-modules`, carregado pelo `internachi/modular`, com o namespace `Modules\`. Nenhum módulo tem migrations (decisão 2).
- **Contextos:** `users` é o cadastro e é dono de `users_outbox`: grava o evento, roda o relay e é o único que escreve na tabela. `notifications` envia o e-mail de boas-vindas e só informa a `users` se o envio deu certo ou falhou. `notifications` se registra como consumidor de `user.registered`, e `users` nunca depende de `notifications` (decisão 26).
- **Casos de uso:** cada operação é uma classe em `src/UseCases`, com um método `execute`, que abre a própria transação; os repositórios só executam consultas. Status e tipos de evento ficam nos enums de `src/Enums`.

- **Edição:** `make watch-laravel` copia cada edição para o `php-fpm`, onde ela vale na próxima requisição, e reinicia o `horizon`, porque um worker de longa duração não recarrega o código. O código entra por cópia, nunca por bind mount (decisão 20 de [decisions.md](decisions.md)).
- **Dependências:** `make laravel-composer ARGS="<comando composer>"` é o único caminho, e só `composer.json` e `composer.lock` mudam na máquina.
- **Testes:** Pest, em `app-modules/<nome>/tests`, rodando com `make test-laravel` num container descartável, com dependências simuladas. O comportamento contra PostgreSQL, Redis e Mailpit reais fica em `tests/infra`.
- **Sem tabelas do framework:** sessão e cache em memória, fila no `redis`, falhas de job só no Horizon, log na saída de erro do container. `apis/laravel` não tem `.env`: as variáveis vêm do `.env` da raiz.

**Como o outbox funciona aqui**
- **Relay:** o comando `outbox:relay` é agendado com `everySecond()` e `withoutOverlapping()`, com a saída enviada ao log do container. Ele faz a seleção do lote e o `dispatch` do job que o consumidor de cada tipo registrou em `OutboxConsumers`, hoje `SendWelcomeEmailJob`; um tipo sem consumidor faz a rodada falhar sem publicar nada. O cache da stack é `array`, então `withoutOverlapping()` só vale dentro de um processo: quem impede duas execuções de publicar a mesma linha é o `SKIP LOCKED`.
- **Worker:** o job é processado pelo Horizon, com `$tries = 1`, porque as retentativas ficam no banco.
- **Limites de tempo:** 5 s do SMTP, 60 s do `timeout` do Horizon, 90 s do `retry_after` e 300 s de `OUTBOX_REPUBLISH_AFTER_SECONDS`, nessa ordem. Assim, um SMTP travado conta como tentativa, e um envio em andamento não é republicado.

**Pontos de atenção**
- A saída de uma tarefa agendada não chega a `docker logs` sem `appendOutputTo`.
- A documentação do Laravel recomenda que tarefas por segundo sejam rápidas e deleguem o trabalho pesado a jobs. O relay segue isso: só publica, e o SMTP fica no job.
- Remover o prefixo padrão `/api`, para a rota ser `/users`, e incluir essa rota na configuração de CORS.
- Manter `after_commit` desligado na conexão da fila, para o `dispatch` acontecer antes do commit do relay, como nas outras stacks.
- Sempre responder JSON nos erros, mesmo sem o header `Accept: application/json`.
- Não usar o formato de validação nativo, que traz `(and N more errors)` em `message` e só textos em `errors`. O corpo de erro segue a [forma do contrato](api-contract.md#forma-do-corpo-de-erro).
- Configurar duas conexões Redis: `default` para a fila e `limiter` para o `redis-limiter`, sem o prefixo automático do Laravel.
- Confiar só no `nginx` como proxy, para o IP do cliente usado no contador ser o que o `nginx` repassa. Ver [IP do cliente](api-contract.md#ip-do-cliente).
- Não usar o `RateLimiter` do framework no contador, porque ele grava com chave e formato próprios. O `RegistrationLimiter` executa o [script do contrato](api-contract.md#operação-no-redis).
- Não usar as migrations padrão. Ver [database.md](database.md#migrations).

Com a API no ar e em ambiente local, o painel do Horizon fica em `http://localhost:8080/horizon`.

```txt
apis/laravel/
├── docker-compose.yml
├── docker/
│   ├── nginx/default.conf
│   └── php/Dockerfile
└── app-modules/
    ├── health/               # GET /health
    │   ├── routes/health-routes.php
    │   ├── src/Checks/
    │   ├── src/Http/Controllers/HealthController.php
    │   └── tests/
    ├── notifications/        # o e-mail de boas-vindas, consumidor de user.registered
    │   ├── resources/views/
    │   ├── src/Jobs/SendWelcomeEmailJob.php
    │   ├── src/Mail/WelcomeMail.php
    │   ├── src/Providers/NotificationsServiceProvider.php
    │   ├── src/UseCases/SendWelcomeEmail.php
    │   └── tests/
    └── users/                # POST /users, os limites, users_outbox e o relay
        ├── resources/lua/    # cópias dos scripts do contrato
        ├── routes/users-routes.php
        ├── src/Console/Commands/RelayOutboxCommand.php
        ├── src/Enums/        # OutboxStatus e OutboxEventType
        ├── src/Http/Controllers/UserController.php
        ├── src/Http/Requests/StoreUserRequest.php
        ├── src/Models/       # User e UserOutboxEvent
        ├── src/Repositories/ # UserRepository e OutboxRepository
        ├── src/Services/     # RegistrationLimiter, RetryPolicy e OutboxConsumers
        ├── src/UseCases/     # RegisterUser e RelayOutboxEvents
        └── tests/
```

## NestJS

| Container | Função |
|---|---|
| `api` | Publica a API na porta 8080 |
| `worker` | Roda o relay e consome a fila `registration-emails` |
| `redis` | Filas do BullMQ, com `noeviction` |

**Como o outbox funciona aqui**
- **Relay:** o `worker` registra com `upsertJobScheduler` um job a cada 1000 ms na fila `outbox-relay`. Esse job seleciona o lote e adiciona os jobs em `registration-emails`.
- **Worker:** os jobs de `registration-emails` são criados sem retentativas automáticas, porque as retentativas ficam no banco.
- **Mesmo código, dois processos:** `api` e `worker` usam a mesma imagem, com entrypoints diferentes (`main.ts` e `worker.ts`).

**Relay e worker no mesmo container:** a `api` não importa nada de fila e não abre conexão com o `redis`; só o `worker` registra o `BullModule`. O consumidor de `registration-emails` roda cada mensagem uma vez, com `attempts` `1`, `maxStalledCount` `0` e lock de 30 s, e as retentativas ficam no banco. O `redis` da stack não tem persistência, então o `worker` registra de novo o agendador `outbox-relay` quando o `redis` volta vazio, e também quando o agendador fica sem próxima execução, o que acontece se o `worker` morre entre pegar uma execução e agendar a seguinte. Nos testes, parar o relay ou o worker é pausar a fila dele (decisão 23).

**Pontos de atenção**
- O `ValidationPipe` retorna 400 por padrão. É preciso configurá-lo para 422.
- Um filtro de exceções global deve produzir a [forma de erro do contrato](api-contract.md#forma-do-corpo-de-erro), com o `code` de cada erro de campo, inclusive para JSON malformado.
- A `api` só conecta ao `redis-limiter`, e o `worker` só conecta ao `redis`. Nos workers, o BullMQ precisa de `maxRetriesPerRequest: null`, para esperar o Redis voltar. Na conexão do contador, o oposto: a falha precisa ser rápida, para a API responder 500 sem segurar a requisição.

```txt
apis/nestjs/
├── docker-compose.yml        # api, worker, redis e a ferramenta npm
├── .dockerignore
├── .npmrc                    # save-exact
├── Dockerfile                # node 26.13.0, com o código por cópia
├── package.json              # versões exatas
├── package-lock.json
├── nest-cli.json             # watch compilado pelo SWC, sem checar tipos
├── tsconfig.json
├── tsconfig.build.json
├── vitest.config.mts         # Vitest com SWC (decisão 25)
└── src/
    ├── main.ts               # api: ApiModule, sem fila
    ├── worker.ts             # worker: WorkerModule, com o BullModule
    ├── api.module.ts
    ├── worker.module.ts
    ├── config.ts
    ├── database.ts           # TypeORM sem schema próprio (decisão 24)
    ├── queues.ts
    ├── http/
    │   ├── json-body.ts      # corpo malformado vira o 422 do contrato
    │   ├── validation.ts
    │   ├── validation.spec.ts
    │   ├── cors.ts
    │   └── contract-exception.filter.ts
    ├── scripts/              # usados por tests/infra
    │   ├── queue-control.ts
    │   └── relay-once.ts
    └── modules/
        ├── health/
        │   ├── health.module.ts
        │   └── health.controller.ts
        ├── users/            # só da api
        │   ├── users.module.ts
        │   ├── users.controller.ts
        │   ├── users.service.ts
        │   ├── registration-attempt-limiter.service.ts
        │   ├── registration-keys.ts
        │   ├── registration-keys.spec.ts
        │   ├── user.entity.ts
        │   ├── dto/create-user.dto.ts
        │   └── lua/          # cópias dos scripts de docs/api-contract.md
        │       ├── attempts.lua
        │       ├── reserve.lua
        │       └── release.lua
        ├── outbox/
        │   ├── outbox.module.ts          # importado pela api e pelo worker, sem fila
        │   ├── outbox.repository.ts
        │   ├── user-outbox-event.entity.ts
        │   ├── retry-delay.ts
        │   ├── retry-delay.spec.ts
        │   ├── outbox-relay.module.ts    # só do worker
        │   ├── outbox-relay.processor.ts
        │   └── relay-scheduler.service.ts
        └── mail/             # só do worker
            ├── mail.module.ts
            ├── registration-email.processor.ts
            ├── mail.service.ts
            ├── welcome-mail.ts
            ├── welcome-mail.spec.ts
            ├── welcome-job.ts
            └── welcome-job.spec.ts
```

## Go

| Container | Função |
|---|---|
| `api` | Publica a API na porta 8080 |
| `worker` | Roda o relay e o consumidor da fila em goroutines separadas |
| `rabbitmq` | Fila `registration-emails`, com painel de gestão na porta 15672 |

A stack Go não tem Redis próprio. A `api` só usa o `redis-limiter` para o contador.

**Como o outbox funciona aqui**
- **Relay:** uma goroutine com `time.Ticker` seleciona o lote e publica no RabbitMQ com *publisher confirms*. A transação só é confirmada depois que o broker aceita as mensagens.
- **Worker:** outra goroutine consome com ack manual. Em caso de falha, grava a retentativa no banco e confirma a mensagem, sem devolvê-la à fila.
- **Fila durável:** a fila e as mensagens são duráveis, então sobrevivem a um reinício do broker.

**Pontos de atenção**
- **Encerramento:** o `worker` precisa tratar o sinal de parada e concluir o job atual antes de sair.
- **Erros sem campo:** inicializar `errors` como lista vazia, porque uma lista nula sairia como `null` no JSON e quebraria a [forma do contrato](api-contract.md#forma-do-corpo-de-erro).

```txt
apis/golang/
├── docker-compose.yml
├── Dockerfile
├── cmd/
│   ├── api/main.go
│   └── worker/main.go
└── internal/
    ├── users/
    │   ├── handler.go
    │   ├── service.go
    │   ├── repository.go
    │   └── attempt_limiter.go
    ├── outbox/
    │   ├── relay.go
    │   └── repository.go
    └── mail/
        ├── consumer.go
        └── sender.go
```

## Frontend

Um único projeto Next.js atende às três stacks. Ele não tem lógica específica de nenhuma delas e aponta sempre para `http://localhost:8080`.

O container roda `next dev`, com o código copiado na imagem. Para editar com recarga automática, use `make watch-frontend`; para acrescentar uma dependência, `make frontend-npm ARGS="install <pacote>"`. Detalhes em [infrastructure.md](infrastructure.md#container-do-frontend).

A página `/` mostra o formulário de cadastro, que chama `POST /users` direto do navegador. O `registrationSchema` valida a forma das respostas de erro, não a entrada: o formulário não valida nada no navegador. Os testes usam Vitest com Testing Library e jsdom, ficam ao lado do código e rodam com `make test-frontend`, que também checa os tipos.

```txt
frontend/
├── Dockerfile
├── vitest.config.mts
└── src/
    ├── app/page.tsx
    └── modules/registration/
        ├── components/RegistrationForm.tsx
        ├── schemas/registrationSchema.ts
        ├── services/registrationService.ts
        └── types/registration.ts
```

## Estrutura do repositório

```txt
cadastro-feliz/
├── README.md
├── Makefile
├── .env.example
├── docker-compose.yml        # frontend, postgres, redis-limiter, mailpit e migrate
├── database/migrations/      # schema canônico em SQL
├── docs/
├── frontend/
└── apis/
    ├── laravel/
    ├── nestjs/
    └── golang/
```

## Testes previstos em cada stack

- **Saúde:** `GET /health` com `200` e com `503` para cada dependência, com o corpo do contrato.
- **Feature do endpoint:** 201, 409, 422, 429 e 500, com os corpos do contrato.
- **Atomicidade:** uma falha ao gravar o outbox não deixa usuário gravado.
- **Relay:** publica eventos prontos, ignora os que estão em espera e republica os expirados.
- **Worker:** marca `processed`, ignora eventos terminais, aplica backoff e chega a `failed`.

Os [cenários de validação](architecture.md#cenários-para-validar-a-implementação) cobrem o fluxo de ponta a ponta.

Toda stack é aceita pelos casos de contrato de `tests/infra`, em `registration.sh` e `outbox.sh`, por meio do próprio adaptador em `tests/infra/adapters`. Os casos internos de uma stack ficam num arquivo dela, como `laravel-outbox.sh` e `nest.sh` (decisão 23 de [decisions.md](decisions.md)), e `stack-switch.sh` troca entre Laravel e NestJS.
