# Stack NestJS com Transactional Outbox verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at cc84df5 (C45 e `Run infra` vermelhos: `bash tests/infra/run.sh` sai com 1)
**Verifier**: independent sub-agent (author != verifier)

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | `nest.sh` `NS1 up-nest on clean clone` | yes - `destroy_environment`, a stack `go` derrubada, serviços exatos `api redis worker`, `healthy` e os 3 IDs iguais na segunda subida |
| C2 | `nest.sh` `NS2 nest published ports and shared image` | yes - portas exatas da `api` (`8080/tcp=8080`), nenhuma nos outros, mesma `.Image` |
| C3 | `nest.sh` `NS3 health ok with real dependencies` | yes - corpo exato, os dois headers e o digest das duas tabelas |
| C4 | `nest.sh` `NS4 health 503 when dependencies stop` | yes - as três combinações com corpo exato, menos de 3 s, headers, e `api` `healthy` depois |
| C5 | `nest.sh` `NS5 health gives up on paused dependency` | yes |
| C6 | `nest.sh` `NS6 failed check is logged not returned` | yes - chaves exatas, valores só `ok`/`fail`, linha `ERROR` com o motivo |
| C7 | `nest.sh` `NS7 api routes are health and users` | yes - as três rotas e oito 404, `/nada` e `/` com JSON |
| C8 | `nest.sh` `NS8 schema untouched by the stack` | yes - `cmp` do dump inteiro, sem migration, `synchronize` desligado |
| C9 | `nest.sh` `NS9 stack queue down keeps the api up` | yes - mesmo ID, `RestartCount` 0, `healthy` em 60 s |
| C10 | `nest.sh` `NS10 api never connects to the stack queue` | yes |
| C11 | `nest.sh` `NS11 up-nest fails when the api does not boot`, `NS12 up-nest fails on taken port 8080` | yes |
| C12 | `nest.sh` `NS13 nest leaves on switch and down` | yes |
| C13 | `nest.sh` `NS14 non-object json answers 422` | yes - os 4 exemplos com o corpo exato de RG4, com o banco parado e sem chave `registration:*` |
| C14 | `nest.sh` `NS15 watch updates the api` | yes - 30 s medidos desde a edição, mesmo ID |
| C15 | `nest.sh` `NS16 watch updates the worker` | yes - 60 s medidos desde a edição, mesmo ID |
| C16 | `nest.sh` `NS17 watch rebuilds on package.json`, `... package-lock.json`, `... Dockerfile` | yes - IDs novos dos dois, imagem nova e igual nos dois, `healthy`, 180 s |
| C17 | `nest.sh` `NS18 nest-npm requires args` | yes |
| C18 | `nest.sh` `NS19 nest-npm writes only json and lock` | yes |
| C19 | `nest.sh` `NS20 nest-npm propagates npm failure` | yes |
| C20 | `nest.sh` `NS21 nest versions are exact` | yes |
| C21 | `nest.sh` `NS22 test-nest passes without dependencies`, `NS23 test-nest keeps running stack` | yes |
| C22 | `nest.sh` `NS24 test-nest fails on failing test` | yes |
| C23 | `retry-delay.spec.ts` `doubles from the base for attempts 0 to 3`; `welcome-job.spec.ts` `is added with one attempt and no backoff`; `welcome-mail.spec.ts` `message id derives from the event`, `escapes the name in html`; `validation.spec.ts` `malformed json answers the contract 422` | yes - `[30,60,120,240]`, `attempts` 1, `backoff` e `jobId` indefinidos, o `Message-ID` exato, o escape exato e o corpo exato para `{"name": `, `[]`, `null`, `"x"` e `1` |
| C24 | `registration.sh` `RG0` a `RG33` (30 ids) com o adaptador `nest` | yes - o arquivo é o de `5d4f5e7` (C26), e os 30 ids batem com os `check` do arquivo |
| C25 | `outbox.sh` `LM0` a `OB38` (27 ids) com o adaptador `nest` | yes - idem; os 27 ids batem com os `check` do arquivo |
| C26 | `git diff --quiet 5d4f5e7 -- tests/infra/registration.sh tests/infra/outbox.sh tests/infra/registration-helpers.sh` | yes |
| C27 | `nest.sh` `NS25 worker pause keeps the relay publishing` | yes - `published` em 10 s e mensagem esperando; as 22 funções são exigidas pela recusa de `run.sh` (CS7) em cada entrada de contrato |
| C28 | `nest.sh` `NS26 relay scheduler runs every second` | yes |
| C29 | `nest.sh` `NS27 relay batch size and order` | yes - o primeiro commit visível tem exatamente os 2 mais antigos, criados fora da ordem de inserção |
| C30 | `nest.sh` `NS28 relay skips locked rows` | yes - o travado é o mais antigo; sem `SKIP LOCKED` o livre só sairia depois dos 12 s da trava |
| C31 | `nest.sh` `NS29 relay failure keeps the batch pending` | no - o contador corrompido faz a primeira publicação do lote falhar; um relay que confirmasse evento a evento também deixaria os dois `pending` |
| C32 | `nest.sh` `NS30 frozen queue releases the batch` | yes - transação observada aberta e fechada em até 3 s, 4 sondagens com `lock_timeout` de 1 s, e-mail em 60 s, `RestartCount` 0 |
| C33 | `nest.sh` `NS31 worker publishes right after it starts` | yes |
| C34 | `nest.sh` `NS32 stopped worker leaves events pending` | yes |
| C35 | `nest.sh` `NS33 job carries only the event id with one attempt` | yes |
| C36 | `nest.sh` `NS34 republish creates a new job` | yes - com `jobId` igual ao `event_id` a segunda mensagem não apareceria |
| C37 | `nest.sh` `NS35 killed worker does not rerun the job` | no - `published` e `attempts` são lidos antes de o `worker` voltar; depois, um job que voltasse pela fila não deixaria rastro |
| C38 | `nest.sh` `NS36 job lock outlasts the smtp timeout` | yes - o intervalo do AC (5000 a 30000 ms) e a falha entre 5 e 10 s; um `lockDuration` de 10000 também passaria, o que o AC admite |
| C39 | `stack-switch.sh` `SW1 nest pending event leaves through laravel` | yes |
| C40 | `stack-switch.sh` `SW2 laravel published event leaves through nest` | yes - exatamente uma mensagem e o `Message-ID` do evento |
| C41 | `stack-switch.sh` `SW3 attempt limit follows nest to laravel`, `SW4 attempt limit follows laravel to nest` | yes - sem o contador, a tentativa depois da troca daria `409` |
| C42 | `stack.sh` `CS1 list prints every entry` | yes - lista exata |
| C43 | `stack.sh` `C16 missing stack refused`, `C16B nest targets are implemented` | yes - `down-nest` e `logs-nest` aqui, `up-nest` e `watch-nest` por NS1 e NS15; `go` recusa nos 4 alvos |
| C44 | `nest.sh` `NS37 ci runs test-nest and the nest suites` | yes |
| C45 | `make test-frontend`, `make test-laravel`, `make test-nest`, `bash tests/infra/run.sh` (`test-infra: todos os testes passaram`) | yes - mas o proof de `run.sh` está vermelho em `proofs.md` |
| C46 | `docs.sh` `ND1 readme describes the nest stack` | yes |
| C47 | `docs.sh` `ND2 stacks describe the nest stack` | no - só confere arquivos da raiz sem ponto e `.ts` de `src` até a profundidade 3, sem `.spec.ts`; os `.lua`, `dto/create-user.dto.ts`, os 5 `.spec.ts`, `.dockerignore` e `.npmrc` não são lidos, e a árvore de hoje não lista os specs nem os dois arquivos com ponto |
| C48 | `docs.sh` `ND3 infrastructure describes the nest stack` | yes |
| C49 | `docs.sh` `ND4 status lines name the nest stack` | no - exige só o trecho `stack NestJS também` e recusa só `NestJS e Go ainda`; "a stack NestJS também ainda não implementa o outbox" passaria |
| C50 | `docs.sh` `ND5 decisions record typeorm vitest and the nest adapter` | yes |
| C51 | `nest.sh` `NS38 queue redis config` | appended by the builder from finding 4, after this verification; not judged by the Verifier |
| C52 | `nest.sh` `NS39 relay recovers a scheduler without a next job` | appended by the builder while closing finding 1 (OB17 instável), after this verification; not judged by the Verifier |

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| C45 e `Run infra` estão vermelhos em `proofs.md` at cc84df5 | `proofs.md:6` - `117 pass, 2 fail`; `:122` C45 `test-infra: todos os testes passaram` **fail**; `:128` `bash tests/infra/run.sh` exit 1, com `test-infra: falhou` e notas `mailpit não está healthy`. Todas as linhas `PASS` que os checks citam estão lá, então o caso que falhou não é um dos 50 e não aparece no trecho guardado | achar o caso que falhou na corrida inteira, corrigir e rodar `check_proofs.py nestjs-stack` de novo | |
| C37: um job que voltasse pela fila depois do `kill` não faz NS35 falhar; `maxStalledCount` 0 (door 4) não tem prova | `tests/infra/nest.sh:703-704` lê `published` e `attempts` antes do `docker start` da linha 705. Depois, com o Mailpit despausado e a republicação de 5 s, o job novo envia e marca `processed`; o job antigo, se voltasse, cairia em `registration-email.processor.ts:34` (`isTerminal`) e não enviaria nada, ou enviaria ele mesmo a única mensagem. O comentário das linhas 707-708 ("mandaria a segunda mensagem") não vale. Com `maxStalledCount` 1 (padrão do BullMQ), os 70 s de espera, a contagem 1 e `attempts` 0 continuam iguais (leitura do código; não matei o `worker` vivo) | depois dos 70 s, exigir `stack_failed_jobs` igual a 1 (com `maxStalledCount` 0 o BullMQ move o job parado para `failed`; com 1 ele volta, completa e some por `removeOnComplete`), ou manter o Mailpit pausado e `OUTBOX_REPUBLISH_AFTER_SECONDS` em 300 com o `worker` de volta por mais de 60 s e exigir `published` com `attempts` 0; opcionalmente exportar as opções do `@Processor` e fixar `maxStalledCount` 0 e `lockDuration` 30000 no Vitest | f468522 - NS35 exige um job em `failed` depois dos 70 s, o interrompido; C37 provado por ela |
| C31: a atomicidade do lote ("qualquer falha desfaz o lote", Shape 6) é provada só quando todas as publicações falham | `tests/infra/nest.sh:565` - `SET bull:registration-emails:id not-a-number` faz o primeiro `INCR` do BullMQ falhar, então nenhum evento foi publicado antes da falha. Um relay que fizesse `add` e `UPDATE ... published` evento a evento passaria NS29, e também OB23 (o gatilho recusa todo `UPDATE` para `published`). Conferi num `redis:8.10.3-alpine` descartável: com o contador em `9223372036854775806`, o primeiro `INCR` dá `9223372036854775807` e o segundo `ERR increment or decrement would overflow` | em NS29, gravar o contador em `9223372036854775806`: o primeiro evento é publicado na fila e o segundo falha; exigir os dois `pending` com `published_at` nulo e uma mensagem na fila | f468522 - NS29 grava o contador em `9223372036854775806`: a primeira publicação sai, a segunda falha, e os dois eventos continuam `pending`; C31 provado por ela |
| A configuração do `redis` da stack (door 1) não tem caso na NestJS | door 1: `redis:8.10.3-alpine`, `noeviction`, sem persistência, `tmpfs`, "como o da Laravel". A Laravel prova isso em `laravel-outbox.sh:31-38` (RG22), que é interno da Laravel; `nest.sh` só confere os nomes dos serviços (NS1) e as portas (NS2). Um compose com `allkeys-lru` ou `appendonly yes` passaria todos os checks. O `redis` vivo está certo: `noeviction`, `appendonly no`, `save` vazio, `Tmpfs {"/data":""}` | um caso `NS` como RG22 sobre `cadastro-feliz-nest-redis-1`, com a imagem, `maxmemory-policy`, `save`, `appendonly` e o `tmpfs` | f468522 - NS38 confere imagem, `noeviction`, `save`, `appendonly` e `tmpfs`; C51 provado por ela |
| C47: ND2 não lê todos os arquivos de `apis/nestjs`, e a árvore não os lista | `tests/infra/docs.sh:591` - `find . -maxdepth 1 ! -name '.*'` e `find src -maxdepth 3 -name '*.ts' ! -name '*.spec.ts'`. Ficam de fora `src/modules/users/dto/create-user.dto.ts` (profundidade 4), os 3 `.lua`, os 5 `.spec.ts`, `.dockerignore` e `.npmrc`; a árvore de `docs/stacks.md` › NestJS não tem nenhum dos 5 specs nem os dois arquivos com ponto, contra "listar os arquivos que existem em `apis/nestjs`" | ou estreitar o AC 47 (sem specs e sem arquivos com ponto) e fazer o teste ler `dto/` e `lua/`, ou listar todos na árvore e ler todos no teste | f468522 - ND2 lê todo arquivo de `apis/nestjs`, em qualquer profundidade, e a árvore lista specs, `.lua`, `dto/` e os arquivos com ponto; C47 provado por ela |
| C49: ND4 aceita um status que diz que a NestJS não implementa o outbox | `tests/infra/docs.sh:618-620` - exige `stack NestJS também` e recusa só `NestJS e Go ainda`. As linhas de hoje estão certas, mas "a stack NestJS também ainda não implementa" passaria | exigir o trecho inteiro de cada arquivo (por exemplo `implementa o outbox e o relay descritos aqui, e a stack NestJS também`) e recusar `NestJS` seguido de `ainda` | f468522 - ND4 recusa qualquer frase do status que cita a NestJS e diz `ainda`; C49 provado por ela |

Exemplos próprios, contra a stack NestJS no ar e em Node 26.13.0 descartável, todos corretos. AC 13: `true`, `false`, `1.5`, `""`, um array com um objeto válido dentro, uma string JSON que contém um objeto, corpo vazio, só espaços, um objeto seguido de lixo, sem `Content-Type` e um corpo acima de 1 MB respondem `422` com o corpo exato de RG4. AC 23: `attempts` anterior 4, 5 e 10 com base 30 dão 480, 960 e 30720 s; `O'Brien` vira `O&#039;Brien`, `Ana &amp; Bia` vira `Ana &amp;amp; Bia` e `<script>` é escapado, como o `{{ $name }}` de `welcome.blade.php` da Laravel.
