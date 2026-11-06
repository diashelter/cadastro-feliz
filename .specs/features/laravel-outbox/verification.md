# Transactional Outbox de `users` na stack Laravel verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at bcff9f4
**Verifier**: independent sub-agent (author != verifier)

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | `tests/infra/outbox.sh` `OB1 registration writes a pending event` | sim - com o `scheduler` parado, compara a linha inteira: `user_id` igual a `data.id`, tipo, `pending`, `0` e `published_at` nulo |
| C2 | `tests/infra/outbox.sh` `OB2 payload keys and normalization` | sim - chaves exatas, nome e e-mail normalizados, `user_id` e `occurred_at` iguais aos da resposta |
| C3 | `tests/infra/registration.sh` `RG7 repeated email conflicts` · `RG14 conflict does not consume quota` | sim - RG7 usa outra caixa e afirma corpo exato e 1 linha em cada tabela; RG14 afirma a cota igual, com a mesma caixa, e a normalização vem antes do limite |
| C4 | `tests/infra/outbox.sh` `OB4 outbox insert failure rolls back the user` | sim - gatilho real no `INSERT`; afirma `500`, corpo exato, usuário ausente e cota igual |
| C5 | `tests/infra/registration.sh` `RG19 queue down still answers 201` · `tests/infra/outbox.sh` `OB5 frozen queue still answers 201` | sim - parado e pausado; status, menos de 3 s, usuário, `pending` e cota + 1. O `grep .ERROR` não é vazio: forcei um `500` e `local.ERROR` apareceu no log do `php-fpm` |
| C6 | `tests/infra/outbox.sh` `OB6 registration never connects to the queue` | sim - uma conexão da API apareceria em toda rodada; basta uma rodada limpa, o que só deixaria passar uma conexão esporádica |
| C7 | `tests/infra/registration.sh` `RG15 ip quota holds in parallel` | sim - 20 `201`, 30 `429`, 20 linhas em cada tabela |
| C8 | `tests/infra/registration.sh` `RG18 database down answers 500 and releases` | sim - `500`, corpo exato, menos de 3 s e cota igual, com a cota em 1 antes |
| C9 | `tests/infra/outbox.sh` `OB9 publisher class is gone` · `app-modules/users/tests/RegisterUserTest.php` `it answers 201 and publishes no job` | sim - arquivo e referências ausentes; `Bus::assertNothingDispatched`, e OB6 cobre o que o `Bus::fake` não vê |
| C10 | `tests/infra/laravel.sh` `LV49 modular locked with local modules` · `LV50 modules layout` · `LV51 image resolves local modules` | sim - `dist.url` igual a `app-modules/outbox` e `vendor/modules/outbox/composer.json` no `php-fpm` |
| C11 | `tests/infra/outbox.sh` `OB11 outbox module does not reference users` | sim - grep em todo o módulo, com uma ou duas barras, e confere que `src` existe |
| C12 | `tests/infra/laravel.sh` `LV1 up-laravel on clean clone` · `LV2 up-laravel rerun keeps containers` | sim - destrói o ambiente e o `.env`; 5 nomes exatos, todos `healthy`, e os 5 IDs iguais ao subir de novo |
| C13 | `tests/infra/laravel.sh` `LV4 laravel published ports` · `tests/infra/outbox.sh` `OB13 scheduler image and schedule list` | sim - imagem exata, sem porta, e `* * * * * 1s` na linha de `outbox:relay` |
| C14 | `tests/infra/outbox.sh` `OB14 outbox config defaults in the scheduler` | sim - os 4 valores, ancorados por regex, no `scheduler` |
| C15 | `tests/infra/outbox.sh` `OB15 relay publishes a pending event` | sim - 10 s, `published`, `published_at` e fila exatamente 1, com o `horizon` parado |
| C16 | `tests/infra/outbox.sh` `OB16 relay skips a future event` | sim - `pending` e fila 0 depois de 5 s; o relay está no ar desde OB15, logo antes |
| C17 | `tests/infra/outbox.sh` `OB17 relay republishes only expired events` | sim - os dois lados, 300 s e 5 s; `published_at` muda e `attempts` fica 0 |
| C18 | `tests/infra/outbox.sh` `OB18 relay never selects terminal events` | sim - `processed` e `failed` com `published_at` de 1 hora; fila 0 e status iguais |
| C19 | `tests/infra/outbox.sh` `OB19 relay batch output and order` | sim - saída exata, código `0`, ordem de inserção diferente da de `created_at`, os 2 mais antigos, e o caso vazio |
| C20 | `tests/infra/outbox.sh` `OB20 relay skips locked rows` | sim - trava real de 8 s; saída `1 event(s)`, menos de 5 s, livre publicado e travado `pending` |
| C21 | `tests/infra/outbox.sh` `OB21 relay failure keeps events and logs` | sim - código `1`, `pending`, `published_at` nulo, linha no `docker logs` do `scheduler` e `healthy`. O código de saída é lido no `php-fpm`; ver o achado do tempo limite do `scheduler` |
| C22 | `tests/infra/outbox.sh` `OB22 relay resumes when the queue returns` | sim - o relógio de 60 s começa em `docker start`; mesmo ID e `RestartCount` 0 |
| C23 | `tests/infra/outbox.sh` `OB23 relay rollback after publish sends once` | sim - gatilho no `UPDATE`, ao menos 4 mensagens para 2 eventos, `pending`, e exatamente 1 e-mail por evento com a fila já vazia |
| C24 | `tests/infra/outbox.sh` `OB24 message before commit ends processed` | sim - atraso de 8 s, mais duro que os 3 s do critério; exige o e-mail com o evento ainda `pending`, depois `processed`, 1 mensagem e `processed_at` |
| C25 | `tests/infra/outbox.sh` `OB25 events wait for the scheduler` | sim para o critério - `pending`, sem e-mail, e até 60 s depois de `docker start`; não distingue a door 9, ver achado |
| C26 | `tests/infra/outbox.sh` `OB26 watch updates the relay` | sim - edita o texto, lê no `scheduler` em até 15 s e compara o ID |
| C56 | `tests/infra/laravel.sh` `LV25 watch rebuilds on composer.json` · `LV25 watch rebuilds on composer.lock` · `LV25 watch rebuilds on docker/php` | não - `healthy` e 180 s valem, mas só o ID do `php-fpm` é comparado; em `docker/php` a imagem não muda, e a igualdade de imagem do `horizon` e do `scheduler` não prova que foram recriados |
| C57 | `tests/infra/outbox.sh` `OB40 frozen queue fails the relay fast` | não julgado pelo Verifier - acrescentado pelo builder para fechar um achado; verde em `proofs.md` |
| C58 | `tests/infra/outbox.sh` `OB41 scheduler publishes right after it starts` | não julgado pelo Verifier - acrescentado pelo builder para fechar um achado; verde em `proofs.md` |
| C27 | `tests/infra/outbox.sh` `OB27 processed event and mail` | sim - 30 s, `processed`, `processed_at`, `last_error` nulo, 1 mensagem e destinatário exato |
| C28 | `tests/infra/outbox.sh` `OB28 mail uses the payload name` | sim - muda `users` antes do envio; afirma o nome original e a ausência do novo |
| C29 | `tests/infra/outbox.sh` `OB29 message id derives from the event` | sim - igualdade exata com o `id` da linha |
| C30 | `tests/infra/registration.sh` `RG23 job carries only the event id` · `RG24 job has no native retries` | sim - mensagem real na fila, com o id do evento, sem os valores de nome, e-mail e `user_id`; `maxTries` 1 e `backoff` nulo |
| C31 | `tests/infra/outbox.sh` `OB31 terminal event message sends nothing` | sim - `processed` e `failed`, com foto de status, `attempts`, `processed_at` e `last_error`, e contagem de e-mails depois da fila vazia |
| C32 | `tests/infra/outbox.sh` `OB32 missing event is ignored` | sim - log com o id, 0 em `jobs/failed` e 0 e-mails |
| C33 | `tests/infra/outbox.sh` `OB33 send failure schedules a retry` | sim - faixas 15 a 30 e 220 a 240, que recusam o erro de usar `attempts` novo (60 e 480); `pending`, `last_error` e 0 em `jobs/failed` |
| C34 | `tests/infra/outbox.sh` `LM3 exhausted retries are recorded and recoverable` | sim - `failed`, `attempts` exatamente 2 e `last_error`, com o limite em 2 |
| C35 | `tests/infra/outbox.sh` `LM3 exhausted retries are recorded and recoverable` | sim - o `UPDATE` do teste é o de docs/database.md, copiado; e-mail e `processed` |
| C36 | `tests/infra/outbox.sh` `OB36 frozen smtp counts as a failure` | sim - `docker pause`; `attempts` em até 30 s, `last_error` e o e-mail depois de despausar |
| C37 | `tests/infra/outbox.sh` `OB37 worker holds no transaction during send` | sim, com ressalva - quando sonda, afirma o que o critério pede, mas passa com zero sondas, ver achado |
| C38 | `tests/infra/outbox.sh` `OB38 database down keeps the event published` | não - afirma `attempts` 0 e 0 e-mails, mas nunca lê `status`, embora o critério e o nome do teste digam `published`; também não confere a republicação |
| C39 | `tests/infra/outbox.sh` `OB39 time limits keep their order` | sim - lê os 4 valores no `horizon` e compara com `5 60 90 300` |
| C40 | `app-modules/outbox/tests/OutboxUnitTest.php` `it waits base times two to the previous attempts` · `it runs once with no native backoff` · `it derives the message id from the event` | sim - `[30, 60, 120, 240]`, `tries` 1, sem `backoff`, `Message-ID` exato, sem banco nem Redis |
| C41 | `tests/infra/registration.sh` `RG29 welcome mail arrives` · `RG30 welcome mail text` · `RG31 welcome mail has no external resources` · `RG32 welcome mail escapes the name` · `RG33 conflict sends no mail` | sim - assunto, remetente, linhas em HTML e texto, escape e 1 mensagem depois do `409` |
| C42 | `tests/infra/registration.sh` `RG27 watch updates the worker` | não - o prazo de 60 s não é afirmado: são 12 voltas de 5 s mais até 8 s de espera cada, até cerca de 156 s, embora a nota diga "em 60 s" |
| C43 | `tests/infra/outbox.sh` `LM1 queue down delays the mail` | não - o resto vale, mas o relógio de 60 s só começa depois de esperar o `redis` (até 60 s) e o `horizon` (até 90 s), sem afirmar esses tempos |
| C44 | `tests/infra/outbox.sh` `LM2 stack down republishes the event` | sim - `published` depois de derrubar, fila 0 só com o `redis` de volta, `published_at` renovado, `processed` e 1 mensagem |
| C45 | `tests/infra/outbox.sh` `LM2B stack down delivers pending events` | sim para o critério - `pending` antes de derrubar e e-mail em até 60 s depois do `up`; não distingue a door 9, ver achado |
| C46 | `tests/infra/outbox.sh` `LM3 exhausted retries are recorded and recoverable` | sim - 30 s de espera real, 0 e-mails e `failed`; o reprocessamento entrega |
| C47 | `tests/infra/registration.sh` `RG26 mail arrives after smtp returns` | sim - `attempts` sobe, não é `failed`, e-mail e `processed` |
| C48 | `make test-frontend` · `make test-laravel` · `tests/infra/run.sh` `test-infra: todos os testes passaram` | sim - `proofs.md` mostra as três saídas com código `0` em bcff9f4 |
| C49 | `tests/infra/docs.sh` `LM4 before and after is recorded` | sim - seção nova, antiga ausente, 4 colunas e 5 linhas com coluna por coluna |
| C50 | `tests/infra/docs.sh` `OD1 architecture describes the outbox` | sim - a frase na linha de status e o `Message-ID` só dentro de › Worker |
| C51 | `tests/infra/docs.sh` `RD1 decision 21 closed and decision 22 recorded` | sim - **Encerrada** na seção 21, nota ausente na 9, e a 22 no índice e na seção |
| C52 | `tests/infra/docs.sh` `LV40 stacks docs describe laravel stack` | sim - linha `scheduler` com `Existe`, nomes presentes e ausentes, caminho do relay; `outbox/` é um grep solto, mas a árvore real está certa |
| C53 | `tests/infra/docs.sh` `RD3 contract and database status` | sim - lê só a linha de status dos dois arquivos, com afirmações positivas e negativas |
| C54 | `tests/infra/docs.sh` `RD4 infrastructure docs list the queue and the scheduler` | sim - a linha do compose em › Arquivos Compose tem `scheduler` |
| C55 | `tests/infra/docs.sh` `RD5 readme states the outbox` | sim - os dois textos ausentes, a frase presente, e `failed` com `manual` em › Limites conhecidos |

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| C38: o evento poderia sair de `published` com o banco fora e nenhum teste falharia | `tests/infra/outbox.sh:673-675` - depois de o banco voltar, só `attempts` e a contagem de e-mails; `status` não é lido, nem `published_at`, apesar de "depois da republicação". Rodei o caso à mão, e o código está certo: `published`, `attempts` 0, sem e-mail | afirmar `rg_event_is published` antes de esperar o e-mail, e `published_at` renovado depois dele | `464a4ca` - OB38 lê `status` e `published_at` com o banco de volta, com o relay parado; C38 |
| C42: o prazo de 60 s de `outbox::welcome-text` não é afirmado | `tests/infra/registration.sh:412-418` - 12 voltas, cada uma com `sleep 5` e `rg_wait_for 8`; um texto que chega em 100 s passa | medir o tempo desde a edição e falhar acima de 60 s, ou limitar as voltas por esse tempo | `464a4ca` - RG27 mede os 60 s desde a edição; C42 |
| C43: o relógio de 60 s começa tarde | `tests/infra/outbox.sh:60-63` - `rg_healthy` do `redis` (60 s) e do `horizon` (90 s) antes de `rg_wait_for 60`; um e-mail em até 210 s passa. OB22 mede certo o AC 22, a partir de `docker start` | medir desde `docker start`, como OB22, sem as esperas antes | `464a4ca` - LM1 conta os 60 s desde `docker start`; C43 |
| C56: `scheduler` e `horizon` "recriados" não é afirmado | `tests/infra/laravel.sh:642-652` - só o ID do `php-fpm` é comparado. Construí a imagem com `# probe` no fim do Dockerfile e com o arquivo original: o ID é o mesmo, então em `docker/php` a igualdade de imagem passa mesmo com os containers antigos | guardar os IDs de `horizon` e `scheduler` antes e exigir IDs novos nos 3 casos | `464a4ca` - LV25 compara os IDs de `horizon` e `scheduler`, e o Dockerfile muda com um `LABEL`; C56 |
| O tempo limite do `scheduler` não tem prova: uma fila travada poderia segurar o lote aberto | door 6 e `docs/infrastructure.md:148`. C21 para o `redis` em vez de pausar, e lê o código de saída no `php-fpm`; sem `REDIS_TIMEOUT` e `REDIS_READ_TIMEOUT` no `scheduler`, a suíte continuaria verde (leitura do teste; não rodei essa variante). Rodei com o `redis` pausado no `scheduler`: sai com `1` em 1,2 s, `pending`, e o e-mail chega 3 s depois de despausar | teste com `docker pause` e `outbox:relay` no próprio `scheduler`, afirmando código `1`, menos de 3 s e `pending` | `464a4ca` - OB40 pausa a fila e mede no `scheduler`, e OB21 lê a saída nele; C57, C21 |
| A door 9 não é provada pelos checks que a cobertura cita (C25, C45) | sem `schedule:run &`, o `schedule:work` dispara em até 60 s, e OB25 e LM2B esperam 60 s, então quase sempre passariam (leitura do teste; não rodei essa variante). Nada afere `init: true`. Medi o código certo: 0,3 s de `docker start` até `published`, e `docker stop` entre 0,1 s e 3,2 s | em OB25, exigir o evento publicado em poucos segundos depois de `docker start`, e limitar o tempo de `docker stop` abaixo dos 10 s | `464a4ca` - OB41 inicia longe da virada do minuto e mede o `docker stop`; C58 |
| C37: o teste passa sem sondar nada | `tests/infra/outbox.sh:642-643` - o laço sai na primeira volta se `attempts` já subiu, e nada exige ao menos uma sonda. O `docker stop` antes dele levou até 3,2 s, contra uma janela de 5 a 8 s | contar as sondas e falhar com zero | `464a4ca` - OB37 exige ao menos 2 sondas durante o envio; C37 |

Exemplos próprios, em bcff9f4, todos corretos. AC 2: nome com tab, aspas, `?`, barra invertida, emoji e apóstrofo, e e-mail `\t ANA+Tag@Example.COM  ` gravam o mesmo valor em `users` e no `payload`, e o e-mail sai. AC 33 e 34: `attempts` anterior 1 espera cerca de 60 s, 2 espera cerca de 120 s, 4 vira `failed` com 5, e 5 continua `failed` com 6. AC 17: com 5 s, publicado há 3 s fica e há 7 s republica. AC 19: 250 prontos com o lote padrão imprimem 100, 100, 50 e 0, com os mais antigos primeiro, e 250 mensagens na fila. AC 23: a mesma mensagem 5 vezes gera 1 e-mail. Um e-mail entre aspas, `"a b"@example.com`, é entregue.
