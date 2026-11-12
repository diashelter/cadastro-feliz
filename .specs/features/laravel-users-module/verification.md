# Módulo único `users` e `DB::transaction` na stack Laravel verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at 3cb85d2
**Verifier**: independent sub-agent (author != verifier)

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | `tests/Feature/ModulesStructureTest.php` `it has a single users module`; `tests/infra/laravel.sh` `t_lv49_modular_locked`, `t_lv50_modules_layout`, `t_lv51_image_modules` | yes - asserts no `app-modules/notifications`, no `modules/notifications` in `require`, neither `modules/notifications` nor `modules/outbox` in the lock, and `dist.url` `app-modules/users` and `app-modules/health` |
| C2 | `ModulesStructureTest.php` `it references no notifications module`; `tests/infra/laravel-outbox.sh` `t_ob11_single_module` | yes - scans every `.php` file (Blade included) under `app-modules/*` and `tests/` for both terms, and checks that the scanned set includes `WelcomeMail.php` and the test file itself |
| C3 | `ModulesStructureTest.php` `it keeps the welcome email in users` | yes, though narrower than the claim - `class_exists` on the three new FQCNs and the three old ones, plus a basename scan; the scan covers `app-modules` only, while AC 3 says `apis/laravel` |
| C4 | `app-modules/users/tests/WelcomeEmailTest.php` `it runs once with no native backoff`, `it derives the message id from the event`, `it renders the users views` | yes - `tries` is `1`, there is no `backoff` property or method, the `messageId` is exact, the views are `users::welcome` and `users::welcome-text`, and the render contains `Olá, Ana!` |
| C5 | `WelcomeEmailTest.php` `it skips terminal events`, `it sends the welcome mail and marks the event processed`, `it records the send failure and does not mark processed`, `it warns and sends nothing for a missing event` | yes - all 5 examples covered: `processed`/`failed` assert nothing sent and no writes; `pending`/`published` assert `hasTo('ana@example.com')`, `assertSentCount(1)` and `markProcessed` once; `boom` asserts `recordFailure($event, 'boom')` and `shouldNotReceive('markProcessed')`; a missing event asserts the exact warning and nothing sent |
| C6 | `ModulesStructureTest.php` `it injects no database connection` | yes - text scan of `app/` and `app-modules/*/src`, and reflection on both constructors against `ConnectionInterface`, `ConnectionResolverInterface` and `DatabaseManager` (`is_a`, so a concrete `Connection` is caught too) |
| C7 | `app-modules/users/tests/RegisterUserUseCaseTest.php` `it writes the user and the event inside one transaction`, `it writes nothing when the transaction does not run` | yes - `DB::shouldReceive('transaction')->once()` and the exact log `['begin', 'users', 'users_outbox', 'commit']`; when the callback does not run, `shouldNotReceive` on both writes |
| C8 | `RegisterUserUseCaseTest.php` `it rethrows an event failure and releases the quota once` | yes - the same exception instance escapes the callback (`$escaped`) and the caller, and `releaseQuota` is `once()` with the IP |
| C9 | `ModulesStructureTest.php` `it opens no transaction in repositories` | yes - regex `transaction\(\|beginTransaction` over `*/src/Repositories`, and asserts both repositories were scanned |
| C10 | `app-modules/users/tests/RegisterUserTest.php` `it answers 201 and publishes no job` | yes - `DB::transaction` is mocked in `beforeEach`, the test asserts `201` with the exact body, and `Bus::assertNothingDispatched()` |
| C11 | `app-modules/users/tests/RelayOutboxTest.php` `it locks, publishes and marks the batch inside one transaction`, `it publishes and marks nothing for an empty batch` | yes - one `DB::transaction` (`once()`), the exact log `['begin','lock','publish e1','publish e2','mark e1,e2','commit']` and the count `2`; an empty batch logs `['begin','lock','commit']` and returns `0` |
| C12 | `RelayOutboxTest.php` `it publishes the welcome email job for user registered` | yes - exactly 1 job, an instance of `Modules\Users\Jobs\SendWelcomeEmailJob`, with `eventId` `e1` |
| C13 | `RelayOutboxTest.php` `it publishes nothing when an event type is unknown` | yes - both examples: the message contains `user.deleted`, the log is exactly `['lock']` (no publish, no mark) |
| C14 | `RelayOutboxTest.php` `it exits 1 and logs when the relay fails`, `it prints the published count`; `tests/infra/laravel-outbox.sh` `t_ob19_batch`, `t_ob21_failure` | yes - exit `1` with `Log::error('outbox relay failed', …)` once; exit `0` with the exact `3 event(s) published.` |
| C15 | `make test-laravel` totals line `Tests: passed` | yes - the proof is the totals line of the whole suite (`42 passed`), and the image runs `--no-deps` |
| C16 | `bash tests/infra/run.sh … ` totals line `test-infra: todos os testes passaram`; lone `git diff --name-only 75bc72a HEAD -- tests/infra` | no - `proofs.md` records the infra run as **fail** (exit 1, `test-infra: falhou`, `postgres não está healthy` in the tail); and the lone proof compares file names, not which checks changed |
| C17 | `tests/infra/laravel-outbox.sh` `t_ob11_single_module` | yes - fails when `app-modules/notifications` exists (`! -e`) or when `grep -rqE 'Modules\\+Notifications'` matches anywhere under `app-modules` |
| C18 | `tests/infra/docs.sh` `t_lv40_stacks` | no - asserts the three tree entries, the absence of `notifications/`, `OutboxConsumers` and `NotificationsServiceProvider`, `dono de users_outbox`, `envia o e-mail de boas-vindas` and `DB::transaction`, but not `roda o relay` |
| C19 | `tests/infra/docs.sh` `t_lv53_decision26` | no - asserts the index row, the section, `**Substitui**`, the reasons, the costs and both rejected alternatives, but not that the **Substitui** line cites `users` + `notifications` with `ConnectionInterface` |

