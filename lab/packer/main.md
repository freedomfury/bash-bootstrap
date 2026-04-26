This is the architectural blueprint for the **Ephemeral Infrastructure Testing Framework**. It treats Packer as a high-performance execution engine rather than an image factory, leveraging QEMU's copy-on-write capabilities and `virtiofs` to ensure zero-clutter on the host.

---

# Ephemeral Infrastructure Testing Framework (EITF)

## 1. Executive Summary
The EITF provides a modular environment where virtual machines are treated as transient compute sidecars. Every run starts from a pristine bit-for-bit identical state and terminates by discarding the virtual disk, leaving behind only the test results written to the shared host mount.

## 2. Core Architecture
The system relies on three pillars to achieve high speed and zero-artifact builds:

* **QCOW2 Backing Files:** Uses a read-only base image (Cloud Image). Packer creates a thin delta file for the run, which is deleted upon completion.
* **virtiofs Integration:** Shares the host directory read-only into the guest at `/var/run/shared-vfsd` via a Go wrapper that manages per-build virtiofsd lifecycle. Results written here persist on the host even after the VM is destroyed.
* **Dynamic SSH Keys:** Uses the `sshkey` plugin (`data.sshkey.build`) to generate one-time credentials, injected via Cloud-Init.

---

## 3. Project Directory Structure

```text
.
├── packer.pkr.hcl             # Plugin requirements (sshkey, qemu)
├── variables.pkr.hcl          # Variable schema + sshkey data source
├── sources.pkr.hcl            # Source blocks (almalinux-97, almalinux-810)
├── images.auto.pkrvars.hcl    # Image URL + checksum mappings
├── builder.json               # Input: consumer-provided build definition
├── builder.pkr.tpl            # Jinja template for build block
├── builder.pkr.hcl            # Output: rendered HCL (generated, do not edit)
├── jinja.toml                 # MiniJinja delimiter config (ERB-style)
├── run-mvp                    # Main entry point script
├── bin/
│   ├── qemu-virtiofsd         # Go binary: QEMU wrapper managing virtiofsd lifecycle
│   └── hcl-render             # Bash script: validate + render builder.json -> builder.pkr.hcl
├── src/
│   └── qemu-virtiofsd/
│       └── main.go            # Go source for the QEMU/virtiofsd wrapper
├── macros/
│   └── provisioners.jinja     # Generic provisioner rendering macro
├── schema/
│   ├── builder.schema.json    # JSON Schema for builder.json
│   └── provisoner/            # Per-type provisioner schemas
│       ├── shell.schema.json
│       ├── shell-local.schema.json
│       └── ansible.schema.json
└── .packer_cache/             # Runtime artifacts (gitignored)
```

---

## 4. Component Breakdown

### A. The Hardware Catalog (`sources.pkr.hcl`)
Defines two QEMU source blocks (`almalinux-97`, `almalinux-810`) backed by AlmaLinux cloud images. Each source:
- Uses `use_backing_file = true` so the host disk is never burdened with a full copy
- Points `qemu_binary` at the Go wrapper (`var.virtiofsd_wrapper`)
- Configures virtiofs via `-chardev`/`-vhost-user-fs-pci` with tag `shared-vfsd`
- Configures a serial console via `-chardev`/`-serial`
- Uses Cloud-Init via `cd_content` with CIDATA label to create an admin user

### B. The Build Configuration (`builder.json` + `builder.pkr.tpl`)
Builds are defined via a JSON input file rendered through a Jinja template. The template produces a `build` block with:
- A fixed `initialize` provisioner (waits for cloud-init and verifies the virtiofs mount)
- User-defined provisioners from `builder.json`
- A fixed `cleanup` post-processor that removes the output directory

See [jinja.md](jinja.md) for full details on the template rendering workflow.

### C. The QEMU Wrapper (`bin/qemu-virtiofsd`)
A Go binary that wraps QEMU to manage per-build virtiofsd lifecycle:
1. Parses the virtiofsd socket path from QEMU arguments (`-chardev id=vfsd`)
2. Starts virtiofsd with `--readonly` and `Pdeathsig=SIGTERM`
3. Waits for the socket to appear, then starts the real QEMU binary
4. Forwards signals (SIGTERM, SIGINT) to QEMU
5. Cleans up virtiofsd and the socket on exit

See [virtfs.md](virtfs.md) for the architecture and design decisions.

### D. The "Zero-Artifact" Strategy
The `cleanup` post-processor removes the output directory after each build:
```hcl
post-processor "shell-local" {
  name   = "cleanup"
  inline = [
    "rm -rf ${var.cache_dir}/pk-${source.name}",
  ]
}
```
Test results should be written to the virtiofs mount (`/var/run/shared-vfsd` in the guest, mapped to the project directory on the host) before the VM shuts down.

---

## 5. Workflow Execution

### Run the MVP Build
```bash
./run-mvp
```

### Debug Mode (keep VM running on error)
```bash
./run-mvp --debug
```

### Debug Serial Console
```bash
socat - UNIX-CONNECT:.packer_cache/run/<name>-<port>-serial.sock
```

The `run-mvp` script handles:
1. Building the Go wrapper if missing or stale
2. Creating the packer cache directory
3. Running `packer init`
4. Exporting required environment variables
5. Running `packer build`
6. Verifying success files in `.packer_cache/run/results/`

---

## 6. Key Benefits
1.  **Immutability:** Every test run is guaranteed to start from a clean state.
2.  **Performance:** No full-disk copies; CPU and I/O are dedicated strictly to the workload.
3.  **Cleanliness:** No orphaned `.qcow2` files or "Golden Images" to manage.
4.  **Extensibility:** New images are added to `images.auto.pkrvars.hcl`; new tests are added as provisioners in `builder.json`.
5.  **Template-driven:** Build definitions are validated JSON, rendered through templates, then validated again by Packer.

---
