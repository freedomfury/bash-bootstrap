# Secrets Management Skill

This skill provides tools for encrypting, decrypting, and managing project secrets using `age` encryption.

## Setup Requirements

Before using any secrets commands, you must set up the monolith environment:

```bash
# First time setup (if vendor doesn't exist)
./mks-vendor

# Set up environment for every session
source exports

# Now you can use secrets commands
make help
```

## Available Commands

- `lib::std::secrets::encrypt` - Encrypt secrets files for commit (public key derived automatically)
- `lib::std::secrets::decrypt` - Decrypt secrets files for use
- `.agent/skills/secrets/bin/audit` - Check who can access encrypted files
- `.agent/skills/secrets/bin/rotate` - Re-encrypt all files with a new key

## Common Errors

If you see "mks-bash not found" errors:
1. Run `./mks-vendor` to build the vendor toolkit
2. Run `source exports` to set up the environment
3. Try again

If you see "MKS_ROOT not set" errors:
1. Make sure you've run `source exports` in this terminal session
2. Don't try to run skill scripts directly - use `make` targets instead