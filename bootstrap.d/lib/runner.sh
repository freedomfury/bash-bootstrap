# shellcheck shell=bash
# bootstrap.d/lib/runner.sh -- Phase runner: executes a lifecycle phase and
# records its stdout, stderr, and exit code to the scoreboard tree.
#
# Requires:
#   BSS_TMP -- subproject temp root, provided by bootstrap.d/exports

[[ -n "${_LIB_RUNNER_LOADED:-}" ]] && return 0
readonly _LIB_RUNNER_LOADED=1

# -- bss::lib::runner: run one lifecycle phase and record its stdout/stderr/rc
#
# Usage:
#   bss::lib::runner --task <name> --func <phase>
#   bss::lib::runner -t <name> -f <phase>
#
# Options:
#   -t, --task  <name>   Task name (e.g. ntp, sshd) — used for score path and function dispatch
#   -f, --func  <phase>  Lifecycle phase to run (initialize, install, configure, execute)
#
# Returns:
#   0  phase succeeded
#   N  exit code of the phase function
# --
# shellcheck disable=SC2154  # BSS_TMP sourced transitively via defaults.sh
bss::lib::runner() {
  local -A opts=(
    [task]=""
    [func]=""
  )

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t | --task)  opts[task]="$2"; shift 2 ;;
      -f | --func)  opts[func]="$2"; shift 2 ;;
      --)           shift; break ;;
      --* | -*)
        lib::std::logger -l error -m "${FUNCNAME[0]}: unknown option: $1"
        return 1
        ;;
      *)
        lib::std::logger -l error -m "${FUNCNAME[0]}: unexpected argument: $1"
        return 1
        ;;
    esac
  done

  local missing=0
  for req in task func; do
    if [[ -z "${opts[${req}]}" ]]; then
      lib::std::logger -l error -m "${FUNCNAME[0]}: required option missing: --${req}"
      (( missing++ )) || true
    fi
  done
  (( missing == 0 )) || return 1

  local _score_dir="${BSS_TMP}/scores/${opts[task]}/${opts[func]}"
  mkdir -p "${_score_dir}"

  local _rc=0
  "tasks::${opts[task]}::${opts[func]}" \
    1> >(tee "${_score_dir}/stdout" || true) \
    2> >(tee "${_score_dir}/stderr" >&2 || true) || _rc=$?

  printf '%d\n' "${_rc}" > "${_score_dir}/rc"
  return "${_rc}"
}
