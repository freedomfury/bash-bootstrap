# Bootstrap Subproject — Technical Specification

`bootstrap.d` is the system-bootstrap subproject. Its job is to configure a
freshly provisioned machine: install packages, drop configuration files, apply
settings, and start or enable services — reliably and idempotently.

The design is deliberately analogous to Ansible roles. Each unit of work is a
self-contained **task** (one per service or subsystem). Tasks share common
infrastructure from the subproject level — libraries, variables, secrets — but
own everything else privately.

For implementation status and the work backlog, see [`PROGRESS.md`](PROGRESS.md).

---

## How It Fits Into the Monolith

The monolith root (`Makefile`) is the only entry point. It includes
`bootstrap.d/main.mk`, which defines the bootstrap pipeline targets. Running
`make bootstrap` cascades through the full pipeline:

```
make bootstrap           ← public entry point
  └─ exports             ← generates MKS_* environment
      └─ bootstrapd      ← begins the subproject pipeline
           ├─ bootstrap.d/exports ← provides BSS_ROOT, BSS_TMP
           │
           ├─ preflight   ← GATE: abort if any subtask fails
           │   └─ (subtasks at author's discretion: fact gathering,
           │       secrets decryption, env validation, etc.)
           │
           ├─ execute     ← parallel tasks; continues on failure
           │   ├─ ntp     ← bootstrap.d/tasks/ntp/entry
           │   └─ sshd    ← bootstrap.d/tasks/sshd/entry
           │
           ├─ finalize    ← ALWAYS runs; emits result (journalctl, Splunk, etc.)
           │
           └─ cleanup     ← ALWAYS runs; removes temp artifacts
```

`finalize` and `cleanup` are unconditional — they run regardless of which
phase failed, including `preflight`. A `preflight` failure skips `execute`
(no point running tasks we know will fail) but still proceeds to `finalize`
and `cleanup` to report the failure and tidy up.

`bootstrapd` enforces this with a grouped shell expression:

```makefile
bootstrapd: bootstrap.d/exports
    @{ $(MAKE) preflight && $(MAKE) execute; } || true
    $(MAKE) finalize
    $(MAKE) cleanup
```

Adding a new service means:
1. Generating a task directory under `bootstrap.d/tasks/<name>/` using the
   `bootstrap-task` skill (see `.agent/skills/bootstrap-task/`)
2. Adding a `<name>:` target to `bootstrap.d/main.mk`
3. Linking it into the `tasks:` prerequisite list

---

## Two-Tier Fact Model

Facts are gathered in two tiers. The goal is to avoid redundant system queries:
gather shared information once at the pipeline level, and gather task-specific
information once at the task level.

### Tier 1 — Global Facts (preflight)

`preflight` runs before any task starts. It invokes the monolith-level fact
generators and writes subproject-scoped artifacts to `${BSS_TMP}/facts/`:

```bash
# bootstrap.d/bin/preflight — fact generator invocations
bin/facts-global-os \
  --prefix BSS_OS_FACTS \
  --output "${BSS_TMP}/facts/facts-global-os.env"

bin/facts-cloud-init \
  --input /run/cloud-init/instance-data.json \
  --prefix BSS_CI_FACTS \
  --output "${BSS_TMP}/facts/facts-cloud-init.env"
```

| Artifact | Format | Contents |
|---|---|---|
| `facts-global-os.env` | Sourceable `KEY=VALUE` | OS, kernel, CPU, memory, network — `BSS_OS_FACTS_*` |
| `facts-cloud-init.env` | Sourceable associative array | Cloud-init data — `BSS_CI_FACTS[...]` |
| `packages.list` | Flat text, `name version` per line | All installed packages — grep-friendly |

The `--prefix BSS_*` flag scopes variables to this subproject. A future
`pipeline.d` subproject would call the same generators with `--prefix PLD_*`.

Tasks source from `${BSS_TMP}/facts/` as needed. Re-querying live system state
inside a task is permitted when a task genuinely needs real-time data — the
above is a cache, not a contract.

### Tier 2 — Task-Level Facts (optional)

