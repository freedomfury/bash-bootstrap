# AI Skills — Shared Conventions

This document defines the common structure, patterns, and conventions that all skills in `.agent/skills/` must follow. Skills are specialized capability modules that extend the AI's understanding of project-specific workflows.

---

## Skill Structure

Every skill directory must contain at minimum a `SKILL.md` file:

```
.agent/skills/<name>/
├── SKILL.md       # Mandatory; defines the skill's purpose, rules, and workflows
└── bin/           # Optional; helper executables for the skill
```

### `SKILL.md` — The Authoritative Definition

The `SKILL.md` file is the single source of truth for a skill. When an AI performs a task related to an existing skill (e.g., "encrypt a secret", "run in sandbox"), it must read the corresponding `SKILL.md` before taking any action.

### `bin/` — Helper Executables

Optional executable scripts that automate skill-specific tasks. These scripts:

- **Must not have a `.sh` suffix** (executables are invoked directly)
- **Must use the full 9-line Bash preamble** (see `docs/bash-conv.md` §9)
- **Must guard against missing `MKS_ROOT`**
- **Should be terse and focused** — complex logic belongs in `lib/` files elsewhere in the project

---

## Standard `SKILL.md` Sections

While skills may vary in content, most `SKILL.md` files should include these sections in order:

### 1. Title and Purpose

```markdown
# Skill: <Name>

Brief one-sentence description of what the skill does.
```

### 2. Canonical Rules (Required)

A numbered list of immutable rules that **must** be followed when working in this domain. These are not suggestions — they are requirements.

```markdown
## Canonical Rules

1. **Always do X** — never Y
2. **Use pattern Z** — because [...]
3. **Never hardcode paths** — derive from environment variables
```

### 3. Workflows (When Applicable)

Step-by-step procedures for common tasks. Number the steps and be explicit.

```markdown
## Workflows

### 1. <Action Name>

- **Goal**: What this workflow achieves
- **Procedure**:
    1. Step one
    2. Step two
    3. Step three
```

### 4. Common Failures / Common Mistakes to Avoid

A bulleted list of pitfalls and how to fix them. This helps the AI recognize errors and suggest corrections.

```markdown
## Common Failures

- **Error symptom**: Why it happens and how to fix it
- **Another symptom**: Explanation and correction
```

---

## Environment Setup

Before using any skill commands, you must set up the monolith environment:

```bash
# First time setup (if vendor doesn't exist)
./mks-vendor

# Set up environment for every session
source exports

# Now you can use skill commands
make help
```

Skills cannot run without the proper environment because they depend on:
- Vendored binaries (`age`, `jq`, etc.) in `vendor/bin/`
- Environment variables (`MKS_ROOT`, `MKS_TMP`, `MKS_VENDOR`)
- Project-specific configuration

---

## Shared Environment Patterns

All skills operate within the monolith's environment. Use these patterns consistently:

### `MKS_ROOT` — The Monolith Root

Every executable must guard against a missing `MKS_ROOT`:

```bash
[[ -n "${MKS_ROOT:-}" ]] || {
  printf 'FATAL: MKS_ROOT is not set — run via make or source exports first\n' >&2
  exit 3
}
```

### `MKS_TMP` — Temporary Directory

When a skill needs temporary files (scratch space, intermediate artifacts, etc.), **use `${MKS_TMP}/skills/<skill-name>/`**. This is the standard location for skill-local temp data.

```bash
local _skill_tmp="${MKS_TMP}/skills/my-skill"
mkdir -p "${_skill_tmp}"
```

**Rationale**: Keeps skill temp files organized under a single namespace for easy cleanup and inspection.

**Note**: Skills may write to other locations as needed for their actual work (e.g., creating project files, writing to `vendor/`, etc.). This convention applies only to transient temporary files.

### Fallback Pattern for Paths

When a path may be overridden by the user but has a sensible default:

```bash
: "${MKS_MY_PATH:=${MKS_TMP}/my-default/path}"
```

This allows users to set `MKS_MY_PATH` externally while providing a default fallback.

---

## Executable Conventions

All helper executables in `bin/` must follow the Bash executable structure defined in `docs/bash-conv.md` §9:

```bash
#!/usr/bin/env mks-bash
# <path>/file -- brief description

set -euo pipefail
shopt -s inherit_errexit
IFS=$'\n\t'

[[ -n "${MKS_ROOT:-}" ]] || {
  printf 'FATAL: MKS_ROOT is not set — run via make or source exports first\n' >&2
  exit 3
}

readonly _SELF="${0##*/}"
# ... constants ...

main() {
  # ... logic ...
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

Key points:

1. **9-line preamble** is mandatory for all Bash executables
2. **`main()` function** with guard — no bare top-level code
3. **`readonly`** for constants, **`local`** for variables
4. **`_SELF`** derived from `${0##*/}` for error messages

---

## Creating a New Skill

When adding a new capability to `.agent/skills/`:

1. **Create the directory**: `.agent/skills/<name>/`
2. **Write `SKILL.md`** with at minimum:
   - Title and purpose
   - Canonical Rules
   - Common Failures
3. **Add `bin/` helpers** if the skill requires automation
4. **Test the skill** by invoking it through the AI and verifying behavior

---

## Existing Skills

| Skill | Purpose |
|-------|---------|
| `sandbox` | Run commands in isolated Podman containers |
| `secrets` | Encrypt/decrypt project secrets with `age` |
| `bootstrap-task` | Create new tasks in `bootstrap.d/tasks/` |
| `compose` | Persistent Podman Compose sessions with systemd |

---

## Keeping This Document Current

When a new pattern emerges across multiple skills, or when an existing convention changes:

1. Update this file to reflect the new consensus
2. Review existing skills for compliance with the updated convention
3. Prompt the user before making changes to existing `SKILL.md` files
