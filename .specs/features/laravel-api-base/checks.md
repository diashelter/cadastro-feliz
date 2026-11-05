# Base da API Laravel checks

Build: none - o repositório não tem build, lint nem type check; o Dockerfile, os composes e o Makefile são exercidos pelas provas, e o Laravel inicializa em C1
Run laravel: `make test-laravel`
Run infra: `bash tests/infra/run.sh docs stack laravel`
Plan: `.specs/features/laravel-api-base/plan.md`

45 checks in 5 slices · 6 one-way doors · 0 open, of which 0 block

## Checks

### S1 - Stack Laravel no ar com `make up-laravel`

**C1** - `make up-laravel` em clone limpo (sem `.env`, rede nem volume) sai com `0`, deixa `nginx` e `php-fpm` do projeto `cadastro-feliz-laravel` `healthy`, e `GET localhost:8080/health` responde `200` (AC 1)
Proof: run infra | PASS LV1 up-laravel on clean clone

**C2** - Segundo `make up-laravel` sem mudança sai com `0` e mantém os dois IDs de container e o ID da imagem `cadastro-feliz-laravel-php-fpm` (AC 2)
Proof: run infra | PASS LV2 up-laravel rerun keeps containers

**C3** - Com uma rota `GET /probe` acrescentada a `apis/laravel/routes/api.php` sem o watch, `/probe` responde `404` antes e `200` com o corpo da rota depois de `make up-laravel` (AC 3)
Proof: run infra | PASS LV3 up-laravel serves current code

**C4** - O projeto `cadastro-feliz-laravel` publica exatamente a porta `8080`, pelo `nginx`, e o `php-fpm` não publica porta (AC 4)
Proof: run infra | PASS LV4 laravel published ports

**C5** - As imagens dos serviços são `nginx:1.30.6-alpine` e `cadastro-feliz-laravel-php-fpm`, o Dockerfile tem `FROM php:8.5.12-fpm-alpine`, e no `php-fpm` `php -m` lista `pdo_pgsql` e `redis` com `phpversion('redis')` igual a `6.3.0` (AC 5)
Proof: run infra | PASS LV5 laravel images and extensions

**C6** - `apis/laravel/composer.lock` trava `laravel/framework` em `v13.40.0` (AC 6)
Proof: run infra | PASS LV6 framework version locked

**C7** - Com erro de sintaxe em `apis/laravel/bootstrap/app.php`, `make up-laravel` sai com código diferente de zero e o `nginx` não fica `healthy` (AC 7)
Proof: run infra | PASS LV7 up-laravel fails when laravel does not boot

**C8** - Com a porta `8080` ocupada por outro container, `make up-laravel` sai com código diferente de zero (AC 8)
Proof: run infra | PASS LV8 up-laravel fails on taken port 8080

**C9** - Com a Laravel ativa, `make up-go` (stack falsa) deixa zero containers `cadastro-feliz-laravel`; depois de `make up-laravel` e `make down-laravel`, zero containers dela e `postgres`, `redis-limiter` e `mailpit` `healthy` (AC 9)
Proof: run infra | PASS LV9 laravel leaves on switch and down

**C10** - `.gitignore` ignora `apis/laravel/vendor` (`git check-ignore` confirma), e `apis/laravel` não tem `.env`, `.env.example` nem `database/migrations` (AC 10)
Proof: run infra | PASS LV10 no vendor env or migrations in repo

**C11** - `.env.example`, em › Específicas de stack, tem `APP_KEY=base64:` com 32 bytes ao decodificar, `APP_ENV=local` e `APP_DEBUG=true` (AC 11)
Proof: run infra | PASS LV11 env example has laravel vars

**C12** - Para cada um de `up-`, `down-`, `logs-` e `watch-` com `nest` e `go` sem compose, o `make` imprime `stack <nome> ainda não implementada`, sai com código diferente de zero e não cria rede nem container (AC 12)
Proof: run infra | PASS C16 missing stack refused

### S2 - `GET /health`

