# Container do frontend verification

**Verdict**: FAIL
**Proofs**: `proofs.md` at 163b45b
**Verifier**: independent sub-agent (author != verifier)

## Checks

| Check | Test | Holds |
| --- | --- | --- |
| C1 | `tests/infra/frontend.sh` `FE1 up-shared serves skeleton` | yes - clean env and no `.env`, exit code, four `healthy`, `200`, `Cadastro Feliz` and `localhost:8080` in the HTML |
| C2 | `tests/infra/frontend.sh` `FE2 up-shared rerun keeps frontend` | yes - 4 project container IDs and the image ID compared before and after, exit code checked |
| C3 | `tests/infra/frontend.sh` `FE3 up-shared serves current code` | yes - `Cadastro Probe` present and `Cadastro Feliz` absent after `make up-shared` |
| C4 | `tests/infra/frontend.sh` `FE4 api url read at start` | yes - `localhost:9090` present, `localhost:8080` absent, image ID unchanged |
| C5 | `tests/infra/shared.sh` `C5 published ports and network ports` | yes - host ports of all project containers equal `3000,5432,8025` |
| C6 | `tests/infra/shared.sh` `C7 pinned images`; `tests/infra/frontend.sh` `FE6 frontend base image` | yes - `config --images` equals the five names exactly; `grep -x 'FROM node:26.13.0-alpine'` |
| C7 | `tests/infra/shared.sh` `C8 up-shared fails on taken port 3000` | yes - blocker on 3000, non-zero exit asserted |
| C8 | `tests/infra/frontend.sh` `FE8 frontend build failure keeps shared` | yes - lock replaced by `{`, non-zero exit and the three `healthy` |
| C9 | `tests/infra/frontend.sh` `FE9 compile error keeps frontend healthy` | yes - `500` asserted, then `healthy` after `sleep 20` |
| C10 | `tests/infra/frontend.sh` `FE10 frontend runs next dev as node` | yes - reads the exec user and `.Config.Cmd` rather than PID 1; at HEAD PID 1 is uid 1000 running `next dev` (checked in `/proc/1`), so the proxy matches |
| C11 | `tests/infra/frontend.sh` `FE11 exact dependency versions` | yes - the three exact pins, and no `": "^`/`": "~` anywhere in the file (stricter than the two sections) |
| C12 | `tests/infra/frontend.sh` `FE12 frontend ignores and no env` | yes - `git check-ignore` on both paths, `frontend/.env` absent |
| C13 | `tests/infra/frontend.sh` `FE13 watch starts frontend with current code` | yes - clean env and no `.env`, edit made before, `.env`, network, `healthy`, edit served, watch still alive |
| C14 | `tests/infra/frontend.sh` `FE14 watch syncs edit` | yes - new text within 10 s, same container ID |
| C15 | `tests/infra/frontend.sh` `FE15 watch syncs create and delete` | yes - `/probe` `200` within 10 s after create, `404` within 10 s after delete |
| C16 | `tests/infra/frontend.sh` `FE16 watch rebuilds on package.json`, `... package-lock.json`, `... next.config.ts` | yes - each of the three triggers: new ID, `healthy`, `200` within 120 s |
| C17 | `tests/infra/frontend.sh` `FE17 watch interrupt keeps frontend` | yes - SIGINT to the process group, same ID, `running`, `200` |
| C18 | `tests/infra/frontend.sh` `FE18 frontend-npm writes exact versions only` | no - the owner assertion `[ -O "$f" ]` cannot fail when the suite runs as uid 0 (it did: runner and repo files are root), so a target that ran npm as root would pass; `"is-number": "7.0.0"` is grepped anywhere in `package.json`, not in `dependencies` |
| C19 | `tests/infra/frontend.sh` `FE19 frontend-npm refuses without args` | yes - non-zero exit, exact usage line, no `cadastro-feliz-` container |
| C20 | `tests/infra/frontend.sh` `FE20 frontend-npm leaves frontend running` | yes - exit `0`, same ID, `200` |
| C21 | `tests/infra/frontend.sh` `FE21 up-shared installs new dependency` | yes - fresh env, `/app/node_modules/is-number` exists after `make up-shared` |
| C22 | `tests/infra/frontend.sh` `FE22 broken frontend does not block migrate or stack` | yes - lock broken, `migrate` exit `0` with `1|f`, `up-go` exit `0` with the fake stack `healthy` |
| C23 | `tests/infra/frontend.sh` `FE23 migrate and stack do not start frontend` | yes - fresh env, no frontend container after `migrate` and after `up-go` |
| C24 | `tests/infra/docs.sh` `FE24 decision 16 recorded` | yes - exact index row with `Definida`, section present with the four terms |
| C25 | `tests/infra/docs.sh` `FE25 infrastructure docs describe frontend` | yes - no "frontend ... não existe" sentence, both targets in › Makefile, the three services on the `make migrate` row, `node:26.13.0-alpine` in › Versões fixadas (section-wide, not on the `frontend` row; only the frontend uses Node, so it holds) |
| C26 | `tests/infra/docs.sh` `FE26 readme describes frontend` | no - the order check takes the first `make up-shared` in the section, which is the blockquote prose on line 2 (already there at a2189cc); with the `make up-shared` code block moved after `make up-go` the test still prints PASS |
| C27 | `tests/infra/docs.sh` `FE27 stacks docs describe frontend` | yes - the three terms in `## Frontend` |
| C28 | `tests/infra/frontend.sh` `FE28 help lists frontend targets` | yes - both targets in `make help` output |

