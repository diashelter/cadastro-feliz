# Formulário de cadastro verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at 4d7ea28 - o arquivo no disco ainda registra `HEAD` 2588e19 e não tem linha de C28; sem rede, a imagem do `frontend` não é construída (`npm ci` falha), então `Run front` e `Run infra` aparecem vermelhos só por isso. Como evidência substituta de C1-C16, o mesmo `npm test` (`tsc --noEmit && vitest run`) rodou no host com Node 22: 26 testes passaram, e o Verifier repetiu o `vitest run` com o mesmo resultado. C18-C24 e C28 foram julgados pela leitura de `tests/infra/test-frontend.sh`, sem execução.
**Verifier**: independent sub-agent (author != verifier)

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | `page.test.tsx` `Home > shows the title, the API address and the empty form` · `Home > keeps Cadastro Feliz only in page.tsx` | sim - título exato, endereço, campos vazios, botão `Cadastrar` habilitado, `status` vazio, sem `aria-describedby`; a busca percorre todo `frontend/src` e exige exatamente `[app/page.tsx]` |
| C2 | `RegistrationForm.test.tsx` `sends one POST with the typed values as JSON` · `joins an API address that ends with a slash` | sim - 1 chamada, URL exata, `POST`, os dois headers e o corpo com os espaços do exemplo do plano; o mutante `type="email"` derruba o teste |
| C3 | `RegistrationForm.test.tsx` `sends empty fields without browser validation` · `sends an invalid email without browser validation` | sim - corpo `""`/`não-é-email`, `noValidate` e ausência de `required`, `maxlength` e `pattern` |
| C4 | `RegistrationForm.test.tsx` `disables the button with Enviando… while waiting` · `sends one request for two quick clicks` · `sends a second request after the response` | sim - o comportamento fica preso; o guarda `inFlight` não é exercido (o mutante que o remove sobrevive porque o botão desabilitado já barra o clique no jsdom), mas a afirmação de 1 requisição continua valendo |
| C5 | `RegistrationForm.test.tsx` `shows success for a 201 with any body` · `keeps the typed values after a 201` | sim - os quatro corpos do plano, texto exato, campos mantidos, botão reabilitado |
| C6 | `RegistrationForm.test.tsx` `shows the first item of each field` · `shows only the first item when a field has two` · `shows already_taken on the email field for a 409` | sim - os três exemplos, campo sem item vazio e `status` vazio |
| C7 | `RegistrationForm.test.tsx` `maps every field and code to its text` | sim - tabela com os 6 pares, texto exato no campo e o outro campo vazio |
| C8 | `RegistrationForm.test.tsx` `shows Verifique este campo. for an unknown code` | sim nos dois exemplos do plano; a regra quebra com `code` igual a uma chave de `Object.prototype` (ver Findings) |
| C9 | `RegistrationForm.test.tsx` `treats a field error body outside the contract as a 500` | sim nos cinco exemplos, em `409` e `422`; mais frouxo que a porta "leitura das respostas": `message` do corpo, `message` do item e o tipo de `field` não são provados (ver Findings) |
| C10 | `RegistrationForm.test.tsx` `shows the minutes of a 429 rounded up` | sim - texto exato nos cinco valores; `Math.round` no lugar de `Math.ceil` derruba o teste |
| C11 | `RegistrationForm.test.tsx` `shows mais tarde for a 429 without a readable Retry-After` | sim - os cinco valores do plano, texto exato |
| C12 | `RegistrationForm.test.tsx` `shows the 500 text for a 500` | sim |
| C13 | `RegistrationForm.test.tsx` `shows the 500 text for a status outside the contract` | sim - os cinco status, com um corpo de erro de campo válido, então ler `400` como `422` falharia |
| C14 | `RegistrationForm.test.tsx` `shows the network failure text when fetch rejects` | sim |
| C15 | `RegistrationForm.test.tsx` `clears field texts when a new request starts` · `clears the general message when a new request starts` | sim - afirma com a segunda requisição ainda pendente |
| C16 | `RegistrationForm.test.tsx` `describes each field with its text` · `announces the general message in a status` | sim - `aria-describedby` aponta para o texto exato, `aria-invalid`, e a mensagem geral só existe no `role="status"` |
| C17 | walk - abrir `localhost:3000` sem stack, preencher e usar `Cadastrar` | sim - walk registrado pelo builder em `proofs.md`; não repetido aqui |
| C18 | `tests/infra/test-frontend.sh` `RF18 test-frontend passes on a clean clone` | sim - `$WORK` é cópia de `git ls-files` (sem `node_modules`), sem `.env`; exige saída `0`, `Test Files … passed` sem `failed` e ausência de `frontend/node_modules`; a checagem de tipos é provada por RF20 |
| C19 | `tests/infra/test-frontend.sh` `RF19 test-frontend fails on a failing test` | sim - código diferente de `0` e o nome `probe fails on purpose` na saída |
| C20 | `tests/infra/test-frontend.sh` `RF20 test-frontend stops on a type error` | sim - código diferente de `0`, `error TS` presente e `Test Files` ausente |
| C21 | `tests/infra/test-frontend.sh` `RF21 test-frontend leaves frontend running` | sim - mesmo ID completo, estado `running` e `200` em `localhost:3000/` |
| C22 | `tests/infra/test-frontend.sh` `RF22 test-frontend uses the current code` | sim - verde antes, teste falho acrescentado sem outro comando, depois código diferente de `0` |
| C23 | `tests/infra/test-frontend.sh` `RF23 test dependencies are exact` | sim pelo texto do AC 23 (sem `^` nem `~`); mais frouxo que "versão exata" da Landing (ver Findings) |
| C24 | `tests/infra/test-frontend.sh` `RF24 help lists test-frontend` | sim |
| C25 | `tests/infra/docs.sh` `RF25 contract describes form rules` | sim - falharia no documento anterior; `grep -F '1 minuto'` também casa `11 minutos` e `1 minutos` (ver Findings) |
| C26 | `tests/infra/docs.sh` `RF26 decision 18 recorded` | sim - linha exata do índice com `Definida`, seção com `422` e `cenário 3` |
| C27 | `tests/infra/docs.sh` `RF27 docs describe the form and test-frontend` | sim - falharia nos três documentos anteriores; a negação em `stacks.md` depende da frase antiga literal `só o esqueleto` |
| C28 | `tests/infra/test-frontend.sh` `RF28 test-frontend leaves no environment behind` | sim - parte de `destroy_environment`, exige saída `0` e nenhum container, rede `cadastro-feliz-net` ou volume `cadastro-feliz-*` |

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| Um `code` igual a uma chave de `Object.prototype` quebra a regra "código sem texto → `Verifique este campo.`": `422` com `name`/`__proto__` derruba o formulário inteiro (React lança `Objects are not valid as a React child` e o botão some), e `name`/`constructor`, `toString`, `valueOf` ou `hasOwnProperty` deixam o campo com `aria-invalid="true"` e descrição vazia | `registrationService.ts` - `FIELD_TEXTS[field][first.code] ?? TEXTS.unknownCode` lê pela cadeia de protótipos; teste descartável no `HEAD`: os 5 códigos falharam (`expected '' to be 'Verifique este campo.'` e `Unable to find role="button"`) | procurar o texto só em chave própria (`Object.hasOwn(FIELD_TEXTS[field], code)` ou um `Map`) e acrescentar `name`/`__proto__` e `email`/`constructor` ao teste de C8 |  `a727c08` - texto procurado só em chave própria (`Object.hasOwn`); C8 cobre `__proto__`, `constructor`, `toString` e `hasOwnProperty` |
| A "forma única" do erro é provada só em parte: tirar a exigência de `message` texto no corpo, de `message` texto no item ou de `field` texto no item deixa os 26 testes verdes | mutantes em `registrationSchema.ts` (`typeof value.message === "string"` no corpo e no item, `typeof value.field === "string"`) sobreviveram; C9 só cobre `errors` vazio/ausente/`null`, item sem `code` e corpo não JSON | acrescentar ao teste de C9 um corpo sem `message`, um item sem `message` e um item com `field` numérico ao lado de um item válido |  `a727c08` - C9 cobre `message` do corpo e do item não texto e `field` não texto ao lado de um item válido; os três mutantes do schema ficam vermelhos |
| Um `Retry-After` muito grande mostra notação exponencial em vez de um inteiro de minutos | teste descartável no `HEAD`: `99999999999999999999999` → `… Tente novamente em 1.6666666666666665e+21 minutos.`; os limites `1`, `59`, `119`, `120`, `121`, `3600`, `060` e `86400` deram o texto certo, e `""`, `+60`, `1e3`, `0x10` deram `… mais tarde.` | limitar os minutos (ou tratar como ilegível um valor acima de `Number.MAX_SAFE_INTEGER`) e provar com um valor grande no teste de C10 ou C11 |  `a727c08` - minutos calculados com `BigInt`; C10 cobre `99999999999999999999999` → `1666666666666666666667 minutos` |
| RF23 aceita qualquer versão que não comece com `^` ou `~` (`>=1.0.0`, `*`, `latest`, `1.x`), mais frouxo que a "versão exata" da porta "test runner do frontend" e do próprio nome do teste | `tests/infra/test-frontend.sh:32-34` - só o `case '^'*\|'~'*` | exigir uma versão semver completa, p.ex. `^[0-9]+\.[0-9]+\.[0-9]+$` |  `a727c08` - C23 exige `major.minor.patch` com pré-release opcional |
| RF25 não prende `1 minuto` no singular: o `grep -qF '1 minuto'` casa `11 minutos` e `1 minutos` | `tests/infra/docs.sh:281` | buscar `` `1 minuto` `` com as crases, ou `1 minuto` seguido de algo que não seja `s` |  `a727c08` - C25 exige `1 minuto` sem dígito antes nem `s` depois |
