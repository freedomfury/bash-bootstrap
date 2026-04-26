# Packer QEMU Builder — Quick Reference

> Condensed from [HashiCorp QEMU Builder Docs](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu).
> For full details, consult the upstream documentation.

---

## Fields Used in This Project

### Required

| Field | Type | Description |
|-------|------|-------------|
| `iso_url` | string | URL to the cloud image (QCOW2) |
| `iso_checksum` | string | Checksum for the image (supports `file:<url>` prefix) |

### VM Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cpus` | int | 1 | Number of virtual CPUs |
| `memory` | int | 512 | Memory in MB |
| `format` | string | `"qcow2"` | Output format (`qcow2` or `raw`) |
| `accelerator` | string | auto | `none`, `kvm`, `tcg`, `hax`, `hvf`, `whpx`, or `xen` |
| `headless` | bool | false | Run without a GUI console |

### Disk Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `disk_image` | bool | false | Treat `iso_url` as a bootable QEMU image (not an ISO) |
| `use_backing_file` | bool | false | Create a QCOW2 delta file using the source as a backing file |
| `disk_size` | string | `"40960M"` | Disk size (suffix: K, M, G, T) |
| `skip_compaction` | bool | false | Skip `qemu-img convert` compaction (auto-set to true when `use_backing_file = true`) |

### QEMU Binary & Arguments

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `qemu_binary` | string | `qemu-system-x86_64` | Path to the QEMU binary (or wrapper) |
| `qemuargs` | [][]string | — | Raw QEMU command-line arguments |

### `qemuargs` Template Variables

Available inside `qemuargs` values:

| Variable | Description |
|----------|-------------|
| `{{ .Name }}` | Build source name |
| `{{ .SSHHostPort }}` | Host port forwarded to guest SSH |
| `{{ .HTTPIP }}` | HTTP server IP (if `http_directory` set) |
| `{{ .HTTPPort }}` | HTTP server port |
| `{{ .OutputDir }}` | Output directory path |

### Cloud-Init / CD Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cd_files` | []string | — | Files to place on attached CD |
| `cd_content` | map[string]string | — | Key/value content to place on CD |
| `cd_label` | string | — | CD volume label (e.g. `"cidata"`) |

### Communicator (SSH)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `communicator` | string | `"ssh"` | `none`, `ssh`, or `winrm` |
| `ssh_username` | string | — | SSH login username (required) |
| `ssh_private_key_file` | string | — | Path to PEM private key |
| `ssh_timeout` | duration | `"5m"` | Time to wait for SSH availability |
| `ssh_password` | string | — | Plaintext password (alternative to key) |

### Shutdown

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `shutdown_command` | string | — | Command to gracefully shut down the guest |
| `shutdown_timeout` | duration | `"5m"` | Time to wait after shutdown command |

---

## Key Template Engine (qemuargs)

`qemuargs` entries can use Go template syntax. Packer evaluates these at build
time, not at HCL parse time. This is how per-build unique values (socket paths,
serial consoles, network ports) flow from Packer into QEMU arguments:

```hcl
qemuargs = [
  ["-chardev", "socket,id=vfsd,path=${local.vfsd_sock}"],
  ["-netdev", "user,hostfwd=tcp::{{ .SSHHostPort }}-:22,id=forward"],
]
```

- `${...}` — HCL interpolation (evaluated by Packer at parse time)
- `{{ .Name }}` — Go template variables (evaluated per-build)

---

## EFI Boot (not currently used)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `efi_boot` | bool | false | Boot in EFI mode |
| `efi_firmware_code` | string | `/usr/share/OVMF/OVMF_CODE.fd` | OVMF code file |
| `efi_firmware_vars` | string | `/usr/share/OVMF/OVMF_VARS.fd` | OVMF vars file |

Note: Secure Boot requires `machine_type` to be a q35 derivative.

---

## Notable Behavior

- **Backing file + skip_compaction**: When `use_backing_file = true`, Packer auto-sets `skip_compaction = true` since converting would defeat the backing file's purpose.
- **qemu_binary version detection**: Packer calls `qemu_binary -version` before builds. Custom wrappers must handle this (the Go wrapper does via pass-through to the real QEMU).
- **Parallel builds**: Each build gets its own `{{ .SSHHostPort }}`, making parallel builds safe when using qemuargs for network config.
