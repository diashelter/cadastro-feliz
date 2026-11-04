# Formulário de cadastro checks

Build: none - a checagem de tipos roda dentro de `make test-frontend` e é provada por C20; o repositório não tem lint
Run front: `make test-frontend`
Run infra: `bash tests/infra/run.sh docs frontend test-frontend`
Plan: `.specs/features/registration-form/plan.md`

28 checks in 3 slices · 4 one-way doors · 0 open, of which 0 block

## Checks

### S1 - Formulário e respostas do contrato

**C1** - `localhost:3000/` mostra o título `Cadastro Feliz`, o endereço de `NEXT_PUBLIC_API_URL`, os campos `Nome` e `E-mail` e o botão `Cadastrar`, sem mensagem; `Cadastro Feliz` aparece em `frontend/src` só em `frontend/src/app/page.tsx` (AC 1)
Proof: run front | ✓ Home > shows the title, the API address and the empty form
Proof: run front | ✓ Home > keeps Cadastro Feliz only in page.tsx

**C2** - Usar `Cadastrar` envia exatamente um `POST` a `{NEXT_PUBLIC_API_URL}/users`, com `Content-Type` e `Accept` `application/json` e corpo com nome e e-mail como digitados; um endereço com barra final vira `…/users`, sem `//users` (AC 2)
Proof: run front | ✓ RegistrationForm > sends one POST with the typed values as JSON
Proof: run front | ✓ RegistrationForm > joins an API address that ends with a slash

**C3** - Campos vazios, ou `não-é-email` no e-mail, ainda geram a requisição, sem mensagem do navegador; nenhum campo tem `required`, `maxLength` ou `pattern`, e o formulário tem `noValidate` (AC 3)
Proof: run front | ✓ RegistrationForm > sends empty fields without browser validation
Proof: run front | ✓ RegistrationForm > sends an invalid email without browser validation

**C4** - Durante a requisição o botão fica desabilitado com `Enviando…`; dois cliques seguidos geram 1 requisição, e um clique depois da resposta gera a 2ª (AC 4)
Proof: run front | ✓ RegistrationForm > disables the button with Enviando… while waiting
Proof: run front | ✓ RegistrationForm > sends one request for two quick clicks
Proof: run front | ✓ RegistrationForm > sends a second request after the response

**C5** - Um `201` mostra `Recebemos seus dados! Em instantes você receberá um e-mail de confirmação.` com corpo do contrato, `{}`, vazio ou `não é json`, mantém os campos e reabilita o botão (AC 5)
Proof: run front | ✓ RegistrationForm > shows success for a 201 with any body
Proof: run front | ✓ RegistrationForm > keeps the typed values after a 201

**C6** - `409`/`422` mostram em cada campo o texto do seu primeiro item, nada no campo sem item e nenhuma mensagem geral, nos três exemplos do plano (AC 6)
Proof: run front | ✓ RegistrationForm > shows the first item of each field
Proof: run front | ✓ RegistrationForm > shows only the first item when a field has two
Proof: run front | ✓ RegistrationForm > shows already_taken on the email field for a 409

**C7** - Os seis pares `field`/`code` mostram exatamente os seis textos do plano (AC 7)
Proof: run front | ✓ RegistrationForm > maps every field and code to its text

**C8** - Campo conhecido com `code` sem texto mostra `Verifique este campo.`, para `email`/`blocked` e `name`/`already_taken` (AC 8)
Proof: run front | ✓ RegistrationForm > shows Verifique este campo. for an unknown code

**C9** - `409`/`422` com `errors: []`, só um item de `phone`, `errors` ausente ou `null`, um item sem `code` ao lado de um válido, ou corpo `não é json`, mostram o texto do `500` e nenhum texto por campo (AC 9)
Proof: run front | ✓ RegistrationForm > treats a field error body outside the contract as a 500

**C10** - `429` com `Retry-After` `742`, `900`, `61`, `60` e `0` mostra `… em 13 minutos.`, `… em 15 minutos.`, `… em 2 minutos.`, `… em 1 minuto.` e `… em 1 minuto.` (AC 10)
Proof: run front | ✓ RegistrationForm > shows the minutes of a 429 rounded up

**C11** - `429` sem `Retry-After`, ou com `abc`, `-5`, `12.5` ou uma data HTTP, mostra `Muitas tentativas de cadastro. Tente novamente mais tarde.` (AC 11)
Proof: run front | ✓ RegistrationForm > shows mais tarde for a 429 without a readable Retry-After

