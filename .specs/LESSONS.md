# LESSONS - auto-maintained by scripts/lessons.py

> Machine-owned. Do NOT hand-edit. Changes are overwritten on the next `lessons.py` write.
> Canonical state lives in `.specs/lessons.json`. Edit lessons only via the script.
> promote_threshold=2 distinct features · window_days=45 · quarantine_threshold=2

## Confirmed (load these at Plan/Checks)

Corroborated across multiple features. Safe to apply as guidance.

_none_

## Candidates (under observation - do NOT load as guidance yet)

Seen once or not yet corroborated. Tracked, not trusted.

### L-001 - A test that the migrate applies the schema must start from an empty volume; a kept volume already carries the version from an earlier test.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: shared-infrastructure
- evidence: C13 tests/infra/migrate.sh t_c13_starts_shared (infra)
- last seen: 2026-11-04T16:42:36Z

### L-002 - A command that should follow output (logs -f) is proven by timeout's exit 124, not by a line in its output.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: shared-infrastructure
- evidence: C25 tests/infra/shared.sh t_c25_logs (infra)
- last seen: 2026-11-04T16:42:36Z

### L-003 - A claim that a file stays unchanged is proven by comparing the whole file before and after, not one line.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: shared-infrastructure
- evidence: C2 tests/infra/shared.sh t_c2_keeps_env (infra)
- last seen: 2026-11-04T16:42:36Z

### L-004 - A listing claimed over every project must be asserted while a second project is up, or a filter to one project passes.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: shared-infrastructure
- evidence: C24 tests/infra/shared.sh t_c24_status (infra)
- last seen: 2026-11-04T16:42:36Z

### L-005 - An order check over a doc section must match only the command lines, not prose that names the same command.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: frontend-container
- evidence: C26 tests/infra/docs.sh t_fe26_readme (infra)
- last seen: 2026-11-04T18:38:23Z

### L-006 - A claim that a container runs as the caller's uid must be proven by a non-root caller, since root owns everything it touches.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: frontend-container
- evidence: C18 tests/infra/frontend.sh t_fe18_npm_exact (infra)
- last seen: 2026-11-04T18:38:23Z

### L-007 - A claim about one section of a JSON file must read that section, not grep the whole file.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: frontend-container
- evidence: C18 tests/infra/frontend.sh t_fe18_npm_exact (infra)
- last seen: 2026-11-04T18:38:24Z

### L-008 - A claim that a TTL is kept, not renewed, is proven by setting an arbitrary TTL first; a range up to the full window also accepts a renewed one.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: registration-ip-limit
- evidence: C7 tests/infra/limiter.sh t_ip7_release (infra)
- last seen: 2026-11-04T19:44:43Z

### L-009 - A script that takes its limit as an argument must be run with a second limit, or a hard-coded limit passes.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: registration-ip-limit
- evidence: C5 tests/infra/limiter.sh t_ip5_reserve_limit (infra)
- last seen: 2026-11-04T19:44:43Z

### L-010 - A doc claim that ties a value to a row is proven on that row, not by grepping the whole section where the value also appears elsewhere.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: registration-ip-limit
- evidence: C1 tests/infra/docs.sh t_ip1_quota (infra)
- last seen: 2026-11-04T19:44:43Z

### L-011 - A doc check for a scenario asserts its outcome phrases, not just the numbers it mentions.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: registration-ip-limit
- evidence: C14 tests/infra/docs.sh t_ip14_scenarios (infra)
- last seen: 2026-11-04T19:44:43Z

### L-012 - A doc check scoped to a section must read that section with its subsections, not a neighbouring one that happens to hold the phrase.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: registration-ip-limit
- evidence: C4 tests/infra/docs.sh t_ip4_responses (infra)
- last seen: 2026-11-04T19:44:43Z

### L-013 - Redis TTL rounds to 0 in a key's last half second; a value meant for Retry-After needs a floor of 1.
- signal: `ac_gap` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: registration-ip-limit
- evidence: AC 5, AC 10 docs/api-contract.md Scripts da cota (infra)
- last seen: 2026-11-04T19:44:43Z

### L-014 - When a plan names the section a test reads from, name the section the doc will actually create.
- signal: `spec_precision_gap` · recurrence: 1 feature(s) · scope: `docs` · harmful: 0
- features: registration-ip-limit
- evidence: plan.md Shape step 1 (docs)
- last seen: 2026-11-04T19:44:43Z

### L-015 - A lookup keyed by text from an API must check own keys only; __proto__ or constructor otherwise resolve through the prototype.
- signal: `ac_gap` · recurrence: 1 feature(s) · scope: `frontend` · harmful: 0
- features: registration-form
- evidence: C8 registrationService.ts (frontend)
- last seen: 2026-11-04T20:09:40Z

### L-016 - A shape check is proven per member, and an invalid member must sit beside a valid one, or the outcome hides which check fired.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `frontend` · harmful: 0
- features: registration-form
- evidence: C9 RegistrationForm.test.tsx (frontend)
- last seen: 2026-11-04T20:09:40Z

### L-017 - Arithmetic on an unbounded numeric header needs an example far past Number's safe range.
- signal: `ac_gap` · recurrence: 1 feature(s) · scope: `frontend` · harmful: 0
- features: registration-form
- evidence: C10 registrationService.ts (frontend)
- last seen: 2026-11-04T20:09:40Z

### L-018 - An exact-version claim is proven by matching the exact form, not by rejecting two range prefixes.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: registration-form
- evidence: C23 tests/infra/test-frontend.sh t_rf23_exact (infra)
- last seen: 2026-11-04T20:09:40Z

### L-019 - A grep for a singular word must exclude neighbouring digits and the plural suffix.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: registration-form
- evidence: C25 tests/infra/docs.sh t_rf25_contract (infra)
- last seen: 2026-11-04T20:09:40Z

### L-020 - A new framework skeleton can register routes of its own; assert the route list equals what Surface declares.
- signal: `ac_gap` · recurrence: 1 feature(s) · scope: `laravel` · harmful: 0
- features: laravel-api-base
- evidence: apis/laravel/config/filesystems.php:36 (C44) (laravel)
- last seen: 2026-11-04T23:17:51Z

### L-021 - A claim that CI installs a pinned tool is proven by the pinned download and checksum lines, not by the step name.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `infra` · harmful: 0
- features: laravel-api-base
- evidence: tests/infra/laravel.sh t_lv34_ci (C34) (infra)
- last seen: 2026-11-04T23:17:51Z

### L-022 - Headers a contract fixes for every status are asserted on every status, not only on the success case.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `laravel` · harmful: 0
- features: laravel-api-base
- evidence: apis/laravel/tests/Feature/Health/HealthTest.php (C22) (laravel)
- last seen: 2026-11-04T23:17:51Z

### L-023 - A config default is proven in the running container, since the test runner's own env overrides it.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `laravel` · harmful: 0
- features: laravel-api-base
- evidence: tests/infra/laravel.sh t_lv45_no_table_defaults (C45) (laravel)
- last seen: 2026-11-04T23:17:51Z

## Quarantined (failed when applied - ignore)

A confirmed lesson that recurred alongside failure. Kept for the maintainer to review.

_none_
