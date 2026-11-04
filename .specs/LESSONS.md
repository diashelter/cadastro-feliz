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

## Quarantined (failed when applied - ignore)

A confirmed lesson that recurred alongside failure. Kept for the maintainer to review.

_none_
