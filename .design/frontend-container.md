# Container do frontend

> Plan from this document. Each slice below carries its own shape - copy it, do not re-derive it.
> Status: decisão já tomada em docs/infrastructure.md e no README (responsável do projeto); forma confirmada pelo responsável do projeto, 2026-11-04

## Situation

- Project: in active construction. Os serviços comuns (`postgres`, `redis-limiter`, `mailpit`, `migrate`), o schema e o `Makefile` existem e são testados por `make test-infra`; não há nenhuma linha de código do frontend nem de stack.
- Decision: committed. O frontend é um serviço Next.js do projeto `cadastro-feliz-shared`, sempre disponível em `localhost:3000`, com `NEXT_PUBLIC_API_URL` apontando para a API (docs/infrastructure.md, README). Esta sessão decidiu só a forma do container.
- In flight: copia de .design/shared-infrastructure.md as imagens oficiais em versão exata, a rede externa `cadastro-feliz-net`, o Makefile como único orquestrador e os testes em `tests/infra`. O formulário e os textos de docs/api-contract.md › Comportamento do frontend ficam para uma rodada própria.
- At stake: reverte-se em uma tarde, porque nada depende do container além da rodada do formulário. O que pesa é o fluxo de edição que essa rodada vai usar todos os dias.

## Problem

Construção. A documentação promete o formulário em `localhost:3000`, ao lado dos serviços comuns, e o README promete que a máquina só precisa de Docker e `make`. O design da infraestrutura comum deixou o Dockerfile e o serviço `frontend` para depois, porque um Dockerfile sem código para construir não pode ser verificado.

Sem o container, a rodada do formulário não tem onde rodar o Next.js sem Node instalado na máquina, o que quebra a promessa do README. Ela teria também de desenhar o formulário e o próprio ambiente ao mesmo tempo. O formulário é a próxima peça e não depende de nenhuma stack, por isso o container vem agora.

Nada foi medido, porque ainda não existe produto. A restrição que pesou foi documental: o responsável roda Docker Desktop no macOS, e o guia de desenvolvimento local do Next.js avisa que, nesse ambiente, os eventos de arquivo de um bind mount podem atrasar ou se perder.

## Success

- Worked if: num clone limpo, `make up-shared` deixa `localhost:3000` respondendo com o esqueleto. No Mac do responsável, com `make watch-frontend` rodando, uma edição de página aparece no navegador em até 2 s, sem reiniciar o container. A rodada do formulário começa sem editar o Dockerfile, o compose nem o Makefile.
- Going wrong: as edições demoram ou não aparecem com o watch ativo, ou a rodada do formulário precisa mexer na infraestrutura para acrescentar uma dependência.
- Review: no início da rodada do formulário, pelo responsável do projeto.

## Boundary

In: o esqueleto do projeto Next.js em `frontend/`, com uma página mínima; o Dockerfile; o serviço `frontend` no `docker-compose.yml` da raiz, com a configuração de watch; os alvos do Makefile; os testes do frontend em `tests/infra`; a decisão 16 em docs/decisions.md; e as atualizações de docs/infrastructure.md (status, tabela do Makefile, versões fixadas), docs/stacks.md › Frontend e do README (status, como vai funcionar, estrutura).

Out:
- Formulário, schema de validação, serviço de cadastro e textos de docs/api-contract.md: ficam para a rodada do formulário.
- Build de produção (`next build`, saída standalone): ver Key decision 1.
- Lint e test runner do frontend: entram com o formulário, o primeiro código com regra para verificar.
- CORS: pertence a cada stack (docs/infrastructure.md › Comunicação do frontend).

Unchanged: porta 3000; `NEXT_PUBLIC_API_URL` e `CORS_ALLOWED_ORIGIN` com os valores atuais; o nome do projeto `cadastro-feliz-shared` e da rede `cadastro-feliz-net`; os passos de `make up-<stack>` em docs/infrastructure.md; a estrutura `frontend/src/modules/registration` de docs/stacks.md, que só a rodada do formulário cria.

