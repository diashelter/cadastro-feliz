# Limite de cadastros por IP checks

Build: none - o repositório não tem build, lint nem type check para documentação e shell; os scripts Lua são executados pelas provas
Run infra: `bash tests/infra/run.sh docs limiter`
Plan: `.specs/features/registration-ip-limit/plan.md`

17 checks in 2 slices · 5 one-way doors · 0 open, of which 0 block

## Checks

### S1 - Cota por IP no contrato

**C1** - `docs/api-contract.md` tem `## Limite por IP` com identidade o IP canônico, chave `registration:ip:{sha256(ip)}`, cota `REGISTRATION_MAX_PER_IP` (20), janela fixa de `REGISTRATION_IP_WINDOW_SECONDS` (3600) a partir da primeira reserva, consumo só por `201` e devolução em `409` e `500` (AC 1)
Proof: run infra | PASS IP1 contract describes ip quota

**C2** - O exemplo do contrato é IP `203.0.113.10` → `registration:ip:631f08140b24b7274d12df3c37a1a80ce5876dafd7007d772e0114fddf88b682`, e o hash é o SHA-256 calculado sobre `203.0.113.10` (AC 2)
Proof: run infra | PASS IP2 ip key example matches sha256

**C3** - Em › Ordem de processamento, o fluxograma e a lista põem a reserva da cota depois da validação e da contagem do par e antes da transação, e a devolução nos ramos `409` e `500` posteriores (AC 3)
Proof: run infra | PASS IP3 processing order reserves before transaction

**C4** - › Respostas diz que o `429` tem duas causas, o par IP + e-mail e a cota do IP, com o mesmo corpo e `Retry-After` da janela que recusou (AC 4)
Proof: run infra | PASS IP4 responses name both 429 causes

**C5** - O script de reserva do documento, rodado no `redis-limiter` com `ARGV` `20` `3600` numa chave ausente, retorna `1` e TTL em `[1, 3600]` 20 vezes, e na 21ª retorna `0` com TTL em `[1, 3600]`, com a chave em `20` (AC 5)
Proof: run infra | PASS IP5 reserve accepts 20 and refuses the 21st

**C6** - 50 execuções paralelas do script de reserva numa chave ausente retornam `1` exatamente 20 vezes, e a chave termina em `20` (AC 6)
Proof: run infra | PASS IP6 parallel reserves accept exactly 20

**C7** - O script de devolução numa chave em `20` a leva a `19` e mantém o TTL em `[1, 3600]` (AC 7)
Proof: run infra | PASS IP7 release decrements and keeps ttl

**C8** - O script de devolução numa chave nunca criada, e numa chave que expirou depois da reserva, deixa a chave ausente (AC 8)
Proof: run infra | PASS IP8 release never creates the key

**C9** - O script de devolução numa chave em `0` a mantém em `0` (AC 9)
Proof: run infra | PASS IP9 release never goes negative

**C10** - Uma reserva recusada retorna o TTL da chave, e o contrato diz que esse TTL é o `Retry-After` (AC 10)
Proof: run infra | PASS IP10 refused reserve returns key ttl

**C11** - Depois de reserva, devolução, reserva, e depois de 20 reservas, 20 devoluções e 1 reserva, a chave tem TTL em `[1, 3600]` (AC 11)
Proof: run infra | PASS IP11 key always has a ttl

**C12** - › Limitações conhecidas não tem mais "Sem limite só por IP" e diz que pessoas atrás do mesmo IP dividem a cota de 20 por hora e que uma devolução que falha deixa uma unidade a mais até a janela expirar (AC 12)
Proof: run infra | PASS IP12 limitations describe ip quota

### S2 - Configuração, cenários e registro

**C13** - `.env.example` tem `REGISTRATION_MAX_PER_IP=20` e `REGISTRATION_IP_WINDOW_SECONDS=3600` em `# Regras de negócio`, e docs/infrastructure.md › Variáveis de ambiente lista as duas com esses valores (AC 13)
Proof: run infra | PASS IP13 env vars documented and exemplified