When a task's `initialize` phase needs to query and cache system state for use
by later phases in the same task, it writes to `${BSS_TMP}/<task>/`. Later
phases source from there if the file exists. Not every task needs this — only
tasks where an expensive or compound query would otherwise repeat across phases.

---

## Subproject Directory Layout

```
bootstrap.d/
├── BOOTSTRAP.md            ← This file: full technical specification
├── PROGRESS.md             ← Implementation backlog and open decisions
├── README.md               ← Convention overrides (extends AGENTS.md)
├── exports                 ← Provides BSS_ROOT, BSS_TMP (sourced before all scripts)
├── main.mk                 ← Subproject pipeline targets (included by root Makefile)
├── tmp/                    ← Runtime artifacts (gitignored); BSS_TMP points here
│   ├── facts/              ← Global fact artifacts written by preflight
│   └── scores/             ← Task result files written during execution
│       └── <task>/
│           └── <phase>/
│               ├── stdout
│               ├── stderr
│               └── rc
├── bin/                    ← Subproject-wide executables (no .sh suffix)
│   ├── preflight           ← Gather global facts, decrypt secrets, validate env
│   └── scoreboard          ← Walk scores/ tree, assemble JSON report
├── lib/
│   └── defaults.sh         ← Sources MKS_ROOT libs + subproject globals
├── vars/
│   ├── globals.env         ← Subproject-wide variables (BSS_GLB_ prefix)
│   ├── secrets.env.sec     ← Plaintext secrets (gitignored)
│   └── secrets.env.sec.age ← Encrypted secrets (committed)
└── tasks/
    └── <name>/             ← One directory per service or subsystem
        ├── entry           ← Task entry point
        ├── bin/            ← Task-private executables
        ├── lib/            ← Task-private libraries (.sh suffix)
        ├── files/          ← Static files to deploy verbatim
        ├── tmpl/           ← Jinja templates rendered at run time
        └── vars/
            └── default.env ← Task variable defaults
```

---

## Task Anatomy

### `entry` — Entry Point

The `entry` file is the task's executable entry point, invoked by its Make target.
It must:

- Be executable (`chmod +x`) with no file extension
- Begin with the standard strict-mode preamble and `MKS_ROOT` guard
- Source `${BSS_ROOT}/lib/defaults.sh`
- Implement the four lifecycle functions
- Call `task::<name>::main` and exit cleanly

For complex tasks, lifecycle functions source from `tasks/<name>/lib/` rather
than cramming logic into `entry`. The `entry` file stays short and readable; the
work lives in libraries.

Minimal skeleton:

```bash
#!/usr/bin/env mks-bash
# bootstrap.d/tasks/<name>/entry -- <name> task entry point

set -euo pipefail
shopt -s inherit_errexit
IFS=$'\n\t'

[[ -n "${MKS_ROOT:-}" ]] || {
  printf 'FATAL: MKS_ROOT is not set — run via make or source exports first\n' >&2
  exit 3
}

readonly _SELF="${0##*/}"

# -- Task variables (sourced first so globals can override)
# shellcheck source=/dev/null
source "${MKS_ROOT}/bootstrap.d/tasks/<name>/vars/default.env"

# -- Subproject environment (provides BSS_ROOT, BSS_TMP, common libs, and logger)
# shellcheck source=bootstrap.d/lib/defaults.sh
source "${MKS_ROOT}/bootstrap.d/lib/defaults.sh"

tasks::<name>::initialize() { ... }
tasks::<name>::install()    { ... }
tasks::<name>::configure()  { ... }
tasks::<name>::execute()    { ... }

task::<name>::main() {
  tasks::<name>::initialize
  tasks::<name>::install
  tasks::<name>::configure
  tasks::<name>::execute
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  task::<name>::main "$@"
fi
```

### Task Lifecycle

Every task implements four lifecycle phases in order:

| Phase | Function | Responsibility |
|---|---|---|
| `initialize` | `tasks::<name>::initialize` | Query system state, cache task-level facts; may be a no-op |
| `install` | `tasks::<name>::install` | Install packages, binaries, users, directories |
| `configure` | `tasks::<name>::configure` | Render templates, write config files, set permissions |
| `execute` | `tasks::<name>::execute` | Enable or start the service, apply live configuration |

