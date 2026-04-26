# shellcheck shell=bash
# Guard: prevent double-sourcing
[[ -n "${_LIB_RMRF_LOADED:-}" ]] && return 0
readonly _LIB_RMRF_LOADED=1

# shellcheck source=lib/std/logger.sh
source "${MKS_ROOT}/lib/std/logger.sh"

# lib/std/rmrf.sh -- safe file deletion with guards
#
# This library provides guarded deletion primitives to prevent catastrophic
# data loss from rm -rf on empty, unset, or maliciously-set path variables.
# ---------------------------------------------------------------------------

# -- lib::std::rmrf::file: safe single file deletion
#
# Usage:
#   lib::std::rmrf::file <path>
#   lib::std::rmrf::file --verbose <path>
#
# Deletes a single file with null guard. Does NOT use -rf (recursive).
# Use lib::std::rmrf::dir for directories.
#
# Options:
#   -v, --verbose    Log the deletion
#
# Returns:
#   0  success (or skipped if path empty)
#   1  path is a protected system path
#   2  deletion failed
# --
lib::std::rmrf::file() {
  local verbose=0
  [[ "$1" == "-v" || "$1" == "--verbose" ]] && { verbose=1; shift; }

  local path="${1:-}"

  # Null guard: empty/unset returns success (nothing to delete)
  [[ -z "${path}" ]] && return 0

  # Reject absolute paths that are system-critical
  case "${path}" in
    /|/etc|/usr|/bin|/sbin|/lib|/home|/root|/var)
      lib::std::logger -l error -m "refusing to delete system path: ${path}"
      return 1
      ;;
    /etc/*|/usr/bin/*|/usr/sbin/*|/bin/*|/sbin/*|/lib/*|/home/*|/root/*)
      lib::std::logger -l error -m "refusing to delete system path: ${path}"
      return 1
      ;;
  esac

  (( verbose )) && lib::std::logger -l info -m "deleting file: ${path}"

  rm -f "${path:-_NULL_}" || {
    lib::std::logger -l error -m "failed to delete: ${path}"
    return 2
  }
}

# -- lib::std::rmrf::dir: safe recursive directory deletion
#
# Usage:
#   lib::std::rmrf::dir <path>
#   lib::std::rmrf::dir --verbose <path>
#
# Deletes a directory recursively with strict path validation.
# THIS IS THE DANGEROUS ONE — all paths are validated.
#
# Options:
#   -v, --verbose    Log the deletion
#
# Returns:
#   0  success (or skipped if path empty)
#   1  path is a protected system path
#   2  deletion failed
# --
lib::std::rmrf::dir() {
  local verbose=0
  [[ "$1" == "-v" || "$1" == "--verbose" ]] && { verbose=1; shift; }

  local path="${1:-}"

  # Null guard: empty/unset returns success (nothing to delete)
  [[ -z "${path}" ]] && return 0

  # Reject root — this is the catastrophic case
  [[ "${path}" == "/" ]] && {
    lib::std::logger -l error -m "refusing to delete root (/)"
    return 1
  }

  # Reject system-critical paths and their subdirectories
  case "${path}" in
    /etc|/usr|/bin|/sbin|/lib|/home|/root|/var|/boot|/opt|/sys|/proc|/dev)
      lib::std::logger -l error -m "refusing to delete system path: ${path}"
      return 1
      ;;
    /etc/*|/usr/*|/bin/*|/sbin/*|/lib/*|/home/*|/root/*|/boot/*|/sys/*|/proc/*|/dev/*)
      lib::std::logger -l error -m "refusing to delete system path: ${path}"
      return 1
      ;;
  esac

  # Warn if path contains parent directory traversal
  if [[ "${path}" == *".."* ]]; then
    lib::std::logger -l warn -m "path contains '..': ${path}"
  fi

  (( verbose )) && lib::std::logger -l info -m "deleting directory: ${path}"

  rm -rf "${path:-_NULL_}" || {
    lib::std::logger -l error -m "failed to delete directory: ${path}"
    return 2
  }
}
