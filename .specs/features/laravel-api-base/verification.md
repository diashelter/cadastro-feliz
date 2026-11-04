# Base da API Laravel verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at d9c31a9
**Verifier**: independent sub-agent (author != verifier)

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | `tests/infra/laravel.sh` `LV1 up-laravel on clean clone` | sim - `destroy_environment` e `rm .env` antes; afirma código `0`, `nginx` e `php-fpm` `healthy` e `/health` `200` |
| C2 | `tests/infra/laravel.sh` `LV2 up-laravel rerun keeps containers` | sim - exige 2 containers e compara os IDs e o ID da imagem antes e depois |
| C3 | `tests/infra/laravel.sh` `LV3 up-laravel serves current code` | sim - `404` antes, `200` e corpo `probe-ok` depois, sem watch |
| C4 | `tests/infra/laravel.sh` `LV4 laravel published ports` | sim - portas do `nginx` exatamente `8080`, `docker port` do `php-fpm` vazio; LV2 fixa que o projeto tem só os 2 containers |
| C5 | `tests/infra/laravel.sh` `LV5 laravel images and extensions` | sim - imagem dos dois containers, `FROM` do Dockerfile, `php -m` e `phpversion("redis")` = `6.3.0` |
| C6 | `tests/infra/laravel.sh` `LV6 framework version locked` | sim - `jq` no lock, igualdade com `v13.40.0` |
| C7 | `tests/infra/laravel.sh` `LV7 up-laravel fails when laravel does not boot` | sim - erro de sintaxe em `bootstrap/app.php` (quebra no build) e em `LimiterCheck.php` (quebra em execução): código diferente de zero e `nginx` não `healthy` |
| C8 | `tests/infra/laravel.sh` `LV8 up-laravel fails on taken port 8080` | sim |
| C9 | `tests/infra/laravel.sh` `LV9 laravel leaves on switch and down` | sim - zero containers do projeto depois de `up-go` e de `down-laravel`, e `shared_healthy` cobre `postgres`, `redis-limiter` e `mailpit` |
| C10 | `tests/infra/laravel.sh` `LV10 no vendor env or migrations in repo` | sim |
| C11 | `tests/infra/laravel.sh` `LV11 env example has laravel vars` | sim - só a seção › Específicas de stack, `base64 -d` com 32 bytes, linhas exatas |
| C12 | `tests/infra/stack.sh` `C16 missing stack refused` | sim - laço sobre `up`/`down`/`logs`/`watch` × `nest`/`go`, mensagem, código, rede e containers |
| C13 | `tests/infra/laravel.sh` `LV13 health ok with real dependencies` | sim - status, `Content-Type`, `no-store`, ausência de `Set-Cookie` e corpo byte a byte |
| C14 | `tests/infra/laravel.sh` `LV14 health 503 when limiter stopped` | sim - status, corpo exato e saúde 30 s depois (os headers do `503` não são afirmados; ver achados) |
| C15 | `tests/infra/laravel.sh` `LV15 health 503 when postgres stopped` | sim |
| C16 | `tests/infra/laravel.sh` `LV16 health 503 when both stopped` | sim |
| C17 | `tests/infra/laravel.sh` `LV17 health gives up on paused dependency` | sim - pausa cada um, `503`, corpo exato e `time_total < 3` |
| C18 | `tests/infra/laravel.sh` `LV18 failed check is logged not returned` | sim - log desde o instante da parada com `health check` e o nome, chaves do corpo exatamente `["checks","status"]` |
| C19 | `tests/infra/laravel.sh` `LV19 health writes nothing` | sim - `DBSIZE` e as duas contagens antes e depois de 5 chamadas |
| C20 | `tests/infra/laravel.sh` `LV20 no native up and no api prefix` | sim |
| C21 | `tests/infra/laravel.sh` `LV21 unknown route answers json` | sim - `-H 'Accept:'` tira o header; `/nada` e `/` |
| C22 | `apis/laravel/tests/Feature/Health/HealthTest.php` `test_returns_ok_when_both_checks_pass`, `test_returns_503_when_database_fails`, `test_returns_503_when_limiter_fails`, `test_returns_503_when_both_checks_fail` | sim - `assertStatus` e `assertSame` com o corpo exato nos 4 casos; `run` com `once()` garante que os dois checks rodam |
| C23 | `tests/infra/laravel.sh` `LV23 watch-laravel starts stack with current code` | sim - `.env`, rede, saúde, `/probe` `200` e o processo vivo |
| C24 | `tests/infra/laravel.sh` `LV24 watch syncs code without restart` | sim - `app`, `config` e `routes` pela resposta (`um-cfg` → `dois-cfg`), `tests` e `bootstrap` por arquivo no container, mesmo ID, 10 s cada |
| C25 | `tests/infra/laravel.sh` `LV25 watch rebuilds on composer.json`, `LV25 watch rebuilds on composer.lock`, `LV25 watch rebuilds on docker/php` | sim - ID novo, `healthy` e `/health` `200` em até 180 s |
| C26 | `tests/infra/laravel.sh` `LV26 watch interrupt keeps stack` | sim - SIGINT no grupo de processos, `running`, mesmos IDs e `200` |
| C27 | `tests/infra/laravel.sh` `LV27 laravel-composer writes only json and lock` | sim - `require`, versão no lock, sem `vendor`, `bootstrap/cache` só com `.gitignore` e dono do `composer.json`; ressalva: o `cp` de volta sobrescreve um arquivo que já pertence ao uid, e o dono se mantém mesmo com o container como root, então a asserção de dono não distingue um `--user` removido (o critério continua valendo) |
| C28 | `tests/infra/laravel.sh` `LV28 laravel-composer requires args` | sim |
| C29 | `tests/infra/laravel.sh` `LV29 laravel-composer keeps running stack` | sim - com `ARGS="--version"` |
| C30 | `tests/infra/laravel.sh` `LV30 up-laravel installs required package` | sim |
| C31 | `tests/infra/laravel.sh` `LV31 test-laravel passes without dependencies` | sim |
| C32 | `tests/infra/laravel.sh` `LV32 test-laravel fails on failing test` | sim - roda depois de LV33, que já construiu a imagem sem o teste, então também prova que a mudança é lida (AC 34) |
| C33 | `tests/infra/laravel.sh` `LV33 test-laravel keeps running stack` | sim |
| C34 | `tests/infra/laravel.sh` `LV34 ci runs test-laravel and laravel suite` | não - reconhece o passo de instalação só pelo nome `Instala o Docker Compose`; não afirma que ele usa `$COMPOSE_VERSION` nem confere o checksum (o "Compose fixado" do critério) |
| C35 | `tests/infra/docs.sh` `LV35 decision 19 recorded` | sim |
| C36 | `tests/infra/docs.sh` `LV36 decision 20 recorded` | sim |
| C37 | `tests/infra/docs.sh` `LV37 contract describes health` | sim |
| C38 | `tests/infra/docs.sh` `LV38 infrastructure docs describe laravel` | sim |
| C39 | `tests/infra/docs.sh` `LV39 readme describes laravel base` | sim - pegaria a frase antiga ("As três stacks ainda estão em design") |
| C40 | `tests/infra/docs.sh` `LV40 stacks docs describe laravel base` | sim |
| C41 | `tests/infra/docs.sh` `LV41 help lists laravel targets` | sim |
| C42 | `tests/infra/laravel.sh` `LV42 broken lock fails build commands` | sim |
| C43 | `tests/infra/laravel.sh` `LV43 laravel-composer propagates composer failure` | sim - além do código, confere que o lock não mudou |

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| A API expõe `GET` e `PUT /storage/{path}`, fora de › Surface (que só tem `GET /health`), e com o `APP_KEY` fixo e público de `.env.example` qualquer um que alcance a porta 8080 assina a URL e grava e lê arquivos no container; nenhum teste olha a lista de rotas | `php artisan route:list` no `php-fpm` lista `health`, `GET\|HEAD storage/{path}` e `PUT storage/{path}`; vêm de `'serve' => true` no disco `local` de `apis/laravel/config/filesystems.php:36`. URL gerada com `Storage::temporaryUploadUrl` + `PUT` com `Host: localhost` → `204`, e o `GET` assinado devolveu o conteúdo gravado (`200`) | `'serve' => false` no disco `local`, e um check que afirma que `route:list` tem só `health` (ou que `GET /storage/x` e `PUT /storage/x` respondem `404`) || `9014b0a` - `'serve' => false` no disco `local`; C44 (`LV44 api exposes only health`) afirma `route:list` só com `health` e `404` em `GET` e `PUT /storage/x` |
| C34 não prende o "Compose fixado": o passo é achado pelo nome | `tests/infra/laravel.sh` `t_lv34_ci` - só `grep -n 'Instala o Docker Compose'` antes de `run: make test-laravel` | afirmar, no job `laravel`, que o passo anterior a `make test-laravel` baixa `$COMPOSE_VERSION` e roda `sha256sum --check` com `$COMPOSE_SHA256` || `9014b0a` - C34 (`LV34`) exige a linha do download de `$COMPOSE_VERSION` e a do `sha256sum --check` com `$COMPOSE_SHA256`, nessa ordem, antes de `make test-laravel` |
| Door 3 fixa `Content-Type: application/json` e `Cache-Control: no-store` "nos dois" status, mas nenhum teste afirma o `Content-Type` de um `503`, e o `no-store` do `503` só é afirmado no caso do banco | LV14, LV15, LV16 e LV17 afirmam status e corpo; `HealthTest.php` só chama `assertStringContainsString('no-store', ...)` em `test_returns_ok_when_both_checks_pass` e `test_returns_503_when_database_fails`. Em `HEAD`, com o `redis-limiter` parado, a resposta tem os dois headers - o código está certo, o teste é que não o prende | `assertHeader('Content-Type', 'application/json')` e o `no-store` nos quatro casos de `HealthTest.php`, ou os headers no `503` de LV14 || `9014b0a` - os quatro testes de `HealthTest.php` afirmam `Content-Type: application/json` e `no-store` (C22) |
| Door 6 (sessão `array`, cache `array`, fila `sync`, log `stderr`) não tem teste que falharia se um padrão voltasse a `database` | C13 afirma ausência de `Set-Cookie`, mas as rotas de `routes/api.php` não têm o middleware de sessão, então o header não depende do driver; C31 roda com `phpunit.xml`, que sobrescreve `SESSION_DRIVER`, `CACHE_STORE` e `QUEUE_CONNECTION`. Em `HEAD`, `php artisan config:show` no `php-fpm` dá `array`, `array`, `sync`, `stderr` e `pgsql` - correto hoje | um check em `tests/infra/laravel.sh` que roda `php artisan config:show` no `php-fpm` em execução para `session.driver`, `cache.default`, `queue.default`, `logging.default` e `database.default` e compara com os valores de door 6 || `9014b0a` - C45 (`LV45 laravel defaults use no table`) confere no `php-fpm` em execução `pgsql`, `array`, `array`, `sync` e `stderr` |

Exemplos próprios rodados em `HEAD` (stack no ar com `make up-laravel`, derrubada no fim):

- `/health` com dependência travada: `postgres` pausado → `503` em 1,02 s; `redis-limiter` pausado → `503` em 1,02 s; os dois pausados (caso que nem o plano nem os checks nomeiam) → `503` `{"status":"fail","checks":{"database":"fail","limiter":"fail"}}` em 2,02 s, abaixo dos 3 s de door 3. `/health?x=1` e `/health/` → `200`; `HEAD /health` → `200`. A regra se manteve.
- Erro sempre em JSON (critério 21 e passo 4): `GET /nada` com `Accept: text/html` → `404` JSON; `POST /health` sem `Accept` → `405` JSON; `/a/b/c.php`, `/index.php`, `/favicon.ico`, `/robots.txt`, `/api` sem `Accept` → `404` JSON. A regra se manteve; a sondagem achou as rotas `storage/{path}` do primeiro achado.
