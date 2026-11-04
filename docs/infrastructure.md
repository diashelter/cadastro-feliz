# Infraestrutura

> **Status:** em construção. O `Makefile`, o `docker-compose.yml` dos serviços compartilhados e o `.env.example` existem e são testados por `make test-infra`. O serviço `frontend` e os composes das stacks ainda não existem.

Tudo roda em Docker. A única dependência na máquina é Docker com Docker Compose, além do `make`.

## Organização dos containers

Há dois grupos com ciclos de vida diferentes:

- **Serviços compartilhados:** `frontend`, `postgres`, `redis-limiter`, `mailpit` e `migrate`. Ficam no ar enquanto se troca de stack.
- **Stacks:** Laravel, NestJS e Go, cada uma com suas dependências. Só uma fica ativa por vez.

```mermaid
flowchart TB
    subgraph shared["Projeto cadastro-feliz-shared"]
        frontend["frontend :3000"]
        postgres[("postgres :5432")]
        limiter[("redis-limiter")]
        mailpit["mailpit :8025"]
        migrate["migrate (execução única)"]
    end
    subgraph active["Projeto da stack ativa"]
        api["API :8080"]
        deps["worker e fila"]
    end
    migrate --> postgres
    api --> postgres
    api --> limiter
    deps --> postgres
    deps --> mailpit
```

### Arquivos Compose

| Arquivo | Nome do projeto | Serviços |
|---|---|---|
| `docker-compose.yml` | `cadastro-feliz-shared` | `frontend`, `postgres`, `redis-limiter`, `mailpit`, `migrate` |
| `apis/laravel/docker-compose.yml` | `cadastro-feliz-laravel` | `nginx`, `php-fpm`, `scheduler`, `horizon`, `redis` |
| `apis/nestjs/docker-compose.yml` | `cadastro-feliz-nest` | `api`, `worker`, `redis` |
| `apis/golang/docker-compose.yml` | `cadastro-feliz-go` | `api`, `worker`, `rabbitmq` |

Os projetos são separados e se comunicam por uma rede externa, `cadastro-feliz-net`. Dessa forma, derrubar uma stack não afeta os serviços compartilhados.

### Uma stack por vez

As três publicam a API na mesma porta da máquina (8080), para o frontend usar sempre o mesmo endereço. Duas stacks não podem ocupar a mesma porta, então subir uma derruba antes a que estiver ativa.

### Dois tipos de Redis

Contador e fila ficam em instâncias separadas, porque têm necessidades opostas.

| | `redis-limiter` (compartilhado) | `redis` (Laravel e NestJS) |
|---|---|---|
| **Guarda** | Contador de tentativas | Fila da stack |
| **Se os dados se perderem** | O limite recomeça; nenhum evento se perde | O relay republica as mensagens depois do tempo limite |
| **Política de memória** | `volatile-ttl`, com limite baixo de memória | `noeviction`, exigida pelo BullMQ |
| **Persistência** | Nenhuma | Não necessária, pois a fonte da verdade é o PostgreSQL |
| **Se ficar indisponível** | A API retorna 500 | O e-mail atrasa; o cadastro continua |

A stack Go não tem `redis` próprio, porque a fila dela é o RabbitMQ.

## Portas

| Porta | Serviço | Disponível |
|---|---|---|
| 3000 | Formulário (`frontend`) | Sempre |
| 8025 | Caixa de e-mail (interface do Mailpit) | Sempre |
| 5432 | PostgreSQL | Sempre |
| 8080 | API | Quando há uma stack ativa |
| 15672 | Painel do RabbitMQ | Só na stack Go |

Dentro da rede Docker, o SMTP do Mailpit responde em `mailpit:1025` e o contador em `redis-limiter:6379`. Essas portas não precisam ser publicadas na máquina.

## Makefile

| Alvo | O que faz |
|---|---|
| `make up-shared` | Cria `.env` a partir de `.env.example` se ele não existir, cria a rede e sobe os serviços compartilhados, esperando que fiquem saudáveis |
| `make migrate` | Aplica as migrations pendentes; sobe os serviços compartilhados antes, se necessário |
| `make up-laravel` | Sobe a stack Laravel |
| `make up-nest` | Sobe a stack NestJS |
| `make up-go` | Sobe a stack Go |
| `make down-laravel` | Derruba a stack Laravel |
| `make down-nest` | Derruba a stack NestJS |
| `make down-go` | Derruba a stack Go |
| `make down` | Derruba as stacks e os serviços compartilhados |
| `make status` | Lista os containers do projeto e seu estado |
| `make logs-laravel`, `make logs-nest`, `make logs-go` | Acompanha os logs da stack |
| `make logs-shared` | Acompanha os logs dos serviços compartilhados |
| `make reset-limits` | Limpa os contadores de tentativas no `redis-limiter` |
| `make test-infra` | Testa a infraestrutura contra o Docker local. Destrói o ambiente `cadastro-feliz-*`, então recusa rodar se ele já existir |

