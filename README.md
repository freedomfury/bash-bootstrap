# bash-bootstrap

A research POC that asked one question: can strict conventions make AI agents produce deterministic code in a language that's hostile to it?

AI writes Python well because Python has strong opinions baked in. Bash is the opposite: weak idioms, decades of variance, ad-hoc error handling. AI-generated Bash is usually unwieldy. The hypothesis behind this project: convention density, not language fluency, is what makes AI output reliable. To test it, I picked Bash on purpose as the worst-case environment.

The answer was yes, with enough rules. The conventions document below is the load-bearing artifact; everything else in the repo is the supporting workbench that demonstrates the methodology can carry weight beyond toy examples.

This is a proof of concept. The conventions and the experimental scaffolding are stable; the bootstrap subproject's tasks layer is intentionally unpopulated.

## The core artifact

[**docs/bash-conv.md**](docs/bash-conv.md) — 1,400 lines of Bash 5.x coding conventions. Three-tier function classification, function templates, modern idiom enforcement (`${ ; }`, `EPOCHSECONDS`, `SRANDOM`, `inherit_errexit`, `local -n` namerefs, `printf '%#Q'`), error handling patterns, library structure, testing integration, and the empirical "Common AI Mistakes" table that grew row by row as I observed and corrected AI failures. This is the document the AI reads to stay on the rails. I wrote it; the AI implemented to it.

[**AGENTS.md**](AGENTS.md) — The project-level governance spec. Path conventions, three-tier script classification (POSIX bootstrappers / Bash executables / Bash libraries), the rules for when an agent must propose updates to the conventions doc, and the standard `MKS_*` environment contract. `CLAUDE.md` and `GEMINI.md` are symlinks to this file so the same instructions serve any agent.

## The supporting workbench

### Hermetic vendored toolchain

`vendor/Containerfile` builds a self-contained binary toolkit: Make from source against musl, jsonschema from source against musl, plus pinned upstream releases of `age`, `jq`, `yq`, `jinja` (minijinja, not Python), `curl`, `trurl`, `bashunit`, `packer`, `shellcheck`, and `hcl2json`. Every binary is validated to have zero dynamic dependencies before being exported via a `FROM scratch` output stage. The result is a `vendor/bin/` directory that runs identically on any modern Linux host without any system installation.

`mks-bash` in the toolkit is a symlink to an OS-codename-specific bash binary (e.g. `resolute-bash` on Ubuntu 26.04) so the build is reproducible across distributions. Every Bash executable in the project uses `#!/usr/bin/env mks-bash` to bind to the vendored interpreter.

### Standard library (`lib/std/`)

Three modules, all namespaced `lib::std::`, all using the full Tier 1 mini-program pattern from the conventions doc:

- **`logger.sh`** — structured logging with timestamps, levels, and caller location.
- **`rmrf.sh`** — guarded deletion primitives that refuse to delete `/`, `/etc`, `/usr`, `/var`, `/home`, `/boot`, etc., with a separate file-only function that doesn't accept `-rf`. Designed to make the catastrophic-rm-rf bug class structurally impossible.
- **`secrets.sh`** — `age`-based encrypt/decrypt with sidecar-hash idempotency (re-encrypts only when source or target has changed) and a nameref-based result option for in-memory decryption that never writes plaintext to disk.

### Two execution surfaces for AI agents

The AI's working environments are kept separate from the project's test environment. They serve the AI, not the test pipeline.

- **[`sandbox`](.agent/skills/sandbox)** — One-shot rootless Podman containers for AI script execution that needs to be safe and disposable. `--cap-drop=ALL`, `--read-only` rootfs, `--network=none` by default, tmpfs overlay on `${MKS_TMP}`, project root bind-mounted read-only at `/skill`. The AI runs a destructive command in the sandbox and the container vanishes when it exits.
- **[`compose`](.agent/skills/compose)** — Persistent Podman Compose sessions with systemd as PID 1, for long-running interactive AI sessions where statefulness matters or where the workload depends on init. Containers are explicitly named, started, exec'd into, and stopped via the skill's `bin/` helpers.

