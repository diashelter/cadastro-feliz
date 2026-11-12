# Limitador de cadastro sem Lua nas stacks Laravel e NestJS

**Approved**: 2026-11-12 - user: "Aprovar e seguir"

## Problem

O contador de tentativas e a cota por IP rodam três scripts Lua (`attempts`, `reserve` e `release`) copiados em cada stack e lidos do disco a cada requisição. A cópia é um contrato textual: `docs/api-contract.md` guarda os scripts, o RG16 de `tests/infra/registration.sh` compara byte a byte a cópia de cada stack com o documento, e o `limiter.sh` executa os blocos do documento no `redis-limiter`. Uma mudança no limitador passa por três lugares, mais a stack Go quando ela existir. Quem paga é quem mantém o projeto, e o responsável decidiu trocar esse arranjo pelo mecanismo nativo de cada stack (`.design/tests-per-stack.md`, Key decisions 2 e 3). A fonte não traz medição: o custo é de manutenção, não de volume.

Quando isto sair, nenhuma stack terá arquivo `.lua`. O cliente de `POST /users` vê exatamente as mesmas respostas de hoje: 201, 409, 422, 429 com `Retry-After` e 500. A cota continua sem passar de `REGISTRATION_MAX_PER_IP` com requisições paralelas, e nenhum contador fica sem expiração.

## Shape

Reusa as classes `RegistrationLimiter` (Laravel) e `RegistrationAttemptLimiter` (NestJS), com a mesma interface pública (contar a tentativa, reservar e devolver a cota), a regra de hash de `RegistrationKeys` e `registration-keys`, as conexões com o `redis-limiter` que já existem e os casos RG9 a RG18 de `tests/infra/registration.sh` como prova de comportamento nas duas stacks. As regras que mudam o resultado - comparar com o limite, desfazer o excedente, corrigir o negativo da devolução - ficam dentro dessas duas classes; o Pest e o Vitest as alcançam sem a stack no ar, e o comportamento contra o Redis real fica nos casos RG de `registration:laravel` e `registration:nest`.

1. `POST /users` -> `RegisterUser` / `UsersService` (exists) - normaliza o e-mail e chama o limitador antes da transação, sem mudança
2. `RegistrationLimiter` / `RegistrationAttemptLimiter` (exists) -> `redis-limiter` (exists) - incrementa o contador do par IP e e-mail com janela fixa de REGISTRATION_ATTEMPT_WINDOW_SECONDS (door 1); acima de REGISTRATION_MAX_ATTEMPTS, lança RegistrationLimited com os segundos restantes, no mínimo 1
3. `RegistrationLimiter` / `RegistrationAttemptLimiter` (exists) -> `redis-limiter` (exists) - incrementa a cota do IP com janela fixa de REGISTRATION_IP_WINDOW_SECONDS; acima de REGISTRATION_MAX_PER_IP, desfaz o próprio incremento e lança `RegistrationLimited` (door 2)
4. `RegisterUser` / `UsersService` (exists) -> `postgres` (exists) - grava `users` e `users_outbox` numa transação, sem mudança
5. `RegisterUser` / `UsersService` (exists) -> limitador -> `redis-limiter` - no 409 ou 500 depois da reserva, devolve uma unidade; se a devolução deixa o contador abaixo de zero (a janela expirou no meio), desfaz a devolução (door 2)
6. out: a mesma resposta HTTP de hoje

```mermaid
sequenceDiagram
    participant C as Cliente
    participant U as RegisterUser / UsersService
    participant L as RegistrationLimiter / RegistrationAttemptLimiter
    participant R as redis-limiter
    participant P as postgres
    C->>U: 1. POST /users
    U->>L: 2. conta a tentativa
    L->>R: 2. incrementa o par, janela fixa
    L-->>U: 2. RegistrationLimited acima do limite
    U->>L: 3. reserva a cota
    L->>R: 3. incrementa a cota; acima do limite, desfaz
    U->>P: 4. BEGIN · users · users_outbox · COMMIT
    U->>L: 5. 409/500 - devolve a unidade
    L->>R: 5. decrementa; abaixo de zero, desfaz
    U-->>C: 6. 201 / 409 / 422 / 429 / 500
```

**Changes underneath**