Cada stack é um nome curto ligado a um diretório e a um projeto Compose: `laravel` usa `apis/laravel` e o projeto `cadastro-feliz-laravel`, `nest` usa `apis/nestjs` e `cadastro-feliz-nest`, `go` usa `apis/golang` e `cadastro-feliz-go`. Um alvo de stack sem compose recusa com `stack <nome> ainda não implementada`, e um nome fora dessa lista recusa com `stack <nome> desconhecida`, nos dois casos antes de alterar qualquer coisa. Para acrescentar uma stack, basta criar o compose dela, com `name: cadastro-feliz-<nome>` e a rede `cadastro-feliz-net` declarada como externa.

### Sequência de `make up-<stack>`

1. Cria `.env` e a rede externa, se ainda não existirem.
2. Derruba as outras stacks.
3. Sobe os serviços compartilhados e espera o PostgreSQL, o `redis-limiter` e o Mailpit ficarem saudáveis.
4. Executa o `migrate`. Se ele falha, o comando para com código diferente de zero e a stack não sobe.
5. Sobe a stack e espera seus containers ficarem no ar.

O Compose não ordena serviços de projetos diferentes, por isso essa ordem é responsabilidade do `Makefile`.

### Versões fixadas

| Serviço | Imagem |
|---|---|
| `postgres` | `postgres:18.6-alpine`, com o volume nomeado em `/var/lib/postgresql` |
| `redis-limiter` | `redis:8.10.3-alpine` |
| `mailpit` | `axllent/mailpit:v1.33.0` |
| `migrate` | `migrate/migrate:v4.20.1` |

### O que cada `down` faz com os dados

| Comando | Containers | Fila da stack | Contadores de tentativas | Dados do PostgreSQL |
|---|---|---|---|---|
| `make down-<stack>` | Remove os da stack | Descarta | Mantém | Mantém |
| `make down` | Remove todos | Descarta | Descarta | Mantém |

Descartar a fila é seguro porque a fonte da verdade é o PostgreSQL. O relay da próxima stack publica de novo o que estiver pendente. Os e-mails capturados pelo Mailpit são perdidos quando o container dele é removido, o que só ocorre em `make down`.

## Comunicação do frontend

O navegador chama a API diretamente em `http://localhost:8080`, sem passar pelo servidor Next.js. Isso deixa o status real de cada resposta visível nas ferramentas do navegador e permite ao frontend diferenciar uma falha de rede de um erro da API.

Como `localhost:3000` e `localhost:8080` são origens diferentes, cada API precisa configurar CORS:

- Liberar a origem de `CORS_ALLOWED_ORIGIN`.
- Aceitar `POST` e `OPTIONS`, com o header `Content-Type`.
- Expor o header `Retry-After`, usado na mensagem do 429.

## Variáveis de ambiente

Os valores abaixo são padrões para uso local, sem nenhum segredo real. Cada framework ainda terá variáveis próprias, como `APP_KEY` no Laravel.

### Compartilhadas

| Variável | Padrão | Uso |
|---|---|---|
| `API_PORT` | `8080` | Porta da API na máquina |
| `NEXT_PUBLIC_API_URL` | `http://localhost:8080` | Endereço da API usado pelo navegador |
| `CORS_ALLOWED_ORIGIN` | `http://localhost:3000` | Origem liberada pela API |
| `DB_HOST` | `postgres` | Host do banco |
| `DB_PORT` | `5432` | Porta do banco |
| `DB_DATABASE` | `cadastro_feliz` | Nome do banco |
| `DB_USERNAME` | `cadastro_feliz` | Usuário do banco |
| `DB_PASSWORD` | `cadastro_feliz` | Senha local do banco |
| `LIMITER_REDIS_HOST` | `redis-limiter` | Host do Redis do contador |
| `LIMITER_REDIS_PORT` | `6379` | Porta do Redis do contador |
| `SMTP_HOST` | `mailpit` | Host SMTP |
| `SMTP_PORT` | `1025` | Porta SMTP |
| `MAIL_FROM` | `no-reply@cadastro-feliz.local` | Remetente do e-mail |

### Regras de negócio

| Variável | Padrão | Uso |
|---|---|---|
| `REGISTRATION_MAX_ATTEMPTS` | `5` | Tentativas por e-mail na janela |
| `REGISTRATION_ATTEMPT_WINDOW_SECONDS` | `900` | Duração da janela (15 minutos) |
| `OUTBOX_BATCH_SIZE` | `100` | Eventos por execução do relay |
| `OUTBOX_REPUBLISH_AFTER_SECONDS` | `300` | Tempo em `published` antes de republicar |
| `OUTBOX_MAX_ATTEMPTS` | `5` | Falhas de envio antes de `failed` |
| `OUTBOX_BACKOFF_BASE_SECONDS` | `30` | Base do backoff exponencial |

### Específicas de stack

| Variável | Padrão | Stack |
|---|---|---|
| `REDIS_HOST` | `redis` | Laravel e NestJS (só a fila) |
| `REDIS_PORT` | `6379` | Laravel e NestJS (só a fila) |
| `RABBITMQ_URL` | `amqp://guest:guest@rabbitmq:5672/` | Go |
