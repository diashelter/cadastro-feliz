# Container do frontend checks

Build: none - o repositório não tem build, lint nem type check; o Dockerfile, o compose e o Makefile são exercidos pelas provas, e o `next dev` compila o esqueleto em C1
Run infra: `make test-infra`
Plan: `.specs/features/frontend-container/plan.md`

28 checks in 5 slices · 3 one-way doors · 0 open, of which 0 block

## Checks

### S1 - Frontend no ar com `make up-shared`

**C1** - `make up-shared` em clone limpo sai com `0`, deixa `postgres`, `redis-limiter`, `mailpit` e `frontend` `healthy`, e `GET localhost:3000/` responde `200` com HTML que contém `Cadastro Feliz` e `localhost:8080` (AC 1)
Proof: run infra | PASS FE1 up-shared serves skeleton

**C2** - Segundo `make up-shared` sem mudança sai com `0`, mantém os quatro IDs de container e o ID da imagem `cadastro-feliz-shared-frontend` (AC 2)
Proof: run infra | PASS FE2 up-shared rerun keeps frontend

**C3** - Com `Cadastro Feliz` trocado por `Cadastro Probe` em `frontend/src/app/page.tsx`, sem watch, `make up-shared` serve HTML com `Cadastro Probe` e sem `Cadastro Feliz` (AC 3)
Proof: run infra | PASS FE3 up-shared serves current code

**C4** - Com `NEXT_PUBLIC_API_URL` trocado no `.env` para o endereço da porta 9090, `make up-shared` serve HTML com `localhost:9090` e sem `localhost:8080`, com o mesmo ID de imagem (AC 4)
Proof: run infra | PASS FE4 api url read at start

**C5** - As portas publicadas pelo projeto `cadastro-feliz-shared` são exatamente {3000, 5432, 8025} (AC 5)
Proof: run infra | PASS C5 published ports and network ports

**C6** - As imagens do compose comum são exatamente as quatro fixadas mais `cadastro-feliz-shared-frontend`, e `frontend/Dockerfile` tem `FROM node:26.13.0-alpine` (AC 6)
Proof: run infra | PASS C7 pinned images
Proof: run infra | PASS FE6 frontend base image

**C7** - Com a porta `3000` ocupada por outro container, `make up-shared` sai com código diferente de zero (AC 7)
Proof: run infra | PASS C8 up-shared fails on taken port 3000

**C8** - Com `frontend/package-lock.json` inválido, `make up-shared` sai com código diferente de zero e `postgres`, `redis-limiter` e `mailpit` ficam `healthy` (AC 8)
Proof: run infra | PASS FE8 frontend build failure keeps shared

**C9** - Com um erro de compilação em `frontend/src/app/page.tsx`, o `frontend` continua `healthy` 20 s depois e `GET localhost:3000/` responde `500` (AC 9)
Proof: run infra | PASS FE9 compile error keeps frontend healthy

**C10** - O processo do container do `frontend` roda com uid `1000` (`node`) e a linha de comando contém `next dev` (AC 10)
Proof: run infra | PASS FE10 frontend runs next dev as node

**C11** - `frontend/package.json` tem `next` `16.4.5`, `react` `19.3.1`, `react-dom` `19.3.1`, e nenhuma versão em `dependencies` nem `devDependencies` começa com `^` ou `~` (AC 11)
Proof: run infra | PASS FE11 exact dependency versions

**C12** - O `.gitignore` ignora `frontend/node_modules` e `frontend/.next` (`git check-ignore`), e `frontend/.env` não existe (AC 12)
Proof: run infra | PASS FE12 frontend ignores and no env

### S2 - Edição pelo `make watch-frontend`

**C13** - Num clone limpo, com `frontend/src/app/page.tsx` editado antes, `make watch-frontend` cria `.env` e a rede, deixa o `frontend` `healthy` servindo a edição e continua rodando (AC 13)
Proof: run infra | PASS FE13 watch starts frontend with current code

**C14** - Com o watch ativo, uma edição de `frontend/src/app/page.tsx` aparece em `GET localhost:3000/` em até 10 s, com o mesmo ID de container (AC 14)
Proof: run infra | PASS FE14 watch syncs edit

