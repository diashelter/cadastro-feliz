# Limite de cadastros por IP verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at 505d470
**Verifier**: independent sub-agent (author != verifier)

Cada teste foi lido em `tests/infra/docs.sh` e `tests/infra/limiter.sh` e julgado com mutantes descartáveis: cópias de `HEAD` com uma alteração em `docs/api-contract.md`, `docs/architecture.md` ou num script Lua, rodadas com as funções reais dos testes. Os scripts rodaram num Redis 8.10.3 descartável (`verify-redis`), já removido. Nenhum container `cadastro-feliz-*` foi criado.

Mutantes que continuaram verdes:

- L1: a reserva troca `tonumber(ARGV[1])` por `20`.
- L2: a reserva faz `EXPIRE` em toda reserva aceita, o que vira uma janela deslizante.
- L3: a devolução faz `EXPIRE KEYS[1] 3600` depois do `DECR`.
- D1: a linha `Cota` diz `30 cadastros`.
- D2: a linha `Janela` diz `Deslizante`.
- D3: a linha `Identidade contada` diz `Par IP + e-mail`.
- D5: o cenário 12 diz "429 no 25º" e "409 consumindo cota".
- D6: a `Decisão` do script de reserva diz "`Retry-After` fixo de 3600".
- D8: o parágrafo do 429 em › Respostas perde "O corpo é o mesmo nos dois casos".
- D9: a limitação diz "20 cadastros por dia".