## Findings

| Finding | Evidence | Fix | Closed |
| --- | --- | --- | --- |
| C26's ordering assertion is vacuous: `make up-shared` after the stack commands still passes | `tests/infra/docs.sh` `t_fe26_readme` - `grep -nF 'make up-shared' \| head -1` hits the blockquote line 2 of › Como vai funcionar; a README copy with the `make up-shared` code line moved below `make up-go` printed `PASS FE26 mutated` | compare command lines only, e.g. `grep -nx 'make up-shared'` against `grep -nxE 'make up-(laravel\|nest\|go)'` inside the section | |
| C18's "pertence ao uid de quem rodou o make" is not proven: the proof ran as root and the repo files are owned by root, so `[ -O "$f" ]` holds even if npm runs as root (`--user 0:0` or no `--user` with a root image user) | `tests/infra/frontend.sh:253`; `id -u` = 0 and `stat frontend/package.json` = `root 0` in the proof environment | run the FE18 `make frontend-npm` as a non-root uid that can reach the Docker socket (e.g. `setpriv`/`sudo -u` with the socket group) on a `frontend/` owned by that uid, or fail FE18 with a note when `id -u` is 0 | |
| C18 asserts `"is-number": "7.0.0"` anywhere in `package.json`, not in `dependencies` | `tests/infra/frontend.sh:246` - `grep -qF '"is-number": "7.0.0"' "$f"`; a save to `devDependencies` would pass | read `.dependencies["is-number"]` (e.g. `node`/`python3 -c json` or a section-bounded awk) and assert `7.0.0` | |

Own examples (all held at HEAD, run in a throwaway copy): `make frontend-npm ARGS="install is-number@^6.0.0"` saved `"6.0.0"` with no `node_modules` on the host; `ARGS="ci"` and `ARGS="install --save-dev is-odd"` left no `frontend/node_modules`; `lang="pt-BR"` -> `lang="en-US"` in `layout.tsx` was served after `make up-shared`; `NEXT_PUBLIC_API_URL=http://api.local:8081/v2` and an empty value were served with the same image ID; with the watch active, a new nested `src/modules/registration/copy/msg.ts` imported by the page was served within 2 s in the same container.
