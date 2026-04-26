# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- `mks-vendor` entry point script for vendor toolkit setup
- `VENDOR.md` documentation for vendor environment troubleshooting
- `MKS_BASH` environment variable pointing to `mks-bash` binary
- OS-codename-specific bash binary (e.g., `questing-bash`) with `mks-bash` symlink

### Changed
- `exports` converted from generated to static file
- Makefile now uses `mks-bash` as shell (via `inc/common.mk`)
- Only `vendor/build` and `vendor/clean` remain POSIX `/bin/sh` — all other scripts use `mks-bash`

### Removed
- Makefile `exports` generation target (exports is now static)
