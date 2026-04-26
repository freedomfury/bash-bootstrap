# Bootstrap Task Move Specification (Working Draft)

Status: Working document.

This file defines the specification for a future helper script that will create
bootstrap task skeletons for the bootstrap-task skill. This is a requirements
document, not an implementation.

## Purpose

Standardize how task skeleton creation is performed so task generation is:

- deterministic
- reproducible
- easy to review
- aligned with the canonical __task__ contract

## Script Specification

### Script identity

- Planned path: .agent/skills/bootstrap-task/bin/create-task
- Planned shell: #!/usr/bin/env mks-bash
- Script class: Bash executable (Type 2 project convention)

### Responsibilities

The script must:

1. Create a new task directory from the canonical template
2. Apply two substitutions only: __task__ and __TASK__
3. Ensure entry is executable
4. Optionally wire the task into bootstrap.d/main.mk
5. Fail fast with clear errors on invalid input or conflicts

The script must not:

1. Generate service-specific implementation logic
2. Translate runbooks into task bodies
3. Modify global architecture or lifecycle contracts

## Input Contract

### Required options

- --name <task-name>

### Optional options

- --type <minimal|complete>
- --wire (default behavior)
- --no-wire
- --template <path>

### Option rules

1. Task names use lowercase letters, numbers, and hyphen only
2. Reserved name __task__ is rejected
3. Target task directory must not already exist
4. --wire and --no-wire are mutually exclusive
5. If --type is omitted, default is complete

## Output Contract

### Directory outputs

For --type minimal:

- bootstrap.d/tasks/<name>/entry
- bootstrap.d/tasks/<name>/vars/default.env

For --type complete, include minimal outputs plus:

- bootstrap.d/tasks/<name>/bin/
- bootstrap.d/tasks/<name>/lib/
- bootstrap.d/tasks/<name>/tmpl/
- bootstrap.d/tasks/<name>/files/

### File content guarantees

1. __task__ placeholders are replaced with task name
2. __TASK__ placeholders are replaced with uppercased task name
3. readonly _TASK equals the task directory name
4. Lifecycle function names preserve required namespace conventions

### Pipeline wiring behavior

If wiring is enabled, the script updates bootstrap.d/main.mk to:

1. Add task to .PHONY
2. Add task to tasks: prerequisites
3. Add task target invoking bootstrap.d/tasks/<name>/entry

If --no-wire is used, no edits to bootstrap.d/main.mk are performed.

## Error Handling Requirements

The script must return non-zero and print a clear error when:

1. --name is missing or invalid
2. target directory already exists
3. template path is missing or unreadable
4. substitutions fail
5. bootstrap.d/main.mk cannot be updated safely when wiring is enabled

## Validation Requirements

After successful creation, the following should hold:

1. Task directory exists with expected files
2. entry is executable
3. No unreplaced __task__/__TASK__ markers remain
4. main.mk wiring matches requested mode (wire or no-wire)

### Scoped runtime validation (required)

The helper must validate only the newly created task, not the full bootstrap
pipeline.

** Import notes: **

Running the full pipeline during task creation can execute unrelated tasks and
cause unnecessary or risky changes on a development machine.

If wiring is enabled, run:

```bash
source exports && make --no-print-directory <name>
```

If --no-wire is used, run the entry directly:

```bash
source exports && bootstrap.d/tasks/<name>/entry
```

Do not run make bootstrap as part of helper validation.

## Relationship to Existing Docs

- task contract and scope: docs/task-spec.md
- skill behavior and usage: .agent/skills/bootstrap-task/SKILL.md

## Future Scope (Out of Scope Here)

1. Runbook-to-task translation
2. Auto-filling lifecycle bodies from prose
3. Intelligent refactoring of large phase bodies into task-local libraries
