# Vendored Binaries

This directory contains statically-linked tools built via `vendor/build` using Podman and the `vendor/Containerfile` definition.

## Quick Start

```bash
# Build the toolkit (run from project root)
./mks-vendor

# Or directly
./vendor/build
```

This creates `vendor.lock` and populates `vendor/bin/` with static binaries.

## What Gets Built

| Binary | Purpose | Source |
|--------|---------|--------|
| `mks-bash` | Symlink to OS-codename-specific bash | `bash-static` from apt |
| `<codename>-bash` | Statically-linked Bash 5.x | Ubuntu apt |
| `make` | GNU Make 4.4.1 | Built from source with musl-gcc |
| `curl` | HTTP client | stunnel/static-curl |
| `trurl` | URL parser | stunnel/static-curl |
| `jq` | JSON processor | jqlang/jq |
| `yq` | YAML/JSON processor | mikefarah/yq |
| `jinja` | Template renderer | mitsuhiko/minijinja-cli |
| `age` | File encryption | FiloSottile/age |

### Dev Tools (`vendor/bin/dev/`)

Auxiliary tools not on PATH by default:

| Binary | Purpose |
|--------|---------|
| `age-keygen` | Generate age key pairs |
| `age-inspect` | Inspect age file headers |
| `age-plugin-batchpass` | Batch passphrase plugin |
| `shellcheck` | Shell script linter |
| `jsonnet` | JSON configuration language |
| `jsonnetfmt` | Jsonnet code formatter |
| `jsonnet-lint` | Jsonnet linter |

## How It Works

1. `vendor/build` runs Podman with `vendor/Containerfile`
2. Containerfile uses `ubuntu:26.04` as build base
3. Downloads/compiles tools statically into `/local/bin/`
4. Final `scratch` stage extracts binaries to `vendor/bin/`
5. `vendor.lock` is created as a sentinel

## OS Codename Naming

The bash binary is named after the Ubuntu codename (`VERSION_CODENAME` from `/etc/os-release`):

- Ubuntu 26.04 → `resolute-bash`
- `mks-bash` symlinks to the codename-specific binary
- `.codename` file stores the codename for reference

## Cleaning Up

```bash
# Remove built binaries (requires rebuilding via ./mks-vendor)
./vendor/clean

# Clean temporary files only (preserves vendor toolkit)
make clean
```

## See Also

- [VENDOR.md](../VENDOR.md) — Troubleshooting vendor environment issues
- [AGENTS.md](../AGENTS.md) — Project conventions and architecture
