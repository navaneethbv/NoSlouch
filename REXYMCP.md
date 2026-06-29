# REXYMCP.md

The rexyMCP architect/executor workflow contract for the NoSlouch project —
whatever agent acts as the architect reads this first.

## Read these first

1. `docs/dev/STANDARDS.md` — engineering Definition of Done.
2. `docs/dev/WORKFLOW.md` — phase lifecycle, status transitions, Update
   Log templates.
3. `docs/dev/NEXT.md` — names the active phase.
4. `docs/architecture.md` — the design.

## Commands

| Command | Purpose |
|---|---|
| `make lint` | Format check (swift-format, verify only) |
| `make build` | Build (`swift build --disable-sandbox`) |
| `make lint` | Lint / static analysis (swift-format is the only linter) |
| `make test` | Tests (`swift test --disable-sandbox`) |

Auto-fix formatting with `make format`.

## Executor

Phases are executed by a **local LLM** reached through the rexyMCP MCP
server (`rexymcp serve`). The executor's contract is **embedded** in the
server binary — there is *no* root `AGENTS.md` or executor-contract file
in this repo.

To dispatch a phase: `/rexymcp:dispatch <phase>`. To review the result:
`/rexymcp:review <phase>`.