**C13** - Com as dependências no ar, `GET /health` responde `200`, `Content-Type: application/json`, `Cache-Control` com `no-store`, sem `Set-Cookie`, e corpo byte a byte `{"status":"ok","checks":{"database":"ok","limiter":"ok"}}` (AC 13)
Proof: run infra | PASS LV13 health ok with real dependencies

**C14** - Com o `redis-limiter` parado, `GET /health` responde `503` com corpo exato `{"status":"fail","checks":{"database":"ok","limiter":"fail"}}`, e `nginx` e `php-fpm` continuam `healthy` 30 s depois (AC 14)
Proof: run infra | PASS LV14 health 503 when limiter stopped

**C15** - Com o `postgres` parado, `GET /health` responde `503` com corpo exato `{"status":"fail","checks":{"database":"fail","limiter":"ok"}}` (AC 15)
Proof: run infra | PASS LV15 health 503 when postgres stopped

**C16** - Com `postgres` e `redis-limiter` parados, `GET /health` responde `503` com corpo exato `{"status":"fail","checks":{"database":"fail","limiter":"fail"}}` (AC 16)
Proof: run infra | PASS LV16 health 503 when both stopped

**C17** - Com o `redis-limiter` pausado, `GET /health` responde `503` com `limiter` `fail` em menos de 3 s; com o `postgres` pausado, `503` com `database` `fail` em menos de 3 s (AC 17)
Proof: run infra | PASS LV17 health gives up on paused dependency

**C18** - Depois de um `503` com o `redis-limiter` parado, o log do `php-fpm` tem uma linha com `limiter`, e depois de um com o `postgres` parado, uma com `database`; os corpos têm só as chaves `status` e `checks` (AC 18)
Proof: run infra | PASS LV18 failed check is logged not returned

**C19** - Cinco `GET /health` deixam iguais o `DBSIZE` do `redis-limiter` e as contagens de `users` e `users_outbox` (AC 19)
Proof: run infra | PASS LV19 health writes nothing

**C20** - `GET /up` e `GET /api/health` respondem `404` (AC 20)
Proof: run infra | PASS LV20 no native up and no api prefix

**C21** - Sem header `Accept`, `GET /nada` e `GET /` respondem `404` com `Content-Type: application/json` (AC 21)
Proof: run infra | PASS LV21 unknown route answers json

**C22** - Os testes do Laravel, com os checks simulados, afirmam o `200` com os dois `ok` e o `503` com o banco, com o contador e com os dois falhando, cada um com o corpo exato (AC 22)
Proof: run laravel | ✓ returns ok when both checks pass
Proof: run laravel | ✓ returns 503 when database fails
Proof: run laravel | ✓ returns 503 when limiter fails
Proof: run laravel | ✓ returns 503 when both checks fail

### S3 - Edição e dependências sem PHP na máquina

**C23** - Em clone limpo, com `GET /probe` acrescentada antes, `make watch-laravel` cria `.env` e a rede, deixa `nginx` e `php-fpm` `healthy`, `/probe` responde `200`, e o comando continua rodando (AC 23)
Proof: run infra | PASS LV23 watch-laravel starts stack with current code

**C24** - Com o watch ativo, cada um dos cinco diretórios sincronizados chega ao `php-fpm` em até 10 s, com o mesmo ID de container: uma rota nova em `routes` que devolve o valor de uma classe nova em `app` e de um arquivo novo em `config` responde `200` com eles, a troca do valor da classe de `um` para `dois` aparece, e arquivos novos em `tests` e `bootstrap` existem no container (AC 24)
Proof: run infra | PASS LV24 watch syncs code without restart

**C25** - Com o watch ativo, mudar `apis/laravel/composer.json`, `apis/laravel/composer.lock` ou `apis/laravel/docker/php/Dockerfile` deixa o `php-fpm`, em até 180 s cada, num container de ID novo, `healthy`, com `/health` `200` (AC 25)
Proof: run infra | PASS LV25 watch rebuilds on composer.json
Proof: run infra | PASS LV25 watch rebuilds on composer.lock
Proof: run infra | PASS LV25 watch rebuilds on docker/php

