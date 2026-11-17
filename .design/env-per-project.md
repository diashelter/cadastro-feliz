# Variáveis de ambiente por projeto

> Plan from this document. Each slice below carries its own shape - copy it, do not re-derive it.
> Status: confirmed by responsável do projeto, 2026-11-16 (decisão já tomada; registrada, sem veredito encenado)
> Nota, 2026-11-16: depois de fechado, a decisão 31 de docs/decisions.md substituiu este design nas APIs, que voltaram a ter `.env.example` e `.env` próprio; ele continua valendo para os serviços comuns da raiz.
> Nota, 2026-11-16: durante o build, a decisão 30 de docs/decisions.md removeu `tests/infra` e `make test-infra`. A slice `make test-infra` deixa de existir, e as Key decisions 2 e 5 valem como regras conferidas pelos checks da feature (.specs/features/env-per-project/checks.md), não por uma suíte de testes.

## Situation

- Project: in active construction. Laravel e NestJS sobem e passam em `make test-infra`; Go ainda não tem diretório.
- Decision: committed pelo responsável do projeto, 2026-11-16, nesta sessão. Inverte o default 2 de .design/shared-infrastructure.md, a Key decision 6 de .design/frontend-container.md (na parte que faz do `.env` da raiz a única fonte) e a Key decision 7 de .design/laravel-api-base.md.
- In flight: copia a ideia que o compose da Laravel já usa para `OUTBOX_RETENTION_DAYS` e `OUTBOX_ALERT_EMAIL`, um valor padrão escrito no próprio compose, e a generaliza para todas as variáveis. Nenhum branch aberto toca nesses arquivos.
- At stake: barato de reverter (só ambiente local, sem segredo real, sem dado), mas largo: o `Makefile`, os três composes e cerca de 40 pontos de `make test-infra` leem ou editam o `.env` da raiz. Errar custa uma tarde de testes quebrados, não dados.

## Problem

Construção, com dor já observada. O `.env` da raiz guarda as variáveis de todos os projetos (36 linhas, das quais `APP_KEY`, `APP_ENV`, `APP_DEBUG`, `REDIS_*` e `RABBITMQ_URL` só servem a uma ou duas stacks), então uma variável nova de uma stack mexe num arquivo comum a todas, na tabela da documentação e nos testes. O arquivo é copiado de `.env.example` uma única vez e nunca mais recebe o que entra depois: o `.env` desta máquina não tem `OUTBOX_RETENTION_DAYS` nem `OUTBOX_ALERT_EMAIL`, e o compose da Laravel precisou de um valor padrão só para que esse `.env` antigo não zerasse a retenção. Nenhuma stack pode ser entendida, nem receber valores próprios para um experimento, sem passar pela raiz. A stack Go vai entrar no mesmo arquivo se nada mudar.

## Success

- Worked if: num clone limpo, sem nenhum `.env` em lugar nenhum, `make up-shared`, `make up-laravel`, `make up-nest` e `make test-infra` passam; e a raiz não tem nenhuma variável de stack.
- Going wrong: um teste de uma stack precisa editar o arquivo de outro projeto, ou um compose resolve uma variável como vazia.
- Review: quando a stack Go for criada, por quem a criar. Ela deve entrar tocando só o diretório dela, a lista de stacks do `Makefile` e a tabela da documentação.

## Boundary

In: os três composes (`cadastro-feliz-shared`, `cadastro-feliz-laravel`, `cadastro-feliz-nest`), o `Makefile`, `make test-infra`, a seção Variáveis de ambiente de docs/infrastructure.md, o README onde cita `.env.example`, e o registro como decisão 29 em docs/decisions.md, com nota nos três designs cujas decisões ela substitui.

Out: a stack Go, que nasce já com esta regra. Segredos de produção e qualquer cofre de segredos, porque a POC não tem produção nem segredo real. Mover o frontend para um compose próprio, que mexeria em `make up-shared`, `make watch-frontend` e nos testes do frontend sem resolver nenhuma das dores acima.

Unchanged: nomes e valores padrão de todas as variáveis; portas, nomes de serviço, de projeto e de rede; os alvos do `Makefile`, menos `env`; o check FE12, já que `frontend/` continua sem `.env` próprio; o comportamento de Laravel e NestJS de não ler `.env` dentro do container.

## Shape

Cada projeto Compose declara as variáveis de que precisa, com o valor local padrão escrito no próprio compose e versionado, e um `.env` opcional e ignorado pelo git, ao lado desse compose, sobrescreve só aquele projeto. Não existe mais passo de cópia: `.env.example` e o alvo `make env` deixam de existir, e um clone limpo sobe tudo. A porta é a regra de que cada projeto é dono das próprias variáveis, que os testes passam a assumir ao trocar valores; desfazê-la depois é refazer esses testes de novo.

