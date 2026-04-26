---
name: bootstrap-task
description: Creates bootstrap task skeletons by invoking the create-task helper, which copies the canonical __task__ template from the skill directory and wires targets into bootstrap.d/main.mk.
---
# Skill: Bootstrap Task Creator

Creates runnable task skeletons in bootstrap.d/tasks/ by invoking the
create-task helper. The canonical template lives in this skill directory
at .agent/skills/bootstrap-task/__task__.

---

## Canonical Rules

1. Always use create-task to generate skeletons; never copy or write by hand
2. The template lives at .agent/skills/bootstrap-task/__task__ — do not edit it
3. Only two substitutions are applied: __task__ (lowercase), __TASK__ (uppercase)
4. entry must be executable and has no extension
5. readonly _TASK must match the directory name exactly
6. Wire the task into bootstrap.d/main.mk unless explicitly told --no-wire
7. Keep the four phase functions present in entry: initialize, install,
   configure, execute
8. Unused phases should remain explicit no-op bodies using true
9. Lifecycle output should go through lib::std::logger, not direct echo/printf

For overall direction and boundaries, see docs/task-spec.md.

---

## Task Types

| Type | Creates |
|------|---------|
| Minimal | entry and vars/default.env only |
| Complete | Minimal plus empty bin/, lib/, tmpl/, files/ |

If not specified, default is complete.

---

## Creation Workflow

All steps are handled by the create-task helper:

```bash
source exports && create-task --name <name> [--type minimal|complete] [--no-wire]
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| --name \<name\> | (required) | Task name: lowercase, numbers, hyphens only |
| --type \<type\> | complete | minimal or complete |
| --wire | on | Wire task into bootstrap.d/main.mk |
| --no-wire | — | Skip main.mk wiring |
| --template \<path\> | .agent/skills/bootstrap-task/__task__ | Custom template dir |

### Examples

Create a complete wired task:
```bash
source exports && create-task --name ntp
```

Create a minimal unwired task:
```bash
source exports && create-task --name ntp --type minimal --no-wire
```

### What create-task does

1. Copies .agent/skills/bootstrap-task/__task__ to bootstrap.d/tasks/<name>
2. Applies __task__ → name and __TASK__ → UPPERCASED_NAME substitutions
3. Makes entry executable
4. Wires task into bootstrap.d/main.mk (unless --no-wire)
5. Validates output (no markers, entry executable, wiring correct)
6. Runs scoped validation — the new task only, never make bootstrap

---

## File Structure

Template source:
```
.agent/skills/bootstrap-task/__task__/
├── entry
└── vars/
    └── default.env
```

Generated output (complete):
```
bootstrap.d/tasks/<name>/
├── entry          (executable)
├── bin/
├── lib/
├── tmpl/
├── files/
└── vars/
    └── default.env
```

---

## Common Mistakes to Avoid

- Running create-task without sourcing exports first (mks-bash not on PATH)
- Using --name with uppercase letters or underscores (rejected by validation)
- Using --name __task__ (reserved, rejected)
- Expecting create-task to run the full pipeline — it validates the new task only
- Editing the template at .agent/skills/bootstrap-task/__task__ directly

## Scope Boundary

This skill creates skeletons only.

It does not translate runbooks into full task implementations. Runbook-to-task
logic belongs to a future skill.

---

## Testing Unwired Tasks

Before wiring into `main.mk`, test tasks standalone using the same environment
the Makefile provides:

```bash
source exports && source bootstrap.d/exports && bootstrap.d/tasks/<name>/entry
```

This runs the task in isolation with:
- `MKS_ROOT`, `MKS_TMP`, `MKS_VENDOR` from root `exports`
- `BSS_ROOT`, `BSS_TMP` from `bootstrap.d/exports`
- Full logger and runner infrastructure

Use this for iterative development before committing to pipeline integration.
