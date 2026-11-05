# Cadastro e e-mail de boas-vindas na stack Laravel, sem outbox checks

Build: none - o repositório não tem build, lint nem type check além do que as provas exercem; a imagem e o boot do Laravel são provados por LV1
Run laravel: `make test-laravel`
Run infra: `bash tests/infra/run.sh`
Plan: `.specs/features/laravel-registration-email/plan.md`

69 checks in 8 slices · 9 one-way doors · 0 open, of which 0 block

## Checks

### S1 - CI verde e `/health` dentro do limite

**C1** - `C9` confere as 26 linhas de docs/infrastructure.md › Variáveis de ambiente contra `.env.example` (AC 1)
Proof: run infra | PASS C9 env example matches docs

**C2** - Com o `postgres` parado, `/health` responde `503` com o corpo exato de `database` em `fail`, em menos de 3 s (AC 2)
Proof: run infra | PASS LV15 health 503 when postgres stopped

**C3** - Com o `redis-limiter` parado, `/health` responde `503` com o corpo exato de `limiter` em `fail`, em menos de 3 s (AC 3)
Proof: run infra | PASS LV14 health 503 when limiter stopped

**C4** - Com os dois parados, `/health` responde `503` com os dois checks em `fail`, em menos de 3 s (AC 4)
Proof: run infra | PASS LV16 health 503 when both stopped

**C5** - Com o `postgres` parado, o log do `php-fpm` tem `health check database`, e o corpo tem só as chaves `status` e `checks` (AC 5)
Proof: run infra | PASS LV18 failed check is logged not returned

**C6** - `make test-frontend`, `make test-laravel` e `bash tests/infra/run.sh` saem com `0` (AC 6)
Proof: make test-frontend
Proof: make test-laravel
Proof: run infra | test-infra: todos os testes passaram

### S2 - Testes em Pest

**C7** - `composer.lock` trava `pestphp/pest` `v5.3.5`, `pestphp/pest-plugin-laravel` `v5.0.1` e `phpunit/phpunit` na série 13 (AC 7)
Proof: run infra | PASS LV46 pest versions locked

**C8** - Um teste `it()` falho em `apis/laravel/tests/Feature` faz `make test-laravel` sair diferente de zero, imprimindo o nome dele (AC 8)
Proof: run infra | PASS LV32 test-laravel fails on failing test

**C9** - Um teste `it()` falho em `apis/laravel/app-modules/health/tests` faz `make test-laravel` sair diferente de zero, imprimindo o nome dele (AC 9)
Proof: run infra | PASS LV47 test-laravel runs module tests

**C10** - `make test-laravel` sem nenhum container sai com `0`, sem deixar container nem rede (AC 10)
Proof: run infra | PASS LV31 test-laravel passes without dependencies

**C11** - Os testes de `/health` são Pest, em `app-modules/health/tests`, e cobrem `200` e os três `503`, cada um com corpo, `Content-Type` e `no-store` (AC 11)
Proof: run infra | PASS LV48 health tests are pest in the module
Proof: run laravel | ✓ it returns ok when both checks pass
Proof: run laravel | ✓ it returns 503 when database fails
Proof: run laravel | ✓ it returns 503 when limiter fails
Proof: run laravel | ✓ it returns 503 when both checks fail

### S3 - Módulos com `internachi/modular`

**C12** - `composer.lock` trava `internachi/modular` `3.0.2` e tem `modules/health` e `modules/users` de `app-modules` (AC 12)
Proof: run infra | PASS LV49 modular locked with local modules

**C13** - `app/Modules` e `routes/api.php` não existem, e `app-modules/health` e `app-modules/users` têm `composer.json` e `src` (AC 13)
Proof: run infra | PASS LV50 modules layout

**C14** - Em clone limpo, `/health` responde `200` com o corpo de hoje, sem `Set-Cookie`, e `vendor/modules/health` existe no `php-fpm` (AC 14)
Proof: run infra | PASS LV1 up-laravel on clean clone
Proof: run infra | PASS LV13 health ok with real dependencies
Proof: run infra | PASS LV51 image resolves local modules

**C15** - Com o watch, uma rota e uma classe novas em `app-modules/users` respondem em até 10 s, com o mesmo ID do `php-fpm` (AC 15)
Proof: run infra | PASS LV24 watch syncs code without restart