**C12** - `500` mostra `Não foi possível concluir seu cadastro. Tente novamente em instantes.` (AC 12)
Proof: run front | ✓ RegistrationForm > shows the 500 text for a 500

**C13** - `200`, `400`, `404`, `405` e `503` mostram o texto do `500` (AC 13)
Proof: run front | ✓ RegistrationForm > shows the 500 text for a status outside the contract

**C14** - Um `fetch` que rejeita mostra `Serviço indisponível no momento. Tente novamente em instantes.` (AC 14)
Proof: run front | ✓ RegistrationForm > shows the network failure text when fetch rejects

**C15** - Um novo envio apaga os textos por campo de um `422` e a mensagem geral de um `201` antes de a resposta chegar (AC 15)
Proof: run front | ✓ RegistrationForm > clears field texts when a new request starts
Proof: run front | ✓ RegistrationForm > clears the general message when a new request starts

**C16** - O texto de cada campo é a descrição acessível do campo, e a mensagem geral fica em `role="status"` (AC 16)
Proof: run front | ✓ RegistrationForm > describes each field with its text
Proof: run front | ✓ RegistrationForm > announces the general message in a status

**C17** - Com nenhuma stack no ar, usar `Cadastrar` em `localhost:3000` num navegador mostra `Serviço indisponível no momento. Tente novamente em instantes.` (AC 17)
Proof: walk - abrir `localhost:3000` sem stack, preencher e usar `Cadastrar`

### S2 - `make test-frontend`

**C18** - Num clone limpo, `make test-frontend` sai com `0` depois de checar os tipos e rodar o Vitest, e `frontend/node_modules` não existe na máquina depois (AC 18)
Proof: run infra | PASS RF18 test-frontend passes on a clean clone

**C19** - Com um teste que falha, `make test-frontend` sai com código diferente de `0` e mostra o nome do teste (AC 19)
Proof: run infra | PASS RF19 test-frontend fails on a failing test

**C20** - Com um erro de tipo em `frontend/src`, `make test-frontend` sai com código diferente de `0`, mostra `error TS` e não roda o Vitest (AC 20)
Proof: run infra | PASS RF20 test-frontend stops on a type error

**C21** - Com o `frontend` no ar, `make test-frontend` mantém o ID e o estado `running` do container, e `GET localhost:3000/` responde `200` depois (AC 21)
Proof: run infra | PASS RF21 test-frontend leaves frontend running

**C22** - Depois de um `make test-frontend` verde, um teste que falha acrescentado em `frontend/src` faz o próximo `make test-frontend` sair com código diferente de `0` (AC 22)
Proof: run infra | PASS RF22 test-frontend uses the current code

**C23** - `frontend/package.json` tem `vitest`, `@vitejs/plugin-react`, `jsdom`, `@testing-library/react`, `@testing-library/dom` e `@testing-library/user-event` em `devDependencies`, sem `^` nem `~` (AC 23)
Proof: run infra | PASS RF23 test dependencies are exact

**C24** - `make help` lista `make test-frontend` (AC 24)
Proof: run infra | PASS RF24 help lists test-frontend

### S3 - Documentação alinhada

**C28** - Num ambiente sem nada do projeto, `make test-frontend` sai com `0` e não deixa nenhum container, rede ou volume `cadastro-feliz-*` (AC 28)
Proof: run infra | PASS RF28 test-frontend leaves no environment behind

**C25** - docs/api-contract.md › Comportamento do frontend diz que não há validação no navegador, que `201` é sucesso com qualquer corpo, que `409`/`422` sem item de `name` ou `email` mostram o texto do `500`, a regra dos minutos com `1 minuto`, e `Muitas tentativas de cadastro. Tente novamente mais tarde.` (AC 25)
Proof: run infra | PASS RF25 contract describes form rules

**C26** - docs/decisions.md tem a decisão `18` "Formulário sem validação no navegador", `Definida`, no índice, e a seção cita `422` e o cenário 3 (AC 26)
Proof: run infra | PASS RF26 decision 18 recorded

