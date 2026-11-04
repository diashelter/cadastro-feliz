# Formulário de cadastro

> Plan from this document. Each slice below carries its own shape - copy it, do not re-derive it.
> Status: decisão já tomada no README, em docs/api-contract.md › Comportamento do frontend e na fatia `RegistrationForm` de .design/api-error-response.md (responsável do projeto); forma confirmada por diashelter, 2026-11-04

## Situation

- Project: in active construction. Os serviços comuns, o schema, o `Makefile` e o container do frontend existem e são testados por `make test-infra`. A página em 3000 é um esqueleto, e nenhuma stack existe.
- Decision: committed. O formulário público com nome e e-mail, seus textos e a tradução por `field` + `code` estão definidos em docs/api-contract.md. Esta sessão decidiu só a forma.
- In flight: copia o fluxo de edição de .design/frontend-container.md (`make watch-frontend`, `make frontend-npm`, só Docker e `make` na máquina) e a estrutura `frontend/src/modules/registration` de docs/stacks.md. Ficam fora o CORS e a exposição do `Retry-After`, que pertencem a cada stack.
- At stake: reverte-se em uma tarde, porque nada depende do formulário além dos cenários de validação. O que pesa é o test runner, que vira o padrão de todo teste do frontend.

## Problem

Construção. O README promete que uma pessoa preenche nome e e-mail em `localhost:3000`, e os cenários 1, 2, 3 e 7 de docs/architecture.md, que são o critério de aceite de cada stack, começam no formulário. O cenário 7 é a falha de rede, quando nenhuma stack está no ar.

Sem o formulário, cada stack só pode ser validada por `curl`. A metade do contrato que pertence ao frontend fica sem nenhum consumidor: a tradução por `field` + `code`, o `Retry-After` lido no navegador e a separação entre falha de rede e erro da API. Uma divergência entre as stacks nesses pontos só apareceria depois que as três estivessem prontas.

O formulário vem antes das stacks porque não depende de nenhuma delas: o contrato está fechado, e o container está pronto. Nada foi medido, porque ainda não existe produto. A evidência é o próprio contrato.

## Success

- Worked if: num clone limpo, só com Docker e `make`, `make test-frontend` passa cobrindo cada linha das tabelas de estado da fatia RegistrationForm. Com nenhuma stack no ar, enviar o formulário em `localhost:3000` mostra `Serviço indisponível no momento. Tente novamente em instantes.` (cenário 7).
- Going wrong: algum estado da tabela só pode ser provado com uma stack no ar, ou um texto em português aparece numa resposta que o contrato não prevê.
- Review: quando a primeira stack for implementada, por quem a implementar, rodando os cenários 1, 2, 3 e 7 de docs/architecture.md pelo formulário.

## Boundary

In: o formulário em `/`, no lugar do esqueleto; a leitura de toda resposta de `POST /users`; o alvo `make test-frontend`, com o test runner e a checagem de tipos; os ajustes em docs/api-contract.md › Comportamento do frontend (texto do 429, regra dos minutos, `Retry-After` ausente, campo desconhecido); docs/stacks.md › Frontend; o README (status e `make test-frontend`); a tabela do Makefile em docs/infrastructure.md; e a decisão 18 em docs/decisions.md.

Out:
- Validação no navegador: o formulário existe para exercitar a API (Key decision 2).
- CORS e exposição do `Retry-After`: são de cada stack (docs/infrastructure.md › Comunicação do frontend), e um teste do frontend não consegue prová-los sem uma API real.
- Teste de ponta a ponta com navegador e API simulada em container: não compensa (Shape).
- ESLint: o projeto não tem nenhuma regra a impor além dos tipos. Entra quando houver uma; custa uma dependência de desenvolvimento.
- Etapa de design visual: o formulário é coadjuvante, idêntico nas três stacks.
- O limite por IP de .design/registration-ip-limit.md: daquele design, esta rodada usa só o texto do 429, que vale também para o limite atual.

Unchanged: `POST /users`, os status, a forma do corpo de erro e a tabela de textos por `field` + `code` de docs/api-contract.md; `NEXT_PUBLIC_API_URL`; o Dockerfile, o serviço `frontend` do compose e os alvos `watch-frontend` e `frontend-npm`; `make test-infra`.

## Prior art

- O guia de testes do Next.js recomenda Vitest com React Testing Library e jsdom para componentes síncronos, e deixa os testes de ponta a ponta para Server Components assíncronos. O formulário é um componente de cliente, então o guia cobre o caso. Adotamos.
- O padrão mais comum para formulários no App Router é a Server Action. Ele não serve aqui: a chamada sairia do servidor Next.js, o navegador deixaria de ver o status real, e a falha de rede viraria um erro do servidor (Key decision 1).

## Shape