Mutantes que ficaram vermelhos, como deviam: `DECR` incondicional (IP8 e IP9), `>` no lugar de `>=` (IP5, IP6 e IP10), TTL fixo na recusa (IP10) e janela de 7200 (IP1).

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | `tests/infra/docs.sh` `IP1 contract describes ip quota` | no - procura `20` e `IP do cliente` na seção inteira (estão também em "1º ao 20º" e em › Chave da cota) e não confere `Fixa`; D1, D2 e D3 passam |
| C2 | `tests/infra/docs.sh` `IP2 ip key example matches sha256` | yes |
| C3 | `tests/infra/docs.sh` `IP3 processing order reserves before transaction` | yes - a ordem é a das linhas do texto, não a das arestas, e a posição da devolução na lista não é conferida; não há mutante plausível que passe |
| C4 | `tests/infra/docs.sh` `IP4 responses name both 429 causes` | no - o "mesmo corpo" é procurado em › Limite por IP, não em › Respostas, e o D8 passa |
| C5 | `tests/infra/limiter.sh` `IP5 reserve accepts 20 and refuses the 21st` | yes - nos `ARGV` `20` `3600` que o critério fixa (os L1 e L2 passam, veja os achados) |
| C6 | `tests/infra/limiter.sh` `IP6 parallel reserves accept exactly 20` | yes |
| C7 | `tests/infra/limiter.sh` `IP7 release decrements and keeps ttl` | no - o intervalo [1, 3600] não distingue um TTL mantido de um renovado para 3600, e o L3 passa |
| C8 | `tests/infra/limiter.sh` `IP8 release never creates the key` | yes |
| C9 | `tests/infra/limiter.sh` `IP9 release never goes negative` | yes |
| C10 | `tests/infra/limiter.sh` `IP10 refused reserve returns key ttl` | no - a metade do script segura (o `EXPIRE 1234` separa o TTL da chave de um valor fixo), mas a metade do texto aceita qualquer menção a `Retry-After` na seção, e o D6 passa |
| C11 | `tests/infra/limiter.sh` `IP11 key always has a ttl` | yes |
| C12 | `tests/infra/docs.sh` `IP12 limitations describe ip quota` | no - não confere "por hora", e o D9 passa |
| C13 | `tests/infra/docs.sh` `IP13 env vars documented and exemplified` | yes |
| C14 | `tests/infra/docs.sh` `IP14 scenarios 12 and 13 in order` | no - no cenário 12, só procura os números `20`, `201`, `429` e `409`; "21º", "sem gravar nada" e "sem consumir cota" não são conferidos, e o D5 passa |
| C15 | `tests/infra/docs.sh` `IP15 decision 17 recorded` | yes |
| C16 | `tests/infra/docs.sh` `IP16 readme describes ip quota` | yes |
| C17 | `tests/infra/docs.sh` `IP17 frontend 429 text is generic` | yes |

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| Uma janela deslizante passa em todos os testes, mas o contrato fixa a janela a partir da primeira reserva (AC 1, door do script de reserva) | Os mutantes L2 (`EXPIRE` em toda reserva) e L3 (devolução renova o TTL) passam de IP5 a IP11. Todas as asserções de TTL usam [1, 3600], que um TTL renovado também satisfaz | Num teste do script, pôr `EXPIRE` com um valor arbitrário (como faz o IP10 com 1234), depois fazer uma reserva aceita e uma devolução, e afirmar que o TTL não sobe acima desse valor. Afirmar também que, com o uso em 0, a próxima reserva recomeça a janela, como diz o contrato |  `3c87e90` - C5 (reserva não renova) e C7 (devolução mantém o TTL) com TTL arbitrário de 1000; C11 confere que a janela recomeça com o uso em 0 |
| A cota passada em `ARGV[1]` nunca varia, e um script com `20` fixo passa | O mutante L1 passa de IP5 a IP11. Todas as chamadas usam `20`. O door "variáveis" rejeita valor fixo justamente porque "testes não conseguem baixar a cota" | Rodar a reserva com outra cota, como `ARGV` `3` `60`: 3 aceitas, a 4ª recusada e o valor em 3 (o exemplo próprio E1 dá esse resultado em `HEAD`) |  `3c87e90` - C5 com `ARGV` `3` `60` |
| IP1 aceita outra cota, outra janela e outra identidade em › Limite por IP | `tests/infra/docs.sh` `t_ip1_quota` procura `'20'` e `'IP do cliente'` na seção inteira e não procura `Fixa`. Os mutantes D1, D2 e D3 passam | Conferir cada valor na própria linha da tabela: `Cota` com `20` e `REGISTRATION_MAX_PER_IP`, `Janela` com `Fixa`, `3600` e `primeira reserva`, e `Identidade contada` com `IP do cliente` e sem `e-mail` |  `3c87e90` - C1 confere cada linha da tabela |
| IP14 aceita um cenário 12 que contradiz o critério | `t_ip14_scenarios` só procura os números `20`, `201`, `429` e `409` na linha 12. O D5 ("429 no 25º", "409 consumindo cota") passa | Conferir `21º`, `sem gravar nada` e `sem consumir cota` na linha 12 |  `3c87e90` - C14 confere `21º`, `sem gravar nada` e `409 sem consumir cota` |
| As partes de texto de IP4, IP10 e IP12 procuram o termo fora do lugar que o critério nomeia, ou deixam parte dele de fora | IP4 procura "mesmo corpo" em › Limite por IP, não em › Respostas (D8 passa). IP10 aceita qualquer `Retry-After` na seção (D6 passa). IP12 não confere "por hora" (D9 passa) | IP4: procurar "mesmo" e "corpo" em › Respostas. IP10: exigir na linha da `Decisão` "segundos restantes" junto de `Retry-After`. IP12: exigir `hora` na linha da cota dividida |  `3c87e90` - C4 lê › Respostas com as subseções; C10 exige a linha da Decisão; C12 exige `por hora` |
| Uma reserva recusada no último meio segundo da janela retorna TTL `0`, fora do [1, 3600] que AC 5 e AC 10 fixam, e a API mandaria `Retry-After: 0` | Exemplo próprio E4 em `HEAD`: com a chave em `20` e `PX 200` ou `PX 400`, a reserva retorna `0 0`, porque o `TTL` do Redis arredonda para 0 abaixo de 500 ms. No exemplo próprio E3, com `ARGV[1]` `0` e a chave ausente, a reserva retorna `0 -2`. O script do par IP + e-mail já tem o mesmo arredondamento | Escolher entre devolver `math.max(1, ttl)` no script ou dizer no contrato que o `Retry-After` pode ser `0` no fim da janela, e dizer que `REGISTRATION_MAX_PER_IP` é pelo menos 1 |  `3c87e90` - script devolve `math.max(1, TTL)`, contrato exige cota ≥ 1; C5 cobre o último meio segundo da janela (recusa e aceite) |
| O plano diz que os scripts ficam em › Operação no Redis, mas eles estão em › Limite por IP › Scripts da cota | `plan.md` Shape, passo 1, e a suposição "Prova dos scripts" (`Confirmed: y`) citam › Operação no Redis. `docs/api-contract.md:216` é a seção do contador do par, e `limiter.sh` `ip_section` extrai os scripts de `## Limite por IP` | Alinhar o texto do plano ao lugar real dos scripts (ou mover os scripts). Hoje um leitor do plano procura na seção errada |  `3c87e90` - plano aponta › Limite por IP › Scripts da cota; nova linha em Landing |

Exemplos próprios que seguraram em `HEAD`:

- E1: com `ARGV` `3` `60`, a reserva aceita 3, recusa a 4ª e a chave fica em 3, com TTL 60.
- E2: com `ARGV` `1`, a reserva aceita 1 e recusa a 2ª.
- E5: com a chave em 1 e TTL 100, a devolução leva o valor a 0 e mantém o TTL em 100; a reserva seguinte recomeça a janela em 3600.
- E6: com a chave em 25 (a cota baixou para 20), a reserva recusa sem alterar o valor, e a devolução leva a 24 mantendo o TTL.
- E7 (estado inesperado): com a chave em 20 sem expiração, a reserva retorna `0 -1`, e a chave nunca ganha TTL até voltar a 0. Os dois scripts não criam esse estado, então isso não é achado.
