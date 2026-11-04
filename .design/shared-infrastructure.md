# Infraestrutura dos serviços comuns

> Plan from this document. Each slice below carries its own shape - copy it, do not re-derive it.
> Status: decisão já tomada em docs/infrastructure.md e docs/decisions.md (responsável do projeto); forma confirmada pelo responsável do projeto, 2026-11-04

## Situation

- Project: in active construction. O repositório tem só documentação; nenhum código, compose ou Makefile existe ainda.
- Decision: committed. A forma geral (projetos Compose separados, rede externa `cadastro-feliz-net`, uma stack por vez, sequência de `make up-<stack>`, portas) está em docs/infrastructure.md e nas decisões 2, 6, 5 e 11 de docs/decisions.md.
- In flight: copia literalmente as tabelas de portas, variáveis e ciclo de vida dos dados de docs/infrastructure.md; ficam fora os composes das stacks e o código do frontend, que têm rodadas próprias.
- At stake: barato de reverter em quase tudo. A exceção é a ferramenta de migrations e a tabela de controle dela, que ficam no banco único que as três stacks leem.

## Problem

Construção. As três stacks foram prometidas como intercambiáveis sobre um banco, um contador e uma caixa de e-mail comuns (README, docs/architecture.md). Sem esses serviços no ar e sem o schema aplicado, nenhuma stack pode começar: a API não tem onde gravar `users` e `users_outbox`, nem onde contar tentativas, e o worker não tem para onde mandar o SMTP. Esta peça vem antes de qualquer stack porque todas dependem dela, e porque a sequência de troca de stack no Makefile é quase toda dos serviços comuns. Escrever essa sequência dentro da primeira stack faria a segunda reescrevê-la.

## Success

- Worked if: a partir de um clone limpo, `make up-shared` seguido de `make migrate` deixa `postgres`, `redis-limiter` e `mailpit` saudáveis, com `users` e `users_outbox` criadas exatamente como em docs/database.md, e a primeira stack a ser construída entra no Makefile acrescentando só o próprio `docker-compose.yml`.
- Going wrong: a primeira stack precisa editar o Makefile além da lista de stacks, ou o `make up-<stack>` sobe a stack com o migrate falhando.
- Review: quando a primeira stack for implementada, por quem a implementar.

## Boundary

In: `docker-compose.yml` da raiz (projeto `cadastro-feliz-shared`) com `postgres`, `redis-limiter`, `mailpit` e `migrate`; `.env.example`; `database/migrations` com a primeira migration; `Makefile` com os alvos comuns e a regra genérica de stack; registro da escolha do golang-migrate como decisão 14 em docs/decisions.md e atualização de docs/infrastructure.md e do README onde dizem que esses arquivos não existem.

Out: Dockerfile e serviço `frontend`, que entram com o código Next.js porque um Dockerfile sem o código que ele constrói não pode ser verificado. Composes e Dockerfiles das stacks, que pertencem à rodada de cada uma. Alvo para apagar o banco, que não está em docs/infrastructure.md e `docker volume rm` resolve.

Unchanged: portas, nomes de serviço, nomes de projeto, nome da rede e variáveis de docs/infrastructure.md. O SQL de docs/database.md, que entra sem alterações.

## Prior art

- Imagens oficiais em vez de Dockerfiles próprios para banco, Redis e caixa de e-mail: adotamos. Nenhum serviço comum desta rodada precisa de Dockerfile.
- Falha conhecida do golang-migrate: uma migration que falha no meio deixa o banco *dirty* e com o schema parcial, porque a ferramenta não envolve o arquivo em uma transação. A decisão 3 existe para evitar isso.
- Falha conhecida do PostgreSQL 18 em diante: o volume nomeado montado no caminho antigo (`/var/lib/postgresql/data`) não persiste nada. O volume vai no caminho que a imagem fixada declara.
- `depends_on` não atravessa projetos Compose. Quem ordena os serviços comuns e a stack é o Makefile (decisão 4).

## Shape

O projeto `cadastro-feliz-shared` roda três serviços de longa duração com imagens oficiais em versões fixas, e um `migrate` de execução única que aplica `database/migrations` com o golang-migrate. O Makefile cria a rede, ordena os projetos e é o único ponto que garante "migrate concluído antes de qualquer stack". A porta difícil de reabrir é a ferramenta de migrations: o formato dos arquivos e a tabela `schema_migrations` ficam no banco que as três stacks compartilham, e trocar de ferramenta depois exige migrar o controle de versão.

