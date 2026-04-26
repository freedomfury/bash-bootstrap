# shellcheck shell=bash
# Guard: prevent double-sourcing
[[ -n "${_LIB_LOGGER_LOADED:-}" ]] && return 0
readonly _LIB_LOGGER_LOADED=1

[[ -n "${MKS_ROOT:-}" ]] || { echo 'Fatal: MKS_ROOT is not set!' >&2; exit 3; }

# lib/std/logger.sh -- structured logging with levels and timestamps
#
# Usage:
#   lib::std::logger -l <debug|info|warn|error> -m <text>
#
# Options:
#   -l, --level    <level>   Log level: debug, info, warn, error (default: info)
#   -m, --message  <text>    Message to log (required)
# ---------------------------------------------------------------------------

lib::std::logger() {
    local -A opts=([level]="info" [message]="")

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -l | --level)
            opts[level]="${2,,}"
            shift 2
            ;;
        -m | --message)
            opts[message]="$2"
            shift 2
            ;;
        *)
            printf 'lib::std::logger: unknown option: %s\n' "$1" >&2
            return 1
            ;;
        esac
    done

    local ts
    printf -v ts '%(%Y-%m-%dT%H:%M:%S)T' "${EPOCHSECONDS}"

    local level_upper="${opts[level]^^}"

    case "${opts[level]}" in
    debug|info|warn|error) ;;
    *) level_upper="INFO" ;;
    esac

    local caller="${FUNCNAME[1]:-${BASH_SOURCE[1]##*/}}"
    local line="${BASH_LINENO[0]}"

    printf '[%s] %-5s %s:%s %s\n' \
      "${ts}" "${level_upper}" "${caller}" "${line}" "${opts[message]}" >&2
}
