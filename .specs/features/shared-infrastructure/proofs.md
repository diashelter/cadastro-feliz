# shared-infrastructure proofs

**HEAD**: 4473a0c
**Tree**: clean
**Shell**: /bin/sh
**Result**: 30 pass, 0 fail

| Check | Proof | Result |
| --- | --- | --- |
| C1 | `run infra / PASS C1 up-shared clean clone` | pass |
| C2 | `run infra / PASS C2 up-shared keeps existing env` | pass |
| C3 | `run infra / PASS C3 up-shared rerun keeps containers` | pass |
| C4 | `run infra / PASS C4 postgres login from host` | pass |
| C5 | `run infra / PASS C5 published ports and network ports` | pass |
| C6 | `run infra / PASS C6 redis-limiter config` | pass |
| C7 | `run infra / PASS C7 pinned images` | pass |
| C8 | `run infra / PASS C8 up-shared fails on taken port 8025` | pass |
| C8 | `run infra / PASS C8 up-shared fails on taken port 5432` | pass |
| C9 | `run infra / PASS C9 env example matches docs` | pass |
| C10 | `run infra / PASS C10 migration 0001 equals docs schema` | pass |
| C11 | `run infra / PASS C11 migrate on empty database` | pass |
| C12 | `run infra / PASS C12 migrate rerun changes nothing` | pass |
| C13 | `run infra / PASS C13 migrate starts shared services` | pass |
| C14 | `run infra / PASS C14 failed migration rolls back and marks dirty` | pass |
| C15 | `run infra / PASS C15 migration 0001 down drops both tables` | pass |
| C16 | `run infra / PASS C16 missing stack refused` | pass |
| C17 | `run infra / PASS C17 unknown stack refused` | pass |
| C18 | `run infra / PASS C18 up-stack runs shared and migrate first` | pass |
| C19 | `run infra / PASS C19 up-stack takes other stacks down` | pass |
| C20 | `run infra / PASS C20 up-stack stops when migrate fails` | pass |
| C21 | `run infra / PASS C21 down-stack keeps shared data` | pass |
| C22 | `run infra / PASS C22 down keeps only postgres volume` | pass |
| C23 | `run infra / PASS C23 reset-limits empties limiter` | pass |
| C24 | `run infra / PASS C24 status lists containers` | pass |
| C25 | `run infra / PASS C25 logs-shared follows logs` | pass |
| C29 | `run infra / PASS C29 status lists stack containers` | pass |
| C26 | `run infra / PASS C26 decision 15 recorded` | pass |
| C27 | `run infra / PASS C27 docs describe existing files` | pass |
| C28 | `run infra / PASS C28 database docs name the tool` | pass |

## Output

`Run infra` - exit 0

```
PASS C10 migration 0001 equals docs schema
PASS C11 migrate on empty database
PASS C12 migrate rerun changes nothing
PASS C13 migrate starts shared services
PASS C15 migration 0001 down drops both tables
PASS C14 failed migration rolls back and marks dirty
PASS C16 missing stack refused
PASS C17 unknown stack refused
PASS C18 up-stack runs shared and migrate first
PASS C19 up-stack takes other stacks down
PASS C29 status lists stack containers
PASS C21 down-stack keeps shared data
PASS C22 down keeps only postgres volume
PASS C20 up-stack stops when migrate fails
test-infra: todos os testes passaram
```