**C16** - `make laravel-composer` com módulos, por um uid não root, muda só `composer.json` e `composer.lock`, e `vendor` não aparece (AC 16)
Proof: run infra | PASS LV27 laravel-composer writes only json and lock

**C17** - Nenhum módulo tem `database/migrations`, e `apis/laravel` continua sem `database/migrations` (AC 17)
Proof: run infra | PASS LV10 no vendor env or migrations in repo

**C18** - `route:list` no `php-fpm`: fora de `horizon`, as rotas são exatamente `health` e `users` (AC 18)
Proof: run infra | PASS LV44 api routes are health users and horizon

### S4 - `POST /users`

**C19** - `{"name":"Ana Souza","email":"ana@example.com"}` responde `201` com `data.id` UUID, nome, e-mail, `created_at` em `YYYY-MM-DDTHH:MM:SSZ` e `message` `User registered successfully.` (AC 19)
Proof: run infra | PASS RG1 post users created body
Proof: run laravel | ✓ it answers 201 and publishes the job

**C20** - `{"name":"  Ana  ","email":"  ANA@Example.COM "}` grava `Ana` e `ana@example.com`, e `users_outbox` fica sem linhas (AC 20)
Proof: run infra | PASS RG2 post users normalizes and skips outbox

**C21** - Cada regra responde `422` com a `message` e o item canônicos: `name` ausente, `""`, `"   "`, `123` e 256 caracteres; `email` ausente, `""`, `123`, `não-é-email`, `ana@` e 255 caracteres; `name` com 255 e `email` com 254 respondem `201` (AC 21)
Proof: run infra | PASS RG3 post users validation table
Proof: run laravel | ✓ it answers 422 for each field rule

**C22** - JSON malformado responde `422` com `required` em `name` e em `email` (AC 22)
Proof: run infra | PASS RG4 post users malformed json

**C23** - Um `422` deixa `users` e as chaves do `redis-limiter` como antes (AC 23)
Proof: run infra | PASS RG5 invalid body touches nothing

**C24** - Campos extras são ignorados, com `201` (AC 24)
Proof: run infra | PASS RG6 extra fields are ignored

**C25** - E-mail repetido, inclusive em outra caixa, responde `409` com `already_taken` e a mensagem canônica, sem linha nova e sem job novo (AC 25)
Proof: run infra | PASS RG7 repeated email conflicts
Proof: run laravel | ✓ it answers 409 when the email is taken and releases the quota

**C26** - Dois `POST` paralelos com o mesmo e-mail novo dão um `201`, um `409` e uma linha (AC 26)
Proof: run infra | PASS RG8 parallel same email

**C27** - O mesmo IP e e-mail 6 vezes dão `201`, quatro `409` e `429` com `Retry-After` entre 1 e 900, a mensagem canônica e `errors` `[]` (AC 27)
Proof: run infra | PASS RG9 attempt limit sequence
Proof: run laravel | ✓ it answers 429 with retry after when the attempts are exceeded

**C28** - Com o par já acima do limite e o `postgres` parado, a resposta é `429`, não `500` (AC 28)
Proof: run infra | PASS RG10 attempt limit never reads the database

**C29** - As chaves são as do contrato, com o IP canônico: os dois exemplos, `::ffff:203.0.113.10` nas mesmas chaves e `2001:DB8:0:0::1` no hash de `2001:db8::1` (AC 29)
Proof: run laravel | ✓ it builds the attempt key from the contract example
Proof: run laravel | ✓ it builds the quota key from the contract example
Proof: run laravel | ✓ it maps an ipv4 mapped address to the same keys
Proof: run laravel | ✓ it compresses and lowers an ipv6 address

**C30** - 6 tentativas com valores diferentes de `X-Forwarded-For`: a 6ª responde `429` (AC 30)
Proof: run infra | PASS RG11 forwarded for is ignored

**C31** - Um e-mail bloqueado em um IP não responde `429` a partir de outro IP (AC 31)
Proof: run infra | PASS RG12 limit is per ip and email

**C32** - 21 e-mails novos do mesmo IP: 20 `201`, o 21º `429` e 20 linhas novas (AC 32)
Proof: run infra | PASS RG13 ip quota

