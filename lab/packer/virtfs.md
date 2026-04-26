# Migrating Packer QEMU Source from 9P to virtiofsd

## Problem

The original Packer configuration used 9P (`-virtfs`) to mount the project directory read-only into QEMU guests. Red Hat has deprecated 9P in favor of virtiofs. Unlike 9P, virtiofs requires a userspace daemon (`virtiofsd`) running on the host with its own socket — creating a lifecycle problem since Packer has no native "sidecar daemon" concept.

## Solution Overview

Use Packer's `qemu_binary` attribute to point at a Go wrapper (`bin/qemu-virtiofsd`) instead of the real `qemu-system-x86_64`. The wrapper:

1. Parses the virtiofsd socket path from the QEMU arguments Packer passes it
2. Starts `virtiofsd` with `--readonly` as a direct child process
3. Waits for the socket to appear (polls with timeout)
4. Starts the real QEMU binary with all original arguments
5. Forwards signals (SIGTERM, SIGINT) to QEMU
6. Cleans up virtiofsd and the socket on exit

Both virtiofsd and QEMU are started with `Pdeathsig=SIGTERM` so the kernel automatically signals them if the wrapper dies — including via SIGKILL.

This keeps the Packer HCL generic. Each source block uses the same wrapper. The virtiofsd plumbing is invisible to Packer.

## Why This Works for Concurrent Builds

Each Packer build invocation launches its own wrapper process, which spawns its own `virtiofsd` with its own socket. The socket path is made unique via Packer's `{{ .Name }}` and `{{ .SSHHostPort }}` template variables (used in `locals` for socket and serial console paths). The `--readonly` flag ensures concurrent builds cannot corrupt the shared host directory.

## Architecture

```
Packer build
  └─ qemu_binary = bin/qemu-virtiofsd (Go wrapper)
       ├─ virtiofsd --socket-path=<unique> --shared-dir=<host dir> --readonly
       │   (Pdeathsig=SIGTERM)
       └─ /usr/bin/qemu-system-x86_64 (original args)
            (Pdeathsig=SIGTERM, signal forwarding)
            └─ Guest mounts virtiofs tag "shared-vfsd" at /var/run/shared-vfsd
```

---

## HCL Configuration

### Variables

The wrapper path and shared directory are passed via environment variables bound to Packer variables:

```hcl
variable "virtiofsd_wrapper" {
  type    = string
  default = env("VIRTIOFSD_WRAPPER")
}

variable "cache_dir" {
  type    = string
  default = env("PACKER_CACHE_DIR")
}
```

A `locals` block computes per-build socket and serial console paths:

```hcl
locals {
  run_dir     = "${var.cache_dir}/run"
  vfsd_sock   = "${local.run_dir}/{{ .Name }}-{{ .SSHHostPort }}.sock"
  serial_sock = "${local.run_dir}/{{ .Name }}-{{ .SSHHostPort }}-serial.sock"
  serial_log  = "${local.run_dir}/{{ .Name }}-{{ .SSHHostPort }}-serial.log"
}
```

### Source Block

Each source block (e.g. `almalinux-97`) references the wrapper and configures virtiofs via QEMU arguments:

```hcl
source "qemu" "almalinux-97" {
  iso_url          = var.image_maps["almalinux-97"].iso_url
  iso_checksum     = var.image_maps["almalinux-97"].iso_checksum
  use_backing_file = true
  disk_image       = true

  # -- Guest hardware
  cpus        = 2
  memory      = 2048
  format      = "qcow2"
  accelerator = "kvm"
  qemu_binary = var.virtiofsd_wrapper

  qemuargs = [
    ["-cpu", "host"],

    # -- virtiofs requirements: shared memory backend
    ["-object", "memory-backend-memfd,id=mem,size=2048M,share=on"],
    ["-numa", "node,memdev=mem"],

    # -- virtiofsd socket (wrapper reads this path to start the daemon)
    ["-chardev", "socket,id=vfsd,path=${local.vfsd_sock}"],
    ["-device", "vhost-user-fs-pci,chardev=vfsd,tag=shared-vfsd"],

    # -- Serial console
    ["-chardev", "socket,id=serial,path=${local.serial_sock},server,nowait,logfile=${local.serial_log}"],
    ["-serial", "chardev:serial"],

    # -- Network
    ["-netdev", "user,hostname={{ .Name }}-{{ .SSHHostPort }},hostfwd=tcp::{{ .SSHHostPort }}-:22,id=forward"],
    ["-device", "virtio-net,netdev=forward,id=net0"],

    # -- Cloud-init via SMBIOS (NoCloud datasource)
    ["-smbios", "type=1,serial=ds=nocloud;h={{ .Name }}-{{ .SSHHostPort }}"]
  ]

  # -- Cloud-init via config drive (CIDATA)
  cd_label = "cidata"
  cd_content = {
    "meta-data" = <<-EOF
      instance_id: "{{ .Name }}-{{ .SSHHostPort }}"
    EOF

    "user-data" = <<-EOF
      #cloud-config

      users:
        - name: ${var.admin_user}
          uid: ${var.host_uid}
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${data.sshkey.build.public_key}
      runcmd:
        - setenforce 0
        - mkdir -p /var/run/shared-vfsd
        - mount -t virtiofs shared-vfsd /var/run/shared-vfsd
    EOF
  }

  # -- SSH communicator (key from sshkey plugin)
  communicator         = "ssh"
  ssh_username         = var.admin_user
  ssh_private_key_file = data.sshkey.build.private_key_path
  ssh_timeout          = "5m"
  headless             = true
}
```