| Front | What changes |
| --- | --- |
| domain | As chaves do `redis-limiter` deixam de ser contrato entre as stacks: cada stack é dona do formato que grava, e o contador deixa de valer na troca de stack. A regra de hash continua igual (nenhum IP ou e-mail em claro). Quem dependia do contador comum: o SW3 e o SW4 de `tests/infra/stack-switch.sh`, e as frases de `docs/api-contract.md` que dizem que o limite vale na troca de stack |
| stored data | Na stack Laravel, o `RateLimiter` grava também uma chave `<chave>:timer` ao lado do contador. Os contadores já gravados no `redis-limiter` local são descartáveis e não migram: `make reset-limits` os limpa, e na pior das hipóteses um contador antigo faz um `Retry-After` maior por uma janela |
| readers | `tests/infra/limiter.sh` sai inteiro, junto com a entrada `limiter` de `run.sh` e das listas que o `stack.sh` confere; o RG16 sai de `registration.sh`, e `stack_lua_dir` sai dos adaptadores, de `run.sh` e da lista do `stack.sh`; o SW3 e o SW4 saem de `stack-switch.sh`. Os RG9 a RG15, RG17 e RG18 continuam e precisam passar nas duas stacks. Os mocks do limitador em `RegisterUserTest` e `RegisterUserUseCaseTest` não mudam, porque a interface pública é a mesma |
| docs | `docs/api-contract.md` (somem "Operação no Redis", "Scripts da cota", a menção a scripts em "Limite por IP" e as frases sobre a troca de stack; ficam o comportamento e a regra de hash), `docs/decisions.md` (uma decisão nova sobre o limitador sem Lua por stack, com as atualizações das decisões 5 e 17), `docs/stacks.md` (a árvore `lua/`) e `docs/architecture.md`, se alguma frase disser que o contador é comum |

Data: none - só contadores descartáveis no `redis-limiter`, sem tabela nem coluna.

## Surface

None - nothing consumed outside. `POST /users` mantém rota, corpo, códigos e `Retry-After`.

## Landing

| One-way door | Literal shape | Alternative rejected |
| --- | --- | --- |
| 1. Contador e cota deixam de ser comuns às stacks | Cada stack grava no `redis-limiter` no formato próprio; `docs/api-contract.md` descreve o comportamento (limites, janelas fixas, 429 com `Retry-After`, o que consome e o que devolve a cota) e a regra de hash, sem operação no Redis. Registrado como decisão nova em `docs/decisions.md` | Manter chave e operação como contrato, com comandos Redis iguais nas três stacks - rejeitado nesta sessão pelo responsável, que escolheu o mecanismo nativo de cada framework |
| 2. Padrão de reserva sem script: incrementar, comparar, desfazer | Reservar: incrementar e comparar o valor devolvido com o limite; acima dele, decrementar e recusar. Devolver: decrementar; abaixo de zero, incrementar de volta. Todo incremento ou decremento garante expiração na mesma operação, para nenhum contador ficar sem TTL. Laravel: `RateLimiter` sobre um cache store no `redis-limiter`, cujo `increment` já cria a chave com TTL. NestJS: comandos do ioredis em `MULTI` com `EXPIRE ... NX` | "Verificar e depois incrementar" (`RateLimiter::tooManyAttempts` + `hit`, ou `attempt`) - deixa N requisições paralelas passarem juntas; `@nestjs/throttler` - storage em memória e sem devolução de unidades |

- Nothing else in this change is hard to reverse

## Criteria

### S1: Contador de tentativas sem Lua (P1)

O par IP e e-mail continua limitado a `REGISTRATION_MAX_ATTEMPTS` por janela fixa, nas duas stacks, sem script.

**Acceptance Criteria**

1. The system SHALL have no `.lua` file under `apis/laravel` or `apis/nestjs`
2. WHEN the same IP and email post `POST /users` 6 times within `REGISTRATION_ATTEMPT_WINDOW_SECONDS` (900) THEN the system SHALL answer 201, then 409 four times, then 429 with `Retry-After` between 1 and 900, in both stacks
   - 1ª → 201; 5ª → 409; 6ª → 429; 7ª ainda na janela → 429
3. WHEN the attempt limit answers 429 THEN the system SHALL not read the database nor reserve quota
4. WHEN the attempt counter is created THEN the system SHALL give it an expiry of `REGISTRATION_ATTEMPT_WINDOW_SECONDS`, and later attempts in the window SHALL not renew it
   - 2ª tentativa 10 s depois da 1ª → o `Retry-After` do 429 nunca passa de 900 menos os segundos decorridos desde a 1ª
5. IF the remaining window rounds to 0 seconds THEN the system SHALL send `Retry-After: 1`
6. IF the `redis-limiter` is unreachable THEN the system SHALL answer 500 without writing `users` or `users_outbox`

### S2: Cota por IP sem Lua (P1)

A cota continua exata sob paralelismo, e só o 201 a consome.

**Acceptance Criteria**

7. WHEN an IP has completed `REGISTRATION_MAX_PER_IP` (20) registrations within `REGISTRATION_IP_WINDOW_SECONDS` THEN the system SHALL answer the next `POST /users` from it with 429 and `Retry-After` between 1 and 3600, without reading the database
   - 20º e-mail novo → 201; 21º → 429
8. WHEN N parallel `POST /users` with distinct new emails compete for the last K free units of an IP THEN the system SHALL answer exactly K of them with 201 and the rest with 429
   - 19 já usadas, 5 em paralelo → um 201 e quatro 429; depois disso o contador vale 20, não 24
