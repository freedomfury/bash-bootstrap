# Sandbox Skill

This skill provides tools for running commands in isolated Podman containers.

## Setup Requirements

Before using any sandbox commands, you must set up the monolith environment:

```bash
# First time setup (if vendor doesn't exist)
./mks-vendor

# Set up environment for every session
source exports

# Now you can use sandbox commands
make help
```

## Available Commands

- `.agent/skills/sandbox/bin/detect-image` - Find the best OCI image for your OS
- `.agent/skills/sandbox/bin/run-podman` - Run a command in a sandboxed container

## Common Errors

If you see "mks-bash not found" errors:
1. Run `./mks-vendor` to build the vendor toolkit
2. Run `source exports` to set up the environment
3. Try again

If you see "MKS_ROOT not set" errors:
1. Make sure you've run `source exports` in this terminal session
2. Don't try to run skill scripts directly - use `make` targets instead