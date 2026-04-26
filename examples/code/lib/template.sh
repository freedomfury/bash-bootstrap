# shellcheck shell=bash
# Guard: prevent double-sourcing
[[ -n "${_LIB_TEMPLATE_LOADED:-}" ]] && return 0
readonly _LIB_TEMPLATE_LOADED=1

[[ -n "${MKS_ROOT:-}" ]] || { echo 'Fatal: MKS_ROOT is not set!' >&2; exit 3; }

# examples/code/lib/template.sh -- example library template providing Tier 1 function
# ---------------------------------------------------------------------------

# -- example::template::greet: write a greeting to stdout or a variable
#
# Usage:
#   example::template::greet --name <value> [--loud] [--result <var>]
#   example::template::greet -n <value> [-l] [-r <var>]
#
# Options:
#   -n, --name   <value>   Name to greet (required)
#   -l, --loud             Boolean flag; greet in uppercase
#   -v, --verbose          Enable verbose output
#   -r, --result <var>     Name of caller variable to write output into (nameref)
#
# Returns:
#   0  success
#   1  usage error
#
# Example:
#   example::template::greet --name "World" --result out_msg
# --
example::template::greet() {
  local -A opts=(
    [name]=""
    [loud]=0
    [verbose]=0
    [result]=""
  )

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n | --name)     opts[name]="$2";    shift 2 ;;
      -l | --loud)     opts[loud]=1;       shift 1 ;;
      -v | --verbose)  opts[verbose]=1;    shift 1 ;;
      -r | --result)   opts[result]="$2";  shift 2 ;;
      --)              shift; break ;;
      --* | -*)
        printf '%s: unknown option: %s\n' "${FUNCNAME[0]}" "$1" >&2
        return 1
        ;;
      *)
        printf '%s: unexpected argument: %s\n' "${FUNCNAME[0]}" "$1" >&2
        return 1
        ;;
    esac
  done

  # -- Required option validation
  if [[ -z "${opts[name]}" ]]; then
    printf '%s: required option missing: --name\n' "${FUNCNAME[0]}" >&2
    return 1
  fi

  local msg="Hello, ${opts[name]}"
  if (( opts[loud] )); then
    msg="${msg^^}!"
  fi

  # -- Write result via nameref if --result was given
  if [[ -n "${opts[result]}" ]]; then
    local -n _fn_result="${opts[result]}"
    _fn_result="${msg}"
  else
    printf '%s\n' "${msg}"
  fi
}
