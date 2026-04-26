# shellcheck shell=bash
# Guard: prevent double-sourcing
[[ -n "${_LIB_DEFAULTS_LOADED:-}" ]] && return 0
readonly _LIB_DEFAULTS_LOADED=1

[[ -n "${MKS_ROOT:-}" ]] || {
    echo 'Fatal: MKS_ROOT is not set!' >&2
    exit 3
}
[[ -n "${BSS_ROOT:-}" ]] || {
    echo 'Fatal: BSS_ROOT is not set!' >&2
    exit 3
}

# shellcheck source=/dev/null
source "${MKS_ROOT}/bootstrap.d/exports"
source "${MKS_ROOT}/lib/std/logger.sh"

# -- Source subproject globals
# shellcheck source=/dev/null  # .env file, not a shell script
source "${BSS_ROOT}/vars/globals.env"
