# shellcheck shell=bash
# Guard: prevent double-sourcing
[[ -n "${_LIB_SECRETS_LOADED:-}" ]] && return 0
readonly _LIB_SECRETS_LOADED=1

# shellcheck source=lib/std/logger.sh
source "${MKS_ROOT}/lib/std/logger.sh"
# shellcheck source=lib/std/rmrf.sh
source "${MKS_ROOT}/lib/std/rmrf.sh"

# lib/std/secrets.sh -- stable interface for secrets management
#
# This library provides a high-level API for encryption and decryption,
# abstracting the underlying implementation (currently age).
# ---------------------------------------------------------------------------

# -- lib::std::secrets::encrypt: idempotent encryption
#
# Usage:
#   lib::std::secrets::encrypt --source <path> --target <path> [--identity <path>]
#   lib::std::secrets::encrypt -s <path> -t <path> [-i <path>] [-v]
#
# Options:
#   -s, --source    <path>   Path to plaintext file (required)
#   -t, --target    <path>   Path to encrypted output (required)
#   -i, --identity  <path>   SSH private key (default: ${MKS_AGE_PKEY:-${MKS_TMP}/age/id_rsa})
#   -v, --verbose            Enable verbose output
#
# Returns:
#   0  success (or skipped due to idempotency)
#   1  usage error
#   2  runtime error
# --
lib::std::secrets::encrypt() {
  local -A opts=(
    [source]=""
    [target]=""
    [identity]="${MKS_AGE_PKEY:-${MKS_TMP}/age/id_rsa}"
    [verbose]=0
  )

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s | --source)   opts[source]="$2";   shift 2 ;;
      -t | --target)   opts[target]="$2";   shift 2 ;;
      -i | --identity) opts[identity]="$2"; shift 2 ;;
      -v | --verbose)  opts[verbose]=1;     shift 1 ;;
      --)              shift; break ;;
      --* | -*)
        lib::std::logger -l error -m "unknown option: $1"
        return 1
        ;;
      *)
        lib::std::logger -l error -m "unexpected argument: $1"
        return 1
        ;;
    esac
  done

  # -- Validation
  local missing=0
  for req in source target; do
    if [[ -z "${opts[${req}]}" ]]; then
      lib::std::logger -l error -m "required option missing: --${req//_/-}"
      (( missing++ )) || true
    fi
  done
  (( missing == 0 )) || return 1

  [[ -f "${opts[source]}" ]] || {
    lib::std::logger -l error -m "source file not found: ${opts[source]}"
    return 2
  }

  # -- Key Guardrails
  if [[ ! -f "${opts[identity]}" ]]; then
    lib::std::logger -l error -m "private key not found: ${opts[identity]}"
    return 2
  fi

  local pubkey="${opts[identity]}.pub"
  if [[ ! -f "${pubkey}" ]]; then
    if (( opts[verbose] )); then
      lib::std::logger -l info -m "deriving public key from ${opts[identity]}"
    fi
    ssh-keygen -y -f "${opts[identity]}" > "${pubkey}" || {
      lib::std::logger -l error -m "failed to derive public key"
      return 2
    }
  fi

  # -- Idempotency Check
  # sidecar naming: replace .sec with .sha.age (if present) or just add .sha.age
  local sidecar="${opts[target]%.sec.age}.sha.age"
  [[ "${sidecar}" == "${opts[target]}" ]] && sidecar="${opts[target]}.sha.age"

  local current_source_hash
  current_source_hash="${ sha256sum "${opts[source]}" | awk '{print $1}'; }"

  if [[ -f "${opts[target]}" && -f "${sidecar}" ]]; then
    local recorded_source_hash recorded_target_hash
    IFS=' ' read -r recorded_source_hash recorded_target_hash < "${sidecar}"

    local current_target_hash
    current_target_hash="${ sha256sum "${opts[target]}" | awk '{print $1}'; }"

    if [[ "${current_source_hash}" == "${recorded_source_hash}" && \
          "${current_target_hash}" == "${recorded_target_hash}" ]]; then
      if (( opts[verbose] )); then
        lib::std::logger -l info -m "skipped (idempotent): ${opts[target]}"
      fi
      return 0
    fi
  fi

  # -- Encrypt (Age Implementation)
  if (( opts[verbose] )); then
    lib::std::logger -l info -m "encrypting ${opts[source]} -> ${opts[target]}"
  fi

  local _encrypt_failed=0
  age --encrypt --armor \
    --recipient "$(<"${pubkey}")" \
    --output "${opts[target]}" \
    "${opts[source]}" || _encrypt_failed=$?

  if (( _encrypt_failed != 0 )); then
    lib::std::logger -l error -m "encryption failed"
    # Remove stale sidecar to prevent hash mismatch on next run
    lib::std::rmrf::file "${sidecar}"
    return 2
  fi

  # -- Update Sidecar
  local new_target_hash
  new_target_hash="$(sha256sum "${opts[target]}" | awk '{print $1}')"
  printf '%s %s\n' "${current_source_hash}" "${new_target_hash}" > "${sidecar}"
}

