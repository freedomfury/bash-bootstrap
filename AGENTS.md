# Project Specification for AI-Assisted Development

> **Role:** You are an expert systems engineer specializing in modern Bash
> (5.3+), GNU Make orchestration, and infrastructure provisioning pipelines.
> This project is a hermetic, monolithic build system that will grow into a
> full configuration management and system provisioning toolchain.

> **IMPORTANT:** This file is the canonical source. `CLAUDE.md` and `GEMINI.md`
> are symlinks to this file. Do not re-read them — they contain identical
> content.

> **Bash Coding Standards:** When writing or modifying bash code, also refer to
> `docs/bash-conv.md` for detailed function templates, idioms, and patterns.

## Purpose

This file defines the project structure, architecture, and conventions unique to
this monolithic bash project. For bash-specific coding standards (function
templates, idioms, error handling, testing), see [docs/bash-conv.md](docs/bash-conv.md).

---

## Project Structure

This is a **monolithic project** containing multiple independent subprojects.
Roots are identified by directory convention — there are no marker files.
Everything is invoked from the monolith root via `make`, which sources `exports`
before delegating to subprojects:

- The **monolith root** contains `Makefile` and `exports`
- **Subprojects** are directories suffixed with `.d` (e.g. `bootstrap.d/`)
- **Tasks** are directories inside a subproject's `tasks/` folder

### Makefile as Orchestrator

The `Makefile` is the primary entry point for the monolith. Following the "Orchestrator Pattern":
- **Minimal Logic**: The Makefile should contain minimal functional logic. It acts as a thin wrapper that handles initialization and delegation.
- **Delegation**: If a build step requires more than a few lines of logic, it must be delegated to a standalone script (either a POSIX bootstrapper or a Bash task).
- **Parallelism**: The Makefile prioritizes orchestrating scripts in parallel and managing their output, not performing the work itself.
- **Pure Orchestration**: The Makefile is an orchestrator: it may execute things in parallel, but it does not perform "actual functional things" about the build.

### Subprojects

Each subproject directory is suffixed with `.d` (e.g., `bootstrap.d/`) and contains:
- Its own `README.md` (project-specific documentation and convention overrides)
- Its own `lib/`, `bin/`, `vars/`, and other directories as needed
- A `tasks/` directory (optional) containing self-contained units of work

Each task inside a subproject's `tasks/` directory contains:
- An `entry` executable — the task's entry point
- Its own `bin/`, `lib/`, `vars/`, `tmpl/`, and `files/` directories as needed

Each subproject's `README.md` may define overrides, extensions, or clarifications to the
global conventions in this file. When working on a subproject, agents must read both
this file and the subproject's README — subproject rules take precedence in case of
conflict.

### Path Variables

Scripts navigate this structure using environment variables. `MKS_ROOT` is set
by the `exports` file (sourced before any script runs), and everything else derives from it:

| Variable | Set by | Points to |
|---|---|---|
| `MKS_ROOT` | `exports` | Monolith root |
| `MKS_TMP` | `exports` | Temporary directory |
| `MKS_VENDOR` | `exports` | `${MKS_ROOT}/vendor/bin` |
| `_PROJECT_ROOT` | Each subproject entry script | Subproject root (e.g. `bootstrap.d/`) |
| `BSS_ROOT` | `bootstrap.d/exports` | Subproject root (exported) |

All entry-point scripts guard against a missing `MKS_ROOT`. Note that only `vendor/build` and `vendor/clean` must remain strictly POSIX compliant (`/bin/sh`) — these are pre-bash bootstrappers that run before the vendor toolkit exists. The root-level `Makefile` and all included `.mk` fragments use `mks-bash` as the shell. All other scripts in this project (including `run` and `lib/` files) are Bash 5.3+.

```bash
# Bash 5.3+ guard pattern
[[ -n "${MKS_ROOT:-}" ]] || {
  printf 'FATAL: MKS_ROOT is not set — run via make or source exports first\n' >&2
  exit 3
}

# POSIX /bin/sh guard pattern (minimal)
if [ -z "${MKS_ROOT:-}" ]; then
  printf 'FATAL: MKS_ROOT is not set — run via make or source exports first\n' >&2
  exit 3
fi
```