**C15** - Com o watch ativo, criar `frontend/src/app/probe/page.tsx` faz `GET localhost:3000/probe` responder `200` em até 10 s, e apagá-lo faz responder `404` em até 10 s (AC 15)
Proof: run infra | PASS FE15 watch syncs create and delete

**C16** - Com o watch ativo, mudar `frontend/package.json`, `frontend/package-lock.json` ou `frontend/next.config.ts` deixa o `frontend`, em até 120 s cada, num container de ID novo, `healthy`, com `GET localhost:3000/` `200` (AC 16)
Proof: run infra | PASS FE16 watch rebuilds on package.json
Proof: run infra | PASS FE16 watch rebuilds on package-lock.json
Proof: run infra | PASS FE16 watch rebuilds on next.config.ts

**C17** - Depois de SIGINT em `make watch-frontend`, o container do `frontend` está `running` com o mesmo ID e `GET localhost:3000/` responde `200` (AC 17)
Proof: run infra | PASS FE17 watch interrupt keeps frontend

### S3 - Dependências por `make frontend-npm`

**C18** - `make frontend-npm ARGS="install is-number@7.0.0"` grava `"is-number": "7.0.0"` em `dependencies` e `node_modules/is-number` `7.0.0` no lock; `make frontend-npm ARGS="install is-odd"` grava uma versão sem `^` nem `~`; `frontend/node_modules` não existe na máquina e `frontend/package.json` pertence ao uid de quem rodou o `make` (AC 18)
Proof: run infra | PASS FE18 frontend-npm writes exact versions only

**C19** - `make frontend-npm` sem `ARGS` imprime `uso: make frontend-npm ARGS="<comando npm>"`, sai com código diferente de zero e nenhum container `cadastro-feliz-` passa a existir (AC 19)
Proof: run infra | PASS FE19 frontend-npm refuses without args

**C20** - Com o `frontend` no ar, `make frontend-npm ARGS="--version"` sai com `0`, e o container do `frontend` mantém o ID e responde `200` em 3000 (AC 20)
Proof: run infra | PASS FE20 frontend-npm leaves frontend running

**C21** - Depois de `make frontend-npm ARGS="install is-number@7.0.0"` e `make up-shared`, o container do `frontend` tem `/app/node_modules/is-number` (AC 21)
Proof: run infra | PASS FE21 up-shared installs new dependency

### S4 - Frontend fora do caminho do migrate e das stacks

**C22** - Com `frontend/package-lock.json` inválido, `make migrate` sai com `0` com a versão `1` aplicada, e `make up-go` com uma stack falsa sai com `0` com a stack `healthy` (AC 22)
Proof: run infra | PASS FE22 broken frontend does not block migrate or stack

**C23** - Num clone limpo, depois de `make migrate`, e depois de `make up-go` com uma stack falsa, nenhum container do serviço `frontend` existe (AC 23)
Proof: run infra | PASS FE23 migrate and stack do not start frontend

### S5 - Documentação alinhada

**C24** - `docs/decisions.md` tem a decisão `16` "Frontend em `next dev` com o código copiado pelo Compose Watch", origem `Definida`, no índice, e a seção cita `next dev`, `Compose Watch`, `bind mount` e `Turbopack` (AC 24)
Proof: run infra | PASS FE24 decision 16 recorded

**C25** - `docs/infrastructure.md` não diz mais que o serviço `frontend` não existe; › Makefile lista `make watch-frontend` e `make frontend-npm`, e a linha de `make migrate` cita `postgres`, `redis-limiter` e `mailpit`; › Versões fixadas lista `node:26.13.0-alpine` (AC 25)
Proof: run infra | PASS FE25 infrastructure docs describe frontend

**C26** - `README.md` não diz mais que o frontend está em design, e › Como vai funcionar mostra `make up-shared` antes do primeiro `make up-` de stack e mostra `make watch-frontend` e `make frontend-npm` (AC 26)
Proof: run infra | PASS FE26 readme describes frontend

**C27** - `docs/stacks.md` › Frontend cita `next dev`, `make watch-frontend` e `make frontend-npm` (AC 27)
Proof: run infra | PASS FE27 stacks docs describe frontend