### Phase Compliance Model

Each phase follows a **check → act** pattern: query current state, compare
against desired state, act only if out of compliance. No phase gates the others.

- `install` checks whether the package or binary already exists before installing
- `configure` compares rendered output against the live config before overwriting
- `execute` checks service state before starting or restarting

`initialize` has no prescribed check behaviour — it does whatever the task needs
before the other phases run: caching a fact, verifying a precondition, or nothing.

How each phase implements its check-then-act logic is the task author's
responsibility. See `.agent/skills/bootstrap-task/` for guidance and examples.

### `vars/default.env` — Task Variables

Each task declares its defaults in `vars/default.env`. All keys must carry the
`BSS_<TASK>_` prefix. Source order matters: `default.env` is sourced first, then
`globals.env` (via `defaults.sh`), so globals win.

```bash
# Example for an 'ntp' task
BSS_NTP_SERVERS=(
    http://pool.ntp.org
    http://time.google.com
)
BSS_NTP_ENABLE=true
```

---

## Task Filtering — Tags

Tasks can be selectively skipped based on a global tag list. This allows the
same pipeline to behave differently across contexts — on-prem install vs. cloud
where packages are pre-baked, full bootstrap vs. configure-only, etc.

`BSS_GLB_TAGS` is a bash array set in `vars/globals.env` or overridden at
invocation time. Each task declares its own tag in `vars/default.env` and
checks for it at the top of `task::<name>::main`:

```bash
# tasks/ntp/vars/default.env
BSS_NTP_TAG=install

# tasks/ntp/entry — top of task::ntp::main
task::ntp::main() {
  if [[ -n "${BSS_GLB_TAGS[*]:-}" ]]; then
    local tag
    for tag in "${BSS_GLB_TAGS[@]}"; do
      [[ "${tag}" == "${BSS_NTP_TAG}" ]] && break
      tag=''
    done
    if [[ -z "${tag:-}" ]]; then
      lib::std::logger -l info -m "ntp: tag '${BSS_NTP_TAG}' not active — skipping"
      return 0
    fi
  fi
  tasks::ntp::initialize
  tasks::ntp::install
  tasks::ntp::configure
  tasks::ntp::execute
}
```

If `BSS_GLB_TAGS` is empty or unset, all tasks run — no filtering applied.
The tag check is the task author's responsibility; the framework does not
enforce it. The task template (`.agent/skills/bootstrap-task/`) includes
the tag-check pattern as a standard scaffold.

## Variable Namespacing

| Scope | Prefix | Example |
|---|---|---|
| Make system (from root `exports`) | `MKS_` | `MKS_ROOT`, `MKS_TMP` |
| Subproject root | `BSS_ROOT` | `${MKS_ROOT}/bootstrap.d` |
| Subproject temp | `BSS_TMP` | `${BSS_ROOT}/tmp` |
| Script-internal paths | `_UPPER_SNAKE_CASE` | `_NTP_ROOT` |
| Bootstrap global config | `BSS_GLB_` | `BSS_GLB_APITOKEN`, `BSS_GLB_TAGS` |
| Bootstrap task config | `BSS_<TASK>_` | `BSS_NTP_SERVERS` |
| OS facts (from preflight) | `BSS_OS_FACTS_` | `BSS_OS_FACTS_ID` |
| Cloud-init facts (from preflight) | `BSS_CI_FACTS` | `BSS_CI_FACTS[v1.region]` |

---

## Execution Model — Parallel by Default

Tasks run in parallel. Make executes all prerequisites of the `tasks` target
concurrently unless an explicit ordering constraint is declared.

```makefile
# All tasks run in parallel (no ordering between them)
tasks: preflight ntp sshd chrony

# sshd must complete before chrony — express as a prerequisite
chrony: sshd
```

Tasks are fully isolated: separate Make recipes, separate `run` processes, no
shared Bash state. Shared state flows only through the exported environment
established by `preflight`.

Design rules:
- **Tasks must not write to the same path without coordination.** Use
  `${BSS_TMP}/<task>/` for task-private temporary output.
- **Ordering dependencies** between tasks are expressed as Make prerequisites.
  Never invoke another task's `run` from inside a task.