**C33** - E-mail já cadastrado com cota livre responde `409`, e o valor de `registration:ip:<hash>` fica igual (AC 33)
Proof: run infra | PASS RG14 conflict does not consume quota

**C34** - 50 `POST` paralelos com e-mails novos dão exatamente 20 `201`, 30 `429` e 20 linhas (AC 34)
Proof: run infra | PASS RG15 ip quota holds in parallel

**C35** - Os três scripts Lua da API são iguais, byte a byte, aos blocos de docs/api-contract.md (AC 35)
Proof: run infra | PASS RG16 lua scripts match the contract

**C36** - Com o `redis-limiter` parado: `500` com corpo exato, sem linha em `users`, em menos de 3 s (AC 36)
Proof: run infra | PASS RG17 limiter down answers 500

**C37** - Com o `postgres` parado e a cota livre: `500` com o mesmo corpo, em menos de 3 s, com `APP_DEBUG=true`, e o valor da cota fica igual (AC 37)
Proof: run infra | PASS RG18 database down answers 500 and releases
Proof: run laravel | ✓ it answers 500 without internal detail when the database fails

**C38** - Com o `redis` da fila parado: `201` em menos de 3 s, linha em `users`, log do `php-fpm` nomeando `SendWelcomeEmailJob` e a cota uma unidade acima (AC 38)
Proof: run infra | PASS RG19 queue down still answers 201
Proof: run laravel | ✓ it answers 201 and logs when publishing fails

**C39** - `OPTIONS /users` da origem de `CORS_ALLOWED_ORIGIN`: `204`, `Access-Control-Allow-Origin` igual à origem e `POST` em `Access-Control-Allow-Methods` (AC 39)
Proof: run infra | PASS RG20 cors preflight

**C40** - `POST /users` dessa origem traz `Access-Control-Allow-Origin` e `Retry-After` em `Access-Control-Expose-Headers`; de outra origem, sem `Access-Control-Allow-Origin` (AC 40)
Proof: run infra | PASS RG21 cors response headers

**C41** - Os testes Pest do módulo `users` cobrem, com dependências simuladas, os `422`, o `409`, o `429`, o `500` e o `201`, cada um com o corpo exato (AC 41)
Proof: run laravel | ✓ it answers 422 for each field rule
Proof: run laravel | ✓ it answers 409 when the email is taken and releases the quota
Proof: run laravel | ✓ it answers 429 with retry after when the attempts are exceeded
Proof: run laravel | ✓ it answers 500 without internal detail when the database fails
Proof: run laravel | ✓ it answers 201 and publishes the job

### S5 - Horizon e a fila própria

**C42** - Em clone limpo, `make up-laravel` sai com `0`, e `nginx`, `php-fpm`, `horizon` e `redis` são os únicos containers, todos `healthy` (AC 42)
Proof: run infra | PASS LV1 up-laravel on clean clone

**C43** - O segundo `make up-laravel` mantém os 4 IDs (AC 43)
Proof: run infra | PASS LV2 up-laravel rerun keeps containers

**C44** - O projeto publica só `8080`, e `php-fpm` e `horizon` têm `pcntl` (AC 44)
Proof: run infra | PASS LV4 laravel published ports
Proof: run infra | PASS LV5 laravel images and extensions

**C45** - O `redis` usa `redis:8.10.3-alpine`, `noeviction`, `save` vazio e `appendonly` `no` (AC 45)
Proof: run infra | PASS RG22 queue redis config

**C46** - Com o `horizon` parado, `queues:registration-emails` tem o id do usuário e não tem nome nem e-mail (AC 46)
Proof: run infra | PASS RG23 job carries only the user id

**C47** - O job publicado tem `maxTries` `5` e backoff `30,60,120,240` com os padrões de `.env.example` (AC 47)
Proof: run infra | PASS RG24 job retries use the defaults

**C48** - Depois de parar e religar o `redis` com o `horizon` no ar, um cadastro novo chega ao Mailpit em até 60 s, sem comando manual (AC 48)
Proof: run infra | PASS RG25 worker survives queue restart

