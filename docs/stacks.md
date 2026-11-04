# Stacks

> **Status:** em construção. A [base da stack Laravel](#laravel) existe, com `nginx`, `php-fpm` e `GET /health`. NestJS e Go estão em design: as estruturas e os containers delas são planejados, e as versões serão fixadas na implementação. O [frontend](#frontend) já existe.

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
| `scheduler` | Roda `schedule:work`, que dispara o relay a cada segundo | Chega com o outbox |
| `horizon` | Consome a fila `registration-emails` e envia os e-mails | Chega com o outbox |
| `redis` | Fila do Horizon, com `noeviction` | Chega com o outbox |

**O que já existe.** `nginx` e `php-fpm` existem, com Laravel 13 sobre PHP 8.5, e o único endpoint é `GET /health`, que consulta o PostgreSQL e o `redis-limiter` ([contrato](api-contract.md#get-health)). `scheduler`, `horizon` e `redis` chegam com o outbox, porque sem o relay e o job não há o que rodar.

- **Edição:** `make watch-laravel` copia cada edição para o `php-fpm`, onde ela vale na próxima requisição. O código entra por cópia, nunca por bind mount (decisão 20 de [decisions.md](decisions.md)).
- **Dependências:** `make laravel-composer ARGS="<comando composer>"` é o único caminho, e só `composer.json` e `composer.lock` mudam na máquina.
- **Testes:** PHPUnit, em `apis/laravel/tests`, rodando com `make test-laravel` num container descartável.
- **Sem tabelas do framework:** sessão e cache em memória, fila `sync` até o outbox, log na saída de erro do container. `apis/laravel` não tem `.env`: as variáveis vêm do `.env` da raiz.

**Como o outbox funciona aqui**
- **Relay:** o comando `outbox:relay` é agendado com `everySecond()` e `withoutOverlapping()`. Ele faz a seleção do lote e o `dispatch` de `SendRegistrationEmailJob`.
- **Worker:** o job é processado pelo Horizon, com `$tries = 1`, porque as retentativas ficam no banco.

**Pontos de atenção**
- A documentação do Laravel recomenda que tarefas por segundo sejam rápidas e deleguem o trabalho pesado a jobs. O relay segue isso: só publica, e o SMTP fica no job.
- Remover o prefixo padrão `/api`, para a rota ser `/users`, e incluir essa rota na configuração de CORS.
- Manter `after_commit` desligado na conexão da fila, para o `dispatch` acontecer antes do commit do relay, como nas outras stacks.
- Sempre responder JSON nos erros, mesmo sem o header `Accept: application/json`.
- Não usar o formato de validação nativo, que traz `(and N more errors)` em `message` e só textos em `errors`. O corpo de erro segue a [forma do contrato](api-contract.md#forma-do-corpo-de-erro).
- Configurar duas conexões Redis: `default` para a fila e `limiter` para o `redis-limiter`, sem o prefixo automático do Laravel.
- Confiar só no `nginx` como proxy, para o IP do cliente usado no contador ser o que o `nginx` repassa. Ver [IP do cliente](api-contract.md#ip-do-cliente).
- Não usar o `RateLimiter` do framework no contador, porque ele grava com chave e formato próprios. O `RegistrationAttemptLimiter` executa o [script do contrato](api-contract.md#operação-no-redis).
- Não usar as migrations padrão. Ver [database.md](database.md#migrations).

Com a API no ar e em ambiente local, o painel do Horizon fica em `http://localhost:8080/horizon`.

```txt
apis/laravel/
├── docker-compose.yml
├── docker/
│   ├── nginx/default.conf
│   └── php/Dockerfile
├── routes/api.php            # rotas na raiz, sem /api
└── app/Modules/
    ├── Health/               # existe: GET /health
    │   ├── Checks/
    │   └── Http/Controllers/HealthController.php
    ├── Users/                # planejado
    │   ├── Actions/RegisterUserAction.php
    │   ├── Http/Controllers/UserController.php
    │   ├── Http/Requests/StoreUserRequest.php
    │   ├── Http/Resources/UserResource.php
    │   ├── Models/User.php
    │   └── Services/RegistrationAttemptLimiter.php
    └── Outbox/               # planejado
        ├── Console/RelayOutboxCommand.php
        ├── Jobs/SendRegistrationEmailJob.php
        ├── Mail/RegistrationCompletedMail.php
        └── Models/UserOutboxEvent.php
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

**Pontos de atenção**
- O `ValidationPipe` retorna 400 por padrão. É preciso configurá-lo para 422.
- Um filtro de exceções global deve produzir a [forma de erro do contrato](api-contract.md#forma-do-corpo-de-erro), com o `code` de cada erro de campo, inclusive para JSON malformado.
- A `api` só conecta ao `redis-limiter`, e o `worker` só conecta ao `redis`. Nos workers, o BullMQ precisa de `maxRetriesPerRequest: null`, para esperar o Redis voltar. Na conexão do contador, o oposto: a falha precisa ser rápida, para a API responder 500 sem segurar a requisição.

```txt
apis/nestjs/
├── docker-compose.yml
├── Dockerfile
└── src/
    ├── main.ts
    ├── worker.ts
    └── modules/
        ├── users/
        │   ├── users.controller.ts
        │   ├── users.service.ts
        │   ├── registration-attempt-limiter.service.ts
        │   └── dto/create-user.dto.ts
        ├── outbox/
        │   ├── outbox-relay.processor.ts
        │   └── outbox.repository.ts
        └── mail/
            ├── registration-email.processor.ts
            └── mail.service.ts
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