O formulário é um componente de cliente na página `/`. Ele envia nome e e-mail exatamente como foram digitados para `POST {NEXT_PUBLIC_API_URL}/users` e escolhe o texto exibido só pelo status, pelo par `field` + `code` e pelo `Retry-After`. A porta difícil de reabrir é a regra de leitura das respostas (Key decision 3), porque é ela que dá a cada stack o mesmo veredito. Os testes provam essa regra com respostas simuladas dentro do próprio teste, sem nenhuma API rodando.

Um teste de ponta a ponta, com navegador real e uma API simulada em container, só ganharia se o CORS e o `Retry-After` exposto fossem responsabilidade do frontend. Eles são de cada stack, e a primeira stack os prova pelos cenários de docs/architecture.md.

## Key decisions

1. **O navegador chama a API direto, a partir de um componente de cliente; nenhuma Server Action ou rota do Next.js fica no meio.** Isso mantém a decisão 12 de docs/decisions.md, e só assim o formulário distingue falha de rede de erro da API. Não copie o padrão de Server Action dos exemplos do Next.js.
2. **O formulário não valida nada no navegador: envia o que foi digitado, sem `trim`, e todo erro de campo exibido vem da API.** Um formulário em branco gera um 422 da API, e assim o cenário 3 de docs/architecture.md pode ser reproduzido pelo formulário. O schema do módulo `registration` valida a forma da resposta, não a entrada. Registrada como decisão 18 em docs/decisions.md.
3. **O status decide o resultado, e o corpo só é lido nos erros de campo.** Um 201 é sucesso com qualquer corpo, porque o cadastro já foi gravado, e mostrar erro levaria a pessoa a reenviar e receber um 409. Um 409 ou 422 só é interpretado com a forma única e ao menos um item de `name` ou `email`. Fora disso, e para qualquer outro status, aparece o texto do 500.
4. **Os campos mantêm o que foi digitado depois de qualquer resposta, e só uma requisição sai por vez.** Repetir o cenário 2 (201, 409 quatro vezes, 429) vira cinco cliques no mesmo botão. Um duplo clique não gera um 409 nem gasta uma tentativa. Um novo envio apaga as mensagens anteriores.
5. **O 429 mostra `Muitas tentativas de cadastro. Tente novamente em {minutos} minutos.` para qualquer limite, com os minutos arredondados para cima a partir do `Retry-After`.** O texto vem de .design/registration-ip-limit.md e vale também para o limite atual por IP + e-mail. Ele substitui o texto de docs/api-contract.md. Sem um `Retry-After` legível, o formulário não inventa um prazo.
6. **Os testes do frontend rodam por `make test-frontend` dentro de um container, sobre o código da cópia de trabalho, sem Node na máquina e sem tocar no ambiente em execução.** Isso mantém a promessa do README e permite rodar os testes com o `make watch-frontend` aberto. Ao contrário de `make test-infra`, esse alvo não destrói nada.

## Work