A forma mais pesada, um arquivo de padrões versionado por projeto (lido pelo Compose como arquivo de ambiente) mais o `.env` opcional, só ganha se algum projeto precisar dessas variáveis fora do Compose, por exemplo rodando o framework direto na máquina, e a POC roda só com Docker e `make` (motivos das decisões 16 e 20 de docs/decisions.md).

## Key decisions

1. **Cada projeto Compose declara as próprias variáveis, com um padrão local versionado, e nenhum `make` cria arquivo de ambiente.** Um clone limpo sobe qualquer projeto; uma variável nova chega pelo `git pull`, com o valor dela, e nunca mais existe um `.env` desatualizado que a deixe vazia.
2. **Toda variável interpolada num compose tem padrão nesse mesmo compose; um compose que resolveria uma variável como vazia é um teste falhando.** É o que transforma a exceção de hoje da Laravel (`OUTBOX_RETENTION_DAYS`) em regra, e é o que garante a decisão 1.
3. **O `.env` que sobrescreve um projeto fica ao lado do compose desse projeto, é opcional e ignorado pelo git, e nenhum outro projeto o enxerga.** O `.env` da raiz passa a sobrescrever só `cadastro-feliz-shared` (as credenciais do PostgreSQL e do migrate, e `NEXT_PUBLIC_API_URL`); nenhuma variável de stack mora na raiz. O Compose 5.6.1 já lê o `.env` do diretório do compose, não o de onde o comando é chamado, então o `Makefile` deixa de apontar um arquivo de ambiente.
4. **O `.env` de sobrescrita nunca entra numa imagem.** NestJS e frontend já o excluem do contexto de build; a Laravel copia o diretório inteiro e hoje levaria esse arquivo para o container, onde o próprio framework o leria. Não copie o `.dockerignore` da Laravel como está.
5. **Os padrões das regras de negócio (`REGISTRATION_*`, `OUTBOX_*`) fazem parte do contrato: o padrão versionado de cada stack é igual ao de docs/infrastructure.md › Regras de negócio, e `make test-infra` falha se uma stack divergir.** Sobrescrever localmente é livre, para experimentar; o padrão não é.
6. **Valores que vários projetos usam são declarados em cada um, de propósito.** As credenciais do banco (do PostgreSQL em `cadastro-feliz-shared`, da conexão em cada stack), a origem do CORS (`http://localhost:3000`) e a porta da API (`8080`) se repetem. Trocar um deles localmente é sobrescrever em cada projeto que o usa; é o preço de nenhum projeto depender de outro para subir.

## Work