**C49** - Com o Mailpit parado e religado antes de esgotar as tentativas, o e-mail chega (AC 49)
Proof: run infra | PASS RG26 mail arrives after smtp returns

**C50** - Com o watch, o texto novo de `WelcomeMail` sai em até 60 s, com o `php-fpm` no mesmo ID (AC 50)
Proof: run infra | PASS RG27 watch updates the worker

**C51** - `make down-laravel` não deixa container nem volume do projeto, e os serviços comuns continuam `healthy` (AC 51)
Proof: run infra | PASS LV9 laravel leaves on switch and down

**C52** - `/horizon` responde `200` em HTML sem recurso estático do `nginx`, e `/horizon/api/stats` traz `status` `running` (AC 52)
Proof: run infra | PASS RG28 horizon panel answers
Proof: run laravel | ✓ it denies the horizon panel outside local

### S6 - E-mail de boas-vindas

**C53** - Depois de um `201`, o Mailpit tem, em até 30 s, uma mensagem para o e-mail, de `no-reply@cadastro-feliz.local`, com o assunto `Boas-vindas ao Cadastro Feliz!` (AC 53)
Proof: run infra | PASS RG29 welcome mail arrives

**C54** - As partes em texto e HTML têm os cinco textos do corpo (AC 54)
Proof: run infra | PASS RG30 welcome mail text

**C55** - O HTML não tem `<img`, `<script` nem endereço `http` externo (AC 55)
Proof: run infra | PASS RG31 welcome mail has no external resources

**C56** - `Ana <b>Souza</b>` aparece escapado no HTML (AC 56)
Proof: run infra | PASS RG32 welcome mail escapes the name

**C57** - Um `409` não gera e-mail novo (AC 57)
Proof: run infra | PASS RG33 conflict sends no mail

**C58** - Preencher o formulário em `localhost:3000` e usar `Cadastrar` mostra `Recebemos seus dados! Em instantes você receberá um e-mail de confirmação.`, e o e-mail aparece em `localhost:8025` (AC 58)
Proof: walk - abrir o formulário, preencher nome e e-mail, usar Cadastrar e abrir o Mailpit

### S7 - Limitações provadas e registradas

**C59** - `redis` parado, cadastro, `redis` religado com o `horizon` no ar: 30 s depois, usuário em `users`, Mailpit sem mensagem, e repetir dá `409` sem mensagem nova (AC 59)
Proof: run infra | PASS LM1 queue down loses the mail

**C60** - `horizon` parado, cadastro, `make down-laravel` e `make up-laravel`: 30 s depois, usuário em `users` e Mailpit sem mensagem (AC 60)
Proof: run infra | PASS LM2 stack down loses the queued job

**C61** - Mailpit parado, tentativas reduzidas esgotadas, Mailpit religado: 30 s depois, usuário em `users`, Mailpit sem mensagem, job em `/horizon/api/jobs/failed`, `users_outbox` sem linhas e nenhuma tabela além de `schema_migrations`, `users` e `users_outbox` (AC 61)
Proof: run infra | PASS LM3 exhausted retries lose the mail

**C62** - `docs/architecture.md` tem `## Limitações do fluxo sem outbox`, com uma linha para cada cenário e para a queda entre gravar e publicar, cada uma com o que acontece e o cenário que passa a cobri-la, e cita `tests/infra` (AC 62)
Proof: run infra | PASS LM4 limitations are recorded

### S8 - Documentação alinhada

**C63** - `docs/decisions.md` tem a decisão `21`, origem `Definida`, no índice e numa seção com `201`, `users_outbox` e a rodada do outbox, e a decisão 9 diz que está suspensa nessa stack (AC 63)
Proof: run infra | PASS RD1 decision 21 recorded

**C64** - `docs/architecture.md` › E-mail enviado tem o assunto e o corpo novos e não tem `Seu cadastro foi concluído` (AC 64)
Proof: run infra | PASS RD2 welcome mail documented

**C65** - O status de `docs/api-contract.md` diz que a stack Laravel implementa `POST /users` e cita a decisão 21 (AC 65)
Proof: run infra | PASS RD3 contract status

**C66** - `docs/stacks.md` › Laravel diz que `nginx`, `php-fpm`, `horizon` e `redis` existem e que `scheduler` chega com o outbox, e mostra `app-modules` e Pest (AC 66)
Proof: run infra | PASS LV40 stacks docs describe laravel stack

