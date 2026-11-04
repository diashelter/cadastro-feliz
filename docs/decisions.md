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
- **Limite consistente:** um par IP e e-mail bloqueado continua bloqueado ao trocar de stack.
- **Cadastro independente da fila:** no desenho anterior, uma queda do Redis em Laravel e NestJS derrubava o cadastro junto com a fila.
- **Configurações opostas:** a fila precisa de `noeviction`, e o BullMQ a exige. O contador é descartável e não precisa de persistência.

**Alternativas descartadas**
- **Um Redis comum para tudo:** economiza containers, mas mistura fila e contador e faz uma queda do Redis parar o cadastro.
- **Contador em memória:** zeraria a cada reinício e não funcionaria com réplicas.
- **Contador no Postgres:** contrariaria o objetivo de não carregar o banco.

**Custos**
- Laravel e NestJS têm dois Redis e duas conexões para configurar.
- Chave e script passam a ser um contrato entre as stacks, definido em [api-contract.md](api-contract.md#operação-no-redis).
- Testes do 429 precisam de outro e-mail ou de `make reset-limits`, porque o contador sobrevive à troca de stack.

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

Cada IP pode concluir no máximo `REGISTRATION_MAX_PER_IP` (20) cadastros a cada `REGISTRATION_IP_WINDOW_SECONDS` (1 hora), em janela fixa no `redis-limiter`. A API reserva uma unidade da cota antes da transação, numa operação atômica, e devolve a reserva quando a resposta é 409 ou 500. Só o 201 consome a cota. A chave, os dois scripts e a posição na ordem de processamento estão em [api-contract.md](api-contract.md#limite-por-ip). O detalhamento está no [design](../.design/registration-ip-limit.md).

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
- As três stacks mantêm cópias de mais dois scripts Lua.

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
