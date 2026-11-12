# Registro de decisões

> Decisões de desenho do Cadastro Feliz, com os motivos. Uma mudança em qualquer item deve ser registrada aqui.

**Origem:** *definida* foi escolhida pelo responsável do projeto; *proposta* veio do desenho e pode ser revista.

| # | Decisão | Origem |
|---|---|---|
| [1](#1-transactional-outbox-em-vez-de-publicar-direto-na-fila) | Transactional Outbox em vez de publicar direto na fila | Definida |
| [2](#2-banco-e-schema-únicos) | Banco e schema únicos | Definida |
| [3](#3-e-mail-repetido-retorna-409) | E-mail repetido retorna 409 | Definida |
| [4](#4-bloqueio-de-15-minutos-em-janela-fixa) | Bloqueio de 15 minutos em janela fixa | Definida |
| [5](#5-redis-comum-para-o-contador-de-tentativas) | Redis comum para o contador de tentativas | Definida |
| [6](#6-uma-stack-ativa-por-vez) | Uma stack ativa por vez | Proposta |
| [7](#7-rota-post-users-sem-prefixo) | Rota `POST /users` sem prefixo | Proposta |
| [8](#8-redis-limiter-indisponível-retorna-500) | `redis-limiter` indisponível retorna 500 | Proposta |
| [9](#9-retentativas-controladas-pelo-banco) | Retentativas controladas pelo banco | Proposta |
| [10](#10-fila-transporta-só-o-identificador-do-evento) | Fila transporta só o identificador do evento | Proposta |
| [11](#11-mailpit-como-caixa-de-e-mail) | Mailpit como caixa de e-mail | Proposta |
| [12](#12-navegador-chama-a-api-diretamente) | Navegador chama a API diretamente | Proposta |
| [13](#13-escopo-das-convenções-do-agentsmd) | Escopo das convenções do `AGENTS.md` | Proposta |
| [14](#14-forma-única-das-respostas-de-erro) | Forma única das respostas de erro | Definida |
| [15](#15-golang-migrate-como-ferramenta-de-migrations) | golang-migrate como ferramenta de migrations | Proposta |
| [16](#16-frontend-em-next-dev-com-o-código-copiado-pelo-compose-watch) | Frontend em `next dev` com o código copiado pelo Compose Watch | Definida |
| [17](#17-cota-de-cadastros-concluídos-por-ip) | Cota de cadastros concluídos por IP | Definida |
| [18](#18-formulário-sem-validação-no-navegador) | Formulário sem validação no navegador | Definida |
| [19](#19-get-health-comum-às-três-stacks) | `GET /health` comum às três stacks | Definida |
| [20](#20-código-da-stack-laravel-copiado-pelo-compose-watch) | Código da stack Laravel copiado pelo Compose Watch | Definida |
| [21](#21-stack-laravel-sem-outbox-até-a-rodada-do-outbox) | Stack Laravel sem outbox até a rodada do outbox | Definida |
| [22](#22-message-id-derivado-do-evento) | `Message-ID` derivado do evento | Proposta |
| [23](#23-suíte-de-contrato-por-stack) | Suíte de contrato por stack | Definida |
| [24](#24-typeorm-sem-schema-próprio-na-stack-nestjs) | TypeORM sem schema próprio na stack NestJS | Definida |
| [25](#25-vitest-com-swc-na-stack-nestjs) | Vitest com SWC na stack NestJS | Definida |
| [26](#26-módulo-único-da-stack-laravel) | Módulo único da stack Laravel | Definida |
| [27](#27-limpeza-e-aviso-de-falhas-de-users_outbox-na-stack-laravel) | Limpeza e aviso de falhas de `users_outbox` na stack Laravel | Definida |
| [28](#28-limitador-de-cada-stack-sem-lua) | Limitador de cada stack, sem Lua | Definida |

## 1. Transactional Outbox em vez de publicar direto na fila

Publicar na fila durante a requisição cria duas escritas sem transação comum, e uma delas pode falhar sem a outra. Com o outbox, usuário e evento são gravados de forma atômica. O custo é ter um relay e aceitar entrega *at-least-once*, com possíveis e-mails duplicados.

## 2. Banco e schema únicos

Um único schema, com migrations em SQL puro aplicadas pelo container `migrate`, garante que as três stacks sejam realmente comparáveis e intercambiáveis. Além disso, permite demonstrar uma stack assumindo eventos deixados por outra.

**Custo:** nenhuma stack usa a ferramenta de migrations do próprio framework.

## 3. E-mail repetido retorna 409

É o status mais preciso para conflito com um recurso existente, e separa esse caso dos erros de validação (422). Amplia a lista inicial de status (201, 422, 429, 500).

**Custo:** o status revela que o e-mail já está cadastrado.

## 4. Bloqueio de 15 minutos em janela fixa

Depois de 5 tentativas do mesmo IP com o mesmo e-mail, a API responde 429 sem consultar o banco, o que reduz a carga causada por tentativas repetidas.

A chave combina IP e e-mail para que um terceiro não bloqueie o e-mail de outra pessoa: quem repete um e-mail alheio esgota só o contador do próprio IP. A duração limita o dano que resta, de quem divide o mesmo IP.

**Custos**
- A janela fixa é simples, mas permite uma rajada na virada da janela.
- Trocar de IP dá mais 5 tentativas para o mesmo e-mail.

## 5. Redis comum para o contador de tentativas

O contador fica em um container compartilhado, o `redis-limiter`. Laravel e NestJS mantêm um `redis` próprio só para a fila, e a stack Go não tem Redis próprio.

**Substitui** o desenho anterior, com um Redis por stack, em que a stack Go tinha um Redis só para o contador.

**Motivos**
- **Regra comum:** o limite de tentativas pertence ao cadastro, como o banco. A fila é um detalhe de cada stack.
- **Cadastro independente da fila:** no desenho anterior, uma queda do Redis em Laravel e NestJS derrubava o cadastro junto com a fila.
- **Configurações opostas:** a fila precisa de `noeviction`, e o BullMQ a exige. O contador é descartável e não precisa de persistência.

**Alternativas descartadas**
- **Um Redis comum para tudo:** economiza containers, mas mistura fila e contador e faz uma queda do Redis parar o cadastro.
- **Contador em memória:** zeraria a cada reinício e não funcionaria com réplicas.
- **Contador no Postgres:** contrariaria o objetivo de não carregar o banco.

**Custos**
- Laravel e NestJS têm dois Redis e duas conexões para configurar.
- O formato gravado no contador é de cada stack, e o limite não acompanha a troca de stack (decisão 28).
- Testes do 429 precisam de outro e-mail ou de `make reset-limits`, porque o contador sobrevive enquanto a janela não expira.

## 6. Uma stack ativa por vez

O frontend usa sempre o mesmo endereço, então as três APIs publicam a porta 8080. `make up-<stack>` derruba as demais antes de subir a escolhida.

**Alternativa descartada:** um gateway à frente das APIs permitiria stacks simultâneas, mas acrescenta um componente que o caso de uso não exige.

## 7. Rota `POST /users` sem prefixo

Segue a especificação do projeto. O `AGENTS.md` sugere `/api/v1`, mas essa orientação vem de outro produto (ver decisão 13). Com um único endpoint, o versionamento ainda não traz benefício.

## 8. `redis-limiter` indisponível retorna 500

Se o contador estiver fora do ar, a API não consegue aplicar o limite. Retornar 500 é coerente com a regra de responder 500 em indisponibilidades e evita que uma falha do Redis jogue toda a carga no banco.

**Custo:** o `redis-limiter` é ponto único de falha do cadastro nas três stacks. Em produção, ele precisaria de alta disponibilidade.

## 9. Retentativas controladas pelo banco

Cada fila tem um mecanismo próprio de retentativa, com comportamentos diferentes. Com `attempts` e `available_at` na tabela, as três stacks seguem exatamente a mesma regra, e o estado de cada evento pode ser consultado com SQL.


## 10. Fila transporta só o identificador do evento

O PostgreSQL continua sendo a única fonte da verdade, e dados pessoais não passam pelo Redis nem pelo RabbitMQ.

**Custo:** o worker faz uma consulta a mais para cada mensagem.

## 11. Mailpit como caixa de e-mail

Captura os e-mails de todas as stacks em um só lugar, sem enviá-los de verdade, e oferece interface web. Usa SMTP na porta 1025 e interface na 8025.

## 12. Navegador chama a API diretamente

Deixa os status reais visíveis nas ferramentas do navegador e diferencia a falha de rede, quando nenhuma stack está no ar, de um erro da API.

**Custo:** cada API precisa configurar CORS.

## 13. Escopo das convenções do `AGENTS.md`

O `AGENTS.md` em `~/Documents` descreve outro produto, uma plataforma de eventos com upload de mídia. Este projeto adota apenas as convenções gerais:

- Documentação em português do Brasil e código em inglês.
- Organização modular.
- Formato das respostas JSON, com o corpo de erro redefinido pela decisão 14, e das mensagens de commit.

Não se aplicam aqui as regras específicas daquele produto, como a arquitetura de upload, a estrutura de filas de mídia e o prefixo `/api/v1`.

## 14. Forma única das respostas de erro

Todo erro de `POST /users` traz `message` e uma lista `errors`, com `field`, `code` e `message` em cada item. A lista fica vazia quando não há erro de campo. O frontend traduz cada item pelo par `field` + `code`, e a API continua em inglês. O detalhamento está em [api-contract.md](api-contract.md#forma-do-corpo-de-erro) e no [design](../.design/api-error-response.md).

**Motivos**
- **Uma forma só:** os status de erro tinham corpos diferentes, e cada stack teria de decidir como montá-los.
- **Tradução sem comparar textos:** o 422 mostra o erro junto de cada campo, e o status não diz qual regra foi violada.
- **Lista em vez de mapa:** sem erro de campo, um mapa vazio sairia como `[]` em PHP e `null` em Go, se não fosse tratado. Em Go, a lista também precisa ser inicializada.

**Alternativas descartadas**
- **Mapa por campo:** mantinha o agrupamento do formato anterior, mas exigia tratar o mapa vazio em cada stack.
- **RFC 9457 (Problem Details):** só compensa com consumidores externos ou ferramentas que esperem o padrão, e hoje há um endpoint e um frontend.
- **Mensagens da API em português:** simplificaria o frontend, mas colocaria texto de interface nas três stacks.

**Custos**
- Nenhuma stack aproveita o formato de erro nativo do framework.
- Os códigos e o par `field` + `code` passam a ser um contrato entre as stacks e o frontend.
- 404, 405, `Content-Type` errado, corpo que não é objeto e a quantidade de erros por campo ficam sem definição, conforme as [limitações do contrato](api-contract.md#limitações-conhecidas).

## 15. golang-migrate como ferramenta de migrations

O container `migrate` usa o golang-migrate (`migrate/migrate:v4.20.1`) para aplicar `database/migrations`. Os arquivos são pares `NNNN_<nome>.up.sql` e `NNNN_<nome>.down.sql`, e o controle de versão fica na tabela `schema_migrations` do schema único. A ferramenta roda SQL puro e não pertence a nenhuma das três stacks, o que mantém a decisão 2.

**Regra:** cada arquivo é atômico por conta própria, começando com `BEGIN;` e terminando com `COMMIT;`, porque o golang-migrate não envolve o arquivo em uma transação. Sem isso, uma falha no meio deixaria o schema parcial.

**Aviso:** mesmo com a transação, uma migration com falha deixa a versão *dirty*. O schema volta ao estado anterior, mas o migrate se recusa a continuar até um `force` manual para a última versão aplicada, descrito em [database.md](database.md#migrations).

**Alternativa descartada:** um script com `psql -f` sobre todos os arquivos não sabe o que já foi aplicado e falha na segunda execução.

**Custo:** trocar de ferramenta depois exige migrar o controle de versão, porque `schema_migrations` fica no banco que as três stacks compartilham.

## 16. Frontend em `next dev` com o código copiado pelo Compose Watch

O container do `frontend` roda sempre `next dev`, e o código entra na imagem por cópia. `make watch-frontend` usa o Compose Watch para copiar cada edição de `frontend/src` para o container e reconstruir a imagem quando `package.json`, `package-lock.json` ou `next.config.ts` mudam. Dependências mudam só por `make frontend-npm`, e `node_modules` nunca existe na máquina. O detalhamento está no [design](../.design/frontend-container.md).

**Motivos**
- **Só Docker e `make`:** quem edita o formulário não precisa de Node na máquina.
- **macOS:** o guia de desenvolvimento local do Next.js avisa que, no Docker Desktop, os eventos de arquivo de um bind mount podem atrasar ou se perder. Com a cópia, o evento nasce dentro do container e o Turbopack o recebe como no Linux.
- **Sem produção:** o formulário é igual nas três stacks, e o que se estuda é a API e o outbox.

**Alternativas descartadas**
- **Bind mount de `frontend/`:** mais simples, mas não confiável no Docker Desktop do macOS. O paliativo comum, `WATCHPACK_POLLING`, só vale para o webpack e não tem efeito no Turbopack, o padrão do Next.js 16.
- **Synchronized file shares do Docker Desktop:** exige assinatura paga.
- **Build de produção com saída standalone:** cada edição exigiria reconstruir a imagem.

**Custos**
- Editar com recarga automática exige um terminal com `make watch-frontend` aberto.
- O container não se parece com produção, e a primeira página de cada container novo demora alguns segundos para compilar.

## 17. Cota de cadastros concluídos por IP

Cada IP pode concluir no máximo `REGISTRATION_MAX_PER_IP` (20) cadastros a cada `REGISTRATION_IP_WINDOW_SECONDS` (1 hora), em janela fixa no `redis-limiter`. A API reserva uma unidade da cota antes da transação, numa operação atômica, e devolve a reserva quando a resposta é 409 ou 500. Só o 201 consome a cota. A chave, a regra de reserva e devolução e a posição na ordem de processamento estão em [api-contract.md](api-contract.md#limite-por-ip). O detalhamento está no [design](../.design/registration-ip-limit.md).

**Motivos**
- **O dano é o e-mail:** cada 201 grava um evento que vira um e-mail para o endereço informado. Sem a cota, um único IP poderia fazer o sistema enviar e-mails para milhares de endereços alheios.
- **Paralelismo:** verificar e reservar na mesma operação garante o limite mesmo com requisições simultâneas.
- **409 não pune:** quem erra o próprio e-mail ou tenta de novo não perde cota.

**Alternativas descartadas**
- **Consultar antes e incrementar depois do commit:** N requisições paralelas passariam juntas.
- **Contar no PostgreSQL, com o IP em `users`:** sobreviveria a uma perda do `redis-limiter`, mas gravaria o IP junto de dados pessoais e carregaria o banco (decisão 5).
- **Limite por faixa de IP (/24, /64):** cada stack teria de calcular a faixa do mesmo jeito.

**Custos**
- Pessoas atrás do mesmo IP dividem a cota.
- Uma devolução que falha deixa a cota com uma unidade a mais até a janela expirar.

## 18. Formulário sem validação no navegador

O formulário envia nome e e-mail exatamente como foram digitados, sem `trim` e sem nenhuma regra no navegador: nenhum `required`, `maxlength` ou `pattern`, e o campo de e-mail é texto, porque um campo `type="email"` tira os espaços das pontas. Todo erro de campo exibido vem da API, traduzido pelo par `field` + `code`. O detalhamento está no [design](../.design/registration-form.md).

**Motivos**
- **A POC exercita a API:** um formulário em branco gera um 422 da API, e assim o cenário 3 de [architecture.md](architecture.md#cenários-para-validar-a-implementação) pode ser reproduzido pelo formulário.
- **Uma só fonte das regras:** as regras de validação vivem nas três stacks; repeti-las no navegador seria uma quarta cópia.

**Alternativas descartadas**
- **Espelhar as regras do contrato no cliente:** a experiência seria melhor, mas o 422 só apareceria por `curl`.

**Custos**
- Cada erro de digitação custa uma requisição, que não conta como tentativa, porque o 422 não conta.

## 19. `GET /health` comum às três stacks

Toda stack expõe `GET /health`, na raiz e sem prefixo, com o mesmo corpo no `200` e no `503`: `status` e um item em `checks` para cada dependência da API, `database` (PostgreSQL) e `limiter` (`redis-limiter`), cada um `ok` ou `fail`. A resposta chega em menos de 3 s mesmo com uma dependência travada, porque cada check desiste em 1 s. O motivo de uma falha vai para o log, nunca para o corpo. O detalhamento está em [api-contract.md](api-contract.md#get-health) e no [design](../.design/laravel-api-base.md).

**Motivos**
- **Stacks intercambiáveis:** um `/health` igual na porta 8080 permite que os testes de infraestrutura e o CI verifiquem qualquer stack da mesma forma.
- **A base prova as conexões:** antes de `POST /users`, a stack mostra que alcança o banco e o contador, separando um erro de rede de um erro de regra.
- **Saúde do container sem depender das dependências:** o container está saudável quando a API responde `/health` com `200` ou `503`; uma queda do contador aparece no corpo, não como uma stack que não sobe.

**Alternativas descartadas**
- **A rota nativa de cada framework, como o `/up` do Laravel:** responde HTML e `500`, sem dizer qual dependência caiu, e muda de stack para stack.
- **A forma de erro da decisão 14 no `503`:** ela é para erros de entrada de `POST /users`; aqui o `503` é um relatório de estado, lido com o mesmo código que o `200`.

**Custos**
- NestJS e Go precisam implementar a mesma rota, o mesmo corpo e o mesmo limite de tempo.
- O Mailpit e a fila não entram no `/health`, porque a API não fala com eles.

## 20. Código da stack Laravel copiado pelo Compose Watch

O código chega ao `php-fpm` só por cópia, nunca por bind mount. A imagem leva o código e o `vendor/`; `make watch-laravel` copia cada edição para o container, onde ela vale na próxima requisição, e reconstrói a imagem quando `composer.json`, `composer.lock` ou `docker/php` mudam. As dependências mudam só por `make laravel-composer`, que roda o composer num container descartável e devolve só `composer.json` e `composer.lock`. `vendor/` nunca existe na máquina. O detalhamento está no [design](../.design/laravel-api-base.md).

**Motivos**
- **Mesmo fluxo do frontend:** a decisão 16 já copia o código pelo Compose Watch, e quem edita uma parte do projeto usa o mesmo gesto na outra.
- **Só Docker e `make`:** o README promete que a máquina não precisa de PHP nem de Composer.

**Alternativas descartadas**
- **Bind mount de `apis/laravel`:** dispensaria o terminal do watch e deixaria `vendor/` visível para a IDE, mas criaria o `vendor/` na máquina e um fluxo diferente do frontend.

**Custos**
- A IDE não enxerga `vendor/` para autocompletar o Laravel.
- Editar exige `make watch-laravel` rodando; sem ele, a edição só entra no próximo `make up-laravel`.

## 21. Stack Laravel sem outbox até a rodada do outbox

**Encerrada** pela rodada do outbox. O texto abaixo registra o estado da stack até então, e o resultado da comparação está em [Antes e depois do outbox](architecture.md#antes-e-depois-do-outbox).

A stack Laravel entrega `POST /users` primeiro sem o outbox: grava em `users` e depois publica o job no Redis do Horizon, como duas escritas sem transação comum. Se a publicação falhar, o usuário fica gravado, a API responde `201` e o erro vai para o log, então o e-mail se perde sem que o cliente saiba. `users_outbox` continua existindo e sem linhas. O contrato continua descrevendo o alvo, e esta decisão termina na rodada do outbox. O detalhamento está no [design](../.design/laravel-registration-email.md).

**Motivos**
- **Observar antes de corrigir:** o problema só estava descrito em texto, e a rodada do outbox não teria um "antes" para comparar.
- **Prova pela inversão:** os testes de `tests/infra/limitations.sh`, hoje `tests/infra/outbox.sh`, afirmavam a perda. Com o outbox, eles se inverteram e provam a correção.
- **Sem recomeçar:** a publicação fica em um único ponto, o `WelcomeEmailPublisher`, para a rodada do outbox trocá-la sem mexer em validação, limites ou resposta.

**Alternativas descartadas**
- **Responder `500` quando a publicação falha:** o cliente saberia da falha, mas a nova tentativa receberia `409` e o e-mail também não sairia.
- **Publicar dentro da transação:** estudaria o caso inverso, o e-mail para um cadastro que não existe, que é bem mais difícil de reproduzir.

**Custos**
- Até a rodada do outbox, um `201` da stack Laravel não garante o envio do e-mail, e [architecture.md](architecture.md#limitações-do-fluxo-sem-outbox) registra quando ele se perde.
- As retentativas ficam no Horizon, e a decisão 9 fica suspensa nessa stack.
- NestJS e Go, quando chegarem, continuam seguindo o contrato, com o outbox.

## 22. `Message-ID` derivado do evento

Todo e-mail de boas-vindas sai com o `Message-ID` `<event_id>@cadastro-feliz.local`, com o domínio fixo nas três stacks. Um reenvio, mesmo por outra stack, sai com o mesmo identificador. O detalhamento está no [design](../.design/laravel-outbox.md).

**Motivo:** a entrega é *at-least-once*, e o identificador estável torna visível uma duplicata, embora não a impeça.

**Alternativa descartada:** derivar o domínio de `MAIL_FROM`, porque uma stack com outro remetente quebraria a identificação das duplicatas.

**Custo:** o formato passa a ser um contrato entre as stacks, e mudá-lo depois obriga a mudar nas três.

## 23. Suíte de contrato por stack

Os casos de `tests/infra` que valem para qualquer stack, em `registration.sh` e `outbox.sh`, são os casos de contrato: só observam a porta 8080, o PostgreSQL, o `redis-limiter` e o Mailpit, e só agem sobre a stack pelo adaptador dela, `tests/infra/adapters/<stack>.sh`. O adaptador define um vocabulário de papéis, como parar o worker, parar o relay, congelar a fila e publicar uma mensagem sem o relay, e não de containers. Os ids não mudam de uma stack para outra; a stack aparece na linha `== <arquivo>:<stack>` antes dos casos. O que é interno de uma stack fica num arquivo dela, como `laravel-outbox.sh`. O detalhamento está no [design](../.design/nestjs-stack.md) e no [plano](../.specs/features/contract-suite/plan.md).

**Motivos**
- **Mesmo contrato, mesma prova:** uma stack nova é aceita pelos mesmos casos, sem cópias que possam divergir.
- **CI sem mudança:** `run.sh --list` imprime uma entrada por arquivo de contrato e adaptador, e a matriz do CI já é montada a partir dela.

**Alternativas descartadas**
- **Arquivos de teste por stack:** cada stack copiaria os casos, e uma cópia poderia divergir do contrato sem nenhum teste perceber.
- **Desvios por stack dentro dos casos:** toda stack nova editaria cada caso.
- **Matriz de duas dimensões no CI, arquivo × stack:** mudaria o workflow a cada stack nova.

**Custos**
- Toda stack precisa de um adaptador com o vocabulário inteiro, mesmo quando relay e worker dividem um processo.
- Um caso de contrato não pode citar nada de uma stack; o OB25 trocou "scheduler" por "relay" no nome.

**Na stack NestJS**
- O relay e o worker rodam no mesmo container, o `worker`, então o adaptador `nest` para cada papel pausando a fila dele no BullMQ: `outbox-relay` para o relay e `registration-emails` para o worker. Parar o container inteiro fica provado em `nest.sh`, o arquivo interno da stack. A troca entre Laravel e NestJS, que precisa das duas stacks, fica em `stack-switch.sh` ([plano](../.specs/features/nestjs-stack/plan.md)).

## 24. TypeORM sem schema próprio na stack NestJS

A stack NestJS acessa o banco pelo TypeORM, mas o TypeORM nunca altera o schema: `synchronize` e `migrationsRun` ficam desligados, e não há migration do TypeORM no repositório. As entidades `User` e `UserOutboxEvent` só mapeiam `users` e `users_outbox` como `database/migrations` as cria. O detalhamento está no [design](../.design/nestjs-stack.md) e no [plano](../.specs/features/nestjs-stack/plan.md).

**Motivos**
- **Uma só fonte do schema:** `database/migrations` continua sendo a única (decisão 2), e as três stacks leem o mesmo banco.
- **Nada reescreve as outras stacks:** um `synchronize` ligado em desenvolvimento alteraria as tabelas que a Laravel também usa.

**Alternativas descartadas**
- **Migrations do TypeORM:** duas fontes do schema, que poderiam divergir.
- **`synchronize` em desenvolvimento:** o banco é o mesmo para as três stacks, e uma entidade errada mudaria a tabela de todas.

**Custos**
- Uma coluna nova exige mudar a migration em SQL e as entidades à mão.

## 25. Vitest com SWC na stack NestJS

Os testes unitários da stack NestJS usam o Vitest, o mesmo executor do frontend, compilados pelo SWC com `unplugin-swc`, como a receita oficial do Nest. `make test-nest` checa os tipos com `tsc --noEmit` e roda o Vitest num container descartável, sem banco nem Redis. O modo watch do Nest CLI também compila com o SWC, pelo `@swc/cli` e sem checar tipos, para a `api` e o `worker` subirem em segundos. O detalhamento está no [design](../.design/nestjs-stack.md).

**Motivos**
- **Um executor de testes no projeto:** o frontend já usa o Vitest.
- **Metadados dos decorators:** o Vitest sozinho não os emite, e a injeção de dependência do Nest precisa deles; o SWC os emite.

**Alternativas descartadas**
- **Jest, o padrão do Nest CLI:** um segundo executor de testes no projeto, com outra configuração e outra saída.

**Custos**
- O SWC não checa tipos, então o `tsc --noEmit` roda antes, como no frontend.

## 26. Módulo único da stack Laravel

O cadastro da stack Laravel fica num módulo só, `users`: grava o usuário e o evento, é dono de `users_outbox`, roda o relay e envia o e-mail de boas-vindas. Cada operação é um caso de uso em `src/UseCases` que abre a própria transação com `DB::transaction`; os repositórios só executam consultas. O detalhamento está no [plano](../.specs/features/laravel-users-module/plan.md).

**Substitui** o desenho de 2026-11-10, com os módulos `users` e `notifications`, um registro `OutboxConsumers` para `users` não depender de `notifications`, e a conexão injetada nos casos de uso como `ConnectionInterface`.

- **Job pelo tipo:** o relay escolhe o job de cada evento com um `match` sobre `OutboxEventType`. Um `event_type` fora do enum faz a rodada do relay falhar sem publicar nada.
- **Casos de uso:** status e tipos de evento ficam em enums; os testes Pest, que rodam sem PostgreSQL, simulam a facade `DB`.

**Motivos**
- **A divisão era só de nome:** `notifications` lia e gravava `users_outbox` pelo repositório de `users`, e manter a direção da dependência exigia um registro, um provider e uma exceção para um evento com um consumidor.
- **Uma forma de falar com o banco:** os repositórios já usam a facade `DB`; a conexão injetada existia só para os testes, que a facade simulada atende.

**Alternativas descartadas**
- **Manter `users` e `notifications`:** separa o e-mail do cadastro, mas o e-mail continua escrevendo pela tabela de `users`, e a separação custa três classes de indireção.
- **`ConnectionInterface` injetada:** testável sem banco, mas é uma segunda forma de abrir transação num código que usa a facade em todo o resto.

**Custos**
- Um segundo consumidor de `user.registered` entra como outro braço do `match`, dentro de `users`.
- A classe do job mudou de namespace de novo: uma mensagem antiga que estiver na fila na troca falha no Horizon, e o evento é republicado depois de `OUTBOX_REPUBLISH_AFTER_SECONDS`.

## 27. Limpeza e aviso de falhas de `users_outbox` na stack Laravel

A stack Laravel agenda dois comandos no `scheduler`. `outbox:purge`, todo dia às 03:00 UTC, apaga os eventos `processed` concluídos há mais de `OUTBOX_RETENTION_DAYS` dias (padrão 7) e não toca em nenhum outro status nem em `users`. `outbox:notify-failed`, a cada 5 minutos, envia a `OUTBOX_ALERT_EMAIL` (padrão `ops@cadastro-feliz.local`) um único resumo com os eventos `failed` ainda não avisados e só depois de o SMTP aceitá-lo preenche `failure_notified_at`, coluna nova da migration `0002`. O reprocessamento manual de [database.md](database.md#reprocessar-um-evento-em-failed) passa a zerar a coluna. O detalhamento está no [design](../.design/laravel-outbox-maintenance.md) e no [plano](../.specs/features/laravel-outbox-maintenance/plan.md).

**Motivos**
- **`failed` era invisível:** só quem consultava o banco à mão sabia que um e-mail de boas-vindas não tinha saído.
- **Dados pessoais acumulados:** todo evento `processed` guardava nome e e-mail para sempre.
- **Resumo em vez de um e-mail por evento:** a causa mais comum de `failed` é o SMTP fora do ar, e uma queda longa geraria dezenas de avisos iguais.
- **Um resumo repetido é tolerado, um aviso perdido não:** a marca só entra depois do envio aceito, a mesma entrega *at-least-once* do resto do outbox.

**Alternativas descartadas**
- **O aviso como um evento em `users_outbox`:** falharia pelo mesmo SMTP que causou o `failed` e exigiria uma regra para a falha do aviso não gerar outro aviso.
- **Editar a `0001`:** um banco que já tem a versão 1 nunca receberia a coluna.
- **Uma tabela própria de avisos:** uma tabela a mais para um campo.
- **Avisar a pessoa cadastrada:** o canal seria o e-mail que acabou de falhar.

**Custos**
- A coluna é do schema comum: a NestJS e o Go a recebem sem usá-la, e com a NestJS ativa os eventos `failed` esperam o primeiro resumo depois que a Laravel voltar.
- A limpeza percorre `users_outbox` inteira, sem índice em `processed_at`; serve à POC.
- Agendada para as 03:00 UTC, a limpeza não roda se a stack estiver fora do ar nessa hora; a execução seguinte apaga o acumulado.

## 28. Limitador de cada stack, sem Lua

O contador de tentativas e a cota por IP deixam de rodar scripts Lua do projeto. A stack Laravel usa o `RateLimiter` do framework sobre um cache store `limiter` no `redis-limiter`, e a stack NestJS usa comandos do ioredis em `MULTI`, com `EXPIRE ... NX`. As duas incrementam, comparam o valor devolvido com o limite e desfazem o próprio incremento quando ele passa do limite. Uma devolução que deixaria o contador abaixo de zero, porque a janela expirou no meio, também é desfeita. O `redis-limiter` continua sendo o armazenamento, mas o formato gravado é de cada stack: o contador deixa de ser comum às stacks. [api-contract.md](api-contract.md#limite-de-tentativas) descreve só o comportamento e a regra de hash das chaves. O detalhamento está no [design](../.design/tests-per-stack.md) e no [plano](../.specs/features/registration-limiter-native/plan.md).

**Substitui**, na decisão 5, o contador comum às stacks, com chave e script como contrato entre elas.

**Motivos**
- **Mecanismo nativo de cada stack:** os scripts eram copiados em cada stack, lidos do disco a cada requisição e mantidos iguais por um teste que comparava o texto com o contrato.
- **Paralelismo preservado:** incrementar e comparar o valor devolvido é atômico no Redis, então a cota continua exata com requisições paralelas.

**Alternativas descartadas**
- **Verificar e depois incrementar** (`RateLimiter::tooManyAttempts` seguido de `hit`, ou `attempt`): N requisições paralelas passariam juntas.
- **`@nestjs/throttler` na stack NestJS:** o storage padrão fica em memória, e a interface de storage não devolve unidades, então 409 e 500 consumiriam cota.
- **Comandos Redis iguais nas três stacks, como contrato:** manteria o contador comum, mas sem o mecanismo nativo do framework que o responsável escolheu.

**Custos**
- Um par bloqueado numa stack não fica bloqueado garantidamente na outra.
- A stack Laravel grava uma chave `:timer` ao lado de cada contador, e o `RedisStore` do framework ainda executa um Lua interno ao criar a chave.
- Se o processo cair entre um decremento negativo e a correção, o contador fica em -1 até a janela expirar, o que aceita um cadastro a mais nessa janela.