**C67** - `docs/infrastructure.md` lista `redis:8.10.3-alpine` em › Versões fixadas e `horizon` e `redis` em › Arquivos Compose (AC 67)
Proof: run infra | PASS RD4 infrastructure docs list the queue

**C68** - O `README.md` diz que a stack Laravel responde `POST /users` sem outbox, cita a decisão 21 e não diz mais que o `201` garante o evento gravado (AC 68)
Proof: run infra | PASS RD5 readme states the limitation

### Acrescentados no build

**C69** - Com um DNS externo que não responde e o `postgres` e o `redis-limiter` parados, `/health` responde `503` com os dois em `fail` em menos de 3 s (AC 69)
Proof: run infra | PASS LV52 health within limit when external dns is mute

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| Landing doors (9) | dependências C7 · C12 · C44 · C45 · módulos C12 · C13 · C14 · C15 · C17 · contrato C19 · C21 · C25 · C27 · C36 · C39 · C40 · job na fila C46 · C47 · ponto único de publicação C38 · C59 · containers da fila C42 · C44 · C45 · C48 · Pest C8 · C9 · C10 · C11 · decisão 21 e texto C63 · C64 · falha rápida no DNS C69 | - |
| `POST /users` statuses (5) | `201` C19 · `409` C25 · `422` C21 · `429` C27 · `500` C36 · C37 | - |
| `OPTIONS /users` statuses (1) | `204` C39 | - |
| `GET /horizon` statuses (2) | `200` C52 · `403` fora de `local`: C52 | - |
| regras de validação, AC 21 (13 exemplos) | C21, table-driven over all 13 | - |
| chaves e IP canônico, AC 29 (4 exemplos) | par C29 · cota C29 · IPv4 mapeado C29 · IPv6 C29 | - |
| limites, AC 27 a 34 (8) | sequência do par C27 · sem banco C28 · `X-Forwarded-For` C30 · outro IP C31 · cota C32 · `409` sem cota C33 · paralelo C34 · `201` consome C38 | - |
| dependências fora do ar em `POST /users` (3) | `redis-limiter` C36 · `postgres` C37 · `redis` da fila C38 | - |
| dependências fora do ar em `GET /health` (4) | `postgres` C2 · `redis-limiter` C3 · os dois C4 · os dois com DNS externo mudo C69 | - |
| textos do e-mail (5) | C54, table-driven over all 5 | - |
| partes do e-mail (2) | texto C54 · HTML C54 · C55 · C56 | - |
| cenários de limitação (4) | Redis parado C59 · stack derrubada C60 · SMTP esgotado C61 · queda entre gravar e publicar: só documento, C62 | - |
| serviços do projeto (4) | `nginx` C42 · `php-fpm` C42 · `horizon` C42 · `redis` C42 | - |
| startup config do Laravel (3 montagens) | `php-fpm` C14 · `horizon` C42 · container de teste C10 | - |
| docs (6 lugares) | `docs/decisions.md` C63 · `docs/architecture.md` C62 · C64 · `docs/api-contract.md` C65 · `docs/stacks.md` C66 · `docs/infrastructure.md` C67 · `README.md` C68 | - |

## Swept

- validation: C21, C22, C24
- failure modes: C36, C37, C38, C49
- idempotency: C25 - repetir o cadastro dá `409`; a falta de idempotência do envio é a limitação estudada, em C59
- authorization: C27, C32 - cadastro público com limites; painel do Horizon só em `local`, C52
- concurrency: C26, C34
- data lifecycle: C20 (gravado normalizado), C60 (a fila é descartada com a stack); limpeza de dados fica fora, como em docs/database.md
- dependency failure: C2, C3, C4, C69, C36, C37, C38, C48, C49
- state transitions: n/a - sem outbox, nenhum registro muda de status nesta rodada; `users_outbox` fica vazia, C20
- observability: C5, C38 - a falha de cada check e de cada publicação vai para o log, que `make logs-laravel` acompanha

## Handoff

- **Settled mid-build:** none
- **Dispatched:** none
- **Boundary:** nothing closed yet
- **Abandoned:** none
- **Walked:** not yet