| Slice | Delivers | Status |
|---|---|---|
| [cadastro-feliz-shared](#cadastro-feliz-shared) | Compose da raiz com padrões próprios, `.env` da raiz opcional e só dele, sem `.env.example` nem `make env` | clear |
| [cadastro-feliz-laravel](#cadastro-feliz-laravel) | Compose da Laravel com todos os padrões e sobrescrita por `.env` próprio, fora da imagem | clear |
| [cadastro-feliz-nest](#cadastro-feliz-nest) | Compose do NestJS com todos os padrões e sobrescrita por `.env` próprio | clear |
| [make test-infra](#make-test-infra) | Testes que trocam valores no projeto certo e checam as decisões 2, 3, 4 e 5 | open — 1 default taken |

Order: cadastro-feliz-shared → cadastro-feliz-laravel e cadastro-feliz-nest, em qualquer ordem → make test-infra. A documentação (docs/infrastructure.md por projeto, decisão 29, notas nos três designs) acompanha a primeira slice, porque os checks de docs.sh a leem.

Already handled by existing code: troca de stack sem recriar os serviços comuns → a regra `up-<stack>` do `Makefile`, que não muda; `.env` antigo e completo na raiz de quem já clonou → continua funcionando, porque `cadastro-feliz-shared` só lê dele as próprias variáveis e os valores são os mesmos dos padrões.

Derivable from the repository, left to the plan: a ordem das variáveis no compose e os comentários de cada grupo, como o bloco `x-app-env` já faz; a tabela de docs/infrastructure.md, agora com uma coluna de projeto, no formato das tabelas atuais.

### cadastro-feliz-shared

**Delivers** o compose da raiz com o padrão de cada variável dele, o `.env` da raiz como sobrescrita opcional só deste projeto, e o fim de `.env.example` e do alvo `make env`. **Status: clear.** Decisões 1, 2 e 3.

| State | What should happen | Caller sees |
|---|---|---|
| Clone limpo, nenhum `.env` | `make up-shared` sobe `postgres`, `redis-limiter`, `mailpit` e `frontend` com os padrões; nenhum arquivo é criado | Os serviços saudáveis, como hoje |
| `.env` na raiz com `NEXT_PUBLIC_API_URL` diferente | O frontend recria com o novo valor, sem rebuild (Key decision 6 de .design/frontend-container.md, que continua valendo) | O esqueleto mostra o novo endereço |
| `.env` na raiz com uma variável de stack | Nenhuma stack a recebe | Nada muda nas stacks |
| `make migrate` | Lê as credenciais deste projeto, as mesmas do `postgres` | As migrations aplicadas |

Alternatives considered: valores fixos no compose da raiz e `frontend/.env` próprio - ganha se o frontend virar um projeto Compose separado, o que está fora.

### cadastro-feliz-laravel

**Delivers** o compose da Laravel declarando o padrão de todas as variáveis de `php-fpm`, do Horizon e do scheduler, inclusive `APP_KEY`, `APP_ENV`, `APP_DEBUG`, `REDIS_*` e a porta publicada, sobrescritas por um `.env` opcional no diretório da stack. **Status: clear.** Decisões 1 a 5.

| State | What should happen | Caller sees |
|---|---|---|
| Clone limpo, `make up-laravel` | A stack sobe com os padrões do próprio compose | `GET /health` `200` |
| `.env` da Laravel com `REGISTRATION_MAX_ATTEMPTS=2` | Só a Laravel passa a recusar na terceira tentativa; o NestJS, se subir depois, usa o padrão do contrato | `429` na terceira tentativa, só nesta stack |
| `.env` da Laravel presente no build | O arquivo não chega à imagem; o framework continua sem ler `.env` dentro do container (Key decision 4) | Nenhuma diferença no comportamento |
| `.env` antigo na raiz com as variáveis da Laravel | Ignorado pela stack | Os padrões do compose da Laravel |

### cadastro-feliz-nest

**Delivers** o compose do NestJS declarando o padrão de todas as variáveis de `api` e `worker`, inclusive `REDIS_*` e a porta publicada, sobrescritas por um `.env` opcional no diretório da stack. **Status: clear.** Decisões 1, 2, 3 e 5.

| State | What should happen | Caller sees |
|---|---|---|
| Clone limpo, `make up-nest` | A stack sobe com os padrões do próprio compose | `GET /health` `200` |
| `.env` do NestJS com `OUTBOX_BATCH_SIZE=2` | Só o worker do NestJS processa em lotes de 2 | O lote menor, só nesta stack |
| `.env` da Laravel presente e `make up-nest` | O NestJS não o lê | Os padrões do NestJS |

### make test-infra

**Delivers** os testes trocando valores no `.env` do projeto que está sendo testado, em vez do da raiz, e checando as decisões novas. **Status: open — 1 default taken.**

| State | What should happen | Caller sees |
|---|---|---|
| Um teste de outbox ou de limite troca um valor da stack | Escreve no `.env` da stack em teste e recria só ela | `PASS`/`FAIL` por check, como hoje |
| Um teste troca `NEXT_PUBLIC_API_URL` ou `DB_PASSWORD` do `postgres` | Escreve no `.env` da raiz | Idem |
| Nenhum `.env` em lugar nenhum | Cada compose resolve todas as variáveis sem vazio (Key decision 2) | Um check por compose |
| Padrão de uma regra de negócio diverge entre uma stack e docs/infrastructure.md | O check falha nomeando a stack e a variável (Key decision 5) | `FAIL` |
| Sobrescrita na Laravel | O NestJS não a enxerga, e a imagem da Laravel não contém o arquivo (Key decisions 3 e 4) | Um check cada |
| Checks que hoje esperam que `make` crie o `.env` da raiz | Passam a esperar que nenhum `make` crie arquivo de ambiente (Key decision 1) | Os mesmos checks, invertidos |

1. Ao terminar, um teste que criou o `.env` de um projeto o apaga, para o próximo começar dos padrões - default: sim, como os testes já apagam o `.env` da raiz hoje.

## Sources

- .design/shared-infrastructure.md - default 2, o `.env.example` único na raiz, substituído aqui.
- .design/frontend-container.md - Key decision 6, `NEXT_PUBLIC_API_URL` lido ao iniciar o container; continua valendo, com a sobrescrita vindo do `.env` da raiz deste projeto.
- .design/laravel-api-base.md - Key decision 7, o `.env` da raiz como única fonte da Laravel, substituída aqui.
- docs/decisions.md - decisões 16 e 20, só Docker e `make` na máquina, o que tira a forma mais pesada do páreo.
- docs/infrastructure.md › Variáveis de ambiente - os nomes e os padrões, que não mudam.