**C26** - Depois de SIGINT no `make watch-laravel`, `nginx` e `php-fpm` continuam `running` com os mesmos IDs, e `/health` responde `200` (AC 26)
Proof: run infra | PASS LV26 watch interrupt keeps stack

**C27** - `make laravel-composer ARGS="require webmozart/assert:1.11.0"` rodado por um uid diferente de root grava `webmozart/assert` em `require` de `composer.json` e a versão `1.11.0` em `composer.lock`, não cria `apis/laravel/vendor`, deixa `apis/laravel/bootstrap/cache` só com `.gitignore`, e `composer.json` pertence a esse uid (AC 27)
Proof: run infra | PASS LV27 laravel-composer writes only json and lock

**C28** - `make laravel-composer` sem `ARGS` imprime `uso: make laravel-composer ARGS="<comando composer>"`, sai com código diferente de zero e não cria container (AC 28)
Proof: run infra | PASS LV28 laravel-composer requires args

**C29** - `make laravel-composer` com a stack no ar mantém o ID do `php-fpm`, e `/health` responde `200` (AC 29)
Proof: run infra | PASS LV29 laravel-composer keeps running stack

**C30** - `make up-laravel` depois do `require` de C27 deixa `/var/www/html/vendor/webmozart/assert` no `php-fpm` (AC 30)
Proof: run infra | PASS LV30 up-laravel installs required package

### S4 - Testes do Laravel com `make test-laravel` e no CI

**C31** - Sem nenhum container `cadastro-feliz-*`, `make test-laravel` sai com `0`, e depois não sobra container nem a rede `cadastro-feliz-net` (AC 31)
Proof: run infra | PASS LV31 test-laravel passes without dependencies

**C32** - Com um teste `assertTrue(false)` acrescentado em `apis/laravel/tests`, `make test-laravel` sai com código diferente de zero, sem nenhum comando antes (AC 32, AC 34)
Proof: run infra | PASS LV32 test-laravel fails on failing test

**C33** - `make test-laravel` com a stack no ar mantém o ID do `php-fpm` respondendo em `8080` (AC 33)
Proof: run infra | PASS LV33 test-laravel keeps running stack

**C34** - `.github/workflows/ci.yml` tem um job `laravel` cujo passo roda `make test-laravel` depois do passo que instala o Compose fixado, e `bash tests/infra/run.sh --list` lista `laravel` (AC 35)
Proof: run infra | PASS LV34 ci runs test-laravel and laravel suite

### S5 - Documentação alinhada

**C35** - `docs/decisions.md` tem a decisão `19` "`GET /health` comum às três stacks", origem `Definida`, no índice e numa seção que cita `200`, `503`, `database`, `limiter` e `3 s` (AC 36)
Proof: run infra | PASS LV35 decision 19 recorded

**C36** - `docs/decisions.md` tem a decisão `20` "Código da stack Laravel copiado pelo Compose Watch", origem `Definida`, no índice e numa seção que cita `bind mount`, `vendor/`, `make watch-laravel` e `make laravel-composer` (AC 37)
Proof: run infra | PASS LV36 decision 20 recorded

**C37** - `docs/api-contract.md` tem a seção `` ## `GET /health` `` com os dois corpos, `503`, `Cache-Control: no-store` e `3 s`, e o status do topo diz que a stack Laravel implementa `GET /health` (AC 38)
Proof: run infra | PASS LV37 contract describes health

**C38** - `docs/infrastructure.md`: › Makefile lista `make watch-laravel`, `make laravel-composer` e `make test-laravel` e diz que `make up-<stack>` reconstrói; › Versões fixadas lista `nginx:1.30.6-alpine`, `php:8.5.12-fpm-alpine` e `composer:2.11.1`; a linha de `apis/laravel/docker-compose.yml` em › Arquivos Compose cita `nginx` e `php-fpm`; › Integração contínua cita `make test-laravel`; › Específicas de stack lista `APP_KEY`, `APP_ENV` e `APP_DEBUG` (AC 39)
Proof: run infra | PASS LV38 infrastructure docs describe laravel