- **`preflight` always completes before any task starts.**

Failure handling: tasks continue running if a peer fails (`make -k`). The
scoreboard reports the full picture regardless of individual failures.

---

## Scoreboard Result Tree

Each task writes per-phase results to `${BSS_TMP}/scores/`:

```
${BSS_TMP}/scores/
  <task>/
    initialize/
      stdout  stderr  rc
    install/
      stdout  stderr  rc
    configure/
      stdout  stderr  rc
    execute/
      stdout  stderr  rc
```

After all tasks complete, `bootstrap.d/bin/scoreboard` walks this tree,
assembles a JSON result document, and ships it. The JSON includes per-task
per-phase exit codes, platform context from `${BSS_TMP}/facts/`, and timing
if captured at runtime.

---

## Secrets

Secrets live in `vars/secrets.env.sec` (gitignored). The committed counterpart
is `vars/secrets.env.sec.age` (ASCII-armored age encryption).

`preflight` decrypts secrets into the exported environment before any task runs.
Tasks receive secrets as environment variables — they never decrypt directly.

```bash
# In preflight — decrypt into memory, never to disk
source <(age --decrypt --identity "${MKS_AGE_PKEY:-${MKS_TMP}/age/id_rsa}" \
    "${BSS_ROOT}/vars/secrets.env.sec.age")
```

See [`docs/age.md`](../docs/age.md) for the complete secrets management specification.

---

## Make Targets

### User-Visible Targets

| Target | Description |
|---|---|
| `make bootstrap` | Run the full bootstrap pipeline |

### Internal Pipeline Targets

Defined in `bootstrap.d/main.mk`:

| Target | Description |
|---|---|
| `bootstrap.d/exports` | Static file; provides `BSS_ROOT` and `BSS_TMP` |
| `bootstrapd` | Full subproject pipeline orchestrator |
| `preflight` | Gate phase: fact gathering, secrets, env validation — abort on failure |
| `execute` | Run all task targets in parallel |
| `finalize` | Always runs: collect result tree, assemble and emit report |
| `cleanup` | Always runs: remove temp artifacts under `${BSS_TMP}` |

### Adding a Task to the Pipeline

1. Generate the task directory using the `bootstrap-task` skill:
   ```
   bootstrap.d/tasks/<name>/entry
   bootstrap.d/tasks/<name>/vars/default.env
   ```
2. Add a target in `bootstrap.d/main.mk`:
   ```makefile
   .PHONY: <name>
   <name>: bootstrap.d/exports preflight
       @echo "==- bootstrap::<name> -=="
       bootstrap.d/tasks/<name>/entry
   ```
3. Add it as a prerequisite of `tasks`:
   ```makefile
   tasks: preflight <name>
   ```
4. If this task must run after another, express that as a prerequisite:
   ```makefile
   <name>: <other>
   ```

---

## Logging

All tasks use `lib::std::logger`:

```bash
lib::std::logger -l info  -m "Installing package..."
lib::std::logger -l debug -m "Config key: ${BSS_NTP_SERVERS[0]}"
lib::std::logger -l warn  -m "NTP pool unreachable, using fallback"
lib::std::logger -l error -m "Failed to start ntp"
```

Log levels: `debug`, `info`, `warn`, `error`. All output goes to stderr.
Because tasks run in parallel, every log line must include the task name so
output remains attributable when lines interleave.

---

## Running a Task in Isolation

During development, run a task outside the full pipeline:

```bash
# From the monolith root:
source exports
bootstrap.d/tasks/<name>/entry
```

Always source `exports` first. The `run` script aborts immediately if
`MKS_ROOT` is not set.

---

## Reference

| Document | Contents |
|---|---|
| [`README.md`](README.md) | Convention overrides specific to this subproject |
| [`PROGRESS.md`](PROGRESS.md) | Implementation backlog and open decisions |
| [`docs/age.md`](../docs/age.md) | Secrets management with age encryption |
| [`docs/facts.md`](../docs/facts.md) | Global fact generators (`facts-global-os`, `facts-cloud-init`) |
| [`AGENTS.md`](../AGENTS.md) | Global Bash coding conventions |
