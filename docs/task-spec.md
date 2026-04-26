# Bootstrap Task Specification (Working Draft)

Status: Working document. This file captures current decisions and direction.
It is a reference for task authors and skill behavior, not a mandatory read for
every change.

## Purpose

Define the canonical task skeleton used by bootstrap task generation and record
near-term boundaries so future work does not need to replay prior discussions.

## Scope

This document covers:

- What the canonical task template must contain right now
- What bootstrap-task skill should generate right now
- What is intentionally deferred to future skills

This document does not define translation of runbooks into full
service-specific implementations yet.

## Architecture Summary

Bootstrap follows a sandwich pipeline model:

1. Top bun: preflight prerequisites
2. Middle: task execution (parallel fan-out)
3. Bottom bun: finalize report and cleanup

The task template exists to keep the middle layer predictable and easy to
review, especially for junior contributors and AI-generated changes.

## Canonical Task Contract

Every generated task keeps the same interface in entry:

- initialize
- install
- configure
- execute

All four phase functions must exist, even if some are no-op for a specific
task.

No-op phases should use:

```bash
true
```

Rationale: true is explicit and easy to understand during reviews.

All phases are still invoked through the standard runner from entry so
scoreboard output remains consistent.

## Template Behavior Today

The bootstrap-task skill currently aims to create a working skeleton only.
That means:

1. Copy canonical template from bootstrap.d/tasks/__task__
2. Substitute __task__ and __TASK__
3. Wire task into bootstrap.d/main.mk
4. Ensure entry is executable
5. Validate with make bootstrap

This is intentionally similar to cookiecutter-style skeleton generation.

## Entry Versus Implementation

Entry is orchestration-facing and should remain compact.

- Load task vars and shared defaults
- Apply basic guards and tag filtering
- Call runner for each lifecycle phase

When task logic grows large, implementation details should move into task-local
lib or bin files and be called from entry.

This is guidance for implementation work, not a hard requirement for skeleton
generation.

## What Is In Scope Right Now

- Stabilize and refine the canonical skeleton
- Keep generation deterministic and reproducible
- Keep generated code readable for junior reviewers

## Future Scope (Not Implemented Yet)

- Runbook-to-task translation skill
- Automated filling of phase bodies from prose instructions
- Additional implementation heuristics for splitting large phase logic into
  task-local libraries

## Practical Review Checklist (Current)

For new tasks created from the skeleton:

1. entry exists and is executable
2. readonly _TASK matches the task directory name
3. All four phase functions exist
4. Runner calls cover all four phases
5. Task target is wired into bootstrap.d/main.mk
6. make bootstrap completes and scoreboard includes the task
