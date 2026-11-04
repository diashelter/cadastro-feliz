# Cadastro Feliz

[![CI](https://github.com/diashelter/cadastro-feliz/actions/workflows/ci.yml/badge.svg)](https://github.com/diashelter/cadastro-feliz/actions/workflows/ci.yml)

Prova de conceito do padrão **Transactional Outbox**, com o mesmo caso de uso construído em três stacks: **Laravel**, **NestJS** e **Go**.

> **Status: em construção.** Os serviços compartilhados (`frontend`, `postgres`, `redis-limiter`, `mailpit` e `migrate`), o schema e o `Makefile` já funcionam. O formulário de cadastro já funciona e é testado por `make test-frontend`. Os testes do frontend e da infraestrutura rodam no [CI](docs/infrastructure.md#integração-contínua) a cada pull request e a cada push na `main`. A base da stack Laravel funciona: `make up-laravel` sobe `nginx` e `php-fpm`, e `GET /health` diz se o banco e o contador respondem. NestJS e Go ainda estão em design, e os comandos delas recusam com `stack <nome> ainda não implementada`.

## Caso de uso

Uma pessoa preenche nome e e-mail em um formulário público e recebe um e-mail informando que o cadastro foi concluído.

1. A pessoa envia o formulário.
2. A API grava o usuário e o evento de envio na mesma transação e responde `201`.
3. Um processo em segundo plano envia o e-mail de confirmação.

O cadastro depende só do PostgreSQL e do Redis que conta as tentativas. A fila e o servidor de e-mail podem estar fora do ar: se a API responde `201`, o evento está gravado e será processado quando eles voltarem.

## Arquitetura

O frontend, o banco, o contador de tentativas e a caixa de e-mail são comuns às três stacks. Só uma stack fica ativa por vez, sempre no mesmo endereço, então o frontend não precisa saber qual delas está respondendo.

```mermaid
flowchart LR
    browser["Navegador"]

    subgraph shared["Serviços compartilhados"]
        frontend["Frontend Next.js"]
        postgres[("PostgreSQL")]
        limiter[("redis-limiter")]
        mailpit["Mailpit"]
    end

    subgraph stack["Stack ativa: Laravel, NestJS ou Go"]
        api["API"]
        relay["Relay"]
        queue[["Fila"]]
        worker["Worker"]
    end

    browser -->|":3000"| frontend
    browser -->|"POST :8080/users"| api
    api -->|"conta tentativas"| limiter
    api -->|"users + users_outbox na mesma transação"| postgres
    relay -->|"busca eventos prontos"| postgres
    relay -->|"publica event_id"| queue
    queue --> worker
    worker -->|"atualiza o evento"| postgres
    worker -->|"SMTP"| mailpit
```

## Stacks

| Stack | Containers | Fila | Relay |
|---|---|---|---|
| **Laravel** | `nginx`, `php-fpm`, `scheduler`, `horizon`, `redis` | Horizon sobre Redis | Comando agendado a cada segundo |
| **NestJS** | `api`, `worker`, `redis` | BullMQ sobre Redis | Agendador de jobs do BullMQ |
| **Go** | `api`, `worker`, `rabbitmq` | RabbitMQ | Goroutine com ticker |
| **Compartilhados** | `frontend`, `postgres`, `redis-limiter`, `mailpit`, `migrate` | | |

O contador de tentativas fica no `redis-limiter`, comum às três stacks. O `redis` de Laravel e NestJS guarda apenas a fila.

## API

Todas as stacks expõem o mesmo endpoint: `POST /users`, com os campos `name` e `email`.

| Status | Quando |
|---|---|
| `201` | Cadastro gravado, com usuário e evento na mesma transação |
| `409` | E-mail já cadastrado |
| `422` | Dados inválidos, incluindo e-mail com formato inválido |
| `429` | Mais de 5 tentativas do mesmo IP com o mesmo e-mail em 15 minutos, ou mais de 20 cadastros por IP em uma hora; responde sem consultar o banco |
| `500` | Indisponibilidade da API |

Todas expõem também `GET /health`, que responde `200` quando o PostgreSQL e o `redis-limiter` respondem e `503` quando algum deles falha, com o mesmo corpo nos dois casos. Ver o [contrato](docs/api-contract.md#get-health).

## Como vai funcionar

> Por enquanto só a stack Laravel tem o próprio `docker-compose.yml`; os alvos de NestJS e Go recusam até terem o deles. `make up-shared` e `make migrate` sobem os serviços compartilhados com o schema aplicado, e o formulário responde em <http://localhost:3000>.

O único pré-requisito é Docker com Docker Compose 2.39 ou mais recente, além do `make`.

Subir os serviços compartilhados, o frontend incluído, e aplicar o schema. `make up-<stack>` não sobe o frontend, então rode `make up-shared` antes:

```bash
make up-shared
```

```bash
make migrate
```

Subir uma stack, que derruba antes qualquer outra ativa:

```bash
make up-laravel
```

```bash
make up-nest
```

```bash
make up-go
```

Derrubar uma stack, mantendo os serviços compartilhados:

```bash
make down-laravel
```

```bash
make down-nest
```

```bash
make down-go
```

Derrubar tudo:

```bash
make down
```

Ver os containers e acompanhar os logs de uma stack:

```bash
make status
```

```bash
make logs-laravel
```

Editar o frontend com recarga automática. O comando fica em primeiro plano copiando cada edição de `frontend/src` para o container; Ctrl+C encerra só a sincronização:

```bash
make watch-frontend
```

Acrescentar uma dependência ao frontend, sem Node na máquina:

```bash
make frontend-npm ARGS="install <pacote>"
```

Checar os tipos e rodar os testes do frontend, sem Node na máquina:

```bash
make test-frontend
```

Editar a stack Laravel com recarga automática. O comando sobe a stack como `make up-laravel` e fica em primeiro plano copiando cada edição para o container; Ctrl+C encerra só a sincronização:

```bash
make watch-laravel
```

Acrescentar uma dependência à stack Laravel, sem PHP nem Composer na máquina:

```bash
make laravel-composer ARGS="require <pacote>"
```

Rodar os testes da stack Laravel, sem PHP na máquina:

```bash
make test-laravel
```

Limpar os contadores de tentativas, para repetir testes do `429`:

```bash
make reset-limits
```

Testar a infraestrutura. Os testes destroem o ambiente `cadastro-feliz-*`, então recusam rodar se ele já existir:

```bash
make test-infra
```

### Endereços

| Serviço | Endereço | Disponível |
|---|---|---|
| Formulário | <http://localhost:3000> | Sempre |
| Caixa de e-mail (Mailpit) | <http://localhost:8025> | Sempre |
| API | <http://localhost:8080> | Com uma stack ativa |
| Saúde da API | <http://localhost:8080/health> | Com uma stack ativa |
| Painel do Horizon | <http://localhost:8080/horizon> | Só na stack Laravel |
| Painel do RabbitMQ | <http://localhost:15672> | Só na stack Go |

## Estrutura do repositório

```txt
cadastro-feliz/
├── README.md
├── Makefile
├── .env.example
├── docker-compose.yml        # serviços compartilhados
├── .github/workflows/        # CI: make test-frontend e tests/infra
├── database/migrations/      # schema canônico em SQL
├── tests/infra/              # testes da infraestrutura (make test-infra)
├── docs/
├── frontend/                 # Next.js em next dev, com o formulário
└── apis/
    ├── laravel/              # nginx, php-fpm e GET /health
    ├── nestjs/               # planejado
    └── golang/               # planejado
```

## Documentação

| Documento | Conteúdo |
|---|---|
| [Arquitetura](docs/architecture.md) | Outbox de ponta a ponta, garantias de entrega, retentativas, cenários de falha e de validação |
| [Contrato da API](docs/api-contract.md) | Ordem de processamento, respostas, limite de tentativas e mensagens do frontend |
| [Banco de dados](docs/database.md) | Schema, migrations, ciclo de status e consultas principais |
| [Stacks](docs/stacks.md) | Containers, funcionamento do outbox e estrutura de cada stack |
| [Infraestrutura](docs/infrastructure.md) | Compose, portas, Makefile, variáveis de ambiente e CI |
| [Decisões](docs/decisions.md) | Decisões de desenho e seus motivos |

## Limites conhecidos

- **E-mails duplicados:** a entrega é *at-least-once*, então uma queda no momento errado pode enviar o e-mail duas vezes.
- **Enumeração de e-mails:** o `409` revela que um e-mail já está cadastrado.
- **Bloqueio por quem divide o IP:** o limite conta o par IP e e-mail, então só quem está atrás do mesmo IP pode bloquear o cadastro de um e-mail alheio, por até 15 minutos.
- **Cota dividida por quem tem o mesmo IP:** pessoas atrás do mesmo IP dividem a cota de 20 cadastros por hora.
- **Ponto único de falha:** se o `redis-limiter` cair, nenhuma stack aceita cadastros até ele voltar.

Este projeto é uma POC de estudo e não está preparado para produção.