The entry-point constraint: `exports` must be sourced before any script executes.

**Interactive and Agent Shell Sessions**

Because every `Bash` tool call runs in its own subshell, environment variables set in one call do not persist to the next. `source exports` cannot be run once at session start and relied upon thereafter — it must be prepended to every command that needs the vendor environment.

The correct pattern for any shell command that depends on `MKS_ROOT`, `mks-bash`, or vendored binaries is:

```bash
source exports && mks-bash -c '...'
```

For multi-step commands, source inside the same shell invocation:

```bash
source exports && mks-bash -c 'source exports && source lib/std/secrets.sh && ...'
```

**If you see errors about `mks-bash` not found**, the vendor environment is not set up correctly.
See [VENDOR.md](VENDOR.md) for common errors and the fix.

---

## Script Classification

Every script in this project falls into one of three categories. Each category has distinct requirements for shell target, structure, and coding style.

### Type 1 — POSIX Bootstrappers (`/bin/sh`)

Extremely minimal scripts used for the initial setup of the developer environment or build orchestration before Bash is available.
- **Examples**: `vendor/build`, `vendor/clean`.
- **Requirements**:
  - Shebang: `#!/bin/sh`
  - Strict Mode: `set -eu` (POSIX only)
  - No `main()` function; linear execution is preferred.
  - Must avoid all bashisms (no `[[`, no `(( ))`, no `declare`, no `local -n`, no `readonly`).
  - Script name: `_SELF="${0##*/}"` (no `readonly` — not POSIX).
  - Minimal environment guard: `if [ -z "${MKS_ROOT:-}" ]; then ... fi`.
- **Note**: These are "PRE-BASH" scripts. They are used to create the environment (bootstrapping) before the functional Bash environment is established.

### Type 2 — Bash Executables

