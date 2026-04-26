# bash-bootstrap

A monolithic Bash project containing multiple independent subprojects, orchestrated via `make`.

## Quick Start

```bash
# Build vendored toolkit (one-time setup)
./mks-vendor

# Run available tasks
make help        # List all targets
make <target>    # Run a specific target
```

## Structure

- `Makefile` — Primary orchestrator; delegates to subprojects
- `<name>.d/` — Subproject directories (contain their own `README.md`)
- `vendor/bin/` — Statically-compiled tools (no system deps)
- `bashunit/` — Reference documentation for the bashunit testing framework
- `lib/` — Shared libraries
- `docs/` — Detailed documentation

## Documentation

| File | Purpose |
|------|---------|
| [AGENTS.md](AGENTS.md) | Project conventions, structure, and rules |
| [docs/bash-conv.md](docs/bash-conv.md) | Bash coding standards |
| [VENDOR.md](VENDOR.md) | Troubleshooting vendor toolkit |
| [bashunit/output/cheat-sheet.md](bashunit/output/cheat-sheet.md) | Bashunit testing framework reference |
| Subproject `README.md` | Subproject-specific details |