## Prior art

- O guia de desenvolvimento local do Next.js diz que, com Docker Desktop no macOS ou no Windows, eventos de arquivo de um bind mount podem atrasar ou se perder, deixando o Fast Refresh com segundos ou minutos de atraso. O guia recomenda rodar fora do Docker ou usar synchronized file shares, e deixar polling como último recurso. Não seguimos nenhum dos dois: rodar fora do Docker quebra a promessa do README, e synchronized file shares exige assinatura paga do Docker Desktop. A Key decision 2 existe por isso.
- A correção mais citada pela comunidade, `WATCHPACK_POLLING=true`, só vale para o webpack. No Next.js 16, `next dev` usa o Turbopack por padrão, e a variável não tem efeito: não copie esse padrão.
- O Compose Watch, da documentação do Docker, aplica `sync` no código-fonte e `rebuild` quando `package.json` muda, e é o exemplo oficial para Node com bundler e HMR. Adotamos. A falha que a documentação descreve é o usuário do container sem permissão de escrita no destino, ou a imagem sem `stat`, `mkdir` e `rmdir`; nesses casos, a sincronização falha.
- O padrão de bind mount com um volume anônimo sobre `node_modules` deixa o `node_modules` velho quando o lock muda. Não montamos o código, então o problema não aparece (Key decision 5).
- O Next.js recomenda Docker para produção, com saída standalone. Não temos produção (Key decision 1).

## Shape

O `frontend` é um serviço do projeto comum construído a partir de `frontend/`. Sua imagem leva o código e as dependências, e o container executa `next dev` na porta 3000. As edições chegam ao container por cópia, pelo Compose Watch, e não por bind mount: o evento de arquivo nasce dentro do container, então o Turbopack o recebe da mesma forma no macOS e no Linux. A porta difícil de reabrir é o fluxo de trabalho da rodada do formulário, que edita com `make watch-frontend` em um terminal e adiciona dependências por `make frontend-npm`; trocá-lo depois custa um Dockerfile, o compose e dois alvos.

O bind mount simples dispensaria o terminal extra. Ele só ganharia se o Docker rodasse direto no Linux, o que não acontece na máquina de quem vai desenvolver o formulário.

## Key decisions

1. **O container roda sempre `next dev`; esta POC não tem build de produção do frontend.** O formulário é um coadjuvante idêntico nas três stacks, e o que se estuda é a API e o outbox. Se alguém precisar medir o frontend em produção, isso exige um target novo no Dockerfile, sem mexer no serviço atual.
2. **O código chega ao container só por cópia, nunca por bind mount.** A imagem leva o código; `make watch-frontend` sincroniza cada edição e reconstrói a imagem quando `package.json` ou `package-lock.json` mudam. Não troque por bind mount com polling: o polling não funciona com o Turbopack (Prior art).
3. **Depois de `make up-shared`, o que responde em 3000 é o código que está em `frontend/` naquele momento.** `make up-shared` reconstrói a imagem do frontend em toda execução; o cache de camadas deixa isso rápido quando nada mudou. Sem isso, uma edição feita sem o watch ficaria invisível até um rebuild manual.
4. **Uma falha do frontend nunca impede o `migrate` nem uma stack de subir.** `make migrate` e `make up-<stack>` sobem e esperam só `postgres`, `redis-limiter` e `mailpit`, como na sequência atual de docs/infrastructure.md, e não constroem a imagem do frontend. `make up-shared` sobe o frontend e falha se ele não ficar saudável. Assim, a API continua testável por curl com o frontend quebrado, e os testes de migrate e de stack não dependem do npm.
5. **Dependências mudam só por `make frontend-npm`, e `node_modules` nunca existe na máquina.** O alvo roda o npm dentro de um container e grava só `package.json` e `package-lock.json` em `frontend/`. A imagem instala a partir do lock, que é a fonte de verdade das dependências.
6. **`NEXT_PUBLIC_API_URL` é lido do `.env` da raiz quando o container inicia, e não durante o build da imagem.** Trocar o valor e rodar `make up-shared` recria o container com o novo endereço. `frontend/` não tem `.env` próprio, porque o `.env` da raiz é a única fonte das variáveis (docs/infrastructure.md).
7. **A imagem base é a Node LTS oficial em Alpine, fixada em versão exata.** A tag é a mais recente disponível na implementação, como nos serviços comuns, e o Next.js também é fixado em versão exata no `package.json`. Ela entra na tabela de versões fixadas de docs/infrastructure.md.

