# Bash Coding Conventions

> **Note:** This document contains bash-specific coding standards. When writing or modifying bash code in this project, refer to this document for function templates, idioms, and patterns.

For project-specific information (structure, paths, subprojects), see [AGENTS.md](../AGENTS.md).

---

## 1. Shell Target

- **Minimum version**: Bash 5.3+ (via `vendor/bin/mks-bash`)
- **Secondary target**: POSIX `/bin/sh` (strictly for `vendor/build` and `vendor/clean` only)
- **Shebang**: Always `#!/usr/bin/env mks-bash` (use `#!/bin/sh` for POSIX bootstrappers)
- **Version guard**: The shebang `#!/usr/bin/env mks-bash` ensures the correct Bash version is used.

---

## 2. Strict Mode — Always On

Every entry-point script begins with:

```bash
set -euo pipefail
shopt -s inherit_errexit
IFS=$'\n\t'
```

- `-e` — exit on any error
- `-u` — treat unset variables as errors
- `-o pipefail` — pipeline fails if any stage fails
- `inherit_errexit` — command substitutions inherit `set -e` (critical for the
  remaining `$()` isolation cases)
- `IFS=$'\n\t'` — prevent word-splitting on spaces

Sourced libraries (`lib/*.sh`) **do not** repeat `set -euo pipefail` — they
inherit strict mode from the entry-point script that sources them. Their only
preamble is the source guard (see Section 9).

---

## 3. Google Shell Style Guide Compliance

This project follows the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
with the extensions and overrides defined in this document taking precedence.

### Key Google rules enforced here:

- **Executables** never have a `.sh` extension — this applies to every
  directly-invoked script without exception, including `bin/` tools,
  `install`, `scripts/lint`, `scripts/run-tests`, and any other file
  a user or process calls directly. The `.sh` extension is reserved
  exclusively for sourced library files in `lib/`. POSIX bootstrapping scripts
  in `vendor/` are also exempt from `.sh` extensions but must use `#!/bin/sh`.