A alternativa mais pesada seria um compose único com `profiles` por stack. Ela só ganha se mais de uma stack precisar ficar no ar ao mesmo tempo, o que a decisão 6 de docs/decisions.md exclui.

## Key decisions

1. **Os serviços comuns usam imagens oficiais fixadas em versão exata, e nenhum deles tem Dockerfile nesta rodada.** Versões maiores: PostgreSQL 18, Redis 8, Mailpit 1.x e migrate 4.x. A tag exata (patch) é a mais recente disponível na implementação, conforme docs/stacks.md. O único Dockerfile comum previsto é o do `frontend`, que chega com o código dele.
2. **A rede `cadastro-feliz-net` é externa em todos os projetos, inclusive no comum, e só o Makefile a cria e remove.** Nenhum projeto Compose é dono dela, então derrubar qualquer projeto nunca a remove nem desconecta os outros.
3. **O schema muda só pelo golang-migrate, com pares `NNNN_<nome>.up.sql` e `NNNN_<nome>.down.sql` em `database/migrations` e controle na tabela `schema_migrations` do schema único. Cada arquivo é atômico por conta própria: abre e confirma a própria transação.** A ferramenta não faz isso sozinha. Uma falha ainda deixa a versão *dirty*: o schema volta ao estado anterior, mas o migrate se recusa a continuar até um `force` manual. Esse aviso precisa estar na documentação.
4. **Nenhuma stack sobe sem que o migrate tenha terminado com sucesso naquela execução de `make up-<stack>`. Se o migrate falha, o comando sai com código diferente de zero e a stack não é iniciada.** O Compose não consegue garantir isso entre projetos, então a responsabilidade é do Makefile.
5. **O ciclo de vida dos dados é o da tabela de docs/infrastructure.md.** O PostgreSQL usa um volume nomeado, que sobrevive a `make down`. O `redis-limiter` e o `mailpit` não têm volume nem persistência, então os contadores e os e-mails somem em `make down`.
6. **Os serviços comuns publicam na máquina só 3000 (reservada ao frontend), 8025 e 5432.** O SMTP (`mailpit:1025`) e o contador (`redis-limiter:6379`) ficam acessíveis apenas pela rede.
7. **Cada stack é identificada por um nome curto (`laravel`, `nest`, `go`) que aponta para o diretório (`apis/laravel`, `apis/nestjs`, `apis/golang`) e para o projeto `cadastro-feliz-<nome>`. Um alvo de stack cujo `docker-compose.yml` não existe recusa a execução antes de alterar qualquer coisa.** Para acrescentar uma stack, basta criar o arquivo dela.

## Work

