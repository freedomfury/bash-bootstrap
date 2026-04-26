# bootstrap.d

System bootstrap subproject. Configures a freshly provisioned machine —
packages, config files, services — using a parallel task pipeline modelled
on Ansible roles.

Entry point: `make bootstrap` from the monolith root.

---

## Documentation

| Document | Purpose |
|---|---|
| [`BOOTSTRAP.md`](BOOTSTRAP.md) | Full technical specification — pipeline, facts, task anatomy, scoreboard |
| [`PROGRESS.md`](PROGRESS.md) | Implementation backlog and open decisions |
| [`docs/facts.md`](../docs/facts.md) | Global fact generators used by preflight |
| [`docs/age.md`](../docs/age.md) | Secrets management |

---

## Convention Overrides

This section documents deviations from and extensions to the global
[`AGENTS.md`](../AGENTS.md) specification. Where a rule here conflicts with
the global specification, **this file takes precedence**.

### Function Namespacing

Task lifecycle functions use a `tasks::<task>::<phase>` naming scheme:

```bash
tasks::ntp::initialize()
tasks::ntp::install()
tasks::ntp::configure()
tasks::ntp::execute()
```

The task `main` function uses `task::<task>::main` (singular `task`):

```bash
task::ntp::main()
```

`task::` signals the top-level orchestrator; `tasks::` signals individual
lifecycle phases. This is a deliberate convention, not a typo.

### Variable Prefixes

| Scope | Prefix | Example |
|---|---|---|
| Bootstrap global config | `BSS_GLB_` | `BSS_GLB_APITOKEN` |
| Bootstrap task config | `BSS_<TASK>_` | `BSS_NTP_SERVERS` |

These prefixes are **required** in this subproject.

### Path Variables

`BSS_ROOT` and `BSS_TMP` are defined in `bootstrap.d/exports` and available
to all scripts that source it. Use `${BSS_TMP}/<task>/` for task-private
temporary output — never `${MKS_TMP}` for bootstrap-scoped artifacts.

### Variable Files: `exports` vs `.env`

- **`exports`**: Mandatory environment setup. Sourced first. Never sourced by `.env` consumers.
- **`.env`**: Situational config. Sourced by Bash scripts only, never by `make` recipes.

Task variable files live at `tasks/<name>/vars/default.env` and are sourced
directly by `run`. Array-valued variables are permitted (Bash 5.3+ only).

### Secrets Handling

Secrets are loaded by `preflight` only, via process substitution:

```bash
source <(age --decrypt --identity "${MKS_AGE_PKEY:-${MKS_TMP}/age/id_rsa}" \
    "${BSS_ROOT}/vars/secrets.env.sec.age")
```

Tasks must not decrypt secrets themselves — they receive exported variables
from the environment established by `preflight`.

### Parallel Execution

Tasks run in parallel by default. Use `${BSS_TMP}/<task>/` for task-private
output. Ordering constraints between tasks are expressed as Make prerequisites
only — never as calls between `run` scripts.

### Logging

All output uses `lib::std::logger`. No direct `printf` to stdout inside task
lifecycle functions. Every log line must be prefixed with the task name.
