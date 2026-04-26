# Compose Skill

This skill provides tools for managing Podman Compose sessions.

## Setup Requirements

Before using any compose commands, you must set up the monolith environment:

```bash
# First time setup (if vendor doesn't exist)
./mks-vendor

# Set up environment for every session
source exports

# Now you can use compose commands
make help
```

## Available Commands

- `.agent/skills/compose/bin/start` - Start a Podman Compose session
- `.agent/skills/compose/bin/stop` - Stop and destroy a Compose session
- `.agent/skills/compose/bin/exec` - Run a command in an active Compose session

## Common Errors

If you see "mks-bash not found" errors:
1. Run `./mks-vendor` to build the vendor toolkit
2. Run `source exports` to set up the environment
3. Try again

If you see "MKS_ROOT not set" errors:
1. Make sure you've run `source exports` in this terminal session
2. Don't try to run skill scripts directly - use `make` targets instead