### CI/CD-style end-to-end testing — `lab/packer/`

The plan was a Molecule replacement that runs against real VMs instead of containers. The Packer build works; the orchestration that wires it to bootstrap tasks is the part the experiment didn't need to reach.

What's there:

- A `run-mvp` orchestrator that spawns Packer over a custom QEMU shim, exports the right environment for Packer's `env()` function, and verifies success-marker files after the build.
- **`lab/packer/src/qemu-virtiofsd/main.go`** — a 187-line Go shim that handles the virtiofsd process lifecycle Packer doesn't natively support. Parses the virtiofs socket path from Packer's QEMU args, spawns virtiofsd as a direct child with `Pdeathsig: SIGTERM`, waits for the socket to be ready, then `exec`s into the real QEMU. Forwards SIGTERM/SIGINT to QEMU, cleans up the socket on exit. Uses Linux Pdeathsig so the kernel guarantees child cleanup even if the wrapper is SIGKILLed.
- **Schema-driven HCL generation** — Packer HCL is rendered from a JSON-Schema-validated build contract via Jinja templates. App-team-style consumers describe what they want in `builder.json`; `schema/builder.schema.json` validates the input; `builder.pkr.tpl` renders the actual `.pkr.hcl`. The invariants (cloud-init wait, virtiofs mount validation, cleanup post-processor) are baked into the template; only the variable parts (sources, provisioners, ordering) come from the validated input. An opinionated facade over Packer.

### Bootstrap subproject (`bootstrap.d/`)

The runtime payload location. The orchestration pipeline is built (`preflight` → `tasks` → `finalize` → `cleanup`), with a parallel-safe `bss::lib::runner` that tees each phase's stdout/stderr/exit code into a `scores/` tree and a `scoreboard` script that walks the tree at the end and produces a structured report. Tasks themselves are intentionally unpopulated — the `bootstrap-task` skill scaffolds them from a canonical template, but the experiment converged before any real tasks were written.

### Agent skills (`.agent/skills/`)

Skill-file pattern matching the format Anthropic now uses for Claude's own skills system: a `SKILL.md` per skill with the canonical rules and workflows, optional `bin/` helpers, optional `files/` for templates and assets.

| Skill | Purpose |
|-------|---------|
| `sandbox` | One-shot Podman containers for AI script execution |
| `compose` | Persistent Podman Compose sessions with systemd |
| `secrets` | Project secret management with `age` |
| `bootstrap-task` | Scaffolds new tasks in `bootstrap.d/tasks/` from a canonical template, with main.mk wiring |

## Quick start

```bash
./mks-vendor                      # build the vendored toolkit (one-time)
source exports                    # set MKS_ROOT, MKS_TMP, MKS_VENDOR, PATH
make help                         # list available targets
```

## Status

This is a research POC whose hypothesis was answered affirmatively: convention density makes AI output reliable in hostile languages. The conventions document and supporting infrastructure are the documented results. The cloud-tooling parts that aren't fully wired up were never the point of the experiment.

I'm not actively developing this project. It's published so that other engineers running into the same AI-augmented-Bash quality wall have something to look at.

## Layout reference

```
.
├── AGENTS.md                  Project conventions, structure, and rules (canonical)
├── CLAUDE.md → AGENTS.md      Symlink for Claude Code
├── GEMINI.md → AGENTS.md      Symlink for Gemini
├── docs/bash-conv.md          The 1,400-line Bash conventions document
├── lib/std/                   Standard library (logger, rmrf, secrets)
├── bin/                       Top-level executables (facts collectors, archive extractor, gh-get-asset)
├── bootstrap.d/               Bootstrap subproject (orchestrator + runner; tasks unpopulated)
├── lab/packer/                CI/CD-style end-to-end testing experiment
├── .agent/skills/             AI agent skill modules
├── examples/                  Reference patterns for the canonical Bash structures
├── vendor/                    Hermetic toolchain (Containerfile + build/clean scripts)
├── exports                    Environment contract sourced before any script runs
└── mks-vendor                 One-time vendor build entry point
```
