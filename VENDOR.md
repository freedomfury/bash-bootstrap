# Vendor Environment

All project scripts and Makefile targets require the vendor environment to be set up. If you see errors like these, you need to source the `exports` file.

## Common Errors

### Running `make` without exports sourced
```
make: /usr/bin/env mks-bash: No such file or directory
make: *** [inc/common.mk:13: help] Error 127
```

### Running a script without exports sourced
```
bash: ./bin/some-script: cannot execute: required file not found
```

## The Fix

Source the `exports` file before running any project commands:

```bash
source exports
```

Or in one command:
```bash
make help  # Fails
source exports && make help  # Works
```

## What `exports` Provides

When you source `exports`, the following are set:

| Variable | Purpose |
|----------|---------|
| `PATH` | Vendor binaries (`vendor/bin/`) added first |
| `MKS_ROOT` | Absolute path to project root |
| `MKS_TMP` | Temporary directory path |
| `MKS_VENDOR` | Path to vendor binaries |
| `MKS_BASH` | Path to the project's `mks-bash` executable |
| `MKS_EXPORTED` | Flag indicating exports was sourced (`true`) |

## Why This Is Required

- **Scripts use `mks-bash` in shebangs** — Ensures they only run when the correct environment is active
- **Makefile uses `mks-bash` as SHELL** — Asserts the environment is sourced before any make target runs
- **Vendor binaries are statically compiled** — Not installed on the system, only available via `vendor/bin/`

## First-Time Setup

If `vendor.lock` doesn't exist (fresh clone), run:
```bash
./mks-vendor
```

This builds the statically-compiled toolkit. After that, `source exports` will work.

> **For AI Agents:** The vendor build process can take 5-10 minutes, especially on first build or after `./vendor/clean`. When running `./vendor/build` through the Bash tool, either:
> - Run it in the background with `run_in_background: true` and a 10-minute timeout
> - Or inform the user to run it manually in their shell (no timeout applies)
>
> Do not assume the build has failed if it appears to "hang" — it is likely compiling make from source or downloading large binaries.

### Force Rebuild

To force a clean rebuild of the vendor toolkit:
```bash
rm vendor.lock && ./mks-vendor
```
