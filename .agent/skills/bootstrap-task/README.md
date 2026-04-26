# Bootstrap Task Skill

This skill helps create new tasks in the bootstrap subproject.

## Setup Requirements

Before using any bootstrap task commands, you must set up the monolith environment:

```bash
# First time setup (if vendor doesn't exist)
./mks-vendor

# Set up environment for every session
source exports

# Now you can use bootstrap task commands
make help
```

## Usage

This skill is primarily used by the AI to create new task structures. Users typically interact with it through `make` commands rather than directly.

## Common Errors

If you see "mks-bash not found" errors:
1. Run `./mks-vendor` to build the vendor toolkit
2. Run `source exports` to set up the environment
3. Try again

If you see "MKS_ROOT not set" errors:
1. Make sure you've run `source exports` in this terminal session
2. Don't try to run skill scripts directly - use `make` targets instead