**C28** - A saída de `make help` lista `make watch-frontend` e `make frontend-npm` (AC 28)
Proof: run infra | PASS FE28 help lists frontend targets

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| Landing doors (3) | execução do frontend C1 · C10 · C14 · C16 · fluxo de dependências C18 · C11 · dependências novas C6 · C11 | - |
| comandos de Shape › Comandos (5) | `make up-shared` C1 · `make watch-frontend` C13 · `make frontend-npm` C18 · `make migrate` C22 · `make up-<stack>` C22 | - |
| erros de `make up-shared` (3 causas) | porta 3000 C7 (5432 e 8025: C8 de shared-infrastructure) · build do `frontend` C8 · serviço não saudável: n/a - nenhum caso além do build é provocável sem quebrar a imagem, coberto por C8 | - |
| erros de `make frontend-npm` (2) | `ARGS` vazio C19 · npm falha: C18 propaga o código do npm por ser o último comando do alvo | - |
| portas publicadas (3) | 3000 C5 · 5432 C5 · 8025 C5 | - |
| imagens (5) | `postgres:18.6-alpine` C6 · `redis:8.10.3-alpine` C6 · `axllent/mailpit:v1.33.0` C6 · `migrate/migrate:v4.20.1` C6 · `cadastro-feliz-shared-frontend` C6 | - |
| gatilhos de rebuild do watch (3) | `package.json` C16 · `package-lock.json` C16 · `next.config.ts` C16 | - |
| ações de sync do watch (3) | edição C14 · criação C15 · remoção C15 | - |
| AC 3 (1 exemplo) | `Cadastro Probe` C3 | - |
| AC 4 (1 exemplo) | porta 9090 C4 | - |
| AC 18 (2 exemplos) | versão explícita C18 · sem versão C18 | - |
| serviços que `migrate` e `up-<stack>` não tocam (2 comandos) | `make migrate` C22 · C23 · `make up-<stack>` C22 · C23 | - |
| docs (5 lugares) | `docs/decisions.md` C24 · `docs/infrastructure.md` C25 · `README.md` C26 · `docs/stacks.md` C27 · `make help` C28 | - |

## Swept

- validation: C19
- failure modes: C8, C9, C22
- idempotency: C2
- authorization: n/a - comandos locais sem identidade de quem chama; o container roda sem root (C10)
- concurrency: C20 - `frontend-npm` com o `frontend` no ar; dois `make` simultâneos não são suportados por nenhum alvo do projeto
- data lifecycle: C4 (variável lida a cada início), C18 (só `package.json` e o lock mudam na máquina); o cache `.next` perdido ao recriar é a suposição aceita no plano
- dependency failure: C8, C22 - o registro do npm ou o lock quebrado só afetam o `frontend`
- state transitions: C13, C16, C17 - watch iniciado, rebuild que recria, interrupção que mantém o container
- observability: existing - `make logs-shared` acompanha todos os serviços do projeto comum (C25 de shared-infrastructure), o `frontend` incluído

## Handoff

- **Settled mid-build:** user: "pode seguir com a verificação"
- **Dispatched:** Verifier at `163b45b` (no screens sub-agent: no criterion cites a capture)
- **Boundary:** C1-C28 closed at `163b45b` (código em `043e77d`, correção de C2, C3 e C4 em `163b45b`)
- **Abandoned:** encaminhador TCP do Docker para o proxy da sessão - recusado pelo ambiente. `build: ./frontend` sem `provenance: false` - a atestação de proveniência leva a data do build e muda o ID da imagem a cada `up --build` sem mudança (C2 e C4 falharam). Título em `layout.tsx` - o `<title>` continuava `Cadastro Feliz` depois de editar a página (C3 falhou); o título está no `page.tsx`
- **Ambiente de prova:** os containers desta sessão não têm rede de saída. A tag local `node:26.13.0-alpine` foi sobreposta, só neste Docker, por uma imagem construída da oficial com o cache do npm preenchido (lock do frontend, `is-number` 6 e 7, `is-odd`) e `NPM_CONFIG_OFFLINE=true`. O repositório não sabe disso: numa máquina com rede, o mesmo Dockerfile parte da imagem oficial e o npm usa o registro. O tempo de 2 s no Mac do responsável não foi medido aqui (Out of scope do plano)
