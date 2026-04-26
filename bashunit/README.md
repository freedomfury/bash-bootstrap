# Bashunit Reference

Extracted documentation from the [bashunit](https://github.com/TypedDevs/bashunit) testing framework. This folder serves as a local reference for writing unit tests in the bash-bootstrap project.

## Purpose

The bash-bootstrap project uses bashunit (vendored at `vendor/bin/dev/bashunit`) for testing. This folder contains the upstream documentation, plus a project-specific cheat sheet, to help AI agents and developers write effective tests.

## Quick Start

```bash
# Build/rebuild the documentation
./build

# Clean extracted documentation
./clean

# View the project-specific cheat sheet
cat output/cheat-sheet.md
```

## What This Does

1. Uses Docker to clone the bashunit repository
2. Extracts all markdown documentation files
3. Generates an index (`output/README.md`) with links to all docs
4. Includes a project-specific `cheat-sheet.md` for this codebase

No Node.js, git, or other dependencies needed on the host - everything runs inside the container.

## Files

| File | Purpose |
|------|---------|
| `Containerfile` | Docker build definition |
| `build` | Script to build/rebuild docs |
| `clean` | Script to remove extracted docs |
| `output/README.md` | Index with links to all documentation |
| `output/cheat-sheet.md` | Project-specific testing guide (start here) |
| `output/*.md` | Extracted bashunit documentation |

## Rebuilding

To update the documentation from upstream:

```bash
cd bashunit
./build
```

## Key References

- **cheat-sheet.md** - Project-specific testing guide (start here)
- **assertions.md** - All available assertion functions
- **test-doubles.md** - Mocks, spies, and call verification
- **common-patterns.md** - Real-world testing examples
- **test-files.md** - Test file structure and lifecycle hooks
