---
name: sandbox
description: Run commands in an isolated, rootless Podman container mirroring the host OS.
---
# Skill: Sandbox — Unprivileged Podman Container

Runs commands inside a rootless, capability-stripped Podman container that
mirrors the host OS and bind-mounts the project root to `/skill`. Use this
skill for commands that are destructive, irreversible, or otherwise suspicious —
the container is fully isolated and disposable.

## Requirements

- **Podman** must be installed and on `PATH` (`podman --version`).
- The host must support rootless containers (`/etc/subuid` and `/etc/subgid`
  entries must exist for the current user).
- `MKS_ROOT` must be set (run via `make` or `source exports` first).

## Canonical Rules

1. **Always use `bin/run-podman`** — never construct a raw `podman run` command by
   hand. `bin/run-podman` encodes all mandatory security flags and the correct
   bind-mount configuration.

2. **One-shot containers are OS-matched only** — `bin/detect-image` reads
   `/etc/os-release` and uses the corresponding OCI image. There is no `--image`
   override; one-shot containers are strictly for simulating commands on the same
   operating system as the host.

3. **Bind mount is immutable by default** — the project root is mounted at
   `/skill:ro`. Pass `--mutable` when the command must write back to the working
   tree. Prefer `:ro` for all inspection, compilation, and read-only steps.

4. **`/skill/tmp` is always a tmpfs** — `MKS_TMP` (`${MKS_ROOT}/tmp`) is
   shadowed by a memory-backed filesystem inside the container. Anything
   written there (generated files, temp artifacts, exports) is wiped
   automatically when the container exits and never reaches the host.

5. **Network is isolated by default** (`--network=none`). Pass
   `--network slirp4netns` for outbound internet access or
   `--network host` only when the test genuinely requires host networking.

6. **Never pass host secrets into the container** — no `--env-file`, no `-e`
   flags, no volume mounts of key material. If a test requires credentials,
   provide them through the container image or a purpose-built mechanism.

## Caution: `--mutable` Mode

While the sandbox provides isolation, **`--mutable` mode is still destructive**.
When `--mutable` is used, writes to `/skill` (excluding `/skill/tmp`) go
directly back to the host working tree via the bind mount. Commands like
`rm -rf bootstrap.d/tasks/old-task` will **permanently delete** those files
from your project.

Always apply reasoning before running destructive commands in mutable mode:
- Verify the target path is correct
- Consider backing up important data first
- Test non-destructively (read-only) before committing to a mutation
- Remember: the container isolates the *process*, not the *files* in mutable mode

## The Canonical `podman run` Invocation

```
podman run \
  --rm \
  --userns=keep-id \
  --security-opt=no-new-privileges \
  --cap-drop=ALL \
  --network=none \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --tmpfs /run:rw,noexec,nosuid,size=16m \
  --tmpfs '/skill/tmp:rw,noexec,nosuid,size=256m,mode=0700,U' \
  --volume "${MKS_ROOT}:/skill:ro" \
  --workdir /skill \
  --pull=missing \
  -i [-t] \
  <image> \
  <command...>
```

Flag rationale:

| Flag | Why |
|------|-----|
| `--userns=keep-id` | Maps host UID into the container; without this, rootless Podman assigns a random UID and the bind mount becomes unreadable |
| `--security-opt=no-new-privileges` | Blocks setuid/setgid privilege escalation inside the container |
| `--cap-drop=ALL` | Drops all Linux capabilities; the process has no elevated access |
| `--network=none` | No inbound or outbound network access by default |
| `--read-only` | Root filesystem is immutable; nothing can be written to the image layer |
| `--tmpfs /tmp` and `/run` | Required when `--read-only` is set; many tools write to these paths at startup |
| `--tmpfs /skill/tmp` | Shadows `MKS_TMP` — generated files stay in memory and vanish on container exit |
| `-i` always, `-t` conditionally | `-i` keeps stdin open for piped invocations; `-t` adds a pseudo-TTY only when stdin is a terminal |
| `--pull=missing` | Avoids redundant registry pulls when the image is already cached locally |

## What `/skill` Contains

`/skill` is the project root (`${MKS_ROOT}`). Inside the container it looks
identical to the working tree on the host — `Makefile`, `bin/`, `lib/`,
`vendor/`, `bootstrap.d/`, etc. The container starts with `--workdir /skill`
so all relative paths resolve correctly.

`/skill/tmp` is a memory-backed overlay. Scripts that write to `${MKS_TMP}`
inside the container write to RAM — the host `tmp/` directory is unaffected.

When `--mutable` is passed, writes to `/skill` (excluding `/skill/tmp`) go directly
back to the host working tree via the bind mount. There is no copy-on-write.

## Automatic `exports` Sourcing

The entrypoint wrapper automatically sources `/skill/exports` inside the container
before executing your command. This means `MKS_ROOT`, `MKS_TMP`, `MKS_VENDOR`, and
other project environment variables are available inside the container.

**On the host**, you must still run `source exports` (or invoke via `make`) before
using the sandbox — `run-podman` requires `MKS_ROOT` to be set.

## Workflows

### 1. Run a single destructive command safely

```bash
source exports && .agent/skills/sandbox/bin/run-podman -- rm -rf bootstrap.d/tasks/old-task
```

Use `--` to prevent `bin/run-podman` from consuming flags meant for the command.

### 2. Drop into an interactive shell

```bash
source exports && .agent/skills/sandbox/bin/run-podman
```

No arguments — `bin/run-podman` defaults to `/bin/bash`.

### 3. Inspect the detected image without running a container

```bash
.agent/skills/sandbox/bin/detect-image
```

Prints the OCI image reference that would be used for the current host.

### 4. Run with write-back to the working tree

```bash
source exports && .agent/skills/sandbox/bin/run-podman --mutable -- make generate-fixtures
```

### 5. Run make targets

```bash
source exports && .agent/skills/sandbox/bin/run-podman --mutable -- make bootstrapd
```

### 6. Run with outbound network access

```bash
source exports && .agent/skills/sandbox/bin/run-podman --network slirp4netns -- curl -fsSL https://example.com
```

### 7. Inspect the resolved command without executing

```bash
source exports && .agent/skills/sandbox/bin/run-podman --verbose -- id
```

Prints the full `podman run ...` invocation to stderr before running.

## Common Failures

- **`MKS_ROOT is not set`** — Run `source exports` or invoke via `make` first.
  The sandbox requires `MKS_ROOT` to be set before running.

- **`podman: command not found`** — Install Podman.
  Debian/Ubuntu: `apt-get install podman`.

- **`cannot determine host OS image`** — The one-shot sandbox requires an OS-matched
  container. The current `bin/detect-image` mappings support `ubuntu` and `debian`.
  Add your distribution's image mapping to the `case` statement, or use a persistent
  compose workflow instead.

- **`cannot find newuidmap`** — Rootless Podman requires the `uidmap` package
  and valid `/etc/subuid`/`/etc/subgid` entries for the current user.

- **`read-only file system`** inside the container — The root FS is
  intentionally read-only. Write to `/tmp` or `/skill/tmp`, or pass `--mutable`
  to write back to `/skill`.

- **Command not found inside container** — The image may not include the tool.
  Install it inline: `bin/run-podman -- bash -c 'apt-get install -y foo && foo --version'`.

- **Permission denied on `/skill` files** — The UID inside the container does
  not match the file owner on the host. Ensure `--userns=keep-id` is present
  (it is always set by `bin/run-podman`). If the issue persists, the host files may
  be owned by a different user.
