# Limitador de cadastro sem Lua nas stacks Laravel e NestJS - verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at 0ba6c24
**Verifier**: independent sub-agent (author != verifier)

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | `test -z "$(git ls-files 'apis/laravel/*.lua' 'apis/nestjs/*.lua')"` | yes |
| C2 | `RegistrationLimiterTest.php` / `registration-attempt-limiter.spec.ts` `refuses the sixth attempt in the window with the seconds left`; `registration.sh` RG9 | yes |
| C3 | `registration.sh` `RG10 attempt limit never reads the database` | no - para o postgres e confere o 429, mas não olha a cota: "nem reserva cota" não é provado |
| C4 | `RegistrationLimiterTest.php` / `registration-attempt-limiter.spec.ts` `keeps the attempt window fixed from the first attempt` | no - só `1 <= Retry-After <= 890`: uma janela de 300 s ou um `Retry-After` constante 1 passam; a expiração de 900 s não é fixada |
| C5 | `RegistrationLimiterTest.php` / `registration-attempt-limiter.spec.ts` `never answers a retry after below one second` | yes |
| C6 | `registration.sh` `RG17 limiter down answers 500` | yes |
| C7 | `RegistrationLimiterTest.php` / `registration-attempt-limiter.spec.ts` `refuses the twenty-first reservation with the seconds left`; `registration.sh` RG13 | no - RG13 roda com o postgres no ar e conta `users`; "sem ler o banco" no 429 da cota não tem prova |
| C8 | `registration.sh` `RG15 ip quota holds in parallel` | no - parte de chave vazia e passa por sorte; no Laravel, `RateLimiter::increment` perde um incremento concorrente quando um contador vivo vai de 0 a 1 (VP1: 21 aceitos com cota 20) |
| C9 | `RegistrationLimiterTest.php` / `registration-attempt-limiter.spec.ts` `leaves the quota at twenty after refused reservations` | yes |
| C10 | `RegistrationLimiterTest.php` / `registration-attempt-limiter.spec.ts` `returns a released unit to the quota`; `registration.sh` RG14, RG18 | yes |
| C11 | `RegistrationLimiterTest.php` / `registration-attempt-limiter.spec.ts` `ignores a release that arrives after the quota window expired` | yes |
| C12 | `RegistrationLimiterTest.php` / `registration-attempt-limiter.spec.ts` `undoes an expired refused reservation without going negative` | yes |
| C13 | `RegistrationLimiterTest.php` / `registration-attempt-limiter.spec.ts` `keeps the quota window fixed from the first reservation`; `leaves no counter without an expiry` | no - Laravel: o teste nunca leva um contador vivo de 0 a 1, e aí o `put` do `RateLimiter` renova a expiração (VP2, VP4); NestJS segura |
| C14 | `registration.sh` RG11, RG12 | yes |
| C15 | `! grep -nE ... docs/api-contract.md && grep -q ... && grep -q ...` | yes |
| C16 | `grep -q '^## 28\. ' docs/decisions.md && ! awk ... && ! awk ...` | yes |
| C17 | `test ! -e tests/infra/limiter.sh && ! grep -rqE ... && bash tests/infra/run.sh docs shared stack stack-switch` | yes - a parte estática passa em 15383b3 e o CS8 não acha nome de stack; `run.sh` não foi rodado aqui, a prova estava vermelha em 0ba6c24 e `proofs.md` é anterior a 4fb7e59 e dca88ac |

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| Laravel: a cota passa de `REGISTRATION_MAX_PER_IP` com reservas sobrepostas (AC 8, door 2) | `RateLimiter::increment` (13.40) faz `add`, `add`, `INCRBY` e, se `! $added && $hits == $amount`, `put($key, $amount)`. Com o contador vivo em 0 (depois de um 409) ou na criação da janela, a reserva A recebe 1 do `INCRBY`, a B incrementa para 2, e o `SETEX 1` de A apaga o incremento de B. Teste descartável VP1 (ArrayStore com a B entre o `INCRBY` e o `put` de A): 21 reservas aceitas, cota 20. O mesmo vale para o contador de tentativas na criação da chave (uma tentativa a mais) | Trocar o `RateLimiter::increment` por `INCRBY` + `EXPIRE ... NX` + `TTL` numa transação na conexão `limiter`, como a NestJS (muda a Assumption confirmada, levar ao responsável); teste com a sobreposição de VP1 || de0e437 C8 - INCRBY, EXPIRE NX e TTL num só MULTI na conexão limiter; o RateLimiter saiu, e o RG15 prova contra Redis real |
| Laravel: reserva que leva um contador vivo de 0 a 1, e devolução que o acha em 0, renovam a expiração (AC 13; contrato "as devoluções não a renovam") | O mesmo `put` do `RateLimiter` regrava a chave com TTL cheio; o `:timer` não muda. VP2 e VP3: expiração 100 s depois da original. VP4: reserva em t, 409, 20 reservas em t+100, nova reserva em t+3650 é recusada com `Retry-After: 3600`, mas o contador morre em t+3700 - o `Retry-After` vem do `:timer` e não bate com o contador | Mesma correção do achado anterior; teste reserva -> devolução -> `travel(100)` -> reserva que confere a expiração e o `Retry-After` || de0e437 C13 - o teste agora reserva, devolve, avança 100 s e confere Retry-After 3500 nas duas stacks |
| Nenhum teste fixa o valor do `Retry-After` | C2, C4, C7 e C13 conferem só `1 <= Retry-After <= N`, e C5 confere 1: um limitador que sempre devolvesse 1, ou uma janela de 300 s, passa em todos, nas duas stacks, e no RG9; o RG13 não lê o `Retry-After`. Hoje o valor está certo (VP6 e VN7: 3500 depois de 100 s) | Com o relógio na mão do teste, conferir o valor exato: 900 e 890 no par, 3600 e 3500 na cota || de0e437 C2 C4 C7 C13 - os testes conferem 900, 890, 3600 e 3500 exatos; o RG13 lê o Retry-After |
| C3 não prova que o 429 do par não reserva cota | `registration.sh` RG10 só confere o status com o postgres parado | No RG10, conferir `rg_quota_value` = 1 depois do 429 || de0e437 C3 - o RG10 confere rg_quota_value = 1 depois do 429 |
| C7 não prova que o 429 da cota não lê o banco | `registration.sh` RG13 roda com o postgres no ar e só conta `users` | Parar o postgres antes do 21º no RG13, como o RG10 faz || de0e437 C7 - o RG13 para o postgres antes do 21º |
