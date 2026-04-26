# Tools

Helper executables under `bin/` that support the Packer/QEMU workflow.

---

## `bin/qemu-virtiofsd`

A Go binary (compiled from `src/qemu-virtiofsd/main.go`) that wraps QEMU to
manage per-build virtiofsd lifecycle. Used via Packer's `qemu_binary` attribute
in source blocks.

### How It Works

1. Parses the virtiofsd socket path from QEMU arguments (`-chardev id=vfsd`)
2. Starts `virtiofsd` with `--readonly` as a direct child process
3. Polls for the socket to appear (250ms intervals, 5s timeout)
4. Starts the real QEMU binary with all original arguments
5. Forwards SIGTERM and SIGINT to QEMU
6. Cleans up virtiofsd and the socket on exit

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `VIRTIOFSD_SHARED_DIR` | Yes | — | Host directory to expose read-only |
| `VIRTIOFSD_BIN` | No | `/usr/libexec/virtiofsd` | Path to virtiofsd binary |
| `QEMU_BIN` | No | `/usr/bin/qemu-system-x86_64` | Path to real QEMU binary |

### Building

`run-mvp` builds the wrapper automatically if the binary is missing or if
`src/qemu-virtiofsd/main.go` is newer than the existing binary:

```bash
(cd src/qemu-virtiofsd && go build -o ../../bin/qemu-virtiofsd .)
```

To rebuild manually:

```bash
cd lab/packer/src/qemu-virtiofsd && go build -o ../../bin/qemu-virtiofsd .
```

See [virtfs.md](virtfs.md) for full architecture details.

---

## `bin/hcl-render`

A Bash script that validates a JSON data file against its schema and renders it
to HCL via the Jinja template system.

### Usage

```
hcl-render --input <file> --template <file> --output <file> \
           [--schema <file>] [--config <file>] [--fmt] [--force]
hcl-render -i <file> -t <file> -o <file> \
           [-s <file>] [-c <file>] [-f] [-F]
```

### Options

| Option | Description |
|--------|-------------|
| `-i, --input <file>` | JSON data file to render (required) |
| `-t, --template <file>` | Jinja template file (required) |
| `-o, --output <file>` | Output HCL file path (required) |
| `-s, --schema <file>` | JSON schema for validation (default: `schema/builder.schema.json` relative to template dir) |
| `-c, --config <file>` | Jinja config file (default: `jinja.toml` relative to template dir) |
| `-f, --fmt` | Run `packer fmt` on the output directory after rendering |
| `-F, --force` | Overwrite output file if it already exists |
| `-h, --help` | Show usage and exit |

### Example

```bash
source exports && lab/packer/bin/hcl-render \
    -i lab/packer/builder.json \
    -t lab/packer/builder.pkr.tpl \
    -o lab/packer/builder.pkr.hcl --force
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Usage error |
| 2 | Validation or render failure |
| 3 | Environment error (MKS_ROOT not set) |

See [jinja.md](jinja.md) for details on the template rendering workflow.

---

## Checking for Orphaned Processes

After a crash, `^C`, or failed run, virtiofsd or QEMU processes may linger.

**1. Check for orphaned virtiofsd processes**
```bash
pgrep -a virtiofsd || echo "(no processes)"
```

**2. Check for orphaned QEMU processes**
```bash
pgrep -a qemu-system || echo "(no processes)"
```

**3. Clean up orphaned processes**
```bash
pkill -f virtiofsd 2>/dev/null || true
pkill -f qemu-system-x86_64 2>/dev/null || true
```

**4. Clean up stale socket files**
```bash
rm -f lab/packer/.packer_cache/run/*.sock
```
