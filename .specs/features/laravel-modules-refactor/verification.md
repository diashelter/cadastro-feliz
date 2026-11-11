# Módulos da stack Laravel por contexto verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at 77089e9
**Verifier**: independent sub-agent (author != verifier)

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | `users/tests/OutboxTest.php` `it lists the statuses and which are terminal` | yes - compara a lista completa de `[valor, isTerminal()]` dos 4 casos, na ordem |
| C2 | `users/tests/OutboxTest.php` `it has only the user registered event type` | yes - `cases()` igual a `[UserRegistered]` e o valor `user.registered` |
| C3 | `tests/Feature/ModulesStructureTest.php` `it keeps status and event literals inside the enums` | yes - varre todo PHP de `app-modules/*/src` pelos 5 literais entre aspas e exige que os dois enums estejam na varredura |
| C4 | `users/tests/OutboxTest.php` `it casts the outbox row to the enums` | parcial - os casts estão provados, mas a ausência de `TERMINAL_STATUSES` é checada só em `UserOutboxEvent`, não em `apis/laravel` como o AC 4 fixa |
| C5 | `users/tests/RegisterUserUseCaseTest.php` `it writes the user and the event inside one transaction`, `it writes nothing when the transaction does not run` | yes - o log `begin, users, users_outbox, commit` prova as duas escritas dentro do callback, na ordem; `transaction()->once()` é verificado no `Mockery::close` |
| C6 | `users/tests/RegisterUserUseCaseTest.php` `it rethrows an event failure and releases the quota once` | yes - a mesma instância da exceção atravessa o callback, e `releaseQuota` é `once()` com o IP |
| C7 | `tests/Feature/ModulesStructureTest.php` `it opens no transaction in repositories` | yes |
| C8 | `tests/Feature/ModulesStructureTest.php` `it has no actions`; `users/tests/RegisterUserTest.php` `it answers 201 through the register user use case` | yes - sem `src/Actions` nem `RegisterUserAction` em nenhum PHP, e `POST /users` chama `RegisterUser::execute` com os argumentos normalizados |
| C9 | `users/tests/RelayOutboxTest.php` `it locks, publishes and marks the batch inside one transaction`, `it publishes and marks nothing for an empty batch` | yes - ordem exata `begin, lock, publish e1, publish e2, mark e1,e2, commit` e `begin, lock, commit` |
| C10 | `users/tests/RelayOutboxTest.php` `it publishes nothing when an event type has no consumer` | yes - os dois exemplos, com o tipo na mensagem e o log só com `lock` |
| C11 | `users/tests/RelayOutboxTest.php` `it exits 1 and logs when the relay fails`, `it prints the published count`; `tests/infra/laravel-outbox.sh` `OB19 relay batch output and order`, `OB21 relay failure keeps events and logs` | yes - as linhas de OB19 e OB21 aparecem como PASS, mas saem de um `Run infra` que terminou com `1` (ver C20) |
| C12 | `notifications/tests/WelcomeEmailTest.php` `it maps user registered to the welcome email job` | yes - resolve `OutboxConsumers` da aplicação já de pé, então prova o provider e o singleton |
| C13 | `tests/infra/laravel-outbox.sh` `OB11 users module does not reference notifications` | yes - `grep -r 'Modules\\+Notifications'` em `app-modules/users` inteiro; mesma ressalva do run infra |
| C14 | `tests/infra/laravel.sh` `LV49 modular locked with local modules`, `LV50 modules layout`, `LV51 image resolves local modules`; `tests/Feature/ModulesStructureTest.php` `it has no outbox module` | parcial - nenhuma prova afirma que `composer.lock` não tem `modules/outbox` (LV49 só exige os três presentes) |
| C15 | `tests/Feature/ModulesStructureTest.php` `it keeps notifications away from users_outbox and transactions` | yes |
| C16 | `notifications/tests/WelcomeEmailTest.php` `it skips terminal events`, `it sends the welcome mail and marks the event processed`, `it records the send failure and does not mark processed`, `it warns and sends nothing for a missing event` | yes - cobre os 5 exemplos; confirmei com um exemplo que um `once()` não cumprido derruba o teste, então o caso da falha (que só tem expectativas do Mockery) segura |
| C17 | `notifications/tests/WelcomeEmailTest.php` `it runs once with no native backoff`, `it derives the message id from the event`, `it renders the notifications views` | yes |
| C18 | `users/tests/OutboxTest.php` `it waits base times two to the previous attempts` | yes |
| C19 | `make test-laravel` - a linha `Tests: 40 passed` | yes |
| C20 | `bash tests/infra/run.sh docs laravel registration:laravel outbox:laravel laravel-outbox stack-switch` - a linha `test-infra: todos os testes passaram` | no - a prova está vermelha em `proofs.md`: saída `1`, `postgres não está healthy` e `test-infra: falhou` |
| C21 | `tests/infra/docs.sh` `LV40 stacks docs describe laravel stack` | parcial - procura `src/UseCases/` e `src/Enums/` na seção Laravel inteira, não na árvore de `users/`, e não checa que `notifications` envia o e-mail |
| C22 | `tests/infra/docs.sh` `LV53 decision 26 records the laravel modules` | parcial - exige o título `**Alternativas descartadas**`, mas não as duas alternativas que o AC 22 nomeia |

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| O subconjunto Laravel de `tests/infra` não está verde em 77089e9, então AC 20 e tudo o que só ele prova (a transação com PostgreSQL real, `stack_dispatch` com a classe nova, OB20, RG15) estão sem prova | `proofs.md` linhas 43 e 46: C20 e `Run infra` com `fail - exit 1`; a cauda mostra `postgres não está healthy` e `test-infra: falhou`. As linhas PASS de C11, C13, C14, C21 e C22 saem desse mesmo run, e a cauda não diz qual id falhou | descobrir qual teste falhou (ou se o ambiente não subiu), corrigir e rodar `check_proofs.py` de novo até C20 e `Run infra` ficarem verdes | CI [run 42988900419](https://github.com/diashelter/cadastro-feliz/actions/runs/42988900419) em `65d21dd` (Ubuntu, com as ferramentas GNU) - `docs`, `laravel` (LV7, LV24 e LV27 inclusive), `registration:laravel`, `outbox:laravel`, `laravel-outbox` e `stack-switch` passaram, cada um com `test-infra: todos os testes passaram`; no macOS só LV7, LV24 e LV27 falham, por `stat -c` e `sed -i`, em trechos que este diff não toca. A entrada `nest` falhou no NS35, que já falha na `main` (run 42639006483) e fica fora do escopo |
| C4 prova a ausência de `TERMINAL_STATUSES` só numa classe, mais frouxo que o AC 4 ("não existir em `apis/laravel`") | `users/tests/OutboxTest.php:33` - `defined(UserOutboxEvent::class.'::TERMINAL_STATUSES')`; hoje o `grep` no código de produção não acha nada, mas uma constante reintroduzida em outro arquivo passaria | varrer os PHP de `app-modules` (e `app`) por `TERMINAL_STATUSES`, como faz o teste de C3 | `3ab6f3b` - C4 varre `app`, `app-modules`, `bootstrap`, `config` e `routes` |
| Nenhuma prova de C14 afirma que `composer.lock` não tem `modules/outbox`, que o AC 14 nomeia | `tests/infra/laravel.sh` `t_lv49_modular_locked` só exige `health`, `notifications` e `users` vindos de `app-modules`; `it has no outbox module` só olha o diretório. Hoje o lock não tem `modules/outbox` | em LV49, exigir que `select(.name == "modules/outbox")` sobre `.packages[]` seja vazio | `3ab6f3b` - C14 (`it has no outbox module`) confere o `composer.lock` |
| LV40 aceita a árvore de docs/stacks.md sem `src/UseCases/` e `src/Enums/` em `users/` | `tests/infra/docs.sh` LV40 faz `grep -qF 'src/UseCases/'` na seção inteira; a linha `src/UseCases/SendWelcomeEmail.php` de `notifications/` já satisfaz o termo. Também não checa que o item de contextos diz que `notifications` envia o e-mail | restringir os termos ao bloco da árvore abaixo de `└── users/`, e checar `notifications` envia o e-mail no item **Contextos** | `3ab6f3b` - C21 (LV40) olha a subárvore de `users/` e o papel de `notifications` |
| LV53 aceita a decisão 26 sem as duas alternativas descartadas que o AC 22 nomeia | `tests/infra/docs.sh` `t_lv53_decision26` procura `**Alternativas descartadas**` e `outbox`, que o resto da seção já contém | procurar `Juntar tudo em \`users\`` e `Manter \`users\` e \`outbox\`` na seção | `3ab6f3b` - C22 (LV53) exige as duas alternativas |

Exemplos próprios rodados em `HEAD` como teste Pest descartável (apagado depois; `git status` limpo além do `checks.md` que já estava modificado), todos com o resultado esperado:
- AC 9: lote de 1 (`begin, lock, publish a, mark a, commit`) e lote de 50 (ordem preservada, uma marcação com os 50 ids).
- AC 10: tipo sem consumidor como 1º e como 2º de 3 → exceção com `user.deleted` e log só `begin, lock`.
- AC 5/6: `UserRepository::create` lançando `EmailAlreadyTaken` → nenhum `recordUserRegistered`, cota devolvida uma vez; limite estourado → nenhuma `transaction()`.
- AC 16: `pending` com `attempts` 4 e envio lançando → `recordFailure` com a mensagem, sem `markProcessed`; o job resolvido pelo contêiner chama o caso de uso.
- AC 12 ponta a ponta sem banco: `RelayOutboxEvents` com o `OutboxConsumers` real da aplicação publica um `SendWelcomeEmailJob` com o id do lote.
- AC 18: `attempts` 4 e 9 com base 30 → 480 e 15360; base 0 → 0. `OutboxConsumers` resolve sempre a mesma instância.
