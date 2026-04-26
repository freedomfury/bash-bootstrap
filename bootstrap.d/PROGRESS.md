# bootstrap.d — Architecture Workspace

This file captures architectural decisions made during design sessions and
translates them into concrete implementation items. It is a living document:
check off items as they land, remove stale entries, and add new decisions here
before coding them.

---

## Settled Architecture

### Pipeline (main.mk)

```
preflight → execute (parallel tasks) → finalize → cleanup
```

- `preflight` is a hard gate — abort if any subtask fails; internal subtasks defined by the `main.mk` author
- `execute` runs all tasks in parallel; continues on individual failures (`make -k` semantics)
- `finalize` always runs — emits a result report (minimum: journalctl; optionally Splunk or other sink)
- `cleanup` always runs — removes temp artifacts under `${BSS_TMP}`
- No task ever calls another task's `run` directly
- `finalize` and `cleanup` always run — unconditional regardless of which phase failed, including `preflight`

### Two-Tier Fact Model

**Tier 1 — Global facts (preflight)**

Preflight gathers facts once before any task runs. Output lands in `${BSS_TMP}/facts/`.

The monolith-level fact generators (`bin/facts-global-os`, `bin/facts-cloud-init`) are
general-purpose tools. Each subproject's `preflight` invokes them with `--prefix` and
`--output` to produce subproject-scoped variables in the right location:

```bash
# bootstrap.d/bin/preflight — example invocations
bin/facts-global-os \
  --prefix BSS_OS_FACTS \
  --output "${BSS_TMP}/facts/facts-global-os.env"

bin/facts-cloud-init \
  --input /run/cloud-init/instance-data.json \
  --prefix BSS_CI_FACTS \
  --output "${BSS_TMP}/facts/facts-cloud-init.env"
```

A future `pipeline.d` subproject would call the same generators with `--prefix PLD_OS_FACTS`
and write to its own `${PLD_TMP}/facts/`. The generators are not bootstrap-specific.

| File | Format | Contents |
|---|---|---|
| `facts-global-os.env` | Sourceable `KEY=VALUE` | OS, kernel, CPU, memory, network — `BSS_OS_FACTS_*` vars |
| `facts-cloud-init.env` | Sourceable assoc array | Cloud-init data — `BSS_CI_FACTS[...]` keys |
| `packages.list` | Flat text, one entry per line | Installed packages: `name version` |

Tasks source what they need from this directory. `packages.list` is intended
for `grep` — no bash array, no variable, just a flat file. Tasks that need to
check "is package X installed" grep this file rather than calling the package
manager again.

Re-querying preflight data live inside a task is permitted when a task
genuinely needs real-time state — this is a guideline, not an enforcement.

**Tier 2 — Task-level facts (optional, in `initialize`)**

When `initialize` needs to cache data for later phases within the same task,
it writes to `${BSS_TMP}/<task>/`. Later phases source from there. Not every
task needs this — only tasks where an expensive query in `initialize` would
otherwise be repeated in `configure` or `execute`.

### Phase Compliance Model

Each lifecycle phase (`initialize`, `install`, `configure`, `execute`) follows
a **check → act** pattern: query current system state, compare against desired
state, act only if out of compliance. No phase is a global gate for the others.

- `install` example: check package list or binary path → install only if absent
- `configure` example: compare rendered template against live config → write only if changed
- `execute` example: check if service is running → start only if stopped; check a lock file → restart only if a change was signaled

`initialize` is not universally an idempotency gate. It may set up task-local
facts, check preconditions specific to the task, or be a no-op — depending on
what the task needs. There is no prescribed behavior.

How each phase implements its check-then-act logic is the task author's
responsibility. The framework provides structure and guidance (via the task
template/skill); it does not enforce a specific check mechanism. Detailed
per-task implementation patterns are deferred to when real tasks are built and
the task template skill is finalized.

### Scoreboard Result Tree

Each task writes its per-phase results to:

```
${BSS_TMP}/scores/<task>/<phase>/stdout
${BSS_TMP}/scores/<task>/<phase>/stderr
${BSS_TMP}/scores/<task>/<phase>/rc
```

