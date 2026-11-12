# Limitador de cadastro sem Lua nas stacks Laravel e NestJS checks

Build: none - o repositório não tem build nem lint além do que as provas exercem; o type check da NestJS roda dentro de `make test-nest` (`tsc --noEmit` antes do Vitest)
Run laravel: `make test-laravel`
Run nest: `make test-nest`
Run contract-laravel: `bash tests/infra/run.sh registration:laravel`
Run contract-nest: `bash tests/infra/run.sh registration:nest`
Plan: `.specs/features/registration-limiter-native/plan.md`

17 checks in 3 slices · 2 one-way doors · 0 open, of which 0 block

## Checks

### S1 - Contador de tentativas sem Lua

**C1** - Nenhum arquivo `.lua` existe em `apis/laravel` nem em `apis/nestjs` (AC 1)
Proof: `test -z "$(git ls-files 'apis/laravel/*.lua' 'apis/nestjs/*.lua')"`

**C2** - O mesmo IP e e-mail recebem 201, quatro 409 e então 429 com `Retry-After` entre 1 e 900, nas duas stacks; a 7ª tentativa na janela também é 429 (AC 2)
Proof: run contract-laravel | PASS RG9 attempt limit sequence
Proof: run contract-nest | PASS RG9 attempt limit sequence
Proof: run laravel | ✓ refuses the sixth attempt in the window with the seconds left
Proof: run nest | ✓ registration-attempt-limiter.spec.ts refuses the sixth attempt in the window with the seconds left

**C3** - Um 429 do contador de tentativas não lê o banco nem reserva cota, nas duas stacks (AC 3)
Proof: run contract-laravel | PASS RG10 attempt limit never reads the database
Proof: run contract-nest | PASS RG10 attempt limit never reads the database

**C4** - A expiração do contador de tentativas é de 900 s, definida só pela primeira tentativa: com a 1ª em t e a 6ª em t+10 s, o `Retry-After` é no máximo 890 (AC 4)
Proof: run laravel | ✓ keeps the attempt window fixed from the first attempt
Proof: run nest | ✓ registration-attempt-limiter.spec.ts keeps the attempt window fixed from the first attempt

**C5** - Com a janela restante arredondada para 0 s, o `Retry-After` é 1 (AC 5)
Proof: run laravel | ✓ never answers a retry after below one second
Proof: run nest | ✓ registration-attempt-limiter.spec.ts never answers a retry after below one second

**C6** - Com o `redis-limiter` fora do ar, `POST /users` responde 500 sem gravar `users` nem `users_outbox`, nas duas stacks (AC 6)
Proof: run contract-laravel | PASS RG17 limiter down answers 500
Proof: run contract-nest | PASS RG17 limiter down answers 500

### S2 - Cota por IP sem Lua

**C7** - O 21º e-mail novo do mesmo IP na janela recebe 429 com `Retry-After` entre 1 e 3600, sem ler o banco, nas duas stacks (AC 7)
Proof: run contract-laravel | PASS RG13 ip quota
Proof: run contract-nest | PASS RG13 ip quota
Proof: run laravel | ✓ refuses the twenty-first reservation with the seconds left
Proof: run nest | ✓ registration-attempt-limiter.spec.ts refuses the twenty-first reservation with the seconds left

**C8** - Requisições paralelas que disputam as últimas unidades da cota recebem exatamente tantos 201 quanto as unidades livres, nas duas stacks (AC 8)
Proof: run contract-laravel | PASS RG15 ip quota holds in parallel
Proof: run contract-nest | PASS RG15 ip quota holds in parallel

**C9** - Uma reserva recusada deixa o contador da cota no valor de antes: 20 depois de quatro recusas, não 24 (AC 8, AC 9)
Proof: run laravel | ✓ leaves the quota at twenty after refused reservations
Proof: run nest | ✓ registration-attempt-limiter.spec.ts leaves the quota at twenty after refused reservations

**C10** - 409 ou 500 depois da reserva devolvem a unidade: o próximo e-mail novo recebe 201 (AC 10)
Proof: run contract-laravel | PASS RG14 conflict does not consume quota
Proof: run contract-nest | PASS RG14 conflict does not consume quota
Proof: run contract-laravel | PASS RG18 database down answers 500 and releases
Proof: run contract-nest | PASS RG18 database down answers 500 and releases
Proof: run laravel | ✓ returns a released unit to the quota
Proof: run nest | ✓ registration-attempt-limiter.spec.ts returns a released unit to the quota

**C11** - Uma devolução que chega depois de a janela da cota expirar não deixa contador abaixo de zero nem sem expiração, e a janela seguinte aceita 20 e recusa o 21º (AC 11)
Proof: run laravel | ✓ ignores a release that arrives after the quota window expired
Proof: run nest | ✓ registration-attempt-limiter.spec.ts ignores a release that arrives after the quota window expired

**C12** - Uma reserva recusada cuja janela expira antes de ser desfeita não deixa contador abaixo de zero nem sem expiração (AC 12)
Proof: run laravel | ✓ undoes an expired refused reservation without going negative
Proof: run nest | ✓ registration-attempt-limiter.spec.ts undoes an expired refused reservation without going negative

**C13** - Todo contador da cota recebe expiração de 3600 s no incremento que o cria, e reservas seguintes não a renovam: com a 1ª reserva em t e a recusa em t+100 s, o `Retry-After` é no máximo 3500 (AC 13)
Proof: run laravel | ✓ keeps the quota window fixed from the first reservation
Proof: run nest | ✓ registration-attempt-limiter.spec.ts keeps the quota window fixed from the first reservation
Proof: run nest | ✓ registration-attempt-limiter.spec.ts leaves no counter without an expiry