## Work

| Slice | Delivers | Status |
|---|---|---|
| [frontend](#frontend) | Esqueleto Next.js, Dockerfile e serviço `frontend` saudável em 3000, com watch configurado | open — 3 defaults taken |
| [Makefile](#makefile) | `up-shared` com o frontend, `watch-frontend`, `frontend-npm` e testes em `tests/infra` | open — 3 defaults taken |

Order: frontend → Makefile.

Já tratados pelo código existente: `make down` remove o container do frontend com os demais do projeto comum; `make status` lista os containers `cadastro-feliz-*`; `make logs-shared` acompanha todos os serviços do projeto comum.

Derivable from the repository, left to the plan: healthcheck com `interval`, `start_period` e `start_interval` como nos serviços comuns; comentários em português no compose e no Makefile; mensagens de recusa do Makefile no formato de `require_stack`; testes com `check "<id> <nome>"` como em `tests/infra`, tudo como o projeto `cadastro-feliz-shared` já faz.

### frontend

**Delivers** o projeto Next.js mínimo em `frontend/` e o serviço `frontend` do projeto comum, publicado em 3000. **Status: open.** É a porta (Key decisions 1, 2 e 7).

| State | What should happen | Caller sees |
|---|---|---|
| Primeira execução, sem imagem | A imagem é construída com `npm ci` a partir do lock, e o container fica saudável | `localhost:3000` mostra o esqueleto |
| Execução repetida sem mudanças | A imagem vem do cache, e o container não é recriado | O mesmo esqueleto |
| `frontend/` editado sem watch, depois `make up-shared` | A imagem é reconstruída e o container é recriado (Key decision 3) | A página com a edição |
| Arquivo editado ou criado com o watch ativo | O arquivo é copiado para o container, e o Turbopack recompila sem reiniciar | A edição em até 2 s, por Fast Refresh |
| Arquivo apagado com o watch ativo | O arquivo também é apagado no container | A página sem o arquivo |
| `package.json` ou lock alterado com o watch ativo | A imagem é reconstruída e o container é recriado (Key decision 2) | A página volta depois do rebuild |
| Erro de compilação na página | O container continua saudável | A tela de erro do Next.js no navegador |
| npm sem rede no primeiro build | O build falha; `postgres`, `redis-limiter` e `mailpit` continuam no ar (Key decision 4) | `make up-shared` sai com erro e mostra a saída do npm |
| Porta 3000 ocupada na máquina | O Compose falha com o erro de porta | `make up-shared` sai com erro |
| `NEXT_PUBLIC_API_URL` alterado no `.env` | O container é recriado com o novo valor, sem rebuild do código (Key decision 6) | O esqueleto mostra o novo endereço |
| Nenhuma stack ativa | Nada muda: o esqueleto não chama a API | O esqueleto |

O esqueleto usa App Router e TypeScript, com o código em `frontend/src/app`, como prevê a estrutura de docs/stacks.md. A página mostra o nome do projeto e o valor de `NEXT_PUBLIC_API_URL`, o que prova que a variável chegou ao navegador. A rodada do formulário substitui essa página.

Alternatives considered: bind mount simples, que ganharia se o Docker rodasse direto no Linux; um target de produção ao lado do de desenvolvimento, que ganharia se algum cenário de validação medisse o frontend.

1. Saudável significa que o servidor responde HTTP em 3000, com qualquer status. Default: um erro de compilação aparece no navegador e não derruba `make up-shared`.
2. npm como gerenciador de pacotes. Default: npm, que vem na imagem do Node e não pede nada a mais.
3. O cache `.next` fica dentro do container e se perde quando ele é recriado. Default: aceitar alguns segundos a mais na primeira compilação depois de recriar, em vez de criar um volume.

### Makefile

**Delivers** os alvos que sobem, sincronizam e alteram o frontend, e a cobertura deles em `make test-infra`. **Status: open.**

| State | What should happen | Caller sees |
|---|---|---|
| `make up-shared` | Sobe os três serviços comuns e o frontend, reconstrói a imagem do frontend e espera os quatro ficarem saudáveis | Sai com sucesso só com os quatro saudáveis |
| `make migrate` ou `make up-<stack>` | Sobe e espera só `postgres`, `redis-limiter` e `mailpit`, sem construir o frontend (Key decision 4) | Mesmo resultado de hoje, mesmo com o frontend quebrado |
| `make up-<stack>` num clone limpo, sem `make up-shared` antes | A stack sobe; o frontend continua fora | `localhost:3000` recusa a conexão até `make up-shared` |
| `make watch-frontend` | Cria `.env` e a rede se não existirem, sobe o frontend se ele não estiver no ar e fica em primeiro plano sincronizando `frontend/` | A saída do watch no terminal |
| Ctrl+C em `make watch-frontend` | A sincronização para; o container continua no ar com o último código sincronizado | `localhost:3000` continua respondendo |
| `make frontend-npm ARGS="install <pacote>"` | Roda o npm num container descartável; só `package.json` e `package-lock.json` mudam em `frontend/` (Key decision 5) | A saída do npm; nenhum `node_modules` aparece na máquina |
| `make frontend-npm` sem `ARGS` | Recusa antes de criar qualquer container | Uma mensagem com o uso do alvo |
| `make test-infra` | Os testes do frontend ficam em arquivo próprio; os testes de migrate e de stack não constroem a imagem do frontend | `PASS`/`FAIL` por check, como hoje |

Alternatives considered: `make up-<stack>` subir também o frontend sem esperar por ele ganharia se o caminho comum fosse ir direto para uma stack num clone limpo. Com isso, porém, todo teste de stack construiria a imagem Node.

1. `make up-<stack>` não sobe o frontend. Default: o README manda rodar `make up-shared` primeiro, e `make down-<stack>` nunca derruba o frontend.
2. Nomes dos alvos. Default: `watch-frontend` e `frontend-npm`, um verbo para o fluxo de edição e o nome da ferramenta para o repasse de comandos.
3. Os testes do frontend precisam de rede para o npm. Default: aceitar, porque o primeiro build depende do registro do npm de qualquer forma; o caso "npm sem rede" é coberto pela mensagem de erro, sem teste automatizado.

## Sources

- docs/infrastructure.md: projeto comum, porta 3000, variáveis, sequência de `make up-<stack>` e versões fixadas.
- README: a promessa de que só são necessários Docker e `make`, e a estrutura do repositório.
- docs/stacks.md › Frontend: a estrutura planejada de `frontend/`.
- .design/shared-infrastructure.md: o serviço `frontend` adiado até haver código, as imagens em versão exata e o Makefile como orquestrador.
- Next.js, guia Local Development: Docker no macOS e no Windows, synchronized file shares e polling como último recurso.
- Next.js, guia de upgrade para a versão 16 e CLI `next dev`: Turbopack como padrão e `--webpack` para sair dele.
- Next.js, watchpack vendorizado: `WATCHPACK_POLLING` só afeta o webpack.
- Docker, Compose file watch: as ações `sync` e `rebuild`, `initial_sync` e os pré-requisitos (`stat`, `mkdir`, `rmdir`, usuário com escrita no destino).
- Docker, Synchronized file shares: disponível só nas assinaturas Pro, Team e Business.
