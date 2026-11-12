# Banco de dados

> **Status:** em construção. O schema abaixo é aplicado pelas migrations `0001_create_users_and_users_outbox` e `0002_add_failure_notified_at_to_users_outbox`. A stack Laravel implementa as consultas abaixo, e a stack NestJS também; Go ainda vai implementá-las.

## Visão geral

As três APIs usam **um único banco e um único schema** em um só container PostgreSQL. Isso mantém as stacks intercambiáveis: um e-mail cadastrado por uma vale para as outras, e um evento pendente de uma stack pode ser enviado pela seguinte.

## Migrations

As migrations são **SQL puro** em `database/migrations`, e são a única fonte do schema. Um container `migrate`, de execução única, as aplica com o [golang-migrate](https://github.com/golang-migrate/migrate) antes de qualquer stack subir (`make migrate`, ou dentro de `make up-<stack>`).

- **Formato:** pares `NNNN_<nome>.up.sql` e `NNNN_<nome>.down.sql`, com numeração de quatro dígitos.
- **Controle:** a tabela `schema_migrations` pertence à ferramenta. Nenhuma stack lê nem escreve nela.
- **Atomicidade:** o golang-migrate não envolve o arquivo em uma transação, então cada arquivo começa com `BEGIN;` e termina com `COMMIT;`.

Se uma migration falha, a transação do arquivo é desfeita, mas a versão fica marcada como *dirty* e o migrate se recusa a continuar. Depois de corrigir o arquivo, volte a versão para a última aplicada com sucesso e rode `make migrate` de novo:

```bash
docker compose --profile tools run --rm migrate -path=/migrations -database="postgres://cadastro_feliz:cadastro_feliz@postgres:5432/cadastro_feliz?sslmode=disable" force 1
```

Nenhuma stack gerencia o schema:

- O Laravel não roda `artisan migrate` e não usa as migrations padrão do framework. Filas, cache e sessões não usam tabelas.
- O NestJS e o Go também não têm migrations próprias.

Essa regra evita que uma ferramenta altere tabelas que as outras duas stacks também usam.

## Schema

```mermaid
erDiagram
    users ||--o{ users_outbox : "gera"
    users {
        uuid id PK
        varchar name
        varchar email UK
        timestamptz created_at
        timestamptz updated_at
    }
    users_outbox {
        uuid id PK
        uuid user_id FK
        varchar event_type
        jsonb payload
        varchar status
        integer attempts
        text last_error
        timestamptz available_at
        timestamptz published_at
        timestamptz processed_at
        timestamptz created_at
        timestamptz failure_notified_at
    }
```

```sql
CREATE TABLE users (
    id         uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    name       varchar(255) NOT NULL,
    email      varchar(254) NOT NULL,
    created_at timestamptz  NOT NULL DEFAULT now(),
    updated_at timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT users_email_unique UNIQUE (email),
    CONSTRAINT users_email_lowercase CHECK (email = lower(email))
);

CREATE TABLE users_outbox (
    id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid         NOT NULL REFERENCES users (id),
    event_type   varchar(100) NOT NULL,
    payload      jsonb        NOT NULL,
    status       varchar(20)  NOT NULL DEFAULT 'pending',
    attempts     integer      NOT NULL DEFAULT 0,
    last_error   text,
    available_at timestamptz  NOT NULL DEFAULT now(),
    published_at timestamptz,
    processed_at timestamptz,
    created_at   timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT users_outbox_status_valid
        CHECK (status IN ('pending', 'published', 'processed', 'failed')),
    CONSTRAINT users_outbox_attempts_positive CHECK (attempts >= 0)
);

CREATE INDEX users_outbox_user_id_index
    ON users_outbox (user_id);

CREATE INDEX users_outbox_pending_index
    ON users_outbox (available_at) WHERE status = 'pending';

CREATE INDEX users_outbox_published_index
    ON users_outbox (published_at) WHERE status = 'published';
```

A `0002` acrescenta a marca do aviso de falha, nula em todo evento que ainda não entrou num resumo aceito pelo SMTP:

```sql
ALTER TABLE users_outbox ADD COLUMN failure_notified_at timestamptz;
```

Por que essas escolhas:

- **`users_email_lowercase`:** com três aplicações escrevendo na mesma tabela, a constraint garante que uma falha de normalização não crie duplicatas que diferem só por maiúsculas.
- **Índices parciais:** a tabela cresce com eventos `processed`, mas o relay só procura `pending` e `published`. Assim, os índices ficam pequenos e a busca continua rápida.
- **`failure_notified_at` sem índice:** só o resumo de falhas a lê, sobre poucos eventos `failed`. A limpeza de `processed` também percorre a tabela, o que basta à POC; um índice parcial em `processed_at` entra quando o volume pesar.

## Evento `user.registered`

```json
{
  "user_id": "0190f3a2-7c1e-7b3a-9d5e-2f4a6b8c0d1e",
  "name": "Ana Souza",
  "email": "ana@example.com",
  "occurred_at": "2026-11-04T12:00:00Z"
}
```

O `payload` tem o mesmo formato em todas as stacks, o que permite a uma stack processar eventos criados por outra. Ele guarda dados pessoais (LGPD), então os eventos `processed` concluídos há mais de `OUTBOX_RETENTION_DAYS` dias (padrão 7) são apagados, como em [Limpeza](#limpeza). Eventos em outros status ficam, e a POC não exclui usuários.

## Ciclo de status

```mermaid
stateDiagram-v2
    [*] --> pending: cadastro confirmado
    pending --> published: relay publica
    published --> published: relay republica após o tempo limite
    published --> processed: worker envia o e-mail
    published --> pending: falha com tentativas restantes
    published --> failed: falha na última tentativa
    pending --> processed: worker recebe mensagem repetida e envia
    pending --> failed: worker recebe mensagem repetida e falha
    failed --> pending: reprocessamento manual
    processed --> [*]: limpeza depois de OUTBOX_RETENTION_DAYS dias
```

| Status | Significado |
|---|---|
| `pending` | Aguardando publicação pelo relay, a partir de `available_at` |
| `published` | Publicado na fila, aguardando o worker |
| `processed` | E-mail enviado (estado terminal) |
| `failed` | Tentativas esgotadas (estado terminal) |

## Consultas principais

Estas consultas definem o comportamento esperado. Cada stack pode escrevê-las com a própria ferramenta, desde que o efeito seja o mesmo.

### Cadastro

```sql
BEGIN;

INSERT INTO users (name, email)
VALUES ($1, $2)
RETURNING id, name, email, created_at;

INSERT INTO users_outbox (user_id, event_type, payload)
VALUES ($3, 'user.registered', $4);

COMMIT;
```

### Busca do relay

```sql
SELECT id
FROM users_outbox
WHERE (status = 'pending' AND available_at <= now())
   OR (status = 'published' AND published_at <= now() - make_interval(secs => $1))
ORDER BY created_at
LIMIT $2
FOR UPDATE SKIP LOCKED;
```

Depois de publicar, na mesma transação:

```sql
UPDATE users_outbox
SET status = 'published', published_at = now()
WHERE id = ANY($1);
```

### Conclusão no worker

```sql
UPDATE users_outbox
SET status = 'processed', processed_at = now(), last_error = NULL
WHERE id = $1;
```

### Falha no worker

```sql
UPDATE users_outbox
SET attempts     = attempts + 1,
    last_error   = $2,
    status       = CASE WHEN attempts + 1 >= $3 THEN 'failed' ELSE 'pending' END,
    available_at = now() + make_interval(secs => $4 * power(2, attempts))
WHERE id = $1
  AND status NOT IN ('processed', 'failed');
```

Em `SET`, o PostgreSQL usa os valores anteriores da linha, então `attempts` nas expressões é o valor antes do incremento. A primeira falha espera `$4` segundos, e a segunda espera o dobro.

### Reprocessar um evento em `failed`

```sql
UPDATE users_outbox
SET status = 'pending', attempts = 0, available_at = now(), failure_notified_at = NULL
WHERE id = $1 AND status = 'failed';
```

Zerar `failure_notified_at` faz uma nova falha do mesmo evento entrar num novo resumo.

### Resumo de falhas

Só a stack Laravel envia o resumo, com o comando `outbox:notify-failed`, a cada 5 minutos. Ele lê os eventos `failed` ainda não avisados, sem travar linhas:

```sql
SELECT id, payload->>'email' AS email, attempts, last_error
FROM users_outbox
WHERE status = 'failed' AND failure_notified_at IS NULL
ORDER BY created_at
LIMIT $1;
```

Envia um único e-mail a `OUTBOX_ALERT_EMAIL` e, só depois de o SMTP aceitá-lo, marca os eventos que continuam `failed`:

```sql
UPDATE users_outbox
SET failure_notified_at = now()
WHERE id = ANY($1) AND status = 'failed' AND failure_notified_at IS NULL;
```

Se o envio falha, nada é marcado, e a execução seguinte tenta de novo. Um evento reprocessado entre a leitura e a marca já está `pending` e não é marcado. Com a stack NestJS ativa, os eventos `failed` esperam o primeiro resumo depois que a Laravel voltar.

### Limpeza

Só a stack Laravel limpa a tabela, com o comando `outbox:purge`, todo dia às 03:00 UTC:

```sql
DELETE FROM users_outbox
WHERE status = 'processed' AND processed_at < now() - make_interval(days => $1);
```

`$1` é `OUTBOX_RETENTION_DAYS`. Uma mensagem repetida de um evento já apagado encontra o evento inexistente, e o worker a ignora.