| Slice | Delivers | Status |
|---|---|---|
| [RegistrationForm](#registrationform) | Formulário em `/` que chama `POST /users` e mostra o texto de cada resposta do contrato | open — 4 defaults taken |
| [test-frontend](#test-frontend) | `make test-frontend`, com o test runner e a checagem de tipos, no container | open — 2 defaults taken |

Order: test-frontend → RegistrationForm. O alvo vem primeiro para que cada estado do formulário nasça já com o seu teste.

Já tratado pelo código existente: o valor de `NEXT_PUBLIC_API_URL` chega ao navegador pelo serviço `frontend` (.design/frontend-container.md, Key decision 6); a edição com recarga, por `make watch-frontend`; as dependências novas, por `make frontend-npm`.

Derivable from the repository, left to the plan: textos de 201, 500, falha de rede e a tabela por `field` + `code`, todos copiados de docs/api-contract.md › Comportamento do frontend; versões exatas nas dependências novas, pelo `.npmrc` existente; comentários e mensagens em português, como no restante do repositório.

### RegistrationForm

**Delivers** o formulário em `/` com os campos nome e e-mail, que chama `POST /users` e mostra um texto por resposta. **Status: open.** É a porta (Key decision 3).

`POST {NEXT_PUBLIC_API_URL}/users` `{"name": <como digitado>, "email": <como digitado>}`, com `Content-Type` e `Accept` `application/json` → leitura conforme a tabela abaixo.

| State | What should happen | Caller sees |
|---|---|---|
| Primeira visita | Campos vazios, nenhuma mensagem | Nome, e-mail e o botão de envio |
| Requisição em andamento | Uma segunda requisição não sai (Key decision 4) | Botão desabilitado com `Enviando…` |
| 201, com qualquer corpo | Os campos continuam preenchidos (Key decisions 3 e 4) | `Recebemos seus dados! Em instantes você receberá um e-mail de confirmação.` |
| Campos em branco | A requisição sai mesmo assim (Key decision 2) | Os textos `required` do 422 junto de cada campo |
| 409 ou 422 com itens de `name` ou `email` | Cada campo mostra o texto do seu primeiro item; um campo sem item fica sem texto | Texto da tabela de docs/api-contract.md, junto do campo |
| Par `field` + `code` com campo conhecido e código desconhecido | O campo fica marcado, sem expor o inglês | `Verifique este campo.` junto do campo |
| 409 ou 422 sem nenhum item de `name` ou `email` (lista vazia, só campos desconhecidos, corpo fora da forma) | Nada é interpretado (Key decision 3) | Texto do 500 |
| 429 com `Retry-After` legível | Minutos = segundos ÷ 60, arredondados para cima, no mínimo 1 (Key decision 5) | `Muitas tentativas de cadastro. Tente novamente em 13 minutos.` para `742`; `… em 1 minuto.` para 1 a 60 |
| 429 sem `Retry-After`, ou com valor ilegível | Nenhum prazo é inventado (Key decision 5) | `Muitas tentativas de cadastro. Tente novamente mais tarde.` |
| 500 | — | `Não foi possível concluir seu cadastro. Tente novamente em instantes.` |
| Outro status (404, 405, 503…) | Nada é interpretado | Texto do 500 |
| Falha de rede: nenhuma stack no ar ou CORS recusado | O navegador não entrega resposta | `Serviço indisponível no momento. Tente novamente em instantes.` |
| Novo envio depois de qualquer resultado | As mensagens anteriores somem antes da requisição sair (Key decision 4) | Só o resultado do novo envio |

Uma recusa de CORS chega ao navegador como falha de rede e não pode ser distinguida dela. Por isso, uma stack com CORS errado mostra `Serviço indisponível`, e o diagnóstico fica no console do navegador.

Alternatives considered: limpar os campos depois do 201, que ganharia se o formulário fosse para um público real e não para quem valida as stacks. Validar no navegador com as regras do contrato, que ganharia se o 422 não precisasse ser reproduzido pelo formulário.

Open, default taken:
1. Tempo limite da requisição: nenhum. O navegador decide quando desiste, e um tempo limite próprio mostraria `Serviço indisponível` para um cadastro que talvez ainda seja gravado.
2. Texto do 429 sem prazo: `Muitas tentativas de cadastro. Tente novamente mais tarde.`, texto novo que entra em docs/api-contract.md.
3. Acessibilidade: cada texto de campo fica associado ao seu campo, e a mensagem geral é anunciada por leitores de tela.
4. Visual: HTML semântico com CSS mínimo, sem biblioteca de componentes nem de estilo.

### test-frontend

**Delivers** o alvo `make test-frontend`, que checa os tipos e roda os testes do frontend dentro de um container. **Status: open.** (Key decision 6.)

| State | What should happen | Caller sees |
|---|---|---|
| Clone limpo, só com Docker e `make` | A imagem do frontend é construída se faltar, e os testes rodam sobre o código atual de `frontend/` | Saída do test runner; o alvo sai com 0 |
| Um teste falha | — | O teste que falhou; o alvo sai com código diferente de 0 |
| Erro de tipo | Os testes nem precisam rodar | O erro do TypeScript; o alvo sai com código diferente de 0 |
| `make up-shared` ou `make watch-frontend` em execução | O container do frontend não é recriado nem parado | O ambiente continua igual depois do alvo |
| Nenhum `node_modules` na máquina | Os testes usam as dependências da imagem | Nenhum `node_modules` aparece em `frontend/` |

Vitest, React Testing Library e jsdom são dependências de desenvolvimento do `frontend/package.json` e entram por `make frontend-npm` (Prior art).

Alternatives considered: rodar os testes dentro de `make test-infra`, que ganharia se esse alvo não destruísse o ambiente local; Jest, que ganharia se o projeto já o usasse.

Open, default taken:
1. A checagem de tipos roda antes dos testes, no mesmo alvo. Default: uma só porta de entrada, e um erro de tipo para tudo.
2. Os testes ficam ao lado do código do módulo `registration`. Default: como no exemplo `with-vitest` do Next.js.

## Sources

- docs/api-contract.md - respostas de `POST /users`, forma do corpo de erro e comportamento do frontend.
- docs/architecture.md › Cenários para validar a implementação - cenários 1, 2, 3 e 7.
- docs/infrastructure.md › Comunicação do frontend - chamada direta do navegador, CORS e `Retry-After`.
- docs/decisions.md - decisões 12, 14 e 16.
- .design/api-error-response.md - fatia `RegistrationForm` e tradução por `field` + `code`.
- .design/registration-ip-limit.md - Key decision 6, texto do 429.
- .design/frontend-container.md - fluxo de edição e adiamento do test runner para esta rodada.
- [Next.js › Testing › Vitest](https://nextjs.org/docs/app/guides/testing/vitest) - dependências, configuração e limite com Server Components assíncronos.