9. WHEN a registration is refused by the quota THEN the system SHALL leave the quota counter at the value it had before that request
10. WHEN `POST /users` answers 409 or 500 after reserving THEN the system SHALL return the unit to the quota
    - 20 usadas por 19 cadastros e um 409 em curso → depois do 409, o próximo e-mail novo recebe 201
11. IF a return arrives after the quota window expired THEN the system SHALL leave no counter below zero and no counter without expiry
    - chave expirada antes da devolução → depois da devolução, a chave não existe ou vale 0 com TTL
12. IF a refused reservation finds the window expired before undoing THEN the system SHALL leave no counter below zero and no counter without expiry
13. The system SHALL give every quota counter it creates an expiry of `REGISTRATION_IP_WINDOW_SECONDS`, set only by the increment that creates it

### S3: Contrato e suíte alinhados (P1)

O que descrevia ou testava os scripts sai, e o resto da suíte continua verde nas duas stacks.

**Acceptance Criteria**

14. The system SHALL keep passing RG9 to RG15, RG17 and RG18 of `tests/infra/registration.sh` against `registration:laravel` and `registration:nest`
15. The `docs/api-contract.md` SHALL describe the attempt limit and the IP quota by behaviour and key hashing only, with no Redis script, no Redis operation and no claim that the limit holds across a stack switch
16. The `docs/decisions.md` SHALL record the limiter without Lua as a new decision, owned per stack, and the decisions 5 and 17 SHALL no longer say the key and the script are a contract between stacks
17. The `tests/infra` suite SHALL no longer contain `limiter.sh`, RG16, SW3, SW4 nor the adapter function `stack_lua_dir`, and `stack.sh`, `docs.sh` and `shared.sh` SHALL keep passing

## Out of scope

| Excluded | Why |
| --- | --- |
| Testes de integração dentro de cada API, contra Redis real | Slices `make test-<stack>`, Suíte Laravel e Suíte NestJS de `.design/tests-per-stack.md`; até lá, o comportamento contra Redis real é provado pelos RG |
| Remover o resto de `tests/infra` e mudar o CI | Slices Workflows por stack e Remoção de `tests/infra` |
| Stack Go | Sem compose; vai implementar o comportamento de `docs/api-contract.md` no formato dela |
| Não executar Lua nenhum no Redis | O `RedisStore::add` do Laravel 13.40 roda um script interno do framework; o pedido é tirar os scripts do projeto, não proibir o framework de usar os dele |
| Mudar limites, janelas, corpo do 429 ou a ordem de processamento | Decisões 4 e 17 continuam valendo |

## Assumptions

| Assumption | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Limitador da stack Laravel | `RateLimiter` do framework sobre um cache store próprio no `redis-limiter` | Escolha do responsável nesta sessão ("Limitador nativo do framework") | y |
| Limitador da stack NestJS | Comandos do ioredis, sem dependência nova | Escolha do responsável nesta sessão ("Comandos do ioredis (Recomendado)") | y |
| Devolução depois da janela expirar | Decrementar e, se o resultado ficar abaixo de zero, incrementar de volta | No Laravel 13.40, `RateLimiter::decrement` é `increment(-1)` precedido de `add(key, 0, ttl)`: nunca deixa a chave sem TTL, mas deixa -1, e a janela seguinte aceitaria 21. A correção ainda pode deixar um -1 transitório, se o processo cair entre os dois passos; ele vence com a janela | n |
| Prova das regras que só aparecem com a janela expirando no meio (criteria 11 e 12) | Pest com o `RateLimiter` sobre o cache store `array`, e Vitest com um dublê em memória do subconjunto de comandos do ioredis usado | Reproduzir a expiração entre dois comandos pelo HTTP não é determinístico; as versões contra Redis real entram nas suítes por stack (`.design/tests-per-stack.md`) | n |
| Nome das chaves | Mantém `registration:attempts:<sha256>` e `registration:ip:<sha256>`, sem prefixo de cache | Não há motivo para mudar, e `make reset-limits` continua limpando tudo; o formato só deixa de ser contrato | n |
| Onde fica a nova decisão | `docs/decisions.md`, como as anteriores, e não `.specs/STATE.md` | O projeto registra as decisões nesse arquivo | n |

**Open questions:** none - all resolved or logged above.

## Differences from the source

None - the product matches the source

## Sources

- `.design/tests-per-stack.md` - binding - slice `RegistrationLimiter`, Key decisions 2 e 3
- `docs/api-contract.md` › Limite por IP, Operação no Redis, Scripts da cota - o comportamento que continua e o contrato que sai
- `docs/decisions.md` - decisões 4, 5, 8 e 17
- laravel/framework v13.40.0, `Illuminate/Cache/RateLimiter.php` e `Illuminate/Cache/RedisStore.php` - `increment` com `add` e TTL, `decrement` como `increment` negativo, `RedisStore::decrement` como `DECRBY` simples