| Slice | Delivers | Status |
|---|---|---|
| [cadastro-feliz-shared](#cadastro-feliz-shared) | `docker-compose.yml` da raiz e `.env.example`, com `postgres`, `redis-limiter` e `mailpit` saudáveis | open — 2 defaults taken |
| [migrate](#migrate) | Serviço `migrate` e a migration `0001_create_users_and_users_outbox` | clear |
| [Makefile](#makefile) | Alvos comuns e a regra genérica `up-`/`down-`/`logs-<stack>` | open — 3 defaults taken |

Order: cadastro-feliz-shared → migrate → Makefile.

Derivable from the repository, left to the plan: nomes de variáveis e valores padrão, como em docs/infrastructure.md › Variáveis de ambiente; healthchecks, com o comando de prontidão de cada imagem.

### cadastro-feliz-shared

**Delivers** o projeto Compose comum com os três serviços de longa duração e uma vaga reservada ao `frontend`. **Status: open.**

| State | What should happen |
|---|---|
| Primeira execução (sem volume nem `.env`) | O PostgreSQL inicializa o banco `cadastro_feliz` com usuário e senha do `.env`; os três serviços ficam saudáveis |
| Execução repetida com tudo no ar | Nada é recriado; os dados continuam |
| Porta 5432 ou 8025 ocupada na máquina | O Compose falha com o erro de porta; nenhum serviço fica parcialmente no ar como se estivesse saudável |
| `redis-limiter` atinge o limite de memória | Descarta as chaves com TTL mais próximo do fim (`volatile-ttl`), sem nunca recusar escrita |
| `mailpit` reiniciado | Os e-mails capturados se perdem (decisão 5) |

Serviços: `postgres` (volume nomeado, porta 5432), `redis-limiter` (`maxmemory 32mb`, `volatile-ttl`, sem RDB e sem AOF), `mailpit` (UI em 8025, SMTP em 1025 só na rede), `migrate` (slice seguinte). Todos estão na rede externa (decisão 2).

Alternatives considered: Valkey no lugar do Redis ganha se a licença do Redis 8 for um problema, o que não acontece em uma POC local.

1. Porta do PostgreSQL publicada fixa em 5432, como na documentação. Default: sem variável para trocar; uma variável entra se alguém tiver PostgreSQL local em conflito.
2. `.env.example` com todas as variáveis de docs/infrastructure.md, inclusive as de stack. Default: um único arquivo na raiz, que os composes das stacks também leem.

### migrate

**Delivers** o container de execução única que aplica `database/migrations` e a primeira migration. **Status: clear.** É a porta difícil de reabrir (decisão 3).

| State | What should happen |
|---|---|
| Banco vazio | Aplica a 0001; `users` e `users_outbox` existem com as constraints e índices de docs/database.md |
| Todas as migrations já aplicadas | Não faz nada e sai com sucesso |
| Migration com erro de SQL | A transação do arquivo é desfeita, a versão fica *dirty*, o processo sai com erro e o `make` para (decisão 4) |
| PostgreSQL ainda não saudável | O migrate espera ficar saudável antes de rodar |

Migration `0001_create_users_and_users_outbox`: o `.up.sql` é o SQL de docs/database.md › Schema sem nenhuma alteração; o `.down.sql` remove `users_outbox` e depois `users`. A tabela `schema_migrations` pertence à ferramenta, e nenhuma stack lê nem escreve nela.

### Makefile

**Delivers** todos os alvos de docs/infrastructure.md › Makefile, mais `up-shared`, `migrate` e `logs-shared`, com as stacks ligadas pela decisão 7. **Status: open.**

| State | What should happen |
|---|---|
| `make up-shared` em máquina limpa | Cria `.env` a partir de `.env.example` se não existir, cria a rede e sobe os serviços comuns esperando que fiquem saudáveis |
| `make migrate` | Aplica as migrations pendentes; sobe os serviços comuns antes, se necessário |
| `make up-<stack>` com o compose da stack ausente | Recusa com a mensagem `stack <nome> ainda não implementada` antes de criar a rede ou derrubar qualquer coisa |
| `make up-<stack>` com outra stack ativa | Segue a sequência de docs/infrastructure.md: rede, derruba as outras, comuns saudáveis, migrate, stack saudável |
| Migrate falha dentro de `make up-<stack>` | Para ali, com código diferente de zero; a stack não sobe (decisão 4) |
| `make down-<stack>` | Remove os containers e a fila da stack; contadores e banco continuam |
| `make down` | Derruba todas as stacks existentes e os comuns; o volume do PostgreSQL continua |
| `make reset-limits` | Esvazia o `redis-limiter`, que só guarda contadores |
| `make status` | Lista os containers de todos os projetos `cadastro-feliz-*` |

1. `make down` também remove a rede `cadastro-feliz-net`. Default: sim, porque nada mais a usa.
2. Nome do alvo que sobe só os serviços comuns. Default: `up-shared`, por simetria com o projeto `cadastro-feliz-shared`.
3. `make up-<stack>` não reconstrói imagens a cada execução. Default: reconstrói só quando o Compose detecta mudança.

## Sources

- docs/infrastructure.md: projetos, rede, portas, Makefile, ciclo de vida dos dados e variáveis.
- docs/database.md: schema da migration 0001 e regra de migrations em SQL puro.
- docs/decisions.md: decisões 2, 5, 6 e 11.
- docs/stacks.md: versões fixadas na implementação; estrutura do repositório.
- golang-migrate (GETTING_STARTED, FAQ, driver postgres): estado *dirty*, `force` e ausência de transação automática.
- docker-library/postgres: `VOLUME` em `/var/lib/postgresql` a partir da versão 18.
- Mailpit Dockerfile: healthcheck `readyz` embutido.
- Docker Compose (`up --wait`, `service_completed_successfully`).