**C39** - O `README.md` não tem frase dizendo que as três stacks estão em design; › Como vai funcionar tem as linhas de comando `make watch-laravel`, `make laravel-composer` e `make test-laravel`; › Endereços tem `http://localhost:8080/health` (AC 40)
Proof: run infra | PASS LV39 readme describes laravel base

**C40** - `docs/stacks.md` › Laravel diz que `nginx` e `php-fpm` existem, que `scheduler`, `horizon` e `redis` chegam com o outbox, e cita `GET /health`, `make watch-laravel` e `make laravel-composer` (AC 41)
Proof: run infra | PASS LV40 stacks docs describe laravel base

**C41** - `make help` lista `make watch-<stack>`, `make laravel-composer` e `make test-laravel` (AC 42)
Proof: run infra | PASS LV41 help lists laravel targets

### Derived from Shape › Comandos

**C42** - Com `apis/laravel/composer.lock` inválido, `make up-laravel` e `make test-laravel` saem com código diferente de zero, e `postgres`, `redis-limiter` e `mailpit` ficam `healthy` (Shape › Comandos: o build falha)
Proof: run infra | PASS LV42 broken lock fails build commands

**C43** - Um `ARGS` que faz o composer falhar (`require pacote/inexistente`) faz `make laravel-composer` sair com código diferente de zero (Shape › Comandos: o composer falha)
Proof: run infra | PASS LV43 laravel-composer propagates composer failure

### Acrescentados pelo Verifier

**C44** - A API só tem a rota `health`: `php artisan route:list` no `php-fpm` lista só `health`, e `GET` e `PUT /storage/x` respondem `404` (› Surface: só `GET /health`)
Proof: run infra | PASS LV44 api exposes only health

**C45** - No `php-fpm` em execução, sem o `phpunit.xml`, os padrões são banco `pgsql`, sessão `array`, cache `array`, fila `sync` e log `stderr` (Landing door 6)
Proof: run infra | PASS LV45 laravel defaults use no table

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| Landing doors (7) | execução da stack C1 · C4 · C5 · C7 · C14 · fluxo de código e dependências C24 · C25 · C27 · C10 · contrato `GET /health` C13 · C14 · C17 · C20 · C37 · `up-<stack>` reconstrói C3 · dependências novas C5 · C6 · Laravel sem tabelas e sem `.env` C10 · C11 · C45 · C31 · composer sobre uma cópia C27 · C42 · C43 | - |
| rotas da API (1) | `GET /health` C44 |
| `GET /health` statuses (2) | `200` C13 · C22 · `503` C14 · C15 · C16 · C17 · C22 | - |
| corpo do `503` por combinação de falhas (3) | só `limiter` C14 · só `database` C15 · os dois C16 | - |
| dependência travada (2) | `redis-limiter` pausado C17 · `postgres` pausado C17 | - |
| comandos de Shape › Comandos (5) | `make up-laravel` C1 · `make watch-laravel` C23 · `make watch-<stack>` sem compose C12 · `make laravel-composer` C27 · `make test-laravel` C31 | - |
| erros de `make up-laravel` (4 causas) | porta 8080 C8 · build C42 · migrate: C20 de shared-infrastructure, mesma regra `up-%` · `nginx` não saudável C7 | - |
| erros de `make laravel-composer` (2) | `ARGS` vazio C28 · composer falha C43 | - |
| erros de `make test-laravel` (2) | build C42 · teste falha C32 | - |
| gatilhos de rebuild do watch (3) | `composer.json` C25 · `composer.lock` C25 · `docker/php` C25 | - |
| diretórios sincronizados pelo watch (5) | `app` C24 · `bootstrap` C24 · `config` C24 · `routes` C24 · `tests` C24 | - |
| recusas de stack sem compose (8) | C12, table-driven over all 8 (`up`/`down`/`logs`/`watch` × `nest`/`go`) | - |
| AC 3 (2 exemplos) | antes `404` C3 · depois `200` C3 | - |
| AC 7 (1 exemplo) | `bootstrap/app.php` com erro de sintaxe C7 | - |
| AC 21 (2 exemplos) | `/nada` C21 · `/` C21 | - |
| AC 24 (1 exemplo) | `um` → `dois` C24 | - |
| startup config do Laravel (2 montagens) | `php-fpm` em execução C13 · container de teste C31 | - |
| docs (6 lugares) | `docs/decisions.md` C35 · C36 · `docs/api-contract.md` C37 · `docs/infrastructure.md` C38 · `README.md` C39 · `docs/stacks.md` C40 · `make help` C41 | - |