### S3 - Contrato e suíte alinhados

**C14** - O `X-Forwarded-For` continua ignorado e o limite continua por IP e e-mail, nas duas stacks (AC 14)
Proof: run contract-laravel | PASS RG11 forwarded for is ignored
Proof: run contract-nest | PASS RG11 forwarded for is ignored
Proof: run contract-laravel | PASS RG12 limit is per ip and email
Proof: run contract-nest | PASS RG12 limit is per ip and email

**C15** - `docs/api-contract.md` não tem script Lua, a seção "Operação no Redis", a seção "Scripts da cota" nem a afirmação de que o limite vale na troca de stack, e mantém a regra de hash e o exemplo das duas chaves (AC 15)
Proof: `! grep -nE '\x60\x60\x60lua|Operação no Redis|Scripts da cota|limite (continua valendo|deixa de valer) na troca de stack' docs/api-contract.md && grep -q 'registration:attempts:da657b591c8d33639918ea46be3b50e2bb1173313d08cf019556c130426a63a8' docs/api-contract.md && grep -q 'registration:ip:631f08140b24b7274d12df3c37a1a80ce5876dafd7007d772e0114fddf88b682' docs/api-contract.md`

**C16** - `docs/decisions.md` tem a decisão 28 sobre o limitador sem Lua por stack, e as decisões 5 e 17 não citam script nem Lua (AC 16)
Proof: `grep -q '^## 28\. ' docs/decisions.md && ! awk '/^## 5\./,/^## 6\./' docs/decisions.md | grep -qiE 'script|lua' && ! awk '/^## 17\./,/^## 18\./' docs/decisions.md | grep -qiE 'script|lua'`

**C17** - `tests/infra` não tem `limiter.sh`, RG16, SW3, SW4 nem `stack_lua_dir`, e as entradas `docs`, `shared`, `stack` e `stack-switch` passam (AC 17)
Proof: `test ! -e tests/infra/limiter.sh && ! grep -rqE 'stack_lua_dir|RG16|SW3|SW4' tests/infra && bash tests/infra/run.sh docs shared stack stack-switch`

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| stacks com limitador (2) | Laravel C2 C4 C5 C7 C9 C10 C11 C12 C13 · NestJS C2 C4 C5 C7 C9 C10 C11 C12 C13 | - |
| casos RG que continuam (9) | RG9 C2 · RG10 C3 · RG11 C14 · RG12 C14 · RG13 C7 · RG14 C10 · RG15 C8 · RG17 C6 · RG18 C10 | - |
| `POST /users` respostas que o limitador decide (3) | 429 do par C2 · 429 da cota C7 · 500 com `redis-limiter` fora C6 | - |
| AC 2 (3 examples) | 5ª → 409 C2 · 6ª → 429 C2 · 7ª → 429 C2 | - |
| AC 8 (2 examples) | um 201 e quatro 429 C8 · contador em 20, não 24 C9 | - |
| AC 11 (1 example) | chave expirada antes da devolução C11 | - |
| caminhos que decrementam a cota (2) | devolução no 409/500 C10 C11 · desfazer a reserva recusada C9 C12 | - |
| Landing doors (2) | door 1, contador por stack C15 C16 C17 · door 2, incrementar-comparar-desfazer C8 C9 C11 C12 | - |
| startup config: cache store `limiter` (2 assemblies) | app em execução C2 C6 (contract-laravel) · harness do Pest C4 | - |
| documentos que descreviam o contrato (2) | `docs/api-contract.md` C15 · `docs/decisions.md` C16 | - |

- Claims naming a status code or header: C2, C3, C6, C7, C8, C10, C14 - each has a proof that crosses `POST /users` against the real stack
- The rules that only show with a window expiring between two commands (C11, C12) are proven at the class level, as `## Assumptions` in the plan says

## Swept

- validation: existing - a validação do corpo vem antes do limitador e não muda (RG3 a RG5 continuam em `registration.sh`)
- failure modes: C10, C12
- idempotency: n/a - `POST /users` não tem chave de idempotência; a repetição é o 409 do contrato
- authorization: C2, C7, C14
- concurrency: C8, C9
- data lifecycle: C4, C11, C13
- dependency failure: C6
- state transitions: n/a - os contadores não têm estados, só valores
- observability: existing - a devolução que falha continua registrada como `registration quota not released`, sem mudança

## Handoff

- **Settled mid-build:** provas com Redis real rodam localmente, derrubando o ambiente - user: "Derrubar o ambiente local (Recomendado)"; o C17 é provado no CI, com o C9 de `shared.sh` corrigido para as 28 variáveis da decisão 27 - user: "Corrigir o C9 e provar no CI (Recomendado)"
- **Dispatched:** Verifier at `dca88ac` (proofs.md at `0ba6c24`; C17 proven in CI on PR diashelter/cadastro-feliz#16)
- **Boundary:** none yet
- **Abandoned:** none
- **Deviations:** os testes de C7 e C12 foram renomeados para nomes mais curtos, sem mudar a afirmação: o Pest cortava os nomes longos quando a largura do terminal era menor, e o check_proofs leu "no test ran". O ajudante `rg_quota_value` de `tests/infra` passou a ignorar a chave `<chave>:timer` que o `RateLimiter` grava, porque o RG14 e o RG18 liam o timestamp dela como se fosse a cota (door 1)
