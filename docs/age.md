# Secrets Management with `age`

This document defines how the project handles encrypted secrets using
[`age`](https://age-encryption.org/). Follow this pattern exactly — it is
the only approved way to load secrets into scripts.

---

## Overview

Secrets live in `vars/secrets.env.sec` (gitignored) as a plain `KEY="value"`
env file. The encrypted counterpart, `vars/secrets.env.sec.age`, is committed
to the repository and decrypted at runtime using an SSH identity.

Encryption is a one-time developer operation. Decryption happens in scripts.

---

## File Conventions

| File | Committed | Description |
|---|---|---|
| `vars/secrets.env.sec` | **No** — gitignored | Plaintext env file; `KEY="value"` per line |
| `vars/secrets.env.sec.age` | **Yes** | Encrypted with the project SSH public key |

The `.gitignore` must contain `*.env.sec` to prevent the plaintext from
being committed. This pattern is intentionally narrow — it ignores only
`.env.sec` files, leaving plain `.env` config files unaffected.

### ASCII Armored (PEM) Format

We always use the `--armor` (or `-a`) flag when encrypting. This ensures the
output is in a PEM-encoded (ASCII) format rather than raw binary. ASCII-armored
files are:
- **Git-friendly**: Diffing and merging are safer for text than binary.
- **Inspectable**: Can be viewed with `cat` or `grep` without breaking terminal.
- **Portable**: Less prone to corruption when copied as text or via clipboard.

---

## Key Pair

`age` accepts SSH RSA and Ed25519 public keys directly as recipients —
no separate `age` key pair is required.

### Canonical Key Paths

| File | Purpose | Committed |
|---|---|---|
| `${MKS_AGE_PKEY:-${MKS_TMP}/age/id_rsa}` | Private key (unencrypted) — used to **decrypt** | **No** — gitignored |
| `${MKS_AGE_PKEY:-${MKS_TMP}/age/id_rsa}.pub` | Public key — used to **encrypt** | Optional — safe to commit |

`tmp/age/` maps to `${MKS_TMP}/age/`, which is gitignored and cleaned by
`make clean`.

### How the Private Key Gets There

The private key is **never generated inside this repo**. It must be a **standard, unencrypted SSH key** (no passphrase) and is placed at `${MKS_AGE_PKEY:-${MKS_TMP}/age/id_rsa}` by one of these means:

| Context | How |
|---|---|
| CI/CD pipeline | Secret injected by the runner and written to `${MKS_TMP}/age/id_rsa` |
| Local development | Symlink or copy placed manually by the developer |
| Automated runner | Written to `MKS_TMP` at startup, cleaned up on exit |

### Deriving the Public Key

The public key is derived automatically from the private key by `lib::std::secrets::encrypt` when needed. If you need the public key for reference (e.g., to verify recipients), you can derive it manually with:

```bash
ssh-keygen -y -f "${MKS_TMP}/age/id_rsa" > "${MKS_TMP}/age/id_rsa.pub"
cat "${MKS_TMP}/age/id_rsa.pub"
```

### Identity Resolution at Runtime

The private key path is passed via `MKS_AGE_PKEY`. If unset, scripts default
to `${MKS_TMP}/age/id_rsa`. The canonical explicit value — set by the pipeline
runner, wrapper script, or local dev environment — is:

```bash
export MKS_AGE_PKEY="${MKS_TMP}/age/id_rsa"
```

> [!IMPORTANT]
> The private key **must not** have a passphrase. We use unencrypted keys to allow our scripts to decrypt secrets silently and non-interactively. Restricted file permissions (`chmod 600`) provide the necessary security.

No script may hardcode this path. Always resolve it via:

```bash
: "${MKS_AGE_PKEY:=${MKS_TMP}/age/id_rsa}"
```

This sets `MKS_AGE_PKEY` to the default in-process if the caller did not
export it — no subprocess, no temp variable.

---


### Standard Library Abstraction

The project provides a library `lib/std/secrets.sh` that provides a stable interface for secrets management, abstracting the underlying implementation (currently `age`).

```bash
source "${MKS_ROOT}/lib/std/secrets.sh"

# Encrypt (with idempotency and public key derivation)
lib::std::secrets::encrypt --source vars/secrets.env.sec --target vars/secrets.env.sec.age

# Decrypt to stdout
lib::std::secrets::decrypt --source vars/secrets.env.sec.age

# Decrypt to variable
local secrets=""
lib::std::secrets::decrypt --source vars/secrets.env.sec.age --result secrets
```

---

## Encrypting a Secrets File

> **Developer operation** — run once when `secrets.env.sec` changes.

The preferred method is using the `lib::std::secrets` library. It automatically handles public key derivation, sidecar hashing for idempotency, and output formatting.

```bash
lib::std::secrets::encrypt \
  --source bootstrap.d/vars/secrets.env.sec \
  --target bootstrap.d/vars/secrets.env.sec.age
```

### Idempotency Sidecar

This command creates or updates a sidecar file with the `.env.sha.age` extension (e.g., `vars/secrets.env.sha.age`). This file is committed to the repository and contains:
`hash(plaintext_source) hash(encrypted_target)`

The library uses this to skip redundant encryption if neither the source nor the target has changed.

---

## Decrypting and Loading Secrets

Use `lib::std::secrets::decrypt` to pipe the decrypted output directly into `source`. The plaintext is never written to disk.

```bash
# Decrypt and load all KEY="value" pairs into the current shell.
source <(lib::std::secrets::decrypt --source bootstrap.d/vars/secrets.env.sec.age)
```

To decrypt to a file during development (e.g., to edit the secrets), use:

```bash
lib::std::secrets::decrypt \
  --source bootstrap.d/vars/secrets.env.sec.age \
  --target bootstrap.d/vars/secrets.env.sec
```

**Why `source <(...)` and not a temp file?**

- `<(...)` is a kernel-level named pipe (fd) — no file is written.
- `source` runs the output in the **current shell**, so exported variables
  persist in the caller's environment.
- A temp-file approach always carries a window where plaintext exists on disk,
  even if cleaned up with a `RETURN` trap. Process substitution eliminates
  that window entirely.

---

## Usage in Scripts

Place the decrypt-and-source call near the top of any script that needs
secrets, after strict mode and after sourcing the standard libraries:

```bash
#!/usr/bin/env mks-bash
set -euo pipefail
shopt -s inherit_errexit
IFS=$'\n\t'

source "${MKS_ROOT}/lib/std/logger.sh"

# -- Load secrets (plaintext never written to disk)
# MKS_AGE_PKEY defaults to ${MKS_TMP}/age/id_rsa if the caller did not set it.
readonly _SECRETS="${BSS_ROOT}/vars/secrets.env.sec.age"

: "${MKS_AGE_PKEY:=${MKS_TMP}/age/id_rsa}"

[[ -f "${MKS_AGE_PKEY}" ]] || { printf 'FATAL: identity file not found: %s\n' "${MKS_AGE_PKEY}" >&2; exit 3; }
[[ -f "${_SECRETS}"     ]] || { printf 'FATAL: secrets file not found: %s\n' "${_SECRETS}"      >&2; exit 3; }

source <(age --decrypt --identity "${MKS_AGE_PKEY}" "${_SECRETS}")
```

After this, all variables from `secrets.env.sec` are available directly:

```bash
printf 'token: %s\n' "${BSS_GLB_APITOKEN}"
```

---

## Verifying the Encrypted File

Use `age-inspect` (in `vendor/bin/dev/`) to confirm the file is valid and
shows the expected recipient without decrypting its contents:

```bash
vendor/bin/dev/age-inspect vars/secrets.env.sec.age
```

---

## Security Notes

- **Never `echo` or `printf` secret values in scripts.** Log only that
  secrets were loaded, not their contents.
- **Never pass secrets as positional arguments** to subprocesses — they
  appear in `ps` output. Use environment variables or stdin instead.
- The `--identity` flag accepts multiple files: `-i key1 -i key2`. This is
  useful when rotating keys — decrypt succeeds as long as any one identity
  matches a recipient in the file.
- To re-encrypt for a new or additional recipient:

  ```bash
  # Add a second recipient (e.g. a team member's SSH key).
  # --recipient values are public keys — safe to inline or store in a file.
  age --encrypt --armor \
    --recipient "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p" \
    --recipient "ssh-ed25519 AAAA... colleague@host" \
    --output vars/secrets.env.sec.age \
    vars/secrets.env.sec
  ```

---

## Secrets File Format

`vars/secrets.env.sec` is a plain Bash env file. Each line is a valid shell
assignment that `source` can execute:

```bash
BSS_GLB_NTP_PASSWORD="ntp_password"
BSS_GLB_INC_PASSPHRASE="include_passphrase"
BSS_GLB_APITOKEN="api_token"
```

Rules:
- One variable per line
- `KEY="value"` — always double-quoted values
- Variable names follow the project prefix convention (`BSS_GLB_` for
  bootstrap global secrets, `BSS_<TASK>_` for task-scoped secrets)
- Empty lines and `#` comment lines are ignored by `source`
- No `export` keyword needed — callers export after loading if required