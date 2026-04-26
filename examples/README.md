# Code Examples

This directory contains example scripts demonstrating the project's coding standards and patterns.

## Setup Requirements

Before using any example scripts, you must set up the monolith environment:

```bash
# First time setup (if vendor doesn't exist)
./mks-vendor

# Set up environment for every session
source exports

# Now you can use example scripts
cd examples/code/bin
./template --help
```

## Directory Structure

```
examples/
├── README.md          <- This file
└── code/
    ├── bin/          <- Example executable scripts
    │   ├── template   <- Bash executable template (uses mks-bash)
    │   └── basic-sh  <- POSIX bootstrapper template (uses /bin/sh)
    └── lib/          <- Example library files
        └── template.sh  <- Library template (sourced, not executed)
```

## Example Scripts

### `bin/template` - Bash Executable Template
- **Purpose**: Shows the standard 9-line preamble structure
- **Requirements**: Needs `mks-bash` environment
- **Usage**: `./template --input <file> [options]`

### `bin/basic-sh` - POSIX Bootstrapper Template
- **Purpose**: Shows minimal POSIX shell for bootstrapping
- **Requirements**: Works with `/bin/sh` only
- **Usage**: `./basic-sh`

## Common Errors

If you see "mks-bash not found" errors:
1. Run `./mks-vendor` to build the vendor toolkit
2. Run `source exports` to set up the environment
3. Try again

If you see "MKS_ROOT not set" errors:
1. Make sure you've run `source exports` in this terminal session
2. Don't try to run example scripts directly without the environment