- **Indentation**: 2 spaces, no tabs
- **Line length**: 80 characters max; continuation with `\` aligned
- **Semicolons**: Never at end of line; `do`/`then` on same line as `for`/`if`
- **Variable expansion**: Always quote: `"${var}"` not `$var`
- **Command substitution**: Always `${ ; }` or `$(...)`, never backticks
- **`[[`** for all conditionals, never `[`
- **`(( ))`** for all arithmetic, never `$[ ]` or `expr` or `let`
- **`printf`** instead of `echo` for any output with variables or escapes. For static literal strings with no escapes or variables, `echo 'string'` is acceptable, but `printf '%s\n' 'string'` is preferred for consistency.
- **`readonly`** and **`local`** used explicitly and consistently
- **Errors** always go to stderr: `printf '...\n' >&2`
- **`main()`** function required in all executable scripts (except POSIX
  bootstrapping scripts where linear execution is preferred)
- **`main`** called only via `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`
  (Bash 5.3+ scripts only)
- **Function declaration**: Always `name() {`, never `function name() {`
- **`declare` vs `local`**: Inside functions, always use `local`. Use `declare`
  only at file scope. Never use `declare -g` inside functions — use namerefs.
- **`::` namespacing**: Used for library functions in `lib/std/`. Convention:
  `lib::std::<function_name>`. Functions outside `lib/std/` remain un-namespaced,
  scoped by their file name.

---

## 3.1 Script Name — `_SELF` Variable

All executable scripts must derive their own name for use in error messages and logging.

### Bash Scripts (Type 2)

```bash
readonly _SELF="${0##*/}"
```

Place this declaration after the strict mode block and before any other code.

### POSIX Scripts (Type 1)

```bash
_SELF="${0##*/}"
```

POSIX scripts cannot use `readonly` (not POSIX-compliant). Omit the `readonly` keyword.

---



## 4. Function Specification — The Core Convention

### 4.1 Function Tiers

Functions fall into one of three tiers based on visibility and complexity.
The tier determines whether the full mini-program pattern is required.

#### Tier 1 — Public Library Functions

Any function in `lib/` or called from more than one script.
**Always** uses the full `--long-form` mini-program pattern. No exceptions.

- Both short (`-x`) and long (`--flag`) forms for **every** option
- Full argument parser with `while [[ $# -gt 0 ]]; do case "$1" in` structure
- `local -A opts` for all parsed values
- Required option validation with error messages
- `--verbose` / `-v` and `--result` / `-r` support
- Full header comment block with usage (showing both forms), options, returns, and example

#### Tier 2 — Task-Level Functions

Called from multiple places within the same script but not exported to `lib/`.
Use the full pattern if the function has **3 or more options**.
Positional arguments are acceptable if the function has **1 or 2 arguments**
and the function name makes the meaning unambiguous without flag names.

```bash
# Acceptable as positional — 2 args, meaning is obvious from name
_check_file_exists() {
  local path="$1"
  local desc="${2:-file}"
  [[ -f "${path}" ]] || {
    printf '%s: %s not found: %s\n' "${FUNCNAME[0]}" "${desc}" "${path}" >&2
    return 4
  }
}
```

#### Tier 3 — Private Internal Helpers

Prefixed with `_`, called from exactly one place, purely mechanical operations
(string formatting, single condition checks, trivial transformations).
Positional arguments are acceptable. Must be documented as positional-only
in the header comment. Must not be called outside the file they are defined in.

```bash
# _join_by -- internal helper, positional only
# Usage: _join_by <delimiter> <element> [<element>...]
# INTERNAL: do not call outside this file
_join_by() {
  local delim="$1"; shift
  local first="$1"; shift
  printf '%s' "${first}${@/#/${delim}}"
}
```

The `_` prefix is the signal to Claude and other developers that this function
is positional-only and internal. Never promote a Tier 3 function to a wider
call site without converting it to the full Tier 1 pattern first.

#### Decision Rule

```
Is this function in lib/ or called from more than one script?
  Yes → Tier 1, full --long-form pattern always

Does it have 3 or more options?
  Yes → Tier 1 or Tier 2 full pattern

Is it called from exactly one place, purely mechanical, prefixed _?
  Yes → Tier 3, positional acceptable

When in doubt → use the full pattern. It costs little and pays off later.
```

### 4.2 Canonical Function Template

```bash
# -- function_name: one-line description of what this function does
#
# Usage:
#   function_name --param-one <value> --param-two <value> [--flag] [--result <var>]
#   function_name -p <value> -P <value> [-f] [-r <var>]
#
# Options:
#   -p, --param-one  <value>   Description of param-one (required)
#   -P, --param-two  <value>   Description of param-two (required)
#   -f, --flag                 Boolean flag; presence means true
#   -v, --verbose              Enable verbose output
#   -r, --result     <var>     Name of caller variable to write output into (nameref)
#
# Returns:
#   0  success
#   1  usage error
#   2  runtime error
#
# Example:
#   function_name --param-one "hello" --param-two "world" --result output_var
# --
function_name() {
  # -- Option defaults
  local -A opts=(
    [param_one]=""
    [param_two]=""
    [flag]=0
    [verbose]=0
    [result]=""
  )

  # -- Argument parsing
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p | --param-one)  opts[param_one]="$2";  shift 2 ;;
      -P | --param-two)  opts[param_two]="$2";  shift 2 ;;
      -f | --flag)       opts[flag]=1;           shift 1 ;;
      -v | --verbose)    opts[verbose]=1;        shift 1 ;;
      -r | --result)     opts[result]="$2";      shift 2 ;;
      --)                shift; break ;;
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
  local missing=0
  for req in param_one param_two; do
    if [[ -z "${opts[${req}]}" ]]; then
      printf '%s: required option missing: --%s\n' \
        "${FUNCNAME[0]}" "${req//_/-}" >&2
      (( missing++ )) || true
    fi
  done
  (( missing == 0 )) || return 1

  # -- Verbose: dump all parsed opts (Bash 5.1+ ${@K} expansion)
  if (( opts[verbose] )); then
    printf '%s: opts: %s\n' "${FUNCNAME[0]}" "${opts[*]@K}" >&2
  fi

  # -- Work
  local output="result: ${opts[param_one]} + ${opts[param_two]}"

  # -- Write result via nameref if --result was given
  if [[ -n "${opts[result]}" ]]; then
    local -n _fn_result="${opts[result]}"
    _fn_result="${output}"
  else
    printf '%s\n' "${output}"
  fi

  return 0
}
```

### 4.3 Naming Conventions

| Thing | Convention | Example |
|---|---|---|
| Functions | `snake_case` | `parse_config` |
| Long switches | `--kebab-case` | `--output-dir` |
| Short switches | `-x` single letter, paired with every long switch | `-p`, `-v`, `-f` |
| Local variables (regular) | `snake_case`, no `_` prefix | `output`, `count`, `ts` |
| Local variables (`local -n` namerefs only) | `_snake_case`, `_` prefix prevents shadowing | `local -n _fn_result` |
| Constants / globals | `UPPER_SNAKE_CASE` | `MAX_RETRIES` |
| Script-internal globals | `_UPPER_SNAKE_CASE` | `_EXTRACT`, `_TARGET` |
| External env variables | `UPPER_SNAKE_CASE` (no prefix) | `GITHUB_TOKEN` |
| Built-in Bash variables | `UPPER_SNAKE_CASE` (no prefix, as-is) | `BASH_VERSINFO`, `EPOCHSECONDS` |
| `opts` array keys | `snake_case` (map from `--kebab-case`) | `opts[output_dir]` |

Switch-to-key mapping rule: replace `-` with `_` in the opts array key.
`--output-dir` → `opts[output_dir]`

#### Environment Variable Files: `exports` vs `.env`

Both `exports` and `.env` files are **Bash 5.3+ compatible** and may use the same features (arrays, `declare`, etc.). The distinction is **semantic**, not technical:

| Aspect | `exports` Files | `.env` Files |
|--------|----------------|--------------|
| **Purpose** | Mandatory environment definition | Situational data and configuration |
| **When sourced** | Always, at project/subproject root | Conditionally, as needed |
| **Location** | Root: `exports`<br>Subproject: `<subproject>/exports` | `vars/*.env`, `tmp/cache/facts/*.env`, etc. |
| **Examples** | `exports` (root), `bootstrap.d/exports` | `vars/globals.env`, `vars/secrets.env.sec`, `tmp/cache/facts/*.env` |

- **`exports`**: Defines the core environment for a project or subproject. Always sourced first before any other code. These establish the foundation (`MKS_ROOT`, `BSS_ROOT`, etc.) and are checked into version control.
- **`.env`**: Contains data or configuration that may or may not be loaded depending on context. Facts files, task-specific configuration, secrets — anything that's conditionally sourced.

> [!NOTE]
> This rule does **not** apply to **Bash Libraries** (`.sh`). Functional scripts that include other libraries or perform logic—even simple "stub" or inclusion libraries like `bootstrap.d/lib/defaults.sh`—must retain the `.sh` extension and follow all Type 3 Bash Library rules.

#### Global variable prefix rule

Bash has no namespacing. Use the `_` prefix to signal that a global is
**set and owned by this script** and is not expected to arrive from the
environment (e.g. a sourced `.env` file or an exported shell variable).

```
Is this variable set from outside the script (e.g. .env, export, CI)?
  Yes → UPPER_SNAKE_CASE          e.g. GITHUB_TOKEN, HOME, CI
  No  → _UPPER_SNAKE_CASE         e.g. _EXTRACT, _TARGET, _SELF_ROOT
```

This applies even when the variable is `readonly` — the prefix is about
origin and ownership, not mutability. A variable set inside the script
gets `_` regardless of whether it is later frozen with `readonly`.

**This rule is not optional and has no exceptions.** A common mistake is omitting the `_` from path globals computed inside the script. These are script-internal — they must be `_TASK_NAME_ROOT` and similar. If the variable does not come from the environment, it gets the `_` prefix, full stop.

`MKS_ROOT`, `MKS_TMP`, and `MKS_VENDOR` follow the standard rule:
they arrive from the environment (set by sourcing `exports`) so they carry no `_` prefix.

#### Local variable prefix rule

Inside a function, the `_` prefix has **one purpose only**: preventing circular
reference collisions in `local -n` namerefs.

```
Is this local declared with `local -n`?
  Yes → prefix with `_`                 e.g. local -n _fn_result="${opts[result]}"
  No  → plain snake_case, no prefix     e.g. local output="", local missing=0
```

A common AI mistake is prefixing all function-local variables with `_`,
copying the pattern from namerefs. This is wrong. Only `local -n` namerefs
get the `_` prefix. Regular locals use plain Python-style `snake_case`.

### 4.4 Boolean Flags

Boolean flags have no value argument. Their presence sets the key to `1`.
Always provide both a short and long form:

```bash
-v | --verbose)  opts[verbose]=1;  shift 1 ;;
-n | --dry-run)  opts[dry_run]=1;  shift 1 ;;
-f | --force)    opts[force]=1;    shift 1 ;;
```

Test them with arithmetic context:

```bash
if (( opts[dry_run] )); then
  printf 'dry-run: would execute: %s\n' "${cmd}" >&2
fi
```

### 4.5 Output via Nameref (`--result`)

Prefer `--result <varname>` over printing to stdout when a function produces
a scalar value that a caller needs to capture. This avoids subshell overhead.

```bash
# Instead of:
result="$(my_function --input "foo")"

# Prefer:
local output=""
my_function --input "foo" --result output
```

For arrays, the same pattern works — the caller pre-declares the array:

```bash
local -a items=()
collect_items --source "/tmp/data" --result items
```

---

## 5. Modern Bash 5.x Idioms — Required

### 5.1 Timestamps — No `date` Subprocess

```bash
# Integer epoch
local ts="${EPOCHSECONDS}"

# Float epoch with microseconds
local ts_precise="${EPOCHREALTIME}"

# Formatted timestamp via printf's %()T — no subprocess
printf '%(%Y-%m-%dT%H:%M:%S)T\n' "${EPOCHSECONDS}"
```

Never call `$(date ...)` just to get a timestamp.

### 5.2 Namerefs (`local -n`) — No `eval`

```bash
local -n _target="${varname}"
_target="value"
```

`eval` is **banned** in this codebase. Any indirect variable manipulation
must use `local -n`. Prefix all nameref locals with `_` to avoid circular
reference collisions.

### 5.3 Scoped Shell Options (`local -`)

```bash
some_function() {
  local -   # all set changes revert when this function returns
  set -x    # trace on for this function only
  ...
}
```

Use this whenever temporarily enabling `set -x`, `set +e`, or `set -f`.

### 5.4 Associative Array Introspection (`${@K}`)

```bash
# Dump all key=value pairs of an associative array (Bash 5.1+)
printf 'opts: %s\n' "${opts[*]@K}"
```

Use this in verbose/debug output instead of writing a loop.

### 5.5 Safe Quoting (`${var@Q}`)

```bash
# Produce a shell-safe quoted version of a variable's value
printf 'Executing: %s\n' "${cmd@Q}"
```

### 5.6 Randomness — `$SRANDOM` Not `$RANDOM`

```bash
# 32-bit non-linear random — better entropy than $RANDOM
local rand="${SRANDOM}"
```

### 5.7 `mapfile` for Reading Into Arrays

```bash
local -a lines=()
# ALWAYS — null-delimited processing handles filenames with spaces/newlines safely
mapfile -d '' lines < <(find "${dir}" -type f -name '*.sh' -print0)
mapfile -t lines < "${some_file}"
```

Never loop with `while read` when `mapfile` covers the case.

### 5.8 Parameter Expansion Over Subprocesses

```bash
# Basename without subprocess
local fname="${path##*/}"

# Dirname without subprocess
local dir="${path%/*}"

# Extension
local ext="${fname##*.}"

# Strip extension
local base="${fname%.*}"

# Lowercase (Bash 4+)
local lower="${var,,}"

# Uppercase (Bash 4+)
local upper="${var^^}"

# String length
local len="${#var}"
```

### 5.9 Arithmetic

```bash
# Always use (( )) for arithmetic — never expr, let, or $[ ]
(( count++ ))
(( total = a + b ))
local -i retries=0
(( retries < MAX_RETRIES )) || return 2
```

### 5.10 In-Process Output Capture: `${ ; }` (Bash 5.3+)

Bash 5.3 introduces **`${ ; }`** — command group substitution. This is one
of the most significant additions in Bash 5.3. It captures the output of
commands **without forking a subshell**, running everything in the current
shell process.

```bash
# Bash 5.3+ — no fork, current shell, output captured
local result="${ my_bash_function --input "foo"; }"

# Old way — forks a subshell, measurable overhead
local result="$(my_bash_function --input "foo")"
```

#### `${ ; }` vs `$( )` vs `{ }` — the full picture

| Construct | Captures output | Forks? | Variables persist? |
|---|---|---|---|
| `$( )` | Yes | Yes — subshell | No |
| `{ }` | No | No — current shell | Yes |
| `${ ; }` | Yes | No — current shell | Yes |

`${ ; }` combines the output capture of `$()` with the in-process execution
of `{ }`. It is strictly better than `$()` for Bash functions and builtins.

#### When to use `${ ; }`

Use `${ ; }` for **all output capture** — Bash functions, builtins, and
external binaries alike. It is strictly never worse than `$( )` and is
always at least as fast:

```bash
# Bash function — no fork at all
local username="${ get_username --user-id "${uid}"; }"

# Builtin — no fork at all
local upper="${ printf '%s' "${var^^}"; }"

# External binary — saves one Bash subshell fork
# (the binary itself still forks at the OS level, but ${ ; }
#  eliminates the extra Bash subshell wrapper $() would add)
local digest="${ sha256sum "${file}" | awk '{print $1}'; }"
local inode="${ stat -c '%i' "${file}"; }"
local response="${ curl -s "https://api.example.com/data"; }"
```

#### The fork cost — precisely stated

| Construct | Bash subshell fork | Binary exec fork | Total forks |
|---|---|---|---|
| `$( my_bash_func )` | Yes | No | 1 |
| `${ my_bash_func; }` | No | No | 0 |
| `$( curl ... )` | Yes | Yes | 2 |
| `${ curl ...; }` | No | Yes | 1 |

`${ ; }` always eliminates the Bash subshell layer. For external binaries
the OS-level exec fork is unavoidable — but `${ ; }` still removes one
of the two forks that `$()` would incur.

#### The decision rule

```
Do I need to capture output?
  Yes → ${ ; }   always — for functions, builtins, and external binaries

The only exception: when you need subshell ISOLATION (scoped cd,
environment change, or set options) AND output capture simultaneously.
That combination is rare — and should be noted in a comment when used.
```

#### When to still use `$( )` — the one exception

```bash
# Isolated directory change with captured output — subshell required
local manifest
manifest="$( cd "${build_dir}" && make --dry-run )"
```

This is the only case where `$()` is the right tool.

#### In loops — the difference is dramatic

```bash
# Wrong — forks on every iteration for a pure Bash operation
for item in "${items[@]}"; do
  local processed
  processed="$(transform_item --input "${item}")"  # fork × N
done

# Correct — zero forks
for item in "${items[@]}"; do
  local processed
  processed="${ transform_item --input "${item}"; }"  # in-process × N
done
```

#### The `grep` + `pipefail` Crash inside `${ ; }`

> **CRITICAL:** Any command that fails inside `${ ; }` will crash the entire script under `inherit_errexit` and `set -o pipefail`.

A common failure: pipelines ending in `grep`. If no matches are found, `grep` exits `1`. Under `inherit_errexit` and `set -o pipefail`, this instantly crashes the script—even inside `${ ; }`. You must suppress the failure:

```bash
# Option A: Output a default value on failure
local changes="${ git status --porcelain | grep '^ M' || printf 'none'; }"

# Option B: Swallow the error and evaluate the blank variable later
local changes="${ git status --porcelain | grep '^ M' || true; }"
```

This applies to any command that may return non-zero: `grep`, `find`, `diff`, `curl`, etc. Always handle the expected failure cases with `|| true` or `|| printf 'default'`.

### 5.11 Subshell Usage — Explicit Rules

A subshell `$()` or `( )` forks a child process. Use them only when
genuinely required. Exhaust in-process options first.

#### Never use a subshell for:

| Task | Wrong | Right |
|---|---|---|
| Basename | `$(basename "$path")` | `"${path##*/}"` |
| Dirname | `$(dirname "$path")` | `"${path%/*}"` |
| Lowercase | `$(echo "$v" \| tr ...)` | `"${v,,}"` |
| Uppercase | `$(echo "$v" \| tr ...)` | `"${v^^}"` |
| String length | `$(echo -n "$v" \| wc -c)` | `"${#v}"` |
| Substring | `$(echo "$v" \| cut -c1-8)` | `"${v:0:8}"` |
| Epoch timestamp | `$(date +%s)` | `"${EPOCHSECONDS}"` |
| Formatted timestamp | `$(date '+%Y-%m-%d')` | `printf -v ts '%(%Y-%m-%d)T' "${EPOCHSECONDS}"` |
| Bash function output | `$(my_function)` | `${ my_function; }` |
| Arithmetic | `result=$(( a + b ))` | `(( result = a + b ))` |
| Default value | `$([ -z "$v" ] && echo "x")` | `"${v:-x}"` |

#### Use `( )` subshell only for:

1. **Isolated directory change** — `cd` must not affect the caller:
   ```bash
   ( cd "${build_dir}" && make install )
   ```

2. **Isolated environment change** — when `local -` is insufficient:
   ```bash
   ( export OVERRIDE=1; source "${plugin}"; run_suite )
   ```

3. **Isolated `set` option change** across a sourced file boundary:
   ```bash
   ( set +e; risky_operation; )
   ```

4. **Background jobs** — forking is the entire point; `${ ; }` is
   synchronous and in-process and cannot background work:

   ```bash
   # Background an external command — straightforward
   curl -s "https://api.example.com" > "${outfile}" &
   local pid=$!

   # Background a Bash function — subshell required
   process_batch --input "${file}" &
   local pid=$!
   wait "${pid}"
   ```

   When a background job needs to return a value, avoid `$()&` —
   it is awkward and error-prone. Instead redirect to a temp file,
   then read it back with `${ ; }` after `wait`:

   ```bash
   # Correct pattern for background job with result collection
   local tmpout
   tmpout="${ mktemp -t "${FUNCNAME[0]}.XXXXXX"; }"
   trap 'rm -f "${tmpout}"' RETURN

   long_running_function --input "${file}" > "${tmpout}" &
   local pid=$!

   # ... do other work concurrently ...

   wait "${pid}"
   local result="${ cat "${tmpout}"; }"
   ```

#### Use `< <( )` process substitution for:

5. **Loading arrays from command output** — the single most important
   subshell rule in this codebase:

   ```bash
   # ALWAYS — mapfile runs in current shell, array persists
   mapfile -t files < <(find "${dir}" -type f -name '*.sh')

   # NEVER — mapfile runs in a subshell, array is lost immediately
   find "${dir}" -type f -name '*.sh' | mapfile -t files
   ```

6. **Diff / comparison without temp files**:
   ```bash
   diff <(sort "${file_a}") <(sort "${file_b}")
   ```

#### Use `$( )` only for:

7. **Subshell isolation WITH output capture** — the one case where
   `${ ; }` cannot substitute:
   ```bash
   # Need cd isolation AND the output — subshell required, note it
   local manifest
   manifest="$( cd "${build_dir}" && make --dry-run )"  # isolation required
   ```
   Always add a comment explaining why `$()` was chosen over `${ ; }`.

---

## 6. Destructive Operations Safety — **CRITICAL**

> **THIS RULE EXISTS TO PREVENT CATASTROPHIC DATA LOSS.**
> Violations will be rejected in code review without exception.

### 6.1 `rm` Requires Null Guards

Any `rm` invocation using a variable **must** use a null guard to prevent
accidental deletion if the variable is empty or unset.

```bash
# FORBIDDEN — if ${path} is empty, this becomes 'rm -f ""'
rm -f "${path}"

# REQUIRED — if ${path} is empty, this becomes 'rm -f "_NULL_'" (safe fail)
rm -f "${path:-_NULL_}"
```

The null guard `${var:-_NULL_}` ensures an empty/unset variable expands to
a literal string `_NULL_` which will never exist, causing `rm` to fail safely
rather than operating on unexpected input.

### 6.2 `rm -rf` Requires Additional Validation

The `-rf` flag (recursive, force) is **exceptionally dangerous**. A null guard
alone is **insufficient** — you must also validate that the path looks safe:

```bash
# FORBIDDEN — no validation, could be '/' or '/etc'
rm -rf "${target_dir:-_NULL_}"

# REQUIRED — validate before destructive operation
if [[ -z "${target_dir:-}" ]]; then
  printf 'FATAL: target_dir is empty\n' >&2
  return 1
fi

# Additional safety checks
case "${target_dir}" in
  /|/etc|/home|/root|/usr|/var)
    printf 'FATAL: refusing to delete system path: %s\n' "${target_dir}" >&2
    return 1
    ;;
esac

# Only now is it safe to delete
rm -rf "${target_dir:-_NULL_}"
```

### 6.3 Standard Library: `lib/std/rmrf.sh`

The project provides a library for safe deletion with built-in guards:

```bash
source "${MKS_ROOT}/lib/std/rmrf.sh"

# Safe single file deletion (non-recursive)
lib::std::rmrf::file "${path}"
lib::std::rmrf::file --verbose "${path}"

# Safe recursive directory deletion (rm -rf with validation)
lib::std::rmrf::dir "${directory}"
lib::std::rmrf::dir --verbose "${directory}"
```

**Key features:**
- Null guard built in — empty/unset vars return success
- System path rejection — refuses `/`, `/etc`, `/usr`, `/home`, etc.
- Parent directory warnings — logs if path contains `..`
- Structured logging via `lib::std::logger`

**When to use:**
- Deleting paths from user input or external sources
- Deleting paths with variable construction
- Any `rm -rf` on a directory you didn't create

**When null guard alone is sufficient:**
- Cleanup traps for temp files you created yourself
- Paths within your own `${MKS_TMP}` subdirectory

### 6.4 TRAP Cleanup Pattern

When cleaning up temp files in traps, the null guard is still required:

```bash
cleanup() {
  local exit_code=$?
  rm -f "${TMPFILE:-_NULL_}"       # Required null guard
  rm -rf "${TMPDIR:-_NULL_}"       # Required null guard for -rf
  exit "${exit_code}"
}
trap cleanup EXIT
```

---

## 7. Error Handling

### 6.1 Trap Template

Every executable script must register cleanup and error traps:

```bash
# -- Trap handlers
_cleanup() {
  local exit_code=$?
  # Remove temp files, release locks, etc.
  rm -f "${_TMPFILE:-}"
  exit "${exit_code}"
}

_on_error() {
  printf 'ERROR: %s failed at line %d (exit %d)\n' \
    "${BASH_SOURCE[0]}" "$1" "$?" >&2
}

# Force signals to properly invoke the EXIT trap
trap 'exit 130' INT
trap 'exit 143' TERM
trap '_cleanup'  EXIT
trap '_on_error "${LINENO}"' ERR
```

### 6.2 Temporary Files

```bash
local tmpfile
tmpfile="${ mktemp -t "${FUNCNAME[0]}.XXXXXX"; }"
# Register cleanup immediately after creation
trap 'rm -f "${tmpfile}"' RETURN
```

Use `RETURN` trap inside functions to clean up function-scoped resources.

### 6.3 Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Usage / argument error |
| 2 | Runtime / logic error |
| 3 | Dependency / environment error |
| 4 | I/O error |
| 5 | Permission error |

Document the exit codes a function can return in its header comment.

### 6.4 Exit Codes in Conditionals

Commands that return non-zero exit codes will crash the script under `set -e` and `inherit_errexit`. This is especially problematic in conditionals where you want to test whether a command succeeded.

```bash
# WRONG — grep returns 1 when no matches, crashing the script
if grep pattern file; then
  echo "found"
fi

# RIGHT — suppress the error, test the result
if [[ -n "${ grep pattern file || true; }" ]]; then
  echo "found"
fi

# ALSO RIGHT — use || : (no-op) to suppress the error
if grep pattern file 2>/dev/null || :; then
  echo "found"
fi
```

For tests where you explicitly need the exit code, disable `set -e` temporarily:

```bash
# Disable strict mode for this command only
if ! grep pattern file 2>/dev/null; then
  echo "not found"
fi
```

Common commands that return non-zero on expected conditions:
- `grep` — returns 1 when no matches found
- `find` — returns 1 when no files match
- `diff` — returns 1 when files differ
- `curl` — returns non-zero on HTTP errors (with `--fail`)
- `test`/`[` — returns 1 when condition is false

---

## 8. Logging Convention

All scripts source `lib/std/logger.sh` which provides:

```bash
# lib::std::logger -l <debug|info|warn|error> -m <text> [--verbose]
lib::std::logger() {
  local -A opts=([level]="info" [message]="" [verbose]=0)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -l | --level)   opts[level]="$2";   shift 2 ;;
      -m | --message) opts[message]="$2"; shift 2 ;;
      -v | --verbose) opts[verbose]=1;    shift 1 ;;
      *) return 1 ;;
    esac
  done

  # EPOCHSECONDS — no subprocess
  local ts
  printf -v ts '%(%Y-%m-%dT%H:%M:%S)T' "${EPOCHSECONDS}"

  local level_upper="${opts[level]^^}"

  case "${opts[level]}" in
    info)  ;;
    warn)  ;;
    error) ;;
  esac

  printf '[%s] %-5s %s\n' "${ts}" "${level_upper}" "${opts[message]}" >&2
}
```

---

## 9. Bash Library Structure (.sh)

Every sourced library file (ending in `.sh`) must follow this exact header layout:

```bash
# shellcheck shell=bash
# Guard: prevent double-sourcing
[[ -n "${_LIB_FILENAME_LOADED:-}" ]] && return 0
readonly _LIB_FILENAME_LOADED=1

[[ -n "${MKS_ROOT:-}" ]] || { echo 'Fatal: MKS_ROOT is not set!' >&2; exit 3; }

# <path> -- <description>
```

Replace `FILENAME` with the uppercased filename stem (e.g., `_LIB_COMMON_LOADED`). Libraries inherit strict mode from the entry-point script that sources them.

### Library dependencies

Libraries must declare their own dependencies immediately after their guard —
not rely on callers to have pre-sourced them. The guards in each file make
transitive sourcing free: whichever file is sourced first wins; every subsequent
`source` of the same file is a no-op.

> **Note:** The diagram below illustrates the dependency pattern, not an
> exhaustive catalog of all libraries.

```
logger.sh   ← baseline; no further deps
secrets.sh  ← sources logger.sh (+ others as needed)
```

If a library needs structured logging, it sources `logger.sh` after its guard.
Callers that also source `logger.sh` pay no extra cost — the guard absorbs the
duplicate. Callers never need to know a library's transitive dependencies.

---

## 10. Bash Executable Structure

All entry-point scripts (excluding POSIX `#!/bin/sh` scripts) must follow this exact header layout:

```bash
#!/usr/bin/env mks-bash

set -euo pipefail
shopt -s inherit_errexit
IFS=$'\n\t'

[[ -n "${MKS_ROOT:-}" ]] || { echo 'Fatal: MKS_ROOT is not set!' >&2; exit 3; }

# Usage:
#   script-name [options]
#
# Options:
#   --input  <path>   Input file or directory (required)
#   --output <path>   Output destination (required)
#   --dry-run         Print actions without executing
#   --verbose         Enable verbose output
#   --help            Show this help and exit
# --

# -- Resolve script directory (symlink-safe)
_SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"  # isolation required
readonly _SCRIPT_DIR

# -- Source libraries
source "${_SCRIPT_DIR}/../lib/std/logger.sh"

# -- Constants
readonly MAX_RETRIES=3
readonly _SELF="${0##*/}"

# -- Traps
_cleanup() { :; }
_on_error() {
  printf 'ERROR: %s failed at line %d (exit %d)\n' \
    "${BASH_SOURCE[0]}" "$1" "$?" >&2
}
trap '_cleanup' EXIT
trap '_on_error "${LINENO}"' ERR

# -- usage: print usage to stderr and exit 1
usage() {
  grep '^#' "${BASH_SOURCE[0]}" | grep -v '^#!' | sed 's/^# \{0,1\}//'
  exit 1
}

# -- main: entry point
main() {
  local -A opts=(
    [input]=""
    [output]=""
    [dry_run]=0
    [verbose]=0
  )

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input)    opts[input]="$2";   shift 2 ;;
      --output)   opts[output]="$2";  shift 2 ;;
      --dry-run)  opts[dry_run]=1;    shift 1 ;;
      --verbose)  opts[verbose]=1;    shift 1 ;;
      --help|-h)  usage ;;
      --)         shift; break ;;
      --*)
        printf '%s: unknown option: %s\n' "${_SELF}" "$1" >&2
        usage
        ;;
    esac
  done

  # validate
  [[ -n "${opts[input]}"  ]] || { printf '%s: --input is required\n'  "${_SELF}" >&2; exit 1; }
  [[ -n "${opts[output]}" ]] || { printf '%s: --output is required\n' "${_SELF}" >&2; exit 1; }

  lib::std::logger -l info -m "Starting ${_SELF}"
  (( opts[verbose] )) && printf 'opts: %s\n' "${opts[*]@K}" >&2

  # ... work ...
}

# -- Only run main when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

---

## 11. Testing with bashunit

This project uses [bashunit](https://bashunit.typeddevs.com) as its test framework.
bashunit is installed as a single executable at `lib/bashunit` — it is committed
to the repo and requires no external install step.

### Installation

```bash
curl -s https://bashunit.typeddevs.com/install.sh | bash
# Creates lib/bashunit
```

### Running Tests

```bash
# All tests
./lib/bashunit ./tests

# Unit tests only
./lib/bashunit ./tests/unit

# Single file
./lib/bashunit ./tests/unit/common_test.sh
```

### Test File Conventions

- Test files end in `_test.sh` (e.g. `logger_test.sh` for `lib/std/logger.sh`)
- Test functions are prefixed with `test_` in `snake_case`
- One test file per lib file, mirroring the `lib/` structure under `tests/unit/`
- Integration tests live in `tests/integration/` and test `bin/` executables end-to-end

### Test File Structure

Every test file follows this layout:

```bash
#!/usr/bin/env mks-bash
# tests/unit/logger_test.sh — tests for lib/std/logger.sh

# Load the library under test
source "${MKS_ROOT}/lib/std/logger.sh"

# ---------------------------------------------------------------------------
# Lifecycle hooks
# ---------------------------------------------------------------------------

# Runs once before all tests in this file
set_up_before_script() {
  # Create shared resources (temp dirs, test fixtures, etc.)
  export TEST_TMPDIR
  TEST_TMPDIR="${ mktemp -d -t bashunit.XXXXXX; }"
}

# Runs once after all tests in this file
tear_down_after_script() {
  rm -rf "${TEST_TMPDIR}"
}

# Runs before each individual test
set_up() {
  # Reset any state that individual tests modify
  :
}

# Runs after each individual test
tear_down() {
  :
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_ensure_dir_creates_directory() {
  local dir="${TEST_TMPDIR}/new_dir"

  ensure_dir --path "${dir}"

  assert_directory_exists "${dir}"
}

test_ensure_dir_is_idempotent() {
  local dir="${TEST_TMPDIR}/existing"
  mkdir -p "${dir}"

  ensure_dir --path "${dir}"

  assert_successful_code
}

test_log_writes_to_stderr() {
  local output
  output="${ lib::std::logger -l error -m "test error" 2>&1 1>/dev/null; }"

  assert_contains "ERROR" "${output}"
  assert_contains "test error" "${output}"
}
```

### Key Assertions

bashunit provides a rich assertion library. The most commonly used:

**Equality**
```bash
assert_same "expected" "actual"        # exact match including special chars
assert_equals "expected" "actual"      # match ignoring ANSI/whitespace
assert_not_same "expected" "actual"
```

**Strings**
```bash
assert_contains "needle" "haystack"
assert_not_contains "needle" "haystack"
assert_matches "^pattern$" "value"     # regex match
assert_string_starts_with "prefix" "value"
assert_string_ends_with "suffix" "value"
assert_empty "${var}"
assert_not_empty "${var}"
```

**Exit Codes**
```bash
# After running a command, check its exit code
my_function --input "foo"
assert_successful_code               # expects 0
assert_unsuccessful_code             # expects non-zero
assert_exit_code "2"                 # expects specific code

# Or run and check in one step
assert_exec "my_function --input foo" --exit 0 --stdout "expected output"
assert_exec "my_function --bad"      --exit 1 --stderr "required option"
```

**Files and Directories**
```bash
assert_file_exists "${path}"
assert_file_contains "${path}" "search string"
assert_files_equals "${expected_file}" "${actual_file}"
assert_directory_exists "${dir}"
assert_is_directory_empty "${dir}"
assert_is_directory_writable "${dir}"
```

**Arrays**
```bash
assert_array_contains "element" "${arr[@]}"
assert_array_not_contains "element" "${arr[@]}"
```

**Numerics**
```bash
assert_greater_than "1" "999"
assert_less_than "999" "1"
assert_greater_or_equal_than "1" "999"
```

**JSON** (requires `jq`)
```bash
assert_json_key_exists ".name" "${json}"
assert_json_contains ".name" "bashunit" "${json}"
assert_json_equals '{"b":2,"a":1}' '{"a":1,"b":2}'
```

**Performance**
```bash
assert_duration "my_function --input foo" 500   # must complete within 500ms
```

**Explicit failure**
```bash
bashunit::fail "descriptive failure message"
```

### Testing Functions That Use `--result` Namerefs

Functions that return values via `local -n` namerefs need a local variable
declared in the test before calling:

```bash
test_get_username_returns_expected_value() {
  local result=""

  get_username --user-id "42" --result result

  assert_same "user_42" "${result}"
}
```

### Testing Functions That Write to stderr

Capture stderr separately using `2>&1 1>/dev/null`:

```bash
test_missing_required_option_prints_error() {
  local err
  err="${ my_function 2>&1 1>/dev/null; }"

  assert_contains "--required-option" "${err}"
  assert_contains "required option missing" "${err}"
}
```

### Fixtures

Place static input files in `tests/fixtures/input/` and expected output
files in `tests/fixtures/expected/`. Reference them in tests via:

```bash
readonly FIXTURES_DIR="${0%/*}/../fixtures"

test_process_produces_expected_output() {
  local actual
  actual="${ process_file --input "${FIXTURES_DIR}/input/sample.txt"; }"

  assert_files_equals "${FIXTURES_DIR}/expected/sample.txt" <(printf '%s' "${actual}")
}
```

---

## 12. Linter Configuration (`.shellcheckrc`)

```ini
enable=all
severity=info
```

`severity=info` reports errors, warnings, and info-level suggestions, but skips
pure style nits. The `shell=` directive is intentionally omitted — each file's
shebang (or inline `# shellcheck shell=bash` directive for sourced libraries)
determines the target shell, keeping POSIX `#!/bin/sh` scripts linted as sh and
Bash scripts linted as Bash.

Run the linter from the project root:

```bash
vendor/bin/dev/shellcheck bin/* lib/std/*.sh bootstrap.d/lib/*.sh bootstrap.d/tasks/*/run
```

All scripts must pass with zero findings before commit.
Use inline `# shellcheck disable=SCxxxx` only with a comment explaining why.

---

## 13. Constructs Reference

### Use These

| Instead of | Use |
|---|---|
| `` `cmd` `` | `${ cmd; }` or `$(cmd)` |
| `[ ]` | `[[ ]]` |
| `expr`, `let`, `$[ ]` | `$(( ))` or `(( ))` |
| `echo` with variables | `printf '%s\n' "${var}"` |
| `$(date +%s)` | `${EPOCHSECONDS}` |
| `$(date +%s%N)` | `${EPOCHREALTIME}` |
| `eval` | `local -n` nameref |
| `$RANDOM` | `$SRANDOM` |
| `seq 1 10` | `{1..10}` |
| `basename "$path"` | `"${path##*/}"` |
| `dirname "$path"` | `"${path%/*}"` |
| `tr '[:upper:]' '[:lower:]'` | `"${var,,}"` |
| `while read` loop | `mapfile -t arr < <(...)` |
| Positional function args | `--long-form --switches` |
| `$(my_bash_function)` | `${ my_bash_function; }` |
| `$(curl ...)` | `${ curl ...; }` |
| `$(any_output_capture)` | `${ any_output_capture; }` |

### Never Use These

- `eval` — use `local -n` namerefs
- Backtick command substitution
- `[ ]` single-bracket tests
- Positional-only function parameters (without `--` flags)
- `echo` for anything with escape sequences or variables
- Hardcoded `/bin/bash` shebang (use `/usr/bin/env mks-bash`)
- `source` without verifying the file exists first (exception: library paths
  that are deterministic from `_SCRIPT_DIR` — these are guaranteed to exist)
- Unquoted variable expansions outside `(( ))`
- `$()` for output capture — use `${ ; }` instead in all cases except subshell isolation
- Piping into `mapfile` — use `mapfile -t arr < <(cmd)` instead

---

## 14. Quick Reference: Writing a New Function

1. Write the header comment block (description, usage, options, returns, example)
2. `local -` as first line (scoped set options)
3. Declare `local -A opts=(...)` with all defaults
4. Write the `while [[ $# -gt 0 ]]; do case "$1" in` parser — every option gets both a short (`-x`) and long (`--long`) form; pair the catch-all as `--* | -*)`
5. Validate required opts, print error + `return 1` for each missing one
6. If `--verbose` is in opts, dump `"${opts[*]@K}"` to stderr
7. Do the work using only `local` variables
8. Capture Bash function output with `${ ; }` not `$()`
9. If returning a value, use `local -n _result "${opts[result]}"` pattern
10. Return explicit exit code

---

## 15. Common AI Mistakes — Do Not Generate These

| Wrong | Right | Rule |
|---|---|---|
| `echo "${var}"` | `printf '%s\n' "${var}"` | Section 3 |
| `result="$(my_func)"` | `result="${ my_func; }"` | Section 5.10 |
| `$(dirname "$0")` | `"${0%/*}"` | Section 5.8 |
| `$(basename "$path")` | `"${path##*/}"` | Section 5.8 |
| `$(date +%s)` | `"${EPOCHSECONDS}"` | Section 5.1 |
| `PROGRAM_NAME=...` (script-internal) | `_SELF=...` | Section 4.3 |
| Missing `local -` as first function line | Always `local -` first | Section 5.3 |
| `$()` without `# isolation required` | Always comment why `$()` was chosen | Section 5.10 |
| `function my_func() {` | `my_func() {` | Section 3 |
| `--long-only)` without a short form | `-x \| --long-only)` for every option | Section 4.2 |
| `while read -r line; do` | `mapfile -t arr < <(...)` | Section 5.7 |
| `[[ $var == "x" ]]` | `[[ "${var}" == "x" ]]` | Section 3 |
| `eval "$cmd"` | `local -n _ref="${name}"` | Section 5.2 |
| `$RANDOM` | `$SRANDOM` | Section 5.6 |
| `set -euo pipefail` in lib/.sh | Omit — inherited from entry point | Section 2 |
| `readonly ROOT_DIR=...` (script-internal) | `readonly _VENDOR_BIN=...` | Section 4.3 |
| `local _var="..."` (non-nameref local) | `local var="..."` — `_` prefix is for `local -n` only | Section 4.3 |
| `exit 1` for missing dependency | `exit 3` | Section 6.3 |
| `cmd \| grep 'x'` without `\|\| true` | `cmd \| grep 'x' \|\| true` | Section 5.10 |
| `age --encrypt` | `age --encrypt --armor` | docs/age.md |

---

## 15. Google Shell Style Guide — Explicit Overrides

This project follows Google's Shell Style Guide with these deliberate overrides:

| Google recommends | This project requires | Reason |
|---|---|---|
| `#!/bin/bash` | `#!/usr/bin/env mks-bash` | Asserts vendor environment is sourced; `mks-bash` only exists in `vendor/bin/` |
| `function` keyword optional | Never use `function` keyword | Consistency — always `name() {` |
| `readarray` or `mapfile` | Always `mapfile` | Standardize on one name |
| `main "$@"` as last line | `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi` | Allows scripts to be sourced for testing |
| No `IFS` recommendation | `IFS=$'\n\t'` always | Defensive word-splitting |
| No subshell guidance | `${ ; }` over `$()` always | Bash 5.3+ in-process capture |
| `::` namespacing for packages | Used in `lib/std/` only | `lib::std::<function_name>` — outside `lib/std/` functions remain un-namespaced |