**C27** - docs/stacks.md › Frontend não diz mais que só existe o esqueleto e cita `make test-frontend`; docs/infrastructure.md › Makefile lista `make test-frontend`; o README não diz mais que o frontend é um esqueleto sem o formulário e mostra `make test-frontend` em › Como vai funcionar (AC 27)
Proof: run infra | PASS RF27 docs describe the form and test-frontend

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| Landing doors (4) | chamada à API C2 · sem validação no navegador C3 · C26 · leitura das respostas C5 · C9 · C10 · C11 · C13 · test runner do frontend C18 · C23 | - |
| respostas lidas pelo formulário (8) | `201` C5 · `409` C6 · `422` C6 · `429` legível C10 · `429` ilegível C11 · `500` C12 · outro status C13 · falha de rede C14 · C17 | - |
| pares `field`/`code` (6) | C7, table-driven over all 6 | - |
| corpo fora do contrato, AC 9 (5 exemplos) | `errors: []` C9 · só `phone` C9 · `errors` ausente ou `null` C9 · item sem `code` C9 · `não é json` C9 | - |
| minutos do 429, AC 10 (5 exemplos) | `742` C10 · `900` C10 · `61` C10 · `60` C10 · `0` C10 | - |
| `Retry-After` ilegível, AC 11 (5 exemplos) | ausente C11 · `abc` C11 · `-5` C11 · `12.5` C11 · data HTTP C11 | - |
| outros status, AC 13 (5) | `200` C13 · `400` C13 · `404` C13 · `405` C13 · `503` C13 | - |
| corpos do 201, AC 5 (4) | do contrato C5 · `{}` C5 · vazio C5 · `não é json` C5 | - |
| controles (3) | campo `Nome` C2 · campo `E-mail` C2 · botão `Cadastrar` C2 · C4 | - |
| `make test-frontend` situações (6) | clone limpo C18 · teste falho C19 · erro de tipo C20 · frontend no ar C21 · código mudado C22 · ambiente vazio C28 | - |
| dependências novas (6) | `vitest` C23 · `@vitejs/plugin-react` C23 · `jsdom` C23 · `@testing-library/react` C23 · `@testing-library/dom` C23 · `@testing-library/user-event` C23 | - |
| documentos alterados (5) | `docs/api-contract.md` C25 · `docs/decisions.md` C26 · `docs/stacks.md` C27 · `docs/infrastructure.md` C27 · `README.md` C27 | - |
| leitores da página em `tests/infra/frontend.sh` (5) | FE1 C1 · FE3 C1 · FE4 C1 · FE9 C1 · FE14 C1 - rodam no mesmo `Run infra` | - |

## Swept

- validation: C3 - a ausência de validação no navegador é a regra; a requisição sai mesmo com campos vazios
- failure modes: C9, C13, C14 - corpo fora do contrato, status inesperado e falha de rede
- idempotency: C4 - um duplo clique não gera uma segunda requisição
- authorization: n/a - formulário público, como `POST /users`
- concurrency: C4 - só uma requisição por vez
- data lifecycle: C5 - os campos mantêm o que foi digitado depois da resposta
- dependency failure: C14, C17 - nenhuma stack no ar
- state transitions: C4, C15 - Pronto, Enviando e os três resultados do diagrama do plano
- observability: n/a - o formulário não registra nada; o diagnóstico de CORS fica no console do navegador

## Handoff

- **Settled mid-build:** none
- **Dispatched:** Verifier at `4d7ea28` (proofs.md do Docker indisponível neste ambiente; evidência de unidade em npm test no host)
- **Boundary:** C1-C27 built at `12fa415`; C1-C16 green no host (Node 22, `tsc --noEmit` e `vitest run`, 26 testes), C25-C27 green em `bash tests/infra/run.sh docs`, C17 walked; C18-C24 e os leitores FE1/FE3/FE4/FE9/FE14 precisam da imagem do frontend, que não constrói neste ambiente
- **Abandoned:** `vitest` 5.1.0 - pede `@types/node` ≥ 22 e o projeto fixa 20.19.43; ficou `vitest` 4.1.12, que aceita 20. As dependências entraram pelo npm 11 do host (`npx npm@11`), porque `make frontend-npm` precisa de rede dentro do container e o npm 10 do host falha com `edgesOut`
- **Environment:** Docker sem rede dentro dos containers: o `npm ci` do Dockerfile falha, então `make test-frontend` e os testes de `tests/infra/frontend.sh` e `tests/infra/test-frontend.sh` não rodam aqui; rodam numa máquina com Docker e acesso ao registro do npm
- **Walked:** `next dev` no host com `NEXT_PUBLIC_API_URL=http://localhost:8080` e nada escutando em 8080; no Chromium, abrir `localhost:3000`, preencher `Ana Souza` e `ana@example.com` e usar `Cadastrar`: a página mostrou `Serviço indisponível no momento. Tente novamente em instantes.`, os campos continuaram preenchidos e o botão voltou a `Cadastrar` habilitado (C17). O `next dev` 16.4.5 gera `AGENTS.md` na pasta em que roda; no container isso fica em `/app` e não chega à máquina