**C14** - docs/architecture.md tem os cenários 12 e 13 com `201`, `429`, `409` e 50 paralelos com exatamente 20 `201`, e a lista de cenários está em ordem numérica (AC 14)
Proof: run infra | PASS IP14 scenarios 12 and 13 in order

**C15** - docs/decisions.md tem a decisão `17` "Cota de cadastros concluídos por IP", `Definida`, no índice, e a seção cita `REGISTRATION_MAX_PER_IP`, `201` e `devolve` (AC 15)
Proof: run infra | PASS IP15 decision 17 recorded

**C16** - A linha `429` da tabela da API no README cita 20 cadastros por IP por hora, e › Limites conhecidos diz que quem divide o IP divide essa cota (AC 16)
Proof: run infra | PASS IP16 readme describes ip quota

**C17** - › Comportamento do frontend mostra para o `429` `Muitas tentativas de cadastro. Tente novamente em {minutos} minutos.` (AC 17)
Proof: run infra | PASS IP17 frontend 429 text is generic

## Coverage

| Set (size) | Member -> proof | Unproven |
| --- | --- | --- |
| Landing doors (5) | chave da cota C1 · C2 · script de reserva C5 · C6 · C10 · script de devolução C7 · C8 · C9 · C11 · variáveis C13 · decisão 17 C15 | - |
| `POST /users` statuses (5) | `201` consome C1 · `409` devolve C1 · C3 · `422` antes da reserva C3 · `429` C4 · `500` devolve C1 · C3 | - |
| regras da cota, AC 1 (6) | identidade C1 · chave C1 · cota C1 · janela C1 · consome só `201` C1 · devolve em `409` e `500` C1 · C3 | - |
| reserva, AC 5 (3 casos) | 1ª a 20ª C5 · 21ª C5 · valor final 20 C5 | - |
| devolução, AC 8 (2 exemplos) | chave nunca criada C8 · chave expirada C8 | - |
| TTL sempre presente, AC 11 (2 exemplos) | reserva-devolução-reserva C11 · 20 reservas, 20 devoluções, 1 reserva C11 | - |
| variáveis novas (2) | `REGISTRATION_MAX_PER_IP` C13 · `REGISTRATION_IP_WINDOW_SECONDS` C13 | - |
| cenários novos (2) | 12 C14 · 13 C14 | - |
| documentos alterados (6) | `docs/api-contract.md` C1-C4, C10, C12, C17 · `.env.example` C13 · `docs/infrastructure.md` C13 · `docs/architecture.md` C14 · `docs/decisions.md` C15 · `README.md` C16 | - |

## Swept

- validation: n/a - nenhuma entrada nova; o IP e o hash são os do contador existente, provados por C2
- failure modes: C12 - a devolução que falha está nas limitações; o `500` com `redis-limiter` fora é a decisão 8, sem mudança
- idempotency: C8, C9 - a devolução repetida ou tardia não cria chave nem fica negativa
- authorization: n/a - `POST /users` continua público; a cota é o throttling, C5
- concurrency: C6
- data lifecycle: C11 - a chave nunca fica sem expiração; `make reset-limits` existente esvazia o `redis-limiter` inteiro
- dependency failure: existing - decisão 8 de docs/decisions.md, `redis-limiter` indisponível retorna `500`
- state transitions: C5, C7, C9, C11 - Livre, EmUso e Esgotada do diagrama do plano
- observability: n/a - nenhuma stack existe; nada a registrar nesta rodada

## Handoff

- **Settled mid-build:** none
- **Dispatched:** Verifier at `505d470` - returned
- **Boundary:** C1-C17 closed at `f50dbdf`
- **Abandoned:** none
- **Environment:** Docker sem acesso ao Docker Hub (429) nem ao npm de dentro dos containers; as imagens vieram de `mirror.gcr.io` e foram marcadas com as tags oficiais. As provas desta feature não constroem a imagem do frontend, por isso o `Run infra` roda só `docs` e `limiter`; o C9 de shared-infrastructure, que muda para 24 variáveis, roda em `make test-infra` completo