### Cloud-Init Details

The guest is bootstrapped via two mechanisms:
- **SMBIOS NoCloud**: `-smbios type=1,serial=ds=nocloud;h=...` tells cloud-init to use the NoCloud datasource
- **CIDATA config drive**: `cd_content` with `cd_label = "cidata"` provides meta-data and user-data

The `runcmd` section mounts the virtiofs share. No kernel module loading is needed — virtiofs support is built into the kernel on RHEL 8+, Ubuntu 20.04+, and AlmaLinux 9.

---

## Go Wrapper (`src/qemu-virtiofsd/main.go`)

The wrapper is compiled to `bin/qemu-virtiofsd`. `run-mvp` builds it automatically if missing or if the source is newer.

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `VIRTIOFSD_SHARED_DIR` | Yes | — | Host directory to expose read-only to guests |
| `VIRTIOFSD_BIN` | No | `/usr/libexec/virtiofsd` | Path to virtiofsd binary |
| `QEMU_BIN` | No | `/usr/bin/qemu-system-x86_64` | Path to real QEMU binary |

### Key Design Decisions

- **Socket path is parsed, not hardcoded.** The wrapper scans `-chardev` arguments for `id=vfsd` and extracts the `path=` value. This means the same wrapper works for every source block and every concurrent build.
- **`--readonly` flag** makes virtiofsd share the directory read-only without needing bind mounts or overlayfs.
- **`Pdeathsig=SIGTERM`** on both child processes means the kernel sends SIGTERM to them if the wrapper dies for any reason, including SIGKILL (which cannot be caught by signal handlers).
- **Direct child processes** (not `exec`) allow the wrapper to manage both virtiofsd and QEMU lifecycle, forwarding signals and cleaning up.
- **Socket readiness polling** (250ms intervals, 5s timeout) avoids a race condition where QEMU starts before virtiofsd is listening.
- **Pass-through for version/help** queries — Packer calls `qemu_binary -version` before builds start, and the wrapper handles this by exec'ing the real QEMU.

### Signal Handling

The wrapper forwards SIGTERM and SIGINT to QEMU. When QEMU exits, the deferred cleanup:
1. Sends SIGTERM to virtiofsd
2. Waits for virtiofsd to exit
3. Removes the socket file

---

## Integration

### Setting Environment Variables

`run-mvp` exports all required variables:

```bash
export VIRTIOFSD_WRAPPER="${_SCRIPT_DIR}/bin/qemu-virtiofsd"
export VIRTIOFSD_SHARED_DIR="${_SCRIPT_DIR}"
export PACKER_CACHE_DIR="${_SCRIPT_DIR}/.packer_cache"
export HOST_UID="${UID}"
export EPOCHREALTIME
```

### Memory Alignment

The `memory-backend-memfd` size must match the `memory` attribute in the source block. Both are set to `2048` (megabytes). If you override `memory`, you must also override the corresponding `qemuargs` entry.

### Prerequisites

- `virtiofsd` installed on the host (packaged as `virtiofsd` in most distros, or built from the Rust crate)
- Guest kernel with virtiofs support (built-in on RHEL 8+, Ubuntu 20.04+, AlmaLinux 8/9)
- Go compiler (for building the wrapper, handled automatically by `run-mvp`)