# -- lib::std::secrets::decrypt: stable decryption interface
#
# Usage:
#   lib::std::secrets::decrypt --source <path> [--target <path>] [--identity <path>] [--result <var>]
#   lib::std::secrets::decrypt -s <path> [-t <path>] [-i <path>] [-r <var>] [-v]
#
# Options:
#   -s, --source    <path>   Path to encrypted file (required)
#   -t, --target    <path>   Path to decrypted output (if omitted, prints to stdout)
#   -i, --identity  <path>   SSH private key (default: ${MKS_AGE_PKEY:-${MKS_TMP}/age/id_rsa})
#   -r, --result    <var>    Nameref to capture output in-memory
#   -v, --verbose            Enable verbose output
#
# Returns:
#   0  success
#   1  usage error
#   2  runtime error
# --
lib::std::secrets::decrypt() {
  local -A opts=(
    [source]=""
    [target]=""
    [identity]="${MKS_AGE_PKEY:-${MKS_TMP}/age/id_rsa}"
    [result]=""
    [verbose]=0
  )

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s | --source)   opts[source]="$2";   shift 2 ;;
      -t | --target)   opts[target]="$2";   shift 2 ;;
      -i | --identity) opts[identity]="$2"; shift 2 ;;
      -r | --result)   opts[result]="$2";   shift 2 ;;
      -v | --verbose)  opts[verbose]=1;     shift 1 ;;
      --)              shift; break ;;
      --* | -*)
        lib::std::logger -l error -m "unknown option: $1"
        return 1
        ;;
      *)
        lib::std::logger -l error -m "unexpected argument: $1"
        return 1
        ;;
    esac
  done

  # -- Validation
  if [[ -z "${opts[source]}" ]]; then
    lib::std::logger -l error -m "required option missing: --source"
    return 1
  fi

  [[ -f "${opts[source]}" ]] || {
    lib::std::logger -l error -m "source file not found: ${opts[source]}"
    return 2
  }

  if [[ ! -f "${opts[identity]}" ]]; then
    lib::std::logger -l error -m "private key not found: ${opts[identity]}"
    return 2
  fi

  # -- Decrypt (Age Implementation)
  if (( opts[verbose] )); then
    lib::std::logger -l info -m "decrypting ${opts[source]}"
  fi

  if [[ -n "${opts[result]}" ]]; then
    local -n _fn_result="${opts[result]}"
    _fn_result="${ age --decrypt --identity "${opts[identity]}" "${opts[source]}"; }" || {
      lib::std::logger -l error -m "decryption failed"
      return 2
    }
  elif [[ -n "${opts[target]}" ]]; then
    age --decrypt --identity "${opts[identity]}" \
      --output "${opts[target]}" "${opts[source]}" || {
        lib::std::logger -l error -m "decryption failed"
        return 2
      }
  else
    age --decrypt --identity "${opts[identity]}" "${opts[source]}" || {
      lib::std::logger -l error -m "decryption failed"
      return 2
    }
  fi

  if (( opts[verbose] )); then
    lib::std::logger -l info -m "decryption complete"
  fi
}