Standard entry-point scripts and tasks that leverage modern Bash features.
- **Examples**: `bin/extract-archive`, `bootstrap.d/tasks/dumb/entry` (example task name).
- **Requirements**:
  - Shebang: `#!/usr/bin/env mks-bash`
  - Full 9-line preamble (see [docs/bash-conv.md Section 10](docs/bash-conv.md#10-bash-executable-structure)).
  - Use of `main()` function and `main "$@"` call guard.
  - Script name: `readonly _SELF="${0##*/}"` (after shebang and strict mode).
  - Strict adherence to all Bash 5.3+ idioms and project conventions.

### Type 3 — Bash Libraries (`.sh`)

Sourced files containing reusable logic and Tier 1 functions.
- **Example**: `lib/std/logger.sh`.
- **Requirements**:
  - No shebang.
  - Source Guard pattern (see [docs/bash-conv.md Section 8](docs/bash-conv.md#8-bash-library-structure-sh)).
  - Inherit strict mode from the caller; do not redeclare `set -euo pipefail`.
  - Tier 1 function patterns for all exported logic.

---

## External Tools

All third-party compiled binaries are vendored under `vendor/bin/`. These are
statically linked and require no system installation. Scripts must always use
these vendored binaries rather than relying on system-provided versions.

### Vendored Binaries

| Binary | Language | Purpose |
|---|---|---|
| `age` | Go | File encryption/decryption — uses SSH key pairs (public/private) |
| `mks-bash` | C | Symlink to OS-codename-specific bash (e.g., `resolute-bash` for Ubuntu 26.04) — authoritative runtime shell |
| `curl` | C | HTTP requests |
| `jinja` | Rust | Template rendering — NOT Python Jinja2 |
| `jq` | C | JSON processing |
| `make` | C | Build automation and parallelization via `make -j` |
| `trurl` | C | URL parsing and manipulation |
| `yq` | Go | YAML/JSON/TOML processing |

### Auxiliary Dev Tools (`vendor/bin/dev/`)

The `vendor/bin/dev/` directory holds auxiliary tooling for development and
secret management workflows. These binaries are **not** added to `PATH` by
the `exports` file and must be referenced by full path when needed.

| Binary | Purpose |
|---|---|
| `bashunit` | Bash testing framework |
| `packer` | HashiCorp Packer - machine image building tool |
| `age-inspect` | Inspect age-encrypted file headers |
| `age-keygen` | Generate age key pairs |
| `age-plugin-batchpass` | Batch passphrase plugin for age |
| `shellcheck` | Shell script static analyser |
| `jsonnet` | JSON configuration language |
| `jsonnetfmt` | Jsonnet code formatter |
| `jsonnet-lint` | Jsonnet linter |
| `jsonschema` | JSON schema validation (sourcemeta/jsonschema - built from source) |

### Secrets Management (`age`)

`age` is the only approved tool for encrypting and decrypting secrets in this
project. The canonical pattern — encrypt once with an SSH public key, decrypt
at runtime via `source <(age --decrypt ...)` with no plaintext ever written to
disk — is documented in full here:

**[docs/age.md](docs/age.md)**

When writing any script that loads secrets, follow that document exactly.

### Resolving Vendored Binaries

`MKS_VENDOR` is set by the `exports` file and points to
`${MKS_ROOT}/vendor/bin`. The `exports` file ensures vendor binaries are on `PATH`:

```bash
# From exports file
export PATH="${MKS_VENDOR}:${PATH}"
```

`vendor/bin/` is prepended to `PATH` by the `exports` file, so vendored tools (`jq`, `yq`,
`jinja`, etc.) are available unqualified in any script that sources `common.sh`.
For clarity in scripts that construct commands explicitly, use the full path:

```bash
local result="${ "${MKS_VENDOR}/jq" '.name' "${json_file}"; }"
"${MKS_VENDOR}/yq" '.services' "${config_file}"
```

### Shebang and Bash Version

The statically compiled `vendor/bin/mks-bash` (symlink to OS-codename-specific binary like `resolute-bash` for Ubuntu 26.04) is the authoritative runtime.

All project scripts use `#!/usr/bin/env mks-bash` in shebangs. This asserts that:
1. The vendor toolkit has been built (`./mks-vendor` was run)
2. The `exports` file has been sourced (adding `vendor/bin/` to PATH)
3. All `MKS_*` environment variables are available

If `mks-bash` is not found, see [VENDOR.md](VENDOR.md) for troubleshooting.

The `install` script rewrites shebangs in installed copies to the absolute
path of the deployed Bash binary, ensuring the correct version runs in
production regardless of what the system provides.

### Building Vendor Binaries

Vendor binaries are built/downloaded by running:

```bash
./mks-vendor
```

This ensures the statically-compiled toolkit is built and available. Run this once after cloning the repo, or whenever `vendor.lock` is missing. To force a clean rebuild, remove `vendor.lock` and run `./mks-vendor` again.

See [VENDOR.md](VENDOR.md) for complete details.

---

## Secrets Management with `age`

Secrets are encrypted with `age` using SSH key pairs and decrypted at runtime via process substitution. This ensures that plaintext secrets never touch the disk.

### Identity Resolution

The private key used for decryption must be **unencrypted** (no passphrase) to allow for non-interactive execution in scripts and CI/CD.

| Variable | Fallback Path | Description |
|---|---|---|
| `MKS_AGE_PKEY` | `${MKS_TMP}/age/id_rsa` | Path to the unencrypted private key |

### Usage Pattern

Always resolve the identity path using the designated fallback:

```bash
: "${MKS_AGE_PKEY:=${MKS_TMP}/age/id_rsa}"
source <(age --decrypt --identity "${MKS_AGE_PKEY}" "${_SECRETS_AGE}")
```

For more details, see [docs/age.md](docs/age.md).

---

## Makefile Tasks Policy

The root-level `Makefile` is the primary entry point for the monolithic project. To maintain a clean and focused root, the following rules apply:

1. **Strict Validation**: No new root-level targets or "convenience" tasks may be added to the `Makefile` without explicit validation and approval from the USER.
2. **Subproject Delegation**: Complex logic and task-specific scripts must live within their respective subprojects (`<subproject>.d/`) and be invoked via `make` only when part of a high-level pipeline (e.g., `make bootstrap`).
3. **Internal Guards**: Targets that rely on the vendored toolkit (e.g., `exports`) must include internal guards to verify `vendor.lock` exists and provide helpful error messages directing the user to `./mks-vendor`.
4. **POSIX Compliance & Orchestration**: Only `vendor/build` and `vendor/clean` must remain strictly POSIX compliant (`/bin/sh`) — these are pre-bash bootstrappers that run before the vendor toolkit exists. The root-level `Makefile` and all included `.mk` fragments now use `mks-bash` as the shell (via `/usr/bin/env mks-bash`). Bashisms are now acceptable in `.mk` recipes. All other scripts in the project are Bash 5.3+.

---

## Project Layout

```
project-root/
├── AGENTS.md                  ← AI instruction file; canonical source
├── CLAUDE.md                  ← symlink to AGENTS.md
├── GEMINI.md                  ← symlink to AGENTS.md
├── README.md                  ← Project overview, usage, quickstart
├── CHANGELOG.md               ← Structured change history
├── VERSION                    ← Single file containing version string
├── Makefile                   ← Single top-level task runner; no subproject Makefiles
├── exports                    ← Static file; defines MKS_ROOT, MKS_TMP, MKS_VENDOR, PATH
├── .gitignore
├── .shellcheckrc              ← Linter config
├── .agent/                    ← AI-assisted development resources
│   ├── README.md              # Shared conventions for all skills
│   └── skills/                ← Specialist instruction sets and helpers
│       └── <name>/
│           ├── SKILL.md       # Capability definition and rules
│           └── bin/           # Skill-specific helper executables
│
├── inc/                       ← Makefile include fragments (not a subproject)
│   ├── common.mk              ← Shared Make variables and shell config
│   └── <subproject>.mk        ← Per-subproject pipeline targets
│
├── vendor/                    ← Statically-compiled toolkit
│   ├── build                  ← Manual setup script (touches vendor.lock)
│   ├── clean                  ← Manual cleanup script (removes vendor.lock)
│   ├── vendor.lock            ← Sentinel file (prerequisite for Makefile)
│   ├── bin/                   ← Built binaries (gitignored)
│   └── Containerfile          ← Build definition
│
├── bin/                       ← Global executables — no .sh suffix on any file here
│   └── my-tool
│
├── lib/                       ← Sourced libraries — .sh suffix required
│   └── std/                   ← Namespaced standard library (lib::std::*)
│       ├── logger.sh          ← Structured logging (lib::std::logger)
│       ├── secrets.sh         ← Age encryption/decryption (lib::std::secrets)
│       └── rmrf.sh            ← Safe file deletion (lib::std::rmrf)
│
├── <subproject>.d/            ← Independent subproject (.d suffix)
│   ├── main.mk                ← Subproject pipeline
│   ├── README.md              ← Subproject docs and convention overrides
│   ├── exports                ← Subproject env vars (sourced after monolith exports)
│   ├── lib/                   ← Subproject-wide libraries
│   ├── vars/                  ← Subproject-wide variables
│   └── tasks/                 ← Self-contained units of work
│       └── <task-name>/
│           ├── entry          ← Task entry point (no .sh suffix)
│           ├── bin/           ← Task-private executables
│           ├── lib/           ← Task-private libraries
│           ├── files/         ← Static files to deploy
│           ├── tmpl/          ← Templates rendered by jinja
│           └── vars/
│               └── default.env  ← Task defaults
│
├── tests/                     ← bashunit test files (_test.sh suffix)
│   ├── lib/                   ← Mirrors lib/ — one _test.sh per source file
│   │   └── std/
│   │       ├── logger_test.sh
│   │       └── secrets_test.sh
│   └── bootstrap.d/           ← Mirrors subproject structure
│       └── ...
│
└── docs/
    ├── bash-conv.md           ← Bash coding conventions
    ├── age.md                 ← Secrets management with age
    ├── functions.md           ← Auto-generated function reference
    ├── architecture.md        ← How the pieces fit together
    └── contributing.md
```

### Layout Rules

- **No `.sh` suffix on any executable** — `bin/`, `scripts/`, and root-level
  executables like `install` are all invoked directly and never get `.sh`
- **`.sh` suffix only on sourced files** — everything in `lib/` gets `.sh`
- **`VERSION`** is read by scripts via `${ cat "${ROOT}/VERSION"; }` —
  never hardcode version strings inside scripts
- **`etc/`** holds templates that ship with the project; runtime config
  lives outside the project root (e.g. `~/.config/my-tool/`)
- **`share/`** holds static data (lookup tables, templates) that scripts
  read at runtime; keeps data out of `lib/`
- Dev/build scripts live in `bin/` alongside other executables when needed
- **`.agent/`** is not ignored by Git — skill definitions should be committed
  to ensure all agents and developers share the same project capabilities

---

## Testing

**Status: Work in Progress — Tests are optional at this time.**

**Agent instruction: Unless specifically prompted by the user, do not add tests.**

### Philosophy

Tests target reusable components, not every script in the project.

- **Primary target**: Files in `lib/` — these are included elsewhere and should be robust
- **Migration trigger**: When a `bin/` script becomes important or large, refactor it into `lib/` and add tests
- **Scope**: Test what logically breaks — core functionality and error paths
- **Approach**: Keep tests simple; use mocking sparingly
- **No retrofitting**: Existing code does not require immediate test coverage

### Test Framework

The project uses `bashunit` (vendored at `vendor/bin/dev/bashunit`) for testing.

Test files use the `_test.sh` suffix. The `tests/` directory mirrors the
project structure — each path under `tests/` corresponds to the source it tests:

- `tests/lib/std/logger_test.sh` tests `lib/std/logger.sh`
- `tests/bootstrap.d/...` tests code under `bootstrap.d/`

### Running Tests

Tests are driven through `make` using directory-based targets. The Makefile
uses a pattern rule so that `tests/` paths are discoverable via tab-completion:

```bash
make test                  # run all tests
make test/lib              # run tests for root lib/ only
make test/lib/std          # run tests for a specific lib namespace
make test/bootstrap.d      # run all tests for the bootstrap subproject
```

For development or debugging, tests can be run directly with bashunit:

```bash
vendor/bin/dev/bashunit tests/lib/std/
```

---

## AI Skills (`.agent/skills/`)

Skills are specialized capability modules that extend the AI's understanding of
the project. Each skill lives in `.agent/skills/<name>/` and must contain a
`SKILL.md` file.

### Skill Structure

| File | Purpose |
|---|---|
| `SKILL.md` | **Mandatory**; defines the authoritative rules and workflows |
| `bin/` | Optional; contains helper executables relevant to the skill |
| `examples/` | Optional; contains sample payloads or reference data |

When performing a task related to an existing skill (e.g. `secrets`), the AI
must read the corresponding `SKILL.md` before taking any action.

**See [.agent/README.md](.agent/README.md)** for shared conventions across all
skills, including standard `SKILL.md` sections, environment patterns, and
executable conventions.

---

## Keeping This Document Current

`AGENTS.md` is a living specification. As the project evolves — new conventions
adopted, new idioms introduced, new mistakes discovered — this file must evolve
with it. `CLAUDE.md` and `GEMINI.md` are symlinks to this file; editing
`AGENTS.md` updates them automatically. Never edit the symlinks directly.

### Agent responsibility

After completing any task that introduces a new pattern, convention, or
correction to a documented rule, the agent must:

1. **Assess** whether the change warrants an update to `AGENTS.md` or `docs/bash-conv.md`
2. **Prompt the user** before making any edits — describe which section is
   affected and what the proposed change would say
3. **Wait for explicit approval** before modifying the file
4. **Apply the update** once approved, keeping the style and tone consistent
   with the rest of the document

### When to propose an update

Propose an update when any of the following occur:

- A new Bash idiom or pattern is established that no existing rule covers → update `docs/bash-conv.md`
- A new "Common AI Mistakes" entry is identified → update `docs/bash-conv.md`
- A vendored binary is added to or removed from `vendor/bin/` → update `AGENTS.md`
- A subproject or task introduces a convention that should be elevated to
  the global spec → update `AGENTS.md`
- An existing rule turns out to be incomplete, ambiguous, or wrong in practice
- A new `docs/` document is created that should be cross-referenced here
- The project layout changes in a way that invalidates the documentation

### What requires user approval before changing

Do not modify existing rules without first confirming with the user that the
intent is to change behaviour, not merely to fix a typo or clarify wording.
Behavioural changes — even small ones — require explicit sign-off.