The `scoreboard` binary walks this tree after all tasks complete, assembles
a single JSON result document, and ships it (e.g., to Splunk). The JSON
document should include:
- Per-task, per-phase pass/fail and exit code
- Timing (if recorded)
- Platform/environment context from `${BSS_TMP}/facts/`

No task writes to a shared file. All contention-free.

### Task Template → Skill Generator

The current `tasks/__task__/` directory is a development scaffold. It should
be moved to `.agent/skills/bootstrap-task/` and used as an AI-driven task
generator. When a new task is needed (e.g., `ntp`, `sshd`, `chrony`), the
agent reads the skill and generates the task from the template.

### Task Filtering — Tags

`BSS_GLB_TAGS` — bash array, set in `vars/globals.env` or overridden at invocation. Empty means all tasks run.

Each task declares `BSS_<TASK>_TAG` in `vars/default.env`. At the top of `task::<name>::main`, the task checks whether its tag is in `BSS_GLB_TAGS` and exits 0 (skip) if not present. No framework — plain bash conditional. The task template scaffold includes this check.

Use cases: on-prem install vs. cloud (pre-baked images), full bootstrap vs. configure-only, selective re-runs.

### Reusable Subproject Pipeline Pattern

The `preflight → tasks → scoreboard` structure is not `bootstrap.d`-specific.
Any future subproject (`pipeline.d`, etc.) can use the same pattern with its
own:
- Subproject-scoped prefix (e.g., `PLD_` for `pipeline.d`)
- Subproject-scoped `tmp/` directory
- Its own `main.mk` defining what `preflight` produces

---

## Implementation Backlog

### Immediate

- [ ] Add `BSS_TMP` to `bootstrap.d/exports`
  ```bash
  declare -xr BSS_TMP="${BSS_ROOT}/tmp"
  ```
- [ ] Verify `bootstrap.d/tmp/` is gitignored
- [ ] Update Environment Setup table in `README.md` to show `BSS_TMP` once it is in `exports`

### Preflight

- [ ] Implement `bootstrap.d/bin/preflight`:
  - Gather cloud-init facts → `${BSS_TMP}/facts/cloud-init.env`
  - Gather platform facts → `${BSS_TMP}/facts/platform.env`
  - Dump installed packages → `${BSS_TMP}/facts/packages.list` (`name version` per line)
  - Decrypt `vars/secrets.env.sec.age` into memory via process substitution
  - Validate required `BSS_GLB_*` variables are set

### Scoreboard

- [ ] Implement `bootstrap.d/bin/scoreboard`:
  - Walk `${BSS_TMP}/scores/` tree
  - Assemble JSON result document (task → phase → rc/stdout/stderr)
  - Embed platform context from `${BSS_TMP}/facts/`
  - Ship JSON (e.g., stdout for piping, or direct to Splunk endpoint)
- [ ] Decide: does scoreboard exit non-zero if any task failed? (affects Make return code)

### Task Infrastructure

- [ ] Decide how stdout/stderr/rc capture per phase gets wired into `task::<name>::main` — implementation detail deferred to when we write the first real task
- [ ] Move `tasks/__task__/` → `.agent/skills/bootstrap-task/`
- [ ] Implement first real task (e.g., `ntp`, `sshd`) using the generator

### Documentation

- [x] Restructure `docs/bootstrap.md` → brief overview with links
- [x] Create `bootstrap.d/BOOTSTRAP.md` — full technical specification

### Deferred / Open

- [ ] Wire up `bootstrapd` recipe: `{ preflight && execute; } || true` followed by unconditional `finalize` and `cleanup`
- [ ] `finalize` minimum viable output: write summary to journalctl (`systemd-cat`); optional Splunk/external sink configurable via `BSS_GLB_*`
- [ ] `lib/defaults.sh` rename (candidate: `common.sh`) — defer to when we touch that file
- [ ] Splunk endpoint configuration: env var? `BSS_GLB_` var? secrets?
- [ ] Task timing: is wall-clock duration captured per phase at runtime?