## Swept

- validation: C28, C43
- failure modes: C7, C14, C15, C16, C17, C42
- idempotency: C2, C19
- authorization: n/a - `GET /health` é público pelo contrato, e os alvos são comandos locais sem identidade de quem chama
- concurrency: C29, C33 - `laravel-composer` e `test-laravel` com a stack no ar; dois `make` simultâneos não são suportados por nenhum alvo do projeto
- data lifecycle: C19 (nada gravado), C27 (só `composer.json` e o lock mudam na máquina), C10 (`vendor` fora do repositório)
- dependency failure: C14, C15, C16, C17
- state transitions: C23, C25, C26 - watch iniciado, rebuild que recria, interrupção que mantém os containers
- observability: C18 - o motivo de cada falha vai para o log do `php-fpm`, que `make logs-laravel` acompanha

## Handoff

- **Settled mid-build:** none
- **Dispatched:** Verifier at `d9c31a9`, returned - 4 achados, fechados no mesmo passo (no screens sub-agent: no criterion cites a capture)
- **Boundary:** C1-C43 closed at `d9c31a9` (código em `6eb4f21`, testes em `9b4be3e`, docs em `d9c31a9`); `check_proofs.py` 48 pass, 0 fail em `d9c31a9`
- **Abandoned:** `tmpfs` sobre `vendor` no serviço `composer` - o Docker criaria `apis/laravel/vendor` na máquina como ponto de montagem (virou a door 7 do plano). A imagem do `php-fpm` no serviço `composer` - um lock quebrado impediria `make laravel-composer` de consertá-lo. `php artisan test` lendo o `.env` ausente - o Collision mostra como aviso a leitura que o phpdotenv faz com `@`; o Laravel deixa de tentar ler o arquivo quando ele não existe. LV7 com `routes/api.php` ou o `HealthController` quebrados - o `package:discover` do build carrega os dois, então o caso só de execução usa o `LimiterCheck`
- **Ambiente de prova:** o Docker desta sessão não alcança os espelhos do Alpine, o PECL nem os downloads do GitHub, e o Docker Hub anônimo responde 429. Só neste Docker, e fora do repositório: as imagens comuns vieram de `mirror.gcr.io` com a tag original; a tag `php:8.5.12-fpm-alpine` foi sobreposta por uma imagem construída da oficial com `pdo_pgsql.so`, `redis.so` (6.3.0), `libpq`, `liblz4`, `libfcgi` e `cgi-fcgi` copiados de `serversideup/php:8.5.12-fpm-alpine3.23` (PHP 8.5.12), `apk`, `pecl install redis-6.3.0` e `docker-php-ext-install` trocados por scripts que só copiam esses arquivos, e um cache offline do composer (`COMPOSER_DISABLE_NETWORK=1`) montado a partir dos clones git do lock; a tag `node:26.13.0-alpine` confia no certificado da sessão, para o `npm ci` do frontend no C22 de shared-infrastructure. Numa máquina com rede, o mesmo Dockerfile roda `apk`, `pecl` e `composer install` de verdade: esse caminho não foi exercido aqui, e o CI só o exercita num pull request ou num disparo manual