Own examples, run at `HEAD` (code identical to 3cb85d2) as a throwaway Pest file under `make test-laravel` (45 passed), then deleted:
- AC 11, a batch of 5 and a batch of 1: 5 publications in id order, one mark `e1,e2,e3,e4,e5`, count `5`; with a batch of 1, one publication and one mark. Holds.
- AC 13, an unknown type 1st of 3 and 2nd of 3 (`order.placed`), the spellings `USER.REGISTERED` and ` user.registered`, and an empty `event_type`: every case throws with the type in the message, publishes nothing and does not mark. Holds.

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| AC 15/16 not proven: the Laravel infra subset exited 1 at 3cb85d2, so C16 is red | `proofs.md` › `Run infra` - exit 1, `test-infra: falhou`, tail `- postgres não está healthy`; row C16 `test-infra: todos os testes passaram` is **fail** | find which check failed (postgres health at startup or a real failure), fix it, and rerun `check_proofs.py` until the `Run infra` row and C16 pass | |
| C16's lone proof is looser than AC 16: it fixes which files changed, not which checks | `checks.md` C16 compares `git diff --name-only … -- tests/infra` with 4 file names; AC 16 names OB11, RG27, LV40, LV49, LV50, LV51, LV53 and `stack_dispatch`. A loosened check elsewhere in the same 4 files would pass. (By hand, the diff at 3cb85d2 touches exactly those 8 functions, so nothing slipped this time.) | prove at function level, e.g. diff the function names in the `@@` hunk headers of `git diff -U0 75bc72a HEAD -- tests/infra` against the 8 names | |
| C18: LV40 passes without "roda o relay" | `tests/infra/docs.sh` `t_lv40_stacks` greps the `**Contexto:**` line for `dono de \`users_outbox\`` and `envia o e-mail de boas-vindas` only; AC 18 also requires that `users` runs the relay | add `grep -qF 'roda o relay'` on the `**Contexto:**` line | |
| C19: LV53 checks that `**Substitui**` exists, not what it cites | `tests/infra/docs.sh` `t_lv53_decision26` greps the body for `'**Substitui**'` only; AC 19 requires the line to cite the `users` + `notifications` design with `ConnectionInterface` | grep the `**Substitui**` line itself for `` `notifications` `` and `ConnectionInterface` | |
| C3: the scan for removed classes is narrower than AC 3 | `ModulesStructureTest.php` `it keeps the welcome email in users` checks the basenames in `modulePhpFiles('*')` (that is, `app-modules` only) plus 3 fixed FQCNs; AC 3 says "não existir em `apis/laravel`", so an `OutboxConsumers` under `app/` would pass | also scan `app/` (and `config/`) for the three basenames, or narrow AC 3 to `app-modules` | |
