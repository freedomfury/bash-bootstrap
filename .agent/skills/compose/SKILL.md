---
name: compose
description: Manage persistent Podman Compose sessions with systemd as PID 1.
---
# Skill: Compose — Persistent Podman Compose Sessions

Starts persistent container sessions using Podman Compose with systemd as PID 1.
Each OS variant has its own directory containing a Containerfile that builds
a systemd-enabled image. Use this skill for longer troubleshooting sessions,
testing systemd-dependent functionality, or running multiple commands in the
same container environment.

## Requirements

- **Podman** must be installed and on `PATH` (`podman --version`)
- **podman-compose** must be installed and on `PATH` (`podman-compose --version`)
  - Install: `pip install podman-compose` or via your package manager
- The host must support rootless containers (`/etc/subuid` and `/etc/subgid`
  entries must exist for the current user)
- `MKS_ROOT` must be set (run via `make` or `source exports` first)

## Directory Structure

Each OS variant has its own directory in `files/`:

```
files/
├── alma-9-systemd/
│   ├── Containerfile     # Builds AlmaLinux 9 image with systemd
│   └── compose.yaml      # Compose file using local build
└── ubuntu-25.10-systemd/
    ├── Containerfile     # Builds Ubuntu 25.10 image with systemd
    └── compose.yaml      # Compose file using local build
```

Images are built automatically on first use and cached for subsequent runs.

## Canonical Rules

1. **Always use the bin/* scripts** — never invoke `podman-compose` directly.
   The `bin/start`, `bin/exec`, and `bin/stop` scripts encapsulate the correct
   project names, service names, and cleanup logic.

2. **Use curated compose directories** — each OS variant has its own directory
   in `files/` (e.g., `ubuntu-25.10-systemd/`) containing a Containerfile and
   compose.yaml. The Containerfile builds a systemd-enabled image; compose.yaml
   references the local build with `build: context: .`. No OS auto-detection.

3. **All sessions run systemd** — every compose file uses `/lib/systemd/systemd` as
   the entrypoint with `SYS_ADMIN` capability and `seccomp=unconfined`. This
   enables full systemd functionality inside the container without full
   `privileged` mode.

4. **Project names derive from compose files** — when starting a session without
   `--name`, the project name is derived from the compose file basename
   (e.g., `ubuntu-25.10-systemd.yaml` → `ubuntu-25.10-systemd`).

5. **Containers are persistent** — unlike the sandbox skill, compose sessions
   continue running after commands complete. You must explicitly stop them with
   `bin/stop`.

6. **The project root is writable** — `/skill` is mounted read-write by default,
   unlike the sandbox's read-only default. This is necessary for task execution
   and systemd operation.

## Caution: Elevated Capabilities

All compose sessions run with `SYS_ADMIN` capability and `seccomp=unconfined`
to enable systemd. This gives the container elevated capabilities:

- The container can perform most system administration tasks
- Security boundaries between host and container are reduced compared to the sandbox

**Use compose sessions only for trusted workloads**. For untrusted or
suspicious commands, prefer the sandbox skill (`.agent/skills/sandbox`) instead.

## Workflows

### 1. Start a new compose session

```bash
source exports
.agent/skills/compose/bin/start --compose .agent/skills/compose/files/ubuntu-25.10-systemd/compose.yaml
```

This starts a session named `ubuntu-25.10-systemd` (derived from the directory name).
On first run, the image will be built (may take 1-2 minutes). Subsequent runs
use the cached image and start quickly.

**Note**: The compose file path is relative to the project root. Use the full
path `.agent/skills/compose/files/...` when invoking from the project root.

### 2. Start with a custom project name

```bash
source exports
.agent/skills/compose/bin/start --compose .agent/skills/compose/files/ubuntu-25.10-systemd/compose.yaml --name my-test
```

### 3. Run commands in the active session

```bash
# Example commands
.agent/skills/compose/bin/exec --name ubuntu-25.10-systemd -- systemctl status
.agent/skills/compose/bin/exec --name ubuntu-25.10-systemd -- make bootstrapd
.agent/skills/compose/bin/exec --name ubuntu-25.10-systemd -- /bin/bash
```

### 4. Stop and destroy a session

```bash
# Stop the session (volumes preserved)
.agent/skills/compose/bin/stop --name ubuntu-25.10-systemd

# Stop and remove volumes
.agent/skills/compose/bin/stop --name ubuntu-25.10-systemd --volumes
```

### 5. Using AlmaLinux 9

```bash
# Start an AlmaLinux 9 session
source exports
.agent/skills/compose/bin/start --compose .agent/skills/compose/files/alma-9-systemd/compose.yaml

# Example commands (AlmaLinux uses dnf instead of apt)
.agent/skills/compose/bin/exec --name alma-9-systemd -- dnf install -y nginx
.agent/skills/compose/bin/exec --name alma-9-systemd -- systemctl enable --now nginx
```

## What `/skill` Contains

`/skill` is the project root (`${MKS_ROOT}`) mounted read-write. Inside the
container it looks identical to the working tree on the host — `Makefile`,
`bin/`, `lib/`, `vendor/`, `bootstrap.d/`, etc.

The container starts with `working_dir: /skill` so all relative paths resolve
correctly.

`/skill/tmp` is a tmpfs mount — writes go to RAM and vanish when the container
is stopped. This shadows `${MKS_TMP}` on the host.

## Environment Variables Inside Sessions

The compose configuration does **not** automatically source `exports`. To access
`MKS_ROOT`, `MKS_TMP`, and other project variables inside a session, source them
manually:

```bash
.agent/skills/compose/bin/exec --name my-session -- bash -c 'source /skill/exports && env | grep MKS'
```

Or drop into a shell and source interactively:

```bash
.agent/skills/compose/bin/exec --name my-session -- /bin/bash
# Inside container:
source /skill/exports
```

## Common Failures

- **`MKS_ROOT is not set`** — Run `source exports` or invoke via `make` first.
  The compose skill requires `MKS_ROOT` to be set before running.

- **`podman-compose: command not found`** — Install podman-compose.
  `pip install podman-compose` or use your distribution's package manager.

- **`permission denied` on `/skill` files** — The UID inside the container
  does not match the file owner on the host. Ensure `userns_mode: keep-id`
  is set in the compose file (it is set by default in all provided compose files).

- **`Failed to mount` or `tmpfs` errors** — The container may not have sufficient
  privileges. Ensure `cap_add: SYS_ADMIN` and `security_opt: seccomp=unconfined`
  are set in the compose file.

- **`systemd not running`** — Verify `/lib/systemd/systemd` is the entrypoint and
  `cgroup_mode: host` is set. Run `systemctl status` to confirm.

- **Container exits immediately** — Check the compose file for errors.
  Run `podman-compose --project-name <name> logs` to see the container output.

- **`project name already in use`** — A session with that name is already running.
  Use `bin/stop --name <name>` to stop it first, or choose a different name.
